# src/resolver.mojo
# Semver dependency resolver.
# Collects version constraints from the manifest and from each chosen
# package's registry entry ("dep_constraints"), and picks the newest
# versions satisfying all of them, backtracking to older versions when a
# choice leads to a conflict.

from std.collections import Dict
from http_client import HttpClient
from manifest import Manifest, Dependency
from lockfile import LockFile, LockedPackage, lockfile_find
from registry import PackageMeta, PackageVersion, registry_fetch_package, registry_fetch_all
from fs import fs_home_dir
from validate import validate_name, trim_spaces


# ─── Semver parsing ────────────────────────────────────────────────────────────

struct SemVer(Copyable, Movable):
    var major: Int
    var minor: Int
    var patch: Int

    def __init__(out self, major: Int, minor: Int, patch: Int):
        self.major = major
        self.minor = minor
        self.patch = patch

    def __init__(out self, *, copy: Self):
        self.major = copy.major
        self.minor = copy.minor
        self.patch = copy.patch

    def __init__(out self, *, deinit move: Self):
        self.major = move.major
        self.minor = move.minor
        self.patch = move.patch

    def __lt__(self, other: Self) -> Bool:
        if self.major != other.major:
            return self.major < other.major
        if self.minor != other.minor:
            return self.minor < other.minor
        return self.patch < other.patch

    def __le__(self, other: Self) -> Bool:
        return not (other < self)

    def __eq__(self, other: Self) -> Bool:
        return self.major == other.major and self.minor == other.minor and self.patch == other.patch

    def __str__(self) -> String:
        return String(self.major) + "." + String(self.minor) + "." + String(self.patch)


def _parse_int(s: String) -> Int:
    var result = 0
    var bytes = s.as_bytes()
    for i in range(len(bytes)):
        var b = bytes[i]
        if b >= 48 and b <= 57:  # '0'..'9'
            result = result * 10 + Int(b - 48)
        else:
            break
    return result


def semver_parse(version: String) raises -> SemVer:
    """Parse 'major.minor.patch' or 'vX.Y.Z'. Raises on invalid format."""
    var s = version
    # Strip leading 'v'
    var bytes = s.as_bytes()
    if len(bytes) > 0 and (bytes[0] == 118 or bytes[0] == 86):  # v or V
        var out = List[UInt8](capacity=len(bytes) - 1)
        for i in range(1, len(bytes)):
            out.append(bytes[i])
        s = String(unsafe_from_utf8=out^)

    var parts = s.split(".")
    if len(parts) < 2:
        raise Error("Invalid semver: " + version)

    # Reject empty components (e.g. "1.", ".1.0", "1..0")
    if String(parts[0]).byte_length() == 0 or String(parts[1]).byte_length() == 0:
        raise Error("Invalid semver: empty component in " + version)
    if len(parts) >= 3 and String(parts[2]).byte_length() == 0:
        raise Error("Invalid semver: empty component in " + version)

    var major = _parse_int(String(parts[0]))
    var minor = _parse_int(String(parts[1]))
    var patch = 0
    if len(parts) >= 3:
        patch = _parse_int(String(parts[2]))
    return SemVer(major, minor, patch)


def semver_satisfies(version: String, constraint: String) raises -> Bool:
    """Check if version satisfies constraint.
    A constraint is one or more comparators joined by commas, all of which
    must hold (e.g. '>=1.0.0,<2.0.0'). Comparators: '>=X.Y.Z', '^X.Y.Z',
    '=X.Y.Z', '>X.Y.Z', '<X.Y.Z', '<=X.Y.Z'; a bare 'X.Y.Z' means '>='.
    An empty constraint matches every version."""
    if constraint.byte_length() == 0:
        return True
    if constraint.find(",") >= 0:
        for part in constraint.split(","):
            var comparator = trim_spaces(String(part))
            if comparator.byte_length() == 0:
                raise Error("Invalid constraint: empty comparator in '" + constraint + "'")
            if not _satisfies_comparator(version, comparator):
                return False
        return True
    return _satisfies_comparator(version, trim_spaces(constraint))


def _satisfies_comparator(version: String, constraint: String) raises -> Bool:
    """Check version against a single comparator."""
    var v = semver_parse(version)
    var bytes = constraint.as_bytes()

    # Determine operator (defaults: ">=" with no prefix to skip)
    var op = ">="
    var ver_start = 0

    if len(bytes) >= 2 and bytes[0] == 62 and bytes[1] == 61:  # >=
        ver_start = 2
    elif len(bytes) >= 2 and bytes[0] == 60 and bytes[1] == 61:  # <=
        op = "<="
        ver_start = 2
    elif len(bytes) >= 1 and bytes[0] == 62:  # >
        op = ">"
        ver_start = 1
    elif len(bytes) >= 1 and bytes[0] == 60:  # <
        op = "<"
        ver_start = 1
    elif len(bytes) >= 1 and bytes[0] == 61:  # =
        op = "="
        ver_start = 1
    elif len(bytes) >= 1 and bytes[0] == 94:  # ^
        op = "^"
        ver_start = 1

    # Extract version string from constraint
    var ver_bytes = List[UInt8](capacity=len(bytes) - ver_start)
    for i in range(ver_start, len(bytes)):
        ver_bytes.append(bytes[i])
    var c = semver_parse(String(unsafe_from_utf8=ver_bytes^))

    if op == ">=":
        return c <= v
    elif op == ">":
        return c < v
    elif op == "<=":
        return v <= c
    elif op == "<":
        return v < c
    elif op == "=":
        return v == c
    elif op == "^":
        # ^X.Y.Z = >=X.Y.Z, <(X+1).0.0
        var upper = SemVer(c.major + 1, 0, 0)
        return c <= v and v < upper
    return True


# ─── Resolver ─────────────────────────────────────────────────────────────────

comptime _MAX_STEPS = 100_000  # versions tried before giving up


@fieldwise_init
struct _Req(Copyable, Movable):
    """A version constraint on a package, and where it came from."""

    var name: String
    var constraint: String
    var source: String  # "mojoproject.toml" or "<package> <version>"


@fieldwise_init
struct _Choice(Copyable, Movable):
    """A package pinned to one of its registry versions (index into
    PackageMeta.versions)."""

    var name: String
    var index: Int


struct _Solver(Movable):
    """Backtracking search for versions satisfying every constraint.

    Constraints come from the manifest and from the registry entry of each
    chosen version. Packages are chosen in discovery order (manifest deps
    first, then each chosen package's deps), newest version first; any
    choice that violates a constraint is undone and the next older version
    is tried."""

    var root: List[_Req]
    var chosen: List[_Choice]
    var steps: Int
    var conflict: String  # first unsatisfiable requirement seen

    def __init__(out self, var root: List[_Req]):
        self.root = root^
        self.chosen = List[_Choice]()
        self.steps = 0
        self.conflict = String()

    def __init__(out self, *, deinit move: Self):
        self.root = move.root^
        self.chosen = move.chosen^
        self.steps = move.steps
        self.conflict = move.conflict^

    def requirements(self, meta_cache: Dict[String, PackageMeta]) raises -> List[_Req]:
        """All constraints implied by the manifest and the current choices,
        in discovery order."""
        var reqs = List[_Req]()
        for i in range(len(self.root)):
            reqs.append(self.root[i].copy())
        for i in range(len(self.chosen)):
            ref meta = meta_cache[self.chosen[i].name]
            ref pv = meta.versions[self.chosen[i].index]
            var source = meta.name + " " + pv.version
            for j in range(len(pv.deps)):
                reqs.append(_Req(pv.deps[j], pv.dep_constraints[j], source))
        return reqs^

    def chosen_index(self, name: String) -> Int:
        for i in range(len(self.chosen)):
            if self.chosen[i].name == name:
                return i
        return -1

    def search(
        mut self,
        mut meta_cache: Dict[String, PackageMeta],
        mut client: HttpClient,
        offline: Bool,
    ) raises -> Bool:
        var reqs = self.requirements(meta_cache)

        # Every chosen version must still satisfy every constraint on it
        for i in range(len(self.chosen)):
            ref meta = meta_cache[self.chosen[i].name]
            var version = meta.versions[self.chosen[i].index].version
            for r in range(len(reqs)):
                if reqs[r].name == meta.name and not semver_satisfies(
                    version, reqs[r].constraint
                ):
                    return False

        # Next package that is required but not yet chosen
        var name = String()
        for r in range(len(reqs)):
            if self.chosen_index(reqs[r].name) < 0:
                name = reqs[r].name
                break
        if name.byte_length() == 0:
            return True  # everything required is chosen and consistent

        _ensure_meta(name, meta_cache, client, offline)
        var mine = List[_Req]()
        for r in range(len(reqs)):
            if reqs[r].name == name:
                mine.append(reqs[r].copy())

        var order = _newest_first(meta_cache[name])
        var tried = False
        for k in range(len(order)):
            var idx = order[k]
            var version = meta_cache[name].versions[idx].version
            var ok = True
            for r in range(len(mine)):
                if not semver_satisfies(version, mine[r].constraint):
                    ok = False
                    break
            if not ok:
                continue
            tried = True
            self.steps += 1
            if self.steps > _MAX_STEPS:
                raise Error(
                    "Dependency resolution gave up after "
                    + String(_MAX_STEPS)
                    + " attempts"
                )
            self.chosen.append(_Choice(name, idx))
            if self.search(meta_cache, client, offline):
                return True
            _ = self.chosen.pop()
        if not tried and self.conflict.byte_length() == 0:
            self.conflict = (
                "No version of '" + name + "' satisfies: " + _describe(mine)
            )
        return False


def _describe(reqs: List[_Req]) -> String:
    var out = String()
    for i in range(len(reqs)):
        if i > 0:
            out += ", "
        var c = reqs[i].constraint
        out += (c if c.byte_length() > 0 else "any") + " (" + reqs[i].source + ")"
    return out^


def _newest_first(meta: PackageMeta) raises -> List[Int]:
    """Indices of meta.versions, newest version first."""
    var order = List[Int]()
    for i in range(len(meta.versions)):
        order.append(i)
    # Insertion sort by semver, descending (version lists are short)
    for i in range(1, len(order)):
        var j = i
        while j > 0 and semver_parse(meta.versions[order[j - 1]].version) < semver_parse(
            meta.versions[order[j]].version
        ):
            var t = order[j - 1]
            order[j - 1] = order[j]
            order[j] = t
            j -= 1
    return order^


def _ensure_meta(
    name: String,
    mut meta_cache: Dict[String, PackageMeta],
    mut client: HttpClient,
    offline: Bool,
) raises:
    """Make sure name's registry metadata is in the cache."""
    if name in meta_cache:
        return
    validate_name(name)
    if offline:
        raise Error("Package not found in registry: " + name)
    meta_cache[name] = registry_fetch_package(name, client)


def resolve_with_cache(
    deps: List[Dependency],
    mut meta_cache: Dict[String, PackageMeta],
    mut client: HttpClient,
    offline: Bool = False,
) raises -> LockFile:
    """Resolve deps to a LockFile using (and filling) meta_cache. With
    offline=True, packages missing from the cache are an error instead of
    being fetched (used by tests)."""
    var root = List[_Req]()
    for i in range(len(deps)):
        validate_name(deps[i].name)
        root.append(_Req(deps[i].name, deps[i].version, "mojoproject.toml"))
    var solver = _Solver(root^)
    if not solver.search(meta_cache, client, offline):
        if solver.conflict.byte_length() > 0:
            raise Error(solver.conflict)
        raise Error("No combination of package versions satisfies all constraints")

    var lock = LockFile()
    var home = fs_home_dir()
    for i in range(len(solver.chosen)):
        ref meta = meta_cache[solver.chosen[i].name]
        ref pv = meta.versions[solver.chosen[i].index]
        var install_path = home + "/.mojo/packages/" + meta.name + "/" + pv.version
        lock.packages.append(
            LockedPackage(meta.name, pv.version, pv.tarball_url, pv.sha256, install_path)
        )
        print("  Resolved: " + meta.name + " " + pv.version)
    return lock^


def resolve(manifest: Manifest, mut client: HttpClient) raises -> LockFile:
    """Resolve all dependencies of manifest. Returns a complete LockFile.

    Fetches packages/all.json in a single HTTP request to pre-populate the
    metadata cache; packages missing from it are fetched individually."""
    var meta_cache = Dict[String, PackageMeta]()
    try:
        meta_cache = registry_fetch_all(client)
        print("  Fetched registry manifest (all.json)")
    except:
        print("  Warning: could not fetch all.json, falling back to per-package fetches")
    return resolve_with_cache(manifest.deps, meta_cache, client)

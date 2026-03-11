# src/resolver.mojo
# Greedy semver dependency resolver (v1).
# Picks newest version satisfying each constraint, resolves transitively.

from collections import Dict
from http_client import HttpClient
from manifest import Manifest, Dependency
from lockfile import LockFile, LockedPackage, lockfile_find
from registry import PackageMeta, PackageVersion, registry_fetch_package, registry_fetch_all
from fs import fs_home_dir
from validate import validate_name


# ─── Semver parsing ────────────────────────────────────────────────────────────

struct SemVer(Copyable, Movable):
    var major: Int
    var minor: Int
    var patch: Int

    fn __init__(out self, major: Int, minor: Int, patch: Int):
        self.major = major
        self.minor = minor
        self.patch = patch

    fn __copyinit__(out self, copy: Self):
        self.major = copy.major
        self.minor = copy.minor
        self.patch = copy.patch

    fn __moveinit__(out self, deinit take: Self):
        self.major = take.major
        self.minor = take.minor
        self.patch = take.patch

    fn __lt__(self, other: Self) -> Bool:
        if self.major != other.major:
            return self.major < other.major
        if self.minor != other.minor:
            return self.minor < other.minor
        return self.patch < other.patch

    fn __le__(self, other: Self) -> Bool:
        return not (other < self)

    fn __eq__(self, other: Self) -> Bool:
        return self.major == other.major and self.minor == other.minor and self.patch == other.patch

    fn __str__(self) -> String:
        return String(self.major) + "." + String(self.minor) + "." + String(self.patch)


fn _parse_int(s: String) -> Int:
    var result = 0
    var bytes = s.as_bytes()
    for i in range(len(bytes)):
        var b = bytes[i]
        if b >= 48 and b <= 57:  # '0'..'9'
            result = result * 10 + Int(b - 48)
        else:
            break
    return result


fn semver_parse(version: String) raises -> SemVer:
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

    var major = _parse_int(String(parts[0]))
    var minor = _parse_int(String(parts[1]))
    var patch = 0
    if len(parts) >= 3:
        patch = _parse_int(String(parts[2]))
    return SemVer(major, minor, patch)


fn semver_satisfies(version: String, constraint: String) raises -> Bool:
    """Check if version satisfies constraint.
    Supported: '>=X.Y.Z', '^X.Y.Z', '=X.Y.Z', '>X.Y.Z', '<X.Y.Z', '<=X.Y.Z'."""
    if len(constraint) == 0:
        return True

    var v = semver_parse(version)
    var bytes = constraint.as_bytes()

    # Determine operator
    var op = String("")
    var ver_start = 0

    if len(bytes) >= 2 and bytes[0] == 62 and bytes[1] == 61:  # >=
        op = ">="
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
    else:
        op = ">="
        ver_start = 0

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

fn _best_version(meta: PackageMeta, constraint: String) raises -> PackageVersion:
    """Find the newest version satisfying the constraint."""
    var found = False
    var best_ver = SemVer(0, 0, 0)
    var best_idx = -1

    for i in range(len(meta.versions)):
        if semver_satisfies(meta.versions[i].version, constraint):
            var sv = semver_parse(meta.versions[i].version)
            if not found or best_ver < sv:
                found = True
                best_ver = sv.copy()
                best_idx = i

    if not found or best_idx < 0:
        raise Error("No version of '" + meta.name + "' satisfies constraint: " + constraint)
    return meta.versions[best_idx].copy()


fn resolve(manifest: Manifest, mut client: HttpClient) raises -> LockFile:
    """Resolve all dependencies (greedy BFS). Returns a complete LockFile.

    Fetches packages/all.json in a single HTTP request to pre-populate a
    local metadata cache. Packages not found in the bulk manifest fall back
    to individual per-package fetches. Within one resolve run, each package
    name is fetched at most once (memoized in meta_cache)."""
    var lock = LockFile()
    var home = fs_home_dir()

    # Bulk-fetch all known packages in one HTTP request (P1 + P2)
    var meta_cache = Dict[String, PackageMeta]()
    try:
        meta_cache = registry_fetch_all(client)
        print("  Fetched registry manifest (all.json)")
    except:
        print("  Warning: could not fetch all.json, falling back to per-package fetches")

    # BFS queue of (name, constraint) pairs
    var queue = List[Dependency]()
    for i in range(len(manifest.deps)):
        queue.append(manifest.deps[i].copy())

    var i = 0
    while i < len(queue):
        var dep_name = queue[i].name
        var dep_version = queue[i].version
        i += 1

        # Skip if already resolved
        if lockfile_find(lock, dep_name) >= 0:
            continue

        # Use cached metadata if available; otherwise fetch individually
        var meta: PackageMeta
        if dep_name in meta_cache:
            meta = meta_cache[dep_name].copy()
        else:
            meta = registry_fetch_package(dep_name, client)
            meta_cache[dep_name] = meta.copy()

        var pv = _best_version(meta, dep_version)

        var install_path = home + "/.mojo/packages/" + dep_name + "/" + pv.version
        var lp = LockedPackage(
            dep_name,
            pv.version,
            pv.tarball_url,
            pv.sha256,
            install_path,
        )
        lock.packages.append(lp^)
        print("  Resolved: " + dep_name + " " + pv.version)

        # Use transitive deps from registry (avoids extra HTTP round-trip per package)
        for j in range(len(pv.deps)):
            var tdep = pv.deps[j]
            validate_name(tdep)
            if lockfile_find(lock, tdep) < 0:
                queue.append(Dependency(tdep, "", ">=0.0.0"))

    return lock^

# src/registry.mojo
# Fetch package metadata from the GitHub-backed mojo-pkg-index.
# Index lives at: https://raw.githubusercontent.com/Mosaad-M/mojo-pkg-index/main/

from std.collections import Dict
from json import JsonValue, parse_json
from http_client import HttpClient, HttpResponse
from validate import validate_constraint, validate_name, validate_tarball_url

comptime INDEX_BASE = "https://raw.githubusercontent.com/Mosaad-M/mojo-pkg-index/main"


struct PackageVersion(Copyable, Movable):
    """A single version entry from the registry."""
    var version: String
    var tarball_url: String
    var sha256: String
    var mojo_requires: String
    var deps: List[String]
    # Version constraint for each entry of deps ("" = any version), from the
    # registry's optional "dep_constraints" object.
    var dep_constraints: List[String]

    def __init__(out self, version: String, tarball_url: String, sha256: String, mojo_requires: String):
        self.version = version
        self.tarball_url = tarball_url
        self.sha256 = sha256
        self.mojo_requires = mojo_requires
        self.deps = List[String]()
        self.dep_constraints = List[String]()

    def __init__(out self, *, copy: Self):
        self.version = copy.version
        self.tarball_url = copy.tarball_url
        self.sha256 = copy.sha256
        self.mojo_requires = copy.mojo_requires
        self.deps = copy.deps.copy()
        self.dep_constraints = copy.dep_constraints.copy()

    def __init__(out self, *, deinit move: Self):
        self.version = move.version^
        self.tarball_url = move.tarball_url^
        self.sha256 = move.sha256^
        self.mojo_requires = move.mojo_requires^
        self.deps = move.deps^
        self.dep_constraints = move.dep_constraints^

    def add_dep(mut self, name: String, constraint: String = ""):
        self.deps.append(name)
        self.dep_constraints.append(constraint)


struct PackageMeta(Copyable, Movable):
    """Full metadata for a package from the registry."""
    var name: String
    var git_url: String
    var versions: List[PackageVersion]

    def __init__(out self, name: String, git_url: String):
        self.name = name
        self.git_url = git_url
        self.versions = List[PackageVersion]()

    def __init__(out self, *, copy: Self):
        self.name = copy.name
        self.git_url = copy.git_url
        self.versions = copy.versions.copy()

    def __init__(out self, *, deinit move: Self):
        self.name = move.name^
        self.git_url = move.git_url^
        self.versions = move.versions^


def parse_package_json(root: JsonValue) raises -> PackageMeta:
    """Parse a single package JSON object into PackageMeta."""
    var meta = PackageMeta(
        root.get_string("name"),
        root.get_string("git_url"),
    )

    var versions_arr = root.get("versions")
    var n = len(versions_arr)
    for i in range(n):
        var v = versions_arr.get(i)
        var tarball_url = v.get_string("tarball_url")
        validate_tarball_url(tarball_url)
        var pv = PackageVersion(
            v.get_string("version"),
            tarball_url,
            v.get_string("sha256"),
            v.get_string("mojo_requires") if v.has_key("mojo_requires") else ">=0.26.1",
        )
        # Parse optional deps array (transitive dependencies from registry)
        if v.has_key("deps"):
            var deps_arr = v.get("deps")
            var nd = len(deps_arr)
            for j in range(nd):
                var dname = deps_arr.get_string(j)
                validate_name(dname)
                pv.add_dep(dname)
        # Optional per-dep version constraints: {"json": ">=3.0.1"}
        if v.has_key("dep_constraints"):
            var dc = v.get("dep_constraints")
            if not dc.is_object():
                raise Error(
                    "Registry: dep_constraints of "
                    + meta.name
                    + " "
                    + pv.version
                    + " must be an object"
                )
            var keys = dc.keys()
            for k in range(len(keys)):
                var dep = keys[k]
                var idx = -1
                for j in range(len(pv.deps)):
                    if pv.deps[j] == dep:
                        idx = j
                if idx < 0:
                    raise Error(
                        "Registry: dep_constraints key '"
                        + dep
                        + "' of "
                        + meta.name
                        + " "
                        + pv.version
                        + " is not in deps"
                    )
                var constraint = dc.get_string(dep)
                validate_constraint(constraint)
                pv.dep_constraints[idx] = constraint
        meta.versions.append(pv^)

    return meta^


def registry_fetch_package(name: String, mut client: HttpClient) raises -> PackageMeta:
    """Fetch package metadata from the index."""
    validate_name(name)
    var url = INDEX_BASE + "/packages/" + name + ".json"
    var resp = client.get(url)
    if resp.status_code != 200:
        raise Error("Package not found in registry: " + name + " (HTTP " + String(resp.status_code) + ")")

    var root = parse_json(resp.body)
    return parse_package_json(root)


def registry_fetch_all(mut client: HttpClient) raises -> Dict[String, PackageMeta]:
    """Fetch the combined all.json manifest in a single HTTP request.
    Returns a Dict mapping package name -> PackageMeta."""
    var url = INDEX_BASE + "/packages/all.json"
    var resp = client.get(url)
    if resp.status_code != 200:
        raise Error("Could not fetch all.json (HTTP " + String(resp.status_code) + ")")

    var root = parse_json(resp.body)
    var pkgs_arr = root.get("packages")
    var n = len(pkgs_arr)
    var result = Dict[String, PackageMeta]()
    for i in range(n):
        var pkg_json = pkgs_arr.get(i)
        var meta = parse_package_json(pkg_json)
        validate_name(meta.name)
        result[meta.name] = meta^
    return result^


def registry_search(query: String, mut client: HttpClient) raises -> List[String]:
    """Search for packages in the index. Returns list of matching names."""
    var url = INDEX_BASE + "/index.json"
    var resp = client.get(url)
    if resp.status_code != 200:
        raise Error("Could not fetch package index (HTTP " + String(resp.status_code) + ")")

    var root = parse_json(resp.body)
    var all_pkgs = root.get("packages")
    var n = len(all_pkgs)
    var result = List[String]()
    for i in range(n):
        var pkg_name = all_pkgs.get_string(i)
        # Simple substring match
        if query.byte_length() == 0 or pkg_name.find(query) >= 0:
            result.append(pkg_name)
    return result^

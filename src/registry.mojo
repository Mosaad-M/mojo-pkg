# src/registry.mojo
# Fetch package metadata from the GitHub-backed mojo-pkg-index.
# Index lives at: https://raw.githubusercontent.com/Mosaad-M/mojo-pkg-index/main/
# When raw.githubusercontent.com is unreachable (some networks filter it),
# the same files are fetched through the GitHub contents API instead.

from std.collections import Dict
from std.os import getenv
from json import JsonValue, parse_json
from http_client import HttpClient, HttpHeaders, HttpResponse
from validate import validate_constraint, validate_name, validate_tarball_url

comptime INDEX_BASE = "https://raw.githubusercontent.com/Mosaad-M/mojo-pkg-index/main"
comptime INDEX_API_BASE = "https://api.github.com/repos/Mosaad-M/mojo-pkg-index/contents"
comptime INDEX_REF = "main"


def index_api_url(path: String) -> String:
    """GitHub contents-API URL for an index file (path like "packages/x.json")."""
    return INDEX_API_BASE + "/" + path + "?ref=" + INDEX_REF


def _primary_is_answer(status: Int) -> Bool:
    """True when raw.githubusercontent.com's reply is final (no fallback).

    Over verified TLS, a 2xx/3xx/4xx is GitHub's real answer (a 404 means
    the package does not exist). Rate limiting and server errors are worth
    retrying through the API.
    """
    return status < 500 and status != 429


def index_get_from(
    primary_base: String, path: String, mut client: HttpClient
) raises -> HttpResponse:
    """GET an index file from primary_base, falling back to the GitHub API.

    The fallback is GitHub itself (same repository, same TLS validation),
    so it adds no new party that could alter the index's tarball hashes.
    """
    var primary_err: String
    try:
        var resp = client.get(primary_base + "/" + path)
        if _primary_is_answer(resp.status_code):
            return resp^
        primary_err = "HTTP " + String(resp.status_code)
    except e:
        primary_err = String(e)

    var headers = HttpHeaders()
    headers.add("Accept", "application/vnd.github.raw")
    var token = getenv("GITHUB_TOKEN", "")
    if token.byte_length() > 0:
        headers.add("Authorization", "Bearer " + token)
    var resp: HttpResponse
    try:
        resp = client.get(index_api_url(path), headers)
    except e:
        raise Error(
            "could not reach the package index: " + primary_base + " failed ("
            + primary_err + "), api.github.com failed (" + String(e) + ")"
        )
    if resp.status_code == 403 or resp.status_code == 429:
        raise Error(
            "could not reach the package index: " + primary_base + " failed ("
            + primary_err + "), and the GitHub API rate limit was hit (HTTP "
            + String(resp.status_code) + "; set GITHUB_TOKEN to raise it)"
        )
    return resp^


def index_get(path: String, mut client: HttpClient) raises -> HttpResponse:
    """GET an index file (e.g. "packages/all.json") with the API fallback."""
    return index_get_from(INDEX_BASE, path, client)


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
    var resp = index_get("packages/" + name + ".json", client)
    if resp.status_code != 200:
        raise Error("Package not found in registry: " + name + " (HTTP " + String(resp.status_code) + ")")

    var root = parse_json(resp.body)
    return parse_package_json(root)


def registry_fetch_all(mut client: HttpClient) raises -> Dict[String, PackageMeta]:
    """Fetch the combined all.json manifest in a single HTTP request.
    Returns a Dict mapping package name -> PackageMeta."""
    var resp = index_get("packages/all.json", client)
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
    var resp = index_get("index.json", client)
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

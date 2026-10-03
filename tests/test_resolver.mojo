# tests/test_resolver.mojo
# Offline tests for the constraint-aware, backtracking resolver and for
# parsing "dep_constraints" from registry JSON. Fixtures mirror the real
# index (json 1.x -> 3.x API break; requests pinning json per version).

from std.collections import Dict
from http_client import HttpClient
from json import parse_json
from lockfile import LockFile, lockfile_find
from manifest import Dependency
from registry import PackageMeta, PackageVersion, parse_package_json
from resolver import resolve_with_cache


def assert_true(val: Bool, label: String) raises:
    if not val:
        raise Error("FAIL: " + label)


def assert_eq(a: String, b: String, label: String) raises:
    if a != b:
        raise Error("FAIL: " + label + " — expected '" + b + "', got '" + a + "'")


def _version(v: String) -> PackageVersion:
    return PackageVersion(
        v,
        "https://github.com/Mosaad-M/x/archive/refs/tags/v" + v + ".tar.gz",
        "0" * 64,
        ">=1.0.0",
    )


def _simple(name: String, versions: List[String]) -> PackageMeta:
    var meta = PackageMeta(name, "Mosaad-M/" + name)
    for i in range(len(versions)):
        meta.versions.append(_version(versions[i]))
    return meta^


def _requests_version(v: String, json_constraint: String) -> PackageVersion:
    var pv = _version(v)
    pv.add_dep("tls")
    pv.add_dep("tcp")
    pv.add_dep("url")
    pv.add_dep("json", json_constraint)
    return pv^


def index() -> Dict[String, PackageMeta]:
    """Fixture mirroring mojo-pkg-index after json 3.x."""
    var cache = Dict[String, PackageMeta]()
    var json_versions = List[String]()
    for v in ["1.0.0", "1.0.1", "1.0.2", "1.1.0", "2.0.0", "3.0.1"]:
        json_versions.append(v)
    cache["json"] = _simple("json", json_versions)
    var tls_versions = List[String]()
    tls_versions.append("1.4.0")
    tls_versions.append("1.4.2")
    cache["tls"] = _simple("tls", tls_versions)
    var one = List[String]()
    one.append("1.1.0")
    cache["tcp"] = _simple("tcp", one)
    cache["url"] = _simple("url", one)
    var requests = PackageMeta("requests", "Mosaad-M/requests")
    requests.versions.append(_requests_version("1.0.0", "<2.0.0"))
    requests.versions.append(_requests_version("1.0.1", "<2.0.0"))
    requests.versions.append(_requests_version("1.1.0", "<2.0.0"))
    requests.versions.append(_requests_version("1.2.0", ">=3.0.1"))
    cache["requests"] = requests^
    return cache^


def deps(*pairs: String) -> List[Dependency]:
    """deps("requests", ">=1.0.0", "json", "=1.1.0", ...)"""
    var out = List[Dependency]()
    var i = 0
    while i + 1 < len(pairs):
        out.append(Dependency(pairs[i], "Mosaad-M/" + pairs[i], pairs[i + 1]))
        i += 2
    return out^


def locked(lock: LockFile, name: String) raises -> String:
    var i = lockfile_find(lock, name)
    if i < 0:
        raise Error("FAIL: " + name + " not in lockfile")
    return lock.packages[i].version


def resolve_offline(d: List[Dependency], mut cache: Dict[String, PackageMeta]) raises -> LockFile:
    var client = HttpClient()
    return resolve_with_cache(d, cache, client, offline=True)


# ─── Scenarios ────────────────────────────────────────────────────────────────

def test_latest_requests_gets_json_3() raises:
    var cache = index()
    var lock = resolve_offline(deps("requests", ">=1.0.0"), cache)
    assert_eq(locked(lock, "requests"), "1.2.0", "newest requests")
    assert_eq(locked(lock, "json"), "3.0.1", "json from requests' constraint")
    assert_eq(locked(lock, "tls"), "1.4.2", "unconstrained dep: newest")
    print("PASS: test_latest_requests_gets_json_3")


def test_pinned_old_requests_gets_json_1() raises:
    # The R-3 bug: this used to lock json 3.0.1, which requests 1.1.0
    # cannot compile against.
    var cache = index()
    var lock = resolve_offline(deps("requests", "=1.1.0"), cache)
    assert_eq(locked(lock, "requests"), "1.1.0", "pinned requests")
    assert_eq(locked(lock, "json"), "1.1.0", "newest json below 2.0.0")
    print("PASS: test_pinned_old_requests_gets_json_1")


def test_backtracks_to_older_requests() raises:
    # requests 1.2.0 needs json >=3.0.1, the manifest pins json 1.1.0:
    # the only solution is requests 1.1.0. Order of manifest deps must
    # not matter.
    var cache = index()
    var lock = resolve_offline(deps("requests", ">=1.0.0", "json", "=1.1.0"), cache)
    assert_eq(locked(lock, "requests"), "1.1.0", "backtracked requests")
    assert_eq(locked(lock, "json"), "1.1.0", "pinned json")
    var cache2 = index()
    var lock2 = resolve_offline(deps("json", "=1.1.0", "requests", ">=1.0.0"), cache2)
    assert_eq(locked(lock2, "requests"), "1.1.0", "backtracked (json listed first)")
    print("PASS: test_backtracks_to_older_requests")


def test_conflict_names_both_sources() raises:
    var cache = index()
    var message = String()
    try:
        _ = resolve_offline(deps("requests", "=1.2.0", "json", "<2.0.0"), cache)
    except e:
        message = String(e)
    assert_true(message.find("json") >= 0, "names the package: " + message)
    assert_true(message.find("<2.0.0 (mojoproject.toml)") >= 0, "names manifest constraint: " + message)
    assert_true(message.find(">=3.0.1 (requests 1.2.0)") >= 0, "names requests' constraint: " + message)
    print("PASS: test_conflict_names_both_sources")


def test_unconstrained_deps_take_newest() raises:
    # Registry entries without dep_constraints behave as before (newest).
    var cache = Dict[String, PackageMeta]()
    var app = PackageMeta("app", "Mosaad-M/app")
    var pv = _version("1.0.0")
    pv.add_dep("lib")
    app.versions.append(pv^)
    cache["app"] = app^
    var libv = List[String]()
    for v in ["1.0.0", "2.0.0", "1.5.0"]:
        libv.append(v)
    cache["lib"] = _simple("lib", libv)
    var lock = resolve_offline(deps("app", ""), cache)
    assert_eq(locked(lock, "lib"), "2.0.0", "newest lib (unsorted versions)")
    print("PASS: test_unconstrained_deps_take_newest")


def test_diamond_takes_newest_in_intersection() raises:
    var cache = Dict[String, PackageMeta]()
    var a = PackageMeta("a", "Mosaad-M/a")
    var av = _version("1.0.0")
    av.add_dep("c", ">=1.0.0,<3.0.0")
    a.versions.append(av^)
    var b = PackageMeta("b", "Mosaad-M/b")
    var bv = _version("1.0.0")
    bv.add_dep("c", ">=2.0.0")
    b.versions.append(bv^)
    cache["a"] = a^
    cache["b"] = b^
    var cv = List[String]()
    for v in ["1.0.0", "2.0.0", "2.5.0", "3.0.0"]:
        cv.append(v)
    cache["c"] = _simple("c", cv)
    var lock = resolve_offline(deps("a", "", "b", ""), cache)
    assert_eq(locked(lock, "c"), "2.5.0", "newest version allowed by both")
    print("PASS: test_diamond_takes_newest_in_intersection")


def test_lock_order_is_deterministic() raises:
    var cache = index()
    var lock = resolve_offline(deps("requests", ">=1.0.0"), cache)
    var order = String()
    for i in range(len(lock.packages)):
        order += lock.packages[i].name + " "
    assert_eq(order, "requests tls tcp url json ", "manifest first, then dep order")
    print("PASS: test_lock_order_is_deterministic")


def test_missing_package_offline_raises() raises:
    var cache = index()
    var raised = False
    try:
        _ = resolve_offline(deps("nonexistent", ">=1.0.0"), cache)
    except:
        raised = True
    assert_true(raised, "unknown package raises")
    print("PASS: test_missing_package_offline_raises")


# ─── Registry parsing ─────────────────────────────────────────────────────────

comptime _PKG_HEAD = '{"name": "requests", "git_url": "Mosaad-M/requests", "versions": [{"version": "1.2.0", "tarball_url": "https://github.com/Mosaad-M/requests/archive/refs/tags/v1.2.0.tar.gz", "sha256": "aa", "deps": ["tls", "json"]'


def test_parse_dep_constraints() raises:
    var meta = parse_package_json(parse_json(_PKG_HEAD + ', "dep_constraints": {"json": ">=3.0.1"}}]}'))
    ref pv = meta.versions[0]
    assert_eq(pv.deps[1], "json", "deps kept")
    assert_eq(pv.dep_constraints[1], ">=3.0.1", "constraint aligned with its dep")
    assert_eq(pv.dep_constraints[0], "", "unconstrained dep")
    var old = parse_package_json(parse_json(_PKG_HEAD + '}]}'))
    assert_eq(old.versions[0].dep_constraints[1], "", "old format: no constraints")
    print("PASS: test_parse_dep_constraints")


def test_parse_rejects_bad_dep_constraints() raises:
    var bad = List[String]()
    bad.append(', "dep_constraints": {"pg": ">=1.0.0"}')     # key not in deps
    bad.append(', "dep_constraints": {"json": ">=1.0"}')     # bad version
    bad.append(', "dep_constraints": {"json": "3.0.1"}')     # no operator
    bad.append(', "dep_constraints": [">=1.0.0"]')           # not an object
    for i in range(len(bad)):
        var raised = False
        try:
            _ = parse_package_json(parse_json(_PKG_HEAD + bad[i] + '}]}'))
        except:
            raised = True
        assert_true(raised, "rejects" + bad[i])
    print("PASS: test_parse_rejects_bad_dep_constraints")


def main() raises:
    print("=== Resolver Tests ===")
    test_latest_requests_gets_json_3()
    test_pinned_old_requests_gets_json_1()
    test_backtracks_to_older_requests()
    test_conflict_names_both_sources()
    test_unconstrained_deps_take_newest()
    test_diamond_takes_newest_in_intersection()
    test_lock_order_is_deterministic()
    test_missing_package_offline_raises()
    test_parse_dep_constraints()
    test_parse_rejects_bad_dep_constraints()
    print("")
    print("All resolver tests passed!")

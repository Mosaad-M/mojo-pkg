# tests/test_remove.mojo
# Unit tests for manifest_remove_dep.

from fs import fs_write_file, fs_read_file
from manifest import manifest_parse, manifest_write, manifest_remove_dep, Manifest, Dependency


def assert_eq(a: String, b: String, label: String) raises:
    if a != b:
        raise Error("FAIL: " + label + " — expected '" + b + "', got '" + a + "'")


def assert_int_eq(a: Int, b: Int, label: String) raises:
    if a != b:
        raise Error("FAIL: " + label + " — expected " + String(b) + ", got " + String(a))


def make_manifest() -> Manifest:
    var m = Manifest()
    m.name = String("test-pkg")
    m.version = String("0.1.0")
    m.mojo_requires = String(">=0.26.1")
    m.platforms.append("linux-64")
    m.deps.append(Dependency("tls", "Mosaad-M/tls", ">=1.0.0"))
    m.deps.append(Dependency("tcp", "Mosaad-M/tcp", ">=1.0.0"))
    m.deps.append(Dependency("json", "Mosaad-M/json", ">=1.0.0"))
    return m^


def test_remove_middle_dep() raises:
    """Remove a dep from the middle of the list; others remain."""
    var m = make_manifest()
    manifest_remove_dep(m, "tcp")
    assert_int_eq(len(m.deps), 2, "remove middle: 2 deps remain")
    assert_eq(m.deps[0].name, "tls", "remove middle: dep[0] is tls")
    assert_eq(m.deps[1].name, "json", "remove middle: dep[1] is json")
    print("PASS: test_remove_middle_dep")


def test_remove_first_dep() raises:
    """Remove the first dep; others remain in order."""
    var m = make_manifest()
    manifest_remove_dep(m, "tls")
    assert_int_eq(len(m.deps), 2, "remove first: 2 deps remain")
    assert_eq(m.deps[0].name, "tcp", "remove first: dep[0] is tcp")
    assert_eq(m.deps[1].name, "json", "remove first: dep[1] is json")
    print("PASS: test_remove_first_dep")


def test_remove_last_dep() raises:
    """Remove the last dep."""
    var m = make_manifest()
    manifest_remove_dep(m, "json")
    assert_int_eq(len(m.deps), 2, "remove last: 2 deps remain")
    assert_eq(m.deps[0].name, "tls", "remove last: dep[0] is tls")
    assert_eq(m.deps[1].name, "tcp", "remove last: dep[1] is tcp")
    print("PASS: test_remove_last_dep")


def test_remove_only_dep() raises:
    """Remove the only dep; list becomes empty."""
    var m = Manifest()
    m.name = String("test")
    m.version = String("0.1.0")
    m.mojo_requires = String(">=0.26.1")
    m.platforms.append("linux-64")
    m.deps.append(Dependency("tls", "Mosaad-M/tls", ">=1.0.0"))
    manifest_remove_dep(m, "tls")
    assert_int_eq(len(m.deps), 0, "remove only: 0 deps remain")
    print("PASS: test_remove_only_dep")


def test_remove_nonexistent_raises() raises:
    """Removing a dep that doesn't exist should raise."""
    var m = make_manifest()
    var raised = False
    try:
        manifest_remove_dep(m, "requests")
    except:
        raised = True
    assert_int_eq(1 if raised else 0, 1, "remove nonexistent: raises Error")
    print("PASS: test_remove_nonexistent_raises")


def test_remove_from_empty_raises() raises:
    """Removing from a manifest with no deps should raise."""
    var m = Manifest()
    m.name = String("empty")
    m.version = String("0.1.0")
    m.mojo_requires = String(">=0.26.1")
    m.platforms.append("linux-64")
    var raised = False
    try:
        manifest_remove_dep(m, "tls")
    except:
        raised = True
    assert_int_eq(1 if raised else 0, 1, "remove from empty: raises Error")
    print("PASS: test_remove_from_empty_raises")


def test_remove_roundtrip() raises:
    """Remove a dep, write to file, parse back, verify dep is gone."""
    var m = make_manifest()
    manifest_remove_dep(m, "tcp")
    manifest_write(m, "/tmp/test_remove_rt.toml")
    var m2 = manifest_parse("/tmp/test_remove_rt.toml")
    assert_int_eq(len(m2.deps), 2, "roundtrip: 2 deps")
    # tcp must not appear
    var found_tcp = False
    for i in range(len(m2.deps)):
        if m2.deps[i].name == "tcp":
            found_tcp = True
    assert_int_eq(1 if found_tcp else 0, 0, "roundtrip: tcp not in parsed manifest")
    assert_eq(m2.deps[0].name, "tls", "roundtrip: dep[0] is tls")
    assert_eq(m2.deps[1].name, "json", "roundtrip: dep[1] is json")
    print("PASS: test_remove_roundtrip")


def test_remove_preserves_dep_fields() raises:
    """Remaining deps keep their git and version fields intact."""
    var m = make_manifest()
    manifest_remove_dep(m, "tcp")
    assert_eq(m.deps[0].git, "Mosaad-M/tls", "preserve fields: tls git")
    assert_eq(m.deps[0].version, ">=1.0.0", "preserve fields: tls version")
    assert_eq(m.deps[1].git, "Mosaad-M/json", "preserve fields: json git")
    assert_eq(m.deps[1].version, ">=1.0.0", "preserve fields: json version")
    print("PASS: test_remove_preserves_dep_fields")


def main() raises:
    print("=== Remove Dep Tests ===")
    test_remove_middle_dep()
    test_remove_first_dep()
    test_remove_last_dep()
    test_remove_only_dep()
    test_remove_nonexistent_raises()
    test_remove_from_empty_raises()
    test_remove_roundtrip()
    test_remove_preserves_dep_fields()
    print("")
    print("All remove tests passed!")

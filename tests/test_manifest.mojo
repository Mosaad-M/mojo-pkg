# tests/test_manifest.mojo
# Tests for manifest_parse using a temporary file.

from fs import fs_write_file, fs_exists
from manifest import manifest_parse, manifest_write, manifest_add_dep, Manifest, Dependency, CDependency
from fs import fs_read_file


fn assert_eq(a: String, b: String, label: String) raises:
    if a != b:
        raise Error("FAIL: " + label + " — expected '" + b + "', got '" + a + "'")


fn assert_int_eq(a: Int, b: Int, label: String) raises:
    if a != b:
        raise Error("FAIL: " + label + " — expected " + String(b) + ", got " + String(a))


fn assert_contains(haystack: String, needle: String, label: String) raises:
    if haystack.find(needle) < 0:
        raise Error("FAIL: " + label + " — expected '" + needle + "' in output")


fn test_parse_full() raises:
    var toml = String("""
[package]
name = "requests"
version = "0.3.0"
description = "Pure-Mojo HTTP/1.1 client"
license = "MIT"
platforms = ["linux-64", "osx-arm64"]

[mojo]
requires = ">=0.26.1"

[dependencies]
tls    = { git = "Mosaad-M/tls",    version = ">=1.0.0" }
tcp    = { git = "Mosaad-M/tcp",    version = ">=1.0.0" }
""")
    fs_write_file("/tmp/test_manifest_full.toml", toml)
    var m = manifest_parse("/tmp/test_manifest_full.toml")

    assert_eq(m.name, "requests", "name")
    assert_eq(m.version, "0.3.0", "version")
    assert_eq(m.description, "Pure-Mojo HTTP/1.1 client", "description")
    assert_eq(m.license, "MIT", "license")
    assert_eq(m.mojo_requires, ">=0.26.1", "mojo_requires")
    assert_int_eq(len(m.deps), 2, "dep count")
    assert_eq(m.deps[0].name, "tls", "dep[0].name")
    assert_eq(m.deps[0].git, "Mosaad-M/tls", "dep[0].git")
    assert_eq(m.deps[0].version, ">=1.0.0", "dep[0].version")
    print("PASS: test_parse_full")


fn test_parse_c_deps() raises:
    var toml = String("""
[package]
name = "tcp"
version = "1.0.0"

[mojo]
requires = ">=0.26.1"

[c-dependencies]
errno_helper = "errno_helper.c"
""")
    fs_write_file("/tmp/test_manifest_cdeps.toml", toml)
    var m = manifest_parse("/tmp/test_manifest_cdeps.toml")

    assert_eq(m.name, "tcp", "tcp name")
    assert_int_eq(len(m.deps), 0, "no mojo deps")
    assert_int_eq(len(m.c_deps), 1, "one c-dep")
    assert_eq(m.c_deps[0].name, "errno_helper", "cdep name")
    assert_eq(m.c_deps[0].source, "errno_helper.c", "cdep source")
    print("PASS: test_parse_c_deps")


fn test_manifest_roundtrip() raises:
    var m = Manifest()
    m.name = String("my-pkg")
    m.version = String("0.2.0")
    m.description = String("Test package")
    m.license = String("MIT")
    m.mojo_requires = String(">=0.26.1")
    m.platforms.append("linux-64")
    m.deps.append(Dependency("json", "Mosaad-M/json", ">=1.0.0"))

    manifest_write(m, "/tmp/test_manifest_rt.toml")

    var m2 = manifest_parse("/tmp/test_manifest_rt.toml")
    assert_eq(m2.name, "my-pkg", "roundtrip name")
    assert_eq(m2.version, "0.2.0", "roundtrip version")
    assert_int_eq(len(m2.deps), 1, "roundtrip dep count")
    assert_eq(m2.deps[0].name, "json", "roundtrip dep name")
    print("PASS: test_manifest_roundtrip")


fn test_manifest_add_dep() raises:
    var m = Manifest()
    m.name = String("test")
    m.version = String("0.1.0")
    m.mojo_requires = String(">=0.26.1")
    m.platforms.append("linux-64")

    manifest_add_dep(m, "tls", "Mosaad-M/tls", ">=1.0.0")
    assert_int_eq(len(m.deps), 1, "add one dep")

    # Adding again should update, not duplicate
    manifest_add_dep(m, "tls", "Mosaad-M/tls", ">=2.0.0")
    assert_int_eq(len(m.deps), 1, "update existing dep")
    assert_eq(m.deps[0].version, ">=2.0.0", "dep updated")

    manifest_add_dep(m, "tcp", "Mosaad-M/tcp", ">=1.0.0")
    assert_int_eq(len(m.deps), 2, "add second dep")
    print("PASS: test_manifest_add_dep")


fn test_no_description() raises:
    var toml = String("""
[package]
name = "minimal"
version = "0.1.0"

[mojo]
requires = ">=0.26.1"
""")
    fs_write_file("/tmp/test_manifest_nodesc.toml", toml)
    var m = manifest_parse("/tmp/test_manifest_nodesc.toml")
    assert_eq(m.description, "", "no description: empty string")
    print("PASS: test_no_description")


fn test_no_license() raises:
    var toml = String("""
[package]
name = "minimal"
version = "0.1.0"

[mojo]
requires = ">=0.26.1"
""")
    fs_write_file("/tmp/test_manifest_nolic.toml", toml)
    var m = manifest_parse("/tmp/test_manifest_nolic.toml")
    assert_eq(m.license, "", "no license: empty string")
    print("PASS: test_no_license")


fn test_multiple_platforms() raises:
    var toml = String("""
[package]
name = "mypkg"
version = "0.1.0"
platforms = ["linux-64", "osx-arm64"]

[mojo]
requires = ">=0.26.1"
""")
    fs_write_file("/tmp/test_manifest_plats.toml", toml)
    var m = manifest_parse("/tmp/test_manifest_plats.toml")
    assert_int_eq(len(m.platforms), 2, "multiple platforms: count == 2")
    # Both platform strings must be present
    var found_linux = False
    var found_osx = False
    for i in range(len(m.platforms)):
        if m.platforms[i] == "linux-64":
            found_linux = True
        if m.platforms[i] == "osx-arm64":
            found_osx = True
    assert_int_eq(1 if found_linux else 0, 1, "multiple platforms: linux-64 found")
    assert_int_eq(1 if found_osx else 0, 1, "multiple platforms: osx-arm64 found")
    print("PASS: test_multiple_platforms")


fn test_empty_deps() raises:
    var toml = String("""
[package]
name = "nodeps"
version = "0.1.0"

[mojo]
requires = ">=0.26.1"
""")
    fs_write_file("/tmp/test_manifest_nodeps.toml", toml)
    var m = manifest_parse("/tmp/test_manifest_nodeps.toml")
    assert_int_eq(len(m.deps), 0, "empty deps: no dependencies")
    print("PASS: test_empty_deps")


fn test_no_c_deps_section() raises:
    var toml = String("""
[package]
name = "nocdeps"
version = "0.1.0"

[mojo]
requires = ">=0.26.1"
""")
    fs_write_file("/tmp/test_manifest_nocdeps.toml", toml)
    var m = manifest_parse("/tmp/test_manifest_nocdeps.toml")
    assert_int_eq(len(m.c_deps), 0, "no c_deps section: empty c_deps list")
    print("PASS: test_no_c_deps_section")


fn test_escape_double_quote_written() raises:
    # Verify that _toml_escape writes \" in the output file for " in values.
    # Note: the simple TOML subset parser does not unescape on read,
    # so we verify the raw file content rather than doing a roundtrip.
    var m = Manifest()
    m.name = String("pkg")
    m.version = String("0.1.0")
    m.description = String('Say "hello"')
    m.mojo_requires = String(">=0.26.1")
    m.platforms.append("linux-64")
    manifest_write(m, "/tmp/test_manifest_escape_dq.toml")
    var content = fs_read_file("/tmp/test_manifest_escape_dq.toml")
    assert_contains(content, "\\\"", "escape double-quote: written as \\\"")
    print("PASS: test_escape_double_quote_written")


fn test_escape_backslash_written() raises:
    # Verify that _toml_escape writes \\ in the output file for \ in values.
    var m = Manifest()
    m.name = String("pkg")
    m.version = String("0.1.0")
    m.description = String("path\\to\\file")
    m.mojo_requires = String(">=0.26.1")
    m.platforms.append("linux-64")
    manifest_write(m, "/tmp/test_manifest_escape_bs.toml")
    var content = fs_read_file("/tmp/test_manifest_escape_bs.toml")
    assert_contains(content, "\\\\", "escape backslash: written as \\\\")
    print("PASS: test_escape_backslash_written")


fn test_c_dep_plain_string() raises:
    var toml = String("""
[package]
name = "tcp"
version = "1.0.0"

[mojo]
requires = ">=0.26.1"

[c-dependencies]
errno_helper = "errno_helper.c"
""")
    fs_write_file("/tmp/test_manifest_cdep_plain.toml", toml)
    var m = manifest_parse("/tmp/test_manifest_cdep_plain.toml")
    assert_int_eq(len(m.c_deps), 1, "c_dep plain: one c-dep")
    assert_eq(m.c_deps[0].name, "errno_helper", "c_dep plain: name")
    assert_eq(m.c_deps[0].source, "errno_helper.c", "c_dep plain: source")
    print("PASS: test_c_dep_plain_string")


fn test_c_dep_inline_table() raises:
    var toml = String("""
[package]
name = "tcp"
version = "1.0.0"

[mojo]
requires = ">=0.26.1"

[c-dependencies]
errno_helper = { source = "errno_helper.c" }
""")
    fs_write_file("/tmp/test_manifest_cdep_inline.toml", toml)
    var m = manifest_parse("/tmp/test_manifest_cdep_inline.toml")
    assert_int_eq(len(m.c_deps), 1, "c_dep inline: one c-dep")
    assert_eq(m.c_deps[0].name, "errno_helper", "c_dep inline: name")
    assert_eq(m.c_deps[0].source, "errno_helper.c", "c_dep inline: source")
    print("PASS: test_c_dep_inline_table")


fn test_write_c_deps() raises:
    var m = Manifest()
    m.name = String("tcp")
    m.version = String("1.0.0")
    m.mojo_requires = String(">=0.26.1")
    m.platforms.append("linux-64")
    m.c_deps.append(CDependency("errno_helper", "errno_helper.c"))
    manifest_write(m, "/tmp/test_manifest_write_cdeps.toml")
    var m2 = manifest_parse("/tmp/test_manifest_write_cdeps.toml")
    assert_int_eq(len(m2.c_deps), 1, "write c_deps: one c-dep read back")
    assert_eq(m2.c_deps[0].name, "errno_helper", "write c_deps: name")
    assert_eq(m2.c_deps[0].source, "errno_helper.c", "write c_deps: source")
    print("PASS: test_write_c_deps")


fn test_add_dep_preserves_others() raises:
    var m = Manifest()
    m.name = String("test")
    m.version = String("0.1.0")
    m.mojo_requires = String(">=0.26.1")
    m.platforms.append("linux-64")
    manifest_add_dep(m, "tls", "Mosaad-M/tls", ">=1.0.0")
    manifest_add_dep(m, "tcp", "Mosaad-M/tcp", ">=1.0.0")
    # Update tls — tcp should still be there
    manifest_add_dep(m, "tls", "Mosaad-M/tls", ">=2.0.0")
    assert_int_eq(len(m.deps), 2, "add_dep preserves: still 2 deps")
    # Find tcp
    var found_tcp = False
    for i in range(len(m.deps)):
        if m.deps[i].name == "tcp":
            found_tcp = True
    assert_int_eq(1 if found_tcp else 0, 1, "add_dep preserves: tcp still present")
    print("PASS: test_add_dep_preserves_others")


fn main() raises:
    print("=== Manifest Tests ===")
    test_parse_full()
    test_parse_c_deps()
    test_manifest_roundtrip()
    test_manifest_add_dep()
    # New expanded tests
    test_no_description()
    test_no_license()
    test_multiple_platforms()
    test_empty_deps()
    test_no_c_deps_section()
    test_escape_double_quote_written()
    test_escape_backslash_written()
    test_c_dep_plain_string()
    test_c_dep_inline_table()
    test_write_c_deps()
    test_add_dep_preserves_others()
    print("")
    print("All manifest tests passed!")

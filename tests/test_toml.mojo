# tests/test_toml.mojo
# Tests for the TOML subset parser.

from toml import toml_parse, toml_get, toml_get_or, toml_has_section, toml_get_inline, toml_section_keys


def assert_eq(actual: String, expected: String, label: String) raises:
    if actual != expected:
        raise Error(label + ": expected '" + expected + "', got '" + actual + "'")


def assert_true(val: Bool, label: String) raises:
    if not val:
        raise Error(label + ": expected True, got False")


def assert_false(val: Bool, label: String) raises:
    if val:
        raise Error(label + ": expected False, got True")


def test_simple_kv() raises:
    var src = String("""
[package]
name = "hello"
version = "1.2.3"
description = "A test package"
""")
    var doc = toml_parse(src)
    assert_eq(toml_get(doc, "package", "name"), "hello", "simple name")
    assert_eq(toml_get(doc, "package", "version"), "1.2.3", "simple version")
    assert_eq(toml_get(doc, "package", "description"), "A test package", "simple description")
    print("PASS: test_simple_kv")


def test_missing_key() raises:
    var src = String("[package]\nname = \"x\"\n")
    var doc = toml_parse(src)
    assert_eq(toml_get_or(doc, "package", "missing", "default"), "default", "missing key default")
    print("PASS: test_missing_key")


def test_has_section() raises:
    var src = String("[package]\nname = \"x\"\n\n[dependencies]\ntls = \">=1.0.0\"\n")
    var doc = toml_parse(src)
    assert_true(toml_has_section(doc, "package"), "has [package]")
    assert_true(toml_has_section(doc, "dependencies"), "has [dependencies]")
    assert_false(toml_has_section(doc, "nonexistent"), "no [nonexistent]")
    print("PASS: test_has_section")


def test_inline_table() raises:
    var src = String("""
[dependencies]
tls = { git = "Mosaad-M/tls", version = ">=1.0.0" }
tcp = { git = "Mosaad-M/tcp", version = "^2.0.0" }
""")
    var doc = toml_parse(src)
    assert_eq(toml_get_inline(doc, "dependencies", "tls", "git"), "Mosaad-M/tls", "inline tls.git")
    assert_eq(toml_get_inline(doc, "dependencies", "tls", "version"), ">=1.0.0", "inline tls.version")
    assert_eq(toml_get_inline(doc, "dependencies", "tcp", "git"), "Mosaad-M/tcp", "inline tcp.git")
    assert_eq(toml_get_inline(doc, "dependencies", "tcp", "version"), "^2.0.0", "inline tcp.version")
    print("PASS: test_inline_table")


def test_section_keys() raises:
    var src = String("""
[dependencies]
tls = { git = "Mosaad-M/tls", version = ">=1.0.0" }
tcp = { git = "Mosaad-M/tcp", version = ">=1.0.0" }
""")
    var doc = toml_parse(src)
    var keys = toml_section_keys(doc, "dependencies")
    # Should have exactly 2 keys (the inline table marker)
    var found_tls = False
    var found_tcp = False
    for k in keys:
        if k == "tls":
            found_tls = True
        if k == "tcp":
            found_tcp = True
    assert_true(found_tls, "section keys contains tls")
    assert_true(found_tcp, "section keys contains tcp")
    print("PASS: test_section_keys")


def test_comment_stripping() raises:
    var src = String("""
[package]
name = "test"  # this is a comment
version = "0.1.0"
""")
    var doc = toml_parse(src)
    assert_eq(toml_get(doc, "package", "name"), "test", "comment stripped")
    print("PASS: test_comment_stripping")


def test_unquoted_value() raises:
    var src = String("""
[mojo]
requires = ">=0.26.1"
[c-dependencies]
errno_helper = "errno_helper.c"
""")
    var doc = toml_parse(src)
    assert_eq(toml_get(doc, "mojo", "requires"), ">=0.26.1", "mojo.requires")
    assert_eq(toml_get(doc, "c-dependencies", "errno_helper"), "errno_helper.c", "c-dep value")
    print("PASS: test_unquoted_value")


def test_full_mojoproject() raises:
    var src = String("""
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
url    = { git = "Mosaad-M/url",    version = ">=1.0.0" }
json   = { git = "Mosaad-M/json",   version = ">=1.0.0" }
""")
    var doc = toml_parse(src)
    assert_eq(toml_get(doc, "package", "name"), "requests", "full name")
    assert_eq(toml_get(doc, "package", "license"), "MIT", "full license")
    assert_eq(toml_get(doc, "mojo", "requires"), ">=0.26.1", "full mojo.requires")
    assert_eq(toml_get_inline(doc, "dependencies", "json", "git"), "Mosaad-M/json", "full json.git")
    print("PASS: test_full_mojoproject")


def assert_int_eq(a: Int, b: Int, label: String) raises:
    if a != b:
        raise Error("FAIL: " + label + " — expected " + String(b) + ", got " + String(a))


def test_comment_on_own_line() raises:
    var src = String("""
[package]
# this entire line is a comment
name = "mypkg"
version = "0.1.0"
""")
    var doc = toml_parse(src)
    assert_eq(toml_get(doc, "package", "name"), "mypkg", "comment on own line ignored")
    print("PASS: test_comment_on_own_line")


def test_comment_after_value() raises:
    var src = String("""
[package]
name = "test" # inline comment
version = "0.1.0"
""")
    var doc = toml_parse(src)
    # Comment should be stripped, value should be exactly "test"
    assert_eq(toml_get(doc, "package", "name"), "test", "inline comment stripped from value")
    print("PASS: test_comment_after_value")


def test_toml_get_raises_on_missing() raises:
    var src = String("[package]\nname = \"x\"\n")
    var doc = toml_parse(src)
    var raised = False
    try:
        _ = toml_get(doc, "package", "nonexistent_key")
    except:
        raised = True
    if not raised:
        raise Error("FAIL: toml_get should raise on missing key")
    print("PASS: test_toml_get_raises_on_missing")


def test_empty_string_value() raises:
    var src = String("[package]\ndescription = \"\"\n")
    var doc = toml_parse(src)
    assert_eq(toml_get(doc, "package", "description"), "", "empty string value")
    print("PASS: test_empty_string_value")


def test_spaces_around_equals() raises:
    var src = String("[package]\nname   =   \"spaced\"\n")
    var doc = toml_parse(src)
    assert_eq(toml_get(doc, "package", "name"), "spaced", "spaces around = ignored")
    print("PASS: test_spaces_around_equals")


def test_inline_table_three_fields() raises:
    var src = String("""
[dependencies]
mypkg = { git = "Org/repo", version = ">=1.0.0", channel = "nightly" }
""")
    var doc = toml_parse(src)
    assert_eq(toml_get_inline(doc, "dependencies", "mypkg", "git"), "Org/repo", "3-field inline: git")
    assert_eq(toml_get_inline(doc, "dependencies", "mypkg", "version"), ">=1.0.0", "3-field inline: version")
    assert_eq(toml_get_inline(doc, "dependencies", "mypkg", "channel"), "nightly", "3-field inline: channel")
    print("PASS: test_inline_table_three_fields")


def test_has_section_missing() raises:
    var src = String("[package]\nname = \"x\"\n")
    var doc = toml_parse(src)
    assert_false(toml_has_section(doc, "dependencies"), "missing section returns false")
    print("PASS: test_has_section_missing")


def test_has_section_present() raises:
    var src = String("[package]\nname = \"x\"\n\n[mojo]\nrequires = \">=0.26.1\"\n")
    var doc = toml_parse(src)
    assert_true(toml_has_section(doc, "mojo"), "present section returns true")
    print("PASS: test_has_section_present")


def test_section_keys_count() raises:
    var src = String("""
[package]
name = "x"
version = "0.1.0"
license = "MIT"
""")
    var doc = toml_parse(src)
    var keys = toml_section_keys(doc, "package")
    assert_int_eq(len(keys), 3, "section keys count: 3 keys")
    print("PASS: test_section_keys_count")


def test_section_keys_names() raises:
    var src = String("[mojo]\nrequires = \">=0.26.1\"\n")
    var doc = toml_parse(src)
    var keys = toml_section_keys(doc, "mojo")
    var found = False
    for k in keys:
        if k == "requires":
            found = True
    assert_true(found, "section keys names: 'requires' found")
    print("PASS: test_section_keys_names")


def test_two_sections_independent() raises:
    var src = String("""
[package]
name = "pkg"
version = "1.0.0"

[mojo]
requires = ">=0.26.1"
""")
    var doc = toml_parse(src)
    assert_eq(toml_get(doc, "package", "name"), "pkg", "two sections: package.name")
    assert_eq(toml_get(doc, "mojo", "requires"), ">=0.26.1", "two sections: mojo.requires")
    print("PASS: test_two_sections_independent")


def main() raises:
    print("=== TOML Parser Tests ===")
    test_simple_kv()
    test_missing_key()
    test_has_section()
    test_inline_table()
    test_section_keys()
    test_comment_stripping()
    test_unquoted_value()
    test_full_mojoproject()
    # New expanded tests
    test_comment_on_own_line()
    test_comment_after_value()
    test_toml_get_raises_on_missing()
    test_empty_string_value()
    test_spaces_around_equals()
    test_inline_table_three_fields()
    test_has_section_missing()
    test_has_section_present()
    test_section_keys_count()
    test_section_keys_names()
    test_two_sections_independent()
    print("")
    print("All TOML tests passed!")

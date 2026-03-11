# tests/test_resolver.mojo
# Tests for the semver parser and constraint checker (no network needed).

from resolver import semver_parse, semver_satisfies, SemVer


fn assert_true(val: Bool, label: String) raises:
    if not val:
        raise Error("FAIL: " + label + " — expected True, got False")


fn assert_false(val: Bool, label: String) raises:
    if val:
        raise Error("FAIL: " + label + " — expected False, got True")


fn assert_eq_str(a: String, b: String, label: String) raises:
    if a != b:
        raise Error("FAIL: " + label + " — expected '" + b + "', got '" + a + "'")


fn test_semver_parse() raises:
    var v = semver_parse("1.2.3")
    assert_eq_str(String(v.major) + "." + String(v.minor) + "." + String(v.patch), "1.2.3", "parse 1.2.3")

    var v2 = semver_parse("v2.0.0")
    assert_eq_str(String(v2.major), "2", "parse v2.0.0 major")

    var v3 = semver_parse("0.26.1")
    assert_eq_str(String(v3.patch), "1", "parse 0.26.1 patch")

    var v4 = semver_parse("1.0")
    assert_eq_str(String(v4.patch), "0", "parse 1.0 patch defaults to 0")

    print("PASS: test_semver_parse")


fn test_gte_constraint() raises:
    assert_true(semver_satisfies("1.0.0", ">=1.0.0"), ">=1.0.0 exact")
    assert_true(semver_satisfies("1.2.3", ">=1.0.0"), ">=1.0.0 higher")
    assert_true(semver_satisfies("2.0.0", ">=1.0.0"), ">=1.0.0 major higher")
    assert_false(semver_satisfies("0.9.9", ">=1.0.0"), ">=1.0.0 lower")
    print("PASS: test_gte_constraint")


fn test_caret_constraint() raises:
    assert_true(semver_satisfies("1.0.0", "^1.0.0"), "^1.0.0 exact")
    assert_true(semver_satisfies("1.5.3", "^1.0.0"), "^1.0.0 minor higher")
    assert_true(semver_satisfies("1.99.99", "^1.0.0"), "^1.0.0 near boundary")
    assert_false(semver_satisfies("2.0.0", "^1.0.0"), "^1.0.0 next major")
    assert_false(semver_satisfies("0.9.0", "^1.0.0"), "^1.0.0 below")
    print("PASS: test_caret_constraint")


fn test_eq_constraint() raises:
    assert_true(semver_satisfies("1.2.3", "=1.2.3"), "=1.2.3 exact")
    assert_false(semver_satisfies("1.2.4", "=1.2.3"), "=1.2.3 higher patch")
    assert_false(semver_satisfies("1.2.2", "=1.2.3"), "=1.2.3 lower patch")
    print("PASS: test_eq_constraint")


fn test_lt_gt_constraint() raises:
    assert_true(semver_satisfies("1.5.0", ">1.0.0"), ">1.0.0")
    assert_false(semver_satisfies("1.0.0", ">1.0.0"), ">1.0.0 not strictly greater")
    assert_true(semver_satisfies("0.9.0", "<1.0.0"), "<1.0.0")
    assert_false(semver_satisfies("1.0.0", "<1.0.0"), "<1.0.0 not strictly less")
    assert_true(semver_satisfies("1.0.0", "<=1.0.0"), "<=1.0.0 exact")
    assert_true(semver_satisfies("0.9.9", "<=1.0.0"), "<=1.0.0 below")
    print("PASS: test_lt_gt_constraint")


fn test_empty_constraint() raises:
    assert_true(semver_satisfies("1.0.0", ""), "empty constraint always true")
    assert_true(semver_satisfies("99.99.99", ""), "empty constraint any version")
    print("PASS: test_empty_constraint")


fn test_semver_ordering() raises:
    var a = SemVer(1, 0, 0)
    var b = SemVer(1, 0, 1)
    var c = SemVer(2, 0, 0)
    assert_true(a < b, "1.0.0 < 1.0.1")
    assert_true(b < c, "1.0.1 < 2.0.0")
    assert_true(a < c, "1.0.0 < 2.0.0")
    assert_false(c < a, "2.0.0 not < 1.0.0")
    assert_true(a == a, "1.0.0 == 1.0.0")
    print("PASS: test_semver_ordering")


fn main() raises:
    print("=== Resolver / SemVer Tests ===")
    test_semver_parse()
    test_gte_constraint()
    test_caret_constraint()
    test_eq_constraint()
    test_lt_gt_constraint()
    test_empty_constraint()
    test_semver_ordering()
    print("")
    print("All resolver tests passed!")

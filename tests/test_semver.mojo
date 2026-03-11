# tests/test_semver.mojo
# Comprehensive tests for semver parsing and constraint checking.
# Replaces test_resolver.mojo (which is retired).

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


fn assert_int_eq(a: Int, b: Int, label: String) raises:
    if a != b:
        raise Error("FAIL: " + label + " — expected " + String(b) + ", got " + String(a))


# ─── semver_parse ──────────────────────────────────────────────────────────────

fn test_parse_basic() raises:
    var v = semver_parse("1.2.3")
    assert_int_eq(v.major, 1, "parse 1.2.3 major")
    assert_int_eq(v.minor, 2, "parse 1.2.3 minor")
    assert_int_eq(v.patch, 3, "parse 1.2.3 patch")
    print("PASS: test_parse_basic")


fn test_parse_v_prefix() raises:
    var v = semver_parse("v2.3.4")
    assert_int_eq(v.major, 2, "parse v2.3.4 major")
    assert_int_eq(v.minor, 3, "parse v2.3.4 minor")
    assert_int_eq(v.patch, 4, "parse v2.3.4 patch")
    print("PASS: test_parse_v_prefix")


fn test_parse_V_prefix() raises:
    var v = semver_parse("V1.0.0")
    assert_int_eq(v.major, 1, "parse V1.0.0 major")
    print("PASS: test_parse_V_prefix")


fn test_parse_zeros() raises:
    var v = semver_parse("0.0.0")
    assert_int_eq(v.major, 0, "parse 0.0.0 major")
    assert_int_eq(v.minor, 0, "parse 0.0.0 minor")
    assert_int_eq(v.patch, 0, "parse 0.0.0 patch")
    print("PASS: test_parse_zeros")


fn test_parse_large() raises:
    var v = semver_parse("10.20.30")
    assert_int_eq(v.major, 10, "parse 10.20.30 major")
    assert_int_eq(v.minor, 20, "parse 10.20.30 minor")
    assert_int_eq(v.patch, 30, "parse 10.20.30 patch")
    print("PASS: test_parse_large")


fn test_parse_two_part() raises:
    var v = semver_parse("1.0")
    assert_int_eq(v.major, 1, "parse 1.0 major")
    assert_int_eq(v.minor, 0, "parse 1.0 minor")
    assert_int_eq(v.patch, 0, "parse 1.0 patch defaults to 0")
    print("PASS: test_parse_two_part")


# ─── SemVer.__str__ ────────────────────────────────────────────────────────────

fn test_semver_str() raises:
    var v = SemVer(1, 2, 3)
    assert_eq_str(v.__str__(), "1.2.3", "__str__ 1.2.3")
    var v2 = SemVer(0, 0, 0)
    assert_eq_str(v2.__str__(), "0.0.0", "__str__ 0.0.0")
    print("PASS: test_semver_str")


# ─── SemVer comparisons ────────────────────────────────────────────────────────

fn test_semver_ordering() raises:
    var a = SemVer(1, 0, 0)
    var b = SemVer(1, 0, 1)
    var c = SemVer(2, 0, 0)
    assert_true(a < b, "1.0.0 < 1.0.1")
    assert_true(b < c, "1.0.1 < 2.0.0")
    assert_true(a < c, "1.0.0 < 2.0.0")
    assert_false(c < a, "2.0.0 not < 1.0.0")
    assert_false(a < a, "1.0.0 not < 1.0.0 (equal)")
    print("PASS: test_semver_ordering")


fn test_semver_equality() raises:
    var a = SemVer(1, 0, 0)
    var b = SemVer(1, 0, 0)
    var c = SemVer(1, 0, 1)
    assert_true(a == b, "1.0.0 == 1.0.0")
    assert_false(a == c, "1.0.0 != 1.0.1")
    print("PASS: test_semver_equality")


fn test_semver_le() raises:
    var a = SemVer(1, 0, 0)
    var b = SemVer(1, 0, 1)
    assert_true(a <= a, "1.0.0 <= 1.0.0")
    assert_true(a <= b, "1.0.0 <= 1.0.1")
    assert_false(b <= a, "1.0.1 not <= 1.0.0")
    print("PASS: test_semver_le")


# ─── >= constraint ─────────────────────────────────────────────────────────────

fn test_gte_constraint() raises:
    assert_true(semver_satisfies("1.0.0", ">=1.0.0"), ">=1.0.0 exact")
    assert_true(semver_satisfies("1.2.3", ">=1.0.0"), ">=1.0.0 higher")
    assert_true(semver_satisfies("2.0.0", ">=1.0.0"), ">=1.0.0 major higher")
    assert_false(semver_satisfies("0.9.9", ">=1.0.0"), ">=1.0.0 lower")
    print("PASS: test_gte_constraint")


# ─── > constraint ─────────────────────────────────────────────────────────────

fn test_gt_constraint() raises:
    assert_true(semver_satisfies("2.0.0", ">1.0.0"), ">1.0.0 higher")
    assert_false(semver_satisfies("1.0.0", ">1.0.0"), ">1.0.0 equal not satisfied")
    assert_false(semver_satisfies("0.9.0", ">1.0.0"), ">1.0.0 lower")
    print("PASS: test_gt_constraint")


# ─── < constraint ─────────────────────────────────────────────────────────────

fn test_lt_constraint() raises:
    assert_true(semver_satisfies("0.9.0", "<1.0.0"), "<1.0.0 lower")
    assert_false(semver_satisfies("1.0.0", "<1.0.0"), "<1.0.0 equal not satisfied")
    assert_false(semver_satisfies("1.1.0", "<1.0.0"), "<1.0.0 higher")
    print("PASS: test_lt_constraint")


# ─── <= constraint ────────────────────────────────────────────────────────────

fn test_lte_constraint() raises:
    assert_true(semver_satisfies("1.0.0", "<=1.0.0"), "<=1.0.0 exact")
    assert_true(semver_satisfies("0.9.0", "<=1.0.0"), "<=1.0.0 below")
    assert_false(semver_satisfies("1.0.1", "<=1.0.0"), "<=1.0.0 above")
    print("PASS: test_lte_constraint")


# ─── = exact constraint ───────────────────────────────────────────────────────

fn test_eq_constraint() raises:
    assert_true(semver_satisfies("1.2.3", "=1.2.3"), "=1.2.3 exact")
    assert_false(semver_satisfies("1.2.4", "=1.2.3"), "=1.2.3 higher patch")
    assert_false(semver_satisfies("1.2.2", "=1.2.3"), "=1.2.3 lower patch")
    print("PASS: test_eq_constraint")


# ─── ^ caret constraint ───────────────────────────────────────────────────────

fn test_caret_constraint() raises:
    assert_true(semver_satisfies("1.0.0", "^1.0.0"), "^1.0.0 exact")
    assert_true(semver_satisfies("1.2.0", "^1.0.0"), "^1.0.0 minor higher")
    assert_true(semver_satisfies("1.0.5", "^1.0.0"), "^1.0.0 patch higher")
    assert_true(semver_satisfies("1.99.99", "^1.0.0"), "^1.0.0 near boundary")
    assert_false(semver_satisfies("2.0.0", "^1.0.0"), "^1.0.0 next major fails")
    assert_false(semver_satisfies("0.9.0", "^1.0.0"), "^1.0.0 below fails")
    print("PASS: test_caret_constraint")


# ─── empty constraint ─────────────────────────────────────────────────────────

fn test_empty_constraint() raises:
    assert_true(semver_satisfies("1.0.0", ""), "empty constraint: always true")
    assert_true(semver_satisfies("99.99.99", ""), "empty constraint: any version")
    assert_true(semver_satisfies("0.0.0", ""), "empty constraint: zero version")
    print("PASS: test_empty_constraint")


fn main() raises:
    print("=== SemVer Tests ===")
    test_parse_basic()
    test_parse_v_prefix()
    test_parse_V_prefix()
    test_parse_zeros()
    test_parse_large()
    test_parse_two_part()
    test_semver_str()
    test_semver_ordering()
    test_semver_equality()
    test_semver_le()
    test_gte_constraint()
    test_gt_constraint()
    test_lt_constraint()
    test_lte_constraint()
    test_eq_constraint()
    test_caret_constraint()
    test_empty_constraint()
    print("")
    print("All semver tests passed!")

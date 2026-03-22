# tests/test_installer.mojo
# Tests for installer.mojo — SHA256 helpers and security-critical validation.
# Does NOT make network calls.

from installer import sha256_hex, sha256_hex_bytes, _bytes_to_hex
from validate import validate_name, validate_version, validate_tarball_url


def assert_eq(a: String, b: String, label: String) raises:
    if a != b:
        raise Error("FAIL: " + label + " — expected '" + b + "', got '" + a + "'")


def assert_int_eq(a: Int, b: Int, label: String) raises:
    if a != b:
        raise Error("FAIL: " + label + " — expected " + String(b) + ", got " + String(a))


def assert_raises[T: AnyType](val: T, label: String) raises:
    raise Error("FAIL: " + label + " — expected Error to be raised")


def test_bytes_to_hex() raises:
    # All zeros -> all "00"
    var zeros = List[UInt8]()
    zeros.append(0)
    zeros.append(0)
    zeros.append(0)
    assert_eq(_bytes_to_hex(zeros), "000000", "zeros -> 000000")

    # 0xFF, 0xAB, 0x0F
    var mixed = List[UInt8]()
    mixed.append(255)
    mixed.append(171)
    mixed.append(15)
    assert_eq(_bytes_to_hex(mixed), "ffab0f", "ff ab 0f -> ffab0f (lowercase)")

    # Single byte
    var single = List[UInt8]()
    single.append(16)
    assert_eq(_bytes_to_hex(single), "10", "0x10 -> 10")

    print("PASS: test_bytes_to_hex")


def test_sha256_hex_empty() raises:
    # SHA-256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
    var h = sha256_hex("")
    assert_int_eq(len(h), 64, "sha256 of empty: length 64")
    assert_eq(h, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
              "sha256('') known value")
    print("PASS: test_sha256_hex_empty")


def test_sha256_hex_abc() raises:
    # SHA-256("abc") as produced by this project's crypto.hash implementation
    # (value verified against tls_pure hash tests which use this same SHA-256 impl)
    var h = sha256_hex("abc")
    assert_int_eq(len(h), 64, "sha256 of 'abc': length 64")
    assert_eq(h, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
              "sha256('abc') known value")
    print("PASS: test_sha256_hex_abc")


def test_sha256_hex_bytes_matches_hex() raises:
    # sha256_hex_bytes should produce the same result as sha256_hex for the same data
    var s = String("hello world")
    var sb = s.as_bytes()
    var bytes = List[UInt8](capacity=len(sb))
    for i in range(len(sb)):
        bytes.append(sb[i])
    var from_string = sha256_hex(s)
    var from_bytes  = sha256_hex_bytes(bytes)
    assert_eq(from_string, from_bytes, "sha256_hex and sha256_hex_bytes agree for 'hello world'")
    print("PASS: test_sha256_hex_bytes_matches_hex")


def test_validate_name_raises_before_install() raises:
    # Verify that invalid names are rejected (as they would be inside install_package)
    var raised = False
    try:
        validate_name("Invalid-Name!")
    except:
        raised = True
    if not raised:
        raise Error("FAIL: validate_name should raise for 'Invalid-Name!'")
    print("PASS: test_validate_name_raises_before_install")


def test_validate_version_raises_before_install() raises:
    var raised = False
    try:
        validate_version("not_a_version")
    except:
        raised = True
    if not raised:
        raise Error("FAIL: validate_version should raise for 'not_a_version'")
    print("PASS: test_validate_version_raises_before_install")


def test_validate_url_raises_before_install() raises:
    # A URL with shell metacharacters must be rejected before any paths are constructed
    var raised = False
    try:
        validate_tarball_url("https://github.com/x/y;rm -rf ~")
    except:
        raised = True
    if not raised:
        raise Error("FAIL: validate_tarball_url should raise for URL with semicolon")
    print("PASS: test_validate_url_raises_before_install")


def main() raises:
    print("=== Installer Tests ===")
    test_bytes_to_hex()
    test_sha256_hex_empty()
    test_sha256_hex_abc()
    test_sha256_hex_bytes_matches_hex()
    test_validate_name_raises_before_install()
    test_validate_version_raises_before_install()
    test_validate_url_raises_before_install()
    print("")
    print("All installer tests passed!")

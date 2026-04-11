# tests/test_tcp.mojo
# Tests for tcp.mojo: platform constants, private-IP detection, DNS resolution.

from std.sys.info import CompilationTarget
from tcp import (
    _is_private_ip,
    _resolve_host,
    SOL_SOCKET,
    SO_RCVTIMEO,
    SO_SNDTIMEO,
)


def assert_true(val: Bool, label: String) raises:
    if not val:
        raise Error("FAIL: " + label + " — expected True, got False")


def assert_false(val: Bool, label: String) raises:
    if val:
        raise Error("FAIL: " + label + " — expected False, got True")


def assert_int_eq(a: Int, b: Int, label: String) raises:
    if a != b:
        raise Error(
            "FAIL: " + label + " — expected " + String(b) + ", got " + String(a)
        )


# ============================================================================
# Platform constant tests
# ============================================================================


def test_platform_constants() raises:
    """Verify SOL_SOCKET / SO_RCVTIMEO / SO_SNDTIMEO match the host OS values."""
    comptime if CompilationTarget.is_macos():
        assert_int_eq(Int(SOL_SOCKET),  0xFFFF,  "macOS SOL_SOCKET")
        assert_int_eq(Int(SO_RCVTIMEO), 0x1006,  "macOS SO_RCVTIMEO")
        assert_int_eq(Int(SO_SNDTIMEO), 0x1005,  "macOS SO_SNDTIMEO")
    else:
        assert_int_eq(Int(SOL_SOCKET),  1,  "Linux SOL_SOCKET")
        assert_int_eq(Int(SO_RCVTIMEO), 20, "Linux SO_RCVTIMEO")
        assert_int_eq(Int(SO_SNDTIMEO), 21, "Linux SO_SNDTIMEO")
    print("PASS: test_platform_constants")


# ============================================================================
# _is_private_ip tests
# ============================================================================
#
# sin_addr is stored in network byte order.  On little-endian (x86/ARM) the
# first octet lands in the lowest-order byte, so 127.0.0.1 is 0x0100007F.


def test_loopback() raises:
    # 127.0.0.1 → network bytes on LE: 0x0100007F
    assert_true(_is_private_ip(0x0100007F), "127.0.0.1 is private")
    print("PASS: test_loopback")


def test_private_10() raises:
    # 10.0.0.1 → 0x0100000A
    assert_true(_is_private_ip(0x0100000A), "10.0.0.1 is private")
    print("PASS: test_private_10")


def test_private_172() raises:
    # 172.16.0.1 → 0x010010AC
    assert_true(_is_private_ip(0x010010AC), "172.16.0.1 is private")
    # 172.31.0.1 → 0x01001FAC
    assert_true(_is_private_ip(0x01001FAC), "172.31.0.1 is private")
    # 172.32.0.1 → 0x010020AC (outside /12 — public)
    assert_false(_is_private_ip(0x010020AC), "172.32.0.1 is public")
    print("PASS: test_private_172")


def test_private_192_168() raises:
    # 192.168.1.1 → 0x0101A8C0
    assert_true(_is_private_ip(0x0101A8C0), "192.168.1.1 is private")
    print("PASS: test_private_192_168")


def test_link_local() raises:
    # 169.254.1.1 → 0x0101FEA9
    assert_true(_is_private_ip(0x0101FEA9), "169.254.1.1 is link-local")
    print("PASS: test_link_local")


def test_zero_network() raises:
    # 0.0.0.0 → 0x00000000
    assert_true(_is_private_ip(0x00000000), "0.0.0.0 is reserved")
    print("PASS: test_zero_network")


def test_public_ip() raises:
    # 8.8.8.8 → 0x08080808
    assert_false(_is_private_ip(0x08080808), "8.8.8.8 is public")
    # 1.1.1.1 → 0x01010101
    assert_false(_is_private_ip(0x01010101), "1.1.1.1 is public")
    print("PASS: test_public_ip")


# ============================================================================
# DNS resolution test (integration — requires network)
# ============================================================================


def test_resolve_host() raises:
    """Resolve raw.githubusercontent.com and confirm we get a non-zero address."""
    var addr = _resolve_host("raw.githubusercontent.com", 443)
    assert_true(addr.sin_addr != 0, "resolved IP is non-zero")
    # On macOS, sockaddr_in has a leading sin_len byte (uint8) before sin_family (uint8),
    # so the UInt16 sin_family field reads as (sin_len | sin_family<<8) = 528.
    # On Linux, sin_family (uint16) is 2 (AF_INET) directly.
    comptime if CompilationTarget.is_macos():
        # sin_family byte is the high byte of the UInt16 field: (val >> 8) & 0xFF == 2
        assert_true((Int(addr.sin_family) >> 8) & 0xFF == 2, "AF_INET family byte (macOS)")
    else:
        assert_int_eq(Int(addr.sin_family), 2, "AF_INET family")
    print("PASS: test_resolve_host")


def test_resolve_bad_host() raises:
    """Resolving a non-existent host must raise."""
    var raised = False
    try:
        _ = _resolve_host("this.host.does.not.exist.invalid", 443)
    except:
        raised = True
    assert_true(raised, "bad host raises Error")
    print("PASS: test_resolve_bad_host")


def main() raises:
    print("=== TCP Tests ===")
    test_platform_constants()
    test_loopback()
    test_private_10()
    test_private_172()
    test_private_192_168()
    test_link_local()
    test_zero_network()
    test_public_ip()
    test_resolve_host()
    test_resolve_bad_host()
    print("")
    print("All TCP tests passed!")

# tests/test_url.mojo
# Tests for the URL parser.

from url import parse_url, Url


def assert_eq(a: String, b: String, label: String) raises:
    if a != b:
        raise Error("FAIL: " + label + " — expected '" + b + "', got '" + a + "'")


def assert_int_eq(a: Int, b: Int, label: String) raises:
    if a != b:
        raise Error("FAIL: " + label + " — expected " + String(b) + ", got " + String(a))


def assert_true(val: Bool, label: String) raises:
    if not val:
        raise Error("FAIL: " + label + " — expected True, got False")


def test_scheme_https() raises:
    var u = parse_url("https://example.com/path")
    assert_eq(u.scheme, "https", "scheme https")
    print("PASS: test_scheme_https")


def test_scheme_http() raises:
    var u = parse_url("http://example.com/path")
    assert_eq(u.scheme, "http", "scheme http")
    print("PASS: test_scheme_http")


def test_host() raises:
    var u = parse_url("https://example.com/path")
    assert_eq(u.host, "example.com", "host extracted")
    print("PASS: test_host")


def test_path() raises:
    var u = parse_url("https://example.com/path/to/resource")
    assert_eq(u.path, "/path/to/resource", "path extracted")
    print("PASS: test_path")


def test_default_port_https() raises:
    var u = parse_url("https://example.com/x")
    assert_int_eq(u.port, 443, "default port https: 443")
    print("PASS: test_default_port_https")


def test_default_port_http() raises:
    var u = parse_url("http://example.com/x")
    assert_int_eq(u.port, 80, "default port http: 80")
    print("PASS: test_default_port_http")


def test_custom_port() raises:
    var u = parse_url("https://host:8443/x")
    assert_int_eq(u.port, 8443, "custom port: 8443")
    assert_eq(u.host, "host", "custom port: host")
    print("PASS: test_custom_port")


def test_query_string() raises:
    var u = parse_url("https://example.com/path?key=val&other=x")
    assert_eq(u.query, "key=val&other=x", "query string extracted")
    print("PASS: test_query_string")


def test_request_path_with_query() raises:
    var u = parse_url("https://example.com/path?key=val")
    assert_eq(u.request_path(), "/path?key=val", "request_path with query")
    print("PASS: test_request_path_with_query")


def test_request_path_no_query() raises:
    var u = parse_url("https://example.com/path")
    assert_eq(u.request_path(), "/path", "request_path without query")
    print("PASS: test_request_path_no_query")


def test_default_path() raises:
    var u = parse_url("https://example.com")
    assert_eq(u.path, "/", "default path is /")
    print("PASS: test_default_path")


def test_host_header_default_port() raises:
    var u = parse_url("https://example.com/x")
    assert_eq(u.host_header(), "example.com", "host_header: no port for 443")
    print("PASS: test_host_header_default_port")


def test_host_header_custom_port() raises:
    var u = parse_url("https://example.com:8443/x")
    assert_eq(u.host_header(), "example.com:8443", "host_header: custom port included")
    print("PASS: test_host_header_custom_port")


def main() raises:
    print("=== URL Parser Tests ===")
    test_scheme_https()
    test_scheme_http()
    test_host()
    test_path()
    test_default_port_https()
    test_default_port_http()
    test_custom_port()
    test_query_string()
    test_request_path_with_query()
    test_request_path_no_query()
    test_default_path()
    test_host_header_default_port()
    test_host_header_custom_port()
    print("")
    print("All URL tests passed!")

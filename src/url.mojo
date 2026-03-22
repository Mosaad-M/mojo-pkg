# ============================================================================
# url.mojo — URL Parser for HTTP Client
# ============================================================================
#
# Parses URLs into components: scheme, host, port, path, query.
# Pure string manipulation — no external dependencies.
#
# Supported formats:
#   http://example.com
#   http://example.com/path
#   http://example.com:8080/path?key=value
#   https://example.com/path?q=1&r=2
#
# ============================================================================


struct Url(Copyable, Movable):
    """Parsed URL components."""

    var scheme: String
    var host: String
    var port: Int
    var path: String
    var query: String
    var raw: String

    def __init__(out self):
        self.scheme = String("")
        self.host = String("")
        self.port = 80
        self.path = String("/")
        self.query = String("")
        self.raw = String("")

    def __copyinit__(out self, copy: Self):
        self.scheme = copy.scheme
        self.host = copy.host
        self.port = copy.port
        self.path = copy.path
        self.query = copy.query
        self.raw = copy.raw

    def __moveinit__(out self, deinit take: Self):
        self.scheme = take.scheme^
        self.host = take.host^
        self.port = take.port
        self.path = take.path^
        self.query = take.query^
        self.raw = take.raw^

    def request_path(self) -> String:
        """Return the path + query string for the HTTP request line.

        Examples:
            /path          -> "/path"
            /path?q=1      -> "/path?q=1"
            /              -> "/"
        """
        if len(self.query) > 0:
            return self.path + "?" + self.query
        return self.path

    def host_header(self) -> String:
        """Return the Host header value.

        Includes port only if it's non-standard (not 80 for http, not 443 for https).
        """
        if (self.scheme == "http" or self.scheme == "ws") and self.port != 80:
            return self.host + ":" + String(self.port)
        if (
            self.scheme == "https" or self.scheme == "wss"
        ) and self.port != 443:
            return self.host + ":" + String(self.port)
        return self.host


def _ptr_to_string(
    data_ptr: UnsafePointer[UInt8, _], start: Int, end: Int
) -> String:
    """Materialize a String from a pointer byte range [start, end)."""
    if start < 0 or start >= end:
        return String("")
    var result = List[UInt8](capacity=end - start)
    for i in range(start, end):
        result.append((data_ptr + i)[])
    return String(unsafe_from_utf8=result^)


def _find_scheme_sep(data_ptr: UnsafePointer[UInt8, _], data_len: Int) -> Int:
    """Find '://' in the URL. Returns position of ':' or -1."""
    if data_len < 3:
        return -1
    for i in range(data_len - 2):
        if (
            (data_ptr + i)[] == UInt8(ord(":"))
            and (data_ptr + i + 1)[] == UInt8(ord("/"))
            and (data_ptr + i + 2)[] == UInt8(ord("/"))
        ):
            return i
    return -1


def _find_char(
    data_ptr: UnsafePointer[UInt8, _], data_len: Int, c: UInt8, start: Int = 0
) -> Int:
    """Find first occurrence of byte c in pointer data starting at start."""
    for i in range(start, data_len):
        if (data_ptr + i)[] == c:
            return i
    return -1


def _parse_port(
    data_ptr: UnsafePointer[UInt8, _], start: Int, end: Int
) raises -> Int:
    """Parse a port number from pointer range [start, end).

    Validates port is 1-65535 and rejects overlong digit strings.
    """
    if start >= end:
        raise Error("empty port string")
    if end - start > 5:
        raise Error("port number too long")
    var result: Int = 0
    for i in range(start, end):
        var c = (data_ptr + i)[]
        if c < UInt8(ord("0")) or c > UInt8(ord("9")):
            raise Error(
                "invalid digit in port: " + _ptr_to_string(data_ptr, start, end)
            )
        result = result * 10 + Int(c - UInt8(ord("0")))
    if result < 1 or result > 65535:
        raise Error("port out of range (1-65535): " + String(result))
    return result


def _validate_host(host: String) raises:
    """Validate hostname contains no dangerous characters.

    Rejects null bytes, CR, LF, spaces, and slash which could enable
    injection attacks or protocol confusion.
    """
    var bytes = host.as_bytes()
    for i in range(len(host)):
        var b = bytes[i]
        if b == 0 or b == 13 or b == 10 or b == 32 or b == 47:
            # \0, \r, \n, space, /
            raise Error("invalid hostname: contains dangerous character")


def parse_url(raw_url: String) raises -> Url:
    """Parse a URL string into its components.

    Uses UnsafePointer for zero-copy parsing — converts the URL to a
    pointer once and uses pointer arithmetic throughout. Strings are
    only materialized when storing into Url struct fields.

    Args:
        raw_url: The URL to parse (e.g. "http://example.com:8080/path?q=1")

    Returns:
        Url struct with scheme, host, port, path, query fields

    Raises:
        Error if URL is malformed (missing scheme, empty host, etc.)
    """
    var url = Url()
    url.raw = raw_url

    # Convert to pointer once
    var raw_copy = raw_url
    var ptr = raw_copy.as_c_string_slice().unsafe_ptr().bitcast[UInt8]()
    var raw_len = len(raw_url)

    # Step 1: Find "://" to extract scheme
    var scheme_end = _find_scheme_sep(ptr, raw_len)
    if scheme_end < 0:
        raise Error("invalid URL: missing scheme (no '://' found)")

    url.scheme = _ptr_to_string(ptr, 0, scheme_end)
    if (
        url.scheme != "http"
        and url.scheme != "https"
        and url.scheme != "ws"
        and url.scheme != "wss"
    ):
        raise Error("unsupported scheme: " + url.scheme)

    # Step 2: Extract authority (host + optional port)
    var authority_start = scheme_end + 3  # skip "://"
    if authority_start >= raw_len:
        raise Error("invalid URL: empty authority")

    # Find end of authority: first "/" or "?" or end of string
    var authority_end = raw_len
    var slash_pos = _find_char(ptr, raw_len, UInt8(ord("/")), authority_start)
    var question_pos = _find_char(ptr, raw_len, UInt8(ord("?")), authority_start)

    if slash_pos >= 0 and (question_pos < 0 or slash_pos < question_pos):
        authority_end = slash_pos
    elif question_pos >= 0:
        authority_end = question_pos

    if authority_end == authority_start:
        raise Error("invalid URL: empty host")

    # Step 3: Split authority [authority_start..authority_end) into host and port
    var colon_pos = _find_char(ptr, authority_end, UInt8(ord(":")), authority_start)
    if colon_pos >= 0:
        url.host = _ptr_to_string(ptr, authority_start, colon_pos)
        url.port = _parse_port(ptr, colon_pos + 1, authority_end)
    else:
        url.host = _ptr_to_string(ptr, authority_start, authority_end)
        # Default port based on scheme
        if url.scheme == "https" or url.scheme == "wss":
            url.port = 443
        else:
            url.port = 80

    if len(url.host) == 0:
        raise Error("invalid URL: empty host")

    # Validate host: no null bytes, CR, LF, or spaces
    _validate_host(url.host)

    # Step 4: Extract path and query
    var rest_start = authority_end
    if rest_start < raw_len:
        var q_pos = _find_char(ptr, raw_len, UInt8(ord("?")), rest_start)
        if q_pos >= 0:
            url.path = _ptr_to_string(ptr, rest_start, q_pos)
            url.query = _ptr_to_string(ptr, q_pos + 1, raw_len)
        else:
            url.path = _ptr_to_string(ptr, rest_start, raw_len)
    else:
        url.path = String("/")

    # Default empty path to "/"
    if len(url.path) == 0:
        url.path = String("/")

    return url^

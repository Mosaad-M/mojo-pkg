# src/validate.mojo
# Input validation for package names, versions, URLs, and C dep sources.
# Enforced at all trust boundaries: registry fetch, install, manifest parse.


def validate_name(name: String) raises:
    """Reject invalid package names.
    Allowed: [a-z0-9][a-z0-9_-]*, max 64 chars.
    Note: only ASCII characters are checked; non-ASCII bytes are rejected implicitly
    because they fall outside all allowed ranges."""
    var bytes = name.as_bytes()
    var n = len(bytes)
    if n == 0 or n > 64:
        raise Error(
            "Invalid package name: '" + name + "' (must be 1-64 chars)"
        )
    for i in range(n):
        var b = bytes[i]
        var ok = False
        if b >= 97 and b <= 122:  # a-z
            ok = True
        elif b >= 48 and b <= 57:  # 0-9
            ok = True
        elif i > 0 and b == 95:  # _ (not first char)
            ok = True
        elif i > 0 and b == 45:  # - (not first char)
            ok = True
        if not ok:
            raise Error(
                "Invalid package name: '"
                + name
                + "' (must match [a-z0-9][a-z0-9_-]*)"
            )


def validate_version(version: String) raises:
    """Reject versions that aren't X.Y.Z (digits and dots only)."""
    var bytes = version.as_bytes()
    var n = len(bytes)
    if n == 0:
        raise Error("Invalid version: empty string")
    if n > 32:
        raise Error("Invalid version: '" + version + "' (max 32 chars)")
    var dots = 0
    for i in range(n):
        var b = bytes[i]
        if b >= 48 and b <= 57:  # 0-9
            pass
        elif b == 46:  # .
            dots += 1
        else:
            raise Error(
                "Invalid version: '"
                + version
                + "' (must be X.Y.Z with digits only)"
            )
    if dots != 2:
        raise Error(
            "Invalid version: '" + version + "' (must be X.Y.Z format)"
        )
    # Reject leading/trailing dots and consecutive dots (empty components)
    if bytes[0] == 46:
        raise Error("Invalid version: '" + version + "' (leading dot)")
    if bytes[n - 1] == 46:
        raise Error("Invalid version: '" + version + "' (trailing dot)")
    for i in range(n - 1):
        if bytes[i] == 46 and bytes[i + 1] == 46:
            raise Error("Invalid version: '" + version + "' (consecutive dots)")


def validate_tarball_url(url: String) raises:
    """Reject tarball URLs that don't start with https://github.com/ and contain
    any character outside the strict allowlist A-Za-z0-9/-_.:%=?&#@."""
    alias PREFIX = "https://github.com/"
    var prefix_bytes = PREFIX.as_bytes()
    var url_bytes = url.as_bytes()
    if len(url_bytes) < len(prefix_bytes):
        raise Error(
            "Insecure tarball URL: '"
            + url
            + "' (must start with https://github.com/)"
        )
    for i in range(len(prefix_bytes)):
        if url_bytes[i] != prefix_bytes[i]:
            raise Error(
                "Insecure tarball URL: '"
                + url
                + "' (must start with https://github.com/)"
            )
    # Require at least one path character after the prefix
    if len(url_bytes) <= len(prefix_bytes):
        raise Error("Insecure tarball URL: no path after github.com/")
    # Strict allowlist: A-Z a-z 0-9 / - _ . : % = ? & # @
    for i in range(len(prefix_bytes), len(url_bytes)):
        var b = url_bytes[i]
        var ok = (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or  # A-Z, a-z
                 (b >= 48 and b <= 57) or  # 0-9
                 b == 47 or b == 45 or b == 95 or b == 46 or b == 58 or  # / - _ . :
                 b == 37 or b == 61 or b == 63 or b == 38 or b == 35 or  # % = ? & #
                 b == 64                                                    # @
        if not ok:
            raise Error("Insecure tarball URL: contains disallowed character")


def validate_cdep_name(name: String) raises:
    """Reject C dep library names that could inject shell flags.
    Allowed: [a-z0-9_-]+, max 64 chars. No spaces or special characters."""
    var bytes = name.as_bytes()
    var n = len(bytes)
    if n == 0 or n > 64:
        raise Error(
            "Invalid C dep name: '" + name + "' (must be 1-64 chars)"
        )
    for i in range(n):
        var b = bytes[i]
        var ok = False
        if b >= 97 and b <= 122:  # a-z
            ok = True
        elif b >= 65 and b <= 90:  # A-Z
            ok = True
        elif b >= 48 and b <= 57:  # 0-9
            ok = True
        elif b == 95:  # _
            ok = True
        elif b == 45:  # -
            ok = True
        if not ok:
            raise Error(
                "Invalid C dep name: '"
                + name
                + "' (only a-zA-Z0-9_- allowed)"
            )


def validate_cdep_source(source: String) raises:
    """Reject C dep source paths containing '/' or '..' (path traversal)."""
    var bytes = source.as_bytes()
    var n = len(bytes)
    if n == 0:
        raise Error("Invalid C dep source: empty string")
    for i in range(n):
        if bytes[i] == 47:  # /
            raise Error(
                "Invalid C dep source: '"
                + source
                + "' (must be a basename — no path separators)"
            )
    if source.find("..") >= 0:
        raise Error(
            "Invalid C dep source: '"
            + source
            + "' (path traversal '..' not allowed)"
        )

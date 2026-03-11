# src/validate.mojo
# Input validation for package names, versions, URLs, and C dep sources.
# Enforced at all trust boundaries: registry fetch, install, manifest parse.


fn validate_name(name: String) raises:
    """Reject invalid package names.
    Allowed: [a-z0-9][a-z0-9_-]*, max 64 chars."""
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


fn validate_version(version: String) raises:
    """Reject versions that aren't X.Y.Z (digits and dots only)."""
    var bytes = version.as_bytes()
    var n = len(bytes)
    if n == 0:
        raise Error("Invalid version: empty string")
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


fn validate_tarball_url(url: String) raises:
    """Reject tarball URLs that don't start with https://github.com/"""
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


fn validate_cdep_name(name: String) raises:
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


fn validate_cdep_source(source: String) raises:
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

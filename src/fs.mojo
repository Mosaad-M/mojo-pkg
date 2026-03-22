# src/fs.mojo
# File system FFI wrappers + platform detection.
# All POSIX calls work identically on Linux and macOS.
#
# NOTE: unsafe_ptr() in Mojo 0.26+ does not guarantee a null byte at data[len].
# All FFI functions that need C strings use alloc+copy+null-terminate explicitly.

from ffi import external_call
from memory.unsafe_pointer import alloc
from os import getenv


# ─── Platform detection ────────────────────────────────────────────────────────

def fs_exists(path: String) -> Bool:
    """Return True if path exists (via access syscall)."""
    var pb = path.as_bytes()
    var n = len(pb)
    var buf = alloc[UInt8](n + 1)
    for i in range(n):
        (buf + i)[] = pb[i]
    (buf + n)[] = 0
    var ret = external_call["access", Int32](buf, Int32(0))
    buf.free()
    return ret == 0


def platform_name() -> String:
    """Return 'linux' or 'macos' based on /proc/version existence."""
    if fs_exists("/proc/version"):
        return String("linux")
    return String("macos")


def shared_lib_ext() -> String:
    if platform_name() == "linux":
        return String(".so")
    return String(".dylib")


def gcc_shared_flag() -> String:
    if platform_name() == "linux":
        return String("-shared")
    return String("-dynamiclib")


def c_compiler() -> String:
    """gcc on Linux, clang on macOS."""
    if platform_name() == "linux":
        return String("gcc")
    return String("clang")


def ca_bundle_path() raises -> String:
    """Return path to system CA bundle."""
    var candidates = List[String]()
    candidates.append("/etc/ssl/certs/ca-certificates.crt")   # Debian/Ubuntu
    candidates.append("/etc/ssl/cert.pem")                     # macOS
    candidates.append("/opt/homebrew/etc/openssl/cert.pem")    # Homebrew arm64
    candidates.append("/etc/pki/tls/certs/ca-bundle.crt")      # RHEL/CentOS
    for i in range(len(candidates)):
        if fs_exists(candidates[i]):
            return candidates[i]
    raise Error("Could not find CA bundle")


# ─── Home directory ────────────────────────────────────────────────────────────

def fs_home_dir() -> String:
    """Return $HOME environment variable."""
    return getenv("HOME", "/tmp")


# ─── Shell quoting ────────────────────────────────────────────────────────────

def _shell_quote(s: String) -> String:
    """Wrap s in single quotes, escaping any embedded single quotes (x -> '\\''x).
    Makes shell commands safe even when paths contain spaces or metacharacters."""
    var bytes = s.as_bytes()
    var out = List[UInt8](capacity=len(bytes) + 2)
    out.append(39)  # opening '
    for i in range(len(bytes)):
        var b = bytes[i]
        if b == 39:  # single quote -> '\''
            out.append(39)   # '
            out.append(92)   # \
            out.append(39)   # '
            out.append(39)   # '
        else:
            out.append(b)
    out.append(39)  # closing '
    return String(unsafe_from_utf8=out^)


# ─── mkdir -p ─────────────────────────────────────────────────────────────────

def fs_mkdir_p(path: String) raises:
    """Create directory and all parents. Like mkdir -p."""
    var cmd = "mkdir -p " + _shell_quote(path)
    var ret = fs_run(cmd)
    if ret != 0:
        raise Error("mkdir -p failed for: " + path)


# ─── File I/O ─────────────────────────────────────────────────────────────────

def fs_read_file(path: String) raises -> String:
    """Read entire file and return as String."""
    var pb = path.as_bytes()
    var pn = len(pb)
    var pbuf = alloc[UInt8](pn + 1)
    for i in range(pn):
        (pbuf + i)[] = pb[i]
    (pbuf + pn)[] = 0
    var fd = external_call["open", Int32](pbuf, Int32(0))  # O_RDONLY=0
    pbuf.free()
    if fd < 0:
        raise Error("Cannot open file: " + path)

    var size = external_call["lseek", Int64](Int(fd), Int64(0), Int32(2))  # SEEK_END=2
    _ = external_call["lseek", Int64](Int(fd), Int64(0), Int32(0))         # SEEK_SET=0

    if size <= 0:
        _ = external_call["close", Int32](fd)
        return String("")

    var rbuf = alloc[UInt8](Int(size) + 1)
    var n = external_call["read", Int](fd, rbuf, Int(size))
    _ = external_call["close", Int32](fd)

    if n <= 0:
        rbuf.free()
        return String("")

    var out = List[UInt8](capacity=n)
    for i in range(n):
        out.append((rbuf + i)[])
    rbuf.free()
    return String(unsafe_from_utf8=out^)


def fs_write_file(path: String, content: String) raises:
    """Write string to file, creating or truncating it."""
    var pb = path.as_bytes()
    var pn = len(pb)
    var pbuf = alloc[UInt8](pn + 1)
    for i in range(pn):
        (pbuf + i)[] = pb[i]
    (pbuf + pn)[] = 0
    var fd = external_call["creat", Int32](pbuf, Int32(420))  # mode 0644
    pbuf.free()
    if fd < 0:
        raise Error("Cannot write file: " + path)

    var bytes = content.as_bytes()
    var n = len(bytes)
    if n > 0:
        var wbuf = alloc[UInt8](n)
        for i in range(n):
            (wbuf + i)[] = bytes[i]
        _ = external_call["write", Int](Int(fd), wbuf, n)
        wbuf.free()
    _ = external_call["close", Int32](fd)


def fs_write_bytes(path: String, data: List[UInt8]) raises:
    """Write raw bytes to file."""
    var pb = path.as_bytes()
    var pn = len(pb)
    var pbuf = alloc[UInt8](pn + 1)
    for i in range(pn):
        (pbuf + i)[] = pb[i]
    (pbuf + pn)[] = 0
    var fd = external_call["creat", Int32](pbuf, Int32(420))  # mode 0644
    pbuf.free()
    if fd < 0:
        raise Error("Cannot write file: " + path)

    var n = len(data)
    if n > 0:
        var wbuf = alloc[UInt8](n)
        for i in range(n):
            (wbuf + i)[] = data[i]
        _ = external_call["write", Int](Int(fd), wbuf, n)
        wbuf.free()
    _ = external_call["close", Int32](fd)


# ─── system() ─────────────────────────────────────────────────────────────────

def fs_run(cmd: String) raises -> Int32:
    """Run a shell command via system(). Returns exit code."""
    var cb = cmd.as_bytes()
    var n = len(cb)
    var buf = alloc[UInt8](n + 1)
    for i in range(n):
        (buf + i)[] = cb[i]
    (buf + n)[] = 0
    var ret = external_call["system", Int32](buf)
    buf.free()
    return ret


def fs_run_check(cmd: String) raises:
    """Run a shell command, raising on non-zero exit."""
    var ret = fs_run(cmd)
    if ret != 0:
        raise Error("Command failed (exit " + String(ret) + "): " + cmd)


def fs_rm_rf(path: String) raises:
    """Remove a directory tree. Like rm -rf."""
    var ret = fs_run("rm -rf " + _shell_quote(path))
    if ret != 0:
        raise Error("rm -rf failed: " + path)

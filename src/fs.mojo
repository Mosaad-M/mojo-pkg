# src/fs.mojo
# File system helpers + platform detection (Linux and macOS).
#
# File I/O, existence checks and command output go through Mojo's std (open,
# std.os.path, std.subprocess). A program may declare each C function with one
# signature only, and std declares open/read/write/lseek/popen/pclose itself;
# tls (linked into mojo-pkg) uses std open(), so declaring them here would not
# compile. Only system(), which std does not declare, is called directly.
#
# NOTE: unsafe_ptr() does not guarantee a null byte at data[len], so the
# system() wrapper copies and null-terminates the command explicitly.

from std.ffi import external_call
from std.memory import alloc
from std.os import getenv
from std.os.path import exists
from std.subprocess import run


# ─── Platform detection ────────────────────────────────────────────────────────

def fs_exists(path: String) -> Bool:
    """Return True if path exists."""
    return exists(path)


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
    try:
        with open(path, "r") as f:
            return f.read()
    except:
        raise Error("Cannot open file: " + path)


def fs_read_bytes(path: String) raises -> List[UInt8]:
    """Read an entire file as raw bytes (for binary files such as tarballs)."""
    try:
        with open(path, "r") as f:
            return f.read_bytes()
    except:
        raise Error("Cannot open file: " + path)


def fs_write_file(path: String, content: String) raises:
    """Write string to file, creating or truncating it."""
    try:
        with open(path, "w") as f:
            f.write(content)
    except:
        raise Error("Cannot write file: " + path)


def fs_write_bytes(path: String, data: List[UInt8]) raises:
    """Write raw bytes to file."""
    try:
        with open(path, "w") as f:
            f.write_bytes(data)
    except:
        raise Error("Cannot write file: " + path)


# ─── system() ─────────────────────────────────────────────────────────────────

def fs_run(cmd: String) raises -> Int32:
    """Run a shell command via system(). Returns exit code."""
    var cb = cmd.as_bytes()
    var n = len(cb)
    var buf = alloc[UInt8](n + 1)
    for i in range(n):
        buf[unsafe_offset=i] = cb[i]
    buf[unsafe_offset=n] = 0
    var ret = external_call["system", Int32](buf)
    buf.unsafe_free()
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


def fs_run_output(cmd: String) raises -> String:
    """Run cmd and return its stdout with trailing whitespace removed."""
    return run(cmd)


def current_platform() -> String:
    """Return pixi-style platform string for current host (e.g. 'linux-64', 'osx-arm64')."""
    if platform_name() == "linux":
        return String("linux-64")
    try:
        var arch = fs_run_output("uname -m")
        if arch == "arm64" or arch == "aarch64":
            return String("osx-arm64")
        return String("osx-64")
    except:
        return String("osx-arm64")

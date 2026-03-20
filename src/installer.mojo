# src/installer.mojo
# Download, verify, and unpack packages.

from http_client import HttpClient
from lockfile import LockedPackage
from manifest import Manifest, CDependency, manifest_parse
from fs import fs_exists, fs_mkdir_p, fs_write_bytes, fs_read_file, fs_run, fs_run_check, shared_lib_ext, gcc_shared_flag, c_compiler, fs_home_dir, _shell_quote
from crypto.hash import sha256
from validate import validate_name, validate_version, validate_tarball_url
from flags import write_flags_cache


fn _bytes_to_hex(data: List[UInt8]) -> String:
    """Convert a byte list to a lowercase hex string."""
    alias HEX = "0123456789abcdef"
    var hb = HEX.as_bytes()
    var out = List[UInt8](capacity=len(data) * 2)
    for i in range(len(data)):
        var b = data[i]
        out.append(hb[Int(b >> 4)])
        out.append(hb[Int(b & 0xF)])
    return String(unsafe_from_utf8=out^)


fn sha256_hex(data: String) -> String:
    """Return SHA-256 hex digest of a string's bytes."""
    var span = data.as_bytes()
    var bytes = List[UInt8](capacity=len(span))
    for i in range(len(span)):
        bytes.append(span[i])
    var digest = sha256(bytes)
    return _bytes_to_hex(digest)


fn sha256_hex_bytes(data: List[UInt8]) -> String:
    """Return SHA-256 hex digest of a byte list."""
    var digest = sha256(data)
    return _bytes_to_hex(digest)


fn install_package(pkg: LockedPackage, mut client: HttpClient) raises:
    """Download, verify, and unpack a single package."""
    # Validate all fields before constructing any paths or commands
    validate_name(pkg.name)
    validate_version(pkg.version)
    validate_tarball_url(pkg.source_url)

    # Skip if already installed (check for mojoproject.toml as sentinel)
    var sentinel = pkg.install_path + "/mojoproject.toml"
    if fs_exists(sentinel):
        # Still compile any missing C deps (handles partial installs)
        try:
            var sub_manifest = manifest_parse(sentinel)
            _compile_c_deps(pkg.install_path, sub_manifest.c_deps)
        except:
            pass
        print("  Already installed: " + pkg.name + " " + pkg.version)
        return

    print("  Downloading: " + pkg.name + " " + pkg.version)
    # Use private per-user tmp dir to avoid shared-/tmp TOCTOU race
    var tmp_dir = fs_home_dir() + "/.mojo/tmp"
    fs_mkdir_p(tmp_dir)
    # pkg.name and pkg.version are already validated (safe chars), so no quoting needed
    # for the filename segments — but the full paths are quoted for safety
    var tarball_path = tmp_dir + "/mojo_pkg_" + pkg.name + "_" + pkg.version + ".tar.gz"
    var listing_tmp  = tmp_dir + "/mojo_pkg_list_" + pkg.name + "_" + pkg.version + ".txt"
    # pkg.source_url goes after -- (handles flag injection); strict allowlist already
    # prohibits shell metacharacters so no shell quoting needed for the URL itself
    var dl_cmd = "curl -sL -o " + _shell_quote(tarball_path) + " -- " + pkg.source_url
    fs_run_check(dl_cmd)

    # Verify SHA256 — empty sha256 is a fatal error (no integrity bypass)
    if len(pkg.sha256) == 0:
        raise Error("SHA256 is missing for " + pkg.name + " — refusing to install unverified package")
    var content = fs_read_file(tarball_path)
    var actual = sha256_hex(content)
    if actual != pkg.sha256:
        raise Error(
            "SHA256 mismatch for " + pkg.name + "\n" +
            "  expected: " + pkg.sha256 + "\n" +
            "  actual:   " + actual
        )

    # Guard against tarball path traversal before unpacking.
    fs_run_check("tar tzf " + _shell_quote(tarball_path) + " > " + _shell_quote(listing_tmp))
    # grep -F treats the pattern as a literal fixed string (no regex metacharacters)
    var traversal_ret = fs_run("grep -F -q '..' " + _shell_quote(listing_tmp))
    if traversal_ret == 0:
        raise Error(
            "Path traversal detected in tarball for " + pkg.name
            + " — tarball contains '..' in entry paths, refusing to unpack"
        )

    # Unpack
    fs_mkdir_p(pkg.install_path)
    var cmd = "tar xzf " + _shell_quote(tarball_path) + " -C " + _shell_quote(pkg.install_path) + " --strip-components=1"
    fs_run_check(cmd)

    print("  Installed: " + pkg.name + " " + pkg.version + " → " + pkg.install_path)

    # Compile C dependencies from the package's own mojoproject.toml
    if fs_exists(sentinel):
        try:
            var sub_manifest = manifest_parse(sentinel)
            _compile_c_deps(pkg.install_path, sub_manifest.c_deps)
        except e:
            print("  Warning: could not compile C deps for " + pkg.name + ": " + String(e))


fn _compile_c_deps(install_path: String, c_deps: List[CDependency]) raises:
    """Compile C library dependencies for a package."""
    if len(c_deps) == 0:
        return

    var ext = shared_lib_ext()
    var flag = gcc_shared_flag()
    var compiler = c_compiler()

    for i in range(len(c_deps)):
        var src      = _shell_quote(install_path + "/" + c_deps[i].source)
        var out_lib  = _shell_quote(install_path + "/lib" + c_deps[i].name + ext)
        var out_lib_path = install_path + "/lib" + c_deps[i].name + ext
        if fs_exists(out_lib_path):
            continue
        print("  Compiling C dep: " + c_deps[i].name)
        var cmd = compiler + " " + flag + " -fPIC -o " + out_lib + " " + src
        fs_run_check(cmd)


fn install_all(packages: List[LockedPackage], mut client: HttpClient) raises:
    """Install all packages in a lockfile."""
    for i in range(len(packages)):
        install_package(packages[i], client)
    # Write global flags cache so 'mojo-pkg flags' is fast on subsequent calls
    try:
        write_flags_cache(packages)
    except e:
        print("  Warning: could not write flags cache: " + String(e))

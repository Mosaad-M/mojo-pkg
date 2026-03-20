# tests/test_flags.mojo
# Tests for flags.mojo — include and linker flag generation.

from flags import get_include_flags, get_linker_flags, write_flags_file
from lockfile import LockFile, LockedPackage
from fs import fs_write_file, fs_exists, fs_read_file


fn assert_eq(a: String, b: String, label: String) raises:
    if a != b:
        raise Error("FAIL: " + label + " — expected '" + b + "', got '" + a + "'")


fn assert_true(val: Bool, label: String) raises:
    if not val:
        raise Error("FAIL: " + label + " — expected True, got False")


fn assert_contains(haystack: String, needle: String, label: String) raises:
    if haystack.find(needle) < 0:
        raise Error("FAIL: " + label + " — expected '" + needle + "' in '" + haystack + "'")


fn assert_not_contains(haystack: String, needle: String, label: String) raises:
    if haystack.find(needle) >= 0:
        raise Error("FAIL: " + label + " — did not expect '" + needle + "' in '" + haystack + "'")


fn test_include_empty() raises:
    var lock = LockFile()
    var flags = get_include_flags(lock)
    # Empty lock → empty flags (may have trailing space — trim for comparison)
    var bytes = flags.as_bytes()
    var n = len(bytes)
    var end = n
    while end > 0 and bytes[end - 1] == 32:
        end -= 1
    var trimmed = List[UInt8](capacity=end)
    for i in range(end):
        trimmed.append(bytes[i])
    var result = String(unsafe_from_utf8=trimmed^)
    assert_eq(result, "", "include empty: no flags")
    print("PASS: test_include_empty")


fn test_include_single() raises:
    var lock = LockFile()
    lock.packages.append(LockedPackage("tls", "1.0.0", "", "", "/mock/tls/path"))
    var flags = get_include_flags(lock)
    assert_contains(flags, "-I \"/mock/tls/path\"", "include single: -I flag present")
    print("PASS: test_include_single")


fn test_include_two() raises:
    var lock = LockFile()
    lock.packages.append(LockedPackage("tls", "1.0.0", "", "", "/mock/tls"))
    lock.packages.append(LockedPackage("tcp", "1.0.0", "", "", "/mock/tcp"))
    var flags = get_include_flags(lock)
    assert_contains(flags, "-I \"/mock/tls\"", "include two: tls flag")
    assert_contains(flags, "-I \"/mock/tcp\"", "include two: tcp flag")
    print("PASS: test_include_two")


fn test_linker_no_manifest() raises:
    # Package whose install_path has no mojoproject.toml
    var lock = LockFile()
    lock.packages.append(LockedPackage("tls", "1.0.0", "", "", "/nonexistent/path"))
    var flags = get_linker_flags(lock)
    assert_eq(flags, "", "linker no manifest: empty flags")
    print("PASS: test_linker_no_manifest")


fn test_linker_no_c_deps() raises:
    # Write a mojoproject.toml with no [c-dependencies] to /tmp
    var toml = String("""
[package]
name = "mylib"
version = "1.0.0"

[mojo]
requires = ">=0.26.1"
""")
    fs_write_file("/tmp/mojoproject_noceps.toml", toml)
    # Use a separate install_path that won't accidentally match
    # We can't easily use a custom dir, so skip linker for this package
    # (just verify it doesn't crash for a package with no toml)
    var lock = LockFile()
    lock.packages.append(LockedPackage("mylib", "1.0.0", "", "", "/nonexistent_noceps"))
    var flags = get_linker_flags(lock)
    assert_eq(flags, "", "linker no c_deps: empty flags when toml missing")
    print("PASS: test_linker_no_c_deps")


fn test_linker_with_c_dep() raises:
    # Write a mojoproject.toml with [c-dependencies] to /tmp
    # Use /tmp as install_path so toml is at /tmp/mojoproject.toml
    var toml = String("""
[package]
name = "tcp"
version = "1.0.0"

[mojo]
requires = ">=0.26.1"

[c-dependencies]
errno_helper = "errno_helper.c"
""")
    fs_write_file("/tmp/mojoproject.toml", toml)
    var lock = LockFile()
    lock.packages.append(LockedPackage("tcp", "1.0.0", "", "", "/tmp"))
    var flags = get_linker_flags(lock)
    assert_contains(flags, "-Xlinker -lerrno_helper", "linker c_dep: lib flag present")
    print("PASS: test_linker_with_c_dep")


fn test_linker_l_flag() raises:
    # Uses /tmp/mojoproject.toml written by test_linker_with_c_dep
    var lock = LockFile()
    lock.packages.append(LockedPackage("tcp", "1.0.0", "", "", "/tmp"))
    var flags = get_linker_flags(lock)
    assert_contains(flags, "-Xlinker -L\"/tmp\"", "linker L flag: -L path present")
    print("PASS: test_linker_l_flag")


fn test_linker_rpath() raises:
    # Uses /tmp/mojoproject.toml written above
    var lock = LockFile()
    lock.packages.append(LockedPackage("tcp", "1.0.0", "", "", "/tmp"))
    var flags = get_linker_flags(lock)
    assert_contains(flags, "-Xlinker -rpath", "linker rpath: rpath flag present")
    print("PASS: test_linker_rpath")


fn test_write_flags_file_creates() raises:
    var lock = LockFile()
    lock.packages.append(LockedPackage("tls", "1.0.0", "", "", "/mock/tls"))
    write_flags_file(lock, "/tmp/test_flags_output.flags")
    assert_true(fs_exists("/tmp/test_flags_output.flags"), "write_flags_file creates file")
    print("PASS: test_write_flags_file_creates")


fn test_write_flags_file_content() raises:
    var lock = LockFile()
    lock.packages.append(LockedPackage("tls", "1.0.0", "", "", "/mock/tls"))
    write_flags_file(lock, "/tmp/test_flags_content.flags")
    var content = fs_read_file("/tmp/test_flags_content.flags")
    assert_contains(content, "-I \"/mock/tls\"", "write_flags_file: content contains -I flag")
    print("PASS: test_write_flags_file_content")


fn test_write_flags_no_trailing_space() raises:
    var lock = LockFile()
    lock.packages.append(LockedPackage("tls", "1.0.0", "", "", "/mock/tls"))
    write_flags_file(lock, "/tmp/test_flags_nospace.flags")
    var content = fs_read_file("/tmp/test_flags_nospace.flags")
    var bytes = content.as_bytes()
    var n = len(bytes)
    # Last char should be newline (10), char before it should NOT be space (32)
    if n >= 2:
        assert_true(bytes[n - 1] == 10, "ends with newline")
        assert_true(bytes[n - 2] != 32, "no trailing space before newline")
    print("PASS: test_write_flags_no_trailing_space")


fn main() raises:
    print("=== Flags Tests ===")
    # Write the c-dep toml first (needed by multiple tests)
    var toml = String("""
[package]
name = "tcp"
version = "1.0.0"

[mojo]
requires = ">=0.26.1"

[c-dependencies]
errno_helper = "errno_helper.c"
""")
    fs_write_file("/tmp/mojoproject.toml", toml)

    test_include_empty()
    test_include_single()
    test_include_two()
    test_linker_no_manifest()
    test_linker_no_c_deps()
    test_linker_with_c_dep()
    test_linker_l_flag()
    test_linker_rpath()
    test_write_flags_file_creates()
    test_write_flags_file_content()
    test_write_flags_no_trailing_space()
    print("")
    print("All flags tests passed!")

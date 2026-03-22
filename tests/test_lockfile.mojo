# tests/test_lockfile.mojo
# Tests for lockfile read/write/find.

from lockfile import LockFile, LockedPackage, lockfile_read, lockfile_write, lockfile_find
from fs import fs_write_file, fs_exists


def assert_eq(a: String, b: String, label: String) raises:
    if a != b:
        raise Error("FAIL: " + label + " — expected '" + b + "', got '" + a + "'")


def assert_int_eq(a: Int, b: Int, label: String) raises:
    if a != b:
        raise Error("FAIL: " + label + " — expected " + String(b) + ", got " + String(a))


def assert_true(val: Bool, label: String) raises:
    if not val:
        raise Error("FAIL: " + label + " — expected True, got False")


def test_empty_roundtrip() raises:
    var lock = LockFile()
    lockfile_write(lock, "/tmp/test_lf_empty.json")
    var lock2 = lockfile_read("/tmp/test_lf_empty.json")
    assert_eq(lock2.mojo_version, "0.26.1", "empty: mojo_version default")
    assert_int_eq(len(lock2.packages), 0, "empty: no packages")
    print("PASS: test_empty_roundtrip")


def test_single_package_roundtrip() raises:
    var lock = LockFile()
    lock.packages.append(LockedPackage(
        "tls",
        "1.0.0",
        "https://github.com/Mosaad-M/tls/archive/v1.0.0.tar.gz",
        "abc123deadbeef",
        "/home/user/.mojo/packages/tls/1.0.0",
    ))
    lockfile_write(lock, "/tmp/test_lf_single.json")
    var lock2 = lockfile_read("/tmp/test_lf_single.json")
    assert_int_eq(len(lock2.packages), 1, "single: package count")
    assert_eq(lock2.packages[0].name, "tls", "single: name")
    assert_eq(lock2.packages[0].version, "1.0.0", "single: version")
    assert_eq(lock2.packages[0].source_url, "https://github.com/Mosaad-M/tls/archive/v1.0.0.tar.gz", "single: source_url")
    assert_eq(lock2.packages[0].sha256, "abc123deadbeef", "single: sha256")
    assert_eq(lock2.packages[0].install_path, "/home/user/.mojo/packages/tls/1.0.0", "single: install_path")
    print("PASS: test_single_package_roundtrip")


def test_multi_package_roundtrip() raises:
    var lock = LockFile()
    lock.packages.append(LockedPackage("tls", "1.0.0", "https://github.com/Mosaad-M/tls/archive/v1.0.0.tar.gz", "sha1", "/path/tls"))
    lock.packages.append(LockedPackage("tcp", "2.0.0", "https://github.com/Mosaad-M/tcp/archive/v2.0.0.tar.gz", "sha2", "/path/tcp"))
    lock.packages.append(LockedPackage("json", "0.5.0", "https://github.com/Mosaad-M/json/archive/v0.5.0.tar.gz", "sha3", "/path/json"))
    lockfile_write(lock, "/tmp/test_lf_multi.json")
    var lock2 = lockfile_read("/tmp/test_lf_multi.json")
    assert_int_eq(len(lock2.packages), 3, "multi: package count")
    assert_eq(lock2.packages[0].name, "tls", "multi: pkg[0] name")
    assert_eq(lock2.packages[1].name, "tcp", "multi: pkg[1] name")
    assert_eq(lock2.packages[2].name, "json", "multi: pkg[2] name")
    assert_eq(lock2.packages[2].version, "0.5.0", "multi: pkg[2] version")
    print("PASS: test_multi_package_roundtrip")


def test_lockfile_find_found() raises:
    var lock = LockFile()
    lock.packages.append(LockedPackage("tls", "1.0.0", "", "", "/path/tls"))
    lock.packages.append(LockedPackage("tcp", "1.0.0", "", "", "/path/tcp"))
    lock.packages.append(LockedPackage("json", "1.0.0", "", "", "/path/json"))
    assert_int_eq(lockfile_find(lock, "tls"), 0, "find: tls at index 0")
    assert_int_eq(lockfile_find(lock, "tcp"), 1, "find: tcp at index 1")
    assert_int_eq(lockfile_find(lock, "json"), 2, "find: json at index 2")
    print("PASS: test_lockfile_find_found")


def test_lockfile_find_not_found() raises:
    var lock = LockFile()
    lock.packages.append(LockedPackage("tls", "1.0.0", "", "", ""))
    assert_int_eq(lockfile_find(lock, "nonexistent"), -1, "find: not found returns -1")
    print("PASS: test_lockfile_find_not_found")


def test_lockfile_find_empty() raises:
    var lock = LockFile()
    assert_int_eq(lockfile_find(lock, "anything"), -1, "find: empty lock returns -1")
    print("PASS: test_lockfile_find_empty")


def test_read_nonexistent() raises:
    var lock = lockfile_read("/tmp/nonexistent_lockfile_xyz.json")
    assert_int_eq(len(lock.packages), 0, "nonexistent: empty packages")
    assert_eq(lock.mojo_version, "0.26.1", "nonexistent: default mojo_version")
    print("PASS: test_read_nonexistent")


def test_mojo_version_written() raises:
    var lock = LockFile()
    lock.mojo_version = String("0.99.0")
    lockfile_write(lock, "/tmp/test_lf_version.json")
    # Read the raw file to check field presence
    var lock2 = lockfile_read("/tmp/test_lf_version.json")
    assert_eq(lock2.mojo_version, "0.99.0", "mojo_version round-trips")
    print("PASS: test_mojo_version_written")


def test_find_first() raises:
    var lock = LockFile()
    lock.packages.append(LockedPackage("alpha", "1.0.0", "", "", ""))
    lock.packages.append(LockedPackage("beta", "1.0.0", "", "", ""))
    assert_int_eq(lockfile_find(lock, "alpha"), 0, "find first: index 0")
    print("PASS: test_find_first")


def test_find_last() raises:
    var lock = LockFile()
    lock.packages.append(LockedPackage("alpha", "1.0.0", "", "", ""))
    lock.packages.append(LockedPackage("beta", "1.0.0", "", "", ""))
    lock.packages.append(LockedPackage("gamma", "1.0.0", "", "", ""))
    assert_int_eq(lockfile_find(lock, "gamma"), 2, "find last: index 2")
    print("PASS: test_find_last")


def test_duplicate_name_finds_first() raises:
    var lock = LockFile()
    lock.packages.append(LockedPackage("tls", "1.0.0", "", "", "/path1"))
    lock.packages.append(LockedPackage("tls", "2.0.0", "", "", "/path2"))
    assert_int_eq(lockfile_find(lock, "tls"), 0, "duplicate: finds first occurrence")
    print("PASS: test_duplicate_name_finds_first")


def test_json_escape_double_quote_roundtrip() raises:
    var lock = LockFile()
    lock.packages.append(LockedPackage(
        "tls",
        "1.0.0",
        "https://github.com/x/y.tar.gz",
        "abc",
        "/home/user/.mojo/packages/tls/\"quoted\"",
    ))
    lockfile_write(lock, "/tmp/test_lf_quote.json")
    var lock2 = lockfile_read("/tmp/test_lf_quote.json")
    assert_int_eq(len(lock2.packages), 1, "quote roundtrip: package count")
    assert_eq(lock2.packages[0].install_path, "/home/user/.mojo/packages/tls/\"quoted\"", "quote roundtrip: install_path with double quote")
    print("PASS: test_json_escape_double_quote_roundtrip")


def test_json_escape_backslash_roundtrip() raises:
    var lock = LockFile()
    lock.packages.append(LockedPackage(
        "tls",
        "1.0.0",
        "https://github.com/x/y.tar.gz",
        "abc",
        "/home/user/.mojo/packages/tls/back\\slash",
    ))
    lockfile_write(lock, "/tmp/test_lf_backslash.json")
    var lock2 = lockfile_read("/tmp/test_lf_backslash.json")
    assert_int_eq(len(lock2.packages), 1, "backslash roundtrip: package count")
    assert_eq(lock2.packages[0].install_path, "/home/user/.mojo/packages/tls/back\\slash", "backslash roundtrip: install_path with backslash")
    print("PASS: test_json_escape_backslash_roundtrip")


def main() raises:
    print("=== LockFile Tests ===")
    test_empty_roundtrip()
    test_single_package_roundtrip()
    test_multi_package_roundtrip()
    test_lockfile_find_found()
    test_lockfile_find_not_found()
    test_lockfile_find_empty()
    test_read_nonexistent()
    test_mojo_version_written()
    test_find_first()
    test_find_last()
    test_duplicate_name_finds_first()
    test_json_escape_double_quote_roundtrip()
    test_json_escape_backslash_roundtrip()
    print("")
    print("All lockfile tests passed!")

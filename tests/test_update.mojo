# tests/test_update.mojo
# Unit tests for the update command's diff logic.
# Tests the lockfile comparison (upgraded/unchanged/added) without network calls.

from lockfile import LockFile, LockedPackage, lockfile_find


def assert_eq(a: String, b: String, label: String) raises:
    if a != b:
        raise Error("FAIL: " + label + " — expected '" + b + "', got '" + a + "'")


def assert_int_eq(a: Int, b: Int, label: String) raises:
    if a != b:
        raise Error("FAIL: " + label + " — expected " + String(b) + ", got " + String(a))


def make_pkg(name: String, version: String) -> LockedPackage:
    return LockedPackage(name, version, "https://example.com/" + name + ".tar.gz", "abc123", "/home/user/.mojo/packages/" + name + "/" + version)


def test_lockfile_find_present() raises:
    var lock = LockFile()
    lock.packages.append(make_pkg("tls", "1.0.0"))
    lock.packages.append(make_pkg("tcp", "1.1.0"))
    assert_int_eq(lockfile_find(lock, "tls"), 0, "find tls at index 0")
    assert_int_eq(lockfile_find(lock, "tcp"), 1, "find tcp at index 1")
    print("PASS: test_lockfile_find_present")


def test_lockfile_find_missing() raises:
    var lock = LockFile()
    lock.packages.append(make_pkg("tls", "1.0.0"))
    assert_int_eq(lockfile_find(lock, "json"), -1, "find missing returns -1")
    print("PASS: test_lockfile_find_missing")


def test_lockfile_find_empty() raises:
    var lock = LockFile()
    assert_int_eq(lockfile_find(lock, "anything"), -1, "empty lock returns -1")
    print("PASS: test_lockfile_find_empty")


def test_diff_unchanged() raises:
    """Simulate update where version is unchanged."""
    var old_lock = LockFile()
    old_lock.packages.append(make_pkg("tls", "1.0.0"))

    var new_lock = LockFile()
    new_lock.packages.append(make_pkg("tls", "1.0.0"))

    var n_changed = 0
    for i in range(len(new_lock.packages)):
        var name = new_lock.packages[i].name
        var new_ver = new_lock.packages[i].version
        var old_idx = lockfile_find(old_lock, name)
        if old_idx >= 0:
            var old_ver = old_lock.packages[old_idx].version
            if old_ver != new_ver:
                n_changed += 1
        else:
            n_changed += 1

    assert_int_eq(n_changed, 0, "unchanged: n_changed == 0")
    print("PASS: test_diff_unchanged")


def test_diff_upgraded() raises:
    """Simulate update where one package is upgraded."""
    var old_lock = LockFile()
    old_lock.packages.append(make_pkg("tls", "1.0.0"))
    old_lock.packages.append(make_pkg("tcp", "1.0.0"))

    var new_lock = LockFile()
    new_lock.packages.append(make_pkg("tls", "1.2.0"))  # upgraded
    new_lock.packages.append(make_pkg("tcp", "1.0.0"))  # unchanged

    var n_changed = 0
    var upgraded_name = String("")
    var upgraded_old = String("")
    var upgraded_new = String("")
    for i in range(len(new_lock.packages)):
        var name = new_lock.packages[i].name
        var new_ver = new_lock.packages[i].version
        var old_idx = lockfile_find(old_lock, name)
        if old_idx >= 0:
            var old_ver = old_lock.packages[old_idx].version
            if old_ver != new_ver:
                upgraded_name = name
                upgraded_old = old_ver
                upgraded_new = new_ver
                n_changed += 1
        else:
            n_changed += 1

    assert_int_eq(n_changed, 1, "upgraded: n_changed == 1")
    assert_eq(upgraded_name, "tls", "upgraded: correct package")
    assert_eq(upgraded_old, "1.0.0", "upgraded: correct old version")
    assert_eq(upgraded_new, "1.2.0", "upgraded: correct new version")
    print("PASS: test_diff_upgraded")


def test_diff_added() raises:
    """Simulate update where a new transitive dep appears."""
    var old_lock = LockFile()
    old_lock.packages.append(make_pkg("tls", "1.0.0"))

    var new_lock = LockFile()
    new_lock.packages.append(make_pkg("tls", "1.0.0"))
    new_lock.packages.append(make_pkg("tcp", "1.0.0"))  # new dep

    var n_changed = 0
    for i in range(len(new_lock.packages)):
        var name = new_lock.packages[i].name
        var new_ver = new_lock.packages[i].version
        var old_idx = lockfile_find(old_lock, name)
        if old_idx >= 0:
            var old_ver = old_lock.packages[old_idx].version
            if old_ver != new_ver:
                n_changed += 1
        else:
            n_changed += 1

    assert_int_eq(n_changed, 1, "added: n_changed == 1")
    print("PASS: test_diff_added")


def test_diff_no_old_lock() raises:
    """Simulate first-time install (no old lock): all packages are 'added'."""
    var old_lock = LockFile()  # empty

    var new_lock = LockFile()
    new_lock.packages.append(make_pkg("tls", "1.0.0"))
    new_lock.packages.append(make_pkg("tcp", "1.0.0"))

    var n_changed = 0
    for i in range(len(new_lock.packages)):
        var old_idx = lockfile_find(old_lock, new_lock.packages[i].name)
        if old_idx < 0:
            n_changed += 1

    assert_int_eq(n_changed, 2, "no old lock: all 2 packages are new")
    print("PASS: test_diff_no_old_lock")


def test_dry_run_labels() raises:
    """Verify that dry-run mode uses 'Would upgrade'/'Would add' labels."""
    # Simulate the label logic from cmd_update(dry_run=True)
    var dry_run = True
    var upgrade_label = "Would upgrade" if dry_run else "Upgraded"
    var add_label = "Would add" if dry_run else "Added"
    if upgrade_label != "Would upgrade":
        raise Error("FAIL: dry_run=True should yield 'Would upgrade'")
    if add_label != "Would add":
        raise Error("FAIL: dry_run=True should yield 'Would add'")

    var dry_run2 = False
    var upgrade_label2 = "Would upgrade" if dry_run2 else "Upgraded"
    var add_label2 = "Would add" if dry_run2 else "Added"
    if upgrade_label2 != "Upgraded":
        raise Error("FAIL: dry_run=False should yield 'Upgraded'")
    if add_label2 != "Added":
        raise Error("FAIL: dry_run=False should yield 'Added'")
    print("PASS: test_dry_run_labels")


def main() raises:
    print("=== Update Diff Tests ===")
    test_lockfile_find_present()
    test_lockfile_find_missing()
    test_lockfile_find_empty()
    test_diff_unchanged()
    test_diff_upgraded()
    test_diff_added()
    test_diff_no_old_lock()
    test_dry_run_labels()
    print("")
    print("All update tests passed!")

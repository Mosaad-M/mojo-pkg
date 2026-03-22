# src/main.mojo
# mojo-pkg CLI entry point.
#
# Usage:
#   mojo-pkg install          — resolve + install all deps from mojoproject.toml
#   mojo-pkg add <name>       — add a package (fetches latest, updates mojoproject.toml)
#   mojo-pkg flags            — print -I/-Xlinker flags for mojo.lock packages
#   mojo-pkg search <query>   — search the registry
#   mojo-pkg list             — list installed packages from mojo.lock

from sys import argv
from http_client import HttpClient
from manifest import Manifest, manifest_parse, manifest_write, manifest_add_dep, manifest_remove_dep
from lockfile import LockFile, lockfile_read, lockfile_write, lockfile_find
from resolver import resolve
from installer import install_all
from flags import write_flags_file, print_flags
from registry import registry_fetch_package, registry_search, PackageMeta
from fs import fs_exists, fs_mkdir_p, fs_home_dir, fs_rm_rf


def print_usage():
    print("mojo-pkg — Mojo Package Manager")
    print("")
    print("Usage:")
    print("  mojo-pkg install          Resolve and install dependencies")
    print("  mojo-pkg update           Re-resolve deps to latest versions")
    print("  mojo-pkg add <name>       Add a dependency from the registry")
    print("  mojo-pkg remove <name>    Remove a dependency")
    print("  mojo-pkg flags            Print -I/-Xlinker flags to stdout")
    print("  mojo-pkg search [query]   Search packages in the registry")
    print("  mojo-pkg list             List locked packages")
    print("  mojo-pkg version          Print version")


def cmd_install() raises:
    """Resolve and install all dependencies from mojoproject.toml."""
    if not fs_exists("mojoproject.toml"):
        raise Error("No mojoproject.toml found in current directory")

    print("Reading mojoproject.toml...")
    var manifest = manifest_parse("mojoproject.toml")

    var client = HttpClient()

    # Re-resolve if no lockfile or if manifest changed
    var lock: LockFile
    if fs_exists("mojo.lock"):
        print("Using existing mojo.lock...")
        lock = lockfile_read("mojo.lock")
    else:
        print("Resolving dependencies...")
        lock = resolve(manifest, client)
        lockfile_write(lock, "mojo.lock")
        print("Wrote mojo.lock")

    # Install all packages
    print("Installing " + String(len(lock.packages)) + " package(s)...")
    install_all(lock.packages, client)

    # Write .mojo_flags
    write_flags_file(lock, ".mojo_flags")
    print("Wrote .mojo_flags")
    print("")
    print("Done! Use $(cat .mojo_flags) in your mojo build command.")


def cmd_update() raises:
    """Re-resolve all deps to latest satisfying versions, update mojo.lock."""
    if not fs_exists("mojoproject.toml"):
        raise Error("No mojoproject.toml found in current directory")

    print("Reading mojoproject.toml...")
    var manifest = manifest_parse("mojoproject.toml")
    var client = HttpClient()

    # Snapshot old lock for diffing
    var old_lock = LockFile()
    if fs_exists("mojo.lock"):
        old_lock = lockfile_read("mojo.lock")

    # Force re-resolve (ignore existing mojo.lock)
    print("Re-resolving dependencies...")
    var lock = resolve(manifest, client)
    lockfile_write(lock, "mojo.lock")

    # Report changes
    var n_changed = 0
    for i in range(len(lock.packages)):
        var name = lock.packages[i].name
        var new_ver = lock.packages[i].version
        var old_idx = lockfile_find(old_lock, name)
        if old_idx >= 0:
            var old_ver = old_lock.packages[old_idx].version
            if old_ver != new_ver:
                print("  Upgraded: " + name + " " + old_ver + " -> " + new_ver)
                n_changed += 1
            else:
                print("  Unchanged: " + name + " " + new_ver)
        else:
            print("  Added: " + name + " " + new_ver)
            n_changed += 1

    install_all(lock.packages, client)
    write_flags_file(lock, ".mojo_flags")
    print(String(n_changed) + " package(s) changed.")


def cmd_remove(pkg_name: String) raises:
    """Remove a package from mojoproject.toml, re-resolve, and delete its files."""
    if len(pkg_name) == 0:
        raise Error("Usage: mojo-pkg remove <package-name>")

    if not fs_exists("mojoproject.toml"):
        raise Error("No mojoproject.toml found in current directory")

    var manifest = manifest_parse("mojoproject.toml")
    manifest_remove_dep(manifest, pkg_name)  # raises if not a direct dep
    manifest_write(manifest, "mojoproject.toml")
    print("  Removed " + pkg_name + " from mojoproject.toml")

    # Snapshot old lock (need install_path before re-resolving)
    var old_lock = LockFile()
    if fs_exists("mojo.lock"):
        old_lock = lockfile_read("mojo.lock")

    var client = HttpClient()
    print("Re-resolving dependencies...")
    var new_lock = resolve(manifest, client)
    lockfile_write(new_lock, "mojo.lock")

    # If still in new lock it's a transitive dep — warn and keep
    if lockfile_find(new_lock, pkg_name) >= 0:
        print("  Warning: '" + pkg_name + "' is still required transitively — keeping files")
    else:
        var old_idx = lockfile_find(old_lock, pkg_name)
        if old_idx >= 0:
            var install_path = old_lock.packages[old_idx].install_path
            print("  Removing " + install_path + "...")
            try:
                fs_rm_rf(install_path)
            except e:
                print("  Warning: could not delete directory: " + String(e))

    install_all(new_lock.packages, client)
    write_flags_file(new_lock, ".mojo_flags")
    print("Removed " + pkg_name)


def cmd_add(pkg_name: String) raises:
    """Add a package: fetch latest version, update mojoproject.toml and mojo.lock."""
    if len(pkg_name) == 0:
        raise Error("Usage: mojo-pkg add <package-name>")

    var client = HttpClient()

    print("Fetching package info: " + pkg_name)
    var meta = registry_fetch_package(pkg_name, client)

    if len(meta.versions) == 0:
        raise Error("No versions available for package: " + pkg_name)

    # Use latest version
    var latest = meta.versions[len(meta.versions) - 1].copy()
    var constraint = ">=" + latest.version

    # Update mojoproject.toml
    var manifest: Manifest
    if fs_exists("mojoproject.toml"):
        manifest = manifest_parse("mojoproject.toml")
    else:
        manifest = Manifest()
        manifest.name = String("my-project")
        manifest.version = String("0.1.0")
        manifest.mojo_requires = String(">=0.26.1")
        manifest.platforms.append("linux-64")

    manifest_add_dep(manifest, pkg_name, meta.git_url, constraint)
    manifest_write(manifest, "mojoproject.toml")
    print("  Updated mojoproject.toml")

    # Force re-resolve
    if fs_exists("mojo.lock"):
        # Remove the old lock (simplest approach: re-resolve everything)
        pass

    print("Re-resolving dependencies...")
    var lock = resolve(manifest, client)
    lockfile_write(lock, "mojo.lock")

    print("Installing " + pkg_name + "...")
    install_all(lock.packages, client)

    write_flags_file(lock, ".mojo_flags")
    print("Added " + pkg_name + " " + latest.version)


def cmd_flags() raises:
    """Print compiler flags from mojo.lock."""
    if not fs_exists("mojo.lock"):
        raise Error("No mojo.lock found. Run 'mojo-pkg install' first.")
    var lock = lockfile_read("mojo.lock")
    print_flags(lock)


def cmd_search(query: String) raises:
    """Search the registry."""
    var client = HttpClient()
    var results = registry_search(query, client)
    if len(results) == 0:
        print("No packages found" + ((" matching '" + query + "'") if len(query) > 0 else ""))
        return
    print("Found " + String(len(results)) + " package(s):")
    for i in range(len(results)):
        print("  " + results[i])


def cmd_list() raises:
    """List locked packages."""
    if not fs_exists("mojo.lock"):
        print("No mojo.lock found.")
        return
    var lock = lockfile_read("mojo.lock")
    if len(lock.packages) == 0:
        print("No packages locked.")
        return
    print("Locked packages:")
    for i in range(len(lock.packages)):
        print("  " + lock.packages[i].name + " " + lock.packages[i].version + "  (" + lock.packages[i].install_path + ")")


def main() raises:
    var args = argv()
    if len(args) < 2:
        print_usage()
        return

    var cmd = args[1]

    if cmd == "install":
        cmd_install()
    elif cmd == "update":
        cmd_update()
    elif cmd == "add":
        var pkg = args[2] if len(args) > 2 else ""
        cmd_add(pkg)
    elif cmd == "flags":
        cmd_flags()
    elif cmd == "remove":
        var pkg = args[2] if len(args) > 2 else ""
        cmd_remove(pkg)
    elif cmd == "search":
        var query = args[2] if len(args) > 2 else ""
        cmd_search(query)
    elif cmd == "list":
        cmd_list()
    elif cmd == "version":
        print("mojo-pkg 0.1.0")
    elif cmd == "help" or cmd == "--help" or cmd == "-h":
        print_usage()
    else:
        print("Unknown command: " + cmd)
        print("")
        print_usage()

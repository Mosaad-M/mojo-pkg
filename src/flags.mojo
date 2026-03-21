# src/flags.mojo
# Generate -I and -Xlinker compiler flags from a lockfile.

from lockfile import LockFile, LockedPackage
from manifest import CDependency, manifest_parse
from fs import fs_write_file, fs_read_file, fs_exists, fs_home_dir, shared_lib_ext


fn get_include_flags(lock: LockFile) -> String:
    """Returns space-separated -I flags for all installed packages.
    Paths use no quoting: install_path is validated to alphanumeric+dash chars only."""
    var flags = String("")
    for i in range(len(lock.packages)):
        flags += "-I " + lock.packages[i].install_path + " "
    return flags


fn get_linker_flags(lock: LockFile) -> String:
    """Returns -Xlinker flags for packages with C deps.
    Paths use no quoting: install_path and c_dep.name are validated safe chars."""
    var flags = String("")
    for i in range(len(lock.packages)):
        var toml_path = lock.packages[i].install_path + "/mojoproject.toml"
        if not fs_exists(toml_path):
            continue
        try:
            var sub_manifest = manifest_parse(toml_path)
            if len(sub_manifest.c_deps) > 0:
                flags += "-Xlinker -L" + lock.packages[i].install_path + " "
                for j in range(len(sub_manifest.c_deps)):
                    flags += "-Xlinker -l" + sub_manifest.c_deps[j].name + " "
                flags += "-Xlinker -rpath -Xlinker " + lock.packages[i].install_path + " "
        except:
            pass
    return flags


fn write_flags_file(lock: LockFile, path: String) raises:
    """Write .mojo_flags file with all -I and -Xlinker flags."""
    var inc = get_include_flags(lock)
    var lnk = get_linker_flags(lock)
    var content = inc
    if len(lnk) > 0:
        content += lnk
    # Trim trailing space
    var bytes = content.as_bytes()
    var end = len(bytes)
    while end > 0 and bytes[end - 1] == 32:
        end -= 1
    if end < len(bytes):
        var trimmed = List[UInt8](capacity=end)
        for i in range(end):
            trimmed.append(bytes[i])
        content = String(unsafe_from_utf8=trimmed^)
    fs_write_file(path, content + "\n")


fn write_flags_cache(packages: List[LockedPackage]) raises:
    """Write computed flags to ~/.mojo/packages/.flags_cache.
    Called by installer after a successful install so that repeated
    'mojo-pkg flags' invocations skip re-parsing all manifests."""
    var home = fs_home_dir()
    var cache_path = home + "/.mojo/packages/.flags_cache"
    # Build a temporary LockFile-like view using only the package list
    var tmp_lock = LockFile()
    for i in range(len(packages)):
        tmp_lock.packages.append(packages[i].copy())
    var inc = get_include_flags(tmp_lock)
    var lnk = get_linker_flags(tmp_lock)
    var content = inc
    if len(lnk) > 0:
        content += lnk
    fs_write_file(cache_path, content)


fn print_flags(lock: LockFile) raises:
    """Print flags to stdout (for use in build scripts via command substitution).
    Reads ~/.mojo/packages/.flags_cache if it exists (written by installer);
    otherwise computes from lock and prints."""
    var home = fs_home_dir()
    var cache_path = home + "/.mojo/packages/.flags_cache"
    var content = String("")
    if fs_exists(cache_path):
        content = fs_read_file(cache_path)
    else:
        var inc = get_include_flags(lock)
        var lnk = get_linker_flags(lock)
        content = inc
        if len(lnk) > 0:
            content += lnk
    # Trim trailing newline/space
    var bytes = content.as_bytes()
    var end = len(bytes)
    while end > 0 and (bytes[end - 1] == 32 or bytes[end - 1] == 10):
        end -= 1
    if end > 0:
        var out = List[UInt8](capacity=end)
        for i in range(end):
            out.append(bytes[i])
        print(String(unsafe_from_utf8=out^))

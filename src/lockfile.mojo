# src/lockfile.mojo
# mojo.lock read/write using json/ module.

from json import JsonValue, parse_json
from fs import fs_read_file, fs_write_file, fs_exists


struct LockedPackage(Copyable, Movable):
    """A single resolved and locked package."""
    var name: String
    var version: String
    var source_url: String
    var sha256: String
    var install_path: String

    def __init__(out self, name: String, version: String, source_url: String, sha256: String, install_path: String):
        self.name = name
        self.version = version
        self.source_url = source_url
        self.sha256 = sha256
        self.install_path = install_path

    def __copyinit__(out self, copy: Self):
        self.name = copy.name
        self.version = copy.version
        self.source_url = copy.source_url
        self.sha256 = copy.sha256
        self.install_path = copy.install_path

    def __moveinit__(out self, deinit take: Self):
        self.name = take.name^
        self.version = take.version^
        self.source_url = take.source_url^
        self.sha256 = take.sha256^
        self.install_path = take.install_path^


struct LockFile(Movable):
    """The full mojo.lock contents."""
    var mojo_version: String
    var packages: List[LockedPackage]

    def __init__(out self):
        self.mojo_version = String("0.26.1")
        self.packages = List[LockedPackage]()

    def __moveinit__(out self, deinit take: Self):
        self.mojo_version = take.mojo_version^
        self.packages = take.packages^


def lockfile_read(path: String) raises -> LockFile:
    """Read and parse a mojo.lock JSON file."""
    var lock = LockFile()
    if not fs_exists(path):
        return lock^

    var src = fs_read_file(path)
    var root = parse_json(src)

    if root.has_key("mojo_version"):
        lock.mojo_version = root.get_string("mojo_version")

    if root.has_key("packages"):
        var pkgs = root.get("packages")
        var n = len(pkgs)
        for i in range(n):
            var pkg = pkgs.get(i)
            var lp = LockedPackage(
                pkg.get_string("name"),
                pkg.get_string("version"),
                pkg.get_string("source_url"),
                pkg.get_string("sha256"),
                pkg.get_string("install_path"),
            )
            lock.packages.append(lp^)

    return lock^


def _json_escape(s: String) -> String:
    """Escape a string for JSON: backslash, double-quote, and common control chars."""
    var bytes = s.as_bytes()
    var out = List[UInt8](capacity=len(bytes))
    for i in range(len(bytes)):
        var b = bytes[i]
        if b == 34:    # "
            out.append(92); out.append(34)   # \"
        elif b == 92:  # \
            out.append(92); out.append(92)   # \\
        elif b == 10:  # \n
            out.append(92); out.append(110)  # \n
        elif b == 13:  # \r
            out.append(92); out.append(114)  # \r
        elif b == 9:   # \t
            out.append(92); out.append(116)  # \t
        else:
            out.append(b)
    return String(unsafe_from_utf8=out^)


def lockfile_write(lock: LockFile, path: String) raises:
    """Write a LockFile to a JSON file.
    TODO: this function has no file locking — concurrent invocations in the same
    directory could corrupt the lockfile. Use of flock() would require significant
    FFI work; the use case (two parallel mojo-pkg install calls in the same dir)
    is rare enough that this is acceptable for now."""
    var content = String("{\n")
    content += "  \"mojo_version\": \"" + _json_escape(lock.mojo_version) + "\",\n"
    content += "  \"packages\": [\n"

    for i in range(len(lock.packages)):
        if i > 0:
            content += ",\n"
        content += "    {\n"
        content += "      \"name\": \"" + _json_escape(lock.packages[i].name) + "\",\n"
        content += "      \"version\": \"" + _json_escape(lock.packages[i].version) + "\",\n"
        content += "      \"source_url\": \"" + _json_escape(lock.packages[i].source_url) + "\",\n"
        content += "      \"sha256\": \"" + _json_escape(lock.packages[i].sha256) + "\",\n"
        content += "      \"install_path\": \"" + _json_escape(lock.packages[i].install_path) + "\"\n"
        content += "    }"

    content += "\n  ]\n}\n"
    fs_write_file(path, content)


def lockfile_find(lock: LockFile, name: String) -> Int:
    """Find a package by name in the lockfile. Returns index or -1."""
    for i in range(len(lock.packages)):
        if lock.packages[i].name == name:
            return i
    return -1

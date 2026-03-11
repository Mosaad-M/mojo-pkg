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

    fn __init__(out self, name: String, version: String, source_url: String, sha256: String, install_path: String):
        self.name = name
        self.version = version
        self.source_url = source_url
        self.sha256 = sha256
        self.install_path = install_path

    fn __copyinit__(out self, copy: Self):
        self.name = copy.name
        self.version = copy.version
        self.source_url = copy.source_url
        self.sha256 = copy.sha256
        self.install_path = copy.install_path

    fn __moveinit__(out self, deinit take: Self):
        self.name = take.name^
        self.version = take.version^
        self.source_url = take.source_url^
        self.sha256 = take.sha256^
        self.install_path = take.install_path^


struct LockFile(Movable):
    """The full mojo.lock contents."""
    var mojo_version: String
    var packages: List[LockedPackage]

    fn __init__(out self):
        self.mojo_version = String("0.26.1")
        self.packages = List[LockedPackage]()

    fn __moveinit__(out self, deinit take: Self):
        self.mojo_version = take.mojo_version^
        self.packages = take.packages^


fn lockfile_read(path: String) raises -> LockFile:
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


fn lockfile_write(lock: LockFile, path: String) raises:
    """Write a LockFile to a JSON file."""
    var content = String("{\n")
    content += "  \"mojo_version\": \"" + lock.mojo_version + "\",\n"
    content += "  \"packages\": [\n"

    for i in range(len(lock.packages)):
        if i > 0:
            content += ",\n"
        content += "    {\n"
        content += "      \"name\": \"" + lock.packages[i].name + "\",\n"
        content += "      \"version\": \"" + lock.packages[i].version + "\",\n"
        content += "      \"source_url\": \"" + lock.packages[i].source_url + "\",\n"
        content += "      \"sha256\": \"" + lock.packages[i].sha256 + "\",\n"
        content += "      \"install_path\": \"" + lock.packages[i].install_path + "\"\n"
        content += "    }"

    content += "\n  ]\n}\n"
    fs_write_file(path, content)


fn lockfile_find(lock: LockFile, name: String) -> Int:
    """Find a package by name in the lockfile. Returns index or -1."""
    for i in range(len(lock.packages)):
        if lock.packages[i].name == name:
            return i
    return -1

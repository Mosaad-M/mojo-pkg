# src/manifest.mojo
# Parse and write mojoproject.toml package descriptors.

from collections import Dict
from toml import TomlDoc, toml_parse, toml_get, toml_get_or, toml_has_section, toml_get_inline, toml_section_keys
from fs import fs_read_file, fs_write_file
from validate import validate_cdep_source, validate_cdep_name, validate_name


struct Dependency(Copyable, Movable):
    """A Mojo source dependency."""
    var name: String
    var git: String      # e.g. "Mosaad-M/tls"
    var version: String  # e.g. ">=1.0.0"

    fn __init__(out self, name: String, git: String, version: String):
        self.name = name
        self.git = git
        self.version = version

    fn __copyinit__(out self, copy: Self):
        self.name = copy.name
        self.git = copy.git
        self.version = copy.version

    fn __moveinit__(out self, deinit take: Self):
        self.name = take.name^
        self.git = take.git^
        self.version = take.version^


struct CDependency(Copyable, Movable):
    """A C library dependency compiled from source."""
    var name: String    # e.g. "errno_helper"
    var source: String  # e.g. "errno_helper.c"

    fn __init__(out self, name: String, source: String):
        self.name = name
        self.source = source

    fn __copyinit__(out self, copy: Self):
        self.name = copy.name
        self.source = copy.source

    fn __moveinit__(out self, deinit take: Self):
        self.name = take.name^
        self.source = take.source^


struct Manifest(Movable):
    """Parsed mojoproject.toml descriptor."""
    var name: String
    var version: String
    var description: String
    var license: String
    var mojo_requires: String
    var platforms: List[String]
    var deps: List[Dependency]
    var c_deps: List[CDependency]

    fn __init__(out self):
        self.name = String("")
        self.version = String("")
        self.description = String("")
        self.license = String("")
        self.mojo_requires = String("")
        self.platforms = List[String]()
        self.deps = List[Dependency]()
        self.c_deps = List[CDependency]()

    fn __moveinit__(out self, deinit take: Self):
        self.name = take.name^
        self.version = take.version^
        self.description = take.description^
        self.license = take.license^
        self.mojo_requires = take.mojo_requires^
        self.platforms = take.platforms^
        self.deps = take.deps^
        self.c_deps = take.c_deps^


fn manifest_parse_str(src: String) raises -> Manifest:
    """Parse a mojoproject.toml from a string."""
    var doc = toml_parse(src)
    var m = Manifest()

    # [package]
    m.name = toml_get_or(doc, "package", "name", "")
    m.version = toml_get_or(doc, "package", "version", "0.0.0")
    m.description = toml_get_or(doc, "package", "description", "")
    m.license = toml_get_or(doc, "package", "license", "")

    # [mojo]
    m.mojo_requires = toml_get_or(doc, "mojo", "requires", ">=0.26.1")

    # [package] platforms
    var plat_raw = toml_get_or(doc, "package", "platforms", "linux-64")
    var plat_bytes = plat_raw.as_bytes()
    if len(plat_bytes) > 0 and plat_bytes[0] == 91:  # [
        # Strip [ and ]
        var b = plat_raw.as_bytes()
        var out_b = List[UInt8](capacity=len(b))
        for i in range(1, len(b) - 1):
            if b[i] != 34:  # skip quotes
                out_b.append(b[i])
        var inner = String(unsafe_from_utf8=out_b^)
        var parts = inner.split(",")
        for p in parts:
            var pb = String(p).as_bytes()
            var trimmed = List[UInt8]()
            for i in range(len(pb)):
                if pb[i] != 32 and pb[i] != 9:
                    trimmed.append(pb[i])
            if len(trimmed) > 0:
                m.platforms.append(String(unsafe_from_utf8=trimmed^))
    else:
        var parts = plat_raw.split(",")
        for p in parts:
            var pb = String(p).as_bytes()
            var trimmed = List[UInt8]()
            for i in range(len(pb)):
                if pb[i] != 32 and pb[i] != 9:
                    trimmed.append(pb[i])
            if len(trimmed) > 0:
                m.platforms.append(String(unsafe_from_utf8=trimmed^))

    # [dependencies] — each key is a dep name with inline table value
    if toml_has_section(doc, "dependencies"):
        var keys = toml_section_keys(doc, "dependencies")
        for k in keys:
            var dep_name = k
            if dep_name == "__inline_table__":
                continue
            var git = String("")
            var ver = String("")
            try:
                git = toml_get_inline(doc, "dependencies", dep_name, "git")
            except:
                pass
            try:
                ver = toml_get_inline(doc, "dependencies", dep_name, "version")
            except:
                try:
                    ver = toml_get(doc, "dependencies", dep_name)
                    if ver == "__inline_table__":
                        ver = String("")
                except:
                    pass
            m.deps.append(Dependency(dep_name, git, ver))

    # [c-dependencies]
    if toml_has_section(doc, "c-dependencies"):
        var keys = toml_section_keys(doc, "c-dependencies")
        for k in keys:
            var lib_name = k
            var src = String("")
            # Try inline table first: errno_helper = { source = "errno_helper.c" }
            try:
                src = toml_get_inline(doc, "c-dependencies", lib_name, "source")
            except:
                # Fall back to plain string: errno_helper = "errno_helper.c"
                try:
                    var raw = toml_get(doc, "c-dependencies", lib_name)
                    if raw != "__inline_table__":
                        src = raw
                except:
                    pass
            if len(src) > 0:
                validate_cdep_name(lib_name)
                validate_cdep_source(src)
                m.c_deps.append(CDependency(lib_name, src))

    return m^


fn manifest_parse(path: String) raises -> Manifest:
    """Parse a mojoproject.toml file at the given path."""
    var src = fs_read_file(path)
    return manifest_parse_str(src)


fn _toml_escape(s: String) -> String:
    """Escape a string for use inside a TOML double-quoted string value.
    Replaces: backslash -> \\, double-quote -> \\", newline -> \\n."""
    var bytes = s.as_bytes()
    var n = len(bytes)
    var out = List[UInt8](capacity=n)
    for i in range(n):
        var b = bytes[i]
        if b == 92:  # backslash
            out.append(92)
            out.append(92)
        elif b == 34:  # double-quote
            out.append(92)
            out.append(34)
        elif b == 10:  # newline
            out.append(92)
            out.append(110)
        else:
            out.append(b)
    return String(unsafe_from_utf8=out^)


fn manifest_write(m: Manifest, path: String) raises:
    """Write a Manifest to a mojoproject.toml file."""
    var content = String("[package]\n")
    content += "name = \"" + _toml_escape(m.name) + "\"\n"
    content += "version = \"" + _toml_escape(m.version) + "\"\n"
    if len(m.description) > 0:
        content += "description = \"" + _toml_escape(m.description) + "\"\n"
    if len(m.license) > 0:
        content += "license = \"" + _toml_escape(m.license) + "\"\n"

    # platforms
    content += "platforms = ["
    for i in range(len(m.platforms)):
        if i > 0:
            content += ", "
        content += "\"" + _toml_escape(m.platforms[i]) + "\""
    content += "]\n"

    content += "\n[mojo]\n"
    content += "requires = \"" + _toml_escape(m.mojo_requires) + "\"\n"

    if len(m.deps) > 0:
        content += "\n[dependencies]\n"
        for i in range(len(m.deps)):
            content += m.deps[i].name + " = { git = \"" + _toml_escape(m.deps[i].git) + "\", version = \"" + _toml_escape(m.deps[i].version) + "\" }\n"

    if len(m.c_deps) > 0:
        content += "\n[c-dependencies]\n"
        for i in range(len(m.c_deps)):
            content += m.c_deps[i].name + " = \"" + _toml_escape(m.c_deps[i].source) + "\"\n"

    fs_write_file(path, content)


fn manifest_add_dep(mut m: Manifest, name: String, git: String, version: String) raises:
    """Add or update a dependency in the manifest."""
    validate_name(name)
    for i in range(len(m.deps)):
        if m.deps[i].name == name:
            m.deps[i].git = git
            m.deps[i].version = version
            return
    m.deps.append(Dependency(name, git, version))

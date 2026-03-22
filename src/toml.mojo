# toml.mojo
# Simple TOML subset parser for mojoproject.toml files.
# Supports: string values, integer values, inline tables { k = "v" },
# section headers [section], comments (#).
# Does NOT support: arrays of tables [[...]], multi-line strings, dates.

from std.collections import Dict


struct TomlDoc(Movable):
    """Parsed TOML document as a two-level dict: sections["section"]["key"] = "value"."""
    var sections: Dict[String, Dict[String, String]]

    def __init__(out self):
        self.sections = Dict[String, Dict[String, String]]()

    def __moveinit__(out self, deinit take: Self):
        self.sections = take.sections^


def _trim(s: String) -> String:
    """Strip leading and trailing whitespace."""
    var bytes = s.as_bytes()
    var start = 0
    var end = len(bytes)
    while start < end and (bytes[start] == 32 or bytes[start] == 9 or bytes[start] == 13 or bytes[start] == 10):
        start += 1
    while end > start and (bytes[end - 1] == 32 or bytes[end - 1] == 9 or bytes[end - 1] == 13 or bytes[end - 1] == 10):
        end -= 1
    if start >= end:
        return String("")
    var out = List[UInt8](capacity=end - start)
    for i in range(start, end):
        out.append(bytes[i])
    return String(unsafe_from_utf8=out^)


def _strip_comment(s: String) -> String:
    """Remove trailing # comment (respects quoted strings)."""
    var bytes = s.as_bytes()
    var in_quote = False
    for i in range(len(bytes)):
        if bytes[i] == 34 and not in_quote:  # "
            in_quote = True
        elif bytes[i] == 34 and in_quote:
            in_quote = False
        elif bytes[i] == 35 and not in_quote:  # #
            var out = List[UInt8](capacity=i)
            for j in range(i):
                out.append(bytes[j])
            return _trim(String(unsafe_from_utf8=out^))
    return s


def _unquote(s: String) raises -> String:
    """Strip surrounding double-quotes and unescape TOML basic string escape sequences.
    Handles: \\" -> ", \\\\ -> \\, \\n -> newline, \\r -> CR, \\t -> tab.
    \\uXXXX sequences are passed through literally (not decoded)."""
    var bytes = s.as_bytes()
    var n = len(bytes)
    if n >= 2 and bytes[0] == 34 and bytes[n - 1] == 34:  # "..."
        var out = List[UInt8](capacity=n - 2)
        var i = 1
        while i < n - 1:
            var b = bytes[i]
            if b == 92:  # backslash
                i += 1
                if i >= n - 1:
                    out.append(92)
                    break
                var esc = bytes[i]
                if esc == 34:        # \" -> "
                    out.append(34)
                elif esc == 92:      # \\ -> \
                    out.append(92)
                elif esc == 110:     # \n -> newline
                    out.append(10)
                elif esc == 114:     # \r -> CR
                    out.append(13)
                elif esc == 116:     # \t -> tab
                    out.append(9)
                elif esc == 117:     # \uXXXX -> pass through literally
                    out.append(92)
                    out.append(117)
                    var hex_count = 0
                    while hex_count < 4 and i + 1 < n - 1:
                        i += 1
                        out.append(bytes[i])
                        hex_count += 1
                else:
                    out.append(92)
                    out.append(esc)
            else:
                out.append(b)
            i += 1
        return String(unsafe_from_utf8=out^)
    return s


def _find_char(s: String, ch: UInt8, start: Int) -> Int:
    """Find first occurrence of ch in s starting at start. Returns -1 if not found."""
    var bytes = s.as_bytes()
    for i in range(start, len(bytes)):
        if bytes[i] == ch:
            return i
    return -1


def _substr(s: String, start: Int, end: Int) -> String:
    """Return s[start:end]."""
    var bytes = s.as_bytes()
    var n = len(bytes)
    var e = end if end <= n else n
    var st = start if start >= 0 else 0
    if st >= e:
        return String("")
    var out = List[UInt8](capacity=e - st)
    for i in range(st, e):
        out.append(bytes[i])
    return String(unsafe_from_utf8=out^)


def _parse_inline_table(s: String) raises -> Dict[String, String]:
    """Parse inline table: { key = "value", key2 = "value2" }"""
    var result = Dict[String, String]()
    var bytes = s.as_bytes()
    var n = len(bytes)

    var i = 0
    while i < n and bytes[i] != 123:  # {
        i += 1
    if i >= n:
        return result^
    i += 1  # skip {

    while i < n:
        while i < n and (bytes[i] == 32 or bytes[i] == 9):
            i += 1
        if i >= n or bytes[i] == 125:  # }
            break

        var key_start = i
        while i < n and bytes[i] != 61 and bytes[i] != 125 and bytes[i] != 32 and bytes[i] != 9:
            i += 1
        var key = _trim(_substr(s, key_start, i))

        while i < n and bytes[i] != 61:  # =
            i += 1
        if i >= n:
            break
        i += 1  # skip =

        while i < n and (bytes[i] == 32 or bytes[i] == 9):
            i += 1

        var val: String
        if i < n and bytes[i] == 34:  # "
            i += 1
            var val_start = i
            while i < n and bytes[i] != 34:
                i += 1
            val = _substr(s, val_start, i)
            i += 1  # skip closing "
        else:
            var val_start = i
            while i < n and bytes[i] != 44 and bytes[i] != 125 and bytes[i] != 32 and bytes[i] != 9:
                i += 1
            val = _substr(s, val_start, i)

        if len(key) > 0:
            result[key] = val

        while i < n and bytes[i] != 44 and bytes[i] != 125:
            i += 1
        if i < n and bytes[i] == 44:  # ,
            i += 1
    return result^


def toml_parse(src: String) raises -> TomlDoc:
    """Parse a TOML document. Returns a TomlDoc with all sections."""
    var doc = TomlDoc()
    var current_section = String("")

    doc.sections[current_section] = Dict[String, String]()

    var lines = src.split("\n")
    for line_s in lines:
        var line = _trim(String(line_s))
        if len(line) == 0 or line.as_bytes()[0] == 35:  # #
            continue

        var bytes = line.as_bytes()

        # Section header [section]
        if bytes[0] == 91:  # [
            var end = _find_char(line, 93, 1)  # ]
            if end > 0:
                current_section = _trim(_substr(line, 1, end))
                if not (current_section in doc.sections):
                    doc.sections[current_section] = Dict[String, String]()
            continue

        # Key = value
        var eq = _find_char(line, 61, 0)  # =
        if eq <= 0:
            continue

        var key = _trim(_substr(line, 0, eq))
        var raw_val = _trim(_strip_comment(_substr(line, eq + 1, len(line.as_bytes()))))

        var val_bytes = raw_val.as_bytes()
        if len(val_bytes) > 0 and val_bytes[0] == 123:  # {
            var sub = _parse_inline_table(raw_val)
            var sub_key = current_section + "." + key
            doc.sections[sub_key] = sub^
            doc.sections[current_section][key] = String("__inline_table__")
        else:
            doc.sections[current_section][key] = _unquote(raw_val)

    return doc^


def toml_get(doc: TomlDoc, section: String, key: String) raises -> String:
    """Get a string value from doc[section][key]. Raises if not found."""
    if section in doc.sections:
        var sec = doc.sections[section].copy()
        if key in sec:
            return sec[key]
    raise Error("TOML key not found: [" + section + "] " + key)


def toml_get_or(doc: TomlDoc, section: String, key: String, default: String) -> String:
    """Get a string value, returning default if not found."""
    try:
        if section in doc.sections:
            var sec = doc.sections[section].copy()
            if key in sec:
                return sec[key]
    except:
        pass
    return default


def toml_has_section(doc: TomlDoc, section: String) -> Bool:
    return section in doc.sections


def toml_get_inline(doc: TomlDoc, section: String, key: String, sub_key: String) raises -> String:
    """Get a value from an inline table: doc[section][key][sub_key]."""
    var inline_section = section + "." + key
    if inline_section in doc.sections:
        var sub = doc.sections[inline_section].copy()
        if sub_key in sub:
            return sub[sub_key]
    raise Error("TOML inline key not found: [" + section + "] " + key + "." + sub_key)


def toml_section_keys(doc: TomlDoc, section: String) raises -> List[String]:
    """Return all keys in a section."""
    if section in doc.sections:
        var result = List[String]()
        var sec = doc.sections[section].copy()
        for k in sec.keys():
            result.append(k)
        return result^
    raise Error("TOML section not found: [" + section + "]")

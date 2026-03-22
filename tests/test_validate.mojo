# tests/test_validate.mojo
# Tests for validate.mojo — all input validation functions.

from validate import validate_name, validate_version, validate_tarball_url, validate_cdep_name, validate_cdep_source


def assert_true(val: Bool, label: String) raises:
    if not val:
        raise Error("FAIL: " + label + " — expected True, got False")


def assert_no_raise(name: String, label: String) raises:
    """Assert validate_name does NOT raise."""
    try:
        validate_name(name)
    except e:
        raise Error("FAIL: " + label + " — unexpected raise: " + String(e))


def assert_raises_name(name: String, label: String) raises:
    """Assert validate_name DOES raise."""
    var raised = False
    try:
        validate_name(name)
    except:
        raised = True
    if not raised:
        raise Error("FAIL: " + label + " — expected Error to be raised for '" + name + "'")


def assert_no_raise_ver(ver: String, label: String) raises:
    try:
        validate_version(ver)
    except e:
        raise Error("FAIL: " + label + " — unexpected raise: " + String(e))


def assert_raises_ver(ver: String, label: String) raises:
    var raised = False
    try:
        validate_version(ver)
    except:
        raised = True
    if not raised:
        raise Error("FAIL: " + label + " — expected Error for version '" + ver + "'")


def assert_no_raise_url(url: String, label: String) raises:
    try:
        validate_tarball_url(url)
    except e:
        raise Error("FAIL: " + label + " — unexpected raise: " + String(e))


def assert_raises_url(url: String, label: String) raises:
    var raised = False
    try:
        validate_tarball_url(url)
    except:
        raised = True
    if not raised:
        raise Error("FAIL: " + label + " — expected Error for url '" + url + "'")


def assert_no_raise_cdep(name: String, label: String) raises:
    try:
        validate_cdep_name(name)
    except e:
        raise Error("FAIL: " + label + " — unexpected raise: " + String(e))


def assert_raises_cdep(name: String, label: String) raises:
    var raised = False
    try:
        validate_cdep_name(name)
    except:
        raised = True
    if not raised:
        raise Error("FAIL: " + label + " — expected Error for cdep name '" + name + "'")


def assert_no_raise_src(src: String, label: String) raises:
    try:
        validate_cdep_source(src)
    except e:
        raise Error("FAIL: " + label + " — unexpected raise: " + String(e))


def assert_raises_src(src: String, label: String) raises:
    var raised = False
    try:
        validate_cdep_source(src)
    except:
        raised = True
    if not raised:
        raise Error("FAIL: " + label + " — expected Error for cdep source '" + src + "'")


# ─── validate_name ─────────────────────────────────────────────────────────────

def test_valid_names() raises:
    assert_no_raise("a", "single char name")
    assert_no_raise("tls", "simple 3-char name")
    assert_no_raise("pkg2", "name with digit")
    assert_no_raise("my-pkg", "name with dash")
    assert_no_raise("my_pkg", "name with underscore")
    # 64-char max
    var long_name = String("a")
    for _ in range(63):
        long_name += "b"
    assert_no_raise(long_name, "64-char name (max allowed)")
    print("PASS: test_valid_names")


def test_invalid_names() raises:
    assert_raises_name("", "empty name")
    # 65-char name
    var too_long = String("a")
    for _ in range(64):
        too_long += "b"
    assert_raises_name(too_long, "65-char name (too long)")
    assert_raises_name("MyPkg", "uppercase letters")
    assert_raises_name("-mypkg", "leading dash")
    assert_raises_name("_mypkg", "leading underscore")
    assert_raises_name("my pkg", "contains space")
    assert_raises_name("my/pkg", "contains slash")
    print("PASS: test_invalid_names")


# ─── validate_version ──────────────────────────────────────────────────────────

def test_valid_versions() raises:
    assert_no_raise_ver("1.0.0", "1.0.0")
    assert_no_raise_ver("0.0.0", "0.0.0")
    assert_no_raise_ver("100.200.300", "large numbers")
    print("PASS: test_valid_versions")


def test_invalid_versions() raises:
    assert_raises_ver("", "empty version")
    assert_raises_ver("1.0", "only two parts")
    assert_raises_ver("1.0.0.0", "four parts (three dots)")
    assert_raises_ver("1.0.a", "letter in version")
    assert_raises_ver("0..0", "consecutive dots")
    assert_raises_ver("1.0.", "trailing dot")
    assert_raises_ver(".1.0", "leading dot")
    # version longer than 32 chars
    var long_ver = String("1")
    for _ in range(32):
        long_ver += "0"
    long_ver += ".0.0"
    assert_raises_ver(long_ver, "version > 32 chars")
    print("PASS: test_invalid_versions")


# ─── validate_tarball_url ──────────────────────────────────────────────────────

def test_valid_tarball_urls() raises:
    assert_no_raise_url("https://github.com/Mosaad-M/tls/archive/v1.0.0.tar.gz", "github tarball")
    assert_no_raise_url("https://github.com/x/y.tar.gz", "minimal github url")
    print("PASS: test_valid_tarball_urls")


def test_invalid_tarball_urls() raises:
    assert_raises_url("", "empty url")
    assert_raises_url("http://github.com/x/y.tar.gz", "http not https")
    assert_raises_url("https://gitlab.com/x/y.tar.gz", "non-github host")
    assert_raises_url("ftp://github.com/x/y.tar.gz", "ftp scheme")
    assert_raises_url("https://github.com/", "no path after github.com/")
    assert_raises_url("https://github.com/x/y;rm -rf ~", "semicolon in url")
    assert_raises_url("https://github.com/x/y$(id)", "dollar sign in url")
    print("PASS: test_invalid_tarball_urls")


# ─── validate_cdep_name ────────────────────────────────────────────────────────

def test_valid_cdep_names() raises:
    assert_no_raise_cdep("errno_helper", "underscore name")
    assert_no_raise_cdep("libfoo-2", "dash and digit")
    assert_no_raise_cdep("MyLib", "uppercase allowed in cdep")
    print("PASS: test_valid_cdep_names")


def test_invalid_cdep_names() raises:
    assert_raises_cdep("", "empty cdep name")
    assert_raises_cdep("my lib", "space in cdep name")
    assert_raises_cdep("lib;rm", "semicolon in cdep name")
    print("PASS: test_invalid_cdep_names")


# ─── validate_cdep_source ─────────────────────────────────────────────────────

def test_valid_cdep_sources() raises:
    assert_no_raise_src("errno_helper.c", "normal c source file")
    assert_no_raise_src("mylib.c", "simple name")
    print("PASS: test_valid_cdep_sources")


def test_invalid_cdep_sources() raises:
    assert_raises_src("", "empty source")
    assert_raises_src("src/errno_helper.c", "path with slash")
    assert_raises_src("../errno_helper.c", "path traversal")
    print("PASS: test_invalid_cdep_sources")


def main() raises:
    print("=== Validate Tests ===")
    test_valid_names()
    test_invalid_names()
    test_valid_versions()
    test_invalid_versions()
    test_valid_tarball_urls()
    test_invalid_tarball_urls()
    test_valid_cdep_names()
    test_invalid_cdep_names()
    test_valid_cdep_sources()
    test_invalid_cdep_sources()
    print("")
    print("All validate tests passed!")

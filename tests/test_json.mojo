# tests/test_json.mojo
# Tests for the JSON parser.

from json import parse_json, JsonValue


def assert_eq(a: String, b: String, label: String) raises:
    if a != b:
        raise Error("FAIL: " + label + " — expected '" + b + "', got '" + a + "'")


def assert_int_eq(a: Int, b: Int, label: String) raises:
    if a != b:
        raise Error("FAIL: " + label + " — expected " + String(b) + ", got " + String(a))


def assert_true(val: Bool, label: String) raises:
    if not val:
        raise Error("FAIL: " + label + " — expected True, got False")


def assert_false(val: Bool, label: String) raises:
    if val:
        raise Error("FAIL: " + label + " — expected False, got True")


def test_null() raises:
    var v = parse_json("null")
    assert_true(v.is_null(), "null: is_null()")
    print("PASS: test_null")


def test_bool_true() raises:
    var v = parse_json("true")
    assert_true(v.is_bool(), "bool true: is_bool()")
    assert_true(v.as_bool(), "bool true: as_bool() == true")
    print("PASS: test_bool_true")


def test_bool_false() raises:
    var v = parse_json("false")
    assert_true(v.is_bool(), "bool false: is_bool()")
    assert_false(v.as_bool(), "bool false: as_bool() == false")
    print("PASS: test_bool_false")


def test_integer() raises:
    var v = parse_json("42")
    assert_true(v.is_number(), "int: is_number()")
    assert_int_eq(v.as_int(), 42, "int: as_int() == 42")
    print("PASS: test_integer")


def test_negative_integer() raises:
    var v = parse_json("-7")
    assert_int_eq(v.as_int(), -7, "negative int: -7")
    print("PASS: test_negative_integer")


def test_float() raises:
    var v = parse_json("3.14")
    assert_true(v.is_number(), "float: is_number()")
    # as_number() returns Float64
    var f = v.as_number()
    assert_true(f > 3.13 and f < 3.15, "float: 3.14 approx")
    print("PASS: test_float")


def test_string() raises:
    var v = parse_json('"hello world"')
    assert_true(v.is_string(), "string: is_string()")
    assert_eq(v.as_string(), "hello world", "string: as_string()")
    print("PASS: test_string")


def test_empty_array() raises:
    var v = parse_json("[]")
    assert_true(v.is_array(), "empty array: is_array()")
    assert_int_eq(len(v), 0, "empty array: len == 0")
    print("PASS: test_empty_array")


def test_array_of_strings() raises:
    var v = parse_json('["a", "b", "c"]')
    assert_true(v.is_array(), "array of strings: is_array()")
    assert_int_eq(len(v), 3, "array of strings: len == 3")
    assert_eq(v.get_string(0), "a", "array[0] == 'a'")
    assert_eq(v.get_string(1), "b", "array[1] == 'b'")
    assert_eq(v.get_string(2), "c", "array[2] == 'c'")
    print("PASS: test_array_of_strings")


def test_nested_object() raises:
    var v = parse_json('{"key": {"subkey": "value"}}')
    assert_true(v.is_object(), "nested object: is_object()")
    var inner = v.get("key")
    assert_eq(inner.get_string("subkey"), "value", "nested object: subkey")
    print("PASS: test_nested_object")


def test_has_key_true() raises:
    var v = parse_json('{"name": "tls", "version": "1.0.0"}')
    assert_true(v.has_key("name"), "has_key: 'name' present")
    assert_true(v.has_key("version"), "has_key: 'version' present")
    print("PASS: test_has_key_true")


def test_has_key_false() raises:
    var v = parse_json('{"name": "tls"}')
    assert_false(v.has_key("missing"), "has_key: 'missing' not present")
    print("PASS: test_has_key_false")


def test_keys() raises:
    var v = parse_json('{"a": 1, "b": 2, "c": 3}')
    var keys = v.keys()
    assert_int_eq(len(keys), 3, "keys: count == 3")
    var found_a = False
    var found_b = False
    var found_c = False
    for k in keys:
        if k == "a":
            found_a = True
        if k == "b":
            found_b = True
        if k == "c":
            found_c = True
    assert_true(found_a, "keys: 'a' present")
    assert_true(found_b, "keys: 'b' present")
    assert_true(found_c, "keys: 'c' present")
    print("PASS: test_keys")


def test_len_array() raises:
    var v = parse_json("[1, 2, 3, 4, 5]")
    assert_int_eq(len(v), 5, "len array: 5 elements")
    print("PASS: test_len_array")


def test_len_object() raises:
    var v = parse_json('{"x": 1, "y": 2}')
    assert_int_eq(len(v), 2, "len object: 2 keys")
    print("PASS: test_len_object")


def test_get_by_index() raises:
    var v = parse_json("[10, 20, 30]")
    assert_int_eq(v.get(0).as_int(), 10, "get by index: [0] == 10")
    assert_int_eq(v.get(1).as_int(), 20, "get by index: [1] == 20")
    assert_int_eq(v.get(2).as_int(), 30, "get by index: [2] == 30")
    print("PASS: test_get_by_index")


def test_get_by_key() raises:
    var v = parse_json('{"name": "tls", "version": "1.0.0"}')
    assert_eq(v.get("name").as_string(), "tls", "get by key: name")
    assert_eq(v.get("version").as_string(), "1.0.0", "get by key: version")
    print("PASS: test_get_by_key")


def test_object_with_int_values() raises:
    var v = parse_json('{"count": 42, "total": 100}')
    assert_int_eq(v.get_int("count"), 42, "object int: count")
    assert_int_eq(v.get_int("total"), 100, "object int: total")
    print("PASS: test_object_with_int_values")


def main() raises:
    print("=== JSON Parser Tests ===")
    test_null()
    test_bool_true()
    test_bool_false()
    test_integer()
    test_negative_integer()
    test_float()
    test_string()
    test_empty_array()
    test_array_of_strings()
    test_nested_object()
    test_has_key_true()
    test_has_key_false()
    test_keys()
    test_len_array()
    test_len_object()
    test_get_by_index()
    test_get_by_key()
    test_object_with_int_values()
    print("")
    print("All JSON tests passed!")

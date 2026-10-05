# tests/test_registry_index.mojo
# Index fetching: the GitHub-API fallback used when raw.githubusercontent.com
# is unreachable (some networks filter it by TLS server name).

from http_client import HttpClient
from registry import index_api_url, index_get_from, _primary_is_answer


def assert_true(val: Bool, label: String) raises:
    if not val:
        raise Error("FAIL: " + label)


def test_api_url() raises:
    assert_true(
        index_api_url("packages/all.json")
        == "https://api.github.com/repos/Mosaad-M/mojo-pkg-index/contents/packages/all.json?ref=main",
        "API URL for packages/all.json",
    )
    print("  PASS: API URL")


def test_fallback_rules() raises:
    # A real answer from raw.githubusercontent.com is final
    assert_true(_primary_is_answer(200), "200 is final")
    assert_true(_primary_is_answer(404), "404 is final (package does not exist)")
    # Rate limiting and server errors fall back to the API
    assert_true(not _primary_is_answer(429), "429 falls back")
    assert_true(not _primary_is_answer(500), "500 falls back")
    assert_true(not _primary_is_answer(503), "503 falls back")
    print("  PASS: fallback rules")


def test_live_fallback() raises:
    # The primary is unusable (a private address, refused by HttpClient),
    # so the file must come from api.github.com. Needs network.
    var client = HttpClient()
    var resp = index_get_from("https://127.0.0.1:9", "index.json", client)
    assert_true(resp.status_code == 200, "API fallback status " + String(resp.status_code))
    var root = resp.json()
    assert_true(len(root.get("packages")) > 0, "index.json lists packages")
    print("  PASS: live fallback to api.github.com")


def main() raises:
    print("=== Registry Index Tests ===")
    test_api_url()
    test_fallback_rules()
    print("=== All registry index tests passed ===")

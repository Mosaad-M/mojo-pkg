# tests/test_registry_index_live.mojo
# Live check (needs network): fetching through the API fallback works.
# Run in CI's build-and-smoke jobs with GITHUB_TOKEN set.

from test_registry_index import test_live_fallback


def main() raises:
    print("=== Registry Index Live Test ===")
    test_live_fallback()

#!/usr/bin/env bash
# End-to-end resolver check against the live mojo-pkg-index.
# Usage: scripts/e2e_resolve.sh <path-to-mojo-pkg-binary>
#
# Each case writes a throwaway mojoproject.toml, runs `update --dry-run`
# (resolves without installing) and checks the resolved versions. The
# expectations encode facts of the live index: requests <= 1.1.0 needs
# json < 2.0.0 and requests 1.2.0 needs json >= 3.0.1.
set -euo pipefail
BIN="$1"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILED=0

resolve() {  # resolve <case-dir> <deps toml lines...>; prints "name version" lines
    local dir="$WORK/$1"; shift
    mkdir -p "$dir"
    {
        printf '[package]\nname = "e2e"\nversion = "0.1.0"\n\n[dependencies]\n'
        printf '%s\n' "$@"
    } > "$dir/mojoproject.toml"
    (cd "$dir" && "$BIN" update --dry-run 2>&1) | sed -n 's/^ *Resolved: \(.*\)$/\1/p'
}

check() {  # check <case> <output> <package> <python condition on version tuple v>
    local version
    version="$(printf '%s\n' "$2" | awk -v p="$3" '$1 == p {print $2}')"
    if [ -n "$version" ] && python3 -c "v = tuple(map(int, '$version'.split('.'))); import sys; sys.exit(0 if ($4) else 1)"; then
        echo "PASS: $1: $3 $version ($4)"
    else
        echo "FAIL: $1: $3 '${version:-missing}' does not satisfy $4"
        FAILED=1
    fi
}

out="$(resolve latest 'requests = { git = "Mosaad-M/requests", version = ">=1.0.0" }')"
check "latest requests" "$out" requests "v >= (1, 2, 0)"
check "latest requests" "$out" json "v >= (3, 0, 1)"

out="$(resolve pinned 'requests = { git = "Mosaad-M/requests", version = "=1.1.0" }')"
check "pinned requests 1.1.0" "$out" requests "v == (1, 1, 0)"
check "pinned requests 1.1.0" "$out" json "v < (2, 0, 0)"

out="$(resolve backtrack \
    'requests = { git = "Mosaad-M/requests", version = ">=1.0.0" }' \
    'json = { git = "Mosaad-M/json", version = "=1.1.0" }')"
check "backtrack" "$out" requests "v < (1, 2, 0)"
check "backtrack" "$out" json "v == (1, 1, 0)"

exit $FAILED

#!/usr/bin/env bash
# Build mojo-pkg binary and install to ~/.mojo/bin/mojo-pkg
set -e

INSTALL_DIR="$HOME/.mojo/bin"
mkdir -p "$INSTALL_DIR"

SELF="$(cd "$(dirname "$0")" && pwd)"

echo "Building mojo-pkg..."
TLS_PURE="${TLS_PURE:-$(cd "$SELF/../tls_pure" 2>/dev/null && pwd || echo "$SELF/../tls_pure")}"
mojo build "$SELF/src/main.mojo" \
    --mcpu x86-64-v2 \
    -I "$SELF/src" \
    -I "$TLS_PURE" \
    -o "$INSTALL_DIR/mojo-pkg"

echo "Installed to $INSTALL_DIR/mojo-pkg"
echo ""
echo "Add to PATH: export PATH=\"\$HOME/.mojo/bin:\$PATH\""

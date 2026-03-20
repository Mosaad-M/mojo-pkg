#!/usr/bin/env bash
set -e
INSTALL_DIR="${MOJO_PKG_INSTALL_DIR:-$HOME/.mojo/bin}"
mkdir -p "$INSTALL_DIR"
BASE_URL="https://github.com/Mosaad-M/mojo-pkg/releases/latest/download"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Installing mojo-pkg to $INSTALL_DIR..."
curl -fsSL "$BASE_URL/mojo-pkg-linux-64.tar.gz"        -o "$TMP_DIR/mojo-pkg.tar.gz"
curl -fsSL "$BASE_URL/mojo-pkg-linux-64.tar.gz.sha256" -o "$TMP_DIR/mojo-pkg.tar.gz.sha256"

# Verify checksum (file has "HASH  filename" format — rewrite filename to match)
cd "$TMP_DIR"
sed -i 's|mojo-pkg-linux-64.tar.gz|mojo-pkg.tar.gz|' mojo-pkg.tar.gz.sha256
sha256sum -c mojo-pkg.tar.gz.sha256 || { echo "SHA256 mismatch — aborting"; exit 1; }

tar xz -C "$INSTALL_DIR" -f mojo-pkg.tar.gz
echo "Done. Add to PATH: export PATH=\"$INSTALL_DIR:\$PATH\""

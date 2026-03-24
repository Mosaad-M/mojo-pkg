#!/usr/bin/env bash
set -e
INSTALL_DIR="${MOJO_PKG_INSTALL_DIR:-$HOME/.mojo/bin}"
mkdir -p "$INSTALL_DIR"
BASE_URL="https://github.com/Mosaad-M/mojo-pkg/releases/latest/download"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Detect platform
OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS-$ARCH" in
    Linux-x86_64)   BINARY="mojo-pkg-linux-64" ;;
    Darwin-arm64)   BINARY="mojo-pkg-osx-arm64" ;;
    Darwin-x86_64)  BINARY="mojo-pkg-osx-64" ;;
    *) echo "Unsupported platform: $OS-$ARCH"; exit 1 ;;
esac

echo "Installing mojo-pkg ($BINARY) to $INSTALL_DIR..."
curl -fsSL "$BASE_URL/${BINARY}.tar.gz"        -o "$TMP_DIR/mojo-pkg.tar.gz"
curl -fsSL "$BASE_URL/${BINARY}.tar.gz.sha256" -o "$TMP_DIR/mojo-pkg.tar.gz.sha256"

# Verify checksum (file has "HASH  filename" format — rewrite filename to match)
cd "$TMP_DIR"
sed -i.bak "s|${BINARY}.tar.gz|mojo-pkg.tar.gz|" mojo-pkg.tar.gz.sha256
if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c mojo-pkg.tar.gz.sha256 || { echo "SHA256 mismatch — aborting"; exit 1; }
else
    shasum -a 256 -c mojo-pkg.tar.gz.sha256 || { echo "SHA256 mismatch — aborting"; exit 1; }
fi

tar xz -C "$INSTALL_DIR" -f mojo-pkg.tar.gz
chmod +x "$INSTALL_DIR/mojo-pkg" "$INSTALL_DIR/mojo-pkg-bin"
echo "Done. Add to PATH: export PATH=\"$INSTALL_DIR:\$PATH\""

#!/usr/bin/env bash
set -e
INSTALL_DIR="${MOJO_PKG_INSTALL_DIR:-$HOME/.mojo/bin}"
mkdir -p "$INSTALL_DIR"
LATEST_URL="https://github.com/Mosaad-M/mojo-pkg/releases/latest/download/mojo-pkg-linux-64.tar.gz"
echo "Installing mojo-pkg to $INSTALL_DIR..."
curl -fsSL "$LATEST_URL" | tar xz -C "$INSTALL_DIR"
echo "Done. Add to PATH: export PATH=\"$INSTALL_DIR:\$PATH\""

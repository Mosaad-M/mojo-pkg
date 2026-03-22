#!/usr/bin/env bash
# Build mojo-pkg binary and install to ~/.mojo/bin/
# Installs two files:
#   mojo-pkg-bin  — compiled Mojo binary
#   mojo-pkg      — wrapper that sets LD_LIBRARY_PATH before exec
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
    -o "$INSTALL_DIR/mojo-pkg-bin"

# Write the wrapper script
cat > "$INSTALL_DIR/mojo-pkg" <<'WRAPPER'
#!/bin/bash
# Wrapper: finds Mojo runtime libs from any pixi env and runs mojo-pkg-bin.
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

LIB_DIR=""
for candidate in \
    "$HOME/mojo_pg/mojo-pkg/.pixi/envs/default/lib" \
    "$HOME/mojo_pg/requests/.pixi/envs/default/lib" \
    "$HOME/mojo_pg/tcp/.pixi/envs/default/lib" \
    "$HOME/mojo_pg/tls_pure/.pixi/envs/default/lib" \
    "$HOME/mojo_pg/websocket/.pixi/envs/default/lib"; do
    if [ -f "$candidate/libKGENCompilerRTShared.so" ]; then
        LIB_DIR="$candidate"
        break
    fi
done

if [ -z "$LIB_DIR" ]; then
    echo "mojo-pkg: could not find Mojo runtime libs (libKGENCompilerRTShared.so)" >&2
    echo "  Ensure at least one pixi environment exists under ~/mojo_pg/." >&2
    exit 1
fi

exec env LD_LIBRARY_PATH="$LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    "$SELF_DIR/mojo-pkg-bin" "$@"
WRAPPER
chmod +x "$INSTALL_DIR/mojo-pkg"

echo "Installed to $INSTALL_DIR/mojo-pkg"
echo ""
echo "Add to PATH: export PATH=\"\$HOME/.mojo/bin:\$PATH\""

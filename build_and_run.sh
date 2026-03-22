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
# Wrapper: finds Mojo runtime libs (libKGENCompilerRTShared.so) and runs mojo-pkg-bin.
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

_find_lib() {
    local lib="libKGENCompilerRTShared.so"

    # 1. Already findable via LD_LIBRARY_PATH or system ldconfig — no-op
    if ldconfig -p 2>/dev/null | grep -q "$lib"; then
        echo ""; return
    fi

    # 2. Walk up from CWD looking for a pixi env (works for any pixi project)
    local dir="$PWD"
    while [ "$dir" != "/" ] && [ "$dir" != "$HOME" ]; do
        local candidate="$dir/.pixi/envs/default/lib"
        if [ -f "$candidate/$lib" ]; then echo "$candidate"; return; fi
        dir="$(dirname "$dir")"
    done

    # 3. PIXI_PROJECT_ROOT (set when running inside pixi run)
    if [ -n "$PIXI_PROJECT_ROOT" ] && \
       [ -f "$PIXI_PROJECT_ROOT/.pixi/envs/default/lib/$lib" ]; then
        echo "$PIXI_PROJECT_ROOT/.pixi/envs/default/lib"; return
    fi

    # 4. Known fixed paths (local dev under ~/mojo_pg)
    for candidate in \
        "$HOME/mojo_pg/mojo-pkg/.pixi/envs/default/lib" \
        "$HOME/mojo_pg/requests/.pixi/envs/default/lib" \
        "$HOME/mojo_pg/tls_pure/.pixi/envs/default/lib" \
        "$HOME/mojo_pg/tcp/.pixi/envs/default/lib"; do
        if [ -f "$candidate/$lib" ]; then echo "$candidate"; return; fi
    done

    # 5. Last resort: find anywhere under $HOME (slow but reliable)
    local found
    found="$(find "$HOME" -name "$lib" -path "*/.pixi/*" 2>/dev/null | head -1)"
    if [ -n "$found" ]; then echo "$(dirname "$found")"; return; fi

    echo ""
}

LIB_DIR="$(_find_lib)"

if [ -n "$LIB_DIR" ]; then
    exec env LD_LIBRARY_PATH="$LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        "$SELF_DIR/mojo-pkg-bin" "$@"
else
    exec "$SELF_DIR/mojo-pkg-bin" "$@"
fi
WRAPPER
chmod +x "$INSTALL_DIR/mojo-pkg"

echo "Installed to $INSTALL_DIR/mojo-pkg"
echo ""
echo "Add to PATH: export PATH=\"\$HOME/.mojo/bin:\$PATH\""

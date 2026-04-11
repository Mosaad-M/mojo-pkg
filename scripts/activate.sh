#!/bin/bash
# Resolve TLS_PURE if not already set by the user.
# Tries ../tls_pure (CI convention) then ../tls (common local name).
if [ -z "$TLS_PURE" ]; then
    TLS_PURE="$(ls -d "$PIXI_PROJECT_ROOT/../tls_pure" "$PIXI_PROJECT_ROOT/../tls" 2>/dev/null | head -1)"
    export TLS_PURE
fi

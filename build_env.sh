#!/usr/bin/env bash
set -euo pipefail

# Keep the SDK and its cache outside this persistent source workspace.
EMSDK_DIR="$(realpath -m "${EMSDK_DIR:-/tmp/emsdk}")"
case "$EMSDK_DIR" in
  /tmp/*) ;;
  *) printf 'EMSDK_DIR must be under /tmp: %s\n' "$EMSDK_DIR" >&2; exit 1 ;;
esac
if [[ ! -d "$EMSDK_DIR/.git" ]]; then
  git clone https://github.com/emscripten-core/emsdk.git "$EMSDK_DIR"
fi
"$EMSDK_DIR/emsdk" install 3.1.74
"$EMSDK_DIR/emsdk" activate 3.1.74
printf 'SDK ready. Use: source "%s/emsdk_env.sh"\n' "$EMSDK_DIR"

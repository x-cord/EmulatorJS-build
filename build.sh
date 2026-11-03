#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${SKIP_SOURCE_UPDATE:-0}" != 1 ]]; then
  node "$ROOT/scripts/restore-sources.mjs"
fi
TARGET="${1:-all}"
case "$TARGET" in
  frontend|mame2003_plus|mednafen_wswan|all) ;;
  -h|--help)
    printf 'Usage: %s [frontend|mame2003_plus|mednafen_wswan|all]\n' "$0"
    printf 'Environment: JOBS (default 8), EMSDK_DIR (default /tmp/emsdk)\n'
    exit 0 ;;
  *) printf 'Unknown target: %s\n' "$TARGET" >&2; exit 1 ;;
esac
JOBS="${JOBS:-8}"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || { printf 'JOBS must be a positive integer\n' >&2; exit 1; }
mkdir -p "$ROOT/output/logs" "$ROOT/output/cores"
exec > >(tee "$ROOT/output/logs/$TARGET-$(date +%Y%m%d-%H%M%S).log") 2>&1

show_source() {
  printf '\nSource: %s\n' "$1"
  git -C "$ROOT/compile/$1" log -1 --format='%H %s'
  git -C "$ROOT/compile/$1" status --short --untracked-files=no
}

build_frontend() {
  show_source EmulatorJS
  (
    cd "$ROOT/compile/EmulatorJS"
    npm ci --include=dev
    rm -f data/emulator.min.js data/emulator.min.css data/emulator.min.js.map
    node minify/minify.js
    # The upstream minifier catches errors without a failing exit status.
    [[ -s data/emulator.min.js && -s data/emulator.min.css ]]
  )
  mkdir -p "$ROOT/output/frontend/data"
  rsync -a --delete --exclude=cores/ "$ROOT/compile/EmulatorJS/data/" "$ROOT/output/frontend/data/"
  git -C "$ROOT/compile/EmulatorJS" rev-parse HEAD > "$ROOT/output/frontend/source-commit.txt"
}

load_sdk() {
  local sdk_dir
  sdk_dir="$(realpath -m "${EMSDK_DIR:-/tmp/emsdk}")"
  case "$sdk_dir" in /tmp/*) ;; *) printf 'EMSDK_DIR must be under /tmp\n' >&2; exit 1 ;; esac
  [[ -f "$sdk_dir/emsdk_env.sh" ]] || { printf 'Run ./build_env.sh first (SDK: %s)\n' "$sdk_dir" >&2; exit 1; }
  set +u
  source "$sdk_dir/emsdk_env.sh"
  set -u
  local version
  version="$(emcc --version)"
  [[ "$version" == *' 3.1.74 '* ]] || { printf 'Emscripten 3.1.74 required; found:\n%s\n' "$version" >&2; exit 1; }
}

build_core() {
  local core="$1" work="$ROOT/work/$1"
  show_source "$core"
  show_source RetroArch
  (
    cd "$ROOT/compile/$core"
    emmake make clean platform=emscripten
    emmake make -j"$JOBS" platform=emscripten
  )
  mkdir -p "$work/RetroArch"
  rsync -a --delete --exclude=.git --exclude='*.o' --exclude='*.a' --exclude='*.bc' \
    --exclude='*_libretro.js' --exclude='*_libretro.wasm' \
    "$ROOT/compile/RetroArch/" "$work/RetroArch/"
  rm -f "$work/RetroArch/emulatorjs/"*_emscripten.bc "$work/RetroArch/libretro_emscripten.a"
  cp "$ROOT/compile/$core/${core}_libretro_emscripten.bc" "$work/RetroArch/emulatorjs/"
  (
    cd "$work/RetroArch/emulatorjs"
    # This script links every .bc in its directory; each core has its own work tree.
    emmake ./build-emulatorjs.sh --clean
    emmake ./build-emulatorjs.sh --clean --legacy
  )
  node "$ROOT/scripts/package-core-wasm.mjs" "$work/EmulatorJS/data/cores" \
    "$ROOT" "$ROOT/compile/$core" "$ROOT/output/cores" "$core"
  {
    printf 'core '; git -C "$ROOT/compile/$core" rev-parse HEAD
    printf 'frontend '; git -C "$ROOT/compile/EmulatorJS" rev-parse HEAD
    printf 'retroarch '; git -C "$ROOT/compile/RetroArch" rev-parse HEAD
    printf 'emscripten 3.1.74\n'
    sha256sum "$ROOT/output/cores/$core-wasm.data" "$ROOT/output/cores/$core-legacy-wasm.data"
  } > "$ROOT/output/cores/$core-build.txt"
}

if [[ "$TARGET" == frontend || "$TARGET" == all ]]; then build_frontend; fi
if [[ "$TARGET" != frontend ]]; then
  load_sdk
  if [[ "$TARGET" == all ]]; then
    build_core mame2003_plus
    build_core mednafen_wswan
  else
    build_core "$TARGET"
  fi
fi
printf '\nBuild complete: %s/output\n' "$ROOT"

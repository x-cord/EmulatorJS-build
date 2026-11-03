#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DESTINATION="${1:-$ROOT/../EmulatorJS/data}"
ONLY_CORE="${2:-}"
case "$ONLY_CORE" in ""|mame2003_plus|mednafen_wswan) ;; *) printf 'Unknown core: %s\n' "$ONLY_CORE" >&2; exit 1 ;; esac
installed=0
if [[ -z "$ONLY_CORE" && -s "$ROOT/output/frontend/data/emulator.min.js" ]]; then
  mkdir -p "$DESTINATION"
  rsync -a --exclude=cores/ "$ROOT/output/frontend/data/" "$DESTINATION/"
  printf 'Installed frontend in %s\n' "$DESTINATION"
  installed=1
fi
for core in mame2003_plus mednafen_wswan; do
  [[ -z "$ONLY_CORE" || "$ONLY_CORE" == "$core" ]] || continue
  if [[ -f "$ROOT/output/cores/$core-wasm.data" && -f "$ROOT/output/cores/$core-legacy-wasm.data" ]]; then
    if [[ "$core" == mame2003_plus ]]; then
      [[ -f "$ROOT/output/cores/$core-thread-wasm.data" && -f "$ROOT/output/cores/$core-thread-legacy-wasm.data" ]] || {
        printf 'Missing threaded MAME pair. Run ./build.sh mame2003_plus-thread first.\n' >&2; exit 1;
      }
    fi
    mkdir -p "$DESTINATION/cores/reports"
    cp "$ROOT/output/cores/$core-wasm.data" "$ROOT/output/cores/$core-legacy-wasm.data" "$DESTINATION/cores/"
    if [[ "$core" == mame2003_plus ]]; then
      cp "$ROOT/output/cores/$core-thread-wasm.data" "$ROOT/output/cores/$core-thread-legacy-wasm.data" "$DESTINATION/cores/"
    fi
    cp "$ROOT/output/cores/reports/$core.json" "$DESTINATION/cores/reports/"
    printf 'Installed %s standard and legacy core packages\n' "$core"
    installed=1
  fi
done
[[ "$installed" == 1 ]] || { printf 'No build output found. Run ./build.sh first.\n' >&2; exit 1; }

#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DESTINATION="${1:-$ROOT/../EmulatorJS/data}"
installed=0
if [[ -s "$ROOT/output/frontend/data/emulator.min.js" ]]; then
  mkdir -p "$DESTINATION"
  rsync -a --exclude=cores/ "$ROOT/output/frontend/data/" "$DESTINATION/"
  printf 'Installed frontend in %s\n' "$DESTINATION"
  installed=1
fi
for core in mame2003_plus mednafen_wswan; do
  if [[ -f "$ROOT/output/cores/$core-wasm.data" && -f "$ROOT/output/cores/$core-legacy-wasm.data" ]]; then
    mkdir -p "$DESTINATION/cores/reports"
    cp "$ROOT/output/cores/$core-wasm.data" "$ROOT/output/cores/$core-legacy-wasm.data" "$DESTINATION/cores/"
    cp "$ROOT/output/cores/reports/$core.json" "$DESTINATION/cores/reports/"
    printf 'Installed %s standard and legacy cores\n' "$core"
    installed=1
  fi
done
[[ "$installed" == 1 ]] || { printf 'No build output found. Run ./build.sh first.\n' >&2; exit 1; }

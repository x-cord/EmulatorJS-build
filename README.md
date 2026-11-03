# Building the EmulatorJS frontend and custom cores

This repository contains the build scripts and source manifest for our
EmulatorJS distribution. The EmulatorJS frontend, MAME 2003-Plus core,
Beetle WonderSwan core, and RetroArch frontend are pulled from their fork
repositories; they are not stored here.

## Sources

`scripts/restore-sources.mjs` clones or updates each source into `compile/`
using the repositories and branches in `sources.json`:

| Directory | Repository | Branch |
| --- | --- | --- |
| `compile/EmulatorJS` | https://github.com/x-cord/EmulatorJS | `xc` |
| `compile/mame2003_plus` | https://github.com/x-cord/mame2003-plus-libretro | `xc` |
| `compile/mednafen_wswan` | https://github.com/x-cord/beetle-wswan-libretro | `auto-rotation` |
| `compile/RetroArch` | https://github.com/x-cord/EmulatorJS-RetroArch | `xc` |

The MAME 2003-Plus core is maintained as an external repository.

## 1. Install prerequisites

On Debian/Ubuntu, install the build tools and Node.js 22:

```bash
sudo apt update
sudo apt install build-essential python3 git rsync p7zip-full pkg-config curl
node --version
npm --version
```

For the custom cores, the commands below use Make, Emscripten and 7-Zip.
The frontend build installs its JavaScript dependencies from the fork's
committed `package-lock.json`.

## 2. Install Emscripten in /tmp

```bash
./build_env.sh
```

This clones the SDK into `/tmp/emsdk`, installs and activates `3.1.74`.
It does not install an SDK in this repository. Core builds source the SDK's
environment automatically and check its version.

To reuse an SDK already installed under `/tmp`:

```bash
EMSDK_DIR=/tmp/opencode/emsdk ./build.sh all
```

`EMSDK_DIR` must be under `/tmp`.

## 3. Build

From this repository:

```bash
JOBS=8 ./build.sh all
```

Or choose one target:

```bash
./build.sh frontend
./build.sh mame2003_plus
./build.sh mednafen_wswan
```

The frontend target does not require Emscripten. It runs `npm ci` with the
fork's lockfile, then `node minify/minify.js`, and stages the data assets.

Each core target:

1. Refreshes `compile/` from the fork repositories unless
   `SKIP_SOURCE_UPDATE=1` is set.
2. Cleans and compiles the core with `platform=emscripten`.
3. Copies the RetroArch source into a separate `work/<core>/RetroArch/` tree.
4. Links standard WebGL2 and legacy WebGL1 variants. Only that core's `.bc`
   is placed in its linker directory, since `build-emulatorjs.sh` links every
   `.bc` it finds there.
5. Packages the JavaScript and WASM with `core.json`, `build.json`, and
   `license.txt`. MAME metadata includes `options.useKeyboard=true`.
6. Writes a fresh core report so EmulatorJS invalidates its cached core.

Output:

```text
output/
  frontend/data/                         # loader, minified frontend, CSS, languages, etc.
  cores/
    mame2003_plus-wasm.data
    mame2003_plus-legacy-wasm.data
    mednafen_wswan-wasm.data
    mednafen_wswan-legacy-wasm.data
    reports/<core>.json                  # cache invalidation / default WebGL2
    <core>-build.txt                     # source IDs, SDK version, package SHA256
  logs/<target>-<timestamp>.log
```

`work/`, `compile/`, and `output/` are ignored by the outer build repository.

## 4. Install into the served EmulatorJS directory

After building, install only MAME without replacing staged frontend assets or
other cores:

```bash
./install.sh ../EmulatorJS/data mame2003_plus
```

To install all staged output:

```bash
./install.sh
```

The default destination is `../EmulatorJS/data`, relative to this repository.
The installer copies staged frontend assets and whichever complete
standard/legacy core pairs were built, together with their reports. It
preserves other installed cores. To stage elsewhere:

```bash
./install.sh path/to/EmulatorJS/data
```

## 5. Refresh the sources

```bash
node scripts/restore-sources.mjs
```

This clones missing repositories and checks out the configured fork branches.
Set `SKIP_SOURCE_UPDATE=1` when running `build.sh` to use the existing
`compile/` checkouts without refreshing them.

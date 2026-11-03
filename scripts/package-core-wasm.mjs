import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';

// node scripts/package-core-wasm.mjs PACKAGES BUILD_REPO CORE_REPO DESTINATION [CORE_NAME]
const [packages, buildRepo, coreRepo, destination] = process.argv.slice(2, 6).map(p => resolve(p));
const coreName = process.argv[6] || 'mame2003_plus';
const threaded = process.argv.includes('--threads');
if (!packages || !buildRepo || !coreRepo || !destination) {
  throw new Error('Usage: node scripts/package-core-wasm.mjs PACKAGES BUILD_REPO CORE_REPO DESTINATION [CORE_NAME]');
}

mkdirSync(destination, { recursive: true });

const core = JSON.parse(readFileSync(join(buildRepo, 'cores.json'), 'utf8'))
  .find(entry => entry.name === coreName);
if (!core) throw new Error(`Core metadata missing for ${coreName}`);
if (coreName === 'mame2003_plus') core.options = { ...core.options, useKeyboard: true };

for (const variant of ['wasm', 'legacy-wasm']) {
  const scratch = mkdtempSync(join(tmpdir(), `${coreName}-package-`));
  try {
    const name = `${coreName}${threaded ? '-thread' : ''}-${variant}.data`;
    execFileSync('7z', ['x', '-y', `-o${scratch}`, join(packages, name)], { stdio: 'pipe' });
    writeFileSync(join(scratch, 'core.json'), `${JSON.stringify(core, null, 2)}\n`);
    copyFileSync(join(buildRepo, 'build.json'), join(scratch, 'build.json'));
    copyFileSync(join(coreRepo, core.license), join(scratch, 'license.txt'));
    const archive = join(scratch, name);
    const members = [`${coreName}_libretro.js`, `${coreName}_libretro.wasm`, 'core.json', 'build.json', 'license.txt'];
    if (threaded) members.push(`${coreName}_libretro.ww.js`);
    execFileSync('7z', ['a', '-t7z', archive, ...members], { cwd: scratch, stdio: 'pipe' });
    copyFileSync(archive, join(destination, name));
    console.log(`Installed ${join(destination, name)} with core metadata`);
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}

mkdirSync(join(destination, 'reports'), { recursive: true });
writeFileSync(join(destination, 'reports', `${coreName}.json`), `${JSON.stringify({ buildStart: Date.now(), options: { defaultWebGL2: true } })}\n`);

import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const manifest = JSON.parse(readFileSync(resolve(root, 'sources.json'), 'utf8'));
const git = (...args) => execFileSync('git', args, { stdio: 'inherit' });

mkdirSync(resolve(root, 'compile'), { recursive: true });
for (const source of manifest.sources) {
  const destination = resolve(root, source.directory);
  if (!existsSync(destination)) {
    git('clone', '--branch', source.branch, '--single-branch', source.repo, destination);
  } else {
    git('-C', destination, 'fetch', 'origin', source.branch);
    git('-C', destination, 'checkout', '--detach', 'FETCH_HEAD');
  }
  console.log(`Source ready: ${source.directory} (${source.repo} ${source.branch})`);
}

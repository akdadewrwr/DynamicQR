// Copies the ArkTS protocol sources to .gen/protocol/*.ts and runs the Node tests against them.
import { cpSync, mkdirSync, readdirSync, rmSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const src = join(here, '..', '..', 'entry', 'src', 'main', 'ets', 'protocol');
const gen = join(here, '.gen', 'protocol');
rmSync(join(here, '.gen'), { recursive: true, force: true });
mkdirSync(gen, { recursive: true });
for (const f of readdirSync(src)) {
  if (f.endsWith('.ets')) cpSync(join(src, f), join(gen, f.replace(/\.ets$/, '.ts')));
}
const tests = readdirSync(join(here, 'tests')).filter((f) => f.endsWith('.test.ts')).map((f) => join('tests', f));
const r = spawnSync(process.execPath, ['--disable-warning=ExperimentalWarning', '--import', './register.mjs', '--test', ...tests],
  { cwd: here, stdio: 'inherit' });
process.exit(r.status === null ? 1 : r.status);

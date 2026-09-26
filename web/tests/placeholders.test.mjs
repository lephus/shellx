// Checks scripts/check-placeholders.mjs, the guard `npm run build` runs before `astro build`.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const script = join(dirname(fileURLToPath(import.meta.url)), '..', 'scripts', 'check-placeholders.mjs');

function run(files) {
  const dir = mkdtempSync(join(tmpdir(), 'shellx-web-'));
  for (const [name, text] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, name)), { recursive: true });
    writeFileSync(join(dir, name), text);
  }
  return spawnSync(process.execPath, [script, dir], { encoding: 'utf8', cwd: dir });
}

test('fails and names every file and line that still has the placeholder', () => {
  const result = run({
    'pages/privacy.md': 'intro\nmáy chủ riêng do ShellX thuê tại **[quốc gia]**\n',
    'pages/en/privacy.md': 'a private server rented by ShellX in **[quốc gia]**\n',
    'pages/terms.md': 'nothing to fill in\n',
  });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Refusing to build: replace the \[quốc gia\] placeholder/);
  assert.match(result.stderr, /pages\/privacy\.md:2/);
  assert.match(result.stderr, /pages\/en\/privacy\.md:1/);
  assert.doesNotMatch(result.stderr, /terms\.md/);
});

test('also finds the placeholder typed in decomposed (NFD) form', () => {
  const result = run({ 'pages/privacy.md': `tại ${'[quốc gia]'.normalize('NFD')}\n` });
  assert.equal(result.status, 1);
});

test('passes once the country is filled in', () => {
  const result = run({ 'pages/privacy.md': 'máy chủ riêng do ShellX thuê tại **Singapore**\n' });
  assert.equal(result.status, 0);
  assert.equal(result.stderr, '');
});

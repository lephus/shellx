import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { bumpPubspec } from '../scripts/bump.mjs';

const script = fileURLToPath(new URL('../scripts/bump.mjs', import.meta.url));
const pubspec = (version) => `name: shellx_desktop\ndescription: ShellX\nversion: ${version}\nenvironment:\n  sdk: ^3.11.0\n`;

test('bumpPubspec sets the version and increments the build number', () => {
  assert.equal(bumpPubspec(pubspec('1.0.0+1'), '1.0.1', '1.0.0'), pubspec('1.0.1+2'));
  assert.equal(bumpPubspec(pubspec('1.0.0'), '1.1.0', '1.0.0'), pubspec('1.1.0+1'));
});

test('bumpPubspec only touches the version line', () => {
  const text = `${pubspec('1.0.0+4')}# version: 9.9.9 in a comment stays\n`;
  assert.equal(bumpPubspec(text, '2.0.0', '1.0.0'), `${pubspec('2.0.0+5')}# version: 9.9.9 in a comment stays\n`);
});

test('bumpPubspec refuses a version that is not x.y.z', () => {
  assert.throws(() => bumpPubspec(pubspec('1.0.0+1'), '1.1', '1.0.0'), /not a x\.y\.z version/);
  assert.throws(() => bumpPubspec(pubspec('1.0.0+1'), 'v1.1.0', '1.0.0'), /not a x\.y\.z version/);
});

test('bumpPubspec refuses a version that is not newer than the released one', () => {
  assert.throws(() => bumpPubspec(pubspec('1.2.0+3'), '1.2.0', '1.2.0'), /must be newer than the released 1\.2\.0/);
  assert.throws(() => bumpPubspec(pubspec('1.2.0+3'), '1.1.9', '1.2.0'), /must be newer than the released 1\.2\.0/);
});

test('bumpPubspec refuses to go below the version already in pubspec.yaml', () => {
  assert.throws(() => bumpPubspec(pubspec('1.3.0+3'), '1.2.5', '1.2.0'), /older than 1\.3\.0 in apps\/desktop\/pubspec\.yaml/);
});

function repo({ pubspecVersion, latest, whatsNew }) {
  const root = mkdtempSync(join(tmpdir(), 'shellx-bump-'));
  mkdirSync(join(root, 'apps/desktop/assets'), { recursive: true });
  mkdirSync(join(root, 'deploy'));
  writeFileSync(join(root, 'apps/desktop/pubspec.yaml'), pubspec(pubspecVersion));
  writeFileSync(join(root, 'deploy/relay.env'), `LATEST_AGENT_VERSION=${latest}\n`);
  writeFileSync(join(root, 'apps/desktop/assets/whats_new.json'), JSON.stringify(whatsNew));
  return root;
}

test('the CLI writes apps/desktop/pubspec.yaml and warns when whats_new.json has no entry', () => {
  const root = repo({ pubspecVersion: '1.0.0+1', latest: '1.0.0', whatsNew: {} });
  const run = spawnSync(process.execPath, [script, '1.0.1'], { cwd: root, encoding: 'utf8' });
  assert.equal(run.status, 0, run.stderr);
  assert.equal(readFileSync(join(root, 'apps/desktop/pubspec.yaml'), 'utf8'), pubspec('1.0.1+2'));
  assert.match(run.stdout, /1\.0\.0\+1 → 1\.0\.1\+2/);
  assert.match(run.stderr, /whats_new\.json has no "1\.0\.1" entry/);
});

test('the CLI does not warn when whats_new.json has the version', () => {
  const root = repo({ pubspecVersion: '1.0.0+1', latest: '1.0.0', whatsNew: { '1.1.0': { en: ['x'], vi: ['y'] } } });
  const run = spawnSync(process.execPath, [script, '1.1.0'], { cwd: root, encoding: 'utf8' });
  assert.equal(run.status, 0, run.stderr);
  assert.doesNotMatch(run.stderr, /whats_new/);
});

test('the CLI leaves pubspec.yaml alone and exits 1 on a bad version', () => {
  const root = repo({ pubspecVersion: '1.0.0+1', latest: '1.0.0', whatsNew: {} });
  const run = spawnSync(process.execPath, [script, '0.9.0'], { cwd: root, encoding: 'utf8' });
  assert.equal(run.status, 1);
  assert.match(run.stderr, /must be newer than the released 1\.0\.0/);
  assert.equal(readFileSync(join(root, 'apps/desktop/pubspec.yaml'), 'utf8'), pubspec('1.0.0+1'));
});

test('the CLI explains its usage without an argument', () => {
  const root = repo({ pubspecVersion: '1.0.0+1', latest: '1.0.0', whatsNew: {} });
  const run = spawnSync(process.execPath, [script], { cwd: root, encoding: 'utf8' });
  assert.equal(run.status, 1);
  assert.match(run.stderr, /usage: node release\/scripts\/bump\.mjs X\.Y\.Z/);
});

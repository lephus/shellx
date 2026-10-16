import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { announceRelayEnv, announceSiteConfig } from '../scripts/announce.mjs';

const script = fileURLToPath(new URL('../scripts/announce.mjs', import.meta.url));
const base = 'https://download.shellx.pro';

const relayEnv = (v) => [
  '# Relay settings shipped with every deploy.',
  'MIN_AGENT=1.0.0',
  'MIN_MOBILE=1.0.0',
  `LATEST_AGENT_VERSION=${v}`,
  `MAC_URL=${base}/desktop/${v}/ShellX-${v}.dmg`,
  `WIN_URL=${base}/desktop/${v}/ShellX-Setup-${v}.exe`,
  'RATE_LIMITS_ENABLED=true',
  '',
].join('\n');

const siteConfig = (v) => `{
  "desktopVersion": "${v}",
  "downloadBaseUrl": "https://download.shellx.pro/desktop",
  "appStoreUrl": null,
  "supportEmail": "someone@example.com"
}
`;

test('announceRelayEnv points the relay at the new installers and keeps every other line', () => {
  assert.equal(announceRelayEnv(relayEnv('1.0.0'), '1.0.1', base), relayEnv('1.0.1'));
});

test('announceRelayEnv never moves the relay back to an older version', () => {
  assert.equal(announceRelayEnv(relayEnv('1.2.0'), '1.1.0', base), relayEnv('1.2.0'));
  assert.equal(announceRelayEnv(relayEnv('1.2.0'), '1.2.0', base), relayEnv('1.2.0'));
});

test('announceRelayEnv refuses a relay.env without the three keys', () => {
  assert.throws(() => announceRelayEnv('MIN_AGENT=1.0.0\nLATEST_AGENT_VERSION=1.0.0\n', '1.0.1', base), /no MAC_URL/);
});

test('announceSiteConfig refuses a config without desktopVersion', () => {
  assert.throws(() => announceSiteConfig('{"downloadBaseUrl": "x"}\n', '1.0.1'), /no "desktopVersion"/);
});

test('announceSiteConfig bumps desktopVersion and keeps the file layout', () => {
  assert.equal(announceSiteConfig(siteConfig('1.0.0'), '1.0.1'), siteConfig('1.0.1'));
  assert.equal(announceSiteConfig(siteConfig('1.2.0'), '1.1.0'), siteConfig('1.2.0'));
});

function repo(v) {
  const root = mkdtempSync(join(tmpdir(), 'shellx-announce-'));
  mkdirSync(join(root, 'deploy'));
  mkdirSync(join(root, 'web/src'), { recursive: true });
  writeFileSync(join(root, 'deploy/relay.env'), relayEnv(v));
  writeFileSync(join(root, 'web/src/site.config.json'), siteConfig(v));
  return root;
}

test('the CLI rewrites both files and reports changed=true', () => {
  const root = repo('1.0.0');
  const output = join(root, 'github_output');
  writeFileSync(output, '');
  const run = spawnSync(process.execPath, [script, '1.0.1'], {
    cwd: root, encoding: 'utf8', env: { ...process.env, GITHUB_OUTPUT: output },
  });
  assert.equal(run.status, 0, run.stderr);
  assert.equal(readFileSync(join(root, 'deploy/relay.env'), 'utf8'), relayEnv('1.0.1'));
  assert.equal(readFileSync(join(root, 'web/src/site.config.json'), 'utf8'), siteConfig('1.0.1'));
  assert.equal(readFileSync(output, 'utf8'), 'changed=true\n');
});

test('the CLI reports changed=false when the relay and website already name the version', () => {
  const root = repo('1.0.0');
  const output = join(root, 'github_output');
  writeFileSync(output, '');
  const run = spawnSync(process.execPath, [script, '1.0.0'], {
    cwd: root, encoding: 'utf8', env: { ...process.env, GITHUB_OUTPUT: output },
  });
  assert.equal(run.status, 0, run.stderr);
  assert.equal(readFileSync(output, 'utf8'), 'changed=false\n');
});

test('the CLI refuses a version that is not x.y.z', () => {
  const root = repo('1.0.0');
  const run = spawnSync(process.execPath, [script, '1.0'], { cwd: root, encoding: 'utf8' });
  assert.equal(run.status, 1);
  assert.match(run.stderr, /not a x\.y\.z version/);
});

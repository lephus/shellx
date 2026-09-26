// Tests for deploy/rollout.sh with a fake `docker` on PATH (no Docker needed):
//   node --test deploy/tests/*.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const script = join(dirname(fileURLToPath(import.meta.url)), '..', 'rollout.sh');

// Fake docker: logs every call; `compose pull` fails for tag "unpullable"; the relay container is
// healthy unless .env's IMAGE_TAG is "broken".
const FAKE_DOCKER = `#!/usr/bin/env bash
echo "docker $* [IMAGE_TAG=\${IMAGE_TAG:-}]" >> "$CALLS"
if [[ "$1 $2" == "compose pull" && "\${IMAGE_TAG:-}" == unpullable ]]; then exit 1; fi
if [[ "$1 $2" == "compose ps" ]]; then echo relay-container-id; exit 0; fi
if [[ "$1" == inspect ]]; then
  if grep -q '^IMAGE_TAG=broken$' .env; then echo unhealthy; else echo healthy; fi
  exit 0
fi
exit 0
`;

function setup({ env = 'PROXY_NETWORK=proxy-net\nIMAGE_TAG=old\n', ownData = true } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'shellx-rollout-'));
  const home = join(root, 'home');
  const app = join(home, 'phu', 'shellx');
  const bin = join(root, 'bin');
  mkdirSync(app, { recursive: true });
  mkdirSync(bin);
  if (ownData) mkdirSync(join(app, 'data'));
  writeFileSync(join(app, '.env'), env);
  writeFileSync(join(bin, 'docker'), FAKE_DOCKER);
  chmodSync(join(bin, 'docker'), 0o755);
  const calls = join(root, 'calls.log');
  writeFileSync(calls, '');
  const run = (tag, appDir = 'phu/shellx', relayUid = String(process.getuid())) =>
    spawnSync('bash', [script, tag, appDir], {
      encoding: 'utf8',
      env: {
        PATH: `${bin}:${process.env.PATH}`, HOME: home, CALLS: calls, HEALTH_TIMEOUT_SECONDS: '3', RELAY_UID: relayUid,
      },
    });
  return { app, run, env: () => readFileSync(join(app, '.env'), 'utf8'), calls: () => readFileSync(calls, 'utf8') };
}

test('healthy: pulls with the new tag, then writes it to .env and restarts once; keeps PROXY_NETWORK', () => {
  const s = setup();
  const result = s.run('abc123');
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /relay is healthy on abc123/);
  assert.equal(s.env(), 'PROXY_NETWORK=proxy-net\nIMAGE_TAG=abc123\n');
  const calls = s.calls();
  assert.match(calls, /docker compose pull \[IMAGE_TAG=abc123\]/);
  assert.equal(calls.match(/compose up -d --remove-orphans/g).length, 1);
});

test('unhealthy: puts the previous tag back, restarts again and fails', () => {
  const s = setup();
  const result = s.run('broken');
  assert.equal(result.status, 1);
  assert.match(result.stderr, /not healthy within 3s on broken; rolling back to old/);
  assert.equal(s.env(), 'PROXY_NETWORK=proxy-net\nIMAGE_TAG=old\n');
  assert.equal(s.calls().match(/compose up -d --remove-orphans/g).length, 2);
});

test('first deploy unhealthy: nothing to roll back to, fails without a second restart', () => {
  const s = setup({ env: 'PROXY_NETWORK=proxy-net\n' });
  const result = s.run('broken');
  assert.equal(result.status, 1);
  assert.match(result.stderr, /rolling back to nothing/);
  assert.equal(s.calls().match(/compose up -d/g).length, 1);
});

test('images that cannot be pulled leave .env and the running stack untouched', () => {
  const s = setup();
  const result = s.run('unpullable');
  assert.equal(result.status, 1);
  assert.equal(s.env(), 'PROXY_NETWORK=proxy-net\nIMAGE_TAG=old\n');
  assert.doesNotMatch(s.calls(), /compose up/);
});

test('refuses to deploy without PROXY_NETWORK in .env', () => {
  const s = setup({ env: 'IMAGE_TAG=old\n' });
  const result = s.run('abc123');
  assert.equal(result.status, 1);
  assert.match(result.stderr, /PROXY_NETWORK is not set in .*phu\/shellx\/\.env/);
  assert.equal(s.calls(), '');
});

test('refuses to deploy when data/ does not belong to the relay user', () => {
  const s = setup();
  const result = s.run('abc123', 'phu/shellx', '1000' === String(process.getuid()) ? '4242' : '1000');
  assert.equal(result.status, 1);
  assert.match(result.stderr, /phu\/shellx\/data must belong to uid/);
  assert.equal(s.calls(), '');
});

test('creates the folder layout and accepts an absolute app dir', () => {
  const s = setup();
  const result = s.run('abc123', s.app);
  assert.equal(result.status, 0, result.stderr);
  for (const dir of ['data', 'backups', 'downloads/desktop', 'nginx-proxy', 'backup']) {
    assert.ok(statSync(join(s.app, dir)).isDirectory(), dir);
  }
});

// Tests for deploy/vps-deploy.sh: reaching the VPS, the ControlPath default, relay2 detection and the
// input validation. The fakes live in vps-fakes.mjs (see vps-deploy.test.mjs).
//   node --test deploy/tests/*.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, writeFileSync } from 'node:fs';
import { FIXED, deploySetup, esc } from './vps-fakes.mjs';

// --- reaching the VPS ---------------------------------------------------------------------------------

test('deploy: no password-less connection stops early and says how to open the shared connection', () => {
  const s = deploySetup();
  const result = s.run([], { FAKE_UNREACHABLE: '1' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /ssh -fN -M -S ~\/\.ssh\/cm-shellx-vps -o ControlPersist=10h higio@42\.115\.41\.70/);
  assert.equal(s.calls().some((l) => l.startsWith('rsync')), false);
  assert.equal(existsSync(s.macLock), false);
});

test('deploy: the ControlPath default only goes with the default target; another SHELLX_VPS needs its own options', () => {
  const s = deploySetup();
  const refused = s.run(['--dry-run'], { SHELLX_VPS: 'deploy@other.example' });
  assert.equal(refused.status, 1);
  assert.match(refused.stderr, /SHELLX_VPS_SSH_OPTS/);
  assert.match(refused.stderr, /never reused for another host/);
  assert.deepEqual(s.calls(), []);

  const explicitDefault = s.run(['--dry-run'], { SHELLX_VPS: 'higio@42.115.41.70' });
  assert.equal(explicitDefault.status, 0, explicitDefault.stderr);
  assert.match(explicitDefault.stdout, /ControlPath=~\/\.ssh\/cm-shellx-vps/);

  const custom = s.run(['--dry-run'], { SHELLX_VPS: 'deploy@host.example', SHELLX_VPS_SSH_OPTS: '-p 2222 -i /keys/id' });
  assert.equal(custom.status, 0, custom.stderr);
  assert.match(custom.stdout, new RegExp(`\\+ ssh -p 2222 -i /keys/id ${esc(FIXED)} deploy@host\\.example 'mkdir -p`));
  assert.match(custom.stdout, new RegExp(`-e 'ssh -p 2222 -i /keys/id ${esc(FIXED)}'`));
  assert.doesNotMatch(custom.stdout, /higio@|ControlPath/);

  const plain = s.run(['--dry-run'], { SHELLX_VPS_SSH_OPTS: '' });
  assert.equal(plain.status, 0, plain.stderr);
  assert.match(plain.stdout, new RegExp(`\\+ ssh ${esc(FIXED)} higio@42\\.115\\.41\\.70 'mkdir -p`));
  assert.doesNotMatch(plain.stdout, /ControlPath/);
});

// --- relay2 detection ---------------------------------------------------------------------------------

for (const [line, on] of [
  ['COMPOSE_PROFILES=relay2', true],
  ['COMPOSE_PROFILES=other,relay2', true],
  ['COMPOSE_PROFILES="relay2"', true],
  ["COMPOSE_PROFILES='x, relay2'", true],
  ['COMPOSE_PROFILES=relay20', false],
  ['COMPOSE_PROFILES=my-relay2', false],
  ['COMPOSE_PROFILES=other', false],
  [null, false],
]) {
  test(`deploy: relay2 is ${on ? 'on' : 'off'} for ${line === null ? 'no COMPOSE_PROFILES line' : line} (parsed as a comma list, like rollout.sh)`, () => {
    const s = deploySetup();
    if (line) writeFileSync(s.sandbox('.env'), `PROXY_NETWORK=proxy-net\nIMAGE_TAG=old\n${line}\n`);
    const result = s.run();
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.ok(s.calls().some((l) => l.endsWith('[relay2]')), 'asks the VPS');
    assert.equal(s.calls().some((l) => /^curl .*%\{http_code\}.* https:\/\/relay\.shellx\.pro\/v2\/relay$/.test(l)), on);
    // Whatever it decided, rollout.sh decided the same: the success line names relay2 only when it is on.
    assert.equal(/relay, relay2 and web are healthy/.test(result.stdout), on);
  });
}

test('deploy: RELAY2_ENABLED=true forces the /v2/relay check without asking, and a wrong answer fails the run', () => {
  const s = deploySetup();
  const result = s.run([], { RELAY2_ENABLED: 'true', FAKE_V2_CODE: '404' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /v2\/relay did not answer 400 426/);
  assert.equal(s.calls().some((l) => l.endsWith('[relay2]')), false);
  // A smoke failure keeps the build sources for a look.
  assert.equal(s.calls().some((l) => l.includes('rm -rf')), false);
});

// --- inputs -------------------------------------------------------------------------------------------

for (const [name, env] of [
  ['an absolute APP_DIR', { APP_DIR: '/srv/other' }],
  ['a parent-directory APP_DIR', { APP_DIR: 'phu/../other' }],
  ['an APP_DIR with a space', { APP_DIR: 'phu/my shellx' }],
  ['an APP_DIR starting with a dash', { APP_DIR: '-rf' }],
  ['an option-like SHELLX_VPS', { SHELLX_VPS: '-oProxyCommand=evil' }],
  ['a SHELLX_VPS with a shell metacharacter', { SHELLX_VPS: 'a@b;rm' }],
  ['a bad RELAY2_ENABLED', { RELAY2_ENABLED: 'maybe' }],
  ['a bad SHELLX_ROLLOUT_TIMEOUT', { SHELLX_ROLLOUT_TIMEOUT: 'soon' }],
]) {
  test(`deploy refuses ${name}`, () => {
    const s = deploySetup();
    const result = s.run([], env);
    assert.equal(result.status, 1);
    assert.deepEqual(s.calls(), []);
  });
}

test('deploy rejects an unknown argument', () => {
  const s = deploySetup();
  const result = s.run(['--force']);
  assert.equal(result.status, 2);
  assert.deepEqual(s.calls(), []);
});

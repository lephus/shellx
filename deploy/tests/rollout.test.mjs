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

// Fake docker: logs every call; `compose pull` fails for tag "unpullable"; `compose up -d` itself
// fails outright (exit 17, unrelated to health) whenever .env's IMAGE_TAG starts with "crash"; the
// relay container is unhealthy when .env's IMAGE_TAG is "broken", the web container is unhealthy
// when it is "webbroken" (both healthy otherwise); `compose ps -q <service>` returns
// "<service>-container-id" so `inspect` (given that id as its last argument) can tell them apart.
const FAKE_DOCKER = `#!/usr/bin/env bash
echo "docker $* [IMAGE_TAG=\${IMAGE_TAG:-}]" >> "$CALLS"
if [[ "$1 $2" == "compose pull" && "\${IMAGE_TAG:-}" == unpullable ]]; then exit 1; fi
if [[ "$1 $2" == "compose up" ]] && grep -q '^IMAGE_TAG=crash' .env; then exit 17; fi
if [[ "$1 $2" == "compose ps" ]]; then echo "\${@: -1}-container-id"; exit 0; fi
if [[ "$1" == inspect ]]; then
  id="\${@: -1}"
  if [[ "$id" == relay-container-id ]] && grep -q '^IMAGE_TAG=broken$' .env; then
    echo unhealthy
  elif [[ "$id" == web-container-id ]] && grep -q '^IMAGE_TAG=webbroken$' .env; then
    echo unhealthy
  else
    echo healthy
  fi
  exit 0
fi
exit 0
`;

// Writes the four items rollout.sh swaps together (deploy.yml stages these into .incoming/; .prev/
// is where the previous ones land): docker-compose.yml, relay.env and two directories (nginx-proxy/,
// backup/) each holding one marker file, so a directory swap is exercised too. Exported so tests can
// also build a .prev/ or a partial .incoming/ directly, to simulate a crash mid-swap.
function writeConfigAt(dir, content) {
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'docker-compose.yml'), content.compose);
  writeFileSync(join(dir, 'relay.env'), content.relayEnv);
  mkdirSync(join(dir, 'nginx-proxy'), { recursive: true });
  writeFileSync(join(dir, 'nginx-proxy', 'marker'), content.nginxMarker);
  mkdirSync(join(dir, 'backup'), { recursive: true });
  writeFileSync(join(dir, 'backup', 'marker'), content.backupMarker);
}

function setup({
  env = 'PROXY_NETWORK=proxy-net\nIMAGE_TAG=old\n', ownData = true, live = null, incoming = null,
} = {}) {
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
  if (live) writeConfigAt(app, live);
  if (incoming) writeConfigAt(join(app, '.incoming'), incoming);
  const run = (tag, appDir = 'phu/shellx', relayUid = String(process.getuid())) =>
    spawnSync('bash', [script, tag, appDir], {
      encoding: 'utf8',
      env: {
        PATH: `${bin}:${process.env.PATH}`, HOME: home, CALLS: calls, HEALTH_TIMEOUT_SECONDS: '3', RELAY_UID: relayUid,
      },
    });
  return {
    app,
    run,
    env: () => readFileSync(join(app, '.env'), 'utf8'),
    calls: () => readFileSync(calls, 'utf8'),
    read: (relPath) => readFileSync(join(app, relPath), 'utf8'),
  };
}

const OLD_CONFIG = {
  compose: 'old compose\n', relayEnv: 'old relay env\n', nginxMarker: 'old nginx\n', backupMarker: 'old backup\n',
};
const NEW_CONFIG = {
  compose: 'new compose\n', relayEnv: 'new relay env\n', nginxMarker: 'new nginx\n', backupMarker: 'new backup\n',
};

test('healthy: pulls with the new tag, then writes it to .env and restarts once; keeps PROXY_NETWORK', () => {
  const s = setup();
  const result = s.run('abc123');
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /relay and web are healthy on abc123/);
  assert.equal(s.env(), 'PROXY_NETWORK=proxy-net\nIMAGE_TAG=abc123\n');
  const calls = s.calls();
  assert.match(calls, /docker compose pull \[IMAGE_TAG=abc123\]/);
  assert.equal(calls.match(/compose up -d --remove-orphans --force-recreate/g).length, 1);
  // Both services are checked, not just the relay (M3).
  assert.match(calls, /compose ps -q relay/);
  assert.match(calls, /compose ps -q web/);
});

test('rolls back when the web container is unhealthy even though the relay is healthy', () => {
  const s = setup();
  const result = s.run('webbroken');
  assert.equal(result.status, 1);
  assert.match(result.stderr, /not healthy within 3s on webbroken; rolling back to old/);
  assert.equal(s.env(), 'PROXY_NETWORK=proxy-net\nIMAGE_TAG=old\n');
  assert.doesNotMatch(s.calls(), /image prune/);
});

test('does not print container logs into the caller output, only a hint to run them on the VPS', () => {
  const s = setup();
  const result = s.run('broken');
  assert.equal(result.status, 1);
  assert.doesNotMatch(s.calls(), /compose logs/);
  assert.match(result.stderr, /see why on the VPS: docker compose logs --tail 50 relay web/);
});

test('prunes old images labelled as ShellX only after a healthy rollout, never after a rollback', () => {
  const healthy = setup();
  const healthyResult = healthy.run('abc123');
  assert.equal(healthyResult.status, 0, healthyResult.stderr);
  assert.match(
    healthy.calls(),
    /image prune -af --filter label=org\.opencontainers\.image\.source=https:\/\/github\.com\/lephus\/shellx --filter until=168h/,
  );

  const failing = setup();
  const failingResult = failing.run('broken');
  assert.equal(failingResult.status, 1);
  assert.doesNotMatch(failing.calls(), /image prune/);
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

test('an outright failure of the first `compose up -d` rolls back to the previous tag and fails', () => {
  const s = setup();
  const result = s.run('crashnew');
  assert.equal(result.status, 1);
  assert.match(result.stderr, /not healthy within 3s on crashnew; rolling back to old/);
  assert.equal(s.env(), 'PROXY_NETWORK=proxy-net\nIMAGE_TAG=old\n');
  assert.equal(s.calls().match(/compose up -d --remove-orphans/g).length, 2);
});

test('when both `compose up -d` calls fail outright, the rollback diagnostic still prints and .env keeps the old tag', () => {
  const s = setup({ env: 'PROXY_NETWORK=proxy-net\nIMAGE_TAG=crashold\n' });
  const result = s.run('crashnew');
  assert.equal(result.status, 1);
  assert.match(result.stderr, /not healthy within 3s on crashnew; rolling back to crashold/);
  assert.match(result.stderr, /the previous release \(crashold\) is not healthy either/);
  assert.equal(s.env(), 'PROXY_NETWORK=proxy-net\nIMAGE_TAG=crashold\n');
  assert.equal(s.calls().match(/compose up -d --remove-orphans/g).length, 2);
});

test('refuses to deploy when data/ does not exist yet, and creates nothing', () => {
  const s = setup({ ownData: false });
  const result = s.run('abc123');
  assert.equal(result.status, 1);
  assert.match(result.stderr, /phu\/shellx\/data does not exist/);
  assert.throws(() => statSync(join(s.app, 'data')));
  assert.throws(() => statSync(join(s.app, 'backups')));
  assert.equal(s.calls(), '');
});

// --- Staged config (deploy.yml's .incoming/), swapped with a .prev/ backup (fix round 1, item 1b) ---

test('a bad deploy restores the old relay.env and docker-compose.yml byte-for-byte, and the old tag', () => {
  const s = setup({ live: OLD_CONFIG, incoming: NEW_CONFIG });
  const result = s.run('broken');
  assert.equal(result.status, 1);
  assert.equal(s.read('docker-compose.yml'), OLD_CONFIG.compose);
  assert.equal(s.read('relay.env'), OLD_CONFIG.relayEnv);
  assert.equal(s.read('nginx-proxy/marker'), OLD_CONFIG.nginxMarker);
  assert.equal(s.read('backup/marker'), OLD_CONFIG.backupMarker);
  assert.equal(s.env(), 'PROXY_NETWORK=proxy-net\nIMAGE_TAG=old\n');
  assert.throws(() => statSync(join(s.app, '.incoming')));
});

test('a failed pull leaves the live files unchanged', () => {
  const s = setup({ live: OLD_CONFIG, incoming: NEW_CONFIG });
  const result = s.run('unpullable');
  assert.equal(result.status, 1);
  assert.equal(s.read('docker-compose.yml'), OLD_CONFIG.compose);
  assert.equal(s.read('relay.env'), OLD_CONFIG.relayEnv);
  assert.equal(s.read('nginx-proxy/marker'), OLD_CONFIG.nginxMarker);
  assert.equal(s.read('backup/marker'), OLD_CONFIG.backupMarker);
  assert.equal(s.env(), 'PROXY_NETWORK=proxy-net\nIMAGE_TAG=old\n');
  assert.doesNotMatch(s.calls(), /compose up/);
});

test('a successful deploy leaves the new files live and the old ones in .prev/', () => {
  const s = setup({ live: OLD_CONFIG, incoming: NEW_CONFIG });
  const result = s.run('abc123');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(s.read('docker-compose.yml'), NEW_CONFIG.compose);
  assert.equal(s.read('relay.env'), NEW_CONFIG.relayEnv);
  assert.equal(s.read('nginx-proxy/marker'), NEW_CONFIG.nginxMarker);
  assert.equal(s.read('backup/marker'), NEW_CONFIG.backupMarker);
  assert.equal(s.read('.prev/docker-compose.yml'), OLD_CONFIG.compose);
  assert.equal(s.read('.prev/relay.env'), OLD_CONFIG.relayEnv);
  assert.equal(s.read('.prev/nginx-proxy/marker'), OLD_CONFIG.nginxMarker);
  assert.equal(s.read('.prev/backup/marker'), OLD_CONFIG.backupMarker);
  assert.throws(() => statSync(join(s.app, '.incoming')));
});

test('a second staged deploy replaces the older .prev/ instead of merging with it', () => {
  const s = setup({ live: OLD_CONFIG, incoming: NEW_CONFIG });
  const first = s.run('abc123');
  assert.equal(first.status, 0, first.stderr);
  const NEWER_CONFIG = {
    compose: 'newer compose\n', relayEnv: 'newer relay env\n', nginxMarker: 'newer nginx\n', backupMarker: 'newer backup\n',
  };
  mkdirSync(join(s.app, '.incoming'));
  writeFileSync(join(s.app, '.incoming', 'docker-compose.yml'), NEWER_CONFIG.compose);
  writeFileSync(join(s.app, '.incoming', 'relay.env'), NEWER_CONFIG.relayEnv);
  mkdirSync(join(s.app, '.incoming', 'nginx-proxy'));
  writeFileSync(join(s.app, '.incoming', 'nginx-proxy', 'marker'), NEWER_CONFIG.nginxMarker);
  mkdirSync(join(s.app, '.incoming', 'backup'));
  writeFileSync(join(s.app, '.incoming', 'backup', 'marker'), NEWER_CONFIG.backupMarker);
  const second = s.run('def456');
  assert.equal(second.status, 0, second.stderr);
  assert.equal(s.read('docker-compose.yml'), NEWER_CONFIG.compose);
  assert.equal(s.read('.prev/docker-compose.yml'), NEW_CONFIG.compose);
  assert.equal(s.read('.prev/relay.env'), NEW_CONFIG.relayEnv);
});

// --- M5: skip a no-op swap; T8 fold: crash-safe stage_config via .prev.new ---

test('a re-deploy of an identical config keeps the older .prev/ untouched', () => {
  const s = setup({ live: NEW_CONFIG, incoming: NEW_CONFIG });
  // A .prev/ already on disk from an earlier, unrelated swap must survive a no-op restage.
  writeConfigAt(join(s.app, '.prev'), OLD_CONFIG);
  const result = s.run('abc123');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(s.read('docker-compose.yml'), NEW_CONFIG.compose);
  assert.equal(s.read('relay.env'), NEW_CONFIG.relayEnv);
  assert.equal(s.read('.prev/docker-compose.yml'), OLD_CONFIG.compose);
  assert.equal(s.read('.prev/relay.env'), OLD_CONFIG.relayEnv);
  assert.throws(() => statSync(join(s.app, '.incoming')));
});

test('discards a stale .prev.new left by a crash before staging, and deploys normally', () => {
  const s = setup({ live: OLD_CONFIG, incoming: NEW_CONFIG });
  writeConfigAt(join(s.app, '.prev.new'), {
    compose: 'garbage\n', relayEnv: 'garbage\n', nginxMarker: 'garbage\n', backupMarker: 'garbage\n',
  });
  const result = s.run('abc123');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(s.read('docker-compose.yml'), NEW_CONFIG.compose);
  assert.equal(s.read('.prev/docker-compose.yml'), OLD_CONFIG.compose);
  assert.throws(() => statSync(join(s.app, '.prev.new')));
});

test('heals a live item left missing by a crash between removing it and moving its replacement in', () => {
  const s = setup();
  // Simulates a run that crashed mid-swap: docker-compose.yml, nginx-proxy/ and backup/ had already
  // been swapped to the new config; relay.env was removed but its replacement never arrived (still
  // sitting in .incoming/); .prev/ (built before any of that, in one piece) still holds the full old
  // config.
  writeFileSync(join(s.app, 'docker-compose.yml'), NEW_CONFIG.compose);
  mkdirSync(join(s.app, 'nginx-proxy'), { recursive: true });
  writeFileSync(join(s.app, 'nginx-proxy', 'marker'), NEW_CONFIG.nginxMarker);
  mkdirSync(join(s.app, 'backup'), { recursive: true });
  writeFileSync(join(s.app, 'backup', 'marker'), NEW_CONFIG.backupMarker);
  // relay.env is deliberately absent from the live app dir: the crashed run removed it.
  writeConfigAt(join(s.app, '.prev'), OLD_CONFIG);
  mkdirSync(join(s.app, '.incoming'), { recursive: true });
  writeFileSync(join(s.app, '.incoming', 'relay.env'), NEW_CONFIG.relayEnv);

  const result = s.run('abc123');
  assert.equal(result.status, 0, result.stderr);
  // The live config ends up fully consistent (nothing missing), whichever of the four items the
  // crashed run had already replaced before it died.
  assert.equal(s.read('docker-compose.yml'), NEW_CONFIG.compose);
  assert.equal(s.read('relay.env'), NEW_CONFIG.relayEnv);
  assert.equal(s.read('nginx-proxy/marker'), NEW_CONFIG.nginxMarker);
  assert.equal(s.read('backup/marker'), NEW_CONFIG.backupMarker);
  assert.throws(() => statSync(join(s.app, '.incoming')));
});

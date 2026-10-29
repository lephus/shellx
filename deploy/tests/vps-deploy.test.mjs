// Tests for deploy/vps-deploy.sh: the order of the steps, the DETACHED rollout (a dropped ssh session does
// not stop it), the origin/main check, the room check and the locks. Nothing leaves the machine: ssh,
// rsync, curl, docker, timeout and caffeinate are fakes (vps-fakes.mjs); the scripts sent to the VPS and
// rollout.sh itself really run, in a sandbox "remote home".
//   node --test deploy/tests/*.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  FIXED, ROLLOUT_SCRIPT, SSH_DEFAULT, deploySetup, esc, waitFor,
} from './vps-fakes.mjs';

test('deploy --dry-run prints every step with the defaults and runs no ssh, rsync or curl', () => {
  const s = deploySetup();
  const result = s.run(['--dry-run'], { RELAY2_ENABLED: 'true' });
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(s.calls(), []);
  const out = result.stdout;
  // The defaults: the user's target and ControlMaster socket, the app folder, the fixed options everywhere.
  assert.match(out, new RegExp(`${esc(SSH_DEFAULT)} 'mkdir -p phu/shellx/\\.build-src/[0-9a-f]{40}'`));
  assert.match(out, new RegExp(`rsync -rt --delete -e '${esc(`ssh -o ControlPath=~/.ssh/cm-shellx-vps ${FIXED}`)}' deploy/nginx-proxy/ higio@42\\.115\\.41\\.70:phu/shellx/\\.incoming/nginx-proxy/`));
  assert.match(out, /timeout 30m docker build -t "ghcr\.io\/lephus\/shellx-relay:\$sha" relay/);
  assert.match(out, /timeout 30m docker build -f web\/Dockerfile -t "ghcr\.io\/lephus\/shellx-web:\$sha" \./);
  assert.match(out, /\+ git fetch origin main/);
  assert.match(out, /mkdir "\$app_dir\/\.deploy\.lock"/);
  assert.match(out, /MemAvailable/);
  assert.match(out, /rsync -t -e .* deploy\/rollout\.sh higio@42\.115\.41\.70:phu\/shellx\/\.rollout\/[0-9a-f]{40}\.sh/);
  assert.match(out, /setsid nohup bash/);
  assert.match(out, /SHELLX_LOCAL_IMAGES=1 bash "\$dir\/\$sha\.sh" "\$sha" "\$app_dir"/);
  assert.match(out, /\+ check https:\/\/relay\.shellx\.pro\/v1\/version/);
  assert.match(out, /rm -rf -- phu\/shellx\/\.build-src\/[0-9a-f]{40}/);
});

test('deploy --dry-run warns about a dirty tree but a real run refuses it', () => {
  const s = deploySetup();
  s.put('relay/src/server.ts', 'changed\n');
  const dry = s.run(['--dry-run']);
  assert.equal(dry.status, 0, dry.stderr);
  assert.match(dry.stderr, /a real run would refuse/);
  const real = s.run();
  assert.equal(real.status, 1);
  assert.match(real.stderr, /uncommitted changes/);
  assert.match(real.stderr, /relay\/src\/server\.ts/);
  assert.deepEqual(s.calls(), []);
});

for (const [what, rel] of [
  ['an edited file under relay/', 'relay/src/server.ts'],
  ['a new file under web/', 'web/src/new-page.astro'],
  ['an edited file under deploy/', 'deploy/relay.env'],
]) {
  test(`deploy refuses ${what} and contacts nothing`, () => {
    const s = deploySetup();
    s.put(rel, 'dirty\n');
    const result = s.run();
    assert.equal(result.status, 1);
    assert.match(result.stderr, /uncommitted changes/);
    assert.deepEqual(s.calls(), []);
  });
}

test('deploy ignores a dirty file outside relay/, web/ and deploy/', () => {
  const s = deploySetup();
  s.put('README.md', 'edited\n');
  const result = s.run([], { RELAY2_ENABLED: 'false' });
  assert.equal(result.status, 0, result.stdout + result.stderr);
});

test('deploy: lock, room check, sources, build, config, detached rollout, smoke checks, cleanup, in that order, all inside phu/shellx', () => {
  const s = deploySetup();
  const result = s.run([], { RELAY2_ENABLED: 'false' });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const calls = s.calls();
  const base = esc(SSH_DEFAULT);
  const order = [
    new RegExp(`^ssh .*ConnectTimeout=15.* higio@42\\.115\\.41\\.70 true$`),
    new RegExp(`^${base} test -f phu/shellx/\\.env && test -d phu/shellx/data$`),
    new RegExp(`^${base} bash -s -- ${s.sha} phu/shellx \\S+ \\[lock\\]$`),
    new RegExp(`^${base} bash -s \\[resources\\]$`),
    new RegExp(`^${base} mkdir -p phu/shellx/\\.build-src/${s.sha}$`),
    /^rsync -rlpt --from0 --files-from=\S+ -e ssh -o ControlPath=~\/\.ssh\/cm-shellx-vps .* \.\/ higio@42\.115\.41\.70:phu\/shellx\/\.build-src\/[0-9a-f]{40}\/$/,
    new RegExp(`^${base} bash -s -- ${s.sha} phu/shellx \\[build\\]$`),
    /mkdir -p phu\/shellx\/\.incoming\/nginx-proxy phu\/shellx\/\.incoming\/backup$/,
    /^rsync -rt -e .* deploy\/docker-compose\.yml deploy\/relay\.env higio@42\.115\.41\.70:phu\/shellx\/\.incoming\/$/,
    /^rsync -rt --delete -e .* deploy\/nginx-proxy\/ higio@42\.115\.41\.70:phu\/shellx\/\.incoming\/nginx-proxy\/$/,
    /^rsync -rt --delete -e .* deploy\/backup\/ higio@42\.115\.41\.70:phu\/shellx\/\.incoming\/backup\/$/,
    /find phu\/shellx\/\.incoming -type d -exec chmod 755/,
    new RegExp(`^rsync -t -e .* deploy/rollout\\.sh higio@42\\.115\\.41\\.70:phu/shellx/\\.rollout/${s.sha}\\.sh$`),
    new RegExp(`^${base} bash -s -- ${s.sha} phu/shellx \\[launch\\]$`),
    new RegExp(`^${base} bash -s -- ${s.sha} phu/shellx 0 \\[poll\\]$`),
    /^curl .*https:\/\/relay\.shellx\.pro\/v1\/version$/,
    /^curl .*https:\/\/shellx\.pro\/$/,
    /^curl .*https:\/\/admin\.shellx\.pro\/api\/session$/,
    /^curl .*-X POST https:\/\/relay\.shellx\.pro\/v2\/relay\/tickets$/,
    new RegExp(`rm -rf -- phu/shellx/\\.build-src/${s.sha} && rm -f -- phu/shellx/\\.rollout/${s.sha}\\.sh`),
  ];
  let at = -1;
  for (const re of order) {
    const next = calls.findIndex((line, i) => i > at && re.test(line));
    assert.ok(next > at, `missing or out of order: ${re}\n${calls.join('\n')}`);
    at = next;
  }
  // RELAY2_ENABLED=false: no /v2/relay GET, and relay2 is not even asked about.
  assert.equal(calls.some((line) => /v2\/relay$/.test(line)), false);
  assert.equal(calls.some((line) => line.includes('[relay2]')), false);

  // The rollout really ran, detached, in the sandbox: relay and web were not pulled, backup was.
  assert.match(result.stdout, /relay and web are healthy on [0-9a-f]{40}/);
  assert.match(result.stdout, /the rollout finished: exit 0/);
  const docker = s.dockerCalls();
  assert.ok(docker.includes(`docker image inspect ghcr.io/lephus/shellx-relay:${s.sha} [IMAGE_TAG=]`));
  assert.ok(docker.includes(`docker image inspect ghcr.io/lephus/shellx-web:${s.sha} [IMAGE_TAG=]`));
  assert.ok(docker.some((l) => l.startsWith('docker compose pull backup ')));
  assert.equal(docker.some((l) => /compose pull( relay| \[)/.test(l)), false);
  assert.match(s.envFile(), new RegExp(`^IMAGE_TAG=${s.sha}$`, 'm'));
  assert.equal(readFileSync(s.sandbox('docker-compose.yml'), 'utf8'), readFileSync(join(s.work, 'deploy', 'docker-compose.yml'), 'utf8'));

  // Everything is cleaned up: both locks, the build sources, the rollout files.
  assert.equal(existsSync(s.sandbox('.deploy.lock')), false);
  assert.equal(existsSync(s.macLock), false);
  assert.equal(existsSync(s.sandbox(`.build-src/${s.sha}`)), false);
  assert.deepEqual(readdirSync(s.sandbox('.rollout')), []);

  // Every ssh and rsync carries the fixed options.
  for (const line of calls.filter((l) => /^(ssh|rsync) /.test(l))) assert.match(line, new RegExp(esc(FIXED)));
  // Every remote path is inside the ShellX folder; the only remote deletion is ours.
  for (const line of calls.filter((l) => /rm /.test(l))) assert.match(line, new RegExp(`rm -rf -- phu/shellx/\\.build-src/${s.sha} &&`));
  for (const line of calls.filter((l) => l.startsWith('rsync'))) assert.match(line, /higio@42\.115\.41\.70:phu\/shellx\//);

  // Only tracked sources of relay/, web/, deploy/web/ and the two preflight files are sent.
  const sent = readFileSync(join(s.root, 'files-from.txt'), 'utf8').split('\n').filter(Boolean).sort();
  assert.deepEqual(sent, [
    'deploy/docker-compose.yml', 'deploy/relay.env', 'deploy/web/nginx.conf', 'relay/Dockerfile', 'relay/package.json',
    'relay/src/server.ts', 'web/Dockerfile', 'web/package.json', 'web/src/pages/index.astro',
  ]);

  // The build script: both tags, each build under `timeout 30m`, the web image from the repository root.
  const stdins = readdirSync(join(s.root, 'stdin')).map((f) => readFileSync(join(s.root, 'stdin', f), 'utf8'));
  const build = stdins.find((t) => t.includes('docker build'));
  assert.match(build, /timeout 30m docker build -t "ghcr\.io\/lephus\/shellx-relay:\$sha" relay/);
  assert.match(build, /timeout 30m docker build -f web\/Dockerfile -t "ghcr\.io\/lephus\/shellx-web:\$sha" \./);
  assert.match(build, /docker compose -f deploy\/docker-compose\.yml config -q/);
  // Nothing secret or log-like is printed by the script itself.
  assert.doesNotMatch(result.stdout + result.stderr, /SECRET|compose logs/);
});

test('deploy keeps the Mac awake with caffeinate -i while it runs', () => {
  const s = deploySetup();
  const result = s.run([], { RELAY2_ENABLED: 'false' });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.ok(waitFor(() => existsSync(join(s.root, 'calls.log.caffeinate'))));
  assert.match(readFileSync(join(s.root, 'calls.log.caffeinate'), 'utf8'), /^caffeinate -i -w \d+$/m);
});

// --- I1: the rollout is detached ----------------------------------------------------------------------

test('deploy: the rollout is a detached copy of rollout.sh, started with SHELLX_LOCAL_IMAGES=1, that leaves an exit marker', () => {
  const s = deploySetup();
  const result = s.run([], { RELAY2_ENABLED: 'false', SHELLX_ROLLOUT_POLL: '0.2' });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const stdins = readdirSync(join(s.root, 'stdin')).map((f) => readFileSync(join(s.root, 'stdin', f), 'utf8'));
  const launch = stdins.find((t) => t.includes('setsid'));
  assert.match(launch, /setsid nohup bash "\$sha\.run\.sh" "\$sha" "\$app_dir" > "\$sha\.log" 2>&1 < \/dev\/null &/);
  assert.match(launch, /SHELLX_LOCAL_IMAGES=1 bash "\$dir\/\$sha\.sh" "\$sha" "\$app_dir"/);
  assert.match(launch, /mv "\$dir\/\$sha\.exit\.tmp" "\$dir\/\$sha\.exit"/);
  // rollout.sh is NOT streamed to `bash -s` any more (a dropped session would SIGPIPE it): it is copied.
  assert.ok(stdins.every((t) => !t.includes('heal_missing_live_items')), 'no ssh call streams rollout.sh');
  assert.ok(s.calls().some((l) => l.includes(`deploy/rollout.sh higio@42.115.41.70:phu/shellx/.rollout/${s.sha}.sh`)));
});

test('deploy: the detached copy is rollout.sh byte for byte (kept after a failed rollout)', () => {
  const s = deploySetup();
  writeFileSync(s.sandbox('docker-unhealthy'), '');
  const result = s.run([], { RELAY2_ENABLED: 'false' });
  assert.equal(result.status, 1);
  assert.equal(readFileSync(s.sandbox(`.rollout/${s.sha}.sh`), 'utf8'), readFileSync(ROLLOUT_SCRIPT, 'utf8'));
});

test('deploy: a rollout poll that fails once or twice is retried; three in a row is a lost connection', () => {
  const retried = deploySetup();
  const ok = retried.run([], { RELAY2_ENABLED: 'false', FAKE_POLL_FAIL_FIRST: '2' });
  assert.equal(ok.status, 0, ok.stdout + ok.stderr);
  assert.match(ok.stdout, /the rollout finished: exit 0/);

  const lost = deploySetup();
  const result = lost.run([], { RELAY2_ENABLED: 'false', FAKE_POLL_FAIL_FIRST: '3' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /lost the ssh connection/);
  assert.ok(waitFor(() => existsSync(lost.sandbox(`.rollout/${lost.sha}.exit`))), 'the detached rollout never finished');
});

test('deploy: when ssh drops during the rollout it carries on by itself, and the script says how to look and that re-running heals', () => {
  const s = deploySetup();
  const result = s.run([], { RELAY2_ENABLED: 'false', FAKE_POLL_DROP: '0' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /lost the ssh connection/);
  assert.match(result.stderr, /docker compose ps/);
  assert.match(result.stderr, new RegExp(`\\.rollout/${s.sha}\\.log`));
  assert.match(result.stderr, /Running deploy\/vps-deploy\.sh again heals/);
  assert.match(result.stderr, /rm -rf phu\/shellx\/\.deploy\.lock/);
  // No smoke checks, build sources kept.
  assert.equal(s.calls().some((l) => l.startsWith('curl')), false);
  assert.equal(s.calls().some((l) => l.includes('rm -rf')), false);
  // The rollout was never tied to the session: it finishes, deploys, and gives the lock back by itself.
  assert.ok(waitFor(() => existsSync(s.sandbox(`.rollout/${s.sha}.exit`))), 'the detached rollout never finished');
  assert.equal(readFileSync(s.sandbox(`.rollout/${s.sha}.exit`), 'utf8'), '0\n');
  assert.match(s.envFile(), new RegExp(`^IMAGE_TAG=${s.sha}$`, 'm'));
  assert.equal(existsSync(s.sandbox('.deploy.lock')), false);
  assert.match(readFileSync(s.sandbox(`.rollout/${s.sha}.log`), 'utf8'), /relay and web are healthy on/);
  // The Mac's own lock is gone: a second deploy can start.
  assert.equal(existsSync(s.macLock), false);
});

test('deploy: a rollout that fails is reported with rollout.sh own lines, rolled back, lock released, no smoke checks', () => {
  const s = deploySetup();
  writeFileSync(s.sandbox('docker-unhealthy'), '');
  const result = s.run([], { RELAY2_ENABLED: 'false' });
  assert.equal(result.status, 1);
  assert.match(result.stdout + result.stderr, new RegExp(`not healthy within 3s on ${s.sha}; rolling back to old`));
  assert.match(result.stderr, /the rollout failed \(exit 1\)/);
  assert.equal(readFileSync(s.sandbox(`.rollout/${s.sha}.exit`), 'utf8'), '1\n');
  assert.match(s.envFile(), /^IMAGE_TAG=old$/m);
  assert.equal(existsSync(s.sandbox('.deploy.lock')), false);
  assert.equal(existsSync(s.macLock), false);
  assert.equal(s.calls().some((l) => l.startsWith('curl')), false);
  // Build sources and the rollout log stay for a look.
  assert.ok(existsSync(s.sandbox(`.build-src/${s.sha}`)));
  assert.ok(existsSync(s.sandbox(`.rollout/${s.sha}.log`)));
});

test('deploy: gives up waiting after SHELLX_ROLLOUT_TIMEOUT but leaves the rollout running, and says so', () => {
  const s = deploySetup();
  writeFileSync(s.sandbox('docker-slow'), '');
  const result = s.run([], { RELAY2_ENABLED: 'false', SHELLX_ROLLOUT_TIMEOUT: '1' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /still running after 1s/);
  assert.match(result.stderr, /docker compose ps/);
  assert.match(result.stderr, /heals/);
  assert.equal(s.calls().some((l) => l.startsWith('curl')), false);
  // It finishes on its own, later, and the lock goes with it.
  assert.ok(waitFor(() => existsSync(s.sandbox(`.rollout/${s.sha}.exit`))), 'the detached rollout never finished');
  assert.equal(readFileSync(s.sandbox(`.rollout/${s.sha}.exit`), 'utf8'), '0\n');
  assert.equal(existsSync(s.sandbox('.deploy.lock')), false);
});

// --- I2: only what is on origin/main ------------------------------------------------------------------

test('deploy refuses a HEAD that is not on origin/main, and says how to override', () => {
  const s = deploySetup();
  s.put('README.md', 'a commit nobody pushed\n');
  s.git('commit', '-q', '-am', 'local only');
  const result = s.run([], { RELAY2_ENABLED: 'false' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /not an ancestor of origin\/main/);
  assert.match(result.stderr, /SHELLX_ALLOW_NON_MAIN=1/);
  assert.deepEqual(s.calls(), []);
});

test('deploy: SHELLX_ALLOW_NON_MAIN=1 deploys a HEAD that is not on origin/main, with a loud warning', () => {
  const s = deploySetup();
  s.put('README.md', 'a commit nobody pushed\n');
  s.git('commit', '-q', '-am', 'local only');
  const result = s.run([], { RELAY2_ENABLED: 'false', SHELLX_ALLOW_NON_MAIN: '1' });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stderr, /WARNING/);
  assert.match(result.stderr, /NOT an ancestor of origin\/main/);
  assert.match(result.stderr, /Production will run code that is not on main/);
});

test('deploy fetches origin/main first: a stale remote-tracking ref does not make a pushed HEAD look unmerged', () => {
  const s = deploySetup();
  const first = s.git('rev-parse', 'HEAD');
  s.put('README.md', 'second\n');
  s.git('commit', '-q', '-am', 'second');
  s.git('push', '-q', 'origin', 'main');
  s.git('update-ref', 'refs/remotes/origin/main', first); // what a Mac that has not fetched for a while sees
  const result = s.run([], { RELAY2_ENABLED: 'false' });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.equal(s.git('rev-parse', 'refs/remotes/origin/main'), s.git('rev-parse', 'HEAD'));
});

test('deploy: a failed fetch cannot prove HEAD is on main, so it refuses unless overridden', () => {
  const s = deploySetup();
  s.git('remote', 'set-url', 'origin', join(s.root, 'does-not-exist.git'));
  const refused = s.run([], { RELAY2_ENABLED: 'false' });
  assert.equal(refused.status, 1);
  assert.match(refused.stderr, /could not fetch origin\/main/);
  assert.deepEqual(s.calls(), []);
  const allowed = s.run([], { RELAY2_ENABLED: 'false', SHELLX_ALLOW_NON_MAIN: '1' });
  assert.equal(allowed.status, 0, allowed.stdout + allowed.stderr);
  assert.match(allowed.stderr, /could not fetch origin\/main/);
});

test('deploy --dry-run only warns about a HEAD that is not on origin/main', () => {
  const s = deploySetup();
  s.put('README.md', 'a commit nobody pushed\n');
  s.git('commit', '-q', '-am', 'local only');
  const result = s.run(['--dry-run']);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stderr, /not an ancestor of origin\/main; a real run would refuse/);
});

// --- I3: room on the VPS ------------------------------------------------------------------------------

for (const [what, env, message] of [
  ['less than 4 GB of disk', { FAKE_DISK_KB: String(3 * 1024 * 1024) }, /only 3\.0 GB free under Docker's root dir \(\/var\/lib\/docker\).*at least 4 GB/],
  ['less than 1.5 GB of available memory', { FAKE_MEM_KB: String(1024 * 1024) }, /only 1\.0 GB of memory is available.*at least 1\.5 GB/],
  ['an unreadable disk size', { FAKE_DISK_KB: '0' }, /could not read the free disk under Docker's root dir/],
  ['an unreadable memory size', { FAKE_MEM_KB: '0' }, /could not read MemAvailable/],
]) {
  test(`deploy refuses ${what} before copying anything, and gives the lock back`, () => {
    const s = deploySetup();
    const result = s.run([], { RELAY2_ENABLED: 'false', ...env });
    assert.equal(result.status, 1);
    assert.match(result.stderr, message);
    assert.equal(s.calls().some((l) => l.startsWith('rsync')), false);
    assert.equal(existsSync(s.sandbox('.deploy.lock')), false);
    assert.equal(existsSync(s.macLock), false);
  });
}

test('deploy accepts exactly 4 GB of disk and 1.5 GB of memory', () => {
  const s = deploySetup();
  const result = s.run([], { RELAY2_ENABLED: 'false', FAKE_DISK_KB: '4194304', FAKE_MEM_KB: '1572864' });
  assert.equal(result.status, 0, result.stdout + result.stderr);
});

// --- I5: locks ----------------------------------------------------------------------------------------

test('deploy refuses while another deploy holds the lock on the VPS, says who, how to clear it, and leaves it alone', () => {
  const s = deploySetup();
  mkdirSync(s.sandbox('.deploy.lock'));
  writeFileSync(s.sandbox('.deploy.lock/owner'), 'abcdef0123 2026-01-01T00:00:00Z someone@othermac\n');
  const result = s.run([], { RELAY2_ENABLED: 'false' });
  assert.equal(result.status, 1);
  assert.match(result.stdout, /held by: abcdef0123 2026-01-01T00:00:00Z someone@othermac/);
  assert.match(result.stderr, /another deploy holds higio@42\.115\.41\.70:phu\/shellx\/\.deploy\.lock/);
  assert.match(result.stderr, /ssh -o ControlPath=~\/\.ssh\/cm-shellx-vps higio@42\.115\.41\.70 rm -rf phu\/shellx\/\.deploy\.lock/);
  assert.equal(s.calls().some((l) => l.startsWith('rsync')), false);
  assert.ok(existsSync(s.sandbox('.deploy.lock/owner')), 'a lock that is not ours must not be removed');
  assert.equal(existsSync(s.macLock), false);
});

test('deploy refuses while another deploy runs on this Mac, but replaces the lock of a dead one', () => {
  const s = deploySetup();
  mkdirSync(s.macLock);
  writeFileSync(join(s.macLock, 'pid'), `${process.pid}\n`); // this test process is alive
  const refused = s.run([], { RELAY2_ENABLED: 'false' });
  assert.equal(refused.status, 1);
  assert.match(refused.stderr, new RegExp(`another deploy to higio@42\\.115\\.41\\.70:phu/shellx is running on this Mac \\(pid ${process.pid}\\)`));
  assert.match(refused.stderr, /rm -rf /);
  assert.deepEqual(s.calls(), []);
  assert.ok(existsSync(s.macLock), 'the running deploy keeps its lock');

  const gone =spawnSync('bash', ['-c', 'echo $$'], { encoding: 'utf8' }).stdout.trim(); // a pid that has exited
  writeFileSync(join(s.macLock, 'pid'), `${gone}\n`);
  const result = s.run([], { RELAY2_ENABLED: 'false' });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stderr, /removing the lock of a deploy that is not running any more/);
  assert.equal(existsSync(s.macLock), false);
});

test('deploy: a failing build gives both locks back and leaves the build sources', () => {
  const s = deploySetup();
  const result = s.run([], { RELAY2_ENABLED: 'false', FAKE_BUILD_FAIL: '1' });
  assert.notEqual(result.status, 0);
  const calls = s.calls();
  assert.ok(calls.some((l) => l.endsWith('[unlock]')), 'the Mac gives the VPS lock back before it hands over');
  assert.equal(existsSync(s.sandbox('.deploy.lock')), false);
  assert.equal(existsSync(s.macLock), false);
  assert.equal(calls.some((l) => l.includes('.incoming')), false);
  assert.equal(calls.some((l) => l.includes('[launch]')), false);
  assert.equal(calls.some((l) => l.startsWith('curl')), false);
  assert.ok(existsSync(s.sandbox(`.build-src/${s.sha}`)));
});

test('deploy: after the hand-off the Mac does not touch the VPS lock (the detached wrapper owns it)', () => {
  const s = deploySetup();
  writeFileSync(s.sandbox('docker-unhealthy'), '');
  const result = s.run([], { RELAY2_ENABLED: 'false' });
  assert.equal(result.status, 1);
  assert.equal(s.calls().some((l) => l.endsWith('[unlock]')), false);
  assert.equal(existsSync(s.sandbox('.deploy.lock')), false);
});

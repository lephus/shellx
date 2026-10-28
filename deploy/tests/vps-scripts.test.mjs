// Tests for deploy/vps-deploy.sh and scripts/shellx/release/publish-to-vps.sh (the no-GitHub-Actions
// path) with a fake ssh, rsync and curl on PATH: nothing leaves the machine.
//   node --test deploy/tests/*.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, '..', '..');
const DEPLOY_SCRIPT = join(repo, 'deploy', 'vps-deploy.sh');
const ROLLOUT_SCRIPT = join(repo, 'deploy', 'rollout.sh');
const PUBLISH_SCRIPT = join(repo, 'scripts', 'shellx', 'release', 'publish-to-vps.sh');

// --- fakes --------------------------------------------------------------------------------------------
// Every call is appended to $CALLS. Behaviour switches (environment of the script under test):
//   FAKE_UNREACHABLE      the BatchMode connection check fails (255)
//   FAKE_BUILD_FAIL       the remote build script (bash -s -- <40 hex sha> <app dir>) fails
//   FAKE_ROLLOUT_FAIL     rollout.sh (SHELLX_LOCAL_IMAGES=1 bash -s) fails
//   FAKE_REMOTE_OCCUPIED  publish: the remote version-folder check exits 3
//   FAKE_RELAY2           the `grep -Eq COMPOSE_PROFILES` question is answered "yes"
//   FAKE_V2_CODE          the HTTP code GET /v2/relay answers (default 400)
//   FAKE_PRECHECK_CODE    publish: the HTTP code of the installer URLs before the upload (default 404)
//   FAKE_SIZE             publish: Content-Length every installer URL answers (default: the local file's size)
const FAKE_SSH = `#!/usr/bin/env bash
echo "ssh $*" >> "$CALLS"
n="$(wc -l < "$CALLS" | tr -d ' ')"
args="$*"
if [[ "$args" == *BatchMode=yes* ]]; then
  if [[ -n "\${FAKE_UNREACHABLE:-}" ]]; then exit 255; fi
  exit 0
fi
if [[ "$args" == *"bash -s"* ]]; then
  cat > "$STDIN_DIR/$n.stdin"
  if [[ "$args" == *SHELLX_LOCAL_IMAGES=1* ]]; then
    if [[ -n "\${FAKE_ROLLOUT_FAIL:-}" ]]; then exit 1; fi
    exit 0
  fi
  if [[ "$args" =~ bash\\ -s\\ --\\ [0-9a-f]{40}\\  ]]; then
    if [[ -n "\${FAKE_BUILD_FAIL:-}" ]]; then exit 1; fi
    exit 0
  fi
  if [[ -n "\${FAKE_REMOTE_OCCUPIED:-}" ]]; then exit 3; fi
  exit 0
fi
if [[ "$args" == *"grep -Eq"* ]]; then
  if [[ -n "\${FAKE_RELAY2:-}" ]]; then exit 0; fi
  exit 1
fi
exit 0
`;

const FAKE_RSYNC = `#!/usr/bin/env bash
echo "rsync $*" >> "$CALLS"
for a in "$@"; do
  case "$a" in
    --files-from=*) tr '\\0' '\\n' < "\${a#--files-from=}" >> "$FILES_FROM" ;;
  esac
done
exit 0
`;

const FAKE_CURL = `#!/usr/bin/env bash
echo "curl $*" >> "$CALLS"
args="$*"
last="\${@: -1}"
if [[ "$args" == *v2/relay/tickets* ]]; then
  printf '{"error":"unauthorized","code":"unauthorized"}\\n401'
  exit 0
fi
if [[ "$args" == *"%{http_code}"* ]]; then
  if [[ "$last" == *precheck=* ]]; then printf '%s' "\${FAKE_PRECHECK_CODE:-404}"; else printf '%s' "\${FAKE_V2_CODE:-400}"; fi
  exit 0
fi
if [[ "$args" == *"-sfIL "* ]]; then
  name="\${last##*/}"; name="\${name%%\\?*}"
  size="\${FAKE_SIZE:-$(wc -c < "$DIST/$name" | tr -d ' ')}"
  printf 'HTTP/2 200\\r\\ncontent-length: %s\\r\\n\\r\\n' "$size"
  exit 0
fi
if [[ "$last" == */appcast.xml\\?verify=* ]]; then
  cat "$DIST/appcast.xml"
  exit 0
fi
exit 0
`;

function makeBin(root) {
  const bin = join(root, 'bin');
  mkdirSync(bin, { recursive: true });
  for (const [name, body] of [['ssh', FAKE_SSH], ['rsync', FAKE_RSYNC], ['curl', FAKE_CURL]]) {
    writeFileSync(join(bin, name), body);
    chmodSync(join(bin, name), 0o755);
  }
  return bin;
}

function baseEnv(root, extra = {}) {
  const calls = join(root, 'calls.log');
  const stdinDir = join(root, 'stdin');
  const filesFrom = join(root, 'files-from.txt');
  mkdirSync(stdinDir, { recursive: true });
  for (const f of [calls, filesFrom]) if (!existsSync(f)) writeFileSync(f, '');
  return {
    PATH: `${join(root, 'bin')}:${process.env.PATH}`,
    HOME: join(root, 'home'),
    CALLS: calls,
    STDIN_DIR: stdinDir,
    FILES_FROM: filesFrom,
    SHELLX_SMOKE_INTERVAL: '0',
    SHELLX_SMOKE_ATTEMPTS: '2',
    ...extra,
  };
}

const readCalls = (root) => readFileSync(join(root, 'calls.log'), 'utf8').split('\n').filter(Boolean);
const idx = (calls, re) => calls.findIndex((line) => re.test(line));

// --- vps-deploy.sh ------------------------------------------------------------------------------------

function git(cwd, ...args) {
  const r = spawnSync('git', args, {
    cwd,
    encoding: 'utf8',
    env: {
      PATH: process.env.PATH,
      HOME: cwd,
      GIT_CONFIG_NOSYSTEM: '1',
      GIT_CONFIG_GLOBAL: '/dev/null',
      GIT_AUTHOR_NAME: 't',
      GIT_AUTHOR_EMAIL: 't@example.invalid',
      GIT_COMMITTER_NAME: 't',
      GIT_COMMITTER_EMAIL: 't@example.invalid',
    },
  });
  assert.equal(r.status, 0, `git ${args.join(' ')}: ${r.stderr}`);
  return r.stdout.trim();
}

function put(root, rel, content = `${rel}\n`) {
  const path = join(root, rel);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, content);
}

// A throwaway git repository shaped like this one (the script finds its repository from its own location).
function deploySetup() {
  const root = mkdtempSync(join(tmpdir(), 'shellx-vpsdeploy-'));
  const work = join(root, 'repo');
  mkdirSync(join(root, 'home'), { recursive: true });
  mkdirSync(work, { recursive: true });
  git(work, 'init', '-q');
  put(work, '.gitignore', 'node_modules\ndist\n.env\n');
  put(work, 'README.md');
  for (const f of [
    'relay/Dockerfile', 'relay/package.json', 'relay/src/server.ts', 'web/Dockerfile', 'web/package.json',
    'web/src/pages/index.astro', 'deploy/web/nginx.conf', 'deploy/docker-compose.yml', 'deploy/relay.env',
    'deploy/nginx-proxy/shellx.pro', 'deploy/backup/entrypoint.sh', 'deploy/README.md',
  ]) put(work, f);
  mkdirSync(join(work, 'deploy'), { recursive: true });
  copyFileSync(DEPLOY_SCRIPT, join(work, 'deploy', 'vps-deploy.sh'));
  copyFileSync(ROLLOUT_SCRIPT, join(work, 'deploy', 'rollout.sh'));
  chmodSync(join(work, 'deploy', 'vps-deploy.sh'), 0o755);
  git(work, 'add', '-A');
  git(work, 'commit', '-q', '-m', 'init');
  // Ignored files must never be sent.
  put(work, 'relay/node_modules/leftpad/index.js');
  put(work, 'web/dist/index.html');
  put(work, 'relay/.env', 'SECRET=1\n');
  makeBin(root);
  const sha = git(work, 'rev-parse', 'HEAD');
  const run = (args = [], extraEnv = {}) =>
    spawnSync('bash', [join(work, 'deploy', 'vps-deploy.sh'), ...args], {
      cwd: work, encoding: 'utf8', env: baseEnv(root, extraEnv),
    });
  return { root, work, sha, run, calls: () => readCalls(root), put: (rel, c) => put(work, rel, c) };
}

test('deploy --dry-run prints every step with the defaults and runs no ssh, rsync or curl', () => {
  const s = deploySetup();
  const result = s.run(['--dry-run']);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(s.calls(), []);
  const out = result.stdout;
  // The defaults: the user's target and ControlMaster socket, the app folder.
  assert.match(out, /ssh -o ControlPath=~\/\.ssh\/cm-shellx-vps higio@42\.115\.41\.70 'mkdir -p phu\/shellx\/\.build-src\/[0-9a-f]{40}'/);
  assert.match(out, new RegExp(`ghcr\\.io/lephus/shellx-relay:\\$sha" relay`));
  assert.match(out, /docker build -f web\/Dockerfile -t "ghcr\.io\/lephus\/shellx-web:\$sha" \./);
  assert.match(out, /rsync -rt --delete -e 'ssh -o ControlPath=~\/\.ssh\/cm-shellx-vps' deploy\/nginx-proxy\/ higio@42\.115\.41\.70:phu\/shellx\/\.incoming\/nginx-proxy\//);
  assert.match(out, /'env SHELLX_LOCAL_IMAGES=1 bash -s -- [0-9a-f]{40} phu\/shellx' < deploy\/rollout\.sh/);
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
  assert.equal(result.status, 0, result.stderr);
});

test('deploy: sources, build, config, rollout, smoke checks, cleanup, in that order, all inside phu/shellx', () => {
  const s = deploySetup();
  const result = s.run([], { RELAY2_ENABLED: 'false' });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const calls = s.calls();
  const base = 'ssh -o ControlPath=~/.ssh/cm-shellx-vps higio@42.115.41.70';
  const order = [
    new RegExp(`^ssh .*BatchMode=yes.* higio@42\\.115\\.41\\.70 true$`),
    new RegExp(`^${base.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')} test -f phu/shellx/\\.env && test -d phu/shellx/data$`),
    new RegExp(`^${base.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')} mkdir -p phu/shellx/\\.build-src/${s.sha}$`),
    /^rsync -rlpt --from0 --files-from=\S+ -e ssh -o ControlPath=~\/\.ssh\/cm-shellx-vps \.\/ higio@42\.115\.41\.70:phu\/shellx\/\.build-src\/[0-9a-f]{40}\/$/,
    new RegExp(`bash -s -- ${s.sha} phu/shellx$`),
    /mkdir -p phu\/shellx\/\.incoming\/nginx-proxy phu\/shellx\/\.incoming\/backup$/,
    /^rsync -rt -e ssh -o ControlPath=~\/\.ssh\/cm-shellx-vps deploy\/docker-compose\.yml deploy\/relay\.env higio@42\.115\.41\.70:phu\/shellx\/\.incoming\/$/,
    /^rsync -rt --delete -e .* deploy\/nginx-proxy\/ higio@42\.115\.41\.70:phu\/shellx\/\.incoming\/nginx-proxy\/$/,
    /^rsync -rt --delete -e .* deploy\/backup\/ higio@42\.115\.41\.70:phu\/shellx\/\.incoming\/backup\/$/,
    /find phu\/shellx\/\.incoming -type d -exec chmod 755/,
    new RegExp(`env SHELLX_LOCAL_IMAGES=1 bash -s -- ${s.sha} phu/shellx$`),
    /^curl .*https:\/\/relay\.shellx\.pro\/v1\/version$/,
    /^curl .*https:\/\/shellx\.pro\/$/,
    /^curl .*https:\/\/admin\.shellx\.pro\/api\/session$/,
    /^curl .*-X POST https:\/\/relay\.shellx\.pro\/v2\/relay\/tickets$/,
    new RegExp(`rm -rf -- phu/shellx/\\.build-src/${s.sha}$`),
  ];
  let at = -1;
  for (const re of order) {
    const next = calls.findIndex((line, i) => i > at && re.test(line));
    assert.ok(next > at, `missing or out of order: ${re}\n${calls.join('\n')}`);
    at = next;
  }
  // RELAY2_ENABLED=false: no /v2/relay GET, and relay2 is not even asked about.
  assert.equal(calls.some((line) => /v2\/relay$/.test(line)), false);
  assert.equal(calls.some((line) => line.includes('grep -Eq')), false);

  // Every remote path is inside the ShellX folder; the only remote deletion is the build sources.
  for (const line of calls.filter((l) => /rm /.test(l))) assert.match(line, new RegExp(`rm -rf -- phu/shellx/\\.build-src/${s.sha}$`));
  for (const line of calls.filter((l) => l.startsWith('rsync'))) assert.match(line, /higio@42\.115\.41\.70:phu\/shellx\//);

  // Only tracked sources of relay/, web/, deploy/web/ and the two preflight files are sent.
  const sent = readFileSync(join(s.root, 'files-from.txt'), 'utf8').split('\n').filter(Boolean).sort();
  assert.deepEqual(sent, [
    'deploy/docker-compose.yml', 'deploy/relay.env', 'deploy/web/nginx.conf', 'relay/Dockerfile', 'relay/package.json',
    'relay/src/server.ts', 'web/Dockerfile', 'web/package.json', 'web/src/pages/index.astro',
  ]);

  // The build script builds both images with CI's tags and the web image from the repository root.
  const stdins = readdirSync(join(s.root, 'stdin')).map((f) => readFileSync(join(s.root, 'stdin', f), 'utf8'));
  const build = stdins.find((t) => t.includes('docker build'));
  assert.match(build, /docker build -t "ghcr\.io\/lephus\/shellx-relay:\$sha" relay/);
  assert.match(build, /docker build -f web\/Dockerfile -t "ghcr\.io\/lephus\/shellx-web:\$sha" \./);
  assert.match(build, /docker compose -f deploy\/docker-compose\.yml config -q/);
  // rollout.sh itself is what is streamed.
  assert.ok(stdins.includes(readFileSync(ROLLOUT_SCRIPT, 'utf8')));
  // Nothing secret or log-like is printed by the script itself.
  assert.doesNotMatch(result.stdout + result.stderr, /SECRET|compose logs/);
});

test('deploy asks the VPS about relay2 and checks GET /v2/relay when it is on', () => {
  const s = deploySetup();
  const result = s.run([], { FAKE_RELAY2: '1' });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.ok(s.calls().some((line) => line.includes("grep -Eq '^COMPOSE_PROFILES=.*relay2' phu/shellx/.env")));
  assert.ok(s.calls().some((line) => /^curl .*%\{http_code\}.* https:\/\/relay\.shellx\.pro\/v2\/relay$/.test(line)));
  assert.match(result.stdout, /https:\/\/relay\.shellx\.pro\/v2\/relay answers 400/);
});

test('deploy: RELAY2_ENABLED=true forces the /v2/relay check, and a wrong answer fails the run', () => {
  const s = deploySetup();
  const result = s.run([], { RELAY2_ENABLED: 'true', FAKE_V2_CODE: '404' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /v2\/relay did not answer 400 426/);
  // Smoke failure keeps the build sources for a look.
  assert.equal(s.calls().some((line) => line.includes('rm -rf')), false);
});

test('deploy: a failing build stops before the config is staged or anything is rolled out', () => {
  const s = deploySetup();
  const result = s.run([], { FAKE_BUILD_FAIL: '1', RELAY2_ENABLED: 'false' });
  assert.notEqual(result.status, 0);
  const calls = s.calls();
  assert.equal(calls.some((line) => line.includes('.incoming')), false);
  assert.equal(calls.some((line) => line.includes('SHELLX_LOCAL_IMAGES')), false);
  assert.equal(calls.some((line) => line.startsWith('curl')), false);
});

test('deploy: a failing rollout skips the smoke checks and keeps the build sources', () => {
  const s = deploySetup();
  const result = s.run([], { FAKE_ROLLOUT_FAIL: '1', RELAY2_ENABLED: 'false' });
  assert.notEqual(result.status, 0);
  const calls = s.calls();
  assert.ok(calls.some((line) => line.includes('SHELLX_LOCAL_IMAGES=1')));
  assert.equal(calls.some((line) => line.startsWith('curl')), false);
  assert.equal(calls.some((line) => line.includes('rm -rf')), false);
});

test('deploy: no password-less connection stops early and says how to open the shared connection', () => {
  const s = deploySetup();
  const result = s.run([], { FAKE_UNREACHABLE: '1' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /ssh -fN -M -S ~\/\.ssh\/cm-shellx-vps -o ControlPersist=10h higio@42\.115\.41\.70/);
  assert.equal(s.calls().some((line) => line.startsWith('rsync')), false);
});

test('deploy: SHELLX_VPS and SHELLX_VPS_SSH_OPTS are honoured, empty options mean plain ssh', () => {
  const s = deploySetup();
  const custom = s.run(['--dry-run'], { SHELLX_VPS: 'deploy@host.example', SHELLX_VPS_SSH_OPTS: '-p 2222 -i /keys/id' });
  assert.equal(custom.status, 0, custom.stderr);
  assert.match(custom.stdout, /\+ ssh -p 2222 -i \/keys\/id deploy@host\.example 'mkdir -p/);
  assert.match(custom.stdout, /-e 'ssh -p 2222 -i \/keys\/id'/);
  assert.doesNotMatch(custom.stdout, /higio@|ControlPath/);

  const plain = s.run(['--dry-run'], { SHELLX_VPS_SSH_OPTS: '' });
  assert.equal(plain.status, 0, plain.stderr);
  assert.match(plain.stdout, /\+ ssh higio@42\.115\.41\.70 'mkdir -p/);
  assert.doesNotMatch(plain.stdout, /ControlPath/);
});

for (const [name, env] of [
  ['an absolute APP_DIR', { APP_DIR: '/srv/other' }],
  ['a parent-directory APP_DIR', { APP_DIR: 'phu/../other' }],
  ['an APP_DIR with a space', { APP_DIR: 'phu/my shellx' }],
  ['an APP_DIR starting with a dash', { APP_DIR: '-rf' }],
  ['an option-like SHELLX_VPS', { SHELLX_VPS: '-oProxyCommand=evil' }],
  ['a SHELLX_VPS with a shell metacharacter', { SHELLX_VPS: 'a@b;rm' }],
  ['a bad RELAY2_ENABLED', { RELAY2_ENABLED: 'maybe' }],
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

// --- publish-to-vps.sh --------------------------------------------------------------------------------

const sha256 = (c) => createHash('sha256').update(c).digest('hex');
const VERSION = '1.5.1';

// A release folder like make-feeds.sh writes (with or without the Windows installer).
function writeDist(dir, { exe = true, version = VERSION } = {}) {
  mkdirSync(dir, { recursive: true });
  const base = `https://download.shellx.pro/desktop/${version}/`;
  const dmg = `dmg ${version}\n`;
  const exeBody = `exe ${version}\n`;
  const appcast = `<rss xmlns:sparkle="x"><item><sparkle:shortVersionString>${version}</sparkle:shortVersionString>`
    + `<enclosure url="${base}ShellX-${version}.dmg" sparkle:edSignature="sig" length="${dmg.length}"/></item></rss>\n`;
  const mac = `${JSON.stringify({ version, url: `${base}ShellX-${version}.dmg`, sha256: sha256(dmg) })}\n`;
  const files = [[`ShellX-${version}.dmg`, dmg], ['appcast.xml', appcast], ['latest-macos.json', mac]];
  if (exe) {
    const win = `${JSON.stringify({ version, url: `${base}ShellX-Setup-${version}.exe`, sha256: sha256(exeBody) })}\n`;
    files.push([`ShellX-Setup-${version}.exe`, exeBody], ['latest-windows.json', win]);
  }
  for (const [name, content] of files) writeFileSync(join(dir, name), content);
  writeFileSync(join(dir, 'SHA256SUMS'), files.map(([n, c]) => `${sha256(c)}  ${n}\n`).join(''));
}

function publishSetup({ exe = true } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'shellx-publish-'));
  mkdirSync(join(root, 'home'), { recursive: true });
  makeBin(root);
  const dist = join(root, 'dist');
  writeDist(dist, { exe });
  const run = (args = [VERSION, dist], extraEnv = {}) =>
    spawnSync('bash', [PUBLISH_SCRIPT, ...args], {
      encoding: 'utf8', env: baseEnv(root, { DIST: dist, ...extraEnv }),
    });
  return { root, dist, run, calls: () => readCalls(root) };
}

// The file names each rsync call sends: the local paths between `-e <ssh command>` and the destination.
const rsyncUploads = (calls) => calls
  .filter((l) => l.startsWith('rsync'))
  .map((l) => l.replace(/^rsync -t -e ssh -o ControlPath=~\/\.ssh\/cm-shellx-vps /, '').replace(/ higio@\S+$/, '')
    .split(' ').map((p) => p.split('/').pop()).join(' '));

test('publish: installers first, then the feeds with SHA256SUMS last, permissions set, nothing outside phu/shellx', () => {
  const s = publishSetup();
  const result = s.run();
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const calls = s.calls();
  const base = 'ssh -o ControlPath=~/.ssh/cm-shellx-vps higio@42.115.41.70';
  const order = [
    new RegExp(`^${base.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')} bash -s -- phu/shellx ${VERSION.replace(/\./g, '\\.')}$`),
    /^curl .*ShellX-1\.5\.1\.dmg\?precheck=/,
    /^curl .*ShellX-Setup-1\.5\.1\.exe\?precheck=/,
    /mkdir -p phu\/shellx\/downloads\/desktop\/1\.5\.1 && chmod 755 phu\/shellx\/downloads phu\/shellx\/downloads\/desktop phu\/shellx\/downloads\/desktop\/1\.5\.1$/,
    /^rsync -t -e .*ShellX-1\.5\.1\.dmg .*ShellX-Setup-1\.5\.1\.exe higio@42\.115\.41\.70:phu\/shellx\/downloads\/desktop\/1\.5\.1\/$/,
    /chmod 644 phu\/shellx\/downloads\/desktop\/1\.5\.1\/ShellX-1\.5\.1\.dmg phu\/shellx\/downloads\/desktop\/1\.5\.1\/ShellX-Setup-1\.5\.1\.exe$/,
    /^curl -sfIL .*ShellX-1\.5\.1\.dmg\?verify=/,
    /^curl -sfIL .*ShellX-Setup-1\.5\.1\.exe\?verify=/,
    /^rsync -t -e .*latest-windows\.json higio@42\.115\.41\.70:phu\/shellx\/downloads\/desktop\/$/,
    /^rsync -t -e .*appcast\.xml higio@42\.115\.41\.70:phu\/shellx\/downloads\/desktop\/$/,
    /^rsync -t -e .*latest-macos\.json higio@42\.115\.41\.70:phu\/shellx\/downloads\/desktop\/$/,
    /^rsync -t -e .*SHA256SUMS higio@42\.115\.41\.70:phu\/shellx\/downloads\/desktop\/$/,
    /chmod 644 phu\/shellx\/downloads\/desktop\/latest-windows\.json phu\/shellx\/downloads\/desktop\/appcast\.xml phu\/shellx\/downloads\/desktop\/latest-macos\.json phu\/shellx\/downloads\/desktop\/SHA256SUMS$/,
    /^curl -sf .*desktop\/appcast\.xml\?verify=/,
  ];
  let at = -1;
  for (const re of order) {
    const next = calls.findIndex((line, i) => i > at && re.test(line));
    assert.ok(next > at, `missing or out of order: ${re}\n${calls.join('\n')}`);
    at = next;
  }
  // The feeds go one rsync each, in this order (rsync itself would sort a multi-file call), SHA256SUMS last.
  assert.deepEqual(
    rsyncUploads(calls),
    ['ShellX-1.5.1.dmg ShellX-Setup-1.5.1.exe', 'latest-windows.json', 'appcast.xml', 'latest-macos.json', 'SHA256SUMS'],
  );
  for (const line of calls.filter((l) => l.startsWith('rsync'))) assert.match(line, /higio@42\.115\.41\.70:phu\/shellx\/downloads\/desktop\//);
  assert.match(result.stdout, /\| ShellX-Setup-1\.5\.1\.exe \| https:\/\/download\.shellx\.pro\/desktop\/1\.5\.1\/ShellX-Setup-1\.5\.1\.exe \| [0-9a-f]{64} \|/);
});

test('publish: a Mac-only release keeps the live latest-windows.json and uploads no exe', () => {
  const s = publishSetup({ exe: false });
  // A stale Windows line in SHA256SUMS and a leftover latest-windows.json must not matter.
  writeFileSync(join(s.dist, 'SHA256SUMS'), `${readFileSync(join(s.dist, 'SHA256SUMS'), 'utf8')}${'0'.repeat(64)}  ShellX-Setup-${VERSION}.exe\n`);
  writeFileSync(join(s.dist, 'latest-windows.json'), '{"version":"0.0.1"}\n');
  const result = s.run();
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const calls = s.calls();
  assert.match(result.stdout, /Mac-only release\. The live latest-windows\.json is kept/);
  assert.match(result.stdout, /kept the live .*latest-windows\.json/);
  assert.equal(calls.some((l) => /Setup|latest-windows/.test(l)), false, calls.join('\n'));
  assert.deepEqual(rsyncUploads(calls), ['ShellX-1.5.1.dmg', 'appcast.xml', 'latest-macos.json', 'SHA256SUMS']);
  assert.doesNotMatch(result.stdout, /\| ShellX-Setup/);
});

test('publish --dry-run runs the local checks, prints the commands and contacts nobody', () => {
  const s = publishSetup();
  const result = s.run(['--dry-run', VERSION, s.dist]);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(s.calls(), []);
  assert.match(result.stdout, /feeds ok/);
  assert.match(result.stdout, /\+ rsync -t -e 'ssh -o ControlPath=~\/\.ssh\/cm-shellx-vps' .*ShellX-1\.5\.1\.dmg .*ShellX-Setup-1\.5\.1\.exe higio@42\.115\.41\.70:phu\/shellx\/downloads\/desktop\/1\.5\.1\//);

  // The local checks run in a dry run too.
  writeFileSync(join(s.dist, `ShellX-${VERSION}.dmg`), 'tampered\n');
  const bad = s.run(['--dry-run', VERSION, s.dist]);
  assert.equal(bad.status, 1);
});

test('publish refuses a version folder that already has files, before uploading anything', () => {
  const s = publishSetup();
  const result = s.run(undefined, { FAKE_REMOTE_OCCUPIED: '1' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /already has files; bump the version instead of overwriting/);
  assert.equal(s.calls().some((l) => l.startsWith('rsync')), false);
});

test('publish refuses an installer URL the website already serves', () => {
  const s = publishSetup();
  const result = s.run(undefined, { FAKE_PRECHECK_CODE: '200' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /already answers HTTP 200; bump the version/);
  assert.equal(s.calls().some((l) => l.startsWith('rsync')), false);
});

test('publish stops when the website cannot be reached (000), as the workflow does', () => {
  const s = publishSetup();
  const result = s.run(undefined, { FAKE_PRECHECK_CODE: '000' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /cannot reach https:\/\/download\.shellx\.pro/);
  assert.equal(s.calls().some((l) => l.startsWith('rsync')), false);
});

test('publish: a size mismatch over HTTPS stops before any feed is uploaded', () => {
  const s = publishSetup();
  const result = s.run(undefined, { FAKE_SIZE: '1' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /has size '1', expected/);
  const uploaded = s.calls().filter((l) => l.startsWith('rsync'));
  assert.equal(uploaded.length, 1); // only the installers
  assert.doesNotMatch(uploaded[0], /appcast|latest-|SHA256SUMS/);
});

test('publish: a tampered installer fails the checksum check before any ssh', () => {
  const s = publishSetup();
  writeFileSync(join(s.dist, `ShellX-${VERSION}.dmg`), 'tampered\n');
  const result = s.run();
  assert.equal(result.status, 1);
  assert.match(result.stderr, /checksums in SHA256SUMS do not match/);
  assert.deepEqual(s.calls(), []);
});

test('publish: SHA256SUMS must list every file it uploads', () => {
  const s = publishSetup();
  const lines = readFileSync(join(s.dist, 'SHA256SUMS'), 'utf8').split('\n').filter((l) => !l.endsWith('  appcast.xml'));
  writeFileSync(join(s.dist, 'SHA256SUMS'), `${lines.join('\n')}\n`);
  const result = s.run();
  assert.equal(result.status, 1);
  assert.match(result.stderr, /SHA256SUMS does not list appcast\.xml/);
  assert.deepEqual(s.calls(), []);
});

test('publish: feeds that point somewhere else are refused', () => {
  const s = publishSetup();
  const path = join(s.dist, 'latest-macos.json');
  const wrong = readFileSync(path, 'utf8').replace('/desktop/1.5.1/', '/desktop/1.5.0/');
  writeFileSync(path, wrong);
  // Keep the checksum honest so the feed check is what fails.
  const sums = readFileSync(join(s.dist, 'SHA256SUMS'), 'utf8').replace(/^[0-9a-f]{64}(  latest-macos\.json)$/m, `${sha256(wrong)}$1`);
  writeFileSync(join(s.dist, 'SHA256SUMS'), sums);
  const result = s.run();
  assert.equal(result.status, 1);
  assert.deepEqual(s.calls(), []);
});

test('publish: a missing required file, a bad version and a missing folder are refused', () => {
  const s = publishSetup();
  rmSync(join(s.dist, 'appcast.xml'));
  assert.equal(s.run().status, 1);
  assert.equal(s.run(['1.5', s.dist]).status, 1);
  assert.equal(s.run(['v1.5.1', s.dist]).status, 1);
  assert.equal(s.run([VERSION, join(s.root, 'nope')]).status, 1);
  assert.equal(s.run([VERSION]).status, 2);
  assert.deepEqual(s.calls(), []);
});

test('publish: an exe without latest-windows.json is refused', () => {
  const s = publishSetup();
  rmSync(join(s.dist, 'latest-windows.json'));
  const result = s.run();
  assert.equal(result.status, 1);
  assert.match(result.stderr, /latest-windows\.json not found/);
  assert.deepEqual(s.calls(), []);
});

test('publish: APP_DIR and SHELLX_VPS are validated like deploy.yml validates VPS_APP_DIR', () => {
  const s = publishSetup();
  for (const env of [{ APP_DIR: '../x' }, { APP_DIR: '/abs' }, { APP_DIR: 'a b' }, { SHELLX_VPS: '-oFoo=bar' }]) {
    assert.equal(s.run(undefined, env).status, 1, JSON.stringify(env));
  }
  assert.deepEqual(s.calls(), []);
});

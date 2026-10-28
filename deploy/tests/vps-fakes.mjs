// Shared by vps-deploy.test.mjs, vps-deploy-options.test.mjs and publish-to-vps.test.mjs (not a test file
// itself: `node --test deploy/tests/*.test.mjs` skips it). Fakes for the no-GitHub-Actions path of
// deploy/vps-deploy.sh and scripts/shellx/release/publish-to-vps.sh: nothing leaves the machine, ssh,
// rsync, curl, docker, timeout and caffeinate are fakes on PATH.
// The fake ssh and rsync work against a sandbox "remote home" (root/remote): the scripts the deploy sends
// to the VPS (lock, launcher, poll, relay2 question, version-folder check) and rollout.sh itself really
// run there, with a fake docker, so the detach/poll/lock logic is exercised for real.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, '..', '..');
export const DEPLOY_SCRIPT = join(repo, 'deploy', 'vps-deploy.sh');
export const ROLLOUT_SCRIPT = join(repo, 'deploy', 'rollout.sh');
export const PUBLISH_SCRIPT = join(repo, 'scripts', 'shellx', 'release', 'publish-to-vps.sh');

export const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
export const FIXED = '-o BatchMode=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=4';
export const SSH_DEFAULT = `ssh -o ControlPath=~/.ssh/cm-shellx-vps ${FIXED} higio@42.115.41.70`;
export const R2 = '08de0bb35efbd46e3cade25446fdb6ffffac41bc';

// --- fakes --------------------------------------------------------------------------------------------
// Every call is appended to $CALLS (ssh calls get a trailing [kind] when they stream one of our scripts).
// Behaviour switches, set in the environment of the script under test:
//   FAKE_UNREACHABLE   the ConnectTimeout=15 connection check fails (255)
//   FAKE_BUILD_FAIL    the remote build script fails
//   FAKE_POLL_DROP=N   the rollout polls after the N-th are dropped (ssh status 255); 0 = all of them
//   FAKE_POLL_FAIL_FIRST=N   only the first N polls fail (255), later ones go through
//   FAKE_DISK_KB, FAKE_MEM_KB   what the resource script reports (default 20 GB, 4 GB)
//   FAKE_V2_CODE       the HTTP code GET /v2/relay answers (default 400)
//   FAKE_PRECHECK_CODE publish: the HTTP code of the installer URLs before the upload (default 404)
//   FAKE_SIZE          publish: Content-Length every installer URL answers (default: the local file's size)
// Files in the sandbox app dir steer the fake docker: docker-unhealthy, docker-slow.
const FAKE_SSH = `#!/usr/bin/env bash
mkdir -p "$STDIN_DIR"
tmp="$STDIN_DIR/incoming.$$"
cat > "$tmp"
kind=""
if grep -q 'MemAvailable' "$tmp"; then kind=resources
elif grep -q 'docker build' "$tmp"; then kind=build
elif grep -q 'setsid' "$tmp"; then kind=launch
elif grep -q '@@STATE' "$tmp"; then kind=poll
elif grep -q 'mkdir "\\$app_dir/.deploy.lock"' "$tmp"; then kind=lock
elif grep -q 'rmdir "\\$app_dir/.deploy.lock"' "$tmp"; then kind=unlock
elif grep -q 'COMPOSE_PROFILES' "$tmp"; then kind=relay2
elif grep -q 'ls -A' "$tmp"; then kind=check
fi
echo "ssh $*\${kind:+ [$kind]}" >> "$CALLS"
n="$(wc -l < "$CALLS" | tr -d ' ')"
mv "$tmp" "$STDIN_DIR/$n.stdin"
target=""
cmd=""
for a in "$@"; do
  if [[ -z "$target" ]]; then
    if [[ "$a" != -* && "$a" == *@* ]]; then target="$a"; fi
  else
    cmd="\${cmd:+$cmd }$a"
  fi
done
if [[ "$*" == *ConnectTimeout=15* && -n "\${FAKE_UNREACHABLE:-}" ]]; then exit 255; fi
case "$kind" in
  resources)
    printf '@@ROOT /var/lib/docker\\n@@DISK_KB %s\\n@@MEM_KB %s\\n' "\${FAKE_DISK_KB:-20971520}" "\${FAKE_MEM_KB:-4194304}"
    exit 0 ;;
  build)
    if [[ -n "\${FAKE_BUILD_FAIL:-}" ]]; then exit 1; fi ;;
  poll)
    if [[ -n "\${FAKE_POLL_FAIL_FIRST:-}" ]]; then
      echo x >> "$STDIN_DIR/pollfails"
      if [[ "$(wc -l < "$STDIN_DIR/pollfails" | tr -d ' ')" -le "$FAKE_POLL_FAIL_FIRST" ]]; then exit 255; fi
    fi
    if [[ -n "\${FAKE_POLL_DROP:-}" ]]; then
      echo x >> "$STDIN_DIR/polls"
      if [[ "$(wc -l < "$STDIN_DIR/polls" | tr -d ' ')" -gt "$FAKE_POLL_DROP" ]]; then exit 255; fi
    fi ;;
esac
cd "$FAKE_REMOTE_HOME" || exit 99
HOME="$FAKE_REMOTE_HOME" RELAY_UID="$(id -u)" HEALTH_TIMEOUT_SECONDS=3 sh -c "$cmd" < "$STDIN_DIR/$n.stdin"
`;

// Copies what is sent into the sandbox home (dest "host:path" -> $FAKE_REMOTE_HOME/path).
const FAKE_RSYNC = `#!/usr/bin/env bash
echo "rsync $*" >> "$CALLS"
list=""; ignore=0; delete=0; skip=0; srcs=()
for a in "$@"; do
  if (( skip )); then skip=0; continue; fi
  case "$a" in
    -e) skip=1 ;;
    --files-from=*) list="\${a#--files-from=}" ;;
    --ignore-existing) ignore=1 ;;
    --delete) delete=1 ;;
    -*) ;;
    *) srcs+=("$a") ;;
  esac
done
last=$(( \${#srcs[@]} - 1 ))
dest="\${srcs[$last]}"
unset "srcs[$last]"
dpath="\${dest#*:}"
target="$FAKE_REMOTE_HOME/$dpath"
if [[ -n "$list" ]]; then
  tr '\\0' '\\n' < "$list" >> "$FILES_FROM"
  while IFS= read -r -d '' f; do
    mkdir -p "$target/$(dirname "$f")"
    cp -p "$f" "$target/$f"
  done < "$list"
  exit 0
fi
for src in "\${srcs[@]}"; do
  if [[ "$src" == */ ]]; then
    if (( delete )); then rm -rf "$target"; fi
    mkdir -p "$target"
    cp -R "$src". "$target"
  else
    if [[ "$dpath" == */ ]]; then mkdir -p "$target"; tf="$target$(basename "$src")"; else mkdir -p "$(dirname "$target")"; tf="$target"; fi
    if (( ignore )) && [[ -e "$tf" ]]; then continue; fi
    cp "$src" "$tf"
  fi
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
if [[ "$last" == *feedcheck=* ]]; then
  name="\${last##*/}"; name="\${name%%\\?*}"
  if [[ -f "$LIVE_FEEDS/$name" ]]; then cat "$LIVE_FEEDS/$name"; exit 0; fi
  exit 22
fi
if [[ "$last" == */appcast.xml\\?verify=* ]]; then
  cat "$DIST/appcast.xml"
  exit 0
fi
exit 0
`;

// The remote docker: logs, reports healthy unless the app dir has a docker-unhealthy file, and `compose
// up` takes 6 s when it has a docker-slow file.
const FAKE_DOCKER = `#!/usr/bin/env bash
echo "docker $* [IMAGE_TAG=\${IMAGE_TAG:-}]" >> "$DOCKER_CALLS"
if [[ "$1 $2" == "compose up" ]]; then
  if [[ -e docker-slow ]]; then sleep 6; fi
  exit 0
fi
if [[ "$1 $2" == "compose ps" ]]; then echo "\${@: -1}-container-id"; exit 0; fi
if [[ "$1" == inspect ]]; then
  if [[ -e docker-unhealthy ]]; then echo unhealthy; else echo healthy; fi
  exit 0
fi
exit 0
`;

const FAKE_TIMEOUT = `#!/usr/bin/env bash
shift
exec "$@"
`;

const FAKE_CAFFEINATE = `#!/usr/bin/env bash
echo "caffeinate $*" >> "$CALLS.caffeinate"
exit 0
`;

function makeBin(root) {
  const bin = join(root, 'bin');
  mkdirSync(bin, { recursive: true });
  for (const [name, body] of [
    ['ssh', FAKE_SSH], ['rsync', FAKE_RSYNC], ['curl', FAKE_CURL], ['docker', FAKE_DOCKER],
    ['timeout', FAKE_TIMEOUT], ['caffeinate', FAKE_CAFFEINATE],
  ]) {
    writeFileSync(join(bin, name), body);
    chmodSync(join(bin, name), 0o755);
  }
  return bin;
}

function baseEnv(root, extra = {}) {
  const calls = join(root, 'calls.log');
  const filesFrom = join(root, 'files-from.txt');
  for (const dir of ['home', 'tmp', 'locks', 'live', 'stdin', 'remote']) mkdirSync(join(root, dir), { recursive: true });
  for (const f of [calls, filesFrom, join(root, 'docker.log')]) if (!existsSync(f)) writeFileSync(f, '');
  return {
    PATH: `${join(root, 'bin')}:${process.env.PATH}`,
    HOME: join(root, 'home'),
    TMPDIR: join(root, 'tmp'),
    CALLS: calls,
    DOCKER_CALLS: join(root, 'docker.log'),
    STDIN_DIR: join(root, 'stdin'),
    FILES_FROM: filesFrom,
    FAKE_REMOTE_HOME: join(root, 'remote'),
    LIVE_FEEDS: join(root, 'live'),
    SHELLX_LOCK_DIR: join(root, 'locks'),
    SHELLX_SMOKE_INTERVAL: '0',
    SHELLX_SMOKE_ATTEMPTS: '2',
    SHELLX_ROLLOUT_POLL: '0.2',
    ...extra,
  };
}

export const readCalls = (root) => readFileSync(join(root, 'calls.log'), 'utf8').split('\n').filter(Boolean);

export function waitFor(cond, ms = 30000) {
  const start = Date.now();
  while (Date.now() - start < ms) {
    if (cond()) return true;
    spawnSync('sleep', ['0.2']);
  }
  return cond();
}

// --- vps-deploy.sh ------------------------------------------------------------------------------------

export function git(cwd, ...args) {
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

export function put(root, rel, content = `${rel}\n`) {
  const path = join(root, rel);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, content);
}

// The git repository (shaped like this one) and its bare "origin" are built once per test process and
// copied for each test: a commit and a push per test would double the run time.
let template = null;
function repoTemplate() {
  if (template) return template;
  const root = mkdtempSync(join(tmpdir(), 'shellx-vpsdeploy-template-'));
  const work = join(root, 'repo');
  const origin = join(root, 'origin.git');
  mkdirSync(work, { recursive: true });
  git(root, 'init', '-q', '--bare', origin);
  git(work, 'init', '-q');
  git(work, 'symbolic-ref', 'HEAD', 'refs/heads/main');
  put(work, '.gitignore', 'node_modules\ndist\n.env\n');
  put(work, 'README.md');
  for (const f of [
    'relay/Dockerfile', 'relay/package.json', 'relay/src/server.ts', 'web/Dockerfile', 'web/package.json',
    'web/src/pages/index.astro', 'deploy/web/nginx.conf', 'deploy/relay.env',
    'deploy/nginx-proxy/shellx.pro', 'deploy/backup/entrypoint.sh', 'deploy/README.md',
  ]) put(work, f);
  put(work, 'deploy/docker-compose.yml', `services:\n  relay2:\n    build:\n      context: ./relay2-src/${R2}\n`);
  copyFileSync(DEPLOY_SCRIPT, join(work, 'deploy', 'vps-deploy.sh'));
  copyFileSync(ROLLOUT_SCRIPT, join(work, 'deploy', 'rollout.sh'));
  chmodSync(join(work, 'deploy', 'vps-deploy.sh'), 0o755);
  git(work, 'add', '-A');
  git(work, 'commit', '-q', '-m', 'init');
  git(work, 'remote', 'add', 'origin', origin);
  git(work, 'push', '-q', 'origin', 'main');
  // Ignored files must never be sent.
  put(work, 'relay/node_modules/leftpad/index.js');
  put(work, 'web/dist/index.html');
  put(work, 'relay/.env', 'SECRET=1\n');
  template = root;
  return root;
}

// A throwaway copy of that repository, with origin/main, and a sandbox VPS.
export function deploySetup() {
  const tpl = repoTemplate();
  const root = mkdtempSync(join(tmpdir(), 'shellx-vpsdeploy-'));
  const work = join(root, 'repo');
  const origin = join(root, 'origin.git');
  for (const dir of ['repo', 'origin.git']) {
    const copied = spawnSync('cp', ['-R', join(tpl, dir), join(root, dir)]);
    assert.equal(copied.status, 0, String(copied.stderr));
  }
  git(work, 'remote', 'set-url', 'origin', origin);
  makeBin(root);
  const env = baseEnv(root);
  // The sandbox VPS: ShellX's folder as README "First-time setup" leaves it.
  const app = join(root, 'remote', 'phu', 'shellx');
  mkdirSync(join(app, 'data'), { recursive: true });
  writeFileSync(join(app, '.env'), 'PROXY_NETWORK=proxy-net\nIMAGE_TAG=old\n');
  mkdirSync(join(app, 'relay2-src', R2, 'scripts', 'shellx', 'relay2'), { recursive: true });
  writeFileSync(join(app, 'relay2-src', R2, 'scripts', 'shellx', 'relay2', 'Dockerfile'), 'FROM scratch\n');
  const sha = git(work, 'rev-parse', 'HEAD');
  const run = (args = [], extraEnv = {}) =>
    spawnSync('bash', [join(work, 'deploy', 'vps-deploy.sh'), ...args], {
      cwd: work, encoding: 'utf8', env: { ...env, ...extraEnv }, timeout: 120000,
    });
  const lockKey = spawnSync('cksum', { input: 'higio@42.115.41.70:phu/shellx', encoding: 'utf8' }).stdout.split(' ')[0];
  return {
    root,
    work,
    app,
    sha,
    run,
    calls: () => readCalls(root),
    put: (rel, c) => put(work, rel, c),
    git: (...a) => git(work, ...a),
    sandbox: (rel) => join(app, rel),
    macLock: join(root, 'locks', `shellx-vps-deploy-${lockKey}.lock`),
    dockerCalls: () => readFileSync(join(root, 'docker.log'), 'utf8').split('\n').filter(Boolean),
    // The sandbox .env, as rollout.sh left it.
    envFile: () => readFileSync(join(app, '.env'), 'utf8'),
  };
}

// --- publish-to-vps.sh --------------------------------------------------------------------------------

export const sha256 = (c) => createHash('sha256').update(c).digest('hex');
export const VERSION = '1.5.1';
export const PROD = 'https://download.shellx.pro';

// A release folder like make-feeds.sh writes (with or without the Windows installer).
export function writeDist(dir, { exe = true, version = VERSION, base = `${PROD}/desktop/${version}/` } = {}) {
  mkdirSync(dir, { recursive: true });
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

export function publishSetup({ exe = true, base } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'shellx-publish-'));
  makeBin(root);
  const dist = join(root, 'dist');
  writeDist(dist, { exe, base });
  const env = baseEnv(root, { DIST: dist });
  const app = join(root, 'remote', 'phu', 'shellx');
  mkdirSync(join(app, 'downloads', 'desktop'), { recursive: true });
  const run = (args = [VERSION, dist], extraEnv = {}) =>
    spawnSync('bash', [PUBLISH_SCRIPT, ...args], { encoding: 'utf8', env: { ...env, ...extraEnv }, timeout: 60000 });
  const lockKey = spawnSync('cksum', { input: `higio@42.115.41.70:phu/shellx:${VERSION}`, encoding: 'utf8' }).stdout.split(' ')[0];
  return {
    root,
    dist,
    app,
    desktop: join(app, 'downloads', 'desktop'),
    live: join(root, 'live'),
    run,
    calls: () => readCalls(root),
    macLock: join(root, 'locks', `shellx-vps-publish-${lockKey}.lock`),
  };
}

// The file names each rsync call sends: the local paths between the -e option string and the destination.
export const rsyncUploads = (calls) => calls
  .filter((l) => l.startsWith('rsync'))
  .map((l) => l.replace(/^rsync .*?-o ServerAliveCountMax=4 /, '').replace(/ higio@\S+$/, '')
    .split(' ').map((p) => p.split('/').pop()).join(' '));

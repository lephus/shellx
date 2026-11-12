// Plan 1D Task 2: desktop release builds carry the Google Desktop OAuth client. The scripts run from a
// sandbox copy (REPO_ROOT = the sandbox), against fake ensure-ghosttykit, xcodebuild and ssh.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const HELPER = 'scripts/shellx/release/google-desktop-client.sh';
const ID = '123456789012-abcdefghijklmnopqrstuvwxyz012345.apps.googleusercontent.com';
const SECRET = 'GOCSPX-fake-0123456'; // short on purpose: the secret scans of Tasks 9 and 10 look for 20+ characters
const GOOD = { SHELLX_GOOGLE_DESKTOP_CLIENT_ID: ID, SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET: SECRET };
const env = (extra = {}) => ({ PATH: process.env.PATH, HOME: process.env.HOME, ...extra });
const withBin = (root, extra = {}) => env({ PATH: `${join(root, 'bin')}:${process.env.PATH}`, ...extra });

function sandbox(...rels) {
  const root = mkdtempSync(join(tmpdir(), 'shellx-release-'));
  for (const rel of rels) { mkdirSync(dirname(join(root, rel)), { recursive: true }); cpSync(join(repo, rel), join(root, rel)); }
  return root;
}
function script(path, body) { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, `#!/usr/bin/env bash\n${body}\n`); chmodSync(path, 0o755); }
const sourced = (call, extra) => spawnSync('bash', ['-c', `. "${join(repo, HELPER)}" && ${call}`], { encoding: 'utf8', env: env(extra) });

const FAKE_XCODEBUILD = `prev=; dd=
for a in "$@"; do [[ "$prev" == -derivedDataPath ]] && dd="$a"; prev="$a"; done
bin="$dd/Build/Products/Release/ShellX.app/Contents/MacOS/ShellX"; mkdir -p "$(dirname "$bin")"
if [[ "$FAKE_EMBED" == yes ]]; then printf 'x\\0%s\\0%s\\0' "$SHELLX_GOOGLE_DESKTOP_CLIENT_ID" "$SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET" > "$bin"; else printf 'x\\0' > "$bin"; fi`;

const FAKE_SSH = `i=$(( $(ls "$CALLS" | grep -c '\\.argv$') + 1 ))
printf '%s' "$*" > "$CALLS/$i.argv"; cat > "$CALLS/$i.stdin"
case "$*" in
  *"df -Pk"*) echo 100 ;;
  *"echo taken"*) echo taken ;;
  *"echo released"*) echo released ;;
  *"cat ~/phu/shellx/.winbuild/out/ShellX-Setup-9.9.9.exe"*|*"cat ~/phu/shellx/.winbuild/out/shellx-desktop.exe"*) printf 'EXE' ;;
  *"cat ~/phu/shellx/.winbuild/out/SHA256SUMS"*)
    sum=$(printf 'EXE' | shasum -a 256 | cut -d' ' -f1)
    printf '%s  ShellX-Setup-9.9.9.exe\\n%s  shellx-desktop.exe\\n' "$sum" "$sum" ;;
  *"test -f ~/phu/shellx/.winbuild/out/shellx_desktop.pdb"*) exit 1 ;;
esac
exit 0`;

test('the guard names the missing or malformed variable and never prints a value', () => {
  for (const [extra, name] of [
    [{}, 'SHELLX_GOOGLE_DESKTOP_CLIENT_ID'],
    [{ ...GOOD, SHELLX_GOOGLE_DESKTOP_CLIENT_ID: '0-shellx-placeholder' }, 'SHELLX_GOOGLE_DESKTOP_CLIENT_ID'],
    [{ SHELLX_GOOGLE_DESKTOP_CLIENT_ID: ID }, 'SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET'],
    [{ ...GOOD, SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET: 'has space' }, 'SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET'],
  ]) {
    const r = sourced('shellx_require_google_desktop_client', extra);
    assert.deepEqual([r.status, r.stdout], [1, ''], name);
    assert.match(r.stderr, new RegExp(`^error: ${name} `));
    for (const value of Object.values(extra)) assert.ok(!r.stderr.includes(value), 'a value was printed');
  }
  const ok = sourced('shellx_require_google_desktop_client', GOOD);
  assert.deepEqual([ok.status, ok.stdout, ok.stderr], [0, '', '']);
});

test('the binary check needs both values in the built bytes and prints nothing', () => {
  const dir = mkdtempSync(join(tmpdir(), 'shellx-bin-'));
  writeFileSync(join(dir, 'both'), Buffer.concat([Buffer.from([0, 1]), Buffer.from(ID), Buffer.from([0]), Buffer.from(SECRET), Buffer.from([255])]));
  writeFileSync(join(dir, 'id-only'), Buffer.concat([Buffer.from(ID), Buffer.from([0])]));
  const run = (f) => sourced(`shellx_binary_has_google_desktop_client "${join(dir, f)}"`, GOOD);
  for (const [f, status] of [['both', 0], ['id-only', 1]]) assert.deepEqual([run(f).status, run(f).stdout, run(f).stderr], [status, '', ''], f);
});

test('sign-and-notarize.sh --build needs the client before building, and in the built app', () => {
  const root = sandbox('scripts/shellx/sign-and-notarize.sh', HELPER);
  const marker = join(root, 'ensure.called');
  script(join(root, 'scripts/ensure-ghosttykit.sh'), `touch "${marker}"`);
  script(join(root, 'bin/xcodebuild'), FAKE_XCODEBUILD);
  const run = (extra) => spawnSync('bash', [join(root, 'scripts/shellx/sign-and-notarize.sh'), '--build', join(root, 'dd')], { encoding: 'utf8', env: withBin(root, extra) });
  const refused = run({});
  assert.equal(refused.status, 1);
  assert.match(refused.stderr, /^error: SHELLX_GOOGLE_DESKTOP_CLIENT_ID /m);
  assert.equal(existsSync(marker), false, 'the build started without the client');
  const missing = run({ ...GOOD, FAKE_EMBED: 'no' });
  assert.deepEqual([missing.status, missing.stdout], [1, '']);
  assert.match(missing.stderr, /does not carry the Google Desktop OAuth client/);
  const built = run({ ...GOOD, FAKE_EMBED: 'yes' });
  assert.equal(built.status, 0, built.stderr);
  assert.match(built.stdout, /\/dd\/Build\/Products\/Release\/ShellX\.app\n$/);
  assert.match(built.stderr, /==> Google Desktop OAuth client: present/);
  for (const r of [refused, missing, built]) assert.ok(!(r.stdout + r.stderr).includes(SECRET));
});

test('build-windows-cross.sh refuses before any ssh without the client', () => {
  const root = sandbox('scripts/shellx/release/build-windows-cross.sh', HELPER);
  const log = join(root, 'ssh.log');
  script(join(root, 'bin/ssh'), `echo "$*" >> "${log}"; exit 1`);
  const r = spawnSync('bash', [join(root, 'scripts/shellx/release/build-windows-cross.sh'), join(root, 'out')], { encoding: 'utf8', input: '', env: withBin(root, { SHELLX_GOOGLE_DESKTOP_CLIENT_ID: ID }) });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /^error: SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET /m);
  assert.equal(existsSync(log), false, 'ssh ran without the client');
});

test('build-windows-cross.sh gives the container the client on stdin, never on a command line', () => {
  const root = sandbox('scripts/shellx/release/build-windows-cross.sh', HELPER, 'scripts/shellx/check-google-branding.py');
  for (const [rel, text] of Object.entries({
    'windows/Cargo.toml': '[workspace.package]\nversion = "9.9.9"\n', 'windows/cross/Dockerfile': 'FROM scratch\n',
    'cmux-tui/README.md': 'x\n', 'shellx-core/README.md': 'x\n',
    '.gitmodules': '[submodule "ghostty"]\n\tpath = ghostty\n\turl = https://example.invalid/ghostty.git\n',
  })) { mkdirSync(dirname(join(root, rel)), { recursive: true }); writeFileSync(join(root, rel), text); }
  const git = (...args) => assert.equal(spawnSync('git', ['-C', root, ...args]).status, 0, args.join(' '));
  git('init', '-q'); git('add', 'windows', 'cmux-tui', 'shellx-core', '.gitmodules');
  git('update-index', '--add', '--cacheinfo', `160000,${'a'.repeat(40)},ghostty`);
  git('-c', 'user.name=t', '-c', 'user.email=t@t.invalid', '-c', 'commit.gpgsign=false', 'commit', '-q', '-m', 'fixture');
  const calls = join(root, 'calls'); mkdirSync(calls);
  script(join(root, 'bin/ssh'), FAKE_SSH);
  const r = spawnSync('bash', [join(root, 'scripts/shellx/release/build-windows-cross.sh'), join(root, 'out')], { encoding: 'utf8', input: '', env: withBin(root, { CALLS: calls, SHELLX_GOOGLE_BRANDING_ROOT: repo, ...GOOD }) });
  assert.equal(r.status, 0, r.stderr);
  const n = readdirSync(calls).filter((f) => f.endsWith('.argv')).length;
  const argv = (i) => readFileSync(join(calls, `${i}.argv`), 'utf8');
  for (let i = 1; i <= n; i++) assert.ok(!argv(i).includes(ID) && !argv(i).includes(SECRET), `ssh call ${i} carries a value in its arguments`);
  const builds = Array.from({ length: n }, (_, i) => i + 1).filter((i) => argv(i).includes('build-in-container.sh'));
  assert.equal(builds.length, 1);
  assert.match(argv(builds[0]), /-e SHELLX_GOOGLE_DESKTOP_CLIENT_ID -e SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET\s/);
  assert.equal(readFileSync(join(calls, `${builds[0]}.stdin`), 'utf8'), `${ID}\n${SECRET}\n`);
  assert.ok(!(r.stdout + r.stderr).includes(SECRET));
  assert.ok(!(r.stdout + r.stderr).includes(ID));
  // No file the script left behind holds a value (calls/ is the fake's own record of stdin).
  const walk = (d) => readdirSync(d, { withFileTypes: true }).flatMap((e) => (e.name === 'calls' && d === root ? [] : e.isDirectory() ? walk(join(d, e.name)) : [join(d, e.name)]));
  for (const f of walk(root)) { const b = readFileSync(f); assert.ok(!b.includes(SECRET) && !b.includes(ID), `${f} holds a value`); }
});

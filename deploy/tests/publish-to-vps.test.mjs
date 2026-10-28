// Tests for scripts/shellx/release/publish-to-vps.sh against a fake ssh, rsync and curl and a sandbox
// "remote home" (see vps-fakes.mjs): the order of the uploads, feeds last, the immutable-version refusal,
// the Mac-only release, the checks, and the input validation.
//   node --test deploy/tests/*.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  chmodSync, existsSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync,
} from 'node:fs';
import { join } from 'node:path';
import {
  FIXED, PROD, SSH_DEFAULT, VERSION, esc, publishSetup, rsyncUploads, sha256, waitFor,
} from './vps-fakes.mjs';

test('publish: installers first, then the feeds with SHA256SUMS last, permissions set, nothing outside phu/shellx', () => {
  const s = publishSetup();
  const result = s.run();
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const calls = s.calls();
  const base = esc(SSH_DEFAULT);
  const order = [
    new RegExp(`^ssh .*ConnectTimeout=15.* higio@42\\.115\\.41\\.70 true$`),
    new RegExp(`^${base} bash -s -- phu/shellx 1\\.5\\.1 \\[check\\]$`),
    /^curl .*ShellX-1\.5\.1\.dmg\?precheck=/,
    /^curl .*ShellX-Setup-1\.5\.1\.exe\?precheck=/,
    /mkdir -p phu\/shellx\/downloads\/desktop\/1\.5\.1 && chmod 755 phu\/shellx\/downloads phu\/shellx\/downloads\/desktop phu\/shellx\/downloads\/desktop\/1\.5\.1$/,
    /^rsync -t --ignore-existing -e .*ShellX-1\.5\.1\.dmg .*ShellX-Setup-1\.5\.1\.exe higio@42\.115\.41\.70:phu\/shellx\/downloads\/desktop\/1\.5\.1\/$/,
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
  for (const line of calls.filter((l) => /^(ssh|rsync) /.test(l))) assert.match(line, new RegExp(esc(FIXED)));
  assert.match(result.stdout, /\| ShellX-Setup-1\.5\.1\.exe \| https:\/\/download\.shellx\.pro\/desktop\/1\.5\.1\/ShellX-Setup-1\.5\.1\.exe \| [0-9a-f]{64} \|/);

  // What landed on the (sandbox) VPS, with the modes nginx needs.
  const mode = (p) => statSync(p).mode & 0o777;
  const versionDir = join(s.desktop, VERSION);
  for (const dir of [join(s.app, 'downloads'), s.desktop, versionDir]) assert.equal(mode(dir), 0o755, dir);
  for (const f of [join(versionDir, `ShellX-${VERSION}.dmg`), join(versionDir, `ShellX-Setup-${VERSION}.exe`),
    ...['appcast.xml', 'latest-macos.json', 'latest-windows.json', 'SHA256SUMS'].map((n) => join(s.desktop, n))]) {
    assert.equal(mode(f), 0o644, f);
  }
  assert.equal(existsSync(s.macLock), false);
  assert.ok(waitFor(() => existsSync(join(s.root, 'calls.log.caffeinate'))));
  assert.match(readFileSync(join(s.root, 'calls.log.caffeinate'), 'utf8'), /^caffeinate -i -w \d+$/m);
});

test('publish: a Mac-only release keeps the live latest-windows.json, uploads no exe and never lists one in SHA256SUMS', () => {
  const s = publishSetup({ exe: false });
  // A stale Windows line in SHA256SUMS and a leftover latest-windows.json must not matter.
  writeFileSync(join(s.dist, 'SHA256SUMS'), `${readFileSync(join(s.dist, 'SHA256SUMS'), 'utf8')}${'0'.repeat(64)}  ShellX-Setup-${VERSION}.exe\n${'1'.repeat(64)}  latest-windows.json\n`);
  writeFileSync(join(s.dist, 'latest-windows.json'), '{"version":"0.0.1"}\n');
  writeFileSync(join(s.desktop, 'latest-windows.json'), 'LIVE WINDOWS\n');
  const result = s.run();
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const calls = s.calls();
  assert.match(result.stdout, /Mac-only release\. The live latest-windows\.json is kept/);
  assert.match(result.stdout, /kept the live .*latest-windows\.json/);
  assert.equal(calls.some((l) => /Setup|latest-windows\.json higio/.test(l)), false, calls.join('\n'));
  assert.deepEqual(rsyncUploads(calls), ['ShellX-1.5.1.dmg', 'appcast.xml', 'latest-macos.json', 'SHA256SUMS']);
  assert.doesNotMatch(result.stdout, /\| ShellX-Setup/);
  // The live Windows feed is untouched; the uploaded SHA256SUMS lists exactly the Mac files.
  assert.equal(readFileSync(join(s.desktop, 'latest-windows.json'), 'utf8'), 'LIVE WINDOWS\n');
  const sums = readFileSync(join(s.desktop, 'SHA256SUMS'), 'utf8');
  assert.deepEqual(sums.split('\n').filter(Boolean).map((l) => l.slice(66)), [`ShellX-${VERSION}.dmg`, 'appcast.xml', 'latest-macos.json']);
  assert.doesNotMatch(sums, /Setup|windows/);
  assert.equal(existsSync(join(s.desktop, VERSION, `ShellX-Setup-${VERSION}.exe`)), false);
});

test('publish --dry-run runs the local checks, prints the commands and contacts nobody', () => {
  const s = publishSetup();
  const result = s.run(['--dry-run', VERSION, s.dist]);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(s.calls(), []);
  assert.match(result.stdout, /feeds ok/);
  assert.match(result.stdout, new RegExp(`\\+ rsync -t --ignore-existing -e '${esc(`ssh -o ControlPath=~/.ssh/cm-shellx-vps ${FIXED}`)}' .*ShellX-1\\.5\\.1\\.dmg .*ShellX-Setup-1\\.5\\.1\\.exe higio@42\\.115\\.41\\.70:phu/shellx/downloads/desktop/1\\.5\\.1/`));
  assert.equal(existsSync(s.macLock), false);

  // The local checks run in a dry run too.
  writeFileSync(join(s.dist, `ShellX-${VERSION}.dmg`), 'tampered\n');
  const bad = s.run(['--dry-run', VERSION, s.dist]);
  assert.equal(bad.status, 1);
});

test('publish refuses a version folder that already has files and, when no live feed points at it, says removing it is safe', () => {
  const s = publishSetup();
  mkdirSync(join(s.desktop, VERSION));
  writeFileSync(join(s.desktop, VERSION, `ShellX-${VERSION}.dmg`), 'half an upload');
  for (const name of ['appcast.xml', 'latest-macos.json', 'latest-windows.json']) {
    writeFileSync(join(s.live, name), `{"url":"${PROD}/desktop/1.5.0/ShellX-1.5.0.x"}\n`);
  }
  const result = s.run();
  assert.equal(result.status, 1);
  assert.match(result.stderr, /already has files; bump the version instead of overwriting/);
  assert.match(result.stderr, /No live feed points at 1\.5\.1.*interrupted upload.*safe/s);
  assert.match(result.stderr, /ssh -o ControlPath=~\/\.ssh\/cm-shellx-vps higio@42\.115\.41\.70 rm -rf phu\/shellx\/downloads\/desktop\/1\.5\.1/);
  assert.equal(s.calls().some((l) => l.startsWith('rsync')), false);
  assert.ok(existsSync(join(s.desktop, VERSION, `ShellX-${VERSION}.dmg`)), 'nothing is removed for you');
});

test('publish: a version a live feed already points at is published; do not touch it', () => {
  const s = publishSetup();
  mkdirSync(join(s.desktop, VERSION));
  writeFileSync(join(s.desktop, VERSION, `ShellX-${VERSION}.dmg`), 'x');
  writeFileSync(join(s.live, 'appcast.xml'), `<enclosure url="${PROD}/desktop/${VERSION}/ShellX-${VERSION}.dmg"/>\n`);
  writeFileSync(join(s.live, 'latest-macos.json'), '{"url":"https://download.shellx.pro/desktop/1.5.0/ShellX-1.5.0.dmg"}\n');
  writeFileSync(join(s.live, 'latest-windows.json'), '{"url":"https://download.shellx.pro/desktop/1.5.0/ShellX-Setup-1.5.0.exe"}\n');
  const result = s.run();
  assert.equal(result.status, 1);
  assert.match(result.stderr, /the live appcast\.xml points at 1\.5\.1/);
  assert.match(result.stderr, /is published.*do not touch the folder/);
  assert.doesNotMatch(result.stderr, /rm -rf/);
});

test('publish: when the live feeds cannot be read it does not say removing the folder is safe', () => {
  const s = publishSetup();
  mkdirSync(join(s.desktop, VERSION));
  writeFileSync(join(s.desktop, VERSION, `ShellX-${VERSION}.dmg`), 'x');
  const result = s.run(); // the fake curl has no live feeds to serve: every feed read fails
  assert.equal(result.status, 1);
  assert.match(result.stderr, /could not read the live appcast\.xml/);
  assert.match(result.stderr, /Could not check the live feeds/);
  assert.doesNotMatch(result.stderr, /rm -rf/);
});

test('publish: a version folder that cannot be listed counts as not free (a failing ls -A is never "empty")', { skip: process.getuid() === 0 }, () => {
  const s = publishSetup();
  const dir = join(s.desktop, VERSION);
  mkdirSync(dir);
  chmodSync(dir, 0o000);
  try {
    const result = s.run();
    assert.equal(result.status, 1);
    assert.match(result.stderr, /already has files/);
    assert.equal(s.calls().some((l) => l.startsWith('rsync')), false);
  } finally {
    chmodSync(dir, 0o755);
  }
});

test('publish: an empty version folder (an upload that died before its first file) is fine', () => {
  const s = publishSetup();
  mkdirSync(join(s.desktop, VERSION));
  const result = s.run();
  assert.equal(result.status, 0, result.stdout + result.stderr);
});

test('publish: installers are uploaded with --ignore-existing, so a file that appears meanwhile is never replaced', () => {
  const s = publishSetup();
  const result = s.run();
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const installerRsync = s.calls().find((l) => l.includes('ShellX-1.5.1.dmg') && l.startsWith('rsync'));
  assert.match(installerRsync, /rsync -t --ignore-existing /);
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
  assert.equal(existsSync(s.macLock), false);
});

test('publish: a tampered installer fails the checksum check before any ssh', () => {
  const s = publishSetup();
  writeFileSync(join(s.dist, `ShellX-${VERSION}.dmg`), 'tampered\n');
  const result = s.run();
  assert.equal(result.status, 1);
  assert.match(result.stderr, /checksums in SHA256SUMS do not match/);
  assert.deepEqual(s.calls(), []);
});

test('publish: SHA256SUMS must list every file it uploads, and every line must be well formed', () => {
  const s = publishSetup();
  const original = readFileSync(join(s.dist, 'SHA256SUMS'), 'utf8');
  writeFileSync(join(s.dist, 'SHA256SUMS'), original.split('\n').filter((l) => !l.endsWith('  appcast.xml')).join('\n'));
  const missing = s.run();
  assert.equal(missing.status, 1);
  assert.match(missing.stderr, /SHA256SUMS does not list appcast\.xml/);

  writeFileSync(join(s.dist, 'SHA256SUMS'), `${original}not a checksum line\n`);
  const malformed = s.run();
  assert.equal(malformed.status, 1);
  assert.match(malformed.stderr, /has a line that is not '<sha256>  <file name>'/);
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

test('publish: DOWNLOAD_BASE_URL other than https://download.shellx.pro is refused unless explicitly allowed', () => {
  const s = publishSetup();
  const refused = s.run(undefined, { DOWNLOAD_BASE_URL: 'https://staging.example.com' });
  assert.equal(refused.status, 1);
  assert.match(refused.stderr, /DOWNLOAD_BASE_URL is https:\/\/staging\.example\.com, not https:\/\/download\.shellx\.pro/);
  assert.match(refused.stderr, /SHELLX_ALLOW_OTHER_DOWNLOAD_URL=1/);
  assert.deepEqual(s.calls(), []);

  // With the override the feeds are checked against that address (so the production feeds no longer pass).
  const other = publishSetup({ base: 'https://staging.example.com/desktop/1.5.1/' });
  const allowed = other.run(['--dry-run', VERSION, other.dist], { DOWNLOAD_BASE_URL: 'https://staging.example.com', SHELLX_ALLOW_OTHER_DOWNLOAD_URL: '1' });
  assert.equal(allowed.status, 0, allowed.stdout + allowed.stderr);
  const mismatch = s.run(['--dry-run', VERSION, s.dist], { DOWNLOAD_BASE_URL: 'https://staging.example.com', SHELLX_ALLOW_OTHER_DOWNLOAD_URL: '1' });
  assert.equal(mismatch.status, 1);

  // The default (unset) and the explicit production address both pass the gate.
  assert.equal(s.run(['--dry-run', VERSION, s.dist], { DOWNLOAD_BASE_URL: PROD }).status, 0);
});

test('publish: the ControlPath default only goes with the default target', () => {
  const s = publishSetup();
  const refused = s.run(undefined, { SHELLX_VPS: 'deploy@other.example' });
  assert.equal(refused.status, 1);
  assert.match(refused.stderr, /SHELLX_VPS_SSH_OPTS/);
  assert.deepEqual(s.calls(), []);
  const ok = s.run(['--dry-run', VERSION, s.dist], { SHELLX_VPS: 'deploy@other.example', SHELLX_VPS_SSH_OPTS: '' });
  assert.equal(ok.status, 0, ok.stderr);
  assert.doesNotMatch(ok.stdout, /ControlPath/);
  assert.match(ok.stdout, new RegExp(`ssh ${esc(FIXED)} deploy@other\\.example`));
});

test('publish refuses while another publish of the same version runs on this Mac', () => {
  const s = publishSetup();
  mkdirSync(s.macLock);
  writeFileSync(join(s.macLock, 'pid'), `${process.pid}\n`);
  const result = s.run();
  assert.equal(result.status, 1);
  assert.match(result.stderr, /another publish of 1\.5\.1 is running on this Mac/);
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

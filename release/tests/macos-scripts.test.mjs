// Exercises release/macos/*.sh on a fake app bundle with an ad-hoc signature ("-").
// macOS only; skipped elsewhere. Real Developer ID signing only happens in release-desktop.yml.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readlinkSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const scripts = join(dirname(fileURLToPath(import.meta.url)), '..', 'macos');
const skip = process.platform !== 'darwin';

function plist(entries) {
  const body = Object.entries(entries)
    .map(([k, v]) => `<key>${k}</key>${typeof v === 'boolean' ? `<${v}/>` : `<string>${v}</string>`}`)
    .join('');
  return `<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict>${body}</dict></plist>\n`;
}

function fakeApp(dir) {
  const app = join(dir, 'ShellX.app');
  mkdirSync(join(app, 'Contents/MacOS'), { recursive: true });
  mkdirSync(join(app, 'Contents/Frameworks'), { recursive: true });
  writeFileSync(
    join(app, 'Contents/Info.plist'),
    plist({ CFBundleExecutable: 'ShellX', CFBundleIdentifier: 'pro.shellx.desktop', CFBundlePackageType: 'APPL' }),
  );
  copyFileSync('/usr/bin/true', join(app, 'Contents/MacOS/ShellX'));
  // Any Mach-O file works for codesign; this stands in for a plugin dylib.
  copyFileSync('/usr/bin/true', join(app, 'Contents/Frameworks/libplugin.dylib'));
  // Stands in for shellx-term (spec §10.7), built into Contents/Helpers by the Xcode phase.
  mkdirSync(join(app, 'Contents/Helpers'), { recursive: true });
  copyFileSync('/usr/bin/true', join(app, 'Contents/Helpers/shellx-term'));
  return app;
}

function run(cmd, args, env = {}) {
  return spawnSync(cmd, args, { encoding: 'utf8', env: { ...process.env, ...env } });
}

test('sign-app.sh signs nested code and the app with hardened runtime', { skip }, () => {
  const dir = mkdtempSync(join(tmpdir(), 'shellx-sign-'));
  try {
    const app = fakeApp(dir);
    const entitlements = join(dir, 'Release.entitlements');
    writeFileSync(entitlements, plist({ 'com.apple.security.network.client': true }));
    const result = run(join(scripts, 'sign-app.sh'), [app, entitlements], { MACOS_SIGNING_IDENTITY: '-' });
    assert.equal(result.status, 0, result.stderr);
    for (const target of [app, join(app, 'Contents/Frameworks/libplugin.dylib'), join(app, 'Contents/Helpers/shellx-term')]) {
      const info = run('codesign', ['-dv', '--verbose=4', target]);
      assert.match(info.stderr, /flags=0x\w+\([^)]*runtime[^)]*\)/, `${target} lacks hardened runtime`);
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('sign-app.sh ad-hoc signature disables library validation so the dry-run app can load its frameworks', { skip }, () => {
  const dir = mkdtempSync(join(tmpdir(), 'shellx-sign-'));
  try {
    const app = fakeApp(dir);
    const entitlements = join(dir, 'Release.entitlements');
    writeFileSync(entitlements, plist({ 'com.apple.security.network.client': true }));
    const result = run(join(scripts, 'sign-app.sh'), [app, entitlements], { MACOS_SIGNING_IDENTITY: '-' });
    assert.equal(result.status, 0, result.stderr);
    const info = run('codesign', ['-d', '--entitlements', '-', app]);
    const text = info.stdout + info.stderr;
    assert.match(text, /com\.apple\.security\.cs\.disable-library-validation/);
    assert.match(text, /com\.apple\.security\.network\.client/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('sign-app.sh refuses entitlements that enable App Sandbox', { skip }, () => {
  const dir = mkdtempSync(join(tmpdir(), 'shellx-sign-'));
  try {
    const app = fakeApp(dir);
    const entitlements = join(dir, 'Release.entitlements');
    writeFileSync(entitlements, plist({ 'com.apple.security.app-sandbox': true }));
    const result = run(join(scripts, 'sign-app.sh'), [app, entitlements], { MACOS_SIGNING_IDENTITY: '-' });
    assert.notEqual(result.status, 0);
    assert.match(result.stdout + result.stderr, /app-sandbox/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('make-dmg.sh packs the app as ShellX.app next to an /Applications link', { skip }, () => {
  const dir = mkdtempSync(join(tmpdir(), 'shellx-dmg-'));
  const mount = join(dir, 'mnt');
  try {
    const app = fakeApp(dir);
    const dmg = join(dir, 'out', 'ShellX-9.9.9.dmg');
    const made = run(join(scripts, 'make-dmg.sh'), [app, dmg]);
    assert.equal(made.status, 0, made.stderr);
    assert.ok(existsSync(dmg));
    mkdirSync(mount);
    const attach = run('hdiutil', ['attach', '-nobrowse', '-readonly', '-mountpoint', mount, dmg]);
    assert.equal(attach.status, 0, attach.stderr);
    try {
      assert.ok(existsSync(join(mount, 'ShellX.app/Contents/Info.plist')), 'ShellX.app missing in dmg');
      assert.ok(lstatSync(join(mount, 'Applications')).isSymbolicLink());
      assert.equal(readlinkSync(join(mount, 'Applications')), '/Applications');
    } finally {
      run('hdiutil', ['detach', mount, '-force']);
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// Stand-ins for xcrun (notarytool, stapler) and spctl: log their arguments, report "Accepted".
function fakeNotaryTools(dir) {
  const bin = join(dir, 'bin');
  mkdirSync(bin);
  const log = join(dir, 'calls.log');
  writeFileSync(join(bin, 'xcrun'), `#!/bin/bash\necho "xcrun $*" >> '${log}'\nif [[ "$1 $2" == "notarytool submit" ]]; then echo '{"status":"Accepted","id":"sub-1"}'; fi\n`, { mode: 0o755 });
  writeFileSync(join(bin, 'spctl'), `#!/bin/bash\necho "spctl $*" >> '${log}'\n`, { mode: 0o755 });
  return { path: `${bin}:${process.env.PATH}`, log };
}

const notaryEnvUnset = { APPLE_API_KEY_PATH: '', APPLE_API_KEY_ID: '', APPLE_API_ISSUER_ID: '', APPLE_APP_SPECIFIC_PASSWORD: '', APPLE_ID: '', APPLE_TEAM_ID: '' };

test('notarize.sh signs in with the Apple ID, app-specific password and team when there is no API key', { skip }, () => {
  const dir = mkdtempSync(join(tmpdir(), 'shellx-notary-'));
  try {
    const tools = fakeNotaryTools(dir);
    const dmg = join(dir, 'ShellX-9.9.9.dmg');
    writeFileSync(dmg, 'x');
    const result = run(join(scripts, 'notarize.sh'), [dmg], {
      ...notaryEnvUnset, PATH: tools.path, APPLE_ID: 'dev@example.com', APPLE_TEAM_ID: 'ABCDE12345', APPLE_APP_SPECIFIC_PASSWORD: 'abcd-efgh-ijkl-mnop',
    });
    assert.equal(result.status, 0, result.stderr);
    const calls = readFileSync(tools.log, 'utf8');
    assert.match(calls, /xcrun notarytool submit .*ShellX-9\.9\.9\.dmg --apple-id dev@example\.com --password abcd-efgh-ijkl-mnop --team-id ABCDE12345 --wait/);
    assert.match(calls, /xcrun stapler staple .*ShellX-9\.9\.9\.dmg/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('notarize.sh prefers the App Store Connect API key when it is set', { skip }, () => {
  const dir = mkdtempSync(join(tmpdir(), 'shellx-notary-'));
  try {
    const tools = fakeNotaryTools(dir);
    const dmg = join(dir, 'ShellX-9.9.9.dmg');
    writeFileSync(dmg, 'x');
    const result = run(join(scripts, 'notarize.sh'), [dmg], {
      ...notaryEnvUnset, PATH: tools.path, APPLE_API_KEY_PATH: '/tmp/AuthKey.p8', APPLE_API_KEY_ID: 'KEY1234567', APPLE_API_ISSUER_ID: 'issuer-uuid',
      APPLE_ID: 'dev@example.com', APPLE_TEAM_ID: 'ABCDE12345', APPLE_APP_SPECIFIC_PASSWORD: 'abcd-efgh-ijkl-mnop',
    });
    assert.equal(result.status, 0, result.stderr);
    assert.match(readFileSync(tools.log, 'utf8'), /--key \/tmp\/AuthKey\.p8 --key-id KEY1234567 --issuer issuer-uuid --wait/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('notarize.sh says which secrets are missing when it has no way to sign in', { skip }, () => {
  const dir = mkdtempSync(join(tmpdir(), 'shellx-notary-'));
  try {
    const tools = fakeNotaryTools(dir);
    const dmg = join(dir, 'ShellX-9.9.9.dmg');
    writeFileSync(dmg, 'x');
    const result = run(join(scripts, 'notarize.sh'), [dmg], { ...notaryEnvUnset, PATH: tools.path, APPLE_ID: 'dev@example.com', APPLE_TEAM_ID: 'ABCDE12345' });
    assert.equal(result.status, 1);
    assert.match(result.stdout + result.stderr, /APPLE_APP_SPECIFIC_PASSWORD/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('check-team.sh refuses code that is not signed by the expected team', { skip }, () => {
  const dir = mkdtempSync(join(tmpdir(), 'shellx-team-'));
  try {
    const app = fakeApp(dir);
    const entitlements = join(dir, 'Release.entitlements');
    writeFileSync(entitlements, plist({ 'com.apple.security.network.client': true }));
    assert.equal(run(join(scripts, 'sign-app.sh'), [app, entitlements], { MACOS_SIGNING_IDENTITY: '-' }).status, 0);
    const result = run(join(scripts, 'check-team.sh'), [app, 'ABCDE12345']);
    assert.equal(result.status, 1);
    assert.match(result.stdout + result.stderr, /signed by team 'not set', expected ABCDE12345/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

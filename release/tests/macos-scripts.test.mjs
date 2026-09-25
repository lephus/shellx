// Exercises release/macos/*.sh on a fake app bundle with an ad-hoc signature ("-").
// macOS only; skipped elsewhere. Real Developer ID signing only happens in release-desktop.yml.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readlinkSync, rmSync, writeFileSync } from 'node:fs';
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
    for (const target of [app, join(app, 'Contents/Frameworks/libplugin.dylib')]) {
      const info = run('codesign', ['-dv', '--verbose=4', target]);
      assert.match(info.stderr, /flags=0x\w+\([^)]*runtime[^)]*\)/, `${target} lacks hardened runtime`);
    }
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

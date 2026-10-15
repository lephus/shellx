import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  announceNeeded, compareVersions, installerUrls, publishDecision, pubspecBuild, pubspecVersion, relayLatestVersion, resolveRelease,
} from '../scripts/version.mjs';

const pubspec = (version) => `name: shellx_desktop\nversion: ${version}\nenvironment:\n  sdk: ^3.11.0\n`;
const relayEnv = (latest) => `MIN_AGENT=1.0.0\nLATEST_AGENT_VERSION=${latest}\nMAC_URL=x\nWIN_URL=y\n`;

test('pubspecVersion strips the +build suffix', () => {
  assert.equal(pubspecVersion(pubspec('1.2.3+7')), '1.2.3');
  assert.equal(pubspecVersion(pubspec('1.2.3')), '1.2.3');
});

test('pubspecVersion rejects a pubspec without a version line', () => {
  assert.throws(() => pubspecVersion('name: shellx_desktop\n'), /no "version:"/);
});

test('pubspecBuild reads the +build number, 0 when there is none', () => {
  assert.equal(pubspecBuild(pubspec('1.2.3+7')), 7);
  assert.equal(pubspecBuild(pubspec('1.2.3')), 0);
});

test('compareVersions orders x.y.z numerically', () => {
  assert.equal(compareVersions('1.0.10', '1.0.9'), 1);
  assert.equal(compareVersions('1.0.0', '1.0.0'), 0);
  assert.equal(compareVersions('0.9.9', '1.0.0'), -1);
  assert.equal(compareVersions('2.0.0', '1.99.99'), 1);
});

test('relayLatestVersion reads LATEST_AGENT_VERSION from deploy/relay.env', () => {
  assert.equal(relayLatestVersion(relayEnv('1.4.2')), '1.4.2');
  assert.throws(() => relayLatestVersion('MIN_AGENT=1.0.0\n'), /no LATEST_AGENT_VERSION/);
});

test('installerUrls names both installers under the version folder', () => {
  assert.deepEqual(installerUrls('1.2.3', 'https://download.shellx.pro'), {
    dmg: 'https://download.shellx.pro/desktop/1.2.3/ShellX-1.2.3.dmg',
    exe: 'https://download.shellx.pro/desktop/1.2.3/ShellX-Setup-1.2.3.exe',
  });
});

test('a push to main releases the pubspec version', () => {
  const result = resolveRelease({
    eventName: 'push', refType: 'branch', refName: 'main', pubspecText: pubspec('1.2.3+7'), relayEnvText: relayEnv('1.2.2'),
  });
  assert.deepEqual(result, { version: '1.2.3', dryRun: false });
});

test('a push to main may release the version the relay already names (first release)', () => {
  const result = resolveRelease({
    eventName: 'push', refType: 'branch', refName: 'main', pubspecText: pubspec('1.0.0+1'), relayEnvText: relayEnv('1.0.0'),
  });
  assert.deepEqual(result, { version: '1.0.0', dryRun: false });
});

test('a pubspec version older than the released one is refused', () => {
  assert.throws(
    () => resolveRelease({
      eventName: 'push', refType: 'branch', refName: 'main', pubspecText: pubspec('1.2.0'), relayEnvText: relayEnv('1.2.3'),
    }),
    /1\.2\.0 is older than the released 1\.2\.3/,
  );
});

test('a push to another branch or a tag is refused', () => {
  assert.throws(
    () => resolveRelease({ eventName: 'push', refType: 'branch', refName: 'dev', pubspecText: pubspec('1.2.3'), relayEnvText: relayEnv('1.0.0') }),
    /only from main/,
  );
  assert.throws(
    () => resolveRelease({ eventName: 'push', refType: 'tag', refName: 'desktop-v1.2.3', pubspecText: pubspec('1.2.3'), relayEnvText: relayEnv('1.0.0') }),
    /only from main/,
  );
});

test('a manual run is a dry run unless dry_run is unchecked', () => {
  const result = resolveRelease({
    eventName: 'workflow_dispatch', refType: 'branch', refName: 'feat/x', inputDryRun: 'true',
    pubspecText: pubspec('1.2.3+1'), relayEnvText: relayEnv('1.0.0'),
  });
  assert.deepEqual(result, { version: '1.2.3', dryRun: true });
  const byDefault = resolveRelease({
    eventName: 'workflow_dispatch', refType: 'branch', refName: 'feat/x', inputDryRun: '',
    pubspecText: pubspec('1.2.3+1'), relayEnvText: relayEnv('1.0.0'),
  });
  assert.equal(byDefault.dryRun, true);
});

test('a dry run may build an older version (nothing is published)', () => {
  const result = resolveRelease({
    eventName: 'workflow_dispatch', refType: 'branch', refName: 'old', inputDryRun: 'true',
    pubspecText: pubspec('0.9.0'), relayEnvText: relayEnv('1.0.0'),
  });
  assert.deepEqual(result, { version: '0.9.0', dryRun: true });
});

test('a manual real release runs only from main', () => {
  assert.throws(
    () => resolveRelease({
      eventName: 'workflow_dispatch', refType: 'branch', refName: 'feat/x', inputDryRun: 'false',
      pubspecText: pubspec('1.2.3'), relayEnvText: relayEnv('1.0.0'),
    }),
    /only from main/,
  );
  const result = resolveRelease({
    eventName: 'workflow_dispatch', refType: 'branch', refName: 'main', inputDryRun: 'false',
    pubspecText: pubspec('1.2.3+2'), relayEnvText: relayEnv('1.0.0'),
  });
  assert.deepEqual(result, { version: '1.2.3', dryRun: false });
});

test('an unexpected event is refused', () => {
  assert.throws(
    () => resolveRelease({ eventName: 'pull_request', refType: 'branch', refName: 'main', pubspecText: pubspec('1.2.3'), relayEnvText: relayEnv('1.0.0') }),
    /unexpected event pull_request/,
  );
});

for (const bad of ['1.2', '1.2.3-rc.1', '01.2.3']) {
  test(`pubspec version ${bad} is refused`, () => {
    assert.throws(
      () => resolveRelease({ eventName: 'push', refType: 'branch', refName: 'main', pubspecText: pubspec(bad), relayEnvText: relayEnv('1.0.0') }),
      /not a x\.y\.z version/,
    );
  });
}

test('publishDecision builds when neither installer is published', () => {
  assert.equal(publishDecision({ dmg: 404, exe: 404 }), 'build');
});

test('publishDecision skips a version that is already published', () => {
  assert.equal(publishDecision({ dmg: 200, exe: 200 }), 'skip');
});

test('publishDecision refuses a half-published version', () => {
  assert.throws(() => publishDecision({ dmg: 200, exe: 404 }), /only the dmg is published/);
  assert.throws(() => publishDecision({ dmg: 404, exe: 200 }), /only the exe is published/);
});

test('publishDecision refuses an unexpected answer from download.shellx.pro', () => {
  assert.throws(() => publishDecision({ dmg: 0, exe: 404 }), /cannot check/);
  assert.throws(() => publishDecision({ dmg: 404, exe: 503 }), /cannot check/);
});

test('announceNeeded is true while the relay or the website still names an older version', () => {
  assert.equal(announceNeeded('1.0.1', { relay: '1.0.0', site: '1.0.1' }), true);
  assert.equal(announceNeeded('1.0.1', { relay: '1.0.1', site: '1.0.0' }), true);
  assert.equal(announceNeeded('1.0.1', { relay: '1.0.1', site: '1.0.1' }), false);
  assert.equal(announceNeeded('1.0.0', { relay: '1.0.1', site: '1.0.1' }), false);
});

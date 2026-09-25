import { test } from 'node:test';
import assert from 'node:assert/strict';
import { pubspecVersion, resolveRelease } from '../scripts/version.mjs';

const pubspec = (version) => `name: shellx_desktop\nversion: ${version}\nenvironment:\n  sdk: ^3.11.0\n`;

test('pubspecVersion strips the +build suffix', () => {
  assert.equal(pubspecVersion(pubspec('1.2.3+7')), '1.2.3');
  assert.equal(pubspecVersion(pubspec('1.2.3')), '1.2.3');
});

test('pubspecVersion rejects a pubspec without a version line', () => {
  assert.throws(() => pubspecVersion('name: shellx_desktop\n'), /no "version:"/);
});

test('tag push publishes the tagged version', () => {
  const result = resolveRelease({
    eventName: 'push', refType: 'tag', refName: 'desktop-v1.2.3', pubspecText: pubspec('1.2.3+7'),
  });
  assert.deepEqual(result, { version: '1.2.3', dryRun: false });
});

test('tag push fails when the tag does not match apps/desktop/pubspec.yaml', () => {
  assert.throws(
    () => resolveRelease({ eventName: 'push', refType: 'tag', refName: 'desktop-v1.2.4', pubspecText: pubspec('1.2.3+7') }),
    /does not match apps\/desktop\/pubspec.yaml version 1.2.3/,
  );
});

for (const refName of ['desktop-v1.2', 'desktop-v1.2.3-rc.1', 'v1.2.3', 'desktop-v01.2.3']) {
  test(`tag ${refName} is rejected`, () => {
    assert.throws(
      () => resolveRelease({ eventName: 'push', refType: 'tag', refName, pubspecText: pubspec('1.2.3') }),
      /not a release tag/,
    );
  });
}

test('manual dry run from a branch uses the input version', () => {
  const result = resolveRelease({
    eventName: 'workflow_dispatch', refType: 'branch', refName: 'main',
    inputVersion: '1.2.3', inputDryRun: 'true', pubspecText: pubspec('1.2.3+1'),
  });
  assert.deepEqual(result, { version: '1.2.3', dryRun: true });
});

test('manual real release from a branch is refused', () => {
  assert.throws(
    () => resolveRelease({
      eventName: 'workflow_dispatch', refType: 'branch', refName: 'main',
      inputVersion: '1.2.3', inputDryRun: 'false', pubspecText: pubspec('1.2.3'),
    }),
    /must run from a desktop-v\* tag/,
  );
});

test('manual run on a tag must agree with the version input', () => {
  assert.throws(
    () => resolveRelease({
      eventName: 'workflow_dispatch', refType: 'tag', refName: 'desktop-v1.2.3',
      inputVersion: '1.2.4', inputDryRun: 'false', pubspecText: pubspec('1.2.3'),
    }),
    /input version 1.2.4 does not match tag desktop-v1.2.3/,
  );
});

test('manual real release from a tag is allowed', () => {
  const result = resolveRelease({
    eventName: 'workflow_dispatch', refType: 'tag', refName: 'desktop-v1.2.3',
    inputVersion: '', inputDryRun: 'false', pubspecText: pubspec('1.2.3+2'),
  });
  assert.deepEqual(result, { version: '1.2.3', dryRun: false });
});

test('manual run from a branch without a version is refused', () => {
  assert.throws(
    () => resolveRelease({
      eventName: 'workflow_dispatch', refType: 'branch', refName: 'main',
      inputVersion: '', inputDryRun: 'true', pubspecText: pubspec('1.2.3'),
    }),
    /version input is required/,
  );
});

test('an invalid version input is refused', () => {
  assert.throws(
    () => resolveRelease({
      eventName: 'workflow_dispatch', refType: 'branch', refName: 'main',
      inputVersion: '1.2', inputDryRun: 'true', pubspecText: pubspec('1.2.3'),
    }),
    /not a x\.y\.z version/,
  );
});

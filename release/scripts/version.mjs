// Decides which desktop version a release-desktop.yml run builds, and whether it is a dry run.
// A real (signed + uploaded) release only ever comes from a `desktop-vX.Y.Z` tag whose version
// equals the `version:` in apps/desktop/pubspec.yaml (build suffix `+N` ignored).

const SEMVER = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;
const TAG = /^desktop-v(.+)$/;

export function pubspecVersion(pubspecText) {
  const match = pubspecText.match(/^version:\s*([^\s#]+)/m);
  if (!match) throw new Error('apps/desktop/pubspec.yaml has no "version:" line');
  return match[1].split('+')[0];
}

function versionFromTag(refName) {
  const match = refName.match(TAG);
  if (!match || !SEMVER.test(match[1])) {
    throw new Error(`"${refName}" is not a release tag (expected desktop-vX.Y.Z)`);
  }
  return match[1];
}

/**
 * @param {{eventName: string, refType: string, refName: string, inputVersion?: string,
 *          inputDryRun?: string, pubspecText: string}} ctx
 * @returns {{version: string, dryRun: boolean}}
 */
export function resolveRelease({ eventName, refType, refName, inputVersion = '', inputDryRun = '', pubspecText }) {
  const onTag = refType === 'tag';
  const dryRun = eventName === 'workflow_dispatch' ? inputDryRun !== 'false' : false;
  let version;
  if (onTag) {
    version = versionFromTag(refName);
    if (inputVersion && inputVersion !== version) {
      throw new Error(`input version ${inputVersion} does not match tag ${refName}`);
    }
  } else {
    if (eventName !== 'workflow_dispatch') throw new Error(`unexpected event ${eventName} on ${refType} ${refName}`);
    if (!dryRun) throw new Error('a real release must run from a desktop-v* tag; use dry_run on branches');
    if (!inputVersion) throw new Error('the version input is required when running from a branch');
    version = inputVersion;
  }
  if (!SEMVER.test(version)) throw new Error(`"${version}" is not a x.y.z version`);
  const declared = pubspecVersion(pubspecText);
  if (declared !== version) {
    throw new Error(`release version ${version} does not match apps/desktop/pubspec.yaml version ${declared}`);
  }
  return { version, dryRun };
}

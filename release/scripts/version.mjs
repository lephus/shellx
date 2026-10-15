// Decides which desktop version a release-desktop.yml run builds, and whether it is a dry run.
// The `version:` in apps/desktop/pubspec.yaml (build suffix `+N` ignored) is the only source of
// truth: a push to main releases it unless download.shellx.pro already serves it.

export const SEMVER = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;
const RELEASE_BRANCH = 'main';

function versionLine(pubspecText) {
  const match = pubspecText.match(/^version:\s*([^\s#]+)/m);
  if (!match) throw new Error('apps/desktop/pubspec.yaml has no "version:" line');
  return match[1];
}

export function pubspecVersion(pubspecText) {
  return versionLine(pubspecText).split('+')[0];
}

export function pubspecBuild(pubspecText) {
  const build = versionLine(pubspecText).split('+')[1];
  return build === undefined ? 0 : Number.parseInt(build, 10);
}

export function compareVersions(a, b) {
  const pa = a.split('.').map(Number);
  const pb = b.split('.').map(Number);
  for (let i = 0; i < 3; i += 1) {
    if (pa[i] !== pb[i]) return pa[i] > pb[i] ? 1 : -1;
  }
  return 0;
}

export function relayLatestVersion(relayEnvText) {
  const match = relayEnvText.match(/^LATEST_AGENT_VERSION=(\S+)/m);
  if (!match) throw new Error('deploy/relay.env has no LATEST_AGENT_VERSION line');
  return match[1];
}

export function installerUrls(version, baseUrl) {
  return {
    dmg: `${baseUrl}/desktop/${version}/ShellX-${version}.dmg`,
    exe: `${baseUrl}/desktop/${version}/ShellX-Setup-${version}.exe`,
  };
}

/**
 * @param {{eventName: string, refType: string, refName: string, inputDryRun?: string,
 *          pubspecText: string, relayEnvText: string}} ctx
 * @returns {{version: string, dryRun: boolean}}
 */
export function resolveRelease({ eventName, refType, refName, inputDryRun = '', pubspecText, relayEnvText }) {
  let dryRun;
  if (eventName === 'push') dryRun = false;
  else if (eventName === 'workflow_dispatch') dryRun = inputDryRun !== 'false';
  else throw new Error(`unexpected event ${eventName} on ${refType} ${refName}`);
  const onMain = refType === 'branch' && refName === RELEASE_BRANCH;
  if (!dryRun && !onMain) {
    throw new Error(`a real release runs only from ${RELEASE_BRANCH} (this run is on ${refType} ${refName}); use dry_run elsewhere`);
  }
  const version = pubspecVersion(pubspecText);
  if (!SEMVER.test(version)) throw new Error(`apps/desktop/pubspec.yaml version "${version}" is not a x.y.z version`);
  const released = relayLatestVersion(relayEnvText);
  if (!dryRun && compareVersions(version, released) < 0) {
    throw new Error(`apps/desktop/pubspec.yaml version ${version} is older than the released ${released} (deploy/relay.env); raise it with release/scripts/bump.mjs`);
  }
  return { version, dryRun };
}

/**
 * Whether a published version still has to be announced: the relay (deploy/relay.env) or the
 * website (web/src/site.config.json) names an older one, e.g. after a failed announce job.
 * @param {string} version
 * @param {{relay: string, site: string}} named
 */
export function announceNeeded(version, { relay, site }) {
  return compareVersions(version, relay) > 0 || compareVersions(version, site) > 0;
}

/**
 * What a real release does with the HTTP status download.shellx.pro gave for each installer URL
 * (0 when it could not be reached): build both, or skip a version that is already out.
 * @param {{dmg: number, exe: number}} status
 * @returns {'build' | 'skip'}
 */
export function publishDecision({ dmg, exe }) {
  for (const [name, code] of Object.entries({ dmg, exe })) {
    if (code !== 200 && code !== 404) {
      throw new Error(`cannot check whether the ${name} is published: download.shellx.pro answered ${code || 'nothing'} (is the web container on the VPS running?)`);
    }
  }
  if (dmg === 404 && exe === 404) return 'build';
  if (dmg === 200 && exe === 200) return 'skip';
  const only = dmg === 200 ? 'dmg' : 'exe';
  throw new Error(`only the ${only} is published for this version; delete it on the VPS (downloads/desktop/<version>/) and run the release again, or raise the version`);
}

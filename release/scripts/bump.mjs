// Picks the next desktop version: `node release/scripts/bump.mjs X.Y.Z` from the repo root sets
// `version: X.Y.Z+N` in apps/desktop/pubspec.yaml (N = previous build number + 1). Commit and push
// to main, and release-desktop.yml builds and publishes it.
import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { compareVersions, pubspecBuild, pubspecVersion, relayLatestVersion, SEMVER } from './version.mjs';

const PUBSPEC = 'apps/desktop/pubspec.yaml';
const RELAY_ENV = 'deploy/relay.env';
const WHATS_NEW = 'apps/desktop/assets/whats_new.json';

export function bumpPubspec(pubspecText, newVersion, releasedVersion) {
  if (!SEMVER.test(newVersion)) throw new Error(`"${newVersion}" is not a x.y.z version`);
  if (compareVersions(newVersion, releasedVersion) <= 0) {
    throw new Error(`${newVersion} must be newer than the released ${releasedVersion} (${RELAY_ENV})`);
  }
  const current = pubspecVersion(pubspecText);
  if (compareVersions(newVersion, current) < 0) {
    throw new Error(`${newVersion} is older than ${current} in ${PUBSPEC}`);
  }
  const build = pubspecBuild(pubspecText) + 1;
  return pubspecText.replace(/^version:[^\S\n]*[^\s#]+/m, `version: ${newVersion}+${build}`);
}

function main(argv) {
  const newVersion = argv[0];
  if (!newVersion) throw new Error('usage: node release/scripts/bump.mjs X.Y.Z (run from the repo root)');
  const before = readFileSync(PUBSPEC, 'utf8');
  const after = bumpPubspec(before, newVersion, relayLatestVersion(readFileSync(RELAY_ENV, 'utf8')));
  writeFileSync(PUBSPEC, after);
  const line = (text) => text.match(/^version:\s*(\S+)/m)[1];
  console.log(`${PUBSPEC}: ${line(before)} → ${line(after)}`);
  const whatsNew = JSON.parse(readFileSync(WHATS_NEW, 'utf8'));
  if (!whatsNew[newVersion]) {
    console.error(`warning: ${WHATS_NEW} has no "${newVersion}" entry, so the "What's new" card will not show for this version`);
  }
  console.log(`Next: commit and push to main; release-desktop.yml publishes ShellX ${newVersion}.`);
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    console.error(`error: ${error.message}`);
    process.exit(1);
  }
}

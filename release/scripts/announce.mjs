// After release-desktop.yml has published a version: point the relay (`GET /v1/version`, which
// tells running agents to update) and the website's download buttons at it. Never moves either
// back to an older version. Usage, from the repo root: node release/scripts/announce.mjs X.Y.Z
// Appends `changed=true|false` to $GITHUB_OUTPUT when set.
import { appendFileSync, readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { compareVersions, installerUrls, relayLatestVersion, SEMVER } from './version.mjs';

const RELAY_ENV = 'deploy/relay.env';
const SITE_CONFIG = 'web/src/site.config.json';
const DOWNLOAD_BASE_URL = 'https://download.shellx.pro';

function setEnvValue(text, key, value) {
  const line = new RegExp(`^${key}=.*$`, 'm');
  if (!line.test(text)) throw new Error(`${RELAY_ENV} has no ${key} line`);
  return text.replace(line, `${key}=${value}`);
}

export function announceRelayEnv(relayEnvText, version, baseUrl) {
  for (const key of ['LATEST_AGENT_VERSION', 'MAC_URL', 'WIN_URL']) setEnvValue(relayEnvText, key, '');
  if (compareVersions(version, relayLatestVersion(relayEnvText)) <= 0) return relayEnvText;
  const urls = installerUrls(version, baseUrl);
  let text = setEnvValue(relayEnvText, 'LATEST_AGENT_VERSION', version);
  text = setEnvValue(text, 'MAC_URL', urls.dmg);
  return setEnvValue(text, 'WIN_URL', urls.exe);
}

export function announceSiteConfig(siteConfigText, version) {
  const current = JSON.parse(siteConfigText).desktopVersion;
  if (typeof current !== 'string') throw new Error(`${SITE_CONFIG} has no "desktopVersion"`);
  if (compareVersions(version, current) <= 0) return siteConfigText;
  return siteConfigText.replace(/("desktopVersion"\s*:\s*)"[^"]*"/, `$1"${version}"`);
}

function main(argv) {
  const version = argv[0];
  if (!version || !SEMVER.test(version)) throw new Error(`"${version ?? ''}" is not a x.y.z version`);
  let changed = false;
  for (const [file, update] of [
    [RELAY_ENV, (text) => announceRelayEnv(text, version, DOWNLOAD_BASE_URL)],
    [SITE_CONFIG, (text) => announceSiteConfig(text, version)],
  ]) {
    const before = readFileSync(file, 'utf8');
    const after = update(before);
    if (after !== before) {
      writeFileSync(file, after);
      changed = true;
      console.log(`${file}: now names ${version}`);
    } else {
      console.log(`${file}: already at ${version} or newer`);
    }
  }
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `changed=${changed}\n`);
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    console.error(`::error::${error.message}`);
    process.exit(1);
  }
}

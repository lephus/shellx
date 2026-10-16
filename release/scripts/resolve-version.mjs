// CLI used by .github/workflows/release-desktop.yml. Reads the GitHub context from env, decides the
// version and the dry-run flag, and for a real release asks download.shellx.pro whether that
// version is already out. Prints the result and appends `version=` / `dry_run=` / `build=` /
// `announce=` to $GITHUB_OUTPUT when set. `announce=true` means the version is published but the
// relay or the website does not name it yet (a failed announce job), so the run only announces.
import { appendFileSync, readFileSync } from 'node:fs';
import { setTimeout as sleep } from 'node:timers/promises';
import { announceNeeded, installerUrls, publishDecision, relayLatestVersion, resolveRelease } from './version.mjs';

const ATTEMPTS = 3;
const retryDelayMs = Number(process.env.RETRY_DELAY_MS ?? 5_000);

// HTTP status of a HEAD request, 0 when unreachable; retried on 0 and 5xx (e.g. a web rollout).
async function status(url) {
  let code = 0;
  for (let attempt = 1; attempt <= ATTEMPTS; attempt += 1) {
    try {
      // Unique query string: never read (or seed) a cached answer for the real URL.
      const response = await fetch(`${url}?precheck=${Date.now()}-${attempt}`, {
        method: 'HEAD', redirect: 'manual', signal: AbortSignal.timeout(20_000),
      });
      code = response.status;
    } catch {
      code = 0;
    }
    if (code !== 0 && code < 500) return code;
    if (attempt < ATTEMPTS) await sleep(retryDelayMs * attempt);
  }
  return code;
}

try {
  const relayEnvText = readFileSync(process.env.RELAY_ENV_PATH ?? 'deploy/relay.env', 'utf8');
  const { version, dryRun } = resolveRelease({
    eventName: process.env.GITHUB_EVENT_NAME ?? '',
    refType: process.env.GITHUB_REF_TYPE ?? '',
    refName: process.env.GITHUB_REF_NAME ?? '',
    inputDryRun: process.env.INPUT_DRY_RUN ?? '',
    pubspecText: readFileSync(process.env.PUBSPEC_PATH ?? 'apps/desktop/pubspec.yaml', 'utf8'),
    relayEnvText,
  });
  let build = true;
  let announce = false;
  if (!dryRun) {
    const urls = installerUrls(version, process.env.DOWNLOAD_BASE_URL ?? 'https://download.shellx.pro');
    const [dmg, exe] = await Promise.all([status(urls.dmg), status(urls.exe)]);
    build = publishDecision({ dmg, exe }) === 'build';
    if (!build) {
      const site = JSON.parse(readFileSync(process.env.SITE_CONFIG_PATH ?? 'web/src/site.config.json', 'utf8')).desktopVersion;
      announce = announceNeeded(version, { relay: relayLatestVersion(relayEnvText), site });
      console.log(announce
        ? `ShellX ${version} is published but the relay or the website still names an older version; announcing it again.`
        : `ShellX ${version} is already published (${urls.dmg}); nothing to build. Raise the version with release/scripts/bump.mjs to release again.`);
    }
  }
  console.log(`version=${version} dry_run=${dryRun} build=${build} announce=${announce}`);
  if (process.env.GITHUB_OUTPUT) {
    appendFileSync(process.env.GITHUB_OUTPUT, `version=${version}\ndry_run=${dryRun}\nbuild=${build}\nannounce=${announce}\n`);
  }
} catch (error) {
  console.error(`::error::${error.message}`);
  process.exit(1);
}

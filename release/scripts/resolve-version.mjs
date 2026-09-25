// CLI used by .github/workflows/release-desktop.yml. Reads the GitHub context from env,
// prints the result and appends `version=` / `dry_run=` to $GITHUB_OUTPUT when set.
import { appendFileSync, readFileSync } from 'node:fs';
import { resolveRelease } from './version.mjs';

try {
  const result = resolveRelease({
    eventName: process.env.GITHUB_EVENT_NAME ?? '',
    refType: process.env.GITHUB_REF_TYPE ?? '',
    refName: process.env.GITHUB_REF_NAME ?? '',
    inputVersion: (process.env.INPUT_VERSION ?? '').trim(),
    inputDryRun: process.env.INPUT_DRY_RUN ?? '',
    pubspecText: readFileSync(process.env.PUBSPEC_PATH ?? 'apps/desktop/pubspec.yaml', 'utf8'),
  });
  console.log(`version=${result.version} dry_run=${result.dryRun}`);
  if (process.env.GITHUB_OUTPUT) {
    appendFileSync(process.env.GITHUB_OUTPUT, `version=${result.version}\ndry_run=${result.dryRun}\n`);
  }
} catch (error) {
  console.error(`::error::${error.message}`);
  process.exit(1);
}

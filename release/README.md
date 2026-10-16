# Desktop release pipeline

`.github/workflows/release-desktop.yml` builds, signs and publishes the desktop agent (spec §8.5, §14).

| Platform | File | Signing | Public URL |
|---|---|---|---|
| macOS 12+ (universal) | `ShellX-<v>.dmg` | Developer ID, hardened runtime, no App Sandbox, notarized and stapled | `https://download.shellx.pro/desktop/<v>/ShellX-<v>.dmg` |
| Windows 10 1809+ (x64) | `ShellX-Setup-<v>.exe` (Inno Setup, per-user, no UAC, English + Vietnamese) | Azure Artifact Signing (formerly "Trusted Signing") once its secrets exist; unsigned until then | `https://download.shellx.pro/desktop/<v>/ShellX-Setup-<v>.exe` |

**Triggers: push to main, the version is yours**

- The version is the `version:` line of `apps/desktop/pubspec.yaml` (the `+build` suffix is
  ignored). Pick the next one with `node release/scripts/bump.mjs X.Y.Z` (sets `X.Y.Z+N`, `N` = the
  previous build number + 1; refuses a version that is not newer than the released one), commit,
  push to `main`.
- Every push to `main` (except docs/Markdown-only pushes) runs the workflow. Its `prepare` job asks
  `download.shellx.pro` whether that version is already out:
  - both installers answer 200 → nothing to do, the run ends in seconds;
  - both answer 404 → build, sign, notarize, upload, then point the relay and the website at it
    (`announce` + `deploy` jobs, below);
  - only one is there, or the server cannot be reached → the run fails and says what to do.

  A release that failed half-way is therefore retried by the next push to `main` (or **Re-run
  failed jobs**), and only one release runs at a time. A `preflight` job stops a real release in
  seconds, before any build, while the macOS signing secrets are missing. If the installers are
  out but the relay or the website still names an older version (a failed `announce`), the next
  push to `main` only runs `announce` + `deploy`.
- After the upload, the `announce` job sets `LATEST_AGENT_VERSION`, `MAC_URL`, `WIN_URL` in
  `deploy/relay.env` and `desktopVersion` in `web/src/site.config.json`, commits that to `main` as
  `github-actions[bot]` (pull after a release), tags the released commit `desktop-vX.Y.Z` (best
  effort: a failed tag never blocks the deploy), then calls `deploy.yml` on the newest `main` to
  roll out the relay and the website. Installers are always live before
  anything links to them. It never moves either file back to an older version, and never changes
  `MIN_AGENT` / `MIN_MOBILE` (raise those by hand to force updates).
- **Actions → Release desktop → Run workflow** with `dry_run` checked (the default) builds and
  packages the pubspec version (from `main`, or any branch the `release` Environment admits —
  its jobs declare that Environment): the macOS app gets an ad-hoc signature, the
  installer is unsigned, nothing is uploaded, and the files are attached to the run as artifacts
  `macos-dmg` and `windows-installer`. An unchecked `dry_run` is accepted only on `main`.
- **Signing.** macOS is always signed with the Developer ID of team `W4RF3W4VTZ` (Apple account
  `phulealali@gmail.com`, both pinned in the workflow's `env:`) and notarized; a real release
  without the certificate fails rather than publish an unsigned dmg. Windows is signed only when the
  Azure secrets exist; otherwise the installer is published unsigned (SmartScreen: *More info → Run
  anyway*) and the run summary says so.

**Files**

| File | Purpose |
|---|---|
| `scripts/version.mjs`, `scripts/resolve-version.mjs` | Pick the version, the dry-run flag and whether it still needs building, from the GitHub context, the pubspec, `deploy/relay.env` and `download.shellx.pro` |
| `scripts/bump.mjs` | `node release/scripts/bump.mjs X.Y.Z`: set the next version in `apps/desktop/pubspec.yaml` |
| `scripts/announce.mjs` | After publishing: point `deploy/relay.env` and `web/src/site.config.json` at the new version |
| `macos/import-certificate.sh` | Import the Developer ID certificate into a temporary keychain; only an identity of team `APPLE_TEAM_ID` is used |
| `macos/check-team.sh` | Refuse an app or dmg not signed by team `APPLE_TEAM_ID` |
| `macos/sign-app.sh` | Sign nested code (dylibs, bundles, `Contents/Helpers/shellx-term`), then the app, with hardened runtime; refuse App Sandbox entitlements |
| `macos/notarize.sh` | `notarytool submit --wait` (API key if set, else Apple ID + app-specific password + team), staple, `spctl` check |
| `macos/make-dmg.sh` | Compressed dmg with `ShellX.app` and an `/Applications` link |
| `windows/shellx.iss` | Inno Setup script (per-user install, Windows 10 1809+, stops a running agent; uninstall runs `ShellX.exe --terminal-sharing-cleanup`) |
| `windows/Vietnamese.isl` | Unofficial Vietnamese messages, copied unchanged from `jrsoftware/issrc` tag `is-6_7_1` (`Files/Languages/Unofficial/Vietnamese.isl`); SHA-256 pinned in `tests/inno.test.mjs` |
| `windows/build-installer.ps1` | Find (or install) Inno Setup 6.7.1 and compile `shellx.iss` |
| `tests/*.test.mjs` | `node --test release/tests/*.test.mjs` (the macOS script tests run only on macOS) |

**shellx-term (terminal sharing):** `flutter build macos` builds it with cargo into
`ShellX.app/Contents/Helpers/shellx-term` (universal in Release: the macOS job adds the
`aarch64-apple-darwin` and `x86_64-apple-darwin` Rust targets); `flutter build windows` puts
`shellx-term.exe` (static CRT) next to `ShellX.exe`, where the Azure step signs it with the other
`exe` files. Both jobs fail if the helper is missing.

**Upload:** the `publish` job rsyncs both files over SSH into
`$VPS_APP_DIR/downloads/desktop/<version>/` on the VPS (default `~/phu/shellx`), with the `VPS_*`
secrets of the `production` Environment that `deploy.yml` already uses. The `web` container serves
that folder at `download.shellx.pro` with `Content-Disposition: attachment` and a one-year immutable
`Cache-Control` (`deploy/web/nginx.conf`). rsync writes to a temporary name and renames it, so a
half-uploaded file is never served under the real name.

## GitHub secrets

The signing secrets are **Environment secrets** of a GitHub Environment named `release` that allows
branch `main` (Settings → Environments → **New environment** → name `release` → **Deployment
branches and tags** → **Selected branches and tags** → add `main`; optionally add **Required
reviewers** for a manual approval before signing runs). Do **not** add them as repository secrets:
only the `macos` and `windows` jobs, which declare `environment: release`, can read them, and dry
runs use none of them.

Settings → Environments → `release` → **Environment secrets** → **Add secret**.

macOS (required for a real release; team `W4RF3W4VTZ`):

| Secret | Value |
|---|---|
| `MACOS_CERTIFICATE_P12_BASE64` | Base64 of the `.p12` export of the "Developer ID Application: … (W4RF3W4VTZ)" certificate **with its private key** (`base64 -i DeveloperID.p12 \| pbcopy`) |
| `MACOS_CERTIFICATE_PASSWORD` | Password chosen when exporting the `.p12` |
| `APPLE_APP_SPECIFIC_PASSWORD` | An app-specific password of `phulealali@gmail.com` (account.apple.com → Sign-In and Security → App-Specific Passwords), used by `notarytool` with team `W4RF3W4VTZ` |

Instead of the app-specific password, notarization can use an App Store Connect API key of the same
team: `APPLE_API_KEY_P8_BASE64` (base64 of `AuthKey_<KEYID>.p8`), `APPLE_API_KEY_ID`,
`APPLE_API_ISSUER_ID`. When `APPLE_API_KEY_P8_BASE64` is set it wins.

Windows (optional; without them the installer is published unsigned):

| Secret | Value |
|---|---|
| `AZURE_TENANT_ID` | Directory (tenant) ID of the app registration |
| `AZURE_CLIENT_ID` | Application (client) ID of the app registration |
| `AZURE_CLIENT_SECRET` | Client secret value of the app registration |
| `AZURE_SIGNING_ENDPOINT` | Signing account endpoint for its region, e.g. `https://weu.codesigning.azure.net/` |
| `AZURE_SIGNING_ACCOUNT_NAME` | Artifact Signing account name |
| `AZURE_CERTIFICATE_PROFILE_NAME` | Certificate profile name (Public Trust) |

The `publish` job reads `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY`, `VPS_KNOWN_HOSTS` and the
`VPS_APP_DIR` / `VPS_SSH_PORT` variables of the `production` Environment (`deploy/README.md`), the
same ones `deploy.yml` uses; nothing VPS-related is needed in `release`. It uploads installers into a
version folder and sets mode 755 on it and on its parents `downloads/` and `downloads/desktop/`, so
nginx (uid 101, in the `web` image) can reach them under a hardened umask.

The `announce` job pushes one commit to `main` and one `desktop-v*` tag with the workflow's
`GITHUB_TOKEN`. If a branch protection rule or ruleset blocks direct pushes to `main`, or a tag
ruleset restricts `desktop-v*` tags to maintainers (an earlier version of this README recommended
one), let GitHub Actions bypass it — or delete the tag ruleset; tags are no longer what triggers a
release. A blocked commit fails `announce` (the installers are live by then; the next push to
`main` tries again, or update the two files by hand); a blocked tag only costs the tag.

The public base URL (`https://download.shellx.pro`), the Apple account and team, and Flutter 3.41.7
are pinned in the workflow's `env:` block. The workflow expects the names fixed by `apps/desktop`:
`ShellX.app` with bundle id `pro.shellx.desktop`, and `ShellX.exe`.

## One-time setup

### 1. Apple (macOS signing and notarization)

Everything below uses the Apple account `phulealali@gmail.com` and team `W4RF3W4VTZ`.

1. Only the team's **Account Holder** can create a Developer ID certificate. On a Mac: Xcode →
   Settings → Accounts → **+** → sign in with `phulealali@gmail.com` → select team `W4RF3W4VTZ` →
   **Manage Certificates…** → **+** → **Developer ID Application** (or developer.apple.com →
   Certificates → **+** → Developer ID Application, with a CSR from Keychain Access).
2. Check it: `security find-identity -v -p codesigning` lists
   `"Developer ID Application: <name> (W4RF3W4VTZ)"`.
3. Keychain Access → login → My Certificates → right-click that certificate → **Export** → `.p12`
   with a strong password → `base64 -i DeveloperID.p12 | pbcopy` → store as
   `MACOS_CERTIFICATE_P12_BASE64`, the password as `MACOS_CERTIFICATE_PASSWORD`. Delete the `.p12`
   file afterwards.
4. account.apple.com → Sign-In and Security → **App-Specific Passwords** → **+** → name
   `shellx-notarize` → store as `APPLE_APP_SPECIFIC_PASSWORD`. (Changing the Apple account password
   revokes it; create a new one then.)
5. The certificate expires after 5 years; notarized builds keep working after expiry thanks to the
   secure timestamp, but new releases need a renewed certificate.

### 2. Azure Artifact Signing (Windows signing)

1. Check eligibility first: Public Trust identity validation is only offered to organizations and
   individual developers in the countries Microsoft lists for Artifact Signing. If the ShellX
   publisher is not eligible, use an OV code-signing certificate instead (spec §14 allows it) and
   replace the two "Sign … (Azure Artifact Signing)" steps in the workflow.
2. Azure portal → create an **Artifact Signing account** in a supported region. Its Overview page
   shows the **Account URI** → `AZURE_SIGNING_ENDPOINT`; the account name →
   `AZURE_SIGNING_ACCOUNT_NAME`.
3. Signing account → **Identity validations** → New → Public → complete the organization (or
   individual) validation.
4. Signing account → **Certificate profiles** → Create → **Public Trust** → select the validation →
   name → `AZURE_CERTIFICATE_PROFILE_NAME`.
5. Microsoft Entra ID → App registrations → **New registration** `shellx-release-signing` →
   copy Directory (tenant) ID → `AZURE_TENANT_ID`, Application (client) ID → `AZURE_CLIENT_ID`;
   Certificates & secrets → **New client secret** → `AZURE_CLIENT_SECRET` (note its expiry date).
6. Signing account → Access control (IAM) → Add role assignment → **Artifact Signing Certificate
   Profile Signer** (older portals: "Trusted Signing Certificate Profile Signer") → the app
   registration.

### 3. `download.shellx.pro` on the VPS

1. Set up the VPS as described in `deploy/README.md`: the `web` container serves
   `~/phu/shellx/downloads/` at `download.shellx.pro`, and the four `VPS_*` Environment secrets let
   the `publish` job upload into it.
2. Check: `curl -s -o /dev/null -w '%{http_code}\n' https://download.shellx.pro/desktop/0.0.0/none`
   prints `404`.

### 4. GitHub

1. Settings → Environments → **New environment** → name `release`, allow deployment for branch
   `main` (optionally add required reviewers), then add the macOS secrets above (and the Azure ones
   once you have them) as Environment secrets.
2. Optional: run one dry run (Actions → Release desktop → Run workflow, `dry_run` checked) to
   validate the toolchain and smoke-test the artifacts before the first real release.
3. There is no CI (VPS spec, decision V5): run the Dart, desktop and mobile tests on your machine
   before pushing to `main`, and `node --test release/tests/*.test.mjs` after touching `release/`.

## Releasing version X.Y.Z

1. Optionally add the version to `apps/desktop/assets/whats_new.json` (the "What's new" card shows
   only for versions listed there; `bump.mjs` warns when it is missing).
2. `node release/scripts/bump.mjs X.Y.Z`, run the desktop tests, commit, push to `main`.
3. Watch **Actions → Release desktop**. When it is green, its summary lists both public URLs with
   SHA-256 hashes, the relay already answers `"version":"X.Y.Z"` on
   `https://relay.shellx.pro/v1/version` (running agents show the update notice within 24 hours),
   and shellx.pro links to the new installers.
4. `git pull` (the release added a bot commit to `main`).
5. Smoke-test: on a clean Mac, download the dmg in a browser, drag ShellX to Applications and open
   it — macOS must show only the standard "downloaded from the Internet" prompt. On Windows, run
   the installer (unsigned: SmartScreen → More info → Run anyway); also once in **Windows Sandbox**
   (no Visual C++ runtime preinstalled) to catch a missing `msvcp140.dll`/`vcruntime140*.dll`.

**First release (1.0.0):** pubspec, `deploy/relay.env` and `web/src/site.config.json` already name
1.0.0 but nothing is uploaded, so the first push to `main` after the signing secrets exist builds and
publishes 1.0.0. `announce` then finds nothing to change (no commit, no deploy) and only tags
`desktop-v1.0.0`.

## When something goes wrong

- **Build, signing or notarization failed:** nothing was uploaded (`publish` runs only after both
  platform jobs succeed). `notarize.sh` prints the notary log; the usual cause is nested code
  without hardened runtime or a secure timestamp. Fix it and push to `main` (same version): the
  version is still unpublished, so it builds again. Or **Re-run failed jobs**.
- **"signed by team …, expected W4RF3W4VTZ" / "no Developer ID Application identity of team
  W4RF3W4VTZ":** the `.p12` in `MACOS_CERTIFICATE_P12_BASE64` belongs to another team; export the
  certificate of team `W4RF3W4VTZ` again (Apple, step 3).
- **`publish` failed after uploading one file:** the next run stops with "only the dmg/exe is
  published". Delete it on the VPS (`rm ~/phu/shellx/downloads/desktop/X.Y.Z/<file>`), then
  **Re-run failed jobs** or push again.
- **`announce` failed to push:** the installers are live. Fix the branch rule and push to `main`
  again (the run only announces), or set the relay and website values by hand (see "Triggers")
  and push, which deploys them; tag the released commit by hand if you want the tag.
- **The `deploy` job failed:** `deploy/relay.env` on `main` already names the new version; re-run
  it (**Re-run failed jobs**) or run **Actions → Deploy → Run workflow** on `main`.
- **A broken installer was published:** do not overwrite it. Objects are served with
  `Cache-Control: immutable` for a year and `publish` refuses existing versions. Release
  `X.Y.(Z+1)`.

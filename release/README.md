# Desktop release pipeline

`.github/workflows/release-desktop.yml` builds, signs and publishes the desktop agent (spec §8.5, §14).

| Platform | File | Signing | Public URL |
|---|---|---|---|
| macOS 12+ (universal) | `ShellX-<v>.dmg` | Developer ID, hardened runtime, no App Sandbox, notarized and stapled | `https://download.shellx.pro/desktop/<v>/ShellX-<v>.dmg` |
| Windows 10 1809+ (x64) | `ShellX-Setup-<v>.exe` (Inno Setup, per-user, no UAC, English + Vietnamese) | Azure Artifact Signing (formerly "Trusted Signing") | `https://download.shellx.pro/desktop/<v>/ShellX-Setup-<v>.exe` |

**Triggers**

- Pushing a tag `desktop-vX.Y.Z` runs a real release: build, sign, notarize, upload to R2.
- **Actions → Release desktop → Run workflow** with `dry_run` checked (the default) builds and
  packages only: the macOS app gets an ad-hoc signature, the installer is unsigned, nothing is
  uploaded, and the files are attached to the run as artifacts `macos-dmg` and
  `windows-installer`. An unchecked `dry_run` is accepted only when the workflow runs on a
  `desktop-v*` tag.
- The release version must equal `version:` in `apps/desktop/pubspec.yaml` (the `+build` suffix is
  ignored); otherwise the run stops in the `prepare` job.

**Files**

| File | Purpose |
|---|---|
| `scripts/version.mjs`, `scripts/resolve-version.mjs` | Pick the version and the dry-run flag from the GitHub context |
| `macos/import-certificate.sh` | Import the Developer ID certificate into a temporary keychain |
| `macos/sign-app.sh` | Sign nested code, then the app, with hardened runtime; refuse App Sandbox entitlements |
| `macos/notarize.sh` | `notarytool submit --wait`, staple, `spctl` check |
| `macos/make-dmg.sh` | Compressed dmg with `ShellX.app` and an `/Applications` link |
| `windows/shellx.iss` | Inno Setup script (per-user install, Windows 10 1809+, stops a running agent) |
| `windows/Vietnamese.isl` | Unofficial Vietnamese messages, copied unchanged from `jrsoftware/issrc` tag `is-6_7_1` (`Files/Languages/Unofficial/Vietnamese.isl`); SHA-256 pinned in `tests/inno.test.mjs` |
| `windows/build-installer.ps1` | Find (or install) Inno Setup 6.7.1 and compile `shellx.iss` |
| `tests/*.test.mjs` | `node --test release/tests/*.test.mjs` (the macOS script tests run only on macOS) |

**Why `wrangler r2 object put` for the upload:** it is the tool the relay already uses, it
authenticates with one Cloudflare API token (no separate S3 access key pair, endpoint URL or AWS
CLI configuration), and it sets `Content-Type`, `Content-Disposition` and `Cache-Control` in one
command. Its 300 MiB single-upload limit is far above the installer sizes. `--remote` is
mandatory: without it Wrangler 4 writes to a local simulated bucket and still reports success.

## GitHub secrets

All 13 secrets below must be created as **Environment secrets** of a GitHub Environment named
`release`, restricted to the tag pattern `desktop-v*` (Settings → Environments → **New environment**
→ name `release` → **Deployment branches and tags** → **Selected branches and tags** → add rule
`desktop-v*`; optionally add **Required reviewers** for a manual approval gate before signing runs).
Do **not** add them as repository secrets: `release-desktop.yml`'s `macos`, `windows` and `publish`
jobs declare `environment: release`, so only workflow runs that match the environment's deployment
rule can read them — a run from an arbitrary branch (for example a `workflow_dispatch` dry run) has
no access, even though dry runs need none of these secrets anyway.

Settings → Environments → `release` → **Environment secrets** → **Add secret**.

| Secret | Job | Value |
|---|---|---|
| `MACOS_CERTIFICATE_P12_BASE64` | macos | Base64 of the `.p12` export of the "Developer ID Application" certificate **with its private key** (`base64 -i DeveloperID.p12 \| pbcopy`) |
| `MACOS_CERTIFICATE_PASSWORD` | macos | Password chosen when exporting the `.p12` |
| `APPLE_API_KEY_P8_BASE64` | macos | Base64 of the App Store Connect API key file `AuthKey_<KEYID>.p8` (`base64 -i AuthKey_<KEYID>.p8 \| pbcopy`) |
| `APPLE_API_KEY_ID` | macos | The key ID (10 characters) |
| `APPLE_API_ISSUER_ID` | macos | The issuer ID (UUID) shown above the keys list |
| `AZURE_TENANT_ID` | windows | Directory (tenant) ID of the app registration |
| `AZURE_CLIENT_ID` | windows | Application (client) ID of the app registration |
| `AZURE_CLIENT_SECRET` | windows | Client secret value of the app registration |
| `AZURE_SIGNING_ENDPOINT` | windows | Signing account endpoint for its region, e.g. `https://weu.codesigning.azure.net/` |
| `AZURE_SIGNING_ACCOUNT_NAME` | windows | Artifact Signing account name |
| `AZURE_CERTIFICATE_PROFILE_NAME` | windows | Certificate profile name (Public Trust) |
| `CLOUDFLARE_API_TOKEN` | publish | API token with **Account → Workers R2 Storage → Edit** |
| `CLOUDFLARE_ACCOUNT_ID` | publish | Cloudflare account ID that owns the R2 bucket and the `shellx.pro` zone |

The bucket name (`shellx-downloads`), the public base URL (`https://download.shellx.pro`), Flutter
3.41.7 and Wrangler 4.139.0 are pinned in the workflow's `env:` block. The workflow expects the
names fixed by `apps/desktop`: `ShellX.app` with bundle id `pro.shellx.desktop`, and `ShellX.exe`.

## One-time setup

### 1. Apple (macOS signing and notarization)

1. Enroll in the Apple Developer Program. Only the **Account Holder** can create Developer ID
   certificates.
2. Xcode → Settings → Accounts → Manage Certificates → **+** → **Developer ID Application**
   (or developer.apple.com → Certificates → **+** → Developer ID Application).
3. Keychain Access → My Certificates → right-click "Developer ID Application: …" → **Export** →
   `.p12` with a strong password → store as `MACOS_CERTIFICATE_P12_BASE64` and
   `MACOS_CERTIFICATE_PASSWORD`.
4. App Store Connect → Users and Access → Integrations → App Store Connect API → **Team Keys** →
   **+**, access **Developer** → download `AuthKey_<KEYID>.p8` (downloadable only once) → store as
   `APPLE_API_KEY_P8_BASE64`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`.
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

### 3. Cloudflare R2 and `download.shellx.pro`

1. R2 → **Create bucket** → name `shellx-downloads`.
2. Bucket → Settings → **Custom Domains** → Add → `download.shellx.pro` → Connect. Leave the
   `r2.dev` public URL disabled.
3. My Profile → API Tokens → **Create Token** → Custom token → Permissions: **Account → Workers R2
   Storage → Edit**, Account resources: the ShellX account → `CLOUDFLARE_API_TOKEN`.
4. Account ID (Workers & Pages overview, right column) → `CLOUDFLARE_ACCOUNT_ID`.
5. Check: `curl -s -o /dev/null -w '%{http_code}\n' https://download.shellx.pro/desktop/0.0.0/none`
   prints `404`.

### 4. GitHub

1. Settings → Environments → **New environment** → name `release`, restrict deployment to tags
   matching `desktop-v*` (optionally add required reviewers), then add the 13 secrets above to it
   as Environment secrets (see "GitHub secrets" above).
2. Recommended: Settings → Rules → Rulesets → **New tag ruleset** targeting `desktop-v*`,
   restricting creation and deletion to maintainers.
3. Run one dry run (next section, step 2) to validate the toolchain before the first real release.
4. After the first full CI run on `feat/shellx-v1` → `main` finishes, make the `CI result` check
   required on `main`: Settings → Branches (or Rules → Rulesets) → add a rule for `main` →
   **Require status checks to pass before merging** → select `CI result`.

## Releasing version X.Y.Z

**First release only (v1.0.0):** `web/src/site.config.json` already ships with
`"desktopVersion": "1.0.0"` (see `web/README.md`). If the website is deployed before this
procedure has published `1.0.0` to R2, its download buttons 404. Run this whole procedure for
`1.0.0` — through step 5 (Relay) at least — before the branch containing `web/` is merged to `main`
and deployed by Cloudflare Pages; step 6 below then only has to confirm the version already
matches.

1. Set `version: X.Y.Z+N` in `apps/desktop/pubspec.yaml` (increase `N` every release), merge to
   `main`, wait for CI.
2. **Dry run:** Actions → Release desktop → Run workflow → branch `main`, version `X.Y.Z`,
   `dry_run` checked. Download the `macos-dmg` and `windows-installer` artifacts and smoke-test them
   (macOS: right-click → Open, because the dry-run app is ad-hoc signed; Windows: SmartScreen →
   More info → Run anyway): the agent starts in the tray, you can sign in, pair a phone and open a
   session. Also smoke-test the dry-run installer in **Windows Sandbox** (a clean Windows with no
   Visual C++ runtime preinstalled): Windows Features → turn on "Windows Sandbox", paste the
   installer in, run it, confirm the agent starts — this is what catches a missing
   `msvcp140.dll`/`vcruntime140.dll`/`vcruntime140_1.dll` that a developer machine (which already
   has the runtime installed) would not.
3. **Tag:** `git switch main && git pull && git tag desktop-vX.Y.Z && git push origin desktop-vX.Y.Z`.
4. Wait for the run to finish. Its summary lists both public URLs with SHA-256 hashes. On a clean
   Mac, download the dmg in a browser, drag ShellX to Applications and open it: macOS must show only
   the standard "downloaded from the Internet" prompt. On Windows, the installer's signature must
   show the publisher.
5. **Relay:** in `relay/wrangler.jsonc`, edit the `vars` of the production environment
   (`env.production.vars`), which feed `GET /v1/version`:
   - `LATEST_AGENT_VERSION` → `X.Y.Z`
   - `MAC_URL` → `https://download.shellx.pro/desktop/X.Y.Z/ShellX-X.Y.Z.dmg`
   - `WIN_URL` → `https://download.shellx.pro/desktop/X.Y.Z/ShellX-Setup-X.Y.Z.exe`
   - `MIN_AGENT` / `MIN_MOBILE` → raise only to force older agents / mobile apps to update.

   Deploy the relay to production (see `relay/README.md`), then check that
   `curl -s https://relay.shellx.pro/v1/version` shows `"version":"X.Y.Z"` and both URLs under
   `latest_agent`. Running agents show the update notice within 24 hours.
6. **Website:** set `"desktopVersion": "X.Y.Z"` in `web/src/site.config.json`, run
   `npm ci && CHECK_DOWNLOADS=1 npm run build` in `web/` (the "installer URLs are live" check must
   pass), merge to `main`. Cloudflare Pages deploys it.

Order matters: installers first, then the relay (which tells running agents to update), then the
website. The relay and the website must never link to files that are not on R2 yet.

## When something goes wrong

- **Build, signing or notarization failed:** nothing was uploaded (`publish` runs only after both
  platform jobs succeed). `notarize.sh` prints the notary log; the usual cause is nested code
  without hardened runtime or a secure timestamp. Fix it, then move the tag:
  `git push --delete origin desktop-vX.Y.Z && git tag -f desktop-vX.Y.Z && git push origin desktop-vX.Y.Z`.
- **`publish` failed after uploading one file:** delete it with
  `npx wrangler@4.139.0 r2 object delete shellx-downloads/desktop/X.Y.Z/<file> --remote`, then
  **Re-run failed jobs**.
- **A broken installer was published:** do not overwrite it. Objects are served with
  `Cache-Control: immutable` for a year and `publish` refuses existing versions. Release
  `X.Y.(Z+1)`.

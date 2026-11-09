# ShellX 2026-11 mobile programme: shared contracts and plan index

This file fixes the names that cross plan boundaries, so plans written and executed in different sessions
agree. Every plan listed below MUST use these names exactly. A plan that needs a new cross-plan name adds it
here in the same commit.

Specs:
- S1 `docs/superpowers/specs/2026-11-07-shellx-google-sign-in-design.md` (Google / Apple sign-in)
- S2 `docs/superpowers/specs/2026-11-07-shellx-mobile-terminal-design.md` (real terminal on phones; builds on
  `docs/superpowers/specs/2026-10-28-shellx-mobile-workspaces-design.md` wave 2)
- S3 `docs/superpowers/specs/2026-11-07-shellx-android-app-design.md` (Android app)

The specs are in Vietnamese; identifiers are English. Where a spec marks a choice "để lại cho người làm"
(left to the builder), the plan owning that area makes it and records it in this file if other plans depend
on it.

## 1. Plan index and order

| Id | Plan file (`docs/superpowers/plans/`) | Spec | Depends on |
| --- | --- | --- | --- |
| 1A | `2026-11-07-shellx-signin-1a-relay.md` | S1 | — |
| 1B | `2026-11-07-shellx-signin-1b-desktop.md` | S1, S3 §7.4b | contracts §2–3 (1A merged for live tests) |
| 1C | `2026-11-07-shellx-signin-1c-ios.md` | S1 | contracts §2, §4 (1A merged for live tests) |
| 1D | `2026-11-07-shellx-signin-1d-rollout.md` | S1 §7, §10 | 1A, 1B, 1C, 3F |
| 2A | `2026-11-07-shellx-terminal-2a-protocol.md` | S2 | — |
| 2B | `2026-11-07-shellx-terminal-2b-mac.md` | S2 | 2A |
| 2C | `2026-11-07-shellx-terminal-2c-ios.md` | S2 | 2A (2B for dogfood) |
| 3A | `2026-11-07-shellx-android-3a-scaffold.md` | S3 | — |
| 3B | `2026-11-07-shellx-android-3b-link-kotlin.md` | S3 §7.1 | 3A |
| 3C | `2026-11-07-shellx-android-3c-core.md` | S3 §6.2 | 3B |
| 3D | `2026-11-07-shellx-android-3d-ui-shell.md` | S3 §6.1 | 3C, contracts §5 |
| 3E | `2026-11-07-shellx-android-3e-ui-work.md` | S3 §6.1, §7.3 | 3D |
| 3F | `2026-11-07-shellx-android-3f-relay-fcm.md` | S3 §7.4 | — (ship in the same relay deploy as 1A) |
| 3G | `2026-11-07-shellx-android-3g-terminal.md` | S2, S3 §7.5 | 2A, 2C, 3E |
| 3H | `2026-11-07-shellx-android-3h-release.md` | S3 §5, §8, §10 | 3A–3G, 1A deployed |

Parallel lanes once their dependencies are met: {1A, 2A, 3A, 3F} → {1B, 1C, 2B, 2C, 3B} → {3C} → {3D}
→ {3E} → {3G} → {1D, 3H}.

Every plan runs on its own branch `feat/shellx-<plan-slug>` (for example `feat/shellx-signin-1a-relay`) in
its own worktree, branched from `develop`. Landing follows the memory note `shellx-working-preferences`
(the user's standing directive for `develop`, 2026-10-22: "làm xong push lên develop luôn") together with
CLAUDE.md "CI, review and merge":
- plans without app UI/runtime changes (1A, 2A, 3A, 3B, 3C, 3F, 3H): after the final review, merge into
  `develop` from the main checkout and push `develop`;
- app UI/runtime plans (1B, 1C, 2B, 2C, 3D, 3E, 3G): after the final review, wait for the plan's USER device
  check and the user's merge directive (`merge`, `merge it`, `auto-merge`), then merge and push `develop`;
- plan 1D (a runbook with the user present at every phase) waits for the merge directive at each of its two
  landings, as it says. Never merge to
`main`, never deploy, never upload to a store: those steps are the user's and appear only in 1D and 3H
as commands handed to the user. Publishing a desktop release with `publish-to-vps.sh` happens only in 1D,
after the user's explicit go-ahead at its release gate (memory `shellx-release-pipeline`).

## 2. Relay HTTP API (owner: 1A; consumers: 1B, 1C, 3B, 3C)

All errors use the existing shape `{"error": {"code", "message"}}` (`relay/src/http/errors.ts`). New
`Errors` entries (name → status, code):

| Name | Status | Code |
| --- | --- | --- |
| `switchFromSignedInDevice` | 409 | `switch_from_signed_in_device` |
| `emailInUse` | 409 | `email_in_use` |
| `identityInUse` | 409 | `identity_in_use` |
| `lastGoogleIdentity` | 409 | `last_google_identity` |
| `registrationClosed` | 410 | `registration_closed` |
| `passwordSignInRemoved` | 410 | `password_sign_in_removed` |
| `reauthRequired` | 401 | `reauth_required` |
| `identityNotFound` | 404 | `identity_not_found` |

Routes (all bodies JSON; `device` is today's object `{kind, name, platform, public_key}` from
`relay/src/auth/device.ts`):

| Route | Auth | Body | Success | Errors |
| --- | --- | --- | --- | --- |
| `POST /v1/auth/nonce` | none | `{}` | 201 `{nonce, expires_in}` (43-char base64url, 600) | 429 |
| `POST /v1/auth/google` | none | `{id_token, nonce, device}` | 200 `{user_id, device_id, token, email}` | 401 `invalid_credentials`, 409 `switch_from_signed_in_device`, 400 `invalid_device`, 429 |
| `POST /v1/auth/google/link` | bearer (any kind) | `{id_token, nonce}` | 200 `{user_id, device_id, token, email}` (new token, `auth_method` google; the old token is deleted) | 401 `invalid_credentials`, 409 `email_in_use`, 409 `identity_in_use` |
| `POST /v1/auth/apple` | none | `{identity_token, authorization_code, nonce, device}` (`device.kind` `mobile`, `platform` `ios`) | 200 `{user_id, device_id, token, email}` or 202 `{status: "link_required", link_token, expires_in}` (600) | 401, 400, 429 |
| `POST /v1/auth/apple/link` | none | `{link_token, machine_id, client_key_b64, proof_b64}` | 201 `{pairing_id}` | 401 `invalid_credentials` (bad / expired link token), 404 `machine_not_found`, 429 |
| `POST /v1/auth/apple/link/status` | none | `{link_token, pairing_id}` | 200 `{status: "pending"|"denied"|"expired"}` or `{status: "approved", session: {user_id, device_id, token, email}, machine: {machine_id, name, link_slot}}` | 401, 404 `pairing_not_found` |
| `DELETE /v1/account` | bearer | `{id_token, nonce}` (Google or Apple, `iat` ≤ 300 s), or legacy `{password}` only while the account still has a password and `PASSWORD_LOGIN=on` | 204 | 401 `reauth_required`, 401 `invalid_credentials`, 429 |
| `GET /v1/account/identities` | bearer | — | 200 `{identities: [{identity_id, provider, email, is_private_email, linked_via_device_name, created_at_unix}]}` | 401 |
| `DELETE /v1/account/identities/:identity_id` | bearer | — | 204 | 404 `identity_not_found`, 409 `last_google_identity` |
| `POST /v1/auth/register` | none | any | — | always 410 `registration_closed` (from 1A on) |
| `POST /v1/auth/login`, `POST /v1/auth/password` | as today | as today | as today while `PASSWORD_LOGIN=on` | 410 `password_sign_in_removed` when `PASSWORD_LOGIN=off` |

- `GET /v2/phone-pairings?role=target` entries gain `links_apple_id` (boolean, `true` for a pairing created
  by `POST /v1/auth/apple/link`).
- `provider` values: `google`, `apple` (and `test` in test relays only).
- `tokens.auth_method`: `password` | `google` | `apple` | `test`, default `password` for existing rows.
- Env (all via `deploy/docker-compose.yml` like the APNs variables): `GOOGLE_CLIENT_IDS`
  (comma-separated allowed `aud` values), `APPLE_CLIENT_IDS` (default `com.shellx.prod,com.shellx.dev`),
  `APPLE_TEAM_ID`, `APPLE_SIWA_KEY_ID`, `APPLE_SIWA_KEY_PATH`, `PASSWORD_LOGIN` (`on` default, `off`),
  `TEST_IDP_ISSUER` and `TEST_IDP_JWKS_PATH` (never set in production).
- Scripts (run inside the relay container on the VPS by the user): `npm run password-cutover`
  (`relay/src/scripts/password-cutover.ts`) and `npm run mint-smoke-token`
  (`relay/src/scripts/mint-smoke-token.ts`).
- Apple nonce rule: the phone passes `sha256_hex(nonce)` to Apple; the relay compares the identity token's
  `nonce` claim with `sha256_hex(nonce)`. Google tokens carry the raw `nonce`.

## 3. shellx-core RPC (owner: 1B; consumers: Mac app, Windows app)

New methods, added to `KNOWN_METHODS` in `shellx-core/src/lib.rs`:

| Method | Params | Result |
| --- | --- | --- |
| `auth.google.begin` | `{purpose: "sign_in" | "link"}` | `{flow_id, auth_url}` |
| `auth.google.finish` | `{flow_id}` | `{user_id, device_id, device_public_key_b64, fingerprint, email, auth_method: "google"}` |
| `auth.google.cancel` | `{flow_id}` | `{}` |
| `account.identities.list` | `{}` | `{identities: [...]}` as the relay returns them |
| `account.identities.remove` | `{identity_id}` | `{}` |

- `session.json` gains `auth_method` and `email` (absent in old files means `password` and unknown).
- `auth.login` stays until the cut-over (in-place switch needs an existing password session), but no UI
  calls it after 1B.
- New `CoreError` codes surfaced to the apps: `switch_from_signed_in_device`, `google_cancelled`,
  `google_timeout`, `google_state_mismatch`, `email_in_use`, `identity_in_use`, `last_google_identity`,
  `password_sign_in_removed`.
- Loopback redirect: `http://127.0.0.1:<random port>/oauth2/callback`, bound to 127.0.0.1 only, 300 s
  timeout. Google endpoints `https://accounts.google.com/o/oauth2/v2/auth` and
  `https://oauth2.googleapis.com/token`; scope `openid email profile`; `prompt=select_account`; PKCE S256.
- Desktop OAuth client id and secret are compiled defaults in `shellx-core` config, overridable with
  `SHELLX_GOOGLE_DESKTOP_CLIENT_ID` / `SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET`.

## 4. Swift `ShellXLinkAccount` additions (owner: 1C; consumers: iOS app)

In `shellx-link/Sources/ShellXLinkAccount/`, on `RelayAPI`:

```swift
func nonce() async throws -> String
func signInWithGoogle(idToken: String, nonce: String, deviceName: String, clientKey: Data) async throws -> AccountSignIn
func linkGoogle(idToken: String, nonce: String, token: String) async throws -> AccountSignIn
func signInWithApple(identityToken: String, authorizationCode: String, nonce: String, deviceName: String, clientKey: Data) async throws -> AppleSignInResult
func requestAppleLink(linkToken: String, offer: PairingOffer, clientKey: Data) async throws -> String // pairing id
func appleLinkStatus(linkToken: String, pairingID: String) async throws -> AppleLinkStatus
func deleteAccount(idToken: String, nonce: String, token: String) async throws
```

```swift
public struct AccountSignIn: Equatable, Sendable { public var session: AccountSession; public var email: String }
public enum AppleSignInResult: Equatable, Sendable { case signedIn(AccountSignIn); case linkRequired(linkToken: String, expiresIn: Int) }
public enum AppleLinkStatus: Equatable, Sendable { case pending, denied, expired; case approved(AccountSignIn, machineID: String, name: String, linkSlot: String) }
```

`login(email:password:...)` is removed by 1C's last task only after the cut-over (1D step), not before.

## 5. Kotlin layout (owner: 3A/3B; consumers: 3C–3H)

- `shellx-link/kotlin/`: standalone Gradle build (`settings.gradle.kts`, Gradle wrapper), MIT. Modules
  `link-core` (package `com.shellx.link.core`) and `link-account` (package `com.shellx.link.account`), Kotlin
  JVM, JVM target 17, JUnit 5. Vectors are read from `../../vectors/` and `../../spec/vectors/` relative to
  each module directory.
- `shellx-android/`: Gradle build with `includeBuild("../shellx-link/kotlin")`. Modules `:core` (Kotlin
  JVM, package `com.shellx.core`, JUnit 5) and `:app` (Android application, namespace `com.shellx.app`).
  Application id `com.shellx.prod` (release, label "ShellX") and `com.shellx.dev` (debug, label "ShellX
  Dev"). Versions in `shellx-android/version.properties` (`VERSION_NAME`, `VERSION_CODE`; first
  `VERSION_CODE` is 100).
- Kotlin names mirror §4 in Kotlin style: `RelayApi.nonce()`, `signInWithGoogle(...)`, `deleteAccount(...)`,
  `AccountSignIn`, `AccountSession`. No Apple methods and no `linkGoogle` on Android (Android never holds a
  password session).
- Scripts: `shellx-android/scripts/dev.sh` with `test link|core|app|screenshots|all`, `screenshots record
  <dir>`, `emulator --api <26|36>`, `device [--serial <id>]`, `build-release`; it sets `JAVA_HOME` to
  `/Applications/Android Studio.app/Contents/jbr/Contents/Home` when unset. `release/mobile/android.sh`
  builds the signed AAB. `scripts/shellx/check-android-license.sh` enforces S3 §5.
- Android strings are generated from `shellx-ios/ShellX/Localizable.xcstrings` by
  `shellx-android/scripts/import-strings.py`: the name is the iOS key with `.` → `_` and camelCase →
  snake_case; `%@` → `%N$s`, `%lld` / `%d` → `%N$d`. The output goes to `app/src/main/res/values/strings.xml`
  and `values-vi/strings.xml` (generated, never hand-edited). Android-only strings live in
  `values*/strings_android.xml`. `dev.sh test app` fails when the generated files are stale.
- Parity ledger: `docs/superpowers/ledgers/shellx-android-parity.md`.
- App shell names (owner 3D; 3E and 3G plug into them):
  - `com.shellx.app.ShellXApplication` builds `com.shellx.app.AppComposition` (the composition root);
  - `com.shellx.app.ui.theme.ShellXTheme` (composable) and `ShellXColors`;
  - `com.shellx.app.ui.nav.ShellXNavHost` with routes `launch`, `sign_in`, `first_mac`, `pairing`, `home`,
    `workspace/{machineId}/{workspaceId}`, `agent/{machineId}/{sessionId}`, `pending`, `sessions/{kind}`,
    `machines`, `settings`, `demo`.
- Platform service interfaces live in `:core` (owner 3C) and are implemented in `:app`: `SecretStore`,
  `NetworkMonitor`, `Clock`, `SpeechEngine`, `PushRegistrar`, `UpdateChecker`, `AttachmentReader`.
- Workspace pane slot (owner 3E): `WorkspaceScreen` renders each chip through `PaneContent(pane)`. A shell
  pane shows `ShellPanePlaceholder` until 3G replaces it with `TerminalPane`.
- "Xem thử không cần tài khoản" (S1 §6.6, S3 §6.1): iPhone owner 1C, Android entry points owner 3D,
  demo data owner 3C (`com.shellx.core.demo.DemoScript`, ported from the iPhone demo script: today
  `shellx-ios/ShellX/Debug/DemoScript.swift`; once plan 1C lands it lives at
  `shellx-ios/Packages/ShellXAppCore/Sources/ShellXDemo/FakeMacDemoScript.swift` with the app glue in
  `shellx-ios/ShellX/Demo/DemoScript.swift` — port from whichever exists on `develop`).
- Android account deletion UI: owner 3D. Android FCM client: owner 3E. Relay FCM: owner 3F.

## 6. ShellX Link terminal messages (owner: 2A; consumers: 2B, 2C, 3G)

Features `terminal_view` and `terminal_create` in `welcome.features`. `message.case` names and wire `t`:

| `message.case` | Wire `t` | Fields (2A finalizes types and limits) |
| --- | --- | --- |
| `terminal_view_open` | `terminal.view.open` | `call_id`, `terminal_id`, `cols`, `rows` |
| `terminal_view_open_result` | `terminal.view.open.result` | `call_id`, `outcome` |
| `terminal_view_frame` | `terminal.view.frame` | `terminal_id`, frame envelope (2A) |
| `terminal_view_input` | `terminal.view.input` | `terminal_id`, `units` |
| `terminal_view_resize` | `terminal.view.resize` | `terminal_id`, `cols`, `rows` |
| `terminal_view_resync` | `terminal.view.resync` | `terminal_id` (phone asks for a full snapshot after a gap) |
| `terminal_view_close` | `terminal.view.close` | `terminal_id` |
| `terminal_view_ended` | `terminal.view.ended` | `terminal_id`, `reason` |
| `terminal_create` | `terminal.create` | `call_id`, `workspace_id` |
| `terminal_create_result` | `terminal.create.result` | `call_id`, `outcome`, `terminal_id` (only with `ok`) |

- Input units: `{"k": "text", "text"}`, `{"k": "key", "key", "mods"}`, `{"k": "paste", "text"}`,
  `{"k": "scroll", "lines"}`; key names and modifier names are fixed by 2A in PROTOCOL.md.
- Outcomes reuse the existing open enum (`ok`, `not_found`, `refused`, `failed`, plus `busy` for a second
  open while one is open, if 2A keeps the one-terminal rule host-side).
- Golden vectors: `shellx-link/spec/vectors/terminal.json`, read by Swift (2A) and Kotlin (3G) tests.

## 7. Releases

- Desktop 1.8.0 (Mac + Windows): Google sign-in (1B) and the "phone" wording (S3 §7.4b).
- The first desktop release after 1.8.0 that contains 2B: `terminal_view` / `terminal_create`.
- iPhone: the next build after 1.0.0 (5) carries 1C; a later build carries 2C. Version and build numbers
  follow `release/mobile/README.md`.
- Android: first Play upload is `VERSION_CODE` 100, `VERSION_NAME` equal to the iPhone's marketing version
  at that time.

## 8. Android push payload (owner: 3F; consumer: 3E)

FCM **data-only** messages, so `RemoteMessage.getNotification()` is null and
`FirebaseMessagingService.onMessageReceived` always runs. All `data` values are strings.

| `kind` | `android.priority` | `android.ttl` | `android.collapse_key` | `data` |
| --- | --- | --- | --- | --- |
| `needs_you` | `high` | `86400s` | `request_id` | `{kind: "needs_you", machine_id, request_id, agent, workspace_title}` |
| `resolved` | `normal` | `86400s` | `request_id` | `{kind: "resolved", machine_id, request_id}` |

- `workspace_title` is `""` when the Mac sends none.
- App rules (3E): notification tag = `request_id`, group = `machine_id`; title string `push_title`; text
  `push_needs_you_workspace` (agent, workspace) when the trimmed title is non-empty, else `push_needs_you`
  (agent); `resolved` cancels the notification with that tag; tapping opens the `pending` route.
- Registration: `PUT /v1/devices/me/push-token {token, platform: "android"}` from a device whose sign-in
  platform is `android`; `DELETE /v1/devices/me/push-token` on sign-out.
- FCM keeps at most 4 collapse keys per offline device: a phone offline through more than 4 requests may
  miss some alerts (accepted).

## 9. Kotlin Link API (owner: 3B; consumers: 3C, 3G)

Exact signatures are in plan 3B's Interfaces blocks; these names are fixed:

- Gradle coordinates `com.shellx.link:link-core` and `com.shellx.link:link-account` (consumed by
  `shellx-android` through `includeBuild("../shellx-link/kotlin")`).
- `com.shellx.link.core.LinkSession` (interface; `LinkClient` implements it, 3C fakes it for tests and the
  demo), created by `LinkClient.connect(circuit, key, hostKey, clientVersion, deviceName, timings)`; push
  Flows `changes`, `sessionChanges`, `workspaceChanges`, `chatEntries`; suspend calls `snapshot`, `reply`,
  `sessions`, `chatHistory`, `chatSend`, `uploadAttachment`, `chatInterrupt`, `workspaces`,
  `createWorkspace`, `renameWorkspace`, `closeWorkspace`, `closeAgent`, `closeTerminal`, `close()`; errors
  `LinkClientException.*`, `MessageUploadException`.
- `NoiseStaticKey.generate()` / `fromPrivate(...)`, `PairingOffer.parse(...)` / `make(...)`, the `ShellXLink`
  constants object, `LinkLog.sink`, `inMemoryCircuitPair()` (tests).
- `com.shellx.link.account.RelayApi(baseUrl, okHttpClient, clientVersion)` with `nonce`,
  `signInWithGoogle`, `deleteAccount`, `requestPairing`, `pairingStatus`, `cancelPairing`, `machines` (from
  `/v2/phone-grants`), `mintConnectTicket`, `unpair`, `logout`, `setPushToken`, `unsetPushToken`;
  `PhonePairing.pair`, `LinkConnector.connect`, `PairedMachine`, `RelayApiException`.
- Plan 3G adds the `terminal_view` / `terminal_create` messages and methods to `LinkSession` after plan 2A.

## 10. Additions from plan 1B (desktop)

- New RPC `auth.session {}` → `{user_id, device_id, email | null, auth_method}` (Windows shows the email
  after a restart; the Mac uses it too).
- `config.set` gains optional test overrides `google_auth_url`, `google_token_url`, `google_client_id`,
  `google_client_secret`.
- `SHELLX_GOOGLE_DESKTOP_CLIENT_ID` / `SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET` are read **at build time**
  (`option_env!`), so plan 1D exports them for both desktop release builds; they never go into git.
- Test-only names: CLI method `auth.google.e2e`, fake routes `/fake-google/*`, env
  `SHELLX_FAKE_GOOGLE_EMAIL`.
- Mac wording: menu item key `remote.phonePairing.menu` becomes "Pair Phone…" / "Ghép cặp điện thoại…"
  (eight "iPhone" keys change in total, listed in plan 1B). The iPhone string `pairing.instructions` (plan
  1C) quotes exactly these words.

## 11. Additions from plan 1C (iPhone) and cross-plan rules

- `AppleLinkStatus.approved` carries `machineID`, `name`, `linkSlot` (§4 amended): the relay's approved
  status reply has no grant fields, and a second request could lose the one-time session hand-over.
- iPhone Google client ids come from xcconfig (`SHELLX_GOOGLE_IOS_CLIENT`, Info.plist key
  `ShellXGoogleClientID`); `release/mobile/ios.sh` refuses an App Store build that still holds the
  placeholder. Plan 1D fills the real ids.
- A password session on the iPhone must switch to Google before it can delete the account (the iPhone
  never sends the legacy `{password}` body).
- **Google branding (all apps):** the Google sign-in button follows Google's branding guidelines
  (https://developers.google.com/identity/branding-guidelines) and uses Google's official "G" mark
  downloaded from that page under Google's terms. Never take a Google logo from GPL code (`ios/`,
  `Packages/`, `Sources/`). Plans 1B, 1C and 3D each add the asset as a USER-approved download step. A font
  for the button (Google Sans) is bundled only when its official download carries the SIL OFL 1.1 licence
  (saved next to it); otherwise the platform's system font is used. Never bundle a font whose licence is
  unconfirmed.
- New iPhone strings from 1C are imported to Android by `import-strings.py` (contracts §5); Android-only
  wording goes to `strings_android.xml`.

## 12. Additions from plans 1A (relay) and 3A (Android scaffold)

From 1A:
- Macs see Apple-link requests only with `GET /v2/phone-pairings?role=target&apple_links=1` (old Macs never
  show one without the Apple warning). shellx-core `phones.pending` sends it (1B).
- Approving an Apple-link pairing can answer 409 `identity_in_use` or 410 `pairing_expired` (1B maps both).
- `POST /v1/auth/apple` never answers `switch_from_signed_in_device` and never links by email: an Apple ID
  with no identity yet gets 202 `link_required` whatever account its email matches, with or without a
  password (user decision 2026-11-08; the QR link attaches the Apple ID to the Mac's account). `POST /v1/auth/apple/link` can answer 400 `bad_request`.
- `POST /v1/auth/google/link` 409 `identity_in_use` also means "this account already has another Google
  identity".
- The approved Apple-link status hands the session out **once** (minted then). A lost answer is recovered by
  signing in with Apple again (the Apple ID is already linked).
- Test identity provider tokens: `aud` `shellx-test-idp`, raw `nonce`; helper `relay/scripts/test-idp.ts`.
- Operator interface (1D): `SHELLX_SMOKE_TOKEN`, `npm run -s mint-smoke-token`, `npm run password-cutover`,
  and the relay's startup log events listed in plan 1A.
- In-app deletion path wording on the website matches the phone strings: English "Settings › Account ›
  Delete Account…", Vietnamese "Cài đặt › Tài khoản › Xoá tài khoản…" (1C's strings; Android imports them).
- 1A leaves to 1D: removing `relay/src/scripts/reset-password.ts` after the cut-over, and the `terms.md` /
  homepage copy that still says "create an account" with a password.

From 3A:
- String names strip the iOS key's format suffix; one collision is resolved as `agent_state_running_for`;
  Android overrides live in `strings_android.xml`; iPhone-only keys are listed in `strings-ios-only.txt`.
- `dev.sh` also has `lock`, `clean`, `--headless`, serial sources, fixed AVD names and ports (see 3A).
- Dependencies: a lockfile per module and `scripts/shellx/android-license-allowlist.txt` with a fixed
  procedure for adding entries; test-only licences (EPL, ICU, CDDL) only on test classpaths.
- App shell: `MainActivity`, `LaunchView`, the `ShellXTheme` API and its Material 3 colour mapping (see 3A);
  screenshot tests use Roborazzi; backup is off for the whole app.
- Platform implementations: 3D owns `SecretStore`, `NetworkMonitor`, `Clock`; 3E owns `SpeechEngine`,
  `PushRegistrar`, `UpdateChecker`, `AttachmentReader`.
- `google-services.json` for both app ids is committed (Google treats it as non-secret; the prod copy is
  already in history at `flutter-final`). 1D/3H add a USER step to restrict the Firebase Android API key
  to the two package names and their SHA-1s in Google Cloud Console.
- First `VERSION_CODE` 100 (the Flutter app's last local code was 2).

## 13. Additions from plan 2A (terminal protocol)

Full definitions are in plan 2A (PROTOCOL.md §11 text). Fixed for 2B, 2C, 3G:
- `terminal.view.open.result` outcomes: `ok`, `not_found`, `refused`, `busy`, `failed`. One view per Link
  session; opening the same terminal again restarts the view.
- `terminal.view.ended` reasons: `gone`, `refused`, `failed`, `not_open` (`not_open` answers input,
  resize or resync for a terminal the session is not viewing; input has no `call_id`).
- Input units: `text` (no control characters, ≤ 4 096 bytes per message), `key` (fixed name list plus
  `a`–`z`; modifiers `ctrl`, `alt`, `shift`; no `cmd`), `paste` (≤ 16 384 bytes), `scroll` (±1…100, alternate
  screen only). Size clamped to 20–300 columns, 5–120 rows.
- Frames: `revision` +1 per frame, starting with a snapshot at 1; `part` / `parts` (≤ 256 parts, each within
  65 519 bytes); part 0 carries the head (`kind` snapshot | delta | history, size, `alt`, cursor, 256-colour
  palette, `history`, `scroll`); styles `{id, fg | fg_rgb, bg | bg_rgb, attrs}`; lines `{y, runs}` with
  negative `y` for history; runs `{x?, t, s?, w?}` (no `w`: one cell per Unicode scalar; with `w`: exactly
  one cell of width 1 or 2). One resync per gap, then wait for a snapshot.
- History: a snapshot carries 240 rows; history frames follow up to 4 000 rows or **262 144 bytes**, never
  ahead of a delta; the host pulls frames (at most one unsent frame per view).
- Swift names (ShellXLinkCore): `TerminalInputUnit`, `TerminalKey`, `TerminalModifier`,
  `TerminalInputCheck`, `TerminalFramePart`, `TerminalFrameHead`, `TerminalGridFrame`, `TerminalStyle`,
  `TerminalRun`, `TerminalLine`, `TerminalFrameSplitter`, `TerminalFrameAssembler`, `TerminalScreen`.
  ShellXLinkSession: `TerminalViewSource`, `TerminalView`, `TerminalCreator` (the Mac implements them, 2B)
  and `TerminalViewPush` plus the `LinkClient` view methods (the iPhone uses them, 2C). Kotlin (3G) mirrors
  these names in `com.shellx.link.core`.

## 14. Android core API (owner: 3C; consumers: 3D, 3E, 3G)

Exact signatures are in plan 3C's Interfaces blocks. Most models expose `state: StateFlow<…State>`; the
exceptions keep their Swift names (`PairingModel.step`, `UpdatePrompt.offered`, `EndedDismissalStore.dismissals`,
`AppCoordinator.phase` / `hub`) — consumers use the names in plan 3C.
- Account: `AppCoordinator` (`phase`, `hub`, `launch`, `signInWithGoogle`, `signOut`, `handleUnauthorized`,
  `deleteAccount`). Hub: `MachineHub` (`state: StateFlow<HubState>`, `scope`, lifecycle and network calls,
  workspace / agent / terminal commands, `chatUpdates`).
- Screens: `PairingModel`, `DecisionCenter`, `PendingSheetModel`, `AgentThreadModel` (`close()` returns a
  `Job`), `WorkspaceScreenModel`, `HomeFocus.make`. Stores: `EndedDismissalStore`, `GoneRemovalStore`,
  `ConversationStore`. Voice / push / update: `VoiceService`, `VoiceInputModel`, `MicHold`,
  `PushRegistration`, `PushPayload.parse`, `UpdatePrompt`.
- Platform interfaces (packages as in plan 3C): `SecretStore`, `NetworkMonitor`, `Clock`, `SpeechEngine`,
  `PushRegistrar`, `UpdateChecker`, `AttachmentReader`, plus `IdentityProviding` (Google ID token via
  Credential Manager, implemented by 3D), `KeyValueStore` (synchronous, DataStore-backed through an
  in-memory snapshot, implemented by 3D) and `VoicePermissionChecking` (implemented by 3E).
- Demo: `com.shellx.core.demo.DemoEnvironment` (+ `FakeMac`, `DemoScript`, `DemoRelay`) in main sources (it
  ships in Release); it has no network path and never touches the real stores.

## 15. Android UI split between 3D and 3E

- 3D builds the app shell, sign-in, pairing, first-Mac + "Try without an account", machines, home, session
  lists and `SettingsScreen` with sections in this order: Your Macs, Account (email, Sign out, Delete
  Account…), Appearance, Voice (language picker shown when the mic is set up), **Notifications**, About.
  3D leaves the Notifications section as an empty slot `NotificationsSettingsSection()` (renders nothing).
- 3E fills `NotificationsSettingsSection()` (permission state + the OEM row "Thông báo đến trễ?" of S3
  §7.4c), and builds the workspace screen, agent chat, pending list and sheets, composer, attachments,
  the voice engine, the FCM client and the update prompt.
- 3D implements `SecretStore`, `NetworkMonitor`, `Clock`, `IdentityProviding`, `KeyValueStore`; 3E
  implements `SpeechEngine`, `VoicePermissionChecking`, `PushRegistrar`, `UpdateChecker`,
  `AttachmentReader`. Both register them in `AppComposition` (3D creates it with constructor parameters
  for 3E's implementations, defaulting to no-op stubs until 3E lands).

## 16. Additions from plan 1D (rollout)

- All OAuth clients live in the Google Cloud project `shellxpro`: iOS × 2 (`com.shellx.prod`, `com.shellx.dev`),
  Android × 3 (`com.shellx.dev` + debug SHA-1; `com.shellx.prod` + upload-key SHA-1; `com.shellx.prod` +
  Play App Signing SHA-1), Web × 1 (Android's `serverClientId`), Desktop × 1.
- The client ids (not secrets) are recorded in `docs/superpowers/ledgers/shellx-signin-rollout.md`, the
  source for 1C's xcconfigs and 3D/3H's Android config. The Desktop client secret lives only in
  `~/.shellx-release/google-desktop-oauth.env`, read by `scripts/shellx/release/google-desktop-client.sh`
  (two guard functions); both desktop release builds refuse to build without it.
- Apple: `com.shellx.dev` is grouped under `com.shellx.prod` for Sign in with Apple, with one SIWA key on the
  relay.
- Android Web client id: `shellx-android/app/src/main/res/values/google_oauth.xml` string
  `google_web_client_id` (a placeholder until 1D fills it from the ledger); `release/mobile/android.sh` (3H)
  refuses a release AAB that still holds the placeholder.
- After the cut-over `/v1/auth/register` keeps answering `registration_closed`. 1B's password code in
  shellx-core stays (the relay refuses passwords anyway); removing it is a follow-up, not part of this
  programme.

## 17. Additions from plan 2B (Mac terminal host)

- Dogfood tag for the Mac build: `terminal-2b-mac` (2C and 3G live checks use it).
- Sizing participant name for a Link viewer: `mobile:shellx-link-<uuid>`.
- `terminal.view.open.result` answers `failed` for a terminal the Mac lists but cannot view.
- The first snapshot may wait up to 500 ms for the phone's size before it is sent.
- Frames can be **wider than 300 columns** (and taller than 120 rows) while the Mac's window owns the size:
  the 20–300 / 5–120 clamp applies only to the size a phone requests. Phone renderers (2C, 3G) must handle
  any width the head reports (fit-to-width scaling).
- 2A's `openView(terminalId:cols:rows:)` carries **no** device name (adding one is a possible later change;
  3G mirrors 2A). PROTOCOL §11.3 as amended by the cross-review: frames may be up to 1 000 columns / rows each
  way while the Mac owns the size.
- Paste limit on the phones: at most 262 144 UTF-8 bytes per paste (16 messages of 16 384 bytes), because the
  host keeps at most 64 queued input messages; a larger paste is refused on the phone with the notice
  `terminal.paste.tooLarge` (2C `TerminalInputBatcher.maxPasteBytes` / `pasteFits`; 3G mirrors it).
- Latency criteria 3–5 are measured against a **Release** tagged Mac build
  (`./scripts/reload.sh --tag terminal-2b-mac --release`), pairing by QR.

## 18. Additions from plan 2C (iPhone terminal) — the design 3G mirrors

Exact names are in plan 2C's Interfaces blocks: `TerminalPane` (SwiftUI host), `TerminalSurfaceView`
(UIScrollView + `UITextInput`), `TerminalCanvasView` (Core Text), `TerminalViewModel` (rules R1–R12: one view
at a time, every outgoing message through one FIFO outbox), `TerminalTyping` (marked-text handling), the
hub's terminal calls `TerminalLink` / `TerminalHubEvent` / `TerminalOpenResult`, the `WorkspaceScreenModel`
additions, the "View as Terminal" / "View as Chat" menu items, three latency metrics, the demo fixtures and
the `FakeMac` terminal API, and 20 new string keys incl. `terminal.paste.tooLarge` (Android imports them).
Plan 3G removes `workspace.shell.placeholder` from the iPhone catalog when it lands; older Macs get
`terminal.needsUpdate`.

Behaviour Android (3G) mirrors:
- Rendering: every row's layout is cached; cells are placed by column so fallback fonts (CJK, emoji) never
  shift later cells; any grid width is scaled to fit the pane; pinch zooms from that scale up to 2.0; fixed
  monospace font at 12 pt (SF Mono on iPhone; Android picks its system monospace or a bundled OFL font).
- Typing: the input field's document is only the marked / composing text. Committed text is sent; text
  still being composed (Telex / VNI) stays on the phone and Backspace edits it. Return is sent as the `enter`
  key.
- Key bar: esc, tab, ctrl (latched for the next key), ←, ↑, ↓, →, and a hide-keyboard key.
- Hardware keys map to `TerminalKey` names; paste comes from the long-press menu (and ⌘V on the iPhone; on
  Android Ctrl+Shift+V pastes and Ctrl+V sends ctrl-v, §21).
- On the alternate screen a vertical pan becomes `scroll` units; on the main screen it scrolls the local
  scrollback.
- Showing or hiding the soft keyboard resizes the terminal (one snapshot plus the history refill each time;
  accepted cost, debounced).

## 19. Additions from plan 3H (Android release)

- `release/mobile/android.sh` commands and outputs are defined in plan 3H (build, checks, `--mark-uploaded`
  after the user's internal-testing upload). Signing reads only `SHELLX_ANDROID_KEY_PROPERTIES` (default
  `~/.shellx-release/key.properties`); passwords are never printed.
- Release checks include: placeholder or ledger-mismatched `google_web_client_id` refused (§16); permission
  allowlist and Play-rule data files; a list of debug-only names that must never ship (the demo is allowed);
  no analytics, ads or crash-reporting SDK; no cleartext traffic; no `AD_ID` permission; 16 KB alignment for
  any `.so`; targetSdk at least the Play requirement.
- Store-asset file names and the "where each Data safety fact comes from" table are in plan 3H.
- Open for the user at Play Console time (non-blocking): whether to declare the reported app version and
  the system speech recognizer's audio in Data safety, and whether the demo's sample data is translated
  for English screenshots.

## 20. Additions from plan 3E (Android UI work)

- Pane slot (3G plugs in here): `PaneContent(pane, shown, agent, shell = { _, _ -> ShellPanePlaceholder() })`;
  `shown` is true only for the page the pager settled on; `ShellPanePlaceholder(modifier)`;
  `WorkspaceScreen(…, pagingLocked, pane = { pane, shown -> … })`; `PaneChips(…, trailing = {})` hosts the ＋
  chip; `WorkspaceMenuItem.items(canCloseTab)`; `WorkspaceScreenActions.make(…)`. 3G passes
  `shell = { pane, shown -> TerminalPane(…) }` from `WorkspaceView`.
- Route `pending` takes optional arguments: `pending?machineId=…&workspaceId=…`.
- Shared names 3E expects from 3D (3E's Task 0 maps them if 3D named them differently): the signed-in
  scope, `AppComposition`, `ShellXNavHost`, `NotificationsSettingsSection()`; and names 3E creates if 3D
  left them out: `PlatformServices`, `SignedInWork`, `WorkRoutes`, `LocalVoice` / `VoiceEnvironment`,
  `LocalAttachmentReader`, `PushHost`.
- 3E builds each account's `VoiceService` (it needs a capability probe beyond the two contract interfaces).
- Push: channel id `needs_you`; notification ids 1 and 2; tap action `com.shellx.app.action.OPEN_PENDING`;
  settings key `shellx.notifications.asked`; pushes from a Mac the phone no longer has are dropped; one group
  summary per Mac.
- Update prompt: Google Play's own flexible-update dialog plus a "Restart" snackbar when downloaded.
- Settings › Voice belongs to 3D (§15).

## 21. Additions from plan 3G (Android terminal)

- Kotlin names in `com.shellx.link.core` (terminal codec, assembler, screen — no frame splitter on the phone),
  `:core` (`TerminalViewModel` mirroring 2C's R1–R12, typing, batcher incl. `maxPasteBytes` / `pasteFits`,
  geometry, zoom, colours) and `:app` (`TerminalPane` and its custom `View`) are listed in plan 3G.
- `LinkSession`'s terminal members get default implementations, so fakes written before 3G still compile.
- Soft keyboard rule: `EditorInfo` = `TYPE_CLASS_TEXT | TYPE_TEXT_FLAG_NO_SUGGESTIONS |
  TYPE_TEXT_FLAG_MULTI_LINE` with no extract UI, no fullscreen, no Enter action and no personalised learning;
  never `TYPE_NULL` or password types (they break Telex). The `InputConnection` keeps only the composing text;
  committed text is sent; each delete call is one Backspace; a multi-line commit goes as a paste.
- Hardware keys: Ctrl+V sends ctrl-v to the shell; Ctrl+Shift+V pastes.
- Android-only strings (`strings_android.xml`): `terminal_paste` and three key-bar labels.
- The terminal view runs while the screen is STARTED; a rotation reopens the view.
- Parity-ledger rows A-g1 to A-g5.

## 22. Additions from plan 3A (Tasks 6–11, landed 7b2c58fdd6)

- SDK pins: `compileSdk = targetSdk = 36`. The Compose BOM stays on a release whose AARs need compileSdk ≤ 36
  (2026.06.01, Compose 1.11.x) until the user installs `platforms/android-37` and this file allows compileSdk 37
  with targetSdk 36.
- `shellx-android/gradle.properties` sets `android.builder.sdkDownload=false` (Gradle never downloads SDK
  packages); `check-android-license.sh` refuses the build without it.
- Robolectric runs `:app` JVM tests on SDK 35 (`app/src/test/resources/robolectric.properties`) because SDK 36
  needs Java 21 and Gradle runs on JDK 17. A test that needs another SDK uses `@Config(sdk = …)` ≤ 35.
- `:app:testReleaseUnitTest` exists only because `app/build.gradle.kts` enables host tests for release (AGP 9 turns
  them off); later plans keep that block.
- Dependency locking is STRICT in every module; core library desugaring is refused; each Android lockfile must
  name both the debug and the release runtime classpaths. Repository blocks hold only `google()` and
  `mavenCentral()` (`gradlePluginPortal()` only in `pluginManagement`).
- `dev.sh`: `test app` runs both variants with `--continue`; `emulator` prints only the serial on stdout;
  `device` / `emulator` refuse an APK whose package is not `com.shellx.dev`; ShellX emulators are recognised by
  AVD name, and `clean` waits for an emulator to exit before deleting its AVD.
- Strings: the Apple-link keys, `appleLink.title`, `settings.account.delete.switchFirst` and the
  `settings.account.switchToGoogle*` keys are iPhone-only (`strings-ios-only.txt`). Plural forms Android ignores
  (en `zero`, vi `one`) are refused.
- Versions pinned: AGP 9.5.1, Kotlin 2.4.21, Gradle 9.9.0, Compose BOM 2026.06.01, JUnit 5.14.4, JUnit 4.13.2,
  Robolectric 4.17, Roborazzi 1.78.0, activity-compose 1.13.0, google-services 4.5.0, API 36.
- Still the user's: Task 10 (Firebase `google-services.json` for both app ids) and the phone dogfood.

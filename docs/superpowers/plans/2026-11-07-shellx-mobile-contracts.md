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
  Application id `com.shellx.prod` in both build types (release label "ShellX", debug label "ShellX
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
- `google-services.json` for `com.shellx.prod` is committed at `shellx-android/app/google-services.json`
  (Google treats it as non-secret). 1D/3H add a USER step to restrict the Firebase Android API key
  to `com.shellx.prod` and its SHA-1s in Google Cloud Console.
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

- All OAuth clients live in the Google Cloud project `shellxpro`: iOS × 1 (`com.shellx.prod`),
  Android `com.shellx.prod` with the debug SHA-1 of the Mac that builds debug, the upload-key SHA-1 and the
  Play App Signing SHA-1, Web × 1 (Android's `serverClientId`), Desktop × 1.
- The client ids (not secrets) are recorded in `docs/superpowers/ledgers/shellx-signin-rollout.md`, the
  source for 1C's xcconfigs and 3D/3H's Android config. The Desktop client secret lives only in
  `~/.shellx-release/google-desktop-oauth.env`, read by `scripts/shellx/release/google-desktop-client.sh`
  (two guard functions); both desktop release builds refuse to build without it.
- Apple: Sign in with Apple uses the single app id `com.shellx.prod`, with one SIWA key on the relay.
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
Plan 3G removed `workspace.shell.placeholder` from the iPhone catalog (landed 2026-11-10, §28); older Macs get
`terminal.needsUpdate` / `terminal_needs_update`.

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
  `LocalAttachmentReader`, `PushHost`. As landed: 3D's environment class is `AppEnvironment`; `PlatformServices`
  is 3E's and sits beside it (§26, §27).
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
- Parity-ledger rows A-g1 to A-g5 are rows **A-31 to A-35** of `docs/superpowers/ledgers/shellx-android-parity.md`;
  **A-36** (landscape), **A-37** (history size cap) and **A-38** (the word the keyboard sees) were added before landing (§28).

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
  `device` installs only a debuggable `com.shellx.prod` APK and refuses a release build on a phone, `emulator`
  accepts any `com.shellx.prod` APK; ShellX emulators are recognised by
  AVD name, and `clean` waits for an emulator to exit before deleting its AVD.
- Strings: the Apple-link keys, `appleLink.title`, `settings.account.delete.switchFirst` and the
  `settings.account.switchToGoogle*` keys are iPhone-only (`strings-ios-only.txt`). Plural forms Android ignores
  (en `zero`, vi `one`) are refused.
- Versions pinned: AGP 9.5.1, Kotlin 2.4.21, Gradle 9.9.0, Compose BOM 2026.06.01, JUnit 5.14.4, JUnit 4.13.2,
  Robolectric 4.17, Roborazzi 1.78.0, activity-compose 1.13.0, google-services 4.5.0, API 36.
- Firebase: `google-services.json` for `com.shellx.prod` is committed (see §12); only the phone dogfood is still the user's.
- User decision 2026-11-09: no `com.shellx.dev` anywhere; debug builds on Android and iPhone use `com.shellx.prod`.

## 23. Additions from plan 2C at landing (34d42258b9), for 3G

- **Pane sizing.** The page of the terminal shown always holds the terminal surface, also under its loading,
  offline, unavailable and old-Mac cards; the surface's size is the phone grid every open needs (R1, R11). A pane
  that shows a message *instead of* the surface before the first snapshot never opens.
- **Who takes input.** `TerminalViewModel.acceptsInput`: true while `.live`, and while `.connecting` once a screen
  came and a view open is in flight (resume, reconnect, `not_open` reopen) — input then queues behind the open
  (R10) and the keyboard and key bar stay. False in waits with no view in flight (the 1 s failed-open retry, busy
  gaps, `notSent`, offline) and under every card; the surface resigns the keyboard then.
- **Surface owns its terminal.** Each surface knows its pane's `terminalId` and drops input, keys, paste and scroll
  when it is not the terminal shown (base spec §4).
- **Typing settles the screen.** Typing in or focusing a terminal settles the workspace screen, so an agent that
  starts waiting never moves the selection away from it (＋ and the successor after a close still move it).
- **＋ chip.** Dimmed while a create is in flight; a pick made meanwhile cancels the pending `expect`.
- **Budgets.** A lost session restores the open budgets (busy ×5, one failed retry); a `not_open` reopen after
  `.opened` has its own budget. `terminalFirstScreen` restarts on the open that actually produces the screen (not
  counting time offline or in the background).

## 24. Additions from plan 3B (landed 91bc8626be)

- Built names beyond §9: result types `PendingChange`, `SessionChange`, `WorkspaceChange`, `ChatPush`,
  `PendingSnapshot`, `SessionList`, `WorkspaceList`, `ChatHistoryPage`, `WorkspaceCreated`, `ChatAttachment`,
  `LinkTimings`; exceptions `LinkClientException.{ProtocolMismatch, Rejected, SessionClosed, TimedOut, Remote,
  UnexpectedAnswer}`, `NoiseException.UntrustedPeer`, `RelayException.*`, `PairingOfferException.*`,
  `RelayApiException.{Http(status, code), BadResponse, SlotMismatch, NotConnectTicket}`,
  `PhonePairingException.{Denied, Expired}`.
- `com.shellx.link.account`: `RelayApi(baseUrl, okHttpClient, clientVersion)` throws on construction
  (`RelayException.InsecureTransport` for plain http to a non-loopback host, `ProtocolViolation` for a bad URL);
  `RelayApi.relaySockets`; `PhonePairing.pair(offerUri, clientKey, api, token, pollInterval = 2.seconds,
  timeout = PairingOffer.LIFETIME, onRequested = {})` (cancelling it withdraws the pairing); `PairedMachine(machineId,
  name, linkSlot, hostKey)`, `PairedMachineListing`, `PhonePairingStatus`, `AccountSession`, `AccountSignIn`,
  `MintedTicket`; `LinkConnector.connect(machine, key, api, token, clientVersion, deviceName, sockets =
  api.relaySockets)` (no `timings`: for custom timings call `mintConnectTicket` → `RelayClientConnector.connect` →
  `LinkClient.connect(…, timings)`); `OkHttpRelaySockets(okHttpClient)`.
- Consumer rules: `LinkLog.sink` is called from any thread (thread-safe); `RelayApi` inherits the caller's OkHttp
  interceptors — never add a logging interceptor (bearer tokens); `clientKey` is the phone's Noise static **public**
  key; `chatSend(id, text, emptyList())` is ambiguous — name `attachments =` or `uploading =`; every type holding user
  content or secrets prints `<redacted>` in `toString()`; attachment copy + SHA-256 run on `Dispatchers.Default`,
  the handshake and per-frame encryption on the caller's dispatcher.
- Failure mapping for 3C's `LinkFailure`: `Http(401, …)` signed out; `Http(_, "not_granted" | "machine_not_found")`
  grant revoked; `NoiseException.UntrustedPeer` / `RelayApiException.SlotMismatch` host key changed;
  `LinkClientException.ProtocolMismatch` needs an update; `IOException`, `RelayException.*`, `SessionClosed`,
  `TimedOut` offline. Tests run with `-ea`: assert exception type, never identity.
- Pins and gaps: OkHttp 5.4.0 until compileSdk 37; `RelayTransportPolicy.isLoopback` takes only canonical decimal IPv4
  octets (parity difference from Swift); the relay socket's incoming queue is unbounded — 3G bounds it before terminal
  streams; the live-relay test `RelayIntegrationTest` needs `CMUX_RELAY_BIN` and has not run yet; R8 has not yet seen
  link-account / BouncyCastle (3C reruns `dev.sh build-release` once `:app` uses them).

## 25. Additions from plan 3C (landed with the 3C merge on 2026-11-09)

Platform interfaces (packages as built; `:app` implements them):
- `com.shellx.core.account.SecretStore` — synchronous `read(item): ByteArray?`, `write(data, item)`, `delete(item)`;
  `SecretItem { SESSION, PHONE_KEY, MACHINES }`; `SecretStoreException.{Unavailable, Failed}`; an undecryptable item
  (lost Keystore key) reads as absent. `AccountVault` calls it on its `io` dispatcher.
- `com.shellx.core.link.NetworkMonitor` (`paths: Flow<NetworkPath>`, `NetworkPath(status, interfaces, gateways)`).
- `com.shellx.core.platform.Clock` (`nowMs()`, `monotonic: TimeSource.WithComparableMarks` — must count deep sleep).
- `com.shellx.core.platform.KeyValueStore` — synchronous `getString`, `putString(key, null = remove)`,
  `getBoolean` (false when absent), `putBoolean`, `remove`; one key space; **`suspend fun flush()`** (default no-op,
  waits until earlier writes are on disk; sign-out and deletion call it after the `shellx.localWipePending` marker
  and before `vault.wipe()`; 3D's DataStore store overrides it); `MemoryKeyValueStore`.
- `com.shellx.core.account.IdentityProviding` — `googleIdToken(nonce): String`;
  `IdentityProviderException.{Cancelled, NotConfigured, Failed}`; `UnavailableIdentityProvider`. Must not hold an
  Activity (sign-in and deletion outlive their screen).
- `com.shellx.core.voice.SpeechEngine` — `start(run, language, contextualStrings): ReceiveChannel<String>`,
  `finish(run): String`, `cancel(run)` (idempotent); `finish`/`cancel` give the mic back, also when cancelled, and
  never throw; bound `finish` with `SpeechTimeouts` (`STANDARD_FINAL_RESULT` 1.5 s, `ON_DEVICE_FINALIZE` 2 s). One
  `SpeechRunSlot` is shared by every engine that uses the mic; `SpeechRunSlot.cancel(run)` refuses every later claim of
  that run, also when it held the mic; `FallbackTranscriber` never falls back or calls `primaryFailed` for a cancelled
  run. `com.shellx.core.voice.VoicePermissionChecking` (`needsPrompt()`, `microphone()`, `speech()`).
- `com.shellx.core.push.PushRegistrar` (`currentToken(): String?`; `PushRegistration` owns the signed-out guard),
  `com.shellx.core.update.UpdateChecker` (`check(): AvailableUpdate?`, `startUpdate(update)`, `AvailableUpdate(versionCode)`),
  `com.shellx.core.composer.AttachmentReader` (`read(pick, taken): OutgoingAttachment`, `AttachmentPick(uri, kind)`,
  `AttachmentReadException.{TooLarge, Unreadable}(name)`; rules in `AttachmentChecks`).

Core objects the UI builds:
- `AppCoordinator(vault, relay, identity, deviceName, wipers, pendingWipeSettings, scope, makeHub)` — `phase`, `hub`
  (null during sign-out, deletion and a 401 while `phase` is still `SignedIn`; never show "signed out" on a null hub
  alone); `launch`, `protectedDataBecameAvailable`, `signInWithGoogle`, `signOut`, `handleUnauthorized`,
  `deleteAccount` are detached in its scope; a repeat call while one runs joins it (`DetachedRun`); no busy flow —
  3D keeps progress state in a ViewModel.
- `MachineHub(vault, relay, connector, latency, settings, scope, clock, sleep = delay, onUnauthorized)` — `scope`,
  `state: StateFlow<HubState>`, `appDidBecomeActive()` (also probes each online session and replaces a silent one —
  the deep-sleep rule), `appDidEnterBackground()` (start it UNDISPATCHED on ON_STOP; teardown completes even if
  cancelled), `backgroundTimeExpired()`, `networkChanged()`, `refreshGrants()`.
- `PairingModel(hub, relay, vault, scope)`, `PairingInbox`, `PairingScanFilter`, `SheetPresence`;
  `DecisionCenter(sender, latency, scope, clock, sleep)`, `PendingSheetModel(key, hub, center)`;
  `AgentThreadModel(ref, hub, store, scope, sleep)` (`close()`/`save()` return `Job`),
  `WorkspaceScreenModel(ref, hub, sleep)`, `HomeFocus.make(...)`; `EndedDismissalStore`, `GoneRemovalStore`,
  `ConversationStore(directory, io, clock, maxThreads = 100)` (one per directory), `ChatCopySweeper(hub, store).run()`.
- Voice: `VoiceService(engine, permissions, cache, latency, settings, scope, timeSource, preferredLanguages,
  contextualStrings)` with `makeModel()`, `cancelAll()` (run on ON_STOP), `primaryFellBack()`; pass a live supervised
  scope (`hub.scope`): when it ends, a listening mic is given back and later `cancel()`/`cancelAll()` never throw.
- `PushPayload.parse(data)`, `UpdatePrompt(installedVersionCode, checker)`; `ShellXEndpoints.of(debugBuild,
  override).apiBase`; `RelayClientFactory.make(apiBase, appVersion, okHttp)` / `makeConnector(…)` (throw on a bad base —
  build them in a `try`); `CoreLog.sink`.
- Demo: `com.shellx.core.demo.DemoEnvironment(scope, clock, historyDirectory, io, approvalDelay = 2.seconds,
  runsScript = true, sleep)` — members `vault`, `settings`, `first`, `second`, `relay`, `history`, `latency`,
  `coordinator`, `script`; `prepare()`, `secondPairingCode()`, `exit()`; with `FakeMac`, `FakeMacFleet`, `DemoRelay`,
  `DemoSecretStore`, `DemoScript`.
- Settings keys (the iPhone's): `shellx.defaultMachineID`, `shellx.localWipePending`, `shellx.dismissedEnded`,
  `shellx.removedGone`, `shellx.voice.language`.

For later plans:
- 3D: rerun `dev.sh build-release` once `:app` uses `:core`/link classes (R8 removed them all so far); run 3B's
  `RelayIntegrationTest` with `CMUX_RELAY_BIN` before the first live dogfood.
- 3E: HEIC/HEIF picks are converted to JPEG like the iPhone (default ruling 2026-11-09; the user may change it).
- 3G: Swift `WorkspaceScreenModel` gained `settle()` (bf4ec493ca) and the create-in-flight API (e816cef88f) after 3G
  was written — 3G Task 11 adds both and ports 37 tests (incl. `typingIntoTheChipShownKeepsItWhenAnAgentAsks`); demo
  terminal fixtures and the hub's terminal calls are 3G's; `MachineHub.withLink`, `workspaceCommand`,
  `WorkspaceScreenModel.Absence`/`absence(machine)` are `internal` hooks; the fake Mac never answers `too_large`.
- iPhone follow-up: `SpeechRunSlot.swift:78-90` has the gap Android fixed in 77c032a0a1 (a cancelled run that held
  the mic can be claimed again by the fallback after a quick tap).

## 26. Additions from plan 3D (landed with the 3D merge on 2026-11-10)

Composition (`com.shellx.app`):
- `AppComposition(environment: AppEnvironment, appScope, speechEngine = NoSpeechEngine, voicePermissions = NoVoicePermissions,
  pushRegistrar = NoPushRegistrar, updateChecker: UpdateChecker? = null, attachmentReader = NoAttachmentReader,
  makeVoice: ((MachineHub, LatencyLog, KeyValueStore, Clock) -> VoiceService)? = null,
  relays: (AccountVault) -> RelayBundle = { RelayBundle.relay(environment, it) },
  demoEnvironment: ((CoroutineScope) -> DemoEnvironment)? = null)`. 3E passes its five pieces by type and `makeVoice = platform::makeVoice`.
- Members: `real: AccountGraph`; `demo: DemoSession` (not a graph: `demo.graph: StateFlow<AccountGraph?>`, `start()`, `exit()`);
  `active: StateFlow<AccountGraph>` (`demo.graph ?: real`); `root: StateFlow<String>`, `inbox`, `appearance`, `lifecycle`,
  `takeLink()`; `vault`, `latency`, `settings`, `clock`, `push`, `updatePrompt` (release builds with a checker only), `appScope`,
  `environment`. Companion `AppComposition.makeScope(hub, relay, vault, history, latency, launch, settings, clock, voice)`.
- `AccountGraph`: `coordinator`, `relay`, `vault`, `settings`, `scopes: SignedInScopes` (`current: StateFlow<SignedInScope?>`),
  `launch`, `push?`, `updatePrompt?`, `isDemo`.
- `SignedInScope(hub, decisions, pairing, history, launch, endedDismissals, goneRemovals, clock, latency, voice: VoiceService? = null,
  sheets = SheetPresence())`; `listNotice`, `chatCopies`, `agentThread(ref)`, `homeShown()`, `workspacesListed()`.
  `start()` runs the chat-copy sweeper and `decisions.sync(hub.pendingItems)` in `hub.scope` — nothing else may sync again.
- `ShellXApplication.composition: StateFlow<AppComposition?>` and `awaitComposition()` (built after the settings load).
  "3D's ON_START hook" is `AppLifecycle.onStart()`; `AppLifecycle` sends `appDidEnterBackground` UNDISPATCHED.
- `AppEnvironment` is the shell's environment class (not `PlatformServices`).

Navigation (`com.shellx.app.ui.nav`):
- `Routes`: `LAUNCH`, `SIGN_IN`, `FIRST_MAC`, `PAIRING`, `HOME`, `DEMO`, `MACHINES`, `SETTINGS`,
  `SESSIONS = "sessions/{kind}?machineId={machineId}"`, `SESSIONS_ARGUMENTS`, `SIGNED_IN_ROOTS`, `sessions(kind, machineId)`.
  `SessionListKind { ENDED, OTHER }` (`wire` `ended` / `other`). Pairing is a full-screen route, not a sheet.
- `ShellXNavigator`: `openWorkspace`, `openAgent`, `openPending(only)`, `openSessions(kind, machineId)`, `openMachines`,
  `openSettings`, `openPairing`, `showPairing`, `back()`. **Every screen leaves with `navigator::back`, never `nav.popBackStack()`**
  (`NavControllerNavigator.back()` pops only a RESUMED top entry and never the root). Screens take the navigator from
  `rememberShellXNavigator(nav, scope)` (internal `NavigatorRelay`: work that outlives a recreation opens its page in the new window).
- `ShellXNavHost(composition, nav, modifier)`. `RootSync(nav, root)` compares `root` with the stack's real bottom entry
  (internal `bottomRoute(nav)`) on every back-stack change; the `first_mac` / `home` swap waits while a page sits above the root.
- `SignedInFrame(composition, nav, root, content)` is where 3E's `SignedInWork` goes (`content` is movable, so the NavHost survives).
- `MainActivity` delivers a link only when `savedInstanceState == null` and the launch is not from history (`launchedFromHistory`).

Shared UI (`com.shellx.app.ui.*`), in the shapes 3E needed:
- Theme: `StatusTone` (`.color()`), `AgentStateStyle(text, shortText, tone)` (data class; `of(row, res)`, `elapsedText`),
  `MachineStateStyle`, `StatusDot`, `AppLanguage`, `AppAppearance` (settings key `shellx.appearance`), `ShellXAppTheme`.
- Components: `PrimaryButton`, `SecondaryButton`, `Modifier.waitingBorder(isActive, cornerRadius)`, `WaitingBorder.isActive`,
  `ActionRow` (`modifier` is the semantics node), `RowAction` / `RowActionKind` (`menuAction(run)`, `swipeAction(run)`), `RowActions`,
  `ConfirmDialog` (confirms once), `MessageDialog`, `SectionTitle`, `isLargeText()` (fontScale >= 1.3), `rememberNowMs`, `HomeTicks`,
  `Modifier.shellXCard(shape, outline)`.
- `com.shellx.app.ui.workspaces`: `ListNotice` (`show`, `Notice`, `DURATION` 4 s), `NoticeCapsule`, `WorkspaceFeedback`,
  `WorkspaceAlert`, `WorkspaceCommand`, `WorkspaceAlertDialog`, `AgentCloseConfirmation`, `WorkspaceRenameSheet`, `FocusRowView`,
  `FocusKind`; `WorkspaceListActions.canClose`, `closeAgent(ref, hub, alert): Deferred<WorkspaceFeedback>?`, `canCloseTab`,
  `closeTab(machineId, workspaceId, terminalId, hub, alert): Deferred<WorkspaceFeedback>?` (both return null while a close of the
  same agent or tab runs), `make(...)`.
- Settings: `SettingsSection(title: String?, footer: String? = null) { }`, `settingsRowColors()`, `SettingsDivider()`,
  `NotificationsSettingsSection()` (3E fills it), `DeleteAccountDialog(flow, onDismiss, scope)`, `DeleteAccountCard(..., spinner)`.

Platform:
- Keystore alias `shellx.secrets.v1`; secrets in `noBackupFilesDir/secrets/<account>.bin` (`0x01` ‖ IV12 ‖ GCM, AAD
  `shellx-secret/1/<account>`) with a `<account>.failures` counter beside it (ledger A-19: permanent errors read as absent; a
  possibly-transient error keeps the file, and API < 33 errors count as lost after 3 starts). Settings in
  `noBackupFilesDir/settings.preferences_pb`; history in `noBackupFilesDir/ShellX` (demo: `ShellXDemo`).
- Settings keys `shellx.appearance`, `shellx.legacyFlutterCleaned`. Gradle property `shellxApiBase` -> `BuildConfig.SHELLX_API_BASE`
  (debug only; debug builds allow cleartext to loopback; release keeps the default of none, and `dev.sh build-release` checks it).
- `ActivityTracker` is a class; the app instance is `ActivityTracker.shared`; it holds only the resumed activity and
  `awaitResumed()` replaces `current()`. `CredentialManagerIdentity` waits for it up to `RESUME_WAIT` (5 min), then `Cancelled`.
- `dev.sh check-release-permissions`: a release refuses `USE_BIOMETRIC` and `USE_FINGERPRINT`.
- Web client id placeholder is exactly `0-shellx-placeholder.apps.googleusercontent.com`; `GoogleWebClient.isReal` refuses it
  (`NotConfigured` before Credential Manager). **For 3H:** the release script must grep for it, and refuse a release bundle
  without `drawable/ic_google_g` (looked up by name, kept by `res/raw/keep_google_branding.xml`).
- Google's button: `GoogleBranding.MARK` = `ic_google_g` (mdpi to xxxhdpi, the centre 20 dp of the Light, no-text, Square Android+Web
  PNGs); `assets/fonts/GoogleSans.ttf` + `GoogleSans-OFL.txt`; both are in.
- Pins: navigation-compose 2.9.8 and lifecycle 2.10.0 (newer need compileSdk 37). The v1 `createComposeRule` is deprecated (review D m-8, undecided).

`:app` test support (`app/src/test/kotlin/com/shellx/app/testing/`): `ManualClock`, `TestIdentity`, `TestNetworkMonitor`,
`ScriptedRelay`, `testEnvironment`, `TestComposition`, `testComposition`, `mainComposition`, `RecordingNavigator`, `waitFor`,
`HomeFixtures`; `com.shellx.app.screenshots`: `assertRenders(name) { }`, `LargeText { }`, `chroma`. Renders never hold an endless
animation (an indeterminate spinner fails the capture after 60 s; use a render hook such as `spinner =`). Robolectric
`waitUntil` needs `waitForIdle()` inside the condition. Google fakes must be JWT-shaped.

Open minors: review D m-2 (a cold-start link is lost if the activity is recreated before the composition exists), m-4
(`launchSingleTop` replaces a sibling page of the same route), m-5 (`NavigatorRelay` drops a call with no window), review B m-1
(`LaunchMark` counts from process start), A-19 (a Keystore stuck on "transient" holds the launch screen).

Verified on emulators API 26 and 36 (debug and R8 release, 2026-11-10). Phone checks and live Google sign-in are the user's
(one app id `com.shellx.prod`; the production relay answers 404 to `POST /v1/auth/nonce` until 1D deploys 1A).

---

## 27. Additions from plan 3E (landed with the 3E merge on 2026-11-10)

Plug points for 3G, now consumed (`com.shellx.app.ui.workspaces`):
- `PaneContent(pane: WorkspacePane, shown: Boolean, agent: @Composable (MachineSession) -> Unit,
  shell: @Composable (WorkspacePane, Boolean) -> Unit = { _, _ -> ShellPanePlaceholder() })` — `shown` is true only for the pager's
  settled page; only that pane may open a terminal view.
- `WorkspaceScreen(title, branch, panes, selected, nowMs, canControl = true, canCloseTab = false, pagingLocked = false,
  notice: AgentNotice? = null, alert: WorkspaceAlert? = null, onAlertDismiss = {}, actions = WorkspaceScreenActions(), back = {},
  pane: @Composable (WorkspacePane, Boolean) -> Unit)` (3G adds `canCreateTerminal`, `canViewTerminals`, `shownAsTerminal`,
  `creatingTerminal`, all defaulted).
- `PaneChips(panes, selected, nowMs, select, close: ((WorkspacePane) -> Unit)? = null, trailing: @Composable () -> Unit = {})`
  (+ `modifier`); `trailing` holds 3G's ＋ chip.
- `WorkspaceMenuItem(@StringRes title)` { RENAME, CLOSE_TAB, CLOSE_WORKSPACE } with `items(canCloseTab)`.
- `WorkspaceScreenActions(select, rename, close, closeTab)` with `make(scope, model, alert, closing, done)`; each command runs in `hub.scope`.
- `WorkspaceView(scope: SignedInScope, ref: WorkspaceRef, open, back)`; its model lives in a `viewModel` holder keyed
  `workspace/<machineId>/<workspaceId>`.
- `ShellPanePlaceholder(modifier)` stays as the page of a Mac whose ShellX shows no terminals.
- `ComposerBarState(scope, initial)` (held by `AgentScreenHolder`, in `viewModelScope`): a pick still being read survives a swipe
  to another pane and a rotation. `CompactHeight` (`MAX_DP = 480`, `TOP_BAR = 48.dp`, `isCompactHeight()`, `topBarHeight()`):
  in a window under 480 dp tall the work screens use 48 dp bars (ledger A-30).

Routes (`WorkRoutes`): `PENDING = "pending?machineId={machineId}&workspaceId={workspaceId}"` (both optional), `WORKSPACE =
"workspace/{machineId}/{workspaceId}"`, `AGENT = "agent/{machineId}/{sessionId}"`; `workspace(ref)`, `agent(ref)`, `pending()`,
`pendingIn(machineId, workspaceId)`, `sessionRef(hub: HubState, machineId, sessionId)`. Destinations open with
`launchSingleTop`; they leave with `navigator::back`. A push tap while the stack is exactly `[root, pending]` with no filter is
taken and navigates nowhere (the open sheet and its text stay).

Composition:
- `PlatformServices(app, debugBuild, updateManager: (Context) -> AppUpdateManager, pushRegistrar: FcmPushRegistrar = FcmPushRegistrar())`:
  `permissions: PermissionRequester`, `voice: SystemVoice`, `voicePermissions`, `speechEngine`, `pushTaps: PushTapInbox`,
  `playUpdates: PlayUpdateChecker?` (null in debug), `updateChecker`, `attachmentReader`, `makeVoice(hub, latency, settings, clock)`,
  `makeNotifier(vault)`.
- `open class ShellXApplication : Application(), PushHost` — `platform`, `receiveLink(uri)`, `pushHooks`; each ON_START runs
  `composition.lifecycle.onStart()` then `pushHooks.notifier.clearAll()`; follows `real.coordinator.phase` with
  `pushRegistrar.followSignOuts`. `LaunchMark.restart()` on the first start.
- `SignedInWork(scope, platform, push: PushRegistration?, settings, openPending: (() -> Unit)?, content)` (null `openPending` =
  the stack's bottom is not the signed-in root yet; a tap waits); `PushRegistrationEffect(machinesEmpty, signedIn, askPermission)`
  starts `signedIn()` UNDISPATCHED and asks for the notification permission without waiting for it.
  `SignedInFrame(composition, nav, root, platform: PlatformServices? = null, content)`, `ShellXApp(composition, nav, platform = null)`;
  a null platform (the demo) never registers push or asks the permission.
- `LocalVoice` (`VoiceEnvironment(service, meter, scope, activity)`), `LocalAttachmentReader`.
- A third voice platform piece: `VoiceCapabilityProbe(sdkInt, onDeviceAvailable, standardAvailable, installedLanguages)`
  (`capabilities(language)`, `markFailed`, `SUPPORT_TIMEOUT = 2.seconds`, `system(context)`), given to `VoiceCapabilityCache`.
  `SystemVoice.primaryFailed` tells every live service the on-device recognizer failed.

Push (`com.shellx.app.platform`):
- Channel id `needs_you`; alert id 1 with tag `request_id`; per-Mac summary id 2 with tag `machine_id`; group `machine_id`;
  tap action `com.shellx.app.action.OPEN_PENDING` -> `MainActivity` -> `PushTapInbox` (`hasTap`, `receive()`, `take()`,
  `isOpenPending(intent)`). Android-only settings key `shellx.notifications.asked`.
- `PushNotifier(context, inForeground, knownMachines: suspend () -> Set<String>?, active)`; `handle(payload)`, `clearAll()`;
  `KNOWN_MACHINES_TIMEOUT = 2.seconds`. Foreground: nothing posts, and every ShellX alert clears on ON_START. A needs-you from a
  Mac not among the paired Macs is dropped; if the vault is unreadable for 2 s, it posts.
- `ShellXMessagingService : FirebaseMessagingService` is data-only (`PushPayload.parse`, then `notifier.handle`); `onNewToken`
  sends the token before returning (`TOKEN_TIMEOUT = 10.seconds`). `interface PushHost { pushHooks }`, `PushHooks(notifier, tokenArrived)`.
- **`FcmPushRegistrar(messaging: () -> FcmMessaging = FcmMessaging::firebase) : PushRegistrar`** — `currentToken()` turns FCM
  auto-init on, awaits the token, null on failure; `signedOut()` turns auto-init off; `followSignOuts(phase: Flow<AppPhase>)`.
  `FcmMessaging { setAutoInit(enabled); token() }`. Auto-init is off until 3C's `PushRegistration` first asks.
- `NotificationPermission`: `ASKED_KEY`, `requestOnce(requester, settings, sdkInt)`, `isOn(context)`, `noDialogShown(before, after)`
  (Settings › Notifications "Turn On" opens the system page only when the rationale flag was off before and after).
  `PermissionRequester.request(permission, onLaunch)` prompts only while RESUMED (shared contract change; the mic shares it).
- `PlayUpdateChecker(manager) : UpdateChecker` (`InstallPhase`, `installs`, `attach`, `check`, `startUpdate`, `completeUpdate`);
  after "No thanks" no Play dialog until the next cold start (ruled 2026-11; one-line change). `UpdateAlert(prompt, installs,
  modifier, restart)`. Play's dialog is the prompt; a Snackbar offers Restart.
- Settings: `NotificationsSettingsSection(settings: KeyValueStore? = null)`, `SettingsScreen(..., back, settings = null)`,
  `OemGuide.of(manufacturer)`, `NotificationSettingsIntents.appNotifications / appDetails`.
- Voice: `VoiceInputModel.read` — a run the recognizer ends by itself with nothing heard sets `Phase.Idle` (3C change, accepted).
  Android has the microphone permission only (`speech()` always true; `voice_denied` has Android wording). Mic TalkBack: the
  tap's label carries the hint (`voice_mic_hint`, Android-only, ledger A-29), no state description.

Deferred 3C items (3C owns; not done by 3E):
- **FCM `deleteToken()` at sign-out.** Today `followSignOuts` only turns auto-init off. 3C needs a sign-out hook on
  `PushRegistration`, called from `AppCoordinator`'s sign-out, account deletion and 401 paths, that forgets `latest` and `sent`;
  then `FcmPushRegistrar.signedOut()` can also call `deleteToken()`.
- **Token rotation after a same-process re-sign-in.** After sign-out and sign-in in one process, auto-init stays off and
  `PushRegistration.signedIn()` / `appBecameActive()` skip the registrar while `latest` is set; a rotation in that process is
  not synced until the next process start.
- **3H Data safety wording:** "no FCM token request or refresh while signed out" — not "no FCM token on the phone". A fresh
  install makes no FCM token until the first sign-in (the user's phone check item 10). The token also goes to the ShellX relay.
  The on-device recognizer keeps voice on the phone; the standard recognizer is the phone's own speech service; ShellX never
  receives or sends audio. Notification text (agent, workspace) comes from the Mac through the relay and is built on the phone.
- The relay already forgets the token at sign-out (A-8); a sign-out while offline cannot delete it (hence the unknown-Mac guard).

Test kit: `TestClock`, `eventually`, `WorkRig` (3G adds `servesTerminalViews`), `FakeSpeechEngine`, `FakeVoicePermissions`,
`FakeResultRegistry`, `TestOwner`, `ManifestTest`.

Open (ruled fine to defer): compact bar gated on height only (portrait split screen leaves chips ~80 dp); a 48 dp bar can clip
titles at font scale >= 1.8 in landscape; a first permission dialog dismissed with Back / outside tap opens the system page;
`attachNote` is not saved across process death. Phone checks Part A (works through "Try without an account") and Part B (needs a
relay with 1A and 3F, FCM both ends, Google sign-in) are the user's; POST_NOTIFICATIONS needs an Android 13+ phone (neither test phone is).

---

## 28. Additions from plan 3G (landed with the 3G merge on 2026-11-10)

Supersedes §21's name list where they differ. Ledger rows: A-g1..A-g5 = **A-31..A-35**, plus **A-36** (landscape),
**A-37** (history size cap) and **A-38** (the word the keyboard sees). Names checked against the landed tip `aef7f0faf5`.

**Kotlin Link (`com.shellx.link.core`)**
- Enums `TerminalViewOpenOutcome`, `TerminalViewEndReason`, `TerminalModifier`, `TerminalFrameKind`, `TerminalCursorShape`,
  `TerminalAttribute`, `TerminalKey`; `TerminalInputUnit`, `TerminalInputCheck`, `TerminalInputException`; grid types,
  `TerminalFrameAssembler`, `TerminalScreen` (mutable, `DEFAULT_MAX_HISTORY_ROWS`), `TerminalRow`, `TerminalStyledRun`,
  `TerminalCell`; the ten terminal `LinkMessage`s; `ShellXLink.TERMINAL_*` constants; `TerminalViewPush { Opened, Frame, Ended }`,
  `TerminalCreated`; `LinkSession` members `terminalPushes`, `openTerminalView`, `closeTerminalView`, `sendTerminalInput`,
  `resizeTerminalView`, `resyncTerminalView`, `createTerminal` (defaults, so older fakes compile). No frame splitter on the phone.
- Frame integers are read as 64-bit and held at Int limits (`wideInt` / `optWideInt`), so Kotlin accepts and refuses exactly the
  frames Swift does.

**Bounds: socket inbox and `TerminalPushQueue`**
- Socket inbox (`OkHttpRelaySocket`, internal): binary messages <= `MAX_QUEUED_BYTES = 1_048_576` (1 MiB; 16 Noise messages);
  `InboxBudget.take` blocks OkHttp's reader thread (TCP back-pressure); nothing dropped (Noise nonces are implicit); text
  messages are not counted and never wait; a message larger than the bound enters alone when the inbox is empty.
- `TerminalPushQueue(maxQueuedWeight = MAX_QUEUED_WEIGHT)`, `MAX_QUEUED_WEIGHT = 2_097_152` (about 2 MiB of frame JSON; weight =
  exact UTF-8 bytes of run text + 64 per part, 48 per style, 2 560 per palette, 16 per line, 24 per run). `offer()` never
  suspends, so replies, pings and other pushes pass an unread flood. Rules:
  - a frame that would pass the bound is dropped unless the queue is empty; the first drop of a run of drops queues
    `TerminalFramePart.LOST` = `TerminalFramePart(revision = 0, part = 1, parts = 2)` — the codec refuses revision 0, so LOST
    cannot come from the wire; the assembler reads it as a gap and asks for exactly one resync;
  - after a LOST, that terminal's deltas and history frames are dropped silently until its next snapshot;
  - **the viewed terminal's snapshot is exempt from the bound** (viewed = last `Opened` until its `Ended`), and a kept snapshot's
    part 0 replaces every queued frame of that terminal, LOST included — at most one snapshot per view queued; later parts count
    only in order (`next` index);
  - `Opened` and viewed `Ended` are never dropped; **`Ended` of non-viewed terminals is capped at 16 queued
    (`MAX_QUEUED_OTHER_ENDS`)**, no coalescing; frames of other terminals follow the bound and leave no state;
  - drop state is kept for the viewed terminal only (`viewLost`, `viewArriving`), cleared by its `Ended`, the next `Opened`, `close()`;
  - one `LinkLog` event per run of drops ("client dropped terminal frames over the bound"), no content.
  - Collectors: one at a time; a collector cancelled while waiting gives its entry back; `pushes` is a hand-written `Flow` that
    emits straight from the collector's coroutine. **No `buffer`, `flowOn`, `shareIn`, `produceIn`, channel or filter (revision
    filters included) between `pushes` and the assembler.** Memory about 2-6 MiB per session plus one snapshot per view opened while lagging.
- **The relay's real behaviour** (`cmux-relay` `relay.rs` ~1113-1116, 1325-1340, `config.rs` 22-23): it queues <= 128 frames or
  2 MiB per socket and **ends the circuit when full**. The phone's bound therefore engages only when decoding lags the network;
  a phone that stays behind loses the circuit and reconnects; the Mac does not send "fewer, larger deltas".
- `LinkClient`: an open that times out and its late `Opened` are decided in one locked step (no `Opened` for a timed-out open).

**`:core` (`com.shellx.core.terminal` unless noted)**
- Hub: `MachineHub : DecisionSending, TerminalLink`; `supportsTerminalCreate(machineId)`; `suspend createTerminal(ref: WorkspaceRef):
  TerminalCreation`; `HubState.supportsTerminalView / supportsTerminalCreate`; `MachineEvent.TerminalPushes(pushes)` (the flow, sent
  just before a session's `Online`); `LatencyMetric.TERMINAL_FIRST_SCREEN`, `TERMINAL_KEY_ECHO`, `TERMINAL_FRAME_APPLY`.
- `interface TerminalLink`: `terminalEvents(machineId): Flow<TerminalHubEvent>` (`Push(machineId, push)` | `State(machineId, state)`),
  `isOnline`, `supportsTerminalView`, `openTerminalView(machineId, terminalId, cols, rows): TerminalOpenResult` (`Outcome` |
  `NotSent` | `NoAnswer`), `closeTerminalView`, `resyncTerminalView`, `sendTerminalInput`, `resizeTerminalView`, `recordLatency`.
- **`hub.terminalEvents(machineId)` and the newest-page-per-Mac rule:** per Mac, only the newest collection takes the pushes
  (a session views one terminal; two collectors would split frames); the older gets states only and takes the pushes again when
  the newer ends. A new collection cancels the older one's taking scope at once. While nobody collects, pushes wait in the bounded
  queue (no drainer). A collection told `Online` is always told a non-`Online` state before that session's pushes end; states
  are conflated. Consequence: two workspace screens of one Mac STARTED at once (navigation transition, predictive back) -> only the
  newer sees frames; the older may sit on Connecting until it reopens.
- `TerminalViewModel(machineId, link: TerminalLink, scope, maxHistoryRows = TerminalScreen.DEFAULT_MAX_HISTORY_ROWS,
  sleep = { delay(it) }, now = TimeSource.Monotonic) : TerminalTextInput`; companion `RESIZE_DELAY` 200 ms, `BUSY_RETRY_DELAY` 300 ms,
  `BUSY_RETRIES = 5`, `FAILED_RETRY_DELAY` 1 s, `SCROLL_COALESCING`, `ECHO_TIMEOUT`; `fixed(...)`.
  - State: `state: StateFlow<TerminalViewState(terminalId, phase, screenRevision: Long, snapshots, topShift, markedText,
    ctrlLatched, sentInputs, pasteTooLarge: Int, acceptsInput)>` and getters for each; `screen` (main thread only);
    `TerminalViewPhase { Connecting, Live, Offline, Unsupported, Unavailable(reason) }`, `TerminalUnavailableReason { GONE, REFUSED, FAILED }`.
  - Lifecycle: `suspend run()`, `show(terminalId?)`, `setPhoneGrid(cols, rows)`, `retry()`, **`close(): Job`**.
  - Input: `insertText`, `setMarkedText`, `unmarkText`, `deleteBackward`, **`typeKey(text)`** (= unmark + insert, one message; hardware
    `Type(text)` goes here, not `insertText`), `press(key, mods)`, `toggleCtrl()`, `paste(text)`, `scroll(lines)`.
  - **`acceptsInput`:** true while Live, and while Connecting once a screen came and an open is in flight (queues behind the open,
    R10); false in waits with no view in flight and under every card. The pane's check is
    `acceptsInput && model.terminalId == the surface's terminalId`.
  - Every send is the last step of a change (an inline answer on `Main.immediate` must not be overwritten); one FIFO outbox.
  - **Dispatcher rule: run the model on `hub.scope` (`Main.immediate`) or a standard test dispatcher, never `Unconfined` /
    `UnconfinedTestDispatcher`** (its `yield()` deferral of a same-turn restart needs a dispatcher that really defers).
  - `WorkspaceView` runs `repeatOnLifecycle(STARTED) { terminal.run() }`; the holder's `onCleared()` calls `terminal.close()`.
- `WorkspaceScreenModel`: `shownAsTerminal: Set<String>`, `terminalShown: String?`, `showAsTerminal(id, on)`, `expect(id)`,
  **`settle()`** (typing in or focusing a terminal settles the screen, so an agent that starts waiting never moves the selection),
  **`creatingTerminal: Boolean`**, **`startCreatingTerminal(): Boolean`**, **`finishCreatingTerminal(terminalId: String?)`** (on every
  way out, in a `finally` run in `hub.scope` so it survives rotation); `WorkspaceScreenState.shownAsTerminal / creatingTerminal`.
  ＋ is dimmed while a create is in flight; a pick made meanwhile wins.
- Typing / keys / geometry: `TerminalTextInput`, `TerminalTyping`, `TerminalInputBatcher` (`MAX_PASTE_BYTES` 256 KiB, `pasteFits`,
  `pasteUnits`, `scrollUnits`), `TerminalKeyCodes`, `TerminalHardwareModifiers`, `TerminalHardwareAction { Send, Type, DeleteBackward,
  Paste, System }`, `TerminalHardwareKeys.action(keyCode, plainChar, altChar, modifiers)`, `TerminalBarKey`, `TerminalGeometry`,
  `TerminalGridSize`, `TerminalScrollStep`, `TerminalZoom`, `TerminalViewport`, `TerminalColors`, `TerminalRgb`, `TerminalResolvedStyle`.
- Demo: `DemoTerminalFixture`, `DemoTerminalScreens`, `DemoEnvironment.TERMINALS`; `FakeMac` terminal API (hostFeatures include
  `terminal_view`, `terminal_create`; `servesTerminalViews`, `acceptsTerminalCreate`); the fake answers `ok` after the Mac has the
  message in order and never answers `too_large`. Demo terminals are fixed 50 x 40 fixtures (the iPhone's are too).
- Test kit: `ScriptedTerminalLink` (`calls`, `openAnswers`, `openGate`, `onOpen`, `onInput`, `eventsFailure`, `openFailure`,
  `openCancelledAtClose`), `TerminalPushReader`, `Collector`, `hubRig(scope = backgroundScope)`, `TerminalFixtures`.

**`:app` (`com.shellx.app.ui.terminal`, `com.shellx.app.ui.workspaces`)**
- `TerminalPane(model, terminalId, title, shown, modifier, locksPaging, showsKeyBar = false, engaged = {})`, `TerminalPane.perform`,
  `TerminalSurfaceView(context, model, terminalId, font, ime)`, `TerminalInputConnection`, `TerminalIme` / `SystemTerminalIme` /
  `LocalTerminalIme`, `TerminalClipboard`, `TerminalKeyBar` / `TerminalKeyBarItem`, `TerminalFont`, `TerminalGlyphMetrics`,
  `TerminalRowLayout`, `TerminalRowCache` (keys rows by identity). Test tags `terminal.surface`, `terminal.connecting`,
  `terminal.unavailable`, `terminal.offline`, `terminal.retry`, `terminal.paste`, `terminal.keyBar`, `terminal.key.*`, `workspace.chip.add`.
- On 3E's screens: `NewTerminalChip(enabled, onClick)`, `WorkspaceMenuItem.VIEW_AS_TERMINAL / VIEW_AS_CHAT` and `AgentChip`
  (`items(canCloseTab, agentChip = null)`), `WorkspaceCommand.CREATE_TERMINAL`, `WorkspaceScreenActions.createTerminal / showAsTerminal`,
  `WorkspaceScreenHolder(model, terminal)`; paging is locked while a voice hold or a zoomed terminal is active.
- Soft keyboard / TalkBack: the §21 `EditorInfo` rule holds. TalkBack reads the terminal from the surface `View` (an
  accessibility delegate: "Terminal <title>" with the screen as text), because a Compose node under the pane never reaches a service.
- **The word the keyboard sees (A-38):** `TerminalInputConnection` keeps a shadow of the word committed since the last word
  boundary (<= 32 UTF-16 units, memory only) before the composing text, and answers `getTextBeforeCursor`,
  `getSurroundingText`, `getExtractedText` and the snapshot from it, with `updateSelection` after every change. A rewrite of
  committed text (`deleteSurroundingText` + `commitText`, a composing region over the word, `replaceText`) goes to the Mac as
  backspaces plus the new text (<= 33 messages per rewrite). A space, Enter, a paste, a named key, a chord, a key-bar key, a
  hardware key event, the focus lost and a restart end the word. `TYPE_TEXT_FLAG_NO_SUGGESTIONS` stays: without it Gboard
  turns auto-correct on (`lss` -> `less`). Telex verified on the API 36 emulator (`tieengs` -> `tiếng`, `vieetj` -> `việt`);
  VNI unit-tested only (the emulator's Gboard has no VNI layout).
- Key bar: eight keys, each touch slot 48-58 dp; under 384 dp wide the row scrolls instead of shrinking a slot.
- A-36: in a window under 480 dp tall, while a terminal page holds the soft keyboard and it takes room, the workspace top bar
  and the demo banner step aside and return with the keyboard; a hardware or floating keyboard keeps them
  (`terminalHoldsKeyboard`, `TerminalPane.holdsKeyboard`, `DemoFrame`, `CompactHeight.TerminalKeyboard`).
- Later fixes on the branch (after `0721606992`): metric logcat lines are debug-only; `TerminalViewState.toString` prints the
  composed word as `<N chars>`; Paste is offered only for a clip whose text the reader takes (a copied file pastes nothing);
  a rotation keeps the keyboard and the key bar (taken back once the window has the focus, asked again if the system hides
  it), and a page that comes back after Back does not take it; the surface is never laid out with no height; a glyph run is
  cut where a glyph would sit more than 0.5 px off its column; `TerminalPushQueue` yields the collector's thread every
  16 pushes or 4 ms; the screen stays out of content capture (`IMPORTANT_FOR_CONTENT_CAPTURE_NO`, data-sensitive on API 34+).

**Strings.** Android-only (`strings_android.xml`): `terminal_paste` (Paste / Dán), `terminal_cap_esc`, `terminal_cap_tab`,
`terminal_cap_ctrl` (untranslatable). `workspace.shell.placeholder` is **deleted** from the iPhone catalog (no Swift or Android
string use; only an `accessibilityIdentifier`); Android's `workspace_shell_placeholder` went with it; `import-strings: ok (266 strings, 1 plurals)`.
Rule for any later Android text surface that must keep Vietnamese composing: §21's `EditorInfo` (never `TYPE_NULL` / password).

**Parity deviations (all in the ledger)**
- A-31 Ctrl+V sends ctrl-v, Ctrl+Shift+V pastes. A-32 a multi-line commit is a paste. A-33 a key that reaches the view while
  composing commits the word first (the keyboard sees keys first on Android). A-34 `IME_FLAG_NO_PERSONALIZED_LEARNING`.
  A-35 the view closes whenever the screen stops (background, another screen, rotation) and reopens on start. A-36 landscape.
- A-37: history is capped at about 16 MiB by estimated size (`TerminalScreen.maxHistoryBytes`, link-core, Android only)
  besides `DEFAULT_MAX_HISTORY_ROWS` = 10 000 rows; the iPhone has the row cap only.
- **m3 retry budgets (differs from the iPhone):** a run that starts with no view restores both open budgets (busy x5, one failed
  retry), the pending retry wait is kept, `Unavailable` is sticky — at most one extra failed open or five extra busy opens per
  stop+start against a Mac that keeps failing (ledger row for `TerminalViewModel`).
- **Ctrl on non-Latin layouts:** Ctrl+letter on a key that types another script (or a combining mark) uses the key's Latin letter
  by physical key code (iPhone parity); **punctuation chords stay `System`** (cannot tell from AZERTY `,` without a layout signal) — a few rare chords.
- Follow-the-bottom threshold is half a row (iPhone parity); non-finite pinch factors / focus / scroll deltas are ignored;
  `Type.toString` prints `<N bytes>`.
- Fixed 12 dp monospace font with pinch zoom (not the system font size); the hide-keyboard key; while zoomed wider than the pane
  paging is locked so a sideways drag always pans (the chips still switch pages).

**Upstream notes (for 3C and the iPhone)**
- A frame's `history` count is **uncapped in both apps** (m8, same as Swift).
- `graphemes()` (Android) vs Swift `Character` differ on edge clusters; the bytes sent are identical.
- Gboard on API 36 shows its suggestion strip despite `TYPE_TEXT_FLAG_NO_SUGGESTIONS`, commits each letter and rewrites the
  word it committed; A-38 turns the rewrites into backspaces and text. Telex/VNI on a real phone are still the user's check
  (Part A item 3).
- R8: only the demo's in-process link has run under R8; add terminal traffic to a release smoke once a live relay is reachable.

**Part B (pending).** Latency capture (`terminalFirstScreen` p95 < 1 000 ms, `terminalKeyEcho` p95 < 300 ms, `terminalFrameApply`
p95 < 16 ms), two-chip swiping, floods (`yes | head -100000`, base64 of 5 MB), vim / htop, ＋ without moving the Mac's selection,
and home / back — all need a relay that answers sign-in (the production relay answers 404 to `/v1/auth/nonce` until 1D deploys 1A)
plus plan 2B's Mac build. Record "Part B pending: needs a relay with 1A (and 1D's Android client) and the 2B Mac build" in the ledger.

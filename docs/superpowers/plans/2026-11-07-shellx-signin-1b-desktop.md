# ShellX Google Sign-in, Plan 1B (Desktop: shellx-core, Mac, Windows) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mac and Windows sign in only with a Google-branded "Continue with Google" button (loopback OAuth + PKCE in `shellx-core`; Google's official "G" from a USER-approved download), switch an existing password session to Google in place, list sign-in methods with Remove for Apple IDs, link to account deletion, warn on the Mac pairing sheet when a pairing links an Apple ID, and say "phone" instead of "iPhone" on the Mac.

**Architecture:** `shellx-core` owns the whole Google flow (`auth.google.begin/finish/cancel`: relay nonce, 127.0.0.1 listener, state, PKCE S256, Google token exchange, then `POST /v1/auth/google` or `/v1/auth/google/link`) plus `account.identities.*` and `auth.session`; the in-memory `shellx-fake-api` gains the new relay routes and a fake Google so every test runs offline. The Mac wraps the core in `ShellXCoreClient`/`ShellXAccount` (package `ShellXBrand`) with a `GoogleSignInModel` in `ShellXRemoteUI` and thin app views; Windows adds the same steps to its pure `AccountFlow` state machine (`shellx-model`) and GPUI views (`shellx-app`).

**Tech Stack:** Rust 1.91 edition 2024 (`ureq` 3.4, rustls/ring, `tiny_http` in the fake), Swift 6.0 language mode (Swift Testing, SwiftUI/AppKit, `@Observable`), GPUI `=0.2.2`, Python 3 harness.

**Spec:** `docs/superpowers/specs/2026-11-07-shellx-google-sign-in-design.md` (S1 §5, §6.3, §6.3b, §6.4, §6.5, §9) and `docs/superpowers/specs/2026-11-07-shellx-android-app-design.md` §7.4b. Cross-plan names: `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` §2 (relay API) and §3 (this plan's RPC). Read all three before Task 1.

## Global Constraints

- Every route, field, RPC method and error code is spelled exactly as in contracts §2–§3. New RPC methods: `auth.google.begin {purpose: "sign_in"|"link"} → {flow_id, auth_url}`, `auth.google.finish {flow_id} → {user_id, device_id, device_public_key_b64, fingerprint, email, auth_method: "google"}`, `auth.google.cancel {flow_id} → {}`, `account.identities.list {} → {identities: [...]}`, `account.identities.remove {identity_id} → {}`, plus `auth.session` (see Contract additions).
- Core error codes the apps handle: `switch_from_signed_in_device`, `google_cancelled`, `google_timeout`, `google_state_mismatch`, `email_in_use`, `identity_in_use`, `last_google_identity`, `password_sign_in_removed`, plus the existing `invalid_credentials`, `network`, `not_logged_in`, `unauthorized`, `http_401`.
- Loopback redirect `http://127.0.0.1:<random port>/oauth2/callback`, listener bound to 127.0.0.1 only, closed after the first callback, a cancel, or 300 s. Google endpoints `https://accounts.google.com/o/oauth2/v2/auth` and `https://oauth2.googleapis.com/token`; scope `openid email profile`; `prompt=select_account`; PKCE `S256`; the raw relay nonce goes in the `nonce` parameter.
- Desktop client id/secret: compiled defaults from `option_env!("SHELLX_GOOGLE_DESKTOP_CLIENT_ID")` / `option_env!("SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET")` (empty when unset at build), overridden at run time by `std::env::var` of the same names, then by `config.set` params. Never commit a real id or secret.
- Never log, `Debug`-print or put in a `CoreError` message: session tokens, `id_token`, the OAuth `code`, the PKCE verifier, the client secret, nonces, `state`, or email addresses.
- No new crates and no new Swift packages: `shellx-core/Cargo.lock` and `windows/Cargo.lock` stay unchanged (the app's Xcode phase builds with `cargo build --release --locked`).
- On a relay 401 the desktop keeps `device.key` and `machine.json`; only `session.json` is forgotten (existing `Core::forget_refused_session`, `shellx-core/src/lib.rs:125-136`).
- `auth.login` stays (dev credentials, tests); no UI calls it after this plan.
- Mac: app-linked Swift stays Swift 6.0 compatible; app tests only through `scripts/shellx/test-app.sh <Suite>` (never bare `xcodebuild`); never quit, relaunch or replace the running ShellX or cmux app; a new `Sources/**/*.swift` file is wired with `./scripts/wire-app-sources.py <path>`; a new/renamed/deleted `cmuxTests/*.swift` file needs `./scripts/sync-test-wiring` (this plan adds none).
- Mac strings: `String(localized: "<key>", defaultValue: "<English>")`, catalog `Resources/Localizable.xcstrings`, all ten locales `en, de, fr, ar, es, zh-Hant, zh-Hans, ko, ja, vi` through `./scripts/localize-changes --base develop` (skills/cmux-localization). `en` and `vi` use exactly the values in the String tables below; the other eight are the executor's translations. Vietnamese follows `scripts/shellx/l10n/vi-glossary.md`; spell "xóa". A translation identical to English needs an `identityLocales` record in `scripts/localization-allowed-omissions.json`. Every call site of a key passes the same `defaultValue`.
- Windows strings live in `windows/shellx-model/src/strings.rs`; each shared string equals the Mac's `en`/`vi` value (pinned by `sign_in_strings_match_the_mac`).
- Delete-account link target: `https://shellx.pro/privacy#delete-account`.
- Google branding (contracts §11; https://developers.google.com/identity/branding-guidelines, h3 "Create a custom Sign in with Google Button", h4 "Size", "Text", "Color", "Font", "Padding", "Google logo in the "Sign in with Google" button"): one rectangular button, Light theme in every appearance on both desktops, as plan 1C does: fill `#FFFFFF`, stroke `#747775` 1 px inside, text `#1F1F1F`, Google Sans Medium 14/20, height 40, corner radius 4, "G" 20×20, padding 12 before the "G", 10 after it, 12 after the text (the page's "Android & web" values and the geometry of its Android + Web assets; the page has no desktop row). Label `remote.signin.google` / `ContinueWithGoogle`.
- The "G" comes only from Google's `signin-assets.zip`, downloaded by the USER in Task 9 under Google's terms. Never copy a Google logo from GPL code (`ios/cmux/Assets.xcassets/GoogleLogo.imageset/google-logo.svg` or anything else in `ios/`, `Packages/`, `Sources/`), never draw, recolor or resize one. Until the files are in the tree both apps show a text-only "Continue with Google" button and the release scripts refuse to build.
- Font licence gate (contracts §11): Google Sans Medium is bundled only next to `GoogleSans-OFL.txt` holding the SIL OFL 1.1 text from its official download; without it the button uses the system font (SF Pro / Segoe UI) at medium 14. Never bundle a font whose licence is unconfirmed.
- Branch `feat/shellx-signin-1b-desktop` from `develop` in its own worktree. Landing (contracts §1): this plan changes app UI/runtime, so after the final review it waits for the USER device check and the user's merge directive (`merge`, `merge it` or `auto-merge`, CLAUDE.md "CI, review and merge"); if none was given, ask with the review summary. Only then merge into `develop` from the main checkout and push `develop`. Never merge to `main`, never deploy, never upload to a store; publishing a desktop release is plan 1D's, after the user's go-ahead.

## Review Focus

1. **The person clicks "Continue with Google" twice, or opens the sheet again while a flow waits.** Only one listener stays open and the older flow ends `google_cancelled`. Tests: Task 3 `a_second_begin_cancels_the_first_flow`; Task 8 `startTwiceRunsOneFlow`.
2. **The browser never comes back (tab closed, laptop asleep).** After 300 s `finish` returns `google_timeout`, the port closes, the sheet says it timed out and can start again. Tests: Task 3 `waiting_past_the_deadline_is_google_timeout`; Task 8 `aTimeoutShowsItsMessageAndAllowsRetry`.
3. **Another tab or local process hits the loopback port with a wrong or missing `state`.** Nothing is sent to Google or the relay, no session is written, the result is `google_state_mismatch`. Test: Task 3 `a_wrong_state_is_google_state_mismatch`.
4. **The relay refuses an old token (cut-over day, revoked device).** The app shows sign-in, keeps `device.key` and `machine.json`, and a Google sign-in to the same account keeps the same `device_id` and machine. Tests: Task 3 `google_sign_in_after_a_401_keeps_the_device_id_and_machine` and `a_refused_link_forgets_the_session_but_keeps_machine_and_key`; Task 7 `serverSignOutForgetsTheIdentityAndAsksForSignIn`; Task 14 `server_sign_out_shows_sign_in`.
5. **Someone signs in with Google using the email of an account that still has a password (before cut-over).** The relay answers `switch_from_signed_in_device`, the local session is untouched, and the app tells them to switch from a signed-in device. Tests: Task 3 `a_password_account_email_answers_switch_from_signed_in_device`; Task 8 `failureShowsTheMessageAndAllowsRetry`; Task 13 `google_error_maps_codes`.

## String tables

Mac keys (`Resources/Localizable.xcstrings`). "Win" names the `windows/shellx-model` `Str` variant or helper that must carry the same text.

| Key | en | vi | Win |
| --- | --- | --- | --- |
| `remote.signin.google` (new) | Continue with Google | Tiếp tục với Google | `ContinueWithGoogle` |
| `remote.signin.waiting` (new) | Waiting for Google… | Đang chờ Google… | `WaitingForGoogle` |
| `remote.signin.browserHint` (new) | Finish signing in in your browser, then come back here. | Hãy hoàn tất đăng nhập trong trình duyệt rồi quay lại đây. | `BrowserHint` |
| `remote.signin.signedInAs` (new) | Signed in as %@ | Đã đăng nhập: %@ | — |
| `remote.signin.done` (new) | Done | Xong | — |
| `remote.signin.switch.title` (new) | Switch to Google sign-in | Chuyển sang đăng nhập Google | `SwitchToGoogle` |
| `remote.signin.switch.intro` (new) | ShellX now signs in with Google. Switching keeps this computer, your phones and your share links. | ShellX giờ đăng nhập bằng Google. Chuyển sang Google vẫn giữ máy tính này, điện thoại và các liên kết chia sẻ của bạn. | `SwitchToGoogleIntro` |
| `remote.signin.switch.button` (new) | Switch… | Chuyển… | `SwitchEllipsis` |
| `remote.signin.error.credentials` (changed) | Google sign-in didn't work. Try again. | Đăng nhập Google không thành công. Hãy thử lại. | `GoogleFailed` |
| `remote.signin.error.timeout` (new) | Google sign-in timed out. Try again. | Đăng nhập Google đã hết thời gian chờ. Hãy thử lại. | `GoogleTimedOut` |
| `remote.signin.error.stateMismatch` (new) | Sign-in didn't finish. Try again. | Đăng nhập chưa hoàn tất. Hãy thử lại. | `GoogleStateMismatch` |
| `remote.signin.error.switchFromSignedInDevice` (new) | This email already has a ShellX account. Open ShellX on a device that is still signed in, go to Settings › Account › Switch to Google sign-in, then try again. | Email này đã có tài khoản ShellX. Mở ShellX trên một máy đang đăng nhập, vào Cài đặt › Tài khoản › Chuyển sang đăng nhập Google, rồi thử lại. | `SwitchFromSignedInDevice` |
| `remote.signin.error.emailInUse` (new) | Another ShellX account already uses this Google account's email. Choose a different Google account. | Email của tài khoản Google này đã thuộc một tài khoản ShellX khác. Hãy chọn tài khoản Google khác. | `EmailInUse` |
| `remote.signin.error.identityInUse` (new) | This Google account already signs in to another ShellX account, or this account already uses another Google account. | Tài khoản Google này đã dùng để đăng nhập một tài khoản ShellX khác, hoặc tài khoản này đã dùng một tài khoản Google khác. | `IdentityInUse` |
| `remote.signin.error.browser` (new) | Couldn't open your browser. | Không mở được trình duyệt. | `BrowserUnavailable` |
| `remote.signin.error.network` (unchanged) | Can't reach relay.shellx.pro | Không kết nối được relay.shellx.pro | `RelayUnreachable` |
| `settings.account.methods.title` (new) | Sign-in methods | Cách đăng nhập | `SignInMethods` |
| `settings.account.methods.google` (new) | Google account | Tài khoản Google | `GoogleAccount` |
| `settings.account.methods.apple` (new) | Apple ID | ID Apple | `AppleId` |
| `settings.account.methods.hiddenEmail` (new) | Hidden email | Email ẩn | `HiddenEmail` |
| `settings.account.methods.addedFrom` (new) | Added from %@ | Thêm từ %@ | `added_from()` |
| `settings.account.methods.remove` (new) | Remove | Gỡ | `RemoveMethod` |
| `settings.account.methods.error` (new) | Sign-in methods: something went wrong (%@) | Cách đăng nhập: có lỗi xảy ra (%@) | `sign_in_methods_error()` |
| `settings.account.deleteAccount` (new) | Delete Account… | Xóa tài khoản… | `DeleteAccount` |
| `remote.phonePairing.appleLink` (new) | Allowing lets this Apple ID sign in to your ShellX account and manage it, including deleting the account. | Cho phép sẽ để ID Apple này đăng nhập và quản lý tài khoản ShellX của bạn, kể cả xóa tài khoản. | — |

"Phone" wording (S3 §7.4b), Mac only; plan 1C quotes `remote.phonePairing.menu`:

| Key | en (was) | en (new) | vi (new) |
| --- | --- | --- | --- |
| `remote.phonePairing.menu` | Pair iPhone… | Pair Phone… | Ghép cặp điện thoại… |
| `remote.phonePairing.title` | Pair iPhone | Pair Phone | Ghép cặp điện thoại |
| `remote.phonePairing.scan` | Scan this code with the ShellX app on your iPhone | Scan this code with the ShellX app on your phone | Quét mã này bằng app ShellX trên điện thoại |
| `remote.phonePairing.signInFirst` | Sign in under Settings › Account to pair an iPhone with this Mac. | Sign in under Settings › Account to pair a phone with this Mac. | Hãy đăng nhập trong Cài đặt › Tài khoản để ghép cặp điện thoại với Mac này. |
| `notifications.forwardToPhone.title` | Forward notifications to my iPhone | Forward notifications to my phone | Chuyển tiếp thông báo tới điện thoại của tôi |
| `notifications.forwardToPhone.subtitle` | Send local agent notifications to ShellX on your iPhone. Enabled by default; turn this off to stop this Mac from forwarding them. | Send local agent notifications to ShellX on your phone. Enabled by default; turn this off to stop this Mac from forwarding them. | Gửi thông báo agent cục bộ tới ShellX trên điện thoại của bạn. Được bật theo mặc định; hãy tắt để Mac này ngừng chuyển tiếp. |
| `settings.mobile.pairIPhone` | Pair iPhone | Pair Phone | Ghép cặp điện thoại |
| `settings.mobile.pairIPhone.subtitle` | Scan the QR code with ShellX on your iPhone, then allow the phone here on this Mac. | Scan the QR code with ShellX on your phone, then allow the phone here on this Mac. | Quét mã QR bằng ShellX trên điện thoại, rồi cho phép điện thoại ngay trên Mac này. |

Windows helpers: `added_from(lang, device)` → "Added from {device}" / "Thêm từ {device}"; `sign_in_methods_error(lang, code)` → "Sign-in methods: something went wrong ({code})" / "Cách đăng nhập: có lỗi xảy ra ({code})" (shown for a failed list or a failed removal).

Loopback pages (exact bytes, served with `HTTP/1.1 200 OK`, `Content-Type: text/html; charset=utf-8`, `Content-Length`, `Cache-Control: no-store`, `Connection: close`):

```html
<!doctype html><html lang="en"><head><meta charset="utf-8"><title>ShellX</title></head><body style="font-family:-apple-system,'Segoe UI',sans-serif;text-align:center;margin-top:20vh"><p>You can close this tab and return to ShellX.</p><p lang="vi">Bạn có thể đóng tab này và quay lại ShellX.</p></body></html>
```

```html
<!doctype html><html lang="en"><head><meta charset="utf-8"><title>ShellX</title></head><body style="font-family:-apple-system,'Segoe UI',sans-serif;text-align:center;margin-top:20vh"><p>Sign-in did not finish. Return to ShellX and try again.</p><p lang="vi">Đăng nhập chưa hoàn tất. Hãy quay lại ShellX và thử lại.</p></body></html>
```

---

### Task 0: Set up the worktree

**Files:** none (environment only).

**Prerequisites:** none. No other plan has to be merged first: every test here runs offline against `shellx-fake-api`, which mirrors relay plan 1A's routes. Live checks against the real relay need 1A deployed; they are plan 1D's.

- [ ] **Step 1: Create the worktree.** Use superpowers:using-git-worktrees to create `.worktrees/signin-1b-desktop` on a new branch `feat/shellx-signin-1b-desktop` from `develop`. Every later path is relative to that worktree. If this plan or `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` is missing there (they may be untracked in the main checkout), read them from `/Users/lehuuphu/Documents/myProjects/shellx/docs/superpowers/plans/` and do not add them on this branch.
- [ ] **Step 2: Make native builds possible.** In the worktree run `git submodule update --init ghostty vendor/bonsplit` (Windows `shellx-app` and the Mac app need ghostty; the Mac app's Xcode project also builds the local package `vendor/bonsplit`) and `ln -s /Users/lehuuphu/Documents/myProjects/shellx/GhosttyKit.xcframework GhosttyKit.xcframework` (ignored by `.gitignore:25`).
- [ ] **Step 3: Baseline.** Run each; record any failure before changing code (fix nothing unrelated):

```bash
(cd shellx-core && cargo test --workspace --locked)
swift test --package-path Packages/Shared/ShellXBrand
(cd windows && cargo test --locked -p shellx-model)
python3 tests/test_shellx_remote_harness.py
python3 tests/test_shellx_vi.py
```
Expected: each ends with all tests passing (`test result: ok`, Swift Testing `passed`, unittest `OK`).

---

### Task 1: Fake relay routes and fake Google in `shellx-fake-api`

**Files:**
- Modify: `shellx-core/fake-api/src/lib.rs` (`FakeOptions` :55-65 and `Default` :96-107, `Recorded` :110-121, `TokenInfo` :123-127, `State` :129-157, `PhonePairing` :159-171, `add_phone_pairing` :399-419, `Reply` :491-506, `handle` :508-537, `route` :543-593, `list_phone_pairings` :1072-1100, `login` :1208-1229; module doc :12-17)
- Modify: `shellx-core/fake-api/src/main.rs:40-50`
- Create: `shellx-core/fake-api/tests/google.rs`

**Interfaces:**
- Produces (used by Tasks 2–5, 15):

```rust
pub struct FakeOptions { /* existing fields */
    pub google_client_id: String,     // default "fake-desktop-client"
    pub google_client_secret: String, // default "fake-desktop-secret"
    pub google_email: String,         // default "google-user@shellx.test": the account the fake Google signs in
    pub google_subject: String,       // default "fake-google-sub-1"
}
pub struct Recorded { /* existing fields */ pub form: BTreeMap<String, String> } // decoded x-www-form-urlencoded body, else empty
impl FakeApi {
    pub fn set_google_account(&self, email: &str, subject: &str);
    pub fn issued_nonces(&self) -> Vec<String>;            // every nonce ever issued, oldest first
    pub fn add_identity(&self, user_id: &str, provider: &str, subject: &str, email: &str,
                        is_private_email: bool, linked_via_device_name: Option<&str>) -> String; // identity_id
    pub fn user_email(&self, user_id: &str) -> Option<String>;
    pub fn user_exists(&self, user_id: &str) -> bool;
    pub fn token_auth_method(&self, token: &str) -> Option<String>; // "password" | "google"
    pub fn add_apple_link_phone_pairing(&self, machine_id: &str, device_name: &str, client_key: [u8; 32]) -> String;
}
/// Test browser: GET `url` (must start `http://127.0.0.1:`), follow one 3xx `Location` (must start
/// `http://127.0.0.1:`), return the last response's status and body. Err for any other URL.
pub fn browse(url: &str) -> Result<(u16, String), String>;
```

Fake behavior (all over plain std/`tiny_http`, no new crates). `TokenInfo` gains `auth_method`; every route that issues a token (login, Google sign-in, link) also sets `last_token`, so `issued_token()` returns the newest one; `/v1/auth/login` users are remembered as password users (`password_users: HashSet<user_id>`); the fake Google account starts as `(opts.google_email, opts.google_subject)`. `Reply` gains `location: Option<String>` (sent as a `Location` header, empty body). `handle` fills `Recorded.form` when `Content-Type` starts `application/x-www-form-urlencoded` (`+` is space, `%XX` decoded).

| Route | Rule |
| --- | --- |
| `POST /v1/auth/nonce` | 201 `{nonce, expires_in: 600}`; nonce = 32 random bytes b64url (43 chars); kept unused until spent. |
| `GET /fake-google/auth?…` | 400 `{"error":"invalid_request"}` unless `client_id` = options id, `response_type=code`, `scope=openid email profile`, `code_challenge_method=S256`, 43-char `code_challenge`, non-empty `state` and `nonce`, `prompt=select_account`, `redirect_uri` starts `http://127.0.0.1:` and ends `/oauth2/callback`. Else 302 `Location: <redirect_uri>?code=<code>&state=<state>`; `code` = `"4/" + 24 random bytes b64url`, written `4%2F…` in the Location; the code remembers challenge, redirect_uri, nonce and the current Google account. |
| `POST /fake-google/token` (form) | 400 `{"error":"invalid_grant"}` unless `grant_type=authorization_code`, the code is known and unused (spent now), `redirect_uri` matches, b64url(SHA-256(`code_verifier`)) = the challenge; 400 `{"error":"invalid_client"}` unless `client_id`/`client_secret` match options. Else 200 `{"access_token":"fake-at","expires_in":3599,"id_token":"fake-idt.<32 random bytes b64url>","scope":"openid email profile","token_type":"Bearer"}`; the id_token remembers email, subject, nonce (single use). |
| `POST /v1/auth/google {id_token, nonce, device}` | 400 `invalid_device` unless `device_ok`; 401 `invalid_credentials` unless the nonce is issued and unused (spend it) and the id_token is known (spend it) with the same nonce. Then: identity (google, subject) → its user; else a user with that email: password user → 409 `switch_from_signed_in_device`, other → add identity; else new user with that email + identity. Device = same (user, key) → same id; one live token per device (`auth_method` google). 200 `{user_id, device_id, token, email}` (email = the account's email). |
| `POST /v1/auth/google/link {id_token, nonce}` + bearer | 401 `unauthorized` without a live bearer; nonce/id_token as above. Identity (google, subject) of another user → 409 `identity_in_use`; of the caller → ok; the caller already has a different Google identity → 409 `identity_in_use` (relay plan 1A). Else the Google email owned by another user → 409 `email_in_use`; else add identity and change the caller's account email to the Google email. Replace the caller's token with a new one (`auth_method` google; old token dead). 200 `{user_id, device_id, token, email}`. |
| `GET /v1/account/identities` + bearer | 200 `{identities: [{identity_id, provider, email, is_private_email, linked_via_device_name, created_at_unix}]}` for the caller's user, oldest first (`linked_via_device_name` null when none). |
| `DELETE /v1/account/identities/<id>` + bearer | 404 `identity_not_found` unless the caller's; 409 `last_google_identity` when it is the user's only `google` identity; else 204. |
| `DELETE /v1/account {id_token, nonce}` + bearer | 401 `reauth_required` without an `id_token` string; 401 `invalid_credentials` unless nonce/id_token valid and the token's (google, subject) identity belongs to the caller (as relay plan 1A); else 204 and the user, its identities and tokens are gone. |
| `GET /v2/phone-pairings?role=target[&apple_links=1]` | each item gains `"links_apple_id": bool` (true only for `add_apple_link_phone_pairing`). Apple-link pairings are listed only when the query also has `apple_links=1` (relay plan 1A, contracts §12); plain pairings are always listed. |

`main.rs`: when `SHELLX_FAKE_GOOGLE_EMAIL` is set and non-empty it replaces `opts.google_email` (never printed).

- [ ] **Step 1: Write the failing tests** in `shellx-core/fake-api/tests/google.rs`. Give the file a raw-socket `request` helper like `fake-api/tests/shares.rs:10-26` that also returns response headers, and a helper `id_token(fake, nonce) -> String` that GETs `/fake-google/auth` with `redirect_uri=http://127.0.0.1:9/oauth2/callback`, reads `code` from `Location`, and POSTs `/fake-google/token` with the matching verifier.

```rust
#[test] fn fake_google_checks_pkce_and_spends_codes() {
    // a verifier whose challenge does not match -> 400 {"error":"invalid_grant"}; the right one -> 200 with id_token;
    // the same code again -> 400 invalid_grant; Location carries "code=4%2F" and the state verbatim
}
#[test] fn nonces_are_single_use() {
    // POST /v1/auth/nonce -> 201, nonce.len() == 43, expires_in == 600
    // sign-in with it -> 200; a second sign-in reusing that nonce (fresh id_token) -> 401 invalid_credentials
}
#[test] fn google_sign_in_follows_the_account_rules() {
    // new email -> 200, user A; same subject again -> same user_id and device_id;
    // a password user (POST /v1/auth/login with email "pw@shellx.test") then set_google_account("pw@shellx.test", "s2")
    //   -> 409 switch_from_signed_in_device; token_auth_method(token) == Some("google") for a Google token
}
#[test] fn link_rules_replace_the_token() {
    // no bearer -> 401 unauthorized; caller B (password "b@shellx.test") while A (password) owns the Google email -> 409 email_in_use;
    // the Google subject already on user C -> 409 identity_in_use; success -> 200, the old bearer is dead,
    // token_auth_method(new) == Some("google"), user_email(B) == Some(the Google email)
}
#[test] fn identities_remove_rules() {
    // only google identity -> 409 last_google_identity; an added apple identity -> 204; unknown id -> 404 identity_not_found;
    // list shows linked_via_device_name "Phu's iPhone" and is_private_email true for the apple row before removal
}
#[test] fn account_delete_needs_a_fresh_identity_token() {
    // missing id_token -> 401 reauth_required; valid -> 204 and user_exists(user) == false
}
#[test] fn apple_link_pairings_are_marked() {
    // GET /v2/phone-pairings?role=target&apple_links=1: add_apple_link_phone_pairing -> item links_apple_id == true;
    // add_phone_pairing -> false; GET ?role=target without apple_links=1 lists only the plain pairing
}
#[test] fn browse_refuses_non_loopback_urls() {
    assert!(shellx_fake_api::browse("https://accounts.google.com/o/oauth2/v2/auth").is_err());
}
```

- [ ] **Step 2: Run to verify they fail.** Run: `(cd shellx-core && cargo test --locked -p shellx-fake-api --test google)`. Expected: compile errors (no `browse`, `set_google_account`, `add_apple_link_phone_pairing`, …).
- [ ] **Step 3: Commit the failing tests.** `git add shellx-core/fake-api/tests/google.rs && git commit -m "test(shellx-core): fake relay Google routes and fake Google"`
- [ ] **Step 4: Implement** the table above in `lib.rs` (new fields, helpers, routes, `browse`) and the env read in `main.rs`; update the module doc's route list.
- [ ] **Step 5: Run to verify they pass.** Run: `(cd shellx-core && cargo test --workspace --locked)`. Expected: `test result: ok` for every target, including the existing `bin.rs`, `shares.rs`, `ticket_format.rs`.
- [ ] **Step 6: Commit.** `git add shellx-core/fake-api/src/lib.rs shellx-core/fake-api/src/main.rs && git commit -m "feat(shellx-core): fake relay Google, identity and account routes"`

---

### Task 2: Google config, session fields, `auth.session` and `auth.google.begin`

**Files:**
- Modify: `shellx-core/src/config.rs:7-88`
- Modify: `shellx-core/src/http.rs` (add `post_form` after `send` :75-124)
- Modify: `shellx-core/src/api.rs` (`SessionFile` :43-59, new types, test literal :171)
- Modify: `shellx-core/src/auth.rs` (`login` :119-165)
- Create: `shellx-core/src/auth_google.rs`
- Modify: `shellx-core/src/lib.rs` (`mod` list :6-21, `KNOWN_METHODS` :33-57, `Core` :64-76, `forget_refused_session` :129-136, `dispatch` :142-186)
- Modify: `shellx-core/tests/support/mod.rs`
- Create: `shellx-core/tests/auth_google.rs`
- Modify: `shellx-core/tests/auth.rs`

**Interfaces:**
- Consumes: Task 1 fake routes, `shellx_fake_api::browse`.
- Produces:

```rust
// config.rs
pub const GOOGLE_AUTH_URL: &str = "https://accounts.google.com/o/oauth2/v2/auth";
pub const GOOGLE_TOKEN_URL: &str = "https://oauth2.googleapis.com/token";
pub struct Config { /* existing */ pub google_auth_url: String, pub google_token_url: String,
                    pub google_client_id: String, pub google_client_secret: String }
// config.set params "google_auth_url", "google_token_url" (validated like api_base: https, or http only for
// 127.0.0.1/localhost), "google_client_id", "google_client_secret" (a present param wins, even ""); Debug prints
// google_client_secret as "<redacted>".
// http.rs: no X-ShellX headers, no bearer; User-Agent only; transport error -> "network"
pub fn post_form(agent: &Agent, cfg: &Config, url: &str, fields: &[(&str, &str)], timeout: Option<Duration>) -> Result<Reply, CoreError>;
// api.rs
pub struct SessionFile { pub token: String, pub user_id: String, pub device_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub auth_method: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub email: Option<String> } // Debug: email "<redacted>"
pub struct NonceResponse { pub nonce: String, #[serde(default)] pub expires_in: u64 }       // Debug hides nonce
pub struct GoogleSignInRequest<'a> { pub id_token: &'a str, pub nonce: &'a str, pub device: LoginDevice<'a> } // not Debug
pub struct GoogleLinkRequest<'a> { pub id_token: &'a str, pub nonce: &'a str }                  // not Debug
pub struct GoogleAuthResponse { pub user_id: String, pub device_id: String, pub token: String, #[serde(default)] pub email: String } // Debug redacts token+email, Drop zeroizes token
pub struct GoogleTokenResponse { #[serde(default)] pub id_token: String }                       // Debug redacts, Drop zeroizes
// auth.rs
pub fn save_session(store: &StateStore, session: &SessionFile, previous_user: Option<&str>) -> Result<(), CoreError>; // write; drop machine.json when the user changed
pub fn forget_session_if(store: &StateStore, used: &str, lock: &Mutex<()>);   // body of Core::forget_refused_session
pub fn session_info(store: &StateStore) -> Result<Value, CoreError>;          // auth.session
// auth_google.rs
#[derive(Clone, Copy, Debug, PartialEq, Eq)] pub enum Purpose { SignIn, Link } // "sign_in" | "link"
pub struct Flow { /* purpose, state, verifier, nonce (Zeroizing), redirect_uri, listener: Mutex<Option<TcpListener>>, deadline: Instant, cancelled: AtomicBool */ }
pub type Flows = Mutex<HashMap<String, Arc<Flow>>>;
pub const FLOW_TIMEOUT: Duration = Duration::from_secs(300);
pub const CALLBACK_PATH: &str = "/oauth2/callback";
pub fn begin(agent: &ureq::Agent, cfg: &Config, store: &StateStore, flows: &Flows, params: &Value) -> Result<Value, CoreError>;
pub fn percent_encode(s: &str) -> String;                 // RFC 3986 unreserved kept, everything else %XX uppercase
pub fn parse_query(q: &str) -> Vec<(String, String)>;     // '+' = space, %XX decoded, order kept
pub fn pkce_challenge(verifier: &str) -> String;          // b64url(SHA-256(verifier)), no padding
// lib.rs: Core gains `google_flows: auth_google::Flows`; KNOWN_METHODS gains "auth.google.begin", "auth.session".
```

`auth.login` now writes `auth_method: "password"` and `email` = the trimmed email it sent. `auth.session` → `{user_id, device_id, email: <string or null>, auth_method: <stored value or "password">}`; `not_logged_in` without `session.json`; it is not a `needs_session` method and sends nothing.

`begin` in order: params must be an object with `purpose` `"sign_in"` or `"link"` (else `invalid_params`); `link` needs `session.json` (else `not_logged_in`); empty `cfg.google_client_id` → `not_configured` ("this build has no Google desktop client id"); every flow already in `flows` is marked cancelled and its listener dropped, and flows past their deadline are removed; `POST /v1/auth/nonce` with body `{}` and **no bearer**; the nonce must be 43 chars of `[A-Za-z0-9_-]` (else `server`); bind `127.0.0.1:0` non-blocking; `state` and `verifier` = 32 random bytes b64url each; `flow_id` = 16 random bytes b64url; `deadline = now + FLOW_TIMEOUT`; return `{flow_id, auth_url}` with exactly this layout (values through `percent_encode`):

```
{google_auth_url}?client_id={id}&redirect_uri={redirect_uri}&response_type=code&scope=openid%20email%20profile&state={state}&nonce={nonce}&code_challenge={challenge}&code_challenge_method=S256&prompt=select_account
```

- [ ] **Step 1: Write the failing tests.** Add to `tests/support/mod.rs`:

```rust
/// config.set extras pointing Google at the fake (`/fake-google/*`) with the fake's client.
pub fn google(fake: &FakeApi) -> Value;
/// Like `logged_out`, configured with `google(&fake)`.
pub fn google_logged_out() -> (Core, FakeApi, Dir);
/// Query of `url` as a map (through `shellx_core::auth_google::parse_query`).
pub fn query(url: &str) -> std::collections::HashMap<String, String>;
```

`tests/auth_google.rs`:

```rust
#[test] fn begin_returns_a_google_url_with_pkce_state_and_the_relay_nonce() {
    let (core, fake, _dir) = support::google_logged_out();
    let r = core.call("auth.google.begin", json!({"purpose": "sign_in"})).unwrap();
    assert_eq!(r["flow_id"].as_str().unwrap().len(), 22);
    let url = r["auth_url"].as_str().unwrap();
    assert!(url.starts_with(&format!("{}/fake-google/auth?client_id=fake-desktop-client&redirect_uri=", fake.base_url)));
    let q = support::query(url);
    assert_eq!((q["response_type"].as_str(), q["scope"].as_str()), ("code", "openid email profile"));
    assert_eq!((q["code_challenge_method"].as_str(), q["prompt"].as_str()), ("S256", "select_account"));
    assert_eq!((q["code_challenge"].len(), q["state"].len()), (43, 43));
    assert_eq!(q["nonce"], fake.issued_nonces()[0]);
    let port = q["redirect_uri"].strip_prefix("http://127.0.0.1:").unwrap().strip_suffix("/oauth2/callback").unwrap();
    assert!(port.parse::<u16>().unwrap() > 0);
    let nonce = &support::requests_to(&fake, "/v1/auth/nonce")[0];
    assert_eq!((nonce.method.as_str(), support::header(nonce, "Authorization")), ("POST", None));
}
#[test] fn default_google_endpoints_are_googles() {
    let cfg = shellx_core::Config::from_params(&json!({"api_base":"https://a.b","state_dir":"/tmp/sx"})).unwrap();
    assert_eq!(cfg.google_auth_url, "https://accounts.google.com/o/oauth2/v2/auth");
    assert_eq!(cfg.google_token_url, "https://oauth2.googleapis.com/token");
}
#[test] fn begin_requires_a_known_purpose_and_a_client_id() {
    // purpose "x" or missing -> invalid_params, nothing sent; google_client_id "" -> not_configured
}
#[test] fn link_needs_a_session() { /* {"purpose":"link"} logged out -> not_logged_in; fake.requests() empty */ }
#[test] fn google_urls_must_be_https_off_loopback() {
    // config.set with google_token_url "http://evil.example/token" -> invalid_params
}
#[test] fn config_debug_hides_the_google_client_secret() {
    // format!("{cfg:?}") does not contain "fake-desktop-secret"
}
```

`tests/auth.rs`:

```rust
#[test] fn login_records_password_and_the_email_in_the_session() {
    // session.json: auth_method == "password", email == "a@b.c"; auth.session returns the same plus user_id/device_id
}
#[test] fn auth_session_reads_old_files_as_password() {
    // write {"token":"t","user_id":"u","device_id":"d"} -> {"user_id":"u","device_id":"d","email":null,"auth_method":"password"}; no request sent
}
#[test] fn auth_session_without_a_session_is_not_logged_in() { /* logged_out() -> Err code "not_logged_in"; fake.requests() empty */ }
```

Unit tests in `src/auth_google.rs`:

```rust
#[test] fn percent_encode_keeps_only_unreserved() { assert_eq!(percent_encode("a b&c=d/é~-._"), "a%20b%26c%3Dd%2F%C3%A9~-._"); }
#[test] fn parse_query_decodes_percent_and_plus() {
    assert_eq!(parse_query("code=4%2F0Ab-x&state=s+t&e="),
               vec![("code".into(), "4/0Ab-x".into()), ("state".into(), "s t".into()), ("e".into(), String::new())]);
}
#[test] fn pkce_challenge_is_rfc7636_s256() {
    assert_eq!(pkce_challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM");
}
```

- [ ] **Step 2: Run to verify they fail.** Run: `(cd shellx-core && cargo test --locked --test auth_google --test auth)`. Expected: compile errors (`auth_google` module, `Config` fields and `support::google` missing).
- [ ] **Step 3: Commit the failing tests.** `git add shellx-core/tests && git commit -m "test(shellx-core): Google sign-in begin, session fields and auth.session"`
- [ ] **Step 4: Implement** the Interfaces above. Refactor `auth::login` to call `save_session`; make `Core::forget_refused_session` call `auth::forget_session_if(store, used, &self.auth_lock)`; dispatch `"auth.google.begin"` to `auth_google::begin(..., &self.google_flows, params)` and `"auth.session"` to `auth::session_info(store)`; add the two names to `KNOWN_METHODS`. Update the `SessionFile` literal in `api.rs:171` with `auth_method: None, email: None`.
- [ ] **Step 5: Run to verify they pass.** Run: `(cd shellx-core && cargo test --workspace --locked)`. Expected: `test result: ok` everywhere and no new compiler warning. Run `git diff --quiet -- shellx-core/Cargo.lock && echo lock-unchanged`. Expected: `lock-unchanged`.
- [ ] **Step 6: Commit.** `git add shellx-core/src shellx-core/tests && git commit -m "feat(shellx-core): auth.google.begin, auth.session and Google config"`

---

### Task 3: `auth.google.finish` and `auth.google.cancel`

**Files:**
- Modify: `shellx-core/src/auth_google.rs`
- Modify: `shellx-core/src/lib.rs` (`KNOWN_METHODS`, `dispatch`)
- Modify: `shellx-core/tests/support/mod.rs`
- Modify: `shellx-core/tests/auth_google.rs`

**Interfaces:**
- Consumes: Task 2 (`Flows`, `Flow`, `begin`, `post_form`, `save_session`, `forget_session_if`, API types).
- Produces:

```rust
pub fn finish(agent: &ureq::Agent, cfg: &Config, store: &StateStore, flows: &Flows, params: &Value, auth_lock: &Mutex<()>) -> Result<Value, CoreError>;
pub fn cancel(flows: &Flows, params: &Value) -> Result<Value, CoreError>; // {} also for an unknown flow_id; flow_id must be a string
/// Accepts on `listener` (non-blocking, polled every 50 ms) until a GET of CALLBACK_PATH arrives, the deadline
/// passes (google_timeout) or `cancelled` is set (google_cancelled). Returns the decoded `code`.
pub fn wait_for_callback(listener: &TcpListener, expected_state: &str, deadline: Instant, cancelled: &AtomicBool) -> Result<Zeroizing<String>, CoreError>;
pub const DONE_PAGE: &str;   // first page in "Loopback pages"
pub const FAILED_PAGE: &str; // second page
// KNOWN_METHODS gains "auth.google.finish", "auth.google.cancel".
```

`wait_for_callback` per accepted connection: `set_nonblocking(false)` (macOS hands accepted sockets the listener's non-blocking flag), 2 s read timeout, read at most 8 KiB up to `\r\n\r\n`; a non-GET → `405` and keep waiting; another path → `404` and keep waiting; on `CALLBACK_PATH`: `state` ≠ expected (or missing) → FAILED_PAGE + `google_state_mismatch`; an `error` param → FAILED_PAGE + `google_cancelled`; no `code` → FAILED_PAGE + `google_state_mismatch`; else DONE_PAGE and the code.

`finish` in order: `flow_id` string (else `invalid_params`); unknown id → `invalid_params` ("unknown flow_id"); a cancelled flow → remove it, `google_cancelled`; take the listener (`None` → `google_cancelled` if cancelled, else `invalid_params` "already finishing"); `wait_for_callback`; `post_form(cfg.google_token_url, [code, client_id, client_secret, redirect_uri, grant_type=authorization_code, code_verifier])` — any non-2xx → `invalid_credentials` (message names the status only), empty `id_token` → `server`; then `sign_in`: `POST /v1/auth/google {id_token, nonce, device}` with no bearer, `device` built exactly like `auth::login` (kind `desktop`); `link`: read the session (gone → `not_logged_in`) and `POST /v1/auth/google/link {id_token, nonce}` with its bearer, and on `unauthorized`/`http_401` call `auth::forget_session_if(store, <that token>, auth_lock)`; a response missing `token`, `user_id`, `device_id` or `email` → `server`; under `auth_lock`, `save_session` with `auth_method: Some("google")`, `email: Some(<relay email>)`, previous user from the old session; the flow entry is removed on every exit. Dispatch clears the shown fingerprints after a successful finish (like `auth.login`, `lib.rs:144-148`). `auth.google.*` never holds `auth_lock` while waiting.

- [ ] **Step 1: Write the failing tests.** Add to `tests/support/mod.rs`:

```rust
/// begin -> fake Google in a browser thread -> finish; finish's result.
pub fn google_sign_in(core: &Core, purpose: &str) -> Result<Value, shellx_core::CoreError> {
    let begun = core.call("auth.google.begin", json!({"purpose": purpose}))?;
    let url = begun["auth_url"].as_str().unwrap().to_string();
    let browser = std::thread::spawn(move || shellx_fake_api::browse(&url));
    let done = core.call("auth.google.finish", json!({"flow_id": begun["flow_id"]}));
    let _ = browser.join();
    done
}
```

Add to `tests/auth_google.rs` (`REG` = `json!({"name":"Mac A","platform":"macos","os_version":"15","app_version":"2.0.0"})`):

```rust
#[test] fn google_sign_in_through_the_browser_writes_a_google_session() {
    let (core, fake, dir) = support::google_logged_out();
    let r = support::google_sign_in(&core, "sign_in").unwrap();
    assert_eq!((r["email"].as_str(), r["auth_method"].as_str()), (Some("google-user@shellx.test"), Some("google")));
    for k in ["user_id", "device_id", "device_public_key_b64", "fingerprint"] { assert!(r[k].as_str().is_some_and(|s| !s.is_empty()), "{k}"); }
    assert!(r.get("token").is_none());
    let s: Value = serde_json::from_slice(&std::fs::read(dir.join("session.json")).unwrap()).unwrap();
    assert_eq!((s["auth_method"].as_str(), s["email"].as_str()), (Some("google"), Some("google-user@shellx.test")));
    assert_eq!(fake.token_auth_method(&fake.issued_token()).as_deref(), Some("google"));
    let t = &support::requests_to(&fake, "/fake-google/token")[0];
    assert_eq!(t.form["grant_type"], "authorization_code");
    assert_eq!(t.form["client_secret"], "fake-desktop-secret");
    assert_eq!(t.form["code_verifier"].len(), 43);
    assert!(t.form["code"].starts_with("4/"));
    assert_eq!(support::header(t, "Authorization"), None);
    let g = &support::requests_to(&fake, "/v1/auth/google")[0];
    assert_eq!(g.body["device"]["kind"], "desktop");
    assert_eq!(g.body["nonce"], json!(fake.issued_nonces()[0]));
    assert_eq!(support::header(g, "Authorization"), None);
    assert_eq!(core.call("machines.list", json!({})).unwrap()["machines"], json!([]));
}
#[test] fn the_loopback_closes_after_the_callback() {
    // begin; port from the auth URL's redirect_uri; browse + finish as in support::google_sign_in;
    // then std::net::TcpStream::connect(("127.0.0.1", port)).is_err()
}
#[test] fn a_wrong_state_is_google_state_mismatch() {
    // browse("{redirect_uri}?code=4%2Fx&state=wrong") in a thread -> finish Err "google_state_mismatch";
    // the browser got 200 with FAILED_PAGE; no /fake-google/token request; no session.json
}
#[test] fn the_browser_error_is_google_cancelled() { /* "{redirect_uri}?error=access_denied&state={state}" -> google_cancelled */ }
#[test] fn cancel_ends_a_waiting_finish() {
    // finish in a thread, then auth.google.cancel {flow_id} -> {} ; thread result google_cancelled within 2 s
}
#[test] fn cancel_before_finish_is_google_cancelled() { /* begin; cancel -> {}; finish -> Err "google_cancelled" at once; cancel of "unknown" -> {} */ }
#[test] fn waiting_past_the_deadline_is_google_timeout() {
    let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    l.set_nonblocking(true).unwrap();
    let t = std::time::Instant::now();
    let e = shellx_core::auth_google::wait_for_callback(&l, "s", t + std::time::Duration::from_millis(200),
        &std::sync::atomic::AtomicBool::new(false)).unwrap_err();
    assert_eq!(e.code, "google_timeout");
    assert!(t.elapsed() >= std::time::Duration::from_millis(200) && t.elapsed() < std::time::Duration::from_secs(2));
}
#[test] fn a_second_begin_cancels_the_first_flow() {
    // a = begin, b = begin: a's port refuses connections; finish(a) -> google_cancelled; sign-in through b succeeds
}
#[test] fn a_failed_token_exchange_is_invalid_credentials() { /* google_client_secret "wrong" -> invalid_credentials, no session.json */ }
#[test] fn a_password_account_email_answers_switch_from_signed_in_device() {
    // auth.login {"email":"google-user@shellx.test","password":"pw"} first; google sign_in -> switch_from_signed_in_device;
    // session.json still has auth_method "password"
}
#[test] fn link_switches_the_password_session_to_google_and_keeps_the_machine() {
    // login old@shellx.test, machines.register REG, old = fake.issued_token(); link ->
    // same user_id and device_id, email "google-user@shellx.test", auth_method "google"; !fake.token_is_live(&old);
    // machine.json kept; the /v1/auth/google/link request carried "Bearer {old}"; machines.list ok afterwards
}
#[test] fn link_conflicts_pass_email_in_use_and_identity_in_use() {
    // email_in_use: auth.login "google-user@shellx.test" (account A owns the email), then auth.login "b@shellx.test";
    //   link -> Err "email_in_use"; session.json still auth_method "password"
    // identity_in_use: set_google_account("x@shellx.test", "sub-x"); google sign_in; auth.logout; auth.login "c@shellx.test";
    //   link -> Err "identity_in_use"
}
#[test] fn a_refused_link_forgets_the_session_but_keeps_machine_and_key() {
    // login, register, fake.revoke_token(..) -> link Err "unauthorized"; no session.json; machine.json and device.key exist
}
#[test] fn google_sign_in_after_a_401_keeps_the_device_id_and_machine() {
    // google sign_in, register, revoke the token, machines.list -> "unauthorized" (machine.json, device.key kept);
    // google sign_in again -> same user_id and device_id; machines.list lists the machine with is_this_machine true
}
#[test] fn google_secrets_never_reach_results_or_errors() {
    // result and a state-mismatch error message contain none of: the issued token, "fake-desktop-secret",
    // the token request's code and code_verifier, the auth URL's state
}
```

- [ ] **Step 2: Run to verify they fail.** Run: `(cd shellx-core && cargo test --locked --test auth_google)`. Expected: compile error (`wait_for_callback` missing) or `unknown_method` failures.
- [ ] **Step 3: Commit the failing tests.** `git add shellx-core/tests && git commit -m "test(shellx-core): Google sign-in finish, cancel, link and 401"`
- [ ] **Step 4: Implement** `finish`, `cancel`, `wait_for_callback`, the two pages, the dispatch arms and the two `KNOWN_METHODS` names.
- [ ] **Step 5: Run to verify they pass.** Run: `(cd shellx-core && cargo test --workspace --locked)`. Expected: `test result: ok` everywhere and no new compiler warning.
- [ ] **Step 6: Commit.** `git add shellx-core/src shellx-core/tests && git commit -m "feat(shellx-core): auth.google.finish and auth.google.cancel over a loopback listener"`

---

### Task 4: `account.identities.*` and `links_apple_id`

**Files:**
- Create: `shellx-core/src/account.rs`
- Modify: `shellx-core/src/lib.rs` (`mod account`, `KNOWN_METHODS`, `needs_session` :60-62, `dispatch`)
- Modify: `shellx-core/src/phones.rs:31-42`
- Create: `shellx-core/tests/account.rs`
- Modify: `shellx-core/tests/phones.rs`

**Interfaces:**
- Consumes: Task 1 fake routes, Task 3 `support::google_sign_in`.
- Produces:

```rust
// account.rs (both need a session; `needs_session` now also matches "account.")
pub fn list_identities(agent: &ureq::Agent, cfg: &Config, store: &StateStore) -> Result<Value, CoreError>;
// GET /v1/account/identities -> {"identities":[{identity_id, provider, email, is_private_email, linked_via_device_name, created_at_unix}]}
// typed item with serde defaults (email "", is_private_email false, linked_via_device_name null, created_at_unix 0);
// items whose identity_id fails pairing_id_ok are dropped
pub fn remove_identity(agent: &ureq::Agent, cfg: &Config, store: &StateStore, params: &Value) -> Result<Value, CoreError>;
// identity_id must pass crate::pairing::pairing_id_ok (else invalid_params, nothing sent); DELETE /v1/account/identities/<id> -> {}
// phones.rs PendingItem gains: #[serde(default)] links_apple_id: bool (passed through to phones.pending)
// phones.rs pending() now requests GET /v2/phone-pairings?role=target&apple_links=1: relay plan 1A lists
// Apple-link requests only to callers that send apple_links=1 (so an old Mac never shows one without the
// warning). The fake-api mirrors this since Task 1: without apple_links=1 it omits Apple-link pairings.
// KNOWN_METHODS gains "account.identities.list", "account.identities.remove".
```

- [ ] **Step 1: Write the failing tests.** `tests/account.rs`:

```rust
#[test] fn identities_list_returns_the_relay_items() {
    // google sign_in; fake.add_identity(user, "apple", "a-sub", "x@privaterelay.appleid.com", true, Some("Phu's iPhone"));
    // list -> 2 items; google item email "google-user@shellx.test"; apple item is_private_email true,
    // linked_via_device_name "Phu's iPhone", created_at_unix > 0
}
#[test] fn identities_remove_sends_the_id_and_passes_relay_codes() {
    // remove apple -> {} and the list has 1 item; remove the google one -> last_google_identity;
    // unknown "id-0" -> identity_not_found; "../x" -> invalid_params with no new request
}
#[test] fn identities_need_a_session_and_a_401_forgets_it() {
    // logged out -> not_logged_in; after fake.revoke_token -> unauthorized and session.json removed, device.key kept
}
```

`tests/phones.rs`:

```rust
#[test] fn phones_pending_passes_links_apple_id() {
    // add_apple_link_phone_pairing -> item links_apple_id == true; add_phone_pairing -> links_apple_id == false
    // the fake-api saw the query apple_links=1 on that request (assert on the recorded query string)
}
#[test] fn fake_api_hides_apple_links_without_the_parameter() {
    // GET /v2/phone-pairings?role=target (no apple_links) -> the Apple-link pairing is absent, the plain one present
}
```

- [ ] **Step 2: Run to verify they fail.** Run: `(cd shellx-core && cargo test --locked --test account --test phones)`. Expected: `unknown_method` failures and a missing `links_apple_id`.
- [ ] **Step 3: Commit the failing tests.** `git add shellx-core/tests && git commit -m "test(shellx-core): sign-in methods and Apple-link pairing flag"`
- [ ] **Step 4: Implement** the Interfaces.
- [ ] **Step 5: Run to verify they pass.** Run: `(cd shellx-core && cargo test --workspace --locked)`. Expected: all `ok` and no new compiler warning.
- [ ] **Step 6: Commit.** `git add shellx-core/src shellx-core/tests && git commit -m "feat(shellx-core): account.identities.list/remove and links_apple_id"`

---

### Task 5: Non-interactive Google sign-in for the e2e harness

**Files:**
- Modify: `shellx-core/src/bin/shellx-core-cli.rs`
- Create: `shellx-core/tests/cli.rs`
- Modify: `scripts/shellx/remote-e2e/harness.py` (constants near :87, `Machine.config` :387-394, `login` :455-456, `start_api` :673-681, module doc :13-15)
- Modify: `tests/test_shellx_remote_harness.py`

**Interfaces:**
- Consumes: Tasks 2–3 (`auth.google.begin/finish/cancel`), Task 1 (fake Google, `SHELLX_FAKE_GOOGLE_EMAIL`).
- Produces: CLI-only pseudo-method `auth.google.e2e` (never in `KNOWN_METHODS`): `shellx-core-cli auth.google.e2e '{"purpose":"sign_in"}'` prints the `auth.google.finish` envelope. Python: `harness.FAKE_GOOGLE_CLIENT_ID = "fake-desktop-client"`, `harness.FAKE_GOOGLE_CLIENT_SECRET = "fake-desktop-secret"`; `Machine.login()` returns the finish result.

CLI algorithm: call `auth.google.begin` with the given JSON (an error envelope is printed as is); if `auth_url` does not start `http://127.0.0.1:` call `auth.google.cancel` and print `{"error":{"code":"invalid_params","message":"auth.google.e2e follows only a loopback fake Google"}}`, exit 1; else spawn a thread that GETs `auth_url` with its own `ureq` agent (`max_redirects(3)`, `http_status_as_error(false)`, `proxy(None)`), print the `auth.google.finish {flow_id}` envelope, join the thread.

- [ ] **Step 1: Write the failing tests.** `shellx-core/tests/cli.rs` (binary from `env!("CARGO_BIN_EXE_shellx-core-cli")`, an in-process `FakeApi`, `SHELLX_CORE_CONFIG` = api_base + state_dir + `support::google(&fake)`):

```rust
#[test] fn cli_google_e2e_signs_in_without_a_person() {
    // stdout last line {"ok":{..., "email":"google-user@shellx.test","auth_method":"google"}};
    // a second CLI run of machines.list prints {"ok":{"machines":[]}}
}
#[test] fn cli_google_e2e_refuses_a_real_google_url() {
    // config without google_auth_url (default https://accounts.google.com...) and google_client_id "x"
    // -> exit code 1, envelope error code "invalid_params"
}
```

`tests/test_shellx_remote_harness.py` (add `import json` and `from unittest import mock` if missing):

```python
class GoogleLogin(unittest.TestCase):
    def test_login_signs_in_through_the_fake_google_without_a_password(self):
        h = harness.Harness("/nonexistent/bin", "/nonexistent/core")
        try:
            machine, seen = h.machine("host1"), {}
            def run(argv, env=None, **_kwargs):
                seen["argv"], seen["env"] = argv, env
                return subprocess.CompletedProcess(argv, 0, '{"ok":{"auth_method":"google"}}\n', "")
            with mock.patch.object(harness.subprocess, "run", run):
                result = machine.login()
            self.assertEqual(seen["argv"][1:], ["auth.google.e2e", json.dumps({"purpose": "sign_in"})])
            config = json.loads(seen["env"]["SHELLX_CORE_CONFIG"])
            self.assertEqual(config["google_auth_url"], f"{h.api_base}/fake-google/auth")
            self.assertEqual(config["google_token_url"], f"{h.api_base}/fake-google/token")
            self.assertEqual(config["google_client_id"], harness.FAKE_GOOGLE_CLIENT_ID)
            self.assertEqual(config["google_client_secret"], harness.FAKE_GOOGLE_CLIENT_SECRET)
            self.assertNotIn(h.password, " ".join(seen["argv"]))
            self.assertEqual(result["auth_method"], "google")
        finally:
            h.close()
```

- [ ] **Step 2: Run to verify they fail.** Run: `(cd shellx-core && cargo test --locked --test cli)` and `python3 tests/test_shellx_remote_harness.py GoogleLogin`. Expected: the CLI prints `unknown_method`; Python fails with `AttributeError: ... FAKE_GOOGLE_CLIENT_ID` or the argv assertion.
- [ ] **Step 3: Commit the failing tests.** `git add shellx-core/tests/cli.rs tests/test_shellx_remote_harness.py && git commit -m "test(shellx): e2e harness signs in through the fake Google"`
- [ ] **Step 4: Implement** the CLI branch; in `harness.py` add the two constants, add `google_auth_url`, `google_token_url`, `google_client_id`, `google_client_secret` to `Machine.config`, make `login()` run `self.core("auth.google.e2e", purpose="sign_in")`, add `"SHELLX_FAKE_GOOGLE_EMAIL": EMAIL` to `start_api`'s env, and update the module doc's "password (auth.login)" sentence.
- [ ] **Step 5: Run to verify they pass.** Run: `(cd shellx-core && cargo test --workspace --locked) && python3 tests/test_shellx_remote_harness.py`. Expected: `test result: ok`; Python `OK`.
- [ ] **Step 6: Optional full e2e** (needs `cmux-relay`; the CI lane `bridge-e2e` runs it otherwise): `(cd cmux-tui && cargo build -p cmux-tui -p cmux-relay --locked) && (cd shellx-core && cargo build --workspace --locked) && SHELLX_E2E_BIN=$PWD/cmux-tui/target/debug SHELLX_E2E_CORE_BIN=$PWD/shellx-core/target/debug python3 tests/test_shellx_remote_e2e.py`. Expected: `OK`. If it cannot build here, record "remote e2e not run locally" for the hand-off.
- [ ] **Step 7: Commit.** `git add shellx-core/src/bin/shellx-core-cli.rs scripts/shellx/remote-e2e/harness.py && git commit -m "feat(shellx): remote e2e signs in with the fake Google instead of auth.login"`

---

### Task 6: Swift core client for Google sign-in and sign-in methods

**Files:**
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/ShellXCoreClient+Google.swift`
- Create: `Packages/Shared/ShellXBrand/Tests/ShellXRemoteCoreTests/ShellXCoreClientGoogleTests.swift`
- Modify: `Packages/Shared/ShellXBrand/Tests/ShellXRemoteCoreTests/ServiceTestSupport.swift` (`FakeRemoteCore` :6-133)

**Interfaces:**
- Consumes: contracts §3 RPC shapes.
- Produces (public, each with a DocC `///` line; all calls block on the FFI, call off main):

```swift
public enum GoogleSignInPurpose: String, Sendable { case signIn = "sign_in"; case link }
public struct GoogleSignInStart: Equatable, Sendable { public let flowID: String; public let authURL: URL }
public struct GoogleSignInResult: Equatable, Sendable { public let userID: String; public let deviceID: String; public let email: String; public let authMethod: String }
public struct AccountSignInMethod: Equatable, Sendable, Identifiable {
    public let id: String; public let provider: String; public let email: String; public let isPrivateEmail: Bool
    public let linkedViaDeviceName: String?; public let createdAt: Date
    public var isApple: Bool { provider == "apple" }
}
extension ShellXCoreClient {
    public func beginGoogleSignIn(purpose: GoogleSignInPurpose) throws -> GoogleSignInStart // bad_response unless auth_url parses with scheme https
    public func finishGoogleSignIn(flowID: String) throws -> GoogleSignInResult
    public func cancelGoogleSignIn(flowID: String) throws
    public func signInMethods() throws -> [AccountSignInMethod]
    public func removeSignInMethod(id: String) throws
}
```

`FakeRemoteCore` gains `let googleEmail = Locked("g@shellx.test")`, `let identities = Locked<[JSONValue]>([])`, `account.` in its `needsSession` prefixes, and cases: `auth.google.begin` (invalid_params unless purpose `sign_in`/`link`; `link` while `!signedIn` → `not_logged_in`; else `{flow_id: "flow-1", auth_url: "https://accounts.google.com/o/oauth2/v2/auth?client_id=test"}`), `auth.google.finish` (sets `signedIn`; `{user_id: userID, device_id: "d_1", device_public_key_b64: "AAAA", fingerprint: ownFingerprint, email: googleEmail, auth_method: "google"}`), `auth.google.cancel` (`{}`), `account.identities.list` (`{identities}`), `account.identities.remove` (drops the item with that `identity_id`, `{}`), and `auth.session` (`not_logged_in` while `!signedIn`, else `{user_id: userID, device_id: "d_1", email: sessionEmail, auth_method: sessionAuthMethod}` from two new fields `let sessionEmail = Locked<String?>(nil)` and `let sessionAuthMethod = Locked("password")`; `auth.login` sets them to the params' email and `"password"`, `auth.google.finish` to `googleEmail` and `"google"`). Its existing `failures`/`down`/`holdNext` apply.

- [ ] **Step 1: Write the failing tests** (`ShellXCoreClientGoogleTests.swift`, a `StubCore` like `ShellXCoreClientPhonesTests.swift:5-17`):

```swift
@Test func beginSendsThePurposeAndReturnsTheURL() throws  // method "auth.google.begin", params ["purpose": .string("link")], flowID "f1", authURL https
@Test func beginRefusesANonHTTPSURL()                       // auth_url "http://evil.test/x" -> ShellXCoreError code "bad_response"
@Test func finishReturnsTheGoogleAccount() throws           // email/authMethod decoded; params ["flow_id": .string("f1")]
@Test func cancelAndRemoveSendTheirIDs() throws             // "auth.google.cancel" ["flow_id"], "account.identities.remove" ["identity_id"]
@Test func signInMethodsDecodeTheRelayItems() throws        // apple row: isApple, isPrivateEmail, linkedViaDeviceName "Phu's iPhone", createdAt 100; null device -> nil
```

- [ ] **Step 2: Run to verify they fail.** Run: `swift test --package-path Packages/Shared/ShellXBrand --filter ShellXCoreClientGoogleTests`. Expected: compile error (`beginGoogleSignIn` not found).
- [ ] **Step 3: Commit the failing tests.** `git add Packages/Shared/ShellXBrand/Tests/ShellXRemoteCoreTests/ShellXCoreClientGoogleTests.swift && git commit -m "test(shellx): core client Google and sign-in method calls"`
- [ ] **Step 4: Implement** the file and the `FakeRemoteCore` cases.
- [ ] **Step 5: Run to verify they pass.** Run: `swift test --package-path Packages/Shared/ShellXBrand`. Expected: all tests passed.
- [ ] **Step 6: Commit.** `git add Packages/Shared/ShellXBrand && git commit -m "feat(shellx): core client for Google sign-in and sign-in methods"`

---

### Task 7: `ShellXAccount` signs in with Google, switches, lists methods, handles server sign-out

**Files:**
- Modify: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/ShellXAccount.swift`
- Modify: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/ShellXRemoteService.swift` (`signIn` :151-166, `bootstrap` :248-257, `handleSignedOut` :508-512)
- Modify: `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXBrand.swift:17-22`
- Modify: `Packages/Shared/ShellXBrand/Tests/ShellXRemoteCoreTests/ShellXAccountTests.swift`
- Modify: `Packages/Shared/ShellXBrand/Tests/ShellXBrandTests/ShellXBrandTests.swift:40-61`

**Interfaces:**
- Consumes: Task 6 types and client calls; `ShellXRemoteService.isSignedOutCode` (`ShellXRemoteServiceSupport.swift:114-117`).
- Produces:

```swift
// ShellXBrand
public static let deleteAccountURL = URL(string: "https://shellx.pro/privacy#delete-account")!
// ShellXRemoteService
/// Runs after a session ends because the relay refused the token or no session is left at launch; never after signOut().
public var onSessionEndedByServer: (@MainActor () -> Void)?
func beginSignedInSession(userID: String) async   // the tail of signIn(email:password:) from its first `guard !terminated`
// ShellXAccount
public struct Identity { /* existing */ public let authMethod: String?   // nil in old records
    public init(userID: String, email: String, signedInAt: Date? = nil, authMethod: String? = nil)
    public var usesPassword: Bool { authMethod == nil || authMethod == "password" } }
public enum GoogleStep: Equatable, Sendable { case idle; case waiting(GoogleSignInPurpose) }
public private(set) var googleStep: GoogleStep
public private(set) var signInMethods: [AccountSignInMethod]
public private(set) var signInMethodsErrorCode: String?
public private(set) var removingSignInMethodIDs: Set<String>
@ObservationIgnored public var onSignedOutByServer: (@MainActor () -> Void)?
public static let googleSwitchOfferedKey = "shellx.account.googleSwitchOffered"
public init(service: ShellXRemoteService, openURL: @escaping @MainActor (URL) -> Bool = { _ in false })
public func signInWithGoogle(purpose: GoogleSignInPurpose) async throws -> Identity
public func cancelGoogleSignIn() async
public func refreshSignInMethods() async
public func removeSignInMethod(id: String) async
public func takeGoogleSwitchOffer(defaults: UserDefaults) -> Bool
/// Launch check against `auth.session` (contracts §10; local, no network): copies the core's email and auth method
/// into the shown identity (saved to account.json when they differ); `not_logged_in` while an identity is shown runs
/// the server sign-out handler; any other error changes nothing.
public func reconcileWithSession() async
// internal, beside LoginReply (ShellXRemoteServiceSupport.swift:10-14)
struct SessionReply: Decodable, Sendable { let user_id: String; let device_id: String; let email: String?; let auth_method: String }
```

Behavior: `init` sets `service.onSessionEndedByServer` to a handler that, when `identity != nil`, removes `account.json`, sets `identity = nil`, clears the method state and calls `onSignedOutByServer`. The service calls the hook at the end of `handleSignedOut(_:)` and in `bootstrap()`'s signed-out branch before the dev-credentials sign-in. `signInWithGoogle`: `googleStep != .idle` → throw `ShellXCoreError(code: "google_in_progress")`; gate on → `await service.prepareLocal()`; `try await service.ensureConfigured()`; begin (off main) → `googleStep = .waiting(purpose)`; `openURL(authURL) == false` → cancel the flow, throw `browser_unavailable`; finish (off main; `googleStep` back to `.idle` on every exit); `.signIn` with the gate on → `await service.beginSignedInSession(userID:)`; save `Identity(userID:, email: result.email, signedInAt: Date(), authMethod: "google")` like `signIn(email:password:)`; `.link` → `await refreshSignInMethods()`; a thrown signed-out code runs the server sign-out handler then rethrows. `cancelGoogleSignIn` cancels the waiting flow id (no-op when idle). `refreshSignInMethods` keeps the last list on failure and sets `signInMethodsErrorCode` (cleared on success). `removeSignInMethod` inserts the id in `removingSignInMethodIDs`, removes, refreshes; a failure sets `signInMethodsErrorCode`. `takeGoogleSwitchOffer` is true once per `defaults` while `identity?.usesPassword == true` and records the key. `signOut()` also clears the method state.

- [ ] **Step 1: Write the failing tests** (add to `ShellXAccountTests.swift`; a `@MainActor final class Opened { var urls: [URL] = [] }` box records `openURL`; every test except the browser-cannot-open one builds `ShellXAccount(service: rig.service, openURL: { opened.urls.append($0); return true })`; "signed in" below means `ServiceRig(signedIn: false)` followed by `account.signIn(email: "dev@shellx.test", password: "pw")`):

```swift
@MainActor @Test func googleSignInOpensTheBrowserAndSavesTheGoogleIdentity() async throws
    // gate off: methods == ["config.set", "auth.google.begin", "auth.google.finish"]; opened == [the auth URL];
    // identity.email "g@shellx.test", authMethod "google", !usesPassword; a relaunched ShellXAccount reads the same identity
@MainActor @Test func googleSignInWithTheGateOnStartsTheSession() async throws   // service.isSignedIn; hostState reaches hostConnected
@MainActor @Test func googleSignInFailsWhenTheBrowserCannotOpen() async          // openURL false -> "browser_unavailable"; last params of "auth.google.cancel" == ["flow_id": "flow-1"]; identity nil
@MainActor @Test func cancelGoogleSignInCancelsTheWaitingFlow() async
    // holdNext = "auth.google.finish"; failures["auth.google.finish"] = ["google_cancelled"]; start signInWithGoogle in a Task;
    // until { rig.core.isHoldingCall }; googleStep == .waiting(.signIn); await cancelGoogleSignIn() -> lastParams("auth.google.cancel")
    // == ["flow_id": "flow-1"]; releaseHeldCall(); the Task throws "google_cancelled"; googleStep == .idle; identity nil
@MainActor @Test func switchToGoogleKeepsTheSessionAndUpdatesTheIdentity() async throws
    // gate on, password sign-in first; link -> begin params purpose "link"; count("machines.register") unchanged;
    // identity.authMethod "google", email "g@shellx.test"; "account.identities.list" called
@MainActor @Test func oldAccountRecordsReadAsPassword() throws                    // account.json without authMethod -> usesPassword
@MainActor @Test func googleSwitchIsOfferedOnceForAPasswordAccount() async throws // UserDefaults(suiteName: UUID().uuidString)!: true, then false; Google identity -> false
@MainActor @Test func signInMethodsListAndRemoveAnAppleID() async               // list 2 items; remove "a1" -> removing contains "a1" during the call, list refreshed to 1
@MainActor @Test func aFailedListKeepsTheLastListAndShowsTheCode() async        // down["account.identities.list"] = "network" -> list kept, code "network"
@MainActor @Test func serverSignOutForgetsTheIdentityAndAsksForSignIn() async throws
    // gate on, signed in; down["machines.list"] = "unauthorized"; advance(machinesInterval, waitingFor: "machines.list");
    // until { identity == nil }; account.json gone; onSignedOutByServer called once
@MainActor @Test func reconcileTakesEmailAndMethodFromTheCoreSession() async throws
    // gate off, signed in; sessionEmail = "new@shellx.test", sessionAuthMethod = "google"; reconcileWithSession() ->
    // identity.email "new@shellx.test", authMethod "google"; a relaunched ShellXAccount reads the same
@MainActor @Test func reconcileWithoutASessionForgetsTheIdentityAndAsksForSignIn() async throws
    // signed in, then core.signedIn = false; reconcileWithSession() -> identity nil, account.json gone, onSignedOutByServer once;
    // down["auth.session"] = "io" instead -> identity kept
```

Add to `ShellXBrandTests.identity()`: `#expect(ShellXBrand.deleteAccountURL.absoluteString == "https://shellx.pro/privacy#delete-account")`.

- [ ] **Step 2: Run to verify they fail.** Run: `swift test --package-path Packages/Shared/ShellXBrand --filter "ShellXAccount|ShellXBrandTests"`. Expected: compile errors (`signInWithGoogle`, `deleteAccountURL` missing).
- [ ] **Step 3: Commit the failing tests.** `git add Packages/Shared/ShellXBrand/Tests && git commit -m "test(shellx): account Google sign-in, switch, methods and server sign-out"`
- [ ] **Step 4: Implement** the Interfaces; make `signIn(email:password:)` call `beginSignedInSession(userID:)`.
- [ ] **Step 5: Run to verify they pass.** Run: `swift test --package-path Packages/Shared/ShellXBrand`. Expected: all tests passed, including the existing `ShellXRemoteServiceTests`, `PhoneOnlyServiceTests`, `LinkHostingTests`.
- [ ] **Step 6: Commit.** `git add Packages/Shared/ShellXBrand && git commit -m "feat(shellx): account signs in with Google and switches password sessions"`

---

### Task 8: `GoogleSignInModel` and sign-in error labels

**Files:**
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteUI/GoogleSignInModel.swift`
- Modify: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteUI/SignInErrorMessage.swift`
- Create: `Packages/Shared/ShellXBrand/Tests/ShellXRemoteUITests/GoogleSignInModelTests.swift`
- Modify: `Packages/Shared/ShellXBrand/Tests/ShellXRemoteUITests/ShellXRemoteUITests.swift:209-218`

**Interfaces:**
- Consumes: `GoogleSignInPurpose` (Task 6), `ShellXCoreError`.
- Produces:

```swift
public struct SignInErrorLabels: Equatable, Sendable {
    public let credentials, network, timeout, stateMismatch, switchFromSignedInDevice, emailInUse, identityInUse, browser: String
    public init(credentials: String, network: String, timeout: String, stateMismatch: String,
                switchFromSignedInDevice: String, emailInUse: String, identityInUse: String, browser: String)
    public static let english: SignInErrorLabels   // the en column of the String tables
}
extension SignInErrorMessage {
    // text(forCode:) maps invalid_credentials, network, google_timeout, google_state_mismatch,
    // switch_from_signed_in_device, email_in_use, identity_in_use, browser_unavailable; any other code is returned as is
    public static func isCancellation(_ error: any Error) -> Bool   // ShellXCoreError code "google_cancelled"
}
@MainActor @Observable public final class GoogleSignInModel {
    public enum Phase: Equatable, Sendable { case ready, waiting, signedIn(email: String) }
    public private(set) var phase: Phase
    public private(set) var errorText: String?
    public let purpose: GoogleSignInPurpose
    @ObservationIgnored public var onFinished: (@MainActor (Bool) -> Void)?
    public init(purpose: GoogleSignInPurpose, labels: SignInErrorLabels,
                signIn: @escaping @MainActor () async throws -> String, cancel: @escaping @MainActor () async -> Void)
    @discardableResult public func start() -> Task<Void, Never>?   // only from .ready: phase .waiting at once, errorText nil
    @discardableResult public func cancel() -> Task<Void, Never>?  // calls onFinished(false) once; while waiting also runs `cancel`
    public func finish()                                            // only in .signedIn: onFinished(true)
}
```

Outcomes of the sign-in task: success → `.signedIn(email:)`; a cancellation, or any error after `cancel()` → `.ready`, `errorText` nil; any other error → `.ready` with `SignInErrorMessage.text(for:labels:)`.

- [ ] **Step 1: Write the failing tests** (`GoogleSignInModelTests.swift`; a small `@MainActor` gate class holding a `CheckedContinuation<String, any Error>` lets a test keep `signIn` pending):

```swift
@MainActor @Test func startShowsWaitingThenTheEmail() async      // phase .waiting right after start(); after await task: .signedIn("g@shellx.test"); onFinished not yet; finish() -> [true]
@MainActor @Test func startTwiceRunsOneFlow() async              // second start() returns nil; signIn ran once
@MainActor @Test func cancelWhileWaitingCancelsTheFlowAndCloses() async  // onFinished == [false] at once; cancel closure ran once; errorText nil after both tasks
@MainActor @Test func googleCancelledFromTheBrowserStaysOpenWithoutError() async // signIn throws google_cancelled -> .ready, errorText nil, onFinished empty
@MainActor @Test func failureShowsTheMessageAndAllowsRetry() async  // switch_from_signed_in_device -> labels.switchFromSignedInDevice; start() again runs signIn again
@MainActor @Test func aTimeoutShowsItsMessageAndAllowsRetry() async // google_timeout -> labels.timeout
```

Update `signInErrorMapping` to the new init and add: `google_state_mismatch`, `email_in_use`, `identity_in_use`, `browser_unavailable` → their labels; `isCancellation(ShellXCoreError(code: "google_cancelled", message: ""))` is true and false for `network`.

- [ ] **Step 2: Run to verify they fail.** Run: `swift test --package-path Packages/Shared/ShellXBrand --filter "GoogleSignInModelTests|signInErrorMapping"`. Expected: compile errors.
- [ ] **Step 3: Commit the failing tests.** `git add Packages/Shared/ShellXBrand/Tests/ShellXRemoteUITests && git commit -m "test(shellx): Google sign-in sheet model"`
- [ ] **Step 4: Implement** the file and the labels.
- [ ] **Step 5: Run to verify they pass.** Run: `swift test --package-path Packages/Shared/ShellXBrand`. Expected: all tests passed.
- [ ] **Step 6: Commit.** `git add Packages/Shared/ShellXBrand && git commit -m "feat(shellx): Google sign-in sheet model and error labels"`

---

### Task 9: Google's official "G" mark, the Google Sans licence gate and the release guard

**Files:**
- Create: `scripts/shellx/fetch-google-branding.sh` (the USER runs it in Step 7; the executor writes it and never runs it)
- Create: `scripts/shellx/check-google-branding.py`
- Create: `tests/test_shellx_google_branding.py`
- Create: `windows/shellx-app/assets/google/README.md`
- Modify: `scripts/shellx/release/make-dmg.sh` (right after the usage line :15)
- Modify: `scripts/shellx/release/build-windows-cross.sh` (right after `cd "$repo"` :29)
- Added by the USER's download and committed in Step 8: `Assets.xcassets/GoogleG.imageset/Contents.json`, `Assets.xcassets/GoogleG.imageset/google-g.png`, `windows/shellx-app/assets/google/google-g.png`; only when the licence gate passes, `Resources/Fonts/GoogleSans-Medium.ttf`, `Resources/Fonts/GoogleSans-OFL.txt`, `windows/shellx-app/assets/fonts/GoogleSans-Medium.ttf`, `windows/shellx-app/assets/fonts/GoogleSans-OFL.txt`.

**Interfaces:**
- Produces (Tasks 10 and 15 use these names):
  - Mac image set `GoogleG` (one 80×80 px PNG `google-g.png`, drawn at 20×20 pt). Mac font `Resources/Fonts/GoogleSans-Medium.ttf`: PostScript name `GoogleSans-Medium`, typographic family "Google Sans", weight 500; the existing `ATSApplicationFontsPath` folder registers it (`Resources/Fonts` is a folder reference, so a new file needs no project change).
  - Windows `windows/shellx-app/assets/google/google-g.png` (the same crop) and `windows/shellx-app/assets/fonts/GoogleSans-Medium.ttf` (typographic family "Google Sans", legacy family "Google Sans Medium", weight 500).
  - `python3 scripts/shellx/check-google-branding.py [--root DIR] [--git-rev REV]`: the root defaults to `$SHELLX_GOOGLE_BRANDING_ROOT`, else the repo root; `--git-rev` reads every file from that commit (`git -C ROOT show REV:<path>`) instead of the working tree.

Check rules: the three mark files must exist; `Contents.json` must parse and name `google-g.png`; each `google-g.png` must start with the PNG signature and carry an 80×80 IHDR. Each platform's font pair (`Resources/Fonts/…` is `mac`, `windows/shellx-app/assets/fonts/…` is `windows`) is either absent (stdout `font: <platform> uses the system font`) or complete: the TTF starts with `00 01 00 00` and `GoogleSans-OFL.txt` beside it contains `SIL Open Font License, Version 1.1`; a TTF without that licence file is `bad`. Exit 0 printing `google branding: OK`; otherwise exit 1 with one stderr line per problem, `missing: <path>` or `bad: <path> (<reason>)`.

Fetch script, in order (`set -euo pipefail`; repo root from the script's own path; a `mktemp -d` work dir removed on exit; each step prints what it does):
1. `curl -fsSL -o "$work/signin-assets.zip" https://developers.google.com/static/identity/images/signin-assets.zip` (the link under h3 "Download Pre-Approved Brand Icons"), then `unzip -q` into `$work/assets`.
2. Source `"$work/assets/Android + Web/PNG @4x/Light/Theme=Light, Show text=No, Shape=Square, Platform=Android+Web@4x.png"`; stop unless `sips -g pixelWidth -g pixelHeight` reports 160×160; `sips -c 80 80 --cropOffset 40 40 "$src" --out "$work/google-g.png"` (the official 20×20 "G" box sits at 10,10 of the 40×40 icon, so at 4× it is 80×80 at 40,40; nothing is scaled or recolored).
3. Write `Assets.xcassets/GoogleG.imageset/google-g.png` and this `Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "google-g.png",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

4. Copy the crop to `windows/shellx-app/assets/google/google-g.png`.
5. Licence gate: `curl -fsSL -o "$work/OFL.txt" https://raw.githubusercontent.com/google/fonts/main/ofl/googlesans/OFL.txt`. Only if it contains `SIL Open Font License, Version 1.1`: read `https://fonts.google.com/download/list?family=Google%20Sans`, drop its first line (`)]}'`), take the `manifest.fileRefs[]` entry whose `filename` is `static/GoogleSans-Medium.ttf`, download its `url`, require the TrueType magic `00 01 00 00`, and install the TTF plus `$work/OFL.txt` renamed `GoogleSans-OFL.txt` into `Resources/Fonts/` and `windows/shellx-app/assets/fonts/`. Otherwise print `font: licence not confirmed; the button keeps the system font` and install no font file.
6. Run `python3 scripts/shellx/check-google-branding.py` and exit with its status.

Release hooks (each runs before anything else in its script and ends it with exit 1 when the check fails): `make-dmg.sh`, right after its usage line, runs `python3 "$(dirname "$0")/../check-google-branding.py"`; `build-windows-cross.sh`, right after `cd "$repo"`, runs `python3 scripts/shellx/check-google-branding.py --git-rev HEAD` (it builds the committed HEAD). Both add `--root "$SHELLX_GOOGLE_BRANDING_ROOT"` when that variable is set.

`windows/shellx-app/assets/google/README.md` keeps the folder in git (Task 15's `build.rs` watches it) and says: `google-g.png` is the centre 80×80 crop of `Android + Web/PNG @4x/Light/Theme=Light, Show text=No, Shape=Square, Platform=Android+Web@4x.png` from Google's `signin-assets.zip`, made by `scripts/shellx/fetch-google-branding.sh`; it is Google's trademark, used under Google's Sign in with Google branding guidelines and not covered by the GPL; another app downloads its own copy from Google.

- [ ] **Step 1: Write the failing tests** in `tests/test_shellx_google_branding.py` (unittest; helpers: `png(w, h)` returns the 8-byte PNG signature plus an IHDR chunk of that size; `complete(root)` writes the three mark files and, for both platforms, a TTF starting `00 01 00 00` with a `GoogleSans-OFL.txt` containing `SIL Open Font License, Version 1.1`; `run(*args, env=None)` runs the check through `subprocess.run` and returns rc, stdout and stderr):

```python
class GoogleBrandingCheck(unittest.TestCase):
    def test_an_empty_tree_names_every_missing_mark_file(self):
        # rc 1; stderr has "missing: Assets.xcassets/GoogleG.imageset/Contents.json",
        # "missing: Assets.xcassets/GoogleG.imageset/google-g.png" and "missing: windows/shellx-app/assets/google/google-g.png"
    def test_a_complete_tree_passes(self):  # rc 0; stdout has "google branding: OK"
    def test_fonts_are_optional_but_never_without_their_licence(self):
        # marks only -> rc 0, stdout has "font: mac uses the system font" and "font: windows uses the system font";
        # adding Resources/Fonts/GoogleSans-Medium.ttf alone -> rc 1,
        # stderr "bad: Resources/Fonts/GoogleSans-Medium.ttf (no SIL OFL 1.1 licence beside it)"
    def test_a_mark_that_is_not_80_px_is_bad(self):  # a 40x40 Mac google-g.png -> rc 1, "bad: Assets.xcassets/GoogleG.imageset/google-g.png"
    def test_git_rev_reads_the_commit_not_the_working_tree(self):
        # temp git repo: commit complete(); delete the working files -> --git-rev HEAD rc 0; commit their removal -> rc 1
    def test_make_dmg_refuses_without_the_mark(self):
        # env SHELLX_GOOGLE_BRANDING_ROOT=<empty dir>: scripts/shellx/release/make-dmg.sh /nonexistent/ShellX.app 1.8.0 <tmp>
        # -> rc 1, stderr names the missing Mac mark and lacks "app bundle not found" (the guard runs first)
    def test_windows_cross_build_refuses_without_the_mark(self):
        # env SHELLX_GOOGLE_BRANDING_ROOT=<temp git repo with one empty commit>: scripts/shellx/release/build-windows-cross.sh <tmp>
        # -> rc 1, stderr "missing: windows/shellx-app/assets/google/google-g.png"
```

- [ ] **Step 2: Run to verify they fail.** Run: `python3 tests/test_shellx_google_branding.py`. Expected: errors (`scripts/shellx/check-google-branding.py` does not exist).
- [ ] **Step 3: Commit the failing tests.** `git add tests/test_shellx_google_branding.py && git commit -m "test(shellx): desktop releases refuse a Google button without the official mark"`
- [ ] **Step 4: Implement** the check, the fetch script (`chmod +x`), both release hooks and the README. Do not run the fetch script, do not download any Google file yourself, never copy `ios/cmux/Assets.xcassets/GoogleLogo.imageset/google-logo.svg` or any other logo found in `ios/`, `Packages/` or `Sources/`, and never draw a "G".
- [ ] **Step 5: Run to verify they pass.** Run: `python3 tests/test_shellx_google_branding.py && bash -n scripts/shellx/fetch-google-branding.sh && python3 scripts/shellx/check-google-branding.py; echo "rc=$?"`. Expected: `OK`, no syntax error, then the three `missing:` lines, both `font: … uses the system font` lines and `rc=1` (nothing downloaded yet).
- [ ] **Step 6: Commit.** `git add scripts/shellx/fetch-google-branding.sh scripts/shellx/check-google-branding.py scripts/shellx/release/make-dmg.sh scripts/shellx/release/build-windows-cross.sh windows/shellx-app/assets/google/README.md && git commit -m "feat(shellx): fetch and check Google's official sign-in assets before a desktop release"`
- [ ] **Step 7: USER — accept Google's terms and download.** Ask the user to read https://developers.google.com/identity/branding-guidelines (and the Google terms it links) and, if they accept them, run in this session:

```
! cd /Users/lehuuphu/Documents/myProjects/shellx/.worktrees/signin-1b-desktop && bash scripts/shellx/fetch-google-branding.sh
```
Expected: it ends with `google branding: OK`. Meanwhile continue with Task 10 and the tasks after it: without the files both apps show a text-only "Continue with Google" button in the system font, and both release scripts refuse to build.
- [ ] **Step 8: Commit the user's download.** Once the user has run it: `python3 scripts/shellx/check-google-branding.py` prints `google branding: OK`; open `Assets.xcassets/GoogleG.imageset/google-g.png` with the Read tool and confirm the full-colour "G" on white. Then `git add Assets.xcassets/GoogleG.imageset windows/shellx-app/assets/google/google-g.png` plus whichever of the four font files exist, and `git commit -m "chore(shellx): Google's official G mark and Google Sans Medium (OFL 1.1), downloaded by the user"`. If the user has not run it by Task 16, record that in the hand-off: desktop releases stay blocked until this commit lands.

---

### Task 10: Mac sign-in sheet shows only the branded "Continue with Google" button

**Files:**
- Modify: `Sources/ShellX/Remote/UI/SignInSheet.swift` (remove `SignInSheetModel` :6-54; rewrite `SignInSheet` :58-112; presenter :145-203)
- Create: `Sources/ShellX/Remote/UI/GoogleSignInButton.swift` (wire it with `./scripts/wire-app-sources.py Sources/ShellX/Remote/UI/GoogleSignInButton.swift`, which edits `cmux.xcodeproj/project.pbxproj`)
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteUI/GoogleSignInButtonSpec.swift`
- Create: `Packages/Shared/ShellXBrand/Tests/ShellXRemoteUITests/GoogleSignInButtonSpecTests.swift`
- Modify: `Sources/ShellX/Remote/UI/RemoteUISnapshot.swift:28-38`
- Modify: `Sources/ShellX/Remote/UI/ShellXRemoteServicing.swift:28-30`
- Modify: `Sources/ShellX/Remote/UI/ShellXRemoteFixtureService.swift:181-195`
- Modify: `Sources/ShellX/Remote/UI/ShellXRemoteUIActions.swift:60-63`
- Modify: `Sources/ShellX/ShellXAccountFlow.swift`
- Modify: `Sources/AppDelegate.swift:1735-1738`
- Modify: `Sources/AboutLicenseContent.swift:30-35`, `cmuxTests/ShellXAboutTests.swift:12-29`
- Modify: `Resources/Localizable.xcstrings`, `scripts/localization-allowed-omissions.json` (only if an identity record is needed)
- Modify: `tests/test_shellx_vi.py`

**Interfaces:**
- Consumes: `GoogleSignInModel`, `SignInErrorLabels` (Task 8); `ShellXAccount.signInWithGoogle/cancelGoogleSignIn/onSignedOutByServer/takeGoogleSwitchOffer/reconcileWithSession` (Task 7); image set `GoogleG` and the face `GoogleSans-Medium` (Task 9; either may be absent).
- Produces:

```swift
// ShellXRemoteUI (import SwiftUI): Google's custom-button rules with the Light theme (Global Constraints)
public struct GoogleSignInButtonSpec: Equatable, Sendable {
    public static let fill: UInt32 = 0xFFFFFF, stroke: UInt32 = 0x747775, text: UInt32 = 0x1F1F1F
    public static let height = 40.0, cornerRadius = 4.0, strokeWidth = 1.0, logoSize = 20.0
    public static let leadingPadding = 12.0, logoGap = 10.0, trailingPadding = 12.0
    public static let fontSize = 14.0, lineHeight = 20.0, fontPostScriptName = "GoogleSans-Medium"
    /// Google Sans Medium 14 when that face is registered, else the system font at 14 medium (licence gate).
    public static func font(isAvailable: (String) -> Bool) -> Font
}
// App: the branded button
struct GoogleSignInButton: View {
    let title: String          // remote.signin.google
    let action: () -> Void
    /// The official mark (image set `GoogleG`) is in the app bundle; without it the button is text-only.
    static var hasMark: Bool { NSImage(named: "GoogleG") != nil }
}
// SignInSheetPresenter: one sheet at a time (an open one is brought to front)
func present(model: GoogleSignInModel, preferredWindow: NSWindow? = nil)
func present(service: any ShellXRemoteServicing, preferredWindow: NSWindow? = nil)  // .signIn over the service's calls
// ShellXRemoteServicing: signIn(email:password:) is replaced by
func signInWithGoogle() async throws -> String   // the account email
func cancelGoogleSignIn() async
// ShellXAccountFlow
static let shared = ShellXAccountFlow(account: ShellXAccount(service: .shared, openURL: { NSWorkspace.shared.open($0) }))
func startSignIn()                                // present a .signIn model over the account
func startGoogleSwitch()                          // present a .link model over the account
func prepareAtLaunch(defaults: UserDefaults)      // onSignedOutByServer -> startSignIn(); then a Task that awaits
                                                  // reconcileWithSession() and, when takeGoogleSwitchOffer(defaults:), startGoogleSwitch()
```

`GoogleSignInButton` draws exactly the spec, in the Light colours whatever the appearance: an `HStack` with spacing `logoGap` holding `Image("GoogleG")` (`.resizable()`, `.interpolation(.high)`, 20×20) when `hasMark`, then the title in `GoogleSignInButtonSpec.font(isAvailable: { NSFont(name: $0, size: 14) != nil })` and `text`; `leadingPadding`/`trailingPadding`, height 40, a `RoundedRectangle(cornerRadius: 4)` filled with `fill` and `.strokeBorder(stroke, lineWidth: 1)` (inside stroke); `.buttonStyle(.plain)`, `.keyboardShortcut(.defaultAction)`, accessibility label = title. Without the mark it is the same button with the text only (no logo, no gap).

Sheet layout (width 340, dark, `ShellXPalette`, `ShellXSheetButtonStyle` kept for the other buttons): title `remote.signin.title` (`.signIn`) or `remote.signin.switch.title` (`.link`); `.link` adds `remote.signin.switch.intro`; `.ready` shows `GoogleSignInButton(title: remote.signin.google)` centred under the title (the default action); `.waiting` shows, in its place, a small `ProgressView` + `remote.signin.waiting` and `remote.signin.browserHint`; `.signedIn` shows `remote.signin.signedInAs` with the email and a primary `remote.signin.done` (`ShellXSheetButtonStyle`); `errorText` in `ShellXPalette.error`; the bottom row has `common.cancel` (cancel action, hidden in `.signedIn`). `AboutLicenseContent.attributions` gains `Attribution(name: "Google Sans", license: "OFL-1.1", url: URL(string: "https://github.com/googlefonts/googlesans"))`. `SignInErrorLabels.localized` uses the Table keys. The fixture's `signInWithGoogle` waits 400 ms, signs in like the old `signIn` and returns `"fixture@shellx.dev"`. `presentSignIn()` falls back to `ShellXAccountFlow.shared.startSignIn()` when `ShellXRemoteUIModel.shared.service` is nil. `AppDelegate` calls `ShellXAccountFlow.shared.prepareAtLaunch(defaults: .standard)` right before the `ShellXRemoteGate.startsAtLaunch` check, only when `!MacSentryStartupPolicy.isRunningUnderXCTest(environment: env)`.

- [ ] **Step 1: Write the failing tests.** In `tests/test_shellx_vi.py` `VietnameseCatalogTests` (add `def en(self, key)` beside `vi` at :197):

```python
def test_google_sign_in_strings_read_naturally(self):
    expected = {  # key: (en, vi) from the plan's String tables
        "remote.signin.google": ("Continue with Google", "Tiếp tục với Google"),
        "remote.signin.waiting": ("Waiting for Google…", "Đang chờ Google…"),
        "remote.signin.switch.title": ("Switch to Google sign-in", "Chuyển sang đăng nhập Google"),
        "remote.signin.error.credentials": ("Google sign-in didn't work. Try again.", "Đăng nhập Google không thành công. Hãy thử lại."),
        "remote.signin.error.switchFromSignedInDevice": (
            "This email already has a ShellX account. Open ShellX on a device that is still signed in, go to Settings › Account › Switch to Google sign-in, then try again.",
            "Email này đã có tài khoản ShellX. Mở ShellX trên một máy đang đăng nhập, vào Cài đặt › Tài khoản › Chuyển sang đăng nhập Google, rồi thử lại."),
    }
    for key, (en, vi) in expected.items():
        self.assertEqual((self.en(key), self.vi(key)), (en, vi), key)
```

`GoogleSignInButtonSpecTests.swift` (values from the branding page's h4 "Color", "Font", "Padding" and the Android + Web asset geometry):

```swift
@Test func lightThemeIsGooglesLightTheme() {
    #expect(GoogleSignInButtonSpec.fill == 0xFFFFFF); #expect(GoogleSignInButtonSpec.stroke == 0x747775); #expect(GoogleSignInButtonSpec.text == 0x1F1F1F)
}
@Test func metricsAreGooglesAndroidAndWebButton() {
    typealias S = GoogleSignInButtonSpec
    #expect([S.height, S.cornerRadius, S.strokeWidth, S.logoSize, S.leadingPadding, S.logoGap,
             S.trailingPadding, S.fontSize, S.lineHeight] == [40, 4, 1, 20, 12, 10, 12, 14, 20])
}
@Test func googleSansOnlyWhenItsFaceIsRegistered() {
    #expect(GoogleSignInButtonSpec.font(isAvailable: { $0 == "GoogleSans-Medium" }) == .custom("GoogleSans-Medium", size: 14))
    #expect(GoogleSignInButtonSpec.font(isAvailable: { _ in false }) == .system(size: 14, weight: .medium))
}
```

`cmuxTests/ShellXAboutTests.swift`: `aboutCreditsUpstreamAndAssets` expects `names.contains("Google Sans")`; `attributionsCarryTheirLicenses` expects `licenses["Google Sans"] == "OFL-1.1"`.

- [ ] **Step 2: Run to verify they fail.** Run: `python3 tests/test_shellx_vi.py VietnameseCatalogTests.test_google_sign_in_strings_read_naturally; swift test --package-path Packages/Shared/ShellXBrand --filter GoogleSignInButtonSpecTests`. Expected: Python FAIL (`(None, None) != ('Continue with Google', …)`); Swift compile error (`GoogleSignInButtonSpec` not found).
- [ ] **Step 3: Commit the failing tests.** `git add tests/test_shellx_vi.py Packages/Shared/ShellXBrand/Tests/ShellXRemoteUITests/GoogleSignInButtonSpecTests.swift cmuxTests/ShellXAboutTests.swift && git commit -m "test(shellx): Google sign-in strings, button spec and Google Sans credit"`
- [ ] **Step 4: Implement** the Interfaces, `GoogleSignInButton` and the sheet with every `remote.signin.*` row of the String tables; wire the new app file with `./scripts/wire-app-sources.py Sources/ShellX/Remote/UI/GoogleSignInButton.swift`.
- [ ] **Step 5: Localize.** Run `./scripts/localize-changes --base develop`, fill every row of the printed work packet (`vi` exactly from the tables; translate de, fr, ar, es, zh-Hant, zh-Hans, ko, ja), run it again. Expected last line: `Localization ready: changed work is complete and the strict catalog validator passed.`
- [ ] **Step 6: Run to verify they pass.** Run: `python3 tests/test_shellx_vi.py && python3 scripts/localization_catalog.py check && ./scripts/wire-app-sources.py --check && swift test --package-path Packages/Shared/ShellXBrand && scripts/shellx/test-app.sh ShellXPhonePairingCoordinatorTests ShellXAboutTests`. Expected: `OK`, no catalog errors, exit 0 from `--check`, Swift tests passed, `** TEST SUCCEEDED **` (the app target compiles with the new sheet and button).
- [ ] **Step 7: Look at it (do not commit).** Write a throwaway cmuxTests file that hosts `SignInSheet` in an `NSHostingView`, renders each phase with `cacheDisplay(in:to:)` into a PNG under `$TMPDIR`; run `./scripts/sync-test-wiring`, then `scripts/shellx/test-app.sh <ThatSuite>`; look at the PNGs (with Task 9's files in place: a white 40 pt button, grey 1 px border, the colour "G" 12 pt from the left edge, dark text; without them: the same button, text only); delete the file and run `./scripts/sync-test-wiring` again. Expected: `git status` shows no change from it.
- [ ] **Step 8: Commit.** `git add Sources/ShellX Sources/AppDelegate.swift Sources/AboutLicenseContent.swift Packages/Shared/ShellXBrand/Sources/ShellXRemoteUI/GoogleSignInButtonSpec.swift cmux.xcodeproj/project.pbxproj Resources/Localizable.xcstrings scripts/localization-allowed-omissions.json && git commit -m "feat(shellx): Mac signs in only with a branded Continue with Google button"`

---

### Task 11: Settings › Account: switch row, sign-in methods, delete link

**Files:**
- Modify: `Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Account/AccountFlow.swift` (protocol :16-97, extension :109-115)
- Modify: `Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/AccountSection.swift:31-40`
- Create: `Sources/ShellX/ShellXAccountDetailView.swift`
- Modify: `Sources/ShellX/ShellXAccountFlow.swift`
- Modify: `cmux.xcodeproj/project.pbxproj` (through `./scripts/wire-app-sources.py Sources/ShellX/ShellXAccountDetailView.swift`)
- Modify: `Resources/Localizable.xcstrings`, `tests/test_shellx_vi.py`

**Interfaces:**
- Consumes: `ShellXAccount` (Task 7), `ShellXBrand.deleteAccountURL`, `ShellXAccountFlow.startGoogleSwitch()` (Task 10).
- Produces:

```swift
// CmuxSettingsUI AccountFlow (requirement + default nil in the existing extension; import SwiftUI)
/// Host rows under the identity row (ShellX: sign-in methods). Nil shows nothing.
var accountDetailContent: AnyView? { get }
// AccountSection: inside the card's VStack, after the team picker: `if let detail = accountFlow?.accountDetailContent { Divider(); detail }`
// App
struct ShellXAccountDetailView: View {
    let account: ShellXAccount
    let onSwitchToGoogle: @MainActor () -> Void
    let openURL: @MainActor (URL) -> Void
}
// ShellXAccountFlow.accountDetailContent: nil while signed out, else AnyView(ShellXAccountDetailView(...))
```

View content top to bottom (styling like `AccountIdentityCard`: `.cmuxFont(size: 13, weight: .medium)` titles, 11 pt `.secondary` subtitles, `.controlSize(.small)` buttons, 14 pt horizontal / 10 pt vertical padding): when `identity.usesPassword`, a row with `remote.signin.switch.title`, `remote.signin.switch.intro` and button `remote.signin.switch.button`; header `settings.account.methods.title`; one row per method — Google: `settings.account.methods.google` + email; Apple: `settings.account.methods.apple` + email or `settings.account.methods.hiddenEmail`, a second line `settings.account.methods.addedFrom` when `linkedViaDeviceName` is set, and button `settings.account.methods.remove` (disabled while its id is in `removingSignInMethodIDs`); `settings.account.methods.error` with the code when `signInMethodsErrorCode` is set; a borderless button `settings.account.deleteAccount` opening `ShellXBrand.deleteAccountURL`. `.task { await account.refreshSignInMethods() }`.

- [ ] **Step 1: Write the failing test** in `tests/test_shellx_vi.py`:

```python
def test_account_settings_strings_read_naturally(self):
    expected = {
        "settings.account.methods.title": ("Sign-in methods", "Cách đăng nhập"),
        "settings.account.methods.google": ("Google account", "Tài khoản Google"),
        "settings.account.methods.apple": ("Apple ID", "ID Apple"),
        "settings.account.methods.addedFrom": ("Added from %@", "Thêm từ %@"),
        "settings.account.deleteAccount": ("Delete Account…", "Xóa tài khoản…"),
    }
    for key, (en, vi) in expected.items():
        self.assertEqual((self.en(key), self.vi(key)), (en, vi), key)
```

- [ ] **Step 2: Run to verify it fails.** Run: `python3 tests/test_shellx_vi.py VietnameseCatalogTests.test_account_settings_strings_read_naturally`. Expected: FAIL.
- [ ] **Step 3: Commit the failing test.** `git add tests/test_shellx_vi.py && git commit -m "test(shellx): Settings account method strings in en and vi"`
- [ ] **Step 4: Implement** the hook, the view (with every `settings.account.*` row of the String tables) and wire the new file with `./scripts/wire-app-sources.py Sources/ShellX/ShellXAccountDetailView.swift`.
- [ ] **Step 5: Localize** as in Task 10 Step 5. Expected: `Localization ready: …`.
- [ ] **Step 6: Run to verify it passes.** Run: `python3 tests/test_shellx_vi.py && python3 scripts/localization_catalog.py check && ./scripts/wire-app-sources.py --check && swift test --package-path Packages/macOS/CmuxSettingsUI && scripts/shellx/test-app.sh ShellXPhonePairingCoordinatorTests`. Expected: `OK`, no catalog errors, exit 0 from `--check`, package tests passed, `** TEST SUCCEEDED **`.
- [ ] **Step 7: Look at it (do not commit)** with the throwaway render test of Task 10 Step 7 for `ShellXAccountDetailView` (password identity with one Google and one Apple row).
- [ ] **Step 8: Commit.** `git add Packages/macOS/CmuxSettingsUI/Sources Sources/ShellX cmux.xcodeproj/project.pbxproj Resources/Localizable.xcstrings scripts/localization-allowed-omissions.json && git commit -m "feat(shellx): Settings account lists sign-in methods and offers the Google switch"`

---

### Task 12: Apple-link warning and errors on the pairing sheet, and "phone" wording

**Files:**
- Modify: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/ShellXCoreClient+Phones.swift` (`PhonePairingRequest` :6-23, `pendingPhonePairings` :62-75)
- Modify: `Packages/Shared/ShellXBrand/Tests/ShellXRemoteCoreTests/ShellXCoreClientPhonesTests.swift`
- Modify: `Sources/ShellX/Remote/Link/ShellXPhonePairingCoordinator.swift` (`Candidate` :72-81, construction :329-330)
- Modify: `Sources/ShellX/Remote/UI/PhonePairingSheet.swift` (:15-17, :62-73, :90, `candidateCard` :99-140)
- Modify: `Sources/ShellX/Sidebar/SidebarMachineHeaderCellView.swift:181`
- Modify: `Sources/NotificationsPage.swift:136-137`, `Sources/Update/UpdateTitlebarAccessory.swift:2565-2586`
- Modify: `Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/MobileSection.swift:548-558`
- Modify: `Packages/macOS/CmuxSettingsUI/Tests/CmuxSettingsUITests/MobileSectionShellXLinkTests.swift:195`
- Modify: `cmuxTests/ShellXPhonePairingCoordinatorTests.swift` (:20-38 style, :468)
- Modify: `Resources/Localizable.xcstrings`, `tests/test_shellx_vi.py`

**Interfaces:**
- Consumes: Task 4 (`links_apple_id` in `phones.pending`).
- Produces:

```swift
// PhonePairingRequest gains `public let linksAppleID: Bool` and init param `linksAppleID: Bool = false` (last);
// decoded from `links_apple_id: Bool?` (absent = false)
// Candidate gains `var linksAppleID = false`, copied from the request
// PhonePairingSheet
static func appleLinkNotice(for candidate: ShellXPhonePairingCoordinator.Candidate) -> String?  // remote.phonePairing.appleLink text, nil otherwise
```

`candidateCard` shows the notice (12 pt, `ShellXPalette.text`, `fixedSize(horizontal: false, vertical: true)`) under the request line when non-nil.

Approving an Apple-link request can now fail in two new ways (relay plan 1A): 409 `identity_in_use` (that Apple ID already signs in to another ShellX account) shows the new key `remote.phonePairing.error.appleIdInUse` (a new `identity_in_use` case in `ShellXPhonePairingCoordinator.message(for:)`, `:551-559`) — en "This Apple ID already signs in to another ShellX account.", vi "ID Apple này đã dùng để đăng nhập một tài khoản ShellX khác." (the tables' "ID Apple"); 410 `pairing_expired` keeps today's text: `message(for:)` has no case for it, so the sheet shows `remote.phonePairing.error` with the code ("Something went wrong (pairing_expired)"). Add a coordinator test for each: `testApproveAppleLinkIdentityInUseShowsTheNotice` (`errorText` is the new key's text), `testApproveExpiredAppleLinkShowsExpired` (`errorText` is `String(format: String(localized: "remote.phonePairing.error", defaultValue: "Something went wrong (%@)"), "pairing_expired")`). Change the eight "phone" keys to the new en values in every call site's `defaultValue` (both call sites of each `notifications.forwardToPhone.*` key) and in the test at `ShellXPhonePairingCoordinatorTests.swift:468`.

- [ ] **Step 1: Write the failing tests.**

`ShellXCoreClientPhonesTests.swift`:

```swift
@Test func pendingDecodesLinksAppleID() throws  // "links_apple_id":true -> linksAppleID true; field absent -> false
```

`cmuxTests/ShellXPhonePairingCoordinatorTests.swift`:

```swift
@Test func testAppleLinkRequestShowsTheAppleIDNotice() async throws {
    // like testValidProofBecomesCandidate, with PhonePairingRequest(..., linksAppleID: true):
    // candidates[0].linksAppleID; PhonePairingSheet.appleLinkNotice(for: candidates[0]) ==
    //   String(localized: "remote.phonePairing.appleLink", defaultValue: "<en from the table>");
    // a normal request's candidate -> appleLinkNotice == nil
}
```

`MobileSectionShellXLinkTests.swift:195`: `#expect(pairing.title == "Pair Phone")`.

`tests/test_shellx_vi.py`:

```python
def test_phone_pairing_says_phone(self):
    expected = {  # the eight keys of the "phone" table: (en new, vi new)
        "remote.phonePairing.menu": ("Pair Phone…", "Ghép cặp điện thoại…"),
        "remote.phonePairing.title": ("Pair Phone", "Ghép cặp điện thoại"),
        # ... the other six rows exactly
    }
    for key, (en, vi) in expected.items():
        self.assertEqual((self.en(key), self.vi(key)), (en, vi), key)
        self.assertNotIn("iPhone", en, key)
```

- [ ] **Step 2: Run to verify they fail.** Run: `swift test --package-path Packages/Shared/ShellXBrand --filter pendingDecodesLinksAppleID; swift test --package-path Packages/macOS/CmuxSettingsUI --filter MobileSectionShellXLinkTests; python3 tests/test_shellx_vi.py VietnameseCatalogTests.test_phone_pairing_says_phone`. Expected: compile error (no `linksAppleID`), `"Pair iPhone" == "Pair Phone"` failure, Python FAIL.
- [ ] **Step 3: Commit the failing tests.** `git add Packages/Shared/ShellXBrand/Tests Packages/macOS/CmuxSettingsUI/Tests cmuxTests/ShellXPhonePairingCoordinatorTests.swift tests/test_shellx_vi.py && git commit -m "test(shellx): Apple-link pairing notice and phone wording"`
- [ ] **Step 4: Implement** the Interfaces, the notice and the eight renames.
- [ ] **Step 5: Localize** as in Task 10 Step 5 (the eight changed keys, `remote.phonePairing.appleLink` and `remote.phonePairing.error.appleIdInUse`). Expected: `Localization ready: …`.
- [ ] **Step 6: Run to verify they pass.** Run: `swift test --package-path Packages/Shared/ShellXBrand && swift test --package-path Packages/macOS/CmuxSettingsUI && python3 tests/test_shellx_vi.py && python3 scripts/localization_catalog.py check && scripts/shellx/test-app.sh ShellXPhonePairingCoordinatorTests`. Expected: all passed, `OK`, no catalog errors, `** TEST SUCCEEDED **`.
- [ ] **Step 7: Commit.** `git add Packages Sources cmuxTests Resources/Localizable.xcstrings scripts/localization-allowed-omissions.json && git commit -m "feat(shellx): Apple-link warning on the pairing sheet; say phone, not iPhone"`

---

### Task 13: Windows core API wrappers, strings and the Google button spec

**Files:**
- Modify: `windows/shellx-model/src/core_api.rs` (types near :76-128, wrappers after :216, tests :275-498)
- Modify: `windows/shellx-model/src/strings.rs` (`Str` :33-139, `ALL` :141-232, `t` :236-421 incl. `FontCredits` :306 and :397, helpers after :512, tests :514-745)
- Create: `windows/shellx-model/src/google_button.rs`
- Modify: `windows/shellx-model/src/lib.rs:3-18` (`pub mod google_button;`)

**Interfaces:**
- Consumes: contracts §3 RPC shapes; the String tables; the Global Constraints' Google button values.
- Produces:

```rust
// google_button.rs: Google's custom-button rules, Light theme, the same values as the Mac's GoogleSignInButtonSpec
pub const FILL: u32 = 0xFFFFFF;
pub const STROKE: u32 = 0x747775;
pub const TEXT: u32 = 0x1F1F1F;
pub const HEIGHT: f32 = 40.0;
pub const CORNER_RADIUS: f32 = 4.0;
pub const STROKE_WIDTH: f32 = 1.0;
pub const LOGO_SIZE: f32 = 20.0;
pub const PAD_LEFT: f32 = 12.0;
pub const LOGO_GAP: f32 = 10.0;
pub const PAD_RIGHT: f32 = 12.0;
pub const FONT_SIZE: f32 = 14.0;
pub const LINE_HEIGHT: f32 = 20.0;
pub const FONT_FAMILY: &str = "Google Sans";            // typographic family of the static Medium face
pub const FONT_FAMILY_LEGACY: &str = "Google Sans Medium"; // its legacy (name ID 1) family, tried second
pub const FONT_WEIGHT: f32 = 500.0;
// strings.rs: Str::FontCredits becomes "JetBrains Mono, Space Grotesk, Google Sans — SIL OFL 1.1" in both languages
// core_api.rs
#[derive(Clone, Copy, Debug, PartialEq, Eq)] pub enum GooglePurpose { SignIn, Link }
impl GooglePurpose { pub fn as_str(self) -> &'static str }   // "sign_in" | "link"
#[derive(Clone, PartialEq, Eq, Deserialize)] pub struct GoogleBegin { pub flow_id: String, pub auth_url: String } // Debug shows flow_id only
#[derive(Clone, PartialEq, Eq, Deserialize)] pub struct GoogleSignIn { pub user_id: String, pub device_id: String,
    pub device_public_key_b64: String, pub fingerprint: String, pub email: String, pub auth_method: String } // Debug hides email
#[derive(Clone, PartialEq, Eq, Deserialize)] pub struct SessionInfo { pub user_id: String, pub device_id: String,
    #[serde(default)] pub email: Option<String>, pub auth_method: String }                                   // Debug hides email
#[derive(Clone, Debug, PartialEq, Eq, Deserialize)] pub struct SignInMethod { pub identity_id: String, pub provider: String,
    #[serde(default)] pub email: String, #[serde(default)] pub is_private_email: bool,
    #[serde(default)] pub linked_via_device_name: Option<String>, #[serde(default)] pub created_at_unix: u64 }
impl SignInMethod { pub fn is_apple(&self) -> bool }
pub fn google_begin(core: &dyn CoreCall, purpose: GooglePurpose) -> Result<GoogleBegin, CoreErr>;
pub fn google_finish(core: &dyn CoreCall, flow_id: &str) -> Result<GoogleSignIn, CoreErr>;
pub fn google_cancel(core: &dyn CoreCall, flow_id: &str) -> Result<(), CoreErr>;
pub fn session_info(core: &dyn CoreCall) -> Result<SessionInfo, CoreErr>;                // "auth.session"
pub fn list_sign_in_methods(core: &dyn CoreCall) -> Result<Vec<SignInMethod>, CoreErr>;  // "account.identities.list"
pub fn remove_sign_in_method(core: &dyn CoreCall, identity_id: &str) -> Result<(), CoreErr>;
// strings.rs: 20 new Str variants (the "Win" column) in Str, ALL and both arms of t(); helpers:
pub fn added_from(lang: Lang, device: &str) -> String;
pub fn sign_in_methods_error(lang: Lang, code: &str) -> String;
/// None for google_cancelled; the mapped string for the codes in the tables; else login_failed(lang, code).
pub fn google_error(lang: Lang, code: &str) -> Option<String>;
```

- [ ] **Step 1: Write the failing tests.** `core_api.rs`:

```rust
#[test] fn google_calls_send_their_params_and_parse() {
    // google_begin(Link) sends ("auth.google.begin", {"purpose":"link"}); google_finish sends {"flow_id":"f1"} and parses email;
    // google_cancel sends {"flow_id":"f1"}; session_info parses {"user_id":"u","device_id":"d","email":null,"auth_method":"password"};
    // list_sign_in_methods parses an apple row (is_apple, is_private_email, linked_via_device_name); remove sends {"identity_id":"a1"}
}
#[test] fn google_values_hide_urls_and_emails_in_debug() {
    // format!("{:?}", GoogleBegin{..auth_url "https://x/?state=S"}) lacks "state=S"; GoogleSignIn/SessionInfo Debug lack the email
}
```

`strings.rs`: extend `sign_in_strings_match_the_mac` with a `pairs` table `(Str, vi, en)` for all 20 new variants, exactly the tables' values, plus

```rust
assert_eq!(added_from(Lang::Vi, "Phu's iPhone"), "Thêm từ Phu's iPhone");
assert_eq!(added_from(Lang::En, "Phu's iPhone"), "Added from Phu's iPhone");
assert_eq!(sign_in_methods_error(Lang::En, "network"), "Sign-in methods: something went wrong (network)");
assert_eq!(sign_in_methods_error(Lang::Vi, "network"), "Cách đăng nhập: có lỗi xảy ra (network)");
```

add `#[test] fn google_error_maps_codes()` (`google_cancelled` → `None`; `switch_from_signed_in_device` → `t(.., SwitchFromSignedInDevice)`; `network` → `RelayUnreachable`; `rate_limited` → `Some(login_failed(lang, "rate_limited"))`), assert `t(lang, Str::FontCredits) == "JetBrains Mono, Space Grotesk, Google Sans — SIL OFL 1.1"` for both languages, and change `all_has_no_duplicates` to `assert_eq!(Str::ALL.len(), 109)`.

`google_button.rs` (a `#[cfg(test)] mod tests` written before the constants exist):

```rust
#[test] fn google_button_matches_the_mac_and_the_branding_page() {
    assert_eq!((FILL, STROKE, TEXT), (0xFFFFFF, 0x747775, 0x1F1F1F));
    assert_eq!([HEIGHT, CORNER_RADIUS, STROKE_WIDTH, LOGO_SIZE, PAD_LEFT, LOGO_GAP, PAD_RIGHT, FONT_SIZE, LINE_HEIGHT],
               [40.0, 4.0, 1.0, 20.0, 12.0, 10.0, 12.0, 14.0, 20.0]);
    assert_eq!((FONT_FAMILY, FONT_FAMILY_LEGACY, FONT_WEIGHT), ("Google Sans", "Google Sans Medium", 500.0));
}
```

- [ ] **Step 2: Run to verify they fail.** Run: `(cd windows && cargo test --locked -p shellx-model)`. Expected: compile errors (`google_begin`, `Str::ContinueWithGoogle`, `google_button::FILL` missing).
- [ ] **Step 3: Commit the failing tests** (the `mod tests` edits and the test-only `google_button.rs` with its `lib.rs` line, before any implementation). `git add windows/shellx-model/src && git commit -m "test(shellx-windows): Google core calls, sign-in strings and button spec"`
- [ ] **Step 4: Implement** the Interfaces.
- [ ] **Step 5: Run to verify they pass.** Run: `(cd windows && cargo test --locked -p shellx-model)`. Expected: `test result: ok` and no new compiler warning.
- [ ] **Step 6: Commit.** `git add windows/shellx-model/src && git commit -m "feat(shellx-windows): Google core calls, sign-in strings and button spec"`

---

### Task 14: Windows account flow: Google sign-in, switch, session, methods, server sign-out

**Files:**
- Modify: `windows/shellx-model/src/account.rs` (`AccountEvent` :31-53, `AccountAction` :55-63, Debug :65-104, `AccountFlow` :106-149, `reset_session` :186-193, `ListResult` :206-274, tests :376-952)

**Interfaces:**
- Consumes: Task 13 types.
- Produces:

```rust
pub const DELETE_ACCOUNT_URL: &str = "https://shellx.pro/privacy#delete-account";
// AccountEvent gains
GoogleRequested(GooglePurpose),
GoogleBegun { purpose: GooglePurpose, result: Result<GoogleBegin, CoreErr> },
GoogleFinished { flow_id: String, result: Result<GoogleSignIn, CoreErr> },
GoogleCancelRequested,
SessionResult(Result<SessionInfo, CoreErr>),
SignInMethodsRequested,
SignInMethodsResult(Result<Vec<SignInMethod>, CoreErr>),
RemoveSignInMethodRequested(String),
SignInMethodRemoved { identity_id: String, result: Result<(), CoreErr> },
// AccountAction gains
CallGoogleBegin(GooglePurpose), OpenBrowser(String), CallGoogleFinish(String), CallGoogleCancel(String),
CallSession, CallListSignInMethods, CallRemoveSignInMethod(String),
// AccountFlow accessors
pub fn google_in_flight(&self) -> Option<GooglePurpose>;
pub fn email(&self) -> Option<&str>;
pub fn auth_method(&self) -> Option<&str>;
pub fn needs_google_switch(&self) -> bool;                 // LoggedIn && auth_method == Some("password")
pub fn sign_in_methods(&self) -> Option<&[SignInMethod]>;
pub fn removing_sign_in_method(&self) -> Option<&str>;
pub fn take_signed_out_by_server(&mut self) -> bool;       // true once after a server sign-out
```

Rules (one test each below): `GoogleRequested(SignIn)` only when `accepts_login()` and no Google flow runs → state `LoggingIn`, `login_in_flight`, `[CallGoogleBegin(SignIn)]`; `GoogleRequested(Link)` only when `needs_google_switch()` and no flow runs → state unchanged, ticks go on; `GoogleBegun` Ok for the running flow → `[OpenBrowser(url), CallGoogleFinish(flow_id)]`; `GoogleBegun` Ok after a cancel → `[CallGoogleCancel(flow_id)]` only; begin/finish errors: SignIn → `Error(e)` (`google_cancelled` → `LoggedOut`), Link → `notice` (`google_cancelled` → nothing); `GoogleFinished` for an unknown flow id → ignored; SignIn success → store email/auth_method, `[CallList]` like `LoginResult(Ok)`; Link success → store email/auth_method, `[CallListSignInMethods]`; `GoogleCancelRequested` while waiting → `[CallGoogleCancel(flow_id)]`, before begin answers → flow dropped and state back to `LoggedOut` (SignIn); entering `LoggedIn` from a `ListResult` with no email → `[.., CallSession]` once per session; `SessionResult(Ok)` stores email/auth_method, `Err` is ignored; a `ListResult` error `unauthorized`/`http_401`/`not_logged_in` while `LoggedIn` → `LoggedOut` and sets the server sign-out flag (`not_logged_in` outside `LoggedIn` keeps today's behaviour, no flag); `SignInMethodsRequested` only while `LoggedIn`; one removal at a time; removal Ok → `[CallListSignInMethods]`, Err → `notice`; `reset_session` also clears the Google flow, email, auth_method, methods, removal and the session-requested mark. The manual `Debug` of both enums never prints the auth URL or an email (`OpenBrowser("<auth url>")`).

- [ ] **Step 1: Write the failing tests** (in `account.rs` tests; reuse `m`, `net`, `logged_in`):

```rust
// begun(id) = GoogleBegun { purpose, result: Ok(GoogleBegin { flow_id: id, auth_url: "https://accounts.google.com/x" }) }
#[test] fn google_sign_in_runs_begin_browser_finish_then_lists() {
    // LoggedOut; GoogleRequested(SignIn) -> [CallGoogleBegin(SignIn)], state LoggingIn, login_in_flight(), google_in_flight() == Some(SignIn);
    // begun("f1") -> [OpenBrowser(url), CallGoogleFinish("f1")]; GoogleFinished{"f1", Ok(email "g@x", auth_method "google")} -> [CallList];
    // ListResult(Ok([me])) -> LoggedIn, actions without CallSession; email() == Some("g@x"); google_in_flight() == None
}
#[test] fn google_cancel_while_waiting_cancels_and_returns_to_signed_out() {
    // ... begun("f1"); GoogleCancelRequested -> [CallGoogleCancel("f1")]; GoogleFinished{"f1", Err(google_cancelled)} -> [],
    // state LoggedOut (not Error), google_in_flight() == None
}
#[test] fn google_cancel_before_begin_answers_cancels_the_returned_flow() {
    // GoogleRequested(SignIn); GoogleCancelRequested -> [], state LoggedOut; begun("f1") -> [CallGoogleCancel("f1")] (no OpenBrowser)
}
#[test] fn google_failure_is_an_error_and_can_be_retried() {
    // GoogleFinished Err(switch_from_signed_in_device) -> Error(e) with that code; GoogleRequested(SignIn) again -> [CallGoogleBegin(SignIn)]
}
#[test] fn a_second_google_request_while_one_runs_is_ignored() { /* second GoogleRequested(SignIn) and GoogleRequested(Link) -> [] */ }
#[test] fn a_stale_google_finish_is_ignored() { /* waiting on "f1": GoogleFinished{"f0", Ok(..)} -> [], state still LoggingIn, email() None */ }
#[test] fn switch_to_google_keeps_the_session_and_updates_the_method() {
    // logged_in(); SessionResult(Ok(password, "old@x")) -> needs_google_switch(); GoogleRequested(Link) -> [CallGoogleBegin(Link)];
    // Tick(16_000) still contains CallList; GoogleBegun -> [OpenBrowser(url), CallGoogleFinish("f1")];
    // GoogleFinished Ok(email "new@x") -> email() == Some("new@x"), auth_method() == Some("google"), !needs_google_switch(),
    // actions == [CallListSignInMethods], state LoggedIn
}
#[test] fn switch_failure_keeps_the_session_and_sets_the_notice() {
    // link flow; GoogleFinished Err(email_in_use) -> state LoggedIn, notice() code "email_in_use", needs_google_switch() still true
}
#[test] fn link_is_refused_unless_signed_in_with_a_password() {
    // LoggedOut -> GoogleRequested(Link) == []; LoggedIn after SessionResult(auth_method "google") -> GoogleRequested(Link) == []
}
#[test] fn entering_logged_in_asks_the_session_once() {
    // Started; ListResult(Ok([me])) actions contain CallSession; the next ListResult(Ok([me])) does not;
    // SessionResult(Err(net())) -> email() None, no state change; SessionResult(Ok(email "a@b.c", "password")) -> email() == Some("a@b.c")
}
#[test] fn server_sign_out_shows_sign_in() {
    // logged_in(); ListResult(Err(unauthorized)) -> LoggedOut, take_signed_out_by_server() true then false;
    // same for http_401 and not_logged_in; LogoutRequested + LogoutResult(Ok) -> flag stays false
}
#[test] fn sign_in_methods_list_and_remove() {
    // LoggedOut: SignInMethodsRequested -> []; logged_in(): -> [CallListSignInMethods]; SignInMethodsResult(Ok([google, apple "a1"])) ->
    // sign_in_methods() has 2; RemoveSignInMethodRequested("a1") -> [CallRemoveSignInMethod("a1")], removing == Some("a1");
    // RemoveSignInMethodRequested("a2") while removing -> []; SignInMethodRemoved{"a1", Ok(())} -> [CallListSignInMethods], removing None;
    // SignInMethodRemoved{"a1", Err(net())} -> notice() == Some(&net())
}
#[test] fn logout_clears_email_method_and_methods() {
    // after SessionResult Ok and SignInMethodsResult Ok: LogoutRequested + LogoutResult(Ok) -> email(), auth_method(), sign_in_methods() all None
}
#[test] fn google_urls_and_emails_never_in_debug() {
    // format!("{:?}", OpenBrowser("https://accounts.google.com/x?state=S")) lacks "state=S";
    // Debug of GoogleFinished{Ok(email "g@x")} and SessionResult(Ok(email "g@x")) lacks "g@x"
}
#[test] fn delete_account_url_is_the_privacy_page() { assert_eq!(DELETE_ACCOUNT_URL, "https://shellx.pro/privacy#delete-account"); }
```

- [ ] **Step 2: Run to verify they fail.** Run: `(cd windows && cargo test --locked -p shellx-model account::)`. Expected: compile errors (`GoogleRequested` missing).
- [ ] **Step 3: Commit the failing tests.** `git add windows/shellx-model/src/account.rs && git commit -m "test(shellx-windows): account flow Google steps and server sign-out"`
- [ ] **Step 4: Implement** the rules.
- [ ] **Step 5: Run to verify they pass.** Run: `(cd windows && cargo test --locked -p shellx-model)`. Expected: `test result: ok` including every existing `account::tests`, and no new compiler warning.
- [ ] **Step 6: Commit.** `git add windows/shellx-model/src/account.rs && git commit -m "feat(shellx-windows): account flow signs in with Google and switches in place"`

---

### Task 15: Windows app: branded Google button and dialog, Settings rows, wiring

**Files:**
- Modify: `windows/shellx-app/src/core_service.rs` (`run_account_action` :122-151, tests :159-412)
- Modify: `windows/shellx-app/src/ui/account.rs` (`Job`/`Done` :24-34, `AccountService` :36-111, `login`/`email` :142-159, `apply` :200-215)
- Modify: `windows/shellx-app/src/ui/login.rs` (whole dialog)
- Modify: `windows/shellx-app/src/ui/settings.rs` (`SettingsEvent` :25-31, `open` :61-65, `account_section` :107-177)
- Modify: `windows/shellx-app/src/ui/root.rs` (subscriptions :171-181, `account_changed` :374-381, :773-775, `open_sign_in` :784-791)
- Modify: `windows/shellx-app/build.rs:4-12`
- Modify: `windows/shellx-app/src/fonts.rs:1-33`
- Modify: `windows/shellx-app/src/icons.rs:95-102` (`by_path`)
- Create: `windows/shellx-app/src/ui/google_button.rs` (and `pub mod google_button;` in `windows/shellx-app/src/ui/mod.rs`)

**Interfaces:**
- Consumes: Tasks 13–14 (`shellx_model::google_button`); Task 9's Windows asset paths; `shellx_fake_api::browse` (dev-dependency); `update_banner::open_https`.
- Produces:

```rust
// build.rs (before the existing Windows-only resource step):
//   println!("cargo::rustc-check-cfg=cfg(shellx_google_mark)"); println!("cargo::rustc-check-cfg=cfg(shellx_google_sans)");
//   println!("cargo:rerun-if-changed=assets/google"); println!("cargo:rerun-if-changed=assets/fonts");
//   cfg shellx_google_mark when assets/google/google-g.png is a file;
//   cfg shellx_google_sans when assets/fonts/GoogleSans-Medium.ttf and assets/fonts/GoogleSans-OFL.txt are both files
//   (the licence gate: a font without its licence text is never embedded)
// icons.rs
pub const GOOGLE_MARK_PATH: &str = "google/google-g.png";
/// The official "G" when the build found it (cfg shellx_google_mark), else None.
pub fn google_mark() -> Option<&'static [u8]>;   // include_bytes!("../assets/google/google-g.png") only under the cfg
// by_path(GOOGLE_MARK_PATH) returns google_mark(); the coolicon table is unchanged
// fonts.rs
pub const GOOGLE_SANS_FAMILY: &str = "Google Sans";
/// The Google Sans Medium face is embedded (cfg shellx_google_sans).
pub fn has_google_sans() -> bool;
// embedded() appends include_bytes!("../assets/fonts/GoogleSans-Medium.ttf") only under cfg shellx_google_sans
// ui/google_button.rs
/// The branded "Continue with Google" button (shellx_model::google_button values, Light theme on the dark UI):
/// rgb(FILL) fill, 1 px rgb(STROKE) border (GPUI borders are inside), CORNER_RADIUS, h(HEIGHT), pl(PAD_LEFT), pr(PAD_RIGHT),
/// gap(LOGO_GAP); the "G" as img(ImageSource::Resource(Resource::Embedded(GOOGLE_MARK_PATH.into()))) sized LOGO_SIZE when
/// google_mark() is Some, else no logo and no gap; the label in rgb(TEXT), FONT_SIZE / LINE_HEIGHT, font FONT_FAMILY weight
/// FONT_WEIGHT with fallbacks FONT_FAMILY_LEGACY then the UI font when has_google_sans(), else the UI font at weight FONT_WEIGHT.
pub fn google_button(id: &'static str, label: &'static str) -> Stateful<Div>;
// core_service.rs: new arms — CallGoogleBegin -> GoogleBegun; CallGoogleFinish -> GoogleFinished (blocks up to 300 s);
// CallGoogleCancel -> None (result ignored); CallSession -> SessionResult; CallListSignInMethods -> SignInMethodsResult;
// CallRemoveSignInMethod -> SignInMethodRemoved; OpenBrowser -> None (the window opens it)
pub const GOOGLE_SWITCH_MARKER: &str = "google-switch-offered";
/// True only for the call that creates `marker` (create_new).
pub fn take_once(marker: &std::path::Path) -> bool;
// ui/account.rs AccountService: keeps `core: Arc<dyn CoreCall>`, `facts: MachineFacts`, `done_tx` to run
// CallGoogleFinish on its own background task (never on the serial worker); OpenBrowser -> open_https(cx, &url);
// `login` and the `email` field are removed.
pub fn google_sign_in(&mut self, purpose: GooglePurpose, cx: &mut Context<Self>);
pub fn cancel_google(&mut self, cx: &mut Context<Self>);
pub fn refresh_sign_in_methods(&mut self, cx: &mut Context<Self>);
pub fn remove_sign_in_method(&mut self, identity_id: String, cx: &mut Context<Self>);
pub fn google_in_flight(&self) -> Option<GooglePurpose>;
pub fn email(&self) -> Option<&str>;                 // flow.email() while LoggedIn
pub fn auth_method(&self) -> Option<&str>;
pub fn needs_google_switch(&self) -> bool;
pub fn sign_in_methods(&self) -> Option<&[SignInMethod]>;
pub fn removing_sign_in_method(&self) -> Option<&str>;
pub fn take_signed_out_by_server(&mut self) -> bool;
pub fn take_google_switch_offer(&mut self) -> bool;  // once per run: needs_google_switch() && take_once(native_dir()/GOOGLE_SWITCH_MARKER)
// ui/login.rs SignInDialog
pub fn open(&mut self, purpose: GooglePurpose, window: &mut Window, cx: &mut Context<Self>);
// ui/settings.rs SettingsEvent gains SwitchToGoogleRequested
// ui/root.rs
pub fn open_sign_in(&mut self, purpose: GooglePurpose, window: &mut Window, cx: &mut Context<Self>);
```

Dialog (card 340 px, as today): title `SignInTitle` or `SwitchToGoogle`; `Link` adds `SwitchToGoogleIntro`; `google_button("sign-in-google", t(lang, Str::ContinueWithGoogle))` centred under the title, clicking it calls `google_sign_in(purpose)`; while `google_in_flight()` the button is replaced by `WaitingForGoogle` + `BrowserHint`; error line from `google_error(lang, code)` — `AccountState::Error(e)` for `SignIn`, `notice()` for `Link`, only after this dialog started a flow; secondary `Cancel` (also Esc) runs `cancel_google` when a flow runs, then closes. The dialog owns a `FocusHandle` with `on_key_down` (Enter starts, Esc cancels) replacing the two text fields, and `focus_target` returns it. It closes itself when a flow it started ends with `LoggedIn` (`SignIn`) or `auth_method() == Some("google")` (`Link`). Settings › Account: email from `account.email()`; when `needs_google_switch()` a row `SwitchToGoogle` / `SwitchToGoogleIntro` / button `SwitchEllipsis` emitting `SwitchToGoogleRequested`; header `SignInMethods`; rows `GoogleAccount` + email, or `AppleId` + email or `HiddenEmail` + `added_from(..)` + button `RemoveMethod`; `sign_in_methods_error` on a methods notice; a secondary button `DeleteAccount` calling `open_https(cx, DELETE_ACCOUNT_URL)`; `open` calls `refresh_sign_in_methods` while signed in. RootView: `SignInRequested` and the machines "+" open `SignIn`; `SwitchToGoogleRequested` opens `Link`; `account_changed` opens `SignIn` when `take_signed_out_by_server()` and `Link` when `take_google_switch_offer()`.

- [ ] **Step 1: Write the failing tests** in `fonts.rs`, `icons.rs` and `core_service.rs` tests:

```rust
// fonts.rs: replaces five_embedded_fonts_are_truetype
#[test] fn embedded_fonts_are_truetype_and_google_sans_follows_the_build() {
    let fonts = embedded();
    assert_eq!(fonts.len(), 5 + usize::from(has_google_sans()));
    assert_eq!(has_google_sans(), cfg!(shellx_google_sans));
    assert!(fonts.iter().all(|f| has_font_magic(f)));
}
// icons.rs
#[test] fn the_google_mark_follows_the_build() {
    assert_eq!(google_mark().is_some(), cfg!(shellx_google_mark));
    assert_eq!(by_path(GOOGLE_MARK_PATH), google_mark());
    if let Some(png) = google_mark() { assert!(png.starts_with(b"\x89PNG\r\n\x1a\n")); }
}
// core_service.rs
#[test] fn take_once_is_true_only_the_first_time() {
    // tempdir: take_once(&dir.join(GOOGLE_SWITCH_MARKER)) true, then false
}
/// Google sign-in through the real shellx-core against the fake API and fake Google: a `CoreCall` wrapper around
/// `CoreBridge` adds `shellx_fake_api`'s Google overrides to `config.set`; on `OpenBrowser(url)` the drive loop spawns
/// `shellx_fake_api::browse(&url)` before running `CallGoogleFinish`.
#[test] fn google_session_against_fake_api() {
    // Started -> LoggedOut; GoogleRequested(SignIn) runs, in this order: "CallGoogleBegin(SignIn)", "OpenBrowser(\"<auth url>\")",
    // a "CallGoogleFinish(" entry (random flow id: assert with starts_with), "CallList", "CallRegister", "CallList";
    // no "CallSession" (finish already gave the email); state LoggedIn; email() == Some("google-user@shellx.test"); auth_method() == Some("google"); !needs_google_switch();
    // SignInMethodsRequested -> one google row
}
```

- [ ] **Step 2: Run to verify they fail.** Run: `(cd windows && cargo test --release --locked -p shellx-app)` (release: debug `shellx-app` tests are unreliable on a Mac, `windows/README.md:54-57`). Expected: compile errors (`take_once`, `has_google_sans`, `google_mark` missing).
- [ ] **Step 3: Commit the failing tests.** `git add windows/shellx-app/src/core_service.rs windows/shellx-app/src/fonts.rs windows/shellx-app/src/icons.rs && git commit -m "test(shellx-windows): Google session through the real core, Google mark and font follow the build"`
- [ ] **Step 4: Implement** the Interfaces and views.
- [ ] **Step 5: Run to verify they pass.** Run: `(cd windows && cargo test --release --locked -p shellx-app && cargo build --release --locked -p shellx-app)`. Expected: `test result: ok` (including `account_session_against_fake_api`, `smoke_account_flow` and the new tests, whichever state Task 9's files are in); the build finishes with no error and no `unexpected_cfgs` warning.
- [ ] **Step 6: Look at it (optional, Mac).** `(cd windows && SHELLX_LANG=en dev/mac-shot.sh $TMPDIR/shellx-signin.png)` and open the PNG; repeat with `SHELLX_LANG=vi`. Expected: a PNG of the window (the sign-in card appears once Settings › Account › Sign In… is used; the screenshot only proves the window starts).
- [ ] **Step 7: Commit.** `git add windows/shellx-app/build.rs windows/shellx-app/src && git commit -m "feat(shellx-windows): branded Google sign-in dialog, switch row and sign-in methods"`

---

### Task 16: Verify and hand off

**Files:** none new.

- [ ] **Step 1: Run the full verification** from the worktree root:

```bash
(cd shellx-core && cargo test --workspace --locked)
git diff --quiet develop...HEAD -- shellx-core/Cargo.lock windows/Cargo.lock && echo locks-unchanged
swift test --package-path Packages/Shared/ShellXBrand
swift test --package-path Packages/macOS/CmuxSettingsUI
(cd windows && cargo test --locked -p shellx-model && cargo test --release --locked -p shellx-app)
python3 tests/test_shellx_remote_harness.py
python3 tests/test_shellx_vi.py
python3 tests/test_shellx_no_phone_home.py
python3 tests/test_shellx_google_branding.py
python3 scripts/shellx/check-google-branding.py
python3 scripts/localization_catalog.py check
./scripts/localize-changes --base develop
./scripts/wire-app-sources.py --check
./scripts/sync-test-wiring --check
scripts/shellx/test-app.sh ShellXPhonePairingCoordinatorTests ShellXAboutTests
python3 scripts/verify-local.py
```
Expected: every Rust/Swift/Python suite passes; `locks-unchanged`; `check-google-branding.py` prints `google branding: OK` once Task 9 Step 8 is committed (before that it lists the missing mark files: record it, the desktop release scripts stay blocked); `Localization ready: changed work is complete and the strict catalog validator passed.`; both wiring checks exit 0; `** TEST SUCCEEDED **`; `verify-local.py` reports all selected checks passed.
- [ ] **Step 2: Secret scan.** Run `git diff develop...HEAD --stat` and `git diff develop...HEAD | grep -nE '^\+.*(GOCSPX-|apps\.googleusercontent\.com)'` (only this branch's added lines: `develop` may meanwhile hold plan 1C's iOS client settings). Expected: no match (no real client id or secret committed).
- [ ] **Step 3: Localization and branding audit for the hand-off.** List the changed surfaces (Mac sign-in sheet with the branded Google button, Settings › Account rows, pairing sheet notice and errors, the eight "phone" keys; Windows dialog with the branded button and Settings), the catalogs updated, the commands above, that the eight non-en/vi locales were machine-translated by the executor, whether Google's "G" and Google Sans came from the USER's download (Task 9 Step 8 commit) or are still pending, and confirm no Google logo was copied from `ios/`, `Packages/` or `Sources/`.
- [ ] **Step 4: Final review.** Use a review subagent (skills/cmux-review, correctness first) on `git diff develop...HEAD`; fix findings with new commits and rerun Step 1.
- [ ] **Step 5: Land (contracts §1).** After the plan's final review passes, This plan changes app UI/runtime, so after the final review it waits for the USER device check and the user's merge directive (`merge`, `merge it` or `auto-merge`, CLAUDE.md "CI, review and merge"); if none was given, ask with the review summary. Only then merge into `develop` from the main checkout (it has `develop` checked out, so the worktree cannot) and push `develop`: `M=/Users/lehuuphu/Documents/myProjects/shellx; git -C "$M" pull --ff-only origin develop && git -C "$M" merge --no-ff feat/shellx-signin-1b-desktop && git -C "$M" push origin develop`. A merge conflict: resolve it in the worktree by merging `develop` into the branch, rerun Step 1, then retry. Never merge to `main`, never deploy, never upload to a store, never publish a release (`publish-to-vps.sh` belongs to plan 1D, after the user's go-ahead). Live checks against the real relay and Google need 1A deployed and the Desktop OAuth client; they belong to plan 1D.
- [ ] **Step 6: Report.** Hand-off notes: skipped checks (for example the remote e2e of Task 5 Step 6), the localization and branding audit, whether the Task 9 USER download is still pending, and the Contract additions below for the contracts owner.

---

## Spec notes

- **401 handling already exists in the core.** `Core::forget_refused_session` (`shellx-core/src/lib.rs:125-136`) already keeps `machine.json` and `device.key`; this plan keeps it, moves its body to `auth::forget_session_if`, and applies it to `account.*` and to the link call. The apps were the gap: the Mac kept showing the email after a 401 (`account.json`), and Windows treated `unauthorized` as offline for 15 s.
- **`auth.google.link` (spec §6.5) is `auth.google.begin {purpose: "link"}`** per contracts §3.
- **"Băng một lần" (one-time banner, §6.3b).** The desktop has no banner surface for account messages. The plan shows the "Switch to Google sign-in" sheet/dialog once (Mac: `UserDefaults` key `shellx.account.googleSwitchOffered`; Windows: marker file `google-switch-offered` in the native data dir) and keeps the permanent row in Settings › Account.
- **"Show the Google sign-in screen" on a 401.** The Mac presents the sign-in sheet when the remote service ends a session on a signed-out code; Windows opens its dialog after a server sign-out.
- **S3 §7.4b names two strings; the code has the wording in eight keys** (pairing sheet title, scan line, sign-in-first line, sidebar menu, two notification keys each used in `NotificationsPage.swift` and `UpdateTitlebarAccessory.swift`, Settings › Mobile row title and subtitle). All eight change. `terminalSharing.device.iphone` ("iPhone" fallback name of a nameless device) is unchanged.
- **Release builds had no working sign-in entry outside Settings.** `ShellXRemoteUIModel.shared.service` is nil in release, so `ShellXRemoteUIActions.presentSignIn()` (share popover, sidebar row) did nothing; it now opens Settings › Account's Google sheet.
- **Windows forgot the email after a restart** (`AccountService.email`, "Unknown after a restart"); spec §4 wants the account email always visible, hence `auth.session`.
- **Google token-exchange failures** have no contract code; they map to `invalid_credentials`.
- **Desktop account deletion** is a link only (spec §3). The fake's `DELETE /v1/account` exists for contract parity; no desktop code calls it.
- **Kept until the cut-over:** `auth.login`, `ShellXAccount.signIn(email:password:)`, `ShellXRemoteService.signIn(email:password:)` (DEBUG dev credentials) and Windows `AccountEvent::LoginSubmitted`; no UI calls them. The now-unused Mac keys `remote.signin.email`, `remote.signin.password`, `remote.signin.submit` and Windows `Str::Email`/`Password`/`EmailAddress`/`Login` stay in place.
- **Windows closes its dialog on success** (no "Signed in as" step); Settings shows the email. The Mac shows "Signed in as …" with Done, as §6.5 describes.
- **Google branding (contracts §11; Google's page read 2026-11-07).** The page gives padding only for "Android & web" (12 / 10 / 12) and iOS (16 / 12 / 16); the desktops take the Android & web values and the geometry of the Android + Web assets (40 px tall, corner radius 4, 20×20 "G" at x 12). Light theme in both appearances, as plan 1C chose; the page allows Light, Dark and Neutral on any background. The official SVGs paint the "G" through a `foreignObject` CSS conic-gradient that AppKit and GPUI's SVG renderer do not draw, so the mark is the centre 80×80 crop of the official @4x PNG (`sips`, no scaling or recolouring). The zip has no bare "G" file; the "Light, no text, Square" icon is the source, as for 1C.
- **Google Sans licence (contracts §11 gate).** `ofl/googlesans/OFL.txt` in github.com/google/fonts says "licensed under the SIL Open Font License, Version 1.1" (no reserved font names; `TRADEMARKS.md` keeps the "Google Sans" name a Google trademark, which bundling the unmodified font respects). The fetch script still checks the licence text before installing the font. The static `GoogleSans-Medium.ttf` (about 2.1 MB) is used on both desktops because Windows embeds static faces (`fonts.rs`).
- **The Mac now calls `auth.session` at launch** (contracts §10 says it does): `ShellXAccount.reconcileWithSession()` copies the core's email and auth method and catches a session that disappeared while the app was closed.

## Contract additions

For the contracts owner to add to §3 (all owned by 1B):

- `auth.session {}` → `{user_id, device_id, email: string|null, auth_method: "password"|"google"|"apple"|"test"}` (old `session.json` files read as `password` / `null`); `not_logged_in` without a session; local only, no network. Consumers: Windows (email after restart) and the Mac (launch reconcile).
- Desktop release guard (for 1D): `scripts/shellx/check-google-branding.py` must print `google branding: OK` before a desktop release; `make-dmg.sh` and `build-windows-cross.sh` run it first and refuse otherwise. The assets come from the USER-run `scripts/shellx/fetch-google-branding.sh` (plan 1B Task 9); 1C and 3D download their own copies, never from these desktop paths.
- `config.set` gains optional `google_auth_url`, `google_token_url` (https, or http on 127.0.0.1/localhost only), `google_client_id`, `google_client_secret`. Test and dev overrides; the apps never pass them.
- Build-time reading of `SHELLX_GOOGLE_DESKTOP_CLIENT_ID` / `SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET` through `option_env!` (the "compiled defaults"), still overridable at run time by the same names. Plan 1D must export both in the environment of the Mac (`scripts/shellx/build-shellx-core.sh` inside the Xcode build) and Windows release builds.
- Test-only names: CLI pseudo-method `shellx-core-cli auth.google.e2e`; fake routes `GET /fake-google/auth`, `POST /fake-google/token`; fake defaults `google_client_id` `fake-desktop-client`, `google_client_secret` `fake-desktop-secret`; env `SHELLX_FAKE_GOOGLE_EMAIL`.
- For 1C (iPhone `pairing.instructions` quotes the Mac menu item): the Mac's `remote.phonePairing.menu` becomes en `Pair Phone…`, vi `Ghép cặp điện thoại…`, so the iPhone string becomes en `On your Mac, open ShellX, right-click “This Mac” and choose Pair Phone…`, vi `Trên Mac, mở ShellX, bấm chuột phải vào “Mac này” rồi chọn Ghép cặp điện thoại…`.

# ShellX Email Code Sign-in, Desktop Plan A (shellx-core + Mac) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Execution (decided):** one implementer runs Tasks 0–8 in order on one branch, commits per task with the failing test first, and stops after Task 8; one whole-branch review follows. Plan B (Windows) starts after this branch is merged.

**Goal:** The Mac signs in with an email address and a 6-digit code next to "Continue with Google", through two new `shellx-core` RPCs that the Windows app (Plan B) also calls.

**Architecture:** `shellx-core` gains `auth.email.begin` (asks the relay to mail a code) and `auth.email.finish` (verifies it and writes `session.json` with `auth_method = "email"`), built like `auth.google.finish` minus the browser; the in-memory `shellx-fake-api` gains the two relay routes and a readable "mailbox", so every test runs offline. On the Mac, `ShellXAccount` wraps the two calls, a testable `EmailSignInModel` (package `ShellXRemoteUI`) owns the steps and the resend lock, and the existing sign-in sheet shows them.

**Tech Stack:** Rust 1.91 edition 2024 (`ureq` 3, `tiny_http` in the fake), Swift 6.0 language mode (Swift Testing, SwiftUI/AppKit, `@Observable`), Python 3 `unittest`.

**Spec:** `docs/superpowers/specs/2026-11-10-shellx-email-code-sign-in-design.md` (Vietnamese): §3, §4, §7 ("Chung", the strings paragraph, **Desktop chung**, **Mac**), the desktop lines of §8–§10; §11 is answered: all four apps, link by verified email (relay side), default sender, every small default stands. Also read the "Email + code sign-in through Resend" section of `docs/superpowers/HANDOFF-shellx-mobile.md` and, for conventions, the header and Tasks 3, 8, 10 of `docs/superpowers/plans/2026-11-07-shellx-signin-1b-desktop.md`. Before Task 4 read `skills/cmux-localization/SKILL.md`; before Task 6 read `skills/cmux-testing/SKILL.md`.

## Global Constraints

- Relay API, the only source of truth for shapes and codes (spec §4):

  ```
  POST /v1/auth/email/code     {email, locale?: "en"|"vi"}
    -> 202 {challenge_id, expires_in: 600, resend_in: 60, email}      email normalized (trim, lowercase)
       400 invalid_email | 400 disposable_email | 429 rate_limited
       503 email_sign_in_disabled | 502 email_send_failed
  POST /v1/auth/email/verify   {challenge_id, code, device}           device as /v1/auth/google (kind != agent)
    -> 200 {user_id, device_id, token, email}
       401 invalid_code | 410 code_expired | 409 switch_from_signed_in_device
       400 invalid_device | 429 rate_limited
  ```

  A relay that predates the feature answers `404 {"error":{"code":"not_found"}}` (`relay/src/app.ts:159`). Errors are `{"error":{"code","message"}}`.
- Code: 6 digits, lives 600 s, 5 guesses, one live code per address, "Resend code" locked for `resend_in` (60 s).
- "Continue with email" is always shown; no discovery call. An unavailable relay shows "This way of signing in isn't available in this build".
- Tests fake the relay (`shellx-fake-api`, `FakeRemoteCore`). Nothing here needs a running relay, a real mailbox or a key.
- Never log, `Debug`-print or put in a `CoreError` message: session tokens, the code, the `challenge_id`, email addresses.
- No new crates and no new Swift packages: `shellx-core/Cargo.lock` stays unchanged (the app's Xcode phase builds with `cargo build --release --locked`).
- Desktop has no account deletion by code; Settings keeps the link to `https://shellx.pro/privacy#delete-account`.
- Mac: app-linked Swift (`Sources/`, `Packages/Shared/ShellXBrand/Sources/`) stays Swift 6.0 compatible (no trailing commas in parameter or argument lists, no `nonisolated` on type declarations; `skills/cmux-architecture/references/swift-6-0-compatibility.md`). App tests only through `scripts/shellx/test-app.sh <Suite>`, never bare `xcodebuild`. Never quit, launch, relaunch or replace `/Applications/ShellX.app` or any cmux app; no `reload.sh --launch`. A new `Sources/**/*.swift` file is wired with `./scripts/wire-app-sources.py <path>`; a new `cmuxTests/*.swift` file with `./scripts/sync-test-wiring`.
- Mac strings: `String(localized: "<key>", defaultValue: "<English>")`, catalog `Resources/Localizable.xcstrings`, all ten locales `en, de, fr, ar, es, zh-Hant, zh-Hans, ko, ja, vi` through `./scripts/localize-changes --base develop`. `en` and `vi` are exactly the String table's values; the other eight are the executor's translations. Vietnamese follows `scripts/shellx/l10n/vi-glossary.md`. A translation identical to English needs an `identityLocales` record in `scripts/localization-allowed-omissions.json`. Every call site of a key passes the same `defaultValue`.
- Mac verification starts with `python3 scripts/verify-local.py --affected develop --swift-changed develop` (explicit base: the default base is `origin/HEAD`, which is `main`).
- Never release, deploy, push or merge to `main`, sign, notarize, or upload anywhere. The implementer does not merge: the orchestrator reviews the branch and lands it on `develop`.
- Branch `feat/shellx-email-code-signin-core-mac` from `develop`, worktree `.worktrees/email-code-signin-core-mac`. Commit style: `test(shellx-core): …` then `feat(shellx-core): …`; `test(shellx): …` then `feat(shellx): …`.

## Review Focus

1. **A code pasted with spaces or a line break ("123 456", " 123456\n").** It is accepted as `123456`. Tests: Task 2 `a_pasted_code_with_spaces_is_sent_as_six_digits`; Task 5 `pastedCodeKeepsOnlySixDigits`.
2. **Double submit: the sixth digit submits by itself while the person also presses Return or Verify.** One verify call, no guess burned. Tests: Task 5 `sixDigitsSubmitByThemselvesOnce`; Task 2 `a_code_that_is_not_six_digits_is_invalid_code_without_a_request`.
3. **An expired code, or the fifth wrong guess.** The sheet says the code expired, stays on the code step and unlocks "Resend code" at once. Tests: Task 2 `a_wrong_code_is_invalid_code_and_the_fifth_is_code_expired`, `an_expired_or_reused_code_is_code_expired`; Task 5 `anExpiredCodeAsksForANewOneAndUnlocksResend`.
4. **Closing the sheet mid-flow and opening it again.** A late answer never changes or reopens the closed sheet, the new sheet starts at the first screen, and a code that verified after the close still leaves this Mac signed in. Tests: Task 5 `cancelWhileSendingIgnoresTheLateChallenge`, `cancelWhileVerifyingClosesOnceAndIgnoresTheResult`; Task 3 `emailCodeSignsInAndSavesTheEmailIdentity`.
5. **A relay without the feature (an old relay's 404, or 503).** One sentence, the email step stays usable, nothing is written. Tests: Task 2 `a_relay_without_email_sign_in_is_email_sign_in_disabled`; Task 5 `aRelayWithoutEmailSignInSaysUnavailable`.
6. **Offline.** The network sentence, the same step, a retry works, no session file. Tests: Task 2 `offline_is_network`; Task 5 `offlineShowsTheNetworkMessageAndAllowsRetry`.
7. **Asking again too soon (429).** A sentence, never the raw `rate_limited`. Tests: Task 4 `signInErrorMapping`; Task 5 `aFailedResendKeepsTheCodeStepAndUnlocksAgain`.

## Rulings

Where the spec and the code disagree the plan follows the code; where the spec is silent the plan decides.

1. A relay without the feature has one core code: 404 `not_found`, a body-less 404 (`http_404`) and 503 `email_sign_in_disabled` on either route all surface as `email_sign_in_disabled`. The apps map one code.
2. `auth.email.finish` returns the six fields of `auth.google.finish` with `auth_method: "email"` (the spec says only "phiên").
3. The core normalizes `locale` (a value starting with `vi`, any case, is `"vi"`; anything else or nothing is `"en"`), so each app passes its UI language as it is. The Mac passes `Bundle.main.preferredLocalizations.first`.
4. The core removes ASCII whitespace from `code` and refuses anything but six ASCII digits with `invalid_code` without a request, so a malformed code never burns a guess.
5. `rate_limited` gets a sentence (`remote.signin.error.rateLimited`, the iPhone's `signin.error.rateLimited` text); the spec's string list omits it though §4 returns 429 on both routes. `signInErrorMapping`'s example of a code shown raw changes from `rate_limited` to `weak_password`.
6. `email_sign_in_disabled` reads as the iPhone's `signin.error.providerUnavailable` text under the Mac key `remote.signin.error.unavailable`.
7. Mac key names follow the catalog: `settings.account.methods.email` (the spec writes `settings.account.method.email`; the code has `settings.account.methods.*`), and the email field reuses the existing, currently unused key `remote.signin.email` ("Email" / "Địa chỉ email") instead of a new `.field` key.
8. `remote.signin.email.resendIn` takes `%@` filled with the whole seconds as text ("42"), not the spec's `%lld`: `scripts/localize_changes.py` stops on an integer placeholder in a new key and demands plural entries. The visible text equals the phones' `Resend code in %lld s`.
9. The spam hint of spec §9 (no key in §7's list) is the second sentence of `remote.signin.email.sentTo`, as in the Android and iPhone plans; no separate key.
10. Settings › Account keeps its two-line row (title "Email code", the address under it) instead of "Email code · foo@bar.com"; Remove stays for Apple IDs only.
11. `code_expired` keeps the person on the code step with Resend unlocked at once; "Use a different email" is the only way back to the email step.
12. Closing the sheet cannot cancel a verify already sent (no cancel API): the closed sheet ignores the answer and the account keeps the session, as with a Google finish after a close.
13. The email path exists only in the "Sign in to ShellX" sheet; the "Switch to Google sign-in" sheet is unchanged (the spec has no `/v1/auth/email/link`).
14. `finishEmailSignIn` returns the existing `GoogleSignInResult` (same shape); no rename.
15. `SignInErrorLabels.init` grows by seven required labels with no default, so the app cannot ship an unlocalized one.
16. Fake API: `mailinator.com` and its subdomains stand for the disposable list; `fail_next` scripts the answers the fake cannot produce by itself (429, 502, 404, `invalid_device`).
17. `auth.login`, the `shellx-fake-api` binary's flags and the remote e2e harness are unchanged.
18. An app-hosted suite `ShellXSignInSheetTests` is added so `test-app.sh` executes tests of the changed app code (plan 1B only compiled it).
19. Wording: the String table matches the Android plan's (`2026-11-11-shellx-email-code-signin-android.md`, which takes this table as its source); the iPhone plan keeps whatever the shared catalog holds. If `shellx-ios/ShellX/Localizable.xcstrings` on `develop` already has `signin.email.*` or the new `signin.error.*` keys when a task starts and a value differs, the catalog's `en` and `vi` replace this plan's for the same string (one text on every app); record each swap in the hand-off.

## Interfaces for Plan B (the RPC contract)

```
auth.email.begin  {email: string, locale?: string}
  -> {challenge_id: string, expires_in: number, resend_in: number, email: string}
     email = the relay's normalized address; expires_in 600 and resend_in 60 when the relay omits them
auth.email.finish {challenge_id: string, code: string}
  -> {user_id, device_id, device_public_key_b64, fingerprint, email, auth_method: "email"}     never a token
```

`begin` writes nothing. `finish` on success writes `session.json` (`auth_method: "email"`, `email`), keeps `device.key`, drops `machine.json` only when the account changed (`auth::save_session`), and `auth.session` then reports `auth_method: "email"`; on any error nothing is written. Both send no bearer. Neither needs a session.

| `CoreError.code` | When |
| --- | --- |
| `invalid_params` | params not an object; `email`, `challenge_id` or `code` missing or not a string; empty `challenge_id` |
| `invalid_email` | relay 400; or the address is empty after trimming (no request) |
| `disposable_email` | relay 400 |
| `rate_limited` | relay 429, either call |
| `email_send_failed` | relay 502: nothing was sent and any earlier code for that address is dead |
| `email_sign_in_disabled` | relay 503 `email_sign_in_disabled`, or 404 (`not_found` or no JSON) on either route |
| `invalid_code` | relay 401; or the code is not six digits after removing whitespace (no request) |
| `code_expired` | relay 410: unknown, expired or used challenge, or the fifth wrong guess. Ask for a new code |
| `switch_from_signed_in_device` | relay 409 |
| `invalid_device` | relay 400 (not expected: the core builds the device) |
| `network`, `server`, `http_<status>`, `not_configured` | as for every other method (`shellx-core/src/http.rs`) |

Fake API names (dev-dependency `shellx-fake-api`): `FakeOptions.email_sign_in: bool`, `FakeApi::email_code(&self, email: &str) -> Option<String>`, `FakeApi::expire_email_codes(&self)`, `FakeApi::fail_next(&self, path: &str, status: u16, code: &str)`.

## String table

Mac keys in `Resources/Localizable.xcstrings`. "Win" is the `windows/shellx-model` name Plan B gives the same text.

| Key | en | vi | Win |
| --- | --- | --- | --- |
| `remote.signin.email.continue` | Continue with email | Tiếp tục với email | `ContinueWithEmail` |
| `remote.signin.email.or` | or | hoặc | `OrDivider` |
| `remote.signin.email` (exists, now used) | Email | Địa chỉ email | `EmailAddress` (exists) |
| `remote.signin.email.send` | Send code | Gửi mã | `SendCode` |
| `remote.signin.email.sentTo` | We sent a code to %@. Can't find it? Check your spam folder. | Đã gửi mã tới %@. Không thấy thư? Hãy kiểm tra thư rác. | `sent_code_to()` |
| `remote.signin.email.code` | 6-digit code | Mã 6 chữ số | `CodePlaceholder` |
| `remote.signin.email.verify` | Verify | Xác minh | `VerifyCode` |
| `remote.signin.email.resend` | Resend code | Gửi lại mã | `ResendCode` |
| `remote.signin.email.resendIn` | Resend code in %@ s | Gửi lại mã sau %@ giây | `resend_code_in()` |
| `remote.signin.email.change` | Use a different email | Dùng email khác | `UseDifferentEmail` |
| `remote.signin.error.invalidEmail` | Enter a valid email address. | Hãy nhập một địa chỉ email hợp lệ. | `InvalidEmail` |
| `remote.signin.error.disposableEmail` | Temporary email addresses can't be used. Try another address. | Không dùng được địa chỉ email tạm thời. Hãy thử địa chỉ khác. | `DisposableEmail` |
| `remote.signin.error.invalidCode` | That code isn't right. Check it and try again. | Mã chưa đúng. Hãy kiểm tra và thử lại. | `InvalidCode` |
| `remote.signin.error.codeExpired` | That code has expired. Request a new one. | Mã đã hết hạn. Hãy yêu cầu mã mới. | `CodeExpired` |
| `remote.signin.error.emailSendFailed` | We couldn't send the email. Try again. | Không gửi được email. Hãy thử lại. | `EmailSendFailed` |
| `remote.signin.error.unavailable` | This way of signing in isn't available in this build. | Bản này chưa dùng được cách đăng nhập này. | `SignInUnavailable` |
| `remote.signin.error.rateLimited` | Try again in a few minutes. | Thử lại sau ít phút. | `RateLimited` |
| `settings.account.methods.email` | Email code | Mã qua email | `EmailCodeMethod` |

`%@` of `resendIn` is the wait in whole seconds as text (`42`). The phones show the same words for every row but the email field (theirs is "Email address"; the Mac reuses its existing key). The two `unavailable` and `rateLimited` rows are the iPhone catalog's `signin.error.providerUnavailable` and `signin.error.rateLimited` values; the other Vietnamese values are this plan's wording (Ruling 19).

## File structure

| File | Responsibility |
| --- | --- |
| `shellx-core/fake-api/src/lib.rs` (modify) | The two relay routes, the mailbox and scripted-failure hooks |
| `shellx-core/fake-api/tests/email.rs` (create) | The fake's routes over raw HTTP |
| `shellx-core/src/auth_email.rs` (create) | `begin`, `finish`, `locale_of`, `clean_code`, the "no email sign-in" mapping |
| `shellx-core/src/api.rs`, `src/lib.rs` (modify) | Request and response types; `KNOWN_METHODS`, dispatch |
| `shellx-core/tests/email.rs`, `tests/support/mod.rs` (create, modify) | The RPCs against the fake |
| `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/ShellXCoreClient+Email.swift` (create) | `EmailCodeChallenge`, the two typed calls |
| `…/ShellXRemoteCore/ShellXAccount.swift` (modify) | `requestEmailCode`, `signInWithEmailCode` |
| `…/ShellXRemoteUI/SignInErrorMessage.swift` (modify) | Seven new labels and codes |
| `…/ShellXRemoteUI/EmailSignInModel.swift` (create) | Steps, sanitizing, auto-submit, resend lock |
| `Sources/ShellX/Remote/UI/EmailSignInSection.swift` (create) | The email and code steps' views |
| `Sources/ShellX/Remote/UI/SignInSheet.swift`, `ShellXRemoteServicing.swift`, `ShellXRemoteFixtureService.swift`, `RemoteUISnapshot.swift`, `Sources/ShellX/ShellXAccountFlow.swift`, `Sources/ShellX/ShellXAccountDetailView.swift` (modify) | Sheet layout and presenter, protocol and fixture, localized labels, account wiring, method label |
| `cmuxTests/ShellXSignInSheetTests.swift` (create) | The sheet lays out in every step; the fixture's email sign-in |

---

### Task 0: Worktree, tools, baseline

**Files:** none (environment only).

- [ ] **Step 1: Create the worktree.** Use superpowers:using-git-worktrees to create `.worktrees/email-code-signin-core-mac` on a new branch `feat/shellx-email-code-signin-core-mac` from `develop`. Every later path is relative to that worktree. This plan and Plan B are untracked in the main checkout: read them from `/Users/richard/Documents/helper/shellx/docs/superpowers/plans/` and do not add them on this branch.
- [ ] **Step 2: Tools.** `cargo` lives in `~/.cargo/bin`, which is not on the default `PATH` here: `export PATH="$HOME/.cargo/bin:$PATH"` in every shell that runs it.
- [ ] **Step 3: Baseline.** Run each and record any failure before changing code (fix nothing unrelated):

```bash
(cd shellx-core && cargo test --workspace --locked)
swift test --package-path Packages/Shared/ShellXBrand
python3 tests/test_shellx_vi.py
python3 scripts/localization_catalog.py check
python3 scripts/verify-local.py --affected develop --swift-changed develop
```
Expected: `test result: ok`, Swift Testing `passed`, unittest `OK`, no catalog errors; `verify-local.py` may fail only `feature-flags` (`ios-feed-performance-release`, known noise in `HANDOFF-shellx-mobile.md`).
- [ ] **Step 4: Native prerequisites for Tasks 6–8.** The Mac app has never been built on this machine: `GhosttyKit.xcframework` is absent and the `ghostty` and `vendor/bonsplit` submodules are not initialized. In the worktree run `./scripts/setup.sh` (CONTRIBUTING.md "Getting Started": submodules, pinned Rust toolchain, checksum-pinned prebuilt GhosttyKit; its requirements list also names the Xcode 26 Metal toolchain and Zig), then `scripts/shellx/test-app.sh ShellXAboutTests`. Expected: `** TEST SUCCEEDED **`. If setup or this run fails for a reason outside this plan (a missing Xcode component, for example), keep the output, do not work around it and never fall back to bare `xcodebuild`: do Tasks 1–5 fully, write Tasks 6–7's code with the parse check only, and report every `test-app.sh` step as "not run on this machine" in Task 8.

---

### Task 1: Fake relay: the two email routes

**Files:**
- Modify: `shellx-core/fake-api/src/lib.rs` (module doc :12-14, `FakeOptions` :59-75 with its `Debug` :78-91 and `Default` :108-123, `TokenInfo` :141-147, `State` :178-216, test hooks beside `revoke_token` :400-403, `route` :653-711, handlers after `delete_account` :1597-1615)
- Create: `shellx-core/fake-api/tests/email.rs`

**Interfaces:**
- Produces (used by Task 2 and by Plan B):

```rust
pub const EMAIL_CODE_TTL_SECS: u64 = 600;
pub const EMAIL_RESEND_SECS: u64 = 60;
pub const EMAIL_CODE_MAX_ATTEMPTS: u32 = 5;
pub struct FakeOptions { /* existing fields */
    /// false: `POST /v1/auth/email/code` answers 503 `email_sign_in_disabled` (a relay without RESEND_API_KEY).
    pub email_sign_in: bool,   // default true
}
impl FakeApi {
    /// The live code for `email` (trimmed, lowercased before the lookup), as the mailbox would show it.
    pub fn email_code(&self, email: &str) -> Option<String>;
    /// Every live email challenge is now past its 600 s.
    pub fn expire_email_codes(&self);
    /// The next request to `path` is answered `status` with `{"error":{"code": code}}`, or with no body when
    /// `code` is empty; the route does not run for it. Calls for one path queue up.
    pub fn fail_next(&self, path: &str, status: u16, code: &str);
}
```

Route rules, in this order. `POST /v1/auth/email/code`: a scripted failure; body not an object → 400 `bad_request`; `!opts.email_sign_in` → 503 `email_sign_in_disabled`; `locale` present and neither `"en"` nor `"vi"` → 400 `bad_request`; `email` not a string, or after trim + lowercase not `local@domain` (local 1–64 characters with no whitespace or `@`; domain of dot-separated non-empty labels, the last one two or more ASCII letters) → 400 `invalid_email`; domain `mailinator.com` or ending `.mailinator.com` → 400 `disposable_email`; else drop that address's older challenges, store `{email, code: random_code(), attempts: 0, expires_at: now + 600}` under a new `challenge_id = random_b64url(32)` and answer 202 `{challenge_id, expires_in: 600, resend_in: 60, email}`.

`POST /v1/auth/email/verify`: a scripted failure; body not an object → 400 `bad_request`; `!device_ok(device)` or `device.kind == "agent"` → 400 `invalid_device` (the challenge is untouched); unknown or expired `challenge_id` → 410 `code_expired` (an expired one is removed); wrong `code` → `attempts += 1`, then 410 `code_expired` and removal when `attempts == 5`, else 401 `invalid_code`; right code → remove the challenge, resolve the user (an identity `provider "email"` with `subject == email` → its user; else the user of `users[email]`: in `password_users` → 409 `switch_from_signed_in_device`, otherwise add the `email` identity to it; else a new user plus the identity), device by `(user, public_key)`, `issue_token(.., "email")`, 200 `{user_id, device_id, token, email}` with the account email as `google_sign_in` computes it. `fail_next` is checked at the top of `route` for every path.

- [ ] **Step 1: Write the failing tests** (`fake-api/tests/email.rs`; it declares its own `request`, `code` and `device` helpers, the same bodies as in `tests/google.rs:10-35,78-80`, since integration tests cannot share them without touching that file):

```rust
const CODE: &str = "/v1/auth/email/code";
const VERIFY: &str = "/v1/auth/email/verify";
// ask(fake, email) -> (status, body) of POST CODE {"email": email, "locale": "en"}
// verify(fake, challenge_id, code, seed) -> (status, body) of POST VERIFY with device(seed)
#[test] fn a_code_request_answers_202_with_the_normalized_email() {
    // POST CODE {"email":"  Foo@Bar.com ","locale":"vi"} -> 202; challenge_id.len() == 43;
    // (expires_in, resend_in) == (600, 60); email == "foo@bar.com";
    // fake.email_code("FOO@bar.com") is Some six ASCII digits
}
#[test] fn bad_addresses_bodies_and_locales_are_refused() {
    // "nope", "a@b", "a b@c.de" -> 400 invalid_email; "a@mailinator.com", "a@x.mailinator.com" -> 400 disposable_email;
    // locale "fr" -> 400 bad_request; body "[]" -> 400 bad_request; fake.email_code(..) is None for each
}
#[test] fn the_right_code_signs_in_once_with_an_email_session() {
    // verify -> 200 with non-empty user_id, device_id, token and email "foo@bar.com";
    // fake.token_auth_method(token) == Some("email"); GET /v1/account/identities with the token lists exactly
    // one item {provider: "email", email: "foo@bar.com"}; the same challenge and code again -> 410 code_expired;
    // fake.email_code("foo@bar.com") is None
}
#[test] fn a_wrong_code_counts_and_the_fifth_kills_the_challenge() {
    // four wrong codes -> 401 invalid_code each; the fifth -> 410 code_expired; then the right code -> 410 code_expired
}
#[test] fn a_new_code_replaces_the_old_one_for_that_address() { /* ask twice: first challenge + its code -> 410; second -> 200 */ }
#[test] fn expired_and_unknown_challenges_are_code_expired() { /* expire_email_codes() -> 410; challenge_id "nope" -> 410 */ }
#[test] fn a_password_account_answers_switch_from_signed_in_device() {
    // POST /v1/auth/login {"email":"a@b.cd","password":"pw","device":device(1)} -> 200; ask "a@b.cd"; verify -> 409
}
#[test] fn a_bad_device_is_invalid_device_and_keeps_the_challenge() {
    // device kind "agent" -> 400 invalid_device; no device -> 400 invalid_device; then device(1) + the code -> 200
}
#[test] fn a_relay_without_email_sign_in_answers_503() { /* FakeOptions { email_sign_in: false, .. } -> 503 email_sign_in_disabled */ }
#[test] fn fail_next_scripts_one_answer_per_call() {
    // fail_next(CODE, 429, "rate_limited") -> 429 rate_limited, then 202;
    // fail_next(CODE, 404, "") -> status 404 with an empty body, then 202
}
```

- [ ] **Step 2: Run to verify they fail.** Run: `(cd shellx-core && cargo test --locked -p shellx-fake-api --test email)`. Expected: compile errors (`email_code`, `fail_next`, `email_sign_in` missing).
- [ ] **Step 3: Commit the failing tests.** `git add shellx-core/fake-api/tests/email.rs && git commit -m "test(shellx-core): fake relay email code routes"`
- [ ] **Step 4: Implement** the Interfaces and the route rules; add the routes to the module doc; `TokenInfo.auth_method`'s comment becomes `"password" | "google" | "email"`.
- [ ] **Step 5: Run to verify they pass.** Run: `(cd shellx-core && cargo test --workspace --locked)`. Expected: `test result: ok` everywhere, no new compiler warning.
- [ ] **Step 6: Commit.** `git add shellx-core/fake-api/src/lib.rs && git commit -m "feat(shellx-core): fake relay answers /v1/auth/email/code and /verify"`

---

### Task 2: `auth.email.begin` and `auth.email.finish`

**Files:**
- Create: `shellx-core/src/auth_email.rs`
- Modify: `shellx-core/src/api.rs` (after `GoogleTokenResponse` :118-129; `SessionFile.auth_method` comment :49)
- Modify: `shellx-core/src/lib.rs` (`mod` list :6-23, `KNOWN_METHODS` :35-65, `dispatch` :147-203)
- Modify: `shellx-core/tests/support/mod.rs`
- Create: `shellx-core/tests/email.rs`

**Interfaces:**
- Consumes: Task 1; `auth::{device_public, device_name, load_session, save_session}`, `http::{send, parse_json}`, `api::{LoginDevice, GoogleAuthResponse, SessionFile}`, `fingerprint::fingerprint`.
- Produces (the contract in "Interfaces for Plan B"):

```rust
// api.rs
/// `POST /v1/auth/email/code` body. Not `Debug` (holds the address).
#[derive(Serialize)] pub struct EmailCodeRequest<'a> { pub email: &'a str, pub locale: &'a str }
/// 202 of `/v1/auth/email/code`. `Debug` shows `expires_in` and `resend_in` only.
#[derive(Deserialize)] pub struct EmailCodeResponse {
    pub challenge_id: String,
    #[serde(default = "…600")] pub expires_in: u64,
    #[serde(default = "…60")] pub resend_in: u64,
    #[serde(default)] pub email: String,
}
/// `POST /v1/auth/email/verify` body. Not `Debug` (holds the code). Its 200 is `GoogleAuthResponse`.
#[derive(Serialize)] pub struct EmailVerifyRequest<'a> { pub challenge_id: &'a str, pub code: &'a str, pub device: LoginDevice<'a> }
// auth_email.rs
pub const CODE_PATH: &str = "/v1/auth/email/code";
pub const VERIFY_PATH: &str = "/v1/auth/email/verify";
/// A value starting with "vi" (any case) is "vi"; anything else, or nothing, is "en".
pub fn locale_of(raw: Option<&str>) -> &'static str;
/// `raw` without ASCII whitespace, when that is exactly six ASCII digits.
pub fn clean_code(raw: &str) -> Option<String>;
pub fn begin(agent: &ureq::Agent, cfg: &Config, params: &Value) -> Result<Value, CoreError>;
pub fn finish(agent: &ureq::Agent, cfg: &Config, store: &StateStore, params: &Value, auth_lock: &Mutex<()>) -> Result<Value, CoreError>;
// lib.rs: KNOWN_METHODS gains "auth.email.begin", "auth.email.finish" after "auth.google.cancel"
// tests/support/mod.rs
/// begin, read the fake's mailbox, finish; finish's result.
pub fn email_sign_in(core: &Core, fake: &FakeApi, email: &str) -> Result<Value, shellx_core::CoreError>;
```

`begin`: params an object, `email` a string (else `invalid_params`); trim it; empty → `invalid_email` with no request; `POST CODE_PATH {email, locale: locale_of(params.locale as str)}` with no bearer; an empty `challenge_id` in the 202 → `server`; result `email` is the reply's, or the trimmed input when the reply's is empty. `finish`: params an object, `challenge_id` a non-empty string and `code` a string (else `invalid_params`); `clean_code(code)` `None` → `invalid_code` with no request; the device exactly as `auth_google`'s sign-in (`kind: "desktop"`, `auth::device_name`, `cfg.platform`, the b64url device public key); `POST VERIFY_PATH` with no bearer; a reply missing `token`, `user_id`, `device_id` or `email` → `server`; then, under `auth_lock`, `save_session` with `auth_method: Some("email")`, the relay's `email` and the previous session's user as `previous_user`. `auth_lock` is never held during a request. Both calls pass every relay error through one mapping: code `not_found`, `http_404` or `email_sign_in_disabled` becomes `CoreError::new("email_sign_in_disabled", "<path>: this relay has no email sign-in")`; every other error is returned as it came. Dispatch clears the shown fingerprints after a successful finish, like `auth.google.finish` (`lib.rs:161-167`).

- [ ] **Step 1: Write the failing tests** (`tests/email.rs`; `REG` as in `tests/auth_google.rs:7`; `session_json(dir)` as in `tests/auth_google.rs:9-11`; `begin(core, email)` = `core.call("auth.email.begin", json!({"email": email, "locale": "en"}))`):

```rust
#[test] fn begin_asks_the_relay_for_a_code_and_returns_the_challenge() {
    // auth.email.begin {"email":"  Foo@Bar.com ","locale":"vi-VN"} -> challenge_id.len() == 43,
    // (expires_in, resend_in) == (600, 60), email == "foo@bar.com";
    // the one recorded request: POST CODE_PATH, body == {"email":"Foo@Bar.com","locale":"vi"}, no Authorization header;
    // no session.json
}
#[test] fn locale_is_vi_or_en() { /* locale "VI" -> body.locale "vi"; "ja" -> "en"; no locale -> "en"; locale 5 -> "en" */ }
#[test] fn finish_signs_in_and_writes_an_email_session() {
    // r = support::email_sign_in(&core, &fake, "Foo@Bar.com").unwrap();
    // (r["email"], r["auth_method"]) == ("foo@bar.com", "email"); user_id, device_id, device_public_key_b64, fingerprint
    // non-empty; r.get("token").is_none(); session.json has auth_method "email" and email "foo@bar.com", mode 0o600 on unix;
    // fake.token_auth_method(&fake.issued_token()) == Some("email");
    // the VERIFY_PATH request: device.kind "desktop", device.platform "macos", device.public_key == r["device_public_key_b64"],
    // code == the mailbox code, no Authorization header;
    // auth.session -> auth_method "email", email "foo@bar.com"; machines.list -> []
}
#[test] fn a_pasted_code_with_spaces_is_sent_as_six_digits() {
    // code c from the mailbox; finish with format!(" {} {}\n", &c[..3], &c[3..]) -> Ok; the VERIFY_PATH body.code == c
}
#[test] fn a_code_that_is_not_six_digits_is_invalid_code_without_a_request() {
    // "12345", "1234567", "12a456", "" -> invalid_code each; no VERIFY_PATH request was recorded;
    // then the mailbox code -> Ok (no guess was burned)
}
#[test] fn a_wrong_code_is_invalid_code_and_the_fifth_is_code_expired() { /* 4 x invalid_code, then code_expired; no session.json */ }
#[test] fn an_expired_or_reused_code_is_code_expired() {
    // fake.expire_email_codes() -> code_expired; after a successful sign-in the same challenge and code -> code_expired
    // and session.json is unchanged
}
#[test] fn relay_refusals_keep_their_codes() {
    // begin "nope" -> invalid_email; "a@mailinator.com" -> disposable_email;
    // fail_next(CODE_PATH, 429, "rate_limited") -> rate_limited; fail_next(CODE_PATH, 502, "email_send_failed") -> email_send_failed;
    // finish: fail_next(VERIFY_PATH, 429, "rate_limited") -> rate_limited; fail_next(VERIFY_PATH, 400, "invalid_device") -> invalid_device
}
#[test] fn a_relay_without_email_sign_in_is_email_sign_in_disabled() {
    // FakeOptions { email_sign_in: false, .. }: begin -> email_sign_in_disabled;
    // default fake: fail_next(CODE_PATH, 404, "not_found") -> email_sign_in_disabled; fail_next(CODE_PATH, 404, "") -> the same;
    // after a real begin, fail_next(VERIFY_PATH, 404, "not_found") -> finish is email_sign_in_disabled; no session.json
}
#[test] fn offline_is_network() {
    // configured with api_base "http://127.0.0.1:1": begin -> network; finish {"challenge_id":"c","code":"123456"} -> network;
    // no session.json
}
#[test] fn a_password_account_email_answers_switch_from_signed_in_device() {
    // auth.login {"email":"a@b.cd","password":"pw"}; begin "a@b.cd"; finish -> switch_from_signed_in_device;
    // session.json still has auth_method "password"
}
#[test] fn an_email_code_signs_into_the_google_account_with_that_address() {
    // (core, fake, _) = support::google_logged_out(); g = support::google_sign_in(&core, "sign_in"); auth.logout;
    // e = support::email_sign_in(&core, &fake, "google-user@shellx.test"); e["user_id"] == g["user_id"];
    // account.identities.list providers == ["google", "email"]
}
#[test] fn email_sign_in_after_a_401_keeps_the_device_id_and_machine() {
    // email sign-in, machines.register REG, fake.revoke_token(issued), machines.list -> unauthorized (machine.json and
    // device.key stay); email sign-in again -> same user_id and device_id; machines.list has is_this_machine true
}
#[test] fn params_are_checked() {
    // begin: json!("x"), {}, {"email": 5} -> invalid_params; {"email": "   "} -> invalid_email and no request;
    // finish: {}, {"challenge_id":"c"}, {"challenge_id":"","code":"123456"}, {"challenge_id":5,"code":"123456"} -> invalid_params
}
#[test] fn secrets_never_reach_results_or_errors() {
    // finish's result (as a string) contains neither the issued token, the mailbox code nor the challenge_id;
    // the messages of an invalid_code, a code_expired, a rate_limited and an email_sign_in_disabled error contain none of
    // the token, the code, the challenge_id or "foo@bar.com";
    // format!("{:?}") of an EmailCodeResponse parsed from {"challenge_id":"CH-SECRET","email":"foo@bar.com"} contains
    // neither "CH-SECRET" nor "foo@bar.com"
}
```

Unit tests in `src/auth_email.rs`: `locale_of` (`Some("vi")`, `Some("Vi-VN")` → `"vi"`; `Some("en")`, `Some("ja")`, `None` → `"en"`) and `clean_code` (`"123456"`, `" 123 456\n"` → `Some("123456")`; `"12345"`, `"1234567"`, `"12a456"`, `"１２３４５６"` → `None`).

- [ ] **Step 2: Run to verify they fail.** Run: `(cd shellx-core && cargo test --locked --test email)`. Expected: compile error (`support::email_sign_in` missing) or `unknown_method` failures.
- [ ] **Step 3: Commit the failing tests.** `git add shellx-core/tests && git commit -m "test(shellx-core): email code sign-in RPCs"`
- [ ] **Step 4: Implement** the Interfaces, the dispatch arms and the two `KNOWN_METHODS` names; `SessionFile.auth_method`'s comment becomes `"password" | "google" | "email"`.
- [ ] **Step 5: Run to verify they pass.** Run: `(cd shellx-core && cargo test --workspace --locked) && git diff --quiet develop -- shellx-core/Cargo.lock && echo lock-unchanged`. Expected: `test result: ok` everywhere, no new compiler warning, `lock-unchanged`.
- [ ] **Step 6: Commit.** `git add shellx-core/src shellx-core/tests && git commit -m "feat(shellx-core): auth.email.begin and auth.email.finish"`

---

### Task 3: Swift core client and `ShellXAccount`

**Files:**
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/ShellXCoreClient+Email.swift`
- Modify: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/ShellXAccount.swift` (`Identity.authMethod` comment :21; a new `// MARK: - Email code` section after `cancelGoogleSignIn` :161-167)
- Modify: `Packages/Shared/ShellXBrand/Tests/ShellXRemoteCoreTests/ServiceTestSupport.swift` (`FakeRemoteCore` state :20-29 and `call` :91-166)
- Create: `Packages/Shared/ShellXBrand/Tests/ShellXRemoteCoreTests/ShellXCoreClientEmailTests.swift`
- Modify: `Packages/Shared/ShellXBrand/Tests/ShellXRemoteCoreTests/ShellXAccountTests.swift`

**Interfaces:**
- Consumes: the RPC contract; `GoogleSignInResult`; `ShellXRemoteService.{ensureConfigured, prepareLocal, beginSignedInSession, offMain}`.
- Produces:

```swift
// ShellXCoreClient+Email.swift
/// A code the relay mailed: the id to verify it with and the address it went to (normalized by the relay).
public struct EmailCodeChallenge: Equatable, Sendable {
    public let challengeID: String
    public let email: String
    public let expiresIn: TimeInterval   // 600
    public let resendIn: TimeInterval    // 60
    public init(challengeID: String, email: String, expiresIn: TimeInterval, resendIn: TimeInterval)
}
extension ShellXCoreClient {
    /// `auth.email.begin`. Throws `bad_response` when the reply has no challenge id.
    public func beginEmailSignIn(email: String, locale: String) throws -> EmailCodeChallenge
    /// `auth.email.finish`.
    public func finishEmailSignIn(challengeID: String, code: String) throws -> GoogleSignInResult
}
// ShellXAccount
/// Asks the relay to mail a sign-in code. Changes no session. Throws the core's code.
public func requestEmailCode(email: String, locale: String) async throws -> EmailCodeChallenge
/// Verifies the code and signs in like a Google `.signIn`: with the gate on it starts the remote session;
/// saves `Identity(authMethod: "email")`. Throws the core's code; nothing is saved then.
@discardableResult public func signInWithEmailCode(challengeID: String, code: String) async throws -> Identity
```

`FakeRemoteCore` gains `let emailCode = Locked("123456")` and two cases: `auth.email.begin` (a string `email`, else `invalid_params`) remembers the trimmed, lowercased address and answers `{"challenge_id":"ch-1","expires_in":600,"resend_in":60,"email":<that address>}`; `auth.email.finish` answers `code_expired` unless `challenge_id == "ch-1"`, `invalid_code` unless `code == emailCode.get()`, else sets `signedIn`, `sessionEmail`, `sessionAuthMethod = "email"` and answers like `auth.google.finish` with that address and `auth_method: "email"`. The log line after a sign-in names no address.

- [ ] **Step 1: Write the failing tests.** `ShellXCoreClientEmailTests.swift` (the `client`, `params` helpers as in `ShellXCoreClientGoogleTests.swift:5-16`):

```swift
@Test func beginSendsTheAddressAndLocaleAndReturnsTheChallenge() throws
// reply {"ok":{"challenge_id":"ch1","expires_in":600,"resend_in":60,"email":"foo@bar.com"}}; beginEmailSignIn(email: "Foo@Bar.com", locale: "vi");
// method "auth.email.begin"; params == ["email": .string("Foo@Bar.com"), "locale": .string("vi")];
// result == EmailCodeChallenge(challengeID: "ch1", email: "foo@bar.com", expiresIn: 600, resendIn: 60)
@Test func beginRefusesAReplyWithoutAChallenge()   // "challenge_id":"" -> ShellXCoreError code "bad_response"
@Test func finishSendsTheChallengeAndCodeAndReturnsTheAccount() throws
// method "auth.email.finish"; params == ["challenge_id": .string("ch1"), "code": .string("123456")];
// result == GoogleSignInResult(userID: "u1", deviceID: "d1", email: "foo@bar.com", authMethod: "email")
@Test func emailCallsKeepTheCoreErrorCode()        // {"error":{"code":"invalid_code","message":"x"}} -> code "invalid_code"
```

`ShellXAccountTests.swift`, a new section:

```swift
@MainActor @Test func emailCodeRequestConfiguresTheCoreAndChangesNoSession() async throws
// ServiceRig(gate: false, signedIn: false); requestEmailCode(email: "Foo@Bar.com", locale: "vi") -> challenge.email "foo@bar.com";
// rig.core.methods == ["config.set", "auth.email.begin"]; lastParams == ["email": "Foo@Bar.com", "locale": "vi"]; identity nil
@MainActor @Test func emailCodeSignsInAndSavesTheEmailIdentity() async throws
// then signInWithEmailCode(challengeID: challenge.challengeID, code: "123456"): identity.email "foo@bar.com",
// authMethod "email", usesPassword false, signedInAt != nil; ShellXAccount(service: rig.service).identity == account.identity;
// rig.launcher.calls.isEmpty; !rig.service.isSignedIn
@MainActor @Test func emailCodeSignInWithTheGateOnStartsTheSession() async throws
// ServiceRig(signedIn: false): rig.service.isSignedIn; await until { rig.service.hostState == rig.hostConnected }
@MainActor @Test func aWrongEmailCodeKeepsSignedOutAndCanBeRetried() async throws
// code "000000" -> errorCode "invalid_code", identity nil; then "123456" -> identity?.authMethod == "email"
```

- [ ] **Step 2: Run to verify they fail.** Run: `swift test --package-path Packages/Shared/ShellXBrand --filter "ShellXCoreClientEmailTests|emailCode|aWrongEmailCode"`. Expected: compile errors (`beginEmailSignIn`, `requestEmailCode` missing).
- [ ] **Step 3: Commit the failing tests.** `git add Packages/Shared/ShellXBrand/Tests/ShellXRemoteCoreTests && git commit -m "test(shellx): email code sign-in through the core client and the account"`
- [ ] **Step 4: Implement** the Interfaces. `signInWithEmailCode` mirrors the `.signIn` branch of `signInWithGoogle` (`ShellXAccount.swift:130-157`) without the browser: `prepareLocal()` with the gate on, `ensureConfigured()`, the core call off the main actor, `beginSignedInSession` with the gate on, `save`.
- [ ] **Step 5: Run to verify they pass.** Run: `swift test --package-path Packages/Shared/ShellXBrand`. Expected: all tests passed.
- [ ] **Step 6: Commit.** `git add Packages/Shared/ShellXBrand && git commit -m "feat(shellx): the account requests and verifies an email sign-in code"`

---

### Task 4: Sign-in error sentences for the email codes

**Files:**
- Modify: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteUI/SignInErrorMessage.swift`
- Modify: `Packages/Shared/ShellXBrand/Tests/ShellXRemoteUITests/ShellXRemoteUITests.swift:209-228` (`signInErrorMapping`)
- Modify: `Sources/ShellX/Remote/UI/RemoteUISnapshot.swift:28-58` (`SignInErrorLabels.localized`)
- Modify: `Resources/Localizable.xcstrings`, `tests/test_shellx_vi.py`; `scripts/localization-allowed-omissions.json` only if an identity record is needed

**Interfaces:**
- Produces:

```swift
public struct SignInErrorLabels: Equatable, Sendable {
    // existing eight, then:
    public let invalidEmail, disposableEmail, invalidCode, codeExpired, emailSendFailed, unavailable, rateLimited: String
    public init(credentials: String, network: String, timeout: String, stateMismatch: String,
                switchFromSignedInDevice: String, emailInUse: String, identityInUse: String, browser: String,
                invalidEmail: String, disposableEmail: String, invalidCode: String, codeExpired: String,
                emailSendFailed: String, unavailable: String, rateLimited: String)
    public static let english   // the en column of the String table for the seven new labels
}
// SignInErrorMessage.text(forCode:labels:) also maps: invalid_email, disposable_email, invalid_code, code_expired,
// email_send_failed, email_sign_in_disabled -> unavailable, rate_limited. Any other code is still returned as is.
```

- [ ] **Step 1: Write the failing tests.** `signInErrorMapping`: build `labels` with the new init (new labels `"ie"`, `"de"`, `"ic"`, `"ce"`, `"sf"`, `"un"`, `"rl"`); the existing `rate_limited` line becomes `text(for: ShellXCoreError(code: "weak_password", message: "x"), labels:) == "weak_password"`; add

```swift
for (code, text) in [("invalid_email", "ie"), ("disposable_email", "de"), ("invalid_code", "ic"), ("code_expired", "ce"),
                     ("email_send_failed", "sf"), ("email_sign_in_disabled", "un"), ("rate_limited", "rl")] {
    #expect(SignInErrorMessage.text(forCode: code, labels: labels) == text)
}
#expect(SignInErrorLabels.english.unavailable == "This way of signing in isn't available in this build.")
```

`tests/test_shellx_vi.py`, in `VietnameseCatalogTests`:

```python
def test_email_sign_in_errors_read_naturally(self):
    expected = {...}  # the seven remote.signin.error.* rows of the plan's String table: key -> (en, vi)
    for key, (en, vi) in expected.items():
        self.assertEqual((self.en(key), self.vi(key)), (en, vi), key)
```

- [ ] **Step 2: Run to verify they fail.** Run: `swift test --package-path Packages/Shared/ShellXBrand --filter signInErrorMapping; python3 tests/test_shellx_vi.py VietnameseCatalogTests.test_email_sign_in_errors_read_naturally`. Expected: Swift compile error (extra arguments in the call); Python FAIL (`(None, None) != …`).
- [ ] **Step 3: Commit the failing tests.** `git add Packages/Shared/ShellXBrand/Tests/ShellXRemoteUITests/ShellXRemoteUITests.swift tests/test_shellx_vi.py && git commit -m "test(shellx): sign-in error sentences for the email codes"`
- [ ] **Step 4: Implement** the labels, the mapping and `SignInErrorLabels.localized` (seven `String(localized:defaultValue:)` with the String table's keys and English).
- [ ] **Step 5: Localize.** Run `./scripts/localize-changes --base develop`, fill every row of the printed work packet (`vi` exactly from the table; translate de, fr, ar, es, zh-Hant, zh-Hans, ko, ja), run it again. Expected last line: `Localization ready: changed work is complete and the strict catalog validator passed.`
- [ ] **Step 6: Run to verify they pass.** Run: `swift test --package-path Packages/Shared/ShellXBrand && python3 tests/test_shellx_vi.py && python3 scripts/localization_catalog.py check && python3 scripts/verify-local.py --affected develop --swift-changed develop && scripts/shellx/test-app.sh ShellXAboutTests`. Expected: tests passed, `OK`, no catalog errors, `verify-local.py` clean but for the known `feature-flags` noise, `** TEST SUCCEEDED **` (the app compiles with the longer `SignInErrorLabels` init).
- [ ] **Step 7: Commit.** `git add Packages/Shared/ShellXBrand/Sources/ShellXRemoteUI/SignInErrorMessage.swift Sources/ShellX/Remote/UI/RemoteUISnapshot.swift Resources/Localizable.xcstrings scripts/localization-allowed-omissions.json && git commit -m "feat(shellx): sign-in errors read as sentences for the email codes and 429"`

---

### Task 5: `EmailSignInModel`

**Files:**
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteUI/EmailSignInModel.swift`
- Create: `Packages/Shared/ShellXBrand/Tests/ShellXRemoteUITests/EmailSignInModelTests.swift`

**Interfaces:**
- Consumes: `EmailCodeChallenge` (Task 3), `SignInErrorLabels`, `SignInErrorMessage` (Task 4).
- Produces:

```swift
/// State of the email-code part of the sign-in sheet. The two calls are injected (`ShellXAccount`), so this
/// module stays free of the account and the bundle.
@MainActor @Observable public final class EmailSignInModel {
    public enum Step: Equatable, Sendable { case idle, email, sending, code, verifying, done(email: String) }
    public static let codeLength = 6
    public private(set) var step: Step            // .idle at first
    public private(set) var errorText: String?    // the last failure as a sentence
    public private(set) var sentTo: String?       // the relay's address for the live code; nil before the first one
    public private(set) var code: String          // ASCII digits only, at most six
    public var canVerify: Bool { get }            // .code, a live challenge, six digits
    @ObservationIgnored public var onFinished: (@MainActor (Bool) -> Void)?   // once: true after `finish()`, false after `cancel()`
    public init(labels: SignInErrorLabels,
                requestCode: @escaping @MainActor (String) async throws -> EmailCodeChallenge,
                verify: @escaping @MainActor (String, String) async throws -> String,   // (challengeID, code) -> account email
                now: @escaping @MainActor () -> Date = { Date() })
    /// Text before and after an "@", then a "." with text on both sides, and no whitespace inside (after trimming).
    public static func isPlausibleEmail(_ text: String) -> Bool
    /// The ASCII digits of `raw`, at most the first six.
    public static func digits(_ raw: String) -> String
    public func begin()                                                              // .idle -> .email
    @discardableResult public func sendCode(to email: String) -> Task<Void, Never>?  // from .email, plausible address
    @discardableResult public func resend() -> Task<Void, Never>?                    // from .code once the lock is over
    public func resendWait(at date: Date) -> Int                                     // whole seconds left, rounded up; 0 = unlocked
    @discardableResult public func setCode(_ raw: String) -> Task<Void, Never>?      // stores digits(raw); may submit
    @discardableResult public func submitCode() -> Task<Void, Never>?                // from .code when canVerify
    public func useDifferentEmail()                                                  // .code -> .email
    public func cancel()
    public func finish()                                                             // only in .done
}
```

Rules. `sendCode` trims the address, goes to `.sending` at once with `errorText` nil and calls `requestCode`; success → `.code` with `sentTo = challenge.email`, an empty `code` and the lock ending at `now() + challenge.resendIn`; failure → `.email` with the sentence. `resend` (same address) does nothing while `resendWait(at: now()) > 0`; it goes through `.sending`; failure → back to `.code` with the old challenge kept, the sentence shown and the lock ended. `setCode` submits by itself when the step is `.code`, a challenge is live, the digits number six and differ from the last submitted code; `submitCode` is the manual path (it may repeat the same code). Verifying: success → `.done(email:)`; failure → `.code` with the sentence and the digits kept; `code_expired` also drops the challenge (so `canVerify` is false) and ends the lock. A non-core error reads as the network sentence. `useDifferentEmail` drops the challenge, `sentTo`, the code and the error. `cancel` reports `false` once and makes every answer still on its way a no-op; `finish` reports `true` once. An answer that belongs to an earlier request (after `useDifferentEmail`, `cancel` or a newer request) is ignored.

- [ ] **Step 1: Write the failing tests** (`EmailSignInModelTests.swift`; a `@MainActor` `Gate<Value>` like `GoogleSignInModelTests.swift:7-17` keeps `requestCode` or `verify` pending and records its arguments; a `@MainActor final class Clock { var now = Date(timeIntervalSince1970: 1_000) }` is the injected clock; `challenge("ch-1")` = `EmailCodeChallenge(challengeID: "ch-1", email: "foo@bar.com", expiresIn: 600, resendIn: 60)`; `toCodeStep()` drives `begin()`, `sendCode(to: "Foo@Bar.com")` and the challenge):

```swift
@MainActor @Test func continueWithEmailShowsTheEmailStep()           // .idle; begin() -> .email; sendCode(to: "nope") -> nil, still .email
@MainActor @Test func plausibleEmailNeedsAnAtAndADotAfterIt()        // true: "a@b.c", " a@b.co "; false: "", "a@b", "a@.c", "a@b.", "@b.c", "a b@c.d"
@MainActor @Test func sendCodeShowsSendingThenTheCodeStep() async    // sendCode(to: "  Foo@Bar.com ") -> .sending at once; requestCode got "Foo@Bar.com";
                                                                     // after the challenge: .code, sentTo "foo@bar.com", errorText nil, resendWait(at: clock.now) == 60
@MainActor @Test func sendCodeTwiceSendsOnce() async                 // the second sendCode returns nil; requestCode ran once
@MainActor @Test func aRefusedAddressReturnsToTheEmailStepWithItsSentence() async   // invalid_email -> .email + labels.invalidEmail;
                                                                     // disposable_email -> labels.disposableEmail; email_send_failed -> labels.emailSendFailed; then a send works
@MainActor @Test func aRelayWithoutEmailSignInSaysUnavailable() async               // email_sign_in_disabled -> .email + labels.unavailable
@MainActor @Test func offlineShowsTheNetworkMessageAndAllowsRetry() async           // requestCode throws URLError(.notConnectedToInternet) ->
                                                                     // .email + labels.network; sendCode again reaches .code
@MainActor @Test func pastedCodeKeepsOnlySixDigits() async           // digits(" 123 456\n") == "123456"; digits("12a34") == "1234";
                                                                     // digits("1234567890") == "123456"; digits("１２３") == ""; on the code step setCode("12 3") -> code "123", no task
@MainActor @Test func sixDigitsSubmitByThemselvesOnce() async        // setCode("123 456") returns a task; .verifying; verify got ("ch-1", "123456");
                                                                     // setCode("123456") and submitCode() while verifying -> nil; verify ran once; resolve "foo@bar.com" -> .done(email: "foo@bar.com")
@MainActor @Test func aWrongCodeStaysOnTheCodeStepAndIsNotSentAgainByItself() async // invalid_code -> .code + labels.invalidCode, code "123456";
                                                                     // setCode("123456") -> nil; submitCode() -> a task (verify ran twice); setCode("654321") submits
@MainActor @Test func anExpiredCodeAsksForANewOneAndUnlocksResend() async           // code_expired -> .code + labels.codeExpired, !canVerify,
                                                                     // resendWait(at: clock.now) == 0; resend() -> requestCode got "Foo@Bar.com" again; with challenge("ch-2") a code verifies against "ch-2"
@MainActor @Test func resendIsLockedForSixtySecondsAndCountsDown() async            // from the code step at t0: resendWait(at: t0) == 60, (t0 + 0.5) == 60,
                                                                     // (t0 + 59.2) == 1, (t0 + 60) == 0; clock.now = t0 + 30: resend() == nil; clock.now = t0 + 60: resend() runs,
                                                                     // .sending, then .code with resendWait(at: clock.now) == 60
@MainActor @Test func aFailedResendKeepsTheCodeStepAndUnlocksAgain() async          // resend fails rate_limited -> .code + labels.rateLimited, sentTo kept,
                                                                     // resendWait(at: clock.now) == 0; a code still verifies against "ch-1"
@MainActor @Test func useADifferentEmailGoesBackAndDropsTheChallenge() async        // -> .email, sentTo nil, code "", errorText nil; submitCode() == nil
@MainActor @Test func cancelWhileSendingIgnoresTheLateChallenge() async             // cancel() -> onFinished values [false]; then the challenge arrives: step is not .code
@MainActor @Test func cancelWhileVerifyingClosesOnceAndIgnoresTheResult() async     // cancel() while verifying -> [false]; verify succeeds: step is not .done,
                                                                     // values still [false]; finish() adds nothing
@MainActor @Test func doneReportsOnceWhenThePersonConfirms() async                  // .done: finish() -> [true]; finish() and cancel() add nothing
```

- [ ] **Step 2: Run to verify they fail.** Run: `swift test --package-path Packages/Shared/ShellXBrand --filter EmailSignInModelTests`. Expected: compile errors (`EmailSignInModel` not found).
- [ ] **Step 3: Commit the failing tests.** `git add Packages/Shared/ShellXBrand/Tests/ShellXRemoteUITests/EmailSignInModelTests.swift && git commit -m "test(shellx): email sign-in sheet model"`
- [ ] **Step 4: Implement** the model (a request counter compared when each answer arrives makes late answers no-ops).
- [ ] **Step 5: Run to verify they pass.** Run: `swift test --package-path Packages/Shared/ShellXBrand`. Expected: all tests passed.
- [ ] **Step 6: Commit.** `git add Packages/Shared/ShellXBrand/Sources/ShellXRemoteUI/EmailSignInModel.swift && git commit -m "feat(shellx): email sign-in sheet model with a resend lock"`

---

### Task 6: The sign-in sheet shows "Continue with email", the email step and the code step

**Files:**
- Modify: `Sources/ShellX/Remote/UI/ShellXRemoteServicing.swift:28-33`
- Modify: `Sources/ShellX/Remote/UI/ShellXRemoteFixtureService.swift:181-194`
- Create: `Sources/ShellX/Remote/UI/EmailSignInSection.swift` (wire it with `./scripts/wire-app-sources.py Sources/ShellX/Remote/UI/EmailSignInSection.swift`, which edits `cmux.xcodeproj/project.pbxproj`)
- Modify: `Sources/ShellX/Remote/UI/SignInSheet.swift` (`SignInSheet` :9-113, `SignInSheetPresenter` :149-208)
- Modify: `Sources/ShellX/ShellXAccountFlow.swift:64-72`
- Create: `cmuxTests/ShellXSignInSheetTests.swift` (then `./scripts/sync-test-wiring`)
- Modify: `Resources/Localizable.xcstrings`, `tests/test_shellx_vi.py`; `scripts/localization-allowed-omissions.json` only if needed

**Interfaces:**
- Consumes: `EmailSignInModel` (Task 5), `ShellXAccount.requestEmailCode` / `signInWithEmailCode` (Task 3), `SignInErrorLabels.localized` (Task 4).
- Produces:

```swift
// ShellXRemoteServicing
/// Mails a sign-in code to `email`. Throws `ShellXCoreError`.
func requestEmailCode(email: String, locale: String) async throws -> EmailCodeChallenge
/// Verifies the code and signs in; returns the account email. Throws `ShellXCoreError`.
func signInWithEmailCode(challengeID: String, code: String) async throws -> String
// EmailSignInSection.swift
/// The email and code steps (`.email`, `.sending`, `.code`, `.verifying`); draws nothing in `.idle` and `.done`.
struct EmailSignInSection: View { let model: EmailSignInModel }
// SignInSheet
struct SignInSheet: View { let model: GoogleSignInModel; let email: EmailSignInModel? }   // email is nil for `.link`
// SignInSheetPresenter
func present(model: GoogleSignInModel, email: EmailSignInModel? = nil, preferredWindow: NSWindow? = nil)
// ShellXAccountFlow
/// The language the app's strings are shown in, for the email's language.
static var emailLocale: String { Bundle.main.preferredLocalizations.first ?? "en" }
```

Sheet rules (width 340, `ShellXPalette`, `ShellXSheetButtonStyle` as today):
- First screen (Google `.ready`, email `.idle`): the Google button as today; under it a centred muted `remote.signin.email.or`; under that a secondary button `remote.signin.email.continue` calling `email.begin()`. While Google is `.waiting` the "or" line and that button are hidden.
- While the email step is not `.idle`, the Google button, the "or" line and the "Continue with email" button are hidden and `EmailSignInSection` is shown.
- Email entry (`sentTo == nil`, step `.email` or `.sending`): a `TextField` with placeholder `remote.signin.email`, `.textContentType(.username)`, autocorrection off, focused when the step appears, disabled while `.sending`; a primary `remote.signin.email.send` button with `.keyboardShortcut(.defaultAction)`, enabled only in `.email` when `EmailSignInModel.isPlausibleEmail(text)`; a small `ProgressView` beside it while `.sending`.
- Code entry (`sentTo != nil`, step `.code`, `.verifying` or `.sending`): `remote.signin.email.sentTo` with the address (it wraps; no line limit); a `TextField` with placeholder `remote.signin.email.code`, `.textContentType(.oneTimeCode)`, monospaced digits, bound with `Binding(get: { model.code }, set: { model.setCode($0) })`, focused when the step appears, disabled unless `.code`; a primary `remote.signin.email.verify` (`.defaultAction`) enabled when `canVerify`, with a small `ProgressView` while `.verifying`; a row with `remote.signin.email.resend` and `remote.signin.email.change`, both enabled only in `.code`. The resend button sits in `TimelineView(.periodic(from: .now, by: 1))`: with `model.resendWait(at: context.date) > 0` it is disabled and reads `remote.signin.email.resendIn` with `String(wait)`.
- Email `.done(email)`: the "Signed in as %@" block and `remote.signin.done` as for Google's `.signedIn`, calling `email.finish()`.
- The error line shows `email.errorText` while the email step is not `.idle`, else `model.errorText`. Cancel is hidden in Google `.signedIn` and email `.done`; it calls `email?.cancel()` and `model.cancel()`.
- Every text field has an explicit width inside the 340 pt sheet (`CloudSheetWindow` resizes the window from the content; a control sized by the width it is offered loops, see `Sources/Cloud/CloudSheetWindow.swift:6-21`).

Presenter: `present(model:email:)` sets `onFinished` of both models to `dismiss()` and keeps both; `present(service:)` builds an `EmailSignInModel(labels: .localized, requestCode: { try await service.requestEmailCode(email: $0, locale: ShellXAccountFlow.emailLocale) }, verify: { try await service.signInWithEmailCode(challengeID: $0, code: $1) })`. `ShellXAccountFlow.presentGoogleSheet(.signIn)` builds the same over `account.requestEmailCode` and `account.signInWithEmailCode(...).email`; `.link` passes `nil`. The fixture: `requestEmailCode` waits 400 ms and returns `EmailCodeChallenge(challengeID: "fixture-challenge", email: <trimmed, lowercased>, expiresIn: 600, resendIn: 60)`; `signInWithEmailCode` throws `ShellXCoreError(code: "invalid_code", …)` unless the code is `ShellXRemoteFixtureService.requestCode`, else signs in as `signInWithGoogle` does (share that state change) and returns the address of the last request.

- [ ] **Step 1: Write the failing tests.** `tests/test_shellx_vi.py`:

```python
def test_email_sign_in_sheet_strings_read_naturally(self):
    expected = {...}  # the nine remote.signin.email.* rows of the String table plus "remote.signin.email": ("Email", "Địa chỉ email")
    for key, (en, vi) in expected.items():
        self.assertEqual((self.en(key), self.vi(key)), (en, vi), key)
```

`cmuxTests/ShellXSignInSheetTests.swift` (imports and the `cmux_DEV` / `cmux` switch as in `cmuxTests/ShellXAboutTests.swift:1-9`, plus `AppKit`, `SwiftUI`, `ShellXRemoteCore`, `ShellXRemoteUI`):

```swift
@MainActor @Suite("ShellX sign-in sheet") struct ShellXSignInSheetTests {
    // google() = GoogleSignInModel(purpose: .signIn, labels: .english, signIn: { "g@shellx.test" }, cancel: {})
    // email() = EmailSignInModel(labels: .english, requestCode: { _ in EmailCodeChallenge(challengeID: "c", email: "foo@bar.com",
    //           expiresIn: 600, resendIn: 60) }, verify: { _, _ in "foo@bar.com" })
    // size(_ sheet: SignInSheet) = NSHostingView(rootView: sheet).fittingSize
    @Test func everyStepLaysOutAtTheSheetWidth() async
    // first screen; after begin(); after sendCode(to: "foo@bar.com") completed (.code); after setCode("123456") completed (.done):
    // each size has width 340 and height > 0; the code step is taller than the first screen
    @Test func theSwitchSheetHasNoEmailPath()
    // SignInSheet(model: GoogleSignInModel(purpose: .link, …), email: nil) has width 340 and height > 0
    @Test func theFixtureSignsInOnlyWithItsCode() async throws
    // let fixture = ShellXRemoteFixtureService(); requestEmailCode(email: " Dev@Shellx.Dev ", locale: "en").email == "dev@shellx.dev";
    // signInWithEmailCode(challengeID:, code: "000000") throws code "invalid_code" and !fixture.isSignedIn;
    // with ShellXRemoteFixtureService.requestCode it returns "dev@shellx.dev" and fixture.isSignedIn
}
```

- [ ] **Step 2: Run to verify they fail.** Run: `python3 tests/test_shellx_vi.py VietnameseCatalogTests.test_email_sign_in_sheet_strings_read_naturally; ./scripts/sync-test-wiring && scripts/shellx/test-app.sh ShellXSignInSheetTests`. Expected: Python FAIL; the test target does not compile (`SignInSheet` has no `email:`, the fixture has no `requestEmailCode`).
- [ ] **Step 3: Commit the failing tests.** `git add tests/test_shellx_vi.py cmuxTests/ShellXSignInSheetTests.swift cmux.xcodeproj/project.pbxproj && git commit -m "test(shellx): email steps of the sign-in sheet"`
- [ ] **Step 4: Implement** the Interfaces and the sheet rules; wire the new app file.
- [ ] **Step 5: Localize** as in Task 4 Step 5 (nine new keys; `remote.signin.email` already has its ten locales). Expected last line: `Localization ready: changed work is complete and the strict catalog validator passed.`
- [ ] **Step 6: Run to verify they pass.** Run: `python3 tests/test_shellx_vi.py && python3 scripts/localization_catalog.py check && ./scripts/wire-app-sources.py --check && ./scripts/sync-test-wiring --check && python3 scripts/verify-local.py --affected develop --swift-changed develop && swift test --package-path Packages/Shared/ShellXBrand && scripts/shellx/test-app.sh ShellXSignInSheetTests ShellXAboutTests`. Expected: `OK`, no catalog errors, both wiring checks exit 0, Swift tests passed, `** TEST SUCCEEDED **` with the three new tests executed (not zero).
- [ ] **Step 7: Look at it (do not commit).** Add to `ShellXSignInSheetTests` a temporary test that hosts each of the four steps in an `NSHostingView` sized to its `fittingSize` and writes it with `cacheDisplay(in:to:)` as a PNG under `NSTemporaryDirectory()` (the file name carries `Bundle.main.preferredLocalizations.first`); run `scripts/shellx/test-app.sh ShellXSignInSheetTests -- -testLanguage en` and again with `-- -testLanguage vi`; open the PNGs; then `git checkout cmuxTests/ShellXSignInSheetTests.swift`. If the second run still renders English, say so in the hand-off instead of trying other ways to switch the language. Expected: a dark 340 pt panel; first screen with the white Google button, "or" and "Continue with email"; the email field with "Send code"; the code step with the two-sentence address line, the code field, "Verify", "Resend code in 60 s" and "Use a different email"; no clipped or overlapping text; `git status` shows no change from this step.
- [ ] **Step 8: Commit.** `git add Sources/ShellX cmux.xcodeproj/project.pbxproj Resources/Localizable.xcstrings scripts/localization-allowed-omissions.json && git commit -m "feat(shellx): the Mac signs in with an email code next to Google"`

---

### Task 7: Settings › Account names the email method

**Files:**
- Modify: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/ShellXCoreClient+Google.swift:27-42` (`AccountSignInMethod`)
- Modify: `Packages/Shared/ShellXBrand/Tests/ShellXRemoteCoreTests/ShellXCoreClientEmailTests.swift`
- Modify: `Sources/ShellX/ShellXAccountDetailView.swift:70-98` (`methodRow`)
- Modify: `Resources/Localizable.xcstrings`, `tests/test_shellx_vi.py:218-227`

**Interfaces:**
- Produces:

```swift
extension AccountSignInMethod {
    public enum Kind: Equatable, Sendable { case google, apple, email }
    /// "apple" is `.apple`, "email" is `.email`, every other provider is `.google`.
    public var kind: Kind { get }
}
```

`methodRow`'s title follows `method.kind`: `settings.account.methods.apple`, `settings.account.methods.email` ("Email code") or `settings.account.methods.google`; the address line and the Apple-only Remove button are unchanged.

- [ ] **Step 1: Write the failing tests.** `ShellXCoreClientEmailTests.swift`:

```swift
@Test func signInMethodKindsFollowTheProvider() throws
// signInMethods() over {"identities":[{"identity_id":"e1","provider":"email","email":"foo@bar.com"},
// {"identity_id":"g1","provider":"google","email":"g@x"},{"identity_id":"a1","provider":"apple"},{"identity_id":"t1","provider":"test"}]}
// -> kinds == [.email, .google, .apple, .google]; the email item is not isApple
```

`tests/test_shellx_vi.py`: add `"settings.account.methods.email": ("Email code", "Mã qua email")` to `test_account_settings_strings_read_naturally`.

- [ ] **Step 2: Run to verify they fail.** Run: `swift test --package-path Packages/Shared/ShellXBrand --filter signInMethodKindsFollowTheProvider; python3 tests/test_shellx_vi.py VietnameseCatalogTests.test_account_settings_strings_read_naturally`. Expected: compile error (`kind` missing); Python FAIL.
- [ ] **Step 3: Commit the failing tests.** `git add Packages/Shared/ShellXBrand/Tests tests/test_shellx_vi.py && git commit -m "test(shellx): the email sign-in method has its own label"`
- [ ] **Step 4: Implement** `kind` and the row title; localize as in Task 4 Step 5 (one key).
- [ ] **Step 5: Run to verify they pass.** Run: `swift test --package-path Packages/Shared/ShellXBrand && python3 tests/test_shellx_vi.py && python3 scripts/localization_catalog.py check && scripts/shellx/test-app.sh ShellXSignInSheetTests`. Expected: passed, `OK`, no catalog errors, `** TEST SUCCEEDED **` (the app compiles with the changed view).
- [ ] **Step 6: Commit.** `git add Packages/Shared/ShellXBrand Sources/ShellX/ShellXAccountDetailView.swift Resources/Localizable.xcstrings scripts/localization-allowed-omissions.json && git commit -m "feat(shellx): Settings names the email code sign-in method"`

---

### Task 8: Verify and hand off

**Files:** none new.

- [ ] **Step 1: Run the full verification** from the worktree root:

```bash
(cd shellx-core && cargo test --workspace --locked)
git diff --quiet develop...HEAD -- shellx-core/Cargo.lock windows/Cargo.lock && echo locks-unchanged
swift test --package-path Packages/Shared/ShellXBrand
python3 tests/test_shellx_remote_harness.py
python3 tests/test_shellx_vi.py
python3 tests/test_shellx_no_phone_home.py
python3 scripts/localization_catalog.py check
./scripts/localize-changes --base develop
./scripts/wire-app-sources.py --check
./scripts/sync-test-wiring --check
scripts/shellx/test-app.sh ShellXSignInSheetTests ShellXAboutTests ShellXPhonePairingCoordinatorTests
python3 scripts/verify-local.py --affected develop --swift-changed develop
```
Expected: every Rust, Swift and Python suite passes; `locks-unchanged`; `Localization ready: changed work is complete and the strict catalog validator passed.`; both wiring checks exit 0; `** TEST SUCCEEDED **`; `verify-local.py` clean but for the known `feature-flags` noise.
- [ ] **Step 2: Secret and address scan.** Run `git diff develop...HEAD | grep -nE '^\+.*(re_[A-Za-z0-9]{8,}|RESEND_API_KEY=|@gmail\.com)'`. Expected: no match (no Resend key and no real address; test addresses use `bar.com`, `b.cd`, `shellx.test`, `shellx.dev`, `mailinator.com`).
- [ ] **Step 3: Localization audit for the hand-off** (skills/cmux-localization "Audit checklist"): the changed surfaces (sign-in sheet's first screen, email step, code step, error line; Settings › Account method row), the 17 new keys and the reused `remote.signin.email`, the commands above, that the eight non-en/vi locales were machine-translated by the executor, and `rg` over the changed Swift for bare English.
- [ ] **Step 4: Report and stop.** Do not merge, push to `main`, deploy or release. Hand-off notes: the commit list; red and green command results per task; every check not run on this machine and why (Task 0 Step 4); that no live relay, real email or tagged dev build was used (the feature needs the relay part and its Resend settings, plan 1D); wording swaps under Ruling 19; and the Contract additions below for the contracts owner.

---

## Contract additions

For the contracts owner (`docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md`, a new email section):

- §3 gains the two rows and the error table of "Interfaces for Plan B"; `auth.session`'s `auth_method` may now be `"email"`; `session.json.auth_method` may be `"email"`.
- Test-only names: fake routes `POST /v1/auth/email/code`, `POST /v1/auth/email/verify`; `FakeOptions.email_sign_in`; `FakeApi::email_code`, `expire_email_codes`, `fail_next`; the fake's disposable domain is `mailinator.com`.
- Mac keys: the String table. Mac type names: `EmailCodeChallenge`, `EmailSignInModel`, `AccountSignInMethod.Kind`, `ShellXAccount.requestEmailCode` / `signInWithEmailCode`.
- Not changed, for whoever mirrors the relay next: the fake's `DELETE /v1/account/identities/<id>` rule still protects only the last Google identity, and its `DELETE /v1/account` still takes a Google id_token only (no desktop code calls either with an email identity).

## Not verified while writing this plan

- No command in this plan was run: the plan was written from the source. In particular the Mac app test target has never been built on this machine (Task 0 Step 4), so `scripts/shellx/test-app.sh` steps are expected to work as they did for plan 1B on the other machine, not observed here.
- `xcodebuild`'s `-testLanguage` (Task 6 Step 7) is expected to switch the hosted app's language for the PNGs; not tried here.
- `NSHostingView(...).fittingSize.width == 340` for the sheet follows `cmuxTests/NewMachineSheetLayoutTests.swift:128`; if the hosted width differs by a rounding point, compare with a tolerance of 1.
- The real relay's answers for a malformed `locale` and its check order are not in the spec; the fake's order (Task 1) is this plan's choice and the core always sends `"en"` or `"vi"`.

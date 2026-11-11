# ShellX Email Code Sign-in, Desktop Plan B (Windows) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Execution (decided):** one implementer runs Tasks 0–4 in order on one branch, commits per task with the failing test first, and stops after Task 4; one whole-branch review follows. This plan starts only after Plan A (`docs/superpowers/plans/2026-11-11-shellx-email-code-signin-core-mac.md`) is merged into `develop`.

**Goal:** The Windows app signs in with an email address and a 6-digit code next to "Continue with Google", through Plan A's `auth.email.begin` and `auth.email.finish`.

**Architecture:** The pure `shellx-model` crate gains the two typed core calls, the strings, and the email steps inside the event-driven `AccountFlow` (time is passed in, so the resend lock is testable); it runs under `cargo test` on a Mac. `shellx-app` maps the two new actions to core calls and draws the steps in the existing sign-in dialog with the text field the password dialog used. On a Mac the release build of the window is checked with screenshots through a Mac-only preview switch.

**Tech Stack:** Rust 1.91 edition 2024, GPUI `=0.2.2`, `shellx-core` (path dependency), `shellx-fake-api` (dev-dependency).

**Spec:** `docs/superpowers/specs/2026-11-10-shellx-email-code-sign-in-design.md` (Vietnamese): §3, §4, §7 ("Chung", the strings paragraph, **Desktop chung**, **Windows**), the desktop lines of §8–§10; §11 is answered with every default. Read Plan A's "Interfaces for Plan B", "String table" and "Rulings" first; for conventions, Tasks 13–15 of `docs/superpowers/plans/2026-11-07-shellx-signin-1b-desktop.md`; `windows/README.md` ("Run the window on a Mac").

## Global Constraints

- The core contract this plan consumes (owned by Plan A; if `shellx-core` on `develop` differs, the code wins and the difference goes in the hand-off):

  ```
  auth.email.begin  {email, locale?} -> {challenge_id, expires_in, resend_in, email}      email = the relay's normalized address
  auth.email.finish {challenge_id, code} -> {user_id, device_id, device_public_key_b64, fingerprint, email, auth_method: "email"}
  ```

  Error codes the app words: `invalid_email`, `disposable_email`, `rate_limited`, `email_send_failed`, `email_sign_in_disabled` (also every 404: a relay without the feature), `invalid_code`, `code_expired`, `switch_from_signed_in_device`, `network`; anything else is shown as today's "Sign-in failed: <code>". The core accepts any `locale` (a value starting with `vi` is Vietnamese, anything else English) and strips whitespace from `code`.
- Code: 6 digits, lives 600 s, 5 guesses; "Resend code" is locked for the `resend_in` the core returns (60 s).
- "Continue with email" is always shown; no discovery call.
- Every shared string equals the Mac's `en` / `vi` value in `Resources/Localizable.xcstrings` on `develop` (the catalog wins over this plan's table), pinned by `sign_in_strings_match_the_mac`.
- Tests fake the relay (`shellx-fake-api`) and the core (`FakeCore`). Nothing here needs a running relay, a real mailbox or a key.
- Never log or `Debug`-print the code, the `challenge_id` or an email address (the manual `Debug` impls of `AccountEvent` / `AccountAction` and `core_api` values).
- No new crates: `windows/Cargo.lock` stays unchanged.
- No account deletion by code: Settings keeps the `DELETE_ACCOUNT_URL` link.
- On a Mac never build or run a debug `shellx-app` (it crashes, `windows/README.md:54-57`): `cargo test --release -p shellx-app`, `cargo build --release -p shellx-app`. `cargo test -p shellx-model` is fine.
- Never release, deploy, build an installer, push or merge to `main`, sign, or touch the VPS. Never quit, launch or replace `/Applications/ShellX.app` or any cmux app (the screenshots start only `windows/target/release/shellx-desktop`). The implementer does not merge.
- Branch `feat/shellx-email-code-signin-windows` from `develop`, worktree `.worktrees/email-code-signin-windows`. Commit style: `test(shellx-windows): …` then `feat(shellx-windows): …`.

## Review Focus

1. **A code pasted with spaces or a line break, or pasted with the sentence around it.** Its six digits are used. Tests: Task 1 `code_digits_takes_the_six_digits_of_what_was_typed`; Task 2 `email_sign_in_runs_email_code_verify_then_lists`.
2. **Double submit: six digits submit by themselves while Enter or Verify is pressed.** One `CallEmailFinish`. Tests: Task 1 `auto_submit_fires_once_per_new_six_digits`; Task 2 `verify_runs_once_for_a_double_submit`.
3. **An expired code, or the fifth wrong guess.** The dialog stays on the code screen, Verify is off, "Resend code" unlocks at once. Test: Task 2 `an_expired_code_drops_the_challenge_and_unlocks_resend`.
4. **Closing the dialog mid-flow and opening it again.** A late answer never brings an old screen back; the reopened dialog starts clean; a code that verified after the close still signs this PC in. Tests: Task 2 `closing_while_sending_ignores_the_late_challenge`, `closing_while_verifying_still_signs_in_when_the_code_was_right`, `reopening_after_a_close_starts_clean`.
5. **A relay without the feature.** One sentence on the email screen; the account stays signed out, not in an error state. Tests: Task 2 `a_relay_without_email_sign_in_keeps_the_app_signed_out`, `a_relay_without_email_sign_in_answers_through_the_real_core`.
6. **Offline, and a list answer that arrives late.** The network sentence on the same screen; a late `not_logged_in` list never throws the person off the code screen. Tests: Task 1 `email_error_maps_codes`; Task 2 `a_late_list_result_does_not_reset_the_email_step`.
7. **Asking again too soon (429).** A sentence and an unlocked Resend, the old code still usable. Test: Task 2 `a_failed_resend_keeps_the_code_step_and_the_old_challenge`.

## Rulings

1. `AccountState` is unchanged. The spec says "`AccountState/Event/Action` thêm các bước", but `AccountState` is what Settings and the sidebar read and `AccountState::Error` is printed by Settings (`ui/settings.rs:136-139`); a half-typed code is not an account state. The steps are an `EmailStep` beside it, with new `AccountEvent` / `AccountAction` variants.
2. Email failures live in the email run (`email_error()`), never in `AccountState::Error`: a wrong code returns the account to `LoggedOut`.
3. Windows has no visible "done" step: after a right code the flow lists and registers exactly as after Google and the dialog closes at `LoggedIn` (plan 1B's ruling for Google); meanwhile it shows "Signing in…".
4. Closing the dialog cannot cancel a verify already sent (no cancel API): the run is hidden and its answer still applies.
5. `reset_session()` leaves the email run alone; entering `LoggedIn` drops it.
6. `email_finish` returns the existing `GoogleSignIn` value (same shape); no rename.
7. A new `email_error()` words the email codes; `google_error()` and its tests are untouched, so Google's 429 still reads "Sign-in failed: rate_limited" here (the Mac's shared mapper gives it the sentence).
8. The code field shows what was typed or pasted; Verify and the auto-submit use `code_digits` of it and need exactly six digits (the Mac's field rewrites itself to its first six digits; `TextField` is not rewritten here, so an IME composition is never disturbed).
9. The resend lock reads "Resend code in 42 s" and the sent-to line carries the spam hint as its second sentence: the Mac's and the phones' text.
10. The email's language is `Lang::locale()` (`"vi"` or `"en"`).
11. Settings › Account titles an `email` identity "Email code" with the address under it; Remove stays for Apple IDs only.
12. A Mac-only preview switch `SHELLX_DEV_SIGN_IN=start|email|code` is added (compiled under `cfg(target_os = "macos")`, never in the Windows product): release builds always talk to `https://relay.shellx.pro` and `dev/mac-shot.sh` cannot click or type, so without it no screenshot could show the new screens.
13. The spec says only debug tests of `shellx-app` cannot run on a Mac; this plan runs its release tests there (`windows/README.md:54-57`) and lists what is left for Windows below.

## Left for the Windows build (cannot run on a Mac)

Say these plainly in the hand-off; none is checked by this plan:

- Typing and pasting in the two fields on real Windows (WM_CHAR after a key-down the root passes, `Ctrl+V`, an IME such as Telex or VNI in the email field): the text field has had no user since plan 1B removed the password dialog.
- The dialog's layout under DirectWrite fonts and at 125 % / 150 % display scaling.
- `cargo test --release --locked -p shellx-app --bin shellx-desktop --target <windows target>` and the `--smoke` run of `.github/workflows/shellx-windows.yml` (job `app`), and the cross build on the VPS.
- A live sign-in: it needs the relay part of this feature deployed with its Resend settings (plan 1D).

## String table

`Str` variants and helpers in `windows/shellx-model/src/strings.rs`; each value equals the Mac key's.

| Win | Mac key | en | vi |
| --- | --- | --- | --- |
| `ContinueWithEmail` | `remote.signin.email.continue` | Continue with email | Tiếp tục với email |
| `OrDivider` | `remote.signin.email.or` | or | hoặc |
| `EmailAddress` (exists) | `remote.signin.email` | Email | Địa chỉ email |
| `SendCode` | `remote.signin.email.send` | Send code | Gửi mã |
| `sent_code_to()` | `remote.signin.email.sentTo` | We sent a code to {email}. Can't find it? Check your spam folder. | Đã gửi mã tới {email}. Không thấy thư? Hãy kiểm tra thư rác. |
| `CodePlaceholder` | `remote.signin.email.code` | 6-digit code | Mã 6 chữ số |
| `VerifyCode` | `remote.signin.email.verify` | Verify | Xác minh |
| `ResendCode` | `remote.signin.email.resend` | Resend code | Gửi lại mã |
| `resend_code_in()` | `remote.signin.email.resendIn` | Resend code in {secs} s | Gửi lại mã sau {secs} giây |
| `UseDifferentEmail` | `remote.signin.email.change` | Use a different email | Dùng email khác |
| `InvalidEmail` | `remote.signin.error.invalidEmail` | Enter a valid email address. | Hãy nhập một địa chỉ email hợp lệ. |
| `DisposableEmail` | `remote.signin.error.disposableEmail` | Temporary email addresses can't be used. Try another address. | Không dùng được địa chỉ email tạm thời. Hãy thử địa chỉ khác. |
| `InvalidCode` | `remote.signin.error.invalidCode` | That code isn't right. Check it and try again. | Mã chưa đúng. Hãy kiểm tra và thử lại. |
| `CodeExpired` | `remote.signin.error.codeExpired` | That code has expired. Request a new one. | Mã đã hết hạn. Hãy yêu cầu mã mới. |
| `EmailSendFailed` | `remote.signin.error.emailSendFailed` | We couldn't send the email. Try again. | Không gửi được email. Hãy thử lại. |
| `SignInUnavailable` | `remote.signin.error.unavailable` | This way of signing in isn't available in this build. | Bản này chưa dùng được cách đăng nhập này. |
| `RateLimited` | `remote.signin.error.rateLimited` | Try again in a few minutes. | Thử lại sau ít phút. |
| `EmailCodeMethod` | `settings.account.methods.email` | Email code | Mã qua email |

## File structure

| File | Responsibility |
| --- | --- |
| `windows/shellx-model/src/email_sign_in.rs` (create) | `EmailStep`, address and code checks, the auto-submit rule, which screen the dialog draws |
| `windows/shellx-model/src/core_api.rs` (modify) | `EmailChallenge`, `email_begin`, `email_finish`, `SignInMethod::is_email` |
| `windows/shellx-model/src/strings.rs` (modify) | 15 `Str` variants, `Lang::locale`, `sent_code_to`, `resend_code_in`, `email_error`, `sign_in_method_label` |
| `windows/shellx-model/src/account.rs` (modify) | The email run inside `AccountFlow`: events, actions, accessors |
| `windows/shellx-app/src/core_service.rs` (modify) | The two actions' core calls |
| `windows/shellx-app/src/ui/account.rs` (modify) | Window-side methods over the flow; the Mac-only preview |
| `windows/shellx-app/src/ui/login.rs` (modify) | The dialog: provider screen, email screen, code screen |
| `windows/shellx-app/src/ui/settings.rs`, `ui/root.rs`, `ui/mod.rs`, `windows/README.md` (modify) | Method label; preview switch; `text_field` is used again; the docs |

---

### Task 0: Worktree, tools, baseline

**Files:** none (environment only).

- [ ] **Step 1: Check Plan A landed.** In the main checkout: `git -C /Users/richard/Documents/helper/shellx grep -n '"auth.email.finish"' develop -- shellx-core/src/lib.rs`. Expected: one match in `KNOWN_METHODS`. No match: stop and report; this plan cannot start.
- [ ] **Step 2: Create the worktree.** Use superpowers:using-git-worktrees to create `.worktrees/email-code-signin-windows` on a new branch `feat/shellx-email-code-signin-windows` from `develop`. Every later path is relative to it. The plans are untracked in the main checkout: read them from `/Users/richard/Documents/helper/shellx/docs/superpowers/plans/` and do not add them on this branch.
- [ ] **Step 3: Tools.** `export PATH="$HOME/.cargo/bin:$PATH"` (cargo is not on the default `PATH` here). `shellx-app` needs the `ghostty` submodule and Zig, and this machine has neither: run `git submodule update --init ghostty`, then `bash scripts/ghostty-zig-version.sh` prints the Zig version to install (CONTRIBUTING.md lists Zig as a requirement; `brew install zig` when Homebrew's version matches). If Zig cannot be installed, keep the output and do not work around it: Task 1 and the `shellx-model` half of Task 2 are done and tested fully; write the `shellx-app` code of Tasks 2–3 and report every `shellx-app` command as "not run on this machine".
- [ ] **Step 4: Baseline.** Run each and record any failure before changing code (fix nothing unrelated; the first release build takes about five minutes):

```bash
(cd windows && cargo test --locked -p shellx-model)
(cd windows && cargo test --release --locked -p shellx-app)
(cd windows && cargo build --release --locked -p shellx-app)
(cd windows && SHELLX_LANG=en dev/mac-shot.sh "$TMPDIR/shellx-baseline.png" 8)
```
Expected: `test result: ok` twice, a finished build, `mac-shot: wrote …` and a PNG that shows the ShellX window. A PNG without the window's content means the terminal has no Screen Recording permission: do not change system settings; report the screenshots of Task 3 as not taken.
- [ ] **Step 5: Print the landed Mac strings** (they are the expected values of Task 1's tests; where one differs from this plan's String table, use the printed value and note it):

```bash
python3 -c "
import json
s = json.load(open('Resources/Localizable.xcstrings'))['strings']
keys = [k for k in s if k.startswith(('remote.signin.email', 'remote.signin.error.')) or k == 'settings.account.methods.email']
for k in sorted(keys):
    l = s[k]['localizations']
    print(k, '|', l['en']['stringUnit']['value'], '|', l['vi']['stringUnit']['value'])"
```

---

### Task 1: Model: the two core calls, the strings and the small rules

**Files:**
- Create: `windows/shellx-model/src/email_sign_in.rs`; modify `windows/shellx-model/src/lib.rs:3-19` (`pub mod email_sign_in;`)
- Modify: `windows/shellx-model/src/core_api.rs` (types after `SignInMethod` :200-219, wrappers after `remove_sign_in_method` :251-257, tests :628-719)
- Modify: `windows/shellx-model/src/strings.rs` (`Lang` :10-31, `Str` :33-159, `ALL` :161-273, `t` :276-517, helpers after `google_error` :540-554, tests :660-665 and :741-878)

**Interfaces:**
- Consumes: Plan A's RPC contract; the String table.
- Produces:

```rust
// core_api.rs
/// `auth.email.begin`. `Debug` shows `expires_in` and `resend_in` only.
#[derive(Clone, PartialEq, Eq, Deserialize)]
pub struct EmailChallenge { pub challenge_id: String, pub email: String, pub expires_in: u64, pub resend_in: u64 }
pub fn email_begin(core: &dyn CoreCall, email: &str, locale: &str) -> Result<EmailChallenge, CoreErr>;   // {"email", "locale"}
/// `auth.email.finish`: the value of `auth.google.finish` with `auth_method: "email"`.
pub fn email_finish(core: &dyn CoreCall, challenge_id: &str, code: &str) -> Result<GoogleSignIn, CoreErr>;   // {"challenge_id", "code"}
impl SignInMethod { pub fn is_email(&self) -> bool }   // provider == "email"
// strings.rs
impl Lang { pub fn locale(self) -> &'static str }   // Vi -> "vi", En -> "en"
// 15 new Str variants (the Win column) in Str, ALL and both arms of t()
pub fn sent_code_to(lang: Lang, email: &str) -> String;
pub fn resend_code_in(lang: Lang, secs: u64) -> String;   // whole seconds
/// The dialog's line for an email-code failure: the seven email sentences, `network` -> RelayUnreachable,
/// `switch_from_signed_in_device` -> SwitchFromSignedInDevice, anything else `login_failed(lang, code)`.
pub fn email_error(lang: Lang, code: &str) -> String;
/// Settings row title: "apple" -> AppleId, "email" -> EmailCodeMethod, anything else -> GoogleAccount.
pub fn sign_in_method_label(provider: &str) -> Str;
// email_sign_in.rs
pub const CODE_LEN: usize = 6;
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EmailStep { Email, Sending, Code, Verifying }
/// Text before and after an '@', then a '.' with text on both sides, no whitespace inside (after trimming).
pub fn email_looks_valid(text: &str) -> bool;
/// The ASCII digits of `raw` when there are exactly six; every other character is skipped.
pub fn code_digits(raw: &str) -> Option<String>;
/// The digits to submit without a click: `code_digits(text)` when a challenge can be verified and they differ from `last`.
pub fn auto_submit(last: Option<&str>, text: &str, can_verify: bool) -> Option<String>;
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SignInScreen { Providers, GoogleWaiting, SigningIn, EmailEntry { busy: bool }, CodeEntry { busy: bool } }
/// What the "Sign in to ShellX" dialog draws. `has_sent_to`: a code was already sent in this run;
/// `started_email`: this dialog started an email step since it opened; `logging_in`: `AccountState::LoggingIn`.
pub fn sign_in_screen(step: Option<EmailStep>, has_sent_to: bool, google_waiting: bool, started_email: bool, logging_in: bool) -> SignInScreen;
```

`sign_in_screen`: `Email` → `EmailEntry { busy: false }`; `Sending` → `CodeEntry { busy: true }` with `has_sent_to`, else `EmailEntry { busy: true }`; `Code` → `CodeEntry { busy: false }`; `Verifying` → `CodeEntry { busy: true }`; no step → `GoogleWaiting` when `google_waiting`, else `SigningIn` when `started_email && logging_in`, else `Providers`.

- [ ] **Step 1: Write the failing tests.** `core_api.rs`:

```rust
#[test] fn email_calls_send_their_params_and_parse() {
    // email_begin(&f, "Foo@Bar.com", "vi") sends ("auth.email.begin", {"email":"Foo@Bar.com","locale":"vi"}) and parses
    // {"challenge_id":"c1","expires_in":600,"resend_in":60,"email":"foo@bar.com"};
    // email_finish(&f, "c1", "123456") sends ("auth.email.finish", {"challenge_id":"c1","code":"123456"}) and parses
    // email "foo@bar.com", auth_method "email"; a provider "email" item of list_sign_in_methods is_email() and not is_apple()
}
#[test] fn email_values_hide_addresses_and_challenges_in_debug() {
    // format!("{:?}", EmailChallenge { challenge_id: "CH-SECRET", email: "foo@bar.com", .. }) contains neither
}
```

`strings.rs`: extend `sign_in_strings_match_the_mac`'s `pairs` with the 15 new variants (the table's vi and en; `assert_eq!(pairs.len(), 35)`; `EmailAddress` is already asserted there), and add to it

```rust
assert_eq!(sent_code_to(Lang::En, "foo@bar.com"), "We sent a code to foo@bar.com. Can't find it? Check your spam folder.");
assert_eq!(sent_code_to(Lang::Vi, "foo@bar.com"), "Đã gửi mã tới foo@bar.com. Không thấy thư? Hãy kiểm tra thư rác.");
assert_eq!(resend_code_in(Lang::En, 42), "Resend code in 42 s");
assert_eq!(resend_code_in(Lang::Vi, 60), "Gửi lại mã sau 60 giây");
assert_eq!((Lang::Vi.locale(), Lang::En.locale()), ("vi", "en"));
```

change `all_has_no_duplicates` to `assert_eq!(Str::ALL.len(), 124)`, and add

```rust
#[test] fn email_error_maps_codes() {
    // for both languages: invalid_email -> InvalidEmail, disposable_email -> DisposableEmail, invalid_code -> InvalidCode,
    // code_expired -> CodeExpired, email_send_failed -> EmailSendFailed, email_sign_in_disabled -> SignInUnavailable,
    // rate_limited -> RateLimited, network -> RelayUnreachable, switch_from_signed_in_device -> SwitchFromSignedInDevice,
    // "invalid_device" -> login_failed(lang, "invalid_device")
}
#[test] fn sign_in_method_labels_follow_the_provider() {
    // "apple" -> AppleId, "email" -> EmailCodeMethod, "google" and "test" -> GoogleAccount
}
```

`email_sign_in.rs` (a `#[cfg(test)] mod tests` written before the functions exist):

```rust
#[test] fn plausible_addresses() { /* true: "a@b.c", " a@b.co "; false: "", "a@b", "a@.c", "a@b.", "@b.c", "a b@c.d" */ }
#[test] fn code_digits_takes_the_six_digits_of_what_was_typed() {
    // " 123 456\n" and "Your ShellX sign-in code is 123456" -> Some("123456");
    // "12345", "1234567", "12a45", "", "１２３４５６" -> None
}
#[test] fn auto_submit_fires_once_per_new_six_digits() {
    // auto_submit(None, "123 456", true) == Some("123456"); auto_submit(Some("123456"), "123456", true) == None;
    // auto_submit(Some("123456"), "654321", true) == Some("654321"); auto_submit(None, "123456", false) == None;
    // auto_submit(None, "12345", true) == None
}
#[test] fn the_dialog_screen_follows_the_steps() {
    // (None, false, false, false, false) -> Providers; (None, _, true, _, _) -> GoogleWaiting;
    // (None, false, false, true, true) -> SigningIn; (None, false, false, false, true) -> Providers;
    // (Some(Email), ..) -> EmailEntry { busy: false }; (Some(Sending), false, ..) -> EmailEntry { busy: true };
    // (Some(Sending), true, ..) -> CodeEntry { busy: true }; (Some(Code), true, ..) -> CodeEntry { busy: false };
    // (Some(Verifying), true, ..) -> CodeEntry { busy: true }
}
```

- [ ] **Step 2: Run to verify they fail.** Run: `(cd windows && cargo test --locked -p shellx-model)`. Expected: compile errors (`email_begin`, `Str::ContinueWithEmail`, `code_digits` missing).
- [ ] **Step 3: Commit the failing tests** (the `mod tests` edits and the test-only `email_sign_in.rs` with its `lib.rs` line). `git add windows/shellx-model/src && git commit -m "test(shellx-windows): email code core calls, strings and input rules"`
- [ ] **Step 4: Implement** the Interfaces.
- [ ] **Step 5: Run to verify they pass.** Run: `(cd windows && cargo test --locked -p shellx-model)`. Expected: `test result: ok`, no new compiler warning.
- [ ] **Step 6: Commit.** `git add windows/shellx-model/src && git commit -m "feat(shellx-windows): email code core calls, strings and input rules"`

---

### Task 2: The email steps in the account flow, run through the core

The flow and its two core calls land in one task: `run_account_action` matches every `AccountAction` with no wildcard (`core_service.rs:145-193`), so new actions without their arms would leave `shellx-app` unbuildable between commits.

**Files:**
- Modify: `windows/shellx-model/src/account.rs` (`AccountEvent` :36-81, `AccountAction` :83-105, both `Debug` impls :107-191, `AccountFlow` :201-265, accessors after :331, `reset_session` :369-383, entering `LoggedIn` :413-434, `GoogleRequested` :574-593, tests :722+)
- Modify: `windows/shellx-app/src/core_service.rs` (imports :19-24, `run_account_action` :140-194, tests after :535)

**Interfaces:**
- Consumes: Task 1 (`EmailStep`, `EmailChallenge`, `GoogleSignIn`, `email_looks_valid`, `code_digits`, `email_begin`, `email_finish`); `shellx_fake_api::{FakeApi, FakeOptions}` with `email_code` and `email_sign_in` (Plan A).
- Produces:

```rust
// AccountEvent gains
EmailRequested,                                           // "Continue with email"
EmailCodeRequested { email: String, locale: String },     // "Send code": the typed address, "vi" | "en"
EmailResendRequested,                                     // "Resend code": the same address and language
EmailBegun(Result<EmailChallenge, CoreErr>),              // result of CallEmailBegin
EmailCodeSubmitted(String),                               // Verify, Enter or six digits typed: the code field's text
EmailFinished { challenge_id: String, result: Result<GoogleSignIn, CoreErr> },   // result of CallEmailFinish
EmailChangeRequested,                                     // "Use a different email"
EmailCancelled,                                           // the dialog closed
// AccountAction gains
CallEmailBegin { email: String, locale: String },
CallEmailFinish { challenge_id: String, code: String },
// AccountFlow
pub fn email_step(&self) -> Option<EmailStep>;            // None with no run, or once the dialog closed a run that is verifying
pub fn email_sent_to(&self) -> Option<&str>;              // the relay's address for the code sent in this run
pub fn email_error(&self) -> Option<&CoreErr>;
pub fn email_can_verify(&self) -> bool;                   // step Code with a live challenge
pub fn email_resend_wait_secs(&self, now_ms: u64) -> u64; // rounded up; 0 = "Resend code" can be pressed
// core_service.rs run_account_action (both on the serial worker):
//   CallEmailBegin { email, locale }      -> Some(EmailBegun(email_begin(core, &email, &locale)))
//   CallEmailFinish { challenge_id, code } -> Some(EmailFinished { challenge_id, result: email_finish(..) })
```

Rules (one test each below):
- `EmailRequested`: only with no email run, no Google flow, `accepts_login()` and not `LoggedIn` → a run at `Email`; no action. `GoogleRequested(_)` is ignored while an email run is open.
- `EmailCodeRequested`: only at `Email` with `email_looks_valid(&email)` → `Sending`, error cleared, `[CallEmailBegin { email: <trimmed>, locale }]`; the run remembers both.
- `EmailResendRequested`: only at `Code` with `email_resend_wait_secs(now_ms) == 0` → `Sending`, error cleared, `[CallEmailBegin { .. }]` with the remembered address and language.
- `EmailBegun`: while a cancelled request's answer is still owed (a counter like `stale_begins`) → count it down and ignore; not at `Sending` → ignore. `Ok(c)` → `Code`, challenge `c.challenge_id`, `sent_to = c.email`, lock until `now_ms + c.resend_in * 1000`. `Err(e)` → `Code` when a code was already sent in this run (the old challenge stays), else `Email`; `error = e`; the lock ends.
- `EmailCodeSubmitted(text)`: only at `Code` with a live challenge, `code_digits(&text)` `Some` and `accepts_login()` → `Verifying`, error cleared, then the same state changes as `GoogleRequested(SignIn)` (`LoggingIn`, `login_in_flight`, `retry_list` off, notice cleared) and `[CallEmailFinish { challenge_id, code: <the digits> }]`.
- `EmailFinished`: ignored unless the run is at `Verifying` with that `challenge_id`. `Ok(info)` → the run is dropped, email and auth method stored, then exactly what `GoogleFinished` does for `SignIn` (`[CallList]`). `Err(e)` → `login_in_flight` off and state `LoggedOut`; a run the dialog closed is dropped; otherwise back to `Code` with `error = e`, and for `code_expired` the challenge is dropped and the lock ends.
- `EmailChangeRequested`: only at `Code` → `Email`; challenge, `sent_to` and error dropped.
- `EmailCancelled`: at `Email` or `Code` → the run is dropped; at `Sending` → dropped, and its answer is owed; at `Verifying` → the run is hidden (`email_step()` is `None`) until `EmailFinished`.
- `reset_session()` does not touch the email run; a `ListResult` that enters `LoggedIn` drops it.
- `Debug` prints `"<redacted>"` for the address, the code and the `challenge_id` in the new events and actions, and the run's `Debug` (inside `AccountFlow`'s) shows its step only.

- [ ] **Step 1: Write the failing tests** (in `account.rs` tests; reuse `m`, `net`, `logged_in`, `logged_out`, `google_done`):

```rust
// challenge(id) = EmailChallenge { challenge_id: id.into(), email: "foo@bar.com".into(), expires_in: 600, resend_in: 60 }
// done() = google_done("foo@bar.com", "email"); finished(id, r) = EmailFinished { challenge_id: id.into(), result: r }
// to_code(f, now): EmailRequested; EmailCodeRequested { email: " Foo@Bar.com ", locale: "vi" }; EmailBegun(Ok(challenge("c1"))), all at `now`
#[test] fn email_sign_in_runs_email_code_verify_then_lists() {
    // logged_out(); EmailRequested -> [], email_step() == Some(Email), state LoggedOut;
    // EmailCodeRequested -> [CallEmailBegin { email: "Foo@Bar.com", locale: "vi" }], Some(Sending);
    // EmailBegun(Ok(challenge("c1"))) -> [], Some(Code), email_sent_to() == Some("foo@bar.com"), email_can_verify();
    // EmailCodeSubmitted(" 123 456\n") -> [CallEmailFinish { challenge_id: "c1", code: "123456" }], Some(Verifying),
    // state LoggingIn, login_in_flight(); finished("c1", Ok(done())) -> [CallList], email_step() None;
    // ListResult(Ok([m("me", true)])) -> LoggedIn, no CallSession; email() == Some("foo@bar.com"),
    // auth_method() == Some("email"), !needs_google_switch()
}
#[test] fn send_code_needs_a_plausible_address_and_runs_once() { /* "nope" -> [], still Email; a valid one -> one CallEmailBegin; again while Sending -> [] */ }
#[test] fn a_refused_address_returns_to_the_email_step_with_the_error() { /* EmailBegun(Err(invalid_email)) -> Some(Email), email_error() code "invalid_email"; the next request clears it */ }
#[test] fn a_relay_without_email_sign_in_keeps_the_app_signed_out() { /* EmailBegun(Err(email_sign_in_disabled)) -> Some(Email), that error, state LoggedOut, notice() None */ }
#[test] fn a_wrong_code_stays_on_the_code_step() { /* finished("c1", Err(invalid_code)) -> Some(Code), email_error() invalid_code, email_can_verify(), state LoggedOut, !login_in_flight(); a new submit -> CallEmailFinish again */ }
#[test] fn an_expired_code_drops_the_challenge_and_unlocks_resend() { /* Err(code_expired) at 5_000 -> Some(Code), !email_can_verify(), email_resend_wait_secs(5_000) == 0; EmailCodeSubmitted("123456") -> []; EmailResendRequested -> [CallEmailBegin { email: "Foo@Bar.com", locale: "vi" }] */ }
#[test] fn verify_runs_once_for_a_double_submit() { /* two EmailCodeSubmitted("123456"): the second is []; at Code, "12345" and "1234567" -> [] */ }
#[test] fn resend_is_locked_for_the_relays_resend_in() { /* to_code at 1_000: wait(1_000) == 60, wait(1_500) == 60, wait(60_200) == 1, wait(61_000) == 0; EmailResendRequested at 30_000 -> []; at 61_000 -> [CallEmailBegin], Some(Sending), email_sent_to() still Some; EmailBegun(Ok(challenge("c2"))) at 62_000 -> wait(62_000) == 60, and a submit sends challenge "c2" */ }
#[test] fn a_failed_resend_keeps_the_code_step_and_the_old_challenge() { /* resend at 61_000; EmailBegun(Err(rate_limited)) -> Some(Code), email_error() rate_limited, wait == 0; a submit sends challenge "c1" */ }
#[test] fn use_a_different_email_returns_to_the_email_step() { /* EmailChangeRequested -> Some(Email), email_sent_to() None, email_error() None; at Verifying it changes nothing */ }
#[test] fn closing_while_sending_ignores_the_late_challenge() { /* EmailCancelled at Sending -> email_step() None; EmailBegun(Ok(challenge("c1"))) -> [], still None; a new run's EmailBegun(Ok(challenge("c2"))) reaches Code and submits "c2" */ }
#[test] fn closing_while_verifying_still_signs_in_when_the_code_was_right() { /* EmailCancelled at Verifying -> email_step() None, state LoggingIn; EmailRequested -> []; finished("c1", Ok(done())) -> [CallList], email() Some */ }
#[test] fn closing_while_verifying_a_wrong_code_ends_signed_out_without_an_error() { /* ... finished("c1", Err(invalid_code)) -> state LoggedOut, email_step() None, email_error() None; EmailRequested -> Some(Email) */ }
#[test] fn reopening_after_a_close_starts_clean() { /* to_code; EmailCancelled; EmailRequested -> Some(Email), email_sent_to() None, email_error() None, !email_can_verify() */ }
#[test] fn a_late_list_result_does_not_reset_the_email_step() { /* new flow: Started (state Unknown); to_code; ListResult(Err(not_logged_in)) -> state LoggedOut, email_step() == Some(Code), email_can_verify() */ }
#[test] fn email_and_google_do_not_run_together() { /* at Email: GoogleRequested(SignIn) -> []; with a Google flow waiting: EmailRequested -> []; logged_in(): EmailRequested -> [] */ }
#[test] fn a_stale_email_finish_is_ignored() { /* at Verifying "c1": finished("c0", Ok(done())) -> [], still Verifying; at Code: finished("c1", Ok(done())) -> [] */ }
#[test] fn email_codes_addresses_and_challenges_never_in_debug() { /* with challenge id "CH-SECRET": Debug of EmailCodeRequested, EmailCodeSubmitted("123456"), EmailFinished Ok, CallEmailBegin, CallEmailFinish and of the flow on the code step contains none of "foo@bar.com", "Foo@Bar.com", "123456", "CH-SECRET" */ }
```

`core_service.rs` tests (`drive`, `cfg`, `facts` exist):

```rust
/// Email sign-in through the real shellx-core against the fake API (the fake's mailbox stands for the email).
#[test] fn email_session_against_fake_api() {
    // FakeApi::start(default); ConfiguredCore over CoreBridge; drive Started -> LoggedOut; drive EmailRequested -> ran == [];
    // drive EmailCodeRequested { email: "Foo@Bar.com", locale: "vi" } ->
    //   ran == ["CallEmailBegin { email: \"<redacted>\", locale: \"vi\" }"], email_step() == Some(Code), email_sent_to() == Some("foo@bar.com");
    // right = api.email_code("foo@bar.com").unwrap(); wrong = "000000", or "111111" when right is "000000";
    // drive EmailCodeSubmitted(wrong) -> one entry starting "CallEmailFinish {" that contains neither code; state LoggedOut;
    //   email_error() code "invalid_code"; email_step() == Some(Code);
    // drive EmailCodeSubmitted(right) -> ran[1..] == ["CallList", "CallRegister", "CallList"]; LoggedIn;
    //   email() == Some("foo@bar.com"); auth_method() == Some("email"); !needs_google_switch(); email_step() None;
    // drive SignInMethodsRequested -> sign_in_methods() has one item with provider "email"
}
#[test] fn a_relay_without_email_sign_in_answers_through_the_real_core() {
    // FakeOptions { email_sign_in: false, ..Default::default() }: EmailRequested, EmailCodeRequested ->
    // email_error() code "email_sign_in_disabled", email_step() == Some(Email), state LoggedOut
}
```

- [ ] **Step 2: Run to verify they fail.** Run: `(cd windows && cargo test --locked -p shellx-model account::)`. Expected: compile errors (`EmailRequested` missing). The `shellx-app` tests cannot compile either until Step 4.
- [ ] **Step 3: Commit the failing tests.** `git add windows/shellx-model/src/account.rs windows/shellx-app/src/core_service.rs && git commit -m "test(shellx-windows): account flow email code steps, through the real core"`
- [ ] **Step 4: Implement** the rules and the two `run_account_action` arms.
- [ ] **Step 5: Run to verify they pass.** Run: `(cd windows && cargo test --locked -p shellx-model && cargo test --release --locked -p shellx-app)`. Expected: `test result: ok` for both, including every existing `account::tests`, `account_session_against_fake_api`, `google_session_against_fake_api`, `smoke_account_flow` and the two new `shellx-app` tests; no new compiler warning.
- [ ] **Step 6: Commit.** `git add windows/shellx-model/src/account.rs windows/shellx-app/src/core_service.rs && git commit -m "feat(shellx-windows): account flow signs in with an email code"`

---

### Task 3: App: the dialog's email and code screens, Settings label, screenshots

**Files:**
- Modify: `windows/shellx-app/src/ui/account.rs` (after `cancel_google` :161-164)
- Modify: `windows/shellx-app/src/ui/login.rs` (the whole dialog)
- Modify: `windows/shellx-app/src/ui/mod.rs:17-19` (`text_field` is used again: drop its comment and `#[allow(dead_code)]`; put the attribute back only if the build then warns)
- Modify: `windows/shellx-app/src/ui/settings.rs:238-242` (the row title)
- Modify: `windows/shellx-app/src/ui/root.rs` (end of `RootView::new` :214-215)
- Modify: `windows/README.md` ("Run the window on a Mac", "Remote view (Macs)")

**Interfaces:**
- Consumes: Task 1 (`sign_in_screen`, `SignInScreen`, `auto_submit`, `code_digits`, `email_looks_valid`, `email_error`, `sent_code_to`, `resend_code_in`, `sign_in_method_label`, `Lang::locale`), Task 2 (the flow's events and accessors), `TextField` / `TextFieldEvent` (`ui/text_field.rs`), `button`, `google_button`.
- Produces:

```rust
// ui/account.rs AccountService: one method per flow event, one per accessor
pub fn email_start(&mut self, cx: &mut Context<Self>);                                           // EmailRequested
pub fn email_send_code(&mut self, email: String, locale: &'static str, cx: &mut Context<Self>);  // EmailCodeRequested
pub fn email_resend(&mut self, cx: &mut Context<Self>);                                          // EmailResendRequested
pub fn email_submit_code(&mut self, code: String, cx: &mut Context<Self>);                       // EmailCodeSubmitted
pub fn email_change(&mut self, cx: &mut Context<Self>);                                          // EmailChangeRequested
pub fn email_cancel(&mut self, cx: &mut Context<Self>);                                          // EmailCancelled
pub fn email_step(&self) -> Option<EmailStep>;
pub fn email_sent_to(&self) -> Option<&str>;
pub fn email_error(&self) -> Option<&CoreErr>;
pub fn email_can_verify(&self) -> bool;
pub fn email_resend_wait_secs(&self) -> u64;      // at this service's clock (`now_ms`)
pub fn signing_in(&self) -> bool;                 // state() is LoggingIn
/// Mac development build only (screenshots): puts the flow on the email step, or with `code_step` on the code step
/// with a made-up challenge for "you@example.com". It feeds the flow directly and drops the returned actions, so no
/// core call is made.
#[cfg(target_os = "macos")]
pub fn dev_preview_email(&mut self, code_step: bool, cx: &mut Context<Self>);
// ui/login.rs SignInDialog gains
email_field: Entity<TextField>,        // TextField::new(false, t(lang, Str::EmailAddress), cx)
code_field: Entity<TextField>,         // TextField::new(false, t(lang, Str::CodePlaceholder), cx)
last_auto: Option<String>,             // the digits last submitted without a click
started_email: bool,                   // an email step was started from this dialog since it opened
shown: SignInScreen,                   // the screen drawn last
/// Mac development build only: the preview behaves as if this dialog had started the email step.
#[cfg(target_os = "macos")] pub fn mark_email_preview(&mut self);
// ui/root.rs
/// Mac development build only: `SHELLX_DEV_SIGN_IN=start|email|code` opens the sign-in dialog on that screen.
#[cfg(target_os = "macos")] fn dev_sign_in_preview(&mut self, window: &mut Window, cx: &mut Context<Self>);
```

Dialog rules (`GooglePurpose::Link` is unchanged; for `SignIn` the screen is `sign_in_screen(account.email_step(), account.email_sent_to().is_some(), account.google_in_flight().is_some(), self.started_email, account.signing_in())`):
- `Providers`: the Google button as today; under it a centred muted `OrDivider`; under that `button("sign-in-email", ContinueWithEmail, Kind::Secondary, false)`, which sets `started_email` and calls `email_start`. `GoogleWaiting`: as today. `SigningIn`: one `text_hi` line `Str::SigningIn`.
- `EmailEntry { busy }`: `email_field` (disabled while `busy`); `button("sign-in-send-code", SendCode, Kind::Primary, busy || !email_looks_valid(text))` calling `email_send_code(text.trim().to_string(), lang.locale(), cx)`.
- `CodeEntry { busy }`: a wrapping `text_hi` block `sent_code_to(lang, address)`; `code_field` (disabled while `busy`); `button("sign-in-verify", VerifyCode, Kind::Primary, busy || !account.email_can_verify() || code_digits(text).is_none())` calling `email_submit_code(text, cx)`; a row with `button("sign-in-resend", <label>, Kind::Secondary, busy || wait > 0)` (label `resend_code_in(lang, wait)` while `wait = account.email_resend_wait_secs()` is above 0, else `ResendCode`) and `button("sign-in-change-email", UseDifferentEmail, Kind::Secondary, busy)`.
- Error line: on `EmailEntry` and `CodeEntry`, `account.email_error().map(|e| email_error(lang, &e.code))`; on the other screens the Google logic of today.
- Keys: `TextFieldEvent::Submit` from the email field runs Send, from the code field runs Verify (each only when its button is enabled); `TextFieldEvent::Cancel` closes; Enter on the dialog's own handle still starts Google on `Providers` only. Each field is observed: a change redraws, and a change of `code_field` submits `auto_submit(self.last_auto.as_deref(), text, account.email_can_verify())` when it is `Some`, remembering it in `last_auto`.
- When the account changes and the screen differs from `shown`: entering `CodeEntry` from `EmailEntry` clears `code_field` and `last_auto`; `shown` is updated; `SignInEvent::Opened` is emitted so RootView moves the keyboard to `focus_target()` (`ui/root.rs:185-187`). `focus_target()` is the email field's handle on `EmailEntry`, the code field's on `CodeEntry`, else the dialog's own.
- The resend countdown repaints through a detached task started whenever the screen becomes `CodeEntry { busy: false }`: wait one second, `cx.notify()`, repeat while the dialog is open on that screen and `email_resend_wait_secs() > 0`.
- `open()` and `close()` clear both fields, `last_auto` and `started_email`; `close()` also calls `account.email_cancel(cx)`. The dialog still closes itself at `LoggedIn`.

Settings: the row title is `t(lang, sign_in_method_label(&m.provider))`; the address line, "Added from" and the Apple-only Remove button are unchanged.

`dev_sign_in_preview` (called last in `RootView::new`, under `cfg(target_os = "macos")`): for `SHELLX_DEV_SIGN_IN` equal to `start`, `email` or `code` it calls `open_sign_in(GooglePurpose::SignIn, window, cx)`; for `email` and `code` also `account.dev_preview_email(code_step, cx)` and `sign_in.mark_email_preview()`. Any other value does nothing.

README: in "Run the window on a Mac" add `SHELLX_DEV_SIGN_IN=start|email|code` (Mac development build only: opens the sign-in dialog on that screen for screenshots, with a made-up address and no network call); in "Remote view (Macs)" say the dialog offers "Continue with Google" and "Continue with email" (a 6-digit code sent to the address).

- [ ] **Step 1: Implement** the `AccountService` methods, the dialog, the Settings title, the preview switch and the README text. (This task's logic is `sign_in_screen`, `auto_submit` and the flow, tested in Tasks 1–2; GPUI views have no test harness here, so the checks are the build, the existing suites and the screenshots.)
- [ ] **Step 2: Build and run the suites.** Run: `(cd windows && cargo build --release --locked -p shellx-app && cargo test --release --locked -p shellx-app && cargo test --locked -p shellx-model)`. Expected: the build finishes with no new warning; `test result: ok` twice.
- [ ] **Step 3: Screenshots.** If `~/.local/share/shellx-native/core/session.json` exists (an earlier manual sign-in), move it aside first and put it back afterwards: with a session the dialog closes at once. Run:

```bash
cd windows
for lang in en vi; do for screen in start email code; do
  SHELLX_LANG=$lang SHELLX_DEV_SIGN_IN=$screen dev/mac-shot.sh "$TMPDIR/shellx-signin-$screen-$lang.png" 8
done; done
```
Expected: six lines `mac-shot: wrote …`. Open each PNG: `start` shows the card with the white Google button, "or" and "Continue with email"; `email` shows the Email field and "Send code" (disabled); `code` shows "We sent a code to you@example.com. Can't find it? Check your spam folder." wrapped inside the card, the code field, "Verify" (disabled), "Resend code in 5x s" (disabled) and "Use a different email"; the `vi` shots show the table's Vietnamese; no clipped or overlapping text inside the 340 px card. Fix what is off and repeat Steps 2–3. Keep the six PNGs for the hand-off; do not commit them.
- [ ] **Step 4: Commit.** `git add windows/shellx-app/src/ui windows/README.md && git commit -m "feat(shellx-windows): sign-in dialog with an email code next to Google"`

---

### Task 4: Verify and hand off

**Files:** none new.

- [ ] **Step 1: Run the full verification** from the worktree root:

```bash
(cd windows && cargo test --locked -p shellx-model)
(cd windows && cargo test --release --locked -p shellx-app)
(cd windows && cargo build --release --locked -p shellx-app)
git diff --quiet develop...HEAD -- windows/Cargo.lock shellx-core/Cargo.lock && echo locks-unchanged
(cd windows && SHELLX_LANG=en dev/mac-shot.sh "$TMPDIR/shellx-after.png" 8)
```
Expected: `test result: ok` twice; a finished build with no new warning; `locks-unchanged`; a PNG of the normal window with no dialog (the preview switch is off unless set).
- [ ] **Step 2: Secret and address scan.** Run `git diff develop...HEAD | grep -nE '^\+.*(re_[A-Za-z0-9]{8,}|RESEND_API_KEY=|@gmail\.com)'`. Expected: no match.
- [ ] **Step 3: Report and stop.** Do not merge, push to `main`, deploy, build an installer or touch the VPS. Hand-off notes: the commit list; red and green results per task; the six screenshots' paths; every command not run on this machine and why (Task 0); the section "Left for the Windows build" word for word; any string that differed from this plan's table (Task 0 Step 5); and the Contract additions below.

---

## Contract additions

For the contracts owner (the email section of `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md`):

- Windows names: `EmailChallenge`, `email_begin`, `email_finish`, `EmailStep`, `SignInScreen`, the eight `AccountEvent::Email*` variants, `AccountAction::CallEmailBegin` / `CallEmailFinish`, the `Str` variants of the String table, `email_error`, `sign_in_method_label`.
- Development-only: `SHELLX_DEV_SIGN_IN=start|email|code` on the Mac build of the window.

## Not verified while writing this plan

- No command in this plan was run. `shellx-app` has never been built on this machine (no Zig, no `ghostty` submodule, no `windows/target`), so the release build, the release tests and `dev/mac-shot.sh` are expected to work as they did for the wave-1 and 1B plans on the other machine, not observed here.
- The preview switch is this plan's design and untested: opening the dialog from inside `RootView::new` relies on GPUI delivering the `SignInEvent` after construction, as it does for the events `reconcile` causes there. If the dialog does not appear in the `start` screenshot, defer the call with `cx.defer_in(window, …)` from `new` instead; the rest of the design stands.
- Moving the keyboard between the two fields by emitting `SignInEvent::Opened` follows RootView's existing subscription (`ui/root.rs:185-187`); on real Windows it is part of "Left for the Windows build".

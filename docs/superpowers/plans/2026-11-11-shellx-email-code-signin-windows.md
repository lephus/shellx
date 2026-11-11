# ShellX Email Code Sign-in, Desktop Plan B (Windows) Implementation Plan

> **Status 2026-11-12: ON HOLD, do not execute.** A review of the Windows app found blockers outside this plan: sign-in never completes against the real relay in any native Windows build (`windows/shellx-model/src/sidebar.rs:16` requires a `fingerprint` string that the relay never sends), no public Mac build answers a PC, and nothing has run a Windows exe since 1.5.0. A design for a usable Windows app is being written (`docs/superpowers/specs/2026-11-12-shellx-windows-usable-design.md`); the email-first sign-in below will be folded into the Windows plan that follows it. The text is kept as revised on 2026-11-11 (three-lens review applied) because that plan will reuse it.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Execution (decided; revised 2026-11-11 afternoon):** one implementer, one branch, six tasks. Stage 1 (Tasks 1–2, `shellx-model`) runs on this Mac now; Task 0 (tools and a `shellx-app` baseline, no code changes) runs in the background, but only once Plan A's Task 0 has finished or stopped (never both plans' Task 0 at once; Task 0's header); Stage 2 (Tasks 3–5, `shellx-app`) starts when Task 0 succeeded and Plan A (`docs/superpowers/plans/2026-11-11-shellx-email-code-signin-core-mac.md`) is merged into `develop`. Stage 1 needs nothing from Plan A: `shellx-model` calls the core by method name through `CoreCall`, and its tests use `FakeCore`. Commits per task with the failing test first; the implementer stops after Task 5; one whole-branch review follows, then the orchestrator lands the branch on `develop` (D8).

**Goal:** The Windows app's "Sign in to ShellX" dialog opens on an email field with "Send code" (a 6-digit code mailed by the relay), with "Continue with Google" under "or", through Plan A's `auth.email.begin` and `auth.email.finish`.

**Architecture:** The pure `shellx-model` crate gains the two typed core calls, the strings, the input rules (ASCII address, Unicode digits, the dialog's screens and Tab order) and the email steps inside the event-driven `AccountFlow` (time is passed in, so the resend lock is testable); all of it runs under `cargo test` on this Mac today. `shellx-app` maps the two new actions to core calls and draws the email-first dialog with the existing `TextField` and keyboard-focusable buttons; on a Mac the release build of the window is checked with screenshots through a Mac-only preview switch.

**Tech Stack:** Rust toolchain 1.95.0 (MSRV 1.91), edition 2024, GPUI `=0.2.2`, `shellx-core` (path dependency), `shellx-fake-api` (dev-dependency).

**Spec and sources:** the binding decisions `.superpowers/sdd/2026-11-11-shellx-email-code-signin/desktop-decisions.md` (D1–D9; they win over everything below); the relay as landed on `develop` (contracts §29 in `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md`, `relay/src/routes/email-sign-in.ts`, `relay/src/auth/email-codes.ts`, `relay/src/auth/email.ts`); the email-first brief `.superpowers/sdd/2026-11-11-shellx-email-code-signin/email-first-brief.md`; the phone catalog `shellx-ios/ShellX/Localizable.xcstrings` for every new string; Plan A's "Interfaces for Plan B" for the RPC names. The spec `docs/superpowers/specs/2026-11-10-shellx-email-code-sign-in-design.md` (Vietnamese, §4 included) is background only. Conventions: Tasks 13–15 of `docs/superpowers/plans/2026-11-07-shellx-signin-1b-desktop.md`; `windows/README.md` ("Run the window on a Mac").

## Revision 2026-11-11 (afternoon)

D1–D9 are the decisions file; "recon" is `.superpowers/sdd/2026-11-11-shellx-email-code-signin/desktop-recon.json` (key: item).

1. Execution: Stage 1 (Tasks 1–2) on this Mac now, Task 0 in the background, Stage 2 (Tasks 3–5) after Task 0; six tasks instead of five; Stage 1 no longer waits for Plan A. (D6)
2. Goal, Architecture, Global Constraints: email first; no "Continue with email", no `EmailRequested` event. (D3, the brief, D5)
3. Tech Stack: toolchain 1.95.0, MSRV 1.91 (was "Rust 1.91"). (recon windows-code: plan_b_drift "Tech Stack")
4. Source of truth: contracts §29 and the relay code on `develop`; the spec is background. (D1)
5. Global Constraints: the consumed contract adds the core's local non-ASCII refusal, its Unicode digit mapping and the exact `vi`/`en` locale; the relay facts the dialog lives with. (D1, D4; recon relay-contract: relay_facts_desktop_must_handle)
6. Global Constraints: an email-path failure with no sentence of its own reads `ServerProblem` ("ShellX is having a problem. Try again later."), not "Sign-in failed: <code>"; Google keeps today's wording. (D2)
7. Global Constraints: read this plan from the main checkout (the plans are tracked since 723fd31506, so a worktree holds the committed text); `windows/Cargo.lock` also pins `shellx-core`'s graph. (recon windows-code: plan_b_drift "Task 0 Step 2", other)
8. Rulings 8 and 12 superseded, 9 and 13 amended, Rulings 14–26 added. (D1–D9)
9. Review Focus rewritten around D2's answers, the ASCII rule, the first screen Google and email share, and the keyboard. (D2, D3, D4)
10. String table: the phone catalog's en/vi; eight texts change (sentTo en and vi, `VerifyCode` vi "Xác nhận", `InvalidEmail`, `DisposableEmail` vi, `InvalidCode`, `CodeExpired` "no longer works", `EmailSendFailed`); `EmailAddress` en "Email" → "Email address"; `ContinueWithEmail` and the button id `sign-in-email` dropped; `ServerProblem` added. (D2, D5; recon ux-and-strings: strings; relay-contract: mismatch "CodeExpired wording")
11. Counts: 15 new `Str` variants (the old 15 minus `ContinueWithEmail`, plus `ServerProblem`), so `Str::ALL.len()` is 124 for a new reason; the new pairs move to their own test `email_strings_match_the_phone_catalog` (15 pairs), and `sign_in_strings_match_the_mac` keeps its 20 pairs with the `EmailAddress` en line changed. (D2, D5; recon ux-and-strings: strings_no_longer_needed)
12. Task 0 rewritten: background, the `ghostty` submodule and zig only, a detached baseline worktree, an honest estimate, the fallback to the other Mac; its old Step 1 (Plan A landed) moves to Task 3 and its old Step 5 (strings print, now of the phone catalog) to Task 1. (D6; recon build-environment; windows-code: plan_b_drift "Task 0 Step 5")
13. Task 1: `email_looks_valid` needs ASCII and at most 254 bytes after trimming; new `email_text_refused` drives the InvalidEmail line. (D4; recon windows-code: ime_and_ascii; relay-contract: mismatch "ASCII")
14. Task 1: `code_digits` maps every Unicode decimal digit to ASCII and keeps "exactly six digits in the whole text"; vectors with leading zeros, full-width and Arabic-Indic digits and the eight-digit mail body. (D4; recon relay-contract: mismatch "leading zeros", relay_facts "the mail")
15. Task 1: `SignInScreen` is `Start | Code | SigningIn`; new `DialogFocus`, `tab_order`, `tab_target`. (D3; recon windows-code: tasks_affected_by_email_first)
16. Task 1: `email_error` maps anything without a sentence to `ServerProblem`. (D2)
17. Task 2: seven `Email*` events, eight since item 39 (Send code starts the run); Google is refused only while a run is Sending, Code or Verifying, and drops a run at Email with its failure. (D3; recon windows-code: tasks_affected_by_email_first)
18. Task 2: a 409 on verify returns to the email step and drops the challenge, the digits and the lock. (D2; recon relay-contract: mismatch Plan B "409")
19. Task 2: a failed Resend drops the challenge for `email_send_failed` / `email_sign_in_disabled` and keeps it for `rate_limited` / `network` / any other code; ~~`email_sign_in_disabled` on verify voids the code~~ (reversed by item 36). (D2; recon relay-contract: mismatch Plan B "resend"; windows-code: plan_b_drift)
20. Task 2: `email_code_epoch()` tells the dialog when to empty the code field (401, 410, 409, a new or dropped challenge). (D2)
21. Task 2: the test helper is `email_finished` (an existing `finished` builds `GoogleFinished`: E0428). (recon windows-code: plan_b_drift)
22. Task 2: a test that a server sign-out of an email session asks for sign-in again. (recon relay-contract: relay_facts "Later removals")
23. Task 2 keeps the two `run_account_action` arms, so no commit leaves `shellx-app` unbuildable, but Task 3 compiles them first. (D6)
24. Task 3 (new): checks Plan A, merges `develop` when needed, prints the fake API's names, runs the real-core tests including a failed Resend. (D6; recon windows-code: other "fail_next answers before touching state")
25. Task 4 (was Task 3): the email-first dialog; the email field holds the keyboard on open, also after a server sign-out; Return, Tab (focusable buttons) and Escape as D3 says; one failure line at a time; the code field emptied on the epoch. (D2, D3)
26. Task 4: `TextField::composing()`; Send, Verify, Resend, Enter and auto-submit wait for an IME composition to end; the email field is never rewritten. (D4; recon windows-code: ime_and_ascii)
27. Task 4: previews `SHELLX_DEV_SIGN_IN=start|code|invalid|switch`, eight PNGs (was `start|email|code`, six). (D3, D4)
28. Task 4: `ui/mod.rs:18-20` (was 17-19); click handlers only on enabled buttons; the stale "Google only" comments. (recon windows-code: plan_b_drift, other)
29. Task 4: the README describes the email field with Send code and Google below; `windows/G1-G3-CHECKLIST.md` gets email-code items in place of the stale password line. (D5; recon windows-code: other)
30. Task 5 (was Task 4): verification names where each check ran; Task 0's worktree is removed after the branch lands. (D6)
31. "Left for the Windows build" is replaced by "Where each check runs": the VPS cross build runs no Windows-target `shellx-app` tests and no `--smoke`; `shellx-windows.yml` has no feature-branch or `shellx-core/**` trigger; Actions availability is unverified. (D6; recon windows-code: plan_b_drift "Left for the Windows build")
32. Contract additions: seven events (eight since item 39) and the new names. (D3)
33. Recorded, not changed here: Android keeps a dead challenge after a failed Resend and re-locking after a 429 is deferred (D9, D2); no "Your session expired" line (D3); the fake API's relay-order fixes are Plan A's (D1); `AccountFlow`'s and `SignInMethod`'s derived `Debug` already print the account email (pre-existing, outside this plan; recon windows-code: other).

Review round 1 (same afternoon):

34. Execution, Task 0's header and estimate, Ruling 24: this Task 0 starts only once Plan A's Task 0 has finished or stopped, so one `brew install` runs at a time and the two cold builds never share the 16 GB Mac (and the iOS simulator run) at once; Stage 2 waits for Plan A on `develop` anyway, so the wait costs nothing. (review: executability, "the two Task 0s are not sequenced")
35. Global Constraints, "Where each check runs", Tasks 3–5: one **Stage 2 line** (`PATH` with zig and cargo, plus `CMUX_GHOSTTY_SRC`) starts every shell that builds or tests `shellx-app`. Agent shells keep no variables between commands, and without it `ghostty-vt-sys` builds from the feature worktree's empty `ghostty` and fails (`cmux-tui/crates/ghostty-vt-sys/build.rs:11-14`, `:42-71`). `dev/mac-shot.sh` only runs the built binary and needs neither. (review: fidelity and executability, "the export is given once")
36. Ruling 22, Task 2 (the epoch doc, the `EmailFinished` rule, the D2 table, the test now `a_disabled_relay_on_verify_keeps_the_code`), Review Focus 3 and 7, Contract additions: `email_sign_in_disabled` on verify keeps the challenge and the digits. That is the RPC contract's rule (Plan A "Interfaces for Plan B", whose UI column says Plan B mirrors the Mac), and both phones do the same. (review: contract and fidelity, "the two desktops react to one code in opposite ways")
37. Task 2: new test `a_verify_refused_for_rate_network_or_server_keeps_the_code` and a D2 table row, so the verify branch "any other code → `Code`, challenge kept" is pinned like the others. (review: contract, "no verify-side 429, network or 5xx test")
38. Task 2: `a_failed_resend_keeps_the_challenge_for_rate_limited_and_network` submits last. A Resend at `Verifying` is refused by the rule, so the old order could not pass. (review: executability)
39. Tasks 2 and 4: new `AccountEvent::EmailEdited` (eight events), sent when the email field's text changes (compared with `email_text_seen`, so a click or a cursor move is no edit). At `Email` it clears the run's failure, so a stale relay sentence gives way to the InvalidEmail sentence as soon as a character outside ASCII is typed (D4), as on the Mac (Plan A Ruling 27) and Android. Test `editing_the_address_clears_the_email_failure`. (review: contract, "a stale failure hides InvalidEmail")
40. Ruling 21, Task 4's `Start` rule, Review Focus 8: the email line stays empty while Google's failure line shows, so the InvalidEmail hint and Google's failure never show together (D3). (review: executability, "two failure lines")
41. Task 3 uses Plan A's final fake names: `set_next_email_code("004217")` always, so the leading zeros go through the real core; `email_locale` is `"vi"`; `fail_next_mail()` stands for the 502, and the fake's code is checked gone; `FakeOptions.email_routes: false` stands for an old relay's 404. New test `a_rate_limited_resend_through_the_real_core_keeps_the_code`. The stale "Not verified" hedge is reworded. (review: fidelity, contract and executability, "the fake's names")
42. Contract additions: the desktop section goes after the iPhone part's §31 and is numbered when it lands, together with Plan A's. The failed-Resend drop is shared with the Mac and the iPhone, not Windows-only. (review: contract)

## Global Constraints

- The relay (D1): contracts §29 and the relay code on `develop`. Facts the dialog lives with: one live code per address and the newest request wins (a newer request from any device makes this challenge answer 410; a code from an older mail is a counted wrong guess); a relay restart or deploy voids every live code (410, no guess counted); the code is a six-character string that keeps its leading zeros (`"004217"`); a 409 on verify means the code is already spent; no 429 carries `Retry-After`; email verifies and Google sign-ins share 10 per IP per minute; the mail's text body also says "10 minutes", so a pasted whole body has eight digits. Production (D1, a note): `PASSWORD_LOGIN` defaults to `on`, so a code for an account that still has a password answers 409.
- The core contract this plan consumes (Plan A's "Interfaces for Plan B"; if `shellx-core` on `develop` differs, the code wins and the difference goes in the hand-off):

  ```
  auth.email.begin  {email, locale?} -> {challenge_id, expires_in, resend_in, email}      email = the relay's normalized address
  auth.email.finish {challenge_id, code} -> {user_id, device_id, device_public_key_b64, fingerprint, email, auth_method: "email"}
  ```

  The core sends the relay exactly `vi` or `en` (D1); refuses an address with any character outside ASCII after trimming as `invalid_email` without a request (D4); removes whitespace from `code`, maps Unicode decimal digits to ASCII and refuses anything but six digits as `invalid_code` without a request (D4); 404 (with or without JSON) and 503 `email_sign_in_disabled` both reach the app as `email_sign_in_disabled` (Plan A Ruling 1).
- Wording of email-path failures (D2): `invalid_email`, `disposable_email`, `rate_limited`, `email_send_failed`, `email_sign_in_disabled`, `invalid_code`, `code_expired`, `switch_from_signed_in_device` have their own sentences; `network` keeps the desktop's `RelayUnreachable`; anything else (`http_502` / `http_503` / `http_504` without JSON, `server`, `invalid_device`, …) reads `ServerProblem`. Google-path errors keep today's `google_error`.
- Code: 6 digits, lives 600 s, 5 guesses; "Resend code" is locked for the `resend_in` the core returns (60 s); after a 429 it unlocks at once (re-locking is deferred, D2).
- Email first (D3): the SignIn dialog opens on the email field with Send code, then "or", Continue with Google, Cancel. No "Continue with email", no discovery call. The Link dialog ("Switch to Google sign-in") is unchanged.
- Strings (D5): every new email string equals the en / vi value of the phone catalog `shellx-ios/ShellX/Localizable.xcstrings` on `develop` (the catalog wins over this plan's table), pinned by `email_strings_match_the_phone_catalog`; older desktop strings (Google path, `RelayUnreachable`) are unchanged.
- Tests fake the relay (`shellx-fake-api`) and the core (`FakeCore`). Nothing here needs a running relay, a real mailbox or a key.
- Never log or `Debug`-print the code, the `challenge_id` or an email address (the manual `Debug` impls of `AccountEvent` / `AccountAction`, the email run and `core_api` values).
- No new crates: `windows/Cargo.lock` stays unchanged. It also holds `shellx-core`'s dependency graph, so Plan A must not change that graph either, or every `--locked` Windows build fails.
- No account deletion by code: Settings keeps the `DELETE_ACCOUNT_URL` link.
- On a Mac never build or run a debug `shellx-app` (it crashes, `windows/README.md:54-57`): `cargo test --release`, `cargo build --release`. `cargo test -p shellx-model` is fine. cargo lives in `~/.cargo/bin`: every shell starts with `export PATH="$HOME/.cargo/bin:$PATH"`. In Stage 2, every shell that builds or tests `shellx-app` starts with the **Stage 2 line** of Task 3 Step 1.3 instead, which also puts zig on `PATH` and sets `CMUX_GHOSTTY_SRC`. Agent shells keep no variables between commands, so the line is repeated in every such shell. `dev/mac-shot.sh` only runs the built binary and needs neither.
- Never release, deploy, build an installer, push or merge to `main`, sign, notarize, use `gh`, dispatch a workflow or touch the VPS. Build no Mac app (no `xcodebuild`, no `reload.sh`); never quit, launch or replace `/Applications/ShellX.app` or any cmux app: the screenshots start only `windows/target/release/shellx-desktop`, and `dev/mac-shot.sh` kills only the PID it started. The implementer does not merge into `develop`; the plan ends with the orchestrator landing the branch there after review (D8). No Windows release with the email path before the relay with the feature is deployed (the user's decision, D8).
- Branch `feat/shellx-email-code-signin-windows` from `develop`, worktree `.worktrees/email-code-signin-windows`. Commit style: `test(shellx-windows): …` then `feat(shellx-windows): …`.
- Read this plan from the main checkout (`/Users/richard/Documents/helper/shellx/docs/superpowers/plans/2026-11-11-shellx-email-code-signin-windows.md`): the worktree's copy is the one committed on `develop` and may predate this revision. Do not edit the plan on the branch.

## Review Focus

1. **A code pasted with spaces, a line break or the mail's subject around it, or typed in full-width or Arabic-Indic digits.** Its six digits are used, as ASCII; the whole mail body (eight digits) keeps Verify off. Tests: Task 1 `code_digits_takes_the_six_digits_of_what_was_typed`; Task 2 `email_sign_in_runs_email_code_verify_then_lists`; Task 3 `email_session_against_fake_api`.
2. **Double submit: six digits submit by themselves while Enter or Verify is pressed.** One `CallEmailFinish`. Tests: Task 1 `auto_submit_fires_once_per_new_six_digits`; Task 2 `verify_runs_once_for_a_double_submit`.
3. **Each verify answer of D2.** 401: stays, the code is emptied, the challenge kept; 410: field off and emptied, Resend unlocked at once; 409: back to the first screen with the address, the challenge and digits dropped; any other answer (429, network, a body-less 5xx, `invalid_device`, `email_sign_in_disabled`): the code step with the digits and the challenge kept. Tests: Task 2 `a_wrong_code_empties_the_field_and_stays_on_the_code_step`, `an_expired_code_drops_the_challenge_and_unlocks_resend`, `a_switch_answer_returns_to_the_first_screen`, `a_verify_refused_for_rate_network_or_server_keeps_the_code`, `a_disabled_relay_on_verify_keeps_the_code`.
4. **A failed Resend.** 502 `email_send_failed`, 503 `email_sign_in_disabled` and 404 drop the challenge (Verify off); 429, network and a body-less 5xx keep it; Resend is unlocked either way. Tests: Task 2 `a_failed_resend_drops_the_challenge_the_relay_lost`, `a_failed_resend_keeps_the_challenge_for_rate_limited_and_network`; Task 3 `a_failed_resend_through_the_real_core_drops_the_challenge`, `a_rate_limited_resend_through_the_real_core_keeps_the_code`.
5. **An address with a Vietnamese letter (Telex, VNI, Unikey turn "ex" into "ẽ").** Send code stays off, "That doesn't look like an email address." shows under the field, also after an earlier failed Send (editing clears that failure), no request; an IME composition is never rewritten. Tests: Task 1 `plausible_addresses`, `refused_text_shows_the_invalid_email_sentence`; Task 2 `send_code_needs_a_plausible_ascii_address_and_runs_once`, `editing_the_address_clears_the_email_failure`.
6. **Closing the dialog mid-flow and opening it again.** A late answer never brings an old screen back; the reopened dialog starts clean; a code that verified after the close still signs this PC in. Tests: Task 2 `closing_while_sending_ignores_the_late_challenge`, `closing_while_verifying_still_signs_in_when_the_code_was_right`, `reopening_after_a_close_starts_clean`.
7. **A relay without the feature (production today), a body-less 5xx, offline.** "This way of signing in isn't available in this build.", "ShellX is having a problem. Try again later." or the network sentence under the field; the app stays signed out; a late `not_logged_in` list never throws the person off the code step. Tests: Task 1 `email_error_maps_codes`; Task 2 `a_relay_without_email_sign_in_keeps_the_app_signed_out`, `a_disabled_relay_on_verify_keeps_the_code`, `a_failed_send_returns_to_the_first_screen_with_the_error`, `a_late_list_result_does_not_reset_the_email_step`; Task 3 `a_relay_without_email_sign_in_answers_through_the_real_core`.
8. **Google and email on one screen.** Never both running; one failure line at a time, so the InvalidEmail hint also hides while Google's failure shows (a dialog rule: no GPUI test harness here, so it is checked by reading Task 4's code and by hand). Test: Task 2 `email_and_google_share_the_first_screen`.
9. **Keyboard only.** The email field has the keyboard on open, Return sends or verifies, Tab follows D3's order, Escape closes. Test: Task 1 `tab_follows_the_dialog_order`; the rest by hand (Where each check runs, rows 7 and 10).

## Rulings

1. `AccountState` is unchanged. The spec says "`AccountState/Event/Action` thêm các bước", but `AccountState` is what Settings and the sidebar read and `AccountState::Error` is printed by Settings (`ui/settings.rs:136-139`); a half-typed code is not an account state. The steps are an `EmailStep` beside it, with new `AccountEvent` / `AccountAction` variants.
2. Email failures live in the email run (`email_error()`), never in `AccountState::Error`: a wrong code returns the account to `LoggedOut`.
3. Windows has no visible "done" step: after a right code the flow lists and registers exactly as after Google and the dialog closes at `LoggedIn` (plan 1B's ruling for Google); meanwhile it shows "Signing in…". (D3 confirms.)
4. Closing the dialog cannot cancel a verify already sent (no cancel API): the run is hidden and its answer still applies. (D3 confirms.)
5. `reset_session()` leaves the email run alone; entering `LoggedIn` drops it.
6. `email_finish` returns the existing `GoogleSignIn` value (same shape); no rename.
7. A new `email_error()` words the email codes; `google_error()` and its tests are untouched, so Google's 429 still reads "Sign-in failed: rate_limited" here. (Its fallback is Ruling 17's.)
8. ~~The code field shows what was typed or pasted; Verify and the auto-submit use `code_digits` of it and need exactly six digits; `TextField` is not rewritten.~~ **Superseded by Ruling 16** (D2 row 1, D4).
9. The resend lock reads "Resend code in 42 s" and the sent-to line carries the spam hint as its second sentence. **Amended by Ruling 18** (D5): the words are the phone catalog's.
10. The email's language is `Lang::locale()` (`"vi"` or `"en"`).
11. Settings › Account titles an `email` identity "Email code" with the address under it; Remove stays for Apple IDs only.
12. ~~A Mac-only preview switch `SHELLX_DEV_SIGN_IN=start|email|code`.~~ **Superseded by Ruling 23** (D3, D4).
13. The spec says only debug tests of `shellx-app` cannot run on a Mac; this plan runs its release tests there. **Amended by Ruling 24** (D6): on this Mac only after Task 0, else on the user's other Mac.
14. **Email first (D3).** The SignIn dialog opens on the email step: the email field (placeholder "Email address"), Send code, the "or" line, Continue with Google, Cancel. `AccountEvent::EmailRequested` and `Str::ContinueWithEmail` do not exist; `EmailCodeRequested` (Send code) starts the run. `SignInScreen` is `Start { sending, google_waiting }`, `Code { busy }` or `SigningIn`; "Waiting for Google…" replaces the Google button inside `Start`. `GooglePurpose::Link` is unchanged.
15. **Google and email on one screen (D3).** `GoogleRequested(SignIn)` is accepted with no run or a run at `Email`, and drops that run with its failure; it is refused while a run is `Sending`, `Code` or `Verifying`. `EmailCodeRequested` is refused while a Google flow runs.
16. **The code field (supersedes 8; D2, D4).** It shows what was typed or pasted and is never filtered or rewritten while typing, so an IME composition is never disturbed. Verify and the auto-submit use `code_digits` (every Unicode decimal digit as ASCII; exactly six digits in the whole text). The dialog empties it, never during a composition, when `email_code_epoch()` moves: a new challenge, a wrong code, a dead or dropped challenge, a 409.
17. **Each relay answer (D2).** Verify: `invalid_code` → code step, field emptied, challenge kept; `code_expired` → code step, challenge dropped (field off and emptied), Resend unlocked; `switch_from_signed_in_device` → the first screen with the typed address kept, the challenge, sent-to address, digits and lock dropped, the switch sentence under the field; any other failure → code step, digits and challenge kept. Failed Resend: `email_send_failed`, `email_sign_in_disabled` (404 included) → challenge dropped; `rate_limited`, `network` → kept; Resend unlocked in both. Failed first Send: the first screen with the sentence; Send works again at once. The sentences are `email_error`'s.
18. **Strings (D5).** The phone catalog's en / vi for the 15 new variants; `EmailAddress` en becomes "Email address" (vi unchanged, and the Mac's new `remote.signin.email.field` has the same text); `ServerProblem` is the catalog's `signin.error.server`, used by `email_error` only; `network` keeps `RelayUnreachable`, and Google's errors keep their texts.
19. **ASCII (D4).** `email_looks_valid` needs ASCII and at most 254 bytes after trimming (the relay's limits and the phones' rule); `email_text_refused` puts `InvalidEmail` under the field as soon as such a character is committed, never while a composition is open. Windows has no per-field input-source switch (Unikey and EVKey are global hooks; GPUI 0.2.2 offers no input scope), so the rule and its sentence are the protection.
20. **Keyboard (D3).** The email field holds the keyboard when the dialog opens, also when it opens by itself after a server sign-out. Return in the email field is Send code when it is enabled; Return in the code field is Verify when it is enabled; six digits submit by themselves. Tab and Shift+Tab follow `tab_order` (first screen: email field, Send code, Continue with Google, Cancel; code step: code field, Verify, Resend, Use a different email, Cancel), skipping disabled controls; today no button can take the keyboard, so the dialog gives its buttons focus handles; Enter or Space presses a focused button. Escape is Cancel anywhere in the dialog and drops a pending challenge. Enter on the dialog's own handle starts Google only for `Link`.
21. **One failure line (D3).** The email failure, or the InvalidEmail hint, shows under the email field; Google's under the Google button. Pressing Send code or typing in the email field hides Google's failure (`started` cleared); pressing Google drops the run with its failure (Ruling 15). While Google's failure shows, the email line stays empty, so a refused address's hint waits until typing hides Google's failure. Editing the address (`EmailEdited`) clears the email run's failure at `Email`, so the InvalidEmail sentence replaces a stale relay sentence as soon as a character outside ASCII is typed (D4; the Mac's `setEmail` does the same, Plan A Ruling 27).
22. **Codes D2 does not list.** `email_sign_in_disabled` on verify keeps the challenge and the digits, like every other verify failure without a rule of its own (Ruling 17). That is the RPC contract (Plan A's "Interfaces for Plan B": "on verify, keep the digits", which the Mac follows and Plan B mirrors), and both phones do the same. On verify it can only come from a 404, because the relay's `/verify` never answers 503 (only `/code` checks for the mail gateway, `relay/src/routes/email-sign-in.ts:44`; `/verify` starts at `:95`); a relay that comes back with the feature has restarted, so the next Verify answers 410 and drops the challenge then. A failed Resend with any code not named in Ruling 17 keeps the challenge, as `network` does: its state is unknown, and a dead one answers 410 on the next Verify, which counts no guess.
23. **Preview (supersedes 12; D3, D4).** `SHELLX_DEV_SIGN_IN=start|code|invalid|switch`, compiled only under `cfg(target_os = "macos")`, never in the Windows product: `start` the empty first screen, `code` the code step for "you@example.com", `invalid` the first screen with "phu@ẽample.com", `switch` the first screen after a 409 with "you@example.com". Release builds always talk to `https://relay.shellx.pro` and `dev/mac-shot.sh` cannot click or type, so this is the only way to screenshot these screens; the preview feeds the flow directly and makes no core call.
24. **Stages (D6).** Stage 1 (Tasks 1–2) runs on this Mac now and changes `shellx-model` plus the two `run_account_action` arms, which are written in Task 2 and compiled first in Task 3. Task 0 runs in the background in its own detached worktree once Plan A's Task 0 has finished or stopped. Stage 2 (Tasks 3–5) needs Task 0 (the `ghostty` submodule and zig; no GhosttyKit, Metal or Xcode build) and Plan A on `develop`. If Task 0 fails here, Stage 2's checks run on the user's other Mac (Task 0 Step 6).
25. **Outside this plan.** A live check against a relay with Resend needs a debug build on a Windows PC with `SHELLX_API_BASE` and a port forward, or the deployed relay: the user's (D7). Android's kept challenge after a failed Resend, re-locking after a 429 (D9) and a "Your session expired" line (D3) are not touched.
26. **iPhone (D3, non-blocking).** The iPhone code step has not landed (`feat/shellx-email-code-signin-ios`). When it lands, compare its code-step rules with Ruling 17 and list the differences in the hand-off; nothing here waits for it.

## Where each check runs (D6)

Commands run from the feature worktree's root after `export PATH="$HOME/.cargo/bin:$PATH"`; rows 4 and 5 after the Stage 2 line of Task 3 Step 1.3 instead, in the same shell.

| # | Check | Command | This Mac now | This Mac after Task 0 | Elsewhere |
| --- | --- | --- | --- | --- | --- |
| 1 | `shellx-model` tests (Tasks 1–2) | `(cd windows && cargo test --locked -p shellx-model)` | yes (192 passed on `develop`, 2026-11-11) | yes | GitHub `shellx-windows.yml` jobs `model` (ubuntu) and `app` (Windows target); the VPS cross build's container |
| 2 | Lockfiles unchanged | `git diff --quiet develop...HEAD -- windows/Cargo.lock shellx-core/Cargo.lock && echo locks-unchanged` | yes | yes | — |
| 3 | Secret and address scan | Task 5 Step 2 | yes | yes | — |
| 4 | `shellx-app` release tests on the Mac host, including Task 3's real-core tests | `(cd windows && cargo test --release --locked -p shellx-app)` | no: no `ghostty` submodule, no zig | yes | the user's other Mac (Task 0 Step 6) |
| 5 | `shellx-app` release build on the Mac host | `(cd windows && cargo build --release --locked -p shellx-app)` | no | yes (cold in a new worktree: about 5–10 min) | the user's other Mac |
| 6 | Eight dialog screenshots | Task 4 Step 3 (`dev/mac-shot.sh`) | no | yes, when the terminal has Screen Recording permission (the user's setting; not checked) | the user's other Mac |
| 7 | Keyboard walk-through of the dialog on the Mac build: Tab order, Return, Escape (macOS input methods, not Windows IMEs) | `(cd windows && SHELLX_LANG=en SHELLX_DEV_SIGN_IN=start target/release/shellx-desktop)`, keys by hand | no | the user only (an agent cannot type into the window); Send code there reaches `relay.shellx.pro`, which says "not available" until the relay is deployed | the user's other Mac |
| 8 | Windows-target build and tests, `--smoke`, `--version` | job `app` of `.github/workflows/shellx-windows.yml`: `cargo build --release --locked -p shellx-app --target x86_64-pc-windows-msvc`, `cargo test --release --locked -p shellx-app --bin shellx-desktop --target x86_64-pc-windows-msvc`, `shellx-desktop.exe --smoke` and `--version` | no | no | GitHub windows-2025: a dispatch on the branch, or the push of `develop` that lands it (path filter `windows/**`), both the user's (no `gh`, no token here); Actions availability unverified (billing block noted 2026-10-28). Or a Windows PC on toolchain 1.95.0 |
| 9 | Windows exe cross-built, `shellx-model` tests on Linux (no Windows-target `shellx-app` tests, no `--smoke`) | `scripts/shellx/release/build-windows-cross.sh` | no | no | the VPS, only on the user's word (shared VPS, the user's ssh master) |
| 10 | Real Windows: typing, Ctrl+V and IME (Windows Telex, VNI, Unikey, EVKey) in the email field, a pasted code, Tab and Escape, DirectWrite layout at 100, 125 and 150 % | by hand, `windows/G1-G3-CHECKLIST.md` "Đăng nhập và ghép cặp" | no | no | the user's Windows 10 1809+ or 11 PC, with the artifact of row 8 or the exe of row 9 |
| 11 | Live sign-in with a mailed code | a debug build on a Windows PC with `SHELLX_API_BASE=http://127.0.0.1:<port>` and a port forward to the orchestrator's relay (D7), or a release build once the relay is deployed | no | no | the user, with a real mailbox |

**Task 0 estimate** (the Windows checks only; nothing of it observed on this Mac): downloads about 0.3–1.2 GB (the `ghostty` clone, not measured with `--depth 1`, about 0.8 GB as a full clone on the other Mac; zig about 50 MB; about 311 crates of `shellx-app` not yet cached, 100–300 MB); disk 3–6 GB (the release target of `windows/`, the submodule, zig); wall time 25–45 min (downloads 10–20 min, the first release build about 5 min on the other Mac plus the libghostty-vt zig build, the baseline tests and screenshot), longer while the iOS simulator run shares the CPU. This Task 0 starts after Plan A's Task 0, whose Step 7 installs zig, so Step 3 normally only checks it; it installs zig only when Plan A's Task 0 stopped before its Step 7. Zig is unproven on this Mac's macOS 26.5: `.github/workflows/shellx-mac.yml:53-54` notes that zig's MachO linker cannot resolve libSystem on macOS 26 for the CI helper build, while the other Mac built libghostty-vt with zig 0.16.0 in October.

## String table

`Str` variants and helpers in `windows/shellx-model/src/strings.rs`; each value equals the phone catalog's (D5).

| Win | Catalog key | en | vi |
| --- | --- | --- | --- |
| `OrDivider` | `signin.email.or` | or | hoặc |
| `EmailAddress` (exists; en changes) | `signin.email.field` | Email address | Địa chỉ email |
| `SendCode` | `signin.email.send` | Send code | Gửi mã |
| `sent_code_to()` | `signin.email.sentTo %@` | We sent a 6-digit code to {email}. If it isn't there in a minute, check your spam folder. | Đã gửi mã 6 chữ số tới {email}. Nếu sau một phút chưa thấy, hãy xem cả thư rác. |
| `CodePlaceholder` | `signin.email.code` | 6-digit code | Mã 6 chữ số |
| `VerifyCode` | `signin.email.verify` | Verify | Xác nhận |
| `ResendCode` | `signin.email.resend` | Resend code | Gửi lại mã |
| `resend_code_in()` | `signin.email.resendIn %lld` | Resend code in {secs} s | Gửi lại mã sau {secs} giây |
| `UseDifferentEmail` | `signin.email.change` | Use a different email | Dùng email khác |
| `InvalidEmail` | `signin.error.invalidEmail` | That doesn't look like an email address. | Địa chỉ email này chưa đúng. |
| `DisposableEmail` | `signin.error.disposableEmail` | Temporary email addresses can't be used. Try another address. | Không dùng được địa chỉ email tạm thời. Hãy dùng địa chỉ khác. |
| `InvalidCode` | `signin.error.invalidCode` | That code isn't right. Check the email and try again. | Mã chưa đúng. Xem lại email rồi thử lại. |
| `CodeExpired` | `signin.error.codeExpired` | That code no longer works. Send a new one. | Mã này không còn dùng được. Hãy gửi mã mới. |
| `EmailSendFailed` | `signin.error.emailSendFailed` | Couldn't send the email. Try again in a moment. | Chưa gửi được email. Thử lại sau giây lát. |
| `SignInUnavailable` | `signin.error.providerUnavailable` | This way of signing in isn't available in this build. | Bản này chưa dùng được cách đăng nhập này. |
| `RateLimited` | `signin.error.rateLimited` | Try again in a few minutes. | Thử lại sau ít phút. |
| `ServerProblem` (D2) | `signin.error.server` | ShellX is having a problem. Try again later. | ShellX đang gặp sự cố. Thử lại sau. |
| `EmailCodeMethod` | `settings.account.method.email` | Email code | Mã qua email |

Used unchanged: `SwitchFromSignedInDevice` (equal to the catalog's `signin.error.switchFromSignedInDevice`), `RelayUnreachable` for `network` (D5 keeps the desktop's "Can't reach relay.shellx.pro"), `SigningIn`, `Cancel`, `ContinueWithGoogle`, `SignInTitle`. Not added: `ContinueWithEmail` (D5). Fifteen new variants: `Str::ALL` grows from 109 to 124.

## File structure

| File | Responsibility |
| --- | --- |
| `windows/shellx-model/src/email_sign_in.rs` (create) | `EmailStep`; the address and code rules; the auto-submit rule; which screen the dialog draws and its Tab order |
| `windows/shellx-model/src/core_api.rs` (modify) | `EmailChallenge`, `email_begin`, `email_finish`, `SignInMethod::is_email` |
| `windows/shellx-model/src/strings.rs` (modify) | 15 `Str` variants, `EmailAddress` en, `Lang::locale`, `sent_code_to`, `resend_code_in`, `email_error`, `sign_in_method_label` |
| `windows/shellx-model/src/account.rs` (modify) | The email run inside `AccountFlow`: events, actions, accessors |
| `windows/shellx-app/src/core_service.rs` (modify) | The two actions' core calls (Task 2); the real-core tests (Task 3) |
| `windows/shellx-app/src/ui/text_field.rs` (modify) | `composing()`; the Mac-only `dev_set_text` |
| `windows/shellx-app/src/ui/account.rs` (modify) | Window-side methods over the flow; the Mac-only preview |
| `windows/shellx-app/src/ui/login.rs` (modify) | The dialog: first screen, code step, focus and keys |
| `windows/shellx-app/src/ui/settings.rs`, `ui/root.rs`, `ui/mod.rs`, `windows/README.md`, `windows/G1-G3-CHECKLIST.md` (modify) | Method label; preview switch; `text_field` used again; the docs; the Windows PC checklist |

---

### Task 0: Tools and a `shellx-app` baseline for Stage 2 (background, no code changes)

The orchestrator starts this once Task 1 Step 1 has created the feature worktree (two `git worktree add` at once can collide) **and** Plan A's Task 0 has finished or stopped. Never run both plans' Task 0 at once: only one `brew install` may run at a time (Homebrew locks a formula while it installs), and Plan A's cold Xcode compile and this cargo release build would share the 16 GB Mac with the iOS simulator run. Stage 2 waits for Plan A on `develop` anyway, so the wait costs nothing. It edits no file of the branch, builds no Mac app (no `xcodebuild`, no `reload.sh`, no DEV app, tagged or not) and never touches `/Applications/ShellX.app`. Heavy commands run under `nice -n 19 env CARGO_BUILD_JOBS=4` while another agent uses the iOS simulator.

**Files:** none. Creates the detached worktree `.worktrees/email-code-signin-windows-t0` (no branch); it stays until the branch lands, because Stage 2 builds against its `ghostty` checkout.

- [ ] **Step 1: Baseline worktree.** `git -C /Users/richard/Documents/helper/shellx worktree add --detach .worktrees/email-code-signin-windows-t0 develop`. Every later path of this task is relative to it. A detached checkout keeps the baseline free of Stage 1's half-written code.
- [ ] **Step 2: ghostty.** `git submodule update --init --depth 1 ghostty` (without `--depth 1` if the pinned commit cannot be fetched that way). Expected: `ghostty/build.zig.zon` exists. Record `git -C ghostty rev-parse HEAD`.
- [ ] **Step 3: zig.** `bash scripts/ghostty-zig-version.sh "$PWD"` prints the minimum version (expected 0.16.x: `windows/cross/Dockerfile:12` pins 0.16.0). When `bash -c 'source scripts/ghostty-zig-version.sh && ghostty_require_compatible_zig "$PWD"'` already passes, go on. Else `brew install zig` when `brew info zig` shows the same major.minor, otherwise `brew install zig@<major.minor>` with `"$(brew --prefix zig@<major.minor>)/bin"` first on `PATH`. Expected: the check prints `zig <version> found at <path>`.
- [ ] **Step 4: Baseline** of unchanged `develop` (record any failing test by name: it predates this plan):

```bash
export PATH="$HOME/.cargo/bin:$PATH"   # plus zig's bin from Step 3 when a versioned formula was installed
cd windows
nice -n 19 env CARGO_BUILD_JOBS=4 cargo test --release --locked -p shellx-app
nice -n 19 env CARGO_BUILD_JOBS=4 cargo build --release --locked -p shellx-app
SHELLX_LANG=en dev/mac-shot.sh "$TMPDIR/shellx-baseline.png" 8
```
Expected: `test result: ok`, a finished build, `mac-shot: wrote …` and a PNG that shows the ShellX window. A PNG without the window's content means the terminal has no Screen Recording permission: do not change system settings; Task 4's screenshots are then "not taken here".
- [ ] **Step 5: Report** to the orchestrator: zig's version and path, the `ghostty` commit, each command's result and wall time, `du -sh windows/target ghostty`, and "Stage 2 can run here: yes / no".
- [ ] **Step 6: If Task 0 fails here** (zig cannot be installed, libghostty-vt does not build with zig on macOS 26.5, or any other environment reason): do not work around it. Stage 1 is unaffected; Tasks 3–4's code is still written and committed here, every `shellx-app` command is reported "not run on this machine", and the checks move to the user's other Mac (the release Mac, which built libghostty-vt with zig 0.16.0 in October). The user brings the branch there (a push of `feat/shellx-email-code-signin-windows` or a `git bundle`, the user's choice; the implementer never pushes) and runs, from that checkout's root:

```bash
git switch feat/shellx-email-code-signin-windows && git submodule update --init ghostty
bash -c 'source scripts/ghostty-zig-version.sh && ghostty_require_compatible_zig "$PWD"'
export PATH="$HOME/.cargo/bin:$PATH" && cd windows
cargo test --locked -p shellx-model && cargo test --release --locked -p shellx-app && cargo build --release --locked -p shellx-app
for lang in en vi; do for screen in start code invalid switch; do
  SHELLX_LANG=$lang SHELLX_DEV_SIGN_IN=$screen dev/mac-shot.sh "$TMPDIR/shellx-signin-$screen-$lang.png" 8
done; done
```
The user sends back the output and the eight PNGs; fixes go in new commits here, and the round repeats.

---

## Stage 1: runs on this Mac now

### Task 1: Model: the two core calls, the strings and the input rules

**Files:**
- Create: `windows/shellx-model/src/email_sign_in.rs`; modify `windows/shellx-model/src/lib.rs:3-19` (`pub mod email_sign_in;`)
- Modify: `windows/shellx-model/src/core_api.rs` (types after `SignInMethod` :200-219, wrappers after `remove_sign_in_method` :251-257, tests :628-719)
- Modify: `windows/shellx-model/src/strings.rs` (`Lang` :10-31, `Str` :33-159, `ALL` :161-273, `t` :276-517 with `EmailAddress` :360 and :479, helpers after `google_error` :540-554, tests :660-665 and :741-878)

**Interfaces:**
- Consumes: the core contract (Global Constraints); the String table.
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
// 15 new Str variants (the Win column) in Str, ALL and both arms of t(); Str::EmailAddress en "Email address"
pub fn sent_code_to(lang: Lang, email: &str) -> String;
pub fn resend_code_in(lang: Lang, secs: u64) -> String;   // whole seconds
/// The dialog's line for an email-path failure: the eight email sentences, `network` -> RelayUnreachable,
/// anything else -> ServerProblem (D2).
pub fn email_error(lang: Lang, code: &str) -> String;
/// Settings row title: "apple" -> AppleId, "email" -> EmailCodeMethod, anything else -> GoogleAccount.
pub fn sign_in_method_label(provider: &str) -> Str;
// email_sign_in.rs
pub const CODE_LEN: usize = 6;
/// The relay's longest address, in bytes (ASCII only).
pub const EMAIL_MAX_LEN: usize = 254;
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EmailStep { Email, Sending, Code, Verifying }
/// After trimming: ASCII only, at most EMAIL_MAX_LEN bytes, text before and after an '@', then a '.' with text
/// on both sides, no whitespace inside.
pub fn email_looks_valid(text: &str) -> bool;
/// After trimming, the text has a character outside ASCII or is longer than EMAIL_MAX_LEN: the dialog shows
/// InvalidEmail under the field before any request.
pub fn email_text_refused(text: &str) -> bool;
/// Every Unicode decimal digit (category Nd) of `raw` as an ASCII digit, when there are exactly six; every other
/// character is skipped.
pub fn code_digits(raw: &str) -> Option<String>;
/// The digits to submit without a click: `code_digits(text)` when a challenge can be verified and they differ from `last`.
pub fn auto_submit(last: Option<&str>, text: &str, can_verify: bool) -> Option<String>;
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SignInScreen { Start { sending: bool, google_waiting: bool }, Code { busy: bool }, SigningIn }
/// What the "Sign in to ShellX" dialog draws. `has_sent_to`: a code was already sent in this run;
/// `code_submitted`: this dialog submitted a code since it opened; `logging_in`: `AccountState::LoggingIn`.
pub fn sign_in_screen(step: Option<EmailStep>, has_sent_to: bool, google_waiting: bool, code_submitted: bool, logging_in: bool) -> SignInScreen;
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DialogFocus { EmailField, SendCode, Google, CodeField, Verify, Resend, ChangeEmail, Cancel }
/// D3's Tab order: Start -> [EmailField, SendCode, Google, Cancel]; Code -> [CodeField, Verify, Resend, ChangeEmail, Cancel];
/// SigningIn -> [Cancel].
pub fn tab_order(screen: SignInScreen) -> &'static [DialogFocus];
/// Where Tab (Shift+Tab with `back`) moves from `from`: the next (previous) entry of `order` that `enabled` accepts,
/// wrapping around; `from` when no other entry is accepted; the first accepted entry when `from` is not in `order`.
pub fn tab_target(order: &[DialogFocus], from: DialogFocus, back: bool, enabled: impl Fn(DialogFocus) -> bool) -> DialogFocus;
```

`sign_in_screen`: `Some(Email)` → `Start { sending: false, google_waiting }`; `Some(Sending)` → `Code { busy: true }` with `has_sent_to`, else `Start { sending: true, google_waiting: false }`; `Some(Code)` → `Code { busy: false }`; `Some(Verifying)` → `Code { busy: true }`; `None` → `Start { sending: false, google_waiting: true }` when `google_waiting`, else `SigningIn` when `code_submitted && logging_in`, else `Start { sending: false, google_waiting: false }`.

`code_digits` maps with `const DECIMAL_ZEROS: [u32; 65]`, the zero code point of every `Nd` run (each run is ten consecutive code points valued 0–9, a Unicode stability guarantee): a character `c` with `z <= c < z + 10` for a zero `z` is the ASCII digit `c - z`. No crate (Global Constraints). Generate the list once with the command below and keep the command in a comment above it; this Mac's Python 3.9.6 has Unicode 13.0 (65 runs, `0x30` to `0x1fbf0`):

```bash
python3 -c "import sys,unicodedata as u; print(', '.join(hex(c) for c in range(sys.maxunicode+1) if u.category(chr(c))=='Nd' and u.decimal(chr(c))==0))"
```

- [ ] **Step 1: Worktree, baseline, the catalog's strings.** Use superpowers:using-git-worktrees to create `.worktrees/email-code-signin-windows` on a new branch `feat/shellx-email-code-signin-windows` from `develop`; every later path is relative to it (the orchestrator may start Task 0 now). `export PATH="$HOME/.cargo/bin:$PATH"`; `(cd windows && cargo test --locked -p shellx-model)` → `test result: ok. 192 passed`. Then print the phone catalog's values, which are the expected values of this task's tests; where one differs from the String table, the catalog wins (note it for the hand-off). Keys with an argument carry it in their name (`signin.email.sentTo %@`, `signin.email.resendIn %lld`):

```bash
python3 -c "
import json
s = json.load(open('shellx-ios/ShellX/Localizable.xcstrings'))['strings']
for k in sorted(k for k in s if k.startswith(('signin.email', 'signin.error.')) or k == 'settings.account.method.email'):
    l = s[k]['localizations']
    print(repr(k), '|', l['en']['stringUnit']['value'], '|', l['vi']['stringUnit']['value'])"
```

- [ ] **Step 2: Write the failing tests.** `core_api.rs`:

```rust
#[test] fn email_calls_send_their_params_and_parse() {
    // email_begin(&f, "Foo@Bar.com", "vi") sends ("auth.email.begin", {"email":"Foo@Bar.com","locale":"vi"}) and parses
    // {"challenge_id":"c1","expires_in":600,"resend_in":60,"email":"foo@bar.com"};
    // email_finish(&f, "c1", "004217") sends ("auth.email.finish", {"challenge_id":"c1","code":"004217"}) and parses
    // email "foo@bar.com", auth_method "email"; a provider "email" item of list_sign_in_methods is_email() and not is_apple()
}
#[test] fn email_values_hide_addresses_and_challenges_in_debug() {
    // format!("{:?}", EmailChallenge { challenge_id: "CH-SECRET", email: "foo@bar.com", .. }) contains neither
}
```

`strings.rs`: in `sign_in_strings_match_the_mac` the `EmailAddress` en line becomes `"Email address"` (its 20 pairs stay); `all_has_no_duplicates` becomes `assert_eq!(Str::ALL.len(), 124)`; add

```rust
#[test] fn email_strings_match_the_phone_catalog() {
    // pairs (Str, vi, en) for the 15 new variants, exactly the String table; assert_eq!(pairs.len(), 15); each t() equals its value
    assert_eq!(sent_code_to(Lang::En, "foo@bar.com"), "We sent a 6-digit code to foo@bar.com. If it isn't there in a minute, check your spam folder.");
    assert_eq!(sent_code_to(Lang::Vi, "foo@bar.com"), "Đã gửi mã 6 chữ số tới foo@bar.com. Nếu sau một phút chưa thấy, hãy xem cả thư rác.");
    assert_eq!(resend_code_in(Lang::En, 42), "Resend code in 42 s");
    assert_eq!(resend_code_in(Lang::Vi, 60), "Gửi lại mã sau 60 giây");
    assert_eq!((Lang::Vi.locale(), Lang::En.locale()), ("vi", "en"));
}
#[test] fn email_error_maps_codes() {
    // for both languages: invalid_email -> InvalidEmail, disposable_email -> DisposableEmail, invalid_code -> InvalidCode,
    // code_expired -> CodeExpired, email_send_failed -> EmailSendFailed, email_sign_in_disabled -> SignInUnavailable,
    // rate_limited -> RateLimited, network -> RelayUnreachable, switch_from_signed_in_device -> SwitchFromSignedInDevice;
    // "http_502", "http_503", "http_504", "server", "invalid_device", "" -> ServerProblem;
    // google_error(lang, "rate_limited") is still Some(login_failed(lang, "rate_limited"))
}
#[test] fn sign_in_method_labels_follow_the_provider() {
    // "apple" -> AppleId, "email" -> EmailCodeMethod, "google" and "test" -> GoogleAccount
}
```

`email_sign_in.rs` (a `#[cfg(test)] mod tests` written before the functions exist):

```rust
#[test] fn plausible_addresses() {
    // true: "a@b.c", " a@b.co ", "phu@example.com\u{00A0}" (str::trim drops U+00A0);
    // false: "", "a@b", "a@.c", "a@b.", "@b.c", "a b@c.d", "phu@ẽample.com", "phú@example.com", "phu@example.cóm",
    //        "phu@\u{FF45}xample.com", format!("{}@b.co", "a".repeat(250)) (255 bytes)
}
#[test] fn refused_text_shows_the_invalid_email_sentence() {
    // email_text_refused true: "phu@ẽample.com", "ẽ", "phu@\u{FF45}xample.com", the 255-byte address;
    // false: "", "phu@exam", "a@b.co", "phu@example.com\u{00A0}"
}
#[test] fn code_digits_takes_the_six_digits_of_what_was_typed() {
    // Some("123456"): " 123 456\n", "１２３４５６", "١٢٣٤٥٦", "Your ShellX sign-in code is 123456";
    // Some("004217"): "004217", "Mã đăng nhập ShellX của bạn là 004217";
    // None: "12345", "1234567", "12a45", "", "12345²", "Your code is 004217. It works for 10 minutes."
}
#[test] fn auto_submit_fires_once_per_new_six_digits() {
    // auto_submit(None, "123 456", true) == Some("123456"); auto_submit(Some("123456"), "123456", true) == None;
    // auto_submit(Some("123456"), "654321", true) == Some("654321"); auto_submit(None, "123456", false) == None;
    // auto_submit(None, "12345", true) == None; auto_submit(None, "１２３４５６", true) == Some("123456")
}
#[test] fn the_dialog_screen_follows_the_steps() {
    // (None, false, false, false, false) -> Start { sending: false, google_waiting: false };
    // (None, false, true, false, true) -> Start { sending: false, google_waiting: true };
    // (None, false, false, true, true) -> SigningIn; (None, false, false, false, true) -> Start { false, false };
    // (Some(Email), false, false, false, false) -> Start { false, false };
    // (Some(Sending), false, ..) -> Start { sending: true, google_waiting: false }; (Some(Sending), true, ..) -> Code { busy: true };
    // (Some(Code), true, ..) -> Code { busy: false }; (Some(Verifying), true, ..) -> Code { busy: true }
}
#[test] fn tab_follows_the_dialog_order() {
    // tab_order(Start { false, false }) == [EmailField, SendCode, Google, Cancel]; all accepted:
    //   EmailField -> SendCode -> Google -> Cancel -> EmailField; back from EmailField -> Cancel;
    //   SendCode refused: EmailField -> Google, back from Google -> EmailField;
    // tab_order(Code { busy: false }) == [CodeField, Verify, Resend, ChangeEmail, Cancel]; Verify and Resend refused:
    //   CodeField -> ChangeEmail; tab_order(SigningIn) == [Cancel], from Cancel -> Cancel;
    // on the Start order, from Verify (not in it) -> EmailField
}
```

- [ ] **Step 3: Run to verify they fail.** Run: `(cd windows && cargo test --locked -p shellx-model)`. Expected: compile errors (`email_begin`, `Str::ServerProblem`, `code_digits`, `tab_order` missing).
- [ ] **Step 4: Commit the failing tests** (the `mod tests` edits and the test-only `email_sign_in.rs` with its `lib.rs` line). `git add windows/shellx-model/src && git commit -m "test(shellx-windows): email code core calls, strings and input rules"`
- [ ] **Step 5: Implement** the Interfaces.
- [ ] **Step 6: Run to verify they pass.** Run: `(cd windows && cargo test --locked -p shellx-model)`. Expected: `test result: ok` (192 plus the new tests), no new compiler warning.
- [ ] **Step 7: Commit.** `git add windows/shellx-model/src && git commit -m "feat(shellx-windows): email code core calls, strings and input rules"`

---

### Task 2: Model: the email steps in the account flow

The flow and the two `run_account_action` arms land together: `run_account_action` matches every `AccountAction` with no wildcard (`core_service.rs:145-193`), so new actions without their arms would leave `shellx-app` unbuildable between commits. `ui/account.rs:255-282` sends unknown actions to the serial worker through its catch-all and needs no change here. The arms cannot be compiled on this Mac before Task 0; Task 3 compiles them first.

**Files:**
- Modify: `windows/shellx-model/src/account.rs` (`AccountEvent` :36-81, `AccountAction` :83-105, both `Debug` impls :107-191, `AccountFlow` :201-265, accessors after :331, `reset_session` :369-383, entering `LoggedIn` :413-434, `GoogleRequested` :574-593, tests :722+)
- Modify: `windows/shellx-app/src/core_service.rs` (imports :19-24, `run_account_action` :140-194)

**Interfaces:**
- Consumes: Task 1 (`EmailStep`, `EmailChallenge`, `GoogleSignIn`, `email_looks_valid`, `code_digits`, `email_begin`, `email_finish`).
- Produces:

```rust
// AccountEvent gains (eight)
EmailCodeRequested { email: String, locale: String },     // "Send code": the typed address, "vi" | "en"; starts the run
EmailEdited,                                              // the email field's text changed; no payload, Debug "EmailEdited"
EmailResendRequested,                                     // "Resend code": the same address and language
EmailBegun(Result<EmailChallenge, CoreErr>),              // result of CallEmailBegin
EmailCodeSubmitted(String),                               // Verify, Enter or six digits typed: the code field's text
EmailFinished { challenge_id: String, result: Result<GoogleSignIn, CoreErr> },   // result of CallEmailFinish
EmailChangeRequested,                                     // "Use a different email"
EmailCancelled,                                           // the dialog closed (Cancel, Escape)
// AccountAction gains
CallEmailBegin { email: String, locale: String },
CallEmailFinish { challenge_id: String, code: String },
// AccountFlow
pub fn email_step(&self) -> Option<EmailStep>;            // None with no run, or once the dialog closed a run that is verifying
pub fn email_sent_to(&self) -> Option<&str>;              // the relay's address for the code sent in this run
pub fn email_error(&self) -> Option<&CoreErr>;
pub fn email_can_verify(&self) -> bool;                   // step Code with a live challenge
pub fn email_resend_wait_secs(&self, now_ms: u64) -> u64; // rounded up; 0 = "Resend code" can be pressed
/// Moves by one whenever the dialog must empty the code field: a new challenge, `invalid_code`, or a dropped
/// challenge (`code_expired`, `switch_from_signed_in_device`, a Resend that lost it).
pub fn email_code_epoch(&self) -> u64;
// core_service.rs run_account_action (both on the serial worker):
//   CallEmailBegin { email, locale }      -> Some(EmailBegun(email_begin(core, &email, &locale)))
//   CallEmailFinish { challenge_id, code } -> Some(EmailFinished { challenge_id, result: email_finish(..) })
```

Rules (each pinned by a test below):
- `EmailCodeRequested`: only with no Google flow, `accepts_login()`, not `LoggedIn`, no run or a run at `Email`, and `email_looks_valid(&email)` → a run at `Sending` (a run at `Email` is replaced, its error with it) and `[CallEmailBegin { email: <trimmed>, locale }]`; the run remembers both.
- `EmailEdited`: at `Email` → the run's error cleared; at any other step, or with no run, nothing changes. Always `[]`.
- `EmailResendRequested`: only at `Code` with `email_resend_wait_secs(now_ms) == 0` → `Sending`, error cleared, `[CallEmailBegin { .. }]` with the remembered address and language.
- `EmailBegun`: while a cancelled request's answer is still owed (counter `stale_email_begins`) → count down and ignore; not at `Sending` → ignore. `Ok(c)` → `Code`, challenge `c.challenge_id`, `sent_to = c.email`, lock until `now_ms + c.resend_in * 1000`, epoch + 1. `Err(e)` on a Resend (a code was already sent in this run) → `Code`, `error = e`, lock ended; for `email_send_failed` and `email_sign_in_disabled` the challenge is dropped (epoch + 1), for any other code it stays. `Err(e)` on the first send → `Email`, `error = e`.
- `EmailCodeSubmitted(text)`: only at `Code` with a live challenge, `code_digits(&text)` `Some` and `accepts_login()` → `Verifying`, error cleared, then the state changes of `GoogleRequested(SignIn)` (`LoggingIn`, `login_in_flight`, `retry_list` off, notice cleared) and `[CallEmailFinish { challenge_id, code: <the digits> }]`.
- `EmailFinished`: ignored unless the run is at `Verifying` (shown or hidden) with that `challenge_id`. `Ok(info)` → the run is dropped, email and auth method stored, then exactly what `GoogleFinished` does for `SignIn` (`[CallList]`). `Err(e)` → `login_in_flight` off and state `LoggedOut`; a run the dialog closed is dropped; otherwise `error = e` and: `invalid_code` → `Code`, challenge kept, epoch + 1; `code_expired` → `Code`, challenge dropped, lock ended, epoch + 1; `switch_from_signed_in_device` → `Email`, challenge and `sent_to` dropped, lock ended, epoch + 1; any other code (`email_sign_in_disabled`, `rate_limited`, `network`, `http_<status>`, `invalid_device`, …) → `Code`, challenge and lock kept, epoch unchanged (so the dialog keeps the digits).
- `EmailChangeRequested`: only at `Code` → `Email`; challenge, `sent_to`, error and lock dropped.
- `EmailCancelled`: at `Email` or `Code` → the run is dropped; at `Sending` → dropped, and its answer is owed; at `Verifying` → hidden (`email_step()` is `None`) until `EmailFinished`.
- `GoogleRequested(SignIn)`: refused while a run is `Sending`, `Code` or `Verifying` (shown or hidden); otherwise as today, after dropping a run at `Email`.
- `reset_session()` does not touch the email run; a `ListResult` that enters `LoggedIn` drops it.
- `Debug` prints `"<redacted>"` for the address, the code and the `challenge_id` in the new events and actions; the run's `Debug` (inside `AccountFlow`'s) shows its step only.

D2's rows and the tests that pin them:

| D2 row | Test |
| --- | --- |
| 401 `invalid_code` on verify | `a_wrong_code_empties_the_field_and_stays_on_the_code_step` |
| 410 `code_expired` on verify | `an_expired_code_drops_the_challenge_and_unlocks_resend` |
| 409 `switch_from_signed_in_device` on verify | `a_switch_answer_returns_to_the_first_screen` |
| failed Resend, `rate_limited` or `network` | `a_failed_resend_keeps_the_challenge_for_rate_limited_and_network`; Task 3 `a_rate_limited_resend_through_the_real_core_keeps_the_code` |
| failed Resend, `email_send_failed`, `email_sign_in_disabled`, 404 | `a_failed_resend_drops_the_challenge_the_relay_lost`; Task 3 `a_failed_resend_through_the_real_core_drops_the_challenge` |
| 429 on Send code or Resend | `a_failed_send_returns_to_the_first_screen_with_the_error`; the second Resend of `a_failed_resend_keeps_…` |
| body-less 502 / 503 / 504, no sentence | Task 1 `email_error_maps_codes`; `http_503` in `a_failed_send_returns_…` |
| 429, network, body-less 5xx or `invalid_device` on verify (rows 6 and 7 on the verify side) | `a_verify_refused_for_rate_network_or_server_keeps_the_code` |
| 503 `email_sign_in_disabled`, 404 | `a_relay_without_email_sign_in_keeps_the_app_signed_out`; `a_disabled_relay_on_verify_keeps_the_code`; Task 1 `email_error_maps_codes`; Task 3 `a_relay_without_email_sign_in_answers_through_the_real_core` |

- [ ] **Step 1: Write the failing tests** (in `account.rs` tests; reuse `m`, `net`, `logged_in`, `logged_out`, `google_done`; the existing `finished` builds `GoogleFinished`, so the email helper is `email_finished`). "Epoch moved" means `email_code_epoch()` is one more than before the event; "unchanged" means equal.

```rust
// challenge(id) = EmailChallenge { challenge_id: id.into(), email: "foo@bar.com".into(), expires_in: 600, resend_in: 60 }
// done() = google_done("foo@bar.com", "email"); email_finished(id, r) = EmailFinished { challenge_id: id.into(), result: r }
// err(code) = CoreErr::new(code, "x"); send() = EmailCodeRequested { email: " Foo@Bar.com ".into(), locale: "vi".into() }
// to_code(f, now): send(); EmailBegun(Ok(challenge("c1"))), both at `now`
#[test] fn email_sign_in_runs_email_code_verify_then_lists() {
    // logged_out(); send() -> [CallEmailBegin { email: "Foo@Bar.com", locale: "vi" }], Some(Sending), state LoggedOut;
    // EmailBegun(Ok(challenge("c1"))) -> [], Some(Code), email_sent_to() == Some("foo@bar.com"), email_can_verify(), epoch 1;
    // EmailCodeSubmitted(" 123 456\n") -> [CallEmailFinish { challenge_id: "c1", code: "123456" }], Some(Verifying),
    // state LoggingIn, login_in_flight(); email_finished("c1", Ok(done())) -> [CallList], email_step() None;
    // ListResult(Ok([m("me", true)])) -> LoggedIn, no CallSession; email() == Some("foo@bar.com"),
    // auth_method() == Some("email"), !needs_google_switch()
}
#[test] fn send_code_needs_a_plausible_ascii_address_and_runs_once() { /* "nope" -> [], "phu@ẽample.com" -> [], email_step() None; a valid one -> one CallEmailBegin; again while Sending -> [] */ }
#[test] fn editing_the_address_clears_the_email_failure() { /* send(); EmailBegun(Err(err("rate_limited"))) -> Some(Email), that error; EmailEdited -> [], email_error() None, still Some(Email); a fresh logged_out(): EmailEdited -> [], email_step() None; new flow: to_code at 1_000; resend at 61_000; EmailBegun(Err(err("rate_limited"))); EmailEdited -> [], email_error() still rate_limited, Some(Code) */ }
#[test] fn a_failed_send_returns_to_the_first_screen_with_the_error() { /* for invalid_email, disposable_email, rate_limited, email_send_failed, network, http_503: send(); EmailBegun(Err(err(code))) -> Some(Email), email_error() code == code, state LoggedOut, !email_can_verify(); send() again -> [CallEmailBegin] at once, email_error() None */ }
#[test] fn a_relay_without_email_sign_in_keeps_the_app_signed_out() { /* EmailBegun(Err(err("email_sign_in_disabled"))) -> Some(Email), that error, state LoggedOut, notice() None */ }
#[test] fn a_wrong_code_empties_the_field_and_stays_on_the_code_step() { /* to_code; submit; email_finished("c1", Err(err("invalid_code"))) -> Some(Code), email_error() invalid_code, email_can_verify(), epoch moved, state LoggedOut, !login_in_flight(); a new submit -> CallEmailFinish with "c1" */ }
#[test] fn an_expired_code_drops_the_challenge_and_unlocks_resend() { /* Err(code_expired) at 5_000 -> Some(Code), !email_can_verify(), email_resend_wait_secs(5_000) == 0, epoch moved; EmailCodeSubmitted("123456") -> []; EmailResendRequested -> [CallEmailBegin { email: "Foo@Bar.com", locale: "vi" }] */ }
#[test] fn a_switch_answer_returns_to_the_first_screen() { /* Err(switch_from_signed_in_device) at 5_000 -> Some(Email), email_error() that code, email_sent_to() None, !email_can_verify(), email_resend_wait_secs(5_000) == 0, epoch moved, state LoggedOut; send() -> [CallEmailBegin] */ }
#[test] fn a_disabled_relay_on_verify_keeps_the_code() { /* to_code at 1_000; submit "123456" at 2_000; email_finished("c1", Err(err("email_sign_in_disabled"))) -> Some(Code), email_error() code "email_sign_in_disabled", email_can_verify(), email_resend_wait_secs(2_000) == 59, epoch unchanged, state LoggedOut; EmailCodeSubmitted("123456") -> [CallEmailFinish { challenge_id: "c1", code: "123456" }] */ }
#[test] fn a_verify_refused_for_rate_network_or_server_keeps_the_code() { /* for rate_limited, network, http_503, invalid_device: to_code at 1_000; EmailCodeSubmitted("123456") at 2_000; email_finished("c1", Err(err(code))) -> Some(Code), email_error() code == code, email_can_verify(), email_resend_wait_secs(2_000) == 59, epoch unchanged, state LoggedOut, !login_in_flight(); EmailCodeSubmitted("123456") again -> [CallEmailFinish { challenge_id: "c1", code: "123456" }] */ }
#[test] fn verify_runs_once_for_a_double_submit() { /* two EmailCodeSubmitted("123456"): the second is []; at Code, "12345" and "1234567" -> [] */ }
#[test] fn resend_is_locked_for_the_relays_resend_in() { /* to_code at 1_000: wait(1_000) == 60, wait(1_500) == 60, wait(60_200) == 1, wait(61_000) == 0; EmailResendRequested at 30_000 -> []; at 61_000 -> [CallEmailBegin], Some(Sending), email_sent_to() still Some; EmailBegun(Ok(challenge("c2"))) at 62_000 -> wait(62_000) == 60, epoch moved, and a submit sends challenge "c2" */ }
#[test] fn a_failed_resend_keeps_the_challenge_for_rate_limited_and_network() { /* for rate_limited, network, http_503: to_code at 1_000; resend at 61_000; EmailBegun(Err(err(code))) -> Some(Code), that error, wait(61_000) == 0, email_can_verify(), epoch unchanged; another EmailResendRequested at 61_000 -> [CallEmailBegin { email: "Foo@Bar.com", locale: "vi" }]; EmailBegun(Err(err(code))) again -> Some(Code), email_can_verify(); last, EmailCodeSubmitted("123456") -> [CallEmailFinish { challenge_id: "c1", code: "123456" }] (a Resend at Verifying is refused, so the submit comes last) */ }
#[test] fn a_failed_resend_drops_the_challenge_the_relay_lost() { /* for email_send_failed, email_sign_in_disabled: to_code at 1_000; resend at 61_000; EmailBegun(Err(err(code))) -> Some(Code), that error, !email_can_verify(), wait 0, epoch moved, email_sent_to() still Some("foo@bar.com"); EmailCodeSubmitted("123456") -> []; EmailResendRequested -> [CallEmailBegin] */ }
#[test] fn use_a_different_email_returns_to_the_first_screen() { /* EmailChangeRequested -> Some(Email), email_sent_to() None, email_error() None, !email_can_verify(); at Verifying it changes nothing; send() -> [CallEmailBegin] */ }
#[test] fn closing_while_sending_ignores_the_late_challenge() { /* send(); EmailCancelled -> email_step() None; send() again -> [CallEmailBegin], Some(Sending); EmailBegun(Ok(challenge("c1"))) -> [], still Sending; EmailBegun(Ok(challenge("c2"))) -> Some(Code); a submit sends "c2" */ }
#[test] fn closing_while_verifying_still_signs_in_when_the_code_was_right() { /* EmailCancelled at Verifying -> email_step() None, state LoggingIn; send() -> []; GoogleRequested(SignIn) -> []; email_finished("c1", Ok(done())) -> [CallList], email() Some */ }
#[test] fn closing_while_verifying_a_wrong_code_ends_signed_out_without_an_error() { /* ... email_finished("c1", Err(invalid_code)) -> state LoggedOut, email_step() None, email_error() None; send() -> [CallEmailBegin] */ }
#[test] fn reopening_after_a_close_starts_clean() { /* to_code; EmailCancelled -> email_step() None, email_sent_to() None, email_error() None, !email_can_verify(); send() -> Some(Sending) */ }
#[test] fn a_late_list_result_does_not_reset_the_email_step() { /* new flow: Started (state Unknown); to_code; ListResult(Err(not_logged_in)) -> state LoggedOut, email_step() == Some(Code), email_can_verify() */ }
#[test] fn email_and_google_share_the_first_screen() { /* send(); GoogleRequested(SignIn) at Sending -> []; EmailBegun(Ok(challenge("c1"))); GoogleRequested(SignIn) at Code -> []; new flow: send(); EmailBegun(Err(invalid_email)) -> Some(Email); GoogleRequested(SignIn) -> [CallGoogleBegin(SignIn)], email_step() None, email_error() None; with that Google flow waiting send() -> []; logged_in(): send() -> [] */ }
#[test] fn a_stale_email_finish_is_ignored() { /* at Verifying "c1": email_finished("c0", Ok(done())) -> [], still Verifying; at Code: email_finished("c1", Ok(done())) -> [] */ }
#[test] fn an_email_session_ended_by_the_server_asks_for_sign_in_again() { /* the walk-through to LoggedIn; ListResult(Err(err("unauthorized"))) -> LoggedOut, take_signed_out_by_server(), auth_method() None */ }
#[test] fn email_codes_addresses_and_challenges_never_in_debug() { /* with challenge id "CH-SECRET": Debug of send(), EmailBegun(Ok(..)), EmailCodeSubmitted("123456"), EmailFinished Ok, CallEmailBegin, CallEmailFinish and of the flow on the code step contains none of "foo@bar.com", "Foo@Bar.com", "123456", "CH-SECRET" */ }
```

- [ ] **Step 2: Run to verify they fail.** Run: `(cd windows && cargo test --locked -p shellx-model account::)`. Expected: compile errors (`EmailCodeRequested` missing).
- [ ] **Step 3: Commit the failing tests.** `git add windows/shellx-model/src/account.rs && git commit -m "test(shellx-windows): account flow email code steps"`
- [ ] **Step 4: Implement** the rules in `account.rs` and the two `run_account_action` arms in `core_service.rs` (imports `email_begin`, `email_finish`).
- [ ] **Step 5: Run to verify they pass.** Run: `(cd windows && cargo test --locked -p shellx-model)`. Expected: `test result: ok`, every existing `account::tests` included; no new compiler warning. `shellx-app` is not compiled here (it needs Task 0).
- [ ] **Step 6: Commit.** `git add windows/shellx-model/src/account.rs windows/shellx-app/src/core_service.rs && git commit -m "feat(shellx-windows): account flow signs in with an email code"`

---

## Stage 2: needs Task 0 and Plan A on `develop`

### Task 3: The email calls through the real core

**Files:**
- Modify: `windows/shellx-app/src/core_service.rs` (tests after :535)

**Interfaces:**
- Consumes: Task 2's events, actions and accessors; Plan A's fake API, as its "Interfaces for Plan B" names it (the names as landed win; Step 1 prints them):
  - `FakeOptions.email_sign_in: bool` (false: `/code` answers 503 `email_sign_in_disabled`) and `FakeOptions.email_routes: bool` (false: both routes answer 404, an old relay), both default true;
  - `FakeApi::email_code(&self, email: &str) -> Option<String>`: the live code mailed to that address;
  - `FakeApi::email_locale(&self, email: &str) -> Option<String>`: that mail's language, `"vi"` only for exactly `vi`;
  - `FakeApi::set_next_email_code(&self, code: &str)`: the next challenge's code, once;
  - `FakeApi::fail_next_mail(&self)`: the relay's 502 `email_send_failed`, which leaves the address with no live code;
  - `FakeApi::fail_next(&self, path: &str, status: u16, code: &str)`: one scripted answer that changes no challenge (the relay's 429).
- Produces: nothing new for later tasks.

- [ ] **Step 1: Prerequisites.**
  1. Plan A landed: `git -C /Users/richard/Documents/helper/shellx grep -n '"auth.email.finish"' develop -- shellx-core/src/lib.rs`. Expected: one match in `KNOWN_METHODS`. No match: stop and report; Stage 2 cannot start.
  2. If this branch was cut before Plan A landed: `git merge --no-edit develop` (never a rebase or a force-push).
  3. Task 0 reported success. Pick the ghostty source `<ghostty>`: when `git ls-tree HEAD ghostty` names the commit that `git -C /Users/richard/Documents/helper/shellx/.worktrees/email-code-signin-windows-t0/ghostty rev-parse HEAD` prints, `<ghostty>` is `/Users/richard/Documents/helper/shellx/.worktrees/email-code-signin-windows-t0/ghostty`; otherwise run `git submodule update --init --depth 1 ghostty` here, and `<ghostty>` is `/Users/richard/Documents/helper/shellx/.worktrees/email-code-signin-windows/ghostty`. `<zig bin>` is the directory of the zig that Task 0 Step 5 reported. Fill both in once; the result is **the Stage 2 line**:

     ```bash
     export PATH="<zig bin>:$HOME/.cargo/bin:$PATH" CMUX_GHOSTTY_SRC="<ghostty>"
     ```

     Agent shells keep no variables between commands, so every later shell that builds or tests `shellx-app` (Steps 1.5, 3 and 4 here, Task 4 Step 2, Task 5 Step 1) starts with this line, unchanged. Without it, `ghostty-vt-sys`'s build script falls back to this worktree's empty `ghostty` directory and its zig build fails (`cmux-tui/crates/ghostty-vt-sys/build.rs:11-14`, `:42-71`); it also re-runs whenever `CMUX_GHOSTTY_SRC` changes (`:25`), so a shell without the line undoes a good build.
  4. The fake's names: `grep -n 'pub fn \|pub email_sign_in\|pub email_routes' shellx-core/fake-api/src/lib.rs`. Expected: the names under Consumes above. Where a name differs, use the landed one and note it for the hand-off.
  5. First build here, in one shell: the Stage 2 line, then `(cd windows && cargo build --release --locked -p shellx-app)` (cold in this worktree: about 5–10 min). Expected: it finishes; a compile error in Task 2's arms is fixed here in its own commit `fix(shellx-windows): …`.
- [ ] **Step 2: Write the tests** (`drive`, `cfg`, `facts` exist):

```rust
/// Email sign-in through the real shellx-core against the fake API (the fake's mailbox stands for the email).
#[test] fn email_session_against_fake_api() {
    // FakeApi::start(default); ConfiguredCore over CoreBridge; drive Started -> LoggedOut;
    // api.set_next_email_code("004217"), so the leading zeros go through the real core;
    // drive EmailCodeRequested { email: " Foo@Bar.com ", locale: "vi" } ->
    //   ran == ["CallEmailBegin { email: \"<redacted>\", locale: \"vi\" }"], email_step() == Some(Code), email_sent_to() == Some("foo@bar.com");
    //   api.email_code("foo@bar.com").as_deref() == Some("004217"); api.email_locale("foo@bar.com").as_deref() == Some("vi") (D1's exact `vi`);
    // drive EmailCodeSubmitted("000000") -> one entry starting "CallEmailFinish {" that contains neither "000000" nor "004217";
    //   state LoggedOut; email_error() code "invalid_code"; email_step() == Some(Code);
    // drive EmailCodeSubmitted("004 217\n") -> ran[1..] == ["CallList", "CallRegister", "CallList"];
    //   LoggedIn; email() == Some("foo@bar.com"); auth_method() == Some("email"); !needs_google_switch(); email_step() None;
    // drive SignInMethodsRequested -> sign_in_methods() has one item with provider "email"
}
#[test] fn a_relay_without_email_sign_in_answers_through_the_real_core() {
    // for FakeOptions { email_sign_in: false, ..Default::default() } (503) and FakeOptions { email_routes: false, ..Default::default() }
    // (an old relay's 404): Started; EmailCodeRequested { "foo@bar.com", "en" } ->
    // email_error() code "email_sign_in_disabled", email_step() == Some(Email), state LoggedOut
}
#[test] fn a_failed_resend_through_the_real_core_drops_the_challenge() {
    // default fake: Started at 0; EmailCodeRequested { "foo@bar.com", "en" } at 1 -> Some(Code);
    // api.fail_next_mail(); drive EmailResendRequested at 61_000 ->
    // ran == ["CallEmailBegin { email: \"<redacted>\", locale: \"en\" }"], email_step() == Some(Code), !email_can_verify(),
    // email_error() code "email_send_failed", email_resend_wait_secs(61_000) == 0;
    // api.email_code("foo@bar.com") == None (the relay holds no live code either)
}
#[test] fn a_rate_limited_resend_through_the_real_core_keeps_the_code() {
    // default fake: Started at 0; EmailCodeRequested { "foo@bar.com", "en" } at 1 -> Some(Code); first = api.email_code("foo@bar.com").unwrap();
    // api.fail_next("/v1/auth/email/code", 429, "rate_limited"); drive EmailResendRequested at 61_000 ->
    // email_step() == Some(Code), email_error() code "rate_limited", email_can_verify(), email_resend_wait_secs(61_000) == 0,
    // api.email_code("foo@bar.com") == Some(first); drive EmailCodeSubmitted(first) -> LoggedIn, auth_method() == Some("email")
}
```

- [ ] **Step 3: Run them.** Run, in one shell: the Stage 2 line, then `(cd windows && cargo test --release --locked -p shellx-app core_service::)`. Expected: the four new tests pass at the first run, since they drive code Task 2 committed after its red run; a failure here is a bug: commit the failing test first, then the fix.
- [ ] **Step 4: Run both suites.** Run, in one shell: the Stage 2 line, then `(cd windows && cargo test --release --locked -p shellx-app && cargo test --locked -p shellx-model)`. Expected: `test result: ok` for both, including `account_session_against_fake_api`, `google_session_against_fake_api` and `smoke_account_flow`.
- [ ] **Step 5: Commit.** `git add windows/shellx-app/src/core_service.rs && git commit -m "test(shellx-windows): email sign-in through the real core"`

---

### Task 4: App: the email-first dialog, Settings label, previews, docs

**Files:**
- Modify: `windows/shellx-app/src/ui/text_field.rs` (after `set_disabled` :80-86)
- Modify: `windows/shellx-app/src/ui/account.rs` (module comment :8-11, after `cancel_google` :161-164)
- Modify: `windows/shellx-app/src/ui/login.rs` (the whole dialog, module comment :1-12)
- Modify: `windows/shellx-app/src/ui/mod.rs:18-20` (`text_field` is used again: drop its comment and `#[allow(dead_code)]`; put the attribute back only if the build then warns)
- Modify: `windows/shellx-app/src/ui/settings.rs:238-242` (the row title)
- Modify: `windows/shellx-app/src/ui/root.rs` (end of `RootView::new` :214-215)
- Modify: `windows/README.md` ("Run the window on a Mac", "Remote view (Macs)"), `windows/G1-G3-CHECKLIST.md` ("Đăng nhập và ghép cặp" :45-48)

**Interfaces:**
- Consumes: Task 1 (`sign_in_screen`, `SignInScreen`, `DialogFocus`, `tab_order`, `tab_target`, `auto_submit`, `code_digits`, `email_looks_valid`, `email_text_refused`, `email_error`, `sent_code_to`, `resend_code_in`, `sign_in_method_label`, `Lang::locale`), Task 2 (the flow's events and accessors), `TextField` / `TextFieldEvent`, `button`, `google_button`.
- Produces:

```rust
// ui/text_field.rs
pub fn composing(&self) -> bool;   // an IME composition is open: self.edit.marked_range().is_some()
#[cfg(target_os = "macos")] pub fn dev_set_text(&mut self, text: &str, cx: &mut Context<Self>);   // previews only
// ui/account.rs AccountService: one method per flow event, one per accessor
pub fn email_send_code(&mut self, email: String, locale: &'static str, cx: &mut Context<Self>);  // EmailCodeRequested
pub fn email_edited(&mut self, cx: &mut Context<Self>);                                          // EmailEdited
pub fn email_resend(&mut self, cx: &mut Context<Self>);                                          // EmailResendRequested
pub fn email_submit_code(&mut self, code: String, cx: &mut Context<Self>);                       // EmailCodeSubmitted
pub fn email_change(&mut self, cx: &mut Context<Self>);                                          // EmailChangeRequested
pub fn email_cancel(&mut self, cx: &mut Context<Self>);                                          // EmailCancelled
pub fn email_step(&self) -> Option<EmailStep>;
pub fn email_sent_to(&self) -> Option<&str>;
pub fn email_error(&self) -> Option<&CoreErr>;
pub fn email_can_verify(&self) -> bool;
pub fn email_resend_wait_secs(&self) -> u64;      // at this service's clock (`now_ms`)
pub fn email_code_epoch(&self) -> u64;
pub fn signing_in(&self) -> bool;                 // state() is LoggingIn
/// Mac development build only (screenshots): "code" puts the flow on the code step with a made-up challenge for
/// "you@example.com" (resend_in 60); "switch" goes on to EmailCodeSubmitted("123456") and a 409
/// (`switch_from_signed_in_device`). It feeds the flow directly and drops the returned actions, so no core call is
/// made; any other value does nothing.
#[cfg(target_os = "macos")] pub fn dev_preview_email(&mut self, preview: &str, cx: &mut Context<Self>);
// ui/login.rs SignInDialog gains
email_field: Entity<TextField>,        // TextField::new(false, t(lang, Str::EmailAddress), cx)
code_field: Entity<TextField>,         // TextField::new(false, t(lang, Str::CodePlaceholder), cx)
last_auto: Option<String>,             // the digits last submitted without a click
code_submitted: bool,                  // this dialog submitted a code since it opened
code_epoch_seen: u64,                  // the email_code_epoch() the code field matches
email_text_seen: String,               // the email field's text when the dialog last looked: tells an edit from a click or cursor move
shown: SignInScreen,                   // the screen drawn last
focused: DialogFocus,                  // what holds the keyboard (SignIn only)
// plus one FocusHandle per focusable button (cx.focus_handle())
/// Mac development build only: fills the email field for the `invalid` and `switch` previews, and sets
/// `email_text_seen` to the same text, so the fill sends no `EmailEdited` (the `switch` preview keeps its sentence).
#[cfg(target_os = "macos")] pub fn dev_fill_email(&mut self, text: &str, cx: &mut Context<Self>);
// ui/root.rs
/// Mac development build only: `SHELLX_DEV_SIGN_IN=start|code|invalid|switch` opens the sign-in dialog on that screen.
#[cfg(target_os = "macos")] fn dev_sign_in_preview(&mut self, window: &mut Window, cx: &mut Context<Self>);
```

Dialog rules. `GooglePurpose::Link` is unchanged. For `SignIn` the screen is `sign_in_screen(account.email_step(), account.email_sent_to().is_some(), account.google_in_flight().is_some(), self.code_submitted, account.signing_in())`; `composing` is the field's `composing()`; `started` (today's flag) means this dialog started Google.
- `Start { sending, google_waiting }`, top to bottom: the title; `email_field` (disabled while `sending`); the email line: nothing while Google's error line (below) shows (D3: one failure at a time), else `account.email_error()` worded by `email_error`, else `t(lang, InvalidEmail)` while `!composing && email_text_refused(text)`; `button("sign-in-send-code", SendCode, Kind::Primary, sending || google_waiting || !account.accepts_login() || composing || !email_looks_valid(text))`, as wide as the field, calling `email_send_code(text.trim().to_string(), lang.locale(), cx)` and clearing `started`; a centred muted `OrDivider`; the Google button as today (its handler off and drawn at reduced opacity while `sending`; "Waiting for Google…" and the hint while `google_waiting`); Google's error line under it, today's rule (`started && !google_waiting`); Cancel, right-aligned.
- `Code { busy }`: a wrapping `text_hi` block `sent_code_to(lang, address)`; `code_field` (disabled while `busy || !account.email_can_verify()`); the error line `email_error(lang, code)`; `button("sign-in-verify", VerifyCode, Kind::Primary, busy || composing || !account.email_can_verify() || code_digits(text).is_none())`, as wide as the field, calling `email_submit_code(text, cx)` and setting `code_submitted`; on its own line `button("sign-in-resend", <label>, Kind::Secondary, busy || composing || wait > 0)` (label `resend_code_in(lang, wait)` while `wait = account.email_resend_wait_secs()` is above 0, else `ResendCode`); on its own line `button("sign-in-change-email", UseDifferentEmail, Kind::Secondary, busy || composing)`; Cancel.
- `SigningIn`: one `text_hi` line `Str::SigningIn`; Cancel.
- Click handlers are attached only to enabled buttons (`button` leaves `on_click` to the caller, `ui/button.rs:16`).
- Keys: `Submit` from the email field runs Send code, from the code field runs Verify, each only when its button is enabled; `Cancel` from either field closes. `Next` / `Prev` from a field, and Tab / Shift+Tab on a focused button, move the keyboard to `tab_target(tab_order(screen), from, back, enabled)`, where `from` is the control that holds the keyboard and `enabled` is the drawn state (a field: not disabled; Cancel: always). On a focused button Enter or Space presses it when enabled and Escape closes. Each handled key stops propagation. A focused button draws a 2 px `palette::PRIMARY_LINE` border (the focused text field's colour). On the dialog's own handle (it may take the keyboard after a click on the card): Enter starts Google only for `Link`, Escape closes, and for `SignIn` Tab / Shift+Tab move on from `focused`.
- Focus: `open()` sets `focused = EmailField` for `SignIn` and gives it the keyboard (the dialog's own handle for `Link`). `focus_target()` is the handle of `focused` on `Start` and `Code`, Cancel's on `SigningIn`, the dialog's own for `Link`. `focused` follows the keyboard: Tab moves, screen changes, and a click into a field or onto a button (observed with `cx.on_focus`). When the account changes and the screen kind differs from `shown`: entering `Code` sets `focused = CodeField`, entering `Start` sets `focused = EmailField` (the email field keeps its text), entering `SigningIn` sets `focused = Cancel`; then `shown` is updated and `SignInEvent::Opened` is emitted so RootView moves the keyboard (`ui/root.rs:185-187` → `focus_terminal`).
- Fields: whenever the account or the code field changes, if `account.email_code_epoch() != code_epoch_seen` and `!code_field.composing()`: `code_field.clear()`, `last_auto = None`, `code_epoch_seen` updated (a composition open at that moment defers the clear to its end). The email field is cleared only by `open()` and `close()`. Each field is observed: a change redraws. `TextField` notifies on clicks, cursor moves and selections too, so an edit of `email_field` is a text that differs from `email_text_seen`: the dialog then stores the new text in `email_text_seen`, clears `started` (Ruling 21) and calls `account.email_edited(cx)` (D4: the InvalidEmail sentence replaces a stale failure). A change of `code_field` submits `auto_submit(self.last_auto.as_deref(), text, account.email_can_verify() && !busy && !composing)` when it is `Some`, remembering it in `last_auto` and setting `code_submitted`.
- The resend countdown repaints through a detached task started whenever the screen becomes `Code { busy: false }`: wait one second, `cx.notify()`, repeat while the dialog is open on that screen and `email_resend_wait_secs() > 0`.
- `open()` and `close()` clear both fields, `last_auto`, `code_submitted`, `started` and `email_text_seen`, and set `code_epoch_seen` to the account's epoch; `close()` also calls `account.email_cancel(cx)`. The dialog still closes itself at `LoggedIn`.
- The module comments `login.rs:1-12` and `ui/account.rs:8-11` no longer say sign-in is Google only.

Settings: the row title is `t(lang, sign_in_method_label(&m.provider))`; the address line, "Added from" and the Apple-only Remove button are unchanged.

`dev_sign_in_preview` (called last in `RootView::new`, under `cfg(target_os = "macos")`): for `SHELLX_DEV_SIGN_IN` equal to `start`, `code`, `invalid` or `switch` it calls `open_sign_in(GooglePurpose::SignIn, window, cx)`; then for `code` and `switch` `account.dev_preview_email(value, cx)`; for `invalid` `sign_in.dev_fill_email("phu@ẽample.com")`, for `switch` `sign_in.dev_fill_email("you@example.com")`. Any other value does nothing.

README: in "Run the window on a Mac" add `SHELLX_DEV_SIGN_IN=start|code|invalid|switch` (Mac development build only: opens the sign-in dialog on that screen for screenshots, with a made-up address and no network call); in "Remote view (Macs)" say the dialog opens on an email field with "Send code" (a 6-digit code is mailed to that address and typed in the dialog), with "Continue with Google" under "or" (quote the labels as that section does, from `strings.rs`).

Checklist: under "Đăng nhập và ghép cặp", replace the stale password line (`:47`) with items written in Vietnamese like the rest of the file: the email field has the keyboard when the dialog opens, Enter sends the code, the mail arrives, typing or pasting the code (also "123 456") signs in; with Unikey, EVKey or the Windows Telex keyboard on, the email field shows "Địa chỉ email này chưa đúng." and "Gửi mã" stays off; Tab walks field, "Gửi mã", Google, "Hủy" and Escape closes; "Gửi lại mã sau N giây" counts down; the dialog at 125 % and 150 % scaling; Continue with Google still works. Note there that until the relay with email sign-in is deployed, Send code answers "Bản này chưa dùng được cách đăng nhập này."

- [ ] **Step 1: Implement** the `TextField` additions, the `AccountService` methods, the dialog, the Settings title, the preview switch, the README and the checklist. (This task's logic is `sign_in_screen`, `tab_target`, `auto_submit` and the flow, tested in Tasks 1–3; GPUI views have no test harness here, so the checks are the build, the suites and the screenshots.)
- [ ] **Step 2: Build and run the suites.** Run, in one shell: the Stage 2 line (Task 3 Step 1.3), then `(cd windows && cargo build --release --locked -p shellx-app && cargo test --release --locked -p shellx-app && cargo test --locked -p shellx-model)`. Expected: the build finishes with no new warning; `test result: ok` twice.
- [ ] **Step 3: Screenshots.** If `~/.local/share/shellx-native/core/session.json` exists (an earlier manual sign-in), move it aside first and put it back afterwards: with a session the dialog closes at once. Run:

```bash
cd windows
for lang in en vi; do for screen in start code invalid switch; do
  SHELLX_LANG=$lang SHELLX_DEV_SIGN_IN=$screen dev/mac-shot.sh "$TMPDIR/shellx-signin-$screen-$lang.png" 8
done; done
```
Expected: eight lines `mac-shot: wrote …`. Open each PNG: `start` shows the title, the field with "Email address", "Send code" (disabled), "or", the white Google button and "Cancel"; `code` shows "We sent a 6-digit code to you@example.com. If it isn't there in a minute, check your spam folder." wrapped inside the card, the code field, "Verify" (disabled), "Resend code in 5x s" (disabled), "Use a different email" and "Cancel"; `invalid` shows "phu@ẽample.com" in the field, "That doesn't look like an email address." under it and "Send code" disabled; `switch` shows "you@example.com" in the field, the switch sentence wrapped under it and "Send code" enabled; the `vi` shots show the table's Vietnamese; no clipped or overlapping text inside the 340 px card. Fix what is off and repeat Steps 2–3. Keep the eight PNGs for the hand-off; do not commit them.
- [ ] **Step 4: Commit.** `git add windows/shellx-app/src/ui windows/README.md windows/G1-G3-CHECKLIST.md && git commit -m "feat(shellx-windows): email-first sign-in dialog with Google below"`

---

### Task 5: Verify and hand off

**Files:** none new.

- [ ] **Step 1: Run the full verification** from the worktree root, in one shell that starts with the Stage 2 line (Task 3 Step 1.3, filled in as there):

```bash
export PATH="<zig bin>:$HOME/.cargo/bin:$PATH" CMUX_GHOSTTY_SRC="<ghostty>"   # the Stage 2 line
(cd windows && cargo test --locked -p shellx-model)
(cd windows && cargo test --release --locked -p shellx-app)
(cd windows && cargo build --release --locked -p shellx-app)
git diff --quiet develop...HEAD -- windows/Cargo.lock shellx-core/Cargo.lock && echo locks-unchanged
(cd windows && SHELLX_LANG=en dev/mac-shot.sh "$TMPDIR/shellx-after.png" 8)
```
Expected: `test result: ok` twice; a finished build with no new warning; `locks-unchanged`; a PNG of the normal window with no dialog (the preview switch is off unless set).
- [ ] **Step 2: Secret and address scan.** Run `git diff develop...HEAD | grep -nE '^\+.*(re_[A-Za-z0-9]{8,}|RESEND_API_KEY=|@gmail\.com)'`. Expected: no match.
- [ ] **Step 3: Report and stop.** Do not merge, push, deploy, build an installer or touch the VPS. Hand-off notes: the commit list; red and green results per task; the eight screenshots' paths; Task 0's report; every command not run on this machine and why; rows 7–11 of "Where each check runs" word for word (they are the user's); any string that differed from this plan's table (Task 1 Step 1); any Plan A name that differed (Task 3 Step 1); the iPhone code-step comparison if it has landed (Ruling 26); the Contract additions below. Task 0's worktree `.worktrees/email-code-signin-windows-t0` stays until the branch lands; the orchestrator then removes it with `git worktree remove --force` (it is this plan's own).

---

## Contract additions

For the contracts owner (`docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md`): a desktop section after the iPhone part's (§31 on `feat/shellx-email-code-signin-ios`), numbered when it lands, together with Plan A's:

- Windows names: `EmailChallenge`, `email_begin`, `email_finish`, `SignInMethod::is_email`; `EmailStep`, `SignInScreen` (`Start`, `Code`, `SigningIn`), `DialogFocus`, `tab_order`, `tab_target`, `email_looks_valid`, `email_text_refused`, `code_digits`, `auto_submit`; the eight `AccountEvent::Email*` variants (`EmailCodeRequested`, `EmailEdited`, `EmailResendRequested`, `EmailBegun`, `EmailCodeSubmitted`, `EmailFinished`, `EmailChangeRequested`, `EmailCancelled`), `AccountAction::CallEmailBegin` / `CallEmailFinish`, `AccountFlow::email_code_epoch`; the `Str` variants of the String table, `email_error`, `sign_in_method_label`; `TextField::composing`.
- Behaviour shared with the phones: email first; a 409 on verify goes back to the email step; a 410 opens Resend at once; a 401 empties the code; any other failed verify (`email_sign_in_disabled` included) keeps the challenge and the digits. Shared with the Mac and the iPhone: a failed Resend drops the challenge for `email_send_failed` / `email_sign_in_disabled` (D2; Android keeps it, D9). Shared with the Mac and Android: editing the address clears the failure shown under it (the iPhone branch keeps it until the next Send). Shared with the Mac: Cancel and Escape close the dialog. Windows-only: exactly six digits in the code field's whole text, Unicode decimal digits mapped; the dialog closes at once after a code sign-in (the Mac keeps "Signed in as … / Done", D3).
- Development-only: `SHELLX_DEV_SIGN_IN=start|code|invalid|switch` on the Mac build of the window.

## Not verified while writing this plan

- Run on this Mac on 2026-11-11 (by the build-environment investigator): `cargo test --locked -p shellx-model` on `develop`, 192 passed. Nothing else here was run: `shellx-app` has never been built on this machine (no zig, no `ghostty` submodule), so Task 0's estimate, the release build, the release tests and `dev/mac-shot.sh` are expected to work as they did on the other Mac, not observed here.
- GPUI 0.2.2's source is not in the local cargo registry. Focus handles on the dialog's button `div`s (`track_focus` on a `Stateful<Div>`, as `login.rs:249-250` already does for the dialog), `cx.on_focus`, Enter and Space on a focused button, and where WM_CHAR goes while a button holds the keyboard on Windows are unverified; the Tab order itself is pinned by the model test only.
- The preview switch is this plan's design and untested: opening the dialog from inside `RootView::new` relies on GPUI delivering the `SignInEvent` after construction, as it does for the events `reconcile` causes there. If the dialog does not appear in the `start` screenshot, defer the call with `cx.defer_in(window, …)` from `new`; the rest stands.
- Moving the keyboard by emitting `SignInEvent::Opened` follows RootView's existing subscription (`ui/root.rs:185-187`); on real Windows it is part of the manual checks.
- `DECIMAL_ZEROS` comes from Python 3.9.6's Unicode 13.0: digits added in later Unicode versions are skipped (Verify stays off for them), where the phones' newer tables may accept them.
- The fake API's names in Task 3 are those of Plan A's "Interfaces for Plan B" as revised on 2026-11-11 (`set_next_email_code`, `fail_next_mail`, `email_locale` and `FakeOptions.email_routes` included), not landed code; Task 3 Step 1 checks them against what lands.
- The iPhone code step has not landed (Ruling 26). Actions availability (billing block noted 2026-10-28) was not re-checked: no network, no `gh`.

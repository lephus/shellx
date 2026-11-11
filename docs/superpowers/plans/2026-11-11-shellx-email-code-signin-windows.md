# ShellX Email Code Sign-in, Desktop Plan B (Windows) Implementation Plan

> **Status 2026-11-12: ready to execute.** This plan is the sign-in part of the Windows design (`docs/superpowers/specs/2026-11-12-shellx-windows-usable-design.md` §4.1, the account-UI half of §4.5, §6 group 2 and the sign-in part of group 3). Tasks 0–6 run now on `develop`. Tasks 7–8 need the foundations plan's rules part on `develop`, and Task 9 also needs its Windows compile command ("Consumed from the foundations plan").

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Execution (decided; revised 2026-11-12):** one implementer, one branch, ten tasks (0–9), in order, everything on this Mac. Each task commits its failing test first. Tasks 0–6 need nothing that is not on `develop` today. Before Task 7, the foundations plan's rules part (F1–F5 below) must be on `develop`. If it is not there when Task 6 is done, the implementer stops and reports. Task 9 also needs F6. The implementer stops after Task 9. One whole-branch review follows, then the orchestrator lands the branch on `develop` with `--no-ff` (D8, design §6).

**Goal:** The Windows app signs in with an email address and a mailed 6-digit code ("email first"). "Continue with Google" shows only in builds that have a Google client. The dialog never opens by itself: after a server sign-out a "Sign in again" notice shows instead. Sign-out is offered in every state that has a session. Every failure reads as a sentence. Access can be requested only from a Mac that can host.

**Architecture:** The pure `shellx-model` crate holds the rules, and all of them run under `cargo test` on this Mac:
- the typed core calls;
- the strings;
- the input rules: the ASCII address, Unicode digits, the dialog's screens, Tab order and keys;
- the email steps inside the event-driven `AccountFlow`, where time is passed in so the resend lock is testable;
- `account_view` for Settings › Account;
- the request-access rule.

`shellx-core` gains one local RPC, `auth.google.available`. `shellx-app` only wires: it maps the new actions to core calls, draws the dialog with the existing `TextField` and focusable buttons, and draws the notice, Settings › Account and the "+" list. The window's release build runs on this Mac, and a Mac-only preview switch shows each screen.

**Tech Stack:** Rust toolchain 1.95.0 (MSRV 1.91), edition 2024, GPUI `=0.2.2` (vendored under `windows/vendor/` once F7 lands), `shellx-core` (path dependency), `shellx-fake-api` (dev-dependency), zig 0.16.0 and the main checkout's `ghostty` for `libghostty-vt`.

**Spec and sources, binding in this order:**
1. The Windows design `docs/superpowers/specs/2026-11-12-shellx-windows-usable-design.md` (Vietnamese).
2. The decisions `.superpowers/sdd/2026-11-11-shellx-email-code-signin/desktop-decisions.md` (D1–D9). The design changes D3 in one point: the dialog never opens by itself.
3. The core contract as it is on `develop` since d847812117: `shellx-core/src/auth_email.rs`, `shellx-core/tests/email.rs`, `shellx-core/fake-api/src/lib.rs`, and "Interfaces for Plan B" in `docs/superpowers/plans/2026-11-11-shellx-email-code-signin-core-mac.md`.

Also used:
- The relay on `develop`: contracts §29 in `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md`, `relay/src/routes/email-sign-in.ts` and `relay/src/auth/email-codes.ts`.
- The phone catalog `shellx-ios/ShellX/Localizable.xcstrings` for every new email string.
- The evidence behind the design, in `.superpowers/sdd/2026-11-11-windows-usable/`: `review-2-input.md` (how keys reach a field on GPUI-Windows) and `review-4-account-pairing-remote.md` (the account flow's states and dead ends).
- The foundations plan `docs/superpowers/plans/2026-11-12-shellx-windows-usable-1-foundations.md`.

Background only: `docs/superpowers/specs/2026-11-10-shellx-email-code-sign-in-design.md` and the brief `.superpowers/sdd/2026-11-11-shellx-email-code-signin/email-first-brief.md`. Conventions: `windows/README.md` ("Run the window on a Mac").

All file:line references are to `develop` at c06834ec4e. After `develop` is merged in (Task 7 Step 1), find the same code by name.

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

## Revision 2026-11-12

"Design" is `docs/superpowers/specs/2026-11-12-shellx-windows-usable-design.md`. "R2" and "R4" are the reviews in `.superpowers/sdd/2026-11-11-windows-usable/`. "F1"–"F7" are the foundations items in the section below.

1. Status: the ON HOLD banner is replaced. The plan is the design's sign-in part. (design §4.1, §6)
2. The binding order is now: design, then D1–D9, then the core on `develop`. The design changes D3: the dialog never opens by itself. (design §4.1, R2 F12)
3. Branch `feat/shellx-windows-signin-email` and worktree `.worktrees/windows-signin-email` (were `…email-code-signin-windows`). (orchestrator)
4. Execution: ten tasks (0–9). Tasks 0–6 run today, Tasks 7–8 after the foundations' rules part, and Task 9 after its compile command. Stages 1 and 2 and the background Task 0 are gone. (design §6; build environment ready)
5. Task 0 is now only the worktree and the baselines. It drops the ghostty clone, the zig install, the detached baseline worktree, the estimate and the other-Mac fallback. The **build line** points `CMUX_GHOSTTY_SRC` at the main checkout's `ghostty`. (build environment ready on 2026-11-12: zig 0.16.0, ghostty initialised, 142 `shellx-app` release tests passing)
6. Global Constraints:
   - the build line;
   - no step depends on GitHub Actions;
   - the foundations items are consumed, never redone;
   - the lockfile rule is relative to `develop`, because F7 changes `windows/Cargo.lock` once;
   - Settings and the dialog never show a code;
   - the core change is limited to `auth.google.available`.

   (billing block; design §4.1, §5)
7. The core contract was re-checked against `develop` (d847812117). The RPC names, params, result fields, error codes and fake-relay names are as Plan A's Interfaces say, and `expire_email_codes` exists. The extra codes (`invalid_params`, `bad_request`, `internal_error`, `payload_too_large`, `not_configured`, `io`, `state_dir_insecure`, `state_file_insecure`, `crypto`, `unknown_method`, `invalid_json`) read `ServerProblem`. (brief)
8. New core RPC `auth.google.available` and new Task 3. Google shows only when the core says the build has a Google client. (design §4.1, §9 "cách lõi báo có cấu hình Google")
9. Task 1:
   - `tab_order` takes `google`;
   - new `dialog_key` and `DialogKey`;
   - `DECIMAL_ZEROS` is public and copied from the core, not generated with Python;
   - new `FirstSignInCreatesAccount` string.

   (design §4.1, R2 §1–§3)
10. Task 2:
    - the two `run_account_action` arms are compiled and tested in the same task;
    - new test `only_one_sign_in_flow_runs_at_a_time`;
    - the server sign-out test no longer uses `take_signed_out_by_server`;
    - `AccountFlow`'s `Debug` stays out of scope.

    (core review of Tasks 1–3, design §4.1)
11. Task 4 (was 3):
    - its prerequisite steps are gone, because Plan A is merged and the fake names were checked while writing;
    - new tests `an_expired_code_through_the_real_core_unlocks_resend`, `google_availability_through_the_real_core` and `the_model_maps_digits_and_lengths_like_the_core`.

    (develop; D4)
12. Task 5 (was 4):
    - Google and "or" show only with a Google client;
    - the first-sign-in line;
    - keys through `dialog_key`, with no key handler on buttons (GPUI clicks a focused button on Enter or Space);
    - the dialog's own handle returns the keyboard to the field;
    - previews `start|google|code|invalid|switch`;
    - the README gets the developer switch only;
    - the checklist edit is dropped.

    (design §4.1, §6 group 6; R2 §2)
13. New Task 6: a "Sign in again" notice in the sidebar footer and in Settings › Account replaces the self-opening dialog, and the one-time Google-switch offer no longer opens a dialog. (design §4.1, R2 F12)
14. New Task 7: Settings › Account is drawn from `account_view`. It offers sign-out in every state with a stored session (F3), words errors as sentences (F4), and shows the Google switch only with Google. (design §4.1; R4 Major 6, Minor 9–10)
15. New Task 8: access can be requested only from a Mac with `can_host` (F2) or while `SHELLX_REQUEST_ANY_MAC=1`, never from a Windows PC. The "+" list says why none can be asked. (design §4.5; R4 Major 5)
16. Task 9 (was 5):
    - the Windows compile uses F6;
    - screenshots only with the Screen Recording permission, else "not taken";
    - the hand-off carries the sign-in items of the design's 10-step list for the docs group;
    - the iPhone code step is compared now that it is on `develop`.

    (design §5.2, §5.3)
17. "Where each check runs" is rewritten. No Actions rows, the VPS cross build is not this plan's, and real Windows is checked by the user from the test installer. (billing; design §5)
18. Review Focus adds:
    - typed text reaching the field;
    - one sign-in flow at a time;
    - a build without Google;
    - no self-opening dialog;
    - sign-out and sentences in an error state;
    - the request rule.

    (design §4.1, §4.5; R2; core review)
19. Rulings 13, 23 and 24 are superseded; 14, 20, 25 and 26 amended; 27–40 added. (design)
20. String table: five non-catalog strings added and `NoOtherMachines` removed. `Str::ALL` counts are stated per task, relative to the branch, because the foundations plan adds strings too. (design §4.1, §4.5, §9)
21. "Not verified" is updated. GPUI 0.2.2's source is now in `~/.cargo/registry`, and the focus and key facts used here were read there. (registry fetched on 2026-11-11)
22. Contract additions: `auth.google.available`, the new Windows names, `SHELLX_REQUEST_ANY_MAC` and the preview values. (design §4.1, §4.5)

## Reconciliation with the foundations plan (orchestrator, 2026-11-12)

The foundations plan (`docs/superpowers/plans/2026-11-12-shellx-windows-usable-1-foundations.md`) was finished after this revision. Its "Interfaces for the later plans" block is the truth for every name below; where this plan uses a guessed name, read it as the real one.

| This plan writes | The foundations plan provides |
| --- | --- |
| `AccountFlow::has_session()` (F3) | `AccountFlow::can_sign_out(&self) -> bool` |
| `account_error(lang, &CoreErr) -> String` (F4) | `strings::failure_sentence(Lang, code: &str) -> String`; `google_error` never returns a raw code |
| `SHELLX_REQUEST_ANY_MAC=1` | `SHELLX_OFFER_ALL_MACS=1`, read through `sidebar::offer_rule_from_env` |
| the request rule and the "+" list filter (Task 8's model part) | already built: `sidebar::{OfferRule, can_offer_access, request_targets, request_panel_notes, build_groups_with}` |
| `MacsCannotHostYet`, `SignInOnYourMac`, a generic server sentence, a rate-limit sentence, an "unavailable" sentence | already built as `Str::{MacCannotHostYet, SignInOnYourMac, ServerProblem, RateLimited, SignInUnavailable}`; this plan adds 12 `Str` variants, not 15 |
| the Windows compile command (F6) | `scripts/shellx/check-windows-build.sh` |
| `AccountFlow`'s `Debug` printing the account email | fixed by the foundations plan (its Task L15) |

Consequences: **Task 8 keeps only the window wiring** (`ui/root.rs`, `ui/sidebar.rs`, the "+" list notes drawn from `request_panel_notes`); it adds no model rule, no environment variable and no sentence that the table lists. Task 1's string count and `google_error` expectations follow the foundations plan's "For the paused email-first plan" notes. This plan starts **after** the foundations plan's rules part is on `develop` (the orchestrator dispatches it then), so Task 7 Step 1's merge is a no-op check.

## Consumed from the foundations plan

`docs/superpowers/plans/2026-11-12-shellx-windows-usable-1-foundations.md` was not on disk when this revision was written. This plan redoes none of the items below. Each item states the behaviour this plan relies on. Where that plan's Interfaces block names a thing differently from the "written here as" column, use its name and record the difference in Task 9's hand-off.

| # | Behaviour relied on | Needed by | Written here as |
| --- | --- | --- | --- |
| F1 | A `machines.list` item with `"fingerprint": null` (the relay never sends a key) parses into `MachineInfo`, so a sign-in reaches `LoggedIn` against the real relay (`windows/shellx-model/src/sidebar.rs:16` today requires a string) | Task 4 once F5 is merged; every live sign-in | (no name) |
| F2 | `MachineInfo.can_host: bool`, `false` when the key is missing or null; the core reads `can_host` from the relay's list and forwards it in `machines.list` | Task 8 | `m.can_host` |
| F3 | The flow says whether a session is stored. True in `LoggedIn`, and in an `Error` or `LoggingIn` reached with a stored session (for example a login that succeeded, then a list refused with `bad_response`: R4 Blocker 1). False in `Unknown`, and in `LoggedOut`. `LogoutRequested` in each such state ends at `LoggedOut`. | Task 7 | `AccountFlow::has_session(&self) -> bool` |
| F4 | `google_error` never returns a code. One function words any account-UI `CoreErr` as a sentence: `network` gets the network sentence, codes without a sentence of their own get the generic server sentence (catalog `signin.error.server`), and `CoreErr.message` is never used | Task 5 (through `google_error`), Task 7 | `account_error(lang: Lang, e: &CoreErr) -> String` |
| F5 | The fake relay answers `/v2/machines` in the real relay's shape (no `noise_public_key_b64`), so the core's `fingerprint` is null | Task 4 (its tests still reach `LoggedIn` through F1) | (no name) |
| F6 | One command, run from this Mac, compiles the committed `HEAD`'s `shellx-app` for `x86_64-pc-windows-msvc` without an installer | Task 9 | "the Windows compile command" |
| F7 | gpui 0.2.2 is vendored under `windows/vendor/` behind `[patch.crates-io]`, so `windows/Cargo.lock` changes once on `develop` | Task 9's lockfile check (relative to `develop`); the GPUI source path | (no name) |

"The foundations' rules part is on `develop`" means F1–F5 are merged there. Check it before Task 7, from the main checkout:
1. `git grep -n can_host develop -- windows/shellx-model/src/sidebar.rs` must match.
2. `git grep -n 'noise_public_key_b64' develop -- shellx-core/fake-api/src/lib.rs` must no longer show it in the `/v2/machines` list answer.
3. The F3 and F4 names from that plan's Interfaces block must be found with `git grep` on `develop`.

Known overlaps, which the merge in Task 7 Step 1 resolves:
- `Str` variants and the `Str::ALL` count in `strings.rs`.
- The generic server sentence, if both plans add it (Task 1's rule).
- `MachineInfo` literals in tests.
- `AccountFlow` fields, and the tests in `account.rs`.

The wiring plan that follows the foundations plan must not redo what this plan wires:
- the sign-in dialog;
- the notice;
- Settings › Account;
- the request button and the "+" list.

## Global Constraints

- The relay (D1): contracts §29 and the relay code on `develop`. Facts the dialog lives with:
  - One live code per address, and the newest request wins. A newer request from any device makes this challenge answer 410, and a code from an older mail is a counted wrong guess.
  - A relay restart or deploy voids every live code (410, no guess counted).
  - The code is a six-character string that keeps its leading zeros (`"004217"`).
  - A 409 on verify means the code is already spent.
  - No 429 carries `Retry-After`.
  - Email verifies and Google sign-ins share 10 per IP per minute.
  - The mail's text body also says "10 minutes", so a pasted whole body has eight digits.

  Production (D1, a note): `PASSWORD_LOGIN` defaults to `on`, so a code for an account that still has a password answers 409.
- The core contract this plan consumes was checked against `shellx-core` on `develop` (d847812117). If the code differs from this text, the code wins and the difference goes in the hand-off.

  ```
  auth.email.begin  {email, locale?} -> {challenge_id, expires_in, resend_in, email}      email = the relay's normalized address
  auth.email.finish {challenge_id, code} -> {user_id, device_id, device_public_key_b64, fingerprint, email, auth_method: "email"}
  auth.google.available {} -> {available: bool}                                            new in Task 3; local, no request
  ```

  What the core does:
  - It sends the relay exactly `vi` or `en` (D1).
  - It refuses an address with any character outside ASCII after trimming as `invalid_email`, without a request (D4).
  - It removes whitespace from `code`, maps Unicode decimal digits to ASCII, and refuses anything but six digits as `invalid_code`, without a request (D4).
  - A 404 (with or without JSON) and a 503 `email_sign_in_disabled` both reach the app as `email_sign_in_disabled` (Plan A Ruling 1).
  - It accepts `auth.email.finish` while a Google flow waits (core review of Tasks 1–3), so the Windows flow must keep one sign-in flow at a time (Ruling 35).
- Wording of email-path failures (D2):
  - `invalid_email`, `disposable_email`, `rate_limited`, `email_send_failed`, `email_sign_in_disabled`, `invalid_code`, `code_expired` and `switch_from_signed_in_device` have their own sentences.
  - `network` keeps the desktop's `RelayUnreachable`.
  - Anything else reads `ServerProblem`: `http_<status>` without JSON, `server`, `invalid_device`, `invalid_params`, `bad_request`, `internal_error`, `payload_too_large`, `not_configured`, `io`, `state_dir_insecure`, `state_file_insecure`, `crypto`, `unknown_method`, `invalid_json`, and so on.

  Google-path and account-state errors are worded by `google_error` and F4. Nowhere in the dialog or in Settings › Account does a person see a code or a `CoreErr.message` (design §4.1).
- Code: 6 digits, lives 600 s, 5 guesses. "Resend code" is locked for the `resend_in` the core returns (60 s). After a 429 it unlocks at once; re-locking is deferred (D2).
- Email first (D3, design §4.1): the SignIn dialog shows the title, then the first-sign-in line, then the email field with Send code. Only when the build has a Google client (Ruling 28) do "or" and Continue with Google follow. Cancel comes last. There is no "Continue with email" and no discovery call. The Link dialog ("Switch to Google sign-in") is unchanged, and it opens only from Settings and only with Google.
- The dialog never opens by itself (design §4.1, R2 F12). Every open is the person's: Settings › Account, the machines "+" while signed out, or the "Sign in again" notice.
- Strings (D5): every new email string equals the en / vi value of the phone catalog `shellx-ios/ShellX/Localizable.xcstrings` on `develop` (the catalog wins over this plan's table), pinned by `email_strings_match_the_phone_catalog`. The five non-email strings follow Ruling 31. Older desktop strings are unchanged. Windows strings live only in `windows/shellx-model/src/strings.rs`; there is no Mac `.xcstrings` change, so the Mac localization flow does not apply.
- Tests fake the relay (`shellx-fake-api`) and the core (`FakeCore`). Nothing here needs a running relay, a real mailbox, a key or a network.
- Never log or `Debug`-print the code, the `challenge_id` or an email address. This covers the manual `Debug` impls of `AccountEvent` and `AccountAction`, the email run, and the `core_api` values.
- No new crates. `git diff develop...HEAD -- windows/Cargo.lock shellx-core/Cargo.lock` stays empty: it is relative to `develop`, so F7's one change to `windows/Cargo.lock` does not count. `windows/Cargo.lock` also holds `shellx-core`'s graph.
- No account deletion by code: Settings keeps the `DELETE_ACCOUNT_URL` link.
- Every shell that builds or tests anything starts with the **build line**. Agent shells keep no variables between commands, so it is repeated in each:

  ```bash
  export PATH="/opt/homebrew/opt/zig@0.16/bin:$HOME/.cargo/bin:$PATH" CMUX_GHOSTTY_SRC="/Users/richard/Documents/helper/shellx/ghostty"
  ```

  Without `CMUX_GHOSTTY_SRC`, `ghostty-vt-sys` builds from the worktree's empty `ghostty` directory and fails (`cmux-tui/crates/ghostty-vt-sys/build.rs:11-14`). It also rebuilds whenever the variable changes (`:25`).
- Builds of the window on a Mac:
  - Never build or run a debug `shellx-app`: it crashes (`windows/README.md:54-57`). Use `cargo test --release` and `cargo build --release`. `cargo test -p shellx-model` is fine.
  - Build under `nice -n 19` while another agent builds or runs a simulator on this 16 GB Mac.
  - `dev/mac-shot.sh` only runs the built binary.
- Never release, deploy, build an installer, push, merge to `main`, sign, notarize, use `gh`, dispatch a workflow, depend on a GitHub Actions run (billing block) or touch the VPS. If F6 runs on the VPS rather than in local Docker, the orchestrator runs it, not the implementer.
- Build no Mac app: no `xcodebuild`, no `reload.sh`. Never quit, launch or replace `/Applications/ShellX.app` or any cmux app. The screenshots start only `windows/target/release/shellx-desktop`, and `dev/mac-shot.sh` kills only the PID it started.
- The implementer does not merge into `develop`; the orchestrator lands the branch after review (D8). No Windows release with the email path before the relay with the feature is deployed (D8; design §8).
- Branch `feat/shellx-windows-signin-email` from `develop`, worktree `.worktrees/windows-signin-email`. Commit style: `test(shellx-windows): …` then `feat(shellx-windows): …`, and `test(shellx-core): …` / `feat(shellx-core): …` for Task 3's core part.
- Read this plan from the main checkout (`/Users/richard/Documents/helper/shellx/docs/superpowers/plans/2026-11-11-shellx-email-code-signin-windows.md`). The worktree's copy is the one committed on `develop`, which may predate this revision. Do not edit the plan on the branch.

## Review Focus

1. **A character typed while the dialog is open reaches the field.** This is the 2026-10-31 "cannot type" defect class. On GPUI-Windows a key-down that any handler stops is never translated, so no `WM_CHAR` follows (R2 §1). No dialog handler stops a key it does not act on: letters, digits, Space, Backspace and Ctrl+V pass, and so does Enter on a button. Tests: Task 1 `keys_the_dialog_does_not_act_on_pass_through`; the existing `modal::tests::composing_and_text_keys_pass_while_a_panel_is_open` stays green; on real Windows, the user (Where each check runs, row 10).
2. **A code pasted with spaces, a line break or the mail's subject around it, or typed in full-width or Arabic-Indic digits.** Its six digits are used, as ASCII. The whole mail body (eight digits) keeps Verify off. Tests: Task 1 `code_digits_takes_the_six_digits_of_what_was_typed`; Task 2 `email_sign_in_runs_email_code_verify_then_lists`; Task 4 `email_session_against_fake_api`, `the_model_maps_digits_and_lengths_like_the_core`.
3. **Double submit: six digits submit by themselves while Enter or Verify is pressed.** One `CallEmailFinish`. Tests: Task 1 `auto_submit_fires_once_per_new_six_digits`; Task 2 `verify_runs_once_for_a_double_submit`.
4. **Each verify answer of D2.**
   - 401: the dialog stays on the code step, the code is emptied, the challenge kept.
   - 410: the field goes off and is emptied, and Resend unlocks at once.
   - 409: back to the first screen with the address; the challenge and digits are dropped.
   - Any other answer (429, network, a body-less 5xx, `invalid_device`, `email_sign_in_disabled`): the code step, with the digits and the challenge kept.

   Tests: Task 2 `a_wrong_code_empties_the_field_and_stays_on_the_code_step`, `an_expired_code_drops_the_challenge_and_unlocks_resend`, `a_switch_answer_returns_to_the_first_screen`, `a_verify_refused_for_rate_network_or_server_keeps_the_code`, `a_disabled_relay_on_verify_keeps_the_code`; Task 4 `an_expired_code_through_the_real_core_unlocks_resend`.
5. **A failed Resend.** 502 `email_send_failed`, 503 `email_sign_in_disabled` and 404 drop the challenge (Verify off). 429, network and a body-less 5xx keep it. Resend is unlocked either way. Tests: Task 2 `a_failed_resend_drops_the_challenge_the_relay_lost`, `a_failed_resend_keeps_the_challenge_for_rate_limited_and_network`; Task 4 `a_failed_resend_through_the_real_core_drops_the_challenge`, `a_rate_limited_resend_through_the_real_core_keeps_the_code`.
6. **An address with a Vietnamese letter (Telex, VNI and Unikey turn "ex" into "ẽ").** Send code stays off and "That doesn't look like an email address." shows under the field, also after an earlier failed Send (editing clears that failure). No request is sent, and an IME composition is never rewritten. Tests: Task 1 `plausible_addresses`, `refused_text_shows_the_invalid_email_sentence`; Task 2 `send_code_needs_a_plausible_ascii_address_and_runs_once`, `editing_the_address_clears_the_email_failure`.
7. **Closing the dialog mid-flow and opening it again.** A late answer never brings an old screen back, and the reopened dialog starts clean. A code that verified after the close still signs this PC in. Tests: Task 2 `closing_while_sending_ignores_the_late_challenge`, `closing_while_verifying_still_signs_in_when_the_code_was_right`, `reopening_after_a_close_starts_clean`.
8. **A relay without the feature (production today), a body-less 5xx, offline.** Under the field, a sentence and never a code: "This way of signing in isn't available in this build.", "ShellX is having a problem. Try again later." or the network sentence. The app stays signed out, and a late `not_logged_in` list never throws the person off the code step. Tests: Task 1 `email_error_maps_codes`; Task 2 `a_relay_without_email_sign_in_keeps_the_app_signed_out`, `a_disabled_relay_on_verify_keeps_the_code`, `a_failed_send_returns_to_the_first_screen_with_the_error`, `a_late_list_result_does_not_reset_the_email_step`; Task 4 `a_relay_without_email_sign_in_answers_through_the_real_core`.
9. **One sign-in flow at a time.** The core accepts `auth.email.finish` while a Google flow waits, so only the flow keeps them apart. Google and email never both run, and only one failure line shows at a time (the one-line rule is checked by reading Task 5's code). Tests: Task 2 `only_one_sign_in_flow_runs_at_a_time`, `email_and_google_share_the_first_screen`, `closing_while_verifying_still_signs_in_when_the_code_was_right`.
10. **A build without a Google client (every cross build today: R4 Blocker 3).** No "or", no Google button and no "Switch to Google sign-in" row. Tab skips Google, and `not_configured` never reaches a person. Tests: Task 3 `google_available_needs_a_client_id_and_secret`, `google_available_reads_the_core_answer`; Task 4 `google_availability_through_the_real_core`; Task 1 `tab_follows_the_dialog_order`; Task 7 `account_view_offers_the_google_switch_only_with_google`.
11. **The server ends the session while the person types in the shell.** No dialog opens, and Enter and letters keep going to the shell. A "Sign in again" notice shows in the sidebar footer and in Settings › Account until the next sign-in. Tests: Task 6 `a_server_sign_out_shows_the_notice_until_the_next_sign_in`, `account_view_offers_sign_in_again_after_a_server_sign_out`.
12. **A stored session that cannot be used (R4 Blocker 1, a broken key file).** "Sign out" is offered, and the error line is a sentence with no code and no server text. Tests: Task 7 `account_view_offers_sign_out_whenever_a_session_is_stored`, `account_view_words_errors_as_sentences`.
13. **Another Windows PC, or a Mac that cannot host yet.** No request button. The "+" list shows only Macs and says why none can be asked. Tests: Task 8 `only_macs_that_can_host_are_offered`, `build_groups_offers_access_only_where_it_can_work`, `the_machine_picker_lists_macs_and_says_why_none_can_be_asked`.
14. **Keyboard only.** The email field has the keyboard on open. Return sends or verifies, Tab follows D3's order, Escape closes, and Enter or Space presses a focused button once. Tests: Task 1 `tab_follows_the_dialog_order`, `keys_the_dialog_does_not_act_on_pass_through`; the rest by hand (Where each check runs, rows 9 and 10).

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
12. ~~A Mac-only preview switch `SHELLX_DEV_SIGN_IN=start|email|code`.~~ **Superseded by Ruling 23** (D3, D4), itself superseded by Ruling 38.
13. ~~The spec says only debug tests of `shellx-app` cannot run on a Mac; this plan runs its release tests there. Amended by Ruling 24 (D6): on this Mac only after Task 0, else on the user's other Mac.~~ **Superseded by Ruling 36**: the release tests and build run on this Mac (build line).
14. **Email first (D3).** The SignIn dialog opens on the email step: the email field (placeholder "Email address"), Send code, the "or" line, Continue with Google, Cancel. `AccountEvent::EmailRequested` and `Str::ContinueWithEmail` do not exist; `EmailCodeRequested` (Send code) starts the run. `SignInScreen` is `Start { sending, google_waiting }`, `Code { busy }` or `SigningIn`; "Waiting for Google…" replaces the Google button inside `Start`. `GooglePurpose::Link` is unchanged. **Amended by Rulings 28 and 31:** "or" and Google are drawn only with a Google client, and the first-sign-in line sits under the title.
15. **Google and email on one screen (D3).** `GoogleRequested(SignIn)` is accepted with no run or a run at `Email`, and drops that run with its failure; it is refused while a run is `Sending`, `Code` or `Verifying`. `EmailCodeRequested` is refused while a Google flow runs.
16. **The code field (supersedes 8; D2, D4).** It shows what was typed or pasted and is never filtered or rewritten while typing, so an IME composition is never disturbed. Verify and the auto-submit use `code_digits` (every Unicode decimal digit as ASCII; exactly six digits in the whole text). The dialog empties it, never during a composition, when `email_code_epoch()` moves: a new challenge, a wrong code, a dead or dropped challenge, a 409.
17. **Each relay answer (D2).** Verify: `invalid_code` → code step, field emptied, challenge kept; `code_expired` → code step, challenge dropped (field off and emptied), Resend unlocked; `switch_from_signed_in_device` → the first screen with the typed address kept, the challenge, sent-to address, digits and lock dropped, the switch sentence under the field; any other failure → code step, digits and challenge kept. Failed Resend: `email_send_failed`, `email_sign_in_disabled` (404 included) → challenge dropped; `rate_limited`, `network` → kept; Resend unlocked in both. Failed first Send: the first screen with the sentence; Send works again at once. The sentences are `email_error`'s.
18. **Strings (D5).** The phone catalog's en / vi for the 15 new variants; `EmailAddress` en becomes "Email address" (vi unchanged, and the Mac's new `remote.signin.email.field` has the same text); `ServerProblem` is the catalog's `signin.error.server`, used by `email_error` only; `network` keeps `RelayUnreachable`, and Google's errors keep their texts.
19. **ASCII (D4).** `email_looks_valid` needs ASCII and at most 254 bytes after trimming (the relay's limits and the phones' rule); `email_text_refused` puts `InvalidEmail` under the field as soon as such a character is committed, never while a composition is open. Windows has no per-field input-source switch (Unikey and EVKey are global hooks; GPUI 0.2.2 offers no input scope), so the rule and its sentence are the protection.
20. **Keyboard (D3).** The email field holds the keyboard when the dialog opens, ~~also when it opens by itself after a server sign-out~~ (the dialog never opens by itself: Ruling 29). Return in the email field is Send code when it is enabled; Return in the code field is Verify when it is enabled; six digits submit by themselves. Tab and Shift+Tab follow `tab_order` (first screen: email field, Send code, Continue with Google, Cancel; code step: code field, Verify, Resend, Use a different email, Cancel), skipping disabled controls; today no button can take the keyboard, so the dialog gives its buttons focus handles; Enter or Space presses a focused button. Escape is Cancel anywhere in the dialog and drops a pending challenge. Enter on the dialog's own handle starts Google only for `Link`. **Amended by Ruling 30:** how the keys are handled, Google left out of the Tab order when it is hidden, and no key handler on the buttons.
21. **One failure line (D3).** The email failure, or the InvalidEmail hint, shows under the email field; Google's under the Google button. Pressing Send code or typing in the email field hides Google's failure (`started` cleared); pressing Google drops the run with its failure (Ruling 15). While Google's failure shows, the email line stays empty, so a refused address's hint waits until typing hides Google's failure. Editing the address (`EmailEdited`) clears the email run's failure at `Email`, so the InvalidEmail sentence replaces a stale relay sentence as soon as a character outside ASCII is typed (D4; the Mac's `setEmail` does the same, Plan A Ruling 27).
22. **Codes D2 does not list.** `email_sign_in_disabled` on verify keeps the challenge and the digits, like every other verify failure without a rule of its own (Ruling 17). That is the RPC contract (Plan A's "Interfaces for Plan B": "on verify, keep the digits", which the Mac follows and Plan B mirrors), and both phones do the same. On verify it can only come from a 404, because the relay's `/verify` never answers 503 (only `/code` checks for the mail gateway, `relay/src/routes/email-sign-in.ts:44`; `/verify` starts at `:95`); a relay that comes back with the feature has restarted, so the next Verify answers 410 and drops the challenge then. A failed Resend with any code not named in Ruling 17 keeps the challenge, as `network` does: its state is unknown, and a dead one answers 410 on the next Verify, which counts no guess.
23. ~~**Preview (supersedes 12; D3, D4).** `SHELLX_DEV_SIGN_IN=start|code|invalid|switch` …~~ **Superseded by Ruling 38.**
24. ~~**Stages (D6).** Stage 1 / Stage 2, a background Task 0 in a detached worktree, the other Mac as fallback.~~ **Superseded by Rulings 32 and 36.** The build environment is ready on this Mac, and the only waits are for the foundations plan.
25. **Outside this plan.** These are not touched:
    - A live check against a relay with Resend needs a debug build on a Windows PC with `SHELLX_API_BASE` and a port forward, or the deployed relay. That is the user's (D7).
    - Android's kept challenge after a failed Resend, and re-locking after a 429 (D9).
    - A "Your session expired" line inside the dialog (D3).

    **Amended:**
    - The sidebar and Settings notice of Ruling 29 is not that line.
    - The test installer, the 10-step check on a real PC, the diagnostics report, the user-facing README text and the new checklist belong to the design's groups 4–6.
    - `AccountFlow`'s derived `Debug`, which prints the account email after a sign-in, is design §4.7(2). It is not in this plan; the hand-off names it.
26. **iPhone (D3, non-blocking).** ~~The iPhone code step has not landed.~~ **Amended:** the iPhone branch landed on `develop` in 6b0ddc5e42. Task 9 compares its code-step rules with Ruling 17 and lists the differences in the hand-off; nothing here waits for it.
27. **Binding order (2026-11-12).** The design comes first, then D1–D9, then the core on `develop`. The design changes D3 in one point: the dialog never opens by itself, so "the email field has the keyboard on open" applies to every open, and every open is the person's.
28. **Google only with a client (design §4.1).**
    - The core answers `auth.google.available {}` with `{"available": true}` exactly when its config has a non-empty `google_client_id` and a non-empty `google_client_secret`, whether they come from `config.set`, the environment or the build. A build with only the id would fail at Google's token step, so it counts as no client (design §3: no new button that can only fail).
    - The window asks once at start, and again when the dialog opens while the answer is unknown (an earlier call failed).
    - Without a "yes", the dialog draws no "or", no Google button and no Google error line, Settings draws no "Switch to Google sign-in" row, and Tab skips Google.
    - `auth.google.begin` is unchanged.
29. **No dialog by itself (design §4.1, R2 F12).**
    - `RootView::account_changed` (`ui/root.rs:387-396`) no longer opens the dialog.
    - A server sign-out sets `AccountFlow::session_ended_by_server()`, a flag that the next entry to `LoggedIn` clears and that nothing consumes. While it is set:
      - the sidebar footer shows "Your session expired." with a "Sign in again" button;
      - Settings › Account shows the same line, and its sign-in button reads "Sign in again".
    - The one-time Google-switch offer no longer opens the Link dialog. `take_google_switch_offer`, `GOOGLE_SWITCH_MARKER` and `take_once` are removed; Settings' switch row stays (Ruling 28).
30. **Keys in the dialog (amends 20; R2 §1–§3).**
    - The dialog card's own key-down listener asks `dialog_key` and acts only on what it returns. Whatever it does not act on it leaves unstopped, so the platform translates it and typed text reaches the field.
    - Buttons get focus handles but no key handler. GPUI already clicks a focused element that has `on_click` when Enter or Space goes up (`gpui-0.2.2/src/elements/div.rs:2178-2200`), so a handler of our own would press twice. Disabled buttons have no `on_click`.
    - For `SignIn`, the dialog's own handle never keeps the keyboard: when it gets it (a click on the card or the backdrop), the dialog gives it back to `focused`.
    - Tab order leaves Google out when Google is hidden (`tab_order(screen, google)`).
31. **Strings outside the phone catalog (design §9; D5 covers only the email strings).** Written in the voice of the existing strings:
    - `FirstSignInCreatesAccount` (design §4.1).
    - `SessionExpired` and `SignInAgain`: the two sentences of the catalog's `signin.expired`. The second becomes the button label, as the design says ("Đăng nhập lại").
    - `MacsCannotHostYet` and `SignInOnYourMac` (design §4.5).

    `NoOtherMachines` is removed: its only use, the empty "+" list, gets the two §4.5 sentences.
32. **Foundations consumed, not redone (design §6 groups 0–1).** F1–F7 belong to the foundations plan. Tasks 7 and 8 start only when F1–F5 are on `develop`, and Task 9 only when F6 is too. Where a name differs, the foundations plan's name wins.
33. **Settings › Account is drawn from `account_view` (design §4: rules are pure functions).** That covers:
    - the sign-in button and its label;
    - the session notice;
    - "Sign out" whenever F3 says a session is stored, `Error` included (R4 Major 6);
    - the Google switch only with Google;
    - the error line, as F4's sentence. No `CoreErr.message` and no code is drawn anywhere in Settings › Account, the methods notice included.
34. **Other machines (the account-UI half of design §4.5).**
    - Access may be requested only from a Mac (`platform == "macos"`) whose list item says `can_host` (F2), or from any Mac while `SHELLX_REQUEST_ANY_MAC` is exactly `1` (read once at start). Never from a Windows PC, never from this machine.
    - Other machines' rows stay, with names and online state. A row that may not be asked shows no button.
    - The "+" list shows only other Macs without a link: requestable ones clickable, the rest dimmed.
    - The "+" list's note:
      - when no listed Mac may be asked: `MacsCannotHostYet`;
      - when there is no other Mac at all: `MacsCannotHostYet` and `SignInOnYourMac`.
35. **One sign-in flow at a time (core review of Tasks 1–3).** The core lets `auth.email.finish` run while a Google flow waits, so Ruling 15's refusals are the only guard: no email event starts a call while `google_in_flight()` is `Some`. Pinned by `only_one_sign_in_flow_runs_at_a_time`.
36. **Where checks run (supersedes 13 and 24; design §5).**
    - Every check of this plan runs on this Mac with the build line.
    - Nothing depends on GitHub Actions (billing).
    - Windows-only code is compiled with F6.
    - Screenshots are taken only if this shell has the Screen Recording permission; otherwise the hand-off says "not taken", and the preview switch stays for the user.
    - Real-Windows behaviour (typing, paste and IME in the two fields, Tab, Escape, scaling) is the user's, from the test installer (design §5.3 step 10), with a diagnostics report when something fails.
37. **Docs (design §6 group 6).** The user-facing README text and the new 10-step checklist belong to the docs group. This plan adds only its developer switches to `windows/README.md` ("Run the window on a Mac"), and Task 9 hands over its sign-in check items. The old Task 4 edits of "Remote view (Macs)" and `windows/G1-G3-CHECKLIST.md` are dropped.
38. **Preview (supersedes 23; D3, D4).**
    - `SHELLX_DEV_SIGN_IN=start|google|code|invalid|switch|expired`, compiled only under `cfg(target_os = "macos")` and never in the Windows product.
    - The screens:
      - `start`: the empty first screen as this build has it. Here that is without Google, because the Mac build has no client.
      - `google`: the same screen with Google, set through `dev_set_google_available`.
      - `code`: the code step for "you@example.com".
      - `invalid`: the first screen with "phu@ẽample.com".
      - `switch`: the first screen after a 409, with "you@example.com".
      - `expired`: no dialog; the sidebar notice after a server sign-out.
    - The preview feeds the flow directly and makes no core call. Release builds always talk to `https://relay.shellx.pro`, and `dev/mac-shot.sh` cannot click or type.
39. **Digits and lengths copied from the core (supersedes the Python step of the old Task 1).**
    - `shellx_model::email_sign_in::DECIMAL_ZEROS` is the 65 values of `shellx_core::auth_email::DECIMAL_ZEROS` (Unicode 13), copied with that comment. The model crate does not link the core.
    - `EMAIL_MAX_LEN` equals `MAX_EMAIL_BYTES` (254).
    - Task 4 pins both equalities from `shellx-app`, which links both crates.
40. **Branch and worktree.** `feat/shellx-windows-signin-email` from `develop`, worktree `.worktrees/windows-signin-email`, one implementer.

## Where each check runs (design §5; D6)

Every command runs from the feature worktree's root, in a shell that starts with the build line (Global Constraints). Nothing here depends on GitHub Actions, which is blocked by billing, and nothing here runs on the VPS.

| # | Check | Command | Where | Baseline on `develop` c06834ec4e |
| --- | --- | --- | --- | --- |
| 1 | `shellx-model` tests | `(cd windows && cargo test --locked -p shellx-model)` | this Mac | 192 passed (2026-11-12) |
| 2 | `shellx-core` tests (Task 3) | `(cd shellx-core && cargo test --workspace --locked)` | this Mac | `test result: ok` |
| 3 | `shellx-app` release tests, with the real-core tests | `(cd windows && nice -n 19 cargo test --release --locked -p shellx-app)` | this Mac | 142 passed (2026-11-12) |
| 4 | `shellx-app` release build | `(cd windows && nice -n 19 cargo build --release --locked -p shellx-app)` | this Mac | about 5 min cold (5m08s in the main checkout, 2026-11-12); a new worktree has its own `windows/target` |
| 5 | Windows-target compile of `shellx-app` (Windows-only code, `cfg(windows)`) | F6, the foundations plan's Windows compile command; it compiles the committed `HEAD` | as F6 says: local Docker on this Mac, else its VPS fallback, which the orchestrator runs | after F6 is on `develop` (Task 9) |
| 6 | Lockfiles unchanged | `git diff --quiet develop...HEAD -- windows/Cargo.lock shellx-core/Cargo.lock && echo locks-unchanged` | this Mac | — |
| 7 | Secret and address scan | Task 9 Step 3 | this Mac | — |
| 8 | Twelve screenshots (six previews, en and vi) | Task 9 Step 4 (`dev/mac-shot.sh`) | this Mac, only if the shell has Screen Recording permission (it had none on 2026-11-12: "could not create image from window"); otherwise "not taken", and the preview switch stays for the user | — |
| 9 | Keyboard walk-through on the Mac build: Tab order, Return, Escape, Enter and Space on a focused button (macOS input methods, not Windows IMEs) | `(cd windows && SHELLX_LANG=en SHELLX_DEV_SIGN_IN=google target/release/shellx-desktop)`, keys by hand | the user (an agent cannot type into the window). Send code there reaches `relay.shellx.pro`, which answers "not available" until the relay is deployed | — |
| 10 | Real Windows: typing, Ctrl+V and IME (Windows Telex, Unikey, EVKey) in the email field and the code field, a pasted code, Tab and Escape, the notice, the dialog at 100, 125 and 150 % | by hand, the design's 10-step list (§5.3 step 10) and the sign-in items Task 9 hands over | the user's PC, from the test installer that the design's group 5 builds; a diagnostics report when something fails | — |
| 11 | Live sign-in with a mailed code | a release build once the relay with email sign-in is deployed, or a debug build on a Windows PC with `SHELLX_API_BASE=http://127.0.0.1:<port>` and a port forward (D7) | the user, with a real mailbox | — |

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

Used unchanged: `SwitchFromSignedInDevice` (equal to the catalog's `signin.error.switchFromSignedInDevice`), `RelayUnreachable` for `network` (D5 keeps the desktop's "Can't reach relay.shellx.pro"), `SigningIn`, `Cancel`, `ContinueWithGoogle`, `SignInTitle`, `SignInEllipsis`, `SwitchToGoogle`. Not added: `ContinueWithEmail` (D5).

`ServerProblem` and F4: if `Str` on the branch already has a variant whose en and vi are the catalog's `signin.error.server` (F4 added it before Task 1 runs), `email_error` uses that variant and Task 1 adds 15 variants instead of 16. If both branches add one, the merge in Task 7 Step 1 keeps the foundations' name.

Strings outside the catalog (Ruling 31):

| Win | Task | en | vi | Source |
| --- | --- | --- | --- | --- |
| `FirstSignInCreatesAccount` | 1 | No account yet? Your first sign-in creates one. | Chưa có tài khoản? Lần đăng nhập đầu tiên sẽ tạo tài khoản cho bạn. | design §4.1 (own wording) |
| `SessionExpired` | 6 | Your session expired. | Phiên đăng nhập đã hết hạn. | catalog `signin.expired`, first sentence |
| `SignInAgain` | 6 | Sign in again | Đăng nhập lại | catalog `signin.expired`, second sentence, as a button label |
| `MacsCannotHostYet` | 8 | ShellX for Mac doesn't accept connections from Windows PCs yet. The terminal on this PC works as usual. | ShellX cho Mac hiện chưa nhận kết nối từ máy tính Windows. Terminal trên máy này vẫn dùng bình thường. | design §4.5 (own wording) |
| `SignInOnYourMac` | 8 | Sign in to ShellX on your Mac with the same account to see it here. | Đăng nhập ShellX trên Mac bằng cùng tài khoản để thấy Mac ở đây. | design §4.5 (own wording) |
| ~~`NoOtherMachines`~~ | 8 | removed | removed | its only use is replaced (Ruling 31) |

Counts. `all_has_no_duplicates` asserts an absolute `Str::ALL.len()`. Each task sets it to the count on the branch before that task plus its own change:
- Task 1: +16, or +15 under the `ServerProblem` rule above. From `develop` c06834ec4e (109) that is 125.
- Task 6: +2.
- Task 8: +1 (two added, one removed).

After the merge in Task 7 Step 1, the number is the merged enum's.

## File structure

| File | Responsibility |
| --- | --- |
| `shellx-core/src/auth_google.rs`, `shellx-core/src/lib.rs`, `shellx-core/tests/auth_google.rs` (modify) | `auth.google.available` (Task 3) |
| `windows/shellx-model/src/email_sign_in.rs` (create) | `EmailStep`; the address and code rules; the auto-submit rule; which screen the dialog draws, its Tab order and what its key listener does |
| `windows/shellx-model/src/core_api.rs` (modify) | `EmailChallenge`, `email_begin`, `email_finish`, `SignInMethod::is_email`, `google_available` |
| `windows/shellx-model/src/strings.rs` (modify) | The String table's variants, `EmailAddress` en, `Lang::locale`, `sent_code_to`, `resend_code_in`, `email_error`, `sign_in_method_label` |
| `windows/shellx-model/src/account.rs` (modify) | The email run inside `AccountFlow`: events, actions, accessors; `session_ended_by_server` |
| `windows/shellx-model/src/account_view.rs` (create) | `AccountView` and `account_view`: what Settings › Account draws (Tasks 6–7) |
| `windows/shellx-model/src/sidebar.rs` (modify) | `may_request_access`, `request_any_mac`, `machine_picker`; `build_groups` takes `any_mac` (Task 8) |
| `windows/shellx-app/src/core_service.rs` (modify) | The two email actions' core calls, `run_google_check`, the real-core tests; the switch-offer marker removed |
| `windows/shellx-app/src/ui/text_field.rs` (modify) | `composing()`; the Mac-only `dev_set_text` |
| `windows/shellx-app/src/ui/account.rs` (modify) | Window-side methods over the flow; the Google check; `view`; the Mac-only previews |
| `windows/shellx-app/src/ui/login.rs` (modify) | The dialog: first screen, code step, focus and keys |
| `windows/shellx-app/src/ui/root.rs` (modify) | No self-opening dialog; preview switch; `request_any_mac`; the picker from the model |
| `windows/shellx-app/src/ui/sidebar.rs` (modify) | The "Sign in again" notice above the footer; the "+" list's rows and note |
| `windows/shellx-app/src/ui/settings.rs` (modify) | Method label; Settings › Account drawn from `account_view` |
| `windows/shellx-app/src/shell_info.rs`, `ui/mod.rs`, `windows/README.md` (modify) | `SHELL_STRINGS`; `text_field` used again; the developer switches |

---

### Task 0: Worktree and baselines (no code changes)

The build environment is ready on this Mac (2026-11-12):
- zig 0.16.0 is at `/opt/homebrew/opt/zig@0.16/bin/zig`;
- the `ghostty` submodule is initialised in the main checkout;
- `cargo build --release --locked -p shellx-app` and `cargo test --release --locked -p shellx-app` (142) pass.

This task only creates the worktree and records the baselines.

**Files:** none.

- [ ] **Step 1: Worktree.** Use superpowers:using-git-worktrees to create `.worktrees/windows-signin-email` on the new branch `feat/shellx-windows-signin-email` from `develop`. Every later path is relative to it. Do not initialise its `ghostty` submodule: the build line points `CMUX_GHOSTTY_SRC` at the main checkout's.
- [ ] **Step 2: Baselines.** Run, in one shell:

```bash
export PATH="/opt/homebrew/opt/zig@0.16/bin:$HOME/.cargo/bin:$PATH" CMUX_GHOSTTY_SRC="/Users/richard/Documents/helper/shellx/ghostty"
bash -c 'source scripts/ghostty-zig-version.sh && ghostty_require_compatible_zig /Users/richard/Documents/helper/shellx'
(cd windows && cargo test --locked -p shellx-model)
(cd shellx-core && cargo test --workspace --locked)
(cd windows && nice -n 19 cargo test --release --locked -p shellx-app)
(cd windows && nice -n 19 cargo build --release --locked -p shellx-app)
(cd windows && SHELLX_LANG=en dev/mac-shot.sh "$TMPDIR/shellx-baseline.png" 8)
```

Expected:
- `zig 0.16.0 found at /opt/homebrew/opt/zig@0.16/bin/zig`;
- `test result: ok. 192 passed` for `shellx-model`;
- `test result: ok` for every `shellx-core` test binary;
- `test result: ok. 142 passed` for `shellx-app`;
- a finished build, about 5 min cold, because this worktree has its own `windows/target`.

`dev/mac-shot.sh` prints either `mac-shot: wrote …` or `could not create image from window`. The second means no Screen Recording permission: do not change system settings, and record "screenshots: not taken" for Task 9. Record any failing test by name: it predates this plan.
- [ ] **Step 3: If a build fails for an environment reason** (zig, ghostty, disk): do not work around it. Stop and report the command and its last 30 lines to the orchestrator.

---

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
// The 15 email variants of the String table plus FirstSignInCreatesAccount (16; 15 under the ServerProblem rule)
// in Str, ALL and both arms of t(); Str::EmailAddress en "Email address"
pub fn sent_code_to(lang: Lang, email: &str) -> String;
pub fn resend_code_in(lang: Lang, secs: u64) -> String;   // whole seconds
/// The dialog's line for an email-path failure: the eight email sentences, `network` -> RelayUnreachable,
/// anything else -> ServerProblem (D2).
pub fn email_error(lang: Lang, code: &str) -> String;
/// Settings row title: "apple" -> AppleId, "email" -> EmailCodeMethod, anything else -> GoogleAccount.
pub fn sign_in_method_label(provider: &str) -> Str;
// email_sign_in.rs
pub const CODE_LEN: usize = 6;
/// The relay's longest address, in bytes (ASCII only); equal to `shellx_core::auth_email::MAX_EMAIL_BYTES` (Task 4 pins it).
pub const EMAIL_MAX_LEN: usize = 254;
/// The first code point of every run of ten Unicode decimal digits (Unicode 13): the 65 values of
/// `shellx_core::auth_email::DECIMAL_ZEROS` (`shellx-core/src/auth_email.rs:26-35`), copied with its doc comment (Ruling 39).
pub const DECIMAL_ZEROS: &[u32] = &[ /* the core's 65 values */ ];
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
/// D3's Tab order. Start -> [EmailField, SendCode, Google, Cancel], without Google when `google` is false
/// (the build has no Google client: Ruling 28). Code -> [CodeField, Verify, Resend, ChangeEmail, Cancel].
/// SigningIn -> [Cancel].
pub fn tab_order(screen: SignInScreen, google: bool) -> &'static [DialogFocus];
/// Where Tab (Shift+Tab with `back`) moves from `from`: the next (previous) entry of `order` that `enabled` accepts,
/// wrapping around; `from` when no other entry is accepted; the first accepted entry when `from` is not in `order`.
pub fn tab_target(order: &[DialogFocus], from: DialogFocus, back: bool, enabled: impl Fn(DialogFocus) -> bool) -> DialogFocus;
/// What the dialog card's own key-down listener does with a key that reached it (Ruling 30).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DialogKey { Pass, Close, Move { back: bool }, StartGoogle }
/// `holder`: the field or button that holds the keyboard, `None` for the dialog's own handle. `link`: the dialog
/// switches a password session to Google. `key`: GPUI's key name. `shift`: Shift held. `other`: Ctrl, Alt or Win held.
/// The listener stops propagation only for a result other than `Pass`.
pub fn dialog_key(holder: Option<DialogFocus>, link: bool, key: &str, shift: bool, other: bool) -> DialogKey;
```

`sign_in_screen`: `Some(Email)` → `Start { sending: false, google_waiting }`; `Some(Sending)` → `Code { busy: true }` with `has_sent_to`, else `Start { sending: true, google_waiting: false }`; `Some(Code)` → `Code { busy: false }`; `Some(Verifying)` → `Code { busy: true }`; `None` → `Start { sending: false, google_waiting: true }` when `google_waiting`, else `SigningIn` when `code_submitted && logging_in`, else `Start { sending: false, google_waiting: false }`.

`dialog_key`, in this order:
1. `other` → `Pass`. A field handles Ctrl+A/C/V/X itself, and the window root swallows the remaining chords.
2. `"escape"` → `Close`.
3. `"tab"`: a field holder → `Pass`, because the field already turned Tab into its own `Next` / `Prev` and stopped it. Any other holder, or `None` → `Move { back: shift }`.
4. `"enter"`: `holder == None && link` → `StartGoogle`. Anything else → `Pass`: a field turned Enter into `Submit` first, and GPUI clicks a focused button on key-up.
5. Every other key → `Pass`.

`code_digits` maps with `DECIMAL_ZEROS`, the zero code point of every `Nd` run (each run is ten consecutive code points valued 0–9, a Unicode stability guarantee): a character `c` with `z <= c < z + 10` for a zero `z` is the ASCII digit `c - z`. No crate (Global Constraints). The list is the core's, copied (Ruling 39).

- [ ] **Step 1: The catalog's strings.** Print the phone catalog's values: they are the expected values of this task's tests. Where one differs from the String table, the catalog wins; note it for the hand-off. Keys with an argument carry it in their name (`signin.email.sentTo %@`, `signin.email.resendIn %lld`). Also check the `ServerProblem` rule: `grep -n 'Thử lại sau\.' windows/shellx-model/src/strings.rs` finds the server sentence only if F4 already added it.

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

`strings.rs` changes:
- In `sign_in_strings_match_the_mac`, the `EmailAddress` en line becomes `"Email address"`; its 20 pairs stay.
- `all_has_no_duplicates` asserts the count before this task plus 16: 125 on `develop` c06834ec4e, or plus 15 under the `ServerProblem` rule.
- Add:

```rust
#[test] fn the_first_sign_in_line() {
    // t(Lang::En, Str::FirstSignInCreatesAccount) == "No account yet? Your first sign-in creates one."
    // t(Lang::Vi, Str::FirstSignInCreatesAccount) == "Chưa có tài khoản? Lần đăng nhập đầu tiên sẽ tạo tài khoản cho bạn."
}
#[test] fn email_strings_match_the_phone_catalog() {
    // pairs (Str, vi, en) for the 15 email variants, exactly the String table (the foundations' variant for
    // signin.error.server under the ServerProblem rule); assert_eq!(pairs.len(), 15); each t() equals its value
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
    // "http_502", "http_503", "http_504", "server", "invalid_device", "invalid_params", "bad_request", "internal_error",
    // "payload_too_large", "not_configured", "io", "crypto", "unknown_method", "" -> ServerProblem;
    // no result contains the code it was given (no "http_", no "_")
    // (google_error is not touched here: its fallback is F4's)
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
    // tab_order(Start { false, false }, true) == [EmailField, SendCode, Google, Cancel]; all accepted:
    //   EmailField -> SendCode -> Google -> Cancel -> EmailField; back from EmailField -> Cancel;
    //   SendCode refused: EmailField -> Google, back from Google -> EmailField;
    // tab_order(Start { false, false }, false) == [EmailField, SendCode, Cancel]: SendCode -> Cancel;
    // tab_order(Code { busy: false }, false) == tab_order(Code { busy: false }, true) == [CodeField, Verify, Resend, ChangeEmail, Cancel];
    //   Verify and Resend refused: CodeField -> ChangeEmail; tab_order(SigningIn, true) == [Cancel], from Cancel -> Cancel;
    // on the Start order, from Verify (not in it) -> EmailField
}
/// The 2026-10-31 "cannot type" defect: a key-down that the dialog stops never becomes WM_CHAR on Windows (R2 §1).
#[test] fn keys_the_dialog_does_not_act_on_pass_through() {
    // holders: None and Some(each of the eight DialogFocus); link false, then true:
    //   dialog_key(h, link, k, false, false) == Pass for k in ["a", "z", "0", "9", "space", "backspace", "delete", "left", "home", "end"]
    //   dialog_key(h, link, k, true, false) == Pass for k in ["a", "2"] (Shift+letter, Shift+digit: typed text)
    //   dialog_key(h, link, "v", false, true) == Pass; dialog_key(h, link, "a", false, true) == Pass (Ctrl chords)
    //   dialog_key(h, link, "escape", false, false) == Close; dialog_key(h, link, "escape", false, true) == Pass
    // enter: dialog_key(None, true, "enter", false, false) == StartGoogle; dialog_key(None, false, "enter", false, false) == Pass;
    //   dialog_key(Some(SendCode), false, "enter", false, false) == Pass; dialog_key(Some(EmailField), false, "enter", false, false) == Pass
    // tab: dialog_key(Some(SendCode), false, "tab", false, false) == Move { back: false };
    //   dialog_key(Some(Cancel), false, "tab", true, false) == Move { back: true }; dialog_key(None, false, "tab", false, false) == Move { back: false };
    //   dialog_key(Some(EmailField), false, "tab", false, false) == Pass; dialog_key(Some(CodeField), false, "tab", true, false) == Pass;
    //   dialog_key(Some(SendCode), false, "tab", false, true) == Pass (Ctrl+Tab)
}
```

- [ ] **Step 3: Run to verify they fail.** Run: `(cd windows && cargo test --locked -p shellx-model)`. Expected: compile errors (`email_begin`, `Str::ServerProblem`, `Str::FirstSignInCreatesAccount`, `code_digits`, `tab_order`, `dialog_key` missing).
- [ ] **Step 4: Commit the failing tests** (the `mod tests` edits and the test-only `email_sign_in.rs` with its `lib.rs` line). `git add windows/shellx-model/src && git commit -m "test(shellx-windows): email code core calls, strings and input rules"`
- [ ] **Step 5: Implement** the Interfaces.
- [ ] **Step 6: Run to verify they pass.** Run: `(cd windows && cargo test --locked -p shellx-model)`. Expected: `test result: ok` (192 plus the new tests), no new compiler warning.
- [ ] **Step 7: Commit.** `git add windows/shellx-model/src && git commit -m "feat(shellx-windows): email code core calls, strings and input rules"`

---

### Task 2: Model: the email steps in the account flow

The flow and the two `run_account_action` arms land together. `run_account_action` matches every `AccountAction` with no wildcard (`core_service.rs:145-193`), so new actions without their arms would leave `shellx-app` unbuildable between commits. `ui/account.rs:255-282` sends unknown actions to the serial worker through its catch-all and needs no change here. Step 5 compiles and tests the arms (build line).

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
- One sign-in flow at a time (Ruling 35). `EmailCodeRequested`, `EmailResendRequested` and `EmailCodeSubmitted` return `[]` and change nothing while `google_in_flight()` is `Some`, whatever the purpose. The core would run an email finish next to a waiting Google flow, so this guard stands even though no screen offers both.
- `reset_session()` does not touch the email run; a `ListResult` that enters `LoggedIn` drops it.
- `Debug` prints `"<redacted>"` for the address, the code and the `challenge_id` in the new events and actions; the run's `Debug` (inside `AccountFlow`'s) shows its step only.

D2's rows and the tests that pin them:

| D2 row | Test |
| --- | --- |
| 401 `invalid_code` on verify | `a_wrong_code_empties_the_field_and_stays_on_the_code_step` |
| 410 `code_expired` on verify | `an_expired_code_drops_the_challenge_and_unlocks_resend` |
| 409 `switch_from_signed_in_device` on verify | `a_switch_answer_returns_to_the_first_screen` |
| failed Resend, `rate_limited` or `network` | `a_failed_resend_keeps_the_challenge_for_rate_limited_and_network`; Task 4 `a_rate_limited_resend_through_the_real_core_keeps_the_code` |
| failed Resend, `email_send_failed`, `email_sign_in_disabled`, 404 | `a_failed_resend_drops_the_challenge_the_relay_lost`; Task 4 `a_failed_resend_through_the_real_core_drops_the_challenge` |
| 429 on Send code or Resend | `a_failed_send_returns_to_the_first_screen_with_the_error`; the second Resend of `a_failed_resend_keeps_…` |
| body-less 502 / 503 / 504, no sentence | Task 1 `email_error_maps_codes`; `http_503` in `a_failed_send_returns_…` |
| 429, network, body-less 5xx or `invalid_device` on verify (rows 6 and 7 on the verify side) | `a_verify_refused_for_rate_network_or_server_keeps_the_code` |
| 503 `email_sign_in_disabled`, 404 | `a_relay_without_email_sign_in_keeps_the_app_signed_out`; `a_disabled_relay_on_verify_keeps_the_code`; Task 1 `email_error_maps_codes`; Task 4 `a_relay_without_email_sign_in_answers_through_the_real_core` |

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
#[test] fn only_one_sign_in_flow_runs_at_a_time() { /* logged_out(); GoogleRequested(SignIn) -> [CallGoogleBegin(SignIn)]; begun(SignIn, "g1") -> [OpenBrowser(..), CallGoogleFinish("g1")]; now send() -> [], EmailCodeSubmitted("123456") -> [], EmailResendRequested -> [], email_step() None, google_in_flight() == Some(SignIn); finished("g1", Err(err("google_cancelled"))) -> google_in_flight() None, state LoggedOut; send() -> [CallEmailBegin { email: "Foo@Bar.com", locale: "vi" }] */ }
#[test] fn an_email_session_ended_by_the_server_signs_out() { /* the walk-through to LoggedIn; ListResult(Err(err("unauthorized"))) -> LoggedOut, auth_method() None, email() None, email_step() None (Task 6 adds the notice to this path) */ }
#[test] fn email_codes_addresses_and_challenges_never_in_debug() { /* with challenge id "CH-SECRET": Debug of send(), EmailBegun(Ok(..)), EmailCodeSubmitted("123456"), EmailFinished Ok, CallEmailBegin, CallEmailFinish and of the flow on the code step contains none of "foo@bar.com", "Foo@Bar.com", "123456", "CH-SECRET" */ }
```

- [ ] **Step 2: Run to verify they fail.** Run: `(cd windows && cargo test --locked -p shellx-model account::)`. Expected: compile errors (`EmailCodeRequested` missing).
- [ ] **Step 3: Commit the failing tests.** `git add windows/shellx-model/src/account.rs && git commit -m "test(shellx-windows): account flow email code steps"`
- [ ] **Step 4: Implement** the rules in `account.rs` and the two `run_account_action` arms in `core_service.rs` (imports `email_begin`, `email_finish`).
- [ ] **Step 5: Run to verify they pass.** Run, in one shell: the build line, then `(cd windows && cargo test --locked -p shellx-model && nice -n 19 cargo test --release --locked -p shellx-app)`. Expected:
  - `test result: ok` for both, every existing `account::tests` included;
  - `shellx-app` compiles the two new arms;
  - no new compiler warning.
- [ ] **Step 6: Commit.** `git add windows/shellx-model/src/account.rs windows/shellx-app/src/core_service.rs && git commit -m "feat(shellx-windows): account flow signs in with an email code"`

---

### Task 3: Core and window: Google only when the build has a Google client

**Files:**
- Modify: `shellx-core/src/auth_google.rs` (after `cancel`), `shellx-core/src/lib.rs` (`KNOWN_METHODS` :36-68, after `"auth.google.cancel"` :43; `dispatch` :151-212, after the `"auth.google.cancel"` arm :167)
- Test: `shellx-core/tests/auth_google.rs` (after `begin_requires_a_known_purpose_and_a_client_id` :50-64; its helpers `support::fake`, `support::state_dir`, `support::configure`, `support::google`)
- Modify: `windows/shellx-model/src/core_api.rs` (wrapper after `google_cancel`; tests)
- Modify: `windows/shellx-app/src/core_service.rs` (after `run_version_check` :196-200), `windows/shellx-app/src/ui/account.rs` (`Job` / `Done` :30-38, the worker :61-76, the result loop :77-88, `new` :114-117, accessors)

**Interfaces:**
- Consumes: `shellx_core::config::Config.google_client_id` / `.google_client_secret` (`shellx-core/src/config.rs:20-21`).
- Produces:

```rust
// shellx-core/src/auth_google.rs
/// `auth.google.available {}` -> `{"available": bool}`: true when `cfg` has a non-empty Google desktop client id
/// and secret (from `config.set`, the environment or the build). Sends nothing; needs no session (Ruling 28).
pub fn available(cfg: &Config) -> Value;
// shellx-core/src/lib.rs: "auth.google.available" in KNOWN_METHODS and in dispatch (no params checked; any object or null)
// windows/shellx-model/src/core_api.rs
/// `auth.google.available`: whether this build can sign in with Google.
pub fn google_available(core: &dyn CoreCall) -> Result<bool, CoreErr>;   // sends {} ; reads "available"
// windows/shellx-app/src/core_service.rs
/// `Some(answer)`, or `None` when the core could not answer (asked again later; Google stays hidden meanwhile).
pub fn run_google_check(core: &dyn CoreCall) -> Option<bool>;
// windows/shellx-app/src/ui/account.rs: Job::GoogleCheck, Done::Google(Option<bool>), field google: Option<bool>
/// The core said this build has a Google client. False until it answered yes.
pub fn google_available(&self) -> bool;
/// Queues `Job::GoogleCheck` when the answer is unknown and no check is queued. `new` calls it once after `Started`;
/// the dialog calls it on open (Task 5).
pub fn check_google(&mut self, cx: &mut Context<Self>);
```

- [ ] **Step 1: Write the failing tests.** `shellx-core/tests/auth_google.rs`:

```rust
#[test] fn google_available_needs_a_client_id_and_secret() {
    // a fresh Core: call("auth.google.available", json!({})) -> Err code "not_configured" (config.set never ran);
    // for (id, secret, want) in [("", "", false), ("fake-desktop-client", "", false), ("", "fake-desktop-secret", false),
    //                            ("fake-desktop-client", "fake-desktop-secret", true)]:
    //   extra = support::google(&fake) with google_client_id = id and google_client_secret = secret (explicit "", so the
    //   environment and the build cannot decide); support::configure(..); call("auth.google.available", json!({}))
    //   == Ok(json!({"available": want}));
    // fake.requests().is_empty() (no request), and no session.json in the state dir
}
```

`windows/shellx-model/src/core_api.rs`:

```rust
#[test] fn google_available_reads_the_core_answer() {
    // FakeCore with auth.google.available -> {"available": true}: google_available(&f) == Ok(true), sent ("auth.google.available", {});
    // -> {"available": false}: Ok(false); -> Err(unknown_method) (an older core): Err with that code;
    // -> {} : Err code "bad_response"
}
```

- [ ] **Step 2: Run to verify they fail.** Run, in one shell: the build line, then `(cd shellx-core && cargo test --locked --test auth_google google_available)` and `(cd windows && cargo test --locked -p shellx-model core_api::)`. Expected: the core test fails on its first assertion (`unknown_method` where `not_configured` is expected), and the model fails to compile (`google_available` missing).
- [ ] **Step 3: Commit the failing tests.** `git add shellx-core/tests/auth_google.rs windows/shellx-model/src/core_api.rs && git commit -m "test(shellx-core): auth.google.available tells whether the build has a Google client"`
- [ ] **Step 4: Implement** `auth_google::available` and its `KNOWN_METHODS` and `dispatch` entries, the model wrapper, `run_google_check`, and the `AccountService` check. The `AccountService` part:
  - The worker answers `Job::GoogleCheck` with `Done::Google(run_google_check(core))`.
  - `Done::Google(Some(b))` sets `google = Some(b)`; `Done::Google(None)` leaves it `None`. Either way the queued flag clears and the service notifies.
  - `new` calls `check_google` right after `apply(Started)` and before `check_update`.
- [ ] **Step 5: Run to verify they pass.** Run, in one shell: the build line, then `(cd shellx-core && cargo test --workspace --locked)`, `(cd windows && cargo test --locked -p shellx-model)` and `(cd windows && nice -n 19 cargo test --release --locked -p shellx-app)`. Expected: `test result: ok` everywhere, and no new compiler warning.
- [ ] **Step 6: Commit.** `git add shellx-core/src windows/shellx-model/src/core_api.rs windows/shellx-app/src && git commit -m "feat(shellx-windows): ask the core whether this build can sign in with Google"`

---

### Task 4: The email and Google checks through the real core

**Files:**
- Modify: `windows/shellx-app/src/core_service.rs` (tests after :535)

**Interfaces:**
- Consumes:
  - Task 2's events, actions and accessors; Task 3's `run_google_check`; the existing test helpers `drive`, `cfg`, `facts` and `FakeGoogleCore` (`core_service.rs:234-260`, `:470-490`).
  - The fake API. Its names were checked against `shellx-core/fake-api/src/lib.rs` on `develop` c06834ec4e:
    - `FakeOptions.email_sign_in: bool` (false: `/code` answers 503 `email_sign_in_disabled`) and `FakeOptions.email_routes: bool` (false: both routes answer 404, an old relay); both default to true.
    - `FakeApi::email_code(&self, email: &str) -> Option<String>`: the live code mailed to that address.
    - `FakeApi::email_locale(&self, email: &str) -> Option<String>`: that mail's language, `"vi"` only for exactly `vi`.
    - `FakeApi::set_next_email_code(&self, code: &str)`: the next challenge's code, once.
    - `FakeApi::expire_email_codes(&self)`: every live challenge answers 410, no guess counted.
    - `FakeApi::fail_next_mail(&self)`: the relay's 502 `email_send_failed`, which leaves the address with no live code.
    - `FakeApi::fail_next(&self, path: &str, status: u16, code: &str)`: one scripted answer that changes no challenge (the relay's 429).
  - `shellx_core::auth_email::{DECIMAL_ZEROS, MAX_EMAIL_BYTES}`.
- Produces: nothing new for later tasks.

The fake's machine list carries `noise_public_key_b64` until F5 is merged in Task 7. After that the core's `fingerprint` is null and F1 parses it. These tests reach `LoggedIn` either way.

- [ ] **Step 1: Write the tests** (`drive`, `cfg`, `facts` exist):

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
#[test] fn an_expired_code_through_the_real_core_unlocks_resend() {
    // default fake: Started at 0; EmailCodeRequested { "foo@bar.com", "en" } at 1 -> Some(Code); code = api.email_code(..).unwrap();
    // api.expire_email_codes() (a relay restart or deploy); drive EmailCodeSubmitted(code) at 2_000 ->
    // email_error() code "code_expired", email_step() == Some(Code), !email_can_verify(), email_resend_wait_secs(2_000) == 0,
    // state LoggedOut; drive EmailResendRequested at 2_000 -> Some(Code), email_can_verify(), and the new api.email_code(..) signs in
}
/// Ruling 28 through the real core: the build's client decides, never the network.
#[test] fn google_availability_through_the_real_core() {
    // ConfiguredCore over FakeGoogleCore (config.set gets the fake client id and secret): run_google_check(&core) == Some(true);
    // over a NoGoogleCore wrapper (same shape as FakeGoogleCore, but sets google_client_id and google_client_secret to ""):
    // run_google_check(&core) == Some(false); over a ConfiguredCore whose make_config returns Err(state_dir): None;
    // api.requests() has no request for any of them
}
/// Ruling 39: the model's copies equal the core's.
#[test] fn the_model_maps_digits_and_lengths_like_the_core() {
    // assert_eq!(shellx_model::email_sign_in::DECIMAL_ZEROS, shellx_core::auth_email::DECIMAL_ZEROS);
    // assert_eq!(shellx_model::email_sign_in::EMAIL_MAX_LEN, shellx_core::auth_email::MAX_EMAIL_BYTES);
    // for s in ["１２３４５６", "١٢٣٤٥٦", "۱۲۳۴۵۶", "१२३४५६", " 123 456\n", "004217"]:
    //   shellx_model::email_sign_in::code_digits(s) == shellx_core::auth_email::clean_code(s)
}
```

- [ ] **Step 2: Run them.** Run, in one shell: the build line, then `(cd windows && nice -n 19 cargo test --release --locked -p shellx-app core_service::)`. Expected: the seven new tests pass at the first run, because they drive code that Tasks 1–3 committed after their red runs. A failure here is a bug: commit the failing test first, then the fix.
- [ ] **Step 3: Run both suites.** Run, in one shell: the build line, then `(cd windows && nice -n 19 cargo test --release --locked -p shellx-app && cargo test --locked -p shellx-model)`. Expected: `test result: ok` for both, including `account_session_against_fake_api`, `google_session_against_fake_api` and `smoke_account_flow`.
- [ ] **Step 4: Commit.** `git add windows/shellx-app/src/core_service.rs && git commit -m "test(shellx-windows): email sign-in and the Google check through the real core"`

---

### Task 5: App: the email-first dialog, Settings label, previews

**Files:**
- Modify: `windows/shellx-app/src/ui/text_field.rs` (after `set_disabled` :80-86)
- Modify: `windows/shellx-app/src/ui/account.rs` (module comment :8-11, after `cancel_google` :161-164)
- Modify: `windows/shellx-app/src/ui/login.rs` (the whole dialog, module comment :1-12; `on_key_down` :142-154 is replaced)
- Modify: `windows/shellx-app/src/ui/mod.rs:18-20` (`text_field` is used again: drop its comment and `#[allow(dead_code)]`; put the attribute back only if the build then warns)
- Modify: `windows/shellx-app/src/ui/settings.rs:238-242` (the row title)
- Modify: `windows/shellx-app/src/ui/root.rs` (end of `RootView::new` :214-215)
- Modify: `windows/README.md` ("Run the window on a Mac" only; Ruling 37)

**Interfaces:**
- Consumes:
  - Task 1: `sign_in_screen`, `SignInScreen`, `DialogFocus`, `tab_order`, `tab_target`, `dialog_key`, `DialogKey`, `auto_submit`, `code_digits`, `email_looks_valid`, `email_text_refused`, `email_error`, `sent_code_to`, `resend_code_in`, `sign_in_method_label`, `Lang::locale`.
  - Task 2: the flow's events and accessors.
  - Task 3: `AccountService::google_available`, `check_google`.
  - `TextField` / `TextFieldEvent`, `button`, `google_button`.
  - `google_error`: F4 makes its fallback a sentence; this task calls it as today.
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
/// Mac development build only: the `google` preview shows the Google button although this build has no client.
#[cfg(target_os = "macos")] pub fn dev_set_google_available(&mut self, on: bool, cx: &mut Context<Self>);
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
/// Mac development build only: `SHELLX_DEV_SIGN_IN=start|google|code|invalid|switch` opens the sign-in dialog on that
/// screen (Ruling 38; Task 6 adds `expired`).
#[cfg(target_os = "macos")] fn dev_sign_in_preview(&mut self, window: &mut Window, cx: &mut Context<Self>);
```

Dialog rules. `GooglePurpose::Link` is unchanged, except that its Enter now comes through `dialog_key`.

For `SignIn`:
- The screen is `sign_in_screen(account.email_step(), account.email_sent_to().is_some(), account.google_in_flight().is_some(), self.code_submitted, account.signing_in())`.
- `google` is `account.google_available()` (Ruling 28).
- `composing` is the field's `composing()`.
- `started` (today's flag) means this dialog started Google.

The screens:
- `Start { sending, google_waiting }`, top to bottom:
  1. The title.
  2. A small muted line `FirstSignInCreatesAccount` (design §4.1).
  3. `email_field`, disabled while `sending`.
  4. The email line:
     - nothing while Google's error line (below) shows (D3: one failure at a time);
     - else `account.email_error()` worded by `email_error`;
     - else `t(lang, InvalidEmail)` while `!composing && email_text_refused(text)`.
  5. `button("sign-in-send-code", SendCode, Kind::Primary, sending || google_waiting || !account.accepts_login() || composing || !email_looks_valid(text))`, as wide as the field. It calls `email_send_code(text.trim().to_string(), lang.locale(), cx)` and clears `started`.
  6. Only while `google`:
     - a centred muted `OrDivider`;
     - the Google button as today. While `sending`, its handler is off and it is drawn at reduced opacity. While `google_waiting`, "Waiting for Google…" and the hint show instead;
     - Google's error line under it, by today's rule (`started && !google_waiting`), worded by `google_error`.
  7. Cancel, right-aligned.

  Without `google`, nothing Google-related is drawn, and Google's error line cannot show.
- `Code { busy }`: a wrapping `text_hi` block `sent_code_to(lang, address)`; `code_field` (disabled while `busy || !account.email_can_verify()`); the error line `email_error(lang, code)`; `button("sign-in-verify", VerifyCode, Kind::Primary, busy || composing || !account.email_can_verify() || code_digits(text).is_none())`, as wide as the field, calling `email_submit_code(text, cx)` and setting `code_submitted`; on its own line `button("sign-in-resend", <label>, Kind::Secondary, busy || composing || wait > 0)` (label `resend_code_in(lang, wait)` while `wait = account.email_resend_wait_secs()` is above 0, else `ResendCode`); on its own line `button("sign-in-change-email", UseDifferentEmail, Kind::Secondary, busy || composing)`; Cancel.
- `SigningIn`: one `text_hi` line `Str::SigningIn`; Cancel.
- Click handlers are attached only to enabled buttons (`button` leaves `on_click` to the caller, `ui/button.rs:16`).
- Keys (Ruling 30):
  - Field events. `Submit` from the email field runs Send code, and from the code field runs Verify, each only when its button is enabled. `Cancel` from either field closes.
  - Tab moves. `Next` / `Prev` from a field, and `DialogKey::Move { back }`, move the keyboard to `tab_target(tab_order(screen, google), from, back, enabled)`:
    - `from` is the control that holds the keyboard;
    - `enabled` is the drawn state: a field when it is not disabled, a button when it is not disabled, Cancel always.
  - The card's listener. The dialog root's `on_key_down` replaces today's `on_key_down`. It computes `holder`: `None` when the dialog's own handle is focused (`self.focus.is_focused(window)`), else `Some(self.focused)`. It then acts on `dialog_key(holder, purpose == Link, key, shift, ctrl || alt || platform)`:
    - `Close` → `close`;
    - `Move` → as above;
    - `StartGoogle` → today's `start`;
    - `Pass` → nothing. It does not stop propagation, so typed text reaches the platform's text path.

    It calls `cx.stop_propagation()` only for the other three.
  - Buttons. They get a `FocusHandle` (`.track_focus(&handle)` on the `Stateful<Div>` that `button` returns) and no key listener. GPUI clicks a focused element with `on_click` when Enter or Space goes up (`gpui-0.2.2/src/elements/div.rs:2178-2200`). Click handlers are attached only to enabled buttons, so a disabled focused button does nothing.
  - A focused button draws a 2 px `palette::PRIMARY_LINE` border, the focused text field's colour.
- Focus:
  - On open:
    - For `SignIn`, `open()` calls `account.check_google(cx)`, sets `focused = EmailField` and gives it the keyboard. The dialog's own handle gets it only for `Link`.
    - `focus_target()` is the handle of `focused` on `Start` and `Code`, Cancel's on `SigningIn`, and the dialog's own for `Link`.
  - Following the keyboard:
    - `focused` follows the keyboard: Tab moves, screen changes, and a click into a field or onto a button (observed with `cx.on_focus` on each handle).
    - For `SignIn`, when the dialog's own handle receives the keyboard (a click on the card or the backdrop: GPUI focuses a `track_focus` element on any mouse button), `cx.on_focus(&self.focus, …)` gives it back to `focused`'s handle. Typed text then still reaches the field (Ruling 30).
  - Screen changes. When the account changes and the screen kind differs from `shown`:
    - entering `Code` sets `focused = CodeField`;
    - entering `Start` sets `focused = EmailField`, and the email field keeps its text;
    - entering `SigningIn` sets `focused = Cancel`.

    Then `shown` is updated and `SignInEvent::Opened` is emitted, so RootView moves the keyboard (`ui/root.rs:185-187` → `focus_terminal`). When `google` becomes false while `focused == Google`, `focused = EmailField`.
- Fields: whenever the account or the code field changes, if `account.email_code_epoch() != code_epoch_seen` and `!code_field.composing()`: `code_field.clear()`, `last_auto = None`, `code_epoch_seen` updated (a composition open at that moment defers the clear to its end). The email field is cleared only by `open()` and `close()`. Each field is observed: a change redraws. `TextField` notifies on clicks, cursor moves and selections too, so an edit of `email_field` is a text that differs from `email_text_seen`: the dialog then stores the new text in `email_text_seen`, clears `started` (Ruling 21) and calls `account.email_edited(cx)` (D4: the InvalidEmail sentence replaces a stale failure). A change of `code_field` submits `auto_submit(self.last_auto.as_deref(), text, account.email_can_verify() && !busy && !composing)` when it is `Some`, remembering it in `last_auto` and setting `code_submitted`.
- The resend countdown repaints through a detached task started whenever the screen becomes `Code { busy: false }`: wait one second, `cx.notify()`, repeat while the dialog is open on that screen and `email_resend_wait_secs() > 0`.
- `open()` and `close()` clear both fields, `last_auto`, `code_submitted`, `started` and `email_text_seen`, and set `code_epoch_seen` to the account's epoch; `close()` also calls `account.email_cancel(cx)`. The dialog still closes itself at `LoggedIn`.
- The module comments `login.rs:1-12` and `ui/account.rs:8-11` no longer say sign-in is Google only.

Settings: the row title is `t(lang, sign_in_method_label(&m.provider))`; the address line, "Added from" and the Apple-only Remove button are unchanged.

`dev_sign_in_preview` is called last in `RootView::new`, under `cfg(target_os = "macos")`. For `SHELLX_DEV_SIGN_IN` equal to `start`, `google`, `code`, `invalid` or `switch`:
1. For `google` only: `account.dev_set_google_available(true, cx)`.
2. `open_sign_in(GooglePurpose::SignIn, window, cx)`.
3. Then:
   - `code` and `switch`: `account.dev_preview_email(value, cx)`;
   - `invalid`: `sign_in.dev_fill_email("phu@ẽample.com")`;
   - `switch`: also `sign_in.dev_fill_email("you@example.com")`.

Any other value does nothing.

README: in "Run the window on a Mac", add `SHELLX_DEV_SIGN_IN=start|google|code|invalid|switch`. It is for the Mac development build only: it opens the sign-in dialog on that screen for screenshots, with a made-up address and no network call. Task 6 adds `expired` to the same line. The user-facing description of sign-in and the checklist are the docs group's (Ruling 37).

- [ ] **Step 1: Implement** the `TextField` additions, the `AccountService` methods, the dialog, the Settings title, the preview switch and the README line. This task's logic is `sign_in_screen`, `tab_order`, `tab_target`, `dialog_key`, `auto_submit` and the flow, all tested in Tasks 1–4. GPUI views have no test harness here, so this task's checks are the build, the suites and reading the key listener against Ruling 30.
- [ ] **Step 2: Build and run the suites.** Run, in one shell: the build line, then `(cd windows && nice -n 19 cargo build --release --locked -p shellx-app && nice -n 19 cargo test --release --locked -p shellx-app && cargo test --locked -p shellx-model)`. Expected: the build finishes with no new warning; `test result: ok` twice.
- [ ] **Step 3: Read the key path once more.** `grep -n 'stop_propagation' windows/shellx-app/src/ui/login.rs`. Expected: every match sits under a `DialogKey::Close`, `Move` or `StartGoogle` arm, or under a `TextFieldEvent` handler; none is reached for `DialogKey::Pass`. `grep -n 'on_key_down\|on_key_up' windows/shellx-app/src/ui/login.rs` shows one listener, on the dialog root, and none on a button.
- [ ] **Step 4: Screenshots, only if Task 0 recorded the Screen Recording permission.** Otherwise skip; Task 9 reports "not taken". If `~/.local/share/shellx-native/core/session.json` exists (an earlier manual sign-in), move it aside first and put it back afterwards: with a session the dialog closes at once. Run:

```bash
cd windows
for lang in en vi; do for screen in start google code invalid switch; do
  SHELLX_LANG=$lang SHELLX_DEV_SIGN_IN=$screen dev/mac-shot.sh "$TMPDIR/shellx-signin-$screen-$lang.png" 8
done; done
```

Expected: ten lines `mac-shot: wrote …`. Open each PNG:
- `start`: the title, the first-sign-in line, the field with "Email address", "Send code" (disabled) and "Cancel". No "or", no Google button.
- `google`: the same, plus "or" and the white Google button above "Cancel".
- `code`: "We sent a 6-digit code to you@example.com. If it isn't there in a minute, check your spam folder." wrapped inside the card, the code field, "Verify" (disabled), "Resend code in 5x s" (disabled), "Use a different email" and "Cancel".
- `invalid`: "phu@ẽample.com" in the field, "That doesn't look like an email address." under it, and "Send code" disabled.
- `switch`: "you@example.com" in the field, the switch sentence wrapped under it, and "Send code" enabled.
- The `vi` shots show the tables' Vietnamese.
- No clipped or overlapping text inside the 340 px card.

Fix what is off and repeat Steps 2–4. Keep the PNGs for the hand-off; do not commit them.
- [ ] **Step 5: Commit.** `git add windows/shellx-app/src/ui windows/README.md && git commit -m "feat(shellx-windows): email-first sign-in dialog, Google only with a client"`

---

### Task 6: No dialog by itself: the "Sign in again" notice

**Files:**
- Modify: `windows/shellx-model/src/account.rs`:
  - the field `signed_out_by_server` :230 and :261;
  - `take_signed_out_by_server` :328-331, replaced;
  - the server sign-out arm :453-464;
  - entering `LoggedIn` :413-434;
  - the test `server_sign_out_shows_sign_in` :1536-1562, replaced.
- Create: `windows/shellx-model/src/account_view.rs`; modify `windows/shellx-model/src/lib.rs` (`pub mod account_view;`)
- Modify: `windows/shellx-model/src/strings.rs` (two variants; `all_has_no_duplicates`)
- Modify: `windows/shellx-app/src/ui/account.rs`:
  - remove `take_signed_out_by_server` :204-207 and `take_google_switch_offer` :209-214, with their imports :23-25;
  - add `session_ended_by_server` and `view`;
  - extend `dev_preview_email`.
- Modify: `windows/shellx-app/src/core_service.rs`: remove `GOOGLE_SWITCH_MARKER` :46-47, `take_once` :49-59 and the test `take_once_is_true_only_the_first_time` :462-468.
- Modify: `windows/shellx-app/src/ui/root.rs` (`account_changed` :387-396; `dev_sign_in_preview`), `windows/shellx-app/src/ui/sidebar.rs` (`render` :109-121, a notice block before `footer`), `windows/shellx-app/src/ui/settings.rs` (`account_section` :114-217), `windows/README.md` (the preview line)

**Interfaces:**
- Consumes: Task 2's flow; Task 5's `dev_sign_in_preview` and `dev_preview_email`.
- Produces:

```rust
// account.rs (replaces take_signed_out_by_server)
/// The server ended this session while it was signed in (a 401, or `not_logged_in` while LoggedIn). Stays true until
/// the flow next enters LoggedIn; reading it changes nothing (Ruling 29).
pub fn session_ended_by_server(&self) -> bool;
// account_view.rs
/// What Settings › Account draws (Ruling 33). Task 7 adds sign_out, google_switch and error.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AccountView {
    /// The sign-in button's label: SignInAgain after a server sign-out, else SignInEllipsis; None while LoggedIn.
    pub sign_in: Option<Str>,
    /// "Your session expired." above the button.
    pub session_expired: bool,
}
pub fn account_view(flow: &AccountFlow) -> AccountView;
// strings.rs: Str::SessionExpired, Str::SignInAgain (the String table)
// ui/account.rs
pub fn session_ended_by_server(&self) -> bool;
pub fn view(&self) -> AccountView;   // account_view(&self.flow)
```

Rules:
- `RootView::account_changed` keeps closing the remote sessions and no longer opens the dialog: both branches of `ui/root.rs:387-396` go.
- Sidebar notice. While `account.session_ended_by_server()`, the sidebar draws a block between the list and `footer`, with `border_t_1` in `theme::line()`, padding like the footer's, and a column of:
  - a muted `SMALL_SIZE` wrapping line `SessionExpired`;
  - `button("sidebar-sign-in-again", SignInAgain, Kind::Secondary, false)`, whose `on_click` calls `root.open_sign_in(GooglePurpose::SignIn, window, cx)`.

  It holds no focus handle, so the keyboard stays where it was.
- Settings › Account takes the sign-in button's label and the line from `account.view()`:
  - `SessionExpired` muted, above the button, while `session_expired`;
  - the button `settings-sign-in` labelled `t(lang, view.sign_in)` while it is `Some`.
- Settings' Google-switch row is unchanged here (Task 7 gates it).
- The `expired` preview (Mac only): `dev_sign_in_preview` handles `expired` without opening the dialog. It calls `account.dev_preview_email("expired", cx)`, which feeds the flow, dropping every returned action:
  1. the `code` preview's events;
  2. `EmailCodeSubmitted("123456")`;
  3. `EmailFinished` `Ok` for "you@example.com" with auth method `email`;
  4. `ListResult(Ok(vec![shell_info::this_machine(None)]))`;
  5. `ListResult(Err(CoreErr::new("unauthorized", "")))`.

  The real startup list answer (`not_logged_in`) may arrive before or after these events; either way the flow ends `LoggedOut` with the notice. The README's preview line gains `expired`.

- [ ] **Step 1: Write the failing tests.** `account.rs` (replace `server_sign_out_shows_sign_in`, keeping its three codes and its startup assertions):

```rust
#[test] fn a_server_sign_out_shows_the_notice_until_the_next_sign_in() {
    // for code in ["not_logged_in", "unauthorized", "http_401"]: logged_in(); ListResult(Err(err(code))) -> LoggedOut,
    //   session_ended_by_server() true, and still true when read again; Tick(…) and Started leave it true;
    //   then the email walk-through: send() (still true), begun, submit, finished Ok (still true),
    //   ListResult(Ok([m("me", true)])) -> LoggedIn, false
    // a fresh flow: Started; ListResult(Err(err("not_logged_in"))) -> LoggedOut, session_ended_by_server() false
    // logged_in(); LogoutRequested; LogoutResult(Ok(())) -> LoggedOut, false (the person signed out)
}
```

`account_view.rs`:

```rust
#[test] fn account_view_offers_sign_in_again_after_a_server_sign_out() {
    // AccountFlow::new() -> AccountView { sign_in: Some(SignInEllipsis), session_expired: false };
    // logged_in() -> { sign_in: None, session_expired: false };
    // logged_in() then ListResult(Err(unauthorized)) -> { sign_in: Some(SignInAgain), session_expired: true };
    // that flow signed in again (Google walk-through to LoggedIn) -> { sign_in: None, session_expired: false }
}
```

`strings.rs`: `sign_in_again_strings` asserts the String table's en and vi for `SessionExpired` and `SignInAgain`. `all_has_no_duplicates` asserts the count before this task plus 2.
- [ ] **Step 2: Run to verify they fail.** `(cd windows && cargo test --locked -p shellx-model)`. Expected: compile errors (`session_ended_by_server`, `account_view`, `Str::SessionExpired` missing).
- [ ] **Step 3: Commit the failing tests.** `git add windows/shellx-model/src && git commit -m "test(shellx-windows): a server sign-out shows a sign-in-again notice instead of a dialog"`
- [ ] **Step 4: Implement** the model, then the window side (the Rules above), including the removals in `ui/account.rs` and `core_service.rs`.
- [ ] **Step 5: Run to verify they pass.** Run, in one shell: the build line, then `(cd windows && cargo test --locked -p shellx-model && nice -n 19 cargo test --release --locked -p shellx-app && nice -n 19 cargo build --release --locked -p shellx-app)`. Expected:
  - `test result: ok` twice and a finished build, with no new warning;
  - `grep -rn 'take_signed_out_by_server\|take_google_switch_offer\|GOOGLE_SWITCH_MARKER\|take_once' windows/shellx-app/src windows/shellx-model/src` prints nothing.
- [ ] **Step 6: Commit.** `git add windows/shellx-model/src windows/shellx-app/src windows/README.md && git commit -m "feat(shellx-windows): sign in again from a notice; the dialog never opens by itself"`

---

### Task 7: Settings › Account: sign-out with any stored session, sentences, Google switch only with Google

Needs F3 and F4, so the foundations' rules part must be on `develop`.

**Files:**
- Modify: `windows/shellx-model/src/account_view.rs`
- Modify: `windows/shellx-app/src/ui/account.rs` (`view`), `windows/shellx-app/src/ui/settings.rs` (`account_section`, `methods_block`'s notice)

**Interfaces:**
- Consumes: F3 (`has_session`), F4 (`account_error`), Task 3's `google_available`, Task 6's `AccountView`.
- Produces:

```rust
// account_view.rs: AccountView gains
    /// "Sign out": F3 says a session is stored (LoggedIn, and an Error or LoggingIn with a session).
    pub sign_out: bool,
    /// "Switch to Google sign-in": needs_google_switch() and the build has a Google client.
    pub google_switch: bool,
    /// The line under the account, as a sentence: the notice (a failed logout, a methods failure), else an
    /// AccountState::Error; F4's wording; never a code, never CoreErr.message.
    pub error: Option<String>,
// the function takes the Google answer and the language now
pub fn account_view(flow: &AccountFlow, google_available: bool, lang: Lang) -> AccountView;
// ui/account.rs
pub fn view(&self, lang: Lang) -> AccountView;   // account_view(&self.flow, self.google_available(), lang)
```

Settings › Account draws only from `view`:
- the email or "Signed in" line, and `SignInSubtitle`, as today;
- the switch row while `google_switch`;
- the methods block while signed in;
- `error` in the error colour;
- the sign-in button and the notice (Task 6);
- "Sign out" while `sign_out`, calling `logout` as today.

The `CoreErr.message` line (`settings.rs:126-141`) and the methods notice's `sign_in_methods_error` call go. The methods notice now reads F4's sentence.

- [ ] **Step 1: Bring in the foundations.** From the main checkout, check that F1–F5 are on `develop` (the three checks under "Consumed from the foundations plan"). If they are not, stop and report: Tasks 7–9 wait. Read the foundations plan's Interfaces block, and use its names for F3 and F4 wherever this plan writes `has_session` and `account_error`. In the worktree: `git merge --no-edit develop`, never a rebase or a force-push. Resolve the conflicts:
  - keep both plans' `Str` variants, one server sentence (the foundations' name), and the summed `Str::ALL` count;
  - give `MachineInfo` literals F2's field;
  - keep both plans' `AccountFlow` fields and tests.

  Then, in one shell: the build line, then `(cd windows && cargo test --locked -p shellx-model && nice -n 19 cargo test --release --locked -p shellx-app)` and `(cd shellx-core && cargo test --workspace --locked)`. Expected: `test result: ok` everywhere, with Task 4's tests now running against F5's machine list. Commit the merge.
- [ ] **Step 2: Write the failing tests** in `account_view.rs`:

```rust
#[test] fn account_view_offers_sign_out_whenever_a_session_is_stored() {
    // LoggedIn -> sign_out; LoggedOut and Unknown -> !sign_out;
    // the state F3's own tests call "an error with a stored session" (built the same way: LoginSubmitted, LoginResult(Ok),
    //   ListResult(Err(err("bad_response"))) = R4 Blocker 1's path) -> sign_out and sign_in Some(SignInEllipsis)
}
#[test] fn account_view_words_errors_as_sentences() {
    // Error(CoreErr::new("bad_response", "machines.list: invalid type: null, expected a string")) -> error == Some(account_error(lang, ..)),
    //   and it contains neither "bad_response" nor "machines.list"; the same for a failed logout notice (code "network") and
    //   a methods notice (code "http_502"); both languages; LoggedIn with no notice -> error None
}
#[test] fn account_view_offers_the_google_switch_only_with_google() {
    // a password session (LoggedIn, SessionResult auth_method "password"): google_switch == google_available for both values;
    // a google or email session: google_switch false either way
}
```

  Update `account_view_offers_sign_in_again_after_a_server_sign_out` to the new signature: `google_available` false, `Lang::En`.
- [ ] **Step 3: Run to verify they fail.** `(cd windows && cargo test --locked -p shellx-model account_view::)`. Expected: compile errors (`sign_out`, `google_switch`, `error` missing; `account_view` takes one argument).
- [ ] **Step 4: Commit the failing tests.** `git add windows/shellx-model/src/account_view.rs && git commit -m "test(shellx-windows): Settings account offers sign-out with any stored session and words errors"`
- [ ] **Step 5: Implement** `account_view`, `AccountService::view` and Settings › Account as above.
- [ ] **Step 6: Run to verify they pass.** Run, in one shell: the build line, then `(cd windows && cargo test --locked -p shellx-model && nice -n 19 cargo test --release --locked -p shellx-app && nice -n 19 cargo build --release --locked -p shellx-app)`. Expected:
  - `test result: ok` twice and a finished build;
  - `grep -n 'e.message\|\.message' windows/shellx-app/src/ui/settings.rs windows/shellx-app/src/ui/login.rs` prints nothing.
- [ ] **Step 7: Commit.** `git add windows/shellx-model/src/account_view.rs windows/shellx-app/src/ui && git commit -m "feat(shellx-windows): Settings account: sign out from any stored session, errors as sentences"`

---

### Task 8: Other machines: ask only a Mac that can host; an honest "+" list

Needs F2 (merged in Task 7 Step 1).

**Files:**
- Modify: `windows/shellx-model/src/sidebar.rs` (`build_groups` :60-117 and its tests :128+), `windows/shellx-model/src/strings.rs` (two variants added, `NoOtherMachines` :115, :236, :352, :471 removed; `all_has_no_duplicates`)
- Modify: `windows/shellx-app/src/shell_info.rs` (`SHELL_STRINGS` :80; `build_groups` calls in its tests :235, :278, :292)
- Modify: `windows/shellx-app/src/ui/root.rs` (`RootView` fields, `new`, the `build_groups` call and the picker :1008-1024), `windows/shellx-app/src/ui/sidebar.rs` (`PickerEntry` :62-67 replaced by the model's `PickerItem`, `render` :74-83, `machine_picker` :229-286)
- Modify: `windows/README.md` ("Run the window on a Mac": `SHELLX_REQUEST_ANY_MAC=1`)

**Interfaces:**
- Consumes: F2 (`MachineInfo.can_host`).
- Produces:

```rust
// sidebar.rs
/// Design §4.5: this PC may ask `m` for access. `m` is a Mac (platform "macos") that is not this machine, and either
/// its list item says can_host or `any_mac` is set. Never a Windows PC.
pub fn may_request_access(m: &MachineInfo, any_mac: bool) -> bool;
/// `SHELLX_REQUEST_ANY_MAC`'s value: on only for exactly "1".
pub fn request_any_mac(env: Option<&str>) -> bool;
/// Another machine's row offers RowAction::RequestAccess only when it is online, has no access yet and
/// may_request_access; otherwise an online row without access gets RowAction::None (no subtitle).
/// Pending and Granted rows are unchanged.
pub fn build_groups(machines: &[MachineInfo], access: &dyn Fn(&str) -> Access, any_mac: bool, utc_offset_secs: i32, lang: Lang) -> Vec<MachineGroup>;
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PickerItem { pub machine_id: String, pub name: String, pub online: bool, pub requestable: bool }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PickerNote { MacsCannotHostYet, NoMacYet }
/// The machines "+" list: the account's other Macs without a link, in build_groups' order (online first, then name, then id);
/// `requestable` = online && may_request_access. Note: NoMacYet when the list is empty, MacsCannotHostYet when no
/// listed Mac may_request_access (online or not), else None.
pub fn machine_picker(machines: &[MachineInfo], has_link: &dyn Fn(&str) -> bool, any_mac: bool) -> (Vec<PickerItem>, Option<PickerNote>);
// strings.rs: Str::MacsCannotHostYet, Str::SignInOnYourMac (the String table); Str::NoOtherMachines removed
```

Window:
- `RootView::new` stores `request_any_mac: bool` from `request_any_mac(std::env::var("SHELLX_REQUEST_ANY_MAC").ok().as_deref())`, read once, and passes it to `build_groups` and `machine_picker`.
- The "+" list draws `PickerItem`s. A requestable row is clickable as today; any other row is drawn at 0.5 opacity with no click handler.
- Under the rows, the note as muted wrapping lines:
  - `NoMacYet` → `MacsCannotHostYet`, then `SignInOnYourMac`;
  - `MacsCannotHostYet` → that line alone.
- `SHELL_STRINGS` swaps `NoOtherMachines` for the two new variants.
- README: `SHELLX_REQUEST_ANY_MAC=1` offers the request button for every Mac. It is for trying Part 2 with a test Mac (design §4.5).

- [ ] **Step 1: Write the failing tests** in `sidebar.rs`. Build the `MachineInfo` values the way F2's tests do:

```rust
#[test] fn only_macs_that_can_host_are_offered() {
    // may_request_access: macos + can_host -> true; macos without can_host -> false, and true with any_mac;
    // windows + can_host -> false, also with any_mac; is_this_machine (macos, can_host) -> false;
    // request_any_mac(Some("1")) true; Some("0"), Some("true"), Some(""), None false
}
#[test] fn build_groups_offers_access_only_where_it_can_work() {
    // online Mac with can_host, Access::None -> RowAction::RequestAccess; online Mac without -> RowAction::None, subtitle None;
    //   the same with any_mac true -> RequestAccess; online Windows PC -> RowAction::None, also with any_mac;
    // Access::Pending { code: "123456" } on a Mac without can_host -> ShowCode("123456"); Access::Granted -> Open;
    // offline rows keep their "offline · last seen" subtitle
}
#[test] fn the_machine_picker_lists_macs_and_says_why_none_can_be_asked() {
    // this PC + another Windows PC -> ([], Some(NoMacYet));
    // this PC + Mac "A" (online, no can_host) + Windows PC -> ([A requestable false], Some(MacsCannotHostYet));
    // + Mac "B" (online, can_host) -> [A requestable false, B requestable true] (both online, so by name), None;
    // Mac "C" offline with can_host only -> ([C requestable false], None); a Mac with has_link -> not listed;
    // any_mac true with "A" -> [A requestable true], None
}
```

`strings.rs`: `machine_picker_strings` asserts the String table's en and vi for the two new variants. `all_has_no_duplicates` asserts the count before this task plus 1.
- [ ] **Step 2: Run to verify they fail.** `(cd windows && cargo test --locked -p shellx-model sidebar::)`. Expected: compile errors (`may_request_access`, `machine_picker` missing; `build_groups` takes four arguments).
- [ ] **Step 3: Commit the failing tests.** `git add windows/shellx-model/src && git commit -m "test(shellx-windows): request access only from a Mac that can host"`
- [ ] **Step 4: Implement** the model, then the window side as above. Pass `false` at every existing `build_groups` test call.
- [ ] **Step 5: Run to verify they pass.** Run, in one shell: the build line, then `(cd windows && cargo test --locked -p shellx-model && nice -n 19 cargo test --release --locked -p shellx-app && nice -n 19 cargo build --release --locked -p shellx-app)`. Expected:
  - `test result: ok` twice (`--smoke-ui-assets`' string check runs inside the app tests) and a finished build;
  - `grep -rn NoOtherMachines windows/shellx-app/src windows/shellx-model/src` prints nothing.
- [ ] **Step 6: Commit.** `git add windows/shellx-model/src windows/shellx-app/src windows/README.md && git commit -m "feat(shellx-windows): ask only Macs that can host; say why the + list is empty"`

---

### Task 9: Verify and hand off

Needs F6 on `develop`; merge `develop` again if it arrived after Task 7 Step 1.

**Files:** none new.

- [ ] **Step 1: Run the full verification** from the worktree root, in one shell:

```bash
export PATH="/opt/homebrew/opt/zig@0.16/bin:$HOME/.cargo/bin:$PATH" CMUX_GHOSTTY_SRC="/Users/richard/Documents/helper/shellx/ghostty"
(cd windows && cargo test --locked -p shellx-model)
(cd shellx-core && cargo test --workspace --locked)
(cd windows && nice -n 19 cargo test --release --locked -p shellx-app)
(cd windows && nice -n 19 cargo build --release --locked -p shellx-app)
git diff --quiet develop...HEAD -- windows/Cargo.lock shellx-core/Cargo.lock && echo locks-unchanged
```

Expected: `test result: ok` for every suite; a finished build with no new warning; `locks-unchanged`.
- [ ] **Step 2: Windows compile.** Run F6, the Windows compile command, exactly as the foundations plan gives it, on the committed `HEAD`. Expected: its success line. If F6 runs on the VPS rather than in local Docker, hand the command to the orchestrator instead of running it. A failure in this branch's code (for example a `cfg(windows)` caller of a removed or renamed method) is fixed in its own commit, and the step repeats.
- [ ] **Step 3: Secret and address scan.** Run `git diff develop...HEAD | grep -nE '^\+.*(re_[A-Za-z0-9]{8,}|RESEND_API_KEY=|@gmail\.com)'`. Expected: no match.
- [ ] **Step 4: Screenshots, only if Task 0 recorded the Screen Recording permission.** Run:

```bash
cd windows
for lang in en vi; do for screen in start google code invalid switch expired; do
  SHELLX_LANG=$lang SHELLX_DEV_SIGN_IN=$screen dev/mac-shot.sh "$TMPDIR/shellx-signin-$screen-$lang.png" 8
done; done
```

Expected: twelve lines `mac-shot: wrote …`, and Task 5 Step 4's views. `expired` shows no dialog; the sidebar shows "Your session expired." and "Sign in again" above the footer, wrapped inside the sidebar in `vi` too. Without the permission, report "screenshots: not taken (no Screen Recording permission); the user can run the loop above".
- [ ] **Step 5: Report and stop.** Do not merge, push, deploy, build an installer or touch the VPS. Hand-off notes:
  - the commit list, and red and green results per task;
  - the screenshots' paths, or "not taken";
  - Task 0's baselines, and every command not run on this machine and why;
  - rows 9–11 of "Where each check runs", word for word (they are the user's);
  - the sign-in check items for the docs group's 10-step list (design §5.3 step 10), in Vietnamese like the rest of that list:
    - the email field has the keyboard when the dialog opens; Enter sends the code; the mail arrives; typing or pasting the code (also "123 456") signs in;
    - with Unikey, EVKey or the Windows Telex keyboard on, the email field shows "Địa chỉ email này chưa đúng." and "Gửi mã" stays off; letters typed in both fields appear once;
    - Tab walks field, "Gửi mã", Google (only in a build with Google), "Hủy", and Escape closes;
    - "Gửi lại mã sau N giây" counts down;
    - the dialog at 125 % and 150 % scaling;
    - after a server sign-out no dialog opens, and the sidebar shows "Phiên đăng nhập đã hết hạn." with "Đăng nhập lại";
    - until the relay with email sign-in is deployed, Send code answers "Bản này chưa dùng được cách đăng nhập này.";
  - any string that differed from this plan's tables (Task 1 Step 1);
  - every F-name that differed from this plan;
  - the iPhone code-step comparison with Ruling 17 (Ruling 26; `feat/shellx-email-code-signin-ios` is on `develop` since 6b0ddc5e42);
  - `AccountFlow`'s derived `Debug` still printing the account email (design §4.7(2), not this plan's);
  - the Contract additions below.

---

## Contract additions

For the contracts owner (`docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md`): a desktop section after the iPhone part's §31, numbered when it lands, together with Plan A's.

- K3 (§3) gains `auth.google.available {} -> {available: bool}`: local, no request, no session, true only with a Google desktop client id and secret in the core's config. `auth.google.begin` is unchanged. The Mac may use it; nothing requires it.
- Windows names:
  - core calls: `EmailChallenge`, `email_begin`, `email_finish`, `google_available`, `SignInMethod::is_email`;
  - dialog rules: `EmailStep`, `SignInScreen` (`Start`, `Code`, `SigningIn`), `DialogFocus`, `tab_order`, `tab_target`, `DialogKey`, `dialog_key`, `email_looks_valid`, `email_text_refused`, `code_digits`, `auto_submit`, `DECIMAL_ZEROS`;
  - flow: the eight `AccountEvent::Email*` variants (`EmailCodeRequested`, `EmailEdited`, `EmailResendRequested`, `EmailBegun`, `EmailCodeSubmitted`, `EmailFinished`, `EmailChangeRequested`, `EmailCancelled`), `AccountAction::CallEmailBegin` / `CallEmailFinish`, `AccountFlow::email_code_epoch`, `AccountFlow::session_ended_by_server` (replaces `take_signed_out_by_server`);
  - views and machines: `AccountView`, `account_view`, `may_request_access`, `request_any_mac`, `PickerItem`, `PickerNote`, `machine_picker`;
  - strings: the `Str` variants of the String tables, `email_error`, `sign_in_method_label`;
  - window: `TextField::composing`.
- Behaviour shared with the phones:
  - email first;
  - a 409 on verify goes back to the email step;
  - a 410 opens Resend at once;
  - a 401 empties the code;
  - any other failed verify (`email_sign_in_disabled` included) keeps the challenge and the digits.
- Shared with the Mac and the iPhone: a failed Resend drops the challenge for `email_send_failed` / `email_sign_in_disabled` (D2; Android keeps it, D9).
- Shared with the Mac and Android: editing the address clears the failure shown under it. The iPhone branch keeps it until the next Send.
- Shared with the Mac: Cancel and Escape close the dialog, and one sign-in flow runs at a time.
- Windows-only:
  - exactly six digits in the code field's whole text, with Unicode decimal digits mapped;
  - the dialog closes at once after a code sign-in (the Mac keeps "Signed in as … / Done", D3);
  - Google is drawn only with a client;
  - the dialog never opens by itself; a "Sign in again" notice shows instead;
  - access can be requested only from a Mac with `can_host`.
- Development and test only:
  - `SHELLX_DEV_SIGN_IN=start|google|code|invalid|switch|expired` on the Mac build of the window;
  - `SHELLX_REQUEST_ANY_MAC=1` (design §4.5: request access from any Mac, for trying Part 2).

## Not verified while writing this plan

- Run while revising (2026-11-12): `cargo test --locked -p shellx-model` on `develop` c06834ec4e, 192 passed. Taken from the orchestrator's brief and `.superpowers/sdd/2026-11-11-windows-usable/progress.md`, not re-run here:
  - zig 0.16.0 at `/opt/homebrew/opt/zig@0.16/bin/zig`;
  - the main checkout's `ghostty`;
  - the release build (5m08s) and 142 release tests of `shellx-app`;
  - `dev/mac-shot.sh` failing for want of the Screen Recording permission.
- Read in GPUI 0.2.2's source (`~/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/gpui-0.2.2`), never run in this dialog:
  - `track_focus` is an `InteractiveElement` method, so it works on a `Stateful<Div>` (`src/elements/div.rs:616`);
  - `Context::on_focus` (`src/app/context.rs:532`);
  - a mouse-down focuses the innermost `track_focus` element and prevents its parents (`div.rs:2022-2037`);
  - Enter and Space on key-up click a focused element that has click listeners, unless default was prevented (`div.rs:2178-2200`).

  How the window behaves on Windows with these is the user's check (row 10).
- Where a typed character goes while a button holds the keyboard: no input handler is registered, so GPUI drops it (R2 §1). This was read, not run.
- The preview switch is untested. Opening the dialog from inside `RootView::new` relies on GPUI delivering the `SignInEvent` after construction, as it does for the events `reconcile` causes there. If the dialog does not appear, defer the call with `cx.defer_in(window, …)` from `new`; the rest stands. The `expired` preview's ordering against the real startup list answer was reasoned from `AccountFlow::on`, not run.
- Moving the keyboard by emitting `SignInEvent::Opened` follows RootView's existing subscription (`ui/root.rs:185-187`). On real Windows it is part of the manual checks.
- `DECIMAL_ZEROS` is Unicode 13: digits added in later Unicode versions are refused (Verify stays off for them), where the phones' newer tables may accept them.
- The foundations plan was not on disk while this revision was written. F1–F7 state the behaviours this plan relies on, and the F3 and F4 names are guesses that its Interfaces block replaces.
- The new strings outside the catalog (Ruling 31) were written here. No native speaker or designer reviewed the Vietnamese.

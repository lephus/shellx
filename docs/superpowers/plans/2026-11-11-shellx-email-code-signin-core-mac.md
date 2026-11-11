# ShellX Email Code Sign-in, Desktop Plan A (shellx-core + Mac) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Execution (decided; revised 2026-11-11 afternoon and 2026-11-12):** Task 0 Step 1 creates the worktree. The orchestrator then runs the rest of Task 0 in the background while one implementer runs **Stage 1** (Tasks 1–7) on this Mac, in order, committing per task with the failing test first. **Stage 2** (Tasks 8–9) starts once Task 0 has passed: on this Mac, or on the release Mac if Task 0 fails here (Task 0 Step 8). Task 10 (the live check) is optional and is for the orchestrator and the user. One whole-branch review follows Task 9. The Windows plan (Plan B) is on hold and not scheduled: nothing in this plan waits for it or is ordered around it, and "Interfaces for Plan B" stays for the Windows work to consume. 11 tasks: 0–10.

**Goal:** The Mac signs in with an email address and a 6-digit code. The sign-in sheet opens on the email field with **Send code**, and **Continue with Google** sits below it. Two new `shellx-core` RPCs carry the email sign-in, and the Windows app (Plan B) calls the same RPCs.

**Architecture:** `shellx-core` gains two RPCs, built like `auth.google.finish` minus the browser. `auth.email.begin` mails a code through the relay. `auth.email.finish` verifies it and writes `session.json` with `auth_method = "email"`. Both refuse locally what the relay would refuse (an address outside ASCII, a code that is not six digits), so no request is sent and no guess is spent. The in-memory `shellx-fake-api` answers the two routes the way the relay on `develop` does: the same check order, the same address rule and guess counting, a 409 that spends the code, and a failed mail that drops the live code. It also exposes a mailbox, so every test runs offline. On the Mac:
- `ShellXAccount` wraps the two calls.
- Package `ShellXRemoteUI` holds three parts:
  - `EmailSignInModel` owns the steps, the typed address, the resend lock and how the sheet reacts to each relay answer (D2).
  - `SignInSheetFlows` keeps Google and email from running at the same time.
  - `SignInTextField` is an AppKit field whose own field editor allows only Roman input sources.
- The app's sign-in sheet draws them.

**Tech Stack:** Rust 1.91 edition 2024 (`ureq` 3, `tiny_http` in the fake), Swift 6.0 language mode (Swift Testing, SwiftUI/AppKit, `@Observable`), Python 3 `unittest`.

**Sources (read before Task 1):**
- The binding decisions `.superpowers/sdd/2026-11-11-shellx-email-code-signin/desktop-decisions.md` (D1–D9). They win over everything below.
- The relay contract: contracts §29 in `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md`, and on `develop` the files `relay/src/routes/email-sign-in.ts`, `relay/src/auth/email-codes.ts`, `relay/src/auth/email.ts`, `relay/src/auth/device.ts` and `relay/src/app.ts`.
- The email-first brief `.superpowers/sdd/2026-11-11-shellx-email-code-signin/email-first-brief.md`, and contracts §30 (Android as built).
- The spec `docs/superpowers/specs/2026-11-10-shellx-email-code-sign-in-design.md` (Vietnamese) is background only. The brief and D3 replace its §3 items 1–2 ("Continue with email", a separate email step); §29 replaces its §4.
- For conventions: the header and Tasks 3, 8 and 10 of `docs/superpowers/plans/2026-11-07-shellx-signin-1b-desktop.md`.
- Before Task 5, read `skills/cmux-localization/SKILL.md`. Before Tasks 7 and 8, read `skills/cmux-testing/SKILL.md`.

## Revision 2026-11-11 (afternoon)

One line per change, with its reason (decision id or recon item; "relay-contract N" and "mac-code N" are the numbered items in `desktop-recon.json`).

1. The relay's source of truth is now contracts §29 and the relay code on `develop` (merge d2d2e11418). Spec §4 is background only (D1; relay-contract 0; mac-code 1).
2. The stale reference `relay/src/app.ts:159` becomes `:183-186` (the 404 fallback). The email routes are mounted at `:168` (relay-contract 1; mac-code 0).
3. Global Constraints now list the relay rules the apps meet: the newest request wins, a restart or deploy voids every code, a 502 leaves no live code, a 409 spends the code, and any locale other than `vi` gets English mail. No 429 carries Retry-After (D1; mac-code 1).
4. The sheet is email first: field and Send code, "or", Continue with Google, Cancel. There is no "Continue with email" button, no `.idle` step and no `begin()` (D3; brief; mac-code 2, 16, 17).
5. The fake answers `/code` in the relay's order: 503 before the body, then 400 `bad_request`, `invalid_email`, `disposable_email`. It never refuses a locale and records each mail's language (`email_locale`) (D1; relay-contract 7, 8; mac-code 8, 10).
6. The fake checks addresses with the relay's rule: an ASCII dot-atom local part, LDH labels, a TLD of 2–63 letters, at most 254 characters, the last "@" at index 1–64 (D1; relay-contract 9; mac-code 9).
7. The fake's `/verify` follows the relay: a desktop device on a phone platform is `invalid_device` and a malformed challenge id is 410 (neither spends a guess); a code that is not a string, or not exactly the six characters, is a counted wrong guess; the fifth guess can still be right; a right code is spent before the account is resolved (D1; relay-contract 10, 12, 19).
8. The fake resolves accounts as the relay does: an email sign-in signs in; a password account, or an unverified account with an Apple ID, answers 409; a Google account gets the email sign-in added; a bare account is claimed; otherwise a new account is made. New hook `add_user` (D1, fake change 8).
9. New fake hooks: `set_next_email_code` (leading zeros, "004217"), `fail_next_mail` (the relay's 502, which drops the address's live code), `FakeOptions.email_routes: false` (an old relay's 404); `fail_next` stays for answers that change no challenge; `expire_email_codes` is documented as the stand-in for a relay restart (D1, fake changes 4–6 and 10; relay-contract 11, 13).
10. New Task 2 makes the fake's account routes know email sign-in: removing a sign-in keeps one of Google, test and email and revokes the removed one's tokens; a Google link to another address removes the email sign-in; `DELETE /v1/account` works with a code (D1, fake change 9; the old Contract additions note).
11. `auth.email.begin` refuses an address that is empty, holds a character outside ASCII, or is longer than 254 bytes after trimming. It answers `invalid_email` and sends no request (D4; mac-code 12; the phones' 254 cap).
12. `auth.email.finish` removes whitespace and maps every Unicode decimal digit to ASCII before the six-digit check (D4; replaces Ruling 4).
13. New core tests: leading zeros reach the relay unchanged; a 409 spends the code; a failed mail leaves no live code while a 429 keeps it; a body-less 5xx is `http_<status>`; an old relay answers 404 on both routes (relay-contract 5, 11, 13, 19).
14. `EmailSignInModel` follows every row of D2 with one test per row: 401 empties the field; 410 turns it off and unlocks Resend; 409 goes back to the email step with the address; a failed Resend drops the code only for `email_send_failed` and `email_sign_in_disabled`; 429 unlocks at once; a code without its own sentence reads as the server sentence; 503 and 404 read as "not available" (D2; relay-contract 3, 5; mac-code 13, 14).
15. The model owns the typed address (`email`, `setEmail`) and keeps it through the code step and after "Use a different email" or a 409. It refuses non-ASCII: Send stays off and the invalid-email sentence shows under the field at once. It asks the shown field for the keyboard at each step (D3, D4; relay-contract 15; mac-code 15, 16).
16. `digits` keeps the first six Unicode decimal digits as ASCII, so full-width and Arabic-Indic digits count, as on the phones (D4).
17. New `SignInSheetFlows`: one flow at a time and one failure on screen at a time. New `GoogleSignInModel.clearError()` (D3; mac-code "other", one flow at a time).
18. `ShellXAccount.signInWithEmailCode` refuses with `google_in_progress` while a Google flow waits, so two session writes never race (mac-code "other").
19. New `SignInTextField` in `ShellXRemoteUI`: an `NSTextField` subclass behind `NSViewRepresentable` whose own field editor sets `allowedInputSourceLocales = [NSAllRomanInputSourcesLocaleIdentifier]`; Return submits, Escape cancels, it takes the keyboard when it appears; unit tests under `swift test` now, the Telex check by hand on a tagged build (D4; mac-code 19; recon ascii_input_restriction).
20. `GoogleSignInButton` gains `isDefaultAction`. It is off on the email-first sheet, so Return sends the code, and on for the `.link` sheet (mac-code 18).
21. Every new email string takes the phone catalog's en and vi. 14 wordings change, among them codeExpired: "That code no longer works. Send a new one." (D5; relay-contract 17; mac-code 3, 4).
22. New key `remote.signin.email.field` = "Email address" in all ten Mac languages. The unused `remote.signin.email` is left alone, and `remote.signin.email.continue` is not added (D5; replaces Ruling 7; mac-code 5, 21).
23. New key `remote.signin.error.server` (catalog `signin.error.server`). It is shown for an email-path failure that has no sentence of its own, body-less 502/503/504 among them. The Google path keeps today's raw codes (D2 row 7; narrows Ruling 5).
24. `SignInErrorLabels` grows by eight labels (seven before), and `SignInErrorMessage.emailText` is new. A new package struct `EmailSignInTexts` holds the sheet's nine texts, so all 18 new keys go through the localization flow in Stage 1 (D5, D6; replaces Ruling 15).
25. The work is split into two stages, with a new section "Where each check runs" (D6). Stage 1 is Tasks 1–7: the core, the fake, the package models, the field and the strings; it runs on this Mac now. Stage 2 is Tasks 8–9: views, the app-hosted suite and the tagged build; it needs Task 0.
26. Task 0 is rewritten: the worktree first, then the native prerequisites in the background. These are the Metal Toolchain, submodules, Rust 1.88, the prebuilt GhosttyKit, the `ShellXAboutTests` proof, zig and a tagged build. It skips `setup.sh`'s git-hook install and gives an honest estimate and the release-Mac fallback (D6; mac-code 7; recon build-environment).
27. Task 0 no longer says the plans are untracked: both have been on `develop` since 723fd31506. Plan files are never edited on the feature branch (mac-code 6).
28. Task 8 (the sheet) replaces the old Task 6: the new layout with its focus, Return, Tab and Escape rules; layout states for the first screen (empty, with an email failure, while Google waits, with a Google failure), the code step live and dead, and done, without the "code step is taller" assertion; PNG expectations without "Continue with email" (D3; mac-code 17, 20, 21).
29. The old Task 7 (Settings method label) is split by stage: `AccountSignInMethod.Kind` moves to Task 4, and the row title and its key move to Task 5 (D6).
30. New Swift test files declare `@Suite` structs, so `--filter <Suite>` really runs them (mac-code "other").
31. The `ShellXCoreClientGoogleTests.swift` helpers are at :5-17, with `params` at :17 (mac-code "other").
32. "Interfaces for Plan B" now lists every core error code and what it means for the UI: the failed-Resend rule, the 409 rule, the ASCII refusal, the digit mapping, and the final fake names (task brief; relay-contract 2, 3).
33. New Task 10, optional and last: the live check through `shellx-core-cli` against the orchestrator's relay on `127.0.0.1:8799`, and the `SHELLX_API_BASE` launch line for the user (D7).
34. Contract additions: a desktop section after the iPhone's, numbered when it lands, that refers to §29 for the relay rules (mac-code 22).
35. The "Not verified" note about the relay's locale handling is removed, because the relay never refuses a locale (relay-contract 7).
36. Recorded, not changed: Escape closes the sheet (Ruling 12 stands); the Mac keeps "Signed in as … / Done"; no "Your session expired" line, no local expiry timer (a 410 tells), no line saying only the newest mail's code works; older desktop strings (network, Google path) unchanged; re-locking Resend after a 429 deferred for all four apps; the phones' own gaps not fixed here (D2, D3, D5, D9).
37. Release order (D8): the branch ends merged into `develop`. No desktop release with the email path ships before the relay with the feature is deployed. Until then production (`main`'s relay) answers 404, so Send code would read "not available".
38. Re-check the code-step rules against the iPhone branch when it lands. Its `b674a2fb39` already drops the code after a Resend the relay could not mail. This is non-blocking (D3).

Round-1 review fixes ("review" names the lens that raised each one):

39. Task 7: while the editor has marked text (an IME or dead-key composition), the coordinator returns false for Return and Escape, as the app's other fields have done since issue #118. So Return never submits and Escape never closes the sheet mid-composition. `onChange` still gets every change, as `SidebarSearchFieldCoordinator` does. New test `returnAndEscapeWaitForAComposition` (review: fidelity).
40. `verify-local.py` only parses with Swift 6.3.3, which accepts SE-0439 trailing commas and SE-0449 `nonisolated` types. A new "Swift 6.0 check" in Global Constraints catches both, and Tasks 4–9 run it before each commit of app-linked Swift. Its table row is split from verify-local's (review: fidelity, executability).
41. Resend asks again for the kept, trimmed `email`, not `sentTo`, as Plan B's `EmailResendRequested` does; the relay normalizes both spellings to one address. The rule now matches `aDeadCodeTurnsTheFieldOffAndUnlocksResend` ("Foo@Bar.com"), and `resendIsLockedForSixtySecondsAndCountsDown` checks the address too (review: fidelity, executability; the contract lens's `sentTo` alternative was not taken, so both desktops match).
42. Task 8 Step 7's two PNG runs set `CMUX_SKIP_ZIG_BUILD=1` and `CMUX_WIREGUARD_GO_REQUIRE=0`, as every other `test-app.sh` run does (review: fidelity).
43. `email_sign_in_disabled` on verify keeps the challenge and the digits. That was already this plan's table, and both phones do the same. Ruling 23, the Verifying rule and the table now say so, and `aRelayWithoutEmailSignInSaysUnavailable` pins it. Plan B's Ruling 22 is to follow this table (review: contract; the fidelity and executability lenses preferred dropping the challenge in both plans).
44. *Superseded by 65 (Plan B is on hold).* Execution: Plan B's Stage 1 may run now beside this plan's Stage 1 (D6); only its Stage 2 waits for this branch on `develop`. The two Task 0s never run at once, and Plan B's starts after this one's Step 7 (review: fidelity, executability).
45. Task 1 copies `tests/google.rs:2-86`, the fake-Google helpers included. Every test that sends a wrong code first fixes the right one with `set_next_email_code`, including Task 2's delete test (review: fidelity).
46. Task 5: `labels` becomes a suite property shared by `signInErrorMapping` and `emailSignInErrorMapping` (review: fidelity).
47. Task 7: `updateNSView` stores the current closures in the coordinator and refreshes the placeholder, font and `contentType`. The suite is `.serialized` like its hosting precedent, and the focus test also checks a new `onSubmit` (review: fidelity).
48. Global Constraints: a versioned zig goes first on `PATH` in every shell that needs it. Task 10 uses a fixed state folder and passes `SHELLX_CORE_CONFIG` on every CLI line, so the block after the user's wait still finds its session (review: fidelity, executability).
49. The Interfaces table adds the store and key codes (`io`, `state_dir_insecure`, `state_file_insecure`, `crypto`), the envelope's (`unknown_method`, `invalid_json`) and the relay's `bad_request`, all read as the server sentence. Revision 32's "every core error code" now holds (review: fidelity).
50. Task 1 Step 1 names `docs/superpowers/HANDOFF-shellx-mobile.md:99` (review: fidelity).
51. Task 8: the code field gets `focusRequest` and `onCancel` (Cancel). Escape closes the sheet from the code step, and the field takes the keyboard back after a 401. Task 9 Step 4 checks Escape there (review: contract, executability).
52. New `SignInSheetFlows.setEmail(google:email:text:)` and `emailFieldError(google:email:)`. Typing hides Google's failure, and the email field's sentence waits while Google's failure shows, so only one failure is on screen. Test `onlyOneFailureShowsWhileTyping`; Task 8's layout test and PNGs add the state "phu@ẽ typed, then a Google failure" (D3; review: contract, executability).
53. Task 3's `secrets_never_reach_results_or_errors` also checks the core's own refusals: the non-ASCII address, the 255-byte one and "12a456" (review: contract).
54. `cancel()` never cancels a request's `Task`. `cancelWhileVerifyingClosesOnceAndIgnoresTheResult` asserts `Task.isCancelled` is false, and Review Focus 7 cites it (D3; review: contract).
55. Task 3's red commit carries `src/auth_email.rs` holding only its tests, with the `lib.rs` module line. Step 2 also runs `--lib auth_email` (review: executability).
56. Task 0 Step 8:
    - It also covers a failure of Step 4.
    - It says which Stage 2 steps are still written here and which are reported "not run on this machine".
    - It carries the PNG test as a patch.
    - The user runs the red and green runs on the release Mac and returns the output and PNGs.
    - No agent pushes.

    (review: executability)
57. Task 8 Step 2's helpers take `signIn` and `verify` with defaults, so the layout test can keep Google pending, fail it and kill a code (review: executability).
58. `reload.sh` runs with `--no-global-cli-links`, so `/tmp/shellx-cli` and the user's `shellx` command stay as they are (review: executability).
59. The user opens the tagged app by its name, `open -n -g -a "ShellX DEV emailsignin"`, never by a raw `.app` path (review: executability).
60. Task 0 Step 7 checks the zig series before it installs anything, as Plan B's Task 0 Step 3 does. Expected: "zig <version> found at <path>" (review: executability).
61. Every `test-app.sh` run on this Mac uses one test DerivedData, `cmux-emailsignin-tests`, which Task 9 Step 3 removes with the tag (review: executability).

Critic pass (2026-11-12):

62. Task 0 Step 2: if Step 6 still fails after Stage 1's last commit, and only in a file Stage 1 changed, Task 0 has passed and Task 8 Step 1 fixes that file. Without this, Stage 2 waited for a fix that only Stage 2 makes, or moved to the release Mac for a reason inside this plan (critic: executability).
63. "Not verified" now records two checks the critic ran here: `swift test --package-path Packages/Shared/ShellXBrand --filter signInErrorMapping` (built and passed with Swift 6.3.3) and `python3 tests/test_shellx_vi.py` (22 tests, OK, Python 3.9.6) (critic: Stage 1's tools).

## Revision 2026-11-12

Facts learned after the afternoon revision; one line each.

64. GitHub Actions has been blocked by billing for this repository since 2026-10-28. No workflow has run since; the last green Windows run was 2026-10-19. "Where each check runs" says so once, and no step waits for a workflow run. Task 0 Step 8 drops its `shellx-mac-unit.yml` route, and Task 9 Step 7 names only this Mac and the release Mac (fact 1).
65. The Windows plan (Plan B) is on hold, and its Task 0 and Stage 2 are no longer scheduled after this plan. The Execution line, Task 0's header and Task 0 Step 7 no longer order this plan around Plan B, and Revision 44 is superseded. "Interfaces for Plan B" stays: the Windows work will still consume it (fact 3).
66. New Ruling 33: this plan leaves the fake's `GET /v2/machines` as it is, although the relay's items carry no `noise_public_key_b64`, so against the relay the core answers `"fingerprint": null`. The relay's shape would break three core tests, whose fix is a design choice outside D1–D9, and Windows `shellx-app` tests that this plan cannot change. Task 9 Steps 2 and 7 and Contract additions name the drift for the Windows work (fact 2).

## Global Constraints

- **Relay API.** The source of truth is contracts §29 and, on `develop`, `relay/src/routes/email-sign-in.ts:38-166`, `relay/src/auth/email-codes.ts`, `relay/src/auth/email.ts` and `relay/src/auth/device.ts`. Spec §4 is background:

  ```
  POST /v1/auth/email/code     {email, locale?}            no bearer
    order: 503 email_sign_in_disabled (no Resend; before anything is counted or read)
           -> 429 rate_limited (10/min per IP, counted before the body is read) -> 400 bad_request (body not an object)
           -> 400 invalid_email -> 400 disposable_email (the domain or a parent is on the list)
           -> 429 rate_limited (per address 3/min, then 10/h; or 50 000 live codes)
           -> the address's older challenge is deleted, the new one stored -> the mail (Resend, 10 s, no retry);
              a failed mail answers 502 email_send_failed and discards the new challenge too
    -> 202 {challenge_id (43 base64url), expires_in: 600, resend_in: 60, email (trimmed, lower-cased)}
       the same 202 with or without an account; exactly "vi" mails Vietnamese, any other locale (or none) English
  POST /v1/auth/email/verify   {challenge_id, code, device}  no bearer; device as for /v1/auth/google
    order: 429 rate_limited (10/min per IP, shared with /google, /apple, /login; no guess counted)
           -> 400 bad_request -> 400 invalid_device (kind agent, or desktop on a platform other than macos/windows; no guess)
           -> 410 code_expired (id missing, not 43 base64url, unknown, expired, replaced, or from before a relay restart; no guess)
           -> the guess is counted, then compared as the exact string:
              wrong 1-4 -> 401 invalid_code; the fifth wrong -> 410 and the challenge goes;
              right -> the challenge goes (committed), then the account is resolved:
                an email sign-in for the address -> sign in; its password still works (PASSWORD_LOGIN on) -> 409;
                a Google (or test) sign-in -> the email sign-in is added; only another sign-in (Apple) -> 409;
                no sign-in at all -> claimed (password and every earlier session dropped); no account -> a new one
    -> 200 {user_id, device_id, token, email (the account's)}      no auth_method in the answer
       409 switch_from_signed_in_device: the code is spent
  ```

  Errors are `{"error":{"code","message"}}`. The core keeps only `code`, and a body-less answer becomes `http_<status>` (`shellx-core/src/http.rs:174-190`). No 429 carries `Retry-After`. A relay without the feature answers `404 {"error":{"code":"not_found"}}` on both routes (`relay/src/app.ts:183-186`). Production runs `main`'s relay, which has neither route, until `develop`'s relay is deployed (D8).
- **Code.**
  - It is a string of six ASCII digits that keeps its leading zeros (`"004217"`).
  - It lives 600 s and takes five guesses.
  - One code is live per address, and the newest request from any device or app wins. A code from an older mail typed against the newest challenge is a counted 401.
  - A relay restart or deploy voids every code (410).
  - "Resend code" is locked for `resend_in` (60 s), on the client only.
- **Production fact (for notes, not code).** `PASSWORD_LOGIN` is not set in `deploy/relay.env`, so it is on. A code for an account that still has a password answers 409 (D1).
- **The email path always shows**, and there is no discovery call. A relay without it (404, or 503 `email_sign_in_disabled`) shows "This way of signing in isn't available in this build."
- **Tests fake the relay** (`shellx-fake-api`, `FakeRemoteCore`, injected closures). Nothing here needs a running relay, a real mailbox or a key, except the optional Task 10.
- **Secrets.** Never log, `Debug`-print or put in a `CoreError` message: session tokens, the code, the `challenge_id`, email addresses.
- **No new crates and no new Swift packages.** `shellx-core/Cargo.lock` and `windows/Cargo.lock` stay unchanged (the app's Xcode phase builds with `cargo build --release --locked`).
- **No deletion by code on desktop.** Settings keeps the link to `https://shellx.pro/privacy#delete-account`.
- **Mac code and builds.**
  - App-linked Swift (`Sources/`, `Packages/Shared/ShellXBrand/Sources/`) stays Swift 6.0 compatible: no trailing commas in parameter or argument lists, no `nonisolated` on type declarations (`skills/cmux-architecture/references/swift-6-0-compatibility.md`).
  - App tests run only through `scripts/shellx/test-app.sh <Suite>`, never bare `xcodebuild`.
  - App builds are only tagged builds (`./scripts/reload.sh --tag <tag>` with `CMUX_DEV_BACKEND_MODE=local`): never an untagged `cmux DEV.app`, and never `--launch` (refused here, because there are no dev credentials).
  - Never quit, launch, relaunch or replace `/Applications/ShellX.app` or any cmux app.
  - A new `Sources/**/*.swift` file is wired with `./scripts/wire-app-sources.py <path>`; a new `cmuxTests/*.swift` file with `./scripts/sync-test-wiring`.
- **Mac strings.**
  - Every call is `String(localized: "<key>", defaultValue: "<English>")`, catalog `Resources/Localizable.xcstrings`.
  - All ten locales (`en, de, fr, ar, es, zh-Hant, zh-Hans, ko, ja, vi`) go through `./scripts/localize-changes --base develop`.
  - `en` and `vi` are exactly the String table's values, which are the phone catalog's (D5). The other eight are the executor's translations.
  - Vietnamese follows `scripts/shellx/l10n/vi-glossary.md`.
  - A translation identical to English needs an `identityLocales` record in `scripts/localization-allowed-omissions.json`.
  - Every call site of a key passes the same `defaultValue`, and no new key has an integer placeholder (Ruling 8).
- **Mac verification** starts with `python3 scripts/verify-local.py --affected develop --swift-changed develop`. The base is explicit because the default base is `origin/HEAD`, which is `main`. Its `swift-syntax` check only parses the changed Swift with the local Swift 6.3.3 (`swiftc -frontend -parse -swift-version 5`, `scripts/verify-local.py:367-372`), and that parser accepts both Swift 6.1 constructs the app may not use, so verify-local does not catch a Swift 6.0 break.
- **The Swift 6.0 check** catches the two constructs `skills/cmux-architecture/references/swift-6-0-compatibility.md:13-17` bans: SE-0439 trailing commas before `)` and SE-0449 `nonisolated` types. It reads every app-linked Swift file the branch adds or changes, committed or not, new files included. Run it from the worktree root before each commit that touches `Sources/` or `Packages/Shared/ShellXBrand/Sources/`. Expected: no output. Fix every file it names before committing.

  ```bash
  { git diff -z --name-only --diff-filter=AM "$(git merge-base develop HEAD)" -- 'Sources/*.swift' 'Packages/Shared/ShellXBrand/Sources/*.swift'; git ls-files -z --others --exclude-standard -- 'Sources/*.swift' 'Packages/Shared/ShellXBrand/Sources/*.swift'; } | xargs -0 perl -0777 -ne 'print "$ARGV: trailing comma before )\n" if /,\s*\)/; print "$ARGV: nonisolated type\n" if /^[ \t]*(?:@\w+[ \t]+)*(?:(?:public|internal|package|private|fileprivate|open|final)[ \t]+)*nonisolated[ \t]+(?:(?:public|internal|package|private|fileprivate|open|final)[ \t]+)*(?:struct|enum|class|protocol|actor)\b/m'
  ```
- **cargo** lives in `~/.cargo/bin`, which is not on the default `PATH`. Run `export PATH="$HOME/.cargo/bin:$PATH"` in every shell that runs it.
- **zig, when Task 0 Step 7 installed a versioned `zig@<major.minor>`** (Homebrew does not link it). An agent's shell keeps no variables from one command to the next. So every shell that runs `scripts/shellx/build-cmux-tui.sh`, `reload.sh` or `cargo … -p shellx-app` starts with `export PATH="$(brew --prefix zig@<major.minor>)/bin:$HOME/.cargo/bin:$PATH"`. `ghostty-vt-sys` finds zig through `ZIG` or `PATH` (`cmux-tui/crates/ghostty-vt-sys/build.rs:42`).
- **Never:** release, deploy, push or merge to `main`, sign, notarize, upload anywhere, use `gh` (not installed here), or use a developer account. The implementer does not merge: the orchestrator reviews the branch and lands it on `develop`. This plan does not use the VPS or its cross build.
- **Branch and commits.** Branch `feat/shellx-email-code-signin-core-mac` from `develop`, in worktree `.worktrees/email-code-signin-core-mac`. Commits are `test(shellx-core): …` then `feat(shellx-core): …`, or `test(shellx): …` then `feat(shellx): …`. A fix that a later stage finds is `fix(shellx): …`.

## Where each check runs (D6)

"Now" means this Mac today: cargo 1.95, Swift 6.3.3, Xcode 26.6, Python 3.9.6. It has no Metal Toolchain, no zig, no submodules, no GhosttyKit and no `gh`. Commands run from the worktree root, and the Rust ones need `~/.cargo/bin` on `PATH`.

| Check | Exact command | Now | After Task 0 | Elsewhere (no GitHub workflow runs today: see below) |
| --- | --- | --- | --- | --- |
| Core and fake relay tests (192 passed on `develop` today) | `(cd shellx-core && cargo test --workspace --locked)` | yes | yes | GitHub `shellx-remote.yml` job `core`, once the branch is on `develop` |
| C ABI smoke (the Mac app's entry into the core) | `(cd shellx-core && bash scripts/c-smoke.sh)` | yes | yes | `shellx-remote.yml`, macOS leg |
| No new crates; locks unchanged | `(cd shellx-core && python3 scripts/test_check_deps.py && python3 scripts/check_deps.py) && git diff --quiet develop...HEAD -- shellx-core/Cargo.lock windows/Cargo.lock && echo locks-unchanged` | yes | yes | `shellx-remote.yml` |
| ShellXBrand package: client, account, models, flows, `SignInTextField` | `swift test --package-path Packages/Shared/ShellXBrand` (one suite: add `--filter <Suite>`) | yes (writes `.build/`, which git ignores) | yes | `shellx-mac.yml`; `shellx-remote.yml` job `swift-package` |
| Strings, catalog, Vietnamese, guards | `python3 tests/test_shellx_vi.py`; `python3 scripts/localization_catalog.py check`; `./scripts/localize-changes --base develop`; `python3 tests/test_shellx_remote_harness.py`; `python3 tests/test_shellx_no_phone_home.py` | yes | yes | `shellx-mac.yml` |
| Source and test wiring | `./scripts/wire-app-sources.py --check && ./scripts/sync-test-wiring --check` | yes | yes | `shellx-mac.yml` |
| Static checks, and Swift syntax as the local Swift 6.3.3 parses it | `python3 scripts/verify-local.py --affected develop --swift-changed develop` | yes | yes | `shellx-mac.yml` (`--all`) |
| Swift 6.0 compatibility (SE-0439 trailing commas, SE-0449 `nonisolated` types) | the Swift 6.0 check (Global Constraints) | yes | yes | nowhere else: no workflow here compiles with Swift 6.0 |
| App-hosted suites: the app compiles, the sheet lays out, the fixture signs in | `CMUX_SKIP_ZIG_BUILD=1 CMUX_WIREGUARD_GO_REQUIRE=0 scripts/shellx/test-app.sh ShellXSignInSheetTests ShellXAboutTests ShellXPhonePairingCoordinatorTests -- -jobs 4 -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/cmux-emailsignin-tests"` | no | yes: first compile ~55–60 min, then ~5 min | release Mac (Task 0 Step 8); GitHub `shellx-mac-unit.yml`, by a dispatch the user starts (~75 min) |
| Windows app tests against the changed fake | `(cd windows && cargo test --release --locked -p shellx-app)` | no (needs the ghostty submodule and zig) | yes, once zig works (Task 0 Step 7) | release Mac; `shellx-windows.yml` job `app`, by the user's dispatch |
| Tagged Debug build of the Mac app | `CMUX_DEV_BACKEND_MODE=local CMUX_SKIP_ZIG_BUILD=1 CMUX_WIREGUARD_GO_REQUIRE=0 CMUX_TUI_CLIENT_LOCAL="$(scripts/shellx/build-cmux-tui.sh)" ./scripts/reload.sh --tag emailsignin --no-global-cli-links` | no | yes, with zig: ~35–45 min cold | release Mac |
| Click-through: focus, Return, Tab, Escape, Telex in the email field | The user opens the tagged app (Task 9 Step 4) | no | the user only: agents cannot launch it here (no `~/.secrets/cmuxterm-dev.env`) | release Mac, by the user |
| Live sign-in with a mailed code | Task 10 | the CLI part, any time after Task 3, by the orchestrator and the user | the DEBUG app's launch line (Task 10 Step 2) | the deployed relay, later (D8) |

**GitHub Actions is not available.** Billing has blocked every workflow of this repository since 2026-10-28. None has run since, and the last green Windows run was 2026-10-19. The workflows in the Elsewhere column are listed for when Actions works again, and no step of this plan waits for one or counts on one. Today every check runs on this Mac or on the release Mac, so the core's Linux leg and any Windows-target build of the core do not run for this branch. Its new Rust is platform-neutral. Even with Actions back, no workflow fires on a `feat/*` branch, and `gh` is not installed here, so any dispatch would be the user's.

**Task 0's estimate (honest; none of it has been observed on this Mac).** Expect 1.5–2 h of wall time before `test-app.sh` first passes:
- The Metal Toolchain (about 0.7 GB), the submodules, the checksum-pinned prebuilt GhosttyKit and the SwiftPM pins.
- Then a cold cmux-unit compile of 55–60 min.

That is 2–3 GB of downloads and 15–30 GB of disk; 132 GiB is free. A first tagged Debug build adds 35–45 min (it has its own DerivedData) and needs zig. The timings come from the other Mac (an M2) and CI. This M4 shares its CPU and 16 GB of RAM with the iOS simulator agent, hence `-- -jobs 4` and `nice`.

## Review Focus

1. **A code pasted with spaces, a line break, wide digits, or the mail's subject around it.** Its six digits are used as ASCII, with leading zeros kept. Tests: Task 3 `a_pasted_code_with_spaces_or_wide_digits_is_sent_as_six_ascii_digits`, `a_code_with_leading_zeros_is_sent_as_the_same_six_characters`; Task 6 `pastedCodeKeepsOnlySixDigits`, `aCodeWithLeadingZerosIsSentAsIs`.
2. **Double submit: the sixth digit submits by itself while the person also presses Return or Verify.** There is one verify call and no guess is burned. Tests: Task 6 `sixDigitsSubmitByThemselvesOnce`; Task 3 `a_code_that_is_not_six_digits_is_invalid_code_without_a_request`.
3. **A dead code (expired, used, replaced by a newer request, voided by a relay restart, or the fifth wrong guess).** The sheet says the code no longer works, empties and turns off the code field, and unlocks "Resend code" at once. Tests: Task 1 `a_wrong_code_counts_and_the_fifth_kills_the_challenge`, `a_new_code_replaces_the_old_one_for_that_address`, `dead_challenges_answer_410`; Task 3 `a_dead_code_is_code_expired`; Task 6 `aDeadCodeTurnsTheFieldOffAndUnlocksResend`.
4. **A 409: the address belongs to an account a code cannot open.** The code is spent, and the sheet goes back to the email step with the address kept and the switch sentence. Tests: Task 1 `a_password_account_answers_409_and_the_code_is_spent`; Task 3 `a_password_account_email_answers_switch_and_spends_the_code`; Task 6 `aSwitchAnswerGoesBackToTheEmailStepWithTheAddress`.
5. **A failed Resend.** After `email_send_failed` (502) or `email_sign_in_disabled` (a 503 with that code, or a 404) there is nothing left to verify, so Verify is off. After a 429, a network failure or any other code (a body-less 5xx included), the code already mailed is kept. Resend unlocks in every case. Tests: Task 1 `fail_next_mail_drops_the_live_code_like_the_relay`; Task 3 `a_failed_mail_leaves_no_live_code_and_a_429_keeps_it`; Task 6 `aResendTheRelayCouldNotMailLeavesNoCodeToVerify`, `aResendRefusedForRateOrNetworkKeepsTheCode`.
6. **An address with a character outside ASCII (Telex's "phu@ẽample.com").** Send code stays off and the invalid-email sentence shows at once. The core sends nothing, and the field's editor offers only Roman input sources. Tests: Task 1 `bad_addresses_and_bodies_are_refused`; Task 3 `begin_refuses_an_address_the_relay_would_refuse_without_a_request`; Task 6 `aNonAsciiAddressShowsTheInvalidEmailSentenceAtOnce`; Task 7 `theFocusedFieldAllowsOnlyRomanInputSources`; by hand in Task 9 Step 4.
7. **Closing the sheet mid-flow and opening it again.** A late answer never changes or reopens the closed sheet, and the new sheet starts empty on the email step. A code that verified after the close still leaves this Mac signed in, because `cancel()` never cancels the verify's `Task`. Tests: Task 6 `cancelWhileSendingIgnoresTheLateChallenge`, and `cancelWhileVerifyingClosesOnceAndIgnoresTheResult` with its `Task.isCancelled == false` assertion; Task 4 `emailCodeSignsInAndSavesTheEmailIdentity`.
8. **A relay without the feature, and a relay being deployed.** An old relay's 404, or the 503 of a relay without Resend, shows "not available". A body-less 502/503/504 shows "ShellX is having a problem". The email path never shows a raw code, and nothing is written. Tests: Task 3 `a_relay_without_email_sign_in_is_email_sign_in_disabled`, `a_proxy_answer_without_a_body_is_http_status`; Task 5 `emailSignInErrorMapping`; Task 6 `aRelayWithoutEmailSignInSaysUnavailable`, `answersWithoutTheirOwnSentenceReadAsTheServerSentence`.
9. **Offline.** The network sentence shows on the same step, a retry works, and no session file is written. Tests: Task 3 `offline_is_network`; Task 6 `offlineShowsTheNetworkMessageAndAllowsRetry`.
10. **The keyboard on the email-first sheet.** The email field has the keyboard when the sheet opens, also when it opens by itself after a server sign-out. Return sends the code and never starts Google, Escape closes the sheet from either field, and Google and email never run together. While an input method or a dead key composes, Return and Escape belong to the composition. Only one failure shows. Tests: Task 7 `theFieldTakesTheKeyboardWhenItAppearsAndWhenAsked`, `returnSubmitsAndEscapeCancels`, `returnAndEscapeWaitForAComposition`; Task 6 `SignInSheetFlowsTests`; by hand in Task 9 Step 4.

## Rulings

Where the decisions (D1–D9) and this list disagree, the decisions win. Where the relay and the spec disagree, the relay on `develop` wins. Where both are silent, the plan decides.

1. A relay without the feature has one core code. A 404 `not_found`, a body-less 404 (`http_404`) and a 503 `email_sign_in_disabled` on either route all surface as `email_sign_in_disabled`, and the apps map one code. *(Stands. A body-less 503 stays `http_503`, per D2 row 7.)*
2. `auth.email.finish` returns the six fields of `auth.google.finish` with `auth_method: "email"` (the spec says only "phiên").
3. The core normalizes `locale`: a value starting with `vi`, in any case, is `"vi"`; anything else, or nothing, is `"en"`. So each app passes its UI language as it is. The Mac passes `Bundle.main.preferredLocalizations.first`. *(Stands per D1: the relay mails Vietnamese only for exactly `"vi"`.)*
4. *Superseded by Ruling 22 (D4).* The core removes ASCII whitespace from `code` and refuses anything but six ASCII digits with `invalid_code` without a request, so a malformed code never burns a guess.
5. *Superseded in part by Ruling 24 (D2).* `rate_limited` gets a sentence (`remote.signin.error.rateLimited`, the catalog's `signin.error.rateLimited` text); the spec's string list omits it though §4 returns 429 on both routes. `signInErrorMapping`'s example of a code shown raw changes from `rate_limited` to `weak_password`. *(The sentence is now the email path's. The Google path keeps today's handling, so `signInErrorMapping`'s raw `rate_limited` line stays.)*
6. `email_sign_in_disabled` reads as the catalog's `signin.error.providerUnavailable` text, under the Mac key `remote.signin.error.unavailable`.
7. *Superseded in part by Ruling 28 (D5).* Mac key names follow the catalog: `settings.account.methods.email` (the spec writes `settings.account.method.email`; the code has `settings.account.methods.*`), and the email field reuses the existing, currently unused key `remote.signin.email` instead of a new `.field` key. *(The first half stands. The field now uses the new key `remote.signin.email.field`.)*
8. `remote.signin.email.resendIn` takes `%@`, filled with the whole seconds as text ("42"), not the spec's `%lld`: `scripts/localize_changes.py` stops on an integer placeholder in a new key and demands plural entries. The visible text equals the phones' `Resend code in %lld s`.
9. The spam hint of spec §9 is the second sentence of `remote.signin.email.sentTo` (in the catalog's wording), as on the phones. There is no separate key.
10. Settings › Account keeps its two-line row (the title "Email code", the address under it) rather than "Email code · foo@bar.com". Remove stays for Apple IDs only.
11. *Superseded in part by Ruling 23 (D2).* `code_expired` keeps the person on the code step with Resend unlocked at once; "Use a different email" is the only way back to the email step. *(This still holds for a 410, which now also empties and turns off the code field. A 409 now goes back to the email step too.)*
12. Closing the sheet cannot cancel a verify already sent, because there is no cancel API. The closed sheet ignores the answer and the account keeps the session, as with a Google finish after a close. Escape is Cancel (D3).
13. The email path exists only in the "Sign in to ShellX" sheet. The "Switch to Google sign-in" sheet is unchanged, and its Google button keeps Return.
14. `finishEmailSignIn` returns the existing `GoogleSignInResult` (same shape); no rename.
15. *Superseded by Ruling 24.* `SignInErrorLabels.init` grows by seven required labels with no default, so the app cannot ship an unlocalized one. *(It now grows by eight, with `server`. There are still no defaults.)*
16. *Superseded by Ruling 21 (D1).* Fake API: `mailinator.com` and its subdomains stand for the disposable list; `fail_next` scripts the answers the fake cannot produce by itself (429, 502, 404, `invalid_device`). *(The disposable stand-in stays. A 502 now comes from `fail_next_mail`, which drops the live code as the relay does.)*
17. `auth.login`, the `shellx-fake-api` binary's flags and the remote e2e harness are unchanged. *(Stands. The shared `device_ok` now also refuses a desktop device on a phone platform, as the relay does. No existing caller sends one.)*
18. An app-hosted suite, `ShellXSignInSheetTests`, is added, so that `test-app.sh` executes tests of the changed app code (plan 1B only compiled it). It runs in Stage 2.
19. *Superseded by Ruling 28 (D5).* Wording: the String table matches the Android plan's; if the shared catalog differs, the catalog's `en` and `vi` replace this plan's, recorded in the hand-off. *(The catalog is now the source for every new email string, and the table below already carries its wording.)*
20. **Source of truth (D1).** Contracts §29 and the relay code on `develop`. Spec §4 is background. The email-first brief and D3 replace spec §3 items 1–2.
21. **The fake relay mirrors the relay (D1).** `/code` and `/verify` follow the relay's order and rules (Global Constraints). The fake never refuses a locale, checks addresses with the relay's rule, resolves accounts with the relay's 409s and claim, and has Task 2's account routes. Its hooks:
    - `fail_next`: answers that change no challenge (429, 404, body-less 5xx, `invalid_device`).
    - `fail_next_mail`: the 502.
    - `set_next_email_code`: fixed codes.
    - `expire_email_codes`: expiry and a relay restart.
    - `FakeOptions.email_sign_in: false`: a relay without Resend. It is fixed for the fake's life, so no challenge outlives a switch.
    - `FakeOptions.email_routes: false`: an old relay.

    The fake does not count rate limits.
22. **The core refuses locally, without a request (D4).**
    - `auth.email.begin` refuses an address that, after trimming, is empty, holds a character outside ASCII, or is longer than 254 bytes (`invalid_email`). The relay would refuse it after spending one of the ten per-IP requests a minute.
    - `auth.email.finish` removes whitespace and maps every Unicode decimal digit (General_Category Nd) to ASCII. If the result is not six digits, it answers `invalid_code`, and no guess is counted.
23. **The Mac model reacts to the relay as D2 says, with one test per row.**
    - 401: the field is emptied and the person stays on the code step.
    - 410: the field is emptied and turned off, Verify is off, and Resend unlocks.
    - 409: the challenge and the digits are dropped, the lock ends, and the sheet goes back to the email step with the address.
    - A failed Resend: the challenge is kept for `rate_limited`, network, and every code without a rule of its own; it is dropped for `email_send_failed` and `email_sign_in_disabled`. Any failed Resend unlocks Resend.
    - A 429 on Send code: Send can be used again at once (no re-lock).
    - Any other verify failure: the digits and the challenge are kept for a retry. That includes `email_sign_in_disabled`, which on verify only a relay without the feature answers (a 404). D2 has no row for it; both phones keep the code there, and Plan B follows this table.
24. **Email-path sentences (D2).** `SignInErrorMessage.emailText` maps the email codes, `switch_from_signed_in_device` and `network` to their sentences. Every other code (`http_502`, `http_503`, `http_504`, `server`, `invalid_device`, `invalid_params`, `bad_response`, `google_in_progress`, …) reads as `remote.signin.error.server`. A non-core error reads as the network sentence. The Google path (`SignInErrorMessage.text`) is unchanged.
25. **The email-first sheet (D3).**
    - Top to bottom: the title; the email field with Send code under it; the email failure under the field; "or"; Continue with Google (not the default action here); Google's failure under it; Cancel.
    - The email field has the keyboard when the sheet opens, also when it opens by itself after a server sign-out. After each step change the shown field takes the keyboard again.
    - Return in the email field sends the code; in the code field it verifies. Escape cancels, from either field. While a composition is open, Return and Escape go to the input method. Tab follows the order above: email field, Send code, Continue with Google, Cancel; on the code step: code field, Verify, Resend, Use a different email, Cancel.
    - Only one failure shows (`SignInSheetFlows`): each flow's start clears the other's; typing in the email field hides Google's failure; the email field's sentence waits while Google's failure shows; and only one flow runs.
    - The Mac keeps "Signed in as … / Done" after a code sign-in.
26. **The Roman-only field (D4).**
    - `SignInTextField` lives in `ShellXRemoteUI`, so its unit test runs under `swift test` now.
    - Each field gets its own `RomanInputFieldEditor`, so the window's shared field editor and the other fields are untouched.
    - Both sheet fields use it. On the code field it stops a Japanese or Chinese input source from composing wide digits.
    - If the unit test cannot observe the restriction, or the check by hand shows Telex still offered, the implementer reports it. The ASCII rule and its sentence then stand alone.
27. **The model's address and digits.** `EmailSignInModel` starts on `.email` (no `.idle`, no `begin()`). It owns the typed address (`email`) through the code step and trims it on send. Editing the address or the code clears the failure shown. `isPlausibleEmail` also requires ASCII. `digits` keeps the first six Unicode decimal digits as ASCII, the phones' rule, on the Mac and in the core (D4).
28. **Strings (D5).** Every new email string takes the phone catalog's en and vi. Two keys are new to the plan: `remote.signin.email.field` and `remote.signin.error.server`. There is no "Continue with email" key. That makes 18 new keys in all. Older desktop strings (network, Google path) are unchanged.
29. **Stages (D6).**
    - Stage 1 (Tasks 1–7) is everything `cargo test`, `swift test` and the Python checks can prove now. It also writes the app-side `.localized` builders and the Settings row title; only Stage 2 compiles them.
    - Stage 2 (Tasks 8–9) is the views, the app-hosted suite, the tagged build and the screenshots.
    - Task 0 never runs `setup.sh` as a whole: its last step installs git hooks for every worktree of this clone.
30. `ShellXAccount.signInWithEmailCode` throws `google_in_progress` while a Google flow waits, so only one session write happens at a time. `requestEmailCode` writes nothing and needs no guard.
31. **Release (D8).** This plan ends with the branch merged into `develop` by the orchestrator. No desktop release with the email path ships before the relay with the feature is deployed. That is the user's decision.
32. **Out of scope (D2, D3, D5, D9):**
    - Re-locking Resend after a 429 (all four apps).
    - "Your session expired" on desktop.
    - A local expiry timer.
    - A line saying that only the newest mail's code works.
    - The phones' own gaps. Android keeps a dead challenge after a failed Resend; that is its own follow-up.
33. **The fake's `GET /v2/machines` keeps its shape (2026-11-12).**
    - The drift:
      - The relay's items are `{machine_id, name, platform, online, last_seen_unix, fingerprint}` (`relay/src/v2/machines.ts:84-108`).
      - The fake's items also carry `os_version`, `app_version` and `noise_public_key_b64` (`shellx-core/fake-api/src/lib.rs:775-797`).
      - The core computes `fingerprint` from `noise_public_key_b64` only and never takes the relay's (`shellx-core/src/machines.rs:93-104`). So against the relay every item has `"fingerprint": null`.
      - The Mac reads that as `""` (`Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/ShellXRemoteService.swift:605`). The Windows model requires a string (`windows/shellx-model/src/sidebar.rs:16`), so a Windows sign-in never completes there.
    - Why this plan does not change the fake:
      - In the relay's shape, three core tests fail: `tests/machines.rs` `list_marks_this_machine_and_offline_after_90s` (:118), `list_fingerprint_of_this_machine_matches_login_fingerprint` (:126-131) and `list_fingerprint_is_computed_from_a_padded_standard_key` (:173-183). Fixing them means deciding where a listed machine's fingerprint comes from: the relay's own string, or the key added to the relay's answer. That is plan 1B's security rule (`list_never_falls_back_to_the_server_fingerprint`), and it is outside D1–D9.
      - Windows `shellx-app` tests that list a registered machine against the fake fail too, at least `account_session_against_fake_api` (`windows/shellx-app/src/core_service.rs:361`) and `login_register_list_heartbeat_logout_against_fake_api` (`core_bridge.rs:75`). This plan cannot fix them (no Windows model changes), and Task 9 Step 2 needs them green.
      - This plan neither reads nor writes `/v2/machines`, and none of its tests asserts on a listed machine's `fingerprint` or key. So the drift is neither hidden further nor made deeper here.
    - The Windows work owns the fix, together with that rule. Task 9 Step 7's hand-off and Contract additions name the drift.

## Interfaces for Plan B (the RPC contract)

```
auth.email.begin  {email: string, locale?: string}
  -> {challenge_id: string, expires_in: number, resend_in: number, email: string}
     email = the relay's normalized address (show it, not the typed text); expires_in 600 and resend_in 60 when the relay omits them
     locale: a value starting with "vi" (any case) is sent as "vi", anything else as "en" (the relay needs exactly "vi")
     refused without a request (invalid_email): empty after trimming, any character outside ASCII, longer than 254 bytes
auth.email.finish {challenge_id: string, code: string}
  -> {user_id, device_id, device_public_key_b64, fingerprint, email, auth_method: "email"}     never a token
     code: whitespace removed, every Unicode decimal digit mapped to ASCII; anything but six digits -> invalid_code, no request
```

What each RPC writes and needs:
- `begin` writes nothing.
- `finish`, on success:
  - writes `session.json` with `auth_method: "email"` and `email`;
  - keeps `device.key`;
  - drops `machine.json` only when the account changed (`auth::save_session`).

  `auth.session` then reports `auth_method: "email"`. On any error no session or machine file is written; `device.key` may be created before the request, as `auth.google.finish` and `auth.login` do, because the relay must receive the public key (review of Tasks 1–3, Minor 1).
- Neither sends a bearer, and neither needs a session.
- A later call may answer 401 `unauthorized`, for example after the email sign-in is removed on another device or after a Google link to another address. That is handled as for any session.

| `CoreError.code` | From | Means | UI (the Mac model; Plan B mirrors it) |
| --- | --- | --- | --- |
| `invalid_params` | either | Params are not an object; `email`, `challenge_id` or `code` is missing or not a string; `challenge_id` is empty | server sentence |
| `invalid_email` | begin | The relay's 400; or locally, with no request (so no per-IP budget is spent): empty, a character outside ASCII, longer than 254 bytes | the invalid-email sentence under the field; stay on the email step. A model shows it as soon as a non-ASCII character is typed, and keeps Send off |
| `disposable_email` | begin | The relay's 400: the domain or a parent is on the list | its sentence; stay on the email step |
| `rate_limited` | either | The relay's 429: 10/min per IP on `/code`; 3/min and 10/h per address; 50 000 live codes; 10/min per IP on `/verify`, shared with Google. It touches no challenge and counts no guess | its sentence. Send code / Resend can be pressed again at once (no re-lock, D2). A failed Resend keeps the challenge; a failed verify keeps the digits |
| `email_send_failed` | begin | The relay's 502: the mail did not go, and the address has no live code at all (the older one was replaced first, the new one discarded) | its sentence. On Resend, drop the challenge (Verify and the code field off) and unlock Resend |
| `email_sign_in_disabled` | either | The relay's 503 `email_sign_in_disabled` (no Resend; `/code` only), or a 404 with `not_found` or no body (a relay without the feature) | the "not available" sentence. On Resend, drop the challenge. On verify, keep the challenge and the digits, as both phones do; Verify asks again, and a 404 counts no guess |
| `invalid_code` | finish | The relay's 401: a counted wrong guess (1–4), including a code from an older mail typed against the newest challenge; or locally: not six decimal digits (no request, no guess) | stay on the code step, empty the code field, show its sentence |
| `code_expired` | finish | The relay's 410: expired, used, replaced by a newer request (from any device or app), issued before a relay restart or deploy, a malformed id, or the fifth wrong guess. The cause cannot be known | the "no longer works" sentence; the code field emptied and off, Verify off, Resend unlocked at once |
| `switch_from_signed_in_device` | finish | The relay's 409: a code cannot open this account (its password still works, or its address was never verified and an Apple ID is attached). The code is spent | drop the challenge and the digits, end the lock, go back to the email step with the address kept, show its sentence |
| `invalid_device` | finish | The relay's 400 (not expected: the core builds the device) | server sentence |
| `bad_request` | either | The relay's 400 for a body that is not a JSON object (`relay/src/http/errors.ts:73-75`; not expected: the core builds the body) | server sentence |
| `network` | either | No answer: offline, DNS, TLS, or the 20 s timeout | the network sentence. A failed Resend keeps the challenge (the relay may or may not have replaced it; a later 410 will tell); a failed verify keeps the digits |
| `internal_error`, `payload_too_large` | either | relay 500 / 413 with a JSON error code; the core passes the code through unchanged (review of Tasks 1–3) | server sentence |
| `http_<status>` | either | A non-2xx answer without a JSON error code, for example a 502/503/504 from the proxy while the relay is being deployed | server sentence; a failed Resend keeps the challenge |
| `server` | either | A 2xx body the core cannot use: a 202 without `challenge_id`, or a 200 without `token`, `user_id`, `device_id` or `email` | server sentence |
| `not_configured` | either | `config.set` never ran | server sentence |
| `io`, `state_dir_insecure`, `state_file_insecure`, `crypto` | either | The state folder or the device key cannot be read or written. The store is opened before dispatch for every method but `config.set` and `version.check` (`shellx-core/src/lib.rs:117`), so `begin` can answer these too (`store.rs:121-135`, `auth.rs`) | server sentence |
| `unknown_method`, `invalid_json` | either | The envelope: a core without these methods, or params that are not JSON (`lib.rs:100`, `:228`). Neither happens with the apps' own builds | server sentence |

**Fake relay names** (dev-dependency `shellx-fake-api`; Plan B's tests use them):
- `FakeOptions.email_sign_in: bool` and `FakeOptions.email_routes: bool`, both default true.
- `FakeApi::email_code(&self, email: &str) -> Option<String>`
- `FakeApi::email_locale(&self, email: &str) -> Option<String>`
- `FakeApi::set_next_email_code(&self, code: &str)`
- `FakeApi::expire_email_codes(&self)`
- `FakeApi::fail_next_mail(&self)`
- `FakeApi::fail_next(&self, path: &str, status: u16, code: &str)`
- `FakeApi::add_user(&self, email: &str) -> String`
- The constants `EMAIL_CODE_TTL_SECS = 600`, `EMAIL_RESEND_SECS = 60` and `EMAIL_CODE_MAX_ATTEMPTS = 5`.
- A desktop device must have `platform` `macos` or `windows`.

The core's digit mapping is `shellx_core::auth_email::decimal_digit` (Task 3). Plan B's model crate does not link the core, so it carries its own mapping (its plan's choice); the core re-checks every code anyway. The Windows dialog follows D3's email-first order: email field, Send code, "or", Continue with Google, Cancel.

## String table

Mac keys in `Resources/Localizable.xcstrings`. "Win" is the `windows/shellx-model` name Plan B gives the same text. Every en and vi value is the phone catalog's (`shellx-ios/ShellX/Localizable.xcstrings` on `develop`: `signin.email.*`, `signin.error.*`, `settings.account.method.email`), per D5.

| Key | en | vi | Win |
| --- | --- | --- | --- |
| `remote.signin.email.field` | Email address | Địa chỉ email | `EmailAddress` (exists; its English becomes "Email address", D5) |
| `remote.signin.email.send` | Send code | Gửi mã | `SendCode` |
| `remote.signin.email.or` | or | hoặc | `OrDivider` |
| `remote.signin.email.sentTo` | We sent a 6-digit code to %@. If it isn't there in a minute, check your spam folder. | Đã gửi mã 6 chữ số tới %@. Nếu sau một phút chưa thấy, hãy xem cả thư rác. | `sent_code_to()` |
| `remote.signin.email.code` | 6-digit code | Mã 6 chữ số | `CodePlaceholder` |
| `remote.signin.email.verify` | Verify | Xác nhận | `VerifyCode` |
| `remote.signin.email.resend` | Resend code | Gửi lại mã | `ResendCode` |
| `remote.signin.email.resendIn` | Resend code in %@ s | Gửi lại mã sau %@ giây | `resend_code_in()` |
| `remote.signin.email.change` | Use a different email | Dùng email khác | `UseDifferentEmail` |
| `remote.signin.error.invalidEmail` | That doesn't look like an email address. | Địa chỉ email này chưa đúng. | `InvalidEmail` |
| `remote.signin.error.disposableEmail` | Temporary email addresses can't be used. Try another address. | Không dùng được địa chỉ email tạm thời. Hãy dùng địa chỉ khác. | `DisposableEmail` |
| `remote.signin.error.invalidCode` | That code isn't right. Check the email and try again. | Mã chưa đúng. Xem lại email rồi thử lại. | `InvalidCode` |
| `remote.signin.error.codeExpired` | That code no longer works. Send a new one. | Mã này không còn dùng được. Hãy gửi mã mới. | `CodeExpired` |
| `remote.signin.error.emailSendFailed` | Couldn't send the email. Try again in a moment. | Chưa gửi được email. Thử lại sau giây lát. | `EmailSendFailed` |
| `remote.signin.error.unavailable` | This way of signing in isn't available in this build. | Bản này chưa dùng được cách đăng nhập này. | `SignInUnavailable` |
| `remote.signin.error.rateLimited` | Try again in a few minutes. | Thử lại sau ít phút. | `RateLimited` |
| `remote.signin.error.server` | ShellX is having a problem. Try again later. | ShellX đang gặp sự cố. Thử lại sau. | Plan B's server sentence |
| `settings.account.methods.email` | Email code | Mã qua email | `EmailCodeMethod` |

Notes:
- 18 new keys. The `%@` of `resendIn` is the wait in whole seconds as text (`42`), per Ruling 8.
- The old `remote.signin.email` ("Email", unused) stays as it is.
- There is no "Continue with email" key, and Plan B drops `ContinueWithEmail` (D5).
- The other eight locales are the executor's translations.

## File structure

| File | Responsibility |
| --- | --- |
| `shellx-core/fake-api/src/lib.rs` (modify) | The two email routes as the relay answers them, the mailbox and the hooks; the account routes that know email sign-in |
| `shellx-core/fake-api/tests/email.rs` (create) | The fake's email routes over raw HTTP |
| `shellx-core/fake-api/tests/email_account.rs` (create) | Identity removal, the Google link and account deletion with email sign-ins |
| `shellx-core/src/auth_email.rs` (create) | `begin`, `finish`, `locale_of`, `sendable_email`, `decimal_digit`, `clean_code`, the "no email sign-in" mapping |
| `shellx-core/src/api.rs`, `src/lib.rs` (modify) | Request and response types; `KNOWN_METHODS`, dispatch |
| `shellx-core/tests/email.rs`, `tests/support/mod.rs` (create, modify) | The RPCs against the fake |
| `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/ShellXCoreClient+Email.swift` (create) | `EmailCodeChallenge`, the two typed calls |
| `…/ShellXRemoteCore/ShellXAccount.swift`, `ShellXCoreClient+Google.swift` (modify) | `requestEmailCode`, `signInWithEmailCode`; `AccountSignInMethod.Kind` |
| `…/ShellXRemoteUI/SignInErrorMessage.swift` (modify) | Eight new labels, `emailText` |
| `…/ShellXRemoteUI/EmailSignInTexts.swift` (create) | The sheet's nine email texts, injected |
| `…/ShellXRemoteUI/EmailSignInModel.swift` (create) | Steps, address, sanitizing, auto-submit, resend lock, the D2 rows |
| `…/ShellXRemoteUI/SignInSheetFlows.swift` (create); `GoogleSignInModel.swift` (modify) | One flow and one failure at a time; `clearError()` |
| `…/ShellXRemoteUI/SignInTextField.swift` (create) | The Roman-only AppKit field |
| `Sources/ShellX/Remote/UI/RemoteUISnapshot.swift`, `Sources/ShellX/ShellXAccountDetailView.swift` (modify; Stage 1 writes, Stage 2 compiles) | `SignInErrorLabels.localized`, `EmailSignInTexts.localized`; the method row's title |
| `Sources/ShellX/Remote/UI/EmailSignInSection.swift` (create) | The first screen's email part and the code step |
| `Sources/ShellX/Remote/UI/SignInSheet.swift`, `GoogleSignInButton.swift`, `ShellXRemoteServicing.swift`, `ShellXRemoteFixtureService.swift`, `Sources/ShellX/ShellXAccountFlow.swift` (modify) | Sheet layout and presenter, the Google button's default action, protocol and fixture, account wiring |
| `cmuxTests/ShellXSignInSheetTests.swift` (create) | The sheet lays out in every state; the fixture's email sign-in |

---

### Task 0: Worktree, then the native prerequisites in the background (Stage 2's prerequisite)

**Files:** none (environment only). Everything runs in `.worktrees/email-code-signin-core-mac`. Submodules, the `./GhosttyKit.xcframework` link and `test-app.sh`'s DerivedData belong to one checkout, so warming another checkout would pay the cold compile twice.

**One heavy job at a time.** While this Task 0 runs, no other plan's Task 0 or cold build starts on this Mac. Only one `brew install` runs at a time, because Homebrew's lock refuses a second, and this cold build already shares the 16 GB Mac with the iOS simulator agent.

**Test DerivedData.** Every `test-app.sh` run on this Mac appends `-derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/cmux-emailsignin-tests"` after its `--`. The path is the same each time, so the cold compile happens once. It stays apart from the tag's own DerivedData, as `skills/cmux-testing/references/local-vs-ci-validation.md:35,44-45` asks, and Task 9 Step 3 removes it with the tag.

- [ ] **Step 1 (foreground, seconds): Create the worktree.**
  - First, the orchestrator commits this revised plan on `develop`. Both plans have been tracked there since 723fd31506. Plan files are never edited or committed on the feature branch, and if the worktree's copy differs, `/Users/richard/Documents/helper/shellx/docs/superpowers/plans/` wins.
  - Then, following superpowers:using-git-worktrees: `git worktree add -b feat/shellx-email-code-signin-core-mac .worktrees/email-code-signin-core-mac develop`.
  - Stage 1 (Task 1) starts now, and Steps 3–7 run in the background beside it.
- [ ] **Step 2: How the background part runs.**
  - The orchestrator runs Steps 3–7 as one background shell in the worktree, with `export PATH="$HOME/.cargo/bin:$PATH"`, under `nice -n 10`, logging to a file outside the repository.
  - It never runs `./scripts/setup.sh` as a whole: its last step, `install-git-hooks.sh`, sets `core.hooksPath` for every worktree of this clone, the iPhone agent's included.
  - It never runs `reload.sh --launch`, and never touches `/Applications/ShellX.app`.
  - Stage 1 keeps committing meanwhile. If Step 6 fails to compile a file Stage 1 is changing (`shellx-core/src`, `Packages/Shared/ShellXBrand`, `Sources/`), that is not a Task 0 failure: re-run Step 6 after Stage 1's next commit (it is incremental, minutes).
  - If Step 6 still fails after Stage 1's last commit, and every error is in a file this branch changed (in practice Task 5's `RemoteUISnapshot.swift` or `ShellXAccountDetailView.swift`), Task 0 has passed. Stage 2 starts here, Task 8 Step 1 fixes that file, and Step 7 runs after that fix. It is not Step 8's fallback.
- [ ] **Step 3: Metal Toolchain** (~5–10 min). Xcode 26 ships it as a separate component, and this is the setup command from CONTRIBUTING.md, not a build. Run `xcrun metal --version || xcodebuild -downloadComponent MetalToolchain`, then `xcrun metal --version`. Expected: a version line. If the download asks for a password or fails, stop Task 0 and report it: the user installs it.
- [ ] **Step 4: Submodules and Rust 1.88** (~5–15 min).
  - Run `git submodule update --init --recursive` (ghostty, vendor/bonsplit, homebrew-cmux).
  - Then the `Native/DiffSidecar` pin that `setup.sh:61-63` installs: `rustup toolchain install 1.88.0 --profile minimal --component clippy,rustfmt && rustup target add --toolchain 1.88.0 aarch64-apple-darwin x86_64-apple-darwin`.
- [ ] **Step 5: GhosttyKit** (minutes). Run `./scripts/ensure-ghosttykit.sh`.
  - Expected: "Seeding cache from prebuilt GhosttyKit.xcframework". The ghostty pointer cb1ef7091c has a pinned checksum in `scripts/ghosttykit-checksums.txt`, and that path needs no zig.
  - If it falls back to a local build, it needs zig: either do Step 7's zig install first, or use CI's path, `./scripts/download-prebuilt-ghosttykit.sh`.
- [ ] **Step 6: The proof** (55–60 min cold). Run `CMUX_SKIP_ZIG_BUILD=1 CMUX_WIREGUARD_GO_REQUIRE=0 scripts/shellx/test-app.sh ShellXAboutTests -- -jobs 4 -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/cmux-emailsignin-tests"`. Expected: `** TEST SUCCEEDED **`. Task 0 passes here: Stage 2's app-hosted checks can run on this Mac.
- [ ] **Step 7: zig and a tagged build** (~10 min, plus 35–45 min cold). This warms the tag's own DerivedData; Task 9 needs it for the tagged app and for the `shellx-app` check.
  - Run `bash scripts/ghostty-zig-version.sh "$PWD"`. It prints the minimum zig version ghostty needs (expected 0.16.x).
  - If `bash -c 'source scripts/ghostty-zig-version.sh && ghostty_require_compatible_zig "$PWD"'` already passes, install nothing.
  - Otherwise compare `brew info zig` with that major.minor. If they match, run `brew install zig`. If not, run `brew install zig@<major.minor>`, then `export PATH="$(brew --prefix zig@<major.minor>)/bin:$PATH"` in this shell; from then on the zig bullet of Global Constraints applies to every other shell.
  - Expected before the build: the check prints `zig <version> found at <path>`. Record both for the hand-off.
  - Then run `CMUX_DEV_BACKEND_MODE=local CMUX_SKIP_ZIG_BUILD=1 CMUX_WIREGUARD_GO_REQUIRE=0 CMUX_TUI_CLIENT_LOCAL="$(scripts/shellx/build-cmux-tui.sh)" ./scripts/reload.sh --tag emailsignin --no-global-cli-links`.
    - Use no `--launch` and no `--build-only`, so the app stays for the user.
    - `--no-global-cli-links` leaves `/tmp/shellx-cli`, `~/.local/bin/shellx-dev` and any `shellx` shim on the user's `PATH` untouched (`scripts/reload.sh:775-794`, `:938-939`). Nothing in this plan uses the dev CLI.
    - Expected: the reload summary naming the tagged app, `ShellX DEV emailsignin`.
  - Zig on macOS 26.5 is unproven here: `shellx-mac.yml:54-55` notes a libSystem link problem, though the other Mac built ghostty's zig parts in October. If zig fails, Task 9's tagged build and click-through move to the release Mac (Step 8); the app-hosted suites stay here.
- [ ] **Step 8: Fallback, the release Mac.**
  - If Step 3, 4, 5 or 6 fails on this Mac for a reason outside this plan, keep the log and stop Task 0. Never work around it with bare `xcodebuild`.
  - Stage 1 is unaffected and continues here.
  - Task 8's code is still written and committed here: Step 2's tests, Step 4's red commit, Step 5's implementation and Step 8's commit.
  - These are reported "not run on this machine", each named:
    - Task 8 Steps 1 and 3;
    - the `test-app.sh` part of Task 8 Step 6, and Task 8 Step 7;
    - the `test-app.sh` line of Task 9 Step 1, and Task 9 Steps 2–3.
  - The red result of Task 8 Step 3 is then owed: the release Mac runs it on Step 4's commit.
  - Task 8 Step 7's temporary PNG test is saved as a patch outside the repository: `git diff -- cmuxTests/ShellXSignInSheetTests.swift > "$TMPDIR/shellx-signin-png.patch"`, then `git checkout cmuxTests/ShellXSignInSheetTests.swift`.
  - The user brings the branch to the release Mac (which has built this app before), with the patch. The branch goes as a push of `feat/shellx-email-code-signin-core-mac` to `origin` or as a `git bundle`; either is the user's action, and no agent pushes.
  - There, in a checkout of the branch, the user runs the block below and Task 9 Step 4's click-through, and sends back the output and the PNGs. Never touch that Mac's `/Applications/ShellX.app` either.
  - Fixes are new `fix(shellx): …` commits here, and the round repeats.

```bash
export PATH="$HOME/.cargo/bin:$PATH"
git submodule update --init --recursive && ./scripts/ensure-ghosttykit.sh
git switch --detach <Task 8 Step 4's commit>   # the red run: expected, the test target does not compile
CMUX_SKIP_ZIG_BUILD=1 CMUX_WIREGUARD_GO_REQUIRE=0 scripts/shellx/test-app.sh ShellXSignInSheetTests
git switch feat/shellx-email-code-signin-core-mac
CMUX_SKIP_ZIG_BUILD=1 CMUX_WIREGUARD_GO_REQUIRE=0 scripts/shellx/test-app.sh ShellXSignInSheetTests ShellXAboutTests ShellXPhonePairingCoordinatorTests
git apply <the patch>
CMUX_SKIP_ZIG_BUILD=1 CMUX_WIREGUARD_GO_REQUIRE=0 scripts/shellx/test-app.sh ShellXSignInSheetTests -- -testLanguage en
CMUX_SKIP_ZIG_BUILD=1 CMUX_WIREGUARD_GO_REQUIRE=0 scripts/shellx/test-app.sh ShellXSignInSheetTests -- -testLanguage vi
git checkout cmuxTests/ShellXSignInSheetTests.swift   # the PNGs are under the test's NSTemporaryDirectory()
(cd windows && cargo test --release --locked -p shellx-app)
CMUX_DEV_BACKEND_MODE=local CMUX_SKIP_ZIG_BUILD=1 CMUX_WIREGUARD_GO_REQUIRE=0 CMUX_TUI_CLIENT_LOCAL="$(scripts/shellx/build-cmux-tui.sh)" ./scripts/reload.sh --tag emailsignin --no-global-cli-links
```

  There is no third route while GitHub Actions is blocked ("Where each check runs"). Once it works again, the user could dispatch `shellx-mac-unit.yml` on the branch, with the input `suites: ShellXSignInSheetTests ShellXAboutTests ShellXPhonePairingCoordinatorTests`, for the app-hosted suites only. That takes about 75 min, and the branch must be on `origin`.

---

## Stage 1: runs on this Mac now

### Task 1: Fake relay, the two email routes as the relay answers them

**Files:**
- Modify: `shellx-core/fake-api/src/lib.rs`: module doc :12-14; `FakeOptions` :59-75 with its `Debug` :78-91 and `Default` :108-123; `TokenInfo` :141-147; `State` :178-216; the test hooks beside `revoke_token` :400-403; `route` :653-711; `device_ok` :1317-1326; the handlers after `delete_account` :1597-1615.
- Create: `shellx-core/fake-api/tests/email.rs`

**Interfaces:**
- Produces (used by Tasks 2–3 and by Plan B):

```rust
pub const EMAIL_CODE_TTL_SECS: u64 = 600;
pub const EMAIL_RESEND_SECS: u64 = 60;
pub const EMAIL_CODE_MAX_ATTEMPTS: u32 = 5;
pub struct FakeOptions { /* existing fields */
    /// false: `POST /v1/auth/email/code` answers 503 `email_sign_in_disabled` before reading the body (a relay
    /// without Resend). Fixed for the fake's life.
    pub email_sign_in: bool,   // default true
    /// false: neither email route exists; both answer 404 `not_found` (a relay from before the feature).
    pub email_routes: bool,    // default true
}
impl FakeApi {
    /// The live code mailed to `email` (trimmed and lowercased first); None when the address has no live challenge.
    pub fn email_code(&self, email: &str) -> Option<String>;
    /// That mail's language: "vi" when the request's `locale` was exactly "vi", else "en".
    pub fn email_locale(&self, email: &str) -> Option<String>;
    /// The next challenge stored uses `code` (six ASCII digits) instead of a random one; once.
    pub fn set_next_email_code(&self, code: &str);
    /// Every live email challenge answers 410 from now on, no guess counted: expiry, and the stand-in for a relay
    /// restart or deploy.
    pub fn expire_email_codes(&self);
    /// The next `/code` that reaches the mail fails as the relay's does: the address's older challenge is gone,
    /// the new one is discarded, the answer is 502 `email_send_failed`.
    pub fn fail_next_mail(&self);
    /// The next request to `path` is answered `status` with `{"error":{"code": code}}`, or with no body when `code`
    /// is empty; the route does not run, so no challenge changes (the relay's 429s change none). Calls for one path queue up.
    pub fn fail_next(&self, path: &str, status: u16, code: &str);
    /// A user with this address, no password and no sign-in (an account whose address nobody verified); its id.
    pub fn add_user(&self, email: &str) -> String;
}
```

**Route rules.** These are the relay's (`relay/src/routes/email-sign-in.ts:38-166`), in this order. `fail_next` is checked at the top of `route` for every path. With `!opts.email_routes`, both email paths fall through to the 404 `not_found` arm.

`POST /v1/auth/email/code`:
1. `!opts.email_sign_in` → 503 `email_sign_in_disabled`.
2. A body that is not a JSON object → 400 `bad_request`.
3. `email` is not a string, or, after trim and lowercase, fails `relay/src/auth/email.ts:5-19` → 400 `invalid_email`. That check is: `EMAIL_RE` (an ASCII dot-atom local part, LDH labels, an alphabetic TLD of 2–63 letters), at most 254 characters, and the last "@" at index 1–64.
4. The domain, or a parent domain, is `mailinator.com` → 400 `disposable_email`.
5. Otherwise, remove that address's challenges and store a new one under `challenge_id = random_b64url(32)`: `{email, code, locale, attempts: 0, expires_at: now + 600}`. The code is the `set_next_email_code` value, else `random_code()`. The locale is `"vi"` when `body.locale == "vi"`, else `"en"`.
6. With `fail_next_mail` armed, discard the new challenge and answer 502 `email_send_failed`. Otherwise answer 202 `{challenge_id, expires_in: 600, resend_in: 60, email}`.

`POST /v1/auth/email/verify`:
1. A body that is not an object → 400 `bad_request`.
2. `!device_ok(device)`, or kind `agent` → 400 `invalid_device`.
3. A `challenge_id` that is not a string matching `^[A-Za-z0-9_-]{43}$`, is unknown, or has `expires_at <= now` → 410 `code_expired`. An expired challenge is removed.
4. `attempts += 1`, then `code` is compared as the exact string; a non-string never matches.
5. A wrong code: at `attempts == 5` the challenge is removed and the answer is 410; before that, 401 `invalid_code`.
6. The right code: remove the challenge, then resolve the account:
   - An identity with `provider "email"` and `subject == email` → its user.
   - Otherwise `users[email]`: in `password_users` → 409 `switch_from_signed_in_device`. Has a `google` or `test` identity → add the `email` identity. Has some other identity → 409. Has none → claim it: revoke every token of the user's devices, then add the `email` identity.
   - Otherwise a new user with the identity.
7. Then find the device by `(user, public_key)`, call `issue_token(.., "email")`, and answer 200 `{user_id, device_id, token, email}` with the account's email (as `google_sign_in` computes it).

`device_ok` is shared with `/login` and `/google`. It also refuses kind `desktop` with a platform other than `macos` or `windows` (`relay/src/auth/device.ts:27`).

- [ ] **Step 1: Baseline** (minutes; record any failure, fix nothing unrelated). Run `(cd shellx-core && cargo test --workspace --locked)`, `swift test --package-path Packages/Shared/ShellXBrand`, `python3 tests/test_shellx_vi.py`, `python3 scripts/localization_catalog.py check` and `python3 scripts/verify-local.py --affected develop --swift-changed develop`. Expected:
  - `test result: ok` (192 tests on `develop` today);
  - Swift Testing `passed`;
  - unittest `OK`;
  - no catalog errors;
  - `verify-local.py` fails at most `feature-flags` (`ios-feed-performance-release`, known noise in `docs/superpowers/HANDOFF-shellx-mobile.md:99`).
- [ ] **Step 2: Write the failing tests** in `fake-api/tests/email.rs`.
  - The file copies the `use` lines and the helpers of `tests/google.rs:2-86`, from `raw` to `google_sign_in`, with the same bodies. Those helpers are private to `google.rs`, and the Google sign-in below needs the fake-Google ones (`challenge`, `auth_path`, `token_form`, `auth_code`, `new_nonce`, `id_token`). Drop any helper the file ends up not using, so no dead-code warning appears.
  - Every test that sends a wrong code first fixes the right one with `set_next_email_code`, because `random_code` (`fake-api/src/lib.rs:997-1001`) can return any six digits, `000000` included. Tasks 2 and 3 follow the same rule.
  - `ask(fake, email, locale)` returns the (status, body) of a POST to CODE; `verify(fake, challenge_id, code: Value, device)` does the same for VERIFY.
  - Test addresses use `bar.com`, `b.cd`, `shellx.test`, `mailinator.com` and `ẽample.com`.

```rust
const CODE: &str = "/v1/auth/email/code";
const VERIFY: &str = "/v1/auth/email/verify";
#[test] fn a_code_request_answers_202_with_the_normalized_email() {
    // POST CODE {"email":"  Foo@Bar.com ","locale":"vi"} -> 202; challenge_id.len() == 43; (expires_in, resend_in) == (600, 60);
    // email == "foo@bar.com"; fake.email_code("FOO@bar.com") is Some six ASCII digits; fake.email_locale("foo@bar.com") == Some("vi")
}
#[test] fn the_mail_is_vietnamese_only_for_exactly_vi() {
    // locale "fr", 7, absent, "VI", "vi-VN" -> 202 each and email_locale == Some("en"); "vi" -> Some("vi")
}
#[test] fn bad_addresses_and_bodies_are_refused() {
    // "nope", "a@b", "a b@c.de", "phu@ẽample.com", "a..b@c.de", "a@-b.cd", ".a@b.cd", a 255-character address,
    // an address whose last "@" is at index 65, email 5 -> 400 invalid_email; "a@mailinator.com", "a@x.mailinator.com"
    // -> 400 disposable_email; body "[]" and "not json" -> 400 bad_request; fake.email_code(..) is None for each
}
#[test] fn a_relay_without_resend_answers_503_before_reading_the_body() {
    // FakeOptions { email_sign_in: false, .. }: body "[]" -> 503 email_sign_in_disabled; {"email":"nope"} -> 503
}
#[test] fn an_old_relay_answers_404_on_both_routes() { /* FakeOptions { email_routes: false, .. }: CODE and VERIFY -> 404 not_found */ }
#[test] fn the_right_code_signs_in_once_with_an_email_session() {
    // verify -> 200 with non-empty user_id, device_id, token and email "foo@bar.com"; fake.token_auth_method(token) == Some("email");
    // GET /v1/account/identities with the token lists exactly one item {provider: "email", email: "foo@bar.com"};
    // the same challenge and code again -> 410 code_expired; fake.email_code("foo@bar.com") is None
}
#[test] fn a_wrong_code_counts_and_the_fifth_kills_the_challenge() {
    // set_next_email_code("004217"); wrong guesses 4217 (a JSON number), " 004217", "4217", "000000" -> 401 invalid_code each;
    // the fifth wrong guess -> 410 code_expired; then "004217" -> 410
}
#[test] fn the_fifth_guess_can_still_be_right() { /* four wrong codes -> 401 each; the right code -> 200 */ }
#[test] fn a_new_code_replaces_the_old_one_for_that_address() {
    // set_next_email_code("111111"), ask -> c1; set_next_email_code("222222"), ask -> c2; verify(c1, "111111") -> 410;
    // verify(c2, "111111") -> 401 invalid_code (an older mail's code is a counted guess); verify(c2, "222222") -> 200
}
#[test] fn dead_challenges_answer_410() {
    // expire_email_codes() -> verify -> 410 and email_code None; challenge_id "nope", a 43-character id never issued,
    // challenge_id 5 -> 410 each
}
#[test] fn a_password_account_answers_409_and_the_code_is_spent() {
    // POST /v1/auth/login {"email":"a@b.cd","password":"pw","device":device(1)} -> 200; ask "a@b.cd"; verify -> 409
    // switch_from_signed_in_device; the same challenge and code -> 410; email_code("a@b.cd") is None
}
#[test] fn an_unverified_account_with_an_apple_id_answers_409() {
    // u = fake.add_user("a@b.cd"); fake.add_identity(&u, "apple", "apple-1", "apple-user@shellx.test", true, None); ask; verify -> 409
}
#[test] fn a_bare_account_is_claimed() { /* u = fake.add_user("a@b.cd"); ask; verify -> 200, user_id == u; its identities are exactly [email] */ }
#[test] fn a_google_account_gets_the_email_sign_in_added() {
    // a Google sign-in (as in tests/google.rs) for google-user@shellx.test; ask that address; verify -> 200 with the same user_id;
    // identities providers == ["google", "email"]
}
#[test] fn a_bad_device_is_invalid_device_and_spends_no_guess() {
    // four wrong codes -> 401 each; then kind "agent", no device, kind "desktop" with platform "ios" -> 400 invalid_device each;
    // then device(1) with the right code -> 200 (none of the three was the fifth guess)
}
#[test] fn fail_next_scripts_one_answer_and_changes_no_challenge() {
    // ask -> c1; fail_next(CODE, 429, "rate_limited"); ask -> 429 rate_limited; fail_next(CODE, 404, ""); ask -> 404 with an
    // empty body; verify(c1, its code) -> 200
}
#[test] fn fail_next_mail_drops_the_live_code_like_the_relay() {
    // ask -> c1; fail_next_mail(); ask -> 502 email_send_failed; email_code None; verify(c1, its code) -> 410; ask -> 202
}
```

- [ ] **Step 3: Run to verify they fail.** Run: `(cd shellx-core && cargo test --locked -p shellx-fake-api --test email)`. Expected: compile errors (`email_code`, `fail_next`, `email_sign_in`, … missing).
- [ ] **Step 4: Commit the failing tests.** `git add shellx-core/fake-api/tests/email.rs && git commit -m "test(shellx-core): fake relay email code routes as the relay answers them"`
- [ ] **Step 5: Implement** the Interfaces and the route rules.
  - Add the routes and hooks to the module doc.
  - `Debug` of `FakeOptions` lists the two new fields.
  - `TokenInfo.auth_method`'s comment becomes `"password" | "google" | "email"`.
- [ ] **Step 6: Run to verify they pass.** Run: `(cd shellx-core && cargo test --workspace --locked)`. Expected: `test result: ok` everywhere, and no new compiler warning. The existing Google and login tests still pass, because their desktop devices say `macos`.
- [ ] **Step 7: Commit.** `git add shellx-core/fake-api/src/lib.rs && git commit -m "feat(shellx-core): fake relay answers /v1/auth/email/code and /verify like the relay"`

---

### Task 2: Fake relay, the account routes that know email sign-in

No desktop code calls these routes, but the fake must not contradict the relay (D1, fake change 9; `relay/src/routes/identities.ts:42-64`, `relay/src/routes/sign-in.ts:111-135`, `relay/src/routes/account.ts:15-61`).

**Files:**
- Modify: `shellx-core/fake-api/src/lib.rs`: `TokenInfo`, `issue_token` :1350-1356, `google_sign_in` :1503-1531, `google_link` :1533-1563, `remove_identity` :1585-1595, `delete_account` :1597-1615.
- Create: `shellx-core/fake-api/tests/email_account.rs`

**Rules:**
- **Token origin.** `TokenInfo` gains `identity_id: Option<String>`: the sign-in a token came through (Google or email), or `None` for a password login. Removing an identity revokes its tokens.
- **`DELETE /v1/account/identities/<id>`.** Removing the account's last `google`, `test` or `email` identity answers 409 `last_google_identity`. Apple IDs never count toward that, and are always removable.
- **`POST /v1/auth/google/link`.** A link that adds Google with an address other than the account's also removes the account's `email` identities and their tokens. The caller still gets its new `google` token, as today.
- **`DELETE /v1/account`** (bearer). It tries `{id_token}` as today, else `{challenge_id, code}` with a string `challenge_id`:
  - The challenge rules of `/verify` apply: a wrong code is a counted 401 `invalid_code`, and the fifth is 410; a dead challenge is 410.
  - A right code for an address other than the account's is spent and answers 401 `reauth_required`.
  - The right code for the account's address deletes the account (204).
  - Anything else answers 401 `reauth_required`.

- [ ] **Step 1: Write the failing tests** in `fake-api/tests/email_account.rs`, with the helpers as in Task 1, plus `email_sign_in(fake, email, seed) -> (user_id, token)`:

```rust
#[test] fn the_last_way_to_sign_in_cannot_be_removed() {
    // an email-only account: DELETE its email identity -> 409 last_google_identity; a Google account with the email sign-in
    // added (device 1 by Google, device 2 by code): DELETE the email identity -> 204, fake.token_is_live(device 2's token)
    // false, device 1's token live; then DELETE the Google identity -> 409
}
#[test] fn linking_google_with_another_address_removes_the_email_sign_in() {
    // email account foo@bar.com on devices 1 and 2; set_google_account("g@x.test", "sub-g"); device 1 links -> 200 email "g@x.test";
    // identities providers == ["google"]; device 2's token is dead; device 1's new token has auth_method "google"
}
#[test] fn an_account_can_be_deleted_with_a_code_to_its_own_address() {
    // email account foo@bar.com; fake.set_next_email_code("123456"); ask foo@bar.com; DELETE /v1/account {challenge_id, "000000"}
    // -> 401 invalid_code (counted);
    // {challenge_id, the right code} -> 204 and fake.user_exists(u) false
}
#[test] fn a_code_to_another_address_cannot_delete_the_account() {
    // email account foo@bar.com; ask other@bar.com; DELETE /v1/account with that challenge and code -> 401 reauth_required;
    // the same challenge and code at /verify -> 410 (spent); a dead challenge -> 410; the user still exists
}
```

- [ ] **Step 2: Run to verify they fail.** Run: `(cd shellx-core && cargo test --locked -p shellx-fake-api --test email_account)`. Expected: assertion failures. The removal is not refused for an email identity, the tokens are still live, and `DELETE /v1/account` answers 401 `reauth_required` to a code.
- [ ] **Step 3: Commit the failing tests.** `git add shellx-core/fake-api/tests/email_account.rs && git commit -m "test(shellx-core): fake account routes with email sign-ins"`
- [ ] **Step 4: Implement** the rules.
- [ ] **Step 5: Run to verify they pass.** Run: `(cd shellx-core && cargo test --workspace --locked)`. Expected: `test result: ok` everywhere, and no new warning.
- [ ] **Step 6: Commit.** `git add shellx-core/fake-api/src/lib.rs && git commit -m "feat(shellx-core): fake account routes keep one sign-in, link and delete with email sign-ins like the relay"`

---

### Task 3: `auth.email.begin` and `auth.email.finish`

**Files:**
- Create: `shellx-core/src/auth_email.rs`
- Modify: `shellx-core/src/api.rs`: after `GoogleTokenResponse` :118-129; the `SessionFile.auth_method` comment :49.
- Modify: `shellx-core/src/lib.rs`: the `mod` list :6-23, `KNOWN_METHODS` :35-65, `dispatch` :147-203.
- Modify: `shellx-core/tests/support/mod.rs`
- Create: `shellx-core/tests/email.rs`

**Interfaces:**
- Consumes: Tasks 1–2; `auth::{device_public, device_name, load_session, save_session}`, `http::{send, parse_json}`, `api::{LoginDevice, GoogleAuthResponse, SessionFile}`, `fingerprint::fingerprint`.
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
/// The relay's limit for a whole address.
pub const MAX_EMAIL_BYTES: usize = 254;
/// A value starting with "vi" (any case) is "vi"; anything else, or nothing, is "en".
pub fn locale_of(raw: Option<&str>) -> &'static str;
/// `raw` trimmed, when that is not empty, ASCII only and at most MAX_EMAIL_BYTES long (else the relay would refuse it).
pub fn sendable_email(raw: &str) -> Option<&str>;
/// The value of a Unicode decimal digit (General_Category Nd: ASCII, full-width, Arabic-Indic, Devanagari, …).
pub fn decimal_digit(c: char) -> Option<u32>;
/// `raw` without whitespace (`char::is_whitespace`) and with every decimal digit as ASCII, when that is exactly six digits.
pub fn clean_code(raw: &str) -> Option<String>;
pub fn begin(agent: &ureq::Agent, cfg: &Config, params: &Value) -> Result<Value, CoreError>;
pub fn finish(agent: &ureq::Agent, cfg: &Config, store: &StateStore, params: &Value, auth_lock: &Mutex<()>) -> Result<Value, CoreError>;
// lib.rs: KNOWN_METHODS gains "auth.email.begin", "auth.email.finish" after "auth.google.cancel"
// tests/support/mod.rs
/// begin, read the fake's mailbox, finish; finish's result.
pub fn email_sign_in(core: &Core, fake: &FakeApi, email: &str) -> Result<Value, shellx_core::CoreError>;
```

**`decimal_digit`** reads `DECIMAL_ZEROS: &[u32]`, the first code point of every run of ten Nd digits. It is written out once with `python3 -I -c "import unicodedata as u; print([hex(c) for c in range(0x110000) if u.category(chr(c)) == 'Nd' and u.decimal(chr(c)) == 0])"`. This Mac's Python 3.9 knows Unicode 13, so digits of scripts added later are dropped like letters.

**`begin`:**
- Params must be an object and `email` a string, else `invalid_params`.
- If `sendable_email(email)` is `None`, answer `invalid_email` with no request.
- Otherwise POST to `CODE_PATH` with `{email: <trimmed>, locale: locale_of(params.locale as str)}` and no bearer.
- An empty `challenge_id` in the 202 is `server`.
- The result's `email` is the reply's, or the trimmed input when the reply's is empty.

**`finish`:**
- Params must be an object, with `challenge_id` a non-empty string and `code` a string, else `invalid_params`.
- If `clean_code(code)` is `None`, answer `invalid_code` with no request.
- The device is built exactly as in `auth_google`'s sign-in: `kind: "desktop"`, `auth::device_name`, `cfg.platform`, the b64url device public key.
- POST to `VERIFY_PATH` with `{challenge_id, code: <the six ASCII digits>, device}` and no bearer.
- A reply missing `token`, `user_id`, `device_id` or `email` is `server`.
- Then, under `auth_lock`, call `save_session` with `auth_method: Some("email")`, the relay's `email`, and the previous session's user as `previous_user`. `auth_lock` is never held during a request.

**Both calls** pass every relay error through one mapping. A code of `not_found`, `http_404` or `email_sign_in_disabled` becomes `CoreError::new("email_sign_in_disabled", "<path>: this relay has no email sign-in")`. Every other error is returned as it came, `http_502`, `http_503` and `http_504` included. Dispatch clears the shown fingerprints after a successful finish, as `auth.google.finish` does (`lib.rs:161-167`).

- [ ] **Step 1: Write the failing tests** in `tests/email.rs`. `REG` is as in `tests/auth_google.rs:7`, and `session_json(dir)` as in `tests/auth_google.rs:9-11`. `begin(core, email)` is `core.call("auth.email.begin", json!({"email": email, "locale": "en"}))`.

```rust
#[test] fn begin_asks_the_relay_for_a_code_and_returns_the_challenge() {
    // auth.email.begin {"email":"  Foo@Bar.com ","locale":"vi-VN"} -> challenge_id.len() == 43, (expires_in, resend_in) == (600, 60),
    // email == "foo@bar.com"; the one recorded request: POST CODE_PATH, body == {"email":"Foo@Bar.com","locale":"vi"},
    // no Authorization header; fake.email_locale("foo@bar.com") == Some("vi"); no session.json
}
#[test] fn locale_is_vi_or_en() { /* locale "VI" -> body.locale "vi"; "ja" -> "en"; no locale -> "en"; locale 5 -> "en" */ }
#[test] fn begin_refuses_an_address_the_relay_would_refuse_without_a_request() {
    // "phu@ẽample.com", "   ", an address of 255 bytes -> invalid_email each; no CODE_PATH request was recorded
}
#[test] fn finish_signs_in_and_writes_an_email_session() {
    // r = support::email_sign_in(&core, &fake, "Foo@Bar.com").unwrap(); (r["email"], r["auth_method"]) == ("foo@bar.com", "email");
    // user_id, device_id, device_public_key_b64, fingerprint non-empty; r.get("token").is_none(); session.json has auth_method
    // "email" and email "foo@bar.com", mode 0o600 on unix; fake.token_auth_method(&fake.issued_token()) == Some("email");
    // the VERIFY_PATH request: device.kind "desktop", device.platform "macos", device.public_key == r["device_public_key_b64"],
    // code == the mailbox code, no Authorization header; auth.session -> auth_method "email", email "foo@bar.com"; machines.list -> []
}
#[test] fn a_code_with_leading_zeros_is_sent_as_the_same_six_characters() {
    // fake.set_next_email_code("004217"); begin; finish "004217" -> Ok; the VERIFY_PATH body.code == "004217" (a JSON string)
}
#[test] fn a_pasted_code_with_spaces_or_wide_digits_is_sent_as_six_ascii_digits() {
    // set_next_email_code("123456"); finish with " １２３ 456\n" -> Ok; the VERIFY_PATH body.code == "123456"
}
#[test] fn a_code_that_is_not_six_digits_is_invalid_code_without_a_request() {
    // "12345", "1234567", "12a456", "123-456", "四五六七八九", "" -> invalid_code each; no VERIFY_PATH request was recorded;
    // then the mailbox code -> Ok (no guess was burned)
}
#[test] fn a_wrong_code_is_invalid_code_and_the_fifth_is_code_expired() { /* 4 x invalid_code, then code_expired; no session.json */ }
#[test] fn a_dead_code_is_code_expired() {
    // fake.expire_email_codes() -> code_expired; a challenge replaced by a second begin for the address -> code_expired;
    // after a successful sign-in the same challenge and code -> code_expired and session.json is unchanged
}
#[test] fn relay_refusals_keep_their_codes() {
    // begin "nope" -> invalid_email; "a@mailinator.com" -> disposable_email; fail_next(CODE_PATH, 429, "rate_limited") -> rate_limited;
    // fail_next_mail() -> email_send_failed; finish: fail_next(VERIFY_PATH, 429, "rate_limited") -> rate_limited;
    // fail_next(VERIFY_PATH, 400, "invalid_device") -> invalid_device
}
#[test] fn a_failed_mail_leaves_no_live_code_and_a_429_keeps_it() {
    // begin -> c1; fail_next_mail(); begin again -> email_send_failed; finish(c1, its code) -> code_expired;
    // begin -> c2; fail_next(CODE_PATH, 429, "rate_limited"); begin again -> rate_limited; finish(c2, its code) -> Ok
}
#[test] fn a_relay_without_email_sign_in_is_email_sign_in_disabled() {
    // FakeOptions { email_sign_in: false, .. }: begin -> email_sign_in_disabled; FakeOptions { email_routes: false, .. }: begin and
    // finish {"challenge_id":"c","code":"123456"} -> email_sign_in_disabled; default fake: fail_next(CODE_PATH, 404, "") ->
    // email_sign_in_disabled; no session.json
}
#[test] fn a_proxy_answer_without_a_body_is_http_status() {
    // fail_next(CODE_PATH, 502, "") -> http_502; fail_next(CODE_PATH, 503, "") -> http_503 (not email_sign_in_disabled);
    // after a real begin, fail_next(VERIFY_PATH, 504, "") -> http_504; no session.json
}
#[test] fn offline_is_network() {
    // api_base "http://127.0.0.1:1": begin -> network; finish {"challenge_id":"c","code":"123456"} -> network; no session.json
}
#[test] fn a_password_account_email_answers_switch_and_spends_the_code() {
    // auth.login {"email":"a@b.cd","password":"pw"}; begin "a@b.cd"; finish -> switch_from_signed_in_device;
    // the same challenge and code -> code_expired; session.json still has auth_method "password"
}
#[test] fn an_email_code_signs_into_the_google_account_with_that_address() {
    // (core, fake, _) = support::google_logged_out(); g = support::google_sign_in(&core, "sign_in"); auth.logout;
    // e = support::email_sign_in(&core, &fake, "google-user@shellx.test"); e["user_id"] == g["user_id"];
    // account.identities.list providers == ["google", "email"]
}
#[test] fn email_sign_in_after_a_401_keeps_the_device_id_and_machine() {
    // email sign-in, machines.register REG, fake.revoke_token(issued), machines.list -> unauthorized (machine.json and device.key
    // stay); email sign-in again -> same user_id and device_id; machines.list has is_this_machine true
}
#[test] fn params_are_checked() {
    // begin: json!("x"), {}, {"email": 5} -> invalid_params; finish: {}, {"challenge_id":"c"}, {"challenge_id":"","code":"123456"},
    // {"challenge_id":5,"code":"123456"} -> invalid_params
}
#[test] fn secrets_never_reach_results_or_errors() {
    // finish's result (as a string) contains neither the issued token, the mailbox code nor the challenge_id; the messages of an
    // invalid_code, a code_expired, a rate_limited and an email_sign_in_disabled error contain none of the token, the code, the
    // challenge_id or "foo@bar.com"; format!("{:?}") of an EmailCodeResponse parsed from {"challenge_id":"CH-SECRET","email":
    // "foo@bar.com"} contains neither "CH-SECRET" nor "foo@bar.com";
    // the local refusals the core writes itself: the invalid_email messages of begin {"email":"phu@ẽample.com"} and of begin with
    // the 255-byte address contain neither address; the invalid_code message of finish {"challenge_id":<the real one>,
    // "code":"12a456"} contains neither "12a456" nor the challenge_id
}
```

Unit tests in `src/auth_email.rs`. In this step the file holds only its `#[cfg(test)] mod tests` (with `use super::*;`), and `pub mod auth_email;` joins the `mod` list of `src/lib.rs` after `pub mod auth;`, so the red commit carries these tests too:
- `locale_of`: `Some("vi")` and `Some("Vi-VN")` → `"vi"`; `Some("en")`, `Some("ja")` and `None` → `"en"`.
- `sendable_email`: `"  a@b.cd "` → `Some("a@b.cd")`; a 254-byte address → `Some`; `""`, `"   "`, `"phu@ẽample.com"` and a 255-byte address → `None`.
- `decimal_digit`:
  - `'7'` → 7, `'٣'` (U+0663) → 3, `'۵'` (U+06F5) → 5, `'५'` (U+096B) → 5, `'５'` (U+FF15) → 5.
  - `'a'`, `'½'`, `'²'`, `'四'` and `'Ⅳ'` → `None`.
  - For every `DECIMAL_ZEROS` entry `z`, all of `z..=z+9` are `char::is_numeric`.
- `clean_code`: `"123456"`, `" 123 456\n"`, `"１２３４５６"` and `"١٢٣٤٥٦"` → `Some("123456")`; `"004217"` → `Some("004217")`; `"12345"`, `"1234567"`, `"12a456"`, `"123-456"` and `"四五六七八九"` → `None`.

- [ ] **Step 2: Run to verify they fail.** Run: `(cd shellx-core && cargo test --locked --test email; cargo test --locked --lib auth_email)`. Expected: the first fails to compile (`support::email_sign_in` missing) or fails with `unknown_method`; the second fails to compile (`locale_of`, `sendable_email`, `decimal_digit`, `clean_code` not found).
- [ ] **Step 3: Commit the failing tests.** `git add shellx-core/tests shellx-core/src/auth_email.rs shellx-core/src/lib.rs && git commit -m "test(shellx-core): email code sign-in RPCs"`
- [ ] **Step 4: Implement** the Interfaces, the dispatch arms and the two `KNOWN_METHODS` names. `SessionFile.auth_method`'s comment becomes `"password" | "google" | "email"`.
- [ ] **Step 5: Run to verify they pass.** Run: `(cd shellx-core && cargo test --workspace --locked && bash scripts/c-smoke.sh) && git diff --quiet develop -- shellx-core/Cargo.lock && echo lock-unchanged`. Expected: `test result: ok` everywhere, no new compiler warning, the smoke exits 0, and `lock-unchanged` is printed.
- [ ] **Step 6: Commit.** `git add shellx-core/src shellx-core/tests && git commit -m "feat(shellx-core): auth.email.begin and auth.email.finish"`

---

### Task 4: Swift core client, `ShellXAccount`, `AccountSignInMethod.Kind`

**Files:**
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/ShellXCoreClient+Email.swift`
- Modify: `…/ShellXRemoteCore/ShellXAccount.swift`: the `Identity.authMethod` comment :21; a new `// MARK: - Email code` section after `cancelGoogleSignIn` :161-167.
- Modify: `…/ShellXRemoteCore/ShellXCoreClient+Google.swift:27-42` (`AccountSignInMethod`)
- Modify: `…/Tests/ShellXRemoteCoreTests/ServiceTestSupport.swift`: the `FakeRemoteCore` state :20-29 and `call` :91-166.
- Create: `…/Tests/ShellXRemoteCoreTests/ShellXCoreClientEmailTests.swift`
- Modify: `…/Tests/ShellXRemoteCoreTests/ShellXAccountTests.swift`

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
/// Verifies the code and signs in like a Google `.signIn`: with the gate on it starts the remote session; saves
/// `Identity(authMethod: "email")`. Throws the core's code (nothing is saved then), or `google_in_progress` while a Google flow waits.
@discardableResult public func signInWithEmailCode(challengeID: String, code: String) async throws -> Identity
// ShellXCoreClient+Google.swift
extension AccountSignInMethod {
    public enum Kind: Equatable, Sendable { case google, apple, email }
    /// "apple" is `.apple`, "email" is `.email`, every other provider is `.google`.
    public var kind: Kind { get }
}
```

**`FakeRemoteCore`** gains `let emailCode = Locked("004217")`, so that leading zeros are always exercised, and two cases:
- `auth.email.begin` needs a string `email`, else `invalid_params`. It remembers the trimmed, lowercased address and answers `{"challenge_id":"ch-1","expires_in":600,"resend_in":60,"email":<that address>}`.
- `auth.email.finish` answers `code_expired` unless `challenge_id == "ch-1"`, and `invalid_code` unless `code == emailCode.get()`. Otherwise it sets `signedIn`, `sessionEmail` and `sessionAuthMethod = "email"`, and answers like `auth.google.finish`, with that address and `auth_method: "email"`.

`failures` and `holdNext` work for both, as for every method. The log line after a sign-in names no address.

- [ ] **Step 1: Write the failing tests.** `ShellXCoreClientEmailTests.swift` uses the `client` and `params` helpers as in `ShellXCoreClientGoogleTests.swift:5-17`:

```swift
@Suite("Core client: email sign-in") struct ShellXCoreClientEmailTests {
    @Test func beginSendsTheAddressAndLocaleAndReturnsTheChallenge() throws
    // reply {"ok":{"challenge_id":"ch1","expires_in":600,"resend_in":60,"email":"foo@bar.com"}}; beginEmailSignIn(email: "Foo@Bar.com", locale: "vi");
    // method "auth.email.begin"; params == ["email": .string("Foo@Bar.com"), "locale": .string("vi")];
    // result == EmailCodeChallenge(challengeID: "ch1", email: "foo@bar.com", expiresIn: 600, resendIn: 60)
    @Test func beginRefusesAReplyWithoutAChallenge() throws   // "challenge_id":"" -> ShellXCoreError code "bad_response"
    @Test func finishSendsTheChallengeAndCodeAndReturnsTheAccount() throws
    // method "auth.email.finish"; params == ["challenge_id": .string("ch1"), "code": .string("004217")];
    // result == GoogleSignInResult(userID: "u1", deviceID: "d1", email: "foo@bar.com", authMethod: "email")
    @Test func emailCallsKeepTheCoreErrorCode() throws        // {"error":{"code":"switch_from_signed_in_device","message":"x"}} -> that code
    @Test func signInMethodKindsFollowTheProvider() throws
    // signInMethods() over {"identities":[{"identity_id":"e1","provider":"email","email":"foo@bar.com"},{"identity_id":"g1","provider":"google",
    // "email":"g@x"},{"identity_id":"a1","provider":"apple"},{"identity_id":"t1","provider":"test"}]} -> kinds == [.email, .google, .apple, .google];
    // the email item is not isApple
}
```

`ShellXAccountTests.swift` gets a new section:

```swift
@MainActor @Test func emailCodeRequestConfiguresTheCoreAndChangesNoSession() async throws
// ServiceRig(gate: false, signedIn: false); requestEmailCode(email: "Foo@Bar.com", locale: "vi") -> challenge.email "foo@bar.com";
// rig.core.methods == ["config.set", "auth.email.begin"]; lastParams == ["email": "Foo@Bar.com", "locale": "vi"]; identity nil
@MainActor @Test func emailCodeSignsInAndSavesTheEmailIdentity() async throws
// then signInWithEmailCode(challengeID: challenge.challengeID, code: "004217"): identity.email "foo@bar.com", authMethod "email",
// usesPassword false, signedInAt != nil; ShellXAccount(service: rig.service).identity == account.identity; rig.launcher.calls.isEmpty;
// !rig.service.isSignedIn
@MainActor @Test func emailCodeSignInWithTheGateOnStartsTheSession() async throws
// ServiceRig(signedIn: false): rig.service.isSignedIn; await until { rig.service.hostState == rig.hostConnected }
@MainActor @Test func aWrongEmailCodeKeepsSignedOutAndCanBeRetried() async throws
// code "000000" -> errorCode "invalid_code", identity nil; then "004217" -> identity?.authMethod == "email"
@MainActor @Test func emailCodeSignInIsRefusedWhileGoogleWaits() async
// as cancelGoogleSignInCancelsTheWaitingFlow (:116-130): a Google sign-in held in auth.google.finish; signInWithEmailCode(challengeID: "ch-1",
// code: "004217") -> "google_in_progress"; rig.core.count("auth.email.finish") == 0; then cancelGoogleSignIn and releaseHeldCall
```

- [ ] **Step 2: Run to verify they fail.** Run: `swift test --package-path Packages/Shared/ShellXBrand --filter "ShellXCoreClientEmailTests|emailCode|aWrongEmailCode"`. Expected: compile errors (`beginEmailSignIn`, `requestEmailCode`, `kind` missing).
- [ ] **Step 3: Commit the failing tests.** `git add Packages/Shared/ShellXBrand/Tests/ShellXRemoteCoreTests && git commit -m "test(shellx): email code sign-in through the core client and the account"`
- [ ] **Step 4: Implement** the Interfaces. `signInWithEmailCode` guards `googleStep == .idle`, then mirrors the `.signIn` branch of `signInWithGoogle` (`ShellXAccount.swift:130-157`) without the browser: `prepareLocal()` with the gate on, `ensureConfigured()`, the core call off the main actor, `beginSignedInSession` with the gate on, then `save`.
- [ ] **Step 5: Run to verify they pass.** Run: `swift test --package-path Packages/Shared/ShellXBrand`, then the Swift 6.0 check (Global Constraints). Expected: all tests pass, and the check prints nothing.
- [ ] **Step 6: Commit.** `git add Packages/Shared/ShellXBrand && git commit -m "feat(shellx): the account requests and verifies an email sign-in code"`

---

### Task 5: Strings: email-path sentences, sheet texts and the 18 Mac keys

**Files:**
- Modify: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteUI/SignInErrorMessage.swift`
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteUI/EmailSignInTexts.swift`
- Modify: `Packages/Shared/ShellXBrand/Tests/ShellXRemoteUITests/ShellXRemoteUITests.swift:209-228` (`signInErrorMapping`), with the new tests in the same suite.
- Modify: `Sources/ShellX/Remote/UI/RemoteUISnapshot.swift:28-58` (`SignInErrorLabels.localized`, with `EmailSignInTexts.localized` beside it). Stage 2 compiles it.
- Modify: `Sources/ShellX/ShellXAccountDetailView.swift:70-98`: `methodRow`'s title follows `method.kind`. Stage 2 compiles it.
- Modify: `Resources/Localizable.xcstrings`, `tests/test_shellx_vi.py`; `scripts/localization-allowed-omissions.json` only if an identity record is needed.

**Interfaces:**
- Produces:

```swift
public struct SignInErrorLabels: Equatable, Sendable {
    // existing eight, then:
    public let invalidEmail, disposableEmail, invalidCode, codeExpired, emailSendFailed, unavailable, rateLimited, server: String
    public init(credentials: String, network: String, timeout: String, stateMismatch: String,
                switchFromSignedInDevice: String, emailInUse: String, identityInUse: String, browser: String,
                invalidEmail: String, disposableEmail: String, invalidCode: String, codeExpired: String,
                emailSendFailed: String, unavailable: String, rateLimited: String, server: String)
    public static let english   // the en column of the String table for the eight new labels
}
public enum SignInErrorMessage {
    // text(forCode:labels:), text(for:labels:), isCancellation(_:): unchanged (the Google path, D2)
    /// The email path (D2): invalid_email, disposable_email, invalid_code, code_expired, email_send_failed,
    /// email_sign_in_disabled (-> unavailable), rate_limited, switch_from_signed_in_device, network; any other code -> server.
    public static func emailText(forCode code: String, labels: SignInErrorLabels) -> String
    /// A non-core error (the transport threw before the core answered) reads as the network sentence.
    public static func emailText(for error: any Error, labels: SignInErrorLabels) -> String
}
/// The email steps' texts, injected so this module needs no bundle (the app passes `.localized`).
public struct EmailSignInTexts: Equatable, Sendable {
    public let field, send, or, code, verify, resend, change: String
    public let sentToFormat: String      // "%@" = the relay's address
    public let resendInFormat: String    // "%@" = the whole seconds as text
    public init(field: String, send: String, or: String, sentToFormat: String, code: String, verify: String,
                resend: String, resendInFormat: String, change: String)
    public static let english            // the en column of the String table
    public func sentTo(_ address: String) -> String
    public func resendIn(seconds: Int) -> String
}
// app, RemoteUISnapshot.swift: SignInErrorLabels.localized gains eight String(localized:defaultValue:) with the table's keys;
// extension EmailSignInTexts { static var localized: EmailSignInTexts } with the nine remote.signin.email.* keys
// app, ShellXAccountDetailView.methodRow: the title is settings.account.methods.apple / .email ("Email code") / .google by method.kind;
// the address line and the Apple-only Remove are unchanged
```

- [ ] **Step 1: Write the failing tests.**
  - `labels` moves out of `signInErrorMapping` (today a local at `ShellXRemoteUITests.swift:210-212`) into the suite, so both mapping tests use it: `private let labels = SignInErrorLabels(credentials: "Google sign-in didn't work. Try again.", network: "Can't reach relay.shellx.pro", timeout: "t", stateMismatch: "s", switchFromSignedInDevice: "sw", emailInUse: "e", identityInUse: "i", browser: "b", invalidEmail: "ie", disposableEmail: "de", invalidCode: "ic", codeExpired: "ce", emailSendFailed: "sf", unavailable: "un", rateLimited: "rl", server: "sv")`. The local `let labels` of `RemoteMachineLabels` in another test of the suite (:83) shadows it, which Swift allows. `signInErrorMapping`'s raw `rate_limited` line stays, because the Google path is unchanged.
  - Two new tests in the same suite:

```swift
@Test func emailSignInErrorMapping() {
    // for (code, text) in [("invalid_email","ie"), ("disposable_email","de"), ("invalid_code","ic"), ("code_expired","ce"),
    //   ("email_send_failed","sf"), ("email_sign_in_disabled","un"), ("rate_limited","rl"), ("switch_from_signed_in_device","sw"),
    //   ("network","Can't reach relay.shellx.pro")] -> emailText(forCode: code, labels: labels) == text;
    // for code in ["http_502","http_503","http_504","server","invalid_device","invalid_params","bad_response","google_in_progress","weird_code"]
    //   -> "sv"; emailText(for: URLError(.notConnectedToInternet), labels: labels) == "Can't reach relay.shellx.pro";
    // SignInErrorLabels.english.unavailable == "This way of signing in isn't available in this build.";
    // SignInErrorLabels.english.server == "ShellX is having a problem. Try again later."
}
@Test func emailSignInTextsFillTheirPlaceholders() {
    // EmailSignInTexts.english.sentTo("foo@bar.com") == "We sent a 6-digit code to foo@bar.com. If it isn't there in a minute, check your spam folder.";
    // .resendIn(seconds: 42) == "Resend code in 42 s"; .field == "Email address"
}
```

  - In `tests/test_shellx_vi.py`, inside `VietnameseCatalogTests`, add two tests, and add `"settings.account.methods.email": ("Email code", "Mã qua email")` to `test_account_settings_strings_read_naturally` (:218-227):

```python
def test_email_sign_in_errors_read_naturally(self):
    expected = {...}  # the eight remote.signin.error.* rows of the String table: key -> (en, vi)
    for key, (en, vi) in expected.items():
        self.assertEqual((self.en(key), self.vi(key)), (en, vi), key)

def test_email_sign_in_sheet_strings_read_naturally(self):
    expected = {...}  # the nine remote.signin.email.* rows: field, send, or, sentTo, code, verify, resend, resendIn, change
    for key, (en, vi) in expected.items():
        self.assertEqual((self.en(key), self.vi(key)), (en, vi), key)
```

- [ ] **Step 2: Run to verify they fail.** Run: `swift test --package-path Packages/Shared/ShellXBrand --filter "signInErrorMapping|emailSignInErrorMapping|emailSignInTextsFillTheirPlaceholders"; python3 tests/test_shellx_vi.py VietnameseCatalogTests.test_email_sign_in_errors_read_naturally VietnameseCatalogTests.test_email_sign_in_sheet_strings_read_naturally VietnameseCatalogTests.test_account_settings_strings_read_naturally`. Expected: a Swift compile error (extra arguments, `emailText` and `EmailSignInTexts` missing), and Python FAIL (`(None, None) != …`).
- [ ] **Step 3: Commit the failing tests.** `git add Packages/Shared/ShellXBrand/Tests/ShellXRemoteUITests/ShellXRemoteUITests.swift tests/test_shellx_vi.py && git commit -m "test(shellx): email sign-in sentences and texts"`
- [ ] **Step 4: Implement** the labels, `emailText`, `EmailSignInTexts`, the two app-side `.localized` builders and the row title.
- [ ] **Step 5: Localize.**
  - Run `./scripts/localize-changes --base develop`. It picks up all 18 keys from the two app files.
  - Fill every row of the printed work packet: `en` and `vi` exactly from the String table; translate de, fr, ar, es, zh-Hant, zh-Hans, ko and ja.
  - Run it again. Expected last line: `Localization ready: changed work is complete and the strict catalog validator passed.`
- [ ] **Step 6: Run to verify they pass.** Run: `swift test --package-path Packages/Shared/ShellXBrand && python3 tests/test_shellx_vi.py && python3 scripts/localization_catalog.py check && python3 scripts/verify-local.py --affected develop --swift-changed develop`, then the Swift 6.0 check (Global Constraints). Expected: tests pass, `OK`, no catalog errors, `verify-local.py` clean apart from the known `feature-flags` noise, and the check prints nothing. It matters most here: `SignInErrorLabels.init` now takes 16 labels and `EmailSignInTexts.init` nine, so a trailing comma is easy to leave. The app-side lines are first compiled in Task 8 Step 1.
- [ ] **Step 7: Commit.** `git add Packages/Shared/ShellXBrand/Sources/ShellXRemoteUI Sources/ShellX/Remote/UI/RemoteUISnapshot.swift Sources/ShellX/ShellXAccountDetailView.swift Resources/Localizable.xcstrings scripts/localization-allowed-omissions.json && git commit -m "feat(shellx): email code sign-in sentences and texts in every Mac language"`

---

### Task 6: `EmailSignInModel` and `SignInSheetFlows`

**Files:**
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteUI/EmailSignInModel.swift`, `…/ShellXRemoteUI/SignInSheetFlows.swift`
- Modify: `…/ShellXRemoteUI/GoogleSignInModel.swift` (adds `clearError()`)
- Create: `…/Tests/ShellXRemoteUITests/EmailSignInModelTests.swift`, `…/Tests/ShellXRemoteUITests/SignInSheetFlowsTests.swift`
- Modify: `…/Tests/ShellXRemoteUITests/GoogleSignInModelTests.swift`

**Interfaces:**
- Consumes: `EmailCodeChallenge` (Task 4); `SignInErrorLabels` and `SignInErrorMessage.emailText` (Task 5); `GoogleSignInModel`.
- Produces:

```swift
/// State of the email part of the sign-in sheet. The two calls are injected (`ShellXAccount`), so this module stays free
/// of the account and the bundle. Nothing here logs an address, a code or a challenge id.
@MainActor @Observable public final class EmailSignInModel {
    public enum Step: Equatable, Sendable { case email, sending, code, verifying, done(email: String) }
    public static let codeLength = 6
    public private(set) var step: Step            // .email at first: the sheet opens on the email step
    public private(set) var email: String         // what the email field holds; kept through the code step
    public private(set) var errorText: String?    // the last failure as a sentence
    public private(set) var sentTo: String?       // the relay's address while the code step shows; nil on the email step
    public private(set) var code: String          // ASCII digits only, at most six
    public private(set) var focusRequest: Int     // grows each time the shown field should take the keyboard
    public var emailFieldError: String? { get }   // errorText, else labels.invalidEmail while the trimmed address holds a non-ASCII character
    public var canSend: Bool { get }              // .email and isPlausibleEmail(email)
    public var codeIsLive: Bool { get }           // a challenge the relay may still take
    public var canEditCode: Bool { get }          // .code and codeIsLive
    public var canVerify: Bool { get }            // .code, codeIsLive, six digits
    public var isBusy: Bool { get }               // .sending or .verifying
    @ObservationIgnored public var onFinished: (@MainActor (Bool) -> Void)?   // once: true after finish(), false after cancel()
    public init(labels: SignInErrorLabels,
                requestCode: @escaping @MainActor (String) async throws -> EmailCodeChallenge,
                verify: @escaping @MainActor (String, String) async throws -> String,   // (challengeID, code) -> account email
                now: @escaping @MainActor () -> Date = { Date() })
    /// Trimmed: ASCII only, no whitespace inside, an "@" that is not first, then a "." neither right after it nor last.
    public static func isPlausibleEmail(_ text: String) -> Bool
    /// The first six Unicode decimal digits (General_Category Nd) of `raw`, as ASCII.
    public static func digits(_ raw: String) -> String
    public func setEmail(_ text: String)                                              // the field changed (.email only); clears errorText
    @discardableResult public func sendCode() -> Task<Void, Never>?                    // from .email when canSend
    @discardableResult public func resend() -> Task<Void, Never>?                      // from .code once the lock is over
    public func resendWait(at date: Date) -> Int                                       // whole seconds left, rounded up; 0 = unlocked
    @discardableResult public func setCode(_ raw: String) -> Task<Void, Never>?        // stores digits(raw); may submit
    @discardableResult public func submitCode() -> Task<Void, Never>?                  // from .code when canVerify
    public func clearError()
    public func useDifferentEmail()                                                    // .code -> .email, the address kept
    public func cancel()
    public func finish()                                                               // only in .done
}
/// The email-first sheet's two flows (D3): one runs at a time, and only the last failure shows.
@MainActor public enum SignInSheetFlows {
    /// The email field and Send code take input: not while Google waits.
    public static func emailEnabled(google: GoogleSignInModel) -> Bool
    /// Continue with Google can be pressed: Google `.ready`, and the email model (if any) on `.email`, so not while it sends.
    public static func googleEnabled(google: GoogleSignInModel, email: EmailSignInModel?) -> Bool
    /// Send code: nil unless `emailEnabled`; clears Google's failure, then `email.sendCode()`.
    @discardableResult public static func sendCode(google: GoogleSignInModel, email: EmailSignInModel) -> Task<Void, Never>?
    /// Continue with Google: nil unless `googleEnabled`; clears the email failure, then `google.start()`.
    @discardableResult public static func startGoogle(google: GoogleSignInModel, email: EmailSignInModel?) -> Task<Void, Never>?
    /// The email field changed: `google.clearError()`, then `email.setEmail(text)`, so typing hides Google's failure.
    public static func setEmail(google: GoogleSignInModel, email: EmailSignInModel, text: String)
    /// The sentence under the email field: nil while Google's failure shows, else `email.emailFieldError`. The
    /// invalid-email sentence of a non-ASCII address is computed from the text, so no start clears it.
    public static func emailFieldError(google: GoogleSignInModel, email: EmailSignInModel) -> String?
}
// GoogleSignInModel
/// Forgets the shown failure (only in `.ready`).
public func clearError()
```

**Rules.** Every sentence comes from `SignInErrorMessage.emailText(for:labels:)`.
- **Send code.** `sendCode` trims `email` in place, goes to `.sending` with `errorText` nil, and calls `requestCode`.
  - Success: `.code`, with `sentTo = challenge.email`, an empty `code`, and the lock ending at `now() + challenge.resendIn`.
  - Failure: `.email` with the sentence.
- **Resend.** `resend` calls `requestCode` with the kept, trimmed `email`, as `sendCode` does (and as Plan B's `EmailResendRequested` sends its remembered address); the relay normalizes either spelling to the same address. It does nothing outside `.code` or while `resendWait(at: now()) > 0`, and goes through `.sending`.
  - Success: the same as a send (a new challenge, an empty code, a new lock).
  - Failure: `.code` with the sentence, and the lock ends. `email_send_failed` and `email_sign_in_disabled` also drop the challenge and the digits; any other failure keeps the challenge (D2).
- **Typing the code.** `setCode` works only in `.code` with a live challenge. It stores `digits(raw)`, and a change clears `errorText`. When the stored digits have changed and number six, it submits by itself. `submitCode` is the manual path.
- **Verifying.**
  - Success: `.done(email:)`.
  - `invalid_code`: `.code`, with the digits emptied and the sentence.
  - `code_expired`: `.code`, with the digits emptied, the challenge dropped, the lock ended and the sentence.
  - `switch_from_signed_in_device`: `.email`, with the address kept; the challenge, `sentTo` and the digits dropped; the lock ended; and the sentence.
  - Any other failure: `.code`, with the digits and the challenge kept and the sentence. That includes `email_sign_in_disabled` (only a relay without the feature answers it on verify, as a 404), as on both phones and in the Interfaces table.
- **Address.** `setEmail` stores the text and clears `errorText`.
- **Use a different email.** `useDifferentEmail` drops the challenge, `sentTo`, the digits, the error and the lock, and returns to `.email` with the address kept.
- **Focus.** `focusRequest` grows whenever the step becomes `.email`, or becomes `.code` with a live challenge.
- **Closing.** `cancel` reports `false` once and makes every answer still on its way a no-op. It never cancels a request's `Task`, so a verify already sent runs to its end and the account keeps the session it creates (D3, Ruling 12). `finish` reports `true` once.
- **Late answers.** An answer that belongs to an earlier request (after `useDifferentEmail`, `cancel` or a newer request) is ignored. A request counter is compared when each answer arrives.
- **One failure on screen (`SignInSheetFlows`, D3).** Each start clears the other flow's failure. Typing in the email field goes through `setEmail(google:email:text:)`, which hides Google's failure. The sheet draws `emailFieldError(google:email:)`, which stays empty while Google's failure shows. Without these two, a Google failure would stay on screen beside the invalid-email sentence of an address being typed, or of a "phu@ẽ" left in the field when Google failed.

- [ ] **Step 1: Write the failing tests** in `EmailSignInModelTests.swift`.
  - A `@MainActor` `Gate<Value>`, like `GoogleSignInModelTests.swift:7-17`, keeps `requestCode` or `verify` pending and records its arguments.
  - The injected clock is `@MainActor final class Clock { var now = Date(timeIntervalSince1970: 1_000) }`.
  - `labels` is `SignInErrorLabels.english`.
  - `challenge("ch-1")` is `EmailCodeChallenge(challengeID: "ch-1", email: "foo@bar.com", expiresIn: 600, resendIn: 60)`.
  - `toCodeStep()` runs `setEmail("Foo@Bar.com")` and `sendCode()`, then resolves `challenge("ch-1")`.

```swift
@MainActor @Suite("Email sign-in model") struct EmailSignInModelTests {
    @Test func theSheetStartsOnTheEmailStep()                      // .email, email "", errorText nil, sentTo nil, canSend false
    @Test func plausibleEmailNeedsAsciiAnAtAndADotAfterIt()        // true: "a@b.c", " a@b.co "; false: "", "a@b", "a@.c", "a@b.", "@b.c",
                                                                   // "a b@c.d", "phu@ẽample.com"
    @Test func aNonAsciiAddressShowsTheInvalidEmailSentenceAtOnce() // setEmail("phu@ẽ") -> emailFieldError == labels.invalidEmail, canSend false,
                                                                   // sendCode() == nil, requestCode never ran; setEmail("phu@example.com") ->
                                                                   // emailFieldError nil, canSend true
    @Test func sendCodeShowsSendingThenTheCodeStep() async         // setEmail("  Foo@Bar.com "); sendCode() -> .sending at once, requestCode got
                                                                   // "Foo@Bar.com", email "Foo@Bar.com"; after challenge("ch-1"): .code, sentTo
                                                                   // "foo@bar.com", errorText nil, code "", resendWait(at: clock.now) == 60, focusRequest grew
    @Test func sendCodeTwiceSendsOnce() async                      // the second sendCode() returns nil; requestCode ran once
    @Test func aRefusedAddressReturnsToTheEmailStepWithItsSentence() async // invalid_email -> .email + labels.invalidEmail; disposable_email ->
                                                                   // disposableEmail; email_send_failed -> emailSendFailed; setEmail(..) clears errorText; then a send works
    @Test func aRelayWithoutEmailSignInSaysUnavailable() async     // D2 row 8: email_sign_in_disabled on Send -> .email + labels.unavailable;
                                                                   // on verify (toCodeStep, setCode("123456")) -> .code + labels.unavailable,
                                                                   // code "123456" kept, codeIsLive, canVerify; submitCode() verifies against "ch-1" again
    @Test func aRateLimitShowsItsSentenceAndSendWorksAgainAtOnce() async // D2 row 6: rate_limited on Send -> .email + labels.rateLimited;
                                                                   // sendCode() returns a task at once (no re-lock)
    @Test func answersWithoutTheirOwnSentenceReadAsTheServerSentence() async // D2 row 7: on Send http_502, http_503, http_504, server, invalid_params
                                                                   // -> .email + labels.server; on verify http_503 and invalid_device -> .code + labels.server,
                                                                   // code kept, canVerify
    @Test func offlineShowsTheNetworkMessageAndAllowsRetry() async // requestCode throws URLError(.notConnectedToInternet) -> .email + labels.network;
                                                                   // sendCode() again reaches .code
    @Test func pastedCodeKeepsOnlySixDigits() async                // digits(" 123 456\n") == "123456"; digits("12a34") == "1234"; digits("1234567890") ==
                                                                   // "123456"; digits("１２３４５６") == "123456"; digits("٠٠٤٢١٧") == "004217";
                                                                   // digits("Your ShellX sign-in code is 004217") == "004217"; digits("四五六") == "";
                                                                   // on the code step setCode("12 3") -> code "123", no task
    @Test func aCodeWithLeadingZerosIsSentAsIs() async             // setCode("004217") returns a task; verify got ("ch-1", "004217")
    @Test func sixDigitsSubmitByThemselvesOnce() async             // setCode("123 456") returns a task; .verifying; verify got ("ch-1", "123456");
                                                                   // setCode("123456") and submitCode() while verifying -> nil; verify ran once;
                                                                   // resolve "foo@bar.com" -> .done(email: "foo@bar.com")
    @Test func aWrongCodeEmptiesTheFieldAndStaysOnTheCodeStep() async // D2 row 1: invalid_code -> .code + labels.invalidCode, code "", codeIsLive,
                                                                   // canEditCode, !canVerify, sentTo kept, resendWait(at: clock.now) > 0, focusRequest grew;
                                                                   // setCode("6") clears errorText; setCode("654321") submits (verify ran twice)
    @Test func aDeadCodeTurnsTheFieldOffAndUnlocksResend() async   // D2 row 2: code_expired -> .code + labels.codeExpired, code "", !codeIsLive,
                                                                   // !canEditCode, setCode("123456") == nil, resendWait(at: clock.now) == 0; resend() ->
                                                                   // requestCode got "Foo@Bar.com" (the kept address, not sentTo "foo@bar.com");
                                                                   // with challenge("ch-2") a code verifies against "ch-2"
    @Test func aSwitchAnswerGoesBackToTheEmailStepWithTheAddress() async // D2 row 3: switch_from_signed_in_device -> .email, email "Foo@Bar.com",
                                                                   // sentTo nil, code "", emailFieldError == labels.switchFromSignedInDevice, resendWait 0,
                                                                   // focusRequest grew; submitCode() == nil; sendCode() sends "Foo@Bar.com" again
    @Test(arguments: ["rate_limited", "offline"])
    func aResendRefusedForRateOrNetworkKeepsTheCode(_ failure: String) async // D2 rows 4 and 6: at t0 + 60 the resend throws ShellXCoreError
                                                                   // rate_limited, or URLError(.notConnectedToInternet) -> .code, labels.rateLimited /
                                                                   // labels.network, sentTo kept, codeIsLive, resendWait(at: clock.now) == 0;
                                                                   // a code still verifies against "ch-1"
    @Test(arguments: ["email_send_failed", "email_sign_in_disabled"])
    func aResendTheRelayCouldNotMailLeavesNoCodeToVerify(_ code: String) async // D2 row 5: the resend fails -> .code, labels.emailSendFailed /
                                                                   // labels.unavailable, !codeIsLive, code "", !canVerify, setCode("123456") == nil,
                                                                   // resendWait 0; resend() with challenge("ch-2") -> a code verifies against "ch-2"
    @Test func resendIsLockedForSixtySecondsAndCountsDown() async  // from the code step at t0: resendWait(at: t0) == 60, (t0 + 0.5) == 60,
                                                                   // (t0 + 59.2) == 1, (t0 + 60) == 0; clock.now = t0 + 30: resend() == nil; clock.now = t0 + 60:
                                                                   // resend() runs, .sending, requestCode's second call got "Foo@Bar.com", then .code with
                                                                   // resendWait(at: clock.now) == 60
    @Test func useADifferentEmailGoesBackWithTheAddress() async    // -> .email, email "Foo@Bar.com", sentTo nil, code "", errorText nil, resendWait 0,
                                                                   // focusRequest grew; submitCode() == nil
    @Test func cancelWhileSendingIgnoresTheLateChallenge() async   // cancel() -> onFinished values [false]; then the challenge arrives: step is not .code
    @Test func cancelWhileVerifyingClosesOnceAndIgnoresTheResult() async // cancel() while verifying -> [false]; verify succeeds: step is not .done,
                                                                   // values still [false]; finish() adds nothing; the gated verify closure records
                                                                   // Task.isCancelled right after its gate opens: false (the request ran to its end,
                                                                   // so the account keeps the session)
    @Test func doneReportsOnceWhenThePersonConfirms() async        // .done: finish() -> [true]; finish() and cancel() add nothing
}
```

`SignInSheetFlowsTests.swift` and `GoogleSignInModelTests.swift`:

```swift
@MainActor @Suite("Sign-in sheet flows") struct SignInSheetFlowsTests {
    @Test func eachStartClearsTheOtherFlowsFailure() async   // Google fails (errorText set); setEmail + SignInSheetFlows.sendCode -> google.errorText nil;
                                                             // the send fails (email.errorText set); SignInSheetFlows.startGoogle -> email.errorText nil
    @Test func onlyOneFailureShowsWhileTyping() async        // Google fails; SignInSheetFlows.setEmail(google:email:text: "phu@ẽ") -> google.errorText nil,
                                                             // email.email "phu@ẽ", emailFieldError(google:email:) == labels.invalidEmail; with "phu@ẽ" still
                                                             // typed, startGoogle and a Google failure -> google.errorText set and
                                                             // emailFieldError(google:email:) nil; setEmail(.., text: "phu@ẽx") -> the invalid-email
                                                             // sentence again, google.errorText nil
    @Test func theTwoFlowsNeverRunTogether() async           // while Google waits: emailEnabled false, sendCode(..) nil, requestCode never ran;
                                                             // while a send is pending: googleEnabled false, startGoogle(..) nil; on the code step: googleEnabled false
}
@MainActor @Test func clearErrorRemovesTheLastFailure() async  // a failed start -> errorText set; clearError() -> nil, phase .ready
```

- [ ] **Step 2: Run to verify they fail.** Run: `swift test --package-path Packages/Shared/ShellXBrand --filter "EmailSignInModelTests|SignInSheetFlowsTests|clearErrorRemovesTheLastFailure"`. Expected: compile errors (`EmailSignInModel`, `SignInSheetFlows`, `clearError` not found).
- [ ] **Step 3: Commit the failing tests.** `git add Packages/Shared/ShellXBrand/Tests/ShellXRemoteUITests && git commit -m "test(shellx): email sign-in model follows every relay answer"`
- [ ] **Step 4: Implement** the model, the flows and `clearError()`.
- [ ] **Step 5: Run to verify they pass.** Run: `swift test --package-path Packages/Shared/ShellXBrand && python3 scripts/verify-local.py --affected develop --swift-changed develop`, then the Swift 6.0 check (Global Constraints). Expected: all tests pass; `verify-local.py` clean apart from the known `feature-flags` noise; the check prints nothing.
- [ ] **Step 6: Commit.** `git add Packages/Shared/ShellXBrand/Sources/ShellXRemoteUI && git commit -m "feat(shellx): email sign-in model with a resend lock, one flow at a time"`

---

### Task 7: `SignInTextField`, the Roman-only field (D4)

**Files:**
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteUI/SignInTextField.swift`
- Create: `Packages/Shared/ShellXBrand/Tests/ShellXRemoteUITests/SignInTextFieldTests.swift`

**Interfaces:**
- Produces:

```swift
/// A one-line AppKit field for the sign-in sheet. Its own field editor allows only Roman input sources while it is focused,
/// so Apple's Vietnamese Telex and VNI are not offered; autocorrection and text replacement are off. Return calls
/// `onSubmit` and Escape calls `onCancel`, except while a composition is open (the input method gets those keys); the
/// field takes the keyboard when it appears and whenever `focusRequest` changes.
public struct SignInTextField: NSViewRepresentable {
    public init(text: String, placeholder: String, contentType: NSTextContentType?, font: NSFont, isEnabled: Bool,
                focusRequest: Int, onChange: @escaping @MainActor (String) -> Void,
                onSubmit: @escaping @MainActor () -> Void, onCancel: @escaping @MainActor () -> Void)
}
/// The field behind `SignInTextField`; its cell hands out the field's own `RomanInputFieldEditor`.
public final class RomanInputTextField: NSTextField
/// A field editor that sets `inputContext?.allowedInputSourceLocales = [NSAllRomanInputSourcesLocaleIdentifier]` each time it
/// becomes first responder. One per field, so the window's shared field editor is untouched.
public final class RomanInputFieldEditor: NSTextView
```

**Rules:**
- **The cell.** `RomanInputTextField`'s cell, an `NSTextFieldCell` subclass, returns its own lazily made `RomanInputFieldEditor` from `fieldEditor(for:)`. The precedent is `Packages/macOS/CmuxBrowser/Sources/CmuxBrowser/Omnibar/BrowserOmnibarPasteTextFieldCell.swift:25-27`.
- **The editor.** `isFieldEditor` is always true. It applies the restriction in `becomeFirstResponder()`, and turns off continuous spell checking, automatic spelling correction, text replacement, and quote and dash substitution.
- **The field.** Single line (`wraps = false`, `isScrollable = true`), with the given `contentType` (`.emailAddress`, available on macOS 14, the deployment target; `.oneTimeCode` for the code field) and font.
- **The coordinator** is the field's delegate:
  - `controlTextDidChange` calls `onChange(field.stringValue)` on every change, a composition's marked text included, as `Sources/SidebarSearchFieldCoordinator.swift:11-14` does. A composition that ends without a text change still reaches the model, and `updateNSView` never writes into a composition.
  - `control(_:textView:doCommandBy:)` returns false while `textView.hasMarkedText()`. Return and Escape then stay with the editor and the input method during an IME or dead-key composition (Option-E, Option-U), and the sheet neither submits nor closes mid-composition. This is the repo's rule since issue #118: `Sources/Find/SurfaceSearchOverlay.swift:321-322,338-340`, `Sources/SidebarSearchFieldCoordinator.swift:17`, `Sources/Panels/BrowserPanelView.swift:4565`. Otherwise it maps `insertNewline(_:)` to `onSubmit()` and `cancelOperation(_:)` to `onCancel()` and returns true. Both are then handled, so Return never reaches Google and Escape never opens completion. Every other command returns false.
- **`updateNSView`**, on every update, as `Sources/Sidebar/SidebarInlineRenameField.swift:41-53` and `Sources/SidebarSearchFieldView.swift:23-35` do (the latter also keeps a composition):
  - It stores the current `onChange`, `onSubmit` and `onCancel` in the coordinator, so a reused view never calls a stale closure.
  - It refreshes the placeholder, font, `contentType` and `isEnabled`.
  - It writes `text` only when it differs from the field's string and the editor has no marked text.
  - On the first move into a window, or when `focusRequest` has changed, it calls `window.makeFirstResponder(field)` on the next main-queue turn.

- [ ] **Step 1: Write the failing tests.** Host the field as `Packages/macOS/CmuxSwiftRenderUI/Tests/CmuxSwiftRenderUITests/SceneTextFieldAutofocusTests.swift:56-80` does: `_ = NSApplication.shared`, an off-screen borderless `NSWindow`, `orderBack(nil)`. The suite is `.serialized` like that precedent (`:16-18`): its async tests wait on main-queue turns and on first-responder state, which tests running at the same time would disturb.

```swift
@MainActor @Suite("Sign-in text field", .serialized) struct SignInTextFieldTests {
    @Test func theFocusedFieldAllowsOnlyRomanInputSources() throws
    // a RomanInputTextField and a plain NSTextField in the window; window.makeFirstResponder(field);
    // editor = try #require(field.currentEditor() as? RomanInputFieldEditor);
    // #expect(editor.inputContext?.allowedInputSourceLocales == [NSAllRomanInputSourcesLocaleIdentifier]);
    // window.makeFirstResponder(plain): plain.currentEditor() is not a RomanInputFieldEditor, and its inputContext's
    // allowedInputSourceLocales is nil (the window's shared editor is untouched)
    @Test func theEditorDoesNotCorrectAnAddress() throws
    // isContinuousSpellCheckingEnabled, isAutomaticSpellingCorrectionEnabled, isAutomaticTextReplacementEnabled,
    // isAutomaticQuoteSubstitutionEnabled, isAutomaticDashSubstitutionEnabled all false; field.contentType == .emailAddress
    @Test func typingReachesOnChange() async throws
    // SignInTextField in an NSHostingView in the window, focused; editor.insertText("phu@", replacementRange: NSRange(location: NSNotFound,
    // length: 0)) -> onChange got "phu@"
    @Test func returnSubmitsAndEscapeCancels() async throws
    // editor.doCommand(by: #selector(NSResponder.insertNewline(_:))) -> submits == 1, cancels == 0;
    // editor.doCommand(by: #selector(NSResponder.cancelOperation(_:))) -> cancels == 1
    @Test func returnAndEscapeWaitForAComposition() async throws
    // focused; editor.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound,
    // length: 0)); editor.hasMarkedText(); delegate = try #require(field.delegate); delegate.control?(field, textView: editor,
    // doCommandBy: #selector(NSResponder.insertNewline(_:))) == false, and the same for cancelOperation(_:) == false; submits == 0,
    // cancels == 0. The delegate is called directly: when it returns false, editor.doCommand(by:) would run the field editor's own
    // insertNewline and end editing. Then editor.unmarkText(); editor.doCommand(by: #selector(NSResponder.insertNewline(_:))) -> submits == 1
    @Test func theFieldTakesTheKeyboardWhenItAppearsAndWhenAsked() async throws
    // hosted with focusRequest 0: after one main-queue turn window.firstResponder is an NSText whose delegate is the field;
    // window.makeFirstResponder(a stand-in view); the root view again with focusRequest 1 and a new onSubmit -> the field's editor
    // is first responder again, and Return reaches the new onSubmit, not the first one
}
```

  The fallback D4 allows: if `editor.inputContext` is nil under `swift test` (an off-screen, non-key window), wrap that one assertion in `withKnownIssue` with the reason, say so in the hand-off, and rely on Task 9 Step 4. If that check shows Telex still offered, report the restriction as not working; the ASCII rule and its sentence stand alone.
- [ ] **Step 2: Run to verify they fail.** Run: `swift test --package-path Packages/Shared/ShellXBrand --filter SignInTextFieldTests`. Expected: compile errors (`RomanInputTextField`, `SignInTextField` not found).
- [ ] **Step 3: Commit the failing tests.** `git add Packages/Shared/ShellXBrand/Tests/ShellXRemoteUITests/SignInTextFieldTests.swift && git commit -m "test(shellx): the sign-in field allows only Roman input sources"`
- [ ] **Step 4: Implement** the Interfaces.
- [ ] **Step 5: Run to verify they pass.** Run: `swift test --package-path Packages/Shared/ShellXBrand && python3 scripts/verify-local.py --affected develop --swift-changed develop`, then the Swift 6.0 check (Global Constraints). Expected: all tests pass (any `withKnownIssue` is named in the hand-off); `verify-local.py` clean apart from the known noise; the check prints nothing.
- [ ] **Step 6: Commit.** `git add Packages/Shared/ShellXBrand/Sources/ShellXRemoteUI/SignInTextField.swift && git commit -m "feat(shellx): a sign-in text field whose editor allows only Roman input sources"`

Stage 1 ends here. Report its commits and results. Stage 2 starts once Task 0 Step 6 has passed, here or on the release Mac.

---

## Stage 2: needs Task 0

### Task 8: The email-first sign-in sheet

**Files:**
- Modify: `Sources/ShellX/Remote/UI/ShellXRemoteServicing.swift:28-33`
- Modify: `Sources/ShellX/Remote/UI/ShellXRemoteFixtureService.swift:181-194`
- Create: `Sources/ShellX/Remote/UI/EmailSignInSection.swift`. Wire it with `./scripts/wire-app-sources.py Sources/ShellX/Remote/UI/EmailSignInSection.swift`, which edits `cmux.xcodeproj/project.pbxproj`.
- Modify: `Sources/ShellX/Remote/UI/SignInSheet.swift`: `SignInSheet` :9-113, `SignInSheetPresenter` :149-208.
- Modify: `Sources/ShellX/Remote/UI/GoogleSignInButton.swift:25-49`
- Modify: `Sources/ShellX/ShellXAccountFlow.swift:64-72`
- Create: `cmuxTests/ShellXSignInSheetTests.swift`, then run `./scripts/sync-test-wiring`.

**Interfaces:**
- Consumes: Tasks 4–7.
- Produces:

```swift
// ShellXRemoteServicing
/// Mails a sign-in code to `email`. Throws `ShellXCoreError`.
func requestEmailCode(email: String, locale: String) async throws -> EmailCodeChallenge
/// Verifies the code and signs in; returns the account email. Throws `ShellXCoreError`.
func signInWithEmailCode(challengeID: String, code: String) async throws -> String
// EmailSignInSection.swift
/// The email part of the first screen (field, its failure, Send code) and the code step; draws nothing in `.done`.
struct EmailSignInSection: View { let model: EmailSignInModel; let google: GoogleSignInModel; let onCancel: () -> Void }
// SignInSheet
struct SignInSheet: View { let model: GoogleSignInModel; let email: EmailSignInModel? }   // email is nil for `.link`
// GoogleSignInButton: `var isDefaultAction = true`; `.keyboardShortcut(.defaultAction)` only when it is true
// SignInSheetPresenter
func present(model: GoogleSignInModel, email: EmailSignInModel? = nil, preferredWindow: NSWindow? = nil)
// ShellXAccountFlow
/// The language the app's strings are shown in, for the mail's language.
static var emailLocale: String { Bundle.main.preferredLocalizations.first ?? "en" }
```

**Sheet rules** (D3). The width, padding, `ShellXPalette`, `ShellXSheetButtonStyle` and dark panel are as today. Every text field and full-width button has an explicit 300 pt width (`Sources/Cloud/CloudSheetWindow.swift:6-21`). Texts come from `EmailSignInTexts.localized`.
- **`.link`** (email is nil): today's sheet exactly. Its Google button keeps Return.
- **The first screen** (`.signIn`; the email step is `.email`, or `.sending` with `sentTo == nil`). Top to bottom, 12 pt apart:
  1. The title.
  2. `SignInTextField` for the address, wired as follows:
     - `texts.field`, `.emailAddress`;
     - enabled when `SignInSheetFlows.emailEnabled` holds and the step is `.email`;
     - `focusRequest: email.focusRequest`;
     - `onChange`: `SignInSheetFlows.setEmail(google:email:text:)` with the Google model, the email model and the new text, so typing hides Google's failure;
     - `onSubmit: SignInSheetFlows.sendCode`;
     - `onCancel`: Cancel.
  3. `SignInSheetFlows.emailFieldError(google:email:)`, in 11 pt error colour, up to 4 lines. It is empty while Google's failure (item 7) shows, so only one failure is on screen (D3).
  4. Send code: primary, `.keyboardShortcut(.defaultAction)`, enabled when `email.canSend` and `emailEnabled`, with a small `ProgressView` beside it while `.sending`.
  5. "or", centred and muted, between two hairlines.
  6. `GoogleSignInButton(isDefaultAction: false)`: enabled when `SignInSheetFlows.googleEnabled`, and calls `SignInSheetFlows.startGoogle`. While Google is `.waiting`, today's "Waiting for Google…" and its hint take its place; the field and Send code stay visible but disabled.
  7. Google's `errorText`.
  8. Cancel.
- **The code step** (`sentTo != nil`; the step is `.code`, `.verifying`, or `.sending` for a resend). It replaces everything between the title and Cancel:
  1. `texts.sentTo(sentTo)`. It wraps, with no line limit.
  2. `SignInTextField` for the code: `texts.code`, `.oneTimeCode`, monospaced digits, enabled when `canEditCode`, `focusRequest: email.focusRequest` (it takes the keyboard back after a 401 or a failed Resend that keeps the code, Ruling 25), `onChange: email.setCode`, `onSubmit: email.submitCode`, and `onCancel`: Cancel, the same action as the email field's. The coordinator handles Escape, so without `onCancel` Escape would do nothing on the code step (D3: Escape is Cancel).
  3. `email.errorText`.
  4. Verify: primary, `.defaultAction`, enabled when `canVerify`, with a `ProgressView` while `.verifying`.
  5. Resend, on its own line, inside `TimelineView(.periodic(from: .now, by: 1))`. While `resendWait(at: context.date) > 0` it is disabled and reads `texts.resendIn(seconds:)` with monospaced digits; otherwise it reads `texts.resend`. It is enabled only in `.code`.
  6. "Use a different email", on its own line, enabled only in `.code`.
- **`.done(email)`**: "Signed in as %@" and Done (`.defaultAction`), as for Google's `.signedIn`, calling `email.finish()`.
- **Cancel** (`.cancelAction`) is hidden in Google's `.signedIn` and the email `.done`. It calls `email?.cancel()` and `model.cancel()`; the presenter's `dismiss()` is idempotent.

**The presenter:**
- `present(model:email:)` sets `onFinished` of both models to `dismiss()` and keeps both.
- `present(service:)` is the sidebar row's path when the fixture runs. It builds `EmailSignInModel(labels: .localized, requestCode: { try await service.requestEmailCode(email: $0, locale: ShellXAccountFlow.emailLocale) }, verify: { try await service.signInWithEmailCode(challengeID: $0, code: $1) })`.
- `ShellXAccountFlow.presentGoogleSheet(.signIn)` builds the same over `account.requestEmailCode` and `account.signInWithEmailCode(...).email`. Settings › Account, the sidebar row and the automatic open after a server sign-out all arrive here. `.link` passes `nil`.

**The fixture:**
- `requestEmailCode` waits 400 ms and returns `EmailCodeChallenge(challengeID: "fixture-challenge", email: <trimmed, lowercased>, expiresIn: 600, resendIn: 60)`.
- `signInWithEmailCode` throws `ShellXCoreError(code: "invalid_code", …)` unless the code is `ShellXRemoteFixtureService.requestCode`. With that code it signs in as `signInWithGoogle` does (sharing that state change) and returns the address of the last request.

- [ ] **Step 1: Compile what Stage 1 wrote.** Run `CMUX_SKIP_ZIG_BUILD=1 CMUX_WIREGUARD_GO_REQUIRE=0 scripts/shellx/test-app.sh ShellXAboutTests -- -jobs 4 -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/cmux-emailsignin-tests"`. Expected: `** TEST SUCCEEDED **`. If Stage 1's app-side lines (`RemoteUISnapshot.swift`, `ShellXAccountDetailView.swift`) do not compile, fix them first, in their own commit `fix(shellx): …`.
- [ ] **Step 2: Write the failing tests.** `cmuxTests/ShellXSignInSheetTests.swift` takes its imports and the `cmux_DEV` / `cmux` switch from `cmuxTests/ShellXAboutTests.swift:1-9`, plus `AppKit`, `SwiftUI`, `ShellXRemoteCore` and `ShellXRemoteUI`:

```swift
@MainActor @Suite("ShellX sign-in sheet") struct ShellXSignInSheetTests {
    // google(signIn: @escaping @MainActor () async throws -> String = { "g@shellx.test" })
    //   = GoogleSignInModel(purpose: .signIn, labels: .english, signIn: signIn, cancel: {})
    // email(verify: @escaping @MainActor (String, String) async throws -> String = { _, _ in "foo@bar.com" })
    //   = EmailSignInModel(labels: .english, requestCode: { _ in EmailCodeChallenge(challengeID: "c", email: "foo@bar.com",
    //     expiresIn: 600, resendIn: 60) }, verify: verify)
    // size(_ sheet: SignInSheet) = NSHostingView(rootView: sheet).fittingSize
    @Test func everyStateLaysOutAtTheSheetWidth() async
    // the first screen empty; with "phu@ẽ" typed (the invalid-email sentence); while Google waits (signIn awaits a gate the test
    // resolves after measuring); with a Google failure (signIn throws ShellXCoreError(code: "google_timeout", message: ""));
    // with "phu@ẽ" typed and then a Google failure; the code step; the code step after code_expired (verify throws
    // ShellXCoreError(code: "code_expired", message: "")); done: each width 340 (±1), height > 0
    @Test func theSwitchSheetHasNoEmailPath()
    // SignInSheet(model: GoogleSignInModel(purpose: .link, …), email: nil): width 340 (±1), height > 0
    @Test func theFixtureSignsInOnlyWithItsCode() async throws
    // let fixture = ShellXRemoteFixtureService(); requestEmailCode(email: " Dev@Shellx.Dev ", locale: "en").email == "dev@shellx.dev";
    // signInWithEmailCode(challengeID:, code: "000000") throws code "invalid_code" and !fixture.isSignedIn;
    // with ShellXRemoteFixtureService.requestCode it returns "dev@shellx.dev" and fixture.isSignedIn
}
```

- [ ] **Step 3: Run to verify they fail.** Run: `./scripts/sync-test-wiring && CMUX_SKIP_ZIG_BUILD=1 CMUX_WIREGUARD_GO_REQUIRE=0 scripts/shellx/test-app.sh ShellXSignInSheetTests -- -jobs 4 -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/cmux-emailsignin-tests"`. Expected: the test target does not compile (`SignInSheet` has no `email:`; the fixture has no `requestEmailCode`).
- [ ] **Step 4: Commit the failing tests.** `git add cmuxTests/ShellXSignInSheetTests.swift cmux.xcodeproj/project.pbxproj && git commit -m "test(shellx): email-first sign-in sheet"`
- [ ] **Step 5: Implement** the Interfaces and the sheet rules, and wire the new app file.
- [ ] **Step 6: Run to verify they pass.** Run: `./scripts/wire-app-sources.py --check && ./scripts/sync-test-wiring --check && python3 scripts/verify-local.py --affected develop --swift-changed develop && swift test --package-path Packages/Shared/ShellXBrand && CMUX_SKIP_ZIG_BUILD=1 CMUX_WIREGUARD_GO_REQUIRE=0 scripts/shellx/test-app.sh ShellXSignInSheetTests ShellXAboutTests -- -jobs 4 -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/cmux-emailsignin-tests"`, then the Swift 6.0 check (Global Constraints). Expected: both wiring checks exit 0, the Swift tests pass, `** TEST SUCCEEDED **` with the three new tests executed (not zero), and the check prints nothing.
- [ ] **Step 7: Look at it (do not commit).**
  - Add to `ShellXSignInSheetTests` a temporary test that hosts each state of `everyStateLaysOutAtTheSheetWidth` in an `NSHostingView` sized to its `fittingSize`, and writes it with `cacheDisplay(in:to:)` as a PNG under `NSTemporaryDirectory()`. The file name carries `Bundle.main.preferredLocalizations.first`.
  - Run `CMUX_SKIP_ZIG_BUILD=1 CMUX_WIREGUARD_GO_REQUIRE=0 scripts/shellx/test-app.sh ShellXSignInSheetTests -- -jobs 4 -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/cmux-emailsignin-tests" -testLanguage en`, then the same command with `-testLanguage vi`. The two variables are the ones every other run sets: without `CMUX_SKIP_ZIG_BUILD=1` the resources phase builds the Ghostty CLI helper with zig (`scripts/build-app-bundled-resources.sh:336-360`), and a changed value also changes that phase's fingerprint (`:218`). Open the PNGs, then run `git checkout cmuxTests/ShellXSignInSheetTests.swift`.
  - If the second run still renders English, say so in the hand-off instead of trying other ways to switch the language.
  - Expected:
    - a dark 340 pt panel;
    - the first screen: title, the email field ("Email address"), Send code, "or", the white Google button, Cancel;
    - the same screen with "That doesn't look like an email address." under the field;
    - with "phu@ẽ" typed and a Google failure: only Google's failure, under its button, and nothing under the field;
    - the code step: the two-sentence address line, the code field, Verify, "Resend code in 60 s" and "Use a different email" on their own lines;
    - the dead-code state with Resend open;
    - done;
    - no clipped or overlapping text, and `git status` shows no change from this step.
- [ ] **Step 8: Commit.** `git add Sources/ShellX cmux.xcodeproj/project.pbxproj && git commit -m "feat(shellx): the sign-in sheet opens on the email field, Google below"`

---

### Task 9: Full verification, tagged build, the user's checks, hand-off

**Files:** none new.

- [ ] **Step 1: Run the full verification** from the worktree root:

```bash
(cd shellx-core && cargo test --workspace --locked && bash scripts/c-smoke.sh)
(cd shellx-core && python3 scripts/test_check_deps.py && python3 scripts/check_deps.py)
git diff --quiet develop...HEAD -- shellx-core/Cargo.lock windows/Cargo.lock && echo locks-unchanged
swift test --package-path Packages/Shared/ShellXBrand
python3 tests/test_shellx_remote_harness.py
python3 tests/test_shellx_vi.py
python3 tests/test_shellx_no_phone_home.py
python3 scripts/localization_catalog.py check
./scripts/localize-changes --base develop
./scripts/wire-app-sources.py --check
./scripts/sync-test-wiring --check
python3 scripts/verify-local.py --affected develop --swift-changed develop
# then the Swift 6.0 check of Global Constraints
CMUX_SKIP_ZIG_BUILD=1 CMUX_WIREGUARD_GO_REQUIRE=0 scripts/shellx/test-app.sh ShellXSignInSheetTests ShellXAboutTests ShellXPhonePairingCoordinatorTests -- -jobs 4 -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/cmux-emailsignin-tests"
```

  Expected:
  - every Rust, Swift and Python suite passes, and the smoke exits 0;
  - `locks-unchanged`;
  - `Localization ready: changed work is complete and the strict catalog validator passed.`;
  - both wiring checks exit 0;
  - `** TEST SUCCEEDED **`;
  - `verify-local.py` clean apart from the known `feature-flags` noise;
  - the Swift 6.0 check prints nothing.
- [ ] **Step 2: The Windows app's tests against the changed fake.** Run `(cd windows && cargo test --release --locked -p shellx-app)` in a shell set up as the zig bullet of Global Constraints says. It needs the ghostty submodule and Task 0 Step 7's zig, and must never be a debug build on a Mac (`windows/README.md:54-57`). Expected: `test result: ok`. If zig is not available here, it runs on the release Mac (Task 0 Step 8); say where it ran. A green run shows only that this plan's fake changes break no Windows test. It does not show that Windows signs in against the real relay, because the fake's `GET /v2/machines` still differs from the relay's (Ruling 33).
- [ ] **Step 3: Tagged build of the branch head.** Run `CMUX_DEV_BACKEND_MODE=local CMUX_SKIP_ZIG_BUILD=1 CMUX_WIREGUARD_GO_REQUIRE=0 CMUX_TUI_CLIENT_LOCAL="$(scripts/shellx/build-cmux-tui.sh)" ./scripts/reload.sh --tag emailsignin --no-global-cli-links`, without `--launch`, in a shell set up as the zig bullet of Global Constraints says. It is incremental after Task 0 Step 7. Expected: the reload summary naming the tagged app, `ShellX DEV emailsignin`. Keep the tag until the user has finished Step 4 and Task 10. Then clean it up with the command `reload.sh` printed (only this tag), and remove the test DerivedData `$HOME/Library/Developer/Xcode/DerivedData/cmux-emailsignin-tests` (only that folder).
- [ ] **Step 4: Checks for the user.** An agent cannot launch the app here, so the user opens the tagged app by its name: `open -n -g -a "ShellX DEV emailsignin"`. The hand-off names the app, never its path (no raw `.app` path in chat). If the name does not resolve, the user takes the path from the `App path:` line of the reload log, which stays out of the chat. Without `SHELLX_API_BASE` it talks to relay.shellx.pro, which has no email routes until the relay is deployed. Record each result in the hand-off, or "owed":
  - **Entry points.** Settings › Account › Sign in and the sidebar's sign-in row open the same sheet: the email field (with the caret), Send code, "or", Continue with Google, Cancel.
  - **Return.** Type `you@example.com` and press Return: the sheet says "This way of signing in isn't available in this build." (production's 404), and Google never opens.
  - **Tab and Escape.** With Full Keyboard Access on, Tab goes field → Send code → Continue with Google → Cancel (on the code step, with Task 10's relay: code field → Verify → Resend → Use a different email → Cancel). Escape closes the sheet, and reopening shows an empty field. On the code step (with Task 10's relay), Escape in the code field also closes the sheet, and reopening starts on the empty first screen.
  - **Telex (D4).**
    - In System Settings › Keyboard › Input Sources, add "Vietnamese – Telex" if needed, and select it.
    - Click the email field: the input menu moves to a Roman source and does not offer Telex.
    - Typing `phu@ex` stays `phu@ex`.
    - Cancel: Telex is the input source again.
    - Paste `phu@ẽample.com`: "That doesn't look like an email address." shows, and Send code is off.
  - **Code step** (only with Task 10's relay): a wrong code empties the field; the Resend countdown runs; "Use a different email" keeps the address; the right code shows "Signed in as …" and then Done; Settings › Account shows "Email code".
- [ ] **Step 5: Secret and address scan.** Run `git diff develop...HEAD | grep -nE '^\+.*(re_[A-Za-z0-9]{8,}|RESEND_API_KEY=|@gmail\.com)'`. Expected: no match: no Resend key and no real address. Test addresses use `bar.com`, `b.cd`, `shellx.test`, `shellx.dev`, `x.test`, `example.com`, `mailinator.com` and `ẽample.com`.
- [ ] **Step 6: Localization audit for the hand-off** (`skills/cmux-localization` "Audit checklist"):
  - the changed surfaces: the sheet's first screen (now the email step), the code step, the two failure lines, and the Settings › Account method row;
  - the 18 new keys in all ten locales;
  - the commands above;
  - that the eight non-en/vi locales were machine-translated by the executor;
  - the two bare-English `rg` searches of `references/audit-workflow.md` over the changed Swift;
  - whether the PNG step ran.
- [ ] **Step 7: Report and stop.** Do not merge, push to `main`, deploy or release. The hand-off contains:
  - the commit list;
  - the red and green command results per task;
  - Task 0's outcome, and where each Stage 2 check ran (this Mac or the release Mac; no workflow runs while GitHub Actions is blocked) or that it did not run, and why;
  - the fake's `GET /v2/machines` drift (Ruling 33), for the Windows work;
  - the D4 outcome: the unit test (and any `withKnownIssue`) and the Telex check;
  - the user's Step 4 results, or "owed";
  - that no live relay or real mail was used, unless Task 10 ran;
  - the Contract additions below;
  - the note to re-check the code step against the iPhone branch when it lands (D3).

---

### Task 10 (optional, last): Live check against the local relay (D7)

This task is for the orchestrator and the user only: it sends a real mail. The orchestrator runs the relay from `develop` on `127.0.0.1:8799` with the real Resend key; the key is never given to an implementer. The CLI part needs only Task 3 and may run any time after it. `<address>` is the user's real address, typed by the orchestrator and never committed.

- [ ] **Step 1: The core, through the CLI** (the orchestrator, in the worktree). Each CLI run is its own process and reads its config only from `SHELLX_CORE_CONFIG` (`shellx-core/src/bin/shellx-core-cli.rs:18-24`); without it a call answers `not_configured`. An agent's shell keeps no variables between commands, and the second block runs after a wait for the user. So the state folder has a fixed name, every line carries its config, and both blocks run in the same session, so `$TMPDIR` is the same.

```bash
cd shellx-core && export PATH="$HOME/.cargo/bin:$PATH"
cargo build --locked --bin shellx-core-cli
rm -rf "${TMPDIR%/}/shellx-live-check" && mkdir -m 700 "${TMPDIR%/}/shellx-live-check"
CFG="{\"api_base\":\"http://127.0.0.1:8799\",\"state_dir\":\"${TMPDIR%/}/shellx-live-check\",\"device_name\":\"ShellX live check\"}"
SHELLX_CORE_CONFIG="$CFG" ./target/debug/shellx-core-cli auth.email.begin '{"email":"<address>","locale":"en"}'
```

  Expected: `{"ok":{"challenge_id":"<43 characters>","expires_in":600,"resend_in":60,"email":"<the address, lower-cased>"}}`, and a mail "Your ShellX sign-in code is NNNNNN" arrives. **Stop:** the user reads the mail and gives the six digits. Then, from the worktree root:

```bash
cd shellx-core
CFG="{\"api_base\":\"http://127.0.0.1:8799\",\"state_dir\":\"${TMPDIR%/}/shellx-live-check\",\"device_name\":\"ShellX live check\"}"
SHELLX_CORE_CONFIG="$CFG" ./target/debug/shellx-core-cli auth.email.finish '{"challenge_id":"<challenge_id>","code":"<the six digits>"}'
SHELLX_CORE_CONFIG="$CFG" ./target/debug/shellx-core-cli auth.session '{}'
SHELLX_CORE_CONFIG="$CFG" ./target/debug/shellx-core-cli auth.logout '{}'
rm -rf "${TMPDIR%/}/shellx-live-check"
```

  Expected:
  - `finish` → `{"ok":{…,"email":"<address>","auth_method":"email"}}`, with no token;
  - `auth.session` → `auth_method` `"email"`;
  - `auth.logout` → ok (the test device's token is revoked on the relay); then the folder, with its device key, is gone.

  Optionally, try one wrong code before the right one (`"000000"`, unless that is the mail's): it answers `{"error":{"code":"invalid_code",…}}`, and the right code still works afterwards.
- [ ] **Step 2: The Mac app** (the user, with Task 9 Step 3's tagged app).
  - Launch it by name: `open -n -g --env SHELLX_API_BASE=http://127.0.0.1:8799 -a "ShellX DEV emailsignin"` (no `.app` path in chat; Task 9 Step 4 says what to do if the name does not resolve).
  - Then go to Settings › Account › Sign in, type the address, press Send code, read the mail and type the code.
  - Expected: "Signed in as …", then Done; Settings › Account shows "Email code".
  - Only a DEBUG build reads `SHELLX_API_BASE` (`Sources/ShellX/Remote/ShellXRemoteService+App.swift:20-31`); release builds always use relay.shellx.pro.
- [ ] **Step 3: Stop.** Report both outcomes; this task commits nothing. Windows has no live check here: it needs a debug build on a Windows PC with `SHELLX_API_BASE` and a port forward, or the deployed relay. That is the user's, with the Windows work.

---

## Contract additions

For the contracts owner (`docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md`): a desktop section after the iPhone part's, numbered when it lands. It refers to §29 for every relay rule.

- K3 (§3) gains `auth.email.begin`, `auth.email.finish` and the error table of "Interfaces for Plan B". `auth.session`'s `auth_method` and `session.json.auth_method` may be `"email"`.
- Test-only names:
  - the fake's two routes and its hooks: `FakeOptions.email_sign_in` and `email_routes`; `email_code`, `email_locale`, `set_next_email_code`, `expire_email_codes`, `fail_next_mail`, `fail_next` and `add_user`;
  - its disposable domain is `mailinator.com`;
  - it now matches §29 on identity removal (the last of google/test/email), on the Google link that removes the email sign-in, and on `DELETE /v1/account` by code;
  - it counts no rate limits;
  - known drift, not fixed here: its `GET /v2/machines` items carry `noise_public_key_b64` (and `os_version`, `app_version`), which the relay's do not, so against the relay the core lists `"fingerprint": null` (Ruling 33).
- Mac keys: the String table (18 new keys; `remote.signin.email` stays unused). Mac type names: `EmailCodeChallenge`, `EmailSignInModel`, `EmailSignInTexts`, `SignInSheetFlows`, `SignInTextField`, `AccountSignInMethod.Kind`, `ShellXAccount.requestEmailCode` / `signInWithEmailCode`, and `SignInErrorMessage.emailText`.
- Desktop order: the email field and Send code, "or", Continue with Google, Cancel. The field has the keyboard when the sheet opens, and Escape closes it. The Windows dialog (Plan B) follows the same order.

## Not verified while writing this plan

- The plan writer ran no command. The build-environment recon ran three checks on `develop` today, all green:
  - `cargo test --workspace --locked` in `shellx-core` (192 passed);
  - `scripts/c-smoke.sh`;
  - `windows` `cargo test --locked -p shellx-model` (192 passed).

  On 2026-11-12 the critic ran two more here, both green: `swift test --package-path Packages/Shared/ShellXBrand --filter signInErrorMapping` (the package built with Swift 6.3.3 and the test passed), and `python3 tests/test_shellx_vi.py` (22 tests, Python 3.9.6). The whole ShellXBrand suite was not run here; it passed 198 tests on the other Mac.
- Task 0 has never run here, and the Mac app has never been built on this Mac. The timings come from the other Mac and CI.
- **The Roman-only restriction:**
  - It is unknown whether a field editor in an off-screen window has an `NSTextView.inputContext` under `swift test`.
  - That `allowedInputSourceLocales` hides Apple's Telex and VNI is an inference from the Vietnamese input method declaring a Unicode script.
  - Third-party Vietnamese typing tools and paste are covered only by the ASCII rule.
- `xcodebuild`'s `-testLanguage` for the PNGs was not tried here.
- `NSHostingView(...).fittingSize.width == 340` follows `cmuxTests/NewMachineSheetLayoutTests.swift:128`. Compare with a tolerance of 1.
- Focus inside a `CloudSheetWindow` sheet: the field asks for it on the next main-queue turn after it moves into the window. Until Task 9 Step 4, that has been seen only in the package test's plain window.
- `DECIMAL_ZEROS` comes from Python 3.9's Unicode 13 tables. Rust's std is newer, so a few new scripts' digits are dropped like letters.
- The Swift 6.0 check is a text check of the two banned constructs, not a Swift 6.0 compile, and no machine here has one. Run by the fixer over all 2,897 app-linked Swift files on `develop`, its patterns found no trailing comma and one `nonisolated struct`: `Sources/AgentResumeLaunchGuard.swift:19`, already on `develop` and outside this plan's files, so the check (changed files only) never reads it.
- `open -a "ShellX DEV emailsignin"` relies on Xcode's build registering the tagged app with Launch Services. That was not tried here, so Task 9 Step 4 names the fallback.

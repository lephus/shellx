# Hand-off: ShellX mobile programme (sign-in, phone terminal, Android)

State on 2026-11-10 (evening, second machine `/Users/richard/Documents/helper/shellx`). The user writes Vietnamese, so reply in Vietnamese.

Plans and their order are in `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` §1:
{1A, 2A, 3A, 3F} → {1B, 1C, 2B, 2C, 3B} → 3C → 3D → 3E → 3G → {1D, 3H}.
Specs: `docs/superpowers/specs/2026-11-07-shellx-{google-sign-in,mobile-terminal,android-app}-design.md`.

## Standing rules

- Never deploy and never run `deploy/vps-deploy.sh` or `publish-to-vps.sh`. Never merge to `main`, and never upload to a store.
- Push to `develop` is approved.
- Never quit, launch or replace `/Applications/ShellX.app` or any cmux app.
- Never use bare `xcodebuild`; use `scripts/shellx/test-app.sh` (Mac) and `shellx-ios/scripts/dev.sh` (iOS).
- Never ask for keys or secrets in chat, and never commit a secret or a keystore.
- **Wave 2 directive ("Chạy nhóm 2, tự merge"):** 1B, 1C, 2B and 2C merge into `develop` and push after a fresh review, without the device and dogfood checks. Record those checks as "skipped (user waived)".
- **Running plans:** each plan runs in its own worktree `.worktrees/<slug>` on `feat/shellx-<slug>`. The executor stops before landing. The orchestrator merges with `git merge --no-ff` from the main checkout, re-runs tests, then pushes.
- **Non-UI plans** (1A, 2A, 3A, 3B, 3C, 3F, 3H) merge after review.
- **Later UI plans** (3D, 3E, 3G) wait for a device check and a "merge" directive; the waiver was given for wave 2 only.
- **One app id (user decision, repeated 2026-11-09):** only `com.shellx.prod`. No `com.shellx.dev` anywhere: iPhone Debug, Android debug, Firebase and OAuth clients all use `com.shellx.prod`. Debug labels stay "ShellX Dev". A debug install on a phone replaces the store app.
- **No developer accounts on this Mac (2026-11-09):** never sign, provision or register ShellX ids with an Apple or Google developer account here; only the Apple Developer account phulealali@gmail.com has rights. So: no `shellx-ios/scripts/dev.sh device`, no `-allowProvisioningUpdates`, no archive, no `release/mobile/*.sh`; Android only with the debug keystore; never read `~/.shellx-release`. Simulator tests, `dev.sh screenshots`, `dev.sh test release` (unsigned) and `shellx-android/scripts/dev.sh device` (debug build over adb) are fine.
- **This Mac:** no Android Studio. Use `export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home`. `sdkmanager` is now a wrapper of `~/Library/Android/sdk/cmdline-tools/latest/bin/android sdk` (package names with `/`). `~/.gradle/gradle.properties` has `-Xmx2G` and 4 workers. Swift 6.3.3.

## Landed on develop (pushed)

| Plan | Merge | Notes |
| --- | --- | --- |
| 3F relay FCM | 0e24b3e9d8 | |
| 1A relay sign-in | f7223c8e5f, Apple fix 4ef5d1c9d1 | Decision 2026-11-08: Apple never links by email. An Apple ID with no identity always gets `link_required` (QR + Allow on the Mac). |
| 2A link protocol | 4833633adb | |
| 1B desktop sign-in | 2efa044405 | |
| 1C iOS sign-in | 692bd18881 | |
| 2B Mac terminal views | 6a53d7c329 | The merge commit carries the security analysis. |
| PendingPicksTests on Swift 6.3 | d13a54271f | One `@MainActor` on the test's `Gate`. |
| 3A Android scaffold | 7b2c58fdd6 | Contracts §22. Review: 0 C, 3 I + 5 M fixed, re-review approved. |
| One app id `com.shellx.prod` + Firebase (3A Task 10) | 61a339fb3e | `shellx-android/app/google-services.json` from the user's download (project `shellxpro`; also holds the Android OAuth client with this Mac's debug SHA-1 and the Web client). |
| 2C iPhone terminal | 34d42258b9 | Contracts §23. Two-reviewer final review (2 I + 11 M fixed test-first), one regression fixed, re-reviews clean. Device check skipped (user waived). Core 682 / app 246 tests. |
| 1C follow-up: Google G + Google Sans Medium (static, OFL) on iOS; iPhone Debug bundle `com.shellx.prod` | cf1d4e2343 | Review approved (0 C / 0 I). Desktop branding by the user: 112079593c. |
| 3B Kotlin Link (`link-core`, `link-account`) | 91bc8626be | Contracts §24. Three chunks, each reviewed + fixed test-first; final review clean. link-core 135, link-account 62 (4 live-relay tests skipped: no `cmux-relay` binary on this Mac). |
| 3C Android core (`:core`) | 4596d4d4c4 | Contracts §25. Four chunks + final review, every Important fixed test-first and re-reviewed. `:core` 586 tests. |
| 3D Android UI shell | b2e39d7ee4 | Contracts §26 (8bd0c521a8). Four chunks + Task 17 + final review, every Important fixed test-first and re-reviewed; `:app` 300 / 172; R8, lint, 16 KB; emulator smoke API 26 + 36. **Landed 2026-11-10 on the user's directive ("push toàn bộ lên develop") before the phone check: the Pixel 3 never appeared on the Mac's USB bus with the cable used. Phone check still owed (USER), on `develop`.** |
| 3E Android UI work | 49eff1b777 | Contracts §27 (8bd0c521a8). Three chunks + Task 13 + final review, every Important fixed test-first and re-reviewed; `:app` 608 / 302, `:core` 587; API 36 emulator smoke. Phone check Part A owed (USER); Part B needs the 1D relay deploy. |
| 3G Android terminal | 492fccaa6a | Contracts §28 (8bd0c521a8). Four chunks + a 26-item final fix round + two re-reviews + the Telex follow-up (A-38), all approved; `:app` 753 / 377, `:core` 765, link-core 189, link-account 64. Phone check Part A owed (USER); Part B needs 1D + the 2B Mac build. |

## 3D, 3E, 3G: landed on develop 2026-11-10, phone checks still owed (details per plan)

- Overnight run (user: "từ giờ đến mai làm cho xong cho tôi", 2026-11-09 17:22): 3D → 3E → 3G, each on its own branch stacked on the previous one, reviewed and fixed like 3C, plus our own emulator / Pixel 3 checks. Merged into develop in that order on 2026-11-10 (b2e39d7ee4, 49eff1b777, 492fccaa6a; contracts §26–§28 in 8bd0c521a8) on the user's directive "push toàn bộ lên develop", given after the Pixel 3 could not be connected (no device on the USB bus; see Waiting on the user, item 5). Each merge's tree equals the reviewed branch tip plus develop's doc and `web/` commits; `dev.sh test all` ran once on the merged tree. The branches stay on origin; the local worktrees were removed. **The phone checks below are still owed and now run from the main checkout on `develop`.** Anything off becomes a follow-up branch.
- **3D: landed (merge b2e39d7ee4), phone check owed** — branch `feat/shellx-android-3d-ui-shell` at 3fe7d2ad0a (3fe7d2ad0a adds a QR fix found in 3E: about 2 % of real Mac pairing codes failed to scan because ZXing's single detector took data for a finder pattern, now with a `QRCodeMultiReader` fallback — worth one camera scan on the phone). Four chunks + Task 17 + final review, every Important fixed test-first and re-reviewed; `:app` 300 debug / 172 release tests; R8 release builds, lint 0 errors, `.so` 16 KB aligned; emulator smoke API 26 + 36 (debug and R8) clean; real Keystore checked on the API 26 emulator and under R8. Ledger and reports: `.superpowers/sdd/2026-11-07-shellx-android-3d-ui-shell/` (git-ignored; `task-17-report.md` has the contract additions for §26 at landing).
  - **How to check (USER):** in the main checkout on `develop`, plug in the phone, run `JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home shellx-android/scripts/dev.sh device --serial <id>` (Pixel 3: `93BX1XMU7`). Then: "Try without an account" → demo home with "Mac giả" and the "Demo · Exit" banner; Settings › Appearance Dark/Light switch at once; with the phone in Vietnamese the words are Vietnamese; Pairing → deny the camera → "Open Settings" works → allow → the scanner shows; TalkBack on Your Macs rows offers Make Default / Unpair. Report anything off.
  - **Live Google sign-in is blocked by the relay:** the production relay answers 404 to `POST /v1/auth/nonce`, i.e. it runs without plan 1A. It needs the 1D deploy (relay with 1A + `GOOGLE_CLIENT_IDS` incl. the Web client). The user approved Google's G and Google Sans for Android (2026-11-09).
- **3E: landed (merge 49eff1b777), phone check owed** — branch `feat/shellx-android-3e-ui-work` at 46992ee03f (stacked on 3D). Three chunks + Task 13 + final review, every Important fixed test-first and re-reviewed; `:app` 608 debug / 302 release, `:core` 587; R8 release, lint-vital, 16 KB alignment, release permissions ok; API 36 emulator smoke clean (demo flows, rotation, landscape, POST_NOTIFICATIONS). Ledger and reports: `.superpowers/sdd/2026-11-07-shellx-android-3e-ui-work/` (`task-13-report.md` has the contract additions for §27 at landing and the full phone-check list).
  - **How to check (USER), Part A in "Try without an account"** (on `develop`, same `dev.sh device --serial <id>` command as 3D): answer a permission card Allow and another Deny; open a question, hold "Answer by voice", say an option in Vietnamese → it is ticked; `+` › Photos and `+` › Files then Send ("Sent" shows); hold the mic, slide left past the line, release → nothing sent; first mic press asks once; rotate with typed text in a question sheet's "Other…" and the plan sheet's Revise → kept; turn the phone sideways in a workspace → the chat still has room; one QR scan of a Mac code. Also read the new Vietnamese mic hint (`voice_mic_hint`) once.
  - **Part B pending** (push arrival/grouping/removal, taps cold/warm/Recents, "a fresh install makes no FCM token until sign-in"): needs the 1D relay deploy and Google sign-in. Android 13's notification dialog needs an Android 13+ phone (the Pixel 3 is 12, the vsmart Live 10); it was checked on the API 36 emulator.
  - **Product calls made overnight (tell me if you want otherwise):** after "No thanks" on Play's update dialog it stays hidden until the next cold start; "Don't allow" on the notification dialog leaves it Off (system settings open only when Android shows no dialog); sheets use `surfaceContainer*` with a hairline edge on inner cards; phone landscape uses a compact 48 dp bar.
  - **Deferred to 3C:** FCM `deleteToken()` at sign-out and token rotation after a same-process re-sign-in (3C's `PushRegistration` keeps the token); until then 3H's Data safety wording is "no FCM token request or refresh while signed out".
- **3G: landed (merge 492fccaa6a), phone check owed** — branch `feat/shellx-android-3g-terminal` at aef7f0faf5 (stacked on 3E). Four chunks (Kotlin terminal protocol + a bounded relay inbox and terminal queue; `:core` hub, fake Mac, typing, geometry; the terminal view model at the iPhone's final behaviour; the app pane, ＋ chip and View as Terminal) + a combined final fix round (26 items from three reviews, all test-first) + two re-reviews, all approved. Tests: link-core 189, link-account 64 (4 skipped: RelayIntegrationTest), `:core` 765, `:app` 753 debug / 377 release (after the Telex follow-up; 729 / 353 at the full `test all`), scripts 53, 0 failures; R8 release build, lintVital, release permissions, 16 KB alignment (16 libs), both licence checks, import-strings 266 / check-strings 300 all pass; API 36 emulator smoke clean (drawing, typing, key bar, paste, zoom, scrollback, landscape, rotation ×2, Home-and-back, ＋, View as Terminal, TalkBack). Ledger, reviews and landing drafts: `.superpowers/sdd/2026-11-07-shellx-android-3g-terminal/` — `landing-contracts-draft.md` (pasted as §26–§28 in 8bd0c521a8, §28 amended for the Telex follow-up), `landing-steps.md` (the merge procedure, run 2026-11-10), `phone-check-3g.md` (the full check list), `fix-final-report.md` (final verification).
  - **How to check (USER), Part A in "Try without an account"** (on `develop`, same `dev.sh device --serial <id>` command): open a workspace of the demo Mac → the shell pane draws a terminal; type (also Vietnamese Telex on Gboard), use the key bar (Esc, Tab, Ctrl+C, arrows), paste, pinch to zoom, scroll back; turn the phone sideways with the keyboard up → the bar steps aside and the grid keeps rows; go to the launcher and back with the keyboard up → typing still works; rotate twice → keyboard stays; swipe terminal ↔ agent pane; ＋ → a new terminal (the chip dims while it is on its way); "View as Terminal" on an agent; TalkBack: the terminal reads "Terminal <name>" then its rows, double-tap opens the keyboard, two-finger swipe pages history. With a Bluetooth keyboard in landscape the top bar stays.
  - **Part B pending** (live Mac: `yes | head -100000`, a 5 MB base64, `lolcat` while watching memory, vim/htop, latency targets p95 first screen < 1 s / key echo < 300 ms / frame apply < 16 ms): needs the 1D relay deploy and the tagged 2B Mac build.
  - **Product calls made (tell me if you want otherwise):** demo terminals stay 50×40 like the iPhone; only the newest page of a Mac receives terminal frames (the iPhone feeds every page); Ctrl+letter on non-Latin layouts follows the physical key, punctuation chords stay unmapped; after a stop/start the retry budgets reset (the iPhone resets only on a Mac drop); history is capped at ≈16 MiB besides 10 000 rows (Android-only); a copied *file* pastes nothing (iPhone parity); the single `workspace.shell.placeholder` entry was removed from the iPhone catalog.
  - **Telex fixed (follow-up, 2c6ca54dce..aef7f0faf5, reviewed twice):** Gboard's Vietnamese Telex now works in the terminal through an Android-only editor emulation of the current word (ledger A-38): the input field reports the word typed since the last word boundary (≤ 32 UTF-16 units) to the keyboard, and the keyboard's rewrites (`replaceText` / `deleteSurroundingText` / `setComposingRegion`) reach the Mac as backspaces plus the new text; `NO_SUGGESTIONS` stays, so no auto-correct. Verified on the API 36 emulator: `tieengs` → `tiếng`, `vieetj` + Backspace → `việt`, `lss`/`grpe` unchanged, two spaces stay two spaces. VNI is unit-tested only (this Gboard offers no VNI layout) — try it on the phone; a rewrite sends up to 33 input messages (true batching needs a `:core` multi-unit API, deferred); one API 26 emulator smoke of the terminal keyboard is still owed before the store build (3H).
  - **Deferred minors (3G):** a lagging consumer holds one exempt snapshot per view opened (≤ ~16 MiB worst case from a hostile host); a stale `Opened` leftover can show the previous view's screen for a moment; a11y scroll events not fired on scroll actions; small per-frame allocations in drawing; the 4 ms yield turn is uninjectable in tests; the upstream notes for the iPhone/Swift side are in §28 of the contracts draft.
- Before the first live dogfood: run 3B's `RelayIntegrationTest` with `CMUX_RELAY_BIN` on a machine that has the binary.

## Email + code sign-in through Resend: design written, waiting for the user (2026-11-10 evening)

- User request (2026-11-10): "làm thêm cho tôi một option là login bằng cách nhập email và nhận mã OTP từ ứng dụng gửi qua mail bằng resend; nhập OTP xong là đăng nhập", then "Làm xong đẩy lên develop cho tôi".
- Design: `docs/superpowers/specs/2026-11-10-shellx-email-code-sign-in-design.md` (Vietnamese; brainstorming recon and builder check done). **No code yet: the brainstorming gate holds until the user approves the design** ("cứ làm" = accept the defaults listed in its §11). After approval: superpowers:writing-plans (one plan per part), then subagent-driven development, each part on its own `feat/shellx-email-code-signin-<part>` branch from `develop`, reviewed, merged with `--no-ff` and pushed to `develop`; landing order relay → Android → iPhone → shellx-core + Mac → Windows. Contracts get a new section and this file gets the user's Resend steps at landing.
- Shape (the spec is authoritative): the relay (`relay/`, TypeScript, Hono + better-sqlite3) gets `POST /v1/auth/email/code {email, locale?}` → 202 `{challenge_id, expires_in: 600, resend_in: 60, email}` and `POST /v1/auth/email/verify {challenge_id, code, device}` → 200 `{user_id, device_id, token, email}` (401 `invalid_code`, 410 `code_expired`, 409 `switch_from_signed_in_device`); `DELETE /v1/account` also accepts `{challenge_id, code}`. Identity provider `email` (subject = normalized email), linked by the verified email into an existing Google-created account; 6-digit code, 10 min, 5 attempts, only hashes stored (`email_codes` table, migration `0011_email_sign_in.sql`, which also widens the identities/tokens CHECKs and turns the four `!= 'apple'` sites into `IN ('google','test')`); limiters 10/min per IP, 3/min and 10/hour per email. `EmailGateway` + `ResendClient` (`POST https://api.resend.com/emails`, Idempotency-Key, 10 s timeout) behind `RESEND_API_KEY` + `EMAIL_FROM`: both set → on, both missing → 503 `email_sign_in_disabled`, one → ConfigError at start. Clients show "Continue with email" unconditionally and map 404/503 to `providerUnavailable`; Android `StoredSession` gains `authMethod` (absent → google); new strings `signin.email.*`, `signin.error.{invalidEmail,disposableEmail,invalidCode,codeExpired,emailSendFailed}`, `settings.account.method.email`; shellx-core RPCs `auth.email.begin` / `auth.email.finish` for Mac and Windows; delete-by-code only on the phones (desktop keeps the privacy link); `web/src/pages/privacy.md` loses "We do not send verification … emails" (web lands on `main` only on the user's push).
- User's part: verify the sender domain in Resend (DNS) and set `RESEND_API_KEY` and `EMAIL_FROM` (`ShellX <sign-in@shellx.pro>` proposed) in the VPS `~/phu/shellx/.env` with a `deploy/docker-compose.yml` passthrough, as part of the 1D deploy. A real send test from a local relay needs the key at `/Users/richard/Downloads/key/resend` and the words "thử gửi"; never a key in chat. No Resend key exists on this Mac today.

## Waiting on the user

1. **A Google OAuth client of type iOS** for bundle `com.shellx.prod` (Google Cloud project `shellxpro`). Decision: no dev client; "làm thẳng Prod".
   - Set its id, without `.apps.googleusercontent.com`, as `SHELLX_GOOGLE_IOS_CLIENT` in both `shellx-ios/Config/Debug.xcconfig` and `Release.xcconfig`. Add the full id to the relay's `GOOGLE_CLIENT_IDS` (plan 1D).
   - The client the user gave (852509094750-nl7t2msvjr77u636ofl7p3hpfu9jp9o3) is a **Desktop** client and does not work for iOS. It serves 1B: pass it at build time through `SHELLX_GOOGLE_DESKTOP_CLIENT_ID` and `SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET`. The secret is in the user's downloaded JSON and is never committed.
2. **Sign in with Apple is enabled** on `com.shellx.prod`. Nothing left to do.
3. ~~1B: Google G and Google Sans on Mac and Windows~~ — done 2026-11-09 (112079593c, the user ran `fetch-google-branding.sh`).
4. **1C Task 15** runs after plan 1D's cut-over.
5. **Android phone checks for 3D, 3E and 3G on `develop`** (lists above and in `.superpowers/sdd/2026-11-07-shellx-android-3g-terminal/phone-check-3g.md`). The three plans landed 2026-11-10 on the user's directive before the check could run: with the cable used, the Pixel 3 never appeared on the Mac's USB bus (`ioreg -p IOUSB` listed only hubs, the Type-C AV adapter, a keyboard and a receiver) — try the Pixel's own data cable straight into the Mac, or Wireless debugging (Android 12: pair with `adb pair ip:port code`, then `adb connect ip:port`). Install from the main checkout with `dev.sh device --serial 93BX1XMU7`. The vsmart Live (serial in `~/.config/shellx/android-serial`) is not on this Mac. Anything off becomes a follow-up branch; nothing is reverted.
6. **HEIC on Android (3E):** default ruling is to convert HEIC/HEIF picks to JPEG like the iPhone; the user may say otherwise.
7. **iPhone follow-up:** `SpeechRunSlot.swift:78-90` has the quick-tap gap Android fixed in 3C (contracts §25).
8. **Email + code sign-in: approve the design** (section above; spec §11). Three decisions: (1) all four apps, or phones first (default: all four); (2) a code sent to foo@gmail.com signs into the account created with Google foo@gmail.com (default: yes; alternative: separate account + QR link through the Mac, like Apple, which adds an Android "Connect to your Mac" screen); (3) sender `ShellX <sign-in@shellx.pro>`, domain verified in Resend, `RESEND_API_KEY` / `EMAIL_FROM` on the VPS. "cứ làm" = the defaults.

## Next after these

- {1D, 3H} after 3G. Not started. 1D now also carries the Resend variables.
- Email + code sign-in (section above) as soon as the design is approved: plans, then relay → Android → iPhone → Mac → Windows, each pushed to `develop` after review.

## Known noise

- `verify-local.py` fails `feature-flags`: `ios-feed-performance-release` in `Packages/Shared/CmuxClientConfig/Sources/CmuxClientConfig/ClientConfigFlag.swift` has reviewBy 2026-11-06. Pre-existing. In the main checkout it passes falsely, because the untracked lower-case `packages/` folders hide `Packages/` on the case-insensitive disk.
- `AttachmentPreparerTests.testCancellingAHungFileReadStopsIt` fails on clean develop.
- `WorkspaceViewTests` and `MachineHubWorkspaceTests.testRefusedCloseKeepsRow` are flaky under load.
- A post-merge Mac build can fail with "cannot find type 'Terminal…'" when DerivedData holds a stale `ShellXLinkCore` module. Delete that module's products and intermediates, then rebuild.

## Deferred review minors (not fixed)

- **3F:**
  - no mixed iOS + Android token-deletion test;
  - no guard for a synchronous throw;
  - no `isWellFormed` check before FCM;
  - `apns_topic IS NULL` is untested;
  - FCM can deliver `resolved` before `needs_you` and leave a stale alert. The iPhone has the same gap.
- **1A:**
  - open `/v1/ws` sockets are not closed when an identity is removed or password access is dropped;
  - there is no Apple revoke for denied links.
- **1B:**
  - three derived `Debug` impls can print emails (IdentityItem, Windows SignInMethod, AccountFlow);
  - the Mac shows raw error codes;
  - link token rotation can flash the UI to signed out.
- **1C (M1–M8):**
  - Exit while the demo starts leaks the demo;
  - overlapping account changes can clear a valid session or sign the user back in;
  - a Keychain write failure after a link leaves a zombie session;
  - a lost delete 204 leaves the deleted account's data on the phone;
  - `finishAppleLink` accepts a stale `.cancelled`;
  - Apple link Cancel and 404 copy is wrong;
  - the delete sheet is wrong after a failed switch;
  - `AppleCredential` and `Outcome` print tokens by default.
- **2B (M-1–M-9):**
  - phone activity is counted with no unit applied;
  - `type` and `paste` results are ignored;
  - modified home/end/page keys are dropped;
  - input deferred during a clipboard read counts as Mac activity;
  - the pacing floor is skipped once after an echo;
  - the deadline task is recreated on every change during a hold;
  - a disconnected Link phone is not told and the view keeps running;
  - there is a short window where a closed tab is not reported as `gone`;
  - suggested for a later 2A revision: pass `device_name` into `openView`.
- **2C (final review 2026-11-09, reports were in `.superpowers/sdd/`):**
  - held hardware arrows, esc, tab, Home/End and Page Up/Down do not auto-repeat on a Bluetooth keyboard;
  - "View as Chat" cannot be reached while the Mac is offline or no longer lists `terminal_view`;
  - commits 4d26389684 and e1f0003eb0 do not build (use `git bisect --first-parent`);
  - after the background grace, returning shows "The Mac is offline" while the phone is only reconnecting;
  - the demo Mac's shell forgets what was typed whenever the view reopens;
  - a lost session restores the open budgets, so a Mac whose session drops on every open cycles offline/connecting and never reaches Try Again;
  - `failedOpen()`'s doc comment still says "input only `.live`"; no test pins `acceptsInput` false in the busy gap or after `notSent`; `testAReopeningPageGivesUpTheKeyboardAndTheKeyBar` now covers only the failed-view wait;
  - latency criteria 3–5, Telex/VNI and hardware keys are untested on a device (user waived the check).
- **1C follow-up / one app id:**
  - `deploy/README.md` (lines ~233–272), `relay/README.md:52`, `scripts/shellx/share-e2e.mjs` and the relay's default `APPLE_CLIENT_IDS` still name `com.shellx.dev` (plan 1D, with the relay config);
  - iPhone Debug and Release now share keychain, defaults and push topic on a device (by design; `shellx-ios/README.md`);
  - the replaced 4.97 MB variable font stays in history (6dae2f42f3).
- **3A:**
  - the Gradle path rule is a text check: a directory read from the environment into a variable (`File(System.getenv("HOME"), …)`) or built with `+` and no `..` literal still passes;
  - runtime-classpath locking is matched by configuration name (backed by STRICT mode);
  - Compose is one BOM behind (1.11.x) until compileSdk 37 is allowed; Robolectric runs on SDK 35.

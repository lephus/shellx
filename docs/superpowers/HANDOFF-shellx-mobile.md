# Hand-off: ShellX mobile programme (sign-in, phone terminal, Android)

State on 2026-11-09 (afternoon, second machine `/Users/richard/Documents/helper/shellx`). The user writes Vietnamese, so reply in Vietnamese.

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

## In progress

- 1C follow-up: Google G + Google Sans on iOS (1C Task 9 steps 7–8) together with the iPhone Debug bundle → `com.shellx.prod`. Assets are in `~/Downloads/shellx-google-signin/` (zip SHA-256 checked).

## Waiting on the user

1. **A Google OAuth client of type iOS** for bundle `com.shellx.prod` (Google Cloud project `shellxpro`). Decision: no dev client; "làm thẳng Prod".
   - Set its id, without `.apps.googleusercontent.com`, as `SHELLX_GOOGLE_IOS_CLIENT` in both `shellx-ios/Config/Debug.xcconfig` and `Release.xcconfig`. Add the full id to the relay's `GOOGLE_CLIENT_IDS` (plan 1D).
   - The client the user gave (852509094750-nl7t2msvjr77u636ofl7p3hpfu9jp9o3) is a **Desktop** client and does not work for iOS. It serves 1B: pass it at build time through `SHELLX_GOOGLE_DESKTOP_CLIENT_ID` and `SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET`. The secret is in the user's downloaded JSON and is never committed.
2. **Sign in with Apple is enabled** on `com.shellx.prod`. Nothing left to do.
3. **1B: Google G and Google Sans on Mac and Windows.** The user accepts Google's branding terms, then runs `bash scripts/shellx/fetch-google-branding.sh`; it must end with `google branding: OK`. Then commit `chore(shellx): Google's official G mark and Google Sans Medium (OFL 1.1), downloaded by the user`. Until then the button is text-only and the desktop release scripts refuse to build.
4. **1C Task 15** runs after plan 1D's cut-over.
5. **Android dark mode on the Pixel 3:** the user turns on dark theme and opens "ShellX Dev" (light was checked 2026-11-09). The vsmart Live (serial in `~/.config/shellx/android-serial`) is not connected on this Mac.

## Next after these

- 3B (Kotlin Link), now that 3A has landed. Not started; offer it to the user.
- Then 3C → 3D → 3E → 3G → {1D, 3H}. Not started; the user has not asked for them yet.

## Known noise

- `verify-local.py` fails `feature-flags`: `ios-feed-performance-release` in `Packages/Shared/CmuxClientConfig/Sources/CmuxClientConfig/ClientConfigFlag.swift` has reviewBy 2026-11-06. Pre-existing.
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
- **3A:**
  - the Gradle path rule is a text check: a directory read from the environment into a variable (`File(System.getenv("HOME"), …)`) or built with `+` and no `..` literal still passes;
  - runtime-classpath locking is matched by configuration name (backed by STRICT mode);
  - Compose is one BOM behind (1.11.x) until compileSdk 37 is allowed; Robolectric runs on SDK 35.

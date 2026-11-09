# Hand-off: ShellX mobile programme (sign-in, phone terminal, Android)

State on 2026-11-09, for continuing on another machine. The user writes Vietnamese, so reply in Vietnamese.

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

## Landed on develop (pushed)

| Plan | Merge | Notes |
| --- | --- | --- |
| 3F relay FCM | 0e24b3e9d8 | |
| 1A relay sign-in | f7223c8e5f, Apple fix 4ef5d1c9d1 | Decision 2026-11-08: Apple never links by email. An Apple ID with no identity always gets `link_required` (QR + Allow on the Mac). |
| 2A link protocol | 4833633adb | |
| 1B desktop sign-in | 2efa044405 | |
| 1C iOS sign-in | 692bd18881 | |
| 2B Mac terminal views | 6a53d7c329 | The merge commit carries the security analysis. |

## In progress

### 2C, iPhone terminal

- Branch `feat/shellx-terminal-2c-ios`, pushed, head 4d26389684, 21 commits on develop.
- Tasks 0–9 are done.
- Tasks 10–11 had their tests committed (75368a9a73). The last commit (4d26389684) is unreviewed WIP of `WorkspaceScreen.swift`; check it before continuing.
- Includes the 2A follow-up: send `closeTerminalView` after a terminal-view open timeout, with a test.
- When done: full plan verification, a fresh review, fix Critical and Important findings test-first, then land it (waiver applies).

### 3A, Android scaffold

- Branch `feat/shellx-android-3a-scaffold`, pushed, head 10b8d759f7. Tasks 1–5 are done.
- Blocked before Task 6 on the USER SDK install:
  ```
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"; S="$HOME/Library/Android/sdk/cmdline-tools/latest/bin/sdkmanager"; yes | "$S" --licenses >/dev/null; "$S" --install "platform-tools" "emulator" "platforms;android-36" "build-tools;36.0.0" "system-images;android-26;google_apis;arm64-v8a" "system-images;android-36;google_apis_playstore;arm64-v8a"
  ```
- The phone is a vsmart Live (Android 10).
- Task 10 needs the Firebase files (USER).
- Expect a trivial `shellx-link/README.md` conflict with 2A when landing.

## Waiting on the user

1. **A Google OAuth client of type iOS** for bundle `com.shellx.prod` (Google Cloud project `shellxpro`). Decision: no dev client; "làm thẳng Prod".
   - Set its id, without `.apps.googleusercontent.com`, as `SHELLX_GOOGLE_IOS_CLIENT` in both `shellx-ios/Config/Debug.xcconfig` and `Release.xcconfig`. Add the full id to the relay's `GOOGLE_CLIENT_IDS` (plan 1D).
   - The client the user gave (852509094750-nl7t2msvjr77u636ofl7p3hpfu9jp9o3) is a **Desktop** client and does not work for iOS. It serves 1B: pass it at build time through `SHELLX_GOOGLE_DESKTOP_CLIENT_ID` and `SHELLX_GOOGLE_DESKTOP_CLIENT_SECRET`. The secret is in the user's downloaded JSON and is never committed.
2. **Debug iOS uses bundle `com.shellx.prod`** (user decision). The user made that edit in Xcode on the first machine, and it was never committed: Debug target `PRODUCT_BUNDLE_IDENTIFIER = com.shellx.prod` and `DEVELOPMENT_TEAM = W4RF3W4VTZ`. Do it properly in the xcconfig with the 1C follow-up below. Note that a Debug install then replaces the App Store app on the phone.
3. **Sign in with Apple is enabled** on `com.shellx.prod`. Nothing left to do.
4. **1C follow-up, Task 9 steps 7–8: Google G and Google Sans on iOS.** Run it after 2C frees the "ShellX Dev" simulator.
   - On the first machine the assets are in `~/Downloads/shellx-google-signin/`: `signin-assets.zip` (SHA-256 ba884069…1c1da1), `GoogleSans.ttf` and `OFL.txt` (SIL OFL 1.1, confirmed).
   - On a new machine the user downloads them again:
     ```
     mkdir -p ~/Downloads/shellx-google-signin && curl -fL -o ~/Downloads/shellx-google-signin/signin-assets.zip https://developers.google.com/static/identity/images/signin-assets.zip
     curl -fL -o ~/Downloads/shellx-google-signin/GoogleSans.ttf 'https://raw.githubusercontent.com/google/fonts/main/ofl/googlesans/GoogleSans%5BGRAD%2Copsz%2Cwght%5D.ttf'
     curl -fL -o ~/Downloads/shellx-google-signin/OFL.txt https://raw.githubusercontent.com/google/fonts/main/ofl/googlesans/OFL.txt
     ```
   - Known snag: `testGoogleSansIsUsedOnceBundled` expects `GoogleSans-Regular`. Adjust it if a static Medium face is used.
5. **1B: Google G and Google Sans on Mac and Windows.** The user accepts Google's branding terms, then runs `bash scripts/shellx/fetch-google-branding.sh`; it must end with `google branding: OK`. Then commit `chore(shellx): Google's official G mark and Google Sans Medium (OFL 1.1), downloaded by the user`. Until then the button is text-only and the desktop release scripts refuse to build.
6. **1C Task 15** runs after plan 1D's cut-over.

## Next after these

- 3B, once 3A lands.
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

# ShellX Android 3A — Scaffold Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the Android build (`shellx-android/` with `:core` and `:app`, plus the MIT `shellx-link/kotlin/` build it includes) and an app that opens on the ShellX launch screen in the iPhone's colours, as "ShellX Dev" (debug) or "ShellX" (release), together with the generated en/vi strings, `dev.sh`, the licence check and the parity ledger.

**Architecture:** `shellx-android/` (with `:core` on Kotlin/JVM and `:app` on Android, Compose and Material 3) includes the standalone build `shellx-link/kotlin/`, whose modules `link-core` and `link-account` stay empty for plan 3B. Every module locks its runtime classpaths in a `gradle.lockfile`, and `scripts/shellx/check-android-license.sh` checks those locks against an allowlist, along with Gradle paths, repositories and the trees. Strings are generated from the iPhone catalog, and render tests run on the JVM (Robolectric native graphics with Roborazzi), writing PNGs like the iPhone's `SnapshotWriter`.

**Tech Stack:** Gradle (Kotlin DSL, version catalogs, dependency locking), Android Gradle Plugin (AGP), Kotlin, Jetpack Compose with Material 3, JUnit 5 (JVM modules), JUnit 4 with Robolectric and Roborazzi (`:app`), Python 3.9+ with `unittest`, bash 3.2, and the Android SDK tools (adb, avdmanager, emulator, aapt2, zipalign, apksigner).

**Spec:** `docs/superpowers/specs/2026-11-07-shellx-android-app-design.md` (S3, in Vietnamese). This plan covers §5, §7.1, §7.2, §8 (scripts and emulators), §9 and §10 (the Firebase files). The cross-plan names come from `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` §1 and §5. Where the contracts and this plan overlap, the contracts win.

## Global Constraints

- Work only in `shellx-android/` (closed source), `shellx-link/kotlin/` (MIT), `scripts/shellx/` (the new licence files), `docs/superpowers/ledgers/shellx-android-parity.md` and one pointer line in `shellx-link/README.md`.
- Never copy, link or import from `ios/`, `Packages/`, `Sources/`, `cmux-tui/` or `shellx-core/`. Translating from `shellx-ios/` is allowed.
- Never write the upstream company name in any file under `shellx-android/` or `shellx-link/kotlin/`. This is the name `scripts/shellx/check-ios-license.sh` rule 4 refuses. Tests build it from pieces.
- `minSdk` is 26. `compileSdk` and `targetSdk` are both `API`: the level Google Play requires on the day of execution, and never below 36 (Task 0 Step 4). There is no dynamic colour.
- Every JVM module targets JVM 17. JVM modules test with JUnit 5 (the newest 5.x, never 6.x, per contracts §5). `:app` tests with JUnit 4 and Robolectric.
- App ids: release is `com.shellx.prod` with label "ShellX". Debug is `com.shellx.dev` with label "ShellX Dev". The namespace is `com.shellx.app`.
- `shellx-android/version.properties` holds `VERSION_NAME=1.0.0` and `VERSION_CODE=100`. 1.0.0 is the iPhone's `MARKETING_VERSION` today.
- Repositories: `google()` and `mavenCentral()` only. `gradlePluginPortal()` is allowed only in a `settings.gradle.kts` `pluginManagement` block.
- Licences: the app may ship Apache-2.0, MIT, BSD-2-Clause, BSD-3-Clause, Bouncy Castle, and Google SDKs listed by name. Test classpaths may also use EPL-1.0, EPL-2.0, ICU and CDDL-1.1. GPL, LGPL and AGPL are never allowed.
- The executor never downloads Android SDK packages. Only the user runs `sdkmanager` (USER steps).
- Do not use Gradle JVM toolchains (`jvmToolchain`), because they can download JDKs.
- When `JAVA_HOME` is unset, use `/Applications/Android Studio.app/Contents/jbr/Contents/Home`. This is JDK 17.0.9 on this Mac.
- This Mac has 16 GB of RAM, and `~/.gradle/gradle.properties` sets `-Xmx2G` and 4 workers. Never set `org.gradle.jvmargs` in the project. Run at most one ShellX emulator at a time.
- In every shell that runs Gradle without `dev.sh`, first run: `export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk"`. Run every command from the worktree root.
- Shell state does not carry over between commands. Run each step's code block in one shell call. When a block uses `latest` or `lic`, paste their one-line definitions first: `latest` is in Task 0 Step 4, `lic` in Task 3 Step 6.
- Scripts must run on bash 3.2: no associative arrays, no `mapfile`, no `${x,,}`, and never expand an empty array under `set -u`.
- Scripts must run on Python 3.9 (`/usr/bin/python3`): no `match`, no `tomllib`, and use `from __future__ import annotations`.
- Never install `com.shellx.prod` on a real phone. A debug-signed release build is installed only on an emulator, in Task 9.
- Never touch the user's running ShellX or cmux apps.
- Never commit a keystore, `key.properties` or a password. `google-services.json` is not a secret and is committed (Task 10).
- Every visible string comes from the generated `strings.xml` or from `strings_android.xml`. Never hand-edit the generated files.
- Commit with an explicit `git add <paths>`. When a task has logic, commit the failing test before the implementation, as the repo history does with `test(...)` and then `feat(...)`.
- Landing (contracts §1): after the final review, merge into `develop` and push `develop`. Never merge to `main`. Never deploy, upload or publish.

## Review Focus

1. **Catalog text that breaks Android.** Catalog values can hold `'`, `"`, `&`, `<`, a leading `@` or `?`, or a newline, and 30 of today's values contain `'`. Vietnamese text can also reorder a placeholder or drop one. In every case the generated XML must compile, and `getString` must neither crash nor garble. Tests (Task 2): `test_escapes_android_specials`, `test_vietnamese_may_reorder_positions`, `test_refuses_vietnamese_with_other_arguments`.
2. **The iPhone catalog changes while the Android plans run.** 1C and 2C will add keys: Apple-only features, iPhone words, maybe new format specifiers. The importer must refuse and name the key, and point to the way out. `dev.sh test app` must fail on stale files. Tests (Task 2): `test_ios_only_keys_are_skipped`, `test_ios_wording_needs_an_android_override`, `test_refuses_unsupported_formats`, `test_check_reports_stale_files`. Task 11 Step 1 handles the merge.
3. **A dependency change that breaks the licence rules.** The check must name the artefact, its lockfile and its scope when a dependency upgrade:
   - pulls in a new transitive artefact;
   - puts a test-only licence on the app classpath;
   - brings a copyleft licence;
   - lists an allowlist key twice, or ships an artefact still listed for tests only;
   - adds a vendored jar;
   - adds a repository.

   Tests: Task 3, every test.
4. **Debug and release installed side by side.** A debug build that says "ShellX" or `com.shellx.prod` collides with the Google Play install on the user's phone. A release build must not be debuggable. Tests: Task 6 `AppIdentityTest`, run on both variants, and the `build-release` checks.
5. **Start-up on API 26 and 36.** Dark mode must not flash white before Compose draws. Edge-to-edge must not leave unreadable system-bar icons. Tests: Task 7 `WindowColorsTest`, and Task 9 emulator screenshots in light and dark.

## File map

```
docs/superpowers/ledgers/shellx-android-parity.md        Task 1
scripts/shellx/check-android-license.sh                  Task 3 (bash entry point)
scripts/shellx/check_android_license.py                  Task 3 (the checks)
scripts/shellx/android-license-allowlist.txt             Task 3, entries added in Tasks 4–8
shellx-link/README.md                                    Task 4 (one pointer line)
shellx-link/kotlin/{settings.gradle.kts,build.gradle.kts,gradle.properties,gradle/libs.versions.toml,
                   gradlew,gradlew.bat,gradle/wrapper/*,.gitignore,README.md}           Task 4
shellx-link/kotlin/link-{core,account}/{build.gradle.kts,gradle.lockfile,src/test/...}  Task 4
shellx-android/{settings.gradle.kts,build.gradle.kts,gradle.properties,gradle/libs.versions.toml,
                version.properties,gradlew,gradlew.bat,gradle/wrapper/*,.gitignore,LICENSE}  Task 5
shellx-android/core/{build.gradle.kts,gradle.lockfile,src/test/...}                      Task 5
shellx-android/scripts/dev.sh                            Task 5, grows in Tasks 6, 8, 9
shellx-android/scripts/import-strings.py                 Task 2
shellx-android/scripts/strings-ios-only.txt              Task 2
shellx-android/scripts/tests/test_import_strings.py      Task 2
shellx-android/scripts/tests/test_check_android_license.py  Task 3
shellx-android/app/build.gradle.kts, proguard-rules.pro, gradle.lockfile                 Task 6
shellx-android/app/src/main/AndroidManifest.xml          Task 6
shellx-android/app/src/main/res/values*/strings.xml (generated), strings_android.xml     Task 2
shellx-android/app/src/debug/res/values/strings_android.xml                             Task 6
shellx-android/app/src/main/kotlin/com/shellx/app/MainActivity.kt                       Task 6, Task 8
shellx-android/app/src/main/kotlin/com/shellx/app/ui/theme/{ShellXColors,ShellXTheme}.kt  Task 7
shellx-android/app/src/main/kotlin/com/shellx/app/ui/LaunchView.kt                      Task 8
shellx-android/app/src/main/res/{drawable,mipmap-anydpi-v26,xml,values,values-night}/... Tasks 6–8
shellx-android/app/src/test/kotlin/com/shellx/app/...    Tasks 6, 7
shellx-android/app/src/testDebug/kotlin/com/shellx/app/screenshots/...                   Task 8
shellx-android/README.md                                 Task 9
shellx-android/app/src/{debug,release}/google-services.json                             Task 10 (USER)
```

---

### Task 0: Set up the worktree, the SDK packages and the phone

**Files:** none in the repository.

**Prerequisites:** none. No other plan has to be merged first (contracts §1).

**Interfaces:**
- Produces:
  - the worktree on branch `feat/shellx-android-3a-scaffold`;
  - `API`, the compile/target SDK level, written into the catalog in Task 6;
  - `AGP_MIN_BUILD_TOOLS`;
  - the system-image package ids for API 26 and 36.
- Re-derive any of these values later with the same commands. They are not stored anywhere.

- [ ] **Step 1: Create the worktree**

  Use superpowers:using-git-worktrees. Create the new branch `feat/shellx-android-3a-scaffold` from `develop`. Skip the skill's "Project Setup" and "Verify Clean Baseline" steps: the root `package.json` belongs to other parts of the repo, and Step 3 is this plan's baseline. If a native worktree tool picked another branch name, run `git switch -c feat/shellx-android-3a-scaffold`.

  Run: `git branch --show-current; git merge-base --is-ancestor develop HEAD && echo based-on-develop; test ! -e shellx-android && echo no-android-yet`

  Expected:
  ```
  feat/shellx-android-3a-scaffold
  based-on-develop
  no-android-yet
  ```

- [ ] **Step 2: Find the plan files**

  The contracts and this plan may be untracked in the main checkout. If `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` is missing in the worktree, read both files from `/Users/lehuuphu/Documents/myProjects/shellx/docs/superpowers/plans/` by absolute path. Never add them to this branch.

- [ ] **Step 3: Baseline the tools**

  Run:
  ```bash
  "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/java" -version 2>&1 | head -1
  ls "$HOME/Library/Android/sdk/cmdline-tools/latest/bin/sdkmanager" "$HOME/Library/Android/sdk/platform-tools/adb"
  python3 --version; /usr/bin/python3 --version; rsvg-convert --version
  ls -d "$HOME"/.gradle/wrapper/dists/gradle-*-bin/*/gradle-*/bin/gradle | sort -V | tail -1
  ```

  Expected:
  - `openjdk version "17.`;
  - both SDK paths listed;
  - Python 3.9 or newer, twice;
  - an `rsvg-convert` version;
  - a Gradle path (this Mac has `gradle-9.3.1`). Task 4 calls it `BOOT_GRADLE`.

  If something is missing, stop and tell the user what is missing.

- [ ] **Step 4: Find `API`, AGP and its minimum Build Tools (read-only web lookups)**

  1. Open https://developer.android.com/google/play/requirements/target-sdk. Note the target API level that new apps and updates need today.
  2. Set `API = max(that level, 36)`.
  3. Find the newest stable AGP:
     ```bash
     latest() { curl -fsS "$1" | grep -o '<version>[^<]*</version>' | sed 's/<[^>]*>//g' | grep -E "^${2:-[0-9]}[0-9.]*$" | sort -V | tail -1; }
     latest https://dl.google.com/dl/android/maven2/com/android/tools/build/gradle/maven-metadata.xml
     ```
  4. Open https://developer.android.com/build/releases/gradle-plugin. In the compatibility table, note that AGP version's minimum Gradle, minimum SDK Build Tools (`AGP_MIN_BUILD_TOOLS`) and JDK. If the JDK is above 17, stop and tell the user.

- [ ] **Step 5: Find the system images**

  Run:
  ```bash
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  "$HOME/Library/Android/sdk/cmdline-tools/latest/bin/sdkmanager" --list 2>&1 | grep -E 'system-images;android-(26|36);' | grep arm64-v8a | awk '{print $1}' | sort -u
  ```

  - **API 26:** pick the first that exists of `system-images;android-26;google_apis_playstore;arm64-v8a`, then `…;google_apis;arm64-v8a`, then `…;default;arm64-v8a`.
  - **API 36:** pick `system-images;android-36;google_apis_playstore;arm64-v8a`, or `…;google_apis;arm64-v8a` if that one is missing.
  - **If sdkmanager prints an XML or version error:** add `"cmdline-tools;latest"` as the first package of Step 6.

- [ ] **Step 6: USER — install the SDK packages**

  Ask the user to run the commands below, with the values from Steps 4–5 filled in. In Claude Code, the user prefixes each command with `!`.

  ```bash
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  SDKM="$HOME/Library/Android/sdk/cmdline-tools/latest/bin/sdkmanager"
  "$SDKM" --install "platform-tools" "emulator" "platforms;android-<API>" "build-tools;<AGP_MIN_BUILD_TOOLS>" "<API 26 image id>" "<API 36 image id>"
  "$SDKM" --licenses
  ```

  The installed emulator (32.1.11) is too old for API 36 images, so `emulator` must be updated too.

  **Meanwhile:** do Tasks 1–5. They need neither the new packages nor an Android build.

  Before Task 6, run `"$SDKM" --list_installed | grep -E "build-tools;<AGP_MIN_BUILD_TOOLS>|platforms;android-<API>|system-images;android-(26|36);"`. Expected: 4 lines.

- [ ] **Step 7: USER — connect the Android phone**

  Ask the user to do the following. The phone is needed by Task 1 (to record which phone it is) and by Task 9 (dogfood).
  1. Turn on Settings › About phone › tap "Build number" 7 times.
  2. Turn on Settings › System › Developer options › USB debugging.
  3. Plug the phone into this Mac and accept the "Allow USB debugging" prompt.

  **Meanwhile:** continue. Run `"$HOME/Library/Android/sdk/platform-tools/adb" devices -l`. When a line ends in `device` and is not `emulator-…`, write its serial to `~/.config/shellx/android-serial`. Create the folder if needed. Do not commit it.

---

### Task 1: Seed the parity ledger

**Files:**
- Create: `docs/superpowers/ledgers/shellx-android-parity.md`

**Interfaces:**
- Produces:
  - the ledger, with rows `6.1-1`…`6.1-17`, `6.2-1`…`6.2-21` and `A-1`…`A-5`;
  - the sections "Test devices" and "iPhone changes since the reference".
- Later tasks set `State` in the same commit as the work: Task 2 for `A-2`, Task 6 for `A-4`, Task 8 for `6.1-1` and `A-5`, Task 9 for the devices.

- [ ] **Step 1: Read the reference commit and the phone**

  Run:
  ```bash
  git rev-parse --short=10 "$(git merge-base develop HEAD)"
  S="$(cat ~/.config/shellx/android-serial 2>/dev/null)"; A="$HOME/Library/Android/sdk/platform-tools/adb"
  [ -n "$S" ] && for p in ro.product.manufacturer ro.product.model ro.build.version.release ro.build.version.sdk; do "$A" -s "$S" shell getprop "$p"; done
  ```

  The first value is `<REF>`. The next four are `<MAKER>`, `<MODEL>`, `<RELEASE>` and `<SDK>`. If there is no serial, ask the user once for the phone's maker, model and Android version. If they do not answer, write `pending (USER)`. Set `<74C>` to `yes` when the maker is Xiaomi (Redmi, POCO), OPPO or vivo; otherwise `no`.

- [ ] **Step 2: Write the ledger**

  Create the file with exactly this content, with the placeholders from Step 1 filled in:

````markdown
# Ledger: ShellX Android parity

Spec: `docs/superpowers/specs/2026-11-07-shellx-android-app-design.md` (S3) §6 and §9. Contracts:
`docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md`. iPhone reference: `shellx-ios/` at `<REF>`.

One row per screen or rule of S3 §6. Each row names the iPhone file the behaviour is translated from, the
Android file it goes to, the owning plan (contracts §1) and its state.

- The plan that builds a row sets its state in the same commit: `todo` → `done (<plan>)`. When Android
  behaves differently on purpose, it uses `differs (<plan>): <what and why>` instead.
- A change to `shellx-ios/` while the Android project runs adds a row to "iPhone changes since the reference"
  in the same commit. After the release, every new phone feature lands in both apps or gets a `differs` row.
- Paths: `ShellX/…` is under `shellx-ios/`, `ShellXAppCore/…` is under `shellx-ios/Packages/ShellXAppCore/Sources/`,
  `app:…` is under `shellx-android/app/src/main/kotlin/com/shellx/app/`, and `core:…` is under
  `shellx-android/core/src/main/kotlin/com/shellx/core/`.
- Mirror rule: `ShellX/<Folders>/<Name>.swift` → `app:<folders in lower case>/<Name>.kt`, and
  `ShellXAppCore/<Folder>/<Name>.swift` → `core:<folder in lower case>/<Name>.kt`. A type keeps its iPhone
  name. Contract names win over the rule. An owning plan that renames a file updates its row.

## Screens and flows (S3 §6.1)

| # | Screen or flow | iPhone | Android | Plan | State |
| --- | --- | --- | --- | --- | --- |
| 6.1-1 | Launch: logo and name | `ShellX/UI/RootView.swift` (`LaunchView`) | `app:ui/LaunchView.kt` | 3A | todo |
| 6.1-2 | Launch: the screen is chosen by the account phase | `ShellX/UI/RootView.swift` (`RootView`), `ShellXAppCore/Account/AppPhase.swift` | `app:ui/nav/ShellXNavHost.kt` (route `launch`) | 3D | todo |
| 6.1-3 | Sign-in: one "Continue with Google" button; errors for network, server, rate limit and pending wipe; "Session expired" banner after a 401 | `ShellX/UI/SignIn/SignInView.swift` | `app:ui/signin/SignInView.kt` (route `sign_in`) | 3D | todo |
| 6.1-4 | Pairing: scan the QR, paste `shellx-link://…`, or open the link from another app; confirm the Mac's name, wait for Allow, done; camera blocked; failure; the code stays in memory and nothing goes out before the user confirms | `ShellX/UI/Pairing/PairingSheet.swift`, `QRScannerView.swift`, `PairingPaste.swift`, `ShellX/Platform/CameraAccess.swift`, `ShellX/UI/Onboarding/FirstMacView.swift`, `Config/Info.plist` (`CFBundleURLTypes`), `ShellX/ShellXApp.swift` (`onOpenURL`) | `app:ui/pairing/…`, `app:platform/CameraAccess.kt`, `app:ui/onboarding/FirstMacView.kt`, intent filter `shellx-link` in `AndroidManifest.xml` (routes `first_mac`, `pairing`) | 3D | todo |
| 6.1-5 | Home: bell with the needs-you count, ＋ (new workspace, asking which Mac when there are several), Settings; groups Needs you, Running, Just finished, Workspaces (one per Mac), then "Ended · N" collapsed; pull to refresh; row actions rename and close a workspace, close an agent, "Remove from this phone" for a gone session | `ShellX/UI/Workspaces/WorkspaceListScreen.swift`, `WorkspaceListView.swift`, `WorkspaceRowView.swift`, `MachineGroupHeader.swift`, `ListNotice.swift`, `WorkspaceRenameSheet.swift`, `ShellX/UI/Home/FocusRowView.swift`, `NeedsYouBar.swift`, `EndedSessionsView.swift` | `app:ui/workspaces/…`, `app:ui/home/…` (route `home`) | 3D | todo |
| 6.1-6 | Session lists: agent sessions outside workspaces; ended sessions | `ShellX/UI/Home/SessionListScreen.swift`, `HomeRoute.swift`, `ShellX/UI/Workspaces/OtherSessionsView.swift` | `app:ui/home/SessionListScreen.kt`, `app:ui/workspaces/OtherSessionsView.kt` (route `sessions/{kind}`) | 3D | todo |
| 6.1-7 | Your Macs: set the default, unpair (asks first), remove a Mac that unpaired this phone | `ShellX/UI/Machines/MachinesView.swift`, `MachineRow.swift` | `app:ui/machines/…` (route `machines`) | 3D | todo |
| 6.1-8 | Workspace: title and git branch; menu with Rename, Close Tab (asks) and Close Workspace (asks); chip row, swipe between panes, long-press a chip to Close Tab; says when the Mac closed a pane or the workspace | `ShellX/UI/Workspaces/WorkspaceView.swift`, `WorkspaceScreen.swift`, `PaneChips.swift`, `WorkspaceFeedback.swift` | `app:ui/workspaces/WorkspaceScreen.kt` (`PaneContent(pane)`), `WorkspaceView.kt`, `PaneChips.kt`, `WorkspaceFeedback.kt` (route `workspace/{machineId}/{workspaceId}`) | 3E | todo |
| 6.1-9 | Shell pane: a real terminal | `ShellX/UI/Workspaces/ShellPanePlaceholder.swift` (until 2C) | `app:ui/workspaces/ShellPanePlaceholder.kt`, then `TerminalPane` | 3E, 3G | todo |
| 6.1-10 | Agent chat: entry kinds (text, collapsed thinking, tool step, state); load more when scrolling up; "New messages"; Stop; Force stop (asks); Close agent (asks); Remove from this phone | `ShellX/UI/Agent/AgentScreen.swift`, `AgentView.swift`, `AgentHeader.swift`, `ChatEntryRow.swift`, `NewMessagesButton.swift`, `StopButton.swift` | `app:ui/agent/…` (route `agent/{machineId}/{sessionId}`) | 3E | todo |
| 6.1-11 | Needs you: permission card (Deny, Allow, menu Always allow / All tools); question sheet (choices, "Other…" typed, answer by voice); plan sheet (Approve, other modes, Revise with required feedback, Reject) | `ShellX/UI/Pending/` (every file) | `app:ui/pending/…` (route `pending`) | 3E | todo |
| 6.1-12 | Composer: text; mic while the field is empty (hold to talk, release to send, slide left to cancel; tap mode with a screen reader); ＋ adds photos and files (at most 5, 10 MiB each); upload progress | `ShellX/UI/Composer/` (every file), `ShellX/Voice/` | `app:ui/composer/…`, `app:voice/…` | 3E | todo |
| 6.1-13 | Settings: Your Macs; Account (email, Sign out with a question, Delete account…); Appearance (System / Light / Dark); About (version, "Licenses" opens shellx.pro) | `ShellX/UI/Settings/SettingsView.swift`, `AccountSection.swift`, `AppearanceSection.swift`, `AboutSection.swift`, `ShellX/UI/Theme/AppAppearance.swift` | `app:ui/settings/…`, `app:ui/theme/AppAppearance.kt` (route `settings`) | 3D | todo |
| 6.1-14 | Settings › Voice: language picker, shown only once the mic works | `ShellX/UI/Settings/VoiceSection.swift` | `app:ui/settings/VoiceSection.kt` | 3D (section), 3E (engine) | todo |
| 6.1-15 | Update prompt: Update / Later, at launch and on every return; never in debug | `ShellX/UI/Update/UpdateAlert.swift`, `ShellXAppCore/Update/UpdatePrompt.swift`, `AppStoreRelease.swift` | `app:ui/update/UpdateAlert.kt` (Play In-App Updates, flexible flow), `core:update/UpdatePrompt.kt` | 3C (rules), 3E (UI) | todo |
| 6.1-16 | Notifications: `needs_you` (a tap opens Needs you) and `resolved` (removes the alert); none while the app is in front | `ShellX/Platform/PushAppDelegate.swift`, `ShellXAppCore/Push/PushRegistration.swift`, `PushPayload.swift` | `app:platform/…` (FCM, contracts §8) | 3E (app), 3F (relay) | todo |
| 6.1-17 | Demo without an account: a text button on sign-in and on "no Mac yet"; a fake Mac with workspaces, agents and needs-you items; a "Demo · Exit" banner; nothing goes to the network | `ShellX/Debug/DemoComposition.swift`, `DemoScript.swift` | `core:demo/DemoScript.kt`, entry points in `app:ui/signin/` and `app:ui/onboarding/` (route `demo`) | 3C (data), 3D (entry points) | todo |

## Behaviour rules (S3 §6.2)

| # | Rule | iPhone | Android | Plan | State |
| --- | --- | --- | --- | --- | --- |
| 6.2-1 | "Just finished": idle within 3 600 s of when the phone saw the session finish | `ShellXAppCore/Home/HomeFocus.swift` (`justDoneFor`) | `core:home/HomeFocus.kt` | 3C | todo |
| 6.2-2 | Finishes are detected; each session keeps its last 2 | `ShellXAppCore/Home/SessionFinishDetector.swift` | `core:home/SessionFinishDetector.kt` | 3C | todo |
| 6.2-3 | "Ended": shown for 43 200 s (12 h) after the end | `ShellXAppCore/Home/HomeFocus.swift` (`endedFor`) | `core:home/HomeFocus.kt` | 3C | todo |
| 6.2-4 | Ended rows are dismissed per Mac | `ShellXAppCore/Home/EndedDismissals.swift` | `core:home/EndedDismissals.kt` | 3C | todo |
| 6.2-5 | A gone session removed from the phone stays removed for 30 days | `ShellXAppCore/Home/GoneRemovals.swift` | `core:home/GoneRemovals.kt` | 3C | todo |
| 6.2-6 | A needs-you item belongs to the newest live session of the same Mac, workspace and agent | `ShellXAppCore/Home/HomeFocus.swift` | `core:home/HomeFocus.kt` | 3C | todo |
| 6.2-7 | The home re-sorts every 30 s | `ShellX/UI/Workspaces/WorkspaceListView.swift` | `app:ui/workspaces/WorkspaceListView.kt` | 3D | todo |
| 6.2-8 | Reconnects after 0.5, 1, 2, 4, 8 and 15 s, then every 30 s, each ±20 %; back to the start on `welcome` | `ShellXAppCore/Link/ReconnectSchedule.swift`, `MachineConnection.swift` | `core:link/ReconnectSchedule.kt`, `MachineConnection.kt` | 3C | todo |
| 6.2-9 | A revision ≤ the current one is dropped, the next one is applied, a gap forces a full resync | `ShellXAppCore/Link/RevisionGate.swift` | `core:link/RevisionGate.kt` | 3C | todo |
| 6.2-10 | After a network change, waits 300 ms for it to settle, then reconnects | `ShellXAppCore/Link/NetworkChangeFilter.swift`, `MachineHub.swift` (`networkChanged`), `ShellX/Platform/NetworkPathWatcher.swift` | `core:link/NetworkChangeFilter.kt`, `MachineHub.kt`, `app:platform/NetworkPathWatcher.kt` (`ConnectivityManager`) | 3C (rule), 3D (watcher) | todo |
| 6.2-11 | In the background: 25 s grace, then the sessions close; on return, the Macs that are not online reconnect | `ShellXAppCore/Link/MachineHub.swift` (`backgroundGrace`) | `core:link/MachineHub.kt`, `ProcessLifecycleOwner` in `app:ShellXApplication.kt` | 3C (rule), 3D (hook) | todo |
| 6.2-12 | Decisions: resent once when there is no answer, then an error; offline is an error at once and never queued; "handled elsewhere" shows for 2 s; feedback ≤ 4 096 bytes | `ShellXAppCore/Pending/DecisionCenter.swift` | `core:pending/DecisionCenter.kt` | 3C | todo |
| 6.2-13 | A chat message ≤ 16 384 bytes | `ShellXAppCore/Home/ComposerValidation.swift` | `core:home/ComposerValidation.kt` | 3C | todo |
| 6.2-14 | An answer ≤ 1 024 bytes | `ShellXAppCore/Pending/QuestionDraft.swift` | `core:pending/QuestionDraft.kt` | 3C | todo |
| 6.2-15 | Attachments: at most 5, 10 MiB each | `shellx-link/Sources/ShellXLinkCore/ShellXLink.swift` | `shellx-link/kotlin/link-core/src/main/kotlin/com/shellx/link/core/ShellXLink.kt` | 3B | todo |
| 6.2-16 | The chat copy is saved at most 500 ms after its last change | `ShellXAppCore/Agent/AgentThreadModel.swift` (`saveDelay`) | `core:agent/AgentThreadModel.kt` | 3C | todo |
| 6.2-17 | A workspace the Mac has not listed is waited for 5 s before the Mac is asked again | `ShellXAppCore/Workspaces/WorkspaceScreenModel.swift` (`patience`) | `core:workspaces/WorkspaceScreenModel.kt` | 3C | todo |
| 6.2-18 | A notice over the composer shows for 4 s | `ShellX/UI/Agent/AgentView.swift` (`noticeDuration`) | `app:ui/agent/AgentView.kt` | 3E | todo |
| 6.2-19 | "Nothing needs you" shows for 0.7 s before the page goes back | `ShellX/UI/Pending/PendingListView.swift` (`leaveDelay`) | `app:ui/pending/PendingListView.kt` | 3E | todo |
| 6.2-20 | A voice result settles after 1.5 s (regular recognizer) or 2 s (on-device recognizer) | `ShellX/Voice/LegacyTranscriber.swift` (`finalResultTimeout`), `AnalyzerTranscriber.swift` (`finalizeTimeout`) | `app:voice/…` (`SpeechRecognizer`) | 3E | todo |
| 6.2-21 | Voice capabilities are cached for 30 s | `ShellXAppCore/Voice/VoiceCapabilityCache.swift` (`defaultReuse`) | `core:voice/VoiceCapabilityCache.kt` | 3C | todo |

## Android-only differences

| # | Difference | Why | Android | Plan | State |
| --- | --- | --- | --- | --- | --- |
| A-1 | Settings › Notifications › "Notifications arriving late?": a short guide per phone maker and a button that opens the app's system settings; no `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Xiaomi, OPPO and vivo hold FCM for apps swiped away (S3 §7.4c) | `app:ui/settings/…` | 3E | todo |
| A-2 | iPhone wording replaced in 14 strings: "iPhone" → "phone", "App Store" → "Google Play", "VoiceOver" → "TalkBack", Apple's servers → the phone's speech service. Names: `first_mac_step2`, `first_mac_subtitle`, `machine_state_revoked`, `machines_unpair_message`, `pairing_error_needs_update`, `pairing_instructions`, `pairing_waiting_detail`, `settings_account_sign_out_confirm`, `settings_appearance_system`, `settings_voice_on_device`, `settings_voice_server`, `signin_error_local_wipe_pending`, `update_message`, `voice_mic_hint` | The words match the iPhone's, except for platform names (S3 §7.2) | `shellx-android/app/src/main/res/values*/strings_android.xml` | 3A | todo |
| A-3 | No Apple sign-in and no password sign-in | S3 §3 | — | — | differs (S3): by design |
| A-4 | Nothing is backed up or moved to a new phone (`allowBackup="false"`, and `data_extraction_rules.xml` excludes everything) | Secrets never go into a backup (S3 §7.3) | `AndroidManifest.xml`, `res/xml/data_extraction_rules.xml` | 3A | todo |
| A-5 | On Android 12 and later, a system splash (the app icon on the ShellX background) shows before the launch screen | Android always shows one | `res/values*/themes.xml` | 3A | todo |

## Test devices

| Device | Maker and model | Android (API) | Used for | S3 §7.4c test |
| --- | --- | --- | --- | --- |
| `ShellX_Dev_API_26` (emulator) | Pixel 5 profile | 8.0 (26) | lowest supported version | no |
| `ShellX_Dev_API_36` (emulator) | Pixel 5 profile | 16 (36) | newest version | no |
| The user's phone | <MAKER> <MODEL> | <RELEASE> (<SDK>) | camera, voice, notifications, Vietnamese keyboard | <74C> |

## iPhone changes since the reference

| Commit | iPhone change | Android row | State |
| --- | --- | --- | --- |
````

- [ ] **Step 3: Check the row counts**

  Run: `f=docs/superpowers/ledgers/shellx-android-parity.md; for p in '6\.1-' '6\.2-' 'A-'; do grep -c "^| $p" "$f"; done`

  Expected:
  ```
  17
  21
  5
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add docs/superpowers/ledgers/shellx-android-parity.md
  git commit -m "docs(shellx-android): seed the Android parity ledger"
  ```

---

### Task 2: Generate the Android strings from the iPhone catalog

**Files:**
- Create: `shellx-android/scripts/import-strings.py`
- Create: `shellx-android/scripts/strings-ios-only.txt`
- Create: `shellx-android/app/src/main/res/values/strings_android.xml`
- Create: `shellx-android/app/src/main/res/values-vi/strings_android.xml`
- Generate: `shellx-android/app/src/main/res/values/strings.xml`
- Generate: `shellx-android/app/src/main/res/values-vi/strings.xml`
- Modify: `docs/superpowers/ledgers/shellx-android-parity.md` (row A-2 → `done (3A)`)
- Test: `shellx-android/scripts/tests/test_import_strings.py`

**Interfaces:**
- Produces:
  - `shellx-android/scripts/import-strings.py [--root <repo root>] [--check]`. The default root is the script's folder `/../..`.
  - It writes, or with `--check` only compares, the two generated files.
  - On success, stdout is `import-strings: wrote …` or `import-strings: ok (<n> strings, <m> plurals)`, and the exit code is 0.
  - On a problem, every problem goes to stderr as `import-strings: <iOS key or Android name>: <problem>`, nothing is written, and the exit code is 1.
  - A stale file prints `import-strings: stale <path>; run shellx-android/scripts/import-strings.py` and exits 1.
  - Android names used later: `app_name` (Android-only, translatable="false"), `root_title`, and every converted iOS key, for example `push_title`, `push_needs_you`, `push_needs_you_workspace` (contracts §8).

- [ ] **Step 1: Write the failing tests**

  Create `shellx-android/scripts/tests/test_import_strings.py`:

```python
"""Tests for shellx-android/scripts/import-strings.py.

Run: python3 -m unittest discover -s shellx-android/scripts/tests -v
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "import-strings.py"
RES = "shellx-android/app/src/main/res"
HEADER = ('<?xml version="1.0" encoding="utf-8"?>\n'
          "<!-- Generated by shellx-android/scripts/import-strings.py from "
          "shellx-ios/ShellX/Localizable.xcstrings. Do not edit: run the script. -->\n")


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def plural(**forms):
    return {"variations": {"plural": {quantity: unit(text) for quantity, text in forms.items()}}}


def entry(en, vi=None, translate=True):
    localizations = {"en": unit(en) if isinstance(en, str) else en}
    if vi is not None:
        localizations["vi"] = unit(vi) if isinstance(vi, str) else vi
    result = {"extractionState": "manual", "localizations": localizations}
    if not translate:
        result["shouldTranslate"] = False
    return result


class ImportStringsTests(unittest.TestCase):
    def tree(self, strings, android_en=None, android_vi=None, ios_only=None):
        root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, root)
        catalog = root / "shellx-ios/ShellX/Localizable.xcstrings"
        catalog.parent.mkdir(parents=True)
        catalog.write_text(json.dumps({"sourceLanguage": "en", "strings": strings, "version": "1.0"}),
                           encoding="utf-8")
        for folder, body in (("values", android_en), ("values-vi", android_vi)):
            (root / RES / folder).mkdir(parents=True)
            if body is not None:
                (root / RES / folder / "strings_android.xml").write_text(
                    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n' + body + "</resources>\n",
                    encoding="utf-8")
        if ios_only is not None:
            (root / "shellx-android/scripts").mkdir(parents=True)
            (root / "shellx-android/scripts/strings-ios-only.txt").write_text(ios_only, encoding="utf-8")
        return root

    def run_script(self, root, *args):
        return subprocess.run([sys.executable, str(SCRIPT), "--root", str(root), *args],
                              capture_output=True, text=True)

    def generated(self, root, folder):
        return (root / RES / folder / "strings.xml").read_text(encoding="utf-8")

    def assertWrites(self, root):
        result = self.run_script(root)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def assertRefused(self, root, *needles):
        result = self.run_script(root)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        for needle in needles:
            self.assertIn(needle, result.stderr)
        self.assertFalse((root / RES / "values/strings.xml").exists(), "nothing is written when refusing")

    def test_writes_the_exact_files(self):
        root = self.tree({
            "root.title": entry("ShellX", "ShellX"),
            "agent.close.title %@": entry("Close %@?", "Đóng agent %@?"),
            "push.title": entry("ShellX", translate=False),
            "workspaces.group.count %lld": entry(plural(one="%lld workspace", other="%lld workspaces"),
                                                 plural(other="%lld workspace")),
        })
        self.assertWrites(root)
        self.assertEqual(self.generated(root, "values"), HEADER + (
            "<resources>\n"
            '    <string name="agent_close_title">Close %1$s?</string>\n'
            '    <string name="push_title" translatable="false">ShellX</string>\n'
            '    <string name="root_title">ShellX</string>\n'
            '    <plurals name="workspaces_group_count">\n'
            '        <item quantity="one">%1$d workspace</item>\n'
            '        <item quantity="other">%1$d workspaces</item>\n'
            "    </plurals>\n"
            "</resources>\n"))
        self.assertEqual(self.generated(root, "values-vi"), HEADER + (
            "<resources>\n"
            '    <string name="agent_close_title">Đóng agent %1$s?</string>\n'
            '    <string name="root_title">ShellX</string>\n'
            '    <plurals name="workspaces_group_count">\n'
            '        <item quantity="other">%1$d workspace</item>\n'
            "    </plurals>\n"
            "</resources>\n"))

    def test_names_follow_the_contract_rule(self):
        root = self.tree({
            "agent.forceStop.title %@ %@": entry("Force stop %1$@ in %2$@?", "Dừng hẳn %1$@ ở %2$@?"),
            "pairing.error.notShellXCode": entry("Not a ShellX code", "Không phải mã ShellX"),
            "firstMac.step2": entry("Scan it.", "Quét mã."),
            "push.needsYou": entry("%@ is waiting for you", "%@ đang chờ bạn xác nhận"),
        })
        self.assertWrites(root)
        out = self.generated(root, "values")
        self.assertIn('<string name="agent_force_stop_title">Force stop %1$s in %2$s?</string>', out)
        self.assertIn('<string name="pairing_error_not_shell_x_code">Not a ShellX code</string>', out)
        self.assertIn('<string name="first_mac_step2">Scan it.</string>', out)
        self.assertIn('<string name="push_needs_you">%1$s is waiting for you</string>', out)

    def test_a_renamed_key_resolves_the_running_collision(self):
        root = self.tree({
            "agent.state.running": entry("Running", "Đang chạy"),
            "agent.state.running %@": entry("Running for %@", "Đang chạy %@"),
        })
        self.assertWrites(root)
        out = self.generated(root, "values")
        self.assertIn('<string name="agent_state_running">Running</string>', out)
        self.assertIn('<string name="agent_state_running_for">Running for %1$s</string>', out)

    def test_an_unresolved_collision_is_refused(self):
        self.assertRefused(self.tree({"home.needsYou": entry("A", "Á"), "home.needs_you": entry("B", "Bé")}),
                           "home_needs_you")

    def test_vietnamese_may_reorder_positions(self):
        root = self.tree({"a.b %@ %@": entry("%1$@ in %2$@", "%2$@ có %1$@")})
        self.assertWrites(root)
        self.assertIn('<string name="a_b">%2$s có %1$s</string>', self.generated(root, "values-vi"))

    def test_escapes_android_specials(self):
        root = self.tree({
            "a.apostrophe": entry("Can't", "Không được"),
            "a.quote": entry('Say "hi" & <go>', "Nói"),
            "a.at": entry("@home", "@nhà"),
            "a.question": entry("?why", "?sao"),
            "a.backslash": entry("a\\b", "a\\b"),
            "a.newline": entry("one\ntwo", "một\nhai"),
        })
        self.assertWrites(root)
        out = self.generated(root, "values")
        self.assertIn(r'<string name="a_apostrophe">Can\'t</string>', out)
        self.assertIn(r'<string name="a_quote">Say \"hi\" &amp; &lt;go&gt;</string>', out)
        self.assertIn(r'<string name="a_at">\@home</string>', out)
        self.assertIn(r'<string name="a_question">\?why</string>', out)
        self.assertIn(r'<string name="a_backslash">a\\b</string>', out)
        self.assertIn(r'<string name="a_newline">one\ntwo</string>', out)

    def test_refuses_unsupported_formats(self):
        for value in ("100%", "%ld items", "%f MB", "50%% done", "%s"):
            with self.subTest(value=value):
                self.assertRefused(self.tree({"a.b": entry(value, value)}), "a.b")

    def test_refuses_mixed_positional_and_plain(self):
        self.assertRefused(self.tree({"a.b": entry("%1$@ and %@", "%1$@ và %@")}), "a.b")

    def test_refuses_vietnamese_with_other_arguments(self):
        self.assertRefused(self.tree({"a.b %@": entry("Hi %@", "Xin chào")}), "a.b %@")

    def test_refuses_a_missing_translation(self):
        self.assertRefused(self.tree({"a.b": entry("Hi")}), "a.b")

    def test_refuses_edge_and_double_spaces(self):
        for value in (" Hi", "Hi ", "Hi  there"):
            with self.subTest(value=value):
                self.assertRefused(self.tree({"a.b": entry(value, "Chào")}), "a.b")

    def test_refuses_other_variations(self):
        device = {"variations": {"device": {"iphone": unit("x")}}}
        self.assertRefused(self.tree({"a.b": entry(device, device)}), "a.b")

    def test_ios_wording_needs_an_android_override(self):
        strings = {"first.subtitle": entry("Answer from this iPhone.", "Trả lời từ iPhone này.")}
        self.assertRefused(self.tree(strings), "first.subtitle", "strings_android.xml")
        root = self.tree(strings,
                         android_en='    <string name="first_subtitle">Answer from this phone.</string>\n',
                         android_vi='    <string name="first_subtitle">Trả lời từ điện thoại này.</string>\n')
        self.assertWrites(root)
        self.assertNotIn("first_subtitle", self.generated(root, "values"))
        self.assertNotIn("first_subtitle", self.generated(root, "values-vi"))

    def test_an_override_keeps_the_ios_arguments(self):
        strings = {"settings.voice.server %@": entry("This iPhone can't do %@.", "iPhone này không làm được %@.")}
        root = self.tree(strings,
                         android_en='    <string name="settings_voice_server">This phone can\\\'t.</string>\n',
                         android_vi='    <string name="settings_voice_server">Không làm được %1$s.</string>\n')
        self.assertRefused(root, "settings_voice_server")

    def test_ios_only_keys_are_skipped(self):
        strings = {"signin.apple": entry("Continue with Apple", "Tiếp tục với Apple"),
                   "root.title": entry("ShellX", "ShellX")}
        root = self.tree(strings, ios_only="# iPhone-only\nsignin.apple\n")
        self.assertWrites(root)
        self.assertNotIn("signin_apple", self.generated(root, "values"))
        self.assertRefused(self.tree(strings, ios_only="signin.apple\ngone.key\n"), "gone.key")

    def test_android_strings_need_vietnamese(self):
        self.assertRefused(self.tree({}, android_en='    <string name="late_hint">Late?</string>\n', android_vi=""),
                           "late_hint")
        self.assertWrites(self.tree(
            {}, android_en='    <string name="app_name" translatable="false">ShellX</string>\n', android_vi=""))

    def test_check_reports_stale_files(self):
        strings = {"root.title": entry("ShellX", "ShellX")}
        root = self.tree(strings)
        missing = self.run_script(root, "--check")
        self.assertEqual(missing.returncode, 1)
        self.assertIn("stale", missing.stderr)
        self.assertWrites(root)
        fresh = self.run_script(root, "--check")
        self.assertEqual(fresh.returncode, 0, fresh.stderr)
        self.assertIn("import-strings: ok", fresh.stdout)
        catalog = root / "shellx-ios/ShellX/Localizable.xcstrings"
        catalog.write_text(json.dumps({"sourceLanguage": "en", "version": "1.0",
                                       "strings": {"root.title": entry("ShellX 2", "ShellX 2")}}), encoding="utf-8")
        stale = self.run_script(root, "--check")
        self.assertEqual(stale.returncode, 1)
        self.assertIn("values/strings.xml", stale.stderr)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the tests to see them fail**

  Run: `python3 -m unittest discover -s shellx-android/scripts/tests -v`

  Expected: FAIL. Every test fails, because `import-strings.py` does not exist yet ("can't open file").

- [ ] **Step 3: Commit the failing tests**

  ```bash
  git add shellx-android/scripts/tests/test_import_strings.py
  git commit -m "test(shellx-android): strings come from the iPhone catalog"
  ```

- [ ] **Step 4: Implement `shellx-android/scripts/import-strings.py`**

  Use the CLI from **Interfaces**. Use the standard library only (`argparse`, `json`, `re`, `xml.etree.ElementTree`), with Python 3.9 syntax. The header comment states the rules below.

  **Inputs.** All paths are under `--root`:
  - `shellx-ios/ShellX/Localizable.xcstrings`;
  - `shellx-android/app/src/main/res/values/strings_android.xml` and `values-vi/strings_android.xml`. Each may be missing.
  - `shellx-android/scripts/strings-ios-only.txt`, which may be missing. It holds one iOS key per line; `#` comments and blank lines are ignored.

  **Name of a key.** Use `RENAMES = {"agent.state.running %@": "agent_state_running_for"}` first. Otherwise:
  ```python
  base = key.split(" ", 1)[0]
  segments = []
  for segment in base.split("."):
      segment = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1_\2", segment)
      segment = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", segment)
      segments.append(segment.lower())
  name = "_".join(segments)        # must match [a-z][a-z0-9_]*
  ```

  **Formats.**
  - Read every `%` left to right. It must match `%(?:(\d+)\$)?(@|lld|d)`; anything else is an "unsupported format" problem.
  - Number the plain specifiers 1, 2, … in order. A value that mixes plain and positional specifiers is a problem.
  - Write `%<n>$s` for `@` and `%<n>$d` for `lld` and `d`.
  - The set of `(position, type)` must be equal across en, vi and every plural form of the key.

  **Escaping, in this order:**
  1. `\` → `\\`
  2. `&` → `&amp;`
  3. `<` → `&lt;`
  4. `>` → `&gt;`
  5. `'` → `\'`
  6. `"` → `\"`
  7. newline → `\n`
  8. tab → `\t`
  9. a leading `@` or `?` gets a `\` in front.

  A value with leading or trailing whitespace, or two spaces in a row, is a problem: Android would collapse it.

  **Entries.**
  - A `stringUnit` becomes `<string>`.
  - `variations.plural` becomes `<plurals>`, with `<item quantity>` in CLDR order (zero, one, two, few, many, other).
  - Any other variation is a problem.
  - A key with `"shouldTranslate": false` gets `translatable="false"` in `values/` and is left out of `values-vi/`.
  - Every other key needs a non-empty vi value for every form.
  - Keys listed in `strings-ios-only.txt` are skipped. A listed key that is missing from the catalog is a problem.

  **Overrides.**
  - A `<string>` or `<plurals>` name defined in `values/strings_android.xml` is left out of both generated files.
  - Every translatable name in `values/strings_android.xml` must also be in `values-vi/strings_android.xml`, and the other way round.
  - An override of an iOS key must use the same `(position, type)` set as that key. Parse with `%(\d+)\$([sd])` on the text, in both languages.

  **iOS wording.** A generated en or vi value that matches `\b(?:iPhone|iPad|iOS|App Store|TestFlight|Apple|VoiceOver|Face ID|Touch ID|Keychain|iCloud|Siri)\b` is a problem. The message says: `add an Android override in strings_android.xml (values and values-vi) or list the key in shellx-android/scripts/strings-ios-only.txt`.

  **Collisions.** Two keys with the same name are a problem that names both keys.

  **Output.**
  - The header is exactly `HEADER` from the test, followed by `<resources>`.
  - All `<string>` elements come first, sorted by name, indented 4 spaces. Then all `<plurals>`, sorted by name, with items indented 8 spaces.
  - Then `</resources>` and one trailing newline.

  **Modes.**
  - The default mode writes both files and prints `import-strings: wrote shellx-android/app/src/main/res/values/strings.xml and values-vi/strings.xml (<n> strings, <m> plurals)`. The counts are for `values/`.
  - `--check` compares the files and prints `import-strings: ok (<n> strings, <m> plurals)`.

- [ ] **Step 5: Run the tests on both Pythons**

  Run:
  ```bash
  python3 -m unittest discover -s shellx-android/scripts/tests -v
  /usr/bin/python3 -m unittest discover -s shellx-android/scripts/tests -v
  ```

  Expected: both end with `Ran 17 tests` and `OK`.

- [ ] **Step 6: Write the iOS-only list and the Android strings**

  Create `shellx-android/scripts/strings-ios-only.txt`:
  ```
  # iPhone catalog keys the Android app never shows (an iPhone-only feature, such as Sign in with Apple).
  # import-strings.py leaves them out of strings.xml. One key per line, exactly as in Localizable.xcstrings.
  ```

  Create `shellx-android/app/src/main/res/values/strings_android.xml`:
  ```xml
  <?xml version="1.0" encoding="utf-8"?>
  <!-- Android-only strings, and Android wording for iPhone strings: a name defined here replaces the one
       import-strings.py would generate. Every translatable name also needs values-vi/strings_android.xml. -->
  <resources>
      <string name="app_name" translatable="false">ShellX</string>
      <string name="first_mac_step2">Scan the QR code it shows with this phone.</string>
      <string name="first_mac_subtitle">See and answer Claude Code on your Mac from this phone.</string>
      <string name="machine_state_revoked">This Mac removed this phone</string>
      <string name="machines_unpair_message">This phone will stop getting requests from this Mac. To use it again, pair again.</string>
      <string name="pairing_error_needs_update">This code is from a newer ShellX. Update ShellX on this phone.</string>
      <string name="pairing_instructions">On your Mac, open ShellX, right-click “This Mac” and choose Pair Phone…</string>
      <string name="pairing_waiting_detail">Keep ShellX open on this phone until the Mac answers.</string>
      <string name="settings_account_sign_out_confirm">This phone will be removed from every paired Mac, and its history will be deleted.</string>
      <string name="settings_appearance_system">Match phone</string>
      <string name="settings_voice_on_device">Recognized on this phone.</string>
      <string name="settings_voice_server">This phone can\'t recognize %1$s on device, so your voice goes to the phone\'s speech recognition service, usually Google\'s servers. ShellX never receives your voice.</string>
      <string name="signin_error_local_wipe_pending">Couldn\'t clear the previous account\'s data on this phone. Try again.</string>
      <string name="update_message">Update ShellX on Google Play to get the latest fixes and features.</string>
      <string name="voice_mic_hint">Hold to talk and release to finish. With TalkBack, double-tap to start and double-tap again to finish.</string>
  </resources>
  ```

  Create `shellx-android/app/src/main/res/values-vi/strings_android.xml`:
  ```xml
  <?xml version="1.0" encoding="utf-8"?>
  <resources>
      <string name="first_mac_step2">Quét mã QR hiện ra bằng điện thoại này.</string>
      <string name="first_mac_subtitle">Xem và trả lời Claude Code trên Mac ngay từ điện thoại này.</string>
      <string name="machine_state_revoked">Mac này đã gỡ điện thoại này</string>
      <string name="machines_unpair_message">Điện thoại này sẽ không còn nhận việc chờ từ Mac này. Muốn dùng lại thì ghép cặp lại.</string>
      <string name="pairing_error_needs_update">Mã này từ bản ShellX mới hơn. Hãy cập nhật ShellX trên điện thoại này.</string>
      <string name="pairing_instructions">Trên Mac, mở ShellX, bấm chuột phải vào “Mac này” rồi chọn Ghép cặp điện thoại…</string>
      <string name="pairing_waiting_detail">Giữ ShellX mở trên điện thoại này cho tới khi Mac trả lời.</string>
      <string name="settings_account_sign_out_confirm">Điện thoại này sẽ bị gỡ khỏi mọi Mac đã ghép cặp, và lịch sử trên điện thoại sẽ bị xoá.</string>
      <string name="settings_appearance_system">Theo máy</string>
      <string name="settings_voice_on_device">Nhận dạng ngay trên điện thoại.</string>
      <string name="settings_voice_server">Điện thoại này chưa nhận dạng được %1$s ngay trên máy, nên giọng nói được gửi tới dịch vụ nhận dạng giọng nói của máy, thường là máy chủ của Google. ShellX không nhận giọng nói của bạn.</string>
      <string name="signin_error_local_wipe_pending">Không xoá được dữ liệu của tài khoản trước trên điện thoại này. Thử lại.</string>
      <string name="update_message">Cập nhật ShellX trên Google Play để có các bản sửa lỗi và tính năng mới nhất.</string>
      <string name="voice_mic_hint">Giữ để nói, thả ra là xong. Với TalkBack, chạm hai lần để bắt đầu, chạm hai lần nữa là xong.</string>
  </resources>
  ```

- [ ] **Step 7: Generate and check the strings**

  Run: `python3 shellx-android/scripts/import-strings.py && python3 shellx-android/scripts/import-strings.py --check`

  Expected: `import-strings: wrote …`, then `import-strings: ok (238 strings, 1 plurals)`. These counts hold for the catalog at `d0a26e26a7`. If the catalog has changed since, the script's own counts are the truth.

  If the importer refuses a key, follow its message:
  - If the key belongs to an iPhone-only feature, add it to `strings-ios-only.txt`.
  - Otherwise, add an override. Write "phone" / "điện thoại" for "iPhone", "Google Play" for "App Store", and "TalkBack" for "VoiceOver", and change nothing else.

  Then rerun the command.

- [ ] **Step 8: Mark ledger row A-2 as done**

  In the ledger, change row `A-2`'s State from `todo` to `done (3A)`.

- [ ] **Step 9: Commit the implementation**

  ```bash
  git add shellx-android/scripts/import-strings.py shellx-android/scripts/strings-ios-only.txt \
    shellx-android/app/src/main/res/values/strings_android.xml shellx-android/app/src/main/res/values-vi/strings_android.xml \
    shellx-android/app/src/main/res/values/strings.xml shellx-android/app/src/main/res/values-vi/strings.xml \
    docs/superpowers/ledgers/shellx-android-parity.md
  git commit -m "feat(shellx-android): strings come from the iPhone catalog, with Android wording for 14"
  ```

---

### Task 3: Write the Android licence check

**Files:**
- Create: `scripts/shellx/check-android-license.sh`
- Create: `scripts/shellx/check_android_license.py`
- Create: `scripts/shellx/android-license-allowlist.txt`
- Test: `shellx-android/scripts/tests/test_check_android_license.py`

**Interfaces:**
- Produces:
  - `scripts/shellx/check-android-license.sh [--root <repo root>]`. On success it prints `check-android-license: ok` and exits 0.
  - On violations it prints one `violation: <path relative to root>[:<line>]: <message>` line per problem and exits 1.
  - On a usage error it exits 2.
  - It always runs `scripts/shellx/check-link-license.sh` from its own folder, on the real repository.
  - The allowlist format, and "The allowlist procedure" in Step 6, are used by Tasks 4–8 and by every later plan that adds a dependency.

- [ ] **Step 1: Write the failing tests**

  Create `shellx-android/scripts/tests/test_check_android_license.py`:

```python
"""Tests for scripts/shellx/check-android-license.sh.

Run: python3 -m unittest discover -s shellx-android/scripts/tests -v
"""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
SCRIPT = REPO / "scripts/shellx/check-android-license.sh"
COMPANY = "Mana" + "flow"  # built from pieces: the check scans this file too

CLEAN = {
    "shellx-android/settings.gradle.kts": (
        "pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }\n"
        "dependencyResolutionManagement { repositories { google(); mavenCentral() } }\n"
        'includeBuild("../shellx-link/kotlin")\n'
        'include(":app")\n'),
    "shellx-android/build.gradle.kts": "plugins { }\n",
    "shellx-android/app/build.gradle.kts": (
        '// includeBuild("../../Sources") in a comment does not count\n'
        'description = "see ../../Sources"\n'
        'val firebase = file("src/debug/google-services.json")\n'),
    "shellx-android/app/gradle.lockfile": (
        "# This is a Gradle generated file for dependency locking.\n"
        "androidx.core:core:1.0.0=debugRuntimeClasspath,releaseRuntimeClasspath\n"
        "junit:junit:4.13.2=debugUnitTestRuntimeClasspath,releaseUnitTestRuntimeClasspath\n"
        "empty=debugAndroidTestRuntimeClasspath\n"),
    "shellx-android/gradle/wrapper/gradle-wrapper.jar": "PK not really a jar\n",
    "shellx-link/kotlin/settings.gradle.kts": 'include(":link-core")\n',
    "shellx-link/kotlin/build.gradle.kts": "\n",
    "shellx-link/kotlin/link-core/build.gradle.kts": 'val vectors = layout.projectDirectory.dir("../../vectors")\n',
    "shellx-link/kotlin/link-core/gradle.lockfile": (
        "org.jetbrains.kotlin:kotlin-stdlib:2.0.0=runtimeClasspath,testRuntimeClasspath\nempty=\n"),
    "scripts/shellx/android-license-allowlist.txt": (
        "# group:artifact scope licence\n"
        "androidx.*:*              ship  Apache-2.0\n"
        "org.jetbrains.kotlin:*    ship  Apache-2.0\n"
        "junit:junit               test  EPL-1.0  # JUnit 4\n"),
}
LOCK = "shellx-android/app/gradle.lockfile"
ALLOW = "scripts/shellx/android-license-allowlist.txt"


class CheckAndroidLicenseTests(unittest.TestCase):
    def tree(self, changes=None, remove=()):
        root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, root)
        files = dict(CLEAN)
        files.update(changes or {})
        for path, text in files.items():
            if path in remove:
                continue
            (root / path).parent.mkdir(parents=True, exist_ok=True)
            (root / path).write_text(text, encoding="utf-8")
        return root

    def check(self, root=None):
        return subprocess.run(["bash", str(SCRIPT)] + (["--root", str(root)] if root else []),
                              capture_output=True, text=True)

    def assertPasses(self, root=None):
        result = self.check(root)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("check-android-license: ok", result.stdout)

    def assertFails(self, root, *needles):
        result = self.check(root)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        for needle in needles:
            self.assertIn(needle, result.stdout)

    def test_repository_passes(self):
        self.assertPasses()

    def test_clean_tree_passes(self):
        self.assertPasses(self.tree())

    def test_unlisted_dependency_fails(self):
        root = self.tree({LOCK: CLEAN[LOCK] + "com.example:evil:1.0=releaseRuntimeClasspath\n"})
        self.assertFails(root, LOCK, "com.example:evil:1.0")

    def test_test_licence_on_the_shipped_classpath_fails(self):
        self.assertFails(self.tree({LOCK: CLEAN[LOCK] + "junit:junit:4.13.2=releaseRuntimeClasspath\n"}),
                         "junit:junit:4.13.2")

    def test_copyleft_entries_fail(self):
        for licence in ("GPL-2.0", "LGPL-2.1", "AGPL-3.0", "GPL-2.0-with-classpath-exception"):
            with self.subTest(licence=licence):
                root = self.tree({ALLOW: CLEAN[ALLOW] + f"org.example:lib  test  {licence}\n"})
                self.assertFails(root, "android-license-allowlist.txt", "org.example:lib")

    def test_unknown_licence_or_scope_fails(self):
        for line in ("org.example:lib  ship  WTFPL\n", "org.example:lib  shipped  MIT\n",
                     "org.example:lib  ship  EPL-2.0\n"):
            with self.subTest(line=line):
                self.assertFails(self.tree({ALLOW: CLEAN[ALLOW] + line}), "org.example:lib")

    def test_only_three_wildcards_exist(self):
        self.assertFails(self.tree({ALLOW: CLEAN[ALLOW] + "com.example:*  ship  MIT\n"}), "com.example:*")

    def test_google_sdks_are_listed_by_name(self):
        for line in ("com.google.firebase:*  ship  Google-SDK\n", "com.google.ads:ads  ship  Google-SDK\n",
                     "com.google.android.gms:*  ship  Apache-2.0\n"):
            with self.subTest(line=line):
                self.assertFails(self.tree({ALLOW: CLEAN[ALLOW] + line}), "android-license-allowlist.txt")
        self.assertPasses(self.tree({
            ALLOW: CLEAN[ALLOW] + "com.google.firebase:firebase-messaging  ship  Google-SDK\n",
            LOCK: CLEAN[LOCK] + "com.google.firebase:firebase-messaging:25.0.0=releaseRuntimeClasspath\n"}))

    def test_the_most_specific_entry_decides(self):
        self.assertFails(self.tree({
            ALLOW: CLEAN[ALLOW] + "androidx.test:core  test  Apache-2.0\n",
            LOCK: CLEAN[LOCK] + "androidx.test:core:1.6.0=releaseRuntimeClasspath\n"}), "androidx.test:core:1.6.0")

    def test_duplicate_key_is_an_error(self):
        for second in ("org.example:lib  test  MIT\n", "org.example:lib  ship  MIT\n"):
            with self.subTest(second=second):
                root = self.tree({ALLOW: CLEAN[ALLOW] + "org.example:lib  test  MIT\n" + second})
                self.assertFails(root, "android-license-allowlist.txt", "org.example:lib", "listed twice")

    def test_test_scope_dependency_on_ship_classpath_fails_until_moved(self):
        lock = CLEAN[LOCK] + "org.example:lib:1.0=releaseRuntimeClasspath\n"
        self.assertFails(self.tree({LOCK: lock, ALLOW: CLEAN[ALLOW] + "org.example:lib  test  MIT\n"}),
                         "org.example:lib:1.0", "move its allowlist line to ship")
        self.assertPasses(self.tree({LOCK: lock, ALLOW: CLEAN[ALLOW] + "org.example:lib  ship  MIT\n"}))

    def test_every_module_has_a_lockfile_with_its_runtime_classpath(self):
        self.assertFails(self.tree(remove=(LOCK,)), "shellx-android/app", "gradle.lockfile")
        self.assertFails(self.tree({LOCK: "junit:junit:4.13.2=debugUnitTestRuntimeClasspath\nempty=\n"}),
                         "releaseRuntimeClasspath")

    def test_paths_stay_inside_the_android_and_link_trees(self):
        cases = [
            ("shellx-android/settings.gradle.kts", 'includeBuild("../shellx-core")\n', "../shellx-core"),
            ("shellx-android/settings.gradle.kts", 'includeBuild("$rootDir/../shellx-link/kotlin")\n', "includeBuild"),
            ("shellx-android/app/build.gradle.kts",
             'android { sourceSets { getByName("main") { java.srcDir("../../Sources") } } }\n', "../../Sources"),
            ("shellx-link/kotlin/link-core/build.gradle.kts", 'val x = file("/Users/me/lib")\n', "/Users/me/lib"),
            ("shellx-link/kotlin/link-core/build.gradle.kts", 'val x = files("~/lib")\n', "~/lib"),
            ("shellx-android/build.gradle.kts", 'val z = file("${rootDir}/../Packages")\n',
             "shellx-android/build.gradle.kts"),
            ("shellx-link/kotlin/link-core/build.gradle.kts", 'val v = layout.projectDirectory.dir("../../../ios")\n',
             "../../../ios"),
        ]
        for path, text, needle in cases:
            with self.subTest(text=text):
                self.assertFails(self.tree({path: text}), needle)

    def test_only_maven_central_and_google_repositories(self):
        settings = CLEAN["shellx-android/settings.gradle.kts"]
        for text in ('repositories { maven("https://jitpack.io") }\n',
                     'repositories { maven { url = uri("https://jitpack.io") } }\n',
                     "repositories { mavenLocal() }\n", "repositories { jcenter() }\n", "repositories { ivy { } }\n"):
            with self.subTest(text=text):
                self.assertFails(self.tree({"shellx-android/settings.gradle.kts": settings + text}),
                                 "settings.gradle.kts")
        self.assertFails(self.tree({"shellx-android/app/build.gradle.kts": "repositories { gradlePluginPortal() }\n"}),
                         "gradlePluginPortal")

    def test_groovy_scripts_and_vendored_binaries_fail(self):
        self.assertFails(self.tree({"shellx-android/extra.gradle": "apply plugin: 'x'\n"}), "shellx-android/extra.gradle")
        self.assertFails(self.tree({"shellx-android/app/libs/vendor.jar": "PK\n"}), "shellx-android/app/libs/vendor.jar")
        self.assertFails(self.tree({"shellx-link/kotlin/link-core/libs/native.so": "ELF\n"}), "native.so")

    def test_the_upstream_company_name_fails(self):
        self.assertFails(self.tree({"shellx-android/README.md": f"Made by {COMPANY}.\n"}), "shellx-android/README.md")
        self.assertFails(self.tree({"shellx-link/kotlin/README.md": f"see {COMPANY.lower()}-ai\n"}),
                         "shellx-link/kotlin/README.md")
        self.assertPasses(self.tree({"shellx-android/Notes.kt": f"fun test{COMPANY}NameFails() {{}}\n"}))

    def test_symlinks_fail(self):
        root = self.tree()
        os.symlink("../../Sources", root / "shellx-android/app/src-link")
        self.assertFails(root, "shellx-android/app/src-link")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the tests to see them fail**

  Run: `python3 -m unittest discover -s shellx-android/scripts/tests -p 'test_check_android_license.py' -v`

  Expected: FAIL. Every test fails, because the script does not exist (exit code 127).

- [ ] **Step 3: Commit the failing tests**

  ```bash
  git add shellx-android/scripts/tests/test_check_android_license.py
  git commit -m "test(shellx-android): the Android licence boundary"
  ```

- [ ] **Step 4: Implement the check**

  `scripts/shellx/check-android-license.sh` is bash 3.2, in the style of `check-ios-license.sh`:
  - It starts with a header comment that lists the rules below.
  - It takes `--root` and `-h`.
  - It runs `python3 -I "$SCRIPT_DIR/check_android_license.py" --root "$ROOT"`.
  - It runs `bash "$SCRIPT_DIR/check-link-license.sh"`. If that fails, it prints the link check's output and `violation: shellx-link: scripts/shellx/check-link-license.sh failed`.
  - It prints `check-android-license: ok` only when both passed.

  `scripts/shellx/check_android_license.py` uses the standard library only and Python 3.9 syntax.
  - **Trees:** `shellx-android/` and `shellx-link/kotlin/`. Skip the `build/`, `.gradle/`, `.kotlin/`, `.idea/` and `__pycache__/` folders.
  - **Allowed path roots:** `shellx-android/`, `shellx-link/kotlin/`, `shellx-link/vectors/` and `shellx-link/spec/`.
  - It reports every violation, sorted by path.

  **Rules:**
  1. **Dependencies.** Every `gradle.lockfile` line of the form `group:artifact:version=conf,…` needs a matching allowlist entry.
     - The scope is `ship` when any of its configurations has no `test` or `Test` in its name; otherwise `test`.
     - The most specific entry decides: an exact `group:artifact`, then `group:*`, then the longest `prefix.*:*`.
     - A `test` entry does not allow a `ship` use. Message: `<group:artifact:version> (ship) is allowed on test classpaths only; move its allowlist line to ship`.
     - When no entry matches, the message is `<group:artifact:version> (<scope>) is not on scripts/shellx/android-license-allowlist.txt`.
  2. **Lockfile coverage.** Every `build.gradle.kts` below the two trees, other than the two build roots (`shellx-android/build.gradle.kts` and `shellx-link/kotlin/build.gradle.kts`), needs a `gradle.lockfile` next to it. That lockfile must name `releaseRuntimeClasspath` or `runtimeClasspath` on some line, the `empty=` line included.
  3. **Allowlist.** Each line is `<group>:<artifact> <scope> <licence> [# note]`.
     - The scope is `ship` or `test`.
     - Each `<group>:<artifact>` key is on one line only. A second line with the same key, in any scope, is a violation that names the key: `<key> is listed twice (lines <a> and <b>)`.
     - Licences allowed for `ship`: `Apache-2.0`, `MIT`, `BSD-2-Clause`, `BSD-3-Clause`, `Bouncy-Castle`, `Google-SDK`. `test` also allows `EPL-1.0`, `EPL-2.0`, `ICU` and `CDDL-1.1`.
     - A licence containing `GPL` (any case) is always a violation.
     - `*` is allowed only in the exact entries `androidx.*:*`, `org.jetbrains.kotlin:*` and `org.jetbrains.kotlinx:*`.
     - The groups `com.google.android.gms`, `com.google.firebase`, `com.google.android.datatransport`, `com.google.android.play` and `com.google.android.libraries.identity.googleid` must name an exact artifact. `Google-SDK` is allowed only for those groups.
  4. **Kotlin DSL reading** (used by rules 5 and 6).
     - Blank out `//` comments and `/* … */` comments (they may nest).
     - String literals are `"…"` (with backslash escapes) and `"""…"""`.
     - A literal is *plain* when it is a `"…"` with no `$` and no backslash.
     - Only `*.gradle.kts` files are read. Any `*.gradle` file is a violation (`Groovy build scripts are not allowed`).
  5. **Repositories.**
     - The code matches `\b(maven|mavenLocal|jcenter|ivy|flatDir)\s*[({]`: violation.
     - `gradlePluginPortal(` appears outside a file named `settings.gradle.kts`: violation.
  6. **Paths.**
     - Look at every literal inside the parentheses of a call to `includeBuild`, `file`, `files`, `fileTree`, `File`, `srcDir`, `srcDirs` or `dir`. Match the parentheses in the code, nesting included.
     - A literal that is not plain is a violation: `<call>(…) path is not a plain string literal`.
     - A plain literal that starts with `/` or `~` is a violation: `<call>("<literal>") is absolute`.
     - Otherwise, resolve it against the folder of the Gradle file with `normpath`. A result outside the allowed roots is a violation: `<call>("<literal>") points outside shellx-android/, shellx-link/kotlin/, shellx-link/vectors/ and shellx-link/spec/`.
  7. **Binaries.** Any `.jar`, `.aar` or `.so` file other than `gradle/wrapper/gradle-wrapper.jar` is a violation.
  8. **Company name.** A file whose first 8 KiB has no NUL byte, and whose text matches `(?i)(?<![A-Za-z0-9_])manaflow(?![A-Za-z0-9_])`, is a violation (`names the upstream company`).
  9. **Symlinks.** Every symlink, dangling or not, is a violation.

  Create `scripts/shellx/android-license-allowlist.txt`:
  ```
  # Dependencies the ShellX Android app (shellx-android/) and ShellX Link for Kotlin (shellx-link/kotlin/) may
  # resolve. scripts/shellx/check-android-license.sh checks every gradle.lockfile against this list.
  #
  # Format: <group>:<artifact>  <scope>  <licence>  [# note]
  #   scope    ship: allowed in the app (release and debug runtime classpaths) and in tests
  #            test: allowed only on test runtime classpaths
  #   licence  ship: Apache-2.0, MIT, BSD-2-Clause, BSD-3-Clause, Bouncy-Castle, Google-SDK
  #            test: also EPL-1.0, EPL-2.0, ICU, CDDL-1.1
  # Never GPL, LGPL or AGPL. Only the three wildcard lines below use "*". Google SDKs (com.google.android.gms,
  # com.google.firebase, com.google.android.datatransport, com.google.android.play,
  # com.google.android.libraries.identity.googleid) are always listed by name.
  # Add a line only after reading the artifact's POM licence; keep the lines sorted.
  # Each group:artifact is listed once. A test entry whose artifact starts to ship moves to ship, never both.

  androidx.*:*                 ship  Apache-2.0
  org.jetbrains.kotlin:*       ship  Apache-2.0
  org.jetbrains.kotlinx:*      ship  Apache-2.0
  ```

- [ ] **Step 5: Run the tests and the check**

  Run:
  ```bash
  python3 -m unittest discover -s shellx-android/scripts/tests -v
  /usr/bin/python3 -m unittest discover -s shellx-android/scripts/tests
  bash scripts/shellx/check-android-license.sh
  bash scripts/shellx/check-ios-license.sh | tail -1
  ```

  Expected:
  - `Ran 34 tests` and `OK`, twice (17 import tests and 17 licence tests);
  - `check-android-license: ok`;
  - `check-ios-license: ok`.

- [ ] **Step 6: The allowlist procedure**

  Tasks 4–8 use this procedure; it is written here once. For each `violation: …: <g>:<a>:<v> (<scope>) is not on …` line:

  1. Read the licence from the POM:
     ```bash
     lic() { p="$(echo "$1" | tr . /)/$2/$3/$2-$3.pom"; for b in https://repo1.maven.org/maven2 https://dl.google.com/dl/android/maven2; do curl -fsS "$b/$p" 2>/dev/null | sed -n '/<licenses>/,/<\/licenses>/p;/<parent>/,/<\/parent>/p' && return; done; }
     lic <g> <a> <v>
     ```
     If the POM has no `<licenses>`, run `lic` on its `<parent>` coordinates.
  2. Map the licence name to an identifier:

     | POM licence name | Identifier |
     | --- | --- |
     | Apache 2.0 (any wording) | `Apache-2.0` |
     | MIT | `MIT` |
     | BSD 3-clause or "New BSD" | `BSD-3-Clause` |
     | BSD 2-clause or "Simplified BSD" | `BSD-2-Clause` |
     | Bouncy Castle Licence | `Bouncy-Castle` |
     | Eclipse Public License 1.0 | `EPL-1.0` |
     | Eclipse Public License 2.0 | `EPL-2.0` |
     | Unicode/ICU, or `Unicode-3.0` (Robolectric's `com.ibm.icu:icu4j`) | `ICU` |
     | "CDDL + GPLv2 with classpath exception" | `CDDL-1.1` (the elected licence) |
     | Android Software Development Kit License | `Google-SDK` |
     | Play Core Software Development Kit Terms of Service (`com.google.android.play:*`, Play In-App Updates) | `Google-SDK` |

  3. If the violation says `is allowed on test classpaths only`, the artefact now ships. Change the scope of its existing line from `test` to `ship`, and do not add a second line. Never list the same `group:artifact` twice, in any scope: the check reports a duplicate as `listed twice`.
  4. Otherwise, add `<g>:<a>  <scope>  <identifier>  # <POM licence name>` in sorted position. The scope comes from the violation line.
  5. If the identifier is not allowed for the scope (for a moved line: not allowed for `ship`), mentions GPL, or the POM gives no licence, do not add or move the line. Stop and report the artefact and its licence to the user.

- [ ] **Step 7: Commit the implementation**

  ```bash
  git add scripts/shellx/check-android-license.sh scripts/shellx/check_android_license.py scripts/shellx/android-license-allowlist.txt
  git commit -m "feat(shellx-android): check the Android licence boundary"
  ```

---

### Task 4: Create the ShellX Link for Kotlin build (empty modules)

**Files:**
- Create: `shellx-link/kotlin/settings.gradle.kts`, `build.gradle.kts`, `gradle.properties`, `gradle/libs.versions.toml`, `.gitignore`, `README.md`
- Create: `shellx-link/kotlin/gradlew`, `gradlew.bat`, `gradle/wrapper/gradle-wrapper.jar`, `gradle/wrapper/gradle-wrapper.properties`
- Create: `shellx-link/kotlin/link-core/build.gradle.kts`, `link-core/gradle.lockfile`
- Create: `shellx-link/kotlin/link-account/build.gradle.kts`, `link-account/gradle.lockfile`
- Modify: `shellx-link/README.md` (one pointer line)
- Modify: `scripts/shellx/android-license-allowlist.txt`
- Test: `shellx-link/kotlin/link-core/src/test/kotlin/com/shellx/link/core/LinkCoreLayoutTest.kt`
- Test: `shellx-link/kotlin/link-account/src/test/kotlin/com/shellx/link/account/LinkAccountLayoutTest.kt`

**Interfaces:**
- Produces:
  - the included build named `shellx-link-kotlin`;
  - the modules `:link-core` and `:link-account`, with Maven group `com.shellx.link`. Their coordinates are `com.shellx.link:link-core` and `com.shellx.link:link-account`. `link-account` has `api(project(":link-core"))`;
  - the catalog keys `kotlin` and `junit` (JUnit 5 BOM). These must equal the same keys in `shellx-android/gradle/libs.versions.toml`;
  - the test working directory is the module folder, so `../../vectors/` and `../../spec/vectors/` resolve (contracts §5).

- [ ] **Step 1: Write the failing tests**

  ```kotlin
  // shellx-link/kotlin/link-core/src/test/kotlin/com/shellx/link/core/LinkCoreLayoutTest.kt
  package com.shellx.link.core

  import java.io.File
  import org.junit.jupiter.api.Assertions.assertTrue
  import org.junit.jupiter.api.Test
  import org.junit.jupiter.api.assertThrows

  class LinkCoreLayoutTest {
      @Test
      fun sharedVectorsAreReachableFromTheModuleDirectory() {
          assertTrue(File("../../vectors/noise_xx.json").isFile)
          assertTrue(File("../../spec/vectors/messages.json").isFile)
      }

      @Test
      fun androidIsNotOnTheClasspath() {
          assertThrows<ClassNotFoundException> { Class.forName("android.content.Context") }
      }
  }
  ```

  ```kotlin
  // shellx-link/kotlin/link-account/src/test/kotlin/com/shellx/link/account/LinkAccountLayoutTest.kt
  package com.shellx.link.account

  import java.io.File
  import org.junit.jupiter.api.Assertions.assertTrue
  import org.junit.jupiter.api.Test

  class LinkAccountLayoutTest {
      @Test
      fun pairingVectorsAreReachableFromTheModuleDirectory() {
          assertTrue(File("../../spec/vectors/pairing.json").isFile)
      }
  }
  ```

- [ ] **Step 2: Confirm the build is missing**

  Run: `test -x shellx-link/kotlin/gradlew || echo "no build yet"`

  Expected: `no build yet`. This is the red state.

- [ ] **Step 3: Look up the versions**

  Use `latest` from Task 0 Step 4.
  - **Kotlin:** `latest https://repo1.maven.org/maven2/org/jetbrains/kotlin/kotlin-gradle-plugin/maven-metadata.xml`.
  - **JUnit 5:** `latest https://repo1.maven.org/maven2/org/junit/junit-bom/maven-metadata.xml 5`. Stay on 5.x.
  - **Gradle:** take the newest stable release with the same major version as AGP's minimum Gradle:
    ```bash
    curl -fsS https://services.gradle.org/versions/all | python3 -c 'import json,sys; m=sys.argv[1]; v=[x["version"] for x in json.load(sys.stdin) if x["version"].split(".")[0]==m and not (x["snapshot"] or x["nightly"] or x["releaseNightly"] or x["broken"] or x["rcFor"] or x["milestoneFor"])]; print(sorted(v,key=lambda s:[int(p) for p in s.split(".")])[-1])' <AGP's minimum Gradle major>
    ```
  - **Gradle checksum:** `curl -fsS https://services.gradle.org/distributions/gradle-<GRADLE>-bin.zip.sha256`.

- [ ] **Step 4: Write the build files**

  `shellx-link/kotlin/settings.gradle.kts`:
  ```kotlin
  // ShellX Link for Kotlin/JVM (MIT License, see ../LICENSE). Included by shellx-android/.
  pluginManagement {
      repositories {
          mavenCentral()
          gradlePluginPortal()
      }
  }
  dependencyResolutionManagement {
      repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
      repositories {
          mavenCentral()
      }
  }
  rootProject.name = "shellx-link-kotlin"
  include(":link-core", ":link-account")
  ```

  `shellx-link/kotlin/gradle/libs.versions.toml`:
  ```toml
  [versions]
  kotlin = "<newest stable Kotlin>"
  junit = "<newest 5.x junit-bom>"

  [libraries]
  junit-bom = { module = "org.junit:junit-bom", version.ref = "junit" }
  junit-jupiter = { module = "org.junit.jupiter:junit-jupiter" }
  junit-platform-launcher = { module = "org.junit.platform:junit-platform-launcher" }

  [plugins]
  kotlin-jvm = { id = "org.jetbrains.kotlin.jvm", version.ref = "kotlin" }
  ```

  The remaining files:
  - `shellx-link/kotlin/build.gradle.kts` holds `plugins { alias(libs.plugins.kotlin.jvm) apply false }` under a comment line `// MIT License, see ../LICENSE.`
  - `shellx-link/kotlin/gradle.properties` holds `kotlin.code.style=official`.
  - `shellx-link/kotlin/.gitignore` holds one entry per line: `.gradle/`, `.kotlin/`, `build/`, `local.properties`, `.idea/`, `*.iml`.

  `link-core/build.gradle.kts` and `link-account/build.gradle.kts` hold exactly the following and nothing else:
  - plugin `alias(libs.plugins.kotlin.jvm)`, and `group = "com.shellx.link"`;
  - `java { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }` and `kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_17) } }`;
  - dependencies: `testImplementation(platform(libs.junit.bom))`, `testImplementation(libs.junit.jupiter)`, `testRuntimeOnly(libs.junit.platform.launcher)`. `link-account` also has `api(project(":link-core"))`;
  - `tasks.test { useJUnitPlatform() }`;
  - `tasks.withType<Test>().configureEach { testLogging { events("passed", "skipped", "failed"); exceptionFormat = TestExceptionFormat.FULL } }`;
  - `configurations.configureEach { if (name == "runtimeClasspath" || name.endsWith("RuntimeClasspath")) resolutionStrategy.activateDependencyLocking() }`.

  The files need `import org.jetbrains.kotlin.gradle.dsl.JvmTarget` and `import org.gradle.api.tasks.testing.logging.TestExceptionFormat` at the top.

- [ ] **Step 5: Generate the wrapper**

  Run:
  ```bash
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  BOOT_GRADLE="$(ls -d "$HOME"/.gradle/wrapper/dists/gradle-*-bin/*/gradle-*/bin/gradle | sort -V | tail -1)"
  (cd shellx-link/kotlin && "$BOOT_GRADLE" wrapper --gradle-version <GRADLE> --distribution-type bin --gradle-distribution-sha256-sum <SHA256>)
  ```

  Expected: `BUILD SUCCESSFUL`. The four wrapper files exist, and `gradle-wrapper.properties` has `distributionSha256Sum=<SHA256>`.

- [ ] **Step 6: Run the tests to see them pass**

  Run:
  ```bash
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk"
  shellx-link/kotlin/gradlew -p shellx-link/kotlin test --console=plain
  ```

  Expected: three `… PASSED` lines and `BUILD SUCCESSFUL`.

- [ ] **Step 7: Lock the dependencies and fill the allowlist**

  Run:
  ```bash
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk"
  shellx-link/kotlin/gradlew -p shellx-link/kotlin :link-core:dependencies :link-account:dependencies --write-locks -q >/dev/null
  bash scripts/shellx/check-android-license.sh
  ```

  Expected: both lockfiles exist. The check lists the JUnit 5 artefacts, `org.opentest4j:opentest4j`, `org.apiguardian:apiguardian-api` and `org.jetbrains:annotations` as not on the list.

  Add them with the allowlist procedure (Task 3 Step 6), then rerun the check. Expected: `check-android-license: ok`.

- [ ] **Step 8: Write the READMEs**

  `shellx-link/kotlin/README.md`:
  ```markdown
  # ShellX Link for Kotlin

  The Kotlin/JVM port of ShellX Link for the Android app: plain JVM libraries with no Android dependency. It is MIT
  licensed like the Swift package (see [../LICENSE](../LICENSE)). It must not depend on, link to or copy code from
  the GPL parts of the repository (`Sources/`, `ios/`, `Packages/`, `cmux-tui/`, `shellx-core/`).
  `scripts/shellx/check-android-license.sh` checks its Gradle files, dependencies and files.

  | Module | Package | What |
  | --- | --- | --- |
  | `link-core` | `com.shellx.link.core` | frames, Noise, relay control and the Link session (plan 3B) |
  | `link-account` | `com.shellx.link.account` | the relay's HTTP API (plan 3B) |

  Tests run on the JVM with JUnit 5. They read the shared vectors from `../../vectors/` and `../../spec/vectors/`,
  relative to each module folder: the same files the Swift tests read.

      shellx-android/scripts/dev.sh test link

  The Android build includes this one with `includeBuild("../shellx-link/kotlin")` and depends on
  `com.shellx.link:link-core` and `com.shellx.link:link-account`. After a dependency change, run
  `shellx-android/scripts/dev.sh lock` and update `scripts/shellx/android-license-allowlist.txt`.
  ```

  In `shellx-link/README.md`, add this line after the paragraph that ends "`scripts/shellx/check-link-license.sh` enforces the boundary.":
  ```
  The Kotlin/JVM port for the Android app lives in [`kotlin/`](kotlin/README.md), under the same MIT licence.
  ```

- [ ] **Step 9: Commit**

  ```bash
  git add shellx-link/kotlin shellx-link/README.md scripts/shellx/android-license-allowlist.txt
  git status --short shellx-link/kotlin | grep -v '^A' || true   # expect no output: build/, .gradle/ and .kotlin/ stay ignored
  git commit -m "build(shellx-link): Kotlin/JVM build with empty link-core and link-account"
  ```

---

### Task 5: Create the Android build with `:core`, and `dev.sh`

**Files:**
- Create: `shellx-android/settings.gradle.kts`, `build.gradle.kts`, `gradle.properties`, `gradle/libs.versions.toml`, `version.properties`, `.gitignore`, `LICENSE`
- Create: `shellx-android/gradlew`, `gradlew.bat`, `gradle/wrapper/gradle-wrapper.jar`, `gradle/wrapper/gradle-wrapper.properties`
- Create: `shellx-android/core/build.gradle.kts`, `core/gradle.lockfile`
- Create: `shellx-android/scripts/dev.sh`
- Modify: `scripts/shellx/android-license-allowlist.txt`
- Test: `shellx-android/core/src/test/kotlin/com/shellx/core/CoreIsPureJvmTest.kt`

**Interfaces:**
- Consumes: Task 4's catalog keys `kotlin` and `junit`, and the coordinates `com.shellx.link:link-core` and `com.shellx.link:link-account`. Also Task 2's `import-strings.py --check` and Task 3's licence check.
- Produces:
  - Gradle root project `shellx-android`, which includes the build `shellx-link-kotlin` and the module `:core` (package `com.shellx.core`);
  - catalog aliases `libs.shellx.link.core` and `libs.shellx.link.account`;
  - `dev.sh` with the variables `ANDROID_DIR`, `REPO_ROOT`, `LINK_DIR`, `ADB`, `DEBUG_APP_ID=com.shellx.dev`, `RELEASE_APP_ID=com.shellx.prod`, `MAIN_ACTIVITY=com.shellx.app.MainActivity`, `SERIAL_FILE="$HOME/.config/shellx/android-serial"`;
  - `dev.sh` functions `die`, `note`, `usage`, `gradle_android <args…>`, `gradle_link <args…>`, `run_checks`, `cmd_test`, `cmd_lock`. Later tasks add the `cmd_*` functions their usage lines name.

- [ ] **Step 1: Write the failing test**

  ```kotlin
  // shellx-android/core/src/test/kotlin/com/shellx/core/CoreIsPureJvmTest.kt
  package com.shellx.core

  import org.junit.jupiter.api.Test
  import org.junit.jupiter.api.assertThrows

  class CoreIsPureJvmTest {
      @Test
      fun androidIsNotOnTheClasspath() {
          assertThrows<ClassNotFoundException> { Class.forName("android.content.Context") }
      }
  }
  ```

  Run: `test -x shellx-android/gradlew || echo "no build yet"`

  Expected: `no build yet`.

- [ ] **Step 2: Write the build files**

  `shellx-android/settings.gradle.kts`:
  ```kotlin
  // The ShellX Android app (closed source, see LICENSE). Includes ShellX Link for Kotlin (MIT).
  pluginManagement {
      repositories {
          google()
          mavenCentral()
          gradlePluginPortal()
      }
  }
  dependencyResolutionManagement {
      repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
      repositories {
          google()
          mavenCentral()
      }
  }
  rootProject.name = "shellx-android"
  includeBuild("../shellx-link/kotlin")
  include(":core")
  ```

  `shellx-android/gradle/libs.versions.toml` (Task 6 adds the Android entries):
  ```toml
  [versions]
  kotlin = "<same as shellx-link/kotlin>"
  junit = "<same as shellx-link/kotlin>"

  [libraries]
  junit-bom = { module = "org.junit:junit-bom", version.ref = "junit" }
  junit-jupiter = { module = "org.junit.jupiter:junit-jupiter" }
  junit-platform-launcher = { module = "org.junit.platform:junit-platform-launcher" }
  shellx-link-core = { module = "com.shellx.link:link-core" }
  shellx-link-account = { module = "com.shellx.link:link-account" }

  [plugins]
  kotlin-jvm = { id = "org.jetbrains.kotlin.jvm", version.ref = "kotlin" }
  ```

  The remaining files:
  - `shellx-android/build.gradle.kts`: `plugins { alias(libs.plugins.kotlin.jvm) apply false }`.
  - `shellx-android/core/build.gradle.kts`: the same settings as Task 4's module build files, with no `group` line. Its dependencies are `implementation(libs.shellx.link.core)`, `implementation(libs.shellx.link.account)` and the three JUnit lines.
  - `shellx-android/.gitignore`: one entry per line, namely `.gradle/`, `.kotlin/`, `build/`, `local.properties`, `.idea/`, `*.iml`, `captures/`, `.cxx/`, `*.jks`, `*.keystore`, `key.properties`.

  `shellx-android/gradle.properties`:
  ```properties
  # Gradle settings for the ShellX Android build. The memory limits come from ~/.gradle/gradle.properties on the
  # maintainer's Mac (16 GB RAM): do not set org.gradle.jvmargs here.
  kotlin.code.style=official
  ```

  `shellx-android/version.properties`:
  ```properties
  # The version of the ShellX Android app. release/mobile/android.sh (plan 3H) reads both values.
  # Raise VERSION_CODE before every Google Play upload. VERSION_NAME is the iPhone's marketing version.
  VERSION_NAME=1.0.0
  VERSION_CODE=100
  ```

  `shellx-android/LICENSE`:
  ```
  Copyright (c) 2026 ShellX. All rights reserved.

  This directory (shellx-android/) holds the source code of the ShellX Android app. It is
  proprietary software. It is not covered by the GNU General Public License, the
  Business Source License or any other licence that applies elsewhere in this
  repository. No permission is granted to use, copy, modify, merge, publish,
  distribute, sublicense or sell this code, in whole or in part, without the prior
  written permission of the copyright holder.

  The app is built only from this directory, the Kotlin library in shellx-link/kotlin/
  (MIT License, see shellx-link/LICENSE) and third-party libraries from Maven Central
  and Google's Maven repository that are listed by name in
  scripts/shellx/android-license-allowlist.txt. It contains no code from ios/,
  Packages/, Sources/, cmux-tui/ or shellx-core/; scripts/shellx/check-android-license.sh
  enforces this boundary.
  ```

- [ ] **Step 3: Generate the wrapper**

  Run the same `wrapper` command as Task 4 Step 5, with `cd shellx-android` and the same Gradle version and checksum.

  Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 4: Write `shellx-android/scripts/dev.sh`**

  Make it executable, with `#!/usr/bin/env bash` and `set -euo pipefail`. Its header comment is exactly the following; `usage` prints it, as in the iOS `dev.sh`:
  ```
  # Builds, installs and tests the ShellX Android app. Together with release/mobile/android.sh (plan 3H), this is
  # the only place that runs Gradle for shellx-android/ and shellx-link/kotlin/.
  #
  #   dev.sh test [link|core|app|screenshots|all]
  #       link: the JVM tests of shellx-link/kotlin; core: the :core tests; app: the :app unit tests of the debug
  #       and release variants (Robolectric); screenshots: the *RenderTest classes; all (the default): all of
  #       them, the script tests and build-release. Every test command first runs
  #       scripts/shellx/check-android-license.sh, scripts/import-strings.py --check and the version catalog check.
  #   dev.sh screenshots record <dir>
  #       Runs every *RenderTest class and writes <name>-<light|dark>-<en|vi>.png into <dir>.
  #   dev.sh emulator --api <26|36> [--headless]
  #       Creates (first time) and boots the private emulator "ShellX_Dev_API_<n>" from an installed system image,
  #       shutting the other one down, then installs and opens the debug app "ShellX Dev" on it.
  #   dev.sh device [--serial <id>]
  #       Installs and opens the debug app on a phone. Serial: --serial, then $SHELLX_ANDROID_SERIAL, then
  #       ~/.config/shellx/android-serial, then the only phone `adb devices` lists.
  #   dev.sh build-release
  #       Unsigned release build (R8 on), then checks app id com.shellx.prod, label "ShellX", the version in
  #       version.properties, the min and target SDK, the locale config, and that it is not debuggable.
  #   dev.sh lock
  #       Rewrites every gradle.lockfile after a dependency change. Then update
  #       scripts/shellx/android-license-allowlist.txt until check-android-license.sh passes.
  #   dev.sh clean
  #       Deletes the private emulators and the build/ folders of both builds.
  #
  # JAVA_HOME defaults to Android Studio's JDK and ANDROID_HOME to ~/Library/Android/sdk. The script never
  # downloads SDK packages (the user installs them with sdkmanager), never installs com.shellx.prod on a phone,
  # and keeps at most one ShellX emulator running.
  ```

  Behaviour in this task:
  - **Helpers**, as in `shellx-ios/scripts/dev.sh`: `die <message> [code]` prints `dev.sh: <message>` to stderr and exits with `code` (default 1); `note <message>` prints `==> <message>` to stderr. Every `==> …` line this plan expects comes from `note`.
  - **Environment.** `: "${JAVA_HOME:=/Applications/Android Studio.app/Contents/jbr/Contents/Home}"` and `: "${ANDROID_HOME:=$HOME/Library/Android/sdk}"`, both exported. If `"$JAVA_HOME/bin/java" -version` does not report version 17 or later, call `die "JDK 17 or newer needed (JAVA_HOME=$JAVA_HOME)"`.
  - **Gradle.** `gradle_android` runs `"$ANDROID_DIR/gradlew" -p "$ANDROID_DIR" --console=plain "$@"`. `gradle_link` runs the same for `LINK_DIR`.
  - **`run_checks`** runs three checks:
    - `note "licence boundary"`, then the licence script;
    - `note "strings"`, then `python3 "$ANDROID_DIR/scripts/import-strings.py" --check`;
    - `note "version catalogs"`, then compare the `kotlin = "…"` and `junit = "…"` lines of the two catalogs. On a match it prints `version catalogs agree: kotlin <v>, junit <v>`. On a mismatch, `run_checks` fails with `dev.sh: shellx-link/kotlin and shellx-android pin different <key> versions (<a> vs <b>)`.
  - **`cmd_test`.** It runs `run_checks` first. Then:
    - `link` → `gradle_link test`;
    - `core` → `gradle_android :core:test`;
    - `all` → `python3 -m unittest discover -s "$ANDROID_DIR/scripts/tests" -t "$ANDROID_DIR/scripts/tests"`, then link, then core;
    - `app` and `screenshots` → `die "test <x> comes with a later task"` (exit 2) for now.

    It ends with `==> test <which>: passed` or `==> test <which>: FAILED`, with the matching exit status.
  - **`cmd_lock`** runs `gradle_link :link-core:dependencies :link-account:dependencies --write-locks -q >/dev/null`, then `gradle_android :core:dependencies --write-locks -q >/dev/null`.
  - **Other commands.** `screenshots`, `emulator`, `device`, `build-release` and `clean` die with exit code 2 and the message `<command> comes with a later task`.
  - **Help.** `-h`, `--help` and `help` print the usage.

- [ ] **Step 5: Lock the dependencies, fill the allowlist and run the tests**

  Run:
  ```bash
  shellx-android/scripts/dev.sh lock
  bash scripts/shellx/check-android-license.sh   # add any missing entries with Task 3 Step 6, then rerun
  shellx-android/scripts/dev.sh test core
  shellx-android/scripts/dev.sh test all
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk"
  shellx-android/gradlew -p shellx-android :core:dependencies --configuration runtimeClasspath | grep -E 'com.shellx.link:link-(core|account)'
  ```

  Expected:
  - `CoreIsPureJvmTest > androidIsNotOnTheClasspath() PASSED` and `==> test core: passed`;
  - `test all` ends with `Ran 34 tests … OK` from the script tests, the three link tests passing, the core test passing, and `==> test all: passed`;
  - the `grep` prints two lines, each with `-> project` (the included build replaced the coordinates).

- [ ] **Step 6: Commit**

  ```bash
  git add shellx-android/settings.gradle.kts shellx-android/build.gradle.kts shellx-android/gradle.properties \
    shellx-android/gradle shellx-android/gradlew shellx-android/gradlew.bat shellx-android/version.properties \
    shellx-android/.gitignore shellx-android/LICENSE shellx-android/core shellx-android/scripts/dev.sh \
    scripts/shellx/android-license-allowlist.txt
  git commit -m "build(shellx-android): Gradle build with :core on ShellX Link, and dev.sh"
  ```

---

### Task 6: Add the `:app` module, with app ids and the version from `version.properties`

**Files:**
- Modify: `shellx-android/settings.gradle.kts` (`include(":core", ":app")`), `build.gradle.kts`, `gradle/libs.versions.toml`, `scripts/dev.sh`
- Modify: `scripts/shellx/android-license-allowlist.txt`, `docs/superpowers/ledgers/shellx-android-parity.md` (row A-4 → `done (3A)`)
- Create: `shellx-android/app/build.gradle.kts`, `app/proguard-rules.pro`, `app/gradle.lockfile`
- Create: `shellx-android/app/src/main/AndroidManifest.xml`, `app/src/main/res/xml/data_extraction_rules.xml`, `app/src/main/res/resources.properties`
- Create: `shellx-android/app/src/debug/res/values/strings_android.xml`
- Create: `shellx-android/app/src/main/kotlin/com/shellx/app/MainActivity.kt`
- Test: `shellx-android/app/src/test/kotlin/com/shellx/app/AppIdentityTest.kt`

**Interfaces:**
- Consumes: Task 2's `R.string.app_name` ("ShellX"), and Task 5's catalog and `dev.sh`.
- Produces:
  - `com.shellx.app.MainActivity : ComponentActivity`, the only activity and the launcher. Task 8 sets its content;
  - catalog keys `agp`, `androidCompileSdk`, `androidTargetSdk`, `androidMinSdk`, `composeBom`, `activityCompose`, `googleServices`, `junit4`, `robolectric`, `androidxTestCore`, `androidxTestExtJunit`;
  - plugin aliases `android-application`, `kotlin-compose`, `google-services`;
  - `dev.sh test app` and `dev.sh build-release`;
  - `BuildConfig` (enabled) in `com.shellx.app`.

- [ ] **Step 1: Confirm the SDK packages from Task 0 Step 6**

  Run the `--list_installed` command from Task 0 Step 6.

  Expected: 4 lines. If a package is missing, ask the user to finish Task 0 Step 6. Never let Gradle install it.

- [ ] **Step 2: Look up the versions and extend the catalog**

  Use `latest` from Task 0 Step 4 and add the newest stable version of each:
  - `agp`, the AGP version from Task 0 Step 4;
  - `composeBom`: `https://dl.google.com/dl/android/maven2/androidx/compose/compose-bom/maven-metadata.xml`;
  - `activityCompose`: `…/androidx/activity/activity-compose/maven-metadata.xml`;
  - `googleServices`: `…/com/google/gms/google-services/maven-metadata.xml`;
  - `androidxTestCore`: `…/androidx/test/core/maven-metadata.xml`;
  - `androidxTestExtJunit`: `…/androidx/test/ext/junit/maven-metadata.xml`;
  - `robolectric`: `https://repo1.maven.org/maven2/org/robolectric/robolectric/maven-metadata.xml`.

  Also set `junit4 = "4.13.2"`, `androidMinSdk = "26"`, and `androidCompileSdk = androidTargetSdk = "<API>"`. Then add:
  ```toml
  androidx-activity-compose = { module = "androidx.activity:activity-compose", version.ref = "activityCompose" }
  androidx-compose-bom = { module = "androidx.compose:compose-bom", version.ref = "composeBom" }
  androidx-compose-material3 = { module = "androidx.compose.material3:material3" }
  androidx-test-core = { module = "androidx.test:core", version.ref = "androidxTestCore" }
  androidx-test-ext-junit = { module = "androidx.test.ext:junit", version.ref = "androidxTestExtJunit" }
  junit4 = { module = "junit:junit", version.ref = "junit4" }
  robolectric = { module = "org.robolectric:robolectric", version.ref = "robolectric" }
  # [plugins]
  android-application = { id = "com.android.application", version.ref = "agp" }
  kotlin-compose = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }
  google-services = { id = "com.google.gms.google-services", version.ref = "googleServices" }
  ```

  In `shellx-android/build.gradle.kts`, add `alias(…) apply false` for each of the three new plugins.

  If AGP is older than 9.0, also add `kotlin-android = { id = "org.jetbrains.kotlin.android", version.ref = "kotlin" }` and apply it in `:app`. AGP 9 and later have built-in Kotlin and refuse that plugin.

- [ ] **Step 3: Write the `:app` skeleton with the release identity only**

  `shellx-android/app/build.gradle.kts` must have these settings:
  - plugins `alias(libs.plugins.android.application)` and `alias(libs.plugins.kotlin.compose)`;
  - `android`:
    - `namespace = "com.shellx.app"`;
    - `compileSdk = libs.versions.androidCompileSdk.get().toInt()`;
    - `defaultConfig { applicationId = "com.shellx.prod"; minSdk = …androidMinSdk…; targetSdk = …androidTargetSdk… }`, with **no** `versionCode` or `versionName` yet;
    - `buildTypes { release { isMinifyEnabled = true; isShrinkResources = true; proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro") } }`, with no signing config;
    - `buildFeatures { compose = true; buildConfig = true }`;
    - `compileOptions` source and target `JavaVersion.VERSION_17`;
    - `androidResources { generateLocaleConfig = true }`;
    - `testOptions { unitTests { isIncludeAndroidResources = true } }`;
    - `packaging { resources { excludes += "/META-INF/{AL2.0,LGPL2.1}" } }`;
  - `kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_17) } }`. If AGP reports that `compilerOptions` is not available there, delete the block: AGP's built-in Kotlin then takes the target from `compileOptions`;
  - dependencies:
    - `implementation(project(":core"))`, `implementation(platform(libs.androidx.compose.bom))`, `implementation(libs.androidx.compose.material3)`, `implementation(libs.androidx.activity.compose)`;
    - `testImplementation` of `libs.junit4`, `libs.robolectric`, `libs.androidx.test.core` and `libs.androidx.test.ext.junit`;
  - the same dependency locking rule as Task 4;
  - `tasks.withType<Test>().configureEach { maxHeapSize = "2g"; testLogging { events("passed", "skipped", "failed"); exceptionFormat = TestExceptionFormat.FULL } }`;
  - Firebase, applied only when both files exist (Task 10 adds them):
    ```kotlin
    if (file("src/debug/google-services.json").isFile && file("src/release/google-services.json").isFile) {
        apply(plugin = "com.google.gms.google-services")
    }
    ```

  `shellx-android/app/proguard-rules.pro`:
  ```
  # R8 rules for the ShellX Android app. AndroidX, Compose and Kotlin ship their own rules; add a rule here only
  # with a comment that names what it keeps and why.
  -keepattributes SourceFile,LineNumberTable
  -renamesourcefileattribute SourceFile
  ```

  `shellx-android/app/src/main/AndroidManifest.xml`. Task 7 sets the theme and Task 8 the icon:
  ```xml
  <?xml version="1.0" encoding="utf-8"?>
  <manifest xmlns:android="http://schemas.android.com/apk/res/android">
      <!-- Nothing is backed up or moved to a new phone: secrets and paired Macs stay on this device (S3 §7.3). -->
      <application
          android:allowBackup="false"
          android:dataExtractionRules="@xml/data_extraction_rules"
          android:label="@string/app_name"
          android:supportsRtl="true"
          android:theme="@android:style/Theme.Material.Light.NoActionBar">
          <activity
              android:name=".MainActivity"
              android:exported="true"
              android:windowSoftInputMode="adjustResize">
              <intent-filter>
                  <action android:name="android.intent.action.MAIN" />
                  <category android:name="android.intent.category.LAUNCHER" />
              </intent-filter>
          </activity>
      </application>
  </manifest>
  ```

  `app/src/main/res/xml/data_extraction_rules.xml`:
  - A `<data-extraction-rules>` element holding `<cloud-backup>` and `<device-transfer>`.
  - Each of the two holds `<exclude domain="…"/>` for `root`, `file`, `database`, `sharedpref` and `external`.

  `app/src/main/res/resources.properties` holds `unqualifiedResLocale=en`.

  `MainActivity.kt` in package `com.shellx.app`: a `ComponentActivity` whose `onCreate` calls `super.onCreate(savedInstanceState)`, then `enableEdgeToEdge()`, then `setContent { }` with empty content.

  In `settings.gradle.kts`, change the include line to `include(":core", ":app")`.

  In `dev.sh`:
  - `test app` → `gradle_android :app:testDebugUnitTest :app:testReleaseUnitTest`;
  - `test all` → add `test app` and `cmd_build_release`, after core;
  - `cmd_lock` → also lock `:app:dependencies`.

- [ ] **Step 4: Write the failing test**

  ```kotlin
  // shellx-android/app/src/test/kotlin/com/shellx/app/AppIdentityTest.kt
  package com.shellx.app

  import android.content.Context
  import androidx.test.core.app.ApplicationProvider
  import androidx.test.ext.junit.runners.AndroidJUnit4
  import java.io.File
  import java.util.Properties
  import org.junit.Assert.assertEquals
  import org.junit.Test
  import org.junit.runner.RunWith

  @RunWith(AndroidJUnit4::class)
  class AppIdentityTest {
      private val context: Context = ApplicationProvider.getApplicationContext()

      @Test
      fun identityMatchesTheBuildType() {
          if (BuildConfig.DEBUG) {
              assertEquals("com.shellx.dev", context.packageName)
              assertEquals("ShellX Dev", context.getString(R.string.app_name))
          } else {
              assertEquals("com.shellx.prod", context.packageName)
              assertEquals("ShellX", context.getString(R.string.app_name))
          }
      }

      @Test
      fun versionComesFromVersionProperties() {
          val version = Properties().apply { File("../version.properties").inputStream().use { load(it) } }
          val info = context.packageManager.getPackageInfo(context.packageName, 0)
          assertEquals(version.getProperty("VERSION_NAME"), info.versionName)
          assertEquals(version.getProperty("VERSION_CODE").toLong(), info.longVersionCode)
      }
  }
  ```

- [ ] **Step 5: Run it to see it fail**

  Run: `shellx-android/scripts/dev.sh lock && shellx-android/scripts/dev.sh test app`

  Expected:
  - `check-android-license.sh` lists the new artefacts. Add them with Task 3 Step 6 and rerun.
  - In the debug variant, `identityMatchesTheBuildType FAILED` with `expected:<com.shellx.dev> but was:<com.shellx.prod>`.
  - In both variants, `versionComesFromVersionProperties FAILED`.
  - `==> test app: FAILED`.

  If Robolectric reports `targetSdkVersion=<API> > maxSdkVersion=<N>`, create `shellx-android/app/src/test/resources/robolectric.properties` with `sdk=<N>` and rerun.

- [ ] **Step 6: Commit the failing test and the skeleton**

  ```bash
  git add shellx-android/settings.gradle.kts shellx-android/build.gradle.kts shellx-android/gradle/libs.versions.toml \
    shellx-android/scripts/dev.sh shellx-android/app scripts/shellx/android-license-allowlist.txt
  git commit -m "test(shellx-android): debug is ShellX Dev (com.shellx.dev), the version comes from version.properties"
  ```

- [ ] **Step 7: Implement the debug identity and the version**

  1. In `app/build.gradle.kts`, read `rootProject.file("version.properties")` with `java.util.Properties`. Call `error("version.properties: missing <KEY>")` when a key is absent. Set `defaultConfig.versionCode` from `VERSION_CODE` (as an Int) and `versionName` from `VERSION_NAME`.
  2. Set the debug application id with the variant API. Product flavors would add variants, and `applicationIdSuffix` cannot produce `com.shellx.dev`:
     ```kotlin
     androidComponents {
         onVariants(selector().withBuildType("debug")) { variant -> variant.applicationId.set("com.shellx.dev") }
     }
     ```
  3. Create `shellx-android/app/src/debug/res/values/strings_android.xml`:
     ```xml
     <?xml version="1.0" encoding="utf-8"?>
     <!-- The debug build's name: "ShellX Dev" installs next to the Google Play build "ShellX". -->
     <resources>
         <string name="app_name" translatable="false">ShellX Dev</string>
     </resources>
     ```
  4. If AGP fails with "android.useAndroidX property is not enabled", add `android.useAndroidX=true` to `gradle.properties`.

- [ ] **Step 8: Add `dev.sh build-release`**

  `cmd_build_release` works as follows:
  1. It runs `gradle_android :app:assembleRelease`. The APK is `$ANDROID_DIR/app/build/outputs/apk/release/app-release-unsigned.apk`.
  2. It sets `AAPT2="$ANDROID_HOME/build-tools/$(ls "$ANDROID_HOME/build-tools" | sort -V | tail -1)/aapt2"`.
  3. It reads `VC` and `VN` from `version.properties`, and `T` from the catalog's `androidTargetSdk`.
  4. It fails, naming the expected value, unless `"$AAPT2" dump badging <apk>` contains:
     - `package: name='com.shellx.prod' versionCode='$VC' versionName='$VN'`;
     - `minSdkVersion:'26'`;
     - `targetSdkVersion:'$T'`;
     - `application-label:'ShellX'`.
  5. It also fails when:
     - the badging contains `application-debuggable`;
     - `"$AAPT2" dump xmltree --file AndroidManifest.xml <apk>` lacks `localeConfig`;
     - `app/build/outputs/mapping/release/mapping.txt` is missing (R8 did not run).
  6. If either `app/src/{debug,release}/google-services.json` is missing, it prints `==> Firebase: not configured (no google-services.json); push stays off in this build`.
  7. On success it prints `==> release checks passed (com.shellx.prod $VN ($VC), target SDK $T)`.

- [ ] **Step 9: Run the tests and the release check**

  Run:
  ```bash
  shellx-android/scripts/dev.sh test app
  shellx-android/scripts/dev.sh build-release
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk"
  shellx-android/gradlew -p shellx-android :app:tasks --all | grep -c GoogleServices
  ```

  Expected:
  - four `… PASSED` lines (2 tests × 2 variants) and `==> test app: passed`;
  - the Firebase note, then `==> release checks passed (com.shellx.prod 1.0.0 (100), target SDK <API>)`;
  - `0`: the plugin is not applied until Task 10.

- [ ] **Step 10: Mark ledger row A-4 as done**

  In the ledger, set row `A-4` to `done (3A)`.

- [ ] **Step 11: Commit the implementation**

  ```bash
  git add shellx-android/app shellx-android/gradle.properties scripts/shellx/android-license-allowlist.txt \
    docs/superpowers/ledgers/shellx-android-parity.md
  git commit -m "feat(shellx-android): app module, ShellX Dev next to ShellX, version from version.properties"
  ```

---

### Task 7: Add the theme in the iPhone's colours

**Files:**
- Create: `shellx-android/app/src/main/kotlin/com/shellx/app/ui/theme/ShellXColors.kt`
- Create: `shellx-android/app/src/main/kotlin/com/shellx/app/ui/theme/ShellXTheme.kt`
- Create: `shellx-android/app/src/main/res/values/colors.xml`, `values-night/colors.xml`, `values/themes.xml`, `values-night/themes.xml`
- Modify: `shellx-android/app/src/main/AndroidManifest.xml` (`android:theme="@style/Theme.ShellX"`)
- Test: `shellx-android/app/src/test/kotlin/com/shellx/app/ui/theme/ShellXColorsTest.kt`
- Test: `shellx-android/app/src/test/kotlin/com/shellx/app/ui/theme/WindowColorsTest.kt`

**Interfaces:**
- Produces, in package `com.shellx.app.ui.theme`. Contracts §5 names `ShellXTheme` and `ShellXColors`; 3A creates them, and 3D owns later changes such as the Settings switch:
  - `@Immutable data class ShellXColors(background, surface, accent, onAccent, accentText, bubbleMine, statusDone, statusError, statusIdle, statusNeedsYou, statusRunning: Color)`, with `companion object { val Light: ShellXColors; val Dark: ShellXColors }`;
  - `internal fun shellXColorScheme(dark: Boolean): ColorScheme`;
  - `val LocalShellXColors: ProvidableCompositionLocal<ShellXColors>`, a `staticCompositionLocalOf` that defaults to `ShellXColors.Light`;
  - `@Composable fun ShellXTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit)`;
  - `object ShellXTheme { val colors: ShellXColors @Composable @ReadOnlyComposable get() }`;
  - `R.color.shellx_background` and `R.style.Theme_ShellX`.

  Token values. They come from `shellx-ios/ShellX/Assets.xcassets/*.colorset`, except `onAccent`, which comes from `ShellX/UI/Components/PrimaryButtonStyle.swift`:

  | Token | Light | Dark | Token | Light | Dark |
  | --- | --- | --- | --- | --- | --- |
  | background | #F2F2F7 | #0B0716 | statusDone | #16A34A | #4ADE80 |
  | surface | #FFFFFF | #17122A | statusError | #DC2626 | #F87171 |
  | accent | #60A5FA | #60A5FA | statusIdle | #6B7280 | #8B919C |
  | onAccent | #0B1220 | #0B1220 | statusNeedsYou | #2563EB | #60A5FA |
  | accentText | #2563EB | #60A5FA | statusRunning | #CA8A04 | #FACC15 |
  | bubbleMine | #DBEAFE | #24364F | | | |

  `shellXColorScheme(dark)` maps the Material 3 roles as follows (light / dark). The other values are iOS system colours:

  | Role | Light | Dark |
  | --- | --- | --- |
  | primary / onPrimary | accent / onAccent | accent / onAccent |
  | primaryContainer / onPrimaryContainer | bubbleMine / #000000 | bubbleMine / #FFFFFF |
  | inversePrimary | #60A5FA | #2563EB |
  | secondary, tertiary / onSecondary, onTertiary | accentText / #FFFFFF | accentText / #0B1220 |
  | secondaryContainer, tertiaryContainer / on… | bubbleMine / #000000 | bubbleMine / #FFFFFF |
  | background, surface, surfaceDim, surfaceTint | background | background |
  | onBackground, onSurface | #000000 | #FFFFFF |
  | surfaceVariant, surfaceBright, surfaceContainerLowest, …Low, surfaceContainer, …High, …Highest | surface | surface |
  | onSurfaceVariant | #993C3C43 | #99EBEBF5 |
  | inverseSurface / inverseOnSurface | #17122A / #FFFFFF | #F2F2F7 / #000000 |
  | error / onError | statusError / #FFFFFF | statusError / #0B0716 |
  | errorContainer / onErrorContainer | #FEE2E2 / #7F1D1D | #450A0A / #FECACA |
  | outline / outlineVariant | #C6C6C8 / #4A3C3C43 | #38383A / #99545458 |
  | scrim | #000000 | #000000 |

  If the Material 3 version's `lightColorScheme()` accepts the `*Fixed*` roles, set them the same in both modes: every `…Fixed` is #DBEAFE, every `…FixedDim` is #60A5FA, every `on…Fixed` is #0B1220, and every `on…FixedVariant` is #2563EB.

  Two further rules:
  - M3 `surface` is the screen colour (iPhone `Background`). Cards, sheets, dialogs, menus and fields sit on `surfaceContainer*` (iPhone `Surface`). Say this in a KDoc on `shellXColorScheme`.
  - Text in the accent colour (text buttons, links) must use `ShellXTheme.colors.accentText`, as the iPhone's `SecondaryButtonStyle` does. #60A5FA on white is only 2.5:1. Say this in a KDoc on `ShellXColors`.

- [ ] **Step 1: Write the failing tests**

  ```kotlin
  // shellx-android/app/src/test/kotlin/com/shellx/app/ui/theme/ShellXColorsTest.kt
  package com.shellx.app.ui.theme

  import androidx.compose.ui.graphics.Color
  import androidx.compose.ui.graphics.toArgb
  import org.junit.Assert.assertEquals
  import org.junit.Test

  class ShellXColorsTest {
      private fun assertArgb(what: String, expected: Long, actual: Color) =
          assertEquals(what, expected.toInt(), actual.toArgb())

      @Test
      fun lightTokensAreTheIPhoneColours() = with(ShellXColors.Light) {
          assertArgb("background", 0xFFF2F2F7, background); assertArgb("surface", 0xFFFFFFFF, surface)
          assertArgb("accent", 0xFF60A5FA, accent); assertArgb("onAccent", 0xFF0B1220, onAccent)
          assertArgb("accentText", 0xFF2563EB, accentText); assertArgb("bubbleMine", 0xFFDBEAFE, bubbleMine)
          assertArgb("statusDone", 0xFF16A34A, statusDone); assertArgb("statusError", 0xFFDC2626, statusError)
          assertArgb("statusIdle", 0xFF6B7280, statusIdle); assertArgb("statusNeedsYou", 0xFF2563EB, statusNeedsYou)
          assertArgb("statusRunning", 0xFFCA8A04, statusRunning)
      }

      @Test
      fun darkTokensAreTheIPhoneColours() = with(ShellXColors.Dark) {
          assertArgb("background", 0xFF0B0716, background); assertArgb("surface", 0xFF17122A, surface)
          assertArgb("accent", 0xFF60A5FA, accent); assertArgb("onAccent", 0xFF0B1220, onAccent)
          assertArgb("accentText", 0xFF60A5FA, accentText); assertArgb("bubbleMine", 0xFF24364F, bubbleMine)
          assertArgb("statusDone", 0xFF4ADE80, statusDone); assertArgb("statusError", 0xFFF87171, statusError)
          assertArgb("statusIdle", 0xFF8B919C, statusIdle); assertArgb("statusNeedsYou", 0xFF60A5FA, statusNeedsYou)
          assertArgb("statusRunning", 0xFFFACC15, statusRunning)
      }

      @Test
      fun materialRolesUseTheShellXColours() {
          for (dark in listOf(false, true)) {
              val c = if (dark) ShellXColors.Dark else ShellXColors.Light
              val s = shellXColorScheme(dark)
              assertEquals(c.accent, s.primary); assertEquals(c.onAccent, s.onPrimary)
              assertEquals(c.bubbleMine, s.primaryContainer); assertEquals(c.accentText, s.secondary)
              assertEquals(c.background, s.background); assertEquals(c.background, s.surface)
              assertEquals(c.background, s.surfaceTint); assertEquals(c.surface, s.surfaceContainer)
              assertEquals(c.surface, s.surfaceContainerLowest); assertEquals(c.surface, s.surfaceContainerHighest)
              assertEquals(c.statusError, s.error)
          }
          assertArgb("light onSurface", 0xFF000000, shellXColorScheme(false).onSurface)
          assertArgb("dark onSurface", 0xFFFFFFFF, shellXColorScheme(true).onSurface)
          assertArgb("light onSurfaceVariant", 0x993C3C43, shellXColorScheme(false).onSurfaceVariant)
          assertArgb("dark onSurfaceVariant", 0x99EBEBF5, shellXColorScheme(true).onSurfaceVariant)
          assertArgb("light outline", 0xFFC6C6C8, shellXColorScheme(false).outline)
      }
  }
  ```

  ```kotlin
  // shellx-android/app/src/test/kotlin/com/shellx/app/ui/theme/WindowColorsTest.kt
  package com.shellx.app.ui.theme

  import android.content.Context
  import androidx.compose.ui.graphics.toArgb
  import androidx.test.core.app.ApplicationProvider
  import androidx.test.ext.junit.runners.AndroidJUnit4
  import com.shellx.app.R
  import org.junit.Assert.assertEquals
  import org.junit.Test
  import org.junit.runner.RunWith
  import org.robolectric.annotation.Config

  /** The window behind Compose (and the Android 12+ splash) has the theme's background, so nothing flashes. */
  @RunWith(AndroidJUnit4::class)
  class WindowColorsTest {
      private val context: Context = ApplicationProvider.getApplicationContext()

      @Test
      fun lightWindowBackgroundIsTheShellXBackground() =
          assertEquals(ShellXColors.Light.background.toArgb(), context.getColor(R.color.shellx_background))

      @Test
      @Config(qualifiers = "night")
      fun darkWindowBackgroundIsTheShellXBackground() =
          assertEquals(ShellXColors.Dark.background.toArgb(), context.getColor(R.color.shellx_background))
  }
  ```

- [ ] **Step 2: Run the tests to see them fail**

  Run: `shellx-android/scripts/dev.sh test app`

  Expected: FAIL, with a compile error `Unresolved reference 'ShellXColors'` (and `'shellx_background'`).

- [ ] **Step 3: Commit the failing tests**

  ```bash
  git add shellx-android/app/src/test/kotlin/com/shellx/app/ui/theme
  git commit -m "test(shellx-android): the theme uses the iPhone's colours"
  ```

- [ ] **Step 4: Implement the theme**

  Write `ShellXColors.kt` and `ShellXTheme.kt` as given in **Interfaces**.

  `ShellXTheme` provides `LocalShellXColors` and wraps `MaterialTheme(colorScheme = shellXColorScheme(darkTheme), content = content)`. It uses no dynamic colour and the default typography.

  The XML resources:
  - `values/colors.xml` sets `<color name="shellx_background">#F2F2F7</color>`.
  - `values-night/colors.xml` sets `#0B0716`.
  - `values/themes.xml` defines `<style name="Theme.ShellX" parent="android:Theme.Material.Light.NoActionBar">` with the item `android:windowBackground` = `@color/shellx_background`.
  - `values-night/themes.xml` is the same with parent `android:Theme.Material.NoActionBar`.

  In the manifest, set `android:theme="@style/Theme.ShellX"`.

- [ ] **Step 5: Run the tests to see them pass**

  Run: `shellx-android/scripts/dev.sh test app`

  Expected: `ShellXColorsTest` (3 tests) passes in both variants, `WindowColorsTest` (2 tests) passes in both variants, `AppIdentityTest` still passes, and the run ends with `==> test app: passed`.

- [ ] **Step 6: Commit the implementation**

  ```bash
  git add shellx-android/app/src/main
  git commit -m "feat(shellx-android): ShellXTheme with the iPhone's colours, following the system's light or dark"
  ```

---

### Task 8: Add the launch screen, logo, app icon and render tests

**Files:**
- Create: `shellx-android/app/src/main/kotlin/com/shellx/app/ui/LaunchView.kt`
- Create: `shellx-android/app/src/main/res/drawable/shellx_logo.xml`, `ic_launcher_background.xml`, `ic_launcher_foreground.xml`, `ic_launcher_monochrome.xml`
- Create: `shellx-android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
- Modify: `MainActivity.kt`, `AndroidManifest.xml` (`android:icon="@mipmap/ic_launcher"`), `app/build.gradle.kts`, `gradle/libs.versions.toml`, `app/gradle.lockfile`, `scripts/dev.sh`
- Modify: `scripts/shellx/android-license-allowlist.txt`, `docs/superpowers/ledgers/shellx-android-parity.md` (rows 6.1-1 and A-5 → `done (3A)`)
- Test: `shellx-android/app/src/testDebug/kotlin/com/shellx/app/screenshots/ShellXSnapshots.kt` (test support)
- Test: `shellx-android/app/src/testDebug/kotlin/com/shellx/app/screenshots/LaunchViewRenderTest.kt`

**Interfaces:**
- Consumes: Task 7's `ShellXTheme`, and Task 2's `R.string.root_title`.
- Produces:
  - `@Composable fun LaunchView(modifier: Modifier = Modifier)` in `com.shellx.app.ui`;
  - `R.drawable.shellx_logo` and `R.mipmap.ic_launcher`;
  - render test support in `com.shellx.app.screenshots` (debug unit tests only):
    - `object ShellXSnapshots { const val DEVICE_QUALIFIERS = "w393dp-h852dp-xxhdpi"; fun capture(name: String, content: @Composable () -> Unit): List<Snapshot> }`;
    - `class Snapshot(val name: String, val theme: String, val language: String, val file: File, val width: Int, val height: Int, val argb: IntArray) { fun pixel(x: Int, y: Int): Int }`.

    `capture` renders `content` inside `ShellXTheme` for light-en, dark-en, light-vi and dark-vi, in that order. It writes `<name>-<light|dark>-<en|vi>.png` into the directory named by the system property `shellx.snapshot.dir`. 3D, 3E and 3G add their render tests as `…RenderTest` classes in this package.
  - `dev.sh test screenshots` and `dev.sh screenshots record <dir>`.

- [ ] **Step 1: Add the render test dependencies**

  1. Look up `roborazzi` with `latest https://repo1.maven.org/maven2/io/github/takahirom/roborazzi/roborazzi/maven-metadata.xml`.
  2. Add to the catalog:
     - `roborazzi = { module = "io.github.takahirom.roborazzi:roborazzi", version.ref = "roborazzi" }`;
     - `roborazzi-compose = { module = "io.github.takahirom.roborazzi:roborazzi-compose", version.ref = "roborazzi" }`;
     - `androidx-compose-ui-test-manifest = { module = "androidx.compose.ui:ui-test-manifest" }`.
  3. In `:app`, add `testDebugImplementation(libs.roborazzi)`, `testDebugImplementation(libs.roborazzi.compose)` and `debugImplementation(libs.androidx.compose.ui.test.manifest)`.
  4. Extend the `Test` configuration with:
     ```kotlin
     systemProperty("roborazzi.test.record", "true")
     systemProperty("shellx.snapshot.dir", providers.gradleProperty("shellx.snapshot.dir")
         .getOrElse(layout.buildDirectory.dir("shellx-snapshots").get().asFile.absolutePath))
     ```
  5. In `dev.sh`:
     - `test screenshots` → `gradle_android :app:testDebugUnitTest --tests 'com.shellx.app.screenshots.*'`;
     - `screenshots record <dir>` → `mkdir -p`, turn the folder into an absolute path, then run the same command with `-Pshellx.snapshot.dir="$dir" --rerun`, and finish with `note "screenshots written to $dir"`.

- [ ] **Step 2: Write the failing render test and its support**

  ```kotlin
  // shellx-android/app/src/testDebug/kotlin/com/shellx/app/screenshots/LaunchViewRenderTest.kt
  package com.shellx.app.screenshots

  import androidx.test.ext.junit.runners.AndroidJUnit4
  import com.shellx.app.ui.LaunchView
  import org.junit.Assert.assertEquals
  import org.junit.Assert.assertFalse
  import org.junit.Assert.assertTrue
  import org.junit.Test
  import org.junit.runner.RunWith
  import org.robolectric.RuntimeEnvironment
  import org.robolectric.annotation.Config
  import org.robolectric.annotation.GraphicsMode

  @RunWith(AndroidJUnit4::class)
  @GraphicsMode(GraphicsMode.Mode.NATIVE)
  @Config(qualifiers = ShellXSnapshots.DEVICE_QUALIFIERS)
  class LaunchViewRenderTest {
      @Test
      fun rendersInLightAndDarkInEnglishAndVietnamese() {
          val shots = ShellXSnapshots.capture("launch") { LaunchView() }

          assertEquals(listOf("light-en", "dark-en", "light-vi", "dark-vi"), shots.map { "${it.theme}-${it.language}" })
          val metrics = RuntimeEnvironment.getApplication().resources.displayMetrics
          for (shot in shots) {
              assertTrue(shot.file.isFile)
              assertEquals("launch-${shot.theme}-${shot.language}.png", shot.file.name)
              assertEquals(1179, shot.width) // 393 dp at xxhdpi: the iPhone 16's 1179 px
              assertEquals(metrics.heightPixels, shot.height)
          }
          val light = shots.first { it.theme == "light" && it.language == "en" }
          val dark = shots.first { it.theme == "dark" && it.language == "en" }
          assertEquals(0xFFF2F2F7.toInt(), light.pixel(10, 10))
          assertEquals(0xFF0B0716.toInt(), dark.pixel(10, 10))
          assertFalse(light.argb.contentEquals(dark.argb))
      }
  }
  ```

  `ShellXSnapshots.capture` works as follows:
  - It reads `System.getProperty("shellx.snapshot.dir")`. If the property is missing, it fails with `error("shellx.snapshot.dir is not set; run shellx-android/scripts/dev.sh test screenshots")`.
  - For each language (en, then vi) and each theme (light, then dark):
    1. it calls `RuntimeEnvironment.setQualifiers("+<language>-<night|notnight>")`;
    2. it renders with Roborazzi's `captureRoboImage(file.absolutePath) { ShellXTheme { content() } }`, from package `com.github.takahirom.roborazzi`;
    3. it reads the PNG back with `javax.imageio.ImageIO` and fills in `Snapshot` (`argb` from `getRGB(0, 0, w, h, null, 0, w)`).
  - `pixel(x, y)` returns `argb[y * width + x]`.

- [ ] **Step 3: Run it to see it fail**

  Run: `shellx-android/scripts/dev.sh lock && shellx-android/scripts/dev.sh test screenshots`

  Expected:
  - Add the new artefacts (Roborazzi, Dropbox `differ` and the like) with Task 3 Step 6.
  - Then FAIL with `Unresolved reference 'LaunchView'`.

- [ ] **Step 4: Commit the failing test**

  ```bash
  git add shellx-android/app/src/testDebug shellx-android/app/build.gradle.kts shellx-android/app/gradle.lockfile \
    shellx-android/gradle/libs.versions.toml shellx-android/scripts/dev.sh scripts/shellx/android-license-allowlist.txt
  git commit -m "test(shellx-android): the launch screen renders in light, dark, English and Vietnamese"
  ```

- [ ] **Step 5: Draw the logo and the app icon from `design/shellx-logo.svg`**

  Every element below comes from the SVG. Vector gradients use absolute coordinates, so each SVG `objectBoundingBox` gradient is already converted below. Colours are `#AARRGGBB`. Every stroke is `strokeLineCap="round" strokeLineJoin="round"` with no fill. The path data, in the logo's 512 coordinate units:

  | # | Element | `pathData` | Paint |
  | --- | --- | --- | --- |
  | 1 | background | `M114,0H398A114,114 0,0 1,512 114V398A114,114 0,0 1,398 512H114A114,114 0,0 1,0 398V114A114,114 0,0 1,114 0Z` | fill: linear (0,0)→(0,512), `#FF1C1438`→`#FF0B0716` |
  | 2 | glow | same as 1 | fill: radial, centre (215.04,235.52), radius 215.04, `#384AF2A1`→`#004AF2A1` |
  | 3 | border | `M114,2H398A112,112 0,0 1,510 114V398A112,112 0,0 1,398 510H114A112,112 0,0 1,2 398V114A112,112 0,0 1,114 2Z` | stroke `#17FFFFFF`, width 3 |
  | 4 | "<" | `M384,122L290,234L384,346` | stroke width 54, linear (384,122)→(290,346), `#FFFFFFFF`→`#FFCFC8EE` |
  | 5 | ">" | `M128,122L222,234L128,346` | stroke width 54, linear (128,122)→(222,346), `#FF7DF7BE`→`#FF2FD98A` |
  | 6 | cursor | `M308,398H376A8,8 0,0 1,384 406V416A8,8 0,0 1,376 424H308A8,8 0,0 1,300 416V406A8,8 0,0 1,308 398Z` | fill: linear (300,398)→(384,424), `#FF7DF7BE`→`#FF2FD98A` |

  A gradient is written inline. Element 4 as the example:
  ```xml
  <path android:pathData="M384,122L290,234L384,346" android:strokeWidth="54"
      android:strokeLineCap="round" android:strokeLineJoin="round">
      <aapt:attr name="android:strokeColor">
          <gradient android:type="linear" android:startX="384" android:startY="122" android:endX="290" android:endY="346"
              android:startColor="#FFFFFFFF" android:endColor="#FFCFC8EE" />
      </aapt:attr>
  </path>
  ```

  The radial gradient of element 2 uses `android:type="radial"`, `centerX`, `centerY` and `gradientRadius`. Every file declares `xmlns:aapt="http://schemas.android.com/aapt"`.

  The files:
  - **`drawable/shellx_logo.xml`:** `width`/`height` 96dp, viewport 512×512, elements 1–6.
  - **`drawable/ic_launcher_foreground.xml`:** 108dp, viewport 768×768, with `<group android:translateX="128" android:translateY="128">` around elements 4–6. This maps the logo's 512 box onto the 72 dp the launcher shows, so the glyphs stay inside the 66 dp safe circle.
  - **`drawable/ic_launcher_background.xml`:** 108dp, viewport 768×768. Path `M0,0H768V768H0Z` twice:
    - first a linear gradient from (0,128) to (0,640), `#FF1C1438`→`#FF0B0716`;
    - then a radial gradient with centre (343.04,363.52), radius 215.04, `#384AF2A1`→`#004AF2A1`.
  - **`drawable/ic_launcher_monochrome.xml`:** like the foreground, with solid `#FFFFFFFF` paint instead of the gradients.
  - **`mipmap-anydpi-v26/ic_launcher.xml`:** `<adaptive-icon>` with `<background android:drawable="@drawable/ic_launcher_background"/>`, `<foreground android:drawable="@drawable/ic_launcher_foreground"/>` and `<monochrome android:drawable="@drawable/ic_launcher_monochrome"/>`.

  In the manifest, set `android:icon="@mipmap/ic_launcher"` on `<application>`.

- [ ] **Step 6: Implement `LaunchView` and show it**

  `LaunchView` mirrors the iPhone's `LaunchView` in `ShellX/UI/RootView.swift`:
  - A `Box` with `modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).windowInsetsPadding(WindowInsets.safeDrawing)`, with its content centred.
  - Inside it, a `Column` with `Arrangement.spacedBy(16.dp)`, centred horizontally, holding:
    - `Image(painterResource(R.drawable.shellx_logo), contentDescription = null)`, sized `(96 * LocalDensity.current.fontScale).dp`;
    - `Text(stringResource(R.string.root_title))`, with style `MaterialTheme.typography.headlineLarge.copy(fontWeight = FontWeight.SemiBold)`, colour `onBackground` and `Modifier.semantics { heading() }`.

  In `MainActivity`, call `setContent { ShellXTheme { LaunchView() } }`.

- [ ] **Step 7: Run the tests to see them pass, then look at the images**

  Run:
  ```bash
  shellx-android/scripts/dev.sh test screenshots
  shellx-android/scripts/dev.sh test app
  SHOTS="$(mktemp -d)"; shellx-android/scripts/dev.sh screenshots record "$SHOTS"; ls "$SHOTS"
  rsvg-convert -w 288 -h 288 design/shellx-logo.svg -o "$SHOTS/logo-from-svg.png"
  ```

  Expected:
  - `LaunchViewRenderTest > rendersInLightAndDarkInEnglishAndVietnamese PASSED`, and `==> test screenshots: passed`;
  - `==> test app: passed`;
  - `launch-dark-en.png`, `launch-dark-vi.png`, `launch-light-en.png`, `launch-light-vi.png`, `logo-from-svg.png`.

  Open `launch-light-en.png`, `launch-dark-en.png` and `logo-from-svg.png`. The logo must match the SVG: two chevrons (lilac "<", mint ">"), the mint cursor, a dark rounded square and a faint glow. "ShellX" sits under it. The backgrounds are #F2F2F7 and #0B0716.

- [ ] **Step 8: Mark ledger rows 6.1-1 and A-5 as done**

  In the ledger, set rows `6.1-1` and `A-5` to `done (3A)`.

- [ ] **Step 9: Commit the implementation**

  ```bash
  git add shellx-android/app/src/main docs/superpowers/ledgers/shellx-android-parity.md
  git commit -m "feat(shellx-android): launch screen with the ShellX logo, adaptive app icon"
  ```

---

### Task 9: Add `dev.sh` emulator, device and clean, the README, and dogfood on emulators and the phone

**Files:**
- Modify: `shellx-android/scripts/dev.sh`
- Create: `shellx-android/README.md`
- Modify: `docs/superpowers/ledgers/shellx-android-parity.md` (the "Test devices" rows)

**Interfaces:**
- Consumes: the debug APK `app/build/outputs/apk/debug/app-debug.apk` and `MAIN_ACTIVITY`.
- Produces:
  - AVDs `ShellX_Dev_API_26` and `ShellX_Dev_API_36`, on ports 5580 and 5582. Their serials are `emulator-5580` and `emulator-5582`;
  - `cmd_emulator`, `cmd_device`, `cmd_clean`;
  - the variable `SHELLX_ANDROID_SERIAL` and the file `~/.config/shellx/android-serial`.

- [ ] **Step 1: Implement the three commands**

  Use `AVDMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager"` and `EMULATOR="$ANDROID_HOME/emulator/emulator"`. Let `build_and_open <serial>` be the helper both commands share:
  1. `gradle_android :app:assembleDebug`;
  2. `"$ADB" -s <serial> install -r <app-debug.apk>`;
  3. `"$ADB" -s <serial> shell am start -W -S -n "$DEBUG_APP_ID/$MAIN_ACTIVITY"`, which must print `Status: ok`.

  **`cmd_emulator --api <26|36> [--headless]`.** Any other API is refused.
  1. Pick the image tag: the first of `google_apis_playstore`, `google_apis` and `default` that has the folder `$ANDROID_HOME/system-images/android-<n>/<tag>/arm64-v8a`. If there is none, `die` with the `sdkmanager --install "system-images;android-<n>;google_apis;arm64-v8a"` line for the user.
  2. If `"$AVDMANAGER" list avd -c` lacks `ShellX_Dev_API_<n>`, create it with `echo no | "$AVDMANAGER" create avd -n ShellX_Dev_API_<n> -k "system-images;android-<n>;<tag>;arm64-v8a" -d pixel_5`. Then append `hw.ramSize=2048` and `hw.keyboard=yes` to `~/.android/avd/ShellX_Dev_API_<n>.avd/config.ini`.
  3. If `adb devices` lists the other ShellX serial, run `"$ADB" -s <other> emu kill` (only one runs at a time).
  4. If its own serial is not listed, start `"$EMULATOR" -avd ShellX_Dev_API_<n> -port <5580|5582> -no-snapshot-save -no-boot-anim`, with `-no-window` when `--headless` is given, in the background with `nohup`. Log to `$ANDROID_DIR/build/dev/emulator-<n>.log`.
  5. Run `"$ADB" -s <serial> wait-for-device`. Then poll `getprop sys.boot_completed` every 2 s until it prints `1`. After 300 s, `die`.
  6. Run `build_and_open`, then `note "ShellX Dev is running on <serial>"`, and print the serial on stdout.

  **`cmd_device [--serial <id>]`.**
  1. Take the serial from `--serial`, then `$SHELLX_ANDROID_SERIAL`, then the first line of `$SERIAL_FILE`, then the only `adb devices` line in state `device` whose serial does not start with `emulator-`.
  2. Refuse a serial that starts with `emulator-` (point to `dev.sh emulator`).
  3. If `"$ADB" -s <serial> get-state` does not print `device`, `die "phone <serial> is not ready: unlock it and allow USB debugging"`.
  4. Run `build_and_open`. This command only ever installs `com.shellx.dev`.

  **`cmd_clean`.**
  1. `emu kill` both ShellX serials, if they are running.
  2. `"$AVDMANAGER" delete avd -n` both AVDs, if they exist.
  3. `rm -rf` the `build/` folders of `shellx-android`, `app` and `core`, and of `shellx-link/kotlin`, `link-core` and `link-account`.

- [ ] **Step 2: Dogfood on the API 36 emulator, light and dark**

  Run:
  ```bash
  shellx-android/scripts/dev.sh emulator --api 36 --headless
  A="$HOME/Library/Android/sdk/platform-tools/adb"; SHOTS="$(mktemp -d)"
  "$A" -s emulator-5582 exec-out screencap -p > "$SHOTS/api36-light.png"
  "$A" -s emulator-5582 shell cmd uimode night yes
  "$A" -s emulator-5582 shell am start -W -S -n com.shellx.dev/com.shellx.app.MainActivity
  "$A" -s emulator-5582 exec-out screencap -p > "$SHOTS/api36-dark.png"
  "$A" -s emulator-5582 shell cmd uimode night no
  ```

  Expected:
  - `==> ShellX Dev is running on emulator-5582`, then `Status: ok`;
  - in `api36-light.png`, the logo and "ShellX" are centred on #F2F2F7, the background runs behind the status bar, and the status-bar icons are dark;
  - in `api36-dark.png`, the background is #0B0716 and the icons are light.

- [ ] **Step 3: Smoke-test R8 with the release build on the API 36 emulator only**

  Run:
  ```bash
  A="$HOME/Library/Android/sdk/platform-tools/adb"; SHOTS="$(mktemp -d)"
  shellx-android/scripts/dev.sh build-release
  BT="$HOME/Library/Android/sdk/build-tools/$(ls "$HOME/Library/Android/sdk/build-tools" | sort -V | tail -1)"
  "$BT/zipalign" -f -p 4 shellx-android/app/build/outputs/apk/release/app-release-unsigned.apk "$SHOTS/aligned.apk"
  "$BT/apksigner" sign --ks "$HOME/.android/debug.keystore" --ks-pass pass:android --key-pass pass:android \
    --ks-key-alias androiddebugkey --out "$SHOTS/release-debugsigned.apk" "$SHOTS/aligned.apk"
  "$A" -s emulator-5582 install -r "$SHOTS/release-debugsigned.apk"
  "$A" -s emulator-5582 shell am start -W -n com.shellx.prod/com.shellx.app.MainActivity
  "$A" -s emulator-5582 exec-out screencap -p > "$SHOTS/api36-release.png"
  "$A" -s emulator-5582 uninstall com.shellx.prod
  ```

  Expected:
  - `release checks passed`, then `Success`, then `Status: ok`;
  - `api36-release.png` shows the same launch screen, which proves R8 broke nothing;
  - `Success` for the uninstall.

  The debug keystore and its password `android` are the SDK's public defaults.

- [ ] **Step 4: Dogfood on the API 26 emulator**

  Run:
  ```bash
  A="$HOME/Library/Android/sdk/platform-tools/adb"; SHOTS="$(mktemp -d)"
  shellx-android/scripts/dev.sh emulator --api 26 --headless
  "$A" -s emulator-5580 exec-out screencap -p > "$SHOTS/api26-light.png"
  "$A" devices
  ```

  Expected:
  - `ShellX Dev is running on emulator-5580`;
  - the screenshot shows the same launch screen;
  - `emulator-5582` is gone from `adb devices`.

  On API 26 the navigation bar may show a dark scrim. That is expected for edge-to-edge on Android 8.0.

- [ ] **Step 5: USER — dogfood on the phone**

  Run: `shellx-android/scripts/dev.sh device`

  Expected: `Status: ok`.

  Then ask the user to check two things on the phone:
  - the home screen shows a "ShellX Dev" icon with the ShellX logo;
  - the app opens on the logo and "ShellX", with the colours following the phone's light or dark setting.

  If the phone is not connected, record the device row as `pending (USER)` and continue.

- [ ] **Step 6: Record the devices in the ledger**

  Update the "Test devices" rows:
  - `emulator ok (<date>)` for the two emulators;
  - the user's answer for the phone.

  If Task 1 could not read the phone, run the `getprop` commands from Task 1 Step 1 now.

- [ ] **Step 7: Write `shellx-android/README.md`**

  Model it on `shellx-ios/README.md`, and never write the upstream company name. It has these sections:
  1. **Title and summary.** The native ShellX Android app: Kotlin, Compose, Material 3, Android 8.0 (API 26) and later, phone layout. It pairs with a Mac running ShellX over ShellX Link.
  2. **Licence boundary.**
     - The app is closed source; link to `LICENSE`.
     - What it may use: its own code; `shellx-link/kotlin/` (MIT); libraries from Maven Central and Google Maven under Apache-2.0, MIT, BSD or the Bouncy Castle licence; and Google SDKs listed by name (Play services for FCM and `googleid`, Firebase, Play In-App Updates). Never GPL, LGPL or AGPL.
     - It takes nothing from `ios/`, `Packages/`, `Sources/`, `cmux-tui/` or `shellx-core/`. Translating from `shellx-ios/` is fine.
     - The rules of `scripts/shellx/check-android-license.sh`.
     - The lockfiles, and the workflow `dev.sh lock` → allowlist (Task 3 Step 6) → check.
  3. **Layout.** A table of `settings.gradle.kts` (includes `../shellx-link/kotlin`), `gradle/libs.versions.toml`, `version.properties`, `core/`, `app/` and `scripts/`.
  4. **Building and testing.**
     - Copy the `dev.sh` usage.
     - The JDK, and that the SDK packages are installed by the user with `sdkmanager`.
     - The emulators: names, APIs, one at a time, `--headless`.
     - The phone: how the serial is chosen, debug build only, never `com.shellx.prod`.
     - `build-release`.
     - `shellx-android/gradlew -p shellx-android --stop` frees the Gradle daemon's memory.
  5. **App ids.** "ShellX Dev" (`com.shellx.dev`, debug) and "ShellX" (`com.shellx.prod`, release) install side by side. Explain how: `androidComponents` and the debug resource overlay.
  6. **Strings.**
     - `import-strings.py` generates them; never edit `strings.xml`.
     - Overrides by name and Android-only strings go in `strings_android.xml` (en and vi). iPhone-only keys go in `scripts/strings-ios-only.txt`.
     - The iOS-wording guard, and the staleness check in every `dev.sh test`.
  7. **Theme and assets.** The iPhone's colours (`ShellXColors`), no dynamic colour, light or dark from the system for now. The logo and adaptive icon come from `design/shellx-logo.svg`, with the 768-unit viewport and the 128 offset.
  8. **Render tests.** Robolectric native graphics with Roborazzi, `test screenshots`, `screenshots record <dir>`, and the file names. No golden images are committed.
  9. **Firebase.** Per build type: `app/src/debug/google-services.json` and `app/src/release/google-services.json`. Both are committed, and the plugin applies only when both exist (Task 10).
  10. **Releasing.** `release/mobile/android.sh` (plan 3H). It is not written yet.

- [ ] **Step 8: Check and commit**

  Run: `bash scripts/shellx/check-android-license.sh && shellx-android/scripts/dev.sh --help | head -3`

  Expected: `check-android-license: ok`, then the first usage lines.

  ```bash
  git add shellx-android/scripts/dev.sh shellx-android/README.md docs/superpowers/ledgers/shellx-android-parity.md
  git commit -m "feat(shellx-android): dev.sh emulator, device and clean; README"
  ```

---

### Task 10: Add the Firebase config files (USER)

**Files:**
- Create: `shellx-android/app/src/debug/google-services.json`
- Create: `shellx-android/app/src/release/google-services.json`

**Interfaces:**
- Consumes: the conditional plugin from Task 6.
- Produces: Firebase configured for both app ids, for 3E (the FCM client).

- [ ] **Step 1: USER — add `com.shellx.dev` to Firebase and download the config**

  Print the debug SHA-1 for the user. Firebase Cloud Messaging does not need it; Google sign-in will:
  ```bash
  "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" -list -v -keystore "$HOME/.android/debug.keystore" -alias androiddebugkey -storepass android | grep 'SHA1:'
  ```

  Then ask the user to do the following:
  1. In the Firebase console, open project `shellxpro` › Add app › Android.
  2. Enter the package name `com.shellx.dev`, the nickname "ShellX Dev" and, optionally, that SHA-1.
  3. Download `google-services.json`. After the new app is added, the project file lists both `com.shellx.prod` and `com.shellx.dev`.
  4. Save that same file to both `<worktree>/shellx-android/app/src/debug/google-services.json` and `<worktree>/shellx-android/app/src/release/google-services.json`. Print the absolute paths for the user.

  Optionally, the user can restrict the project's Android API key, in Google Cloud › Credentials, to the two package names.

  **Meanwhile:** start Task 11 Step 2. If the user does not provide the files during this session, skip Steps 2–5, and write `Firebase config: pending (USER, Task 10)` in the hand-off.

- [ ] **Step 2: Check the files**

  Run:
  ```bash
  for f in shellx-android/app/src/{debug,release}/google-services.json; do python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["project_info"]["project_id"], ",".join(sorted(c["client_info"]["android_client_info"]["package_name"] for c in d["client"])))' "$f"; done
  ```

  Expected, twice: `shellxpro com.shellx.dev,com.shellx.prod`.

- [ ] **Step 3: Build with Firebase**

  Run:
  ```bash
  shellx-android/scripts/dev.sh test app
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk"
  shellx-android/gradlew -p shellx-android :app:tasks --all | grep -c GoogleServices
  shellx-android/scripts/dev.sh build-release
  grep -rl google_app_id shellx-android/app/build/generated | head -2
  ```

  Expected:
  - `==> test app: passed`;
  - a count of 2 or more;
  - `release checks passed` with no "Firebase: not configured" line;
  - two generated `values.xml` paths, one for debug and one for release.

- [ ] **Step 4: Run the licence check**

  Run: `bash scripts/shellx/check-android-license.sh`

  Expected: `check-android-license: ok`. The plugin adds no app dependency.

- [ ] **Step 5: Commit**

  ```bash
  git add shellx-android/app/src/debug/google-services.json shellx-android/app/src/release/google-services.json
  git commit -m "build(shellx-android): Firebase config for com.shellx.dev and com.shellx.prod"
  ```

---

### Task 11: Verify and hand off

**Files:** none new. This task may regenerate strings or update the allowlist after merging `develop`.

- [ ] **Step 1: Bring the branch up to date with `develop`**

  Run:
  ```bash
  git -C /Users/lehuuphu/Documents/myProjects/shellx pull --ff-only origin develop   # the main checkout is on develop
  git merge --no-edit develop
  python3 shellx-android/scripts/import-strings.py --check || python3 shellx-android/scripts/import-strings.py
  ```

  If `pull --ff-only` fails because `develop` has diverged, stop and ask the user.

  If the importer refuses new iPhone keys:
  - put an iPhone-only feature, such as Sign in with Apple, in `strings-ios-only.txt`;
  - give text that names the iPhone, App Store or VoiceOver an override, writing "phone" / "điện thoại", "Google Play" and "TalkBack", and changing nothing else.

  Add a row to the ledger's "iPhone changes since the reference" for each iPhone change you met. If anything changed, run:
  ```bash
  git add shellx-android/app/src/main/res shellx-android/scripts/strings-ios-only.txt docs/superpowers/ledgers/shellx-android-parity.md
  git commit -m "feat(shellx-android): import the iPhone strings added on develop"
  ```

- [ ] **Step 2: Run the full verification**

  Run:
  ```bash
  shellx-android/scripts/dev.sh test all
  bash scripts/shellx/check-android-license.sh
  bash scripts/shellx/check-ios-license.sh | tail -1
  bash scripts/shellx/check-link-license.sh && echo link-ok
  swift package --package-path shellx-link describe >/dev/null && echo swiftpm-ok
  python3 scripts/verify-local.py
  git status --short
  ```

  Expected:
  - `test all` ends with `==> test all: passed`. Along the way: `Ran 34 tests … OK`, the link, core and app tests `PASSED`, and `release checks passed`;
  - `check-android-license: ok`, then `check-ios-license: ok`, then `link-ok`, then `swiftpm-ok`;
  - `verify-local.py` ends with a line that starts with `PASSED:`;
  - `git status --short` prints nothing.

  If a `verify-local.py` check fails, rerun it in the main checkout on `develop` with `python3 scripts/verify-local.py --only <check>`. The same failure there is pre-existing: record it in the hand-off and do not fix it.

- [ ] **Step 3: Get a review**

  Follow `skills/cmux-review/SKILL.md` (default pre-merge review). Give a fresh review subagent:
  - this plan's goal;
  - the base `$(git merge-base develop HEAD)` and the head `HEAD`;
  - `git diff develop...HEAD`.

  Ask for correctness first, then this plan's Global Constraints. Fix the concrete findings, rerun Step 2, and get a second review of the repair when the fixes were not trivial.

- [ ] **Step 4: Land the branch (contracts §1)**

  In the main checkout `/Users/lehuuphu/Documents/myProjects/shellx`, on `develop`, run:
  ```bash
  git -C /Users/lehuuphu/Documents/myProjects/shellx status --short | grep -v '^??' || true   # expect no output
  git -C /Users/lehuuphu/Documents/myProjects/shellx merge --no-ff --no-edit feat/shellx-android-3a-scaffold
  (cd /Users/lehuuphu/Documents/myProjects/shellx && bash scripts/shellx/check-android-license.sh && python3 shellx-android/scripts/import-strings.py --check)
  git -C /Users/lehuuphu/Documents/myProjects/shellx push origin develop
  ```

  Expected:
  - no tracked changes (untracked files are fine);
  - a merge commit;
  - `check-android-license: ok` and `import-strings: ok (…)`;
  - the push succeeds.

  Never merge to `main`. Never deploy, upload or publish.

- [ ] **Step 5: Hand off**

  Report to the user, in Vietnamese per their preference:
  - what landed, with the merge commit;
  - the versions pinned: AGP, Kotlin, Gradle, Compose BOM, JUnit 5, Robolectric, Roborazzi, and `API`;
  - the screenshots from Tasks 8–9;
  - what is still the user's: the Firebase files if Task 10 was skipped; phone dogfood if pending; for 3H, the Play Console checks from S3 §10;
  - this plan's "Contract additions", to copy into the contracts file;
  - its "Spec notes".

---

## Spec notes

1. **Gradle path boundary.** S3 §5 keeps Gradle paths inside `shellx-android/` and `shellx-link/kotlin/`. But contracts §5 has the link tests read `../../vectors/` and `../../spec/vectors/`, which are MIT data in `shellx-link/`. The check therefore also allows `shellx-link/vectors/` and `shellx-link/spec/`.
2. **Licences on test classpaths.** S3 §5 lists the licences the app may use. The contracts require JUnit 5 (EPL-2.0), and Robolectric brings test-only artefacts under EPL, ICU and CDDL. The check separates what ships (release and debug runtime classpaths) from test classpaths, and allows those extra licences only on test classpaths. GPL, LGPL and AGPL are never allowed. Dual-licensed artefacts (CDDL or GPLv2) are listed under the CDDL.
3. **Names of keys with arguments.** The contracts' name rule does not cover iPhone keys that end with format arguments, such as `agent.close.title %@`. The name uses the key up to its first space. Exactly one collision exists (`agent.state.running` and `agent.state.running %@`); a rename table resolves it to `agent_state_running_for`.
4. **"Same words as the iPhone"** (S3 §7.2) would put "iPhone", "App Store", "VoiceOver" or "Apple" into 14 Android strings. They get Android wording, and the importer refuses future ones without an override (ledger A-2). The voice-server string says "usually Google's servers", because the phone, not ShellX, chooses its recognition service. 3E may refine that copy.
5. **The splash.** S3 §6.1 says "logo, name". The iPhone shows its launch image, then `LaunchView`. Android 12 and later always add a system splash (the app icon on the window background) first. The window background is the ShellX background, so there is no flash (ledger A-5).
6. **Who owns the theme.** Contracts §5 makes 3D the owner of `ShellXTheme` and `ShellXColors`. 3A creates their first version, because the launch screen needs it. Light and dark follow the system; 3D adds the Settings › Appearance switch, including `enableEdgeToEdge` system-bar styles for a forced theme.
7. **Screenshot tests.** S3 §8 asks for screenshot tests "like `SnapshotWriter.swift`". As on the iPhone, the render tests write PNGs when asked and assert light ≠ dark. No golden images are committed. S3 §11 leaves the library to the builder: this plan picks Roborazzi over Paparazzi, for three reasons:
   - It captures through Robolectric, the real Android framework, so 3D and 3E can run Compose behaviour tests (system Back, dialogs, bottom sheets) on the JVM with the same setup.
   - Its screen capture includes dialog and bottom-sheet windows.
   - It does not depend on a layoutlib bundled per compileSdk, which is where Paparazzi breaks when the SDK moves.

   Both are Apache-2.0 and need no emulator. Roborazzi is used without its Gradle plugin: only its capture runs, in record mode.
8. **Backups.** S3 §7.3 asks that secrets stay out of backups. 3A turns backup and device transfer off for the whole app, as the Flutter app did (ledger A-4). A later plan may allow individual preferences.
9. **Emulator images.** S3 §8 notes that only API 29 phone and API 35 tablet images are installed; this was confirmed. The installed emulator (32.1.11) is too old for API 36 images, so the user's `sdkmanager` step also updates `emulator`.
10. **Firebase files are committed.** S3 §10 says `google-services.json` is not a secret and should be kept "as the builder proposes". The prod file was already public in this repository (tag `flutter-final`, `apps/mobile/android/app/google-services.json`, project `shellxpro`), and worktrees need the files.
11. **`VERSION_CODE` 100.** The Flutter app's last local versionCode was 2 (`1.0.0+2` at `flutter-final`). The user confirms the highest uploaded code in Play Console (3H).
12. **Ledger owners.** S3 and the contracts do not say how §6.1 and §6.2 split between 3D and 3E, nor which plan implements each `:core` platform interface. The ledger assigns them (see Contract additions 8).
13. **`pairing_instructions`** quotes the Mac's menu item as it will read after desktop 1.8.0 (S3 §7.4b, plan 1B): "Pair Phone…" / "Ghép cặp điện thoại…".
14. **Native code.** Compose may bring a native library (`androidx.graphics:graphics-path`), so 3H's 16 KB page-size check applies from the first build.

## Contract additions

Add these to the contracts file (§5 unless noted). This plan did not edit it.

1. **Android string names.**
   - The name is derived from the iPhone key up to its first space. `RENAMES` in `import-strings.py` overrides it; today it holds only `agent.state.running %@` → `agent_state_running_for`.
   - A name defined in `values/strings_android.xml` replaces the generated one, and needs its vi text in `values-vi/strings_android.xml`.
   - iPhone-only keys are listed in `shellx-android/scripts/strings-ios-only.txt`.
   - The Android-only `app_name` is "ShellX", or "ShellX Dev" through `app/src/debug/res/values/strings_android.xml`.
2. **The Mac menu item after desktop 1.8.0** (owner 1B). `remote.phonePairing.menu` reads `Pair Phone…` / `Ghép cặp điện thoại…`. The Android `pairing_instructions` quotes it; if 1B picks other words, 1B updates that Android string too.
3. **`dev.sh` additions.**
   - commands `lock` and `clean`, and `emulator --headless`;
   - the serial sources `--serial`, `$SHELLX_ANDROID_SERIAL` and `~/.config/shellx/android-serial`;
   - the AVDs `ShellX_Dev_API_26` and `ShellX_Dev_API_36`, on ports 5580 and 5582, with serials `emulator-5580` and `emulator-5582`.
4. **Dependency licences.**
   - Every module has a `gradle.lockfile` (runtime classpaths only). The list of allowed dependencies is `scripts/shellx/android-license-allowlist.txt`, with format `group:artifact scope licence` and scope `ship` or `test`.
   - Every plan that adds a dependency runs `dev.sh lock`, adds allowlist lines by the procedure in this plan's Task 3 Step 6, and gets `check-android-license.sh` to pass in the same commit.
   - Each `group:artifact` has one line. A `test` line whose artefact starts to ship is moved to `ship`, never duplicated.
5. **Test layout.**
   - `:app` unit tests live in `app/src/test/kotlin` (JUnit 4 with Robolectric).
   - Render tests live in `app/src/testDebug/kotlin/com/shellx/app/screenshots/*RenderTest.kt`. They use `ShellXSnapshots.capture(name) { … }` with `@GraphicsMode(NATIVE)` and `@Config(qualifiers = ShellXSnapshots.DEVICE_QUALIFIERS)`.
   - The PNGs are named `<name>-<light|dark>-<en|vi>.png`.
6. **App shell.**
   - `com.shellx.app.MainActivity` is the only activity and the launcher.
   - `com.shellx.app.ui.LaunchView` is the launch screen.
   - The theme is `ShellXTheme(darkTheme: Boolean = isSystemInDarkTheme(), content)` and `ShellXTheme.colors`, with tokens `ShellXColors.Light` and `ShellXColors.Dark` and the Material 3 role table in Task 7. M3 `surface` is the screen colour; containers are the iPhone's `Surface`.
7. **Mirror rule.** `shellx-ios/ShellX/<Folders>/<Name>.swift` → `shellx-android/app/src/main/kotlin/com/shellx/app/<folders in lower case>/<Name>.kt`, and `ShellXAppCore/<Folder>/<Name>.swift` → `shellx-android/core/src/main/kotlin/com/shellx/core/<folder in lower case>/<Name>.kt`. Types keep their iPhone names, and contract names win.
8. **Owners of the `:app` platform implementations.** 3D owns `SecretStore`, `NetworkMonitor` and `Clock`, plus the `ProcessLifecycleOwner` hook. 3E owns `SpeechEngine`, `PushRegistrar`, `UpdateChecker` and `AttachmentReader`.
9. **Version catalog keys.**
   - Kotlin coordinates: group `com.shellx.link`, so `com.shellx.link:link-core` and `com.shellx.link:link-account`, with aliases `libs.shellx.link.core` and `libs.shellx.link.account`.
   - The keys `kotlin` and `junit` must be equal in both catalogs; `dev.sh` checks this.
   - SDK keys: `androidMinSdk`, `androidCompileSdk`, `androidTargetSdk`.
10. **Firebase.** The config is `shellx-android/app/src/debug/google-services.json` and `app/src/release/google-services.json`, both committed. The google-services plugin applies only when both exist; until then push is off.

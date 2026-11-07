# ShellX Android 3D — UI Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Android app's shell on plan 3C's core, so a user can sign in with Google, pair a Mac (QR, paste or link), see its workspaces and agents, manage their Macs and settings, delete the account, or try the app without an account. The shell covers:
- the composition root and the platform services (Keystore secrets, DataStore settings, network, clock, Google identity);
- navigation with the contract routes;
- the screens: sign-in, pairing, first Mac with "Try without an account", Your Macs, the home, the session lists and Settings.

**Architecture:** `ShellXApplication` loads the DataStore settings snapshot off the main thread, then builds `AppComposition`.
- `AppComposition` holds the real account's `AccountGraph` and a `DemoSession`. Each account has an `AppCoordinator` (3C) and, per hub it makes, one `SignedInScope`.
- `AppComposition.root` names the one root destination of `ShellXNavHost` (`launch`, `sign_in`, `first_mac`, `home` or `demo`). The other contract routes are pushed above it.
- Every screen is a stateless composable fed with plain values (render-tested with 3A's Roborazzi helper and driven by Compose UI tests), plus a thin stateful wrapper that reads 3C's models.
- `AppLifecycle` (fed by `ProcessLifecycleOwner`) launches the account at the first ON_START and drives the hub's background grace and the network watcher.
- Plan 3E (`docs/superpowers/plans/2026-11-07-shellx-android-3e-ui-work.md`, already written) plugs in through:
  - `AppComposition`'s five typed parameters and `makeVoice`;
  - the three work destinations of `ShellXNavHost`;
  - the `SignedInFrame` seam;
  - `NotificationsSettingsSection()`;
  - the shared names in Contract additions.

**Tech Stack:** Kotlin, Jetpack Compose with Material 3 (3A's BOM), Navigation Compose, Lifecycle (runtime-compose, viewmodel-compose, process), DataStore Preferences, Android Keystore (AES-GCM), ConnectivityManager, Credential Manager with `googleid`, CameraX with ZXing core, `material-icons-extended`. Tests: JUnit 4 with Robolectric, Compose UI test, Roborazzi through 3A's `ShellXSnapshots`, kotlinx-coroutines-test.

**Spec:** `docs/superpowers/specs/2026-11-07-shellx-android-app-design.md` (S3) §3 (Flutter data), §4, §6.1, §6.2 (rows 7, 10 and 11), §7.2, §7.3; `docs/superpowers/specs/2026-11-07-shellx-google-sign-in-design.md` (S1) §6.3, §6.7, §6.8. Cross-plan names: `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` §1, §5, §11, §12, §14, §15, §16, §20. Built on plans 3A (scaffold), 3B (Kotlin Link) and 3C (core), whose Interfaces blocks this plan uses by name. The iPhone screens translated are under `shellx-ios/ShellX/UI/`; the sign-in, deletion and demo screens follow plan 1C Tasks 9, 11 and 13. Plan 3E's Task 0 table and Task 12 say what 3E expects from this plan.

## Global Constraints

- **Where.** Only `shellx-android/`, `scripts/shellx/android-license-allowlist.txt` and `docs/superpowers/ledgers/shellx-android-parity.md`. Never copy or link from `ios/`, `Packages/`, `Sources/`, `cmux-tui/` or `shellx-core/`; translating `shellx-ios/` is allowed. Never write the upstream company name (3A licence rule 8). Never edit `:core` or `shellx-link/kotlin/`.
- **Google branding (contracts §11).**
  - The "G" comes only from Google's `signin-assets.zip`, downloaded by the user (Task 9 Step 7), and is cropped unchanged. Never take a Google logo from `ios/`, `Packages/` or `Sources/`, and never use a drawn, traced or converted one.
  - Google Sans is bundled only when its official download carries the SIL OFL 1.1 text, saved next to it as `assets/fonts/GoogleSans-OFL.txt`. Otherwise the button uses the platform font.
- **Contract names** (contracts §5, §15, §16, §20), exactly:
  - `com.shellx.app.ShellXApplication` and `com.shellx.app.AppComposition`;
  - `com.shellx.app.ui.nav.ShellXNavHost` with the routes `launch`, `sign_in`, `first_mac`, `pairing`, `home`, `workspace/{machineId}/{workspaceId}`, `agent/{machineId}/{sessionId}`, `pending` (optional `?machineId=…&workspaceId=…`), `sessions/{kind}`, `machines`, `settings`, `demo`;
  - `SettingsScreen` with the sections Your Macs, Account, Appearance, Voice, Notifications, About, in that order, and `NotificationsSettingsSection()`, which renders nothing;
  - the string `google_web_client_id` in `shellx-android/app/src/main/res/values/google_oauth.xml`.
- **Names plan 3E creates.** Never define them here:
  - `PlatformServices`, `SignedInWork`, `LocalVoice`, `VoiceEnvironment`, `LocalAttachmentReader`, `PushHost`, `PushTapInbox`, `UpdateAlert`, `NeedsYouBar`;
  - 3E's test kit names in `com.shellx.app.testing`: `TestClock`, `eventually`, `WorkRig`, `FakeSpeechEngine`, `FakeVoicePermissions`, `FakeResultRegistry`, `TestOwner`;
  - `com.shellx.app.ManifestTest`.

  The names that 3E's plan marks "create if missing" are created here, with exactly 3E's shapes (Contract additions 6).
- **3C's API.** Use the names and signatures of 3C's Interfaces blocks. If a real one differs, use the real one and list the difference in your report.
- **minSdk 26.** Guard every call above API 26 (`ClipboardManager.clearPrimaryClip` is API 28). Never use `RouteInfo.isDefaultRoute` (API 29).
- **Look (S3 §7.2).**
  - Material 3 through `ShellXTheme`, with no dynamic colour.
  - Text and icons in the accent colour use `ShellXTheme.colors.accentText`. Filled buttons are `PrimaryButton` (accent fill, `onAccent` label). There are no gradient buttons.
  - Status colours come only through `StatusTone.color()` (Task 6); running is `statusRunning` (yellow).
  - "Card" is a surface in `ShellXTheme.colors.surface` with a 1 dp outline of `onSurface` at 10 % alpha.
- **Type scale** (iPhone → Material 3): `largeTitle` → `headlineLarge`, `title2` → `headlineSmall`, `title3` → `titleLarge`, `headline` → `titleMedium`, `body` → `bodyLarge`, `callout` and `subheadline` → `bodyMedium`, `footnote` → `bodySmall`, `caption` → `labelMedium`, `caption2` → `labelSmall`. The iPhone's `.secondary` colour is `onSurfaceVariant`, `.monospaced()` is `FontFamily.Monospace`, and semibold is `FontWeight.SemiBold`.
- **Large text.** `isLargeText()` (Task 6) is `LocalDensity.current.fontScale >= 1.3f`, the threshold 3E uses too. Where the iPhone switches layout at its accessibility sizes, Android switches here.
- **Touch targets** are at least 48 dp. The iPhone's 44 pt rows become 48 dp.
- **Interactions (S3 §7.2).**
  - Pushed screens have a Material top app bar with a back arrow (`Icons.AutoMirrored.Filled.ArrowBack`, description `nav_back`).
  - System Back and predictive back work everywhere (`android:enableOnBackInvokedCallback="true"`).
  - The iPhone's rename sheet becomes a `ModalBottomSheet`. Pairing is a full-screen route (Spec note 1).
  - Every confirmation is a `ConfirmDialog`, `AgentCloseConfirmation` or the deletion card (Task 15).
  - On a row, the swipe runs the primary action and a long press opens a menu of every action. The same actions are TalkBack custom actions (`ActionRow`, Task 6).
  - Pull to refresh uses `PullToRefreshBox`. Screens are edge-to-edge inside a `Scaffold`.
- **Strings.**
  - Every visible string comes from `stringResource` / `pluralStringResource` over the generated `strings.xml` or `strings_android.xml`. Never hand-edit the generated files.
  - After editing `strings_android.xml`, run `python3 shellx-android/scripts/import-strings.py`.
  - Shown verbatim: "ShellX" (through `root_title`), version numbers, `shellx.pro`, and user data (Mac names, titles, e-mails).
- **TalkBack.**
  - Where the iPhone posts a VoiceOver announcement, the text node has `liveRegion = LiveRegionMode.Polite`.
  - Decorative icons have `contentDescription = null`.
  - Cards merge their descendants. Clickable rows carry `onClickLabel` where the iPhone has a hint.
- **Threading.** 3C's models are main-confined: call them from composition, or from coroutines on `Dispatchers.Main.immediate`.
  - Work that must finish after its screen leaves runs in `scope.hub.scope` (hub commands, unpair) or in `composition.appScope` (demo start and exit); the screen only awaits it.
  - Never touch the disk or the Keystore on the main thread: use `environment.io`.
- **Secrets and logs.** Log only through `CoreLog`, whose sink is `android.util.Log.i("ShellX", line)`. Never log a token, id, name, pairing code or content. Pairing codes stay in memory (`PairingInbox`, `PairingModel`).
- **Tests.** `:app` tests are JUnit 4, and every test class has `@RunWith(AndroidJUnit4::class)` (Robolectric), as in 3E: `android.jar`'s stubs throw on the JVM.
  - Logic tests go in `app-test/`. Compose UI tests and render tests go in `app-ui-test/`: they need `ui-test-manifest`, which is debug only.
  - Coroutine tests use `runTest` with block bodies (`@Test fun x() { runTest { … } }`), long-lived objects in `backgroundScope`, and `waitFor` from `com.shellx.app.testing` (Task 7). Real-time Compose waits use `composeRule.waitUntil`.
  - Render tests are `…RenderTest` classes in `com.shellx.app.screenshots`, annotated like 3A's `LaunchViewRenderTest`. Each case is `assertRenders("<name>") { … }` (Task 6, the same helper as 3E Task 1). PNGs are `<name>-<light|dark>-<en|vi>.png`.
  - Robolectric builds `android.app.Application` unless a test says `@Config(application = ShellXApplication::class)` (Task 1).
- **Dependencies.** Only the ones Task 1 adds.
  - Each version is the newest stable one, found with 3A's `latest` helper (3A Task 0 Step 4).
  - Every new artefact goes through `dev.sh lock` and the allowlist procedure (3A Task 3 Step 6). Google SDK groups are listed by exact artifact with `Google-SDK`.
- **Commits.** Commit the failing tests first (`test(shellx-android): …`), then the implementation (`feat(shellx-android): …`). Always use an explicit `git add <paths>`. Ledger rows change in the same commit as their code.
- **Landing** (contracts §1, and CLAUDE.md "CI, review and merge" for UI changes). Merge into `develop` only after the USER phone check and the user's merge directive (`merge`, `merge it`, `auto-merge`). Push `develop`. Never merge to `main`, deploy, upload to a store or publish.

## Review Focus

1. **A configuration change mid-flow** (rotation, a dark-mode switch, a language change while pairing or with a dialog open). A recreated screen must keep the pairing attempt and the dialog's target; only leaving the pairing page cancels the attempt. Tests: Task 10 `leavingTheScreenCancelsThePairingAndRecreationDoesNot`; Task 13 `anOpenConfirmationSurvivesRecreation`.
2. **A `shellx-link` link that arrives while signed out, during the demo or over an open pending sheet.** It waits in memory, later opens only the confirmation step, and nothing reaches the relay before Pair. Tests: Task 7 `aLinkWaitsForARealSignedInHomeAndOnlyFillsTheConfirmation` and `aLinkWaitsWhileASheetIsOpenOrTheDemoRuns`.
3. **A process started in the background** (an FCM message, 3E). It connects no Mac and watches no network until the first ON_START, so it uses no battery (S3 §4). Test: Task 8 `aBackgroundStartConnectsNothing`.
4. **A Keystore key that is lost (restore, cleared credentials) or busy.**
   - A lost key reads as signed out: the sign-in screen, not a "keychain" error.
   - A busy store keeps the launch screen and is retried at the next start.
   Tests: Task 4 `aLostKeyReadsAsAbsentAndDeletesTheFile` and `aBusyKeystoreIsUnavailableAndKeepsTheFile`; Task 7 `aBusyKeystoreKeepsTheLaunchScreenUntilItOpens`.
5. **Repeated taps on a one-shot action** (Delete Account, Sign out, Unpair, Pair, ＋, Close Agent, Close Tab): exactly one request goes out. Tests:
   - Task 15 `deleteTappedTwiceDeletesOnce` and `signOutTappedTwiceSignsOutOnce`;
   - Task 11 `unpairTappedTwiceUnpairsOnce`;
   - Task 7 `pairTappedTwiceSendsOnePairingRequest`;
   - Task 12 `closeAgentAsksTheMacOnce` and `closeTabAsksTheMacOnce`;
   - Task 13 `aSecondTapOnCreateWaitsForTheFirst`.

## Conventions

- **Path prefixes.**
  - `app/` = `shellx-android/app/src/main/kotlin/com/shellx/app/`
  - `res/` = `shellx-android/app/src/main/res/`
  - `app-test/` = `shellx-android/app/src/test/kotlin/com/shellx/app/`
  - `app-ui-test/` = `shellx-android/app/src/testDebug/kotlin/com/shellx/app/`
  - `ios/` = `shellx-ios/ShellX/` (this prefix never means the repository's root `ios/` folder, which is GPL and which the Global Constraints forbid)
  - `ios-tests/` = `shellx-ios/ShellXTests/`
- **Gradle.** Paste these definitions at the start of every shell call that uses them (shell state does not carry over):

  ```bash
  gw() { R="$(git rev-parse --show-toplevel)"; JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" "$R/shellx-android/gradlew" -p "$R/shellx-android" --console=plain "$@"; }
  acounts() { R="$(git rev-parse --show-toplevel)"; for c in "$@"; do echo "$c $(grep -o 'tests="[0-9]*" skipped="[0-9]*" failures="[0-9]*" errors="[0-9]*"' "$R/shellx-android/app/build/test-results/testDebugUnitTest/TEST-com.shellx.app.$c.xml" | head -1)"; done; }
  ```

  - One class: `gw :app:testDebugUnitTest --tests 'com.shellx.app.<…>'`.
  - A **red** run ends with `BUILD FAILED` and the compile error or the failing test the step names. A **green** run ends with `BUILD SUCCESSFUL` and has no `FAILED`.
  - `acounts ui.home.FocusRowTextTest` prints `tests="5" skipped="0" failures="0" errors="0"` when a step says "5 tests".
  - The full runs are `shellx-android/scripts/dev.sh test app` (passes with `==> test app: passed`) and `shellx-android/scripts/dev.sh test screenshots` (`==> test screenshots: passed`).
- **Read the Swift first.** The iPhone file a task names is the reference for every body this plan leaves out: structure, order and words. Read it before the task.
- **Porting an iPhone test.** One Kotlin `@Test` per Swift `func test…`, named without `test`, with every assertion and literal kept. Translate:
  - `Date(timeIntervalSince1970: s)` → epoch ms;
  - `await` before a fake → nothing (3C's fakes are synchronous);
  - `URLError(…)` → `java.io.IOException("offline")`;
  - `machineID` → `machineId`;
  - `.working` → `AgentState.WORKING`;
  - `String(localized: "k \(x)")` → `context.getString(R.string.<name>, x)`, where `<name>` is the contract name of key `k`;
  - `.environment(\.dynamicTypeSize, .accessibility3)` → `LargeText { … }` (Task 6).
- **Render tests.** A screen is captured through its stateless composable, never through a model.
- **Dialogs in screenshots.** `ShellXSnapshots.capture` draws the composable's own window only, so a dialog or sheet window does not appear in it (Spec note 10). Render the content composable instead (`DeleteAccountCard`, `WorkspaceRenameContent`). Compose UI tests check dialog text and buttons.
- **Ledger** (`docs/superpowers/ledgers/shellx-android-parity.md`).
  - A row whose Plan cell is `3D`, or shared with a plan that is already done, becomes `done (3D)` in the commit that finishes it.
  - New `A-` rows go at the end of "Android-only differences", numbered from the first free number, in the order the tasks add them. 3E numbers its own rows after these.
  - Their Plan cell is `3D` and their State is `differs (3D): by design`, unless a task says otherwise.

## File map

| Area | Main files | Task |
| --- | --- | --- |
| Build | `shellx-android/app/build.gradle.kts`, `gradle/libs.versions.toml`, `app/src/main/AndroidManifest.xml`, `app/src/debug/{AndroidManifest.xml,res/xml/network_security_config.xml}`, `res/values/google_oauth.xml`, `scripts/dev.sh` | 1 |
| Strings | `res/values*/strings_android.xml`, `scripts/strings-ios-only.txt` | 2 |
| Platform | `app/platform/{AndroidClock,DataStoreKeyValueStore,DeviceName,NetworkPathWatcher,LegacyFlutterCleanup}.kt` | 3 |
| Secrets | `app/platform/KeystoreSecretStore.kt` | 4 |
| Identity | `app/platform/{CredentialManagerIdentity,ActivityTracker}.kt` | 5 |
| Theme and components | `app/ui/theme/{AppAppearance,AppLanguage,AgentStateStyle,MachineStateStyle}.kt`, `app/ui/components/{PrimaryButtonStyle,SecondaryButtonStyle,WaitingBorder,ActionRow,RowActions,Dialogs,SectionTitle,Ticker,LargeText,Savers}.kt`, `app-ui-test/screenshots/{RenderAssertions,PixelChecks}.kt` | 6 |
| Composition | `app/{AppComposition,AppEnvironment,AccountGraph,SignedInScope,LaunchMark,Stubs}.kt`, `app/demo/DemoSession.kt`, `app/ui/nav/{Routes,WorkRoutes,ShellXNavigator,RootRoutes}.kt`, `app/ui/workspaces/ListNotice.kt`, `app-test/testing/*` | 7 |
| Lifecycle | `app/{AppLifecycle,ShellXApplication,LinkIntents}.kt` | 8 |
| Sign-in, first Mac, demo entry | `app/ui/signin/*`, `app/ui/onboarding/FirstMacView.kt`, `app/demo/DemoBanner.kt`, `res/raw/keep_google_branding.xml`; after the USER step `res/drawable-{mdpi,xhdpi,xxhdpi,xxxhdpi}/ic_google_g.png` and `app/src/main/assets/fonts/GoogleSans{.ttf,-OFL.txt}` | 9 |
| Pairing | `app/ui/pairing/*`, `app/platform/CameraAccess.kt` | 10 |
| Your Macs | `app/ui/machines/*` | 11 |
| Home cards, words, close paths | `app/ui/home/FocusRowView.kt`, `app/ui/workspaces/{WorkspaceRowView,MachineGroupHeader,WorkspaceGroup,WorkspaceFeedback,WorkspaceListModel,WorkspaceListActions,OtherSessionsModel}.kt` | 12 |
| Home screen | `app/ui/workspaces/{WorkspaceListScreen,WorkspaceListView,WorkspaceRenameSheet}.kt`; `make` in `WorkspaceListActions.kt`; `NoticeCapsule` in `ListNotice.kt` | 13 |
| Session lists | `app/ui/home/{SessionListScreen,EndedSessionsView}.kt`, `app/ui/workspaces/OtherSessionsView.kt` | 14 |
| Settings | `app/ui/settings/*` | 15 |
| Assembly | `app/ui/nav/ShellXNavHost.kt`, `app/ui/{ShellXApp,SignedInView,SignedInFrame}.kt`, `app/MainActivity.kt` | 16 |

---

### Task 0: Set up the worktree and check what this plan builds on

**Files:** none.

- [ ] **Step 1: Create the worktree.** Use superpowers:using-git-worktrees. The branch is `feat/shellx-android-3d-ui-shell`, created from `develop`. Without a native tool, run `git worktree add .worktrees/android-3d-ui-shell -b feat/shellx-android-3d-ui-shell develop`. Work only in the worktree from now on.
- [ ] **Step 2: Check that 3A, 3B, 3C and 1C are merged.**

  ```bash
  test -x shellx-android/gradlew \
    && test -f shellx-android/app/src/testDebug/kotlin/com/shellx/app/screenshots/ShellXSnapshots.kt \
    && test -f shellx-android/core/src/main/kotlin/com/shellx/core/account/AppCoordinator.kt \
    && test -f shellx-android/core/src/main/kotlin/com/shellx/core/demo/DemoEnvironment.kt \
    && grep -rq 'interface LinkSession' shellx-link/kotlin/link-core/src/main \
    && grep -rq 'object PhonePairing' shellx-link/kotlin/link-account/src/main \
    && grep -q '"signin.google"' shellx-ios/ShellX/Localizable.xcstrings && echo ready
  ```

  Expected: `ready`. Otherwise stop and report "plans 3A, 3B, 3C and 1C must be merged into develop first". 1C is needed because its strings are the Android sign-in, demo and deletion strings (contracts §11). Change nothing.
- [ ] **Step 3: Read what this plan builds on.**
  - 3A Tasks 6–8, 3C's Interfaces blocks and its "UI wiring summary", and 3E's Task 0 table, Task 1 test kit and Task 12 wiring (the names 3E expects).
  - These files: `shellx-android/app/build.gradle.kts`, `app/src/main/AndroidManifest.xml`, `app/src/main/kotlin/com/shellx/app/{MainActivity.kt,ui/LaunchView.kt,ui/theme/*.kt}`, `app/src/testDebug/kotlin/com/shellx/app/screenshots/ShellXSnapshots.kt`, `gradle/libs.versions.toml`, `scripts/dev.sh`.
  - In `shellx-android/core/src/main/kotlin/com/shellx/core/`: `account/AppCoordinator.kt`, `link/MachineHub.kt`, `link/HubState.kt`, `pairing/*`, `home/*`, `demo/DemoEnvironment.kt`, `platform/*`, `voice/VoiceService.kt`.
  - If a plan file is missing in the worktree, read it from `/Users/lehuuphu/Documents/myProjects/shellx/docs/superpowers/plans/`. Never commit plan files on this branch.
- [ ] **Step 4: Baseline.** Run `shellx-android/scripts/dev.sh test all`.

  Expected: `==> test all: passed`. If it fails before any change, stop and report.

---

### Task 1: Dependencies, manifest, debug relay access and the Web client placeholder

**Files:**
- Modify: `shellx-android/gradle/libs.versions.toml`, `shellx-android/app/build.gradle.kts`, `shellx-android/app/gradle.lockfile` (rewritten by `dev.sh lock`), `scripts/shellx/android-license-allowlist.txt`, `shellx-android/app/src/main/AndroidManifest.xml`, `shellx-android/scripts/dev.sh` (`cmd_build_release`), `docs/superpowers/ledgers/shellx-android-parity.md`
- Create: `res/values/google_oauth.xml`, `shellx-android/app/src/debug/AndroidManifest.xml`, `shellx-android/app/src/debug/res/xml/network_security_config.xml`
- Create, or modify if 3A made it: `shellx-android/app/src/test/resources/robolectric.properties`
- Test: `app-test/ShellManifestTest.kt`, `app-ui-test/DebugRelayAccessTest.kt`

**Interfaces:**
- Produces:
  - **Catalog.** The `[versions]` keys `navigationCompose`, `lifecycle`, `datastore`, `credentials`, `googleid`, `camerax` and `zxing`, and these aliases. They are the same names 3E Task 1 adds when missing.

    ```toml
    androidx-navigation-compose = { module = "androidx.navigation:navigation-compose", version.ref = "navigationCompose" }
    androidx-lifecycle-runtime-compose = { module = "androidx.lifecycle:lifecycle-runtime-compose", version.ref = "lifecycle" }
    androidx-lifecycle-viewmodel-compose = { module = "androidx.lifecycle:lifecycle-viewmodel-compose", version.ref = "lifecycle" }
    androidx-lifecycle-process = { module = "androidx.lifecycle:lifecycle-process", version.ref = "lifecycle" }
    androidx-datastore-preferences = { module = "androidx.datastore:datastore-preferences", version.ref = "datastore" }
    androidx-credentials = { module = "androidx.credentials:credentials", version.ref = "credentials" }
    androidx-credentials-play-services-auth = { module = "androidx.credentials:credentials-play-services-auth", version.ref = "credentials" }
    googleid = { module = "com.google.android.libraries.identity.googleid:googleid", version.ref = "googleid" }
    androidx-camera-camera2 = { module = "androidx.camera:camera-camera2", version.ref = "camerax" }
    androidx-camera-lifecycle = { module = "androidx.camera:camera-lifecycle", version.ref = "camerax" }
    androidx-camera-view = { module = "androidx.camera:camera-view", version.ref = "camerax" }
    zxing-core = { module = "com.google.zxing:core", version.ref = "zxing" }
    androidx-compose-material-icons-extended = { module = "androidx.compose.material:material-icons-extended" }
    androidx-compose-ui-test-junit4 = { module = "androidx.compose.ui:ui-test-junit4" }
    ```
  - **`BuildConfig.SHELLX_API_BASE: String`.** It is `""`, unless a debug build gets `-PshellxApiBase=<url>`; 3C's `ShellXEndpoints.of` reads it.
  - **`R.string.google_web_client_id`.** It holds `0-shellx-placeholder.apps.googleusercontent.com` until plan 1D fills the real Web client ID (contracts §16).
  - **Manifest.** The permissions `INTERNET`, `ACCESS_NETWORK_STATE` and `CAMERA`. The camera is optional for installs. `<application android:enableOnBackInvokedCallback="true">`. `MainActivity` is `singleTask` with a `shellx-link` intent filter. Task 8 adds `android:name=".ShellXApplication"`, once the class exists.
  - **Robolectric** builds `android.app.Application` by default.

- [ ] **Step 1: Look up the versions and extend the catalog.** Use `latest` from 3A Task 0 Step 4 on:
  - Google Maven (`https://dl.google.com/dl/android/maven2/<group path>/<artifact>/maven-metadata.xml`): `androidx/navigation/navigation-compose`, `androidx/lifecycle/lifecycle-process`, `androidx/datastore/datastore-preferences`, `androidx/credentials/credentials`, `com/google/android/libraries/identity/googleid/googleid`, `androidx/camera/camera-core`;
  - Maven Central: `https://repo1.maven.org/maven2/com/google/zxing/core/maven-metadata.xml`.

  Add the Interfaces entries. The two Compose aliases have no version: the BOM sets it. If the BOM does not manage `material-icons-extended`, pin the newest stable `1.7.x` of it.
- [ ] **Step 2: Write the failing tests.**

```kotlin
// app-test/ShellManifestTest.kt (3E's ManifestTest checks its own permissions)
@RunWith(AndroidJUnit4::class)
class ShellManifestTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test fun shellxLinkLinksOpenTheOneActivity() {
        val view = Intent(Intent.ACTION_VIEW, Uri.parse("shellx-link://pair?v=1&m=m1")).addCategory(Intent.CATEGORY_BROWSABLE)
        assertEquals(listOf("com.shellx.app.MainActivity"),
            context.packageManager.queryIntentActivities(view, 0).map { it.activityInfo.name })
    }

    @Test fun theOneActivityIsSingleTask() {
        val info = context.packageManager.getActivityInfo(ComponentName(context, "com.shellx.app.MainActivity"), 0)
        assertEquals(ActivityInfo.LAUNCH_SINGLE_TASK, info.launchMode)
    }

    @Test fun noRelayOverrideWithoutTheGradleProperty() { assertEquals("", BuildConfig.SHELLX_API_BASE) }

    @Test fun theWebClientIdIsThePlaceholderOrAWebClient() {
        val id = context.getString(R.string.google_web_client_id)
        assertTrue(id, id == "0-shellx-placeholder.apps.googleusercontent.com" ||
            Regex("^[0-9]+-[a-z0-9]+\\.apps\\.googleusercontent\\.com$").matches(id))
    }
}
```

```kotlin
// app-ui-test/DebugRelayAccessTest.kt (debug only: the file exists only in src/debug)
@RunWith(AndroidJUnit4::class)
class DebugRelayAccessTest {
    @Test fun debugBuildsMayReachOnlyALoopbackRelayOverHttp() {
        val parser = ApplicationProvider.getApplicationContext<Context>().resources.getXml(R.xml.network_security_config)
        val domains = mutableListOf<String>(); var cleartext: String? = null
        while (parser.next() != XmlPullParser.END_DOCUMENT) {
            if (parser.eventType != XmlPullParser.START_TAG) continue
            if (parser.name == "domain-config") cleartext = parser.getAttributeValue(null, "cleartextTrafficPermitted")
            if (parser.name == "domain") domains += parser.nextText()
        }
        assertEquals("true", cleartext); assertEquals(listOf("127.0.0.1", "localhost"), domains)
    }
}
```

- [ ] **Step 3: Run them (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.ShellManifestTest' --tests 'com.shellx.app.DebugRelayAccessTest'`.

  Expected: `BUILD FAILED`, with `Unresolved reference: SHELLX_API_BASE` (or `network_security_config`).
- [ ] **Step 4: Commit the tests.** Run `git add shellx-android/app/src/test shellx-android/app/src/testDebug` and `git commit -m "test(shellx-android): manifest, links and the debug relay"`.
- [ ] **Step 5: Implement.**
  - **`app/build.gradle.kts`.**
    - Set `defaultConfig { buildConfigField("String", "SHELLX_API_BASE", "\"\"") }`, and in `buildTypes { debug { … } }` the same field from `providers.gradleProperty("shellxApiBase").getOrElse("")`.
    - Add `implementation` of the thirteen app aliases: every alias above except `androidx-compose-ui-test-junit4` (`material-icons-extended` included).
    - Add `testImplementation(platform(libs.androidx.compose.bom))`, `testImplementation(libs.androidx.compose.ui.test.junit4)` and `testImplementation(libs.kotlinx.coroutines.test)`. The last alias comes from 3C.
  - **`AndroidManifest.xml`** (main).
    - Add `<uses-permission>` for `android.permission.INTERNET`, `android.permission.ACCESS_NETWORK_STATE` and `android.permission.CAMERA`.
    - Add `<uses-feature android:name="android.hardware.camera" android:required="false" />` and the same for `android.hardware.camera.autofocus`.
    - On `<application>`, add `android:enableOnBackInvokedCallback="true"`.
    - On `MainActivity`, add `android:launchMode="singleTask"` and a second `<intent-filter>` with `action.VIEW`, `category.DEFAULT`, `category.BROWSABLE` and `<data android:scheme="shellx-link" />`.
  - **`app/src/debug/AndroidManifest.xml`.** `<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application android:networkSecurityConfig="@xml/network_security_config" /></manifest>`, with a comment: "Debug builds may reach a relay on this Mac through `adb reverse` (ledger A-6); release builds keep Android's default of no cleartext."
  - **`app/src/debug/res/xml/network_security_config.xml`.** `<network-security-config><domain-config cleartextTrafficPermitted="true">` holding `<domain includeSubdomains="false">127.0.0.1</domain>` and the same for `localhost`.
  - **`res/values/google_oauth.xml`:**

    ```xml
    <?xml version="1.0" encoding="utf-8"?>
    <!-- Google sign-in (S1 §6.7, contracts §16): the OAuth client of type "Web application" in project shellxpro,
         used as Credential Manager's serverClientId. PLACEHOLDER until plan 1D copies the real ID from
         docs/superpowers/ledgers/shellx-signin-rollout.md; release/mobile/android.sh (3H) refuses a release
         that still holds it. Client IDs are not secrets. -->
    <resources>
        <string name="google_web_client_id" translatable="false">0-shellx-placeholder.apps.googleusercontent.com</string>
    </resources>
    ```
  - **`robolectric.properties`.** Add the line `application=android.app.Application`, keeping any line 3A wrote.
  - **`dev.sh` `cmd_build_release`.** After 3A's checks, add four. Each failure names what was expected.
    - The badging contains `uses-permission: name='android.permission.INTERNET'`, `…ACCESS_NETWORK_STATE'` and `…CAMERA'`.
    - It does not match `uses-permission: name='android.permission.(READ_EXTERNAL_STORAGE|WRITE_EXTERNAL_STORAGE|MANAGE_EXTERNAL_STORAGE|READ_MEDIA_[A-Z_]*)'`.
    - It contains `uses-feature-not-required: name='android.hardware.camera'`.
    - The `xmltree` of the manifest contains neither `networkSecurityConfig` nor `usesCleartextTraffic`.
- [ ] **Step 6: Lock and fill the allowlist.** Run `shellx-android/scripts/dev.sh lock`, then `bash scripts/shellx/check-android-license.sh`.
  - Apply 3A Task 3 Step 6 to every `violation` line, and rerun until it prints `check-android-license: ok`.
  - Expect Google SDK lines, each with its exact artifact and `Google-SDK`: one line per `com.google.android.gms:play-services-…` artefact that `credentials-play-services-auth` pulls in (3A's rule 3 allows no `*` there), and `com.google.android.libraries.identity.googleid:googleid`. Also expect `com.google.zxing:core` (Apache-2.0), CameraX's `com.google.guava:listenablefuture` and `com.google.auto.value:auto-value-annotations`, and Apache-2.0 annotation or injection libraries (for example `org.jspecify:jspecify`, `javax.inject:javax.inject`).
  - When a violation says `(ship)` for an artefact the allowlist already lists as `test` (3A's Robolectric run added it), change that line's scope to `ship` instead of adding a second line for it.
  - If a licence is not allowed for its scope, stop and report the artefact to the user.
- [ ] **Step 7: Run (green).** Run the Step 3 command, then `shellx-android/scripts/dev.sh test app` and `shellx-android/scripts/dev.sh build-release`.

  Expected:
  - 4 and 1 tests;
  - `==> test app: passed`;
  - `==> release checks passed (…)`.
- [ ] **Step 8: Ledger.** Add an `A-` row:
  - difference: "A debug build may reach a relay at `http://127.0.0.1` or `http://localhost` (cleartext to loopback only, `app/src/debug/res/xml/network_security_config.xml`); release builds allow no cleartext";
  - why: "the debug relay override of A-6 needs plain HTTP to a relay on the Mac through `adb reverse`; the iPhone's debug build has `NSAllowsLocalNetworking`";
  - Android: `app/src/debug/AndroidManifest.xml`.
- [ ] **Step 9: Commit.** Run `git add shellx-android/gradle shellx-android/app shellx-android/scripts/dev.sh scripts/shellx/android-license-allowlist.txt docs/superpowers/ledgers/shellx-android-parity.md`, then `git commit -m "build(shellx-android): UI shell dependencies, manifest, links and the debug relay"`.

---

### Task 2: Strings for sign-in, deletion, the demo and Android interactions

**Files:**
- Modify: `shellx-android/scripts/strings-ios-only.txt`, `res/values/strings_android.xml`, `res/values-vi/strings_android.xml`, `docs/superpowers/ledgers/shellx-android-parity.md`
- Generate: `res/values/strings.xml`, `res/values-vi/strings.xml`
- Test: `app-test/StringsTest.kt`

**Interfaces:**
- Produces:
  - the imported 1C names `signin_google`, `signin_demo`, `signin_error_switch_from_signed_in_device`, `signin_error_provider_unavailable`, `signin_error_provider_failed`, `first_mac_demo`, `demo_banner_title`, `demo_banner_exit`, `demo_banner_label`, `settings_account_delete`, `settings_account_delete_title`, `settings_account_delete_button`, `settings_account_delete_deleting`;
  - Android wording for `signin_subtitle`, `signin_error_reauth_required` and `settings_account_delete_message`;
  - the Android-only names `nav_back`, `row_actions`, `action_open_agent` and `action_open_your_macs`.

- [ ] **Step 1: See where the catalog stands.** Run `python3 shellx-android/scripts/import-strings.py --check`.

  Write down every refused key. If it already passes, another plan has imported 1C's keys: check that the entries below are as this task writes them, and change any that differ.
- [ ] **Step 2: Write the failing test.**

```kotlin
// app-test/StringsTest.kt
@RunWith(AndroidJUnit4::class)
class StringsTest {
    private fun text(id: Int, language: String): String {
        RuntimeEnvironment.setQualifiers("+$language")
        return ApplicationProvider.getApplicationContext<Context>().getString(id)
    }

    @Test fun androidWordingNamesNoApplePlatform() {
        for (id in listOf(R.string.signin_subtitle, R.string.signin_error_reauth_required, R.string.settings_account_delete_message))
            for (language in listOf("en", "vi")) {
                val value = text(id, language)
                for (word in listOf("iPhone", "Apple", "App Store")) assertFalse(value, value.contains(word))
            }
    }

    @Test fun theDeletionPathReadsAsOnTheWebsite() {   // contracts §12: "Settings › Account › Delete Account…"
        assertEquals(listOf("Settings", "Account", "Delete Account…"),
            listOf(R.string.settings_title, R.string.settings_account_title, R.string.settings_account_delete).map { text(it, "en") })
        assertEquals(listOf("Cài đặt", "Tài khoản", "Xoá tài khoản…"),
            listOf(R.string.settings_title, R.string.settings_account_title, R.string.settings_account_delete).map { text(it, "vi") })
    }

    @Test fun androidOnlyStringsHaveVietnamese() {
        for (id in listOf(R.string.nav_back, R.string.row_actions, R.string.action_open_agent, R.string.action_open_your_macs))
            assertNotEquals(text(id, "en"), text(id, "vi"))
    }

    @Test fun theDemoAndSignInStringsCameOver() {
        assertEquals("Continue with Google", text(R.string.signin_google, "en"))
        assertEquals("Xem thử không cần tài khoản", text(R.string.signin_demo, "vi"))
        assertEquals("Thoát", text(R.string.demo_banner_exit, "vi"))
    }
}
```

- [ ] **Step 3: Run it (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.StringsTest'`.

  Expected: `BUILD FAILED`, with `Unresolved reference: nav_back` (or another of the names).
- [ ] **Step 4: Commit the test.** Run `git add shellx-android/app/src/test/kotlin/com/shellx/app/StringsTest.kt` and `git commit -m "test(shellx-android): sign-in, deletion and demo strings"`.
- [ ] **Step 5: Mark the iPhone-only keys.** Append these keys to `strings-ios-only.txt`, under a comment `# Plan 1C: Sign in with Apple, and the password-session switch that Android never has`.
  - Keys: `signin.apple.linkDenied`, `signin.apple.linkExpired`, `signin.apple.linkFailed`, `appleLink.title`, `appleLink.intro`, `signin.error.emailInUse`, `signin.error.identityInUse`, `settings.account.switchToGoogle`, `settings.account.switchToGoogle.detail`, `settings.account.delete.switchFirst`, `switchToGoogle.banner.switch`, `switchToGoogle.banner.later`.
  - Write each key exactly as in the catalog. Leave out a key the catalog does not have: the importer refuses a missing one.
- [ ] **Step 6: Add the Android wording and the Android-only strings.** Add each name to both `strings_android.xml` files, en then vi, escaped as 3A's importer escapes (`'` → `\'`):

  | Name | en | vi |
  | --- | --- | --- |
  | `signin_subtitle` | Use the Google account you use with ShellX on your Mac. | Dùng tài khoản Google bạn dùng với ShellX trên Mac. |
  | `signin_error_reauth_required` | Sign in with the Google account this ShellX account uses, then try again. | Hãy đăng nhập bằng tài khoản Google mà tài khoản ShellX này dùng, rồi thử lại. |
  | `settings_account_delete_message` | This deletes your ShellX account for good. Every Mac and phone signed in to it is signed out, its pairings and shared sessions end, and this phone's history is removed. To confirm, you sign in once more. | Thao tác này xoá vĩnh viễn tài khoản ShellX của bạn. Mọi Mac và điện thoại đang đăng nhập bị đăng xuất, các ghép cặp và phiên chia sẻ kết thúc, lịch sử trên điện thoại này bị xoá. Để xác nhận, bạn đăng nhập lại một lần. |
  | `nav_back` | Back | Quay lại |
  | `row_actions` | show actions | hiện tác vụ |
  | `action_open_agent` | open the agent's chat | mở cuộc trò chuyện với agent |
  | `action_open_your_macs` | open Your Macs | mở Máy của bạn |

  The last three are `onClickLabel` and `onLongClickLabel` texts: TalkBack reads them after "Double-tap to" and "Double-tap and hold to".
- [ ] **Step 7: Generate and resolve the rest.** Run `python3 shellx-android/scripts/import-strings.py && python3 shellx-android/scripts/import-strings.py --check`.

  Expected: `import-strings: ok (…)`. If any other key is refused, apply 3A Task 11 Step 1's rule:
  - an iPhone-only feature goes to `strings-ios-only.txt`;
  - otherwise add an override that changes only the platform words.

  Then add a row to "iPhone changes since the reference" for each.
- [ ] **Step 8: Run (green).** Run the Step 3 command, then `shellx-android/scripts/dev.sh test app`.

  Expected: 4 tests; `==> test app: passed`.
- [ ] **Step 9: Ledger and commit.**
  - Add an `A-` row with State `done (3D)`:
    - difference: "Android wording for three plan-1C strings (`signin_subtitle`, `signin_error_reauth_required`, `settings_account_delete_message`): Google only, phone for iPhone; 1C's Apple and password-switch keys are in `strings-ios-only.txt`";
    - why: "S3 §3: no Apple sign-in and no password session on Android";
    - Android: `res/values*/strings_android.xml`.
  - Run `git add shellx-android/scripts/strings-ios-only.txt shellx-android/app/src/main/res docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): sign-in, deletion and demo strings from the iPhone, with Android wording"`.

---

### Task 3: Clock, settings store, device name, network watcher and the Flutter clean-up

**Files:**
- Create in `app/platform/`: `AndroidClock.kt`, `DataStoreKeyValueStore.kt`, `DeviceName.kt`, `NetworkPathWatcher.kt`, `LegacyFlutterCleanup.kt`
- Modify: `docs/superpowers/ledgers/shellx-android-parity.md`
- Test in `app-test/platform/`: `AndroidClockTest.kt`, `DataStoreKeyValueStoreTest.kt`, `DeviceNameTest.kt`, `NetworkPathWatcherTest.kt`, `LegacyFlutterCleanupTest.kt`

**Interfaces:**
- Consumes: 3C's `Clock`, `KeyValueStore`, `NetworkMonitor`, `NetworkPath`, `CoreLog`.
- Produces (`com.shellx.app.platform`):

```kotlin
/** Counts deep sleep (SystemClock.elapsedRealtimeNanos), as 3C's Clock.monotonic requires. */
object ElapsedRealtimeTimeSource : AbstractLongTimeSource(DurationUnit.NANOSECONDS)
/** nowMs = System.currentTimeMillis(); monotonic = ElapsedRealtimeTimeSource. */
object AndroidClock : Clock
/** KeyValueStore over DataStore Preferences (S3 §7.3): reads come from an in-memory map filled once at load; a write
 *  changes the map at once and reaches the file in call order, on `scope` (IO). Thread-safe. */
class DataStoreKeyValueStore private constructor(/* store, map, scope */) : KeyValueStore {
    /** Waits until every write made so far is on disk. */
    suspend fun flush()
    companion object {
        /** Damaged file → empty (ReplaceFileCorruptionHandler); unreadable → empty and CoreLog "settings_load_failed". */
        suspend fun load(file: File, scope: CoroutineScope): DataStoreKeyValueStore
        fun file(context: Context): File               // File(context.noBackupFilesDir, "settings.preferences_pb")
    }
}
object DeviceName {
    const val MAX_CODE_POINTS = 100                    // relay/src/auth/device.ts DEVICE_NAME_MAX_CHARS
    /** The first non-blank of settingName and model, trimmed, else "Android"; cut to MAX_CODE_POINTS code points. */
    fun of(settingName: String?, model: String?): String
    fun current(context: Context): String              // of(Settings.Global DEVICE_NAME, Build.MODEL)
}
object NetworkPaths {
    /** status "satisfied" with internet, else "unsatisfied"; interfaces = listOfNotNull(interfaceName). */
    fun of(hasInternet: Boolean, interfaceName: String?, defaultGateways: List<String>): NetworkPath
}
/** NetworkMonitor (contracts §5) over ConnectivityManager.registerDefaultNetworkCallback (S3 §7.3). The current path
 *  first, then one per change; unregisters when collection ends. */
class NetworkPathWatcher(connectivity: ConnectivityManager) : NetworkMonitor
interface KeystoreAliases { fun list(): List<String>; fun delete(alias: String) }
object AndroidKeystoreAliases : KeystoreAliases     // KeyStore "AndroidKeyStore"
object LegacyFlutterCleanup {
    const val DONE_KEY = "shellx.legacyFlutterCleaned"
    /** S3 §3: deletes the old Flutter app's leftovers once. Returns true when everything is gone (DONE_KEY then true). */
    fun run(dataDir: File, settings: KeyValueStore, keystore: KeystoreAliases = AndroidKeystoreAliases): Boolean
}
```

- [ ] **Step 1: Write the failing tests.** Each comment line is one `@Test` with those values.

```kotlin
class DataStoreKeyValueStoreTest {   // TemporaryFolder rule; runBlocking; each store gets CoroutineScope(SupervisorJob() + Dispatchers.IO)
    // valuesSurviveARelaunch: putString("a","1"), putBoolean("b",true), flush(); cancel and join the scope; load() again → "1", true
    // readsSeeAWriteAtOnce: putString("a","2") → getString("a") == "2" with no flush
    // writesReachTheFileInCallOrder: for i in 0 until 200 putString("k", if (i % 7 == 0) null else "$i"); flush; relaunch →
    //   getString("k") == "199"
    // nullAndRemoveDeleteTheKey: putString("a","1"); putString("a", null) → null; putBoolean("b",true); remove("b") → false;
    //   both still so after flush and a relaunch
    // aDamagedFileStartsEmpty: write "not a protobuf" into the file → load → getString("a") == null; putString("a","3"), flush,
    //   relaunch → "3"
    // aKeyKeepsItsType: putBoolean("x", true) → getString("x") == null, getBoolean("x") == true
}
class DeviceNameTest {
    // theSettingNameComesFirst: of("  Phu's Pixel  ", "Pixel 9") == "Phu's Pixel"
    // aBlankSettingFallsBackToTheModel: of(" ", "Pixel 9") == "Pixel 9"; of(null, "Pixel 9") == "Pixel 9"
    // nothingAtAllIsAndroid: of(null, "  ") == "Android"
    // longNamesAreCutToTheRelaysLimit: of("é".repeat(150), null).codePointCount == 100; of("📱".repeat(120), null) has
    //   100 code points and ends with a whole surrogate pair
}
class LegacyFlutterCleanupTest {   // TemporaryFolder as dataDir; MemoryKeyValueStore; a fake KeystoreAliases
    // theFlutterAppsDataGoesOnce: dataDir has app_flutter/state.json, shared_prefs/FlutterSharedPreferences.xml,
    //   shared_prefs/FlutterSecureStorage.xml, shared_prefs/com.google.firebase.messaging.xml and files/keep.txt; aliases
    //   ["com.shellx.prod.FlutterSecureStoragePluginKey", "shellx.secrets.v1", "other"] → run == true; app_flutter and the
    //   two Flutter files are gone; the Firebase file and keep.txt stay; deleted aliases == the Flutter one; DONE_KEY true.
    //   Then recreate app_flutter/state.json → run == true and it stays (done once)
    // aFailureLeavesTheMarkOff: list() throws KeyStoreException → the files are still deleted; run == false; DONE_KEY false
}
class AndroidClockTest {
    // monotonicCountsTheTimeTheSystemClockMoved: mark; ShadowSystemClock.advanceBy(java.time.Duration.ofSeconds(26)) →
    //   mark.elapsedNow() == 26.seconds
    // wallTimeIsEpochMilliseconds: abs(AndroidClock.nowMs() - System.currentTimeMillis()) < 1_000
}
class NetworkPathWatcherTest {
    // pathsDecideOnInternetInterfaceAndGateways: of(true, "wlan0", ["192.168.1.1"]) == NetworkPath("satisfied", ["wlan0"],
    //   ["192.168.1.1"]); of(false, null, emptyList()).status == "unsatisfied"; equal inputs → equal paths; another gateway → not equal
    // theWatcherStartsWithTheCurrentPathAndUnregisters: runBlocking { NetworkPathWatcher(cm).paths.first() } returns a path;
    //   afterwards shadowOf(cm).networkCallbacks is empty
}
```

- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.platform.*'`.

  Expected: `BUILD FAILED`, with `Unresolved reference: DataStoreKeyValueStore`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test` and `git commit -m "test(shellx-android): clock, settings store, device name, network watcher, Flutter clean-up"`.
- [ ] **Step 4: Implement.**
  - **`DataStoreKeyValueStore`.**
    - Make the store with `PreferenceDataStoreFactory.create(corruptionHandler = ReplaceFileCorruptionHandler { emptyPreferences() }, scope = scope, produceFile = { file })`.
    - The memory is a `ConcurrentHashMap<String, Any>`, filled from `data.first().asMap()` (by key name). `getString` is `map[key] as? String`; `getBoolean` is `map[key] as? Boolean ?: false`.
    - One writer coroutine in `scope` drains a `Channel<Write>(UNLIMITED)` of `Put(key, value: Any?)` and `Flush(done: CompletableDeferred<Unit>)`.
    - `Put` runs `edit`: a null value removes `stringPreferencesKey(key)` (removal goes by name); a `String` or `Boolean` sets its typed key.
    - An `IOException` logs `settings_write_failed` and the writer goes on. A `CancellationException` is rethrown.
  - **`NetworkPathWatcher`.**
    - `callbackFlow`: first `trySend(path(activeNetwork caps, activeNetwork link))`, then `registerDefaultNetworkCallback`.
    - The callback keeps the last `NetworkCapabilities` and `LinkProperties`, sends a path on `onCapabilitiesChanged` and `onLinkPropertiesChanged`, and on `onLost` clears both and sends.
    - The path is `NetworkPaths.of(caps?.hasCapability(NET_CAPABILITY_INTERNET) == true, link?.interfaceName, link?.routes.orEmpty().filter { it.destination.prefixLength == 0 }.mapNotNull { it.gateway?.hostAddress })`.
    - `awaitClose { unregisterNetworkCallback }`.
  - **`LegacyFlutterCleanup`.**
    - Delete `File(dataDir, "app_flutter")` recursively, every file in `File(dataDir, "shared_prefs")` whose name starts with `Flutter`, and every Keystore alias containing `flutter` (ignoring case).
    - Each failure logs `legacy_cleanup_failed` and the rest goes on. Set `DONE_KEY` only when nothing failed. When `DONE_KEY` is already set, return true at once and touch nothing.
- [ ] **Step 5: Run (green).** Run the Step 2 command.

  Expected: PASS. `DataStoreKeyValueStoreTest` 6, `DeviceNameTest` 4, `LegacyFlutterCleanupTest` 2, `AndroidClockTest` 2, `NetworkPathWatcherTest` 2.
- [ ] **Step 6: Ledger and commit.**
  - Add an `A-` row, State `done (3D)`:
    - difference: "The first launch deletes what the old Flutter app (same app id) left: `app_flutter/`, `shared_prefs/Flutter*`, its Keystore aliases";
    - why: "S3 §3: the native app reads none of the Flutter data and cleans it at first open";
    - Android: `app:platform/LegacyFlutterCleanup.kt`.
  - Run `git add shellx-android/app/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): clock, DataStore settings, device name, network watcher, Flutter clean-up"`.

---

### Task 4: The Keystore secret store

**Files:**
- Create: `app/platform/KeystoreSecretStore.kt`
- Test: `app-test/platform/KeystoreSecretStoreTest.kt`

Reference: `ios/Platform/KeychainSecretStore.swift`, `ios-tests/KeychainSecretStoreTests.swift`; 3C Task 6 (the `SecretStore` contract: unreadable reads as null after deleting; `Unavailable` only while the data is still there).

**Interfaces:**
- Consumes: 3C's `SecretStore`, `SecretItem`, `SecretStoreException`.
- Produces (`com.shellx.app.platform`):

```kotlin
/** The Keystore key the store encrypts with. Throws KeyStoreException, ProviderException or GeneralSecurityException. */
fun interface SecretKeyProvider { fun key(): SecretKey }
/** AES-256-GCM key in the Android Keystore: non-exportable, no user authentication, made on first use. Synchronized. */
class AndroidKeystoreKey(private val alias: String = ALIAS) : SecretKeyProvider { companion object { const val ALIAS = "shellx.secrets.v1" } }
/** SecretStore over the Keystore (S3 §7.3): one file per item in `directory`, never backed up. Blocking; 3C's AccountVault
 *  calls it on its io dispatcher. */
class KeystoreSecretStore(private val directory: File, private val keys: SecretKeyProvider = AndroidKeystoreKey()) : SecretStore {
    companion object { fun directory(context: Context): File }      // File(context.noBackupFilesDir, "secrets")
}
```

  **The file scheme:**
  - The file is `<directory>/<item.account>.bin` = `0x01` (format version) ‖ IV (12 bytes) ‖ ciphertext with its 16-byte tag.
  - AAD = UTF-8 of `"shellx-secret/1/" + item.account`, so a file copied onto another item does not open.
  - **Write.** `Cipher.getInstance("AES/GCM/NoPadding")`, `init(ENCRYPT_MODE, key)` (the provider picks the IV; read `cipher.iv`), `updateAAD`, `doFinal`. Write `<name>.tmp`, `fd.sync()`, then `renameTo(<name>.bin)`. Create the directory with `mkdirs()`. Any failure, the key included → `SecretStoreException.Failed(cause)`.
  - **Read.**
    - no file → null;
    - an `IOException` reading it → `Unavailable(cause)`;
    - `keys.key()` throws `KeyStoreException` or `ProviderException` → `Unavailable(cause)`, and the file stays;
    - any other key failure (`UnrecoverableKeyException`, `KeyPermanentlyInvalidatedException`, `InvalidKeyException`), a wrong version byte, a file under 29 bytes, or an `AEADBadTagException` → delete the file and return null.
    - Decrypt with `GCMParameterSpec(128, iv)`.
  - **Delete.** A missing file is fine; a file that will not delete → `Failed`.
  - **`AndroidKeystoreKey.key()`.** `KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.getKey(alias, null) as SecretKey?`, else generate it with `KeyGenerator.getInstance("AES", "AndroidKeyStore")` and `KeyGenParameterSpec.Builder(alias, PURPOSE_ENCRYPT or PURPOSE_DECRYPT)`, with `BLOCK_MODE_GCM`, `ENCRYPTION_PADDING_NONE`, key size 256 and randomized encryption required.

- [ ] **Step 1: Write the failing tests.** Every test except the last uses an in-memory key: `val k = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey(); SecretKeyProvider { k }`.

```kotlin
class KeystoreSecretStoreTest {   // TemporaryFolder rule
    // writeReadDeleteRoundTrips (port of testWriteReadDelete): read null; write "one" → "one"; write "two" → "two" (replaces);
    //   delete → null; delete again does not throw
    // filesAreEncryptedAndBoundToTheirItem: write "token-secret" as SESSION → the file's bytes do not contain "token-secret";
    //   copy session.bin over phone-key.bin → read(PHONE_KEY) == null and phone-key.bin is gone; read(SESSION) still works
    // aLostKeyReadsAsAbsentAndDeletesTheFile (RF 4): write with key A; a store over the same directory with key B → read null,
    //   file gone; then write/read with B works
    // aBusyKeystoreIsUnavailableAndKeepsTheFile (RF 4): write; a store whose provider throws KeyStoreException → read throws
    //   SecretStoreException.Unavailable, the file is still there; write throws SecretStoreException.Failed
    // aDamagedFileReadsAsAbsent: flip the last byte → null and deleted; a 10-byte file → null and deleted; version byte 2 → null
    // noTemporaryFileStays: after write, the directory holds only "session.bin"
    // theDirectoryIsNotBackedUp: KeystoreSecretStore.directory(context) == File(context.noBackupFilesDir, "secrets")
}
```

- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.platform.KeystoreSecretStoreTest'`.

  Expected: `Unresolved reference: KeystoreSecretStore`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test` and `git commit -m "test(shellx-android): Keystore secret store"`.
- [ ] **Step 4: Implement** the scheme above.
- [ ] **Step 5: Run (green).** Expected: PASS, 7 tests.
- [ ] **Step 6: Commit.** Run `git add shellx-android/app/src/main` and `git commit -m "feat(shellx-android): secrets in files sealed by an Android Keystore key"`.

---

### Task 5: Google identity through Credential Manager

**Files:**
- Create: `app/platform/CredentialManagerIdentity.kt` (with `GoogleWebClient`, `CredentialGetter`, `IdentityErrors`), `app/platform/ActivityTracker.kt`
- Test: `app-test/platform/CredentialManagerIdentityTest.kt`, `app-test/platform/GoogleWebClientTest.kt`

Reference: S1 §6.7; contracts §14 (`IdentityProviding`), §16 (the Web client resource); 3C Task 14 (`IdentityProviderException`).

**Interfaces:**
- Consumes: 3C's `IdentityProviding`, `IdentityProviderException`; Task 1's `R.string.google_web_client_id`.
- Produces (`com.shellx.app.platform`):

```kotlin
object GoogleWebClient {
    const val PLACEHOLDER = "0-shellx-placeholder.apps.googleusercontent.com"
    /** Not the placeholder, and of the form ^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$. */
    fun isReal(id: String): Boolean
    fun id(context: Context): String?            // R.string.google_web_client_id when isReal, else null
}
fun interface CredentialGetter { suspend fun get(activity: Activity, request: GetCredentialRequest): GetCredentialResponse }
object IdentityErrors {
    /** GetCredentialCancellationException → Cancelled; GetCredentialProviderConfigurationException,
     *  GetCredentialUnsupportedException → NotConfigured; any other GetCredentialException → Failed. */
    fun of(error: GetCredentialException): IdentityProviderException
}
/** The current (latest resumed, not destroyed) activity, weakly held; registered by ShellXApplication (Task 8). */
object ActivityTracker : Application.ActivityLifecycleCallbacks { fun current(): Activity? }
/** IdentityProviding over Credential Manager (S1 §6.7): GetSignInWithGoogleOption with serverClientId = the Web client
 *  (contracts §16) and setNonce(the relay's nonce). */
class CredentialManagerIdentity(private val serverClientId: String?, private val activity: () -> Activity?,
                                private val getter: CredentialGetter) : IdentityProviding {
    override suspend fun googleIdToken(nonce: String): String
    companion object { fun create(context: Context): CredentialManagerIdentity }  // GoogleWebClient.id, ActivityTracker::current, CredentialManager.create(context)::getCredential
}
```

  `googleIdToken`, in this order:
  1. `serverClientId == null` → `NotConfigured()`; the getter is not called.
  2. No activity → `Failed()`.
  3. Request `GetCredentialRequest.Builder().addCredentialOption(GetSignInWithGoogleOption.Builder(serverClientId).setNonce(nonce).build()).build()`.
  4. A `CustomCredential` of type `GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL` → `GoogleIdTokenCredential.createFrom(data).idToken`. Any other credential, or a `GoogleIdTokenParsingException` → `Failed()`.
  5. A `GetCredentialException` → `IdentityErrors.of(it)`. A `CancellationException` is rethrown.

- [ ] **Step 1: Write the failing tests.** The activity is `Robolectric.buildActivity(ComponentActivity::class.java).setup().get()`; the getter is a fake that records the request.

```kotlin
class GoogleWebClientTest {
    // theShippedResourceIsThePlaceholderUntilPlan1D: GoogleWebClient.id(context) == null when the resource is PLACEHOLDER
    //   (if plan 1D has filled it, assert id(context) == the resource instead)
    // onlyAWebClientIdIsReal: isReal("123-abc.apps.googleusercontent.com"); !isReal(PLACEHOLDER); !isReal(""); !isReal("abc")
}
class CredentialManagerIdentityTest {
    // aPlaceholderClientIsNotConfigured: CredentialManagerIdentity(null, …) → NotConfigured; the getter was not called
    // theRequestCarriesTheWebClientAndTheRelayNonce: the getter answers GetCredentialResponse(CustomCredential(
    //   GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL, GoogleIdTokenCredential.Builder().setId("a@b.c")
    //   .setIdToken("id-token-1").build().data)) → googleIdToken("n-1") == "id-token-1"; the request's one option is a
    //   GetSignInWithGoogleOption with serverClientId "123-abc.apps.googleusercontent.com" and nonce "n-1"
    // closingGoogleSheetIsCancelled: GetCredentialCancellationException("x") → IdentityProviderException.Cancelled
    // noProviderIsNotConfigured: GetCredentialProviderConfigurationException("x") and GetCredentialUnsupportedException("x") → NotConfigured
    // otherFailuresAreFailed: NoCredentialException("x"), GetCredentialUnknownException("x"), a PasswordCredential("u","p")
    //   response, and activity = { null } → Failed each time
}
```

- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.platform.CredentialManagerIdentityTest' --tests 'com.shellx.app.platform.GoogleWebClientTest'`.

  Expected: `Unresolved reference: CredentialManagerIdentity`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test` and `git commit -m "test(shellx-android): Google ID token through Credential Manager"`.
- [ ] **Step 4: Implement.** `ActivityTracker` sets its `WeakReference` in `onActivityResumed` and `onActivityStarted`, and clears it in `onActivityDestroyed` when the activity is the one it holds. If an exception constructor in a test is not public in this library version, drop that case, and list it in the report.
- [ ] **Step 5: Run (green).** Expected: PASS, 2 and 5 tests.
- [ ] **Step 6: Commit.** Run `git add shellx-android/app/src/main` and `git commit -m "feat(shellx-android): Google sign-in identity over Credential Manager"`.

---

### Task 6: Theme switch, state styles and shared components

**Files:**
- Create in `app/ui/theme/`: `AppAppearance.kt` (`AppAppearance`, `AppAppearanceStore`, `ShellXAppTheme`), `AppLanguage.kt`, `AgentStateStyle.kt` (with `StatusTone`), `MachineStateStyle.kt` (with `StatusDot`)
- Create in `app/ui/components/`: `PrimaryButtonStyle.kt` (`PrimaryButton`), `SecondaryButtonStyle.kt` (`SecondaryButton`), `WaitingBorder.kt`, `ActionRow.kt` (`RowAction`, `ActionRow`), `RowActions.kt`, `Dialogs.kt` (`ConfirmDialog`, `MessageDialog`), `SectionTitle.kt`, `Ticker.kt` (`HomeTicks`, `rememberNowMs`), `LargeText.kt` (`isLargeText`), `Savers.kt` (`WorkspaceRefSaver`, `SessionRefSaver`)
- Create (test support): `app-ui-test/screenshots/RenderAssertions.kt` (`assertRenders`, `LargeText`), `app-ui-test/screenshots/PixelChecks.kt` (`chroma`)
- Modify: `docs/superpowers/ledgers/shellx-android-parity.md`
- Test: `app-test/ui/theme/AppAppearanceTest.kt`, `app-test/ui/theme/StylesTest.kt`, `app-test/ui/components/WaitingBorderTest.kt`, `app-test/ui/components/RowActionsTest.kt`, `app-ui-test/ui/components/ComponentsTest.kt`, `app-ui-test/screenshots/WaitingBorderRenderTest.kt`

Reference: `ios/UI/Theme/{AppAppearance,AgentStateStyle,MachineStateStyle,Locale+App}.swift`, `ios/UI/Components/{PrimaryButtonStyle,SecondaryButtonStyle,WaitingBorder}.swift`, `ios-tests/{AppearanceTests,WaitingBorderRenderTests}.swift`; 3E Task 7 and Task 1 (the shapes of `StatusTone`, `AgentStateStyle`, `StatusDot`, `assertRenders` and `LargeText`).

**Interfaces:**
- Consumes: 3A's `ShellXTheme`, `ShellXColors`, `ShellXSnapshots`, `Snapshot`; 3B's `AgentState` (`com.shellx.link.core`); 3C's `KeyValueStore`, `AgentStatusRow`, `MachineLinkState`, `WorkspaceRef`, `SessionRef`, `Clock`.
- Produces:

```kotlin
// com.shellx.app.ui.theme
enum class AppAppearance(val stored: String, @StringRes val title: Int) {
    SYSTEM("system", R.string.settings_appearance_system), LIGHT("light", R.string.settings_appearance_light),
    DARK("dark", R.string.settings_appearance_dark);
    fun isDark(systemDark: Boolean): Boolean
    companion object { const val STORAGE_KEY = "shellx.appearance"; fun fromStored(value: String?): AppAppearance }  // unknown → SYSTEM
}
/** Main-confined. Settings › Appearance (the iPhone's @AppStorage key). */
class AppAppearanceStore(private val settings: KeyValueStore) { val appearance: StateFlow<AppAppearance>; fun set(appearance: AppAppearance) }
/** ShellXTheme(darkTheme = appearance.isDark(isSystemInDarkTheme())). */
@Composable fun ShellXAppTheme(appearance: AppAppearance, content: @Composable () -> Unit)
/** The language the strings show in (the iPhone's Locale.app): Vietnamese when the locale's language is "vi", else English. */
object AppLanguage { fun of(locale: Locale): Locale; @Composable fun current(): Locale }
enum class StatusTone { DONE, ERROR, IDLE, NEEDS_YOU, RUNNING }
@Composable fun StatusTone.color(): Color                       // ShellXTheme.colors.statusDone … statusRunning
data class AgentStateStyle(val text: String?, val shortText: String?, val tone: StatusTone?) {
    companion object {
        fun of(row: AgentStatusRow, res: Resources): AgentStateStyle                                // AgentStateStyle.swift's table
        /** "4 minutes", "1 hour, 5 minutes" (hours and minutes, at most two units, rounded down), or seconds under a minute. */
        fun elapsedText(elapsed: Duration, locale: Locale): String
    }
}
data class MachineStateStyle(val text: String, val tone: StatusTone) {
    companion object { fun of(state: MachineLinkState, machineName: String, res: Resources): MachineStateStyle }
}
@Composable fun StatusDot(color: Color, modifier: Modifier = Modifier)      // (8 * fontScale).dp circle; no semantics
// com.shellx.app.ui.components
@Composable fun PrimaryButton(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, content: @Composable RowScope.() -> Unit)
@Composable fun SecondaryButton(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true,
                                color: Color = ShellXTheme.colors.accentText, content: @Composable RowScope.() -> Unit)
@Composable fun isLargeText(): Boolean                                         // LocalDensity.current.fontScale >= 1.3f
object WaitingBorder {
    val PALETTE: List<Long> = listOf(0xFF60A5FA, 0xFFA78BFA, 0xFFF472B6, 0xFFFBBF24, 0xFF60A5FA)
    val LINE_WIDTH: Dp = 2.dp; val TURN: Duration = 3.seconds; const val FRAMES_PER_SECOND = 30
    fun isActive(state: AgentState, online: Boolean): Boolean                  // online && state == NEEDS_INPUT
    fun angle(atMs: Long): Float                                               // degrees in [0, 360), one turn per TURN
    fun animates(animatorsEnabled: Boolean): Boolean                           // = animatorsEnabled
}
fun Modifier.waitingBorder(isActive: Boolean, cornerRadius: Dp): Modifier
data class RowAction(val label: String, val icon: ImageVector, val destructive: Boolean, val run: () -> Unit)
/** A row (S3 §7.2): a swipe from the end runs `swipe`; a long press opens `menu`; TalkBack lists `menu` as custom actions. */
@Composable fun ActionRow(swipe: RowAction?, menu: List<RowAction>, onClick: (() -> Unit)?, onClickLabel: String?,
                          modifier: Modifier = Modifier, enabled: Boolean = true, content: @Composable () -> Unit)
enum class RowActionKind { CLOSE_AGENT, REMOVE_FROM_PHONE, CLOSE_WORKSPACE, RENAME_WORKSPACE, REMOVE_ENDED, MAKE_DEFAULT, PAIR_AGAIN, UNPAIR, REMOVE_MAC }
data class RowActionPlan(val swipe: RowActionKind?, val menu: List<RowActionKind>)
object RowActions {
    fun agentCard(closable: Boolean, removable: Boolean): RowActionPlan
    fun workspaceCard(canControl: Boolean): RowActionPlan
    fun endedCard(): RowActionPlan
    fun otherSessionCard(removable: Boolean): RowActionPlan
    fun machine(state: MachineLinkState, offersMakeDefault: Boolean): RowActionPlan
}
/** Cancel (common_cancel) and confirm; confirm runs onDismiss() then onConfirm(); destructive tints confirm statusError. */
@Composable fun ConfirmDialog(title: String, text: String?, confirmLabel: String, onConfirm: () -> Unit, onDismiss: () -> Unit, destructive: Boolean = true)
@Composable fun MessageDialog(title: String?, text: String, onDismiss: () -> Unit)   // one "OK" (common_ok)
@Composable fun SectionTitle(text: String, modifier: Modifier = Modifier)     // uppercase, labelMedium, 0.6 sp tracking, heading
object HomeTicks { val INTERVAL: Duration = 30.seconds; fun every(interval: Duration = INTERVAL): Flow<Unit> }
@Composable fun rememberNowMs(clock: Clock, ticks: Flow<Unit> = remember { HomeTicks.every() }): Long
val WorkspaceRefSaver: Saver<WorkspaceRef?, Any>; val SessionRefSaver: Saver<SessionRef?, Any>
// app-ui-test/screenshots, exactly 3E Task 1's API (3E keeps these files)
/** ShellXSnapshots.capture with the iPhone render tests' checks: light-en, dark-en, light-vi, dark-vi, each a file 1179 px
 *  wide, and light differs from dark. */
fun assertRenders(name: String, content: @Composable () -> Unit): List<Snapshot>
@Composable fun LargeText(content: @Composable () -> Unit)                 // font scale 2 through LocalDensity
fun chroma(argb: Int): Int                                                 // PixelChecks.kt: max(r, g, b) - min(r, g, b)
```

  **Row actions.** These are the iPhone's swipe and context-menu actions, re-shaped for Android:

  | Row | Swipe | Long-press menu, in order |
  | --- | --- | --- |
  | agent card (home) | `CLOSE_AGENT` if closable, else `REMOVE_FROM_PHONE` if removable, else none | `CLOSE_AGENT` if closable; `REMOVE_FROM_PHONE` if removable |
  | workspace card | `CLOSE_WORKSPACE` if canControl | `RENAME_WORKSPACE`, `CLOSE_WORKSPACE` if canControl; none otherwise |
  | ended card | `REMOVE_ENDED` | `REMOVE_ENDED` |
  | other-session card | `REMOVE_FROM_PHONE` if removable | `REMOVE_FROM_PHONE` if removable |
  | Mac row | `REMOVE_MAC` if `Revoked`, else `UNPAIR` | `MAKE_DEFAULT` if offered; `PAIR_AGAIN` if `HostKeyChanged`; `REMOVE_MAC` if `Revoked`, else `UNPAIR` |

  **How each kind looks.** The screens turn a kind into a `RowAction`:

  | Kind | Menu label | Swipe label | Icon | Destructive | What follows |
  | --- | --- | --- | --- | --- | --- |
  | `CLOSE_AGENT` | `agent_close_menu` | `agent_close` | `Icons.Filled.Close` | yes | `AgentCloseConfirmation` |
  | `REMOVE_FROM_PHONE` | `agent_remove_from_phone` | same | `Icons.Outlined.Delete` | yes | at once |
  | `CLOSE_WORKSPACE` | `workspace_menu_close` | `workspaces_close` | `Icons.Filled.Close` | yes | `ConfirmDialog` |
  | `RENAME_WORKSPACE` | `workspace_menu_rename` | — | `Icons.Outlined.Edit` | no | rename sheet |
  | `REMOVE_ENDED` | `ended_remove` | same | `Icons.Outlined.Delete` | yes | at once |
  | `MAKE_DEFAULT` | `machines_make_default` | — | `Icons.Outlined.StarOutline` | no | at once |
  | `PAIR_AGAIN` | `machines_pair_again` | — | `Icons.Filled.QrCodeScanner` | no | pairing |
  | `UNPAIR` | `machines_unpair` | same | `Icons.Outlined.RemoveCircleOutline` | yes | `ConfirmDialog` |
  | `REMOVE_MAC` | `machines_remove` | same | `Icons.Outlined.Delete` | yes | at once |

  **`ActionRow`.**
  - It wraps `content` in `SwipeToDismissBox`, with `enableDismissFromStartToEnd = false`, `enableDismissFromEndToStart = swipe != null && enabled`, and `gesturesEnabled = swipe != null && enabled`.
  - The background is `statusError` for a destructive swipe, else `accentText`, with the swipe's icon and label at the end edge in white.
  - A swipe past the threshold runs `swipe.run()` once, and the row returns to rest. On material3 1.4 or later, use the `onDismiss` parameter, then `state.reset()`. On older versions, use `confirmValueChange` that runs the action on `EndToStart` and returns false; guard it so one gesture runs it once.
  - Inside, `Modifier.combinedClickable(onClick, onClickLabel, onLongClick = { haptic LongPress; open the menu }, onLongClickLabel = stringResource(R.string.row_actions))`. Leave out the long press when `menu` is empty.
  - The menu is a `DropdownMenu` of `DropdownMenuItem`s (icon and label, `statusError` when destructive); choosing an item closes the menu, then runs it.
  - `Modifier.semantics { customActions = menu.map { CustomAccessibilityAction(it.label) { it.run(); true } } }`.
  - `enabled = false` turns off the clicks, the gestures and the custom actions, and draws the row at 38 % alpha.

  **`Modifier.waitingBorder`** (the algorithm the tests do not fix).
  - Use `Modifier.composed`.
  - Inactive: return `this`.
  - Active: `var angle by remember { mutableFloatStateOf(0f) }`. When `WaitingBorder.animates(ValueAnimator.areAnimatorsEnabled())`, run `LaunchedEffect(Unit) { while (true) withInfiniteAnimationFrameMillis { angle = WaitingBorder.angle(System.currentTimeMillis() / 33 * 33) } }`. The infinite-animation frame lets Compose tests go idle, and the quantised time caps redraws at 30 frames a second, in step across cards.
  - Draw with `drawWithContent { drawContent(); … }`, reading `angle` there only (a redraw, no recomposition):
    - a `ShaderBrush` whose shader is `SweepGradientShader(center, PALETTE colours)` with `setLocalMatrix(Matrix().apply { setRotate(angle, center.x, center.y) })`;
    - stroked as `drawRoundRect(brush, topLeft = Offset(w / 2, w / 2), size = Size(size.width - w, size.height - w), cornerRadius = CornerRadius(r - w / 2), style = Stroke(w))`, where `w = LINE_WIDTH.toPx()`.
  - No semantics.

  **`AgentStateStyle.of`** (the iPhone's table).
  - Not online → `agent_state_offline`, short text the same, `IDLE`.
  - `NEEDS_INPUT` → `agent_state_needs_you`, `NEEDS_YOU`.
  - `WORKING` → `agent_state_running_for` with `elapsedText` when elapsed is known, else `agent_state_running`. The short text is the elapsed text, or `agent_state_running`. The tone is `RUNNING`.
  - `IDLE` → `agent_state_done`, `DONE`.
  - `ENDED` → `agent_state_ended`, `IDLE`.
  - Any other wire value → all null.
  - The locale is `AppLanguage.of(res.configuration.locales[0])`.
  - `elapsedText` uses `android.icu.text.MeasureFormat.getInstance(ULocale.forLocale(locale), FormatWidth.WIDE)`: under 60 s, `format(Measure(seconds, MeasureUnit.SECOND))`; otherwise `formatMeasures` of hours (when > 0) and minutes (when > 0, or when hours is 0).

  **`MachineStateStyle.of`.**
  - `Online` → `machine_state_online`, `DONE`.
  - `Connecting` and `Reconnecting` → `machine_state_connecting`, `RUNNING`.
  - `Offline` → `machine_state_offline` (name), `IDLE`.
  - `Revoked` → `machine_state_revoked`, `ERROR`.
  - `HostKeyChanged` → `machine_state_host_key_changed`, `ERROR`.
  - `NeedsUpdate` → `machine_state_needs_update`, `NEEDS_YOU`.

  **Buttons.** `PrimaryButton` is an M3 `Button`: min height 50 dp, `RoundedCornerShape(12.dp)`, horizontal content padding 16 dp, container `accent`, content `onAccent`; disabled, both at 40 % alpha. `SecondaryButton` has container `color` at 14 % alpha and content `color`.

- [ ] **Step 1: Write the failing tests.**

```kotlin
class AppAppearanceTest {
    // storedChoiceDefaultsToMatchPhone (port): fromStored(null) == SYSTEM; fromStored("sepia") == SYSTEM; each round-trips
    // eachChoiceDecidesDarkness: SYSTEM.isDark(true/false) follows; LIGHT.isDark(true) false; DARK.isDark(false) true
    // theStoreKeepsTheChoice: store.set(DARK) → settings.getString("shellx.appearance") == "dark"; a new store over the same
    //   settings starts at DARK; appearance.value == DARK
}
class StylesTest {
    // everyMacStateHasWordsAndATone (port of testEveryStateHasWordsAndAColor): the seven states of MachinesRenderTests'
    //   list → no empty text; online is DONE; connecting == reconnecting; offline names "Mac Studio"; 6 distinct texts
    // agentStatesReadAsOnTheIPhone: offline → "Mac offline" and IDLE; needs input → "Needs you"; working, 4 min →
    //   "Running for 4 minutes" (short "4 minutes"); working, no elapsed → "Running"; idle → "Done", DONE;
    //   ended → "Ended"; AgentState("teleport") → nulls
    // durationsAreInTheAppLanguage: elapsedText(8.minutes, en) == "8 minutes"; 1.minutes → "1 minute"; 45.seconds →
    //   "45 seconds"; 65.minutes → "1 hour, 5 minutes"; 120.minutes → "2 hours"; elapsedText(8.minutes, vi) == "8 phút"
    // theAppLanguageIsVietnameseOrEnglish: of(Locale("vi","VN")).language == "vi"; of(Locale.FRANCE) and of(Locale.UK) → "en"
}
class WaitingBorderTest {
    // theColoursAndStrokeAreTheSpecifiedOnes (port): PALETTE as in Interfaces; first == last; LINE_WIDTH == 2.dp
    // theGradientTurnsOnceEveryThreeSecondsAtAConstantSpeed (port): TURN == 3.seconds; angle(0) == 0; 750 → 90; 1500 → 180;
    //   2250 → 270; 3000 → 0; 4500 → 180; 300750 → 90 (each ±0.001); FRAMES_PER_SECOND == 30
    // onlyAnAgentThatWaitsForTheUserHasTheBorder (port): isActive(NEEDS_INPUT, true); not WORKING, IDLE, ENDED,
    //   AgentState("thinking"); not (NEEDS_INPUT, false)
    // reduceMotionKeepsTheBorderStill (port): animates(true) && !animates(false)
}
class RowActionsTest {
    // agentCards: (true,false) → (CLOSE_AGENT, [CLOSE_AGENT]); (false,true) → (REMOVE_FROM_PHONE, [REMOVE_FROM_PHONE]);
    //   (true,true) → (CLOSE_AGENT, [CLOSE_AGENT, REMOVE_FROM_PHONE]); (false,false) → (null, [])
    // workspaceCards: true → (CLOSE_WORKSPACE, [RENAME_WORKSPACE, CLOSE_WORKSPACE]); false → (null, [])
    // sessionListCards: endedCard() → (REMOVE_ENDED, [REMOVE_ENDED]); otherSessionCard(false) → (null, [])
    // macRows: (Online, true) → (UNPAIR, [MAKE_DEFAULT, UNPAIR]); (HostKeyChanged, false) → (UNPAIR, [PAIR_AGAIN, UNPAIR]);
    //   (Revoked, false) → (REMOVE_MAC, [REMOVE_MAC]); (Offline(1), true) → (UNPAIR, [MAKE_DEFAULT, UNPAIR])
}
```

```kotlin
// app-ui-test/ui/components/ComponentsTest.kt (createComposeRule, content inside ShellXTheme)
class ComponentsTest {
    // aSwipeRunsTheSwipeActionOnceAndTheRowStays: ActionRow(swipe = counting "Close") over Text("row") tagged "row" →
    //   performTouchInput { swipeLeft() } → count 1, "row" displayed; again → 2
    // aLongPressOpensTheMenuAndRunsTheChosenAction: menu ["Rename", "Close"] → longClick → both shown in that order;
    //   click "Close" → its count 1, the menu is gone
    // talkBackListsTheMenuAsCustomActions: the node's SemanticsProperties.CustomActions labels == ["Rename", "Close"]
    // aRowWithoutActionsNeitherSwipesNorHasAMenu: swipe = null, menu = [] → swipeLeft and longClick change nothing; no CustomActions
    // aDisabledRowIgnoresItsActions: enabled = false → swipe and click do nothing
    // confirmRunsOnceAndCloses: ConfirmDialog over a `var shown` → click confirm → onConfirm 1, dialog text gone
    // nowFollowsTheTicks: a local manual Clock shows its nowMs through rememberNowMs(clock, ticks); its wall time += 31_000;
    //   ticks.tryEmit(Unit) → the new value is displayed
    // appearanceOverridesTheSystem: ShellXAppTheme(DARK) → MaterialTheme.colorScheme.background == ShellXColors.Dark.background;
    //   under @Config(qualifiers = "night"), LIGHT → ShellXColors.Light.background
}
```

  `WaitingBorderRenderTest` (RF of the iPhone's frame test):
  - `aBorderedCardHasAColouredTopEdgeAndAPlainOneDoesNot`. Capture `waiting-border-card` and `waiting-border-card-plain` with `assertRenders`.
  - Each draws `Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) { Box(Modifier.padding(16.dp).fillMaxWidth().height(64.dp).clip(RoundedCornerShape(14.dp)).background(ShellXTheme.colors.surface).waitingBorder(active, 14.dp)) }`.
  - In every returned shot, take pixel row `y = 49`, for `x` in `90 until width - 90` (inside the stroke, clear of the corners at xxhdpi).
  - Bordered: at least half of those pixels have `chroma > 80`, and the largest colour distance between two of them is over 100. Plain: no pixel has `chroma > 40`.
- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.ui.theme.*' --tests 'com.shellx.app.ui.components.*' --tests 'com.shellx.app.screenshots.WaitingBorderRenderTest'`.

  Expected: `Unresolved reference: AppAppearance`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test shellx-android/app/src/testDebug` and `git commit -m "test(shellx-android): appearance, state styles and shared components"`.
- [ ] **Step 4: Implement** everything in Interfaces.
- [ ] **Step 5: Run (green).** Expected: PASS.
  - `AppAppearanceTest` 3, `StylesTest` 4, `WaitingBorderTest` 4, `RowActionsTest` 4, `ComponentsTest` 8, `WaitingBorderRenderTest` 1.
  - Then `shellx-android/scripts/dev.sh test app` passes.
- [ ] **Step 6: Ledger and commit.**
  - Add an `A-` row:
    - difference: "A row's actions: a swipe from the end runs the primary one (the iPhone's first swipe button), a long press opens a menu of all of them, and TalkBack lists them as custom actions; touch targets are 48 dp, not 44 pt";
    - why: "S3 §7.2 (Android interactions; Material's minimum touch target)";
    - Android: `app:ui/components/{ActionRow,RowActions}.kt`.
  - Run `git add shellx-android/app/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): appearance switch, state styles, buttons, waiting border, row actions, dialogs"`.

---

### Task 7: The composition root, routes and the two accounts

**Files:**
- Create in `app/`: `AppComposition.kt` (with `RelayBundle`), `AppEnvironment.kt`, `AccountGraph.kt` (with `SignedInScopes`), `SignedInScope.kt`, `LaunchMark.kt`, `Stubs.kt` (`NoSpeechEngine`, `NoVoicePermissions`, `NoPushRegistrar`, `NoAttachmentReader`)
- Create: `app/demo/DemoSession.kt`, `app/ui/workspaces/ListNotice.kt` (`ListNotice`, `Notice`), `app/ui/nav/Routes.kt` (with `SessionListKind`), `app/ui/nav/WorkRoutes.kt`, `app/ui/nav/ShellXNavigator.kt`, `app/ui/nav/RootRoutes.kt` (with `RootState`)
- Create (test support, `app-test/testing/`): `ManualClock.kt`, `TestIdentity.kt`, `TestNetworkMonitor.kt`, `ScriptedRelay.kt`, `TestEnvironment.kt`, `RecordingNavigator.kt`, `WaitFor.kt`, `Compositions.kt`
- Test: `app-test/AppCompositionTest.kt`, `app-test/LaunchMarkTest.kt`, `app-test/demo/DemoSessionTest.kt`, `app-test/ui/nav/RoutesTest.kt`, `app-test/ui/nav/RootRoutesTest.kt`

Reference: `ios/AppComposition.swift`, `ios/AppGraph.swift`, `ios/SignedInScope.swift`, `ios/LaunchMark.swift`, `ios/UI/RootView.swift`, `ios/UI/Home/HomeRoute.swift`, `ios/UI/Workspaces/ListNotice.swift`; 1C Task 13 (`DemoSession`); `ios-tests/{LaunchMarkTests,DemoCompositionTests}.swift`; 3C's "UI wiring summary"; 3E Task 0 (what it reads from `AppComposition` and `SignedInScope`) and Task 12 (`WorkRoutes`).

**Interfaces:**
- Consumes: Tasks 3–6; 3C's `AppCoordinator`, `MachineHub`, `HubState`, `AccountVault`, `RelayAccountCalling`, `MachineLinkConnecting`, `RelayClientFactory`, `LatencyLog`, `LatencyMetric`, `ConversationStore`, `ChatCopySweeper`, `DecisionCenter`, `PairingModel`, `PairingInbox`, `SheetPresence`, `EndedDismissalStore`, `GoneRemovalStore`, `AgentThreadModel`, `PushRegistration`, `PushRegistrar`, `UpdatePrompt`, `UpdateChecker`, `AttachmentReader`, `SpeechEngine`, `VoicePermissionChecking`, `VoiceService`, `DemoEnvironment`, `FakeMac`, `FakeMacFleet`, `DemoRelay`, `DemoSecretStore`, `MemoryKeyValueStore`; 3B's `PairedMachine`, `AccountSignIn`, `AccountSession` (`com.shellx.link.account`, used by the test support).
- Produces:

```kotlin
// com.shellx.app
/** What the shell needs from Android (Task 8 makes the real one; tests make fakes). Not 3E's PlatformServices. */
class AppEnvironment(
    val secrets: SecretStore, val settings: KeyValueStore, val network: NetworkMonitor, val clock: Clock,
    val identity: IdentityProviding, val io: CoroutineDispatcher, val historyDirectory: File, val demoHistoryDirectory: File,
    val deviceName: String, val appVersion: String, val versionCode: Long, val debugBuild: Boolean, val apiBase: String,
)   // Task 8 adds `companion object { suspend fun android(app: Application): AppEnvironment }`
object NoSpeechEngine : SpeechEngine             // start → a closed channel; finish → ""; cancel does nothing
object NoVoicePermissions : VoicePermissionChecking   // needsPrompt false; microphone false; speech false
object NoPushRegistrar : PushRegistrar           // currentToken() = null
object NoAttachmentReader : AttachmentReader     // read throws AttachmentReadException.Unreadable("")
class RelayBundle(val relay: RelayAccountCalling, val connector: MachineLinkConnecting) {
    companion object { fun relay(environment: AppEnvironment, vault: AccountVault): RelayBundle }   // RelayClientFactory.make/makeConnector, one OkHttpClient
}
/** LaunchMark.swift: launchToHome and launchToWorkspaceList once per launch, from construction, by clock.monotonic. */
class LaunchMark(latency: LatencyLog, clock: Clock) { fun homeShown(); fun workspacesListed(); fun skip() }
/** SignedInScope.swift: what one signed-in hub's screens share (3E reads these names). Main-confined. */
class SignedInScope(
    val hub: MachineHub, val decisions: DecisionCenter, val pairing: PairingModel, val history: ConversationStore,
    val launch: LaunchMark, val endedDismissals: EndedDismissalStore, val goneRemovals: GoneRemovalStore,
    val clock: Clock, val latency: LatencyLog, val voice: VoiceService? = null, val sheets: SheetPresence = SheetPresence(),
) {
    val chatCopies: ChatCopySweeper                       // ChatCopySweeper(hub, history)
    val listNotice: ListNotice
    fun agentThread(ref: SessionRef): AgentThreadModel    // AgentThreadModel(ref, hub, history, hub.scope)
    fun homeShown(); fun workspacesListed()               // forward to launch
    /** Once, in hub.scope: chatCopies.run(), and decisions.sync(items) on every distinct hub pendingItems (SignedInView.swift). */
    fun start()
}
/** One SignedInScope per hub the coordinator makes (made, then started once); null while there is no hub. */
class SignedInScopes(coordinator: AppCoordinator, scope: CoroutineScope, make: (MachineHub) -> SignedInScope) {
    val current: StateFlow<SignedInScope?>
}
class AccountGraph(
    val coordinator: AppCoordinator, val relay: RelayAccountCalling, val vault: AccountVault, val settings: KeyValueStore,
    val scopes: SignedInScopes, val launch: LaunchMark, val push: PushRegistration?, val updatePrompt: UpdatePrompt?, val isDemo: Boolean,
)
/** The composition root (contracts §5). Main-confined; appScope is supervised, Dispatchers.Main.immediate in the app.
 *  The five typed parameters are plan 3E's implementations (contracts §15), each defaulting to a stub. */
class AppComposition(
    val environment: AppEnvironment, val appScope: CoroutineScope,
    val speechEngine: SpeechEngine = NoSpeechEngine, val voicePermissions: VoicePermissionChecking = NoVoicePermissions,
    val pushRegistrar: PushRegistrar = NoPushRegistrar, val updateChecker: UpdateChecker? = null,
    val attachmentReader: AttachmentReader = NoAttachmentReader,
    /** 3E passes PlatformServices::makeVoice; null: no mic and no Settings › Voice. */
    makeVoice: ((hub: MachineHub, latency: LatencyLog, settings: KeyValueStore, clock: Clock) -> VoiceService)? = null,
    relays: (AccountVault) -> RelayBundle = { RelayBundle.relay(environment, it) },
    demoEnvironment: ((CoroutineScope) -> DemoEnvironment)? = null,  // null: DemoEnvironment(it, environment.clock, environment.demoHistoryDirectory, environment.io)
) {
    val latency: LatencyLog; val appearance: AppAppearanceStore; val inbox: PairingInbox
    val real: AccountGraph
    val demo: DemoSession
    val active: StateFlow<AccountGraph>           // demo.graph.value ?: real
    val root: StateFlow<String>                   // RootRoutes.of(the active account's RootState); Routes.LAUNCH first
    // The real account's pieces, by the names 3E's plan reads:
    val vault: AccountVault; val settings: KeyValueStore; val clock: Clock
    val push: PushRegistration?; val updatePrompt: UpdatePrompt?
    /** The active account is real, signed in, its hub loaded and its scope's sheets closed: takes the inbox link, begins
     *  the pairing model with it (the confirmation step) and returns true. Otherwise false and the link waits. */
    fun takeLink(): Boolean
    companion object {
        fun makeScope(hub: MachineHub, relay: RelayAccountCalling, vault: AccountVault, history: ConversationStore,
                      latency: LatencyLog, launch: LaunchMark, settings: KeyValueStore, clock: Clock, voice: VoiceService?): SignedInScope
    }
}
// com.shellx.app.demo
/** "Try without an account" (S1 §6.6, S3 §6.1), as 1C's DemoSession: the demo over the real app until Exit. Main-confined. */
class DemoSession(appScope: CoroutineScope, makeEnvironment: (CoroutineScope) -> DemoEnvironment,
                  graphOf: (DemoEnvironment, CoroutineScope) -> AccountGraph) {
    val graph: StateFlow<AccountGraph?>
    /** No-op while one runs. A child scope of appScope; graph = graphOf(env, child) first; then env.prepare() and
     *  env.coordinator.launch(). It never writes the clipboard (Spec note 4). */
    suspend fun start()
    /** graph = null first; then env.exit(); then cancels the child scope. */
    suspend fun exit()
}
// com.shellx.app.ui.workspaces
data class Notice(val text: String, val id: String = UUID.randomUUID().toString())
class ListNotice { val current: StateFlow<Notice?>; fun show(text: String); fun clear(id: String); companion object { val DURATION: Duration } }  // 4 s
// com.shellx.app.ui.nav
enum class SessionListKind(val wire: String) { ENDED("ended"), OTHER("other") }
/** The shell's routes. The three work routes are WorkRoutes'. */
object Routes {
    const val LAUNCH = "launch"; const val SIGN_IN = "sign_in"; const val FIRST_MAC = "first_mac"; const val PAIRING = "pairing"
    const val HOME = "home"; const val DEMO = "demo"; const val MACHINES = "machines"; const val SETTINGS = "settings"
    const val SESSIONS = "sessions/{kind}?machineId={machineId}"
    val SESSIONS_ARGUMENTS: List<NamedNavArgument>     // kind: String; machineId: String, nullable, default null
    val SIGNED_IN_ROOTS: Set<String> = setOf(FIRST_MAC, HOME)
    fun sessions(kind: SessionListKind, machineId: String? = null): String   // machineId through Uri.encode
}
/** Exactly plan 3E Task 12's shape (3E keeps this file). */
object WorkRoutes {
    const val WORKSPACE = "workspace/{machineId}/{workspaceId}"; const val AGENT = "agent/{machineId}/{sessionId}"
    const val PENDING = "pending?machineId={machineId}&workspaceId={workspaceId}"     // both arguments nullable, default null
    fun workspace(ref: WorkspaceRef): String; fun agent(ref: SessionRef): String      // Uri.encode on each id
    fun pending(): String                                                             // "pending"
    fun pendingIn(machineId: String, workspaceId: String): String
    /** The agent route's ref from the hub's session sets; agent and workspaceTitle "" when the hub lists none. */
    fun sessionRef(hub: HubState, machineId: String, sessionId: String): SessionRef
}
interface ShellXNavigator {
    fun openWorkspace(ref: WorkspaceRef); fun openAgent(ref: SessionRef); fun openPending(only: WorkspaceRef? = null)
    fun openSessions(kind: SessionListKind, machineId: String? = null); fun openMachines(); fun openSettings()
    /** The pairing model is cancelled (a fresh scan), then the page opens (the iPhone's openPairing). */
    fun openPairing()
    /** The page opens on the model's current step (a link took it to the confirmation). */
    fun showPairing()
    fun back()
}
data class RootState(val demo: Boolean, val phase: AppPhase, val hubLoaded: Boolean, val hasMachines: Boolean, val scopeReady: Boolean)
object RootRoutes { fun of(state: RootState): String }
```

  **`RootRoutes.of`:**

  | demo | phase | `hubLoaded && scopeReady` | hasMachines | root |
  | --- | --- | --- | --- | --- |
  | true | `SignedIn` | true | any | `demo` |
  | true | anything else | | | `launch` |
  | false | `Launching` | | | `launch` |
  | false | `SignedOut` | | | `sign_in` |
  | false | `SignedIn` | false | | `launch` |
  | false | `SignedIn` | true | true | `home` |
  | false | `SignedIn` | true | false | `first_mac` |

  **What `AppComposition` builds.** This follows `AppComposition.swift` and 3C's wiring summary.
  1. `vault = AccountVault(environment.secrets, environment.io)`, then `bundle = relays(vault)`.
  2. `history = ConversationStore(environment.historyDirectory, environment.io, environment.clock)` and `launch = LaunchMark(latency, environment.clock)`.
  3. The coordinator: `AppCoordinator(vault, bundle.relay, environment.identity, environment.deviceName, listOf(history), environment.settings, appScope) { MachineHub(vault, bundle.relay, bundle.connector, latency, environment.settings, appScope, environment.clock) { holder.coordinator.handleUnauthorized() } }`, reaching the coordinator through a `lateinit` holder.
  4. `push = PushRegistration(bundle.relay, vault, pushRegistrar)`.
  5. `updatePrompt = UpdatePrompt(environment.versionCode, updateChecker)` only when `!environment.debugBuild && updateChecker != null` (S3 §6.1: never in debug).
  6. `real = AccountGraph(…, scopes = SignedInScopes(coordinator, appScope) { hub -> makeScope(hub, bundle.relay, vault, history, latency, launch, environment.settings, environment.clock, makeVoice?.invoke(hub, latency, environment.settings, environment.clock)) }, isDemo = false)`.
  7. The demo's `graphOf(env, child)`: an `AccountGraph(env.coordinator, env.relay, env.vault, env.settings, SignedInScopes(env.coordinator, child) { makeScope(it, env.relay, env.vault, env.history, env.latency, demoLaunch, env.settings, environment.clock, makeVoice?.invoke(it, env.latency, env.settings, environment.clock)) }, demoLaunch, push = null, updatePrompt = null, isDemo = true)`, where `demoLaunch = LaunchMark(env.latency, environment.clock).also { it.skip() }`.
  8. `appearance = AppAppearanceStore(environment.settings)`: always the real settings, also during the demo.
  9. `root` = `active.flatMapLatest { g -> combine(g.coordinator.phase, g.coordinator.hub.flatMapLatest { it?.state ?: flowOf(null) }, g.scopes.current) { … } }.distinctUntilChanged().stateIn(appScope, SharingStarted.Eagerly, Routes.LAUNCH)`.

  **Test support** (`com.shellx.app.testing`). The `:core` test fixtures are not visible from `:app`, and 3E's kit names (`TestClock`, `eventually`, `WorkRig`, …) are left free for 3E.

```kotlin
class ManualClock(var wallMs: Long = 1_700_000_000_000) : Clock { fun advance(by: Duration) }   // monotonic: a TestTimeSource advanced too
class TestIdentity(var result: Result<String> = Result.success("google-id-token")) : IdentityProviding { val nonces: List<String> }
class TestNetworkMonitor : NetworkMonitor { val flow: MutableSharedFlow<NetworkPath>; val subscribers: Int }   // replay = 1
/** RelayAccountCalling for :app tests: account calls answer from presets; machines, unpair, pair, logout and push go to a
 *  DemoRelay(paired, pairable, approvalDelay = Duration.ZERO). Every call is recorded by name. */
class ScriptedRelay(paired: List<PairedMachine> = emptyList(), pairable: Set<String> = emptySet()) : RelayAccountCalling {
    var signIn: Result<AccountSignIn>      // default AccountSignIn(AccountSession("u1", "d1", "tok-1"), "phu@example.com")
    var delete: Result<Unit>               // default success
    val calls: List<String>                // "nonce", "google:<idToken>", "delete:<idToken>", "logout", "machines", "unpair:<grantId>",
                                           // "pair", "push:set", "push:unset"
}
fun testEnvironment(root: File, io: CoroutineDispatcher, secrets: SecretStore = DemoSecretStore(),
                    settings: KeyValueStore = MemoryKeyValueStore(), network: TestNetworkMonitor = TestNetworkMonitor(),
                    clock: ManualClock = ManualClock(), identity: IdentityProviding = TestIdentity(), debugBuild: Boolean = true): AppEnvironment
    // history root/ShellX, demo root/ShellXDemo, device "Test Phone", version "1.0.0", code 100, apiBase "https://relay.example.test"
class RecordingNavigator : ShellXNavigator { val calls: List<String> }
    // "workspace:<m>/<w>", "agent:<m>/<s>", "pending", "pending:<m>/<w>", "sessions:ended", "sessions:other:<m>",
    // "machines", "settings", "pairing", "showPairing", "back"
/** Virtual-time wait: runCurrent(), check, delay(5 ms), until the condition holds or `timeout` of virtual time passed. */
suspend fun TestScope.waitFor(timeout: Duration = 10.seconds, condition: () -> Boolean): Boolean
class TestComposition(val composition: AppComposition, val relay: ScriptedRelay, val identity: TestIdentity,
                      val network: TestNetworkMonitor, val clock: ManualClock, val settings: KeyValueStore, val secrets: SecretStore)
/** An AppComposition over fakes in backgroundScope (io = StandardTestDispatcher(testScheduler)). signedIn: the vault holds
 *  StoredSession("u1","d1","tok-1","phu@example.com") and `macs` owned by "u1". The connector is FakeMacFleet(macs + pairable).
 *  The demo's environment uses approvalDelay = Duration.ZERO and runsScript = false. Nothing is launched. */
suspend fun TestScope.testComposition(root: File, macs: List<FakeMac> = emptyList(), signedIn: Boolean = true,
    pairable: List<FakeMac> = emptyList(), secrets: SecretStore = DemoSecretStore(), debugBuild: Boolean = true,
    makeVoice: ((MachineHub, LatencyLog, KeyValueStore, Clock) -> VoiceService)? = null): TestComposition
/** The same over the real main thread (Robolectric): appScope = the caller's CoroutineScope(SupervisorJob() +
 *  Dispatchers.Main.immediate), io = Dispatchers.IO, FakeMacs built by the caller on that scope. For Compose tests that
 *  wait with composeRule.waitUntil. */
fun mainComposition(root: File, macs: List<FakeMac>, appScope: CoroutineScope, signedIn: Boolean = true,
    pairable: List<FakeMac> = emptyList(), clock: ManualClock = ManualClock()): TestComposition
```

- [ ] **Step 1: Write the test support and the failing tests.**

```kotlin
class AppCompositionTest {   // TemporaryFolder; runTest; `t = testComposition(...)`, `c = t.composition`
    // signingInMakesTheScopeOfTheNewHub: signedIn = false; c.real.coordinator.launch() → c.root.value == SIGN_IN;
    //   signInWithGoogle() → waitFor root == FIRST_MAC; c.real.scopes.current.value!!.hub === c.real.coordinator.hub.value;
    //   t.relay.calls starts with ["nonce", "google:google-id-token"]
    // pairingTheFirstMacMovesTheRootHome: after the above with pairable = [mac]: scope.pairing.begin(mac.pairingCode()),
    //   scope.pairing.confirm() → waitFor root == HOME
    // pairTappedTwiceSendsOnePairingRequest (RF 5): begin, then two backgroundScope.launch { confirm() } → waitFor Paired;
    //   t.relay.calls.count { it == "pair" } == 1
    // signingOutDropsTheScope: signed in with [mac]; launch → waitFor HOME; signOut() → root == SIGN_IN; current == null
    // aBusyKeystoreKeepsTheLaunchScreenUntilItOpens (RF 4): secrets = a DemoSecretStore wrapper whose read throws
    //   SecretStoreException.Unavailable() while `busy`; launch(); advanceUntilIdle → root == LAUNCH; busy = false;
    //   protectedDataBecameAvailable() → waitFor root == HOME
    // aLinkWaitsForARealSignedInHomeAndOnlyFillsTheConfirmation (RF 2): signedIn = false, pairable = [b]; launch;
    //   c.inbox.receive(b.pairingCode()); takeLink() == false; signInWithGoogle(); waitFor root == FIRST_MAC;
    //   takeLink() == true; scope.pairing.step.value == Confirm(b's name); "pair" !in t.relay.calls; inbox.hasLink false
    // aLinkWaitsWhileASheetIsOpenOrTheDemoRuns (RF 2): signed in with [a], pairable [b]; launch; scope.sheets.opened();
    //   receive → takeLink() false; sheets.closed() → true. Then c.demo.start(); receive again → false and hasLink stays
    //   true; c.demo.exit() → true
    // theUpdatePromptExistsOnlyInReleaseWithAChecker: debugBuild = true → c.updatePrompt == null; debugBuild = false with
    //   updateChecker = null → null; debugBuild = false with a checker → non-null; c.push != null; c.vault === c.real.vault
    // makeVoiceGivesEachHubItsVoice: makeVoice = a counting factory over local fakes → after sign-in,
    //   current.value!!.voice is the factory's answer; factory calls == 1
}
class DemoSessionTest {
    // startSignsInToTheDemoWithItsSampleMac (1C): c.demo.start() → c.active.value.isDemo; waitFor phase ==
    //   SignedIn("demo@shellx.pro") and hub machines names == ["Mac giả"], Online; graph.push == null; updatePrompt == null;
    //   waitFor c.root.value == DEMO
    // startingTwiceKeepsOneDemo: start twice → the same graph instance
    // exitHandsTheAppBackToTheRealAccount: exit() → c.active.value === c.real; root follows the real account (SIGN_IN when
    //   signed out); waitFor the demo's first Mac has liveSessionCount == 0
    // theDemoNeverTouchesTheRealStores: real secrets and settings are counting wrappers → after start, a little virtual time
    //   and exit, 0 writes to either; root/ShellX does not exist
}
class LaunchMarkTest {
    // theWorkspaceListIsMeasuredOncePerLaunch (port, ManualClock)
    // aLaunchThatSignedInFirstHasNoSample (port)
}
class RootRoutesTest { // theRootFollowsTheAccount: the seven rows of the table above
}
class RoutesTest {
    // theRoutesAreTheContractNames: LAUNCH "launch", SIGN_IN "sign_in", FIRST_MAC "first_mac", PAIRING "pairing", HOME "home",
    //   DEMO "demo", MACHINES "machines", SETTINGS "settings", WorkRoutes.WORKSPACE "workspace/{machineId}/{workspaceId}",
    //   WorkRoutes.AGENT "agent/{machineId}/{sessionId}", WorkRoutes.PENDING starts with "pending", SESSIONS starts with "sessions/{kind}"
    // everyArgumentIsEncoded: WorkRoutes.workspace(WorkspaceRef("m/1", "ws 1%")) == "workspace/m%2F1/ws%201%25";
    //   agent(SessionRef("m1", "s 1", "claude", "x")) == "agent/m1/s%201"; pending() == "pending";
    //   pendingIn("m1", "ws/2") == "pending?machineId=m1&workspaceId=ws%2F2"; Routes.sessions(ENDED) == "sessions/ended";
    //   Routes.sessions(OTHER, "m 1") == "sessions/other?machineId=m%201"
    // theAgentRouteFindsItsSessionOrKeepsTheIds: a HubState with session s1 (claude, shellx-ios) → sessionRef(state, m, "s1")
    //   has agent "claude" and workspaceTitle "shellx-ios"; sessionRef(state, m, "nope") == SessionRef(m, "nope", "", "")
}
```

- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.AppCompositionTest' --tests 'com.shellx.app.LaunchMarkTest' --tests 'com.shellx.app.demo.*' --tests 'com.shellx.app.ui.nav.*'`.

  Expected: `Unresolved reference: AppComposition`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test` and `git commit -m "test(shellx-android): composition root, accounts, demo session and routes"`.
- [ ] **Step 4: Implement** the files in Interfaces.
- [ ] **Step 5: Run (green).** Run the command of Step 2 three times; every run must pass.

  Expected: `AppCompositionTest` 9, `DemoSessionTest` 4, `LaunchMarkTest` 2, `RootRoutesTest` 1, `RoutesTest` 3.
- [ ] **Step 6: Commit.** Run `git add shellx-android/app/src/main` and `git commit -m "feat(shellx-android): composition root with the real account, the demo and the routes"`.

---

### Task 8: The process lifecycle, the application and the Android environment

**Files:**
- Create: `app/AppLifecycle.kt`, `app/ShellXApplication.kt`, `app/LinkIntents.kt`
- Modify: `app/AppEnvironment.kt` (add `android(app)`), `app/AppComposition.kt` (add `val lifecycle = AppLifecycle(this)`), `shellx-android/app/src/main/AndroidManifest.xml` (`android:name=".ShellXApplication"`), `docs/superpowers/ledgers/shellx-android-parity.md`
- Test: `app-test/AppLifecycleTest.kt`, `app-test/LinkIntentsTest.kt`, `app-test/ShellXApplicationTest.kt` (`@Config(application = ShellXApplication::class)`)

Reference: `ios/ShellXApp.swift:18-63` (launch and scene phases), `ios/Platform/NetworkPathWatcher.swift`; 3C Tasks 12 and 14 (the lifecycle calls); 3C's "UI wiring summary"; 3E Task 12 (its edits to `ShellXApplication` and this ON_START hook).

**Interfaces:**
- Consumes: Task 7; Tasks 3–5 (the platform implementations).
- Produces:

```kotlin
// com.shellx.app
/** Main-confined. Fed by ProcessLifecycleOwner (ShellXApplication); this is "3D's ON_START hook" of 3E's plan. The real
 *  account only; the demo runs in memory. */
class AppLifecycle(private val composition: AppComposition) {
    val isStarted: Boolean
    fun onStart()
    fun onStop()
}
class ShellXApplication : Application() {
    /** null until the settings snapshot is read and the composition built (onCreate starts it). */
    val composition: StateFlow<AppComposition?>
    suspend fun awaitComposition(): AppComposition
}
object LinkIntents {
    /** ACTION_VIEW with a shellx-link URI (scheme compared ignoring case) → its string; anything else → null. */
    fun uri(intent: Intent?): String?
}
// AppEnvironment.Companion
/** The real environment (S3 §7.3), on Dispatchers.IO. In order: settings = DataStoreKeyValueStore.load(file(app),
 *  CoroutineScope(SupervisorJob() + Dispatchers.IO)); LegacyFlutterCleanup.run(app.dataDir, settings);
 *  KeystoreSecretStore(directory(app)); NetworkPathWatcher; AndroidClock; CredentialManagerIdentity.create(app);
 *  noBackupFilesDir/ShellX and /ShellXDemo; DeviceName.current(app); BuildConfig.VERSION_NAME, VERSION_CODE, DEBUG;
 *  ShellXEndpoints.of(BuildConfig.DEBUG, BuildConfig.SHELLX_API_BASE.ifEmpty { null }).apiBase. */
suspend fun android(app: Application): AppEnvironment
```

  **`onStart()`**, in this order:
  1. The first time only: `appScope.launch { real.coordinator.launch(); if (hub == null || hub.state.value.machines.isEmpty()) real.launch.skip() }`. This happens on the first start in front, never at process start (Spec note 9).
  2. Network watching starts. `networkJob = appScope.launch { val filter = NetworkChangeFilter(appScope) { real.coordinator.hub.value?.networkChanged() }; environment.network.paths.collect { filter.receive(it) } }`.
  3. `appScope.launch { real.coordinator.protectedDataBecameAvailable() }`.
  4. When `real.updatePrompt` is set: `appScope.launch { it.check() }`. When `real.push` is set: `appScope.launch { it.appBecameActive() }`.
  5. When the hub exists: `hub.appDidBecomeActive()`, then `appScope.launch { hub.refreshGrants() }`.

  **`onStop()`:**
  - `networkJob?.cancel()`;
  - when the hub exists, `appScope.launch { hub.appDidEnterBackground() }`;
  - when `active.value.scopes.current.value?.voice` is set, `appScope.launch { voice.cancelAll() }`.

  **`ShellXApplication.onCreate`:**
  - `CoreLog.sink = { Log.i("ShellX", it) }`, then `registerActivityLifecycleCallbacks(ActivityTracker)`.
  - Make `appScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)` and `events = Channel<Lifecycle.Event>(UNLIMITED)`.
  - Add `ProcessLifecycleOwner.get().lifecycle.addObserver(LifecycleEventObserver { _, e -> if (e == ON_START || e == ON_STOP) events.trySend(e) })`.
  - Then `appScope.launch { val environment = withContext(Dispatchers.IO) { AppEnvironment.android(this@ShellXApplication) }; val c = AppComposition(environment, appScope); _composition.value = c; for (e in events) if (e == ON_START) c.lifecycle.onStart() else c.lifecycle.onStop() }`.
  - The one channel keeps the events in order, and holds the ones that come before the composition exists. Plan 3E adds its `PlatformServices` and passes its pieces to the `AppComposition(…)` call here (3E Task 12).

- [ ] **Step 1: Write the failing tests.**

```kotlin
class AppLifecycleTest {   // runTest; testComposition(root, macs = [mac]) with mac = FakeMac("MacBook Pro", backgroundScope)
    // aBackgroundStartConnectsNothing (RF 3): no onStart; advanceUntilIdle → mac.connectCount == 0; t.network.subscribers == 0;
    //   real.coordinator.phase.value == Launching
    // theFirstStartLaunchesTheAccountAndWatchesTheNetwork: onStart() → waitFor root == HOME and the Mac Online;
    //   mac.connectCount == 1; subscribers == 1
    // stoppingClosesTheLinksAfterTheGrace: online; onStop() → subscribers == 0; advanceTimeBy(24.seconds) →
    //   mac.liveSessionCount == 1; advanceTimeBy(2.seconds) → waitFor liveSessionCount == 0; onStart() → waitFor
    //   connectCount == 2 and Online
    // aNetworkChangeWhileStartedReplacesTheLinks: online; network.flow.emit(path("wlan0")); emit(path("rmnet0"));
    //   advanceTimeBy(301.milliseconds) → waitFor connectCount == 2
    // everyStartAsksAgain: onStart(); waitFor online (the first start has no hub yet, so it asks nothing); onStop(); onStart() →
    //   waitFor t.relay.calls.count { it == "machines" } == 1; onStop(); onStart() → waitFor that count == 2
    // aLaunchWithoutAMacTakesNoLaunchSample: macs = [] → onStart → waitFor FIRST_MAC; real.launch.homeShown() →
    //   c.latency.summary(LatencyMetric.LAUNCH_TO_HOME) == null; with a Mac → homeShown() → count 1
}
class LinkIntentsTest {
    // aShellXLinkIsTaken: Intent(ACTION_VIEW, Uri.parse("shellx-link://pair?v=1&m=m1")) → that string;
    //   "SHELLX-LINK://pair?v=1" → taken; an https link, ACTION_MAIN and null → null
}
@Config(application = ShellXApplication::class)
class ShellXApplicationTest {
    // theCompositionIsBuiltOnceTheSettingsAreRead: app = ApplicationProvider.getApplicationContext<ShellXApplication>();
    //   loop up to 10 s: shadowOf(Looper.getMainLooper()).idle(); Thread.sleep(10) until app.composition.value != null;
    //   environment.historyDirectory == File(app.noBackupFilesDir, "ShellX"); demoHistoryDirectory == …/ShellXDemo;
    //   environment.debugBuild == BuildConfig.DEBUG; environment.settings is DataStoreKeyValueStore
    // coreLogGoesToLogcatOnly: CoreLog.log("probe_line") → ShadowLog.getLogsForTag("ShellX").any { it.msg == "probe_line" }
}
```

- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.AppLifecycleTest' --tests 'com.shellx.app.LinkIntentsTest' --tests 'com.shellx.app.ShellXApplicationTest'`.

  Expected: `Unresolved reference: lifecycle`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test` and `git commit -m "test(shellx-android): process lifecycle, application and links"`.
- [ ] **Step 4: Implement** the Interfaces, and set `android:name=".ShellXApplication"` on `<application>`.
- [ ] **Step 5: Run (green).** Run the Step 2 command three times.

  Expected: PASS, 6, 1 and 2 tests each time. Then `shellx-android/scripts/dev.sh test app` passes: 3A's tests still build a plain `Application`.
- [ ] **Step 6: Ledger and commit.**
  - Set rows `6.2-10` and `6.2-11` to `done (3D)`.
    - `6.2-10`'s Android cell becomes `core:link/NetworkChangeFilter.kt`, `MachineHub.kt`, `app:platform/NetworkPathWatcher.kt` (`ConnectivityManager`), `app:AppLifecycle.kt`.
    - `6.2-11`'s Android cell becomes `core:link/MachineHub.kt`, `ProcessLifecycleOwner` in `app:ShellXApplication.kt`, `app:AppLifecycle.kt`.
  - Add an `A-` row:
    - difference: "The account launches at the app's first start in front, not at process start, and the network is watched only while the app is in front";
    - why: "S3 §4 (battery): a push (FCM) may start the process in the background, and nothing may connect then";
    - Android: `app:AppLifecycle.kt`.
  - Run `git add shellx-android/app/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): application, process lifecycle, network watching and links"`.

---

### Task 9: Sign-in, the first-Mac screen and the demo's entry points

**Files:**
- Create: `app/ui/signin/SignInView.kt`, `app/ui/signin/SignInErrorText.kt`, `app/ui/signin/GoogleSignInButton.kt` (with `GoogleButtonColors` and `GoogleBranding`), `app/ui/onboarding/FirstMacView.kt`, `app/demo/DemoBanner.kt`, `res/raw/keep_google_branding.xml`
- After the USER step (Steps 7–9):
  - create `res/drawable-mdpi/ic_google_g.png`, `res/drawable-xhdpi/ic_google_g.png`, `res/drawable-xxhdpi/ic_google_g.png` and `res/drawable-xxxhdpi/ic_google_g.png`;
  - when the font licence gate passes, create `shellx-android/app/src/main/assets/fonts/GoogleSans.ttf` and `shellx-android/app/src/main/assets/fonts/GoogleSans-OFL.txt`;
  - modify `shellx-android/README.md` (a "Third-party assets" section).
- Modify: `docs/superpowers/ledgers/shellx-android-parity.md`
- Test: `app-test/ui/signin/SignInErrorTextTest.kt`, `app-ui-test/ui/signin/SignInViewTest.kt`, `app-ui-test/ui/signin/GoogleBrandingTest.kt`, `app-ui-test/ui/onboarding/FirstMacViewTest.kt`, `app-ui-test/screenshots/SignInRenderTest.kt`

Reference:
- `ios/UI/SignIn/SignInView.swift` and `ios/UI/Onboarding/FirstMacView.swift`;
- plan 1C Task 9 (its `GoogleSignInButton`, and Steps 6–8, which use the same downloads) and Task 13 (`SignInErrorText`, the demo buttons, `DemoBanner`);
- contracts §11 (Google branding and the font licence gate);
- https://developers.google.com/identity/branding-guidelines. Re-read its sections "Color", "Font", "Padding", "Google logo in the 'Sign in with Google' button" and "Download Pre-Approved Brand Icons" before Step 4.

**What the page says** (read on 2026-11-07; Spec note 6):
- **"Font":** "The button font is Google Sans Medium", 14/20 in every theme's row. The page names one font for every platform, and never Roboto.
- **"Padding", row "Android & Web":** 12 px before the Google logo, 10 px after it, and 12 px after the text. The iOS row is 16 / 12 / 16.
- **"Color", Light theme:** fill `#FFFFFF`, stroke `#747775` 1 px inside, text `#1F1F1F`. The page also offers Dark and Neutral. Android uses Light in both appearances, as plan 1C does.
- **The "G":** "you can't change the size or color" of it. Only the standard colour version is allowed, and never your own icon. A custom size starts from the bundle's sizes.

**Interfaces:**
- Consumes: 3C's `SignInException`; Task 6's buttons and `ShellXAppTheme`; Task 2's strings; 3A's `R.drawable.shellx_logo`.
- Produces:

```kotlin
// com.shellx.app.ui.signin
/** signIn is AppCoordinator.signInWithGoogle (it throws SignInException). startDemo null: no demo button. */
@Composable fun SignInView(expired: Boolean, signIn: suspend () -> Unit, startDemo: (() -> Unit)?, modifier: Modifier = Modifier,
                           initialError: SignInException? = null)
object SignInErrorText { @StringRes fun message(error: SignInException): Int? }   // null for Cancelled
/** "Continue with Google" drawn to Google's branding page (contracts §11). `mark` and `font` are parameters so tests can
 *  draw the button with and without Google's files. */
@Composable fun GoogleSignInButton(onClick: () -> Unit, busy: Boolean, enabled: Boolean, modifier: Modifier = Modifier,
                                   @DrawableRes mark: Int? = GoogleBranding.mark(LocalContext.current),
                                   font: FontFamily? = GoogleBranding.font(LocalContext.current))
/** The page's Light theme. */
object GoogleButtonColors { val Fill = Color(0xFFFFFFFF); val Stroke = Color(0xFF747775); val Text = Color(0xFF1F1F1F) }
/** Google's files for the button (Step 8). Each file is looked for once per process; each answer is null until it is in. */
object GoogleBranding {
    const val MARK = "ic_google_g"
    const val FONT_ASSET = "fonts/GoogleSans.ttf"; const val FONT_LICENCE_ASSET = "fonts/GoogleSans-OFL.txt"
    /** The official "G" (20 × 20 dp): Resources.getIdentifier(MARK, "drawable", packageName), so the app builds before the
     *  USER step (@SuppressLint("DiscouragedApi")). */
    @DrawableRes fun mark(context: Context): Int?
    /** Google Sans Medium: FontFamily(Font(FONT_ASSET, context.assets, FontWeight.Medium, variationSettings =
     *  FontVariation.Settings(FontVariation.weight(500)))), only when FONT_LICENCE_ASSET is next to it; null → the platform font. */
    fun font(context: Context): FontFamily?
}
// com.shellx.app.ui.onboarding
@Composable fun FirstMacView(pair: () -> Unit, tryDemo: (() -> Unit)?, openSettings: () -> Unit, modifier: Modifier = Modifier)
// com.shellx.app.demo
@Composable fun DemoBanner(exit: () -> Unit, modifier: Modifier = Modifier)
```

  **`SignInErrorText.message`:**
  - `InvalidCredentials` → `signin_error_invalid_credentials`;
  - `RateLimited` → `signin_error_rate_limited`;
  - `Network` → `signin_error_network`;
  - `Server` → `signin_error_server`;
  - `LocalWipePending` → `signin_error_local_wipe_pending`;
  - `Cancelled` → null;
  - `SwitchFromSignedInDevice` → `signin_error_switch_from_signed_in_device`;
  - `ReauthRequired` → `signin_error_reauth_required`;
  - `ProviderUnavailable` → `signin_error_provider_unavailable`;
  - `ProviderFailed` → `signin_error_provider_failed`.

  **`SignInView`**, top to bottom (`SignInView.swift`'s layout):
  - A `Column(verticalScroll)` with horizontal padding 16 dp and vertical padding 24 dp, `widthIn(max = 520.dp)`, centred, spaced 16 dp. It holds:
    - `R.drawable.shellx_logo` at `(64 * fontScale).dp`;
    - `signin_title` (`headlineLarge`, SemiBold, heading);
    - `signin_subtitle` (`bodyLarge`, `onSurfaceVariant`);
    - when `expired`, `signin_expired` (`bodyMedium`, `NEEDS_YOU` tone, tag `signin.expired`);
    - the error, when there is one (`bodyMedium`, `ERROR` tone, `liveRegion = Polite`, tag `signin.error`);
    - `GoogleSignInButton(busy = busy, enabled = !busy)`, full width;
    - when `startDemo` is set, a `TextButton` `signin_demo` (`accentText`, min height 48 dp, tag `signin.demo`).
  - A tap while busy does nothing. Otherwise: `busy = true`, `error = null`, then `rememberCoroutineScope().launch { try { signIn() } catch (e: SignInException) { error = e } catch (e: Exception) { rethrow a CancellationException; error = SignInException.Server("unknown") } finally { busy = false } }`.
  - An error whose `message` is null shows nothing. Both buttons are disabled while busy.

  **`GoogleSignInButton`** (plan 1C's button, with the page's "Android & Web" values):
  - A `Surface(onClick, enabled, shape = RoundedCornerShape(50), color = GoogleButtonColors.Fill, border = BorderStroke(1.dp, GoogleButtonColors.Stroke))`. The pill is the bundle's Pill shape, and Compose draws the border inside, as the page asks.
  - Its modifier is `fillMaxWidth().heightIn(min = 48.dp).alpha(if (enabled) 1f else 0.4f).testTag("signin.google")`; 40 % matches `PrimaryButton`.
  - Inside, a `Row` centred in the button, padded 12 dp at the start and the end and 8 dp vertically:
    - with `mark`: `Image(painterResource(mark), contentDescription = null, Modifier.size(20.dp).testTag("signin.google.mark"))`, then a 10 dp gap. Without it, the G and its gap are left out: this text-only form lasts until Step 8;
    - `Text(stringResource(R.string.signin_google), color = GoogleButtonColors.Text, fontFamily = font ?: FontFamily.Default, fontWeight = FontWeight.Medium, fontSize = 14.sp, lineHeight = 20.sp, textAlign = TextAlign.Center)`.
  - While `busy`, a 20 dp `CircularProgressIndicator` (2 dp stroke, `GoogleButtonColors.Text`) replaces the group. The button's `contentDescription` is then `signin_google`, so TalkBack still names it.
  - The G is never tinted, resized or redrawn: it stays 20 dp at every font scale.

  **`FirstMacView`** (`FirstMacView.swift`, and 1C Task 13 for the demo button):
  - A `TopAppBar` with no title and a Settings `IconButton` (`Icons.Outlined.Settings`, description `settings_title`, tag `root.settings`).
  - A scrolling column, padded like `SignInView`, holding:
    - `Icons.Outlined.Devices` at `(64 * fontScale).dp` in `accentText`;
    - `pairing_title` (`headlineLarge`, SemiBold, heading);
    - `first_mac_subtitle`;
    - two steps, each a 24 dp `accentText` disc numbered "1" or "2" beside `pairing_instructions` and `first_mac_step2`;
    - a `PrimaryButton` with `Icons.Filled.QrCodeScanner` and `first_mac_scan` (tag `firstMac.pair`);
    - when `tryDemo` is set, a `TextButton` `first_mac_demo` (tag `firstMac.demo`).

  **`DemoBanner`.**
  - A `Row` of full width, min height 48 dp, background `accentText` at 14 % alpha, horizontal padding 16 dp, tag `demo.banner`.
  - It shows `demo_banner_title` (`titleSmall`, `accentText`, with `contentDescription` = `demo_banner_label`), a "·", then a `TextButton` `demo_banner_exit` (tag `demo.exit`).

- [ ] **Step 1: Write the failing tests.**

```kotlin
class SignInErrorTextTest {
    // everyFailureHasItsOwnWords (1C): the nine non-cancelled cases (Server("x")) → 9 non-null ids, 9 distinct non-empty strings
    // closingGoogleSheetSaysNothing: message(SignInException.Cancelled()) == null
}
// app-ui-test (createComposeRule; content in ShellXTheme)
class SignInViewTest {
    // continueWithGoogleSignsInOnceAndWaits: signIn waits on a CompletableDeferred and counts → click "signin.google"
    //   twice → count 1; "signin.demo" is not enabled while it waits; complete → enabled again
    // aClosedGoogleSheetShowsNothing: signIn throws SignInException.Cancelled() → no node tagged "signin.error"
    // aFailureShowsItsWordsInALiveRegion: throws Network() → "signin.error" shows signin_error_network and has
    //   SemanticsProperties.LiveRegion == LiveRegionMode.Polite
    // anExpiredSessionSaysSo: expired = true → "signin.expired" shows signin_expired
    // tryWithoutAnAccountStartsTheDemo: click "Try without an account" → startDemo 1; startDemo = null → no "signin.demo"
}
@GraphicsMode(GraphicsMode.Mode.NATIVE) @Config(qualifiers = "xxhdpi")
class GoogleBrandingTest {
    // theGoogleMarkIsTheOfficialSizeOnceBundled: assumeTrue("Task 9 Step 8 adds the mark", GoogleBranding.mark(context) != null);
    //   BitmapFactory.decodeResource(resources, it) is 60 × 60 (20 dp); its four corner pixels are white (each channel
    //   ≥ 0xF5); at least 20 % of its pixels have chroma > 80; among those, each of red, green and blue is the largest
    //   channel of some pixel (Google's colours, not a monochrome G)
    // googleSansIsUsedOnceBundled: assumeTrue("Task 9 Step 8 bundles Google Sans", "GoogleSans.ttf" in
    //   context.assets.list("fonts").orEmpty()); GoogleBranding.font(context) != null
    // aBundledFontCarriesItsOflLicence (contracts §11): every .ttf or .otf in assets/fonts has "<name>-OFL.txt" next to it,
    //   and that file contains "SIL OPEN FONT LICENSE Version 1.1"; with no font it passes
    // theMarkShowsOnlyWhenBundledAndTheNameStaysWhileBusy: GoogleSignInButton({}, false, true, mark = R.drawable.shellx_logo,
    //   font = null) → "signin.google.mark" exists (unmerged tree); mark = null → it does not, and "Continue with Google" is
    //   displayed; busy = true → no "Continue with Google" text node, and "signin.google" has contentDescription
    //   "Continue with Google"
}
class FirstMacViewTest {
    // theButtonsDoWhatTheySay: "firstMac.pair" → pair 1; "firstMac.demo" → tryDemo 1; "root.settings" → openSettings 1;
    //   tryDemo = null → no "firstMac.demo"
}
```

  `SignInRenderTest` captures, each with `assertRenders`:
  - `signin` (`SignInView(false, {}, startDemo = {})`);
  - `signin-error` (`initialError = SwitchFromSignedInDevice()`);
  - `signin-expired`;
  - `first-mac` (`tryDemo = null`);
  - `first-mac-demo`;
  - `demo-banner` (`Column { DemoBanner {}; Spacer(Modifier.weight(1f)) }`).
- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.ui.signin.*' --tests 'com.shellx.app.ui.onboarding.*' --tests 'com.shellx.app.screenshots.SignInRenderTest'`.

  Expected: `Unresolved reference: SignInView`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test shellx-android/app/src/testDebug` and `git commit -m "test(shellx-android): sign-in, first Mac, Google's button and the demo banner"`.
- [ ] **Step 4: Implement** the Interfaces. Also add `res/raw/keep_google_branding.xml`, holding `<resources xmlns:tools="http://schemas.android.com/tools" tools:keep="@drawable/ic_google_g" />`. Release builds shrink resources (3A sets `isShrinkResources = true`), and the mark is looked up by name.
- [ ] **Step 5: Run (green), then look.** Run the Step 2 command, then `acounts ui.signin.GoogleBrandingTest`, then `SHOTS="$(mktemp -d)"; shellx-android/scripts/dev.sh screenshots record "$SHOTS"`.

  Expected: PASS:
  - `SignInErrorTextTest` 2, `SignInViewTest` 5, `FirstMacViewTest` 1 and `SignInRenderTest` 6;
  - `GoogleBrandingTest` prints `tests="4" skipped="2" failures="0" errors="0"`: the mark and the font are not in yet.

  Open `signin-light-en.png`, `signin-dark-vi.png` and `first-mac-demo-light-vi.png`, and check:
  - the Google button is white, with a #747775 outline and #1F1F1F words, in both themes, and shows its text only for now;
  - "Xem thử không cần tài khoản" is in the accent text colour;
  - no text is clipped.
- [ ] **Step 6: Ledger and commit.**
  - Add an `A-` row:
    - difference: "Continue with Google uses the branding page's 'Android & Web' padding (12 / 10 / 12 dp around the 20 dp G; the iPhone's row is 16 / 12 / 16) and the Android + Web icons, and it is at least 48 dp high (the iPhone's is 44 pt, beside Apple's button)";
    - why: "contracts §11 and Google's branding guidelines ('Padding'); the 48 dp touch target";
    - Android: `app:ui/signin/GoogleSignInButton.kt`.
  - Run `git add shellx-android/app/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): Google sign-in screen, first-Mac screen and the demo's entry points"`.
- [ ] **Step 7: USER — download Google's sign-in assets and Google Sans.** This follows contracts §11 and Google's terms (the page's "Other Guidelines" and https://www.google.com/permissions/). Google Sans is under the SIL Open Font License 1.1. These are the files of plan 1C Task 9 Step 6.
  - If `~/Downloads/shellx-google-signin/` already holds `signin-assets.zip`, `GoogleSans.ttf` and `OFL.txt`, only ask the user to confirm that the Android app may use them, and to run the third command below when `GoogleSans-Medium.ttf` is not there yet.
  - Otherwise ask the user to run:

    ```
    ! mkdir -p ~/Downloads/shellx-google-signin && curl -fL -o ~/Downloads/shellx-google-signin/signin-assets.zip https://developers.google.com/static/identity/images/signin-assets.zip && shasum -a 256 ~/Downloads/shellx-google-signin/signin-assets.zip
    ! curl -fL -o ~/Downloads/shellx-google-signin/GoogleSans.ttf 'https://raw.githubusercontent.com/google/fonts/main/ofl/googlesans/GoogleSans%5BGRAD%2Copsz%2Cwght%5D.ttf' && curl -fL -o ~/Downloads/shellx-google-signin/OFL.txt https://raw.githubusercontent.com/google/fonts/main/ofl/googlesans/OFL.txt
    ! curl -fsSL 'https://fonts.google.com/download/list?family=Google%20Sans' | tail -n +2 | python3 -c 'import json,sys; print(next(f["url"] for f in json.load(sys.stdin)["manifest"]["fileRefs"] if f["filename"] == "static/GoogleSans-Medium.ttf"))' | xargs curl -fL -o ~/Downloads/shellx-google-signin/GoogleSans-Medium.ttf
    ```

    The third command fetches the static Medium face, the one plan 1B ships: a few hundred KB instead of the ~5 MB variable font. Step 8 bundles it when it is there, else the variable font.

    On 2026-11-07 the zip's SHA-256 was `ba884069e12093b06bcfd776915081254a7c95094b80d50be2c5dc6bac1c1da1` (plan 1C). Another value only means Google updated the bundle; Step 8 checks that the files it needs are still there.
  - The user then says "Google assets downloaded". Meanwhile go on with Task 10, and come back for Steps 8–9 once the user has answered, before Task 17.
  - If the user declines, the button keeps its text-only form; record "Google's G: pending (USER)" for the hand-off. A store release needs the mark (Contract additions 10).
  - Never take the mark from anywhere else: no Google logo from `ios/`, `Packages/` or `Sources/`, and no drawn or traced one.
- [ ] **Step 8: Add the G and the font.** With `<scratch>` your scratchpad directory, list the icons:

  ```bash
  S=~/Downloads/shellx-google-signin; W="<scratch>/google-g"; R=shellx-android/app/src/main/res
  mkdir -p "$W" && shasum -a 256 "$S/signin-assets.zip"
  unzip -Z1 "$S/signin-assets.zip" | grep -i '^android' | grep 'Theme=Light, Show text=No, Shape=Square' | grep '\.png$'
  ```

  Expected: four entries, one under each of `PNG @1x/` to `PNG @4x/` of the `Android + Web` folder. With any other count, stop and ask the user. Never use the bundle's SVGs: their "G" is a `foreignObject`, which a VectorDrawable cannot hold.

  Then extract each icon and crop its centre 20 dp, unchanged. The icon's frame lies outside that square.

  ```bash
  for k in 1 2 3 4; do
    e="$(unzip -Z1 "$S/signin-assets.zip" | grep -i '^android' | grep "PNG @${k}x/" | grep 'Theme=Light, Show text=No, Shape=Square' | grep '\.png$')"
    unzip -p "$S/signin-assets.zip" "$e" > "$W/light@${k}x.png" && sips -g pixelWidth -g pixelHeight "$W/light@${k}x.png" | tail -2
  done
  mkdir -p "$R/drawable-mdpi" "$R/drawable-xhdpi" "$R/drawable-xxhdpi" "$R/drawable-xxxhdpi"
  sips --cropToHeightWidth 20 20 "$W/light@1x.png" --out "$R/drawable-mdpi/ic_google_g.png"
  sips --cropToHeightWidth 40 40 "$W/light@2x.png" --out "$R/drawable-xhdpi/ic_google_g.png"
  sips --cropToHeightWidth 60 60 "$W/light@3x.png" --out "$R/drawable-xxhdpi/ic_google_g.png"
  sips --cropToHeightWidth 80 80 "$W/light@4x.png" --out "$R/drawable-xxxhdpi/ic_google_g.png"
  ```

  Expected: four square icons. Each side is `k` times the `@1x` side, and the `@1x` side is larger than 22 px. Android scales the `xhdpi` file for `hdpi` phones.

  Then run the font licence gate (contracts §11):

  ```bash
  F=shellx-android/app/src/main/assets/fonts; G="$S/GoogleSans-Medium.ttf"; test -f "$G" || G="$S/GoogleSans.ttf"
  grep -q 'SIL OPEN FONT LICENSE Version 1.1' "$S/OFL.txt" && file "$G" | grep -q 'TrueType' && echo "font-gate-ok $G"
  ```

  - Only on `font-gate-ok`, run `mkdir -p "$F" && cp "$G" "$F/GoogleSans.ttf" && cp "$S/OFL.txt" "$F/GoogleSans-OFL.txt"`. The font ships unmodified, with its licence next to it.
  - Otherwise bundle no font. The button keeps the platform font, `googleSansIsUsedOnceBundled` stays skipped, and the hand-off says why.
- [ ] **Step 9: Verify and commit.**
  - Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.ui.signin.*' --tests 'com.shellx.app.screenshots.SignInRenderTest'`, then `acounts ui.signin.GoogleBrandingTest`.

    Expected: PASS, with `tests="4" skipped="0" failures="0" errors="0"`, or `skipped="1"` when the font gate failed.
  - Run `bash scripts/shellx/check-android-license.sh`. Expected: `check-android-license: ok`.
  - Compare with Google's own button.
    1. Record the screenshots again, with Step 5's command.
    2. Find Google's Pill button with `unzip -Z1 "$S/signin-assets.zip" | grep -i '^android' | grep 'PNG @3x/' | grep 'Theme=Light, Show text=Yes, Shape=Pill'`, and `unzip -p` that entry into `$W/google-pill@3x.png`.
    3. Put `signin-light-en.png` and `signin-dark-vi.png` beside it. The G must have the same size and colours, the gap to the words must be the same, and so must the outline and the fill. The words, the width and, without Google Sans, the letters may differ.

    If the G differs in size, stop and ask the user.
  - In `shellx-android/README.md`, add a section "Third-party assets":
    > `app/src/main/res/drawable-{mdpi,xhdpi,xxhdpi,xxxhdpi}/ic_google_g.png` is Google's official "G", cropped unchanged (20 × 20 dp) from the Light, no-text, Square Android + Web icons of Google's sign-in bundle (https://developers.google.com/static/identity/images/signin-assets.zip, SHA-256 `<Step 8's value>`, linked from https://developers.google.com/identity/branding-guidelines, "Download Pre-Approved Brand Icons"). `app/src/main/assets/fonts/GoogleSans.ttf` is Google Sans (the static Medium face from fonts.google.com, or the variable font from github.com/google/fonts when that download failed: say which), under the SIL OFL 1.1 (`GoogleSans-OFL.txt`, shipped next to it). Both serve only the Continue with Google button, which follows that page. Never replace them with a Google logo from `ios/`, `Packages/` or `Sources/`, or with a drawn one.

    When the font gate failed, leave out the font sentence; say instead that the button uses the platform font, and why.
  - Set row `6.1-3` to `done (3D)`.
  - Run `git add shellx-android/app/src/main/res/drawable-*dpi/ic_google_g.png shellx-android/README.md docs/superpowers/ledgers/shellx-android-parity.md`. When the font gate passed, also run `git add shellx-android/app/src/main/assets/fonts`. Then run `git commit -m "feat(shellx-android): Google's G mark and Google Sans on the Continue with Google button"`.

---

### Task 10: Pairing with a Mac

**Files:**
- Create: `app/ui/pairing/PairingScreen.kt` (`PairingScreen`, `PairingScreenContent`, `PairingActions`, `PairingText`, `PairingRouteViewModel`, `CancelPairingWhenLeft`), `app/ui/pairing/QrScanner.kt` (`QrScanner`, `QrAnalyzer`), `app/ui/pairing/QrFrameDecoder.kt`, `app/ui/pairing/PairingPaste.kt`, `app/platform/CameraAccess.kt`
- Modify: `docs/superpowers/ledgers/shellx-android-parity.md`
- Test: `app-test/ui/pairing/QrFrameDecoderTest.kt`, `app-test/ui/pairing/PairingPasteTest.kt`, `app-test/ui/pairing/PairingTextTest.kt`, `app-test/platform/CameraAccessTest.kt`, `app-ui-test/ui/pairing/PairingScreenTest.kt`, `app-ui-test/screenshots/PairingRenderTest.kt`

Reference: `ios/UI/Pairing/{PairingSheet,QRScannerView,PairingPaste}.swift`, `ios/Platform/CameraAccess.swift`, `ios-tests/{MachinesRenderTests,DemoCompositionTests}.swift` (the pairing and paste tests).

**Interfaces:**
- Consumes: 3C's `PairingModel`, `PairingFailure`, `PairingScanFilter`; 3B's `PairingOffer.make` (tests); Task 6's components.
- Produces:

```kotlin
// com.shellx.app.platform
enum class CameraAccess {
    NOT_DETERMINED, AUTHORIZED, DENIED, UNAVAILABLE;
    /** No camera (FEATURE_CAMERA_ANY) → UNAVAILABLE; CAMERA granted → AUTHORIZED; else NOT_DETERMINED (DENIED comes only
     *  from a refused request). */
    companion object { fun current(context: Context): CameraAccess }
}
// com.shellx.app.ui.pairing
object QrFrameDecoder { fun decode(luminance: ByteArray, rowStride: Int, width: Int, height: Int): String? }
class QrAnalyzer(private val onCode: (String) -> Unit, private val mainExecutor: Executor) : ImageAnalysis.Analyzer
/** The back camera (CameraX Preview + ImageAnalysis) reporting every QR text it reads, on the main thread. */
@Composable fun QrScanner(onCode: (String) -> Unit, modifier: Modifier = Modifier)
/** PairingPaste.swift: the clipboard's text, read once; a pairing code is then cleared from the clipboard. */
object PairingPaste { fun take(clipboard: ClipboardManager, context: Context): String }
class PairingActions(val scanned: (String) -> Unit = {}, val paste: () -> Unit = {}, val confirm: () -> Unit = {},
                     val retry: () -> Unit = {}, val close: () -> Unit = {}, val openSettings: () -> Unit = {})
@Composable fun PairingScreenContent(step: PairingModel.Step, camera: CameraAccess, actions: PairingActions = PairingActions(),
    modifier: Modifier = Modifier, scanner: @Composable (Modifier, (String) -> Unit) -> Unit = { m, onCode -> QrScanner(onCode, m) })
@Composable fun PairingScreen(model: PairingModel, close: () -> Unit)
object PairingText {
    fun message(failure: PairingFailure, res: Resources): String     // PairingSheetContent.message; Server(code) → pairing_error_server(code)
    fun announcement(step: PairingModel.Step, res: Resources): String?
}
/** Cancels the pairing when its back stack entry is popped (onCleared), never on recomposition or a configuration change. */
class PairingRouteViewModel(private val cancel: () -> Unit) : ViewModel()
@Composable fun CancelPairingWhenLeft(cancel: () -> Unit)   // viewModel(factory) { PairingRouteViewModel(cancel) } in the current entry
```

  **QR frames** (the loop the tests do not fix).
  - `QrFrameDecoder.decode` builds `PlanarYUVLuminanceSource(luminance, rowStride, height, 0, 0, width, height, false)`, then returns `QRCodeReader().decode(BinaryBitmap(HybridBinarizer(source)), mapOf(DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE))).text`. A `ReaderException` → null.
  - `QrAnalyzer.analyze(image)`:

    ```kotlin
    try {
        val plane = image.planes[0]; val buffer = plane.buffer
        val data = ByteArray(plane.rowStride * image.height)
        buffer.get(data, 0, minOf(buffer.remaining(), data.size))
        QrFrameDecoder.decode(data, plane.rowStride, image.width, image.height)?.let { text -> mainExecutor.execute { onCode(text) } }
    } finally { image.close() }
    ```
  - `QrScanner`:
    - `AndroidView(factory = { PreviewView(it).apply { scaleType = PreviewView.ScaleType.FILL_CENTER } })`;
    - `LaunchedEffect(lifecycleOwner)`: get `ProcessCameraProvider.awaitInstance(context)`; build `Preview` with `setSurfaceProvider(view.surfaceProvider)` and `ImageAnalysis` with `STRATEGY_KEEP_ONLY_LATEST`, its analyzer on a remembered single-thread executor; `bindToLifecycle(lifecycleOwner, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis)`; then `awaitCancellation()`, with `finally { provider.unbind(preview, analysis) }`;
    - `rememberUpdatedState(onCode)`; the executor shuts down in a `DisposableEffect`.

  **`PairingScreenContent`** (`PairingSheetContent`'s steps).
  - A `Scaffold` with a `TopAppBar`: title `pairing_title`, navigation icon `Icons.Filled.Close` (description `common_close`, tag `pairing.close`) running `close`.
  - The body is a scrolling column, padded 20 dp across and 16 dp down, `widthIn(max = 520.dp)`.
  - **`Idle`.**
    - The viewfinder: a black square box (radius 16 dp, max 360 dp, centred) holding `scanner` when `AUTHORIZED`, else a spinner. A white 3 dp outline (radius 12 dp) is inset 48 dp. The box has `contentDescription = pairing_camera_label` and tag `pairing.scanner`.
    - After a non-ShellX code, `pairing_error_not_shell_x_code` in the `NEEDS_YOU` tone (tag `pairing.otherCode`).
    - `DENIED` → a card with `Icons.Outlined.VideocamOff` and `pairing_camera_denied`, then a `PrimaryButton` `pairing_camera_open_settings` (tag `pairing.openSettings`).
    - `UNAVAILABLE` → a card with `Icons.Outlined.PhotoCamera` and `pairing_camera_unavailable`.
    - Then `pairing_instructions`, and an `OutlinedButton` with `Icons.Outlined.ContentPaste` and `pairing_paste` (tag `pairing.paste`).
    - Scanning keeps `val filter = remember(idle) { PairingScanFilter() }`: `Pairing(text)` → a haptic (`HapticFeedbackType.Confirm`, or `LongPress` if this Compose version lacks it), then `actions.scanned(text)`; `NotShellX` shows the notice; `Ignored` does nothing.
  - **`Confirm(name)`:** `Icons.Outlined.Devices` in `accentText`; `pairing_confirm_title` (name) and `pairing_confirm_message`; a `PrimaryButton` `pairing_confirm_button` (tag `pairing.confirm`); a `TextButton` `common_cancel` (tag `pairing.cancel`) running `close`.
  - **`WaitingForMac(name)`:** a spinner; `pairing_waiting` (name) and `pairing_waiting_detail`; an `OutlinedButton` `common_cancel` (tag `pairing.cancel`).
  - **`Paired(name)`:** `Icons.Filled.CheckCircle` in the `DONE` tone; `pairing_paired` (name); a `PrimaryButton` `pairing_done` (tag `pairing.done`) running `close`.
  - **`Failed(f)`:** `Icons.Filled.Warning` in the `ERROR` tone; `PairingText.message(f)`; a `PrimaryButton` `pairing_retry` (tag `pairing.retry`).
  - The message title (`headlineSmall`, SemiBold, centred, tag `pairing.message`) has `liveRegion = Polite` for `WaitingForMac`, `Paired` and `Failed`.

  **`PairingScreen`** (`PairingSheet.swift`).
  - It collects `model.step`. The camera starts at `CameraAccess.current(context)`.
  - A `rememberLauncherForActivityResult(RequestPermission())` sets `AUTHORIZED` or `DENIED`. `LaunchedEffect(step is Idle, camera)` launches the `CAMERA` request when the step is `Idle` and the camera is `NOT_DETERMINED`: ask when the scanner is about to show, never before.
  - On `ON_RESUME`, re-read `current(context)`, and keep `DENIED` unless the result is `AUTHORIZED`.
  - The actions:
    - `scanned` → `model.begin(it)`;
    - `paste` → `model.begin(PairingPaste.take(clipboard, context))`;
    - `confirm` → `rememberCoroutineScope().launch { model.confirm() }` (3C runs it detached);
    - `retry` → `model.cancel()`;
    - `close` → `close()`;
    - `openSettings` → `Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))`.

  **`PairingPaste.take`.**
  - `clipboard.primaryClip?.getItemAt(0)?.coerceToText(context)?.toString() ?: ""`.
  - When `PairingScanFilter.isPairingText(text)`, clear the clip: `clearPrimaryClip()` on API 28 and later, else `setPrimaryClip(ClipData.newPlainText("", ""))`.

- [ ] **Step 1: Write the failing tests.**

```kotlin
class QrFrameDecoderTest {   // QRCodeWriter().encode(text, QR_CODE, 400, 400) → bytes 0 (black) / 255 (white)
    // aShellXCodeDecodes: PairingOffer.make("6f1c2b7e-0d4a-4c1e-9a53-3b8e5d2f7a10", "slot-1", ByteArray(32) { 1 }, "MacBook của Phú").uri
    //   → decode(luminance, 400, 400, 400) == that uri
    // paddedRowsDecode: the same image with rowStride 448 (pad bytes 127) → the same text
    // aBlankFrameHasNoCode: ByteArray(400 * 400) { -1 } → null
    // anyQrIsReported: "https://example.com" → "https://example.com" (PairingScanFilter does the filtering)
}
class PairingPasteTest {
    // aPastedCodeIsReadOnceAndCleared (port): "shellx-link://pair?v=1&m=m1&s=s1&k=k&c=c&n=Mac\n" → that text; then the
    //   clipboard holds no text, or ""
    // otherPastedTextIsLeftAlone (port): "a note" → "a note", and it stays
    // anEmptyClipboardIsEmptyText: no clip → ""
}
class PairingTextTest {
    // eachFailureSaysSomethingDifferent (port of testPairingFailuresRender's set): the 8 failures, with Server("internal") →
    //   8 distinct texts; the server text contains "internal"
    // announcementsFollowTheStep (port): Idle and Confirm → null; Failed(Denied) == message(Denied);
    //   WaitingForMac("Studio") and Paired("Studio") contain "Studio"
}
class CameraAccessTest {
    // noCameraIsUnavailable: shadowOf(packageManager).setSystemFeature(FEATURE_CAMERA_ANY, false) → UNAVAILABLE
    // aGrantedCameraIsAuthorized: feature on; shadowOf(application).grantPermissions(CAMERA) → AUTHORIZED
    // notAskedYetIsNotDetermined: feature on, no grant → NOT_DETERMINED
}
// app-ui-test
class PairingScreenTest {
    // aScannedShellXCodeIsTakenOnce: PairingScreenContent(Idle, AUTHORIZED, scanner = a fake capturing onCode) → feed the same
    //   pairing code twice → scanned 1; feed "https://example.com" → "pairing.otherCode" displayed
    // eachStepsButtonsReachTheirActions: Idle "pairing.paste" → paste; Confirm "pairing.confirm" → confirm and "pairing.cancel"
    //   → close; Paired "pairing.done" → close; Failed "pairing.retry" → retry; "pairing.close" → close
    // aDeniedCameraOffersSettings: DENIED → click "pairing.openSettings" → openSettings 1
    // theStepTitleIsALiveRegion: WaitingForMac, Paired and Failed → "pairing.message" has LiveRegion Polite; Confirm → none
    // leavingTheScreenCancelsThePairingAndRecreationDoesNot (RF 1): StateRestorationTester(rule).setContent { NavHost with
    //   "a" and "pairing", whose destination calls CancelPairingWhenLeft { cancels++ } }; navigate("pairing");
    //   emulateSaveAndRestore() → cancels == 0; popBackStack(); waitForIdle → cancels == 1
}
```

  `PairingRenderTest` captures, each with `assertRenders` (camera `UNAVAILABLE` unless named):
  - `pairing-idle-unavailable`, `pairing-idle-denied`;
  - `pairing-idle-scanner` (`AUTHORIZED`, with a black `Box` as the scanner);
  - `pairing-confirm`, `pairing-waiting`, `pairing-paired` (Mac name "MacBook Pro");
  - `pairing-failed-<label>` for `not-shellx`, `needs-update`, `damaged`, `denied`, `expired`, `other-account`, `network`, `server` (`Server("internal")`).
- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.ui.pairing.*' --tests 'com.shellx.app.platform.CameraAccessTest' --tests 'com.shellx.app.screenshots.PairingRenderTest'`.

  Expected: `Unresolved reference: QrFrameDecoder`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test shellx-android/app/src/testDebug` and `git commit -m "test(shellx-android): pairing screen, QR frames, paste and camera access"`.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run (green).** Expected: PASS.
  - `QrFrameDecoderTest` 4, `PairingPasteTest` 3, `PairingTextTest` 2, `CameraAccessTest` 3, `PairingScreenTest` 5, `PairingRenderTest` 14.
  - Open `pairing-idle-denied-dark-vi.png` and `pairing-confirm-light-en.png`; check the layout matches the iPhone's steps.
- [ ] **Step 6: Ledger and commit.**
  - Add an `A-` row:
    - difference: "Pairing is a full-screen page (route `pairing`) with a Close button, not a sheet; system Back cancels the attempt as the iPhone's swipe-down does";
    - why: "contracts §5 names the route; a camera preview inside a draggable sheet fights the drag";
    - Android: `app:ui/pairing/PairingScreen.kt`.
  - Run `git add shellx-android/app/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): pair a Mac by QR, pasted code or link"`.

---

### Task 11: Your Macs

**Files:**
- Create: `app/ui/machines/MachinesView.kt` (`MachinesView`, `MachineList`, `MachineListItem`), `app/ui/machines/MachineRow.kt` (`MachineRow`, `DefaultBadge`)
- Modify: `docs/superpowers/ledgers/shellx-android-parity.md`
- Test: `app-test/ui/machines/MachineListItemTest.kt`, `app-ui-test/ui/machines/MachinesScreenTest.kt`, `app-ui-test/screenshots/MachinesRenderTest.kt`

Reference: `ios/UI/Machines/{MachinesView,MachineRow}.swift`, `ios-tests/MachinesRenderTests.swift`.

**Interfaces:**
- Consumes: Task 6 (`ActionRow`, `RowActions.machine`, `ConfirmDialog`, `MessageDialog`, `MachineStateStyle`, `StatusDot`); Task 7 (`SignedInScope`, `ShellXNavigator`).
- Produces (`com.shellx.app.ui.machines`):

```kotlin
data class MachineListItem(val id: String, val name: String, val state: MachineLinkState) {
    fun offersMakeDefault(defaultId: String?): Boolean      // id != defaultId && state.canBeDefault
}
/** The list with its actions, from plain values (MachineList in MachinesView.swift). */
@Composable fun MachineList(items: List<MachineListItem>, defaultId: String?, makeDefault: (String) -> Unit,
                            unpair: suspend (String) -> Unit, pair: () -> Unit, back: () -> Unit)
@Composable fun MachineRow(name: String, state: MachineLinkState, isDefault: Boolean, pairAgain: () -> Unit, remove: () -> Unit)
@Composable fun DefaultBadge()
/** Route `machines`: fed by scope.hub; unpair runs in hub.scope and the screen awaits it. */
@Composable fun MachinesView(scope: SignedInScope, navigator: ShellXNavigator)
```

  **`MachineList`.**
  - A `Scaffold` with a `TopAppBar`: title `machines_title`, back, and an action `Icons.Filled.Add` (description `pairing_title`, tag `machines.pair`) running `pair`.
  - A `LazyColumn`: one card holding the rows separated by `HorizontalDivider` (16 dp inset), then the footer `machines_footer` (`bodySmall`, `onSurfaceVariant`).
  - Each row is an `ActionRow` with `RowActions.machine(item.state, item.offersMakeDefault(defaultId))`, `onClick = null`, and `enabled = item.id !in working`.
  - The actions:
    - `UNPAIR` sets `confirming = item`, held by `rememberSaveable` through its id;
    - `REMOVE_MAC` runs `unpairNow(item)`;
    - `MAKE_DEFAULT` runs `makeDefault(id)`;
    - `PAIR_AGAIN` runs `pair()`.
  - `ConfirmDialog(title = machines_unpair_title(name), text = machines_unpair_message, confirmLabel = machines_unpair)` runs `unpairNow`.
  - `unpairNow` does nothing for an id already in `working`. Otherwise: add the id, then `rememberCoroutineScope().launch { try { unpair(id) } catch (e: Exception) { rethrow cancellation; failed = item } finally { working -= id } }`.
  - `failed` shows `MessageDialog(title = machines_unpair_failed_title, text = machines_unpair_failed_message(name))`.

  **`MachineRow`** (`MachineRow.swift`).
  - `Icons.Outlined.Laptop` (left out at large text), the name (`titleMedium`, SemiBold), and `DefaultBadge` when default; under them, `StatusDot(style.tone.color())` and the style's text (`bodyMedium`, `onSurfaceVariant`).
  - At large text, the badge and the action go under the name.
  - `HostKeyChanged` → an `OutlinedButton` `machines_pair_again` in `accentText` (tag `machine.pairAgain`). `Revoked` → an `OutlinedButton` `machines_remove` in the `ERROR` tone (tag `machine.remove`).
  - The details merge into one `contentDescription`: "name, state text[, Default]".
  - Tag `machine.row`.
- `DefaultBadge`: `machines_default` in `labelMedium` SemiBold, `accentText` on 14 % `accentText`, capsule, hidden from TalkBack.
- `MachinesView`:
  - `items` come from `hub.state.machines`, and `defaultId` from `hub.state.defaultMachineId`;
  - `makeDefault = { scope.hub.defaultMachineId = it }`;
  - `unpair = { id -> scope.hub.scope.async { scope.hub.unpair(id) }.await() }`;
  - `pair = navigator::openPairing`, `back = navigator::back`.

- [ ] **Step 1: Write the failing tests.**

```kotlin
class MachineListItemTest {
    // makeDefaultIsOfferedOnlyForUsableMacs (port): the seven-state list with defaultId "m2" →
    //   [true, false, true, true, false, false, true]
}
// app-ui-test (createComposeRule; MachineList over plain items)
class MachinesScreenTest {
    // swipingAnOnlineMacAsksBeforeUnpairing: swipe "MacBook Pro" → dialog "Unpair MacBook Pro?" with machines_unpair_message
    //   → click the dialog's "Unpair" → unpair("m1") once
    // unpairTappedTwiceUnpairsOnce (RF 5): unpair waits on a gate; confirm; swipe the row again → nothing (row disabled);
    //   open the menu → nothing; open the gate → unpair count 1
    // aMacThatRemovedThisPhoneIsRemovedWithoutAQuestion: Revoked "Mac của Lan" → click "machine.remove" → unpair("m5") with
    //   no dialog; a swipe does the same
    // aFailedUnpairSaysSo: unpair throws IOException → "Couldn't Unpair" and "MacBook Pro is still paired. …"; OK closes it
    // theMenuOffersWhatTheMacAllows: long-press: Online non-default → [Make Default, Unpair]; the default → [Unpair];
    //   HostKeyChanged → [Pair Again, Unpair]; Revoked → [Remove]; "Make Default" → makeDefault("m3")
    // plusOpensPairing: "machines.pair" → pair 1
}
```

  `MachinesRenderTest` captures, each with `assertRenders`:
  - `machines`: the seven states of `MachinesRenderTests.everyState` ("Mac của Lan" included), default `m1`;
  - `machines-large-text`: the first three states and `HostKeyChanged`, inside `LargeText { … }`.
- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.ui.machines.*' --tests 'com.shellx.app.screenshots.MachinesRenderTest'`.

  Expected: `Unresolved reference: MachineListItem`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test shellx-android/app/src/testDebug` and `git commit -m "test(shellx-android): Your Macs"`.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run (green).** Expected: PASS, with 1, 6 and 2 tests. Open `machines-large-text-light-vi.png`: no name breaks inside a word, and the actions stay visible.
- [ ] **Step 6: Ledger and commit.** Set row `6.1-7` to `done (3D)`. Run `git add shellx-android/app/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): Your Macs with default, unpair and remove"`.

---

### Task 12: Home cards, their words, the Mac groups, the Mac's answers and the shared close paths

**Files:**
- Create: `app/ui/home/FocusRowView.kt` (`FocusKind`, `FocusRowText`, `FocusRowView`)
- Create in `app/ui/workspaces/`: `WorkspaceRowView.kt`, `MachineGroupHeader.kt` (`MachineGroupHeader`, `MachineGroupHeaderText`), `WorkspaceGroup.kt`, `WorkspaceFeedback.kt` (`WorkspaceCommand`, `WorkspaceAlert`, `WorkspaceFeedback`, `WorkspaceAlertDialog`, `AgentCloseConfirmation`), `WorkspaceListActions.kt` (`canClose`, `closeAgent`, `canCloseTab`, `closeTab`), `WorkspaceListModel.kt`, `OtherSessionsModel.kt`
- Create (test support): `app-test/testing/HomeFixtures.kt`
- Test: `app-test/ui/home/FocusRowTextTest.kt`, `app-test/ui/workspaces/WorkspaceGroupTest.kt`, `app-test/ui/workspaces/WorkspaceFeedbackTest.kt`, `app-test/ui/workspaces/WorkspaceListModelTest.kt`, `app-test/ui/workspaces/WorkspaceCloseTest.kt`

Reference: `ios/UI/Home/FocusRowView.swift`, `ios/UI/Workspaces/{WorkspaceRowView,MachineGroupHeader,WorkspaceFeedback}.swift`, `WorkspaceListScreen.swift` (`WorkspaceGroup`), `WorkspaceListView.swift` (`groups`, `closableAgents`, `removableAgents`, `canClose`, `closeAgent`, `canCloseTab`, `closeTab`), `OtherSessionsView.swift` (`sessions`, `kind`); `ios-tests/{WorkspaceListRenderTests,WorkspaceListActionsTests,WaitingBorderRenderTests}.swift`; 3E Task 7 and Task 8 (the shapes of `WorkspaceFeedback`, `WorkspaceAlertDialog`, `AgentCloseConfirmation` and the four close functions, which 3E's agent and workspace screens call).

**Interfaces:**
- Consumes: 3C's `FocusItem`, `HomeFocus`, `MachineSession`, `AgentStatusRow`, `AgentLabel`, `MachineHub`, `HubState`, `WorkspaceRow`, `WorkspaceRef`, `WorkspaceCommandResult`, `GoneRemovals`, `GoneRemovalStore`; 3B's `AgentSession` (`com.shellx.link.core`); Task 6 (`AgentStateStyle`, `StatusTone`, `WaitingBorder`, `StatusDot`, `isLargeText`).
- Produces:

```kotlin
// com.shellx.app.ui.home
enum class FocusKind { NEEDS_YOU, RUNNING, JUST_DONE, ENDED, IDLE }
/** FocusRowView.swift's words; `locale` is AppLanguage's. */
class FocusRowText(private val res: Resources, private val locale: Locale) {
    fun tag(item: FocusItem, kind: FocusKind, nowMs: Long): String?
    fun timeText(item: FocusItem, kind: FocusKind, nowMs: Long): String?
    fun subLine(item: FocusItem, kind: FocusKind, nowMs: Long, showsMachineName: Boolean): String
    fun ageText(elapsed: Duration): String          // whole minutes, at least one, never negative
    companion object {
        fun showsWaitingBorder(item: FocusItem, kind: FocusKind): Boolean   // kind == NEEDS_YOU && item.session.online
        fun quotedQuestion(item: FocusItem, kind: FocusKind): String?       // “question” on a needs-you card with one
        fun tone(kind: FocusKind): StatusTone                               // NEEDS_YOU, RUNNING, DONE (JUST_DONE), IDLE (ENDED, IDLE)
    }
}
@Composable fun FocusRowView(item: FocusItem, kind: FocusKind, nowMs: Long, showsMachineName: Boolean,
                             modifier: Modifier = Modifier, trailingInset: Dp = 0.dp)
// com.shellx.app.ui.workspaces
data class WorkspaceGroup(val id: String, val name: String, val state: MachineLinkState, val isDefault: Boolean,
    val rows: List<WorkspaceRow>, val allowsControl: Boolean, val listsWorkspaces: Boolean, val otherSessionCount: Int) {
    enum class Listing { HIDDEN, UPDATE_MAC, EMPTY, ROWS }
    val showsRows: Boolean; val canControl: Boolean; val listing: Listing; val showsOtherSessions: Boolean
    companion object { fun rowsShow(state: MachineLinkState): Boolean }
}
@Composable fun WorkspaceRowView(row: WorkspaceRow, dimmed: Boolean = false, modifier: Modifier = Modifier)
@Composable fun MachineGroupHeader(group: WorkspaceGroup, showsDefault: Boolean, open: () -> Unit, modifier: Modifier = Modifier)
object MachineGroupHeaderText {
    fun time(ms: Long, context: Context): String                 // android.text.format.DateFormat.getTimeFormat(context)
    fun caption(state: MachineLinkState, machineName: String, context: Context): String?
    fun line(group: WorkspaceGroup, showsDefault: Boolean, context: Context): String        // "MacBook Pro · Default"
    fun spokenLabel(group: WorkspaceGroup, showsDefault: Boolean, context: Context): String // "MacBook Pro, Connected, Default, 4 workspaces"
}
enum class WorkspaceCommand { CREATE, RENAME, CLOSE, CLOSE_AGENT, CLOSE_TAB }
enum class WorkspaceAlert(@StringRes val message: Int) {
    OFFLINE(R.string.workspaces_alert_offline), REFUSED_CLOSE(R.string.workspaces_alert_refused_close),
    REFUSED_CONTROL(R.string.workspaces_alert_refused_control), REFUSED_CLOSE_AGENT(R.string.workspaces_alert_refused_close_agent),
    AGENT_NOT_CLOSABLE(R.string.workspaces_alert_agent_not_closable), REFUSED_CLOSE_TAB(R.string.workspaces_alert_refused_close_tab),
    TAB_NOT_CLOSABLE(R.string.workspaces_alert_tab_not_closable), FAILED(R.string.workspaces_alert_failed),
    UNKNOWN(R.string.workspaces_alert_unknown)
}
sealed interface WorkspaceFeedback {
    data object None : WorkspaceFeedback; data class Open(val ref: WorkspaceRef) : WorkspaceFeedback
    data object Refresh : WorkspaceFeedback; data class Alert(val alert: WorkspaceAlert) : WorkspaceFeedback
    companion object { fun of(result: WorkspaceCommandResult, command: WorkspaceCommand, machineId: String): WorkspaceFeedback }  // WorkspaceFeedback.swift
}
@Composable fun WorkspaceAlertDialog(alert: WorkspaceAlert?, dismiss: () -> Unit)      // message + common_ok; nothing when null
/** agent_close_title(name), agent_close_confirm, agent_close (ERROR tone), common_cancel; nothing when name is null. */
@Composable fun AgentCloseConfirmation(name: String?, close: () -> Unit, dismiss: () -> Unit)
/** The one Close Agent and Close Tab path (the home here, 3E's agent and workspace screens). Main-confined; a close already
 *  on its way sends nothing and returns null. Each command runs in hub.scope. */
object WorkspaceListActions {
    fun canClose(session: MachineSession, hub: MachineHub): Boolean      // not ENDED, agent_close, a listed tab names it
    fun closeAgent(ref: SessionRef, hub: MachineHub, alert: (WorkspaceAlert) -> Unit): Deferred<WorkspaceFeedback>?
    fun canCloseTab(machineId: String, hub: MachineHub): Boolean          // hub.supportsTerminalClose(machineId)
    fun closeTab(machineId: String, workspaceId: String, terminalId: String, hub: MachineHub,
                 alert: (WorkspaceAlert) -> Unit): Deferred<WorkspaceFeedback>?
    // Task 13 adds make(…)
}
object WorkspaceListModel {
    fun groups(hub: HubState, removed: GoneRemovals): List<WorkspaceGroup>      // default Mac first, then pairing order
    fun closableAgents(hub: MachineHub): Set<SessionRef>                         // reachable, online, WorkspaceListActions.canClose
    fun removableAgents(hub: HubState, removals: GoneRemovalStore): Set<SessionRef>
}
object OtherSessionsModel {
    fun sessions(hub: HubState, machineId: String, removed: GoneRemovals): List<MachineSession>  // removed.shown(hub.otherSessions(id))
    fun kind(session: AgentSession, finishedAtMs: Long?, nowMs: Long): FocusKind
}
```

  **The words.** `FocusRowText` follows `FocusRowView.swift` exactly:
  - **`tag`:**
    - `NEEDS_YOU` → `agent_state_needs_you`;
    - `RUNNING` → `ageText(AgentStatusRow.of(session, nowMs).elapsed)`, or `agent_state_running` without an elapsed time;
    - `JUST_DONE` → `agent_state_done`;
    - otherwise null.
  - **`timeText`**, where `since(ms)` is `max(0, nowMs - ms)`:
    - `RUNNING` → null;
    - `NEEDS_YOU` → `ageText` of `stateSinceMs ?: lastActivityMs`;
    - `JUST_DONE` → "ago" of `finishedAtMs`;
    - `ENDED` → "ago" of `stateSinceMs ?: lastActivityMs`;
    - `IDLE` → "ago" of `lastActivityMs`;
    - "ago" is `home_ago(ageText(…))`.
  - **`subLine`:** `[workspaceTitle, AgentLabel.of(agent).text, machineName if shown, timeText]`, without the empty ones, joined with `" · "`.
  - **`ageText(e)`:** `AgentStateStyle.elapsedText(max(1, e.inWholeSeconds.coerceAtLeast(0) / 60).minutes, locale)`.

  **The close paths** (`WorkspaceListView.swift`'s "Closing an agent" and "Closing a tab").
  - The in-flight keys are object-level sets, like the iPhone's statics: `SessionRef` for agents, `(machineId, terminalId)` for tabs.
  - A key already in its set → return null. Otherwise add it, and return `hub.scope.async { try { val f = WorkspaceFeedback.of(hub.closeAgent(ref) / hub.closeTerminal(…), CLOSE_AGENT / CLOSE_TAB, machineId); if (f is Alert) alert(f.alert); f } finally { remove the key } }`.

  **`FocusRowView`'s look.**
  - Padding 12 dp at the start, `12 dp + trailingInset` at the end, 10 dp vertically; min height 48 dp.
  - The background is `ShellXTheme.colors.surface` in `RoundedCornerShape(14.dp)`.
  - The 1 dp outline is `accent` at 45 % for `NEEDS_YOU`, else `onSurface` at 10 %. It is left out when the waiting border shows (`Modifier.waitingBorder(showsWaitingBorder, 14.dp)`).
  - Alpha 0.55 when offline. `semantics(mergeDescendants = true)`. Tag `home.agent.<machineId>.<sessionId>`.
  - The title line: `StatusDot(tone.color())` and the name (`titleMedium`, 1 line, 3 at large text), then the tag chip (`labelMedium` SemiBold in the tone's colour, on 14 % of it, radius 6 dp). At large text the chip goes under the name.
  - Then the sub line (`bodySmall`, `onSurfaceVariant`, 2 lines, 4 at large text), then the quoted question (`bodySmall`, `accentText`, 2 lines, 4 at large text).

  **`WorkspaceRowView`:** the title (`titleMedium`, 1 line, 3 at large text) and the branch (`bodySmall`, monospace, `onSurfaceVariant`, `TextOverflow.MiddleEllipsis`, min width 72 dp, aligned to the end). At large text the branch goes under the title. A card with radius 12 dp, alpha 0.55 when dimmed, merged semantics, tag `workspace.row.<workspaceId>`.

  **`MachineGroupHeader`:**
  - a clickable `Row` (min height 48 dp, `onClickLabel = action_open_your_macs`): `StatusDot`, `line` (`labelMedium` SemiBold, upper case in the app language, 0.6 sp tracking, `onSurfaceVariant`, 1 line, 3 at large text), a spacer, and the row count when it shows rows and lists workspaces;
  - alpha 0.55 when it shows no rows;
  - semantics: `contentDescription = spokenLabel`, `heading()`; tag `workspace.group.<id>`;
  - `caption`: `Online` → null; `Offline(since)` → `workspaces_group_offline(time(since))`; otherwise `MachineStateStyle`'s text.

- [ ] **Step 1: Write `HomeFixtures` and the failing tests.** `HomeFixtures` ports the fixtures of `WorkspaceListRenderTests.swift` with `NOW_MS = 1_700_000_000_000`:
  - the functions `ref(id, machine = "m1")`, `ms(minutesAgo)`, `session(id, title, state, minutesAgo, workspace = "shellx", agent = "claude", machine = "m1", machineName = "MacBook Pro", online = true)` and `item(session, question = null, finishedAtMs = null)`;
  - the values `shellx`, `relay`, `web`, `notes`, `broken`, `macbook`, `mini` (`Offline` since 2026-10-28 08:12 in the default zone), `pending` (p1, p2) and `mockup` (a `HomeFocus` with the same items);
  - all exact, Vietnamese titles included.

  The close tests port these tests of `WorkspaceListActionsTests.swift` onto `testComposition(root, macs)` plus `c.lifecycle.onStart()`, with `hub = c.real.coordinator.hub.value!!`, `alerts = mutableListOf<WorkspaceAlert>()` and `tasks = mutableListOf<Deferred<WorkspaceFeedback>>()`. Each close call is `WorkspaceListActions.closeAgent(ref, hub, alerts::add)?.let(tasks::add)` (or `closeTab`). "The second tap started nothing" means it returned null.

```kotlin
class FocusRowTextTest {   // FocusRowText(context.resources, Locale.ENGLISH)
    // theMockupCardsSayWhatTheIPhoneSays (port of testRendersTheMockupHome's word checks): needs-you tag "Needs you";
    //   running tags [elapsedText(8 min), elapsedText(1 min)]; just-done tag "Done"; ended tags [null, null, null];
    //   subLine(running[1]) == "toknix · Codex"; subLine(justDone[0], showsMachineName) == "shellx · Claude Code · MacBook Pro · "
    //   + home_ago(elapsedText(12 min)); quotedQuestion(needsYou[0]) == "“Cho phép chạy xcodebuild?”"; running → null
    // everySubLineEndsWithATimeExceptRunning (port)
    // timesUnderAMinuteAreOneMinuteAndNeverNegative (port)
    // anOtherSessionIsDrawnByItsState (port, OtherSessionsModel.kind; finished 10 min ago → JUST_DONE; an hour and a minute → IDLE)
    // onlyANeedsYouCardOfAnOnlineMacHasTheWaitingBorder (port of testOnlyANeedsYouCardHasTheBorder)
}
class WorkspaceGroupTest {
    // rowsShowOnlyWhileTheMacIsOrWasJustOnline (port): [true, true, true, false, false, false, false]
    // listingFollowsTheMac (port of testRendersGroupsAndStates, …OldMac…, …Empty…): macbook ROWS; mini HIDDEN; old UPDATE_MAC
    //   with showsOtherSessions; an online Mac with no rows EMPTY
    // otherSessionsNeedRowsAndSessions (port of testRendersOtherSessionsRow's assertions)
    // theCaptionSaysWhyThereAreNoRows (port of testGroupCaptionSaysWhyThereAreNoRows)
}
class WorkspaceFeedbackTest {
    // feedbackFollowsTheMacsAnswer (port of testFeedbackFollowsTheMacsAnswer, every line)
    // everyAlertSaysSomethingDifferent (port): 9 distinct non-empty messages
}
class WorkspaceListModelTest {   // runTest; testComposition(...); c.lifecycle.onStart(); hub = c.real.coordinator.hub.value!!
    // groupsPutTheDefaultMacFirstAndFlagAnOldOne (port; hub.defaultMachineId = old's id; removed = GoneRemovals.NONE)
    // aMacNotOnlineYetIsNotCalledOld (port)
    // onlyAnOnlineMacThatTakesAgentCloseOffersIt (port; failNextConnects(IOException("offline"), 1000) and dropLiveSessions())
    // onlyAnAgentWithAListedTabOffersClose (port)
}
class WorkspaceCloseTest {
    // closeAgentAsksTheMacOnce (RF 5; port of testCloseAgentAsksTheMacOnce)
    // closeAgentTheMacCannotCloseIsAnAlert (port)
    // closeAgentTheMacRefusesSaysWhy (port)
    // closeTabAsksTheMacOnce (RF 5; port)
    // closeTabTheMacCannotCloseIsAnAlert (port)
    // closeTabTheMacRefusesSaysWhy (port)
    // aMacWithoutTerminalCloseOffersNoCloseTab (port, without the WorkspaceMenuItem assertion, which is 3E's;
    //   phoneFrameCount → phoneCallCount)
}
```

- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.ui.home.FocusRowTextTest' --tests 'com.shellx.app.ui.workspaces.*'`.

  Expected: `Unresolved reference: FocusRowText`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test` and `git commit -m "test(shellx-android): home cards, groups, the Mac's answers and the close paths"`.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run (green).** Run the Step 2 command twice. Expected: PASS, with `FocusRowTextTest` 5, `WorkspaceGroupTest` 4, `WorkspaceFeedbackTest` 2, `WorkspaceListModelTest` 4 and `WorkspaceCloseTest` 7.
- [ ] **Step 6: Commit.** Run `git add shellx-android/app/src/main` and `git commit -m "feat(shellx-android): agent and workspace cards, Mac groups, command feedback and the close paths"`.

---

### Task 13: The home screen, its actions and the 30-second re-sort

**Files:**
- Create in `app/ui/workspaces/`: `WorkspaceListScreen.kt` (`WorkspaceListScreen`, `WorkspaceListScreenActions`), `WorkspaceListView.kt`, `WorkspaceRenameSheet.kt` (`WorkspaceRenameSheet`, `WorkspaceRenameContent`)
- Modify: `app/ui/workspaces/WorkspaceListActions.kt` (add `make`), `app/ui/workspaces/ListNotice.kt` (add `NoticeCapsule`), `docs/superpowers/ledgers/shellx-android-parity.md`
- Test: `app-test/ui/workspaces/WorkspaceListActionsTest.kt`, `app-ui-test/ui/workspaces/WorkspaceListScreenTest.kt`, `app-ui-test/ui/workspaces/WorkspaceListViewTest.kt`, `app-ui-test/screenshots/HomeRenderTest.kt`

Reference: `ios/UI/Workspaces/{WorkspaceListScreen,WorkspaceListView,WorkspaceRenameSheet,ListNotice}.swift`, `ios-tests/{WorkspaceListActionsTests,WorkspaceListRenderTests}.swift`.

**Interfaces:**
- Consumes: Tasks 6, 7 and 12; 3C's `HomeFocus.make`, `DecisionCenter.visibleItems`, `WorkspaceTitle`, `takeGraphemes`.
- Produces (`com.shellx.app.ui.workspaces`):

```kotlin
/** WorkspaceListScreen.Actions. */
class WorkspaceListScreenActions(
    val openWorkspace: (WorkspaceRef) -> Unit = {}, val create: (String) -> Unit = {}, val rename: (WorkspaceRef, String) -> Unit = { _, _ -> },
    val close: (WorkspaceRef) -> Unit = {}, val closeAgent: (SessionRef) -> Unit = {}, val removeFromPhone: (MachineSession) -> Unit = {},
    val openAgent: (SessionRef) -> Unit = {}, val openPending: () -> Unit = {}, val openSettings: () -> Unit = {},
    val openMachines: () -> Unit = {}, val openOtherSessions: (String) -> Unit = {}, val openEnded: () -> Unit = {},
    val refresh: suspend () -> Unit = {},
)
@Composable fun WorkspaceListScreen(groups: List<WorkspaceGroup>, focus: HomeFocus, pending: List<MachinePendingItem>, nowMs: Long,
    creating: Boolean = false, notice: Notice? = null, showsMachineNames: Boolean = false,
    closableAgents: Set<SessionRef> = emptySet(), removableAgents: Set<SessionRef> = emptySet(),
    actions: WorkspaceListScreenActions = WorkspaceListScreenActions(), alert: WorkspaceAlert? = null, onAlertDismissed: () -> Unit = {})
@Composable fun NoticeCapsule(text: String, modifier: Modifier = Modifier)     // in ListNotice.kt; polite live region; tag workspaces.notice
// added to object WorkspaceListActions (WorkspaceListActions.make in Swift)
fun make(scope: SignedInScope, navigator: ShellXNavigator, alert: (WorkspaceAlert) -> Unit, creating: MutableState<Boolean>,
         done: (Deferred<WorkspaceFeedback>) -> Unit = {}): WorkspaceListScreenActions
/** The home (routes `home` and `demo`, through SignedInView): WorkspaceListScreen fed by `scope`, re-sorted by `ticks`. */
@Composable fun WorkspaceListView(scope: SignedInScope, navigator: ShellXNavigator, ticks: Flow<Unit> = remember { HomeTicks.every() })
@Composable fun WorkspaceRenameSheet(current: String, save: (String) -> Unit, cancel: () -> Unit)   // ModalBottomSheet; 3E reuses it
@Composable fun WorkspaceRenameContent(current: String, save: (String) -> Unit, cancel: () -> Unit, modifier: Modifier = Modifier)
```

  **`WorkspaceListActions.make`** (`WorkspaceListActions.make` in Swift).
  - `run(command, machineId, call)` = `done(scope.hub.scope.async { val f = WorkspaceFeedback.of(call(), command, machineId); when (f) { is Open → navigator.openWorkspace(f.ref); Refresh → hub.refreshWorkspaces(machineId); is Alert → alert(f.alert); None → {} }; f })`.
  - The actions:
    - `openWorkspace` → `hub.markSeen(ref)`, then `navigator.openWorkspace(ref)`;
    - `create` → nothing while `creating.value`; otherwise `creating.value = true`, and run `CREATE`, setting `creating.value = false` in `finally`;
    - `rename` → `RENAME`; `close` → `CLOSE`;
    - `closeAgent` → `closeAgent(ref, hub, alert)?.let(done)`;
    - `removeFromPhone` → `scope.goneRemovals.remove(session)`;
    - `openAgent`, `openPending`, `openSettings`, `openMachines` → the navigator;
    - `openOtherSessions(m)` → `openSessions(OTHER, m)`; `openEnded` → `openSessions(ENDED)`;
    - `refresh` → `hub.refreshWorkspaces()`.

  **`WorkspaceListScreen`'s layout** (`WorkspaceListScreen.swift`, in Compose).
  - A `Scaffold` with a `TopAppBar`:
    - title `root_title`;
    - the bell: `BadgedBox` over `Icons.Outlined.Notifications`, with a `Badge` (container `accent`, content `onAccent`) showing "99+" above 99. Its description is `workspaces_bell` with no item, else `pending_section_title` (count). Tag `workspaces.bell`.
    - ＋ (`Icons.Filled.Add`, description `workspaces_create`, tag `workspaces.create`). It uses the groups with `canControl`: with one, it creates there; with several, a `DropdownMenu` headed `workspaces_create_pick_mac` lists their names; with none, or while `creating`, it is disabled.
    - Settings (`Icons.Outlined.Settings`, description `settings_title`, tag `root.settings`).
  - The body is a `PullToRefreshBox(isRefreshing, onRefresh = { refreshing = true; launch { actions.refresh(); refreshing = false } })` around a `LazyColumn` with stable keys, in this order:
    1. When `focus.isQuiet`, `home_quiet` (tag `home.quiet`). Otherwise, for "Needs you", "Running" and "Just finished", each only when it has cards: a `SectionTitle` (`home_needs_you`, `home_running`, `home_just_done`, with the count), then one card per item.
    2. `SectionTitle(home_workspaces)`, then per group:
       - its `MachineGroupHeader` (`open = actions.openMachines`);
       - its listing: `UPDATE_MAC` → a card with `Icons.Outlined.ArrowCircleUp` and `workspaces_old_mac` (tag `workspace.updateMac.<id>`); `EMPTY` → `workspaces_empty` (tag `workspace.empty.<id>`);
       - when it shows rows, an `ActionRow` per row, dimmed unless `Online`;
       - when `showsOtherSessions`, a row "`workspaces_other` (count) ›" (tag `workspace.otherSessions.<id>`).
    3. When `focus.ended` is not empty, the fold "`home_ended` (count) ›", with a dashed 1 dp outline (`PathEffect.dashPathEffect([4dp, 3dp])`, `onSurface` at 20 %) and tag `home.ended`.
  - Card insets are 12 dp across and 3 dp down. A section title has 16 dp at the top and 4 dp at the bottom.
  - Each card is an `ActionRow`:
    - agent cards use `RowActions.agentCard(id in closableAgents, id in removableAgents)`, `onClick = openAgent(id)` and `onClickLabel = action_open_agent`;
    - workspace cards use `RowActions.workspaceCard(group.canControl)` and `onClick = openWorkspace(row.id)`.
  - The kinds:
    - `CLOSE_AGENT` sets `closingAgent`; `CLOSE_WORKSPACE` sets `closing`; `RENAME_WORKSPACE` sets `renaming`;
    - `REMOVE_FROM_PHONE` runs `removeFromPhone(item.session)` at once.
    - The three targets are `rememberSaveable` through `WorkspaceRefSaver` and `SessionRefSaver`, and are looked up again in `groups` and `focus`; a target that has gone closes its dialog.
  - The dialogs:
    - `closing` → `ConfirmDialog(workspaces_close_title(title), workspaces_close_confirm, workspaces_close)`, then `close(ref)`;
    - `AgentCloseConfirmation(closingAgent?.name, close = { closeAgent(id) }, dismiss = { closingAgent = null })`;
    - `renaming` → `WorkspaceRenameSheet(row.title, save = { renaming = null; rename(ref, it) }, cancel = { renaming = null })`;
    - `WorkspaceAlertDialog(alert, onAlertDismissed)`.
  - `notice` → a `NoticeCapsule` at the bottom centre, above the navigation bar.

  **`WorkspaceRenameContent`.**
  - `workspaces_rename_title` (`titleLarge`).
  - An `OutlinedTextField` labelled `workspaces_rename_placeholder`: single line, `ImeAction.Done` (commits), no capitalisation, no autocorrect, focused on show. Its value starts as `current.takeGraphemes(128)`, and every edit is cut to 128 graphemes. Tag `workspace.rename.field`.
  - A row with a `common_cancel` `TextButton`, and a `workspaces_rename_save` `TextButton` (tag `workspace.rename.save`) enabled when `WorkspaceTitle.canSave(text)`, which saves `WorkspaceTitle.cleaned(text)`.
  - `Modifier.imePadding()`.
  - `WorkspaceRenameSheet` puts it in a `ModalBottomSheet(onDismissRequest = cancel, skipPartiallyExpanded = true)`.

  **`WorkspaceListView`.**
  - It collects `scope.hub.state`, `scope.decisions.state`, `scope.goneRemovals.state`, `scope.endedDismissals.dismissals` and `scope.listNotice.current`, with `nowMs = rememberNowMs(scope.clock, ticks)`.
  - It passes:
    - `groups = WorkspaceListModel.groups(hub, removals)`;
    - `pending = scope.decisions.visibleItems(hub.pendingItems)`;
    - `focus = HomeFocus.make(hub.reachableSessions, pending, hub.finishTimes, dismissed, removed, nowMs)`;
    - `showsMachineNames = hub.machines.size > 1`;
    - `closableAgents = WorkspaceListModel.closableAgents(scope.hub)` and `removableAgents = WorkspaceListModel.removableAgents(hub, scope.goneRemovals)`;
    - `actions = remember(scope) { WorkspaceListActions.make(scope, navigator, { alert = it }, creating) }`.
  - Effects:
    - `LaunchedEffect(Unit) { scope.homeShown() }`;
    - `LaunchedEffect(hub.defaultMachineListedWorkspaces) { if (it) scope.workspacesListed() }`;
    - `LaunchedEffect(notice?.id) { delay(ListNotice.DURATION); scope.listNotice.clear(id) }`.

- [ ] **Step 1: Write the failing tests.**
  - **`WorkspaceListActionsTest`** ports the twelve `make`-based tests of `ios-tests/WorkspaceListActionsTests.swift` (Task 12 ported the other eleven):
    - `testControlsPushTheirScreens`, `testEndedFoldPushesTheEndedPage`, `testOpeningAWorkspaceMarksItSeen`;
    - `testCreateOpensTheNewWorkspace`, `testASecondTapOnCreateWaitsForTheFirst` (RF 5);
    - `testRenameChangesTheRowByPush`, `testCloseRemovesTheRowByPush`, `testClosingTheLastWorkspaceIsAnAlert`, `testRenameBlockedByTheMacIsAnAlert`;
    - `testAWorkspaceTheMacDoesNotHaveRefreshesTheListQuietly`, `testAMacThatIsNotOnlineAnswersOfflineWithAnAlert`, `testPullToRefreshAsksTheOnlineMacsAgain`.

    The rig translates like this:
    - `makeRig(macs)` → `t = testComposition(root, macs)`, `c.lifecycle.onStart()`, then `waitFor` until `real.scopes.current` is non-null;
    - the rig's parts: `nav = RecordingNavigator()`, `alerts = mutableListOf<WorkspaceAlert>()`, `tasks = mutableListOf<Deferred<WorkspaceFeedback>>()`, `creating = mutableStateOf(false)`, `actions = WorkspaceListActions.make(scope, nav, alerts::add, creating) { tasks += it }`;
    - `rig.screen.routes` → `nav.calls`: `.workspace(r)` → `"workspace:<m>/<w>"`, `.pending` → `"pending"`, `.settings` → `"settings"`, `.machines` → `"machines"`, `.otherSessions(m)` → `"sessions:other:<m>"`, `.ended` → `"sessions:ended"`;
    - `lastFeedback()` → `tasks.last().await()`.
  - **`WorkspaceListScreenTest`** (Compose, over `HomeFixtures`). Each comment line is one `@Test`:

```kotlin
class WorkspaceListScreenTest {
    // aWorkspaceCardOpensItsWorkspace: click "workspace.row.ws-relay" → openWorkspace(ref("ws-relay"))
    // swipingAWorkspaceAsksBeforeClosingIt: swipe "workspace.row.ws-web" → "Close “web”?" → click the dialog's "Close" →
    //   close(ref("ws-web")) once; Cancel instead → none
    // renameFromTheLongPressMenu: longClick the web row → "Rename Workspace" → "workspace.rename.field" holds "web"; type
    //   "  landing  " over it → "workspace.rename.save" → rename(ref("ws-web"), "landing"); a blank field → save not enabled
    // aMacThatCannotTakeCommandsOffersNoRowActions: macbook with allowsControl = false → swipe and long press do nothing
    // anAgentCardSwipesToCloseAndAsks: closableAgents = {running[0].id} → swipe its card → "Close Viết test SessionSet?" →
    //   confirm → closeAgent(running[0].id)
    // aGoneAgentSwipesToRemoveWithoutAQuestion: removableAgents = {running[1].id} only → swipe → removeFromPhone(that session),
    //   no dialog
    // theBellSaysHowManyWait: pending of 2 → "workspaces.bell" has contentDescription "Needs you · 2"; none → "Needs you"
    // plusPicksTheMacWhenSeveralTakeCommands: two groups with canControl → click "workspaces.create" → both names shown →
    //   "Mac mini" → create("m2"); one → create("m1") at once; none, or creating = true → not enabled
    // headersFoldsAndRowsOpenTheirPages: "workspace.group.m1" → openMachines; "workspace.otherSessions.m1" → openOtherSessions("m1");
    //   "home.ended" → openEnded; an agent card → openAgent(its id)
    // anAlertIsShownUntilDismissed: alert = OFFLINE → workspaces_alert_offline shown; OK → onAlertDismissed 1
    // anOpenConfirmationSurvivesRecreation (RF 1): StateRestorationTester; swipe web → dialog; emulateSaveAndRestore() →
    //   "Close “web”?" still displayed
}
```

  - **`WorkspaceListViewTest`** (Compose, real main thread: `mainComposition(root, listOf(mac), appScope, clock = clock)`, `c.lifecycle.onStart()`). `theHomeRegroupsEveryThirtySeconds` (ledger 6.2-7):
    - Set up `mac = FakeMac("MacBook Pro", appScope, nowMs = clock::nowMs)`, with session `s1` WORKING in workspace `shellx`.
    - Wait until the scope exists. Set content to `WorkspaceListView(scope, RecordingNavigator(), ticks)`, with `ticks = MutableSharedFlow<Unit>(extraBufferCapacity = 1)`.
    - `upsertSession(s1 IDLE)` → `waitUntil` "Just finished · 1" is displayed.
    - `clock.advance(3_601.seconds)` and `ticks.tryEmit(Unit)` → `waitUntil` "Just finished · 1" is gone.
    - In `@After`, cancel `appScope`.
  - **`HomeRenderTest`** ports the home renders of `WorkspaceListRenderTests.swift`, each with `assertRenders`:
    - `home-focus`, `home-focus-large-text` (inside `LargeText`), `home-quiet`, `home-old-mac`, `home-two-macs`;
    - `workspaces` (the bell count 2), `workspaces-error`, `workspaces-large-text`, `workspaces-old-mac`, `workspaces-other-sessions`, `workspaces-empty`, `workspaces-offline`;
    - `workspaces-rename` (`WorkspaceRenameContent("shellx-ios", …)`).
- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.ui.workspaces.WorkspaceList*' --tests 'com.shellx.app.screenshots.HomeRenderTest'`.

  Expected: `Unresolved reference: make` (or `WorkspaceListScreen`).
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test shellx-android/app/src/testDebug` and `git commit -m "test(shellx-android): the home, its actions and its re-sort"`.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run (green).** Run the Step 2 command twice. Expected: PASS, with 12, 11, 1 and 13 tests; Task 12's classes still pass.

  Open `home-focus-light-en.png`, `home-focus-dark-vi.png` and `workspaces-large-text-light-vi.png`. Compare them with the iPhone's mockup A:
  - the groups are in the iPhone's order;
  - the needs-you card has its multicolour ring;
  - running is yellow;
  - the branch sits at the right;
  - nothing is clipped.
- [ ] **Step 6: Ledger and commit.**
  - Set rows `6.1-5` and `6.2-7` to `done (3D)`.
  - In row `6.1-5`, move `NeedsYouBar.swift` out of the iPhone cell into row `6.1-10`'s iPhone cell (3E's agent screen shows it, Spec note 5).
  - Run `git add shellx-android/app/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): the home with agent groups, Mac groups, row actions and a 30-second re-sort"`.

---

### Task 14: Session lists: agents outside workspaces and Ended

**Files:**
- Create: `app/ui/home/SessionListScreen.kt`, `app/ui/home/EndedSessionsView.kt`, `app/ui/workspaces/OtherSessionsView.kt`
- Modify: `docs/superpowers/ledgers/shellx-android-parity.md`
- Test: `app-ui-test/ui/home/SessionListScreenTest.kt`, `app-test/ui/home/EndedDismissalsWiringTest.kt`, `app-test/ui/home/GoneRemovalWiringTest.kt`, `app-ui-test/screenshots/SessionListRenderTest.kt`

Reference: `ios/UI/Home/{SessionListScreen,EndedSessionsView}.swift`, `ios/UI/Workspaces/OtherSessionsView.swift`; `ios-tests/{EndedDismissalsWiringTests,GoneRemovalWiringTests}.swift`; the list renders of `WorkspaceListRenderTests.swift`.

**Interfaces:**
- Consumes: Tasks 6, 7, 12 and 13.
- Produces:

```kotlin
// com.shellx.app.ui.home
/** SessionListScreen.swift: cards from plain values; `remove` draws a trash at each card's end and is its swipe. */
@Composable fun SessionListScreen(title: String, header: String?, items: List<FocusItem>, kind: (FocusItem) -> FocusKind, nowMs: Long,
    showsMachineName: Boolean, @StringRes empty: Int, openAgent: (SessionRef) -> Unit, back: () -> Unit,
    remove: ((FocusItem) -> Unit)? = null, removableGone: Set<SessionRef> = emptySet(), removeGone: (FocusItem) -> Unit = {})
/** Route sessions/ended: HomeFocus.make(reachable, [], emptyMap(), dismissed, removed, nowMs).ended; remove = endedDismissals.dismiss. */
@Composable fun EndedSessionsView(scope: SignedInScope, navigator: ShellXNavigator, ticks: Flow<Unit> = remember { HomeTicks.every() })
// com.shellx.app.ui.workspaces
/** Route sessions/other?machineId=…: OtherSessionsModel.sessions; removableGone = goneRemovals.removable(those); removeGone = remove. */
@Composable fun OtherSessionsView(scope: SignedInScope, machineId: String, navigator: ShellXNavigator, ticks: Flow<Unit> = remember { HomeTicks.every() })
```

  **The screen.**
  - A `Scaffold` with a `TopAppBar` (title, back) and a `LazyColumn`.
  - With no items: `empty` (`bodyMedium`, `onSurfaceVariant`, centred, 24 dp vertical padding, tag `sessionList.empty`).
  - Otherwise: the optional header as a `SectionTitle`, then one `ActionRow` per item:
    - the plan is `RowActions.endedCard()` when `remove` is set, else `RowActions.otherSessionCard(item.id in removableGone)`;
    - `onClick = openAgent(item.id)`, `onClickLabel = action_open_agent`;
    - the content is `FocusRowView(item, kind(item), nowMs, showsMachineName, trailingInset = if (remove != null) 48.dp else 0.dp)`, tag `sessionList.row.<sessionId>`.
  - With `remove`, a 48 dp `IconButton` (`Icons.Outlined.Delete`, `onSurfaceVariant`, description `ended_remove_named` with the name, tag `sessionList.remove.<sessionId>`) sits over the card's end edge.
  - The kinds: `REMOVE_ENDED` → `remove(item)`; `REMOVE_FROM_PHONE` → `removeGone(item)`.
- The routes:
  - `EndedSessionsView`: title `ended_title`, header null, kind `ENDED`, `showsMachineName = machines.size > 1`, empty `ended_empty`.
  - `OtherSessionsView`: title `workspaces_other_title`, header = the Mac's name, kind `OtherSessionsModel.kind(session, finishedAtMs, nowMs)`, empty `workspaces_other_empty`, names from `SessionName.distinct`, finish times from `hub.finishTimes[machineId]`.

- [ ] **Step 1: Write the failing tests.**

```kotlin
// app-ui-test
class SessionListScreenTest {
    // theTrashAndTheSwipeTakeAnEndedCardOff: remove counts → click "sessionList.remove.e1" → remove(e1); swipe e2 → remove(e2)
    // aGoneSessionSwipesToRemoveFromThisPhone: removableGone = {s2} → swipe s2 → removeGone(s2); swipe s1 → nothing
    // anEmptyListSaysSo: items = [] → "sessionList.empty" shows ended_empty
    // aCardOpensItsAgent: click s1 → openAgent(s1's ref)
}
class EndedDismissalsWiringTest {   // port of testACardTakenOffTheEndedPageStaysOffAfterALaunch
    // aCardTakenOffTheEndedPageStaysOffAfterALaunch: two scopes made with AppComposition.makeScope over the same
    //   MemoryKeyValueStore (the second is the "next launch") → dismissals of the first are seen by the second's HomeFocus
}
class GoneRemovalWiringTest {   // port of GoneRemovalWiringTests' rig with testComposition; the agent screen's part is 3E's:
    //   `scope.goneRemovals.noteGone(session)` stands in for AgentView.noteGone
    // aRemovedGhostLeavesEveryListAndCountAndStaysOffAfterALaunch (port)
    // aRemovedGhostComesBackWhenItsMacReportsAChange (port)
}
```

  `SessionListRenderTest` ports `testOtherSessionsListRenders` (`workspaces-other-sessions-list`, `workspaces-other-sessions-empty`), `testEndedListRenders` (`ended-list`) and `testEndedListEmptyRenders` (`ended-empty`), each with `assertRenders`.
- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.ui.home.*' --tests 'com.shellx.app.screenshots.SessionListRenderTest'`.

  Expected: `Unresolved reference: SessionListScreen`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test shellx-android/app/src/testDebug` and `git commit -m "test(shellx-android): session lists, ended dismissals and gone removals"`.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run (green).** Expected: PASS, with 4, 1, 2 and 4 tests; `FocusRowTextTest` still passes.
- [ ] **Step 6: Ledger and commit.** Set row `6.1-6` to `done (3D)`; its Android cell becomes `app:ui/home/SessionListScreen.kt`, `EndedSessionsView.kt`, `app:ui/workspaces/OtherSessionsView.kt`, `app:ui/nav/Routes.kt` (route `sessions/{kind}`). Run `git add shellx-android/app/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): agents outside workspaces and the Ended page"`.

---

### Task 15: Settings, with account deletion

**Files:**
- Create in `app/ui/settings/`: `SettingsScreen.kt` (with `SettingsSection`), `AccountSection.kt` (`AccountActions`, `AccountSection`), `DeleteAccountDialog.kt` (`DeleteAccountFlow`, `DeleteAccountCard`, `DeleteAccountDialog`), `AppearanceSection.kt`, `VoiceSection.kt` (`VoiceSection`, `VoiceSectionText`), `NotificationsSettingsSection.kt`, `AboutSection.kt` (`AboutSection`, `AboutLinks`, `versionText`)
- Modify: `docs/superpowers/ledgers/shellx-android-parity.md`
- Test: `app-test/ui/settings/DeleteAccountFlowTest.kt`, `app-test/ui/settings/SettingsTextTest.kt`, `app-ui-test/ui/settings/SettingsScreenTest.kt`, `app-ui-test/screenshots/SettingsRenderTest.kt`

Reference: `ios/UI/Settings/{SettingsView,AccountSection,AppearanceSection,VoiceSection,AboutSection}.swift`; 1C Task 11 (Delete Account, `AccountActions`); S1 §6.8; contracts §12 (the deletion path), §15 (the section order) and §20 (Settings › Voice is 3D's; 3E fills the Notifications slot with this layout).

**Interfaces:**
- Consumes: Tasks 6, 9 (`SignInErrorText`) and 7; 3C's `VoiceService`, `VoiceLanguage`, `VoiceEngine`, `SignInException`.
- Produces (`com.shellx.app.ui.settings`):

```kotlin
/** What Settings › Account can do; null in the demo (only the e-mail row shows). */
class AccountActions(val signOut: suspend () -> Unit, val deleteAccount: suspend () -> Unit)
@Composable fun SettingsScreen(email: String, account: AccountActions?, appearance: AppAppearance, onAppearance: (AppAppearance) -> Unit,
                               voice: VoiceService?, version: String, openMachines: () -> Unit, back: () -> Unit)
/** One section's look, for every section here and for 3E's Notifications section: a title, a card of rows, a footer. */
@Composable fun SettingsSection(title: String?, footer: String? = null, content: @Composable ColumnScope.() -> Unit)
@Composable fun AccountSection(email: String, account: AccountActions?)
/** S1 §6.8. Main-confined. */
class DeleteAccountFlow(private val delete: suspend () -> Unit) {
    sealed interface Step { data object Confirm : Step; data object Working : Step; data class Failed(@StringRes val message: Int) : Step }
    val step: StateFlow<Step>
    /** Does nothing while Working. Working; then success stays Working (the screen goes as the account signs out);
     *  SignInException.Cancelled → Confirm; another SignInException → Failed(SignInErrorText.message ?: signin_error_server);
     *  any other non-cancellation exception → Failed(signin_error_server). */
    suspend fun run()
}
@Composable fun DeleteAccountCard(step: DeleteAccountFlow.Step, onDelete: () -> Unit, onCancel: () -> Unit, modifier: Modifier = Modifier)
@Composable fun DeleteAccountDialog(flow: DeleteAccountFlow, onDismiss: () -> Unit)   // BasicAlertDialog; dismiss ignored while Working
@Composable fun AppearanceSection(appearance: AppAppearance, onAppearance: (AppAppearance) -> Unit)
@Composable fun VoiceSection(service: VoiceService)
object VoiceSectionText {
    @StringRes fun name(language: VoiceLanguage): Int                       // voice_language_vietnamese / voice_language_english
    fun explanation(engine: VoiceEngine?, language: VoiceLanguage, res: Resources): String
}
/** Plan 3E fills it (contracts §15, §20). Renders nothing until then. */
@Composable fun NotificationsSettingsSection() {}
object AboutLinks { const val WEBSITE = "https://shellx.pro"; const val WEBSITE_HOST = "shellx.pro" }
fun versionText(versionName: String, versionCode: Long): String              // "1.0.0 (100)"
@Composable fun AboutSection(version: String)
```

  **`SettingsScreen`** (`SettingsView.swift`).
  - A `Scaffold` with a `LargeTopAppBar` (title `settings_title`, back, `exitUntilCollapsedScrollBehavior`). The body is a `LazyColumn` of sections, in this order:
    1. `SettingsSection(null)` with one row: `Icons.Outlined.Laptop`, `machines_title`, a chevron; tag `settings.machines`; `onClick = openMachines`;
    2. `AccountSection`;
    3. `AppearanceSection`;
    4. `VoiceSection`, when `voice` is set;
    5. `NotificationsSettingsSection()`;
    6. `AboutSection`.
  - **`SettingsSection`:** an optional title (`labelLarge`, `accentText`, heading, 16 dp start padding), then a `Surface` card (radius 16 dp, `surfaceContainer`) holding `content` as `ListItem`s (transparent containers) with inset dividers, then an optional footer (`bodySmall`, `onSurfaceVariant`).
  - **Account** (`settings_account_title`):
    - the e-mail row: `signin_email`, with the e-mail as trailing text in a `SelectionContainer`.
    - With `account`, a "Sign out" row (`settings_account_sign_out`, `ERROR` tone, tag `settings.signOut`). While signing out it shows a trailing spinner and is disabled. It opens `ConfirmDialog(settings_account_sign_out, settings_account_sign_out_confirm, settings_account_sign_out)`. Confirming does nothing while `signingOut`; otherwise it sets `signingOut = true` and runs `account.signOut()`, then sets it back.
    - Then "Delete Account…" (`settings_account_delete`, `ERROR` tone, tag `settings.delete`), which shows `DeleteAccountDialog(remember { DeleteAccountFlow(account.deleteAccount) })`.
  - **Appearance** (`settings_appearance_title`): the label `settings_appearance_mode`, then a `SingleChoiceSegmentedButtonRow` of the three `AppAppearance.title`s (tag `settings.appearance`).
  - **Voice** (`settings_voice_title`):
    - a row `settings_voice_language` whose trailing text is the current language's name; a tap opens a `DropdownMenu` of the two languages, and the choice runs `service.setLanguage(it)`. Tag `settings.voice.language`.
    - The footer is `explanation(engine, language)` (tag `settings.voice.engine`) when `engineKnown`, else a small spinner.
    - `LaunchedEffect(language) { service.refreshEngine() }`.
    - `explanation`: `ON_DEVICE_RECOGNIZER` and `ON_DEVICE` → `settings_voice_on_device`; `SERVER` → `settings_voice_server` (the language's name); null → `settings_voice_unavailable`.
  - **About** (`settings_about_title`):
    - `settings_about_version` with the trailing `version`, merged for TalkBack;
    - `settings_about_license` with trailing `AboutLinks.WEBSITE_HOST` and `Icons.AutoMirrored.Outlined.OpenInNew`, tag `settings.about.license`; `onClick = LocalUriHandler.current.openUri(AboutLinks.WEBSITE)`.

  **`DeleteAccountCard`.**
  - A `Surface` (radius 28 dp, `surfaceContainerHigh`, 24 dp padding).
  - `Icons.Filled.Warning` in the `ERROR` tone, `settings_account_delete_title` (`headlineSmall`), `settings_account_delete_message`.
  - For `Failed`, its message in the `ERROR` tone (tag `delete.error`, `liveRegion = Polite`).
  - The buttons, at the end: `TextButton` `common_cancel` (tag `delete.cancel`), then `TextButton` `settings_account_delete_button` in the `ERROR` tone (tag `delete.confirm`).
  - `Working` replaces the message line with a spinner and `settings_account_delete_deleting` (tag `delete.working`), and disables both buttons.
  - `DeleteAccountDialog`'s `onDelete` is `rememberCoroutineScope().launch { flow.run() }`. 3C's `deleteAccount` runs detached; the coordinator's sign-out ends the screen.

- [ ] **Step 1: Write the failing tests.**

```kotlin
class DeleteAccountFlowTest {   // runTest
    // aDeletionThatWorksStaysWorking: delete returns → step == Working
    // closingTheGoogleSheetGoesBackToTheQuestion: throws SignInException.Cancelled() → Confirm
    // aRefusedReauthenticationSaysWhy: throws ReauthRequired() → Failed(R.string.signin_error_reauth_required);
    //   throws IllegalStateException() → Failed(R.string.signin_error_server)
    // deleteTappedTwiceDeletesOnce (RF 5): delete waits on a gate; launch run() twice → delete called once; open → Working
}
class SettingsTextTest {
    // theVoiceLineNamesThePathUsed: ON_DEVICE and ON_DEVICE_RECOGNIZER → settings_voice_on_device; SERVER with VIETNAMESE →
    //   contains "Vietnamese"; null → settings_voice_unavailable
    // licensesLinkToTheWebsiteAndShowItsHost (port): Uri.parse(WEBSITE).host == WEBSITE_HOST; versionText("1.0.0", 100) == "1.0.0 (100)"
}
// app-ui-test
class SettingsScreenTest {
    // sectionsComeInTheContractOrder: voice = a VoiceService over private fakes in this file (a SpeechEngine that hears nothing,
    //   a VoicePermissionChecking that grants all; not 3E's FakeSpeechEngine) → the heading texts top to bottom ==
    //   [Account, Appearance, Voice, About]; "settings.machines" sits above the Account heading; voice = null →
    //   [Account, Appearance, About]
    // signOutAsksFirst: "settings.signOut" → the dialog with settings_account_sign_out_confirm → confirm → signOut 1
    // signOutTappedTwiceSignsOutOnce (RF 5): signOut waits on a gate; confirm; open the dialog again and confirm → signOut 1
    // deletingAsksThenWorksThenLeaves: "settings.delete" → the card with settings_account_delete_message → "delete.confirm"
    //   → "delete.working" shown, both buttons not enabled; deleteAccount called once
    // aCancelledOrRefusedDeletionSaysSoInTheCard: deleteAccount throws Cancelled → back to the question, no "delete.error";
    //   throws ReauthRequired → "delete.error" shows signin_error_reauth_required
    // theDemoShowsOnlyTheEmail: account = null → "demo@shellx.pro" shown; no "settings.signOut", no "settings.delete"
    // appearanceChangesAtOnce: click "Dark" → onAppearance(DARK)
    // licensesOpensTheWebsite: a LocalUriHandler fake → click "settings.about.license" → "https://shellx.pro"
}
```

  `SettingsRenderTest` captures, each with `assertRenders`:
  - `settings` (account set, voice null);
  - `settings-voice` (the fake `VoiceService`, ENGLISH);
  - `settings-demo` (account null, `demo@shellx.pro`);
  - `delete-account-confirm`, `delete-account-working` and `delete-account-failed` (`DeleteAccountCard` with `Failed(R.string.signin_error_reauth_required)`).
- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.ui.settings.*' --tests 'com.shellx.app.screenshots.SettingsRenderTest'`.

  Expected: `Unresolved reference: DeleteAccountFlow`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test shellx-android/app/src/testDebug` and `git commit -m "test(shellx-android): settings and account deletion"`.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run (green).** Expected: PASS, with 4, 2, 8 and 6 tests. Open `settings-light-vi.png` and `delete-account-confirm-dark-en.png`: the e-mail is readable, Sign out and Delete are red, the segments fit, and the version reads "1.0.0 (100)".
- [ ] **Step 6: Ledger and commit.**
  - Set row `6.1-13` to `done (3D)`.
  - In row `6.1-14`, set Plan to `3D (section), 3E (engine)`, Android to `app:ui/settings/VoiceSection.kt`, and keep `todo`: the section shows once 3E's `makeVoice` is plugged in.
  - Add an `A-` row:
    - difference: "Delete Account… is a dialog: the question, then Google's sheet for a fresh sign-in, then the deletion; Google only, and no 'switch to Google first' step";
    - why: "S1 §6.8; an Android session is always Google (contracts §5)";
    - Android: `app:ui/settings/DeleteAccountDialog.kt`.
  - Run `git add shellx-android/app/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): Settings with account, appearance, voice, about and account deletion"`.

---

### Task 16: Navigation host, the app root and the activity

**Files:**
- Create: `app/ui/nav/ShellXNavHost.kt` (`ShellXNavHost`, `RootSync`, `NavControllerNavigator`, `SignedIn`, `WorkPlaceholder`), `app/ui/ShellXApp.kt`, `app/ui/SignedInView.kt`, `app/ui/SignedInFrame.kt`
- Modify: `app/MainActivity.kt`, `docs/superpowers/ledgers/shellx-android-parity.md`
- Test: `app-ui-test/ui/nav/RootSyncTest.kt`, `app-ui-test/ShellXAppSmokeTest.kt`, `app-test/MainActivityTest.kt` (`@Config(application = ShellXApplication::class)`)

Reference: `ios/UI/{RootView,SignedInView}.swift`, `ios/ShellXApp.swift`, `ios/UI/Home/HomeRoute.swift`; 1C Task 13 (`DemoRootView`); `ios-tests/{LaunchSmokeTests,DemoCompositionTests}.swift`; 3E Task 12 (the three destinations it replaces, its `SignedInWork` wrapper, and its edits to `MainActivity`).

**Interfaces:**
- Consumes: every task before.
- Produces:

```kotlin
// com.shellx.app.ui.nav
/** The app's NavHost (contracts §5): startDestination launch; RootSync keeps composition.root at the bottom of the stack.
 *  `nav` is the name 3E's Task 12 code uses. */
@Composable fun ShellXNavHost(composition: AppComposition, nav: NavHostController, modifier: Modifier = Modifier)
/** Keeps `root` as the only root destination (the algorithm below). */
@Composable fun RootSync(nav: NavHostController, root: String)
/** A signed-in destination's body: the active account's scope, or LaunchView while there is none. */
@Composable fun SignedIn(composition: AppComposition, content: @Composable (SignedInScope) -> Unit)
/** The three work routes until plan 3E replaces them: a top bar with back and `title`, no body. */
@Composable internal fun WorkPlaceholder(title: String, back: () -> Unit)
class NavControllerNavigator(private val nav: NavHostController, private val scope: () -> SignedInScope?) : ShellXNavigator
// com.shellx.app.ui
/** The window: the "Demo · Exit" banner over the NavHost while the demo is active, and the links into pairing. */
@Composable fun ShellXApp(composition: AppComposition, nav: NavHostController = rememberNavController())
/** SignedInView.swift's root: FirstMacView without a Mac, else WorkspaceListView. */
@Composable fun SignedInView(account: AccountGraph, scope: SignedInScope, navigator: ShellXNavigator, startDemo: (() -> Unit)?)
/** The one place a signed-in account's environment wraps the whole NavHost (iPhone SignedInView's environment and tasks).
 *  3D: content(). Plan 3E (Task 12): `val scope = <active scope>; if (scope == null) content() else SignedInWork(scope,
 *  platform, active.push /* null in the demo */, composition.settings, openPending = { nav.navigate(WorkRoutes.pending()) {
 *  popUpTo(root); launchSingleTop = true } }) { content() }`. ShellXApp passes `content` as movable content, so the
 *  NavHost keeps its state when the wrapper appears or goes. */
@Composable fun SignedInFrame(composition: AppComposition, nav: NavHostController, root: String, content: @Composable () -> Unit)
```

  **`RootSync`** (the algorithm the tests check but do not fix):

  ```kotlin
  var applied by rememberSaveable { mutableStateOf(Routes.LAUNCH) }
  val entry by nav.currentBackStackEntryAsState()
  LaunchedEffect(root, entry) {
      if (root == applied) return@LaunchedEffect
      val atRoot = nav.previousBackStackEntry == null
      // Pairing the first Mac, or unpairing the last one, never pulls the user off the page they are on.
      if (applied in Routes.SIGNED_IN_ROOTS && root in Routes.SIGNED_IN_ROOTS && !atRoot) return@LaunchedEffect
      nav.navigate(root) { popUpTo(nav.graph.id) { inclusive = true }; launchSingleTop = true }
      applied = root
  }
  ```

  **`ShellXNavHost`'s destinations.** Each signed-in body runs inside `SignedIn(composition) { scope -> … }`. Transitions are `fadeIn(tween(300))` and `fadeOut(tween(300))` for enter, exit, popEnter and popExit; Navigation's predictive-back support runs them with the gesture.
  - `launch` → `LaunchView()`.
  - `sign_in` → `SignInView(expired = (phase as? SignedOut)?.expired == true, signIn = { real.coordinator.signInWithGoogle() }, startDemo = { appScope.launch { demo.start() } })`.
  - `first_mac`, `home` and `demo` → `SignedInView(active, scope, navigator, startDemo = if (active.isDemo) null else { appScope.launch { demo.start() } })`. All three draw by the current state, so a root waiting to be swapped is never stale.
  - `pairing` → `CancelPairingWhenLeft { scope.pairing.cancel() }`, then `PairingScreen(scope.pairing, close = navigator::back)`.
  - `composable(WorkRoutes.WORKSPACE) { e -> SignedIn(composition) { scope -> WorkPlaceholder(<the workspace's title from hub.state>, back = { nav.popBackStack() }) } }`.
  - `composable(WorkRoutes.AGENT) { e -> SignedIn(composition) { scope -> WorkPlaceholder(<SessionName of WorkRoutes.sessionRef(scope.hub.state.value, m, s)>, …) } }`.
  - `composable(WorkRoutes.PENDING, arguments = listOf(navArgument("machineId") { type = NavType.StringType; nullable = true; defaultValue = null }, navArgument("workspaceId") { … the same })) { e -> SignedIn(composition) { scope -> WorkPlaceholder(stringResource(R.string.workspaces_bell), …) } }`.
  - The three work destinations are the ones plan 3E replaces, keeping `SignedIn { scope -> … }` and `nav`.
  - `composable(Routes.SESSIONS, Routes.SESSIONS_ARGUMENTS)` → `EndedSessionsView(scope, navigator)` for `ended`, else `OtherSessionsView(scope, machineId ?: "", navigator)`.
  - `machines` → `MachinesView(scope, navigator)`.
  - `settings` → `SettingsScreen`, with:
    - `email = (phase as? SignedIn)?.email ?: ""`;
    - `account = if (active.isDemo) null else AccountActions({ coordinator.signOut() }, { coordinator.deleteAccount() })`;
    - `appearance` from `composition.appearance`;
    - `voice = scope.voice`;
    - `version = versionText(BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE.toLong())`.
  - Then `RootSync(nav, composition.root.collectAsStateWithLifecycle().value)`.
  - `navigator = remember(nav) { NavControllerNavigator(nav) { composition.active.value.scopes.current.value } }`.

  **`NavControllerNavigator`.**
  - Each `open…` navigates with `launchSingleTop = true`, which drops a double tap: `WorkRoutes.workspace/agent`, `WorkRoutes.pending()` or `pendingIn(…)`, `Routes.sessions(…)`, `Routes.MACHINES`, `Routes.SETTINGS`.
  - `openPairing()` runs `scope()?.pairing?.cancel()`, then `showPairing()`; `showPairing()` navigates to `pairing` (single top).
  - `back()` is `popBackStack()`.

  **`SignedInView`.**
  - `hasMachines = hub.state.machines.isNotEmpty()`.
  - Without a Mac: `FirstMacView(pair = navigator::openPairing, tryDemo = startDemo, openSettings = navigator::openSettings)`. Otherwise: `WorkspaceListView(scope, navigator)`.
  - Push registration and the notification prompt are 3E's `SignedInWork`.

  **`ShellXApp`.**
  - `val host = remember(composition, nav) { movableContentOf { ShellXNavHost(composition, nav) } }`.
  - A `Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background))`:
    - while `active.isDemo`, `DemoBanner(exit = { appScope.launch { demo.exit() } }, Modifier.windowInsetsPadding(WindowInsets.statusBars))`;
    - then a `Box(Modifier.weight(1f))`, with `.consumeWindowInsets(WindowInsets.statusBars)` during the demo, holding `SignedInFrame(composition, nav, root) { host() }`.
  - Links: `LaunchedEffect(inbox.hasLink, root, the active scope's sheets.isAnyOpen) { if (composition.takeLink()) navigator.showPairing() }`.

  **`MainActivity`.**
  - In `onCreate`, after 3A's `enableEdgeToEdge()`: when `savedInstanceState == null`, `deliver(intent)`.
  - `onNewIntent(intent)` calls `setIntent(intent)` and `deliver(intent)`.
  - `deliver` = `lifecycleScope.launch { LinkIntents.uri(intent)?.let { app.awaitComposition().inbox.receive(it) } }`.
  - Content:
    - before the composition, `ShellXTheme { LaunchView() }`;
    - after it, `val appearance by c.appearance.appearance.collectAsStateWithLifecycle()` and `val dark = appearance.isDark(isSystemInDarkTheme())`;
    - `DisposableEffect(dark) { enableEdgeToEdge(SystemBarStyle.auto(TRANSPARENT, TRANSPARENT) { dark }, SystemBarStyle.auto(lightScrim, darkScrim) { dark }); onDispose {} }`, with `lightScrim = Color.argb(0xe6, 0xFF, 0xFF, 0xFF)` and `darkScrim = Color.argb(0x80, 0x1b, 0x1b, 0x1b)`;
    - `ShellXAppTheme(appearance) { ShellXApp(c) }`.
  - Plan 3E adds its permission and update registrations, the notification tap and its `UpdateAlert` here (3E Task 12).

- [ ] **Step 1: Write the failing tests.**

```kotlin
// app-ui-test/ui/nav/RootSyncTest.kt: createAndroidComposeRule<ComponentActivity>(); a test NavHost with LAUNCH, SIGN_IN,
//   FIRST_MAC, HOME, DEMO, PAIRING, SETTINGS, MACHINES, each drawing Text("screen:<route>"), plus RootSync(nav, root);
//   `root` is a mutableStateOf
class RootSyncTest {
    // theRootFollowsTheAccount: root LAUNCH → SIGN_IN → HOME: "screen:home" shown; previousBackStackEntry == null
    // signingOutClearsEveryScreen: HOME; navigate SETTINGS, MACHINES; root = SIGN_IN → current route "sign_in"; previous null
    // aFirstMacWaitsUntilThePageOnTopCloses: root FIRST_MAC; navigate PAIRING; root = HOME → current still "pairing";
    //   popBackStack() → current "home"; previous null
    // losingTheLastMacAtTheRootSwitchesAtOnce: root HOME at the root; root = FIRST_MAC → current "first_mac"
    // systemBackReturnsToTheRoot: HOME → SETTINGS → rule.activity.onBackPressedDispatcher.onBackPressed() → "screen:home"
    // sessionArgumentsRoundTrip: a destination composable(Routes.SESSIONS, Routes.SESSIONS_ARGUMENTS) showing its arguments;
    //   navigate(Routes.sessions(OTHER, "m 1")) → "other|m 1"; navigate(Routes.sessions(ENDED)) → "ended|null"
}
// app-ui-test/ShellXAppSmokeTest.kt: Robolectric main thread; appScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
//   cancelled in @After; mac = FakeMac("MacBook Pro", appScope) with workspace "shellx-ios" (one zsh terminal);
//   t = mainComposition(root, macs = emptyList(), appScope, signedIn = false, pairable = listOf(mac)); every wait is waitUntil(10_000)
class ShellXAppSmokeTest {
    // signInPairAndSeeTheHome: setContent { ShellXAppTheme(SYSTEM) { ShellXApp(t.composition) } }; lifecycle.onStart() →
    //   "Continue with Google" shown → click → "Pair a Mac" shown → put mac.pairingCode() on the ClipboardManager →
    //   click "Scan QR Code" → click "Paste Pairing Code" → "Pair with MacBook Pro?" → click "Pair" →
    //   "Paired with MacBook Pro." → click "Done" → "shellx-ios" shown on the home; t.relay.calls contains "pair" once
    // theDemoShowsItsBannerAndExits: from the sign-in screen click "Try without an account" → "Demo" and "Exit" shown and
    //   the demo Mac's header ("MAC GIẢ") shown → click "Exit" → "Continue with Google" shown again; no "Exit"
}
@Config(application = ShellXApplication::class)
class MainActivityTest {
    // aShellXLinkFromAnotherAppReachesTheInbox: Robolectric.buildActivity(MainActivity::class.java,
    //   Intent(ACTION_VIEW, Uri.parse("shellx-link://pair?v=1&m=m1"))).setup(); loop up to 10 s (idle the main looper,
    //   sleep 10 ms) until app.composition.value?.inbox?.hasLink?.value == true
}
```

- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.ui.nav.RootSyncTest' --tests 'com.shellx.app.ShellXAppSmokeTest' --tests 'com.shellx.app.MainActivityTest'`.

  Expected: `Unresolved reference: RootSync`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test shellx-android/app/src/testDebug` and `git commit -m "test(shellx-android): navigation host, app root and links into the activity"`.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run (green).** Run the Step 2 command three times, then `shellx-android/scripts/dev.sh test all`.

  Expected: 6, 2 and 1 tests pass every time; `==> test all: passed`.
- [ ] **Step 6: Try it on the emulator.**

  ```bash
  shellx-android/scripts/dev.sh emulator --api 36 --headless
  A="$HOME/Library/Android/sdk/platform-tools/adb"; SHOTS="$(mktemp -d)"
  "$A" -s emulator-5582 exec-out screencap -p > "$SHOTS/api36-signin.png"
  "$A" -s emulator-5582 shell am start -W -a android.intent.action.VIEW -d 'shellx-link://pair?v=1' com.shellx.dev
  ```

  Expected: `Status: ok`, and the sign-in screen in the screenshot.
  - On the emulator, tap "Try without an account". If the emulator has no UI access, use `adb shell input tap` at the coordinates read from `uiautomator dump`.
  - Check the demo home ("Mac giả", the banner), open Settings in the demo (only the e-mail in Account), then Exit.
  - Then run `shellx-android/scripts/dev.sh emulator --api 26 --headless` and repeat the sign-in screenshot and the demo with `-s emulator-5580` (that emulator's serial, 3A) in place of `emulator-5582`. Android 8.0 must not crash.
- [ ] **Step 7: Ledger and commit.**
  - Set rows `6.1-2`, `6.1-4` and `6.1-17` to `done (3D)`.
  - In `6.1-4`'s Android cell, write `app:ui/pairing/PairingScreen.kt` (iPhone `PairingSheet`), `QrScanner.kt`, `QrFrameDecoder.kt`, `PairingPaste.kt`, `app:platform/CameraAccess.kt`, `app:ui/onboarding/FirstMacView.kt`, `app:LinkIntents.kt`, `app:MainActivity.kt`, and the `shellx-link` intent filter.
  - Run `git add shellx-android/app/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): navigation host, app root, demo banner and links into the app"`.

---

### Task 17: Verify and hand off

**Files:** none new. A fix found here first gets a failing test in the task that owns the code.

- [ ] **Step 1: Bring the branch up to date.**

  ```bash
  git -C /Users/lehuuphu/Documents/myProjects/shellx pull --ff-only origin develop
  git merge --no-edit develop
  python3 shellx-android/scripts/import-strings.py --check || python3 shellx-android/scripts/import-strings.py
  ```

  - If `pull --ff-only` fails, stop and ask the user.
  - If the importer refuses new iPhone keys, apply Task 2 Step 7's rule, add the ledger rows, and commit (`feat(shellx-android): import the iPhone strings added on develop`).
- [ ] **Step 2: Run the full verification.**

  ```bash
  shellx-android/scripts/dev.sh test all
  bash scripts/shellx/check-android-license.sh
  bash scripts/shellx/check-ios-license.sh | tail -1
  grep -rniE 'manaflow' shellx-android || echo name-ok
  grep -rn 'import android\.' shellx-android/core/src || echo core-ok
  grep -rnE 'class (PlatformServices|PushTapInbox)\b|fun (SignedInWork|UpdateAlert|NeedsYouBar)\(|LocalVoice|LocalAttachmentReader|object TestClock|fun eventually\(' shellx-android/app/src || echo names-left-for-3E
  ls shellx-android/app/src/main/res/drawable-*dpi/ic_google_g.png 2>/dev/null | wc -l
  ls shellx-android/app/src/main/assets/fonts 2>/dev/null
  git diff --stat develop -- shellx-ios shellx-link shellx-android/core Sources ios Packages cmux-tui shellx-core
  git diff develop -- shellx-android/app/src/main/res/values/google_oauth.xml | grep -c '^+.*apps.googleusercontent' || true
  python3 scripts/verify-local.py
  git status --short
  ```

  Expected:
  - `==> test all: passed`;
  - `check-android-license: ok`, then `check-ios-license: ok`;
  - `name-ok`, `core-ok` and `names-left-for-3E`;
  - `4` Google marks, or `0` while Task 9 Steps 7–9 wait for the user (report that as pending);
  - for the fonts, either nothing or exactly `GoogleSans-OFL.txt` and `GoogleSans.ttf`;
  - an empty diff for the GPL, iPhone, link and core trees;
  - the `google_oauth.xml` count is the one added line holding the placeholder (`0-shellx-placeholder…`), never a real ID;
  - `verify-local.py` ends with a line starting `PASSED:`;
  - `git status --short` prints nothing.

  If a `verify-local.py` check fails, rerun it on `develop` in the main checkout with `--only <check>`. The same failure there is pre-existing: report it and do not fix it.
- [ ] **Step 3: Smoke-test R8 on the API 36 emulator.** Run 3A Task 9 Step 3's commands: `build-release`, zipalign, debug-sign, install `com.shellx.prod`, open it, take a screenshot, uninstall.

  Expected: `release checks passed`, `Success`, `Status: ok`, and the sign-in screen in the screenshot, with the G on the Google button once Task 9 Step 8 has added it. R8 must not break Credential Manager, CameraX or navigation, and the resource shrinker must not drop the mark.
- [ ] **Step 4: Check the ledger.**
  - Rows `6.1-2`, `6.1-4`, `6.1-5`, `6.1-6`, `6.1-7`, `6.1-13`, `6.1-17`, `6.2-7`, `6.2-10` and `6.2-11` say `done (3D)`. So does `6.1-3`, once Task 9 Step 9 is done.
  - Row `6.1-14` says `3D (section), 3E (engine)`, `todo`.
  - The eight `A-` rows of Tasks 1, 2, 3, 6, 8, 9, 10 and 15 exist.
- [ ] **Step 5: Get a review.** Follow `skills/cmux-review/SKILL.md` (the default pre-merge review), through superpowers:requesting-code-review.
  - Give the fresh reviewer this plan, contracts §5, §14, §15, §16 and §20, 3E's Task 0 table and Task 12, the base `$(git merge-base develop HEAD)`, the head, and `git diff develop...HEAD`.
  - Ask for correctness first, then this plan's Global Constraints, Review Focus and the names 3E expects.
  - Fix each confirmed finding with a failing test first, rerun Step 2, and get a second review when the fixes were not trivial.
- [ ] **Step 6: USER — dogfood on the user's Android phone.** Run `shellx-android/scripts/dev.sh device`.

  Expected: `Status: ok`. Then ask the user to check these on the phone:
  1. "Try without an account": the demo home with "Mac giả", its workspaces and the "Demo · Exit" banner; Settings shows only the e-mail; Exit returns to sign-in.
  2. Settings › Appearance › Dark and Light switch at once, system bars included. With the phone in Vietnamese, the words are Vietnamese.
  3. Pairing with the camera: deny the camera prompt → "Open Settings" works; allow it in Settings and come back → the scanner shows.
  4. **Google sign-in, needing three things:**
     - row 6 (the Web client) of `docs/superpowers/ledgers/shellx-signin-rollout.md` holds an ID;
     - the relay runs plan 1A with that ID in `GOOGLE_CLIENT_IDS`;
     - the `ShellX Android (dev)` OAuth client (package `com.shellx.dev` + this Mac's debug SHA-1) exists.

     If all three hold, build the dogfood APK with the ledger's ID written into `google_oauth.xml` locally, never committed: `git checkout -- shellx-android/app/src/main/res/values/google_oauth.xml` right after the install. Then:
     - "Continue with Google" with a Google account that has a Mac signed in → "Pair a Mac";
     - scan that Mac's pairing QR → Pair → Allow on the Mac → the home shows its workspaces (tapping one opens a placeholder until 3E lands);
     - leave the app for more than 30 s and come back → the Mac reconnects;
     - Settings › Account › Delete Account… with a throwaway Google account (sign in with it first) → back at the sign-in screen, and signing in with it again makes a new, empty account.

     If any of the three is missing, record check 4 as `pending (USER: needs 1D Task 1 and the relay with 1A)`.
  5. If the phone's maker is Xiaomi, OPPO or vivo (ledger "Test devices"), note it for 3E's §7.4c test.

  Record each answer in the ledger's "Test devices" row of the phone and in the hand-off.
- [ ] **Step 7: Land (contracts §1).** This is a UI change, so merge only with the user's merge directive after Step 6. If none was given, ask, with the review summary. Then, in the main checkout on `develop`:

  ```bash
  git -C /Users/lehuuphu/Documents/myProjects/shellx status --short | grep -v '^??' || true    # expect no output
  git -C /Users/lehuuphu/Documents/myProjects/shellx merge --no-ff --no-edit feat/shellx-android-3d-ui-shell
  (cd /Users/lehuuphu/Documents/myProjects/shellx && shellx-android/scripts/dev.sh test app)
  git -C /Users/lehuuphu/Documents/myProjects/shellx push origin develop
  ```

  Expected: no tracked changes, a merge commit, `==> test app: passed`, and the push succeeds. Never merge to `main`, deploy, upload or publish. Finish the worktree with superpowers:finishing-a-development-branch.
- [ ] **Step 8: Hand off.** Report to the user, in Vietnamese:
  - what landed, with the merge commit;
  - the test counts;
  - the allowlist lines added;
  - the screenshots looked at (Tasks 9–16);
  - the phone results, or what is still pending;
  - the localisation audit: every name added to `strings_android.xml` and every 1C key imported or listed as iPhone-only, each with its en and vi text (`git diff develop -- shellx-android/app/src/main/res shellx-android/scripts/strings-ios-only.txt`);
  - Google's branding: the mark and the font are in, the font gate failed (and why), or the USER step is still pending;
  - what is the user's: the 1D items for Google sign-in, and the phone checks if pending;
  - this plan's "Contract additions" and "Spec notes", for 3E's executor too.

---

## Spec notes

These are places where the spec, the brief or the contracts differ from the code or from the iPhone. The code is the fact, and this plan follows the spec's intent.

1. **Pairing is a route, not a sheet.** S3 §7.2 turns iPhone sheets into bottom sheets, but contracts §5 names a `pairing` route. A camera preview inside a draggable sheet fights the drag, so pairing is a full-screen page. Back and Close cancel the attempt, as the iPhone's dismissal does (`PairingRouteViewModel`, so rotation does not). Ledger `A-` row of Task 10.
2. **Route arguments.**
   - The iPhone's `pendingIn(machineID, workspaceId)` becomes the optional query arguments of `pending?machineId=…&workspaceId=…` (contracts §20).
   - `otherSessions(machineID)` and `ended` become `sessions/other?machineId=…` and `sessions/ended`.
   - The contract names stay the route patterns' prefixes.
3. **`first_mac` and `home` are one screen.** The iPhone's root view switches its content when the Mac count crosses zero, and keeps the pushed screens. Android keeps two routes, as contracts §5 names them. Both draw `SignedInView` by state, and the root is renamed only when it is on top. So pairing the first Mac keeps the "Paired" step on screen, as on the iPhone.
4. **The demo does not write the clipboard.** 3C's wiring summary says to put the second demo Mac's code on the clipboard. 1C's in-app `DemoSession` passes `pasteboard: nil`, and Android 13 and later show a system "copied" message for a write the user did not ask for. `DemoEnvironment.secondPairingCode()` stays for tests.
5. **`NeedsYouBar` belongs to the agent screen.** Ledger row 6.1-5 lists it under the home, but the iPhone shows it only over a conversation (`AgentScreen.swift:146`). 3E creates it (its Task 5), and the iPhone file moves to row 6.1-10.
6. **Google's button** (contracts §11; https://developers.google.com/identity/branding-guidelines, read on 2026-11-07).
   - **Font.** The page names one font for every platform: "The button font is Google Sans Medium", 14/20 in each theme's row. It never names Roboto. Android bundles Google Sans behind contracts §11's licence gate, with its OFL 1.1 text saved next to it. S3 §5's licence list names libraries only. If the gate fails, the button uses the platform font (Roboto) Medium 14/20.
   - **Padding.** The page's only Android values are the padding, in its row "Android & Web": 12 px before the logo, 10 px after it, 12 px after the text. Android follows that row. The iPhone follows the iOS row, 16 / 12 / 16.
   - **Theme.** The button uses the Light theme in both appearances, as plan 1C does; the page also offers Dark and Neutral.
   - **The G.** The bundle holds only whole buttons (plan 1C, checked 2026-11-07), and its SVG "G" is a `foreignObject`, which a VectorDrawable cannot hold. So the G is the centre 20 dp of the Light, no-text, Square Android + Web PNGs, unchanged. 20 dp is the size plan 1C measured in the bundle's iOS icons; Task 9 Step 9's comparison with Google's own Android + Web button confirms it for Android.
   - **Height.** The page sets no height. The button is at least 48 dp high, by the touch-target rule.
   - **Before the USER step.** Until the files are in, the button shows its text only, as on the iPhone.
7. **Account deletion.** S1 §6.8's "hộp xác nhận" is a dialog card (`DeleteAccountCard` in a `BasicAlertDialog`). The card has the steps of 1C's `DeleteAccountSheet`, minus `switchFirst`: an Android session is always Google.
8. **Voice section.** Contracts §15 and §20 put the Voice section in 3D's `SettingsScreen`, while ledger row 6.1-14 says 3E. 3D builds the section; it shows once 3E's `makeVoice` builds a `VoiceService` per hub. This matches the iPhone, where a nil `VoiceService` shows no mic.
9. **Launch at the first start in front.** The iPhone launches the account when its window first appears. Android does it at the first `ProcessLifecycleOwner` ON_START, and watches the network only while started. A process that FCM starts in the background must not connect (S3 §4).
10. **Screenshots of dialogs.** 3A's `ShellXSnapshots.capture` draws the composable's own window, so dialog and bottom-sheet windows are not in the PNGs. Compose UI tests check every dialog's words and buttons. The deletion card and the rename sheet's content are rendered directly. The iPhone's per-alert renders have no Android image.
11. **Touch targets** are 48 dp (Material), not 44 pt.
12. **Appearance.** The app's windows follow Settings › Appearance, and so do the system bars, through `enableEdgeToEdge`. Windows the system owns (Google's account sheet, the permission prompt) follow the phone's theme, and so does the window background before Compose draws.
13. **No "Switch to Google".** The iPhone's banner and Account row exist for password sessions only, which Android never has (contracts §5).
14. **TalkBack.** `announceForAccessibility` is deprecated, so the iPhone's VoiceOver announcements become polite live regions on the same texts.
15. **The Flutter data clean-up** (S3 §3) had no owner in the contracts. 3D does it once at first launch, as part of building the environment.
16. **The Mac's "last seen" time** uses the phone's 12/24-hour setting (`DateFormat.getTimeFormat`); the iPhone uses the app language's short time.
17. **The relay override in debug** (3C's A-6) needs cleartext to loopback, which a network security config allows in debug builds only. Release builds keep Android's default of no cleartext, and `dev.sh build-release` checks it.
18. **Push and the update prompt are 3E's.** The iPhone's `SignedInView` calls `push.signedIn()`, asks for notifications and opens tapped alerts; its `RootView` shows the update alert. On Android these sit in 3E's `SignedInWork`, `PushTapInbox` and `UpdateAlert` (3E Task 12). So this plan's `SignedInView` and `MainActivity` handle neither, and until 3E lands no push token is registered. With 3D's stubs there is none anyway.
19. **The shell's environment class** is `AppEnvironment`, because contracts §20 reserves `PlatformServices` for 3E's platform pieces.

## Contract additions

These are cross-plan names that 3E, 3G and 3H rely on. They are listed for the contracts owner; the executor does not edit the contracts file.

1. **Composition** (§5, §15, §20):
   - `AppComposition(environment: AppEnvironment, appScope, speechEngine: SpeechEngine = NoSpeechEngine, voicePermissions: VoicePermissionChecking = NoVoicePermissions, pushRegistrar: PushRegistrar = NoPushRegistrar, updateChecker: UpdateChecker? = null, attachmentReader: AttachmentReader = NoAttachmentReader, makeVoice: ((MachineHub, LatencyLog, KeyValueStore, Clock) -> VoiceService)? = null, relays, demoEnvironment)`. 3E passes its five pieces by type and `makeVoice = platform::makeVoice`.
   - Its members: `real` and `demo` `AccountGraph`s, `active`, `root`, `inbox`, `appearance`, `lifecycle`, `takeLink()` and `makeScope(…, voice)`; and, by the names 3E reads, `vault`, `latency`, `settings`, `clock`, `push`, `updatePrompt`, `appScope`.
   - The update prompt exists only in release builds with a checker.
   - `ShellXApplication.composition: StateFlow<AppComposition?>` and `awaitComposition()`. The composition is built after the settings load, and 3E edits the `AppComposition(…)` call there.
   - "3D's ON_START hook" is `AppLifecycle.onStart()`.
2. **`SignedInScope`** (3E Task 0): `hub`, `decisions`, `pairing`, `history`, `chatCopies`, `voice`, `sheets`, `listNotice`, `endedDismissals`, `goneRemovals`, `clock`, `latency`, `agentThread(ref)`, `homeShown()`, `workspacesListed()`.
   - `start()` runs the chat-copy sweeper and `decisions.sync(hub.pendingItems)` in `hub.scope`, so 3E need not add the sync.
   - A test-built scope (3E's `WorkRig`) uses `AppComposition.makeScope(…)`, then `start()`.
3. **Routes** (§5, §20):
   - `WorkRoutes`, in exactly 3E Task 12's shape (3E keeps the file).
   - `Routes` for the shell's own routes, with `SESSIONS = "sessions/{kind}?machineId={machineId}"`, `SESSIONS_ARGUMENTS`, and `SessionListKind` `ended` and `other`.
   - `ShellXNavigator` for 3D's screens.
   - `ShellXNavHost(composition, nav)`. Its three work destinations are `composable(WorkRoutes.X, …) { e -> SignedIn(composition) { scope -> WorkPlaceholder(…) } }`; 3E replaces each `WorkPlaceholder` with its view.
   - `RootSync(nav, root)`.
4. **The signed-in wrapper:** `SignedInFrame(composition, nav, root, content)` is where 3E's `SignedInWork` goes. It passes `active.push`, which is null in the demo, and opens `pending` over `root`. `content` is movable (`movableContentOf`), so the NavHost survives the wrapper.
5. **Slots plan 3E fills:**
   - `NotificationsSettingsSection()`, laid out with `SettingsSection(title, footer) { … }`;
   - the three work destinations;
   - `SignedInFrame`;
   - `MainActivity.onCreate`, `onNewIntent` and the root content, for 3E's permissions, Play updates, tap and `UpdateAlert`.
6. **Shared UI 3D creates in 3E's shapes** (3E's "create if missing" finds them):
   - in the theme: `StatusTone` with `StatusTone.color()`, `AgentStateStyle(text, shortText, tone)` with `of(row, res)` and `elapsedText(elapsed, locale)`, `MachineStateStyle(text, tone)`, `StatusDot(color, modifier)` (in `MachineStateStyle.kt`), `AppLanguage`, `AppAppearance` and `ShellXAppTheme`;
   - in `com.shellx.app.ui.components`:
     - the buttons `PrimaryButton` (`PrimaryButtonStyle.kt`) and `SecondaryButton` (`SecondaryButtonStyle.kt`);
     - the waiting border: `Modifier.waitingBorder(isActive, cornerRadius)` and `WaitingBorder.isActive(state, online)`;
     - the row and dialog helpers: `ActionRow`, `RowAction`, `RowActions`, `ConfirmDialog`, `MessageDialog`, `SectionTitle`;
     - the rest: `isLargeText()` (fontScale ≥ 1.3), `rememberNowMs`, `HomeTicks` and the two `Saver`s;
   - in `com.shellx.app.ui.workspaces`: `ListNotice` (`show(text)`, `Notice`, `DURATION` 4 s), `NoticeCapsule(text)`, `WorkspaceFeedback`, `WorkspaceAlert`, `WorkspaceCommand`, `WorkspaceAlertDialog(alert, dismiss)`, `AgentCloseConfirmation(name, close, dismiss)` and `WorkspaceRenameSheet(current, save, cancel)`;
   - `WorkspaceListActions.canClose(session, hub)`, `closeAgent(ref, hub, alert): Deferred<WorkspaceFeedback>?`, `canCloseTab(machineId, hub)` and `closeTab(machineId, workspaceId, terminalId, hub, alert): Deferred<WorkspaceFeedback>?`, which every Close Agent and Close Tab goes through, plus 3D's `make(…)`;
   - `FocusRowView` and `FocusKind`.
7. **Names 3E creates, which 3D never defines:** `PlatformServices`, `SignedInWork`, `LocalVoice` / `VoiceEnvironment`, `LocalAttachmentReader`, `PushHost`, `PushTapInbox` (the tap action `com.shellx.app.action.OPEN_PENDING`), `UpdateAlert`, `NeedsYouBar`, and the test kit names `TestClock`, `eventually`, `WorkRig`, `FakeSpeechEngine`, `FakeVoicePermissions`, `FakeResultRegistry`, `TestOwner`, `ManifestTest`.
8. **Platform:**
   - Keystore alias `shellx.secrets.v1`; secrets in `noBackupFilesDir/secrets/<account>.bin`; settings in `noBackupFilesDir/settings.preferences_pb`; history in `noBackupFilesDir/ShellX`, and the demo's in `noBackupFilesDir/ShellXDemo`;
   - the settings keys `shellx.appearance` and `shellx.legacyFlutterCleaned`;
   - the Gradle property `shellxApiBase` → `BuildConfig.SHELLX_API_BASE` (debug only);
   - the debug loopback cleartext config;
   - `ActivityTracker.current()`;
   - `LinkIntents.uri(intent)`.
9. **The Web client placeholder** (§16): exactly `0-shellx-placeholder.apps.googleusercontent.com`. `GoogleWebClient.isReal` refuses it, so a build that still holds it signs in with `ProviderUnavailable`. 3H's release script greps for this value.
10. **Google's button on Android** (§11):
    - the mark is drawable `ic_google_g` (`GoogleBranding.MARK`): PNGs in `drawable-mdpi` to `drawable-xxxhdpi`, the centre 20 dp of the Light, no-text, Square Android + Web icons of Google's bundle;
    - Google Sans is `assets/fonts/GoogleSans.ttf`, with `GoogleSans-OFL.txt` next to it;
    - until they are in, the button shows its text only, as plan 1C's does.
    - **For 3H:** like 1C's `ios.sh`, the release script should refuse a release bundle whose resources lack `drawable/ic_google_g` (looked up by name, so the resource shrinker can drop it). Assets are never shrunk, so the font needs no bundle check.
11. **`:app` test support** (`app/src/test/kotlin/com/shellx/app/testing/`), free of 3E's names: `ManualClock`, `TestIdentity`, `TestNetworkMonitor`, `ScriptedRelay`, `testEnvironment`, `TestComposition`, `testComposition`, `mainComposition`, `RecordingNavigator`, `waitFor`, `HomeFixtures`.
    - In `com.shellx.app.screenshots`, 3D creates `assertRenders(name) { … }` and `LargeText { … }` with exactly 3E Task 1's API (3E keeps `RenderAssertions.kt`), and `chroma` in `PixelChecks.kt`.
    - Robolectric builds `android.app.Application` by default (`robolectric.properties`).

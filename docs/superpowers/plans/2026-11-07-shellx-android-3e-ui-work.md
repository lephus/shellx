# ShellX Android 3E — UI Work Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Android screens where the work happens, translated from the iPhone app:
- the workspace screen (chips, swipeable panes, `⋮` menu, long-press Close Tab, notices when the Mac closes things);
- the agent chat;
- the Needs-you list with its question, plan and full-text sheets;
- the composer with hold-to-talk and photos/files.

It also builds the platform pieces behind them:
- the `SpeechRecognizer` engine;
- FCM push notifications;
- the Play in-app update prompt;
- Settings › Notifications.

**Architecture:** Every screen mirrors its iPhone file (`shellx-ios/ShellX/UI/…`) in `app:ui/<folder>/<Name>.kt`, in two layers:
- a composable fed by plain values, which render tests can show in any state;
- a hub-fed `…View`, which keeps plan 3C's model in a ViewModel holder and runs it while the screen is STARTED.

The platform pieces implement 3C's interfaces (`SpeechEngine`, `VoicePermissionChecking`, `PushRegistrar`, `UpdateChecker`, `AttachmentReader`) behind small ports, so Robolectric tests drive them without system services. Three things tie 3E to plan 3D's shell, and Task 12 plugs them in (`AppComposition`, `ShellXApplication`, `MainActivity`, `ShellXNavHost`):
- one class, `PlatformServices`, holds the platform pieces;
- one composable, `SignedInWork`, hands them to the signed-in screens;
- one object, `WorkRoutes`, names the routes.

**Tech Stack:** Kotlin, Jetpack Compose with Material 3 (3A's Compose BOM), Navigation Compose and Lifecycle (3D), `androidx.activity` result contracts (Photo Picker, `OpenMultipleDocuments`, runtime permissions), `android.speech.SpeechRecognizer`, Firebase Cloud Messaging (Firebase BOM), Play In-App Updates (`com.google.android.play:app-update`), JUnit 4 with Robolectric, Compose UI tests, and Roborazzi through 3A's `ShellXSnapshots`.

**Spec:** `docs/superpowers/specs/2026-11-07-shellx-android-app-design.md` (S3):
- §6.1, the rows for the workspace screen, agent chat, Needs you, composer, update prompt and notifications;
- §6.2, every timing and limit these screens use;
- §7.2;
- §7.3, the rows for `SpeechRecognizer`, the audio level, Photo Picker / `OpenMultipleDocuments`, haptics and Play In-App Updates;
- §7.4 (client side) and §7.4c.

Cross-plan names come from `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` §1, §5, §8, §12, §14 and §15. The other plans:
- 3A (`…-3a-scaffold.md`): build, strings, `ShellXSnapshots`, ledger;
- 3C (`…-3c-core.md`): every core name used here, from its Interfaces blocks;
- 3F (`…-3f-relay-fcm.md`): what the relay sends;
- 3D (`…-3d-ui-shell.md`): the shell. It was written in parallel with this plan; Task 0 maps its real names.

## Global Constraints

- **Branch and landing (contracts §1).** Branch `feat/shellx-android-3e-ui-work`, from `develop`, after 3A–3D are merged.
  - After the final review and the user's OK in Task 13, merge into `develop` and push `develop`.
  - Never merge to `main`. Never deploy, upload or publish.
- **Scope.** Change only:
  - `shellx-android/app/`;
  - `shellx-android/gradle/libs.versions.toml`;
  - `scripts/shellx/android-license-allowlist.txt`;
  - `shellx-android/scripts/strings-ios-only.txt` (only by 3A Task 11 Step 1's rule, in Task 13 Step 1);
  - `docs/superpowers/ledgers/shellx-android-parity.md`.

  Never edit `shellx-android/core`, `shellx-link/`, `shellx-ios/` or the plan files. If a 3C name or signature differs from what this plan says, use the real one and list it in the report. If a 3C behaviour is wrong, stop and report it: 3C owns it.
- **Mirror rule (3A, contracts §5).**
  - `shellx-ios/ShellX/<Folders>/<Name>.swift` becomes `shellx-android/app/src/main/kotlin/com/shellx/app/<folders in lower case>/<Name>.kt`. A type keeps its iPhone name, and contract names win.
  - A Swift view's static helpers live in an `object` with the view's name, beside the `@Composable fun` of the same name. For example, `object PendingCardView { fun kindText(…) }` sits next to `@Composable fun PendingCardView(…)`. Kotlin allows a function and an object to share a name.
- **Licence (S3 §5).**
  - Translate only from `shellx-ios/` and the plans. Never copy from `Sources/`, `Packages/`, `ios/`, `cmux-tui/` or `shellx-core/`.
  - Never write the upstream company name.
  - New artefacts are only:
    - Firebase Messaging, through the Firebase BOM;
    - `com.google.android.play:app-update`;
    - `androidx.compose.material:material-icons-extended`;
    - `androidx.compose.ui:ui-test-junit4` (tests only);
    - the Lifecycle and Navigation artefacts that 3D has not already added.
  - Each new artefact goes through 3A's allowlist procedure (3A Task 3 Step 6). No Markdown, image-loading or permission library.
  - None of these may appear on `releaseRuntimeClasspath` in `app/gradle.lockfile`, because plan 3H's release check refuses them:
    - `com.google.firebase:firebase-analytics`, `firebase-crashlytics`, `firebase-perf`, `firebase-inappmessaging`;
    - `com.google.android.gms:play-services-measurement*`, `play-services-ads`, `play-services-analytics`, `play-services-appset`.

    When one comes in, exclude it in `app/build.gradle.kts`, and say so in the report.
  - The release build's permissions are exactly `POST_NOTIFICATIONS` and `RECORD_AUDIO` beyond what 3A–3D request (plan 3H keeps the list).
- **Strings.**
  - Every visible string comes from the generated `strings.xml` (iOS key → name by 3A's rule, for example `agent.removeFromPhone` → `agent_remove_from_phone`) or from `res/values*/strings_android.xml`. Never hand-edit the generated files.
  - An Android-only string or an override goes into both `values/strings_android.xml` and `values-vi/strings_android.xml`. After adding an override, run `python3 shellx-android/scripts/import-strings.py`, and commit the regenerated files with it.
  - Helpers that build text take `res: Resources`. Composables use `stringResource`.
- **Look (S3 §7.2).**
  - Colours come from `ShellXTheme.colors` and the Material 3 scheme (3A Task 7):
    - text buttons and links use `accentText`;
    - a destructive action uses `statusError`;
    - running is `statusRunning` (yellow);
    - a sheet or card sits on `surfaceContainer*`.
  - No gradients, except 3D's waiting border.
  - Icons are Material icons from `material-icons-extended`.
- **Android interaction (S3 §7.2).**
  - A `TopAppBar` with a back arrow, and system Back (predictive back comes with Navigation).
  - `ModalBottomSheet(skipPartiallyExpanded = true)` where the iPhone uses a sheet. `AlertDialog` for every confirmation.
  - A long press opens a `DropdownMenu`. `⋮` (`Icons.Filled.MoreVert`) is the overflow menu.
  - Insets are handled edge to edge. Touch targets are at least 48 dp.
- **Threading (3C).**
  - Models are main-confined. Screens collect `state` (and `hub.state`, `center.state`) with `collectAsStateWithLifecycle()`, then read the getters.
  - A model's `run()` runs only while the lifecycle is STARTED (`repeatOnLifecycle`).
  - Work that must outlive a composable runs in `scope.hub.scope`, never only in `rememberCoroutineScope()`. That is decisions, retries, sends, stops, closes, saves and mic stops.
  - Mic actions run in `LocalVoice.current.scope`.
- **Privacy.** Never log message text, transcripts, attachment names or bytes, workspace titles, tokens or ids. Log lines go through `CoreLog.log` with event names and counts only.
- **Constants.** Copy these exactly.

  | What | Value |
  | --- | --- |
  | Notice over the composer and over the panes (ledger 6.2-18) | 4 s (`AgentView.NOTICE_DURATION`) |
  | "Nothing needs you" before going back (6.2-19) | 700 ms (`PendingListView.LEAVE_DELAY`) |
  | Final voice result (6.2-20) | `SpeechTimeouts.STANDARD_FINAL_RESULT` (1 500 ms) and `SpeechTimeouts.ON_DEVICE_FINALIZE` (2 s), from 3C |
  | Recognizer ready | 3 s (`SpeechRecognizerEngine.READY_TIMEOUT`) |
  | Recognition support check | 2 s (`VoiceCapabilityProbe.SUPPORT_TIMEOUT`) |
  | Audio level | `onRmsChanged` dB mapped linearly from −2 dB (0) to 10 dB (1), clamped |
  | Card preview | 3 lines, 600 characters (graphemes) |
  | Live dictation shown | the last 160 characters |
  | Attachment tile, thumbnail | 56 dp; long side 200 px; cache of 32 |
  | File read chunk | 65 536 bytes |
  | Mic diameter | 58 dp default (the question sheet); the composer's and the plan sheet's are 48 dp |
  | Cancel / keyboard drag | 3C's `VoiceInputModel.CANCEL_DISTANCE` (80 dp) and `KEYBOARD_DISTANCE` (60 dp); pointer deltas go in dp |
  | Large-text layout (iPhone accessibility sizes) | `LocalDensity.current.fontScale >= 1.3f` stacks buttons |
  | Notification channel | id `needs_you`, importance HIGH; child id 1, summary id 2; tag `request_id`, group `machine_id` |
  | Tap action | `com.shellx.app.action.OPEN_PENDING` |
  | Paired-Mac check before posting | at most 2 s; on timeout or error the alert posts |
  | Settings key (Android only) | `shellx.notifications.asked` |
- **Tests.**
  - JUnit 4 with `org.junit.Assert`. Every `:app` test class, plain logic included, runs with the Robolectric runner (`@RunWith(AndroidJUnit4::class)`), because `android.jar`'s stubs throw on the JVM.
  - Compose UI tests and render tests live in `app/src/testDebug/kotlin/com/shellx/app/…`, because `createComposeRule` needs 3A's debug-only `ui-test-manifest`. Every other test lives in `app/src/test/kotlin/com/shellx/app/…` and runs in both variants.
  - Render tests sit in package `com.shellx.app.screenshots` and use `assertRenders` (Task 1). Each render name gets its own `@Test`. No golden images are committed (3A).
  - Every `…RenderTest` class carries the annotations of 3A's `LaunchViewRenderTest`: `@RunWith(AndroidJUnit4::class)`, `@GraphicsMode(GraphicsMode.Mode.NATIVE)` and `@Config(qualifiers = ShellXSnapshots.DEVICE_QUALIFIERS)`. Without them the captures are not 1179 px wide and `assertRenders` fails.
  - No real sleeps, except `eventually` polling (Task 1). Time-based UI is checked with `composeRule.mainClock`; core timing with `runTest` virtual time.
- **Commits (3A).**
  - When a task has logic, commit the failing tests (`test(shellx-android): …`) before the implementation (`feat(shellx-android): …`).
  - Always use an explicit `git add <paths>`.
  - Ledger rows change in the same commit as the code they describe.
- **Never** touch the user's running ShellX or cmux apps. Never install `com.shellx.prod` on the phone.

## Review Focus

These are inputs the spec implies but no ported iPhone test exercises, most likely first. Each has a test in its owning task.

1. **A hold on the mic that ends without a lift.** The pager or a list claims the touch, the permission dialog opens mid-press, or the screen leaves (Back, the pane swiped away). The words are dropped, nothing is sent, and the microphone is given back. Tests:
   - Task 4 `aHoldTakenAwayCancelsAndSendsNothing`;
   - Task 4 `leavingWhileHoldingGivesTheMicrophoneBack`.
2. **A picked file of unknown size that streams past 10 MiB** (a cloud document, a pipe). It is refused after reading at most 10 MiB plus one chunk, and is never loaded whole. Test: Task 4 `anUnknownSizeStreamStopsJustPastTheLimit`.
3. **Android recreates the screen while the user types** (rotation, dark mode, font size, split screen). The "Other…" answer and its page, the plan feedback, and the composer's draft with its attachments survive. Tests:
   - Task 6 `typedAnswersSurviveRecreation`;
   - Task 6 `feedbackSurvivesRecreation`;
   - Task 7 `theDraftLivesInTheScreenHolder`.
4. **Pushes that must not show, or must not break anything:**
   - a push for a Mac this phone no longer has (signed out or unpaired while offline, so the relay still holds the token);
   - a push while the app is in front;
   - a `resolved` for an alert that was never shown;
   - a phone without notification permission.

   Nothing is posted and nothing crashes, and a Mac's group summary leaves with its last alert. Tests: Task 9 `PushNotifierTest`.
5. **Android's recognizer ends a segment when the user pauses but still holds the mic.** Listening goes on, and the words before the pause appear once, in Vietnamese. Silence after the words ends the dictation, and the words are kept. Tests:
   - Task 3 `aPauseWhileHeldKeepsListeningAndTheWords`;
   - Task 3 `silenceAfterWordsEndsTheRunKeepingThem`.

## Conventions

- **Path prefixes.**
  - `app/` = `shellx-android/app/src/main/kotlin/com/shellx/app/`
  - `app-test/` = `shellx-android/app/src/test/kotlin/com/shellx/app/`
  - `app-ui-test/` = `shellx-android/app/src/testDebug/kotlin/com/shellx/app/`
  - `res/` = `shellx-android/app/src/main/res/`
  - `ios/` = `shellx-ios/ShellX/` (this prefix never means the repository's root `ios/` folder, which is GPL and which the Licence rule forbids)
  - `ios-tests/` = `shellx-ios/ShellXTests/`
- **Read the Swift first.** The Swift file a task names is the reference for every body this plan does not write out: layout, order, padding, words and accessibility. Keep its behaviour. Port no iPhone feature this plan does not name.
- **Gradle.** Paste these one-line definitions at the start of every shell call that uses them (shell state does not carry over):

  ```bash
  gw() { R="$(git rev-parse --show-toplevel)"; JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" "$R/shellx-android/gradlew" -p "$R/shellx-android" --console=plain "$@"; }
  counts() { R="$(git rev-parse --show-toplevel)"; for c in "$@"; do f="$R/shellx-android/app/build/test-results/testDebugUnitTest/TEST-com.shellx.app.$c.xml"; echo "$c $(grep -o 'tests="[0-9]*" skipped="[0-9]*" failures="[0-9]*" errors="[0-9]*"' "$f" | head -1)"; done; }
  ```

  - A **red** run ends with `BUILD FAILED`, plus the compile error (`Unresolved reference` naming the step's symbol) or the failing test the step names.
  - A **green** run ends with `BUILD SUCCESSFUL` and has no `FAILED` line.
  - "N tests" means `counts <package.Class>` prints `tests="N" skipped="0" failures="0" errors="0"`.
  - Every green step ends with `shellx-android/scripts/dev.sh test app`. It must print `==> test app: passed`, which covers both variants and the tests of earlier tasks and of 3D.
- **Porting an iPhone test.** One Kotlin `@Test` per `func test…`, named without `test` and with a lower-case first letter. Keep every literal and assertion, and translate with this table:

  | Swift | Kotlin |
  | --- | --- |
  | `XCTAssertEqual(actual, expected)` | `assertEquals(expected, actual)` |
  | `String(localized: "a.bC")` | `res.getString(R.string.a_b_c)` (with arguments: `getString(id, …)`) |
  | `try assertRenders(view, name: "x")` | `assertRenders("x") { … }` (Task 1) |
  | `NavigationStack { X }` | `X`: the screen draws its own top bar |
  | `.constant(v)` binding | the value, and `{}` for its change callback |
  | `.environment(\.dynamicTypeSize, .accessibility3)` | `LargeText { … }` (Task 1): font scale 2 |
  | `.environment(service)` | `CompositionLocalProvider(LocalVoice provides env)` (Task 3) |
  | `Date(timeIntervalSince1970: 1_700_000_000)` | `nowMs = 1_700_000_000_000` |
  | `machineID:` | `machineId =` (3C) |
  | `await eventually { c }` | `eventually { c }` (Task 1) |
  | `size(of: view).height` | `onNodeWithTag(tag).getUnclippedBoundsInRoot().height` (in dp) |
  | `.permission`, `.working`, `.prose`, … | 3B's constants: `PendingKind.PERMISSION`, `AgentState.WORKING`, `ChatEntryKind.PROSE`, … |
- **3D's names.** Task 0 Step 5 maps each name of the "From 3D" table to 3D's real code.
  - When a name differs, use 3D's name wherever this plan says the other, and never rename 3D's code.
  - An item marked *create if missing* is created by the task named, with the Interfaces given there.
  - An item marked *must exist* that is missing stops the plan.
- **Parity ledger** (`docs/superpowers/ledgers/shellx-android-parity.md`).
  - A row whose Plan cell is `3E` gets `done (3E)`, or `differs (3E): <what and why>`, in the commit that finishes it.
  - Shared rows follow 3C's rule: the last plan sets the row.
  - New Android-only rows go at the end of "Android-only differences", with the next free `A-` numbers in the order this plan lists them. They are called `A-e1`…`A-e6` below.

## File map

| Area | Main files | Task |
| --- | --- | --- |
| Build, manifest, test kit | `libs.versions.toml`, `app/build.gradle.kts`, `AndroidManifest.xml`; `app-test/testing/*`, `app-ui-test/screenshots/RenderAssertions.kt` | 1 |
| Plan Markdown | `app/ui/pending/PlanMarkdownText.kt` | 2 |
| Voice engine | `app/voice/{RecognizerPort,SpeechRecognizerEngine,AudioLevelMeter,VoiceCapabilityProbe,SystemVoicePermissions,SystemVoice,VoiceEnvironment}.kt`, `app/platform/PermissionRequester.kt` | 3 |
| Composer | `app/ui/composer/{MicButton,VoiceStatusView,ComposerBar,AttachMenu,AttachmentStrip,AttachmentPreparer}.kt`, `app/ui/components/{PrimaryButtonStyle,SecondaryButtonStyle}.kt` (if missing) | 4 |
| Needs you | `app/ui/pending/{PendingCardView,PendingCardStatusLine,CommandPreview,CutNotice,ChoiceRow,ByteCounter,FullTextSheet,PendingCardsSection,PendingRoute,PendingSheetState,PendingSheetHost,PendingListView}.kt`, `app/ui/home/NeedsYouBar.kt` (if missing) | 5 |
| Sheets | `app/ui/pending/{QuestionAnswerSheet,PlanReviewSheet}.kt` | 6 |
| Agent | `app/ui/agent/{AgentScreen,AgentView,AgentHeader,ChatEntryRow,NewMessagesButton,StopButton}.kt` (+ the 3D pieces if missing) | 7 |
| Workspace | `app/ui/workspaces/{WorkspaceScreen,WorkspaceView,PaneChips,ShellPanePlaceholder}.kt` (+ the 3D pieces if missing) | 8 |
| Push | `app/platform/{PushNotifier,ShellXMessagingService,FcmPushRegistrar,PlayTasks,PushTapInbox,NotificationPermission}.kt`, `res/drawable/ic_stat_shellx.xml` | 9 |
| Update | `app/platform/PlayUpdateChecker.kt`, `app/ui/update/UpdateAlert.kt` | 10 |
| Settings › Notifications | `app/ui/settings/{NotificationsSettingsSection,OemGuide}.kt` | 11 |
| Wiring | `app/{PlatformServices}.kt`, `app/ui/SignedInWork.kt`, `app/ui/nav/WorkRoutes.kt`; edits to 3D's `AppComposition.kt`, `ShellXApplication.kt`, `MainActivity.kt`, `ui/nav/ShellXNavHost.kt` | 12 |

---

### Task 0: Set up the worktree, check what this plan builds on, map 3D's names

**Files:** none.

- [ ] **Step 1: Create the worktree.** Use superpowers:using-git-worktrees, with branch `feat/shellx-android-3e-ui-work` from `develop`. Without a native tool, run `git worktree add .worktrees/android-3e-ui-work -b feat/shellx-android-3e-ui-work develop`. Work only there from now on. Plan files may be untracked in the main checkout: read them at `/Users/lehuuphu/Documents/myProjects/shellx/docs/superpowers/plans/` and never commit them here.
- [ ] **Step 2: Check that 3A–3D are merged.**

  ```bash
  test -x shellx-android/gradlew \
    && test -f shellx-android/app/src/testDebug/kotlin/com/shellx/app/screenshots/ShellXSnapshots.kt \
    && grep -rq 'class WorkspaceScreenModel' shellx-android/core/src/main \
    && grep -rq 'class VoiceService' shellx-android/core/src/main \
    && grep -rq 'class AppComposition' shellx-android/app/src/main \
    && grep -rq 'fun ShellXNavHost' shellx-android/app/src/main \
    && grep -rq 'fun NotificationsSettingsSection' shellx-android/app/src/main && echo ready
  ```

  Expected: `ready`. Otherwise stop and report "plans 3A–3D must be merged into develop first". Change nothing.
- [ ] **Step 3: Run the baseline.** Run `shellx-android/scripts/dev.sh test all`.

  Expected: `==> test all: passed`. If it fails before you change anything, stop and report.
- [ ] **Step 4: Read what this plan builds on.**
  - 3C's core packages `agent`, `pending`, `workspaces`, `voice`, `push`, `update`, `composer`, `home` (`ComposerValidation`, `SessionName`, `AgentStatusRow`), `link` (`MachineHub`, `HubState`), `text`, `demo` (`FakeMac`, `FakeMacFleet`, `DemoRelay`, `DemoSecretStore`), and `platform` (`Clock`, `KeyValueStore`, `MemoryKeyValueStore`), `account` (`AccountVault`), `storage` (`ConversationStore`), `diagnostics` (`LatencyLog`) and `pairing` (`SheetPresence`).
  - 3D's `app/` files: `AppComposition.kt`, `ShellXApplication.kt`, `MainActivity.kt`, `ui/nav/ShellXNavHost.kt`, the per-sign-in scope, `ui/settings/`, `ui/theme/`, `ui/components/`, `ui/workspaces/` and `ui/home/`.
  - 3A's `ShellXSnapshots.kt` and `strings_android.xml`.
- [ ] **Step 5: Map 3D's names.** For each row, find 3D's real name and signature (`grep -rn`). Keep the map for your final report; do not commit it.

  | Name this plan uses (iPhone mirror) | Expected | If missing |
  | --- | --- | --- |
  | `com.shellx.app.SignedInScope` | `hub`, `decisions`, `pairing`, `history`, `voice: VoiceService?`, `sheets: SheetPresence`, `listNotice: ListNotice`, `endedDismissals`, `goneRemovals`, `fun agentThread(ref: SessionRef): AgentThreadModel` (= `AgentThreadModel(ref, hub, history, hub.scope)`), and how 3D builds one per sign-in | must exist |
  | `AppComposition` constructor parameters of types `SpeechEngine`, `VoicePermissionChecking`, `PushRegistrar`, `UpdateChecker`, `AttachmentReader` (contracts §15); its `vault`, `latency`, `settings: KeyValueStore`, `clock`, `push: PushRegistration?`, `updatePrompt: UpdatePrompt?`, app scope | must exist |
  | `ShellXNavHost` destinations `workspace/{machineId}/{workspaceId}`, `agent/{machineId}/{sessionId}`, `pending`; the signed-in root it shows them in | must exist |
  | `NotificationsSettingsSection()` (empty slot) and how `SettingsScreen` lays out a section | must exist |
  | The signed-in root calling `scope.decisions.sync(hub.pendingItems)` on every hub change (iPhone `SignedInView`) | Task 12 adds it to `SignedInWork` |
  | 3D's `ProcessLifecycleOwner` ON_START hook calling `updatePrompt?.check()` and `push?.appBecameActive()` (3C's UI wiring summary; iPhone `ShellXApp`), and `updatePrompt?.check()` once at launch | Task 12 adds the missing calls to that hook |
  | `StatusDot(color: Color)`; `AgentStateStyle.of(row: AgentStatusRow, res: Resources)` with `text: String?`, `shortText: String?`, `tone: StatusTone?`; `enum class StatusTone { DONE, ERROR, IDLE, NEEDS_YOU, RUNNING }` with `@Composable fun StatusTone.color(): Color` (`ShellXTheme.colors.status*`) | create if missing (Task 7) |
  | `Modifier.waitingBorder(isActive: Boolean, cornerRadius: Dp)` and `WaitingBorder.isActive(state: AgentState, online: Boolean)` | create if missing (Task 8): port `ios/UI/Components/WaitingBorder.swift` |
  | `ListNotice` (`fun show(text: String)`) and `@Composable NoticeCapsule(text: String)` | create if missing (Task 8) |
  | `WorkspaceCommand`, `WorkspaceAlert` (with `@StringRes message`), `WorkspaceFeedback` (`None`, `Open(ref)`, `Refresh`, `Alert(alert)`, `of(result, command, machineId)`), `@Composable WorkspaceAlertDialog(alert: WorkspaceAlert?, dismiss: () -> Unit)`, `@Composable AgentCloseConfirmation(name: String?, close: () -> Unit, dismiss: () -> Unit)` | create if missing (Task 7) |
  | `WorkspaceListActions.canClose(session, hub)` and `closeAgent(ref, hub, alert): Deferred<WorkspaceFeedback>?` | create if missing (Task 7) |
  | `WorkspaceListActions.canCloseTab(machineId, hub)` and `closeTab(machineId, workspaceId, terminalId, hub, alert): Deferred<WorkspaceFeedback>?` | create if missing (Task 8) |
  | `@Composable WorkspaceRenameSheet(current: String, save: (String) -> Unit, cancel: () -> Unit)` | create if missing (Task 8) |
  | `@Composable PrimaryButton(onClick, modifier, enabled, content)` and `SecondaryButton(onClick, modifier, enabled, color, content)` | create if missing (Task 4) |
  | `@Composable NeedsYouBar(items, showsMachineName, open)` | create if missing (Task 5) |
  | Catalog aliases for `lifecycle-runtime-compose`, `lifecycle-viewmodel-compose`, `lifecycle-process`, `navigation-compose`, `material-icons-extended` | Task 1 adds |

- [ ] **Step 6: Note two facts for later.**
  - Run `grep -q 'sendData' relay/src/push/fcm.ts && echo 3F-merged || echo 3F-not-merged`. Task 9 uses the answer.
  - Run the following. `REF` is the iPhone reference commit in the ledger's header.

    ```bash
    REF="$(grep -m1 -oE 'shellx-ios/` at `[0-9a-f]{7,40}' docs/superpowers/ledgers/shellx-android-parity.md | grep -oE '[0-9a-f]{7,40}$')"
    git log --oneline "$REF"..develop -- shellx-ios/ShellX/UI/Workspaces shellx-ios/ShellX/UI/Agent shellx-ios/ShellX/UI/Pending \
      shellx-ios/ShellX/UI/Composer shellx-ios/ShellX/UI/Home/NeedsYouBar.swift shellx-ios/ShellX/Voice shellx-ios/ShellX/Platform/PushAppDelegate.swift
    ```

    Read each commit it lists. Port only the behaviour this plan names, and list the commits in your report.

---

### Task 1: Build wiring, manifest and the `:app` test kit

**Files:**
- Modify: `shellx-android/gradle/libs.versions.toml`, `shellx-android/app/build.gradle.kts`, `shellx-android/app/gradle.lockfile` (rewritten by `dev.sh lock`), `scripts/shellx/android-license-allowlist.txt`, `shellx-android/app/src/main/AndroidManifest.xml`
- Create (test kit, `com.shellx.app.testing`): `app-test/testing/{TestClock,Eventually,WorkRig,FakeSpeechEngine,FakeVoicePermissions,FakeResultRegistry,TestOwner}.kt`
- Create: `app-ui-test/screenshots/RenderAssertions.kt`, only when 3D did not make it (3D Task 6 creates it with exactly the API below: keep 3D's file)
- Test: `app-test/ManifestTest.kt`, `app-test/testing/WorkRigTest.kt`

**Interfaces:**
- Consumes:
  - 3C: `Clock`, `MachineHub`, `AccountVault`, `DemoSecretStore`, `DemoRelay`, `FakeMac`, `FakeMacFleet`, `ConversationStore`, `DecisionCenter`, `PairingModel`, `SheetPresence`, `EndedDismissalStore`, `GoneRemovalStore`, `MemoryKeyValueStore`, `LatencyLog`, `SpeechEngine`, `VoicePermissionChecking`;
  - 3A: `ShellXSnapshots`, `Snapshot`;
  - 3D: `SignedInScope`.
- Produces (test kit; `app/src/test` is also on the debug UI tests' classpath):

```kotlin
object TestClock : Clock        // nowMs() = System.currentTimeMillis(); monotonic = TimeSource.Monotonic
/** Runs the main looper and waits (real time, at most timeoutMs) until condition holds: ShadowLooper.idleMainLooper(),
 *  check, Thread.sleep(5). Returns the condition's last value. */
fun eventually(timeoutMs: Long = 10_000, condition: () -> Boolean): Boolean
/** Port of ios-tests/Support/WorkspaceRig.swift. Everything runs on Dispatchers.Main.immediate (the Robolectric main looper). */
class WorkRig(val scope: SignedInScope, val mac: FakeMac, val settings: MemoryKeyValueStore) {
    val hub: MachineHub
    val machineId: String                                   // mac.machine.machineId
    fun workspaceModel(name: String = "shellx"): WorkspaceScreenModel   // WorkspaceRef(machineId, "ws-<name>")
    fun close()                                             // hub.stopAll(), cancel the scope, delete the history folder
    companion object {
        fun make(acceptsAgentClose: Boolean = true, acceptsTerminalClose: Boolean = true, acceptsAttachments: Boolean = true,
                 voice: VoiceService? = null): WorkRig
    }
}
/** A SpeechEngine the test drives (a small port of 3C's core-test FakeTranscriber, which :app cannot see). Main thread. */
class FakeSpeechEngine : SpeechEngine {
    data class Start(val run: SpeechRunId, val language: VoiceLanguage, val contextualStrings: List<String>)
    val starts: List<Start>; val finishCalls: List<SpeechRunId>; val cancelCalls: List<SpeechRunId>; val activeRun: SpeechRunId?
    var finalText: String?                 // what finish() answers for the active run; null → the last text said
    fun say(text: String)                  // the whole text so far, to the active run
    fun end(error: Throwable? = null)      // the active run's channel ends by itself
}
class FakeVoicePermissions(var microphone: Boolean = true, var needsPrompt: Boolean = false) : VoicePermissionChecking // speech() = true
/** Records each launch; answers at once with answer(launch) when set, else holds it for answerLast(result). */
class FakeResultRegistry : ActivityResultRegistry() {
    data class Launch(val requestCode: Int, val contract: ActivityResultContract<*, *>, val input: Any?)
    val launches: List<Launch>; var answer: ((Launch) -> Any?)?; fun answerLast(result: Any?)
    val owner: ActivityResultRegistryOwner           // for LocalActivityResultRegistryOwner in Compose tests
}
/** A LifecycleOwner made with LifecycleRegistry.createUnsafe, CREATED until start(). */
class TestOwner : LifecycleOwner { fun start() }
```

- Produces (`app-ui-test/screenshots/RenderAssertions.kt`, package `com.shellx.app.screenshots`):

```kotlin
/** ShellXSnapshots.capture with the iPhone render tests' checks: light-en, dark-en, light-vi, dark-vi, each a file 1179 px
 *  wide, and light differs from dark. */
fun assertRenders(name: String, content: @Composable () -> Unit): List<Snapshot>
/** Text at font scale 2 (the iPhone tests' accessibility3). */
@Composable fun LargeText(content: @Composable () -> Unit)
```

- [ ] **Step 1: Wire the build.** Paste 3A's `latest` definition first:

  ```bash
  latest() { curl -fsS "$1" | grep -o '<version>[^<]*</version>' | sed 's/<[^>]*>//g' | grep -E "^${2:-[0-9]}[0-9.]*$" | sort -V | tail -1; }
  ```

  1. **Versions.** Add catalog versions with the newest stable versions:
     - `firebaseBom`, from `latest https://dl.google.com/dl/android/maven2/com/google/firebase/firebase-bom/maven-metadata.xml`;
     - `playAppUpdate`, from `latest https://dl.google.com/dl/android/maven2/com/google/android/play/app-update/maven-metadata.xml`.
  2. **Aliases.** Add these, each unless the catalog already has the module:
     - `firebase-bom` = `com.google.firebase:firebase-bom`;
     - `firebase-messaging` = `com.google.firebase:firebase-messaging` (no version);
     - `play-app-update` = `com.google.android.play:app-update`;
     - `androidx-compose-material-icons-extended` = `androidx.compose.material:material-icons-extended`;
     - `androidx-compose-ui-test-junit4` = `androidx.compose.ui:ui-test-junit4`.

     When Task 0 found them missing, also add these, versioned with `latest` on their `dl.google.com` metadata:
     - `androidx-lifecycle-runtime-compose`;
     - `androidx-lifecycle-viewmodel-compose`;
     - `androidx-lifecycle-process`;
     - `androidx-navigation-compose`.
  3. **Module build.** In `app/build.gradle.kts`:

     ```kotlin
     implementation(platform(libs.firebase.bom))
     implementation(libs.firebase.messaging)
     implementation(libs.play.app.update)
     implementation(libs.androidx.compose.material.icons.extended)
     testImplementation(platform(libs.androidx.compose.bom))
     testImplementation(libs.androidx.compose.ui.test.junit4)
     testImplementation(libs.kotlinx.coroutines.test)
     ```

     plus `implementation(...)` of each Lifecycle/Navigation alias added above.
- [ ] **Step 2: Write the test kit and the failing tests.**
  - Write the kit files with the Interfaces above.
  - `WorkRig.make` builds what `WorkspaceRig.swift` builds, as follows.
    - **FakeMac.** `FakeMac("MacBook Pro", main, acceptsAttachments = …, acceptsAgentClose = …, acceptsTerminalClose = …)`.
    - **Workspaces.** `ws-shellx` and `ws-web`:
      - `ws-shellx`: title `shellx-ios`, order 0, directory `~/shellx/shellx-ios`, branch `feat/workspaces`. Its terminals are `t-claude` (`claude`, order 0, not selected, session `s1`) and `t-zsh` (`zsh`, order 1, selected).
      - `ws-web`: title `web`, order 1, with terminal `t-web` (`zsh`, order 0, selected).
    - **Session.** `s1` is `claude` in `ws-shellx` / `shellx-ios`, `WORKING`, with `stateSinceMs = now - 240_000` and `lastActivityMs = now`.
    - **History of `s1`.**
      - `e1`: rev 1, seq 1, USER, PROSE, `"thêm danh sách workspace vào màn chính"`, ts `1_700_000_000_000`;
      - `e2`: rev 1, seq 2, AGENT, PROSE, `"Mình sẽ thêm **WorkspaceList** và sửa màn chính."`, ts `1_700_000_001_000`.
    - **Vault.** `AccountVault(DemoSecretStore(), Dispatchers.IO)`, holding session `u1`/`d1`/`tok-1`/`a@b.c` and `[mac.machine]` owned by `u1`.
    - **Relay.** `DemoRelay(listOf(mac.machine), emptySet(), Duration.ZERO)`.
    - **Hub.** `MachineHub(vault, relay, FakeMacFleet(listOf(mac)) { vault.phoneKey() }, LatencyLog(), settings, main, TestClock) {}`.
    - **History store.** `ConversationStore(<new temp dir>, Dispatchers.IO, TestClock)`.
    - **Scope.** Build `SignedInScope` the way 3D builds one per sign-in, with `voice`.
    - **Start.** Run `hub.start()` in `main`, then require `eventually { hub.workspaceRows(machineId).size == 2 && hub.liveSessions.size == 1 }`.
  - Write `RenderAssertions.kt`. Then write the tests:

```kotlin
@RunWith(AndroidJUnit4::class)
class ManifestTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    @Test fun asksForNotificationsAndTheMicrophoneButNeverBatteryExemptions() {
        val asked = context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
            .requestedPermissions.orEmpty().toSet()
        assertTrue(Manifest.permission.POST_NOTIFICATIONS in asked)
        assertTrue(Manifest.permission.RECORD_AUDIO in asked)
        assertFalse("android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" in asked)   // S3 §7.4c
    }
    @Test fun fcmMakesNoTokenBeforeTheAppAsksForOne() {   // no FCM token or Firebase installation at a bare launch (3H Data safety)
        val meta = context.packageManager.getApplicationInfo(context.packageName, PackageManager.GET_META_DATA).metaData
        assertFalse(meta?.getBoolean("firebase_messaging_auto_init_enabled", true) ?: true)
    }
}
@RunWith(AndroidJUnit4::class)
class WorkRigTest {
    @Test fun theRigHasTwoWorkspacesAndOneWorkingSession() {
        val rig = WorkRig.make()
        try {
            assertEquals(listOf("ws-shellx", "ws-web"), rig.hub.workspaceRows(rig.machineId).map { it.id.workspaceId })
            assertEquals(listOf("s1"), rig.hub.liveSessions.map { it.session.sessionId })
            assertEquals("t-zsh", rig.workspaceModel().selectedTerminalId)
        } finally { rig.close() }
    }
    @Test fun theFakeEngineHandsTheWordsToItsRun() { runTest {
        val engine = FakeSpeechEngine(); val run = SpeechRunId()
        val words = engine.start(run, VoiceLanguage.VIETNAMESE, listOf("PR"))
        engine.say("xin chào"); assertEquals("xin chào", words.receive())
        engine.finalText = "xin chào bạn"; assertEquals("xin chào bạn", engine.finish(run))
        assertTrue(words.isClosedForReceive); assertEquals(listOf(run), engine.finishCalls); assertNull(engine.activeRun)
    } }
}
```

- [ ] **Step 3: Lock and run (red).** Run `shellx-android/scripts/dev.sh lock`, then `bash scripts/shellx/check-android-license.sh`.
  - For every `violation` line, apply 3A's allowlist procedure and rerun until the check prints `check-android-license: ok`. Firebase, Play Core and Play services artefacts are "Google SDKs listed by name" (S3 §5). When the violation names an artefact the allowlist already has as `test` and the violation says `(ship)`, change that line's scope to `ship` instead of adding a second line for it.
  - Then run `gw :app:testDebugUnitTest --tests 'com.shellx.app.ManifestTest' --tests 'com.shellx.app.testing.*'`.

  Expected: `asksForNotificationsAndTheMicrophoneButNeverBatteryExemptions FAILED` and `fcmMakesNoTokenBeforeTheAppAsksForOne FAILED`. The two `WorkRigTest` tests pass.
- [ ] **Step 4: Commit the kit and the failing test.** Run `git add shellx-android/gradle/libs.versions.toml shellx-android/app/build.gradle.kts shellx-android/app/gradle.lockfile scripts/shellx/android-license-allowlist.txt shellx-android/app/src/test shellx-android/app/src/testDebug`, then `git commit -m "test(shellx-android): app test kit; the manifest asks for notifications and the microphone"`.
- [ ] **Step 5: Edit the manifest.** Inside `<manifest>`, before `<application>`, add:

  ```xml
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
  <uses-permission android:name="android.permission.RECORD_AUDIO" />
  <!-- Android 11+: SpeechRecognizer can see the phone's recognition service only through this query. -->
  <queries>
      <intent>
          <action android:name="android.speech.RecognitionService" />
      </intent>
  </queries>
  ```

  and inside `<application>`:

  ```xml
  <!-- FCM makes no token and no Firebase installation until FcmPushRegistrar first asks for one (3C's PushRegistration, Task 9). -->
  <meta-data android:name="firebase_messaging_auto_init_enabled" android:value="false" />
  ```

- [ ] **Step 6: Run (green).** Run the same command. Expected: PASS, 2 and 2 tests.
- [ ] **Step 7: Commit.** Run `git add shellx-android/app/src/main/AndroidManifest.xml`, then `git commit -m "feat(shellx-android): notification and microphone permissions, speech service query"`.

---

### Task 2: Plan Markdown

**Files:**
- Create: `app/ui/pending/PlanMarkdownText.kt`
- Test: `app-test/ui/pending/PlanMarkdownTextTest.kt`

Reference: `ios/UI/Pending/PlanMarkdownText.swift`; `ios-tests/PendingCardRenderTests.swift` (`testPlanMarkdownBlocks`).

**Interfaces:**
- Produces (`com.shellx.app.ui.pending`):

```kotlin
@Composable fun PlanMarkdownText(markdown: String, modifier: Modifier = Modifier, color: Color = Color.Unspecified)
object PlanMarkdownText {
    sealed interface Block {
        data class Heading(val level: Int, val text: String) : Block
        data class Bullet(val text: String, val level: Int) : Block
        data class Numbered(val number: String, val text: String, val level: Int) : Block
        data class Code(val code: String) : Block
        data object Rule : Block
        data class Paragraph(val text: String) : Block
    }
    fun blocks(markdown: String): List<Block>          // the Swift body, line for line
    fun summary(markdown: String): String              // the Swift body
    /** Inline Markdown of one block, line breaks kept (iOS inlineOnlyPreservingWhitespace). */
    fun inline(text: String, code: SpanStyle = SpanStyle(fontFamily = FontFamily.Monospace), link: TextLinkStyles? = null): AnnotatedString
}
```

  `inline` scans left to right. Each opening mark that finds its closing mark becomes a span over the parsed inside; otherwise it stays text. The rules:
  - **Backslash.** `\` followed by an ASCII punctuation character is that character, as text.
  - **Code.** `` ` `` up to the next `` ` `` is code: the inside is literal, with the `code` style.
  - **Bold.** `**` or `__` up to the next identical pair, with a non-empty inside, is bold (`FontWeight.Bold`).
  - **Italic.** A single `*` or `_` up to the next single identical character is italic (`FontStyle.Italic`), when:
    - the inside is not empty;
    - the inside neither starts nor ends with whitespace;
    - for `_`, the opener does not follow a letter or digit, so `snake_case` stays text.
  - **Link.** `[label](url)` is the parsed label with `LinkAnnotation.Url(url, link)`.

  The composable draws each block the Swift way:
  - headings: level 1 `titleMedium` SemiBold, level 2 `titleSmall`, deeper levels `bodyMedium` SemiBold, each with `heading()` semantics;
  - list rows: the marker in `onSurfaceVariant` and the text indented `16.dp * min(level, 4)`;
  - code: monospace `bodySmall` on `surfaceContainerHighest`, with 8 dp corners and 10 dp padding;
  - rules: `HorizontalDivider`;
  - paragraphs: `Text(inline(...))`.

  The whole is in a `SelectionContainer`.

- [ ] **Step 1: Write the failing tests.**

```kotlin
@RunWith(AndroidJUnit4::class)
class PlanMarkdownTextTest {
    private val plan = "## Pair Macs by QR\n\n1. Add `PairingModel` and its **tests** first.\n2. Build the pairing sheet: scan, paste, confirm.\n" +
        "3. \"Your Macs\" with unpair.\n\n### Checks\n- `swift test` for ShellXAppCore\n  - render tests in light and dark\n```\ndev.sh test all\n```"
    @Test fun blocksFollowThePlansLines() {
        assertEquals(listOf(Heading(2, "Pair Macs by QR"), Numbered("1", "Add `PairingModel` and its **tests** first.", 0),
            Numbered("2", "Build the pairing sheet: scan, paste, confirm.", 0), Numbered("3", "\"Your Macs\" with unpair.", 0),
            Heading(3, "Checks"), Bullet("`swift test` for ShellXAppCore", 0), Bullet("render tests in light and dark", 1),
            Code("dev.sh test all")), PlanMarkdownText.blocks(plan))
        assertEquals(listOf(Paragraph("one\ntwo"), Paragraph("three")), PlanMarkdownText.blocks("one\ntwo\n\nthree"))
        assertEquals(listOf(Paragraph("#hashtag"), Rule, Code("open")), PlanMarkdownText.blocks("#hashtag\n---\n```\nopen"))
    }
    @Test fun aCardsSummaryCarriesTextNotMarks() {
        assertEquals("Title\n1. First\n• item\ntext", PlanMarkdownText.summary("## Title\n\n1. First\n- item\n---\ntext"))
    }
    @Test fun inlineMarksBecomeSpans() {
        val s = PlanMarkdownText.inline("Add `PairingModel` and its **tests** first, *now*.")
        assertEquals("Add PairingModel and its tests first, now.", s.text)
        fun spans(p: (SpanStyle) -> Boolean) = s.spanStyles.filter { p(it.item) }.map { s.text.substring(it.start, it.end) }
        assertEquals(listOf("PairingModel"), spans { it.fontFamily == FontFamily.Monospace })
        assertEquals(listOf("tests"), spans { it.fontWeight == FontWeight.Bold })
        assertEquals(listOf("now"), spans { it.fontStyle == FontStyle.Italic })
    }
    @Test fun unclosedMarksAndIntrawordUnderscoresStayText() {
        for (t in listOf("**unclosed", "snake_case_name", "a * b * c", "`open code", "[label](no close", "dòng một\n**không đóng"))
            assertEquals(t, PlanMarkdownText.inline(t).text)
        assertEquals("2 * 3", PlanMarkdownText.inline("2 \\* 3").text)
    }
    @Test fun linksKeepTheirLabelAndUrl() {
        val s = PlanMarkdownText.inline("see [the docs](https://shellx.pro/docs) now")
        assertEquals("see the docs now", s.text)
        val link = s.getLinkAnnotations(0, s.length).single()
        assertEquals("https://shellx.pro/docs", (link.item as LinkAnnotation.Url).url)
        assertEquals("the docs", s.text.substring(link.start, link.end))
    }
}
```

- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.ui.pending.PlanMarkdownTextTest'`.

  Expected: `Unresolved reference` naming `PlanMarkdownText`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test/kotlin/com/shellx/app/ui/pending`, then `git commit -m "test(shellx-android): plan Markdown blocks and inline marks"`.
- [ ] **Step 4: Implement `PlanMarkdownText.kt`.**
- [ ] **Step 5: Run (green).** Expected: PASS, 5 tests.
- [ ] **Step 6: Commit.** Run `git add shellx-android/app/src/main/kotlin/com/shellx/app/ui/pending/PlanMarkdownText.kt`, then `git commit -m "feat(shellx-android): plan Markdown text"`.

---

### Task 3: The speech engine, its capability probe, permissions and level meter

**Files:**
- Create in `app/voice/`: `RecognizerPort.kt` (with `SystemRecognizerPort`, `RecognizerKind`), `SpeechRecognizerEngine.kt` (with `RecognizerIntents`), `AudioLevelMeter.kt`, `VoiceCapabilityProbe.kt`, `SystemVoicePermissions.kt`, `SystemVoice.kt`, `VoiceEnvironment.kt` (with `MicActivity`, `LocalVoice`)
- Create: `app/platform/PermissionRequester.kt`
- Test in `app-test/voice/`: `SpeechRecognizerEngineTest.kt`, `VoiceCapabilityProbeTest.kt`, `SystemVoicePermissionsTest.kt`, `AudioLevelMeterTest.kt`
- Test: `app-test/platform/PermissionRequesterTest.kt`

Reference:
- `ios/Voice/LegacyTranscriber.swift` (runs, the final-result wait, a teardown during start);
- `ios/Voice/AnalyzerTranscriber.swift` (start errors that blame the recognizer or the audio);
- `ios/Voice/{VoiceService,SystemVoicePermissions,VoiceCapabilityProbe,AudioLevelMeter}.swift`;
- 3C Tasks 24–26.

**Interfaces:**
- Consumes (3C, `com.shellx.core.voice`): `SpeechEngine`, `SpeechRunId`, `SpeechRunSlot` (with `Handlers` and `Claim`), `SpeechStartException.Recognizer` / `Audio`, `SpeechTimeouts`, `FallbackTranscriber`, `TranscriptAccumulator`, `VoiceLanguage`, `VoiceCapabilities`, `VoiceCapabilityCache`, `VoicePermissionChecking`, `VoiceService`.
- Produces:

```kotlin
// com.shellx.app.voice
enum class RecognizerKind { ON_DEVICE, STANDARD }
/** One platform recognizer for one run; SystemRecognizerPort wraps android.speech.SpeechRecognizer (main thread only). */
interface RecognizerPort {
    fun start(intent: Intent, listener: RecognitionListener)   // setRecognitionListener, then startListening
    fun stop()                                                  // stopListening: the recognizer delivers its final result
    fun cancel()
    fun destroy()
}
class SystemRecognizerPort(recognizer: SpeechRecognizer) : RecognizerPort {
    companion object {
        /** ON_DEVICE: API 31+ and SpeechRecognizer.isOnDeviceRecognitionAvailable → createOnDeviceSpeechRecognizer.
         *  STANDARD: SpeechRecognizer.isRecognitionAvailable → createSpeechRecognizer. Otherwise null. Main thread. */
        fun create(context: Context, kind: RecognizerKind): RecognizerPort?
    }
}
/** The intent of one listening segment. */
class RecognizerIntents(packageName: String, sdkInt: Int = Build.VERSION.SDK_INT) {
    /** ACTION_RECOGNIZE_SPEECH with LANGUAGE_MODEL_FREE_FORM, EXTRA_LANGUAGE = language.tag, EXTRA_PARTIAL_RESULTS = true,
     *  EXTRA_MAX_RESULTS = 1, EXTRA_PREFER_OFFLINE = preferOffline, EXTRA_CALLING_PACKAGE; on API 33+ also
     *  EXTRA_BIASING_STRINGS = contextualStrings and EXTRA_ENABLE_FORMATTING = FORMATTING_OPTIMIZE_QUALITY. */
    fun of(language: VoiceLanguage, contextualStrings: List<String>, preferOffline: Boolean): Intent
}
/** One android.speech recognizer as 3C's SpeechEngine (iPhone LegacyTranscriber and AnalyzerTranscriber). */
class SpeechRecognizerEngine(
    kind: RecognizerKind, slot: SpeechRunSlot, makePort: () -> RecognizerPort?, meter: AudioLevelMeter,
    intents: RecognizerIntents, main: CoroutineDispatcher = Dispatchers.Main.immediate,
    preferOffline: suspend (VoiceLanguage) -> Boolean = { false },
) : SpeechEngine {
    companion object {
        val READY_TIMEOUT: Duration                               // 3 s
        fun finalTimeout(kind: RecognizerKind): Duration          // ON_DEVICE → SpeechTimeouts.ON_DEVICE_FINALIZE, STANDARD → STANDARD_FINAL_RESULT
        fun startError(code: Int): SpeechStartException           // the table below
    }
}
/** How loud the voice is, 0..1 (iPhone AudioLevelMeter). Thread-safe. */
class AudioLevelMeter {
    val level: StateFlow<Float>
    fun update(rmsDb: Float)          // ((rmsDb - RMS_FLOOR_DB) / (RMS_CEILING_DB - RMS_FLOOR_DB)).coerceIn(0f, 1f)
    fun reset()
    companion object { const val RMS_FLOOR_DB = -2f; const val RMS_CEILING_DB = 10f }
}
/** What can recognize a language right now (iPhone VoiceCapabilityProbe). */
class VoiceCapabilityProbe(
    sdkInt: Int, onDeviceAvailable: () -> Boolean, standardAvailable: () -> Boolean,
    /** API 33+: the languages installed on the device for that recognizer (checkRecognitionSupport); null when unknown. */
    installedLanguages: suspend (RecognizerKind, VoiceLanguage) -> Set<String>?,
) {
    suspend fun capabilities(language: VoiceLanguage): VoiceCapabilities
    suspend fun onDeviceReady(language: VoiceLanguage): Boolean      // capabilities(language).onDeviceRecognizer
    suspend fun standardOnDevice(language: VoiceLanguage): Boolean
    fun markFailed(language: VoiceLanguage)                          // the on-device recognizer is not offered again (process)
    companion object {
        val SUPPORT_TIMEOUT: Duration                                // 2 s
        fun system(context: Context): VoiceCapabilityProbe
        fun matches(tag: String, language: VoiceLanguage): Boolean   // equal ignoring case, or the same first subtag (split on - or _)
    }
}
// com.shellx.app.platform
/** Runtime permissions for code that is not a screen (the mic's model, the push effect). Main thread. */
class PermissionRequester(context: Context) {
    fun isGranted(permission: String): Boolean
    /** Registers one RequestPermission launcher (key "shellx.permission") in registry; call from MainActivity.onCreate. */
    fun attach(registry: ActivityResultRegistry, owner: LifecycleOwner)
    /** The user's answer; false at once while nothing is attached. Requests run one at a time, in order; a request for a
     *  permission already being asked waits for that answer. */
    suspend fun request(permission: String): Boolean
}
// com.shellx.app.voice
class SystemVoicePermissions(requester: PermissionRequester) : VoicePermissionChecking   // needsPrompt = !granted(RECORD_AUDIO);
                                                       // microphone = granted || request(RECORD_AUDIO); speech = true
/** The phone's speech recognition (iPhone VoiceService.system): the on-device recognizer first, the standard one as fallback. */
class SystemVoice(context: Context, probe: VoiceCapabilityProbe = VoiceCapabilityProbe.system(context),
                  val meter: AudioLevelMeter = AudioLevelMeter()) {
    val probe: VoiceCapabilityProbe
    /** FallbackTranscriber(slot, onDevice, standard, usePrimary = probe::onDeviceReady,
     *  primaryFailed = { probe.markFailed(it); newestService?.primaryFellBack(it) }); both engines share slot and meter, make
     *  ports with SystemRecognizerPort.create(context, kind), and the STANDARD one gets preferOffline = probe::standardOnDevice. */
    val engine: SpeechEngine
    /** VoiceService(engine, permissions, VoiceCapabilityCache(timeSource = clock.monotonic, ask = probe::capabilities),
     *  latency, settings, hub.scope, clock.monotonic, preferredLanguages = the phone's locale list as BCP 47 tags,
     *  VoiceService.contextualStrings(hub)). The newest one made hears primaryFellBack. */
    fun makeService(hub: MachineHub, permissions: VoicePermissionChecking, latency: LatencyLog, settings: KeyValueStore,
                    clock: Clock): VoiceService
}
/** What a mic needs (iPhone: VoiceService in the environment). service null shows no mic; mic actions that must outlive
 *  a composable run in scope (the hub's). */
class VoiceEnvironment(val service: VoiceService?, val meter: AudioLevelMeter, val scope: CoroutineScope,
                       val activity: MicActivity = MicActivity())
/** Which mics are active now (VoiceService.isListening is not observable); the workspace pager stops paging while one is. */
class MicActivity { val anyActive: StateFlow<Boolean>; fun update(mic: Any, active: Boolean) }
val LocalVoice: ProvidableCompositionLocal<VoiceEnvironment?>       // staticCompositionLocalOf { null }
```

  **The run's states and the error mapping.** The engine's private `Run` holds:
  - the port and its listener;
  - a `Channel<String>(CONFLATED)`;
  - a `TranscriptAccumulator`;
  - a `ready: CompletableDeferred<Unit>`;
  - a `final: CompletableDeferred<String>`;
  - a state: STARTING, LISTENING, FINISHING or ENDED.

  Every port call and listener callback runs on `main`. `start`, `finish` and `cancel` do this:
  1. **`start(run, language, strings)`.**
     1. Call `slot.begin(run)`, then `makePort()`. Null → throw `SpeechStartException.Recognizer(IllegalStateException("unavailable"))`.
     2. `slot.claim(run, Handlers(finish = { finish(r) }, teardown = { tearDown(r) }))`. On `Refused`, destroy the port, close the channel and return it. On `Granted(replaced)`, call `replaced?.teardown()`.
     3. Call `port.start(intents.of(language, strings, preferOffline(language)), listener)`.
     4. Wait with `withTimeoutOrNull(READY_TIMEOUT) { ready.await() }`.
        - It completes on `onReadyForSpeech`, `onBeginningOfSpeech` or the first partial result.
        - An `onError` before that fails it with `startError(code)`: tear down, then throw that error.
        - A timeout: tear down, then throw `SpeechStartException.Recognizer(TimeoutException())`.
     5. If the slot no longer holds `run`, tear down and return the closed channel. Otherwise set LISTENING and return the channel.
  2. **Partial result.** `send(acc.take(first, isFinal = false))`.
  3. **`onResults`.** `whole = acc.take(first ?: "", isFinal = true)`, then `send(whole)`.
     - When FINISHING: complete `final` with `acc.text`, then tear down.
     - When LISTENING and the segment's text is not blank: call `port.start(<the same intent>, listener)` again. The user paused but still holds; this is RF 5.
     - When LISTENING and the segment is blank: end by itself.
  4. **`onError(code)`.**
     - In STARTING: see start.
     - In FINISHING: complete `final` with `acc.text`, then tear down.
     - In LISTENING: `ERROR_NO_MATCH` (7) and `ERROR_SPEECH_TIMEOUT` (6) end by itself with no error. Any other code ends by itself with `IOException("speech_error_$code")` when `acc.text` is blank, and with no error otherwise. Words heard are always kept.
  5. **Ending by itself.**
     1. Close the channel, with the error if there is one.
     2. Set ENDED.
     3. Call `meter.reset()`.
     4. When `slot.ended(run)`, call `port.destroy()`.
  6. **`onRmsChanged(db)`** → `meter.update(db)` while LISTENING or FINISHING.
  7. **`finish(r)`** (through `slot.takeForFinish`).
     1. Set FINISHING and call `port.stop()`.
     2. `text = withTimeoutOrNull(finalTimeout(kind)) { final.await() } ?: acc.text`.
     3. Tear down, then return `text`. The public `finish(run)` returns `""` when the slot hands back nothing.
  8. **`tearDown(r)`** (cancel, or a newer run took the microphone): unless ENDED, call `port.cancel()` and `port.destroy()`, close the channel, reset the meter, complete `final` with `acc.text`, and set ENDED.

  `startError(code)`:
  - `ERROR_AUDIO` (3) and `ERROR_INSUFFICIENT_PERMISSIONS` (9) → `SpeechStartException.Audio(IOException("speech_error_$code"))`;
  - every other code (1, 2, 4, 5, 8, 10–15, unknown) → `SpeechStartException.Recognizer(IOException("speech_error_$code"))`.

  **`VoiceCapabilityProbe` rules.**
  - `onDeviceRecognizer` is true when all of these hold:
    - `sdkInt >= 31`;
    - `onDeviceAvailable()`;
    - the language was not marked failed;
    - `installedLanguages(ON_DEVICE, language)` is null or holds a match. API 31–32 cannot tell, so it is tried; a start failure falls back and marks it (3C's `FallbackTranscriber`).
  - `standardAvailable` = `standardAvailable()`.
  - `standardOnDevice` = `standardAvailable && sdkInt >= 33 && installedLanguages(STANDARD, language)` holds a match.
  - `system(context)` asks `SpeechRecognizer.checkRecognitionSupport` on the main thread, through a fresh recognizer of that kind that it destroys afterwards. It reads `RecognitionSupport.installedOnDeviceLanguages`, within `SUPPORT_TIMEOUT`. Below API 33, or on an error or timeout, the answer is null.

- [ ] **Step 1: Write the failing tests.** The engine tests use this fake:

```kotlin
private class FakePort : RecognizerPort {
    val intents = mutableListOf<Intent>(); var listener: RecognitionListener? = null
    var stops = 0; var cancels = 0; var destroyed = false
    override fun start(intent: Intent, listener: RecognitionListener) { intents += intent; this.listener = listener }
    override fun stop() { stops++ }
    override fun cancel() { cancels++ }
    override fun destroy() { destroyed = true }
    fun ready() = listener!!.onReadyForSpeech(Bundle())
    fun partial(t: String) = listener!!.onPartialResults(bundle(t))
    fun results(t: String) = listener!!.onResults(bundle(t))
    fun error(code: Int) = listener!!.onError(code)
    private fun bundle(t: String) = Bundle().apply { putStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION, arrayListOf(t)) }
}
```

```kotlin
@RunWith(AndroidJUnit4::class)
class SpeechRecognizerEngineTest {
    private val ports = mutableListOf<FakePort>()
    private fun TestScope.engine(kind: RecognizerKind = RecognizerKind.STANDARD, slot: SpeechRunSlot = SpeechRunSlot(),
                                 meter: AudioLevelMeter = AudioLevelMeter()) =
        SpeechRecognizerEngine(kind, slot, { FakePort().also { ports += it } }, meter, RecognizerIntents("com.shellx.dev", 33),
            StandardTestDispatcher(testScheduler))
    private suspend fun TestScope.listening(e: SpeechRecognizerEngine, run: SpeechRunId, strings: List<String> = emptyList()): ReceiveChannel<String> {
        val started = async { e.start(run, VoiceLanguage.VIETNAMESE, strings) }; runCurrent()
        assertFalse(started.isCompleted); ports.last().ready(); return started.await()
    }

    @Test fun aRunWaitsForTheRecognizerAndSendsTheWholeText() { runTest {
        val e = engine(); val words = listening(e, SpeechRunId(), listOf("shellx", "PR"))
        ports[0].partial("chạy"); assertEquals("chạy", words.receive())
        ports[0].partial("chạy test"); assertEquals("chạy test", words.receive())
        val intent = ports[0].intents.single()
        assertEquals("vi-VN", intent.getStringExtra(RecognizerIntent.EXTRA_LANGUAGE))
        assertTrue(intent.getBooleanExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false))
        assertEquals(1, intent.getIntExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 0))
        assertEquals(arrayListOf("shellx", "PR"), intent.getStringArrayListExtra(RecognizerIntent.EXTRA_BIASING_STRINGS))
    } }
    @Test fun aPauseWhileHeldKeepsListeningAndTheWords() { runTest {                       // RF 5
        val e = engine(); val run = SpeechRunId(); val words = listening(e, run)
        ports[0].partial("chạy test"); ports[0].results("chạy test")
        assertEquals(2, ports[0].intents.size)                                             // listening again, same recognizer
        ports[0].partial("rồi tạo PR"); assertEquals("chạy test rồi tạo PR", words.receive())
        val finished = async { e.finish(run) }; runCurrent(); assertEquals(1, ports[0].stops)
        ports[0].results("rồi tạo PR")
        assertEquals("chạy test rồi tạo PR", finished.await()); assertTrue(ports[0].destroyed)
    } }
    @Test fun silenceAfterWordsEndsTheRunKeepingThem() { runTest {                          // RF 5
        val slot = SpeechRunSlot(); val e = engine(slot = slot); val words = listening(e, SpeechRunId())
        ports[0].partial("xin chào"); ports[0].error(SpeechRecognizer.ERROR_SPEECH_TIMEOUT)
        assertEquals("xin chào", words.receive())
        assertNull(words.receiveCatching().exceptionOrNull()); assertTrue(words.isClosedForReceive)
        assertEquals(1, ports[0].intents.size); assertTrue(ports[0].destroyed); assertNull(slot.active)
    } }
    @Test fun aNetworkErrorBeforeAnyWordEndsTheRunWithIt() { runTest {
        val e = engine(); val words = listening(e, SpeechRunId())
        ports[0].error(SpeechRecognizer.ERROR_NETWORK)
        assertTrue(words.receiveCatching().exceptionOrNull() is IOException)
    } }
    @Test fun finishWaitsForTheFinalResultAtMostItsTimeout() { runTest {
        for ((kind, ms) in listOf(RecognizerKind.STANDARD to 1_500L, RecognizerKind.ON_DEVICE to 2_000L)) {
            val e = engine(kind); val run = SpeechRunId(); listening(e, run); ports.last().partial("gần xong")
            val finished = async { e.finish(run) }; advanceTimeBy(ms - 1); runCurrent(); assertFalse(finished.isCompleted)
            advanceTimeBy(2); runCurrent(); assertEquals("gần xong", finished.await()); assertEquals(1, ports.last().cancels)
        }
    } }
    @Test fun startErrorsSayWhoseFaultTheyWere() { runTest {
        for ((code, recognizer) in listOf(12 to true, 13 to true, 5 to true, 8 to true, 4 to true, 2 to true, 3 to false, 9 to false)) {
            val e = engine(); val started = async { runCatching { e.start(SpeechRunId(), VoiceLanguage.ENGLISH, emptyList()) } }
            runCurrent(); ports.last().error(code)
            val error = started.await().exceptionOrNull()
            assertTrue("$code", if (recognizer) error is SpeechStartException.Recognizer else error is SpeechStartException.Audio)
            assertTrue(ports.last().destroyed)
        }
        val none = SpeechRecognizerEngine(RecognizerKind.ON_DEVICE, SpeechRunSlot(), { null }, AudioLevelMeter(),
            RecognizerIntents("p", 33), StandardTestDispatcher(testScheduler))
        assertTrue(runCatching { none.start(SpeechRunId(), VoiceLanguage.ENGLISH, emptyList()) }.exceptionOrNull() is SpeechStartException.Recognizer)
        val slow = engine(); val started = async { runCatching { slow.start(SpeechRunId(), VoiceLanguage.ENGLISH, emptyList()) } }
        advanceTimeBy(3_001); runCurrent(); assertTrue(started.await().exceptionOrNull() is SpeechStartException.Recognizer)
    } }
    @Test fun aNewerRunTearsDownTheOlderRecognizer() { runTest {
        val slot = SpeechRunSlot(); val e = engine(slot = slot); val old = listening(e, SpeechRunId())
        val newer = SpeechRunId(); listening(e, newer)
        assertEquals(1, ports[0].cancels); assertTrue(ports[0].destroyed); assertTrue(old.isClosedForReceive)
        assertEquals(newer, slot.active); assertFalse(ports[1].destroyed)
    } }
    @Test fun levelsReachTheMeterAndDropAtTheEnd() { runTest {
        val meter = AudioLevelMeter(); val e = engine(meter = meter); val run = SpeechRunId(); listening(e, run)
        ports[0].listener!!.onRmsChanged(10f); assertEquals(1f, meter.level.value, 0f)
        ports[0].listener!!.onRmsChanged(4f); assertEquals(0.5f, meter.level.value, 0.001f)
        e.cancel(run); runCurrent(); assertEquals(0f, meter.level.value, 0f); assertTrue(ports[0].destroyed)
    } }
    @Test fun belowApi33TheIntentHasNoBias() {
        val intent = RecognizerIntents("p", sdkInt = 32).of(VoiceLanguage.ENGLISH, listOf("PR"), preferOffline = true)
        assertNull(intent.getStringArrayListExtra(RecognizerIntent.EXTRA_BIASING_STRINGS))
        assertTrue(intent.getBooleanExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, false))
        assertEquals("en-US", intent.getStringExtra(RecognizerIntent.EXTRA_LANGUAGE))
    }
}
```

  The other tests. Each comment line is one `@Test` with those values:

```kotlin
class VoiceCapabilityProbeTest {   // probe(sdk = 34, onDevice = true, standard = true, installed = { kind, _ -> … })
    // theOnDeviceRecognizerComesFirstWhenItHasTheLanguage: ON_DEVICE installs {"vi-VN"} → VIETNAMESE capabilities ==
    //   VoiceCapabilities(true, false, true); engine == ON_DEVICE_RECOGNIZER
    // withoutTheLanguageOnDeviceTheStandardRecognizerRuns: ON_DEVICE {"en-US"}, STANDARD {} → VIETNAMESE ==
    //   VoiceCapabilities(false, false, true); engine == SERVER; STANDARD {"vi"} → VoiceCapabilities(false, true, true), ON_DEVICE
    // aLanguageThatFailedOnDeviceIsNotOfferedAgain: markFailed(VIETNAMESE) → onDeviceReady(VIETNAMESE) false, ENGLISH still true
    // belowApi31ThereIsNoOnDeviceRecognizer: sdk 30 → onDeviceRecognizer false even with onDevice = true
    // unknownSupportIsTriedOnApi31: sdk 31, installed returns null → onDeviceRecognizer true
    // nothingAvailableIsNoEngine: onDevice false, standard false → engine == null
    // tagsMatchByTheirFirstSubtag: matches("vi", VIETNAMESE), matches("vi_VN", VIETNAMESE), matches("EN-gb", ENGLISH);
    //   !matches("ve-VE", VIETNAMESE)
}
@RunWith(AndroidJUnit4::class)
class PermissionRequesterTest {   // FakeResultRegistry + TestOwner (attach while CREATED, then start())
    // nothingAttachedAnswersFalse: request(RECORD_AUDIO) == false; launches empty
    // oneLaunchAnswersEveryoneAskingTheSamePermission: two concurrent requests → registry.launches.size == 1 with input
    //   RECORD_AUDIO; answerLast(true) → both true
    // requestsForDifferentPermissionsRunInOrder: RECORD_AUDIO then POST_NOTIFICATIONS → the second launches only after
    //   the first was answered
}
@RunWith(AndroidJUnit4::class)
class SystemVoicePermissionsTest {
    // aGrantedMicrophoneAsksNothing: grantPermissions(RECORD_AUDIO) → needsPrompt false, microphone true, no launch, speech true
    // aMissingMicrophoneIsAskedForOnce: denied → needsPrompt true; microphone() launches RequestPermission(RECORD_AUDIO);
    //   answer false → false
}
class AudioLevelMeterTest {
    // decibelsMapLinearlyAndClamp: update(-2f) → 0; update(10f) → 1; update(4f) → 0.5; update(-30f) → 0; update(40f) → 1; reset() → 0
}
```

- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.voice.*' --tests 'com.shellx.app.platform.PermissionRequesterTest'`.

  Expected: `Unresolved reference` naming `RecognizerPort`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test`, then `git commit -m "test(shellx-android): speech recognizer engine, capability probe and permissions"`.
- [ ] **Step 4: Implement** the files in Interfaces.
- [ ] **Step 5: Run (green).** Run it three times. Expected each time: PASS, with these counts:
  - `voice.SpeechRecognizerEngineTest`: 9;
  - `voice.VoiceCapabilityProbeTest`: 7;
  - `platform.PermissionRequesterTest`: 3;
  - `voice.SystemVoicePermissionsTest`: 2;
  - `voice.AudioLevelMeterTest`: 1.
- [ ] **Step 6: Commit with the ledger.**
  - Set row `6.2-20` to `done (3E)`.
  - Add row `A-e1`:
    - difference: "While the mic is held, the recognizer starts listening again after each pause that produced words; a silent stretch ends the dictation and keeps the words";
    - why: "Android's SpeechRecognizer ends a segment at every pause";
    - Android: `app:voice/SpeechRecognizerEngine.kt`;
    - plan: 3E;
    - state: `differs (3E): by design`.

  Run `git add shellx-android/app/src/main/kotlin/com/shellx/app/voice shellx-android/app/src/main/kotlin/com/shellx/app/platform docs/superpowers/ledgers/shellx-android-parity.md`, then `git commit -m "feat(shellx-android): SpeechRecognizer engine with on-device first, probe, permissions and level meter"`.

---

### Task 4: The composer: buttons, the mic, the live words, the bar and attachments

**Files:**
- Create if missing (Task 0): `app/ui/components/PrimaryButtonStyle.kt` (`PrimaryButton`), `app/ui/components/SecondaryButtonStyle.kt` (`SecondaryButton`)
- Create in `app/ui/composer/`: `MicButton.kt`, `VoiceStatusView.kt`, `ComposerBar.kt` (with `byteCount`), `AttachMenu.kt`, `AttachmentStrip.kt` (with `AttachmentThumbnails`), `AttachmentPreparer.kt` (with `LocalAttachmentReader`)
- Modify: `res/values/strings_android.xml`, `res/values-vi/strings_android.xml`, then regenerate `res/values/strings.xml` and `res/values-vi/strings.xml`
- Create (test kit): `app-test/testing/VoiceRig.kt`, `app-test/testing/TestAttachmentProvider.kt`
- Test: `app-test/ui/composer/AttachmentPreparerTest.kt`, `app-test/ui/composer/ComposerTextsTest.kt`
- Test: `app-ui-test/ui/composer/MicButtonTest.kt`, `app-ui-test/ui/composer/ComposerBarTest.kt`, `app-ui-test/screenshots/ComposerRenderTest.kt`

Reference: `ios/UI/Composer/*.swift`, `ios/UI/Components/{PrimaryButtonStyle,SecondaryButtonStyle}.swift`; `ios-tests/MicButtonRenderTests.swift` (the composer part); `ios-tests/AttachmentPreparerTests.swift` (the file rules).

**Interfaces:**
- Consumes:
  - 3C: `VoiceInputModel` (`press`, `drag`, `release`, `outcome`, `typeInstead`, `cancel`, `dismiss`, `phase`, `wantsKeyboard`, `limitReached`, `maxBytes`, `isActive`), `MicHold`, `DictationOutcome`, `ComposerValidation`, `ComposerDraft`, `OutgoingAttachment`, `PendingPicks`, `AttachmentReader`, `AttachmentPick`, `AttachmentReadException`, `AttachmentChecks`, `com.shellx.core.text`;
  - 3B: `ShellXLink` (`com.shellx.link.core`, reached through `:core`), with `ShellXLink.MAX_ATTACHMENTS_PER_MESSAGE` and `ShellXLink.MAX_ATTACHMENT_BYTES`;
  - Task 3: `LocalVoice`, `VoiceEnvironment`, `MicActivity`, `AudioLevelMeter`.
- Produces:

```kotlin
// com.shellx.app.ui.components (iPhone PrimaryButtonStyle / SecondaryButtonStyle)
/** accent fill, onAccent label, 12 dp corners, at least 50 dp tall, 0.4 alpha when disabled. */
@Composable fun PrimaryButton(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, content: @Composable RowScope.() -> Unit)
/** The same shape: `color` at 14 % behind a label in `color`. */
@Composable fun SecondaryButton(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true,
                                color: Color = ShellXTheme.colors.accentText, content: @Composable RowScope.() -> Unit)
// com.shellx.app.ui.composer
@Composable fun MicButton(model: VoiceInputModel, @StringRes label: Int, modifier: Modifier = Modifier, diameter: Dp = 58.dp,
    onOutcome: (DictationOutcome) -> Unit, onKeyboard: (() -> Unit)? = null, onPress: (() -> Unit)? = null, onNothing: (() -> Unit)? = null)
object MicButton {
    /** IDLE and FINISHING → Icons.Outlined.Mic; LISTENING → Icons.Filled.GraphicEq; CANCEL_ARMED → Icons.Filled.Close;
     *  DENIED and UNAVAILABLE → Icons.Outlined.MicOff. */
    fun symbol(phase: VoiceInputModel.Phase): ImageVector
}
@Composable fun VoiceStatusView(model: VoiceInputModel, level: Float, modifier: Modifier = Modifier)
object VoiceStatusView {
    const val SHOWN_CHARACTERS = 160
    /** The text when it has at most 160 graphemes; else "…" + the last 160 graphemes, starting after their first whitespace. */
    fun newest(text: String): String
}
@Composable fun ComposerBar(draft: ComposerDraft, onDraftChange: (ComposerDraft) -> Unit, send: (String, List<OutgoingAttachment>) -> Unit,
    modifier: Modifier = Modifier, attachmentsEnabled: Boolean = false, sending: Double? = null,
    sendVoice: ((String) -> Unit)? = null, voice: VoiceInputModel? = null)   // voice null → LocalVoice.current?.service?.makeModel()
object ComposerBar {
    /** TooManyAttachments → composer_attach_too_many; AttachmentTooLarge(name) → composer_attach_too_large(name); else null. */
    fun problem(validation: ComposerValidation, res: Resources): String?
}
/** "16,384" in English; "16 384" with U+00A0 in Vietnamese (NumberFormat with the grouping separator replaced). */
fun ComposerValidation.Companion.byteCount(count: Int, locale: Locale): String
@Composable fun AttachMenu(attachments: List<OutgoingAttachment>, onAdd: (OutgoingAttachment) -> Unit, picks: PendingPicks,
                           side: Dp, enabled: Boolean, note: (String?) -> Unit)
@Composable fun AttachmentStrip(attachments: List<OutgoingAttachment>, onRemove: (String) -> Unit, locked: Boolean,
                                loading: List<String>, cancelLoading: (String) -> Unit)
object AttachmentStrip { val TILE_SIDE: Dp }                                  // 56.dp
/** Small images of the photos in the composer, decoded with inSampleSize so the long side is at least MAX_PIXEL_SIZE, kept
 *  in an LruCache of 32 by attachment id. Display only: what is sent is untouched. */
object AttachmentThumbnails { const val MAX_PIXEL_SIZE = 200; fun image(attachment: OutgoingAttachment): ImageBitmap? }
/** 3C's AttachmentReader over a ContentResolver (iPhone AttachmentPreparer). */
class AttachmentPreparer(resolver: ContentResolver, io: CoroutineDispatcher) : AttachmentReader {
    companion object {
        const val CHUNK_BYTES = 65_536
        /** TooLarge(name) → composer_attach_too_large(name); Unreadable(name) → composer_attach_unreadable(name). */
        fun message(failure: AttachmentReadException, res: Resources): String
    }
}
/** The reader the composer uses; null → AttachmentPreparer(LocalContext.current.contentResolver, Dispatchers.IO). */
val LocalAttachmentReader: ProvidableCompositionLocal<AttachmentReader?>     // staticCompositionLocalOf { null }
```

- Produces (test kit):

```kotlin
/** A VoiceService over FakeSpeechEngine and FakeVoicePermissions on the main looper (iPhone MicButtonRenderTests' rig). */
class VoiceRig(val engine: FakeSpeechEngine, val permissions: FakeVoicePermissions, val service: VoiceService, val env: VoiceEnvironment) {
    fun model(maxBytes: Int = ComposerValidation.MAX_BYTES): VoiceInputModel
    companion object {
        val SERVER_ONLY: VoiceCapabilities                // VoiceCapabilities(false, false, true)
        /** settings: MemoryKeyValueStore with VIETNAMESE saved; the meter at `level`. */
        fun make(capabilities: VoiceCapabilities = SERVER_ONLY, microphone: Boolean = true, level: Float = 0.6f): VoiceRig
    }
}
/** A ContentProvider for "content://com.shellx.test.attachments/<name>": query gives DISPLAY_NAME and SIZE from `entries`,
 *  getType the entry's MIME type. Register with Robolectric.setupContentProvider; streams come from
 *  shadowOf(contentResolver).registerInputStream. */
class TestAttachmentProvider : ContentProvider() {
    companion object { val entries: MutableMap<String, Entry>; data class Entry(val name: String, val size: Long?, val mime: String?) }
}
```

  **The hold gesture** (`MicButton`). This body follows 3C's `MicHold`: only a lift sends, and a hold taken away cancels.

  ```kotlin
  Modifier.pointerInput(model, touchExploration) {
      if (touchExploration) return@pointerInput             // TalkBack on: taps go through semantics only
      awaitEachGesture {
          val down = awaitFirstDown(requireUnconsumed = false); down.consume()
          perform(hold.holdingChanged(true))                // PRESS
          var lifted = false
          try {
              while (true) {
                  val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                  if (!change.pressed) { lifted = true; change.consume(); break }
                  if (change.isConsumed) break               // another handler took the touch
                  val d = change.position - down.position
                  model.drag(d.x.toDp().value.toDouble(), d.y.toDp().value.toDouble())
                  change.consume()                          // the pager never sees the drag
              }
          } finally {                                       // also when the composable leaves while held
              if (lifted) perform(hold.ended())             // RELEASE
              perform(hold.holdingChanged(false))
              perform(hold.settle())                        // CANCEL when there was no lift
          }
      }
  }
  ```

  The three actions, all launched in `LocalVoice.current!!.scope`:
  - `PRESS → start()`. When the model is not active: haptic `GestureThresholdActivate`, `onPress()`, then `model.press()`.
  - `RELEASE → finish()`. Note whether cancel was armed, then call `release()`.
    - Words → `outcome(words)`. A `Complete` outcome plays haptic `Confirm`. Then call `onOutcome`.
    - Null → when cancel was armed, haptic `Reject`. Then call `onNothing`.
  - `CANCEL → cancel()`. `drag(-VoiceInputModel.CANCEL_DISTANCE, 0.0)`, then `finish()`.

  Accessibility:
  - `touchExploration` is `AccessibilityManager.isTouchExplorationEnabled`, followed with a listener.
  - Semantics: role Button and test tag `voice.mic`.
  - `contentDescription`: `label`, or `voice_mic_stop` while active.
  - `stateDescription`: `voice_mic_hint` while idle.
  - `onClick`: finish while active, start otherwise.
  - Custom actions: `common_cancel` while active, and `voice_keyboard` when `onKeyboard` is set.

  The model's active state is reported to `LocalVoice.current.activity`, and taken back on dispose. The look follows `MicButton.swift`:
  - rings only while active; at a fixed size when animations are off (`Settings.Global.ANIMATOR_DURATION_SCALE == 0`);
  - an accent fill while active, otherwise accent at 15 % with an accent border at 45 %;
  - 1.06 scale while active, 0.55 alpha while cancel is armed.

  **`ComposerBar`** ports `ComposerBar.swift`:
  - **The mic** shows only while the text, the attachments and the picks are empty, nothing is being sent, the model exists and its phase is not `Unavailable`. Otherwise the round button is Send.
  - **Send** acts on `ComposerValidation.message(text, attachments)`, only when that is `Ok` and no pick is still being read.
    - It calls `send(text, carried)`.
    - Text only: the field empties at once (`onDraftChange(draft.copy(text = ""))`).
    - With attachments: the bar keeps them, and the owner clears them.
  - **Under the field.**
    - `TooLong(bytes)` shows `composer_too_long(byteCount(bytes), byteCount(MAX_BYTES))` (tag `composer.tooLong`).
    - Otherwise `problem(...)`, or the last attach note (tag `composer.attachProblem`).
    - Otherwise, while the field holds the words a dictation stopped at, `voice_limit(byteCount(MAX_BYTES))` (tag `composer.voiceLimit`).
  - **While `sending` is set:** the field and `+` are disabled, and the button is a progress ring at `sending` (tag `composer.sending`, description `composer_sending`).
  - **The keyboard.** `wantsKeyboard`, "Type instead", or no recognizer: focus the field, then `model.typeInstead()`.
  - **Typing.** Text that becomes non-empty calls `dismiss()`, and `typeInstead()` while a dictation is active.
  - **A dictation.** `Complete(words)` → `sendVoice(words)`, or `send(words, [])`. `CutAtLimit(words)` puts the words in the field and opens the keyboard.
  - **Dispose** cancels the model.
  - **Tags.** The field is `composer.field`, Send is `composer.send` (description `composer_send`), `+` is `composer.attach`.

  **`AttachMenu`** ports `AttachMenu.swift`:
  - **The `+` button** (description `composer_attach`) opens a `DropdownMenu` with Photos (`composer_attach_photos`) and Files (`composer_attach_files`).
  - **Room.** `room = ShellXLink.MAX_ATTACHMENTS_PER_MESSAGE - attachments.size - picks.count`. The menu is disabled at 0.
  - **Photos** launch `PickMultipleVisualMedia(5)` with `ImageOnly`. **Files** launch `OpenMultipleDocuments()` with `arrayOf("*/*")`.
  - **The picked URIs** go to `picks.read`, in order. Each load is `reader.read(AttachmentPick(uri, kind), taken = <the attachments' names when its read starts>)`.
  - **A read's result.**
    - Success: `onAdd`, unless 5 are held already; then the note is `composer_attach_too_many`.
    - `AttachmentReadException`: the note is `AttachmentPreparer.message`.
    - Any other failure: the note is `composer_attach_pick_failed`.

  **`AttachmentStrip`** shows:
  - 56 dp tiles: a photo's thumbnail, or a file icon over its name in 9 sp, cut in the middle;
  - then one spinner tile per pick still being read;
  - an ✕ on each tile (descriptions `composer_attachment_remove(name)` and `composer_attach_cancel_loading`), with a touch target of at least 40 dp. The ✕ of an attachment is off while `locked`;
  - the whole strip at 0.6 alpha while `locked`.

  Thumbnails are decoded off the main thread (`produceState` on `Dispatchers.Default`).

  **`AttachmentPreparer.read`** runs in `withContext(io)`:
  1. Query `OpenableColumns.DISPLAY_NAME` and `SIZE`. A missing cursor or a null column means unknown.
  2. Name it. A photo is `AttachmentChecks.photoName(AttachmentChecks.photoExtension(resolver.getType(uri)), taken)`. A file takes the display name, else `uri.lastPathSegment`, else `"file"`.
  3. Call `AttachmentChecks.refuseIfTooLarge(name, size)`.
  4. Open the stream (null → `Unreadable(name)`). Read `CHUNK_BYTES` at a time, call `ensureActive()` between chunks, and throw `TooLarge(name)` as soon as the total passes `ShellXLink.MAX_ATTACHMENT_BYTES` (RF 2).
  5. `IOException` and `SecurityException` become `Unreadable(name)`, logged as `attach_file_unreadable <exception class simple name>`.
  6. Return `AttachmentChecks.checked(kind, name, bytes)`.

  **New strings** (Android wording: Android has no speech-recognition permission). In `values/strings_android.xml`:
  `<string name="voice_denied">ShellX needs microphone access to hear you.</string>`
  In `values-vi/strings_android.xml`:
  `<string name="voice_denied">ShellX cần quyền micro để nghe bạn.</string>`

- [ ] **Step 1: Write the failing tests.**

```kotlin
@RunWith(AndroidJUnit4::class)
class AttachmentPreparerTest {
    @get:Rule val temp = TemporaryFolder()
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val preparer = AttachmentPreparer(context.contentResolver, Dispatchers.Unconfined)
    private val authority = "com.shellx.test.attachments"
    @Before fun setUp() { Robolectric.setupContentProvider(TestAttachmentProvider::class.java, authority); TestAttachmentProvider.entries.clear() }
    private fun content(name: String, size: Long?, mime: String?, bytes: InputStream): String {
        TestAttachmentProvider.entries[name] = TestAttachmentProvider.Entry(name, size, mime)
        val uri = Uri.parse("content://$authority/$name"); shadowOf(context.contentResolver).registerInputStream(uri, bytes)
        return uri.toString()
    }
    @Test fun aPickedFileIsReadWholeUnderItsName() { runTest {
        val f = temp.newFile("build-output.log").apply { writeText("error: missing import\n") }
        val a = preparer.read(AttachmentPick(Uri.fromFile(f).toString(), AttachmentKind.FILE), emptyList())
        assertEquals("build-output.log", a.name); assertEquals(AttachmentKind.FILE, a.kind)
        assertArrayEquals("error: missing import\n".toByteArray(), a.data)
    } }
    @Test fun aPhotoIsNamedAfterItsTypeAndTheNamesTaken() { runTest {
        val uri = content("IMG_0001", 3, "image/png", ByteArrayInputStream(byteArrayOf(1, 2, 3)))
        val a = preparer.read(AttachmentPick(uri, AttachmentKind.IMAGE), listOf("photo-1.png"))
        assertEquals("photo-2.png", a.name); assertArrayEquals(byteArrayOf(1, 2, 3), a.data)
    } }
    @Test fun aReportedSizeOverTheLimitIsRefusedBeforeReading() { runTest {
        val untouched = object : InputStream() { override fun read(): Int = error("read") }
        val uri = content("big.mov", 10_485_761, "video/quicktime", untouched)
        val e = runCatching { preparer.read(AttachmentPick(uri, AttachmentKind.FILE), emptyList()) }.exceptionOrNull()
        assertEquals("big.mov", (e as AttachmentReadException.TooLarge).name)
    } }
    @Test fun anUnknownSizeStreamStopsJustPastTheLimit() { runTest {                       // RF 2
        var served = 0L
        val endless = object : InputStream() {
            override fun read(): Int { served++; return 0 }
            override fun read(b: ByteArray, off: Int, len: Int): Int { served += len; return len }
        }
        val uri = Uri.parse("content://com.shellx.test.nowhere/stream"); shadowOf(context.contentResolver).registerInputStream(uri, endless)
        val e = runCatching { preparer.read(AttachmentPick(uri.toString(), AttachmentKind.FILE), emptyList()) }.exceptionOrNull()
        assertEquals("stream", (e as AttachmentReadException.TooLarge).name)
        assertTrue(served <= ShellXLink.MAX_ATTACHMENT_BYTES + AttachmentPreparer.CHUNK_BYTES)
    } }
    @Test fun aMissingOrEmptyFileSaysWhichOne() { runTest {
        val gone = runCatching { preparer.read(AttachmentPick(Uri.fromFile(File(temp.root, "gone.txt")).toString(), AttachmentKind.FILE), emptyList()) }
        assertEquals("gone.txt", (gone.exceptionOrNull() as AttachmentReadException.Unreadable).name)
        val empty = runCatching { preparer.read(AttachmentPick(Uri.fromFile(temp.newFile("empty.txt")).toString(), AttachmentKind.FILE), emptyList()) }
        assertEquals("empty.txt", (empty.exceptionOrNull() as AttachmentReadException.Unreadable).name)
    } }
}
@RunWith(AndroidJUnit4::class)
class ComposerTextsTest {
    private val res = ApplicationProvider.getApplicationContext<Context>().resources
    @Test fun byteCountsReadInTheAppsLanguage() {
        assertEquals("16,384", ComposerValidation.byteCount(16_384, Locale.ENGLISH))
        assertEquals("16 384", ComposerValidation.byteCount(16_384, Locale("vi")))
    }
    @Test fun attachmentProblemsHaveTheirWords() {
        assertEquals(res.getString(R.string.composer_attach_too_many), ComposerBar.problem(ComposerValidation.TooManyAttachments, res))
        assertEquals(res.getString(R.string.composer_attach_too_large, "video.mov"), ComposerBar.problem(ComposerValidation.AttachmentTooLarge("video.mov"), res))
        assertEquals(AttachmentPreparer.message(AttachmentReadException.TooLarge("video.mov"), res), ComposerBar.problem(ComposerValidation.AttachmentTooLarge("video.mov"), res))
        assertNull(ComposerBar.problem(ComposerValidation.Ok("x"), res))
    }
    @Test fun aLongDictationShowsItsNewestWords() {            // port of testLongDictationShowsItsNewestWords
        val spoken = "Chạy test cho shellx rồi tạo PR cho branch develop"
        assertEquals(spoken, VoiceStatusView.newest(spoken))
        val shown = VoiceStatusView.newest("giữ route v1, đừng xoá. ".repeat(40) + "rồi push")
        assertTrue(shown.startsWith("…")); assertTrue(shown.endsWith("rồi push"))
        assertTrue(shown.graphemeCount() <= VoiceStatusView.SHOWN_CHARACTERS + 1); assertFalse(shown.drop(1).startsWith(" "))
    }
    @Test fun eachMicStateHasItsSymbol() {
        val symbols = listOf(VoiceInputModel.Phase.Idle, VoiceInputModel.Phase.Listening(""), VoiceInputModel.Phase.CancelArmed(""),
            VoiceInputModel.Phase.Denied(VoicePermission.MICROPHONE)).map(MicButton::symbol)
        assertEquals(4, symbols.toSet().size)
    }
}
@RunWith(AndroidJUnit4::class)
class MicButtonTest {
    @get:Rule val compose = createComposeRule()
    private var outcome: DictationOutcome? = null; private var nothing = 0
    private val mic get() = compose.onNodeWithTag("voice.mic")
    private fun show(rig: VoiceRig, model: VoiceInputModel, shown: State<Boolean> = mutableStateOf(true)) = compose.setContent {
        ShellXTheme { CompositionLocalProvider(LocalVoice provides rig.env) {
            if (shown.value) MicButton(model, R.string.voice_mic, onOutcome = { outcome = it }, onKeyboard = {}, onNothing = { nothing++ })
        } }
    }
    @Test fun holdingListensAndTheLiftSendsTheWords() {
        val rig = VoiceRig.make(); val model = rig.model(); show(rig, model)
        mic.performTouchInput { down(center) }; compose.waitUntil { rig.engine.starts.size == 1 }
        rig.engine.say("chạy test"); compose.waitUntil { model.phase == VoiceInputModel.Phase.Listening("chạy test") }
        mic.performTouchInput { up() }; compose.waitUntil { outcome != null }
        assertEquals(DictationOutcome.Complete("chạy test"), outcome)
        assertEquals(listOf(rig.engine.starts[0].run), rig.engine.finishCalls)
    }
    @Test fun dragLeftPastEightyDpArmsCancelAndTheLiftSendsNothing() {
        val rig = VoiceRig.make(); val model = rig.model(); show(rig, model)
        mic.performTouchInput { down(center) }; compose.waitUntil { rig.engine.starts.size == 1 }; rig.engine.say("bỏ đi")
        mic.performTouchInput { moveBy(Offset(-81.dp.toPx(), 0f)) }
        compose.waitUntil { model.phase == VoiceInputModel.Phase.CancelArmed("bỏ đi") }
        mic.performTouchInput { up() }; compose.waitUntil { nothing == 1 }
        assertNull(outcome); assertEquals(listOf(rig.engine.starts[0].run), rig.engine.cancelCalls)
    }
    @Test fun aHoldTakenAwayCancelsAndSendsNothing() {                                    // RF 1
        val rig = VoiceRig.make(); val model = rig.model(); show(rig, model)
        mic.performTouchInput { down(center) }; compose.waitUntil { rig.engine.starts.size == 1 }; rig.engine.say("nửa câu")
        mic.performTouchInput { cancel() }
        compose.waitUntil { rig.engine.cancelCalls.size == 1 }
        assertNull(outcome); assertEquals(VoiceInputModel.Phase.Idle, model.phase); assertNull(rig.engine.activeRun)
    }
    @Test fun leavingWhileHoldingGivesTheMicrophoneBack() {                               // RF 1
        val rig = VoiceRig.make(); val model = rig.model(); val shown = mutableStateOf(true); show(rig, model, shown)
        mic.performTouchInput { down(center) }; compose.waitUntil { rig.engine.starts.size == 1 }; rig.engine.say("đang nói")
        shown.value = false
        compose.waitUntil { rig.engine.activeRun == null }
        assertEquals(1, rig.engine.cancelCalls.size); assertNull(outcome); assertEquals(VoiceInputModel.Phase.Idle, model.phase)
        assertFalse(rig.env.activity.anyActive.value)
    }
    @Test fun swipingUpBeforeAnyWordAsksForTheKeyboard() {
        val rig = VoiceRig.make(); val model = rig.model(); show(rig, model)
        mic.performTouchInput { down(center) }; compose.waitUntil { rig.engine.starts.size == 1 }
        mic.performTouchInput { moveBy(Offset(0f, -61.dp.toPx())) }; compose.waitUntil { model.wantsKeyboard }
        mic.performTouchInput { up() }; compose.waitForIdle(); assertNull(outcome)
    }
    @Test fun talkBackTapsStartAndFinishAndCancelIsAnAction() {
        val rig = VoiceRig.make(); val model = rig.model(); show(rig, model)
        mic.performSemanticsAction(SemanticsActions.OnClick); compose.waitUntil { rig.engine.starts.size == 1 }
        rig.engine.say("một hai"); compose.waitUntil { model.phase == VoiceInputModel.Phase.Listening("một hai") }
        mic.performSemanticsAction(SemanticsActions.OnClick); compose.waitUntil { outcome != null }
        assertEquals(DictationOutcome.Complete("một hai"), outcome)
        mic.performSemanticsAction(SemanticsActions.OnClick); compose.waitUntil { rig.engine.starts.size == 2 }
        val cancelLabel = ApplicationProvider.getApplicationContext<Context>().getString(R.string.common_cancel)
        mic.performCustomAccessibilityActionWithLabel(cancelLabel); compose.waitUntil { rig.engine.cancelCalls.size == 1 }
    }
}
```

  `ComposerBarTest` hosts `ComposerBar(draft, { draft = it }, send = { t, a -> sent += t to a.size }, …)` over a `mutableStateOf(ComposerDraft())`. Each comment line is one `@Test`:

```kotlin
class ComposerBarTest {
    // aTextMessageLeavesTheFieldAtOnce: type "  chạy test  ", tap composer.send → sent == [("chạy test", 0)]; draft.text == ""
    // tooLongSaysByHowMuchAndBlocksSend: draft "a".repeat(16_385) → composer.tooLong reads
    //   composer_too_long("16,385", "16,384"); composer.send is not enabled
    // attachmentsAloneGoAndStayInTheBar: one FILE attachment, attachmentsEnabled → tap Send → sent == [("", 1)]; draft keeps it
    // sendingLocksTheBar: text "x", one attachment, sending = 0.4 → composer.sending exists; composer.field and composer.attach not enabled
    // theMicShowsOnlyWhileTheBarIsEmpty: LocalVoice = VoiceRig.make().env → voice.mic exists; draft text "x" → voice.mic gone, composer.send shown
    // aDictationStoppedAtTheLimitGoesIntoTheField: press voice.mic (down), say("giữ route v1, đừng xoá. ".repeat(700)), up →
    //   draft.text has at most 16 384 bytes and is not empty; composer.voiceLimit shown; sent empty
    // noRecognizerOpensTheKeyboard: VoiceRig.make(VoiceCapabilities.NONE), tap voice.mic (semantics) → voice.mic gone; composer.field is focused
}
```

  `ComposerRenderTest` ports the composer part of `MicButtonRenderTests.swift`. Each line is one `@Test` that calls `assertRenders(name) { … }`, with the bar at the bottom of a `Column` on `background`:
  - `voice-idle`: an empty bar with `VoiceRig.make().env`.
  - `voice-listening`: press, then `say("Chạy test cho shellx rồi tạo PR cho branch develop")`, before rendering.
  - `voice-cancel-armed`: the same, then `model.drag(-120.0, 0.0)`.
  - `voice-denied`: `microphone = false`, then press.
  - `voice-unavailable`: `VoiceCapabilities.NONE`, then press.
  - `voice-limit`: `say("giữ route v1, đừng xoá. ".repeat(700))` until `limitReached`.
  - `composer-attachments`: two attachments and no text. The first is `photo-1.png`: a 1170×2532 `Bitmap` filled `#1F2129` with 30 bars, bar 12 red, compressed to PNG. The second is `build-output.log` holding `"error: missing import\n"`.
  - `composer-sending`: text `"Sửa lỗi này giúp mình"`, both attachments, `sending = 0.4`.
  - `composer-loading`: an `AttachmentStrip` with both attachments and `loading = listOf("a", "b")`.
  - `composer-too-many`: six `log-N.txt` files.

- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.ui.composer.*' --tests 'com.shellx.app.screenshots.ComposerRenderTest'`.

  Expected: `Unresolved reference` naming `AttachmentPreparer`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test shellx-android/app/src/testDebug`, then `git commit -m "test(shellx-android): composer, hold-to-talk and attachment reading"`.
- [ ] **Step 4: Implement.**
  - Write the files in Interfaces.
  - Add `voice_denied` to both `strings_android.xml` files.
  - Run `python3 shellx-android/scripts/import-strings.py`. Expected: `import-strings: wrote …`.
- [ ] **Step 5: Run (green).** Run the same command three times. Expected: PASS, with these counts:
  - `AttachmentPreparerTest`: 5;
  - `ComposerTextsTest`: 4;
  - `MicButtonTest`: 6;
  - `ComposerBarTest`: 7;
  - `ComposerRenderTest`: 10.

  Then run `shellx-android/scripts/dev.sh screenshots record "$(mktemp -d)"` and open `voice-listening-dark-vi.png` and `composer-attachments-light-en.png`:
  - the mic is solid blue with a waveform and rings;
  - the Vietnamese words sit above the bar;
  - the photo tile shows the thumbnail.
- [ ] **Step 6: Commit with the ledger.**
  - Add row `A-e2`:
    - difference: "The mic asks only for the microphone (RECORD_AUDIO), the first time it is pressed, and its 'denied' line names only the microphone";
    - why: "Android has no separate speech-recognition permission";
    - Android: `app:voice/SystemVoicePermissions.kt`, `strings_android.xml` (`voice_denied`);
    - plan: 3E;
    - state: `differs (3E): by design`.

  Run `git add shellx-android/app/src/main docs/superpowers/ledgers/shellx-android-parity.md`, then `git commit -m "feat(shellx-android): composer with hold-to-talk, live words, photos and files"`.

---

### Task 5: Needs you: cards, status lines, the list and the sheet host

**Files:**
- Create in `app/ui/pending/`: `PendingCardView.kt`, `PendingCardStatusLine.kt`, `CommandPreview.kt`, `CutNotice.kt`, `ChoiceRow.kt`, `ByteCounter.kt`, `FullTextSheet.kt`, `PendingCardsSection.kt`, `PendingRoute.kt`, `PendingSheetState.kt`, `PendingSheetHost.kt`, `PendingListView.kt`
- Create if missing (Task 0): `app/ui/home/NeedsYouBar.kt`
- Test: `app-test/ui/pending/PendingTextsTest.kt`, `app-ui-test/ui/pending/PendingListViewTest.kt`, `app-ui-test/screenshots/PendingCardRenderTest.kt`

Reference: `ios/UI/Pending/{PendingCardView,PendingCardStatusLine,CommandPreview,CutNotice,ChoiceRow,ByteCounter,FullTextSheet,PendingCardsSection,PendingRoute,PendingSheetState,PendingSheetHost,PendingListView}.swift`, `ios/UI/Home/NeedsYouBar.swift`; `ios-tests/PendingCardRenderTests.swift`.

**Interfaces:**
- Consumes:
  - 3C: `MachinePendingItem`, `PendingKey`, `PendingItem` (`actions`, `previewText`, `previewFields`, `previewMayBeCut`), `PendingAction`, `PermissionLayout`, `DecisionStatus`, `DecisionFailure`, `DecisionCenter`, `PendingSheetModel` (`LinkNote`), `SheetPresence`, `AgentLabel`, `MachineHub`;
  - Task 0: `StatusDot`, `StatusTone`;
  - Task 2: `PlanMarkdownText`;
  - Task 4: `PrimaryButton`, `SecondaryButton`.
- Produces (`com.shellx.app.ui.pending`):

```kotlin
class PendingCardActions(val decide: (LinkDecision) -> Unit = {}, val openSheet: () -> Unit = {}, val showMore: () -> Unit = {},
                         val retry: () -> Unit = {})
@Composable fun PendingCardView(item: MachinePendingItem, status: DecisionStatus?, showsMachineName: Boolean,
                                actions: PendingCardActions = PendingCardActions(), modifier: Modifier = Modifier)
object PendingCardView {
    /** "**shellx** · Claude Code · MacBook Pro · wants to run Bash": the workspace SemiBold, the rest in `secondary`. */
    fun headline(item: MachinePendingItem, showsMachineName: Boolean, res: Resources, secondary: Color): AnnotatedString
    fun spokenHeadline(item: MachinePendingItem, showsMachineName: Boolean, res: Resources): String   // joined with ", "
    fun kindText(item: PendingItem, res: Resources): String
    @StringRes fun title(action: PendingAction): Int       // PendingAction+title of PendingCardView.swift
}
object PendingCardStatusLine {
    sealed interface Mark { data object Progress : Mark; data class Symbol(val icon: ImageVector, val tone: StatusTone) : Mark }
    data class Line(val text: String, val mark: Mark, val offersRetry: Boolean = false)
    fun line(status: DecisionStatus?, actionable: Boolean, machineName: String, linkNote: PendingSheetModel.LinkNote? = null,
             res: Resources): Line?
}
@Composable fun PendingCardStatusLine(status: DecisionStatus?, actionable: Boolean, machineName: String,
                                      linkNote: PendingSheetModel.LinkNote? = null, retry: () -> Unit = {})
enum class CommandPreviewStyle { COMMAND, PROSE, MARKDOWN }
@Composable fun CommandPreview(text: String, style: CommandPreviewStyle = CommandPreviewStyle.COMMAND, showMore: () -> Unit)
object CommandPreview { const val LINE_LIMIT = 3; const val COLLAPSED_CHARACTERS = 600; fun collapsed(text: String): Pair<String, Boolean> }
@Composable fun CutNotice()
@Composable fun ChoiceRow(selected: Boolean, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit)
@Composable fun ByteCounter(used: Int, limit: Int)                 // pending_bytes / pending_too_long in statusError past the limit
@Composable fun FullTextSheet(item: PendingItem, close: () -> Unit)
class PendingRoute(val kind: Kind, val model: PendingSheetModel) {
    enum class Kind { QUESTION, PLAN, FULL_TEXT }
    val id: PendingKey
    companion object { fun kind(item: PendingItem): Kind }      // QUESTION when actions == [Answer]; PLAN when kind EXIT_PLAN and actions != [OpenOnMac]
}
/** What a question or plan sheet shows about its decision (iPhone PendingSheetState; not 3C's core type of the same name). */
data class PendingSheetState(val status: DecisionStatus? = null, val handledElsewhere: Boolean = false, val canSend: Boolean = true,
                             val actionable: Boolean = true, val linkNote: PendingSheetModel.LinkNote? = null) {
    val shownStatus: DecisionStatus?                               // HandledElsewhere when handledElsewhere, else status
    companion object { fun of(model: PendingSheetModel): PendingSheetState }
}
/** The ModalBottomSheet over the cards: question, plan or full text by route.kind (Task 6 fills the first two). */
@Composable fun PendingSheetHost(route: PendingRoute, hub: MachineHub, center: DecisionCenter, sheets: SheetPresence?, close: () -> Unit)
fun LazyListScope.pendingCardsSection(items: List<MachinePendingItem>, status: (PendingKey) -> DecisionStatus?,
                                      showsMachineName: Boolean, actions: (MachinePendingItem) -> PendingCardActions)
object PendingCardsSection {
    /** decide and retry → center.send / center.retry in hub.scope; openSheet and showMore → PendingSheetModel(item.id, hub, center),
     *  then open(PendingRoute(kind(item.item), model)) unless model.opened is null. */
    fun actions(item: MachinePendingItem, hub: MachineHub, center: DecisionCenter, open: (PendingRoute) -> Unit): PendingCardActions
}
@Composable fun PendingListView(hub: MachineHub, center: DecisionCenter, sheets: SheetPresence?,
                                only: ((MachinePendingItem) -> Boolean)? = null, back: () -> Unit)
object PendingListView { val LEAVE_DELAY: Duration }               // 700 ms
/** The open sheet of one pending page, kept across configuration changes (viewModel(key = "pending")). */
class PendingListHolder : ViewModel() { var route: PendingRoute? }   // a Compose mutableStateOf
// com.shellx.app.ui.home (create if missing). Tag home.needsYou; description = pending_section_title(count) + the spoken headline.
@Composable fun NeedsYouBar(items: List<MachinePendingItem>, showsMachineName: Boolean, open: () -> Unit, modifier: Modifier = Modifier)
object NeedsYouBar { fun headline(item: MachinePendingItem, showsMachineName: Boolean, res: Resources, secondary: Color): AnnotatedString }
```

  Behaviour follows the Swift files:
  - **Card.**
    - The buttons are enabled when `item.actionable` and the status is null or `Failed`.
    - A permission lays out with `PermissionLayout.of(actions)`: Deny is a `SecondaryButton` in `statusError`; the others are `PrimaryButton`s; the menu items sit behind a `⋯` icon button (description `pending_more`).
    - A question has one `pending_answer` button; a plan has one `pending_review_plan` button.
    - `[OpenOnMac]` shows the laptop icon with `pending_open_on_mac`.
    - At `fontScale >= 1.3f` the buttons stack.
    - Tags: `pending.card`, `pending.allow`, `pending.deny`, `pending.more`, `pending.open`.
  - **Preview.** A permission shows it in `COMMAND` style. A plan shows `PlanMarkdownText.summary` in `MARKDOWN` style. Anything else uses `PROSE`.
  - **Status line.** `line` is `PendingCardStatusLine.swift`'s table. The colour names become tones: `StatusIdle` → `IDLE`, `StatusError` → `ERROR`. "Try again" is tagged `pending.retry`.
  - **List.**
    - It shows `center.visibleItems(only?.let { hub.pendingItems.filter(it) } ?: hub.pendingItems)`.
    - The title is `pending_list_title`. When empty, it shows `pending_list_empty` with `Icons.Outlined.CheckCircle`.
    - Once a card showed here and none is left with no sheet up, it waits `LEAVE_DELAY`, then calls `back()`.
    - The open route lives in a ViewModel holder (`PendingListHolder`), so an open sheet survives recreation.
  - **Host.**
    - It collects `hub.state`, `center.state` and `route.model.state`, then builds `PendingSheetState.of(route.model)`.
    - It closes when the status becomes `Done`. While `handledElsewhere`, it announces `pending_status_handled_elsewhere` through a polite live region.
    - It calls `sheets?.opened()` and `closed()` in a `DisposableEffect`.
    - Its `send` is `hub.scope.launch { route.model.send(decision) }`.

- [ ] **Step 1: Write the failing tests.**
  - **`PendingTextsTest`** (Robolectric). Port these, with the fixtures of `PendingCardRenderTests.swift` translated literally (`PendingKind("teleport")` for `.other("teleport")`):
    - `testStatusLinesSayDifferentThings`;
    - `testSheetLinkNotesSayWhyNothingIsSent`;
    - `testHeadlineNamesWorkspaceAgentMacAndKind`;
    - `testSheetKindFollowsTheItem`;
    - from `testLongPreviewRendersCollapsed`, the `CommandPreview.collapsed` assertions only. Build the 8 KB preview with `cutToUtf8(PendingItem.MAX_PREVIEW_BYTES)`, because there is no `truncatedPreview` on Android.

    Then add:

```kotlin
@Test fun theNeedsYouBarLeavesOutTheAgent() {
    val item = MachinePendingItem("m1", "MacBook Pro", PendingItem(requestId = "p1", kind = PendingKind.PERMISSION, agent = "claude",
        workspaceId = "ws", workspaceTitle = "shellx", toolName = "Bash", createdAtMs = 1, modes = listOf("once")), true)
    assertEquals("shellx · " + res.getString(R.string.pending_kind_permission, "Bash"), NeedsYouBar.headline(item, false, res, Color.Gray).text)
    assertEquals("shellx · MacBook Pro · " + res.getString(R.string.pending_kind_permission, "Bash"), NeedsYouBar.headline(item, true, res, Color.Gray).text)
}
```

  - **`PendingListViewTest`** (Compose, over `WorkRig`). Add items with `rig.mac.addPending(...)` and show `PendingListView(rig.hub, rig.scope.decisions, rig.scope.sheets, …)`. The test keeps `decisions.sync(hub.pendingItems)` running with `LaunchedEffect { hub.state.collect { … } }`, as 3D's signed-in root does. Each comment line is one `@Test`:

```kotlin
class PendingListViewTest {
    // allowDecidesAndTheCardGoes: a permission p1 (modes once/always/deny) in ws-shellx → tap pending.allow →
    //   rig.mac.decisions == [Decision("p1", LinkDecision.Permission(PermissionMode.ONCE))]; no pending.card left
    // aWorkspacesPageShowsOnlyItsCards: p1 in ws-shellx and p2 in ws-web, only = { it.isIn(rig.machineId, "ws-shellx") } → one card
    // theLastCardHandledSaysSoThenGoesBack: after the decision, pending_list_empty shows and back has not run;
    //   mainClock.advanceTimeBy(800) → back ran once; PendingListView.LEAVE_DELAY == 700.milliseconds
    // answerOpensTheQuestionSheetAndShowMoreTheFullText: a question q1 → tap pending.open → the sheet shows q1's prompt;
    //   close; a permission whose preview has 4 lines → tap pending.showMore → pending_full_text_title or the tool name shows
    // aSheetClosesOnceItsDecisionIsDone: open q1, send through the sheet's model (route.model.send(Question(["Postgres"])))
    //   → the sheet's prompt is gone and the card too
}
```

  - **`PendingCardRenderTest`.** Port `PendingCardRenderTests.swift`'s card and full-text renders. That makes these names, each through `assertRenders`, with the cards in a `LazyColumn` on `background` and 16 dp padding:
    - `pending-kinds`;
    - `pending-kinds-more`;
    - `pending-state-sending`, `pending-state-offline`, `pending-state-no-answer`, `pending-state-rejected`, `pending-state-handled-elsewhere`, `pending-state-reconnecting`;
    - `pending-ax3` (in `LargeText`);
    - `pending-long-preview`;
    - `pending-full-edit`, `pending-full-cut`.

    Add `needs-you-bar`: a `NeedsYouBar` with the permission and the question items, near the top.
- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.ui.pending.Pending*' --tests 'com.shellx.app.screenshots.PendingCardRenderTest'`.

  Expected: `Unresolved reference` naming `PendingCardStatusLine`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test shellx-android/app/src/testDebug`, then `git commit -m "test(shellx-android): Needs-you cards, status lines and the list"`.
- [ ] **Step 4: Implement.** Write the files in Interfaces. The host shows only `FullTextSheet` until Task 6, and for the other kinds a `Text` with the item's prompt or plan. Task 6 replaces those two branches.
- [ ] **Step 5: Run (green).** Expected: PASS, with these counts:
  - `PendingTextsTest`: 6;
  - `PendingListViewTest`: 5;
  - `PendingCardRenderTest`: 13.
- [ ] **Step 6: Commit with the ledger.** Set row `6.2-19` to `done (3E)`. Then run `git add shellx-android/app/src/main docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): Needs-you list, cards and sheet host"`.

---

### Task 6: The question and plan sheets

**Files:**
- Create: `app/ui/pending/QuestionAnswerSheet.kt`, `app/ui/pending/PlanReviewSheet.kt`
- Modify: `app/ui/pending/PendingSheetHost.kt` (the two branches)
- Test: `app-test/ui/pending/SheetRulesTest.kt`, `app-ui-test/ui/pending/QuestionAnswerSheetTest.kt`, `app-ui-test/ui/pending/PlanReviewSheetTest.kt`, `app-ui-test/screenshots/PendingSheetRenderTest.kt`

Reference: `ios/UI/Pending/{QuestionAnswerSheet,PlanReviewSheet}.swift`; `ios-tests/PendingCardRenderTests.swift` (the sheets); `ios-tests/MicButtonRenderTests.swift` (the sheets' mics).

**Interfaces:**
- Consumes:
  - 3C: `QuestionDraft`, `PendingQuestion.optionMatching`, `DecisionCenter.MAX_FEEDBACK_BYTES`, `ExitPlanMode`, `LinkDecision`;
  - Task 4: `MicButton`, `VoiceStatusView`;
  - Task 5: everything.
- Produces (`com.shellx.app.ui.pending`):

```kotlin
/** One page per question: its options as a checklist, "Other…" with a field, "Answer by voice", Back / Next / Send. The
 *  initial-state parameters let render tests start anywhere (as the Swift init). */
@Composable fun QuestionAnswerSheet(item: MachinePendingItem, state: PendingSheetState, send: (LinkDecision) -> Unit, close: () -> Unit,
    draft: QuestionDraft? = null, page: Int = 0, typing: Set<String> = emptySet(), freeText: Map<String, String> = emptyMap(),
    voice: VoiceInputModel? = null, unmatched: Set<String> = emptySet())
object QuestionAnswerSheet {
    fun tooLong(draft: QuestionDraft, typed: Map<String, String>): Boolean        // the Swift body
    /** Saves each question's picked labels and typed text; restores by replaying toggle / setFreeText on QuestionDraft(questions). */
    fun draftSaver(questions: List<PendingQuestion>): Saver<QuestionDraft, Any>
}
@Composable fun PlanReviewSheet(item: MachinePendingItem, state: PendingSheetState, send: (LinkDecision) -> Unit, close: () -> Unit,
    revising: Boolean = false, feedback: String = "", voice: VoiceInputModel? = null)
object PlanReviewSheet { @StringRes fun title(mode: ExitPlanMode): Int }   // AUTO_ACCEPT → pending_plan_auto_accept; ULTRAPLAN →
                                                                          // pending_plan_ultraplan; else pending_plan_approve
```

  Both sheets keep their edits in `rememberSaveable` (RF 3):
  - the question sheet keeps `page`, `typing`, `typed`, `unmatched` and the draft (`draftSaver`);
  - the plan sheet keeps `revising` and `feedback`.

  When `voice` is null, a sheet makes its own model with `LocalVoice.current?.service?.makeModel(…)`, with `QuestionDraft.MAX_ANSWER_BYTES` or `DecisionCenter.MAX_FEEDBACK_BYTES`. A sheet cancels its mic, in `LocalVoice.current.scope`:
  - when it leaves composition;
  - when it can no longer edit (the question sheet) or is handled elsewhere (the plan sheet);
  - when a field takes focus (`typeInstead()`).

  The spoken answer is the Swift `answer(_:bySaying:)`:
  - `optionMatching(words)` picks the option, clears the typed text, and announces the label;
  - otherwise the words become the "Other…" text, the field opens, the question is marked unmatched, and `pending_question_voice_no_match` is announced.

  Announcements are polite live regions. The mic and its words sit in the bottom bar, outside the list. "Close" is the top bar's navigation action (`common_close`, tag `pending.close`). The other tags are as the Swift: `pending.option`, `pending.other`, `pending.otherField`, `pending.next`, `pending.send`, `pending.approve`, `pending.otherModes`, `pending.revise`, `pending.reject`, `pending.feedback`, `pending.sendFeedback`, `pending.voice.noMatch`.

- [ ] **Step 1: Write the failing tests.**
  - **`SheetRulesTest`.**
    - Port `testQuestionSheetBlocksAnswersOverTheLimit`.
    - `aDraftSurvivesItsSaver`: picks Postgres; free text `"Chỉ lint"` on `checks`; save then restore → the same `decision`.
    - `eachApprovalModeHasItsTitle`: `title(AUTO_ACCEPT)`, `title(ULTRAPLAN)` and `title(MANUAL)` are the three named strings; `title(ExitPlanMode("x"))` is `pending_plan_approve`.
  - **`QuestionAnswerSheetTest`** uses the two-question item of `PendingCardRenderTests.swift`:
    - `db`: "Postgres" / "SQLite", single;
    - `checks`: "Lint" / "Unit tests" / "UI tests", multi.

    Each comment line is one `@Test`:

```kotlin
class QuestionAnswerSheetTest {
    // picksGoOutAsTheirLabels: tap Postgres, pending.next, Lint, Unit tests, pending.send → sent == [Question(["Postgres", "Lint, Unit tests"])]
    // nextNeedsAnAnswer: on page 1, pending.next is not enabled until an option is tapped
    // anOtherAnswerIsSentAsTyped: page 2 (Next after Postgres), tap pending.other, type "Chỉ chạy lint" →
    //   sent == [Question(["Postgres", "Chỉ chạy lint"])]
    // aSpokenAnswerPicksTheOptionItNames: VoiceRig.make(), voice = rig.model(QuestionDraft.MAX_ANSWER_BYTES); press the mic,
    //   say("postgres"), lift → Postgres is selected (its checkmark row has the selected semantics); nothing sent
    // aSpokenAnswerWithoutAMatchBecomesTheOtherAnswer: say("Dùng MongoDB đi") → pending.otherField holds it; pending.voice.noMatch shows
    // typedAnswersSurviveRecreation (RF 3): StateRestorationTester; page 2, type "Chỉ lint" in Other → emulateSavedInstanceStateRestore()
    //   → still page 2, the field holds "Chỉ lint"; Postgres still selected
    // handledElsewhereOffersOnlyClose: state = PendingSheetState(handledElsewhere = true, canSend = false) → common_close button
    //   shown, pending.send absent; pending_status_handled_elsewhere shown
}
```

  - **`PlanReviewSheetTest`.** The plan item has `modes = ["manual", "auto_accept", "ultraplan", "deny"]`. Each comment line is one `@Test`:

```kotlin
class PlanReviewSheetTest {
    // approveSendsManual: tap pending.approve → sent == [ExitPlan(MANUAL, null)]
    // otherModesSitInTheMenu: tap pending.otherModes, then pending_plan_auto_accept → sent == [ExitPlan(AUTO_ACCEPT, null)]
    // reviseNeedsFeedbackWithinTheLimit: tap pending.revise → pending.sendFeedback not enabled; type "Tách bước 2 ra." → enabled →
    //   tap → sent == [ExitPlan(DENY, "Tách bước 2 ra.")]; "x".repeat(4_097) → not enabled and the counter reads
    //   pending_too_long(4097, 4096)
    // feedbackSurvivesRecreation (RF 3): StateRestorationTester; revise, type "Giữ route v1" → restore → revising, same text
    // dictationAddsToTheFeedback: revising with feedback "Giữ route v1", the mic: say("đừng xoá"), lift →
    //   field == "Giữ route v1 đừng xoá"; nothing sent
    // rejectSendsDeny: tap pending.reject → sent == [ExitPlan(DENY, null)]
}
```

  - **`PendingSheetRenderTest`.** Port the sheet renders of `PendingCardRenderTests.swift`. Each sheet's content is rendered directly, not inside a `ModalBottomSheet`, on `surfaceContainer`:
    - `pending-question`;
    - `pending-question-other`;
    - `pending-question-handled`;
    - `pending-question-reconnecting`;
    - `pending-question-offline`;
    - `pending-question-too-long`;
    - `pending-question-choices-too-long`;
    - `pending-plan`;
    - `pending-plan-revise-too-long`;
    - `pending-plan-handled`;
    - `pending-plan-needs-pairing`;
    - `pending-plan-missing`.

    Add the three mic renders of `MicButtonRenderTests.swift`, with a `VoiceRig`:
    - `pending-question-voice-no-match`;
    - `pending-question-voice-listening`;
    - `pending-plan-voice`.
- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.ui.pending.*Sheet*' --tests 'com.shellx.app.ui.pending.SheetRulesTest' --tests 'com.shellx.app.screenshots.PendingSheetRenderTest'`.

  Expected: `Unresolved reference` naming `QuestionAnswerSheet`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test shellx-android/app/src/testDebug`, then `git commit -m "test(shellx-android): question and plan sheets"`.
- [ ] **Step 4: Implement** both sheets, and the two branches of `PendingSheetHost`.
- [ ] **Step 5: Run (green).** Expected: PASS, with these counts:
  - `SheetRulesTest`: 3;
  - `QuestionAnswerSheetTest`: 7;
  - `PlanReviewSheetTest`: 6;
  - `PendingSheetRenderTest`: 15.
- [ ] **Step 6: Commit with the ledger.** Set row `6.1-11` to `done (3E)`. Then run `git add shellx-android/app/src/main docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): question sheet with voice answers and plan review sheet"`.

---

### Task 7: The agent screen

**Files:**
- Create in `app/ui/agent/`: `AgentScreen.kt` (with `AgentScreenActions`, `AgentNotice`, `RemoveFromPhoneButton`), `AgentView.kt` (with `AgentScreenHolder`), `AgentHeader.kt`, `ChatEntryRow.kt`, `NewMessagesButton.kt`, `StopButton.kt`
- Create if missing (Task 0):
  - `app/ui/theme/AgentStateStyle.kt` (with `StatusTone`);
  - `StatusDot` in `app/ui/theme/MachineStateStyle.kt`;
  - `app/ui/workspaces/WorkspaceFeedback.kt`;
  - `app/ui/workspaces/WorkspaceListActions.kt` (`canClose`, `closeAgent`).
- Test: `app-test/ui/agent/AgentTextsTest.kt`, `app-ui-test/ui/agent/AgentScreenTest.kt`, `app-ui-test/ui/agent/AgentViewTest.kt`, `app-ui-test/screenshots/AgentRenderTest.kt`

Reference: `ios/UI/Agent/*.swift`; `ios/UI/Theme/{AgentStateStyle,MachineStateStyle}.swift`; `ios/UI/Workspaces/WorkspaceFeedback.swift` and the "Closing an agent" part of `WorkspaceListView.swift`; `ios-tests/AgentRenderTests.swift`.

**Interfaces:**
- Consumes:
  - 3C: `AgentThreadModel` (getters, `run`, `close`, `save`, `send`, `stop`, `loadOlder`, `retry`, `EmptyState`, `Older`), `ChatEntry`, `ChatFollow`, `AgentSendResult`, `ComposerDraft`, `AgentStatusRow`, `SessionName`, `AgentLabel`, `GoneRemovalStore`, `WorkspaceCommandResult`;
  - Tasks 2, 4, 5;
  - Task 0: `SignedInScope`;
  - Task 12: `WorkRoutes.pendingIn`. Until Task 12, AgentView builds that route string inline as `"pending?machineId=$m&workspaceId=$w"` with `Uri.encode`; Task 12 switches it to `WorkRoutes`.
- Produces (`com.shellx.app.ui.agent`):

```kotlin
data class AgentNotice(val text: String, val id: String = UUID.randomUUID().toString())     // iPhone AgentScreen.Notice
class AgentScreenActions(val send: (String, List<OutgoingAttachment>) -> Unit = { _, _ -> }, val sendVoice: (String) -> Unit = {},
    val stop: () -> Unit = {}, val forceStop: () -> Unit = {}, val loadOlder: () -> Unit = {}, val retry: () -> Unit = {},
    val seeAllPending: () -> Unit = {}, val closeAgent: () -> Unit = {}, val removeFromPhone: () -> Unit = {})
@Composable fun AgentScreen(ref: SessionRef, place: String, row: () -> AgentStatusRow?, gone: Boolean, offline: Boolean,
    pending: List<MachinePendingItem>, showsMachineName: Boolean, entries: List<ChatEntry>, emptyState: AgentThreadModel.EmptyState?,
    machineName: String, older: AgentThreadModel.Older, loadingOlder: Boolean, canStop: Boolean, notice: AgentNotice?,
    draft: ComposerDraft, onDraftChange: (ComposerDraft) -> Unit, embedded: Boolean = false, attachmentsEnabled: Boolean = false,
    sending: Double? = null, closeAgentName: String? = null, canRemoveFromPhone: Boolean = false,
    actions: AgentScreenActions = AgentScreenActions(), back: () -> Unit = {})
@Composable fun RemoveFromPhoneButton(remove: () -> Unit)        // tag agent.removeFromPhone, at least 48 dp tall
@Composable fun AgentHeader(place: String, row: AgentStatusRow?, gone: Boolean, offline: Boolean)
object AgentHeader { data class Status(val text: String?, val tone: StatusTone?); fun status(row: AgentStatusRow?, gone: Boolean, offline: Boolean, res: Resources): Status }
@Composable fun ChatEntryRow(entry: ChatEntry, agent: String, modifier: Modifier = Modifier, initiallyExpanded: Boolean = false)
object ChatEntryRow { fun accessibilityText(entry: ChatEntry, agent: String, res: Resources): String }
@Composable fun NewMessagesButton(action: () -> Unit)            // tag agent.newMessages
/** "Stop" (statusError): a tap stops; a long press opens a menu with "Force Stop…"; "Force Stop…" is also a TalkBack action. */
@Composable fun StopButton(stop: () -> Unit, forceStop: () -> Unit)   // tag agent.stop
object StopButton { fun text(outcome: ChatInterruptOutcome?, offline: Boolean, machineName: String, res: Resources): String }
@Composable fun AgentView(scope: SignedInScope, ref: SessionRef, open: (String) -> Unit, back: () -> Unit, embedded: Boolean = false)
object AgentView {
    val NOTICE_DURATION: Duration                                  // 4 s
    fun text(result: AgentSendResult, ref: SessionRef, machineName: String, res: Resources): String?    // the Swift table
    fun removable(model: AgentThreadModel, embedded: Boolean): MachineSession?                          // embedded → null, else ghost
    /** With picks: draft.sendStarted(); without: the draft unchanged. */
    fun beforeSend(draft: ComposerDraft, picked: List<OutgoingAttachment>): ComposerDraft
    /** Without picks: the text back when result.keepsDraft and the field is still empty; with picks: draft.sendEnded(keepsDraft). */
    fun afterSend(draft: ComposerDraft, text: String, picked: List<OutgoingAttachment>, result: AgentSendResult): ComposerDraft
}
/** One agent screen's model and composer across configuration changes (3C: close() from onCleared). */
class AgentScreenHolder(val model: AgentThreadModel) : ViewModel() { var draft: ComposerDraft; override fun onCleared() }
// com.shellx.app.ui.workspaces, create if missing (ports of WorkspaceFeedback.swift and WorkspaceListView.swift's close part)
enum class WorkspaceCommand { CREATE, RENAME, CLOSE, CLOSE_AGENT, CLOSE_TAB }
enum class WorkspaceAlert(@StringRes val message: Int) { OFFLINE(…), REFUSED_CLOSE(…), REFUSED_CONTROL(…), REFUSED_CLOSE_AGENT(…),
    AGENT_NOT_CLOSABLE(…), REFUSED_CLOSE_TAB(…), TAB_NOT_CLOSABLE(…), FAILED(…), UNKNOWN(…) }            // workspaces_alert_*
sealed interface WorkspaceFeedback { data object None : WorkspaceFeedback; data class Open(val ref: WorkspaceRef) : WorkspaceFeedback
    data object Refresh : WorkspaceFeedback; data class Alert(val alert: WorkspaceAlert) : WorkspaceFeedback
    companion object { fun of(result: WorkspaceCommandResult, command: WorkspaceCommand, machineId: String): WorkspaceFeedback } }
@Composable fun WorkspaceAlertDialog(alert: WorkspaceAlert?, dismiss: () -> Unit)      // message + common_ok
@Composable fun AgentCloseConfirmation(name: String?, close: () -> Unit, dismiss: () -> Unit)   // agent_close_title(name),
                                                                    // agent_close_confirm, agent_close (statusError), common_cancel
object WorkspaceListActions {   // main-confined; a close already on its way sends nothing (returns null)
    fun canClose(session: MachineSession, hub: MachineHub): Boolean
    fun closeAgent(ref: SessionRef, hub: MachineHub, alert: (WorkspaceAlert) -> Unit): Deferred<WorkspaceFeedback>?   // in hub.scope
}
// com.shellx.app.ui.theme, create if missing
enum class StatusTone { DONE, ERROR, IDLE, NEEDS_YOU, RUNNING }
@Composable fun StatusTone.color(): Color                        // ShellXTheme.colors.statusDone … statusRunning
@Composable fun StatusDot(color: Color)                          // 8 dp × fontScale, hidden from TalkBack
class AgentStateStyle(val text: String?, val shortText: String?, val tone: StatusTone?) {
    companion object {
        fun of(row: AgentStatusRow, res: Resources): AgentStateStyle      // AgentStateStyle.swift's table
        /** Under 60 s: seconds; else hours and minutes (at most two units, minutes rounded down), wide, with android.icu
         *  MeasureFormat in `locale`. */
        fun elapsedText(elapsed: Duration, locale: Locale): String
    }
}
```

  **`AgentScreen`** ports `AgentScreen.swift`:
  - **Standalone top bar.**
    - Title: `ref.workspaceTitle`. A back arrow.
    - `StopButton` while `canStop`.
    - `⋮` (tag `agent.menu`, description `agent_menu`) while it holds something:
      - `agent_close_menu`, in red, disabled while offline. It opens `AgentCloseConfirmation(closeAgentName)`.
      - `agent_remove_from_phone`, in red, at once.
  - **Embedded** (a workspace pane): no top bar. `StopButton` sits at the end of the header; there is no `⋮` and no Remove.
  - **Top block.**
    - `AgentHeader`, recomputed every second from `row()`. It is one line when place and state fit, else two (`FlowRow`).
    - Then `RemoveFromPhoneButton` (standalone and `canRemoveFromPhone`).
    - Then `NeedsYouBar(pending)`, calling `seeAllPending`.
  - **Chat.**
    - A `LazyColumn` of `ChatEntryRow`s keyed by entry id, with 12 dp spacing and 16 dp side padding.
    - On top: the older row, by `older`:
      - `LOADABLE`: a spinner that calls `loadOlder` when it scrolls into view (tag `agent.loadOlder`). The first entry is kept as the anchor: when `loadingOlder` goes false, scroll back to that anchor.
      - `FAILED`: `agent_older_failed` with `pending_status_retry`.
      - `ONLY_ON_MAC`: `agent_older_on_mac`.
    - When there are no entries, the empty row, by `emptyState`. The tags are `agent.loading`, `agent.empty`, `agent.empty.offline`, `agent.empty.failed`, `agent.empty.gone`.
    - The bottom is an item keyed `"bottom"`. Its visibility (`layoutInfo.visibleItemsInfo`) drives 3C's `ChatFollow.bottomVisible`.
    - When the last entry's id changes and `follow.newest(id)` says so, scroll to the bottom. `follow.hasUnseen` shows `NewMessagesButton`, which jumps to the bottom.
  - **Bottom.** The notice capsule (tag `agent.notice`, polite live region), over the `ComposerBar(draft, …, send = actions.send, sendVoice = actions.sendVoice)`.
  - **Force Stop** confirms with `agent_force_stop_title(agent, ref.workspaceTitle)`, `agent_force_stop_message`, `agent_force_stop` (red) and `common_cancel`.

  **`ChatEntryRow`** ports `ChatEntryRow.swift`, kind by kind:
  - **Mine** (USER + PROSE): a `bubbleMine` bubble on the right, with corners 14 / 14 / 4 / 14 and 40 dp of leading space.
  - **Agent prose:** `PlanMarkdownText`. Another role's prose is drawn in `onSurfaceVariant`.
  - **THOUGHT:** a 48 dp row with `Icons.Outlined.Psychology` and `agent_thought`, collapsed until tapped (tag `agent.entry.thought`).
  - **TOOL_USE:** `Icons.Outlined.Build`, then the tool name in SemiBold, then the text in monospace on one line until tapped (tag `agent.entry.tool`, `stateDescription` `agent_tool_expand_hint` while collapsed).
  - **STATUS:** centred, small, `onSurfaceVariant`.
  - **Other kinds:** small and `onSurfaceVariant`.
  - **Cut** (`truncated == true`): `agent_cut` as a caption under the entry (tag `agent.entry.cut`), hidden from TalkBack. The marker is part of `accessibilityText`, which each entry's single semantics node carries.

  **`AgentView`** ports `AgentView.swift`:
  - **The holder.** `viewModel(key = "agent/${ref.machineId}/${ref.sessionId}") { AgentScreenHolder(scope.agentThread(ref)) }`.
  - **Collected state.** `model.state`, `hub.state` and `decisions.state`.
  - **Running.** `model.run()` runs while STARTED. `model.save()` runs at `ON_STOP` and when the view leaves composition.
  - **Gone sessions.** `model.ghost` not null → `scope.goneRemovals.noteGone(it)`.
  - **Notices** clear after `NOTICE_DURATION`.
  - **Send.**
    1. `holder.draft = beforeSend(…)`.
    2. In `hub.scope`: `model.send(text, picked, viaVoice)`.
    3. `holder.draft = afterSend(…)`.
    4. Show `text(result, …)`.
  - **Stop** → `StopButton.text(model.stop(hard), model.offline, model.machineName, res)`, in `hub.scope`.
  - **Close Agent** → `WorkspaceListActions.closeAgent(model.ref, hub) { alert = it }`. The alert shows in `WorkspaceAlertDialog`.
  - **Remove from This Phone** → `scope.goneRemovals.remove(ghost)`, then `back()`.
  - **The "Needs you" bar** → `open("pending?machineId=…&workspaceId=…")` for the session's workspace.
  - **The `AgentScreen` values:**
    - `place` = `"${AgentLabel.of(ref.agent).text} · ${session?.machineName ?: model.machineName}"`;
    - `pending` = `decisions.visibleItems(model.pendingHere)`;
    - `showsMachineName` = `hub.machines.size > 1`;
    - `attachmentsEnabled` = `hub.acceptsAttachments(ref.machineId) || draft.attachments.isNotEmpty()`;
    - `sending` = `if (draft.isSending) model.uploadProgress ?: 0.0 else null`;
    - `closeAgentName` = `SessionName.base(session.session)`, when not embedded and `WorkspaceListActions.canClose(session, hub)`;
    - `canRemoveFromPhone` = `removable(model, embedded) != null`.

- [ ] **Step 1: Write the failing tests.**
  - **`AgentTextsTest`** (Robolectric).
    - Port `testEverySendAndStopResultHasItsWords`. The Swift result list becomes `listOf(Refused(TooLong(16_385)), Sent(SUBMITTED), Sent(BUSY), Sent(NOT_FOUND), Sent(FAILED), Offline, NoAnswer)`, and `.other("x")` becomes `ChatSendOutcome("x")`.
    - Port `testHeaderSaysTheState`, with `AgentStateStyle.elapsedText(240.seconds, Locale.ENGLISH)`.
    - Add these:

```kotlin
@Test fun theCutMarkerIsHeardOncePerEntry() {
    val marker = res.getString(R.string.agent_cut); assertTrue(marker.startsWith("…"))
    for ((role, kind) in listOf(USER to PROSE, AGENT to PROSE, SYSTEM to PROSE, AGENT to THOUGHT, AGENT to TOOL_USE, SYSTEM to STATUS,
            AGENT to ChatEntryKind("x"))) {
        val label = ChatEntryRow.accessibilityText(ChatEntry("e4", 1, 4, role, kind, "abc", truncated = true, toolName = "Bash", tsMs = 1), "Claude Code", res)
        assertEquals("$role $kind: $label", 1, label.split(marker).size - 1)
    }
    assertFalse(marker in ChatEntryRow.accessibilityText(ChatEntry("e5", 1, 5, AGENT, PROSE, "abc", tsMs = 1), "Claude Code", res))
}
@Test fun aSendKeepsOrClearsTheDraftAsTheResultSays() {
    val photo = OutgoingAttachment(kind = AttachmentKind.IMAGE, name = "photo-1.jpg", data = byteArrayOf(1))
    val empty = ComposerDraft()
    assertEquals("chạy test", AgentView.afterSend(empty, "chạy test", emptyList(), AgentSendResult.Offline).text)        // keeps
    assertEquals("", AgentView.afterSend(empty, "chạy test", emptyList(), AgentSendResult.Sent(ChatSendOutcome.SUBMITTED)).text)
    assertEquals("gõ lại", AgentView.afterSend(empty.copy(text = "gõ lại"), "chạy test", emptyList(), AgentSendResult.Offline).text)
    val held = AgentView.beforeSend(empty.copy(attachments = listOf(photo)), listOf(photo)); assertTrue(held.isSending)
    assertTrue(AgentView.afterSend(held, "", listOf(photo), AgentSendResult.Sent(ChatSendOutcome.SUBMITTED)).attachments.isEmpty())
    assertEquals(listOf(photo), AgentView.afterSend(held, "", listOf(photo), AgentSendResult.NotSent).attachments)
}
```

  - **`AgentScreenTest`** (Compose, plain values; the fixtures of `AgentRenderTests.swift`). Each comment line is one `@Test`:

```kotlin
class AgentScreenTest {
    // aCutEntryShowsTheMarkerInEveryKind: one truncated entry per kind → agent.entry.cut count == 7; the same entries whole → 0
    // aThoughtStartsCollapsedAndOpensOnTap: 12-line thought → collapsed height >= 48 dp and < 64 dp; after a tap, > collapsed + 100 dp
    // aToolCallStaysOnOneLineUntilTapped: 600 x's + 60 lines → collapsed < 80 dp; after a tap > 5 × collapsed
    // aLongCodeBlockWrapsWithinTheScreen: the Swift testLongCodeBlockWraps entry → its width <= 393 dp, its height > 600 dp
    // newEntriesAreFollowedOnlyAtTheBottom: 40 entries; scroll to the first → add entry 41 → agent.newMessages shows; tap it →
    //   it goes and entry 41 is displayed; at the bottom, entry 42 → no agent.newMessages
    // theTopAsksForOlderEntries: older = LOADABLE, 3 entries → loadOlder called once
    // stopTapsAndForceStopAsksFirst: canStop → tap agent.stop → stop once; long-press agent.stop → agent_force_stop_menu →
    //   dialog agent_force_stop_title("Claude Code", "shellx") → agent_force_stop → forceStop once
    // closeAndRemoveSitWhereTheySay: closeAgentName "claude 12:00", canRemoveFromPhone → agent.menu → agent_close_menu → dialog
    //   agent_close_title("claude 12:00") → agent_close → closeAgent once; agent.removeFromPhone is >= 48 dp tall → tap →
    //   removeFromPhone once; embedded = true → no agent.menu, no agent.removeFromPhone
}
```

  - **`AgentViewTest`** (Compose over `WorkRig`). The view is `AgentView(rig.scope, SessionRef(rig.machineId, "s1", "claude", "shellx-ios"), open = { opened += it }, back = { backs++ })`. Each comment line is one `@Test`:

```kotlin
class AgentViewTest {
    // aSentMessageSaysSentForFourSeconds: type "chạy test", tap composer.send → rig.mac.sentTexts == [SentText("s1", "chạy test")];
    //   agent.notice reads agent_sent; mainClock.advanceTimeBy(4_100) → agent.notice gone
    // theDraftLivesInTheScreenHolder (RF 3): type "đang gõ"; hide the AgentView (a state flag), show it again in the same
    //   ViewModelStoreOwner → composer.field still holds "đang gõ"
    // closeAgentFromTheMenuReachesTheMac: agent.menu → agent_close_menu → agent_close → eventually rig.mac.agentCloses == ["s1"]
    // aSessionTheMacLostCanBeRemovedFromThisPhone: rig.mac.setSendOutcome(ChatSendOutcome.NOT_FOUND); send "x" →
    //   agent.removeFromPhone shows; tap → rig.scope.goneRemovals.removals.hides(<s1's MachineSession>); backs == 1
    // theWorkspacesRequestsOpenTheirOwnPage: rig.mac.addPending(a permission in ws-shellx) → tap home.needsYou →
    //   opened == ["pending?machineId=${rig.machineId}&workspaceId=ws-shellx"] (encoded)
}
```

  - **`AgentRenderTest`.** Port every render of `AgentRenderTests.swift`, with the same fixtures, nowMs `1_700_000_000_000`, and `ref` `SessionRef("m1", "s1", "claude", "shellx")`:
    - `agent-kinds`, with the permission pending item and the notice `agent_stop_sent`;
    - `agent-cut`, `agent-code`, `agent-thought`;
    - `agent-500`: 500 entries of `"ệ".repeat(1_365) + "a"`, with older `ONLY_ON_MAC`;
    - `agent-empty`, `agent-loading`, `agent-offline`, `agent-offline-empty`, `agent-failed`;
    - `agent-gone`, `agent-gone-empty`, `agent-gone-removable`, `agent-gone-removable-empty`;
    - `agent-older-failed`;
    - `agent-ax3` and `agent-gone-removable-ax3`, both in `LargeText`;
    - `agent-gone-pane` (embedded);
    - `agent-new-messages`.

    That is 19 renders.
- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.ui.agent.*' --tests 'com.shellx.app.screenshots.AgentRenderTest'`.

  Expected: `Unresolved reference` naming `AgentView`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test shellx-android/app/src/testDebug`, then `git commit -m "test(shellx-android): agent screen, its words and its wiring"`.
- [ ] **Step 4: Implement** the files in Interfaces, and the create-if-missing pieces Task 0 found missing.
- [ ] **Step 5: Run (green).** Run three times. Expected: PASS, with these counts:
  - `AgentTextsTest`: 4;
  - `AgentScreenTest`: 8;
  - `AgentViewTest`: 5;
  - `AgentRenderTest`: 19.
- [ ] **Step 6: Commit with the ledger.** Set rows `6.1-10`, `6.1-12` (the composer, now fed upload progress by the agent screen) and `6.2-18` to `done (3E)`. Then run `git add shellx-android/app/src/main docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): agent chat screen with stop, close, older messages and new-message follow"`.

---

### Task 8: The workspace screen

**Files:**
- Create in `app/ui/workspaces/`: `WorkspaceScreen.kt` (with `WorkspaceScreenActions`, `WorkspaceMenuItem`, `PaneContent`, `WorkspaceWaitingView`, `WorkspaceMissingView`), `WorkspaceView.kt` (with `WorkspaceScreenHolder`), `PaneChips.kt`, `ShellPanePlaceholder.kt`
- Create if missing (Task 0):
  - `WorkspaceListActions.canCloseTab` and `closeTab`, in the file that holds `WorkspaceListActions`;
  - `app/ui/workspaces/WorkspaceRenameSheet.kt`;
  - `app/ui/workspaces/ListNotice.kt` (`ListNotice`, `NoticeCapsule`);
  - `app/ui/components/WaitingBorder.kt`.
- Test: `app-test/ui/workspaces/WorkspaceTextsTest.kt`, `app-test/ui/workspaces/WorkspaceActionsTest.kt`, `app-ui-test/ui/workspaces/WorkspaceScreenTest.kt`, `app-ui-test/ui/workspaces/WorkspaceViewTest.kt`, `app-ui-test/screenshots/WorkspaceRenderTest.kt`

Reference:
- `ios/UI/Workspaces/{WorkspaceScreen,WorkspaceView,PaneChips,ShellPanePlaceholder,ListNotice,WorkspaceRenameSheet}.swift`;
- the "Closing a tab" part of `WorkspaceListView.swift`;
- `ios/UI/Components/WaitingBorder.swift`;
- `ios-tests/{WorkspaceViewTests,WorkspaceRenderTests,WorkspaceLiveRenderTests}.swift`, `ios-tests/Support/WorkspaceRig.swift`.

**Interfaces:**
- Consumes:
  - 3C: `WorkspaceScreenModel` (`phase`, `selectedTerminalId`, `shownPaneClosed`, `lastTabClosedHere`, `workspace`, `panes`, `canControl`, `select`, `closesHere`, `keeps`, `run`, `defaultTerminal`), `WorkspacePane`, `WorkspaceRef`, `MachineHub` (`renameWorkspace`, `closeWorkspace`, `closeTerminal`, `refreshWorkspaces`, `markSeen`, `supportsTerminalClose`);
  - Task 3: `LocalVoice`, `MicActivity`;
  - Task 7: `AgentView`, `AgentScreen`, `AgentNotice`, `WorkspaceFeedback`, `WorkspaceAlert`, `WorkspaceAlertDialog`, `AgentStateStyle`, `StatusDot`.
- Produces (`com.shellx.app.ui.workspaces`). These are the names plan 3G plugs into:

```kotlin
class WorkspaceScreenActions(val select: (String) -> Unit = {}, val rename: (String) -> Unit = {}, val close: () -> Unit = {},
                             val closeTab: (String) -> Unit = {}) {
    companion object {
        /** iPhone WorkspaceScreenActions.make: each command runs in scope.hub.scope; done gets its Deferred (tests wait on it). */
        fun make(scope: SignedInScope, model: WorkspaceScreenModel, alert: (WorkspaceAlert) -> Unit, closing: () -> Unit = {},
                 done: (Deferred<WorkspaceFeedback>) -> Unit = {}): WorkspaceScreenActions
    }
}
enum class WorkspaceMenuItem(@StringRes val title: Int) {
    RENAME(R.string.workspace_menu_rename), CLOSE_TAB(R.string.terminal_close_menu), CLOSE_WORKSPACE(R.string.workspace_menu_close);
    val isDestructive: Boolean                                     // every item but RENAME
    companion object { fun items(canCloseTab: Boolean): List<WorkspaceMenuItem> }   // CLOSE_TAB only when canCloseTab
}
/** One workspace's screen from plain values (iPhone WorkspaceScreen). `pane` draws one page of the pager; WorkspaceView passes
 *  PaneContent. `pagingLocked` stops sideways paging (a mic listens; 3G may lock it too). */
@Composable fun WorkspaceScreen(title: String, branch: String?, panes: List<WorkspacePane>, selected: String?, nowMs: Long,
    canControl: Boolean = true, canCloseTab: Boolean = false, pagingLocked: Boolean = false, notice: AgentNotice? = null,
    alert: WorkspaceAlert? = null, onAlertDismiss: () -> Unit = {}, actions: WorkspaceScreenActions = WorkspaceScreenActions(),
    back: () -> Unit = {}, pane: @Composable (pane: WorkspacePane, shown: Boolean) -> Unit)
/** The pane slot (contracts §5): an agent pane shows `agent`, any other shows `shell`. `shown` is true only for the settled
 *  page. Plan 3G passes shell = { pane, shown -> TerminalPane(…) } from WorkspaceView; this function does not change. */
@Composable fun PaneContent(pane: WorkspacePane, shown: Boolean, agent: @Composable (MachineSession) -> Unit,
    shell: @Composable (pane: WorkspacePane, shown: Boolean) -> Unit = { _, _ -> ShellPanePlaceholder() })
@Composable fun WorkspaceWaitingView(back: () -> Unit)            // spinner; title workspaces_title; tag workspace.loading
@Composable fun WorkspaceMissingView(back: () -> Unit)            // workspace_not_found, SecondaryButton workspace_not_found_back
/** The chip row (iPhone PaneChips). `close` set: a long press on a chip opens a menu with "Close Tab…". `trailing` comes after
 *  the last chip: plan 3G's "＋" chip. */
@Composable fun PaneChips(panes: List<WorkspacePane>, selected: String?, nowMs: Long, select: (String) -> Unit,
    close: ((WorkspacePane) -> Unit)? = null, trailing: @Composable () -> Unit = {})
object PaneChips {
    fun label(pane: WorkspacePane, res: Resources): String       // title, else AgentLabel.of(agent).text, else workspace_chip_shell
    fun state(pane: WorkspacePane, nowMs: Long, res: Resources): AgentStateStyle?   // null for a shell and for an unknown state
    fun showsWaitingBorder(pane: WorkspacePane): Boolean
}
@Composable fun ShellPanePlaceholder(modifier: Modifier = Modifier)   // workspace_shell_placeholder; tag workspace.shell.placeholder
@Composable fun WorkspaceView(scope: SignedInScope, ref: WorkspaceRef, open: (String) -> Unit, back: () -> Unit)
object WorkspaceView {
    fun paneClosedNotice(res: Resources): String                  // workspace_pane_closed_on_mac
    fun leavingNotice(closedHere: Boolean, res: Resources): String?   // null when closedHere, else workspace_closed_on_mac
}
class WorkspaceScreenHolder(val model: WorkspaceScreenModel) : ViewModel()
// create if missing, beside canClose / closeAgent:
//   fun canCloseTab(machineId: String, hub: MachineHub): Boolean = hub.supportsTerminalClose(machineId)
//   fun closeTab(machineId: String, workspaceId: String, terminalId: String, hub: MachineHub,
//                alert: (WorkspaceAlert) -> Unit): Deferred<WorkspaceFeedback>?        // null while the same tab's close is out
```

  **`WorkspaceScreen`** ports `WorkspaceScreen.swift`:
  - **Top bar.**
    - A back arrow.
    - The title block: the title in `titleMedium` over the branch in monospace `labelSmall` (`onSurfaceVariant`, one line, `TextOverflow.MiddleEllipsis`). Merged semantics, heading, tag `workspace.title`.
    - `⋮` (tag `workspace.menu`, description `workspace_menu`), disabled unless `canControl`. Its items are `items(canCloseTab && <a chip shows>)`: the plain items, a divider, then the red ones.
  - **Body.**
    - `PaneChips`, with `close` set only when `canCloseTab && canControl`.
    - Below it, a `HorizontalPager` (`userScrollEnabled = !pagingLocked`, `key` = pane id). With no panes, `workspace_no_terminals` instead (tag `workspace.noTerminals`).
    - `notice` floats over the top of the pages, as 3D's `NoticeCapsule`, in a polite live region.
  - **Dialogs.**
    - Rename: `WorkspaceRenameSheet` in a `ModalBottomSheet`. Save calls `actions.rename`.
    - Close Workspace: `workspaces_close_title(title)`, `workspaces_close_confirm`, `workspaces_close` in red, `common_cancel`.
    - Close Tab: `terminal_close_title(PaneChips.label(pane))`, `terminal_close_confirm`, `terminal_close` in red, `common_cancel`. Confirming calls `actions.closeTab(pane.id)`.
    - `WorkspaceAlertDialog(alert, onAlertDismiss)`.

  **Keeping the pager and the chips in step.** The pager follows `selected`, and a settled page selects its chip:

  ```kotlin
  val pager = rememberPagerState(initialPage = panes.indexOfFirst { it.id == selected }.coerceAtLeast(0)) { panes.size }
  val currentSelected by rememberUpdatedState(selected)
  var lastIds by remember { mutableStateOf(panes.map { it.id }) }
  LaunchedEffect(selected, panes.map { it.id }) {
      val ids = panes.map { it.id }; val target = ids.indexOf(selected)
      if (target >= 0 && pager.currentPage != target) { if (ids != lastIds) pager.scrollToPage(target) else pager.animateScrollToPage(target) }
      lastIds = ids
  }
  LaunchedEffect(pager) {
      snapshotFlow { pager.settledPage }.collect { page ->
          panes.getOrNull(page)?.id?.let { if (it != currentSelected) actions.select(it) }
      }
  }
  ```

  **`PaneChips`.**
  - A `LazyRow` with 12 dp side padding and 6 dp between chips. The selected chip scrolls into view whenever `selected` changes.
  - A chip has 10 dp corners and is at least 48 dp tall.
    - Selected: accent at 12 % with an accent border at 45 %, and an `accentText` label in SemiBold.
    - Otherwise: on `surfaceContainer`, with an `onSurface` border at 10 %.
    - An agent chip has a `StatusDot` in the tone of `state`. `showsWaitingBorder` draws 3D's waiting border in place of the outline.
  - Gestures: `combinedClickable(onClick = select, onLongClick = …)`. The long press is offered only while `close` is set; it plays `HapticFeedbackType.LongPress` and opens a `DropdownMenu` with `terminal_close_menu` in red.
  - Semantics: label, `stateDescription = state?.text`, `selected`, tag `workspace.chip.<id>`.

  **`WorkspaceView`** ports `WorkspaceView.swift`:
  - **The holder.** `viewModel(key = "workspace/${ref.machineId}/${ref.workspaceId}") { WorkspaceScreenHolder(WorkspaceScreenModel(ref, scope.hub)) }`.
  - **Running.** `model.run()` runs while STARTED.
  - **By phase.**
    - SHOWING → `WorkspaceScreen`.
    - WAITING → `WorkspaceWaitingView`.
    - NOT_FOUND → `WorkspaceMissingView`.
    - DISMISSED → `leavingNotice(closedHere || model.lastTabClosedHere)`, given to `scope.listNotice.show`, then `back()`.
    - MACHINE_REMOVED → `back()`.
  - **A rise of `shownPaneClosed`** shows `paneClosedNotice` for `AgentView.NOTICE_DURATION`.
  - **Leaving.** On dispose, `scope.hub.markSeen(ref)`.
  - **The screen's values:**
    - `canCloseTab = WorkspaceListActions.canCloseTab(ref.machineId, scope.hub)`;
    - `pagingLocked` = `LocalVoice.current?.activity?.anyActive`, collected;
    - `pane = { p, shown -> PaneContent(p, shown, agent = { s -> key(s.ref) { AgentView(scope, s.ref, open, back, embedded = true) } }) }`.

- [ ] **Step 1: Write the failing tests.**
  - **`WorkspaceTextsTest`** (Robolectric). Port these from `WorkspaceRenderTests.swift`:
    - `testTheMenuOffersRenameCloseTabAndCloseWorkspace`;
    - `testAChipSaysItsTabsNameOrWhatItRuns`;
    - `testAChipsDotIsItsAgentsState`, where `colorName` becomes `tone`: `[NEEDS_YOU, null, RUNNING]`, idle → `DONE`, ended → `IDLE`, `AgentState("thinking")` → null;
    - `testLeavingSaysWhyUnlessTheUserClosedIt`;
    - `testTheListNoticeClearsOnlyItself`, only when this task created `ListNotice`.

    Add `theDefaultChipIsTheOneThatWaitsElseTheMacsSelection`, the `defaultTerminal` assertions of `testAgentChipShowsChat` and `testDefaultChipFollowsMacSelection`.
  - **`WorkspaceActionsTest`** (Robolectric, over `WorkRig`). Port every test of `WorkspaceViewTests.swift` except `testTheMenuListsCloseTabOnlyWhenItCan`: 11 tests.
    - `rig.actions` becomes `actions(model)`, which is `WorkspaceScreenActions.make(rig.scope, model, alert = { alerts += it }, closing = { closings++ }, done = { tasks += it })`.
    - `await rig.lastFeedback()` becomes `lastFeedback()`: wait with `eventually { tasks.last().isCompleted }`, then `getCompleted()`.
    - `follow(rig)` becomes `rig.hub.scope.launch { model.run() }`, cancelled in `@After`.
    - `.nothing`, `.refresh` and `.alert(.refusedClose)` become `WorkspaceFeedback.None`, `Refresh` and `Alert(WorkspaceAlert.REFUSED_CLOSE)`.
    - `setNextWorkspaceOutcome(.refused)` becomes `setNextWorkspaceOutcome(WorkspaceControlOutcome.REFUSED)`.
    - `terminalCloses` becomes `rig.mac.terminalCloses.map { "${it.workspaceId}/${it.terminalId}" }`.
  - **`WorkspaceScreenTest`** (Compose, plain values). The panes are those of `WorkspaceRenderTests.swift`: `t-claude` (an agent that asks), `t-zsh` (a shell) and `t-dev` (`dev :3000`, an agent at work). `selected` is a test `mutableStateOf`, and `select` sets it. The agent slot is `Text("agent ${s.session.sessionId}", Modifier.testTag("pane.${s.session.sessionId}"))`. Each comment line is one `@Test`:

```kotlin
class WorkspaceScreenTest {
    // tappingAChipShowsItsPage: selected "t-claude"; tap workspace.chip.t-zsh → selected == "t-zsh"; workspace.shell.placeholder displayed
    // swipingThePagesSelectsTheNextChip: selected "t-claude"; swipeLeft on the pager → selected == "t-zsh"
    // aSelectionFromTheModelTurnsThePage: selected = "t-dev" → pane.s-dev displayed
    // aLongPressOffersCloseTabAndAsksFirst: canCloseTab → long-press workspace.chip.t-zsh → terminal_close_menu → the dialog title is
    //   terminal_close_title("zsh") → terminal_close → closeTabs == ["t-zsh"]; with canCloseTab false a long press opens no menu
    // theMenuOffersCloseTabForTheChipShown: selected "t-claude", canCloseTab → workspace.menu shows workspace_menu_rename,
    //   terminal_close_menu, workspace_menu_close; tap terminal_close_menu → the title is terminal_close_title("claude")
    // closeWorkspaceAsksFirst: workspace.menu → workspace_menu_close → workspaces_close_title("shellx-ios") → workspaces_close →
    //   closes == 1; canControl = false → workspace.menu is not enabled
    // aLockedPagerIgnoresSwipes: pagingLocked = true; swipeLeft → selected still "t-claude"
    // aWorkspaceWithoutTerminalsSaysSo: panes empty → workspace.noTerminals displayed
}
```

  - **`WorkspaceViewTest`** (Compose, over `WorkRig`, showing `WorkspaceView(rig.scope, WorkspaceRef(rig.machineId, "ws-shellx"), …)`). Each comment line is one `@Test`:

```kotlin
class WorkspaceViewTest {
    // thePaneClosedOnTheMacShowsTheNoticeThenItGoes: the Mac shows t-zsh; rig.mac.upsertWorkspace(ws-shellx with only t-claude) →
    //   workspace_pane_closed_on_mac shown and workspace.chip.t-claude selected; mainClock.advanceTimeBy(4_100) → the notice is gone
    // aWorkspaceClosedOnTheMacLeavesWithTheListsNotice: rig.mac.removeWorkspace("ws-shellx") → back ran once; the scope's
    //   ListNotice holds workspace_closed_on_mac
}
```

  - **`WorkspaceRenderTest`.** Port `WorkspaceRenderTests.swift` and `WorkspaceLiveRenderTests.swift`. The agent pane is the real `AgentScreen`, built with the fixtures of the Swift `agentPane`. The render names:
    - `workspace-agent`, `workspace-shell`, `workspace-mac-selection`;
    - `workspace-shells`, `workspace-empty`, `workspace-many-chips`;
    - `workspace-ax3` (in `LargeText`);
    - `workspace-no-control`, `workspace-pane-closed`;
    - `workspace-loading`, `workspace-not-found`;
    - `workspace-live`: `WorkspaceView` over `WorkRig`, with a pending permission in `ws-shellx` and `s1`'s chat already loaded through `scope.agentThread(ref)`;
    - `workspace-live-waiting`: `WorkRig` opening `"new"`.

    That is 13 tests. `workspace-alert` is not ported: a dialog is its own window, which `captureRoboImage` does not draw. `WorkspaceScreenTest` covers the dialogs.
- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.ui.workspaces.*' --tests 'com.shellx.app.screenshots.WorkspaceRenderTest'`.

  Expected: `Unresolved reference` naming `WorkspaceScreen`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test shellx-android/app/src/testDebug`, then `git commit -m "test(shellx-android): workspace screen, chips, pager and commands"`.
- [ ] **Step 4: Implement** the files in Interfaces, and the create-if-missing pieces.
- [ ] **Step 5: Run (green).** Run three times. Expected: PASS, with these counts:
  - `WorkspaceTextsTest`: 5, or 6 with the `ListNotice` test;
  - `WorkspaceActionsTest`: 11;
  - `WorkspaceScreenTest`: 8;
  - `WorkspaceViewTest`: 2;
  - `WorkspaceRenderTest`: 13.
- [ ] **Step 6: Commit with the ledger.** Set row `6.1-8` to `done (3E)`. Row `6.1-9` (3E, 3G) stays `todo` for 3G. Then run `git add shellx-android/app/src/main docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): workspace screen with chips, swipeable panes, Close Tab and Mac-side notices"`.

---

### Task 9: Push: the FCM service, the notifier and taps

**Files:**
- Create in `app/platform/`: `PushNotifier.kt`, `ShellXMessagingService.kt` (with `PushHost`, `PushHooks`), `FcmPushRegistrar.kt`, `PlayTasks.kt`, `PushTapInbox.kt`, `NotificationPermission.kt`
- Create: `res/drawable/ic_stat_shellx.xml`
- Modify: `AndroidManifest.xml` (the service), `res/values/strings_android.xml`, `res/values-vi/strings_android.xml`
- Create (test kit): `app-test/platform/PushTestApplication.kt`
- Test in `app-test/platform/`: `ShellXMessagingServiceTest.kt`, `PushNotifierTest.kt`, `PushTapInboxTest.kt`, `NotificationPermissionTest.kt`

Reference: `ios/Platform/PushAppDelegate.swift` (no banner in front, a tap opens the requests, resolved removes); `ios/ShellXApp.swift` (coming to the front removes every delivered alert); `ios/UI/SignedInView.swift:84-93` (when to ask); contracts §8; 3F's Contract additions.

**Interfaces:**
- Consumes: 3C's `PushPayload` (`parse`, `NeedsYou.showsWorkspace`), `PushRegistrar`, `KeyValueStore`; Task 3's `PermissionRequester`; 3A's `MainActivity`.
- Produces (`com.shellx.app.platform`):

```kotlin
/** What the FCM service reaches through its Application (ShellXApplication in Task 12; tests use their own). */
interface PushHost { val pushHooks: PushHooks }
class PushHooks(val notifier: PushNotifier, val tokenArrived: (String) -> Unit)
/** Data-only FCM messages (contracts §8). Never touches FirebaseApp in onMessageReceived. */
class ShellXMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage)   // PushPayload.parse(message.data) → runBlocking { hooks.notifier.handle(it) }
    override fun onNewToken(token: String)                   // hooks.tokenArrived(token)
}
/** Posts and removes the "needs you" alerts. Thread-safe: FCM calls it on its own thread. */
class PushNotifier(context: Context, inForeground: () -> Boolean, knownMachines: suspend () -> Set<String>?) {
    suspend fun handle(payload: PushPayload)
    fun clearAll()                                           // the app came to the front (iPhone removeAllDeliveredNotifications)
    companion object {
        const val CHANNEL_ID = "needs_you"; const val NOTIFICATION_ID = 1; const val SUMMARY_ID = 2
        const val ACTION_OPEN_PENDING = "com.shellx.app.action.OPEN_PENDING"
        val KNOWN_MACHINES_TIMEOUT: Duration                 // 2 s
        fun ensureChannel(context: Context)                  // notification_channel_needs_you, IMPORTANCE_HIGH, + description
        /** push_needs_you_workspace(agent, workspaceTitle) when showsWorkspace, else push_needs_you(agent). */
        fun text(payload: PushPayload.NeedsYou, res: Resources): String
    }
}
class FcmPushRegistrar : PushRegistrar                       // FirebaseMessaging.getInstance().isAutoInitEnabled = true (off until now,
                                                             // Task 1), then .token.await(); null on any failure
/** Task's result (listeners on a direct executor, Runnable::run); cancellation-aware. */
suspend fun <T> Task<T>.await(): T
/** A tap on a "needs you" alert, held until the signed-in screens take it (iPhone PushTapInbox). Main thread. */
class PushTapInbox { val hasTap: StateFlow<Boolean>; fun receive(); fun take(): Boolean
    companion object { fun isOpenPending(intent: Intent?): Boolean } }      // action == ACTION_OPEN_PENDING
/** POST_NOTIFICATIONS, asked once automatically, the first time a Mac is paired (iPhone registerIfAllowed). */
object NotificationPermission {
    const val ASKED_KEY = "shellx.notifications.asked"
    suspend fun requestOnce(requester: PermissionRequester, settings: KeyValueStore, sdkInt: Int = Build.VERSION.SDK_INT)
    fun isOn(context: Context): Boolean      // areNotificationsEnabled() and the channel, once made, is not IMPORTANCE_NONE
}
```

  **`PushNotifier.handle`.**
  1. **A `NeedsYou`:**
     1. Return when `inForeground()`. No banner in front, as on the iPhone: the app shows what waits.
     2. Return when `SDK_INT >= 33` and `POST_NOTIFICATIONS` is not granted.
     3. Read `known = withTimeoutOrNull(KNOWN_MACHINES_TIMEOUT) { knownMachines() }`. Return when `known != null && payload.machineId !in known` (RF 4).
     4. Call `ensureChannel`.
     5. Post the alert with tag `requestId` and id `NOTIFICATION_ID`:
        - `setSmallIcon(R.drawable.ic_stat_shellx)`;
        - title `push_title`, text `text(payload)`;
        - group `machineId`;
        - `setAutoCancel(true)`;
        - `contentIntent` = `PendingIntent.getActivity(context, requestId.hashCode(), <Intent(context, MainActivity::class.java)>, FLAG_IMMUTABLE or FLAG_UPDATE_CURRENT)`. The intent has action `ACTION_OPEN_PENDING` and `FLAG_ACTIVITY_SINGLE_TOP or FLAG_ACTIVITY_CLEAR_TOP`.
     6. Post the summary with tag `machineId` and id `SUMMARY_ID`: the same group, `setGroupSummary(true)`, `setGroupAlertBehavior(GROUP_ALERT_CHILDREN)`, the same title, text and intent.
  2. **A `Resolved`:** cancel `(requestId, NOTIFICATION_ID)`. Then, when no active notification with id `NOTIFICATION_ID` has group `machineId`, cancel `(machineId, SUMMARY_ID)`.

  **`ic_stat_shellx.xml`:** 24 dp, viewport 512 × 512. It holds elements 4, 5 and 6 of 3A Task 8's logo table (the two chevrons and the cursor), all painted solid `#FFFFFFFF`: strokes with width 54, round caps and joins, and the cursor as a fill.

  **Manifest**, inside `<application>`:

  ```xml
  <service android:name=".platform.ShellXMessagingService" android:exported="false">
      <intent-filter>
          <action android:name="com.google.firebase.MESSAGING_EVENT" />
      </intent-filter>
  </service>
  ```

  **Strings.**

  | Name | en | vi |
  | --- | --- | --- |
  | `notification_channel_needs_you` | Needs you | Cần bạn |
  | `notification_channel_needs_you_description` | When an agent on your Mac is waiting for you | Khi agent trên Mac đang chờ bạn |

- [ ] **Step 1: Write the failing tests.**

```kotlin
class PushTestApplication : Application(), PushHost {
    var foreground = false; var machines: Set<String>? = setOf("m1"); val tokens = mutableListOf<String>()
    override val pushHooks: PushHooks by lazy { PushHooks(PushNotifier(this, { foreground }, { machines })) { tokens += it } }
}

@RunWith(AndroidJUnit4::class)
@Config(application = PushTestApplication::class)
class ShellXMessagingServiceTest {
    private val app: PushTestApplication = ApplicationProvider.getApplicationContext()
    private val shown get() = app.getSystemService(NotificationManager::class.java).activeNotifications.toList()
    private lateinit var service: ShellXMessagingService
    @Before fun setUp() {
        shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        service = Robolectric.buildService(ShellXMessagingService::class.java).create().get()
    }
    private fun receive(vararg data: Pair<String, String>) =
        service.onMessageReceived(RemoteMessage.Builder("shellx@fcm.googleapis.com").setData(mapOf(*data)).build())
    private fun needsYou(request: String, title: String = "shellx") = receive("kind" to "needs_you", "machine_id" to "m1",
        "request_id" to request, "agent" to "Claude Code", "workspace_title" to title)
    private fun StatusBarNotification.text() = notification.extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
    private val alerts get() = shown.filter { it.id == PushNotifier.NOTIFICATION_ID }

    @Test fun needsYouIsTaggedByRequestGroupedByMacAndWorded() {
        needsYou("r1")
        val alert = alerts.single()
        assertEquals("r1", alert.tag); assertEquals("m1", alert.notification.group)
        assertEquals("ShellX", alert.notification.extras.getCharSequence(Notification.EXTRA_TITLE)?.toString())
        assertEquals("Claude Code in shellx is waiting for you", alert.text())
        assertEquals(PushNotifier.CHANNEL_ID, alert.notification.channelId)
        val summary = shown.single { it.id == PushNotifier.SUMMARY_ID }
        assertEquals("m1", summary.tag); assertTrue(summary.notification.flags and Notification.FLAG_GROUP_SUMMARY != 0)
    }
    @Test fun aBlankOrMissingWorkspaceUsesTheShortWords() {
        needsYou("r1", title = "   ")
        receive("kind" to "needs_you", "machine_id" to "m1", "request_id" to "r2", "agent" to "Codex")
        assertEquals(listOf("Claude Code is waiting for you", "Codex is waiting for you"), alerts.sortedBy { it.tag }.map { it.text() })
    }
    @Test @Config(qualifiers = "vi") fun vietnameseAlertsUseTheVietnameseWords() {
        needsYou("r1"); assertEquals("Claude Code ở shellx đang chờ bạn xác nhận", alerts.single().text())
    }
    @Test fun resolvedRemovesThatAlertOnly() {
        needsYou("r1"); needsYou("r2")
        receive("kind" to "resolved", "machine_id" to "m1", "request_id" to "r1")
        assertEquals(listOf("r2"), alerts.map { it.tag }); assertEquals(1, shown.count { it.id == PushNotifier.SUMMARY_ID })
    }
    @Test fun aTapOpensTheWaitingRequests() {
        needsYou("r1")
        val intent = shadowOf(alerts.single().notification.contentIntent).savedIntent
        assertEquals(PushNotifier.ACTION_OPEN_PENDING, intent.action)
        assertEquals(MainActivity::class.java.name, intent.component?.className)
        assertTrue(PushTapInbox.isOpenPending(intent))
    }
    @Test fun messagesAreDataOnlyAndOtherKindsAreIgnored() {
        val message = RemoteMessage.Builder("shellx@fcm.googleapis.com")
            .setData(mapOf("kind" to "teleport", "machine_id" to "m1", "request_id" to "r1")).build()
        assertNull(message.notification); service.onMessageReceived(message); assertTrue(shown.isEmpty())
    }
    @Test fun aNewTokenGoesToTheRegistration() { service.onNewToken("fcm-9"); assertEquals(listOf("fcm-9"), app.tokens) }
}
```

  The other tests. Each comment line is one `@Test`:

```kotlin
@RunWith(AndroidJUnit4::class)
class PushNotifierTest {      // PushNotifier(app, { foreground }, { machines }) over the Robolectric application; POST_NOTIFICATIONS granted
    // nothingShowsWhileTheAppIsInFront (RF 4): foreground = true → handle(NeedsYou("m1", "r1", "Codex", "")) → no notification
    // aMacThisPhoneDoesNotHaveIsIgnored (RF 4): machines = {"m2"} → nothing; machines = null → it posts;
    //   knownMachines = { awaitCancellation() } inside runTest → it posts once 2 s of virtual time passed
    // withoutPermissionNothingIsPosted (RF 4): denyPermissions(POST_NOTIFICATIONS) → nothing posted
    // theSummaryLeavesWithTheLastAlertOfItsMac (RF 4): r1, r2 on m1 and r3 on m2 → Resolved(m1, r1) → m1's summary stays;
    //   Resolved(m1, r2) → no m1 alert or summary; m2's alert and summary stay
    // comingToTheFrontClearsEveryAlertAndAStrayResolvedIsHarmless (RF 4): two alerts → clearAll() → none;
    //   handle(Resolved("m1", "zz")) does not throw
}
@RunWith(AndroidJUnit4::class)
class PushTapInboxTest {
    // aTapIsTakenOnce: receive() → hasTap true; take() true; take() false; hasTap false
    // onlyTheOpenPendingActionCounts: isOpenPending(Intent(ACTION_OPEN_PENDING)) true; (Intent(Intent.ACTION_MAIN)) false; (null) false
}
@RunWith(AndroidJUnit4::class)
class NotificationPermissionTest {   // PermissionRequester over FakeResultRegistry (answer = { true }), MemoryKeyValueStore
    // asksOnceFromAndroid13: sdkInt 33, not granted → one RequestPermission(POST_NOTIFICATIONS) launch and ASKED_KEY true;
    //   a second requestOnce → still one launch
    // neverAsksBelowAndroid13OrWhenGranted: sdkInt 32 → no launch; sdkInt 33 with the permission granted → no launch
    // isOnFollowsTheAppAndTheChannel: enabled and channel HIGH → true; shadowOf(manager).setNotificationsEnabled(false) → false;
    //   channel re-made with IMPORTANCE_NONE → false
}
```

- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.platform.*'`.

  Expected: `Unresolved reference` naming `ShellXMessagingService`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test`, then `git commit -m "test(shellx-android): FCM data messages become tagged, grouped alerts"`.
- [ ] **Step 4: Implement.** Write the files in Interfaces, the icon, the service entry and the strings.
- [ ] **Step 5: Run (green).** Expected: PASS, with these counts:
  - `ShellXMessagingServiceTest`: 7;
  - `PushNotifierTest`: 5;
  - `PushTapInboxTest`: 2;
  - `NotificationPermissionTest`: 3.

  `PermissionRequesterTest` (Task 3) still passes.
- [ ] **Step 6: Commit with the ledger.**
  - Row `6.1-16` (3E app, 3F relay): `done (3E, 3F)` when Task 0 Step 6 printed `3F-merged`; otherwise it stays `todo` and your report says so.
  - Add row `A-e3`:
    - difference: "A needs-you push from a Mac this phone does not have (signed out or unpaired while offline) is dropped; each Mac's alerts are grouped under a summary";
    - why: "the relay can still hold this phone's token after an offline sign-out; Android shows a group only with a summary";
    - Android: `app:platform/PushNotifier.kt`;
    - plan: 3E;
    - state: `differs (3E): by design`.
  - Add row `A-e4`:
    - difference: "Notification permission (Android 13+) is asked once by itself, when the first Mac is paired; afterwards Settings › Notifications offers Turn On";
    - why: "Android shows its permission dialog at most twice, iOS once";
    - Android: `app:platform/NotificationPermission.kt`;
    - plan: 3E;
    - state: `differs (3E): by design`.

  Run `git add shellx-android/app/src/main docs/superpowers/ledgers/shellx-android-parity.md`, then `git commit -m "feat(shellx-android): FCM client: needs-you alerts, resolved removal, taps and the permission"`.

---

### Task 10: The update prompt over Play In-App Updates

**Files:**
- Create: `app/platform/PlayUpdateChecker.kt`, `app/ui/update/UpdateAlert.kt`
- Modify: `res/values/strings_android.xml`, `res/values-vi/strings_android.xml`
- Test: `app-test/platform/PlayUpdateCheckerTest.kt`, `app-ui-test/ui/update/UpdateAlertTest.kt`

Reference: `ios/UI/Update/UpdateAlert.swift`; `ShellXAppCore/Update/UpdatePrompt.swift`; 3C Task 28.

**Interfaces:**
- Consumes: 3C's `UpdateChecker`, `AvailableUpdate`, `UpdatePrompt` (`offered`, `check`, `later`, `update`); Task 9's `await`.
- Produces:

```kotlin
// com.shellx.app.platform
/** 3C's UpdateChecker over Play In-App Updates, flexible flow only (S3 §7.3). */
class PlayUpdateChecker(manager: AppUpdateManager) : UpdateChecker {
    enum class InstallPhase { NONE, DOWNLOADING, DOWNLOADED, INSTALLING, FAILED }
    val installs: StateFlow<InstallPhase>              // from an InstallStateUpdatedListener registered at construction
    /** A StartIntentSenderForResult launcher (key "shellx.update") for startUpdateFlowForResult; call in MainActivity.onCreate. */
    fun attach(registry: ActivityResultRegistry, owner: LifecycleOwner)
    /** AvailableUpdate(availableVersionCode) when UPDATE_AVAILABLE, FLEXIBLE is allowed and nothing is pending, downloading,
     *  downloaded or installing; else null. Also sets installs from installStatus(), so a download finished while the app was
     *  away asks to restart. */
    override suspend fun check(): AvailableUpdate?
    /** startUpdateFlowForResult(the newest info, launcher, AppUpdateOptions.newBuilder(FLEXIBLE).build()); nothing without a
     *  launcher. An AppUpdateInfo is used once: a used one is fetched again. */
    override suspend fun startUpdate(update: AvailableUpdate)
    fun completeUpdate()                               // manager.completeUpdate(): Play restarts the app into the new version
    companion object { fun phase(installStatus: Int): InstallPhase }
}
// com.shellx.app.ui.update
/** Starts Play's flexible-update dialog once per offer (UpdatePrompt.update(): Play's "Update / No thanks" is the prompt) and,
 *  when a download finished, shows a Snackbar update_downloaded with the action update_restart. prompt null (debug) shows nothing. */
@Composable fun UpdateAlert(prompt: UpdatePrompt?, installs: StateFlow<PlayUpdateChecker.InstallPhase>?, restart: () -> Unit,
                            modifier: Modifier = Modifier)
```

  `phase` mapping:
  - `PENDING` and `DOWNLOADING` → `DOWNLOADING`;
  - `DOWNLOADED` → `DOWNLOADED`;
  - `INSTALLING` → `INSTALLING`;
  - `FAILED` → `FAILED`;
  - everything else → `NONE`.

  **Strings.**

  | Name | en | vi |
  | --- | --- | --- |
  | `update_downloaded` | The update is downloaded. | Đã tải xong bản cập nhật. |
  | `update_restart` | Restart | Khởi động lại |

- [ ] **Step 1: Write the failing tests.**

```kotlin
@RunWith(AndroidJUnit4::class)
class PlayUpdateCheckerTest {
    private val fake = FakeAppUpdateManager(ApplicationProvider.getApplicationContext())
    private fun attached() = PlayUpdateChecker(fake).also { val owner = TestOwner(); it.attach(FakeResultRegistry(), owner); owner.start() }
    @Test fun noUpdateOffersNothing() { runTest { fake.setUpdateNotAvailable(); assertNull(attached().check()) } }
    @Test fun aFlexibleUpdateIsOfferedStartedDownloadedAndCompleted() { runTest {
        fake.setUpdateAvailable(101); val checker = attached()
        assertEquals(AvailableUpdate(101), checker.check())
        checker.startUpdate(AvailableUpdate(101)); assertTrue(fake.isConfirmationDialogVisible)
        fake.userAcceptsUpdate(); fake.downloadStarts(); assertEquals(PlayUpdateChecker.InstallPhase.DOWNLOADING, checker.installs.value)
        fake.downloadCompletes(); assertEquals(PlayUpdateChecker.InstallPhase.DOWNLOADED, checker.installs.value)
        assertNull(checker.check()); assertEquals(PlayUpdateChecker.InstallPhase.DOWNLOADED, checker.installs.value)
        checker.completeUpdate(); assertTrue(fake.isInstallSplashScreenVisible)
    } }
    @Test fun anImmediateOnlyUpdateIsNotOffered() { runTest { fake.setUpdateAvailable(101, AppUpdateType.IMMEDIATE); assertNull(attached().check()) } }
    @Test fun withoutAnActivityStartingDoesNothing() { runTest {
        fake.setUpdateAvailable(101); val checker = PlayUpdateChecker(fake)
        checker.check(); checker.startUpdate(AvailableUpdate(101)); assertFalse(fake.isConfirmationDialogVisible)
    } }
    @Test fun installStatusesMapToPhases() {
        assertEquals(listOf(DOWNLOADING, DOWNLOADING, DOWNLOADED, INSTALLING, FAILED, NONE, NONE, NONE),
            listOf(InstallStatus.PENDING, InstallStatus.DOWNLOADING, InstallStatus.DOWNLOADED, InstallStatus.INSTALLING,
                InstallStatus.FAILED, InstallStatus.INSTALLED, InstallStatus.CANCELED, InstallStatus.UNKNOWN).map(PlayUpdateChecker::phase))
    }
}
```

  `UpdateAlertTest` (Compose) uses a test `UpdateChecker` that answers a set `AvailableUpdate?` and records `startUpdate` calls. Each comment line is one `@Test`:

```kotlin
class UpdateAlertTest {
    // anOfferStartsPlaysFlowOnce: UpdatePrompt(100, checker answering AvailableUpdate(101)); prompt.check() → UpdateAlert shown →
    //   started == [AvailableUpdate(101)]; prompt.offered.value == null; another recomposition starts nothing more
    // aDownloadedUpdateAsksToRestart: installs = MutableStateFlow(DOWNLOADED) → update_downloaded shown; tap update_restart →
    //   restart called once
    // nothingShowsWithoutAPrompt: UpdateAlert(null, null) {} → no update_downloaded text, nothing started
}
```

- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.platform.PlayUpdateCheckerTest' --tests 'com.shellx.app.ui.update.*'`.

  Expected: `Unresolved reference` naming `PlayUpdateChecker`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test shellx-android/app/src/testDebug`, then `git commit -m "test(shellx-android): Play flexible update checker and prompt"`.
- [ ] **Step 4: Implement**, with the strings.
- [ ] **Step 5: Run (green).** Expected: PASS, 5 and 3 tests.
- [ ] **Step 6: Commit with the ledger.**
  - Row `6.1-15` (3C rules, 3E UI) becomes `done (3E)`.
  - Add row `A-e5`:
    - difference: "The update prompt is Google Play's own flexible-update dialog (Update / No thanks), at launch and on every return, never in debug; a finished download offers Restart";
    - why: "Play reports a versionCode, not a version name, and its flexible flow brings its own dialog and needs completeUpdate()";
    - Android: `app:ui/update/UpdateAlert.kt`, `app:platform/PlayUpdateChecker.kt`;
    - plan: 3E;
    - state: `differs (3E): by design`.

  Run `git add shellx-android/app/src/main docs/superpowers/ledgers/shellx-android-parity.md`, then `git commit -m "feat(shellx-android): update prompt over Play in-app updates (flexible)"`.

---

### Task 11: Settings › Notifications

**Files:**
- Modify: 3D's `app/ui/settings/NotificationsSettingsSection.kt` (the empty slot gets its body; keep 3D's file and signature)
- Create: `app/ui/settings/OemGuide.kt` (with `NotificationSettingsIntents`)
- Modify: `res/values/strings_android.xml`, `res/values-vi/strings_android.xml`
- Test: `app-test/ui/settings/OemGuideTest.kt`, `app-ui-test/ui/settings/NotificationsSettingsSectionTest.kt`, `app-ui-test/screenshots/NotificationsSettingsRenderTest.kt`

Reference: S3 §7.4c; ledger row `A-1`; 3D's other `SettingsScreen` sections, whose header and row look this section uses.

**Interfaces:**
- Consumes: Task 9's `NotificationPermission.isOn`.
- Produces (`com.shellx.app.ui.settings`):

```kotlin
@Composable fun NotificationsSettingsSection()        // 3D's slot: reads LocalContext, refreshes at ON_RESUME
/** The section from plain values (render and UI tests). */
@Composable internal fun NotificationsSettingsContent(on: Boolean, guide: OemGuide, turnOn: () -> Unit, openAppSettings: () -> Unit,
                                                      lateOpen: Boolean = false)
enum class OemGuide(@StringRes val text: Int) {
    XIAOMI(R.string.settings_notifications_late_xiaomi), OPPO(R.string.settings_notifications_late_oppo),
    VIVO(R.string.settings_notifications_late_vivo), SAMSUNG(R.string.settings_notifications_late_samsung),
    OTHER(R.string.settings_notifications_late_other);
    /** Case-insensitive: xiaomi, redmi, poco → XIAOMI; oppo, realme, oneplus → OPPO; vivo, iqoo → VIVO; samsung → SAMSUNG; else OTHER. */
    companion object { fun of(manufacturer: String): OemGuide }
}
object NotificationSettingsIntents {
    fun appNotifications(context: Context): Intent   // Settings.ACTION_APP_NOTIFICATION_SETTINGS + EXTRA_APP_PACKAGE = packageName
    fun appDetails(context: Context): Intent         // Settings.ACTION_APPLICATION_DETAILS_SETTINGS, data "package:<packageName>"
}
```

  **The section.**
  - The header is `settings_notifications_title`.
  - **Row 1:** `settings_notifications_allow`, with `settings_notifications_on` or `settings_notifications_off` at its end.
    - On: the footer is `settings_notifications_on_footer`.
    - Off: the footer is `settings_notifications_off_footer`, and a `SecondaryButton` `settings_notifications_turn_on` (tag `settings.notifications.turnOn`).
  - **Turn On.**
    - On API 33+ without the permission: a `RequestPermission` launch for `POST_NOTIFICATIONS` (`rememberLauncherForActivityResult`). A `false` answer then opens `appNotifications`.
    - Otherwise it opens `appNotifications` at once.
  - **Row 2:** `settings_notifications_late` (tag `settings.notifications.late`) shows or hides the guide:
    - `settings_notifications_late_intro`;
    - then `guide.text` for `OemGuide.of(Build.MANUFACTURER)`;
    - then a `SecondaryButton` `settings_notifications_open_app_settings` (tag `settings.notifications.openAppSettings`) that opens `appDetails`.

    There is no battery-optimisation request (S3 §7.4c).

  **Strings** (both `strings_android.xml` files):

  | Name | en | vi |
  | --- | --- | --- |
  | `settings_notifications_title` | Notifications | Thông báo |
  | `settings_notifications_allow` | Allow Notifications | Cho phép thông báo |
  | `settings_notifications_on` | On | Bật |
  | `settings_notifications_off` | Off | Tắt |
  | `settings_notifications_on_footer` | You get an alert when an agent needs you. | Bạn được báo khi agent cần bạn. |
  | `settings_notifications_off_footer` | Turn on notifications to know when an agent needs you. | Bật thông báo để biết khi agent cần bạn. |
  | `settings_notifications_turn_on` | Turn On | Bật |
  | `settings_notifications_late` | Notifications arriving late? | Thông báo đến trễ? |
  | `settings_notifications_late_intro` | Some phones hold back notifications from apps that were swiped away from Recents. If alerts from your Mac arrive late: | Một số điện thoại giữ lại thông báo của ứng dụng đã bị vuốt khỏi danh sách gần đây. Nếu thông báo từ Mac đến trễ: |
  | `settings_notifications_late_xiaomi` | Open App Settings, turn on Autostart, then set Battery saver to No restrictions. | Mở Cài đặt ứng dụng, bật Tự khởi động, rồi đặt Tiết kiệm pin thành Không hạn chế. |
  | `settings_notifications_late_oppo` | Open App Settings, then Battery usage: turn on Allow background activity and Allow auto launch. | Mở Cài đặt ứng dụng, vào Sử dụng pin, bật Cho phép hoạt động nền và Cho phép tự khởi chạy. |
  | `settings_notifications_late_vivo` | Open App Settings, then Battery: allow high background power use, and turn on Autostart if your phone has it. | Mở Cài đặt ứng dụng, vào Pin, cho phép dùng nhiều pin ở chế độ nền, và bật Tự khởi động nếu máy có. |
  | `settings_notifications_late_samsung` | Open App Settings, then Battery: choose Unrestricted. | Mở Cài đặt ứng dụng, vào Pin, chọn Không hạn chế. |
  | `settings_notifications_late_other` | Open App Settings, then Battery, and let ShellX run in the background without restrictions. | Mở Cài đặt ứng dụng, vào Pin, và cho ShellX chạy nền không hạn chế. |
  | `settings_notifications_open_app_settings` | Open App Settings | Mở cài đặt ứng dụng |

- [ ] **Step 1: Write the failing tests.** Each comment line is one `@Test`:

```kotlin
class OemGuideTest {
    // makersFindTheirGuide: "Xiaomi", "Redmi", "POCO" → XIAOMI; "OPPO", "realme", "OnePlus" → OPPO; "vivo", "iQOO" → VIVO;
    //   "samsung" → SAMSUNG; "Google", "" → OTHER
    // everyGuideHasItsOwnWords: OemGuide.entries.map { it.text }.toSet().size == 5
}
class NotificationsSettingsSectionTest {   // createAndroidComposeRule<ComponentActivity>(); the public section, ShellXTheme
    // onSaysOn: POST_NOTIFICATIONS granted, notifications enabled → settings_notifications_on shown, no settings.notifications.turnOn
    // offTurnOnAsksForThePermissionThenOpensSettings: permission denied; LocalActivityResultRegistryOwner = FakeResultRegistry.owner
    //   answering false → tap turnOn → one launch of RequestPermission with POST_NOTIFICATIONS; then
    //   shadowOf(activity).nextStartedActivity.action == Settings.ACTION_APP_NOTIFICATION_SETTINGS
    // theLateRowOpensTheGuideAndTheAppsSettings: tap settings.notifications.late → OemGuide.of(Build.MANUFACTURER)'s text shown; tap
    //   settings.notifications.openAppSettings → nextStartedActivity is ACTION_APPLICATION_DETAILS_SETTINGS with data
    //   "package:" + activity.packageName
}
```

  `NotificationsSettingsRenderTest` renders `NotificationsSettingsContent` on `background`, one test each:
  - `settings-notifications-on`;
  - `settings-notifications-off`;
  - `settings-notifications-late` (`OTHER`, `lateOpen = true`);
  - `settings-notifications-late-xiaomi`.
- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.ui.settings.*' --tests 'com.shellx.app.screenshots.NotificationsSettingsRenderTest'`.

  Expected: `Unresolved reference` naming `OemGuide`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test shellx-android/app/src/testDebug`, then `git commit -m "test(shellx-android): Settings › Notifications and the late-notifications guide"`.
- [ ] **Step 4: Implement**, with the strings.
- [ ] **Step 5: Run (green).** Expected: PASS, with 2, 3 and 4 tests. 3D's Settings tests still pass.
- [ ] **Step 6: Commit with the ledger.**
  - Set row `A-1` to `done (3E)`.
  - Add row `A-e6`:
    - difference: "Settings › Notifications says whether notifications are on and offers Turn On";
    - why: "Android lets the user turn alerts off for the app or its channel; the iPhone leaves this to iOS Settings";
    - Android: `app:ui/settings/NotificationsSettingsSection.kt`;
    - plan: 3E;
    - state: `differs (3E): by design`.

  Run `git add shellx-android/app/src/main docs/superpowers/ledgers/shellx-android-parity.md`, then `git commit -m "feat(shellx-android): Settings › Notifications with the OEM guide"`.

---

### Task 12: Wire 3E into the app shell

**Files:**
- Create: `app/PlatformServices.kt`, `app/ui/SignedInWork.kt` (with `PushRegistrationEffect`), and `app/ui/nav/WorkRoutes.kt` only when 3D did not make it (3D Task 7 creates it in this shape: keep 3D's file)
- Modify (3D's files; keep everything else in them):
  - `app/AppComposition.kt`;
  - `app/ShellXApplication.kt`;
  - `app/MainActivity.kt`;
  - `app/ui/nav/ShellXNavHost.kt`;
  - `app/ui/SignedInFrame.kt` (3D's seam for `SignedInWork`);
  - `app/ui/agent/AgentView.kt` (its inline route becomes `WorkRoutes.pendingIn`).
- Test: `app-test/PlatformServicesTest.kt`, `app-test/ui/nav/WorkRoutesTest.kt`, `app-ui-test/ui/nav/WorkRoutesNavTest.kt`, `app-ui-test/ui/SignedInWorkTest.kt`

Reference: `ios/AppComposition.swift` (`VoiceService.system`, `PushRegistration`, the update prompt only in release); `ios/ShellXApp.swift` (coming to the front); `ios/UI/SignedInView.swift` (pending routes, push taps, the permission moment, mics stopped in the background); `ios/UI/Home/HomeRoute.swift`.

**Interfaces:**
- Consumes: every task above; 3D's composition, scope, nav host and lifecycle hook (Task 0 map).
- Produces:

```kotlin
// com.shellx.app
/** Plan 3E's platform pieces (contracts §5, §15), made once per process before AppComposition. */
class PlatformServices(app: Application, debugBuild: Boolean) {
    val permissions: PermissionRequester; val voice: SystemVoice; val voicePermissions: VoicePermissionChecking
    val speechEngine: SpeechEngine                     // voice.engine
    val pushRegistrar: PushRegistrar                   // FcmPushRegistrar()
    val pushTaps: PushTapInbox
    val playUpdates: PlayUpdateChecker?                // null when debugBuild: never in debug builds (S3 §6.1)
    val updateChecker: UpdateChecker?                  // playUpdates
    val attachmentReader: AttachmentReader             // AttachmentPreparer(app.contentResolver, Dispatchers.IO)
    fun makeVoice(hub: MachineHub, latency: LatencyLog, settings: KeyValueStore, clock: Clock): VoiceService
    /** inForeground = ProcessLifecycleOwner is at least STARTED; knownMachines = vault().machines() ids, null on any failure.
     *  `vault` suspends: FCM can start the process before 3D's composition exists. */
    fun makeNotifier(vault: suspend () -> AccountVault): PushNotifier
}
// com.shellx.app.ui
/** What 3E's screens need from a signed-in account (iPhone SignedInView's environment and tasks). */
@Composable fun SignedInWork(scope: SignedInScope, platform: PlatformServices, push: PushRegistration?, settings: KeyValueStore,
                             openPending: () -> Unit, content: @Composable () -> Unit)
@Composable fun PushRegistrationEffect(machinesEmpty: Boolean, signedIn: suspend () -> Unit, askPermission: suspend () -> Unit)
// com.shellx.app.ui.nav
object WorkRoutes {
    const val WORKSPACE = "workspace/{machineId}/{workspaceId}"; const val AGENT = "agent/{machineId}/{sessionId}"
    const val PENDING = "pending?machineId={machineId}&workspaceId={workspaceId}"     // both arguments nullable, default null
    fun workspace(ref: WorkspaceRef): String; fun agent(ref: SessionRef): String      // Uri.encode on each id
    fun pending(): String                                                             // "pending"
    fun pendingIn(machineId: String, workspaceId: String): String
    /** The agent route's ref from the hub's session sets; agent and workspaceTitle "" when the hub lists none (SessionRef's
     *  identity is the two ids). */
    fun sessionRef(hub: HubState, machineId: String, sessionId: String): SessionRef
}
```

  **`SignedInWork`:**
  - It provides `LocalVoice` = `VoiceEnvironment(scope.voice, platform.voice.meter, scope.hub.scope)` and `LocalAttachmentReader` = `platform.attachmentReader`.
  - It runs `PushRegistrationEffect(<hub has no Macs>, { push?.signedIn() }, { NotificationPermission.requestOnce(platform.permissions, settings) })`, which is `LaunchedEffect(machinesEmpty) { if (!machinesEmpty) { signedIn(); askPermission() } }`.
  - When `pushTaps.hasTap` and the hub has Macs, it calls `openPending()` when `pushTaps.take()`.
  - At `ON_STOP` it calls `scope.voice?.cancelAll()` in `hub.scope`: leaving the foreground stops every mic.
  - When Task 0 found that 3D's root does not sync decisions, it also collects `hub.state` into `scope.decisions.sync(it.pendingItems)`.

  **The edits to 3D's files.**
  1. **`ShellXApplication.kt`.**
     - Make `lateinit var platform: PlatformServices` with `PlatformServices(this, BuildConfig.DEBUG)`, first in `onCreate`, and call `PushNotifier.ensureChannel(this)`.
     - Pass `platform`'s pieces to AppComposition's five parameters, by type: `SpeechEngine` ← `speechEngine`, `VoicePermissionChecking` ← `voicePermissions`, `PushRegistrar` ← `pushRegistrar`, `UpdateChecker` ← `updateChecker`, `AttachmentReader` ← `attachmentReader`.
     - Give each per-sign-in scope its voice from `platform.makeVoice(hub, latency, settings, clock)`: with 3D's code that is the `AppComposition(…, makeVoice = platform::makeVoice)` argument, which 3D's `makeScope` already uses for the real account and the demo.
     - Implement `PushHost`: `pushHooks = PushHooks(platform.makeNotifier { awaitComposition().vault }) { token -> <app scope>.launch { awaitComposition().push?.tokenArrived(token) } }`, made lazily. 3D builds the composition only after the settings load (`composition: StateFlow<AppComposition?>`), and an FCM message can start the process before that, so never read `composition.value!!` here.
     - Where `onCreate`'s event loop forwards ON_START to `c.lifecycle.onStart()` (3D's ON_START hook), add `pushHooks.notifier.clearAll()`.
  2. **`AppComposition.kt`.** Make the update prompt `UpdatePrompt(BuildConfig.VERSION_CODE.toLong(), checker)` only when the `UpdateChecker` is not null and the build is not debug. When 3D already does this, change nothing.
  3. **`MainActivity.kt`.**
     - In `onCreate`, after `super.onCreate`: `platform.permissions.attach(activityResultRegistry, this)`, `platform.playUpdates?.attach(activityResultRegistry, this)`, and, only when `savedInstanceState == null` (as 3D's `deliver`: a recreated activity keeps its old intent), `if (PushTapInbox.isOpenPending(intent)) platform.pushTaps.receive()`.
     - In `onNewIntent`: `setIntent(intent)`, then the same check. Keep 3D's deep-link handling there.
     - Last in the root content: `UpdateAlert(<composition>.updatePrompt, platform.playUpdates?.installs) { platform.playUpdates?.completeUpdate() }`, aligned bottom-centre above the navigation bar.
  4. **`SignedInFrame.kt` and `ShellXNavHost.kt`.**
     - In 3D's `SignedInFrame(composition, nav, root, content)` (its KDoc names this edit), wrap the content once for the whole NavHost: `val scope = <the active AccountGraph's scopes.current, collected>; if (scope == null) content() else SignedInWork(scope, platform, <the active AccountGraph>.push /* null in the demo */, composition.settings, openPending = { nav.navigate(WorkRoutes.pending()) { popUpTo(root); launchSingleTop = true } }) { content() }`. `content` stays movable content, so the NavHost keeps its state. Never wrap single destinations in `SignedInWork`.
     - In `ShellXNavHost`, replace only the `WorkPlaceholder(…)` of the three destinations, keeping 3D's `SignedIn(composition) { scope -> … }` wrapper, arguments and `nav`:

  ```kotlin
  composable(WorkRoutes.WORKSPACE) { e -> SignedIn(composition) { scope ->
      WorkspaceView(scope, WorkspaceRef(e.arguments!!.getString("machineId")!!, e.arguments!!.getString("workspaceId")!!),
          open = { nav.navigate(it) }, back = { nav.popBackStack() })
  } }
  composable(WorkRoutes.AGENT) { e -> SignedIn(composition) { scope ->
      val ref = remember(e) { WorkRoutes.sessionRef(scope.hub.state.value, e.arguments!!.getString("machineId")!!, e.arguments!!.getString("sessionId")!!) }
      AgentView(scope, ref, open = { nav.navigate(it) }, back = { nav.popBackStack() })
  } }
  composable(WorkRoutes.PENDING, arguments = listOf(
      navArgument("machineId") { type = NavType.StringType; nullable = true; defaultValue = null },
      navArgument("workspaceId") { type = NavType.StringType; nullable = true; defaultValue = null })) { e -> SignedIn(composition) { scope ->
      val m = e.arguments?.getString("machineId"); val w = e.arguments?.getString("workspaceId")
      PendingListView(scope.hub, scope.decisions, scope.sheets, only = if (m != null && w != null) ({ it.isIn(m, w) }) else null,
          back = { nav.popBackStack() })
  } }
  ```

  Where 3D's own screens built route strings by hand for these three destinations, switch them to `WorkRoutes`. Change nothing else in them.

- [ ] **Step 1: Write the failing tests.** Each comment line is one `@Test`:

```kotlin
@RunWith(AndroidJUnit4::class)
class PlatformServicesTest {
    // theUpdateCheckerExistsOnlyInRelease: PlatformServices(app, BuildConfig.DEBUG).playUpdates != null == !BuildConfig.DEBUG
    // theContractPiecesAreTheRealOnes: speechEngine is FallbackTranscriber, voicePermissions is SystemVoicePermissions,
    //   pushRegistrar is FcmPushRegistrar, attachmentReader is AttachmentPreparer
}
@RunWith(AndroidJUnit4::class)
class WorkRoutesTest {
    // routesEncodeTheirIds: workspace(WorkspaceRef("m1", "ws-1")) == "workspace/m1/ws-1";
    //   agent(SessionRef("m1", "s 1", "claude", "x")) == "agent/m1/s%201"; pendingIn("m1", "ws/2") == "pending?machineId=m1&workspaceId=ws%2F2"
    // theAgentRouteFindsItsSessionOrKeepsTheIds: WorkRig hub state → sessionRef(state, machineId, "s1") has agent "claude" and
    //   title "shellx-ios"; sessionRef(state, machineId, "nope") == SessionRef(machineId, "nope", "", "")
}
class WorkRoutesNavTest {   // a NavHost with WorkRoutes.PENDING (both arguments nullable) and WorkRoutes.AGENT showing their arguments
    // pendingWithoutArgumentsShowsEverything: navigate(WorkRoutes.pending()) → machineId and workspaceId are null
    // pendingInCarriesItsWorkspace: navigate(pendingIn("m1", "ws 1")) → "m1" and "ws 1"; navigate(agent(SessionRef("m1", "s 1", "", ""))) → "s 1"
}
class SignedInWorkTest {    // over WorkRig, with PlatformServices(app, true)
    // aTapOpensTheWaitingRequestsOnceTheMacsAreLoaded: platform.pushTaps.receive() → openPending called once; a recomposition
    //   calls it no more
    // registrationRunsOnceTheFirstMacExists: PushRegistrationEffect(machinesEmpty = true, …) → nothing; set false →
    //   calls == ["signedIn", "askPermission"]; recomposing with false again adds nothing
    // theScreensGetTheMicAndTheReader: inside content, LocalVoice.current?.service === rig.scope.voice and
    //   LocalAttachmentReader.current === platform.attachmentReader
}
```

- [ ] **Step 2: Run (red).** Run `gw :app:testDebugUnitTest --tests 'com.shellx.app.PlatformServicesTest' --tests 'com.shellx.app.ui.nav.WorkRoutes*' --tests 'com.shellx.app.ui.SignedInWorkTest'`.

  Expected: `Unresolved reference` naming `PlatformServices`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/app/src/test shellx-android/app/src/testDebug`, then `git commit -m "test(shellx-android): 3E wiring: platform services, routes and the signed-in work"`.
- [ ] **Step 4: Implement** the three new files and the edits. Then run `shellx-android/scripts/dev.sh test all`, so that 3D's own shell tests show whether the edits broke anything.
- [ ] **Step 5: Run (green).** Expected:
  - PASS, with 2, 2, 2 and 3 tests;
  - `==> test all: passed`;
  - `dev.sh build-release` ends with `release checks passed`.
- [ ] **Step 6: Commit with the ledger.** Row `6.1-14` (Settings › Voice): 3D built the section and left the row `todo` until a `VoiceService` exists; `makeVoice` is now plugged in, so set it to `done (3D, 3E)`. Run `git add shellx-android/app/src docs/superpowers/ledgers/shellx-android-parity.md`, then `git commit -m "feat(shellx-android): plug the workspace, agent, Needs-you, voice, push and update work into the app shell"`.

---

### Task 13: Verify and hand off

**Files:** none new. A fix found here gets a failing test first, in the task that owns the code.

- [ ] **Step 1: Catch up with `develop`.** Run `git merge --no-edit develop`, then `python3 shellx-android/scripts/import-strings.py --check || python3 shellx-android/scripts/import-strings.py`. Handle new iPhone keys by 3A Task 11 Step 1's rule, and commit any change with its ledger row.
- [ ] **Step 2: Run the full verification.**

  ```bash
  shellx-android/scripts/dev.sh test all
  shellx-android/scripts/dev.sh test all
  bash scripts/shellx/check-android-license.sh
  python3 shellx-android/scripts/import-strings.py --check
  shellx-android/scripts/dev.sh build-release
  A2="$HOME/Library/Android/sdk/build-tools/$(ls "$HOME/Library/Android/sdk/build-tools" | sort -V | tail -1)/aapt2"
  "$A2" dump xmltree --file AndroidManifest.xml shellx-android/app/build/outputs/apk/release/app-release-unsigned.apk \
    | grep -cE 'android.speech.RecognitionService|ShellXMessagingService|POST_NOTIFICATIONS|RECORD_AUDIO'
  "$A2" dump xmltree --file AndroidManifest.xml shellx-android/app/build/outputs/apk/release/app-release-unsigned.apk \
    | grep -c REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
  python3 scripts/verify-local.py
  ```

  Expected:
  - `==> test all: passed`, twice;
  - `check-android-license: ok` and `import-strings: ok (…)`;
  - `release checks passed`;
  - a count of `4` or more, then `0`;
  - `verify-local.py` exits 0. A failing check also fails on `develop` in the main checkout? Then it is pre-existing: report it and do not fix it here.
- [ ] **Step 3: Run the boundary greps.** Each command must print nothing:

  ```bash
  git diff --stat develop -- shellx-android/core shellx-link shellx-ios Sources ios Packages cmux-tui shellx-core
  grep -rniE 'manaflow' shellx-android/app/src
  grep -rnE 'Log\.(d|i|w|e|v)\(' shellx-android/app/src/main/kotlin | grep -viE 'CoreLog'
  grep -rn 'REQUEST_IGNORE_BATTERY_OPTIMIZATIONS' shellx-android/app/src/main
  ```

- [ ] **Step 4: Look at the screens.** Run `SHOTS="$(mktemp -d)"; shellx-android/scripts/dev.sh screenshots record "$SHOTS"; ls "$SHOTS" | wc -l`. Then open these and compare each with the iPhone render of the same name:
  - `workspace-live-light-vi.png`;
  - `agent-kinds-dark-en.png`;
  - `pending-question-voice-listening-light-vi.png`;
  - `pending-plan-dark-vi.png`;
  - `voice-listening-dark-vi.png`;
  - `settings-notifications-late-light-vi.png`.

  They must have the same structure, order and words, with Android controls and the ShellX colours.
- [ ] **Step 5: Check the ledger.**
  - Rows `6.1-8`, `6.1-10`, `6.1-11`, `6.1-12`, `6.1-15`, `6.2-18`, `6.2-19`, `6.2-20` and `A-1` say `done (3E)`.
  - `6.1-16` is `done (3E, 3F)`, or `todo` while 3F is not merged.
  - `6.1-9` is `todo` (3G).
  - `6.1-14`, Settings › Voice (3D's section, contracts §15), says `done (3D, 3E)` (Task 12 Step 6).
  - The six rows `A-e1`…`A-e6` exist.

  Commit any ledger fix with `git add docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "docs(shellx-android): ledger rows for the 3E screens"`.
- [ ] **Step 6: Review.** Run a review subagent on `git diff develop...HEAD`, through superpowers:requesting-code-review and `skills/cmux-review/SKILL.md` (correctness first). Give it this plan, contracts §5, §8 and §15, and the iPhone reference folders. Fix each confirmed finding with a failing test first, then repeat Steps 2–5.
- [ ] **Step 7: USER — check on the real Android phone.** Run `shellx-android/scripts/dev.sh device`; expected: `ShellX Dev is running on <serial>`. Then ask the user to do the following and tell you what they saw.

  **Part A works today, through "Try without an account":**
  1. **A permission.** Open Needs you, answer a permission card with Allow (another with Deny), and see each card go.
  2. **A question by voice.** Open a question, press and hold "Answer by voice", and say an option's label in Vietnamese. Release: that option is ticked. Then send.
  3. **A photo and a file.** In an agent's chat, use `+` › Photos to pick a photo, and `+` › Files to pick a file under 10 MB. Send: the ring fills, then "Sent" shows.
  4. **A cancelled hold.** Hold the mic, speak, slide left past the line, release: nothing is sent.

  **Part B needs a relay that runs plans 1A and 3F** (production after plan 1D's deploy, or a dev relay the debug build reaches through 3C's A-6 override: the `shellxApiBase` Gradle property and `adb reverse`), **FCM on both ends** (3A Task 10 done, so `dev.sh build-release` prints no `Firebase: not configured` line; on that relay `docker compose logs relay | grep push_` shows `push_enabled`, plan 3F), **and Google sign-in for `com.shellx.dev`:** the three conditions of 3D Task 17 Step 6 check 4 (the ledger's Web client ID, `GOOGLE_CLIENT_IDS` on that relay, the `ShellX Android (dev)` OAuth client). While the committed `google_oauth.xml` still holds the placeholder, write the ledger's ID into it locally for this install only, and run `git checkout -- shellx-android/app/src/main/res/values/google_oauth.xml` right after it (never commit it):
  5. Sign in with Google and pair with the Mac.
  6. Swipe ShellX Dev away from Recents. On the Mac, start an agent action that needs permission. A "needs you" notification appears, its text naming the agent and the workspace. Do not tap it.
  7. Answer the request on the Mac: the notification disappears within seconds.
  8. If the ledger's test phone is Xiaomi, OPPO or vivo: when step 6 was late or missing, follow Settings › Notifications › "Notifications arriving late?" and repeat steps 6–7.

  Record what passed in the hand-off, and in the ledger's "Test devices" row. When Part B cannot run yet, record "Part B pending: needs a relay with 1A and 3F".
- [ ] **Step 8: Land (contracts §1).** This is an app UI and runtime change, so merge only after the user's explicit OK in Step 7: an OK on Part A, with Part B pending, counts when the user says so. In the checkout that has `develop`:
  1. Run `git pull --ff-only`.
  2. Run `git merge --no-ff feat/shellx-android-3e-ui-work -m "Merge branch 'feat/shellx-android-3e-ui-work' into develop"`.
  3. Run `shellx-android/scripts/dev.sh test app`. Expected: `==> test app: passed`.
  4. Run `git push origin develop`.

  Never merge to `main`. Never deploy, upload or publish. Remove the worktree afterwards (superpowers:finishing-a-development-branch).
- [ ] **Step 9: Report**, in Vietnamese, to the user. Include:
  - the merge commit and the test counts;
  - the Task 0 map of 3D names that differed, and the create-if-missing pieces this plan had to make;
  - the 3C names that differed;
  - the allowlist entries added;
  - the iPhone commits met in Task 0 Step 6;
  - the results of the USER check;
  - for plan 3G, the plug points listed under "Contract additions";
  - for plan 3H, the Data safety facts listed under "Spec notes".

## Spec notes

These are places where the spec, the brief, the contracts or the ledger differ from the code, or where Android differs from the iPhone. The code is the fact, and this plan follows the spec's intent.

- **Update prompt (S3 §6.1, §7.3; `A-e5`).** The iPhone shows its own alert ("Version %@ is available") and opens the App Store. Play In-App Updates gives a `versionCode`, not a version name, and its flexible flow brings its own dialog ("Update / No thanks"). That dialog is therefore the prompt: Update / Later at launch and on every return, never in debug builds. Google's flexible flow also needs a restart step once the download is done (`completeUpdate`), so a Snackbar offers Restart. The iPhone keys `update.title`, `update.message`, `update.now` and `update.later` stay generated but unused, and R8 drops them from release.
- **Settings › Voice.** Ledger row `6.1-14` names 3E, but contracts §15 gives the Voice section to 3D. The contracts win: 3E only supplies the `VoiceService` (`PlatformServices.makeVoice`) that the section reads.
- **`NeedsYouBar`.** The ledger lists it under the home row `6.1-5`, but on the iPhone only the agent screen uses it (the home has the bell). It is created here when 3D did not make it.
- **`WorkspaceFeedback.swift`.** Row `6.1-8` names it for 3E, but 3D's home row actions need it first. This plan uses 3D's, or creates it when missing (Task 7).
- **Notification permission (`A-e4`).** The iPhone asks at the moment the first Mac exists, and iOS shows its prompt once. Android 13+ is asked at the same moment, once by itself (`shellx.notifications.asked`). Afterwards, Settings › Notifications offers Turn On: the system dialog again while Android allows it, then the app's notification settings.
- **No banner in front.** The iPhone's `willPresent` returns no options. On Android, a needs-you message that arrives while the app is in front is not posted at all, and every ShellX alert is cleared when the app comes to the front (iPhone `removeAllDeliveredNotifications` on becoming active).
- **Pushes from an unknown Mac (`A-e3`).** An Android-only guard. A sign-out while offline cannot delete the token on the relay (3C's sign-out is best effort), so alerts for that account could keep arriving. A needs-you whose `machine_id` is not among the paired Macs is dropped. When the vault cannot be read within 2 s, the alert posts: missing an alert is worse.
- **Group summary.** Contracts §8 fixes the tag (`request_id`) and the group (`machine_id`). Android shows a group only when it has a summary, so each Mac gets a summary (tag `machine_id`, id 2) that leaves with its last alert.
- **Voice (`A-e1`, `A-e2`; S3 §7.3).**
  - `SpeechRecognizer` ends a segment at every pause. While the mic is held, the engine starts again after a segment with words. A segment with no words (silence, no match) ends the dictation and keeps the words, which also bounds a TalkBack tap-mode dictation.
  - Android has only the microphone permission. `voice_denied` gets Android wording, and `speech()` is always true.
  - Which languages the on-device recognizer has is known only from API 33 (`checkRecognitionSupport`). On API 31–32 it is tried, and a failure falls back through 3C's `FallbackTranscriber`, which then refreshes Settings.
  - Contextual strings become `EXTRA_BIASING_STRINGS` on API 33+ only.
- **For plan 3H (Data safety).**
  - The on-device recognizer keeps the voice on the phone.
  - The standard recognizer is the phone's own speech service (usually Google's servers, under that service's terms). ShellX never receives, stores or sends audio (`settings_voice_server` says so).
  - FCM uses a registration token and Firebase Installations (device identifiers held by Google); the token also goes to the ShellX relay to route alerts. Both are made only when 3C's `PushRegistration` first asks `FcmPushRegistrar` for the token (FCM auto-init is off until then, Task 1). Report whether 3C asks before a session exists (at a signed-out launch): 3H's Data safety says the token is registered after sign-in.
  - Notification text (agent name, workspace title) comes from the Mac through the relay, and is built on the phone.
- **Hold-to-talk thresholds.** 3C's 80 / 60 are dp on Android; the pointer's movement is converted from px. A hold taken away (the pager, a list, the permission dialog, the screen leaving) cancels: 3C's `MicHold`.
- **Touch targets.** 48 dp, Android's minimum, in place of the iPhone's 44 pt. Tests check 48 dp.
- **`⋮` instead of `•••`.** S3 says "menu •••". Android's overflow menu is `⋮` (Material), and S3 §7.2 asks for Android interaction.
- **Routes.** The iPhone has `pendingIn(machineID, workspaceId)`. Android keeps the contracts' `pending` route and adds two optional query arguments (`WorkRoutes.PENDING`). The `agent/{machineId}/{sessionId}` route carries only ids, so its `SessionRef` comes from the hub (`WorkRoutes.sessionRef`).
- **Configuration changes.** Android recreates the screen on rotation, theme, font size and split screen, which the iPhone never does.
  - Each screen's model and composer draft live in a ViewModel holder (3C: `close()` from `onCleared()`).
  - The sheets keep what was typed in `rememberSaveable`.
  - The pending list keeps the open sheet in its holder.
  - Picks still being read are lost on recreation; the user picks again.
- **Render tests.**
  - `workspace-alert` is not ported: a dialog is its own window, which `captureRoboImage` does not draw. Compose UI tests check every dialog instead.
  - Sheets render their content directly, not inside `ModalBottomSheet`.
- **The Photo Picker** allows 5 at a time. Extra picks beyond the room left get "Up to 5 attachments", as Files does on both phones.
- **`ShellPanePlaceholder`** keeps its iPhone words until 3G replaces it.

## Contract additions

These are the cross-plan names 3E creates or relies on that contracts §5 and §15 do not list yet. They are here for the contracts owner; the executor of this plan does not edit the contracts file.

- **Plug points for plan 3G** (`com.shellx.app.ui.workspaces`).
  - `PaneContent(pane: WorkspacePane, shown: Boolean, agent: @Composable (MachineSession) -> Unit, shell: @Composable (WorkspacePane, Boolean) -> Unit = { _, _ -> ShellPanePlaceholder() })`. 3G passes `shell = { pane, shown -> TerminalPane(…) }` in `WorkspaceView`. `shown` is true only for the pager's settled page: only that pane may open a terminal view.
  - `ShellPanePlaceholder(modifier)`.
  - `WorkspaceScreen(…, pagingLocked: Boolean, pane: @Composable (WorkspacePane, Boolean) -> Unit)`.
  - `PaneChips(panes, selected, nowMs, select, close, trailing: @Composable () -> Unit = {})`. `trailing` is where 3G's "＋" chip goes.
  - `WorkspaceMenuItem.items(canCloseTab)`. 3G adds its "View as terminal" item there.
  - `WorkspaceScreenActions(select, rename, close, closeTab)` with `make(scope, model, alert, closing, done)`, and `WorkspaceView(scope, ref, open, back)`.
- **Route.** `pending?machineId={machineId}&workspaceId={workspaceId}`, with both arguments optional (`WorkRoutes.PENDING`; plain `pending` still matches). Also `WorkRoutes.workspace(ref)`, `agent(ref)`, `pending()`, `pendingIn(machineId, workspaceId)` and `sessionRef(hubState, machineId, sessionId)`.
- **Composition.**
  - `com.shellx.app.PlatformServices` holds 3E's implementations: `speechEngine`, `voicePermissions`, `pushRegistrar`, `updateChecker`, `attachmentReader`, plus `permissions`, `voice`, `pushTaps`, `playUpdates`, `makeVoice(hub, latency, settings, clock)` and `makeNotifier(vault)`. `ShellXApplication` holds it, and implements `com.shellx.app.platform.PushHost`.
  - `com.shellx.app.ui.SignedInWork(scope, platform, push, settings, openPending) { … }` wraps 3D's signed-in content.
  - `LocalVoice` (`VoiceEnvironment(service, meter, scope, activity)`) and `LocalAttachmentReader`.
- **A third voice platform piece.** Besides `SpeechEngine` and `VoicePermissionChecking`, a `VoiceService` needs the capability probe (`VoiceCapabilityProbe.capabilities`, given to `VoiceCapabilityCache`). That is why 3E builds the per-account `VoiceService` (`PlatformServices.makeVoice`) where the iPhone calls `VoiceService.system`.
- **Push.**
  - Channel id `needs_you`. Alert id 1, with tag `request_id`; summary id 2, with tag `machine_id`; group `machine_id`.
  - The tap action `com.shellx.app.action.OPEN_PENDING`, sent to `MainActivity`, and `PushTapInbox`.
  - The Android-only settings key `shellx.notifications.asked`.
- **Names 3E reads from 3D** (Task 0 maps them): `SignedInScope` with `hub`, `decisions`, `pairing`, `history`, `voice`, `sheets`, `listNotice`, `endedDismissals`, `goneRemovals` and `agentThread(ref)`. Also `StatusDot`, `AgentStateStyle` / `StatusTone`, `waitingBorder`, `ListNotice` / `NoticeCapsule`, `WorkspaceFeedback` / `WorkspaceAlert` / `WorkspaceAlertDialog` / `AgentCloseConfirmation`, `WorkspaceListActions`, `WorkspaceRenameSheet`, and `PrimaryButton` / `SecondaryButton`.

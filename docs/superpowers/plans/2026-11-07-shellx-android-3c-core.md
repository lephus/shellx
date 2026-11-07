# ShellX Android core (plan 3C) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the iPhone app's logic (`ShellXAppCore`) and its demo Mac to the pure Kotlin/JVM module `:core` of `shellx-android`, on top of plan 3B's Link API. The port covers the account, the Macs and their Link sessions, revision-synced sets, pairing, decisions, agent chat, composer and attachments, home grouping, the history store, voice logic, push and update rules. The iPhone's behaviour tests are translated into JVM tests.

**Architecture:** `:core` (`com.shellx.core`) has one package per iPhone folder (contracts §5 and the parity ledger's mirror rule). The Swift constructs map like this:
- A Swift `@Observable` class becomes a class with an immutable `…State` snapshot in a `StateFlow`, plus a plain getter for each field.
- A Swift value type becomes an immutable Kotlin value.
- A Swift actor becomes a class serialized by a `Mutex`, with an injected I/O dispatcher.

Code that is `@MainActor` on the iPhone is confined to the dispatcher of the `CoroutineScope` it is given. That is the app's main dispatcher, and in tests the `runTest` dispatcher, so tests run on virtual time. The platform reaches the core only through the interfaces of contracts §5, which plans 3D and 3E implement. The demo Mac (`com.shellx.core.demo`) is a scripted, in-memory fake of 3B's `LinkSession`, and it ships in every build.

**Tech Stack:** Kotlin/JVM 17, kotlinx-coroutines (core, and test for virtual time), kotlinx-serialization-json (`JsonElement` API only, no compiler plugin), plan 3B's `com.shellx.link:link-core` and `link-account` (OkHttp 5 underneath), JUnit 5 with `kotlin("test")`, OkHttp `mockwebserver3` (tests only), and plan 3A's Gradle build, `dev.sh`, lockfiles and licence check.

**Spec:** `docs/superpowers/specs/2026-11-07-shellx-android-app-design.md` (S3): §6.1, §6.2 (every constant), §7.1, §7.3, §7.4 (client side) and §9. Also `docs/superpowers/specs/2026-11-07-shellx-google-sign-in-design.md` (S1): §6.3, §6.7 and §6.8. Cross-plan names: `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` §1, §2, §5, §8, §9 and §11. Kotlin Link API: `docs/superpowers/plans/2026-11-07-shellx-android-3b-link-kotlin.md` (its Interfaces blocks). Build: `docs/superpowers/plans/2026-11-07-shellx-android-3a-scaffold.md`. The Google sign-in, account-deletion and demo-relay behaviour that this plan ports is specified for the iPhone in `docs/superpowers/plans/2026-11-07-shellx-signin-1c-ios.md` Tasks 3, 4, 6, 7 and 12.

## Global Constraints

- **Layout (contracts §5, the ledger's mirror rule).** `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/<Folder>/<Name>.swift` becomes `shellx-android/core/src/main/kotlin/com/shellx/core/<folder in lower case>/<Name>.kt`, in package `com.shellx.core.<folder>`. A type keeps its iPhone name, with two exceptions:
  - a Swift `…Error` type is a `…Exception` (3B's convention), and its file is named after the Kotlin type;
  - a contract name wins: `SpeechEngine` replaces `SpeechTranscribing`.

  Files for Swift extensions are named `PendingItemActions.kt`, `PendingItemPreview.kt` and `PendingQuestionMatching.kt`. The new packages are `platform`, `text` and `demo`. Tests go in `shellx-android/core/src/test/kotlin/com/shellx/core/<folder>/<Name>Test.kt`, and test-only fakes and helpers in `…/test/kotlin/com/shellx/core/testing/`.
- **Pure JVM.** `:core` never imports `android.*` (3A's `CoreIsPureJvmTest` stays green). Main sources use only Java APIs that Android 8.0 (API 26) has. `java.time`, `java.nio.file`, `java.text.Normalizer` and `java.util.UUID` are fine. Never use `java.util.HexFormat`, `java.net.http`, `InputStream.readAllBytes`/`transferTo` or `Thread.ofVirtual`; Task 30 greps for them.
- **Licence (S3 §5).** `shellx-android/` is closed source (3A's `LICENSE`). Translate only from `shellx-ios/` and the plans. Never copy from `Sources/`, `Packages/`, `ios/`, `cmux-tui/` or `shellx-core/`. Never write the upstream company name.
- **Dependencies.** Main code uses only:
  - `api(libs.shellx.link.core)` and `api(libs.shellx.link.account)`;
  - `api` kotlinx-coroutines-core;
  - `implementation` kotlinx-serialization-json.

  Tests add `kotlin("test")`, kotlinx-coroutines-test and `com.squareup.okhttp3:mockwebserver3`. Versions are the exact strings 3B pinned in `shellx-link/kotlin/gradle/libs.versions.toml`: coroutines-test uses the coroutines-core version, and mockwebserver3 the okhttp version. Each new artefact goes through 3A's allowlist procedure (3A Task 3 Step 6).
- **Threading.** A class marked *main-confined* is called only from the dispatcher of the `scope` it was given. That is `Dispatchers.Main.immediate` in the app and the `runTest` dispatcher in tests. It runs all its own work in that scope.
  - Every `scope: CoroutineScope` parameter must be supervised (`SupervisorJob`).
  - `AccountVault` and `ConversationStore` do every `SecretStore` and file call on the `io: CoroutineDispatcher` they are given, never on the caller's dispatcher.
  - `LatencyLog`, `SpeechRunSlot`, `MemoryKeyValueStore`, `DemoSecretStore` and `FakeMac` are thread-safe (`synchronized`, never held across a suspension).
- **Actions that outlive their screen.** Some actions change state shared with other screens:
  - `AppCoordinator.launch`, `signInWithGoogle`, `signOut`, `handleUnauthorized`, `deleteAccount` and `protectedDataBecameAvailable`;
  - `PairingModel.confirm`;
  - `DecisionCenter.send` and `retry`.

  Each runs its work in its object's own scope and only waits for it (`runDetached`, Task 1). Cancelling the caller (Back, a configuration change, a cleared `viewModelScope`) never leaves that work half done. On the iPhone a view's Task is not cancelled this way, so this is how the Swift behaviour carries over to Kotlin.
- **Coroutines (3B rules).**
  - Never swallow a `CancellationException`: any `catch (e: Exception)` or `catch (e: Throwable)` around suspending code rethrows it first.
  - Timeouts use `withTimeoutOrNull`.
  - Long-lived loops close what they opened in `finally`.
- **Exceptions (3B rules).** Exceptions are sealed classes. A case without fields is a `class`, never an `object`. A case with fields is a `data class`.
- **Secrets and content never leave the process in text.**
  - `CoreLog` lines carry event names, error codes, counts and sizes only.
  - `toString()` of a type holding a token, key, pairing code or attachment bytes prints `<redacted>` or `<N bytes>`.
  - A `ByteArray` field means `equals`/`hashCode` use `contentEquals`/`contentHashCode`.
- **Time.** A moment is epoch milliseconds in a `Long` named `…Ms`. A length of time is a `kotlin.time.Duration`. Models read time only through `Clock` (Task 1), never `System.currentTimeMillis()`.
- **Copy.** `:core` holds no user-visible strings; 3D and 3E own them. The demo's data strings are copied verbatim from the iPhone demo, Vietnamese included.
- **Constants (S3 §6.2 and the Swift code).** Copy these exactly:

  | Constant | Value |
  | --- | --- |
  | "Just finished" | 3 600 s |
  | "Ended" | 43 200 s |
  | Gone removals kept | 30 days |
  | Finishes kept per session | 2 |
  | Reconnect waits | 0.5 / 1 / 2 / 4 / 8 / 15 / 30 s, ±20 % |
  | Network settle | 300 ms |
  | Background grace | 25 s |
  | "Handled elsewhere" linger | 2 s |
  | Plan feedback | 4 096 bytes |
  | Chat message | 16 384 bytes |
  | Question answer | 1 024 bytes |
  | Attachments | 5 per message, 10 485 760 bytes each (3B's `ShellXLink`) |
  | Chat copy save delay | 500 ms |
  | Unlisted workspace patience | 5 s |
  | Voice capability reuse | 30 s |
  | Voice result settle | 1.5 s (standard recognizer) / 2 s (on-device recognizer) |
  | Chat page size | 50 |
  | Chat entries kept | 500 |
  | Handled-items memory | 256 |
  | Latency window | 200 |
  | Stored threads | 100 |
  | Workspace title | 128 characters and 512 bytes |
  | Workspace question line | 140 characters |
  | Demo step interval | 20 s |
  | Demo pending cap | 6 |
- **Tests.**
  - JUnit 5 with `kotlin.test` assertions.
  - Every test is `@Test fun name() { runTest { … } }` with a block body, or a plain block body when it does not suspend.
  - Long-lived objects (hubs, connections, fake Macs) live in `backgroundScope`.
  - No real sleeps, except where a step says so.
- **Commits.** 3A's rule applies: when a task has logic, commit the failing tests (`test(shellx-android): …`) before the implementation (`feat(shellx-android): …`). Always use an explicit `git add <paths>`, never `git add -A`. Ledger rows change in the same commit as the code they describe (see Conventions).
- **Landing (contracts §1).** Work on branch `feat/shellx-android-3c-core`. After the final review, merge into `develop` and push `develop`. Never merge to `main`, never deploy, never publish.

## Review Focus

These are inputs the spec implies but that no translated iPhone test exercises, most likely first. Each has a test in its owning task.

1. **A screen's coroutine is cancelled in the middle of an action** (Back, predictive back, rotation, a cleared `viewModelScope`). The sign-out still wipes, a decision still gets its final status, and a pairing whose Mac said Allow is still saved. A Swift view never cancels its Task this way, so the iPhone tests cannot catch it. Tests:
   - Task 14 `aCancelledSignOutStillWipes`;
   - Task 15 `cancellingTheCallerOfConfirmStillSavesTheMac`;
   - Task 16 `aCancelledCallerStillGetsItsStatus`.
2. **The app stays in the background past the 25 s grace without the grace timer ever firing.** Android freezes cached apps, and Doze stops timers. On return, every Mac must reconnect from scratch instead of showing dead sessions as live. Test: Task 12 `aReturnAfterTheGraceReconnectsEvenWhenTheTimerNeverRan`.
3. **Keystore and file work on the main thread.** That would be lag, which S3 §4 forbids. The vault and the history store must do every store and file call on their I/O dispatcher. Tests:
   - Task 6 `storeWorkRunsOnTheIoDispatcher`;
   - Task 18 `fileWorkRunsOnTheIoDispatcher`.
4. **Upload progress arriving from the Link client's thread.** 3B calls `progress` on `Dispatchers.Default`. The value must be applied on the model's scope, only upward, and never after its send ended. Test: Task 19 `progressFromAnotherThreadNeverOutlivesItsSend`.
5. **An FCM data map with extra keys** (`google.*`, `from`), no `workspace_title`, a blank title, or a missing `agent`. It must parse the same way every time, and choose the right notification text. Test: Task 27 `dataWithExtraKeysOrNoTitleStillParses`.

## Conventions

- **Path prefixes.**
  - `core/` = `shellx-android/core/src/main/kotlin/com/shellx/core/`
  - `core-test/` = `shellx-android/core/src/test/kotlin/com/shellx/core/`
  - `ios/` = `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/`
  - `ios-tests/` = `shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/`
  - `ios-support/` = `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppTestSupport/`; after plan 1C lands, the `FakeMac*` files live in `shellx-ios/Packages/ShellXAppCore/Sources/ShellXDemo/` instead.
- **Read the Swift first.** The Swift file named in a task is the reference for every body this plan does not write out. Read it before the task, and keep its behaviour.
  - If plan 1C or 2C changed a reference file since this plan was written, this plan's Interfaces win. Keep the behaviour this plan names, and list the difference in your final report.
  - Do not port new iPhone features this plan does not name.
- **Gradle.** Paste this one-line definition at the start of every shell call that uses it (shell state does not carry over):

  ```bash
  gw() { R="$(git rev-parse --show-toplevel)"; JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" "$R/shellx-android/gradlew" -p "$R/shellx-android" --console=plain "$@"; }
  ```

  A **red** run ends with `BUILD FAILED` and the compile error or failing test the step names. A **green** run ends with `BUILD SUCCESSFUL` and has no `FAILED` line.
- **Test counts.** To check a class's count, read its XML report:

  ```bash
  counts() { R="$(git rev-parse --show-toplevel)"; for c in "$@"; do echo "$c $(grep -o 'tests="[0-9]*" skipped="[0-9]*" failures="[0-9]*" errors="[0-9]*"' "$R/shellx-android/core/build/test-results/test/TEST-com.shellx.core.$c.xml" | head -1)"; done; }
  ```

  For example, `counts link.MachineHubTest` must print `tests="13" skipped="0" failures="0" errors="0"` when a step says "13 tests".
- **Porting a Swift test file.** "Port `ios-tests/FooTests.swift`" means:
  - write one Kotlin `@Test` per `func test…`, in `core-test/<folder>/FooTest.kt`, in the package of the code under test;
  - name it after the Swift name without `test`, with a lower-case first letter;
  - keep every assertion and literal value, translated with the table below;
  - drop only the tests the task lists, each for the reason it gives. The task gives the expected count.

  | Swift | Kotlin |
  | --- | --- |
  | `final class FooTests: XCTestCase`, `@MainActor` | `class FooTest`; drop `@MainActor` |
  | `func testX() async throws` | `@Test fun x() { runTest { … } }` |
  | `await` before a fake's method (`await mac.addPending(…)`) | drop the `await`: the fakes are synchronous |
  | `await eventually { c }`, `instantSleep`, `ManualSleeper`, `Gate`, `ManualClock`, `EventLog`, fixtures (`pendingItem`, `agentSession`, …) | the same names from `com.shellx.core.testing` (Tasks 1, 3, 10) |
  | `Task { … }`, `await t.value`, `t.cancel()` | `backgroundScope.async { … }` (`launch` when there is no value), `.await()`/`.join()`, `.cancel()` |
  | `addTeardownBlock { await x.stopAll() }` | nothing: `backgroundScope` ends with the test |
  | `UserDefaults(suiteName:)` | `MemoryKeyValueStore()` (Task 1) |
  | `Date()`, `Date(timeIntervalSince1970: s)` | epoch ms: `ManualClock().wallMs`, `(s * 1000).toLong()`; a `now:` closure becomes a `ManualClock` |
  | `TimeZone(identifier: x)` | `ZoneId.of(x)` |
  | `Data(repeating: b, count: n)`, `Data("x".utf8)` | `ByteArray(n) { b }`, `"x".encodeToByteArray()` |
  | `machineID`, `requestID`, `grantID`, `userID`, `deviceID` | `machineId`, `requestId`, `grantId`, `userId`, `deviceId` |
  | `URLError(…)` | `java.io.IOException("offline")` |
  | `RelayAPIError.http(status:code:)`, `.badResponse`, `.slotMismatch` | `RelayApiException.Http(status, code)`, `BadResponse()`, `SlotMismatch()` |
  | `LinkClientError.remote(code:message:)`, `.timedOut`, `.sessionClosed`, `.protocolMismatch(message:)` | `LinkClientException.Remote(code, detail)`, `TimedOut()`, `SessionClosed()`, `ProtocolMismatch(detail)` |
  | `NoiseError.untrustedPeer` | `NoiseException.UntrustedPeer()` |
  | `PairingOfferError.badURI`, `.unsupportedVersion`, `.badField` | `PairingOfferException.BadUri()`, `UnsupportedVersion()`, `BadField(field)` |
  | `PhonePairingError.denied`, `.expired` | `PhonePairingException.Denied()`, `Expired()` |
  | `XCTAssertEqual(a, b, accuracy: x)` | `assertEquals(a, b, x)` |
  | `XCTAssertTrue(a === b)` | `assertSame(a, b)` |
  | `try XCTUnwrap(x)` | `assertNotNull(x)` |
  | `do { try f(); XCTFail() } catch { XCTAssertEqual(error as? E, e) }` | `assertSameCase(e, assertFails { f() })` |
  | `var v = Value(); v.change(…)` (a value that is immutable in Kotlin) | `v = v.change(…)` |
  | `.seconds(n)`, `.milliseconds(n)` | `n.seconds`, `n.milliseconds` |
  | `.working` and the other cases of 3B's open enums | `AgentState.WORKING` and so on; Swift `.other` is any unknown wire value, such as `AgentState("teleport")` |
  | `FakeMac(name: "X", …)` | `FakeMac("X", backgroundScope, …)` |
  | `FakeMacFleet(macs, phoneKey: { try await vault.phoneKey() })` | `FakeMacFleet(macs) { vault.phoneKey() }` |
  | `mac.phoneFrameCount` | `mac.phoneCallCount` |
  | `PairedMachine` changed in place (`var m = mac.machine; m.name = "Studio"`) | `mac.machine.copy(name = "Studio")` |

- **The model pattern.** Every main-confined model `X` with observable state has these parts:
  - `val state: StateFlow<XState>`;
  - a read-only property for each `XState` field, with the Swift property's name, reading `state.value`;
  - derived getters (Swift computed properties) that read only `state.value` of the model and of the flows its KDoc names, such as `hub.state.value`.

  A Compose screen therefore collects those flows with `collectAsStateWithLifecycle()`, then reads the getters. The Interfaces blocks list each `XState`.
- **Value types.** A Swift `struct` whose `mutating` functions return nothing becomes an immutable Kotlin class. Each such function returns the changed copy. A Swift `struct` with a `mutating` function that also returns a value (`ChatFollow`, `MicHold`, `PairingScanFilter`, `TranscriptAccumulator`, `SessionFinishDetector`) becomes a small mutable class, not thread-safe, held by one owner.
- **Parity ledger** (`docs/superpowers/ledgers/shellx-android-parity.md`, from 3A).
  - A row whose `Plan` cell is exactly `3C` gets `done (3C)` in the commit that implements it.
  - A row shared with another plan (`3C (rules), 3E (UI)` and the like) keeps `todo`; the last plan sets it.
  - New `A-` rows that this plan adds go at the end of "Android-only differences", in the format of the rows already there. The tasks call them `A-6` to `A-12`, assuming 3A's `A-5` is the last row. If another plan already took a number, use the next free numbers in the same order, and say so in your report.

## File map

| Area | Main files (`core/`) | Task |
| --- | --- | --- |
| Build, platform, test kit | `platform/{Clock,KeyValueStore,CoreLog,Detached}.kt`, `core-test/testing/*` | 1 |
| Text | `text/Text.kt` | 2 |
| Link values | `link/{RevisionGate,PendingSet,SessionSet,WorkspaceSet,ReconnectSchedule,MachineLinkState,SessionRef,MachineSession,MachinePendingItem,ChatUpdate,LinkCallException,AttachmentSendException,LinkFailure,NetworkPath,NetworkMonitor,NetworkChangeFilter}.kt` | 3 |
| Pending values | `pending/{PendingAction,PendingItemActions,PendingItemPreview,PermissionLayout,QuestionDraft,AgentLabel,DecisionStatus,DecisionFailure}.kt` | 4 |
| Names and rows | `home/{SessionName,SessionFinishDetector,AgentStatusRow}.kt`, `workspaces/{WorkspaceRow,WorkspacePane,WorkspaceTitle,WorkspaceCommandResult}.kt` | 5 |
| Vault | `account/{SecretStore,StoredSession,AccountVault,LocalDataWiping}.kt` | 6 |
| Relay seam | `account/{RelayAccountCalling,RelayAccountClient,RelayClientFactory}.kt`, `link/{MachineLinkConnecting,RelayMachineConnector}.kt`, `config/ShellXEndpoints.kt` | 7 |
| Fake Mac | `demo/{FakeMac,FakeMacSession,FakeMacFeed,FakeMacSessions,FakeMacWorkspaces,FakeMacChat,FakeMacFleet}.kt` | 8, 9 |
| Connection | `diagnostics/LatencyLog.kt`, `link/{MachineEvent,MachineConnection}.kt` | 10 |
| Hub | `link/{MachineModel,HubState,MachineHub}.kt`, `pending/DecisionSending.kt` | 11–13 |
| Account flows | `account/{AppPhase,SignInException,IdentityProviding,AppCoordinator}.kt` | 14 |
| Pairing | `pairing/{PairingFailure,PairingInbox,PairingModel,PairingScanFilter,SheetPresence}.kt` | 15 |
| Decisions | `pending/{DecisionCenter,PendingSheetModel}.kt` | 16 |
| Chat and composer values | `agent/{ChatThread,ChatFollow,AgentSendResult}.kt`, `home/ComposerValidation.kt`, `composer/{ComposerDraft,OutgoingAttachment}.kt`, `storage/JsonCodec.kt` | 17 |
| Store | `storage/{StoreDocument,ConversationStore,ChatCopySweeper}.kt` | 18 |
| Attachments | `composer/{UploadProgress,PendingPicks,AttachmentReader,AttachmentChecks}.kt`, `MachineHub.chatSend` with attachments | 19 |
| Agent screen | `agent/AgentThreadModel.kt` | 20, 21 |
| Home | `home/{HomeFocus,EndedDismissals,GoneRemovals}.kt` | 22 |
| Workspace screen | `workspaces/WorkspaceScreenModel.kt` | 23 |
| Voice values | `voice/{VoiceLanguage,VoiceCapabilities,VoiceCapabilityCache,TranscriptAccumulator,DictationOutcome,PendingQuestionMatching}.kt` | 24 |
| Speech engine | `voice/{SpeechEngine,SpeechStartException,SpeechRunSlot,FallbackTranscriber,VoicePermissionChecking,SpeechTimeouts}.kt` | 25 |
| Voice models | `voice/{MicHold,VoiceInputModel,VoiceService}.kt` | 26 |
| Push | `push/{PushPayload,PushRegistrar,PushRegistration}.kt` | 27 |
| Update | `update/{UpdateChecker,UpdatePrompt}.kt` | 28 |
| Demo | `demo/{DemoScript,DemoRelay,DemoSecretStore,DemoEnvironment}.kt` | 29 |

---

### Task 0: Set up the worktree

**Files:** none.

- [ ] **Step 1: Create the worktree.** Use superpowers:using-git-worktrees. The branch is `feat/shellx-android-3c-core`, from `develop`. When there is no native worktree tool, run `git worktree add .worktrees/android-3c-core -b feat/shellx-android-3c-core develop`. Work only in that worktree from now on.
- [ ] **Step 2: Check that plans 3A and 3B are merged.**

  ```bash
  test -x shellx-android/gradlew && test -f shellx-android/core/build.gradle.kts \
    && test -f docs/superpowers/ledgers/shellx-android-parity.md \
    && grep -rq 'interface LinkSession' shellx-link/kotlin/link-core/src/main \
    && grep -rq 'object PhonePairing' shellx-link/kotlin/link-account/src/main && echo ready
  ```

  Expected: `ready`. Otherwise, stop and report "plans 3A and 3B must be merged into develop first". Change nothing.
- [ ] **Step 3: Read what this plan builds on.** Read:
  - `shellx-android/core/build.gradle.kts`, `shellx-android/gradle/libs.versions.toml` and `shellx-link/kotlin/gradle/libs.versions.toml`;
  - in `shellx-link/kotlin/link-core/src/main/kotlin/com/shellx/link/core/`: `LinkSession.kt`, `Models.kt`, `OpenEnums.kt`, `ShellXLink.kt`, `NoiseKeys.kt`, `PairingOffer.kt`;
  - in `shellx-link/kotlin/link-account/src/main/kotlin/com/shellx/link/account/`: `ApiModels.kt`, `RelayApi.kt`, `PhonePairing.kt`, `LinkConnector.kt`.

  Every "Consumes" line below uses 3B's names. If a real name or signature differs, use the real one and list the difference in your final report. Never edit 3B's files.

  If a plan file is missing from the worktree, read it in the primary checkout (`git worktree list` shows it), because plan files may be uncommitted there. Do not commit plan files on this branch.
- [ ] **Step 4: Run the baseline.** Run `shellx-android/scripts/dev.sh test core`.

  Expected: `==> test core: passed`. If it fails before you change anything, stop and report.
- [ ] **Step 5: Note where the iPhone demo lives.** Run `test -d shellx-ios/Packages/ShellXAppCore/Sources/ShellXDemo && echo after-1C || echo before-1C`, and keep the answer for Tasks 8, 9 and 29.

---

### Task 1: Build wiring, platform basics and the test kit

**Files:**
- Modify: `shellx-android/gradle/libs.versions.toml`, `shellx-android/core/build.gradle.kts`, `shellx-android/core/gradle.lockfile` (rewritten by `dev.sh lock`), `scripts/shellx/android-license-allowlist.txt` (only if the licence check asks)
- Create: `core/platform/Clock.kt`, `core/platform/KeyValueStore.kt`, `core/platform/CoreLog.kt`, `core/platform/Detached.kt`
- Create (test kit): `core-test/testing/AsyncTestSupport.kt`, `core-test/testing/ManualClock.kt`, `core-test/testing/Assertions.kt`, `core-test/testing/Fixtures.kt`
- Test: `core-test/platform/PlatformTest.kt`, `core-test/testing/TestKitTest.kt`

Reference: `ios-tests/Support/AsyncTestSupport.swift`, `ios-tests/Support/ManualClock.swift`, `ios-tests/Support/PendingRig.swift` (the fixture functions only).

**Interfaces:**
- Consumes: 3B's model types (`PendingItem`, `AgentSession`, `ChatEntry`, `LinkWorkspace`, `LinkTerminal`, `PendingQuestion`, `PendingQuestionOption`) and the open enums.
- Produces (main, `com.shellx.core.platform`):

```kotlin
/** Time for the core. :app passes its Android clock (3D); tests pass ManualClock. */
interface Clock {
    /** Wall-clock time in epoch milliseconds, the scale of the Mac's `*_ms` fields. */
    fun nowMs(): Long
    /** For stopwatches and "how long in the background": never goes back, and on Android keeps counting in deep
     *  sleep (3D backs it with SystemClock.elapsedRealtimeNanos). */
    val monotonic: TimeSource.WithComparableMarks
}

/** Small non-secret settings (the iPhone's UserDefaults; S3 §7.3 DataStore). Synchronous: :app keeps every value in
 *  memory, loaded before AppComposition is built, and writes through to DataStore in the background (3D). */
interface KeyValueStore {
    fun getString(key: String): String?
    fun putString(key: String, value: String?)      // null removes the key
    fun getBoolean(key: String): Boolean            // false when absent
    fun putBoolean(key: String, value: Boolean)
    fun remove(key: String)
}
/** In memory only: the demo's own settings, and tests. Thread-safe. */
class MemoryKeyValueStore : KeyValueStore

/** Where the core's log lines go (:app sends them to android.util.Log, 3D). Lines are event names with error codes,
 *  counts or sizes: never a token, key, pairing code, id, name, path or content. */
object CoreLog {
    @Volatile var sink: (String) -> Unit = {}
    fun log(line: String)
}

/** Runs [block] in this scope and waits for it. Cancelling the caller does not cancel the work. The block starts at
 *  once in the caller's frame (CoroutineStart.UNDISPATCHED). The inner `async` returns a `Result` and never completes
 *  exceptionally, so a supervised parent that reports child failures (runTest's backgroundScope) never sees the
 *  failure; `getOrThrow()` hands the failure to the caller. */
internal suspend fun <T> CoroutineScope.runDetached(block: suspend CoroutineScope.() -> T): T
```

- Produces (tests, `com.shellx.core.testing`):

```kotlin
val instantSleep: suspend (Duration) -> Unit                  // = { yield() }
/** Repeats until the condition holds or `timeout` of virtual time passed, returning the condition's last value:
 *  runCurrent(), check the condition, then delay(5.milliseconds). */
suspend fun TestScope.eventually(timeout: Duration = 10.seconds, condition: suspend () -> Boolean): Boolean
/** A sleep the test drives (port of ManualSleeper): each call waits until release(), or until cancelled (then it
 *  counts in `cancelled` and rethrows). */
class ManualSleeper {
    val sleep: suspend (Duration) -> Unit
    val requested: List<Duration>      // every duration asked for, in order
    val waiting: List<Duration>        // the waits still blocked, in the order they began
    val cancelled: Int
    fun release(matches: (Duration) -> Boolean = { true })
}
/** Holds callers until open(); ignores cancellation (withContext(NonCancellable) around a CompletableDeferred). */
class Gate { suspend fun wait(); fun open(); val waiting: Int }
/** wallMs moves only through advance() or assignment. The monotonic source is a kotlin.time.TestTimeSource that
 *  advance() moves too. */
class ManualClock(var wallMs: Long = 1_700_000_000_000) : Clock { fun advance(by: Duration) }
/** The same exception case: the same class, and when the class declares instance fields of its own (a data class
 *  case), equal values. */
fun assertSameCase(expected: Throwable, actual: Throwable?, message: String? = null)
fun ByteArray.hex(): String           // lower-case hex
// Fixtures.kt: the values of AsyncTestSupport.swift and PendingRig.swift, exactly.
fun pendingItem(id: String, createdAtMs: Long = 1_700_000_000_000, workspace: String = "shellx"): PendingItem
fun agentSession(id: String, state: AgentState = AgentState.WORKING, lastActivityMs: Long? = 1_700_000_000_000,
                 stateSinceMs: Long? = 1_700_000_000_000, workspace: String = "shellx"): AgentSession
fun linkTerminal(id: String, sessionId: String? = null, order: Int = 0, selected: Boolean = false): LinkTerminal
fun linkWorkspace(workspace: String = "shellx", order: Int = 0, terminals: List<LinkTerminal> = emptyList(),
                  directory: String? = null, branch: String? = null, ports: List<Int>? = null): LinkWorkspace
fun chatEntry(seq: Long, text: String? = null): ChatEntry      // id "e-<seq>", rev 1, AGENT, PROSE, tsMs 1_700_000_000_000 + seq
fun permissionItem(id: String, modes: List<String> = listOf("once", "always", "deny")): PendingItem
fun questionItem(id: String): PendingItem
fun planItem(id: String): PendingItem
```

- [ ] **Step 1: Wire the build.**
  - **Catalog** (`shellx-android/gradle/libs.versions.toml`). Add these aliases with the version strings described in Global Constraints:
    - `kotlinx-coroutines-core` = `org.jetbrains.kotlinx:kotlinx-coroutines-core`;
    - `kotlinx-coroutines-test` = `org.jetbrains.kotlinx:kotlinx-coroutines-test`;
    - `kotlinx-serialization-json` = `org.jetbrains.kotlinx:kotlinx-serialization-json`;
    - `okhttp-mockwebserver3` = `com.squareup.okhttp3:mockwebserver3`.
  - **Module build** (`shellx-android/core/build.gradle.kts`). Keep 3A's plugin, JVM-17, JUnit, test-logging and locking lines. Change 3A's `implementation(libs.shellx.link.core)` and `implementation(libs.shellx.link.account)` to `api(…)`. Add:

    ```kotlin
    api(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.serialization.json)
    testImplementation(kotlin("test"))
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.okhttp.mockwebserver3)
    ```

    Do not apply the Kotlin serialization compiler plugin.

- [ ] **Step 2: Write the test kit and the failing tests.** Write the four `core-test/testing/` files with the Interfaces above. Then write these tests:

```kotlin
class PlatformTest {
    @Test fun memoryStoreKeepsStringsAndBooleans() {
        val s = MemoryKeyValueStore()
        assertNull(s.getString("a")); s.putString("a", "1"); assertEquals("1", s.getString("a"))
        s.putString("a", null); assertNull(s.getString("a"))
        assertFalse(s.getBoolean("b")); s.putBoolean("b", true); assertTrue(s.getBoolean("b"))
        s.remove("b"); assertFalse(s.getBoolean("b"))
    }
    @Test fun detachedWorkSurvivesTheCallersCancellation() { runTest {
        val scope = CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler))
        val gate = CompletableDeferred<Unit>(); var finished = false
        val caller = launch { scope.runDetached { gate.await(); finished = true } }
        runCurrent(); caller.cancelAndJoin(); gate.complete(Unit); runCurrent()
        assertTrue(finished); scope.cancel()
    } }
    @Test fun detachedFailuresReachTheCallerAndNotTheScope() { runTest {
        val scope = CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler))
        assertEquals("boom", assertFailsWith<IllegalStateException> { scope.runDetached { error("boom") } }.message)
        assertTrue(scope.isActive); scope.cancel()
    } }
    @Test fun coreLogGoesToTheSink() {
        val lines = mutableListOf<String>(); CoreLog.sink = { lines += it }
        try { CoreLog.log("hub_started") } finally { CoreLog.sink = {} }
        assertEquals(listOf("hub_started"), lines)
    }
}
class TestKitTest {
    @Test fun manualSleeperRecordsReleasesAndCountsCancellations() { runTest {
        val s = ManualSleeper()
        val a = backgroundScope.launch { s.sleep(1.seconds) }; val b = backgroundScope.launch { s.sleep(2.seconds) }
        runCurrent()
        assertEquals(listOf(1.seconds, 2.seconds), s.requested); assertEquals(listOf(1.seconds, 2.seconds), s.waiting)
        s.release { it == 1.seconds }; runCurrent(); assertTrue(a.isCompleted)
        b.cancelAndJoin(); assertEquals(1, s.cancelled); assertEquals(emptyList(), s.waiting)
    } }
    @Test fun gateHoldsThroughCancellationUntilOpened() { runTest {
        val g = Gate(); val job = backgroundScope.launch { g.wait() }; runCurrent()
        assertEquals(1, g.waiting); job.cancel(); runCurrent(); assertEquals(1, g.waiting)
        g.open(); runCurrent(); assertEquals(0, g.waiting)
        val late = backgroundScope.launch { g.wait() }; runCurrent(); assertTrue(late.isCompleted)
    } }
    @Test fun eventuallyLetsVirtualTimePass() { runTest {
        var ready = false; backgroundScope.launch { delay(3.seconds); ready = true }
        assertTrue(eventually { ready }); assertFalse(eventually(timeout = 100.milliseconds) { false })
    } }
    @Test fun manualClockMovesOnlyWhenTold() {
        val c = ManualClock(wallMs = 1_700_000_000_000); val mark = c.monotonic.markNow()
        c.advance(1500.milliseconds)
        assertEquals(1_700_000_001_500, c.nowMs()); assertEquals(1500.milliseconds, mark.elapsedNow())
        c.wallMs = 5; assertEquals(5, c.nowMs())
    }
    @Test fun sameCaseComparesClassAndFields() {
        assertSameCase(RelayApiException.BadResponse(), RelayApiException.BadResponse())
        assertSameCase(RelayApiException.Http(401, "x"), RelayApiException.Http(401, "x"))
        assertFails { assertSameCase(RelayApiException.Http(401, "x"), RelayApiException.Http(401, "y")) }
        assertFails { assertSameCase(RelayApiException.BadResponse(), RelayApiException.SlotMismatch()) }
    }
}
```

- [ ] **Step 3: Run the tests (red).** Run `gw :core:test --tests 'com.shellx.core.platform.*' --tests 'com.shellx.core.testing.*'`.

  Expected: `BUILD FAILED` with `Unresolved reference: MemoryKeyValueStore`.
- [ ] **Step 4: Commit the tests.** Run `git add shellx-android/gradle/libs.versions.toml shellx-android/core/build.gradle.kts shellx-android/core/src/test`, then `git commit -m "test(shellx-android): core test kit and platform basics"`.
- [ ] **Step 5: Implement the four `core/platform/` files.**
- [ ] **Step 6: Lock the dependencies and run the tests (green).**
  - Run `shellx-android/scripts/dev.sh lock`, then `bash scripts/shellx/check-android-license.sh`.
  - For every `violation` line, apply 3A's allowlist procedure (Task 3 Step 6) and rerun until the check prints `check-android-license: ok`.
  - Then run `shellx-android/scripts/dev.sh test core`.

  Expected: `==> test core: passed`; `counts platform.PlatformTest testing.TestKitTest` shows 4 and 5 tests.
- [ ] **Step 7: Commit.** Run `git add shellx-android/core shellx-android/gradle/libs.versions.toml scripts/shellx/android-license-allowlist.txt`, then `git commit -m "feat(shellx-android): core build, clock, settings, log and detached actions"`.

---

### Task 2: Characters, UTF-8 cuts and composed form

**Files:**
- Create: `core/text/Text.kt`
- Test: `core-test/text/TextTest.kt`

**Interfaces:**
- Produces (`com.shellx.core.text`). This is the unit Swift's `String` counts in. Use it wherever the Swift code counts, cuts or drops `Character`s:

```kotlin
fun String.graphemes(): List<String>
fun String.graphemeCount(): Int
fun String.takeGraphemes(count: Int): String
fun String.dropLastGrapheme(): String           // "" stays ""
fun String.cutToUtf8(maxBytes: Int): String     // the longest prefix of whole graphemes with at most maxBytes UTF-8 bytes
val String.utf8Size: Int
fun String.nfc(): String                        // java.text.Normalizer NFC
```

- [ ] **Step 1: Write the failing tests.**

```kotlin
class TextTest {
    private val family = "👨‍👩‍👧‍👦"
    @Test fun clustersAreWhatAPersonCounts() {
        assertEquals(listOf("a", "b"), "ab".graphemes())
        assertEquals(25, family.utf8Size); assertEquals(listOf(family), family.graphemes())
        assertEquals(listOf("🇻🇳", "🇺🇸"), "🇻🇳🇺🇸".graphemes())
        val decomposed = Normalizer.normalize("ệ", Normalizer.Form.NFD)
        assertEquals(1, decomposed.graphemeCount()); assertEquals(5, decomposed.utf8Size)
        assertEquals(listOf("👍🏽", "x"), "👍🏽x".graphemes()); assertEquals(listOf("\r\n", "a"), "\r\na".graphemes())
        assertEquals(1, "❤️".graphemeCount())
    }
    @Test fun cutsKeepWholeClusters() {
        assertEquals("a".repeat(1020), ("a".repeat(1020) + "🇻🇳").cutToUtf8(1024))
        assertEquals("ệ".nfc().repeat(341), "ệ".nfc().repeat(400).cutToUtf8(1024))
        assertEquals("ab", "abc".dropLastGrapheme()); assertEquals("", "".dropLastGrapheme())
        assertEquals("x", ("x" + family).dropLastGrapheme()); assertEquals(family.repeat(2), family.repeat(5).takeGraphemes(2))
    }
    @Test fun composedFormIsNfc() {
        assertEquals(Normalizer.normalize("Tiếng Việt", Normalizer.Form.NFC),
            Normalizer.normalize("Tiếng Việt", Normalizer.Form.NFD).nfc())
    }
}
```

- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.text.TextTest'`.

  Expected: `Unresolved reference: graphemes`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test/kotlin/com/shellx/core/text` and `git commit -m "test(shellx-android): grapheme rules"`.
- [ ] **Step 4: Implement `Text.kt`.** JDK 17's `BreakIterator` splits emoji ZWJ sequences, so it is not used.
  - Walk the string by code point. A cluster is one code point followed by any number of these extenders:
    - a combining mark (`Character.getType` is `NON_SPACING_MARK`, `ENCLOSING_MARK` or `COMBINING_SPACING_MARK`);
    - a variation selector (U+FE00–U+FE0F or U+E0100–U+E01EF);
    - an emoji modifier (U+1F3FB–U+1F3FF);
    - a tag character (U+E0020–U+E007F);
    - U+200D ZWJ together with the code point after it (and that code point's own extenders).
  - Two regional indicators in a row (U+1F1E6–U+1F1FF) form one cluster.
  - `"\r\n"` is one cluster.
- [ ] **Step 5: Run (green).** Run the same command. Expected: PASS, 3 tests.
- [ ] **Step 6: Commit.** Run `git add shellx-android/core/src/main/kotlin/com/shellx/core/text` and `git commit -m "feat(shellx-android): grapheme-safe text helpers"`.

---

### Task 3: Link values, revision sets, failures and the network filter

**Files:**
- Create in `core/link/`: `RevisionGate.kt`, `PendingSet.kt`, `SessionSet.kt`, `WorkspaceSet.kt`, `ReconnectSchedule.kt`, `MachineLinkState.kt`, `SessionRef.kt`, `MachineSession.kt`, `MachinePendingItem.kt`, `ChatUpdate.kt`, `LinkCallException.kt`, `AttachmentSendException.kt`, `LinkFailure.kt`, `NetworkPath.kt`, `NetworkMonitor.kt`, `NetworkChangeFilter.kt`
- Modify: `core-test/testing/Fixtures.kt` (add `liveSession`)
- Test in `core-test/link/`: `PendingSetTest.kt`, `SessionSetTest.kt`, `WorkspaceSetTest.kt`, `ReconnectScheduleTest.kt`, `MachineLinkStateTest.kt`, `LinkFailureTest.kt`, `NetworkChangeFilterTest.kt`

Reference: the `ios/Link/` files of the same names (`LinkCallError.swift`, `AttachmentSendError.swift` for the exceptions); `ios-tests/Support/HubRig.swift` (`liveSession`).

**Interfaces:**
- Consumes: 3B's `PendingItem`, `AgentSession`, `LinkWorkspace`, `ChatEntry`, `RelayApiException`, `NoiseException`, `LinkClientException`.
- Produces (`com.shellx.core.link`):

```kotlin
object RevisionGate {
    enum class Result { APPLIED, IGNORED, GAP }
    fun check(current: Long, incoming: Long): Result        // <= current IGNORED, current + 1 APPLIED, else GAP
}
/** A set, and what a change did to it: `value` is the changed set when APPLIED, else the set unchanged. */
data class Revised<T>(val value: T, val result: RevisionGate.Result)

/** Items sorted by (createdAtMs, requestId). equals/hashCode/toString over (revision, items). */
class PendingSet(val revision: Long = 0, items: List<PendingItem> = emptyList()) {
    val items: List<PendingItem>
    fun reset(revision: Long, items: List<PendingItem>): PendingSet
    fun apply(revision: Long, added: List<PendingItem>, resolved: List<String>): Revised<PendingSet>
}
/** Sessions sorted by lastActivityMs, newest first (null last), then by sessionId. */
class SessionSet(val revision: Long = 0, sessions: List<AgentSession> = emptyList()) {
    val sessions: List<AgentSession>
    fun reset(revision: Long, sessions: List<AgentSession>): SessionSet
    fun apply(revision: Long, upserted: List<AgentSession>, removed: List<String>): Revised<SessionSet>
    fun session(sessionId: String): AgentSession?
}
/** Workspaces sorted by (order, workspaceId). */
class WorkspaceSet(val revision: Long = 0, workspaces: List<LinkWorkspace> = emptyList()) {
    val workspaces: List<LinkWorkspace>
    fun reset(revision: Long, workspaces: List<LinkWorkspace>): WorkspaceSet
    fun apply(revision: Long, upserted: List<LinkWorkspace>, removed: List<String>): Revised<WorkspaceSet>
    fun workspace(id: String): LinkWorkspace?
}
data class ReconnectSchedule(val steps: List<Duration>, val jitterFraction: Double) {
    // init: require(steps.isNotEmpty()) { "a schedule needs at least one step" }
    fun delay(afterFailures: Int, jitter: Double): Duration   // 0 → ZERO; jitter clamped to -1..1
    companion object { val STANDARD: ReconnectSchedule }      // 500 ms, 1, 2, 4, 8, 15, 30 s; 0.2
}
sealed interface MachineLinkState {
    data object Connecting : MachineLinkState
    data object Online : MachineLinkState
    data object Reconnecting : MachineLinkState
    data class Offline(val sinceMs: Long) : MachineLinkState
    data object Revoked : MachineLinkState
    data object HostKeyChanged : MachineLinkState
    data object NeedsUpdate : MachineLinkState
    val canBeDefault: Boolean      // !needsPairing
    val needsPairing: Boolean      // Revoked, HostKeyChanged
    val isTerminal: Boolean        // Revoked, HostKeyChanged, NeedsUpdate
}
/** Identity is (machineId, sessionId): equals and hashCode ignore agent and workspaceTitle. */
data class SessionRef(val machineId: String, val sessionId: String, val agent: String, val workspaceTitle: String)
data class MachineSession(val machineId: String, val machineName: String, val online: Boolean, val session: AgentSession) {
    val ref: SessionRef        // (machineId, session.sessionId, session.agent, session.workspaceTitle)
    val id: SessionRef get() = ref
}
data class PendingKey(val machineId: String, val requestId: String)
data class MachinePendingItem(val machineId: String, val machineName: String, val item: PendingItem, val actionable: Boolean) {
    val id: PendingKey
    fun isIn(machineId: String, workspaceId: String): Boolean
}
sealed interface ChatUpdate {
    val ref: SessionRef
    val entries: List<ChatEntry>                                  // empty for Reset
    data class Upsert(override val ref: SessionRef, override val entries: List<ChatEntry>) : ChatUpdate
    data class Reset(override val ref: SessionRef) : ChatUpdate
}
sealed class LinkCallException(message: String) : Exception(message) {
    data class Offline(val machineName: String) : LinkCallException("offline")
    data class NeedsPairing(val machineName: String) : LinkCallException("needs_pairing")
    class UnknownMachine : LinkCallException("unknown_machine")
}
sealed class AttachmentSendException(message: String) : Exception(message) {
    class UploadFailed : AttachmentSendException("upload_failed")
    data class Refused(val code: String) : AttachmentSendException("refused")
}
enum class LinkFailure {
    OFFLINE, SIGNED_OUT, REVOKED, HOST_KEY_CHANGED, NEEDS_UPDATE;
    val stopsReconnecting: Boolean                                 // != OFFLINE
    companion object {
        /** Http(401, _) → SIGNED_OUT; Http(_, "not_granted" | "machine_not_found") → REVOKED;
         *  NoiseException.UntrustedPeer, RelayApiException.SlotMismatch → HOST_KEY_CHANGED;
         *  LinkClientException.ProtocolMismatch → NEEDS_UPDATE; anything else → OFFLINE. */
        fun of(error: Throwable): LinkFailure
    }
}
/** What decides whether live sessions may have died: status, primary interface (interfaces.firstOrNull()) and the
 *  sorted gateways. equals/hashCode/toString over those three. */
class NetworkPath(val status: String, interfaces: List<String>, gateways: List<String>) {
    val primaryInterface: String?
    val gateways: List<String>
}
/** The device's default network (contracts §5; 3D implements it with ConnectivityManager.registerDefaultNetworkCallback).
 *  Emits the current path first, then every change. Status "satisfied" when a default network with INTERNET exists,
 *  else "unsatisfied"; interfaces = [LinkProperties.interfaceName]; gateways = the default routes' gateway addresses. */
interface NetworkMonitor { val paths: Flow<NetworkPath> }
/** Main-confined. The first path is the baseline, an equal path is no change, and changes less than SETTLE apart are
 *  reported once, after the last. */
class NetworkChangeFilter(scope: CoroutineScope, sleep: suspend (Duration) -> Unit = { delay(it) }, onChange: () -> Unit) {
    fun receive(path: NetworkPath)
    companion object { val SETTLE: Duration }                    // 300 ms
}
```

- Produces (test kit): `fun liveSession(id: String, mac: String = "m1", online: Boolean = true, state: AgentState = AgentState.WORKING, activity: Long?, since: Long? = 1_700_000_000_000): MachineSession`, with the values of `HubRig.swift`.

- [ ] **Step 1: Port the tests.** Port these files:

  | Swift file | Tests |
  | --- | --- |
  | `ios-tests/PendingSetTests.swift` | 4 |
  | `ios-tests/SessionSetTests.swift` | 3 |
  | `ios-tests/WorkspaceSetTests.swift` | 5 |
  | `ios-tests/ReconnectScheduleTests.swift` | 2 |
  | `ios-tests/MachineLinkStateTests.swift` | 1 |
  | `ios-tests/LinkFailureTests.swift` | 7 |
  | `ios-tests/NetworkChangeFilterTests.swift` | 4 |

  - A Swift `XCTAssertEqual(set.apply(…), .ignored)` becomes `val r = set.apply(…); set = r.value; assertEquals(RevisionGate.Result.IGNORED, r.result)`.
  - `NetworkChangeFilter(sleep:onChange:)` becomes `NetworkChangeFilter(backgroundScope, sleeper.sleep) { calls++ }`.
  - `await Task.yield()` becomes `runCurrent()`.
- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.link.*'`.

  Expected: `Unresolved reference: PendingSet`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): link values and revision sets"`.
- [ ] **Step 4: Implement.** Port each Swift body.
- [ ] **Step 5: Run (green).** Run the same command. Expected: PASS, with the counts in the Step 1 table.
- [ ] **Step 6: Commit with the ledger.** Set row `6.2-9` to `done (3C)`. Then run `git add shellx-android/core/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): revision sets, link states and the network filter"`.

---

### Task 4: Pending items: actions, previews, permission layout, question drafts

**Files:**
- Create in `core/pending/`: `PendingAction.kt`, `PendingItemActions.kt`, `PendingItemPreview.kt`, `PermissionLayout.kt`, `QuestionDraft.kt`, `AgentLabel.kt`, `DecisionStatus.kt`, `DecisionFailure.kt`
- Test in `core-test/pending/`: `PendingActionTest.kt`, `PermissionLayoutTest.kt`, `QuestionDraftTest.kt`, `AgentLabelTest.kt`

Reference: the `ios/Pending/` files of the same names (`PendingItem+Actions.swift`, `PendingItem+Preview.swift`).

**Interfaces:**
- Consumes: 3B's `PendingItem` (with `companion object`), `PendingQuestion`, `LinkDecision`, `PermissionMode`, `ExitPlanMode`, `PendingKind`; Task 2 `cutToUtf8`.
- Produces (`com.shellx.core.pending`):

```kotlin
sealed interface PendingAction {
    data object AllowOnce : PendingAction;  data object Deny : PendingAction
    data object AllowAlways : PendingAction; data object AllowAllTools : PendingAction
    data object Answer : PendingAction;      data class ApprovePlan(val mode: ExitPlanMode) : PendingAction
    data object RevisePlan : PendingAction;  data object RejectPlan : PendingAction; data object OpenOnMac : PendingAction
    val decision: LinkDecision?             // as PendingAction.swift
}
val PendingItem.actions: List<PendingAction>
val PendingItem.previewText: String?
/** The tool input's fields for "Show more": telling keys first, then the rest sorted. A value that is not a string
 *  is compact JSON with object keys sorted, recursively (kotlinx JsonElement.toString()). */
val PendingItem.previewFields: List<Pair<String, String>>?
fun PendingItem.Companion.previewMayBeCut(text: String): Boolean
data class PermissionLayout(val buttons: List<PendingAction>, val menu: List<PendingAction>) {
    companion object { fun of(actions: List<PendingAction>): PermissionLayout }
}
data class AgentLabel(val text: String) { companion object { fun of(agent: String): AgentLabel } }  // claude → "Claude Code", codex → "Codex"
/** Immutable: toggle and setFreeText return the changed draft. */
class QuestionDraft(val questions: List<PendingQuestion>) {
    fun toggle(questionId: String, label: String): QuestionDraft
    fun setFreeText(questionId: String, text: String): QuestionDraft
    fun isSelected(questionId: String, label: String): Boolean
    fun freeText(questionId: String): String
    fun isAnswered(questionId: String): Boolean
    fun answerBytes(questionId: String): Int
    fun isTooLong(questionId: String): Boolean
    val isComplete: Boolean
    val decision: LinkDecision?
    companion object { const val MAX_ANSWER_BYTES = 1024; fun freeTextBytes(text: String): Int }
}
sealed interface DecisionStatus {
    data object Sending : DecisionStatus; data object Done : DecisionStatus; data object HandledElsewhere : DecisionStatus
    data class Failed(val failure: DecisionFailure) : DecisionStatus
}
enum class DecisionFailure { OFFLINE, NO_ANSWER, REJECTED }
```

- [ ] **Step 1: Port the tests.**

  | Swift file | Tests |
  | --- | --- |
  | `ios-tests/PendingActionTests.swift` | 12 |
  | `ios-tests/PermissionLayoutTests.swift` | 3 |
  | `ios-tests/QuestionDraftTests.swift` | 10 |
  | `ios-tests/AgentLabelTests.swift` | 2 |

  Swift `item.previewFields?.map(\.key)` becomes `item.previewFields?.map { it.first }`.
- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.pending.*'`.

  Expected: `Unresolved reference: actions`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): pending actions, previews and question drafts"`.
- [ ] **Step 4: Implement.**
  - JSON goes through `Json.parseToJsonElement`; a preview that does not parse to a `JsonObject` has no fields.
  - `QuestionDraft` cuts with `cutToUtf8(MAX_ANSWER_BYTES)` and trims with `trim()`.
- [ ] **Step 5: Run (green).** Expected: PASS with the counts in the Step 1 table.
- [ ] **Step 6: Commit with the ledger.** Set row `6.2-14` to `done (3C)`. Then run `git add shellx-android/core/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): pending actions, previews and question drafts"`.

---

### Task 5: Session names, finish detection and workspace rows

**Files:**
- Create: `core/home/SessionName.kt`, `core/home/SessionFinishDetector.kt`, `core/home/AgentStatusRow.kt`
- Create: `core/workspaces/WorkspaceRow.kt` (with `WorkspaceRef`, `WorkspaceState`), `core/workspaces/WorkspacePane.kt`, `core/workspaces/WorkspaceTitle.kt`, `core/workspaces/WorkspaceCommandResult.kt`
- Test: `core-test/home/{SessionNameTest,SessionFinishDetectorTest,AgentStatusRowTest}.kt`, `core-test/workspaces/{WorkspaceRowTest,WorkspaceTitleTest}.kt`

Reference: the `ios/Home/` and `ios/Workspaces/` files of the same names.

**Interfaces:**
- Consumes: Task 3 (`SessionRef`, `MachineSession`, `MachinePendingItem`, `WorkspaceSet`); Task 4 (`previewText`, `AgentLabel`); Task 2.
- Produces:

```kotlin
// com.shellx.core.home
object SessionName {
    fun cleaned(title: String?): String?
    fun base(session: AgentSession, zone: ZoneId = ZoneId.systemDefault()): String   // "HH:mm" with DateTimeFormatter, Locale.ROOT
    fun distinct(sessions: List<MachineSession>, zone: ZoneId = ZoneId.systemDefault()): Map<SessionRef, String>
}
/** Mutable (Conventions). In memory only. */
class SessionFinishDetector {
    fun observe(machineId: String, sessions: List<AgentSession>): List<SessionRef>
    fun retain(machineIds: Set<String>)
    fun copy(): SessionFinishDetector              // a deep copy: what "saved and restored" means in the tests
    internal fun reportedCount(machineId: String): Int
    companion object { const val FINISHES_KEPT = 2 }
}
data class AgentStatusRow(val ref: SessionRef, val machineName: String, val state: AgentState, val online: Boolean,
                          val elapsed: Duration?) {
    val id: SessionRef get() = ref
    companion object {
        fun of(session: MachineSession, nowMs: Long): AgentStatusRow
        fun rows(sessions: List<MachineSession>, nowMs: Long): List<AgentStatusRow>
    }
}
// com.shellx.core.workspaces
enum class WorkspaceState { NEEDS_YOU, RUNNING, DONE, ERROR, IDLE }
data class WorkspaceRef(val machineId: String, val workspaceId: String)
data class WorkspaceRow(val id: WorkspaceRef, val title: String, val directory: String? = null, val branch: String? = null,
    val ports: List<Int> = emptyList(), val state: WorkspaceState = WorkspaceState.IDLE, val question: String? = null,
    val terminals: List<LinkTerminal> = emptyList()) {
    companion object {
        internal const val QUESTION_LENGTH = 140
        fun rows(workspaces: WorkspaceSet, sessions: List<AgentSession>, pending: List<MachinePendingItem>,
                 finished: Set<String>, machineId: String): List<WorkspaceRow>
        internal fun sessionIds(workspaceId: String, terminals: List<LinkTerminal>, among: List<AgentSession>): Set<String>
        internal fun firstLine(text: String): String?          // counts graphemes (Task 2)
    }
}
data class WorkspacePane(val id: String, val title: String, val session: MachineSession? = null) {
    val isAgent: Boolean
    companion object {
        internal fun panes(workspace: LinkWorkspace, session: (String) -> MachineSession?): List<WorkspacePane>
        internal fun ordered(terminals: List<LinkTerminal>): List<LinkTerminal>
    }
}
object WorkspaceTitle {
    const val MAX_CHARACTERS = 128
    fun cleaned(title: String): String               // trim, nfc(), takeGraphemes(128), dropLastGrapheme() while > 512 bytes, trim
    fun canSave(title: String): Boolean
}
sealed interface WorkspaceCommandResult {
    data class Ok(val workspaceId: String?) : WorkspaceCommandResult
    data object NotFound : WorkspaceCommandResult; data object Refused : WorkspaceCommandResult
    data object Failed : WorkspaceCommandResult;   data object Offline : WorkspaceCommandResult
    data object Unknown : WorkspaceCommandResult
    companion object { internal fun of(outcome: WorkspaceControlOutcome, workspaceId: String? = null): WorkspaceCommandResult }
}
```

- [ ] **Step 1: Port the tests.**

  | Swift file | Tests |
  | --- | --- |
  | `ios-tests/SessionNameTests.swift` | 10 |
  | `ios-tests/SessionFinishDetectorTests.swift` | 6 |
  | `ios-tests/AgentStatusRowTests.swift` | 3 |
  | `ios-tests/WorkspaceRowTests.swift` | 9 |
  | `ios-tests/WorkspaceTitleTests.swift` | 5 |

  - A JSON round trip of the detector (`roundTrip(detector)`) becomes `detector.copy()`.
  - `precomposedStringWithCanonicalMapping` becomes `.nfc()`, and `decomposedStringWithCanonicalMapping` becomes `Normalizer.normalize(…, NFD)`.
  - Compare wire bytes with `encodeToByteArray().toList()`.
- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.home.*' --tests 'com.shellx.core.workspaces.*'`.

  Expected: `Unresolved reference: SessionName`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): session names, finishes and workspace rows"`.
- [ ] **Step 4: Implement.** Port each Swift body.
  - `SessionName.cleaned` uses the regexes `<[^>]*>` and `<[^>]*$`.
  - Split lines on `\r\n`, `\r`, `\n`, U+0085, U+2028 and U+2029, and words on whitespace.
- [ ] **Step 5: Run (green).** Expected: PASS with the counts in the Step 1 table.
- [ ] **Step 6: Commit with the ledger.** Set row `6.2-2` to `done (3C)`. Then run `git add shellx-android/core/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): session names, finish detection and workspace rows"`.

---

### Task 6: The vault: secrets, session and paired Macs

**Files:**
- Create: `core/account/SecretStore.kt`, `core/account/StoredSession.kt`, `core/account/AccountVault.kt`, `core/account/LocalDataWiping.kt`
- Create (test kit): `core-test/testing/InMemorySecretStore.kt`
- Test: `core-test/account/AccountVaultTest.kt`

Reference: `ios/Account/{SecretStore,StoredSession,AccountVault,LocalDataWiping}.swift`, `ios-support/InMemorySecretStore.swift`.

**Interfaces:**
- Consumes: 3B's `NoiseStaticKey`, `PairedMachine`.
- Produces (`com.shellx.core.account`):

```kotlin
/** The three secrets (contracts §5: SecretStore is implemented by :app, 3D, with an AES-GCM key in the Android
 *  Keystore, excluded from backup). */
enum class SecretItem(val account: String) { SESSION("session"), PHONE_KEY("phone-key"), MACHINES("machines") }
sealed class SecretStoreException(message: String, cause: Throwable? = null) : Exception(message, cause) {
    /** The store cannot be read right now, but the data is still there: never treat it as missing. */
    class Unavailable(cause: Throwable? = null) : SecretStoreException("unavailable", cause)
    class Failed(cause: Throwable? = null) : SecretStoreException("failed", cause)
}
/** Blocking calls; AccountVault calls them on its io dispatcher only. read returns null for an item that is absent,
 *  or that can no longer be decrypted (the implementation deletes it first: a lost Keystore key must not lock the
 *  user out). It throws Unavailable only while the data is still there but unreadable for now, and Failed otherwise. */
interface SecretStore {
    fun read(item: SecretItem): ByteArray?
    fun write(data: ByteArray, item: SecretItem)
    fun delete(item: SecretItem)
}
data class StoredSession(val userId: String, val deviceId: String, val token: String, val email: String) {
    override fun toString(): String                // "StoredSession(user=<userId>, device=<deviceId>, <redacted>)"
}
/** Data this phone keeps for the signed-in account; wiped on sign-out, account deletion, or another account's sign-in. */
fun interface LocalDataWiping { suspend fun wipe() }
/** Every operation holds one Mutex and runs the store call in withContext(io). */
class AccountVault(store: SecretStore, io: CoroutineDispatcher) {
    suspend fun session(): StoredSession?                        // unreadable JSON → null
    suspend fun setSession(session: StoredSession)
    suspend fun clearSession()
    suspend fun phoneKey(): NoiseStaticKey                        // created once (NoiseStaticKey.generate()); a store error propagates
    suspend fun machines(): List<PairedMachine>                   // unreadable or absent → []
    suspend fun machinesOwner(): String?
    suspend fun setMachines(machines: List<PairedMachine>, owner: String)
    suspend fun wipe()                                            // deletes every item; keeps going; rethrows the first failure
}
```

  The stored formats use the iPhone's key names:
  - the session is `{"userID","deviceID","token","email"}`;
  - the Macs are `{"version":1,"owner":"<id>","machines":[{"machineID","name","linkSlot","hostKey":"<standard padded base64>"}]}`;
  - the phone key is its 32 raw private bytes.
- Produces (test kit): `class InMemorySecretStore : SecretStore` with `var failReads: SecretStoreException?`, `var failWrites: SecretStoreException?`, `var failDeletes: SecretStoreException?` and `fun writeCount(item: SecretItem): Int`. It ports `InMemorySecretStore.swift` and is thread-safe.

- [ ] **Step 1: Port the tests and add the I/O test (RF 3).** Port `ios-tests/AccountVaultTests.swift` (5 tests). In each one:
  - use `AccountVault(store, StandardTestDispatcher(testScheduler))`;
  - write `.failed(status:)` and `.unavailable(status:)` as `SecretStoreException.Failed()` and `Unavailable()`;
  - compare errors with `assertIs`.

  Add this test:

```kotlin
@Test fun storeWorkRunsOnTheIoDispatcher() {
    val executor = Executors.newSingleThreadExecutor { Thread(it, "vault-io") }
    val io = executor.asCoroutineDispatcher()
    try {
        runBlocking {
            val threads = Collections.synchronizedSet(mutableSetOf<String>())
            val inner = InMemorySecretStore()
            val store = object : SecretStore {
                override fun read(item: SecretItem) = inner.read(item).also { threads += Thread.currentThread().name }
                override fun write(data: ByteArray, item: SecretItem) { threads += Thread.currentThread().name; inner.write(data, item) }
                override fun delete(item: SecretItem) { threads += Thread.currentThread().name; inner.delete(item) }
            }
            val vault = AccountVault(store, io)
            vault.setSession(StoredSession("u", "d", "t", "e")); vault.session(); vault.phoneKey()
            vault.setMachines(emptyList(), "u"); vault.machines(); vault.wipe()
            assertEquals(setOf("vault-io"), threads.toSet())
        }
    } finally { io.close() }
}
```

- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.account.AccountVaultTest'`.

  Expected: `Unresolved reference: AccountVault`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): the account vault"`.
- [ ] **Step 4: Implement.** Build the JSON with `buildJsonObject` and read it with `jsonObject`/`jsonPrimitive`. Any parsing failure means "unreadable".
- [ ] **Step 5: Run (green).** Expected: PASS, 6 tests.
- [ ] **Step 6: Commit.** Run `git add shellx-android/core/src` and `git commit -m "feat(shellx-android): account vault over the secret store"`.

---

### Task 7: Relay calls, the Link connector and the endpoints

**Files:**
- Create: `core/account/RelayAccountCalling.kt`, `core/account/RelayAccountClient.kt`, `core/account/RelayClientFactory.kt`
- Create: `core/link/MachineLinkConnecting.kt`, `core/link/RelayMachineConnector.kt`
- Create: `core/config/ShellXEndpoints.kt`
- Create (test kit): `core-test/testing/FakeRelayAccount.kt`
- Test: `core-test/account/{RelayClientFactoryTest,RelayAccountClientTest}.kt`, `core-test/link/RelayMachineConnectorTest.kt`, `core-test/config/ShellXEndpointsTest.kt`

Reference:
- `ios/Account/{RelayAccountCalling,RelayAPI+RelayAccountCalling,RelayClientFactory}.swift`;
- `ios/Link/{MachineLinkConnecting,RelayMachineConnector}.swift`, `ios/Config/ShellXEndpoints.swift`;
- `ios-support/FakeRelayAccount.swift`;
- 1C Task 4 for the Google and delete calls (`FakeRelayAccount` presets and `setHook`).

**Interfaces:**
- Consumes: 3B's `RelayApi`, `PhonePairing.pair`, `LinkConnector.connect`, `AccountSignIn`, `PairedMachineListing`, `LinkSession`, `RelayException.InsecureTransport`; Task 6.
- Produces:

```kotlin
// com.shellx.core.account
/** The relay calls the app needs (contracts §2, §8). RelayAccountClient is the real one; tests use FakeRelayAccount;
 *  the demo uses DemoRelay (Task 29). */
interface RelayAccountCalling {
    suspend fun nonce(): String
    suspend fun signInWithGoogle(idToken: String, nonce: String, deviceName: String, clientKey: ByteArray): AccountSignIn
    suspend fun deleteAccount(idToken: String, nonce: String, token: String)
    suspend fun logout(token: String)
    suspend fun machines(token: String): List<PairedMachineListing>
    suspend fun unpair(grantId: String, token: String)
    suspend fun pair(offerUri: String, clientKey: ByteArray, token: String): PairedMachine
    suspend fun setPushToken(fcmToken: String, token: String)
    suspend fun unsetPushToken(token: String)
}
/** Every call goes to `api`; pair is PhonePairing.pair(offerUri, clientKey, api, token). */
class RelayAccountClient(val api: RelayApi) : RelayAccountCalling
object RelayClientFactory {
    /** appVersion when it matches ^[0-9]{1,6}\.[0-9]{1,6}\.[0-9]{1,6}$, else "0.0.0". */
    fun headerVersion(appVersion: String): String
    /** Throws RelayException.InsecureTransport for an http base that is not loopback (3B's RelayApi init). */
    fun make(apiBase: String, appVersion: String, okHttp: OkHttpClient = OkHttpClient()): RelayAccountClient
    fun makeConnector(apiBase: String, appVersion: String, vault: AccountVault, deviceName: String,
                      okHttp: OkHttpClient = OkHttpClient()): MachineLinkConnecting
}
// com.shellx.core.link
/** Opens one Link session to a paired Mac. RelayMachineConnector is the real one; FakeMacFleet is the fake. */
fun interface MachineLinkConnecting { suspend fun connect(machine: PairedMachine): LinkSession }
/** Reads the token and phone key from the vault on every attempt. No stored session → RelayApiException.Http(401, "signed_out")
 *  before any request. Then LinkConnector.connect(machine, key, api, token, clientVersion, deviceName). */
class RelayMachineConnector(api: RelayApi, vault: AccountVault, clientVersion: String, deviceName: String) : MachineLinkConnecting
// com.shellx.core.config
data class ShellXEndpoints(val apiBase: String) {
    companion object {
        const val PRODUCTION = "https://relay.shellx.pro"
        /** Release builds always PRODUCTION. A debug build takes `override` (3D passes BuildConfig.SHELLX_API_BASE from
         *  the Gradle property shellxApiBase) when it is https, or http to a loopback host by ShellXEndpoints.swift's
         *  isLoopback rules; anything else is dropped with CoreLog "api_override_rejected". */
        fun of(debugBuild: Boolean, override: String?): ShellXEndpoints
    }
}
```

- Produces (test kit): `class FakeRelayAccount(sleep: suspend (Duration) -> Unit = { delay(it) }) : RelayAccountCalling`. It is a port of `FakeRelayAccount.swift`, without `login`, plus 1C's Google and delete presets and hooks:

```kotlin
sealed interface Call {
    data object Nonce : Call
    data class SignInWithGoogle(val idToken: String, val nonce: String, val deviceName: String, val clientKeyHex: String) : Call
    data class DeleteAccount(val idToken: String, val nonce: String, val token: String) : Call
    data class Logout(val token: String) : Call
    data class Machines(val token: String) : Call
    data class Unpair(val grantId: String, val token: String) : Call
    data class Pair(val offerUri: String, val clientKeyHex: String, val token: String) : Call
    data class SetPushToken(val fcmToken: String, val token: String) : Call
    data class UnsetPushToken(val token: String) : Call
}
enum class Function { NONCE, SIGN_IN_WITH_GOOGLE, DELETE_ACCOUNT, LOGOUT, MACHINES, UNPAIR, PAIR, SET_PUSH_TOKEN, UNSET_PUSH_TOKEN }
val calls: List<Call>
fun setNonce(nonce: String)                                   // default "nonce-1"
fun setGoogleSignIn(result: Result<AccountSignIn>)            // default AccountSignIn(AccountSession("user", "device", "token"), "user@example.com")
fun setGrants(grants: List<PairedMachineListing>); fun addGrant(machine: PairedMachine)   // grant "grant-<machineId>", "macos", online, fingerprint "fake"
fun setError(error: Exception?, function: Function)
fun setPairResult(machine: PairedMachine?, approvalDelay: Duration); fun setApprovalDelay(delay: Duration)
fun setHook(hook: (suspend () -> Unit)?, function: Function)  // runs inside the call, after it is recorded, before it answers
fun resetCalls()
```

- [ ] **Step 1: Port and write the tests.**
  - **Ported files.**

    | Swift file | Tests | Kotlin |
    | --- | --- | --- |
    | `ios-tests/RelayClientFactoryTests.swift` | 3 | a `MockWebServer` on `127.0.0.1` (`http://127.0.0.1:<port>`) replaces the `URLProtocol` stubs |
    | `ios-tests/RelayMachineConnectorTests.swift` | 1 | the server answers every request with 403 `{"error":{"code":"not_granted","message":"no"}}`; the expected paths are `["/v2/relay/tickets", "/v2/relay/tickets"]` |
    | `ios-tests/ShellXEndpointsTests.swift` | 7 | `ShellXEndpoints(debugBuild: b, environment: [key: v])` becomes `ShellXEndpoints.of(b, v)`, `[:]` becomes `null`, and URL values become strings |

  - **New test, `RelayAccountClientTest.everyCallReachesTheRelayApi`.**
    - Set up a `MockWebServer` whose dispatcher answers:
      - `POST /v1/auth/nonce` → 201 `{"nonce":"n1","expires_in":600}`;
      - `POST /v1/auth/google` → 200 `{"user_id":"u1","device_id":"d1","token":"t1","email":"a@b.c"}`;
      - `GET /v2/phone-grants` → 200 `{"grants":[]}`;
      - everything else → 204.
    - Call `nonce()`, `signInWithGoogle("id", "n1", "Pixel", ByteArray(32))`, `machines("t1")`, `unpair("g1", "t1")`, `setPushToken("fcm", "t1")`, `unsetPushToken("t1")`, `logout("t1")` and `deleteAccount("id2", "n2", "t1")`.
    - Assert, in order, the methods and paths: `POST /v1/auth/nonce`, `POST /v1/auth/google`, `GET /v2/phone-grants`, `DELETE /v2/phone-grants/g1`, `PUT /v1/devices/me/push-token`, `DELETE /v1/devices/me/push-token`, `POST /v1/auth/logout`, `DELETE /v1/account`.
    - Assert that the sign-in returned `AccountSignIn(AccountSession("u1", "d1", "t1"), "a@b.c")`.
- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.account.*' --tests 'com.shellx.core.link.RelayMachineConnectorTest' --tests 'com.shellx.core.config.*'`.

  Expected: `Unresolved reference: RelayClientFactory`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): relay calls, connector and endpoints"`.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run (green).** Expected: PASS.
  - `RelayClientFactoryTest` has 3 tests;
  - `RelayAccountClientTest` has 1;
  - `RelayMachineConnectorTest` has 1;
  - `ShellXEndpointsTest` has 7.
- [ ] **Step 6: Commit with the ledger.** Add row `A-6` to "Android-only differences" in the format of the rows there:
  - difference: "A debug build reads its relay from the `shellxApiBase` Gradle property, not an environment variable. A relay on the Mac is reached through `adb reverse tcp:<port> tcp:<port>` at `http://127.0.0.1:<port>`, because `10.0.2.2` is refused like any other non-loopback http address";
  - why: "Android apps have no launch environment";
  - Android: `core:config/ShellXEndpoints.kt`;
  - plan: 3C;
  - state: `differs (3C): by design`.

  Then run `git add shellx-android/core/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): relay calls, Link connector and endpoints"`.

---

### Task 8: The fake Mac: connections, pending items, sessions and the workspace list

**Files:**
- Create in `core/demo/`: `FakeMac.kt`, `FakeMacSession.kt` (internal), `FakeMacFeed.kt` (internal), `FakeMacSessions.kt` (internal), `FakeMacWorkspaces.kt` (internal; the list part only in this task), `FakeMacFleet.kt`
- Test: `core-test/demo/FakeMacTest.kt`

Reference: `ios-support/FakeMac.swift`, `FakeMacFeed.swift`, `FakeMacSessions.swift`, `FakeMacWorkspaces.swift` and `FakeMacFleet.swift` (or their `ShellXDemo/` copies, per Task 0 Step 5); the host rules in `shellx-link/Sources/ShellXLinkSession/LinkHost.swift:150-170, 262-300, 452-480`.

This fake ships in every build: it is the demo's Mac (contracts §5, §11). It implements 3B's `LinkSession` directly, with no codec and no Noise. It keeps the host rules the phone can observe, so the iPhone's hub tests translate unchanged.

**Interfaces:**
- Consumes: 3B's `LinkSession`, its result types (`PendingSnapshot`, `PendingChange`, `SessionList`, `SessionChange`, `WorkspaceList`, `WorkspaceChange`, `ChatPush`, `ChatHistoryPage`, `WorkspaceCreated`, `ChatAttachment`), `LinkClientException`, `MessageUploadException`, `NoiseStaticKey`, `PairingOffer`, `PairedMachine`, `ShellXLink`, `LinkCodec.MAX_FRAME_BYTES`; Task 7 `MachineLinkConnecting`.
- Produces (`com.shellx.core.demo`; FakeMac is thread-safe, Global Constraints):

```kotlin
class FakeMac(
    name: String, scope: CoroutineScope, id: String? = null,
    val servesSessionsAndChat: Boolean = true, val acceptsAttachments: Boolean = true,
    val servesWorkspaces: Boolean = true, val acceptsWorkspaceControl: Boolean = true,
    val acceptsAgentClose: Boolean = true, val acceptsTerminalClose: Boolean = true,
    nowMs: () -> Long = System::currentTimeMillis,
) {
    data class Decision(val requestId: String, val decision: LinkDecision)
    data class SentText(val sessionId: String, val text: String)
    data class HistoryRequest(val sessionId: String, val beforeSeq: Long?, val limit: Int)
    data class Interrupt(val sessionId: String, val hard: Boolean)
    data class TerminalCloseCall(val workspaceId: String, val terminalId: String)
    /** machineId "mac-<id>", linkSlot "slot-<id>", the first host key; id defaults to a random lower-case UUID. */
    val machine: PairedMachine
    val connectCount: Int
    val liveSessionCount: Int
    /** Every LinkSession call any phone made (close and the four Flows do not count). */
    val phoneCallCount: Int
    fun connector(phoneKey: suspend () -> NoiseStaticKey): MachineLinkConnecting
    fun failNextConnects(error: Exception, count: Int)
    fun rotateHostKey()
    /** Ends every live session from the Mac's side: each one's four Flows complete and its pending calls throw SessionClosed. */
    fun dropLiveSessions()
    fun pairingOffer(): PairingOffer                  // PairingOffer.make(machineId, linkSlot, current host key, name)
    fun pairingCode(): String                         // pairingOffer().uri
    // pending (FakeMacFeed)
    fun addPending(item: PendingItem); fun resolvePending(requestId: String); fun skipNextPendingRevision()
    fun setReplyOutcome(outcome: ReplyOutcome?, delay: Duration = Duration.ZERO, resolves: Boolean = true)
    val decisions: List<Decision>; val snapshotCount: Int
    fun holdSnapshots(); fun releaseSnapshots(); val heldSnapshotCount: Int
    // sessions (FakeMacSessions)
    fun upsertSession(session: AgentSession); fun removeSession(sessionId: String); fun skipNextSessionRevision()
    val sessionListCount: Int
    // workspace list (FakeMacWorkspaces)
    fun setWorkspaces(workspaces: List<LinkWorkspace>); fun upsertWorkspace(workspace: LinkWorkspace)
    fun removeWorkspace(workspaceId: String); fun skipNextWorkspaceRevision()
    val workspaceListCount: Int
    // Task 9 adds the chat and control members of FakeMac.swift
}
/** Connects each machine to the FakeMac with its machineId; any other machine → RelayApiException.Http(404, "machine_not_found"). */
class FakeMacFleet(macs: List<FakeMac>, phoneKey: suspend () -> NoiseStaticKey) : MachineLinkConnecting
```

  **Connecting** (`connector(...).connect(machine)`), in this order:
  1. `phoneKey()`;
  2. `connectCount += 1`;
  3. while `failNextConnects` has failures left, throw its error;
  4. when `machine.hostKey` is not the current host key's public key, throw `NoiseException.UntrustedPeer()`;
  5. otherwise open a new `FakeMacSession` and count it in `liveSessionCount` until either side closes it.

  **`hostFeatures`** of a session, fixed when it opens:
  - `attachments` when `servesSessionsAndChat && acceptsAttachments`;
  - `workspaces` when `servesWorkspaces`;
  - `workspace_control` when `servesWorkspaces && acceptsWorkspaceControl`;
  - `agent_close` when `servesSessionsAndChat && acceptsAgentClose`;
  - `terminal_close` when `servesWorkspaces && acceptsTerminalClose`.

  **Every call** counts in `phoneCallCount`, then:
  - a call on a closed session throws `SessionClosed()`;
  - otherwise the Mac's side of the call runs in the FakeMac's `scope` (`async`), so a held call still acts once released;
  - the phone waits for that answer or for the session's end, whichever comes first (`select`; the end throws `SessionClosed()`).

  **Pushes.** Each change of the Mac's state is broadcast to every live session's `Channel(UNLIMITED)`. A revision counts once per change of the Mac (not per session), and `skipNext…Revision` raises it without a broadcast.

  **Host rules of this task:**

  | Call | Answer |
  | --- | --- |
  | `snapshot()` | waits while snapshots are held (`heldSnapshotCount`), then `snapshotCount += 1` and `PendingSnapshot(revision, items sorted by requestId)` |
  | `reply` | records a `Decision` and waits `delay`. A preset outcome is answered as is: a preset `DELIVERED` resolves the item unless `resolves` is false. Without a preset, a known item is resolved and gets `DELIVERED`; a request resolved before gets `ALREADY_HANDLED`; anything else gets `UNKNOWN` |
  | `sessions()` | `Remote("unsupported", "this host has no agent sessions")` without `servesSessionsAndChat`; else `sessionListCount += 1` and `SessionList(revision, sessions sorted by sessionId)` |
  | `workspaces()` | `Remote("unsupported", "this host lists no workspaces")` without `servesWorkspaces`. Otherwise `workspaceListCount += 1`, then `Remote("too_large", "the answer does not fit in one frame")` when the workspaces' titles hold more than `LinkCodec.MAX_FRAME_BYTES` UTF-8 bytes, else `WorkspaceList(revision, sorted by (order, workspaceId))` |
  | `setWorkspaces` | broadcasts what differs from the old list as one change, as `FakeMacWorkspaces.set` does; nothing differs → no change |

- [ ] **Step 1: Write the failing tests** in `FakeMacTest`. Each comment line is a `@Test` with those values. Sessions come from `mac.connector { NoiseStaticKey.generate() }.connect(mac.machine)`.

```kotlin
class FakeMacTest {
    // featuresFollowWhatTheMacServes: default → setOf("attachments","workspaces","workspace_control","agent_close","terminal_close");
    //   servesSessionsAndChat = false → setOf("workspaces","workspace_control","terminal_close");
    //   servesWorkspaces = false → setOf("attachments","agent_close"); acceptsAttachments = false → no "attachments";
    //   acceptsWorkspaceControl = false → no "workspace_control"
    // connectCountsEveryAttemptAndFailsAsTold: failNextConnects(IOException("down"), 2) → two connects throw IOException,
    //   the third connects; connectCount == 3; liveSessionCount == 1
    // aRotatedKeyIsAnUntrustedPeer: rotateHostKey() → connect(mac.machine) throws NoiseException.UntrustedPeer; connectCount == 1;
    //   connect(mac.machine.copy(hostKey = mac.pairingOffer().hostKey)) succeeds
    // pendingRevisionsCountEveryChangeAndSkipLeavesAGap: addPending(pendingItem("r1")) before connecting → snapshot() ==
    //   PendingSnapshot(1, [r1]); addPending(r2) → changes.first() == PendingChange(2, [r2], []);
    //   skipNextPendingRevision(); resolvePending("r1") → next change PendingChange(4, [], ["r1"])
    // replyResolvesAKnownItemAndAnswersAlreadyHandledAfter: reply("r1", Permission(ONCE)) == DELIVERED and a change resolves r1;
    //   reply("r1", …) again == ALREADY_HANDLED; reply("nope", …) == UNKNOWN; decisions has the three;
    //   setReplyOutcome(ALREADY_HANDLED) → reply("r2", …) == ALREADY_HANDLED
    // heldSnapshotsWaitAndAClosedSessionStopsWaiting: holdSnapshots(); a call to snapshot() → heldSnapshotCount == 1;
    //   session.close() → the call throws SessionClosed; releaseSnapshots() → snapshotCount == 1; liveSessionCount == 0
    // sessionsFollowTheMacAndAreUnsupportedWithoutChat: upsertSession(s1) → sessions() == SessionList(1, [s1]);
    //   upsertSession(s2) → sessionChanges.first() == SessionChange(2, [s2], []); removeSession("s1") → SessionChange(3, [], ["s1"]);
    //   FakeMac(servesSessionsAndChat = false).sessions() throws Remote("unsupported", …)
    // aWorkspaceListThatDoesNotFitIsTooLarge: setWorkspaces([LinkWorkspace("ws-huge", "w".repeat(70_000), 0, terminals = [])])
    //   → workspaces() throws Remote("too_large", …); workspaceListCount == 1
    // dropLiveSessionsEndsEveryFlowAndCall: two sessions; holdSnapshots() and a snapshot() call on the first; dropLiveSessions()
    //   → the call throws SessionClosed; on both sessions changes, sessionChanges, workspaceChanges and chatEntries toList() complete;
    //   liveSessionCount == 0
    // phoneCallsAreCounted: snapshot(), sessions(), workspaces() → phoneCallCount == 3; collecting a Flow adds nothing
    // fleetConnectsByMachineIdAndRefusesStrangers: FakeMacFleet([a]) { key }.connect(b.machine) throws Http(404, "machine_not_found")
}
```

- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.demo.FakeMacTest'`.

  Expected: `Unresolved reference: FakeMac`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): the fake Mac's connections and lists"`.
- [ ] **Step 4: Implement.**
  - `FakeMacSession` implements every `LinkSession` member. In this task, the chat and control members throw `Remote("unsupported", …)`; Task 9 replaces them.
  - `close()` is idempotent.
- [ ] **Step 5: Run (green).** Expected: PASS, 11 tests.
- [ ] **Step 6: Commit.** Run `git add shellx-android/core/src` and `git commit -m "feat(shellx-android): fake Mac with connections, pending items, sessions and workspaces"`.

---

### Task 9: The fake Mac: chat, attachments and control

**Files:**
- Create: `core/demo/FakeMacChat.kt` (internal)
- Modify: `core/demo/FakeMac.kt`, `FakeMacSession.kt`, `FakeMacWorkspaces.kt`
- Test: `core-test/demo/FakeMacChatTest.kt`

Reference: `ios-support/FakeMacChat.swift` and `FakeMacWorkspaces.swift` (control part); `LinkHost.swift:276-330, 360-425` (the chat, attachment and control rules); 3B Task 9 (the upload rules and the upload turn).

**Interfaces:**
- Produces, added to `FakeMac` (the names and semantics of `FakeMac.swift`):

```kotlin
fun setHistory(sessionId: String, entries: List<ChatEntry>)
fun pushChat(sessionId: String, entries: List<ChatEntry>)
fun resetChat(sessionId: String, entries: List<ChatEntry>)
fun setSendOutcome(outcome: ChatSendOutcome?); val sentTexts: List<SentText>; val receivedAttachments: List<ChatAttachment>
fun setInterruptOutcome(outcome: ChatInterruptOutcome?); val interrupts: List<Interrupt>; val historyRequests: List<HistoryRequest>
fun holdChat(); fun releaseChat()
val workspaceCalls: List<String>                  // "create", "rename:<id>:<title>", "close:<id>"
fun setNextWorkspaceOutcome(outcome: WorkspaceControlOutcome); fun holdWorkspaceControl(); fun releaseWorkspaceControl()
val agentCloses: List<String>; fun setNextAgentCloseOutcome(outcome: WorkspaceControlOutcome)
val terminalCloses: List<TerminalCloseCall>; fun setNextTerminalCloseOutcome(outcome: WorkspaceControlOutcome)
```

  **Host rules.** Without `servesSessionsAndChat`, every chat call is `Remote("unsupported", "this host has no chat")`.

  | Call | Answer |
  | --- | --- |
  | `chatHistory(sessionId, beforeSeq, limit)` | records a `HistoryRequest`; `limit` outside 1..50 → `Remote("bad_request", …)`; unknown session → `Remote("not_found", "no such session")`. Otherwise the entries sorted by `seq` (before `beforeSeq` if given), the last `limit` of them, with `hasMore = older.size > limit`. The page is read when the call arrives and delivered after the hold |
  | `chatSend(sessionId, text, attachments = [])` | records a `SentText`, waits for the hold, then answers the preset, else `NOT_FOUND` for an unknown transcript, else `SUBMITTED`. Text bytes outside 1..16 384 (0..16 384 with attachment ids) → `Remote("bad_request", …)`, and nothing is recorded |
  | `chatSend(sessionId, text, uploading, progress)` | holds a per-session upload turn (`Mutex`) for the whole message. Without `acceptsAttachments` → `MessageUploadException(Remote("unsupported", "this host takes no attachments"))`. An attachment over 10 485 760 bytes → `MessageUploadException(Remote("too_large", …))`; an empty one → `MessageUploadException(Remote("bad_request", …))`; then nothing is recorded. Otherwise `progress(sentSoFar)` once per chunk of at most `ShellXLink.MAX_ATTACHMENT_CHUNK_BYTES`, counted over all attachments; then `receivedAttachments += uploading`, and the text-only rules |
  | `uploadAttachment(kind, name, data, progress)` | the same per-attachment rules; returns `"U<n>"` |
  | `chatInterrupt(sessionId, hard)` | records an `Interrupt`, waits for the hold, then answers the preset, else `NOT_FOUND`, else `SENT` |
  | `pushChat`, `resetChat` | broadcast `ChatPush.Upsert`, `ChatPush.Reset` in order. A push upserts the transcript by entry id; a reset replaces it |
  | `createWorkspace`, `renameWorkspace`, `closeWorkspace` | `Remote("unsupported", "this host takes no workspace control")` without the feature; rename with a title over 512 bytes → `Remote("bad_request", …)`. Otherwise `FakeMacWorkspaces.swift`'s rules: record, wait for the hold, take the next outcome; a create adds `"ws-new-<n>"` titled `"Workspace <n>"` with terminal `"ws-new-<n>-t1"` `"zsh"` (order 0, selected); `NOT_FOUND`; the last workspace is `REFUSED` |
  | `closeAgent(sessionId)` | `Remote("unsupported", "this host takes no agent control")` without the feature. Otherwise record, wait for the hold, take the next outcome; a listed session that has not ended turns `ENDED` with `stateSinceMs = lastActivityMs = nowMs()` and is broadcast; else `NOT_FOUND` |
  | `closeTerminal(workspaceId, terminalId)` | `Remote("unsupported", "this host takes no terminal control")` without the feature. Otherwise record, wait for the hold, take the next outcome; the terminal leaves its workspace, and the workspace goes with its last terminal; else `NOT_FOUND` |

- [ ] **Step 1: Write the failing tests** in `FakeMacChatTest`:

```kotlin
class FakeMacChatTest {
    // historyPagesFromTheNewestAndBeforeASeq: setHistory("s1", (1L..30L).map { chatEntry(it) }) → chatHistory("s1", null, 10)
    //   == ChatHistoryPage(entries 21..30, true); (21, 10) → 11..20, true; (11, 50) → 1..10, false; historyRequests has the three
    // historyRules: limit 0 and 51 → Remote("bad_request"); unknown "s9" → Remote("not_found"); servesSessionsAndChat = false → Remote("unsupported")
    // pushAndResetReachChatEntriesInOrder: pushChat("s1", [e7]); resetChat("s1", [e1]); pushChat("s1", [e2]) →
    //   chatEntries.take(3).toList() == [Upsert("s1", [e7]), Reset("s1"), Upsert("s1", [e2])]; history seqs [1, 2]
    // sendAndInterruptOutcomes: known transcript → SUBMITTED and SENT; "nope" → NOT_FOUND twice; presets answer as set;
    //   chatSend("s1", "") → Remote("bad_request"); "a".repeat(16_385) → Remote("bad_request"); sentTexts and interrupts recorded
    // heldChatCallsActAfterRelease: holdChat(); a chatSend("s1", "x") call stays waiting; releaseChat() → SUBMITTED
    // attachmentsUploadInChunksAndArriveWithTheMessage: chatSend("s1", "x", [ChatAttachment(FILE, "big", ByteArray(100_000)),
    //   ChatAttachment(IMAGE, "small.jpg", ByteArray(3))]) { progress += it } → SUBMITTED;
    //   progress == [45_000, 90_000, 100_000, 100_003]; receivedAttachments == both, in order; sentTexts == [SentText("s1", "x")]
    // attachmentRulesRefuseBeforeTyping: acceptsAttachments = false → MessageUploadException with cause Remote("unsupported");
    //   10_485_761 bytes → cause Remote("too_large"); 0 bytes → cause Remote("bad_request"); sentTexts empty each time
    // oneMessageUploadsAtATime: two concurrent messages "one" (a0..a4) and "two" (b0..b4), 50_000 bytes each →
    //   both SUBMITTED; receivedAttachments names are a0..a4 then b0..b4, or b0..b4 then a0..a4, never mixed
    // workspaceControlActsLikeTheMac: create → WorkspaceCreated(OK, "ws-new-1") and the list has "ws-new-1" with terminal
    //   "ws-new-1-t1"; renameWorkspace("ws-new-1", "Docs") == OK; rename "nope" == NOT_FOUND; closing the only workspace == REFUSED;
    //   with two, close == OK; a 513-byte title → Remote("bad_request"); setNextWorkspaceOutcome(FAILED) → FAILED and nothing changes;
    //   workspaceCalls == ["create", "rename:ws-new-1:Docs", "rename:nope:x", "close:ws-new-1", …] in call order
    // agentAndTerminalClose: closeAgent of a working "s1" == OK and sessionChanges brings s1 ENDED; closeAgent("nope") == NOT_FOUND;
    //   closeTerminal of a workspace's last terminal removes the workspace; a terminal of another workspace == NOT_FOUND;
    //   setNextTerminalCloseOutcome(REFUSED) → REFUSED; holdWorkspaceControl() also holds both closes until released
    // controlIsUnsupportedWithoutItsFeature: acceptsWorkspaceControl = false → createWorkspace throws Remote("unsupported");
    //   acceptsAgentClose = false → closeAgent Remote("unsupported"); acceptsTerminalClose = false → closeTerminal Remote("unsupported")
}
```

- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.demo.FakeMacChatTest'`.

  Expected: `Unresolved reference: setHistory`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): the fake Mac's chat and control"`.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run (green).** Run `gw :core:test --tests 'com.shellx.core.demo.*'`.

  Expected: PASS; `FakeMacChatTest` has 11 tests and `FakeMacTest` still has 11.
- [ ] **Step 6: Commit.** Run `git add shellx-android/core/src` and `git commit -m "feat(shellx-android): fake Mac chat, attachments and control"`.

---

### Task 10: Latency log and the connection to one Mac

**Files:**
- Create: `core/diagnostics/LatencyLog.kt`, `core/link/MachineEvent.kt`, `core/link/MachineConnection.kt`
- Create (test kit): `core-test/testing/EventLog.kt`
- Test: `core-test/diagnostics/LatencyLogTest.kt`, `core-test/link/MachineConnectionTest.kt`

Reference: `ios/Diagnostics/LatencyLog.swift`, `ios/Link/{MachineEvent,MachineConnection}.swift`, `ios-tests/Support/AsyncTestSupport.swift` (`EventLog`).

**Interfaces:**
- Consumes: Tasks 3, 7 and 8; 3B's `LinkSession`.
- Produces:

```kotlin
// com.shellx.core.diagnostics
enum class LatencyMetric(val wire: String) {
    REPLY_ROUND_TRIP("replyRoundTrip"), PENDING_ARRIVAL("pendingArrival"), SESSION_CHANGE_ARRIVAL("sessionChangeArrival"),
    LAUNCH_TO_HOME("launchToHome"), LAUNCH_TO_WORKSPACE_LIST("launchToWorkspaceList"), FIRST_WORD("firstWord")
}
data class LatencySummary(val count: Int, val p50: Duration, val p95: Duration)
/** Thread-safe. Keeps the last WINDOW samples of each metric; logs "<wire> <ms> ms" through `sink`. */
class LatencyLog(sink: (String) -> Unit = CoreLog::log) {
    fun record(metric: LatencyMetric, duration: Duration)        // negative → ZERO
    fun summary(metric: LatencyMetric): LatencySummary?          // nearest-rank percentiles, as the Swift code
    companion object { const val WINDOW = 200 }
}
// com.shellx.core.link
sealed interface MachineEvent {
    data class State(val state: MachineLinkState) : MachineEvent
    data class Features(val features: Set<String>) : MachineEvent
    data class Pending(val set: PendingSet, val actionable: Boolean) : MachineEvent
    data class Sessions(val set: SessionSet, val supported: Boolean) : MachineEvent
    data class Workspaces(val set: WorkspaceSet, val supported: Boolean) : MachineEvent
    data class Chat(val sessionId: String, val entries: List<ChatEntry>) : MachineEvent
    data class ChatReset(val sessionId: String) : MachineEvent
    data object SignedOut : MachineEvent
}
/** Main-confined. The loop of MachineConnection.swift, run in `scope`. */
class MachineConnection(
    machine: PairedMachine, connector: MachineLinkConnecting, latency: LatencyLog, scope: CoroutineScope, clock: Clock,
    schedule: ReconnectSchedule = ReconnectSchedule.STANDARD, sleep: suspend (Duration) -> Unit = { delay(it) },
) {
    /** Every event in order. Single consumer: a Channel(UNLIMITED) as a Flow; it completes when the loop stops. */
    val events: Flow<MachineEvent>
    fun start()
    suspend fun stop()
    fun reconnectNow()
    suspend fun forceReconnect()
    /** Runs `body` on the live session; LinkCallException.Offline(machine.name) unless Online. */
    suspend fun <T> call(body: suspend (LinkSession) -> T): T
    suspend fun refreshWorkspaces()
}
// test kit: EventLog(events: Flow<MachineEvent>, scope: CoroutineScope) with the accessors of EventLog in AsyncTestSupport.swift
```

  Port notes for `MachineConnection`:
  - `lostAt` and `Offline.sinceMs` come from `clock.nowMs()`, and the latency samples use `clock.nowMs() - …Ms`.
  - The backoff wait is a child job of the loop (`coroutineScope { launch { sleep(delay) } }`). `reconnectNow()` cancels that child, and the loop goes on at once.
  - Jitter is `Random.nextDouble(-1.0, 1.0)`.
  - The four streams are read as in Swift: three child `launch`es and `changes` collected in the loop. Cancel the children when `changes` completes.
  - Every path out of the loop closes the client (`finally`).

- [ ] **Step 1: Port the tests.**

  | Swift file | Tests | Kotlin |
  | --- | --- | --- |
  | `ios-tests/LatencyLogTests.swift` | 3 | `testRecordingFromManyThreads` records from 8 coroutines on `Dispatchers.Default` inside `runBlocking` |
  | `ios-tests/MachineConnectionTests.swift` | 18 | each connection is `MachineConnection(mac.machine, mac.connector { phone }, latency, backgroundScope, ManualClock(), sleep = …)`; `EventLog(connection.events, backgroundScope)` |

- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.diagnostics.*' --tests 'com.shellx.core.link.MachineConnectionTest'`.

  Expected: `Unresolved reference: MachineConnection`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): latency log and machine connection"`.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run (green).** Run the same command three times; every run must pass.

  Expected: PASS, 3 and 18 tests.
- [ ] **Step 6: Commit with the ledger.** Set row `6.2-8` to `done (3C)`. Then run `git add shellx-android/core/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): machine connection with reconnect and resync"`.

---

### Task 11: The hub: Macs, pending items, calls and chat pushes

**Files:**
- Create: `core/link/MachineModel.kt`, `core/link/HubState.kt`, `core/link/MachineHub.kt`, `core/pending/DecisionSending.kt`
- Create (test kit): `core-test/testing/HubRig.kt`
- Test: `core-test/link/MachineHubTest.kt`, `core-test/link/MachineHubUnpairTest.kt`

Reference: `ios/Link/{MachineModel,MachineHub}.swift`; `ios-tests/MachineHubTests.swift`, `MachineHubUnpairTests.swift`, `Support/HubRig.swift`.

**Interfaces:**
- Consumes: Tasks 3, 5, 6, 7 and 10.
- Produces (`com.shellx.core.link`):

```kotlin
data class MachineModel(
    val machine: PairedMachine, val name: String = machine.name, val state: MachineLinkState = MachineLinkState.Connecting,
    val pending: PendingSet = PendingSet(), val pendingActionable: Boolean = false,
    val sessions: SessionSet = SessionSet(), val sessionsSupported: Boolean = true,
    val workspaces: WorkspaceSet = WorkspaceSet(), val workspacesSupported: Boolean = false,
    val hostFeatures: Set<String> = emptySet(),
) { val id: String get() = machine.machineId }

/** One snapshot of everything the hub shows. Derived values are computed once per instance (lazy, NONE). */
data class HubState(
    val machines: List<MachineModel> = emptyList(),
    val isLoaded: Boolean = false,
    val storedDefaultMachineId: String? = null,
    val finishTimes: Map<String, Map<String, Long>> = emptyMap(),   // machineId → sessionId → when the phone saw it finish
    val handled: List<PendingKey> = emptyList(),                     // newest last, at most HANDLED_MEMORY
) {
    val defaultMachineId: String?                  // the stored id while paired, else the first Mac's
    val defaultMachineListedWorkspaces: Boolean
    val pendingItems: List<MachinePendingItem>      // sorted by (createdAtMs, machineId, requestId)
    val liveSessions: List<MachineSession>
    val reachableSessions: List<MachineSession>
    fun machine(id: String): MachineModel?
    fun leftWhileSynced(key: PendingKey): Boolean
    fun workspaceRows(machineId: String): List<WorkspaceRow>
    fun otherSessions(machineId: String): List<MachineSession>
    fun hasListedTerminal(ref: SessionRef): Boolean
    fun finishedSessionIds(machineId: String): Set<String>
    fun supportsWorkspaceControl(machineId: String): Boolean
    fun supportsAgentClose(machineId: String): Boolean
    fun supportsTerminalClose(machineId: String): Boolean
    fun acceptsAttachments(machineId: String): Boolean
}
data class MachineSessions(val machineId: String, val sessions: List<AgentSession>)
data class MachineStateUpdate(val machineId: String, val state: MachineLinkState)

// com.shellx.core.pending (DecisionSending.kt; DecisionCenter in Task 16 takes it)
/** Throws LinkCallException when nothing was sent, LinkClientException when the call failed. MachineHub is the real one. */
fun interface DecisionSending { suspend fun reply(key: PendingKey, decision: LinkDecision): ReplyOutcome }

/** Main-confined. Every paired Mac and its Link for the signed-in account (MachineHub.swift). Its own work runs in
 *  `scope`, a child of the scope it was given: stopAll() cancels it, as its last step. */
class MachineHub(
    vault: AccountVault, relay: RelayAccountCalling, connector: MachineLinkConnecting, latency: LatencyLog,
    settings: KeyValueStore, scope: CoroutineScope, clock: Clock,
    sleep: suspend (Duration) -> Unit = { delay(it) },
    onUnauthorized: suspend () -> Unit,
) : DecisionSending {
    companion object {
        val BACKGROUND_GRACE: Duration                 // 25 s (Task 12)
        const val DEFAULT_MACHINE_KEY = "shellx.defaultMachineID"
        const val HANDLED_MEMORY = 256
    }
    val scope: CoroutineScope                      // the hub's own scope: models of this account run in it
    val state: StateFlow<HubState>
    // the same names as Swift, reading state.value:
    val machines: List<MachineModel>; val isLoaded: Boolean; val finishTimes: Map<String, Map<String, Long>>
    var defaultMachineId: String?                   // set writes KeyValueStore DEFAULT_MACHINE_KEY (null removes)
    val defaultMachineListedWorkspaces: Boolean; val pendingItems: List<MachinePendingItem>
    val liveSessions: List<MachineSession>; val reachableSessions: List<MachineSession>
    fun leftWhileSynced(key: PendingKey): Boolean
    fun transcriptResets(ref: SessionRef): Int      // not observable (a plain counter)
    suspend fun start(); suspend fun stopAll()
    suspend fun add(machine: PairedMachine)         // MachineHub.AddException.NotSignedIn
    suspend fun unpair(machineId: String)
    suspend fun refreshGrants()
    override suspend fun reply(key: PendingKey, decision: LinkDecision): ReplyOutcome
    suspend fun chatHistory(ref: SessionRef, beforeSeq: Long?, limit: Int): ChatHistoryPage
    suspend fun chatSend(ref: SessionRef, text: String): ChatSendOutcome
    suspend fun chatInterrupt(ref: SessionRef, hard: Boolean): ChatInterruptOutcome
    /** Each call registers a Channel(UNLIMITED) subscriber at once and returns it as a Flow (consumeAsFlow). A collector
     *  that ends unregisters it (onCompletion), and so does a closed channel found at the next publish. Nothing is replayed. */
    fun chatUpdates(): Flow<ChatUpdate>
    fun sessionUpdates(): Flow<MachineSessions>
    fun stateUpdates(): Flow<MachineStateUpdate>
    internal val chatSubscriberCount: Int; internal val connectionCount: Int; internal val sessionSubscriberCount: Int
    internal suspend fun reportUnauthorized()
    sealed class AddException(message: String) : Exception(message) { class NotSignedIn : AddException("not_signed_in") }
}
// test kit (HubRig.kt): a signed-in hub over InMemorySecretStore (session u1/d1/tok-1/a@b.c, the Macs saved for u1),
//   FakeRelayAccount, FakeMacFleet, MemoryKeyValueStore, backgroundScope, and a ManualClock. It serves every Swift rig
//   that builds a hub (MachineHubTests' rig, HubRig.swift, the hubs of MachineHubWorkspaceTests and FakeMacDemoScriptTests):
class HubRig(val hub: MachineHub, val vault: AccountVault, val relay: FakeRelayAccount, val settings: MemoryKeyValueStore,
             val latency: LatencyLog, val clock: ManualClock, val backoff: ManualSleeper, val unauthorized: MutableList<Unit>,
             private val test: TestScope) {
    /** HubRig.swift's online(sessions:): eventually every Mac is online and liveSessions.size == sessions. */
    suspend fun online(sessions: Int): Boolean
}
/** The hub's sleep is `sleep` when given (MachineHubWorkspaceTests and FakeMacDemoScriptTests pass instantSleep),
 *  else sleeper.sleep (the Swift rigs' ManualSleeper). onUnauthorized appends to `unauthorized`. */
suspend fun TestScope.hubRig(macs: List<FakeMac>, saved: List<FakeMac>? = null, sleeper: ManualSleeper = ManualSleeper(),
    sleep: (suspend (Duration) -> Unit)? = null, settings: MemoryKeyValueStore = MemoryKeyValueStore(),
    clock: ManualClock = ManualClock(), connector: (MachineLinkConnecting) -> MachineLinkConnecting = { it },
    relay: (FakeRelayAccount) -> RelayAccountCalling = { it }, start: Boolean = false): HubRig
fun allOnline(hub: MachineHub): Boolean
```

  Port notes:
  - Keep the Swift names of the hub's private helpers `apply`, `revoke`, `detachAll` and `withLink` (and `workspaceCommand`, Task 13): plan 3G extends them by name.
  - Every change goes through `_state.update { … }`. A model is replaced with `copy(…)`.
  - In `refreshGrants`, the Swift identity check (`model === …`) becomes "the hub still has this `machineId` with the same `PairedMachine` it had when the request left".
  - `apply(.signedOut)` launches `reportUnauthorized()` in the hub's scope.
  - `DecisionSending` is created in this task, in `core/pending/DecisionSending.kt`, and `MachineHub.reply` overrides it.

- [ ] **Step 1: Port the tests.**
  - **`MachineHubTests.swift` → `MachineHubTest`** (13 tests). Port exactly these:
    - `testStartsOneConnectionPerPairedMachine`
    - `testPendingMergedAcrossMachinesSortedByCreation`
    - `testRefreshMarksMissingGrantRevokedAndRenames`
    - `testChatResetArrivesAsItsOwnUpdateInOrder`
    - `testChatAndSessionUpdatesMulticast`
    - `testCallsRouteToTheirMac`
    - `testAddSavesMachineAndReplacesSameID`
    - `testDefaultMachineFallsBackToFirst`
    - `testRefreshUnauthorizedReports`
    - `testStopAllWhileAddingStartsNothing`
    - `testRefreshSkipsMacRepairedMeanwhile`
    - `testRefreshAfterStopAllDoesNotReport`
    - `testLoadedOnceTheVaultWasRead`

    The other six go to Task 12, and `testUnauthorizedCallsCoordinator` to Task 14.
  - **Private helpers.** Port `GatedConnector` and `GatedGrantsRelay` from `MachineHubTests.swift:634-666` as private test classes. `GatedConnector` returns `LinkSession`; `GatedGrantsRelay` delegates every `RelayAccountCalling` member of Task 7 to the base fake.
  - **`MachineHubUnpairTests.swift` → `MachineHubUnpairTest`** (8 tests). `store.failWrites = .failed(status:)` becomes `SecretStoreException.Failed()`.
- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.link.MachineHub*'`.

  Expected: `Unresolved reference: MachineHub`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): hub machines, calls and pushes"`.
- [ ] **Step 4: Implement** `MachineModel.kt`, `HubState.kt` and `MachineHub.kt`, except the background, network, workspace-command and finish-detection members. Those stay out of the class until Tasks 12 and 13 add them. The pieces `apply` needs are ported now:
  - `finishTimes` comes from `SessionFinishDetector` in `noteFinishes`;
  - `rememberHandled`;
  - `publishChat`.
- [ ] **Step 5: Run (green).** Run the same command three times; all three runs must pass.

  Expected: PASS, 13 and 8 tests.
- [ ] **Step 6: Commit.** Run `git add shellx-android/core/src` and `git commit -m "feat(shellx-android): machine hub with merged pending items, calls and chat pushes"`.

---

### Task 12: The hub: background grace, frozen returns and network changes

**Files:**
- Modify: `core/link/MachineHub.kt`
- Test: `core-test/link/MachineHubLifecycleTest.kt`

Reference: `MachineHub.swift:383-443, 762-787`; `ios-tests/MachineHubTests.swift` (the six tests below).

**Interfaces:**
- Produces, on `MachineHub`:

```kotlin
/** Android: ProcessLifecycleOwner ON_START (3D). Cancels the grace. When the sessions were closed, reconnects every Mac;
 *  otherwise asks each Mac that is not online to retry now. Android addition: when the app went to the background
 *  BACKGROUND_GRACE or more ago by clock.monotonic but the grace never ran out (a frozen or dozing process), it first
 *  detaches every connection, as the grace would have, so every Mac reconnects from scratch. */
fun appDidBecomeActive()
/** Android: ON_STOP (3D launches it in the app scope). Waits BACKGROUND_GRACE with `sleep`; still in the background
 *  then → closes every session. Records clock.monotonic.markNow() for the rule above. */
suspend fun appDidEnterBackground()
/** Closes every session at once (iOS: background time expired). Android keeps it for a future signal. Today only tests call it. */
fun backgroundTimeExpired()
/** The default network changed (NetworkChangeFilter's onChange, 3D): each connection replaces its client at once. */
fun networkChanged()
```

- [ ] **Step 1: Port the tests and write the frozen-return tests (RF 2).**
  - **Ported** from `ios-tests/MachineHubTests.swift` into `MachineHubLifecycleTest`:
    - `testPathChangeForcesReconnect`
    - `testBackgroundClosesAfterGrace`
    - `testQuickReturnKeepsSessions`
    - `testStopAllWhileSuspendingStartsNothing`
    - `testPathChangeAbortsAttemptStillSyncing`
    - `testBackgroundExpiryClosesAtOnce`
  - **New tests:**

```kotlin
@Test fun aReturnAfterTheGraceReconnectsEvenWhenTheTimerNeverRan() { runTest {
    val a = FakeMac("MacBook Pro", backgroundScope); a.addPending(pendingItem("a1"))
    val rig = hubRig(listOf(a)); rig.hub.start()
    assertTrue(eventually { allOnline(rig.hub) && rig.hub.pendingItems.size == 1 })
    val background = backgroundScope.launch { rig.hub.appDidEnterBackground() }
    assertTrue(eventually { rig.backoff.waiting == listOf(MachineHub.BACKGROUND_GRACE) })
    rig.clock.advance(26.seconds)                    // frozen: the grace's own timer never fired
    rig.hub.appDidBecomeActive()
    assertTrue(eventually { a.connectCount == 2 && allOnline(rig.hub) && rig.hub.pendingItems.map { it.actionable } == listOf(true) })
    assertTrue(eventually { a.liveSessionCount == 1 })
    background.join()
} }
@Test fun aReturnWithinTheGraceByTheClockKeepsTheSessions() { runTest {
    val a = FakeMac("MacBook Pro", backgroundScope); val rig = hubRig(listOf(a)); rig.hub.start()
    assertTrue(eventually { allOnline(rig.hub) })
    val background = backgroundScope.launch { rig.hub.appDidEnterBackground() }
    assertTrue(eventually { rig.backoff.waiting == listOf(MachineHub.BACKGROUND_GRACE) })
    rig.clock.advance(24.seconds); rig.hub.appDidBecomeActive(); background.join()
    assertEquals(1, a.connectCount); assertEquals(1, a.liveSessionCount); assertEquals(1, rig.backoff.cancelled)
} }
```

- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.link.MachineHubLifecycleTest'`.

  Expected: `Unresolved reference: appDidEnterBackground`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): hub background grace and network changes"`.
- [ ] **Step 4: Implement.** Port the Swift bodies, then add the monotonic rule in `appDidBecomeActive`.
- [ ] **Step 5: Run (green).** Run three times. Expected: PASS, 8 tests each time.
- [ ] **Step 6: Commit with the ledger.** Add row `A-7`:
  - difference: "Coming back after 25 s or more in the background reconnects every Mac, measured with a clock that counts deep sleep, even when the grace timer never ran";
  - why: "Android freezes cached apps and Doze stops their timers, so the iPhone's background-task expiry has no Android signal";
  - Android: `core:link/MachineHub.kt` (`appDidBecomeActive`);
  - plan: 3C;
  - state: `differs (3C): by design`.

  Row `6.2-11` (3C and 3D) stays `todo`. Run `git add shellx-android/core/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): hub background grace, frozen returns and network changes"`.

---

### Task 13: The hub: workspaces, finished sessions and commands

**Files:**
- Modify: `core/link/MachineHub.kt`, `core/link/HubState.kt`
- Test: `core-test/link/MachineHubWorkspaceTest.kt`

Reference: `MachineHub.swift:157-250, 527-581, 682-699, 803-823`; `ios-tests/MachineHubWorkspaceTests.swift`.

**Interfaces:**
- Produces, on `MachineHub`. The same names as Swift; the queries read `state.value` through `HubState`:

```kotlin
fun workspaceRows(machineId: String): List<WorkspaceRow>
fun otherSessions(machineId: String): List<MachineSession>
fun hasListedTerminal(ref: SessionRef): Boolean
fun finishedSessionIds(machineId: String): Set<String>
fun markSeen(ref: WorkspaceRef)
fun markSeen(ref: SessionRef)
fun supportsWorkspaceControl(machineId: String): Boolean
fun supportsAgentClose(machineId: String): Boolean
fun supportsTerminalClose(machineId: String): Boolean
fun acceptsAttachments(machineId: String): Boolean
suspend fun refreshWorkspaces(machineId: String? = null)
suspend fun createWorkspace(machineId: String): WorkspaceCommandResult
suspend fun renameWorkspace(ref: WorkspaceRef, title: String): WorkspaceCommandResult
suspend fun closeWorkspace(ref: WorkspaceRef): WorkspaceCommandResult
suspend fun closeAgent(ref: SessionRef): WorkspaceCommandResult
suspend fun closeTerminal(machineId: String, workspaceId: String, terminalId: String): WorkspaceCommandResult
```

  `workspaceCommand` maps errors like this:
  - `LinkCallException` (any case) → `Offline`;
  - `LinkClientException.Remote` → `Failed`;
  - any other non-cancellation exception → `Unknown`;
  - a `CancellationException` is rethrown.

  The hub's `now` is `clock.nowMs()`, so a `now:` closure in the Swift tests becomes the rig's `ManualClock`.

- [ ] **Step 1: Port the tests.** Port `ios-tests/MachineHubWorkspaceTests.swift` (43 tests).
  - `makeHub(mac)` and `makeHub(macs:)` become `hubRig(…, sleep = instantSleep, start = true).hub`, because the Swift default sleep is `instantSleep`.
  - `makeHub(mac, sleep: s)` becomes `sleep = s`.
  - A `now:` closure becomes the rig's `ManualClock`: where the Swift test changes the date the closure returns, set `rig.clock.wallMs` at the same point.
- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.link.MachineHubWorkspaceTest'`.

  Expected: `Unresolved reference: workspaceRows`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): hub workspaces, finishes and commands"`.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run (green).** Run three times.

  Expected: PASS, 43 tests; `MachineHubTest` and `MachineHubLifecycleTest` still pass.
- [ ] **Step 6: Commit.** Run `git add shellx-android/core/src` and `git commit -m "feat(shellx-android): hub workspace rows, finished sessions and workspace commands"`.

---

### Task 14: The account: Google sign-in, sign-out, a refused token, account deletion

**Files:**
- Create: `core/account/AppPhase.kt`, `core/account/SignInException.kt`, `core/account/IdentityProviding.kt`, `core/account/AppCoordinator.kt`
- Create (test kit): `core-test/testing/FakeIdentityProvider.kt`, `core-test/testing/Wipers.kt` (`CountingWiper`, `FlakyWiper`, `GatedWiper`), `core-test/testing/CoordinatorRig.kt`
- Test: `core-test/account/{AppCoordinatorTest,AppCoordinatorGoogleTest,SignInExceptionTest}.kt`

Reference:
- `ios/Account/{AppCoordinator,AppPhase,SignInError}.swift`;
- `ios-tests/AppCoordinatorTests.swift`, `MachineHubTests.swift` (`testUnauthorizedCallsCoordinator`);
- 1C Task 3 (`IdentityProviding`), Task 4 (the `SignInError` table), Task 6 (sign-in order, `CoordinatorRig`) and Task 7 (delete account and the in-progress rule);
- S1 §6.3 (`switch_from_signed_in_device`, keep the key and the Macs after a 401) and §6.8.

**Interfaces:**
- Consumes: Tasks 6, 7, 11 and 12.
- Produces (`com.shellx.core.account`):

```kotlin
sealed interface AppPhase {
    data object Launching : AppPhase
    data class SignedOut(val expired: Boolean) : AppPhase
    data class SignedIn(val email: String) : AppPhase
}
sealed class SignInException(message: String) : Exception(message) {
    class InvalidCredentials : SignInException("invalid_credentials")
    class RateLimited : SignInException("rate_limited")
    class Network : SignInException("network")
    data class Server(val code: String) : SignInException("server")
    class LocalWipePending : SignInException("local_wipe_pending")
    class Cancelled : SignInException("cancelled")
    class SwitchFromSignedInDevice : SignInException("switch_from_signed_in_device")
    class ReauthRequired : SignInException("reauth_required")
    class ProviderUnavailable : SignInException("provider_unavailable")
    class ProviderFailed : SignInException("provider_failed")
    companion object {
        /** First match wins: Http(401, "invalid_credentials") → InvalidCredentials; Http(401, "reauth_required") →
         *  ReauthRequired; Http(409, "switch_from_signed_in_device") → SwitchFromSignedInDevice; Http(429, _) →
         *  RateLimited; Http(_, code) → Server(code); BadResponse → Server("bad_response"); IOException → Network;
         *  IdentityProviderException Cancelled / NotConfigured / Failed → Cancelled / ProviderUnavailable / ProviderFailed;
         *  else Server("unknown"). */
        fun of(error: Throwable): SignInException
    }
}
/** The phone's identity provider (Contract addition; 3D implements it with Credential Manager,
 *  GetSignInWithGoogleOption, serverClientId = the "Web" client, setNonce(nonce), S1 §6.7). */
interface IdentityProviding {
    /** Google's ID token for a sign-in carrying the relay's raw `nonce`. Throws IdentityProviderException. */
    suspend fun googleIdToken(nonce: String): String
}
sealed class IdentityProviderException(message: String) : Exception(message) {
    class Cancelled : IdentityProviderException("cancelled")         // the user closed Google's sheet
    class NotConfigured : IdentityProviderException("not_configured")
    class Failed : IdentityProviderException("failed")
}
/** Every call throws IdentityProviderException.NotConfigured (the demo, tests that sign in no other way). */
class UnavailableIdentityProvider : IdentityProviding

/** Main-confined. Every action runs through runDetached in `scope` (Global Constraints). */
class AppCoordinator(
    vault: AccountVault, relay: RelayAccountCalling, identity: IdentityProviding, deviceName: String,
    wipers: List<LocalDataWiping>, pendingWipeSettings: KeyValueStore, scope: CoroutineScope,
    makeHub: () -> MachineHub,
) {
    val phase: StateFlow<AppPhase>                    // starts Launching
    val hub: StateFlow<MachineHub?>                   // non-null exactly while signed in
    suspend fun launch()
    suspend fun protectedDataBecameAvailable()        // Android: call on every ON_START (3D)
    suspend fun signInWithGoogle()                    // throws SignInException
    suspend fun signOut()
    suspend fun handleUnauthorized()
    suspend fun deleteAccount()                       // throws SignInException
    companion object { const val PENDING_WIPE_KEY = "shellx.localWipePending" }
}
```

  The rules port `AppCoordinator.swift`, with these Android changes:
  - **`signInWithGoogle()`**, in this order:
    1. `guard retryPendingWipe() else throw LocalWipePending()`;
    2. `vault.phoneKey()` (failure → `Server("keychain")`);
    3. `relay.nonce()`;
    4. `identity.googleIdToken(nonce)`;
    5. `relay.signInWithGoogle(idToken, nonce, deviceName, key.publicKey)`;
    6. `completeSignIn`: the other-owner wipe and the store part of Swift's `signIn(email:password:)` (`AppCoordinator.swift:81-102`), storing `StoredSession(userId, deviceId, token, signIn.email)`.

    Every error goes through `SignInException.of`.
  - **`signOut()`** also calls `relay.unsetPushToken(token)` (best effort) after the unpairs and before `relay.logout(token)` (contracts §8). Put the local part of the sign-out in one private function that `deleteAccount` reuses: write the marker, `vault.wipe()`, run the wipers, clear the marker.
  - **`deleteAccount()`** (S1 §6.8, 1C Task 7, Google only):
    1. no stored session → `Server("signed_out")`;
    2. `relay.nonce()`, then `identity.googleIdToken(nonce)`;
    3. with a private `accountChangeInProgress` flag set, `relay.deleteAccount(idToken, nonce, token)`;
    4. stop the hub;
    5. the local part of `signOut()`, with no unpair, push or logout call;
    6. `phase = SignedOut(false)`, then clear the flag.

    **On failure:** clear the flag. `Http(401, "unauthorized")` → `handleUnauthorized()`, then throw `Server("unauthorized")`. Otherwise, when a 401 was remembered during the call → `handleUnauthorized()`. Then throw `SignInException.of(error)`; the hub and the session stay.
  - **`handleUnauthorized()`** while the flag is set only remembers that a 401 came, and returns.
- Produces (test kit):
  - `class FakeIdentityProvider : IdentityProviding`, with `var googleResult: Result<String> = Result.success("google-id-token")` and `val googleNonces: List<String>`;
  - the three wipers, ported from `AppCoordinatorTests.swift:9-65`;
  - `class CoordinatorRig(val store: InMemorySecretStore, val vault: AccountVault, val relay: FakeRelayAccount, val identity: FakeIdentityProvider, val wiper: CountingWiper, val pendingSettings: MemoryKeyValueStore, val coordinator: AppCoordinator)`;
  - `suspend fun TestScope.coordinatorRig(macs: List<FakeMac> = emptyList(), extraWipers: List<LocalDataWiping> = emptyList(), store: InMemorySecretStore = InMemorySecretStore(), pendingSettings: MemoryKeyValueStore = MemoryKeyValueStore()): CoordinatorRig`.
    - The device name is `"Phu's Pixel"` and the wipers are `extraWipers + wiper`.
    - The coordinator and its hubs run in `backgroundScope`.
    - `makeHub` builds `MachineHub(vault, relay, FakeMacFleet(macs) { vault.phoneKey() }, LatencyLog(), MemoryKeyValueStore(), backgroundScope, ManualClock(), instantSleep) { coordinator.handleUnauthorized() }`. The coordinator is reached through a `lateinit` holder, as `CoordinatorBox` in `MachineHubTests.swift:668-672`.
  - In the ported Swift tests, a coordinator built by hand (the relaunches in `AppCoordinatorTests.swift`) gets `backgroundScope` too.

- [ ] **Step 1: Port the tests and write the Android ones.**
  - **`AppCoordinatorTests.swift` → `AppCoordinatorTest`** (14 tests, plus `testUnauthorizedCallsCoordinator` from `MachineHubTests.swift`: 15 in all). Translate the password calls to Google:
    - `relay.setLogin(.success(account))` becomes `relay.setGoogleSignIn(Result.success(AccountSignIn(account, "a@b.c")))`, and `.failure(x)` becomes `Result.failure(x)`.
    - `signIn(email: E, password: _)` becomes `signInWithGoogle()`. The fake's sign-in answers with email `E`: set it with `setGoogleSignIn` before each call that uses another email.
    - A `.login(email:deviceName:clientKey:)` call in an expected list becomes `Nonce, SignInWithGoogle("google-id-token", "nonce-1", "Phu's Pixel", key.hex())`.
    - `testSignOutUnpairsLogsOutAndWipes` expects `[Machines("tok-1"), Unpair("g1", "tok-1"), Unpair("g2", "tok-1"), UnsetPushToken("tok-1"), Logout("tok-1")]`.
    - `testSignOutWipesEvenWhenRelayUnreachable` also sets an error for `UNSET_PUSH_TOKEN`.
    - In `testSignInMapsInvalidCredentialsAndRateLimit`, `URLError` becomes `IOException`.
  - **`AppCoordinatorGoogleTest`**, written fresh. `google = AccountSignIn(AccountSession("u1", "d1", "tok-g"), "g@example.com")`. Each comment line is one `@Test`:

```kotlin
class AppCoordinatorGoogleTest {
    // googleSignInSendsTheNonceTheTokenAndThePhoneKey (1C): calls == [Nonce, SignInWithGoogle("google-id-token", "nonce-1",
    //   "Phu's Pixel", vault.phoneKey().publicKey.hex())]; identity.googleNonces == ["nonce-1"];
    //   vault.session() == StoredSession("u1", "d1", "tok-g", "g@example.com"); phase == SignedIn("g@example.com"); hub != null
    // googleSignInCancelledChangesNothing: googleResult = failure(IdentityProviderException.Cancelled()) → SignInException.Cancelled;
    //   calls == [Nonce]; phase == SignedOut(false); hub == null; then googleResult = success → the next sign-in works
    // googleSignInErrorsMap: relay failures Http(409, "switch_from_signed_in_device") / Http(401, "invalid_credentials") /
    //   Http(429, "rate_limited") / IOException → SwitchFromSignedInDevice / InvalidCredentials / RateLimited / Network;
    //   identity failures NotConfigured / Failed → ProviderUnavailable / ProviderFailed (assertSameCase)
    // googleSignInAsAnotherAccountWipesTheOldHistory: vault.setMachines([m0], "someone-else") → wiper.wipes == 1;
    //   machines == []; machinesOwner == "u1"
    // pendingWipeBlocksGoogleSignInBeforeAnyRelayCall: a FlakyWiper and pendingSettings.putBoolean(PENDING_WIPE_KEY, true)
    //   → LocalWipePending; calls == []
    // signOutDeletesThePushTokenBeforeLoggingOut: signed in; signOut() → calls end with [UnsetPushToken("tok-g"), Logout("tok-g")]
    // deleteAccountReauthenticatesDeletesAndWipesLikeSignOut: session "tok-old" stored, launch(); googleResult = "google-fresh"
    //   → calls == [Nonce, DeleteAccount("google-fresh", "nonce-1", "tok-old")] (no unpair, push or logout);
    //   every SecretItem reads null; wiper.wipes == 1; marker false; phase == SignedOut(false); hub == null
    // cancelledOrRefusedDeleteKeepsEverything: Cancelled → SignInException.Cancelled, calls == [Nonce];
    //   setError(Http(401, "reauth_required"), DELETE_ACCOUNT) → ReauthRequired, session token still "tok-old", the same hub
    // deleteWithARefusedTokenSignsOutAsExpired: setError(Http(401, "unauthorized"), DELETE_ACCOUNT) → Server("unauthorized");
    //   phase == SignedOut(true); vault.machines() still has the Mac
    // unauthorizedDuringDeleteEndsSignedOutNotExpired: setHook({ coordinator.handleUnauthorized() }, DELETE_ACCOUNT)
    //   → deleteAccount() succeeds; phase == SignedOut(false)
    // deleteWithoutASessionIsSignedOut: no stored session → Server("signed_out"); calls == []
    // aCancelledSignOutStillWipes (RF 1): signed in; setHook({ gate.wait() }, LOGOUT); val caller = launch { coordinator.signOut() };
    //   eventually { gate.waiting == 1 }; caller.cancelAndJoin(); gate.open() → eventually { phase == SignedOut(false) };
    //   every SecretItem reads null; wiper.wipes == 1
}
```

  - **`SignInExceptionTest.relayAndProviderErrorsMap`**: the table of 1C Task 4, minus `email_in_use` and `identity_in_use` (which Android never receives), with `IOException` for `URLError`. Expected: 11 cases, each checked with `assertSameCase`.
- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.account.*'`.

  Expected: `Unresolved reference: AppCoordinator`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): Google sign-in, sign-out and account deletion"`.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run (green).** Expected: PASS.
  - `AppCoordinatorTest` has 15 tests;
  - `AppCoordinatorGoogleTest` has 12;
  - `SignInExceptionTest` has 1.
- [ ] **Step 6: Commit with the ledger.** Add row `A-8`:
  - difference: "Sign-out also deletes this phone's FCM token on the relay before logging out";
  - why: "Contracts §8; the iPhone relies on logout alone";
  - Android: `core:account/AppCoordinator.kt`;
  - plan: 3C;
  - state: `differs (3C): by design`.

  Run `git add shellx-android/core/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): account coordinator with Google sign-in and account deletion"`.

---

### Task 15: Pairing with a Mac

**Files:**
- Create in `core/pairing/`: `PairingFailure.kt`, `PairingInbox.kt`, `PairingModel.kt`, `PairingScanFilter.kt`, `SheetPresence.kt`
- Test in `core-test/pairing/`: `PairingModelTest.kt`, `PairingInboxTest.kt`, `PairingScanFilterTest.kt`, `SheetPresenceTest.kt`

Reference: `ios/Pairing/*.swift`; `ios-tests/{PairingModelTests,PairingInboxTests,PairingScanFilterTests,SheetPresenceTests}.swift`.

**Interfaces:**
- Consumes: Tasks 3 (`LinkFailure`), 6, 7 and 11 (`hub.add`, `hub.reportUnauthorized()`).
- Produces (`com.shellx.core.pairing`):

```kotlin
sealed interface PairingFailure {
    data object NotShellXCode : PairingFailure; data object NeedsUpdate : PairingFailure; data object DamagedCode : PairingFailure
    data object Denied : PairingFailure;        data object Expired : PairingFailure;     data object OtherAccount : PairingFailure
    data object Network : PairingFailure;       data class Server(val code: String) : PairingFailure
    companion object {
        /** PairingOfferException BadUri / UnsupportedVersion / BadField → NotShellXCode / NeedsUpdate / DamagedCode;
         *  PhonePairingException Denied / Expired → Denied / Expired; Http(_, "machine_not_found") → OtherAccount;
         *  IOException → Network; Http(_, code) → Server(code); BadResponse → Server("bad_response");
         *  SecretStoreException → Server("keychain"); MachineHub.AddException.NotSignedIn → Server("signed_out");
         *  else Server("unknown"). */
        fun of(error: Throwable): PairingFailure
    }
}
/** Main-confined. Holds the newest shellx-link URL in memory until a signed-in screen takes it (Android: the
 *  shellx-link intent filter, 3D). */
class PairingInbox {
    val hasLink: StateFlow<Boolean>
    fun receive(url: String): Boolean              // scheme compared case-insensitively
    fun take(): String?
    fun take(over: SheetPresence): String?
    companion object { const val SCHEME = "shellx-link" }
}
class SheetPresence { val isAnyOpen: StateFlow<Boolean>; fun opened(); fun closed() }
/** Mutable (Conventions). */
class PairingScanFilter {
    sealed interface Verdict { data class Pairing(val text: String) : Verdict; data object NotShellX : Verdict; data object Ignored : Verdict }
    fun accept(payload: String): Verdict
    companion object { fun isPairingText(text: String): Boolean }
}
/** Main-confined. */
class PairingModel(hub: MachineHub, relay: RelayAccountCalling, vault: AccountVault, scope: CoroutineScope) {
    sealed interface Step {
        data object Idle : Step; data class Confirm(val machineName: String) : Step
        data class WaitingForMac(val machineName: String) : Step; data class Paired(val machineName: String) : Step
        data class Failed(val failure: PairingFailure) : Step
    }
    val step: StateFlow<Step>
    fun begin(uri: String)
    suspend fun confirm()
    fun cancel()
    companion object { internal fun lowercasingScheme(text: String): String }
}
```

  `confirm()` uses this algorithm (Kotlin cancellation discards the result of a cancelled coroutine, so Swift's "take the late approval, then withdraw it" needs an explicit form):
  1. Unless the step is `Confirm(name)` and a code is held, return. Set the step to `WaitingForMac(name)`.
  2. `val job = scope.launch(start = CoroutineStart.UNDISPATCHED) { attempt(uri, name) }`; `attempt = job`; then `job.join()`. Cancelling the caller only ends the `join`; the attempt goes on.
  3. In `attempt`:
     - Read the phone key and the token; no token → `AddException.NotSignedIn()`. Call `relay.pair(uri, key.publicKey, token)`.
     - A `CancellationException` is rethrown. Any other error: when `attempt === thisJob`, call `fail(error)`, then return.
  4. Once `pair` returned, if `attempt !== thisJob` or `!isActive` (`cancel()` or a newer code came meanwhile), call `withdraw(approval)` inside `withContext(NonCancellable)`, then return.
  5. Call `withContext(NonCancellable) { hub.add(approval.machine) }`. On failure, withdraw (NonCancellable); then, when `attempt === thisJob`, call `fail(error)`; return.
  6. When `attempt === thisJob`, finish with `Paired(approval.machine.name)`.

  `cancel()` cancels `attempt`, clears it and the held code, and sets the step to `Idle`. `fail` reports `hub.reportUnauthorized()` when `LinkFailure.of(error) == SIGNED_OUT`.

- Produces (private to `PairingModelTest`; a port of its Swift `Rig`):

```kotlin
class PairingRig(val model: PairingModel, val hub: MachineHub, val vault: AccountVault, val relay: FakeRelayAccount,
                 val approval: ManualSleeper, val store: InMemorySecretStore)
/** Session u1/d1/tok-1 stored, `saved` Macs saved; FakeRelayAccount(sleep = approval.sleep), wrapped by `relay`; a
 *  started hubRig-style hub over FakeMacFleet(macs) with instantSleep; PairingModel(hub, relay(fake), vault, backgroundScope). */
suspend fun TestScope.pairingRig(macs: List<FakeMac>, saved: List<FakeMac> = emptyList(),
                                 relay: (FakeRelayAccount) -> RelayAccountCalling = { it }): PairingRig
```

- [ ] **Step 1: Port the tests and write the cancellation test (RF 1).**
  - **Ported files.**

    | Swift file | Tests | Kotlin |
    | --- | --- | --- |
    | `ios-tests/PairingModelTests.swift` | 15 | port `HeldPairRelay` as a private class that waits on a `Gate`, then delegates to the base `FakeRelayAccount` (all Task 7 members); `PairingInbox.receive(URL)` takes the URL's string |
    | `ios-tests/PairingInboxTests.swift` | 5 | |
    | `ios-tests/PairingScanFilterTests.swift` | 5 | |
    | `ios-tests/SheetPresenceTests.swift` | 1 | |

  - **New test:**

```kotlin
@Test fun cancellingTheCallerOfConfirmStillSavesTheMac() { runTest {
    val mac = FakeMac("MacBook Pro", backgroundScope); val rig = pairingRig(listOf(mac))
    rig.relay.setApprovalDelay(1.seconds); rig.model.begin(mac.pairingCode())
    val caller = launch { rig.model.confirm() }
    assertTrue(eventually { rig.approval.waiting.size == 1 })
    caller.cancelAndJoin()                                    // the screen went away
    rig.approval.release()
    assertTrue(eventually { rig.model.step.value == PairingModel.Step.Paired("MacBook Pro") })
    assertEquals(listOf(mac.machine), rig.vault.machines())
    assertTrue(eventually { rig.hub.machines.singleOrNull()?.state == MachineLinkState.Online })
} }
```

- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.pairing.*'`.

  Expected: `Unresolved reference: PairingModel`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): pairing model, inbox and scan filter"`.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run (green).** Expected: PASS, with 16, 5, 5 and 1 tests.
- [ ] **Step 6: Commit.** Run `git add shellx-android/core/src` and `git commit -m "feat(shellx-android): pairing with a Mac"`.

---

### Task 16: Decisions on pending items and the pending sheets

**Files:**
- Create: `core/pending/DecisionCenter.kt`, `core/pending/PendingSheetModel.kt`
- Create (test kit): `core-test/testing/PendingRig.kt` (`PendingRig`, `ScriptedSender`)
- Test: `core-test/pending/DecisionCenterTest.kt`, `core-test/pending/PendingSheetModelTest.kt`

Reference: `ios/Pending/{DecisionCenter,PendingSheetModel}.swift`; `ios-tests/{DecisionCenterTests,PendingSheetModelTests}.swift`, `Support/PendingRig.swift`.

**Interfaces:**
- Consumes: `DecisionSending` and `MachineHub` (Task 11), Task 4's `DecisionStatus` and `DecisionFailure`, `LatencyLog` (Task 10).
- Produces (`com.shellx.core.pending`):

```kotlin
data class DecisionCenterState(
    val status: Map<PendingKey, DecisionStatus> = emptyMap(),
    val dismissed: Set<PendingKey> = emptySet(),
    val lingering: Map<PendingKey, MachinePendingItem> = emptyMap(),
)
/** Main-confined. send and retry run through runDetached in `scope`; the linger timers also run there. */
class DecisionCenter(sender: DecisionSending, latency: LatencyLog, scope: CoroutineScope, clock: Clock,
                     sleep: suspend (Duration) -> Unit = { delay(it) }) {
    val state: StateFlow<DecisionCenterState>
    val status: Map<PendingKey, DecisionStatus>
    suspend fun send(decision: LinkDecision, key: PendingKey)
    fun sync(pendingItems: List<MachinePendingItem>)
    suspend fun retry(key: PendingKey)
    fun visibleItems(items: List<MachinePendingItem>): List<MachinePendingItem>   // reads only
    companion object { const val MAX_FEEDBACK_BYTES = 4096; val HANDLED_ELSEWHERE_LINGER: Duration }   // 2 s
}
data class PendingSheetState(val ownResult: DecisionStatus? = null, val sending: Boolean = false)
/** Main-confined. Derived getters read state, hub.state and center.state. */
class PendingSheetModel(val key: PendingKey, hub: MachineHub, center: DecisionCenter) {
    enum class LinkNote { RECONNECTING, OFFLINE, NEEDS_PAIRING, NEEDS_UPDATE }
    val opened: MachinePendingItem?
    val state: StateFlow<PendingSheetState>
    val current: MachinePendingItem?; val status: DecisionStatus?; val actionable: Boolean
    val handledElsewhere: Boolean; val linkNote: LinkNote?; val canSend: Boolean
    suspend fun send(decision: LinkDecision)
}
```

- Produces (test kit, ports of `Support/PendingRig.swift`):

```kotlin
/** Each call takes the next answer, and the last one repeats. With a gate, every call waits on it first. */
class ScriptedSender(answers: List<Answer>) : DecisionSending {
    sealed interface Answer {
        data class Outcome(val outcome: ReplyOutcome) : Answer
        data class Failure(val error: Exception) : Answer
    }
    val calls: List<Pair<PendingKey, LinkDecision>>
    var gate: Gate?
}
/** A started hubRig (backoff = its ManualSleeper) and a DecisionCenter(hub, latency, backgroundScope, clock, linger.sleep). */
class PendingRig(val hub: MachineHub, val center: DecisionCenter, val latency: LatencyLog, val backoff: ManualSleeper,
                 val linger: ManualSleeper, private val test: TestScope) {
    fun key(mac: FakeMac, requestId: String): PendingKey
    suspend fun synced(count: Int): Boolean           // eventually: every Mac online, `count` items, all actionable
    val shown: List<MachinePendingItem>               // center.sync(hub.pendingItems), then center.visibleItems(hub.pendingItems)
    val visibleIds: List<String>
}
suspend fun TestScope.pendingRig(macs: List<FakeMac>): PendingRig
```

  The round trip is measured with `clock.monotonic.markNow()`. `failure(error)` maps:
  - `LinkCallException.Offline`, `NeedsPairing` and `LinkClientException.SessionClosed` → `OFFLINE`;
  - `LinkClientException.Remote` and `LinkCallException.UnknownMachine` → `REJECTED`;
  - else → `NO_ANSWER`.

  The one resend happens on `LinkClientException.TimedOut`.

- [ ] **Step 1: Port the tests and write the cancellation test (RF 1).**
  - **Ported files.** `ScriptedSender` and `Gate` come from the kit.

    | Swift file | Tests |
    | --- | --- |
    | `ios-tests/DecisionCenterTests.swift` | 11 |
    | `ios-tests/PendingSheetModelTests.swift` | 8 |

  - **New test:**

```kotlin
@Test fun aCancelledCallerStillGetsItsStatus() { runTest {
    val sender = ScriptedSender(listOf(ScriptedSender.Answer.Outcome(ReplyOutcome.DELIVERED))).also { it.gate = Gate() }
    val center = DecisionCenter(sender, LatencyLog(), backgroundScope, ManualClock(), ManualSleeper().sleep)
    val key = PendingKey("m1", "r1"); center.sync(listOf(MachinePendingItem("m1", "Mac", permissionItem("r1"), true)))
    val caller = launch { center.send(LinkDecision.Permission(PermissionMode.ONCE), key) }
    runCurrent(); assertEquals(DecisionStatus.Sending, center.status[key])
    caller.cancelAndJoin(); sender.gate!!.open(); runCurrent()
    assertEquals(DecisionStatus.Done, center.status[key])
} }
```

- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.pending.DecisionCenterTest' --tests 'com.shellx.core.pending.PendingSheetModelTest'`.

  Expected: `Unresolved reference: DecisionCenter`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): decision center and pending sheets"`.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run (green).** Expected: PASS, 12 and 8 tests; the hub tests still pass.
- [ ] **Step 6: Commit with the ledger.** Set row `6.2-12` to `done (3C)`. Then run `git add shellx-android/core/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): decisions on pending items and pending sheets"`.

---

### Task 17: Chat thread, follow, send results and composer values

**Files:**
- Create: `core/agent/ChatThread.kt`, `core/agent/ChatFollow.kt`, `core/agent/AgentSendResult.kt`, `core/home/ComposerValidation.kt`, `core/composer/ComposerDraft.kt`, `core/composer/OutgoingAttachment.kt`, `core/storage/JsonCodec.kt`
- Test: `core-test/agent/{ChatThreadTest,ChatFollowTest}.kt`, `core-test/home/ComposerValidationTest.kt`, `core-test/composer/ComposerDraftTest.kt`

Reference: `ios/Agent/{ChatThread,ChatFollow,AgentSendResult}.swift`, `ios/Home/ComposerValidation.swift`, `ios/Composer/{ComposerDraft,OutgoingAttachment}.swift`.

**Interfaces:**
- Produces:

```kotlin
// com.shellx.core.storage
/** encode/decode one document; decode throws on anything it cannot read (the store then treats the file as corrupt). */
interface JsonCodec<T> { fun encode(value: T): JsonElement; fun decode(json: JsonElement): T }
// com.shellx.core.agent
/** Immutable. Normalized on construction exactly as ChatThread.swift's init (sorted by seq then arrival, one entry per
 *  id keeping ChatEntry.newer, capped to MAX_ENTRIES between transcript lines). equals/hashCode over (entries, hasMore). */
class ChatThread(entries: List<ChatEntry> = emptyList(), hasMore: Boolean = false) {
    val entries: List<ChatEntry>; val hasMore: Boolean
    fun upsert(incoming: List<ChatEntry>): ChatThread
    fun applyLatestPage(page: List<ChatEntry>, hasMore: Boolean): ChatThread
    fun applyOlderPage(page: List<ChatEntry>, hasMore: Boolean): ChatThread
    companion object {
        const val MAX_ENTRIES = 500
        /** {"entries":[{"id","rev","seq","role","kind","text","truncated"?,"tool_name"?,"ts_ms"}],"has_more"}, with
         *  role and kind as their wire strings; decode re-normalizes. */
        val CODEC: JsonCodec<ChatThread>
    }
}
/** Mutable (Conventions). */
class ChatFollow {
    val atBottom: Boolean; val hasUnseen: Boolean
    fun bottomVisible(visible: Boolean)
    fun newest(id: String?): Boolean
    fun jumpedToBottom()
}
sealed interface AgentSendResult {
    data class Refused(val validation: ComposerValidation) : AgentSendResult
    data class Sent(val outcome: ChatSendOutcome) : AgentSendResult
    data object Offline : AgentSendResult; data object NotSent : AgentSendResult
    data object AttachmentsUnsupported : AgentSendResult; data object NoAnswer : AgentSendResult
    val keepsDraft: Boolean                          // AgentSendResult.swift's table
}
// com.shellx.core.home
sealed interface ComposerValidation {
    data object Empty : ComposerValidation; data class Ok(val text: String) : ComposerValidation
    data class TooLong(val bytes: Int) : ComposerValidation; data object TooManyAttachments : ComposerValidation
    data class AttachmentTooLarge(val name: String) : ComposerValidation
    companion object {
        const val MAX_BYTES = 16_384
        fun of(text: String, attachmentCount: Int = 0): ComposerValidation
        fun check(attachments: List<OutgoingAttachment>): ComposerValidation?
        fun message(text: String, attachments: List<OutgoingAttachment>): ComposerValidation
    }
}
// com.shellx.core.composer
/** Never logged: toString is "OutgoingAttachment(id=<id>, kind=<kind>, <N bytes>)" (no name). ByteArray rule. */
data class OutgoingAttachment(val id: String = UUID.randomUUID().toString(), val kind: AttachmentKind, val name: String,
                              val data: ByteArray)
/** Immutable. The screen edits text and attachments with copy(). */
data class ComposerDraft(val text: String = "", val attachments: List<OutgoingAttachment> = emptyList(),
                         private val inFlight: Set<String>? = null) {
    val isSending: Boolean
    fun sendStarted(): ComposerDraft
    fun sendEnded(keepsDraft: Boolean): ComposerDraft
}
```

- [ ] **Step 1: Port the tests.**

  | Swift file | Tests |
  | --- | --- |
  | `ios-tests/ChatThreadTests.swift` | 5 |
  | `ios-tests/ChatFollowTests.swift` | 1 |
  | `ios-tests/ComposerValidationTests.swift` | 3 |
  | `ios-tests/ComposerDraftTests.swift` | 3 |

  In `ChatThreadTests`, a JSON round trip (`JSONDecoder().decode(… JSONEncoder().encode(thread))`) becomes `ChatThread.CODEC.decode(ChatThread.CODEC.encode(thread))`.
- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.agent.*' --tests 'com.shellx.core.home.ComposerValidationTest' --tests 'com.shellx.core.composer.*'`.

  Expected: `Unresolved reference: ChatThread`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): chat thread and composer values"`.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run (green).** Expected: PASS, with 5, 1, 3 and 3 tests.
- [ ] **Step 6: Commit with the ledger.** Set row `6.2-13` to `done (3C)`. Then run `git add shellx-android/core/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): chat thread, follow, send results and composer values"`.

---

### Task 18: The history store

**Files:**
- Create: `core/storage/StoreDocument.kt`, `core/storage/ConversationStore.kt`, `core/storage/ChatCopySweeper.kt`
- Test: `core-test/storage/ConversationStoreTest.kt`

Reference: `ios/Storage/*.swift`; `ios-tests/ConversationStoreTests.swift`.

**Interfaces:**
- Consumes: Tasks 6 (`LocalDataWiping`), 11 (`hub.chatUpdates()`), 17 (`JsonCodec`).
- Produces (`com.shellx.core.storage`):

```kotlin
sealed interface StoreDocument {
    data class Thread(val ref: SessionRef) : StoreDocument
    val kind: String                                     // "thread": the only name a log line carries
}
/** JSON files in `directory` (3D passes File(context.noBackupFilesDir, "ShellX"): nothing is backed up). Every
 *  operation holds one Mutex and does its file work in withContext(io). A thread is
 *  threads/<sha256-hex("<machineId>\u0000<sessionId>")>.json, replaced atomically (a temp file, then
 *  Files.move(…, ATOMIC_MOVE, REPLACE_EXISTING)), with its last-modified time set to clock.nowMs(). Only the
 *  newest maxThreads files are kept, and the file just written is never evicted. A corrupt file loads as null
 *  and is removed. */
class ConversationStore(directory: File, io: CoroutineDispatcher, clock: Clock, maxThreads: Int = 100) : LocalDataWiping {
    suspend fun <T> load(doc: StoreDocument, codec: JsonCodec<T>): T?
    suspend fun writer(): Writer
    suspend fun writer(claiming: StoreDocument): Writer
    class Writer internal constructor(/* store, epoch, claim */) {
        suspend fun <T> save(value: T, codec: JsonCodec<T>, doc: StoreDocument)
        suspend fun remove(doc: StoreDocument)
    }
    override suspend fun wipe()                          // the epoch moves even when the delete fails; the failure is thrown
}
/** Main-confined. Drops a session's stored copy at its Mac's chat.reset, until cancelled. */
class ChatCopySweeper(hub: MachineHub, store: ConversationStore) { suspend fun run() }
```

- [ ] **Step 1: Port the tests and add the I/O test (RF 3).**
  - **Ported**: `ios-tests/ConversationStoreTests.swift` into `ConversationStoreTest`, using a JUnit `@TempDir` directory, `io = StandardTestDispatcher(testScheduler)`, and a `Ticks` clock that implements `Clock`.
    - Do not port `testBackupExclusionIsSetAgainAfterWipe` or `testDirectoryExcludedFromBackup`. On Android, backup exclusion is the directory 3D chooses (S3 §7.3, `noBackupFilesDir`).
    - In `testFailedWipeThrowsButStillInvalidatesWriters`, set the permissions with `Files.setPosixFilePermissions` (`r-x------`, then back to `rwx------`).
    - `Doc` becomes a `data class Doc(val items: List<String>)` with a test `JsonCodec`.
  - **New test, `fileWorkRunsOnTheIoDispatcher`** (RF 3). It follows the vault test of Task 6, with a single-thread executor named `"store-io"`. A test `JsonCodec` records `Thread.currentThread().name` in `encode` and `decode`. Call `save`, `load`, `remove` and `wipe`. Assert that every recorded name is `"store-io"`.
- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.storage.*'`.

  Expected: `Unresolved reference: ConversationStore`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): history store"`.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run (green).** Expected: PASS, 11 tests.
- [ ] **Step 6: Commit.** Run `git add shellx-android/core/src` and `git commit -m "feat(shellx-android): history store with epochs, claims and eviction"`.

---

### Task 19: Attachment plumbing: hub send, upload progress, picks and reading rules

**Files:**
- Modify: `core/link/MachineHub.kt` (add `chatSend` with attachments)
- Create: `core/composer/UploadProgress.kt`, `core/composer/PendingPicks.kt`, `core/composer/AttachmentReader.kt`, `core/composer/AttachmentChecks.kt`
- Test: `core-test/composer/{UploadProgressTest,PendingPicksTest,AttachmentChecksTest}.kt`, `core-test/link/MachineHubAttachmentTest.kt`

Reference: `MachineHub.swift:467-521`; `ios/Composer/{UploadProgress,PendingPicks}.swift`; `shellx-ios/ShellX/UI/Composer/AttachmentPreparer.swift` (the size, empty and naming rules); `ios-tests/{AttachmentSendTests,PendingPicksTests}.swift`; `shellx-ios/ShellXTests/AttachmentPreparerTests.swift` (the rules only).

**Interfaces:**
- Produces:

```kotlin
// on MachineHub
/** As MachineHub.swift: `attachments` empty → chatSend(ref, text). Without the Mac's attachments feature →
 *  AttachmentSendException.Refused("unsupported") and nothing is sent. Otherwise one session.chatSend(sessionId, text,
 *  uploading = ChatAttachment(kind, name, data) each) { sent -> progress(if (total > 0) sent / total else 1.0) }.
 *  MessageUploadException whose cause is Remote(code) → Refused(code); any other MessageUploadException → UploadFailed();
 *  LinkClientException.Remote(code) → Refused(code); CancellationException propagates. A refusal logs
 *  "attach_send_failed count=<n> bytes=<total> <message>" (never a name or a byte). `progress` may run on any thread. */
suspend fun chatSend(ref: SessionRef, text: String, attachments: List<OutgoingAttachment>, progress: (Double) -> Unit): ChatSendOutcome
// com.shellx.core.composer
/** Main-confined. Port of UploadProgress.swift; each progress value hops to `scope` (scope.launch) before it is applied. */
internal class UploadProgress(scope: CoroutineScope) {
    val fraction: StateFlow<Double?>
    suspend fun <T> track(send: suspend (progress: (Double) -> Unit) -> T): T
}
/** Main-confined. Port of PendingPicks.swift; ids are UUID strings; reads run one at a time in `scope`. */
class PendingPicks(scope: CoroutineScope) {
    val ids: StateFlow<List<String>>
    val count: Int
    fun read(loads: List<suspend () -> OutgoingAttachment>, done: (Result<OutgoingAttachment>) -> Unit): List<String>
    fun cancel(id: String)
}
/** A picked photo or file (contracts §5; 3E implements it with the Photo Picker / OpenMultipleDocuments through
 *  ContentResolver, off the main thread, cancellable). */
data class AttachmentPick(val uri: String, val kind: AttachmentKind)
interface AttachmentReader {
    /** A photo is named AttachmentChecks.photoName(AttachmentChecks.photoExtension(mime), taken); a file keeps its display
     *  name. It checks the size first when the provider reports it (refuseIfTooLarge), then the bytes (checked).
     *  Throws AttachmentReadException. */
    suspend fun read(pick: AttachmentPick, taken: List<String>): OutgoingAttachment
}
sealed class AttachmentReadException(val name: String) : Exception("attachment_unreadable") {
    class TooLarge(name: String) : AttachmentReadException(name)
    class Unreadable(name: String) : AttachmentReadException(name)
}
object AttachmentChecks {
    /** Over ShellXLink.MAX_ATTACHMENT_BYTES → TooLarge(name); empty → Unreadable(name); else the attachment as picked. */
    fun checked(kind: AttachmentKind, name: String, data: ByteArray): OutgoingAttachment
    fun refuseIfTooLarge(name: String, size: Long?)       // size > MAX → TooLarge(name); null or ≤ MAX → nothing
    /** "photo-<n>.<extension>", with the first n from 1 that no name in `taken` has. */
    fun photoName(extension: String, taken: List<String>): String
    /** image/jpeg → "jpg", image/png → "png", image/heic and image/heif → "heic", image/gif → "gif", image/webp → "webp";
     *  anything else or null → "jpg". */
    fun photoExtension(mimeType: String?): String
}
```

- [ ] **Step 1: Port and write the tests.**
  - **`PendingPicksTest`**: port `ios-tests/PendingPicksTests.swift` (6 tests).
  - **`MachineHubAttachmentTest`**: port `testProgressCountsTheBytesOfEveryAttachment` from `ios-tests/AttachmentSendTests.swift` (1 test). `HubRig.make([mac], in: self)` becomes `hubRig(listOf(mac), start = true)`, and `rig.online(sessions: 1)` becomes `rig.online(1)`.
  - **`AttachmentChecksTest`** (new; the rules of `AttachmentPreparerTests.swift`):

```kotlin
class AttachmentChecksTest {
    @Test fun aPickedImageIsSentAsIs() { val b = ByteArray(3) { 7 }; val a = AttachmentChecks.checked(AttachmentKind.IMAGE, "photo-1.jpg", b)
        assertContentEquals(b, a.data); assertEquals("photo-1.jpg", a.name) }
    @Test fun overTenMiBIsRefusedWithItsName() {
        assertEquals("big.mov", assertFailsWith<AttachmentReadException.TooLarge> {
            AttachmentChecks.checked(AttachmentKind.FILE, "big.mov", ByteArray(10_485_761)) }.name)
        assertFailsWith<AttachmentReadException.TooLarge> { AttachmentChecks.refuseIfTooLarge("x", 10_485_761) }
        AttachmentChecks.refuseIfTooLarge("x", 10_485_760); AttachmentChecks.refuseIfTooLarge("x", null) }
    @Test fun anEmptyFileIsUnreadable() { assertEquals("empty.txt", assertFailsWith<AttachmentReadException.Unreadable> {
        AttachmentChecks.checked(AttachmentKind.FILE, "empty.txt", ByteArray(0)) }.name) }
    @Test fun photosAreNamedFromWhatTheyAre() {
        assertEquals("photo-1.jpg", AttachmentChecks.photoName("jpg", emptyList()))
        assertEquals("photo-3.png", AttachmentChecks.photoName("png", listOf("photo-1.png", "photo-2.png", "photo-1.jpg")))
        assertEquals(listOf("jpg", "png", "heic", "heic", "gif", "webp", "jpg", "jpg"), listOf("image/jpeg", "image/png",
            "image/heic", "image/heif", "image/gif", "image/webp", "application/pdf", null).map { AttachmentChecks.photoExtension(it) }) }
    @Test fun failuresNeverPrintTheBytes() { val a = OutgoingAttachment(kind = AttachmentKind.FILE, name = "secret.txt", data = ByteArray(4))
        assertFalse("secret" in a.toString()); assertTrue("4 bytes" in a.toString()) }
    @Test fun everyFailureSaysWhichAttachment() { listOf(AttachmentReadException.TooLarge("a.pdf"), AttachmentReadException.Unreadable("a.pdf"))
        .forEach { assertEquals("a.pdf", it.name) } }
}
```

  - **`UploadProgressTest`**. The second test is RF 4: it runs on a real single-thread "main" dispatcher, because the point is a progress call from another thread.

```kotlin
class UploadProgressTest {
    @Test fun fractionIsZeroThenFollowsUpwardAndIsNilAfter() { runTest {
        val upload = UploadProgress(backgroundScope); val gate = CompletableDeferred<Unit>()
        val sending = async { upload.track { progress -> progress(0.5); progress(0.25); progress(2.0); gate.await(); "done" } }
        runCurrent(); assertEquals(1.0, upload.fraction.value)
        gate.complete(Unit); assertEquals("done", sending.await()); runCurrent(); assertNull(upload.fraction.value)
    } }
    @Test fun progressFromAnotherThreadNeverOutlivesItsSend() {
        val main = Executors.newSingleThreadExecutor { Thread(it, "main") }.asCoroutineDispatcher()
        try { runBlocking(main) {
            val upload = UploadProgress(CoroutineScope(SupervisorJob() + main)); var late: ((Double) -> Unit)? = null
            val result = upload.track { progress ->
                late = progress
                withContext(Dispatchers.Default) { progress(0.5); progress(0.25) }
                withTimeout(5.seconds) { while (upload.fraction.value != 0.5) delay(1) }
                "done"
            }
            assertEquals("done", result); assertNull(upload.fraction.value)
            withContext(Dispatchers.Default) { late!!(0.9) }; delay(50); assertNull(upload.fraction.value)
        } } finally { main.close() }
    }
}
```

- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.composer.*' --tests 'com.shellx.core.link.MachineHubAttachmentTest'`.

  Expected: `Unresolved reference: UploadProgress`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): attachment plumbing"`.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run (green).** Expected: PASS.
  - `PendingPicksTest` has 6 tests;
  - `MachineHubAttachmentTest` has 1;
  - `AttachmentChecksTest` has 6;
  - `UploadProgressTest` has 2.
- [ ] **Step 6: Commit with the ledger.** Add row `A-9`:
  - difference: "A photo's file extension comes from the picked item's MIME type; the image bytes are not inspected";
  - why: "Android's Photo Picker reports a MIME type and has no ImageIO";
  - Android: `core:composer/AttachmentChecks.kt`;
  - plan: 3C;
  - state: `differs (3C): by design`.

  Run `git add shellx-android/core/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): attachment send, upload progress, picks and reading rules"`.

---

### Task 20: The agent screen: history, live entries, resets and saving

**Files:**
- Create: `core/agent/AgentThreadModel.kt`
- Test: `core-test/agent/AgentThreadModelTest.kt`

Reference: `ios/Agent/AgentThreadModel.swift`; `ios-tests/AgentThreadModelTests.swift`, `Support/HubRig.swift`.

**Interfaces:**
- Consumes: Tasks 11, 13, 17, 18 and 19.
- Produces (`com.shellx.core.agent`):

```kotlin
data class AgentThreadState(
    val thread: ChatThread = ChatThread(), val loading: Boolean = false, val loadingOlder: Boolean = false,
    val uploadProgress: Double? = null, val answeredNotFound: Boolean = false, val cacheRead: Boolean = false,
    val latestLoaded: Boolean = false, val latestFailed: Boolean = false, val olderFailed: Boolean = false,
)
/** Main-confined. `scope` runs its saves and hops; pass hub.scope, not viewModelScope (3E), so a save started when
 *  the screen leaves still finishes. Derived getters read state and hub.state. */
class AgentThreadModel(val ref: SessionRef, hub: MachineHub, store: ConversationStore, scope: CoroutineScope,
                       sleep: suspend (Duration) -> Unit = { delay(it) }) {
    enum class EmptyState { LOADING, NO_MESSAGES, OFFLINE, FAILED, GONE }
    enum class Older { NONE, LOADABLE, FAILED, ONLY_ON_MAC }
    val state: StateFlow<AgentThreadState>
    val thread: ChatThread; val loading: Boolean; val loadingOlder: Boolean; val uploadProgress: Double?
    val offline: Boolean; val session: MachineSession?; val machineName: String; val sessionGone: Boolean
    val ghost: MachineSession?; val pendingHere: List<MachinePendingItem>; val canStop: Boolean
    val olderOnlyOnMac: Boolean; val canLoadOlder: Boolean; val emptyState: EmptyState?; val older: Older
    suspend fun retry()
    suspend fun open()                    // once; later calls wait for the first
    suspend fun loadOlder()
    /** Follows the hub until cancelled (3E: while the screen is STARTED). */
    suspend fun run()
    /** Writes the copy now if it changed, in `scope`; returns the write's Job. Callable from onCleared(). */
    fun close(): Job
    fun save(): Job                       // the app left the foreground
    internal val isObserving: Boolean
    companion object { const val PAGE_SIZE = 50; val SAVE_DELAY: Duration }   // 500 ms
    // Task 21 adds send and stop.
}
```

- [ ] **Step 1: Port the tests.** Port `ios-tests/AgentThreadModelTests.swift` into `AgentThreadModelTest`, except `testSendMapsOutcomes` and `testStopSoftAndHard`, which go to Task 21. That leaves 19 tests.
  - The model is `AgentThreadModel(ref, rig.hub, rig.store, backgroundScope, timers.sleep)`.
  - `await model.close()` becomes `model.close().join()`.
  - `HubRig` gains the store: add `val store: ConversationStore` and a `seed: suspend (ConversationStore) -> Unit = {}` parameter to `hubRig`. `seed` runs before the hub starts.
  - The store is a `ConversationStore` over a fresh `kotlin.io.path.createTempDirectory("hub-rig").toFile()`, with `io = StandardTestDispatcher(testScheduler)` and the rig's clock.
  - `HubRig.make([mac], in: self, seed: s)` becomes `hubRig(listOf(mac), seed = s, start = true)`, and `rig.online(sessions: n)` becomes `rig.online(n)`.
- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.agent.AgentThreadModelTest'`.

  Expected: `Unresolved reference: AgentThreadModel`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): agent screen history, live entries and resets"`.
- [ ] **Step 4: Implement.** Port the Swift body. These pieces become Kotlin like this:
  - Swift `async let` becomes `coroutineScope { launch { … } }`.
  - `opening: Task` becomes a `Deferred` created in `scope`.
  - `pendingSave` and `writing` become `Job`s in `scope`: each new write `join()`s the previous one first.
- [ ] **Step 5: Run (green).** Run three times. Expected: PASS, 19 tests each time.
- [ ] **Step 6: Commit with the ledger.** Set row `6.2-16` to `done (3C)`. Then run `git add shellx-android/core/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): agent screen model with history, live entries and saved copies"`.

---

### Task 21: The agent screen: send, stop and attachments

**Files:**
- Modify: `core/agent/AgentThreadModel.kt`
- Test: `core-test/agent/AgentThreadSendTest.kt`

Reference: `AgentThreadModel.swift:277-318`; `ios-tests/AgentThreadModelTests.swift` (`testSendMapsOutcomes`, `testStopSoftAndHard`), `ios-tests/AttachmentSendTests.swift`.

**Interfaces:**
- Produces, on `AgentThreadModel`:

```kotlin
/** ComposerValidation.message first, then Offline at once, then the hub. LinkCallException.Offline / NeedsPairing →
 *  Offline; AttachmentSendException.Refused("unsupported") → AttachmentsUnsupported; any other
 *  AttachmentSendException → NotSent; CancellationException propagates; anything else → NoAnswer. A NOT_FOUND
 *  outcome marks the session gone. */
suspend fun send(text: String, attachments: List<OutgoingAttachment> = emptyList(), viaVoice: Boolean): AgentSendResult
suspend fun stop(hard: Boolean): ChatInterruptOutcome?
```

- [ ] **Step 1: Port the tests.**
  - From `AgentThreadModelTests.swift`, port `testSendMapsOutcomes` and `testStopSoftAndHard` (2 tests).
  - Port all of `ios-tests/AttachmentSendTests.swift` except `testProgressCountsTheBytesOfEveryAttachment` (ported in Task 19): 11 tests.
  - `HubRig.make` and `rig.online(sessions:)` translate as in Task 20. The model is `AgentThreadModel(ref, rig.hub, rig.store, backgroundScope, ManualSleeper().sleep)`.
  - `FractionLog` becomes a synchronized list.
  - In `testUploadProgressShowsUntilTheMacAnswers`, `Task.sleep(for: .milliseconds(50))` becomes `delay(50)` and `runCurrent()`.
- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.agent.AgentThreadSendTest'`.

  Expected: `Unresolved reference: send`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): agent screen send, stop and attachments"`.
- [ ] **Step 4: Implement.** `uploadProgress` comes from a private `UploadProgress(scope)` whose `fraction` is copied into `AgentThreadState.uploadProgress`.
- [ ] **Step 5: Run (green).** Run three times. Expected: PASS, 13 tests; `AgentThreadModelTest` still passes.
- [ ] **Step 6: Commit.** Run `git add shellx-android/core/src` and `git commit -m "feat(shellx-android): agent screen send, stop and attachments"`.

---

### Task 22: The home: focus groups, ended dismissals and gone removals

**Files:**
- Create: `core/home/HomeFocus.kt` (with `FocusItem`), `core/home/EndedDismissals.kt` (with `EndedDismissalStore`), `core/home/GoneRemovals.kt` (with `GoneRemovalStore`)
- Test: `core-test/home/{HomeFocusTest,EndedDismissalsTest,GoneRemovalsTest}.kt`

Reference: `ios/Home/{HomeFocus,EndedDismissals,GoneRemovals}.swift`; their tests.

**Interfaces:**
- Produces (`com.shellx.core.home`):

```kotlin
data class FocusItem(val session: MachineSession, val name: String, val question: String? = null, val finishedAtMs: Long? = null) {
    val id: SessionRef get() = session.ref
}
data class HomeFocus(val needsYou: List<FocusItem>, val running: List<FocusItem>, val justDone: List<FocusItem>,
                     val ended: List<FocusItem>) {
    val isQuiet: Boolean
    companion object {
        val JUST_DONE_FOR: Duration                       // 3 600 s
        val ENDED_FOR: Duration                           // 43 200 s
        val EMPTY: HomeFocus
        fun make(sessions: List<MachineSession>, pending: List<MachinePendingItem>, finished: Map<String, Map<String, Long>>,
                 dismissed: EndedDismissals = EndedDismissals.NONE, removed: GoneRemovals = GoneRemovals.NONE,
                 nowMs: Long, zone: ZoneId = ZoneId.systemDefault()): HomeFocus
        fun endedMs(session: AgentSession): Long?
        internal fun endedAge(ms: Long, nowMs: Long): Duration   // never negative
    }
}
/** Immutable. CODEC JSON: {"ends":{"<machineId>":{"<sessionId>":<endMs>}}}. */
class EndedDismissals {
    fun hides(session: MachineSession): Boolean
    fun dismiss(session: MachineSession): EndedDismissals
    fun pruned(nowMs: Long): EndedDismissals
    companion object { val NONE: EndedDismissals; val CODEC: JsonCodec<EndedDismissals> }
}
/** Main-confined. Reads the saved JSON text at construction (unreadable → NONE), pruned; saves after each change. */
class EndedDismissalStore(settings: KeyValueStore, clock: Clock) {
    val dismissals: StateFlow<EndedDismissals>
    fun dismiss(session: MachineSession)
    companion object { const val KEY = "shellx.dismissedEnded" }
}
/** Immutable. CODEC JSON: {"removals":{"<machineId>":{"<sessionId>":{"stamp":{"state","state_since_ms"?,"last_activity_ms"?},"removed_at_ms"}}}}. */
class GoneRemovals {
    data class Stamp(val state: AgentState, val stateSinceMs: Long?, val lastActivityMs: Long?) {
        companion object { fun of(session: AgentSession): Stamp }
    }
    fun hides(session: MachineSession): Boolean
    fun shown(sessions: List<MachineSession>): List<MachineSession>
    fun remove(session: MachineSession, atMs: Long): GoneRemovals
    fun pruned(nowMs: Long): GoneRemovals
    companion object { val KEPT_FOR: Duration; val NONE: GoneRemovals; val CODEC: JsonCodec<GoneRemovals> }  // 30 days
}
data class GoneRemovalState(val removals: GoneRemovals = GoneRemovals.NONE,
                            val knownGone: Map<SessionRef, GoneRemovals.Stamp> = emptyMap())
/** Main-confined. knownGone is never saved. */
class GoneRemovalStore(settings: KeyValueStore, clock: Clock) {
    val state: StateFlow<GoneRemovalState>
    val removals: GoneRemovals
    fun noteGone(session: MachineSession); fun canRemove(session: MachineSession): Boolean
    fun removable(sessions: List<MachineSession>): Set<SessionRef>; fun remove(session: MachineSession)
    companion object { const val KEY = "shellx.removedGone" }
}
```

- [ ] **Step 1: Port the tests.**

  | Swift file | Tests |
  | --- | --- |
  | `ios-tests/HomeFocusTests.swift` | 16 |
  | `ios-tests/EndedDismissalsTests.swift` | 19 |
  | `ios-tests/GoneRemovalsTests.swift` | 21 |

  - A `Date` becomes epoch ms.
  - A JSON round trip becomes `CODEC.decode(CODEC.encode(x))`.
  - Saved data is read and written with `settings.getString(KEY)` and `putString`.
  - `testUnreadableSavedDataStartsEmpty` stores `"not json"`.
- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.home.HomeFocusTest' --tests 'com.shellx.core.home.EndedDismissalsTest' --tests 'com.shellx.core.home.GoneRemovalsTest'`.

  Expected: `Unresolved reference: HomeFocus`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): home focus, ended dismissals and gone removals"`.
- [ ] **Step 4: Implement.** Port the grouping and ordering of `HomeFocus.make` exactly as `HomeFocus.swift:58-125`:
  - first the removed sessions are filtered out;
  - then the requests are matched to the newest waiting session, else the newest live one;
  - first match wins per session;
  - the three top lists are newest activity first, then by `(machineId, sessionId)`;
  - Ended is newest end first;
  - the top lists share one `SessionName.distinct` pass, and Ended has its own.
- [ ] **Step 5: Run (green).** Expected: PASS, 16, 19 and 21 tests.
- [ ] **Step 6: Commit with the ledger.** Set rows `6.2-1`, `6.2-3`, `6.2-4`, `6.2-5` and `6.2-6` to `done (3C)`. Then run `git add shellx-android/core/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): home focus groups, ended dismissals and gone removals"`.

---

### Task 23: The workspace screen

**Files:**
- Create: `core/workspaces/WorkspaceScreenModel.kt`
- Test: `core-test/workspaces/WorkspaceScreenModelTest.kt`

Reference: `ios/Workspaces/WorkspaceScreenModel.swift`; `ios-tests/WorkspaceScreenModelTests.swift`.

**Interfaces:**
- Produces (`com.shellx.core.workspaces`):

```kotlin
data class WorkspaceScreenState(val phase: WorkspaceScreenModel.Phase = WorkspaceScreenModel.Phase.WAITING,
    val selectedTerminalId: String? = null, val shownPaneClosed: Int = 0, val lastTabClosedHere: Boolean = false)
/** Main-confined. Derived getters read state and hub.state. reconcile() runs once at construction. */
class WorkspaceScreenModel(val ref: WorkspaceRef, hub: MachineHub, sleep: suspend (Duration) -> Unit = { delay(it) }) {
    enum class Phase { WAITING, SHOWING, DISMISSED, MACHINE_REMOVED, NOT_FOUND }
    val state: StateFlow<WorkspaceScreenState>
    val phase: Phase; val selectedTerminalId: String?; val shownPaneClosed: Int; val lastTabClosedHere: Boolean
    val workspace: LinkWorkspace?; val panes: List<WorkspacePane>; val canControl: Boolean
    fun select(terminalId: String); fun closesHere(terminalId: String); fun keeps(terminalId: String)
    /** markSeen, reconcile, then reconcile on every hub.state emission until cancelled; gives up waiting after PATIENCE. */
    suspend fun run()
    internal fun reconcile()
    companion object {
        val PATIENCE: Duration                                   // 5 s
        fun defaultTerminal(workspace: LinkWorkspace, pending: List<MachinePendingItem>, sessions: List<AgentSession>? = null): String?
        internal fun defaultChoice(workspace: LinkWorkspace, pending: List<MachinePendingItem>, sessions: List<AgentSession>?): Pair<String?, Boolean>
        internal fun successor(gone: String, before: List<String>, now: List<String>): String?
    }
}
```

  Swift's `withObservationTracking` wake-up becomes `hub.state.collect { reconcile() }`. Every emission reconciles; `reconcile()` changes nothing when nothing relevant changed.

- [ ] **Step 1: Port the tests.** Port `ios-tests/WorkspaceScreenModelTests.swift` (32 tests).
- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.workspaces.WorkspaceScreenModelTest'`.

  Expected: `Unresolved reference: WorkspaceScreenModel`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): workspace screen model"`.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run (green).** Run three times. Expected: PASS, 32 tests each time.
- [ ] **Step 6: Commit with the ledger.** Set row `6.2-17` to `done (3C)`. Then run `git add shellx-android/core/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): workspace screen model"`.

---

### Task 24: Voice values: language, capabilities, cache, transcript and spoken answers

**Files:**
- Create in `core/voice/`: `VoiceLanguage.kt`, `VoiceCapabilities.kt` (with `VoiceEngine`), `VoiceCapabilityCache.kt`, `TranscriptAccumulator.kt`, `DictationOutcome.kt`, `PendingQuestionMatching.kt`
- Test in `core-test/voice/`: `VoiceCapabilitiesTest.kt`, `VoiceCapabilityCacheTest.kt`, `TranscriptAccumulatorTest.kt`, `OptionMatchingTest.kt`

Reference: the `ios/Voice/` files of the same names (`PendingQuestion+Matching.swift`).

**Interfaces:**
- Produces (`com.shellx.core.voice`):

```kotlin
enum class VoiceLanguage(val tag: String) {
    VIETNAMESE("vi-VN"), ENGLISH("en-US");
    fun save(settings: KeyValueStore)
    companion object {
        const val SETTINGS_KEY = "shellx.voice.language"
        fun of(preferredLanguages: List<String>): VoiceLanguage     // Vietnamese when any tag's first part (split on - or _) is "vi"
        fun saved(settings: KeyValueStore, preferredLanguages: List<String>): VoiceLanguage
    }
}
/** Android (S3 §7.3): the on-device recognizer (SpeechRecognizer.createOnDeviceSpeechRecognizer, API 31+) first,
 *  then the standard SpeechRecognizer on the phone, then the standard one through the phone's speech service. */
enum class VoiceEngine { ON_DEVICE_RECOGNIZER, ON_DEVICE, SERVER }
data class VoiceCapabilities(val onDeviceRecognizer: Boolean, val standardOnDevice: Boolean, val standardAvailable: Boolean) {
    val engine: VoiceEngine?
    companion object { val NONE: VoiceCapabilities }
}
/** Mutex-guarded. Keeps an answer that has an engine for `reuse` by `timeSource`; never keeps one without. */
class VoiceCapabilityCache(reuse: Duration = DEFAULT_REUSE, timeSource: TimeSource.WithComparableMarks,
                           ask: suspend (VoiceLanguage) -> VoiceCapabilities) {
    suspend fun capabilities(language: VoiceLanguage): VoiceCapabilities
    suspend fun forget(language: VoiceLanguage)
    companion object { val DEFAULT_REUSE: Duration }      // 30 s
}
/** Mutable (Conventions). */
class TranscriptAccumulator { val text: String; fun take(piece: String, isFinal: Boolean): String }
sealed interface DictationOutcome {
    val words: String
    data class Complete(override val words: String) : DictationOutcome
    data class CutAtLimit(override val words: String) : DictationOutcome
}
/** PendingQuestion+Matching.swift. Folding: replace đ/Đ with d/D, Normalizer NFKD, drop \p{M}, lower-case (Locale.ROOT),
 *  every code point that is not a letter or digit becomes a space. */
fun PendingQuestion.optionMatching(transcript: String): PendingQuestionOption?
```

- [ ] **Step 1: Port the tests.**

  | Swift file | Tests |
  | --- | --- |
  | `ios-tests/VoiceCapabilitiesTests.swift` | 6 |
  | `ios-tests/VoiceCapabilityCacheTests.swift` | 4 |
  | `ios-tests/TranscriptAccumulatorTests.swift` | 3 |
  | `ios-tests/OptionMatchingTests.swift` | 5 |

  - `VoiceCapabilities(analyzerSupportsLocale:, legacyOnDevice:, legacyAvailable:)` becomes `VoiceCapabilities(onDeviceRecognizer, standardOnDevice, standardAvailable)`.
  - `.analyzer` becomes `ON_DEVICE_RECOGNIZER`.
  - A `ManualClock` used as a `Clock<Duration>` becomes a `kotlin.time.TestTimeSource`.
  - `UserDefaults` becomes `MemoryKeyValueStore`.
- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.voice.*'`.

  Expected: `Unresolved reference: VoiceCapabilities`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): voice values"`.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run (green).** Expected: PASS, 6, 4, 3 and 5 tests.
- [ ] **Step 6: Commit with the ledger.** Set row `6.2-21` to `done (3C)`. Then run `git add shellx-android/core/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): voice language, capabilities, cache and spoken answers"`.

---

### Task 25: The speech engine seam: run slot, fallback and permissions

**Files:**
- Create in `core/voice/`: `SpeechEngine.kt` (with `SpeechRunId`), `SpeechStartException.kt`, `SpeechRunSlot.kt`, `FallbackTranscriber.kt`, `VoicePermissionChecking.kt` (with `VoicePermission`), `SpeechTimeouts.kt`
- Create (test kit): `core-test/testing/FakeTranscriber.kt`, `core-test/testing/FakeVoicePermissions.kt`
- Test: `core-test/voice/{SpeechRunSlotTest,FallbackTranscriberTest}.kt`

Reference: the `ios/Voice/` files of the same names (`SpeechTranscribing.swift`, `SpeechStartError.swift`); `ios-support/{FakeTranscriber,FakeVoicePermissions}.swift`; `shellx-ios/ShellX/Voice/{LegacyTranscriber,AnalyzerTranscriber}.swift` (the two timeouts).

**Interfaces:**
- Produces (`com.shellx.core.voice`):

```kotlin
data class SpeechRunId(val raw: String = UUID.randomUUID().toString())
/** One speech recognizer (contracts §5; 3E implements it over android.speech.SpeechRecognizer, on-device and standard).
 *  Audio and transcripts never leave the phone's recognizer, and transcripts are never logged. */
interface SpeechEngine {
    /** Starts listening as `run`. The channel carries the whole text heard so far, the newest replacing the one before
     *  (Channel.CONFLATED is fine). It closes after finish or cancel, or by itself; a recognizer failure closes it with
     *  the error. Starting a run stops any other run first. */
    suspend fun start(run: SpeechRunId, language: VoiceLanguage, contextualStrings: List<String>): ReceiveChannel<String>
    suspend fun finish(run: SpeechRunId): String        // "" when nothing was heard, or for a run that is not the one listening
    suspend fun cancel(run: SpeechRunId)
}
sealed class SpeechStartException(cause: Throwable) : Exception("speech_start", cause) {
    class Recognizer(cause: Throwable) : SpeechStartException(cause)   // the fallback gives up the primary for the language
    class Audio(cause: Throwable) : SpeechStartException(cause)        // fails this press only
}
/** Thread-safe (synchronized). SpeechRunSlot.swift with Handlers(finish: suspend () -> String, teardown: suspend () -> Unit). */
class SpeechRunSlot {
    class Handlers(val finish: suspend () -> String, val teardown: suspend () -> Unit)
    sealed interface Claim { class Granted(val replaced: Handlers?) : Claim; data object Refused : Claim }
    val active: SpeechRunId?
    fun isActive(run: SpeechRunId): Boolean
    fun begin(run: SpeechRunId)
    fun claim(run: SpeechRunId, handlers: Handlers): Claim
    fun cancel(run: SpeechRunId): Handlers?
    fun takeForFinish(run: SpeechRunId): Handlers?
    fun ended(run: SpeechRunId): Boolean
}
class FallbackTranscriber(slot: SpeechRunSlot, primary: SpeechEngine, fallback: SpeechEngine,
                          usePrimary: suspend (VoiceLanguage) -> Boolean,
                          primaryFailed: suspend (VoiceLanguage) -> Unit) : SpeechEngine
enum class VoicePermission { MICROPHONE, SPEECH }
/** 3E implements it with RECORD_AUDIO. Android has no separate speech permission, so speech() returns true. */
interface VoicePermissionChecking {
    suspend fun needsPrompt(): Boolean
    suspend fun microphone(): Boolean
    suspend fun speech(): Boolean
}
/** For 3E's recognizers (S3 §6.2, ledger 6.2-20): how long finish() waits for the final result. */
object SpeechTimeouts {
    val STANDARD_FINAL_RESULT: Duration          // 1 500 ms (iPhone LegacyTranscriber.finalResultTimeout)
    val ON_DEVICE_FINALIZE: Duration             // 2 s (iPhone AnalyzerTranscriber.finalizeTimeout)
}
```

- Produces (test kit): ports of `FakeTranscriber` (implementing `SpeechEngine`; `say`, `fail`, `endStream`, `finalText`, `startError`, `holdStarts`/`releaseStarts`/`releaseStart`, `starts`, `grantedRuns`, `finishCalls`, `cancelCalls`, `cancelledRuns`, `activeRun`, `isRunning`, `startsWaiting`) and of `FakeVoicePermissions`. In `FakeTranscriber.Start`, the field `locale` becomes `language`.

- [ ] **Step 1: Port the tests.**

  | Swift file | Tests |
  | --- | --- |
  | `ios-tests/SpeechRunSlotTests.swift` | 6 |
  | `ios-tests/FallbackTranscriberTests.swift` | 6 |

  `Locale(identifier: "vi-VN")` becomes `VoiceLanguage.VIETNAMESE`.
- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.voice.SpeechRunSlotTest' --tests 'com.shellx.core.voice.FallbackTranscriberTest'`.

  Expected: `Unresolved reference: SpeechRunSlot`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): speech run slot and fallback"`.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run (green).** Expected: PASS, 6 and 6 tests.
- [ ] **Step 6: Commit.** Run `git add shellx-android/core/src` and `git commit -m "feat(shellx-android): speech engine seam, run slot and fallback"`.

---

### Task 26: Hold-to-talk and the voice service

**Files:**
- Create: `core/voice/MicHold.kt`, `core/voice/VoiceInputModel.kt`, `core/voice/VoiceService.kt`
- Test: `core-test/voice/{VoiceInputModelTest,VoiceServiceTest}.kt`

Reference: `ios/Voice/{MicHold,VoiceInputModel}.swift`; `shellx-ios/ShellX/Voice/VoiceService.swift` (iPhone app target; its logic moves into `:core` on Android); `ios-tests/VoiceInputModelTests.swift`; `shellx-ios/ShellXTests/VoiceServiceTests.swift`.

**Interfaces:**
- Produces (`com.shellx.core.voice`):

```kotlin
/** Mutable (Conventions). Compose's pointer input gives the same two signals (3E): the hold state and the lift. */
class MicHold {
    enum class Step { PRESS, RELEASE, CANCEL, NONE }
    fun holdingChanged(holding: Boolean): Step
    fun ended(): Step
    fun settle(): Step
}
data class VoiceInputState(val phase: VoiceInputModel.Phase = VoiceInputModel.Phase.Idle, val wantsKeyboard: Boolean = false,
    val firstWordLatency: Duration? = null, val limitReached: Boolean = false, val language: VoiceLanguage)
/** Main-confined. The reader runs in `scope`. */
class VoiceInputModel(engine: SpeechEngine, permissions: VoicePermissionChecking,
    capabilities: suspend (VoiceLanguage) -> VoiceCapabilities, language: VoiceLanguage,
    contextualStrings: () -> List<String>, latency: LatencyLog, timeSource: TimeSource.WithComparableMarks,
    scope: CoroutineScope, maxBytes: Int = ComposerValidation.MAX_BYTES) {
    sealed interface Phase {
        data object Idle : Phase; data class Listening(val text: String) : Phase; data class CancelArmed(val text: String) : Phase
        data object Finishing : Phase; data class Denied(val permission: VoicePermission) : Phase; data object Unavailable : Phase
    }
    val state: StateFlow<VoiceInputState>
    val phase: Phase; var wantsKeyboard: Boolean; val firstWordLatency: Duration?; val limitReached: Boolean
    var language: VoiceLanguage; val maxBytes: Int; val isActive: Boolean
    suspend fun press(); fun drag(dx: Double, dy: Double); suspend fun release(): String?
    fun outcome(words: String): DictationOutcome
    suspend fun typeInstead(); suspend fun cancel(); fun dismiss()
    companion object {
        const val CANCEL_DISTANCE = 80.0            // dp
        const val KEYBOARD_DISTANCE = 60.0          // dp
        val TERMS: List<String>                     // ["PR", "CI", "push", "pull request", "branch", "merge", "deploy", "commit", "Claude"]
        fun contextualStrings(workspaceTitles: List<String>): List<String>
    }
}
data class VoiceServiceState(val language: VoiceLanguage, val engine: VoiceEngine? = null, val engineKnown: Boolean = false)
/** Main-confined. One per signed-in account (3E builds it with a FallbackTranscriber over its two recognizers). */
class VoiceService(engine: SpeechEngine, permissions: VoicePermissionChecking, cache: VoiceCapabilityCache,
    latency: LatencyLog, settings: KeyValueStore, scope: CoroutineScope, timeSource: TimeSource.WithComparableMarks,
    preferredLanguages: List<String>, contextualStrings: () -> List<String>) {
    val state: StateFlow<VoiceServiceState>
    val language: VoiceLanguage; val engine: VoiceEngine?; val engineKnown: Boolean
    /** Some mic made here listens or finishes (not observable; a screen collects its own mic's state). */
    val isListening: Boolean
    fun makeModel(maxBytes: Int = ComposerValidation.MAX_BYTES): VoiceInputModel   // keeps a WeakReference to each
    fun setLanguage(language: VoiceLanguage)
    suspend fun refreshEngine()
    suspend fun cancelAll()
    /** The on-device recognizer failed to start for `language` (FallbackTranscriber's primaryFailed): forget the cached
     *  answer and ask again, so Settings names the path really used. */
    suspend fun primaryFellBack(language: VoiceLanguage)
    companion object { fun contextualStrings(hub: MachineHub): () -> List<String> }   // the live sessions' workspace titles
}
```

  `VoiceInputModel` cuts with `cutToUtf8(maxBytes)`. The first-word stopwatch is `timeSource.markNow()`.

- [ ] **Step 1: Port the tests.**
  - **`VoiceInputModelTests.swift` → `VoiceInputModelTest`** (22 tests).
    - The rig's `ManualClock` becomes a `TestTimeSource`; `clock.advance(by: x)` becomes `timeSource += x`.
    - `start.locale.identifier == "vi-VN"` becomes `start.language == VoiceLanguage.VIETNAMESE`.
  - **`VoiceServiceTests.swift` → `VoiceServiceTest`** (3 tests).
    - `testAnalyzerFallbackMakesSettingsNameThePathUsed` becomes `primaryFallbackMakesSettingsNameThePathUsed`; it ends at `assertEquals(VoiceEngine.SERVER, service.engine)`, because `VoiceSection` is UI.
    - Drop the `AudioLevelMeter` argument.
- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.voice.VoiceInputModelTest' --tests 'com.shellx.core.voice.VoiceServiceTest'`.

  Expected: `Unresolved reference: VoiceInputModel`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): hold-to-talk and voice service"`.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run (green).** Run three times. Expected: PASS, 22 and 3 tests each time.
- [ ] **Step 6: Commit with the ledger.** Add row `A-10`:
  - difference: "Voice: the on-device recognizer comes first (API 31+), then the standard `SpeechRecognizer`. There is no separate speech permission. The microphone and level meter belong to the recognizer, so the iPhone's audio-route and level-throttle rules do not apply";
  - why: "S3 §7.3 replaces the iPhone's recognizers with `SpeechRecognizer`";
  - Android: `core:voice/VoiceCapabilities.kt`, `FallbackTranscriber.kt`, `VoiceService.kt`;
  - plan: 3C;
  - state: `differs (3C): by design`.

  Run `git add shellx-android/core/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): hold-to-talk model and voice service"`.

---

### Task 27: Push: the FCM payload and token registration

**Files:**
- Create: `core/push/PushPayload.kt`, `core/push/PushRegistrar.kt`, `core/push/PushRegistration.kt`
- Test: `core-test/push/{PushRegistrationTest,PushPayloadTest}.kt`

Reference: `ios/Push/{PushPayload,PushRegistration}.swift`; `ios-tests/PushTests.swift`; contracts §8.

**Interfaces:**
- Produces (`com.shellx.core.push`):

```kotlin
/** What an FCM data message from a paired Mac says (contracts §8). */
sealed interface PushPayload {
    val machineId: String; val requestId: String
    data class NeedsYou(override val machineId: String, override val requestId: String, val agent: String,
                        val workspaceTitle: String) : PushPayload {
        /** Contracts §8: use push_needs_you_workspace when true, else push_needs_you. */
        val showsWorkspace: Boolean               // workspaceTitle.trim().isNotEmpty()
    }
    data class Resolved(override val machineId: String, override val requestId: String) : PushPayload
    companion object {
        /** null unless kind is "needs_you" or "resolved" and machine_id and request_id are non-empty. A needs_you also
         *  needs a non-empty agent. A missing workspace_title is "". Every other key is ignored. */
        fun parse(data: Map<String, String>): PushPayload?
    }
}
/** The platform's push service (contracts §5; 3E implements it with FirebaseMessaging.getToken()). Asking may create
 *  an FCM token, so PushRegistration asks only while a session is stored. */
interface PushRegistrar { suspend fun currentToken(): String? }   // null when there is none (no Play services, not issued yet)
/** Main-confined. Port of PushRegistration.swift with FCM tokens: setPushToken(fcmToken, session token). A token and
 *  session pair is sent once; again after a failure, after appBecameActive(), or after another sign-in.
 *  Session guard: every path that would call registrar.currentToken() first reads vault.session(). With no session it
 *  returns before calling the registrar, so a signed-out phone never requests or creates an FCM token (plan 3H's
 *  Data safety answers rely on this). A token that arrives while signed out is kept, and sent at the next signedIn(). */
class PushRegistration(relay: RelayAccountCalling, vault: AccountVault, registrar: PushRegistrar) {
    suspend fun tokenArrived(token: String)       // FirebaseMessagingService.onNewToken (3E); never asks the registrar
    suspend fun signedIn()                        // with a session: asks registrar.currentToken() when no token arrived yet
    suspend fun appBecameActive()                 // forgets what was sent; with a session, asks the registrar when no token is known
}
```

- [ ] **Step 1: Port and write the tests.**
  - **`PushRegistrationTest`**: port the 7 `PushRegistrationTests` of `ios-tests/PushTests.swift`.
    - The token is `"fcm-1"`.
    - Each expected call is `SetPushToken("fcm-1", <session token>)`. `testANewTokenGoesToTheRelayAsHexWithTheAppAndHost` becomes `aNewTokenGoesToTheRelayWithTheSessionToken`.
    - The registrar is a private test fake, `FakePushRegistrar(var token: String? = null)`: `currentToken()` returns `token` and counts its calls in `requests`.
    - Add `signedInAsksTheRegistrarWhenNoTokenArrived`: the registrar answers `"fcm-2"`; `signedIn()` → `[SetPushToken("fcm-2", "tok-1")]`.
    - Add `appBecameActiveWithoutASessionRequestsNoToken` (the session guard):

```kotlin
@Test fun appBecameActiveWithoutASessionRequestsNoToken() { runTest {
    val vault = AccountVault(InMemorySecretStore(), StandardTestDispatcher(testScheduler))   // no session stored
    val relay = FakeRelayAccount(); val registrar = FakePushRegistrar(token = "fcm-2")
    val push = PushRegistration(relay, vault, registrar)
    push.appBecameActive(); push.signedIn()
    assertEquals(0, registrar.requests)                       // no FCM token is requested or created while signed out
    assertEquals(emptyList(), relay.calls)
    vault.setSession(StoredSession("u1", "d2", "tok-2", "a@b.c")); push.signedIn()
    assertEquals(1, registrar.requests)
    assertEquals(listOf(FakeRelayAccount.Call.SetPushToken("fcm-2", "tok-2")), relay.calls)
} }
```

    - That makes 9 tests.
  - **`PushPayloadTest`**: rewrite the 3 `PushPayloadTests` as FCM data maps, for example `mapOf("kind" to "needs_you", "machine_id" to "m1", "request_id" to "r1", "agent" to "Claude Code", "workspace_title" to "shellx")` → `NeedsYou("m1", "r1", "Claude Code", "shellx")`. Then add the RF 5 test:

```kotlin
@Test fun dataWithExtraKeysOrNoTitleStillParses() {
    assertEquals(PushPayload.NeedsYou("m1", "r1", "Claude Code", ""), PushPayload.parse(mapOf("kind" to "needs_you",
        "machine_id" to "m1", "request_id" to "r1", "agent" to "Claude Code", "google.message_id" to "x", "from" to "y")))
    assertFalse(PushPayload.NeedsYou("m1", "r1", "Codex", "   ").showsWorkspace)
    assertTrue(PushPayload.NeedsYou("m1", "r1", "Codex", "Dự án 🚀").showsWorkspace)
    assertNull(PushPayload.parse(mapOf("kind" to "needs_you", "machine_id" to "m1", "request_id" to "r1")))
    assertNull(PushPayload.parse(mapOf("kind" to "needs_you", "machine_id" to "", "request_id" to "r1", "agent" to "Codex")))
    assertEquals(PushPayload.Resolved("m1", "r1"), PushPayload.parse(mapOf("kind" to "resolved", "machine_id" to "m1",
        "request_id" to "r1", "agent" to "Claude Code", "workspace_title" to "shellx")))
}
```

- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.push.*'`.

  Expected: `Unresolved reference: PushPayload`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): FCM payload and token registration"`.
- [ ] **Step 4: Implement.** In `signedIn()` and `appBecameActive()`, read `vault.session()` before anything that could reach `registrar.currentToken()`. With no session, return at once.
- [ ] **Step 5: Run (green).** Expected: PASS, 9 and 4 tests.
- [ ] **Step 6: Commit with the ledger.** Add row `A-11`:
  - difference: "A push is an FCM data message that carries `agent` and `workspace_title`, and the phone builds the alert text itself";
  - why: "contracts §8: data-only messages";
  - Android: `core:push/PushPayload.kt`;
  - plan: 3C;
  - state: `differs (3C): by design`.

  Row `6.1-16` stays `todo`. Run `git add shellx-android/core/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): FCM payload and push token registration"`.

---

### Task 28: The update prompt

**Files:**
- Create: `core/update/UpdateChecker.kt`, `core/update/UpdatePrompt.kt`
- Test: `core-test/update/UpdatePromptTest.kt`

Reference: `ios/Update/UpdatePrompt.swift`; `ios-tests/AppStoreUpdateTests.swift`.

**Interfaces:**
- Produces (`com.shellx.core.update`):

```kotlin
data class AvailableUpdate(val versionCode: Long)
/** The store (contracts §5; 3E implements it with Play In-App Updates: UPDATE_AVAILABLE and FLEXIBLE allowed →
 *  AvailableUpdate(availableVersionCode()), else null; startUpdate starts the flexible flow). */
interface UpdateChecker {
    suspend fun check(): AvailableUpdate?          // may throw; a failure changes nothing
    suspend fun startUpdate(update: AvailableUpdate)
}
/** Main-confined. 3D makes one only in release builds (S3 §6.1: never in debug) and calls check() at launch and on every
 *  ON_START. */
class UpdatePrompt(installedVersionCode: Long, checker: UpdateChecker) {
    val offered: StateFlow<AvailableUpdate?>       // a newer versionCode than the installed one, or null
    suspend fun check()                            // a check while one is under way does nothing
    fun later()
    suspend fun update()                           // startUpdate(offered) when there is one, then later()
}
```

- [ ] **Step 1: Port and write the tests.**
  - **Ported** from `ios-tests/AppStoreUpdateTests.swift`, onto a fake `UpdateChecker` that answers from a queue and can be held:
    - `testANewerVersionIsOffered`
    - `testTheInstalledOrAnOlderVersionIsNotOffered`
    - `testLaterHidesItUntilTheNextCheck`
    - `testAFailedLookupShowsNothing`
    - `testAStoreThatNoLongerHasTheNewerVersionTakesTheOfferBack`
    - `testAsksTheStoreOnceWhileALookupIsUnderWay`

    Use installed code 100 and offered code 101, or 100 and 99 for "not newer". Do not port the six lookup, parse and `AppVersion` tests: there is no App Store lookup on Android.
  - **New test, `updateStartsTheStoresFlowAndHidesThePrompt`**: offered 101 → `update()` calls `startUpdate(AvailableUpdate(101))` once; then `offered.value == null`.
- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.update.*'`.

  Expected: `Unresolved reference: UpdatePrompt`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): update prompt"`.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run (green).** Expected: PASS, 7 tests.
- [ ] **Step 6: Commit with the ledger.** Add row `A-12`:
  - difference: "The update prompt compares Play `versionCode`s from Play In-App Updates; there is no store-page URL";
  - why: "S3 §7.3: flexible in-app update instead of the App Store lookup";
  - Android: `core:update/UpdatePrompt.kt`;
  - plan: 3C;
  - state: `differs (3C): by design`.

  Row `6.1-15` stays `todo`. Run `git add shellx-android/core/src docs/superpowers/ledgers/shellx-android-parity.md` and `git commit -m "feat(shellx-android): update prompt over Play in-app updates"`.

---

### Task 29: The demo: script, relay, secrets and environment

**Files:**
- Create in `core/demo/`: `DemoScript.kt`, `DemoRelay.kt`, `DemoSecretStore.kt`, `DemoEnvironment.kt`
- Test in `core-test/demo/`: `DemoScriptTest.kt`, `DemoRelayTest.kt`, `DemoEnvironmentTest.kt`

Reference. The content to port is the same in either layout; use the one Task 0 Step 5 found:
- **Before 1C:** `ios-support/FakeMacDemoScript.swift`, `shellx-ios/ShellX/Debug/DemoScript.swift` and `shellx-ios/ShellX/Debug/DemoComposition.swift`.
- **After 1C:** `shellx-ios/Packages/ShellXAppCore/Sources/ShellXDemo/FakeMacDemoScript.swift`, `shellx-ios/ShellX/Demo/DemoScript.swift`, `shellx-ios/ShellX/Demo/DemoComposition.swift` and `ShellXDemo/DemoRelay.swift`.

Also read 1C Task 12 (`DemoRelay`, `DemoSecretStore`); `ios-tests/FakeMacDemoScriptTests.swift`; and `shellx-ios/ShellXTests/DemoCompositionTests.swift`.

"Try without an account" ships in every build (S1 §6.6, S3 §6.1, contracts §5 and §11). 3D selects it at runtime: the route `demo`, from the sign-in and "no Mac yet" screens, with a "Demo · Exit" banner. The demo never touches the network or the real account's data. Nothing in `core/demo/` may name `RelayApi`, `RelayAccountClient`, `RelayClientFactory`, `LinkConnector`, `RelayMachineConnector` or `okhttp3`; Task 30 greps for them.

**Interfaces:**
- Consumes: Tasks 8, 9, 14 and 18; everything a signed-in hub needs.
- Produces (`com.shellx.core.demo`):

```kotlin
/** Main-confined. FakeMacDemoScript's setUp, step and run, and DemoScript's start. */
class DemoScript(val mac: FakeMac, nowMs: () -> Long) {
    fun setUp()                        // the four sessions, their histories and WORKSPACES, exactly as FakeMacDemoScript.swift
    fun step(index: Int)
    suspend fun run(sleep: suspend (Duration) -> Unit, setUp: Boolean = true, from: Int = 0)
    /** Once: setUp(), steps 0, 1 and 2, then run(sleep, setUp = false, from = 3) in `scope`. */
    fun start(scope: CoroutineScope, sleep: suspend (Duration) -> Unit = { delay(it) }): Job
    companion object { val INTERVAL: Duration; const val MAX_PENDING = 6; val WORKSPACES: List<LinkWorkspace> }   // 20 s
}
/** No network (1C Task 12). machines() lists one grant per paired Mac in pairing order ("grant-<machineId>", "macos",
 *  online, its linkSlot, fingerprint "demo"). unpair removes by grantId. pair parses the offer (its error is thrown);
 *  a machine outside pairableMachineIds → Http(404, "machine_not_found"); otherwise it waits approvalDelay with `sleep`,
 *  lists the Mac and returns the offer's PairedMachine. logout, setPushToken and unsetPushToken do nothing; nonce,
 *  signInWithGoogle and deleteAccount throw REFUSAL. */
class DemoRelay(paired: List<PairedMachine>, pairableMachineIds: Set<String>, approvalDelay: Duration,
                sleep: suspend (Duration) -> Unit = { delay(it) }) : RelayAccountCalling {
    companion object { val REFUSAL: RelayApiException.Http }       // Http(403, "demo"); a getter returning a new instance
}
/** Memory only: nothing reaches the Keystore. Thread-safe. */
class DemoSecretStore : SecretStore
/** Everything the demo route shows, built from DemoComposition: a vault over DemoSecretStore, the demo's own
 *  MemoryKeyValueStore, DemoRelay, "Mac giả" (id "demo-1", paired) and "Mac giả 2" (id "demo-2", pairable), a
 *  ConversationStore over `historyDirectory` (3D passes File(context.noBackupFilesDir, "ShellXDemo")), and an
 *  AppCoordinator with UnavailableIdentityProvider, device name "Android", wipers [history], whose hubs connect through
 *  FakeMacFleet([first, second]) with onUnauthorized = {}. */
class DemoEnvironment(scope: CoroutineScope, clock: Clock, historyDirectory: File, io: CoroutineDispatcher,
                      approvalDelay: Duration = 2.seconds, runsScript: Boolean = true,
                      sleep: suspend (Duration) -> Unit = { delay(it) }) {
    val vault: AccountVault; val settings: KeyValueStore; val relay: DemoRelay
    val first: FakeMac; val second: FakeMac; val history: ConversationStore; val latency: LatencyLog
    val coordinator: AppCoordinator; val script: DemoScript
    /** Once: stores StoredSession("demo", "demo-phone", "demo-token", EMAIL) and [first.machine] owned by "demo", then,
     *  with runsScript, starts the script and gives the first Mac WORKSPACES. The caller then calls coordinator.launch(). */
    suspend fun prepare()
    /** The second Mac's code: 3D puts it on the clipboard so "Paste pairing code" pairs it. */
    fun secondPairingCode(): String
    /** "Demo · Exit": stops the script and the hub. The demo history stays in its own directory (the iPhone keeps it too). */
    suspend fun exit()
    companion object {
        const val FIRST_NAME = "Mac giả"; const val SECOND_NAME = "Mac giả 2"; const val EMAIL = "demo@shellx.pro"
        val WORKSPACES: List<LinkWorkspace>            // DemoComposition.workspaces: shellx-ios, relay, web, notes
    }
}
```

- [ ] **Step 1: Port and write the tests.**
  - **`FakeMacDemoScriptTests.swift` → `DemoScriptTest`** (6 tests). `FakeMacDemoScript` becomes `DemoScript(mac, clock::nowMs)`, and the test's hub is `hubRig(listOf(mac), sleep = instantSleep, start = true).hub`.
  - **`DemoRelayTest`**: the 4 tests of 1C Task 12. In `testEveryAccountCallIsRefused`, check only `nonce`, `signInWithGoogle` and `deleteAccount` (Android has no login, `linkGoogle` or Apple calls).
  - **`DemoCompositionTests.swift` → `DemoEnvironmentTest`**: port the three demo tests.
    - `testDemoIsSignedInWithFakeMacOnlineAndPairsSecondMacFromPastedCode` uses `secondPairingCode()` instead of the pasteboard, and a `PairingModel(hub, environment.relay, environment.vault, hub.scope)`.
    - `testDemoMacListsTheFourWorkspacesOfTheDesign`.
    - `testDemoAgentScreenShowsTheScriptedChatAndStops` uses `AgentThreadModel(ref, hub, environment.history, hub.scope)`.

    Do not port the two pasteboard tests (3D owns the clipboard). Add:

```kotlin
@Test fun demoSignOutWipesOnlyTheDemoStores(@TempDir root: File) { runTest {
    val real = File(root, "ShellX").apply { mkdirs(); File(this, "keep.json").writeText("{}") }
    val demoDir = File(root, "ShellXDemo")
    val env = DemoEnvironment(backgroundScope, ManualClock(), demoDir, StandardTestDispatcher(testScheduler),
        approvalDelay = Duration.ZERO, runsScript = false)
    env.prepare(); env.coordinator.launch()
    env.history.writer().save(ChatThread(listOf(chatEntry(1))), ChatThread.CODEC,
        StoreDocument.Thread(SessionRef(env.first.machine.machineId, "s1", "claude", "shellx")))
    assertTrue(demoDir.exists())
    env.coordinator.signOut()
    assertEquals(AppPhase.SignedOut(false), env.coordinator.phase.value)
    assertTrue(File(real, "keep.json").isFile)                    // the real history is untouched
    assertFalse(demoDir.exists())                                 // the demo's own history was wiped
    // The demo relay refuses every account call (DemoRelay.REFUSAL): signing in again never leaves the process.
    assertSameCase(SignInException.Server("demo"), assertFails { env.coordinator.signInWithGoogle() })
} }
```
- [ ] **Step 2: Run (red).** Run `gw :core:test --tests 'com.shellx.core.demo.Demo*'`.

  Expected: `Unresolved reference: DemoScript`.
- [ ] **Step 3: Commit the tests.** Run `git add shellx-android/core/src/test` and `git commit -m "test(shellx-android): demo script, relay and environment"`.
- [ ] **Step 4: Implement.** Copy every literal from the iPhone demo verbatim: titles, Vietnamese chat lines, workspace and terminal ids, modes, question options and the plan text.
- [ ] **Step 5: Run (green).** Expected: PASS, 6, 4 and 4 tests.
- [ ] **Step 6: Commit with the ledger.** Row `6.1-17` (3C and 3D) stays `todo`. Run `git add shellx-android/core/src` and `git commit -m "feat(shellx-android): demo Mac script, relay, secrets and environment"`.

---

### Task 30: Verify and hand off

**Files:** none new. A fix found here gets a failing test first, in the task that owns the code.

- [ ] **Step 1: Run the full suite.** Run `shellx-android/scripts/dev.sh test core` three times.

  Expected: `==> test core: passed` every time. Then run `shellx-android/scripts/dev.sh test all`; expected `==> test all: passed`. Record the total test count from `shellx-android/core/build/test-results/test/*.xml`.
- [ ] **Step 2: Run the licence checks.** Run `bash scripts/shellx/check-android-license.sh`.

  Expected: `check-android-license: ok`.
- [ ] **Step 3: Run the boundary greps.** Each command must print nothing:

  ```bash
  grep -rn 'import android\.' shellx-android/core/src
  grep -rnE 'HexFormat|java\.net\.http|readAllBytes|transferTo|ofVirtual' shellx-android/core/src/main
  grep -rnE 'okhttp3|RelayApi\b|RelayAccountClient|RelayClientFactory|LinkConnector|RelayMachineConnector' shellx-android/core/src/main/kotlin/com/shellx/core/demo
  grep -rnE 'System\.currentTimeMillis' shellx-android/core/src/main | grep -v 'demo/FakeMac.kt'
  grep -rni 'manaflow' shellx-android/core
  git diff --stat develop -- shellx-ios shellx-link Sources ios Packages cmux-tui shellx-core
  ```

- [ ] **Step 4: Check the ledger.**
  - Rows `6.2-1` to `6.2-6`, `6.2-8`, `6.2-9`, `6.2-12` to `6.2-14`, `6.2-16`, `6.2-17` and `6.2-21` say `done (3C)`.
  - The seven `A-` rows of Tasks 7, 12, 14, 19, 26, 27 and 28 exist.
  - The shared rows `6.1-15`, `6.1-16`, `6.1-17`, `6.2-10` and `6.2-11` say `todo`.
- [ ] **Step 5: Run the repository checks.** Run `python3 scripts/verify-local.py`.

  Expected: exit 0. If a check fails, run the same command on `develop` in the primary checkout. A failure there too is pre-existing: report it and do not fix it on this branch.
- [ ] **Step 6: Review.** Run a review subagent on `git diff develop...HEAD` with `skills/cmux-review/SKILL.md` (correctness first), through superpowers:requesting-code-review.
  - Give it this plan, contracts §5 and §9, and the Swift reference folders.
  - Fix each confirmed finding with a failing test first, then repeat Steps 1–5.
- [ ] **Step 7: Land on develop (contracts §1).**
  1. In the checkout that has `develop`, run `git pull --ff-only`.
  2. Run `git merge --no-ff feat/shellx-android-3c-core -m "Merge branch 'feat/shellx-android-3c-core' into develop"`.
  3. Run `shellx-android/scripts/dev.sh test core`. Expected: `==> test core: passed`.
  4. Run `git push origin develop`.

  Never merge into `main`, never deploy, never publish. This plan changes no app UI or runtime, so no dogfood build is needed. Remove the worktree afterwards (superpowers:finishing-a-development-branch).
- [ ] **Step 8: Report.** Include:
  - the test counts;
  - any 3B name that differed from this plan;
  - any iPhone reference that changed since this plan;
  - the allowlist entries added;
  - the "UI wiring summary" below, for the 3D and 3E authors.

## UI wiring summary (for plans 3D and 3E)

- **Composition (3D).**
  - Build one supervised main scope for the app.
  - Use one `io` dispatcher (`Dispatchers.IO`).
  - Build an `AccountVault` over the Keystore `SecretStore`.
  - Build the relay with `RelayClientFactory.make(ShellXEndpoints.of(BuildConfig.DEBUG, BuildConfig.SHELLX_API_BASE.ifEmpty { null }).apiBase, VERSION_NAME, okHttp)`, and the connector with `RelayClientFactory.makeConnector(…)`.
  - Build a `ConversationStore(File(noBackupFilesDir, "ShellX"), io, clock)`.
  - Build an `AppCoordinator(vault, relay, credentialManagerIdentity, deviceName, wipers = [store], dataStoreSettings, appScope) { MachineHub(vault, relay, connector, latency, dataStoreSettings, appScope, clock) { coordinator.handleUnauthorized() } }`. The hub reaches its coordinator through a holder, as `CoordinatorReference` in `shellx-ios/ShellX/AppComposition.swift`. Per sign-in, also build the `DecisionCenter(hub, latency, hub.scope, clock)`, `PairingModel(hub, relay, vault, hub.scope)`, `EndedDismissalStore`, `GoneRemovalStore`, `ChatCopySweeper` (run while signed in) and `VoiceService`.
  - Set `CoreLog.sink` to `android.util.Log`.
- **Lifecycle (3D).** These follow `shellx-ios/ShellX/ShellXApp.swift:42-63`.
  - On `ProcessLifecycleOwner` ON_START, in the app scope: `coordinator.protectedDataBecameAvailable()`, `updatePrompt?.check()`, `push.appBecameActive()`, then `hub.appDidBecomeActive()` and `hub.refreshGrants()`.
  - On ON_STOP: launch `hub.appDidEnterBackground()` in the app scope, and `voice.cancelAll()`.
  - `NetworkMonitor.paths` feeds a `NetworkChangeFilter(appScope) { coordinator.hub.value?.networkChanged() }`.
  - The `shellx-link` intent goes to `PairingInbox.receive`.
- **Screens.**
  - Collect `coordinator.phase` and `hub.state`, and each model's `state`, with `collectAsStateWithLifecycle()`. Read the getters after that.
  - The home re-sorts with `HomeFocus.make(…, nowMs = clock.nowMs())` every 30 s (ledger `6.2-7`).
  - An agent screen makes `AgentThreadModel(ref, hub, store, hub.scope)`, runs `run()` while STARTED, and calls `close()` from `onCleared()`.
  - A workspace screen runs `WorkspaceScreenModel.run()` while STARTED.
- **Push (3E).**
  - `onNewToken` → `push.tokenArrived`.
  - `onMessageReceived` → `PushPayload.parse(remoteMessage.data)`.
  - `push.signedIn()` is called once the first Mac exists, then the app asks for `POST_NOTIFICATIONS`, as the iPhone does in `shellx-ios/ShellX/UI/SignedInView.swift:88-93`.
- **Demo (3D).** `DemoEnvironment(appScope, clock, File(noBackupFilesDir, "ShellXDemo"), io)`, then `prepare()`, then `coordinator.launch()`. Put `secondPairingCode()` on the clipboard. Exit calls `exit()`.

## Spec notes

These are places where the spec, the brief or the contracts differ from the code, or where Android differs from the iPhone. The code is the fact, and this plan follows the spec's intent.

- **Sign-in.** The iPhone code on `develop` still signs in with a password (`AppCoordinator.signIn(email:password:)`). Android implements the S1 flow (§6.2, §6.3, §6.7, §6.8) as 1C specifies it for the iPhone: a relay nonce, Google's ID token through `IdentityProviding`, `POST /v1/auth/google`, keeping the phone key and the Macs after a 401, and account deletion with a fresh ID token. There is no password, Apple, `linkGoogle` or "switch to Google" on Android (contracts §5).
- **Naming.** Swift `…Error` types are Kotlin `…Exception`s, following 3B. `SpeechTranscribing` is `SpeechEngine` (contract name). The iPhone's app-target `VoiceService` moves into `:core` so that it can be tested on the JVM.
- **Observation.** Swift `@Observable` models become `StateFlow` snapshots plus getters. `MachineModel` is an immutable snapshot inside `HubState`, not an object with identity, so `refreshGrants` compares pairing records instead of object identity.
- **Cancellation.** Swift views never cancel their Tasks, but Kotlin screens do. That is why coordinator, pairing and decision actions run detached in their object's scope (`runDetached`), and why `AgentThreadModel.close()` and `save()` return a `Job` instead of suspending. `PairingModel.confirm` withdraws a late approval explicitly, because a cancelled Kotlin coroutine discards its result.
- **Background (A-7).** Android has no "background time expiring" signal, and freezes cached apps. `appDidBecomeActive` therefore checks the monotonic clock, which counts deep sleep. `backgroundTimeExpired()` stays for parity, but no Android signal calls it today.
- **Sign-out (A-8).** Sign-out deletes the FCM token before logging out (contracts §8). The relay's logout also deletes push tokens (`relay/src/routes/auth.ts:157-160`), so the extra call only matters when logout itself fails.
- **Settings.** `UserDefaults` becomes a synchronous `KeyValueStore`. 3D backs it with DataStore through an in-memory snapshot loaded before composition, because the iPhone logic reads its settings synchronously (for example the default Mac in the hub's init).
- **Secrets.** On Android a Keystore key can be lost (a restore, or credentials cleared). The `SecretStore` contract therefore makes an undecryptable item read as absent: the user signs in again and pairs again, instead of being locked out with "keychain" errors. The diagnostic code `"keychain"` is kept for parity; no screen shows it.
- **Endpoints (A-6).** The override comes from the build, not the environment. An emulator reaches a relay on the Mac through `adb reverse`, because 3B's transport policy refuses `http://10.0.2.2`.
- **History store.** Backup exclusion and file protection are the directory 3D chooses (`noBackupFilesDir`, S3 §7.3), so the two backup tests are not ported. The iPhone-only migration `removeMergedChatData` is not ported: there is no older Android data.
- **Characters.** JDK 17's `BreakIterator` does not keep emoji ZWJ sequences together, so `text/Text.kt` has its own simplified grapheme rule. It covers combining marks, ZWJ, variation selectors, skin tones, tags and flags.
- **Finish detector.** On the iPhone it is `Codable` but never stored. On Android it is in memory only, and the tests' "saved and restored" round trip is `copy()`.
- **Fake Mac.** 3B ports no `LinkHost`, so the fake Mac implements `LinkSession` itself and reproduces the host rules the phone can observe (features, `unsupported`, `not_found`, `bad_request`, `too_large`, revisions, the upload turn). `phoneFrameCount` becomes `phoneCallCount`. The fake ships in every build as the demo's Mac (contracts §5, §11), like 1C's `ShellXDemo` target.
- **Voice (A-10).** The iPhone engines are `analyzer`, `onDevice` and `server`. On Android they are `ON_DEVICE_RECOGNIZER` (`createOnDeviceSpeechRecognizer`), `ON_DEVICE` and `SERVER`. `AudioInputRoute`, `AudioLevelThrottle` and their 4 tests are not ported: the Android recognizer owns the microphone and reports its level (`onRmsChanged`). The 1.5 s and 2 s result timeouts are constants in `SpeechTimeouts` for 3E's recognizers.
- **Update (A-12).** `AppStoreRelease`, `AppVersion` and their 6 tests are not ported; Play In-App Updates compares version codes.
- **Push (A-11).** The iPhone payload is `userInfo["shellx"]` with an APNs alert. The Android payload is the FCM data map of contracts §8, including `agent` and `workspace_title` for the alert text.
- **Timers that belong to the UI.** The 4 s notice (`AgentView.noticeDuration`), the 0.7 s "Nothing needs you" (`PendingListView.leaveDelay`) and the 30 s home re-sort live in the iPhone app target, so 3D and 3E port them (ledger rows `6.2-7`, `6.2-18`, `6.2-19`).
- **Tests not ported.** `LicenseBoundaryTests` (17) and `StringsCatalogCheckTests` (11) test iPhone scripts; 3A has the Android equivalents.
- **Demo names.** "Mac giả" and "Mac giả 2" are data, kept as on the iPhone. The device name of the demo account is "Android".

## Contract additions

These are cross-plan names that 3D and 3E rely on and that contracts §5 does not list yet. They are listed here for the contracts owner. The executor of this plan does not edit the contracts file.

- **Packages of the seven platform interfaces.**
  - `com.shellx.core.account.SecretStore` (with `SecretItem`, `SecretStoreException`);
  - `com.shellx.core.link.NetworkMonitor` (with `NetworkPath`);
  - `com.shellx.core.platform.Clock`;
  - `com.shellx.core.voice.SpeechEngine` (with `SpeechRunId`, `SpeechStartException`);
  - `com.shellx.core.push.PushRegistrar`;
  - `com.shellx.core.update.UpdateChecker` (with `AvailableUpdate`);
  - `com.shellx.core.composer.AttachmentReader` (with `AttachmentPick`, `AttachmentReadException`, `AttachmentChecks`).
- **Further platform interfaces that :app implements.**
  - `com.shellx.core.account.IdentityProviding` (`googleIdToken(nonce)`, with `IdentityProviderException`, `UnavailableIdentityProvider`): 3D, Credential Manager;
  - `com.shellx.core.platform.KeyValueStore` (with `MemoryKeyValueStore`): 3D, DataStore;
  - `com.shellx.core.voice.VoicePermissionChecking`: 3E.
- **Core objects the UI plans build and read.**
  - `AppCoordinator` (`phase`, `hub`);
  - `MachineHub` (`state: StateFlow<HubState>`, `scope`) and `HubState`;
  - `PairingModel`, `PairingInbox`, `SheetPresence`;
  - `DecisionCenter`, `PendingSheetModel`;
  - `AgentThreadModel`, `WorkspaceScreenModel`, `HomeFocus`;
  - `EndedDismissalStore`, `GoneRemovalStore`, `ConversationStore`, `ChatCopySweeper`;
  - `VoiceService`, `VoiceInputModel`, `MicHold`;
  - `PushRegistration`, `PushPayload`, `UpdatePrompt`;
  - `ShellXEndpoints`, `RelayClientFactory`, `CoreLog`.
- **Demo.** `com.shellx.core.demo.DemoEnvironment` (what the `demo` route builds), with `FakeMac`, `FakeMacFleet`, `DemoRelay`, `DemoSecretStore` and `DemoScript`.
- **Settings keys** (the iPhone's, unchanged): `shellx.defaultMachineID`, `shellx.localWipePending`, `shellx.dismissedEnded`, `shellx.removedGone`, `shellx.voice.language`.

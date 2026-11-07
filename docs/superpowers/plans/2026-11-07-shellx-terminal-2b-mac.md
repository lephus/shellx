# Mac host for the phone terminal (2B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Mac serves plan 2A's `terminal_view` and `terminal_create` from its real terminals. That takes six parts: a frame-sink seam in cmux's render observer and byte tee; a ShellX Link terminal view that captures Ghostty's render grid, diffs it and converts it; the phone's typing, keys, pastes and wheel through the Mac's own input paths; the phone as its own `latest` sizing participant; `terminal.create` that keeps the Mac's selection; and handling for device management (MDM) and unpairing. Tests and a probe dogfood cover all of it.

**Architecture:** cmux's `MobileTerminalRenderObserver` gains frame sinks. A sink keeps Ghostty's frame and tick notifications on, opens the byte tee's gate, and is told when its surface may have changed. With no sink registered, the iroh lane runs exactly as before. A `ShellXLinkTerminalView` is one such sink. It is pull-based: when 2A's pump asks for a frame, it waits for a change, passes cmux's `MobileTerminalFramePacer` (a 90 ms floor, with a bypass for typing echo), captures the surface itself, and diffs against its own baseline with CMUXMobileCore's public `renderGridEmission(comparedTo:)`. It never touches the iroh observer's shared baselines. Then `ShellXLinkGridConverter` turns the cmux frame into 2A's `TerminalGridFrame`. `ShellXLinkTerminalViewSource` looks terminals up in the list the phone sees (`ShellXLinkWorkspaceSource`). The phone joins the terminal's shared sizing as participant `mobile:shellx-link-<uuid>` with `counts_override: true`, and the terminal runs `latest` while a phone views it. Its input runs inside `TerminalController.performRemoteParticipantInput`, so the input counts as the phone's activity.

**Tech Stack:** Swift (app target in Swift 5 language mode, Swift 6.0-compatible syntax), Swift Testing in `cmuxTests` run with `scripts/shellx/test-app.sh`, a real Ghostty in tests (`cmuxTests/ScrollbackTestTerminal.swift`), CMUXMobileCore render grid, ShellXLinkCore / ShellXLinkSession from plan 2A.

**Spec:** `docs/superpowers/specs/2026-11-07-shellx-mobile-terminal-design.md` (S2 §3.3, §3.4, §3.8a–d, §3.9, §5) on top of `docs/superpowers/specs/2026-10-28-shellx-mobile-workspaces-design.md` §8.3, §9, §10, §11. Wire format and host protocols: `docs/superpowers/plans/2026-11-07-shellx-terminal-2a-protocol.md` (PROTOCOL.md §11, `TerminalViewSource`, `TerminalView`, `TerminalCreator`). Cross-plan names and landing: `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` §1, §6, §13. These plan files may exist only in the main checkout (`/Users/lehuuphu/Documents/myProjects/shellx/docs/superpowers/plans/`); read them there and never add them to this branch.

## Global Constraints

- Branch `feat/shellx-terminal-2b-mac`, worktree `/Users/lehuuphu/Documents/myProjects/shellx/.worktrees/terminal-2b-mac`, from `develop` after plan 2A is merged. All paths below are relative to the worktree.
- Change nothing under `shellx-link/` (2A owns it), no spec and no contracts file. 2A's merged code is the source of truth for its names: if a 2A name in this plan differs from the merged code, use the merged one and list it in the hand-off.
- App-linked code (`Sources/`, `Packages/`) stays within Swift 6.0 syntax: no trailing comma in a parameter or argument list, no `nonisolated` on a type declaration. The app target compiles in Swift 5 language mode.
- Wire new `Sources/**/*.swift` files with `./scripts/wire-app-sources.py <files>` and new `cmuxTests/*.swift` files with `./scripts/sync-test-wiring`; commit `cmux.xcodeproj/project.pbxproj` with them.
- Run app tests only through `toknix run scripts/shellx/test-app.sh <Suite>...`, never bare `xcodebuild`. Never launch, quit, relaunch or replace `/Applications/ShellX.app` or any other app. The agent never opens the tagged build either; the user does. Never paste an `.app` path or a `file://` URL into chat.
- The iroh path does not change. With no frame sink registered, `MobileTerminalRenderObserver` and `MobileTerminalByteTee` behave exactly as on `develop`. Link code never calls these: `adoptReplayBaseline`, `decorateReplayFrame`, `noteTerminalViewportChanged`, `requestRenderGridFullResync`, `MobileTerminalByteTee.performMobileInput` or `recordAcceptedInput`, `v2MobileTerminalReplay`, `v2MobileTerminalInput`, `v2MobileTerminalScroll` or `v2MobileTerminalPaste`.
- `RemoteRelayCommandPolicy` and `RemoteRelayRoutingSchema` do not change. No v2 socket method is added, and no v2 method gains a wire parameter.
- Privacy: logs carry fixed codes and counts only (`Logger(subsystem: "pro.shellx.desktop", category: "link-terminal")`, `privacy: .public` only on codes). They never carry terminal content, typed or pasted text, key names, workspace or tab titles, or workspace, terminal or client ids. No `cmuxDebugLog` of any of these.
- Typing latency (skills/cmux-debugging): the only addition to a per-keystroke Mac path is one dictionary lookup in `noteLocalTerminalSizingActivity`, placed after its existing host guard. Frame sinks never capture inside their notification.
- Values: phone size 20–300 × 5–120 (2A's host clamps it before `openView`); snapshot history up to `ShellXLink.terminalHistoryRowBudget` (4 000) rows; at most `ShellXLink.terminalMaxCellTextBytes` (32) UTF-8 bytes per cell; style ids 1…65 535; pacing floor `MobileTerminalFramePacer.floorPeriod` (90 ms); first-snapshot size fence 500 ms; sizing client id `shellx-link-<lowercased UUID>`, participant `mobile:shellx-link-<lowercased UUID>`.
- MDM: every call reads `MobileRemoteControlPolicy.isDisabled` through an injected `isBlocked` closure; tests set `MobileRemoteControlPolicy.overrideForTesting` or inject the closure.
- No new locks, no `DispatchQueue.main.async`, no polling in product code (skills/cmux-architecture). The only sleep is a cancellable `Task.sleep(until:)` for a pacing or fence deadline.
- Commits: `test(shellx): … (failing)` with the red tests first, then `feat(shellx): …`, staged with explicit `git add <paths>`. Run build, test and git commands through `toknix run`.
- Landing (contracts §1): this plan changes app UI/runtime, so after the final review it waits for the USER device check and the user's merge directive (`merge`, `merge it` or `auto-merge`, CLAUDE.md "CI, review and merge"); if none was given, ask with the review summary. Only then merge into `develop` and push `develop`. Never merge to `main`, never deploy, never publish a release, never upload to a store.

## Review Focus

1. **An output flood while the phone is slow** (`yes | head -100000`, `cat` of a large file). The view merges changes and never queues, the phone ends on the final screen, its history stays in order, and the Mac stays responsive. Pinned in Task 4 (`floodEndsOnTheLastScreen`).
2. **Wide, combining and emoji cells from a real Ghostty** (CJK, `e` + U+0301, a flag, `❤️`, Vietnamese). Each Ghostty cell stays one Link cell: a flag is never split into two regional-indicator cells, and two narrow letters are never merged into one. Pinned in Task 2 (`realGhosttyCellsSurviveTheConversion`).
3. **The tab or the workspace is closed on the Mac while the phone views it.** The view ends with `gone` instead of hanging on a terminal that is gone. Pinned in Task 6 (`aViewEndsGoneWhenItsTerminalLeavesTheList`).
4. **The phone and the Mac type in turns.** The grid goes to whoever typed last, and the phone's own keystrokes never hand it to the Mac. Pinned in Task 3 (`turnsOfTypingHandTheGridBackAndForth`).
5. **A terminal with no live surface yet** (restored and never shown, or a hibernated agent). The view waits, and shows the terminal once its runtime starts. Pinned in Task 4 (`aTerminalWithoutALiveSurfaceShowsOnceItStarts`) and Task 6 (`liveSourceOpensAListedTerminalAndJoinsItsSizing`, which goes through the materializing path).

---

## File map

| Path | Responsibility | Task |
| --- | --- | --- |
| `Sources/Mobile/MobileTerminalFrameSink.swift` (new) | `MobileTerminalFrameSink`, `MobileTerminalFrameSinkRegistry` | 1 |
| `Sources/Mobile/MobileTerminalRenderObserver.swift` | Sink registry, demand, notification in the flush | 1 |
| `Sources/Mobile/MobileTerminalByteTee.swift` | `hasOutputDemand`, the sink-demand gate | 1 |
| `Sources/ShellX/Remote/Link/ShellXLinkGridConverter.swift` (new) | Render-grid frame → `TerminalGridFrame` | 2 |
| `Sources/ShellX/Remote/Link/TerminalController+ShellXLinkSizing.swift` (new) | Link sizing participant, remote-input activity | 3 |
| `Sources/TerminalController.swift` | Two stored properties (3); `v2MobileTerminalCreate(params:preserveSelection:)` (7) | 3, 7 |
| `Sources/TerminalController+SharedSizing.swift` | Activity suppression; reset and remove clear the new state | 3 |
| `docs/shared-terminal-sizing.md` | "ShellX Link phones" paragraph | 3 |
| `Sources/ShellX/Remote/Link/ShellXLinkFramePacing.swift` (new) | Pull-based hand-off to `MobileTerminalFramePacer` | 4 |
| `Sources/ShellX/Remote/Link/ShellXLinkTerminalView.swift` (new) | `TerminalView` + frame sink | 4, 5 |
| `Sources/ShellX/Remote/Link/ShellXLinkKeyChord.swift` (new) | Phone key + modifiers → Mac key name | 5 |
| `Sources/ShellX/Remote/Link/ShellXLinkTerminalViewSource.swift` (new) | `TerminalViewSource`: lookup, outcomes, `gone` | 6 |
| `Sources/ShellX/Remote/Link/ShellXLinkTerminalView+Live.swift`, `ShellXLinkTerminalViewSource+Live.swift` (new) | Live closures over `TerminalController` | 6 |
| `Sources/ShellX/Remote/Link/ShellXLinkWorkspaceSource.swift` | `TerminalCreator`; `listedWorkspaceID(holding:)` | 6, 7 |
| `Sources/ShellX/Remote/Link/ShellXLinkHostController.swift`, `Sources/ShellX/Remote/ShellXRemoteService+App.swift` | `Sources`, `makeLinkHost`, wiring | 8 |
| `cmuxTests/MobileTerminalFrameSinkTests.swift` (new) | Seam tests, iroh unchanged | 1 |
| `cmuxTests/ShellXLinkTerminalTestSupport.swift` (new) | Real-Ghostty helpers, recorders, `FakeLinkMac` | 2, 4, 6 |
| `cmuxTests/ShellXLinkGridConverterTests.swift`, `ShellXLinkSizingTests.swift`, `ShellXLinkFramePacingTests.swift`, `ShellXLinkTerminalViewFrameTests.swift`, `ShellXLinkTerminalViewInputTests.swift`, `ShellXLinkTerminalViewSourceTests.swift`, `ShellXLinkTerminalCreateTests.swift`, `ShellXLinkTerminalSessionTests.swift` (new) | Behaviour tests | 2–8 |
| `cmuxTests/ShellXLinkWorkspaceSourceTests.swift`, `Packages/macOS/CmuxRemoteWorkspace/Tests/CmuxRemoteWorkspaceTests/RemoteCLIRelayPolicyTests.swift` | `terminal.create` source tests; relay deny pin | 7 |

The iroh guard suites, run in Tasks 0, 1 and 10, are: `MobileHostAuthorizationTests` (it includes the connection event-lane and lifecycle tests), `MobileHostTerminalThemeTests`, `MobileHostSurfaceEventLaneTests`, `MobileTerminalByteTeeAppendCostTests`, `MobileTerminalFramePacerTests`, `DeviceTerminalMirrorTests`, `MobileTerminalInputRoutingTests`, `MobileTerminalReplayHibernationTests`, `MobileViewportApplyGovernorTests`, `CloudTerminalSharedSizingTests`, `LocalTerminalSizingHostLifecycleTests`. Below, IROH_SUITES means this list.

---

### Task 0: Worktree, setup, baseline

**Files:** none.

- [ ] **Step 1: Check that 2A is merged**

```bash
cd /Users/lehuuphu/Documents/myProjects/shellx
git show develop:shellx-link/Sources/ShellXLinkSession/TerminalViewSource.swift > /dev/null && echo present
git grep -c 'terminalHistoryFillMaxBytes = 262_144' develop -- shellx-link/Sources
```
Expected: `present`, then a line ending in `:1`. If either check fails, stop and report "2A is not on develop; 2B cannot start".

- [ ] **Step 2: Create the worktree and set it up** (superpowers:using-git-worktrees; this repo keeps worktrees in `.worktrees/`)

```bash
git worktree add .worktrees/terminal-2b-mac -b feat/shellx-terminal-2b-mac develop
cd .worktrees/terminal-2b-mac
toknix run ./scripts/setup.sh
```
Expected: the setup ends with `==> Setup complete!`. It initializes `ghostty` and `vendor/bonsplit` and links `GhosttyKit.xcframework`.

- [ ] **Step 3: Baseline.** The first app test run builds from cold, which can take 40 minutes, so run it in the background.

Run: `toknix run swift test --package-path shellx-link 2>&1 | tail -3`. Expected: the summary ends `with 0 failures (0 unexpected)`.
Run: `toknix run scripts/shellx/test-app.sh <IROH_SUITES> ShellXLinkWorkspaceSourceTests ShellXLinkHostPolicyTests`. Expected: `** TEST SUCCEEDED **`. Write down any failing test by name: the later tasks compare against this list. If one fails, re-run it alone once, then record it as pre-existing.

---

### Task 1: Frame-sink seam in the render observer and the byte tee

**Files:**
- Create: `Sources/Mobile/MobileTerminalFrameSink.swift`
- Modify: `Sources/Mobile/MobileTerminalRenderObserver.swift`. These spots: the class line 12 (conformance), the surface-theme handler 103-113, `stop()` 117-138, `noteTerminalBytes` 140-148, `refreshNotificationDemand` 175-214, `enqueueTerminalUpdate` 216-227, `flushTerminalUpdates` 244-328, `invalidateTerminalThemes` 668-676, and the debug block 762-766.
- Modify: `Sources/Mobile/MobileTerminalByteTee.swift` (lines 90-91 and the gate at 120-126)
- Test: create `cmuxTests/MobileTerminalFrameSinkTests.swift`

**Interfaces:**
- Produces:

```swift
/// A consumer of one terminal surface's render updates outside the iroh event lane (a ShellX Link terminal view).
/// The observer calls it on the main actor after the surface parsed output, drew, ticked or changed its theme; the
/// sink captures and diffs on its own schedule and returns at once (no capture inside the call).
@MainActor
protocol MobileTerminalFrameSink: AnyObject {
    /// The surface whose updates the sink receives; constant for the sink's lifetime.
    var frameSinkSurfaceID: UUID { get }
    /// The surface may have drawn new content.
    func terminalSurfaceMayHaveChanged()
}

/// Where frame sinks register (the app passes ``MobileTerminalRenderObserver/shared``; tests pass a recorder).
@MainActor
protocol MobileTerminalFrameSinkRegistry: AnyObject {
    func addFrameSink(_ sink: any MobileTerminalFrameSink)
    func removeFrameSink(_ sink: any MobileTerminalFrameSink)
}

// MobileTerminalRenderObserver: MobileTerminalFrameSinkRegistry (on its declaration)
func addFrameSink(_ sink: any MobileTerminalFrameSink)      // weak; adding twice keeps one registration
func removeFrameSink(_ sink: any MobileTerminalFrameSink)
#if DEBUG
var debugFrameSinkCountForTesting: Int { get }
var debugPendingSurfaceCountForTesting: Int { get }           // pendingSurfaceIDs.count
var debugRenderGridStateSurfaceCountForTesting: Int { get }   // renderGridStatesBySurfaceID.count (iroh baselines)
func debugEnqueueTerminalUpdateForTesting(surfaceID: UUID?)   // calls enqueueTerminalUpdate(surfaceID:)
func debugFlushTerminalUpdatesForTesting()                    // calls flushTerminalUpdates()
#endif

// MobileTerminalByteTee
/// Whether PTY output must reach `publishFromMain`: an iroh `terminal.bytes` or `terminal.render_grid` subscriber,
/// an iroh terminal lane, or a frame sink. Read on Ghostty's IO thread.
nonisolated var hasOutputDemand: Bool { get }
/// The render observer turns this on with its first frame sink and off with its last.
nonisolated func setFrameSinkDemand(_ active: Bool)
```

Observer rules. Each one keeps the iroh behaviour when no sink exists:
1. Storage: `private var frameSinksBySurfaceID: [UUID: [ObjectIdentifier: WeakFrameSink]]` with a nested `private struct WeakFrameSink { weak var sink: (any MobileTerminalFrameSink)? }`. The first add calls `MobileTerminalByteTee.shared.setFrameSinkDemand(true)` and then `refreshNotificationDemand()`. When the registry becomes empty (on remove, or on pruning released sinks), it calls `setFrameSinkDemand(false)` and then `refreshNotificationDemand()`.
2. `refreshNotificationDemand()`: `shouldRetainDemand = hasAnyRenderEventSubscribers || !frameSinksBySurfaceID.isEmpty`. Nothing else in it changes.
3. `noteTerminalBytes(surfaceID:)` and `enqueueTerminalUpdate(surfaceID:)`. Their guards also pass for sinks: `|| frameSinksBySurfaceID[surfaceID] != nil` for the first, `|| !frameSinksBySurfaceID.isEmpty` for the second. Their bodies do not change.
4. `flushTerminalUpdates()`: the top guard also passes for sinks. Right after it clears the pending state (after line 262), it calls `notifyFrameSinks(surfaceIDs: surfaceIDs.union(themeSurfaceIDs), all: shouldEmitAllThemes || (surfaceIDs.isEmpty && shouldEmitGlobal))`. This is the same "all surfaces" rule iroh uses at line 309. The iroh code after it does not change.
5. `private func notifyFrameSinks(surfaceIDs: Set<UUID>, all: Bool)` iterates a copy of the registry. It calls `terminalSurfaceMayHaveChanged()` on every live sink of the named surfaces (of every surface when `all`), drops released entries, and applies rule 1's emptiness step.
6. The `ghosttySurfaceThemeDidChange` handler calls `notifyFrameSinks(surfaceIDs: [surfaceID], all: false)` before its iroh guard. `invalidateTerminalThemes()` calls `notifyFrameSinks(surfaceIDs: [], all: true)` first.
7. `stop()` also clears the registry and calls `setFrameSinkDemand(false)`.

Byte tee: add `nonisolated private let frameSinkDemand = AtomicBooleanGate(false)`. `hasOutputDemand` is the current three-way condition `|| frameSinkDemand.loadAcquire()`, and `append` becomes `guard hasOutputDemand else { return }`.

- [ ] **Step 1: Write the failing tests** (`@MainActor @Suite("Mobile terminal frame sinks", .serialized, .timeLimit(.minutes(1)))`; each body runs inside `AppContextSerialGate.withExclusiveAppContext`). Every test starts with `MobileHostService.debugResetEventSubscriptionsForTesting(); observer.stop(); observer.start()` and ends with `observer.stop(); observer.start()`, where `observer = MobileTerminalRenderObserver.shared`. Use a file-private `@MainActor final class RecordingFrameSink: MobileTerminalFrameSink` (`init(surfaceID:)`, `private(set) var changes`) and a local `eventually(_:)` that polls every 10 ms for up to 2 s.

```swift
@Test func aSinkHoldsGhosttyNotificationsWithoutAnIrohSubscriber() {
    #expect(!observer.debugIsRetainingNotificationDemandForTesting)
    let sink = RecordingFrameSink(surfaceID: UUID())
    observer.addFrameSink(sink)
    #expect(observer.debugIsRetainingNotificationDemandForTesting && observer.debugFrameSinkCountForTesting == 1)
    #expect(MobileTerminalByteTee.shared.hasOutputDemand)
    observer.removeFrameSink(sink)
    #expect(!observer.debugIsRetainingNotificationDemandForTesting && observer.debugFrameSinkCountForTesting == 0)
    #expect(!MobileTerminalByteTee.shared.hasOutputDemand)
}

@Test func outputNotifiesOnlyTheSinksOfItsSurface() {
    let a = RecordingFrameSink(surfaceID: UUID()), b = RecordingFrameSink(surfaceID: UUID())
    observer.addFrameSink(a); observer.addFrameSink(b)
    observer.debugFlushTerminalUpdatesForTesting()          // drain what real ticks left pending; no await below
    let before = (a.changes, b.changes)
    observer.noteTerminalBytes(surfaceID: a.frameSinkSurfaceID)
    #expect(observer.debugPendingSurfaceCountForTesting == 1)
    observer.debugFlushTerminalUpdatesForTesting()
    #expect(a.changes == before.0 + 1 && b.changes == before.1)
}

@Test func aGlobalTickNotifiesEverySink()      // drain; debugEnqueueTerminalUpdateForTesting(surfaceID: nil); flush → both +1
@Test func aReleasedSinkStopsTheDemand()       // add a sink in a `do {}` scope, never remove; global enqueue + flush →
                                               // count 0, demand released, !hasOutputDemand
@Test func withoutSinksOrSubscribersOutputIsIgnored() {   // the develop behaviour, pinned
    observer.noteTerminalBytes(surfaceID: UUID())
    #expect(observer.debugPendingSurfaceCountForTesting == 0 && !MobileTerminalByteTee.shared.hasOutputDemand)
}
@Test func sinksAloneLeaveNoIrohState()        // sink on S; noteTerminalBytes(S); flush → debugRenderGridStateSurfaceCountForTesting == 0

@Test func anIrohSubscriberKeepsItsDemandWhenTheLastSinkLeaves() async {
    let session = MobileHostConnection(id: UUID(), transport: RecordingMobileHostByteTransport(),
        authorizeRequest: { _ in nil }, onAuthorizedRequest: { _ in }, handleRequest: { _ in .ok([:]) }, onClose: { _ in })
    await session.subscribe(streamID: "events", topics: ["terminal.render_grid"])
    #expect(await eventually { observer.debugIsRetainingNotificationDemandForTesting })
    observer.debugFlushTerminalUpdatesForTesting()                      // drain; no await until the check
    observer.noteTerminalBytes(surfaceID: UUID())
    #expect(observer.debugPendingSurfaceCountForTesting == 1)            // iroh behaviour, unchanged
    let sink = RecordingFrameSink(surfaceID: UUID())
    observer.addFrameSink(sink); observer.removeFrameSink(sink)
    #expect(observer.debugIsRetainingNotificationDemandForTesting && MobileTerminalByteTee.shared.hasOutputDemand)
    await session.unsubscribe(streamID: "events")
    #expect(await eventually { !observer.debugIsRetainingNotificationDemandForTesting })
    await session.close(reason: "test complete")
}
```

- [ ] **Step 2: Wire the file and see the tests fail**

Run: `./scripts/sync-test-wiring` then `toknix run scripts/shellx/test-app.sh MobileTerminalFrameSinkTests`
Expected: FAIL, the test target does not compile: `error: value of type 'MobileTerminalRenderObserver' has no member 'addFrameSink'` (xcodebuild ends `** TEST FAILED **`).

- [ ] **Step 3: Commit the red tests**

```bash
git add cmuxTests/MobileTerminalFrameSinkTests.swift cmux.xcodeproj/project.pbxproj
git commit -m "test(shellx): frame sinks take render updates without an iroh subscriber (failing)"
```

- [ ] **Step 4: Implement** the protocols, the registry, rules 1–7 and the byte tee gate. Then run `./scripts/wire-app-sources.py Sources/Mobile/MobileTerminalFrameSink.swift`.

- [ ] **Step 5: Run the seam tests and the iroh guard suites**

Run: `toknix run scripts/shellx/test-app.sh MobileTerminalFrameSinkTests <IROH_SUITES>`
Expected: `** TEST SUCCEEDED **`, with no failure beyond the Task 0 baseline list.

- [ ] **Step 6: Commit**

```bash
git add Sources/Mobile/MobileTerminalFrameSink.swift Sources/Mobile/MobileTerminalRenderObserver.swift \
  Sources/Mobile/MobileTerminalByteTee.swift cmux.xcodeproj/project.pbxproj
git commit -m "feat(shellx): frame-sink seam in the render observer and the byte tee"
```

---

### Task 2: Converting render-grid captures to Link frames

**Files:**
- Create: `Sources/ShellX/Remote/Link/ShellXLinkGridConverter.swift`
- Create: `cmuxTests/ShellXLinkTerminalTestSupport.swift`, `cmuxTests/ShellXLinkGridConverterTests.swift`

**Interfaces:**
- Consumes: 2A's `TerminalGridFrame`, `TerminalFrameHead`, `TerminalCursor`, `TerminalPalette`, `TerminalStyle`, `TerminalRun`, `TerminalLine`, `TerminalAttribute`, `TerminalScreen` and `TerminalFrameSplitter` (the last two in tests). CMUXMobileCore's `MobileTerminalRenderGridFrame` (`RowSpan`, `Style`, `Cursor`) and `TerminalTheme`.
- Produces:

```swift
/// Turns cmux render-grid captures of one terminal into ShellX Link grid frames (PROTOCOL.md 11.5).
struct ShellXLinkGridConverter {
    /// The Link palette of the capture's effective theme: lowercase colors, exactly 256 indexed colors.
    let palette: TerminalPalette
    init(theme: TerminalTheme)
    /// A snapshot of a full capture: the screen and, on the main screen, its history rows.
    func snapshot(_ frame: MobileTerminalRenderGridFrame) -> TerminalGridFrame
    /// A delta of a row-delta capture (`frame.full == false`).
    func delta(_ frame: MobileTerminalRenderGridFrame) -> TerminalGridFrame
    /// The runs of one row's spans; `styles` holds the frame's Link styles by id (ids missing draw in the default style).
    func runs(of spans: [MobileTerminalRenderGridFrame.RowSpan], styles: [Int: TerminalStyle]) -> [TerminalRun]
    /// The Link style of a capture style; nil when it draws as the default style or its id is outside 1...65_535.
    func style(_ style: MobileTerminalRenderGridFrame.Style) -> TerminalStyle?
    static func linkPalette(of theme: TerminalTheme) -> TerminalPalette
    /// `#rrggbb` lowercase, or nil when `raw` is not `#` plus 6 hex digits.
    static func linkColor(_ raw: String?) -> String?
}
```

Rules, which the tests pin:
- **Palette:** `theme.validatedOrDefault()`. `fg` and `bg` are the theme's `foreground` and `background`, and `cursor` is the theme's `cursor` when it parses. `colors` is the theme's palette when it has 256 entries. A 16-entry palette is completed with xterm's values. For `i` in 16…231: with `n = i - 16`, the components are `(n / 36, (n / 6) % 6, n % 6)`, each mapped `c == 0 ? 0 : 55 + 40 * c`. For `i` in 232…255 the color is gray `8 + 10 * (i - 232)`. Every color is lowercased.
- **Style:** the attrs come in this order: bold, faint, italic, underline, blink, inverse, invisible, strikethrough→`strike`, overline.
  - fg:
    - source `.palette` (index `p` in 0…255): `fg = p`. Exception: when the resolved `foreground` parses and differs from `palette.colors[p]`, it is `fgRgb` = the resolved color (the Mac drew it bright or bold-colored).
    - `.rgb`: `fgRgb`.
    - `.defaultColor`: none, unless `bold` and the resolved color differs from `palette.fg`; then `fgRgb`.
    - `nil` (legacy): `fgRgb` when it parses and differs from `palette.fg`.
  - bg: `.palette` gives `bg = p`. `.rgb` gives `bgRgb`. `.defaultColor` gives none. `nil` gives `bgRgb` when it differs from `palette.bg`.
  - A result with no color and no attribute is `nil`.
- **Runs:** each span becomes exactly one run, in column order, and spans are never merged. Ghostty sends two kinds of span. One is a run of narrow cells holding one scalar each, so its scalar count equals its width. The other is one cell of its own, wide or holding a cluster (`renderGridCellNeedsOwnSpan`, `ghostty/src/apprt/embedded.zig:3736`). The converter tells them apart like this:

```text
expected = column after the previous run of this row (0 for the first)
for span in spans sorted by column:
    scalars = span.text.unicodeScalars.count;  width = span.cellWidth ?? scalars
    skip the span when scalars == 0 or width <= 0
    x = span.column == expected ? nil : span.column
    s = styles[span.styleID] != nil ? span.styleID : nil
    if scalars == width && !(width == 2 && span.text.count == 1):        // narrow cells
        run(x, t: span.text, s);                         expected = span.column + scalars
    else:                                                                 // one cell
        run(x, t: span.text cut to <= 32 UTF-8 bytes on a scalar boundary, s, w: min(width, 2))
        expected = span.column + min(width, 2)
```

  The only ambiguous shape is two scalars over two columns. `"ab"` (two Characters) is two narrow cells. A flag or `❤️` (one Character) is one cell.
- **snapshot:** the head has `kind .snapshot`, the frame's `cols` and `rows`, `alt = activeScreen == .alternate`, the cursor, the converter's `palette`, and `history = alt ? 0 : scrollbackRows`. The cursor maps `column→x`, `row→y`, `style→shape`, `visible`, `blinking→blink`; a missing cursor becomes `TerminalCursor(x: 0, y: 0, visible: false)`. Lines: first the history rows that have spans, at `y = row - scrollbackRows` (main screen only, oldest first), then the screen rows that have spans, at `y = row`. Blank rows are left out. `styles` lists only the Link styles its runs use, by ascending id.
- **delta:** the head has `kind .delta`, the frame's `cols`, `rows` and `alt`, the cursor, `scroll = alt ? 0 : scrolledRows` and `history = alt ? 0 : scrollbackRows` (a burst's carried rows). There is one line per row in `clearedRows`, with that row's runs; a changed row with no spans gets a line without runs, which blanks it. The carried history lines come first, as in a snapshot.

Test support (`ShellXLinkTerminalTestSupport.swift`) extends the existing real-Ghostty terminal `cmuxTests/ScrollbackTestTerminal.swift`. That terminal is manual-mirror, hosted in a window, with `launch()`, `output(_:)`, `inputBytesBeforeBarrier()` and `close()`. The extension adds:

```swift
extension ScrollbackTestTerminal {
    /// ghostty_surface_set_grid_size, then waits up to 5 s until a capture shows the size (as CloudRestoreReplayFixture.setGrid).
    func setGrid(columns: Int, rows: Int) async throws
    /// Waits up to 5 s until `surface.readText(region: .screen)` contains `text`.
    func waitForScreen(containing text: String) async throws
    /// surface.mobileRenderGridFrame(stateSeq: 0, full: true, scrollbackLines: history, includeTheme: true, anchor: .screen)?.frame
    func capture(history: Int) -> MobileTerminalRenderGridFrame?
}
```

- [ ] **Step 1: Write the failing tests** (`@Suite("ShellX Link grid converter")`). The fixtures are a gray test theme, `TerminalTheme(background: "#101010", foreground: "#D0D0D0", cursor: "#FF8800", selectionBackground: "#333333", selectionForeground: "#FFFFFF", palette: (0..<256).map { String(format: "#%02X%02X%02X", $0, $0, $0) })`, a converter built from it, and `span(_ column:_ text:width:style:row:)` building `RowSpan(row:column:styleID:text:cellWidth:)`.

```swift
@Test func narrowSpansAreNarrowRunsAndAContiguousRunOmitsItsColumn() {
    #expect(converter.runs(of: [span(0, "ls", width: 2), span(2, " -la", width: 4, style: 1), span(10, "x", width: 1)],
                           styles: [1: TerminalStyle(id: 1, fg: 2)])
            == [TerminalRun(text: "ls"), TerminalRun(text: " -la", style: 1), TerminalRun(x: 10, text: "x")])
}
@Test func aWideCharacterIsOneCellTwoColumnsWide()   // span(3, "中", width: 2) → [TerminalRun(x: 3, text: "中", width: 2)]
@Test func aCombiningMarkStaysInItsCell()           // span(0, "e\u{301}", width: 1) → [TerminalRun(text: "e\u{301}", width: 1)]
@Test(arguments: [("ab", nil as Int?), ("\u{1F1FB}\u{1F1F3}", 2), ("\u{2764}\u{FE0F}", 2)])
func twoScalarsOverTwoColumns(text: String, cellWidth: Int?) {
    #expect(converter.runs(of: [span(0, text, width: 2)], styles: [:]) == [TerminalRun(text: text, width: cellWidth)])
}
@Test func aClusterOver32BytesIsCutOnAScalarBoundary() throws {
    let run = try #require(converter.runs(of: [span(0, "e" + String(repeating: "\u{301}", count: 20), width: 1)], styles: [:]).first)
    #expect(run.text == "e" + String(repeating: "\u{301}", count: 15) && run.width == 1)   // 31 bytes; 16 marks would be 33
}
@Test func colorsAreThoseTheMacDraws() {
    typealias S = MobileTerminalRenderGridFrame.Style
    #expect(converter.style(S(id: 1, foreground: "#020202", foregroundSource: .palette, foregroundPaletteIndex: 2)) == TerminalStyle(id: 1, fg: 2))
    #expect(converter.style(S(id: 2, foreground: "#0A0A0A", foregroundSource: .palette, foregroundPaletteIndex: 2, bold: true))
            == TerminalStyle(id: 2, fgRgb: "#0a0a0a", attrs: [.bold]))
    #expect(converter.style(S(id: 3, foreground: "#A6E22E", background: "#336699", foregroundSource: .rgb, backgroundSource: .rgb))
            == TerminalStyle(id: 3, fgRgb: "#a6e22e", bgRgb: "#336699"))
    #expect(converter.style(S(id: 4, foreground: "#FFFFFF", foregroundSource: .defaultColor, bold: true)) == TerminalStyle(id: 4, fgRgb: "#ffffff", attrs: [.bold]))
    #expect(converter.style(S(id: 5, foreground: "#D0D0D0", background: "#101010", foregroundSource: .defaultColor, backgroundSource: .defaultColor)) == nil)
    #expect(converter.style(S(id: 6, background: "#040404", backgroundSource: .palette, backgroundPaletteIndex: 4)) == TerminalStyle(id: 6, bg: 4))
    #expect(converter.style(S(id: 7, bold: true, faint: true, italic: true, underline: true, blink: true, inverse: true,
                              invisible: true, strikethrough: true, overline: true))?.attrs
            == [.bold, .faint, .italic, .underline, .blink, .inverse, .invisible, .strike, .overline])
    #expect(converter.style(S(id: 70_000, bold: true)) == nil)
}
@Test func aSixteenColorThemeIsCompletedToXterm256() {
    let colors = ShellXLinkGridConverter.linkPalette(of: .monokai).colors
    #expect(colors.count == 256 && colors[16] == "#000000" && colors[17] == "#00005f" && colors[231] == "#ffffff"
            && colors[232] == "#080808" && colors[255] == "#eeeeee")
}
@Test func aSnapshotCarriesScreenHistoryCursorAndPalette() throws {
    let frame = try MobileTerminalRenderGridFrame(surfaceID: "s", stateSeq: 1, columns: 10, rows: 3,
        cursor: .init(row: 2, column: 1, visible: true, style: .bar, blinking: true),
        styles: [.default, .init(id: 1, foreground: "#020202", foregroundSource: .palette, foregroundPaletteIndex: 2)],
        rowSpans: [span(0, "hello", width: 5, style: 1), span(0, "$ ", width: 2, row: 2)],
        terminalTheme: theme, scrollbackRows: 2,
        scrollbackSpans: [span(0, "old 1", width: 5, row: 0), span(0, "old 2", width: 5, row: 1)], anchor: .screen)
    let link = converter.snapshot(frame)
    #expect(link.head == TerminalFrameHead(kind: .snapshot, cols: 10, rows: 3, alt: false,
        cursor: TerminalCursor(x: 1, y: 2, shape: .bar, visible: true, blink: true), palette: converter.palette, history: 2))
    #expect(link.styles == [TerminalStyle(id: 1, fg: 2)])
    var screen = TerminalScreen(); screen.apply(link)
    #expect(screen.screenText() == ["hello", "", "$"] && screen.historyText() == ["old 1", "old 2"])
    _ = try TerminalFrameSplitter.parts(of: link, revision: 1, terminalId: "t-1")     // 2A's codec accepts it
}
@Test func aBurstDeltaCarriesItsScrollChangedRowsAndHistory() throws {
    // full: false, clearedRows [0, 1], rowSpans [span(0, "r6", width: 2)], scrollbackRows 2 with "r4", "r5", scrolledRows 4
    // head == TerminalFrameHead(kind: .delta, cols: 10, rows: 2, cursor: TerminalCursor(x: 0, y: 1), history: 2, scroll: 4)
    // link.lines.contains(TerminalLine(y: 1)); applied after converter.snapshot of rows ["r1","r2"]:
    // screenText == ["r6", ""], historyText == ["r1", "r2", "r4", "r5"]
}
@Test func theAlternateScreenHasNoHistory()     // activeScreen .alternate with scrollbackRows 3 → head.alt, history 0, no y < 0
@Test func realGhosttyCellsSurviveTheConversion() async throws {      // Review Focus 2
    try await AppContextSerialGate.withExclusiveAppContext {
        let terminal = try ScrollbackTestTerminal(); defer { terminal.close() }
        try await terminal.launch(); try await terminal.setGrid(columns: 30, rows: 4)
        try terminal.output("\u{1b}ca中e\u{301}\u{1F1FB}\u{1F1F3}\u{2764}\u{FE0F}z\r\nTiếng Việt\r\n")
        try await terminal.waitForScreen(containing: "Vi")
        let capture = try #require(terminal.capture(history: 0))
        let converter = ShellXLinkGridConverter(theme: try #require(capture.terminalTheme))
        var screen = TerminalScreen(); screen.apply(converter.snapshot(capture))
        let texts = (0..<30).compactMap { x -> String? in
            if case let .glyph(text, _, _) = screen.cell(x: x, y: 0) { return text } else { return nil } }
        #expect(texts.contains("中") && texts.contains("e\u{301}") && texts.contains("\u{1F1FB}\u{1F1F3}"))
        #expect(!texts.contains("\u{1F1FB}") && !texts.contains("\u{1F1F3}"))
        #expect(screen.screenText()[1] == "Tiếng Việt")
    }
}
```

- [ ] **Step 2: Wire and run.** Run `./scripts/sync-test-wiring`, then `toknix run scripts/shellx/test-app.sh ShellXLinkGridConverterTests`. Expected: FAIL with `error: cannot find 'ShellXLinkGridConverter' in scope`.
- [ ] **Step 3: Commit red:** `git add cmuxTests/ShellXLinkTerminalTestSupport.swift cmuxTests/ShellXLinkGridConverterTests.swift cmux.xcodeproj/project.pbxproj && git commit -m "test(shellx): render-grid to Link frame conversion (failing)"`
- [ ] **Step 4: Implement** the converter, then run `./scripts/wire-app-sources.py Sources/ShellX/Remote/Link/ShellXLinkGridConverter.swift`.
- [ ] **Step 5: Run:** `toknix run scripts/shellx/test-app.sh ShellXLinkGridConverterTests`. Expected: `** TEST SUCCEEDED **`.
- [ ] **Step 6: Commit:** `git add Sources/ShellX/Remote/Link/ShellXLinkGridConverter.swift cmux.xcodeproj/project.pbxproj && git commit -m "feat(shellx): convert render-grid captures to ShellX Link frames"`

---

### Task 3: The phone as its own `latest` sizing participant

**Files:**
- Create: `Sources/ShellX/Remote/Link/TerminalController+ShellXLinkSizing.swift`
- Modify: `Sources/TerminalController.swift:314` (add two stored properties after `cloudSizingRelaysBySurfaceID`)
- Modify: `Sources/TerminalController+SharedSizing.swift`: `noteLocalTerminalSizingActivity` 208-214, `resetLocalSizingHosts` 233-238, `removeLocalSizingHost` 243-250
- Modify: `docs/shared-terminal-sizing.md`: add a paragraph after the "Participants" section's last bullet (line 74)
- Test: create `cmuxTests/ShellXLinkSizingTests.swift`

**Interfaces:**
- Consumes: `localSizingHost(surfaceID:create:)`, `resolveSharedSizing(surfaceID:reports:countsOverride:immediate:reason:)`, `clearMobileViewportReport(surfaceID:clientID:reason:)`, `noteMobileSizingActivity(surfaceID:clientID:)`, `localSizingSetPolicy(surfaceID:policy:)`, `MobileViewportReport`, `LocalTerminalSizingHost.phoneParticipantID(clientID:)` and `forgetPhone(_:)`, `TerminalSizingPolicy.fitEveryone` and `.latest`.
- Produces:

```swift
// TerminalController (stored, TerminalController.swift)
/// Surfaces whose explicit input a remote participant is applying right now, with nesting depth.
var remoteParticipantInputDepthBySurfaceID: [UUID: Int] = [:]
/// The policy a terminal had before its first ShellX Link phone made it `latest`.
var shellXLinkSizingPolicyRestoreBySurfaceID: [UUID: TerminalSizingPolicy] = [:]

// TerminalController+ShellXLinkSizing.swift (@MainActor extension)
static let shellXLinkSizingClientIDPrefix = "shellx-link-"
/// A ShellX Link phone starts viewing `surfaceID` at columns × rows. It joins the shared sizing as its own counting
/// participant (attach is its activity), and the terminal runs `latest` while any Link phone views it, unless someone chose
/// a policy other than Fit everyone for it. Returns the grid the terminal is expected to take (the replay fence's value).
@discardableResult
func shellXLinkSizingAttach(surfaceID: UUID, clientID: String, columns: Int, rows: Int) -> (columns: Int, rows: Int)?
/// The phone's grid changed: a new report and the phone's activity.
func shellXLinkSizingResize(surfaceID: UUID, clientID: String, columns: Int, rows: Int)
/// The phone stopped viewing: its report goes and the Mac's size returns at once. After the last Link phone leaves, a
/// `latest` this code set goes back to the recorded policy (unless someone changed it meanwhile).
func shellXLinkSizingDetach(surfaceID: UUID, clientID: String)
/// Runs one batch of a remote participant's input so the Mac pane's explicit-input hook does not count it as the Mac's
/// activity, then counts it as that participant's.
func performRemoteParticipantInput(surfaceID: UUID, clientID: String, _ body: () -> Void)
```

Behaviour:
- **attach:**
  1. `localSizingHost(surfaceID:create: true)`.
  2. If a host exists, its `state.policy == .fitEveryone`, and no restore record exists: record `.fitEveryone`, then `localSizingSetPolicy(surfaceID:policy: .latest)`.
  3. Store `MobileViewportReport(columns:rows:updatedAt: Date(), sticky: true)` for `clientID`, with `deviceKind` left at `.iphone`. It is sticky, so no TTL timer.
  4. Return `resolveSharedSizing(surfaceID:reports:countsOverride: (clientID: clientID, value: true), reason: "shellx.link.attach")`.
- **resize:** replace the report's columns and rows (keep it sticky), call `resolveSharedSizing(… reason: "shellx.link.resize")`, then `noteMobileSizingActivity(surfaceID:clientID:)`.
- **detach:**
  1. `clearMobileViewportReport(surfaceID:clientID:reason: "shellx.link.detach")`.
  2. `forgetPhone(phoneParticipantID(clientID:))` on the stored host.
  3. If no report with the prefix remains for the surface and a record exists: when `state.policy == .latest`, set the recorded policy back; then drop the record.
- **performRemoteParticipantInput:** increment the depth, run `body`, decrement (remove at 0), then `noteMobileSizingActivity(surfaceID:clientID:)`.
- **`noteLocalTerminalSizingActivity`:** right after `guard var host = …`, add `guard remoteParticipantInputDepthBySurfaceID[surfaceID] == nil else { return }`.
- **Cleanup:** `resetLocalSizingHosts()` clears `shellXLinkSizingPolicyRestoreBySurfaceID`; `removeLocalSizingHost(surfaceID:)` drops that surface's record.
- **Doc paragraph:** "**ShellX Link phones.** A phone viewing a terminal over ShellX Link joins as participant `mobile:shellx-link-<uuid>` (one per view, `device_kind` `iphone`) with `counts_override: true`, so the same-user deferral above does not apply to it. While at least one Link phone views a terminal whose policy is Fit everyone, the host runs it as `latest` and goes back to Fit everyone after the last one leaves; a policy someone chose is kept. Link input runs inside `TerminalController.performRemoteParticipantInput`, so it is the phone's activity, not the Mac pane's (`Sources/ShellX/Remote/Link/TerminalController+ShellXLinkSizing.swift`)."

- [ ] **Step 1: Write the failing tests** (`@MainActor @Suite("ShellX Link sizing", .serialized, .timeLimit(.minutes(1)))`). Copy `withAppContext` from `cmuxTests/LocalTerminalSizingHostLifecycleTests.swift:63-87`. In each test: `let panelId = try #require(workspace.focusedPanelId)`, `try #require(controller.terminalSocketTarget(surfaceID: panelId) != nil)`, and `defer { controller.debugResetMobileViewportReportsForTesting() }`. The helpers are `state = controller.terminalSharing.snapshot(for: panelId)?.state`, `phone = "mobile:shellx-link-a"` and `mac = "mac:\(panelId.uuidString.lowercased())"`.

```swift
@Test func aLinkPhoneOwnsTheGridOnceItOpens() {
    controller.shellXLinkSizingAttach(surfaceID: panelId, clientID: "shellx-link-a", columns: 46, rows: 30)
    #expect(state?.policy == .latest && state?.owners == [phone] && state?.cols == 46 && state?.rows == 30)
    #expect(state?.participant(phone)?.counts == true && state?.participant(phone)?.participant.countsOverride == true)
}
@Test func macTypingTakesTheGridBack()                  // attach; controller.noteLocalTerminalSizingActivity(surfaceID:) → owners == [mac]
@Test func linkInputIsThePhonesActivity()               // attach; Mac activity; performRemoteParticipantInput(…) {
                                                        //   controller.noteLocalTerminalSizingActivity(surfaceID: panelId) } → owners == [phone]
@Test func turnsOfTypingHandTheGridBackAndForth()       // Review Focus 4: attach, then 3 × (Mac activity → [mac];
                                                        //   remote input whose body runs the Mac hook → [phone])
@Test func aPhoneResizeIsItsActivityAndItsSize()        // attach 46×30; Mac activity; resize 80×24 → owners [phone], cols 80, rows 24
@Test func closingTheViewGivesTheMacItsSizeAndPolicyBack() {
    controller.shellXLinkSizingAttach(surfaceID: panelId, clientID: "shellx-link-a", columns: 46, rows: 30)
    controller.shellXLinkSizingDetach(surfaceID: panelId, clientID: "shellx-link-a")
    #expect(state?.owners == [mac] && state?.policy == .fitEveryone && state?.participant(phone) == nil)
    #expect(controller.mobileViewportReportsBySurfaceID[panelId] == nil)
}
@Test func aPolicySomeoneChoseIsKept()                  // largest = TerminalSizingPolicy(mode: .largest). (a) _ = controller.localSizingHost(
                                                        // surfaceID: panelId, create: true); localSizingSetPolicy(surfaceID:policy: largest);
                                                        // attach and detach → policy stays largest. (b) attach (→ .latest), then
                                                        // localSizingSetPolicy(largest), detach → still largest
@Test func twoLinkPhonesKeepLatestUntilTheLastLeaves()  // attach a, b; detach a → .latest; detach b → .fitEveryone
@Test func otherPhonesKeepTheirRules() {                // a non-Link phone report: policy and override untouched
    controller.debugSetMobileViewportReportForTesting(surfaceID: panelId, clientID: "iphone-1", columns: 50, rows: 20)
    _ = controller.resolveSharedSizing(surfaceID: panelId, reports: controller.mobileViewportReportsBySurfaceID[panelId] ?? [:], reason: "test")
    #expect(state?.policy == .fitEveryone && state?.participant("mobile:iphone-1")?.participant.countsOverride == nil)
}
```

- [ ] **Step 2: Wire and run:** `./scripts/sync-test-wiring`, then `toknix run scripts/shellx/test-app.sh ShellXLinkSizingTests`. Expected: FAIL with `error: value of type 'TerminalController' has no member 'shellXLinkSizingAttach'`.
- [ ] **Step 3: Commit red:** `git add cmuxTests/ShellXLinkSizingTests.swift cmux.xcodeproj/project.pbxproj && git commit -m "test(shellx): a Link phone is its own latest sizing participant (failing)"`
- [ ] **Step 4: Implement** the stored properties, the extension, the three edits and the doc paragraph, then run `./scripts/wire-app-sources.py Sources/ShellX/Remote/Link/TerminalController+ShellXLinkSizing.swift`.
- [ ] **Step 5: Run:** `toknix run scripts/shellx/test-app.sh ShellXLinkSizingTests LocalTerminalSizingHostLifecycleTests CloudTerminalSharedSizingTests MobileViewportApplyGovernorTests`. Expected: `** TEST SUCCEEDED **`.
- [ ] **Step 6: Commit:** `git add Sources/ShellX/Remote/Link/TerminalController+ShellXLinkSizing.swift Sources/TerminalController.swift Sources/TerminalController+SharedSizing.swift docs/shared-terminal-sizing.md cmux.xcodeproj/project.pbxproj && git commit -m "feat(shellx): Link phones join shared sizing as their own participant"`

---

### Task 4: The terminal view's frames: snapshot, deltas, pacing, resync, close

**Files:**
- Create: `Sources/ShellX/Remote/Link/ShellXLinkFramePacing.swift`, `Sources/ShellX/Remote/Link/ShellXLinkTerminalView.swift`
- Modify: `cmuxTests/ShellXLinkTerminalTestSupport.swift`
- Test: create `cmuxTests/ShellXLinkFramePacingTests.swift`, `cmuxTests/ShellXLinkTerminalViewFrameTests.swift`

**Interfaces:**
- Consumes: Task 1 `MobileTerminalFrameSink` and `MobileTerminalFrameSinkRegistry`, Task 2 `ShellXLinkGridConverter`, `MobileTerminalFramePacer`, `MobileTerminalByteTee.shared.currentSequence(surfaceID:)` and `currentRenderCaptureIdentity(surfaceID:)`, `TerminalSurface.mobileRenderGridFrame(…)` and `runtimeSurfaceGeneration`, `MobileTerminalRenderGridFrame.renderGridEmission(comparedTo:fullScrollbackTarget:allowScrollbackRequest:)` and `emissionState`, 2A's `TerminalView`, `TerminalViewEvent` and `ShellXLink.terminalHistoryRowBudget`.
- Produces:

```swift
/// When a Link view captures its next delta: the pull-based hand-off between the pump asking for a frame and cmux's
/// frame pacer (90 ms floor, an input's echo never held).
struct ShellXLinkFramePacing {
    enum Step: Equatable { case capture; case hold(until: ContinuousClock.Instant) }
    init()
    /// A change is waiting and the pump wants a frame.
    mutating func changeArrived(now: ContinuousClock.Instant, inputSequence: UInt64?) -> Step
    /// The held time passed: capture now (true), or nothing was held back (false).
    mutating func holdEnded(now: ContinuousClock.Instant) -> Bool
    /// A snapshot (outside the pacer) went out now.
    mutating func noteSnapshot(now: ContinuousClock.Instant, inputSequence: UInt64?)
}

/// One phone's view of one Mac terminal (PROTOCOL.md section 11): captures the terminal's render grid on demand, diffs it
/// against what the phone last got, and applies the phone's input through the Mac's own input paths.
@MainActor
final class ShellXLinkTerminalView: TerminalView, MobileTerminalFrameSink {
    /// What the view does with its terminal; the live one (Task 6) resolves the surface id on every call.
    struct Terminal {
        var surface: @MainActor () -> TerminalSurface?                  // nil once the terminal is gone
        var type: @MainActor (_ text: String) -> Void                     // ControlTerminalSocketTarget.sendInputResult
        var press: @MainActor (_ keyName: String) -> Bool                 // sendNamedKeyResult(…).accepted
        var paste: @MainActor (_ text: String) -> Void                    // sendTextResult (Ghostty's paste path)
        var scroll: @MainActor (_ lines: Int, _ column: Int, _ row: Int) -> Void   // mobileScroll at that cell
    }
    /// The phone's part in the terminal's shared sizing (Task 3 behind the live one).
    struct Sizing {
        var attach: @MainActor (_ cols: Int, _ rows: Int) -> (columns: Int, rows: Int)?
        var resize: @MainActor (_ cols: Int, _ rows: Int) -> Void
        var input: @MainActor (_ apply: () -> Void) -> Void
        var detach: @MainActor () -> Void
    }
    static let firstSnapshotFence: Duration = .milliseconds(500)
    let surfaceID: UUID
    init(surfaceID: UUID, terminal: Terminal, sizing: Sizing, frameSinks: any MobileTerminalFrameSinkRegistry,
         isBlocked: @escaping @MainActor () -> Bool, notificationCenter: NotificationCenter = .default,
         onClose: @escaping @MainActor (ShellXLinkTerminalView) -> Void = { _ in })
    /// Joins the sizing (keeps attach's answer for the first-snapshot fence), registers as a frame sink, and watches
    /// `ManagedDevicePolicy.didChangeNotification` on `notificationCenter`.
    func open(cols: Int, rows: Int)
    /// Ends the view without the phone asking: `nextFrame()` returns `.ended(reason)` from now on (first reason wins).
    func end(_ reason: TerminalViewEndReason)
    var frameSinkSurfaceID: UUID { get }          // surfaceID
    func terminalSurfaceMayHaveChanged()
    func nextFrame() async -> TerminalViewEvent
    func requestSnapshot() async
    func input(_ units: [TerminalInputUnit]) async            // Task 4: does nothing yet; Task 5 implements it
    func resize(cols: Int, rows: Int) async                   // Task 4: does nothing yet; Task 5 implements it
    func close() async
}
```

The pacing hand-off body, which the tests below pin:

```swift
mutating func changeArrived(now: ContinuousClock.Instant, inputSequence: UInt64?) -> Step {
    switch pacer.updateArrived(now: now, acceptedInputSequence: inputSequence) {
    case .emit: heldUntil = nil; return .capture
    case .coalesce: return .hold(until: heldUntil ?? now)
    case .coalesceAndSchedule(let deadline): heldUntil = deadline; return .hold(until: deadline)
    }
}
mutating func holdEnded(now: ContinuousClock.Instant) -> Bool { heldUntil = nil; return pacer.flushFired(now: now) }
mutating func noteSnapshot(now: ContinuousClock.Instant, inputSequence: UInt64?) {
    heldUntil = nil; pacer.noteUnpacedEmit(now: now, acceptedInputSequence: inputSequence)
}
```

View state: `needsSnapshot` (true at start), `baseline: MobileTerminalRenderGridEmissionState?`, `generation: UInt64?` (`runtimeSurfaceGeneration` at the last capture), `converter`, `alternate: Bool` and `lastCursor: TerminalCursor` (from the last frame; `false` and `(0, 0)` before any), `inputSequence: UInt64?` (Task 5 advances it), `expectedGrid`, `fenceUntil` and `fencePassed`, `heldUntil`, `pacing`, `endReason`, `closed`, `pendingChange`, one `waiter`, `captureRevision`.

**The wait** (`waitForWake(until deadline:) async -> Wake`, with `Wake` one of `.changed`, `.snapshotRequested`, `.deadline` and `.ended`):
- It returns `.ended` at once when the view is ended, closed or its task is cancelled. It returns `.changed` at once, clearing it, when `pendingChange` is set.
- Otherwise it parks one `CheckedContinuation` tagged with a fresh wait id. When `deadline` is set, it also starts a `Task.sleep(until: deadline, clock: .continuous)` task that resumes `.deadline`.
- `terminalSurfaceMayHaveChanged()` resumes `.changed`, or sets `pendingChange` when nothing waits. `requestSnapshot()` sets `needsSnapshot` and resumes `.snapshotRequested`. `end(_:)` and `close()` resume `.ended`.
- A cancellation handler hops to the main actor and resumes `.ended` only for the wait id it captured, so a late cancel never resumes a newer wait.
- Resuming cancels the deadline task and clears the waiter. Each continuation resumes exactly once.

**`nextFrame()`** (the pull-based hand-off):

```text
loop:
  if closed or Task.isCancelled: return .ended(.failed)        // never sent: the pump is already stopping
  if let r = endReason: return .ended(r)
  if isBlocked(): end(.refused); continue
  if needsSnapshot:
      switch captureSnapshot(now): .frame(f) → return .frame(f) | .gone → end(.gone); continue | .notYet → (wait)
  switch await waitForWake(until: min(heldUntil, fenceUntil)):
      .ended, .snapshotRequested: continue
      .deadline: if fenceUntil passed { fenceUntil = nil; fencePassed = true; continue }
                 guard pacing.holdEnded(now) else { continue }
      .changed:  if needsSnapshot { continue }
                 switch pacing.changeArrived(now, inputSequence) { .capture: heldUntil = nil | .hold(t): heldUntil = t; continue }
  switch captureUpdate(): .frame(f) → return .frame(f) | .gone → end(.gone) | .unchanged, .notYet → continue

capture(history n) = surface.mobileRenderGridFrame(stateSeq: tee.currentSequence(surfaceID:) ?? 0,
    renderEpoch: tee.currentRenderCaptureIdentity(surfaceID:).epoch, renderRevision: ++captureRevision,
    full: true, scrollbackLines: n, includeTheme: true, anchor: .screen)?.frame

captureSnapshot(now):  surface = terminal.surface() else .gone;  grid = capture(history: terminalHistoryRowBudget) else .notYet
    if !fencePassed, let expected = expectedGrid, (grid.columns, grid.rows) != expected:
        fenceUntil = fenceUntil ?? now + firstSnapshotFence;  if now < fenceUntil { return .notYet }
    fencePassed = true; fenceUntil = nil; expectedGrid = nil
    baseline = grid.emissionState; generation = surface.runtimeSurfaceGeneration; needsSnapshot = false
    converter = ShellXLinkGridConverter(theme: grid.terminalTheme ?? TerminalTheme.currentMacTerminalThemeSnapshot())
    remember alternate and cursor; pacing.noteSnapshot(now, inputSequence); return .frame(converter.snapshot(grid))

captureUpdate():  surface = terminal.surface() else .gone
    if surface.runtimeSurfaceGeneration != generation { needsSnapshot = true; return .unchanged }
    grid = capture(history: 0) else .notYet
    emission = try grid.renderGridEmission(comparedTo: baseline, fullScrollbackTarget: terminalHistoryRowBudget, allowScrollbackRequest: true)
    if .needsScrollback(rows): deeper = capture(history: rows) else .notYet; emission = deeper.renderGridEmission(…, allowScrollbackRequest: false)
    .none → .unchanged
    .emit(frame, state): baseline = state; remember alternate and cursor
        frame.full ? (converter = new converter of frame's theme; .frame(converter.snapshot(frame))) : .frame(converter.delta(frame))
    a thrown MobileTerminalRenderGridError: log its case name, needsSnapshot = true, .unchanged
```

**`close()`:** runs once. It sets `closed`, resumes `.ended`, calls `frameSinks.removeFrameSink(self)`, removes the policy observer, calls `sizing.detach()` and then `onClose(self)`.

Test support additions to `ShellXLinkTerminalTestSupport.swift`:
- `RecordingFrameSinkRegistry` (`sinks`, `notifyAll()`).
- `RecordingSizing`, with `enum Call: Equatable { case attach(cols: Int, rows: Int), resize(cols: Int, rows: Int), input, detach }`, `calls`, `var expectedGrid: (columns: Int, rows: Int)?` (attach's answer), `isInsideInput`, and `var sizing: ShellXLinkTerminalView.Sizing`.
- `TestPolicy` (`blocked`, `center: NotificationCenter`, `change(blocked:)`, which posts `ManagedDevicePolicy.didChangeNotification`).
- `extension ScrollbackTestTerminal { var linkTerminal: ShellXLinkTerminalView.Terminal }`, with closures over `surface`: `sendInputResult`, `sendNamedKey(_:).accepted`, `sendTextResult` and `mobileScroll(deltaLines:col:row:)`.
- `extension ShellXLinkTerminalView`: `func nextEvent(within: Duration = .seconds(5)) async throws -> TerminalViewEvent` (races `nextFrame()` against a sleep and throws on timeout) and `func returnsNothing(for: Duration) async -> Bool` (runs `nextFrame()` in a task, sleeps, records whether it returned, then cancels it and awaits it).
- `extension TerminalScreen { mutating func apply(_ event: TerminalViewEvent) }` (applies `.frame`).
- `extension ScrollbackTestTerminal { func openLinkView(cols: Int, rows: Int, sizing: RecordingSizing = .init(), registry: RecordingFrameSinkRegistry = .init(), policy: TestPolicy = .init()) -> ShellXLinkTerminalView }` builds the view over `linkTerminal` with `isBlocked: { policy.blocked }` and `notificationCenter: policy.center`, then calls `open(cols:rows:)`. Do not add free functions.

- [ ] **Step 1: Write the failing tests.** `ShellXLinkFramePacingTests` (pure, with `t0 = ContinuousClock.now` and `floor = MobileTerminalFramePacer.floorPeriod`):

```swift
@Test func aChangeRightAfterASnapshotWaitsForTheFloor() {
    var pacing = ShellXLinkFramePacing(); pacing.noteSnapshot(now: t0, inputSequence: nil)
    #expect(pacing.changeArrived(now: t0 + .milliseconds(10), inputSequence: nil) == .hold(until: t0 + floor))
    #expect(pacing.changeArrived(now: t0 + .milliseconds(20), inputSequence: nil) == .hold(until: t0 + floor))
    #expect(pacing.holdEnded(now: t0 + floor))
}
@Test func aChangeAfterTheFloorIsCapturedAtOnce()    // noteSnapshot(t0); changeArrived(t0 + 100 ms) == .capture
@Test func theEchoOfAnInputIsNeverHeld()            // noteSnapshot(t0, nil); changeArrived(t0 + 10 ms, inputSequence: 1) == .capture;
                                                    // then changeArrived(t0 + 20 ms, 1) == .hold(until: t0 + 10 ms + floor)
@Test func aHoldWithNothingHeldCapturesNothing()     // changeArrived(t0 + 100 ms) == .capture; holdEnded(t0 + 200 ms) == false
```

`ShellXLinkTerminalViewFrameTests` (`@MainActor @Suite(.serialized, .timeLimit(.minutes(2)))`). Each test runs inside `AppContextSerialGate.withExclusiveAppContext`, with `let terminal = try ScrollbackTestTerminal(); defer { terminal.close() }; try await terminal.launch(); try await terminal.setGrid(columns: 20, rows: 5)`.

```swift
@Test func theFirstFrameIsASnapshotWithTheHistory() async throws {
    try terminal.output("\u{1b}c" + (1...30).map { "line \($0)\r\n" }.joined()); try await terminal.waitForScreen(containing: "line 30")
    let sizing = RecordingSizing(); let view = terminal.openLinkView(cols: 20, rows: 5, sizing: sizing)
    guard case let .frame(first) = try await view.nextEvent() else { return Issue.record("no frame") }
    #expect(first.head.kind == .snapshot && first.head.history >= 25 && sizing.calls == [.attach(cols: 20, rows: 5)])
    var screen = TerminalScreen(); screen.apply(.frame(first))
    #expect((screen.historyText() + screen.screenText()).filter { !$0.isEmpty } == (1...30).map { "line \($0)" })
}
@Test func newOutputComesAsADelta()                       // after the snapshot: output "hello"; view.terminalSurfaceMayHaveChanged()
                                                          // → .delta; applied → screen contains "hello"
@Test func changesWhileThePumpIsBusyMergeIntoOneDelta()   // snapshot; output "a\r\n", "b\r\n", "c", each followed by a change
                                                          // and no nextFrame; one nextFrame → a delta showing a, b, c;
                                                          // then returnsNothing(for: 300 ms)
@Test func anUnchangedTerminalSendsNothing()              // snapshot; a change with no output → returnsNothing(for: 300 ms)
@Test func aResyncWakesAWaitingViewWithASnapshot()        // snapshot; pending = Task { await view.nextFrame() }; await
                                                          // view.requestSnapshot() → the task returns a .snapshot within 2 s
@Test func aNewSizeComesAsASnapshot()                     // snapshot at 20×5; setGrid(30, 6); change → .snapshot with cols 30, rows 6
@Test func theAlternateScreenComesAsASnapshotWithoutHistory()   // output "\u{1b}[?1049hvim"; change → .snapshot, alt, history 0
@Test func aPaletteChangeComesAsASnapshot()               // output "\u{1b}]4;1;rgb:12/34/56\u{1b}\\"; change → .snapshot,
                                                          // head.palette?.colors[1] == "#123456"
@Test func aBurstKeepsTheHistoryContiguous()              // setGrid(20, 3); output "\u{1b}ca1\r\na2\r\na3"; snapshot; output
                                                          // "\r\nb1\r\n…\r\nb10" (no newline after b10); change → one delta with
                                                          // scroll > 3; applied → historyText() == ["a1","a2","a3","b1",…,"b7"],
                                                          // screenText() == ["b8","b9","b10"]
@Test func floodEndsOnTheLastScreen() async throws {      // Review Focus 1
    // 20 chunks for lines "L0001"..."L2000". Each chunk is "\r\n" followed by its 100 lines joined with "\r\n", with no
    // newline after its last line, so no row changes after it scrolls (cmux's burst model, Spec note 11). After each chunk,
    // waitForScreen(its last line) and a change. Call nextEvent() only after every 5th chunk, then drain until
    // returnsNothing(for: 300 ms). The applied frames equal a fresh
    // ShellXLinkGridConverter(theme:).snapshot(terminal.capture(history: 4000)) applied to a new TerminalScreen:
    // both screenText() and historyText(). #expect(frames.count <= 10)
}
@Test func aTerminalWithoutALiveSurfaceShowsOnceItStarts() async throws {   // Review Focus 5
    // A TerminalSurface(tabId: UUID(), context: GHOSTTY_SURFACE_CONTEXT_SPLIT, configTemplate: nil, ioMode: .manualMirror,
    // manualInputHandler: { _ in }) with no window: open a view on it; returnsNothing(for: 300 ms). Then host it in an
    // NSWindow as CloudRestoreReplayFixture.init does (cmuxTests/CloudRestoreReplayFixture.swift:35-46), wait for
    // surface.hasLiveSurface, output "ready" through ghostty_surface_process_output, and signal a change. The next event
    // is a .snapshot whose screen contains "ready".
}
@Test func theFirstSnapshotWaitsForTheDecidedSize()       // sizing.expectedGrid = (30, 6) before open; pending = Task {
                                                          // await view.nextFrame() }; await Task.yield(); setGrid(30, 6) +
                                                          // change → pending returns a .snapshot of 30×6 (without the fence
                                                          // it would return the 20×5 one at once)
@Test func theFirstSnapshotStopsWaitingAfterTheFence()    // expectedGrid (30, 6) never reached: a .snapshot 20×5 within 1.5 s
@Test func closeEndsAWaitingViewAndLeavesOnce()           // pending nextFrame; await view.close() → the task returns;
                                                          // sizing.calls.last == .detach; registry.sinks empty; a second close
                                                          // adds nothing
@Test func cancellingAWaitReturnsPromptly()               // snapshot; t = Task { await view.nextFrame() }; t.cancel() → returns
                                                          // within 1 s; a later output + change still gives a delta
@Test func aGoneTerminalEnds()                            // view.end(.gone) → .ended(.gone); and a Terminal whose surface()
                                                          // returns nil → first event .ended(.gone)
@Test func theViewLeavesIrohStateAlone() async throws {
    // observer.adoptReplayBaseline(seeded, surfaceID: terminal.surface.id), as MobileHostTerminalThemeTests:196-208 does.
    // Run snapshot + delta through a view, then: observer.terminalThemesBySurfaceID[id] == seeded.terminalTheme and
    // observer.debugRenderGridStateSurfaceCountForTesting is unchanged. End with observer.stop(); observer.start().
}
```

- [ ] **Step 2: Wire and run:** `./scripts/sync-test-wiring`, then `toknix run scripts/shellx/test-app.sh ShellXLinkFramePacingTests ShellXLinkTerminalViewFrameTests`. Expected: FAIL with `error: cannot find 'ShellXLinkFramePacing' in scope`.
- [ ] **Step 3: Commit red:** `git add cmuxTests/ShellXLinkTerminalTestSupport.swift cmuxTests/ShellXLinkFramePacingTests.swift cmuxTests/ShellXLinkTerminalViewFrameTests.swift cmux.xcodeproj/project.pbxproj && git commit -m "test(shellx): Link terminal view frames and pacing (failing)"`
- [ ] **Step 4: Implement** both files, then run `./scripts/wire-app-sources.py Sources/ShellX/Remote/Link/ShellXLinkFramePacing.swift Sources/ShellX/Remote/Link/ShellXLinkTerminalView.swift`.
- [ ] **Step 5: Run:** `toknix run scripts/shellx/test-app.sh ShellXLinkFramePacingTests ShellXLinkTerminalViewFrameTests MobileTerminalFrameSinkTests MobileHostTerminalThemeTests`. Expected: `** TEST SUCCEEDED **`.
- [ ] **Step 6: Commit:** `git add Sources/ShellX/Remote/Link/ShellXLinkFramePacing.swift Sources/ShellX/Remote/Link/ShellXLinkTerminalView.swift cmux.xcodeproj/project.pbxproj && git commit -m "feat(shellx): Link terminal view snapshots, deltas and pull-based pacing"`

---

### Task 5: The view's input, resize and device management

**Files:**
- Create: `Sources/ShellX/Remote/Link/ShellXLinkKeyChord.swift`
- Modify: `Sources/ShellX/Remote/Link/ShellXLinkTerminalView.swift` (`input`, `resize`, the policy observer's handler)
- Test: create `cmuxTests/ShellXLinkTerminalViewInputTests.swift`

**Interfaces:**
- Consumes: Task 4 view and support; 2A's `TerminalInputUnit`, `TerminalKey`, `TerminalModifier`; `TerminalSurface.pendingKeyEvent(for:)` naming (`Packages/macOS/CmuxTerminal/Sources/CmuxTerminal/Surface/TerminalSurface+Input.swift:854-942`).
- Produces:

```swift
/// The Mac's named-key spelling (`TerminalSurface.sendNamedKey`) of a phone's key and modifiers: ctrl, alt and shift
/// in that order, then the key, joined with "+" (`ctrl+c`, `shift+tab`, `page_up`). Nil for a key or modifier the
/// Mac does not know (the unit is skipped).
struct ShellXLinkKeyChord: Equatable {
    let macKeyName: String
    init?(key: TerminalKey, mods: [TerminalModifier])
}
```

Key names: `enter`, `tab`, `backspace`, `escape`, `delete`, `space`, `up`, `down`, `left`, `right`, `home`, `end`, `pageUp`→`page_up`, `pageDown`→`page_down`; `.letter(c)` maps to `String(c)`, and `.other` has no chord. The modifiers `.ctrl`, `.alt` and `.shift` map to `ctrl`, `alt` and `shift`, deduplicated, and `.other` has no chord.

`input(_ units:)`:
1. Ignore it when ended or closed. When `isBlocked()`, call `end(.refused)` and return; nothing is applied.
2. Otherwise run, inside `sizing.input { … }`, each unit in order:
   - `.text(s)` calls `terminal.type(s)`.
   - `.key(k, m)` calls `terminal.press(chord.macKeyName)`, or is skipped when there is no chord or `press` returns false.
   - `.paste(s)` calls `terminal.paste(s)`.
   - `.scroll(lines:)` calls `terminal.scroll(lines, lastCursor.x, lastCursor.y)`, only when the last frame was the alternate screen. The sign passes through: positive means toward older content, like Ghostty's positive wheel delta.
   - `.other` is skipped.
3. When any unit was applied, advance `inputSequence` (wrapping add, starting from 1). The next change is then the echo, which the pacer never holds.

`resize(cols:rows:)`: ignore it when ended or closed; otherwise call `sizing.resize(cols, rows)`. The policy observer: `if isBlocked() { end(.refused) }`.

- [ ] **Step 1: Write the failing tests** (same app-context and terminal setup as Task 4). Start each test with `try terminal.output("\u{1b}c")` and `#expect(try await terminal.inputBytesBeforeBarrier().isEmpty)`. Then build the view with `let view = terminal.openLinkView(cols: 20, rows: 5, sizing: sizing, policy: policy)` and take its first snapshot with `_ = try await view.nextEvent()`:

```swift
@Test(arguments: [(TerminalKey.enter, [TerminalModifier](), "enter"), (.letter("c"), [.ctrl], "ctrl+c"), (.tab, [.shift], "shift+tab"),
                  (.left, [.shift, .alt, .ctrl], "ctrl+alt+shift+left"), (.pageUp, [], "page_up"), (.space, [.ctrl], "ctrl+space")])
func keyChordsUseTheMacNames(key: TerminalKey, mods: [TerminalModifier], name: String) {
    #expect(ShellXLinkKeyChord(key: key, mods: mods)?.macKeyName == name)
}
@Test func unknownKeysOrModifiersHaveNoChord()     // .other("f13") → nil; .letter("c") with [.other("hyper")] → nil
@Test func inputReachesTheTerminalInOrder() async throws {
    await view.input([.text("ls"), .key(.enter, mods: []), .key(.letter("c"), mods: [.ctrl])])
    #expect(try await terminal.inputBytesBeforeBarrier() == Data("ls\r\u{03}".utf8))
}
@Test func pasteGoesThroughTheMacsPastePath()      // output "\u{1b}[?2004h"; input [.paste("a\nb")] → written bytes contain
                                                   // "\u{1b}[200~", "a", "b" and "\u{1b}[201~"
@Test func unknownUnitsAreSkippedAndTheRestApplied()   // [.key(.other("f13")), .key(.letter("c"), mods: [.other("hyper")]),
                                                       //  .other(kind: "gesture"), .text("ok")] → bytes == "ok"
@Test func theWheelTurnsOnlyOnTheAlternateScreen() async throws {
    await view.input([.scroll(lines: 3)])                           // main screen: the phone scrolls its own history
    #expect(try await terminal.inputBytesBeforeBarrier().isEmpty)
    try terminal.output("\u{1b}[?1049h\u{1b}[?1007h"); view.terminalSurfaceMayHaveChanged()
    guard case let .frame(alt) = try await view.nextEvent(), alt.head.alt else { return Issue.record("no alternate snapshot") }
    await view.input([.scroll(lines: 3)])
    let up = String(decoding: try await terminal.inputBytesBeforeBarrier(), as: UTF8.self)
    #expect(up.contains("\u{1b}[A") || up.contains("\u{1b}OA"))          // positive = toward older content = up
    await view.input([.scroll(lines: -2)])
    let down = String(decoding: try await terminal.inputBytesBeforeBarrier(), as: UTF8.self)
    #expect(down.contains("\u{1b}[B") || down.contains("\u{1b}OB"))
}
@Test func inputIsThePhonesActivity()       // a Terminal whose `type` records sizing.isInsideInput; input [.text("x")] →
                                            // recorded true, sizing.calls contains .input
@Test func resizeReportsThePhonesSize()     // await view.resize(cols: 80, rows: 24) → sizing.calls.last == .resize(cols: 80, rows: 24)
@Test func deviceManagementEndsTheViewAsRefused() async throws {
    // snapshot taken; pending = Task { await view.nextFrame() }; policy.change(blocked: true) → pending returns .ended(.refused);
    // await view.input([.text("x")]) → inputBytesBeforeBarrier() is empty
}
@Test func inputWhileBlockedIsNotApplied()  // policy.blocked = true with no notification; input [.text("x")] → nothing written;
                                            // nextEvent() == .ended(.refused)
@Test func inputAfterCloseIsNotApplied()    // await view.close(); input [.text("x")] → nothing written
```

- [ ] **Step 2: Wire and run:** `./scripts/sync-test-wiring`, then `toknix run scripts/shellx/test-app.sh ShellXLinkTerminalViewInputTests`. Expected: FAIL. The build stops at `error: cannot find 'ShellXLinkKeyChord' in scope`. Once the chord type exists, the other tests fail their assertions, because `input` and `resize` still do nothing.
- [ ] **Step 3: Commit red:** `git add cmuxTests/ShellXLinkTerminalViewInputTests.swift cmux.xcodeproj/project.pbxproj && git commit -m "test(shellx): Link terminal view input, resize and device management (failing)"`
- [ ] **Step 4: Implement**, then run `./scripts/wire-app-sources.py Sources/ShellX/Remote/Link/ShellXLinkKeyChord.swift`.
- [ ] **Step 5: Run:** `toknix run scripts/shellx/test-app.sh ShellXLinkTerminalViewInputTests ShellXLinkTerminalViewFrameTests`. Expected: `** TEST SUCCEEDED **`.
- [ ] **Step 6: Commit:** `git add Sources/ShellX/Remote/Link/ShellXLinkKeyChord.swift Sources/ShellX/Remote/Link/ShellXLinkTerminalView.swift cmux.xcodeproj/project.pbxproj && git commit -m "feat(shellx): Link terminal view input through the Mac's input paths"`

---

### Task 6: The terminal view source

**Files:**
- Create: `Sources/ShellX/Remote/Link/ShellXLinkTerminalViewSource.swift`, `Sources/ShellX/Remote/Link/ShellXLinkTerminalViewSource+Live.swift`, `Sources/ShellX/Remote/Link/ShellXLinkTerminalView+Live.swift`
- Modify: `Sources/ShellX/Remote/Link/ShellXLinkWorkspaceSource.swift:200-206`. Rename the private `listedWorkspace(holding:)` to the internal `listedWorkspaceID(holding:)` and update its two callers (lines 184 and 230).
- Test: create `cmuxTests/ShellXLinkTerminalViewSourceTests.swift`; modify `cmuxTests/ShellXLinkTerminalTestSupport.swift` (add `FakeLinkMac`, which Task 8 reuses)

**Interfaces:**
- Consumes: Tasks 3–5; `TerminalController.mobileResolveWorkspaceAndSurface(params:requireTerminal:)` (it materializes a never-shown terminal headlessly, `Sources/TerminalController.swift:17207-17262`); `Workspace.controlSocketTerminalInputTarget(for:)`; `ControlTerminalSocketTarget.resumeAgentHibernationForRemoteAttach()`, `sendInputResult`, `sendNamedKeyResult` and `sendTextResult`; `TerminalController.terminalSocketTarget(surfaceID:)`; `GhosttyApp.terminalSurfaceRegistry.terminalSurface(id:)`; `ShellXLinkWorkspaceSource.workspaceChanges()`.
- Produces:

```swift
/// ShellX: the Mac's terminals as phones view them (`terminal_view`, PROTOCOL.md 11): only terminals of local workspaces
/// the phone's list holds, one Link view per phone, ended `gone` when the list loses the terminal. Never logs ids or titles.
@MainActor
final class ShellXLinkTerminalViewSource: TerminalViewSource {
    struct Mac {
        /// The listed workspace whose terminals include `terminal`; nil when none lists it.
        var listedWorkspace: @MainActor (_ terminal: UUID) -> UUID?
        /// Makes a listed terminal ready for a viewer (a never-shown terminal starts, a hibernated agent wakes) and
        /// returns the surface to view; nil when there is none.
        var prepare: @MainActor (_ workspace: UUID, _ terminal: UUID) -> UUID?
        var terminal: @MainActor (_ surface: UUID) -> ShellXLinkTerminalView.Terminal
        var sizing: @MainActor (_ surface: UUID, _ clientID: String) -> ShellXLinkTerminalView.Sizing
        var isBlocked: @MainActor () -> Bool
        /// Calls `onChange` after each change of the listed workspaces until the returned function runs.
        var listChanges: @MainActor (_ onChange: @escaping @MainActor () -> Void) -> @MainActor () -> Void
    }
    init(mac: Mac, frameSinks: any MobileTerminalFrameSinkRegistry, notificationCenter: NotificationCenter = .default)
    func openView(terminalId: String, cols: Int, rows: Int) async -> TerminalViewOpenResult
    var openViewCount: Int { get }
}
extension ShellXLinkTerminalViewSource.Mac { static func live(workspaces: ShellXLinkWorkspaceSource) -> Self }   // +Live file
extension ShellXLinkTerminalView.Terminal { static func live(surfaceID: UUID) -> Self }                          // +Live file
extension ShellXLinkTerminalView.Sizing { static func live(surfaceID: UUID, clientID: String) -> Self }          // +Live file
// ShellXLinkWorkspaceSource
func listedWorkspaceID(holding terminal: UUID) -> UUID?
```

`openView` runs these checks in order:
1. `isBlocked()` gives `.notOpened(.refused)`.
2. A non-UUID id, or `listedWorkspace` returning nil, gives `.notOpened(.notFound)`, and `prepare` is never called.
3. `prepare` returning nil gives `.notOpened(.failed)`.
4. Otherwise it makes a client id `TerminalController.shellXLinkSizingClientIDPrefix + UUID().uuidString.lowercased()`, builds the view over `mac.terminal(surface)` and `mac.sizing(surface, clientID)`, calls `open(cols:rows:)`, keeps it with its listed terminal id, and returns `.opened(view)`.

While at least one view is open, the source holds one `listChanges` subscription. On each change, it ends with `.gone` every view whose terminal `listedWorkspace` no longer finds. `onClose` forgets the view, and the last close drops the subscription.

Live closures:
- `listedWorkspace` is `workspaces.listedWorkspaceID(holding:)`.
- `prepare` resolves `["workspace_id": w, "surface_id": t]` through `mobileResolveWorkspaceAndSurface(…, requireTerminal: true)`, calls `resumeAgentHibernationForRemoteAttach()` on `resolved.workspace.controlSocketTerminalInputTarget(for:)`, and returns `resolved.surfaceId`. This is the iroh replay's own preparation.
- `isBlocked` is `MobileRemoteControlPolicy.isDisabled`.
- `listChanges` runs a main-actor task over `for await _ in workspaces.workspaceChanges()`; the stop function cancels it.
- `Terminal.live`:
  - `surface` reads the registry by id;
  - `type`, `press` and `paste` resolve `terminalSocketTarget(surfaceID:)` on every call;
  - `scroll` calls `target.surface.mobileScroll(deltaLines: Double(lines), col: column, row: row)` and then `MobileTerminalRenderObserver.shared.noteTerminalBytes(surfaceID:)`, the two calls of `v2MobileTerminalScroll` (lines 16513-16516).
- `Sizing.live` forwards to Task 3's four methods with `clientID`.

- [ ] **Step 1: Write the failing tests** (`@MainActor @Suite(.serialized, .timeLimit(.minutes(1)))`). `FakeLinkMac` (`@MainActor final class` in the support file) holds `listed: [UUID: UUID]` (terminal → workspace), `surfaces: [UUID: UUID]` (prepare's answer), `blocked`, `prepares`, `attaches: [(clientID: String, cols: Int, rows: Int)]`, `listeners` and `fireListChange()`. Its `mac` value uses `ScrollbackTestTerminal.linkTerminal` and a `RecordingSizing` per client.

```swift
@Test func aBlockedMacRefusesTheOpen()                  // .notOpened(.refused); prepares empty
@Test func anIdThatIsNotListedIsNotFound()              // "ws-a" and an unlisted UUID → .notOpened(.notFound); prepares empty
@Test func aListedTerminalThatCannotBePreparedFails()   // listed, surfaces empty → .notOpened(.failed)
@Test func aListedTerminalOpensAndJoinsTheSizing()      // .opened; prepares == [(W, T)]; attaches == [(prefix…, 46, 30)];
                                                        // openViewCount 1; the view is a registered frame sink
@Test func eachOpenIsItsOwnParticipant()                // two opens of T → two different client ids, both with the prefix
@Test func aViewEndsGoneWhenItsTerminalLeavesTheList() async throws {   // Review Focus 3
    // open T over a launched ScrollbackTestTerminal; first event is a .snapshot; listed[T] = nil; fireListChange()
    // → next event == .ended(.gone)
}
@Test func theListIsWatchedOnlyWhileAViewIsOpen()       // listeners 0 → open → 1 → second open → 1 → close both → 0
@Test func liveSourceOpensAListedTerminalAndJoinsItsSizing() async throws {   // Review Focus 5, live closures
    // Inside AppContextSerialGate.withExclusiveAppContext, one real main window: AppDelegate(), app.registerMainWindow(window,
    // windowId:tabManager:sidebarState:sidebarSelectionState:fileExplorerState:), and
    // TerminalController.shared.setActiveTabManager(manager), as ShellXLinkWorkspaceSourceTests.twoWindowsListedInOrder
    // does (cmuxTests/ShellXLinkWorkspaceSourceTests.swift:147-174). Build the source with
    // .live(workspaces: ShellXLinkWorkspaceSource()) and a RecordingFrameSinkRegistry. Opening the focused panel's
    // terminal → .opened, and TerminalController.shared.terminalSharing.snapshot(for:)?.state has one participant whose id
    // starts with "mobile:shellx-link-". Opening UUID() → .notOpened(.notFound). await view.close() → that participant
    // is gone. Defer debugResetMobileViewportReportsForTesting() and the window teardown.
}
```

- [ ] **Step 2: Wire and run:** `./scripts/sync-test-wiring`, then `toknix run scripts/shellx/test-app.sh ShellXLinkTerminalViewSourceTests`. Expected: FAIL with `error: cannot find 'ShellXLinkTerminalViewSource' in scope`.
- [ ] **Step 3: Commit red:** `git add cmuxTests/ShellXLinkTerminalViewSourceTests.swift cmuxTests/ShellXLinkTerminalTestSupport.swift cmux.xcodeproj/project.pbxproj && git commit -m "test(shellx): Link terminal view source (failing)"`
- [ ] **Step 4: Implement** the source, the three live closures, and the rename. Wire the new files with `./scripts/wire-app-sources.py <the three new files>`.
- [ ] **Step 5: Run:** `toknix run scripts/shellx/test-app.sh ShellXLinkTerminalViewSourceTests ShellXLinkWorkspaceSourceTests`. Expected: `** TEST SUCCEEDED **`.
- [ ] **Step 6: Commit:** `git add Sources/ShellX/Remote/Link/ShellXLinkTerminalViewSource.swift Sources/ShellX/Remote/Link/ShellXLinkTerminalViewSource+Live.swift Sources/ShellX/Remote/Link/ShellXLinkTerminalView+Live.swift Sources/ShellX/Remote/Link/ShellXLinkWorkspaceSource.swift cmux.xcodeproj/project.pbxproj && git commit -m "feat(shellx): Link terminal view source over the listed terminals"`

---

### Task 7: `terminal.create` keeps the Mac's selection

**Files:**
- Modify: `Sources/TerminalController.swift:16174-16204` (`v2MobileTerminalCreate`)
- Modify: `Sources/ShellX/Remote/Link/ShellXLinkWorkspaceSource.swift`: the doc comment at 10-32, the conformance at 34, `Control` at 42-78, and a new `// MARK: - TerminalCreator` section after `TerminalControl`
- Test: `cmuxTests/ShellXLinkWorkspaceSourceTests.swift` (`FakeMac` at 880-940 gains `createTerminal`); create `cmuxTests/ShellXLinkTerminalCreateTests.swift`; `Packages/macOS/CmuxRemoteWorkspace/Tests/CmuxRemoteWorkspaceTests/RemoteCLIRelayPolicyTests.swift`

**Interfaces:**
- Consumes: 2A's `TerminalCreator`; `Workspace.newTerminalSurface(…preserveBonsplitSelectionWhenUnfocused:…)` (`Sources/Workspace.swift:9636`, restore at 9921-9928).
- Produces:

```swift
// TerminalController: the iroh and socket callers (lines 15653, TerminalController+ControlMobileHostContext.swift:57) keep the default
func v2MobileTerminalCreate(params: [String: Any], preserveSelection: Bool = false) -> V2CallResult
    // passes `preserveBonsplitSelectionWhenUnfocused: preserveSelection` right after `preserveFocusWhenUnfocused: false`

// ShellXLinkWorkspaceSource: …, TerminalControl, TerminalCreator
// Control
/// Opens a terminal tab in the workspace's focused pane without changing the Mac's selection (`terminal.create`).
var createTerminal: @MainActor @Sendable (_ workspaceId: UUID) -> V2CallResult
    // live: TerminalController.shared.v2MobileTerminalCreate(params: ["workspace_id": workspaceId.uuidString], preserveSelection: true)
func createTerminal(workspaceId: String) async -> (outcome: WorkspaceControlOutcome, terminalId: String?)
```

`createTerminal` returns, in order of its checks:
- `(.refused, nil)` when `control.isBlocked()`;
- `(.notFound, nil)` for a non-UUID id or a workspace the list does not hold (`isListed`); the Mac is asked nothing;
- otherwise `Self.outcome(of:action: "create-terminal")`. On `.ok` it calls `refresh()` and returns the payload's `created_terminal_id` (nil when absent); on any other outcome, `(outcome, nil)`.

- [ ] **Step 1: Write the failing tests.** In `ShellXLinkWorkspaceSourceTests`, `FakeMac` gains `var createTerminalResult: TerminalController.V2CallResult = .ok(["created_terminal_id": "T-NEW"] as [String: Any])` and `private(set) var terminalCreates: [UUID]`, and its `control` passes `createTerminal:`. The workspaces in these tests use UUID strings.

```swift
@Test func createTerminalOpensATabInAListedWorkspace()   // listed W → (.ok, "T-NEW"); terminalCreates == [W]
@Test func createTerminalOutsideTheListIsNotFound()      // "ws-a" and an unlisted UUID → (.notFound, nil); terminalCreates empty
@Test func createTerminalBlockedIsRefused()              // blocked → (.refused, nil); terminalCreates empty
@Test(arguments: [("not_found", WorkspaceControlOutcome.notFound), ("protected", .refused), ("invalid_state", .refused),
                  ("internal_error", .failed), ("unavailable", .failed)])
func createTerminalErrorMapsToOutcome(code: String, outcome: WorkspaceControlOutcome)   // .err(code:…) → (outcome, nil)
@Test func createTerminalOkWithoutAnIdIsOkWithoutId()    // .ok([:]) → (.ok, nil)
```

`ShellXLinkTerminalCreateTests` (`@MainActor @Suite(.serialized)`, with `withAppContext` copied from `LocalTerminalSizingHostLifecycleTests`):

```swift
@Test(arguments: [true, false])
func aNewTabKeepsTheMacsSelection(inTheSelectedWorkspace: Bool) async throws {
    // The target is manager.tabs.first, or a second workspace from manager.addWorkspaceIfActive(select: false,
    // autoWelcomeIfNeeded: false, autoRefreshMetadata: false) while the first stays selected. With
    // pane = target.bonsplitController.focusedPaneId, it gets tab A, newTerminalSurface(inPane: pane, focus: true), and
    // tab B, newTerminalSurface(inPane: pane, focus: false, preserveBonsplitSelectionWhenUnfocused: true). Record
    // selectedTab(inPane: pane)?.id, focusedPaneId, target.focusedPanelId and manager.selectedTabId.
    let result = TerminalController.shared.v2MobileTerminalCreate(params: ["workspace_id": target.id.uuidString], preserveSelection: true)
    guard case let .ok(payload) = result, let id = (payload as? [String: Any])?["created_terminal_id"] as? String,
          let created = UUID(uuidString: id) else { return Issue.record("no terminal created") }
    #expect(target.panels[created] != nil)
    // These four are unchanged now and again after two 50 ms main-queue turns: selected tab, focused pane,
    // focused panel, selected workspace.
}
```

`RemoteCLIRelayPolicyTests` gets a pin that passes at once: it pins the unchanged allowlist.

```swift
@Test("terminal paths a ShellX Link phone reaches stay off the relay", arguments: [
    "terminal.create", "mobile.terminal.create", "terminal.input", "mobile.terminal.input",
    "terminal.scroll", "mobile.terminal.scroll", "mobile.terminal.replay", "mobile.terminal.paste"])
func deniesLinkTerminalPathsThroughTheRelay(method: String) throws {
    let alias = (remote: UUID(), local: UUID())
    try withServer(workspaceAliases: [alias.remote: alias.local]) { port, unixServer in
        let exchange = try runPolicyRelayExchange(port: port, relayID: relayID, tokenHex: tokenHex,
            commandLine: #"{"id":"p9","method":"\#(method)","params":{"workspace_id":"\#(alias.remote.uuidString)"}}"#)
        expectDenial(exchange, unixServer, method)
    }
}
```

- [ ] **Step 2: Wire and run:** `./scripts/sync-test-wiring`, then `toknix run scripts/shellx/test-app.sh ShellXLinkWorkspaceSourceTests ShellXLinkTerminalCreateTests`. Expected: FAIL with `error: extra argument 'createTerminal' in call` (or `extra argument 'preserveSelection'`).
- [ ] **Step 3: Commit red:** `git add cmuxTests/ShellXLinkWorkspaceSourceTests.swift cmuxTests/ShellXLinkTerminalCreateTests.swift Packages/macOS/CmuxRemoteWorkspace/Tests/CmuxRemoteWorkspaceTests/RemoteCLIRelayPolicyTests.swift cmux.xcodeproj/project.pbxproj && git commit -m "test(shellx): terminal.create keeps the Mac's selection (failing)"`
- [ ] **Step 4: Implement** the parameter, the `Control` closure, the conformance and the doc comment bullet: "`terminal.create` opens a tab in a listed workspace's focused pane without changing the Mac's selection (`v2MobileTerminalCreate(params:preserveSelection: true)`)".
- [ ] **Step 5: Run:**
  - `toknix run scripts/shellx/test-app.sh ShellXLinkWorkspaceSourceTests ShellXLinkTerminalCreateTests ShellXLinkHostPolicyTests` → `** TEST SUCCEEDED **`
  - `toknix run swift test --package-path Packages/macOS/CmuxRemoteWorkspace --filter RemoteCLIRelayPolicyTests` → the run reports every test passed
- [ ] **Step 6: Commit:** `git add Sources/TerminalController.swift Sources/ShellX/Remote/Link/ShellXLinkWorkspaceSource.swift && git commit -m "feat(shellx): terminal.create for phones without changing the Mac's selection"`

---

### Task 8: Serve it from the Link host, end to end

**Files:**
- Modify: `Sources/ShellX/Remote/Link/ShellXLinkHostController.swift`. Replace the seven source properties (45-51) with one `sources`; the init at 82-105 keeps its parameters and adds two; `launch` at 138-155; `serve` at 251-320 (the `LinkHost(…)` at 295-299 becomes `makeLinkHost`); doc comments at 9-21 and 63-81.
- Modify: `Sources/ShellX/Remote/ShellXRemoteService+App.swift:53-71`
- Test: create `cmuxTests/ShellXLinkTerminalSessionTests.swift`

**Interfaces:**
- Consumes: Tasks 6–7; 2A's `LinkHost.init(…, terminalControl:, terminalViews:, terminalCreator:, hostVersion:, machineName:)`, `LinkClient` terminal methods, `TerminalViewPush`, `TerminalFrameAssembler`; `makeInMemoryCircuitPair()`, `NoiseStaticKey()`, `LinkClient.connect(_:key:hostKey:clientVersion:deviceName:)`, `LinkHost.disconnect(clientKey:)` (what `revoke` calls).
- Produces:

```swift
// ShellXLinkHostController
/// What the link host serves phones from: the agent Feed and every optional ShellX Link source.
struct Sources: Sendable {
    var feed: any AgentFeedSource
    var sessions: (any AgentSessionSource)?, chat: (any AgentChatSource)?
    var workspaces: (any WorkspaceSource)?, workspaceControl: (any WorkspaceControl)?
    var agentControl: (any AgentControl)?, terminalControl: (any TerminalControl)?
    var terminalViews: (any TerminalViewSource)?, terminalCreator: (any TerminalCreator)?
}
/// The `LinkHost` of one registration attempt over `sources` (the only place sources enter a host).
nonisolated static func makeLinkHost(key: NoiseStaticKey, trustedClients: @escaping @Sendable () -> Set<Data>,
                                     sources: Sources, hostVersion: String, machineName: String) -> LinkHost
// init gains `terminalViews: (any TerminalViewSource)? = nil, terminalCreator: (any TerminalCreator)? = nil` after `terminalControl:`
```

Composition (`forApp`): after `let workspaces = ShellXLinkWorkspaceSource()`, add `let terminalViews = ShellXLinkTerminalViewSource(mac: .live(workspaces: workspaces), frameSinks: MobileTerminalRenderObserver.shared)`, and pass `terminalViews: terminalViews, terminalCreator: workspaces` after `terminalControl: workspaces`.

- [ ] **Step 1: Write the failing tests** (`@MainActor @Suite("ShellX Link terminal sessions", .serialized, .timeLimit(.minutes(2)))`).
  - The rig: a launched `ScrollbackTestTerminal` (20×5) listed as terminal T in workspace W by Task 6's `FakeLinkMac`, a `RecordingFrameSinkRegistry`, a `TestPolicy`, an `actor FakeTerminalCreator: TerminalCreator` answering `(.ok, "t-new")`, and `struct NoFeed: AgentFeedSource` (empty snapshot, a finished `changes()` stream, `.unknown` replies).
  - The host is `ShellXLinkHostController.makeLinkHost(key: hostKey, trustedClients: { [phoneKey.publicKey] }, sources: …)`, served with `Task { await host.serve(hostEnd) }` over `makeInMemoryCircuitPair()`.
  - The client is `LinkClient.connect(phoneEnd, key: phoneKey, hostKey: hostKey.publicKey, clientVersion: "test", deviceName: "probe")`.
  - T is `terminal.surface.id` (the fake's `prepare` returns it), and W is any UUID.
  - `PushCollector` (file-private, `@MainActor`) has `init(_ stream: AsyncStream<TerminalViewPush>)`, which starts a main-actor task appending to `pushes: [TerminalViewPush]`. It has `func screen(terminalId: String) -> TerminalScreen`, which runs a fresh 2A `TerminalFrameAssembler` and `TerminalScreen` over the `.frame` pushes after the last `.opened(terminalId)`, and `func eventually(_ condition: @MainActor (PushCollector) -> Bool) async -> Bool`, which polls every 10 ms for up to 5 s.

```swift
@Test func theLinkHostOffersTerminalViewsAndCreationOnlyWithTheirSources()   // with both sources hostFeatures ⊇
                                                                             // {"terminal_view", "terminal_create"}; with neither, it has neither
@Test func thePhoneSeesTheTerminalAndTypesIntoIt() async throws {
    try terminal.output("\u{1b}chello-2b\r\n"); try await terminal.waitForScreen(containing: "hello-2b")
    #expect(try await client.openTerminalView(terminalId: T.uuidString, cols: 20, rows: 5) == .ok)
    #expect(await pushes.eventually { $0.screen(terminalId: T.uuidString).screenText().contains("hello-2b") })
    try await client.sendTerminalInput(terminalId: T.uuidString, units: [.text("ls"), .key(.enter, mods: [])])
    #expect(await terminal.inputBytes(until: { $0.count >= 3 }) == Data("ls\r".utf8))   // the host applies input after the call returns
    let created = try await client.createTerminal(workspaceId: W.uuidString)
    #expect(created.outcome == .ok && created.terminalId == "t-new")
}
@Test func inputForAnotherTerminalReachesNothing()   // open T; sendTerminalInput(terminalId: UUID().uuidString, [.text("x")])
                                                     // → a push .ended(terminalId: that id, reason: .notOpen); inputBytesBeforeBarrier() empty
@Test func unpairingClosesThePhonesView()            // open T; await host.disconnect(clientKey: phoneKey.publicKey) →
                                                     // eventually sizing.calls.last == .detach and registry.sinks.isEmpty
@Test func deviceManagementMidSessionRefusesTheViewAndNewOpens()   // open T; policy.change(blocked: true) → a push
                                                     // .ended(terminalId: T, reason: .refused); openTerminalView again → .refused
@Test func viewingAndTypingNeverChangeTheMacSelection()   // criterion 6 for view + input (Task 7 covers terminal.create):
                                                     // record the selection the same way Task 7's test does (selected workspace id,
                                                     // each pane's selected tab, the key window) → open T, send .text("x") and
                                                     // .key(.enter, mods: []), resize to 30×8, close the view → every recorded value
                                                     // is unchanged and no window was ordered front
```

- [ ] **Step 2: Wire and run:** `./scripts/sync-test-wiring`, then `toknix run scripts/shellx/test-app.sh ShellXLinkTerminalSessionTests`. Expected: FAIL with `error: type 'ShellXLinkHostController' has no member 'makeLinkHost'`.
- [ ] **Step 3: Commit red:** `git add cmuxTests/ShellXLinkTerminalSessionTests.swift cmux.xcodeproj/project.pbxproj && git commit -m "test(shellx): Link host serves terminal views end to end (failing)"`
- [ ] **Step 4: Implement** `Sources`, `makeLinkHost`, the init and `serve` changes, and the composition.
- [ ] **Step 5: Run:** `toknix run scripts/shellx/test-app.sh ShellXLinkTerminalSessionTests ShellXLinkHostPolicyTests ShellXLinkTerminalViewSourceTests`. Expected: `** TEST SUCCEEDED **`.
- [ ] **Step 6: Commit:** `git add Sources/ShellX/Remote/Link/ShellXLinkHostController.swift Sources/ShellX/Remote/ShellXRemoteService+App.swift && git commit -m "feat(shellx): serve terminal views and terminal creation over ShellX Link"`

---

### Task 9: Dogfood: tagged build and probe

**Files:** none (fixes found here go back to the owning task's files as `fix(shellx): …` commits, with a failing test first).

Steps marked **USER** are for the user. The agent waits for them and never does them itself. Keep the probe state dir at `~/.shellx-probe-2b` (mode 0700, outside any repository). Never print an offer URI, a password or a token.

- [ ] **Step 1: Build the probe and the tagged app**

Run: `toknix run swift build --package-path shellx-link --product shellx-link-probe`. Expected: `Build complete!`.
Run: `CMUX_DEV_BACKEND_MODE=local CMUX_TUI_CLIENT_LOCAL="$(scripts/shellx/build-cmux-tui.sh)" toknix run ./scripts/reload.sh --tag terminal-2b-mac`. Expected: `==> reload succeeded in …`. Do not pass `--launch`: on this Mac it stops with `tagged launches require authenticated dev credentials`, and that gate is not bypassed. Do not quote the printed App path.

- [ ] **Step 2: USER.** Open **ShellX DEV terminal-2b-mac**. It runs next to `/Applications/ShellX.app` with its own bundle id and socket. Sign in under Settings › Account with your ShellX account, then tell the agent it is running.

- [ ] **Step 3: USER, in your own terminal.** Skip this step if `~/.shellx-probe-2b` already exists and `shellx-link-probe machines` lists the tagged Mac. Otherwise run `shellx-link/.build/debug/shellx-link-probe login --state ~/.shellx-probe-2b --api https://relay.shellx.pro --email <your email> --password-stdin < <a 0600 file holding the password>`. If the account has no password (Google sign-in only), or `login` fails with `password_sign_in_removed` (the relay's password cut-over, contracts §2), skip Steps 4–7, note it in Step 8, and go on to Step 9.

- [ ] **Step 4: Pair the probe with the tagged Mac**

```bash
umask 077
CMUX_TAG=terminal-2b-mac scripts/cmux-debug-cli.sh rpc shellx.link.debug_pairing_offer '{}' > ~/.shellx-probe-2b/offer.json
shellx-link/.build/debug/shellx-link-probe pair --state ~/.shellx-probe-2b --offer-file ~/.shellx-probe-2b/offer.json
```
Run `pair` in the background. It logs `pairing request <id> sent; …`. Then either the **USER** clicks Allow in the sheet, or the agent runs `CMUX_TAG=terminal-2b-mac scripts/cmux-debug-cli.sh rpc shellx.link.debug_pairing_approve '{"pairing_id":"<id>"}'`. Expected: `paired with "…" after N ms: machine <id> …`. Then `rm ~/.shellx-probe-2b/offer.json`, because it holds a one-time code.

- [ ] **Step 5: Look and type.** Write `P="shellx-link/.build/debug/shellx-link-probe"` and `S="--state $HOME/.shellx-probe-2b --machine <tagged machine id>"`.
  - `$P workspaces $S --seconds 3`: take a workspace id W and a terminal id T.
  - `$P terminal-view T $S --cols 46 --rows 30 --seconds 20`. Expected: `first snapshot <ms> ms after the open`, with <ms> under 1000; the printed screen matches the Mac's; the Mac pane shows a 46×30 border while it runs and goes back to its own size after it exits.
  - While that runs, **USER**: type `ls` in that terminal on the Mac. Expected: a frame at the Mac's size (the Mac took the grid back) showing the output.
  - `$P terminal-type T $S --text "echo from-probe" --key enter --wait-ms 1500`. Expected: an `echo <ms> ms` line and a screen showing `from-probe`.
  - `$P terminal-type T $S --text "yes | head -100000" --key enter --wait-ms 4000`, then `$P terminal-view T $S --seconds 5`. Expected: the final screen shows the prompt after the `y` lines, and **USER** confirms the Mac stayed responsive.
  - `$P terminal-type T $S --key ctrl+c` exits 0. `$P terminal-type T $S --key cmd+q --dry-run` exits 1, because no ⌘ key exists.

- [ ] **Step 6: New tab.** `$P terminal-create W $S` → `ok` and a new terminal id. **USER**: the Mac still shows the same workspace, pane and tab, and no window moved forward.

- [ ] **Step 7: Unpair while viewing.** Run `$P terminal-view T $S --seconds 60`. **USER**: remove the probe phone in the tagged app's paired phones list. Expected: the probe ends at once (exit 4), and the Mac pane is back at its own size.

- [ ] **Step 8: Record** in the hand-off: the first-snapshot ms, the echo ms, the outcome of each step, and which **USER** steps did not run. Do not commit any log.

- [ ] **Step 9: USER, once plan 2C has landed.** Install the iPhone build with `shellx-ios/scripts/dev.sh device --device-id 51B0EA4F-D2C2-56A2-AC2B-3CD87DBAC107` (the phone must be unlocked) and pair it with ShellX DEV terminal-2b-mac. Then check:
  - a shell chip shows the Mac's screen within 1 s;
  - typing echoes within 300 ms;
  - vim and htop draw on the alternate screen;
  - Telex Vietnamese types the right accented letters;
  - rotating the phone resizes the terminal;
  - swiping to another chip closes the first view, and that terminal goes back to the Mac's size;
  - typing on the Mac takes the size back, and typing on the phone takes it again;
  - the ＋ chip adds a tab without changing the Mac's selection;
  - removing the phone on the Mac ends the pane.

---

### Task 10: Verify and hand off

**Files:** none new.

- [ ] **Step 1: Full verification**

Run: `toknix run scripts/shellx/test-app.sh MobileTerminalFrameSinkTests ShellXLinkGridConverterTests ShellXLinkSizingTests ShellXLinkFramePacingTests ShellXLinkTerminalViewFrameTests ShellXLinkTerminalViewInputTests ShellXLinkTerminalViewSourceTests ShellXLinkTerminalCreateTests ShellXLinkTerminalSessionTests ShellXLinkWorkspaceSourceTests ShellXLinkHostPolicyTests <IROH_SUITES>`
Expected: `** TEST SUCCEEDED **`, with no failure beyond the Task 0 baseline list.
Run: `toknix run swift test --package-path Packages/macOS/CmuxRemoteWorkspace --filter RemoteCLIRelayPolicyTests`. Expected: every test passed.
Run: `toknix run swift test --package-path shellx-link 2>&1 | tail -3`. Expected: `with 0 failures`.
Run: `./scripts/sync-test-wiring --check && ./scripts/wire-app-sources.py --check; echo "exit=$?"`. Expected: `exit=0`.
Run: `python3 scripts/verify-local.py; echo "exit=$?"`. Expected: `exit=0`.
Run: `git diff --name-only develop...HEAD | grep -E '^shellx-link/|RemoteRelayCommandPolicy|RemoteRelayRoutingSchema'`. Expected: no output.
Run: `git diff develop...HEAD -- Sources | grep -nE 'Logger\(|\.(notice|info|error|debug|warning)\(|cmuxDebugLog|print\('`. Expected: every hit interpolates only a fixed code or a count.

- [ ] **Step 2: Localization audit.** Record in the hand-off: no app UI, settings, menu or catalog string changed. The Link participant shows in the Mac's size panel through the existing localized device-kind label "iPhone". `docs/shared-terminal-sizing.md` is English developer documentation, like the rest of `docs/`.

- [ ] **Step 3: Review.** Run the default pre-merge review of skills/cmux-review/SKILL.md with a fresh review subagent. Give it the intent, the base and head SHAs (`develop`…`HEAD`) and the diff, ask for correctness first, and point it at Review Focus, Global Constraints and Spec notes. Fix concrete findings, each with a failing test first, as `fix(shellx): …`, re-run Step 1, and get a fresh review of a non-trivial repair.

- [ ] **Step 4: Security analysis text** (CLAUDE.md "Remote CLI relay"). Put it in the body of the merge commit (`-F`), and in the hand-off, word for word:

```text
Security analysis (CLAUDE.md "Remote CLI relay")

No v2 socket method is added and none gains a parameter: RemoteRelayCommandPolicy and RemoteRelayRoutingSchema are
unchanged and default-deny. terminal.create, mobile.terminal.create, terminal.input, mobile.terminal.input,
terminal.scroll, mobile.terminal.scroll, mobile.terminal.replay and mobile.terminal.paste stay off the relay
(RemoteCLIRelayPolicyTests.deniesLinkTerminalPathsThroughTheRelay). v2MobileTerminalCreate gains a Swift-only
preserveSelection parameter (default false), so the iroh and socket callers behave as before. The new calls are
ShellX Link messages (terminal.view.*, terminal.create; PROTOCOL.md §11), served only to a phone this Mac trusts:
its paired key, signed in to the same account, allowed on this Mac (§9).

1. Command or content execution on the Mac: yes, on purpose. terminal.view.input types into the one terminal its
   session opened, as the user at the keyboard would. Typed text has no control characters (TerminalInputCheck on
   both sides). Keys come from a fixed list with ctrl, alt and shift only, so no ⌘ shortcut is reachable. Pastes go
   through Ghostty's paste path, bracketed when the program asked. The mouse wheel acts only on the alternate
   screen. No message carries a command line, path, directory, environment variable, URL or program.
   terminal.create opens the user's default shell in a new tab of a listed workspace, in the directory the Mac
   chooses. It types nothing, and keeps the Mac's selection and focus (preserveBonsplitSelectionWhenUnfocused).
2. Objects the phone does not own: it reaches only terminals of the Mac's local workspaces, by ids the host looks
   up in its own list (ShellXLinkWorkspaceSource); SSH and other remote workspaces are not listed (not_found).
   Input goes only to the session's viewed terminal (not_open otherwise). A view ends when its tab or workspace
   closes (gone), when device management blocks remote control (refused; input after that is not applied), or
   when its session ends (removing the phone on the Mac closes its sessions at once). The phone's size applies to
   that terminal only while the phone is the last to use it, and the terminal returns to the Mac's size when the
   view ends.
3. Local state exposed: the screen of the terminal the phone opened, at most 4 000 rows and 262 144 bytes of its
   history, and the terminal's colors; no other terminal, file, environment or setting. Memory per view is bounded:
   one emission baseline and no frame queue, and the Link pump holds at most one unsent frame. Logs carry codes and
   counts only: no terminal content, keys, typed or pasted text, workspace or tab names, or ids.
```

- [ ] **Step 5: Land on develop** (contracts §1; never `main`, no deploy, no release). This plan changes app UI/runtime, so after the final review it waits for the USER device check and the user's merge directive (`merge`, `merge it` or `auto-merge`, CLAUDE.md "CI, review and merge"); if none was given, ask with the review summary. Only then run:

```bash
cd /Users/lehuuphu/Documents/myProjects/shellx
git checkout develop
git merge --no-ff feat/shellx-terminal-2b-mac -F <file holding "Merge branch 'feat/shellx-terminal-2b-mac' into develop", a blank line, then Step 4's text>
toknix run scripts/shellx/test-app.sh ShellXLinkTerminalSessionTests ShellXLinkTerminalViewFrameTests   # expect ** TEST SUCCEEDED **
git push origin develop
git worktree remove .worktrees/terminal-2b-mac && git branch -d feat/shellx-terminal-2b-mac
```

- [ ] **Step 6: Report** to the user:
  - the merge commit and the tests run;
  - the localization audit;
  - the dogfood results and which **USER** steps (Task 9 Steps 2–3, 5–7 and 9) are still open;
  - that the tagged build ShellX DEV terminal-2b-mac stays until the user quits it;
  - that a desktop release carrying `terminal_view` is the user's decision (contracts §7).

---

## Spec notes

1. **The seam lives in the observer and the byte tee.** S2 §3.8a names `MobileHostService` as one of the seam's places. In the code, its role is the iroh subscription tracker (`MobileHostService.swift:36`) and iroh delivery (`:605`, `:693`). The new demand does not go through it: the main-actor registry lives in the observer, and the IO-thread flag is an `AtomicBooleanGate` in the byte tee. `MobileHostService` stays unchanged, and iroh keeps its own tracker.
2. **Pull, not push.** S2 §3.8a says the Mac "sends frames to both" lanes. The observer only says "this surface may have changed". The Link view captures when 2A's pump asks, and diffs against its own baseline with CMUXMobileCore's public `renderGridEmission`, so there is no encode or decode and no copy of the observer. It cannot use the observer's iroh deltas: they chain from a shared baseline, and a slow phone would miss some.
3. **No replay RPC, no iroh input bodies.** Base spec §8.3 names `v2MobileTerminalReplay` and `v2MobileTerminalInput`. The replay rebases iroh's shared screen baseline (`adoptReplayBaseline`, `TerminalController+MobileScrollPrefetch.swift:52-53`). The input, scroll and paste bodies carry iroh delivery and watermark bookkeeping (`performMobileInput`). So 2B calls what those bodies call: `mobileResolveWorkspaceAndSurface` (which materializes a terminal), `resumeAgentHibernationForRemoteAttach`, `surface.mobileRenderGridFrame`, `ControlTerminalSocketTarget.sendInputResult` (the spec's text path, `TerminalController.swift:16588`), `sendNamedKeyResult` (`TerminalController+ControlTerminalBinding.swift:57`), `mobileScroll` plus `noteTerminalBytes` (`TerminalController.swift:16513-16516`), and `sendTextResult` (Ghostty's paste, as at `:16818`). The phone sends Enter itself, so the agent-aware submit key of `v2MobileTerminalPaste` does not apply.
4. **Sizing.** The same-user deferral (`TerminalSizingEngine.swift:98-112`) and the Mac's user id on phones (`TerminalController+SharedSizing.swift:104-110`) would keep a phone from ever owning the grid. So the Link participant has `counts_override: true`. "Run under `latest`" (base §10) happens only while a Link phone views a terminal whose policy is the default Fit everyone, and is undone after the last one leaves. A chosen policy is kept, and other clients' rules do not change.
5. **Remote input activity** (S2 §3.8b, `Workspace+AttentionFlashRouting.swift:21-27`). `performRemoteParticipantInput` suppresses the Mac-pane activity only during the synchronous send. Input that the Mac defers during a runtime clipboard read (`deferInputDuringRuntimeClipboardRead`) and replays later still counts as the Mac's activity. That case is rare, and accepted.
6. **Keys.** The Mac's named-key path has no modified `home`, `end`, `page_up` or `page_down` (`keycodeForNamedKey`, `TerminalSurface+Input.swift:837-852`). A `shift+home` unit is therefore skipped, as 2A skips unknown keys.
7. **Device name.** 2A's `TerminalViewSource.openView` gets no device information. So the Mac's size panel shows a Link phone as "iPhone" (`.iphone`, no name), Android phones included.
8. **Gone.** S2 never says how the Mac learns that a terminal is gone. 2B decides it from the list the phone sees: the source watches `ShellXLinkWorkspaceSource.workspaceChanges()`. A surface missing from the registry counts too. Surface teardown is not used, because hibernation tears the runtime down without closing the tab.
9. **First-snapshot fence.** The first snapshot waits up to 500 ms for the grid that sizing decided. This is the same idea as the replay viewport fence (`TerminalController.swift:16300-16325`), and it keeps a Mac-sized flash from being the phone's first screen.
10. **Snapshot cost.** Each snapshot captures up to 4 000 history rows on the main actor, and the observer's burst path costs the same. There is no rate limit in this version. Task 9 measures it; dragging the Mac window while a phone views is the case to watch.
11. **Burst scroll.** A burst delta's `scroll` is cmux's `scrolledRows` (the rows on screen plus the rows carried), not every row that scrolled. By PROTOCOL.md 11.6 the phone shows the newest carried rows and nothing in between, which matches cmux's own consumer. In that model, as in cmux's, the phone moves its own top rows into history. So a row written after the last frame and then scrolled away (a prompt line filled by a burst) keeps its older content in the phone's history; the next snapshot corrects it.
12. **`terminal.create`.** S2 §3.3 is confirmed by the code: `v2MobileTerminalCreate` passes no `preserveBonsplitSelectionWhenUnfocused` (`TerminalController.swift:16187-16195`). Only the ShellX path passes it; iroh's `mobile.terminal.create` keeps its behaviour. If an `ok` arrives without an id (the v2 body always sends one), it is answered `ok` without `terminal_id`.
13. **Agent pane as a terminal** (S2 §3.4). An agent's terminal is a listed terminal, so opening it needs no Mac code.

## Contract additions

Names other plans rely on that contracts §6 and §13 do not list. 2B does not edit the contracts; the coordinator adds these.

- **Dogfood identity for 2C:** tag `terminal-2b-mac`, tagged app "ShellX DEV terminal-2b-mac", probe state `~/.shellx-probe-2b`. 2C's iPhone dogfood can pair with this build.
- **Mac behaviour 2C and 3G can count on:**
  - `terminal.view.open` answers `failed` for a listed terminal that has no surface to view;
  - the first snapshot can come up to 500 ms after `ok` while the size settles;
  - snapshot `history` can reach 4 000 rows (2A sends 240 rows plus the fill);
  - when the Mac owns the grid, it can be wider than 300 columns (2C scales it, PROTOCOL.md 11.3);
  - a phone's view is a sizing participant `mobile:shellx-link-<uuid>` on the Mac.
- **Suggested for a later 2A revision:** pass the session's `device_name` into `TerminalViewSource.openView`, so the Mac's size panel can name the phone (Spec note 7).

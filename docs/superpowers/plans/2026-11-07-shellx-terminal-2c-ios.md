# ShellX iPhone terminal pane (2C) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the iPhone's shell-pane placeholder with the Mac's real terminal: drawn from plan 2A's grid frames, typed into from the system keyboard (Telex and VNI included), a key bar and a hardware keyboard, scrolled, sized and zoomed, one open at a time, plus the ＋ chip, "View as Terminal", demo terminals and render tests.

**Architecture:** `ShellXAppCore` gets the pure rules (typing with marked text, input batching, hardware keys, geometry and zoom, colours) and `TerminalViewModel`, one per workspace screen: it opens the one terminal shown through `MachineHub` (which now forwards `LinkClient.terminalPushes`), assembles frames with 2A's `TerminalFrameAssembler` and `TerminalScreen`, and sends every message through one FIFO outbox. The app draws with Core Text in a UIKit view (`TerminalSurfaceView`, a `UIScrollView` that is also the keyboard's `UITextInput`) inside a SwiftUI `TerminalPane`, which `WorkspaceScreen` shows for shell chips. `FakeMac` serves fake terminals built from `DemoTerminalScreens`, used by tests, render tests and the demo.

**Tech Stack:** Swift 6 language mode, iOS 17, SwiftUI, UIKit (`UITextInput`, `UIScrollView`, `UIEditMenuInteraction`, `UIPress`), Core Text, XCTest; `ShellXLinkCore` / `ShellXLinkSession` from plan 2A; `shellx-ios/scripts/dev.sh`.

**Spec:** `docs/superpowers/specs/2026-11-07-shellx-mobile-terminal-design.md` (S2: §2, §3.1, §3.3, §3.4, §3.6, §3.7, §3.9, §4, §5) on top of `docs/superpowers/specs/2026-10-28-shellx-mobile-workspaces-design.md` §2.2 (criteria 3–5), §6.2, §6.3, §7.2, §10, §11. Cross-plan names: `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` §1 (landing), §5 (demo location rule), §6 and §13 (terminal names and limits). Built on `docs/superpowers/plans/2026-11-07-shellx-terminal-2a-protocol.md` (its Interfaces blocks are the API this plan calls; its "Wire specification" is PROTOCOL.md §11).

## Global Constraints

- Branch `feat/shellx-terminal-2c-ios`, worktree `.worktrees/terminal-2c-ios`, from `develop`, only after plan 2A is merged into `develop` (Task 0 checks).
- Change files only under `shellx-ios/`. Exceptions: the two Android string files regenerated in Task 12 (only if `shellx-android/scripts/import-strings.py` exists) and the two ledgers named in Task 12. Never edit `shellx-link/` (2A owns it), `Sources/`, `Packages/` at the repository root, or the contracts file.
- Licence boundary (`shellx-ios/README.md`): the app's own code, the MIT `shellx-link` products and Apple frameworks on the allowlist of `scripts/shellx/check-ios-license.sh`. This plan imports only `Foundation`, `os`, `Observation`, `SwiftUI`, `UIKit`, `CoreText`, `CoreGraphics`, `QuartzCore`, `XCTest`, `ShellXLinkCore`, `ShellXLinkSession`, `ShellXLinkAccount` and the app's own modules. Reading cmux's GPL `Packages/iOS/CmuxMobileShell` or `Packages/Shared/CMUXMobileCore` (or MIT SwiftTerm) for reference is fine; copying any of it is not. No network package, no symlink, no word "Manaflow".
- Build and test only through `shellx-ios/scripts/dev.sh` (`test core|app|release|all`, `screenshots`, `device`) or, for one ShellXAppCore suite, `swift test --package-path shellx-ios/Packages/ShellXAppCore --filter …`. Never `xcodebuild`.
- Prefix every build, test and git command with `toknix run` (user instruction). The expected output written below is what the command itself prints.
- 2A names exactly as its Interfaces blocks: `TerminalViewPush` (`.opened(terminalId:)`, `.frame(terminalId:part:)`, `.ended(terminalId:reason:)`), `LinkClient.terminalPushes`, `openTerminalView(terminalId:cols:rows:)`, `closeTerminalView(terminalId:)`, `sendTerminalInput(terminalId:units:)`, `resizeTerminalView(terminalId:cols:rows:)`, `resyncTerminalView(terminalId:)`, `createTerminal(workspaceId:)`, `TerminalFrameAssembler`, `TerminalAssemblyResult`, `TerminalScreen`, `TerminalRow`, `TerminalStyledRun`, `TerminalCell`, `TerminalCellStyle`, `TerminalAttribute`, `TerminalPalette`, `TerminalCursor`, `TerminalCursorShape`, `TerminalGridFrame`, `TerminalFrameHead`, `TerminalFrameKind`, `TerminalFramePart`, `TerminalStyle`, `TerminalLine`, `TerminalRun`, `TerminalFrameSplitter`, `TerminalInputUnit`, `TerminalKey`, `TerminalModifier`, `TerminalInputCheck`, `TerminalInputError`, `TerminalViewOpenOutcome`, `TerminalViewEndReason`; host side `TerminalViewSource`, `TerminalView`, `TerminalViewOpenResult`, `TerminalViewEvent`, `TerminalCreator`, `LinkHost(…, terminalControl:, terminalViews:, terminalCreator:, …)`; `ShellXLink.terminalViewFeature`, `ShellXLink.terminalCreateFeature` and the `ShellXLink.terminal*` limits. If `develop` has a 2A name that differs, the code on `develop` wins: use it and add a line to Spec notes.
- Fixed values: terminal font SF Mono (`UIFont.monospacedSystemFont(ofSize:weight:)`) at 12 pt, regular and bold; content padding 4 pt; zoom between the fit-to-width scale and 2.0; resize sent 200 ms after the last size change; `busy` retried every 300 ms, at most 5 times; a failed open retried once after 1 s; alternate-screen scrolling summed for 50 ms per message; an echo waited for at most 2 s; a paste above 262 144 UTF-8 bytes (`TerminalInputBatcher.maxPasteBytes`) is refused with `terminal.paste.tooLarge`; key bar order esc, tab, ctrl, ←, ↑, ↓, →, then a hide-keyboard key at the trailing end; key bar row 44 pt high with 36 pt keys; the phone keeps `TerminalScreen.defaultMaxHistoryRows` (10 000) history rows.
- Strings: every visible or spoken string is a key in `shellx-ios/ShellX/Localizable.xcstrings` with `en`, `vi` and a `comment`, entry shape `{"comment": …, "extractionState": "manual", "localizations": {"en": {"stringUnit": {"state": "translated", "value": …}}, "vi": {…}}}`, used through `String(localized:)` or `LocalizedStringResource`. `Text(verbatim:)` only for never-translated text (key caps `esc`, `tab`, `ctrl`; terminal content).
- Contracts §17 (plan 2B): frames can be wider than 300 columns and taller than 120 rows while the Mac's window owns the size (the 20-300 / 5-120 clamp applies only to the size a phone asks for), so nothing on the phone clamps a frame's size (2A's assembler takes 1-1 000); the first snapshot may come up to 500 ms after `terminal.view.open` (the Mac waits for the phone's size), during which the pane shows its loading state; `terminal.view.open.result` answers `failed` for a terminal the Mac lists but cannot view; the dogfood Mac build is tagged `terminal-2b-mac`.
- Privacy: never log terminal content, typed or pasted text, keys, or workspace and tab titles. `Logger` lines carry codes and counts only (`privacy: .public` only for those).
- HIG (`Packages/iOS/AGENTS.md`): before Tasks 8, 9 and 10 fetch and read the Apple HIG pages named there and follow them. The deliberate deviations (a fixed 12 pt terminal font with pinch zoom instead of Dynamic Type; a hide-keyboard key added to the spec's key bar) go into the hand-off of Task 12.
- Never quit, relaunch or replace the user's running ShellX (`/Applications/ShellX.app`) or cmux. The only simulator is `dev.sh`'s "ShellX Dev".
- Commits: conventional (`feat(shellx-ios): …`, `docs(shellx): …`), staged with explicit `git add <paths>`.
- Landing (contracts §1, the rule for app and UI plans): this plan changes app UI and runtime, so after the final review it waits for the USER live check on the iPhone and the user's merge directive (`merge`, `merge it` or `auto-merge`, CLAUDE.md "CI, review and merge"); only then merge into `develop` from the main checkout and push `develop`. If no directive was given, ask for one with the review summary. Never `main`, never deploy, never upload to TestFlight or the App Store.
- `<DEMO_PKG>` and `<APP_DEMO>` are the two demo directories Task 0 finds; write the real path wherever this plan writes them.

## Review Focus

1. **Fast chip swipes and the wrong terminal** (base spec §4 anti-goal: typed text must never land in a terminal other than the one shown): swiping A → B → A while frames are in flight never draws A's frames on B's page and never sends B's keystrokes to A. Pinned in Task 5 (`testFastSwitchesNeverShowAnotherTerminalsFrames`) and Task 6 (`testInputAfterASwitchGoesToTheNewTerminal`).
2. **Telex or VNI composition meeting the key bar, ctrl or a hardware key mid-word**: the composed word is committed before the key, ctrl tapped mid-word applies to the next key and not to the word, and a hardware key while composing goes to the input method. Pinned in Task 3 (`testAKeyWhileComposingCommitsTheWordFirst`, `testCtrlTappedWhileComposingWaitsForTheNextKey`, `testComposingHandsEveryKeyToTheSystem`).
3. **Keyboard show/hide and rotation bursts**: several pane sizes within a fraction of a second become one resize with the last size, and a size change while the open is in flight follows the open. Pinned in Task 6 (`testGridChangesSendOneResizeWithTheLatestSize`, `testResizeDuringTheOpenFollowsIt`).
4. **Backgrounding or a dropped link mid-view**: the view closes once, the last screen stays, it reopens once on return or reconnect and starts a fresh assembler (no resync storm). Pinned in Task 5 (`testBackgroundDuringTheOpenClosesAfterIt`, `testMacOfflineKeepsTheScreenAndReopensOnceOnline`, `TerminalViewLiveTests.testAReconnectReopensTheView`).
5. **The Mac's size winning, then the phone's coming back**: a 100-column grid, and one of 320 columns and 130 rows (beyond what a phone may ask for, contracts §17), fit the width; a pinch never goes below fit, frames of the same width keep the pinch, and a grid of another width goes back to fit. Pinned in Task 4 (`TerminalZoomTests`, `testFitScaleShrinksAWiderGridAndNeverEnlarges`), Task 5 (`testAGridWiderThanThePhoneCanAskForIsShown`) and Task 8 (`testRendersHtopFittedToWidth`, `testRendersA320ColumnGridFittedToWidth`).

---

## Design (decided)

### Renderer: Core Text in a UIKit view

`TerminalCanvasView` (a `UIView`) draws with Core Text; it sits inside `TerminalSurfaceView`, a `UIScrollView` used for scroll physics only, which is also the first responder for the keyboard. SwiftUI's `TerminalPane` hosts it through `TerminalSurface` (`UIViewRepresentable`). SwiftUI `Canvas` was rejected:

- Criterion 4 (key echo p95 < 300 ms, network included): an echo changes one row. The canvas keeps a per-row layout cache (`TerminalRowLayout`, rebuilt only for rows whose value changed) and redraws the visible rows from it. A `Canvas` re-runs its whole closure and re-resolves every `Text` on each change, with no layout kept across frames, after a SwiftUI diff on the main thread.
- Criterion 3 (open p95 < 1 s): only the visible rows of the first snapshot are laid out; history (up to 10 000 rows) is laid out only when scrolled into view. A `Canvas` needs one tall canvas or one view per row in a `ScrollView`.
- Criterion 5 (floods): frames come at the host's pace (one unsent frame per view, 2A §11.8) and each apply touches only changed rows; scrolling through history is native `UIScrollView` physics drawing about 40 rows per offset.
- Input needs UIKit anyway: marked text needs `UITextInput`, hardware keys need `pressesBegan`; both are on the same view.
- Cells are placed by column, never by font advance, so CJK and emoji fallback fonts cannot push later cells sideways (Task 8).

### Input

- The surface is a `UITextInput` whose document is only the marked text. Committed text (`insertText`) is sent; marked text (`setMarkedText`) is drawn at the cursor and never sent; `deleteBackward` edits the marked text and, only when there is none, sends `backspace` (S2 §3.6). Rules: `TerminalTyping`, Task 3.
- Return arrives as `"\n"` in `insertText` and goes out as `key enter`; tab and line breaks become keys, other control characters are dropped (2A refuses them in text).
- Key bar (`TerminalKeyBar`) at the bottom of the pane, which SwiftUI keeps above the keyboard, shown while the surface has focus: esc, tab, ctrl (latched for the next key), ←, ↑, ↓, →, and a trailing hide-keyboard key.
- Hardware keys (`pressesBegan`): esc, tab, arrows, home, end, page up and down, forward delete and ctrl+letter go out as named keys; plain letters, Return and Backspace go through the text system (so input methods keep working); ⌘ combinations go to the system (S2 §3.7: no app shortcuts). Mapping: `TerminalHardwareKeys`, Task 3.
- Paste: a long press opens the edit menu with Paste, and ⌘V; both send `paste` units (at most 16 384 bytes per message).
- Scrolling: on the main screen the phone scrolls its own history (`UIScrollView`); on the alternate screen a vertical pan becomes `scroll` units (finger down = positive = toward older content), summed for 50 ms per message.
- Size: the phone asks for what fits the pane at 12 pt (`TerminalGeometry.phoneGrid`) on open and after the pane's size changes (keyboard, rotation), 200 ms after the last change. A grid wider than the pane (the Mac's size won) is drawn scaled to fit the width, whatever width the head reports (it can pass 300 columns and 120 rows, contracts §17); a pinch zooms between that scale and 2.0 (`TerminalZoom`). Pinching never changes the requested size.

### Rules of `TerminalViewModel` (Tasks 5 and 6)

The model holds the terminal shown (`terminalId`), the phone grid (nil until the surface reports one), `active` (its newest `run()` is running and it is not suspended), and at most one **view**: the terminal it asked the Mac to show, an attempt number, whether the open was answered `ok`, whether its `.opened` push arrived, and the size last sent for it. Every message to the Mac goes through one FIFO outbox drained by one task (started by the first `run()`, finished by `deinit`); the task awaits each call, and an open's answer is handled before the next message goes.

- **R1 Want.** The model wants a view while `active`, `terminalId != nil`, a grid is known, `link.isOnline(machineID)`, `link.supportsTerminalView(machineID)`, the phase is not `.unavailable`, and it is not waiting for the Mac after a `.notSent` (R3). `reconcile()` (after every change below) first queues `close` for a view that is no longer wanted or is for another terminal and forgets it; then, when wanted and there is no view, queues `open(terminalId, cols, rows)` with the next attempt number and sets `.connecting`. While `active`, when the Mac is the reason nothing can be wanted: online without `terminal_view` → `.unsupported`; not online → `.offline`. A model that is not `active` never changes its phase in `reconcile()`.
- **R2 show(id).** A different id: a fresh `TerminalScreen(maxHistoryRows:)`, assembler and `TerminalTyping`; `snapshots = 0`, `topShift = 0`, `screenRevision += 1`; retry budgets restored; `.connecting`; the first-screen clock starts (when `id` is not nil); reconcile. The same id does nothing. The clock starts here, at the user's swipe or tap, not at the `ok`: the Mac may hold the first snapshot up to 500 ms for the phone's size (contracts §17) and that wait is part of criterion 3. The phase stays `.connecting` (the pane's loading state) after the `ok` until a snapshot is applied.
- **R3 Open answers**, for the current attempt only (any other is ignored): `ok` → answered. `busy` → forget the view; after 300 ms reconcile; after 5 such retries `.unavailable(.failed)`. `not_found` → forget, `.unavailable(.gone)`. `refused` → forget, `.unavailable(.refused)`. `failed` (also the answer for a terminal the Mac lists but cannot view, contracts §17), an unknown outcome, or `.noAnswer` while `link.isOnline` → forget; the first time, reconcile after 1 s; the second time `.unavailable(.failed)`. `.notSent`, or `.noAnswer` while not online → forget, and open again only after the next `.state` event of this Mac or a `show`, `retry` or `resume` (so a hub that still calls the Mac online during a reconnect cannot make the model ask in a loop); while `active`, R1 then sets `.offline` or `.unsupported`.
- **R4 `.opened(id)`** for the view's terminal on this Mac: a fresh `TerminalFrameAssembler`; frames count from now on. Frames of that terminal before it are ignored. Every push for another terminal or another Mac is ignored.
- **R5 Frames.** `assembler.receive(part)`; `resync` → queue `resync(id)`; a complete frame → R7.
- **R6 `.ended(id, reason)`** of the view (after its `.opened`): `gone` → `.unavailable(.gone)`; `refused` → `.unavailable(.refused)`; `not_open` → forget the view and reconcile at once (a new open); `failed` or unknown → as a failed open (R3). Before `.opened` it is ignored.
- **R7 Apply.** `screen.apply(frame)`, `screenRevision += 1`. A snapshot: `snapshots += 1`, `topShift = 0`, phase `.live`, the first-screen latency recorded (once per start of the clock; a reopen after R6, R8 or `resume` starts it again when it is not running), both retry budgets restored. A history frame: `topShift += after − before`. A delta on the main screen: `topShift −= max(0, before + min(scroll, rows) + min(history, max(0, scroll − rows)) − after)` (`before`/`after`: history row counts around the apply; `scroll`, `rows`, `history` from the head). Every apply records `terminalFrameApply` (assemble plus apply); the first apply after an echo start records `terminalKeyEcho`.
- **R8 Mac state** `.state(machineID, s)`: not `.online` → forget the view without a close (its session is gone) and, unless the phase is `.unavailable` or `.unsupported`, set `.offline`; the screen stays. `.online` → reconcile (a new open).
- **R9 run().** Subscribes to `link.terminalEvents()`, sets running, reconciles, handles events until cancelled, then clears running and reconciles (the close is queued and still goes out). A `run()` that starts while an older one is still finishing (SwiftUI restarts `.task`) takes over: only the newest handles events and owns running; an older one returns without touching state. `suspend()` / `resume()` (app background / foreground) clear / set suspended and reconcile. `retry()` clears `.unavailable` and the budgets, sets `.connecting`, reconciles.
- **R10 Typing** (`insertText`, `setMarkedText`, `unmarkText`, `deleteBackward`, `press`, `toggleCtrl`): `TerminalTyping` turns the call into units; with a view, each message of `TerminalInputBatcher.messages(units)` is queued as `input(id, units)` (after any queued open) and raises `sentInputs` by one; without a view they are dropped. A message holding a `text` or `key` unit starts the echo clock if it is not running; the clock is dropped after 2 s without a frame.
- **R11 Grid** `setPhoneGrid(cols:rows:)`: values below 1 are ignored; the grid is stored and the model reconciles (the first grid may open). With a view, a grid different from the size last sent is queued as `resize` 200 ms after the last change (a newer change restarts the wait); an open carries the grid of its moment.
- **R12 Paste and scroll.** `paste(text)`: when `TerminalInputBatcher.pasteFits(text)` is false nothing is sent and the model raises the `pasteTooLarge` notice (string `terminal.paste.tooLarge`); otherwise `TerminalInputBatcher.pasteUnits(text)` → messages, with a view. `scroll(lines:)` only with a view and `screen.alt`: summed for 50 ms, then `TerminalInputBatcher.scrollUnits(total)` as one message.

---

## File map

`Core/` is `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/`; `CoreTests/` is `shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/`; `App/` is `shellx-ios/ShellX/`; `AppTests/` is `shellx-ios/ShellXTests/`.

| Path | Responsibility | Task |
| --- | --- | --- |
| `<DEMO_PKG>/DemoTerminalScreens.swift` (new) | Demo palette, styles, markup, fixtures | 1 |
| `<DEMO_PKG>/FakeMacTerminals.swift` (new) | `FakeMac`'s `TerminalViewSource` and `TerminalCreator`; a tiny fake shell | 1 |
| `<DEMO_PKG>/FakeMac.swift`, `<DEMO_PKG>/FakeMacWorkspaces.swift` | Serve terminals; test API | 1 |
| `Core/Terminal/TerminalLink.swift` (new) | Hub events, open result, the `TerminalLink` seam | 2 |
| `Core/Link/MachineHub+Terminal.swift` (new) | Hub terminal calls and `terminal.create` | 2 |
| `Core/Link/MachineEvent.swift`, `MachineConnection.swift`, `MachineHub.swift` | Forward `terminalPushes`; state events for terminal pages | 2 |
| `Core/Diagnostics/LatencyLog.swift` | Three terminal metrics | 2 |
| `Core/Terminal/TerminalTyping.swift` (new) | Marked text and the ctrl latch → units | 3 |
| `Core/Terminal/TerminalInputBatcher.swift` (new) | Units → messages within 2A's limits | 3 |
| `Core/Terminal/TerminalHardwareKeys.swift` (new) | HID usage → named key; key bar keys | 3 |
| `Core/Terminal/TerminalGeometry.swift` (new) | Phone grid, fit scale, zoom, scroll lines | 4 |
| `Core/Terminal/TerminalColors.swift` (new) | Styles and palette → colours | 4 |
| `Core/Terminal/TerminalViewModel.swift` (new) | R1–R12 | 5, 6 |
| `Core/Workspaces/WorkspaceScreenModel.swift` | Terminal shown, View as Terminal, the terminal ＋ made | 7 |
| `App/UI/Terminal/TerminalFont.swift`, `TerminalRowLayout.swift`, `TerminalCanvasView.swift`, `TerminalSurfaceView.swift`, `TerminalSurface.swift`, `TerminalPane.swift` (new) | Drawing, scrolling, zoom, pane states | 8 |
| `App/UI/Terminal/TerminalSurfaceView+TextInput.swift`, `TerminalKeyBar.swift` (new) | Keyboard, hardware keys, paste, key bar | 9 |
| `App/UI/Workspaces/ShellPanePlaceholder.swift` | Old-Mac text | 8 |
| `App/UI/Workspaces/WorkspaceScreen.swift`, `PaneChips.swift`, `WorkspaceView.swift`, `WorkspaceFeedback.swift` | Terminal pages, menu items, ＋ chip, wiring | 10 |
| `<APP_DEMO>/DemoComposition.swift` | The demo Mac's terminals | 11 |
| `App/Localizable.xcstrings` | 20 keys | 8, 9, 10 |
| `CoreTests/Support/TerminalTestSupport.swift` (new) | `TerminalPushReader`, `Collector`, `ScriptedTerminalLink`, frame helpers | 1, 2, 5 |
| `CoreTests/…` | `DemoTerminalScreensTests`, `FakeMacTerminalsTests`, `MachineHubTerminalTests`, `TerminalTypingTests`, `TerminalInputBatcherTests`, `TerminalHardwareKeysTests`, `TerminalGeometryTests`, `TerminalColorsTests`, `TerminalViewModelTests`, `TerminalViewLiveTests`, `TerminalViewModelInputTests`, `WorkspaceScreenModelTests` (extended), `Support/AsyncTestSupport.swift` (EventLog) | 1–7 |
| `AppTests/…` | `TerminalRenderTests`, `TerminalRowLayoutTests`, `TerminalSurfaceTests` (new); `WorkspaceRenderTests`, `WorkspaceViewTests`, `WorkspaceLiveRenderTests`, `DemoCompositionTests` (extended) | 8–11 |

`ShellX/` and `ShellXTests/` are synchronized folders: a new Swift file there needs no `project.pbxproj` change.

---

### Task 0: Set up the worktree

**Files:** none.

- [ ] **Step 1: Check that plan 2A is on `develop`**

```bash
cd /Users/lehuuphu/Documents/myProjects/shellx
git log develop --merges --oneline | grep -c "feat/shellx-terminal-2a-protocol"
git show develop:shellx-link/Sources/ShellXLinkSession/LinkClient.swift | grep -c "terminalPushes"
```

Expected: `1` (or more) and a number of 1 or more. If either is `0`, stop and report: 2C needs 2A merged.

- [ ] **Step 2: Create the worktree** (superpowers:using-git-worktrees; this repository keeps worktrees in `.worktrees/`)

```bash
git worktree add .worktrees/terminal-2c-ios -b feat/shellx-terminal-2c-ios develop
cd .worktrees/terminal-2c-ios
```

- [ ] **Step 3: Note where the plans live.** This plan, plan 2A and the contracts file may be untracked in the main checkout; read them from `/Users/lehuuphu/Documents/myProjects/shellx/docs/superpowers/plans/` and never add them to this branch.

- [ ] **Step 4: Find the demo directories** (contracts §5: plan 1C may have moved them)

```bash
dirname "$(git ls-files 'shellx-ios/Packages/ShellXAppCore/Sources/*/FakeMac.swift')"
dirname "$(git ls-files 'shellx-ios/ShellX/*/DemoComposition.swift')"
```

Expected: `shellx-ios/Packages/ShellXAppCore/Sources/ShellXDemo` (1C landed) or `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppTestSupport` (not yet); then `shellx-ios/ShellX/Demo` or `shellx-ios/ShellX/Debug`. The first is `<DEMO_PKG>`, the second `<APP_DEMO>`; write both down for the rest of the plan. Either way, core and app tests reach the fake Mac through `import ShellXAppTestSupport` (after 1C it re-exports `ShellXDemo`), and every type this plan adds in `<DEMO_PKG>` that the app or a test uses is `public`.

- [ ] **Step 5: Check the baseline**

Run: `shellx-ios/scripts/dev.sh test core`
Expected: the last line is `==> test core: passed`.
Run: `shellx-ios/scripts/dev.sh test app`
Expected: the last line is `==> test app: passed`. If either is red, stop and report the failing tests before any change.

---

### Task 1: Demo terminal screens and the fake Mac's terminals

**Files:**
- Create: `<DEMO_PKG>/DemoTerminalScreens.swift`, `<DEMO_PKG>/FakeMacTerminals.swift`
- Modify: `<DEMO_PKG>/FakeMac.swift` (stored properties 56-87, `init` 90-110, the `LinkHost` call in `open(phoneKey:)` 169-176, new API after the `// MARK: - Workspaces` block 220-253)
- Modify: `<DEMO_PKG>/FakeMacWorkspaces.swift` (two helpers after `remove(_:)`, line 77)
- Create: `CoreTests/Support/TerminalTestSupport.swift` (`TerminalPushReader`)
- Test: create `CoreTests/DemoTerminalScreensTests.swift`, `CoreTests/FakeMacTerminalsTests.swift`

**Interfaces:**
- Consumes: 2A's `TerminalViewSource`, `TerminalView`, `TerminalViewOpenResult`, `TerminalViewEvent`, `TerminalCreator`, grid types and the `LinkHost` init parameters `terminalViews:` and `terminalCreator:` (after `terminalControl:`).
- Produces:

```swift
// DemoTerminalScreens.swift (public)
public struct DemoTerminalFixture: Equatable, Sendable {
    public var cols: Int
    public var rows: Int
    public var alt: Bool
    public var palette: TerminalPalette
    public var styles: [TerminalStyle]
    /// History rows, oldest first (main screen only).
    public var history: [[TerminalRun]]
    /// Screen rows from the top; rows past the end are blank.
    public var screen: [[TerminalRun]]
    public var cursor: TerminalCursor
    /// A shell: `screen[cursor.y]` is this prompt, typing is echoed after it, Enter starts a new prompt row.
    /// Nil: input changes nothing.
    public var prompt: [TerminalRun]?
    /// Printed one after the other at the cursor while the terminal is viewed, every `tickInterval`.
    public var ticks: [[TerminalRun]]
    public var tickInterval: Duration?
    public init(cols: Int, rows: Int, alt: Bool = false, palette: TerminalPalette = DemoTerminalScreens.palette,
                styles: [TerminalStyle] = DemoTerminalScreens.styles, history: [[TerminalRun]] = [],
                screen: [[TerminalRun]], cursor: TerminalCursor, prompt: [TerminalRun]? = nil,
                ticks: [[TerminalRun]] = [], tickInterval: Duration? = nil)
    /// The content as one snapshot: head (`.snapshot`, cols, rows, alt, cursor, palette, history = alt ? 0 : history.count),
    /// every style, history rows at y = -history.count ... -1 (none on the alternate screen), then each non-empty screen row at its y.
    public var snapshot: TerminalGridFrame { get }
}
public enum DemoTerminalScreens {
    public static let palette: TerminalPalette            // fg "#e6e3f0", bg "#0b0716", cursor "#60a5fa", colors xterm256(base: the 16 below)
    public static let styles: [TerminalStyle]              // ids 1-13 below
    /// The 16 given colours, then the 6×6×6 cube (levels 0, 95, 135, 175, 215, 255; index 16 + 36r + 6g + b), then 24 greys
    /// (8 + 10·i, index 232 + i), each "#rrggbb" in lowercase.
    public static func xterm256(base: [String]) -> [String]
    /// Runs from markup: "{n}" (one or more ASCII digits between braces) switches to style n for what follows ("{0}": the
    /// default style, `style` nil); any other "{" is text. Each Character whose first scalar is East Asian wide (U+1100-115F,
    /// U+2E80-303E, U+3041-33FF, U+3400-4DBF, U+4E00-9FFF, U+A000-A4CF, U+AC00-D7A3, U+F900-FAFF, U+FE30-FE4F, U+FF00-FF60,
    /// U+FFE0-FFE6, U+20000-3FFFD) or has `properties.isEmojiPresentation` is its own run with `width` 2; any other Character
    /// of more than one scalar is its own run with `width` 1; the rest of a same-style stretch is one narrow run. No run has `x`.
    public static func runs(_ markup: String) -> [TerminalRun]
    public static let shell: DemoTerminalFixture
    /// A delta on `shell`: row 10 becomes its prompt + "ls -la", cursor (29, 10).
    public static let shellTyping: TerminalGridFrame
    public static let devServer: DemoTerminalFixture
    public static let wide: DemoTerminalFixture
    public static let vim: DemoTerminalFixture
    public static let htop: DemoTerminalFixture
    public static let agent: DemoTerminalFixture
    /// A fresh shell: row 0 is runs("{1}$ "), cursor (2, 0), that row is the prompt.
    public static func prompt(cols: Int, rows: Int) -> DemoTerminalFixture
}

// FakeMac (public additions)
public struct TerminalViewSize: Equatable, Sendable {          // nested: FakeMac.TerminalViewSize
    public var terminalId: String; public var cols: Int; public var rows: Int
    public init(terminalId: String, cols: Int, rows: Int)
}
/// False: no `terminal_view` in `welcome` (a ShellX from before it). False too when `servesWorkspaces` is false.
public nonisolated let servesTerminalViews: Bool
/// False: no `terminal_create` in `welcome`. False too when `servesWorkspaces` is false.
public nonisolated let acceptsTerminalCreate: Bool
// init gains, at the end: servesTerminalViews: Bool = true, acceptsTerminalCreate: Bool = true
public func setTerminalFixtures(_ fixtures: [String: DemoTerminalFixture])   // by terminal id; others get prompt(cols:rows:)
public func refuseTerminalView(_ terminalId: String, with outcome: TerminalViewOpenOutcome)
public func holdTerminalViewOpens()
public func releaseTerminalViewOpens()
public func emitTerminalFrame(_ terminalId: String, _ frame: TerminalGridFrame)       // to that terminal's current view
public func endTerminalView(_ terminalId: String, reason: TerminalViewEndReason)      // its current view ends
public func setNextTerminalCreateOutcome(_ outcome: WorkspaceControlOutcome)
public var terminalViewOpens: [TerminalViewSize] { get }      // every openView, in order (refused ones too)
public var terminalViewResizes: [TerminalViewSize] { get }
public var terminalViewCloses: [String] { get }
public func terminalViewInputs(_ terminalId: String) -> [[TerminalInputUnit]]
public func terminalViewSnapshotRequests(_ terminalId: String) -> Int
public var terminalCreates: [String] { get }                  // workspace ids, in order

// FakeMacWorkspaces (internal)
func listsTerminal(_ terminalId: String) -> Bool
/// Appends LinkTerminal(terminalId: "<workspaceId>-new-<n>" (n = 1, 2, … over the Mac's life), title: "zsh",
/// order: the workspace's last order + 1, selected: false) and broadcasts the change; nil for a workspace it does not list.
func addTerminal(to workspaceId: String) -> String?

// CoreTests/Support/TerminalTestSupport.swift
/// Reads `pushes` as they come: every push, and the screen of the newest view of `terminalId` (a fresh 2A
/// `TerminalFrameAssembler` and `TerminalScreen` at each `.opened(terminalId)`; frames of other terminals ignored).
final class TerminalPushReader: @unchecked Sendable {
    init(_ pushes: AsyncStream<TerminalViewPush>, terminalId: String)
    var pushes: [TerminalViewPush] { get }
    var screen: TerminalScreen { get }
}
```

`FakeMacTerminals` (internal, `final class FakeMacTerminals: TerminalViewSource, TerminalCreator, @unchecked Sendable`, an `NSLock` like `FakeMacWorkspaces`; `FakeMac` makes one in `init` over its `workspaceSource` and passes it as `terminalViews:` when `servesWorkspaces && servesTerminalViews` and as `terminalCreator:` when `servesWorkspaces && acceptsTerminalCreate`, nil otherwise) and its view class `FakeMacTerminalView: TerminalView, @unchecked Sendable` behave as follows:

1. `openView(terminalId:cols:rows:)` records the size, waits while opens are held, answers `.notOpened(outcome)` for a refused id, `.notOpened(.notFound)` when `listsTerminal` is false, else makes a view over `fixtures[id] ?? DemoTerminalScreens.prompt(cols: cols, rows: rows)`, makes it that id's current view and answers `.opened(view)`.
2. `nextFrame()` returns, in this order of preference: the first queued emitted frame or end; on the first call, or after `requestSnapshot()`, a snapshot of the current content; when anything was typed or printed since the last frame, one delta (head `.delta`, the fixture's cols, rows and `alt`, the cursor, `scroll` = rows that scrolled off since the last frame, every screen row as a line, every style); otherwise it waits. After `close()`, or when its task is cancelled, it returns `.ended(.failed)` at once.
3. `input(_:)` is recorded per terminal id. With a `prompt`: `text` appends to the typed text after the prompt on the cursor row; `paste` too, each line break acting as Enter; `key enter` keeps the row and starts a new prompt row under it (at the bottom row the screen scrolls one row into history); `key backspace` removes the last typed Character (never the prompt); ctrl+`c` appends `^C`, then acts as Enter; ctrl+`l` clears the screen to one prompt row at the top (history kept). Other units change nothing. Without a `prompt` input is only recorded.
4. `resize(cols:rows:)` is recorded (the fake keeps its fixture's size); `requestSnapshot()` is counted per terminal id; `close()` is recorded and stops the ticks.
5. A fixture with `tickInterval` prints `ticks[n % ticks.count]` (n = 0, 1, …) at the cursor row every interval while its view is open: the cursor moves down a row, and at the bottom row the screen scrolls one row into history.
6. `createTerminal(workspaceId:)` is recorded; a forced next outcome other than `.ok` answers `(outcome, nil)` once; otherwise `addTerminal(to:)` gives `(.ok, id)` or `(.notFound, nil)`.

Fixtures (styles: 1 fg 2 bold · 2 fg 6 bold · 3 faint · 4 fg 1 · 5 fg 3 · 6 fg 4 · 7 inverse · 8 fg 0 bg 6 · 9 fg 8 italic · 10 fg 5 · 11 fg_rgb `#ff8800` · 12 fg 12 underline · 13 strike. Base colours 0-15: `#1b1a23 #e88a8a #6fd49a #e8c468 #60a5fa #c792ea #7fd6e0 #d0cde0 #4a4858 #f2a7a7 #93e3b5 #f0d68f #8bbefc #d9b0f0 #a3e6ee #f5f3fa`). Every row is written as `runs("…")` of the markup given; `P` is `{1}➜ {2}shellx {5}git:(develop){0} ` (23 columns), `W` is `{1}➜ {2}notes{0} ` (8 columns). No row may be wider than its fixture's columns.

| Fixture | Size, screen | Content |
| --- | --- | --- |
| `shell` | 50 × 40, main; cursor (23, 10); prompt `runs(P)` | History, 30 rows, oldest first: `P` + `git log --oneline -6`; six commits `{5}d0a26e2{0} docs: specs for sign-in and terminal`, `{5}df63759{0} release: point the website at 1.7.0`, `{5}f904210{0} build: ShellX for Windows 1.7.0`, `{5}46f99e7{0} build: ShellX 1.7.0 (build 123)`, `{5}fd510af{0} merge: automation flowchart`, `{5}0d6c8af{0} fix: keep the selection on the Mac`; `P` + `ls`; `{2}Packages{0}   README.md   {2}shellx-ios{0}   {2}shellx-link{0}`; `P` + `swift test`; 17 rows `{3}[n/17] Compiling ShellXLinkCore{0}` for n = 1…17; `{1}✔{0} Executed 412 tests, with 0 failures`; `P` + `clear`; an empty row. Screen rows 0-10: `P` + `git status`; `On branch develop`; `Changes not staged for commit:`; `  {4}modified:   UI/TerminalPane.swift{0}`; `Untracked files:`; `  {4}UI/TerminalKeyBar.swift{0}`; empty; `P` + `echo $TERM`; `xterm-ghostty`; `{9}italic{0} {13}strike{0} {12}link{0} {11}#ff8800{0} {7}inverse{0}`; `P`. |
| `devServer` | 50 × 40, main; cursor (0, 10); ticks every 3 s | Rows 0-9: `{3}> web@0.1.0 dev{0}`; `{3}> dev-server --port 3000{0}`; empty; `  {1}DEV{0} server ready in {5}412 ms{0}`; `  {1}➜{0}  Local:   {12}http://localhost:3000/{0}`; `  {1}➜{0}  Network: {3}use --host to expose{0}`; empty; `{3}10:42:01{0} GET / {1}200{0} in 23ms`; `{3}10:42:02{0} GET /api/status {1}200{0} in 4ms`; `{3}10:42:05{0} GET /favicon.ico {4}404{0} in 2ms`. Ticks: `{3}10:43:00{0} GET /api/status {1}200{0} in 5ms`, `{3}10:43:03{0} GET /api/workspaces {1}200{0} in 12ms`, `{3}10:43:06{0} POST /api/terminal {5}302{0} in 7ms`, `{3}10:43:09{0} GET /missing {4}404{0} in 1ms`. |
| `wide` | 50 × 40, main; cursor (8, 7); prompt `runs(W)` | Rows 0-7: `W` + `cat ghi-chu.txt`; `Tiếng Việt có dấu: ắ ặ ề ổ ữ đ Đ` (precomposed letters); `Dấu rời: e\u{301} a\u{300} o\u{303}` (written with the escapes: combining marks); `中文：终端测试`; `日本語：ターミナル`; `한국어: 터미널`; `Emoji: 🚀 ✅ 👍🏽 🇻🇳 👨‍👩‍👧`; `W`. |
| `vim` | 50 × 40, alternate; cursor (8, 4) block | Rows 0-9: `{10}import{0} SwiftUI`; empty; `{10}struct{0} ContentView: View {`; `    {10}var{0} body: {10}some{0} View {`; `        Text({5}"Xin chào"{0})`; `            .padding()`; `    }`; `}`; empty; `{9}// Mở trong vim trên Mac{0}`. Rows 10-38: `{6}~{0}`. Row 39: `{7}` + `ContentView.swift [+]`, spaces, `5,9`, spaces, `All`, exactly 50 columns, + `{0}`. |
| `htop` | **100** × 30, alternate; cursor hidden (`visible: false`) | Rows 0-3: CPU meters `  {6}1{0}  [` + `{1}` green bars + `{4}` red bars + spaces + `38.2%]` (42 columns from the first space to `]`), then 3 spaces and `{6}Tasks:{0} 214, 1203 thr; 3 running`, `{6}Load average:{0} 1.42 1.37 1.30`, `{6}Uptime:{0} 3 days, 04:12:55`, nothing (CPUs 1-4 at 38.2, 12.0, 51.7, 6.1 %). Row 4: `  {6}Mem{0}[` … `9.81G/16.0G]`; row 5: `  {6}Swp{0}[` … `112M/2.00G]`; row 6 empty; row 7: `{8}    PID USER       PRI  NI  VIRT   RES   SHR S CPU% MEM%   TIME+  Command` padded to 100 columns + `{0}`; rows 8-27: 20 processes in those columns, CPU% falling (commands such as `ShellX`, `claude`, `node`, `swift-build`, `zsh`, `Safari`); row 12 is the selected one, all of it in `{7}` padded to 100 columns; row 28 empty; row 29: `{7}F1{0}Help  {7}F2{0}Setup {7}F3{0}Search{7}F4{0}Filter{7}F5{0}Tree  {7}F6{0}SortBy{7}F7{0}Nice -{7}F8{0}Nice +{7}F9{0}Kill  {7}F10{0}Quit`. |
| `agent` | 50 × 40, alternate; cursor (4, 37) | Row 0 `{6}╭` + 48 × `─` + `╮{0}`; row 1 `{6}│{0} {1}✻{0} Agent đang làm việc ở shellx-ios` padded to column 49 + `{6}│{0}`; row 2 `{6}╰` + 48 × `─` + `╯{0}`; row 4 `{1}●{0} Đọc UI/Terminal/TerminalPane.swift`; row 5 `{1}●{0} Sửa 3 tệp, chạy {5}swift test{0}`; row 6 `  {3}⎿ Executed 128 tests, with 0 failures{0}`; row 8 `Xong phần vẽ terminal. Tiếp theo: bàn phím.`; rows 36-38 a box like rows 0-2 whose middle row is `{6}│{0} > ` padded to column 49 + `{6}│{0}`; row 39 `  {3}Enter gửi · Esc dừng{0}`. |

- [ ] **Step 1: Write the failing tests**

`DemoTerminalScreensTests`:

```swift
func testXterm256() {
    let colors = DemoTerminalScreens.xterm256(base: Array(repeating: "#123456", count: 16))
    XCTAssertEqual(colors.count, 256)
    XCTAssertEqual([colors[16], colors[21], colors[196], colors[231], colors[232], colors[255]],
                   ["#000000", "#0000ff", "#ff0000", "#ffffff", "#080808", "#eeeeee"])
    XCTAssertEqual(DemoTerminalScreens.palette.colors[4], "#60a5fa")
    XCTAssertEqual(DemoTerminalScreens.palette.bg, "#0b0716")
}

func testMarkup() {
    XCTAssertEqual(DemoTerminalScreens.runs("{1}$ {0}ls"), [TerminalRun(text: "$ ", style: 1), TerminalRun(text: "ls")])
    XCTAssertEqual(DemoTerminalScreens.runs("a中e\u{301}🇻🇳{z"),
                   [TerminalRun(text: "a"), TerminalRun(text: "中", width: 2), TerminalRun(text: "e\u{301}", width: 1),
                    TerminalRun(text: "🇻🇳", width: 2), TerminalRun(text: "{z")])
}

func testEveryFixtureSplitsAndAssemblesIntoItself() throws {
    let all: [(String, DemoTerminalFixture)] = [
        ("shell", DemoTerminalScreens.shell), ("devServer", DemoTerminalScreens.devServer), ("wide", DemoTerminalScreens.wide),
        ("vim", DemoTerminalScreens.vim), ("htop", DemoTerminalScreens.htop), ("agent", DemoTerminalScreens.agent),
        ("prompt", DemoTerminalScreens.prompt(cols: 50, rows: 20))]
    for (name, fixture) in all {
        let parts = try TerminalFrameSplitter.parts(of: fixture.snapshot, revision: 1, terminalId: "t")
        var assembler = TerminalFrameAssembler()
        XCTAssertEqual(parts.map { assembler.receive($0) }.last?.frame, fixture.snapshot, name)
        var screen = TerminalScreen()
        screen.apply(fixture.snapshot)
        XCTAssertEqual(screen.cols, fixture.cols, name)
        XCTAssertEqual(screen.alt, fixture.alt, name)
        XCTAssertEqual(screen.historyRows.count, fixture.alt ? 0 : fixture.history.count, name)
        XCTAssertLessThanOrEqual(fixture.screen.count, fixture.rows, name)
        if let prompt = fixture.prompt { XCTAssertEqual(fixture.screen[fixture.cursor.y], prompt, name) }
    }
}

func testTheFixturesHoldWhatTheRenderTestsShow() {
    XCTAssertTrue(DemoTerminalScreens.vim.alt && DemoTerminalScreens.htop.alt && DemoTerminalScreens.agent.alt)
    XCTAssertEqual(DemoTerminalScreens.htop.cols, 100)
    XCTAssertEqual(DemoTerminalScreens.shell.history.count, 30)
    XCTAssertEqual(DemoTerminalScreens.shell.cursor.x, 23)
    let wide = DemoTerminalScreens.wide.screen.flatMap { $0 }
    XCTAssertTrue(wide.contains(TerminalRun(text: "中", width: 2)))
    XCTAssertTrue(wide.contains(TerminalRun(text: "🇻🇳", width: 2)))
    XCTAssertTrue(wide.contains(TerminalRun(text: "e\u{301}", width: 1)))
    XCTAssertEqual(DemoTerminalScreens.devServer.tickInterval, .seconds(3))
    XCTAssertEqual(DemoTerminalScreens.devServer.ticks.count, 4)
}
```

`FakeMacTerminalsTests` (`@MainActor`; `connect` makes a `LinkClient` with `mac.connector(phoneKey: { key }).connect(mac.machine)` for a fresh `NoiseStaticKey()`; `ws(_ ids: String...)` is `LinkWorkspace(workspaceId: "ws-a", title: "a", order: 0, terminals:)` with `LinkTerminal(terminalId: id, title: id, order: index, selected: index == 0)`; every test closes its clients at the end):

```swift
func testWelcomeOffersTerminalViewsAndCreation() async throws {
    let both: Set = [ShellXLink.terminalViewFeature, ShellXLink.terminalCreateFeature]
    let client = try await connect(FakeMac(name: "Mac"))
    XCTAssertTrue(client.hostFeatures.isSuperset(of: both))
    let old = try await connect(FakeMac(name: "Old", servesTerminalViews: false, acceptsTerminalCreate: false))
    XCTAssertTrue(old.hostFeatures.isDisjoint(with: both))
}

func testOpenServesTheFixturesScreen() async throws {
    let mac = FakeMac(name: "Mac")
    await mac.setWorkspaces([ws("t1")])
    await mac.setTerminalFixtures(["t1": DemoTerminalScreens.shell])
    let client = try await connect(mac)
    let reader = TerminalPushReader(client.terminalPushes, terminalId: "t1")
    let opened = try await client.openTerminalView(terminalId: "t1", cols: 50, rows: 40)
    XCTAssertEqual(opened, .ok)
    var expected = TerminalScreen()
    expected.apply(DemoTerminalScreens.shell.snapshot)
    let shown = await eventually { reader.screen.screenText() == expected.screenText() }
    XCTAssertTrue(shown)
    let opens = await mac.terminalViewOpens
    XCTAssertEqual(opens, [FakeMac.TerminalViewSize(terminalId: "t1", cols: 50, rows: 40)])
}

func testAnUnlistedTerminalIsNotFound() async throws {
    let mac = FakeMac(name: "Mac"); await mac.setWorkspaces([ws("t1")])
    let client = try await connect(mac)
    let answer = try await client.openTerminalView(terminalId: "nope", cols: 50, rows: 40)
    XCTAssertEqual(answer, .notFound)
}

func testTypingEchoesOnThePromptLine() async throws {
    let mac = FakeMac(name: "Mac"); await mac.setWorkspaces([ws("t1")])
    let client = try await connect(mac)
    let reader = TerminalPushReader(client.terminalPushes, terminalId: "t1")
    _ = try await client.openTerminalView(terminalId: "t1", cols: 20, rows: 5)
    try await client.sendTerminalInput(terminalId: "t1", units: [.text("ls")])
    try await client.sendTerminalInput(terminalId: "t1", units: [.key(.enter, mods: [])])
    try await client.sendTerminalInput(terminalId: "t1", units: [.text("x"), .key(.backspace, mods: [])])
    try await client.sendTerminalInput(terminalId: "t1", units: [.key(.letter("c"), mods: [.ctrl])])
    let echoed = await eventually { Array(reader.screen.screenText().prefix(3)) == ["$ ls", "$ ^C", "$"] }
    XCTAssertTrue(echoed, "\(reader.screen.screenText())")
    let inputs = await mac.terminalViewInputs("t1")
    XCTAssertEqual(inputs.count, 4)
}

func testCloseResizeAndSnapshotRequestsAreRecorded() async throws {
    // open t1 at 20 × 5; resizeTerminalView 30 × 10; resyncTerminalView; closeTerminalView; then:
    let recorded = await eventually {
        let resizes = await mac.terminalViewResizes, requests = await mac.terminalViewSnapshotRequests("t1")
        let closes = await mac.terminalViewCloses
        return resizes == [FakeMac.TerminalViewSize(terminalId: "t1", cols: 30, rows: 10)] && requests == 1 && closes == ["t1"]
    }
    XCTAssertTrue(recorded)
}

func testCreateAddsATerminalTabToTheWorkspace() async throws {
    let created = try await client.createTerminal(workspaceId: "ws-a")
    XCTAssertEqual(created.outcome, .ok)
    let id = try XCTUnwrap(created.terminalId)
    XCTAssertEqual(id, "ws-a-new-1")
    let list = try await client.workspaces()
    XCTAssertTrue(list.workspaces.first?.terminals.contains { $0.terminalId == id } ?? false)
    let missing = try await client.createTerminal(workspaceId: "nope")
    XCTAssertEqual(missing.outcome, .notFound)
    await mac.setNextTerminalCreateOutcome(.refused)
    let refused = try await client.createTerminal(workspaceId: "ws-a")
    XCTAssertEqual(refused.outcome, .refused); XCTAssertNil(refused.terminalId)
    let creates = await mac.terminalCreates
    XCTAssertEqual(creates, ["ws-a", "nope", "ws-a"])
}

func testEmittedFramesAndEndsReachThePhone() async throws {
    // open t1 at 20 × 5, wait for the prompt, then:
    await mac.emitTerminalFrame("t1", TerminalGridFrame(
        head: TerminalFrameHead(kind: .delta, cols: 20, rows: 5, cursor: TerminalCursor(x: 0, y: 0)),
        lines: [TerminalLine(y: 0, runs: [TerminalRun(text: "hi")])]))
    // eventually reader.screen.screenText().first == "hi"
    await mac.endTerminalView("t1", reason: .gone)
    // eventually reader.pushes.contains(.ended(terminalId: "t1", reason: .gone))
}

func testRefusedAndHeldOpens() async throws {
    await mac.refuseTerminalView("t1", with: .refused)
    let refused = try await client.openTerminalView(terminalId: "t1", cols: 20, rows: 5)
    XCTAssertEqual(refused, .refused)
    await mac.holdTerminalViewOpens()
    let pending = Task { try await client.openTerminalView(terminalId: "t2", cols: 20, rows: 5) }
    // eventually terminalViewOpens.count == 2; then:
    await mac.releaseTerminalViewOpens()
    let opened = try await pending.value
    XCTAssertEqual(opened, .ok)
}

func testTicksAppendLinesWhileTheTerminalIsViewed() async throws {
    let ticking = DemoTerminalFixture(cols: 20, rows: 3, screen: [], cursor: TerminalCursor(x: 0, y: 0),
                                      ticks: [DemoTerminalScreens.runs("tick")], tickInterval: .milliseconds(20))
    await mac.setTerminalFixtures(["t1": ticking])
    // open t1; eventually Array(reader.screen.screenText().prefix(2)) == ["tick", "tick"]
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path shellx-ios/Packages/ShellXAppCore --filter 'DemoTerminalScreensTests|FakeMacTerminalsTests'`
Expected: FAIL, the build stops at `error: cannot find 'DemoTerminalScreens' in scope` (or another new name).

- [ ] **Step 3: Implement** `DemoTerminalScreens.swift`, `FakeMacTerminals.swift`, the `FakeMac` and `FakeMacWorkspaces` additions and `TerminalPushReader`, as the Interfaces and the table say.

- [ ] **Step 4: Run them to see them pass**

Run: the command of Step 2. Expected: `Executed 13 tests, with 0 failures (0 unexpected)`.
Run: `shellx-ios/scripts/dev.sh test core`. Expected: `==> test core: passed`.

- [ ] **Step 5: Commit**

```bash
git add <DEMO_PKG>/DemoTerminalScreens.swift <DEMO_PKG>/FakeMacTerminals.swift <DEMO_PKG>/FakeMac.swift \
  <DEMO_PKG>/FakeMacWorkspaces.swift shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/Support/TerminalTestSupport.swift \
  shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/DemoTerminalScreensTests.swift \
  shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/FakeMacTerminalsTests.swift
git commit -m "feat(shellx-ios): fake Mac terminals and demo terminal screens"
```

---

### Task 2: Terminal views through the machine hub

**Files:**
- Create: `Core/Terminal/TerminalLink.swift`, `Core/Link/MachineHub+Terminal.swift`
- Modify: `Core/Link/MachineEvent.swift` (one case), `Core/Link/MachineConnection.swift` (doc 9-18, `read(_:)` 204-229), `Core/Diagnostics/LatencyLog.swift` (`LatencyMetric` 5-20)
- Modify: `Core/Link/MachineHub.swift`: `latency` (line 37), `withLink` (789) and `workspaceCommand` (806) drop `private`; a stored `@ObservationIgnored var terminalSubscribers: [UUID: AsyncStream<TerminalHubEvent>.Continuation] = [:]` after `stateSubscribers` (line 51); `stopAll()` (273-289) finishes it; `apply(_:from:to:)` (647-680) handles `.terminal` and publishes `.state`; `revoke(_:)` (752-760) and `detachAll()` (768-779) publish the states they set
- Modify: `CoreTests/Support/AsyncTestSupport.swift` (`EventLog.add`, 152-168: count `.terminal`), `CoreTests/Support/TerminalTestSupport.swift` (`Collector`)
- Test: create `CoreTests/MachineHubTerminalTests.swift`

**Interfaces:**
- Consumes: 2A's `LinkClient` terminal API and `TerminalViewPush`; Task 1's `FakeMac` terminal API.
- Produces:

```swift
// TerminalLink.swift
/// What the hub tells terminal pages, in the order it took it from the Macs.
public enum TerminalHubEvent: Equatable, Sendable {
    /// A push of the Mac's live session (`LinkClient.terminalPushes`).
    case push(machineID: String, TerminalViewPush)
    /// The Mac's link state changed; `.online` comes again after every reconnect, and a view opened before it is gone.
    case state(machineID: String, MachineLinkState)
}
/// How a `terminal.view.open` went.
public enum TerminalOpenResult: Equatable, Sendable {
    case outcome(TerminalViewOpenOutcome)
    /// Nothing was sent: the Mac is not online, or did not list `terminal_view`.
    case notSent
    /// Sent, but no answer came: the session ended or the call timed out.
    case noAnswer
}
/// The hub as a terminal page uses it. `MachineHub` is the real one; tests script one.
@MainActor public protocol TerminalLink: AnyObject {
    func terminalEvents() -> AsyncStream<TerminalHubEvent>
    func isOnline(_ machineID: String) -> Bool
    func supportsTerminalView(_ machineID: String) -> Bool
    func openTerminalView(machineID: String, terminalId: String, cols: Int, rows: Int) async -> TerminalOpenResult
    func closeTerminalView(machineID: String, terminalId: String) async
    func sendTerminalInput(machineID: String, terminalId: String, units: [TerminalInputUnit]) async
    func resizeTerminalView(machineID: String, terminalId: String, cols: Int, rows: Int) async
    func resyncTerminalView(machineID: String, terminalId: String) async
    func recordLatency(_ metric: LatencyMetric, _ duration: Duration)
}

// MachineEvent, after `chatReset`
/// A terminal push of the live session (`LinkClient.terminalPushes`), in order with the other events.
case terminal(TerminalViewPush)

// MachineHub+Terminal.swift
extension MachineHub: TerminalLink { /* every requirement above */ }
extension MachineHub {
    /// True when the Mac listed `terminal_create` when it was last online (the ＋ chip).
    public func supportsTerminalCreate(_ machineID: String) -> Bool
    /// Opens a terminal tab in the workspace on its Mac (`terminal.create`); `terminalId` only with `.ok`. Sent once, like the
    /// workspace commands: `.offline` and nothing sent when the Mac is not online, `.failed` without `terminal_create`,
    /// `.unknown` when the answer was lost.
    public func createTerminal(_ ref: WorkspaceRef) async -> (result: WorkspaceCommandResult, terminalId: String?)
}

// LatencyMetric, after `firstWord`
/// Showing a terminal (a chip shown, or the view opened again) to its first screen (mobile terminal spec S2 §2 with the
/// workspaces spec §2.2, criterion 3: p95 under 1 s).
case terminalFirstScreen
/// Typing in a terminal to the next frame of it (criterion 4: p95 under 300 ms).
case terminalKeyEcho
/// Assembling and applying one terminal frame on the main actor (criterion 5: a flood never stalls the app; p95 under 16 ms).
case terminalFrameApply

// CoreTests/Support/TerminalTestSupport.swift
/// Keeps every element of `stream` as it arrives.
final class Collector<Element: Sendable>: @unchecked Sendable {
    init(_ stream: AsyncStream<Element>)
    var items: [Element] { get }
}
```

Behaviour:
- `terminalEvents()` is multicast like `chatUpdates()` (a subscriber is dropped when its reader stops; nothing is kept for a later one). `apply` publishes `.push(machineID: model.id, push)` for `.terminal(push)` and, after setting `model.state` in the `.state` arm, `.state(machineID: model.id, state)`. `revoke(_:)` publishes `.state(id, .revoked)`; `detachAll()` publishes `.state(id, .reconnecting)` for each Mac it moves from `.online`. `stopAll()` finishes every terminal subscriber.
- `isOnline` is `state == .online`; `supportsTerminalView` and `supportsTerminalCreate` read `hostFeatures` like `supportsTerminalClose(_:)`.
- `openTerminalView`: a Mac not online, or without `terminal_view` → `.notSent`, nothing sent. Otherwise through `withLink`: the outcome → `.outcome(_)`; `LinkCallError` → `.notSent`; `LinkClientError.remote` → `.outcome(.failed)`; any other error → `.noAnswer`.
- `closeTerminalView`, `sendTerminalInput`, `resizeTerminalView`, `resyncTerminalView`: the same guard (nothing sent); errors are swallowed and logged as `terminal_send_failed`, a `TerminalInputError` as `terminal_input_refused` (codes only).
- `createTerminal` runs through `workspaceCommand(ref.machineID, feature: ShellXLink.terminalCreateFeature)`; the body unpacks `client.createTerminal(workspaceId:)` into `WorkspaceCommandResult(outcome:)` and keeps the id (for example in a small lock-protected box) only when the outcome is `.ok`.
- `recordLatency` → `latency.record(_:_:)`.
- `MachineConnection.read(_:)` gains a fifth child task: `for await push in client.terminalPushes { output.yield(.terminal(push)) }` (read even when no page shows a terminal: the client buffers without bound). Update the type's doc ("four streams" → five).

- [ ] **Step 1: Write the failing tests** in `MachineHubTerminalTests` (`@MainActor`; `makeMac(servesTerminalViews:acceptsTerminalCreate:)` makes a `FakeMac` with `ws-a` holding `t1` and `t2`; each test makes `let rig = try await HubRig.make([mac], in: self)`, checks `await rig.online(sessions: 0)`, and uses `id = mac.machine.machineID`):

```swift
func testHubOffersTerminalsOnlyWhenTheMacDoes() async throws {
    // new Mac:
    XCTAssertTrue(rig.hub.isOnline(id)); XCTAssertTrue(rig.hub.supportsTerminalView(id)); XCTAssertTrue(rig.hub.supportsTerminalCreate(id))
    // a Mac made with (servesTerminalViews: false, acceptsTerminalCreate: false): both false
}

func testPushesArriveInOrderAfterTheOpen() async throws {
    let events = Collector(rig.hub.terminalEvents())
    let answer = await rig.hub.openTerminalView(machineID: id, terminalId: "t1", cols: 50, rows: 20)
    XCTAssertEqual(answer, .outcome(.ok))
    let pushes = { events.items.compactMap { event -> TerminalViewPush? in
        if case let .push(machine, push) = event, machine == id { return push }; return nil } }
    let framed = await eventually { pushes().contains { if case .frame(terminalId: "t1", _) = $0 { return true }; return false } }
    XCTAssertTrue(framed)
    XCTAssertEqual(pushes().first, .opened(terminalId: "t1"))
    let opens = await mac.terminalViewOpens
    XCTAssertEqual(opens, [FakeMac.TerminalViewSize(terminalId: "t1", cols: 50, rows: 20)])
}

func testInputResizeResyncAndCloseReachTheMac() async throws {
    _ = await rig.hub.openTerminalView(machineID: id, terminalId: "t1", cols: 50, rows: 20)
    await rig.hub.sendTerminalInput(machineID: id, terminalId: "t1", units: [.text("ls")])
    await rig.hub.resizeTerminalView(machineID: id, terminalId: "t1", cols: 60, rows: 30)
    await rig.hub.resyncTerminalView(machineID: id, terminalId: "t1")
    await rig.hub.closeTerminalView(machineID: id, terminalId: "t1")
    let reached = await eventually {
        let inputs = await mac.terminalViewInputs("t1"), closes = await mac.terminalViewCloses
        let requests = await mac.terminalViewSnapshotRequests("t1"), resizes = await mac.terminalViewResizes
        return inputs == [[.text("ls")]] && closes == ["t1"] && requests == 1
            && resizes == [FakeMac.TerminalViewSize(terminalId: "t1", cols: 60, rows: 30)]
    }
    XCTAssertTrue(reached)
}

func testNothingIsSentWithoutTheFeature() async throws {
    // mac made with (servesTerminalViews: false, acceptsTerminalCreate: false)
    let before = mac.phoneFrameCount
    let answer = await rig.hub.openTerminalView(machineID: id, terminalId: "t1", cols: 50, rows: 20)
    XCTAssertEqual(answer, .notSent)
    await rig.hub.sendTerminalInput(machineID: id, terminalId: "t1", units: [.text("x")])
    await rig.hub.closeTerminalView(machineID: id, terminalId: "t1")
    let made = await rig.hub.createTerminal(WorkspaceRef(machineID: id, workspaceId: "ws-a"))
    XCTAssertEqual(made.result, .failed); XCTAssertNil(made.terminalId)
    XCTAssertEqual(mac.phoneFrameCount, before)
}

func testNothingIsSentToAMacThatIsNotOnline() async throws {
    XCTAssertFalse(rig.hub.isOnline("mac-nope"))
    let answer = await rig.hub.openTerminalView(machineID: "mac-nope", terminalId: "t1", cols: 50, rows: 20)
    XCTAssertEqual(answer, .notSent)
    let made = await rig.hub.createTerminal(WorkspaceRef(machineID: "mac-nope", workspaceId: "ws-a"))
    XCTAssertEqual(made.result, .offline)
}

func testStateChangesReachTerminalSubscribers() async throws {
    let events = Collector(rig.hub.terminalEvents())
    await mac.dropLiveSessions()
    let back = await eventually {
        rig.backoff.release()
        let states = events.items.compactMap { event -> MachineLinkState? in
            if case let .state(machine, state) = event, machine == id { return state }; return nil }
        return states.contains(.reconnecting) && states.last == .online
    }
    XCTAssertTrue(back)
}

func testCreateTerminalOutcomes() async throws {
    let made = await rig.hub.createTerminal(WorkspaceRef(machineID: id, workspaceId: "ws-a"))
    XCTAssertEqual(made.result, .ok(workspaceId: nil))
    let newId = try XCTUnwrap(made.terminalId)
    let listed = await eventually {
        rig.hub.machines.first?.workspaces.workspace("ws-a")?.terminals.contains { $0.terminalId == newId } ?? false
    }
    XCTAssertTrue(listed)
    let missing = await rig.hub.createTerminal(WorkspaceRef(machineID: id, workspaceId: "nope"))
    XCTAssertEqual(missing.result, .notFound)
    await mac.setNextTerminalCreateOutcome(.refused)
    let refused = await rig.hub.createTerminal(WorkspaceRef(machineID: id, workspaceId: "ws-a"))
    XCTAssertEqual(refused.result, .refused); XCTAssertNil(refused.terminalId)
    let creates = await mac.terminalCreates
    XCTAssertEqual(creates, ["ws-a", "nope", "ws-a"])
}

func testStopAllFinishesTheTerminalStream() async throws {
    let stream = rig.hub.terminalEvents()
    let finished = Task { for await _ in stream {}; return true }
    await rig.hub.stopAll()
    let done = await finished.value
    XCTAssertTrue(done)
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path shellx-ios/Packages/ShellXAppCore --filter MachineHubTerminalTests`
Expected: FAIL, `error: cannot find 'TerminalHubEvent' in scope` (or `value of type 'MachineHub' has no member 'terminalEvents'`).

- [ ] **Step 3: Implement** the files and changes listed, as the Interfaces and Behaviour say.

- [ ] **Step 4: Run them to see them pass**

Run: the command of Step 2. Expected: `Executed 8 tests, with 0 failures (0 unexpected)`.
Run: `shellx-ios/scripts/dev.sh test core`. Expected: `==> test core: passed` (`MachineConnectionTests` and `MachineHubTests` stay green).

- [ ] **Step 5: Commit**

```bash
git add shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Terminal/TerminalLink.swift \
  shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Link \
  shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Diagnostics/LatencyLog.swift \
  shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/Support \
  shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/MachineHubTerminalTests.swift
git commit -m "feat(shellx-ios): terminal views through the machine hub"
```

---

### Task 3: Typing, input batching and hardware keys

**Files:**
- Create: `Core/Terminal/TerminalTyping.swift`, `Core/Terminal/TerminalInputBatcher.swift`, `Core/Terminal/TerminalHardwareKeys.swift`
- Test: create `CoreTests/TerminalTypingTests.swift`, `CoreTests/TerminalInputBatcherTests.swift`, `CoreTests/TerminalHardwareKeysTests.swift`

**Interfaces:**
- Consumes: 2A's `TerminalInputUnit`, `TerminalKey`, `TerminalModifier`, `TerminalInputCheck`, `ShellXLink.terminalMaxInputUnits`, `.terminalMaxTextBytes`, `.terminalMaxPasteBytes`, `.terminalMaxScrollLines`.
- Produces:

```swift
/// What the keyboard composes and what it sends (S2 §3.6). Marked text (an input method's word in progress, Telex or VNI)
/// stays on the phone; only committed text goes out. Ctrl, tapped on the key bar, applies to the next key or letter.
public struct TerminalTyping: Equatable, Sendable {
    public private(set) var markedText: String
    public private(set) var ctrlLatched: Bool
    public init(markedText: String = "", ctrlLatched: Bool = false)
    public mutating func toggleCtrl()
    public mutating func insert(_ text: String) -> [TerminalInputUnit]       // UITextInput.insertText
    public mutating func setMarked(_ text: String) -> [TerminalInputUnit]    // UITextInput.setMarkedText
    public mutating func unmark() -> [TerminalInputUnit]                     // UITextInput.unmarkText
    public mutating func deleteBackward() -> [TerminalInputUnit]             // UIKeyInput.deleteBackward
    public mutating func key(_ key: TerminalKey, mods: [TerminalModifier] = []) -> [TerminalInputUnit]   // key bar, hardware key
}

public enum TerminalInputBatcher {
    /// `units` as `terminal.view.input` messages, in order. Every message passes `TerminalInputCheck.check`: 1 to 64 units,
    /// typed text at most 4 096 UTF-8 bytes in all, pasted text at most 16 384; a longer `text` or `paste` unit is cut into
    /// pieces at Character boundaries (a Character longer than the limit at scalar boundaries).
    public static func messages(_ units: [TerminalInputUnit]) -> [[TerminalInputUnit]]
    /// Pasted text as one `paste` unit, with every control character but tab, line feed and carriage return dropped; [] when
    /// nothing is left.
    public static func pasteUnits(_ text: String) -> [TerminalInputUnit]
    /// The largest paste the phone sends: 16 messages of 16 384 bytes. The host keeps at most 64 queued input messages
    /// (plan 2A), so a longer paste could silently lose its tail; R12 refuses it instead and the pane shows
    /// `terminal.paste.tooLarge` (en "That paste is too large to send (256 KB at most).", vi "Nội dung dán quá lớn để gửi (tối đa 256 KB).").
    public static let maxPasteBytes = 262_144
    /// True when the cleaned paste (as `pasteUnits` would send it) is at most `maxPasteBytes` UTF-8 bytes.
    public static func pasteFits(_ text: String) -> Bool
    /// A scroll of `lines` (either sign) as units of at most 100 lines each, in the same direction; [] for 0.
    public static func scrollUnits(_ lines: Int) -> [TerminalInputUnit]
}

public struct TerminalHardwareModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int)
    public static let shift = TerminalHardwareModifiers(rawValue: 1)
    public static let control = TerminalHardwareModifiers(rawValue: 2)
    public static let alternate = TerminalHardwareModifiers(rawValue: 4)
    public static let command = TerminalHardwareModifiers(rawValue: 8)
}
public enum TerminalHardwareAction: Equatable, Sendable {
    case send(TerminalKey, mods: [TerminalModifier])
    /// Leave it to UIKit: text input, the input method, the system's ⌘ shortcuts.
    case system
}
public enum TerminalHardwareKeys {
    /// `usage` is the USB HID keyboard usage (`UIKey.keyCode.rawValue`); `composing` is true while marked text exists.
    public static func action(usage: Int, modifiers: TerminalHardwareModifiers, composing: Bool) -> TerminalHardwareAction
}
/// The key bar's keys, in its order (`allCases`).
public enum TerminalBarKey: CaseIterable, Sendable {
    case escape, tab, ctrl, left, up, down, right
    /// What it sends; nil for ctrl, which latches for the next key instead.
    public var key: TerminalKey? { get }
}
```

`TerminalTyping` (the algorithm, which the tests pin but do not determine everywhere):

```swift
public mutating func insert(_ text: String) -> [TerminalInputUnit] {
    let committing = !markedText.isEmpty            // the input method's word becomes this text
    markedText = ""
    guard !committing, ctrlLatched, let first = text.first else { return Self.plain(text) }
    ctrlLatched = false
    return Self.chord(first) + Self.plain(String(text.dropFirst()))
}
public mutating func setMarked(_ text: String) -> [TerminalInputUnit] {
    if markedText.isEmpty, ctrlLatched, let first = text.first {   // ctrl takes the first letter of a new composition
        ctrlLatched = false
        return Self.chord(first)                     // markedText stays empty; the surface resets the keyboard (Task 9)
    }
    markedText = text
    return []
}
public mutating func unmark() -> [TerminalInputUnit] {
    defer { markedText = "" }
    return Self.plain(markedText)                    // committing never takes the ctrl latch
}
public mutating func deleteBackward() -> [TerminalInputUnit] {
    if !markedText.isEmpty { markedText.removeLast(); return [] }
    return key(.backspace)
}
public mutating func key(_ key: TerminalKey, mods: [TerminalModifier] = []) -> [TerminalInputUnit] {
    var units = unmark()                             // the word in progress goes first
    var mods = mods
    if ctrlLatched {
        ctrlLatched = false
        if !mods.contains(.ctrl) { mods.insert(.ctrl, at: 0) }
    }
    units.append(.key(key, mods: mods))
    return units
}
// plain(_:): per Character: "\n", "\r", "\r\n" → .key(.enter, mods: []); "\t" → .key(.tab, mods: []); otherwise its scalars
//   minus U+0000-001F, U+007F, U+0080-009F join the current .text unit (a stretch between keys is one unit; empty → none).
// chord(_:): an ASCII letter a-z or A-Z → .key(.letter(lowercased), mods: [.ctrl]); " " → .key(.space, mods: [.ctrl]);
//   a line break → .key(.enter, mods: [.ctrl]); "\t" → .key(.tab, mods: [.ctrl]); anything else → plain(String(character)).
```

`TerminalHardwareKeys.action` (the mapping; HID usages are fixed by the USB HID keyboard page, and `UIKeyboardHIDUsage` uses the same values):

```swift
if composing || modifiers.contains(.command) { return .system }
var mods: [TerminalModifier] = []
if modifiers.contains(.control) { mods.append(.ctrl) }
if modifiers.contains(.alternate) { mods.append(.alt) }
if modifiers.contains(.shift) { mods.append(.shift) }
let named: [Int: TerminalKey] = [0x29: .escape, 0x2B: .tab, 0x4F: .right, 0x50: .left, 0x51: .down, 0x52: .up,
                                 0x4A: .home, 0x4B: .pageUp, 0x4C: .delete, 0x4D: .end, 0x4E: .pageDown]
if let key = named[usage] { return .send(key, mods: mods) }
let control = modifiers.contains(.control), alternate = modifiers.contains(.alternate)
switch usage {
case 0x04...0x1D where control: return .send(.letter(Character(Unicode.Scalar(UInt8(0x61 + usage - 0x04)))), mods: mods)
case 0x28 where control || alternate: return .send(.enter, mods: mods)        // Return
case 0x2A where control || alternate: return .send(.backspace, mods: mods)    // Delete (backspace)
case 0x2C where control: return .send(.space, mods: mods)
default: return .system   // letters, Return, Backspace, Space, alt+letter, F-keys: the text system or nothing
}
```

- [ ] **Step 1: Write the failing tests**

`TerminalTypingTests`:

```swift
func testCommittedTextIsSentAndMarkedTextIsNot() {
    var typing = TerminalTyping()
    XCTAssertEqual(typing.setMarked("v"), []); XCTAssertEqual(typing.setMarked("vi"), []); XCTAssertEqual(typing.setMarked("việ"), [])
    XCTAssertEqual(typing.markedText, "việ")
    XCTAssertEqual(typing.insert("việt"), [.text("việt")])
    XCTAssertEqual(typing.markedText, "")
}
func testUnmarkCommitsWhatWasComposed() {
    var typing = TerminalTyping()
    _ = typing.setMarked("Tiế")
    XCTAssertEqual(typing.unmark(), [.text("Tiế")]); XCTAssertEqual(typing.unmark(), [])
}
func testBackspaceWhileComposingStaysOnThePhone() {
    var typing = TerminalTyping()
    _ = typing.setMarked("việ")
    XCTAssertEqual(typing.deleteBackward(), []); XCTAssertEqual(typing.markedText, "vi")
    _ = typing.setMarked("")
    XCTAssertEqual(typing.deleteBackward(), [.key(.backspace, mods: [])])
}
func testLineBreaksAndTabsAreKeys() {
    var typing = TerminalTyping()
    XCTAssertEqual(typing.insert("ls\n"), [.text("ls"), .key(.enter, mods: [])])
    XCTAssertEqual(typing.insert("a\r\nb\tc"), [.text("a"), .key(.enter, mods: []), .text("b"), .key(.tab, mods: []), .text("c")])
    XCTAssertEqual(typing.insert("\r"), [.key(.enter, mods: [])])
}
func testOtherControlCharactersAreDropped() {
    var typing = TerminalTyping()
    XCTAssertEqual(typing.insert("a\u{1b}[31mb\u{7f}\u{85}"), [.text("a[31mb")])
    XCTAssertEqual(typing.insert("\u{1b}"), [])
}
func testCtrlLatchesForTheNextKeyOnly() {
    var typing = TerminalTyping()
    typing.toggleCtrl(); XCTAssertTrue(typing.ctrlLatched)
    XCTAssertEqual(typing.insert("c"), [.key(.letter("c"), mods: [.ctrl])]); XCTAssertFalse(typing.ctrlLatched)
    XCTAssertEqual(typing.insert("c"), [.text("c")])
    typing.toggleCtrl(); typing.toggleCtrl(); XCTAssertFalse(typing.ctrlLatched)
}
func testCtrlWithAnUppercaseLetterSpaceOrReturn() {
    var typing = TerminalTyping()
    typing.toggleCtrl(); XCTAssertEqual(typing.insert("C"), [.key(.letter("c"), mods: [.ctrl])])
    typing.toggleCtrl(); XCTAssertEqual(typing.insert(" "), [.key(.space, mods: [.ctrl])])
    typing.toggleCtrl(); XCTAssertEqual(typing.insert("\n"), [.key(.enter, mods: [.ctrl])])
}
func testCtrlWithAnyOtherCharacterTypesItPlain() {
    var typing = TerminalTyping()
    typing.toggleCtrl(); XCTAssertEqual(typing.insert("1x"), [.text("1x")]); XCTAssertFalse(typing.ctrlLatched)
    typing.toggleCtrl(); XCTAssertEqual(typing.insert("đ"), [.text("đ")])
}
func testCtrlAppliesToTheKeyBarAndHardwareKeys() {
    var typing = TerminalTyping()
    typing.toggleCtrl(); XCTAssertEqual(typing.key(.left), [.key(.left, mods: [.ctrl])])
    XCTAssertEqual(typing.key(.left), [.key(.left, mods: [])])
    typing.toggleCtrl(); XCTAssertEqual(typing.key(.letter("c"), mods: [.ctrl]), [.key(.letter("c"), mods: [.ctrl])])
}
func testCtrlLatchedTakesTheFirstLetterOfANewComposition() {
    var typing = TerminalTyping()
    typing.toggleCtrl()
    XCTAssertEqual(typing.setMarked("c"), [.key(.letter("c"), mods: [.ctrl])])
    XCTAssertEqual(typing.markedText, ""); XCTAssertFalse(typing.ctrlLatched)
}
func testCtrlTappedWhileComposingWaitsForTheNextKey() {   // Review Focus 2
    var typing = TerminalTyping()
    _ = typing.setMarked("việ"); typing.toggleCtrl()
    XCTAssertEqual(typing.setMarked("việt"), []); XCTAssertEqual(typing.markedText, "việt")
    XCTAssertEqual(typing.unmark(), [.text("việt")]); XCTAssertTrue(typing.ctrlLatched)
    XCTAssertEqual(typing.key(.letter("c")), [.key(.letter("c"), mods: [.ctrl])])
    _ = typing.setMarked("viê"); typing.toggleCtrl()
    XCTAssertEqual(typing.insert("việt"), [.text("việt")], "committing a word is never a ctrl chord")
    XCTAssertTrue(typing.ctrlLatched)
}
func testAKeyWhileComposingCommitsTheWordFirst() {   // Review Focus 2
    var typing = TerminalTyping()
    _ = typing.setMarked("việ")
    XCTAssertEqual(typing.key(.left), [.text("việ"), .key(.left, mods: [])])
    XCTAssertEqual(typing.markedText, "")
}
```

`TerminalInputBatcherTests`:

```swift
func testSmallInputIsOneMessage() {
    XCTAssertEqual(TerminalInputBatcher.messages([.text("ls"), .key(.enter, mods: [])]), [[.text("ls"), .key(.enter, mods: [])]])
}
func testEveryMessagePassesTheProtocolCheck() throws {
    let units: [TerminalInputUnit] = Array(repeating: .key(.tab, mods: []), count: 100)
        + [.text(String(repeating: "é", count: 10_000))] + TerminalInputBatcher.pasteUnits(String(repeating: "a", count: 40_000))
    let messages = TerminalInputBatcher.messages(units)
    for message in messages { XCTAssertNoThrow(try TerminalInputCheck.check(message)) }
    let typed = messages.flatMap { $0 }.compactMap { if case let .text(t) = $0 { return t }; return nil }.joined()
    XCTAssertEqual(typed, String(repeating: "é", count: 10_000))
}
func testTypedTextSplitsAt4096UTF8Bytes() {
    let messages = TerminalInputBatcher.messages([.text(String(repeating: "é", count: 3000))])
    XCTAssertEqual(messages, [[.text(String(repeating: "é", count: 2048))], [.text(String(repeating: "é", count: 952))]])
}
func testNoMessageHoldsMoreThan64Units() {
    XCTAssertEqual(TerminalInputBatcher.messages(Array(repeating: .key(.tab, mods: []), count: 100)).map(\.count), [64, 36])
}
func testAClusterIsNeverCut() {
    let family = "👨‍👩‍👧‍👦"                                        // 25 UTF-8 bytes, one Character
    let text = String(repeating: family, count: 200)
    let pieces = TerminalInputBatcher.messages([.text(text)]).flatMap { $0 }.compactMap { unit -> String? in
        if case let .text(t) = unit { return t }; return nil }
    XCTAssertEqual(pieces.joined(), text)
    XCTAssertTrue(pieces.allSatisfy { $0.utf8.count == $0.count * 25 }, "every piece is whole families")
}
func testPasteLimitIs256KiB() {
    XCTAssertEqual(TerminalInputBatcher.maxPasteBytes, 262_144)
    XCTAssertTrue(TerminalInputBatcher.pasteFits(String(repeating: "a", count: 262_144)))
    XCTAssertFalse(TerminalInputBatcher.pasteFits(String(repeating: "a", count: 262_145)))
    XCTAssertTrue(TerminalInputBatcher.pasteFits(String(repeating: "a", count: 262_144) + "\u{1b}"))   // dropped controls do not count
}

func testPasteSplitsAt16384BytesAndDropsWhatTheProtocolRefuses() {
    XCTAssertEqual(TerminalInputBatcher.pasteUnits("a\u{1b}[201~b\r\n\tc\u{7f}"), [.paste("a[201~b\r\n\tc")])
    XCTAssertEqual(TerminalInputBatcher.pasteUnits(""), []); XCTAssertEqual(TerminalInputBatcher.pasteUnits("\u{1b}"), [])
    let messages = TerminalInputBatcher.messages(TerminalInputBatcher.pasteUnits(String(repeating: "a", count: 20_000)))
    XCTAssertEqual(messages, [[.paste(String(repeating: "a", count: 16_384))], [.paste(String(repeating: "a", count: 3_616))]])
}
func testScrollUnitsHoldAtMost100Lines() {
    XCTAssertEqual(TerminalInputBatcher.scrollUnits(250), [.scroll(lines: 100), .scroll(lines: 100), .scroll(lines: 50)])
    XCTAssertEqual(TerminalInputBatcher.scrollUnits(-3), [.scroll(lines: -3)])
    XCTAssertEqual(TerminalInputBatcher.scrollUnits(0), [])
}
```

`TerminalHardwareKeysTests` (`func a(_ usage: Int, _ modifiers: TerminalHardwareModifiers = [], composing: Bool = false)` calls `TerminalHardwareKeys.action`):

```swift
func testNamedKeysAreSentWithTheirModifiers() {
    XCTAssertEqual(a(0x29), .send(.escape, mods: [])); XCTAssertEqual(a(0x2B), .send(.tab, mods: []))
    XCTAssertEqual(a(0x2B, [.shift]), .send(.tab, mods: [.shift]))
    XCTAssertEqual([a(0x50), a(0x4F), a(0x52), a(0x51)],
                   [.send(.left, mods: []), .send(.right, mods: []), .send(.up, mods: []), .send(.down, mods: [])])
    XCTAssertEqual(a(0x50, [.alternate]), .send(.left, mods: [.alt]))
    XCTAssertEqual(a(0x52, [.control, .shift]), .send(.up, mods: [.ctrl, .shift]))
    XCTAssertEqual([a(0x4A), a(0x4D), a(0x4B), a(0x4E), a(0x4C)],
                   [.send(.home, mods: []), .send(.end, mods: []), .send(.pageUp, mods: []), .send(.pageDown, mods: []),
                    .send(.delete, mods: [])])
}
func testCtrlLettersAreKeys() {
    XCTAssertEqual(a(0x06, [.control]), .send(.letter("c"), mods: [.ctrl]))
    XCTAssertEqual(a(0x04, [.control, .shift]), .send(.letter("a"), mods: [.ctrl, .shift]))
    XCTAssertEqual(a(0x1D, [.control]), .send(.letter("z"), mods: [.ctrl]))
}
func testTextReturnBackspaceAndSpaceGoThroughTheTextSystem() {
    for (usage, modifiers) in [(0x06, []), (0x06, [.shift]), (0x06, [.alternate]), (0x28, []), (0x2A, []), (0x2C, [])]
        as [(Int, TerminalHardwareModifiers)] {
        XCTAssertEqual(a(usage, modifiers), .system, "\(usage)")
    }
}
func testReturnBackspaceAndSpaceWithModifiersAreKeys() {
    XCTAssertEqual(a(0x28, [.control]), .send(.enter, mods: [.ctrl]))
    XCTAssertEqual(a(0x2A, [.alternate]), .send(.backspace, mods: [.alt]))
    XCTAssertEqual(a(0x2C, [.control]), .send(.space, mods: [.ctrl]))
}
func testCommandShortcutsAndUnknownKeysGoToTheSystem() {
    XCTAssertEqual(a(0x19, [.command]), .system); XCTAssertEqual(a(0x29, [.command]), .system); XCTAssertEqual(a(0x3A), .system)
}
func testComposingHandsEveryKeyToTheSystem() {   // Review Focus 2
    for usage in [0x29, 0x50, 0x2B] { XCTAssertEqual(a(usage, composing: true), .system) }
    XCTAssertEqual(a(0x06, [.control], composing: true), .system)
}
func testKeyBarOrderAndKeys() {
    XCTAssertEqual(TerminalBarKey.allCases, [.escape, .tab, .ctrl, .left, .up, .down, .right])
    XCTAssertEqual(TerminalBarKey.allCases.map(\.key), [.escape, .tab, nil, .left, .up, .down, .right])
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path shellx-ios/Packages/ShellXAppCore --filter 'TerminalTypingTests|TerminalInputBatcherTests|TerminalHardwareKeysTests'`
Expected: FAIL, `error: cannot find 'TerminalTyping' in scope`.

- [ ] **Step 3: Implement** the three files (bodies above for `TerminalTyping` and `TerminalHardwareKeys`; the batcher fills one message greedily, starting a new one when a unit would pass a limit).

- [ ] **Step 4: Run them to see them pass**

Run: the command of Step 2. Expected: `Executed 27 tests, with 0 failures (0 unexpected)`.

- [ ] **Step 5: Commit**

```bash
git add shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Terminal/TerminalTyping.swift \
  shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Terminal/TerminalInputBatcher.swift \
  shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Terminal/TerminalHardwareKeys.swift \
  shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/TerminalTypingTests.swift \
  shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/TerminalInputBatcherTests.swift \
  shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/TerminalHardwareKeysTests.swift
git commit -m "feat(shellx-ios): terminal typing, input batching and hardware keys"
```

---

### Task 4: Geometry, zoom and colours

**Files:**
- Create: `Core/Terminal/TerminalGeometry.swift`, `Core/Terminal/TerminalColors.swift`
- Test: create `CoreTests/TerminalGeometryTests.swift` (classes `TerminalGeometryTests` and `TerminalZoomTests`), `CoreTests/TerminalColorsTests.swift`

**Interfaces:**
- Consumes: 2A's `TerminalCellStyle`, `TerminalAttribute`, `TerminalPalette`.
- Produces:

```swift
public enum TerminalGeometry {
    public static let padding: CGFloat = 4
    public static let maxZoom: CGFloat = 2
    /// The grid the phone asks for: what fits `viewport` at the default font, whose cell is `cell`; at least 1 × 1.
    public static func phoneGrid(viewport: CGSize, cell: CGSize) -> (cols: Int, rows: Int)
    /// The scale that fits `cols` columns into `viewportWidth`; 1 when they fit already (never larger than 1).
    public static func fitScale(cols: Int, cell: CGSize, viewportWidth: CGFloat) -> CGFloat
    /// Whole lines of a vertical pan on the alternate screen: `carry + translation` over `lineHeight × scale`, truncated toward
    /// zero (positive for a finger moving down, toward older content); the rest carries over.
    public static func scrollLines(translation: CGFloat, carry: CGFloat, lineHeight: CGFloat, scale: CGFloat) -> (lines: Int, carry: CGFloat)
}
/// The user's pinch over a grid: nil follows the fit scale; a grid with other columns goes back to it.
public struct TerminalZoom: Equatable, Sendable {
    public private(set) var zoom: CGFloat?
    public init()
    public mutating func gridChanged(cols: Int)          // remembers `cols`; a different value than the last sets zoom to nil
    public mutating func pinch(to zoom: CGFloat, fit: CGFloat)   // stores min(max(zoom, fit), TerminalGeometry.maxZoom)
    public func scale(fit: CGFloat) -> CGFloat           // min(max(zoom ?? fit, fit), TerminalGeometry.maxZoom)
}

public struct TerminalRGB: Hashable, Sendable {
    public var red: UInt8, green: UInt8, blue: UInt8
    public init(red: UInt8, green: UInt8, blue: UInt8)
}
public struct TerminalResolvedStyle: Hashable, Sendable {
    public var foreground: TerminalRGB
    /// Nil: the default background, which the canvas has painted already.
    public var background: TerminalRGB?
    public var bold: Bool, italic: Bool, underline: Bool, strike: Bool, overline: Bool
    /// False for `invisible`: only the background is drawn.
    public var drawsText: Bool
}
public enum TerminalColors {
    /// "#rrggbb" in either case; nil otherwise.
    public static func rgb(_ hex: String) -> TerminalRGB?
    public static func foreground(_ palette: TerminalPalette) -> TerminalRGB   // palette.fg, else #ffffff
    public static func background(_ palette: TerminalPalette) -> TerminalRGB   // palette.bg, else #000000
    public static func cursor(_ palette: TerminalPalette) -> TerminalRGB       // palette.cursor, else the foreground
    public static func resolve(_ style: TerminalCellStyle, palette: TerminalPalette) -> TerminalResolvedStyle
}
```

Bodies the tests do not determine:

```swift
public static func phoneGrid(viewport: CGSize, cell: CGSize) -> (cols: Int, rows: Int) {
    guard cell.width > 0, cell.height > 0 else { return (1, 1) }
    let cols = Int(((viewport.width - 2 * padding) / cell.width).rounded(.down))
    let rows = Int(((viewport.height - 2 * padding) / cell.height).rounded(.down))
    return (max(1, cols), max(1, rows))
}
public static func fitScale(cols: Int, cell: CGSize, viewportWidth: CGFloat) -> CGFloat {
    let content = CGFloat(max(cols, 1)) * cell.width
    guard content > 0 else { return 1 }
    return min(1, max(viewportWidth - 2 * padding, 1) / content)
}
```

`resolve`: foreground = `fgRgb` parsed, else palette colour `fg` (0…255, a valid colour), else the palette foreground; background = `bgRgb` parsed, else palette colour `bg`, else nil. `inverse` swaps them, a nil background counting as the palette background (so the new background is never nil). `faint` mixes the foreground halfway toward the background (or the palette background), each channel `((a + b) / 2).rounded()`. `invisible` sets `drawsText` false. `bold`, `italic`, `underline`, `strike`, `overline` set their flags; `blink` and unknown attributes are ignored.

- [ ] **Step 1: Write the failing tests**

```swift
// TerminalGeometryTests
func testPhoneGridFitsTheViewport() {
    let grid = TerminalGeometry.phoneGrid(viewport: CGSize(width: 375, height: 646), cell: CGSize(width: 7.2, height: 15))
    XCTAssertEqual(grid.cols, 50); XCTAssertEqual(grid.rows, 42)
    let tiny = TerminalGeometry.phoneGrid(viewport: .zero, cell: CGSize(width: 7.2, height: 15))
    XCTAssertEqual(tiny.cols, 1); XCTAssertEqual(tiny.rows, 1)
}
func testFitScaleShrinksAWiderGridAndNeverEnlarges() {
    XCTAssertEqual(TerminalGeometry.fitScale(cols: 120, cell: CGSize(width: 7.2, height: 15), viewportWidth: 375), 367 / 864, accuracy: 0.0001)
    XCTAssertEqual(TerminalGeometry.fitScale(cols: 40, cell: CGSize(width: 7.2, height: 15), viewportWidth: 375), 1)
    XCTAssertEqual(TerminalGeometry.fitScale(cols: 320, cell: CGSize(width: 7.2, height: 15), viewportWidth: 375), 367 / 2304, accuracy: 0.0001,
                   "a Mac-sized grid beyond the phone's 300-column limit (contracts §17)")
}
func testScrollLinesKeepTheRest() {
    let first = TerminalGeometry.scrollLines(translation: 47, carry: 0, lineHeight: 15, scale: 1)
    XCTAssertEqual(first.lines, 3); XCTAssertEqual(first.carry, 2, accuracy: 0.001)
    let up = TerminalGeometry.scrollLines(translation: -20, carry: first.carry, lineHeight: 15, scale: 1)
    XCTAssertEqual(up.lines, -1); XCTAssertEqual(up.carry, -3, accuracy: 0.001)
    XCTAssertEqual(TerminalGeometry.scrollLines(translation: 30, carry: 0, lineHeight: 15, scale: 0.5).lines, 4)
}
// TerminalZoomTests (Review Focus 5)
func testANewGridWidthGoesBackToFit() {
    var zoom = TerminalZoom()
    zoom.gridChanged(cols: 100); zoom.pinch(to: 1, fit: 0.5)
    zoom.gridChanged(cols: 100); XCTAssertEqual(zoom.scale(fit: 0.5), 1, "frames of the same width keep the pinch")
    zoom.gridChanged(cols: 50); XCTAssertNil(zoom.zoom); XCTAssertEqual(zoom.scale(fit: 1), 1)
}
func testPinchStaysBetweenFitAndTwo() {
    var zoom = TerminalZoom()
    zoom.pinch(to: 0.1, fit: 0.5); XCTAssertEqual(zoom.scale(fit: 0.5), 0.5)
    zoom.pinch(to: 9, fit: 0.5); XCTAssertEqual(zoom.scale(fit: 0.5), 2)
}
func testAZoomBelowANewFitFollowsTheFit() {
    var zoom = TerminalZoom()
    zoom.pinch(to: 0.6, fit: 0.5)
    XCTAssertEqual(zoom.scale(fit: 0.8), 0.8, "a wider pane after rotation: never smaller than fit")
}

// TerminalColorsTests (palette: fg #d0d0d0, bg #101010, colors[i] = grey i, colors[2] = "#00ff00")
func testDefaultStyleUsesThePalette() {
    let style = TerminalColors.resolve(.default, palette: palette)
    XCTAssertEqual(style.foreground, TerminalRGB(red: 0xd0, green: 0xd0, blue: 0xd0)); XCTAssertNil(style.background)
    XCTAssertTrue(style.drawsText); XCTAssertFalse(style.bold)
}
func testIndexedAndRGBColours() {
    let style = TerminalColors.resolve(TerminalCellStyle(fg: 2, bgRgb: "#336699"), palette: palette)
    XCTAssertEqual(style.foreground, TerminalRGB(red: 0, green: 255, blue: 0))
    XCTAssertEqual(style.background, TerminalRGB(red: 0x33, green: 0x66, blue: 0x99))
}
func testInverseSwapsEvenTheDefaults() {
    let style = TerminalColors.resolve(TerminalCellStyle(attrs: [.inverse]), palette: palette)
    XCTAssertEqual(style.foreground, TerminalRGB(red: 0x10, green: 0x10, blue: 0x10))
    XCTAssertEqual(style.background, TerminalRGB(red: 0xd0, green: 0xd0, blue: 0xd0))
}
func testFaintBlendsHalfwayToTheBackground() {
    let style = TerminalColors.resolve(TerminalCellStyle(fgRgb: "#ffffff", bgRgb: "#000000", attrs: [.faint]), palette: palette)
    XCTAssertEqual(style.foreground, TerminalRGB(red: 128, green: 128, blue: 128))
}
func testInvisibleBoldItalicUnderlineStrikeOverline() {
    let style = TerminalColors.resolve(TerminalCellStyle(attrs: [.invisible, .bold, .italic, .underline, .strike, .overline, .blink]), palette: palette)
    XCTAssertFalse(style.drawsText)
    XCTAssertTrue(style.bold && style.italic && style.underline && style.strike && style.overline)
}
func testBadColoursFallBack() {
    XCTAssertNil(TerminalColors.rgb("#12345")); XCTAssertEqual(TerminalColors.rgb("#AbCdEf"), TerminalRGB(red: 0xab, green: 0xcd, blue: 0xef))
    let broken = TerminalPalette(fg: "red", bg: "#101010", colors: palette.colors)
    XCTAssertEqual(TerminalColors.foreground(broken), TerminalRGB(red: 255, green: 255, blue: 255))
    XCTAssertEqual(TerminalColors.cursor(palette), TerminalColors.foreground(palette))
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path shellx-ios/Packages/ShellXAppCore --filter 'TerminalGeometryTests|TerminalZoomTests|TerminalColorsTests'`
Expected: FAIL, `error: cannot find 'TerminalGeometry' in scope`.

- [ ] **Step 3: Implement** both files.

- [ ] **Step 4: Run them to see them pass**

Run: the command of Step 2. Expected: `Executed 12 tests, with 0 failures (0 unexpected)`.

- [ ] **Step 5: Commit**

```bash
git add shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Terminal/TerminalGeometry.swift \
  shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Terminal/TerminalColors.swift \
  shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/TerminalGeometryTests.swift \
  shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/TerminalColorsTests.swift
git commit -m "feat(shellx-ios): terminal geometry, zoom and colours"
```

---

### Task 5: The terminal view model: lifecycle and frames

**Files:**
- Create: `Core/Terminal/TerminalViewModel.swift`
- Modify: `CoreTests/Support/TerminalTestSupport.swift` (`ScriptedTerminalLink`, `testPalette`, frame helpers)
- Test: create `CoreTests/TerminalViewModelTests.swift`, `CoreTests/TerminalViewLiveTests.swift`

**Interfaces:**
- Consumes: Task 2 (`TerminalLink`, `TerminalHubEvent`, `TerminalOpenResult`, `MachineHub: TerminalLink`, the latency metrics), Task 3 (`TerminalTyping`), 2A's `TerminalFrameAssembler` and `TerminalScreen`.
- Produces (rules R1–R9 and the first-grid part of R11 of "Design"; copy the rules into the type's doc comment):

```swift
public enum TerminalUnavailableReason: Equatable, Sendable { case gone, refused, failed }
public enum TerminalViewPhase: Equatable, Sendable {
    /// Opening the view, or waiting for its first screen.
    case connecting
    case live
    /// The Mac is not online: the last screen (if any) stays, dimmed.
    case offline
    /// The Mac is online but its ShellX shows no terminals (no `terminal_view`).
    case unsupported
    case unavailable(TerminalUnavailableReason)
}

/// One workspace screen's terminal: the one terminal it shows, opened on the Mac at the phone's size (rules R1-R12).
@MainActor @Observable
public final class TerminalViewModel {
    public static let resizeDelay: Duration = .milliseconds(200)
    public static let busyRetryDelay: Duration = .milliseconds(300)
    public static let busyRetries = 5
    public static let failedRetryDelay: Duration = .seconds(1)
    public static let scrollCoalescing: Duration = .milliseconds(50)
    public static let echoTimeout: Duration = .seconds(2)

    public let machineID: String
    /// The terminal the page shown is; nil while it is none (an agent's chat).
    public private(set) var terminalId: String?
    public private(set) var phase: TerminalViewPhase           // .connecting at first
    public private(set) var screen: TerminalScreen
    /// Raised by one whenever `screen` changes.
    public private(set) var screenRevision: Int
    /// Snapshots applied since the terminal was shown (0: no screen yet).
    public private(set) var snapshots: Int
    /// Rows added above the oldest history row, minus rows dropped from the top, since the last snapshot (R7): the surface
    /// keeps a scrolled-up view in place by it.
    public private(set) var topShift: Int
    public private(set) var typing: TerminalTyping

    /// `sleep` waits out every delay (tests pass a `ManualSleeper`); `now` times the latencies.
    public init(machineID: String, link: any TerminalLink, maxHistoryRows: Int = TerminalScreen.defaultMaxHistoryRows,
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now })
    /// A model that shows `screen` in `phase` and sends nothing (render tests, previews). Never call `run()` on it.
    /// `snapshots` is 1 when `screen` has a size, else 0.
    public static func fixed(terminalId: String, screen: TerminalScreen = TerminalScreen(), phase: TerminalViewPhase = .live,
                             typing: TerminalTyping = TerminalTyping()) -> TerminalViewModel

    public func run() async
    public func show(_ terminalId: String?)
    public func setPhoneGrid(cols: Int, rows: Int)
    public func suspend()
    public func resume()
    public func retry()
}

// CoreTests/Support/TerminalTestSupport.swift
/// A `TerminalLink` the test drives: it records every call, answers each open from `openAnswers` (then `.outcome(.ok)`),
/// after `openGate` when one is set, and hands `emit(_:)` to every stream `terminalEvents()` returned.
@MainActor final class ScriptedTerminalLink: TerminalLink {
    enum Call: Equatable {
        case open(String, cols: Int, rows: Int), close(String), input(String, [TerminalInputUnit])
        case resize(String, cols: Int, rows: Int), resync(String)
    }
    var calls: [Call]                         // in order
    var online = true
    var supportsViews = true
    var openAnswers: [TerminalOpenResult] = []
    var openGate: Gate?
    var samples: [(metric: LatencyMetric, duration: Duration)]   // every recordLatency call, in order
    var latencies: [LatencyMetric] { get }    // samples.map(\.metric)
    var opens: [String] { get }               // terminal ids of the open calls
    var inputs: [[TerminalInputUnit]] { get } // units of the input calls
    func emit(_ event: TerminalHubEvent)
}
/// fg #d0d0d0, bg #101010, colors[i] = grey i.
let testPalette: TerminalPalette
/// One whole frame in one part (part 0 of 1). Snapshot head: cursor (0, 0), `testPalette`, `history` = history.count;
/// history rows at y = -history.count ... -1, then `text[i]` at y = i. Delta head: cursor (0, 0), `scroll`, `history`.
func snapshotPart(revision: Int, cols: Int = 20, rows: Int = 2, text: [String], history: [String] = [], alt: Bool = false) -> TerminalFramePart
func deltaPart(revision: Int, cols: Int = 20, rows: Int = 2, replacing: [Int: String], scroll: Int = 0,
               history: [String] = [], alt: Bool = false) -> TerminalFramePart
func historyPart(revision: Int, cols: Int = 20, rows: Int = 2, lines: [String]) -> TerminalFramePart
/// A `now` the test moves by hand, for `TerminalViewModel(now:)`: `base + offset` under a lock.
final class SteppedNow: @unchecked Sendable {
    var now: @Sendable () -> ContinuousClock.Instant { get }
    func advance(by duration: Duration)
}
```

- [ ] **Step 1: Write the failing tests**

`TerminalViewModelTests` (`@MainActor`; `makeModel(_ link:sleeper:maxHistoryRows:now:)` builds `TerminalViewModel(machineID: "m1", link:, maxHistoryRows:, sleep: sleeper.sleep, now:)` with a default `ManualSleeper()` and `{ ContinuousClock.now }`, starts `Task { await model.run() }` and cancels it in teardown; `live(_ model:_ link:_ id: = "t1", text: = ["$"], alt: = false)` does `setPhoneGrid(cols: 50, rows: 20)`, `show(id)`, waits for `link.opens.last == id`, emits `.push(machineID: "m1", .opened(terminalId: id))` and `.push(machineID: "m1", .frame(terminalId: id, part: snapshotPart(revision: 1, cols: 50, rows: 20, text: text, alt: alt)))`, and waits for `.live`; `emit(_ link:_ push:)` emits on `"m1"`):

```swift
func testOpensTheTerminalShownAtThePhoneSize() async {
    let link = ScriptedTerminalLink(); let model = makeModel(link)
    model.show("t1")
    try? await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(link.calls, [], "no open before the phone's size is known")
    model.setPhoneGrid(cols: 50, rows: 20)
    let opened = await eventually { link.calls == [.open("t1", cols: 50, rows: 20)] }
    XCTAssertTrue(opened); XCTAssertEqual(model.phase, .connecting)
}

func testTheFirstSnapshotGoesLiveAndIsMeasured() async {
    let link = ScriptedTerminalLink(); let model = makeModel(link)
    await live(model, link, text: ["$ ls"])
    XCTAssertEqual(model.screen.screenText().first, "$ ls"); XCTAssertEqual(model.snapshots, 1); XCTAssertEqual(model.topShift, 0)
    XCTAssertEqual(link.latencies.filter { $0 == .terminalFirstScreen }.count, 1)
    XCTAssertTrue(link.latencies.contains(.terminalFrameApply))
}

func testFramesBeforeOpenedAndOfOtherTerminalsOrMacsAreIgnored() async {
    let link = ScriptedTerminalLink(); let model = makeModel(link)
    model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
    _ = await eventually { link.opens == ["t1"] }
    emit(link, .frame(terminalId: "t1", part: snapshotPart(revision: 1, text: ["early"])))
    emit(link, .opened(terminalId: "t1"))
    link.emit(.push(machineID: "m2", .frame(terminalId: "t1", part: snapshotPart(revision: 1, text: ["other mac"]))))
    emit(link, .frame(terminalId: "t2", part: snapshotPart(revision: 1, text: ["other terminal"])))
    emit(link, .frame(terminalId: "t1", part: snapshotPart(revision: 1, text: ["mine"])))
    let shown = await eventually { model.phase == .live }
    XCTAssertTrue(shown); XCTAssertEqual(model.screen.screenText().first, "mine")
}

func testFastSwitchesNeverShowAnotherTerminalsFrames() async {   // Review Focus 1
    let link = ScriptedTerminalLink(); let model = makeModel(link)
    model.setPhoneGrid(cols: 50, rows: 20); model.show("t1"); model.show("t2")
    let ordered = await eventually {
        link.calls == [.open("t1", cols: 50, rows: 20), .close("t1"), .open("t2", cols: 50, rows: 20)]
    }
    XCTAssertTrue(ordered, "\(link.calls)")
    emit(link, .opened(terminalId: "t1")); emit(link, .frame(terminalId: "t1", part: snapshotPart(revision: 1, text: ["one"])))
    emit(link, .opened(terminalId: "t2")); emit(link, .frame(terminalId: "t2", part: snapshotPart(revision: 1, text: ["two"])))
    emit(link, .frame(terminalId: "t1", part: deltaPart(revision: 2, replacing: [0: "late one"])))
    _ = await eventually { model.phase == .live }
    try? await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(model.screen.screenText().first, "two")
}

func testTheLoadingStateLastsUntilTheFirstSnapshot() async {   // contracts §17: the Mac may wait 500 ms for the size
    let link = ScriptedTerminalLink(); let clock = SteppedNow()
    let model = makeModel(link, now: clock.now)
    model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
    _ = await eventually { link.opens == ["t1"] }
    emit(link, .opened(terminalId: "t1"))
    try? await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(model.phase, .connecting, "answered and opened, but no screen yet: still loading")
    clock.advance(by: .milliseconds(600))
    emit(link, .frame(terminalId: "t1", part: snapshotPart(revision: 1, cols: 50, rows: 20, text: ["$"])))
    _ = await eventually { model.phase == .live }
    XCTAssertEqual(link.samples.first { $0.metric == .terminalFirstScreen }?.duration, .milliseconds(600),
                   "measured from the swipe, the Mac's wait included")
}

func testAGridWiderThanThePhoneCanAskForIsShown() async {   // Review Focus 5, contracts §17
    let link = ScriptedTerminalLink(); let model = makeModel(link)
    model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
    _ = await eventually { link.opens == ["t1"] }
    emit(link, .opened(terminalId: "t1"))
    emit(link, .frame(terminalId: "t1", part: snapshotPart(revision: 1, cols: 320, rows: 130, text: [String(repeating: "x", count: 320)])))
    let shown = await eventually { model.phase == .live }
    XCTAssertTrue(shown)
    XCTAssertEqual(model.screen.cols, 320); XCTAssertEqual(model.screen.rows, 130)
    XCTAssertFalse(link.calls.contains(.resync("t1")))
}

func testShowingNothingClosesTheView() async {
    let link = ScriptedTerminalLink(); let model = makeModel(link)
    await live(model, link)
    model.show(nil)
    let closed = await eventually { link.calls.last == .close("t1") }
    XCTAssertTrue(closed)
}

func testLeavingTheScreenClosesTheView() async {
    let link = ScriptedTerminalLink()
    let model = TerminalViewModel(machineID: "m1", link: link, sleep: ManualSleeper().sleep)
    let run = Task { await model.run() }
    await live(model, link)
    run.cancel()
    let closed = await eventually { link.calls.last == .close("t1") }
    XCTAssertTrue(closed, "the close still goes out after run() ends")
}

func testARestartedRunKeepsTheViewOpen() async {
    let link = ScriptedTerminalLink()
    let model = TerminalViewModel(machineID: "m1", link: link, sleep: ManualSleeper().sleep)
    let first = Task { await model.run() }
    await live(model, link)
    first.cancel()
    let second = Task { await model.run() }
    addTeardownBlock { second.cancel() }
    try? await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(link.calls, [.open("t1", cols: 50, rows: 20)], "SwiftUI restarting the page's task neither closes nor reopens")
}

func testBackgroundClosesAndForegroundReopens() async {
    let link = ScriptedTerminalLink(); let model = makeModel(link)
    await live(model, link)
    model.suspend()
    let closed = await eventually { link.calls.last == .close("t1") }
    XCTAssertTrue(closed); XCTAssertEqual(model.screen.screenText().first, "$", "the screen stays")
    model.resume()
    let reopened = await eventually { link.opens == ["t1", "t1"] }
    XCTAssertTrue(reopened)
}

func testBackgroundDuringTheOpenClosesAfterIt() async {   // Review Focus 4
    let link = ScriptedTerminalLink(); let gate = Gate(); link.openGate = gate
    let model = makeModel(link)
    model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
    _ = await eventually { link.opens == ["t1"] }
    model.suspend(); gate.open()
    let ordered = await eventually { link.calls == [.open("t1", cols: 50, rows: 20), .close("t1")] }
    XCTAssertTrue(ordered)
    emit(link, .opened(terminalId: "t1")); emit(link, .frame(terminalId: "t1", part: snapshotPart(revision: 1, text: ["$"])))
    try? await Task.sleep(for: .milliseconds(50))
    XCTAssertNotEqual(model.phase, .live)
}

func testAGapAsksForOneResyncThenTakesTheSnapshot() async {
    let link = ScriptedTerminalLink(); let model = makeModel(link)
    await live(model, link)
    emit(link, .frame(terminalId: "t1", part: deltaPart(revision: 3, cols: 50, rows: 20, replacing: [0: "three"])))
    emit(link, .frame(terminalId: "t1", part: deltaPart(revision: 4, cols: 50, rows: 20, replacing: [0: "four"])))
    let asked = await eventually { link.calls.filter { $0 == .resync("t1") }.count == 1 }
    try? await Task.sleep(for: .milliseconds(50))
    XCTAssertTrue(asked); XCTAssertEqual(link.calls.filter { $0 == .resync("t1") }.count, 1)
    emit(link, .frame(terminalId: "t1", part: snapshotPart(revision: 5, cols: 50, rows: 20, text: ["fresh"])))
    let fresh = await eventually { model.screen.screenText().first == "fresh" }
    XCTAssertTrue(fresh)
}

func testMacOfflineKeepsTheScreenAndReopensOnceOnline() async {   // Review Focus 4
    let link = ScriptedTerminalLink(); let model = makeModel(link)
    await live(model, link, text: ["$ ls"])
    link.online = false; link.emit(.state(machineID: "m1", .reconnecting))
    let offline = await eventually { model.phase == .offline }
    XCTAssertTrue(offline); XCTAssertEqual(model.screen.screenText().first, "$ ls")
    XCTAssertFalse(link.calls.contains(.close("t1")), "the session is gone: nothing to close")
    link.online = true; link.emit(.state(machineID: "m1", .online))
    let reopened = await eventually { link.opens == ["t1", "t1"] }
    XCTAssertTrue(reopened)
    emit(link, .opened(terminalId: "t1"))
    emit(link, .frame(terminalId: "t1", part: snapshotPart(revision: 1, cols: 50, rows: 20, text: ["back"])))
    let back = await eventually { model.phase == .live && model.screen.screenText().first == "back" }
    XCTAssertTrue(back, "revision 1 again: a fresh assembler takes it")
    XCTAssertFalse(link.calls.contains(.resync("t1")))
}

func testOpenOutcomesThatStop() async {
    let link = ScriptedTerminalLink(); link.openAnswers = [.outcome(.notFound), .outcome(.refused)]
    let model = makeModel(link)
    model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
    let gone = await eventually { model.phase == .unavailable(.gone) }
    try? await Task.sleep(for: .milliseconds(50))
    XCTAssertTrue(gone); XCTAssertEqual(link.opens, ["t1"], "a terminal that is gone is not asked for again")
    model.show("t2")
    let refused = await eventually { model.phase == .unavailable(.refused) }
    XCTAssertTrue(refused)
}

func testAFailedOpenIsRetriedOnceThenOffersTryAgain() async {
    let link = ScriptedTerminalLink(); link.openAnswers = [.outcome(.failed), .noAnswer]
    let sleeper = ManualSleeper(); let model = makeModel(link, sleeper: sleeper)
    model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
    _ = await eventually { sleeper.waiting.contains(TerminalViewModel.failedRetryDelay) }
    sleeper.release { $0 == TerminalViewModel.failedRetryDelay }
    let failed = await eventually { link.opens.count == 2 && model.phase == .unavailable(.failed) }
    XCTAssertTrue(failed)
    model.retry()
    let again = await eventually { link.opens.count == 3 }
    XCTAssertTrue(again)
}

func testBusyIsRetriedFiveTimes() async {
    let link = ScriptedTerminalLink(); link.openAnswers = Array(repeating: .outcome(.busy), count: 6)
    let sleeper = ManualSleeper(); let model = makeModel(link, sleeper: sleeper)
    model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
    for _ in 0..<5 {
        _ = await eventually { sleeper.waiting.contains(TerminalViewModel.busyRetryDelay) }
        sleeper.release { $0 == TerminalViewModel.busyRetryDelay }
    }
    let failed = await eventually { link.opens.count == 6 && model.phase == .unavailable(.failed) }
    XCTAssertTrue(failed, "\(link.opens.count) \(model.phase)")
}

func testEndedViews() async {
    let link = ScriptedTerminalLink(); let model = makeModel(link)
    await live(model, link)
    emit(link, .ended(terminalId: "t1", reason: .notOpen))
    let reopened = await eventually { link.opens == ["t1", "t1"] }
    XCTAssertTrue(reopened)
    emit(link, .opened(terminalId: "t1")); emit(link, .frame(terminalId: "t1", part: snapshotPart(revision: 1, text: ["$"])))
    _ = await eventually { model.phase == .live }
    emit(link, .ended(terminalId: "t1", reason: .gone))
    let gone = await eventually { model.phase == .unavailable(.gone) }
    XCTAssertTrue(gone)
    await live(model, link, "t2")
    emit(link, .ended(terminalId: "t2", reason: .refused))
    let refused = await eventually { model.phase == .unavailable(.refused) }
    XCTAssertTrue(refused)
}

func testNotOpenBeforeOpenedIsIgnored() async {
    let link = ScriptedTerminalLink(); let gate = Gate(); link.openGate = gate
    let model = makeModel(link)
    model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
    _ = await eventually { link.opens == ["t1"] }
    emit(link, .ended(terminalId: "t1", reason: .notOpen))
    gate.open()
    try? await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(link.opens, ["t1"])
}

func testAMacWithoutTerminalViewsOrOfflineOpensNothing() async {
    let old = ScriptedTerminalLink(); old.supportsViews = false
    let model = makeModel(old)
    model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
    let unsupported = await eventually { model.phase == .unsupported }
    XCTAssertTrue(unsupported); XCTAssertEqual(old.calls, [])
    let away = ScriptedTerminalLink(); away.online = false; away.supportsViews = false
    let other = makeModel(away)
    other.setPhoneGrid(cols: 50, rows: 20); other.show("t1")
    let offline = await eventually { other.phase == .offline }
    XCTAssertTrue(offline, "a Mac never seen online is not called too old")
}

func testTopShiftFollowsRowsAddedAboveAndDroppedFromTheTop() async {
    let link = ScriptedTerminalLink(); let model = makeModel(link, maxHistoryRows: 5)
    model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
    _ = await eventually { link.opens == ["t1"] }
    emit(link, .opened(terminalId: "t1"))
    emit(link, .frame(terminalId: "t1", part: snapshotPart(revision: 1, cols: 10, rows: 2, text: ["a", "b"], history: ["h1", "h2"])))
    _ = await eventually { model.snapshots == 1 }
    emit(link, .frame(terminalId: "t1", part: historyPart(revision: 2, cols: 10, rows: 2, lines: ["h-2", "h-1", "h0"])))
    let grown = await eventually { model.topShift == 3 && model.screen.historyRows.count == 5 }
    XCTAssertTrue(grown)
    emit(link, .frame(terminalId: "t1", part: deltaPart(revision: 3, cols: 10, rows: 2, replacing: [0: "c", 1: "d"], scroll: 2)))
    let dropped = await eventually { model.topShift == 1 }
    XCTAssertTrue(dropped, "two rows dropped from the top")
    emit(link, .frame(terminalId: "t1", part: snapshotPart(revision: 4, cols: 10, rows: 2, text: ["e"])))
    let reset = await eventually { model.snapshots == 2 && model.topShift == 0 }
    XCTAssertTrue(reset)
}
```

`TerminalViewLiveTests` (`@MainActor`; through `HubRig` and a `FakeMac` whose `ws-a` holds `t1` and `t2`):

```swift
func testOpensSwitchesAndClosesThroughAFakeMac() async throws {
    let mac = FakeMac(name: "Mac"); await mac.setWorkspaces([/* ws-a with t1, t2 */])
    let rig = try await HubRig.make([mac], in: self)
    let up = await rig.online(sessions: 0); XCTAssertTrue(up)
    let model = TerminalViewModel(machineID: mac.machine.machineID, link: rig.hub)
    let run = Task { await model.run() }; addTeardownBlock { run.cancel() }
    model.setPhoneGrid(cols: 30, rows: 6); model.show("t1")
    let shown = await eventually { model.phase == .live && model.screen.screenText().first == "$" }
    XCTAssertTrue(shown)
    let opens = await mac.terminalViewOpens
    XCTAssertEqual(opens, [FakeMac.TerminalViewSize(terminalId: "t1", cols: 30, rows: 6)])
    model.show("t2")
    let switched = await eventually {
        let closes = await mac.terminalViewCloses, opens = await mac.terminalViewOpens
        return model.phase == .live && closes == ["t1"] && opens.map(\.terminalId) == ["t1", "t2"]
    }
    XCTAssertTrue(switched, "closed before the next open: no busy, no retry")
    model.show(nil)
    let closed = await eventually { await mac.terminalViewCloses == ["t1", "t2"] }
    XCTAssertTrue(closed)
}

func testAReconnectReopensTheView() async throws {   // Review Focus 4
    // live on t1 as above, then:
    await mac.dropLiveSessions()
    let back = await eventually {
        rig.backoff.release()
        let opens = await mac.terminalViewOpens
        return model.phase == .live && opens.count == 2
    }
    XCTAssertTrue(back)
}

func testATerminalTheMacCannotViewFailsLikeAnyFailure() async throws {   // contracts §17
    // the FakeMac and model as above, after: await mac.refuseTerminalView("t1", with: .failed)
    model.setPhoneGrid(cols: 30, rows: 6); model.show("t1")
    let failed = await eventually {
        let opens = await mac.terminalViewOpens
        return model.phase == .unavailable(.failed) && opens.count == 2
    }
    XCTAssertTrue(failed, "one retry after 1 s, then Try Again")
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path shellx-ios/Packages/ShellXAppCore --filter 'TerminalViewModelTests|TerminalViewLiveTests'`
Expected: FAIL, `error: cannot find 'TerminalViewModel' in scope`.

- [ ] **Step 3: Implement** `TerminalViewModel` per R1–R9 and the first part of R11, the test support, and `fixed(…)` (its link is a private no-op `TerminalLink` that is never online and supports nothing; a fixed model is never `active`, so R1 leaves its phase alone).

- [ ] **Step 4: Run them to see them pass**

Run: the command of Step 2. Expected: `Executed 23 tests, with 0 failures (0 unexpected)`.
Run: `shellx-ios/scripts/dev.sh test core`. Expected: `==> test core: passed`.

- [ ] **Step 5: Commit**

```bash
git add shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Terminal/TerminalViewModel.swift \
  shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/Support/TerminalTestSupport.swift \
  shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/TerminalViewModelTests.swift \
  shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/TerminalViewLiveTests.swift
git commit -m "feat(shellx-ios): terminal view model"
```

---

### Task 6: The terminal view model: typing, paste, scrolling and resizing

**Files:**
- Modify: `Core/Terminal/TerminalViewModel.swift`
- Test: create `CoreTests/TerminalViewModelInputTests.swift`; modify `CoreTests/TerminalViewLiveTests.swift`

**Interfaces:**
- Consumes: Task 3 (`TerminalTyping`, `TerminalInputBatcher`), Task 5.
- Produces (R10, the resize part of R11, R12):

```swift
// TerminalViewModel
public func insertText(_ text: String)
public func setMarkedText(_ text: String)
public func unmarkText()
public func deleteBackward()
public func press(_ key: TerminalKey, mods: [TerminalModifier] = [])
public func toggleCtrl()
public func paste(_ text: String)
public func scroll(lines: Int)
/// Raised by one for every input message queued (typing, keys, paste, scroll): the surface goes back to the bottom.
public private(set) var sentInputs: Int
/// Raised by one each time a paste is refused for its size (R12: `TerminalInputBatcher.pasteFits` is false); nothing
/// is sent, and the pane shows `terminal.paste.tooLarge`.
public private(set) var pasteTooLarge: Int
```

- [ ] **Step 1: Write the failing tests** in `TerminalViewModelInputTests` (same helpers as Task 5; copy `makeModel`, `live` and `emit` into this class):

```swift
func testTypingSendsCommittedTextOnly() async {
    let link = ScriptedTerminalLink(); let model = makeModel(link); await live(model, link)
    model.setMarkedText("v"); model.setMarkedText("vi"); model.setMarkedText("việ")
    XCTAssertEqual(model.typing.markedText, "việ")
    try? await Task.sleep(for: .milliseconds(50)); XCTAssertEqual(link.inputs, [])
    model.insertText("việt")
    let sent = await eventually { link.inputs == [[.text("việt")]] }
    XCTAssertTrue(sent)
}
func testBackspaceWhileComposingSendsNothing() async {
    let link = ScriptedTerminalLink(); let model = makeModel(link); await live(model, link)
    model.setMarkedText("việ"); model.deleteBackward()
    XCTAssertEqual(model.typing.markedText, "vi")
    model.unmarkText(); model.deleteBackward()
    let sent = await eventually { link.inputs == [[.text("vi")], [.key(.backspace, mods: [])]] }
    XCTAssertTrue(sent)
}
func testTheKeyBarAndTheCtrlLatch() async {
    let link = ScriptedTerminalLink(); let model = makeModel(link); await live(model, link)
    model.toggleCtrl(); XCTAssertTrue(model.typing.ctrlLatched)
    model.insertText("c"); model.press(.escape)
    let sent = await eventually { link.inputs == [[.key(.letter("c"), mods: [.ctrl])], [.key(.escape, mods: [])]] }
    XCTAssertTrue(sent)
}
func testInputTypedWhileOpeningGoesAfterTheOpen() async {
    let link = ScriptedTerminalLink(); let gate = Gate(); link.openGate = gate
    let model = makeModel(link)
    model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
    _ = await eventually { link.opens == ["t1"] }
    model.insertText("ls")
    try? await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(link.calls, [.open("t1", cols: 50, rows: 20)])
    gate.open()
    let ordered = await eventually { link.calls == [.open("t1", cols: 50, rows: 20), .input("t1", [.text("ls")])] }
    XCTAssertTrue(ordered)
}
func testInputAfterASwitchGoesToTheNewTerminal() async {   // Review Focus 1
    let link = ScriptedTerminalLink(); let model = makeModel(link); await live(model, link)
    model.show("t2"); model.insertText("x")
    let sent = await eventually { link.calls.last == .input("t2", [.text("x")]) }
    XCTAssertTrue(sent); XCTAssertFalse(link.calls.contains(.input("t1", [.text("x")])))
}
func testNothingIsTypedWithoutAView() async {
    let link = ScriptedTerminalLink(); link.online = false
    let model = makeModel(link)
    model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
    _ = await eventually { model.phase == .offline }
    model.insertText("x"); model.paste("y"); model.press(.enter)
    try? await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(link.inputs, [])
}
func testPasteGoesInPasteSizedMessages() async {
    let link = ScriptedTerminalLink(); let model = makeModel(link); await live(model, link)
    model.paste(String(repeating: "a", count: 20_000))
    let sent = await eventually { link.inputs.count == 2 }
    XCTAssertTrue(sent)
    XCTAssertEqual(link.inputs, [[.paste(String(repeating: "a", count: 16_384))], [.paste(String(repeating: "a", count: 3_616))]])
}
func testAPasteOverTheLimitIsRefused() async {
    let link = ScriptedTerminalLink(); let model = makeModel(link); await live(model, link)
    model.paste(String(repeating: "a", count: TerminalInputBatcher.maxPasteBytes + 1))
    try? await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(link.inputs, [], "nothing of it is sent")
    XCTAssertEqual(model.pasteTooLarge, 1); XCTAssertEqual(model.sentInputs, 0)
}
func testScrollOnTheAlternateScreenIsSummed() async {
    let link = ScriptedTerminalLink(); let sleeper = ManualSleeper(); let model = makeModel(link, sleeper: sleeper)
    await live(model, link, alt: true)
    model.scroll(lines: 1); model.scroll(lines: 1); model.scroll(lines: 1)
    XCTAssertEqual(link.inputs, [])
    _ = await eventually { sleeper.waiting.contains(TerminalViewModel.scrollCoalescing) }
    sleeper.release { $0 == TerminalViewModel.scrollCoalescing }
    let sent = await eventually { link.inputs == [[.scroll(lines: 3)]] }
    XCTAssertTrue(sent)
}
func testScrollOnTheMainScreenSendsNothing() async {
    let link = ScriptedTerminalLink(); let sleeper = ManualSleeper(); let model = makeModel(link, sleeper: sleeper)
    await live(model, link)
    model.scroll(lines: 3); sleeper.release()
    try? await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(link.inputs, [])
}
func testGridChangesSendOneResizeWithTheLatestSize() async {   // Review Focus 3
    let link = ScriptedTerminalLink(); let sleeper = ManualSleeper(); let model = makeModel(link, sleeper: sleeper)
    await live(model, link)
    model.setPhoneGrid(cols: 50, rows: 10); model.setPhoneGrid(cols: 40, rows: 18); model.setPhoneGrid(cols: 50, rows: 12)
    let resizes = { link.calls.filter { if case .resize = $0 { return true }; return false } }
    XCTAssertEqual(resizes(), [])
    _ = await eventually { sleeper.waiting.contains(TerminalViewModel.resizeDelay) }
    sleeper.release { $0 == TerminalViewModel.resizeDelay }
    let one = await eventually { resizes() == [.resize("t1", cols: 50, rows: 12)] }
    try? await Task.sleep(for: .milliseconds(50))
    XCTAssertTrue(one); XCTAssertEqual(resizes().count, 1)
}
func testResizeDuringTheOpenFollowsIt() async {   // Review Focus 3
    let link = ScriptedTerminalLink(); let gate = Gate(); link.openGate = gate
    let sleeper = ManualSleeper(); let model = makeModel(link, sleeper: sleeper)
    model.setPhoneGrid(cols: 50, rows: 20); model.show("t1")
    _ = await eventually { link.opens == ["t1"] }
    model.setPhoneGrid(cols: 50, rows: 12)
    _ = await eventually { sleeper.waiting.contains(TerminalViewModel.resizeDelay) }
    sleeper.release { $0 == TerminalViewModel.resizeDelay }
    gate.open()
    let ordered = await eventually { link.calls == [.open("t1", cols: 50, rows: 20), .resize("t1", cols: 50, rows: 12)] }
    XCTAssertTrue(ordered)
}
func testTheSameSizeSendsNoResize() async {
    let link = ScriptedTerminalLink(); let sleeper = ManualSleeper(); let model = makeModel(link, sleeper: sleeper)
    await live(model, link)
    model.setPhoneGrid(cols: 50, rows: 20); sleeper.release()
    try? await Task.sleep(for: .milliseconds(50))
    XCTAssertFalse(link.calls.contains { if case .resize = $0 { return true }; return false })
}
func testEchoIsMeasuredFromTypingToTheNextFrame() async {
    let link = ScriptedTerminalLink(); let model = makeModel(link); await live(model, link)
    model.insertText("a")
    _ = await eventually { link.inputs.count == 1 }
    emit(link, .frame(terminalId: "t1", part: deltaPart(revision: 2, cols: 50, rows: 20, replacing: [0: "$ a"])))
    let measured = await eventually { link.latencies.filter { $0 == .terminalKeyEcho }.count == 1 }
    XCTAssertTrue(measured)
    emit(link, .frame(terminalId: "t1", part: deltaPart(revision: 3, cols: 50, rows: 20, replacing: [1: "x"])))
    try? await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(link.latencies.filter { $0 == .terminalKeyEcho }.count, 1, "one echo per keystroke")
}
func testAnEchoThatNeverComesIsDropped() async {
    let link = ScriptedTerminalLink(); let sleeper = ManualSleeper(); let model = makeModel(link, sleeper: sleeper)
    await live(model, link)
    model.insertText("a")
    _ = await eventually { sleeper.waiting.contains(TerminalViewModel.echoTimeout) }
    sleeper.release { $0 == TerminalViewModel.echoTimeout }
    try? await Task.sleep(for: .milliseconds(20))
    emit(link, .frame(terminalId: "t1", part: deltaPart(revision: 2, cols: 50, rows: 20, replacing: [0: "late"])))
    try? await Task.sleep(for: .milliseconds(50))
    XCTAssertFalse(link.latencies.contains(.terminalKeyEcho))
}
```

Add to `TerminalViewLiveTests`:

```swift
func testTypingEchoesThroughAFakeMac() async throws {
    // live on t1 at 30 × 6 (prompt), then:
    model.insertText("ls"); model.press(.enter)
    let echoed = await eventually { Array(model.screen.screenText().prefix(2)) == ["$ ls", "$"] }
    XCTAssertTrue(echoed)
    let inputs = await mac.terminalViewInputs("t1")
    XCTAssertEqual(inputs, [[.text("ls")], [.key(.enter, mods: [])]])
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path shellx-ios/Packages/ShellXAppCore --filter 'TerminalViewModelInputTests|TerminalViewLiveTests'`
Expected: FAIL, `error: value of type 'TerminalViewModel' has no member 'insertText'`.

- [ ] **Step 3: Implement** R10, the resize part of R11 and R12 (each delay is a task that awaits `sleep(…)` and is cancelled when a newer change replaces it; the echo clock keeps a start instant and a token so a stale timeout does nothing).

- [ ] **Step 4: Run them to see them pass**

Run: the command of Step 2. Expected: `Executed 19 tests, with 0 failures (0 unexpected)`.
Run: `shellx-ios/scripts/dev.sh test core`. Expected: `==> test core: passed`.

- [ ] **Step 5: Commit**

```bash
git add shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Terminal/TerminalViewModel.swift \
  shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/TerminalViewModelInputTests.swift \
  shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/TerminalViewLiveTests.swift
git commit -m "feat(shellx-ios): typing, paste, scrolling and resizing in the terminal model"
```

---

### Task 7: The workspace screen model knows the terminal shown

**Files:**
- Modify: `Core/Workspaces/WorkspaceScreenModel.swift` (properties after `lastTabClosedHere` line 52; `select(_:)` 160-168; `reconcile()` 225-263)
- Test: modify `CoreTests/WorkspaceScreenModelTests.swift`

**Interfaces:**
- Consumes: today's `WorkspaceScreenModel`, `WorkspacePane.isAgent`.
- Produces:

```swift
/// The agent chips the user switched to their terminal ("View as Terminal"), until the screen closes.
public private(set) var shownAsTerminal: Set<String> = []
/// Switches the agent chip `terminalId` to its terminal (true) or back to its chat; an id the workspace does not have is ignored.
public func showAsTerminal(_ terminalId: String, _ on: Bool)
/// The terminal the page shown is: the chip shown when it is a shell, or an agent chip shown as its terminal; nil while the
/// chip shown is an agent's chat, or there is none. `WorkspaceView` gives it to `TerminalViewModel.show(_:)`.
public var terminalShown: String? { get }
/// The Mac made `terminalId` for this screen (＋): it is shown as soon as the Mac's list has it (at once when it does).
/// The user picking a chip first drops it.
public func expect(_ terminalId: String)
```

`reconcile()`: when the expected id is in the list, select it (`settled = true`) and forget it. `select(_:)` forgets it.

- [ ] **Step 1: Write the failing tests** (using the file's `terminals(_:agent:selected:)` and `makeModel(_:workspace:sleeper:sessions:)` helpers):

```swift
func testTheTerminalShownIsTheShellOrAnAgentShownAsTerminal() async throws {
    let mac = FakeMac(name: "Mac")
    await mac.setWorkspaces([linkWorkspace(terminals: terminals("claude", "zsh", agent: ["claude": "s1"], selected: "zsh"))])
    await mac.upsertSession(agentSession("s1"))
    let (model, _, _) = try await makeModel(mac, sessions: 1)
    XCTAssertEqual(model.terminalShown, "zsh")
    model.select("claude"); XCTAssertNil(model.terminalShown, "an agent's chip shows its chat")
    model.showAsTerminal("claude", true)
    XCTAssertEqual(model.shownAsTerminal, ["claude"]); XCTAssertEqual(model.terminalShown, "claude")
    model.showAsTerminal("claude", false); XCTAssertNil(model.terminalShown)
    model.showAsTerminal("nope", true); XCTAssertEqual(model.shownAsTerminal, [])
}
func testAnExpectedTerminalShowsOnceTheListHasIt() async throws {
    let mac = FakeMac(name: "Mac")
    await mac.setWorkspaces([linkWorkspace(terminals: terminals("zsh", selected: "zsh"))])
    let (model, _, _) = try await makeModel(mac)
    model.expect("t-new"); XCTAssertEqual(model.selectedTerminalId, "zsh")
    await mac.upsertWorkspace(linkWorkspace(terminals: terminals("zsh", "t-new", selected: "zsh")))
    let shown = await eventually { model.selectedTerminalId == "t-new" }
    XCTAssertTrue(shown); XCTAssertEqual(model.shownPaneClosed, 0)
}
func testAnExpectedTerminalAlreadyListedShowsAtOnce() async throws {
    // workspace terminals("zsh", "t-new", selected: "zsh"); model.expect("t-new") → selectedTerminalId == "t-new" right away
}
func testPickingAChipDropsTheExpectedOne() async throws {
    // terminals("zsh", "other", selected: "zsh"); expect("t-new"); select("other");
    // upsert terminals("zsh", "other", "t-new"); after a short wait selectedTerminalId == "other"
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path shellx-ios/Packages/ShellXAppCore --filter WorkspaceScreenModelTests`
Expected: FAIL, `error: value of type 'WorkspaceScreenModel' has no member 'terminalShown'`.

- [ ] **Step 3: Implement** the four members and the two edits.

- [ ] **Step 4: Run them to see them pass**

Run: the command of Step 2. Expected: `with 0 failures (0 unexpected)` (the existing tests of the file stay green).

- [ ] **Step 5: Commit**

```bash
git add shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Workspaces/WorkspaceScreenModel.swift \
  shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/WorkspaceScreenModelTests.swift
git commit -m "feat(shellx-ios): the workspace screen model knows the terminal shown"
```

---

### Task 8: Draw the Mac's terminal in a pane

**Files:**
- Create: `App/UI/Terminal/TerminalFont.swift`, `TerminalRowLayout.swift`, `TerminalCanvasView.swift`, `TerminalSurfaceView.swift`, `TerminalSurface.swift`, `TerminalPane.swift`
- Modify: `App/UI/Workspaces/ShellPanePlaceholder.swift` (doc 3-4, text key line 14), `App/Localizable.xcstrings` (8 keys)
- Test: create `AppTests/TerminalRenderTests.swift`, `AppTests/TerminalRowLayoutTests.swift`

**Interfaces:**
- Consumes: Task 4 (`TerminalGeometry`, `TerminalZoom`, `TerminalColors`), Task 5 (`TerminalViewModel`, `.fixed`), Task 1 fixtures (tests), 2A's `TerminalScreen`, `TerminalRow`, `TerminalCell`.
- Produces:

```swift
/// SF Mono at `size` (12 pt): regular, bold, italic and bold italic (italic falls back to the upright face when the
/// system has none), and the cell they make. CTFonts are immutable, hence @unchecked Sendable.
struct TerminalFont: @unchecked Sendable {
    static let size: CGFloat = 12
    static let standard: TerminalFont
    /// width: the advance of "0" in the regular face; height: ceil(ascent + descent + leading).
    let cell: CGSize
    /// From a cell's top to its baseline: ascent plus half the leading.
    let baseline: CGFloat
    let underlineOffset: CGFloat     // below the baseline (CTFontGetUnderlinePosition, made positive downward)
    let lineThickness: CGFloat       // CTFontGetUnderlineThickness, at least 1
    func font(bold: Bool, italic: Bool) -> CTFont
}

/// One row, laid out once from its cells and drawn from that until the row changes.
struct TerminalRowLayout {
    struct Cell: Equatable { var column: Int; var width: Int; var text: String }
    /// Consecutive cells of one resolved style (a blank cell counts as a space in the default style).
    struct Segment: Equatable {
        var columns: Range<Int>
        var style: TerminalResolvedStyle
        /// Cells of width 1 and one scalar, each at its column.
        var narrow: [Cell]
        /// Cells of width 2, or of more than one scalar: each drawn on its own, centred in its `width` columns.
        var clusters: [Cell]
    }
    static func segments(_ cells: [TerminalCell], palette: TerminalPalette) -> [Segment]
    let segments: [Segment]
    init(row: TerminalRow, cols: Int, palette: TerminalPalette, font: TerminalFont)
    /// Draws the row with its top at y = 0 in grid units (the caller scaled and translated the context).
    func draw(in context: CGContext, font: TerminalFont)
    /// The glyph cell covering `column` (the second column of a wide cell gives the wide cell) and its style; nil for a blank.
    func cell(at column: Int) -> (cell: Cell, style: TerminalResolvedStyle)?
}

/// Draws the visible rows of `model.screen` (it keeps no copy of the screen), the cursor and the marked text.
final class TerminalCanvasView: UIView {
    init(model: TerminalViewModel, font: TerminalFont)
    var scale: CGFloat
    var showsCursor: Bool
}

/// The scroll physics around the canvas: content = history and screen rows on the main screen, screen rows on the
/// alternate one, at `TerminalZoom.scale(fit:)`; follows the bottom unless scrolled up (then holds by `topShift`); pinch
/// zoom; alternate-screen pans become `model.scroll(lines:)`; reports `TerminalGeometry.phoneGrid` to the model.
final class TerminalSurfaceView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    init(model: TerminalViewModel, font: TerminalFont = .standard)
    /// Called with true / false when the view becomes / stops being the first responder (Task 9).
    var onFocusChange: (Bool) -> Void
    var isFollowingBottom: Bool { get }
    func update(revision: Int, snapshots: Int, topShift: Int, phase: TerminalViewPhase, typing: TerminalTyping, sentInputs: Int)
}

struct TerminalSurface: UIViewRepresentable {
    let model: TerminalViewModel
    let revision: Int
    let snapshots: Int
    let topShift: Int
    let typing: TerminalTyping
    let phase: TerminalViewPhase
    let sentInputs: Int
    let title: String
    @Binding var focused: Bool
}

/// A shell chip's page (and an agent chip's shown as its terminal).
struct TerminalPane: View {
    let model: TerminalViewModel
    let terminalId: String
    /// The tab's name as its chip shows it (VoiceOver).
    let title: String
    /// Tests: the key bar shows without focus (Task 9).
    var showsKeyBar = false
}
```

How the pieces behave (decisions the tests do not pin):
- **Pane states.** A page whose `terminalId` is not `model.terminalId` shows `ShellPanePlaceholder()` while `model.phase == .unsupported`, else plain `Color.appSurface`. The page shown: `.unsupported` → `ShellPanePlaceholder()`; `.unavailable(.gone)` → icon `xmark.rectangle` + `terminal.gone`; `.unavailable(.refused)` → icon `lock` + `workspaces.alert.refused.control`; `.unavailable(.failed)` → icon `exclamationmark.triangle` + `terminal.failed` + a `SecondaryButtonStyle` button `terminal.retry` (`model.retry()`); `.connecting` with `snapshots == 0` → `ProgressView` over `terminal.connecting`; `.offline` with `snapshots == 0` → icon `wifi.slash` + `workspaces.alert.offline`; otherwise the surface (`.offline`: at 50 % opacity with `NoticeCapsule(text: String(localized: "terminal.offline"))` over its top; `.connecting`: a small `ProgressView` at its top trailing corner). Message pages are centred on `Color.appSurface`, `.font(.callout)`, secondary text, `.accessibilityElement(children: .combine)`; identifiers `terminal.connecting`, `terminal.unavailable`, `terminal.offline`, `terminal.retry`, `terminal.surface`.
- **Observation.** `TerminalPane.body` reads `model.terminalId`, `phase`, `screenRevision`, `snapshots`, `topShift`, `typing` and `sentInputs` and passes them to `TerminalSurface`, so SwiftUI calls `updateUIView` after each change; `updateUIView` calls `update(…)`. It also reads `pasteTooLarge`: when it rises, `NoticeCapsule(text: String(localized: "terminal.paste.tooLarge"))` shows over the top of the surface for `AgentView.noticeDuration` (4 s) and VoiceOver announces it (`AccessibilityNotification.Announcement`).
- **Surface.** `contentInsetAdjustmentBehavior = .never`, `isDirectionalLockEnabled = true`, `alwaysBounceVertical` on the main screen only, background the palette background (`TerminalColors.background`) once a palette exists, else clear. In `layoutSubviews`: the canvas frame is `bounds` (the visible part of the content); fit = `TerminalGeometry.fitScale(cols: screen.cols, cell: font.cell, viewportWidth: bounds.width)`; `zoom.gridChanged(cols: screen.cols)`; scale = `zoom.scale(fit:)`; `contentSize` = (2 × padding + cols × cell.width × scale, 2 × padding + shownRows × cell.height × scale) with shownRows = (alt ? 0 : history count) + rows. On an update: a new snapshot count, a new `sentInputs` (the user typed), or following the bottom scrolls to the bottom; a new `typing` redraws the canvas; otherwise the content offset moves by (topShift − last topShift) × cell.height × scale. When `bounds.size` changed, report `TerminalGeometry.phoneGrid(viewport: bounds.size, cell: font.cell)` with `Task { @MainActor in model.setPhoneGrid(cols:rows:) }` (never inside the layout pass). Pinch (`UIPinchGestureRecognizer`): `zoom.pinch(to: startScale × recognizer.scale, fit:)`, keeping the content point under the fingers in place. Alternate-screen pan (`UIPanGestureRecognizer`, simultaneous with the scroll view's): only while `screen.alt` and the content fits vertically, and only its vertical part: `TerminalGeometry.scrollLines` → `model.scroll(lines:)`; the carry resets when the pan ends. Accessibility: one element, label `terminal.surface.label <title>`, value the screen rows' text joined by line breaks, traits `.allowsDirectInteraction`.
- **Canvas drawing** (`draw(_:)`): fill with the palette background; translate by (padding − origin) and scale by `scale`; for each visible row index (history rows first on the main screen, then screen rows), take its `TerminalRowLayout` from a cache keyed by row index that holds the `TerminalRow` it was built from (rebuilt when the row, `cols` or the palette differ; entries more than 40 rows outside the visible range dropped), and draw it at y = index × cell.height. Then the cursor, unless `showsCursor` is false (phase not `.live`, `cursor.visible` false, or marked text present): its box is the cell under it (2 columns for a wide cell); `block` (and unknown shapes) fills the box with `TerminalColors.cursor` and draws that cell's text again in `TerminalColors.background`; `bar` a 2-pt wide box at its left; `underline` a 2-pt high box at its bottom; `blockHollow` a 1-pt stroke of the box; never blinking. Then the marked text (`model.typing.markedText`, Task 9): at the cursor's cell in the regular face, palette foreground on palette background, with a 1-pt underline under its whole width.
- **Row layout** (the algorithm): `segments` walks `row.cells(cols:)`: `.continuation` is skipped, `.blank` is a narrow " " in `TerminalCellStyle.default`, `.glyph(text, width, style)` is narrow when `width == 1` and `text` is one scalar, else a cluster; consecutive cells whose `TerminalColors.resolve(_:palette:)` is equal form one segment. `draw`: per segment, a background rect over its columns when `background != nil`; when `drawsText`, the narrow cells' text as one `CTLine` (font of `bold`/`italic`, `kCTLigatureAttributeName: 0`, `kCTForegroundColorFromContextAttributeName: true`) whose glyphs are drawn with `CTFontDrawGlyphs` using each `CTRun`'s own font: a glyph's cell is the narrow cell whose scalar holds the glyph's string index (map the UTF-16 offset of every scalar first), its x is that cell's column × cell.width plus its offset from the first glyph of the same scalar; each cluster as its own `CTLine` drawn with `CTLineDraw`, centred in width × cell.width; underline at baseline + `underlineOffset`, strike at baseline − 0.3 × cell.height, overline at the cell's top, each `lineThickness` high across the segment. Layouts build their `CTLine`s once.

Strings (Task 8):

| Key | en | vi | comment |
| --- | --- | --- | --- |
| `terminal.needsUpdate` | Update ShellX on the Mac to see the terminal. | Cập nhật ShellX trên Mac để xem terminal. | In a shell pane when the Mac's ShellX is too old to show its terminals. |
| `terminal.connecting` | Opening the terminal… | Đang mở terminal… | In a shell pane while the Mac sends the terminal's first screen. |
| `terminal.offline` | The Mac is offline. This is the last screen it sent. | Mac đang ngoại tuyến. Đây là màn hình cuối cùng Mac gửi. | A short line over a terminal whose Mac went offline; the last screen stays, dimmed. |
| `terminal.gone` | This terminal is no longer on the Mac. | Terminal này không còn trên Mac. | In a shell pane whose terminal was closed on the Mac. |
| `terminal.failed` | Couldn't show the terminal. | Không hiện được terminal. | In a shell pane when the Mac could not show the terminal; a Try Again button follows. |
| `terminal.paste.tooLarge` | That paste is too large to send (256 KB at most). | Nội dung dán quá lớn để gửi (tối đa 256 KB). | A short notice over the terminal when a paste is over `TerminalInputBatcher.maxPasteBytes`; nothing is sent. |
| `terminal.retry` | Try Again | Thử lại | Button under the line saying the terminal could not be shown: asks the Mac again. |
| `terminal.surface.label %@` | Terminal %@ | Màn hình terminal %@ | VoiceOver label of the terminal area; the argument is the tab's name as its chip shows it. |

`ShellPanePlaceholder` shows `terminal.needsUpdate` instead of `workspace.shell.placeholder` (this plan does not delete that key; plan 3G removes it from the catalog when it lands, and older Macs get `terminal.needsUpdate`) and its doc says it is the page of a shell chip on a Mac whose ShellX shows no terminals.

- [ ] **Step 1: Read the HIG pages** (Packages/iOS/AGENTS.md): Gestures (https://developer.apple.com/design/human-interface-guidelines/gestures), Typography (https://developer.apple.com/design/human-interface-guidelines/typography), Accessibility (https://developer.apple.com/design/human-interface-guidelines/accessibility). Note in the task's report what they ask of pinch, panning beside page swipes, fixed-size text and VoiceOver labels. If a page cannot be fetched, write that down for the hand-off.

- [ ] **Step 2: Write the failing tests**

`TerminalRowLayoutTests` (`@testable import ShellX`):

```swift
func testCellsOfOneStyleFormOneSegment() {
    let cells = TerminalRow(runs: [TerminalStyledRun(x: 0, text: "ab", style: TerminalCellStyle(fg: 1)),
                                   TerminalStyledRun(x: 2, text: "c")]).cells(cols: 5)
    let segments = TerminalRowLayout.segments(cells, palette: DemoTerminalScreens.palette)
    XCTAssertEqual(segments.map(\.columns), [0..<2, 2..<5])
    XCTAssertEqual(segments[0].narrow.map(\.text), ["a", "b"])
}
func testWideAndClusterCellsAreDrawnOnTheirOwn() {
    let cells = TerminalRow(runs: [TerminalStyledRun(x: 0, text: "a"), TerminalStyledRun(x: 1, text: "中", width: 2),
                                   TerminalStyledRun(x: 3, text: "e\u{301}", width: 1)]).cells(cols: 5)
    let segments = TerminalRowLayout.segments(cells, palette: DemoTerminalScreens.palette)
    XCTAssertEqual(segments.count, 1)
    XCTAssertEqual(segments[0].clusters, [.init(column: 1, width: 2, text: "中"), .init(column: 3, width: 1, text: "e\u{301}")])
    XCTAssertEqual(segments[0].narrow.map(\.column), [0, 4])
}
func testTheCellUnderTheCursorIsFound() {
    let row = TerminalRow(runs: [TerminalStyledRun(x: 0, text: "a"), TerminalStyledRun(x: 1, text: "中", width: 2)])
    let layout = TerminalRowLayout(row: row, cols: 5, palette: DemoTerminalScreens.palette, font: .standard)
    XCTAssertEqual(layout.cell(at: 2)?.cell, .init(column: 1, width: 2, text: "中"))
    XCTAssertEqual(layout.cell(at: 0)?.cell.text, "a")
    XCTAssertNil(layout.cell(at: 4))
}
```

`TerminalRenderTests` (`@MainActor`; `assertRenders` as in `WorkspaceRenderTests` (two images, the window's size, light differs from dark); `screen(_ fixture:deltas:)` applies `fixture.snapshot` then each delta to a `TerminalScreen()`; `page(_ model:showsKeyBar:)` is `NavigationStack { TerminalPane(model: model, terminalId: model.terminalId ?? "t", title: "zsh", showsKeyBar: showsKeyBar).background(Color.appBackground).navigationTitle(Text(verbatim: "shellx-ios")).navigationBarTitleDisplayMode(.inline) }`; every render uses `settle: 0.2`):

```swift
func testRendersANormalShell() throws {
    let screen = Self.screen(DemoTerminalScreens.shell, deltas: [DemoTerminalScreens.shellTyping])
    XCTAssertEqual(screen.cursor?.x, 29)
    try assertRenders(page(.fixed(terminalId: "t-zsh", screen: screen)), name: "terminal-shell")
}
func testRendersVimOnTheAlternateScreen() throws {
    let screen = Self.screen(DemoTerminalScreens.vim)
    XCTAssertTrue(screen.alt); XCTAssertEqual(screen.historyRows.count, 0)
    try assertRenders(page(.fixed(terminalId: "t-vim", screen: screen)), name: "terminal-vim")
}
func testRendersHtopFittedToWidth() throws {   // Review Focus 5
    let fit = TerminalGeometry.fitScale(cols: 100, cell: TerminalFont.standard.cell, viewportWidth: SnapshotWriter.size.width)
    XCTAssertLessThan(fit, 1); XCTAssertGreaterThan(fit, 0.3)
    try assertRenders(page(.fixed(terminalId: "t-htop", screen: Self.screen(DemoTerminalScreens.htop))), name: "terminal-htop")
}
func testRendersA320ColumnGridFittedToWidth() throws {   // Review Focus 5, contracts §17
    let ruler = String(repeating: "0123456789", count: 31) + "012345"                       // 316 columns
    let wideMac = DemoTerminalFixture(
        cols: 320, rows: 130,
        screen: (0..<130).map { DemoTerminalScreens.runs("{5}" + String(format: "%03d", $0) + "{0} " + ruler) },
        cursor: TerminalCursor(x: 0, y: 129))
    let screen = Self.screen(wideMac)
    XCTAssertEqual(screen.cols, 320); XCTAssertEqual(screen.rows, 130)
    let fit = TerminalGeometry.fitScale(cols: 320, cell: TerminalFont.standard.cell, viewportWidth: SnapshotWriter.size.width)
    XCTAssertLessThan(fit, 0.2); XCTAssertGreaterThan(fit, 0)
    try assertRenders(page(.fixed(terminalId: "t-mac", screen: screen)), name: "terminal-320-columns")
}
func testRendersWideCharacters() throws {
    try assertRenders(page(.fixed(terminalId: "t-notes", screen: Self.screen(DemoTerminalScreens.wide))), name: "terminal-wide")
}
func testRendersAnAgentsTerminal() throws {
    try assertRenders(page(.fixed(terminalId: "t-claude", screen: Self.screen(DemoTerminalScreens.agent))), name: "terminal-agent")
}
func testRendersTheMacTooOldPlaceholder() throws {
    try assertRenders(page(.fixed(terminalId: "t-zsh", phase: .unsupported)), name: "terminal-needs-update")
}
func testRendersWhileItCannotShowTheTerminal() throws {
    let shell = Self.screen(DemoTerminalScreens.shell)
    let states: [(String, TerminalViewModel)] = [
        ("terminal-connecting", .fixed(terminalId: "t", phase: .connecting)),
        ("terminal-offline", .fixed(terminalId: "t", screen: shell, phase: .offline)),
        ("terminal-gone", .fixed(terminalId: "t", phase: .unavailable(.gone))),
        ("terminal-refused", .fixed(terminalId: "t", phase: .unavailable(.refused))),
        ("terminal-failed", .fixed(terminalId: "t", phase: .unavailable(.failed))),
    ]
    var firsts: [Data?] = []
    for (name, model) in states {
        let images = try SnapshotWriter().write(page(model), name: name, settle: 0.2)
        XCTAssertNotEqual(images.first?.pngData(), images.last?.pngData(), name)
        firsts.append(images.first?.pngData())
    }
    XCTAssertEqual(Set(firsts.compactMap { $0 }).count, states.count, "each state looks different")
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `shellx-ios/scripts/dev.sh test app`
Expected: FAIL: an `error: cannot find 'TerminalPane' in scope` line and `==> test app: FAILED`.

- [ ] **Step 4: Implement** the six files, the placeholder change and the 8 catalog entries.

- [ ] **Step 5: Run them to see them pass**

Run: `shellx-ios/scripts/dev.sh test app`. Expected: `==> test app: passed`.
Run: `python3 shellx-ios/scripts/check-strings.py`. Expected: `check-strings: ok (<n> keys)`.
Run: `shellx-ios/scripts/dev.sh screenshots /tmp/terminal-2c-task8`. Expected: `==> screenshots written to …`. Open the `terminal-*` PNGs (en and vi, light and dark): CJK and emoji sit in their two columns with the next character right after them, the htop grid fits the width, the vim status bar spans the row, the texts are not clipped.

- [ ] **Step 6: Commit**

```bash
git add shellx-ios/ShellX/UI/Terminal shellx-ios/ShellX/UI/Workspaces/ShellPanePlaceholder.swift shellx-ios/ShellX/Localizable.xcstrings \
  shellx-ios/ShellXTests/TerminalRenderTests.swift shellx-ios/ShellXTests/TerminalRowLayoutTests.swift
git commit -m "feat(shellx-ios): draw the Mac's terminal in a shell pane"
```

---

### Task 9: Type into the terminal

**Files:**
- Create: `App/UI/Terminal/TerminalSurfaceView+TextInput.swift`, `App/UI/Terminal/TerminalKeyBar.swift`
- Modify: `App/UI/Terminal/TerminalSurfaceView.swift` (stored properties for the text input; tap and long-press recognizers; `UIEditMenuInteraction`), `App/UI/Terminal/TerminalSurface.swift` (focus), `App/UI/Terminal/TerminalPane.swift` (key bar), `App/Localizable.xcstrings` (9 keys)
- Test: create `AppTests/TerminalSurfaceTests.swift`; modify `AppTests/TerminalRenderTests.swift`

**Interfaces:**
- Consumes: Task 3 (`TerminalHardwareKeys`, `TerminalHardwareModifiers`, `TerminalBarKey`), Task 6 (typing methods), Task 8.
- Produces:

```swift
// TerminalSurfaceView: UITextInput (in the extension file; stored properties in the class)
var pasteboard: UIPasteboard          // .general; tests set a named one
// UIKeyInput / UITextInput / UITextInputTraits members; paste(_:); canPerformAction(_:withSender:); pressesBegan/Ended/Cancelled

/// The key bar's buttons: its keys in `TerminalBarKey` order, then hide keyboard.
enum TerminalKeyBarItem: Hashable { case key(TerminalBarKey), hideKeyboard }
struct TerminalKeyBar: View {
    let ctrlLatched: Bool
    let press: (TerminalKeyBarItem) -> Void
}
// TerminalPane
/// What a key bar button does: a key → `model.press(key)`; ctrl → `model.toggleCtrl()`; hide keyboard → `hideKeyboard()`.
static func perform(_ item: TerminalKeyBarItem, on model: TerminalViewModel, hideKeyboard: () -> Void)
```

The text input (an algorithm the tests pin only in part):
- The document is `model.typing.markedText`; positions are a private `UITextPosition` subclass holding a UTF-16 offset, ranges a private `UITextRange` subclass; `beginningOfDocument` 0, `endOfDocument` the marked text's UTF-16 length; `markedTextRange` nil when it is empty; `selectedTextRange` the caret at the `selectedRange` last given to `setMarkedText` (its end), clamped; `text(in:)` the marked substring; `replace(_:withText:)` commits the marked text with that range replaced (`model.insertText(new)`); `firstRect(for:)` and `caretRect(for:)` the cursor's cell in the surface's coordinates (caret 2 pt wide); `selectionRects(for:)` `[]`; `closestPosition(to:)` the end; `tokenizer` `UITextInputStringTokenizer(textInput: self)`; `hasText` true (so Backspace always reaches `deleteBackward`); `markedTextStyle` nil; writing direction left to right.
- `insertText(_:)` → `model.insertText`; `setMarkedText(_:selectedRange:)` → `model.setMarkedText(text ?? "")`; `unmarkText()` → `model.unmarkText()`; `deleteBackward()` → `model.deleteBackward()`. Each redraws the canvas (the model's `sentInputs` brings the view back to the bottom).
- When the marked text changes without the keyboard asking (a key bar or hardware key committed it, or ctrl took the first composed letter), on the next main-queue turn call `inputDelegate?.selectionWillChange(self)`, `textWillChange(self)`, `textDidChange(self)`, `selectionDidChange(self)`, so the keyboard drops its composition.
- Traits: `autocorrectionType .no`, `autocapitalizationType .none`, `spellCheckingType .no`, `smartQuotesType .no`, `smartDashesType .no`, `smartInsertDeleteType .no`, `inlinePredictionType .no`, `keyboardType .default` (so the Vietnamese keyboards stay available), `returnKeyType .default`, `keyboardAppearance .default`; and a computed `writingToolsBehavior` returning `.none`, marked `@available(iOS 18.0, *)`.
- `canBecomeFirstResponder` true while the phase is `.live` or `.connecting`; `becomeFirstResponder`/`resignFirstResponder` call `onFocusChange` on the next main-queue turn. A tap becomes first responder. A long press (0.5 s) becomes first responder and presents `UIEditMenuInteraction` at the touch; `canPerformAction` is true only for `paste(_:)` while `pasteboard.hasStrings`; `paste(_:)` → `model.paste(pasteboard.string)`.
- `pressesBegan`: for each press with a `key`, `TerminalHardwareKeys.action(usage: key.keyCode.rawValue, modifiers: <from key.modifierFlags: .shift, .control, .alternate, .command>, composing: !model.typing.markedText.isEmpty)`; `.send(key, mods)` → `model.press(key, mods:)` and that press is not passed on; the rest go to `super` (also in `pressesEnded` and `pressesCancelled`, so UIKit's text system and input methods see them).
- `TerminalSurface`: `focused` true → `becomeFirstResponder()`, false → `resignFirstResponder()`; `onFocusChange` writes `focused`. A page that is not the one shown never keeps focus.
- `TerminalPane`: under the surface, while `focused || showsKeyBar`, `TerminalKeyBar(ctrlLatched: model.typing.ctrlLatched) { Self.perform($0, on: model) { focused = false } }`.
- `TerminalKeyBar` layout: a 44-pt row on `Color.appSurface` with a 1-pt top line `Color.primary.opacity(0.1)`; keys 36 pt high, at least 44 pt wide, 8-pt corners, 6-pt spacing, 8-pt side padding, on `Color.appBackground`; caps `Text(verbatim: "esc")`, `"tab"`, `"ctrl"` in `.system(size: 15, weight: .medium, design: .monospaced)`; arrows `Image(systemName: "arrow.left")`, `arrow.up`, `arrow.down`, `arrow.right`; after a `Spacer`, `keyboard.chevron.compact.down`. A latched ctrl: `Color("AccentColor").opacity(0.2)` behind `Color("AccentText")`, a 1-pt `Color("AccentColor").opacity(0.45)` outline, trait `.isSelected` and value `terminal.key.ctrl.latched`. Identifiers `terminal.key.escape`, `.tab`, `.ctrl`, `.left`, `.up`, `.down`, `.right`, `terminal.key.hideKeyboard`.

Strings (Task 9):

| Key | en | vi | comment |
| --- | --- | --- | --- |
| `terminal.key.escape` | Escape | Phím Esc | VoiceOver label of the esc key on the key bar over the keyboard. |
| `terminal.key.tab` | Tab | Phím Tab | VoiceOver label of the tab key on the key bar. |
| `terminal.key.ctrl` | Control | Phím Control | VoiceOver label of the ctrl key on the key bar: it holds Control for the next key. |
| `terminal.key.ctrl.latched` | On for the next key | Bật cho phím kế tiếp | VoiceOver value of the ctrl key while it is held for the next key. |
| `terminal.key.left` | Left Arrow | Mũi tên trái | VoiceOver label of the left arrow key on the key bar. |
| `terminal.key.up` | Up Arrow | Mũi tên lên | VoiceOver label of the up arrow key on the key bar. |
| `terminal.key.down` | Down Arrow | Mũi tên xuống | VoiceOver label of the down arrow key on the key bar. |
| `terminal.key.right` | Right Arrow | Mũi tên phải | VoiceOver label of the right arrow key on the key bar. |
| `terminal.key.hideKeyboard` | Hide Keyboard | Ẩn bàn phím | The key at the end of the key bar: hides the keyboard. |

- [ ] **Step 1: Read the HIG pages:** Virtual keyboards (https://developer.apple.com/design/human-interface-guidelines/virtual-keyboards), Keyboards (https://developer.apple.com/design/human-interface-guidelines/keyboards), Edit menus (https://developer.apple.com/design/human-interface-guidelines/edit-menus). Note what they ask of a key row above the keyboard, keyboard traits, physical keyboards and the Paste menu.

- [ ] **Step 2: Write the failing tests**

`TerminalSurfaceTests` (`@MainActor`; `makeSurface()` builds `WorkspaceRig.make(in: self)`, a `TerminalViewModel(machineID: rig.model.ref.machineID, link: rig.hub)` whose `run()` runs until teardown, `setPhoneGrid(cols: 40, rows: 10)`, `show("t-zsh")`, waits for `.live`, and returns `(rig, model, TerminalSurfaceView(model: model))`):

```swift
func testMarkedTextStaysOnThePhoneUntilCommitted() async throws {
    let (rig, _, surface) = try await makeSurface()
    surface.setMarkedText("việ", selectedRange: NSRange(location: 3, length: 0))
    let marked = try XCTUnwrap(surface.markedTextRange)
    XCTAssertEqual(surface.text(in: marked), "việ")
    try await Task.sleep(for: .milliseconds(200))
    let early = await rig.mac.terminalViewInputs("t-zsh")
    XCTAssertEqual(early, [])
    surface.insertText("việt")
    XCTAssertNil(surface.markedTextRange)
    let sent = await WorkspaceRig.eventually { await rig.mac.terminalViewInputs("t-zsh") == [[.text("việt")]] }
    XCTAssertTrue(sent)
}
func testDeleteBackwardEditsTheCompositionThenSendsBackspace() async throws {
    let (rig, model, surface) = try await makeSurface()
    surface.setMarkedText("việ", selectedRange: NSRange(location: 3, length: 0))
    surface.deleteBackward(); XCTAssertEqual(model.typing.markedText, "vi")
    surface.unmarkText(); surface.deleteBackward()
    let sent = await WorkspaceRig.eventually {
        await rig.mac.terminalViewInputs("t-zsh") == [[.text("vi")], [.key(.backspace, mods: [])]]
    }
    XCTAssertTrue(sent)
}
func testReturnIsTheEnterKey() async throws {
    let (rig, _, surface) = try await makeSurface()
    surface.insertText("\n")
    let sent = await WorkspaceRig.eventually { await rig.mac.terminalViewInputs("t-zsh") == [[.key(.enter, mods: [])]] }
    XCTAssertTrue(sent)
}
func testTheKeyboardNeverCorrectsOrCapitalizes() async throws {
    let (_, _, surface) = try await makeSurface()
    XCTAssertEqual(surface.autocorrectionType, .no); XCTAssertEqual(surface.autocapitalizationType, UITextAutocapitalizationType.none)
    XCTAssertEqual(surface.spellCheckingType, .no); XCTAssertEqual(surface.smartQuotesType, .no)
    XCTAssertEqual(surface.smartDashesType, .no); XCTAssertEqual(surface.smartInsertDeleteType, .no)
    XCTAssertEqual(surface.inlinePredictionType, .no); XCTAssertEqual(surface.keyboardType, .default)
    XCTAssertTrue(surface.canBecomeFirstResponder); XCTAssertTrue(surface.hasText)
}
func testPasteSendsOnePasteUnit() async throws {
    let (rig, _, surface) = try await makeSurface()
    let board = UIPasteboard.withUniqueName(); let name = board.name
    addTeardownBlock { @MainActor in UIPasteboard.remove(withName: name) }
    board.string = "echo a\necho b"; surface.pasteboard = board
    XCTAssertTrue(surface.canPerformAction(#selector(UIResponderStandardEditActions.paste(_:)), withSender: nil))
    XCTAssertFalse(surface.canPerformAction(#selector(UIResponderStandardEditActions.copy(_:)), withSender: nil))
    surface.paste(nil)
    let sent = await WorkspaceRig.eventually { await rig.mac.terminalViewInputs("t-zsh") == [[.paste("echo a\necho b")]] }
    XCTAssertTrue(sent)
}
func testTheKeyBarDrivesTheModel() async throws {
    let (rig, model, _) = try await makeSurface()
    var hidden = false
    TerminalPane.perform(.key(.ctrl), on: model) {}
    XCTAssertTrue(model.typing.ctrlLatched)
    TerminalPane.perform(.key(.escape), on: model) {}
    TerminalPane.perform(.hideKeyboard, on: model) { hidden = true }
    XCTAssertTrue(hidden)
    let sent = await WorkspaceRig.eventually { await rig.mac.terminalViewInputs("t-zsh") == [[.key(.escape, mods: [.ctrl])]] }
    XCTAssertTrue(sent)
}
```

Add to `TerminalRenderTests`:

```swift
func testRendersTheKeyBarWithCtrlLatched() throws {
    let typing = TerminalTyping(markedText: "việ", ctrlLatched: true)
    let model = TerminalViewModel.fixed(terminalId: "t-zsh", screen: Self.screen(DemoTerminalScreens.shell), typing: typing)
    try assertRenders(page(model, showsKeyBar: true), name: "terminal-key-bar-ctrl")
    let plain = try SnapshotWriter().write(page(.fixed(terminalId: "t-zsh", screen: Self.screen(DemoTerminalScreens.shell)), showsKeyBar: true),
                                           name: "terminal-key-bar", settle: 0.2)
    let latched = try SnapshotWriter().write(page(model, showsKeyBar: true), name: "terminal-key-bar-ctrl", settle: 0.2)
    XCTAssertNotEqual(plain.first?.pngData(), latched.first?.pngData(), "the latch and the marked text show")
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `shellx-ios/scripts/dev.sh test app`
Expected: FAIL: `error: value of type 'TerminalSurfaceView' has no member 'setMarkedText'` (or `cannot find 'TerminalKeyBarItem'`) and `==> test app: FAILED`.

- [ ] **Step 4: Implement** the text input, the hardware keys, paste, focus, the key bar and the 9 catalog entries.

- [ ] **Step 5: Run them to see them pass**

Run: `shellx-ios/scripts/dev.sh test app`. Expected: `==> test app: passed`.
Run: `python3 shellx-ios/scripts/check-strings.py`. Expected: `check-strings: ok (<n> keys)`.

- [ ] **Step 6: Commit**

```bash
git add shellx-ios/ShellX/UI/Terminal shellx-ios/ShellX/Localizable.xcstrings \
  shellx-ios/ShellXTests/TerminalSurfaceTests.swift shellx-ios/ShellXTests/TerminalRenderTests.swift
git commit -m "feat(shellx-ios): type into the terminal"
```

---

### Task 10: Terminal pages, the ＋ chip and View as Terminal

**Files:**
- Modify: `App/UI/Workspaces/WorkspaceScreen.swift` (`WorkspaceScreenActions` 5-14; `WorkspaceMenuItem` 17-39; the struct's generics and properties 54-82; `PaneChips` call 86-88; `menu` 160-182; `page(of:)` 210-216), `App/UI/Workspaces/PaneChips.swift` (properties 12-20, body 47-64), `App/UI/Workspaces/WorkspaceView.swift` (state 21-35, body 37-88, `make` 118-157), `App/UI/Workspaces/WorkspaceFeedback.swift` (`WorkspaceCommand` 5-13, `of` 61-90), `App/Localizable.xcstrings` (3 keys)
- Test: modify `AppTests/WorkspaceRenderTests.swift` (helper 92-106, menu test 183-198, two new renders), `AppTests/WorkspaceViewTests.swift`, `AppTests/WorkspaceLiveRenderTests.swift`

**Interfaces:**
- Consumes: Tasks 2 (`supportsTerminalView`, `supportsTerminalCreate`, `createTerminal`), 5 (`TerminalViewModel`), 7 (`shownAsTerminal`, `showAsTerminal`, `terminalShown`, `expect`), 8 and 9 (`TerminalPane`).
- Produces:

```swift
// WorkspaceScreenActions gains
/// The user tapped ＋: open a new terminal tab in this workspace on the Mac.
var createTerminal: () -> Void = {}
/// "View as Terminal" (true) or "View as Chat" (false) on the agent chip with this terminal id.
var showAsTerminal: (String, Bool) -> Void = { _, _ in }

enum WorkspaceMenuItem: CaseIterable {
    case rename, viewAsTerminal, viewAsChat, closeTab, closeWorkspace
    /// How the agent chip shown shows its page, when `•••` may switch it (its Mac shows terminals).
    enum AgentChip { case chat, terminal }
    /// In this order: rename; viewAsTerminal for `.chat` or viewAsChat for `.terminal`; closeTab when `canCloseTab`; closeWorkspace.
    static func items(canCloseTab: Bool, agentChip: AgentChip? = nil) -> [WorkspaceMenuItem]
    var title: String            // viewAsTerminal "workspace.menu.viewAsTerminal", viewAsChat "workspace.menu.viewAsChat"
    var isDestructive: Bool      // closeTab and closeWorkspace only
}

struct WorkspaceScreen<AgentPane: View, ShellPane: View>: View {
    // … today's properties up to `canCloseTab` (line 67), then these three, then `pagingLocked` and the rest:
    /// The Mac takes `terminal.create`: the chips end with ＋, enabled while `canControl`.
    var canCreateTerminal = false
    /// The Mac shows terminals: `•••` offers View as Terminal / View as Chat on an agent chip.
    var canViewTerminals = false
    /// The agent chips shown as their terminal (`WorkspaceScreenModel.shownAsTerminal`).
    var shownAsTerminal: Set<String> = []
    // … `alert`, `agent`, then:
    /// The page of a shell chip, and of an agent chip shown as its terminal.
    @ViewBuilder let shell: (WorkspacePane) -> ShellPane
}

// PaneChips gains
/// The user tapped ＋; nil leaves it out (the Mac takes no `terminal.create`).
var add: (() -> Void)? = nil
/// False dims ＋ (the Mac is not online).
var addEnabled = true

// WorkspaceCommand gains
/// Opens a terminal tab in the workspace (`MachineHub.createTerminal(_:)`).
case createTerminal
```

Wiring:
- `page(of:)`: an agent pane not in `shownAsTerminal` → `agent(session)`; any other pane → `shell(pane)`.
- `menu`: `items(canCloseTab: canCloseTab && shownPane != nil, agentChip:)` where `agentChip` is nil unless `canViewTerminals` and the shown pane is an agent (`.terminal` when it is in `shownAsTerminal`, else `.chat`); `.viewAsTerminal` → `actions.showAsTerminal(pane.id, true)`, `.viewAsChat` → `actions.showAsTerminal(pane.id, false)`.
- `PaneChips`: after the chips, when `add` is set, a chip with `Image(systemName: "plus")` in the chip style (`Color.appSurface`, the 1-pt outline, 44-pt row), `.disabled(!addEnabled)`, label `terminal.new`, identifier `workspace.chip.add`. `WorkspaceScreen` passes `add: canCreateTerminal ? actions.createTerminal : nil`, `addEnabled: canControl`.
- `WorkspaceView`: `@State private var terminal: TerminalViewModel` made in `init` with `TerminalViewModel(machineID: ref.machineID, link: scope.hub)`; `@Environment(\.scenePhase)`; `WorkspaceScreen(…, canCreateTerminal: hub.supportsTerminalCreate(ref.machineID), canViewTerminals: hub.supportsTerminalView(ref.machineID), shownAsTerminal: model.shownAsTerminal, …, shell: { pane in TerminalPane(model: terminal, terminalId: pane.id, title: PaneChips.label(for: pane)) })`; on the `Group`: `.task { await terminal.run() }`, `.onChange(of: model.terminalShown, initial: true) { _, id in terminal.show(id) }`, `.onChange(of: scenePhase) { _, phase in if phase == .background { terminal.suspend() } else if phase == .active { terminal.resume() } }`.
- `WorkspaceScreenActions.make`: `createTerminal: { run(.createTerminal) { let answer = await hub.createTerminal(ref); if let id = answer.terminalId { model.expect(id) }; return answer.result } }`, `showAsTerminal: { model.showAsTerminal($0, $1) }`.
- `WorkspaceFeedback.of`: `.createTerminal` joins `.create, .rename, .close` for `.notFound` (`.refresh`) and `.create, .rename` for `.refused` (`.alert(.refusedControl)`); `.ok` is `.nothing` (only `.create` opens a workspace).

Strings (Task 10):

| Key | en | vi | comment |
| --- | --- | --- | --- |
| `terminal.new` | New Terminal | Terminal mới | VoiceOver label of the ＋ chip at the end of the chip row: opens a new terminal tab in this workspace on the Mac. |
| `workspace.menu.viewAsTerminal` | View as Terminal | Xem dạng terminal | Item of the ••• menu while the chip shown runs an agent: shows that agent's terminal instead of its chat. |
| `workspace.menu.viewAsChat` | View as Chat | Xem dạng chat | Item of the ••• menu while an agent's chip shows its terminal: back to the agent's chat. |

- [ ] **Step 1: Read the HIG pages:** Menus (https://developer.apple.com/design/human-interface-guidelines/menus), Buttons (https://developer.apple.com/design/human-interface-guidelines/buttons). Note what they say about the order of non-destructive items and the hit size of the ＋ chip.

- [ ] **Step 2: Write the failing tests**

`WorkspaceRenderTests`: `screen(…)` gains `canCreateTerminal: Bool = false`, `canViewTerminals: Bool = false`, `shownAsTerminal: Set<String> = []`, `shell: @escaping (WorkspacePane) -> AnyView = { _ in AnyView(ShellPanePlaceholder()) }` and passes them on. The menu test becomes:

```swift
func testTheMenuOffersRenameViewAsTerminalCloseTabAndCloseWorkspace() {
    XCTAssertEqual(WorkspaceMenuItem.items(canCloseTab: false), [.rename, .closeWorkspace], "a Mac from before terminal_close")
    XCTAssertEqual(WorkspaceMenuItem.items(canCloseTab: true), [.rename, .closeTab, .closeWorkspace])
    XCTAssertEqual(WorkspaceMenuItem.items(canCloseTab: true, agentChip: .chat), [.rename, .viewAsTerminal, .closeTab, .closeWorkspace])
    XCTAssertEqual(WorkspaceMenuItem.items(canCloseTab: true, agentChip: .terminal), [.rename, .viewAsChat, .closeTab, .closeWorkspace])
    let titles = WorkspaceMenuItem.allCases.map(\.title)
    XCTAssertEqual(titles, [String(localized: "workspace.menu.rename"), String(localized: "workspace.menu.viewAsTerminal"),
                            String(localized: "workspace.menu.viewAsChat"), String(localized: "terminal.close.menu"),
                            String(localized: "workspace.menu.close")])
    XCTAssertEqual(Set(titles).count, 5)
    XCTAssertEqual(WorkspaceMenuItem.allCases.filter(\.isDestructive), [.closeTab, .closeWorkspace])
}
func testRendersTheNewTerminalChip() throws {
    try assertRenders(screen(selected: "t-zsh", canCreateTerminal: true), name: "workspace-new-terminal")
    let without = try SnapshotWriter().write(screen(selected: "t-zsh"), name: "workspace-shell")
    let with = try SnapshotWriter().write(screen(selected: "t-zsh", canCreateTerminal: true), name: "workspace-new-terminal")
    XCTAssertNotEqual(without.first?.pngData(), with.first?.pngData())
}
func testRendersAnAgentChipAsItsTerminal() throws {
    var agent = TerminalScreen(); agent.apply(DemoTerminalScreens.agent.snapshot)
    let model = TerminalViewModel.fixed(terminalId: "t-claude", screen: agent)
    try assertRenders(
        screen(selected: "t-claude", canViewTerminals: true, shownAsTerminal: ["t-claude"],
               shell: { pane in AnyView(TerminalPane(model: model, terminalId: pane.id, title: pane.title)) }),
        name: "workspace-agent-as-terminal")
}
```

`WorkspaceViewTests`:

```swift
func testNewTerminalReachesTheMacAndItsChipShows() async throws {
    let rig = try await makeRig(); follow(rig)
    XCTAssertTrue(rig.hub.supportsTerminalCreate(rig.model.ref.machineID))
    rig.actions.createTerminal()
    let feedback = await rig.lastFeedback()
    XCTAssertEqual(feedback, .nothing)
    let creates = await rig.mac.terminalCreates
    XCTAssertEqual(creates, ["ws-shellx"])
    let shown = await eventually { rig.model.selectedTerminalId?.hasPrefix("ws-shellx-new-") == true }
    XCTAssertTrue(shown, "\(String(describing: rig.model.selectedTerminalId))")
    XCTAssertTrue(rig.screen.alerts.isEmpty)
}
func testARefusedNewTerminalIsAnAlert() async throws {
    let rig = try await makeRig(); follow(rig)
    await rig.mac.setNextTerminalCreateOutcome(.refused)
    rig.actions.createTerminal()
    let feedback = await rig.lastFeedback()
    XCTAssertEqual(feedback, .alert(.refusedControl)); XCTAssertEqual(rig.screen.alerts, [.refusedControl])
    XCTAssertEqual(rig.model.selectedTerminalId, "t-zsh")
}
func testViewAsTerminalSwitchesTheAgentChipsPage() async throws {
    let rig = try await makeRig(); follow(rig)
    rig.actions.select("t-claude"); XCTAssertNil(rig.model.terminalShown)
    rig.actions.showAsTerminal("t-claude", true); XCTAssertEqual(rig.model.terminalShown, "t-claude")
    rig.actions.showAsTerminal("t-claude", false); XCTAssertNil(rig.model.terminalShown)
}
func testANewTerminalsAnswers() {
    let m = "m1"
    XCTAssertEqual(WorkspaceFeedback.of(.ok(workspaceId: nil), for: .createTerminal, machineID: m), .nothing)
    XCTAssertEqual(WorkspaceFeedback.of(.notFound, for: .createTerminal, machineID: m), .refresh)
    XCTAssertEqual(WorkspaceFeedback.of(.refused, for: .createTerminal, machineID: m), .alert(.refusedControl))
    XCTAssertEqual(WorkspaceFeedback.of(.failed, for: .createTerminal, machineID: m), .alert(.failed))
    XCTAssertEqual(WorkspaceFeedback.of(.offline, for: .createTerminal, machineID: m), .alert(.offline))
    XCTAssertEqual(WorkspaceFeedback.of(.unknown, for: .createTerminal, machineID: m), .alert(.unknown))
}
```

`WorkspaceLiveRenderTests`:

```swift
func testRendersATerminalFromTheHub() async throws {
    let rig = try await WorkspaceRig.make(in: self)
    await rig.mac.setTerminalFixtures(["t-zsh": DemoTerminalScreens.shell])
    XCTAssertEqual(rig.model.selectedTerminalId, "t-zsh", "the Mac's selection: a shell")
    let live = NavigationStack { WorkspaceView(scope: rig.scope, ref: rig.model.ref, open: { _ in }) }
    let images = try SnapshotWriter().write(live, name: "workspace-live-terminal", settle: 1.0)
    XCTAssertEqual(images.count, 2)
    let opened = await WorkspaceRig.eventually { await rig.mac.terminalViewOpens.first?.terminalId == "t-zsh" }
    XCTAssertTrue(opened, "the page shown opened its terminal")
    let cols = await rig.mac.terminalViewOpens.first?.cols ?? 0
    XCTAssertGreaterThanOrEqual(cols, 20)
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `shellx-ios/scripts/dev.sh test app`
Expected: FAIL: `error: extra argument 'shell' in call` (or `type 'WorkspaceMenuItem' has no member 'viewAsTerminal'`) and `==> test app: FAILED`.

- [ ] **Step 4: Implement** the wiring and the 3 catalog entries.

- [ ] **Step 5: Run them to see them pass**

Run: `shellx-ios/scripts/dev.sh test app`. Expected: `==> test app: passed` (the existing `WorkspaceViewTests`, `WorkspaceListActionsTests` and `WaitingBorderRenderTests` calls of `items(canCloseTab:)` and `PaneChips(…)` compile unchanged).
Run: `python3 shellx-ios/scripts/check-strings.py`. Expected: `check-strings: ok (<n> keys)`.

- [ ] **Step 6: Commit**

```bash
git add shellx-ios/ShellX/UI/Workspaces shellx-ios/ShellX/Localizable.xcstrings \
  shellx-ios/ShellXTests/WorkspaceRenderTests.swift shellx-ios/ShellXTests/WorkspaceViewTests.swift \
  shellx-ios/ShellXTests/WorkspaceLiveRenderTests.swift
git commit -m "feat(shellx-ios): terminal pages, the new terminal chip and View as Terminal"
```

---

### Task 11: The demo Mac's terminals

**Files:**
- Modify: `<APP_DEMO>/DemoComposition.swift` (the `if runsScript` block of `prepare`, lines 72-76 today; a new static after `workspaces`, line 101)
- Test: modify `AppTests/DemoCompositionTests.swift`

**Interfaces:**
- Consumes: Task 1 (`FakeMac.setTerminalFixtures`, `DemoTerminalScreens`), Task 5 (`TerminalViewModel`).
- Produces:

```swift
/// What the demo Mac's terminals show ("Try without an account" and `SHELLX_DEMO=1`): the agents' terminals an agent's
/// screen, the shells a session, a dev server that keeps logging, and a note in Vietnamese, Chinese, Japanese, Korean and emoji.
static let terminals: [String: DemoTerminalFixture] = [
    "demo-shellx-t1": DemoTerminalScreens.agent, "demo-shellx-t2": DemoTerminalScreens.shell,
    "demo-relay-t1": DemoTerminalScreens.devServer, "demo-web-t1": DemoTerminalScreens.agent,
    "demo-notes-t1": DemoTerminalScreens.wide,
]
// prepare, right after `await first.setWorkspaces(Self.workspaces)`:  await first.setTerminalFixtures(Self.terminals)
```

- [ ] **Step 1: Write the failing test** in `DemoCompositionTests`:

```swift
func testDemoMacShowsItsTerminals() async throws {
    let graph = DemoComposition.make(
        approvalDelay: .zero, pasteboard: makePasteboard(), runsScript: true, history: makeHistoryDirectory())
    await graph.prepare()
    await graph.coordinator.launch()
    let hub = try XCTUnwrap(graph.coordinator.hub)
    addTeardownBlock { @MainActor in await hub.stopAll() }
    let id = try XCTUnwrap(hub.machines.first?.id)
    let ready = await eventually { hub.supportsTerminalView(id) && hub.supportsTerminalCreate(id) && hub.workspaceRows(machineID: id).count == 4 }
    XCTAssertTrue(ready)
    let model = TerminalViewModel(machineID: id, link: hub)
    let run = Task { await model.run() }
    addTeardownBlock { run.cancel() }
    model.setPhoneGrid(cols: 50, rows: 40)
    model.show("demo-shellx-t2")
    var expected = TerminalScreen()
    expected.apply(DemoTerminalScreens.shell.snapshot)
    let shell = await eventually { model.phase == .live && model.screen.screenText() == expected.screenText() }
    XCTAssertTrue(shell)
    model.show("demo-notes-t1")
    let wide = await eventually { model.phase == .live && model.screen.screenText().contains("中文：终端测试") }
    XCTAssertTrue(wide)
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `shellx-ios/scripts/dev.sh test app`
Expected: FAIL in `testDemoMacShowsItsTerminals` (the demo serves fresh prompts, so the shell screen never matches) and `==> test app: FAILED`.

- [ ] **Step 3: Implement** the static and the one line in `prepare`.

- [ ] **Step 4: Run it to see it pass**

Run: `shellx-ios/scripts/dev.sh test app`. Expected: `==> test app: passed`.
Run: `shellx-ios/scripts/dev.sh test release`. Expected: `==> test release: passed` with `no Debug-only code in <n> Mach-O files` (the terminal code adds no Debug-only name; before plan 1C the demo stays Debug-only, after it ships on purpose).

- [ ] **Step 5: Commit**

```bash
git add <APP_DEMO>/DemoComposition.swift shellx-ios/ShellXTests/DemoCompositionTests.swift
git commit -m "feat(shellx-ios): the demo Mac's terminals"
```

---

### Task 12: Verify and hand off

**Files:** the Android generated strings (only if their script exists), `docs/superpowers/ledgers/shellx-mobile-workspaces.md`, `docs/superpowers/ledgers/shellx-android-parity.md` (only if it exists).

- [ ] **Step 1: Bring `develop` in.** Run `git merge develop`. If plan 1C landed meanwhile (`shellx-ios/Packages/ShellXAppCore/Sources/ShellXDemo/FakeMac.swift` now exists) and `DemoTerminalScreens.swift` or `FakeMacTerminals.swift` is still in `Sources/ShellXAppTestSupport/`, `git mv` both into `Sources/ShellXDemo/` (their types are already `public` where used), check that `DemoComposition.swift` is in `shellx-ios/ShellX/Demo/` with the `setTerminalFixtures` line, and commit `refactor(shellx-ios): demo terminals move with the demo`.

- [ ] **Step 2: Android strings.** If `shellx-android/scripts/import-strings.py` exists: run `python3 shellx-android/scripts/import-strings.py` (expected `import-strings: wrote shellx-android/app/src/main/res/values/strings.xml and values-vi/strings.xml (…)`), then `python3 shellx-android/scripts/import-strings.py --check` (expected `import-strings: ok (…)`), and commit the two files as `chore(shellx-android): import the terminal strings`. If it refuses a key, stop and report the key: do not edit Android files by hand. If the script does not exist, skip this step. If `docs/superpowers/ledgers/shellx-android-parity.md` exists, replace `ShellX/UI/Workspaces/ShellPanePlaceholder.swift (until 2C)` in it with `ShellX/UI/Terminal/TerminalPane.swift` and commit it as `docs(shellx): the iPhone terminal pane in the Android parity ledger`.

- [ ] **Step 3: Full verification**

Run: `shellx-ios/scripts/dev.sh test all`. Expected: `==> test all: passed`.
Run: `bash scripts/shellx/check-ios-license.sh`. Expected: `check-ios-license: ok`.
Run: `python3 shellx-ios/scripts/check-strings.py`. Expected: `check-strings: ok (<n> keys)`.
Run: `python3 scripts/verify-local.py; echo "exit=$?"`. Expected: a line starting `PASSED:` (a hint line follows it) and `exit=0`.
Run: `git diff --name-only develop...HEAD | grep -v -e '^shellx-ios/' -e '^shellx-android/app/src/main/res/values' -e '^docs/superpowers/ledgers/'`. Expected: no output.
Run: `shellx-ios/scripts/dev.sh screenshots /tmp/terminal-2c-shots`. Expected: `==> screenshots written to …`. Open every `terminal-*`, `workspace-new-terminal*`, `workspace-agent-as-terminal*` and `workspace-live-terminal*` PNG in en and vi, light and dark: no clipped or overlapping text, a translation everywhere, the latched ctrl and the marked text visible, wide characters aligned. Fix and rerun if not.

- [ ] **Step 4: Localization audit** (CLAUDE.md, `skills/cmux-localization`): list the 20 keys added with their en and vi:

```bash
python3 -c 'import json; d=json.load(open("shellx-ios/ShellX/Localizable.xcstrings")); [print(k, "|", v["localizations"]["en"]["stringUnit"]["value"], "|", v["localizations"]["vi"]["stringUnit"]["value"]) for k, v in sorted(d["strings"].items()) if k.startswith(("terminal.needsUpdate", "terminal.connecting", "terminal.offline", "terminal.gone", "terminal.failed", "terminal.paste.tooLarge", "terminal.retry", "terminal.surface", "terminal.key.", "terminal.new", "workspace.menu.viewAs"))]'
grep -rnE '(Text|Button|Label)\(\s*"' shellx-ios/ShellX
```

Expected: 20 lines, then no output from `grep`. Put both in the hand-off, with the note that the iPhone no longer uses `workspace.shell.placeholder` and plan 3G removes it from the catalog.

- [ ] **Step 5: Whole-branch review.** Run a fresh review of `develop...feat/shellx-terminal-2c-ios` (superpowers:requesting-code-review, correctness first), pointing the reviewer at this plan's "Design" (R1–R12) and "Review Focus" and at plan 2A's "Wire specification". Fix what it finds (a behavioural bug gets its failing test committed first, CLAUDE.md), rerun Step 3, and commit fixes as `fix(shellx-ios): …`.

- [ ] **Step 6: USER live check on the iPhone** (S2 §5; the workspaces spec §2.2 criteria 3–5 and §11). It needs a Mac running plan 2B: check `git log develop --merges --oneline | grep -c "feat/shellx-terminal-2b-mac"`. If it prints `0`, stop here: the branch stays unmerged until 2B has landed and this check is done; go to Step 8 and report that landing waits for 2B and the live check. Otherwise hand this checklist to the user now; Claude never quits, relaunches or replaces the user's `/Applications/ShellX.app`.

**USER:**
1. Open the tagged Mac build **ShellX DEV terminal-2b-mac** (contracts §17; plan 2B Task 9 Step 2), signed in to your ShellX account. If it no longer exists, first rebuild it in the main checkout on `develop` with plan 2B Task 9 Step 1's `./scripts/reload.sh --tag terminal-2b-mac` command (never `--launch`). **For the measurements of items 5–7 use a Release build** (the base spec §11 asks for one; a Debug build can miss the 1 s target for no real reason): `./scripts/reload.sh --tag terminal-2b-mac --release` (never `--launch`). A Release build may not include the probe's debug pairing calls, so pair the iPhone by QR (item 2).
2. Unlock the iPhone 11 Pro, then run `shellx-ios/scripts/dev.sh device --device-id <id>` (`<id>` from `xcrun devicectl list devices`; it can be left out when `~/.config/shellx/iphone-device-id` holds it). The app arrives signed out: sign in. If the iPhone is not yet paired with ShellX DEV terminal-2b-mac (it is a Mac of its own, whose name ends in "(DEV …)", apart from `/Applications/ShellX.app`), pair it with that Mac's pairing QR code.
3. Turn Wi-Fi off on the iPhone (4G), so phone and Mac are on different networks over `relay.shellx.pro`.
4. On the Mac open Console.app, pick the iPhone, turn on Action › Include Info Messages (the latency lines are info-level), filter `subsystem:com.shellx.app category:latency`, press Start.
5. Criterion 3: open a workspace with two shell chips and swipe between them 20 times. Criterion 6: meanwhile the Mac keeps its selected workspace and tab, and no Mac window comes to the front.
6. Criterion 4: tap a terminal and type 20 single letters about a second apart.
7. Criterion 5: run `yes | head -100000`, then `head -c 5000000 /dev/urandom | base64`: the app keeps scrolling and swiping chips, the Mac stays responsive, and the last screen on the phone matches the Mac's.
8. Telex: switch to the Vietnamese keyboard (Telex) and type `echo "Tieengs Vieetj cos daaus"` then Return: the shell shows `echo "Tiếng Việt có dấu"`; while a word is underlined, Backspace edits it and nothing reaches the Mac until it is committed. VNI: `Tie61ng Vie65t` gives `Tiếng Việt`.
9. Key bar: esc; tab (completion); ctrl then `c` stops `sleep 100`; ↑ recalls the last command. The hide-keyboard key hides the keyboard.
10. `vim`: a finger swipe scrolls the file; `:q` returns to the shell with its history. `htop` after typing on the Mac (the Mac's size wins): the phone fits the width, a pinch zooms in, typing on the phone brings the phone's size back.
11. Long-press the terminal → Paste a two-line text: it arrives as one paste.
12. A Bluetooth keyboard (if one is at hand): letters, Return, Backspace, Tab, Esc, arrows, Ctrl+C.
13. The ＋ chip opens a new terminal, and the Mac's selected tab does not change. On an agent chip, ••• › View as Terminal shows its terminal; View as Chat goes back.
14. Send the app to the background: the Mac's terminal goes back to the Mac's size; come back: the terminal reopens.
15. In Console.app select the latency lines, copy them and save them as `~/Desktop/terminal-latency.txt`.

Then compute the numbers:

```bash
python3 - ~/Desktop/terminal-latency.txt <<'PY'
import math, re, sys
values = {}
for line in open(sys.argv[1], encoding="utf-8"):
    m = re.search(r"(terminalFirstScreen|terminalKeyEcho|terminalFrameApply) (\d+) ms", line)
    if m:
        values.setdefault(m.group(1), []).append(int(m.group(2)))
for name, v in sorted(values.items()):
    v.sort()
    rank = lambda f: v[min(max(math.ceil(f * len(v)), 1), len(v)) - 1]
    print(f"{name}: n={len(v)} p50={rank(0.5)} ms p95={rank(0.95)} ms max={v[-1]} ms")
PY
```

Targets: `terminalFirstScreen` p95 < 1 000 ms, `terminalKeyEcho` p95 < 300 ms, `terminalFrameApply` p95 < 16 ms. Append to `docs/superpowers/ledgers/shellx-mobile-workspaces.md` a section `## Đợt 2: terminal trên iPhone (plan 2C)` with a table `Số đo | n | p50 | p95 | Mục tiêu | Đạt?` and one line per checklist item 7–14 (đạt / chưa đạt, and what was wrong), commit it on this branch as `docs(shellx): terminal measurements on the iPhone`. A missed target or a failed item is reported to the user, not fixed silently; a fix goes on this branch (a behavioural bug gets its failing test first), then Step 3 runs again and the user repeats the checklist items it touches.

- [ ] **Step 7: Land on `develop`, only on the user's merge directive** (contracts §1, the rule for app and UI plans; CLAUDE.md "CI, review and merge"). This plan changes app UI and runtime, so it merges only after the review (Step 5), the USER live check (Step 6) and the user's explicit `merge`, `merge it` or `auto-merge` (not `finish`, `lgtm` or `ship it`). If no such directive was given, ask for one with the review summary (what changed, the results of Step 3, the review's findings and their fixes, the live-check numbers) and wait. Then, from the main checkout:

```bash
cd /Users/lehuuphu/Documents/myProjects/shellx
git checkout develop
git merge --no-ff feat/shellx-terminal-2c-ios -m "Merge branch 'feat/shellx-terminal-2c-ios' into develop"
shellx-ios/scripts/dev.sh test core       # expect: ==> test core: passed
git push origin develop
git worktree remove .worktrees/terminal-2c-ios
git branch -d feat/shellx-terminal-2c-ios
```

Never `main`, no deploy, no TestFlight or App Store upload.

- [ ] **Step 8: Report** to the user: the merge commit, or what landing still waits for (2B, the live check, the merge directive); the test counts of `test core` and `test app`; the verification results; the localization audit; the HIG pages read and the two deviations (fixed 12 pt font with pinch zoom instead of Dynamic Type; the hide-keyboard key), plus any page that could not be fetched; the live-check results or that they wait for 2B; and the Contract additions below for the orchestrator to copy into the contracts file.

---

## Spec notes

1. **Assembler tests.** S2 §5 puts the assembler and revision tests in `ShellXAppCore`; 2A put the assembler in `ShellXLinkCore` (its Spec note 1). 2C tests how the phone uses it: one resync per gap and a fresh assembler per view (`TerminalViewModelTests`).
2. **Key bar.** The base spec §6.2 and S2 §2 list esc, tab, ctrl, ←, ↑, ↓, →. The plan keeps that order and adds a trailing hide-keyboard key: a terminal has no other way to dismiss the keyboard while it has focus (HIG Virtual keyboards). Deviation recorded for the hand-off.
3. **View as Chat.** S2 §3.4 keeps "View agent pane as terminal"; the plan adds the reverse item, so an agent chip can go back to its chat without leaving the screen.
4. **Closing on background.** Base §7.2 closes the terminal when the app goes to the background; the plan closes it at once on `scenePhase == .background`, apart from the hub's 25 s session grace, and reopens it on `.active`.
5. **Font and zoom.** Base §10 sizes the phone's grid "with the app's default font size", and S2 §4 rules out changing the font from the phone: the grid is always computed at 12 pt and a pinch only zooms the drawing (fit … 2.0). This deviates from Dynamic Type (HIG Typography) on purpose; the deviation goes into the hand-off.
6. **Keyboard and size.** The keyboard showing or hiding changes the pane's rows, so the phone resizes (after 200 ms) and the Mac answers with a snapshot and its history fill (2A §11.8, at most 256 KiB each). Accepted, so full-screen programs fit above the keyboard.
7. **Criterion 5.** The spec gives no number for "the app does not hang"; the plan measures `terminalFrameApply` (p95 < 16 ms, one frame at 60 Hz) and the user checks the final screen.
8. **"Close this pane".** Base §6.2's item is the existing "Close Tab…" (S2 §3.4); nothing to build.
9. **＋ chip.** S2 §3.3 hides ＋ without `terminal_create`; the plan also dims it while the Mac is not online, like `•••`.
10. **Pager.** The workspace screen's `TabView` keeps neighbouring pages alive, so the terminal opened is the selected chip's (`WorkspaceScreenModel.terminalShown`), never any page that appears.
11. **Old-Mac text.** S2 §3.9's wording becomes the new key `terminal.needsUpdate`, which older Macs get; the iPhone stops using `workspace.shell.placeholder`, and plan 3G removes that key from the catalog when it lands.
12. **Ctrl with non-letters.** The protocol names no digit or punctuation key (2A Spec note 6), so ctrl latched before a digit or symbol types it plain; ctrl + space, Return and Tab are sent as keys.
13. **Alt on a hardware keyboard.** S2 §3.7 lists Ctrl+letter only; Option+letter goes through the text system (it types the Option character), while Option with arrows, Return or Backspace is sent as `alt`.
14. **Cursor.** Drawn steady; `blink` is ignored.
15. **Echo latency.** `terminalKeyEcho` ends at the next frame after typing, which may hold unrelated output (a log line): accepted noise for criterion 4.
16. **Plan 2B's host (contracts §17).** Base §10 assumes the phone never sees more than the size it asks for; 2B sends the Mac window's own size while the Mac owns it, which can pass 300 × 120, so the renderer and fit-to-width take any size up to 2A's 1 000. The Mac may hold the first snapshot up to 500 ms for the phone's size: the pane stays in its loading state and `terminalFirstScreen` counts the wait. A terminal the Mac lists but cannot view answers `failed`, shown like every failure (one retry, then Try Again).

## Contract additions

Names other plans need (2C cannot edit the contracts; the orchestrator copies them into the next free section, §18 "Additions from plan 2C"):

- **View name.** The iPhone's terminal page is `TerminalPane` (`shellx-ios/ShellX/UI/Terminal/TerminalPane.swift`), the name §5 gives the Android slot.
- **Rules 3G mirrors** (Kotlin style, in `:core`): `TerminalViewModel` with rules R1–R12 of this plan's "Design" and its constants (resize 200 ms after the last change; `busy` retried every 300 ms, 5 times; one retry of a failed open after 1 s; alternate-screen scroll summed for 50 ms; echo dropped after 2 s), `TerminalViewPhase` (`connecting`, `live`, `offline`, `unsupported`, `unavailable(gone | refused | failed)`); `TerminalTyping` (committed text only, composing text local, Backspace edits the composition, ctrl latch rules, line break → `enter`, tab → `tab`, other control characters dropped); `TerminalInputBatcher` (`messages`, `pasteUnits`, `scrollUnits`, `maxPasteBytes` 262 144, `pasteFits`; a paste over the limit is refused with `terminal.paste.tooLarge`, R12); `TerminalBarKey` order `escape, tab, ctrl, left, up, down, right` plus the UI's trailing hide-keyboard key; hardware keys with the actions of `TerminalHardwareKeys` (Android maps `KeyEvent` codes); `TerminalGeometry` (padding 4, the phone grid at the default 12-point monospace font, fit-to-width, zoom between fit and 2) and `TerminalZoom`; `TerminalColors` (inverse swaps with the defaults, faint halfway to the background, invisible draws no text).
- **Hub calls** (iPhone `MachineHub`; Android's 3C/3G hub mirrors them): `terminalEvents()` → `TerminalHubEvent.push(machineID, TerminalViewPush)` / `.state(machineID, MachineLinkState)`; `isOnline`, `supportsTerminalView`, `supportsTerminalCreate`; `openTerminalView(machineID, terminalId, cols, rows)` → `TerminalOpenResult` (`outcome`, `notSent`, `noAnswer`); `closeTerminalView`, `sendTerminalInput`, `resizeTerminalView`, `resyncTerminalView`; `createTerminal(WorkspaceRef)` → `(result: WorkspaceCommandResult, terminalId)`; `recordLatency`. The seam is `TerminalLink`.
- **Workspace screen.** `WorkspaceScreenModel.shownAsTerminal`, `showAsTerminal(_:_:)`, `terminalShown`, `expect(_:)`; `WorkspaceMenuItem.viewAsTerminal`, `.viewAsChat`; `WorkspaceCommand.createTerminal` (`.notFound` → refresh, `.refused` → "Mac is blocking remote control").
- **Latency metrics.** `LatencyMetric.terminalFirstScreen` (from the swipe or tap to the first applied snapshot, the Mac's wait of up to 500 ms for the size included), `.terminalKeyEcho`, `.terminalFrameApply` (p95 targets 1 000, 300 and 16 ms).
- **Demo.** `DemoTerminalFixture`, `DemoTerminalScreens` (`palette`, `styles`, `xterm256(base:)`, markup `runs(_:)`, `shell`, `shellTyping`, `devServer`, `wide`, `vim`, `htop`, `agent`, `prompt(cols:rows:)`) in the demo target (`ShellXDemo` after 1C); the demo Mac's mapping `demo-shellx-t1` and `demo-web-t1` → `agent`, `demo-shellx-t2` → `shell`, `demo-relay-t1` → `devServer`, `demo-notes-t1` → `wide`; `FakeMac` terminal API (`servesTerminalViews`, `acceptsTerminalCreate`, `setTerminalFixtures`, `refuseTerminalView`, `hold/releaseTerminalViewOpens`, `emitTerminalFrame`, `endTerminalView`, `setNextTerminalCreateOutcome`, `terminalViewOpens`, `terminalViewResizes`, `terminalViewCloses`, `terminalViewInputs`, `terminalViewSnapshotRequests`, `terminalCreates`; new tabs are `<workspaceId>-new-<n>`) and the fake shell of Task 1 (3C's demo port takes these with the rest of the demo).
- **Strings** (Android imports them, contracts §5): `terminal.needsUpdate`, `terminal.connecting`, `terminal.offline`, `terminal.gone`, `terminal.failed`, `terminal.paste.tooLarge`, `terminal.retry`, `terminal.surface.label %@`, `terminal.key.escape`, `terminal.key.tab`, `terminal.key.ctrl`, `terminal.key.ctrl.latched`, `terminal.key.left`, `terminal.key.up`, `terminal.key.down`, `terminal.key.right`, `terminal.key.hideKeyboard`, `terminal.new`, `workspace.menu.viewAsTerminal`, `workspace.menu.viewAsChat`. 20 keys in all. `workspace.shell.placeholder` is no longer used by the iPhone; plan 3G removes it from the catalog when it lands (older Macs get `terminal.needsUpdate`).

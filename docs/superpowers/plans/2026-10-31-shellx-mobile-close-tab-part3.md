# ShellX mobile close-tab (part 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From the iPhone, "Close Tab…" closes **any** terminal tab of a local workspace on the Mac (agent or plain shell, whatever runs in it), after a confirmation.

**Architecture:** the same shape as part 2's `agent.close`, keyed by the ids the phone already has from `workspace.list`.
- **Protocol:** feature `terminal_close`; call `terminal.close` (`call_id`, `workspace_id`, `terminal_id`); answer `terminal.close.result` (`call_id`, `outcome`), reusing `WorkspaceControlOutcome`.
- **Mac:** `ShellXLinkWorkspaceSource` also conforms to a new `TerminalControl`. It checks the terminal is in a workspace it lists, then closes it through the existing `Control.closeSurface` (`v2MobileAgentSurfaceClose`, which already applies the last-tab rule).
- **iPhone:** `MachineHub.closeTerminal`; the workspace screen's `•••` gets "Close Tab…" for the chip shown (it replaces "Close Agent…" there), and a long-press on any chip offers "Close Tab…". Always confirmed first.

**Spec:** `docs/superpowers/specs/2026-10-29-shellx-mobile-home-focus-design.md` §6.6 (user decision 2026-10-31). Builds on part 2 (`2026-10-29-shellx-mobile-home-focus-part2-close-agent.md`), already on this branch.

## Global Constraints

- Branch `feat/shellx-mobile-home-focus`; repo root for paths is the worktree `.claude/worktrees/shellx-home-focus`.
- Wire names: feature `terminal_close`; `terminal.close` with `call_id`, `workspace_id`, `terminal_id` (all non-empty strings; `call_id` required as for every call); `terminal.close.result` with `call_id`, `outcome`; outcomes `ok`, `not_found`, `refused`, `failed`, any other string kept as `.other`.
- Never resend `terminal.close` after a lost link or a timeout (PROTOCOL.md §7).
- Outcomes on the Mac:
  - **`not_found`:** either id is not a UUID, or the terminal is not a terminal of a workspace the Mac lists (SSH and other remote workspaces are never listed), or it is gone by the time the Mac acts.
  - **`refused`:** `MobileRemoteControlPolicy.isDisabled`, or the Mac's own rule forbids it (`protected`, `invalid_state`, `denied`: pinned workspace, last workspace of a window, or last tab with "Keep Workspace Open When Closing Last Surface" on).
  - **`failed`:** anything else.
- Unlike `agent.close`, there is no live-agent check: the user picked this tab explicitly. `agent.close` keeps its own rules unchanged.
- Closing does not ask on the Mac (`force: true`); last tab of a workspace → the workspace closes when the close-last-surface preference is on (default), else `refused` — exactly `v2MobileAgentSurfaceClose`'s existing behaviour.
- Do not log workspace ids, terminal ids or titles.
- Mac tests only through `scripts/shellx/test-app.sh <Suite>`; never bare `xcodebuild`; never launch, quit or replace any app.
- New iPhone strings in `shellx-ios/ShellX/Localizable.xcstrings` with `en`, `vi` and comments; `check-strings.py` must pass.
- Commit each failing test before its fix; stage files by explicit path.

## Review Focus

- **A tab in an SSH/remote workspace, or a terminal id from another workspace:** `not_found`, nothing closes. Pinned in Task 2.
- **Old Mac (no `terminal_close`):** no "Close Tab…" anywhere and nothing is sent (count frames as part 2 Task 4 does). Pinned in Tasks 3 and 4.
- **Double tap / menu while long-press close is in flight:** exactly one `terminal.close` reaches the Mac. Pinned in Task 4.
- **Last tab:** the workspace closes (default), or `refused` with keep-open on. Already pinned for `v2MobileAgentSurfaceClose` in part 2; Task 2 only checks the outcome passes through.

---

### Task 1: `terminal.close` in shellx-link (messages, host, client, probe, PROTOCOL.md)

**Files:** follow part 2's Tasks 1 and 2 file by file (`ShellXLink.swift`, `LinkMessage.swift`, `LinkCodec.swift`, `spec/vectors/messages.json`, `ShellXLinkSession/LinkHost.swift`, `LinkClient.swift`, new `ShellXLinkSession/TerminalControl.swift`, probe `main.swift` + `Commands.swift` + README usage, `Tests/ShellXLinkCoreTests/LinkCodecTests.swift`, `Tests/ShellXLinkSessionTests/FakeWorkspaceSource.swift`, `Tests/ShellXLinkSessionTests/WorkspaceSessionTests.swift`, `spec/PROTOCOL.md`).

**Interfaces (produces):**
- `ShellXLink.terminalCloseFeature = "terminal_close"`.
- `LinkMessage.terminalClose(callId: String, workspaceId: String, terminalId: String)` (wire `terminal.close`) and `LinkMessage.terminalCloseResult(callId: String, outcome: WorkspaceControlOutcome)` (wire `terminal.close.result`).
- ```swift
  /// Closes one terminal tab of a workspace the host lists. A host that has one offers `terminal_close`.
  public protocol TerminalControl: Sendable {
      /// `.notFound` for a terminal that is not in a workspace the host lists; `.refused` when remote control is
      /// blocked or the host's rule forbids it; `.failed` when it could not act.
      func closeTerminal(workspaceId: String, terminalId: String) async -> WorkspaceControlOutcome
  }
  ```
- `LinkHost.init(…, terminalControl: (any TerminalControl)? = nil, …)` on both inits; advertises `terminal_close` only with it; without it `terminal.close` gets `error unsupported` with the `call_id`; each call runs in `group.addTask`; a client-sent `terminal.close.result` is `bad_request`.
- `LinkClient.closeTerminal(workspaceId: String, terminalId: String) async throws -> WorkspaceControlOutcome` (doc: never resend).
- Probe `shellx-link-probe terminal-close <workspace_id> <terminal_id>`, exit 2 unless `ok`.

- [ ] **Step 1: failing tests and vectors.** `testTerminalCloseRoundTrip` (wire `t`, both id keys, `call_id` required on encode and decode, missing `terminal_id` → `badJSON(callId:)`); feature constant; vectors `terminal_close` `{"t":"terminal.close","call_id":"c90","workspace_id":"ws-1","terminal_id":"t-1"}`, `terminal_close_result_ok`, `terminal_close_result_not_found`; in `WorkspaceSessionTests`: `testWelcomeListsTerminalCloseOnlyWithControl`, `testTerminalCloseUnsupportedWithoutControl`, `testTerminalCloseReachesControl` (fake records `[("ws-1","t-1")]`, returns `.ok`, `.notFound`, `.refused`, `.other("busy")` in turn), `testSlowTerminalCloseDoesNotBlockTheSession`, `testTerminalCloseResultFromAClientIsBadRequest`.
- [ ] **Step 2:** run `toknix run swift test --package-path shellx-link`, confirm compile-red; commit red.
- [ ] **Step 3: implement**, and PROTOCOL.md: message table rows, call_id/answer lists, features list, outcomes, §8 golden table and case count, the error-codes `unsupported` sentence, §10 "Allowed calls" row, and a §10 "Tabs" paragraph answering the three questions (command/content execution: none — two ids only; unowned objects: none — only a terminal of a local workspace the host lists, never SSH/remote; local state exposed: none), plus: no live-agent check by design (the user chose the tab), the last-tab rule, MDM `refused`, no ids/titles in logs.
- [ ] **Step 4:** `toknix run swift test --package-path shellx-link` and `toknix run swift build --package-path shellx-link --product shellx-link-probe` green.
- [ ] **Step 5:** commit `feat(shellx-link): terminal.close for phones`.

### Task 2: Mac closes a listed terminal tab

**Files:** `Sources/ShellX/Remote/Link/ShellXLinkWorkspaceSource.swift`, `Sources/ShellX/Remote/Link/ShellXLinkHostController.swift`, `Sources/ShellX/Remote/ShellXRemoteService+App.swift`; test `cmuxTests/ShellXLinkWorkspaceSourceTests.swift`.

**Interfaces:** consumes Task 1 `TerminalControl`. Produces `ShellXLinkWorkspaceSource: …, TerminalControl` with `closeTerminal(workspaceId:terminalId:)`:
- `isBlocked()` → `.refused`;
- either id not a UUID → `.notFound`;
- `refresh()`, then not `isListed(workspace, terminal:)` → `.notFound`;
- else `outcome(of: control.closeSurface(ws, t), action: "close-terminal")`, `refresh()` on `.ok`.
Wiring: `terminalControl: workspaces` (same instance) through `ShellXLinkHostController` into `LinkHost`.

- [ ] **Step 1: failing tests:** `closeTerminalClosesItsListedSurface` (recorder `[(W, T)]`, `.ok`); `closeTerminalOnAnUnlistedSurfaceIsNotFound` (terminal of another workspace; listed terminal under an unlisted workspace; nothing closes); `closeTerminalWithGarbledIdsIsNotFound`; `closeTerminalBlockedIsRefused`; `closeTerminalErrorMapsToOutcome` (parameterized: `not_found` → `.notFound`; `protected`, `invalid_state`, `denied` → `.refused`; `internal_error` → `.failed`); `closeTerminalNeedsNoAgent` (a listed shell terminal with no agent session closes).
- [ ] **Step 2:** `toknix run scripts/shellx/test-app.sh ShellXLinkWorkspaceSourceTests` → red; commit red.
- [ ] **Step 3:** implement and wire.
- [ ] **Step 4:** `toknix run scripts/shellx/test-app.sh ShellXLinkWorkspaceSourceTests ShellXLinkHostPolicyTests` green.
- [ ] **Step 5:** commit `feat(shellx): close a listed terminal tab for a phone`.

### Task 3: iPhone hub sends `terminal.close`

**Files:** `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Link/MachineHub.swift`; fakes `ShellXAppTestSupport/FakeMac.swift`, `FakeMacWorkspaces.swift`; test `Tests/ShellXAppCoreTests/MachineHubWorkspaceTests.swift`.

**Interfaces:** `public func supportsTerminalClose(_ machineID: String) -> Bool`; `public func closeTerminal(_ machineID: String, workspaceId: String, terminalId: String) async -> WorkspaceCommandResult` through `workspaceCommand(feature: ShellXLink.terminalCloseFeature)` (`.offline` when not online, `.failed` without the feature and nothing sent, `.unknown` on lost link/timeout, never resent). Fake: `FakeMac(…, acceptsTerminalClose: Bool = true)`, `terminalCloses: [(workspaceId: String, terminalId: String)]`, `setNextTerminalCloseOutcome(_:)`; on `.ok` the fake removes that terminal from its workspace (and the workspace when it was its last terminal) and publishes the change, the way the Mac's list update reports it; `holdWorkspaceControl()` holds it too.

- [ ] **Step 1: failing tests:** `testCloseTerminalCallsTheMacAndTheTabGoes`; `testCloseTerminalOutcomesMapToResults`; `testCloseTerminalWithoutTheFeatureSendsNothing` (use `phoneFrameCount` like `testCloseAgentWithoutTheFeatureIsFailedWithoutCalling`); `testCloseTerminalOfflineMacIsOffline`; `testCloseTerminalIsSentOnce`; `testSupportsTerminalCloseFollowsTheFeature`.
- [ ] **Step 2:** `toknix run swift test --package-path shellx-ios/Packages/ShellXAppCore --filter MachineHubWorkspaceTests` → red; commit red.
- [ ] **Step 3–4:** implement; full package green (known pre-existing flake in older `MachineHubWorkspaceTests`: rerun once, report).
- [ ] **Step 5:** commit `feat(shellx-ios): hub closes a terminal tab on its Mac`.

### Task 4: iPhone "Close Tab…" in the workspace menu and on a chip's long-press

**Files:** `shellx-ios/ShellX/UI/Workspaces/WorkspaceScreen.swift`, `WorkspaceView.swift`, `PaneChips.swift`, `WorkspaceFeedback.swift`, `WorkspaceListView.swift` (`WorkspaceListActions`), `shellx-ios/ShellX/Localizable.xcstrings`; tests `shellx-ios/ShellXTests/WorkspaceViewTests.swift`, `WorkspaceRenderTests.swift`, `WorkspaceListActionsTests.swift`, `WorkspaceListRenderTests.swift`.

**Behaviour:**
- `WorkspaceMenuItem`: `.closeAgent` becomes `.closeTab`; `items(canCloseTab:)` → `[.rename, .closeTab, .closeWorkspace]` or without `.closeTab`. Shown for the chip shown (agent or shell) when `hub.supportsTerminalClose(machineID)` and the Mac is online (disabled offline, like the other items). Remove `WorkspaceView.closableAgent`'s use in this menu (keep the agent screen's "Close Agent…" and the home swipes from part 2 untouched).
- `PaneChips`: every chip gets `.contextMenu` with "Close Tab…" when closing is supported (an optional `close: ((WorkspacePane) -> Void)?`; nil → no context menu item).
- One confirmation (`confirmationDialog`): title `terminal.close.title %@` with `PaneChips.label(for:)`, message `terminal.close.confirm`, one destructive button `terminal.close`.
- `WorkspaceCommand.closeTab`; feedback: `.ok` → `.nothing`; `.notFound` → `.alert(.tabNotClosable)`; `.refused` → `.alert(.refusedCloseTab)`; the rest as for the other commands.
- One send path in `WorkspaceListActions.closeTab(machineID:workspaceId:terminalId:)` with a per-(machine, terminal) in-flight set shared by the menu and the long-press.
- Closing the shown chip's tab: the screen moves to the next chip when the list update arrives; when the workspace itself closes, the existing closed-workspace handling applies.

**Strings (en / vi, with comments):**

| Key | en | vi |
| --- | --- | --- |
| `terminal.close` | Close Tab | Đóng tab |
| `terminal.close.menu` | Close Tab… | Đóng tab… |
| `terminal.close.title %@` | Close tab %@? | Đóng tab %@? |
| `terminal.close.confirm` | The tab and everything running in it on the Mac will be stopped. If it is the workspace's last tab, the workspace closes too. | Tab và mọi thứ đang chạy trong nó trên Mac sẽ bị dừng. Nếu đó là tab cuối của workspace, workspace cũng đóng theo. |
| `workspaces.alert.tabNotClosable` | The Mac can't close this tab: it is no longer there. | Mac không đóng được tab này: tab không còn trên Mac. |
| `workspaces.alert.refused.closeTab` | The Mac won't close this tab: remote control is blocked, or it's the last tab of a workspace that is pinned, the last in its window, or set to stay open. | Mac không cho đóng tab này: điều khiển từ xa đang bị chặn, hoặc đó là tab cuối của một workspace đang ghim, là workspace cuối của cửa sổ, hoặc được đặt để giữ lại. |

`agent.close.menu` stays in the catalog only if still used (the agent screen uses it); remove nothing else.

- [ ] **Step 1: failing tests:** `WorkspaceViewTests`/`WorkspaceRenderTests`: `items(canCloseTab: true) == [.rename, .closeTab, .closeWorkspace]`, `false` → `[.rename, .closeWorkspace]`; `WorkspaceListActionsTests.testCloseTabAsksTheMacOnce` (second call while the first is held sends nothing); `testCloseTabTheMacCannotCloseIsAnAlert` (`.notFound` → `.tabNotClosable`); `testCloseTabTheMacRefusesSaysWhy`; `testAMacWithoutTerminalCloseOffersNoCloseTab`; `WorkspaceListRenderTests.testFeedbackFollowsTheMacsAnswer` extended with `.closeTab` rows.
- [ ] **Step 2:** `toknix run shellx-ios/scripts/dev.sh test app` → red; commit red.
- [ ] **Step 3:** implement controls, confirmation, alerts, strings (follow Apple HIG Menus / Context menus / Action sheets).
- [ ] **Step 4:** `toknix run shellx-ios/scripts/dev.sh test all` green.
- [ ] **Step 5:** commit `feat(shellx-ios): close any tab from the phone`.

### Task 5: Dogfood

- [ ] Rebuild the tagged Mac app (`reload.sh --tag push-needs-you`, no launch) and reinstall the iPhone app (`shellx-ios/scripts/dev.sh device --device-id 51B0EA4F-D2C2-56A2-AC2B-3CD87DBAC107`). Checklist: close a shell tab running a dev server from the `•••`; long-press another chip → Close Tab…; close the last tab of a workspace; an SSH workspace tab is never offered/answers not_found; regular old ShellX shows no "Close Tab…".

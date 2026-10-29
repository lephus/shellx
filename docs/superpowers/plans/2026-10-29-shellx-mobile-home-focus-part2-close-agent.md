# ShellX mobile close-agent (part 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From the iPhone, "Close" shuts one agent down for real on the Mac. The Mac closes the terminal tab the agent runs in, and the session moves to "Ended".

**Architecture:**
- **Protocol:** ShellX Link gains a feature `agent_close` and a call `agent.close` (`call_id`, `session_id`), answered by `agent.close.result` (`call_id`, `outcome`). It reuses `WorkspaceControlOutcome`.
- **Mac:** `ShellXLinkWorkspaceSource` already lists the local workspaces and runs the workspace commands. It now also conforms to a new `AgentControl` protocol.
  - It resolves the session's surface and checks that the agent is alive and in a listed local workspace.
  - It then closes the surface in-process with `force: true`, or closes the workspace when that surface is its last one. This is what the desktop's Close Tab does by default.
- **iPhone:** `MachineHub.closeAgent` follows the workspace commands' send-once rule. The UI offers it on a swipe and in the agent and workspace menus, always after a confirmation.

**Tech Stack:** Swift 6, SwiftPM (`shellx-link`, `ShellXAppCore`), SwiftUI, XCTest and Swift Testing (`cmuxTests`), JSON golden vectors.

**Spec:** `docs/superpowers/specs/2026-10-29-shellx-mobile-home-focus-design.md` §6.5, §7 "Phần 2", §8. It builds on part 1 (`2026-10-29-shellx-mobile-home-focus-part1.md`), which must land first.

## Global Constraints

- All paths are relative to the repo root `/Users/lehuuphu/Documents/myProjects/shellx`. Use the same branch as part 1, or a branch on top of it.
- Wire names:
  - feature `agent_close`;
  - `agent.close` with `call_id`, `session_id`;
  - `agent.close.result` with `call_id`, `outcome`;
  - outcomes `ok`, `not_found`, `refused`, `failed`, plus any other string kept as `.other`.
- Never resend `agent.close` after a lost link or a timeout, the same as the workspace commands (PROTOCOL.md §7).
- Outcomes:
  - **`not_found`:** the session is unknown, ended, has no known live pid, has no surface, or its surface is not a terminal of a workspace the Mac lists (SSH and other remote workspaces are never listed).
  - **`refused`:** `MobileRemoteControlPolicy.isDisabled`, or the Mac's own rule forbids it (`protected`, or the last workspace of a window).
  - **`failed`:** anything else.
- A live agent means:
  - a Claude Code record that is not `.ended`;
  - its `pid` is known and alive;
  - this is the same rule as `ShellXLinkChatSource.hasLiveAgent`. After the agent exits, its terminal runs the user's shell, and that must never be closed by this call.
- Closing does not ask on the Mac: the phone already confirmed. Pass `force: true`.
- When the surface is its workspace's last surface and `TabManager.closeWorkspaceOnLastSurfacePreferenceEnabled()` is true (the desktop default), close the workspace instead, with `v2MobileWorkspaceClose(params: ["workspace_id": id, "force": true])`. When that preference is off, answer `refused`.
- New `cmuxTests/*.swift` files need `./scripts/sync-test-wiring`. Name them `ShellXLink*Tests.swift` so CI's ShellX Mac lane picks them up.
- Run Mac tests only through `scripts/shellx/test-app.sh <Suite>`. Never run bare `xcodebuild`, and never quit, relaunch or replace the user's running ShellX (`build-shellx/…/Release/ShellX.app`).
- New iPhone strings go in `shellx-ios/ShellX/Localizable.xcstrings` with `en` and `vi`, and `check-strings.py` must pass.
- This is a behavioral change with a security surface. Commit each failing test before its fix (CLAUDE.md, "Reproduce and repair"), and record the red and green runs in the PR.

## Review Focus

- **The agent's tab is its workspace's last tab.** By default the whole workspace closes, as with ⌘W on the desktop. With "Keep Workspace Open" on, the Mac refuses. Pinned in Task 3.
- **The agent exited a moment ago.** Its tab now runs the user's shell, and the Mac must answer `not_found` without closing anything. Pinned in Task 3.
- **Session on an SSH workspace.** It is listed in `agent.sessions` but its workspace is not in `workspace.list`, so the answer is `not_found` and nothing closes. Pinned in Task 3.
- **A double tap, or swipe-close while the agent screen's close is in flight.** Exactly one `agent.close` reaches the Mac. Pinned in Task 4, `testCloseAgentIsSentOnce`, and Task 5.
- **An old Mac (1.5.1 or wave 1 without `agent_close`).** No close control shows anywhere, and the hub never sends the call. Pinned in Tasks 4 and 5.

---

### Task 1: `agent.close` messages in ShellXLinkCore

**Files:**
- Modify:
  - `shellx-link/Sources/ShellXLinkCore/ShellXLink.swift:21-22`: add the feature constant next to `workspaceControlFeature`;
  - `shellx-link/Sources/ShellXLinkCore/Messages/LinkMessage.swift:50-51`: the two cases;
  - `shellx-link/Sources/ShellXLinkCore/Messages/LinkCodec.swift`: the `T` table at lines 18-37, a body struct near line 80, `encode` at lines 119-231, `decode` at lines 233-349;
  - `shellx-link/spec/vectors/messages.json`: three vectors after `workspace_close_result_refused`, around line 1637;
  - `shellx-link/spec/PROTOCOL.md`: the call_id list at lines 81-82, the answer list at line 89, the message table at lines 137-138, the features list at line 183, the outcomes at lines 354-356, the §8 golden table at lines 584-585.
- Test: `shellx-link/Tests/ShellXLinkCoreTests/LinkCodecTests.swift`. Add the new vector cases in `message(from:_:)` near line 745, and new tests next to `testWorkspaceControlRoundTrip` at line 458.

**Interfaces:**
- Produces:
  - `ShellXLink.agentCloseFeature = "agent_close"`.
  - `LinkMessage.agentClose(callId: String, sessionId: String)`, wire `agent.close`.
  - `LinkMessage.agentCloseResult(callId: String, outcome: WorkspaceControlOutcome)`, wire `agent.close.result`.

- [ ] **Step 1: Write the failing tests and vectors**

  - `testAgentCloseRoundTrip` round-trips both messages and checks the wire `t` strings and the `session_id` key. It also checks that `call_id` is required, so decoding without it is an error.
  - Extend `testWorkspaceConstants`, or add `testAgentCloseFeature`, asserting `"agent_close"`.
  - Add these vectors:
    - `agent_close`: `{"t":"agent.close","call_id":"c78","session_id":"sess-1"}`;
    - `agent_close_result_ok`;
    - `agent_close_result_not_found`.
- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `toknix run swift test --package-path shellx-link --filter LinkCodecTests`
  Expected: compile errors, since `agentClose` is undefined.
- [ ] **Step 3: Implement the cases, the codec entries and the PROTOCOL.md rows**

  Follow the `workspaceClose` pattern and reuse `WorkspaceOutcome` for the result body. In PROTOCOL.md's semantics after line 292, add this paragraph: "`agent.close` closes the terminal tab of a live agent session the host lists in a local workspace, without asking; on its workspace's last tab the Mac does what its Close Tab does (by default closes the workspace). `not_found` for an unknown, ended or tab-less session."
- [ ] **Step 4: Run the tests and confirm they pass**

  Run: `toknix run swift test --package-path shellx-link`
  Expected: PASS. `RelayIntegrationTests` skip without `CMUX_RELAY_BIN`; say so in the PR.
- [ ] **Step 5: Commit**

  Commit the failing test first, then the code. Final message: `feat(shellx-link): agent.close messages`.

### Task 2: `LinkHost`/`LinkClient` serve `agent_close`, PROTOCOL.md §10, probe

**Files:**
- Create: `shellx-link/Sources/ShellXLinkSession/AgentControl.swift`
- Modify:
  - `shellx-link/Sources/ShellXLinkSession/LinkHost.swift`:
    - stored property near line 19;
    - both inits at lines 36-64;
    - features at lines 149-159;
    - `converse`, a branch beside lines 384-392 and the exhaustive list at lines 398-402.
  - `shellx-link/Sources/ShellXLinkSession/LinkClient.swift`:
    - `closeAgent` after line 408;
    - the waiter group at lines 519-523, not the `break` group at lines 548-550.
  - `shellx-link/spec/PROTOCOL.md` §10:
    - an "Allowed calls" row after line 689;
    - an "Agents" paragraph beside "Workspaces" at lines 752-773.
  - `shellx-link/Sources/shellx-link-probe/main.swift` (usage at lines 12-31, dispatch at lines 81-119), `shellx-link/Sources/shellx-link-probe/Commands.swift` (beside `chatStop`, lines 194-208), and the probe usage in `shellx-link/README.md`.
  - `shellx-link/Tests/ShellXLinkSessionTests/FakeWorkspaceSource.swift`: add `FakeAgentControl`.
- Test: `shellx-link/Tests/ShellXLinkSessionTests/WorkspaceSessionTests.swift`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - In `AgentControl.swift`:

    ```swift
    /// Closes an agent session's terminal on the host. A host that has one offers `agent_close`.
    public protocol AgentControl: Sendable {
        /// `.notFound` for a session the host does not list as a live agent in a local workspace;
        /// `.refused` when remote control is blocked or the host's rule forbids it; `.failed` when it could not act.
        func closeAgent(sessionId: String) async -> WorkspaceControlOutcome
    }
    ```
  - `LinkHost.init(…, agentControl: (any AgentControl)? = nil, …)`, on the public init and on the internal `timings:` init. With it the host advertises `agent_close`. Without it, `agent.close` gets `error unsupported` with the `call_id`. Each call runs in `group.addTask`.
  - `LinkClient.closeAgent(sessionId: String) async throws -> WorkspaceControlOutcome`.
  - Probe command `shellx-link-probe agent-close <session_id>`. It exits 2 unless the outcome is `ok`.

- [ ] **Step 1: Write the failing tests**

  In `WorkspaceSessionTests`:
  - `testWelcomeListsAgentCloseOnlyWithControl`;
  - `testAgentCloseUnsupportedWithoutControl`, expecting `LinkClientError.remote(code: "unsupported", …)`;
  - `testAgentCloseReachesControl`, where the fake records `["sess-1"]` and returns `.ok`, `.notFound`, `.refused` and `.other("busy")` in turn;
  - `testSlowAgentCloseDoesNotBlockTheSession`, modelled on `testSlowControlDoesNotBlockTheSession` with a held `Gate`.
- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `toknix run swift test --package-path shellx-link --filter WorkspaceSessionTests`
  Expected: compile errors.
- [ ] **Step 3: Implement the host, the client, the probe and PROTOCOL.md §10**

  The §10 "Agents" paragraph answers the three questions the "Workspaces" paragraph answers:
  - **Command or content execution:** none. The call carries only a session id.
  - **Unowned objects:** none. It only reaches a live Claude Code agent the host lists, in a local workspace it lists, and never an SSH or remote one.
  - **Local state exposed:** none.

  It also states the shell fall-through rule (no close once the agent has ended), the last-tab rule, the MDM `refused`, and "no session titles in logs". Line 774's note that the `cmux ssh` relay allowlist does not change stays true.
- [ ] **Step 4: Run the tests and the probe build, and confirm they pass**

  Run: `toknix run swift test --package-path shellx-link` and `toknix run swift build --package-path shellx-link --product shellx-link-probe`
  Expected: PASS and a green build.
- [ ] **Step 5: Commit**

  Red first, then `feat(shellx-link): serve agent.close to phones`.

### Task 3: Mac closes a live agent's tab

**Files:**
- Modify: `Sources/ShellX/Remote/Link/ShellXLinkWorkspaceSource.swift`:
  - conformance at lines 27-28;
  - `Control` at lines 36-57;
  - a `closeAgent` beside `closeWorkspace` at lines 141-147;
  - `outcome(of:action:)` at lines 168-180, which now maps `"invalid_state"` and `"denied"` to `.refused`.
- Modify: `Sources/TerminalController+MobileTerminalLifecycle.swift`. Add `func v2MobileAgentSurfaceClose(workspaceID: UUID, surfaceID: UUID) -> V2CallResult` beside `v2MobileTerminalClose` (lines 14-50).
- Modify: `Sources/ShellX/Remote/Link/ShellXLinkChatSource.swift:230-240`. Make `hasLiveAgent`'s rule reusable: a `static func isLiveAgent(_ record: AgentChatSessionRecord) -> Bool` used by both sources. Change the instance method to call it, without changing its behavior.
- Modify: `Sources/ShellX/Remote/Link/ShellXLinkHostController.swift` (fields at lines 43-57, init at lines 73-92, launch at lines 125-139, `serve` at lines 234-279) and `Sources/ShellX/Remote/ShellXRemoteService+App.swift:55-67`. Pass `agentControl: workspaces`, the same `ShellXLinkWorkspaceSource` instance.
- Test: `cmuxTests/ShellXLinkWorkspaceSourceTests.swift`, beside the control tests at lines 291-379, extending its `FakeMac` recorder at lines 409-449.

**Interfaces:**
- Consumes: Task 2 `AgentControl`.
- Produces:
  - `ShellXLinkWorkspaceSource: WorkspaceSource, WorkspaceControl, AgentControl`.
  - `Control` gains:
    - `agentSurface: @MainActor @Sendable (_ sessionId: String) -> (workspaceId: UUID, surfaceId: UUID)?`, nil unless the record is a live agent with a surface and a workspace. The live implementation uses `TerminalController.shared.agentChatTranscriptService.sessionRecord(sessionID:)` and `ShellXLinkChatSource.isLiveAgent`.
    - `closeSurface: @MainActor @Sendable (_ workspaceId: UUID, _ surfaceId: UUID) -> V2CallResult`. The live implementation is `v2MobileAgentSurfaceClose`.
  - `closeAgent(sessionId:)`:
    - `isBlocked()` → `.refused`;
    - `agentSurface` nil → `.notFound`;
    - after `refresh()`, no published workspace with `workspaceId == ws.uuidString` holding a terminal whose `terminalId == surface.uuidString` → `.notFound`;
    - otherwise `outcome(of: closeSurface(…), action: "close-agent")`, and `refresh()` on `.ok`.
  - `v2MobileAgentSurfaceClose`:
    - resolve the workspace; `not_found` when it is missing;
    - when the surface is its last panel, return `v2MobileWorkspaceClose(params: ["workspace_id": workspaceID.uuidString, "force": true])` if `tabManager.closeWorkspaceOnLastSurfacePreferenceEnabled()`, else `.err(code: "protected", …)`;
    - otherwise call `controlSurfaceClose(routing: ControlRoutingSelectors(hasWindowIDParam: false, windowID: nil, groupID: nil, workspaceID: workspaceID, surfaceID: surfaceID, paneID: nil), surfaceID: surfaceID, hasSurfaceIDParam: true, force: true)` and map the result:
      - `.closed` → `.ok`;
      - `.surfaceNotFound`, `.workspaceNotFound` or `.invalidSurfaceID` → `not_found`;
      - `.lastSurface` (a race) or `.denied` → `protected`;
      - anything else → `internal_error`.

- [ ] **Step 1: Write the failing tests**

  In `ShellXLinkWorkspaceSourceTests`:
  - `closeAgentClosesItsListedSurface`: the snapshot has workspace W with terminal T, `agentSurface("s1") == (W, T)`, and `closeSurface` returns `.ok`. Expect `.ok`, with the recorder holding `[(W, T)]`.
  - `closeAgentNotLiveIsNotFound`: `agentSurface` returns nil. Expect `.notFound` and no close.
  - `closeAgentOnAnUnlistedSurfaceIsNotFound`: the surface is in no snapshot workspace, as with SSH. Expect `.notFound` and no close.
  - `closeAgentBlockedIsRefused`: `isBlocked` is true. Expect `.refused` and no close.
  - `closeAgentErrorMapsToOutcome`, parameterized:
    - `not_found` → `.notFound`;
    - `protected`, `invalid_state` and `denied` → `.refused`;
    - `internal_error` → `.failed`.

  Find out whether `cmuxTests` already builds a `TabManager` with a workspace for `v2MobileTerminalClose` or `v2MobileWorkspaceCreate(params:tabManager:)` (search `cmuxTests` for those names). If it does, also add:
  - `agentSurfaceCloseOnTheLastSurfaceClosesTheWorkspace`: preference on. The workspace is gone afterwards.
  - `agentSurfaceCloseKeepsAWorkspaceWhenThePreferenceIsOff`: expect `protected`, and the workspace stays.
  - `agentSurfaceCloseClosesOneOfTwoSurfaces`: one panel is left.

  If no such fixture exists, say so in the PR and cover these three cases in Task 6's dogfood checklist.
- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `toknix run scripts/shellx/test-app.sh ShellXLinkWorkspaceSourceTests`
  Expected: compile errors.
- [ ] **Step 3: Implement the source, the TerminalController method, the shared live check and the wiring**

  Do not log session ids, titles or surface ids, matching the existing `outcome(of:)` logging, which logs only the code.
- [ ] **Step 4: Run the tests and confirm they pass**

  Run: `toknix run scripts/shellx/test-app.sh ShellXLinkWorkspaceSourceTests ShellXLinkChatSourceTests ShellXLinkSessionSourceTests ShellXLinkHostPolicyTests`
  Expected: PASS. `ShellXLinkChatSourceTests.testSendAndInterruptReachOnlyALiveAgent` proves the shared live check kept its behavior.
- [ ] **Step 5: Commit**

  Red first, then `feat(shellx): close a live agent's tab for a phone`.

### Task 4: iPhone hub sends `agent.close`

**Files:**
- Modify: `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Link/MachineHub.swift`:
  - beside `supportsWorkspaceControl` at about line 186;
  - beside `closeWorkspace` at about line 500;
  - `workspaceCommand` at about line 725, which gains a `feature: String` parameter so both features share it.
- Modify: `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppTestSupport/FakeMac.swift` (init at lines 83-95, and the `LinkHost` it builds). Add `acceptsAgentClose: Bool = true`, passing a fake `AgentControl` only when it is true. Add these to `FakeMacWorkspaces.swift`:
  - `agentCloses: [String]`;
  - `setNextAgentCloseOutcome(_:)`;
  - on `.ok`, the fake upserts the session as `.ended`, the way the real Mac's liveness sweep reports it.
- Test: `shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/MachineHubWorkspaceTests.swift`

**Interfaces:**
- Consumes: Task 2 `LinkClient.closeAgent`, `ShellXLink.agentCloseFeature`.
- Produces:
  - `public func supportsAgentClose(_ machineID: String) -> Bool`.
  - `public func closeAgent(_ ref: SessionRef) async -> WorkspaceCommandResult`:
    - a Mac that is not `.online` gives `.offline`, and nothing is sent;
    - a Mac without the feature gives `.failed`, and nothing is sent;
    - a lost link or timeout gives `.unknown`, never resent;
    - otherwise `WorkspaceCommandResult(outcome:)`.

- [ ] **Step 1: Write the failing tests**

  - `testCloseAgentCallsTheMacAndTheSessionEnds`: `agentCloses == ["s1"]`, and the session turns `.ended`. It leaves Running and enters `HomeFocus.ended`.
  - `testCloseAgentOutcomesMapToResults`.
  - `testCloseAgentWithoutTheFeatureIsFailedWithoutCalling`, with `acceptsAgentClose: false`.
  - `testCloseAgentOfflineMacIsOffline`.
  - `testCloseAgentIsSentOnce`: hold the fake, lose the connection while waiting, and expect `.unknown` with `agentCloses.count == 1` after reconnect.
  - `testSupportsAgentCloseFollowsTheFeature`.
- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `toknix run swift test --package-path shellx-ios/Packages/ShellXAppCore --filter MachineHubWorkspaceTests`
  Expected: compile errors.
- [ ] **Step 3: Implement the hub methods and the fake**

- [ ] **Step 4: Run the tests and confirm they pass**

  Run: `toknix run swift test --package-path shellx-ios/Packages/ShellXAppCore`
  Expected: PASS.
- [ ] **Step 5: Commit**

  Red first, then `feat(shellx-ios): hub closes an agent on its Mac`.

### Task 5: iPhone "Close" on the rows, the agent screen and the workspace menu

**Files:**
- Modify: `shellx-ios/ShellX/UI/Workspaces/WorkspaceFeedback.swift`:
  - `WorkspaceCommand` gains `.closeAgent`;
  - `WorkspaceAlert` gains `.agentNotClosable`;
  - `WorkspaceFeedback.of` maps `.closeAgent`: `.notFound` → `.alert(.agentNotClosable)`, `.refused` → `.alert(.refusedControl)`, `.ok` → `.nothing`, and the rest as today.
- Modify:
  - `shellx-ios/ShellX/UI/Workspaces/WorkspaceListScreen.swift` and `WorkspaceListView.swift`: the swipe on the three groups' rows, the confirmation, and `Actions.closeAgent`;
  - `shellx-ios/ShellX/UI/Workspaces/OtherSessionsView.swift` (`SessionListScreen` from part 1): the swipe, the confirmation and the alert, outside list only, never on the ended list.
- Modify: `shellx-ios/ShellX/UI/Agent/AgentScreen.swift` (`Actions` at lines 17-31, `NavigationChrome` at lines 282-303) and `shellx-ios/ShellX/UI/Agent/AgentView.swift`.
  - When standalone, the toolbar gets a `•••` menu holding "Close Agent", shown when the session is not ended and `hub.supportsAgentClose`.
  - Embedded in the workspace screen, nothing changes there.
- Modify: `shellx-ios/ShellX/UI/Workspaces/WorkspaceScreen.swift` (`WorkspaceMenuItem` at lines 15-25, `menu` at lines 121-133) and `WorkspaceView.swift`. Add `.closeAgent`, listed when the chip shown is an agent pane with a live session and the Mac supports it.
- Modify: `shellx-ios/ShellX/Localizable.xcstrings`.
- Test: `shellx-ios/ShellXTests/WorkspaceListActionsTests.swift`, `shellx-ios/ShellXTests/WorkspaceListRenderTests.swift`, `shellx-ios/ShellXTests/WorkspaceViewTests.swift`

**Interfaces:**
- Consumes: Task 4 `hub.closeAgent(_:)`, `hub.supportsAgentClose(_:)`; part 1's `FocusItem` and `SessionListScreen`.
- Produces:
  - `WorkspaceListScreen.Actions.closeAgent: (SessionRef) -> Void`, called after the confirmation.
  - `WorkspaceListScreen` gains `var closableMachines: Set<String> = []`.
  - `static func WorkspaceMenuItem.items(canCloseAgent: Bool) -> [WorkspaceMenuItem]`.

The confirmation is always a `confirmationDialog`:

- title: `agent.close.title %@` with the row's name;
- message: `agent.close.confirm`;
- one destructive button: `agent.close`.

The swipe button is not `.destructive`, for the reason the workspace swipe already documents.

Strings, with `en`/`vi` and comments:

| Key | en | vi |
| --- | --- | --- |
| `agent.close` | Close | Đóng |
| `agent.close.menu` | Close Agent | Đóng agent |
| `agent.close.title %@` | Close %@? | Đóng agent %@? |
| `agent.close.confirm` | Its terminal tab on the Mac will be closed. If it is the workspace's last tab, the workspace closes too. | Tab terminal của agent trên Mac sẽ bị đóng. Nếu đó là tab cuối của workspace, workspace cũng đóng theo. |
| `workspaces.alert.agentNotClosable` | The Mac can't close this agent: it has no terminal tab there, or it has already stopped. | Mac không đóng được agent này: nó không có tab terminal trên Mac, hoặc đã dừng. |

- [ ] **Step 1: Write the failing tests**

  - `WorkspaceListActionsTests.testCloseAgentAsksTheMacOnce`: two `closeAgent` calls in a row, the second while the first is held. The Mac gets one call; follow `testASecondTapOnCreateWaitsForTheFirst`.
  - `testCloseAgentTheMacCannotCloseIsAnAlert`: `.notFound` → `.agentNotClosable`.
  - `WorkspaceListRenderTests.testFeedbackFollowsTheMacsAnswer`: extend it with the `.closeAgent` rows.
  - `testEveryAlertSaysSomethingDifferent`: it covers the new case automatically through `CaseIterable`.
  - `WorkspaceViewTests`: `WorkspaceMenuItem.items(canCloseAgent: true)` returns `[.rename, .closeAgent, .closeWorkspace]`, and `false` returns `[.rename, .closeWorkspace]`.
- [ ] **Step 2: Run the app tests and confirm they fail**

  Run: `toknix run shellx-ios/scripts/dev.sh test app`
  Expected: compile errors.
- [ ] **Step 3: Implement the controls, the confirmations, the alerts and the strings**

  A `creating`-style flag must prevent a second send while one waits. Keep it per `SessionRef` in `WorkspaceListActions`, shared by the swipe and the menus.
- [ ] **Step 4: Run all iOS tests and confirm they pass**

  Run: `toknix run shellx-ios/scripts/dev.sh test all`
  Expected: PASS for core, app and release, plus the strings and licence checks.
- [ ] **Step 5: Commit**

  Red first, then `feat(shellx-ios): close an agent from the phone`.

### Task 6: Dogfood on the Mac and the iPhone

**Files:** none changed. The build output folder is excluded through `.git/info/exclude`.

- [ ] **Step 1: Build the Mac app in its own folder**

  Run: `CMUX_GHOSTTYKIT_NO_PREBUILT=1 toknix run scripts/shellx/sign-and-notarize.sh --build build-shellx-agent-close`. Add `build-shellx-agent-close/` to `.git/info/exclude`.
  Expected: it prints the `.app` path. Do not notarize, and do not open or replace the running ShellX.
- [ ] **Step 2: Install the iPhone build**

  Run: `toknix run shellx-ios/scripts/dev.sh device --device-id 51B0EA4F-D2C2-56A2-AC2B-3CD87DBAC107`. The phone must be unlocked.
- [ ] **Step 3: Hand the user the swap command and the checklist**

  Give the user a short command to quit their ShellX themselves and open the new build. Then the checklist:
  1. Swipe a running agent and choose Close, then confirm. The tab closes on the Mac, and the row moves to "Ended · N" within a few seconds.
  2. Do the same with an agent that is the only tab of a workspace. The workspace closes.
  3. Close an agent from the agent screen's `•••` and from the workspace's `•••`.
  4. An SSH agent, if any, shows the "can't close" alert.
  5. With the old 1.5.1 Mac back, no Close control shows anywhere.

  Record the results, including how long item 1 took to reach "Ended", in the PR. Do not merge without the user's explicit merge directive.

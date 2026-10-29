# ShellX mobile focused home (part 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The iPhone home lists agents by what needs doing (Needs you → Running → Just finished), names each row after the session's own title, folds ended sessions into "Ended · N" for 12 hours, and keeps the workspace list below. It works against the released Mac 1.5.1.

**Architecture:** Two pure models in `ShellXAppCore`: `SessionName` (cleaned, de-duplicated row names) and `HomeFocus` (which session goes in which group, with the 1-hour and 12-hour windows). They are fed by `MachineHub`, which now records when the phone saw each session finish. The SwiftUI home (`WorkspaceListScreen`) stays a plain-value screen so render tests can draw every state. There is no Mac or protocol change; part 2 (`2026-10-29-shellx-mobile-home-focus-part2-close-agent.md`) adds the close button.

**Tech Stack:** Swift 6, SwiftUI (iOS 17+), Swift Observation, XCTest, SwiftPM package `ShellXAppCore`, string catalog `ShellX/Localizable.xcstrings`.

**Spec:** `docs/superpowers/specs/2026-10-29-shellx-mobile-home-focus-design.md` (sections 1–6.4 and 7; 6.5 is part 2).

## Global Constraints

- Every path below is relative to the repo root `/Users/lehuuphu/Documents/myProjects/shellx`. Work on a branch off `develop`, for example `feat/shellx-mobile-home-focus`.
- "Vừa xong" lasts **1 hour** after the phone saw the finish. A session stays while age < 3600 s and leaves at exactly 3600 s.
- "Đã kết thúc" lasts **12 hours** after the end. A session stays while age < 43 200 s and leaves at exactly 43 200 s. Age is `now − stateSinceMs`, falling back to `lastActivityMs`. With neither time the session is hidden everywhere. A negative age (Mac clock ahead of the phone) counts as 0.
- Row name: the cleaned `title`. Failing that, `"<AgentLabel> · HH:mm"` from the last activity. Failing that, `AgentLabel` alone. Rows in one list whose names come out equal get ` · #2`, ` · #3`… in `(machineID, sessionId)` order.
- Every new or changed user-facing string goes in `shellx-ios/ShellX/Localizable.xcstrings` with `en` and `vi`, plus a `comment`. `shellx-ios/scripts/check-strings.py` must pass: no bare `Text("…")`, `Button("…")`, `Label("…")` or `.navigationTitle("…")`.
- Colours come only from the existing assets (`StatusNeedsYou`, `StatusRunning`, `StatusDone`, `StatusIdle`, `AccentColor`, `AccentText`, `Color.appSurface`, `Color.appBackground`). No gradients and no glows.
- Screens are built from plain values (`WorkspaceListScreen`, the session lists). Views that read the hub (`WorkspaceListView`, `OtherSessionsView`, `EndedSessionsView`) only adapt it.
- Core tests: `swift test --package-path shellx-ios/Packages/ShellXAppCore --filter <Class>`. App tests: `shellx-ios/scripts/dev.sh test app`, which runs the whole ShellXTests bundle on the "ShellX Dev" simulator. Wrap both in `toknix run`.
- Never quit, relaunch or replace the user's running ShellX on the Mac. Part 1 needs no Mac build.

## Review Focus

- **Mac clock ahead of the phone.** `stateSinceMs` can lie in the phone's future. The session must show in "Ended" (age 0), never vanish or crash. Pinned in Task 3.
- **A session that changes state while the home is open** must appear in exactly one group, never two. Pinned in Task 3, with each session counted once across the four lists.
- **The same `sessionId` on two Macs** must give two rows with their own names, not merge them. Pinned in Tasks 1 and 3, where everything is keyed by `SessionRef`.
- **Mac 1.5.1** has no workspaces and no `workspace_control`. The groups still fill, and "Agents outside workspaces" lists every live session. Pinned in Task 4's render test.
- **A Mac going offline** removes its sessions from the three groups and from "Ended". A reconnecting Mac keeps them, dimmed. Pinned in Task 2.

---

### Task 1: Row names (`SessionName`)

**Files:**
- Create: `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Home/SessionName.swift`
- Test: `shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/SessionNameTests.swift`

**Interfaces:**
- Consumes: `AgentLabel(agent:)`, `MachineSession`, `SessionRef`, which already exist.
- Produces:
  ```swift
  public enum SessionName {
      /// The first non-blank line of `title` with every `<…>` tag removed, a leading `/command` word dropped,
      /// and runs of whitespace collapsed to one space; nil when nothing is left.
      public static func cleaned(_ title: String?) -> String?
      /// `cleaned(title)`, else "<AgentLabel> · HH:mm" from `lastActivityMs` (then `stateSinceMs`), else the label.
      public static func base(of session: AgentSession, timeZone: TimeZone = .current) -> String
      /// The name each session shows in one list: equal bases get " · #2", " · #3"… in (machineID, sessionId) order.
      public static func distinct(_ sessions: [MachineSession], timeZone: TimeZone = .current) -> [SessionRef: String]
  }
  ```

- [ ] **Step 1: Write the failing tests**

  Use the helper `agentSession(_:state:lastActivityMs:stateSinceMs:workspace:)` from `Tests/ShellXAppCoreTests/Support/AsyncTestSupport.swift`, and set `.title` on the copy it returns.

  ```swift
  func testCleanedKeepsAPlainTitle() { XCTAssertEqual(SessionName.cleaned("Sửa nút ＋ trên iOS 🚀"), "Sửa nút ＋ trên iOS 🚀") }
  func testCleanedTakesTheFirstNonBlankLineAndCollapsesSpaces() {
      XCTAssertEqual(SessionName.cleaned("\n  \n  Viết test   SessionSet \nmore"), "Viết test SessionSet")
  }
  func testCleanedDropsTagsAndALeadingSlashCommand() {
      XCTAssertEqual(SessionName.cleaned("<command-message>brainstorm</command-message>"), "brainstorm")
      XCTAssertEqual(SessionName.cleaned("/review fix the login bug"), "fix the login bug")
      XCTAssertNil(SessionName.cleaned("<command-name>/clear</command-name>"))
  }
  func testCleanedIsNilForNothing() {
      XCTAssertNil(SessionName.cleaned(nil)); XCTAssertNil(SessionName.cleaned("   \n "))
  }
  func testBaseFallsBackToAgentAndTime() {
      var s = agentSession("s1", lastActivityMs: 1_793_284_320_000)   // 2026-10-29 14:32:00 UTC
      s.title = nil
      XCTAssertEqual(SessionName.base(of: s, timeZone: TimeZone(identifier: "UTC")!), "Claude Code · 14:32")
      s.lastActivityMs = nil; s.stateSinceMs = nil
      XCTAssertEqual(SessionName.base(of: s), "Claude Code")
  }
  func testDistinctNumbersEqualNamesInSessionOrder() {
      // s3, s1, s2 all titled "Fix bug"; s4 titled "Docs"
      // expect s1 "Fix bug", s2 "Fix bug · #2", s3 "Fix bug · #3", s4 "Docs"
  }
  func testDistinctKeepsTheSameSessionIdOnTwoMacsApart() {
      // "s1" titled "Fix bug" on mac "m1" and on mac "m2": two keys, names "Fix bug" and "Fix bug · #2"
  }
  ```

- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `toknix run swift test --package-path shellx-ios/Packages/ShellXAppCore --filter SessionNameTests`
  Expected: the build fails with "cannot find 'SessionName' in scope".

- [ ] **Step 3: Implement `SessionName` in `Home/SessionName.swift`**

  Format the time with a `DateFormatter` set to `"HH:mm"`, the given `timeZone` and `Locale(identifier: "en_US_POSIX")`. Join with `" · "`, the separator the app already uses.

- [ ] **Step 4: Run the tests and confirm they pass**

  Run: the command from Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

  ```bash
  git add shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Home/SessionName.swift shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/SessionNameTests.swift
  git commit -m "feat(shellx-ios): name sessions after their own title"
  ```

### Task 2: The hub records finish times and marks sessions seen

**Files:**
- Modify: `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Link/MachineHub.swift`
  - `finishedIds`, around line 30;
  - `init`, around line 63;
  - `otherSessions(machineID:)`, around line 157;
  - `finishedSessionIds`, around line 168;
  - `markSeen`, around line 174;
  - `noteFinishes`, around line 607.
- Test: `shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/MachineHubWorkspaceTests.swift`. Extend `makeHub` with a `now:` parameter and add the tests next to `finishedRig()`.

**Interfaces:**
- Produces:
  - `MachineHub.init(…, onUnauthorized:, now: @escaping @Sendable () -> Date = { Date() })`. The new parameter goes last, so existing callers compile unchanged.
  - `public var finishTimes: [String: [String: Date]]`: per Mac, sessionId → when the phone saw it finish. `finishedIds` becomes this dictionary.
  - `finishedSessionIds(machineID:)` keeps its signature and returns the keys.
  - `public func markSeen(_ ref: SessionRef)`: drops that one session from the finished set. `markSeen(_ ref: WorkspaceRef)` stays.
  - `otherSessions(machineID:)` now leaves out `.ended` sessions. Update its doc comment.
  - `public var reachableSessions: [MachineSession]`: every session, in every state, of the Macs whose state is `.online`, `.connecting` or `.reconnecting`. `online` is true only for `.online`. Most recent activity first, the same order as `liveSessions`.

- [ ] **Step 1: Write the failing tests**

  ```swift
  func testAFinishIsTimedWhenThePhoneSawIt()      // now = D; s1 working → idle; finishTimes[id]?["s1"] == D
  func testAFinishKeepsItsFirstTime()             // then clock D+600, s2 finishes: s1 still D, s2 D+600
  func testMarkSeenOfASessionClearsOnlyIt()       // s1 and s2 finished; markSeen(SessionRef for s1) → finishedSessionIds == ["s2"]
  func testOtherSessionsLeaveOutEndedOnes()       // a session in no workspace, state .ended → otherSessions(machineID:) is empty
  func testReachableSessionsHoldEveryStateOfAReachableMac() // working + ended sessions on an online Mac → both listed
  func testReachableSessionsLeaveOutAnOfflineMac() // two Macs, b fails its connects (as in MachineHubTests.testPathChangeForcesReconnect) → only a's sessions
  ```

  Drive the clock with a `ManualClock` from `Tests/ShellXAppCoreTests/Support/ManualClock.swift`, or with a locked `Date` box passed as `now:`. Each test asserts exact `Date` values.

- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `toknix run swift test --package-path shellx-ios/Packages/ShellXAppCore --filter MachineHubWorkspaceTests`
  Expected: compile errors for `now:`, `finishTimes`, `markSeen(_: SessionRef)` and `reachableSessions`.

- [ ] **Step 3: Implement the hub changes**

  In `noteFinishes`:
  - a newly reported session gets `now()`;
  - a session already present keeps its date;
  - drop sessions that are no longer idle, as the intersection does today.

  `forgetFinishes(of:)` clears that Mac's dictionary.

- [ ] **Step 4: Run the core tests and confirm they pass**

  Run: `toknix run swift test --package-path shellx-ios/Packages/ShellXAppCore`
  Expected: PASS, including the existing `testDone*` tests.

- [ ] **Step 5: Commit**

  ```bash
  git add shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Link/MachineHub.swift shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/MachineHubWorkspaceTests.swift
  git commit -m "feat(shellx-ios): time each finished turn on the phone"
  ```

### Task 3: Which session goes where (`HomeFocus`)

**Files:**
- Create: `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Home/HomeFocus.swift`
- Modify: `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Workspaces/WorkspaceRow.swift`. Make `firstLine(_:)` `static` (internal) instead of `private static`, so `HomeFocus` can reuse it.
- Test: `shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/HomeFocusTests.swift`

**Interfaces:**
- Consumes: Task 1 `SessionName.distinct`; Task 2 `finishTimes` shape `[String: [String: Date]]`; `MachinePendingItem`, `PendingItem.previewText`.
- Produces:
  ```swift
  public struct FocusItem: Identifiable, Equatable, Sendable {
      public var session: MachineSession
      public var name: String            // from SessionName.distinct over the list it is in
      public var question: String?       // first line of the matched request (needsYou only)
      public var finishedAt: Date?       // justDone only
      public var id: SessionRef { session.ref }
  }
  public struct HomeFocus: Equatable, Sendable {
      public var needsYou: [FocusItem]
      public var running: [FocusItem]
      public var justDone: [FocusItem]
      public var ended: [FocusItem]      // newest end first
      public var isQuiet: Bool           // needsYou, running and justDone all empty
      public static let justDoneFor: TimeInterval = 3600
      public static let endedFor: TimeInterval = 43_200
      public static let empty: HomeFocus
      public static func make(
          sessions: [MachineSession], pending: [MachinePendingItem], finished: [String: [String: Date]],
          now: Date, timeZone: TimeZone = .current) -> HomeFocus
  }
  ```

The rules come from spec §6.1 and §6.3, first match wins per session:

1. **Needs you:**
   - every `.needsInput` session;
   - plus, for each request with no `.needsInput` session matching `(machineID, item.workspaceId, item.agent)`, the most recently active matching session that is not `.ended` (promoted);
   - a request matching nothing adds nothing.

   Each request's question goes to the most recently active matching card. Ties are broken by `sessionId`.
2. **Running:** `.working`, unless already in Needs you.
3. **Just done:** `.idle`, with a finish time in `finished[machineID][sessionId]` and `now − finishedAt < justDoneFor`.
4. **Ended:** `.ended`, with an age (as defined in Global Constraints) `< endedFor`.
5. Every other session appears in no list.

Sort the first three lists by `lastActivityMs` descending, then `(machineID, sessionId)`. Sort Ended by end time descending. Names are distinct across Needs you + Running + Just done taken together; Ended gets its own `distinct` pass.

- [ ] **Step 1: Write the failing tests**

  ```swift
  func testEachSessionGoesToItsGroup()            // needsInput s1, working s2, idle s3 finished 10 min ago, idle s4 never finished,
                                                  // ended s5 1 h ago → [s1], [s2], [s3], [s5]; s4 nowhere
  func testJustDoneLastsAnHour()                  // finished now−3599 s → in; now−3600 s → out
  func testEndedLastsTwelveHours()                // stateSinceMs now−43 199 s → in; now−43 200 s → out
  func testEndedAgeFallsBackToLastActivity()      // stateSinceMs nil, lastActivityMs now−60 s → in
  func testEndedWithoutAnyTimeIsHidden()          // both nil → ended is empty
  func testEndedFromAMacClockAheadShows()         // stateSinceMs now+300 s → in ended
  func testEndedIsNewestFirst()
  func testTheQuestionGoesToTheNewestWaitingSession() // two needsInput in ws-shellx (activity 5, 9), pending preview
                                                  // "Cho phép chạy xcodebuild?\nchi tiết" → activity-9 card has
                                                  // "Cho phép chạy xcodebuild?", the other nil; needsYou.count == 2
  func testARequestPromotesTheNewestLiveSession() // only s working in ws-shellx + a request → s in needsYou, running empty
  func testARequestMatchingNoSessionMakesNoCard() // request workspaceId "wf-123" → needsYou empty
  func testRequestsOfAnotherMacOrAgentDoNotMatch()
  func testNoSessionIsInTwoGroups()               // a fixture with every state × request/no request: the four lists' ids are disjoint
  func testNamesAreDistinctAcrossTheTopGroups()   // "Fix bug" working s1 + "Fix bug" needsInput s2 → "Fix bug", "Fix bug · #2"
  func testTheSameSessionIdOnTwoMacsIsTwoItems()
  ```

- [ ] **Step 2: Run the tests and confirm they fail**

  Run: `toknix run swift test --package-path shellx-ios/Packages/ShellXAppCore --filter HomeFocusTests`
  Expected: the build fails because `HomeFocus` is undefined.

- [ ] **Step 3: Implement `HomeFocus.make` in `Home/HomeFocus.swift`**

- [ ] **Step 4: Run the tests and confirm they pass**

  Run: `toknix run swift test --package-path shellx-ios/Packages/ShellXAppCore`
  Expected: PASS, including `WorkspaceRowTests`.

- [ ] **Step 5: Commit**

  ```bash
  git add shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Home/HomeFocus.swift shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Workspaces/WorkspaceRow.swift shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/HomeFocusTests.swift
  git commit -m "feat(shellx-ios): sort the home's agents by what needs doing"
  ```

### Task 4: The home screen

**Files:**
- Modify: `shellx-ios/ShellX/UI/Workspaces/WorkspaceListScreen.swift`
- Modify: `shellx-ios/ShellX/UI/Workspaces/WorkspaceListView.swift`
- Create: `shellx-ios/ShellX/UI/Home/FocusRowView.swift`
- Modify: `shellx-ios/ShellX/UI/Workspaces/WorkspaceRowView.swift`. Turn it into the one-line row; see the step.
- Modify: `shellx-ios/ShellX/UI/Home/HomeRoute.swift`. Add `case ended`.
- Modify: `shellx-ios/ShellX/UI/SignedInView.swift:42-58`. Route `.ended` to `EndedSessionsView`, which Task 5 creates. Until then, route it to `EmptyView()` so this task builds.
- Modify: `shellx-ios/ShellX/Localizable.xcstrings`
- Test: `shellx-ios/ShellXTests/WorkspaceListRenderTests.swift`, `shellx-ios/ShellXTests/WorkspaceListActionsTests.swift`

**Interfaces:**
- Consumes: Task 3 `HomeFocus`, `FocusItem`; Task 2 `reachableSessions` and `finishTimes`.
- Produces:
  - `WorkspaceListScreen` gains `let focus: HomeFocus`, `var now = Date()` and `var showsMachineNames = false`.
  - `Actions` gains `openEnded: () -> Void`.
  - Focus rows are `NavigationLink(value: item.id)` (a `SessionRef`); `WorkspaceListView` already registers that destination.
  - `FocusRowView(item: FocusItem, kind: FocusRowView.Kind, now: Date, showsMachineName: Bool)` with `enum Kind { case needsYou, running, justDone, ended }`. Task 5 reuses it for the session lists, and part 2 adds a swipe to it.

Layout, top to bottom, follows spec §6.1 and mockup A at `.superpowers/brainstorm/15486-1793251125/content/home-focus.html`:

- **Title:** `Text(verbatim: "ShellX")`; the product name is never translated.
- **Toolbar:** bell, ＋ and Settings, as today.
- **No `NeedsYouBar`** on this screen. Remove `needsYou` and its `safeAreaInset`. `pending` still feeds the bell's count.
- **"Needs you · N", "Running · N", "Just finished · N" sections:** each appears only when it has items. When `focus.isQuiet`, show one muted line, "No agent is running", instead.
- **`FocusRowView`:**
  - a card in `Color.appSurface` with a 14-pt radius;
  - a `StatusDot` coloured by kind: needs you `StatusNeedsYou`, running `StatusRunning`, done `StatusDone`, ended `StatusIdle`;
  - the name on one line, tail-truncated (3 lines at accessibility sizes);
  - on the right, a tag:
    - "Needs you";
    - the elapsed time from `AgentStateStyle.elapsedText`;
    - "Done";
    - nothing;
  - the sub line: `workspaceTitle · AgentLabel`, the Mac name when `showsMachineName`, and for just-done items "<elapsed> ago";
  - a needs-you card has an `AccentColor` border at 0.45 opacity and the question in quotes in `AccentText`;
  - a card from a Mac that is not online is dimmed to 0.55 opacity.
- **"Workspaces" section:** one per Mac, as today, with `MachineGroupHeader`.
  - Rows are one line: the title on the left, the branch in mono `.footnote` on the right.
  - Tap and swipe actions are unchanged.
  - Replace `WorkspaceRowView`'s body with this line and delete `metaLine(for:)`, `quotedQuestion(for:)` and their tests in `WorkspaceListRenderTests`. Keep `dimmed`.
- **"Agents outside workspaces · N" row:** the existing `workspaces.other %lld` row; change the words only (see strings).
- **"Ended · N" fold:** the last row of the list, shown when `focus.ended` is not empty, with a dashed border and a chevron. It calls `actions.openEnded`.
- **`WorkspaceListView`:**
  - Wrap the screen in `TimelineView(.periodic(from: .now, by: 30))`.
  - Pass `focus: HomeFocus.make(sessions: hub.reachableSessions, pending: scope.decisions.visibleItems(hub.pendingItems), finished: hub.finishTimes, now: context.date)` and `now: context.date`.
  - Set `showsMachineNames: hub.machines.count > 1`.
  - Wire `openEnded: { open(.ended) }`.

Strings: add `en`/`vi` pairs with comments.

| Key | en | vi |
| --- | --- | --- |
| `home.needsYou %lld` | Needs you · %lld | Cần bạn · %lld |
| `home.running %lld` | Running · %lld | Đang chạy · %lld |
| `home.justDone %lld` | Just finished · %lld | Vừa xong · %lld |
| `home.workspaces` | Workspaces | Workspace |
| `home.quiet` | No agent is running | Không có agent nào đang chạy |
| `home.ended %lld` | Ended · %lld | Đã kết thúc · %lld |
| `home.ago %@` | %@ ago | %@ trước |

Then change two existing keys:

- `workspaces.other %lld` becomes "Agents outside workspaces · %lld" / "Agent ngoài workspace · %lld";
- `workspaces.other.title` becomes "Agents Outside Workspaces" / "Agent ngoài workspace".

The `en` plural branches need `one` and `other`. If nothing uses `workspaces.title` any more, delete it from the catalog.

- [ ] **Step 1: Write the failing render and action tests**

  In `WorkspaceListRenderTests`:

  - `testRendersTheMockupHome`: build a `HomeFocus` directly with `FocusItem` values from mockup A:
    - "Sửa nút ＋ trên iOS", needs you, with the question "Cho phép chạy xcodebuild?";
    - "Viết test SessionSet" and "Dọn README", running;
    - "Build bản 1.5.1", just done;
    - three ended sessions;
    - the `macbook` group.

    `assertRenders(…, name: "home-focus")`.
  - `testRendersAQuietHome`: `HomeFocus.empty` → `name: "home-quiet"`.
  - `testRendersAnOldMacHome`: Mac 1.5.1 (`listsWorkspaces: false`, `otherSessionCount: 3`) with two running items → `name: "home-old-mac"`.
  - `testRendersTwoMacNames`: `showsMachineNames: true` → `name: "home-two-macs"`.

  Update the existing `list(…)` helper to pass `focus:`, defaulting to `.empty`.

  In `WorkspaceListActionsTests`, add `testEndedFoldPushesTheEndedPage`: run `actions.openEnded()` and assert `.ended` was pushed. Model it on `testControlsPushTheirScreens`.

- [ ] **Step 2: Run the app tests and confirm they fail**

  Run: `toknix run shellx-ios/scripts/dev.sh test app`
  Expected: the build fails on `focus:`, `openEnded` and `HomeRoute.ended`.

- [ ] **Step 3: Implement the screen, the row and the strings as laid out above**

- [ ] **Step 4: Run the app tests and the string check, and confirm they pass**

  Run: `toknix run shellx-ios/scripts/dev.sh test app`. It also runs `check-strings.py`.
  Expected: PASS.

- [ ] **Step 5: Look at the PNGs**

  Run: `toknix run shellx-ios/scripts/dev.sh screenshots /private/tmp/claude-501/home-focus-shots`. Open `home-focus` in light, in dark, and in `vi`.
  Expected: it matches mockup A. Nothing is cut mid-word, and no two rows share a name.

- [ ] **Step 6: Commit**

  ```bash
  git add shellx-ios/ShellX/UI shellx-ios/ShellX/Localizable.xcstrings shellx-ios/ShellXTests/WorkspaceListRenderTests.swift shellx-ios/ShellXTests/WorkspaceListActionsTests.swift
  git commit -m "feat(shellx-ios): home lists agents by what needs doing"
  ```

### Task 5: The "Ended" page, renamed outside-workspace list, and opening an agent marks it seen

**Files:**
- Modify: `shellx-ios/ShellX/UI/Workspaces/OtherSessionsView.swift`. Turn `OtherSessionsList` into the shared list `SessionListScreen` (same file, or `ShellX/UI/Home/SessionListScreen.swift`).
- Create: `shellx-ios/ShellX/UI/Home/EndedSessionsView.swift`
- Modify: `shellx-ios/ShellX/UI/SignedInView.swift`. Change `.ended` to `EndedSessionsView(hub: hub)`.
- Modify: `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppCore/Agent/AgentThreadModel.swift`. At the top of `run()`, line 228, call `hub.markSeen(ref)`. Every way of opening an agent goes through `run()`: home, lists, pending and workspace pane. Test it in `Tests/ShellXAppCoreTests/AgentThreadModelTests.swift`.
- Modify: `shellx-ios/Packages/ShellXAppCore/Sources/ShellXAppTestSupport/FakeMacDemoScript.swift` `setUp()`. Add two sessions:
  - `demo-shellx-2`: `ws-shellx`, title "Pairing sheet", `.idle`, so the demo shows a `#2`;
  - `demo-ended`: `ws-web`, title "Release 1.5.1", `.ended`, `stateSinceMs: ms − 7_200_000`.

  Update `FakeMacDemoScriptTests` and `DemoCompositionTests` counts to match.
- Modify: `shellx-ios/ShellX/Localizable.xcstrings`. Add `ended.title` = "Ended" / "Đã kết thúc" and `ended.empty` = "No agent ended in the last 12 hours" / "Không có agent nào kết thúc trong 12 giờ qua".
- Test: `shellx-ios/ShellXTests/WorkspaceListRenderTests.swift`, `shellx-ios/Packages/ShellXAppCore/Tests/ShellXAppCoreTests/AgentThreadModelTests.swift`

**Interfaces:**
- Consumes:
  - Task 4 `FocusRowView`;
  - Task 3 `HomeFocus.make(…).ended`;
  - Task 1 `SessionName.distinct`;
  - Task 2 `markSeen(_: SessionRef)`, `reachableSessions`, `otherSessions(machineID:)`.
- Produces: `SessionListScreen(title: String, header: String?, items: [FocusItem], kind: FocusRowView.Kind, now: Date, showsMachineName: Bool)`.
  - Empty, it shows the existing `workspaces.other.empty` text for the outside list and `ended.empty` for the ended list. Pass the empty text as a `LocalizedStringResource` parameter.
  - Rows are `NavigationLink(value: item.id)`.

Behavior:

- `OtherSessionsView` builds its items from `hub.otherSessions(machineID:)`. Ended sessions are already gone (Task 2). Name them with `SessionName.distinct`, and give each the `FocusRowView.Kind` of its state.
- `EndedSessionsView` uses `HomeFocus.make(sessions: hub.reachableSessions, pending: [], finished: [:], now: context.date).ended` inside `TimelineView(.periodic(from: .now, by: 30))`. A session therefore leaves the page at 12 hours while it is open.

- [ ] **Step 1: Write the failing tests**

  - `testEndedListRenders`, with three ended items from two Macs → `name: "ended-list"`.
  - `testEndedListEmptyRenders` → `name: "ended-empty"`.
  - Update `testOtherSessionsListRenders` so its fixture has two sessions titled the same: the names read "X" and "X · #2".
  - `AgentThreadModelTests.testRunMarksTheSessionSeen`: a hub where s1 and s2 finished. Start `run()` for s1 in a task, wait `eventually` until `hub.finishedSessionIds(machineID:) == ["s2"]`, then cancel. Run it with `swift test --package-path shellx-ios/Packages/ShellXAppCore --filter AgentThreadModelTests`.

- [ ] **Step 2: Run the app tests and confirm they fail**

  Run: `toknix run shellx-ios/scripts/dev.sh test app`
  Also run `toknix run swift test --package-path shellx-ios/Packages/ShellXAppCore --filter AgentThreadModelTests`.
  Expected: the app build fails because `SessionListScreen` and `EndedSessionsView` are undefined, and `testRunMarksTheSessionSeen` fails.

- [ ] **Step 3: Implement the lists, the route, the seen call and the demo sessions**

- [ ] **Step 4: Run all iOS tests and confirm they pass**

  Run: `toknix run shellx-ios/scripts/dev.sh test all`
  Expected: PASS for core, app and release, with the licence and strings checks green.

- [ ] **Step 5: Commit**

  ```bash
  git add shellx-ios/ShellX shellx-ios/ShellXTests shellx-ios/Packages/ShellXAppCore
  git commit -m "feat(shellx-ios): ended page and title-named session lists"
  ```

### Task 6: Dogfood on the iPhone

**Files:** none changed.

- [ ] **Step 1: Install on the iPhone**

  Run: `toknix run shellx-ios/scripts/dev.sh device --device-id 51B0EA4F-D2C2-56A2-AC2B-3CD87DBAC107`. The phone must be unlocked.
  Expected: "installed" and the app opens.

- [ ] **Step 2: Hand the checklist to the user**

  The user runs it against their Mac, which runs 1.5.1:
  1. The home shows Needs you / Running / Just finished, and no two rows share a name.
  2. No ended session shows outside "Ended · N".
  3. Opening an agent from "Just finished" removes it from the group.
  4. "Agents outside workspaces" lists only live sessions.

  Record the user's results in the PR description. The home is UI, so do not merge without the user's explicit merge directive (CLAUDE.md).

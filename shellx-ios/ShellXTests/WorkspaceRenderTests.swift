import ShellXAppCore
import ShellXAppTestSupport
import ShellXLinkCore
import SwiftUI
import XCTest
@testable import ShellX

/// The workspace screen: the chip row over a pane per chip (a chat for an agent, the placeholder for a
/// shell), its states while the workspace has not come or is not there, and the words behind them,
/// each in light and dark (`dev.sh screenshots` writes them out in en and vi).
@MainActor
final class WorkspaceRenderTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)
    private static let nowMs: Int64 = 1_700_000_000_000

    private func assertRenders(_ view: some View, name: String) throws {
        let images = try SnapshotWriter().write(view, name: name)
        XCTAssertEqual(images.count, 2)
        for image in images { XCTAssertEqual(image.size, SnapshotWriter.size) }
        XCTAssertNotEqual(images.first?.pngData(), images.last?.pngData(), "light and dark renders should differ")
    }

    // MARK: - Fixtures

    private static func session(_ id: String, state: AgentState, since: Int64 = 240_000) -> MachineSession {
        MachineSession(
            machineID: "m1", machineName: "MacBook Pro", online: true,
            session: AgentSession(
                sessionId: id, agent: "claude", workspaceId: "ws-shellx", workspaceTitle: "shellx-ios", state: state,
                stateSinceMs: nowMs - since, lastActivityMs: nowMs - 5_000))
    }

    private static let claude = session("s-claude", state: .needsInput)
    private static let dev = session("s-dev", state: .working)

    /// `claude` (an agent that asks), `zsh` (a shell), `dev :3000` (an agent at work).
    private static let panes = [
        WorkspacePane(id: "t-claude", title: "claude", session: claude),
        WorkspacePane(id: "t-zsh", title: "zsh"),
        WorkspacePane(id: "t-dev", title: "dev :3000", session: dev),
    ]

    private static let workspace = LinkWorkspace(
        workspaceId: "ws-shellx", title: "shellx-ios", order: 0, directory: "~/shellx/shellx-ios",
        branch: "feat/workspaces",
        terminals: [
            LinkTerminal(terminalId: "t-claude", title: "claude", order: 0, selected: false, sessionId: "s-claude"),
            LinkTerminal(terminalId: "t-zsh", title: "zsh", order: 1, selected: true),
            LinkTerminal(terminalId: "t-dev", title: "dev :3000", order: 2, selected: false, sessionId: "s-dev"),
        ])

    private static let request = MachinePendingItem(
        machineID: "m1", machineName: "MacBook Pro",
        item: PendingItem(
            requestId: "p1", kind: .permission, agent: "claude", workspaceId: "ws-shellx", workspaceTitle: "shellx-ios",
            toolName: "Bash", toolInputPreview: #"{"command":"xcodebuild test"}"#, createdAtMs: 1,
            modes: ["once", "always", "deny"]),
        actionable: true)

    private static func entry(_ seq: Int, _ role: ChatEntryRole, _ kind: ChatEntryKind, _ text: String, tool: String? = nil)
        -> ChatEntry
    {
        ChatEntry(
            id: "e\(seq)", rev: 1, seq: seq, role: role, kind: kind, text: text, toolName: tool,
            tsMs: nowMs - Int64((10 - seq) * 30_000))
    }

    private static let chat: [ChatEntry] = [
        entry(1, .user, .prose, "thêm danh sách workspace vào màn chính"),
        entry(2, .agent, .prose, "Mình sẽ thêm **WorkspaceList** và sửa màn chính. Cần chạy test để kiểm tra."),
        entry(3, .agent, .toolUse, "ShellX/UI/Home/HomeView.swift", tool: "Edit"),
        entry(4, .agent, .toolUse, "ShellX/UI/Workspace/WorkspaceList.swift", tool: "Edit"),
        entry(5, .agent, .toolUse, "xcodebuild test", tool: "Bash"),
    ]

    /// The embedded agent screen for `session`, as `AgentView` feeds it, from fixtures.
    private func agentPane(_ session: MachineSession, pending: [MachinePendingItem]) -> some View {
        let row = AgentStatusRow(session: session, now: Self.now)
        return AgentScreen(
            ref: session.ref, embedded: true, place: "Claude Code · MacBook Pro", row: { row }, gone: false,
            offline: false, pending: pending, showsMachineName: false, entries: Self.chat, emptyState: nil,
            machineName: "MacBook Pro", older: .none, loadingOlder: false,
            canStop: session.session.state == .working || session.session.state == .needsInput, notice: nil,
            draft: .constant(""))
    }

    /// Records which agent panes the pager asked for.
    private final class Requested {
        var sessions: [String] = []
    }

    private func screen(
        selected: String?, panes: [WorkspacePane] = WorkspaceRenderTests.panes, title: String = "shellx-ios",
        branch: String? = "feat/workspaces", canControl: Bool = true, alert: WorkspaceAlert? = nil,
        notice: AgentScreen.Notice? = nil, requested: Requested = Requested()
    ) -> some View {
        NavigationStack {
            WorkspaceScreen(
                title: title, branch: branch, panes: panes, selected: selected, now: Self.now, canControl: canControl,
                notice: notice, alert: .constant(alert),
                agent: { session in
                    let _ = requested.sessions.append(session.session.sessionId)
                    self.agentPane(session, pending: session.session.sessionId == "s-claude" ? [Self.request] : [])
                })
        }
    }

    // MARK: - Chips and panes

    func testAgentChipShowsChat() throws {
        // A request waits on the agent: its chip is the one shown, though the Mac has `zsh` selected.
        let first = WorkspaceScreenModel.defaultTerminal(in: Self.workspace, pending: [Self.request])
        XCTAssertEqual(first, "t-claude")
        XCTAssertEqual(Self.panes.map(\.isAgent), [true, false, true], "an agent chip is a chat, a shell chip is not")

        let requested = Requested()
        try assertRenders(screen(selected: first, requested: requested), name: "workspace-agent")

        XCTAssertTrue(requested.sessions.contains("s-claude"), "the shown chip's page is the agent screen: \(requested.sessions)")
        XCTAssertFalse(requested.sessions.isEmpty)
    }

    func testShellChipShowsPlaceholder() throws {
        let agentImages = try SnapshotWriter().write(screen(selected: "t-claude"), name: "workspace-agent")
        let shellImages = try SnapshotWriter().write(screen(selected: "t-zsh"), name: "workspace-shell")
        XCTAssertEqual(shellImages.count, 2)
        XCTAssertNotEqual(shellImages.first?.pngData(), shellImages.last?.pngData(), "light and dark renders should differ")

        // The placeholder is not an agent screen: a pane without a session shows it, and the two chips
        // show different pages.
        let shell = try XCTUnwrap(Self.panes.first { $0.id == "t-zsh" })
        XCTAssertNil(shell.session)
        XCTAssertNotEqual(agentImages.first?.pngData(), shellImages.first?.pngData())
    }

    func testDefaultChipFollowsMacSelection() throws {
        // Nothing waits: the chip the Mac has selected, here the shell.
        let first = WorkspaceScreenModel.defaultTerminal(in: Self.workspace, pending: [])
        XCTAssertEqual(first, "t-zsh")

        try assertRenders(screen(selected: first), name: "workspace-mac-selection")
    }

    func testRendersAShellOnlyWorkspaceAndAnEmptyOne() throws {
        let shells = [
            WorkspacePane(id: "a", title: "zsh"), WorkspacePane(id: "b", title: "npm run dev"),
        ]
        try assertRenders(screen(selected: "b", panes: shells, title: "relay", branch: "main"), name: "workspace-shells")
        try assertRenders(screen(selected: nil, panes: [], title: "notes", branch: nil), name: "workspace-empty")
    }

    func testRendersLongNamesManyChipsAndLargeText() throws {
        let many = (1...9).map { WorkspacePane(id: "t\($0)", title: "terminal number \($0)") }
        let long = "a-very-long-workspace-name-that-goes-on-and-on"
        try assertRenders(
            screen(selected: "t7", panes: many, title: long, branch: "feature/a-long-branch-name-with-many-parts"),
            name: "workspace-many-chips")
        try assertRenders(
            screen(selected: "t-zsh").environment(\.dynamicTypeSize, .accessibility3), name: "workspace-ax3")
    }

    func testRendersWhileTheMacIsAway() throws {
        try assertRenders(screen(selected: "t-zsh", canControl: false), name: "workspace-no-control")
        try assertRenders(screen(selected: "t-zsh", alert: .refusedClose), name: "workspace-alert")
    }

    /// Spec section 6.2: the pane shown was closed on the Mac, the next chip shows, and a short line says why.
    func testRendersThePaneClosedNotice() throws {
        let notice = AgentScreen.Notice(text: WorkspaceView.paneClosedNotice)
        XCTAssertEqual(notice.text, String(localized: "workspace.paneClosedOnMac"))
        let withNotice = try SnapshotWriter().write(screen(selected: "t-zsh", notice: notice), name: "workspace-pane-closed")
        let without = try SnapshotWriter().write(screen(selected: "t-zsh"), name: "workspace-shell")
        XCTAssertNotEqual(withNotice.first?.pngData(), without.first?.pngData(), "the line shows over the pages")
    }

    func testRendersTheWaitingAndMissingStates() throws {
        try assertRenders(NavigationStack { WorkspaceWaitingView() }, name: "workspace-loading")
        try assertRenders(NavigationStack { WorkspaceMissingView(back: {}) }, name: "workspace-not-found")
    }

    // MARK: - Words

    func testTheMenuOffersRenameAndCloseWorkspaceOnly() {
        XCTAssertEqual(WorkspaceMenuItem.allCases, [.rename, .closeWorkspace], "no 'close pane' before the terminal version")
        let titles = WorkspaceMenuItem.allCases.map(\.title)
        XCTAssertEqual(titles, [String(localized: "workspace.menu.rename"), String(localized: "workspace.menu.close")])
        XCTAssertEqual(Set(titles).count, 2)
    }

    func testAChipSaysItsTabsNameOrWhatItRuns() {
        XCTAssertEqual(PaneChips.label(for: WorkspacePane(id: "a", title: "zsh")), "zsh")
        XCTAssertEqual(PaneChips.label(for: WorkspacePane(id: "b", title: "")), "Terminal", "a shrunk list has no tab names")
        XCTAssertEqual(
            PaneChips.label(for: WorkspacePane(id: "c", title: "", session: Self.claude)), "Claude Code")
    }

    func testAChipsDotIsItsAgentsState() {
        let now = Self.now
        let colors = Self.panes.map { PaneChips.state(of: $0, now: now)?.colorName }
        XCTAssertEqual(colors, ["StatusNeedsYou", nil, "StatusRunning"], "a shell has no dot")

        let idle = WorkspacePane(id: "i", title: "i", session: Self.session("i", state: .idle))
        let ended = WorkspacePane(id: "e", title: "e", session: Self.session("e", state: .ended))
        let unknown = WorkspacePane(id: "u", title: "u", session: Self.session("u", state: .other("thinking")))
        XCTAssertEqual(PaneChips.state(of: idle, now: now)?.colorName, "StatusDone")
        XCTAssertEqual(PaneChips.state(of: ended, now: now)?.colorName, "StatusIdle")
        XCTAssertNil(PaneChips.state(of: unknown, now: now), "a state this app does not know has no dot")
        XCTAssertNotNil(PaneChips.state(of: Self.panes[0], now: now)?.text, "the colour is never the only cue")
    }

    func testLeavingSaysWhyUnlessTheUserClosedIt() {
        XCTAssertEqual(WorkspaceView.leavingNotice(closedHere: false), String(localized: "workspace.closedOnMac"))
        XCTAssertNil(WorkspaceView.leavingNotice(closedHere: true))
    }

    func testTheListNoticeClearsOnlyItself() throws {
        let notice = ListNotice()
        notice.show("one")
        let first = try XCTUnwrap(notice.current?.id)
        notice.show("two")
        notice.clear(first)
        XCTAssertEqual(notice.current?.text, "two", "a newer line stays")
        notice.clear(try XCTUnwrap(notice.current?.id))
        XCTAssertNil(notice.current)
    }
}

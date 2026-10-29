import ShellXAppCore
import SwiftUI
import XCTest
@testable import ShellX

/// The app's home: the agents by what needs doing (mockup A), a quiet home, two Macs (one offline)
/// with their workspaces, a Mac whose ShellX is too old for workspaces, the row of agents outside
/// workspaces, each in light and dark (`dev.sh screenshots` writes them out in en and vi), and the
/// words and decisions behind the rows.
@MainActor
final class WorkspaceListRenderTests: XCTestCase {
    private func assertRenders(_ view: some View, name: String) throws {
        let images = try SnapshotWriter().write(view, name: name)
        XCTAssertEqual(images.count, 2)
        for image in images { XCTAssertEqual(image.size, SnapshotWriter.size) }
        XCTAssertNotEqual(images.first?.pngData(), images.last?.pngData(), "light and dark renders should differ")
    }

    // MARK: - Fixtures

    private static func ref(_ id: String, machine: String = "m1") -> WorkspaceRef {
        WorkspaceRef(machineID: machine, workspaceId: id)
    }

    private static let shellx = WorkspaceRow(
        id: ref("ws-shellx"), title: "shellx-ios", directory: "~/shellx/shellx-ios", branch: "feat/workspaces",
        state: .needsYou, question: "Cho phép chạy xcodebuild test?")
    private static let relay = WorkspaceRow(
        id: ref("ws-relay"), title: "relay", directory: "~/shellx/relay", branch: "main", ports: [8787], state: .running)
    private static let web = WorkspaceRow(
        id: ref("ws-web"), title: "web", directory: "~/shellx/web", branch: "develop", ports: [3000], state: .done)
    private static let notes = WorkspaceRow(id: ref("ws-notes"), title: "notes", directory: "~", state: .idle)
    private static let broken = WorkspaceRow(
        id: ref("ws-broken"), title: "a-very-long-workspace-name-that-goes-on-and-on", directory: "~/code/a/deeply/nested/directory",
        branch: "feature/a-long-branch-name", ports: [3000, 3001, 5173], state: .error)

    private static let macbook = WorkspaceGroup(
        id: "m1", name: "MacBook Pro", state: .online, isDefault: true, rows: [shellx, relay, web, notes],
        allowsControl: true, listsWorkspaces: true, otherSessionCount: 0)

    private static let eightTwelve = DateComponents(
        calendar: .current, year: 2026, month: 10, day: 28, hour: 8, minute: 12).date ?? .distantPast

    private static let mini = WorkspaceGroup(
        id: "m2", name: "Mac mini", state: .offline(since: eightTwelve), isDefault: false, rows: [],
        allowsControl: false, listsWorkspaces: true, otherSessionCount: 0)

    private static let pending = [
        MachinePendingItem(
            machineID: "m1", machineName: "MacBook Pro",
            item: PendingItem(
                requestId: "p1", kind: .permission, agent: "claude", workspaceId: "ws-shellx",
                workspaceTitle: "shellx-ios", toolName: "Bash",
                toolInputPreview: #"{"command":"xcodebuild test"}"#, createdAtMs: 1, modes: ["once", "always", "deny"]),
            actionable: true),
        MachinePendingItem(
            machineID: "m1", machineName: "MacBook Pro",
            item: PendingItem(
                requestId: "p2", kind: .permission, agent: "claude", workspaceId: "ws-shellx",
                workspaceTitle: "shellx-ios", toolName: "Bash",
                toolInputPreview: #"{"command":"git push"}"#, createdAtMs: 2, modes: ["once", "always", "deny"]),
            actionable: true),
    ]

    // The agents of mockup A, as `HomeFocus` sorts them.

    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// Unix milliseconds `minutes` before `now`.
    private static func ms(minutesAgo minutes: Double) -> Int64 {
        Int64((now.timeIntervalSince1970 - minutes * 60) * 1000)
    }

    private static func session(
        _ id: String, _ title: String, state: AgentState, minutesAgo: Double, workspace: String = "shellx",
        agent: String = "claude", machine: String = "m1", machineName: String = "MacBook Pro", online: Bool = true
    ) -> MachineSession {
        MachineSession(
            machineID: machine, machineName: machineName, online: online,
            session: AgentSession(
                sessionId: id, agent: agent, workspaceId: "ws-\(workspace)", workspaceTitle: workspace, title: title,
                state: state, stateSinceMs: ms(minutesAgo: minutesAgo), lastActivityMs: ms(minutesAgo: minutesAgo)))
    }

    private static func item(_ session: MachineSession, question: String? = nil, finishedAt: Date? = nil) -> FocusItem {
        FocusItem(session: session, name: session.session.title ?? "", question: question, finishedAt: finishedAt)
    }

    private static let mockup: HomeFocus = {
        var focus = HomeFocus.empty
        focus.needsYou = [
            item(session("s1", "Sửa nút ＋ trên iOS", state: .needsInput, minutesAgo: 2), question: "Cho phép chạy xcodebuild?"),
        ]
        focus.running = [
            item(session("s2", "Viết test SessionSet", state: .working, minutesAgo: 8)),
            item(session("s3", "Dọn README", state: .working, minutesAgo: 1, workspace: "toknix", agent: "codex")),
        ]
        focus.justDone = [
            item(session("s4", "Build bản 1.5.1", state: .idle, minutesAgo: 12), finishedAt: now.addingTimeInterval(-12 * 60)),
        ]
        focus.ended = [
            item(session("s5", "Đổi tên nhánh", state: .ended, minutesAgo: 30)),
            item(session("s6", "Sửa lỗi relay", state: .ended, minutesAgo: 95, workspace: "relay")),
            item(session("s7", "Viết spec", state: .ended, minutesAgo: 240, agent: "codex")),
        ]
        return focus
    }()

    private func list(
        _ groups: [WorkspaceGroup], focus: HomeFocus = .empty, pending: [MachinePendingItem] = [],
        showsMachineNames: Bool = false, alert: WorkspaceAlert? = nil
    ) -> some View {
        NavigationStack {
            WorkspaceListScreen(
                groups: groups, focus: focus, pending: pending, now: Self.now, showsMachineNames: showsMachineNames,
                alert: .constant(alert))
        }
    }

    // MARK: - Screens

    func testRendersTheMockupHome() throws {
        try assertRenders(list([Self.macbook], focus: Self.mockup), name: "home-focus")
        try assertRenders(
            list([Self.macbook], focus: Self.mockup).environment(\.dynamicTypeSize, .accessibility3),
            name: "home-focus-ax3")

        // What the cards say.
        let now = Self.now
        XCTAssertEqual(
            Self.mockup.needsYou.map { FocusRowView.tag(for: $0, kind: .needsYou, now: now) },
            [String(localized: "agent.state.needsYou")])
        XCTAssertEqual(
            Self.mockup.running.map { FocusRowView.tag(for: $0, kind: .running, now: now) },
            [AgentStateStyle.elapsedText(.seconds(8 * 60)), AgentStateStyle.elapsedText(.seconds(60))])
        XCTAssertEqual(
            Self.mockup.justDone.map { FocusRowView.tag(for: $0, kind: .justDone, now: now) },
            [String(localized: "agent.state.done")])
        XCTAssertEqual(Self.mockup.ended.map { FocusRowView.tag(for: $0, kind: .ended, now: now) }, [nil, nil, nil])

        XCTAssertEqual(
            FocusRowView.subLine(for: Self.mockup.running[1], kind: .running, now: now, showsMachineName: false),
            "toknix · Codex")
        XCTAssertEqual(
            FocusRowView.subLine(for: Self.mockup.justDone[0], kind: .justDone, now: now, showsMachineName: true),
            "shellx · Claude Code · MacBook Pro · "
                + String(localized: "home.ago \(AgentStateStyle.elapsedText(.seconds(12 * 60)))"))
        XCTAssertEqual(
            FocusRowView.quotedQuestion(for: Self.mockup.needsYou[0], kind: .needsYou),
            "\u{201C}Cho phép chạy xcodebuild?\u{201D}")
        XCTAssertNil(FocusRowView.quotedQuestion(for: Self.mockup.running[0], kind: .running))
    }

    func testRendersAQuietHome() throws {
        XCTAssertTrue(HomeFocus.empty.isQuiet)
        try assertRenders(list([Self.macbook], focus: .empty), name: "home-quiet")
    }

    func testRendersAnOldMacHome() throws {
        // ShellX 1.5.1 on the Mac: no workspaces and no `workspace_control`, but its agents still sort.
        let old = WorkspaceGroup(
            id: "m1", name: "MacBook Pro", state: .online, isDefault: true, rows: [], allowsControl: false,
            listsWorkspaces: false, otherSessionCount: 3)
        var focus = HomeFocus.empty
        focus.running = [
            Self.item(Self.session("s1", "Viết test SessionSet", state: .working, minutesAgo: 8)),
            Self.item(Self.session("s2", "Dọn README", state: .working, minutesAgo: 1, agent: "codex")),
        ]
        try assertRenders(list([old], focus: focus), name: "home-old-mac")
        XCTAssertEqual(old.listing, .updateMac)
        XCTAssertTrue(old.showsOtherSessions, "every live session stays reachable")
    }

    func testRendersTwoMacNames() throws {
        // The Mac mini is coming back: its card is its last known one, faded.
        var mini = Self.mini
        mini.state = .reconnecting
        var focus = Self.mockup
        focus.running.append(
            Self.item(
                Self.session(
                    "s9", "Chạy benchmark", state: .working, minutesAgo: 30, workspace: "bench", machine: "m2",
                    machineName: "Mac mini", online: false)))
        try assertRenders(list([Self.macbook, mini], focus: focus, showsMachineNames: true), name: "home-two-macs")
        XCTAssertEqual(
            FocusRowView.subLine(for: focus.running[2], kind: .running, now: Self.now, showsMachineName: true),
            "bench · Claude Code · Mac mini")
    }

    func testRendersGroupsAndStates() throws {
        try assertRenders(list([Self.macbook, Self.mini], pending: Self.pending), name: "workspaces")

        // What the rows say (the SwiftUI accessibility tree is not reachable from a unit test, so the
        // words are checked where the views take them from).
        XCTAssertEqual(Self.macbook.listing, .rows)
        XCTAssertEqual(Self.mini.listing, .hidden, "an offline Mac shows no rows")
        XCTAssertEqual(Self.macbook.rows.map(\.title), ["shellx-ios", "relay", "web", "notes"])
        XCTAssertFalse(Self.macbook.showsOtherSessions)
    }

    func testRendersAllStatesAndLongNames() throws {
        var group = Self.macbook
        group.rows.append(Self.broken)
        try assertRenders(list([group]), name: "workspaces-error")
        try assertRenders(
            list([group], pending: Self.pending).environment(\.dynamicTypeSize, .accessibility3),
            name: "workspaces-ax3")
    }

    func testRendersOldMacBanner() throws {
        let old = WorkspaceGroup(
            id: "m3", name: "iMac", state: .online, isDefault: false, rows: [], allowsControl: false,
            listsWorkspaces: false, otherSessionCount: 2)
        try assertRenders(list([Self.macbook, old]), name: "workspaces-old-mac")
        XCTAssertEqual(old.listing, .updateMac)
        XCTAssertEqual(Self.macbook.listing, .rows)
        XCTAssertTrue(old.showsOtherSessions, "the old Mac's sessions stay reachable")
    }

    func testRendersOtherSessionsRow() throws {
        var group = Self.macbook
        group.otherSessionCount = 3
        var offline = Self.mini
        offline.otherSessionCount = 5
        try assertRenders(list([group, offline]), name: "workspaces-other-sessions")
        XCTAssertTrue(group.showsOtherSessions)
        XCTAssertFalse(offline.showsOtherSessions, "an offline Mac shows no row under its header")
        XCTAssertFalse(Self.macbook.showsOtherSessions, "no row when there is nothing to list")
    }

    func testAnOnlineMacWithNoWorkspaceSaysSo() throws {
        var empty = Self.macbook
        empty.rows = []
        XCTAssertEqual(empty.listing, .empty)
        try assertRenders(list([empty]), name: "workspaces-empty")
    }

    func testRendersEveryAlert() throws {
        for alert in WorkspaceAlert.allCases {
            try assertRenders(list([Self.macbook], alert: alert), name: "workspaces-alert-\(alert.rawValue)")
        }
    }

    func testRendersWithoutAnyMacOnline() throws {
        try assertRenders(list([Self.mini]), name: "workspaces-offline")
    }

    func testOtherSessionsListRenders() throws {
        let sessions = [
            MachineSession(
                machineID: "m1", machineName: "MacBook Pro", online: true,
                session: AgentSession(
                    sessionId: "s1", agent: "claude", workspaceId: "ws-gone", workspaceTitle: "old-experiment",
                    title: "Fix the flaky test", state: .working, stateSinceMs: 1_700_000_000_000 - 240_000,
                    lastActivityMs: 1_700_000_000_000)),
            MachineSession(
                machineID: "m1", machineName: "MacBook Pro", online: true,
                session: AgentSession(
                    sessionId: "s2", agent: "claude", workspaceId: "", workspaceTitle: "ssh-box", state: .ended,
                    lastActivityMs: 1_699_999_000_000)),
        ]
        try assertRenders(
            NavigationStack {
                OtherSessionsList(
                    machineName: "MacBook Pro", sessions: sessions, now: Date(timeIntervalSince1970: 1_700_000_000))
            },
            name: "workspaces-other-sessions-list")
        try assertRenders(
            NavigationStack { OtherSessionsList(machineName: "MacBook Pro", sessions: [], now: .now) },
            name: "workspaces-other-sessions-empty")
    }

    func testRenameSheetRenders() throws {
        try assertRenders(WorkspaceRenameSheet(current: "shellx-ios", save: { _ in }, cancel: {}), name: "workspaces-rename")
    }

    // MARK: - Words

    func testEveryStateHasWordsExceptIdle() {
        let styles = [WorkspaceState.needsYou, .running, .done, .error].map { AgentStateStyle($0) }
        for style in styles {
            XCTAssertFalse(style.text?.isEmpty ?? true)
            XCTAssertNotNil(style.color)
        }
        XCTAssertEqual(Set(styles.compactMap(\.text)).count, 4, "each state says something different")
        XCTAssertEqual(styles.map(\.colorName), ["StatusNeedsYou", "StatusRunning", "StatusDone", "StatusError"])
        XCTAssertNil(AgentStateStyle(.idle).text, "an idle workspace has no label")
        XCTAssertNil(AgentStateStyle(.idle).colorName)
    }

    func testGroupCaptionSaysWhyThereAreNoRows() {
        let offline = MachineGroupHeader.caption(for: .offline(since: Self.eightTwelve), machineName: "Mac mini")
        let time = MachineGroupHeader.time(Self.eightTwelve)
        XCTAssertTrue(offline?.contains(time) ?? false, "\(offline ?? "nil") names the last time")
        XCTAssertNil(MachineGroupHeader.caption(for: .online, machineName: "Mac"))
        for state in [MachineLinkState.revoked, .hostKeyChanged, .needsUpdate, .connecting, .reconnecting] {
            XCTAssertFalse(MachineGroupHeader.caption(for: state, machineName: "Mac")?.isEmpty ?? true, "\(state)")
        }
    }

    func testRowsShowOnlyWhileTheMacIsOrWasJustOnline() {
        XCTAssertEqual(
            [MachineLinkState.online, .connecting, .reconnecting, .offline(since: .now), .revoked, .hostKeyChanged, .needsUpdate]
                .map(WorkspaceGroup.rowsShow(for:)),
            [true, true, true, false, false, false, false])
    }

    // MARK: - What the Mac answered

    func testFeedbackFollowsTheMacsAnswer() {
        let m = "m1"
        XCTAssertEqual(
            WorkspaceFeedback.of(.ok(workspaceId: "ws-new"), for: .create, machineID: m), .open(Self.ref("ws-new")))
        XCTAssertEqual(WorkspaceFeedback.of(.ok(workspaceId: nil), for: .create, machineID: m), .nothing, "the row arrives by push")
        XCTAssertEqual(WorkspaceFeedback.of(.ok(workspaceId: nil), for: .rename, machineID: m), .nothing)
        XCTAssertEqual(WorkspaceFeedback.of(.ok(workspaceId: nil), for: .close, machineID: m), .nothing)
        for command in [WorkspaceCommand.create, .rename, .close] {
            XCTAssertEqual(WorkspaceFeedback.of(.notFound, for: command, machineID: m), .refresh)
            XCTAssertEqual(WorkspaceFeedback.of(.offline, for: command, machineID: m), .alert(.offline))
            XCTAssertEqual(WorkspaceFeedback.of(.failed, for: command, machineID: m), .alert(.failed))
            XCTAssertEqual(WorkspaceFeedback.of(.unknown, for: command, machineID: m), .alert(.unknown))
        }
        XCTAssertEqual(WorkspaceFeedback.of(.refused, for: .close, machineID: m), .alert(.refusedClose))
        XCTAssertEqual(WorkspaceFeedback.of(.refused, for: .create, machineID: m), .alert(.refusedControl))
        XCTAssertEqual(WorkspaceFeedback.of(.refused, for: .rename, machineID: m), .alert(.refusedControl))
    }

    func testEveryAlertSaysSomethingDifferent() {
        let messages = WorkspaceAlert.allCases.map(\.message)
        XCTAssertEqual(Set(messages).count, WorkspaceAlert.allCases.count)
        for message in messages { XCTAssertFalse(message.isEmpty) }
    }

    func testRenameNeedsAName() {
        XCTAssertFalse(WorkspaceRenameSheet.canSave(""))
        XCTAssertFalse(WorkspaceRenameSheet.canSave("  \n\t "))
        XCTAssertTrue(WorkspaceRenameSheet.canSave(" relay "))
        XCTAssertEqual(WorkspaceRenameSheet.cleaned("  relay \n"), "relay")
    }
}

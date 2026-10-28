import ShellXAppCore
import SwiftUI
import XCTest
@testable import ShellX

/// The workspace list, the app's home: two Macs (one offline) with a workspace in every state, a Mac
/// whose ShellX is too old for workspaces, the row of other agent sessions, each in light and dark
/// (`dev.sh screenshots` writes them out in en and vi), and the words and decisions behind the rows.
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

    private func list(
        _ groups: [WorkspaceGroup], pending: [MachinePendingItem] = [], alert: WorkspaceAlert? = nil
    ) -> some View {
        NavigationStack {
            WorkspaceListScreen(groups: groups, pending: pending, alert: .constant(alert))
        }
    }

    // MARK: - Screens

    func testRendersGroupsAndStates() throws {
        try assertRenders(list([Self.macbook, Self.mini], pending: Self.pending), name: "workspaces")

        // What the rows say (the SwiftUI accessibility tree is not reachable from a unit test, so the
        // words are checked where the views take them from).
        XCTAssertEqual(Self.macbook.listing, .rows)
        XCTAssertEqual(Self.mini.listing, .hidden, "an offline Mac shows no rows")
        XCTAssertEqual(Self.macbook.rows.map(\.title), ["shellx-ios", "relay", "web", "notes"])
        let labels = Self.macbook.rows.map { AgentStateStyle($0.state).text }
        XCTAssertEqual(labels.map { $0 != nil }, [true, true, true, false], "all but the idle one have a label")
        XCTAssertEqual(
            Self.macbook.rows.map(WorkspaceRowView.quotedQuestion(for:)),
            ["\u{201C}Cho phép chạy xcodebuild test?\u{201D}", nil, nil, nil])
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

    func testMetaLineJoinsBranchDirectoryAndPorts() {
        XCTAssertEqual(
            WorkspaceRowView.metaLine(for: Self.shellx), "feat/workspaces · ~/shellx/shellx-ios")
        XCTAssertEqual(WorkspaceRowView.metaLine(for: Self.relay), "main · ~/shellx/relay · :8787")
        XCTAssertEqual(WorkspaceRowView.metaLine(for: Self.notes), "~")
        XCTAssertEqual(WorkspaceRowView.metaLine(for: Self.broken), "feature/a-long-branch-name · ~/code/a/deeply/nested/directory · :3000 :3001 :5173")
        XCTAssertNil(WorkspaceRowView.metaLine(for: WorkspaceRow(id: Self.ref("x"), title: "x")))
    }

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

import ShellXAppCore
import SwiftUI
import XCTest
@testable import ShellX

/// The home ("ShellX"): empty, full (two pending requests, three agents, six entries), with the
/// Mac offline, at an accessibility text size and with an overlong draft, each in light and dark
/// (`dev.sh screenshots` writes them out in en and vi).
@MainActor
final class HomeRenderTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)
    private static let nowMs: Int64 = 1_700_000_000_000

    private func assertRenders(_ view: some View, name: String) throws {
        let images = try SnapshotWriter().write(view, name: name)
        XCTAssertEqual(images.count, 2)
        for image in images { XCTAssertEqual(image.size, SnapshotWriter.size) }
        XCTAssertNotEqual(images.first?.pngData(), images.last?.pngData(), "light and dark renders should differ")
    }

    // MARK: - Fixtures

    private static func session(
        _ id: String, workspace: String, state: AgentState, sinceAgo: Int64?, online: Bool = true,
        machine: String = "MacBook Pro"
    ) -> MachineSession {
        MachineSession(
            machineID: "m1", machineName: machine, online: online,
            session: AgentSession(
                sessionId: id, agent: "claude", workspaceId: "ws-\(workspace)", workspaceTitle: workspace, state: state,
                stateSinceMs: sinceAgo.map { nowMs - $0 }, lastActivityMs: nowMs - (sinceAgo ?? 0)))
    }

    private static let sessions = [
        session("s1", workspace: "shellx", state: .working, sinceAgo: 240_000),
        session("s2", workspace: "web", state: .needsInput, sinceAgo: 30_000),
        session("s3", workspace: "relay", state: .idle, sinceAgo: 600_000),
    ]

    private static var shellx: SessionRef { sessions[0].ref }
    private static var web: SessionRef { sessions[1].ref }

    private static let pending = [
        MachinePendingItem(
            machineID: "m1", machineName: "MacBook Pro",
            item: PendingItem(
                requestId: "p1", kind: .permission, agent: "claude", workspaceId: "ws-web", workspaceTitle: "web",
                toolName: "Bash", toolInputPreview: #"{"command":"git push origin feat/home"}"#, createdAtMs: 1,
                modes: ["once", "always", "deny"]),
            actionable: true),
        MachinePendingItem(
            machineID: "m1", machineName: "MacBook Pro",
            item: PendingItem(
                requestId: "q1", kind: .question, agent: "claude", workspaceId: "ws-shellx", workspaceTitle: "shellx",
                createdAtMs: 2,
                questions: [
                    PendingQuestion(
                        id: "q", prompt: "Which colour should the primary button use?", multiSelect: false,
                        options: [
                            PendingQuestionOption(id: "blue", label: "Blue #60a5fa"),
                            PendingQuestionOption(id: "gray", label: "Gray"),
                        ])
                ]),
            actionable: true),
        MachinePendingItem(
            machineID: "m1", machineName: "MacBook Pro",
            item: PendingItem(
                requestId: "x1", kind: .exitPlan, agent: "claude", workspaceId: "ws-relay", workspaceTitle: "relay",
                createdAtMs: 3, modes: ["auto_accept", "manual", "deny"], planPreview: "1. Add tests.\n2. Ship."),
            actionable: true),
    ]

    private static func entry(_ index: Int, _ content: HomeEntry.Content) -> HomeEntry {
        HomeEntry(id: "e\(index)", at: now.addingTimeInterval(Double(index)), content: content)
    }

    private static var conversation: [HomeEntry] {
        [
            entry(0, .userSaid(text: "Sửa CI đỏ cho shellx đi", target: shellx, viaVoice: true)),
            entry(1, .note(.sent(shellx))),
            entry(2, .userSaid(text: "Còn trang chủ thì sao?", target: web, viaVoice: false)),
            entry(3, .note(.sendFailed(web, .busy))),
            entry(4, .note(.agentFinished(shellx, summary: "Đã sửa import thiếu, CI xanh rồi."))),
            entry(5, .note(.noLiveSession)),
        ]
    }

    private func home(
        machine: (name: String, state: MachineLinkState)? = ("MacBook Pro", .online),
        pending: [MachinePendingItem] = [], sessions: [MachineSession] = [], entries: [HomeEntry] = [],
        target: SessionRef? = nil, draft: String = "", expanded: Bool = true
    ) -> some View {
        let rows = AgentStatusRow.rows(sessions, now: Self.now)
        return NavigationStack {
            HomeScreen(
                machine: machine, pending: pending, pendingStatus: [:], showsMachineName: false, rows: { rows },
                entries: entries, target: target, pickedTarget: nil, sessions: sessions, draft: .constant(draft),
                agentsExpanded: .constant(expanded))
        }
    }

    // MARK: - Screens

    func testEmptyHomeRenders() throws {
        try assertRenders(home(), name: "home-empty")
    }

    func testFullHomeRenders() throws {
        try assertRenders(
            home(pending: Array(Self.pending.prefix(2)), sessions: Self.sessions, entries: Self.conversation,
                 target: Self.shellx),
            name: "home-full")
    }

    func testMoreThanTwoPendingOffersSeeAllAndCollapsedAgents() throws {
        try assertRenders(
            home(pending: Self.pending, sessions: Self.sessions, entries: Self.conversation, target: Self.shellx,
                 expanded: false),
            name: "home-see-all")
    }

    func testMacOfflineRenders() throws {
        let offline = Self.sessions.map { session -> MachineSession in
            var copy = session
            copy.online = false
            return copy
        }
        let entries = Self.conversation + [
            Self.entry(6, .userSaid(text: "Có ai không?", target: nil, viaVoice: false)),
            Self.entry(7, .note(.machineOffline(machineName: "MacBook Pro"))),
        ]
        try assertRenders(
            home(machine: ("MacBook Pro", .offline(since: Self.now)), sessions: offline, entries: entries),
            name: "home-offline")
    }

    func testHomeRendersAtAccessibilityTextSize() throws {
        try assertRenders(
            home(pending: Array(Self.pending.prefix(2)), sessions: Self.sessions, entries: Self.conversation,
                 target: Self.shellx)
                .environment(\.dynamicTypeSize, .accessibility3),
            name: "home-ax3")
    }

    func testOverlongDraftRenders() throws {
        let draft = String(repeating: "ệ", count: 5_461) + "ab"
        XCTAssertEqual(ComposerValidation(draft), .tooLong(bytes: 16_385))
        XCTAssertFalse(ComposerValidation(draft).canSend)
        try assertRenders(
            home(sessions: Self.sessions, entries: Self.conversation, target: Self.shellx, draft: draft),
            name: "home-too-long")
    }

    // MARK: - Words

    func testAgentStatesHaveWordsAndColors() {
        let rows = AgentStatusRow.rows(Self.sessions, now: Self.now)
        let styles = rows.map(AgentStateStyle.init)
        XCTAssertEqual(rows.map(\.state), [.needsInput, .working, .idle])
        XCTAssertEqual(styles.map(\.colorName), ["StatusNeedsYou", "StatusRunning", "StatusDone"])
        for style in styles { XCTAssertFalse(style.text?.isEmpty ?? true) }

        var offline = Self.sessions[0]
        offline.online = false
        let offlineStyle = AgentStateStyle(AgentStatusRow(session: offline, now: Self.now))
        XCTAssertEqual(offlineStyle.colorName, "StatusIdle")
        XCTAssertEqual(offlineStyle.text, String(localized: "agent.state.offline"), "offline wins over the last state")

        var unknown = Self.sessions[0]
        unknown.session.state = .other("paused")
        let unknownStyle = AgentStateStyle(AgentStatusRow(session: unknown, now: Self.now))
        XCTAssertNil(unknownStyle.text, "a state this app does not know has no badge")
        XCTAssertNil(unknownStyle.colorName)
    }

    func testElapsedTimeInTheAppLanguage() {
        let vi = Locale(identifier: "vi")
        let en = Locale(identifier: "en")
        XCTAssertEqual(AgentStateStyle.elapsedText(.seconds(240), locale: vi), "4 phút")
        XCTAssertEqual(AgentStateStyle.elapsedText(.seconds(240), locale: en), "4 minutes")
        XCTAssertEqual(AgentStateStyle.elapsedText(.seconds(299), locale: en), "4 minutes", "not rounded up")
        XCTAssertEqual(AgentStateStyle.elapsedText(.seconds(30), locale: en), "30 seconds")
        XCTAssertTrue(AgentStateStyle.elapsedText(.seconds(3_900), locale: en).contains("1 hour"))
    }

    func testEveryNoteHasASentence() {
        let notes: [HomeNote] = [
            .sent(Self.shellx), .sendFailed(Self.shellx, .notFound), .sendFailed(Self.shellx, .busy),
            .sendFailed(Self.shellx, .failed), .sendFailed(Self.shellx, .noAnswer),
            .machineOffline(machineName: "MacBook Pro"), .noLiveSession,
            .agentFinished(Self.shellx, summary: "CI xanh"), .agentFinished(Self.shellx, summary: nil),
        ]
        let texts = notes.map(HomeNoteRow.text(for:))
        XCTAssertEqual(Set(texts).count, notes.count, "each note reads differently")
        for (note, text) in zip(notes, texts) {
            switch note {
            case .machineOffline: XCTAssertTrue(text.contains("MacBook Pro"))
            case .noLiveSession: XCTAssertTrue(text.contains("Claude Code"))
            default:
                XCTAssertTrue(text.contains("Claude Code") && text.contains("shellx"), text)
            }
        }
        XCTAssertTrue(texts[7].contains("CI xanh"))
    }
}

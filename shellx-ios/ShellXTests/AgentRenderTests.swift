import ShellXAppCore
import SwiftUI
import XCTest
@testable import ShellX

/// One agent's screen: every kind of chat entry, an entry the Mac cut, a long code block, a
/// collapsed thought, 500 entries of 4 KB, and the empty, loading, offline and gone states, each in
/// light and dark (`dev.sh screenshots` writes them out in en and vi).
@MainActor
final class AgentRenderTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)
    private static let nowMs: Int64 = 1_700_000_000_000

    private func assertRenders(_ view: some View, name: String) throws {
        let images = try SnapshotWriter().write(view, name: name)
        XCTAssertEqual(images.count, 2)
        for image in images { XCTAssertEqual(image.size, SnapshotWriter.size) }
        XCTAssertNotEqual(images.first?.pngData(), images.last?.pngData(), "light and dark renders should differ")
    }

    // MARK: - Fixtures

    private static let session = MachineSession(
        machineID: "m1", machineName: "MacBook Pro", online: true,
        session: AgentSession(
            sessionId: "s1", agent: "claude", workspaceId: "ws-shellx", workspaceTitle: "shellx", state: .working,
            stateSinceMs: nowMs - 240_000, lastActivityMs: nowMs - 5_000))

    private static var ref: SessionRef { session.ref }

    private static func entry(
        _ seq: Int, _ role: ChatEntryRole, _ kind: ChatEntryKind, _ text: String, tool: String? = nil,
        truncated: Bool? = nil
    ) -> ChatEntry {
        ChatEntry(
            id: "e\(seq)", rev: 1, seq: seq, role: role, kind: kind, text: text, truncated: truncated, toolName: tool,
            tsMs: nowMs - Int64((20 - seq) * 30_000))
    }

    private static let everyKind: [ChatEntry] = [
        entry(1, .user, .prose, "Sửa giúp mình lỗi build ở shellx nhé."),
        entry(2, .agent, .thought, "Lỗi nằm ở bước link; xem log trước đã. Có thể thiếu import ShellXAppCore."),
        entry(3, .agent, .toolUse, "swift build --package-path shellx-ios/Packages/ShellXAppCore", tool: "Bash"),
        entry(4, .system, .status, "Đã nén ngữ cảnh."),
        entry(5, .agent, .prose, "Mình đã sửa **import thiếu** trong `HomeView.swift`:\n\n- thêm `import ShellXAppCore`\n- chạy lại `swift test`\n\nBuild xanh rồi."),
        entry(6, .agent, .other("attachment"), "image.png (240 KB)"),
        entry(7, .agent, .prose, String(repeating: "Log rất dài… ", count: 60), truncated: true),
    ]

    private static let pending = MachinePendingItem(
        machineID: "m1", machineName: "MacBook Pro",
        item: PendingItem(
            requestId: "p1", kind: .permission, agent: "claude", workspaceId: "ws-shellx", workspaceTitle: "shellx",
            toolName: "Bash", toolInputPreview: #"{"command":"git push origin feat/agent"}"#, createdAtMs: 1,
            modes: ["once", "always", "deny"]),
        actionable: true)

    private func screen(
        session: MachineSession? = AgentRenderTests.session, entries: [ChatEntry] = AgentRenderTests.everyKind,
        pending: [MachinePendingItem] = [], gone: Bool = false, offline: Bool = false,
        emptyState: AgentThreadModel.EmptyState? = nil, older: AgentThreadModel.Older = .none,
        notice: String? = nil, draft: String = ""
    ) -> some View {
        let row = session.map { AgentStatusRow(session: $0, now: Self.now) }
        let canStop = row.map { $0.online && ($0.state == .working || $0.state == .needsInput) } ?? false
        return NavigationStack {
            AgentScreen(
                ref: Self.ref, place: "Claude Code · MacBook Pro", row: { row }, gone: gone, offline: offline,
                pending: pending, showsMachineName: false, entries: entries,
                emptyState: entries.isEmpty ? emptyState : nil, machineName: "MacBook Pro", older: older,
                loadingOlder: false, canStop: canStop && !gone,
                notice: notice.map { AgentScreen.Notice(text: $0) }, draft: .constant(draft))
        }
    }

    /// The size a view asks for when offered the snapshot width, after SwiftUI settled its state. A
    /// view that does not wrap reports more than that width.
    private func size(of view: some View) -> CGSize {
        let width = SnapshotWriter.size.width
        let host = UIHostingController(rootView: view)
        // The window's safe area (status bar, home indicator) is not part of the row.
        host.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(origin: .zero, size: SnapshotWriter.size))
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.view.layoutIfNeeded()
        let size = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        window.isHidden = true
        return size
    }

    private func row(_ entry: ChatEntry, expanded: Bool = false) -> some View {
        ChatEntryRow(entry: entry, agent: "Claude Code", expanded: expanded)
            .padding(.horizontal, 16)
    }

    // MARK: - Entries

    func testEveryKindRenders() throws {
        try assertRenders(screen(pending: [Self.pending], notice: String(localized: "agent.stop.sent")), name: "agent-kinds")
    }

    func testTruncatedEntryShowsMarker() throws {
        let text = String(repeating: "Log rất dài… ", count: 20)
        let cut = Self.entry(1, .agent, .prose, text, truncated: true)
        let whole = Self.entry(1, .agent, .prose, text)

        let marker = String(localized: "agent.cut")
        XCTAssertTrue(marker.hasPrefix("…"))
        XCTAssertTrue(ChatEntryRow.accessibilityText(for: cut, agent: "Claude Code").hasSuffix(marker))
        XCTAssertFalse(ChatEntryRow.accessibilityText(for: whole, agent: "Claude Code").contains(marker))
        XCTAssertGreaterThan(size(of: row(cut)).height, size(of: row(whole)).height + 10, "the marker takes a line")

        // Every kind shows it, the user's own text and a collapsed thought too.
        for kind in [ChatEntryKind.thought, .toolUse, .status, .other("x")] {
            let role: ChatEntryRole = kind == .status ? .system : .agent
            let cutKind = Self.entry(2, role, kind, "abc", tool: "Bash", truncated: true)
            let wholeKind = Self.entry(2, role, kind, "abc", tool: "Bash")
            XCTAssertGreaterThan(size(of: row(cutKind)).height, size(of: row(wholeKind)).height + 10, "\(kind)")
        }
        let mine = Self.entry(3, .user, .prose, text, truncated: true)
        XCTAssertGreaterThan(size(of: row(mine)).height, size(of: row(Self.entry(3, .user, .prose, text))).height + 10)

        // VoiceOver hears the marker once per entry: in the entry's own label, never twice.
        for (role, kind) in [
            (ChatEntryRole.user, ChatEntryKind.prose), (.agent, .prose), (.system, .prose), (.agent, .thought),
            (.agent, .toolUse), (.system, .status), (.agent, .other("x")),
        ] {
            let entry = Self.entry(4, role, kind, "abc", tool: "Bash", truncated: true)
            let label = ChatEntryRow.accessibilityText(for: entry, agent: "Claude Code")
            XCTAssertEqual(label.components(separatedBy: marker).count - 1, 1, "\(role) \(kind): \(label)")
        }
        try assertRenders(screen(entries: [whole, cut, mine]), name: "agent-cut")
    }

    func testLongCodeBlockWraps() throws {
        // About 4 KB: a fenced block with a 600-character line and many short ones.
        let long = String(repeating: "x", count: 600)
        let lines = (1...60).map { "let value\($0) = compute(\($0)) // مرحبا 🚀" }
        let code = "Kết quả:\n\n```swift\n\(long)\n\(lines.joined(separator: "\n"))\n```\n\nXong."
        XCTAssertLessThanOrEqual(code.utf8.count, ChatEntry.maxTextBytes)
        let entry = Self.entry(1, .agent, .prose, code)

        let measured = size(of: row(entry))
        XCTAssertLessThanOrEqual(measured.width, SnapshotWriter.size.width + 0.5, "a long line wraps, it never widens the chat")
        XCTAssertGreaterThan(measured.height, 600, "every line shows")
        XCTAssertEqual(PlanMarkdownText.blocks(code).filter { if case .code = $0 { return true } else { return false } }.count, 1)

        // A long tool call stays on one line until tapped.
        let tool = Self.entry(2, .agent, .toolUse, long + "\n" + lines.joined(separator: "\n"), tool: "Bash")
        let collapsed = size(of: row(tool)).height
        XCTAssertLessThan(collapsed, 80)
        XCTAssertGreaterThan(size(of: row(tool, expanded: true)).height, collapsed * 5)
        try assertRenders(screen(entries: [entry, tool]), name: "agent-code")
    }

    func testThoughtStartsCollapsed() throws {
        let text = (1...12).map { "Bước \($0): kiểm tra lại giả định." }.joined(separator: "\n")
        let thought = Self.entry(1, .agent, .thought, text)

        let collapsed = size(of: row(thought)).height
        let open = size(of: row(thought, expanded: true)).height
        XCTAssertLessThan(collapsed, 60, "collapsed: only the Thinking label")
        XCTAssertGreaterThanOrEqual(collapsed, 44, "the label is a full tap target")
        XCTAssertGreaterThan(open, collapsed + 100)
        try assertRenders(
            VStack(spacing: 12) {
                row(thought)
                row(thought, expanded: true)
                Spacer()
            }
            .padding(.top, 60)
            .background(Color.appBackground),
            name: "agent-thought")
    }

    func testFiveHundredEntriesOfFourKilobytesRender() throws {
        let text = String(repeating: "ệ", count: 1_365) + "a"
        XCTAssertEqual(text.utf8.count, ChatEntry.maxTextBytes)
        let entries = (1...ChatThread.maxEntries).map { seq in
            Self.entry(seq, seq.isMultiple(of: 7) ? .user : .agent, seq.isMultiple(of: 5) ? .toolUse : .prose, text,
                       tool: "Bash", truncated: true)
        }
        try assertRenders(screen(entries: entries, older: .onlyOnMac), name: "agent-500")
    }

    // MARK: - States

    func testStatesRender() throws {
        try assertRenders(screen(entries: [], emptyState: .noMessages), name: "agent-empty")
        try assertRenders(screen(entries: [], emptyState: .loading), name: "agent-loading")
        var offline = Self.session
        offline.online = false
        try assertRenders(screen(session: offline, offline: true, draft: "Còn đó không?"), name: "agent-offline")
        try assertRenders(
            screen(session: offline, entries: [], offline: true, emptyState: .offline), name: "agent-offline-empty")
        try assertRenders(screen(entries: [], emptyState: .failed), name: "agent-failed")
        try assertRenders(screen(session: nil, gone: true), name: "agent-gone")
        try assertRenders(screen(session: nil, entries: [], gone: true, emptyState: .gone), name: "agent-gone-empty")
        try assertRenders(
            screen(entries: Array(Self.everyKind.prefix(3)), older: .failed), name: "agent-older-failed")
        try assertRenders(
            screen(pending: [Self.pending], older: .loadable).environment(\.dynamicTypeSize, .accessibility3),
            name: "agent-ax3")
    }

    func testNewMessagesButtonRenders() throws {
        XCTAssertNotEqual(String(localized: "agent.newMessages"), "agent.newMessages")
        let button = NewMessagesButton(action: {})
        XCTAssertGreaterThanOrEqual(size(of: button).height, 44, "a full tap target")
        try assertRenders(
            VStack {
                Spacer()
                button
                Spacer().frame(height: 120)
            }
            .frame(maxWidth: .infinity)
            .background(Color.appBackground),
            name: "agent-new-messages")
    }

    func testHeaderSaysTheState() {
        let working = AgentStatusRow(session: Self.session, now: Self.now)
        XCTAssertEqual(
            AgentHeader.status(row: working, gone: false, offline: false).text,
            String(localized: "agent.state.running \(AgentStateStyle.elapsedText(.seconds(240)))"))
        XCTAssertEqual(AgentHeader.status(row: working, gone: true, offline: false).text, String(localized: "agent.gone"))
        XCTAssertEqual(
            AgentHeader.status(row: nil, gone: false, offline: true).text, String(localized: "agent.state.offline"))
        XCTAssertNil(AgentHeader.status(row: nil, gone: false, offline: false).text)
        var ended = Self.session
        ended.session.state = .ended
        XCTAssertEqual(
            AgentHeader.status(row: AgentStatusRow(session: ended, now: Self.now), gone: false, offline: false).text,
            String(localized: "agent.state.ended"))
    }

    func testEverySendAndStopResultHasItsWords() {
        let results: [AgentSendResult] = [
            .refused(.tooLong(bytes: 16_385)), .sent(.submitted), .sent(.busy), .sent(.notFound), .sent(.failed),
            .offline, .noAnswer,
        ]
        let texts = results.compactMap { AgentView.text(for: $0, ref: Self.ref, machineName: "MacBook Pro") }
        XCTAssertEqual(texts.count, results.count)
        XCTAssertEqual(Set(texts).count, results.count, "each result reads differently")
        XCTAssertEqual(texts[2], String(localized: "agent.busy"))
        XCTAssertEqual(texts[3], String(localized: "agent.gone"))
        XCTAssertTrue(texts[5].contains("MacBook Pro"), "offline names the Mac")
        XCTAssertNil(AgentView.text(for: .refused(.empty), ref: Self.ref, machineName: "MacBook Pro"))
        XCTAssertEqual(
            AgentView.text(for: .sent(.other("x")), ref: Self.ref, machineName: "MacBook Pro"),
            AgentView.text(for: .sent(.failed), ref: Self.ref, machineName: "MacBook Pro"))

        let stops = [
            StopButton.text(for: .sent, offline: false, machineName: "MacBook Pro"),
            StopButton.text(for: .notFound, offline: false, machineName: "MacBook Pro"),
            StopButton.text(for: .failed, offline: false, machineName: "MacBook Pro"),
            StopButton.text(for: nil, offline: true, machineName: "MacBook Pro"),
            StopButton.text(for: nil, offline: false, machineName: "MacBook Pro"),
        ]
        XCTAssertEqual(Set(stops).count, stops.count)
        XCTAssertEqual(stops[0], String(localized: "agent.stop.sent"))
        XCTAssertTrue(stops[3].contains("MacBook Pro"))
        // No answer is final for a stop: not the pending cards' "not yet" line.
        XCTAssertEqual(stops[4], String(localized: "agent.stop.noAnswer"))
        XCTAssertNotEqual(stops[4], String(localized: "pending.status.noAnswer"))
    }
}

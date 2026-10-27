import Foundation
import ShellXLinkCore

/// What the Debug demo's Mac (`SHELLX_DEMO=1`) does over time, so every screen has something to
/// show before a real Mac serves phones.
///
/// `setUp()` gives the Mac two Claude Code sessions, both working, each with a chat history that
/// holds every kind of entry (user, agent and system; prose, thought, tool use, status; one cut
/// short). Then every `interval`, `step(_:)` adds a pending request, in turn a permission, a
/// question and a plan, and switches one session between working and idle. At most `maxPending`
/// requests wait at once: the oldest is resolved when another comes.
public actor FakeMacDemoScript {
    public static let interval: Duration = .seconds(20)
    public static let maxPending = 6

    public nonisolated let mac: FakeMac
    private let now: @Sendable () -> Date
    private var waiting: [String] = []
    private var sessions: [AgentSession] = []

    public init(mac: FakeMac, now: @escaping @Sendable () -> Date = { Date() }) {
        self.mac = mac
        self.now = now
    }

    /// `setUp()` (unless already done), then a `step` after every `interval`, until the task is
    /// cancelled.
    public func run(sleep: @Sendable (Duration) async throws -> Void, setUp runsSetUp: Bool = true) async {
        if runsSetUp { await setUp() }
        var index = 0
        while !Task.isCancelled {
            do { try await sleep(Self.interval) } catch { return }
            await step(index)
            index += 1
        }
    }

    public func setUp() async {
        let ms = millis()
        sessions = [
            AgentSession(
                sessionId: "demo-shellx", agent: "claude", workspaceId: "ws-shellx", workspaceTitle: "shellx",
                title: "Pairing sheet", state: .working, stateSinceMs: ms - 90_000, lastActivityMs: ms - 5_000),
            AgentSession(
                sessionId: "demo-web", agent: "claude", workspaceId: "ws-web", workspaceTitle: "web",
                title: "Landing page", state: .working, stateSinceMs: ms - 300_000, lastActivityMs: ms - 60_000),
        ]
        for session in sessions {
            await mac.setHistory(sessionId: session.sessionId, entries: Self.history(for: session.workspaceTitle, at: ms))
            await mac.upsertSession(session)
        }
    }

    /// The `index`-th tick (0, 1, 2…).
    public func step(_ index: Int) async {
        let ms = millis()
        let id = "demo-\(index)-\(ms)"
        let session = sessions.isEmpty ? nil : sessions[index % sessions.count]
        let workspace = session?.workspaceTitle ?? "shellx"
        await mac.addPending(Self.request(id: id, kind: index % 3, workspace: workspace, at: ms))
        waiting.append(id)
        while waiting.count > Self.maxPending {
            await mac.resolvePending(waiting.removeFirst())
        }
        guard !sessions.isEmpty else { return }
        let slot = index % sessions.count
        sessions[slot].state = sessions[slot].state == .working ? .idle : .working
        sessions[slot].stateSinceMs = ms
        sessions[slot].lastActivityMs = ms
        await mac.upsertSession(sessions[slot])
        let entry = ChatEntry(
            id: "\(sessions[slot].sessionId)-tick-\(index)", rev: 1, seq: 100 + index, role: .agent, kind: .prose,
            text: sessions[slot].state == .idle ? "Xong. Mình đã chạy lại test, tất cả đều xanh." : "Đang làm tiếp…",
            tsMs: ms)
        await mac.pushChat(sessionId: sessions[slot].sessionId, entries: [entry])
    }

    private func millis() -> Int64 { Int64(now().timeIntervalSince1970 * 1000) }

    private static func request(id: String, kind: Int, workspace: String, at ms: Int64) -> PendingItem {
        switch kind {
        case 0:
            return PendingItem(
                requestId: id, kind: .permission, agent: "claude", workspaceId: "ws-\(workspace)",
                workspaceTitle: workspace, toolName: "Bash",
                toolInputPreview: #"{"command":"git push origin feat/pairing","description":"Push the branch"}"#,
                createdAtMs: ms, modes: ["once", "always", "deny"])
        case 1:
            return PendingItem(
                requestId: id, kind: .question, agent: "claude", workspaceId: "ws-\(workspace)",
                workspaceTitle: workspace, createdAtMs: ms, modes: [],
                questions: [
                    PendingQuestion(
                        id: "q1", header: "Màu", prompt: "Nút chính nên dùng màu nào?", multiSelect: false,
                        options: [
                            PendingQuestionOption(id: "blue", label: "Xanh #60a5fa", description: "Màu chính của ShellX"),
                            PendingQuestionOption(id: "gray", label: "Xám", description: "Ít nổi hơn"),
                        ])
                ])
        default:
            return PendingItem(
                requestId: id, kind: .exitPlan, agent: "claude", workspaceId: "ws-\(workspace)",
                workspaceTitle: workspace, createdAtMs: ms, modes: ["auto_accept", "manual", "deny"],
                planPreview: """
                    1. Thêm PairingModel và test.
                    2. Làm sheet ghép cặp: quét QR, dán mã, xác nhận.
                    3. Danh sách "Máy của bạn" với gỡ ghép cặp.
                    """)
        }
    }

    private static func history(for workspace: String, at ms: Int64) -> [ChatEntry] {
        let texts: [(ChatEntryRole, ChatEntryKind, String, String?, Bool?)] = [
            (.user, .prose, "Sửa giúp mình lỗi build ở \(workspace) nhé.", nil, nil),
            (.agent, .thought, "Lỗi nằm ở bước link; xem log trước đã.", nil, nil),
            (.agent, .toolUse, "swift build", "Bash", nil),
            (.system, .status, "Đã nén ngữ cảnh.", nil, nil),
            (.agent, .prose, String(repeating: "Log rất dài… ", count: 40), nil, true),
            (.agent, .prose, "Mình đã sửa import thiếu. Build xanh rồi.", nil, nil),
        ]
        return texts.enumerated().map { offset, entry in
            ChatEntry(
                id: "\(workspace)-\(offset)", rev: 1, seq: offset + 1, role: entry.0, kind: entry.1, text: entry.2,
                truncated: entry.4, toolName: entry.3, tsMs: ms - Int64((texts.count - offset) * 30_000))
        }
    }
}

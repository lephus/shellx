import CmuxAgentChat
import CmuxMobileHost
import Foundation
import ShellXLinkCore
import ShellXLinkSession

/// ShellX: ShellX Link's chat (`chat.*`) over ``AgentChatTranscriptService``: transcript pages, live entries,
/// and the send and interrupt commands, for Claude Code sessions only (v1).
///
/// * Entries are the service's ``ChatMessage``s mapped to ``ChatEntry`` (prose, thought, tool use, status,
///   other), with `text` cut to ``ChatEntry/maxTextBytes``. Live entries come from `appended` and `updated`
///   frames; P2 skips the live prose preview (`streamingProse`) and transcript resets.
/// * `rev` comes from one counter for every emission, history and push alike, so it rises strictly per
///   entry id. The counter starts at the wall clock in microseconds, so a relaunched Mac never reuses a
///   revision a phone still holds.
/// * The tailer updates its cache before it publishes a batch, so a history read can return an entry older
///   than a push that reached the main actor while the read was in flight. Such an entry is served with the
///   pushed content (and a new `rev`), so a stale copy never outranks the push on the phone.
/// * A listed session whose agent has not written its transcript yet has an empty history; `nil` (the
///   phone's `not_found`) is for sessions the Mac does not have or cannot read.
/// * Send and interrupt run ``TerminalController/agentChatSend(sessionID:text:attachments:)`` and
///   ``TerminalController/agentChatInterrupt(sessionID:hard:)``, the paths behind `mobile.chat.send` and
///   `mobile.chat.interrupt`, and only for a session whose agent still runs (not ended, a known live pid);
///   any other session is `not_found` before a terminal is touched (PROTOCOL.md section 10).
///
/// The frame observer is registered only while someone subscribes to ``entries()``; it also keeps the
/// service tailing transcripts with no mobile client subscribed. All state is main-actor isolated.
@MainActor
final class ShellXLinkChatSource: AgentChatSource {
    typealias Send = @MainActor (_ sessionID: String, _ text: String) async -> TerminalController.V2CallResult
    typealias Interrupt = @MainActor (_ sessionID: String, _ hard: Bool) async -> TerminalController.V2CallResult
    typealias Push = (sessionId: String, entries: [ChatEntry])

    /// A history read in flight, from ``beginHistoryRead(sessionId:)`` to ``finishHistoryRead(_:page:)``.
    struct HistoryRead {
        fileprivate let id = UUID()
    }

    private let serviceProvider: @MainActor () -> AgentChatTranscriptService?
    private let sendCommand: Send
    private let interruptCommand: Interrupt
    private var subscribers: [UUID: AsyncStream<Push>.Continuation] = [:]
    /// Streams that ended before their subscription ran; never subscribed afterwards.
    private var endedEarly: Set<UUID> = []
    private var observation: (service: AgentChatTranscriptService, token: UUID)?
    /// Reads in flight: their session and the entries pushed for it meanwhile, by entry id.
    private var reads: [UUID: (sessionId: String, pushed: [String: ChatEntry])] = [:]
    private var lastRev: Int

    /// - Parameters:
    ///   - service: The app's transcript service; nil until the app wires it.
    ///   - send: Types a message into a session; tests replace the shared `TerminalController` path.
    ///   - interrupt: Interrupts a session; tests replace the shared `TerminalController` path.
    init(
        service: @escaping @MainActor () -> AgentChatTranscriptService? = { TerminalController.shared.agentChatTranscriptService },
        send: @escaping Send = { await TerminalController.shared.agentChatSend(sessionID: $0, text: $1) },
        interrupt: @escaping Interrupt = { await TerminalController.shared.agentChatInterrupt(sessionID: $0, hard: $1) }
    ) {
        self.serviceProvider = service
        self.sendCommand = send
        self.interruptCommand = interrupt
        self.lastRev = Self.clockRev()
    }

    /// Live subscriptions (tests).
    var subscriberCount: Int { subscribers.count }

    // MARK: - AgentChatSource

    func history(sessionId: String, beforeSeq: Int?, limit: Int) async -> (entries: [ChatEntry], hasMore: Bool)? {
        guard let service = linkSession(sessionId) else { return nil }
        let read = beginHistoryRead(sessionId: sessionId)
        let page = await service.historyRebindingIfStale(sessionID: sessionId, beforeSeq: beforeSeq, limit: limit)
        guard let page else {
            reads[read.id] = nil
            // A listed session whose agent has not written its transcript yet has an empty history, not
            // `not_found` (PROTOCOL.md 4, ChatEntry); its entries arrive in `chat.entries` once written.
            return await service.isAwaitingTranscript(sessionID: sessionId) ? ([], false) : nil
        }
        return finishHistoryRead(read, page: page)
    }

    func send(sessionId: String, text: String) async -> ChatSendOutcome {
        guard hasLiveAgent(sessionId) else { return .notFound }
        return Self.sendOutcome(await sendCommand(sessionId, text))
    }

    func interrupt(sessionId: String, hard: Bool) async -> ChatInterruptOutcome {
        guard hasLiveAgent(sessionId) else { return .notFound }
        return Self.interruptOutcome(await interruptCommand(sessionId, hard))
    }

    nonisolated func entries() -> AsyncStream<(sessionId: String, entries: [ChatEntry])> {
        let (stream, continuation) = AsyncStream<Push>.makeStream(bufferingPolicy: .unbounded)
        let id = UUID()
        // Synchronous from cancellation, `finish()` or release: only schedule the removal.
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.unsubscribe(id) }
        }
        Task { @MainActor in self.subscribe(id, continuation) }
        return stream
    }

    // MARK: - History reads

    /// Starts recording the pushes for `sessionId` that a history read must not undercut.
    func beginHistoryRead(sessionId: String) -> HistoryRead {
        let read = HistoryRead()
        reads[read.id] = (sessionId, [:])
        return read
    }

    /// The read's page as entries: each entry pushed while the read was in flight carries the pushed content.
    func finishHistoryRead(_ read: HistoryRead, page: ChatHistoryPage) -> (entries: [ChatEntry], hasMore: Bool) {
        let pushed = reads.removeValue(forKey: read.id)?.pushed ?? [:]
        let entries = page.messages.map { message -> ChatEntry in
            var entry = pushed[message.id] ?? Self.entry(message, rev: 0)
            entry.rev = nextRev()
            return entry
        }
        return (entries, page.hasMore)
    }

    // MARK: - Subscriptions

    private func subscribe(_ id: UUID, _ continuation: AsyncStream<Push>.Continuation) {
        guard endedEarly.remove(id) == nil else { return }
        subscribers[id] = continuation
        startObserving()
    }

    private func unsubscribe(_ id: UUID) {
        guard subscribers.removeValue(forKey: id) != nil else {
            endedEarly.insert(id)
            return
        }
        guard subscribers.isEmpty, let observation else { return }
        observation.service.removeFrameObserver(observation.token)
        self.observation = nil
    }

    private func startObserving() {
        guard observation == nil, !subscribers.isEmpty, let service = serviceProvider() else { return }
        let token = service.addFrameObserver { [weak self] frame in self?.receive(frame) }
        observation = (service, token)
    }

    /// Publishes the entries of an `appended` or `updated` frame of a Claude Code session.
    func receive(_ frame: ChatSessionEventFrame) {
        let messages: [ChatMessage]
        switch frame.event {
        case .appended(let list), .updated(let list): messages = list
        case .stateChanged, .descriptorChanged, .sessionRemoved, .terminalBlocks, .streamingProse, .reset, .unknown:
            return
        }
        guard !messages.isEmpty, linkSession(frame.sessionID) != nil else { return }
        let entries = messages.map { Self.entry($0, rev: nextRev()) }
        for (id, read) in reads where read.sessionId == frame.sessionID {
            for entry in entries { reads[id]?.pushed[entry.id] = entry }
        }
        for continuation in subscribers.values {
            continuation.yield((sessionId: frame.sessionID, entries: entries))
        }
    }

    // MARK: - Mapping

    /// The service when `sessionId` is a Claude Code agent session it knows.
    private func linkSession(_ sessionId: String) -> AgentChatTranscriptService? {
        linkRecord(sessionId)?.service
    }

    private func linkRecord(_ sessionId: String) -> (service: AgentChatTranscriptService, record: AgentChatSessionRecord)? {
        guard let service = serviceProvider() else { return nil }
        if !subscribers.isEmpty { startObserving() }
        guard let record = service.sessionRecord(sessionID: sessionId),
              record.agentKind == .claude, record.descriptor.kind == .agent else {
            return nil
        }
        return (service, record)
    }

    /// Whether a phone's text or interrupt may go to `sessionId` (PROTOCOL.md section 10): a Claude Code session
    /// that has not ended and whose agent process the Mac knows by pid and finds alive. The send path then types
    /// into the terminal the agent ran in; once the agent is gone that terminal runs the user's shell (or whatever
    /// started next), so text must never reach it. Stricter than the mobile path, which trusts a binding without
    /// a pid: a session whose pid the Mac has not learned yet is `not_found` here until a hook names it.
    private func hasLiveAgent(_ sessionId: String) -> Bool {
        guard let record = linkRecord(sessionId)?.record, let pid = record.pid else { return false }
        if case .ended = record.state { return false }
        return Self.processIsAlive(pid)
    }

    /// `kill(pid, 0)`: the process exists (EPERM: it exists under another user).
    private static func processIsAlive(_ pid: Int) -> Bool {
        guard pid > 0, let id = pid_t(exactly: pid) else { return false }
        return kill(id, 0) == 0 || errno == EPERM
    }

    private func nextRev() -> Int {
        lastRev = max(lastRev + 1, Self.clockRev())
        return lastRev
    }

    private static func clockRev() -> Int {
        Int(Date().timeIntervalSince1970 * 1_000_000)
    }

    /// `message` as a Link entry with `text` cut to ``ChatEntry/maxTextBytes``.
    static func entry(_ message: ChatMessage, rev: Int) -> ChatEntry {
        let role: ChatEntryRole = switch message.role {
        case .user: .user
        case .agent: .agent
        case .system: .system
        }
        let (kind, text, toolName) = content(message.kind)
        let cut = ChatEntry.cut(text)
        let ms = (message.timestamp.timeIntervalSince1970 * 1000).rounded()
        return ChatEntry(
            id: message.id, rev: rev, seq: message.seq, role: role, kind: kind, text: cut.text,
            truncated: cut.truncated ? true : nil, toolName: toolName, tsMs: ms > 0 ? Int64(ms) : 0
        )
    }

    /// The Link kind, display text and tool name of a message kind: tool runs, terminal commands and file
    /// edits are all `tool_use`; kinds Link has no card for are `other` with a one-line summary.
    private static func content(_ kind: ChatMessageKind) -> (ChatEntryKind, String, String?) {
        switch kind {
        case .prose(let prose):
            return (.prose, prose.text, nil)
        case .thought(let thought):
            return (.thought, thought.text, nil)
        case .toolUse(let tool):
            return (.toolUse, firstLine(tool.summary), tool.toolName)
        case .terminal(let capture):
            return (.toolUse, capture.command, "Bash")
        case .fileEdit(let edit):
            let tool = switch edit.operation {
            case .edit: "Edit"
            case .write: "Write"
            case .delete: "Delete"
            }
            return (.toolUse, edit.filePath, tool)
        case .status(let status):
            return (.status, [status.event.rawValue, status.detail].compactMap { $0 }.joined(separator: ": "), nil)
        case .permissionRequest(let request):
            return (other, firstLine([request.title, request.subject].filter { !$0.isEmpty }.joined(separator: ": ")), nil)
        case .question(let question):
            return (other, firstLine(question.prompt), nil)
        case .attachment(let attachment):
            return (other, attachment.displayName ?? attachment.media.rawValue, nil)
        case .unsupported(let payload):
            return (other, payload.rawType, nil)
        }
    }

    private static let other = ChatEntryKind.other("other")

    private static func firstLine(_ text: String) -> String {
        String(text.prefix { $0 != "\n" && $0 != "\r" })
    }

    /// `chat.send` outcome of the shared send path: `input_queue_full` (and a paste already in flight) is
    /// `busy`; a paste whose submit key failed is `failed` (the next send clears the prompt first).
    static func sendOutcome(_ result: TerminalController.V2CallResult) -> ChatSendOutcome {
        switch result {
        case .ok(let payload):
            return (payload as? [String: Any])?["submitted"] as? Bool == false ? .failed : .submitted
        case .err(let code, _, _):
            switch code {
            case "not_found": return .notFound
            case "input_queue_full", "busy": return .busy
            default: return .failed
            }
        }
    }

    static func interruptOutcome(_ result: TerminalController.V2CallResult) -> ChatInterruptOutcome {
        switch result {
        case .ok: return .sent
        case .err(let code, _, _): return code == "not_found" ? .notFound : .failed
        }
    }
}

import Foundation
import ShellXLinkCore
import ShellXLinkSession

/// `FakeMac`'s chat: an `AgentChatSource` in memory. A session has a transcript once `setHistory`
/// or `push` named it; others answer `not_found`. It takes attachments unless made with
/// `acceptsAttachments` false, and records them as they arrive with a message.
final class FakeMacChat: AgentChatSource, @unchecked Sendable {
    typealias Push = ChatPush

    let acceptsAttachments: Bool
    private let lock = NSLock()
    /// Entries by session, then by `ChatEntry.id` (upserts).
    private var transcripts: [String: [String: ChatEntry]] = [:]
    private var subscribers: [UUID: AsyncStream<Push>.Continuation] = [:]
    private var sendOutcome: ChatSendOutcome?
    private var interruptOutcome: ChatInterruptOutcome?
    private var sends: [FakeMac.SentText] = []
    private var attachments: [ChatAttachment] = []
    private var interruptCalls: [FakeMac.Interrupt] = []
    private var historyCalls: [FakeMac.HistoryRequest] = []
    private var holding = false
    private var held: [CheckedContinuation<Void, Never>] = []

    var sentTexts: [FakeMac.SentText] { lock.withLock { sends } }
    var receivedAttachments: [ChatAttachment] { lock.withLock { attachments } }

    init(acceptsAttachments: Bool) {
        self.acceptsAttachments = acceptsAttachments
    }
    var interrupts: [FakeMac.Interrupt] { lock.withLock { interruptCalls } }
    var historyRequests: [FakeMac.HistoryRequest] { lock.withLock { historyCalls } }

    /// Chat calls are recorded, then wait for `release()`.
    func hold() {
        lock.withLock { holding = true }
    }

    func release() {
        let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            holding = false
            defer { held = [] }
            return held
        }
        for continuation in waiting { continuation.resume() }
    }

    private func waitWhileHeld() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let pass = lock.withLock { () -> Bool in
                guard holding else { return true }
                held.append(continuation)
                return false
            }
            if pass { continuation.resume() }
        }
    }

    func setHistory(sessionId: String, entries: [ChatEntry]) {
        lock.withLock { transcripts[sessionId] = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last }) }
    }

    /// Upserts entries into the transcript and pushes them to every subscriber.
    func push(sessionId: String, entries: [ChatEntry]) {
        lock.withLock {
            for entry in entries { transcripts[sessionId, default: [:]][entry.id] = entry }
            let push = ChatPush.upsert(sessionId: sessionId, entries: entries)
            for (id, continuation) in subscribers {
                if case .terminated = continuation.yield(push) { subscribers[id] = nil }
            }
        }
    }

    /// Replaces the session's transcript, as when the Mac reloads it, and pushes `chat.reset` to
    /// every subscriber, in order with the entries pushed before and after.
    func reset(sessionId: String, entries: [ChatEntry]) {
        lock.withLock {
            transcripts[sessionId] = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            for (id, continuation) in subscribers {
                if case .terminated = continuation.yield(.reset(sessionId: sessionId)) { subscribers[id] = nil }
            }
        }
    }

    func setSendOutcome(_ outcome: ChatSendOutcome?) {
        lock.withLock { sendOutcome = outcome }
    }

    func setInterruptOutcome(_ outcome: ChatInterruptOutcome?) {
        lock.withLock { interruptOutcome = outcome }
    }

    /// Answers from the transcript as it is when the call arrives, like a Mac reading its file; a
    /// held call delivers that answer later (after a reset, it is the old transcript's page).
    func history(sessionId: String, beforeSeq: Int?, limit: Int) async -> (entries: [ChatEntry], hasMore: Bool)? {
        let page = lock.withLock { () -> (entries: [ChatEntry], hasMore: Bool)? in
            historyCalls.append(FakeMac.HistoryRequest(sessionId: sessionId, beforeSeq: beforeSeq, limit: limit))
            guard let all = transcripts[sessionId]?.values.sorted(by: { $0.seq < $1.seq }) else { return nil }
            let older = all.filter { entry in beforeSeq.map { entry.seq < $0 } ?? true }
            return (Array(older.suffix(limit)), older.count > limit)
        }
        await waitWhileHeld()
        return page
    }

    func send(sessionId: String, text: String) async -> ChatSendOutcome {
        lock.withLock { sends.append(FakeMac.SentText(sessionId: sessionId, text: text)) }
        await waitWhileHeld()
        return lock.withLock {
            if let sendOutcome { return sendOutcome }
            return transcripts[sessionId] == nil ? .notFound : .submitted
        }
    }

    /// A message with attachments: recorded like a text (`sentTexts`), its attachments in order.
    func send(sessionId: String, text: String, attachments: [ChatAttachment]) async -> ChatSendOutcome {
        lock.withLock { self.attachments.append(contentsOf: attachments) }
        return await send(sessionId: sessionId, text: text)
    }

    func interrupt(sessionId: String, hard: Bool) async -> ChatInterruptOutcome {
        lock.withLock { interruptCalls.append(FakeMac.Interrupt(sessionId: sessionId, hard: hard)) }
        await waitWhileHeld()
        return lock.withLock {
            if let interruptOutcome { return interruptOutcome }
            return transcripts[sessionId] == nil ? .notFound : .sent
        }
    }

    func entries() -> AsyncStream<Push> {
        let (stream, continuation) = AsyncStream.makeStream(of: Push.self)
        lock.withLock { subscribers[UUID()] = continuation }
        return stream
    }
}

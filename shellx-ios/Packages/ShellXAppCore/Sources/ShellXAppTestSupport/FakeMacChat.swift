import Foundation
import ShellXLinkCore
import ShellXLinkSession

/// `FakeMac`'s chat: an `AgentChatSource` in memory. A session has a transcript once `setHistory`
/// or `push` named it; others answer `not_found`.
final class FakeMacChat: AgentChatSource, @unchecked Sendable {
    typealias Push = (sessionId: String, entries: [ChatEntry])

    private let lock = NSLock()
    /// Entries by session, then by `ChatEntry.id` (upserts).
    private var transcripts: [String: [String: ChatEntry]] = [:]
    private var subscribers: [UUID: AsyncStream<Push>.Continuation] = [:]
    private var sendOutcome: ChatSendOutcome?
    private var interruptOutcome: ChatInterruptOutcome?
    private var sends: [FakeMac.SentText] = []
    private var interruptCalls: [FakeMac.Interrupt] = []
    private var historyCalls: [FakeMac.HistoryRequest] = []
    private var holding = false
    private var held: [CheckedContinuation<Void, Never>] = []

    var sentTexts: [FakeMac.SentText] { lock.withLock { sends } }
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
            for (id, continuation) in subscribers {
                if case .terminated = continuation.yield((sessionId, entries)) { subscribers[id] = nil }
            }
        }
    }

    func setSendOutcome(_ outcome: ChatSendOutcome?) {
        lock.withLock { sendOutcome = outcome }
    }

    func setInterruptOutcome(_ outcome: ChatInterruptOutcome?) {
        lock.withLock { interruptOutcome = outcome }
    }

    func history(sessionId: String, beforeSeq: Int?, limit: Int) async -> (entries: [ChatEntry], hasMore: Bool)? {
        lock.withLock {
            historyCalls.append(FakeMac.HistoryRequest(sessionId: sessionId, beforeSeq: beforeSeq, limit: limit))
        }
        await waitWhileHeld()
        return lock.withLock {
            guard let all = transcripts[sessionId]?.values.sorted(by: { $0.seq < $1.seq }) else { return nil }
            let older = all.filter { entry in beforeSeq.map { entry.seq < $0 } ?? true }
            return (Array(older.suffix(limit)), older.count > limit)
        }
    }

    func send(sessionId: String, text: String) async -> ChatSendOutcome {
        lock.withLock { sends.append(FakeMac.SentText(sessionId: sessionId, text: text)) }
        await waitWhileHeld()
        return lock.withLock {
            if let sendOutcome { return sendOutcome }
            return transcripts[sessionId] == nil ? .notFound : .submitted
        }
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

import Foundation
import ShellXLinkCore
import ShellXLinkSession

/// `FakeMac`'s chat: an `AgentChatSource` in memory. A session has a transcript once `setHistory`
/// or `push` named it; others answer `not_found`.
final class FakeMacChat: AgentChatSource, @unchecked Sendable {
    typealias Push = ChatPush

    private let lock = NSLock()
    /// Entries by session, then by `ChatEntry.id` (upserts).
    private var transcripts: [String: [String: ChatEntry]] = [:]
    private var subscribers: [UUID: AsyncStream<Push>.Continuation] = [:]
    private var sendOutcome: ChatSendOutcome?
    private var interruptOutcome: ChatInterruptOutcome?
    private var sends: [FakeMac.SentText] = []
    private var interruptCalls: [FakeMac.Interrupt] = []

    var sentTexts: [FakeMac.SentText] { lock.withLock { sends } }
    var interrupts: [FakeMac.Interrupt] { lock.withLock { interruptCalls } }

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

    func setSendOutcome(_ outcome: ChatSendOutcome?) {
        lock.withLock { sendOutcome = outcome }
    }

    func setInterruptOutcome(_ outcome: ChatInterruptOutcome?) {
        lock.withLock { interruptOutcome = outcome }
    }

    func history(sessionId: String, beforeSeq: Int?, limit: Int) async -> (entries: [ChatEntry], hasMore: Bool)? {
        lock.withLock {
            guard let all = transcripts[sessionId]?.values.sorted(by: { $0.seq < $1.seq }) else { return nil }
            let older = all.filter { entry in beforeSeq.map { entry.seq < $0 } ?? true }
            return (Array(older.suffix(limit)), older.count > limit)
        }
    }

    func send(sessionId: String, text: String) async -> ChatSendOutcome {
        lock.withLock {
            sends.append(FakeMac.SentText(sessionId: sessionId, text: text))
            if let sendOutcome { return sendOutcome }
            return transcripts[sessionId] == nil ? .notFound : .submitted
        }
    }

    func interrupt(sessionId: String, hard: Bool) async -> ChatInterruptOutcome {
        lock.withLock {
            interruptCalls.append(FakeMac.Interrupt(sessionId: sessionId, hard: hard))
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

import Foundation
import ShellXLinkCore
import ShellXLinkSession

/// An in-memory `AgentChatSource`: transcripts per session, configurable outcomes, and a log of calls.
/// A session exists when it has a transcript (possibly empty).
final class FakeChatSource: AgentChatSource, @unchecked Sendable {
    private let lock = NSLock()
    private var transcripts: [String: [ChatEntry]]
    private var sendOutcomes: [String: ChatSendOutcome] = [:]
    private var interruptOutcomes: [String: ChatInterruptOutcome] = [:]
    private var subscribers: [UUID: AsyncStream<ChatPush>.Continuation] = [:]
    private var _sends: [(sessionId: String, text: String)] = []
    private var _attachmentSends: [(sessionId: String, text: String, attachments: [ChatAttachment])] = []
    private var _interrupts: [(sessionId: String, hard: Bool)] = []
    private var _entriesCalls = 0
    private let terminationLock = NSLock()
    private var terminated: Set<UUID> = []

    let acceptsAttachments: Bool

    /// `transcripts` seeds each session's entries, oldest first. `acceptsAttachments` makes the host advertise
    /// the `attachments` feature and hand uploads to `send(sessionId:text:attachments:)`.
    init(_ transcripts: [String: [ChatEntry]] = [:], acceptsAttachments: Bool = false) {
        self.transcripts = transcripts
        self.acceptsAttachments = acceptsAttachments
    }

    /// The text-only sends (`send(sessionId:text:)`).
    var sends: [(sessionId: String, text: String)] { lock.withLock { _sends } }
    /// The sends that carried attachments, in the order the host made them.
    var attachmentSends: [(sessionId: String, text: String, attachments: [ChatAttachment])] {
        lock.withLock { _attachmentSends }
    }
    var interrupts: [(sessionId: String, hard: Bool)] { lock.withLock { _interrupts } }
    var entriesCalls: Int { lock.withLock { _entriesCalls } }
    var activeSubscribers: Int {
        let ids = lock.withLock { Set(subscribers.keys) }
        return ids.subtracting(terminationLock.withLock { terminated }).count
    }

    func setSendOutcome(_ outcome: ChatSendOutcome, for sessionId: String) {
        lock.withLock { sendOutcomes[sessionId] = outcome }
    }

    func setInterruptOutcome(_ outcome: ChatInterruptOutcome, for sessionId: String) {
        lock.withLock { interruptOutcomes[sessionId] = outcome }
    }

    /// Appends entries to a transcript and pushes them to every subscriber.
    func append(_ entries: [ChatEntry], to sessionId: String) {
        lock.withLock {
            transcripts[sessionId, default: []].append(contentsOf: entries)
            publish(.upsert(sessionId: sessionId, entries: entries))
        }
    }

    /// Replaces a transcript (as a fork or `claude --resume` does) and pushes a reset to every subscriber.
    func reset(_ sessionId: String, to entries: [ChatEntry]) {
        lock.withLock {
            transcripts[sessionId] = entries
            publish(.reset(sessionId: sessionId))
        }
    }

    /// Call with `lock` held.
    private func publish(_ push: ChatPush) {
        for (id, continuation) in subscribers {
            if case .terminated = continuation.yield(push) { subscribers[id] = nil }
        }
    }

    func history(sessionId: String, beforeSeq: Int?, limit: Int) async -> (entries: [ChatEntry], hasMore: Bool)? {
        lock.withLock {
            guard let all = transcripts[sessionId] else { return nil }
            let older = all.filter { entry in beforeSeq.map { entry.seq < $0 } ?? true }
            return (Array(older.suffix(limit)), older.count > limit)
        }
    }

    func send(sessionId: String, text: String) async -> ChatSendOutcome {
        lock.withLock {
            _sends.append((sessionId, text))
            guard transcripts[sessionId] != nil else { return .notFound }
            return sendOutcomes[sessionId] ?? .submitted
        }
    }

    func send(sessionId: String, text: String, attachments: [ChatAttachment]) async -> ChatSendOutcome {
        lock.withLock {
            _attachmentSends.append((sessionId, text, attachments))
            guard transcripts[sessionId] != nil else { return .notFound }
            return sendOutcomes[sessionId] ?? .submitted
        }
    }

    func interrupt(sessionId: String, hard: Bool) async -> ChatInterruptOutcome {
        lock.withLock {
            _interrupts.append((sessionId, hard))
            guard transcripts[sessionId] != nil else { return .notFound }
            return interruptOutcomes[sessionId] ?? .sent
        }
    }

    func entries() -> AsyncStream<ChatPush> {
        let (stream, continuation) = AsyncStream.makeStream(of: ChatPush.self)
        let id = UUID()
        lock.withLock {
            _entriesCalls += 1
            subscribers[id] = continuation
        }
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            _ = self.terminationLock.withLock { self.terminated.insert(id) }
        }
        return stream
    }
}

func chatEntry(
    _ seq: Int, rev: Int = 1, role: ChatEntryRole = .agent, kind: ChatEntryKind = .prose, text: String? = nil
) -> ChatEntry {
    ChatEntry(
        id: "e-\(seq)", rev: rev, seq: seq, role: role, kind: kind, text: text ?? "entry \(seq)",
        tsMs: 1_700_000_000_000 + Int64(seq))
}

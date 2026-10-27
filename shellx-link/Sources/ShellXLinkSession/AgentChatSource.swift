import ShellXLinkCore

/// One chat push of a host, in the order it was sent: new or changed entries of a session, or the reset of that
/// session's transcript (PROTOCOL.md section 4, `chat.entries` and `chat.reset`).
public enum ChatPush: Equatable, Sendable {
    /// `chat.entries`: new or changed entries of `sessionId`, upserts by `ChatEntry.id`.
    case upsert(sessionId: String, entries: [ChatEntry])
    /// `chat.reset`: the transcript of `sessionId` was replaced. Every entry held for it, and its `seq` values,
    /// are gone; the pushes after this one belong to the new transcript.
    case reset(sessionId: String)

    /// The session the push is about.
    public var sessionId: String {
        switch self {
        case let .upsert(sessionId, _), let .reset(sessionId): sessionId
        }
    }

    /// The upserted entries; empty for a reset. With ``sessionId`` it reads a push like the earlier
    /// `(sessionId, entries)` tuple, so a consumer written for that shape treats a reset as an empty upsert.
    public var entries: [ChatEntry] {
        switch self {
        case let .upsert(_, entries): entries
        case .reset: []
        }
    }
}

/// The host's chat transcripts and the commands that act on a session (PROTOCOL.md section 4,
/// `chat.*`).
public protocol AgentChatSource: Sendable {
    /// A page of the transcript of `sessionId`, oldest entry first: the newest `limit` entries whose
    /// `seq` is below `beforeSeq` (the newest entries when nil). `hasMore` is true when older entries
    /// exist. Nil when the session does not exist.
    func history(sessionId: String, beforeSeq: Int?, limit: Int) async -> (entries: [ChatEntry], hasMore: Bool)?
    /// Types `text` into the session as a new user message.
    ///
    /// Must return promptly or honor task cancellation: `LinkHost.serve` waits for in-flight calls
    /// before it returns, and the phone stops waiting after 10 s.
    func send(sessionId: String, text: String) async -> ChatSendOutcome
    /// Interrupts the session's current turn; `hard` asks for a stronger stop than the soft one.
    func interrupt(sessionId: String, hard: Bool) async -> ChatInterruptOutcome
    /// Every new or changed entry, and every transcript reset, from now on, in the order they happened: the
    /// host sends them to the phone in this order, so a reset separates the old transcript's entries from the
    /// new one's. The client upserts entries by `ChatEntry.id`.
    ///
    /// The source assigns `ChatEntry.rev`: every emission of an entry, here and in `history`, carries a
    /// `rev` strictly greater than any earlier emission of the same `id`. The host does not renumber it.
    /// The host cuts any `text` longer than `ChatEntry.maxTextBytes` before sending.
    ///
    /// Multicast, with the same lifetime and `onTermination` rules as `AgentFeedSource.changes()`.
    func entries() -> AsyncStream<ChatPush>
}

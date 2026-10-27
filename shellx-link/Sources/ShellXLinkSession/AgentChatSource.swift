import ShellXLinkCore

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
    /// Every new or changed entry from now on; the client upserts by `ChatEntry.id`.
    ///
    /// Multicast, with the same lifetime and `onTermination` rules as `AgentFeedSource.changes()`.
    func entries() -> AsyncStream<(sessionId: String, entries: [ChatEntry])>
}

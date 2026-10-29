import ShellXLinkCore

/// The host's list of agent sessions (PROTOCOL.md section 4, `agent.sessions`).
///
/// Its `revision` is a counter of its own, apart from the pending-set revision of `AgentFeedSource`.
public protocol AgentSessionSource: Sendable {
    /// The current sessions and their revision.
    func sessions() async -> (revision: Int, sessions: [AgentSession])
    /// Every change of the session list from now on. A source MUST raise `revision` by exactly 1
    /// per change, and `sessions()` at revision r includes every change up to r.
    ///
    /// Multicast, with the same lifetime and `onTermination` rules as `AgentFeedSource.changes()`:
    /// each call is a new subscriber, dropped when the consumer stops iterating, and
    /// `onTermination` must not take a lock that is held while calling `yield` or `finish`.
    func sessionChanges() -> AsyncStream<(revision: Int, upserted: [AgentSession], removed: [String])>
}

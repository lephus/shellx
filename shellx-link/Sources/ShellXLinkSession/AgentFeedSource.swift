import ShellXLinkCore

/// The host's view of the agent requests waiting for a human decision.
///
/// `LinkHost` reads it for every session; the app backs it with its agent hook state.
public protocol AgentFeedSource: Sendable {
    /// The current pending set and its revision.
    func snapshot() async -> (revision: Int, pending: [PendingItem])
    /// Every change of the pending set from now on.
    ///
    /// Multicast: each call is a new subscriber. The subscription ends when the stream's consumer
    /// stops iterating (its task is cancelled), and the source must then drop it.
    func changes() -> AsyncStream<(revision: Int, added: [PendingItem], resolved: [String])>
    /// Resolves `requestId` at most once (PROTOCOL.md section 5).
    func reply(requestId: String, mode: PermissionMode) async -> ReplyOutcome
}

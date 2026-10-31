import ShellXLinkCore

/// Closes an agent session's terminal on the host. A host that has one offers `agent_close`.
///
/// What a phone may do to a running agent (PROTOCOL.md section 10). The implementation applies the host's own rules,
/// acts without changing the host's selection or bringing its window to the front, and never logs a session's title.
/// The call carries only a session id, so it can reach nothing but a live agent the host itself lists.
///
/// Calls arrive concurrently and may take a while; the host serves other calls meanwhile.
public protocol AgentControl: Sendable {
    /// `.notFound` for a session the host does not list as a live agent in a local workspace;
    /// `.refused` when remote control is blocked or the host's rule forbids it; `.failed` when it could not act.
    func closeAgent(sessionId: String) async -> WorkspaceControlOutcome
}

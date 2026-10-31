import ShellXLinkCore

/// Closes one terminal tab of a workspace the host lists. A host that has one offers `terminal_close`.
///
/// What a phone may do to a terminal tab (PROTOCOL.md section 10). The implementation applies the host's own rules,
/// acts without changing the host's selection or bringing its window to the front, and never logs a workspace id,
/// a terminal id or a title. The call carries two ids and nothing else, so it can reach nothing but a terminal of
/// a local workspace the host itself lists. It does not look for a live agent: the user picked this tab.
///
/// Calls arrive concurrently and may take a while; the host serves other calls meanwhile.
public protocol TerminalControl: Sendable {
    /// `.notFound` for a terminal that is not in a workspace the host lists; `.refused` when remote control is
    /// blocked or the host's rule forbids it; `.failed` when it could not act.
    func closeTerminal(workspaceId: String, terminalId: String) async -> WorkspaceControlOutcome
}

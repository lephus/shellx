import ShellXLinkCore

/// Opens a terminal tab in a workspace the host lists (PROTOCOL.md 11.9). A host that has one offers `terminal_create`.
///
/// The implementation adds the tab in the pane the Mac has selected in that workspace, running the user's default
/// shell, without changing the Mac's selection (workspace, pane, the tab each pane shows), focus or window order. It
/// answers `.notFound` for a workspace it does not list, `.refused` when remote control is blocked or its rules forbid
/// it, `.failed` when it could not act, and gives `terminalId` only with `.ok`. It never logs a workspace's title.
/// Calls arrive concurrently and may take a while; the host serves other calls meanwhile.
public protocol TerminalCreator: Sendable {
    func createTerminal(workspaceId: String) async -> (outcome: WorkspaceControlOutcome, terminalId: String?)
}

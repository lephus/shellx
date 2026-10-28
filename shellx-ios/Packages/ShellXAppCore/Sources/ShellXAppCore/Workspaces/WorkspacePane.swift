import Foundation
import ShellXLinkCore

/// One chip of the workspace screen: a terminal of the workspace, and the agent running in it when
/// the hub lists that agent's session.
public struct WorkspacePane: Identifiable, Equatable, Sendable {
    /// The terminal's id on the Mac.
    public var id: String
    /// The tab's name on the Mac.
    public var title: String
    /// The session the terminal names (`LinkTerminal.sessionId`), as its Mac lists it. Nil for a shell,
    /// and for a terminal that names a session the Mac does not list (any more): that one shows as a
    /// shell, never as a chat with nothing behind it.
    public var session: MachineSession?

    public init(id: String, title: String, session: MachineSession? = nil) {
        self.id = id
        self.title = title
        self.session = session
    }

    /// The pane is an agent's chat; any other is a shell.
    public var isAgent: Bool { session != nil }

    /// The terminals of `workspace` as panes, in the Mac's order (`order`, then id). `session` gives the
    /// session a terminal names, if the hub lists it.
    static func panes(of workspace: LinkWorkspace, session: (String) -> MachineSession?) -> [WorkspacePane] {
        ordered(workspace.terminals).map { terminal in
            WorkspacePane(
                id: terminal.terminalId, title: terminal.title, session: terminal.sessionId.flatMap(session))
        }
    }

    /// `terminals` by `order`; two at the same position by id, so the chips do not shuffle between two answers.
    static func ordered(_ terminals: [LinkTerminal]) -> [LinkTerminal] {
        terminals.sorted { ($0.order, $0.terminalId) < ($1.order, $1.terminalId) }
    }
}

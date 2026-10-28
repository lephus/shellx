import Foundation

/// One terminal of a workspace, as listed in `workspace.list` (PROTOCOL.md section 4, "Workspace").
public struct LinkTerminal: Codable, Equatable, Sendable {
    /// Unique, stable id of the terminal: the surface id on the Mac.
    public var terminalId: String
    public var title: String
    /// Position among the workspace's terminals.
    public var order: Int
    /// Whether the terminal is the selected one on the Mac; a client uses it only to pick its default tab.
    public var selected: Bool
    /// The Claude Code session running in this terminal, matching `AgentSession.sessionId`, when there is one.
    public var sessionId: String?

    public init(terminalId: String, title: String, order: Int, selected: Bool, sessionId: String? = nil) {
        self.terminalId = terminalId
        self.title = title
        self.order = order
        self.selected = selected
        self.sessionId = sessionId
    }
}

/// One workspace of the Mac, as listed by `workspace.list`.
public struct LinkWorkspace: Codable, Equatable, Sendable {
    /// Unique, stable id; the same value as `AgentSession.workspaceId` and `PendingItem.workspaceId`.
    public var workspaceId: String
    public var title: String
    /// Position in the Mac's sidebar (across windows: window order, then order within the window).
    public var order: Int
    /// Display text for the working directory, with the home directory written `~`. Read-only.
    public var directory: String?
    public var branch: String?
    /// Listening ports, when the workspace has any.
    public var ports: [Int]?
    public var terminals: [LinkTerminal]

    public init(
        workspaceId: String, title: String, order: Int, directory: String? = nil, branch: String? = nil,
        ports: [Int]? = nil, terminals: [LinkTerminal]
    ) {
        self.workspaceId = workspaceId
        self.title = title
        self.order = order
        self.directory = directory
        self.branch = branch
        self.ports = ports
        self.terminals = terminals
    }

    /// The workspace after shrink steps 1 to `step` (PROTOCOL.md section 6, the shrink steps for `workspace.list`):
    /// 1 drops `ports`, 2 `directory`, 3 `branch`, 4 the `title` of every terminal (it becomes `""`). The steps add
    /// up, so each is a smaller frame than the one before. Nil for a step outside 1 to 4.
    public func shrunk(step: Int) -> LinkWorkspace? {
        guard (1...4).contains(step) else { return nil }
        var copy = self
        copy.ports = nil
        if step >= 2 { copy.directory = nil }
        if step >= 3 { copy.branch = nil }
        if step >= 4 { copy.terminals = terminals.map { var t = $0; t.title = ""; return t } }
        return copy
    }
}

/// How the host answered `workspace.create`, `workspace.rename` or `workspace.close`.
public enum WorkspaceControlOutcome: LinkWireEnum {
    case ok
    case notFound
    /// The Mac does not allow it: remote control is blocked, or its own rule forbids it (closing the last workspace).
    case refused
    case failed
    case other(String)

    public init(wire: String) {
        switch wire {
        case "ok": self = .ok
        case "not_found": self = .notFound
        case "refused": self = .refused
        case "failed": self = .failed
        default: self = .other(wire)
        }
    }

    public var wire: String {
        switch self {
        case .ok: return "ok"
        case .notFound: return "not_found"
        case .refused: return "refused"
        case .failed: return "failed"
        case let .other(raw): return raw
        }
    }
}

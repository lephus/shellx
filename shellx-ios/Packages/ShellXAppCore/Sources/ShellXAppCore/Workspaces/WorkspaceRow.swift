import Foundation
import ShellXLinkCore

/// What a workspace row says about the agents in it, most pressing first.
public enum WorkspaceState: Equatable, Sendable {
    /// A request of the workspace waits for the user.
    case needsYou
    /// An agent in the workspace is working.
    case running
    /// An agent in the workspace finished a turn and the user has not looked since.
    case done
    /// Reserved: nothing reports an error yet.
    case error
    /// No agent, or none doing anything.
    case idle
}

/// Points at one workspace on one Mac.
public struct WorkspaceRef: Hashable, Sendable {
    public var machineID: String
    public var workspaceId: String

    public init(machineID: String, workspaceId: String) {
        self.machineID = machineID
        self.workspaceId = workspaceId
    }
}

/// One line of a Mac's workspace list: the workspace as the Mac lists it, and a state worked out from
/// the Mac's sessions and pending requests.
public struct WorkspaceRow: Identifiable, Equatable, Sendable {
    public var id: WorkspaceRef
    public var title: String
    public var directory: String?
    public var branch: String?
    public var ports: [Int]
    public var state: WorkspaceState
    /// The first line of the first pending request of the workspace, while `state` is `.needsYou`.
    public var question: String?
    public var terminals: [LinkTerminal]

    public init(
        id: WorkspaceRef, title: String, directory: String? = nil, branch: String? = nil, ports: [Int] = [],
        state: WorkspaceState = .idle, question: String? = nil, terminals: [LinkTerminal] = []
    ) {
        self.id = id
        self.title = title
        self.directory = directory
        self.branch = branch
        self.ports = ports
        self.state = state
        self.question = question
        self.terminals = terminals
    }

    /// The longest `question`, in characters.
    static let questionLength = 140

    /// The rows for `workspaces`, in their order.
    ///
    /// The state, first match wins:
    /// - `.needsYou`: a pending request of the workspace is waiting; `question` is the first line of
    ///   the first one in `pending`;
    /// - `.running`: a session of the workspace is `working`;
    /// - `.done`: a session of the workspace is in `finished`, the ids `SessionFinishDetector` reported
    ///   finished and the user has not seen since (`MachineHub.finishedSessionIds(machineID:)`);
    /// - `.idle`.
    ///
    /// A session is in a workspace when its own `workspaceId` is the workspace's, or a terminal of the
    /// workspace names it (`LinkTerminal.sessionId`). `pending` of other Macs are left out.
    public static func rows(
        workspaces: WorkspaceSet, sessions: [AgentSession], pending: [MachinePendingItem], finished: Set<String>,
        machineID: String
    ) -> [WorkspaceRow] {
        workspaces.workspaces.map { workspace in
            let mine = sessionIds(workspaceId: workspace.workspaceId, terminals: workspace.terminals, among: sessions)
            let request = pending.first { $0.isIn(machineID: machineID, workspaceId: workspace.workspaceId) }
            let state: WorkspaceState
            var question: String?
            if let request {
                state = .needsYou
                question = request.item.previewText.flatMap(firstLine)
            } else if sessions.contains(where: { mine.contains($0.sessionId) && $0.state == .working }) {
                state = .running
            } else if !mine.isDisjoint(with: finished) {
                state = .done
            } else {
                state = .idle
            }
            return WorkspaceRow(
                id: WorkspaceRef(machineID: machineID, workspaceId: workspace.workspaceId), title: workspace.title,
                directory: workspace.directory, branch: workspace.branch, ports: workspace.ports ?? [], state: state,
                question: question, terminals: workspace.terminals)
        }
    }

    /// The ids of the sessions in a workspace: those of `sessions` whose `workspaceId` is
    /// `workspaceId`, and those one of its `terminals` names.
    static func sessionIds(workspaceId: String, terminals: [LinkTerminal], among sessions: [AgentSession]) -> Set<String> {
        let named = Set(terminals.compactMap(\.sessionId))
        return Set(
            sessions.filter { $0.workspaceId == workspaceId || named.contains($0.sessionId) }.map(\.sessionId))
    }

    /// The first non-blank line of `text`, trimmed, cut to `questionLength` characters (with "…").
    private static func firstLine(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline)
            .lazy.map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line else { return nil }
        guard line.count > questionLength else { return line }
        return String(line.prefix(questionLength - 1)) + "…"
    }
}

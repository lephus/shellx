import ShellXAppCore
import SwiftUI

/// The commands the list and the workspace screen send to a Mac.
enum WorkspaceCommand: Equatable {
    case create
    case rename
    case close
    /// Closes the terminal tab an agent runs in (`MachineHub.closeAgent(_:)`).
    case closeAgent
}

/// What the list says when a command did not simply work. The words always say what to do next.
enum WorkspaceAlert: String, CaseIterable, Identifiable {
    case offline
    case refusedClose
    case refusedControl
    /// The Mac has no terminal tab for the agent, or the agent has stopped already.
    case agentNotClosable
    case failed
    case unknown

    var id: String { rawValue }

    var message: String {
        switch self {
        case .offline: String(localized: "workspaces.alert.offline")
        case .refusedClose: String(localized: "workspaces.alert.refused.close")
        case .refusedControl: String(localized: "workspaces.alert.refused.control")
        case .agentNotClosable: String(localized: "workspaces.alert.agentNotClosable")
        case .failed: String(localized: "workspaces.alert.failed")
        case .unknown: String(localized: "workspaces.alert.unknown")
        }
    }
}

/// What the list does with a Mac's answer to a command.
enum WorkspaceFeedback: Equatable {
    /// Nothing to show: the row arrives, changes or leaves by the Mac's push.
    case nothing
    /// Opens the workspace just made.
    case open(WorkspaceRef)
    /// The Mac has no such workspace: asks for its list again, with no word to the user.
    case refresh
    case alert(WorkspaceAlert)

    /// The feedback for `result` of `command` on the Mac `machineID`.
    static func of(_ result: WorkspaceCommandResult, for command: WorkspaceCommand, machineID: String) -> WorkspaceFeedback {
        switch result {
        case let .ok(workspaceId):
            // A create the Mac answered without an id stays on the list: the new row arrives by push.
            guard command == .create, let workspaceId else { return .nothing }
            return .open(WorkspaceRef(machineID: machineID, workspaceId: workspaceId))
        case .notFound:
            // An agent the Mac cannot close is no sign the workspace list is stale: say why instead.
            return command == .closeAgent ? .alert(.agentNotClosable) : .refresh
        case .refused:
            return .alert(command == .close ? .refusedClose : .refusedControl)
        case .failed:
            return .alert(.failed)
        case .offline:
            return .alert(.offline)
        case .unknown:
            return .alert(.unknown)
        }
    }
}

extension View {
    /// Shows `alert`, when there is one, as an alert with "OK"; closing it clears the binding. The list
    /// and the workspace screen say the same words for the same answer.
    func workspaceAlert(_ alert: Binding<WorkspaceAlert?>) -> some View {
        self.alert(
            alert.wrappedValue?.message ?? "",
            isPresented: Binding(get: { alert.wrappedValue != nil }, set: { if !$0 { alert.wrappedValue = nil } })
        ) {
            Button(String(localized: "common.ok")) {}
        }
    }
}

extension View {
    /// Asks before an agent is closed: "Close <name>?", what closing does on the Mac, and one red "Close"
    /// (the system adds Cancel). Shown while `item` is set; `name` gives the agent's name, `close` runs once
    /// the user confirmed. The home's cards, the agents outside workspaces, the agent screen and the
    /// workspace screen ask the same way (HIG: Action sheets).
    func agentCloseConfirmation<Item>(
        _ item: Binding<Item?>, name: @escaping (Item) -> String, close: @escaping (Item) -> Void
    ) -> some View {
        confirmationDialog(
            item.wrappedValue.map { String(localized: "agent.close.title \(name($0))") } ?? "",
            isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } }),
            titleVisibility: .visible, presenting: item.wrappedValue
        ) { target in
            Button(String(localized: "agent.close"), role: .destructive) { close(target) }
        } message: { _ in
            Text(LocalizedStringResource("agent.close.confirm"))
        }
    }
}

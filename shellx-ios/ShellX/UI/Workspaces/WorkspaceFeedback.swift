import ShellXAppCore
import SwiftUI

/// The workspace commands of the list.
enum WorkspaceCommand: Equatable {
    case create
    case rename
    case close
}

/// What the list says when a command did not simply work. The words always say what to do next.
enum WorkspaceAlert: String, CaseIterable, Identifiable {
    case offline
    case refusedClose
    case refusedControl
    case failed
    case unknown

    var id: String { rawValue }

    var message: String {
        switch self {
        case .offline: String(localized: "workspaces.alert.offline")
        case .refusedClose: String(localized: "workspaces.alert.refused.close")
        case .refusedControl: String(localized: "workspaces.alert.refused.control")
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
            return .refresh
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

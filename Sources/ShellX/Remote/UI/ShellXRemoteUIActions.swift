import AppKit
import Foundation
import ShellXBrand
import ShellXRemoteCore

/// What the sidebar's remote rows do when clicked. Everything goes through
/// `ShellXRemoteUIModel.shared.service`, so with the gate off these are no-ops.
@MainActor
enum ShellXRemoteUIActions {
    /// U2 sets this to present `RequestAccessSheet` for the machine with the
    /// code `requestAccess` returned. Until then nothing is shown: the header
    /// switches to "waiting · 123 456" on the service's next update.
    static var presentRequestAccess: ((_ machineID: RemoteMachine.ID, _ code: String) -> Void)?

    static func requestAccess(to machineID: RemoteMachine.ID) {
        guard let service = ShellXRemoteUIModel.shared.service else { return }
        Task { @MainActor in
            do {
                let code = try await service.requestAccess(to: machineID)
                // ShellX: present RequestAccessSheet (U2)
                presentRequestAccess?(machineID, code)
            } catch {
                NSSound.beep()
            }
        }
    }

    static func openSession(on machineID: RemoteMachine.ID) {
        guard let service = ShellXRemoteUIModel.shared.service else { return }
        Task { @MainActor in
            do {
                try await service.openSession(on: machineID)
            } catch {
                NSSound.beep()
            }
        }
    }

    static func presentSignIn() {
        guard let service = ShellXRemoteUIModel.shared.service else { return }
        SignInSheetPresenter.shared.present(service: service)
    }

    /// A click on a ShellX header row: the sign-in row opens the sheet, an
    /// accessible remote machine opens a session. Returns false when the row
    /// does nothing.
    static func handleClick(on row: ShellXSidebarHeaderRow) -> Bool {
        switch row {
        case .brand:
            return false
        case .signIn:
            presentSignIn()
            return true
        case .machine(let header):
            guard case .remote(let machineID) = header.key, header.action == .open else { return false }
            openSession(on: machineID)
            return true
        }
    }
}

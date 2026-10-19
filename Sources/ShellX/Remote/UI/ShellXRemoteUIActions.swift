import AppKit
import Foundation
import ShellXBrand
import ShellXRemoteCore

/// What the sidebar's remote rows do when clicked. Everything goes through
/// `ShellXRemoteUIModel.shared.service`, so with the gate off these are no-ops.
@MainActor
enum ShellXRemoteUIActions {
    static func requestAccess(to machineID: RemoteMachine.ID) {
        guard let service = ShellXRemoteUIModel.shared.service else { return }
        Task { @MainActor in
            do {
                let code = try await service.requestAccess(to: machineID)
                // The sheet follows the machine's `OutgoingPairing` live; the
                // header also switches to "waiting · 123 456".
                presentRequestAccess(to: machineID, expectedCode: code)
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

    /// Shows (or brings back) the request-access sheet for `machineID`.
    /// `expectedCode` is the raw code ("123456") the request returned, if known.
    static func presentRequestAccess(to machineID: RemoteMachine.ID, expectedCode: String?) {
        guard let service = ShellXRemoteUIModel.shared.service else { return }
        RequestAccessSheetPresenter.shared.present(machineID: machineID, expectedCode: expectedCode, service: service)
    }

    static func presentSignIn() {
        guard let service = ShellXRemoteUIModel.shared.service else { return }
        SignInSheetPresenter.shared.present(service: service)
    }

    /// A click on a ShellX header row: the sign-in row opens the sheet, an
    /// accessible remote machine opens a session, a machine waiting for
    /// approval reopens its request-access sheet. Returns false when the row
    /// does nothing.
    static func handleClick(on row: ShellXSidebarHeaderRow) -> Bool {
        switch row {
        case .brand:
            return false
        case .signIn:
            presentSignIn()
            return true
        case .machine(let header):
            guard case .remote(let machineID) = header.key else { return false }
            switch header.action {
            case .open:
                openSession(on: machineID)
                return true
            case .waiting(let code):
                // The header shows the grouped code ("123 456"); the pairing holds it raw.
                presentRequestAccess(to: machineID, expectedCode: code.replacingOccurrences(of: " ", with: ""))
                return true
            default:
                return false
            }
        }
    }
}

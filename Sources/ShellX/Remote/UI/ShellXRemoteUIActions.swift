import AppKit
import Foundation
import ShellXBrand
import ShellXRemoteCore

/// What the sidebar's remote rows do when clicked. Everything goes through
/// `ShellXRemoteUIModel.shared.service`, so with the gate off these are no-ops. Phone pairing is the
/// exception: it works on this Mac's link host (`ShellXRemoteGate.servesPhones`). Settings › Mobile opens it;
/// the This Mac header's menu item exists only with remote machines on (`ShellXRemoteGate.isEnabled`).
@MainActor
enum ShellXRemoteUIActions {
    static func requestAccess(to machineID: RemoteMachine.ID) {
        guard let service = ShellXRemoteUIModel.shared.service else { return }
        Task { @MainActor in
            do {
                let code = try await service.requestAccess(to: machineID)
                // ShellX: present RequestAccessSheet (U2). The sheet follows the
                // machine's `OutgoingPairing` live; the header also switches to
                // "waiting · 123 456".
                presentRequestAccess(to: machineID, expectedCode: code)
            } catch {
                NSSound.beep()
            }
        }
    }

    /// A workspace closed: let the service forget it. No-op when the remote UI is off.
    static func workspaceClosed(_ id: UUID) {
        ShellXRemoteUIModel.shared.service?.forgetRemoteWorkspace(id)
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

    /// Settings › Mobile › "Show QR Code…" and "Pair iPhone…" on the This Mac header: shows the pairing sheet
    /// over this Mac's link host. With no link host running the sheet says the Mac is not ready, with no QR.
    ///
    /// - Parameter bringToFront: False from the DEBUG socket methods, which must not take focus.
    /// - Returns: The open sheet's coordinator.
    @discardableResult
    static func presentPhonePairing(bringToFront: Bool = true) -> ShellXPhonePairingCoordinator? {
        PhonePairingSheetPresenter.shared.present(bringToFront: bringToFront) { ShellXPhonePairingCoordinator.forApp() }
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

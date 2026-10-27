#if DEBUG
import Foundation
import ShellXRemoteCore

extension TerminalController {
    /// ShellX: `shellx.link.debug_pairing_offer {}` → `{offer_uri}` (DEBUG). Opens the "Pair iPhone" sheet
    /// through the same path as its menu item, then returns the URI the sheet's QR shows, so a probe can
    /// pair without a camera.
    ///
    /// Runs on the socket worker (`ControlCommandExecutionPolicy.socketWorkerMethods`): making the offer
    /// reads the host key off the main thread. A new sheet is attached to the main window without
    /// activating the app; an open one is left where it is. The reply holds the one-time pairing code, so
    /// nothing here logs it.
    nonisolated func v2ShellXLinkDebugPairingOffer(id: Any?, params: [String: Any]) -> String {
        v2AsyncResultCall(id: id, timeoutSeconds: 30) {
            let coordinator = await MainActor.run { ShellXRemoteUIActions.presentPhonePairing(bringToFront: false) }
            guard let coordinator else {
                return .err(code: "link_not_running", message: "this Mac has no ShellX Link host", data: nil)
            }
            do {
                let offer = try await coordinator.currentOffer()
                return .ok(["offer_uri": offer.uri])
            } catch {
                return Self.shellXLinkPairingError(error)
            }
        }
    }

    /// ShellX: `shellx.link.debug_pairing_approve {pairing_id}` → `{approved: true}` (DEBUG). Allows a
    /// request through the open sheet's coordinator, exactly as its Allow button does: only a request whose
    /// proof matches the QR on screen can be allowed.
    ///
    /// Runs on the socket worker: the approval blocks on the key store and on HTTP. It touches no window.
    nonisolated func v2ShellXLinkDebugPairingApprove(id: Any?, params: [String: Any]) -> String {
        guard let pairingID = params["pairing_id"] as? String, !pairingID.isEmpty else {
            return v2Error(id: id, code: "invalid_params",
                           message: "shellx.link.debug_pairing_approve requires pairing_id")
        }
        return v2AsyncResultCall(id: id, timeoutSeconds: 30) {
            let coordinator = await MainActor.run { PhonePairingSheetPresenter.shared.coordinator }
            guard let coordinator else {
                return .err(code: "pairing_not_open", message: "the phone pairing sheet is not open", data: nil)
            }
            do {
                try await coordinator.approve(pairingID)
                return .ok(["approved": true])
            } catch {
                return Self.shellXLinkPairingError(error)
            }
        }
    }

    private nonisolated static func shellXLinkPairingError(_ error: any Error) -> V2CallResult {
        if let core = error as? ShellXCoreError {
            return .err(code: core.code, message: core.message, data: nil)
        }
        return .err(code: ShellXLinkHostController.keyErrorKind(error), message: "phone pairing failed", data: nil)
    }
}
#endif

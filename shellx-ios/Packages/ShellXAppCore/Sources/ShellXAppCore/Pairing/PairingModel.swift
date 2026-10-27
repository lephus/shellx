import Foundation
import Observation
import ShellXLinkAccount
import ShellXLinkCore
import os

/// Pairing this iPhone with a Mac from its QR code (or a pasted or opened `shellx-link://` code).
///
/// A code is only read by `begin(uri:)`; nothing reaches the network until the user confirms the
/// Mac's name, so a link opened from elsewhere can never pair by itself. `confirm()` then asks the
/// relay, waits for the user to press Allow on the Mac, and hands the Mac to the hub, which saves it
/// and connects.
///
/// The code holds a one-time secret: it is kept in memory only until the attempt ends, and never
/// logged.
@MainActor @Observable
public final class PairingModel {
    public enum Step: Equatable, Sendable {
        /// Waiting for a code (the scanner is showing).
        case idle
        /// A valid code: ask "Pair with <name>?" before anything else happens.
        case confirm(machineName: String)
        /// The request is with the Mac; the user must press Allow there.
        case waitingForMac(machineName: String)
        case paired(machineName: String)
        case failed(PairingFailure)
    }

    public private(set) var step: Step = .idle

    @ObservationIgnored private let hub: MachineHub
    @ObservationIgnored private let relay: any RelayAccountCalling
    @ObservationIgnored private let vault: AccountVault
    @ObservationIgnored private let log = Logger(subsystem: "com.shellx.app", category: "pairing")
    /// The code being confirmed or paired; nil otherwise.
    @ObservationIgnored private var offerURI: String?
    /// The relay request of the current attempt; replaced or dropped when the attempt ends.
    @ObservationIgnored private var attempt: Task<PairedMachine, any Error>?

    public init(hub: MachineHub, relay: any RelayAccountCalling, vault: AccountVault) {
        self.hub = hub
        self.relay = relay
        self.vault = vault
    }

    /// Reads a code from the scanner, the pasteboard or an opened link. A valid one moves to
    /// `.confirm`; anything else to `.failed`. Never touches the network. A code arriving while an
    /// attempt is under way replaces it.
    public func begin(uri: String) {
        reset()
        let text = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let offer = try PairingOffer(uri: text)
            offerURI = text
            step = .confirm(machineName: offer.machineName)
        } catch {
            let failure = PairingFailure(error)
            log.notice("pairing_code_refused \(String(describing: failure), privacy: .public)")
            step = .failed(failure)
        }
    }

    /// The user confirmed the Mac: send the request with this phone's key and wait for the Mac's
    /// answer. Returns when the attempt ended (paired, failed, or cancelled by `cancel()`).
    public func confirm() async {
        guard case let .confirm(machineName) = step, let uri = offerURI else { return }
        step = .waitingForMac(machineName: machineName)
        let (relay, vault) = (self.relay, self.vault)
        let request = Task { () async throws -> PairedMachine in
            let clientKey = try await vault.phoneKey().publicKey
            guard let token = try await vault.session()?.token else { throw MachineHub.AddError.notSignedIn }
            return try await relay.pair(offerURI: uri, clientKey: clientKey, token: token)
        }
        attempt = request
        do {
            let machine = try await request.value
            // Cancelled or replaced while the Mac answered: this attempt no longer speaks.
            guard attempt == request else { return }
            try await hub.add(machine)
            guard attempt == request else { return }
            finish(.paired(machineName: machine.name))
        } catch {
            guard attempt == request else { return }
            let failure = PairingFailure(error)
            log.notice("pairing_failed \(String(describing: failure), privacy: .public)")
            finish(.failed(failure))
        }
    }

    /// Stops waiting for the Mac (the relay request is withdrawn) and goes back to `.idle`. Also
    /// what closing the sheet does, whatever the step.
    public func cancel() {
        reset()
        step = .idle
    }

    private func finish(_ outcome: Step) {
        attempt = nil
        offerURI = nil
        step = outcome
    }

    private func reset() {
        attempt?.cancel()
        attempt = nil
        offerURI = nil
    }
}

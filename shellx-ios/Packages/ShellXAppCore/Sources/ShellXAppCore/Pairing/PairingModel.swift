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
    @ObservationIgnored private var attempt: Task<Approval, any Error>?

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
        let text = Self.lowercasingScheme(uri.trimmingCharacters(in: .whitespacesAndNewlines))
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
        let request = Task { () async throws -> Approval in
            let clientKey = try await vault.phoneKey().publicKey
            guard let token = try await vault.session()?.token else { throw MachineHub.AddError.notSignedIn }
            let machine = try await relay.pair(offerURI: uri, clientKey: clientKey, token: token)
            return Approval(machine: machine, token: token)
        }
        attempt = request
        let approval: Approval
        do {
            approval = try await request.value
        } catch {
            guard attempt == request else { return }
            await fail(error)
            return
        }
        // Cancelled or replaced while the Mac answered: this attempt no longer speaks, and the grant
        // the relay just made would be left behind.
        guard attempt == request else {
            await withdraw(approval)
            return
        }
        do {
            try await hub.add(approval.machine)
        } catch {
            await withdraw(approval)
            guard attempt == request else { return }
            await fail(error)
            return
        }
        guard attempt == request else { return }
        finish(.paired(machineName: approval.machine.name))
    }

    /// Stops waiting for the Mac (the relay request is withdrawn) and goes back to `.idle`. Also
    /// what closing the sheet does, whatever the step.
    public func cancel() {
        reset()
        step = .idle
    }

    /// The system opens the app for `SHELLX-LINK://…` too, and a QR code may carry the scheme in
    /// capitals, but `PairingOffer` parses only the lowercase scheme: lowercase it first, so every
    /// way in (link, scan, paste) agrees with the parser.
    static func lowercasingScheme(_ text: String) -> String {
        guard let colon = text.firstIndex(of: ":"), text[..<colon].lowercased() == PairingInbox.scheme else {
            return text
        }
        return PairingInbox.scheme + text[colon...]
    }

    private func fail(_ error: any Error) async {
        let failure = PairingFailure(error)
        log.notice("pairing_failed \(String(describing: failure), privacy: .public)")
        finish(.failed(failure))
        // A refused token cannot pair, however often the user retries: back to the "session
        // expired" sign-in, the way the hub handles a 401 anywhere else.
        if LinkFailure(error) == .signedOut { await hub.reportUnauthorized() }
    }

    /// The relay granted this iPhone a Mac it is not keeping (the attempt was cancelled or
    /// replaced, or saving the Mac failed): take the grant back, so the Mac does not list an iPhone
    /// that does not know it. Best effort, errors only logged. A Mac this iPhone already keeps (a
    /// cancelled re-pair) keeps its grant: it is not an orphan.
    private func withdraw(_ approval: Approval) async {
        let machineID = approval.machine.machineID
        guard !hub.machines.contains(where: { $0.id == machineID }) else { return }
        do {
            for grant in try await relay.machines(token: approval.token) where grant.machineID == machineID {
                try await relay.unpair(grantID: grant.grantID, token: approval.token)
            }
        } catch {
            log.notice("pairing_withdraw_failed")
        }
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

/// What the relay answered for an attempt, with the token it was made with.
private struct Approval: Sendable {
    let machine: PairedMachine
    let token: String
}

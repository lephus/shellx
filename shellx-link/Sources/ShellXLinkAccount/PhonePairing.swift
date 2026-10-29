import Foundation
import ShellXLinkCore

/// A machine this phone is paired with. `hostKey` comes from the QR offer, never from the relay.
public struct PairedMachine: Codable, Equatable, Sendable {
    public var machineID: String
    public var name: String
    public var linkSlot: String
    public var hostKey: Data

    public init(machineID: String, name: String, linkSlot: String, hostKey: Data) {
        self.machineID = machineID
        self.name = name
        self.linkSlot = linkSlot
        self.hostKey = hostKey
    }
}

public enum PhonePairingError: Error, Equatable, Sendable {
    /// The user pressed Deny on the Mac.
    case denied
    /// Nobody approved within `PairingOffer.lifetime`, or the relay reports the request expired.
    case expired
}

public enum PhonePairing {
    /// Sends a pairing request for the scanned offer and waits (up to `PairingOffer.lifetime`) for
    /// the user to approve it on the Mac.
    ///
    /// Trust comes from the offer: the host key is the offer's, and the machine id and link slot the
    /// relay reports on approval must equal the offer's, otherwise `RelayAPIError.badResponse`.
    ///
    /// `onRequested` gets the relay's pairing id once the request is sent, before the first poll: the
    /// moment a UI switches to "approve on the Mac" (and a test harness can approve that id).
    public static func pair(
        offerURI: String,
        clientKey: Data,
        api: RelayAPI,
        token: String,
        pollInterval: Duration = .seconds(2),
        timeout: Duration = .seconds(PairingOffer.lifetime),
        onRequested: @Sendable (String) -> Void = { _ in }
    ) async throws -> PairedMachine {
        let offer = try PairingOffer(uri: offerURI)
        let id = try await api.requestPairing(offer: offer, clientKey: clientKey, token: token)
        onRequested(id)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        // Unless the relay itself reported the end of the request, leave nothing pending (or granted)
        // behind for a phone that is not going to pin the key: ask the relay to withdraw it, once.
        var relayDecided = false
        do {
            while true {
                try Task.checkCancellation()
                do {
                    switch try await api.pairingStatus(id: id, token: token) {
                    case .pending:
                        break
                    case .denied:
                        relayDecided = true
                        throw PhonePairingError.denied
                    case .expired:
                        relayDecided = true
                        throw PhonePairingError.expired
                    case let .approved(machineID, _, linkSlot):
                        guard machineID == offer.machineID, linkSlot == offer.linkSlot else {
                            throw RelayAPIError.badResponse
                        }
                        return PairedMachine(
                            machineID: offer.machineID, name: offer.machineName, linkSlot: offer.linkSlot,
                            hostKey: offer.hostKey)
                    }
                } catch let error as URLError where error.code != .cancelled {
                    // Transient (network): keep polling until the deadline.
                } catch RelayAPIError.http(let status, _) where status >= 500 {
                    // Transient (relay trouble): keep polling until the deadline.
                }
                guard clock.now < deadline else { throw PhonePairingError.expired }
                try await Task.sleep(for: pollInterval)
            }
        } catch {
            if !relayDecided {
                // Detached so that it still runs when this task was cancelled.
                await Task.detached { try? await api.cancelPairing(id: id, token: token) }.value
            }
            throw error
        }
    }
}

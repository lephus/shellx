import Foundation
import ShellXLinkCore

/// An Apple link the Mac allowed: the session the relay issued and the Mac to remember.
public struct AppleLinkApproval: Equatable, Sendable {
    public var signIn: AccountSignIn
    /// From the scanned offer: the host key is the QR code's, never the relay's.
    public var machine: PairedMachine

    public init(signIn: AccountSignIn, machine: PairedMachine) {
        self.signIn = signIn
        self.machine = machine
    }
}

public enum AppleLinkPairing {
    /// Sends the link request for the scanned offer with the link token of an Apple ID that has no account yet and
    /// waits (up to `PairingOffer.lifetime`) for Allow on the Mac. Like `PhonePairing.pair`, trust comes from the
    /// offer. Nothing is sent to withdraw the request: the relay has no route for it.
    public static func link(
        offerURI: String,
        linkToken: String,
        clientKey: Data,
        api: RelayAPI,
        pollInterval: Duration = .seconds(2),
        timeout: Duration = .seconds(PairingOffer.lifetime),
        onRequested: @Sendable (String) -> Void = { _ in }
    ) async throws -> AppleLinkApproval {
        let offer = try PairingOffer(uri: offerURI)
        let id = try await api.requestAppleLink(linkToken: linkToken, offer: offer, clientKey: clientKey)
        onRequested(id)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while true {
            try Task.checkCancellation()
            do {
                switch try await api.appleLinkStatus(linkToken: linkToken, pairingID: id) {
                case .pending:
                    break
                case .denied:
                    throw PhonePairingError.denied
                case .expired:
                    throw PhonePairingError.expired
                case let .approved(signIn, machineID, _, linkSlot):
                    guard machineID == offer.machineID, linkSlot == offer.linkSlot else {
                        throw RelayAPIError.badResponse
                    }
                    return AppleLinkApproval(
                        signIn: signIn,
                        machine: PairedMachine(
                            machineID: offer.machineID, name: offer.machineName, linkSlot: offer.linkSlot,
                            hostKey: offer.hostKey))
                }
            } catch let error as URLError where error.code != .cancelled {
                // Transient (network): keep polling until the deadline.
            } catch RelayAPIError.http(let status, _) where status >= 500 {
                // Transient (relay trouble): keep polling until the deadline.
            }
            guard clock.now < deadline else { throw PhonePairingError.expired }
            try await Task.sleep(for: pollInterval)
        }
    }
}

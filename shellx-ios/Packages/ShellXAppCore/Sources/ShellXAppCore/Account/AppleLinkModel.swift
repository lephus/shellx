import Foundation
import Observation
import ShellXLinkAccount
import ShellXLinkCore
import os

/// "Connect to Your Mac" after Sign in with Apple found no ShellX account (S1 §6.4): scan the Mac's pairing code,
/// confirm its name, press Allow on the Mac. Steps are `PairingModel.Step`, so the pairing screen shows them. The
/// link token stays in memory and is never logged.
@MainActor @Observable
public final class AppleLinkModel {
    public enum Outcome: Equatable, Sendable { case linked(AppleLinkApproval), cancelled, denied, expired }

    public private(set) var step: PairingModel.Step = .idle

    @ObservationIgnored private let linkToken: String
    @ObservationIgnored private let relay: any RelayAccountCalling
    @ObservationIgnored private let vault: AccountVault
    @ObservationIgnored private let finish: @MainActor (Outcome) async -> Void
    @ObservationIgnored private let log = Logger(subsystem: "com.shellx.app", category: "apple-link")
    @ObservationIgnored private var offerURI: String?
    @ObservationIgnored private var attempt: Task<AppleLinkApproval, any Error>?

    init(
        linkToken: String, relay: any RelayAccountCalling, vault: AccountVault,
        finish: @escaping @MainActor (Outcome) async -> Void
    ) {
        self.linkToken = linkToken
        self.relay = relay
        self.vault = vault
        self.finish = finish
    }

    /// As `PairingModel.begin(uri:)`: trims, lowercases the scheme, parses; never reaches the relay.
    public func begin(uri: String) {
        reset()
        let text = PairingModel.lowercasingScheme(uri.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            let offer = try PairingOffer(uri: text)
            offerURI = text
            step = .confirm(machineName: offer.machineName)
        } catch {
            let failure = PairingFailure(error)
            log.notice("apple_link_code_refused \(String(describing: failure), privacy: .public)")
            step = .failed(failure)
        }
    }

    /// `.confirm` → `.waitingForMac` → `relay.linkApple(...)` → `.paired` then `finish(.linked)`.
    public func confirm() async {
        guard case let .confirm(machineName) = step, let uri = offerURI else { return }
        step = .waitingForMac(machineName: machineName)
        let (relay, vault, linkToken) = (self.relay, self.vault, self.linkToken)
        let request = Task { () async throws -> AppleLinkApproval in
            let clientKey = try await vault.phoneKey().publicKey
            return try await relay.linkApple(offerURI: uri, linkToken: linkToken, clientKey: clientKey)
        }
        attempt = request
        let approval: AppleLinkApproval
        do {
            approval = try await request.value
        } catch {
            // Replaced or cancelled while the Mac answered: this attempt no longer speaks.
            guard attempt == request else { return }
            await handle(error)
            return
        }
        guard attempt == request else { return }
        attempt = nil
        offerURI = nil
        step = .paired(machineName: approval.machine.name)
        await finish(.linked(approval))
    }

    /// Back to `.idle`, dropping the attempt under way (there is nothing to withdraw on the relay).
    public func cancel() {
        reset()
        step = .idle
    }

    /// The Close button: `cancel()`, then `finish(.cancelled)`.
    public func close() {
        cancel()
        Task { await finish(.cancelled) }
    }

    private func handle(_ error: any Error) async {
        attempt = nil
        offerURI = nil
        switch error {
        case PhonePairingError.denied:
            await finish(.denied)
        case PhonePairingError.expired, RelayAPIError.http(status: 401, _):
            await finish(.expired)
        default:
            let failure = PairingFailure(error)
            log.notice("apple_link_failed \(String(describing: failure), privacy: .public)")
            step = .failed(failure)
        }
    }

    private func reset() {
        attempt?.cancel()
        attempt = nil
        offerURI = nil
    }
}

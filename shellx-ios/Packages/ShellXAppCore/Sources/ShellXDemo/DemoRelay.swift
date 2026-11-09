import Foundation
import ShellXAppCore
import ShellXLinkAccount
import ShellXLinkCore

/// The demo's relay: no network. Lists the demo Macs it was given or paired, pairs a demo Mac's code after
/// `approvalDelay`, and refuses every account call.
public actor DemoRelay: RelayAccountCalling {
    public static let refusal = RelayAPIError.http(status: 403, code: "demo")

    private var paired: [PairedMachine]
    private let pairableMachineIDs: Set<String>
    private let approvalDelay: Duration
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(
        paired: [PairedMachine], pairableMachineIDs: Set<String>, approvalDelay: Duration,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.paired = paired
        self.pairableMachineIDs = pairableMachineIDs
        self.approvalDelay = approvalDelay
        self.sleep = sleep
    }

    public func machines(token: String) async throws -> [PairedMachineListing] {
        paired.map {
            PairedMachineListing(
                grantID: "grant-\($0.machineID)", machineID: $0.machineID, name: $0.name, platform: "macos",
                online: true, linkSlot: $0.linkSlot, fingerprint: "demo")
        }
    }

    public func unpair(grantID: String, token: String) async throws {
        paired.removeAll { "grant-\($0.machineID)" == grantID }
    }

    public func pair(offerURI: String, clientKey: Data, token: String) async throws -> PairedMachine {
        let offer = try PairingOffer(uri: offerURI)
        guard pairableMachineIDs.contains(offer.machineID) else {
            throw RelayAPIError.http(status: 404, code: "machine_not_found")
        }
        if approvalDelay > .zero { try await sleep(approvalDelay) }
        let machine = PairedMachine(
            machineID: offer.machineID, name: offer.machineName, linkSlot: offer.linkSlot, hostKey: offer.hostKey)
        if !paired.contains(where: { $0.machineID == machine.machineID }) { paired.append(machine) }
        return machine
    }

    public func logout(token: String) async throws {}

    public func setPushToken(_ hexToken: String, topic: String, environment: APNsEnvironment, token: String)
        async throws
    {}

    public func login(email: String, password: String, deviceName: String, clientKey: Data) async throws
        -> AccountSession
    { throw Self.refusal }

    public func nonce() async throws -> String { throw Self.refusal }

    public func signInWithGoogle(idToken: String, nonce: String, deviceName: String, clientKey: Data) async throws
        -> AccountSignIn
    { throw Self.refusal }

    public func linkGoogle(idToken: String, nonce: String, token: String) async throws -> AccountSignIn {
        throw Self.refusal
    }

    public func signInWithApple(
        identityToken: String, authorizationCode: String, nonce: String, deviceName: String, clientKey: Data
    ) async throws -> AppleSignInResult { throw Self.refusal }

    public func linkApple(offerURI: String, linkToken: String, clientKey: Data) async throws -> AppleLinkApproval {
        throw Self.refusal
    }

    public func deleteAccount(idToken: String, nonce: String, token: String) async throws { throw Self.refusal }
}

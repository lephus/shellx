import Foundation
import ShellXAppCore
import ShellXLinkAccount
import ShellXLinkCore

/// A `RelayAccountCalling` that records every call and answers from presets.
///
/// Pairing works like the relay and `PhonePairing`: the offer is parsed (a bad one throws its
/// `PairingOfferError`), the "Mac" approves after `approvalDelay`, and the paired machine comes from
/// the offer, host key included, unless `setPairResult` gave another. A successful pairing adds the
/// Mac's grant to `machines(token:)`, and `unpair` removes it.
public actor FakeRelayAccount: RelayAccountCalling {
    public enum Call: Equatable, Sendable {
        case login(email: String, deviceName: String, clientKey: Data)
        case logout(token: String)
        case machines(token: String)
        case unpair(grantID: String, token: String)
        case pair(offerURI: String, clientKey: Data, token: String)
        case setPushToken(hexToken: String, topic: String, environment: APNsEnvironment, token: String)
    }

    public enum Function: Sendable { case login, logout, machines, unpair, pair, setPushToken }

    public private(set) var calls: [Call] = []
    private var loginResult: Result<AccountSession, Error> = .success(
        AccountSession(userID: "user", deviceID: "device", token: "token"))
    private var grants: [PairedMachineListing] = []
    private var errors: [Function: Error] = [:]
    /// nil: the machine described by the offer.
    private var pairedMachine: PairedMachine?
    private var approvalDelay: Duration = .zero
    private let sleep: @Sendable (Duration) async throws -> Void

    /// `sleep` waits out `approvalDelay` (the user pressing Allow on the Mac); a cancelled wait
    /// throws, like the real polling.
    public init(sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    public func setLogin(_ result: Result<AccountSession, Error>) { loginResult = result }
    public func setGrants(_ grants: [PairedMachineListing]) { self.grants = grants }
    /// Lists `machine` in `machines(token:)`, as after pairing.
    public func addGrant(for machine: PairedMachine) {
        guard !grants.contains(where: { $0.machineID == machine.machineID }) else { return }
        grants.append(
            PairedMachineListing(
                grantID: "grant-\(machine.machineID)", machineID: machine.machineID, name: machine.name,
                platform: "macos", online: true, linkSlot: machine.linkSlot, fingerprint: "fake"))
    }
    public func setError(_ error: Error?, for function: Function) { errors[function] = error }
    /// `pair` answers `machine` (nil: the offer's machine) after `approvalDelay`.
    public func setPairResult(_ machine: PairedMachine?, approvalDelay: Duration) {
        pairedMachine = machine
        self.approvalDelay = approvalDelay
    }
    /// How long `pair` waits before the Mac approves.
    public func setApprovalDelay(_ delay: Duration) { approvalDelay = delay }
    public func resetCalls() { calls = [] }

    public func login(email: String, password: String, deviceName: String, clientKey: Data) async throws
        -> AccountSession
    {
        calls.append(.login(email: email, deviceName: deviceName, clientKey: clientKey))
        if let error = errors[.login] { throw error }
        return try loginResult.get()
    }

    public func logout(token: String) async throws {
        calls.append(.logout(token: token))
        if let error = errors[.logout] { throw error }
    }

    public func machines(token: String) async throws -> [PairedMachineListing] {
        calls.append(.machines(token: token))
        if let error = errors[.machines] { throw error }
        return grants
    }

    public func unpair(grantID: String, token: String) async throws {
        calls.append(.unpair(grantID: grantID, token: token))
        if let error = errors[.unpair] { throw error }
        grants.removeAll { $0.grantID == grantID }
    }

    public func setPushToken(_ hexToken: String, topic: String, environment: APNsEnvironment, token: String) async throws {
        calls.append(.setPushToken(hexToken: hexToken, topic: topic, environment: environment, token: token))
        if let error = errors[.setPushToken] { throw error }
    }

    public func pair(offerURI: String, clientKey: Data, token: String) async throws -> PairedMachine {
        calls.append(.pair(offerURI: offerURI, clientKey: clientKey, token: token))
        if let error = errors[.pair] { throw error }
        let offer = try PairingOffer(uri: offerURI)
        if approvalDelay > .zero { try await sleep(approvalDelay) }
        let machine = pairedMachine ?? PairedMachine(
            machineID: offer.machineID, name: offer.machineName, linkSlot: offer.linkSlot, hostKey: offer.hostKey)
        addGrant(for: machine)
        return machine
    }
}

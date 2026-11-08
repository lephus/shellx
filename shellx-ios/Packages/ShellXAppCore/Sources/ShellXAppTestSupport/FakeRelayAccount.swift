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
        case nonce
        case signInWithGoogle(idToken: String, nonce: String, deviceName: String, clientKey: Data)
        case linkGoogle(idToken: String, nonce: String, token: String)
        case signInWithApple(identityToken: String, authorizationCode: String, nonce: String, deviceName: String, clientKey: Data)
        case linkApple(offerURI: String, linkToken: String, clientKey: Data)
        case deleteAccount(idToken: String, nonce: String, token: String)
        case logout(token: String)
        case machines(token: String)
        case unpair(grantID: String, token: String)
        case pair(offerURI: String, clientKey: Data, token: String)
        case setPushToken(hexToken: String, topic: String, environment: APNsEnvironment, token: String)
    }

    public enum Function: Sendable {
        case login, logout, machines, unpair, pair, setPushToken
        case nonce, signInWithGoogle, linkGoogle, signInWithApple, linkApple, deleteAccount
    }

    public private(set) var calls: [Call] = []
    private var loginResult: Result<AccountSession, Error> = .success(
        AccountSession(userID: "user", deviceID: "device", token: "token"))
    private var nonceValue = "nonce-1"
    private var googleSignIn: Result<AccountSignIn, Error> = .success(
        AccountSignIn(session: AccountSession(userID: "user", deviceID: "device", token: "token"), email: "user@example.com"))
    private var linkGoogleResult: Result<AccountSignIn, Error> = .success(
        AccountSignIn(session: AccountSession(userID: "user", deviceID: "device", token: "google-token"), email: "user@example.com"))
    private var appleSignIn: Result<AppleSignInResult, Error> = .success(
        .signedIn(AccountSignIn(session: AccountSession(userID: "user", deviceID: "device", token: "token"), email: "user@example.com")))
    private var appleLinkSignIn = AccountSignIn(
        session: AccountSession(userID: "user", deviceID: "device", token: "apple-token"), email: "user@example.com")
    private var hooks: [Function: @Sendable () async -> Void] = [:]
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
    public func setNonce(_ nonce: String) { nonceValue = nonce }
    public func setGoogleSignIn(_ result: Result<AccountSignIn, Error>) { googleSignIn = result }
    public func setLinkGoogle(_ result: Result<AccountSignIn, Error>) { linkGoogleResult = result }
    public func setAppleSignIn(_ result: Result<AppleSignInResult, Error>) { appleSignIn = result }
    public func setAppleLinkSignIn(_ signIn: AccountSignIn) { appleLinkSignIn = signIn }
    /// Runs inside `function`'s call, after it is recorded and before it answers (a 401 racing a request).
    public func setHook(_ hook: (@Sendable () async -> Void)?, for function: Function) { hooks[function] = hook }
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

    private func enter(_ call: Call, _ function: Function) async throws {
        calls.append(call)
        if let hook = hooks[function] { await hook() }
        if let error = errors[function] { throw error }
    }

    public func nonce() async throws -> String {
        try await enter(.nonce, .nonce)
        return nonceValue
    }

    public func signInWithGoogle(idToken: String, nonce: String, deviceName: String, clientKey: Data) async throws
        -> AccountSignIn
    {
        try await enter(
            .signInWithGoogle(idToken: idToken, nonce: nonce, deviceName: deviceName, clientKey: clientKey), .signInWithGoogle)
        return try googleSignIn.get()
    }

    public func linkGoogle(idToken: String, nonce: String, token: String) async throws -> AccountSignIn {
        try await enter(.linkGoogle(idToken: idToken, nonce: nonce, token: token), .linkGoogle)
        return try linkGoogleResult.get()
    }

    public func signInWithApple(
        identityToken: String, authorizationCode: String, nonce: String, deviceName: String, clientKey: Data
    ) async throws -> AppleSignInResult {
        try await enter(
            .signInWithApple(
                identityToken: identityToken, authorizationCode: authorizationCode, nonce: nonce, deviceName: deviceName,
                clientKey: clientKey), .signInWithApple)
        return try appleSignIn.get()
    }

    /// Like `pair`: parses the offer, waits `approvalDelay`, adds the Mac's grant.
    public func linkApple(offerURI: String, linkToken: String, clientKey: Data) async throws -> AppleLinkApproval {
        try await enter(.linkApple(offerURI: offerURI, linkToken: linkToken, clientKey: clientKey), .linkApple)
        let offer = try PairingOffer(uri: offerURI)
        if approvalDelay > .zero { try await sleep(approvalDelay) }
        let machine = PairedMachine(
            machineID: offer.machineID, name: offer.machineName, linkSlot: offer.linkSlot, hostKey: offer.hostKey)
        addGrant(for: machine)
        return AppleLinkApproval(signIn: appleLinkSignIn, machine: machine)
    }

    public func deleteAccount(idToken: String, nonce: String, token: String) async throws {
        try await enter(.deleteAccount(idToken: idToken, nonce: nonce, token: token), .deleteAccount)
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

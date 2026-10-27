import Foundation
import ShellXAppCore
import ShellXLinkAccount

/// A `RelayAccountCalling` that records every call and answers from presets.
public actor FakeRelayAccount: RelayAccountCalling {
    public enum Call: Equatable, Sendable {
        case login(email: String, deviceName: String, clientKey: Data)
        case logout(token: String)
        case machines(token: String)
        case unpair(grantID: String, token: String)
        case pair(offerURI: String, clientKey: Data, token: String)
    }

    public enum Function: Sendable { case login, logout, machines, unpair, pair }

    public private(set) var calls: [Call] = []
    private var loginResult: Result<AccountSession, Error> = .success(
        AccountSession(userID: "user", deviceID: "device", token: "token"))
    private var grants: [PairedMachineListing] = []
    private var errors: [Function: Error] = [:]
    private var pairedMachine = PairedMachine(
        machineID: "machine", name: "Mac", linkSlot: "slot", hostKey: Data(repeating: 0, count: 32))
    private var approvalDelay: Duration = .zero

    public init() {}

    public func setLogin(_ result: Result<AccountSession, Error>) { loginResult = result }
    public func setGrants(_ grants: [PairedMachineListing]) { self.grants = grants }
    public func setError(_ error: Error?, for function: Function) { errors[function] = error }
    public func setPairResult(_ machine: PairedMachine, approvalDelay: Duration) {
        pairedMachine = machine
        self.approvalDelay = approvalDelay
    }
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
    }

    public func pair(offerURI: String, clientKey: Data, token: String) async throws -> PairedMachine {
        calls.append(.pair(offerURI: offerURI, clientKey: clientKey, token: token))
        if let error = errors[.pair] { throw error }
        if approvalDelay > .zero { try await Task.sleep(for: approvalDelay) }
        return pairedMachine
    }
}

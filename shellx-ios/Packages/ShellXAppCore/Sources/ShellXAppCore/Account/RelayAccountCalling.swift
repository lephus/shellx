import Foundation
import ShellXLinkAccount

/// The relay calls the account flow needs. `RelayAPI` is the real one; tests use a fake.
public protocol RelayAccountCalling: Sendable {
    func login(email: String, password: String, deviceName: String, clientKey: Data) async throws -> AccountSession
    func logout(token: String) async throws
    func machines(token: String) async throws -> [PairedMachineListing]
    func unpair(grantID: String, token: String) async throws
    func pair(offerURI: String, clientKey: Data, token: String) async throws -> PairedMachine
}

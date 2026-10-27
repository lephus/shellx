import Foundation
import ShellXLinkAccount
import ShellXLinkSession

/// Connects through the ShellX relay with the account's token and the phone's Link key, both read
/// from the vault on every attempt, so a new sign-in is used at once.
public struct RelayMachineConnector: MachineLinkConnecting {
    private let api: RelayAPI
    private let vault: AccountVault
    private let clientVersion: String
    private let deviceName: String

    public init(api: RelayAPI, vault: AccountVault, clientVersion: String, deviceName: String) {
        self.api = api
        self.vault = vault
        self.clientVersion = clientVersion
        self.deviceName = deviceName
    }

    /// Without a stored session it throws `RelayAPIError.http(status: 401, ...)`, the same as a
    /// token the relay refuses.
    public func connect(_ machine: PairedMachine) async throws -> LinkClient {
        guard let token = try await vault.session()?.token else {
            throw RelayAPIError.http(status: 401, code: "signed_out")
        }
        let key = try await vault.phoneKey()
        return try await LinkConnector.connect(
            machine: machine, key: key, api: api, token: token, clientVersion: clientVersion, deviceName: deviceName)
    }
}

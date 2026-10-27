import Foundation
import ShellXLinkCore
import ShellXLinkRelay
import ShellXLinkSession

public enum LinkConnector {
    /// Connects to a paired machine: mints a connect ticket (its slot must be the pinned one),
    /// opens a relay circuit (retrying while the Mac is between registrations), and runs the Noise
    /// handshake trusting only the host key pinned at pairing.
    public static func connect(
        machine: PairedMachine,
        key: NoiseStaticKey,
        api: RelayAPI,
        token: String,
        clientVersion: String,
        deviceName: String
    ) async throws -> LinkClient {
        let minted = try await api.mintConnectTicket(
            machineID: machine.machineID, expectedSlot: machine.linkSlot, token: token)
        let circuit = try await RelayClientConnector.connect(
            relayURL: minted.relayURL, slot: machine.linkSlot, ticket: minted.ticket)
        return try await LinkClient.connect(
            circuit, key: key, hostKey: machine.hostKey, clientVersion: clientVersion, deviceName: deviceName)
    }
}

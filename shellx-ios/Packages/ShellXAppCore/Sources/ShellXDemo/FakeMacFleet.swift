import Foundation
import ShellXAppCore
import ShellXLinkAccount
import ShellXLinkCore
import ShellXLinkSession

/// Connects each paired machine to the `FakeMac` with its `machineID`. A machine that is not in the
/// fleet answers as the relay does for a removed Mac (`machine_not_found`).
public struct FakeMacFleet: MachineLinkConnecting {
    private let connectors: [String: any MachineLinkConnecting]

    public init(_ macs: [FakeMac], phoneKey: @escaping @Sendable () async throws -> NoiseStaticKey) {
        var connectors: [String: any MachineLinkConnecting] = [:]
        for mac in macs { connectors[mac.machine.machineID] = mac.connector(phoneKey: phoneKey) }
        self.connectors = connectors
    }

    public func connect(_ machine: PairedMachine) async throws -> LinkClient {
        guard let connector = connectors[machine.machineID] else {
            throw RelayAPIError.http(status: 404, code: "machine_not_found")
        }
        return try await connector.connect(machine)
    }
}

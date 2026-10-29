import Foundation
import ShellXLinkAccount
import ShellXLinkSession

/// Opens one Link session to a paired Mac. `RelayMachineConnector` is the real one; tests use `FakeMac`.
public protocol MachineLinkConnecting: Sendable {
    func connect(_ machine: PairedMachine) async throws -> LinkClient
}

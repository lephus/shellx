import Foundation
import ShellXLinkCore

/// Names one pending request across all Macs.
public struct PendingKey: Hashable, Sendable {
    public var machineID: String
    public var requestId: String

    public init(machineID: String, requestId: String) {
        self.machineID = machineID
        self.requestId = requestId
    }
}

/// A pending request with the Mac it came from.
public struct MachinePendingItem: Identifiable, Equatable, Sendable {
    public var machineID: String
    public var machineName: String
    public var item: PendingItem
    /// False while the Mac's session is not live and synced: the card shows, its buttons do not act.
    public var actionable: Bool

    public init(machineID: String, machineName: String, item: PendingItem, actionable: Bool) {
        self.machineID = machineID
        self.machineName = machineName
        self.item = item
        self.actionable = actionable
    }

    public var id: PendingKey { PendingKey(machineID: machineID, requestId: item.requestId) }
}

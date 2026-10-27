import Foundation

/// What about the device's network path decides whether live Link sessions may have died: its
/// status, the primary interface (the one new connections use) and the gateways. Interfaces behind
/// the primary one do not count: cellular coming up while Wi-Fi carries the sessions changes nothing.
public struct NetworkPath: Equatable, Sendable {
    public var status: String
    public var primaryInterface: String?
    /// Sorted, so their order does not count.
    public var gateways: [String]

    /// `interfaces` in order of preference, as `NWPath.availableInterfaces` lists them.
    public init(status: String, interfaces: [String], gateways: [String]) {
        self.status = status
        primaryInterface = interfaces.first
        self.gateways = gateways.sorted()
    }
}

import Foundation

/// D9: the daemon approves only the invitation id this machine issued for an approved pairing,
/// once, within 300 s. Everything else is denied.
public struct ApprovalGate: Sendable {
    public enum Decision: Equatable, Sendable { case approve(pairingID: String), deny }
    private var issued: [String: (pairingID: String, at: Date)] = [:]
    private static let lifetime: TimeInterval = 300

    public init() {}

    public mutating func expect(invitationID: String, pairingID: String, now: Date) {
        issued[invitationID] = (pairingID, now)
    }

    public mutating func decide(pendingInvitationID: String, now: Date) -> Decision {
        guard let entry = issued.removeValue(forKey: pendingInvitationID),
              now.timeIntervalSince(entry.at) <= Self.lifetime else { return .deny }
        return .approve(pairingID: entry.pairingID)
    }
}

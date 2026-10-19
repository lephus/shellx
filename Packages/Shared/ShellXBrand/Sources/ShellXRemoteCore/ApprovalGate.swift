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

    /// Decides and consumes at once (the invitation can never be approved again, even if approving fails).
    public mutating func decide(pendingInvitationID: String, now: Date) -> Decision {
        let decision = check(pendingInvitationID: pendingInvitationID, now: now)
        issued[pendingInvitationID] = nil
        return decision
    }

    /// Decides without consuming: an approval only uses the invitation up once `consume` confirms the
    /// daemon admitted it, so a failed `enroll approve` is retried (still within the 300 s) instead of
    /// the next poll denying it. Unknown or expired invitations are denied.
    public func check(pendingInvitationID: String, now: Date) -> Decision {
        guard let entry = issued[pendingInvitationID], now.timeIntervalSince(entry.at) <= Self.lifetime else { return .deny }
        return .approve(pairingID: entry.pairingID)
    }

    /// The daemon admitted the invitation: it is never approved again.
    public mutating func consume(invitationID: String) {
        issued[invitationID] = nil
    }

    /// Forgets an invitation that will never be handed out (its pairing was not approved after all).
    public mutating func revoke(invitationID: String) {
        issued[invitationID] = nil
    }

    /// Drops invitations older than their 300 s lifetime.
    public mutating func pruneExpired(now: Date) {
        issued = issued.filter { now.timeIntervalSince($0.value.at) <= Self.lifetime }
    }

    /// True when no invitation is expected (the daemon's pending list need not be polled).
    public var isEmpty: Bool { issued.isEmpty }
}

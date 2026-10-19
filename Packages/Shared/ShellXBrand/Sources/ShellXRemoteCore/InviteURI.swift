import Foundation

public struct InviteSummary: Equatable, Sendable {
    public let invitationID: String
    public let relayRoute: String
    public let relaySlot: String
    public let daemonFingerprint: String

    public init(invitationID: String, relayRoute: String, relaySlot: String, daemonFingerprint: String) {
        self.invitationID = invitationID; self.relayRoute = relayRoute
        self.relaySlot = relaySlot; self.daemonFingerprint = daemonFingerprint
    }
}

public enum InviteError: Error, Equatable, Sendable { case malformed }

/// Reads the non-secret part of a cmux `EnrollmentInvitation` the way `shellx-core/src/pairing.rs`
/// `parse_invite` does. `secret` and `relay_access[].ticket` are not declared, so they are never decoded.
public enum InviteURI {
    private static let prefix = "cmux://enroll/"

    private struct View: Decodable {
        struct Access: Decodable { let route: String; let slot: String }
        let version: Int
        let id: String
        let daemon_public_key: String
        let daemon_fingerprint: String
        let relay_access: [Access]?
    }

    public static func summary(of uri: String) throws -> InviteSummary {
        guard uri.hasPrefix(prefix), let json = base64URLDecode(String(uri.dropFirst(prefix.count))),
              let view = try? JSONDecoder().decode(View.self, from: json), view.version == 1,
              let key = base64URLDecode(view.daemon_public_key), key.count == 32,
              base64URLEncode(Data(SHA256Pure.digest(key).prefix(16))) == view.daemon_fingerprint,
              let first = view.relay_access?.first,
              let scheme = first.route.components(separatedBy: "://").first, first.route.contains("://"),
              ["relay+ws", "relay+wss", "relay+https", "relay+do"].contains(scheme),
              !first.slot.isEmpty, first.slot.utf8.count <= 256,
              !first.slot.utf8.contains(where: { $0 <= 0x20 || $0 == 0x7f })
        else { throw InviteError.malformed }
        return InviteSummary(invitationID: view.id, relayRoute: first.route, relaySlot: first.slot,
                             daemonFingerprint: view.daemon_fingerprint)
    }

    static func base64URLDecode(_ s: String) -> Data? {
        guard s.utf8.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5a) || ($0 >= 0x61 && $0 <= 0x7a) || $0 == 0x2d || $0 == 0x5f }) else { return nil }
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        if b.count % 4 == 1 { return nil }
        b += String(repeating: "=", count: (4 - b.count % 4) % 4)
        return Data(base64Encoded: b)
    }

    static func base64URLEncode(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

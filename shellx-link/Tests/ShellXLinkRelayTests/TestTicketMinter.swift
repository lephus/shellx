import CryptoKit
import Foundation
import ShellXLinkRelay

/// Test-only stand-in for the ShellX API that mints relay tickets for a slot.
///
/// Format: `v2.<base64url(claims JSON)>.<base64url(HMAC-SHA256(signing payload))>`, where the
/// signing payload is the newline-joined canonical claim list the relay recomputes on verify.
struct TestTicketMinter: Sendable {
    enum Permission: String, Sendable {
        case register
        case connect

        var role: String { self == .register ? "daemon" : "client" }
    }

    static let issuer = "shellx-relay"
    static let lifetimeSeconds: Int64 = 120

    let secret: Data

    init(secret: String) {
        self.secret = Data(secret.utf8)
    }

    func mint(_ permission: Permission, slot: String, now: Date = Date()) -> RelayTicket {
        let issued = Int64(now.timeIntervalSince1970)
        let expires = issued + Self.lifetimeSeconds
        // Circuit, lane and generation stay null, as the ShellX API mints them.
        let claims: [String: Any] = [
            "version": 2,
            "issuer": Self.issuer,
            "permission": permission.rawValue,
            "role": permission.role,
            "slot": slot,
            "circuit": NSNull(),
            "lane": NSNull(),
            "generation": NSNull(),
            "issued_at_unix": issued,
            "expires_at_unix": expires,
        ]
        let body = try! JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys])
        let payload = [
            "cmux-relay-ticket-v2", "2", Self.issuer, permission.rawValue, permission.role, slot,
            "", "", "", String(issued), String(expires),
        ].joined(separator: "\n")
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(payload.utf8),
            using: SymmetricKey(data: secret)
        )
        let ticket = "v2.\(Self.base64URL(body)).\(Self.base64URL(Data(mac)))"
        return RelayTicket(ticket: ticket, expiresAtUnix: expires)
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

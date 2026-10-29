import Foundation

/// A phone of this account asking this Mac for access (`phones.pending`).
///
/// Its descriptions never print the key or the proof.
public struct PhonePairingRequest: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: String
    public let deviceName: String
    public let platform: String
    /// The phone's 32-byte public key.
    public let clientKey: Data
    /// The phone's 32-byte pairing proof.
    public let proof: Data
    public let createdAt: Date

    public init(id: String, deviceName: String, platform: String, clientKey: Data, proof: Data, createdAt: Date) {
        self.id = id; self.deviceName = deviceName; self.platform = platform
        self.clientKey = clientKey; self.proof = proof; self.createdAt = createdAt
    }

    public var description: String { "PhonePairingRequest(id: \(id), device: \(deviceName), platform: \(platform), <redacted>)" }
    public var debugDescription: String { description }
}

/// A phone that holds a grant on this Mac (`phones.grants`).
public struct PairedPhone: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let grantID: String
    public let deviceID: String
    public let deviceName: String
    public let platform: String
    /// The phone's 32-byte public key.
    public let clientKey: Data
    public let createdAt: Date
    public let lastSeen: Date?

    public init(grantID: String, deviceID: String, deviceName: String, platform: String, clientKey: Data, createdAt: Date, lastSeen: Date?) {
        self.grantID = grantID; self.deviceID = deviceID; self.deviceName = deviceName; self.platform = platform
        self.clientKey = clientKey; self.createdAt = createdAt; self.lastSeen = lastSeen
    }

    public var description: String { "PairedPhone(grant: \(grantID), device: \(deviceName), platform: \(platform), <redacted>)" }
    public var debugDescription: String { description }
}

/// Typed phone pairing methods. Every call blocks on the FFI: call from a background queue, never the main thread.
extension ShellXCoreClient {
    private static let phoneKeyLength = 32

    private static func badResponse(_ what: String) -> ShellXCoreError {
        ShellXCoreError(code: "bad_response", message: "core reply has an unusable \(what)")
    }

    /// Standard (or URL-safe), padded or not, base64 of exactly 32 bytes.
    private static func phoneBytes(_ b64: String, what: String) throws -> Data {
        var s = b64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        guard let data = Data(base64Encoded: s), data.count == phoneKeyLength else { throw badResponse(what) }
        return data
    }

    /// Requests from phones of this account waiting for this Mac's decision, newest first.
    public func pendingPhonePairings() throws -> [PhonePairingRequest] {
        struct Item: Decodable {
            let pairing_id: String, device_name: String, platform: String
            let client_key_b64: String, proof_b64: String, created_at_unix: Double
        }
        struct Reply: Decodable { let pairings: [Item] }
        return try call("phones.pending", as: Reply.self).pairings.map {
            PhonePairingRequest(
                id: $0.pairing_id, deviceName: $0.device_name, platform: $0.platform,
                clientKey: try Self.phoneBytes($0.client_key_b64, what: "client key"),
                proof: try Self.phoneBytes($0.proof_b64, what: "proof"),
                createdAt: Date(timeIntervalSince1970: $0.created_at_unix))
        }
    }

    /// Grants the phone link access to this Mac. Throws the server's code (`pairing_expired`, `pairing_not_pending`, ...).
    public func approvePhonePairing(_ id: String) throws {
        struct Empty: Decodable {}
        _ = try call("phones.approve", ["pairing_id": .string(id)], as: Empty.self)
    }

    /// Refuses the request. Idempotent on the server.
    public func denyPhonePairing(_ id: String) throws {
        struct Empty: Decodable {}
        _ = try call("phones.deny", ["pairing_id": .string(id)], as: Empty.self)
    }

    /// Phones that currently hold a grant on this Mac.
    public func pairedPhones() throws -> [PairedPhone] {
        struct Item: Decodable {
            let grant_id: String, device_id: String, device_name: String, platform: String
            let client_key_b64: String, created_at_unix: Double, last_seen_unix: Double?
        }
        struct Reply: Decodable { let grants: [Item] }
        return try call("phones.grants", as: Reply.self).grants.map {
            PairedPhone(
                grantID: $0.grant_id, deviceID: $0.device_id, deviceName: $0.device_name, platform: $0.platform,
                clientKey: try Self.phoneBytes($0.client_key_b64, what: "client key"),
                createdAt: Date(timeIntervalSince1970: $0.created_at_unix),
                lastSeen: $0.last_seen_unix.map { Date(timeIntervalSince1970: $0) })
        }
    }

    /// Removes a phone's access. An unknown grant throws code `not_found`.
    public func revokePhone(grantID: String) throws {
        struct Empty: Decodable {}
        _ = try call("phones.revoke", ["grant_id": .string(grantID)], as: Empty.self)
    }
}

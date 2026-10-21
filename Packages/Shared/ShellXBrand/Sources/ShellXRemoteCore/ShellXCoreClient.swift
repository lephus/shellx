import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), null, array([JSONValue]), object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

public protocol ShellXCoreCalling: Sendable { func call(method: String, json: Data) throws -> Data }

public struct ShellXCoreError: Error, Equatable, Sendable {
    public let code: String
    public let message: String
    public init(code: String, message: String) { self.code = code; self.message = message }
}

/// Typed wrapper over the K3 envelope `{"ok": ...}` / `{"error": {"code", "message"}}`.
public struct ShellXCoreClient: Sendable {
    private let core: any ShellXCoreCalling

    public init(_ core: any ShellXCoreCalling) { self.core = core }

    private struct Envelope<R: Decodable>: Decodable {
        struct Failure: Decodable { let code: String; let message: String }
        let ok: R?
        let error: Failure?
    }

    public func call<R: Decodable>(_ method: String, _ params: [String: JSONValue] = [:], as: R.Type) throws -> R {
        let reply = try core.call(method: method, json: try JSONEncoder().encode(params))
        let envelope: Envelope<R>
        do { envelope = try JSONDecoder().decode(Envelope<R>.self, from: reply) }
        catch { throw ShellXCoreError(code: "bad_response", message: "unreadable core reply") }
        if let failure = envelope.error { throw ShellXCoreError(code: failure.code, message: failure.message) }
        if let ok = envelope.ok { return ok }
        if let null = try? JSONDecoder().decode(R.self, from: Data("null".utf8)) { return null }
        throw ShellXCoreError(code: "bad_response", message: "core reply has no result")
    }
}

/// One row of `shares.list`.
public struct ShellXShareSummary: Decodable, Equatable, Sendable {
    public let id: String
    public let permission: SharePermission
    public let lifetime: ShareLifetime
    public let expiresAtUnix: Double
    public let revoked: Bool

    enum CodingKeys: String, CodingKey { case id, permission, lifetime, revoked; case expiresAtUnix = "expires_at_unix" }
}

/// `shares.create` reply.
public struct ShellXCreatedShare: Decodable, Equatable, Sendable {
    public let id: String
    public let slot: String
    public let expiresAtUnix: Double
    public let claimUntilUnix: Double?

    enum CodingKeys: String, CodingKey { case id, slot; case expiresAtUnix = "expires_at_unix"; case claimUntilUnix = "claim_until_unix" }
}

/// Typed share methods. Every call blocks on the FFI: call from a background queue, never the main thread.
extension ShellXCoreClient {
    /// API share ids are 8 characters; the display dash (`xxxx-xxxx`) is stripped before any call.
    static func apiShareID(_ id: String) -> String { id.replacingOccurrences(of: "-", with: "") }

    /// `id` is proposed by the caller (see `ShareID.random()`); `access` is the HKDF access token derived with
    /// that id as salt (base64url); the link secret never reaches the core. A taken id throws code `share_id_taken`:
    /// the core does not retry, because `access` depends on the id (see `createShareRetryingID`).
    public func createShare(id: String, permission: SharePermission, lifetime: ShareLifetime, oneTime: Bool, access: String) throws -> ShellXCreatedShare {
        try call("shares.create", ["id": .string(Self.apiShareID(id)), "permission": .string(permission.rawValue),
                                   "lifetime": .string(lifetime.rawValue), "one_time": .bool(oneTime), "access": .string(access)],
                 as: ShellXCreatedShare.self)
    }

    /// Creates a share with a fresh client id and derives `access` from the one `secret` for that id. On
    /// `share_id_taken` it draws a new id and derives `access` again, up to `maxAttempts` attempts in all (default 3);
    /// any other error, or the last `share_id_taken`, is thrown. The secret is never regenerated.
    public func createShareRetryingID(
        permission: SharePermission, lifetime: ShareLifetime, oneTime: Bool,
        secret: ShareSecret = .random(), maxAttempts: Int = 3, makeID: () -> String = ShareID.random
    ) throws -> (share: ShellXCreatedShare, secret: ShareSecret) {
        var attempt = 0
        while true {
            attempt += 1
            let id = makeID()
            do {
                let share = try createShare(id: id, permission: permission, lifetime: lifetime, oneTime: oneTime,
                                            access: secret.keys(shareID: id).access)
                return (share, secret)
            } catch let error as ShellXCoreError where error.code == "share_id_taken" && attempt < maxAttempts {
                continue
            }
        }
    }

    public func listShares() throws -> [ShellXShareSummary] {
        struct Reply: Decodable { let shares: [ShellXShareSummary] }
        return try call("shares.list", as: Reply.self).shares
    }

    /// Idempotent.
    public func revokeShare(id: String) throws {
        struct Empty: Decodable {}
        _ = try call("shares.revoke", ["id": .string(Self.apiShareID(id))], as: Empty.self)
    }

    public func hostShareTicket(id: String) throws -> (ticket: String, relayURL: URL, expiresAt: Date) {
        struct Reply: Decodable { let ticket: String; let expires_at_unix: Double; let relay_url: String }
        let r = try call("shares.host_ticket", ["id": .string(Self.apiShareID(id))], as: Reply.self)
        guard !r.ticket.isEmpty, let url = URL(string: r.relay_url), url.scheme != nil else {
            throw ShellXCoreError(code: "bad_response", message: "core reply has no usable ticket or relay_url")
        }
        return (r.ticket, url, Date(timeIntervalSince1970: r.expires_at_unix))
    }
}

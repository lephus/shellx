import Foundation
import ShellXLinkCore
import ShellXLinkRelay

/// Errors from the ShellX relay HTTP API.
public enum RelayAPIError: Error, Equatable, Sendable {
    /// The API answered with a non-2xx status; `code` is its `error.code` (`"unknown"` when the body has none).
    case http(status: Int, code: String)
    /// The answer was not what the API documents, or contradicts what the phone already trusts.
    case badResponse
    /// A minted ticket is for another slot than the machine's link slot.
    case slotMismatch
    /// A minted ticket does not carry the `connect` permission.
    case notConnectTicket
}

/// A signed-in phone. The token is a bearer secret: descriptions and the mirror leave it out.
public struct AccountSession: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public var userID: String
    public var deviceID: String
    public var token: String

    public init(userID: String, deviceID: String, token: String) {
        self.userID = userID
        self.deviceID = deviceID
        self.token = token
    }

    public var description: String { "AccountSession(user: \(userID), device: \(deviceID), <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self, children: ["userID": userID, "deviceID": deviceID, "token": "<redacted>"],
            displayStyle: .struct)
    }
}

/// How a phone pairing request stands.
public enum PhonePairingStatus: Equatable, Sendable {
    case pending
    case approved(machineID: String, name: String, linkSlot: String)
    case denied
    case expired
}

/// A machine this phone may connect to, as the relay lists it.
public struct PairedMachineListing: Equatable, Sendable {
    public var grantID: String
    public var machineID: String
    public var name: String
    public var platform: String
    public var online: Bool
    public var linkSlot: String
    public var fingerprint: String

    public init(
        grantID: String, machineID: String, name: String, platform: String, online: Bool,
        linkSlot: String, fingerprint: String
    ) {
        self.grantID = grantID
        self.machineID = machineID
        self.name = name
        self.platform = platform
        self.online = online
        self.linkSlot = linkSlot
        self.fingerprint = fingerprint
    }
}

/// The phone's side of the ShellX relay HTTP API (`/v1/auth/login`, `/v2/phone-pairings`,
/// `/v2/phone-grants`, `/v2/relay/tickets`). `*_b64` request fields are standard base64.
public struct RelayAPI: Sendable {
    public let baseURL: URL
    private let session: URLSession
    private let clientVersion: String

    /// Throws `RelayError.insecureTransport` unless `baseURL` is `https` or a loopback `http` URL.
    public init(baseURL: URL, session: URLSession = .shared, clientVersion: String) throws {
        try RelayTransportPolicy.requireHTTPS(baseURL)
        self.baseURL = baseURL
        self.session = session
        self.clientVersion = clientVersion
    }

    public func login(email: String, password: String, deviceName: String, clientKey: Data) async throws
        -> AccountSession
    {
        let device: [String: String] = [
            "kind": "mobile", "platform": "ios", "name": deviceName, "public_key": Self.base64URL(clientKey),
        ]
        let reply: LoginReply = try await send(
            "POST", "/v1/auth/login", token: nil,
            body: ["email": email, "password": password, "device": device])
        return AccountSession(userID: reply.userID, deviceID: reply.deviceID, token: reply.token)
    }

    /// Asks the machine in `offer` to approve this phone; returns the pairing id to poll.
    public func requestPairing(offer: PairingOffer, clientKey: Data, token: String) async throws -> String {
        let reply: PairingCreated = try await send(
            "POST", "/v2/phone-pairings", token: token,
            body: [
                "machine_id": offer.machineID,
                "client_key_b64": clientKey.base64EncodedString(),
                "proof_b64": offer.proof(clientKey: clientKey).base64EncodedString(),
            ])
        guard Self.isSafeSegment(reply.pairingID) else { throw RelayAPIError.badResponse }
        return reply.pairingID
    }

    /// Withdraws a pending pairing request (`POST /v2/phone-pairings/:id/deny`, which the sending phone may call).
    public func cancelPairing(id: String, token: String) async throws {
        guard Self.isSafeSegment(id) else { throw RelayAPIError.badResponse }
        let _: Empty = try await send("POST", "/v2/phone-pairings/\(id)/deny", token: token, body: nil)
    }

    public func pairingStatus(id: String, token: String) async throws -> PhonePairingStatus {
        guard Self.isSafeSegment(id) else { throw RelayAPIError.badResponse }
        let reply: PairingStatusReply = try await send("GET", "/v2/phone-pairings/\(id)", token: token, body: nil)
        switch reply.status {
        case "pending": return .pending
        case "denied": return .denied
        case "expired": return .expired
        case "approved":
            guard let machine = reply.machine else { throw RelayAPIError.badResponse }
            return .approved(machineID: machine.machineID, name: machine.name, linkSlot: machine.linkSlot)
        default: throw RelayAPIError.badResponse
        }
    }

    /// The machines this phone was approved for (`GET /v2/phone-grants`).
    public func machines(token: String) async throws -> [PairedMachineListing] {
        let reply: GrantsReply = try await send("GET", "/v2/phone-grants", token: token, body: nil)
        return reply.grants.map {
            PairedMachineListing(
                grantID: $0.grantID, machineID: $0.machineID, name: $0.name, platform: $0.platform,
                online: $0.online, linkSlot: $0.linkSlot, fingerprint: $0.fingerprint)
        }
    }

    /// Mints a link-lane connect ticket for `machineID`. The ticket must be for `expectedSlot`
    /// (the slot pinned at pairing) and carry the `connect` permission.
    public func mintConnectTicket(machineID: String, expectedSlot: String, token: String) async throws
        -> (ticket: RelayTicket, relayURL: URL)
    {
        let reply: TicketReply = try await send(
            "POST", "/v2/relay/tickets", token: token,
            body: ["permission": "connect", "lane": "link", "target_machine_id": machineID])
        let ticket = RelayTicket(ticket: reply.ticket, expiresAtUnix: reply.expiresAtUnix)
        guard let claims = ticket.claims, let relayURL = URL(string: reply.relayURL), relayURL.host != nil
        else { throw RelayAPIError.badResponse }
        guard claims.permission == "connect" else { throw RelayAPIError.notConnectTicket }
        guard claims.slot == expectedSlot else { throw RelayAPIError.slotMismatch }
        return (ticket, relayURL)
    }

    /// Removes this phone's access to a machine.
    public func unpair(grantID: String, token: String) async throws {
        guard Self.isSafeSegment(grantID) else { throw RelayAPIError.badResponse }
        let _: Empty = try await send("DELETE", "/v2/phone-grants/\(grantID)", token: token, body: nil)
    }

    // MARK: - Transport

    func send<Reply: Decodable>(
        _ method: String, _ path: String, token: String?, body: [String: Any]?
    ) async throws -> Reply {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: 15)
        request.httpMethod = method
        request.setValue(clientVersion, forHTTPHeaderField: "X-ShellX-Version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        // A redirect could carry the bearer token or the login body to another host: never follow one.
        let (data, response) = try await session.data(for: request, delegate: RefuseRedirects())
        guard let http = response as? HTTPURLResponse else { throw RelayAPIError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let code = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error.code ?? "unknown"
            throw RelayAPIError.http(status: http.statusCode, code: code)
        }
        if Reply.self == Empty.self { return Empty() as! Reply }
        do {
            return try JSONDecoder().decode(Reply.self, from: data)
        } catch {
            throw RelayAPIError.badResponse
        }
    }

    /// Ids go into URL paths; accept only what the relay issues (UUIDs and the like).
    private static func isSafeSegment(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 64
            && id.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 | 0x20 >= 0x61 && $0 | 0x20 <= 0x7a) || $0 == 0x2d || $0 == 0x5f }
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Answers every HTTP redirect with "do not follow", so the 3xx response is the result.
private final class RefuseRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

// MARK: - Wire types

struct Empty: Decodable {}

private struct ErrorEnvelope: Decodable {
    struct Body: Decodable { var code: String }
    var error: Body
}

private struct LoginReply: Decodable {
    var userID: String
    var deviceID: String
    var token: String
    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case deviceID = "device_id"
        case token
    }
}

private struct PairingCreated: Decodable {
    var pairingID: String
    private enum CodingKeys: String, CodingKey { case pairingID = "pairing_id" }
}

private struct PairingStatusReply: Decodable {
    struct Machine: Decodable {
        var machineID: String
        var name: String
        var linkSlot: String
        private enum CodingKeys: String, CodingKey {
            case machineID = "machine_id"
            case name
            case linkSlot = "link_slot"
        }
    }
    var status: String
    var machine: Machine?
}

private struct GrantsReply: Decodable {
    struct Grant: Decodable {
        var grantID: String
        var machineID: String
        var name: String
        var platform: String
        var online: Bool
        var linkSlot: String
        var fingerprint: String
        private enum CodingKeys: String, CodingKey {
            case grantID = "grant_id"
            case machineID = "machine_id"
            case name, platform, online
            case linkSlot = "link_slot"
            case fingerprint
        }
    }
    var grants: [Grant]
}

private struct TicketReply: Decodable {
    var ticket: String
    var expiresAtUnix: Int64
    var relayURL: String
    private enum CodingKeys: String, CodingKey {
        case ticket
        case expiresAtUnix = "expires_at_unix"
        case relayURL = "relay_url"
    }
}

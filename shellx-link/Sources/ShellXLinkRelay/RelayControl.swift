import Foundation

/// A relay ticket minted for one slot by the ShellX API: a register ticket for the host, a
/// connect ticket for a client. The relay checks the signature, scope and expiry.
///
/// The ticket is a bearer secret: its descriptions and its mirror (what `dump` prints) leave it out.
public struct RelayTicket: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var ticket: String
    public var expiresAtUnix: Int64

    public init(ticket: String, expiresAtUnix: Int64) {
        self.ticket = ticket
        self.expiresAtUnix = expiresAtUnix
    }

    public var description: String { "RelayTicket(expires: \(expiresAtUnix), <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["ticket": "<redacted>", "expiresAtUnix": expiresAtUnix], displayStyle: .struct)
    }
}

/// Fetches a fresh ticket. The host calls it once per registration attempt.
public typealias TicketProvider = @Sendable () async throws -> RelayTicket

/// Errors raised by the relay client.
///
/// Transport failures before a circuit is ready (connection refused, TLS, timeouts) surface as
/// the underlying `URLError`.
public enum RelayError: Error, Equatable {
    /// The circuit ended: the peer or this side closed it, or the socket dropped.
    case closed
    /// The relay refused an operation with an `error` control message.
    case server(code: String, retryable: Bool)
    /// The relay sent something this client does not expect.
    case protocolViolation(String)
}

/// Protocol constants of `cmux-relay`.
enum RelayProtocol {
    /// The value the relay requires in the `protocol` field of register, connect and join.
    static let version: UInt8 = 5
    /// How long a control exchange (register, allocation, join) may wait for its reply.
    static let controlTimeout: Duration = .seconds(10)
    /// Error codes that mean the ticket itself is not acceptable.
    static let authenticationCodes: Set<String> = [
        "unauthorized", "invalid-ticket", "ticket-expired", "registration-expired",
    ]
}

enum RelayRole: String, Codable, Sendable {
    case daemon
    case client
}

/// The JSON text messages the relay exchanges, tagged by a kebab-case `type`.
enum RelayControl: Equatable, Sendable {
    case register(protocol: UInt8, slot: String, ticket: String)
    case registered(leaseSeconds: UInt32)
    case connect(protocol: UInt8, slot: String, ticket: String, lane: String, generation: UInt64)
    case allocated(circuit: String, lane: String, generation: UInt64, joinTicket: String)
    case incoming(circuit: String, lane: String, generation: UInt64, joinTicket: String)
    case join(
        protocol: UInt8, slot: String, circuit: String, lane: String, generation: UInt64,
        ticket: String, role: RelayRole)
    case ready(circuit: String, lane: String, generation: UInt64)
    case ping(nonce: UInt64)
    case pong(nonce: UInt64)
    case error(code: String, message: String, retryable: Bool)

    func encodedText() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(_ text: String) throws -> RelayControl {
        do {
            return try JSONDecoder().decode(RelayControl.self, from: Data(text.utf8))
        } catch {
            throw RelayError.protocolViolation("invalid relay control message")
        }
    }
}

extension RelayControl: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case `protocol`
        case slot
        case ticket
        case leaseSeconds = "lease_seconds"
        case lane
        case generation
        case circuit
        case joinTicket = "join_ticket"
        case role
        case nonce
        case code
        case message
        case retryable
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "register":
            self = .register(
                protocol: try c.decode(UInt8.self, forKey: .protocol),
                slot: try c.decode(String.self, forKey: .slot),
                ticket: try c.decode(String.self, forKey: .ticket))
        case "registered":
            self = .registered(leaseSeconds: try c.decode(UInt32.self, forKey: .leaseSeconds))
        case "connect":
            self = .connect(
                protocol: try c.decode(UInt8.self, forKey: .protocol),
                slot: try c.decode(String.self, forKey: .slot),
                ticket: try c.decode(String.self, forKey: .ticket),
                lane: try c.decode(String.self, forKey: .lane),
                generation: try c.decode(UInt64.self, forKey: .generation))
        case "allocated", "incoming":
            let circuit = try c.decode(String.self, forKey: .circuit)
            let lane = try c.decode(String.self, forKey: .lane)
            let generation = try c.decode(UInt64.self, forKey: .generation)
            let joinTicket = try c.decode(String.self, forKey: .joinTicket)
            self = type == "allocated"
                ? .allocated(circuit: circuit, lane: lane, generation: generation, joinTicket: joinTicket)
                : .incoming(circuit: circuit, lane: lane, generation: generation, joinTicket: joinTicket)
        case "join":
            self = .join(
                protocol: try c.decode(UInt8.self, forKey: .protocol),
                slot: try c.decode(String.self, forKey: .slot),
                circuit: try c.decode(String.self, forKey: .circuit),
                lane: try c.decode(String.self, forKey: .lane),
                generation: try c.decode(UInt64.self, forKey: .generation),
                ticket: try c.decode(String.self, forKey: .ticket),
                role: try c.decode(RelayRole.self, forKey: .role))
        case "ready":
            self = .ready(
                circuit: try c.decode(String.self, forKey: .circuit),
                lane: try c.decode(String.self, forKey: .lane),
                generation: try c.decode(UInt64.self, forKey: .generation))
        case "ping":
            self = .ping(nonce: try c.decode(UInt64.self, forKey: .nonce))
        case "pong":
            self = .pong(nonce: try c.decode(UInt64.self, forKey: .nonce))
        case "error":
            self = .error(
                code: try c.decode(String.self, forKey: .code),
                message: try c.decode(String.self, forKey: .message),
                retryable: try c.decode(Bool.self, forKey: .retryable))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "unknown relay control type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .register(version, slot, ticket):
            try c.encode("register", forKey: .type)
            try c.encode(version, forKey: .protocol)
            try c.encode(slot, forKey: .slot)
            try c.encode(ticket, forKey: .ticket)
        case let .registered(leaseSeconds):
            try c.encode("registered", forKey: .type)
            try c.encode(leaseSeconds, forKey: .leaseSeconds)
        case let .connect(version, slot, ticket, lane, generation):
            try c.encode("connect", forKey: .type)
            try c.encode(version, forKey: .protocol)
            try c.encode(slot, forKey: .slot)
            try c.encode(ticket, forKey: .ticket)
            try c.encode(lane, forKey: .lane)
            try c.encode(generation, forKey: .generation)
        case let .allocated(circuit, lane, generation, joinTicket),
            let .incoming(circuit, lane, generation, joinTicket):
            if case .allocated = self {
                try c.encode("allocated", forKey: .type)
            } else {
                try c.encode("incoming", forKey: .type)
            }
            try c.encode(circuit, forKey: .circuit)
            try c.encode(lane, forKey: .lane)
            try c.encode(generation, forKey: .generation)
            try c.encode(joinTicket, forKey: .joinTicket)
        case let .join(version, slot, circuit, lane, generation, ticket, role):
            try c.encode("join", forKey: .type)
            try c.encode(version, forKey: .protocol)
            try c.encode(slot, forKey: .slot)
            try c.encode(circuit, forKey: .circuit)
            try c.encode(lane, forKey: .lane)
            try c.encode(generation, forKey: .generation)
            try c.encode(ticket, forKey: .ticket)
            try c.encode(role, forKey: .role)
        case let .ready(circuit, lane, generation):
            try c.encode("ready", forKey: .type)
            try c.encode(circuit, forKey: .circuit)
            try c.encode(lane, forKey: .lane)
            try c.encode(generation, forKey: .generation)
        case let .ping(nonce):
            try c.encode("ping", forKey: .type)
            try c.encode(nonce, forKey: .nonce)
        case let .pong(nonce):
            try c.encode("pong", forKey: .type)
            try c.encode(nonce, forKey: .nonce)
        case let .error(code, message, retryable):
            try c.encode("error", forKey: .type)
            try c.encode(code, forKey: .code)
            try c.encode(message, forKey: .message)
            try c.encode(retryable, forKey: .retryable)
        }
    }
}

/// URL rules for the relay control socket and per-circuit sockets.
enum RelayEndpoint {
    /// Normalizes the configured relay URL into the control WebSocket URL.
    ///
    /// `relay+ws`/`http` map to `ws`, `relay+wss`/`https` to `wss`. An empty path becomes
    /// `/v1/relay`; any other path (for example the ShellX `/v2/relay` route) is kept.
    static func control(_ url: URL) throws -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(), parts.host != nil
        else {
            throw RelayError.protocolViolation("relay URL is invalid")
        }
        switch scheme {
        case "ws", "relay+ws", "http": parts.scheme = "ws"
        case "wss", "relay+wss", "https": parts.scheme = "wss"
        default: throw RelayError.protocolViolation("relay URL scheme \(scheme) is unsupported")
        }
        if parts.path.isEmpty || parts.path == "/" {
            parts.path = "/v1/relay"
        }
        parts.query = nil
        parts.fragment = nil
        guard let control = parts.url else {
            throw RelayError.protocolViolation("relay URL is invalid")
        }
        return control
    }

    /// The URL a circuit socket joins on. The native relay takes joins on the control URL;
    /// slot-routed relays (`/v1/slots/...`) take them on `/v1/circuits/<id>`.
    static func circuit(_ control: URL, circuit: String) -> URL {
        guard control.path.hasPrefix("/v1/slots/"),
              var parts = URLComponents(url: control, resolvingAgainstBaseURL: false)
        else {
            return control
        }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        let segment = circuit.addingPercentEncoding(withAllowedCharacters: allowed) ?? circuit
        parts.percentEncodedPath = "/v1/circuits/\(segment)"
        return parts.url ?? control
    }
}

/// Client-chosen lane tokens: 24 random bytes, base64url without padding.
enum RelayLane {
    static func random() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<24).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

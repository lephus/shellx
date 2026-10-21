import Foundation

public enum ShareRelayRole: String, Sendable, Codable { case daemon, client }

/// The relay2 control messages a share host uses (TEXT JSON, tag `type`, kebab-case), mirroring
/// `RelayControl` in `cmux-tui/crates/cmux-remote-protocol/src/relay.rs`.
public enum ShareRelayControl: Sendable, Equatable {
    /// `REMOTE_PROTOCOL_VERSION` in `cmux-remote-protocol/src/frame.rs`.
    public static let protocolVersion = 5

    case register(protocol: Int, slot: String, ticket: String)
    case registered(leaseSeconds: Int)
    case incoming(circuit: String, lane: String, generation: UInt64, joinTicket: String)
    case join(protocol: Int, slot: String, circuit: String, lane: String, generation: UInt64, ticket: String,
              role: ShareRelayRole)
    case ready(circuit: String, lane: String, generation: UInt64)
    case ping(nonce: UInt64)
    case pong(nonce: UInt64)
    case error(code: String, message: String, retryable: Bool)

    private struct Wire: Codable {
        var type: String
        var `protocol`: Int?
        var slot: String?
        var ticket: String?
        var leaseSeconds: Int?
        var circuit: String?
        var lane: String?
        var generation: UInt64?
        var joinTicket: String?
        var role: ShareRelayRole?
        var nonce: UInt64?
        var code: String?
        var message: String?
        var retryable: Bool?

        enum CodingKeys: String, CodingKey {
            case type, `protocol`, slot, ticket, circuit, lane, generation, role, nonce, code, message, retryable
            case leaseSeconds = "lease_seconds"
            case joinTicket = "join_ticket"
        }
    }

    private var wire: Wire {
        var w = Wire(type: "")
        switch self {
        case .register(let p, let slot, let ticket):
            w.type = "register"; w.protocol = p; w.slot = slot; w.ticket = ticket
        case .registered(let lease):
            w.type = "registered"; w.leaseSeconds = lease
        case .incoming(let circuit, let lane, let generation, let joinTicket):
            w.type = "incoming"; w.circuit = circuit; w.lane = lane; w.generation = generation; w.joinTicket = joinTicket
        case .join(let p, let slot, let circuit, let lane, let generation, let ticket, let role):
            w.type = "join"; w.protocol = p; w.slot = slot; w.circuit = circuit; w.lane = lane
            w.generation = generation; w.ticket = ticket; w.role = role
        case .ready(let circuit, let lane, let generation):
            w.type = "ready"; w.circuit = circuit; w.lane = lane; w.generation = generation
        case .ping(let nonce): w.type = "ping"; w.nonce = nonce
        case .pong(let nonce): w.type = "pong"; w.nonce = nonce
        case .error(let code, let message, let retryable):
            w.type = "error"; w.code = code; w.message = message; w.retryable = retryable
        }
        return w
    }

    public func encoded() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: (try? encoder.encode(wire)) ?? Data(), as: UTF8.self)
    }

    /// nil for malformed JSON, an unknown `type` or a missing field.
    public static func decode(_ text: String) -> ShareRelayControl? {
        guard let w = try? JSONDecoder().decode(Wire.self, from: Data(text.utf8)) else { return nil }
        switch w.type {
        case "register":
            guard let p = w.protocol, let slot = w.slot, let ticket = w.ticket else { return nil }
            return .register(protocol: p, slot: slot, ticket: ticket)
        case "registered":
            return w.leaseSeconds.map { .registered(leaseSeconds: $0) }
        case "incoming":
            guard let c = w.circuit, let l = w.lane, let g = w.generation, let j = w.joinTicket else { return nil }
            return .incoming(circuit: c, lane: l, generation: g, joinTicket: j)
        case "join":
            guard let p = w.protocol, let slot = w.slot, let c = w.circuit, let l = w.lane, let g = w.generation,
                  let t = w.ticket, let r = w.role else { return nil }
            return .join(protocol: p, slot: slot, circuit: c, lane: l, generation: g, ticket: t, role: r)
        case "ready":
            guard let c = w.circuit, let l = w.lane, let g = w.generation else { return nil }
            return .ready(circuit: c, lane: l, generation: g)
        case "ping": return w.nonce.map { .ping(nonce: $0) }
        case "pong": return w.nonce.map { .pong(nonce: $0) }
        case "error":
            guard let c = w.code, let m = w.message, let r = w.retryable else { return nil }
            return .error(code: c, message: m, retryable: r)
        default: return nil
        }
    }
}

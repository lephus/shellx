import Foundation

public enum LinkCodecError: Error, Equatable, Sendable {
    case frameTooLarge
    /// `callId` is the frame's `call_id` when it could be read (valid, 1-64 bytes), so a host can echo it.
    case badJSON(callId: String?)
    case wrongVersion
    case cannotEncodeUnknown
}

/// JSON frame codec for ShellX Link v1: `{"v":1,"t":"<type>",...}` in UTF-8.
public enum LinkCodec {
    /// Noise max message (65535) minus the 16-byte tag; counts UTF-8 bytes of the JSON frame.
    public static let maxFrameBytes = 65_519
    /// Maximum UTF-8 bytes of a `call_id`.
    public static let maxCallIdBytes = 64

    private enum T {
        static let hello = "hello", welcome = "welcome", error = "error"
        static let snapshotGet = "agent.snapshot.get", snapshot = "agent.snapshot", changed = "agent.changed"
        static let reply = "agent.reply", replyResult = "agent.reply.result"
        static let ping = "ping", pong = "pong"
    }

    // Per-message bodies (keys are snake_case on the wire).
    private struct Empty: Codable {}
    private struct Hello: Codable { var clientVersion: String; var deviceName: String }
    private struct Welcome: Codable { var protocolVersion: Int; var hostVersion: String; var machineName: String }
    private struct Err: Codable { var code: String; var message: String; var callId: String? }
    private struct CallOnly: Codable { var callId: String }
    private struct Snapshot: Codable { var callId: String; var revision: Int; var pending: [PendingItem] }
    private struct Changed: Codable { var revision: Int; var added: [PendingItem]; var resolved: [String] }
    private struct Reply: Codable { var callId: String; var requestId: String; var decision: LinkDecision }
    private struct ReplyResult: Codable { var callId: String; var requestId: String; var outcome: ReplyOutcome }
    private struct Nonce: Codable { var nonce: UInt64 }

    private struct Envelope { var v: Int; var t: String }

    /// Strict envelope: `v` must be a JSON integer token (`1.0`, `1e0`, `"1"`, `true` are `badJSON`).
    private static func parseEnvelope(_ d: Data) throws -> Envelope {
        guard let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let vn = obj["v"] as? NSNumber, String(cString: vn.objCType) == "q",
              let t = obj["t"] as? String
        else { throw LinkCodecError.badJSON(callId: nil) }
        return Envelope(v: vn.intValue, t: t)
    }

    private static func validCallId(_ id: String) -> Bool {
        let n = id.utf8.count
        return n >= 1 && n <= maxCallIdBytes
    }

    /// The frame's `call_id`, when it is a valid one.
    private static func readCallId(_ d: Data) -> String? {
        guard let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let id = obj["call_id"] as? String, validCallId(id) else { return nil }
        return id
    }

    private struct Frame<Body: Encodable>: Encodable {
        var t: String
        var body: Body
        private enum Keys: String, CodingKey { case v, t }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(ShellXLink.protocolVersion, forKey: .v)
            try c.encode(t, forKey: .t)
            try body.encode(to: encoder)
        }
    }

    public static func encode(_ m: LinkMessage) throws -> Data {
        let data: Data
        do {
            switch m {
            case let .hello(cv, dn): data = try enc(T.hello, Hello(clientVersion: cv, deviceName: dn))
            case let .welcome(pv, hv, mn): data = try enc(T.welcome, Welcome(protocolVersion: pv, hostVersion: hv, machineName: mn))
            case let .error(code, message, callId):
                if let callId { try requireValid(callId) }
                data = try enc(T.error, Err(code: code, message: message, callId: callId))
            case let .snapshotGet(callId):
                try requireValid(callId)
                data = try enc(T.snapshotGet, CallOnly(callId: callId))
            case let .snapshot(callId, r, p):
                try requireValid(callId)
                data = try enc(T.snapshot, Snapshot(callId: callId, revision: r, pending: p))
            case let .changed(r, a, res): data = try enc(T.changed, Changed(revision: r, added: a, resolved: res))
            case let .reply(callId, id, decision):
                try requireValid(callId)
                data = try enc(T.reply, Reply(callId: callId, requestId: id, decision: decision))
            case let .replyResult(callId, id, o):
                try requireValid(callId)
                data = try enc(T.replyResult, ReplyResult(callId: callId, requestId: id, outcome: o))
            case let .ping(n): data = try enc(T.ping, Nonce(nonce: n))
            case let .pong(n): data = try enc(T.pong, Nonce(nonce: n))
            case .unknown: throw LinkCodecError.cannotEncodeUnknown
            }
        } catch let e as LinkCodecError {
            throw e
        } catch {
            throw LinkCodecError.badJSON(callId: nil)
        }
        guard data.count <= maxFrameBytes else { throw LinkCodecError.frameTooLarge }
        return data
    }

    public static func decode(_ d: Data) throws -> LinkMessage {
        guard d.count <= maxFrameBytes else { throw LinkCodecError.frameTooLarge }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let env = try parseEnvelope(d)
        guard env.v == ShellXLink.protocolVersion else { throw LinkCodecError.wrongVersion }
        func body<B: Decodable>(_ type: B.Type) throws -> B {
            do { return try decoder.decode(type, from: d) } catch { throw LinkCodecError.badJSON(callId: readCallId(d)) }
        }
        /// A `call_id` that is present must also be 1-64 bytes; a frame with a bad one is `bad_json`
        /// without a callId to echo.
        func call<B: Decodable>(_ type: B.Type, _ id: KeyPath<B, String>) throws -> B {
            let b = try body(type)
            guard validCallId(b[keyPath: id]) else { throw LinkCodecError.badJSON(callId: nil) }
            return b
        }
        switch env.t {
        case T.hello: let b = try body(Hello.self); return .hello(clientVersion: b.clientVersion, deviceName: b.deviceName)
        case T.welcome:
            let b = try body(Welcome.self)
            return .welcome(protocolVersion: b.protocolVersion, hostVersion: b.hostVersion, machineName: b.machineName)
        case T.error:
            let b = try body(Err.self)
            if let id = b.callId, !validCallId(id) { throw LinkCodecError.badJSON(callId: nil) }
            return .error(code: b.code, message: b.message, callId: b.callId)
        case T.snapshotGet: return .snapshotGet(callId: try call(CallOnly.self, \.callId).callId)
        case T.snapshot:
            let b = try call(Snapshot.self, \.callId)
            return .snapshot(callId: b.callId, revision: b.revision, pending: b.pending)
        case T.changed:
            let b = try body(Changed.self)
            return .changed(revision: b.revision, added: b.added, resolved: b.resolved)
        case T.reply:
            let b = try call(Reply.self, \.callId)
            return .reply(callId: b.callId, requestId: b.requestId, decision: b.decision)
        case T.replyResult:
            let b = try call(ReplyResult.self, \.callId)
            return .replyResult(callId: b.callId, requestId: b.requestId, outcome: b.outcome)
        case T.ping: return .ping(nonce: try body(Nonce.self).nonce)
        case T.pong: return .pong(nonce: try body(Nonce.self).nonce)
        default: return .unknown(type: env.t)
        }
    }

    private static func requireValid(_ callId: String) throws {
        guard validCallId(callId) else { throw LinkCodecError.badJSON(callId: nil) }
    }

    private static func enc<B: Encodable>(_ t: String, _ body: B) throws -> Data {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try e.encode(Frame(t: t, body: body))
    }
}

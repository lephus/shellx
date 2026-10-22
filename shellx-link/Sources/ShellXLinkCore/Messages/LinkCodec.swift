import Foundation

public enum LinkCodecError: Error, Equatable, Sendable {
    case frameTooLarge
    case badJSON
    case wrongVersion
    case cannotEncodeUnknown
}

/// JSON frame codec for ShellX Link v1: `{"v":1,"t":"<type>",...}` in UTF-8.
public enum LinkCodec {
    /// Noise max message (65535) minus the 16-byte tag; counts UTF-8 bytes of the JSON frame.
    public static let maxFrameBytes = 65_519

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
    private struct Err: Codable { var code: String; var message: String }
    private struct Snapshot: Codable { var revision: Int; var pending: [PendingItem] }
    private struct Changed: Codable { var revision: Int; var added: [PendingItem]; var resolved: [String] }
    private struct Reply: Codable { var requestId: String; var mode: PermissionMode }
    private struct ReplyResult: Codable { var requestId: String; var outcome: ReplyOutcome }
    private struct Nonce: Codable { var nonce: UInt64 }

    private struct Envelope { var v: Int; var t: String }

    /// Strict envelope: `v` must be a JSON integer token (`1.0`, `1e0`, `"1"`, `true` are `badJSON`).
    private static func parseEnvelope(_ d: Data) throws -> Envelope {
        guard let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let vn = obj["v"] as? NSNumber, String(cString: vn.objCType) == "q",
              let t = obj["t"] as? String
        else { throw LinkCodecError.badJSON }
        return Envelope(v: vn.intValue, t: t)
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
            case let .error(code, message): data = try enc(T.error, Err(code: code, message: message))
            case .snapshotGet: data = try enc(T.snapshotGet, Empty())
            case let .snapshot(r, p): data = try enc(T.snapshot, Snapshot(revision: r, pending: p))
            case let .changed(r, a, res): data = try enc(T.changed, Changed(revision: r, added: a, resolved: res))
            case let .reply(id, mode): data = try enc(T.reply, Reply(requestId: id, mode: mode))
            case let .replyResult(id, o): data = try enc(T.replyResult, ReplyResult(requestId: id, outcome: o))
            case let .ping(n): data = try enc(T.ping, Nonce(nonce: n))
            case let .pong(n): data = try enc(T.pong, Nonce(nonce: n))
            case .unknown: throw LinkCodecError.cannotEncodeUnknown
            }
        } catch let e as LinkCodecError {
            throw e
        } catch {
            throw LinkCodecError.badJSON
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
            do { return try decoder.decode(type, from: d) } catch { throw LinkCodecError.badJSON }
        }
        switch env.t {
        case T.hello: let b = try body(Hello.self); return .hello(clientVersion: b.clientVersion, deviceName: b.deviceName)
        case T.welcome:
            let b = try body(Welcome.self)
            return .welcome(protocolVersion: b.protocolVersion, hostVersion: b.hostVersion, machineName: b.machineName)
        case T.error: let b = try body(Err.self); return .error(code: b.code, message: b.message)
        case T.snapshotGet: return .snapshotGet
        case T.snapshot: let b = try body(Snapshot.self); return .snapshot(revision: b.revision, pending: b.pending)
        case T.changed:
            let b = try body(Changed.self)
            return .changed(revision: b.revision, added: b.added, resolved: b.resolved)
        case T.reply: let b = try body(Reply.self); return .reply(requestId: b.requestId, mode: b.mode)
        case T.replyResult: let b = try body(ReplyResult.self); return .replyResult(requestId: b.requestId, outcome: b.outcome)
        case T.ping: return .ping(nonce: try body(Nonce.self).nonce)
        case T.pong: return .pong(nonce: try body(Nonce.self).nonce)
        default: return .unknown(type: env.t)
        }
    }

    private static func enc<B: Encodable>(_ t: String, _ body: B) throws -> Data {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try e.encode(Frame(t: t, body: body))
    }
}

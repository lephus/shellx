import Foundation

public enum SharePermission: String, Sendable, Codable { case view, type }

public enum ShareLifetime: String, Sendable, Codable {
    case fifteenMinutes = "15m"
    case oneHour = "1h"
    case untilQuit = "until_quit"
}

public enum SharePaneKind: String, Sendable, Codable { case terminal, browser, agent }

public enum ShareByeReason: String, Sendable, Codable {
    case revoked, expired
    case hostQuit = "host_quit"
}

public struct SharePane: Sendable, Equatable, Codable {
    public var id: String
    public var title: String
    public var kind: SharePaneKind
    public var cols: Int
    public var rows: Int

    public init(id: String, title: String, kind: SharePaneKind, cols: Int, rows: Int) {
        self.id = id; self.title = title; self.kind = kind; self.cols = cols; self.rows = rows
    }
}

/// Plaintext messages of wire format v1. `seq` is added by the cipher, not stored here.
public enum ShareMessage: Sendable, Equatable, Codable {
    case welcome(nonce: Data, perm: SharePermission, expiresAt: Int?, panes: [SharePane], active: String)
    case panes([SharePane], active: String)
    case replay(pane: String, cols: Int, rows: Int, data: Data)
    case out(pane: String, data: Data)
    case size(pane: String, cols: Int, rows: Int)
    case bye(ShareByeReason)
    /// Host keepalive (amendment A2): sent on a live circuit idle for 60 s; carries only `seq`.
    case ka
    case hello(nonce: Data, label: String)
    case select(pane: String)
    case input(pane: String, data: Data)

    private enum Key: String, CodingKey {
        case t, seq, nonce, perm, panes, active, pane, cols, rows, data, reason, label
        case expiresAt = "expires_at_unix"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        func b64(_ k: Key) throws -> Data {
            guard let d = Data(base64Encoded: try c.decode(String.self, forKey: k)) else {
                throw DecodingError.dataCorruptedError(forKey: k, in: c, debugDescription: "bad base64")
            }
            return d
        }
        func nonce(_ c: KeyedDecodingContainer<Key>) throws -> Data {
            guard let d = Data(base64Encoded: try c.decode(String.self, forKey: .nonce)), d.count == 16 else {
                throw DecodingError.dataCorruptedError(forKey: .nonce, in: c, debugDescription: "nonce must be 16 bytes")
            }
            return d
        }
        switch try c.decode(String.self, forKey: .t) {
        case "welcome":
            self = .welcome(nonce: try nonce(c), perm: try c.decode(SharePermission.self, forKey: .perm),
                            expiresAt: try c.decodeIfPresent(Int.self, forKey: .expiresAt),
                            panes: try c.decode([SharePane].self, forKey: .panes),
                            active: try c.decode(String.self, forKey: .active))
        case "panes":
            self = .panes(try c.decode([SharePane].self, forKey: .panes), active: try c.decode(String.self, forKey: .active))
        case "replay":
            self = .replay(pane: try c.decode(String.self, forKey: .pane), cols: try c.decode(Int.self, forKey: .cols),
                           rows: try c.decode(Int.self, forKey: .rows), data: try b64(.data))
        case "out": self = .out(pane: try c.decode(String.self, forKey: .pane), data: try b64(.data))
        case "size":
            self = .size(pane: try c.decode(String.self, forKey: .pane), cols: try c.decode(Int.self, forKey: .cols),
                         rows: try c.decode(Int.self, forKey: .rows))
        case "bye": self = .bye(try c.decode(ShareByeReason.self, forKey: .reason))
        case "ka": self = .ka
        case "hello": self = .hello(nonce: try nonce(c), label: try c.decode(String.self, forKey: .label))
        case "select": self = .select(pane: try c.decode(String.self, forKey: .pane))
        case "in": self = .input(pane: try c.decode(String.self, forKey: .pane), data: try b64(.data))
        default:
            throw DecodingError.dataCorruptedError(forKey: .t, in: c, debugDescription: "unknown type")
        }
    }

    /// Plain (seq-less) encoding; the wire form is `wireJSON(seq:)`.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        for (key, value) in fields {
            switch value {
            case .string(let s): try c.encode(s, forKey: Key(stringValue: key)!)
            case .int(let i): try c.encode(i, forKey: Key(stringValue: key)!)
            case .optInt(let i): try c.encode(i, forKey: Key(stringValue: key)!)
            case .panes(let p): try c.encode(p, forKey: Key(stringValue: key)!)
            }
        }
    }

    private enum Field { case string(String), int(Int), optInt(Int?), panes([SharePane]) }

    /// Ordered fields after `t`/`seq`, exactly the v1 key names.
    private var fields: [(String, Field)] {
        switch self {
        case .welcome(let nonce, let perm, let exp, let panes, let active):
            [("t", .string("welcome")), ("nonce", .string(nonce.base64EncodedString())), ("perm", .string(perm.rawValue)), ("expires_at_unix", .optInt(exp)),
             ("panes", .panes(panes)), ("active", .string(active))]
        case .panes(let panes, let active):
            [("t", .string("panes")), ("panes", .panes(panes)), ("active", .string(active))]
        case .replay(let pane, let cols, let rows, let data):
            [("t", .string("replay")), ("pane", .string(pane)), ("cols", .int(cols)), ("rows", .int(rows)),
             ("data", .string(data.base64EncodedString()))]
        case .out(let pane, let data):
            [("t", .string("out")), ("pane", .string(pane)), ("data", .string(data.base64EncodedString()))]
        case .size(let pane, let cols, let rows):
            [("t", .string("size")), ("pane", .string(pane)), ("cols", .int(cols)), ("rows", .int(rows))]
        case .bye(let reason): [("t", .string("bye")), ("reason", .string(reason.rawValue))]
        case .ka: [("t", .string("ka"))]
        case .hello(let nonce, let label):
            [("t", .string("hello")), ("nonce", .string(nonce.base64EncodedString())), ("label", .string(label))]
        case .select(let pane): [("t", .string("select")), ("pane", .string(pane))]
        case .input(let pane, let data):
            [("t", .string("in")), ("pane", .string(pane)), ("data", .string(data.base64EncodedString()))]
        }
    }

    /// Deterministic UTF-8 JSON: `t`, `seq`, then the remaining keys in fixed order.
    public func wireJSON(seq: Int) -> Data {
        func str(_ s: String) -> String {
            let enc = JSONEncoder()
            enc.outputFormatting = [.withoutEscapingSlashes]
            return String(decoding: (try? enc.encode(s)) ?? Data("\"\"".utf8), as: UTF8.self)
        }
        func render(_ f: Field) -> String {
            switch f {
            case .string(let s): str(s)
            case .int(let i): String(i)
            case .optInt(let i): i.map(String.init) ?? "null"
            case .panes(let ps):
                "[" + ps.map {
                    #"{"id":\#(str($0.id)),"title":\#(str($0.title)),"kind":\#(str($0.kind.rawValue)),"cols":\#($0.cols),"rows":\#($0.rows)}"#
                }.joined(separator: ",") + "]"
            }
        }
        var parts: [String] = []
        for (i, (k, v)) in fields.enumerated() {
            parts.append("\(str(k)):\(render(v))")
            if i == 0 { parts.append("\"seq\":\(seq)") }
        }
        return Data(("{" + parts.joined(separator: ",") + "}").utf8)
    }
}

/// Decoding wrapper: `seq` must be a JSON integer; the message is decoded from the same parse.
struct ShareEnvelope: Decodable {
    let seq: Int
    let message: ShareMessage

    private enum Key: String, CodingKey { case seq }

    /// JSONDecoder accepts `2.0` for an `Int`, so additionally require that the raw text has exactly
    /// one `"seq":` token followed by plain decimal digits (no sign, fraction or exponent).
    /// An unescaped `"seq":` cannot occur inside a JSON string, so this cannot match string content.
    static func hasIntegerSeqToken(_ json: Data) -> Bool {
        let needle = Array("\"seq\":".utf8)
        let b = Array(json)
        var found: Int?
        var i = 0
        while i + needle.count <= b.count {
            if b[i..<(i + needle.count)].elementsEqual(needle) {
                if found != nil { return false }
                found = i + needle.count
                i += needle.count
            } else { i += 1 }
        }
        guard var j = found, j < b.count else { return false }
        let start = j
        while j < b.count, (0x30...0x39).contains(b[j]) { j += 1 }
        return j > start && j < b.count && (b[j] == 0x2C || b[j] == 0x7D)
    }

    init(from decoder: Decoder) throws {
        seq = try decoder.container(keyedBy: Key.self).decode(Int.self, forKey: .seq)
        message = try ShareMessage(from: decoder)
    }
}

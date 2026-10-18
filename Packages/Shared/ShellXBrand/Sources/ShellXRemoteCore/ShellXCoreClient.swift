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

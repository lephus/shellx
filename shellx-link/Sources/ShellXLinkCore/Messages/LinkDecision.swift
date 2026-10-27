import Foundation

/// A string enum that stays decodable when a newer peer sends a value this version does not know
/// (PROTOCOL.md section 3, "Extension"): unknown strings decode to the enum's `.other(raw)` case.
public protocol LinkWireEnum: Codable, Equatable, Sendable {
    init(wire: String)
    var wire: String { get }
}

extension LinkWireEnum {
    public init(from decoder: Decoder) throws {
        self.init(wire: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wire)
    }
}

/// How the user answers a permission prompt.
public enum PermissionMode: LinkWireEnum {
    case once, always, all, deny
    case other(String)

    public init(wire: String) {
        switch wire {
        case "once": self = .once
        case "always": self = .always
        case "all": self = .all
        case "deny": self = .deny
        default: self = .other(wire)
        }
    }

    public var wire: String {
        switch self {
        case .once: return "once"
        case .always: return "always"
        case .all: return "all"
        case .deny: return "deny"
        case let .other(raw): return raw
        }
    }
}

/// How the user answers an agent's plan.
public enum ExitPlanMode: LinkWireEnum {
    case ultraplan
    case autoAccept
    case manual
    case deny
    case other(String)

    public init(wire: String) {
        switch wire {
        case "ultraplan": self = .ultraplan
        case "auto_accept": self = .autoAccept
        case "manual": self = .manual
        case "deny": self = .deny
        default: self = .other(wire)
        }
    }

    public var wire: String {
        switch self {
        case .ultraplan: return "ultraplan"
        case .autoAccept: return "auto_accept"
        case .manual: return "manual"
        case .deny: return "deny"
        case let .other(raw): return raw
        }
    }
}

/// What the host did with an `agent.reply`.
public enum ReplyOutcome: LinkWireEnum {
    case delivered
    case alreadyHandled
    case unknown
    case other(String)

    public init(wire: String) {
        switch wire {
        case "delivered": self = .delivered
        case "already_handled": self = .alreadyHandled
        case "unknown": self = .unknown
        default: self = .other(wire)
        }
    }

    public var wire: String {
        switch self {
        case .delivered: return "delivered"
        case .alreadyHandled: return "already_handled"
        case .unknown: return "unknown"
        case let .other(raw): return raw
        }
    }
}

/// The user's decision in an `agent.reply`: `{"kind":"permission","mode":"once"}`,
/// `{"kind":"question","selections":["<label>"]}` or `{"kind":"exit_plan","mode":"manual","feedback":"..."}`.
public enum LinkDecision: Codable, Equatable, Sendable {
    case permission(PermissionMode)
    /// The labels of the chosen options (`PendingQuestionOption.label`).
    case question(selections: [String])
    case exitPlan(ExitPlanMode, feedback: String?)
    /// A `kind` this version does not know.
    case other(kind: String)

    /// The wire `kind` this decision answers (equals `PendingItem.Kind.wire` of the item it answers).
    public var kind: String {
        switch self {
        case .permission: return "permission"
        case .question: return "question"
        case .exitPlan: return "exit_plan"
        case let .other(kind): return kind
        }
    }

    private enum Keys: String, CodingKey { case kind, mode, selections, feedback }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "permission": self = .permission(try c.decode(PermissionMode.self, forKey: .mode))
        case "question": self = .question(selections: try c.decode([String].self, forKey: .selections))
        case "exit_plan":
            self = .exitPlan(
                try c.decode(ExitPlanMode.self, forKey: .mode),
                feedback: try c.decodeIfPresent(String.self, forKey: .feedback))
        default: self = .other(kind: kind)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(kind, forKey: .kind)
        switch self {
        case let .permission(mode): try c.encode(mode, forKey: .mode)
        case let .question(selections): try c.encode(selections, forKey: .selections)
        case let .exitPlan(mode, feedback):
            try c.encode(mode, forKey: .mode)
            try c.encodeIfPresent(feedback, forKey: .feedback)
        case .other: break
        }
    }
}

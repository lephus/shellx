import Foundation

public enum ChatEntryRole: LinkWireEnum {
    case user
    case agent
    case system
    case other(String)

    public init(wire: String) {
        switch wire {
        case "user": self = .user
        case "agent": self = .agent
        case "system": self = .system
        default: self = .other(wire)
        }
    }

    public var wire: String {
        switch self {
        case .user: return "user"
        case .agent: return "agent"
        case .system: return "system"
        case let .other(raw): return raw
        }
    }
}

public enum ChatEntryKind: LinkWireEnum {
    case prose
    case thought
    case toolUse
    case status
    /// An entry the host could not classify, or a kind this version does not know.
    case other(String)

    public init(wire: String) {
        switch wire {
        case "prose": self = .prose
        case "thought": self = .thought
        case "tool_use": self = .toolUse
        case "status": self = .status
        default: self = .other(wire)
        }
    }

    public var wire: String {
        switch self {
        case .prose: return "prose"
        case .thought: return "thought"
        case .toolUse: return "tool_use"
        case .status: return "status"
        case let .other(raw): return raw
        }
    }
}

/// One entry of a session's chat transcript. Entries are upserted by `id`; `seq` orders them.
public struct ChatEntry: Codable, Equatable, Sendable {
    /// Maximum UTF-8 bytes of `text` on the wire.
    public static let maxTextBytes = 4096

    public var id: String
    public var seq: Int
    public var role: ChatEntryRole
    public var kind: ChatEntryKind
    public var text: String
    /// True when the host cut `text`; omitted when it did not.
    public var truncated: Bool?
    public var toolName: String?
    public var tsMs: Int64

    public init(
        id: String, seq: Int, role: ChatEntryRole, kind: ChatEntryKind, text: String, truncated: Bool? = nil,
        toolName: String? = nil, tsMs: Int64
    ) {
        self.id = id
        self.seq = seq
        self.role = role
        self.kind = kind
        self.text = text
        self.truncated = truncated
        self.toolName = toolName
        self.tsMs = tsMs
    }

    /// Cuts `text` to at most `maxTextBytes` UTF-8 bytes on a Unicode scalar boundary. The creator of an
    /// entry sets `truncated = true` when this reports a cut, and leaves it nil otherwise.
    public static func cut(_ text: String) -> (text: String, truncated: Bool) {
        guard text.utf8.count > maxTextBytes else { return (text, false) }
        return (PendingItem.truncatedPreview(text, maxBytes: maxTextBytes), true)
    }
}

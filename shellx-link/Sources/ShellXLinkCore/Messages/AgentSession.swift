import Foundation

/// What an agent session is doing (PROTOCOL.md section 4, "AgentSession").
public enum AgentState: LinkWireEnum {
    case idle
    case working
    case needsInput
    case ended
    /// A state this version does not know; clients show the session without a state badge.
    case other(String)

    public init(wire: String) {
        switch wire {
        case "idle": self = .idle
        case "working": self = .working
        case "needs_input": self = .needsInput
        case "ended": self = .ended
        default: self = .other(wire)
        }
    }

    public var wire: String {
        switch self {
        case .idle: return "idle"
        case .working: return "working"
        case .needsInput: return "needs_input"
        case .ended: return "ended"
        case let .other(raw): return raw
        }
    }
}

/// One agent session running on the host, as listed by `agent.sessions`.
public struct AgentSession: Codable, Equatable, Sendable {
    public var sessionId: String
    /// Agent name, for example `claude`.
    public var agent: String
    public var workspaceId: String
    public var workspaceTitle: String
    /// The session's own title, when it has one. The first thing the host drops to fit a frame.
    public var title: String?
    public var state: AgentState
    /// Unix time in milliseconds at which `state` began.
    public var stateSinceMs: Int64?
    public var lastActivityMs: Int64?

    public init(
        sessionId: String, agent: String, workspaceId: String, workspaceTitle: String, title: String? = nil,
        state: AgentState, stateSinceMs: Int64? = nil, lastActivityMs: Int64? = nil
    ) {
        self.sessionId = sessionId
        self.agent = agent
        self.workspaceId = workspaceId
        self.workspaceTitle = workspaceTitle
        self.title = title
        self.state = state
        self.stateSinceMs = stateSinceMs
        self.lastActivityMs = lastActivityMs
    }

    /// A copy without `title` (PROTOCOL.md section 6, the shrink step for `agent.sessions`).
    public func withoutTitle() -> AgentSession {
        var copy = self
        copy.title = nil
        return copy
    }
}

/// How the host answered `chat.send`.
public enum ChatSendOutcome: LinkWireEnum {
    case submitted
    case notFound
    case busy
    case failed
    case other(String)

    public init(wire: String) {
        switch wire {
        case "submitted": self = .submitted
        case "not_found": self = .notFound
        case "busy": self = .busy
        case "failed": self = .failed
        default: self = .other(wire)
        }
    }

    public var wire: String {
        switch self {
        case .submitted: return "submitted"
        case .notFound: return "not_found"
        case .busy: return "busy"
        case .failed: return "failed"
        case let .other(raw): return raw
        }
    }
}

/// How the host answered `chat.interrupt`.
public enum ChatInterruptOutcome: LinkWireEnum {
    case sent
    case notFound
    case failed
    case other(String)

    public init(wire: String) {
        switch wire {
        case "sent": self = .sent
        case "not_found": self = .notFound
        case "failed": self = .failed
        default: self = .other(wire)
        }
    }

    public var wire: String {
        switch self {
        case .sent: return "sent"
        case .notFound: return "not_found"
        case .failed: return "failed"
        case let .other(raw): return raw
        }
    }
}

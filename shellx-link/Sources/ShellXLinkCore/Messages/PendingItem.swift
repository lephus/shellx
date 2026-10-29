import Foundation

/// One agent request waiting for a human decision (permission prompt, question, plan exit).
public struct PendingItem: Codable, Equatable, Sendable {
    public enum Kind: LinkWireEnum {
        case permission
        case question
        case exitPlan
        /// A kind this version does not know; clients show a generic "open on the Mac" card.
        case other(String)

        public init(wire: String) {
            switch wire {
            case "permission": self = .permission
            case "question": self = .question
            case "exit_plan": self = .exitPlan
            default: self = .other(wire)
            }
        }

        public var wire: String {
            switch self {
            case .permission: return "permission"
            case .question: return "question"
            case .exitPlan: return "exit_plan"
            case let .other(raw): return raw
            }
        }
    }

    /// Maximum UTF-8 bytes of `toolInputPreview` and of `planPreview` on the wire.
    public static let maxPreviewBytes = 8192

    public var requestId: String
    public var kind: Kind
    /// Agent name; "claude" in P1.
    public var agent: String
    public var workspaceId: String
    public var workspaceTitle: String
    public var toolName: String?
    public var toolInputPreview: String?
    public var createdAtMs: Int64
    /// The answers this request accepts, as wire strings (`PermissionMode` or `ExitPlanMode` values).
    /// Required on the wire; empty when the request takes no mode (a question).
    public var modes: [String]
    public var questions: [PendingQuestion]?
    /// The plan text of an `exit_plan` request; shrunk like `toolInputPreview` (PROTOCOL.md section 6).
    public var planPreview: String?

    public init(
        requestId: String, kind: Kind, agent: String, workspaceId: String, workspaceTitle: String,
        toolName: String? = nil, toolInputPreview: String? = nil, createdAtMs: Int64,
        modes: [String] = [], questions: [PendingQuestion]? = nil, planPreview: String? = nil
    ) {
        self.requestId = requestId
        self.kind = kind
        self.agent = agent
        self.workspaceId = workspaceId
        self.workspaceTitle = workspaceTitle
        self.toolName = toolName
        self.toolInputPreview = toolInputPreview
        self.createdAtMs = createdAtMs
        self.modes = modes
        self.questions = questions
        self.planPreview = planPreview
    }

    /// Cuts `text` to at most `maxBytes` UTF-8 bytes (default `maxPreviewBytes`), on a Unicode scalar boundary.
    public static func truncatedPreview(_ text: String, maxBytes: Int = maxPreviewBytes) -> String {
        guard text.utf8.count > maxBytes else { return text }
        var used = 0
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let n = String(scalar).utf8.count
            if used + n > maxBytes { break }
            used += n
            out.append(scalar)
        }
        return String(out)
    }

    /// Pure helper for the host's oversize rule (PROTOCOL.md section 6): returns a copy whose previews
    /// (`toolInputPreview` and `planPreview`) are cut to `maxBytes`, or omitted when `maxBytes` is nil.
    public func withPreviewLimit(_ maxBytes: Int?) -> PendingItem {
        var copy = self
        guard let maxBytes else {
            copy.toolInputPreview = nil
            copy.planPreview = nil
            return copy
        }
        copy.toolInputPreview = toolInputPreview.map { Self.truncatedPreview($0, maxBytes: maxBytes) }
        copy.planPreview = planPreview.map { Self.truncatedPreview($0, maxBytes: maxBytes) }
        return copy
    }
}

/// One question of a `question` request.
public struct PendingQuestion: Codable, Equatable, Sendable {
    public var id: String
    public var header: String?
    public var prompt: String
    public var multiSelect: Bool
    public var options: [PendingQuestionOption]

    public init(id: String, header: String? = nil, prompt: String, multiSelect: Bool, options: [PendingQuestionOption]) {
        self.id = id
        self.header = header
        self.prompt = prompt
        self.multiSelect = multiSelect
        self.options = options
    }
}

/// One option of a `PendingQuestion`. A `LinkDecision.question` selects options by `label`.
public struct PendingQuestionOption: Codable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var description: String?

    public init(id: String, label: String, description: String? = nil) {
        self.id = id
        self.label = label
        self.description = description
    }
}

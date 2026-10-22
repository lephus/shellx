import Foundation

/// One agent request waiting for a human decision (permission prompt, question, plan exit).
public struct PendingItem: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case permission
        case question
        case exitPlan = "exit_plan"
    }

    /// Maximum UTF-8 bytes of `toolInputPreview` on the wire.
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

    public init(
        requestId: String, kind: Kind, agent: String, workspaceId: String, workspaceTitle: String,
        toolName: String? = nil, toolInputPreview: String? = nil, createdAtMs: Int64
    ) {
        self.requestId = requestId
        self.kind = kind
        self.agent = agent
        self.workspaceId = workspaceId
        self.workspaceTitle = workspaceTitle
        self.toolName = toolName
        self.toolInputPreview = toolInputPreview
        self.createdAtMs = createdAtMs
    }

    /// Cuts `text` to at most `maxPreviewBytes` UTF-8 bytes, on a Unicode scalar boundary.
    public static func truncatedPreview(_ text: String) -> String {
        guard text.utf8.count > maxPreviewBytes else { return text }
        var used = 0
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let n = String(scalar).utf8.count
            if used + n > maxPreviewBytes { break }
            used += n
            out.append(scalar)
        }
        return String(out)
    }
}

public enum PermissionMode: String, Codable, Sendable { case once, always, all, deny }

public enum ReplyOutcome: String, Codable, Sendable {
    case delivered
    case alreadyHandled = "already_handled"
    case unknown
}

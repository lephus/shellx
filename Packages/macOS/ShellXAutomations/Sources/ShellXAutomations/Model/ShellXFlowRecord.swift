public import Foundation

/// A drawn flow plus what it was drawn from.
public struct ShellXFlowRecord: Codable, Sendable, Equatable {
    /// The flowchart.
    public var flow: ShellXAutomationFlow
    /// Fingerprint of the `SKILL.md` text the flow was drawn from.
    public var sourceHash: String
    /// When Claude drew it.
    public var drawnAt: Date

    /// Creates a record.
    public init(flow: ShellXAutomationFlow, sourceHash: String, drawnAt: Date) {
        self.flow = flow
        self.sourceHash = sourceHash
        self.drawnAt = drawnAt
    }
}

/// How a stored flow relates to the current `SKILL.md`.
public enum ShellXFlowStatus: String, Sendable {
    /// Drawn from the current text.
    case current
    /// Drawn from an older text.
    case stale
    /// No usable flow is stored.
    case missing
    /// Workflows derive their chart from their steps and store none.
    case derived
}

public import Foundation

/// The recorded outcome of one automation run.
public struct ShellXRunRecord: Codable, Sendable, Equatable {
    /// Run state.
    public var status: ShellXRunStatus
    /// What started the run.
    public var trigger: ShellXRunTrigger
    /// Start time.
    public var startedAt: Date
    /// Finish time, once finished.
    public var finishedAt: Date?
    /// Claude session id, if known.
    public var sessionId: String?
    /// Summary of a finished run.
    public var summary: String?
    /// Failure or needs-you reason.
    public var reason: String?
    /// One-based index of the failed workflow step.
    public var failedStep: Int?
    /// Whether the user has not yet seen this run.
    public var unread: Bool

    /// Creates a run record.
    public init(
        status: ShellXRunStatus,
        trigger: ShellXRunTrigger,
        startedAt: Date,
        finishedAt: Date? = nil,
        sessionId: String? = nil,
        summary: String? = nil,
        reason: String? = nil,
        failedStep: Int? = nil,
        unread: Bool = true
    ) {
        self.status = status
        self.trigger = trigger
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.sessionId = sessionId
        self.summary = summary
        self.reason = reason
        self.failedStep = failedStep
        self.unread = unread
    }
}

public import Foundation

/// A Claude Code run went past its time limit and was stopped.
///
/// ``ShellXClaudeProcess`` throws it; the runner records its description as the run's failure reason.
public struct ShellXClaudeTimeLimitError: LocalizedError, Sendable, Equatable {
    /// Creates the error.
    public init() {}

    /// Plain English; the host shows run reasons as they are.
    public var errorDescription: String? { "Claude Code ran longer than the time limit." }
}

public import Foundation

/// Runs one headless Claude Code invocation.
public protocol ShellXClaudeLaunching: Sendable {
    /// Runs `prompt` in `workingDirectory`, appends every output line to `transcript` and returns what the run produced.
    func run(
        prompt: String,
        workingDirectory: URL,
        allowedTools: [String],
        resumeSessionId: String?,
        transcript: URL
    ) async throws -> ShellXClaudeResult
}

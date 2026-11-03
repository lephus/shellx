public import Foundation

/// Starts the Claude Code process the creator talks to.
public protocol ShellXCreatorProcessLaunching: Sendable {
    /// Launches Claude Code with `arguments` in `workingDirectory`.
    ///
    /// - Returns: stdout lines, a closure that writes one line to stdin, and a closure that stops the process.
    func start(arguments: [String], workingDirectory: URL) async throws -> (
        lines: AsyncThrowingStream<String, any Error>,
        send: @Sendable (String) async throws -> Void,
        stop: @Sendable () async -> Void
    )
}

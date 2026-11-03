import Foundation
import ShellXAutomations

/// Starts the creator's Claude Code once its path is known.
///
/// The creator session is built synchronously, but finding `claude` and the user's `PATH` may
/// take seconds, so this launcher asks ``ShellXClaudePathCache`` when the session starts and
/// then hands off to ``ShellXCreatorProcess``.
struct ShellXResolvingCreatorLauncher: ShellXCreatorProcessLaunching {
    private let claude: ShellXClaudePathCache

    init(claude: ShellXClaudePathCache) {
        self.claude = claude
    }

    func start(arguments: [String], workingDirectory: URL) async throws -> (
        lines: AsyncThrowingStream<String, any Error>,
        send: @Sendable (String) async throws -> Void,
        stop: @Sendable () async -> Void
    ) {
        guard let launch = await claude.launch() else {
            throw ClaudeMissing()
        }
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let process = ShellXCreatorProcess(executablePath: launch.path, environment: launch.environment)
        return try await process.start(arguments: arguments, workingDirectory: workingDirectory)
    }

    /// No `claude` binary was found; the message is shown in the creator chat.
    struct ClaudeMissing: LocalizedError {
        var errorDescription: String? {
            String(
                localized: "automations.creator.claudeMissing",
                defaultValue: "Claude Code was not found on this Mac. Install it, then try again."
            )
        }
    }
}

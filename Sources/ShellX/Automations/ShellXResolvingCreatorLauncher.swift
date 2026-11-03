import Foundation
import ShellXAutomations

/// Starts the creator's Claude Code once its path is known.
///
/// The creator session is built synchronously, but finding `claude` may take seconds, so
/// this launcher asks ``ShellXClaudePathCache`` when the session starts and then hands off
/// to ``ShellXCreatorProcess`` with a `PATH` that also reaches the tools `claude` calls.
struct ShellXResolvingCreatorLauncher: ShellXCreatorProcessLaunching {
    private let claudePath: ShellXClaudePathCache
    private let baseEnvironment: [String: String]

    init(claudePath: ShellXClaudePathCache, baseEnvironment: [String: String]) {
        self.claudePath = claudePath
        self.baseEnvironment = baseEnvironment
    }

    func start(arguments: [String], workingDirectory: URL) async throws -> (
        lines: AsyncThrowingStream<String, any Error>,
        send: @Sendable (String) async throws -> Void,
        stop: @Sendable () async -> Void
    ) {
        guard let executable = await claudePath.path() else {
            throw ShellXCreatorProcess.Failure(message: String(
                localized: "automations.creator.claudeMissing",
                defaultValue: "Claude Code was not found on this Mac. Install it, then try again."
            ))
        }
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let process = ShellXCreatorProcess(
            executablePath: executable,
            environment: Self.environment(base: baseEnvironment, claudePath: executable)
        )
        return try await process.start(arguments: arguments, workingDirectory: workingDirectory)
    }

    /// `base` with `PATH` led by the folder holding `claude`, then Homebrew's folders.
    static func environment(base: [String: String], claudePath: String) -> [String: String] {
        var environment = base
        let claudeFolder = URL(filePath: claudePath).deletingLastPathComponent().path
        var entries = [claudeFolder, "/opt/homebrew/bin", "/usr/local/bin"]
        let existing = (base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        for entry in existing where !entries.contains(entry) { entries.append(entry) }
        environment["PATH"] = entries.joined(separator: ":")
        return environment
    }
}

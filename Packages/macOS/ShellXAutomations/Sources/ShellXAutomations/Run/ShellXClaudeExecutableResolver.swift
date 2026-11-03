public import Foundation

/// Finds the user's `claude` binary. Never returns ShellX's own `shellx-claude-wrapper`.
public struct ShellXClaudeExecutableResolver: Sendable {
    private let environment: [String: String]
    private let home: URL
    private let isExecutable: @Sendable (String) -> Bool
    private let loginShellLookup: @Sendable () -> String?

    /// Creates a resolver. `loginShellLookup` should run `/bin/zsh -lc 'command -v claude'`.
    public init(
        environment: [String: String],
        home: URL,
        isExecutable: @escaping @Sendable (String) -> Bool,
        loginShellLookup: @escaping @Sendable () -> String?
    ) {
        self.environment = environment
        self.home = home
        self.isExecutable = isExecutable
        self.loginShellLookup = loginShellLookup
    }

    /// Absolute path of `claude`, or `nil` when none is found.
    public func resolve() -> String? {
        var candidates: [String] = []
        if let override = environment["SHELLX_CLAUDE_PATH"], !override.isEmpty { candidates.append(override) }
        candidates.append(home.appending(path: ".claude/local/claude").path)
        candidates.append(home.appending(path: ".local/bin/claude").path)
        candidates.append("/opt/homebrew/bin/claude")
        candidates.append("/usr/local/bin/claude")
        for path in candidates where accepts(path) { return path }
        guard let found = loginShellLookup()?.trimmingCharacters(in: .whitespacesAndNewlines),
              found.hasPrefix("/"), accepts(found) else { return nil }
        return found
    }

    private func accepts(_ path: String) -> Bool {
        guard isExecutable(path) else { return false }
        let real = URL(filePath: path).resolvingSymlinksInPath().lastPathComponent
        return real != "shellx-claude-wrapper"
    }
}

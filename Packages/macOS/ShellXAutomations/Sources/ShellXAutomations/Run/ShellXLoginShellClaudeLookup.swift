public import Foundation

/// Asks the user's login shell where `claude` lives (`/bin/zsh -lc 'command -v claude'`).
///
/// Blocks like ``ShellXLoginShellCommand``: call it on a dedicated thread, never on the cooperative pool.
public struct ShellXLoginShellClaudeLookup: Sendable {
    private let timeout: Duration

    /// Creates a lookup that gives the shell `timeout` before killing it.
    public init(timeout: Duration = .seconds(5)) {
        self.timeout = timeout
    }

    /// The absolute path printed by the shell, or `nil`.
    public func callAsFunction() -> String? {
        ShellXLoginShellCommand(script: "command -v claude", timeout: timeout)().flatMap(Self.absolutePath(fromOutput:))
    }

    /// The last non-empty line of `output`, if it is an absolute path.
    static func absolutePath(fromOutput output: String) -> String? {
        let last = output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        guard let last, last.hasPrefix("/") else { return nil }
        return last
    }
}

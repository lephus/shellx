public import Foundation

/// The environment an unattended `claude` run gets.
///
/// launchd starts jobs with `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, so tools such as `gh`, Homebrew's `node`
/// or `jq` would be missing. PATH becomes, de-duplicated in this order: the folders of `claude` (as linked,
/// then resolved), the login shell's PATH, the usual install folders, then anything else already inherited.
/// Every other variable is inherited unchanged.
public struct ShellXRoutineClaudeEnvironment: Sendable {
    private let inherited: [String: String]
    private let home: URL
    private let loginShellPath: @Sendable () -> String?
    private let resolveSymlinks: @Sendable (String) -> String

    /// Creates the builder. `loginShellPath` returns the raw output of `print -r -- $PATH` in the login shell
    /// (see ``live(inherited:home:)``); `resolveSymlinks` maps a path to its target.
    public init(
        inherited: [String: String],
        home: URL,
        loginShellPath: @escaping @Sendable () -> String?,
        resolveSymlinks: @escaping @Sendable (String) -> String
    ) {
        self.inherited = inherited
        self.home = home
        self.loginShellPath = loginShellPath
        self.resolveSymlinks = resolveSymlinks
    }

    /// A builder that asks the real login shell (bounded) and resolves symlinks on disk.
    /// ``environment(forClaudeAt:)`` then blocks like ``ShellXLoginShellCommand``: call it on a dedicated thread.
    public static func live(inherited: [String: String], home: URL) -> ShellXRoutineClaudeEnvironment {
        ShellXRoutineClaudeEnvironment(
            inherited: inherited,
            home: home,
            loginShellPath: { ShellXLoginShellCommand(script: "print -r -- $PATH")() },
            resolveSymlinks: { URL(filePath: $0).resolvingSymlinksInPath().path }
        )
    }

    /// The environment for the `claude` binary at `claudePath`.
    public func environment(forClaudeAt claudePath: String) -> [String: String] {
        let linkFolder = URL(filePath: claudePath).deletingLastPathComponent().path
        let resolvedFolder = URL(filePath: resolveSymlinks(claudePath)).deletingLastPathComponent().path
        let login = loginShellPath().map(Self.entries(fromLoginShellOutput:)) ?? []
        let fallbacks = [
            "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", home.appending(path: ".local/bin").path,
            "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        ]
        let inheritedEntries = (inherited["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen: Set<String> = []
        var path: [String] = []
        for entry in [linkFolder, resolvedFolder] + login + fallbacks + inheritedEntries
        where entry.hasPrefix("/") && seen.insert(entry).inserted {
            path.append(entry)
        }
        var result = inherited
        result["PATH"] = path.joined(separator: ":")
        return result
    }

    /// The absolute entries of the last non-empty line of the login shell's output (profile scripts may print first).
    static func entries(fromLoginShellOutput output: String) -> [String] {
        let last = output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty } ?? ""
        return last.split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
    }
}

public import Foundation

/// Posts banners through the `ShellX Notifier.app` helper, launched with `/usr/bin/open`.
public struct ShellXNotifierClient: ShellXNotifying {
    private let helperAppPath: String
    private let runOpen: @Sendable ([String]) async throws -> Int32

    /// Creates a client for the helper at `helperAppPath`. `runOpen` runs an argument vector (executable first) and returns its exit status.
    public init(helperAppPath: String, runOpen: @escaping @Sendable ([String]) async throws -> Int32) {
        self.helperAppPath = helperAppPath
        self.runOpen = runOpen
    }

    /// The argument vector that launches a fresh, background helper instance for `n`.
    func argv(for n: ShellXAutomationNotification) -> [String] {
        [
            "/usr/bin/open", "-g", "-n", "-a", helperAppPath, "--args",
            "--title", n.title,
            "--body", n.body,
            "--url", n.url.absoluteString,
            "--group", n.group,
        ]
    }

    /// Launches the helper; throws when `open` exits non-zero.
    public func post(_ n: ShellXAutomationNotification) async throws {
        let status = try await runOpen(argv(for: n))
        guard status == 0 else { throw ShellXNotifierError.openFailed(status: status) }
    }
}

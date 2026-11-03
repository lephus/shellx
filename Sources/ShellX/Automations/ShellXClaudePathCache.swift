import Foundation
import ShellXAutomations

/// Resolves the user's `claude` binary once and remembers the answer.
///
/// ``ShellXClaudeExecutableResolver/resolve()`` can block for seconds while the login
/// shell answers, so it runs on a detached task, never on the main actor or the
/// cooperative pool's callers. A miss is not cached, so installing Claude Code later works.
actor ShellXClaudePathCache {
    private let resolve: @Sendable () -> String?
    private var cached: String?
    private var inFlight: Task<String?, Never>?

    init(resolve: @escaping @Sendable () -> String?) {
        self.resolve = resolve
    }

    /// The absolute path of `claude`, or nil when none was found.
    func path() async -> String? {
        if let cached { return cached }
        if let inFlight { return await inFlight.value }
        let resolve = resolve
        let task = Task.detached(priority: .userInitiated) { resolve() }
        inFlight = task
        let found = await task.value
        inFlight = nil
        cached = found
        return found
    }
}

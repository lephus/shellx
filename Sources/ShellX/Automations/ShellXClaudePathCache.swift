import Foundation
import ShellXAutomations

/// Finds the user's `claude` binary and the environment to run it with, once, and remembers both.
///
/// ``ShellXClaudeExecutableResolver/resolve()`` and ``ShellXRoutineClaudeEnvironment`` ask the
/// login shell and can block for seconds, so the lookup runs on its own thread, never on the
/// main actor or the cooperative pool. A miss is not cached, so installing Claude Code later works.
actor ShellXClaudePathCache {
    /// Where `claude` is and the environment (with the user's `PATH`) it runs with.
    struct Launch: Sendable, Equatable {
        let path: String
        let environment: [String: String]
    }

    private let lookUp: @Sendable () -> Launch?
    private var cached: Launch?
    private var inFlight: Task<Launch?, Never>?

    /// - Parameter lookUp: Blocking lookup; it runs on a dedicated thread.
    init(lookUp: @escaping @Sendable () -> Launch?) {
        self.lookUp = lookUp
    }

    /// Resolves with `resolver`, then builds the environment for the found binary with `environment`.
    init(resolver: ShellXClaudeExecutableResolver, environment: ShellXRoutineClaudeEnvironment) {
        self.init(lookUp: {
            guard let path = resolver.resolve() else { return nil }
            return Launch(path: path, environment: environment.environment(forClaudeAt: path))
        })
    }

    /// The absolute path of `claude`, or nil when none was found.
    func path() async -> String? {
        await launch()?.path
    }

    /// The binary and its environment, or nil when none was found.
    func launch() async -> Launch? {
        if let cached { return cached }
        if let inFlight { return await inFlight.value }
        let lookUp = lookUp
        let task = Task<Launch?, Never> {
            await withCheckedContinuation { continuation in
                // Blocking login-shell work: a thread of its own, like the CLI does.
                Thread.detachNewThread { continuation.resume(returning: lookUp()) }
            }
        }
        inFlight = task
        let found = await task.value
        inFlight = nil
        cached = found
        return found
    }
}

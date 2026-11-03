import Foundation
import os
import ShellXAutomations

/// Starts `shellx routine run <id> --trigger manual` for "Run now", the same command launchd calls.
///
/// The run keeps going on its own. The launcher only waits ``grace`` to catch a CLI that could not
/// start or exited non-zero at once, and reports that as a readable message; after the grace, or on a
/// clean early exit, it reports nil.
struct ShellXRoutineRunLauncher: Sendable {
    private let cliPath: String
    private let grace: Duration
    private let run: @Sendable ([String]) async throws -> Int32

    /// - Parameters:
    ///   - cliPath: The bundled `shellx`.
    ///   - grace: How long an early failure still counts as "could not start".
    ///   - run: Runs an argument vector and returns its exit status; ``ShellXArgvProcess`` in the app.
    init(
        cliPath: String,
        grace: Duration = .seconds(1),
        run: @escaping @Sendable ([String]) async throws -> Int32 = { try await ShellXArgvProcess().run($0) }
    ) {
        self.cliPath = cliPath
        self.grace = grace
        self.run = run
    }

    /// Starts the run for `id`; returns a failure message, or nil when it started.
    func start(_ id: String) async -> String? {
        let argv = [cliPath, "routine", "run", id, "--trigger", "manual"]
        let run = run
        let grace = grace
        return await withCheckedContinuation { continuation in
            // Carve-out: the process exit and the grace deadline race to resume the continuation exactly once.
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let finish: @Sendable (String?) -> Void = { value in
                let first = resumed.withLock { done -> Bool in
                    defer { done = true }
                    return !done
                }
                if first { continuation.resume(returning: value) }
            }
            Task.detached(priority: .utility) {
                do {
                    let status = try await run(argv)
                    finish(status == 0 ? nil : String(
                        localized: "automations.run.exitStatus",
                        defaultValue: "shellx stopped with status \(Int(status))."
                    ))
                } catch {
                    finish(error.localizedDescription)
                }
            }
            Task.detached {
                try? await Task.sleep(for: grace)
                finish(nil)
            }
        }
    }
}

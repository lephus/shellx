import Foundation
@testable import CmuxGit

struct FakeWorkspaceChangesGitRunner: WorkspaceChangesGitRunning {
    let results: [[String]: WorkspaceChangesGitResult]
    let beforeRun: @Sendable ([String], URL) throws -> Void
    let recorder = FakeWorkspaceChangesGitCallRecorder()

    init(
        results: [[String]: WorkspaceChangesGitResult],
        beforeRun: @escaping @Sendable ([String], URL) throws -> Void = { _, _ in }
    ) {
        self.results = results
        self.beforeRun = beforeRun
    }

    func run(arguments: [String], in directory: URL) throws -> WorkspaceChangesGitResult {
        recorder.record(arguments)
        try beforeRun(arguments, directory)
        return results[arguments] ?? WorkspaceChangesGitResult(output: Data(), exitCode: 1)
    }

    static func result(_ output: String = "", exitCode: Int32 = 0) -> WorkspaceChangesGitResult {
        WorkspaceChangesGitResult(output: Data(output.utf8), exitCode: exitCode)
    }
}

/// Thread-safe list of the argument vectors a runner was asked to execute.
final class FakeWorkspaceChangesGitCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []

    func record(_ arguments: [String]) {
        lock.lock()
        recorded.append(arguments)
        lock.unlock()
    }

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}

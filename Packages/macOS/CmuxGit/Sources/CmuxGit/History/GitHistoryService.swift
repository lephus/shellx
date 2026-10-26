import Darwin
public import Foundation

/// Read-only git access for the Git Graph panel.
///
/// Every method validates web-supplied values first, then runs allow-listed git
/// subcommands through ``WorkspaceChangesGitRunning`` on a dedicated queue so the
/// cooperative pool and the main actor are never blocked.
public struct GitHistoryService: Sendable {
    private static let queue = DispatchQueue(
        label: "pro.shellx.git-history",
        qos: .utility,
        attributes: .concurrent
    )
    private static let pageOutputLimit = 16 * 1024 * 1024
    private static let patchOutputLimit = 8 * 1024 * 1024
    private static let metadataOutputLimit = 16 * 1024 * 1024
    private static let messageOutputLimit = 256 * 1024
    private static let commonPrefix = [
        "-c", "core.fsmonitor=false",
        "-c", "log.showSignature=false",
        "-c", "color.ui=false",
    ]

    private let runner: any WorkspaceChangesGitRunning
    private let pageSize: Int
    private let maximumCommits: Int
    private let wallTimeLimit: TimeInterval

    public init() {
        self.init(runner: SystemWorkspaceChangesGitRunner())
    }

    init(
        runner: any WorkspaceChangesGitRunning,
        pageSize: Int = GitHistoryLimits.pageSize,
        maximumCommits: Int = GitHistoryLimits.maximumCommits,
        wallTimeLimit: TimeInterval = 15
    ) {
        self.runner = runner
        self.pageSize = pageSize
        self.maximumCommits = maximumCommits
        self.wallTimeLimit = wallTimeLimit
    }

    // MARK: Public API

    public func head(repositoryRoot: String) async throws -> GitHistoryHead {
        try await execute(repositoryRoot) { try $0.loadHead() }
    }

    public func refs(repositoryRoot: String) async throws -> [GitHistoryRef] {
        try await execute(repositoryRoot) { try $0.loadRefs() }
    }

    public func page(
        repositoryRoot: String,
        query: GitHistoryQuery,
        skip: Int
    ) async throws -> GitHistoryPage {
        try GitHistoryArgumentValidator.validateSkip(skip)
        try GitHistoryArgumentValidator.validateBranchFullName(query.branchFullName)
        let pageSize = pageSize
        let maximumCommits = maximumCommits
        return try await execute(repositoryRoot) { command in
            if let branch = query.branchFullName {
                guard try command.loadRefs().contains(where: { $0.fullName == branch }) else {
                    throw GitHistoryError.invalidArgument("branchFullName")
                }
            }
            guard try command.loadHead().sha != nil else {
                return GitHistoryPage(commits: [], hasMore: false, reachedLimit: false)
            }
            let count = max(0, min(pageSize, maximumCommits - skip))
            guard count > 0 else {
                return GitHistoryPage(commits: [], hasMore: false, reachedLimit: true)
            }
            let revisions: [String]
            if let branch = query.branchFullName {
                revisions = [branch]
            } else {
                revisions = ["--branches", "--tags", "HEAD"] + (query.includeRemotes ? ["--remotes"] : [])
            }
            let output = try command.run(
                [
                    "log", "--date-order", "--source",
                    "--format=\(GitHistoryParser.logFormat)",
                    "--skip=\(skip)", "--max-count=\(count + 1)",
                ] + revisions + ["--"],
                maximumOutputByteCount: Self.pageOutputLimit
            )
            let parsed = GitHistoryParser.commits(fromLog: output)
            let commits = Array(parsed.prefix(count))
            return GitHistoryPage(
                commits: commits,
                hasMore: parsed.count > count,
                reachedLimit: skip + commits.count >= maximumCommits
            )
        }
    }

    public func fileChanges(repositoryRoot: String, sha: String) async throws -> [GitHistoryFileChange] {
        try GitHistoryArgumentValidator.validateSHA(sha)
        return try await execute(repositoryRoot) { try $0.loadFileChanges(sha: sha) }
    }

    /// The full message of `sha` as `git log -1 --format=%B` prints it, without
    /// trailing whitespace. Invalid UTF-8 is replaced, not rejected. A message over
    /// 256 KiB throws ``GitHistoryError/outputTooLarge``.
    public func commitMessage(repositoryRoot: String, sha: String) async throws -> String {
        try GitHistoryArgumentValidator.validateSHA(sha)
        return try await execute(repositoryRoot) { command in
            let output = try command.run(
                ["log", "-1", "--no-color", "--encoding=UTF-8", "--format=%B", sha, "--"],
                maximumOutputByteCount: Self.messageOutputLimit
            )
            var message = String(decoding: output, as: UTF8.self)
            while message.last?.isWhitespace == true {
                message.removeLast()
            }
            return message
        }
    }

    public func filePatch(repositoryRoot: String, sha: String, path: String) async throws -> Data {
        try GitHistoryArgumentValidator.validateSHA(sha)
        try GitHistoryArgumentValidator.validatePath(path)
        return try await execute(repositoryRoot) { command in
            guard let change = try command.loadFileChanges(sha: sha)
                .first(where: { $0.path == path || $0.oldPath == path }) else {
                throw GitHistoryError.invalidArgument("path")
            }
            let base: String
            if let parent = try command.firstParent(of: sha) {
                base = parent
            } else {
                base = try command.emptyTree()
            }
            let pathspecs = [change.oldPath, change.path].compactMap { $0 }
            return try command.run(
                [
                    "--literal-pathspecs",
                    "diff", "--no-color", "--no-ext-diff", "--no-textconv", "-M",
                    "--src-prefix=a/", "--dst-prefix=b/",
                    base, sha, "--",
                ] + pathspecs,
                maximumOutputByteCount: Self.patchOutputLimit
            )
        }
    }

    public func workingTreeStatus(repositoryRoot: String) async throws -> GitHistoryWorkingTreeStatus {
        try await execute(repositoryRoot) { command in
            let output = try command.run(
                ["status", "--porcelain=v1", "-z", "--untracked-files=normal"],
                maximumOutputByteCount: Self.metadataOutputLimit
            )
            return GitHistoryParser.workingTreeStatus(porcelainV1Z: output)
        }
    }

    // MARK: Execution

    private func execute<T: Sendable>(
        _ repositoryRoot: String,
        _ work: @escaping @Sendable (Command) throws -> T
    ) async throws -> T {
        let command = Command(
            runner: runner,
            directory: URL(fileURLWithPath: repositoryRoot, isDirectory: true),
            deadline: DispatchTime.now() + wallTimeLimit,
            wallTimeLimit: wallTimeLimit
        )
        return try await Self.offCooperativePool {
            do {
                let toplevel = try command.runAllowingFailure(["rev-parse", "--show-toplevel"], maximumOutputByteCount: 64 * 1024)
                guard toplevel.exitCode == 0 else { throw GitHistoryError.notARepository }
                return try work(command)
            } catch let error as POSIXError {
                throw Self.map(error)
            }
        }
    }

    private static func map(_ error: POSIXError) -> GitHistoryError {
        switch error.code {
        case .ENOENT, .EACCES, .ENOEXEC, .ENOTDIR:
            return .gitUnavailable
        case .ETIMEDOUT:
            return .timedOut
        default:
            return .failed(exitCode: -1)
        }
    }

    private static func offCooperativePool<T: Sendable>(
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        let signal = WorkspaceChangesCancellationSignal()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    continuation.resume(with: Result {
                        try signal.withCurrentBinding { try work() }
                    })
                }
            }
        } onCancel: {
            signal.cancel()
        }
    }

    /// One logical operation: shares a single wall-clock budget across its git calls.
    struct Command: Sendable {
        let runner: any WorkspaceChangesGitRunning
        let directory: URL
        let deadline: DispatchTime
        let wallTimeLimit: TimeInterval

        func runAllowingFailure(
            _ arguments: [String],
            maximumOutputByteCount: Int
        ) throws -> WorkspaceChangesGitResult {
            let now = DispatchTime.now()
            guard deadline > now else { throw GitHistoryError.timedOut }
            let remaining = Double(deadline.uptimeNanoseconds - now.uptimeNanoseconds) / 1_000_000_000
            let result = try runner.run(
                arguments: GitHistoryService.commonPrefix + arguments,
                in: directory,
                maximumOutputByteCount: maximumOutputByteCount,
                wallTimeLimit: remaining
            )
            if WorkspaceChangesCancellationSignal.isCurrentCancelled { throw CancellationError() }
            if result.standardOutputWasTruncated {
                throw DispatchTime.now() >= deadline ? GitHistoryError.timedOut : GitHistoryError.outputTooLarge
            }
            return result
        }

        func run(_ arguments: [String], maximumOutputByteCount: Int) throws -> Data {
            let result = try runAllowingFailure(arguments, maximumOutputByteCount: maximumOutputByteCount)
            guard result.exitCode == 0 else { throw GitHistoryError.failed(exitCode: result.exitCode) }
            return result.output
        }

        func loadHead() throws -> GitHistoryHead {
            let commit = try runAllowingFailure(
                ["rev-parse", "-q", "--verify", "HEAD^{commit}"],
                maximumOutputByteCount: 4096
            )
            if commit.exitCode == 1 { return GitHistoryHead(sha: nil, branch: nil) }
            guard commit.exitCode == 0 else { throw GitHistoryError.failed(exitCode: commit.exitCode) }
            let sha = String(decoding: commit.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let branch = try runAllowingFailure(["symbolic-ref", "-q", "--short", "HEAD"], maximumOutputByteCount: 4096)
            if branch.exitCode == 1 { return GitHistoryHead(sha: sha, branch: nil) }
            guard branch.exitCode == 0 else { throw GitHistoryError.failed(exitCode: branch.exitCode) }
            let name = String(decoding: branch.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return GitHistoryHead(sha: sha, branch: name.isEmpty ? nil : name)
        }

        func loadRefs() throws -> [GitHistoryRef] {
            let output = try run(
                [
                    "for-each-ref", "--format=\(GitHistoryParser.refFormat)",
                    "refs/heads", "refs/remotes", "refs/tags",
                ],
                maximumOutputByteCount: GitHistoryService.metadataOutputLimit
            )
            return GitHistoryParser.refs(fromForEachRef: output)
        }

        func firstParent(of sha: String) throws -> String? {
            let output = try run(["rev-list", "--parents", "-n", "1", sha], maximumOutputByteCount: 64 * 1024)
            let fields = String(decoding: output, as: UTF8.self)
                .split(whereSeparator: { $0 == " " || $0 == "\n" })
            return fields.count > 1 ? String(fields[1]) : nil
        }

        func emptyTree() throws -> String {
            let output = try run(["hash-object", "-t", "tree", "--stdin"], maximumOutputByteCount: 4096)
            return String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func loadFileChanges(sha: String) throws -> [GitHistoryFileChange] {
            let range: [String]
            if let parent = try firstParent(of: sha) {
                range = [parent, sha]
            } else {
                range = ["--root", sha]
            }
            func diffTree(_ mode: String) throws -> Data {
                try run(
                    ["diff-tree", "-r", "-M", "--no-ext-diff", "--no-textconv", "--no-commit-id", "-z", mode]
                        + range,
                    maximumOutputByteCount: GitHistoryService.metadataOutputLimit
                )
            }
            return GitHistoryParser.fileChanges(
                nameStatusZ: try diffTree("--name-status"),
                numstatZ: try diffTree("--numstat")
            )
        }
    }
}

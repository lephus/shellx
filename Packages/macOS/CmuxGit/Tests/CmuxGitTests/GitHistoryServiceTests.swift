import Foundation
import Testing
@testable import CmuxGit

@Suite struct GitHistoryServiceTests {
    private static let identity = ["-c", "user.name=cmux-tests", "-c", "user.email=cmux-tests@example.invalid"]

    private func text(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addCommit(_ fixture: WorkspaceChangesGitRepositoryFixture, _ name: String) throws {
        try fixture.write(name, "\(name)\n")
        try fixture.git(["add", name])
        try fixture.commit(name)
    }

    @Test func pagesHistoryWithMergeAndRemoteToggle() async throws {
        let fixture = try WorkspaceChangesGitRepositoryFixture()
        try fixture.makeBaseline()
        let first = text(try fixture.git(["rev-parse", "HEAD"]))
        try fixture.git(["checkout", "-b", "feature/x"])
        try addCommit(fixture, "f1.txt")
        try addCommit(fixture, "f2.txt")
        try fixture.git(["checkout", "main"])
        try addCommit(fixture, "m1.txt")
        try fixture.git(Self.identity + ["merge", "--no-ff", "-m", "merge x", "feature/x"])
        try fixture.git(["update-ref", "refs/remotes/origin/main", first])
        try fixture.git(Self.identity + ["tag", "-a", "v1", "-m", "v1", first])

        let service = GitHistoryService()
        let page = try await service.page(
            repositoryRoot: fixture.root.path,
            query: .init(includeRemotes: true, branchFullName: nil),
            skip: 0
        )
        #expect(page.commits.first?.parents.count == 2)
        let expected = text(try fixture.git([
            "log", "--date-order", "--format=%H", "--branches", "--tags", "--remotes", "HEAD",
        ])).split(separator: "\n").map(String.init)
        #expect(page.commits.map(\.sha) == expected)
        #expect(!page.hasMore)

        let refs = try await service.refs(repositoryRoot: fixture.root.path)
        #expect(refs.contains { $0.name == "origin/main" && $0.kind == .remoteBranch })
        #expect(refs.contains { $0.name == "v1" && $0.kind == .tag && $0.target == first })
        let head = try await service.head(repositoryRoot: fixture.root.path)
        #expect(head.branch == "main")

        let branchPage = try await service.page(
            repositoryRoot: fixture.root.path,
            query: .init(includeRemotes: false, branchFullName: "refs/heads/feature/x"),
            skip: 0
        )
        #expect(branchPage.commits.count == 3)
    }

    @Test func capsAtMaximumCommitsAndReportsLimit() async throws {
        let fixture = try WorkspaceChangesGitRepositoryFixture()
        try fixture.makeBaseline()
        for index in 1...6 { try addCommit(fixture, "c\(index).txt") }
        let service = GitHistoryService(runner: SystemWorkspaceChangesGitRunner(), pageSize: 3, maximumCommits: 5)
        let query = GitHistoryQuery(includeRemotes: false, branchFullName: nil)
        let first = try await service.page(repositoryRoot: fixture.root.path, query: query, skip: 0)
        #expect(first.commits.count == 3)
        #expect(first.hasMore)
        #expect(!first.reachedLimit)
        let second = try await service.page(repositoryRoot: fixture.root.path, query: query, skip: 3)
        #expect(second.commits.count == 2)
        #expect(second.reachedLimit)
    }

    @Test func handlesEmptyDetachedShallowAndWorktreeRepos() async throws {
        let service = GitHistoryService()
        let query = GitHistoryQuery(includeRemotes: true, branchFullName: nil)

        let empty = try WorkspaceChangesGitRepositoryFixture()
        let unborn = try await service.head(repositoryRoot: empty.root.path)
        #expect(unborn.sha == nil)
        let emptyPage = try await service.page(repositoryRoot: empty.root.path, query: query, skip: 0)
        #expect(emptyPage.commits.isEmpty)

        let fixture = try WorkspaceChangesGitRepositoryFixture()
        try fixture.makeBaseline()
        try addCommit(fixture, "a.txt")
        try addCommit(fixture, "b.txt")
        try fixture.git(["checkout", "--detach"])
        let detached = try await service.head(repositoryRoot: fixture.root.path)
        #expect(detached.branch == nil)
        #expect(detached.sha != nil)

        let clone = fixture.root.deletingLastPathComponent()
            .appendingPathComponent("shallow-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: clone) }
        try fixture.git(["clone", "--depth", "2", "file://\(fixture.root.path)", clone.path])
        let shallow = try await service.page(repositoryRoot: clone.path, query: query, skip: 0)
        #expect(shallow.commits.count == 2)
        let oldest = try #require(shallow.commits.last)
        #expect(!shallow.commits.contains { oldest.parents.contains($0.sha) })

        let worktree = fixture.root.deletingLastPathComponent()
            .appendingPathComponent("wt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: worktree) }
        try fixture.git(["worktree", "add", worktree.path, "-b", "wt-branch"])
        let worktreePage = try await service.page(repositoryRoot: worktree.path, query: query, skip: 0)
        #expect(!worktreePage.commits.isEmpty)
    }

    @Test func fileChangesAndPatchForRootMergeAndRename() async throws {
        let service = GitHistoryService()
        let fixture = try WorkspaceChangesGitRepositoryFixture()
        try fixture.makeBaseline()
        let root = fixture.root.path
        let rootSHA = text(try fixture.git(["rev-parse", "HEAD"]))

        let rootChanges = try await service.fileChanges(repositoryRoot: root, sha: rootSHA)
        #expect(rootChanges.map(\.path) == ["tracked.txt"])
        #expect(rootChanges.allSatisfy { $0.status == .added })
        let rootPatch = try await service.filePatch(repositoryRoot: root, sha: rootSHA, path: "tracked.txt")
        #expect(String(decoding: rootPatch, as: UTF8.self).hasPrefix("diff --git"))

        try fixture.write("a.txt", "alpha\nbeta\ngamma\n")
        try fixture.git(["add", "a.txt"])
        try fixture.commit("add a")
        try fixture.git(["mv", "a.txt", "b.txt"])
        try fixture.commit("rename")
        let renameSHA = text(try fixture.git(["rev-parse", "HEAD"]))
        let renamed = try await service.fileChanges(repositoryRoot: root, sha: renameSHA)
        #expect(renamed.count == 1)
        #expect(renamed.first?.status == .renamed)
        #expect(renamed.first?.oldPath == "a.txt")
        #expect(renamed.first?.path == "b.txt")
        let renamePatch = try await service.filePatch(repositoryRoot: root, sha: renameSHA, path: "b.txt")
        #expect(String(decoding: renamePatch, as: UTF8.self).contains("rename from a.txt"))

        try fixture.git(["checkout", "-b", "side", "HEAD~1"])
        try addCommit(fixture, "side.txt")
        try fixture.git(["checkout", "main"])
        try fixture.git(Self.identity + ["merge", "--no-ff", "-m", "merge side", "side"])
        let mergeSHA = text(try fixture.git(["rev-parse", "HEAD"]))
        let merged = try await service.fileChanges(repositoryRoot: root, sha: mergeSHA)
        let expected = text(try fixture.git(["diff", "--name-only", "\(mergeSHA)^1", mergeSHA]))
            .split(separator: "\n").map(String.init)
        #expect(merged.map(\.path).sorted() == expected.sorted())
        #expect(expected == ["side.txt"])
    }

    @Test func patchKeepsABPrefixesDespiteNoprefixConfig() async throws {
        let service = GitHistoryService()
        let fixture = try WorkspaceChangesGitRepositoryFixture()
        try fixture.makeBaseline()
        try fixture.git(["config", "diff.noprefix", "true"])
        try fixture.write("tracked.txt", "changed\n")
        try fixture.git(["add", "tracked.txt"])
        try fixture.commit("modify tracked")
        let sha = text(try fixture.git(["rev-parse", "HEAD"]))
        let patch = try await service.filePatch(repositoryRoot: fixture.root.path, sha: sha, path: "tracked.txt")
        let body = String(decoding: patch, as: UTF8.self)
        #expect(body.hasPrefix("diff --git a/"))
        #expect(body.contains("\n--- a/tracked.txt"))
        #expect(body.contains("\n+++ b/tracked.txt"))
    }

    @Test func rejectsUntrustedArguments() async throws {
        let fixture = try WorkspaceChangesGitRepositoryFixture()
        try fixture.makeBaseline()
        let root = fixture.root.path
        let sha = text(try fixture.git(["rev-parse", "HEAD"]))
        let recorder = RecordingRunner()
        let service = GitHistoryService(runner: recorder)
        let query = GitHistoryQuery(includeRemotes: false, branchFullName: nil)

        func expectInvalid(_ operation: () async throws -> Void) async {
            do {
                try await operation()
                Issue.record("expected invalidArgument")
            } catch let error as GitHistoryError {
                guard case .invalidArgument = error else {
                    Issue.record("unexpected error \(error)")
                    return
                }
            } catch {
                Issue.record("unexpected error \(error)")
            }
        }

        // Syntactic rejections: zero git calls.
        for bad in ["HEAD", "--output=/tmp/x", String(sha.dropLast())] {
            await expectInvalid { _ = try await service.fileChanges(repositoryRoot: root, sha: bad) }
            await expectInvalid { _ = try await service.filePatch(repositoryRoot: root, sha: bad, path: "tracked.txt") }
        }
        for bad in ["--all", "heads/main", ""] {
            await expectInvalid {
                _ = try await service.page(
                    repositoryRoot: root,
                    query: .init(includeRemotes: false, branchFullName: bad),
                    skip: 0
                )
            }
        }
        for bad in [-1, 5001] {
            await expectInvalid { _ = try await service.page(repositoryRoot: root, query: query, skip: bad) }
        }
        #expect(recorder.calls.isEmpty)

        // Semantic rejections: lookup only, never the target command.
        await expectInvalid { _ = try await service.filePatch(repositoryRoot: root, sha: sha, path: "../../etc/passwd") }
        await expectInvalid {
            _ = try await service.page(
                repositoryRoot: root,
                query: .init(includeRemotes: false, branchFullName: "refs/heads/does-not-exist"),
                skip: 0
            )
        }
        let subcommands = Set(recorder.calls.compactMap { $0.dropFirst(6).first })
        #expect(subcommands.isSubset(of: ["rev-parse", "rev-list", "diff-tree", "for-each-ref"]))
        #expect(!subcommands.contains("diff"))
        #expect(!subcommands.contains("log"))
        for call in recorder.calls {
            #expect(Array(call.prefix(6)) == ["-c", "core.fsmonitor=false", "-c", "log.showSignature=false", "-c", "color.ui=false"])
        }
    }

    @Test func mapsNotARepositoryAndTimeout() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-a-repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        await #expect(throws: GitHistoryError.notARepository) {
            _ = try await GitHistoryService().head(repositoryRoot: directory.path)
        }

        let timingOut = FakeWorkspaceChangesGitRunner(results: [:]) { _, _ in throw POSIXError(.ETIMEDOUT) }
        await #expect(throws: GitHistoryError.timedOut) {
            _ = try await GitHistoryService(runner: timingOut).head(repositoryRoot: directory.path)
        }
        let missing = FakeWorkspaceChangesGitRunner(results: [:]) { _, _ in throw POSIXError(.ENOENT) }
        await #expect(throws: GitHistoryError.gitUnavailable) {
            _ = try await GitHistoryService(runner: missing).head(repositoryRoot: directory.path)
        }
    }
}

/// Delegates to the real runner while recording every argument vector.
private struct RecordingRunner: WorkspaceChangesGitRunning {
    let inner = SystemWorkspaceChangesGitRunner()
    let recorder = FakeWorkspaceChangesGitCallRecorder()
    var calls: [[String]] { recorder.calls }

    func run(arguments: [String], in directory: URL) throws -> WorkspaceChangesGitResult {
        recorder.record(arguments)
        return try inner.run(arguments: arguments, in: directory)
    }

    func run(arguments: [String], in directory: URL, maximumOutputByteCount: Int, wallTimeLimit: TimeInterval) throws -> WorkspaceChangesGitResult {
        recorder.record(arguments)
        return try inner.run(arguments: arguments, in: directory, maximumOutputByteCount: maximumOutputByteCount, wallTimeLimit: wallTimeLimit)
    }
}

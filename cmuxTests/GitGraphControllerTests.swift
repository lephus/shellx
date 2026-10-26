import AppKit
import CmuxGit
import Foundation
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class GitGraphControllerTests: XCTestCase {
    private let sha = String(repeating: "a", count: 40)

    func testRepoStateReportsReadyWithRepositoryNameAndHead() async {
        let history = FakeGitHistory()
        history.headResult = .success(GitHistoryHead(sha: "abc", branch: "develop"))
        let controller = GitGraphController(placement: .sidebar, history: history, diffOpener: nil)
        controller.showRepository(root: "/tmp/shellx", status: .ready)

        let reply = await controller.handle(method: "repo.state", params: [:])

        XCTAssertEqual(reply as NSDictionary, [
            "ok": true,
            "generation": 1,
            "result": ["status": "ready", "repositoryName": "shellx", "head": ["sha": "abc", "branch": "develop"]],
        ] as NSDictionary)
    }

    func testRepoStateReportsEmptyForUnbornHead() async {
        let history = FakeGitHistory()
        history.headResult = .success(GitHistoryHead(sha: nil, branch: "main"))
        let controller = GitGraphController(placement: .sidebar, history: history, diffOpener: nil)
        controller.showRepository(root: "/tmp/shellx", status: .ready)

        let reply = await controller.handle(method: "repo.state", params: [:])

        XCTAssertEqual(result(reply)?["status"] as? String, "empty")
    }

    func testRepoStateWithoutReadyStatusSkipsGit() async {
        let history = FakeGitHistory()
        let controller = GitGraphController(placement: .sidebar, history: history, diffOpener: nil)

        controller.showRepository(root: "/Users/me/remote-repo", status: .remote)
        let remote = await controller.handle(method: "repo.state", params: [:])
        controller.showRepository(root: nil, status: .noDirectory)
        let none = await controller.handle(method: "repo.state", params: [:])
        let refs = await controller.handle(method: "history.refs", params: [:])

        XCTAssertEqual(result(remote) as NSDictionary?, ["status": "remote", "repositoryName": "remote-repo"] as NSDictionary)
        XCTAssertEqual(result(none) as NSDictionary?, ["status": "noDirectory"] as NSDictionary)
        XCTAssertEqual(errorCode(refs), "notAllowed")
        XCTAssertEqual(history.calls, [])
    }

    func testStaleReplyAfterRepoChangeIsMarkedNotAllowedWithNewGeneration() async {
        let history = FakeGitHistory()
        history.holdsPage = true
        let controller = GitGraphController(placement: .sidebar, history: history, diffOpener: nil)
        controller.showRepository(root: "/tmp/shellx", status: .ready)

        let pending = Task { () -> ReplySummary in
            ReplySummary(await controller.handle(method: "history.page", params: ["skip": 0, "includeRemotes": true]))
        }
        await history.waitForHeldPage()
        controller.showRepository(root: "/tmp/other", status: .ready)
        history.releasePage()
        let reply = await pending.value

        XCTAssertEqual(reply, ReplySummary(ok: false, code: "notAllowed", generation: 2))
    }

    func testServiceErrorsMapToCodes() async {
        let cases: [(GitHistoryError, String)] = [
            (.notARepository, "notARepository"),
            (.gitUnavailable, "gitUnavailable"),
            (.timedOut, "timedOut"),
            (.outputTooLarge, "outputTooLarge"),
            (.invalidArgument("sha"), "invalidArgument"),
            (.failed(exitCode: 128), "failed"),
        ]
        for (error, code) in cases {
            let history = FakeGitHistory()
            history.error = error
            let controller = GitGraphController(placement: .sidebar, history: history, diffOpener: nil)
            controller.showRepository(root: "/tmp/shellx", status: .ready)

            let reply = await controller.handle(method: "history.refs", params: [:])

            XCTAssertEqual(reply["ok"] as? Bool, false, code)
            XCTAssertEqual(errorCode(reply), code)
            XCTAssertEqual(reply["generation"] as? UInt64, 1, code)
            XCTAssertFalse(((reply["error"] as? [String: Any])?["message"] as? String ?? "").isEmpty, code)
        }
    }

    func testRepositoryErrorsUpdateStatusUntilHeadReadsAgain() async {
        let history = FakeGitHistory()
        let controller = GitGraphController(placement: .sidebar, history: history, diffOpener: nil)
        controller.showRepository(root: "/tmp/shellx", status: .ready)

        history.error = .notARepository
        _ = await controller.handle(method: "history.refs", params: [:])
        XCTAssertEqual(controller.status, .notRepository)
        history.error = .gitUnavailable
        _ = await controller.handle(method: "repo.state", params: [:])
        XCTAssertEqual(controller.status, .gitUnavailable)

        history.error = nil
        let retry = await controller.handle(method: "repo.state", params: [:])
        XCTAssertEqual(result(retry)?["status"] as? String, "ready")
        XCTAssertEqual(controller.status, .ready)
    }

    func testNilOptionalsAreSentAsJSONNull() async throws {
        let history = FakeGitHistory()
        history.headResult = .success(GitHistoryHead(sha: sha, branch: nil))
        history.fileChangesResult = .success([
            GitHistoryFileChange(path: "logo.png", oldPath: nil, status: .added, additions: nil, deletions: nil),
        ])
        let controller = GitGraphController(placement: .sidebar, history: history, diffOpener: nil)
        controller.showRepository(root: "/tmp/shellx", status: .ready)

        let state = await controller.handle(method: "repo.state", params: [:])
        let files = await controller.handle(method: "history.files", params: ["sha": sha])

        let head = try XCTUnwrap(result(state)?["head"] as? [String: Any])
        XCTAssertEqual(head["sha"] as? String, sha)
        XCTAssertTrue(head["branch"] is NSNull, "head.branch must be null, got \(String(describing: head["branch"]))")
        let change = try XCTUnwrap((files["result"] as? [Any])?.first as? [String: Any])
        XCTAssertEqual(change["path"] as? String, "logo.png")
        XCTAssertEqual(change["status"] as? String, "added")
        XCTAssertTrue(change["oldPath"] is NSNull, "oldPath must be null, got \(String(describing: change["oldPath"]))")
        XCTAssertTrue(change["additions"] is NSNull, "additions must be null, got \(String(describing: change["additions"]))")
        XCTAssertTrue(change["deletions"] is NSNull, "deletions must be null, got \(String(describing: change["deletions"]))")
    }

    func testHistoryPageMapsParamsToQueryAndEncodesPage() async throws {
        let history = FakeGitHistory()
        let commit = GitHistoryCommit(
            sha: sha, parents: [], source: "main", authorName: "Ada", authorEmail: "ada@example.com",
            authorDate: "2026-10-26T10:00:00+07:00", committerDate: "2026-10-26T10:00:00+07:00", subject: "Initial"
        )
        history.pageResult = .success(GitHistoryPage(commits: [commit], hasMore: true, reachedLimit: false))
        let controller = GitGraphController(placement: .tab, history: history, diffOpener: nil)
        controller.showRepository(root: "/tmp/shellx", status: .ready)

        let reply = await controller.handle(
            method: "history.page",
            params: ["skip": 300, "includeRemotes": false, "branch": "refs/heads/main"]
        )
        let invalid = await controller.handle(method: "history.page", params: ["skip": "0", "includeRemotes": true])

        XCTAssertEqual(history.pageRequests.count, 1)
        XCTAssertEqual(history.pageRequests.first?.root, "/tmp/shellx")
        XCTAssertEqual(history.pageRequests.first?.query, GitHistoryQuery(includeRemotes: false, branchFullName: "refs/heads/main"))
        XCTAssertEqual(history.pageRequests.first?.skip, 300)
        let page = try XCTUnwrap(result(reply))
        XCTAssertEqual(page["hasMore"] as? Bool, true)
        XCTAssertEqual(page["reachedLimit"] as? Bool, false)
        let first = try XCTUnwrap((page["commits"] as? [Any])?.first as? [String: Any])
        XCTAssertEqual(first["sha"] as? String, sha)
        XCTAssertEqual(first["subject"] as? String, "Initial")
        XCTAssertEqual(errorCode(invalid), "invalidArgument")
    }

    func testOpenFileDiffFetchesPatchAndCallsOpener() async {
        let history = FakeGitHistory()
        history.patchResult = .success(Data("diff --git a/App.swift b/App.swift\n".utf8))
        let opener = FakeDiffOpener()
        let controller = GitGraphController(placement: .sidebar, history: history, diffOpener: opener)
        controller.showRepository(root: "/tmp/shellx", status: .ready)

        let reply = await controller.handle(method: "history.openFileDiff", params: ["sha": sha, "path": "Sources/App.swift"])

        XCTAssertEqual(history.patchRequests.map(\.sha), [sha])
        XCTAssertEqual(history.patchRequests.map(\.path), ["Sources/App.swift"])
        XCTAssertEqual(opener.commitFileDiffs.count, 1)
        XCTAssertEqual(opener.commitFileDiffs.first?.repositoryRoot, "/tmp/shellx")
        XCTAssertEqual(opener.commitFileDiffs.first?.sha, sha)
        XCTAssertEqual(opener.commitFileDiffs.first?.path, "Sources/App.swift")
        XCTAssertEqual(opener.commitFileDiffs.first?.patch, Data("diff --git a/App.swift b/App.swift\n".utf8))
        XCTAssertEqual(reply as NSDictionary, ["ok": true, "generation": 1, "result": ["opened": true]] as NSDictionary)
    }

    func testHistoryMessageReturnsTheFullMessage() async {
        let history = FakeGitHistory()
        let message = "Fix <b>bold</b> parsing\n\nThe body keeps\n  its line breaks.\n"
        history.messageResult = .success(message)
        let controller = GitGraphController(placement: .sidebar, history: history, diffOpener: nil)
        controller.showRepository(root: "/tmp/shellx", status: .ready)

        let reply = await controller.handle(method: "history.message", params: ["sha": sha])
        let missing = await controller.handle(method: "history.message", params: [:])

        XCTAssertEqual(reply as NSDictionary, ["ok": true, "generation": 1, "result": ["message": message]] as NSDictionary)
        XCTAssertEqual(history.messageRequests.map(\.root), ["/tmp/shellx"])
        XCTAssertEqual(history.messageRequests.map(\.sha), [sha])
        XCTAssertEqual(errorCode(missing), "invalidArgument")
        XCTAssertEqual(history.messageRequests.count, 1, "a request without a sha never reaches git")
    }

    func testHistoryMessageMapsErrorsAndDropsStaleReplies() async {
        let history = FakeGitHistory()
        history.messageResult = .failure(.outputTooLarge)
        let controller = GitGraphController(placement: .sidebar, history: history, diffOpener: nil)
        controller.showRepository(root: "/tmp/shellx", status: .ready)
        let tooLarge = await controller.handle(method: "history.message", params: ["sha": sha])
        XCTAssertEqual(errorCode(tooLarge), "outputTooLarge")

        history.messageResult = .success("Subject")
        history.holdsMessage = true
        let pending = Task { () -> ReplySummary in
            ReplySummary(await controller.handle(method: "history.message", params: ["sha": self.sha]))
        }
        await history.waitForHeldMessage()
        controller.showRepository(root: "/tmp/other", status: .ready)
        history.releaseMessage()
        let stale = await pending.value
        XCTAssertEqual(stale, ReplySummary(ok: false, code: "notAllowed", generation: 2))

        controller.showRepository(root: nil, status: .noDirectory)
        let noRepository = await controller.handle(method: "history.message", params: ["sha": sha])
        XCTAssertEqual(errorCode(noRepository), "notAllowed")
    }

    func testOpenWorkingTreeDiffCallsOpenerWithRepositoryRoot() async {
        let opener = FakeDiffOpener()
        let controller = GitGraphController(placement: .sidebar, history: FakeGitHistory(), diffOpener: opener)
        controller.showRepository(root: "/tmp/shellx", status: .ready)

        let reply = await controller.handle(method: "history.openWorkingTreeDiff", params: [:])

        XCTAssertEqual(opener.workingTreeDiffs, ["/tmp/shellx"])
        XCTAssertEqual(result(reply) as NSDictionary?, ["opened": true] as NSDictionary)
    }

    func testOpenAsTabForwardsRepositoryRoot() async {
        let controller = GitGraphController(placement: .sidebar, history: FakeGitHistory(), diffOpener: nil)
        var requestedRoots: [String?] = []
        controller.onOpenAsTab = { requestedRoots.append($0) }
        controller.showRepository(root: "/tmp/shellx", status: .ready)

        let reply = await controller.handle(method: "history.openAsTab", params: [:])

        XCTAssertEqual(requestedRoots, ["/tmp/shellx"])
        XCTAssertEqual(reply["ok"] as? Bool, true)
        XCTAssertEqual(reply["generation"] as? UInt64, 1)
    }

    func testAppContextReportsLabelsPlacementAndAppearance() async throws {
        let controller = GitGraphController(placement: .tab, history: FakeGitHistory(), diffOpener: nil)
        controller.effectiveAppearance = { NSAppearance(named: .darkAqua)! }
        let dark = await controller.handle(method: "app.context", params: [:])
        controller.effectiveAppearance = { NSAppearance(named: .aqua)! }
        let light = await controller.handle(method: "app.context", params: [:])

        let context = try XCTUnwrap(result(dark))
        XCTAssertEqual(context["placement"] as? String, "tab")
        XCTAssertEqual(context["appearance"] as? String, "dark")
        XCTAssertEqual(context["labels"] as? [String: String], GitGraphLabels.localized())
        XCTAssertEqual(result(light)?["appearance"] as? String, "light")
    }

    func testEventsCarryGeneration() {
        let controller = GitGraphController(placement: .sidebar, history: FakeGitHistory(), diffOpener: nil)
        var events: [NSDictionary] = []
        controller.eventSink = { events.append($0 as NSDictionary) }

        controller.showRepository(root: "/tmp/shellx", status: .ready)
        controller.notifyInvalidated()

        XCTAssertEqual(events, [
            ["type": "repo.changed", "generation": 1],
            ["type": "history.invalidated", "generation": 1],
        ])
        XCTAssertEqual(controller.generation, 1)
        XCTAssertEqual(controller.repositoryRoot, "/tmp/shellx")
        XCTAssertEqual(controller.status, .ready)
    }

    func testLabelsCoverEveryWebKey() throws {
        let repoRoot = SwiftTestingAssertions.sourceURL()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent("webviews/src/git-graph/labels.ts"),
            encoding: .utf8
        )
        let block = try XCTUnwrap(
            source.components(separatedBy: "DEFAULT_GIT_GRAPH_LABELS = {").dropFirst().first?
                .components(separatedBy: "} as const").first
        )
        let entry = try NSRegularExpression(pattern: #"^\s*(\w+):\s*"(.*)",\s*$"#, options: .anchorsMatchLines)
        var webLabels: [String: String] = [:]
        for match in entry.matches(in: block, range: NSRange(block.startIndex..., in: block)) {
            let key = String(block[Range(match.range(at: 1), in: block)!])
            webLabels[key] = String(block[Range(match.range(at: 2), in: block)!])
        }
        XCTAssertGreaterThan(webLabels.count, 20)

        let labels = GitGraphLabels.localized()
        XCTAssertEqual(Set(labels.keys), Set(webLabels.keys))

        let catalogData = try Data(contentsOf: repoRoot.appendingPathComponent("Resources/Localizable.xcstrings"))
        let catalog = try XCTUnwrap(
            (try JSONSerialization.jsonObject(with: catalogData) as? [String: Any])?["strings"] as? [String: Any]
        )
        let locales = ["en", "de", "fr", "ar", "es", "zh-Hant", "zh-Hans", "ko", "ja", "vi"]
        for (key, english) in webLabels {
            XCTAssertEqual(placeholders(in: labels[key] ?? ""), placeholders(in: english), key)
            let localizations = (catalog["gitGraph.label.\(key)"] as? [String: Any])?["localizations"] as? [String: Any]
            XCTAssertNotNil(localizations, "gitGraph.label.\(key) is missing from Localizable.xcstrings")
            for locale in locales {
                let unit = (localizations?[locale] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String
                XCTAssertNotNil(value, "gitGraph.label.\(key) has no \(locale) value")
                XCTAssertEqual(placeholders(in: value ?? ""), placeholders(in: english), "gitGraph.label.\(key) [\(locale)]")
            }
            let englishValue = ((localizations?["en"] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
            XCTAssertEqual(englishValue, english, "gitGraph.label.\(key) English copy differs from labels.ts")
        }
    }

    func testShellDocumentCheckAllowsOnlyThePageAndItsFragments() throws {
        let shell = GitGraphURLSchemeHandler.shellURL
        let isShell = GitGraphURLSchemeHandler.isShellDocument

        XCTAssertEqual(shell.absoluteString, "shellx-git-graph://app/git-graph.html")
        XCTAssertTrue(isShell(shell))
        XCTAssertTrue(isShell(URL(string: "shellx-git-graph://app/git-graph.html#commit")))
        XCTAssertTrue(isShell(URL(string: "shellx-git-graph://app/git-graph.html#")))
        XCTAssertFalse(isShell(URL(string: "shellx-git-graph://app/agent-session.html")))
        XCTAssertFalse(isShell(URL(string: "shellx-git-graph://app/main.mjs")))
        XCTAssertFalse(isShell(URL(string: "shellx-git-graph://app/chunks/../git-graph.html")))
        XCTAssertFalse(isShell(URL(string: "shellx-git-graph://app/git-graph.html?x=1")))
        XCTAssertFalse(isShell(URL(string: "shellx-git-graph://other/git-graph.html")))
        XCTAssertFalse(isShell(URL(string: "shellx-git-graph://app:8080/git-graph.html")))
        XCTAssertFalse(isShell(URL(string: "shellx-git-graph://user@app/git-graph.html")))
        XCTAssertFalse(isShell(URL(string: "https://app/git-graph.html")))
        XCTAssertFalse(isShell(URL(fileURLWithPath: "/tmp/shellx-bundle/markdown-viewer/webviews-app/git-graph.html")))
        XCTAssertFalse(isShell(nil))
    }

    // MARK: Helpers

    private func result(_ reply: [String: Any]) -> [String: Any]? {
        reply["result"] as? [String: Any]
    }

    private func errorCode(_ reply: [String: Any]) -> String? {
        (reply["error"] as? [String: Any])?["code"] as? String
    }

    private func placeholders(in text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: #"\{\w+\}"#)
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .map { String(text[Range($0.range, in: text)!]) }
            .sorted()
    }
}

/// The parts of a bridge reply the stale-reply test compares, in a `Sendable` form.
private struct ReplySummary: Equatable, Sendable {
    var ok: Bool?
    var code: String?
    var generation: UInt64?

    init(ok: Bool?, code: String?, generation: UInt64?) {
        self.ok = ok
        self.code = code
        self.generation = generation
    }

    init(_ reply: [String: Any]) {
        ok = reply["ok"] as? Bool
        code = (reply["error"] as? [String: Any])?["code"] as? String
        generation = reply["generation"] as? UInt64
    }
}

@MainActor
private final class FakeGitHistory: GitGraphHistoryProviding {
    var headResult: Result<GitHistoryHead, GitHistoryError> = .success(GitHistoryHead(sha: "abc", branch: "develop"))
    var refsResult: Result<[GitHistoryRef], GitHistoryError> = .success([])
    var pageResult: Result<GitHistoryPage, GitHistoryError> = .success(
        GitHistoryPage(commits: [], hasMore: false, reachedLimit: false)
    )
    var fileChangesResult: Result<[GitHistoryFileChange], GitHistoryError> = .success([])
    var messageResult: Result<String, GitHistoryError> = .success("")
    var patchResult: Result<Data, GitHistoryError> = .success(Data())
    var workingTreeResult: Result<GitHistoryWorkingTreeStatus, GitHistoryError> = .success(
        GitHistoryWorkingTreeStatus(added: 0, modified: 0, deleted: 0)
    )
    /// Thrown by every method when set, instead of its result.
    var error: GitHistoryError?
    /// When true, `page` suspends until `releasePage()`.
    var holdsPage = false
    /// When true, `commitMessage` suspends until `releaseMessage()`.
    var holdsMessage = false

    private(set) var calls: [String] = []
    private(set) var pageRequests: [(root: String, query: GitHistoryQuery, skip: Int)] = []
    private(set) var patchRequests: [(root: String, sha: String, path: String)] = []
    private(set) var messageRequests: [(root: String, sha: String)] = []
    private var heldPage: CheckedContinuation<Void, Never>?
    private var pageWaiter: CheckedContinuation<Void, Never>?
    private var heldMessage: CheckedContinuation<Void, Never>?
    private var messageWaiter: CheckedContinuation<Void, Never>?

    func waitForHeldMessage() async {
        guard heldMessage == nil else { return }
        await withCheckedContinuation { messageWaiter = $0 }
    }

    func releaseMessage() {
        heldMessage?.resume()
        heldMessage = nil
    }

    func commitMessage(repositoryRoot: String, sha: String) async throws -> String {
        messageRequests.append((repositoryRoot, sha))
        if holdsMessage {
            await withCheckedContinuation { continuation in
                heldMessage = continuation
                messageWaiter?.resume()
                messageWaiter = nil
            }
        }
        return try record("commitMessage", messageResult)
    }

    func waitForHeldPage() async {
        guard heldPage == nil else { return }
        await withCheckedContinuation { pageWaiter = $0 }
    }

    func releasePage() {
        heldPage?.resume()
        heldPage = nil
    }

    func head(repositoryRoot: String) async throws -> GitHistoryHead {
        try record("head", headResult)
    }

    func refs(repositoryRoot: String) async throws -> [GitHistoryRef] {
        try record("refs", refsResult)
    }

    func page(repositoryRoot: String, query: GitHistoryQuery, skip: Int) async throws -> GitHistoryPage {
        pageRequests.append((repositoryRoot, query, skip))
        if holdsPage {
            await withCheckedContinuation { continuation in
                heldPage = continuation
                pageWaiter?.resume()
                pageWaiter = nil
            }
        }
        return try record("page", pageResult)
    }

    func fileChanges(repositoryRoot: String, sha: String) async throws -> [GitHistoryFileChange] {
        try record("fileChanges", fileChangesResult)
    }

    func filePatch(repositoryRoot: String, sha: String, path: String) async throws -> Data {
        patchRequests.append((repositoryRoot, sha, path))
        return try record("filePatch", patchResult)
    }

    func workingTreeStatus(repositoryRoot: String) async throws -> GitHistoryWorkingTreeStatus {
        try record("workingTreeStatus", workingTreeResult)
    }

    private func record<T>(_ call: String, _ result: Result<T, GitHistoryError>) throws -> T {
        calls.append(call)
        if let error { throw error }
        return try result.get()
    }
}

@MainActor
private final class FakeDiffOpener: GitGraphDiffOpening {
    private(set) var commitFileDiffs: [(repositoryRoot: String, sha: String, path: String, patch: Data)] = []
    private(set) var workingTreeDiffs: [String] = []

    func openCommitFileDiff(repositoryRoot: String, sha: String, path: String, patch: Data) -> Bool {
        commitFileDiffs.append((repositoryRoot, sha, path, patch))
        return true
    }

    func openWorkingTreeDiff(repositoryRoot: String) -> Bool {
        workingTreeDiffs.append(repositoryRoot)
        return true
    }
}

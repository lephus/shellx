import AppKit
import CmuxGit
import Foundation

/// Reads history for the Git Graph page. It mirrors ``GitHistoryService`` so tests
/// can substitute a fake; ``GitHistoryServiceProvider`` is the app's implementation.
@MainActor
protocol GitGraphHistoryProviding: AnyObject {
    func head(repositoryRoot: String) async throws -> GitHistoryHead
    func refs(repositoryRoot: String) async throws -> [GitHistoryRef]
    func page(repositoryRoot: String, query: GitHistoryQuery, skip: Int) async throws -> GitHistoryPage
    func fileChanges(repositoryRoot: String, sha: String) async throws -> [GitHistoryFileChange]
    func commitMessage(repositoryRoot: String, sha: String) async throws -> String
    func filePatch(repositoryRoot: String, sha: String, path: String) async throws -> Data
    func workingTreeStatus(repositoryRoot: String) async throws -> GitHistoryWorkingTreeStatus
}

/// Forwards to ``GitHistoryService``, which runs git off the main actor.
@MainActor
final class GitHistoryServiceProvider: GitGraphHistoryProviding {
    private let service: GitHistoryService

    nonisolated init(service: GitHistoryService = GitHistoryService()) {
        self.service = service
    }

    func head(repositoryRoot: String) async throws -> GitHistoryHead {
        try await service.head(repositoryRoot: repositoryRoot)
    }

    func refs(repositoryRoot: String) async throws -> [GitHistoryRef] {
        try await service.refs(repositoryRoot: repositoryRoot)
    }

    func page(repositoryRoot: String, query: GitHistoryQuery, skip: Int) async throws -> GitHistoryPage {
        try await service.page(repositoryRoot: repositoryRoot, query: query, skip: skip)
    }

    func fileChanges(repositoryRoot: String, sha: String) async throws -> [GitHistoryFileChange] {
        try await service.fileChanges(repositoryRoot: repositoryRoot, sha: sha)
    }

    func commitMessage(repositoryRoot: String, sha: String) async throws -> String {
        try await service.commitMessage(repositoryRoot: repositoryRoot, sha: sha)
    }

    func filePatch(repositoryRoot: String, sha: String, path: String) async throws -> Data {
        try await service.filePatch(repositoryRoot: repositoryRoot, sha: sha, path: path)
    }

    func workingTreeStatus(repositoryRoot: String) async throws -> GitHistoryWorkingTreeStatus {
        try await service.workingTreeStatus(repositoryRoot: repositoryRoot)
    }
}

/// Opens the diffs the Git Graph page asks for. Each call returns whether a diff opened.
@MainActor
protocol GitGraphDiffOpening: AnyObject {
    func openCommitFileDiff(repositoryRoot: String, sha: String, path: String, patch: Data) -> Bool
    func openWorkingTreeDiff(repositoryRoot: String) -> Bool
}

/// Answers the Git Graph page's bridge requests for one placement, and tells the
/// page when the repository it shows changes.
///
/// ``generation`` counts repository changes. Every reply and event carries it. A
/// request whose repository changed while it ran is answered `notAllowed` with the
/// new generation, so the page drops it.
@MainActor
final class GitGraphController: ObservableObject {
    let placement: GitGraphPlacement
    /// Settable because the sidebar controller exists before a workspace is chosen.
    var diffOpener: (any GitGraphDiffOpening)?
    @Published private(set) var repositoryRoot: String?
    /// The status passed to ``showRepository(root:status:)``. A history request that
    /// fails because the folder is no longer a repository, or because git cannot run,
    /// changes it to `.notRepository` or `.gitUnavailable` until `repo.state` reads HEAD again.
    @Published private(set) var status: GitGraphRepoStatus = .loading
    private(set) var generation: UInt64 = 0
    /// ``repositoryRoot`` while it is a repository, else nil, so a tab opened from
    /// this controller never pins a folder that is not one.
    var readyRepositoryRoot: String? {
        status == .ready ? repositoryRoot : nil
    }
    /// Delivers `repo.changed` and `history.invalidated` to the page.
    var eventSink: ((_ event: [String: Any]) -> Void)?
    /// Called for `history.openAsTab`.
    var onOpenAsTab: ((_ repositoryRoot: String?) -> Void)?
    /// Called by `repo.state` while the shown status is `.lookupFailed`, so the
    /// page's Retry walks the folder again. ``GitGraphRepositoryTracker`` sets it.
    var onRetryLookup: (() -> Void)?
    /// The appearance `app.context` reports. ``GitGraphWebView`` points it at its web view.
    var effectiveAppearance: @MainActor () -> NSAppearance = { NSApplication.shared.effectiveAppearance }
    /// Resolves the target this controller shows and watches its files. It holds the
    /// controller weakly.
    private(set) lazy var tracker = GitGraphRepositoryTracker(controller: self)

    private let history: any GitGraphHistoryProviding
    /// The status the caller last passed to ``showRepository(root:status:)``.
    private var shownStatus: GitGraphRepoStatus = .loading

    init(
        placement: GitGraphPlacement,
        history: any GitGraphHistoryProviding = GitHistoryServiceProvider(),
        diffOpener: (any GitGraphDiffOpening)?
    ) {
        self.placement = placement
        self.history = history
        self.diffOpener = diffOpener
    }

    /// Shows `root` with `status`, bumps ``generation`` and emits `repo.changed`.
    ///
    /// `root` is used as given; this method does not resolve it. Pass the work tree's
    /// top level, because `filePatch` run from a subdirectory returns an empty patch.
    /// `root` must be non-nil when `status` is `.ready`.
    func showRepository(root: String?, status: GitGraphRepoStatus) {
        repositoryRoot = root
        shownStatus = status
        self.status = status
        generation += 1
        emit(.repoChanged)
    }

    /// Tells the page to reload the current repository's history.
    func notifyInvalidated() {
        emit(.historyInvalidated)
    }

    /// Answers one bridge request. The returned dictionary is the reply for the page.
    func handle(method: String, params: [String: Any]) async -> [String: Any] {
        let requestGeneration = generation
        do {
            let result = try await perform(method, params: params, generation: requestGeneration)
            guard generation == requestGeneration else { return staleReply() }
            return ["ok": true, "result": result, "generation": generation]
        } catch {
            guard generation == requestGeneration else { return staleReply() }
            if let error = error as? GitHistoryError {
                noteRepositoryError(error)
            }
            let failure = BridgeFailure(error)
            return errorReply(code: failure.code, message: failure.message)
        }
    }

    /// A failed reply at the current generation.
    func errorReply(code: GitGraphBridgeContract.ErrorCode, message: String) -> [String: Any] {
        ["ok": false, "error": ["code": code.rawValue, "message": message], "generation": generation]
    }

    // MARK: Requests

    private func perform(
        _ name: String,
        params: [String: Any],
        generation requestGeneration: UInt64
    ) async throws -> Any {
        guard let method = GitGraphBridgeContract.Method(rawValue: name) else {
            throw BridgeFailure(code: .invalidArgument, message: "Unknown method: \(name).")
        }
        switch method {
        case .appContext:
            return appContext()
        case .repoState:
            return try await repoState(generation: requestGeneration)
        case .historyRefs:
            let root = try readyRoot()
            return try GitGraphBridgeJSON.object(await history.refs(repositoryRoot: root))
        case .historyPage:
            let root = try readyRoot()
            guard let skip = params["skip"] as? Int else { throw BridgeFailure.invalidParameter("skip") }
            guard let includeRemotes = params["includeRemotes"] as? Bool else {
                throw BridgeFailure.invalidParameter("includeRemotes")
            }
            let query = GitHistoryQuery(includeRemotes: includeRemotes, branchFullName: try optionalString(params, "branch"))
            return try GitGraphBridgeJSON.object(await history.page(repositoryRoot: root, query: query, skip: skip))
        case .historyFiles:
            let root = try readyRoot()
            let sha = try string(params, "sha")
            return try GitGraphBridgeJSON.object(
                await history.fileChanges(repositoryRoot: root, sha: sha),
                nullableKeys: ["oldPath", "additions", "deletions"]
            )
        case .historyMessage:
            let root = try readyRoot()
            let sha = try string(params, "sha")
            let message = try await history.commitMessage(repositoryRoot: root, sha: sha)
            return ["message": message]
        case .historyWorkingTree:
            let root = try readyRoot()
            return try GitGraphBridgeJSON.object(await history.workingTreeStatus(repositoryRoot: root))
        case .historyOpenFileDiff:
            let root = try readyRoot()
            let sha = try string(params, "sha")
            let path = try string(params, "path")
            guard diffOpener != nil else { return ["opened": false] }
            let patch = try await history.filePatch(repositoryRoot: root, sha: sha, path: path)
            // Open nothing for a repository the page no longer shows.
            guard generation == requestGeneration, let diffOpener else { return ["opened": false] }
            return ["opened": diffOpener.openCommitFileDiff(repositoryRoot: root, sha: sha, path: path, patch: patch)]
        case .historyOpenWorkingTreeDiff:
            let root = try readyRoot()
            return ["opened": diffOpener?.openWorkingTreeDiff(repositoryRoot: root) ?? false]
        case .historyOpenAsTab:
            guard let onOpenAsTab else { return ["opened": false] }
            onOpenAsTab(readyRepositoryRoot)
            return ["opened": true]
        }
    }

    private func appContext() -> [String: Any] {
        let isDark = effectiveAppearance().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return [
            "labels": GitGraphLabels.localized(),
            "placement": placement.rawValue,
            "appearance": isDark ? "dark" : "light",
        ]
    }

    /// `{status, repositoryName, head}`. HEAD is read only while the shown status is
    /// `.ready`; an unborn HEAD (no sha) reports `empty`. While the last folder check
    /// failed, it walks the folder again and answers `timedOut`; a walk that finds
    /// the folder emits `repo.changed`.
    private func repoState(generation requestGeneration: UInt64) async throws -> [String: Any] {
        if shownStatus == .lookupFailed {
            onRetryLookup?()
            throw BridgeFailure(code: .timedOut, message: "The folder check did not finish.")
        }
        var state: [String: Any] = [:]
        if let root = repositoryRoot {
            // Not `URL(fileURLWithPath:)`, which stats the path on the main actor.
            state["repositoryName"] = (root as NSString).lastPathComponent
        }
        guard shownStatus == .ready, let root = repositoryRoot else {
            state["status"] = shownStatus.rawValue
            return state
        }
        let head = try await history.head(repositoryRoot: root)
        if generation == requestGeneration {
            status = shownStatus
        }
        state["status"] = (head.sha == nil ? GitGraphRepoStatus.empty : .ready).rawValue
        state["head"] = try GitGraphBridgeJSON.object(head, nullableKeys: ["sha", "branch"])
        return state
    }

    /// The root history requests read, or `notAllowed` while no local repository is shown.
    private func readyRoot() throws -> String {
        guard shownStatus == .ready, let root = repositoryRoot else {
            throw BridgeFailure(code: .notAllowed, message: "No local repository is shown.")
        }
        return root
    }

    private func noteRepositoryError(_ error: GitHistoryError) {
        switch error {
        case .notARepository:
            status = .notRepository
        case .gitUnavailable:
            status = .gitUnavailable
        case .timedOut, .outputTooLarge, .invalidArgument, .failed:
            break
        }
    }

    private func staleReply() -> [String: Any] {
        errorReply(code: .notAllowed, message: "The repository changed while the request ran.")
    }

    private func emit(_ event: GitGraphBridgeContract.Event) {
        eventSink?(["type": event.rawValue, "generation": generation])
    }

    // MARK: Parameters (untrusted page input)

    private func string(_ params: [String: Any], _ name: String) throws -> String {
        guard let value = params[name] as? String else { throw BridgeFailure.invalidParameter(name) }
        return value
    }

    /// A missing or `null` parameter is nil.
    private func optionalString(_ params: [String: Any], _ name: String) throws -> String? {
        guard let value = params[name], !(value is NSNull) else { return nil }
        guard let string = value as? String else { throw BridgeFailure.invalidParameter(name) }
        return string
    }
}

/// A failed request: its wire code and a short English diagnostic. The page shows
/// its own localized copy for the code, so `message` is not user-facing.
private struct BridgeFailure: Error {
    let code: GitGraphBridgeContract.ErrorCode
    let message: String

    init(code: GitGraphBridgeContract.ErrorCode, message: String) {
        self.code = code
        self.message = message
    }

    init(_ error: any Error) {
        if let failure = error as? BridgeFailure {
            self = failure
            return
        }
        guard let error = error as? GitHistoryError else {
            self.init(code: .failed, message: "Unexpected error: \(error.localizedDescription)")
            return
        }
        switch error {
        case .notARepository:
            self.init(code: .notARepository, message: "The folder is not a Git repository.")
        case .gitUnavailable:
            self.init(code: .gitUnavailable, message: "Git could not be run.")
        case .timedOut:
            self.init(code: .timedOut, message: "Git did not finish in time.")
        case .outputTooLarge:
            self.init(code: .outputTooLarge, message: "Git output exceeded the size limit.")
        case let .invalidArgument(name):
            self.init(code: .invalidArgument, message: "Invalid argument: \(name).")
        case let .failed(exitCode):
            self.init(code: .failed, message: "Git exited with status \(exitCode).")
        }
    }

    static func invalidParameter(_ name: String) -> BridgeFailure {
        BridgeFailure(code: .invalidArgument, message: "Missing or invalid parameter: \(name).")
    }
}

/// Turns history models into the Foundation objects a bridge reply carries.
private enum GitGraphBridgeJSON {
    /// `JSONEncoder` leaves out nil optionals, but `types.ts` declares them `T | null`.
    /// Each of `nullableKeys` missing from an encoded object (or from each object of
    /// an encoded array) is added as `NSNull`, which reaches the page as `null`.
    static func object<T: Encodable>(_ value: T, nullableKeys: Set<String> = []) throws -> Any {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
        guard !nullableKeys.isEmpty else { return object }
        if let objects = object as? [Any] {
            return objects.map { addingNulls(to: $0, keys: nullableKeys) }
        }
        return addingNulls(to: object, keys: nullableKeys)
    }

    private static func addingNulls(to object: Any, keys: Set<String>) -> Any {
        guard var dictionary = object as? [String: Any] else { return object }
        for key in keys where dictionary[key] == nil {
            dictionary[key] = NSNull()
        }
        return dictionary
    }
}

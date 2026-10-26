import Foundation

/// Wire names shared with the page side of the Git Graph bridge
/// (`webviews/src/git-graph/bridge.ts` and `types.ts`).
///
/// The page posts `{method, params}` to the `shellxGitGraph` handler and gets back
/// `{ok: true, result, generation}` or `{ok: false, error: {code, message}, generation}`.
/// The host pushes events by calling `window.shellxGitGraph.receive({type, generation})`.
enum GitGraphBridgeContract {
    static let handlerName = "shellxGitGraph"

    /// `GitGraphMethod` in `types.ts`.
    enum Method: String {
        case appContext = "app.context"
        case repoState = "repo.state"
        case historyRefs = "history.refs"
        case historyPage = "history.page"
        case historyFiles = "history.files"
        case historyMessage = "history.message"
        case historyWorkingTree = "history.workingTree"
        case historyOpenFileDiff = "history.openFileDiff"
        case historyOpenWorkingTreeDiff = "history.openWorkingTreeDiff"
        case historyOpenAsTab = "history.openAsTab"
    }

    /// `GitGraphEvent.type` in `types.ts`.
    enum Event: String {
        case repoChanged = "repo.changed"
        case historyInvalidated = "history.invalidated"
    }

    /// `error.code` of a failed reply. `notAllowed` marks a request from an untrusted
    /// frame, one made while no local repository is shown, or one whose repository
    /// changed while it ran (the page drops that reply).
    enum ErrorCode: String {
        case notARepository
        case gitUnavailable
        case timedOut
        case outputTooLarge
        case invalidArgument
        case failed
        case notAllowed
    }
}

/// Where a Git Graph page is shown; sent as `app.context.placement`.
enum GitGraphPlacement: String {
    case sidebar
    case tab
}

/// What the page should show for the current target; sent as `repo.state.status`.
enum GitGraphRepoStatus: String {
    case loading
    case ready
    case notRepository
    case remote
    case noDirectory
    case gitUnavailable
    case empty
}

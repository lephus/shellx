import Foundation

/// Localized copy for the Git Graph page, sent in `app.context.labels`.
///
/// The keys are those of `DEFAULT_GIT_GRAPH_LABELS` in `webviews/src/git-graph/labels.ts`
/// (catalog keys `gitGraph.label.<key>`). The page fills `{current}`, `{total}` and
/// `{count}` itself, so those placeholders stay literal in every translation.
enum GitGraphLabels {
    static func localized() -> [String: String] {
        [
            "allBranches": String(localized: "gitGraph.label.allBranches", defaultValue: "All branches"),
            "showRemotes": String(localized: "gitGraph.label.showRemotes", defaultValue: "Remote branches"),
            "searchPlaceholder": String(
                localized: "gitGraph.label.searchPlaceholder",
                defaultValue: "Search message, hash or author"
            ),
            "searchCount": String(localized: "gitGraph.label.searchCount", defaultValue: "{current}/{total}"),
            "searchNoResults": String(
                localized: "gitGraph.label.searchNoResults",
                defaultValue: "No results in the loaded commits"
            ),
            "refresh": String(localized: "gitGraph.label.refresh", defaultValue: "Refresh"),
            "openAsTab": String(localized: "gitGraph.label.openAsTab", defaultValue: "Open as tab"),
            "columnGraph": String(localized: "gitGraph.label.columnGraph", defaultValue: "Graph"),
            "columnDescription": String(localized: "gitGraph.label.columnDescription", defaultValue: "Description"),
            "columnDate": String(localized: "gitGraph.label.columnDate", defaultValue: "Date"),
            "columnAuthor": String(localized: "gitGraph.label.columnAuthor", defaultValue: "Author"),
            "columnCommit": String(localized: "gitGraph.label.columnCommit", defaultValue: "Commit"),
            "loading": String(localized: "gitGraph.label.loading", defaultValue: "Loading history…"),
            "notRepository": String(
                localized: "gitGraph.label.notRepository",
                defaultValue: "This folder is not a Git repository."
            ),
            "empty": String(localized: "gitGraph.label.empty", defaultValue: "This repository has no commits yet."),
            "remote": String(
                localized: "gitGraph.label.remote",
                defaultValue: "Git Graph only supports repositories on this Mac."
            ),
            "noDirectory": String(
                localized: "gitGraph.label.noDirectory",
                defaultValue: "Focus a terminal to see its repository."
            ),
            "gitUnavailable": String(
                localized: "gitGraph.label.gitUnavailable",
                defaultValue: "Git was not found on this Mac."
            ),
            "failed": String(localized: "gitGraph.label.failed", defaultValue: "Could not read the history."),
            "retry": String(localized: "gitGraph.label.retry", defaultValue: "Retry"),
            "limitReached": String(
                localized: "gitGraph.label.limitReached",
                defaultValue: "Showing the most recent commits only (limit: {count})."
            ),
            "filesChanged": String(localized: "gitGraph.label.filesChanged", defaultValue: "Files changed: {count}"),
            "binary": String(localized: "gitGraph.label.binary", defaultValue: "binary"),
            "mergeNote": String(
                localized: "gitGraph.label.mergeNote",
                defaultValue: "Changes compared with the first parent."
            ),
            "uncommitted": String(localized: "gitGraph.label.uncommitted", defaultValue: "Uncommitted changes"),
            "selectCommit": String(
                localized: "gitGraph.label.selectCommit",
                defaultValue: "Select a commit to see its changes."
            ),
        ]
    }
}

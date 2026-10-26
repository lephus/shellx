// English fallbacks. Swift sends localized values for every key in
// `app.context` (GitGraphLabels.localized(), `gitGraph.label.<key>`); its test
// reads the keys below from this file, so keep one `key: "value",` per line.
export const DEFAULT_GIT_GRAPH_LABELS = {
  allBranches: "All branches",
  showRemotes: "Remote branches",
  searchPlaceholder: "Search message, hash or author",
  searchCount: "{current}/{total}",
  searchNoResults: "No results in the loaded commits",
  refresh: "Refresh",
  openAsTab: "Open as tab",
  columnGraph: "Graph",
  columnDescription: "Description",
  columnDate: "Date",
  columnAuthor: "Author",
  columnCommit: "Commit",
  loading: "Loading history…",
  notRepository: "This folder is not a Git repository.",
  empty: "This repository has no commits yet.",
  remote: "Git Graph only supports repositories on this Mac.",
  noDirectory: "Focus a terminal to see its repository.",
  gitUnavailable: "Git was not found on this Mac.",
  failed: "Could not read the history.",
  retry: "Retry",
  limitReached: "Showing the most recent commits only (limit: {count}).",
  filesChanged: "Files changed: {count}",
  binary: "binary",
  mergeNote: "Changes compared with the first parent.",
  uncommitted: "Uncommitted changes",
  selectCommit: "Select a commit to see its changes.",
} as const;

export type GitGraphLabelKey = keyof typeof DEFAULT_GIT_GRAPH_LABELS;
export type GitGraphLabelValues = Record<string, string | number>;
export type GitGraphLabelResolver = (key: GitGraphLabelKey, values?: GitGraphLabelValues) => string;

/** Fills `{name}` placeholders; unknown placeholders stay as written. */
export function formatGitGraphLabel(template: string, values: GitGraphLabelValues): string {
  return template.replace(/\{(\w+)\}/g, (match, name: string) =>
    Object.hasOwn(values, name) ? String(values[name]) : match,
  );
}

export function createGitGraphLabelResolver(labels?: Record<string, string>): GitGraphLabelResolver {
  return (key, values) => {
    const localized = labels?.[key];
    const template =
      typeof localized === "string" && localized.trim() !== "" ? localized : DEFAULT_GIT_GRAPH_LABELS[key];
    return values ? formatGitGraphLabel(template, values) : template;
  };
}

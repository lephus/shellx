import { GitLog } from "@tomplum/react-git-log";
import { useEffect, useLayoutEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import { createGitGraphBridge, type GitGraphBridge } from "./bridge";
import { CommitRow, CommitRowContext, type CommitRowContextValue } from "./CommitRow";
import { DetailPanel } from "./DetailPanel";
import { createGitGraphLabelResolver, type GitGraphLabelKey, type GitGraphLabelResolver } from "./labels";
import {
  GIT_GRAPH_LANE_COLORS,
  findMatches,
  gitLogInputs,
  layoutFor,
  refChipsByCommit,
  toRgb,
  type GitGraphLayout,
} from "./model";
import { GIT_GRAPH_COMMIT_LIMIT, GitGraphStore, type GitGraphState, type GitGraphView } from "./store";
import { Toolbar } from "./Toolbar";
import type { GitGraphWorkingTree } from "./types";

type Appearance = "dark" | "light";

const LANE_COLOURS = GIT_GRAPH_LANE_COLORS.map(toRgb);
const LOAD_MORE_THRESHOLD_PX = 600;
// react-git-log's container is `height: 100%`; inside the scroller it must
// grow with its rows so the footer lands after the last one.
const LOG_CLASSES = { containerClass: "gg-log", containerStyles: { height: "auto" } };

function isDirty(workingTree: GitGraphWorkingTree | null): workingTree is GitGraphWorkingTree {
  return workingTree !== null && workingTree.added + workingTree.modified + workingTree.deleted > 0;
}

function nearBottom(element: HTMLElement): boolean {
  return element.scrollHeight - element.scrollTop - element.clientHeight < LOAD_MORE_THRESHOLD_PX;
}

function scrollToSha(container: HTMLElement | null, sha: string | undefined): void {
  if (!container || !sha) return;
  container.querySelector<HTMLElement>(`[data-sha="${CSS.escape(sha)}"]`)?.scrollIntoView({ block: "center" });
}

/** Starts from the app's appearance, then follows the web view's colour scheme as it changes. */
function useAppearance(initial: Appearance | undefined): Appearance {
  const [query] = useState(() => window.matchMedia("(prefers-color-scheme: dark)"));
  const [beforeContext] = useState<Appearance>(() => (query.matches ? "dark" : "light"));
  const [system, setSystem] = useState<Appearance | null>(null);
  useEffect(() => {
    const onChange = () => setSystem(query.matches ? "dark" : "light");
    query.addEventListener("change", onChange);
    return () => query.removeEventListener("change", onChange);
  }, [query]);
  return system ?? initial ?? beforeContext;
}

export function GitGraphApp({ bridge }: { bridge?: GitGraphBridge }) {
  const [store] = useState(() => new GitGraphStore(bridge ?? createGitGraphBridge()));
  const state = useSyncExternalStore(store.subscribe, store.getState);
  useEffect(() => {
    void store.start();
    return () => store.dispose();
  }, [store]);

  const rootRef = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(() => window.innerWidth);
  useEffect(() => {
    const element = rootRef.current;
    if (!element) return;
    const observer = new ResizeObserver((entries) => {
      const entry = entries[0];
      if (entry) setWidth(entry.contentRect.width);
    });
    observer.observe(element);
    return () => observer.disconnect();
  }, []);
  const layout = layoutFor(width);

  const appearance = useAppearance(state.context?.appearance);
  useEffect(() => {
    document.documentElement.dataset.ggAppearance = appearance;
  }, [appearance]);

  const labels = state.context?.labels;
  const label = useMemo(() => createGitGraphLabelResolver(labels), [labels]);
  const { view } = state;

  return (
    <div ref={rootRef} className="gg-app" data-layout={layout}>
      {state.context === null ? null : view.kind === "ready" ? (
        <HistoryView store={store} state={state} layout={layout} appearance={appearance} label={label} />
      ) : (
        <StatusView view={view} label={label} onRetry={() => void store.retry()} />
      )}
    </div>
  );
}

function StatusView({
  view,
  label,
  onRetry,
}: {
  view: Exclude<GitGraphView, { kind: "ready" }>;
  label: GitGraphLabelResolver;
  onRetry: () => void;
}) {
  const key: GitGraphLabelKey = view.kind === "status" ? view.status : view.kind;
  const canRetry = view.kind === "failed" || (view.kind === "status" && view.status === "gitUnavailable");
  return (
    <div className="gg-status">
      <output>{label(key)}</output>
      {canRetry ? (
        <button type="button" className="gg-button" onClick={onRetry}>
          {label("retry")}
        </button>
      ) : null}
    </div>
  );
}

type HistoryViewProps = {
  store: GitGraphStore;
  state: GitGraphState;
  layout: GitGraphLayout;
  appearance: Appearance;
  label: GitGraphLabelResolver;
};

function HistoryView({ store, state, layout, appearance, label }: HistoryViewProps) {
  const [query, setQuery] = useState("");
  const [matchIndex, setMatchIndex] = useState(0);
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 60_000);
    return () => window.clearInterval(timer);
  }, []);

  const scrollRef = useRef<HTMLDivElement>(null);
  const logRef = useRef<HTMLDivElement>(null);
  const lastScrollTop = useRef(0);
  const [graphColumnWidth, setGraphColumnWidth] = useState(0);

  // Search covers loaded commits only; matches are highlighted, never hidden.
  // Up to 5,000 commits: the list and everything derived from it are rebuilt only
  // when the commits (or the query) change, not on every render.
  const matches = useMemo(() => findMatches(state.commits, query), [state.commits, query]);
  const matchSet = useMemo(() => new Set(matches), [matches]);
  const current = matches.length === 0 ? -1 : Math.min(matchIndex, matches.length - 1);
  const currentMatch = current >= 0 ? (matches[current] ?? null) : null;

  const onQueryChange = (next: string) => {
    setQuery(next);
    setMatchIndex(0);
    scrollToSha(scrollRef.current, findMatches(state.commits, next)[0]);
  };
  const onSearchStep = (direction: 1 | -1) => {
    if (matches.length === 0) return;
    const next = (current + direction + matches.length) % matches.length;
    setMatchIndex(next);
    scrollToSha(scrollRef.current, matches[next]);
  };

  const onScroll = () => {
    const element = scrollRef.current;
    if (!element) return;
    lastScrollTop.current = element.scrollTop;
    if (nearBottom(element)) void store.loadMore();
  };

  // A reload replaces the commits: a refresh keeps the scroll position, a
  // filter change starts at the top. A refresh re-reads every loaded page before
  // it lands, and this runs after those rows are in the DOM, so the old offset exists.
  useLayoutEffect(() => {
    const element = scrollRef.current;
    if (!element) return;
    element.scrollTop = state.scroll === "keep" ? lastScrollTop.current : 0;
  }, [state.historyVersion, state.scroll]);

  // Keep paging while the loaded rows do not reach 600 px past the viewport.
  useEffect(() => {
    const element = scrollRef.current;
    if (element && nearBottom(element)) void store.loadMore();
  }, [state.commits, store]);

  // The wide header's first column spans the graph. Its width follows the lane
  // count and react-git-log's node size, which the library applies only after
  // its first render, so track the table's box rather than measuring once.
  useLayoutEffect(() => {
    const table = logRef.current?.querySelector<HTMLElement>("#react-git-log-table");
    if (!table) return;
    const measure = () => setGraphColumnWidth(table.offsetLeft);
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(table);
    return () => observer.disconnect();
  }, [state.logKey]);

  const visibleRefs = useMemo(
    () => (state.includeRemotes ? state.refs : state.refs.filter((ref) => ref.kind !== "remoteBranch")),
    [state.includeRemotes, state.refs],
  );
  const chipsByCommit = useMemo(() => refChipsByCommit(visibleRefs, state.head), [visibleRefs, state.head]);
  // Every row reads this context, so a new object re-renders all of them.
  const rowContext = useMemo<CommitRowContextValue>(
    () => ({ chipsByCommit, layout, matches: matchSet, currentMatch, workingTree: state.workingTree, label, now }),
    [chipsByCommit, layout, matchSet, currentMatch, state.workingTree, label, now],
  );
  const { entries, currentBranch, hasHead } = useMemo(
    () => gitLogInputs(state.commits, state.head),
    [state.commits, state.head],
  );
  const headBranchRef = state.head.branch === null ? null : `refs/heads/${state.head.branch}`;
  // The working-tree row hangs off HEAD, so it only shows when HEAD's branch is in
  // view and HEAD's commit is loaded. Without that commit there is nothing to hang
  // it from, yet react-git-log would still reserve an empty graph row for it.
  const showIndex =
    isDirty(state.workingTree) && hasHead && (state.branch === null || state.branch === headBranchRef);
  const selectedCommit = useMemo(
    () => state.commits.find((c) => c.sha === state.selectedSha) ?? null,
    [state.commits, state.selectedSha],
  );

  return (
    <>
      <Toolbar
        label={label}
        showOpenAsTab={state.context?.placement === "sidebar"}
        refs={state.refs}
        branch={state.branch}
        includeRemotes={state.includeRemotes}
        query={query}
        matchCount={matches.length}
        matchIndex={Math.max(current, 0)}
        onBranchChange={(branch) => void store.setBranch(branch)}
        onIncludeRemotesChange={(includeRemotes) => void store.setIncludeRemotes(includeRemotes)}
        onQueryChange={onQueryChange}
        onSearchStep={onSearchStep}
        onRefresh={() => void store.refresh()}
        onOpenAsTab={() => void store.openAsTab()}
      />
      <div ref={scrollRef} className="gg-scroll" onScroll={onScroll}>
        {layout === "wide" ? (
          <div
            className="gg-columns"
            style={{
              gridTemplateColumns: `${graphColumnWidth}px minmax(0, 1fr) var(--gg-col-date) var(--gg-col-author) var(--gg-col-hash)`,
            }}
          >
            <span>{label("columnGraph")}</span>
            <span>{label("columnDescription")}</span>
            <span>{label("columnDate")}</span>
            <span>{label("columnAuthor")}</span>
            <span>{label("columnCommit")}</span>
          </div>
        ) : null}
        <div ref={logRef}>
          <CommitRowContext.Provider value={rowContext}>
            <GitLog
              key={state.logKey}
              entries={entries}
              currentBranch={currentBranch}
              theme={appearance}
              colours={LANE_COLOURS}
              showGitIndex={showIndex}
              indexStatus={state.workingTree ?? undefined}
              enableSelectedCommitStyling
              onSelectCommit={(commit) => void store.select(commit?.hash ?? null)}
              classes={LOG_CLASSES}
            >
              <GitLog.GraphHTMLGrid nodeSize={10} />
              <GitLog.Table row={CommitRow} />
            </GitLog>
          </CommitRowContext.Provider>
        </div>
        {state.reachedLimit ? (
          <div className="gg-footer">{label("limitReached", { count: GIT_GRAPH_COMMIT_LIMIT.toLocaleString() })}</div>
        ) : null}
        {state.pagingFailed ? (
          <div className="gg-footer">
            <span>{label("failed")}</span>
            <button type="button" className="gg-button" onClick={() => void store.retryPaging()}>
              {label("retry")}
            </button>
          </div>
        ) : null}
        {state.loadingMore ? <div className="gg-footer gg-muted">{label("loading")}</div> : null}
      </div>
      <DetailPanel
        label={label}
        selectedSha={state.selectedSha}
        commit={selectedCommit}
        workingTree={state.workingTree}
        files={state.files}
        filesState={state.filesState}
        message={state.message}
        onOpenFile={(path) => void store.openFile(path)}
      />
    </>
  );
}

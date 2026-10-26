import { createGenerationGate, type GitGraphBridge } from "./bridge";
import { mergePage } from "./model";
import type {
  GitGraphCommit,
  GitGraphContext,
  GitGraphEvent,
  GitGraphFileChange,
  GitGraphHead,
  GitGraphMethod,
  GitGraphPage,
  GitGraphRef,
  GitGraphReply,
  GitGraphRepoState,
  GitGraphWorkingTree,
} from "./types";

export const GIT_GRAPH_COMMIT_LIMIT = 5000;
export const INDEX_SHA = "index";

export type GitGraphStatusMessage = "notRepository" | "remote" | "noDirectory" | "gitUnavailable" | "empty";

export type GitGraphView =
  | { kind: "loading" }
  | { kind: "status"; status: GitGraphStatusMessage }
  | { kind: "failed" }
  | { kind: "ready" };

export type GitGraphState = {
  context: GitGraphContext | null;
  view: GitGraphView;
  /**
   * Key for the graph component. Bumped on `repo.changed` and when a reload
   * drops the selection, so react-git-log's own selection state starts over.
   */
  logKey: number;
  head: GitGraphHead;
  refs: GitGraphRef[];
  workingTree: GitGraphWorkingTree | null;
  commits: GitGraphCommit[];
  /** Commits fetched so far, used as the next `skip`. */
  loadedCount: number;
  hasMore: boolean;
  reachedLimit: boolean;
  loadingMore: boolean;
  pagingFailed: boolean;
  branch: string | null;
  includeRemotes: boolean;
  /** A commit sha, `"index"` for the working tree row, or null. */
  selectedSha: string | null;
  files: GitGraphFileChange[] | null;
  filesState: "idle" | "loading" | "failed";
  /** Bumped whenever `commits` is replaced (not appended). */
  historyVersion: number;
  /** What the list's scroll position should do after `historyVersion` changes. */
  scroll: "top" | "keep";
};

const NO_HEAD: GitGraphHead = { sha: null, branch: null };

function initialState(): GitGraphState {
  return {
    context: null,
    view: { kind: "loading" },
    logKey: 0,
    head: NO_HEAD,
    refs: [],
    workingTree: null,
    commits: [],
    loadedCount: 0,
    hasMore: false,
    reachedLimit: false,
    loadingMore: false,
    pagingFailed: false,
    branch: null,
    includeRemotes: true,
    selectedSha: null,
    files: null,
    filesState: "idle",
    historyVersion: 0,
    scroll: "top",
  };
}

const FALLBACK_CONTEXT: GitGraphContext = { labels: {}, placement: "tab", appearance: "dark" };

function normalizeContext(value: Partial<GitGraphContext> | null | undefined): GitGraphContext {
  return {
    labels: value?.labels && typeof value.labels === "object" ? value.labels : {},
    placement: value?.placement === "sidebar" ? "sidebar" : "tab",
    appearance: value?.appearance === "light" ? "light" : "dark",
  };
}

function viewForError(code: string): GitGraphView {
  if (code === "notARepository") return { kind: "status", status: "notRepository" };
  if (code === "gitUnavailable") return { kind: "status", status: "gitUnavailable" };
  return { kind: "failed" };
}

function viewForRepoState(repo: GitGraphRepoState): GitGraphView {
  switch (repo.status) {
    case "ready":
      return { kind: "ready" };
    case "loading":
      return { kind: "loading" };
    default:
      return { kind: "status", status: repo.status };
  }
}

/** How a history (re)load treats what is on screen. */
type LoadMode =
  /** New repository: drop the selection, scroll to the top. */
  | "initial"
  /** Branch or remote filter changed: keep a still-present selection, scroll to the top. */
  | "filter"
  /**
   * Refresh or `history.invalidated`: also re-read HEAD and every page loaded so
   * far, keeping the selection and the scroll position.
   */
  | "refresh";

/** The commit list a (re)load produced, applied to the state in one step. */
type LoadedHistory = {
  commits: GitGraphCommit[];
  loadedCount: number;
  hasMore: boolean;
  reachedLimit: boolean;
};

export class GitGraphStore {
  private state: GitGraphState = initialState();
  private readonly listeners = new Set<() => void>();
  private readonly gate = createGenerationGate();
  /** Bumped by every history (re)load; older page replies are ignored. */
  private historyEpoch = 0;
  /** The newest (re)load: a repository load, a filter change or a refresh. Null when idle. */
  private activeLoad: Promise<void> | null = null;
  /** A refresh was asked for while a load ran; it runs once that load finishes. */
  private refreshQueued = false;
  /** Callers of a queued refresh, resolved when no load is left to run. */
  private idleWaiters: Array<() => void> = [];
  /** Bumped by every selection change; older file lists are ignored. */
  private selectionEpoch = 0;
  private offEvent: (() => void) | null = null;

  constructor(private readonly bridge: GitGraphBridge) {}

  getState = (): GitGraphState => this.state;

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

  private set(patch: Partial<GitGraphState>): void {
    this.state = { ...this.state, ...patch };
    for (const listener of this.listeners) listener();
  }

  /**
   * Sends a request and drops the reply when it belongs to an older repository
   * (older generation), or when the host marks it stale (`notAllowed` with a
   * newer generation, sent while the repository changed under the request).
   */
  private async call<T>(method: GitGraphMethod, params?: object): Promise<GitGraphReply<T> | null> {
    const reply = await this.bridge.request<T>(method, params);
    const before = this.gate.latest();
    if (!this.gate.accept(reply.generation)) return null;
    if (!reply.ok && reply.error.code === "notAllowed" && reply.generation > before) return null;
    return reply;
  }

  async start(): Promise<void> {
    if (this.offEvent) return;
    this.offEvent = this.bridge.onEvent((event) => this.handleEvent(event));
    // Labels, placement and appearance do not depend on the repository, so this
    // reply skips the generation check.
    const context = this.bridge.request<GitGraphContext>("app.context").then((reply) => {
      this.set({ context: reply.ok ? normalizeContext(reply.result) : FALLBACK_CONTEXT });
    });
    await Promise.all([context, this.loadRepo()]);
  }

  dispose(): void {
    this.offEvent?.();
    this.offEvent = null;
  }

  handleEvent(event: GitGraphEvent): void {
    if (!this.gate.accept(event.generation)) return;
    if (event.type === "repo.changed") {
      this.selectionEpoch += 1;
      const { context, includeRemotes, logKey } = this.state;
      this.state = { ...initialState(), context, includeRemotes, logKey: logKey + 1 };
      this.set({});
      // The new repository's first load reads everything afresh.
      this.refreshQueued = false;
      void this.loadRepo();
    } else {
      void this.refresh();
    }
  }

  /** Reads `repo.state` and, when the repository is ready, its history. */
  loadRepo(): Promise<void> {
    return this.runLoad(() => this.readRepo());
  }

  /**
   * Makes `load` the load in flight. A newer load supersedes it: each one bumps
   * `historyEpoch`, so an older one applies nothing. When the newest load
   * finishes, a refresh queued meanwhile runs once.
   */
  private runLoad(load: () => Promise<void>): Promise<void> {
    const run: Promise<void> = load().finally(() => this.settle(run));
    this.activeLoad = run;
    return run;
  }

  private settle(run: Promise<void>): void {
    if (this.activeLoad !== run) return;
    this.activeLoad = null;
    if (this.refreshQueued) {
      this.refreshQueued = false;
      void this.refresh();
      return;
    }
    for (const resolve of this.idleWaiters.splice(0)) resolve();
  }

  private async readRepo(): Promise<void> {
    const epoch = ++this.historyEpoch;
    this.set({ view: { kind: "loading" } });
    const reply = await this.call<GitGraphRepoState>("repo.state");
    if (!reply || epoch !== this.historyEpoch) return;
    if (!reply.ok) {
      this.set({ view: viewForError(reply.error.code) });
      return;
    }
    const view = viewForRepoState(reply.result);
    if (view.kind !== "ready") {
      this.set({ view });
      return;
    }
    this.set({ head: reply.result.head ?? NO_HEAD });
    await this.loadHistory("initial");
  }

  retry(): Promise<void> {
    return this.loadRepo();
  }

  /**
   * Re-reads the shown history (the refresh button and `history.invalidated`).
   * It never aborts a load in flight: it queues one more refresh after it, and
   * further requests meanwhile fold into that one. Resolves after the refresh it
   * started, or once the queued one it joined (and any queued after it) has run.
   */
  refresh(): Promise<void> {
    if (this.activeLoad) {
      this.refreshQueued = true;
      return new Promise((resolve) => this.idleWaiters.push(resolve));
    }
    return this.runLoad(() => (this.state.view.kind === "ready" ? this.loadHistory("refresh") : this.readRepo()));
  }

  setBranch(branch: string | null): Promise<void> {
    this.set({ branch });
    return this.runLoad(() => this.loadHistory("filter"));
  }

  setIncludeRemotes(includeRemotes: boolean): Promise<void> {
    const { branch, refs } = this.state;
    const branchIsRemote = refs.some((ref) => ref.fullName === branch && ref.kind === "remoteBranch");
    this.set({ includeRemotes, branch: !includeRemotes && branchIsRemote ? null : branch });
    return this.runLoad(() => this.loadHistory("filter"));
  }

  private pageParams(skip: number): object {
    const { branch, includeRemotes } = this.state;
    return branch ? { skip, includeRemotes, branch } : { skip, includeRemotes };
  }

  private async loadHistory(mode: LoadMode): Promise<void> {
    const epoch = ++this.historyEpoch;
    // A page still in flight belongs to the old list and will be ignored.
    if (this.state.loadingMore) this.set({ loadingMore: false });
    // A refresh reads back as many commits as are loaded now (spec §6.8), so a
    // selection past the first page and the scroll position survive it.
    const target = mode === "refresh" ? this.state.loadedCount : 0;
    const [repo, refs, workingTree, page] = await Promise.all([
      mode === "refresh" ? this.call<GitGraphRepoState>("repo.state") : Promise.resolve(null),
      this.call<GitGraphRef[]>("history.refs"),
      this.call<GitGraphWorkingTree>("history.workingTree"),
      this.call<GitGraphPage>("history.page", this.pageParams(0)),
    ]);
    if (epoch !== this.historyEpoch) return;
    if (repo) {
      if (!repo.ok) return this.set({ view: viewForError(repo.error.code) });
      const view = viewForRepoState(repo.result);
      if (view.kind !== "ready") return this.set({ view });
    }
    if (!refs || !page) return;
    if (!refs.ok) return this.set({ view: viewForError(refs.error.code) });
    const { branch } = this.state;
    if (branch && !refs.result.some((ref) => ref.fullName === branch)) {
      // The filtered branch is gone; fall back to all branches.
      this.set({ branch: null });
      return this.loadHistory(mode);
    }
    if (!page.ok) return this.set({ view: viewForError(page.error.code) });
    const history = await this.readRemainingPages(epoch, page.generation, page.result, target);
    if (!history) return;
    this.applyHistory(mode, refs.result, workingTree?.ok ? workingTree.result : null, history, repo);
  }

  /**
   * Fetches pages after `first`, one at a time, until `target` commits are read,
   * history runs out or the limit is hit. Returns null, so the caller applies
   * nothing, when a newer reload started, the generation changed or a page failed
   * (the failure is shown).
   */
  private async readRemainingPages(
    epoch: number,
    generation: number,
    first: GitGraphPage,
    target: number,
  ): Promise<LoadedHistory | null> {
    let commits = mergePage([], first, 0);
    let loadedCount = first.commits.length;
    let last = first;
    while (loadedCount < target && last.hasMore && !last.reachedLimit && last.commits.length > 0) {
      const reply = await this.call<GitGraphPage>("history.page", this.pageParams(loadedCount));
      if (epoch !== this.historyEpoch || !reply || reply.generation !== generation) return null;
      if (!reply.ok) {
        this.set({ view: viewForError(reply.error.code) });
        return null;
      }
      commits = mergePage(commits, reply.result, loadedCount);
      loadedCount += reply.result.commits.length;
      last = reply.result;
    }
    return { commits, loadedCount, hasMore: last.hasMore, reachedLimit: last.reachedLimit };
  }

  private applyHistory(
    mode: LoadMode,
    refs: GitGraphRef[],
    workingTree: GitGraphWorkingTree | null,
    history: LoadedHistory,
    repo: GitGraphReply<GitGraphRepoState> | null,
  ): void {
    const { commits } = history;
    const { selectedSha } = this.state;
    const dirty = workingTree !== null && workingTree.added + workingTree.modified + workingTree.deleted > 0;
    const keepSelection =
      mode !== "initial" &&
      selectedSha !== null &&
      (selectedSha === INDEX_SHA ? dirty : commits.some((c) => c.sha === selectedSha));
    const droppedSelection = !keepSelection && selectedSha !== null;
    if (!keepSelection) this.selectionEpoch += 1;
    const head = repo?.ok ? (repo.result.head ?? NO_HEAD) : this.state.head;
    this.set({
      view: commits.length === 0 ? { kind: "status", status: "empty" } : { kind: "ready" },
      head,
      refs,
      workingTree,
      commits,
      loadedCount: history.loadedCount,
      hasMore: history.hasMore,
      reachedLimit: history.reachedLimit,
      loadingMore: false,
      pagingFailed: false,
      selectedSha: keepSelection ? selectedSha : null,
      files: keepSelection ? this.state.files : null,
      filesState: keepSelection ? this.state.filesState : "idle",
      logKey: droppedSelection ? this.state.logKey + 1 : this.state.logKey,
      historyVersion: this.state.historyVersion + 1,
      scroll: mode === "refresh" ? "keep" : "top",
    });
  }

  /** Loads the next page; no-op while another load runs or paging is done. */
  async loadMore(): Promise<void> {
    const s = this.state;
    if (s.view.kind !== "ready" || this.activeLoad || s.loadingMore || s.pagingFailed) return;
    if (!s.hasMore || s.reachedLimit) return;
    const epoch = this.historyEpoch;
    const skip = s.loadedCount;
    this.set({ loadingMore: true });
    const reply = await this.call<GitGraphPage>("history.page", this.pageParams(skip));
    if (epoch !== this.historyEpoch) return;
    if (!reply) return this.set({ loadingMore: false });
    if (!reply.ok) return this.set({ loadingMore: false, pagingFailed: true });
    this.set({
      commits: mergePage(this.state.commits, reply.result, skip),
      loadedCount: skip + reply.result.commits.length,
      hasMore: reply.result.hasMore,
      reachedLimit: reply.result.reachedLimit,
      loadingMore: false,
    });
  }

  retryPaging(): Promise<void> {
    this.set({ pagingFailed: false });
    return this.loadMore();
  }

  /** `"index"` opens the working-tree diff; a sha loads its file list. */
  async select(sha: string | null): Promise<void> {
    const token = ++this.selectionEpoch;
    if (sha === null || sha === INDEX_SHA) {
      this.set({ selectedSha: sha, files: null, filesState: "idle" });
      if (sha === INDEX_SHA) await this.call("history.openWorkingTreeDiff");
      return;
    }
    this.set({ selectedSha: sha, files: null, filesState: "loading" });
    const reply = await this.call<GitGraphFileChange[]>("history.files", { sha });
    if (token !== this.selectionEpoch || !reply) return;
    if (!reply.ok) return this.set({ filesState: "failed" });
    this.set({ files: reply.result, filesState: "idle" });
  }

  async openFile(path: string): Promise<void> {
    const sha = this.state.selectedSha;
    if (sha === null || sha === INDEX_SHA) return;
    await this.call("history.openFileDiff", { sha, path });
  }

  async openAsTab(): Promise<void> {
    await this.call("history.openAsTab");
  }
}

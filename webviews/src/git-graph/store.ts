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
  /** Refresh or `history.invalidated`: also re-read HEAD, keep selection and scroll. */
  | "refresh";

export class GitGraphStore {
  private state: GitGraphState = initialState();
  private readonly listeners = new Set<() => void>();
  private readonly gate = createGenerationGate();
  /** Bumped by every history (re)load; older page replies are ignored. */
  private historyEpoch = 0;
  private historyInFlight = false;
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
      void this.loadRepo();
    } else {
      void this.refresh();
    }
  }

  /** Reads `repo.state` and, when the repository is ready, its history. */
  async loadRepo(): Promise<void> {
    const epoch = ++this.historyEpoch;
    this.historyInFlight = false;
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

  refresh(): Promise<void> {
    if (this.state.view.kind !== "ready") return this.loadRepo();
    return this.loadHistory("refresh");
  }

  setBranch(branch: string | null): Promise<void> {
    this.set({ branch });
    return this.loadHistory("filter");
  }

  setIncludeRemotes(includeRemotes: boolean): Promise<void> {
    const { branch, refs } = this.state;
    const branchIsRemote = refs.some((ref) => ref.fullName === branch && ref.kind === "remoteBranch");
    this.set({ includeRemotes, branch: !includeRemotes && branchIsRemote ? null : branch });
    return this.loadHistory("filter");
  }

  private pageParams(skip: number): object {
    const { branch, includeRemotes } = this.state;
    return branch ? { skip, includeRemotes, branch } : { skip, includeRemotes };
  }

  private async loadHistory(mode: LoadMode): Promise<void> {
    const epoch = ++this.historyEpoch;
    this.historyInFlight = true;
    // A page still in flight belongs to the old list and will be ignored.
    if (this.state.loadingMore) this.set({ loadingMore: false });
    try {
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
      this.applyFirstPage(mode, refs.result, workingTree?.ok ? workingTree.result : null, page.result, repo);
    } finally {
      if (epoch === this.historyEpoch) this.historyInFlight = false;
    }
  }

  private applyFirstPage(
    mode: LoadMode,
    refs: GitGraphRef[],
    workingTree: GitGraphWorkingTree | null,
    page: GitGraphPage,
    repo: GitGraphReply<GitGraphRepoState> | null,
  ): void {
    const commits = mergePage([], page, 0);
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
      loadedCount: page.commits.length,
      hasMore: page.hasMore,
      reachedLimit: page.reachedLimit,
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
    if (s.view.kind !== "ready" || this.historyInFlight || s.loadingMore || s.pagingFailed) return;
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

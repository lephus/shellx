import { expect, test } from "bun:test";
import type { GitGraphBridge } from "./bridge";
import { GitGraphStore } from "./store";
import type { GitGraphCommit, GitGraphEvent, GitGraphMethod, GitGraphRef, GitGraphReply } from "./types";

type Handler = (params: Record<string, unknown>) => GitGraphReply<unknown> | undefined;
type Call = { method: GitGraphMethod; params: Record<string, unknown>; resolve: (reply: GitGraphReply<unknown>) => void };

class FakeBridge implements GitGraphBridge {
  calls: Call[] = [];
  handlers: Partial<Record<GitGraphMethod, Handler>> = {};
  private listeners = new Set<(e: GitGraphEvent) => void>();

  request<T>(method: GitGraphMethod, params: object = {}): Promise<GitGraphReply<T>> {
    return new Promise((resolve) => {
      const call: Call = { method, params: params as Record<string, unknown>, resolve: resolve as Call["resolve"] };
      this.calls.push(call);
      const reply = this.handlers[method]?.(call.params);
      if (reply) resolve(reply as GitGraphReply<T>);
    });
  }

  onEvent(cb: (e: GitGraphEvent) => void): () => void {
    this.listeners.add(cb);
    return () => this.listeners.delete(cb);
  }

  emit(event: GitGraphEvent): void {
    for (const listener of this.listeners) listener(event);
  }

  callsTo(method: GitGraphMethod): Call[] {
    return this.calls.filter((c) => c.method === method);
  }
}

const ok = <T>(result: T, generation = 1): GitGraphReply<T> => ({ ok: true, result, generation });
const err = (code: string, generation = 1): GitGraphReply<never> => ({
  ok: false,
  error: { code, message: code },
  generation,
});
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

function sha(n: number): string {
  return n.toString(16).padStart(40, "0");
}

function commit(n: number): GitGraphCommit {
  return {
    sha: sha(n),
    parents: [sha(n + 1)],
    source: "main",
    authorName: "A",
    authorEmail: "a@x.io",
    authorDate: "2026-01-01T00:00:00Z",
    committerDate: "2026-01-01T00:00:00Z",
    subject: `commit ${n}`,
  };
}

const range = (from: number, to: number) => Array.from({ length: to - from }, (_, i) => commit(from + i));

const REFS: GitGraphRef[] = [
  { kind: "localBranch", name: "main", fullName: "refs/heads/main", target: sha(0) },
  { kind: "remoteBranch", name: "origin/main", fullName: "refs/remotes/origin/main", target: sha(0) },
];

function readyBridge(generation = 1): FakeBridge {
  const bridge = new FakeBridge();
  bridge.handlers = {
    "app.context": () => ok({ labels: { refresh: "Làm mới" }, placement: "sidebar", appearance: "light" }, generation),
    "repo.state": () => ok({ status: "ready", repositoryName: "shellx", head: { sha: sha(0), branch: "main" } }, generation),
    "history.refs": () => ok(REFS, generation),
    "history.workingTree": () => ok({ added: 1, modified: 2, deleted: 0 }, generation),
    "history.page": (p) => {
      const skip = Number(p.skip);
      return ok({ commits: range(skip, skip + 3), hasMore: skip < 6, reachedLimit: false }, generation);
    },
    "history.files": () => ok([{ path: "a.txt", oldPath: null, status: "modified", additions: 1, deletions: 0 }], generation),
    "history.openFileDiff": () => ok({ opened: true }, generation),
    "history.openWorkingTreeDiff": () => ok({ opened: true }, generation),
    "history.openAsTab": () => ok(null, generation),
  };
  return bridge;
}

test("start reads the context and repository, then loads refs, working tree and the first page", async () => {
  const bridge = readyBridge();
  const store = new GitGraphStore(bridge);
  await store.start();
  const s = store.getState();
  expect(s.context).toEqual({ labels: { refresh: "Làm mới" }, placement: "sidebar", appearance: "light" });
  expect(s.view).toEqual({ kind: "ready" });
  expect(s.head).toEqual({ sha: sha(0), branch: "main" });
  expect(s.commits.map((c) => c.subject)).toEqual(["commit 0", "commit 1", "commit 2"]);
  expect(s.workingTree).toEqual({ added: 1, modified: 2, deleted: 0 });
  expect(bridge.callsTo("history.page")[0]!.params).toEqual({ skip: 0, includeRemotes: true });
});

test("a repository that is not ready shows its status and loads no history", async () => {
  const bridge = readyBridge();
  bridge.handlers["repo.state"] = () => ok({ status: "remote" });
  const store = new GitGraphStore(bridge);
  await store.start();
  expect(store.getState().view).toEqual({ kind: "status", status: "remote" });
  expect(bridge.callsTo("history.page")).toHaveLength(0);
});

test("service errors map to states: missing git and non-repositories get their message, the rest fail", async () => {
  for (const [code, view] of [
    ["gitUnavailable", { kind: "status", status: "gitUnavailable" }],
    ["notARepository", { kind: "status", status: "notRepository" }],
    ["timedOut", { kind: "failed" }],
    ["outputTooLarge", { kind: "failed" }],
  ] as const) {
    const bridge = readyBridge();
    bridge.handlers["history.page"] = () => err(code);
    const store = new GitGraphStore(bridge);
    await store.start();
    expect(store.getState().view).toEqual(view);
  }
});

test("a reply from an older generation is dropped after repo.changed", async () => {
  const bridge = readyBridge();
  delete bridge.handlers["repo.state"];
  const store = new GitGraphStore(bridge);
  void store.start();
  await flush();
  bridge.emit({ type: "repo.changed", generation: 2 });
  await flush();
  const [first, second] = bridge.callsTo("repo.state");
  second!.resolve(ok({ status: "notRepository" }, 2));
  await flush();
  first!.resolve(ok({ status: "ready", head: { sha: sha(0), branch: "main" } }, 1));
  await flush();
  expect(store.getState().view).toEqual({ kind: "status", status: "notRepository" });
  expect(bridge.callsTo("history.refs")).toHaveLength(0);
});

test("notAllowed with a newer generation marks an in-flight reply stale, so it is dropped", async () => {
  const bridge = readyBridge();
  delete bridge.handlers["repo.state"];
  const store = new GitGraphStore(bridge);
  void store.start();
  await flush();
  bridge.callsTo("repo.state")[0]!.resolve(err("notAllowed", 2));
  await flush();
  expect(store.getState().view).toEqual({ kind: "loading" });
});

test("repo.changed resets the history, the selection and the graph key, then reloads", async () => {
  const bridge = readyBridge();
  const store = new GitGraphStore(bridge);
  await store.start();
  await store.select(sha(1));
  await store.setIncludeRemotes(false);
  const before = store.getState();
  bridge.handlers = readyBridge(2).handlers;
  bridge.emit({ type: "repo.changed", generation: 2 });
  expect(store.getState().commits).toEqual([]);
  expect(store.getState().selectedSha).toBeNull();
  expect(store.getState().logKey).toBe(before.logKey + 1);
  await flush();
  expect(store.getState().view).toEqual({ kind: "ready" });
  expect(store.getState().includeRemotes).toBe(false);
});

test("history.invalidated reloads HEAD, refs, working tree and page 0, keeping a selection that still exists", async () => {
  const bridge = readyBridge();
  const store = new GitGraphStore(bridge);
  await store.start();
  await store.select(sha(1));
  const { logKey, historyVersion } = store.getState();
  bridge.calls = [];
  bridge.emit({ type: "history.invalidated", generation: 1 });
  await flush();
  expect(bridge.calls.map((c): string => c.method).sort()).toEqual([
    "history.page",
    "history.refs",
    "history.workingTree",
    "repo.state",
  ]);
  const s = store.getState();
  expect(s.selectedSha).toBe(sha(1));
  expect(s.files).toHaveLength(1);
  expect(s.scroll).toBe("keep");
  expect(s.logKey).toBe(logKey);
  expect(s.historyVersion).toBe(historyVersion + 1);
});

test("invalidations during a refresh queue exactly one more refresh, and the first refresh still lands", async () => {
  const bridge = readyBridge();
  const store = new GitGraphStore(bridge);
  await store.start();
  const before = store.getState();
  delete bridge.handlers["history.page"];
  bridge.calls = [];
  bridge.emit({ type: "history.invalidated", generation: 1 });
  await flush();
  expect(bridge.callsTo("history.page")).toHaveLength(1);

  bridge.emit({ type: "history.invalidated", generation: 1 });
  void store.refresh();
  bridge.emit({ type: "history.invalidated", generation: 1 });
  await flush();
  expect(bridge.callsTo("history.page")).toHaveLength(1);

  bridge.callsTo("history.page")[0]!.resolve(ok({ commits: range(10, 13), hasMore: false, reachedLimit: false }));
  await flush();
  expect(store.getState().commits.map((c) => c.subject)).toEqual(["commit 10", "commit 11", "commit 12"]);
  expect(store.getState().historyVersion).toBe(before.historyVersion + 1);
  expect(bridge.callsTo("repo.state")).toHaveLength(2);
  const pages = bridge.callsTo("history.page");
  expect(pages).toHaveLength(2);

  pages[1]!.resolve(ok({ commits: range(20, 23), hasMore: false, reachedLimit: false }));
  await flush();
  expect(store.getState().commits.map((c) => c.subject)).toEqual(["commit 20", "commit 21", "commit 22"]);
  expect(store.getState().historyVersion).toBe(before.historyVersion + 2);
  expect(bridge.callsTo("history.page")).toHaveLength(2);
  expect(bridge.callsTo("repo.state")).toHaveLength(2);
});

test("an invalidation during the initial load runs one refresh after it", async () => {
  const bridge = readyBridge();
  const page = bridge.handlers["history.page"]!;
  delete bridge.handlers["history.page"];
  const store = new GitGraphStore(bridge);
  void store.start();
  await flush();
  expect(bridge.callsTo("history.page")).toHaveLength(1);

  bridge.emit({ type: "history.invalidated", generation: 1 });
  await flush();
  expect(bridge.callsTo("repo.state")).toHaveLength(1);
  expect(bridge.callsTo("history.page")).toHaveLength(1);

  bridge.handlers["history.page"] = page;
  bridge.callsTo("history.page")[0]!.resolve(ok({ commits: range(0, 3), hasMore: true, reachedLimit: false }));
  await flush();
  expect(store.getState().view).toEqual({ kind: "ready" });
  expect(bridge.callsTo("repo.state")).toHaveLength(2);
  expect(bridge.callsTo("history.page").map((c) => c.params.skip)).toEqual([0, 0]);
  expect(store.getState().scroll).toBe("keep");
});

test("history.invalidated drops a selection that is gone and remounts the graph", async () => {
  const bridge = readyBridge();
  const store = new GitGraphStore(bridge);
  await store.start();
  await store.select(sha(2));
  const { logKey } = store.getState();
  bridge.handlers["history.page"] = () => ok({ commits: [commit(10)], hasMore: false, reachedLimit: false });
  bridge.emit({ type: "history.invalidated", generation: 1 });
  await flush();
  expect(store.getState().selectedSha).toBeNull();
  expect(store.getState().files).toBeNull();
  expect(store.getState().logKey).toBe(logKey + 1);
});

test("loadMore pages with skip = loaded count and stops when hasMore is false", async () => {
  const bridge = readyBridge();
  const store = new GitGraphStore(bridge);
  await store.start();
  await store.loadMore();
  await store.loadMore();
  await store.loadMore();
  expect(bridge.callsTo("history.page").map((c) => c.params.skip)).toEqual([0, 3, 6]);
  expect(store.getState().commits).toHaveLength(9);
  expect(store.getState().hasMore).toBe(false);
});

test("loadMore does nothing once the limit is reached", async () => {
  const bridge = readyBridge();
  bridge.handlers["history.page"] = () => ok({ commits: range(0, 3), hasMore: true, reachedLimit: true });
  const store = new GitGraphStore(bridge);
  await store.start();
  await store.loadMore();
  expect(bridge.callsTo("history.page")).toHaveLength(1);
});

test("a page reply that lands after a reload started is ignored", async () => {
  const bridge = readyBridge();
  const store = new GitGraphStore(bridge);
  await store.start();
  const page = bridge.handlers["history.page"]!;
  delete bridge.handlers["history.page"];
  void store.loadMore();
  await flush();
  bridge.handlers["history.page"] = page;
  await store.setBranch("refs/heads/main");
  bridge.callsTo("history.page")[1]!.resolve(ok({ commits: range(50, 53), hasMore: false, reachedLimit: false }));
  await flush();
  expect(store.getState().commits.map((c) => c.subject)).toEqual(["commit 0", "commit 1", "commit 2"]);
  expect(store.getState().branch).toBe("refs/heads/main");
});

test("branch filter sends the ref fullName and falls back to all branches when the ref is gone", async () => {
  const bridge = readyBridge();
  const store = new GitGraphStore(bridge);
  await store.start();
  await store.setBranch("refs/heads/main");
  expect(bridge.callsTo("history.page").at(-1)!.params).toEqual({
    skip: 0,
    includeRemotes: true,
    branch: "refs/heads/main",
  });
  bridge.handlers["history.refs"] = () => ok(REFS.slice(1));
  await store.refresh();
  expect(store.getState().branch).toBeNull();
  expect(bridge.callsTo("history.page").at(-1)!.params).toEqual({ skip: 0, includeRemotes: true });
});

test("turning remote branches off clears a remote branch filter", async () => {
  const bridge = readyBridge();
  const store = new GitGraphStore(bridge);
  await store.start();
  await store.setBranch("refs/remotes/origin/main");
  await store.setIncludeRemotes(false);
  expect(store.getState().branch).toBeNull();
  expect(bridge.callsTo("history.page").at(-1)!.params).toEqual({ skip: 0, includeRemotes: false });
});

test("selecting the index row opens the working-tree diff; a commit loads its files; a file opens its diff", async () => {
  const bridge = readyBridge();
  const store = new GitGraphStore(bridge);
  await store.start();
  await store.select("index");
  expect(bridge.callsTo("history.openWorkingTreeDiff")).toHaveLength(1);
  expect(bridge.callsTo("history.files")).toHaveLength(0);
  await store.select(sha(1));
  expect(bridge.callsTo("history.files")[0]!.params).toEqual({ sha: sha(1) });
  expect(store.getState().files).toHaveLength(1);
  await store.openFile("a.txt");
  expect(bridge.callsTo("history.openFileDiff")[0]!.params).toEqual({ sha: sha(1), path: "a.txt" });
});

test("a file list for an earlier selection is ignored", async () => {
  const bridge = readyBridge();
  const store = new GitGraphStore(bridge);
  await store.start();
  delete bridge.handlers["history.files"];
  void store.select(sha(1));
  void store.select(sha(2));
  await flush();
  const [first, second] = bridge.callsTo("history.files");
  second!.resolve(ok([]));
  first!.resolve(ok([{ path: "stale.txt", oldPath: null, status: "added", additions: 1, deletions: 0 }]));
  await flush();
  expect(store.getState().selectedSha).toBe(sha(2));
  expect(store.getState().files).toEqual([]);
});

test("a refresh re-reads every loaded page, so a selection past the first page and the loaded count survive", async () => {
  const bridge = readyBridge();
  const store = new GitGraphStore(bridge);
  await store.start();
  await store.loadMore();
  await store.loadMore();
  await store.select(sha(7));
  const { logKey, loadedCount } = store.getState();
  expect(loadedCount).toBe(9);
  bridge.calls = [];
  bridge.emit({ type: "history.invalidated", generation: 1 });
  await flush();
  expect(bridge.callsTo("history.page").map((c) => c.params.skip)).toEqual([0, 3, 6]);
  const s = store.getState();
  expect(s.loadedCount).toBe(9);
  expect(s.commits).toHaveLength(9);
  expect(s.selectedSha).toBe(sha(7));
  expect(s.files).toHaveLength(1);
  expect(s.logKey).toBe(logKey);
  expect(s.scroll).toBe("keep");
});

test("a refresh keeps reachedLimit when the loaded commits had hit the limit", async () => {
  const bridge = readyBridge();
  bridge.handlers["history.page"] = (p) => {
    const skip = Number(p.skip);
    return ok({ commits: range(skip, skip + 3), hasMore: skip + 3 < 6, reachedLimit: skip + 3 >= 6 });
  };
  const store = new GitGraphStore(bridge);
  await store.start();
  await store.loadMore();
  expect(store.getState().reachedLimit).toBe(true);
  bridge.calls = [];
  await store.refresh();
  expect(bridge.callsTo("history.page").map((c) => c.params.skip)).toEqual([0, 3]);
  expect(store.getState().reachedLimit).toBe(true);
  expect(store.getState().loadedCount).toBe(6);
});

test("a multi-page refresh is discarded when a later page arrives with a new generation", async () => {
  const bridge = readyBridge();
  const store = new GitGraphStore(bridge);
  await store.start();
  await store.loadMore();
  await store.select(sha(4));
  const before = store.getState();
  const page = bridge.handlers["history.page"]!;
  bridge.handlers["history.page"] = (p) => (Number(p.skip) === 0 ? page(p) : undefined);
  bridge.calls = [];
  bridge.emit({ type: "history.invalidated", generation: 1 });
  await flush();
  const pending = bridge.callsTo("history.page");
  expect(pending.map((c) => c.params.skip)).toEqual([0, 3]);
  pending[1]!.resolve(ok({ commits: range(30, 33), hasMore: false, reachedLimit: false }, 2));
  await flush();
  const s = store.getState();
  expect(s.historyVersion).toBe(before.historyVersion);
  expect(s.commits).toBe(before.commits);
  expect(s.selectedSha).toBe(sha(4));
});

test("repo.changed during a multi-page refresh wins over the refresh", async () => {
  const bridge = readyBridge();
  const store = new GitGraphStore(bridge);
  await store.start();
  await store.loadMore();
  const page = bridge.handlers["history.page"]!;
  bridge.handlers["history.page"] = (p) => (Number(p.skip) === 0 ? page(p) : undefined);
  bridge.calls = [];
  bridge.emit({ type: "history.invalidated", generation: 1 });
  await flush();
  const stale = bridge.callsTo("history.page")[1]!;
  bridge.handlers = readyBridge(2).handlers;
  bridge.handlers["repo.state"] = () => ok({ status: "notRepository" }, 2);
  bridge.emit({ type: "repo.changed", generation: 2 });
  await flush();
  stale.resolve(ok({ commits: range(3, 6), hasMore: false, reachedLimit: false }, 1));
  await flush();
  expect(store.getState().view).toEqual({ kind: "status", status: "notRepository" });
  expect(store.getState().commits).toEqual([]);
});

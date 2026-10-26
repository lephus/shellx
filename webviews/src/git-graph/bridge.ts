import type { GitGraphEvent, GitGraphMethod, GitGraphReply } from "./types";

// Page side of the `shellxGitGraph` bridge (Swift: GitGraphBridgeContract).
//
// Requests are `{ method, params }`, posted to a WKScriptMessageHandlerWithReply
// whose promise resolves to `{ ok: true, result, generation }` or
// `{ ok: false, error: { code, message }, generation }`. Params and results:
// - `app.context` → GitGraphContext
// - `repo.state` → GitGraphRepoState
// - `history.refs` → GitGraphRef[]
// - `history.workingTree` → GitGraphWorkingTree
// - `history.page { skip, includeRemotes, branch? }` → GitGraphPage
// - `history.files { sha }` → GitGraphFileChange[]
// - `history.openFileDiff { sha, path }`, `history.openWorkingTreeDiff`,
//   `history.openAsTab` → no meaningful result
// The host pushes events by calling `window.shellxGitGraph.receive(event)`.

export type GitGraphMessageHandler = {
  postMessage(message: unknown): Promise<unknown>;
};

export type GitGraphHost = {
  webkit?: { messageHandlers?: { shellxGitGraph?: GitGraphMessageHandler } };
  shellxGitGraph?: { receive(event: GitGraphEvent): void };
};

export type GitGraphBridge = {
  request<T>(method: GitGraphMethod, params?: object): Promise<GitGraphReply<T>>;
  onEvent(cb: (e: GitGraphEvent) => void): () => void;
};

function isReply(value: unknown): value is GitGraphReply<unknown> {
  if (typeof value !== "object" || value === null) return false;
  const reply = value as { ok?: unknown; generation?: unknown; error?: unknown };
  if (typeof reply.generation !== "number" || typeof reply.ok !== "boolean") return false;
  if (reply.ok) return true;
  const error = reply.error as { code?: unknown } | null | undefined;
  return typeof error === "object" && error !== null && typeof error.code === "string";
}

function isEvent(value: unknown): value is GitGraphEvent {
  if (typeof value !== "object" || value === null) return false;
  const event = value as { type?: unknown; generation?: unknown };
  return (
    (event.type === "repo.changed" || event.type === "history.invalidated") &&
    typeof event.generation === "number"
  );
}

export function createGitGraphBridge(host: GitGraphHost = window): GitGraphBridge {
  const listeners = new Set<(e: GitGraphEvent) => void>();
  // Failures made up on this side carry the newest generation seen, so the
  // page's stale-reply check treats them as current.
  let latestGeneration = 0;
  const observe = (generation: number) => {
    if (generation > latestGeneration) latestGeneration = generation;
  };
  const failure = (message: string): GitGraphReply<never> => ({
    ok: false,
    error: { code: "failed", message },
    generation: latestGeneration,
  });

  host.shellxGitGraph = {
    receive(event) {
      if (!isEvent(event)) return;
      observe(event.generation);
      for (const listener of listeners) listener(event);
    },
  };

  return {
    async request<T>(method: GitGraphMethod, params: object = {}): Promise<GitGraphReply<T>> {
      const handler = host.webkit?.messageHandlers?.shellxGitGraph;
      if (!handler) return failure("The shellxGitGraph handler is not available.");
      let reply: unknown;
      try {
        reply = await handler.postMessage({ method, params });
      } catch (error) {
        return failure(error instanceof Error ? error.message : String(error));
      }
      if (!isReply(reply)) return failure("Malformed reply.");
      observe(reply.generation);
      return reply as GitGraphReply<T>;
    },
    onEvent(cb) {
      listeners.add(cb);
      return () => {
        listeners.delete(cb);
      };
    },
  };
}

/** Tracks the newest generation seen; anything older belongs to a previous repository. */
export function createGenerationGate() {
  let latest = 0;
  return {
    accept(generation: number): boolean {
      if (generation < latest) return false;
      latest = generation;
      return true;
    },
    latest: () => latest,
  };
}

import { expect, test } from "bun:test";
import { createGenerationGate, createGitGraphBridge, type GitGraphHost } from "./bridge";

function fakeHost(reply: (msg: unknown) => unknown): GitGraphHost {
  return {
    webkit: {
      messageHandlers: {
        shellxGitGraph: {
          postMessage: (msg: unknown) => Promise.resolve(reply(msg)),
        },
      },
    },
  };
}

test("request posts to the shellxGitGraph handler and resolves the reply", async () => {
  const posted: unknown[] = [];
  const host = fakeHost((msg) => { posted.push(msg); return { ok: true, result: { status: "ready" }, generation: 1 }; });
  const bridge = createGitGraphBridge(host);
  const reply = await bridge.request("repo.state");
  expect(posted).toEqual([{ method: "repo.state", params: {} }]);
  expect(reply).toEqual({ ok: true, result: { status: "ready" }, generation: 1 });
});

test("receive fans events out to subscribers and unsubscribe stops delivery", () => {
  const host = fakeHost(() => ({ ok: true, result: null, generation: 0 }));
  const bridge = createGitGraphBridge(host);
  const seen: string[] = [];
  const off = bridge.onEvent((e) => seen.push(e.type));
  host.shellxGitGraph!.receive({ type: "history.invalidated", generation: 2 });
  off();
  host.shellxGitGraph!.receive({ type: "repo.changed", generation: 3 });
  expect(seen).toEqual(["history.invalidated"]);
});

test("no git-graph source uses dangerouslySetInnerHTML", async () => {
  const glob = new Bun.Glob("src/git-graph/**/*.tsx");
  for await (const file of glob.scan(".")) {
    expect(await Bun.file(file).text()).not.toContain("dangerouslySetInnerHTML");
  }
});

test("request passes params through and turns a missing handler into a failed reply", async () => {
  const posted: unknown[] = [];
  const bridge = createGitGraphBridge(fakeHost((msg) => { posted.push(msg); return { ok: true, result: [], generation: 4 }; }));
  await bridge.request("history.page", { skip: 300, includeRemotes: false });
  expect(posted).toEqual([{ method: "history.page", params: { skip: 300, includeRemotes: false } }]);

  const reply = await createGitGraphBridge({}).request("repo.state");
  expect(reply.ok).toBe(false);
});

test("a rejected or malformed host reply becomes a failed reply at the latest seen generation", async () => {
  let call = 0;
  const host: GitGraphHost = {
    webkit: {
      messageHandlers: {
        shellxGitGraph: {
          postMessage: () => {
            call += 1;
            if (call === 1) return Promise.resolve({ ok: true, result: null, generation: 5 });
            if (call === 2) return Promise.reject(new Error("boom"));
            return Promise.resolve("not a reply");
          },
        },
      },
    },
  };
  const bridge = createGitGraphBridge(host);
  await bridge.request("repo.state");
  const rejected = await bridge.request("repo.state");
  expect(rejected).toEqual({ ok: false, error: { code: "failed", message: "boom" }, generation: 5 });
  const malformed = await bridge.request("repo.state");
  expect(malformed.ok).toBe(false);
  expect(malformed.generation).toBe(5);
});

test("the generation gate drops replies older than the latest generation it has seen", () => {
  const gate = createGenerationGate();
  expect(gate.accept(1)).toBe(true);
  expect(gate.accept(3)).toBe(true);
  expect(gate.accept(2)).toBe(false);
  expect(gate.accept(3)).toBe(true);
  expect(gate.latest()).toBe(3);
});

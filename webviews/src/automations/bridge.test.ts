import { expect, test } from "bun:test";
import { createAutomationsBridge, type AutomationsHost } from "./bridge";

function fakeHost(reply: (msg: unknown) => unknown): AutomationsHost {
  return {
    webkit: { messageHandlers: { shellxAutomations: { postMessage: (m: unknown) => Promise.resolve(reply(m)) } } },
  };
}

test("request posts {method, params} and resolves the ok reply", async () => {
  const posted: unknown[] = [];
  const bridge = createAutomationsBridge(
    fakeHost((m) => {
      posted.push(m);
      return { ok: true, result: { automations: [] } };
    }),
  );
  const reply = await bridge.request("automations.list");
  expect(posted).toEqual([{ method: "automations.list", params: {} }]);
  expect(reply).toEqual({ ok: true, result: { automations: [] } });
});

test("params are passed through", async () => {
  const posted: unknown[] = [];
  const bridge = createAutomationsBridge(fakeHost((m) => (posted.push(m), { ok: true, result: null })));
  await bridge.request("automations.delete", { id: "external:x", confirmedExternal: true });
  expect(posted).toEqual([{ method: "automations.delete", params: { id: "external:x", confirmedExternal: true } }]);
});

test("host errors keep their code and message", async () => {
  const bridge = createAutomationsBridge(fakeHost(() => ({ ok: false, error: { code: "notFound", message: "gone" } })));
  expect(await bridge.request("automations.runNow", { id: "a" })).toEqual({
    ok: false,
    error: { code: "notFound", message: "gone" },
  });
});

test("missing handler, rejection and malformed replies become failed replies", async () => {
  expect((await createAutomationsBridge({}).request("app.context")).ok).toBe(false);
  const rejecting: AutomationsHost = {
    webkit: { messageHandlers: { shellxAutomations: { postMessage: () => Promise.reject(new Error("boom")) } } },
  };
  expect(await createAutomationsBridge(rejecting).request("app.context")).toEqual({
    ok: false,
    error: { code: "failed", message: "boom" },
  });
  const malformed = await createAutomationsBridge(fakeHost(() => "nope")).request("app.context");
  expect(malformed.ok).toBe(false);
});

test("receive fans events out and unsubscribe stops delivery; junk is ignored", () => {
  const host = fakeHost(() => ({ ok: true, result: null }));
  const bridge = createAutomationsBridge(host);
  const seen: string[] = [];
  const off = bridge.onEvent((e) => seen.push(e.type));
  host.shellxAutomations!.receive({ type: "focus", id: "a" });
  host.shellxAutomations!.receive({ nope: 1 } as never);
  off();
  host.shellxAutomations!.receive({ type: "automations.changed" });
  expect(seen).toEqual(["focus"]);
});

test("receive accepts the appearance event", () => {
  const host = fakeHost(() => ({ ok: true, result: null }));
  const bridge = createAutomationsBridge(host);
  const seen: unknown[] = [];
  bridge.onEvent((e) => seen.push(e));
  host.shellxAutomations!.receive({ type: "appearance", appearance: "light" });
  expect(seen).toEqual([{ type: "appearance", appearance: "light" }]);
});

test("no automations source uses dangerouslySetInnerHTML or window dialogs", async () => {
  const glob = new Bun.Glob("src/automations/**/*.{ts,tsx}");
  for await (const file of glob.scan(".")) {
    if (file.endsWith(".test.ts") || file.endsWith(".test.tsx")) continue;
    const text = await Bun.file(file).text();
    expect(text).not.toContain("dangerouslySetInnerHTML");
    expect(text).not.toMatch(/window\.(confirm|alert|prompt)\(/);
  }
});

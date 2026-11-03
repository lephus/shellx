import { expect, test } from "bun:test";
import type { AutomationsBridge } from "./bridge";
import { AutomationsStore, visibleAutomations } from "./store";
import type { AutomationDTO, AutomationDraft, AutomationsEvent, AutomationsMethod } from "./types";

function dto(over: Partial<AutomationDTO>): AutomationDTO {
  return {
    id: "a",
    kind: "skill",
    name: "a",
    description: "d",
    notify: { on: [], targets: [] },
    allowedTools: [],
    steps: [],
    enabled: true,
    origin: "shellx",
    createdAt: "2026-11-03T00:00:00Z",
    updatedAt: "2026-11-03T00:00:00Z",
    iphonePending: false,
    ...over,
  };
}

function draft(over: Partial<AutomationDraft>): AutomationDraft {
  return {
    kind: "cronjob",
    name: "",
    description: "",
    notify: { on: [], targets: [] },
    allowedTools: [],
    steps: [],
    skillMarkdown: "",
    ...over,
  };
}

function fakeBridge(handlers: Partial<Record<AutomationsMethod, (p: object) => unknown>> = {}) {
  const calls: { method: string; params: object }[] = [];
  let listener: (e: AutomationsEvent) => void = () => {};
  const bridge: AutomationsBridge = {
    async request(method, params = {}) {
      calls.push({ method, params });
      const h = handlers[method];
      if (h) {
        const r = h(params);
        if (r && typeof r === "object" && "__error" in r) return { ok: false, error: { code: "x", message: "bad" } } as never;
        return { ok: true, result: r } as never;
      }
      if (method === "app.context") return { ok: true, result: { labels: {}, reduceMotion: false } } as never;
      if (method === "automations.list") return { ok: true, result: { automations: [] } } as never;
      return { ok: true, result: null } as never;
    },
    onEvent(cb) {
      listener = cb;
      return () => {};
    },
  };
  return { bridge, calls, emit: (e: AutomationsEvent) => listener(e) };
}

const creator = (event: object): AutomationsEvent => ({ type: "creator.event", event } as AutomationsEvent);

async function started(handlers = {}) {
  const f = fakeBridge(handlers);
  const store = new AutomationsStore(f.bridge);
  await store.start();
  return { store, ...f };
}

test("appliesDraftEventsKeepingLastGood", async () => {
  const { store, emit } = await started();
  await store.startCreator();
  emit(creator({ type: "draft", draft: draft({ name: "pr-digest" }) }));
  expect(store.getState().creator.draft?.name).toBe("pr-digest");
  emit(creator({ type: "draft", draft: null }));
  emit(creator({ type: "draft", draft: "garbage" }));
  emit(creator({ type: "draft" }));
  expect(store.getState().creator.draft?.name).toBe("pr-digest");
  emit(creator({ type: "draft", draft: draft({ name: "pr-digest-2" }) }));
  expect(store.getState().creator.draft?.name).toBe("pr-digest-2");
});

test("textDeltasAppendToStreamingMessage", async () => {
  const { store, emit } = await started();
  await store.startCreator();
  emit(creator({ type: "textDelta", text: "Hel" }));
  emit(creator({ type: "textDelta", text: "lo" }));
  expect(store.getState().creator.streaming).toBe("Hello");
  expect(store.getState().creator.messages).toEqual([]);
});

test("assistantMessageReplacesStreaming", async () => {
  const { store, emit } = await started();
  await store.startCreator();
  emit(creator({ type: "textDelta", text: "Hel" }));
  emit(creator({ type: "assistantMessage", text: "Hello there", choices: { question: "q", multi: false, options: ["a"] } }));
  const c = store.getState().creator;
  expect(c.streaming).toBeNull();
  expect(c.messages).toHaveLength(1);
  expect(c.messages[0]).toMatchObject({ role: "assistant", text: "Hello there" });
});

test("filtersByKind", async () => {
  const f = fakeBridge({
    "automations.list": () => ({
      automations: [dto({ id: "s", kind: "skill" }), dto({ id: "w", kind: "workflow" }), dto({ id: "c", kind: "cronjob" })],
    }),
  });
  const store = new AutomationsStore(f.bridge);
  await store.start();
  const ids = () => visibleAutomations(store.getState()).own.map((a) => a.id);
  expect(ids()).toEqual(["s", "w", "c"]);
  store.setFilter("workflow");
  expect(ids()).toEqual(["w"]);
  store.setFilter("cronjob");
  expect(ids()).toEqual(["c"]);
});

test("externalSkillsGroupedSeparately", async () => {
  const f = fakeBridge({
    "automations.list": () => ({
      automations: [dto({ id: "s" }), dto({ id: "external:x", origin: "external", kind: "skill" })],
    }),
  });
  const store = new AutomationsStore(f.bridge);
  await store.start();
  let v = visibleAutomations(store.getState());
  expect(v.own.map((a) => a.id)).toEqual(["s"]);
  expect(v.external.map((a) => a.id)).toEqual(["external:x"]);
  store.setFilter("cronjob");
  v = visibleAutomations(store.getState());
  expect(v.external).toEqual([]);
});

test("focusEventSelectsCard", async () => {
  const { store, emit } = await started();
  emit({ type: "focus", id: "abc" });
  expect(store.getState().focusId).toBe("abc");
  expect(store.getState().view).toBe("list");
});

test("context focusId and reduceMotion are applied", async () => {
  const f = fakeBridge({ "app.context": () => ({ labels: { save: "Lưu" }, focusId: "z", reduceMotion: true }) });
  const store = new AutomationsStore(f.bridge);
  await store.start();
  expect(store.getState().focusId).toBe("z");
  expect(store.getState().context?.reduceMotion).toBe(true);
});

test("first message is prefixed with the chosen type; Auto sends text as is", async () => {
  const { store, calls } = await started();
  await store.startCreator();
  store.setCreatorType("cronjob");
  await store.sendMessage("every morning");
  await store.sendMessage("second");
  const sends = calls.filter((c) => c.method === "creator.send").map((c) => (c.params as { text: string }).text);
  expect(sends).toEqual(["Type: cronjob. every morning", "second"]);
  expect(store.getState().creator.messages.map((m) => m.text)).toEqual(["every morning", "second"]);
});

test("save with issues stays in the creator; save success returns to the list with the card focused", async () => {
  let n = 0;
  const { store, calls } = await started({
    "creator.save": () =>
      ++n === 1
        ? { issues: [{ field: "name", code: "bad", message: "no" }] }
        : { automation: dto({ id: "new" }) },
  });
  await store.startCreator();
  await store.save();
  expect(store.getState().view).toBe("creator");
  expect(store.getState().creator.issues).toHaveLength(1);
  await store.save();
  expect(store.getState().view).toBe("list");
  expect(store.getState().focusId).toBe("new");
  expect(calls.some((c) => c.method === "automations.list")).toBe(true);
});

test("external delete needs confirmation and sends confirmedExternal", async () => {
  const { store, calls } = await started();
  store.requestDelete(dto({ id: "external:x", origin: "external" }));
  expect(store.getState().pendingDelete?.external).toBe(true);
  await store.confirmDelete();
  expect(calls.find((c) => c.method === "automations.delete")?.params).toEqual({ id: "external:x", confirmedExternal: true });
  expect(store.getState().pendingDelete).toBeNull();
  store.requestDelete(dto({ id: "own" }));
  await store.confirmDelete();
  expect(calls.filter((c) => c.method === "automations.delete")[1]?.params).toEqual({ id: "own" });
});

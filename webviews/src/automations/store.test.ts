import { expect, test } from "bun:test";
import type { AutomationsBridge } from "./bridge";
import { AutomationsStore, draftInProgress, visibleAutomations } from "./store";
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
        const r = await h(params);
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

const FAIL = () => ({ __error: true });

test("a failed list action sets actionError, keeps the card, and can be dismissed", async () => {
  const f = fakeBridge({ "automations.delete": FAIL, "automations.runNow": FAIL });
  const store = new AutomationsStore(f.bridge);
  await store.start();
  store.requestDelete(dto({ id: "own" }));
  await store.confirmDelete();
  expect(store.getState().actionError).toBe("bad");
  expect(f.calls.filter((c) => c.method === "automations.list")).toHaveLength(1);
  store.dismissActionError();
  expect(store.getState().actionError).toBeNull();
  await store.runNow("own");
  expect(store.getState().actionError).toBe("bad");
});

test("a failed creator.start surfaces as a failed message", async () => {
  const { store } = await started({ "creator.start": FAIL });
  await store.startCreator();
  expect(store.getState().creator.messages.map((m) => m.role)).toEqual(["error"]);
});

test("a list reply without an automations array is a load failure", async () => {
  const f = fakeBridge({ "automations.list": () => ({ nope: 1 }) });
  const store = new AutomationsStore(f.bridge);
  await store.start();
  expect(store.getState().loadFailed).toBe(true);
});

test("emptyListOpensTheCreator", async () => {
  const { store, calls } = await started();
  expect(store.getState().view).toBe("creator");
  expect(calls.map((c) => c.method)).toContain("creator.start");
});

test("listWithAutomationsOrAFocusStaysOnTheList", async () => {
  const withItems = await started({ "automations.list": () => ({ automations: [dto({})] }) });
  expect(withItems.store.getState().view).toBe("list");
  expect(withItems.calls.map((c) => c.method)).not.toContain("creator.start");
  const focused = await started({ "app.context": () => ({ labels: {}, reduceMotion: false, focusId: "x" }) });
  expect(focused.store.getState().view).toBe("list");
});

/** A store over one saved automation, so it does not open the creator on its own. */
const withOne = () => started({ "automations.list": () => ({ automations: [dto({})] }) });

test("Back after a message keeps the chat as a draft in progress that Continue reopens", async () => {
  const { store, calls } = await withOne();
  await store.startCreator();
  await store.sendMessage("hi");
  await store.leaveCreator();
  expect(store.getState().view).toBe("list");
  expect(calls.some((c) => c.method === "creator.cancel")).toBe(false);
  expect(draftInProgress(store.getState().creator)).toBe(true);

  store.resumeCreator();
  expect(store.getState().view).toBe("creator");
  expect(store.getState().creator.messages.map((m) => m.text)).toEqual(["hi"]);
  expect(calls.filter((c) => c.method === "creator.start")).toHaveLength(1);
});

test("Back before any message discards the creator as before", async () => {
  const { store, calls } = await withOne();
  await store.startCreator();
  await store.leaveCreator();
  expect(calls.some((c) => c.method === "creator.cancel")).toBe(true);
  expect(draftInProgress(store.getState().creator)).toBe(false);
});

test("discarding a draft in progress asks first, then stops Claude", async () => {
  const { store, calls } = await withOne();
  await store.startCreator();
  await store.sendMessage("hi");
  await store.leaveCreator();

  store.requestDiscard();
  expect(store.getState().pendingDiscard).not.toBeNull();
  store.cancelDiscard();
  expect(draftInProgress(store.getState().creator)).toBe(true);

  store.requestDiscard();
  await store.confirmDiscard();
  expect(calls.some((c) => c.method === "creator.cancel")).toBe(true);
  expect(draftInProgress(store.getState().creator)).toBe(false);
  expect(store.getState().pendingDiscard).toBeNull();
  expect(store.getState().view).toBe("list");
});

test("starting another creator while a draft is in progress asks before replacing it", async () => {
  const { store, calls } = await withOne();
  await store.startCreator();
  await store.sendMessage("hi");
  await store.leaveCreator();

  await store.startCreator("other");
  expect(store.getState().view).toBe("list");
  expect(calls.filter((c) => c.method === "creator.start")).toHaveLength(1);

  await store.confirmDiscard();
  const starts = calls.filter((c) => c.method === "creator.start");
  expect(starts).toHaveLength(2);
  expect(starts[1].params).toEqual({ editId: "other" });
  expect(store.getState().view).toBe("creator");
  expect(store.getState().creator.messages).toHaveLength(0);
});

test("Edit on the automation already being edited goes back to its draft without asking", async () => {
  const { store, calls } = await withOne();
  await store.startCreator("same");
  await store.sendMessage("tweak it");
  await store.leaveCreator();

  await store.startCreator("same");
  expect(store.getState().pendingDiscard).toBeNull();
  expect(store.getState().view).toBe("creator");
  expect(calls.filter((c) => c.method === "creator.start")).toHaveLength(1);
});

test("an event the discarded session sent while it was being stopped does not reach the next creator", async () => {
  let emitStale: () => void = () => {};
  const f = fakeBridge({
    "automations.list": () => ({ automations: [dto({})] }),
    "creator.cancel": () => (emitStale(), null),
  });
  const store = new AutomationsStore(f.bridge);
  await store.start();
  emitStale = () => f.emit(creator({ type: "textDelta", text: "stale" }));
  await store.startCreator();
  await store.sendMessage("hi");
  await store.leaveCreator();

  store.requestDiscard();
  await store.confirmDiscard();

  expect(store.getState().creator.streaming).toBeNull();
  expect(store.getState().creator.busy).toBe(false);
});

test("card edits keep the frontmatter in step and reach the host before save and send", async () => {
  const { store, emit, calls } = await started({ "creator.save": () => ({ automation: dto({ id: "new" }) }) });
  await store.startCreator();
  emit(creator({ type: "draft", draft: draft({ name: "a", description: "d", skillMarkdown: "---\nname: a\ndescription: d\n---\nBody\n" }) }));
  store.editDraft({ name: "b" });
  expect(store.getState().creator.draft?.skillMarkdown).toBe("---\nname: b\ndescription: d\n---\nBody\n");
  store.editDraft({ skillMarkdown: "---\nname: c\ndescription: New words\n---\nBody\n" });
  expect(store.getState().creator.draft?.name).toBe("c");
  expect(store.getState().creator.draft?.description).toBe("New words");
  await store.sendMessage("hi");
  const methods = calls.map((c) => c.method);
  expect(methods.indexOf("creator.edit")).toBeLessThan(methods.indexOf("creator.send"));
  expect(calls.find((c) => c.method === "creator.edit")?.params).toEqual({
    name: "c",
    description: "New words",
    skillMarkdown: "---\nname: c\ndescription: New words\n---\nBody\n",
  });
  // Unchanged since the last flush: save does not send the edit again.
  await store.save();
  expect(calls.filter((c) => c.method === "creator.edit")).toHaveLength(1);
});

test("the card cannot be edited while Claude is busy, and a new draft from Claude wins", async () => {
  const { store, emit } = await started();
  await store.startCreator();
  emit(creator({ type: "draft", draft: draft({ name: "a" }) }));
  emit(creator({ type: "busy", busy: true }));
  store.editDraft({ name: "b" });
  expect(store.getState().creator.draft?.name).toBe("a");
  emit(creator({ type: "busy", busy: false }));
  store.editDraft({ name: "b" });
  expect(store.getState().creator.draftDirty).toBe(true);
  emit(creator({ type: "draft", draft: draft({ name: "z" }) }));
  expect(store.getState().creator.draftDirty).toBe(false);
});

test("save waits for an edit a blur already sent", async () => {
  let release: () => void = () => {};
  const order: string[] = [];
  const { store, emit } = await started({
    "creator.edit": () => new Promise((resolve) => { release = () => { order.push("edit"); resolve({}); }; }),
    "creator.save": () => { order.push("save"); return { automation: dto({ id: "new" }) }; },
  });
  await store.startCreator();
  emit(creator({ type: "draft", draft: draft({ name: "a" }) }));
  store.editDraft({ name: "b" });
  void store.flushDraftEdit();
  const saving = store.save();
  await Promise.resolve();
  release();
  await saving;
  expect(order).toEqual(["edit", "save"]);
});

test("editMarksFlowOutdated: an edit makes the chart out of date until the next draft with a flow", async () => {
  const { store, emit } = await started();
  await store.startCreator();
  const flow = { nodes: [{ id: "a", type: "step" as const, label: "Go" }], edges: [] };
  expect(store.getState().creator.draftView).toBe("flow");
  emit(creator({ type: "draft", draft: draft({ kind: "skill", name: "a", skillMarkdown: "---\nname: a\n---\n", flow }) }));
  expect(store.getState().creator.flowCurrent).toBe(true);
  store.editDraft({ skillMarkdown: "---\nname: a\n---\nMore\n" });
  expect(store.getState().creator.flowCurrent).toBe(false);
  emit(creator({ type: "draft", draft: draft({ kind: "skill", name: "a", skillMarkdown: "x", flow }) }));
  expect(store.getState().creator.flowCurrent).toBe(true);
  emit(creator({ type: "draft", draft: draft({ kind: "skill", name: "a", skillMarkdown: "x" }) }));
  expect(store.getState().creator.flowCurrent).toBe(false);
  store.setDraftView("text");
  expect(store.getState().creator.draftView).toBe("text");
});

import { afterEach, expect, test } from "bun:test";
import { JSDOM } from "jsdom";
import { flushSync } from "react-dom";
import { createRoot, type Root } from "react-dom/client";
import { renderToStaticMarkup } from "react-dom/server";
import { AutomationCard } from "./AutomationCard";
import { createAutomationLabelResolver } from "./labels";
import type { AutomationDTO, AutomationRunDTO } from "./types";

const label = createAutomationLabelResolver();
const base: AutomationDTO = {
  id: "a1",
  kind: "workflow",
  name: "flow",
  description: "d",
  notify: { on: [], targets: [] },
  allowedTools: [],
  steps: [],
  enabled: true,
  origin: "shellx",
  createdAt: "2026-11-03T10:00:00Z",
  updatedAt: "2026-11-03T10:00:00Z",
  iphonePending: false,
};

function render(lastRun: AutomationRunDTO): string {
  const store = {} as never;
  return renderToStaticMarkup(
    <AutomationCard store={store} automation={{ ...base, lastRun }} label={label} focused={false} />,
  );
}

const run: AutomationRunDTO = { status: "running", trigger: "manual", startedAt: "2026-11-03T10:00:00Z", unread: false };

test("running workflow shows Step 2/3", () => {
  expect(render({ ...run, currentStep: 2, totalSteps: 3 })).toContain("Step 2/3");
});

test("single-step or finished runs show no step progress", () => {
  expect(render({ ...run, currentStep: 1, totalSteps: 1 })).not.toContain("Step ");
  expect(render({ ...run, status: "done", finishedAt: "2026-11-03T10:00:42Z", currentStep: 3, totalSteps: 3 })).not.toContain("Step ");
});

test("finished run shows its duration", () => {
  const html = render({ ...run, status: "done", finishedAt: "2026-11-03T10:00:42Z" });
  expect(html).toContain("42 s");
});

function renderCard(over: Partial<AutomationDTO>): string {
  const store = {} as never;
  return renderToStaticMarkup(<AutomationCard store={store} automation={{ ...base, ...over }} label={label} focused={false} />);
}

test("skills ShellX did not create offer Edit in the app as well as Edit file", () => {
  const html = renderCard({ id: "external:theirs", kind: "skill", origin: "external" });
  expect(html).toContain(">Edit file<");
  expect(html).toContain(">Edit<");
  expect(renderCard({})).toContain(">Edit<");
});

// Clicks need a DOM; the globals are put back after each test.
let root: Root | null = null;
let dom: JSDOM | null = null;
const saved = new Map<string, unknown>();
for (const key of ["window", "document", "navigator", "Element", "Node", "HTMLElement"]) {
  saved.set(key, (globalThis as Record<string, unknown>)[key]);
}

afterEach(async () => {
  if (root) flushSync(() => root?.unmount());
  root = null;
  await new Promise((resolve) => setTimeout(resolve, 0));
  dom?.window.close();
  dom = null;
  for (const [key, value] of saved) {
    if (value === undefined) delete (globalThis as Record<string, unknown>)[key];
    else (globalThis as Record<string, unknown>)[key] = value;
  }
});

function mount(automation: AutomationDTO, store: object): HTMLElement {
  dom = new JSDOM("<!doctype html><html><body><div id='root'></div></body></html>", { url: "http://127.0.0.1/" });
  const g = globalThis as Record<string, unknown>;
  g.window = dom.window;
  g.document = dom.window.document;
  g.navigator = dom.window.navigator;
  g.Element = dom.window.Element;
  g.Node = dom.window.Node;
  g.HTMLElement = dom.window.HTMLElement;
  const container = dom.window.document.getElementById("root")!;
  root = createRoot(container);
  flushSync(() => root?.render(<AutomationCard store={store as never} automation={automation} label={label} focused={false} />));
  return container;
}

test("nameOpensDetail", () => {
  const calls: string[] = [];
  const store = {
    openDetail: (id: string) => (calls.push(`openDetail:${id}`), Promise.resolve()),
    markRead: (id: string) => (calls.push(`markRead:${id}`), Promise.resolve()),
  };
  let container = mount(base, store);
  container.querySelector<HTMLButtonElement>(".au-name-button")!.click();
  expect(calls).toEqual(["openDetail:a1"]);

  flushSync(() => root?.unmount());
  root = null;
  calls.length = 0;
  container = mount({ ...base, lastRun: { ...run, status: "done", unread: true } }, store);
  container.querySelector<HTMLButtonElement>(".au-name-button")!.click();
  expect(calls.sort()).toEqual(["markRead:a1", "openDetail:a1"]);
});

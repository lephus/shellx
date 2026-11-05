import { expect, test } from "bun:test";
import { buildChart, layoutChart, usableFlow, type ChartModel, type ChartSource, type PlacedNode } from "./flowChartModel";
import { createAutomationLabelResolver } from "./labels";
import type { AutomationFlow } from "./types";

const label = createAutomationLabelResolver();

/** Shaped like the disk-cleanup skill: measure, report, ask, then delete or stop. */
const diskFlow: AutomationFlow = {
  trigger: "When the disk is full",
  nodes: [
    { id: "measure", type: "step", label: "Measure disk usage" },
    { id: "report", type: "step", label: "Report what takes space" },
    { id: "approve", type: "askUser", label: "Approve?" },
    { id: "delete", type: "step", label: "Delete approved items" },
    { id: "measure-again", type: "step", label: "Measure again" },
    { id: "end", type: "end", label: "Done" },
    { id: "stop", type: "end", label: "Stop" },
  ],
  edges: [
    { from: "measure", to: "report" },
    { from: "report", to: "approve" },
    { from: "approve", to: "delete", label: "Yes" },
    { from: "approve", to: "stop", label: "No" },
    { from: "delete", to: "measure-again" },
    { from: "measure-again", to: "end" },
  ],
};

const workflow: ChartSource = {
  kind: "workflow",
  description: "Digest",
  schedule: { cron: "0 9 * * 1", human: "Mondays 09:00" },
  notify: { on: ["done"], targets: ["mac"] },
  steps: [
    { title: "Fetch", prompt: "p1" },
    { title: "Summarize", prompt: "p2" },
  ],
  flow: null,
};

const skill: ChartSource = {
  kind: "skill",
  description: "Frees disk space",
  notify: { on: [], targets: [] },
  steps: [],
  flow: diskFlow,
};

function chart(source: ChartSource): ChartModel {
  const model = buildChart(source, label);
  if (!model) throw new Error("expected a chart");
  return model;
}

function placed(nodes: PlacedNode[], id: string): PlacedNode {
  const node = nodes.find((n) => n.id === id);
  if (!node) throw new Error(`missing node ${id}`);
  return node;
}

const centerX = (n: PlacedNode) => n.x + n.w / 2;

test("usableFlowRejectsBadData", () => {
  const node = { id: "a", type: "step", label: "A" };
  expect(usableFlow(null)).toBeNull();
  expect(usableFlow({ nodes: [], edges: [] })).toBeNull();
  expect(usableFlow({ nodes: [] })).toBeNull();
  expect(usableFlow({ nodes: [node, { ...node }], edges: [] })).toBeNull();
  expect(usableFlow({ nodes: [node], edges: [{ from: "a", to: "ghost" }] })).toBeNull();
  expect(usableFlow({ nodes: [{ ...node, type: "loop" }], edges: [] })).toBeNull();
  expect(usableFlow(diskFlow)).toEqual(diskFlow);
});

test("workflowChart", () => {
  const model = chart(workflow);
  expect(model.nodes.map((n) => n.id)).toEqual(["start", "step-1", "step-2", "notify"]);
  expect(model.nodes[0]?.label).toBe("Mondays 09:00");
  expect(model.nodes.filter((n) => n.shape === "step").map((n) => n.number)).toEqual([1, 2]);
  expect(model.edges).toEqual([
    { from: "start", to: "step-1" },
    { from: "step-1", to: "step-2" },
    { from: "step-2", to: "notify" },
  ]);
  expect(model.nodes[3]?.label).toBe("Notify Mac · When done");
  const manual = chart({ ...workflow, schedule: null });
  expect(manual.nodes[0]?.label).toBe("Runs when you press Run now");
});

test("workflowWithoutNotifyEndsDone", () => {
  const model = chart({ ...workflow, notify: { on: [], targets: ["mac"] } });
  const last = model.nodes[model.nodes.length - 1];
  expect(last).toEqual({ id: "done", shape: "end", label: "Done" });
  expect(model.nodes.some((n) => n.id === "notify")).toBe(false);
  expect(model.edges).toContainEqual({ from: "step-2", to: "done" });
});

test("skillChartUsesTrigger", () => {
  const model = chart(skill);
  expect(model.nodes[0]).toEqual({ id: "start", shape: "start", label: "When the disk is full" });
  expect(model.edges).toContainEqual({ from: "start", to: "measure" });
  expect(model.nodes.some((n) => n.id === "notify" || n.id === "done")).toBe(false);
  expect(model.nodes.filter((n) => n.shape === "step").map((n) => [n.id, n.number])).toEqual([
    ["measure", 1],
    ["report", 2],
    ["delete", 3],
    ["measure-again", 4],
  ]);
  const long = "x".repeat(100);
  const fromDescription = chart({ ...skill, description: long, flow: { ...diskFlow, trigger: undefined } });
  expect(Array.from(fromDescription.nodes[0]?.label ?? "")).toHaveLength(80);
  expect(fromDescription.nodes[0]?.label.endsWith("…")).toBe(true);
});

test("cronjobAddsNotifyAfterTerminals", () => {
  const model = chart({ ...skill, kind: "cronjob", schedule: { cron: "0 8 * * *", human: "8:00" }, notify: { on: ["done", "failed"], targets: ["mac", "iphone"] } });
  expect(model.nodes[0]?.label).toBe("8:00");
  expect(model.edges).toContainEqual({ from: "end", to: "notify" });
  expect(model.edges).toContainEqual({ from: "stop", to: "notify" });
  expect(model.edges.filter((e) => e.to === "notify")).toHaveLength(2);
  expect(model.nodes[model.nodes.length - 1]?.label).toBe(
    "Notify Mac + iPhone (after the next update) · When done, When failed",
  );
});

test("skillWithoutFlowIsNull", () => {
  expect(buildChart({ ...skill, flow: null }, label)).toBeNull();
  expect(buildChart({ ...skill, kind: "cronjob", flow: null }, label)).toBeNull();
  const broken = { ...diskFlow, edges: [{ from: "measure", to: "ghost" }] };
  expect(buildChart({ ...skill, flow: broken }, label)).toBeNull();
});

test("flowIdsThatClashWithChartIdsAreRenamed", () => {
  const flow: AutomationFlow = {
    nodes: [
      { id: "start", type: "step", label: "Begin" },
      { id: "notify", type: "step", label: "Tell the team" },
    ],
    edges: [{ from: "start", to: "notify" }],
  };
  const model = chart({ ...skill, kind: "cronjob", notify: { on: ["done"], targets: ["mac"] }, flow });
  expect(model.nodes.map((n) => n.id)).toEqual(["start", "flow-start", "flow-notify", "notify"]);
  expect(model.edges).toEqual([
    { from: "start", to: "flow-start" },
    { from: "flow-start", to: "flow-notify" },
    { from: "flow-notify", to: "notify" },
  ]);
});

test("layoutBranchGoesRight", () => {
  const layout = layoutChart(chart(skill));
  const ask = placed(layout.nodes, "approve");
  expect(placed(layout.nodes, "stop").x).toBeGreaterThan(ask.x);
  expect(centerX(placed(layout.nodes, "delete"))).toBe(centerX(ask));
  const main = ["start", "measure", "report", "approve", "delete", "measure-again", "end"];
  const ys = main.map((id) => placed(layout.nodes, id).y);
  for (let i = 1; i < ys.length; i++) expect(ys[i]).toBeGreaterThan(ys[i - 1] ?? 0);
  for (const node of layout.nodes) {
    expect(node.x + node.w).toBeLessThanOrEqual(layout.width);
    expect(node.y + node.h).toBeLessThanOrEqual(layout.height);
  }
});

test("layoutRoutesLoopOutside", () => {
  const looped = { ...diskFlow, edges: [...diskFlow.edges, { from: "measure-again", to: "measure" }] };
  const layout = layoutChart(chart({ ...skill, flow: looped }));
  const back = layout.edges.find((e) => e.from === "measure-again" && e.to === "measure");
  expect(back?.back).toBe(true);
  expect(layout.edges.filter((e) => e.back)).toHaveLength(1);
  const points = back?.points ?? [];
  const maxRight = Math.max(...layout.nodes.map((n) => n.x + n.w));
  const source = placed(layout.nodes, "measure-again");
  const target = placed(layout.nodes, "measure");
  // It leaves the source's right edge and enters the target's right edge; everything between is in the lane.
  expect(points[0]).toEqual([source.x + source.w, source.y + source.h / 2]);
  expect(points[points.length - 1]).toEqual([target.x + target.w, target.y + target.h / 2]);
  const lane = points.slice(1, -1);
  expect(lane.length).toBeGreaterThan(0);
  for (const [x] of lane) expect(x).toBeGreaterThanOrEqual(maxRight);
  for (const [x] of lane) expect(x).toBeLessThanOrEqual(layout.width);
});

test("wrapsLongLabels", () => {
  const text = "abcdefghi ".repeat(20);
  expect(text).toHaveLength(200);
  const layout = layoutChart({
    nodes: [
      { id: "start", shape: "start", label: "Go" },
      { id: "a", shape: "step", label: text, number: 1 },
    ],
    edges: [{ from: "start", to: "a" }],
  });
  const lines = placed(layout.nodes, "a").lines;
  expect(lines).toHaveLength(3);
  expect(lines[2]?.endsWith("…")).toBe(true);
  for (const line of lines) expect(Array.from(line).length).toBeLessThanOrEqual(36);
});

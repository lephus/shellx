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

const flowNode = (id: string, type: AutomationFlow["nodes"][number]["type"] = "step") => ({ id, type, label: id });
const layoutOf = (flow: AutomationFlow) => layoutChart(chart({ ...skill, flow }));

/** Ids of the boxes, other than its own two ends, that an edge's segments pass through. */
function crossedBoxes(layout: ReturnType<typeof layoutChart>): string[] {
  const hits: string[] = [];
  for (const edge of layout.edges) {
    edge.points.forEach(([x1, y1], i) => {
      const next = edge.points[i + 1];
      if (!next) return;
      const [x2, y2] = next;
      for (const n of layout.nodes) {
        if (n.id === edge.from || n.id === edge.to) continue;
        const crosses =
          Math.max(x1, x2) > n.x && Math.min(x1, x2) < n.x + n.w && Math.max(y1, y2) > n.y && Math.min(y1, y2) < n.y + n.h;
        if (crosses) hits.push(`${edge.from}->${edge.to} crosses ${n.id}`);
      }
    });
  }
  return hits;
}

test("edgesNeverCrossOtherBoxes", () => {
  // A side branch's drop into its column would run through a later side step.
  const elbowRight: AutomationFlow = {
    nodes: [flowNode("a"), flowNode("d1", "decision"), flowNode("b"), flowNode("d2", "decision"), flowNode("c"), flowNode("e", "end"), flowNode("y"), flowNode("x", "end")],
    edges: [
      { from: "a", to: "d1" },
      { from: "d1", to: "b", label: "Yes" },
      { from: "d1", to: "x", label: "No" },
      { from: "b", to: "d2" },
      { from: "d2", to: "c", label: "Yes" },
      { from: "d2", to: "y", label: "No" },
      { from: "y", to: "x" },
      { from: "c", to: "e" },
    ],
  };
  // A side branch merging back left would run down its column through a later side step.
  const mergeLeft: AutomationFlow = {
    nodes: [flowNode("a"), flowNode("d1", "decision"), flowNode("b"), flowNode("d2", "decision"), flowNode("c"), flowNode("p"), flowNode("q"), flowNode("e", "end")],
    edges: [
      { from: "a", to: "d1" },
      { from: "d1", to: "b", label: "Yes" },
      { from: "d1", to: "p", label: "No" },
      { from: "b", to: "d2" },
      { from: "d2", to: "c", label: "Yes" },
      { from: "d2", to: "q", label: "No" },
      { from: "p", to: "e" },
      { from: "q", to: "c" },
      { from: "c", to: "e" },
    ],
  };
  // A loop's stub to the lane would run through a side sibling in the same row.
  const backStub: AutomationFlow = {
    nodes: [flowNode("a"), flowNode("d", "decision"), flowNode("b"), flowNode("z"), flowNode("e", "end")],
    edges: [
      { from: "a", to: "d" },
      { from: "d", to: "b", label: "Yes" },
      { from: "d", to: "z", label: "No" },
      { from: "b", to: "a" },
      { from: "b", to: "e" },
      { from: "z", to: "e" },
    ],
  };
  const looped = { ...diskFlow, edges: [...diskFlow.edges, { from: "measure-again", to: "measure" }] };
  for (const flow of [elbowRight, mergeLeft, backStub, diskFlow, looped]) {
    const layout = layoutOf(flow);
    expect(crossedBoxes(layout)).toEqual([]);
    for (const edge of layout.edges) {
      for (const [x, y] of edge.points) {
        expect(x).toBeGreaterThanOrEqual(0);
        expect(y).toBeGreaterThanOrEqual(0);
        expect(x).toBeLessThanOrEqual(layout.width);
        expect(y).toBeLessThanOrEqual(layout.height);
      }
    }
  }
  expect(layoutOf(backStub).edges.find((e) => e.from === "b" && e.to === "a")?.back).toBe(true);
});

test("branchLabelsDoNotOverlap", () => {
  const threeWay: AutomationFlow = {
    nodes: [flowNode("d", "decision"), flowNode("a"), flowNode("b"), flowNode("c"), flowNode("e", "end")],
    edges: [
      { from: "d", to: "a", label: "Small" },
      { from: "d", to: "b", label: "Medium" },
      { from: "d", to: "c", label: "Large" },
      { from: "a", to: "e" },
      { from: "b", to: "e" },
      { from: "c", to: "e" },
    ],
  };
  const layout = layoutOf(threeWay);
  const labelled = layout.edges.filter((e) => e.label !== undefined);
  expect(labelled).toHaveLength(3);
  // Text boxes of 11px labels: about 6.2 px per character, baseline at y.
  const boxes = labelled.map((e) => {
    const [x, y] = e.labelAt ?? [Number.NaN, Number.NaN];
    return { x, y, w: (e.label ?? "").length * 6.2, h: 12, edge: e };
  });
  for (const box of boxes) {
    expect(Number.isFinite(box.x) && Number.isFinite(box.y)).toBe(true);
    // Each label sits beside a segment of its own edge.
    const near = box.edge.points.some(([x1, y1], i) => {
      const [x2, y2] = box.edge.points[i + 1] ?? [x1, y1];
      const dx = Math.max(Math.min(x1, x2) - box.x, 0, box.x - Math.max(x1, x2));
      const dy = Math.max(Math.min(y1, y2) - box.y, 0, box.y - Math.max(y1, y2));
      return i + 1 < box.edge.points.length && Math.hypot(dx, dy) <= 16;
    });
    expect(near).toBe(true);
  }
  for (let i = 0; i < boxes.length; i++) {
    for (let j = i + 1; j < boxes.length; j++) {
      const a = boxes[i];
      const b = boxes[j];
      if (!a || !b) continue;
      const overlap = a.x < b.x + b.w && b.x < a.x + a.w && a.y - a.h < b.y && b.y - b.h < a.y;
      expect(overlap).toBe(false);
    }
  }
});

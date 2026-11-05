import { expect, test } from "bun:test";
import { renderToStaticMarkup } from "react-dom/server";
import { FlowChart } from "./FlowChart";
import { buildChart, layoutChart, type ChartSource } from "./flowChartModel";
import { createAutomationLabelResolver } from "./labels";

const label = createAutomationLabelResolver();

const skill: ChartSource = {
  kind: "skill",
  description: "Frees disk space",
  notify: { on: [], targets: [] },
  steps: [],
  flow: {
    trigger: "When the disk is full",
    nodes: [
      { id: "measure", type: "step", label: "Measure disk usage", detail: "du -sh on the caches" },
      { id: "anything", type: "decision", label: "Anything to clean?" },
      { id: "approve", type: "askUser", label: "Approve?" },
      { id: "delete", type: "step", label: "Delete approved items" },
      { id: "end", type: "end", label: "Done" },
      { id: "stop", type: "end", label: "Stop" },
    ],
    edges: [
      { from: "measure", to: "anything" },
      { from: "anything", to: "approve", label: "Yes" },
      { from: "anything", to: "end", label: "No" },
      { from: "approve", to: "delete", label: "Yes" },
      { from: "approve", to: "stop", label: "No" },
      { from: "delete", to: "end" },
    ],
  },
};

const workflow: ChartSource = {
  kind: "workflow",
  description: "Digest",
  notify: { on: ["done"], targets: ["mac"] },
  steps: [
    { title: "Fetch", prompt: "p1" },
    { title: "Summarize", prompt: "p2" },
    { title: "Write", prompt: "p3" },
  ],
  flow: null,
};

function render(source: ChartSource, runningNodeId?: string): { html: string; shapes: string[] } {
  const model = buildChart(source, label);
  if (!model) throw new Error("expected a chart");
  const layout = layoutChart(model);
  const html = renderToStaticMarkup(<FlowChart layout={layout} label={label} runningNodeId={runningNodeId} />);
  return { html, shapes: layout.nodes.map((n) => n.shape) };
}

test("rendersShapesAndA11yList", () => {
  const { html, shapes } = render(skill);
  expect((html.match(/<polygon/g) ?? []).length).toBe(2);
  expect([...html.matchAll(/data-shape="(\w+)"/g)].map((m) => m[1])).toEqual(shapes);
  expect([...shapes].sort()).toEqual(["askUser", "decision", "end", "end", "start", "step", "step"]);
  expect(html).toContain("<title>du -sh on the caches</title>");

  const list = html.slice(html.indexOf('<ol class="au-visually-hidden"'));
  expect(list.length).toBeLessThan(html.length);
  const listed = [...list.matchAll(/<span class="au-flow-a11y-node">([^<]*)<\/span>/g)].map((m) => m[1]);
  expect(listed).toEqual([
    "When the disk is full",
    "Measure disk usage",
    "Anything to clean?",
    "Approve?",
    "Delete approved items",
    "Stop",
    "Done",
  ]);
  expect(list).toContain("Approve? → No: Stop");
  expect(list).toContain("Approve? → Yes: Delete approved items");
  expect(list).toContain("Anything to clean? → No: Done");
});

test("marksRunningNode", () => {
  const { html } = render(workflow, "step-2");
  expect((html.match(/data-running="true"/g) ?? []).length).toBe(1);
  expect(html).toMatch(/data-node="step-2"[^>]*data-running="true"/);
  expect(html).toContain("● running");
  expect(render(workflow).html).not.toContain("● running");
});

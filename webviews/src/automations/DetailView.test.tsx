import { expect, test } from "bun:test";
import { renderToStaticMarkup } from "react-dom/server";
import { DetailView } from "./DetailView";
import { createAutomationLabelResolver } from "./labels";
import type { DetailState } from "./store";
import type { AutomationDetail, AutomationDTO } from "./types";

const label = createAutomationLabelResolver();
const automation: AutomationDTO = {
  id: "a1",
  kind: "skill",
  name: "release-notes",
  description: "Writes the release notes",
  notify: { on: [], targets: [] },
  allowedTools: [],
  steps: [],
  enabled: true,
  origin: "shellx",
  createdAt: "2026-11-03T10:00:00Z",
  updatedAt: "2026-11-03T10:00:00Z",
  iphonePending: false,
};
const markdown = "---\nname: release-notes\n---\nRead the merged PRs.\n";

function render(data: Partial<AutomationDetail>, over: Partial<DetailState> = {}): string {
  const detail: DetailState = {
    id: "a1",
    loading: false,
    data: { automation, skillMarkdown: markdown, flow: null, flowStatus: "missing", ...data },
    error: null,
    drawing: false,
    mode: "flow",
    ...over,
  };
  return renderToStaticMarkup(<DetailView store={{} as never} detail={detail} actionError={null} label={label} />);
}

const flow = {
  nodes: [
    { id: "read", type: "step" as const, label: "Read the merged PRs" },
    { id: "end", type: "end" as const, label: "Done" },
  ],
  edges: [{ from: "read", to: "end" }],
};

test("missingShowsDrawButton", () => {
  const html = render({ flowStatus: "missing" });
  expect(html).toContain("This automation has no flowchart yet");
  expect(html).toContain(">Draw flowchart</button>");
  expect(html).toContain("Claude reads SKILL.md and draws it, it takes a few seconds");
  expect(html).not.toContain("au-flow-svg");
  const drawing = render({ flowStatus: "missing" }, { drawing: true });
  expect(drawing).toMatch(/<button[^>]*disabled=""[^>]*>Drawing…<\/button>/);
  const failed = render({ flowStatus: "missing" }, { error: "Claude could not draw the flowchart: timeout" });
  expect(failed).toContain("Claude could not draw the flowchart: timeout");
  expect(failed).toContain(">Draw flowchart</button>");
});

test("staleShowsChangedText", () => {
  const html = render({ flowStatus: "stale", flow });
  expect(html).toContain("The content changed since the flowchart was drawn");
  expect(html).not.toContain("This automation has no flowchart yet");
  expect(html).toContain(">Draw flowchart</button>");
  expect(html).not.toContain("au-flow-svg");
});

test("currentShowsChartAndCaption", () => {
  const html = render({ flowStatus: "current", flow });
  expect(html).toContain("au-flow-svg");
  expect(html).toContain('data-node="read"');
  expect(html).toContain("Drawn by Claude from SKILL.md · see Text for the details");
  expect(html).not.toContain(">Draw flowchart</button>");
  expect(html).toContain("← Back");
  expect(html).toContain("release-notes");
  expect(html).toContain("Writes the release notes");
  expect(html).toContain(">Edit file<");
});

test("workflowRunningHighlightsStep", () => {
  const workflow: AutomationDTO = {
    ...automation,
    kind: "workflow",
    steps: [
      { title: "Fetch", prompt: "Fetch the PRs" },
      { title: "Summarize", prompt: "Summarize them" },
      { title: "Post", prompt: "Post the summary" },
    ],
    lastRun: { status: "running", trigger: "manual", startedAt: "2026-11-03T10:00:00Z", currentStep: 2, totalSteps: 3, unread: false },
  };
  const html = render({ automation: workflow, flowStatus: "derived" });
  expect(html).toMatch(/data-node="step-2"[^>]*data-running="true"/);
  expect(html).not.toMatch(/data-node="step-1"[^>]*data-running/);
  expect(html).toContain("Step 2/3");
  expect(html).not.toContain("Drawn by Claude from SKILL.md");
});

test("textModeIsReadOnly", () => {
  const html = render({ flowStatus: "current", flow }, { mode: "text" });
  expect(html).not.toContain("<textarea");
  expect(html).not.toContain("au-flow-svg");
  expect(html).toContain('<pre class="au-pre">---\nname: release-notes\n---\nRead the merged PRs.\n</pre>');
  const workflow = render(
    { automation: { ...automation, kind: "workflow", steps: [{ title: "Fetch", prompt: "Fetch the PRs" }] }, flowStatus: "derived" },
    { mode: "text" },
  );
  expect(workflow).toMatch(/<ol[^>]*>.*Fetch.*Fetch the PRs.*<\/ol>/s);
  expect(workflow).toContain('<pre class="au-pre">');
});

test("refreshErrorShowsAboveChart: a failed refresh is said above the chart it keeps", () => {
  const html = render({ flowStatus: "current", flow }, { error: "SKILL.md could not be read" });
  const alert = html.indexOf("SKILL.md could not be read");
  expect(alert).toBeGreaterThan(-1);
  expect(alert).toBeLessThan(html.indexOf("au-flow-svg"));
  expect(html).toMatch(/role="alert"[^>]*>SKILL.md could not be read/);
  const text = render({ flowStatus: "current", flow }, { error: "SKILL.md could not be read", mode: "text" });
  expect(text.indexOf("SKILL.md could not be read")).toBeLessThan(text.indexOf('<pre class="au-pre">'));
  expect(text.indexOf("SKILL.md could not be read")).toBeGreaterThan(-1);
  expect(render({ flowStatus: "current", flow })).not.toContain('role="alert"');
});

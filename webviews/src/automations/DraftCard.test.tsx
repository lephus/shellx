import { expect, test } from "bun:test";
import { renderToStaticMarkup } from "react-dom/server";
import { DraftCard } from "./DraftCard";
import { createAutomationLabelResolver } from "./labels";
import type { DraftViewMode } from "./store";
import type { AutomationDraft, ValidationIssueDTO } from "./types";

const label = createAutomationLabelResolver();
const empty: AutomationDraft = {
  kind: "",
  name: "",
  description: "",
  notify: { on: [], targets: [] },
  allowedTools: [],
  steps: [],
  skillMarkdown: "",
};

function render(
  draft: AutomationDraft,
  issues: ValidationIssueDTO[] = [],
  ready = false,
  view: DraftViewMode = "text",
  flowCurrent = true,
  locked = false,
): string {
  return renderToStaticMarkup(
    <DraftCard
      label={label}
      draft={draft}
      issues={issues}
      ready={ready}
      view={view}
      onViewChange={() => {}}
      flowCurrent={flowCurrent}
      locked={locked}
    />,
  );
}

test("fields appear only once they are non-empty", () => {
  const empty1 = render(empty);
  expect(empty1).not.toContain("Schedule");
  expect(empty1).not.toContain("Directory");
  expect(empty1).not.toContain("Notify");
  const html = render({
    ...empty,
    kind: "cronjob",
    name: "pr-digest",
    schedule: { cron: "0 8 * * *", human: "8:00 every day" },
    workingDirectory: "/tmp/x",
  });
  expect(html).toContain("pr-digest");
  expect(html).toContain("8:00 every day");
  expect(html).toContain("0 8 * * *");
  expect(html).toContain("/tmp/x");
  expect(html).not.toContain("Notify");
  expect(html).toContain("drafting…");
  expect(render({ ...empty, name: "x" }, [], true)).toContain("✓ ready");
});

test("issues render under their field and model text stays text", () => {
  const html = render({ ...empty, name: "<b>Bad</b>" }, [
    { field: "name", code: "invalidName", message: "Use lowercase <i>words</i>" },
    { field: "claude", code: "missing", message: "Claude Code not found" },
  ]);
  expect(html).toContain("&lt;b&gt;Bad&lt;/b&gt;");
  expect(html).not.toContain("<b>Bad");
  expect(html).toContain("Use lowercase &lt;i&gt;words&lt;/i&gt;");
  const nameRow = html.indexOf('data-field="name"');
  expect(nameRow).toBeGreaterThan(-1);
  expect(html.indexOf("Use lowercase")).toBeGreaterThan(nameRow);
  expect(html).toContain("Claude Code not found");
});

test("a steps issue shows under the steps field even with no steps", () => {
  const html = render({ ...empty, kind: "workflow", name: "x" }, [
    { field: "steps", code: "missing", message: "A workflow needs at least one step." },
  ]);
  const stepsRow = html.indexOf('data-field="steps"');
  expect(stepsRow).toBeGreaterThan(-1);
  expect(html.indexOf("A workflow needs at least one step.")).toBeGreaterThan(stepsRow);
});

test("the iPhone target shows the pending label", () => {
  const html = render({ ...empty, name: "x", notify: { on: ["done"], targets: ["mac", "iphone"] } });
  expect(html).toContain("When done");
  expect(html).toContain("iPhone (after the next update)");
  expect(render({ ...empty, name: "x", notify: { on: ["done"], targets: ["mac"] } })).not.toContain("after the next update");
});

test("with onEdit, name, description and SKILL.md are editable fields", () => {
  const draft = { ...empty, kind: "skill" as const, name: "n", description: "d", skillMarkdown: "---\nname: n\n---\n" };
  const html = renderToStaticMarkup(
    <DraftCard label={label} draft={draft} issues={[]} ready onEdit={() => {}} locked view="text" onViewChange={() => {}} flowCurrent />,
  );
  expect(html).toContain('<input class="au-edit"');
  expect((html.match(/<textarea/g) ?? []).length).toBe(2);
  expect((html.match(/readOnly=""|readonly=""/g) ?? []).length).toBe(3);
  expect(render(draft)).not.toContain("<textarea");
});

const flow = {
  nodes: [
    { id: "a", type: "step" as const, label: "Fetch the PRs" },
    { id: "b", type: "step" as const, label: "Write the digest" },
  ],
  edges: [{ from: "a", to: "b" }],
};
const skill: AutomationDraft = {
  ...empty,
  kind: "skill",
  name: "pr-digest",
  description: "Digest PRs",
  skillMarkdown: "---\nname: pr-digest\n---\nBody",
  flow,
};

test("defaultsToFlowchart: a skill draft with a usable flow shows the chart and the caption", () => {
  const html = renderToStaticMarkup(
    <DraftCard label={label} draft={skill} issues={[]} ready onEdit={() => {}} view="flow" onViewChange={() => {}} flowCurrent />,
  );
  expect(html).toContain("<svg");
  expect(html).toContain("Fetch the PRs");
  expect(html).toContain(label("flowCaption"));
  expect((html.match(/<textarea/g) ?? []).length).toBe(1);
  expect(html).not.toContain('data-field="skillMarkdown"');
  expect(html).toMatch(/aria-pressed="true"[^>]*>Flowchart/);
  expect(html).toMatch(/aria-pressed="false"[^>]*>Text/);
  expect(html).not.toContain(label("flowOutdated"));
});

test("switchShowsText: the Text view is today's card and its fields stay editable", () => {
  const html = renderToStaticMarkup(
    <DraftCard label={label} draft={skill} issues={[]} ready onEdit={() => {}} view="text" onViewChange={() => {}} flowCurrent />,
  );
  expect(html).not.toContain("<svg");
  expect(html).not.toContain(label("flowCaption"));
  expect((html.match(/<textarea/g) ?? []).length).toBe(2);
  expect(html).toContain('data-field="skillMarkdown"');
  expect(html).toMatch(/aria-pressed="true"[^>]*>Text/);
});

test("earlyDraftShowsDrawing: a skill draft with a name and no flow says Claude is drawing", () => {
  const html = render({ ...skill, flow: undefined }, [], false, "flow");
  expect(html).toContain(label("flowDrawing"));
  expect(html).not.toContain("<svg");
});

test("workflowNeedsNoFlow: a workflow draft with steps renders the chart without a placeholder or caption", () => {
  const html = render(
    { ...empty, kind: "workflow", name: "w", steps: [{ title: "Pull", prompt: "p" }, { title: "Push", prompt: "q" }] },
    [],
    true,
    "flow",
  );
  expect(html).toContain("<svg");
  expect(html).toContain("Pull");
  expect(html).not.toContain(label("flowDrawing"));
  expect(html).not.toContain(label("flowCaption"));
});

test("badFlowFallsBackToText: an edge to an unknown node shows the Text fields", () => {
  const bad = { ...skill, flow: { nodes: flow.nodes, edges: [{ from: "a", to: "zzz" }] } };
  const html = render(bad, [], true, "flow");
  expect(html).not.toContain("<svg");
  expect(html).not.toContain(label("flowDrawing"));
  expect(html).toContain('data-field="skillMarkdown"');
});

test("an out-of-date chart is dimmed with a note, and busy while locked", () => {
  const html = render(skill, [], true, "flow", false, true);
  expect(html).toContain(label("flowOutdated"));
  expect(html).toContain("<svg");
  expect(html).toContain('data-busy="true"');
  expect(render(skill, [], true, "flow", true, false)).not.toContain('data-busy="true"');
});

test("issues on hidden fields still show in the flow view", () => {
  const html = render(skill, [{ field: "skillMarkdown", code: "bad", message: "SKILL.md is broken" }], false, "flow");
  expect(html).toContain("SKILL.md is broken");
});

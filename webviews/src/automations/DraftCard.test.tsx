import { expect, test } from "bun:test";
import { renderToStaticMarkup } from "react-dom/server";
import { DraftCard } from "./DraftCard";
import { createAutomationLabelResolver } from "./labels";
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

function render(draft: AutomationDraft, issues: ValidationIssueDTO[] = [], ready = false): string {
  return renderToStaticMarkup(<DraftCard label={label} draft={draft} issues={issues} ready={ready} />);
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

test("the iPhone target shows the pending label", () => {
  const html = render({ ...empty, name: "x", notify: { on: ["done"], targets: ["mac", "iphone"] } });
  expect(html).toContain("When done");
  expect(html).toContain("iPhone (after the next update)");
  expect(render({ ...empty, name: "x", notify: { on: ["done"], targets: ["mac"] } })).not.toContain("after the next update");
});

import { expect, test } from "bun:test";
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

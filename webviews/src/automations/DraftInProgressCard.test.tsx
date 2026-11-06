import { expect, test } from "bun:test";
import { renderToStaticMarkup } from "react-dom/server";
import { DraftInProgressCard } from "./DraftInProgressCard";
import { createAutomationLabelResolver } from "./labels";
import type { CreatorState } from "./store";

const label = createAutomationLabelResolver();
const store = {} as never;

function creator(over: Partial<CreatorState>): CreatorState {
  return {
    messages: [{ id: 1, role: "user", text: "Digest my PRs every morning" }],
    streaming: null,
    draft: null,
    issues: [],
    busy: false,
    type: "auto",
    saving: false,
    editId: null,
    draftDirty: false,
    draftView: "flow",
    flowCurrent: false,
    ...over,
  };
}

test("a draft in progress shows as a Draft card with Continue and Discard", () => {
  const html = renderToStaticMarkup(<DraftInProgressCard store={store} creator={creator({})} label={label} automations={[]} />);
  expect(html).toContain(`>${label("draftBadge")}<`);
  expect(html).toContain(label("untitledDraft"));
  expect(html).toContain("Digest my PRs every morning");
  expect(html).toContain(`>${label("continueDraft")}<`);
  expect(html).toContain(`>${label("discard")}<`);
});

test("the card names the draft and shows Claude thinking while it works", () => {
  const draft = {
    kind: "cronjob" as const, name: "pr-digest", description: "Digest PRs", notify: { on: [], targets: [] },
    allowedTools: [], steps: [], skillMarkdown: "x",
  };
  const html = renderToStaticMarkup(
    <DraftInProgressCard store={store} creator={creator({ draft, busy: true })} label={label} automations={[]} />,
  );
  expect(html).toContain("pr-digest");
  expect(html).toContain("Digest PRs");
  expect(html).toContain(label("thinking"));
});

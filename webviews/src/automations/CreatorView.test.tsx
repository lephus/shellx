import { expect, test } from "bun:test";
import { renderToStaticMarkup } from "react-dom/server";
import { CreatorView } from "./CreatorView";
import { createAutomationLabelResolver } from "./labels";
import type { CreatorState } from "./store";

const label = createAutomationLabelResolver();
const store = {} as never;
const draft = {
  kind: "skill" as const, name: "pr-digest", description: "Digest PRs", notify: { on: [], targets: [] },
  allowedTools: [], steps: [], skillMarkdown: "x",
};

function render(over: Partial<CreatorState>, reduceMotion = false): string {
  const creator: CreatorState = {
    messages: [{ id: 1, role: "user", text: "hi" }],
    streaming: null, draft: null, issues: [], busy: false, type: "auto", saving: false, editId: null, draftDirty: false, draftView: "flow", flowCurrent: false, ...over,
  };
  return renderToStaticMarkup(<CreatorView store={store} creator={creator} label={label} reduceMotion={reduceMotion} />);
}

test("the draft pane shows Claude working, before and after a draft exists", () => {
  for (const html of [render({ busy: true }), render({ busy: true, draft })]) {
    expect(html).toContain('class="au-draft-pane" data-busy="true"');
    expect(html).toContain(label("draftWorking"));
  }
});

test("an idle draft pane shows no loading text", () => {
  const html = render({ busy: false, draft });
  expect(html).toContain('data-busy="false"');
  expect(html).not.toContain(label("draftWorking"));
});

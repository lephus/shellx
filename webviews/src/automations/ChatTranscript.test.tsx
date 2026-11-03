import { expect, test } from "bun:test";
import { renderToStaticMarkup } from "react-dom/server";
import { ChatTranscript } from "./ChatTranscript";
import { createAutomationLabelResolver } from "./labels";
import type { ChatMessage } from "./store";

const label = createAutomationLabelResolver();
const sent: ChatMessage[] = [{ id: 1, role: "user", text: "Make a skill" }];

function render(busy: boolean, streaming: string | null): string {
  return renderToStaticMarkup(
    <ChatTranscript label={label} messages={sent} streaming={streaming} busy={busy} onAnswer={() => {}} />,
  );
}

test("shows that Claude is thinking while it works and has written nothing yet", () => {
  const html = render(true, null);
  expect(html).toContain('data-thinking="true"');
  expect(html).toContain(label("thinking"));
});

test("hides the thinking row once Claude's reply streams in or it is idle", () => {
  expect(render(true, "Sure")).not.toContain('data-thinking="true"');
  expect(render(false, null)).not.toContain('data-thinking="true"');
});

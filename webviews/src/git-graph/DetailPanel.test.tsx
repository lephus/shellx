import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { DetailPanel } from "./DetailPanel";
import { createGitGraphLabelResolver } from "./labels";
import type { GitGraphCommit } from "./types";

const label = createGitGraphLabelResolver();
const sha = "0123456789abcdef0123456789abcdef01234567";
const commit: GitGraphCommit = {
  sha,
  parents: ["fedcba9876543210fedcba9876543210fedcba98"],
  source: "main",
  authorName: "Ann",
  authorEmail: "ann@example.com",
  authorDate: "2026-10-26T10:00:00+07:00",
  committerDate: "2026-10-26T10:00:00+07:00",
  subject: "Fix <b>bold</b> parsing",
};

function render(message: string | null): string {
  return renderToStaticMarkup(
    <DetailPanel
      label={label}
      selectedSha={sha}
      commit={commit}
      workingTree={null}
      files={null}
      filesState="idle"
      message={message}
      onOpenFile={() => {}}
    />,
  );
}

test("the detail pane shows the full message as text and the full hash", () => {
  const html = render("Fix <b>bold</b> parsing\n\n<script>alert(1)</script> keeps\n  its line breaks.\n");
  expect(html).toContain('<h2 class="gg-detail-subject">Fix &lt;b&gt;bold&lt;/b&gt; parsing</h2>');
  expect(html).toContain('<p class="gg-detail-body">&lt;script&gt;alert(1)&lt;/script&gt; keeps\n  its line breaks.</p>');
  expect(html).not.toContain("<b>");
  expect(html).not.toContain("<script>");
  expect(html).toContain(`<span class="gg-mono gg-detail-sha">${sha}</span>`);
});

test("until the message is read, the log's subject stands in and there is no body", () => {
  const html = render(null);
  expect(html).toContain('<h2 class="gg-detail-subject">Fix &lt;b&gt;bold&lt;/b&gt; parsing</h2>');
  expect(html).not.toContain("gg-detail-body");
  expect(html).toContain(sha);
});

test("the body keeps its line breaks and the hash stays selectable", () => {
  const css = readFileSync(new URL("./styles.css", import.meta.url), "utf8");
  expect(css).toMatch(/\.gg-detail-body\s*\{[^}]*white-space:\s*pre-wrap/);
  expect(css).toMatch(/\.gg-detail-sha\s*\{[^}]*user-select:\s*text/);
});

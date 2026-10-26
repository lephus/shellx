import { afterEach, expect, test } from "bun:test";
import { GitLog, type CustomTableRow } from "@tomplum/react-git-log";
import { JSDOM } from "jsdom";
import { flushSync } from "react-dom";
import { createRoot, type Root } from "react-dom/client";
import { gitLogInputs } from "./model";
import type { GitGraphCommit, GitGraphHead } from "./types";

// Renders the real react-git-log with the props GitGraphApp passes, to check
// where it puts HEAD: on lane 0, with the uncommitted-changes row above it.

let root: Root | null = null;
let dom: JSDOM | null = null;
const saved = new Map<string, unknown>();
for (const key of ["window", "document", "navigator", "Element", "Node", "HTMLElement"]) {
  saved.set(key, (globalThis as Record<string, unknown>)[key]);
}

afterEach(async () => {
  if (root) flushSync(() => root?.unmount());
  root = null;
  // React schedules passive effects on a timer; let them run before `window` goes.
  await new Promise((resolve) => setTimeout(resolve, 0));
  dom?.window.close();
  dom = null;
  for (const [key, value] of saved) {
    if (value === undefined) delete (globalThis as Record<string, unknown>)[key];
    else (globalThis as Record<string, unknown>)[key] = value;
  }
});

const Row: CustomTableRow = ({ commit }) => <div data-row={commit.hash} data-parents={commit.parents.join(" ")} />;

/** Commits newest first, each the parent of the one before, with real `--source` names. */
function shaped(rows: Array<[sha: string, source: string]>): GitGraphCommit[] {
  return rows.map(([sha, source], index) => ({
    sha,
    parents: index + 1 < rows.length ? [rows[index + 1]![0]] : [],
    source,
    authorName: "A",
    authorEmail: "a@x.io",
    authorDate: `2026-01-0${9 - index}T00:00:00Z`,
    committerDate: `2026-01-0${9 - index}T00:00:00Z`,
    subject: sha,
  }));
}

function render(commits: GitGraphCommit[], head: GitGraphHead) {
  dom = new JSDOM("<!doctype html><html><body><div id='root'></div></body></html>", { url: "http://127.0.0.1/" });
  const g = globalThis as Record<string, unknown>;
  g.window = dom.window;
  g.document = dom.window.document;
  g.navigator = dom.window.navigator;
  g.Element = dom.window.Element;
  g.Node = dom.window.Node;
  g.HTMLElement = dom.window.HTMLElement;
  const container = dom.window.document.getElementById("root")!;
  const { entries, currentBranch } = gitLogInputs(commits, head);
  root = createRoot(container);
  flushSync(() => {
    root?.render(
      <GitLog entries={entries} currentBranch={currentBranch} showGitIndex indexStatus={{ added: 1, modified: 0, deleted: 0 }}>
        <GitLog.GraphHTMLGrid nodeSize={10} />
        <GitLog.Table row={Row} />
      </GitLog>,
    );
  });
  const lane = (sha: string): number | null => {
    const cell = container.querySelector(`[data-testid="commit-node-${sha}"]`)?.closest('[data-testid^="graph-column-row-"]');
    const match = cell?.getAttribute("data-testid")?.match(/-col-(\d+)$/);
    return match ? Number(match[1]) : null;
  };
  const index = container.querySelector('[data-row="index"]');
  return { lane, indexParent: index?.getAttribute("data-parents") ?? null };
}

test("HEAD on main below origin/main's tip: the uncommitted row hangs off HEAD, on lane 0", () => {
  const commits = shaped([["c5", "origin/main"], ["c4", "origin/main"], ["c3", "aaa-backup"], ["c2", "aaa-backup"], ["c1", "aaa-backup"]]);
  const { lane, indexParent } = render(commits, { sha: "c3", branch: "main" });
  expect(indexParent).toBe("c3");
  expect([lane("c3"), lane("c2"), lane("c1")]).toEqual([0, 0, 0]);
  expect(lane("c5")).not.toBe(0);
});

test("with remote branches hidden, the uncommitted row still shows above HEAD", () => {
  const commits = shaped([["c3", "aaa-backup"], ["c2", "aaa-backup"], ["c1", "aaa-backup"]]);
  const { lane, indexParent } = render(commits, { sha: "c3", branch: "main" });
  expect(indexParent).toBe("c3");
  expect(lane("c3")).toBe(0);
});

test("a detached HEAD below a branch named like HEAD keeps the row and lane 0", () => {
  const commits = shaped([["n1", "fix-HEADER"], ["c3", "aaa-backup"], ["c2", "HEAD"], ["c1", "HEAD"]]);
  const { lane, indexParent } = render(commits, { sha: "c2", branch: null });
  expect(indexParent).toBe("c2");
  expect(lane("c2")).toBe(0);
});

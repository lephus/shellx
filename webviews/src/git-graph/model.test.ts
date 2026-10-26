import { expect, test } from "bun:test";
import {
  GIT_GRAPH_LANE_COLORS,
  findMatches,
  gitLogInputs,
  layoutFor,
  mergePage,
  refChipsByCommit,
  splitCommitMessage,
  toLogEntries,
  toRgb,
  visibleChips,
  type GitLogInputs,
  type RefChip,
} from "./model";
import type { GitGraphCommit, GitGraphPage, GitGraphRef } from "./types";

function commit(sha: string, subject = "s", authorName = "n", authorEmail = "e@x.io"): GitGraphCommit {
  return {
    sha,
    parents: [],
    source: "main",
    authorName,
    authorEmail,
    authorDate: "2026-01-01T00:00:00Z",
    committerDate: "2026-01-02T00:00:00Z",
    subject,
  };
}

function page(commits: GitGraphCommit[]): GitGraphPage {
  return { commits, hasMore: false, reachedLimit: false };
}

test("toRgb converts the lane palette", () => {
  expect(toRgb("#60a5fa")).toBe("rgb(96, 165, 250)");
  expect(GIT_GRAPH_LANE_COLORS.map(toRgb)[7]).toBe("rgb(153, 246, 228)");
});

test("toLogEntries maps commits and keeps unloaded parents", () => {
  const c = { ...commit("a", "Subject", "Ann", "ann@y.io"), parents: ["zzz"] };
  expect(toLogEntries([c], "b")).toEqual([
    {
      hash: "a",
      parents: ["zzz"],
      branch: "main",
      message: "Subject",
      committerDate: "2026-01-02T00:00:00Z",
      authorDate: "2026-01-01T00:00:00Z",
      author: { name: "Ann", email: "ann@y.io" },
    },
  ]);
});

/**
 * The commit react-git-log treats as HEAD: the first entry whose `branch`
 * contains `currentBranch` (`commits.find((t) => t.branch.includes(e.currentBranch))`
 * in the graph builder, and the same lookup for the uncommitted-changes row).
 */
function libraryHead({ entries, currentBranch }: GitLogInputs): string | undefined {
  return entries.find((entry) => entry.branch.includes(currentBranch))?.hash;
}

/** Commits newest first, with the `--source` names real git reports for that shape. */
function shaped(rows: Array<[sha: string, source: string]>): GitGraphCommit[] {
  return rows.map(([sha, source], index) => ({
    ...commit(sha),
    source,
    parents: index + 1 < rows.length ? [rows[index + 1]![0]] : [],
  }));
}

test("HEAD on main with origin/main ahead and another branch at HEAD: the HEAD commit is HEAD", () => {
  // git log --source reports HEAD's commit as reached from aaa-backup (sorted
  // before main), and origin/main's tip contains the text "main".
  const head = { sha: "c3", branch: "main" };
  const withRemotes = shaped([["c5", "origin/main"], ["c4", "origin/main"], ["c3", "aaa-backup"], ["c2", "aaa-backup"]]);
  const withoutRemotes = shaped([["c3", "aaa-backup"], ["c2", "aaa-backup"]]);
  expect(libraryHead(gitLogInputs(withRemotes, head))).toBe("c3");
  expect(libraryHead(gitLogInputs(withoutRemotes, head))).toBe("c3");
});

test("a branch whose name contains HEAD's branch name does not take HEAD's place", () => {
  const dev = shaped([["d1", "develop"], ["c3", "aaa-backup"], ["c2", "aaa-backup"]]);
  expect(libraryHead(gitLogInputs(dev, { sha: "c3", branch: "dev" }))).toBe("c3");
  const feat = shaped([["r1", "origin/feat/x"], ["c3", "feat/x"]]);
  expect(libraryHead(gitLogInputs(feat, { sha: "c3", branch: "feat/x" }))).toBe("c3");
});

test("a detached HEAD is its own commit, even below a branch named like HEAD", () => {
  const detached = shaped([["n1", "fix-HEADER"], ["c3", "aaa-backup"], ["c2", "HEAD"], ["c1", "HEAD"]]);
  expect(libraryHead(gitLogInputs(detached, { sha: "c2", branch: null }))).toBe("c2");
});

test("only HEAD's entry carries the HEAD marker; the others keep their source", () => {
  const commits = shaped([["c5", "origin/main"], ["c3", "aaa-backup"]]);
  const { entries, currentBranch, hasHead } = gitLogInputs(commits, { sha: "c3", branch: "main" });
  // Ref names cannot contain a space, so no source can contain the marker.
  expect(currentBranch).toContain(" ");
  expect(entries.map((entry) => entry.branch)).toEqual(["origin/main", currentBranch]);
  expect(hasHead).toBe(true);
  // HEAD's commit not loaded (a branch filter without it): no entry is HEAD, and
  // the caller must not ask for the uncommitted-changes row.
  const unloaded = gitLogInputs(commits, { sha: "zz", branch: "main" });
  expect(unloaded.entries.map((entry) => entry.branch)).toEqual(["origin/main", "aaa-backup"]);
  expect(libraryHead(unloaded)).toBeUndefined();
  expect(unloaded.hasHead).toBe(false);
  expect(gitLogInputs(commits, { sha: null, branch: "main" }).hasHead).toBe(false);
});

test("refChipsByCommit orders head, local, remote, tag", () => {
  const refs: GitGraphRef[] = [
    { kind: "tag", name: "v1", fullName: "refs/tags/v1", target: "a" },
    { kind: "remoteBranch", name: "origin/main", fullName: "refs/remotes/origin/main", target: "a" },
    { kind: "localBranch", name: "main", fullName: "refs/heads/main", target: "a" },
    { kind: "localBranch", name: "develop", fullName: "refs/heads/develop", target: "a" },
  ];
  expect(
    refChipsByCommit(refs, { sha: "a", branch: "develop" })
      .get("a")!
      .map((c) => `${c.kind}:${c.label}`),
  ).toEqual(["head:develop", "local:main", "remote:origin/main", "tag:v1"]);
});

test("findMatches searches subject, author, email and sha prefix only", () => {
  const commits = [commit("abcd1234", "Fix <b>bold</b>", "Phu.le", "p@x.dev"), commit("ffff0000", "other", "Ann", "ann@y.io")];
  expect(findMatches(commits, "BOLD")).toEqual(["abcd1234"]);
  expect(findMatches(commits, "ann@")).toEqual(["ffff0000"]);
  expect(findMatches(commits, "abcd")).toEqual(["abcd1234"]);
  expect(findMatches(commits, "abc")).toEqual([]);
  expect(findMatches(commits, "  ")).toEqual([]);
});

test("layoutFor switches at 560px", () => {
  expect(layoutFor(559)).toBe("narrow");
  expect(layoutFor(560)).toBe("wide");
});

test("mergePage replaces on skip 0 and appends without duplicates", () => {
  const a = [commit("a"), commit("b")];
  expect(mergePage(a, page([commit("b"), commit("c")]), 2).map((c) => c.sha)).toEqual(["a", "b", "c"]);
  expect(mergePage(a, page([commit("z")]), 0).map((c) => c.sha)).toEqual(["z"]);
});

test("splitCommitMessage separates the first line from a body that keeps its breaks", () => {
  expect(splitCommitMessage("Subject only\n")).toEqual({ subject: "Subject only", body: "" });
  expect(splitCommitMessage("Subject\n\n\nFirst para\n  indented\n\nSecond <b>x</b>\n\n")).toEqual({
    subject: "Subject",
    body: "First para\n  indented\n\nSecond <b>x</b>",
  });
  expect(splitCommitMessage("Windows\r\n\r\nBody\r\n")).toEqual({ subject: "Windows", body: "Body" });
  expect(splitCommitMessage("Wrapped first\nparagraph\n\nBody")).toEqual({
    subject: "Wrapped first",
    body: "paragraph\n\nBody",
  });
});

test("visibleChips keeps one chip in narrow layout", () => {
  const chips = [{ label: "develop", kind: "head" }, { label: "origin/develop", kind: "remote" }] as RefChip[];
  expect(visibleChips(chips, "narrow")).toEqual({ shown: [chips[0]], overflow: 1 });
  expect(visibleChips(chips, "wide").overflow).toBe(0);
});

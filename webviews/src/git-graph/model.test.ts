import { expect, test } from "bun:test";
import {
  GIT_GRAPH_LANE_COLORS,
  findMatches,
  layoutFor,
  mergePage,
  refChipsByCommit,
  toLogEntries,
  toRgb,
  visibleChips,
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
  expect(toLogEntries([c])).toEqual([
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

test("visibleChips keeps one chip in narrow layout", () => {
  const chips = [{ label: "develop", kind: "head" }, { label: "origin/develop", kind: "remote" }] as RefChip[];
  expect(visibleChips(chips, "narrow")).toEqual({ shown: [chips[0]], overflow: 1 });
  expect(visibleChips(chips, "wide").overflow).toBe(0);
});

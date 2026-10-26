import type { GitLogEntry } from "@tomplum/react-git-log";
import type { GitGraphCommit, GitGraphHead, GitGraphPage, GitGraphRef } from "./types";

export const GIT_GRAPH_LANE_COLORS: readonly string[] = [
  "#60a5fa",
  "#c4b5fd",
  "#6fd49a",
  "#e8c468",
  "#7dd3fc",
  "#a5b4fc",
  "#e88a8a",
  "#99f6e4",
];

/** react-git-log renders hex invisibly in dark mode, so colours go in as rgb(). */
export function toRgb(hex: string): string {
  const value = hex.replace("#", "");
  const r = Number.parseInt(value.slice(0, 2), 16);
  const g = Number.parseInt(value.slice(2, 4), 16);
  const b = Number.parseInt(value.slice(4, 6), 16);
  return `rgb(${r}, ${g}, ${b})`;
}

/**
 * The `branch` of HEAD's entry, and the `currentBranch` passed to `GitLog`.
 *
 * react-git-log takes the first entry whose `branch` contains `currentBranch` as
 * HEAD: that commit gets lane 0 (its first-parent line follows), and the
 * uncommitted-changes row hangs off it. A `git log --source` name cannot stand in
 * for HEAD: `origin/main` contains `main`, `develop` contains `dev`, and HEAD's
 * commit is often reported as reached from another branch. A ref name cannot
 * contain a space, so no other entry can contain this value. It is never shown:
 * the rows are ours (`CommitRow`), and `GitLog.Tags`, which prints `branch`, is not used.
 */
export const GIT_LOG_HEAD_BRANCH = "shellx HEAD";

export function toLogEntries(commits: GitGraphCommit[], headSha: string | null): GitLogEntry[] {
  return commits.map((c) => ({
    hash: c.sha,
    parents: c.parents,
    branch: c.sha === headSha ? GIT_LOG_HEAD_BRANCH : c.source,
    message: c.subject,
    committerDate: c.committerDate,
    authorDate: c.authorDate,
    author: { name: c.authorName, email: c.authorEmail },
  }));
}

/** The `entries` and `currentBranch` props of `GitLog`, and whether HEAD's commit is among the entries. */
export type GitLogInputs = { entries: GitLogEntry[]; currentBranch: string; hasHead: boolean };

export function gitLogInputs(commits: GitGraphCommit[], head: GitGraphHead): GitLogInputs {
  return {
    entries: toLogEntries(commits, head.sha),
    currentBranch: GIT_LOG_HEAD_BRANCH,
    hasHead: head.sha !== null && commits.some((c) => c.sha === head.sha),
  };
}

export type RefChip = { label: string; kind: "head" | "local" | "remote" | "tag" };

const CHIP_ORDER: Record<RefChip["kind"], number> = { head: 0, local: 1, remote: 2, tag: 3 };

export function refChipsByCommit(refs: GitGraphRef[], head: GitGraphHead): Map<string, RefChip[]> {
  const byCommit = new Map<string, RefChip[]>();
  for (const ref of refs) {
    let kind: RefChip["kind"];
    if (ref.kind === "tag") kind = "tag";
    else if (ref.kind === "remoteBranch") kind = "remote";
    else kind = head.branch !== null && ref.name === head.branch ? "head" : "local";
    const chips = byCommit.get(ref.target) ?? [];
    chips.push({ label: ref.name, kind });
    byCommit.set(ref.target, chips);
  }
  for (const chips of byCommit.values()) {
    chips.sort((a, b) => CHIP_ORDER[a.kind] - CHIP_ORDER[b.kind] || (a.label < b.label ? -1 : a.label > b.label ? 1 : 0));
  }
  return byCommit;
}

export function findMatches(commits: GitGraphCommit[], query: string): string[] {
  const q = query.trim().toLowerCase();
  if (q === "") return [];
  const shaPrefix = q.length >= 4 && /^[0-9a-f]+$/.test(q);
  return commits
    .filter(
      (c) =>
        c.subject.toLowerCase().includes(q) ||
        c.authorName.toLowerCase().includes(q) ||
        c.authorEmail.toLowerCase().includes(q) ||
        (shaPrefix && c.sha.toLowerCase().startsWith(q)),
    )
    .map((c) => c.sha);
}

export type GitGraphLayout = "narrow" | "wide";

export function layoutFor(width: number): GitGraphLayout {
  return width < 560 ? "narrow" : "wide";
}

export function mergePage(existing: GitGraphCommit[], page: GitGraphPage, skip: number): GitGraphCommit[] {
  if (skip === 0) return page.commits;
  const seen = new Set(existing.map((c) => c.sha));
  return [...existing, ...page.commits.filter((c) => !seen.has(c.sha))];
}

/**
 * Splits a raw commit message (`%B`) into its first line and the rest, dropping
 * the blank lines between them and trailing whitespace. The body keeps its own
 * line breaks and indentation.
 */
export function splitCommitMessage(message: string): { subject: string; body: string } {
  const text = message.replace(/\s+$/, "");
  const newline = text.indexOf("\n");
  if (newline < 0) return { subject: text, body: "" };
  return {
    subject: text.slice(0, newline).replace(/\r$/, ""),
    body: text.slice(newline + 1).replace(/^(?:[ \t]*\r?\n)+/, ""),
  };
}

export function visibleChips(chips: RefChip[], layout: GitGraphLayout): { shown: RefChip[]; overflow: number } {
  if (layout === "wide") return { shown: chips, overflow: 0 };
  return { shown: chips.slice(0, 1), overflow: Math.max(0, chips.length - 1) };
}

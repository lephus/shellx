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

export function toLogEntries(commits: GitGraphCommit[]): GitLogEntry[] {
  return commits.map((c) => ({
    hash: c.sha,
    parents: c.parents,
    branch: c.source,
    message: c.subject,
    committerDate: c.committerDate,
    authorDate: c.authorDate,
    author: { name: c.authorName, email: c.authorEmail },
  }));
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

export function visibleChips(chips: RefChip[], layout: GitGraphLayout): { shown: RefChip[]; overflow: number } {
  if (layout === "wide") return { shown: chips, overflow: 0 };
  return { shown: chips.slice(0, 1), overflow: Math.max(0, chips.length - 1) };
}

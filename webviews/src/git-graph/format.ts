import type { GitGraphFileStatus } from "./types";

// Dates follow the web view's locale (the app's), as the diff viewer does.
const dateFormatter = new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" });
const relativeFormatter = new Intl.RelativeTimeFormat(undefined, { numeric: "auto", style: "narrow" });

const RELATIVE_STEPS: ReadonlyArray<[Intl.RelativeTimeFormatUnit, number]> = [
  ["year", 365 * 24 * 3600],
  ["month", 30 * 24 * 3600],
  ["week", 7 * 24 * 3600],
  ["day", 24 * 3600],
  ["hour", 3600],
  ["minute", 60],
];

function parse(iso: string): number | null {
  const time = Date.parse(iso);
  return Number.isNaN(time) ? null : time;
}

export function formatDate(iso: string): string {
  const time = parse(iso);
  return time === null ? iso : dateFormatter.format(time);
}

export function formatRelative(iso: string, now: number): string {
  const time = parse(iso);
  if (time === null) return iso;
  const seconds = Math.round((time - now) / 1000);
  for (const [unit, size] of RELATIVE_STEPS) {
    if (Math.abs(seconds) >= size) return relativeFormatter.format(Math.trunc(seconds / size), unit);
  }
  return relativeFormatter.format(0, "minute");
}

export function shortSha(sha: string): string {
  return sha.slice(0, 7);
}

export const FILE_STATUS_LETTER: Record<GitGraphFileStatus, string> = {
  added: "A",
  modified: "M",
  deleted: "D",
  renamed: "R",
  copied: "C",
  typeChanged: "T",
  unmerged: "U",
  unknown: "?",
};

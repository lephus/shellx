import type { AutomationLabelResolver } from "./labels";
import type { AutomationDraft, AutomationKind, NotifyTarget, RunStatus } from "./types";

export function kindLabelKey(kind: AutomationKind) {
  return kind === "skill" ? "kindSkill" : kind === "workflow" ? "kindWorkflow" : "kindCronjob";
}

export function statusLabelKey(status: RunStatus) {
  switch (status) {
    case "running":
      return "statusRunning";
    case "done":
      return "statusDone";
    case "failed":
      return "statusFailed";
    case "needsYou":
      return "statusNeedsYou";
    default:
      return "statusSkipped";
  }
}

export function formatTime(iso: string | undefined): string {
  if (!iso) return "";
  const date = new Date(iso);
  return Number.isNaN(date.getTime()) ? iso : date.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
}

export function scheduleText(schedule: AutomationDraft["schedule"]): { human: string; cron: string } | null {
  if (!schedule) return null;
  if (!schedule.cron && !schedule.human) return null;
  return { human: schedule.human, cron: schedule.cron };
}

export function notifyOnLabel(label: AutomationLabelResolver, on: string): string {
  return on === "done" ? label("notifyDone") : on === "failed" ? label("notifyFailed") : label("notifyNeedsYou");
}

/** "Mac", or "iPhone (after the next update)" while iPhone delivery is pending. */
export function notifyTargetLabel(label: AutomationLabelResolver, target: NotifyTarget): string {
  return target === "iphone" ? `${label("targetIphone")} (${label("iphonePending")})` : label("targetMac");
}

/** Run length as "42 s", "3 min 5 s" or "2 h 10 min"; the unit patterns come from the host's labels. */
export function formatDuration(ms: number, label: AutomationLabelResolver): string {
  const total = Math.max(0, Math.floor(ms / 1000));
  if (total < 60) return label("durationSeconds", { seconds: total });
  if (total < 3600) return label("durationMinutes", { minutes: Math.floor(total / 60), seconds: total % 60 });
  return label("durationHours", { hours: Math.floor(total / 3600), minutes: Math.floor((total % 3600) / 60) });
}

/** Milliseconds between two ISO timestamps, or null when either is missing or invalid. */
export function runDurationMs(startedAt: string, finishedAt: string | undefined): number | null {
  if (!finishedAt) return null;
  const ms = new Date(finishedAt).getTime() - new Date(startedAt).getTime();
  return Number.isNaN(ms) ? null : ms;
}

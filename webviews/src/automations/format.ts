import type { AutomationLabelResolver } from "./labels";
import type { AutomationDraft, AutomationKind, RunStatus } from "./types";

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

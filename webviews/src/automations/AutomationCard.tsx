import { useEffect, useRef } from "react";
import { AutomationActions } from "./AutomationActions";
import { formatDuration, formatTime, kindLabelKey, runDurationMs, statusLabelKey } from "./format";
import type { AutomationLabelResolver } from "./labels";
import type { AutomationsStore } from "./store";
import type { AutomationDTO } from "./types";

export function AutomationCard({
  store,
  automation: a,
  label,
  focused,
}: {
  store: AutomationsStore;
  automation: AutomationDTO;
  label: AutomationLabelResolver;
  focused: boolean;
}) {
  const ref = useRef<HTMLElement>(null);
  useEffect(() => {
    if (focused) ref.current?.scrollIntoView?.({ block: "center" });
  }, [focused]);
  const run = a.lastRun;
  const canToggle = a.kind !== "skill";
  const targets = a.notify.targets;
  const showSteps = run?.status === "running" && (run.totalSteps ?? 0) > 1 && run.currentStep != null;
  const durationMs = run && run.status !== "running" ? runDurationMs(run.startedAt, run.finishedAt) : null;
  return (
    <article
      ref={ref}
      className="au-card au-item"
      data-focused={focused ? "true" : "false"}
      data-id={a.id}
    >
      <div className="au-item-head">
        <span className="au-kind" data-kind={a.kind}>{label(kindLabelKey(a.kind))}</span>
        <h3 className="au-item-name">
          <button
            type="button"
            className="au-name-button"
            onClick={() => {
              if (run?.unread) void store.markRead(a.id);
              void store.openDetail(a.id);
            }}
          >
            {a.name}
          </button>
        </h3>
        {run?.unread ? <span className="au-unread" title={label("unread")} /> : null}
        {canToggle && !a.enabled ? <span className="au-muted">{label("disabled")}</span> : null}
        <span className="au-targets">
          {targets.includes("mac") ? <span className="au-target" title={label("targetMac")}>{label("targetMac")}</span> : null}
          {targets.includes("iphone") ? (
            <span className="au-target" title={a.iphonePending ? label("iphonePending") : label("targetIphone")}>
              {label("targetIphone")}
              {a.iphonePending ? ` (${label("iphonePending")})` : ""}
            </span>
          ) : null}
        </span>
      </div>
      <p className="au-item-desc">{a.description}</p>
      {a.schedule ? (
        <p className="au-item-meta">
          {a.schedule.human} <span className="au-muted">({a.schedule.cron})</span>
          {a.nextRun && a.enabled ? <span className="au-muted"> · {label("nextRun", { time: formatTime(a.nextRun) })}</span> : null}
        </p>
      ) : null}
      {a.kind !== "skill" ? (
        <p className="au-item-meta">
          {run ? (
            <span className="au-run" data-status={run.status}>
              {label(statusLabelKey(run.status))}
              {showSteps ? ` · ${label("stepProgress", { current: run.currentStep ?? 0, total: run.totalSteps ?? 0 })}` : ""}
              {run.finishedAt || run.startedAt ? ` · ${formatTime(run.finishedAt ?? run.startedAt)}` : ""}
              {durationMs != null ? ` · ${formatDuration(durationMs, label)}` : ""}
            </span>
          ) : (
            <span className="au-muted">{label("neverRun")}</span>
          )}
          {run && (run.summary || run.reason) ? <span className="au-muted"> — {run.reason ?? run.summary}</span> : null}
        </p>
      ) : null}
      <AutomationActions store={store} automation={a} label={label} />
    </article>
  );
}

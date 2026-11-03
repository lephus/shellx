import { useEffect, useRef } from "react";
import { formatTime, kindLabelKey, statusLabelKey } from "./format";
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
              store.selectCard(a.id);
              if (run?.unread) void store.markRead(a.id);
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
              {run.finishedAt || run.startedAt ? ` · ${formatTime(run.finishedAt ?? run.startedAt)}` : ""}
            </span>
          ) : (
            <span className="au-muted">{label("neverRun")}</span>
          )}
          {run && (run.summary || run.reason) ? <span className="au-muted"> — {run.reason ?? run.summary}</span> : null}
        </p>
      ) : null}
      <div className="au-actions">
        {a.kind !== "skill" ? (
          <button type="button" className="au-button" onClick={(e) => (e.preventDefault(), void store.runNow(a.id))}>
            {label("runNow")}
          </button>
        ) : null}
        {canToggle ? (
          <button type="button" className="au-button" onClick={(e) => (e.preventDefault(), void store.setEnabled(a.id, !a.enabled))}>
            {a.enabled ? label("disable") : label("enable")}
          </button>
        ) : null}
        <button type="button" className="au-button" onClick={(e) => (e.preventDefault(), void store.startCreator(a.id))}>
          {label("edit")}
        </button>
        <button type="button" className="au-button" onClick={(e) => (e.preventDefault(), void store.editFile(a.id))}>
          {label("editFile")}
        </button>
        <button type="button" className="au-button" onClick={(e) => (e.preventDefault(), void store.reveal(a.id))}>
          {label("reveal")}
        </button>
        {a.kind !== "skill" ? (
          <button type="button" className="au-button" onClick={(e) => (e.preventDefault(), void store.openLog(a.id))}>
            {label("openLog")}
          </button>
        ) : null}
        {run?.status === "needsYou" && run.sessionId ? (
          <button type="button" className="au-button au-primary" onClick={(e) => (e.preventDefault(), void store.continueInTerminal(a.id))}>
            {label("continueInTerminal")}
          </button>
        ) : null}
        <button type="button" className="au-button au-danger" onClick={(e) => (e.preventDefault(), store.requestDelete(a))}>
          {label("delete")}
        </button>
      </div>
    </article>
  );
}

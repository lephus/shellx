import { useMemo } from "react";
import { AutomationActions } from "./AutomationActions";
import { FlowChart } from "./FlowChart";
import { buildChart, layoutChart } from "./flowChartModel";
import { formatTime, kindLabelKey, statusLabelKey } from "./format";
import type { AutomationLabelResolver } from "./labels";
import { ActionErrorBanner } from "./ListView";
import type { AutomationsStore, DetailState } from "./store";
import type { AutomationDetail } from "./types";
import { ViewSwitch } from "./ViewSwitch";

type Props = {
  store: AutomationsStore;
  detail: DetailState;
  actionError: string | null;
  label: AutomationLabelResolver;
};

/** One line: description, schedule with next run, last run with step progress. */
function Summary({ data, label }: { data: AutomationDetail; label: AutomationLabelResolver }) {
  const a = data.automation;
  const run = a.lastRun;
  const showSteps = run?.status === "running" && (run.totalSteps ?? 0) > 1 && run.currentStep != null;
  return (
    <p className="au-detail-summary">
      {a.description}
      {a.schedule ? (
        <span className="au-muted">
          {a.description ? " · " : ""}
          {a.schedule.human}
          {a.nextRun && a.enabled ? ` · ${label("nextRun", { time: formatTime(a.nextRun) })}` : ""}
        </span>
      ) : null}
      {a.kind !== "skill" && run ? (
        <span className="au-run" data-status={run.status}>
          {" · "}
          {label(statusLabelKey(run.status))}
          {showSteps ? ` · ${label("stepProgress", { current: run.currentStep ?? 0, total: run.totalSteps ?? 0 })}` : ""}
        </span>
      ) : null}
    </p>
  );
}

function FlowBody({ store, detail, data, label }: { store: AutomationsStore; detail: DetailState; data: AutomationDetail; label: AutomationLabelResolver }) {
  const a = data.automation;
  const isWorkflow = a.kind === "workflow";
  const layout = useMemo(() => {
    const chart = buildChart(
      { kind: a.kind, description: a.description, schedule: a.schedule, notify: a.notify, steps: a.steps, flow: data.flow },
      label,
    );
    return chart === null ? null : layoutChart(chart);
  }, [a, data.flow, label]);
  const run = a.lastRun;
  const runningNodeId = isWorkflow && run?.status === "running" && run.currentStep != null ? `step-${run.currentStep}` : undefined;

  if ((data.flowStatus === "current" || data.flowStatus === "derived") && layout !== null) {
    return (
      <div className="au-flow-box">
        <FlowChart layout={layout} label={label} runningNodeId={runningNodeId} />
        {!isWorkflow ? <p className="au-flow-note">{label("flowCaption")}</p> : null}
      </div>
    );
  }
  return (
    <div className="au-flow-empty">
      <p className="au-muted">{data.flowStatus === "stale" ? label("flowStale") : label("flowMissing")}</p>
      {detail.error !== null ? (
        <p className="au-issue" role="alert">
          {detail.error || label("genericError")}
        </p>
      ) : null}
      <button type="button" className="au-button au-primary" disabled={detail.drawing} onClick={() => void store.drawFlow()}>
        {detail.drawing ? label("drawingFlow") : label("drawFlow")}
      </button>
      <p className="au-flow-note">{label("drawFlowHint")}</p>
    </div>
  );
}

/** Read-only: a workflow's steps, then SKILL.md. */
function TextBody({ data, label }: { data: AutomationDetail; label: AutomationLabelResolver }) {
  const steps = data.automation.kind === "workflow" ? data.automation.steps : [];
  return (
    <>
      {steps.length > 0 ? (
        <section className="au-detail-section">
          <h3 className="au-detail-k">{label("fieldSteps")}</h3>
          <ol className="au-steps">
            {steps.map((step, index) => (
              <li key={`${index}:${step.title}`}>
                <span className="au-detail-step-title">{step.title}</span>
                <p className="au-detail-step-prompt">{step.prompt}</p>
              </li>
            ))}
          </ol>
        </section>
      ) : null}
      <section className="au-detail-section">
        <h3 className="au-detail-k">{label("fieldSkill")}</h3>
        <pre className="au-pre">{data.skillMarkdown}</pre>
      </section>
    </>
  );
}

/** The page of one saved automation: its flowchart (or text) and the card's actions. */
export function DetailView({ store, detail, actionError, label }: Props) {
  const data = detail.data;
  const a = data?.automation;
  return (
    <div className="au-detail">
      <header className="au-detail-head">
        <button type="button" className="au-button au-detail-back" onClick={() => store.closeDetail()}>
          ← {label("back")}
        </button>
        {data && a ? (
          <>
            <div className="au-detail-title">
              <span className="au-kind" data-kind={a.kind}>{label(kindLabelKey(a.kind))}</span>
              <h2>{a.name}</h2>
              <ViewSwitch mode={detail.mode} onChange={(mode) => store.setDetailView(mode)} label={label} />
            </div>
            <Summary data={data} label={label} />
            <AutomationActions store={store} automation={a} label={label} />
          </>
        ) : null}
      </header>
      <ActionErrorBanner store={store} actionError={actionError} label={label} />
      <div className="au-detail-body">
        {data ? (
          detail.mode === "flow" ? (
            <FlowBody store={store} detail={detail} data={data} label={label} />
          ) : (
            <TextBody data={data} label={label} />
          )
        ) : detail.loading ? (
          <output className="au-status">{label("loading")}</output>
        ) : (
          <div className="au-status">
            <output>{detail.error || label("genericError")}</output>
            <button type="button" className="au-button" onClick={() => void store.openDetail(detail.id)}>
              {label("retry")}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

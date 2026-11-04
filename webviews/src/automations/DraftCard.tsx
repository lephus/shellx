import { useEffect, useLayoutEffect, useRef, type ReactNode } from "react";
import { kindLabelKey, notifyOnLabel, scheduleText } from "./format";
import type { AutomationLabelResolver } from "./labels";
import type { DraftEdit } from "./store";
import type { AutomationDraft, ValidationField, ValidationIssueDTO } from "./types";

type Props = {
  label: AutomationLabelResolver;
  draft: AutomationDraft;
  issues: ValidationIssueDTO[];
  ready: boolean;
  /** Set when the user may change name, description and SKILL.md on the card. */
  onEdit?: (edit: DraftEdit) => void;
  /** Called when an edited field loses focus. */
  onCommit?: () => void;
  /** Keeps the fields read-only, e.g. while Claude rewrites the draft. */
  locked?: boolean;
};

const useIsoLayoutEffect = typeof window === "undefined" ? useEffect : useLayoutEffect;

/** A text area that grows with its text, up to its CSS max-height. */
function GrowingText({
  value,
  className,
  ariaLabel,
  readOnly,
  onChange,
  onBlur,
}: {
  value: string;
  className: string;
  ariaLabel: string;
  readOnly: boolean;
  onChange: (value: string) => void;
  onBlur?: () => void;
}) {
  const ref = useRef<HTMLTextAreaElement>(null);
  useIsoLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${el.scrollHeight}px`;
  }, [value]);
  return (
    <textarea
      ref={ref}
      className={className}
      value={value}
      rows={1}
      spellCheck={false}
      readOnly={readOnly}
      aria-label={ariaLabel}
      onChange={(e) => onChange(e.target.value)}
      onBlur={onBlur}
    />
  );
}

function Field({
  name,
  title,
  issues,
  children,
}: {
  name: ValidationField | "notify" | "steps" | "tools";
  title: string;
  issues: ValidationIssueDTO[];
  children: ReactNode;
}) {
  return (
    <div className="au-field" data-field={name}>
      <span className="au-field-k">{title}</span>
      <div className="au-field-v">
        {children}
        {issues.map((issue) => (
          <p key={`${issue.code}:${issue.message}`} className="au-issue" role="alert">
            {issue.message}
          </p>
        ))}
      </div>
    </div>
  );
}

/** Shows each draft field only once it is non-empty (or has a validation issue). */
export function DraftCard({ label, draft, issues, ready, onEdit, onCommit, locked = false }: Props) {
  const editable = onEdit !== undefined;
  const forField = (field: ValidationField) => issues.filter((i) => i.field === field);
  const schedule = scheduleText(draft.schedule);
  const directory = draft.workingDirectory ?? "";
  const hasNotify = draft.notify.on.length > 0 || draft.notify.targets.length > 0;
  const general = issues.filter((i) => i.field === "claude" || i.field === "kind");
  const targets = draft.notify.targets.map((t) =>
    t === "iphone" ? `${label("targetIphone")} (${label("iphonePending")})` : label("targetMac"),
  );

  return (
    <div className="au-card au-draft" data-ready={ready ? "true" : "false"}>
      <div className="au-draft-head">
        {draft.kind !== "" ? <span className="au-kind" data-kind={draft.kind}>{label(kindLabelKey(draft.kind))}</span> : null}
        <h4 className="au-draft-name">{draft.name}</h4>
        <span className="au-draft-status">{ready ? label("statusReady") : label("statusDrafting")}</span>
      </div>
      {draft.name !== "" || forField("name").length > 0 ? (
        <Field name="name" title={label("fieldName")} issues={forField("name")}>
          {editable ? (
            <input
              className="au-edit"
              value={draft.name}
              spellCheck={false}
              readOnly={locked}
              aria-label={label("fieldName")}
              onChange={(e) => onEdit({ name: e.target.value })}
              onBlur={onCommit}
            />
          ) : (
            <span>{draft.name}</span>
          )}
        </Field>
      ) : null}
      {draft.description !== "" || forField("description").length > 0 ? (
        <Field name="description" title={label("fieldDescription")} issues={forField("description")}>
          {editable ? (
            <GrowingText
              className="au-edit"
              value={draft.description}
              ariaLabel={label("fieldDescription")}
              readOnly={locked}
              onChange={(description) => onEdit({ description })}
              onBlur={onCommit}
            />
          ) : (
            <span>{draft.description}</span>
          )}
        </Field>
      ) : null}
      {schedule !== null || forField("schedule").length > 0 ? (
        <Field name="schedule" title={label("fieldSchedule")} issues={forField("schedule")}>
          {schedule ? (
            <span>
              {schedule.human}
              {schedule.human && schedule.cron ? " " : ""}
              {schedule.cron ? <span className="au-muted">({schedule.cron})</span> : null}
            </span>
          ) : null}
        </Field>
      ) : null}
      {directory !== "" || forField("workingDirectory").length > 0 ? (
        <Field name="workingDirectory" title={label("fieldDirectory")} issues={forField("workingDirectory")}>
          <span>{directory}</span>
        </Field>
      ) : null}
      {hasNotify ? (
        <Field name="notify" title={label("fieldNotify")} issues={[]}>
          <span>{[...draft.notify.on.map((o) => notifyOnLabel(label, o)), ...targets].join(" · ")}</span>
        </Field>
      ) : null}
      {draft.steps.length > 0 || forField("steps").length > 0 ? (
        <Field name="steps" title={label("fieldSteps")} issues={forField("steps")}>
          {draft.steps.length > 0 ? (
            <ol className="au-steps">
              {draft.steps.map((step, index) => (
                <li key={`${index}:${step.title}`}>{step.title}</li>
              ))}
            </ol>
          ) : null}
        </Field>
      ) : null}
      {draft.allowedTools.length > 0 ? (
        <Field name="tools" title={label("fieldTools")} issues={[]}>
          <span className="au-mono">{draft.allowedTools.join(", ")}</span>
        </Field>
      ) : null}
      {draft.skillMarkdown !== "" || forField("skillMarkdown").length > 0 ? (
        <Field name="skillMarkdown" title={label("fieldSkill")} issues={forField("skillMarkdown")}>
          {editable ? (
            <GrowingText
              className="au-edit au-pre"
              value={draft.skillMarkdown}
              ariaLabel={label("fieldSkill")}
              readOnly={locked}
              onChange={(skillMarkdown) => onEdit({ skillMarkdown })}
              onBlur={onCommit}
            />
          ) : (
            <pre className="au-pre">{draft.skillMarkdown}</pre>
          )}
        </Field>
      ) : null}
      {general.map((issue) => (
        <p key={`${issue.code}:${issue.message}`} className="au-issue" role="alert">
          {issue.message}
        </p>
      ))}
    </div>
  );
}

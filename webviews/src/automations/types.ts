// Page-side types for the `shellxAutomations` bridge (Swift host: Task 8).

export type AutomationKind = "skill" | "workflow" | "cronjob";
export type NotifyOn = "done" | "failed" | "needsYou";
export type NotifyTarget = "mac" | "iphone";
export type RunStatus = "running" | "done" | "failed" | "needsYou" | "skipped";

export type AutomationSchedule = { cron: string; human: string };
export type AutomationStep = { title: string; prompt: string };
export type AutomationNotify = { on: NotifyOn[]; targets: NotifyTarget[] };

export type AutomationRunDTO = {
  status: RunStatus;
  trigger: string;
  startedAt: string;
  finishedAt?: string;
  sessionId?: string;
  summary?: string;
  reason?: string;
  failedStep?: number | string;
  currentStep?: number;
  totalSteps?: number;
  unread: boolean;
};

export type AutomationDTO = {
  id: string;
  kind: AutomationKind;
  name: string;
  description: string;
  schedule?: AutomationSchedule;
  workingDirectory?: string;
  notify: AutomationNotify;
  allowedTools: string[];
  steps: AutomationStep[];
  enabled: boolean;
  origin: "shellx" | "external";
  createdAt: string;
  updatedAt: string;
  lastRun?: AutomationRunDTO;
  nextRun?: string;
  iphonePending: boolean;
};

export type FlowNodeType = "step" | "decision" | "askUser" | "end";
export type FlowNode = { id: string; type: FlowNodeType; label: string; detail?: string };
export type FlowEdge = { from: string; to: string; label?: string };
/** Mirrors the Swift `ShellXAutomationFlow`; absent optional fields are omitted. */
export type AutomationFlow = { trigger?: string; nodes: FlowNode[]; edges: FlowEdge[] };
export type FlowStatus = "current" | "stale" | "missing" | "derived";

/** Reply of `automations.detail` and `automations.drawFlow`. */
export type AutomationDetail = {
  automation: AutomationDTO;
  skillMarkdown: string;
  flow: AutomationFlow | null;
  flowStatus: FlowStatus;
};

export type ValidationField =
  | "name"
  | "description"
  | "schedule"
  | "workingDirectory"
  | "skillMarkdown"
  | "steps"
  | "claude"
  | "kind";
export type ValidationIssueDTO = { field: ValidationField; code: string; message: string };

/** Mirrors the Swift `ShellXAutomationDraft`. Fields may be empty early on. */
export type AutomationDraft = {
  kind: AutomationKind | "";
  name: string;
  description: string;
  schedule?: AutomationSchedule | null;
  workingDirectory?: string | null;
  notify: AutomationNotify;
  allowedTools: string[];
  steps: AutomationStep[];
  skillMarkdown: string;
  flow?: AutomationFlow | null;
};

export type ChoiceSet = { question: string; multi: boolean; options: string[] };

export type CreatorEvent =
  | { type: "textDelta"; text: string }
  | { type: "assistantMessage"; text: string; choices?: ChoiceSet }
  | { type: "draft"; draft: AutomationDraft }
  | { type: "busy"; busy: boolean }
  | { type: "failed"; message: string }
  | { type: "validation"; issues: ValidationIssueDTO[] };

export type AutomationsEvent =
  | { type: "automations.changed" }
  | { type: "creator.event"; event: CreatorEvent }
  | { type: "focus"; id: string };

export type AutomationsMethod =
  | "app.context"
  | "automations.list"
  | "automations.runNow"
  | "automations.setEnabled"
  | "automations.delete"
  | "automations.reveal"
  | "automations.editFile"
  | "automations.openLog"
  | "automations.continueInTerminal"
  | "automations.markRead"
  | "automations.detail"
  | "automations.drawFlow"
  | "creator.start"
  | "creator.send"
  | "creator.cancel"
  | "creator.save"
  | "creator.edit";

export type AutomationsReply<T> =
  | { ok: true; result: T }
  | { ok: false; error: { code: string; message: string } };

export type AutomationsContext = {
  labels: Record<string, string>;
  focusId?: string;
  reduceMotion: boolean;
  appearance?: "dark" | "light";
};

export type SaveResult = { automation: AutomationDTO } | { issues: ValidationIssueDTO[] };

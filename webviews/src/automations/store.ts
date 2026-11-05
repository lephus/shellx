import type { AutomationsBridge } from "./bridge";
import { usableFlow } from "./flowChartModel";
import { readFrontmatter, writeFrontmatter } from "./frontmatter";
import type {
  AutomationDraft,
  AutomationDTO,
  AutomationKind,
  AutomationsContext,
  AutomationsEvent,
  ChoiceSet,
  CreatorEvent,
  SaveResult,
  ValidationIssueDTO,
} from "./types";

export type ListFilter = "all" | AutomationKind;
export type CreatorType = "auto" | AutomationKind;

export type ChatMessage = {
  id: number;
  role: "user" | "assistant" | "error";
  text: string;
  choices?: ChoiceSet;
};

export type CreatorState = {
  messages: ChatMessage[];
  /** Assistant text still arriving; replaced by the final `assistantMessage`. */
  streaming: string | null;
  draft: AutomationDraft | null;
  issues: ValidationIssueDTO[];
  busy: boolean;
  type: CreatorType;
  saving: boolean;
  editId: string | null;
  /** The user changed the draft on the card and the host has not been told yet. */
  draftDirty: boolean;
  /** The draft card shows the flowchart or the text fields. */
  draftView: DraftViewMode;
  /** The chart matches the draft: false once the user edits the card, until the next draft event. */
  flowCurrent: boolean;
};

export type DraftViewMode = "flow" | "text";

/** The draft fields the user can change on the card. */
export type DraftEdit = Partial<Pick<AutomationDraft, "name" | "description" | "skillMarkdown">>;

export type AutomationsState = {
  context: AutomationsContext | null;
  view: "list" | "creator";
  loading: boolean;
  loadFailed: boolean;
  automations: AutomationDTO[];
  filter: ListFilter;
  focusId: string | null;
  pendingDelete: { id: string; name: string; external: boolean } | null;
  /** Message of the last failed list action, until dismissed. */
  actionError: string | null;
  /** Asking before a draft in progress is thrown away; `then` is the creator to open afterwards. */
  pendingDiscard: { then: { editId: string | null } | null } | null;
  creator: CreatorState;
};

function initialCreator(editId: string | null = null): CreatorState {
  return {
    messages: [],
    streaming: null,
    draft: null,
    issues: [],
    busy: false,
    type: "auto",
    saving: false,
    editId,
    draftDirty: false,
    draftView: "flow",
    flowCurrent: false,
  };
}

function initialState(): AutomationsState {
  return {
    context: null,
    view: "list",
    loading: true,
    loadFailed: false,
    automations: [],
    filter: "all",
    focusId: null,
    pendingDelete: null,
    actionError: null,
    pendingDiscard: null,
    creator: initialCreator(),
  };
}

function isDraft(value: unknown): value is AutomationDraft {
  if (typeof value !== "object" || value === null) return false;
  const d = value as Partial<AutomationDraft>;
  return typeof d.name === "string" && typeof d.skillMarkdown === "string" && typeof d.notify === "object" && d.notify !== null;
}

/** Cards for the current filter; skills ShellX did not create are listed apart. */
export function visibleAutomations(state: AutomationsState): { own: AutomationDTO[]; external: AutomationDTO[] } {
  const matches = (a: AutomationDTO) => state.filter === "all" || a.kind === state.filter;
  const own = state.automations.filter((a) => a.origin !== "external" && matches(a));
  const external = state.automations.filter((a) => a.origin === "external" && matches(a));
  return { own, external };
}

/** Whether the creator holds a chat worth keeping: the user has sent at least one message. */
export function draftInProgress(creator: CreatorState): boolean {
  return creator.messages.some((m) => m.role === "user");
}

/** The draft is ready once it can be saved and the assistant has stopped. */
export function draftIsReady(creator: CreatorState): boolean {
  const d = creator.draft;
  return d !== null && !creator.busy && d.name.trim() !== "" && d.skillMarkdown.trim() !== "";
}

export class AutomationsStore {
  private state: AutomationsState = initialState();
  private listeners = new Set<() => void>();
  private nextId = 1;
  private off: (() => void) | null = null;
  private editInFlight: Promise<string | null> | null = null;

  constructor(private readonly bridge: AutomationsBridge) {}

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

  getState = (): AutomationsState => this.state;

  private set(patch: Partial<AutomationsState>): void {
    this.state = { ...this.state, ...patch };
    for (const l of this.listeners) l();
  }

  private setCreator(patch: Partial<CreatorState>): void {
    this.set({ creator: { ...this.state.creator, ...patch } });
  }

  async start(): Promise<void> {
    this.off?.();
    this.off = this.bridge.onEvent((e) => this.handleEvent(e));
    const ctx = await this.bridge.request<AutomationsContext>("app.context");
    if (ctx.ok) {
      const c = ctx.result;
      this.set({
        context: {
          labels: c.labels && typeof c.labels === "object" ? c.labels : {},
          focusId: c.focusId,
          reduceMotion: c.reduceMotion === true,
          appearance: c.appearance,
        },
        focusId: c.focusId ?? this.state.focusId,
      });
    } else {
      this.set({ context: { labels: {}, reduceMotion: false } });
    }
    await this.reload();
    // Nothing to manage yet: open straight into the creator (spec §1), unless a banner asked for a card.
    const s = this.state;
    if (!s.loadFailed && s.automations.length === 0 && !s.focusId && s.view === "list") {
      await this.startCreator();
    }
  }

  dispose(): void {
    this.off?.();
    this.off = null;
  }

  async reload(): Promise<void> {
    const reply = await this.bridge.request<{ automations: AutomationDTO[] }>("automations.list");
    if (reply.ok && Array.isArray(reply.result?.automations)) {
      this.set({ automations: reply.result.automations, loading: false, loadFailed: false });
    } else {
      this.set({ loading: false, loadFailed: true });
    }
  }

  handleEvent(event: AutomationsEvent): void {
    switch (event.type) {
      case "automations.changed":
        void this.reload();
        break;
      case "focus":
        this.set({ focusId: event.id, view: "list", filter: "all" });
        break;
      case "creator.event":
        this.handleCreatorEvent(event.event);
        break;
    }
  }

  private handleCreatorEvent(event: CreatorEvent): void {
    const c = this.state.creator;
    switch (event.type) {
      case "textDelta":
        if (typeof event.text === "string") this.setCreator({ streaming: (c.streaming ?? "") + event.text });
        break;
      case "assistantMessage":
        this.setCreator({
          streaming: null,
          messages: [
            ...c.messages,
            { id: this.nextId++, role: "assistant", text: String(event.text ?? ""), choices: event.choices },
          ],
        });
        break;
      case "draft":
        // A malformed or partial draft keeps the last good one.
        if (isDraft(event.draft)) this.setCreator({
            draft: event.draft,
            issues: [],
            draftDirty: false,
            flowCurrent: usableFlow(event.draft.flow) !== null,
          });
        break;
      case "busy":
        this.setCreator({ busy: event.busy === true });
        break;
      case "failed":
        this.setCreator({
          busy: false,
          streaming: null,
          messages: [...c.messages, { id: this.nextId++, role: "error", text: String(event.message ?? "") }],
        });
        break;
      case "validation":
        this.setCreator({ issues: Array.isArray(event.issues) ? event.issues : [] });
        break;
    }
  }

  // List actions

  setFilter(filter: ListFilter): void {
    this.set({ filter });
  }

  selectCard(id: string | null): void {
    this.set({ focusId: id });
  }

  /** Sends a list action; a failed reply becomes `actionError`. Returns whether it succeeded. */
  private async act(method: Parameters<AutomationsBridge["request"]>[0], params: object): Promise<boolean> {
    const reply = await this.bridge.request(method, params);
    if (!reply.ok) {
      this.set({ actionError: reply.error.message || reply.error.code });
      return false;
    }
    return true;
  }

  dismissActionError(): void {
    this.set({ actionError: null });
  }

  runNow = (id: string) => this.act("automations.runNow", { id });
  reveal = (id: string) => this.act("automations.reveal", { id });
  editFile = (id: string) => this.act("automations.editFile", { id });
  openLog = (id: string) => this.act("automations.openLog", { id });
  continueInTerminal = (id: string) => this.act("automations.continueInTerminal", { id });
  async setEnabled(id: string, enabled: boolean): Promise<void> {
    if (await this.act("automations.setEnabled", { id, enabled })) await this.reload();
  }
  async markRead(id: string): Promise<void> {
    if (await this.act("automations.markRead", { id })) await this.reload();
  }

  requestDelete(a: AutomationDTO): void {
    this.set({ pendingDelete: { id: a.id, name: a.name, external: a.origin === "external" || a.id.startsWith("external:") } });
  }

  cancelDelete(): void {
    this.set({ pendingDelete: null });
  }

  async confirmDelete(): Promise<void> {
    const pending = this.state.pendingDelete;
    if (!pending) return;
    this.set({ pendingDelete: null });
    const params = pending.external ? { id: pending.id, confirmedExternal: true } : { id: pending.id };
    if (await this.act("automations.delete", params)) await this.reload();
  }

  // Creator

  /** Opens the creator; a draft in progress is only replaced after the user confirms. */
  async startCreator(editId?: string): Promise<void> {
    const current = this.state.creator;
    if (draftInProgress(current)) {
      if (editId !== undefined && editId === current.editId) this.resumeCreator();
      else this.set({ pendingDiscard: { then: { editId: editId ?? null } } });
      return;
    }
    await this.openCreator(editId ?? null);
  }

  private async openCreator(editId: string | null): Promise<void> {
    this.set({ view: "creator", creator: initialCreator(editId) });
    const reply = await this.bridge.request("creator.start", editId !== null ? { editId } : {});
    if (!reply.ok) this.handleCreatorEvent({ type: "failed", message: reply.error.message });
  }

  setDraftView(mode: DraftViewMode): void {
    this.setCreator({ draftView: mode });
  }

  /**
   * Changes the draft on the card. Name and description stay in step with the SKILL.md
   * frontmatter, both ways. The host hears about it on `flushDraftEdit`.
   */
  editDraft(edit: DraftEdit): void {
    const c = this.state.creator;
    if (!c.draft || c.busy) return;
    let draft = { ...c.draft, ...edit };
    if (edit.skillMarkdown !== undefined) {
      const front = readFrontmatter(edit.skillMarkdown);
      if (front.name !== undefined) draft.name = front.name;
      if (front.description !== undefined) draft.description = front.description;
    } else if (edit.name !== undefined || edit.description !== undefined) {
      draft = { ...draft, skillMarkdown: writeFrontmatter(draft.skillMarkdown, edit) };
    }
    const touched = new Set(["name", "description", "skillMarkdown"]);
    this.setCreator({ draft, draftDirty: true, flowCurrent: false, issues: c.issues.filter((i) => !touched.has(i.field)) });
  }

  /**
   * Sends the card's unsent edits to the host, so a save or the next message sees them.
   * Waits for an edit already on its way. Returns the error, if any.
   */
  async flushDraftEdit(): Promise<string | null> {
    while (this.editInFlight) {
      const error = await this.editInFlight;
      if (error !== null) return error;
    }
    const { draft, draftDirty } = this.state.creator;
    if (!draft || !draftDirty) return null;
    this.setCreator({ draftDirty: false });
    const sending = this.bridge
      .request("creator.edit", { name: draft.name, description: draft.description, skillMarkdown: draft.skillMarkdown })
      .then((reply) => {
        if (reply.ok) return null;
        this.setCreator({ draftDirty: true });
        return reply.error.message;
      })
      .finally(() => {
        if (this.editInFlight === sending) this.editInFlight = null;
      });
    this.editInFlight = sending;
    return sending;
  }

  setCreatorType(type: CreatorType): void {
    this.setCreator({ type });
  }

  async sendMessage(text: string): Promise<void> {
    const trimmed = text.trim();
    if (trimmed === "") return;
    const c = this.state.creator;
    const first = c.messages.every((m) => m.role !== "user");
    const outgoing = first && c.type !== "auto" ? `Type: ${c.type}. ${trimmed}` : trimmed;
    this.setCreator({
      messages: [...c.messages, { id: this.nextId++, role: "user", text: trimmed }],
      busy: true,
      issues: [],
    });
    // Claude hears about the card's edits ahead of this message; a failed edit still sends it.
    await this.flushDraftEdit();
    const reply = await this.bridge.request("creator.send", { text: outgoing });
    if (!reply.ok) this.handleCreatorEvent({ type: "failed", message: reply.error.message });
  }

  /** Back to the list. A chat the user has written in stays open as a draft in progress. */
  async leaveCreator(): Promise<void> {
    if (draftInProgress(this.state.creator)) {
      this.set({ view: "list" });
      return;
    }
    await this.bridge.request("creator.cancel");
    this.set({ view: "list", creator: initialCreator() });
  }

  /** Returns to the draft in progress; Claude kept working while the list was shown. */
  resumeCreator(): void {
    this.set({ view: "creator" });
  }

  requestDiscard(): void {
    this.set({ pendingDiscard: { then: null } });
  }

  cancelDiscard(): void {
    this.set({ pendingDiscard: null });
  }

  /** Keeps the draft in progress instead of the creator that asked to replace it. */
  continueInsteadOfDiscard(): void {
    this.set({ pendingDiscard: null, view: "creator" });
  }

  /** Stops Claude and drops the draft in progress, then opens the creator that asked for it, if any. */
  async confirmDiscard(): Promise<void> {
    const then = this.state.pendingDiscard?.then ?? null;
    this.set({ pendingDiscard: null, view: "list" });
    // Events the session sent before it stopped arrive before this reply; reset only after them.
    await this.bridge.request("creator.cancel");
    this.set({ creator: initialCreator() });
    if (then) await this.openCreator(then.editId);
  }

  async save(): Promise<void> {
    if (this.state.creator.saving) return;
    this.setCreator({ saving: true });
    const editError = await this.flushDraftEdit();
    if (editError !== null) {
      this.setCreator({ saving: false });
      this.handleCreatorEvent({ type: "failed", message: editError });
      return;
    }
    const reply = await this.bridge.request<SaveResult>("creator.save");
    if (reply.ok && reply.result && "automation" in reply.result) {
      this.set({ view: "list", focusId: reply.result.automation.id, filter: "all", creator: initialCreator() });
      await this.reload();
    } else if (reply.ok && reply.result && "issues" in reply.result) {
      this.setCreator({ saving: false, issues: reply.result.issues });
    } else {
      this.setCreator({ saving: false });
      this.handleCreatorEvent({ type: "failed", message: reply.ok ? "" : reply.error.message });
    }
  }
}

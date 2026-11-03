import type { AutomationsBridge } from "./bridge";
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
};

export type AutomationsState = {
  context: AutomationsContext | null;
  view: "list" | "creator";
  loading: boolean;
  loadFailed: boolean;
  automations: AutomationDTO[];
  filter: ListFilter;
  focusId: string | null;
  pendingDelete: { id: string; name: string; external: boolean } | null;
  creator: CreatorState;
};

function initialCreator(editId: string | null = null): CreatorState {
  return { messages: [], streaming: null, draft: null, issues: [], busy: false, type: "auto", saving: false, editId };
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
      this.set({ loading: false, loadFailed: !reply.ok });
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
        if (isDraft(event.draft)) this.setCreator({ draft: event.draft, issues: [] });
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

  private act(method: Parameters<AutomationsBridge["request"]>[0], params: object): Promise<unknown> {
    return this.bridge.request(method, params);
  }

  runNow = (id: string) => this.act("automations.runNow", { id });
  reveal = (id: string) => this.act("automations.reveal", { id });
  editFile = (id: string) => this.act("automations.editFile", { id });
  openLog = (id: string) => this.act("automations.openLog", { id });
  continueInTerminal = (id: string) => this.act("automations.continueInTerminal", { id });
  async setEnabled(id: string, enabled: boolean): Promise<void> {
    await this.act("automations.setEnabled", { id, enabled });
    await this.reload();
  }
  async markRead(id: string): Promise<void> {
    await this.act("automations.markRead", { id });
    await this.reload();
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
    await this.act("automations.delete", pending.external ? { id: pending.id, confirmedExternal: true } : { id: pending.id });
    await this.reload();
  }

  // Creator

  async startCreator(editId?: string): Promise<void> {
    this.set({ view: "creator", creator: initialCreator(editId ?? null) });
    await this.bridge.request("creator.start", editId ? { editId } : {});
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
    const reply = await this.bridge.request("creator.send", { text: outgoing });
    if (!reply.ok) this.handleCreatorEvent({ type: "failed", message: reply.error.message });
  }

  async leaveCreator(): Promise<void> {
    await this.bridge.request("creator.cancel");
    this.set({ view: "list", creator: initialCreator() });
  }

  async save(): Promise<void> {
    if (this.state.creator.saving) return;
    this.setCreator({ saving: true });
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

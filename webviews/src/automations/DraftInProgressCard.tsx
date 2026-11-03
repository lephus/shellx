import { draftIsReady, type AutomationsStore, type CreatorState } from "./store";
import type { AutomationLabelResolver } from "./labels";
import type { AutomationDTO } from "./types";

/** The creator chat the user left with Back: Claude keeps working on it until it is continued or discarded. */
export function DraftInProgressCard({
  store,
  creator,
  label,
  automations,
}: {
  store: AutomationsStore;
  creator: CreatorState;
  label: AutomationLabelResolver;
  automations: AutomationDTO[];
}) {
  const edited = creator.editId !== null ? automations.find((a) => a.id === creator.editId) : undefined;
  const name = creator.draft?.name.trim() || edited?.name || label("untitledDraft");
  const lastUserMessage = [...creator.messages].reverse().find((m) => m.role === "user")?.text ?? "";
  const description = creator.draft?.description.trim() || lastUserMessage;
  const status = creator.busy ? label("thinking") : draftIsReady(creator) ? label("statusReady") : label("statusDrafting");
  return (
    <article className="au-card au-item au-draft-progress" data-busy={creator.busy ? "true" : "false"}>
      <div className="au-item-head">
        <span className="au-kind" data-kind="draft">{label("draftBadge")}</span>
        <h3 className="au-item-name">
          <button type="button" className="au-name-button" onClick={() => store.resumeCreator()}>
            {name}
          </button>
        </h3>
        <span className="au-muted">{status}</span>
      </div>
      {edited ? <p className="au-item-meta au-muted">{label("editingName", { name: edited.name })}</p> : null}
      {description !== "" ? <p className="au-item-desc">{description}</p> : null}
      <div className="au-actions">
        <button type="button" className="au-button au-primary" onClick={() => store.resumeCreator()}>
          {label("continueDraft")}
        </button>
        <button type="button" className="au-button au-danger" onClick={() => store.requestDiscard()}>
          {label("discard")}
        </button>
      </div>
    </article>
  );
}

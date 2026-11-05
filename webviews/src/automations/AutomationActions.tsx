import type { AutomationLabelResolver } from "./labels";
import type { AutomationsStore } from "./store";
import type { AutomationDTO } from "./types";

/** The buttons of a saved automation, on its list card and on its detail page. */
export function AutomationActions({
  store,
  automation: a,
  label,
}: {
  store: AutomationsStore;
  automation: AutomationDTO;
  label: AutomationLabelResolver;
}) {
  const run = a.lastRun;
  const canToggle = a.kind !== "skill";
  return (
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
  );
}

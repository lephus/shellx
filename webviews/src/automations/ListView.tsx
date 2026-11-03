import { AutomationCard } from "./AutomationCard";
import type { AutomationLabelResolver } from "./labels";
import { visibleAutomations, type AutomationsState, type AutomationsStore, type ListFilter } from "./store";

const FILTERS: { value: ListFilter; key: "filterAll" | "filterSkills" | "filterWorkflows" | "filterCronjobs" }[] = [
  { value: "all", key: "filterAll" },
  { value: "skill", key: "filterSkills" },
  { value: "workflow", key: "filterWorkflows" },
  { value: "cronjob", key: "filterCronjobs" },
];

export function ListView({
  store,
  state,
  label,
}: {
  store: AutomationsStore;
  state: AutomationsState;
  label: AutomationLabelResolver;
}) {
  const { own, external } = visibleAutomations(state);
  return (
    <div className="au-list">
      <header className="au-list-head">
        <h2>{label("title")}</h2>
        <div className="au-tabs" role="tablist">
          {FILTERS.map((f) => (
            <button
              key={f.value}
              type="button"
              role="tab"
              aria-selected={state.filter === f.value}
              className="au-tab"
              onClick={() => store.setFilter(f.value)}
            >
              {label(f.key)}
            </button>
          ))}
        </div>
        <button type="button" className="au-button au-primary" onClick={() => void store.startCreator()}>
          {label("newAutomation")}
        </button>
      </header>
      {state.actionError !== null ? (
        <div className="au-banner" role="alert">
          <span>{label("actionFailed", { message: state.actionError })}</span>
          <button type="button" className="au-button" onClick={() => store.dismissActionError()}>
            {label("dismiss")}
          </button>
        </div>
      ) : null}
      <div className="au-list-body">
        {state.loading ? (
          <output className="au-status">{label("loading")}</output>
        ) : state.loadFailed ? (
          <div className="au-status">
            <output>{label("loadFailed")}</output>
            <button type="button" className="au-button" onClick={() => void store.reload()}>
              {label("retry")}
            </button>
          </div>
        ) : own.length === 0 && external.length === 0 ? (
          <output className="au-status">{label("empty")}</output>
        ) : (
          <>
            {own.map((a) => (
              <AutomationCard key={a.id} store={store} automation={a} label={label} focused={state.focusId === a.id} />
            ))}
            {external.length > 0 ? (
              <>
                <h3 className="au-group">{label("otherSkills")}</h3>
                {external.map((a) => (
                  <AutomationCard key={a.id} store={store} automation={a} label={label} focused={state.focusId === a.id} />
                ))}
              </>
            ) : null}
          </>
        )}
      </div>
    </div>
  );
}

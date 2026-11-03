import { useEffect, useMemo, useState, useSyncExternalStore } from "react";
import { createAutomationsBridge, type AutomationsBridge } from "./bridge";
import { ConfirmDialog } from "./ConfirmDialog";
import { CreatorView } from "./CreatorView";
import { DiscardDialog } from "./DiscardDialog";
import { createAutomationLabelResolver } from "./labels";
import { ListView } from "./ListView";
import { AutomationsStore } from "./store";

export function AutomationsApp({ bridge }: { bridge?: AutomationsBridge }) {
  const [store] = useState(() => new AutomationsStore(bridge ?? createAutomationsBridge()));
  const state = useSyncExternalStore(store.subscribe, store.getState);
  useEffect(() => {
    void store.start();
    return () => store.dispose();
  }, [store]);

  const appearance = state.context?.appearance;
  useEffect(() => {
    if (appearance) document.documentElement.dataset.auAppearance = appearance;
    else delete document.documentElement.dataset.auAppearance;
  }, [appearance]);

  const labels = state.context?.labels;
  const label = useMemo(() => createAutomationLabelResolver(labels), [labels]);
  const reduceMotion = state.context?.reduceMotion === true;
  const pending = state.pendingDelete;

  return (
    <div className="au-app" data-reduce-motion={reduceMotion ? "true" : "false"}>
      {state.context === null ? null : state.view === "creator" ? (
        <CreatorView store={store} creator={state.creator} label={label} reduceMotion={reduceMotion} />
      ) : (
        <ListView store={store} state={state} label={label} />
      )}
      {state.pendingDiscard ? (
        <DiscardDialog
          label={label}
          replacing={state.pendingDiscard.then !== null}
          onDiscard={() => void store.confirmDiscard()}
          onContinue={() => store.continueInsteadOfDiscard()}
          onCancel={() => store.cancelDiscard()}
        />
      ) : null}
      {pending ? (
        <ConfirmDialog
          label={label}
          name={pending.name}
          external={pending.external}
          onConfirm={() => void store.confirmDelete()}
          onCancel={() => store.cancelDelete()}
        />
      ) : null}
    </div>
  );
}

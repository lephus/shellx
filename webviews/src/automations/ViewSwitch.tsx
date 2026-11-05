import type { AutomationLabelResolver } from "./labels";
import type { DraftViewMode } from "./store";

/** A two-button segmented control: the draft as a flowchart or as text. */
export function ViewSwitch({
  mode,
  onChange,
  label,
}: {
  mode: DraftViewMode;
  onChange: (mode: DraftViewMode) => void;
  label: AutomationLabelResolver;
}) {
  return (
    <div className="au-view-switch">
      <button type="button" aria-pressed={mode === "flow"} onClick={() => onChange("flow")}>
        {label("viewFlow")}
      </button>
      <button type="button" aria-pressed={mode === "text"} onClick={() => onChange("text")}>
        {label("viewText")}
      </button>
    </div>
  );
}

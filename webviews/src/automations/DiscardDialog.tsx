import { useEffect, useRef } from "react";
import type { AutomationLabelResolver } from "./labels";

/** Confirms throwing away the draft in progress; `replacing` offers to keep working on it instead. */
export function DiscardDialog({
  label,
  replacing,
  onDiscard,
  onContinue,
  onCancel,
}: {
  label: AutomationLabelResolver;
  replacing: boolean;
  onDiscard: () => void;
  onContinue: () => void;
  onCancel: () => void;
}) {
  const keepRef = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    keepRef.current?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onCancel();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onCancel]);
  return (
    <div className="au-scrim">
      <div className="au-dialog" role="alertdialog" aria-modal="true" aria-labelledby="au-discard-title">
        <h3 id="au-discard-title">{label("discardTitle")}</h3>
        <p>{label("discardBody")}</p>
        <div className="au-dialog-actions">
          {replacing ? (
            <button ref={keepRef} type="button" className="au-button" onClick={onContinue}>
              {label("continueDraft")}
            </button>
          ) : (
            <button ref={keepRef} type="button" className="au-button" onClick={onCancel}>
              {label("cancel")}
            </button>
          )}
          <button type="button" className="au-button au-danger" onClick={onDiscard}>
            {label("discard")}
          </button>
        </div>
      </div>
    </div>
  );
}

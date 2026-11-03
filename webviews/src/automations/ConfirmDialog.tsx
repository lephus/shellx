import { useEffect, useRef } from "react";
import type { AutomationLabelResolver } from "./labels";

export function ConfirmDialog({
  label,
  name,
  external,
  onConfirm,
  onCancel,
}: {
  label: AutomationLabelResolver;
  name: string;
  external: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  const cancelRef = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    cancelRef.current?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onCancel();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onCancel]);
  return (
    <div className="au-scrim">
      <div className="au-dialog" role="alertdialog" aria-modal="true" aria-labelledby="au-dialog-title">
        <h3 id="au-dialog-title">{label("deleteTitle", { name })}</h3>
        <p>{label("deleteBody")}</p>
        {external ? <p className="au-issue">{label("deleteExternalWarning")}</p> : null}
        <div className="au-dialog-actions">
          <button ref={cancelRef} type="button" className="au-button" onClick={onCancel}>
            {label("cancel")}
          </button>
          <button type="button" className="au-button au-danger" onClick={onConfirm}>
            {label("confirmDelete")}
          </button>
        </div>
      </div>
    </div>
  );
}

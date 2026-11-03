import { createRoot } from "react-dom/client";
import { AutomationsApp } from "../automations/AutomationsApp";
import automationsStyles from "../automations/styles.css?inline";
import { installWebviewStyles } from "./installWebviewStyles";

/**
 * Boots the Automations surface (`automations.html`). Loaded as its own chunk.
 * Its data comes from the `shellxAutomations` bridge, not from an inline config.
 */
export function mountAutomationsSurface(rootElement: HTMLElement): void {
  installWebviewStyles("automations", automationsStyles);
  createRoot(rootElement).render(<AutomationsApp />);
}

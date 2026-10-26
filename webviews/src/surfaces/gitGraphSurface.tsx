import { createRoot } from "react-dom/client";
import { GitGraphApp } from "../git-graph/GitGraphApp";
import gitGraphStyles from "../git-graph/styles.css?inline";
import { installWebviewStyles } from "./installWebviewStyles";

/**
 * Boots the Git Graph surface (`git-graph.html`). Loaded as its own chunk, with
 * react-git-log in `git-graph-vendor`, so the other surfaces never ship it.
 * Its data comes from the `shellxGitGraph` bridge, not from an inline config.
 */
export function mountGitGraphSurface(rootElement: HTMLElement): void {
  installWebviewStyles("git-graph", gitGraphStyles);
  createRoot(rootElement).render(<GitGraphApp />);
}

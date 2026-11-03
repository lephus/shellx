type WebviewKind = "agent-session" | "automations" | "diff" | "git-graph";

function resolveWebviewKind(): WebviewKind {
  if (
    document.documentElement.dataset.cmuxWebviewKind === "git-graph" ||
    document.body.dataset.cmuxWebviewKind === "git-graph"
  ) {
    return "git-graph";
  }
  if (
    document.documentElement.dataset.cmuxWebviewKind === "automations" ||
    document.body.dataset.cmuxWebviewKind === "automations"
  ) {
    return "automations";
  }
  if (
    document.documentElement.dataset.cmuxWebviewKind === "agent-session" ||
    document.body.dataset.cmuxWebviewKind === "agent-session" ||
    document.getElementById("cmux-agent-session-config")
  ) {
    return "agent-session";
  }
  return "diff";
}

const rootElement = document.getElementById("root");
if (!rootElement) {
  throw new Error("Missing cmux webview root");
}

// Load only the active surface so each one ships as its own chunk: the diff
// viewer pulls in `@pierre/diffs`, the agent session pulls in its editor UI,
// the Git Graph pulls in react-git-log, and none pays for the others. Shared
// vendor code (React, the router) is hoisted by Rollup into chunks they reuse.
const kind = resolveWebviewKind();
if (kind === "git-graph") {
  void import("./surfaces/gitGraphSurface").then((surface) => {
    surface.mountGitGraphSurface(rootElement);
  });
} else if (kind === "automations") {
  void import("./surfaces/automationsSurface").then((surface) => {
    surface.mountAutomationsSurface(rootElement);
  });
} else if (kind === "agent-session") {
  void import("./surfaces/agentSessionSurface").then((surface) => {
    surface.mountAgentSessionSurface(rootElement);
  });
} else {
  void import("./surfaces/diffSurface").then((surface) => {
    surface.mountDiffSurface(rootElement);
  });
}

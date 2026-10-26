import { expect, test } from "bun:test";
import { createGitGraphLabelResolver, DEFAULT_GIT_GRAPH_LABELS } from "./labels";

test("labels fall back to English, prefer non-empty localized values and fill placeholders", () => {
  const label = createGitGraphLabelResolver({ refresh: "Làm mới", retry: "  ", searchCount: "{current} trên {total}" });
  expect(label("refresh")).toBe("Làm mới");
  expect(label("retry")).toBe("Retry");
  expect(label("allBranches")).toBe("All branches");
  expect(label("searchCount", { current: 3, total: 17 })).toBe("3 trên 17");
  expect(label("limitReached", { count: 5000 })).toBe("Showing the most recent commits only (limit: 5000).");
  expect(label("filesChanged")).toBe("Files changed: {count}");
  expect(createGitGraphLabelResolver()("noDirectory")).toBe(DEFAULT_GIT_GRAPH_LABELS.noDirectory);
});

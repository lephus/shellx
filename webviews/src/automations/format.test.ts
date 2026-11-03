import { expect, test } from "bun:test";
import { formatDuration } from "./format";
import { createAutomationLabelResolver } from "./labels";

const label = createAutomationLabelResolver();

test("formatDuration boundaries", () => {
  expect(formatDuration(0, label)).toBe("0 s");
  expect(formatDuration(59_000, label)).toBe("59 s");
  expect(formatDuration(60_000, label)).toBe("1 min 0 s");
  expect(formatDuration(3_599_000, label)).toBe("59 min 59 s");
  expect(formatDuration(3_600_000, label)).toBe("1 h 0 min");
  expect(formatDuration(-5, label)).toBe("0 s");
});

test("formatDuration uses host-localized labels", () => {
  const vi = createAutomationLabelResolver({ durationSeconds: "{seconds} giây" });
  expect(formatDuration(42_000, vi)).toBe("42 giây");
});

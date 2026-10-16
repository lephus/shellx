import { describe, expect, it } from "vitest";
import { FrameBudgets, IDLE_MS } from "../src/hub/frame-budgets.js";
import { FRAMES_PER_SECOND } from "../src/hub/token-bucket.js";

const T0 = 1_900_000_000_000;

function clock() {
  let now = T0;
  return { now: () => now, set: (ms: number) => (now = ms) };
}

/** Calls take() `times` times; returns how many frames were allowed. */
function spend(budgets: FrameBudgets, deviceId: string, times: number): number {
  let allowed = 0;
  for (let i = 0; i < times; i++) if (budgets.take(deviceId)) allowed++;
  return allowed;
}

describe("FrameBudgets (500 frames/s per device)", () => {
  it("counts a bucket as idle after exactly the time an empty one needs to refill (capacity / refill rate)", () => {
    expect(FRAMES_PER_SECOND).toBe(500);
    expect(IDLE_MS).toBe(1000); // 500 frames at 500 frames/s
  });

  it("keeps a bucket 999 ms after its last use, still partly spent", () => {
    const t = clock();
    const budgets = new FrameBudgets(t.now);
    expect(spend(budgets, "device", FRAMES_PER_SECOND + 1)).toBe(FRAMES_PER_SECOND);
    budgets.sweep(T0 + 999);
    expect(budgets.size).toBe(1);
    t.set(T0 + 999);
    expect(spend(budgets, "device", FRAMES_PER_SECOND)).toBe(499); // 499.5 frames refilled, not a fresh 500
  });

  it("drops it 1000 ms after its last use, when it has refilled to exactly what a new bucket holds", () => {
    const t = clock();
    const swept = new FrameBudgets(t.now);
    const kept = new FrameBudgets(t.now); // never swept: the reference
    expect(spend(swept, "device", FRAMES_PER_SECOND)).toBe(FRAMES_PER_SECOND);
    expect(spend(kept, "device", FRAMES_PER_SECOND)).toBe(FRAMES_PER_SECOND);
    swept.sweep(T0 + IDLE_MS);
    expect(swept.size).toBe(0);
    t.set(T0 + IDLE_MS);
    // Dropping it changed nothing observable: both allow exactly a full budget.
    expect(spend(swept, "device", FRAMES_PER_SECOND + 1)).toBe(FRAMES_PER_SECOND);
    expect(spend(kept, "device", FRAMES_PER_SECOND + 1)).toBe(FRAMES_PER_SECOND);
  });

  it("sweeps from take() at most once every 60 s", () => {
    const t = clock();
    const budgets = new FrameBudgets(t.now);
    budgets.take("idle");
    budgets.take("busy");
    t.set(T0 + 59_999);
    budgets.take("busy");
    expect(budgets.size).toBe(2); // "idle" has been idle for ~60 s, but no sweep yet
    t.set(T0 + 60_000);
    budgets.take("busy");
    expect(budgets.size).toBe(1); // swept: "idle" dropped, "busy" (used 1 ms ago) kept
    budgets.take("idle");
    t.set(T0 + 60_000 + 59_999);
    budgets.take("busy");
    expect(budgets.size).toBe(2); // the next sweep is 60 s after the last one
    t.set(T0 + 120_000);
    budgets.take("busy");
    expect(budgets.size).toBe(1);
  });
});

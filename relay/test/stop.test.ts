import { afterEach, describe, expect, it, vi } from "vitest";
import { createStopHandler } from "../src/stop.js";

afterEach(() => {
  vi.restoreAllMocks();
});

/** Fakes for everything the handler touches, recording the order of events. */
function harness(shutdown: () => Promise<void>, closeDb: () => void = () => {}) {
  const events: string[] = [];
  const lines: string[] = [];
  vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
    lines.push(args.map(String).join(" "));
  });
  let exited: (code: number) => void = () => {};
  const exit = new Promise<number>((resolve) => (exited = resolve));
  const stop = createStopHandler({
    shutdown: () => {
      events.push("shutdown");
      return shutdown();
    },
    closeDb: () => {
      events.push("close_db");
      closeDb();
    },
    exit: (code) => {
      events.push(`exit ${code}`);
      exited(code);
    },
    forceExitMs: 200,
  });
  return { stop, events, lines, exit };
}

describe("SIGTERM/SIGINT handler (src/stop.ts)", () => {
  it("shuts down, then closes the database, then exits 0", async () => {
    const h = harness(async () => {});
    h.stop("SIGTERM");
    expect(await h.exit).toBe(0);
    expect(h.events).toEqual(["shutdown", "close_db", "exit 0"]);
    expect(h.lines.join("\n")).toContain('"event":"relay_stopping","signal":"SIGTERM"');
    expect(h.lines.join("\n")).toContain('"event":"relay_stopped"');
  });

  it("logs a failed shutdown by kind only, still closes the database, and exits 1", async () => {
    const h = harness(() => Promise.reject(Object.assign(new Error("database is locked: UPDATE devices ..."), { code: "SQLITE_BUSY" })));
    h.stop("SIGTERM");
    expect(await h.exit).toBe(1);
    expect(h.events).toEqual(["shutdown", "close_db", "exit 1"]);
    const output = h.lines.join("\n");
    expect(output).toContain('"event":"relay_shutdown_failed","error":"SQLITE_BUSY"');
    expect(output).not.toContain("UPDATE devices");
  });

  it("still exits (1) when closing the database fails", async () => {
    const h = harness(
      async () => {},
      () => {
        throw new TypeError("The database connection is busy executing a query");
      },
    );
    h.stop("SIGINT");
    expect(await h.exit).toBe(1);
    expect(h.lines.join("\n")).toContain('"event":"db_close_failed","error":"TypeError"');
  });

  it("ignores every signal after the first", async () => {
    let finish: () => void = () => {};
    const h = harness(() => new Promise<void>((resolve) => (finish = resolve)));
    h.stop("SIGTERM");
    h.stop("SIGTERM");
    h.stop("SIGINT");
    finish();
    expect(await h.exit).toBe(0);
    expect(h.events).toEqual(["shutdown", "close_db", "exit 0"]);
    expect(h.lines.filter((line) => line.includes("relay_stopping"))).toHaveLength(1);
  });

  it("exits 1 without waiting further if the shutdown hangs past the force-exit deadline", async () => {
    const h = harness(() => new Promise<void>(() => {}));
    const started = Date.now();
    h.stop("SIGTERM");
    expect(await h.exit).toBe(1);
    expect(Date.now() - started).toBeGreaterThanOrEqual(150);
    expect(h.events).toEqual(["shutdown", "exit 1"]);
  });
});

import { errorKind, logMeta } from "./log.js";

export interface StopDeps {
  /** The relay's graceful shutdown (`RunningRelay.shutdown`). */
  shutdown(): Promise<void>;
  /** Closes the database; only called once the shutdown settled. */
  closeDb(): void;
  /** `process.exit` in production. */
  exit(code: number): void;
  /** Hard stop (exit 1) if the whole stop takes longer than this. */
  forceExitMs: number;
}

/**
 * The SIGTERM/SIGINT handler of `src/server.ts` (spec §4.3). The first signal starts a graceful
 * stop: shutdown, then close the database, then exit 0. A failing shutdown or database close is
 * logged by kind only; the database is still closed and the exit code is 1. Every later signal is
 * ignored. If the stop hangs past `forceExitMs`, the process exits 1 regardless.
 */
export function createStopHandler(deps: StopDeps): (signal: string) => void {
  let stopping = false;
  return (signal) => {
    if (stopping) return;
    stopping = true;
    logMeta("relay_stopping", { signal });
    const forceExit = setTimeout(() => deps.exit(1), deps.forceExitMs).unref();
    const finish = (code: number): void => {
      try {
        deps.closeDb();
      } catch (err) {
        logMeta("db_close_failed", { error: errorKind(err) });
        code = 1;
      }
      logMeta("relay_stopped");
      clearTimeout(forceExit);
      deps.exit(code);
    };
    let shutdown: Promise<void>;
    try {
      shutdown = deps.shutdown();
    } catch (err) {
      shutdown = Promise.reject(err);
    }
    void shutdown.then(
      () => finish(0),
      (err: unknown) => {
        logMeta("relay_shutdown_failed", { error: errorKind(err) });
        finish(1);
      },
    );
  };
}

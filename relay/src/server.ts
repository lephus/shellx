// Entry point of the relay container: `node dist/server.js` (dev: `npm run dev`).
import { createRateLimiters } from "./auth/rate-limit.js";
import { ConfigError, loadConfig, type Config } from "./config.js";
import { Db } from "./db/db.js";
import { migrate } from "./db/migrate.js";
import { HubRegistry } from "./hub/registry.js";
import { errorKind, logMeta } from "./log.js";
import { startRelay } from "./relay.js";
import { createStopHandler } from "./stop.js";

/** Hard stop if a graceful shutdown hangs; stays under Compose's 10 s stop_grace_period. */
const FORCE_EXIT_MS = 9000;

function fail(message: string): never {
  console.error(`relay: ${message}`);
  process.exit(1);
}

let config: Config;
try {
  config = loadConfig(process.env);
} catch (err) {
  fail(err instanceof ConfigError ? err.message : "invalid configuration");
}

let db: Db;
try {
  db = Db.open(config.dbPath);
  migrate(db);
} catch (err) {
  fail(`cannot open database at ${config.dbPath} (${errorKind(err)})`);
}

const hubs = new HubRegistry({ db });
const relay = await startRelay(
  { config, db, hubs, limiters: createRateLimiters(config) },
  { host: config.host, port: config.port },
).catch((err: unknown) => fail(`cannot listen on ${config.host}:${config.port} (${errorKind(err)})`));
logMeta("relay_started", { port: relay.port });

const stop = createStopHandler({
  shutdown: () => relay.shutdown(),
  closeDb: () => db.close(),
  exit: (code) => process.exit(code),
  forceExitMs: FORCE_EXIT_MS,
});
process.on("SIGTERM", () => stop("SIGTERM"));
process.on("SIGINT", () => stop("SIGINT"));

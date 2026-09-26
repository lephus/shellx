// Entry point of the relay container: `node dist/server.js` (dev: `npm run dev`).
import { createRateLimiters } from "./auth/rate-limit.js";
import { ConfigError, loadConfig, type Config } from "./config.js";
import { Db } from "./db/db.js";
import { migrate } from "./db/migrate.js";
import { HubRegistry } from "./hub/registry.js";
import { errorKind, logMeta } from "./log.js";
import { startRelay } from "./relay.js";

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

let stopping = false;
async function stop(signal: string): Promise<void> {
  if (stopping) return;
  stopping = true;
  logMeta("relay_stopping", { signal });
  setTimeout(() => process.exit(1), FORCE_EXIT_MS).unref();
  await relay.shutdown();
  db.close();
  logMeta("relay_stopped");
  process.exit(0);
}
process.on("SIGTERM", () => void stop("SIGTERM"));
process.on("SIGINT", () => void stop("SIGINT"));

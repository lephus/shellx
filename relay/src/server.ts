// Entry point of the relay container: `node dist/server.js` (dev: `npm run dev`).
import { adminStatus } from "./admin/app.js";
import { createRateLimiters } from "./auth/rate-limit.js";
import { ConfigError, loadConfig, type Config } from "./config.js";
import { Db } from "./db/db.js";
import { migrate } from "./db/migrate.js";
import { HubRegistry } from "./hub/registry.js";
import { errorKind, logMeta } from "./log.js";
import { loadPush } from "./push/config.js";
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

// Push is optional (push spec §5): without a usable FCM_SERVICE_ACCOUNT the relay runs as before.
const push = loadPush(process.env);
if (push.gateway === null) logMeta("push_disabled", { reason: push.reason });
else logMeta("push_enabled", { project: push.projectId });

// Admin is optional too: without an ADMIN_PASSWORD of at least 16 characters the dashboard on
// ADMIN_HOST only answers 503 admin_disabled. Neither line says anything about the password itself.
const admin = adminStatus(config);
if (admin === "enabled") logMeta("admin_enabled", { host: config.adminHost });
else logMeta("admin_disabled", { reason: admin });

const hubs = new HubRegistry({ db });
const relay = await startRelay(
  { config, db, hubs, limiters: createRateLimiters(config), push: push.gateway },
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

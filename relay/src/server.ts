// Entry point of the relay container: `node dist/server.js` (dev: `npm run dev`).
import { adminStatus } from "./admin/app.js";
import { loadAppleSiwa } from "./auth/apple-rest.js";
import { type IdTokenVerifier, loadIdTokenVerifier } from "./auth/id-token.js";
import { createRateLimiters } from "./auth/rate-limit.js";
import { ConfigError, loadConfig, type Config } from "./config.js";
import { Db } from "./db/db.js";
import { migrate } from "./db/migrate.js";
import { HubRegistry } from "./hub/registry.js";
import { errorKind, logMeta } from "./log.js";
import { loadApns } from "./push/apns.js";
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

// Google / Apple / test-provider ID-token checks; an unreadable TEST_IDP_JWKS_PATH stops the relay.
let idTokens: IdTokenVerifier;
try {
  idTokens = loadIdTokenVerifier(config);
} catch (err) {
  fail(err instanceof ConfigError ? err.message : "invalid configuration");
}
if (config.googleClientIds.length === 0) logMeta("google_sign_in_disabled");
if (config.testIdp !== null) logMeta("test_idp_enabled");
if (!config.passwordLogin) logMeta("password_login_off");

// Sign in with Apple's REST side (refresh-token exchange and revocation) is optional: without the key
// the Apple sign-in itself works, but no refresh token is stored and nothing is revoked.
const siwa = loadAppleSiwa(process.env);
if (siwa.gateway === null) logMeta("apple_siwa_disabled", { reason: siwa.reason });
else logMeta("apple_siwa_enabled");

let db: Db;
try {
  db = Db.open(config.dbPath);
  migrate(db);
} catch (err) {
  fail(`cannot open database at ${config.dbPath} (${errorKind(err)})`);
}

// Push is optional (push spec §5): without a usable FCM_SERVICE_ACCOUNT the relay runs as before.
// The one FCM client serves POST /v1/notifications and the Android app's data messages.
const push = loadPush(process.env);
if (push.gateway === null) logMeta("push_disabled", { reason: push.reason });
else logMeta("push_enabled", { project: push.projectId });
// APNs for the native iPhone app is optional as well: without APNS_KEY_PATH, APNS_KEY_ID and
// APNS_TEAM_ID (and a readable .p8 key) POST /v2/notifications reaches Android phones only
// (503 only when FCM is off too).
const apns = loadApns(process.env);
if (apns.gateway === null) logMeta("apns_disabled", { reason: apns.reason });
else logMeta("apns_enabled");

// Admin is optional too: without an ADMIN_PASSWORD of at least 16 characters the dashboard on
// ADMIN_HOST only answers 503 admin_disabled. Neither line says anything about the password itself.
const admin = adminStatus(config);
if (admin === "enabled") logMeta("admin_enabled", { host: config.adminHost });
else logMeta("admin_disabled", { reason: admin });

// Relay v2 tickets need CMUX_RELAY_HMAC_SECRET (at least 32 bytes); without it they answer 503.
if (config.relayV2DisabledReason === null) logMeta("relay_v2_enabled");
else logMeta("relay_v2_disabled", { reason: config.relayV2DisabledReason });

const hubs = new HubRegistry({ db });
const relay = await startRelay(
  { config, db, hubs, limiters: createRateLimiters(config), push: push.gateway, fcm: push.gateway, apns: apns.gateway, idTokens, appleTokens: siwa.gateway },
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

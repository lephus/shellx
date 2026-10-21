import type { IncomingMessage } from "node:http";
import { Hono } from "hono";
import { ADMIN_STATIC_DIR, createAdminApp, hostName } from "./admin/app.js";
import type { PasswordHasher } from "./auth/password.js";
import { HasherBusyError, passwords as defaultPasswords } from "./auth/password.js";
import type { RateLimiters } from "./auth/rate-limit.js";
import type { AuthContext } from "./auth/session.js";
import type { Config } from "./config.js";
import type { Db } from "./db/db.js";
import type { HubRegistry } from "./hub/registry.js";
import { ApiError, errorBody, Errors } from "./http/errors.js";
import { errorKind, logMeta } from "./log.js";
import { accountRoutes } from "./routes/account.js";
import { authRoutes } from "./routes/auth.js";
import { deviceRoutes } from "./routes/devices.js";
import { notificationRoutes } from "./routes/notifications.js";
import { pairingRoutes } from "./routes/pairings.js";
import { machineRoutes } from "./v2/machines.js";
import { newSlot } from "./v2/encoding.js";
import { randomShareId, shareRoutes } from "./v2/shares.js";
import { relayTicketRoutes } from "./v2/relay-tickets.js";
import { machinePairingRoutes, randomPairingCode } from "./v2/pairings.js";
import type { PushGateway } from "./push/fcm.js";
import { webSocketAuth, webSocketUpgrade } from "./routes/ws.js";
import { readNativeLatest } from "./native-latest.js";
import { versionAnswer } from "./settings.js";
import { audienceOf, OS_VERSION_HEADER, PLATFORM_HEADER } from "./versions.js";

export interface AppDeps {
  config: Config;
  db: Db;
  hubs: HubRegistry;
  limiters: RateLimiters;
  /** Defaults to the process-wide argon2id hasher (at most 4 hashes at once, 32 waiting). */
  passwords?: PasswordHasher;
  /** Unix milliseconds; injectable for token-expiry tests. */
  now?: () => number;
  /** FCM gateway; null or absent when push is not configured (503 `push_unavailable`). */
  push?: PushGateway | null;
  /** Directory of the admin UI (index.html, admin.css, admin.js); defaults to `relay/admin/`. */
  adminStaticDir?: string;
  /** The 6-digit code of a new /v2 pairing; defaults to `randomInt(0, 1_000_000)` zero-padded. Injectable for tests. */
  pairingCode?: () => string;
  /** The 8-character id of a new share; defaults to random characters of the share alphabet. Injectable for tests. */
  shareId?: () => string;
  /** The relay slot of a new share; defaults to 16 random bytes. Injectable for tests. */
  shareSlot?: () => string;
}

export interface AppVariables {
  config: Config;
  db: Db;
  hubs: HubRegistry;
  limiters: RateLimiters;
  passwords: PasswordHasher;
  now: () => number;
  push: PushGateway | null;
  pairingCode: () => string;
  shareId: () => string;
  shareSlot: () => string;
  /** Set by `requireAuth` / `webSocketAuth` on authenticated routes only. */
  auth: AuthContext;
}

/** What @hono/node-server passes as `c.env`; `incoming.socket.remoteAddress` is the TCP peer. */
export interface AppBindings {
  incoming: IncomingMessage;
}

export type AppEnv = { Bindings: AppBindings; Variables: AppVariables };

export function createApp(deps: AppDeps): Hono<AppEnv> {
  const app = new Hono<AppEnv>();
  const admin = createAdminApp({
    config: deps.config,
    db: deps.db,
    hubs: deps.hubs,
    now: deps.now ?? Date.now,
    staticDir: deps.adminStaticDir ?? ADMIN_STATIC_DIR,
  });

  // First of all: a request for ADMIN_HOST goes to the admin app and only there (its own routes,
  // 404 and errors), so no relay route answers on the admin host. The admin app is mounted nowhere
  // else, so no admin route answers on any other host.
  app.use("*", async (c, next) => {
    if (hostName(c.req.header("Host")) === deps.config.adminHost) return admin.fetch(c.req.raw, c.env);
    await next();
  });

  app.use("*", async (c, next) => {
    c.set("config", deps.config);
    c.set("db", deps.db);
    c.set("hubs", deps.hubs);
    c.set("limiters", deps.limiters);
    c.set("passwords", deps.passwords ?? defaultPasswords);
    c.set("now", deps.now ?? Date.now);
    c.set("push", deps.push ?? null);
    c.set("pairingCode", deps.pairingCode ?? randomPairingCode);
    c.set("shareId", deps.shareId ?? randomShareId);
    c.set("shareSlot", deps.shareSlot ?? newSlot);
    await next();
  });

  app.get("/v1/version", (c) => {
    const config = c.get("config");
    // Per audience (X-ShellX-Platform / X-ShellX-OS-Version, K6); no header, flutter-macos < 14 and
    // an unparsable OS get today's body: the admin's override or MIN_AGENT / MIN_MOBILE, latest_agent from env.
    const audience = audienceOf(c.req.header(PLATFORM_HEADER), c.req.header(OS_VERSION_HEADER));
    const now = c.get("now")();
    const latest = {
      macos: audience === "native-macos" || audience === "flutter-macos-14" ? readNativeLatest(config.nativeManifestDir, "macos", now) : null,
      windows: audience === "native-windows" ? readNativeLatest(config.nativeManifestDir, "windows", now) : null,
    };
    return c.json(versionAnswer(c.get("db"), config, audience, latest));
  });

  app.route("/v1/auth", authRoutes);
  app.route("/v1/account", accountRoutes);
  app.route("/v1/devices", deviceRoutes);
  app.route("/v1/pairings", pairingRoutes);
  app.route("/v1/notifications", notificationRoutes);
  app.route("/v2/machines", machineRoutes);
  app.route("/v2/pairings", machinePairingRoutes);
  app.route("/v2/relay/tickets", relayTicketRoutes);
  app.route("/v2/shares", shareRoutes);
  app.get("/v1/ws", webSocketAuth, webSocketUpgrade);

  app.notFound((c) => {
    const e = Errors.notFound();
    return c.json(errorBody(e.code, e.message), e.status);
  });

  app.onError((err, c) => {
    if (err instanceof ApiError) return c.json(errorBody(err.code, err.message), err.status);
    if (err instanceof HasherBusyError) {
      // argon2 is saturated (M8): the same answer as the rate limiters, and nothing logged per request.
      const e = Errors.rateLimited();
      return c.json(errorBody(e.code, e.message), e.status);
    }
    logMeta("unhandled_error", { method: c.req.method, path: new URL(c.req.url).pathname, error: errorKind(err) });
    return c.json(errorBody("internal_error", "Internal error"), 500);
  });

  return app;
}

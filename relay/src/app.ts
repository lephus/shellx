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
import type { PushGateway } from "./push/fcm.js";
import { webSocketAuth, webSocketUpgrade } from "./routes/ws.js";
import { minVersions } from "./settings.js";

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
}

export interface AppVariables {
  config: Config;
  db: Db;
  hubs: HubRegistry;
  limiters: RateLimiters;
  passwords: PasswordHasher;
  now: () => number;
  push: PushGateway | null;
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
    await next();
  });

  app.get("/v1/version", (c) => {
    const config = c.get("config");
    // The admin's override from the dashboard when set, else MIN_AGENT / MIN_MOBILE; latest_agent is
    // env only (the desktop release pipeline commits it to deploy/relay.env).
    const min = minVersions(c.get("db"), config);
    return c.json({
      min_agent: min.min_agent,
      min_mobile: min.min_mobile,
      latest_agent: { version: config.latestAgentVersion, mac_url: config.macUrl, win_url: config.winUrl },
    });
  });

  app.route("/v1/auth", authRoutes);
  app.route("/v1/account", accountRoutes);
  app.route("/v1/devices", deviceRoutes);
  app.route("/v1/pairings", pairingRoutes);
  app.route("/v1/notifications", notificationRoutes);
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

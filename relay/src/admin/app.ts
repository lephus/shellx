import { createHash, timingSafeEqual } from "node:crypto";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { Hono, type Context, type MiddlewareHandler } from "hono";
import { deleteCookie, getCookie, setCookie } from "hono/cookie";
import type { AppBindings } from "../app.js";
import { clientIp } from "../auth/client-ip.js";
import { SlidingWindowLimiter } from "../auth/rate-limit.js";
import type { Config } from "../config.js";
import type { Db } from "../db/db.js";
import type { HubRegistry } from "../hub/registry.js";
import { jsonBodyLimit } from "../http/body-limit.js";
import { ApiError, errorBody, Errors } from "../http/errors.js";
import { errorKind, logMeta } from "../log.js";
import {
  envMinVersions, MIN_VERSION_KEYS, minVersionOverrides, setMinVersionOverride, type MinVersionKey,
} from "../settings.js";
import { isSettableVersion } from "../versions.js";
import { ADMIN_SESSION_TTL_MS, AdminSessions } from "./sessions.js";
import { adminStats } from "./stats.js";

/** `relay/admin/` (the UI files): `src/admin/` and `dist/admin/` are both two levels below the package root. */
export const ADMIN_STATIC_DIR = fileURLToPath(new URL("../../admin/", import.meta.url));

/** Shorter passwords leave admin disabled (a guessable password would expose every account's metadata). */
export const ADMIN_PASSWORD_MIN_CHARS = 16;
/** Failed sign-ins allowed per client IP within ADMIN_LOGIN_WINDOW_MS; beyond it, 429 even for the right password. */
export const ADMIN_LOGIN_FAILURES = 5;
export const ADMIN_LOGIN_WINDOW_MS = 15 * 60 * 1000;
export const ADMIN_COOKIE = "shellx_admin";

/**
 * On every admin response. The UI is three same-origin files with no inline script or style, so the
 * CSP can forbid everything else; nothing is cached (the pages show live account statistics).
 */
export const ADMIN_SECURITY_HEADERS: Readonly<Record<string, string>> = {
  "Content-Security-Policy":
    "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; " +
    "base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
  "X-Frame-Options": "DENY",
  "Cache-Control": "no-store",
};

/** The only static paths served; anything else that is not /api is 404 (no path ever reaches the file system). */
const STATIC_FILES: readonly (readonly [path: string, file: string, type: string])[] = [
  ["/", "index.html", "text/html; charset=utf-8"],
  ["/admin.css", "admin.css", "text/css; charset=utf-8"],
  ["/admin.js", "admin.js", "text/javascript; charset=utf-8"],
];

const AdminErrors = {
  disabled: () => new ApiError(503, "admin_disabled", "Admin is not enabled on this relay"),
  unauthorized: () => new ApiError(401, "unauthorized", "Sign in first"),
  invalidCredentials: () => new ApiError(401, "invalid_credentials", "Password is incorrect"),
  invalidBody: () => new ApiError(400, "invalid_body", "Request body is not valid"),
  invalidVersion: () => new ApiError(400, "invalid_version", "Versions must look like 1.2.3"),
} as const;

/** Whether admin is on, or why not (logged once at startup as `admin_enabled` / `admin_disabled`). */
export function adminStatus(config: Pick<Config, "adminPassword">): "enabled" | "no_password" | "password_too_short" {
  if (config.adminPassword === null) return "no_password";
  return [...config.adminPassword].length >= ADMIN_PASSWORD_MIN_CHARS ? "enabled" : "password_too_short";
}

/** The host name of a Host header: port and a trailing dot dropped, lower-cased; "" when absent. */
export function hostName(header: string | undefined): string {
  const host = (header ?? "").trim().toLowerCase();
  if (host.startsWith("[")) return host.slice(0, host.indexOf("]") + 1); // IPv6 literal, never a DNS name
  return host.replace(/:\d*$/, "").replace(/\.$/, "");
}

/** `https://<host>`, or `http://<host>[:port]` for local development (`npm run dev` on admin.localhost). */
function isAdminOrigin(origin: string, host: string): boolean {
  if (origin === `https://${host}` || origin === `http://${host}`) return true;
  const prefix = `http://${host}:`;
  return origin.startsWith(prefix) && /^\d{1,5}$/.test(origin.slice(prefix.length));
}

function sha256(text: string): Buffer {
  return createHash("sha256").update(text, "utf8").digest();
}

async function readBody(c: Context): Promise<Record<string, unknown>> {
  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    throw AdminErrors.invalidBody();
  }
  if (typeof body !== "object" || body === null || Array.isArray(body)) throw AdminErrors.invalidBody();
  return body as Record<string, unknown>;
}

export interface AdminDeps {
  config: Config;
  db: Db;
  hubs: HubRegistry;
  now: () => number;
  /** Directory holding index.html, admin.css and admin.js. */
  staticDir: string;
}

type AdminEnv = { Bindings: AppBindings };

/**
 * The admin dashboard on ADMIN_HOST: three static files and a small JSON API (stats, minimum
 * versions). `createApp` hands it every request whose Host is ADMIN_HOST and nothing else, so none of
 * this is reachable on the relay's own host name, and none of the relay's routes on this one.
 *
 * Sign-in is one shared password (ADMIN_PASSWORD) compared as SHA-256 digests with timingSafeEqual
 * (equal lengths, so the comparison time says nothing about the password). The session cookie is
 * HttpOnly, Secure and SameSite=Strict; mutating calls additionally need `Content-Type:
 * application/json` (which a cross-site form or a no-CORS fetch cannot send without a preflight
 * this app never grants) and, when the browser sends one, an Origin of ADMIN_HOST.
 */
export function createAdminApp(deps: AdminDeps): Hono<AdminEnv> {
  const app = new Hono<AdminEnv>();
  const { config, db, now } = deps;
  const enabled = adminStatus(config) === "enabled";
  const passwordDigest = enabled ? sha256(config.adminPassword!) : null;
  const sessions = new AdminSessions(now);
  const loginFailures = new SlidingWindowLimiter({ limit: ADMIN_LOGIN_FAILURES, windowMs: ADMIN_LOGIN_WINDOW_MS, now });

  const signedIn = (c: Context): boolean => enabled && sessions.isValid(getCookie(c, ADMIN_COOKIE));
  const requireAdmin: MiddlewareHandler<AdminEnv> = async (c, next) => {
    if (!signedIn(c)) throw AdminErrors.unauthorized();
    await next();
  };

  app.use("*", async (c, next) => {
    await next();
    for (const [name, value] of Object.entries(ADMIN_SECURITY_HEADERS)) c.res.headers.set(name, value);
  });

  app.use("/api/*", async (c, next) => {
    if (!enabled && c.req.path !== "/api/session") throw AdminErrors.disabled();
    if (c.req.method !== "GET" && c.req.method !== "HEAD") { // every call that may change something
      const type = c.req.header("Content-Type")?.split(";")[0]!.trim().toLowerCase();
      const origin = c.req.header("Origin");
      if (type !== "application/json" || (origin !== undefined && !isAdminOrigin(origin, config.adminHost))) {
        throw Errors.forbidden();
      }
    }
    await next();
  });

  app.get("/api/session", (c) => c.json({ enabled, signed_in: signedIn(c) }));

  app.post("/api/login", jsonBodyLimit, async (c) => {
    const body = await readBody(c);
    // Checked after the body is read, with no await between this check, the comparison and the
    // recorded failure: parallel requests cannot all pass the check before any failure counts.
    const ip = clientIp(c.req.header("X-Real-IP"), c.env.incoming.socket.remoteAddress);
    if (loginFailures.isLimited(ip)) throw Errors.rateLimited();
    const password = typeof body.password === "string" ? body.password : "";
    if (!timingSafeEqual(sha256(password), passwordDigest!)) {
      await loginFailures.limit(ip);
      logMeta("admin_login_failed");
      throw AdminErrors.invalidCredentials();
    }
    setCookie(c, ADMIN_COOKIE, sessions.create(), {
      httpOnly: true, secure: true, sameSite: "Strict", path: "/", maxAge: ADMIN_SESSION_TTL_MS / 1000,
    });
    logMeta("admin_login");
    return c.body(null, 204);
  });

  app.post("/api/logout", (c) => {
    sessions.end(getCookie(c, ADMIN_COOKIE));
    deleteCookie(c, ADMIN_COOKIE, { httpOnly: true, secure: true, sameSite: "Strict", path: "/" });
    return c.body(null, 204);
  });

  app.get("/api/stats", requireAdmin, (c) => c.json(adminStats(db, now(), deps.hubs.liveDevices())));

  const settings = () => {
    const env = envMinVersions(config);
    const overrides = minVersionOverrides(db);
    const entry = (key: MinVersionKey) => ({ value: overrides[key] ?? env[key], env: env[key], overridden: key in overrides });
    return {
      min_agent: entry("min_agent"),
      min_mobile: entry("min_mobile"),
      latest_agent: { version: config.latestAgentVersion, mac_url: config.macUrl, win_url: config.winUrl },
    };
  };

  app.get("/api/settings", requireAdmin, (c) => c.json(settings()));

  /** Any subset of {min_agent, min_mobile}: "x.y.z" sets the override, null removes it (back to env). */
  app.put("/api/settings", requireAdmin, jsonBodyLimit, async (c) => {
    const body = await readBody(c);
    const changes: [MinVersionKey, string | null][] = [];
    for (const [key, value] of Object.entries(body)) {
      if (!(MIN_VERSION_KEYS as readonly string[]).includes(key)) throw AdminErrors.invalidBody();
      if (value !== null && typeof value !== "string") throw AdminErrors.invalidBody();
      if (value !== null && !isSettableVersion(value)) throw AdminErrors.invalidVersion();
      changes.push([key as MinVersionKey, value]);
    }
    const at = now();
    db.transaction(() => {
      for (const [key, value] of changes) setMinVersionOverride(db, key, value, at);
    });
    if (changes.length > 0) logMeta("admin_settings_changed", Object.fromEntries(changes));
    return c.json(settings());
  });

  for (const [path, file, type] of STATIC_FILES) {
    app.get(path, async (c) => {
      let content: string;
      try {
        content = await readFile(join(deps.staticDir, file), "utf8");
      } catch {
        throw Errors.notFound();
      }
      return c.body(content, 200, { "Content-Type": type });
    });
  }

  app.notFound((c) => {
    const e = Errors.notFound();
    return c.json(errorBody(e.code, e.message), e.status);
  });

  app.onError((err, c) => {
    if (err instanceof ApiError) return c.json(errorBody(err.code, err.message), err.status);
    logMeta("admin_unhandled_error", { method: c.req.method, path: new URL(c.req.url).pathname, error: errorKind(err) });
    return c.json(errorBody("internal_error", "Internal error"), 500);
  });

  return app;
}

import type { IncomingMessage } from "node:http";
import { Hono } from "hono";
import type { Config } from "./config.js";
import type { Db } from "./db/db.js";
import { ApiError, errorBody, Errors } from "./http/errors.js";
import { errorKind, logMeta } from "./log.js";

export interface AppDeps {
  config: Config;
  db: Db;
  /** Unix milliseconds; injectable for token-expiry tests. */
  now?: () => number;
}

export interface AppVariables {
  config: Config;
  db: Db;
  now: () => number;
}

/** What @hono/node-server passes as `c.env`; `incoming.socket.remoteAddress` is the TCP peer. */
export interface AppBindings {
  incoming: IncomingMessage;
}

export type AppEnv = { Bindings: AppBindings; Variables: AppVariables };

export function createApp(deps: AppDeps): Hono<AppEnv> {
  const app = new Hono<AppEnv>();

  app.use("*", async (c, next) => {
    c.set("config", deps.config);
    c.set("db", deps.db);
    c.set("now", deps.now ?? Date.now);
    await next();
  });

  app.get("/v1/version", (c) => {
    const config = c.get("config");
    return c.json({
      min_agent: config.minAgent,
      min_mobile: config.minMobile,
      latest_agent: { version: config.latestAgentVersion, mac_url: config.macUrl, win_url: config.winUrl },
    });
  });

  app.notFound((c) => {
    const e = Errors.notFound();
    return c.json(errorBody(e.code, e.message), e.status);
  });

  app.onError((err, c) => {
    if (err instanceof ApiError) return c.json(errorBody(err.code, err.message), err.status);
    logMeta("unhandled_error", { method: c.req.method, path: new URL(c.req.url).pathname, error: errorKind(err) });
    return c.json(errorBody("internal_error", "Internal error"), 500);
  });

  return app;
}

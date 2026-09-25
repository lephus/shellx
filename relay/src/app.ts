import { Hono } from "hono";
import { limitersFromEnv, type RateLimiters } from "./auth/rate-limit";
import type { Env } from "./env";
import { ApiError, errorBody, Errors } from "./http/errors";
import { logMeta } from "./log";

export interface AppDeps {
  /** Tests inject fakes; production uses the Workers rate limiting bindings. */
  limiters?: (env: Env) => RateLimiters;
  /** Unix milliseconds; injectable for token-expiry tests. */
  now?: () => number;
}

export interface AppVariables {
  limiters: RateLimiters;
  now: () => number;
}

export type AppEnv = { Bindings: Env; Variables: AppVariables };

export function createApp(deps: AppDeps = {}): Hono<AppEnv> {
  const app = new Hono<AppEnv>();

  app.use("*", async (c, next) => {
    c.set("limiters", (deps.limiters ?? limitersFromEnv)(c.env));
    c.set("now", deps.now ?? Date.now);
    await next();
  });

  app.get("/v1/version", (c) =>
    c.json({
      min_agent: c.env.MIN_AGENT,
      min_mobile: c.env.MIN_MOBILE,
      latest_agent: { version: c.env.LATEST_AGENT_VERSION, mac_url: c.env.MAC_URL, win_url: c.env.WIN_URL },
    }),
  );

  app.notFound((c) => {
    const e = Errors.notFound();
    return c.json(errorBody(e.code, e.message), e.status);
  });

  app.onError((err, c) => {
    if (err instanceof ApiError) return c.json(errorBody(err.code, err.message), err.status);
    logMeta("unhandled_error", { method: c.req.method, path: new URL(c.req.url).pathname, error: err.name });
    return c.json(errorBody("internal_error", "Internal error"), 500);
  });

  return app;
}

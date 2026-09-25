import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { bindingLimiter, limitersFromEnv } from "../src/auth/rate-limit";
import { call, makeApp } from "./helpers";

describe("app skeleton", () => {
  it("GET /v1/version returns the configured versions", async () => {
    const res = await call(makeApp(), "GET", "/v1/version");
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      min_agent: "1.0.0",
      min_mobile: "1.0.0",
      latest_agent: {
        version: "1.0.0",
        mac_url: "https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg",
        win_url: "https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe",
      },
    });
  });

  it("unknown routes return the JSON error shape", async () => {
    const res = await call(makeApp(), "GET", "/v1/nope");
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: { code: "not_found", message: "Not found" } });
  });

  it("D1 migrations created the four tables", async () => {
    const { results } = await env.DB.prepare(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('users','devices','tokens','pairings') ORDER BY name",
    ).all<{ name: string }>();
    expect(results.map((r) => r.name)).toEqual(["devices", "pairings", "tokens", "users"]);
  });

  it("pairings carries the agent-generated pairing_id (TEXT NOT NULL) and keeps its (agent, mobile) key", async () => {
    const { results } = await env.DB.prepare("PRAGMA table_info(pairings)")
      .all<{ name: string; type: string; notnull: number; pk: number }>();
    expect(results.map((c) => [c.name, c.type, c.notnull, c.pk])).toEqual([
      ["agent_id", "TEXT", 1, 1],
      ["mobile_id", "TEXT", 1, 2],
      ["pairing_id", "TEXT", 1, 0],
      ["created_at", "INTEGER", 1, 0],
    ]);
  });

  it("bindingLimiter maps the binding outcome and passes the key through", async () => {
    const seen: string[] = [];
    const limiter = bindingLimiter({
      limit: async ({ key }) => {
        seen.push(key);
        return { success: key !== "blocked" };
      },
    });
    expect(await limiter.limit("203.0.113.7")).toBe(true);
    expect(await limiter.limit("blocked")).toBe(false);
    expect(seen).toEqual(["203.0.113.7", "blocked"]);
  });

  it("the local config disables rate limits and still wires the three bindings", async () => {
    expect(env.RATE_LIMITS_ENABLED).toBe("false");
    expect(await bindingLimiter(env.LOGIN_IP_LIMITER).limit("wiring-check")).toBe(true);
    expect(await bindingLimiter(env.LOGIN_EMAIL_LIMITER).limit("wiring-check")).toBe(true);
    expect(await bindingLimiter(env.REGISTER_IP_LIMITER).limit("wiring-check")).toBe(true);
  });

  const refuse: RateLimit = { limit: async () => ({ success: false }) };
  const refusingEnv = (flag: string) => ({
    ...env,
    RATE_LIMITS_ENABLED: flag,
    LOGIN_IP_LIMITER: refuse,
    LOGIN_EMAIL_LIMITER: refuse,
    REGISTER_IP_LIMITER: refuse,
  });

  it('RATE_LIMITS_ENABLED = "false" turns every limiter off', async () => {
    const limiters = limitersFromEnv(refusingEnv("false"));
    expect(await limiters.loginIp.limit("k")).toBe(true);
    expect(await limiters.loginEmail.limit("k")).toBe(true);
    expect(await limiters.registerIp.limit("k")).toBe(true);
  });

  it('any other value ("true" in staging/production) enforces the bindings', async () => {
    for (const flag of ["true", "", "False", "0"]) {
      const limiters = limitersFromEnv(refusingEnv(flag));
      expect(await limiters.loginIp.limit("k")).toBe(false);
      expect(await limiters.loginEmail.limit("k")).toBe(false);
      expect(await limiters.registerIp.limit("k")).toBe(false);
    }
  });
});

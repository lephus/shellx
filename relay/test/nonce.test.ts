import { describe, expect, it } from "vitest";
import { consumeNonce, MAX_LIVE_NONCES } from "../src/auth/nonces.js";
import { createRateLimiters } from "../src/auth/rate-limit.js";
import { hashToken } from "../src/auth/tokens.js";
import { call, CountingLimiter, db, errorCode, makeApp, newNonce, unlimited } from "./helpers.js";

const T0 = 1_800_000_000_000;
const ask = (app: ReturnType<typeof makeApp>, ip?: string) => call(app, "POST", "/v1/auth/nonce", { ip, body: {} });

describe("POST /v1/auth/nonce", () => {
  it("answers 201 with a 43-character base64url nonce for 600 s and stores only its SHA-256", async () => {
    const app = makeApp({ now: () => T0 });
    const res = await ask(app);
    expect(res.status).toBe(201);
    const body = await res.json<{ nonce: string; expires_in: number }>();
    expect(body).toEqual({ nonce: expect.stringMatching(/^[A-Za-z0-9_-]{43}$/), expires_in: 600 });
    expect(db().get("SELECT expires_at FROM auth_nonces WHERE nonce_hash = ?", await hashToken(body.nonce))).toEqual({ expires_at: T0 + 600_000 });
    expect(db().get("SELECT COUNT(*) AS n FROM auth_nonces WHERE nonce_hash = ?", Buffer.from(body.nonce))).toEqual({ n: 0 });
  });

  it("is used at most once and never at or after its expiry", async () => {
    const app = makeApp({ now: () => T0 });
    const once = await newNonce(app);
    expect(await consumeNonce(db(), once, T0 + 1)).toBe(true);
    expect(await consumeNonce(db(), once, T0 + 2)).toBe(false);
    expect(await consumeNonce(db(), await newNonce(app), T0 + 600_000)).toBe(false);
    expect(await consumeNonce(db(), "n".repeat(43), T0)).toBe(false);
    expect(await consumeNonce(db(), 42, T0)).toBe(false);
  });

  it("deletes expired nonces when the next one is issued, and answers 429 while 50 000 are live", async () => {
    let now = T0;
    const app = makeApp({ now: () => now });
    expect(MAX_LIVE_NONCES).toBe(50_000);
    db().run(`WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 50000)
              INSERT INTO auth_nonces (nonce_hash, expires_at) SELECT randomblob(32), ? FROM n`, T0 + 600_000);
    const full = await ask(app);
    expect([full.status, await errorCode(full)]).toEqual([429, "rate_limited"]);
    now += 600_000;
    expect((await ask(app)).status).toBe(201);
    expect(db().get("SELECT COUNT(*) AS n FROM auth_nonces")).toEqual({ n: 1 });
  });

  it("is limited per X-Real-IP: 30 per minute in production, nothing with RATE_LIMITS_ENABLED=false", async () => {
    const nonceIp = new CountingLimiter(2);
    const counted = makeApp({ limiters: { ...unlimited, nonceIp } });
    for (const status of [201, 201, 429]) expect((await ask(counted, "198.51.100.9")).status).toBe(status);
    expect(nonceIp.calls).toEqual(Array(3).fill("198.51.100.9"));
    const production = makeApp({ limiters: createRateLimiters({ rateLimitsEnabled: true }) });
    for (let i = 0; i < 30; i++) expect((await ask(production, "198.51.100.10")).status).toBe(201);
    expect((await ask(production, "198.51.100.10")).status).toBe(429);
    expect((await ask(production, "198.51.100.11")).status).toBe(201);
    const off = makeApp({ limiters: createRateLimiters({ rateLimitsEnabled: false }) });
    for (let i = 0; i < 40; i++) expect((await ask(off, "198.51.100.12")).status).toBe(201);
  });
});

import { join } from "node:path";
import Database from "better-sqlite3";
import { afterEach, describe, expect, it, vi } from "vitest";
import { createRateLimiters } from "../src/auth/rate-limit.js";
import { authenticate } from "../src/auth/session.js";
import { hashToken, TOKEN_IDLE_TTL_MS, TOKEN_TOUCH_INTERVAL_MS } from "../src/auth/tokens.js";
import { Db } from "../src/db/db.js";
import { HubRegistry } from "../src/hub/registry.js";
import {
  call, CountingLimiter, db, deviceBody, errorCode, loginDevice, makeApp, PASSWORD, randomEmail, randomPublicKey,
  registerAccount, tempDir, unlimited,
} from "./helpers.js";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

afterEach(() => {
  vi.restoreAllMocks();
});

describe("POST /v1/auth/register", () => {
  it("creates user, device and token; stores only hashes", async () => {
    const app = makeApp();
    const email = randomEmail();
    const device = deviceBody("agent");
    const res = await call(app, "POST", "/v1/auth/register", { body: { email, password: PASSWORD, device } });
    expect(res.status).toBe(201);
    const body = await res.json<{ user_id: string; device_id: string; token: string }>();
    expect(body.user_id).toMatch(UUID_RE);
    expect(body.device_id).toMatch(UUID_RE);
    expect(body.token).toMatch(/^[A-Za-z0-9_-]{43}$/);

    const user = db().get<{ email: string; password_hash: string }>("SELECT email, password_hash FROM users WHERE id = ?", body.user_id);
    expect(user?.email).toBe(email);
    expect(user?.password_hash).toMatch(/^\$argon2id\$v=19\$m=19456,t=2,p=1\$/);

    const tokenRow = db().get<{ device_id: string }>("SELECT device_id FROM tokens WHERE token_hash = ?", await hashToken(body.token));
    expect(tokenRow?.device_id).toBe(body.device_id);
    const rawToken = db().get<{ n: number }>("SELECT COUNT(*) AS n FROM tokens WHERE token_hash = ?", body.token);
    expect(rawToken?.n).toBe(0);
  });

  it("normalises the email (whitespace + uppercase) before storing", async () => {
    const app = makeApp();
    const local = `Mixed.Case-${crypto.randomUUID()}`;
    const res = await call(app, "POST", "/v1/auth/register", {
      body: { email: `  ${local}@Example.COM \n`, password: PASSWORD, device: deviceBody("agent") },
    });
    expect(res.status).toBe(201);
    const { user_id } = await res.json<{ user_id: string }>();
    const row = db().get<{ email: string }>("SELECT email FROM users WHERE id = ?", user_id);
    expect(row?.email).toBe(`${local.toLowerCase()}@example.com`);
  });

  it.each([
    [{ email: "not-an-email" }, 400, "invalid_email"],
    [{ email: 42 }, 400, "invalid_email"],
    [{ email: "someone@yopmail.com" }, 400, "disposable_email"],
    [{ email: "someone@x.yopmail.com" }, 400, "disposable_email"],
    [{ email: "  Someone@X.YOPMAIL.com " }, 400, "disposable_email"],
    [{ password: "1234567" }, 400, "weak_password"],
    [{ password: "x".repeat(129) }, 400, "weak_password"],
    [{ password: 12345678 }, 400, "weak_password"],
    [{ device: undefined }, 400, "invalid_device"],
    [{ device: deviceBody("agent", { kind: "tablet" }) }, 400, "invalid_device"],
    [{ device: deviceBody("agent", { platform: "linux" }) }, 400, "invalid_device"],
    [{ device: deviceBody("agent", { name: "   " }) }, 400, "invalid_device"],
    [{ device: deviceBody("agent", { name: "n".repeat(101) }) }, 400, "invalid_device"],
    [{ device: deviceBody("agent", { public_key: "AAAA" }) }, 400, "invalid_device"],
    [{ device: deviceBody("agent", { public_key: `${randomPublicKey()}=` }) }, 400, "invalid_device"],
  ])("rejects %j with %i %s", async (override, status, code) => {
    const body = { email: randomEmail(), password: PASSWORD, device: deviceBody("agent"), ...override };
    const res = await call(makeApp(), "POST", "/v1/auth/register", { body });
    expect(res.status).toBe(status);
    expect(await errorCode(res)).toBe(code);
  });

  it("rejects a non-JSON body with 400 bad_request", async () => {
    const res = await call(makeApp(), "POST", "/v1/auth/register", { body: "{not json" });
    expect(res.status).toBe(400);
    expect(await errorCode(res)).toBe("bad_request");
  });

  it("returns 409 email_taken for the same address in a different case", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const res = await call(app, "POST", "/v1/auth/register", {
      body: { email: ` ${account.email.toUpperCase()} `, password: PASSWORD, device: deviceBody("agent") },
    });
    expect(res.status).toBe(409);
    expect(await errorCode(res)).toBe("email_taken");
  });

  it("returns 429 rate_limited once the per-IP register limiter refuses", async () => {
    const registerIp = new CountingLimiter(3);
    const app = makeApp({ limiters: { ...unlimited, registerIp } });
    for (let i = 0; i < 3; i++) {
      const ok = await call(app, "POST", "/v1/auth/register", {
        ip: "198.51.100.1",
        body: { email: randomEmail(), password: PASSWORD, device: deviceBody("agent") },
      });
      expect(ok.status).toBe(201);
    }
    const res = await call(app, "POST", "/v1/auth/register", {
      ip: "198.51.100.1",
      body: { email: randomEmail(), password: PASSWORD, device: deviceBody("agent") },
    });
    expect(res.status).toBe(429);
    expect(await errorCode(res)).toBe("rate_limited");
    expect(registerIp.calls).toEqual(Array(4).fill("198.51.100.1"));
  });
});

describe("production rate limits (createRateLimiters, keyed by X-Real-IP)", () => {
  const register = (app: ReturnType<typeof makeApp>, ip?: string) =>
    call(app, "POST", "/v1/auth/register", {
      ip,
      body: { email: randomEmail(), password: PASSWORD, device: deviceBody("agent") },
    });

  it("allows 3 registrations per X-Real-IP per minute, then answers 429; another IP is unaffected", async () => {
    const app = makeApp({ limiters: createRateLimiters({ rateLimitsEnabled: true }) });
    for (let i = 0; i < 3; i++) expect((await register(app, "198.51.100.10")).status).toBe(201);
    const refused = await register(app, "198.51.100.10");
    expect(refused.status).toBe(429);
    expect(await errorCode(refused)).toBe("rate_limited");
    expect((await register(app, "198.51.100.11")).status).toBe(201);
  });

  it('turns every limit off when RATE_LIMITS_ENABLED is "false"', async () => {
    const app = makeApp({ limiters: createRateLimiters({ rateLimitsEnabled: false }) });
    for (let i = 0; i < 5; i++) expect((await register(app, "198.51.100.12")).status).toBe(201);
  });

  it("logs neither the IP nor the email of a refused request", async () => {
    const app = makeApp({ limiters: createRateLimiters({ rateLimitsEnabled: true }) });
    const lines: string[] = [];
    vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    });
    const email = randomEmail();
    const statuses: number[] = [];
    for (let i = 0; i < 12; i++) {
      const res = await call(app, "POST", "/v1/auth/login", {
        ip: "198.51.100.13",
        body: { email, password: "wrong password", device: deviceBody("mobile") },
      });
      statuses.push(res.status);
    }
    expect(statuses).toContain(429); // otherwise this proves nothing about a refused request
    const output = lines.join("\n");
    expect(output).not.toContain("198.51.100.13");
    expect(output).not.toContain(email);
  });
});

describe("POST /v1/auth/login", () => {
  it("logs in with a differently-cased, padded email and creates a new device for a new key", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const res = await call(app, "POST", "/v1/auth/login", {
      body: { email: `\t${account.email.toUpperCase()}  `, password: PASSWORD, device: deviceBody("mobile") },
    });
    expect(res.status).toBe(200);
    const body = await res.json<{ user_id: string; device_id: string; token: string }>();
    expect(body.user_id).toBe(account.agent.userId);
    expect(body.device_id).not.toBe(account.agent.deviceId);
    expect(body.token).toMatch(/^[A-Za-z0-9_-]{43}$/);
  });

  it("reuses the device_id for a known public key and replaces its previous token", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const first = await loginDevice(app, account, "mobile");
    const second = await loginDevice(app, account, "mobile", first.publicKey);
    expect(second.deviceId).toBe(first.deviceId);
    const now = Date.now();
    expect(await authenticate(db(), first.token, now)).toBeNull();
    expect(await authenticate(db(), second.token, now)).toEqual({
      userId: account.agent.userId, deviceId: first.deviceId, kind: "mobile",
    });
  });

  it("returns 401 invalid_credentials for a wrong password or an unknown email", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const wrong = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: "wrong password", device: deviceBody("mobile") },
    });
    expect(wrong.status).toBe(401);
    expect(await errorCode(wrong)).toBe("invalid_credentials");
    const unknown = await call(app, "POST", "/v1/auth/login", {
      body: { email: randomEmail(), password: PASSWORD, device: deviceBody("mobile") },
    });
    expect(unknown.status).toBe(401);
    expect(await errorCode(unknown)).toBe("invalid_credentials");
  });

  it("accepts an NFC password for an account registered with the NFD spelling", async () => {
    const app = makeApp();
    const nfc = "Mật khẩu đẹp 2026".normalize("NFC");
    const account = await registerAccount(app, randomEmail(), nfc.normalize("NFD"));
    const res = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: nfc, device: deviceBody("mobile") },
    });
    expect(res.status).toBe(200);
  });

  it("rate limits per IP (10) and per normalised email (5)", async () => {
    const loginIp = new CountingLimiter(10);
    const loginEmail = new CountingLimiter(5);
    const app = makeApp({ limiters: { ...unlimited, loginIp, loginEmail } });
    const account = await registerAccount(app);
    const attempt = (email: string, ip: string) =>
      call(app, "POST", "/v1/auth/login", { ip, body: { email, password: "wrong password", device: deviceBody("mobile") } });

    for (let i = 0; i < 5; i++) expect((await attempt(i % 2 ? account.email.toUpperCase() : account.email, `192.0.2.${i}`)).status).toBe(401);
    const sixth = await attempt(` ${account.email} `, "192.0.2.99");
    expect(sixth.status).toBe(429);
    expect(await errorCode(sixth)).toBe("rate_limited");
    expect(new Set(loginEmail.calls)).toEqual(new Set([account.email]));

    for (let i = 0; i < 10; i++) expect((await attempt(randomEmail(), "198.51.100.200")).status).toBe(401);
    const eleventh = await attempt(randomEmail(), "198.51.100.200");
    expect(eleventh.status).toBe(429);
  });

  it("keys a request without X-Real-IP by its socket address", async () => {
    const loginIp = new CountingLimiter(10);
    const app = makeApp({ limiters: { ...unlimited, loginIp } });
    await call(app, "POST", "/v1/auth/login", {
      ip: null,
      body: { email: randomEmail(), password: "wrong password", device: deviceBody("mobile") },
    });
    expect(loginIp.calls).toEqual(["127.0.0.1"]);
  });

  it("never logs passwords, tokens or email addresses", async () => {
    const lines: string[] = [];
    const capture = (...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    };
    vi.spyOn(console, "log").mockImplementation(capture);
    vi.spyOn(console, "info").mockImplementation(capture);
    vi.spyOn(console, "warn").mockImplementation(capture);
    vi.spyOn(console, "error").mockImplementation(capture);
    const app = makeApp();
    const password = "Secret-Pa55word-XYZ";
    const account = await registerAccount(app, randomEmail(), password);
    await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: "Wrong-Pa55word-XYZ", device: deviceBody("mobile") },
    });
    const session = await loginDevice(app, account, "mobile");
    const output = lines.join("\n");
    expect(lines.length).toBeGreaterThan(0);
    for (const secret of [password, "Wrong-Pa55word-XYZ", account.agent.token, session.token, account.email]) {
      expect(output).not.toContain(secret);
    }
  });
});

describe("token lifetime", () => {
  it("expires after 90 idle days and refreshes last_used_at at most hourly", async () => {
    const t0 = 1_800_000_000_000;
    const app = makeApp({ now: () => t0 });
    const account = await registerAccount(app);
    const hash = await hashToken(account.agent.token);
    const lastUsed = () => db().get<{ last_used_at: number }>("SELECT last_used_at FROM tokens WHERE token_hash = ?", hash)?.last_used_at;

    expect(await authenticate(db(), account.agent.token, t0 + 30 * 60 * 1000)).not.toBeNull();
    expect(lastUsed()).toBe(t0);
    const t1 = t0 + TOKEN_TOUCH_INTERVAL_MS;
    expect(await authenticate(db(), account.agent.token, t1)).not.toBeNull();
    expect(lastUsed()).toBe(t1);

    expect(await authenticate(db(), account.agent.token, t1 + TOKEN_IDLE_TTL_MS)).not.toBeNull();
    const t2 = t1 + TOKEN_IDLE_TTL_MS;
    expect(await authenticate(db(), account.agent.token, t2 + TOKEN_IDLE_TTL_MS + 1)).toBeNull();
    expect(lastUsed()).toBeUndefined();
  });

  it("rejects missing and malformed tokens", async () => {
    expect(await authenticate(db(), null, Date.now())).toBeNull();
    expect(await authenticate(db(), "A".repeat(43), Date.now())).toBeNull();
  });
});

describe("database contention", () => {
  it("answers 500 internal_error while another process holds the write lock, logs only SQLITE_BUSY, and recovers", async () => {
    db(); // create the test database file
    const path = join(tempDir(), "relay.db");
    const impatient = Db.open(path, { busyTimeoutMs: 100 });
    const app = makeApp({ db: impatient, hubs: new HubRegistry({ db: impatient }) });
    const lines: string[] = [];
    vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    });
    const other = new Database(path); // e.g. the reset-password script in the same volume
    const email = randomEmail();
    const register = () =>
      call(app, "POST", "/v1/auth/register", { body: { email, password: PASSWORD, device: deviceBody("agent") } });
    try {
      other.exec("BEGIN IMMEDIATE");
      const blocked = await register();
      expect(blocked.status).toBe(500);
      expect(await blocked.json()).toEqual({ error: { code: "internal_error", message: "Internal error" } });
      expect((await call(app, "GET", "/v1/version")).status).toBe(200); // still serving
      other.exec("ROLLBACK");
      expect((await register()).status).toBe(201); // nothing half-written by the failed attempt
    } finally {
      other.close();
      impatient.close();
    }
    const output = lines.join("\n");
    expect(output).toContain('"event":"unhandled_error"');
    expect(output).toContain('"error":"SQLITE_BUSY"');
    expect(output).not.toContain(email);
    expect(output).not.toContain("INSERT");
  });
});

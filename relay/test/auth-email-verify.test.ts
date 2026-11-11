import { describe, expect, it } from "vitest";
import type { AppDeps } from "../src/app.js";
import { insertToken } from "../src/auth/session.js";
import { hashToken } from "../src/auth/tokens.js";
import { FakeEmailGateway } from "./fake-email.js";
import {
  call, CountingLimiter, db, deviceBody, emailSession, errorCode, googleSession, loginDevice, makeApp, registerAccount, requestEmailCode,
  seedUser, signInEmail, TEST_CONFIG, type TestApp, unlimited,
} from "./helpers.js";

const T0 = 1_800_000_000_000;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const CODE = "004217";

function setup(deps: Partial<AppDeps> = {}) {
  const mail = new FakeEmailGateway();
  return { mail, app: makeApp({ email: mail, emailCode: () => CODE, ...deps }) };
}
const verify = (app: TestApp, challengeId: unknown, code: unknown, device: unknown = deviceBody("mobile")) =>
  call(app, "POST", "/v1/auth/email/verify", { body: { challenge_id: challengeId, code, device } });
const devices = (app: TestApp, token: string) => call(app, "GET", "/v1/devices", { token });
const identities = (userId: string) =>
  db().all<{ provider: string; subject: string }>("SELECT provider, subject FROM identities WHERE user_id = ? ORDER BY provider", userId);
const count = (table: string) => db().get<{ n: number }>(`SELECT COUNT(*) AS n FROM ${table}`)!.n;
const seedAppleIdentity = (userId: string, subject: string, email: string) =>
  db().run(
    "INSERT INTO identities (id, provider, subject, user_id, email, is_private_email, created_at, last_used_at) VALUES (?, 'apple', ?, ?, ?, 1, 1, 1)",
    crypto.randomUUID(), subject, userId, email,
  );

describe("POST /v1/auth/email/verify", () => {
  it("creates an account on the first code: the normalized address, no password, one email identity, an email token", async () => {
    const { mail, app } = setup();
    const res = await signInEmail(app, mail, { email: "  New.User@Example.com " });
    expect(res.status).toBe(200);
    const body = await res.json<{ user_id: string; device_id: string; token: string }>();
    expect(body).toEqual({
      user_id: expect.stringMatching(UUID_RE), device_id: expect.stringMatching(UUID_RE), token: expect.stringMatching(/^[A-Za-z0-9_-]{43}$/), email: "new.user@example.com",
    });
    expect(db().get("SELECT email, password_hash FROM users WHERE id = ?", body.user_id)).toEqual({ email: "new.user@example.com", password_hash: null });
    expect(db().all("SELECT provider, subject, email, is_private_email FROM identities")).toEqual([
      { provider: "email", subject: "new.user@example.com", email: "new.user@example.com", is_private_email: 0 },
    ]);
    const row = db().get<{ auth_method: string; identity_id: string }>("SELECT auth_method, identity_id FROM tokens WHERE token_hash = ?", await hashToken(body.token));
    expect(row?.auth_method).toBe("email");
    expect(row?.identity_id).toMatch(UUID_RE);
    expect((await devices(app, body.token)).status).toBe(200);
    expect(count("email_codes")).toBe(0);
  });

  it("signs the same address in to the same account; same key, same device, one live token per device", async () => {
    const { mail, app } = setup();
    const first = await emailSession(app, mail, { email: "ann@example.com", kind: "mobile" });
    const again = await emailSession(app, mail, { email: "ANN@example.com", kind: "mobile", publicKey: first.publicKey });
    expect([again.userId, again.deviceId, again.email]).toEqual([first.userId, first.deviceId, "ann@example.com"]);
    expect((await devices(app, first.token)).status).toBe(401);
    const desk = await emailSession(app, mail, { email: "ann@example.com", kind: "desktop" });
    expect(desk.userId).toBe(first.userId);
    expect(desk.deviceId).not.toBe(first.deviceId);
    expect(identities(first.userId)).toEqual([{ provider: "email", subject: "ann@example.com" }]);
  });

  it("answers 401 invalid_code to a wrong guess and counts it; the fifth guess may be right, a fifth wrong one answers 410 and burns the code", async () => {
    const { mail, app } = setup();
    const a = await requestEmailCode(app, mail, "ann@example.com");
    for (let n = 1; n <= 4; n++) {
      const res = await verify(app, a.challengeId, "004218");
      expect([res.status, await errorCode(res)]).toEqual([401, "invalid_code"]);
      expect(db().get("SELECT attempts FROM email_codes")).toEqual({ attempts: n });
    }
    expect((await verify(app, a.challengeId, CODE)).status).toBe(200);

    const b = await requestEmailCode(app, mail, "bob@example.com");
    for (const guess of ["4217", 4217, "004216", " 004217"]) expect(await errorCode(await verify(app, b.challengeId, guess))).toBe("invalid_code");
    const fifth = await verify(app, b.challengeId, "000000");
    expect([fifth.status, await errorCode(fifth)]).toEqual([410, "code_expired"]);
    const late = await verify(app, b.challengeId, CODE);
    expect([late.status, await errorCode(late)]).toEqual([410, "code_expired"]);
    expect(db().all("SELECT email FROM users")).toEqual([{ email: "ann@example.com" }]);
  });

  it("answers 410 code_expired to a used, replaced, expired, unknown or malformed challenge: none of them signs in", async () => {
    let now = T0;
    const { mail, app } = setup({ now: () => now });
    const used = await requestEmailCode(app, mail, "ann@example.com");
    expect((await verify(app, used.challengeId, CODE)).status).toBe(200);
    const replaced = await requestEmailCode(app, mail, "bob@example.com");
    const expired = await requestEmailCode(app, mail, "bob@example.com");
    const stale = await verify(app, replaced.challengeId, CODE);
    expect([stale.status, await errorCode(stale)]).toEqual([410, "code_expired"]);
    now = T0 + 600_000;
    for (const id of [used.challengeId, expired.challengeId, "n".repeat(43), "short", 42, undefined]) {
      const res = await verify(app, id, CODE);
      expect([res.status, await errorCode(res)]).toEqual([410, "code_expired"]);
    }
    expect([count("users"), count("email_codes")]).toEqual([1, 0]);
    now = T0;
    const fresh = await requestEmailCode(app, mail, "carol@example.com");
    now = T0 + 599_999;
    expect((await verify(app, fresh.challengeId, CODE)).status).toBe(200);
  });

  it("signs in at most once when one challenge is verified concurrently, and compares at most five concurrent guesses", async () => {
    const { mail, app } = setup();
    const right = await requestEmailCode(app, mail, "ann@example.com");
    const answers = await Promise.all(Array.from({ length: 6 }, () => verify(app, right.challengeId, CODE)));
    expect(answers.map((r) => r.status).sort()).toEqual([200, 410, 410, 410, 410, 410]);
    expect([count("users"), count("devices"), count("tokens"), count("identities")]).toEqual([1, 1, 1, 1]);

    const wrong = await requestEmailCode(app, mail, "bob@example.com");
    const guesses = await Promise.all(Array.from({ length: 9 }, (_, i) => verify(app, wrong.challengeId, `99999${i}`)));
    expect(guesses.map((r) => r.status).sort()).toEqual([401, 401, 401, 401, 410, 410, 410, 410, 410]);
    expect((await verify(app, wrong.challengeId, CODE)).status).toBe(410);
    expect(count("users")).toBe(1);
  });

  it("links into the account created with Google for that address, in any spelling; the account keeps both sign-ins and its sessions", async () => {
    const { mail, app } = setup();
    const g = await googleSession(app, { email: "ann.lee@example.com" });
    const s = await emailSession(app, mail, { email: " Ann.Lee@EXAMPLE.com " });
    expect([s.userId, s.email]).toEqual([g.userId, "ann.lee@example.com"]);
    expect(identities(g.userId)).toEqual([{ provider: "email", subject: "ann.lee@example.com" }, { provider: "google", subject: g.sub }]);
    expect((await devices(app, g.token)).status).toBe(200);
    expect(count("users")).toBe(1);
  });

  it("never matches another spelling of a mailbox (dots, +tag) or an address that only an identity carries", async () => {
    const { mail, app } = setup();
    const g = await googleSession(app, { email: "ann.lee@example.com" });
    seedAppleIdentity(g.userId, "a-1", "hidden@icloud.example");
    for (const email of ["annlee@example.com", "ann.lee+shellx@example.com", "hidden@icloud.example"]) {
      const s = await emailSession(app, mail, { email });
      expect(s.userId).not.toBe(g.userId);
      expect(s.email).toBe(email);
    }
    expect(identities(g.userId).map((i) => i.provider)).toEqual(["apple", "google"]);
    expect(count("users")).toBe(4);
  });

  it("answers 409 switch_from_signed_in_device for an account whose password still works: nothing is attached and the code is spent", async () => {
    const { mail, app } = setup();
    const account = await registerAccount(app);
    const { challengeId } = await requestEmailCode(app, mail, account.email.toUpperCase());
    for (const [status, code] of [[409, "switch_from_signed_in_device"], [410, "code_expired"]] as const) {
      const res = await verify(app, challengeId, CODE);
      expect([res.status, await errorCode(res)]).toEqual([status, code]);
    }
    expect([count("identities"), count("devices")]).toEqual([0, 1]);
    const login = await call(app, "POST", "/v1/auth/login", { body: { email: account.email, password: account.password, device: deviceBody("mobile") } });
    expect(login.status).toBe(200);
  });

  it("claims an account that has no sign-in left (password off or already cleared): the password and every earlier session go", async () => {
    const account = await registerAccount(makeApp());
    const phone = await loginDevice(makeApp(), account, "mobile");
    const other = "other-session-0123456789abcdef0123456789abc"; // 43 characters; minted without an identity, like the smoke token
    insertToken(db(), await hashToken(other), account.agent.deviceId, Date.now(), "test", null);
    expect((await devices(makeApp(), other)).status).toBe(200);
    const { mail, app } = setup({ config: { ...TEST_CONFIG, passwordLogin: false } });
    const s = await emailSession(app, mail, { email: account.email });
    expect(s.userId).toBe(account.agent.userId);
    expect(db().get("SELECT password_hash FROM users WHERE id = ?", s.userId)).toEqual({ password_hash: null });
    for (const token of [account.agent.token, phone.token, other]) expect((await devices(app, token)).status).toBe(401);
    expect(db().get("SELECT COUNT(*) AS n FROM tokens t JOIN devices d ON d.id = t.device_id WHERE d.user_id = ?", s.userId)).toEqual({ n: 1 });
    expect(identities(s.userId)).toEqual([{ provider: "email", subject: account.email }]);

    const cleared = await seedUser("cleared@example.com", null); // after the cut-over, PASSWORD_LOGIN still on
    const on = setup();
    expect((await emailSession(on.app, on.mail, { email: "cleared@example.com" })).userId).toBe(cleared);
  });

  it("refuses (409) an account whose address was never verified and that has another sign-in (an Apple ID, no Google): nothing changes", async () => {
    const { mail, app } = setup({ config: { ...TEST_CONFIG, passwordLogin: false } });
    const userId = await seedUser("legacy@example.com", "correct horse battery");
    seedAppleIdentity(userId, "a-legacy", "legacy@example.com");
    const res = await signInEmail(app, mail, { email: "legacy@example.com" });
    expect([res.status, await errorCode(res)]).toEqual([409, "switch_from_signed_in_device"]);
    expect(identities(userId)).toEqual([{ provider: "apple", subject: "a-legacy" }]);
    expect(db().get("SELECT password_hash IS NOT NULL AS kept FROM users WHERE id = ?", userId)).toEqual({ kept: 1 });
    expect([count("devices"), count("users")]).toEqual([0, 1]);
  });

  it("answers 400 invalid_device to an agent, a malformed or a missing device without spending a guess, and 400 bad_request to non-JSON", async () => {
    const { mail, app } = setup();
    const { challengeId } = await requestEmailCode(app, mail, "ann@example.com");
    for (const device of [deviceBody("agent"), deviceBody("desktop", { platform: "ios" }), null]) {
      const res = await verify(app, challengeId, CODE, device);
      expect([res.status, await errorCode(res)]).toEqual([400, "invalid_device"]);
    }
    expect(await errorCode(await call(app, "POST", "/v1/auth/email/verify", { body: "{oops" }))).toBe("bad_request");
    expect(db().get("SELECT attempts FROM email_codes")).toEqual({ attempts: 0 });
    expect((await verify(app, challengeId, CODE)).status).toBe(200);
  });

  it("is limited per IP by the login limiter, and records X-ShellX-Version on the device", async () => {
    const loginIp = new CountingLimiter(1);
    const { mail, app } = setup({ limiters: { ...unlimited, loginIp } });
    const s = await emailSession(app, mail, { ip: "198.51.100.7", headers: { "X-ShellX-Version": "1.8.0" } });
    expect(db().get("SELECT app_version FROM devices WHERE id = ?", s.deviceId)).toEqual({ app_version: "1.8.0" });
    const blocked = await signInEmail(app, mail, { ip: "198.51.100.7" });
    expect([blocked.status, await errorCode(blocked)]).toEqual([429, "rate_limited"]);
    expect(loginIp.calls).toEqual(["198.51.100.7", "198.51.100.7"]);
  });
});

import { describe, expect, it } from "vitest";
import { hashToken } from "../src/auth/tokens.js";
import { fakeGoogle, googleClaims } from "./fake-idp.js";
import {
  call, CountingLimiter, db, deviceBody, errorCode, googleSession, loginDevice, makeApp, newNonce, randomEmail,
  registerAccount, seedUser, signInGoogle, TEST_CONFIG, unlimited,
} from "./helpers.js";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const devices = (app: ReturnType<typeof makeApp>, token: string) => call(app, "GET", "/v1/devices", { token });

describe("POST /v1/auth/google", () => {
  it("creates an account on the first sign-in: Google email, no password, one identity, a google token", async () => {
    const app = makeApp();
    const s = await googleSession(app, { email: "  New.User@Gmail.com " });
    expect(s.email).toBe("new.user@gmail.com");
    expect(db().get("SELECT email, password_hash FROM users WHERE id = ?", s.userId)).toEqual({ email: "new.user@gmail.com", password_hash: null });
    expect(db().all("SELECT provider, subject, email FROM identities WHERE user_id = ?", s.userId)).toEqual([{ provider: "google", subject: s.sub, email: "new.user@gmail.com" }]);
    const row = db().get<{ auth_method: string; identity_id: string }>("SELECT auth_method, identity_id FROM tokens WHERE token_hash = ?", await hashToken(s.token));
    expect(row?.auth_method).toBe("google");
    expect(row?.identity_id).toMatch(UUID_RE);
    expect((await devices(app, s.token)).status).toBe(200);
  });

  it("signs the same Google account in to the same account whatever its email says now; same key, same device", async () => {
    const app = makeApp();
    const first = await googleSession(app, { kind: "mobile" });
    const again = await googleSession(app, { sub: first.sub, email: randomEmail(), kind: "mobile", publicKey: first.publicKey });
    expect([again.userId, again.deviceId, again.email]).toEqual([first.userId, first.deviceId, first.email]);
    expect((await devices(app, first.token)).status).toBe(401);
    const desk = await googleSession(app, { sub: first.sub, kind: "desktop" });
    expect(desk.userId).toBe(first.userId);
    expect(desk.deviceId).not.toBe(first.deviceId);
  });

  it("answers 409 switch_from_signed_in_device for the email (any case) of an account that still has a password", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const res = await signInGoogle(app, { email: ` ${account.email.toUpperCase()}` });
    expect([res.status, await errorCode(res)]).toEqual([409, "switch_from_signed_in_device"]);
    expect(db().get("SELECT COUNT(*) AS n FROM identities")).toEqual({ n: 0 });
    const login = await call(app, "POST", "/v1/auth/login", { body: { email: account.email, password: account.password, device: deviceBody("mobile") } });
    expect(login.status).toBe(200);
  });

  it("links by email (any case) to an account without a password", async () => {
    const app = makeApp();
    const email = randomEmail();
    const userId = await seedUser(email, null);
    expect((await googleSession(app, { email: email.toUpperCase() })).userId).toBe(userId);
    expect(db().get("SELECT COUNT(*) AS n FROM identities WHERE user_id = ?", userId)).toEqual({ n: 1 });
  });

  it("with PASSWORD_LOGIN=off links by email to an account that still has a password, removes it and signs out its password sessions", async () => {
    const account = await registerAccount(makeApp());
    const phone = await loginDevice(makeApp(), account, "mobile");
    const app = makeApp({ config: { ...TEST_CONFIG, passwordLogin: false } });
    const s = await googleSession(app, { email: account.email });
    expect(s.userId).toBe(account.agent.userId);
    expect(db().get("SELECT password_hash FROM users WHERE id = ?", s.userId)).toEqual({ password_hash: null });
    for (const token of [account.agent.token, phone.token]) expect((await devices(app, token)).status).toBe(401);
    expect((await devices(app, s.token)).status).toBe(200);
  });

  it("refuses (401) a new Google account whose email is that of an account that already has a Google sign-in", async () => {
    const app = makeApp();
    const first = await googleSession(app);
    const res = await signInGoogle(app, { email: first.email });
    expect([res.status, await errorCode(res)]).toEqual([401, "invalid_credentials"]);
    expect(db().get("SELECT COUNT(*) AS n FROM identities")).toEqual({ n: 1 });
  });

  it("uses a nonce once, and only one the relay issued", async () => {
    const app = makeApp();
    const nonce = await newNonce(app);
    const body = { id_token: await fakeGoogle.sign(googleClaims({ nonce })), nonce, device: deviceBody("desktop") };
    expect((await call(app, "POST", "/v1/auth/google", { body })).status).toBe(200);
    const replay = await call(app, "POST", "/v1/auth/google", { body });
    expect([replay.status, await errorCode(replay)]).toEqual([401, "invalid_credentials"]);
    const forged = "f".repeat(43);
    const res = await call(app, "POST", "/v1/auth/google", { body: { id_token: await fakeGoogle.sign(googleClaims({ nonce: forged })), nonce: forged, device: deviceBody("desktop") } });
    expect(res.status).toBe(401);
  });

  it.each([
    ["an unknown audience", { aud: "someone-else.apps.googleusercontent.com" }],
    ["an unverified email", { email_verified: false }],
    ["an Apple issuer", { iss: "https://appleid.apple.com" }],
  ])("answers 401 invalid_credentials to %s", async (_, claims) => {
    const res = await signInGoogle(makeApp(), { claims });
    expect([res.status, await errorCode(res)]).toEqual([401, "invalid_credentials"]);
  });

  it("answers 400 invalid_device to an agent, a malformed or a missing device, and 400 bad_request to non-JSON", async () => {
    const app = makeApp();
    for (const device of [deviceBody("agent"), deviceBody("desktop", { platform: "ios" }), undefined]) {
      const res = await call(app, "POST", "/v1/auth/google", { body: { id_token: "x", nonce: await newNonce(app), device } });
      expect([res.status, await errorCode(res)]).toEqual([400, "invalid_device"]);
    }
    expect(await errorCode(await call(app, "POST", "/v1/auth/google", { body: "{oops" }))).toBe("bad_request");
  });

  it("is limited per IP by the login limiter", async () => {
    const loginIp = new CountingLimiter(1);
    const app = makeApp({ limiters: { ...unlimited, loginIp } });
    expect((await signInGoogle(app, { ip: "198.51.100.7" })).status).toBe(200);
    expect((await signInGoogle(app, { ip: "198.51.100.7" })).status).toBe(429);
    expect(loginIp.calls).toEqual(["198.51.100.7", "198.51.100.7"]);
  });

  it("accepts the test identity provider as provider test, auth_method test", async () => {
    const s = await googleSession(makeApp(), { idp: "test" });
    expect(db().get("SELECT provider FROM identities WHERE user_id = ?", s.userId)).toEqual({ provider: "test" });
    expect(db().get("SELECT auth_method FROM tokens WHERE device_id = ?", s.deviceId)).toEqual({ auth_method: "test" });
  });

  it("records X-ShellX-Version on the device", async () => {
    const s = await googleSession(makeApp(), { headers: { "X-ShellX-Version": "1.8.0" } });
    expect(db().get("SELECT app_version FROM devices WHERE id = ?", s.deviceId)).toEqual({ app_version: "1.8.0" });
  });
});

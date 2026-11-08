import { describe, expect, it } from "vitest";
import { hashToken } from "../src/auth/tokens.js";
import { call, db, deviceBody, errorCode, googleIdToken, googleSession, loginDevice, makeApp, registerAccount, type TestApp } from "./helpers.js";

const link = (app: TestApp, token: string | undefined, body: Record<string, unknown>) => call(app, "POST", "/v1/auth/google/link", { token, body });

describe("POST /v1/auth/google/link (S1 §6.3b)", () => {
  it("links Google to the signed-in account even with another email; only this device moves to a google token", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const phone = await loginDevice(app, account, "mobile");
    const sub = `g-${crypto.randomUUID()}`;
    const res = await link(app, account.agent.token, await googleIdToken(app, { sub, email: "Owner@Gmail.com" }));
    expect(res.status).toBe(200);
    const body = await res.json<{ user_id: string; device_id: string; token: string; email: string }>();
    expect(body).toMatchObject({ user_id: account.agent.userId, device_id: account.agent.deviceId, email: "owner@gmail.com" });
    expect(db().get("SELECT email, password_hash IS NOT NULL AS has_password FROM users WHERE id = ?", account.agent.userId)).toEqual({ email: "owner@gmail.com", has_password: 1 });
    expect(db().get("SELECT auth_method FROM tokens WHERE token_hash = ?", await hashToken(body.token))).toEqual({ auth_method: "google" });
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(401);
    expect((await call(app, "GET", "/v1/devices", { token: phone.token })).status).toBe(200);
    const login = await call(app, "POST", "/v1/auth/login", { body: { email: "owner@gmail.com", password: account.password, device: deviceBody("mobile") } });
    expect(login.status).toBe(200);
    expect((await googleSession(app, { sub, kind: "mobile" })).userId).toBe(account.agent.userId);
  });

  it("answers 409 email_in_use when another account has that email, changing nothing", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const other = await registerAccount(app);
    const res = await link(app, account.agent.token, await googleIdToken(app, { email: other.email }));
    expect([res.status, await errorCode(res)]).toEqual([409, "email_in_use"]);
    expect(db().get("SELECT COUNT(*) AS n FROM identities")).toEqual({ n: 0 });
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(200);
  });

  it("answers 409 identity_in_use for a Google account of another account, or a second Google account for this one", async () => {
    const app = makeApp();
    const taken = await googleSession(app);
    const account = await registerAccount(app);
    const desk = await loginDevice(app, account, "desktop");
    const res = await link(app, account.agent.token, await googleIdToken(app, { sub: taken.sub, email: taken.email }));
    expect([res.status, await errorCode(res)]).toEqual([409, "identity_in_use"]);
    expect((await link(app, account.agent.token, await googleIdToken(app, { sub: "g-first" }))).status).toBe(200);
    const second = await link(app, desk.token, await googleIdToken(app, { sub: "g-second" }));
    expect([second.status, await errorCode(second)]).toEqual([409, "identity_in_use"]);
    const again = await link(app, desk.token, await googleIdToken(app, { sub: "g-first" }));
    expect(again.status).toBe(200);
    expect(db().get("SELECT COUNT(*) AS n FROM identities WHERE user_id = ?", account.agent.userId)).toEqual({ n: 1 });
  });

  it("needs a bearer token, a valid ID token and an unused nonce", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const fresh = await loginDevice(app, account, "mobile"); // before the link below changes the account's email
    expect(await errorCode(await link(app, undefined, await googleIdToken(app)))).toBe("unauthorized");
    const bad = await link(app, account.agent.token, { ...(await googleIdToken(app)), id_token: "not-a-jwt" });
    expect([bad.status, await errorCode(bad)]).toEqual([401, "invalid_credentials"]);
    const used = await googleIdToken(app);
    expect((await link(app, account.agent.token, used)).status).toBe(200);
    expect((await link(app, fresh.token, used)).status).toBe(401);
  });
});

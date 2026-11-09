import { describe, expect, it } from "vitest";
import { call, db, deviceBody, errorCode, makeApp, registerAccount, TEST_CONFIG } from "./helpers.js";

const off = () => makeApp({ config: { ...TEST_CONFIG, passwordLogin: false } });

describe("PASSWORD_LOGIN=off (S1 §6.9)", () => {
  it("answers 410 password_sign_in_removed to login and password change; signed-in sessions keep working", async () => {
    const account = await registerAccount(makeApp());
    const app = off();
    const login = await call(app, "POST", "/v1/auth/login", { body: { email: account.email, password: account.password, device: deviceBody("mobile") } });
    expect([login.status, await errorCode(login)]).toEqual([410, "password_sign_in_removed"]);
    const change = await call(app, "POST", "/v1/auth/password", { token: account.agent.token, body: { new_password: "brand new password" } });
    expect([change.status, await errorCode(change)]).toEqual([410, "password_sign_in_removed"]);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(200);
  });

  it("no longer takes the password to delete an account: 401 reauth_required, nothing deleted", async () => {
    const account = await registerAccount(makeApp());
    const res = await call(off(), "DELETE", "/v1/account", { token: account.agent.token, body: { password: account.password } });
    expect([res.status, await errorCode(res)]).toEqual([401, "reauth_required"]);
    expect(db().get("SELECT COUNT(*) AS n FROM users WHERE id = ?", account.agent.userId)).toEqual({ n: 1 });
  });
});

import { describe, expect, it } from "vitest";
import { hashPassword } from "../src/auth/password.js";
import { call, callStreamed, db, deviceBody, errorCode, loginDevice, makeApp, registerAccount } from "./helpers.js";

// Final review I2: login and DELETE /v1/account passed any-length passwords to argon2, and no route
// capped its request body.

const BODY_LIMIT = 16 * 1024;
const TOO_LONG = "x".repeat(129); // 129 code points: one over the 8-128 policy

/** Stores the argon2id hash of `password` for the user directly, bypassing the policy check. */
async function plantPassword(userId: string, password: string): Promise<void> {
  db().run("UPDATE users SET password_hash = ? WHERE id = ?", await hashPassword(password), userId);
}

/** A JSON object with the fields of `base` plus padding, exactly `bytes` UTF-8 bytes long. */
function paddedJson(base: Record<string, unknown>, bytes: number): string {
  const skeleton = new TextEncoder().encode(JSON.stringify({ ...base, pad: "" })).length;
  if (skeleton > bytes) throw new Error("base is already larger than the requested size");
  const body = JSON.stringify({ ...base, pad: "p".repeat(bytes - skeleton) });
  expect(new TextEncoder().encode(body).length).toBe(bytes);
  return body;
}

describe("password length cap on login and account deletion", () => {
  it("login refuses a password over 128 code points as invalid_credentials, even one that would verify", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    await plantPassword(account.agent.userId, TOO_LONG);
    const res = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: TOO_LONG, device: deviceBody("mobile") },
    });
    expect(res.status).toBe(401);
    expect(await errorCode(res)).toBe("invalid_credentials");
  });

  it("counts code points after NFC: 128 characters typed as NFD or as astral symbols still log in", async () => {
    const app = makeApp();
    const nfc = "ệ".normalize("NFC").repeat(128);
    const account = await registerAccount(app, undefined, nfc);
    expect([...nfc.normalize("NFD")].length).toBe(384);
    const nfdLogin = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: nfc.normalize("NFD"), device: deviceBody("mobile") },
    });
    expect(nfdLogin.status).toBe(200);

    const astral = "😀".repeat(128); // 256 UTF-16 code units, 128 code points
    await plantPassword(account.agent.userId, astral);
    const astralLogin = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: astral, device: deviceBody("mobile") },
    });
    expect(astralLogin.status).toBe(200);
  });

  it("account deletion refuses a password over 128 code points before verifying, deleting nothing", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    await plantPassword(account.agent.userId, TOO_LONG);
    const res = await call(app, "DELETE", "/v1/account", { token: account.agent.token, body: { password: TOO_LONG } });
    expect(res.status).toBe(401);
    expect(await errorCode(res)).toBe("invalid_credentials");
    expect(db().get("SELECT 1 FROM users WHERE id = ?", account.agent.userId)).toBeDefined();
  });
});

describe("request body limit (16 KiB) on the JSON routes", () => {
  interface Route {
    method: string;
    path: (ids: { mobileId: string }) => string;
    token: "none" | "agent";
  }
  const routes: [string, Route][] = [
    ["POST /v1/auth/register", { method: "POST", path: () => "/v1/auth/register", token: "none" }],
    ["POST /v1/auth/login", { method: "POST", path: () => "/v1/auth/login", token: "none" }],
    ["POST /v1/auth/password", { method: "POST", path: () => "/v1/auth/password", token: "agent" }],
    ["DELETE /v1/account", { method: "DELETE", path: () => "/v1/account", token: "agent" }],
    ["POST /v1/pairings", { method: "POST", path: () => "/v1/pairings", token: "agent" }],
  ];

  it.each(routes)("%s answers 413 payload_too_large (JSON error shape) one byte over the limit", async (_, route) => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const body = paddedJson(
      { email: account.email, password: account.password, new_password: "another password", mobile_id: mobile.deviceId, device: deviceBody("mobile") },
      BODY_LIMIT + 1,
    );
    const res = await call(app, route.method, route.path({ mobileId: mobile.deviceId }), {
      body,
      token: route.token === "agent" ? account.agent.token : undefined,
    });
    expect(res.status).toBe(413);
    expect(await res.json()).toEqual({ error: { code: "payload_too_large", message: "Request body is too large" } });
    // Nothing happened: the account and its password are unchanged.
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(200);
  });

  it("accepts a body of exactly 16 KiB", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const body = paddedJson({ email: account.email, password: account.password, device: deviceBody("mobile") }, BODY_LIMIT);
    expect((await call(app, "POST", "/v1/auth/login", { body })).status).toBe(200);
  });

  it("also caps a streamed body that has no Content-Length", async () => {
    const chunk = new TextEncoder().encode(" ".repeat(4096));
    const res = await callStreamed(makeApp(), "POST", "/v1/auth/login", Array(5).fill(chunk));
    expect(res.status).toBe(413);
    expect(await errorCode(res)).toBe("payload_too_large");
  });

  it("keeps 401 unauthorized ahead of the size check on authenticated routes", async () => {
    const res = await call(makeApp(), "DELETE", "/v1/account", { body: paddedJson({}, BODY_LIMIT + 1) });
    expect(res.status).toBe(401);
    expect(await errorCode(res)).toBe("unauthorized");
  });
});

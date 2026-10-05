import { describe, expect, it } from "vitest";
import { call, db, errorCode, loginDevice, makeApp, PASSWORD, registerAccount } from "./helpers.js";

function tokenOf(deviceId: string): { token: string; platform: string } | undefined {
  return db().get<{ token: string; platform: string }>("SELECT token, platform FROM push_tokens WHERE device_id = ?", deviceId);
}

describe("migration 0003_push_tokens", () => {
  it("creates push_tokens with a unique token and the platform check", () => {
    const columns = db().all<{ name: string; type: string; notnull: number; pk: number }>("PRAGMA table_info(push_tokens)");
    expect(columns.map((c) => [c.name, c.type, c.notnull, c.pk])).toEqual([
      ["device_id", "TEXT", 0, 1],
      ["token", "TEXT", 1, 0],
      ["platform", "TEXT", 1, 0],
      ["updated_at", "INTEGER", 1, 0],
    ]);
    const indexes = db().all<{ name: string; unique: number }>("PRAGMA index_list(push_tokens)");
    expect(indexes.some((i) => i.unique === 1 && i.name === "push_tokens_token")).toBe(true);
  });
});

describe("PUT /v1/devices/me/push-token", () => {
  it("stores the phone's token and platform (204), and replaces it on the next PUT", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const phone = await loginDevice(app, account, "mobile");
    const res = await call(app, "PUT", "/v1/devices/me/push-token", { token: phone.token, body: { token: "fcm-1", platform: "ios" } });
    expect(res.status).toBe(204);
    expect(tokenOf(phone.deviceId)).toEqual({ token: "fcm-1", platform: "ios" });
    const again = await call(app, "PUT", "/v1/devices/me/push-token", { token: phone.token, body: { token: "fcm-2", platform: "android" } });
    expect(again.status).toBe(204);
    expect(tokenOf(phone.deviceId)).toEqual({ token: "fcm-2", platform: "android" });
    expect(db().get<{ n: number }>("SELECT COUNT(*) AS n FROM push_tokens")!.n).toBe(1);
  });

  it("moves a token registered again from another device (one token, one device)", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const first = await loginDevice(app, account, "mobile");
    const second = await loginDevice(app, account, "mobile");
    await call(app, "PUT", "/v1/devices/me/push-token", { token: first.token, body: { token: "shared", platform: "android" } });
    const res = await call(app, "PUT", "/v1/devices/me/push-token", { token: second.token, body: { token: "shared", platform: "android" } });
    expect(res.status).toBe(204);
    expect(tokenOf(first.deviceId)).toBeUndefined();
    expect(tokenOf(second.deviceId)).toEqual({ token: "shared", platform: "android" });
  });

  it("moves a token across accounts too (the phone signed into another account)", async () => {
    const app = makeApp();
    const a = await loginDevice(app, await registerAccount(app), "mobile");
    const b = await loginDevice(app, await registerAccount(app), "mobile");
    await call(app, "PUT", "/v1/devices/me/push-token", { token: a.token, body: { token: "t", platform: "ios" } });
    await call(app, "PUT", "/v1/devices/me/push-token", { token: b.token, body: { token: "t", platform: "ios" } });
    expect(tokenOf(a.deviceId)).toBeUndefined();
    expect(tokenOf(b.deviceId)?.token).toBe("t");
  });

  it("is for phones only: an agent gets 403 mobile_only", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const res = await call(app, "PUT", "/v1/devices/me/push-token", { token: account.agent.token, body: { token: "x", platform: "ios" } });
    expect(res.status).toBe(403);
    expect(await errorCode(res)).toBe("mobile_only");
  });

  it("requires a token (401)", async () => {
    const res = await call(makeApp(), "PUT", "/v1/devices/me/push-token", { body: { token: "x", platform: "ios" } });
    expect(res.status).toBe(401);
  });

  it("refuses a missing, empty or over-4096-character token and an unknown platform (400 bad_request)", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const phone = await loginDevice(app, account, "mobile");
    for (const body of [
      { platform: "ios" },
      { token: "", platform: "ios" },
      { token: "a".repeat(4097), platform: "ios" },
      { token: 42, platform: "ios" },
      { token: "x" },
      { token: "x", platform: "macos" },
      { token: "x", platform: "IOS" },
    ]) {
      const res = await call(app, "PUT", "/v1/devices/me/push-token", { token: phone.token, body });
      expect(res.status, JSON.stringify(body).slice(0, 60)).toBe(400);
      expect(await errorCode(res)).toBe("bad_request");
    }
    expect(tokenOf(phone.deviceId)).toBeUndefined();
    const longest = await call(app, "PUT", "/v1/devices/me/push-token", { token: phone.token, body: { token: "a".repeat(4096), platform: "ios" } });
    expect(longest.status).toBe(204);
  });
});

describe("DELETE /v1/devices/me/push-token", () => {
  it("removes the caller's token (204) and is idempotent", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const phone = await loginDevice(app, account, "mobile");
    await call(app, "PUT", "/v1/devices/me/push-token", { token: phone.token, body: { token: "t", platform: "ios" } });
    expect((await call(app, "DELETE", "/v1/devices/me/push-token", { token: phone.token })).status).toBe(204);
    expect(tokenOf(phone.deviceId)).toBeUndefined();
    expect((await call(app, "DELETE", "/v1/devices/me/push-token", { token: phone.token })).status).toBe(204);
    expect((await call(app, "DELETE", "/v1/devices/me/push-token", { token: account.agent.token })).status).toBe(204);
  });

  it("requires a token (401)", async () => {
    expect((await call(makeApp(), "DELETE", "/v1/devices/me/push-token")).status).toBe(401);
  });
});

describe("tokens go away with the device's sign-in", () => {
  it("logout deletes the phone's push token", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const phone = await loginDevice(app, account, "mobile");
    await call(app, "PUT", "/v1/devices/me/push-token", { token: phone.token, body: { token: "t", platform: "android" } });
    expect((await call(app, "POST", "/v1/auth/logout", { token: phone.token })).status).toBe(204);
    expect(tokenOf(phone.deviceId)).toBeUndefined();
  });

  it("deleting the account deletes every push token of it (cascade)", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const phone = await loginDevice(app, account, "mobile");
    await call(app, "PUT", "/v1/devices/me/push-token", { token: phone.token, body: { token: "t", platform: "android" } });
    const res = await call(app, "DELETE", "/v1/account", { token: phone.token, body: { password: PASSWORD } });
    expect(res.status).toBe(204);
    expect(tokenOf(phone.deviceId)).toBeUndefined();
    expect(db().get<{ n: number }>("SELECT COUNT(*) AS n FROM push_tokens")!.n).toBe(0);
  });
});

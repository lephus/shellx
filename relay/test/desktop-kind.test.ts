import { describe, expect, it } from "vitest";
import { adminStats } from "../src/admin/stats.js";
import { call, db, deviceBody, errorCode, loginDesktop, makeApp, pair, registerAccount, upgradeStatus } from "./helpers.js";

describe("the desktop device kind", () => {
  it("logs in as kind desktop, and refuses a desktop on ios", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const desktop = await loginDesktop(app, account);
    expect(db().get("SELECT kind FROM devices WHERE id = ?", desktop.deviceId)).toEqual({ kind: "desktop" });

    const bad = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: account.password, device: deviceBody("desktop", { platform: "ios" }) },
    });
    expect(bad.status).toBe(400);
    expect(await errorCode(bad)).toBe("invalid_device");
  });

  it("is refused at the WebSocket upgrade with 403", async () => {
    const app = makeApp();
    const desktop = await loginDesktop(app, await registerAccount(app));
    expect(await upgradeStatus(app, desktop.token)).toBe(403);
  });

  it("cannot create a v1 pairing (agent_only)", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const desktop = await loginDesktop(app, account);
    const res = await pair(app, desktop.token, account.agent.deviceId);
    expect(res.status).toBe(403);
    expect(await errorCode(res)).toBe("agent_only");
  });

  it("is listed with kind desktop by the agent's GET /v1/devices", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const desktop = await loginDesktop(app, account);
    const res = await call(app, "GET", "/v1/devices", { token: account.agent.token });
    expect(res.status).toBe(200);
    const body = await res.json<{ id: string; kind: string }[]>();
    expect(body.find((d) => d.id === desktop.deviceId)?.kind).toBe("desktop");
  });

  it("is counted by the admin stats without touching the agent numbers", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    await loginDesktop(app, account);
    const stats = adminStats(db(), Date.now(), []);
    expect(stats.devices.desktop).toEqual({ total: 1, online: 0, by_platform: { macos: 1, windows: 0 } });
    expect(stats.versions.desktop).toHaveLength(1);
    expect(stats.devices.agent.total).toBe(1);
  });
});

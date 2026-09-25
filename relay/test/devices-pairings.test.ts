import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { hubFor } from "../src/hub/user-hub";
import { encodePresence, pairingRemovedEvent } from "../src/protocol/frames";
import { call, connect, errorCode, hex, loginDevice, makeApp, registerAccount, type TestApp } from "./helpers";

interface DeviceJson {
  id: string;
  kind: string;
  name: string;
  platform: string;
  online: boolean;
  last_seen_at: number | null;
  paired_with_me: boolean;
}

async function listDevices(app: TestApp, token: string): Promise<DeviceJson[]> {
  const res = await call(app, "GET", "/v1/devices", { token });
  expect(res.status).toBe(200);
  return res.json<DeviceJson[]>();
}

async function pair(app: TestApp, agentToken: string, mobileId: string): Promise<Response> {
  return call(app, "POST", "/v1/pairings", { token: agentToken, body: { mobile_id: mobileId } });
}

describe("GET /v1/devices", () => {
  it("requires a valid token", async () => {
    const res = await call(makeApp(), "GET", "/v1/devices");
    expect(res.status).toBe(401);
    expect(await errorCode(res)).toBe("unauthorized");
  });

  it("lists signed-in devices of the caller's account with presence, and no public keys", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const other = await registerAccount(app); // another account: must never appear
    const socket = await connect(app, account.agent.token);

    const devices = await listDevices(app, mobile.token);
    expect(devices).toEqual([
      { id: account.agent.deviceId, kind: "agent", name: "MacBook-Pro", platform: "macos", online: true, last_seen_at: null, paired_with_me: false },
      { id: mobile.deviceId, kind: "mobile", name: "iPhone 16", platform: "ios", online: false, last_seen_at: null, paired_with_me: false },
    ]);
    expect(JSON.stringify(devices)).not.toContain(account.agent.publicKey);
    expect(devices.map((d) => d.id)).not.toContain(other.agent.deviceId);
    socket.close();
  });

  it("hides devices whose tokens are gone (signed out)", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await env.DB.prepare("DELETE FROM tokens WHERE device_id = ?").bind(mobile.deviceId).run();
    expect((await listDevices(app, account.agent.token)).map((d) => d.id)).toEqual([account.agent.deviceId]);
  });
});

describe("POST /v1/pairings", () => {
  it("records a pairing visible as paired_with_me from both sides; idempotent", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    expect((await pair(app, account.agent.token, mobile.deviceId)).status).toBe(201);
    expect((await pair(app, account.agent.token, mobile.deviceId.toUpperCase())).status).toBe(201);

    const fromMobile = await listDevices(app, mobile.token);
    expect(fromMobile.find((d) => d.id === account.agent.deviceId)?.paired_with_me).toBe(true);
    expect(fromMobile.find((d) => d.id === mobile.deviceId)?.paired_with_me).toBe(false);
    const fromAgent = await listDevices(app, account.agent.token);
    expect(fromAgent.find((d) => d.id === mobile.deviceId)?.paired_with_me).toBe(true);
    const count = await env.DB.prepare("SELECT COUNT(*) AS n FROM pairings WHERE agent_id = ?")
      .bind(account.agent.deviceId).first<{ n: number }>();
    expect(count?.n).toBe(1);
  });

  it("is agent-only", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const res = await pair(app, mobile.token, mobile.deviceId);
    expect(res.status).toBe(403);
    expect(await errorCode(res)).toBe("agent_only");
  });

  it("returns 404 device_not_found for unknown ids, agents and other accounts' mobiles", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const otherAgent = await loginDevice(app, account, "agent");
    const stranger = await registerAccount(app);
    const strangerMobile = await loginDevice(app, stranger, "mobile");
    for (const id of [crypto.randomUUID(), "not-a-uuid", otherAgent.deviceId, strangerMobile.deviceId]) {
      const res = await pair(app, account.agent.token, id);
      expect(res.status).toBe(404);
      expect(await errorCode(res)).toBe("device_not_found");
    }
  });
});

describe("DELETE /v1/pairings/:agent_id/:mobile_id", () => {
  it("lets the agent remove a pairing and notifies the connected mobile", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await pair(app, account.agent.token, mobile.deviceId);
    const m = await connect(app, mobile.token);

    const res = await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, {
      token: account.agent.token,
    });
    expect(res.status).toBe(204);
    expect(hex(await m.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId)));
    const fromMobile = await listDevices(app, mobile.token);
    expect(fromMobile.find((d) => d.id === account.agent.deviceId)?.paired_with_me).toBe(false);
  });

  it("lets the mobile remove a pairing and notifies the connected agent", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await pair(app, account.agent.token, mobile.deviceId);
    const a = await connect(app, account.agent.token);

    const res = await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, {
      token: mobile.token,
    });
    expect(res.status).toBe(204);
    expect(hex(await a.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId)));
  });

  it("queues the event for an offline agent and delivers it after the presence snapshot", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await pair(app, account.agent.token, mobile.deviceId);
    const m = await connect(app, mobile.token);
    await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token });
    expect(hex(await m.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId)));

    const a = await connect(app, account.agent.token);
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    expect(hex(await a.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId)));
    a.close();
    await new Promise((resolve) => setTimeout(resolve, 50));
    const again = await connect(app, account.agent.token);
    expect(hex(await again.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    await again.expectSilence(); // delivered exactly once
  });

  it("is idempotent and forbidden to devices that are not a party", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const bystander = await loginDevice(app, account, "mobile");
    await pair(app, account.agent.token, mobile.deviceId);
    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`;
    const forbidden = await call(app, "DELETE", path, { token: bystander.token });
    expect(forbidden.status).toBe(403);
    expect(await errorCode(forbidden)).toBe("forbidden");
    const stillPaired = await env.DB.prepare("SELECT 1 FROM pairings WHERE agent_id = ? AND mobile_id = ?")
      .bind(account.agent.deviceId, mobile.deviceId).first();
    expect(stillPaired).not.toBeNull(); // the bystander's 403 must not touch the row
    expect((await call(app, "DELETE", path, { token: mobile.token })).status).toBe(204);
    expect((await call(app, "DELETE", path, { token: mobile.token })).status).toBe(204);
  });

  it("replays the event to an agent that was online when it fired, on its next connect", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await pair(app, account.agent.token, mobile.deviceId);
    const a = await connect(app, account.agent.token);

    const res = await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, {
      token: mobile.token,
    });
    expect(res.status).toBe(204);
    expect(hex(await a.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId)));
    a.close();
    await new Promise((resolve) => setTimeout(resolve, 50));

    // A silently-dead live socket must not lose the event: it was queued too, and is replayed here.
    const again = await connect(app, account.agent.token);
    expect(hex(await again.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId)));
    await again.expectSilence();
  });

  it("dedupes repeated pair/unpair cycles while the agent is offline into one queued event", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`;
    await pair(app, account.agent.token, mobile.deviceId);
    await call(app, "DELETE", path, { token: mobile.token });
    await pair(app, account.agent.token, mobile.deviceId);
    await call(app, "DELETE", path, { token: mobile.token });
    await pair(app, account.agent.token, mobile.deviceId);
    await call(app, "DELETE", path, { token: mobile.token });

    const a = await connect(app, account.agent.token);
    expect(hex(await a.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId)));
    await a.expectSilence(); // exactly one queued row survived three cycles, not three
  });

  it("keeps the pairing row when the hub RPC fails, so a retry can still deliver the event", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await pair(app, account.agent.token, mobile.deviceId);
    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`;

    let calls = 0;
    const failingOnce = {
      idFromName: (name: string) => name,
      get: () => ({
        online: async () => [],
        disconnect: async () => {},
        notifyPairingRemoved: async () => {
          calls++;
          if (calls === 1) throw new Error("boom");
        },
      }),
    } as unknown as typeof env.USER_HUB;

    const failed = await call(app, "DELETE", path, { token: mobile.token, bindings: { USER_HUB: failingOnce } });
    expect(failed.status).toBe(500);
    expect(await errorCode(failed)).toBe("internal_error");
    const stillThere = await env.DB.prepare("SELECT 1 FROM pairings WHERE agent_id = ? AND mobile_id = ?")
      .bind(account.agent.deviceId, mobile.deviceId).first();
    expect(stillThere).not.toBeNull(); // the failed hub call must not have deleted the row

    const retried = await call(app, "DELETE", path, { token: mobile.token });
    expect(retried.status).toBe(204);
    const gone = await env.DB.prepare("SELECT 1 FROM pairings WHERE agent_id = ? AND mobile_id = ?")
      .bind(account.agent.deviceId, mobile.deviceId).first();
    expect(gone).toBeNull();

    const a = await connect(app, account.agent.token);
    expect(hex(await a.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId)));
  });
});

describe("UserHub RPC", () => {
  it("online() lists connected devices and disconnect() closes them with the given code", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const a = await connect(app, account.agent.token);
    const m = await connect(app, mobile.token);
    await m.nextBinary();
    await a.nextBinary();
    const hub = hubFor(env, account.agent.userId);
    expect((await hub.online()).sort()).toEqual([account.agent.deviceId, mobile.deviceId].sort());

    await hub.disconnect([mobile.deviceId], 4002);
    expect(await m.closed).toEqual({ code: 4002, reason: "revoked" });
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, false)));
    expect(await hub.online()).toEqual([account.agent.deviceId]);
    await hub.disconnect([mobile.deviceId], 4002); // already gone: no-op
    await a.expectSilence();
  });
});

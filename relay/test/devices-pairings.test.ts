import { describe, expect, it, vi } from "vitest";
import type { HubRegistry } from "../src/hub/registry.js";
import { encodePresence, pairingRemovedEvent } from "../src/protocol/frames.js";
import {
  call, connect, db, errorCode, hex, hubs, loginDevice, makeApp, newPairingId, pair, pairingIdOf, registerAccount,
  type TestApp, uuidv7,
} from "./helpers.js";

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

async function countPairings(agentId: string): Promise<number> {
  return db().get<{ n: number }>("SELECT COUNT(*) AS n FROM pairings WHERE agent_id = ?", agentId)?.n ?? 0;
}

/** A registry whose `forUser(...)` returns `hub` for every account (the hub methods a test fakes). */
function fakeHubs(hub: Record<string, unknown>): HubRegistry {
  return { forUser: () => hub } as unknown as HubRegistry;
}

const settle = () => new Promise((resolve) => setTimeout(resolve, 50));

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
    db().run("DELETE FROM tokens WHERE device_id = ?", mobile.deviceId);
    expect((await listDevices(app, account.agent.token)).map((d) => d.id)).toEqual([account.agent.deviceId]);
  });

  it("lists devices, not pairing rows: no pairing_id appears", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    expect((await pair(app, account.agent.token, mobile.deviceId, pairingId)).status).toBe(201);
    const res = await call(app, "GET", "/v1/devices", { token: mobile.token });
    const text = await res.text();
    expect(text).not.toContain(pairingId);
    expect(text).not.toContain("pairing_id");
  });
});

describe("POST /v1/pairings", () => {
  it("records a pairing visible as paired_with_me from both sides; idempotent", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    expect((await pair(app, account.agent.token, mobile.deviceId, pairingId)).status).toBe(201);
    expect((await pair(app, account.agent.token, mobile.deviceId.toUpperCase(), pairingId)).status).toBe(201);

    const fromMobile = await listDevices(app, mobile.token);
    expect(fromMobile.find((d) => d.id === account.agent.deviceId)?.paired_with_me).toBe(true);
    expect(fromMobile.find((d) => d.id === mobile.deviceId)?.paired_with_me).toBe(false);
    const fromAgent = await listDevices(app, account.agent.token);
    expect(fromAgent.find((d) => d.id === mobile.deviceId)?.paired_with_me).toBe(true);
    expect(await countPairings(account.agent.deviceId)).toBe(1);
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

describe("POST /v1/pairings: pairing_id (agent-generated, one per pairing)", () => {
  it("requires pairing_id to be a lower-case canonical UUIDv7 string: 400 bad_request (usual error shape), nothing recorded", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const bodies: Record<string, unknown>[] = [
      { mobile_id: mobile.deviceId },
      { mobile_id: mobile.deviceId, pairing_id: "not-a-uuid" },
      { mobile_id: mobile.deviceId, pairing_id: "" },
      { mobile_id: mobile.deviceId, pairing_id: 42 },
      { mobile_id: mobile.deviceId, pairing_id: null },
      { mobile_id: mobile.deviceId, pairing_id: [newPairingId()] },
      { mobile_id: mobile.deviceId, pairing_id: crypto.randomUUID() }, // v4
      { mobile_id: mobile.deviceId, pairing_id: "00000000-0000-0000-0000-000000000000" },
      { mobile_id: mobile.deviceId, pairing_id: newPairingId().replace(/^(.{14})7/, (_, head: string) => `${head}8`) }, // v8
      { mobile_id: mobile.deviceId, pairing_id: newPairingId().toUpperCase() }, // not lower case
    ];
    for (const body of bodies) {
      const res = await call(app, "POST", "/v1/pairings", { token: account.agent.token, body });
      expect(res.status).toBe(400);
      expect(await res.json()).toEqual({ error: { code: "bad_request", message: "Malformed request body" } });
    }
    expect(await countPairings(account.agent.deviceId)).toBe(0);
  });

  it("stores the id exactly as sent; the same id again is 201 and changes nothing", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    expect((await pair(app, account.agent.token, mobile.deviceId, pairingId)).status).toBe(201);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(pairingId);
    expect((await pair(app, account.agent.token, mobile.deviceId, pairingId)).status).toBe(201);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(pairingId);
    expect(await countPairings(account.agent.deviceId)).toBe(1);
  });

  it("re-pairing the same phone under a new id replaces the row's id (no tombstone, no event)", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const [x, y] = [newPairingId(), newPairingId()];
    expect((await pair(app, account.agent.token, mobile.deviceId, x)).status).toBe(201);
    expect((await pair(app, account.agent.token, mobile.deviceId, y)).status).toBe(201);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(y);
    expect(await countPairings(account.agent.deviceId)).toBe(1);
    const a = await connect(app, account.agent.token);
    await a.expectSilence();
  });

  it("answers 410 pairing_removed when this exact pairing was already removed: no row, tombstone kept", async () => {
    // The agent's first POST committed but its response was lost; the phone unpaired; the agent's
    // retry (same pairing id) must not bring the pairing back (plan 03 Task 9 review).
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    expect((await pair(app, account.agent.token, mobile.deviceId, pairingId)).status).toBe(201);
    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`;
    expect((await call(app, "DELETE", path, { token: mobile.token })).status).toBe(204);

    for (let attempt = 0; attempt < 2; attempt++) {
      const retry = await pair(app, account.agent.token, mobile.deviceId, pairingId);
      expect(retry.status).toBe(410);
      expect(await retry.json()).toEqual({ error: { code: "pairing_removed", message: expect.any(String) } });
    }
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBeNull();

    // The tombstone is still there, still for this pairing.
    const a = await connect(app, account.agent.token);
    expect(hex(await a.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, pairingId)));
    await a.expectSilence();
  });

  it("a POST with a newer id clears the older pairing's tombstone and records the new id", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const [x, y] = [newPairingId(), newPairingId()];
    await pair(app, account.agent.token, mobile.deviceId, x);
    await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token });

    expect((await pair(app, account.agent.token, mobile.deviceId, y)).status).toBe(201);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(y);
    const a = await connect(app, account.agent.token);
    await a.expectSilence(); // the tombstone of pairing x is gone
  });

  it("refuses a stale POST whose id is older than the tombstone: 410, no row, the newer tombstone still replays", async () => {
    // An old pairing's POST (x) was still in flight — or retried — after the user paired the phone
    // again (y) and then unpaired it: it must neither clear y's tombstone nor record x.
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const [x, y] = [newPairingId(), newPairingId()];
    expect((await pair(app, account.agent.token, mobile.deviceId, y)).status).toBe(201);
    expect((await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token })).status).toBe(204);

    const stale = await pair(app, account.agent.token, mobile.deviceId, x);
    expect(stale.status).toBe(410);
    expect(await errorCode(stale)).toBe("pairing_removed");
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBeNull();
    const a = await connect(app, account.agent.token);
    expect(hex(await a.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, y)));
    await a.expectSilence();
  });

  it("refuses a stale POST whose id is older than the current row: 410, the newer row is kept", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const [x, y] = [newPairingId(), newPairingId()];
    expect((await pair(app, account.agent.token, mobile.deviceId, y)).status).toBe(201);

    const stale = await pair(app, account.agent.token, mobile.deviceId, x);
    expect(stale.status).toBe(410);
    expect(await errorCode(stale)).toBe("pairing_removed");
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(y);
    const a = await connect(app, account.agent.token);
    await a.expectSilence(); // no tombstone either
  });

  it("orders ids by their UUIDv7 timestamp, not by when the requests arrive", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const base = Date.now() - 60 * 60 * 1000;
    const later = uuidv7(base);
    const earlier = uuidv7(base - 24 * 60 * 60 * 1000);
    expect((await pair(app, account.agent.token, mobile.deviceId, later)).status).toBe(201);
    expect((await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token })).status).toBe(204);
    expect((await pair(app, account.agent.token, mobile.deviceId, earlier)).status).toBe(410);
    const newest = uuidv7(base + 1);
    expect((await pair(app, account.agent.token, mobile.deviceId, newest)).status).toBe(201);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(newest);
  });

  it("refuses (410) an id whose UUIDv7 timestamp is more than 24 h ahead of the relay's clock: no row, no tombstone", async () => {
    const now = Date.UTC(2027, 5, 1);
    const app = makeApp({ now: () => now });
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const day = 24 * 60 * 60 * 1000;

    const tooFar = await pair(app, account.agent.token, mobile.deviceId, uuidv7(now + day + 1));
    expect(tooFar.status).toBe(410);
    expect(await errorCode(tooFar)).toBe("pairing_removed");
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBeNull();
    const a = await connect(app, account.agent.token);
    await a.expectSilence(); // no tombstone was written for it
    a.close();

    // Exactly 24 h ahead is still accepted (clock skew), and later ids keep working.
    const edge = uuidv7(now + day);
    expect((await pair(app, account.agent.token, mobile.deviceId, edge)).status).toBe(201);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(edge);
  });

  it("asks the hub before writing the row and again after, and answers 410 (removing the row) if the pairing was removed in between", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    const seen: { args: unknown[]; row: string | null }[] = [];
    // First answer: "fine to record"; second: "this pairing has been removed meanwhile" (a phone
    // DELETE that read the fresh row and wrote its tombstone between the upsert and the re-check).
    const answers = [true, false];
    const racing = makeApp({
      hubs: fakeHubs({
        admitPairing: async (...args: unknown[]) => {
          seen.push({ args, row: await pairingIdOf(account.agent.deviceId, mobile.deviceId) });
          return answers.shift();
        },
      }),
    });

    const res = await call(racing, "POST", "/v1/pairings", {
      token: account.agent.token,
      body: { mobile_id: mobile.deviceId, pairing_id: pairingId },
    });
    expect(res.status).toBe(410);
    expect(await errorCode(res)).toBe("pairing_removed");
    const args = [account.agent.deviceId, mobile.deviceId, pairingId];
    expect(seen).toEqual([{ args, row: null }, { args, row: pairingId }]);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBeNull();
  });

  it("a 410 also removes a row left behind under that same id, and never a row with another id", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const [x, y] = [newPairingId(), newPairingId()];
    const refusing = makeApp({ hubs: fakeHubs({ admitPairing: async () => false }) });
    const post = (id: string) =>
      call(refusing, "POST", "/v1/pairings", { token: account.agent.token, body: { mobile_id: mobile.deviceId, pairing_id: id } });

    await pair(app, account.agent.token, mobile.deviceId, x);
    expect((await post(y)).status).toBe(410);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(x); // another pairing's row stays
    expect((await post(x)).status).toBe(410);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBeNull();
  });

  it("fails closed when the hub cannot be asked: 500, nothing recorded, nothing secret logged", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const throwing = makeApp({
      hubs: fakeHubs({
        admitPairing: async () => {
          throw new Error("hub is down");
        },
      }),
    });
    const lines: string[] = [];
    const spy = vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    });
    const res = await call(throwing, "POST", "/v1/pairings", {
      token: account.agent.token,
      body: { mobile_id: mobile.deviceId, pairing_id: newPairingId() },
    });
    spy.mockRestore();
    expect(res.status).toBe(500);
    expect(await errorCode(res)).toBe("internal_error");
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBeNull();
    const output = lines.join("\n");
    expect(output).not.toContain("hub is down");
    expect(output).not.toContain(account.agent.token);
  });
});

describe("POST /v1/pairings: hub failure after the row was written", () => {
  it("answers 500 if the re-check throws (the row may already be recorded); a retry with the same id converges to 201", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    let calls = 0;
    const failingRecheck = makeApp({
      hubs: fakeHubs({
        admitPairing: async () => {
          calls++;
          if (calls === 2) throw new Error("hub is down");
          return true;
        },
      }),
    });

    const failed = await call(failingRecheck, "POST", "/v1/pairings", {
      token: account.agent.token,
      body: { mobile_id: mobile.deviceId, pairing_id: pairingId },
    });
    expect(failed.status).toBe(500);
    expect(await errorCode(failed)).toBe("internal_error");
    expect(calls).toBe(2);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(pairingId); // already recorded

    expect((await pair(app, account.agent.token, mobile.deviceId, pairingId)).status).toBe(201);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(pairingId);
    expect(await countPairings(account.agent.deviceId)).toBe(1);
  });

  it("a retry after that 500 still answers 410 if the phone unpaired meanwhile", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    let calls = 0;
    const failingRecheck = makeApp({
      hubs: fakeHubs({
        admitPairing: async () => {
          calls++;
          if (calls === 2) throw new Error("hub is down");
          return true;
        },
      }),
    });
    await call(failingRecheck, "POST", "/v1/pairings", {
      token: account.agent.token,
      body: { mobile_id: mobile.deviceId, pairing_id: pairingId },
    });
    expect((await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token })).status).toBe(204);

    const retry = await pair(app, account.agent.token, mobile.deviceId, pairingId);
    expect(retry.status).toBe(410);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBeNull();
  });
});

describe("DELETE /v1/pairings/:agent_id/:mobile_id", () => {
  it("lets the agent remove a pairing and notifies the connected mobile", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    await pair(app, account.agent.token, mobile.deviceId, pairingId);
    const m = await connect(app, mobile.token);

    const res = await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, {
      token: account.agent.token,
    });
    expect(res.status).toBe(204);
    expect(hex(await m.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, pairingId)));
    const fromMobile = await listDevices(app, mobile.token);
    expect(fromMobile.find((d) => d.id === account.agent.deviceId)?.paired_with_me).toBe(false);
  });

  it("lets the mobile remove a pairing and notifies the connected agent", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    await pair(app, account.agent.token, mobile.deviceId, pairingId);
    const a = await connect(app, account.agent.token);

    const res = await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, {
      token: mobile.token,
    });
    expect(res.status).toBe(204);
    expect(hex(await a.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, pairingId)));
  });

  it("queues the event for an offline agent and delivers it after the presence snapshot", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    const event = hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, pairingId));
    await pair(app, account.agent.token, mobile.deviceId, pairingId);
    const m = await connect(app, mobile.token);
    await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token });
    expect(hex(await m.nextBinary())).toBe(event);

    const a = await connect(app, account.agent.token);
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    expect(hex(await a.nextBinary())).toBe(event);
    await a.expectSilence();
  });

  it("replays a queued event (tombstone) on every agent connect until the phone is paired again under a new id", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    const event = hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, pairingId));
    await pair(app, account.agent.token, mobile.deviceId, pairingId);
    // The agent is offline when the phone unpairs.
    expect((await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token })).status).toBe(204);

    // Not deleted on send: a connect whose socket dies right after the replay must not lose it.
    for (let i = 0; i < 3; i++) {
      const a = await connect(app, account.agent.token);
      expect(hex(await a.nextBinary())).toBe(event);
      await a.expectSilence();
      a.close();
      await settle();
    }

    // Re-pairing the same phone (a new pairing, so a new id) clears the tombstone.
    expect((await pair(app, account.agent.token, mobile.deviceId)).status).toBe(201);
    const after = await connect(app, account.agent.token);
    await after.expectSilence();
  });

  it("never replays a stale event after unpair → re-pair of the same phone (agent online throughout)", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`;
    const pairingId = newPairingId();
    await pair(app, account.agent.token, mobile.deviceId, pairingId);
    const a = await connect(app, account.agent.token);

    expect((await call(app, "DELETE", path, { token: mobile.token })).status).toBe(204);
    expect(hex(await a.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, pairingId)));
    // The user pairs the same phone again (same device ids, new pairing id), then the desktop reconnects.
    expect((await pair(app, account.agent.token, mobile.deviceId)).status).toBe(201);
    a.close();
    await settle();

    const again = await connect(app, account.agent.token);
    await again.expectSilence(); // a replayed pairing_removed would drop the freshly re-paired phone
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
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).not.toBeNull(); // the bystander's 403 must not touch the row
    expect((await call(app, "DELETE", path, { token: mobile.token })).status).toBe(204);
    expect((await call(app, "DELETE", path, { token: mobile.token })).status).toBe(204);
  });

  it("replays the event to an agent that was online when it fired, on its next connect", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    const event = hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, pairingId));
    await pair(app, account.agent.token, mobile.deviceId, pairingId);
    const a = await connect(app, account.agent.token);

    const res = await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, {
      token: mobile.token,
    });
    expect(res.status).toBe(204);
    expect(hex(await a.nextBinary())).toBe(event);
    a.close();
    await settle();

    // A silently-dead live socket must not lose the event: it was queued too, and is replayed here.
    const again = await connect(app, account.agent.token);
    expect(hex(await again.nextBinary())).toBe(event);
    await again.expectSilence();
  });

  it("collapses repeated pair/unpair cycles while the agent is offline into one tombstone, for the latest pairing", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`;
    const ids = [newPairingId(), newPairingId(), newPairingId()];
    for (const id of ids) {
      expect((await pair(app, account.agent.token, mobile.deviceId, id)).status).toBe(201);
      expect((await call(app, "DELETE", path, { token: mobile.token })).status).toBe(204);
    }

    const a = await connect(app, account.agent.token);
    expect(hex(await a.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, ids[2]!)));
    await a.expectSilence(); // exactly one queued row survived three cycles, not three
  });

  it("keeps the pairing row when the hub RPC fails, so a retry can still deliver the event", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    await pair(app, account.agent.token, mobile.deviceId, pairingId);
    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`;

    let calls = 0;
    const failingOnce = makeApp({
      hubs: fakeHubs({
        notifyPairingRemoved: async () => {
          calls++;
          if (calls === 1) throw new Error("boom");
        },
      }),
    });

    const failed = await call(failingOnce, "DELETE", path, { token: mobile.token });
    expect(failed.status).toBe(500);
    expect(await errorCode(failed)).toBe("internal_error");
    // The failed hub call must not have deleted the row.
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(pairingId);

    const retried = await call(app, "DELETE", path, { token: mobile.token });
    expect(retried.status).toBe(204);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBeNull();

    const a = await connect(app, account.agent.token);
    expect(hex(await a.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, pairingId)));
  });
});

describe("DELETE /v1/pairings: ?pairing_id= (the agent's revoke) and the phone's unpair", () => {
  it("with a matching id deletes the row; the live event and the replayed tombstone carry that id", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    const event = hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, pairingId));
    await pair(app, account.agent.token, mobile.deviceId, pairingId);
    const m = await connect(app, mobile.token);

    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}?pairing_id=${pairingId}`;
    expect((await call(app, "DELETE", path, { token: account.agent.token })).status).toBe(204);
    expect(hex(await m.nextBinary())).toBe(event);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBeNull();

    const a = await connect(app, account.agent.token);
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    expect(hex(await a.nextBinary())).toBe(event);
    await a.expectSilence();
  });

  it("with a mismatching id is a no-op: 204, row kept, no tombstone, no event (a revoke landing after a re-pair)", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const [x, y] = [newPairingId(), newPairingId()];
    await pair(app, account.agent.token, mobile.deviceId, x);
    // The user revoked pairing x on the desktop and quickly paired the phone again (y) before the
    // revoke's DELETE reached the relay.
    await pair(app, account.agent.token, mobile.deviceId, y);
    const m = await connect(app, mobile.token);
    const a = await connect(app, account.agent.token);
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    expect(hex(await m.nextBinary())).toBe(hex(encodePresence(account.agent.deviceId, true)));

    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}?pairing_id=${x}`;
    expect((await call(app, "DELETE", path, { token: account.agent.token })).status).toBe(204);
    expect((await call(app, "DELETE", path, { token: mobile.token })).status).toBe(204);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(y);
    await m.expectSilence();
    await a.expectSilence();
    a.close();
    await settle();
    const again = await connect(app, account.agent.token);
    expect(hex(await again.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    await again.expectSilence(); // no tombstone was written
  });

  it("with an id but no row at all is a no-op: 204, no tombstone, no event", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const m = await connect(app, mobile.token);
    const a = await connect(app, account.agent.token);
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    expect(hex(await m.nextBinary())).toBe(hex(encodePresence(account.agent.deviceId, true)));

    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}?pairing_id=${newPairingId()}`;
    expect((await call(app, "DELETE", path, { token: account.agent.token })).status).toBe(204);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBeNull();
    await m.expectSilence();
    await a.expectSilence();
    a.close();
    await settle();
    const again = await connect(app, account.agent.token);
    expect(hex(await again.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    await again.expectSilence(); // no tombstone was written
  });

  it("without an id deletes whatever row exists and reports that row's id", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const [x, y] = [newPairingId(), newPairingId()];
    await pair(app, account.agent.token, mobile.deviceId, x);
    await pair(app, account.agent.token, mobile.deviceId, y);
    const a = await connect(app, account.agent.token);

    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`;
    expect((await call(app, "DELETE", path, { token: mobile.token })).status).toBe(204);
    expect(hex(await a.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, y)));
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBeNull();
  });

  it("refuses an invalid (non-UUIDv7 or not lower case) pairing_id query with 400 bad_request and leaves the row alone", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    await pair(app, account.agent.token, mobile.deviceId, pairingId);
    const base = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`;
    const queries = [
      "?pairing_id=not-a-uuid", "?pairing_id=", "?pairing_id", `?pairing_id=${crypto.randomUUID()}`,
      `?pairing_id=${pairingId.toUpperCase()}`,
    ];
    for (const query of queries) {
      const res = await call(app, "DELETE", `${base}${query}`, { token: account.agent.token });
      expect(res.status).toBe(400);
      expect(await errorCode(res)).toBe("bad_request");
    }
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(pairingId);
  });

  it("the revoke only deletes the row it notified about, even if a re-pair replaces the row in between", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const [x, y] = [newPairingId(), newPairingId()];
    await pair(app, account.agent.token, mobile.deviceId, x);
    const notified: unknown[][] = [];
    const racing = makeApp({
      hubs: fakeHubs({
        notifyPairingRemoved: async (...args: unknown[]) => {
          notified.push(args);
          // A re-pair's POST lands between the DELETE's read and its delete.
          db().run("UPDATE pairings SET pairing_id = ? WHERE agent_id = ? AND mobile_id = ?", y, account.agent.deviceId, mobile.deviceId);
        },
      }),
    });

    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}?pairing_id=${x}`;
    const res = await call(racing, "DELETE", path, { token: account.agent.token });
    expect(res.status).toBe(204);
    expect(notified).toEqual([[account.agent.deviceId, mobile.deviceId, x]]);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(y);
  });

  it("the phone's unpair tries again when the row was replaced in between, and reports the id it deleted", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const [x, y] = [newPairingId(), newPairingId()];
    await pair(app, account.agent.token, mobile.deviceId, x);
    const notified: unknown[][] = [];
    const racing = makeApp({
      hubs: fakeHubs({
        notifyPairingRemoved: async (...args: unknown[]) => {
          notified.push(args);
          if (notified.length === 1) {
            db().run("UPDATE pairings SET pairing_id = ? WHERE agent_id = ? AND mobile_id = ?", y, account.agent.deviceId, mobile.deviceId);
          }
        },
      }),
    });

    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`;
    const res = await call(racing, "DELETE", path, { token: mobile.token });
    expect(res.status).toBe(204);
    expect(notified).toEqual([
      [account.agent.deviceId, mobile.deviceId, x],
      [account.agent.deviceId, mobile.deviceId, y],
    ]);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBeNull();
  });

  it("gives up with 500 (row kept) rather than loop forever if the row keeps changing", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await pair(app, account.agent.token, mobile.deviceId);
    let calls = 0;
    const churning = makeApp({
      hubs: fakeHubs({
        notifyPairingRemoved: async () => {
          calls++;
          db().run("UPDATE pairings SET pairing_id = ? WHERE agent_id = ? AND mobile_id = ?", newPairingId(), account.agent.deviceId, mobile.deviceId);
        },
      }),
    });

    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`;
    const res = await call(churning, "DELETE", path, { token: mobile.token });
    expect(res.status).toBe(500);
    expect(await errorCode(res)).toBe("internal_error");
    expect(calls).toBe(3);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).not.toBeNull();
  });
});

describe("UserHub calls from routes", () => {
  it("online() lists connected devices and disconnect() closes them with the given code", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const a = await connect(app, account.agent.token);
    const m = await connect(app, mobile.token);
    await m.nextBinary();
    await a.nextBinary();
    const hub = hubs().forUser(account.agent.userId);
    expect((await hub.online()).sort()).toEqual([account.agent.deviceId, mobile.deviceId].sort());

    await hub.disconnect([mobile.deviceId], 4002);
    expect(await m.closed).toEqual({ code: 4002, reason: "revoked" });
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, false)));
    expect(await hub.online()).toEqual([account.agent.deviceId]);
    await hub.disconnect([mobile.deviceId], 4002); // already gone: no-op
    await a.expectSilence();
  });

  it("keeps one tombstone per (agent, mobile) holding the newest id: a newer removal overwrites it, an older one does not", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const other = await loginDevice(app, account, "mobile");
    const [w, x, y, z] = [newPairingId(), newPairingId(), newPairingId(), newPairingId()];
    const hub = hubs().forUser(account.agent.userId);
    await hub.notifyPairingRemoved(account.agent.deviceId, mobile.deviceId, x);
    await hub.notifyPairingRemoved(account.agent.deviceId, other.deviceId, z);
    await hub.notifyPairingRemoved(account.agent.deviceId, mobile.deviceId, y); // newer: overwrites x
    await hub.notifyPairingRemoved(account.agent.deviceId, mobile.deviceId, w); // older: y stays

    const a = await connect(app, account.agent.token);
    const replayed = [hex(await a.nextBinary()), hex(await a.nextBinary())].sort();
    expect(replayed).toEqual([
      hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, y)),
      hex(pairingRemovedEvent(account.agent.deviceId, other.deviceId, z)),
    ].sort());
    await a.expectSilence();
  });

  it("admitPairing() refuses ids not newer than the tombstone (keeping it), and clears it for a newer id", async () => {
    const agentId = crypto.randomUUID();
    const mobileId = crypto.randomUUID();
    const [w, x, y] = [newPairingId(), newPairingId(), newPairingId()];
    const hub = hubs().forUser(crypto.randomUUID());
    expect(await hub.admitPairing(agentId, mobileId, x)).toBe(true); // no tombstone at all
    await hub.notifyPairingRemoved(agentId, mobileId, x);
    expect(await hub.admitPairing(agentId, mobileId, x)).toBe(false); // the removed pairing itself
    expect(await hub.admitPairing(agentId, mobileId, w)).toBe(false); // an older pairing
    expect(await hub.admitPairing(agentId, mobileId, x)).toBe(false); // still there
    expect(await hub.admitPairing(crypto.randomUUID(), mobileId, w)).toBe(true); // other agent: untouched
    expect(await hub.admitPairing(agentId, mobileId, x)).toBe(false);
    expect(await hub.admitPairing(agentId, mobileId, y)).toBe(true); // newer: clears x's tombstone
    expect(await hub.admitPairing(agentId, mobileId, w)).toBe(true);
    expect(await hub.purgeAll()).toBe(0);
  });
});

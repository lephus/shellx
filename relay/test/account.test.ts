import { env } from "cloudflare:workers";
import { describe, expect, it, vi } from "vitest";
import { CONN_ID_HEADER, DEVICE_ID_HEADER, DEVICE_KIND_HEADER, hubFor } from "../src/hub/user-hub";
import { encodePresence, pairingRemovedEvent } from "../src/protocol/frames";
import {
  call, connect, CountingLimiter, deviceBody, errorCode, hex, loginDevice, makeApp, registerAccount, TestSocket, unlimited,
} from "./helpers";

const NEW_PASSWORD = "brand new password";

describe("POST /v1/auth/password", () => {
  it("is agent-only and validates the new password", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const byMobile = await call(app, "POST", "/v1/auth/password", { token: mobile.token, body: { new_password: NEW_PASSWORD } });
    expect(byMobile.status).toBe(403);
    expect(await errorCode(byMobile)).toBe("agent_only");
    const weak = await call(app, "POST", "/v1/auth/password", { token: account.agent.token, body: { new_password: "short" } });
    expect(weak.status).toBe(400);
    expect(await errorCode(weak)).toBe("weak_password");
    expect((await call(app, "POST", "/v1/auth/password", { body: { new_password: NEW_PASSWORD } })).status).toBe(401);
  });

  it("changes the password, revokes every other device (4002) and keeps pairings", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const secondAgent = await loginDevice(app, account, "agent");
    expect((await call(app, "POST", "/v1/pairings", { token: account.agent.token, body: { mobile_id: mobile.deviceId } })).status).toBe(201);

    const a = await connect(app, account.agent.token);
    const m = await connect(app, mobile.token);
    const a2 = await connect(app, secondAgent.token);
    const before = Date.now();

    const res = await call(app, "POST", "/v1/auth/password", { token: account.agent.token, body: { new_password: NEW_PASSWORD } });
    expect(res.status).toBe(204);
    expect((await m.closed).code).toBe(4002);
    expect((await a2.closed).code).toBe(4002);

    // The caller keeps its token and its socket; the others' tokens are gone.
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(200);
    expect((await call(app, "GET", "/v1/devices", { token: mobile.token })).status).toBe(401);
    expect((await call(app, "GET", "/v1/devices", { token: secondAgent.token })).status).toBe(401);
    const offline = new Set<string>();
    while (offline.size < 2) {
      const frame = await a.nextBinary();
      if (frame[1] === 0x02 && frame[18] === 0) offline.add(hex(frame));
    }
    expect(offline).toEqual(new Set([hex(encodePresence(mobile.deviceId, false)), hex(encodePresence(secondAgent.deviceId, false))]));

    // Old password is dead, new one works; pairing survived.
    const oldLogin = await call(app, "POST", "/v1/auth/login", { body: { email: account.email, password: account.password, device: deviceBody("mobile") } });
    expect(oldLogin.status).toBe(401);
    const newLogin = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: NEW_PASSWORD, device: deviceBody("mobile", { public_key: mobile.publicKey }) },
    });
    expect(newLogin.status).toBe(200);
    const pairing = await env.DB.prepare("SELECT COUNT(*) AS n FROM pairings WHERE agent_id = ? AND mobile_id = ?")
      .bind(account.agent.deviceId, mobile.deviceId).first<{ n: number }>();
    expect(pairing?.n).toBe(1);
    const changed = await env.DB.prepare("SELECT password_changed_at FROM users WHERE id = ?")
      .bind(account.agent.userId).first<{ password_changed_at: number }>();
    expect(changed?.password_changed_at).toBeGreaterThanOrEqual(before);
  });
});

/**
 * The real D1 binding, except that the route's first `batch()` first runs `hook` — a concurrent
 * request landing between the route's reads and its write, deterministically.
 */
function dbRacingFirstBatch(hook: () => Promise<void>): D1Database {
  let fired = false;
  return {
    prepare: (query: string) => env.DB.prepare(query),
    batch: async (statements: D1PreparedStatement[]) => {
      if (!fired) {
        fired = true;
        await hook();
      }
      return env.DB.batch(statements);
    },
  } as unknown as D1Database;
}

async function settle<T>(promise: Promise<T>, ms = 1500): Promise<T | "timeout"> {
  return Promise.race([promise, new Promise<"timeout">((resolve) => setTimeout(() => resolve("timeout"), ms))]);
}

describe("password change races (final review M1)", () => {
  it("a login that verified the old password gets no token once the change has committed", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const device = deviceBody("mobile");
    // Between this login's argon2 verify (old hash) and its token insert, the agent changes the password.
    const racingDb = dbRacingFirstBatch(async () => {
      const changed = await call(app, "POST", "/v1/auth/password", { token: account.agent.token, body: { new_password: NEW_PASSWORD } });
      expect(changed.status).toBe(204);
    });
    const res = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: account.password, device },
      bindings: { DB: racingDb },
    });
    expect(res.status).toBe(401);
    expect(await errorCode(res)).toBe("invalid_credentials");
    const tokens = await env.DB.prepare(
      "SELECT COUNT(*) AS n FROM tokens t JOIN devices d ON d.id = t.device_id WHERE d.user_id = ? AND d.public_key = ?",
    ).bind(account.agent.userId, device.public_key as string).first<{ n: number }>();
    expect(tokens?.n).toBe(0);
    // The caller of the change is unaffected, and the new password works.
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(200);
    const fresh = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: NEW_PASSWORD, device: deviceBody("mobile") },
    });
    expect(fresh.status).toBe(200);
  });

  it("closes a device that connected after any device list would have been read, but keeps the caller", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const caller = await connect(app, account.agent.token);
    let late: TestSocket | undefined;
    // A phone signs in and connects after the route read its device list but before the change commits.
    const racingDb = dbRacingFirstBatch(async () => {
      const mobile = await loginDevice(app, account, "mobile");
      late = await connect(app, mobile.token);
    });
    const res = await call(app, "POST", "/v1/auth/password", {
      token: account.agent.token,
      body: { new_password: NEW_PASSWORD },
      bindings: { DB: racingDb },
    });
    expect(res.status).toBe(204);
    expect(late).toBeDefined();
    expect(await settle(late!.closed)).toEqual({ code: 4002, reason: "revoked" });
    expect(await settle(caller.closed, 300)).toBe("timeout"); // the caller's own socket stays up
  });
});

describe("POST /v1/auth/logout", () => {
  it("mobile: deletes only its token; pairings stay", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await call(app, "POST", "/v1/pairings", { token: account.agent.token, body: { mobile_id: mobile.deviceId } });
    expect((await call(app, "POST", "/v1/auth/logout", { token: mobile.token })).status).toBe(204);
    expect((await call(app, "GET", "/v1/devices", { token: mobile.token })).status).toBe(401);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(200);
    const pairing = await env.DB.prepare("SELECT COUNT(*) AS n FROM pairings WHERE mobile_id = ?")
      .bind(mobile.deviceId).first<{ n: number }>();
    expect(pairing?.n).toBe(1);
  });

  it("agent: deletes its token and all its pairings, and tells connected mobiles", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await call(app, "POST", "/v1/pairings", { token: account.agent.token, body: { mobile_id: mobile.deviceId } });
    const m = await connect(app, mobile.token);

    expect((await call(app, "POST", "/v1/auth/logout", { token: account.agent.token })).status).toBe(204);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(401);
    const pairing = await env.DB.prepare("SELECT COUNT(*) AS n FROM pairings WHERE agent_id = ?")
      .bind(account.agent.deviceId).first<{ n: number }>();
    expect(pairing?.n).toBe(0);
    expect(hex(await m.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId)));
  });

  it("requires a token", async () => {
    const res = await call(makeApp(), "POST", "/v1/auth/logout");
    expect(res.status).toBe(401);
  });
});

describe("DELETE /v1/account", () => {
  const countRows = async (sql: string, id: string) =>
    (await env.DB.prepare(sql).bind(id).first<{ n: number }>())?.n;

  it("refuses a wrong password with 401 invalid_credentials and deletes nothing", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const res = await call(app, "DELETE", "/v1/account", { token: account.agent.token, body: { password: "not my password" } });
    expect(res.status).toBe(401);
    expect(await errorCode(res)).toBe("invalid_credentials");
    const missing = await call(app, "DELETE", "/v1/account", { token: account.agent.token, body: {} });
    expect(missing.status).toBe(401);
    expect(await countRows("SELECT COUNT(*) AS n FROM users WHERE id = ?", account.agent.userId)).toBe(1);
  });

  it("requires a token and a JSON body", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    expect((await call(app, "DELETE", "/v1/account", { body: { password: account.password } })).status).toBe(401);
    const notJson = await call(app, "DELETE", "/v1/account", { token: account.agent.token, body: "{oops" });
    expect(notJson.status).toBe(400);
    expect(await errorCode(notJson)).toBe("bad_request");
  });

  it("deletes user, devices, tokens and pairings, and closes every socket with 4002", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await call(app, "POST", "/v1/pairings", { token: account.agent.token, body: { mobile_id: mobile.deviceId } });
    const a = await connect(app, account.agent.token);
    const m = await connect(app, mobile.token);

    const res = await call(app, "DELETE", "/v1/account", { token: mobile.token, body: { password: account.password } });
    expect(res.status).toBe(204);
    expect((await a.closed).code).toBe(4002);
    expect((await m.closed).code).toBe(4002);

    expect(await countRows("SELECT COUNT(*) AS n FROM users WHERE id = ?", account.agent.userId)).toBe(0);
    expect(await countRows("SELECT COUNT(*) AS n FROM devices WHERE user_id = ?", account.agent.userId)).toBe(0);
    expect(await countRows("SELECT COUNT(*) AS n FROM tokens WHERE device_id = ?", mobile.deviceId)).toBe(0);
    expect(await countRows("SELECT COUNT(*) AS n FROM tokens WHERE device_id = ?", account.agent.deviceId)).toBe(0);
    expect(await countRows("SELECT COUNT(*) AS n FROM pairings WHERE agent_id = ?", account.agent.deviceId)).toBe(0);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(401);

    // The e-mail address is free again.
    const again = await call(app, "POST", "/v1/auth/register", {
      body: { email: account.email, password: "a fresh password", device: deviceBody("agent") },
    });
    expect(again.status).toBe(201);
  });

  it("rate limits password attempts per account email", async () => {
    const loginEmail = new CountingLimiter(5);
    const app = makeApp({ limiters: () => ({ ...unlimited, loginEmail }) });
    const account = await registerAccount(app);
    for (let i = 0; i < 5; i++) {
      const res = await call(app, "DELETE", "/v1/account", { token: account.agent.token, body: { password: "wrong password" } });
      expect(res.status).toBe(401);
    }
    const blocked = await call(app, "DELETE", "/v1/account", { token: account.agent.token, body: { password: account.password } });
    expect(blocked.status).toBe(429);
    expect(loginEmail.calls).toEqual(Array(6).fill(account.email));
  });

  it("purges the hub's durable pairing_removed queue once the account is gone", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await call(app, "POST", "/v1/pairings", { token: account.agent.token, body: { mobile_id: mobile.deviceId } });
    // The agent never connects: unpairing from the mobile side durably queues the event for it
    // (Task 8's pending_pairing_removed table).
    const unpaired = await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token });
    expect(unpaired.status).toBe(204);

    const res = await call(app, "DELETE", "/v1/account", { token: mobile.token, body: { password: account.password } });
    expect(res.status).toBe(204);

    // The account (and every device/token) is gone, so we can't reconnect through the normal HTTP
    // auth path to observe redelivery; call the hub RPC directly instead, as the "UserHub RPC" tests
    // in devices-pairings.test.ts do. purgeAll() run here a second time proves the route's own call
    // already emptied the queue: a leftover row would make it return more than 0.
    const hub = hubFor(env, account.agent.userId);
    expect(await hub.purgeAll()).toBe(0);
  });

  it("closes a device whose socket lands in the hub only after any device-id snapshot would have been taken", async () => {
    // Fix round 1: the old implementation read `SELECT id FROM devices` *before* the D1 delete and
    // closed only that list. closeAccount() (see UserHub.closeAccount) takes no such list — it
    // closes whatever is actually live in the hub at the moment it runs. Simulate a device whose
    // socket is only created *after* the point such a snapshot would have been read (and after the
    // D1 delete has already committed) by driving the Durable Object's own `fetch()` directly —
    // exactly how a WebSocket upgrade that already passed `authenticate()` earlier, but is only now
    // landing in the hub, would look from the hub's point of view (see also the TOCTOU test above).
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const realHub = env.USER_HUB.get(env.USER_HUB.idFromName(account.agent.userId));
    let lateSocket: TestSocket | undefined;
    const lateConnectHub = {
      idFromName: (name: string) => name,
      get: () => ({
        closeAccount: async () => {
          const headers = new Headers({
            Upgrade: "websocket",
            [DEVICE_ID_HEADER]: mobile.deviceId,
            [DEVICE_KIND_HEADER]: "mobile",
            [CONN_ID_HEADER]: crypto.randomUUID(),
          });
          const upgrade = await realHub.fetch(new Request("https://user-hub/connect", { headers }));
          lateSocket = new TestSocket(upgrade.webSocket!);
          return realHub.closeAccount();
        },
      }),
    } as unknown as typeof env.USER_HUB;

    const res = await call(app, "DELETE", "/v1/account", {
      token: account.agent.token,
      body: { password: account.password },
      bindings: { USER_HUB: lateConnectHub },
    });
    expect(res.status).toBe(204);
    expect((await lateSocket!.closed).code).toBe(4002);
  });

  it("still deletes the account and returns 204 if closing the hub afterward throws, logging metadata only", async () => {
    // Fix round 1: the delete is irreversible; a hub outage after it must not turn a successful
    // account deletion into a 500.
    const app = makeApp();
    const account = await registerAccount(app);
    const throwingHub = {
      idFromName: (name: string) => name,
      get: () => ({
        closeAccount: async () => {
          throw new Error("hub is down");
        },
      }),
    } as unknown as typeof env.USER_HUB;

    const lines: string[] = [];
    const spy = vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    });
    const res = await call(app, "DELETE", "/v1/account", {
      token: account.agent.token,
      body: { password: account.password },
      bindings: { USER_HUB: throwingHub },
    });
    spy.mockRestore();

    expect(res.status).toBe(204);
    const gone = await env.DB.prepare("SELECT 1 FROM users WHERE id = ?").bind(account.agent.userId).first();
    expect(gone).toBeNull();
    const output = lines.join("\n");
    expect(output).toContain("account_close_failed");
    expect(output).not.toContain("hub is down");
  });
});

describe("agent logout: safe notify-then-delete order and queue purge", () => {
  it("keeps the token and pairing intact when a hub RPC fails, so a retried logout can still deliver the event", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await call(app, "POST", "/v1/pairings", { token: account.agent.token, body: { mobile_id: mobile.deviceId } });

    let calls = 0;
    // Unlike devices-pairings.test.ts's "failingOnce" (which succeeds after its first failure),
    // this fake fails notifyPairingRemoved on *every* call — the test only ever exercises one.
    const alwaysFailingNotify = {
      idFromName: (name: string) => name,
      get: () => ({
        online: async () => [],
        disconnect: async () => {},
        notifyPairingRemoved: async () => {
          calls++;
          throw new Error("boom");
        },
        purgeAgent: async () => 0,
        purgeAll: async () => 0,
      }),
    } as unknown as typeof env.USER_HUB;

    const failed = await call(app, "POST", "/v1/auth/logout", { token: account.agent.token, bindings: { USER_HUB: alwaysFailingNotify } });
    expect(failed.status).toBe(500);
    expect(await errorCode(failed)).toBe("internal_error");
    expect(calls).toBe(1);
    // Nothing was deleted: the token is still valid and the pairing row survives.
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(200);
    const stillPaired = await env.DB.prepare("SELECT 1 FROM pairings WHERE agent_id = ?")
      .bind(account.agent.deviceId).first();
    expect(stillPaired).not.toBeNull();

    const retried = await call(app, "POST", "/v1/auth/logout", { token: account.agent.token });
    expect(retried.status).toBe(204);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(401);
    const gone = await env.DB.prepare("SELECT 1 FROM pairings WHERE agent_id = ?")
      .bind(account.agent.deviceId).first();
    expect(gone).toBeNull();
  });

  it("purges any pairing_removed rows still queued for the agent, even ones unrelated to this logout's own pairings", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await call(app, "POST", "/v1/pairings", { token: account.agent.token, body: { mobile_id: mobile.deviceId } });
    // The agent never connects: removing the pairing from the mobile side durably queues the event
    // for the agent (Task 8). Re-pair with a *different* mobile so the agent still has a current
    // pairing at logout time — proving the purge isn't limited to pairings this same logout deleted.
    const unpaired = await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token });
    expect(unpaired.status).toBe(204);
    const mobile2 = await loginDevice(app, account, "mobile");
    await call(app, "POST", "/v1/pairings", { token: account.agent.token, body: { mobile_id: mobile2.deviceId } });

    expect((await call(app, "POST", "/v1/auth/logout", { token: account.agent.token })).status).toBe(204);

    const hub = hubFor(env, account.agent.userId);
    expect(await hub.purgeAgent(account.agent.deviceId)).toBe(0);
  });

  it("an agent that signs in again after logout gets no replay of tombstones from before the logout", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await call(app, "POST", "/v1/pairings", { token: account.agent.token, body: { mobile_id: mobile.deviceId } });
    await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token });
    // The tombstone is replayed on connect (and kept) ...
    const before = await connect(app, account.agent.token);
    expect(hex(await before.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId)));
    before.close();
    await new Promise((resolve) => setTimeout(resolve, 50));

    // ... until the agent logs out, which purges it.
    expect((await call(app, "POST", "/v1/auth/logout", { token: account.agent.token })).status).toBe(204);
    const again = await loginDevice(app, account, "agent", account.agent.publicKey);
    expect(again.deviceId).toBe(account.agent.deviceId);
    const after = await connect(app, again.token);
    await after.expectSilence();
  });

  it("still logs the agent out (204) if purging its queue afterward throws, logging metadata only", async () => {
    // Fix round 1: same best-effort treatment as account deletion's closeAccount() — the token and
    // pairings are already gone by this point, so a hub outage here must not turn a successful
    // logout into a 500.
    const app = makeApp();
    const account = await registerAccount(app);
    const throwingPurge = {
      idFromName: (name: string) => name,
      get: () => ({
        notifyPairingRemoved: async () => {},
        purgeAgent: async () => {
          throw new Error("hub is down");
        },
      }),
    } as unknown as typeof env.USER_HUB;

    const lines: string[] = [];
    const spy = vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    });
    const res = await call(app, "POST", "/v1/auth/logout", { token: account.agent.token, bindings: { USER_HUB: throwingPurge } });
    spy.mockRestore();

    expect(res.status).toBe(204);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(401);
    const output = lines.join("\n");
    expect(output).toContain("agent_purge_failed");
    expect(output).not.toContain("hub is down");
  });
});

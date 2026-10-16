import { describe, expect, it, vi } from "vitest";
import { passwords, type PasswordHasher } from "../src/auth/password.js";
import type { HubRegistry } from "../src/hub/registry.js";
import { encodePresence, pairingRemovedEvent } from "../src/protocol/frames.js";
import {
  call, connect, CountingLimiter, db, deviceBody, errorCode, FakeSocket, hex, hubs, loginDevice, makeApp, newPairingId,
  pair, registerAccount, type TestSocket, unlimited,
} from "./helpers.js";

const NEW_PASSWORD = "brand new password";

/** A registry whose `forUser(...)` returns `hub` for every account (hub methods the test fakes). */
function fakeHubs(hub: Record<string, unknown>): HubRegistry {
  return { forUser: () => hub } as unknown as HubRegistry;
}

/**
 * The real argon2id hasher, except that the first `hash` (or `verify`) finishes only after `hook`
 * ran: a concurrent request landing between a route's password check and its write, deterministically.
 */
function hasherRacing(on: "hash" | "verify", hook: () => Promise<void>): PasswordHasher {
  let fired = false;
  const race = async () => {
    if (!fired) {
      fired = true;
      await hook();
    }
  };
  return {
    async hash(password) {
      const phc = await passwords.hash(password);
      if (on === "hash") await race();
      return phc;
    },
    async verify(password, phc) {
      const ok = await passwords.verify(password, phc);
      if (on === "verify") await race();
      return ok;
    },
  };
}

async function settle<T>(promise: Promise<T>, ms = 1500): Promise<T | "timeout"> {
  return Promise.race([promise, new Promise<"timeout">((resolve) => setTimeout(() => resolve("timeout"), ms))]);
}

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
    expect((await pair(app, account.agent.token, mobile.deviceId)).status).toBe(201);

    const a = await connect(app, account.agent.token);
    const m = await connect(app, mobile.token);
    const a2 = await connect(app, secondAgent.token);
    const before = Date.now();

    const res = await call(app, "POST", "/v1/auth/password", { token: account.agent.token, body: { new_password: NEW_PASSWORD } });
    expect(res.status).toBe(204);
    expect((await m.closed).code).toBe(4002);
    expect((await a2.closed).code).toBe(4002);

    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(200);
    expect((await call(app, "GET", "/v1/devices", { token: mobile.token })).status).toBe(401);
    expect((await call(app, "GET", "/v1/devices", { token: secondAgent.token })).status).toBe(401);
    const offline = new Set<string>();
    while (offline.size < 2) {
      const frame = await a.nextBinary();
      if (frame[1] === 0x02 && frame[18] === 0) offline.add(hex(frame));
    }
    expect(offline).toEqual(new Set([hex(encodePresence(mobile.deviceId, false)), hex(encodePresence(secondAgent.deviceId, false))]));

    const oldLogin = await call(app, "POST", "/v1/auth/login", { body: { email: account.email, password: account.password, device: deviceBody("mobile") } });
    expect(oldLogin.status).toBe(401);
    const newLogin = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: NEW_PASSWORD, device: deviceBody("mobile", { public_key: mobile.publicKey }) },
    });
    expect(newLogin.status).toBe(200);
    const pairing = db().get<{ n: number }>(
      "SELECT COUNT(*) AS n FROM pairings WHERE agent_id = ? AND mobile_id = ?", account.agent.deviceId, mobile.deviceId,
    );
    expect(pairing?.n).toBe(1);
    const changed = db().get<{ password_changed_at: number }>("SELECT password_changed_at FROM users WHERE id = ?", account.agent.userId);
    expect(changed?.password_changed_at).toBeGreaterThanOrEqual(before);
  });
});

describe("password change races (final review M1)", () => {
  it("a login that verified the old password gets no token once the change has committed", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const device = deviceBody("mobile");
    // Between this login's argon2 verify (old hash) and its token insert, the agent changes the password.
    const racing = makeApp({
      passwords: hasherRacing("verify", async () => {
        const changed = await call(app, "POST", "/v1/auth/password", { token: account.agent.token, body: { new_password: NEW_PASSWORD } });
        expect(changed.status).toBe(204);
      }),
    });
    const res = await call(racing, "POST", "/v1/auth/login", { body: { email: account.email, password: account.password, device } });
    expect(res.status).toBe(401);
    expect(await errorCode(res)).toBe("invalid_credentials");
    const tokens = db().get<{ n: number }>(
      "SELECT COUNT(*) AS n FROM tokens t JOIN devices d ON d.id = t.device_id WHERE d.user_id = ? AND d.public_key = ?",
      account.agent.userId,
      Buffer.from(device.public_key as string, "base64url"),
    );
    expect(tokens?.n).toBe(0);
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
    // A phone signs in and connects after the route hashed the new password but before the change commits.
    const racing = makeApp({
      passwords: hasherRacing("hash", async () => {
        const mobile = await loginDevice(app, account, "mobile");
        late = await connect(app, mobile.token);
      }),
    });
    const res = await call(racing, "POST", "/v1/auth/password", {
      token: account.agent.token,
      body: { new_password: NEW_PASSWORD },
    });
    expect(res.status).toBe(204);
    expect(late).toBeDefined();
    expect(await settle(late!.closed)).toEqual({ code: 4002, reason: "revoked" });
    expect(await settle(caller.closed, 300)).toBe("timeout");
  });
});

describe("POST /v1/auth/logout", () => {
  it("mobile: deletes only its token; pairings stay", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await pair(app, account.agent.token, mobile.deviceId);
    expect((await call(app, "POST", "/v1/auth/logout", { token: mobile.token })).status).toBe(204);
    expect((await call(app, "GET", "/v1/devices", { token: mobile.token })).status).toBe(401);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(200);
    expect(db().get<{ n: number }>("SELECT COUNT(*) AS n FROM pairings WHERE mobile_id = ?", mobile.deviceId)?.n).toBe(1);
  });

  it("agent: deletes its token and all its pairings, and tells each connected mobile its pairing's id", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const mobile2 = await loginDevice(app, account, "mobile");
    const [first, second] = [newPairingId(), newPairingId()];
    await pair(app, account.agent.token, mobile.deviceId, first);
    await pair(app, account.agent.token, mobile2.deviceId, second);
    const m = await connect(app, mobile.token);
    const m2 = await connect(app, mobile2.token);
    expect(hex(await m.nextBinary())).toBe(hex(encodePresence(mobile2.deviceId, true)));
    expect(hex(await m2.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));

    expect((await call(app, "POST", "/v1/auth/logout", { token: account.agent.token })).status).toBe(204);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(401);
    expect(db().get<{ n: number }>("SELECT COUNT(*) AS n FROM pairings WHERE agent_id = ?", account.agent.deviceId)?.n).toBe(0);
    expect(hex(await m.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, first)));
    expect(hex(await m2.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile2.deviceId, second)));
    await m.expectSilence();
    await m2.expectSilence();
  });

  it("requires a token", async () => {
    const res = await call(makeApp(), "POST", "/v1/auth/logout");
    expect(res.status).toBe(401);
  });
});

describe("DELETE /v1/account", () => {
  const countRows = (sql: string, id: string) => db().get<{ n: number }>(sql, id)?.n;

  it("refuses a wrong password with 401 invalid_credentials and deletes nothing", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const res = await call(app, "DELETE", "/v1/account", { token: account.agent.token, body: { password: "not my password" } });
    expect(res.status).toBe(401);
    expect(await errorCode(res)).toBe("invalid_credentials");
    const missing = await call(app, "DELETE", "/v1/account", { token: account.agent.token, body: {} });
    expect(missing.status).toBe(401);
    expect(countRows("SELECT COUNT(*) AS n FROM users WHERE id = ?", account.agent.userId)).toBe(1);
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
    await pair(app, account.agent.token, mobile.deviceId);
    const a = await connect(app, account.agent.token);
    const m = await connect(app, mobile.token);

    const res = await call(app, "DELETE", "/v1/account", { token: mobile.token, body: { password: account.password } });
    expect(res.status).toBe(204);
    expect((await a.closed).code).toBe(4002);
    expect((await m.closed).code).toBe(4002);

    expect(countRows("SELECT COUNT(*) AS n FROM users WHERE id = ?", account.agent.userId)).toBe(0);
    expect(countRows("SELECT COUNT(*) AS n FROM devices WHERE user_id = ?", account.agent.userId)).toBe(0);
    expect(countRows("SELECT COUNT(*) AS n FROM tokens WHERE device_id = ?", mobile.deviceId)).toBe(0);
    expect(countRows("SELECT COUNT(*) AS n FROM tokens WHERE device_id = ?", account.agent.deviceId)).toBe(0);
    expect(countRows("SELECT COUNT(*) AS n FROM pairings WHERE agent_id = ?", account.agent.deviceId)).toBe(0);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(401);

    const again = await call(app, "POST", "/v1/auth/register", {
      body: { email: account.email, password: "a fresh password", device: deviceBody("agent") },
    });
    expect(again.status).toBe(201);
  });

  it("rate limits password attempts per account email", async () => {
    const loginEmail = new CountingLimiter(5);
    const app = makeApp({ limiters: { ...unlimited, loginEmail } });
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
    await pair(app, account.agent.token, mobile.deviceId);
    const unpaired = await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token });
    expect(unpaired.status).toBe(204);

    const res = await call(app, "DELETE", "/v1/account", { token: mobile.token, body: { password: account.password } });
    expect(res.status).toBe(204);
    // A leftover row would make this second purge return more than 0.
    expect(await hubs().forUser(account.agent.userId).purgeAll()).toBe(0);
  });

  it("closes a device whose socket lands in the hub only after any device-id snapshot would have been taken", async () => {
    // closeAccount takes no device list: it closes whatever is live when it runs. Simulate a socket
    // that joins the hub after the user row is already gone (its upgrade passed authenticate()
    // earlier) by joining it directly, right before the real closeAccount runs.
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const late = new FakeSocket();
    const lateJoin = makeApp({
      hubs: fakeHubs({
        closeAccount: async () => {
          const hub = hubs().forUser(account.agent.userId);
          await hub.connect(late, { deviceId: mobile.deviceId, kind: "mobile", connId: crypto.randomUUID() });
          return hub.closeAccount();
        },
      }),
    });
    const res = await call(lateJoin, "DELETE", "/v1/account", { token: account.agent.token, body: { password: account.password } });
    expect(res.status).toBe(204);
    expect(late.closedWith).toEqual({ code: 4002, reason: "revoked" });
  });

  it("still deletes the account and returns 204 if closing the hub afterward throws, logging metadata only", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const throwing = makeApp({
      hubs: fakeHubs({
        closeAccount: async () => {
          throw new Error("hub is down");
        },
      }),
    });
    const lines: string[] = [];
    const spy = vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    });
    const res = await call(throwing, "DELETE", "/v1/account", { token: account.agent.token, body: { password: account.password } });
    spy.mockRestore();

    expect(res.status).toBe(204);
    expect(db().get("SELECT 1 FROM users WHERE id = ?", account.agent.userId)).toBeUndefined();
    const output = lines.join("\n");
    expect(output).toContain("account_close_failed");
    expect(output).not.toContain("hub is down");
  });
});

describe("agent logout: safe notify-then-delete order and queue purge", () => {
  it("keeps the token and pairing intact when a hub call fails, so a retried logout can still deliver the event", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await pair(app, account.agent.token, mobile.deviceId);

    let calls = 0;
    const failing = makeApp({
      hubs: fakeHubs({
        notifyPairingRemoved: async () => {
          calls++;
          throw new Error("boom");
        },
        purgeAgent: async () => 0,
      }),
    });
    const failed = await call(failing, "POST", "/v1/auth/logout", { token: account.agent.token });
    expect(failed.status).toBe(500);
    expect(await errorCode(failed)).toBe("internal_error");
    expect(calls).toBe(1);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(200);
    expect(db().get("SELECT 1 FROM pairings WHERE agent_id = ?", account.agent.deviceId)).toBeDefined();

    const retried = await call(app, "POST", "/v1/auth/logout", { token: account.agent.token });
    expect(retried.status).toBe(204);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(401);
    expect(db().get("SELECT 1 FROM pairings WHERE agent_id = ?", account.agent.deviceId)).toBeUndefined();
  });

  it("purges any pairing_removed rows still queued for the agent, even ones unrelated to this logout's own pairings", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await pair(app, account.agent.token, mobile.deviceId);
    const unpaired = await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token });
    expect(unpaired.status).toBe(204);
    const mobile2 = await loginDevice(app, account, "mobile");
    await pair(app, account.agent.token, mobile2.deviceId);

    expect((await call(app, "POST", "/v1/auth/logout", { token: account.agent.token })).status).toBe(204);
    expect(await hubs().forUser(account.agent.userId).purgeAgent(account.agent.deviceId)).toBe(0);
  });

  it("an agent that signs in again after logout gets no replay of tombstones from before the logout", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    await pair(app, account.agent.token, mobile.deviceId, pairingId);
    await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token });
    const before = await connect(app, account.agent.token);
    expect(hex(await before.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, pairingId)));
    before.close();
    await before.closed;

    expect((await call(app, "POST", "/v1/auth/logout", { token: account.agent.token })).status).toBe(204);
    const again = await loginDevice(app, account, "agent", account.agent.publicKey);
    expect(again.deviceId).toBe(account.agent.deviceId);
    const after = await connect(app, again.token);
    await after.expectSilence();
  });

  it("still logs the agent out (204) if purging its queue afterward throws, logging metadata only", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const throwing = makeApp({
      hubs: fakeHubs({
        notifyPairingRemoved: async () => {},
        purgeAgent: async () => {
          throw new Error("hub is down");
        },
      }),
    });
    const lines: string[] = [];
    const spy = vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    });
    const res = await call(throwing, "POST", "/v1/auth/logout", { token: account.agent.token });
    spy.mockRestore();

    expect(res.status).toBe(204);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(401);
    const output = lines.join("\n");
    expect(output).toContain("agent_purge_failed");
    expect(output).not.toContain("hub is down");
  });
});

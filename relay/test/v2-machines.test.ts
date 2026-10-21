import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import { call, db, errorCode, loginDesktop, makeApp, randomPublicKey, registerAccount, registerMachine } from "./helpers.js";

const T0 = 1_760_000_000_500;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

interface Listed {
  machine_id: string; name: string; platform: string; online: boolean; last_seen_unix: number | null; fingerprint: string;
}
async function list(app: ReturnType<typeof makeApp>, token: string): Promise<Listed[]> {
  const res = await call(app, "GET", "/v2/machines", { token });
  expect(res.status).toBe(200);
  return (await res.json<{ machines: Listed[] }>()).machines;
}

describe("POST /v2/machines", () => {
  it("registers once per device and refreshes on a second call", async () => {
    const app = makeApp();
    const desktop = await loginDesktop(app, await registerAccount(app));
    const body = { name: "Mac-Studio", platform: "macos", os_version: "15.2", app_version: "1.0.0", noise_public_key_b64: randomPublicKey() };
    const first = await call(app, "POST", "/v2/machines", { token: desktop.token, body });
    expect(first.status).toBe(201);
    const a = await first.json<{ machine_id: string; slot: string }>();
    expect(a.machine_id).toMatch(UUID_RE);
    expect(a.slot).toMatch(/^[A-Za-z0-9_-]{22}$/);

    const second = await call(app, "POST", "/v2/machines", { token: desktop.token, body: { ...body, name: "  Renamed ", app_version: "1.0.1" } });
    expect(second.status).toBe(200);
    expect(await second.json()).toEqual(a);
    const machines = await list(app, desktop.token);
    expect(machines).toHaveLength(1);
    expect(machines[0]!.name).toBe("Renamed");
    expect(db().get("SELECT app_version FROM machines WHERE id = ?", a.machine_id)).toEqual({ app_version: "1.0.1" });
  });

  it("a new key changes the fingerprint, drops grants and expires pending pairings", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const one = await loginDesktop(app, account);
    const two = await loginDesktop(app, account);
    const m1 = await registerMachine(app, one.token);
    const m2 = await registerMachine(app, two.token);
    const before = (await list(app, one.token)).find((m) => m.machine_id === m1.machine_id)!.fingerprint;
    const now = Date.now();
    db().run("INSERT INTO machine_grants (from_machine_id, to_machine_id, pairing_id, created_at) VALUES (?, ?, ?, ?)", m2.machine_id, m1.machine_id, "p", now);
    for (const [from, to] of [[m2.machine_id, m1.machine_id], [m1.machine_id, m2.machine_id]] as const) {
      db().run(
        `INSERT INTO machine_pairings (id, user_id, from_machine_id, to_machine_id, requester_x25519, requester_fingerprint, code, status, created_at)
         VALUES (?, ?, ?, ?, ?, 'f', '123456', 'pending', ?)`,
        crypto.randomUUID(), account.agent.userId, from, to, Buffer.alloc(32), now,
      );
    }
    const res = await call(app, "POST", "/v2/machines", {
      token: one.token,
      body: { name: "Mac-Studio", platform: "macos", os_version: "15.2", app_version: "1.0.0", noise_public_key_b64: randomPublicKey() },
    });
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ machine_id: m1.machine_id, slot: m1.slot });
    expect((await list(app, one.token)).find((m) => m.machine_id === m1.machine_id)!.fingerprint).not.toBe(before);
    expect(db().all("SELECT * FROM machine_grants")).toEqual([]);
    expect(db().all("SELECT status FROM machine_pairings")).toEqual([{ status: "expired" }, { status: "expired" }]);
  });

  it("is desktop-only and needs a token", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const body = { name: "x", platform: "macos", os_version: "15.2", app_version: "1.0.0", noise_public_key_b64: randomPublicKey() };
    const agent = await call(app, "POST", "/v2/machines", { token: account.agent.token, body });
    expect(agent.status).toBe(403);
    expect(await errorCode(agent)).toBe("desktop_only");
    expect((await call(app, "POST", "/v2/machines", { body })).status).toBe(401);
  });

  it.each([
    ["empty name", { name: "   " }],
    ["long name", { name: "x".repeat(101) }],
    ["non-string name", { name: 5 }],
    ["linux", { platform: "linux" }],
    ["os_version letters", { os_version: "15.x" }],
    ["os_version 5 parts", { os_version: "1.2.3.4.5" }],
    ["app_version two parts", { app_version: "1.0" }],
    ["app_version suffix", { app_version: "1.0.0-beta" }],
    ["short key", { noise_public_key_b64: Buffer.alloc(31).toString("base64url") }],
    ["bad base64", { noise_public_key_b64: "!!!" }],
  ])("rejects %s with invalid_machine", async (_label, override) => {
    const app = makeApp();
    const desktop = await loginDesktop(app, await registerAccount(app));
    const body = { name: "Mac", platform: "macos", os_version: "15.2", app_version: "1.0.0", noise_public_key_b64: randomPublicKey(), ...override };
    const res = await call(app, "POST", "/v2/machines", { token: desktop.token, body });
    expect(res.status).toBe(400);
    expect(await errorCode(res)).toBe("invalid_machine");
  });
});

describe("GET /v2/machines", () => {
  it("lists the account's machines only, with fingerprint and no slot or key", async () => {
    const app = makeApp();
    const a = await loginDesktop(app, await registerAccount(app));
    const b = await loginDesktop(app, await registerAccount(app));
    const ma = await registerMachine(app, a.token);
    await registerMachine(app, b.token);
    const res = await call(app, "GET", "/v2/machines", { token: a.token });
    const text = await res.text();
    expect(text).not.toContain(ma.slot);
    expect(text).not.toContain("slot");
    const machines = JSON.parse(text).machines as Listed[];
    expect(machines).toEqual([{
      machine_id: ma.machine_id, name: "Mac-Studio", platform: "macos", online: false, last_seen_unix: null,
      fingerprint: createHash("sha256").update(Buffer.from(ma.noiseKey, "base64url")).digest("hex").slice(0, 16),
    }]);
  });

  it("only shows machines whose device holds a live token", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const one = await loginDesktop(app, account);
    const two = await loginDesktop(app, account);
    await registerMachine(app, one.token);
    const m2 = await registerMachine(app, two.token);
    db().run("DELETE FROM tokens WHERE device_id = ?", two.deviceId);
    const machines = await list(app, one.token);
    expect(machines.map((m) => m.machine_id)).not.toContain(m2.machine_id);
    expect(machines).toHaveLength(1);
  });
});

describe("heartbeat", () => {
  it("is online for 90 s after the last heartbeat", async () => {
    let clock = T0 - 1000;
    const app = makeApp({ now: () => clock });
    const desktop = await loginDesktop(app, await registerAccount(app));
    const m = await registerMachine(app, desktop.token);
    clock = T0;
    expect((await call(app, "POST", `/v2/machines/${m.machine_id}/heartbeat`, { token: desktop.token })).status).toBe(204);
    clock = T0 + 90_000;
    expect(await list(app, desktop.token)).toMatchObject([{ online: true, last_seen_unix: 1_760_000_000 }]);
    clock = T0 + 90_001;
    expect(await list(app, desktop.token)).toMatchObject([{ online: false, last_seen_unix: 1_760_000_000 }]);
  });

  it("is owner only; other accounts and bad ids get 404", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const one = await loginDesktop(app, account);
    const two = await loginDesktop(app, account);
    const other = await loginDesktop(app, await registerAccount(app));
    const m2 = await registerMachine(app, two.token);
    const mo = await registerMachine(app, other.token);
    const beat = (id: string) => call(app, "POST", `/v2/machines/${id}/heartbeat`, { token: one.token });
    const same = await beat(m2.machine_id);
    expect(same.status).toBe(403);
    expect(await errorCode(same)).toBe("forbidden");
    const foreign = await beat(mo.machine_id);
    expect(foreign.status).toBe(404);
    expect(await errorCode(foreign)).toBe("machine_not_found");
    expect((await beat("not-a-uuid")).status).toBe(404);
    expect((await beat(crypto.randomUUID())).status).toBe(404);
  });
});

describe("DELETE /v2/machines/:id", () => {
  it("deletes own machine and its grants, any same-account machine, never another account's", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const one = await loginDesktop(app, account);
    const two = await loginDesktop(app, account);
    const other = await loginDesktop(app, await registerAccount(app));
    const m1 = await registerMachine(app, one.token);
    const m2 = await registerMachine(app, two.token);
    const mo = await registerMachine(app, other.token);
    db().run("INSERT INTO machine_grants (from_machine_id, to_machine_id, pairing_id, created_at) VALUES (?, ?, 'p', ?)", m2.machine_id, m1.machine_id, Date.now());

    const foreign = await call(app, "DELETE", `/v2/machines/${mo.machine_id}`, { token: one.token });
    expect(foreign.status).toBe(404);
    expect(await errorCode(foreign)).toBe("machine_not_found");

    expect((await call(app, "DELETE", `/v2/machines/${m1.machine_id}`, { token: one.token })).status).toBe(204);
    expect(db().all("SELECT * FROM machine_grants")).toEqual([]);
    expect((await call(app, "DELETE", `/v2/machines/${m2.machine_id}`, { token: one.token })).status).toBe(204);
    expect(db().get("SELECT 1 AS x FROM machines WHERE id = ?", mo.machine_id)).toEqual({ x: 1 });
  });
});

describe("sign-out", () => {
  it("desktop logout deletes its machine", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const one = await loginDesktop(app, account);
    const two = await loginDesktop(app, account);
    const m1 = await registerMachine(app, one.token);
    await registerMachine(app, two.token);
    expect((await call(app, "POST", "/v1/auth/logout", { token: one.token })).status).toBe(204);
    expect(db().get("SELECT 1 FROM machines WHERE id = ?", m1.machine_id)).toBeUndefined();
    expect(await list(app, two.token)).toHaveLength(1);
  });

  it("an agent password change removes the other desktops from the list", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const desktop = await loginDesktop(app, account);
    const m = await registerMachine(app, desktop.token);
    const res = await call(app, "POST", "/v1/auth/password", { token: account.agent.token, body: { new_password: "another long password" } });
    expect(res.status).toBe(204);
    const again = await loginDesktop(app, { ...account, password: "another long password" });
    await registerMachine(app, again.token);
    const ids = (await list(app, again.token)).map((x) => x.machine_id);
    expect(ids).not.toContain(m.machine_id);
  });
});

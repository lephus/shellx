import { describe, expect, it } from "vitest";
import { MAX_PENDING_PER_TARGET, PAIRING_TTL_MS } from "../src/v2/pairings.js";
import {
  call, CountingLimiter, db, errorCode, loginDesktop, loginDevice, makeApp, registerAccount,
  registerMachine, unlimited, type Session, type TestApp,
} from "./helpers.js";

const T0 = 1_760_000_000_500;

interface Desk { session: Session; machineId: string; linkSlot: string; fingerprint: string }

/** Account 1: desktops A (target) and B (other), phone P; account 2: desktop D and phone Q. */
async function setup(app: TestApp) {
  const account = await registerAccount(app);
  const desk = async (acc = account): Promise<Desk> => {
    const session = await loginDesktop(app, acc);
    const m = await registerMachine(app, session.token);
    const row = db().get<{ fingerprint: string }>("SELECT fingerprint FROM machines WHERE id = ?", m.machine_id)!;
    return { session, machineId: m.machine_id, linkSlot: m.link_slot, fingerprint: row.fingerprint };
  };
  const a = await desk();
  const b = await desk();
  const phone = await loginDevice(app, account, "mobile");
  const other = await registerAccount(app);
  const d = await desk(other);
  const foreignPhone = await loginDevice(app, other, "mobile");
  return { account, a, b, d, phone, foreignPhone, newPhone: () => loginDevice(app, account, "mobile") };
}

function standardB64(bytes = 32): string {
  return Buffer.from(crypto.getRandomValues(new Uint8Array(bytes))).toString("base64");
}

function request(app: TestApp, token: string, machineId: string, body: Record<string, unknown> = {}) {
  return call(app, "POST", "/v2/phone-pairings", {
    token, body: { machine_id: machineId, client_key_b64: standardB64(), proof_b64: standardB64(), ...body },
  });
}

async function created(app: TestApp, token: string, machineId: string, body: Record<string, unknown> = {}): Promise<string> {
  const res = await request(app, token, machineId, body);
  expect(res.status).toBe(201);
  return (await res.json<{ pairing_id: string }>()).pairing_id;
}

function approve(app: TestApp, token: string, id: string) {
  return call(app, "POST", `/v2/phone-pairings/${id}/approve`, { token });
}

function mint(app: TestApp, token: string, body: Record<string, unknown>) {
  return call(app, "POST", "/v2/relay/tickets", { token, body });
}

function claimsOf(ticket: string): Record<string, unknown> {
  return JSON.parse(Buffer.from(ticket.split(".")[1]!, "base64url").toString("utf8")) as Record<string, unknown>;
}

describe("creating a request", () => {
  it("lets a phone ask a machine of its account", async () => {
    const app = makeApp({ now: () => T0 });
    const { a, phone } = await setup(app);
    const res = await request(app, phone.token, a.machineId);
    expect(res.status).toBe(201);
    const body = await res.json<{ pairing_id: string }>();
    expect(Object.keys(body)).toEqual(["pairing_id"]);
    const state = await call(app, "GET", `/v2/phone-pairings/${body.pairing_id}`, { token: phone.token });
    expect(state.status).toBe(200);
    expect(await state.json()).toEqual({ status: "pending" });
  });

  it("normalizes the proof to standard base64 and accepts URL-alphabet input", async () => {
    const app = makeApp({ now: () => T0 });
    const { a, phone } = await setup(app);
    const bytes = new Uint8Array(32).fill(0xfb); // encodes with + and / in the standard alphabet
    const url = Buffer.from(bytes).toString("base64url");
    const id = await created(app, phone.token, a.machineId, { proof_b64: url, client_key_b64: url });
    const row = db().get<{ proof: string; client_key: Buffer }>("SELECT proof, client_key FROM phone_pairings WHERE id = ?", id)!;
    expect(row.proof).toBe(Buffer.from(bytes).toString("base64"));
    expect(Buffer.from(row.client_key).equals(Buffer.from(bytes))).toBe(true);
  });

  it("rejects keys and proofs that are not 32 bytes", async () => {
    const app = makeApp({ now: () => T0 });
    const { a, phone } = await setup(app);
    expect((await request(app, phone.token, a.machineId, { client_key_b64: standardB64(31) })).status).toBe(400);
    expect((await request(app, phone.token, a.machineId, { proof_b64: standardB64(33) })).status).toBe(400);
    expect((await request(app, phone.token, a.machineId, { proof_b64: 5 })).status).toBe(400);
  });

  it("answers machine_not_found for another account's machine", async () => {
    const app = makeApp({ now: () => T0 });
    const { d, phone } = await setup(app);
    const res = await request(app, phone.token, d.machineId);
    expect(res.status).toBe(404);
    expect(await errorCode(res)).toBe("machine_not_found");
    expect(db().get("SELECT COUNT(*) AS n FROM phone_pairings")).toEqual({ n: 0 });
  });

  it("refuses a desktop token with mobile_only and no token with 401", async () => {
    const app = makeApp({ now: () => T0 });
    const { a, b } = await setup(app);
    const res = await request(app, b.session.token, a.machineId);
    expect(res.status).toBe(403);
    expect(await errorCode(res)).toBe("mobile_only");
    expect((await call(app, "POST", "/v2/phone-pairings", { body: {} })).status).toBe(401);
  });

  it("supersedes an older pending request of the same phone to the same machine", async () => {
    const app = makeApp({ now: () => T0 });
    const { a, b, phone } = await setup(app);
    const first = await created(app, phone.token, a.machineId);
    const elsewhere = await created(app, phone.token, b.machineId);
    const second = await created(app, phone.token, a.machineId);
    const status = async (id: string) => (await (await call(app, "GET", `/v2/phone-pairings/${id}`, { token: phone.token })).json<{ status: string }>()).status;
    expect(await status(first)).toBe("expired");
    expect(await status(second)).toBe("pending");
    expect(await status(elsewhere)).toBe("pending");
  });

  it("caps live pending requests per machine and rolls the supersede back", async () => {
    const app = makeApp({ now: () => T0 });
    const { a, newPhone } = await setup(app);
    const phones: Session[] = [];
    for (let i = 0; i < MAX_PENDING_PER_TARGET; i++) {
      const p = await newPhone();
      phones.push(p);
      await created(app, p.token, a.machineId);
    }
    const extra = await newPhone();
    const refused = await request(app, extra.token, a.machineId);
    expect(refused.status).toBe(429);
    expect(await errorCode(refused)).toBe("rate_limited");
    // a phone already pending may renew
    await created(app, phones[0]!.token, a.machineId);
  });

  it("rate limits per device", async () => {
    const limiter = new CountingLimiter(1);
    const app = makeApp({ now: () => T0, limiters: { ...unlimited, pairingCreate: limiter } });
    const { a, phone } = await setup(app);
    expect((await request(app, phone.token, a.machineId)).status).toBe(201);
    const second = await request(app, phone.token, a.machineId);
    expect(second.status).toBe(429);
    expect(limiter.calls).toEqual([phone.deviceId, phone.deviceId]);
  });
});

describe("the target machine", () => {
  it("lists pending requests with the phone's name, key and proof", async () => {
    const app = makeApp({ now: () => T0 });
    const { a, b, phone } = await setup(app);
    const key = standardB64();
    const proof = standardB64();
    const id = await created(app, phone.token, a.machineId, { client_key_b64: key, proof_b64: proof });
    await created(app, phone.token, b.machineId);
    const res = await call(app, "GET", "/v2/phone-pairings?role=target", { token: a.session.token });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      pairings: [{
        pairing_id: id, device_name: "iPhone 16", platform: "ios", client_key_b64: key, proof_b64: proof,
        created_at_unix: Math.floor(T0 / 1000), links_apple_id: false,
      }],
    });
  });

  it("hides decided and expired requests", async () => {
    let now = T0;
    const app = makeApp({ now: () => now });
    const { a, newPhone } = await setup(app);
    const p1 = await newPhone();
    const p2 = await newPhone();
    await created(app, p1.token, a.machineId);
    now += PAIRING_TTL_MS + 1;
    const fresh = await created(app, p2.token, a.machineId);
    const list = async () => (await (await call(app, "GET", "/v2/phone-pairings?role=target", { token: a.session.token })).json<{ pairings: { pairing_id: string }[] }>()).pairings.map((p) => p.pairing_id);
    expect(await list()).toEqual([fresh]);
    expect((await approve(app, a.session.token, fresh)).status).toBe(204);
    expect(await list()).toEqual([]);
  });

  it("is refused for a mobile token and without a role", async () => {
    const app = makeApp({ now: () => T0 });
    const { a, phone } = await setup(app);
    const asPhone = await call(app, "GET", "/v2/phone-pairings?role=target", { token: phone.token });
    expect(asPhone.status).toBe(403);
    expect(await errorCode(asPhone)).toBe("desktop_only");
    expect((await call(app, "GET", "/v2/phone-pairings", { token: a.session.token })).status).toBe(400);
  });

  it("approves: a grant exists and the phone sees the machine with its link_slot", async () => {
    const app = makeApp({ now: () => T0 });
    const { a, phone } = await setup(app);
    const id = await created(app, phone.token, a.machineId);
    expect((await approve(app, a.session.token, id)).status).toBe(204);
    const state = await call(app, "GET", `/v2/phone-pairings/${id}`, { token: phone.token });
    expect(await state.json()).toEqual({
      status: "approved", machine: { machine_id: a.machineId, name: "Mac-Studio", link_slot: a.linkSlot },
    });
    expect(db().all("SELECT device_id, machine_id, pairing_id FROM phone_grants")).toEqual([
      { device_id: phone.deviceId, machine_id: a.machineId, pairing_id: id },
    ]);
  });

  it("re-approving after a new request upserts the grant (one row)", async () => {
    const app = makeApp({ now: () => T0 });
    const { a, phone } = await setup(app);
    await approve(app, a.session.token, await created(app, phone.token, a.machineId));
    const second = await created(app, phone.token, a.machineId);
    await approve(app, a.session.token, second);
    expect(db().all("SELECT pairing_id FROM phone_grants")).toEqual([{ pairing_id: second }]);
  });

  it("refuses a mobile approver, another desktop of the account and another account's desktop", async () => {
    const app = makeApp({ now: () => T0 });
    const { a, b, d, phone } = await setup(app);
    const id = await created(app, phone.token, a.machineId);
    const byPhone = await approve(app, phone.token, id);
    expect(byPhone.status).toBe(403);
    expect(await errorCode(byPhone)).toBe("desktop_only");
    const byB = await approve(app, b.session.token, id);
    expect(byB.status).toBe(403);
    expect(await errorCode(byB)).toBe("forbidden");
    const byD = await approve(app, d.session.token, id);
    expect(byD.status).toBe(404);
    expect(await errorCode(byD)).toBe("pairing_not_found");
    expect(db().get("SELECT COUNT(*) AS n FROM phone_grants")).toEqual({ n: 0 });
  });

  it("expires a request after 5 minutes", async () => {
    let now = T0;
    const app = makeApp({ now: () => now });
    const { a, phone } = await setup(app);
    const id = await created(app, phone.token, a.machineId);
    now += PAIRING_TTL_MS + 1;
    const late = await approve(app, a.session.token, id);
    expect(late.status).toBe(410);
    expect(await errorCode(late)).toBe("pairing_expired");
    const state = await call(app, "GET", `/v2/phone-pairings/${id}`, { token: phone.token });
    expect(await state.json()).toEqual({ status: "expired" });
  });

  it("makes a second approval and an approval after deny fail with pairing_not_pending", async () => {
    const app = makeApp({ now: () => T0 });
    const { a, phone } = await setup(app);
    const id = await created(app, phone.token, a.machineId);
    expect((await approve(app, a.session.token, id)).status).toBe(204);
    const again = await approve(app, a.session.token, id);
    expect(again.status).toBe(409);
    expect(await errorCode(again)).toBe("pairing_not_pending");
    const id2 = await created(app, phone.token, a.machineId);
    expect((await call(app, "POST", `/v2/phone-pairings/${id2}/deny`, { token: a.session.token })).status).toBe(204);
    expect((await approve(app, a.session.token, id2)).status).toBe(409);
  });
});

describe("deny and the phone's view", () => {
  it("lets the target machine or the sending phone deny, nobody else", async () => {
    const app = makeApp({ now: () => T0 });
    const { a, b, phone, foreignPhone, newPhone } = await setup(app);
    const deny = (token: string, id: string) => call(app, "POST", `/v2/phone-pairings/${id}/deny`, { token });
    const id = await created(app, phone.token, a.machineId);
    expect((await deny(b.session.token, id)).status).toBe(403);
    expect((await deny(foreignPhone.token, id)).status).toBe(404);
    const sibling = await newPhone();
    expect((await deny(sibling.token, id)).status).toBe(403);
    expect((await deny(phone.token, id)).status).toBe(204);
    expect((await deny(phone.token, id)).status).toBe(204); // idempotent
    const state = await call(app, "GET", `/v2/phone-pairings/${id}`, { token: phone.token });
    expect(await state.json()).toEqual({ status: "denied" });
    const id2 = await created(app, phone.token, a.machineId);
    expect((await deny(a.session.token, id2)).status).toBe(204);
    expect((await approve(app, a.session.token, id2)).status).toBe(409);
  });

  it("shows a request only to the phone that sent it", async () => {
    const app = makeApp({ now: () => T0 });
    const { a, phone, foreignPhone, newPhone } = await setup(app);
    const id = await created(app, phone.token, a.machineId);
    expect((await call(app, "GET", `/v2/phone-pairings/${id}`, { token: foreignPhone.token })).status).toBe(404);
    const sibling = await newPhone();
    expect((await call(app, "GET", `/v2/phone-pairings/${id}`, { token: sibling.token })).status).toBe(404);
    expect((await call(app, "GET", `/v2/phone-pairings/${id}`, { token: a.session.token })).status).toBe(403);
  });
});

describe("grants", () => {
  async function granted() {
    const app = makeApp({ now: () => T0 });
    const s = await setup(app);
    const id = await created(app, s.phone.token, s.a.machineId);
    await approve(app, s.a.session.token, id);
    const grantId = db().get<{ id: string }>("SELECT id FROM phone_grants")!.id;
    return { app, ...s, grantId };
  }

  it("lists a phone's grants with machine details", async () => {
    const { app, a, phone, grantId } = await granted();
    db().run("UPDATE machines SET last_seen_at = ? WHERE id = ?", T0 - 1000, a.machineId);
    const res = await call(app, "GET", "/v2/phone-grants", { token: phone.token });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      grants: [{
        grant_id: grantId, machine_id: a.machineId, name: "Mac-Studio", platform: "macos", online: true,
        link_slot: a.linkSlot, fingerprint: a.fingerprint,
      }],
    });
  });

  it("lists a machine's grants for its desktop only", async () => {
    const { app, a, b, phone, grantId } = await granted();
    db().run("UPDATE devices SET last_seen_at = ? WHERE id = ?", T0 - 5000, phone.deviceId);
    const key = db().get<{ client_key: Buffer }>("SELECT client_key FROM phone_grants")!.client_key;
    const res = await call(app, "GET", "/v2/phone-grants", { token: a.session.token });
    expect(await res.json()).toEqual({
      grants: [{
        grant_id: grantId, device_id: phone.deviceId, device_name: "iPhone 16", platform: "ios",
        client_key_b64: Buffer.from(key).toString("base64"), created_at_unix: Math.floor(T0 / 1000),
        last_seen_unix: Math.floor((T0 - 5000) / 1000),
      }],
    });
    expect(await (await call(app, "GET", "/v2/phone-grants", { token: b.session.token })).json()).toEqual({ grants: [] });
  });

  it("refuses an agent token", async () => {
    const { app, account } = await granted();
    const agent = await loginDevice(app, account, "agent");
    expect((await call(app, "GET", "/v2/phone-grants", { token: agent.token })).status).toBe(403);
  });

  it("is removed by the phone or by the machine, and then tickets are refused", async () => {
    for (const by of ["phone", "machine"] as const) {
      const { app, a, phone, grantId } = await granted();
      const token = by === "phone" ? phone.token : a.session.token;
      expect((await call(app, "DELETE", `/v2/phone-grants/${grantId}`, { token })).status).toBe(204);
      const res = await mint(app, phone.token, { permission: "connect", lane: "link", target_machine_id: a.machineId });
      expect(res.status).toBe(403);
      expect(await errorCode(res)).toBe("not_granted");
      expect(db().get("SELECT COUNT(*) AS n FROM phone_grants")).toEqual({ n: 0 });
      db().run("DELETE FROM users"); // fresh state for the next round
    }
  });

  it("is not removable by other devices", async () => {
    const { app, b, d, foreignPhone, grantId, newPhone } = await granted();
    const sibling = await newPhone();
    for (const t of [b.session.token, d.session.token, foreignPhone.token, sibling.token]) {
      const res = await call(app, "DELETE", `/v2/phone-grants/${grantId}`, { token: t });
      expect([403, 404]).toContain(res.status);
    }
    expect(db().get("SELECT COUNT(*) AS n FROM phone_grants")).toEqual({ n: 1 });
    expect((await call(app, "DELETE", "/v2/phone-grants/not-a-uuid", { token: b.session.token })).status).toBe(404);
  });
});

describe("tickets for a phone", () => {
  it("mints a client ticket for the target's link_slot", async () => {
    const app = makeApp({ now: () => T0 });
    const { a, phone } = await setup(app);
    await approve(app, a.session.token, await created(app, phone.token, a.machineId));
    const res = await mint(app, phone.token, { permission: "connect", lane: "link", target_machine_id: a.machineId });
    expect(res.status).toBe(200);
    const body = await res.json<{ ticket: string; expires_at_unix: number; relay_url: string }>();
    expect(body.expires_at_unix).toBe(Math.floor(T0 / 1000) + 120);
    expect(claimsOf(body.ticket)).toMatchObject({ permission: "connect", role: "client", slot: a.linkSlot });
  });

  it("answers not_granted without a grant and machine_not_found for another account's machine", async () => {
    const app = makeApp({ now: () => T0 });
    const { a, d, phone } = await setup(app);
    const none = await mint(app, phone.token, { permission: "connect", lane: "link", target_machine_id: a.machineId });
    expect(none.status).toBe(403);
    expect(await errorCode(none)).toBe("not_granted");
    const foreign = await mint(app, phone.token, { permission: "connect", lane: "link", target_machine_id: d.machineId });
    expect(foreign.status).toBe(404);
    expect(await errorCode(foreign)).toBe("machine_not_found");
  });

  it("refuses register (403), a missing lane (400) and a missing target (400)", async () => {
    const app = makeApp({ now: () => T0 });
    const { a, phone } = await setup(app);
    await approve(app, a.session.token, await created(app, phone.token, a.machineId));
    expect((await mint(app, phone.token, { permission: "register", lane: "link", machine_id: a.machineId })).status).toBe(403);
    expect((await mint(app, phone.token, { permission: "connect", target_machine_id: a.machineId })).status).toBe(400);
    expect((await mint(app, phone.token, { permission: "connect", lane: "link" })).status).toBe(400);
  });

  it("does not let a grant of one phone serve a sibling phone", async () => {
    const app = makeApp({ now: () => T0 });
    const { a, phone, newPhone } = await setup(app);
    await approve(app, a.session.token, await created(app, phone.token, a.machineId));
    const sibling = await newPhone();
    const res = await mint(app, sibling.token, { permission: "connect", lane: "link", target_machine_id: a.machineId });
    expect(await errorCode(res)).toBe("not_granted");
  });
});

describe("mobile tokens elsewhere", () => {
  it("still get desktop_only on the machine, pairing and share routes", async () => {
    const app = makeApp({ now: () => T0 });
    const { a, phone } = await setup(app);
    for (const [path, body] of [
      ["/v2/machines", { name: "x" }],
      ["/v2/pairings", { from_machine_id: a.machineId, to_machine_id: a.machineId }],
      ["/v2/shares", {}],
    ] as const) {
      const res = await call(app, "POST", path, { token: phone.token, body });
      expect(res.status).toBe(403);
      expect(await errorCode(res)).toBe("desktop_only");
    }
  });
});

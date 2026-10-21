import { describe, expect, it } from "vitest";
import {
  hasGrant, MAX_PENDING_PER_TARGET, PAIRING_TTL_MS, PAIRING_VISIBLE_MS, SEALED_INVITE_MAX_BYTES,
} from "../src/v2/pairings.js";
import {
  approvePairing, call, db, errorCode, loginDesktop, makeApp, randomPublicKey, randomSealedInvite, registerAccount,
  registerMachine, requestPairing, type Session, type TestApp,
} from "./helpers.js";

const T0 = 1_760_000_000_500;

interface Item {
  pairing_id: string; from_machine_id: string; to_machine_id: string; requester_fingerprint: string;
  requester_x25519_b64?: string; code: string; status: string; sealed_invite_b64?: string;
}

interface Desk { session: Session; machineId: string; fingerprint: string; noiseKey: string }

/** Account 1 with desktops A (requester), B (target) and C (third machine); account 2 with desktop D. */
async function setup(app: TestApp) {
  const account = await registerAccount(app);
  const desk = async (acc = account): Promise<Desk> => {
    const session = await loginDesktop(app, acc);
    const { machine_id, noiseKey } = await registerMachine(app, session.token);
    const row = db().get<{ fingerprint: string }>("SELECT fingerprint FROM machines WHERE id = ?", machine_id)!;
    return { session, machineId: machine_id, fingerprint: row.fingerprint, noiseKey };
  };
  const a = await desk();
  const b = await desk();
  const c = await desk();
  const d = await desk(await registerAccount(app));
  return { account, a, b, c, d, desk };
}

async function list(app: TestApp, token: string, role: "target" | "requester"): Promise<Item[]> {
  const res = await call(app, "GET", `/v2/pairings?role=${role}`, { token });
  expect(res.status).toBe(200);
  return (await res.json<{ pairings: Item[] }>()).pairings;
}

function post(app: TestApp, token: string, body: Record<string, unknown>) {
  return call(app, "POST", "/v2/pairings", { token, body });
}

function approve(app: TestApp, token: string, id: string, sealed: unknown = randomSealedInvite()) {
  return call(app, "POST", `/v2/pairings/${id}/approve`, { token, body: { sealed_invite_b64: sealed } });
}

function deny(app: TestApp, token: string, id: string) {
  return call(app, "POST", `/v2/pairings/${id}/deny`, { token });
}

function grantRows(): unknown[] {
  return db().all("SELECT from_machine_id, to_machine_id, pairing_id FROM machine_grants");
}

it("exports the K1 limits", () => {
  expect([PAIRING_TTL_MS, PAIRING_VISIBLE_MS, MAX_PENDING_PER_TARGET, SEALED_INVITE_MAX_BYTES]).toEqual([300_000, 600_000, 10, 8192]);
});

describe("happy path", () => {
  it("A requests B, B sees the code and fingerprint, approves, A gets the sealed invite verbatim", async () => {
    const app = makeApp();
    const { a, b } = await setup(app);
    const x25519 = a.noiseKey; // URL alphabet, no padding
    const res = await post(app, a.session.token, { from_machine_id: a.machineId, to_machine_id: b.machineId, requester_x25519_b64: x25519 });
    expect(res.status).toBe(201);
    const created = await res.json<{ pairing_id: string; code: string }>();
    expect(Object.keys(created).sort()).toEqual(["code", "pairing_id"]);
    expect(created.code).toMatch(/^\d{6}$/);

    const target = await list(app, b.session.token, "target");
    expect(target).toHaveLength(1);
    expect(target[0]).toEqual({
      pairing_id: created.pairing_id, from_machine_id: a.machineId, to_machine_id: b.machineId,
      requester_fingerprint: a.fingerprint, requester_x25519_b64: Buffer.from(x25519, "base64url").toString("base64"),
      code: created.code, status: "pending",
    });
    expect(target[0]).not.toHaveProperty("sealed_invite_b64");
    expect(await list(app, b.session.token, "requester")).toEqual([]);
    expect(await list(app, a.session.token, "target")).toEqual([]);

    const sealed = randomSealedInvite(200);
    expect(sealed).toMatch(/^[A-Za-z0-9+/]+={0,2}$/); // standard alphabet, padded
    expect((await approve(app, b.session.token, created.pairing_id, sealed)).status).toBe(204);

    const mine = await list(app, a.session.token, "requester");
    expect(mine).toHaveLength(1);
    expect(mine[0]!.status).toBe("approved");
    expect(mine[0]!.sealed_invite_b64).toBe(sealed);
    expect(mine[0]!.code).toBe(created.code);
    // the target never gets the invite back
    expect((await list(app, b.session.token, "target"))[0]).not.toHaveProperty("sealed_invite_b64");

    expect(hasGrant(db(), a.machineId, b.machineId)).toBe(true);
    expect(hasGrant(db(), b.machineId, a.machineId)).toBe(false);
    expect(grantRows()).toEqual([{ from_machine_id: a.machineId, to_machine_id: b.machineId, pairing_id: created.pairing_id }]);
  });

  it("returns a URL-alphabet invite byte-identical too", async () => {
    const app = makeApp();
    const { a, b } = await setup(app);
    const { pairing_id } = await requestPairing(app, a.session.token, a.machineId, b.machineId);
    const sealed = Buffer.from(crypto.getRandomValues(new Uint8Array(61))).toString("base64url");
    await approvePairing(app, b.session.token, pairing_id, sealed);
    expect((await list(app, a.session.token, "requester"))[0]!.sealed_invite_b64).toBe(sealed);
  });

  it("is desktop-only and needs a token", async () => {
    const app = makeApp();
    const { account, a, b } = await setup(app);
    const agent = await post(app, account.agent.token, { from_machine_id: a.machineId, to_machine_id: b.machineId, requester_x25519_b64: a.noiseKey });
    expect(agent.status).toBe(403);
    expect(await errorCode(agent)).toBe("desktop_only");
    expect((await call(app, "GET", "/v2/pairings?role=target")).status).toBe(401);
    expect((await call(app, "GET", "/v2/pairings?role=target", { token: account.agent.token })).status).toBe(403);
    const { pairing_id } = await requestPairing(app, a.session.token, a.machineId, b.machineId);
    expect((await approve(app, account.agent.token, pairing_id)).status).toBe(403);
    expect((await call(app, "POST", `/v2/pairings/${pairing_id}/approve`, { body: { sealed_invite_b64: randomSealedInvite() } })).status).toBe(401);
    expect((await deny(app, account.agent.token, pairing_id)).status).toBe(403);
  });

  it("a desktop with no machine lists nothing", async () => {
    const app = makeApp();
    const { account, a, b } = await setup(app);
    await requestPairing(app, a.session.token, a.machineId, b.machineId);
    const bare = await loginDesktop(app, account);
    expect(await list(app, bare.token, "target")).toEqual([]);
    expect(await list(app, bare.token, "requester")).toEqual([]);
  });
});

describe("spoofing", () => {
  it("(a) a requester cannot send another machine's id as from_machine_id", async () => {
    const app = makeApp();
    const { a, b, c, d } = await setup(app);
    const same = await post(app, a.session.token, { from_machine_id: c.machineId, to_machine_id: b.machineId, requester_x25519_b64: c.noiseKey });
    expect(same.status).toBe(403);
    expect(await errorCode(same)).toBe("forbidden");
    const foreign = await post(app, a.session.token, { from_machine_id: d.machineId, to_machine_id: b.machineId, requester_x25519_b64: d.noiseKey });
    expect(foreign.status).toBe(404);
    expect(await errorCode(foreign)).toBe("machine_not_found");
    for (const bad of ["not-a-uuid", crypto.randomUUID(), 5, null]) {
      const res = await post(app, a.session.token, { from_machine_id: bad, to_machine_id: b.machineId, requester_x25519_b64: randomPublicKey() });
      expect(res.status).toBe(404);
    }
    expect(db().all("SELECT id FROM machine_pairings")).toEqual([]);
  });

  it("(b) the code and fingerprint come from the server, never from the body", async () => {
    const app = makeApp({ pairingCode: () => "654321" });
    const { a, b } = await setup(app);
    const res = await post(app, a.session.token, {
      from_machine_id: a.machineId, to_machine_id: b.machineId, requester_x25519_b64: a.noiseKey,
      code: "123456", requester_fingerprint: "0".repeat(16), status: "approved",
    });
    expect(res.status).toBe(201);
    const created = await res.json<{ pairing_id: string; code: string }>();
    expect(created.code).toBe("654321");
    expect(db().get("SELECT code, requester_fingerprint, status FROM machine_pairings WHERE id = ?", created.pairing_id)).toEqual({
      code: "654321", requester_fingerprint: a.fingerprint, status: "pending",
    });
    expect(a.fingerprint).not.toBe("0".repeat(16));
    expect(grantRows()).toEqual([]);
  });

  it("(c) only the target approves: not the requester, not a third machine, not another account", async () => {
    const app = makeApp();
    const { account, a, b, c, d } = await setup(app);
    const { pairing_id } = await requestPairing(app, a.session.token, a.machineId, b.machineId);
    const self = await approve(app, a.session.token, pairing_id);
    expect(self.status).toBe(403);
    expect(await errorCode(self)).toBe("forbidden");
    const third = await approve(app, c.session.token, pairing_id);
    expect(third.status).toBe(403);
    expect(await errorCode(third)).toBe("forbidden");
    const foreign = await approve(app, d.session.token, pairing_id);
    expect(foreign.status).toBe(404);
    expect(await errorCode(foreign)).toBe("pairing_not_found");
    const bare = await loginDesktop(app, account); // same account, no machine
    expect((await approve(app, bare.token, pairing_id)).status).toBe(403);
    // the refused attempts left it pending and granted nothing
    expect(db().get("SELECT status, sealed_invite FROM machine_pairings WHERE id = ?", pairing_id)).toEqual({ status: "pending", sealed_invite: null });
    expect(grantRows()).toEqual([]);
    // third machines and other accounts cannot deny either; unknown ids are 404
    expect((await deny(app, c.session.token, pairing_id)).status).toBe(403);
    expect((await deny(app, d.session.token, pairing_id)).status).toBe(404);
    expect((await approve(app, b.session.token, crypto.randomUUID())).status).toBe(404);
    expect((await approve(app, b.session.token, "not-a-uuid")).status).toBe(404);
    expect(await list(app, d.session.token, "target")).toEqual([]);
    expect(await list(app, d.session.token, "requester")).toEqual([]);
  });

  it("(d) a request past 5 minutes cannot be approved and reads expired", async () => {
    let clock = T0;
    const app = makeApp({ now: () => clock });
    const { a, b } = await setup(app);
    const { pairing_id } = await requestPairing(app, a.session.token, a.machineId, b.machineId);
    clock = T0 + 300_001;
    const late = await approve(app, b.session.token, pairing_id);
    expect(late.status).toBe(410);
    expect(await errorCode(late)).toBe("pairing_expired");
    expect((await list(app, b.session.token, "target"))[0]!.status).toBe("expired");
    expect((await list(app, a.session.token, "requester"))[0]!.status).toBe("expired");
    expect(db().get("SELECT status, sealed_invite FROM machine_pairings WHERE id = ?", pairing_id)).toEqual({ status: "expired", sealed_invite: null });
    expect(hasGrant(db(), a.machineId, b.machineId)).toBe(false);
  });

  it("(d') a request at exactly 5 minutes still reads pending and can be approved", async () => {
    let clock = T0;
    const app = makeApp({ now: () => clock });
    const { a, b } = await setup(app);
    const { pairing_id } = await requestPairing(app, a.session.token, a.machineId, b.machineId);
    clock = T0 + 300_000;
    expect((await list(app, b.session.token, "target"))[0]!.status).toBe("pending");
    expect((await approve(app, b.session.token, pairing_id)).status).toBe(204);
  });

  it("(e) an approved request cannot be approved again or denied", async () => {
    const app = makeApp();
    const { a, b } = await setup(app);
    const { pairing_id } = await requestPairing(app, a.session.token, a.machineId, b.machineId);
    const first = await approvePairing(app, b.session.token, pairing_id);
    const again = await approve(app, b.session.token, pairing_id);
    expect(again.status).toBe(409);
    expect(await errorCode(again)).toBe("pairing_not_pending");
    const denied = await deny(app, b.session.token, pairing_id);
    expect(denied.status).toBe(409);
    expect(await errorCode(denied)).toBe("pairing_not_pending");
    expect((await deny(app, a.session.token, pairing_id)).status).toBe(409);
    // the first invite is kept, the grant stays
    expect((await list(app, a.session.token, "requester"))[0]).toMatchObject({ status: "approved", sealed_invite_b64: first });
    expect(hasGrant(db(), a.machineId, b.machineId)).toBe(true);
  });

  it("(f) two pending requests to one target never share a code", async () => {
    const codes = ["111111", "111111", "222222"];
    const app = makeApp({ pairingCode: () => codes.shift()! });
    const { a, b, c } = await setup(app);
    const one = await requestPairing(app, a.session.token, a.machineId, b.machineId);
    const two = await requestPairing(app, c.session.token, c.machineId, b.machineId);
    expect([one.code, two.code]).toEqual(["111111", "222222"]);
    expect(codes).toEqual([]);
    expect((await list(app, b.session.token, "target")).map((p) => p.code).sort()).toEqual(["111111", "222222"]);
  });

  it("(f') a code is reused only once the earlier request is no longer live", async () => {
    let clock = T0;
    const app = makeApp({ now: () => clock, pairingCode: () => "111111" });
    const { a, b, c } = await setup(app);
    await requestPairing(app, a.session.token, a.machineId, b.machineId);
    // still live: every draw collides, the server gives up with 500 and stores nothing
    const stuck = await post(app, c.session.token, { from_machine_id: c.machineId, to_machine_id: b.machineId, requester_x25519_b64: c.noiseKey });
    expect(stuck.status).toBe(500);
    expect(db().all("SELECT id FROM machine_pairings WHERE from_machine_id = ?", c.machineId)).toEqual([]);
    clock = T0 + 300_001;
    expect((await requestPairing(app, c.session.token, c.machineId, b.machineId)).code).toBe("111111");
    // another target may get the same code at the same time
    expect((await requestPairing(app, a.session.token, a.machineId, c.machineId)).code).toBe("111111");
  });

  it("(g) the 11th live pending request to one target is refused with 429", async () => {
    const app = makeApp();
    const { account, b, desk } = await setup(app);
    const requesters: Desk[] = [];
    for (let i = 0; i < MAX_PENDING_PER_TARGET + 1; i++) requesters.push(await desk(account));
    for (const r of requesters.slice(0, MAX_PENDING_PER_TARGET)) await requestPairing(app, r.session.token, r.machineId, b.machineId);
    const last = requesters[MAX_PENDING_PER_TARGET]!;
    const refused = await post(app, last.session.token, { from_machine_id: last.machineId, to_machine_id: b.machineId, requester_x25519_b64: last.noiseKey });
    expect(refused.status).toBe(429);
    expect(await errorCode(refused)).toBe("rate_limited");
    expect(db().get("SELECT COUNT(*) AS n FROM machine_pairings")).toEqual({ n: MAX_PENDING_PER_TARGET });
    // a requester already pending may still renew its own request (it supersedes, the count stays 10)
    const first = requesters[0]!;
    await requestPairing(app, first.session.token, first.machineId, b.machineId);
    // once one is decided there is room again
    const pending = await list(app, b.session.token, "target");
    await approvePairing(app, b.session.token, pending.find((p) => p.status === "pending")!.pairing_id);
    await requestPairing(app, last.session.token, last.machineId, b.machineId);
  });

  it("(h) two concurrent approvals: one 204, one 409, one grant", async () => {
    const app = makeApp();
    const { a, b } = await setup(app);
    const { pairing_id } = await requestPairing(app, a.session.token, a.machineId, b.machineId);
    const [s1, s2] = [randomSealedInvite(), randomSealedInvite()];
    const results = await Promise.all([approve(app, b.session.token, pairing_id, s1), approve(app, b.session.token, pairing_id, s2)]);
    expect(results.map((r) => r.status).sort()).toEqual([204, 409]);
    expect(grantRows()).toEqual([{ from_machine_id: a.machineId, to_machine_id: b.machineId, pairing_id }]);
    const winner = results[0]!.status === 204 ? s1 : s2;
    expect((await list(app, a.session.token, "requester"))[0]!.sealed_invite_b64).toBe(winner);
  });
});

describe("validation", () => {
  it("to_machine_id must be in the account and not the requester itself", async () => {
    const app = makeApp();
    const { a, d } = await setup(app);
    const foreign = await post(app, a.session.token, { from_machine_id: a.machineId, to_machine_id: d.machineId, requester_x25519_b64: a.noiseKey });
    expect(foreign.status).toBe(404);
    expect(await errorCode(foreign)).toBe("machine_not_found");
    const unknown = await post(app, a.session.token, { from_machine_id: a.machineId, to_machine_id: crypto.randomUUID(), requester_x25519_b64: a.noiseKey });
    expect(unknown.status).toBe(404);
    const self = await post(app, a.session.token, { from_machine_id: a.machineId, to_machine_id: a.machineId, requester_x25519_b64: a.noiseKey });
    expect(self.status).toBe(400);
    expect(await errorCode(self)).toBe("bad_request");
    expect(db().all("SELECT id FROM machine_pairings")).toEqual([]);
  });

  it.each([
    ["31 bytes", Buffer.alloc(31, 7).toString("base64")],
    ["33 bytes", Buffer.alloc(33, 7).toString("base64")],
    ["not base64", "!".repeat(43)],
    ["a number", 5],
    ["missing", undefined],
  ])("requester_x25519_b64 %s is 400", async (_label, value) => {
    const app = makeApp();
    const { a, b } = await setup(app);
    const res = await post(app, a.session.token, { from_machine_id: a.machineId, to_machine_id: b.machineId, requester_x25519_b64: value });
    expect(res.status).toBe(400);
    expect(await errorCode(res)).toBe("bad_request");
  });

  it("(i) the requester key must be the requester machine's noise key (D1)", async () => {
    const app = makeApp();
    const { a, b } = await setup(app);
    const body = (key: string) => ({ from_machine_id: a.machineId, to_machine_id: b.machineId, requester_x25519_b64: key });
    const other = randomPublicKey();
    const wrong = await post(app, a.session.token, body(other));
    expect(wrong.status).toBe(400);
    expect(await errorCode(wrong)).toBe("bad_request");
    expect(db().all("SELECT id FROM machine_pairings")).toEqual([]);

    const rotated = randomPublicKey();
    await registerMachine(app, a.session.token, { noise_public_key_b64: rotated });
    const old = await post(app, a.session.token, body(a.noiseKey));
    expect(old.status).toBe(400);
    expect(db().all("SELECT id FROM machine_pairings")).toEqual([]);
    expect((await post(app, a.session.token, body(rotated))).status).toBe(201);
  });

  it("refuses a malformed body", async () => {
    const app = makeApp();
    const { a } = await setup(app);
    const res = await call(app, "POST", "/v2/pairings", { token: a.session.token, body: "[1]" });
    expect(res.status).toBe(400);
  });

  it.each([
    ["8193 bytes", Buffer.alloc(SEALED_INVITE_MAX_BYTES + 1, 9).toString("base64"), "bad_request"],
    ["empty", "", "bad_request"],
    ["not base64", "%%%%", "bad_request"],
    ["mixed alphabets", "ab+c-d__", "bad_request"],
    ["not a string", 12, "bad_request"],
    ["the plaintext URI", Buffer.from("cmux://enroll/abc").toString("base64"), "plaintext_invite"],
    ["the plaintext URI, URL alphabet", Buffer.from("cmux://enroll/abc?psk=0123456789abcdef").toString("base64url"), "plaintext_invite"],
  ])("approve refuses an invite that is %s", async (_label, sealed, code) => {
    const app = makeApp();
    const { a, b } = await setup(app);
    const { pairing_id } = await requestPairing(app, a.session.token, a.machineId, b.machineId);
    const res = await approve(app, b.session.token, pairing_id, sealed);
    expect(res.status).toBe(400);
    expect(await errorCode(res)).toBe(code);
    expect(db().get("SELECT status, sealed_invite FROM machine_pairings WHERE id = ?", pairing_id)).toEqual({ status: "pending", sealed_invite: null });
    expect(grantRows()).toEqual([]);
  });

  it("approve accepts exactly 8192 bytes", async () => {
    const app = makeApp();
    const { a, b } = await setup(app);
    const { pairing_id } = await requestPairing(app, a.session.token, a.machineId, b.machineId);
    expect((await approve(app, b.session.token, pairing_id, Buffer.alloc(SEALED_INVITE_MAX_BYTES, 9).toString("base64"))).status).toBe(204);
  });

  it.each(["both", "", "TARGET"])("GET ?role=%s is 400", async (role) => {
    const app = makeApp();
    const { a } = await setup(app);
    const res = await call(app, "GET", `/v2/pairings?role=${role}`, { token: a.session.token });
    expect(res.status).toBe(400);
    expect(await errorCode(res)).toBe("bad_request");
    expect((await call(app, "GET", "/v2/pairings", { token: a.session.token })).status).toBe(400);
  });
});

describe("supersede", () => {
  it("a second request from A to B expires the first", async () => {
    const app = makeApp();
    const { a, b } = await setup(app);
    const first = await requestPairing(app, a.session.token, a.machineId, b.machineId);
    const second = await requestPairing(app, a.session.token, a.machineId, b.machineId);
    const items = await list(app, b.session.token, "target");
    expect(items.map((p) => [p.pairing_id, p.status])).toEqual([[second.pairing_id, "pending"], [first.pairing_id, "expired"]]);
    const stale = await approve(app, b.session.token, first.pairing_id);
    expect(stale.status).toBe(409);
    expect(hasGrant(db(), a.machineId, b.machineId)).toBe(false);
  });
});

describe("listing window and purge", () => {
  it("lists newest first for 10 minutes", async () => {
    let clock = T0;
    const app = makeApp({ now: () => clock });
    const { a, b, c } = await setup(app);
    const one = await requestPairing(app, a.session.token, a.machineId, b.machineId);
    clock = T0 + 1;
    const two = await requestPairing(app, c.session.token, c.machineId, b.machineId);
    expect((await list(app, b.session.token, "target")).map((p) => p.pairing_id)).toEqual([two.pairing_id, one.pairing_id]);
    clock = T0 + PAIRING_VISIBLE_MS;
    expect((await list(app, b.session.token, "target")).map((p) => p.pairing_id)).toEqual([two.pairing_id, one.pairing_id]);
    clock = T0 + PAIRING_VISIBLE_MS + 1;
    expect((await list(app, b.session.token, "target")).map((p) => p.pairing_id)).toEqual([two.pairing_id]);
    expect((await list(app, a.session.token, "requester"))).toEqual([]);
  });

  it("drops the sealed invite 10 minutes after the decision", async () => {
    let clock = T0;
    const app = makeApp({ now: () => clock });
    const { a, b } = await setup(app);
    const { pairing_id } = await requestPairing(app, a.session.token, a.machineId, b.machineId);
    const sealed = await approvePairing(app, b.session.token, pairing_id);
    clock = T0 + PAIRING_VISIBLE_MS;
    expect((await list(app, a.session.token, "requester"))[0]!.sealed_invite_b64).toBe(sealed);
    clock = T0 + PAIRING_VISIBLE_MS + 1;
    const items = await list(app, a.session.token, "requester");
    expect(items.every((p) => !("sealed_invite_b64" in p))).toBe(true);
    expect(db().get("SELECT sealed_invite FROM machine_pairings WHERE id = ?", pairing_id)).toEqual({ sealed_invite: null });
    // the grant outlives the purge
    expect(hasGrant(db(), a.machineId, b.machineId)).toBe(true);
  });

  it("deletes rows after 24 hours", async () => {
    let clock = T0;
    const app = makeApp({ now: () => clock });
    const { a, b } = await setup(app);
    await requestPairing(app, a.session.token, a.machineId, b.machineId);
    clock = T0 + 24 * 60 * 60_000;
    await list(app, b.session.token, "target");
    expect(db().get("SELECT COUNT(*) AS n FROM machine_pairings")).toEqual({ n: 1 });
    clock = T0 + 24 * 60 * 60_000 + 1;
    await list(app, b.session.token, "target");
    expect(db().get("SELECT COUNT(*) AS n FROM machine_pairings")).toEqual({ n: 0 });
  });
});

describe("deny", () => {
  it("the target denies: denied, no grant; denying twice is 204", async () => {
    const app = makeApp();
    const { a, b } = await setup(app);
    const { pairing_id } = await requestPairing(app, a.session.token, a.machineId, b.machineId);
    expect((await deny(app, b.session.token, pairing_id)).status).toBe(204);
    expect((await list(app, a.session.token, "requester"))[0]!.status).toBe("denied");
    expect(hasGrant(db(), a.machineId, b.machineId)).toBe(false);
    expect((await deny(app, b.session.token, pairing_id)).status).toBe(204);
    const late = await approve(app, b.session.token, pairing_id);
    expect(late.status).toBe(409);
    expect(grantRows()).toEqual([]);
  });

  it("the requester cancels its own request", async () => {
    const app = makeApp();
    const { a, b } = await setup(app);
    const { pairing_id } = await requestPairing(app, a.session.token, a.machineId, b.machineId);
    expect((await deny(app, a.session.token, pairing_id)).status).toBe(204);
    expect((await list(app, b.session.token, "target"))[0]!.status).toBe("denied");
    expect((await approve(app, b.session.token, pairing_id)).status).toBe(409);
  });

  it("an expired request cannot be denied", async () => {
    let clock = T0;
    const app = makeApp({ now: () => clock });
    const { a, b } = await setup(app);
    const { pairing_id } = await requestPairing(app, a.session.token, a.machineId, b.machineId);
    clock = T0 + PAIRING_TTL_MS + 1;
    const res = await deny(app, b.session.token, pairing_id);
    expect(res.status).toBe(409);
    expect(await errorCode(res)).toBe("pairing_not_pending");
  });
});

describe("logging", () => {
  it("never logs the code, keys or the invite", async () => {
    const lines: string[] = [];
    const original = console.log;
    console.log = (...args: unknown[]) => { lines.push(args.map(String).join(" ")); };
    try {
      const app = makeApp({ pairingCode: () => "987123" });
      const { a, b } = await setup(app);
      const x25519 = a.noiseKey;
      const { pairing_id } = await requestPairing(app, a.session.token, a.machineId, b.machineId);
      const sealed = await approvePairing(app, b.session.token, pairing_id);
      const events = lines.filter((l) => l.includes("pairing_")).map((l) => JSON.parse(l) as Record<string, unknown>);
      expect(events.map((e) => e.event)).toEqual(["pairing_created", "pairing_approved"]);
      for (const e of events) expect(Object.keys(e).sort()).toEqual(["device_id", "event", "pairing_id", "ts"]);
      const all = lines.join("\n");
      for (const secret of ["987123", x25519, sealed, Buffer.from(x25519, "base64url").toString("base64")]) expect(all).not.toContain(secret);
    } finally {
      console.log = original;
    }
  });
});

import { describe, expect, it } from "vitest";
import { MAX_PENDING_PER_TARGET, PAIRING_TTL_MS } from "../src/v2/pairings.js";
import { FakeAppleTokens } from "./fake-idp.js";
import {
  call, CountingLimiter, db, errorCode, googleSession, makeApp, randomPublicKey, registerMachine, signInApple, unlimited, type TestApp,
} from "./helpers.js";

const T0 = 1_800_000_000_000;
const b64 = () => Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString("base64");

async function setup(app: TestApp) {
  const owner = await googleSession(app, { kind: "desktop" });
  const machine = await registerMachine(app, owner.token);
  const sub = `a-${crypto.randomUUID()}`;
  const phoneKey = randomPublicKey();
  const link = async () => (await (await signInApple(app, { sub, email: "hidden@privaterelay.appleid.com", isPrivateEmail: true, publicKey: phoneKey, name: "Ann's iPhone" })).json<{ link_token: string }>()).link_token;
  return { owner, machineId: machine.machine_id, linkSlot: machine.link_slot, sub, phoneKey, link };
}
const ask = (app: TestApp, linkToken: string, machineId: string, extra: Record<string, unknown> = {}) =>
  call(app, "POST", "/v1/auth/apple/link", { body: { link_token: linkToken, machine_id: machineId, client_key_b64: b64(), proof_b64: b64(), ...extra } });
const status = (app: TestApp, linkToken: string, pairingId: string) => call(app, "POST", "/v1/auth/apple/link/status", { body: { link_token: linkToken, pairing_id: pairingId } });
const approve = (app: TestApp, token: string, id: string) => call(app, "POST", `/v2/phone-pairings/${id}/approve`, { token });
const pairingOf = async (res: Awaited<ReturnType<typeof ask>>) => (await res.json<{ pairing_id: string }>()).pairing_id;

describe("Apple ID link through the Mac (S1 §6.4)", () => {
  it("shows the request to the Mac only with apple_links=1, flagged and named after the iPhone", async () => {
    const app = makeApp({ now: () => T0 });
    const s = await setup(app);
    const key = b64();
    const proof = b64();
    const res = await ask(app, await s.link(), s.machineId, { client_key_b64: key, proof_b64: proof });
    expect(res.status).toBe(201);
    const id = await pairingOf(res);
    expect(await (await call(app, "GET", "/v2/phone-pairings?role=target&apple_links=1", { token: s.owner.token })).json()).toEqual({
      pairings: [{ pairing_id: id, device_name: "Ann's iPhone", platform: "ios", client_key_b64: key, proof_b64: proof, created_at_unix: T0 / 1000, links_apple_id: true }],
    });
    expect(await (await call(app, "GET", "/v2/phone-pairings?role=target", { token: s.owner.token })).json()).toEqual({ pairings: [] });
  });

  it("links the Apple ID to the Mac's account on approval and hands the session out exactly once", async () => {
    const app = makeApp({ now: () => T0, appleTokens: new FakeAppleTokens() });
    const s = await setup(app);
    const linkToken = await s.link();
    const id = await pairingOf(await ask(app, linkToken, s.machineId));
    expect(await (await status(app, linkToken, id)).json()).toEqual({ status: "pending" });
    expect((await approve(app, s.owner.token, id)).status).toBe(204);
    const phone = db().get<{ id: string }>("SELECT id FROM devices WHERE public_key = ?", Buffer.from(s.phoneKey, "base64url"))!;
    expect(db().get("SELECT user_id, email, is_private_email, apple_refresh_token, linked_via_device_id FROM identities WHERE provider = 'apple'")).toEqual({
      user_id: s.owner.userId, email: "hidden@privaterelay.appleid.com", is_private_email: 1, apple_refresh_token: "apple-refresh-token-1", linked_via_device_id: phone.id,
    });
    const answer = await status(app, linkToken, id);
    const body = await answer.json<{ session: { token: string } }>();
    expect(body).toEqual({
      status: "approved",
      session: { user_id: s.owner.userId, device_id: phone.id, token: expect.stringMatching(/^[A-Za-z0-9_-]{43}$/), email: s.owner.email },
      machine: { machine_id: s.machineId, name: "Mac-Studio", link_slot: s.linkSlot },
    });
    expect(db().get("SELECT auth_method FROM tokens WHERE device_id = ?", phone.id)).toEqual({ auth_method: "apple" });
    const grants = await (await call(app, "GET", "/v2/phone-grants", { token: body.session.token })).json<{ grants: { machine_id: string }[] }>();
    expect(grants.grants.map((g) => g.machine_id)).toEqual([s.machineId]);
    const second = await status(app, linkToken, id);
    expect([second.status, await errorCode(second)]).toEqual([401, "invalid_credentials"]);
    const direct = await (await signInApple(app, { sub: s.sub, publicKey: s.phoneKey })).json<{ user_id: string; device_id: string }>();
    expect([direct.user_id, direct.device_id]).toEqual([s.owner.userId, phone.id]);
  });

  it("deny: the iPhone reads denied and nothing is linked", async () => {
    const app = makeApp({ now: () => T0 });
    const s = await setup(app);
    const linkToken = await s.link();
    const id = await pairingOf(await ask(app, linkToken, s.machineId));
    expect((await call(app, "POST", `/v2/phone-pairings/${id}/deny`, { token: s.owner.token })).status).toBe(204);
    expect(await (await status(app, linkToken, id)).json()).toEqual({ status: "denied" });
    expect(db().get("SELECT (SELECT COUNT(*) FROM identities WHERE provider = 'apple') AS i, (SELECT COUNT(*) FROM phone_grants) AS g")).toEqual({ i: 0, g: 0 });
  });

  it("expires a request after 5 minutes and a link token after 10", async () => {
    let now = T0;
    const app = makeApp({ now: () => now });
    const s = await setup(app);
    const linkToken = await s.link();
    const id = await pairingOf(await ask(app, linkToken, s.machineId));
    now += PAIRING_TTL_MS + 1;
    const late = await approve(app, s.owner.token, id);
    expect([late.status, await errorCode(late)]).toEqual([410, "pairing_expired"]);
    expect(await (await status(app, linkToken, id)).json()).toEqual({ status: "expired" });
    const id2 = await pairingOf(await ask(app, linkToken, s.machineId));
    now = T0 + 600_000;
    expect((await status(app, linkToken, id2)).status).toBe(401);
    expect((await ask(app, linkToken, s.machineId)).status).toBe(401);
    const lateApprove = await approve(app, s.owner.token, id2);
    expect([lateApprove.status, await errorCode(lateApprove)]).toEqual([410, "pairing_expired"]);
  });

  it("refuses a bad link token, an unknown machine, malformed keys and a pairing of another link", async () => {
    const app = makeApp({ now: () => T0 });
    const s = await setup(app);
    const a = await s.link();
    const b = await s.link();
    expect(await errorCode(await ask(app, "x".repeat(43), s.machineId))).toBe("invalid_credentials");
    expect(await errorCode(await ask(app, a, crypto.randomUUID()))).toBe("machine_not_found");
    expect((await ask(app, a, s.machineId, { client_key_b64: "AAAA" })).status).toBe(400);
    const id = await pairingOf(await ask(app, a, s.machineId));
    expect(await errorCode(await status(app, b, id))).toBe("pairing_not_found");
  });

  it("lets a newer request of the same link supersede the older one; a link already approved cannot ask again", async () => {
    const app = makeApp({ now: () => T0 });
    const s = await setup(app);
    const linkToken = await s.link();
    const first = await pairingOf(await ask(app, linkToken, s.machineId));
    const second = await pairingOf(await ask(app, linkToken, s.machineId));
    expect(await (await status(app, linkToken, first)).json()).toEqual({ status: "expired" });
    expect((await approve(app, s.owner.token, second)).status).toBe(204);
    expect((await ask(app, linkToken, s.machineId)).status).toBe(401);
  });

  it("answers 409 identity_in_use when the Apple ID already signs in to another account, leaving the request pending", async () => {
    const app = makeApp({ now: () => T0 });
    const s = await setup(app);
    const other = await googleSession(app, { kind: "desktop" });
    const otherMachine = await registerMachine(app, other.token);
    const toOther = await pairingOf(await ask(app, await s.link(), otherMachine.machine_id));
    const mine = await pairingOf(await ask(app, await s.link(), s.machineId));
    expect((await approve(app, s.owner.token, mine)).status).toBe(204);
    const clash = await approve(app, other.token, toOther);
    expect([clash.status, await errorCode(clash)]).toEqual([409, "identity_in_use"]);
    expect(db().get("SELECT status FROM phone_pairings WHERE id = ?", toOther)).toEqual({ status: "pending" });
  });

  it("caps live pending requests per machine (429)", async () => {
    const app = makeApp({ now: () => T0 });
    const s = await setup(app);
    for (let i = 0; i < MAX_PENDING_PER_TARGET; i++) expect((await ask(app, await s.link(), s.machineId)).status).toBe(201);
    expect((await ask(app, await s.link(), s.machineId)).status).toBe(429);
  });

  it("limits link requests per IP with the login limiter", async () => {
    const loginIp = new CountingLimiter(3);
    const app = makeApp({ now: () => T0, limiters: { ...unlimited, loginIp } });
    const s = await setup(app); // call 1: the Google sign-in
    const linkToken = await s.link(); // call 2: the Apple sign-in
    expect((await ask(app, linkToken, s.machineId)).status).toBe(201); // call 3
    expect((await ask(app, linkToken, s.machineId)).status).toBe(429); // call 4
  });
});

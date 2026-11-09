import { describe, expect, it } from "vitest";
import { FakeAppleTokens } from "./fake-idp.js";
import { call, db, errorCode, googleSession, linkAppleIdByQr, makeApp, registerMachine, type TestApp } from "./helpers.js";

const T0 = 1_800_000_000_000;
const UUID = /^[0-9a-f-]{36}$/;
const list = (app: TestApp, token: string) => call(app, "GET", "/v1/account/identities", { token });
const remove = (app: TestApp, token: string, id: string) => call(app, "DELETE", `/v1/account/identities/${id}`, { token });

async function owner(app: TestApp) {
  const desk = await googleSession(app, { kind: "desktop" });
  const machine = await registerMachine(app, desk.token);
  const apple = await linkAppleIdByQr(app, desk.token, machine.machine_id, { email: "hidden@privaterelay.appleid.com", isPrivateEmail: true, name: "Ann's iPhone" });
  return { desk, apple };
}

describe("/v1/account/identities", () => {
  it("lists the Google sign-in and each Apple ID with the iPhone that linked it", async () => {
    const app = makeApp({ now: () => T0, appleTokens: new FakeAppleTokens() });
    const { desk } = await owner(app);
    await googleSession(app);
    expect(await (await list(app, desk.token)).json()).toEqual({
      identities: [
        { identity_id: expect.stringMatching(UUID), provider: "google", email: desk.email, is_private_email: false, linked_via_device_name: null, created_at_unix: T0 / 1000 },
        { identity_id: expect.stringMatching(UUID), provider: "apple", email: "hidden@privaterelay.appleid.com", is_private_email: true, linked_via_device_name: "Ann's iPhone", created_at_unix: T0 / 1000 },
      ],
    });
  });

  it("removes an Apple ID: its devices are signed out, Apple is asked to revoke, the phone grant and the Mac stay", async () => {
    const tokens = new FakeAppleTokens();
    const app = makeApp({ now: () => T0, appleTokens: tokens });
    const { desk, apple } = await owner(app);
    const id = (await (await list(app, desk.token)).json<{ identities: { identity_id: string; provider: string }[] }>()).identities.find((i) => i.provider === "apple")!.identity_id;
    expect((await remove(app, desk.token, id)).status).toBe(204);
    expect((await call(app, "GET", "/v1/devices", { token: apple.session.token })).status).toBe(401);
    expect((await call(app, "GET", "/v1/devices", { token: desk.token })).status).toBe(200);
    expect(tokens.revokes).toEqual([{ clientId: "com.shellx.dev", refreshToken: "apple-refresh-token-1" }]);
    expect(db().get("SELECT COUNT(*) AS n FROM phone_grants WHERE device_id = ?", apple.session.deviceId)).toEqual({ n: 1 });
  });

  it("keeps the Apple ID when the iPhone is unpaired", async () => {
    const app = makeApp({ now: () => T0, appleTokens: new FakeAppleTokens() });
    const { desk, apple } = await owner(app);
    const grant = db().get<{ id: string }>("SELECT id FROM phone_grants WHERE device_id = ?", apple.session.deviceId)!;
    expect((await call(app, "DELETE", `/v2/phone-grants/${grant.id}`, { token: desk.token })).status).toBe(204);
    expect(db().get("SELECT COUNT(*) AS n FROM identities WHERE provider = 'apple'")).toEqual({ n: 1 });
  });

  it("refuses the Google sign-in (409 last_google_identity), unknown or foreign ids (404) and a missing token (401)", async () => {
    const app = makeApp({ now: () => T0, appleTokens: new FakeAppleTokens() });
    const { desk } = await owner(app);
    const other = await googleSession(app);
    const mine = (await (await list(app, desk.token)).json<{ identities: { identity_id: string; provider: string }[] }>()).identities;
    const google = await remove(app, desk.token, mine.find((i) => i.provider === "google")!.identity_id);
    expect([google.status, await errorCode(google)]).toEqual([409, "last_google_identity"]);
    const foreign = db().get<{ id: string }>("SELECT id FROM identities WHERE user_id = ?", other.userId)!.id;
    for (const id of ["not-a-uuid", crypto.randomUUID(), foreign]) expect(await errorCode(await remove(app, desk.token, id))).toBe("identity_not_found");
    expect((await call(app, "GET", "/v1/account/identities")).status).toBe(401);
  });
});

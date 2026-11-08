import { describe, expect, it } from "vitest";
import { hashToken } from "../src/auth/tokens.js";
import { FakeAppleTokens } from "./fake-idp.js";
import {
  appleIdToken, call, db, deviceBody, errorCode, googleSession, linkAppleIdByQr, makeApp, randomEmail, randomPublicKey, registerAccount,
  registerMachine, seedUser, signInApple,
} from "./helpers.js";

describe("POST /v1/auth/apple", () => {
  it("answers 202 link_required for an Apple ID that matches no account; keeps the link hash, the iPhone key and the refresh token", async () => {
    const tokens = new FakeAppleTokens();
    const app = makeApp({ appleTokens: tokens });
    const publicKey = randomPublicKey();
    const res = await signInApple(app, { sub: "a-new", email: "h@privaterelay.appleid.com", isPrivateEmail: true, publicKey, authorizationCode: "code-1" });
    expect(res.status).toBe(202);
    const body = await res.json<{ status: string; link_token: string; expires_in: number }>();
    expect(body).toEqual({ status: "link_required", link_token: expect.stringMatching(/^[A-Za-z0-9_-]{43}$/), expires_in: 600 });
    const link = db().get<{ token_hash: Buffer; subject: string; is_private_email: number; apple_refresh_token: string; device_public_key: Buffer }>("SELECT * FROM apple_links")!;
    expect(Buffer.from(link.token_hash).equals(Buffer.from(await hashToken(body.link_token)))).toBe(true);
    expect([link.subject, link.is_private_email, link.apple_refresh_token]).toEqual(["a-new", 1, "apple-refresh-token-1"]);
    expect(Buffer.from(link.device_public_key).toString("base64url")).toBe(publicKey);
    expect(tokens.exchanges).toEqual([{ clientId: "com.shellx.dev", code: "code-1" }]);
    expect(db().get("SELECT (SELECT COUNT(*) FROM users) AS users, (SELECT COUNT(*) FROM identities) AS identities")).toEqual({ users: 0, identities: 0 });
  });

  it("answers 202 link_required for the email of an account without a password, even one with a Google sign-in, and links nothing by email", async () => {
    const app = makeApp({ appleTokens: new FakeAppleTokens() });
    const email = randomEmail();
    const seeded = await seedUser(email, null);
    const google = await googleSession(app, { kind: "desktop" });
    for (const [userId, accountEmail] of [[seeded, email], [google.userId, google.email]] as const) {
      const res = await signInApple(app, { email: accountEmail.toUpperCase() });
      expect(res.status).toBe(202);
      expect((await res.json<{ status: string }>()).status).toBe("link_required");
      expect(db().get("SELECT COUNT(*) AS n FROM identities WHERE user_id = ? AND provider = 'apple'", userId)).toEqual({ n: 0 });
    }
    expect(db().get("SELECT COUNT(*) AS n FROM tokens WHERE auth_method = 'apple'")).toEqual({ n: 0 });
  });

  it("answers 202 link_required for the email of an account that still has a password, and links nothing to that account", async () => {
    const tokens = new FakeAppleTokens();
    const app = makeApp({ appleTokens: tokens });
    const account = await registerAccount(app);
    const res = await signInApple(app, { email: account.email });
    expect(res.status).toBe(202);
    expect((await res.json<{ status: string }>()).status).toBe("link_required");
    expect(db().get("SELECT COUNT(*) AS n FROM identities WHERE user_id = ?", account.agent.userId)).toEqual({ n: 0 });
  });

  it("asks Apple for a refresh token only while the identity has none for this bundle id; a failed exchange never blocks", async () => {
    const tokens = new FakeAppleTokens();
    tokens.refreshToken = null;
    const app = makeApp({ appleTokens: tokens });
    const owner = await googleSession(app, { kind: "desktop" });
    const machine = await registerMachine(app, owner.token);
    await linkAppleIdByQr(app, owner.token, machine.machine_id, { sub: "a-2" });
    expect(db().get("SELECT apple_refresh_token FROM identities WHERE subject = 'a-2'")).toEqual({ apple_refresh_token: null });
    tokens.refreshToken = "apple-refresh-token-2";
    expect((await signInApple(app, { sub: "a-2" })).status).toBe(200);
    expect(db().get("SELECT apple_refresh_token, apple_client_id FROM identities WHERE subject = 'a-2'")).toEqual({ apple_refresh_token: "apple-refresh-token-2", apple_client_id: "com.shellx.dev" });
    expect((await signInApple(app, { sub: "a-2" })).status).toBe(200);
    expect(tokens.exchanges).toHaveLength(2);
  });

  it("signs in without an authorization code or without an Apple key, never calling Apple", async () => {
    const tokens = new FakeAppleTokens();
    const email = randomEmail();
    await seedUser(email, null);
    expect((await signInApple(makeApp({ appleTokens: tokens }), { email, authorizationCode: null })).status).toBe(202);
    expect((await signInApple(makeApp(), { email: randomEmail() })).status).toBe(202);
    expect(tokens.exchanges).toEqual([]);
  });

  it("refuses a non-iPhone device (400 invalid_device) and a token that carries the raw nonce (401)", async () => {
    const app = makeApp();
    for (const device of [deviceBody("desktop"), deviceBody("mobile", { platform: "android" })]) {
      const res = await call(app, "POST", "/v1/auth/apple", { body: { ...(await appleIdToken(app)), authorization_code: "c", device } });
      expect([res.status, await errorCode(res)]).toEqual([400, "invalid_device"]);
    }
    const raw = await appleIdToken(app);
    const res = await call(app, "POST", "/v1/auth/apple", {
      body: { ...(await appleIdToken(app, { claims: { nonce: raw.nonce } })), nonce: raw.nonce, authorization_code: "c", device: deviceBody("mobile") },
    });
    expect([res.status, await errorCode(res)]).toEqual([401, "invalid_credentials"]);
  });
});

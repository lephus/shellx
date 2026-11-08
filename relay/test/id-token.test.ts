import { describe, expect, it } from "vitest";
import { createIdTokenVerifier, loadIdTokenVerifier, sha256Hex } from "../src/auth/id-token.js";
import { createTestIssuer, testIdTokenClaims } from "../scripts/test-idp.js";
import { appleClaims, fakeApple, fakeGoogle, fakeTestIdp, GOOGLE_AUD, googleClaims, TEST_ISSUER, testIdTokens } from "./fake-idp.js";

const NOW = 1_800_000_000_000;
const nowSec = NOW / 1000;
const NONCE = "n".repeat(43);
const verifier = testIdTokens();
const signIn = { providers: ["google", "test"] as const, nonce: NONCE, maxAgeSec: 600, nowMs: NOW };
const google = async (extra: Record<string, unknown> = {}) =>
  fakeGoogle.sign(googleClaims({ nonce: NONCE, nowSec, sub: "g-1", email: " Ann.Lee@Gmail.com ", extra }));

describe("Google ID tokens", () => {
  it("accept a valid token (either issuer spelling) and normalize the email", async () => {
    expect(await verifier.verify(await google(), signIn)).toEqual({
      provider: "google", subject: "g-1", email: "ann.lee@gmail.com", isPrivateEmail: false, audience: GOOGLE_AUD,
    });
    expect(await verifier.verify(await google({ iss: "accounts.google.com" }), signIn)).toMatchObject({ provider: "google" });
  });

  it.each([
    ["an unknown audience", { aud: "someone-else.apps.googleusercontent.com" }], ["another issuer", { iss: "https://evil.example" }],
    ["an expired token", { exp: nowSec - 61 }], ["an iat older than 600 s", { iat: nowSec - 601 }],
    ["an iat over 60 s ahead", { iat: nowSec + 61 }], ["an unverified email", { email_verified: false }],
    ["email_verified as a string", { email_verified: "true" }], ["no email", { email: undefined }],
    ["another nonce", { nonce: "m".repeat(43) }], ["the Apple form of the nonce", { nonce: sha256Hex(NONCE) }],
    ["no sub", { sub: undefined }],
  ])("refuse %s", async (_, extra) => {
    expect(await verifier.verify(await google(extra), signIn)).toBeNull();
  });

  it("use the age limit asked for: 600 s and 60 s ahead pass, 300 s for re-authentication", async () => {
    expect(await verifier.verify(await google({ iat: nowSec - 600 }), signIn)).not.toBeNull();
    expect(await verifier.verify(await google({ iat: nowSec + 60 }), signIn)).not.toBeNull();
    expect(await verifier.verify(await google({ iat: nowSec - 300 }), { ...signIn, maxAgeSec: 300 })).not.toBeNull();
    expect(await verifier.verify(await google({ iat: nowSec - 301 }), { ...signIn, maxAgeSec: 300 })).toBeNull();
  });

  it("refuse a forged key under the real kid, alg none, a non-string, an oversized token and a provider not asked for", async () => {
    const kid = (await fakeGoogle.jwks()).keys[0]!.kid;
    const impostor = await createTestIssuer("https://accounts.google.com", "RS256");
    const forged = await impostor.sign(googleClaims({ nonce: NONCE, nowSec }), { kid });
    expect(await verifier.verify(forged, signIn)).toBeNull();
    const b64 = (v: unknown) => Buffer.from(JSON.stringify(v)).toString("base64url");
    expect(await verifier.verify(`${b64({ alg: "none" })}.${b64(googleClaims({ nonce: NONCE, nowSec }))}.`, signIn)).toBeNull();
    expect(await verifier.verify(42, signIn)).toBeNull();
    expect(await verifier.verify("x".repeat(8193), signIn)).toBeNull();
    expect(await verifier.verify(await google(), { ...signIn, providers: ["apple"] as const })).toBeNull();
  });

  it("refuse every Google token while GOOGLE_CLIENT_IDS is empty", async () => {
    const none = createIdTokenVerifier({ googleClientIds: [], appleClientIds: [], testIdp: null, googleKeys: fakeGoogle.keys });
    expect(await none.verify(await google(), signIn)).toBeNull();
  });
});

describe("Apple identity tokens", () => {
  const options = { ...signIn, providers: ["apple"] as const };
  const apple = async (extra: Record<string, unknown> = {}) =>
    fakeApple.sign(appleClaims({ nonce: NONCE, nowSec, sub: "a-1", email: "h1@privaterelay.appleid.com", isPrivateEmail: true, extra }));

  it("accept sha256_hex(nonce) and email_verified true or \"true\", and report a private email", async () => {
    expect(await verifier.verify(await apple(), options)).toEqual({
      provider: "apple", subject: "a-1", email: "h1@privaterelay.appleid.com", isPrivateEmail: true, audience: "com.shellx.dev",
    });
    expect(await verifier.verify(await apple({ email_verified: true, is_private_email: false }), options)).toMatchObject({ isPrivateEmail: false });
  });

  it.each([["the raw nonce", { nonce: NONCE }], ["an unverified email", { email_verified: "false" }], ["another bundle id", { aud: "com.example.other" }]])(
    "refuse %s", async (_, extra) => {
      expect(await verifier.verify(await apple(extra), options)).toBeNull();
    },
  );
});

describe("test identity provider", () => {
  it("is accepted only when configured, for aud shellx-test-idp only", async () => {
    const claims = testIdTokenClaims(TEST_ISSUER, { sub: "t-1", email: "e2e@example.com", nonce: NONCE, nowSec });
    expect(await verifier.verify(await fakeTestIdp.sign(claims), signIn)).toMatchObject({ provider: "test", subject: "t-1" });
    expect(await verifier.verify(await fakeTestIdp.sign({ ...claims, aud: GOOGLE_AUD }), signIn)).toBeNull();
    const noTest = createIdTokenVerifier({ googleClientIds: [GOOGLE_AUD], appleClientIds: [], testIdp: null, googleKeys: fakeGoogle.keys });
    expect(await noTest.verify(await fakeTestIdp.sign(claims), signIn)).toBeNull();
  });

  it("reads TEST_IDP_JWKS_PATH and refuses an unreadable or malformed file", async () => {
    const idp = await createTestIssuer("https://t.invalid");
    const files: Record<string, string> = { "/ok.json": JSON.stringify(idp.jwks), "/bad.json": '{"keys": 3}' };
    const read = (path: string) => {
      const text = files[path];
      if (text === undefined) throw Object.assign(new Error("no such file"), { code: "ENOENT" });
      return text;
    };
    const config = (jwksPath: string) => ({ googleClientIds: [], appleClientIds: [], testIdp: { issuer: "https://t.invalid", jwksPath } });
    const loaded = loadIdTokenVerifier(config("/ok.json"), read);
    const token = await idp.sign(testIdTokenClaims("https://t.invalid", { sub: "s", email: "e@example.com", nonce: NONCE, nowSec }));
    expect(await loaded.verify(token, signIn)).toMatchObject({ provider: "test" });
    for (const path of ["/missing.json", "/bad.json"]) {
      expect(() => loadIdTokenVerifier(config(path), read)).toThrow("TEST_IDP_JWKS_PATH is not a readable JWKS file");
    }
  });

  it("sha256Hex is lower-case hex", () => {
    expect(sha256Hex("abc")).toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  });
});

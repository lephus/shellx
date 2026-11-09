import { createPublicKey, generateKeyPairSync } from "node:crypto";
import { jwtVerify } from "jose";
import { afterEach, describe, expect, it, vi } from "vitest";
import { appleClientSecret, AppleRestClient, loadAppleSiwa, revokeAppleTokens } from "../src/auth/apple-rest.js";
import { FakeAppleTokens } from "./fake-idp.js";

const pem = { privateKeyEncoding: { type: "pkcs8", format: "pem" }, publicKeyEncoding: { type: "spki", format: "pem" } } as const;
const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1", ...pem }) as unknown as { privateKey: string; publicKey: string };
const KEY = { teamId: "W4RF3W4VTZ", keyId: "ABC123DEFG", privateKeyPem: privateKey };
const NOW = 1_800_000_000_000;
afterEach(() => vi.restoreAllMocks());

function captureLog(): () => string {
  const lines: string[] = [];
  vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => void lines.push(args.map(String).join(" ")));
  return () => lines.join("\n");
}

function fakeFetch(answers: { status: number; body: string }[] | Error) {
  const calls: { url: string; form: URLSearchParams; contentType: string | null }[] = [];
  const fn = (async (url: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(url), form: new URLSearchParams(String(init?.body)), contentType: new Headers(init?.headers).get("content-type") });
    if (answers instanceof Error) throw answers;
    const answer = answers.shift()!;
    return new Response(answer.body, { status: answer.status });
  }) as typeof fetch;
  return { fn, calls };
}

describe("Apple REST", () => {
  it("signs the client secret as ES256 with the key id: iss team, sub bundle id, aud appleid, 300 s", async () => {
    const { payload, protectedHeader } = await jwtVerify(await appleClientSecret(KEY, "com.shellx.dev", NOW), createPublicKey(publicKey), { currentDate: new Date(NOW) });
    expect(protectedHeader).toMatchObject({ alg: "ES256", kid: "ABC123DEFG" });
    expect(payload).toEqual({ iss: "W4RF3W4VTZ", sub: "com.shellx.dev", aud: "https://appleid.apple.com", iat: 1_800_000_000, exp: 1_800_000_300 });
  });

  it("exchanges an authorization code for the refresh token", async () => {
    const f = fakeFetch([{ status: 200, body: JSON.stringify({ access_token: "a", refresh_token: "r-1", id_token: "i", token_type: "Bearer", expires_in: 3600 }) }]);
    expect(await new AppleRestClient({ key: KEY, fetch: f.fn, now: () => NOW }).exchangeCode("com.shellx.dev", "code-1")).toBe("r-1");
    expect([f.calls[0]!.url, f.calls[0]!.contentType]).toEqual(["https://appleid.apple.com/auth/token", "application/x-www-form-urlencoded"]);
    expect(Object.fromEntries(f.calls[0]!.form)).toMatchObject({ client_id: "com.shellx.dev", code: "code-1", grant_type: "authorization_code" });
    await expect(jwtVerify(f.calls[0]!.form.get("client_secret")!, createPublicKey(publicKey), { currentDate: new Date(NOW) })).resolves.toBeDefined();
  });

  it.each([
    ["a 400 answer", [{ status: 400, body: '{"error":"invalid_grant"}' }]],
    ["a 200 without refresh_token", [{ status: 200, body: "{}" }]],
    ["no answer", new Error("ECONNRESET")],
  ] as const)("answers null to %s and logs metadata only", async (_, answers) => {
    const log = captureLog();
    const client = new AppleRestClient({ key: KEY, fetch: fakeFetch(Array.isArray(answers) ? ([...answers] as { status: number; body: string }[]) : (answers as Error)).fn, now: () => NOW });
    expect(await client.exchangeCode("com.shellx.dev", "secret-code")).toBeNull();
    expect(log()).toContain("apple_token_exchange_failed");
    expect(log()).not.toContain("secret-code");
  });

  it("revokes a refresh token: true on 200, false otherwise, never logging the token", async () => {
    const ok = fakeFetch([{ status: 200, body: "" }]);
    expect(await new AppleRestClient({ key: KEY, fetch: ok.fn, now: () => NOW }).revoke("com.shellx.prod", "r-9")).toBe(true);
    expect(ok.calls[0]!.url).toBe("https://appleid.apple.com/auth/revoke");
    expect(Object.fromEntries(ok.calls[0]!.form)).toMatchObject({ client_id: "com.shellx.prod", token: "r-9", token_type_hint: "refresh_token" });
    const log = captureLog();
    expect(await new AppleRestClient({ key: KEY, fetch: fakeFetch([{ status: 400, body: "{}" }]).fn }).revoke("com.shellx.prod", "r-9")).toBe(false);
    expect(log()).toContain("apple_revoke_failed");
    expect(log()).not.toContain("r-9");
  });

  it("revokeAppleTokens revokes each stored token and logs what it skipped", async () => {
    const log = captureLog();
    const fake = new FakeAppleTokens();
    await revokeAppleTokens(fake, [{ apple_client_id: "com.shellx.dev", apple_refresh_token: "r-1" }, { apple_client_id: null, apple_refresh_token: null }]);
    expect(fake.revokes).toEqual([{ clientId: "com.shellx.dev", refreshToken: "r-1" }]);
    await revokeAppleTokens(null, [{ apple_client_id: "com.shellx.dev", apple_refresh_token: "r-2" }]);
    expect(log()).toContain('"event":"apple_revoke_skipped","reason":"no_refresh_token"');
    expect(log()).toContain('"event":"apple_revoke_skipped","reason":"not_configured"');
    expect(log()).not.toContain("r-2");
  });

  it("loadAppleSiwa: off without all three variables, unreadable or not a P-256 key; on with one", () => {
    const env = { APPLE_TEAM_ID: "W4RF3W4VTZ", APPLE_SIWA_KEY_ID: "ABC123DEFG", APPLE_SIWA_KEY_PATH: "/secrets/siwa.p8" };
    const file = (text: string) => ({ readFile: () => text });
    expect(loadAppleSiwa({ ...env, APPLE_TEAM_ID: " " })).toEqual({ gateway: null, reason: "not_configured" });
    expect(loadAppleSiwa(env, { readFile: () => { throw new Error("ENOENT"); } })).toEqual({ gateway: null, reason: "unreadable" });
    expect(loadAppleSiwa(env, file("not a key"))).toEqual({ gateway: null, reason: "invalid" });
    expect(loadAppleSiwa(env, file((generateKeyPairSync("rsa", { modulusLength: 2048, ...pem }) as unknown as { privateKey: string }).privateKey))).toEqual({ gateway: null, reason: "invalid" });
    expect(loadAppleSiwa(env, file(privateKey)).gateway).toBeInstanceOf(AppleRestClient);
  });
});

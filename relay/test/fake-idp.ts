import { randomUUID } from "node:crypto";
import type { JSONWebKeySet, JWTHeaderParameters, JWTPayload, JWTVerifyGetKey } from "jose";
import { createTestIssuer, type TestIssuer, testIdTokenClaims } from "../scripts/test-idp.js";
import { createIdTokenVerifier, type IdTokenVerifier, sha256Hex } from "../src/auth/id-token.js";
import { APPLE_ISSUER, DEFAULT_APPLE_CLIENT_IDS } from "../src/auth/providers.js";

export const GOOGLE_AUD = "1234-desktop.apps.googleusercontent.com";
export const APPLE_AUD = "com.shellx.dev";
export const TEST_ISSUER = "https://test-idp.shellx.invalid";

export interface FakeIssuer {
  readonly issuer: string;
  readonly keys: JWTVerifyGetKey;
  sign(claims: JWTPayload, header?: Partial<JWTHeaderParameters>): Promise<string>;
  jwks(): Promise<JSONWebKeySet>;
}

/** A fake issuer whose key pair is generated on first use, so files that never sign pay nothing. */
export function fakeIssuer(issuer: string, alg: "ES256" | "RS256"): FakeIssuer {
  let created: Promise<TestIssuer> | undefined;
  const real = () => (created ??= createTestIssuer(issuer, alg));
  return {
    issuer,
    // Resolves keys lazily too: jose calls this getter with the token header.
    keys: async (header, token) => (await real()).keys(header, token),
    sign: async (claims, header) => (await real()).sign(claims, header),
    jwks: async () => (await real()).jwks,
  };
}

export const fakeGoogle = fakeIssuer("https://accounts.google.com", "RS256");
export const fakeApple = fakeIssuer(APPLE_ISSUER, "RS256");
export const fakeTestIdp = fakeIssuer(TEST_ISSUER, "ES256");

export interface ClaimInput {
  nonce: string;
  sub?: string;
  email?: string;
  nowSec?: number;
  extra?: Record<string, unknown>;
}

const nowSecOf = (input: ClaimInput) => input.nowSec ?? Math.floor(Date.now() / 1000);

export function googleClaims(input: ClaimInput): JWTPayload {
  const iat = nowSecOf(input);
  return {
    iss: "https://accounts.google.com", aud: GOOGLE_AUD, sub: input.sub ?? `g-${randomUUID()}`,
    email: input.email ?? `g-${randomUUID()}@example.com`, email_verified: true, nonce: input.nonce,
    iat, exp: iat + 3600, ...input.extra,
  };
}

export function appleClaims(input: ClaimInput & { isPrivateEmail?: boolean }): JWTPayload {
  const iat = nowSecOf(input);
  return {
    iss: APPLE_ISSUER, aud: APPLE_AUD, sub: input.sub ?? `a-${randomUUID()}`,
    email: input.email ?? `a-${randomUUID()}@example.com`, email_verified: "true",
    is_private_email: input.isPrivateEmail === true ? "true" : "false", nonce: sha256Hex(input.nonce),
    iat, exp: iat + 600, ...input.extra,
  };
}

export function testClaims(input: ClaimInput): JWTPayload {
  return {
    ...testIdTokenClaims(TEST_ISSUER, {
      sub: input.sub ?? `t-${randomUUID()}`, email: input.email ?? `t-${randomUUID()}@example.com`, nonce: input.nonce, nowSec: nowSecOf(input),
    }),
    ...input.extra,
  };
}

/** A verifier that trusts the three fake issuers above. */
export function testIdTokens(): IdTokenVerifier {
  return createIdTokenVerifier({
    googleClientIds: [GOOGLE_AUD],
    appleClientIds: [...DEFAULT_APPLE_CLIENT_IDS],
    testIdp: { issuer: TEST_ISSUER, keys: fakeTestIdp.keys },
    googleKeys: fakeGoogle.keys,
    appleKeys: fakeApple.keys,
  });
}

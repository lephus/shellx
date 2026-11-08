/**
 * A test identity provider: a key pair, its public JWKS and a signer. Used by the relay's tests and by
 * harnesses (share-e2e) that run a relay with TEST_IDP_ISSUER / TEST_IDP_JWKS_PATH. Not part of the image.
 */
import { createLocalJWKSet, exportJWK, generateKeyPair, type JSONWebKeySet, type JWTHeaderParameters, type JWTPayload, type JWTVerifyGetKey, SignJWT } from "jose";
import { TEST_IDP_AUDIENCE } from "../src/auth/providers.js";

export interface TestIssuer {
  readonly issuer: string;
  /** Public keys only, each with `kid`, `alg` and `use: "sig"`. */
  readonly jwks: JSONWebKeySet;
  readonly keys: JWTVerifyGetKey;
  /** Signs `claims` exactly as given; the header is `{alg, kid, typ: "JWT", ...header}`. */
  sign(claims: JWTPayload, header?: Partial<JWTHeaderParameters>): Promise<string>;
}

export async function createTestIssuer(issuer: string, alg: "ES256" | "RS256" = "ES256"): Promise<TestIssuer> {
  const { publicKey, privateKey } = await generateKeyPair(alg, { extractable: true });
  const kid = crypto.randomUUID();
  const jwks: JSONWebKeySet = { keys: [{ ...(await exportJWK(publicKey)), kid, alg, use: "sig" }] };
  return {
    issuer,
    jwks,
    keys: createLocalJWKSet(jwks),
    sign: (claims, header = {}) => new SignJWT(claims).setProtectedHeader({ alg, kid, typ: "JWT", ...header }).sign(privateKey),
  };
}

export function testIdTokenClaims(issuer: string, input: { sub: string; email: string; nonce: string; nowSec?: number }): JWTPayload {
  const nowSec = input.nowSec ?? Math.floor(Date.now() / 1000);
  return {
    iss: issuer, aud: TEST_IDP_AUDIENCE, sub: input.sub, email: input.email, email_verified: true,
    nonce: input.nonce, iat: nowSec, exp: nowSec + 600,
  };
}

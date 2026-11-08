import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { createLocalJWKSet, createRemoteJWKSet, decodeJwt, type JSONWebKeySet, jwtVerify, type JWTVerifyGetKey } from "jose";
import { ConfigError, type Config } from "../config.js";
import { errorKind, logMeta } from "../log.js";
import { normalizeEmail } from "./email.js";
import { APPLE_ISSUER, GOOGLE_ISSUERS, type IdentityProvider, TEST_IDP_AUDIENCE } from "./providers.js";

export const GOOGLE_JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs";
export const APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys";
export const ID_TOKEN_MAX_AGE_SEC = 600;
export const REAUTH_MAX_AGE_SEC = 300;
export const CLOCK_TOLERANCE_SEC = 60;
export const MAX_ID_TOKEN_CHARS = 8192;

export interface VerifiedIdToken {
  provider: IdentityProvider;
  subject: string;
  /** Already `normalizeEmail`'d. */
  email: string;
  isPrivateEmail: boolean;
  /** The matched client id (for Apple, the bundle id). */
  audience: string;
}

export interface VerifyOptions {
  providers: readonly IdentityProvider[];
  nonce: string;
  maxAgeSec: number;
  nowMs: number;
}

export interface IdTokenVerifier {
  /** Never throws for a bad token: null, after logging `id_token_rejected` with a reason (no token content). */
  verify(token: unknown, options: VerifyOptions): Promise<VerifiedIdToken | null>;
}

export interface IdTokenVerifierOptions {
  googleClientIds: readonly string[];
  appleClientIds: readonly string[];
  testIdp: { issuer: string; keys: JWTVerifyGetKey } | null;
  googleKeys?: JWTVerifyGetKey;
  appleKeys?: JWTVerifyGetKey;
}

export function sha256Hex(text: string): string {
  return createHash("sha256").update(text, "utf8").digest("hex");
}

export function createIdTokenVerifier(options: IdTokenVerifierOptions): IdTokenVerifier {
  // jose caches a remote JWKS (and honors its cache headers); one set per process.
  const googleKeys = options.googleKeys ?? createRemoteJWKSet(new URL(GOOGLE_JWKS_URL));
  const appleKeys = options.appleKeys ?? createRemoteJWKSet(new URL(APPLE_JWKS_URL));

  const reject = (provider: string, reason: string): null => {
    logMeta("id_token_rejected", { provider, reason });
    return null;
  };

  return {
    async verify(token, { providers, nonce, maxAgeSec, nowMs }) {
      if (typeof token !== "string" || token.length === 0 || token.length > MAX_ID_TOKEN_CHARS) return reject("unknown", "malformed");
      let iss: unknown;
      try {
        iss = decodeJwt(token).iss;
      } catch {
        return reject("unknown", "malformed");
      }
      let provider: IdentityProvider;
      if (typeof iss === "string" && GOOGLE_ISSUERS.includes(iss)) provider = "google";
      else if (iss === APPLE_ISSUER) provider = "apple";
      else if (typeof iss === "string" && options.testIdp !== null && iss === options.testIdp.issuer) provider = "test";
      else return reject("unknown", "issuer");
      if (!providers.includes(provider)) return reject(provider, "provider");

      const audiences =
        provider === "google" ? options.googleClientIds : provider === "apple" ? options.appleClientIds : [TEST_IDP_AUDIENCE];
      if (audiences.length === 0) return reject(provider, "audience");
      const keys = provider === "google" ? googleKeys : provider === "apple" ? appleKeys : options.testIdp!.keys;
      const issuers = provider === "google" ? [...GOOGLE_ISSUERS] : [provider === "apple" ? APPLE_ISSUER : options.testIdp!.issuer];
      const algorithms = provider === "test" ? ["ES256", "RS256"] : ["RS256"];

      let payload;
      try {
        ({ payload } = await jwtVerify(token, keys, {
          issuer: issuers,
          audience: [...audiences],
          algorithms,
          clockTolerance: CLOCK_TOLERANCE_SEC,
          currentDate: new Date(nowMs),
          requiredClaims: ["sub", "iat", "exp", "nonce", "email"],
        }));
      } catch (err) {
        return reject(provider, errorKind(err));
      }

      const nowSec = nowMs / 1000;
      const iat = payload.iat;
      if (typeof iat !== "number" || nowSec - iat > maxAgeSec || iat - nowSec > CLOCK_TOLERANCE_SEC) return reject(provider, "iat");
      const subject = payload.sub;
      if (typeof subject !== "string" || subject === "") return reject(provider, "subject");
      const expectedNonce = provider === "apple" ? sha256Hex(nonce) : nonce;
      if (typeof payload.nonce !== "string" || payload.nonce !== expectedNonce) return reject(provider, "nonce");
      const verified = provider === "apple" ? payload.email_verified === true || payload.email_verified === "true" : payload.email_verified === true;
      const email = typeof payload.email === "string" ? normalizeEmail(payload.email) : "";
      if (!verified || email === "") return reject(provider, "email");

      const aud = payload.aud;
      const audience = typeof aud === "string" ? aud : (aud ?? []).find((a: string) => audiences.includes(a)) ?? "";
      return {
        provider,
        subject,
        email,
        isPrivateEmail: provider === "apple" && (payload.is_private_email === true || payload.is_private_email === "true"),
        audience,
      };
    },
  };
}

/** Builds the process's verifier; reads the test provider's JWKS file only when one is configured. */
export function loadIdTokenVerifier(
  config: Pick<Config, "googleClientIds" | "appleClientIds" | "testIdp">,
  readFile: (path: string) => string = (p) => readFileSync(p, "utf8"),
): IdTokenVerifier {
  let testIdp: IdTokenVerifierOptions["testIdp"] = null;
  if (config.testIdp !== null) {
    try {
      const jwks = JSON.parse(readFile(config.testIdp.jwksPath)) as JSONWebKeySet;
      testIdp = { issuer: config.testIdp.issuer, keys: createLocalJWKSet(jwks) };
    } catch {
      throw new ConfigError("TEST_IDP_JWKS_PATH is not a readable JWKS file");
    }
  }
  return createIdTokenVerifier({ googleClientIds: config.googleClientIds, appleClientIds: config.appleClientIds, testIdp });
}

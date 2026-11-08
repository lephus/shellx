import { createPrivateKey, type KeyObject } from "node:crypto";
import { readFileSync } from "node:fs";
import { SignJWT } from "jose";
import { errorKind, logMeta } from "../log.js";
import { APPLE_ISSUER } from "./providers.js";

export const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
export const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";
export const APPLE_REST_TIMEOUT_MS = 5000;
export const APPLE_CLIENT_SECRET_TTL_SEC = 300;

export interface AppleSiwaKey {
  teamId: string;
  keyId: string;
  privateKeyPem: string;
}

/** Apple's REST side of Sign in with Apple. Neither method ever throws. */
export interface AppleTokenGateway {
  /** The refresh token for an authorization code, or null (a failed exchange never blocks a sign-in). */
  exchangeCode(clientId: string, code: string): Promise<string | null>;
  /** True when Apple revoked the refresh token. */
  revoke(clientId: string, refreshToken: string): Promise<boolean>;
}

function ecKey(pem: string): KeyObject {
  const key = createPrivateKey(pem);
  if (key.asymmetricKeyType !== "ec" || key.asymmetricKeyDetails?.namedCurve !== "prime256v1") {
    throw new Error("not an EC P-256 private key");
  }
  return key;
}

/** The ES256 JWT Apple takes as `client_secret` (S1 §6.2): iss team, sub bundle id, valid 300 s. */
export async function appleClientSecret(key: AppleSiwaKey, clientId: string, nowMs: number): Promise<string> {
  return signSecret(ecKey(key.privateKeyPem), key, clientId, nowMs);
}

function signSecret(keyObject: KeyObject, key: AppleSiwaKey, clientId: string, nowMs: number): Promise<string> {
  const nowSec = Math.floor(nowMs / 1000);
  return new SignJWT({ sub: clientId })
    .setProtectedHeader({ alg: "ES256", kid: key.keyId })
    .setIssuer(key.teamId)
    .setAudience(APPLE_ISSUER)
    .setIssuedAt(nowSec)
    .setExpirationTime(nowSec + APPLE_CLIENT_SECRET_TTL_SEC)
    .sign(keyObject);
}

export class AppleRestClient implements AppleTokenGateway {
  private readonly keyObject: KeyObject;
  private readonly fetchFn: typeof fetch;
  private readonly now: () => number;

  constructor(private readonly options: { key: AppleSiwaKey; fetch?: typeof fetch; now?: () => number }) {
    this.keyObject = ecKey(options.key.privateKeyPem);
    this.fetchFn = options.fetch ?? fetch;
    this.now = options.now ?? Date.now;
  }

  private async post(url: string, form: Record<string, string>, clientId: string): Promise<{ status: number; body: string }> {
    const client_secret = await signSecret(this.keyObject, this.options.key, clientId, this.now());
    const res = await this.fetchFn(url, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ client_id: clientId, client_secret, ...form }),
      signal: AbortSignal.timeout(APPLE_REST_TIMEOUT_MS),
    });
    return { status: res.status, body: await res.text() };
  }

  async exchangeCode(clientId: string, code: string): Promise<string | null> {
    try {
      const { status, body } = await this.post(APPLE_TOKEN_URL, { code, grant_type: "authorization_code" }, clientId);
      if (status === 200) {
        const refresh = (JSON.parse(body) as { refresh_token?: unknown }).refresh_token;
        if (typeof refresh === "string" && refresh !== "") return refresh;
      }
      logMeta("apple_token_exchange_failed", { status });
    } catch (err) {
      logMeta("apple_token_exchange_failed", { error: errorKind(err) });
    }
    return null;
  }

  async revoke(clientId: string, refreshToken: string): Promise<boolean> {
    try {
      const { status } = await this.post(APPLE_REVOKE_URL, { token: refreshToken, token_type_hint: "refresh_token" }, clientId);
      if (status === 200) return true;
      logMeta("apple_revoke_failed", { status });
    } catch (err) {
      logMeta("apple_revoke_failed", { error: errorKind(err) });
    }
    return false;
  }
}

export type AppleSiwaSetup = { gateway: AppleTokenGateway } | { gateway: null; reason: "not_configured" | "unreadable" | "invalid" };

/**
 * `APPLE_TEAM_ID`, `APPLE_SIWA_KEY_ID` and `APPLE_SIWA_KEY_PATH` (a `.p8`, mounted read-only). Any
 * missing, or a file that is not an EC P-256 key: no code exchange and no revocation; sign-in itself
 * keeps working.
 */
export function loadAppleSiwa(
  env: Readonly<Record<string, string | undefined>>, options: { readFile?: (path: string) => string; fetch?: typeof fetch } = {},
): AppleSiwaSetup {
  const path = env.APPLE_SIWA_KEY_PATH?.trim();
  const keyId = env.APPLE_SIWA_KEY_ID?.trim();
  const teamId = env.APPLE_TEAM_ID?.trim();
  if (!path || !keyId || !teamId) return { gateway: null, reason: "not_configured" };
  let pem: string;
  try {
    pem = (options.readFile ?? ((p) => readFileSync(p, "utf8")))(path);
  } catch {
    return { gateway: null, reason: "unreadable" };
  }
  try {
    return { gateway: new AppleRestClient({ key: { keyId, teamId, privateKeyPem: pem }, fetch: options.fetch }) };
  } catch {
    return { gateway: null, reason: "invalid" };
  }
}

/** Revokes each stored refresh token; never throws and never blocks the caller's own work. */
export async function revokeAppleTokens(
  gateway: AppleTokenGateway | null,
  rows: readonly { apple_client_id: string | null; apple_refresh_token: string | null }[],
): Promise<void> {
  for (const row of rows) {
    if (row.apple_refresh_token === null || row.apple_client_id === null) {
      logMeta("apple_revoke_skipped", { reason: "no_refresh_token" });
    } else if (gateway === null) {
      logMeta("apple_revoke_skipped", { reason: "not_configured" });
    } else {
      await gateway.revoke(row.apple_client_id, row.apple_refresh_token);
    }
  }
}

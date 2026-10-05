import { createPrivateKey, createSign } from "node:crypto";
import { errorKind, logMeta } from "../log.js";

/** One notification to one phone (push spec §5). */
export interface PushMessage {
  token: string;
  title: string;
  body: string;
  data: Readonly<Record<string, string>>;
}

/**
 * `ok`: FCM accepted it. `invalid_token`: FCM says the token is gone or malformed (UNREGISTERED /
 * INVALID_ARGUMENT) — the caller deletes it. `error`: anything else (logged by kind, not retried).
 */
export type PushResult = "ok" | "invalid_token" | "error";

/** What the notifications route needs; `FcmClient` in production, a fake in tests. */
export interface PushGateway {
  send(message: PushMessage): Promise<PushResult>;
}

/** The fields of a Google service account JSON key the relay uses. */
export interface ServiceAccount {
  projectId: string;
  clientEmail: string;
  /** PKCS#8 PEM ("-----BEGIN PRIVATE KEY-----"). */
  privateKey: string;
  tokenUri: string;
}

export const DEFAULT_TOKEN_URI = "https://oauth2.googleapis.com/token";
export const DEFAULT_FCM_ENDPOINT = "https://fcm.googleapis.com";
export const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

/** Lifetime asked for in the JWT assertion (Google's maximum). */
const ASSERTION_LIFETIME_S = 3600;
/** A cached access token is renewed this long before it expires. */
export const TOKEN_RENEW_MARGIN_MS = 60_000;
/** Each HTTP call to Google gives up after this long. */
export const FCM_TIMEOUT_MS = 10_000;

export class ServiceAccountError extends Error {
  override name = "ServiceAccountError";
}

/** Parses a service account key file; throws `ServiceAccountError` naming what is missing. */
export function parseServiceAccount(text: string): ServiceAccount {
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    throw new ServiceAccountError("not JSON");
  }
  if (typeof json !== "object" || json === null || Array.isArray(json)) throw new ServiceAccountError("not a JSON object");
  const v = json as Record<string, unknown>;
  const field = (name: string): string => {
    const value = v[name];
    if (typeof value !== "string" || value.trim() === "") throw new ServiceAccountError(`missing ${name}`);
    return value;
  };
  const projectId = field("project_id");
  const clientEmail = field("client_email");
  const privateKey = field("private_key");
  try {
    if (createPrivateKey(privateKey).asymmetricKeyType !== "rsa") throw new Error("not RSA");
  } catch {
    throw new ServiceAccountError("private_key is not an RSA private key");
  }
  const tokenUri = typeof v.token_uri === "string" && v.token_uri !== "" ? v.token_uri : DEFAULT_TOKEN_URI;
  if (!/^[a-z0-9-]+$/.test(projectId)) throw new ServiceAccountError("project_id is not a project id");
  return { projectId, clientEmail, privateKey, tokenUri };
}

function base64Url(data: string | Buffer): string {
  return Buffer.from(data).toString("base64url");
}

/** The signed RS256 JWT assertion for Google's OAuth token endpoint. */
export function signAssertion(account: ServiceAccount, audience: string, nowMs: number): string {
  const iat = Math.floor(nowMs / 1000);
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64Url(
    JSON.stringify({ iss: account.clientEmail, scope: FCM_SCOPE, aud: audience, iat, exp: iat + ASSERTION_LIFETIME_S }),
  );
  const signer = createSign("RSA-SHA256");
  signer.update(`${header}.${claims}`);
  return `${header}.${claims}.${signer.sign(account.privateKey).toString("base64url")}`;
}

export interface FcmClientOptions {
  account: ServiceAccount;
  /** Defaults to the global `fetch`. */
  fetch?: typeof fetch;
  /** Unix milliseconds. */
  now?: () => number;
  /** Base URL of the FCM API (tests point it at a local fake). */
  endpoint?: string;
  /** OAuth token URL; defaults to the service account's `token_uri`. */
  tokenEndpoint?: string;
}

interface CachedToken {
  value: string;
  expiresAt: number;
}

/** FCM error codes that mean "this token will never work again": the token is deleted. */
const INVALID_TOKEN_CODES = new Set(["UNREGISTERED", "INVALID_ARGUMENT"]);

/**
 * FCM HTTP v1 client (push spec §5): an OAuth access token from a JWT signed with the service
 * account's key (node:crypto, no Google library), cached until shortly before it expires, with at
 * most one token request in flight. Never logs tokens, titles or bodies.
 */
export class FcmClient implements PushGateway {
  private readonly fetch: typeof fetch;
  private readonly now: () => number;
  private readonly sendUrl: string;
  private readonly tokenUrl: string;
  private cached: CachedToken | null = null;
  private pending: Promise<string> | null = null;

  constructor(private readonly options: FcmClientOptions) {
    this.fetch = options.fetch ?? fetch;
    this.now = options.now ?? Date.now;
    const endpoint = (options.endpoint ?? DEFAULT_FCM_ENDPOINT).replace(/\/+$/, "");
    this.sendUrl = `${endpoint}/v1/projects/${options.account.projectId}/messages:send`;
    this.tokenUrl = options.tokenEndpoint ?? options.account.tokenUri;
  }

  async send(message: PushMessage): Promise<PushResult> {
    let accessToken: string;
    try {
      accessToken = await this.accessToken();
    } catch (err) {
      logMeta("fcm_token_failed", { error: errorKind(err) });
      return "error";
    }
    let res: Response;
    try {
      res = await this.fetch(this.sendUrl, {
        method: "POST",
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token: message.token,
            notification: { title: message.title, body: message.body },
            data: message.data,
            android: { priority: "high" },
            apns: { payload: { aps: { sound: "default" } } },
          },
        }),
        signal: AbortSignal.timeout(FCM_TIMEOUT_MS),
      });
    } catch (err) {
      logMeta("fcm_send_failed", { error: errorKind(err) });
      return "error";
    }
    if (res.ok) {
      await res.body?.cancel();
      return "ok";
    }
    const code = await fcmErrorCode(res);
    if (res.status === 401) this.cached = null; // a revoked or expired access token: fetch a new one next time
    if (code !== null && INVALID_TOKEN_CODES.has(code)) return "invalid_token";
    logMeta("fcm_send_failed", { status: res.status, error: code ?? "unknown" });
    return "error";
  }

  /** The cached access token, or a new one (one request at a time). */
  private async accessToken(): Promise<string> {
    const cached = this.cached;
    if (cached !== null && this.now() < cached.expiresAt - TOKEN_RENEW_MARGIN_MS) return cached.value;
    this.pending ??= this.fetchToken().finally(() => {
      this.pending = null;
    });
    return this.pending;
  }

  private async fetchToken(): Promise<string> {
    const issuedAt = this.now();
    const assertion = signAssertion(this.options.account, this.options.account.tokenUri, issuedAt);
    const res = await this.fetch(this.tokenUrl, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }).toString(),
      signal: AbortSignal.timeout(FCM_TIMEOUT_MS),
    });
    if (!res.ok) {
      await res.body?.cancel();
      throw Object.assign(new Error("token request refused"), { code: `HTTP_${res.status}` });
    }
    const json = (await res.json()) as { access_token?: unknown; expires_in?: unknown };
    if (typeof json.access_token !== "string" || json.access_token === "") {
      throw Object.assign(new Error("no access token"), { code: "BAD_TOKEN_RESPONSE" });
    }
    const lifetimeS = typeof json.expires_in === "number" && json.expires_in > 0 ? json.expires_in : ASSERTION_LIFETIME_S;
    this.cached = { value: json.access_token, expiresAt: issuedAt + lifetimeS * 1000 };
    return json.access_token;
  }
}

/**
 * The FCM error code of a failed send: `details[].errorCode` of the FcmError detail when present
 * (e.g. UNREGISTERED), else `error.status` (e.g. INVALID_ARGUMENT); null when the body says neither.
 */
async function fcmErrorCode(res: Response): Promise<string | null> {
  let json: unknown;
  try {
    json = await res.json();
  } catch {
    return null;
  }
  const error = (json as { error?: { status?: unknown; details?: unknown } } | null)?.error;
  if (typeof error !== "object" || error === null) return null;
  if (Array.isArray(error.details)) {
    for (const detail of error.details) {
      const code = (detail as { errorCode?: unknown } | null)?.errorCode;
      if (typeof code === "string" && /^[A-Z_]+$/.test(code)) return code;
    }
  }
  return typeof error.status === "string" && /^[A-Z_]+$/.test(error.status) ? error.status : null;
}

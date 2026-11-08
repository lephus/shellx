import { createPrivateKey, sign, type KeyObject } from "node:crypto";
import { readFileSync } from "node:fs";
import { connect, constants, type ClientHttp2Session } from "node:http2";
import { errorKind, logMeta } from "../log.js";
import type { PushResult } from "./fcm.js";

/** Which APNs host a device token belongs to: Debug builds get sandbox tokens, App Store builds production. */
export type ApnsEnvironment = "sandbox" | "production";

/** One push to one iPhone (Apple's "Sending notification requests to APNs"). */
export interface ApnsMessage {
  /** The device token, hex. */
  token: string;
  /** The app's bundle id. */
  topic: string;
  environment: ApnsEnvironment;
  /** `alert` shows something; `background` only wakes the app (`content-available`). */
  pushType: "alert" | "background";
  /** 10 delivers now; Apple requires 5 for a background push. */
  priority: 5 | 10;
  /** Replaces an earlier notification with the same id on the phone (at most 64 bytes). */
  collapseId?: string;
  /** Unix seconds after which APNs stops trying; absent: Apple's default. */
  expiresAtSec?: number;
  payload: Readonly<Record<string, unknown>>;
}

export interface ApnsGateway {
  send(message: ApnsMessage): Promise<PushResult>;
}

/** The provider key from Apple Developer › Keys (the `.p8` file), with its key id and the team id. */
export interface ApnsKey {
  keyId: string;
  teamId: string;
  privateKeyPem: string;
}

export interface ApnsRequest {
  origin: string;
  path: string;
  headers: Record<string, string>;
  body: string;
}

export type ApnsTransport = (request: ApnsRequest) => Promise<{ status: number; body: string }>;

export const APNS_ORIGINS: Readonly<Record<ApnsEnvironment, string>> = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
};
/** Apple refuses a provider token older than an hour and asks for at most one new one per 20 minutes. */
export const APNS_JWT_TTL_MS = 50 * 60 * 1000;
export const APNS_TIMEOUT_MS = 10_000;
/** Answers that mean the token is gone or not this app's: the relay deletes it. */
const INVALID_TOKEN_REASONS = new Set(["BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered"]);

/** 403 answers that mean the provider token, not the request, is the problem. */
const REFUSED_PROVIDER_TOKEN_REASONS = new Set(["ExpiredProviderToken", "InvalidProviderToken"]);

/**
 * APNs provider API client: an ES256 provider token signed with the `.p8` key (node:crypto), reused for
 * 50 minutes, over one HTTP/2 connection per host. Never logs tokens or payloads.
 */
export class ApnsClient implements ApnsGateway {
  private readonly key: KeyObject;
  private readonly transport: ApnsTransport;
  private readonly now: () => number;
  private cached: { value: string; signedAt: number } | null = null;

  constructor(private readonly options: { key: ApnsKey; transport?: ApnsTransport; now?: () => number }) {
    this.key = createPrivateKey(options.key.privateKeyPem);
    this.transport = options.transport ?? http2Transport();
    this.now = options.now ?? Date.now;
  }

  async send(message: ApnsMessage): Promise<PushResult> {
    let answer = await this.attempt(message);
    // An expired or refused provider token: sign a new one and retry this message once.
    if (answer !== null && answer.status === 403 && REFUSED_PROVIDER_TOKEN_REASONS.has(reasonOf(answer.body))) {
      this.cached = null;
      answer = await this.attempt(message);
    }
    if (answer === null) return "error";
    if (answer.status === 200) return "ok";
    const reason = reasonOf(answer.body);
    if (answer.status === 403) this.cached = null;
    if (answer.status === 410 || (answer.status === 400 && INVALID_TOKEN_REASONS.has(reason))) return "invalid_token";
    logMeta("apns_send_failed", { status: answer.status, error: reason || "unknown" });
    return "error";
  }

  /** One request to APNs; null when the connection failed. */
  private async attempt(message: ApnsMessage): Promise<{ status: number; body: string } | null> {
    const headers: Record<string, string> = {
      authorization: `bearer ${this.providerToken()}`,
      "apns-topic": message.topic,
      "apns-push-type": message.pushType,
      "apns-priority": String(message.priority),
      "content-type": "application/json",
    };
    if (message.collapseId !== undefined) headers["apns-collapse-id"] = message.collapseId;
    if (message.expiresAtSec !== undefined) headers["apns-expiration"] = String(message.expiresAtSec);
    try {
      return await this.transport({
        origin: APNS_ORIGINS[message.environment], path: `/3/device/${message.token}`, headers,
        body: JSON.stringify(message.payload),
      });
    } catch (err) {
      logMeta("apns_send_failed", { error: errorKind(err) });
      return null;
    }
  }

  private providerToken(): string {
    const now = this.now();
    if (this.cached !== null && now - this.cached.signedAt < APNS_JWT_TTL_MS) return this.cached.value;
    const header = base64url(JSON.stringify({ alg: "ES256", kid: this.options.key.keyId }));
    const claims = base64url(JSON.stringify({ iss: this.options.key.teamId, iat: Math.floor(now / 1000) }));
    const signature = sign("sha256", Buffer.from(`${header}.${claims}`), { key: this.key, dsaEncoding: "ieee-p1363" });
    this.cached = { value: `${header}.${claims}.${signature.toString("base64url")}`, signedAt: now };
    return this.cached.value;
  }
}

/** HTTP/2 to APNs: one session per origin, opened on first use and again after it closes or fails. */
export function http2Transport(options: { timeoutMs?: number } = {}): ApnsTransport & { close(): void } {
  const sessions = new Map<string, ClientHttp2Session>();
  const sessionFor = (origin: string): ClientHttp2Session => {
    const open = sessions.get(origin);
    if (open !== undefined && !open.closed && !open.destroyed) return open;
    const session = connect(origin);
    session.on("error", () => sessions.delete(origin));
    session.on("close", () => sessions.delete(origin));
    // An idle connection must not keep the relay process alive on shutdown.
    session.unref();
    sessions.set(origin, session);
    return session;
  };
  const transport = (request: ApnsRequest) =>
    new Promise<{ status: number; body: string }>((resolve, reject) => {
      const stream = sessionFor(request.origin).request({
        [constants.HTTP2_HEADER_METHOD]: "POST",
        [constants.HTTP2_HEADER_PATH]: request.path,
        ...request.headers,
      });
      let settled = false;
      const settle = (done: () => void) => {
        if (settled) return;
        settled = true;
        done();
      };
      let timedOut = false;
      stream.setTimeout(options.timeoutMs ?? APNS_TIMEOUT_MS, () => {
        timedOut = true;
        stream.close(constants.NGHTTP2_CANCEL);
      });
      let status = 0;
      let body = "";
      stream.setEncoding("utf8");
      stream.on("response", (headers) => (status = Number(headers[constants.HTTP2_HEADER_STATUS])));
      stream.on("data", (chunk: string) => (body += chunk));
      stream.on("end", () => settle(() => (status === 0 ? reject(new Error(timedOut ? "apns_timeout" : "apns_no_response")) : resolve({ status, body }))));
      stream.on("error", (err) => settle(() => reject(err)));
      // A stream closed locally (the timeout) emits only `close`: nothing settled yet means it timed out.
      stream.on("close", () => settle(() => reject(new Error("apns_timeout"))));
      stream.end(request.body);
    });
  return Object.assign(transport, {
    close: () => {
      for (const session of sessions.values()) session.close();
      sessions.clear();
    },
  });
}

/** Why push to iPhones is off: a variable missing, the key file unreadable, or not a private key. */
export type ApnsDisabledReason = "not_configured" | "unreadable" | "invalid";

export type ApnsSetup = { gateway: ApnsGateway } | { gateway: null; reason: ApnsDisabledReason };

/**
 * `APNS_KEY_PATH` (the `.p8` file, mounted read-only), `APNS_KEY_ID` and `APNS_TEAM_ID`. Any missing,
 * or a file that is not a key: push to iPhones is off, the relay keeps running and
 * `POST /v2/notifications` reaches Android phones only (503 `push_unavailable` when FCM is off too).
 */
export function loadApns(
  env: Readonly<Record<string, string | undefined>>, options: { readFile?: (path: string) => string } = {},
): ApnsSetup {
  const path = env.APNS_KEY_PATH?.trim();
  const keyId = env.APNS_KEY_ID?.trim();
  const teamId = env.APNS_TEAM_ID?.trim();
  if (!path || !keyId || !teamId) return { gateway: null, reason: "not_configured" };
  let pem: string;
  try {
    pem = (options.readFile ?? ((p) => readFileSync(p, "utf8")))(path);
  } catch {
    return { gateway: null, reason: "unreadable" };
  }
  try {
    return { gateway: new ApnsClient({ key: { keyId, teamId, privateKeyPem: pem } }) };
  } catch {
    return { gateway: null, reason: "invalid" };
  }
}

function base64url(text: string): string {
  return Buffer.from(text).toString("base64url");
}

function reasonOf(body: string): string {
  try {
    const reason = (JSON.parse(body) as { reason?: unknown }).reason;
    return typeof reason === "string" ? reason : "";
  } catch {
    return "";
  }
}

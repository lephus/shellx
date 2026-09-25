import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { createApp, type AppDeps } from "../src/app";
import type { RateLimiter, RateLimiters } from "../src/auth/rate-limit";

export const BASE = "http://relay.test";

export const allowAll: RateLimiter = { limit: async () => true };
export const unlimited: RateLimiters = { loginIp: allowAll, loginEmail: allowAll, registerIp: allowAll };

/** Fake limiter: allows `max` calls per key, then refuses; records every key it saw. */
export class CountingLimiter implements RateLimiter {
  readonly calls: string[] = [];
  private readonly counts = new Map<string, number>();
  constructor(private readonly max: number) {}
  async limit(key: string): Promise<boolean> {
    this.calls.push(key);
    const next = (this.counts.get(key) ?? 0) + 1;
    this.counts.set(key, next);
    return next <= this.max;
  }
}

export type TestApp = ReturnType<typeof createApp>;

export function makeApp(deps: AppDeps = {}): TestApp {
  return createApp({ limiters: () => unlimited, ...deps });
}

export interface CallOptions {
  body?: unknown;
  token?: string;
  ip?: string;
  headers?: Record<string, string>;
  /** Overrides individual bindings/vars for this request only. */
  bindings?: Partial<typeof env>;
}

export async function call(app: TestApp, method: string, path: string, options: CallOptions = {}): Promise<Response> {
  const headers = new Headers(options.headers);
  if (options.body !== undefined) headers.set("Content-Type", "application/json");
  if (options.token !== undefined) headers.set("Authorization", `Bearer ${options.token}`);
  headers.set("CF-Connecting-IP", options.ip ?? "203.0.113.7");
  const request = new Request(`${BASE}${path}`, {
    method,
    headers,
    body: options.body === undefined ? undefined : typeof options.body === "string" ? options.body : JSON.stringify(options.body),
  });
  const ctx = createExecutionContext();
  const response = await app.fetch(request, { ...env, ...options.bindings }, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}

export const PASSWORD = "correct horse battery";

export function randomEmail(): string {
  return `user-${crypto.randomUUID()}@example.com`;
}

export function randomPublicKey(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

export type Kind = "agent" | "mobile";

export function deviceBody(kind: Kind, overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    kind,
    name: kind === "agent" ? "MacBook-Pro" : "iPhone 16",
    platform: kind === "agent" ? "macos" : "ios",
    public_key: randomPublicKey(),
    ...overrides,
  };
}

export interface Session {
  userId: string;
  deviceId: string;
  token: string;
  publicKey: string;
}

export interface Account {
  email: string;
  password: string;
  agent: Session;
}

/** Registers a fresh account whose first device is an agent. */
export async function registerAccount(app: TestApp, email = randomEmail(), password = PASSWORD): Promise<Account> {
  const device = deviceBody("agent");
  const res = await call(app, "POST", "/v1/auth/register", { body: { email, password, device } });
  if (res.status !== 201) throw new Error(`register failed: ${res.status} ${await res.text()}`);
  const body = await res.json<{ user_id: string; device_id: string; token: string }>();
  return {
    email,
    password,
    agent: { userId: body.user_id, deviceId: body.device_id, token: body.token, publicKey: device.public_key as string },
  };
}

/** Logs in an additional device (new key unless `publicKey` is given). */
export async function loginDevice(app: TestApp, account: Account, kind: Kind, publicKey = randomPublicKey()): Promise<Session> {
  const res = await call(app, "POST", "/v1/auth/login", {
    body: { email: account.email, password: account.password, device: deviceBody(kind, { public_key: publicKey }) },
  });
  if (res.status !== 200) throw new Error(`login failed: ${res.status} ${await res.text()}`);
  const body = await res.json<{ user_id: string; device_id: string; token: string }>();
  return { userId: body.user_id, deviceId: body.device_id, token: body.token, publicKey };
}

/** POST /v1/pairings as `agentToken`, with a fresh agent-generated pairing id unless one is given. */
export async function pair(
  app: TestApp,
  agentToken: string,
  mobileId: string,
  pairingId: string = crypto.randomUUID(),
): Promise<Response> {
  return call(app, "POST", "/v1/pairings", { token: agentToken, body: { mobile_id: mobileId, pairing_id: pairingId } });
}

/** The `pairing_id` of the D1 row for (agent, mobile), or null when there is no row. */
export async function pairingIdOf(agentId: string, mobileId: string): Promise<string | null> {
  const row = await env.DB.prepare("SELECT pairing_id FROM pairings WHERE agent_id = ? AND mobile_id = ?")
    .bind(agentId, mobileId)
    .first<{ pairing_id: string }>();
  return row?.pairing_id ?? null;
}

export async function errorCode(res: Response): Promise<string> {
  const body = await res.json<{ error: { code: string; message: string } }>();
  return body.error.code;
}

export interface CloseInfo {
  code: number;
  reason: string;
}

/** Client end of a relay WebSocket with an awaitable message queue. */
export class TestSocket {
  private readonly queue: (Uint8Array | string)[] = [];
  private notify: (() => void) | null = null;
  readonly closed: Promise<CloseInfo>;

  constructor(readonly ws: WebSocket) {
    // With current compatibility dates the standard default is "blob"; frames are easier as bytes.
    ws.binaryType = "arraybuffer";
    ws.accept();
    ws.addEventListener("message", (event) => {
      this.queue.push(typeof event.data === "string" ? event.data : new Uint8Array(event.data as ArrayBuffer));
      this.notify?.();
    });
    this.closed = new Promise((resolve) => {
      ws.addEventListener("close", (event) => {
        resolve({ code: event.code, reason: event.reason });
        this.notify?.();
      });
    });
  }

  async next(timeoutMs = 2000): Promise<Uint8Array | string> {
    const deadline = Date.now() + timeoutMs;
    while (this.queue.length === 0) {
      const remaining = deadline - Date.now();
      if (remaining <= 0) throw new Error("timed out waiting for a message");
      await new Promise<void>((resolve) => {
        const timer = setTimeout(resolve, remaining);
        this.notify = () => {
          clearTimeout(timer);
          resolve();
        };
      });
      this.notify = null;
    }
    return this.queue.shift()!;
  }

  async nextBinary(timeoutMs = 2000): Promise<Uint8Array> {
    const message = await this.next(timeoutMs);
    if (typeof message === "string") throw new Error(`expected a binary frame, got text ${JSON.stringify(message)}`);
    return message;
  }

  /** Resolves if nothing arrives within `ms`; throws with the unexpected message otherwise. */
  async expectSilence(ms = 250): Promise<void> {
    await new Promise((resolve) => setTimeout(resolve, ms));
    if (this.queue.length > 0) throw new Error(`unexpected message: ${String(this.queue[0])}`);
  }

  send(data: Uint8Array | string): void {
    this.ws.send(data);
  }

  close(code = 1000): void {
    this.ws.close(code, "bye");
  }
}

export async function connect(app: TestApp, token: string | undefined): Promise<TestSocket> {
  const res = await call(app, "GET", "/v1/ws", { token, headers: { Upgrade: "websocket" } });
  if (res.status !== 101 || res.webSocket === null) throw new Error(`upgrade failed: ${res.status}`);
  return new TestSocket(res.webSocket);
}

export function hex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

export async function waitFor<T>(probe: () => Promise<T | null | undefined>, timeoutMs = 2000): Promise<T> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const value = await probe();
    if (value !== null && value !== undefined) return value;
    if (Date.now() > deadline) throw new Error("condition not met in time");
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
}

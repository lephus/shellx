import { mkdtempSync, rmSync } from "node:fs";
import http from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, expect } from "vitest";
import { WebSocket } from "ws";
import type { AppDeps } from "../src/app.js";
import type { Argon2Backend } from "../src/auth/password.js";
import type { RateLimiter, RateLimiters } from "../src/auth/rate-limit.js";
import type { Config } from "../src/config.js";
import { Db } from "../src/db/db.js";
import { migrate } from "../src/db/migrate.js";
import { HubRegistry } from "../src/hub/registry.js";
import type { HubSocket } from "../src/hub/user-hub.js";
import { type ListenOptions, startRelay, type RunningRelay } from "../src/relay.js";

// ---- configuration used by every test relay ---------------------------------------------------

export const TEST_CONFIG: Config = {
  host: "127.0.0.1",
  port: 0,
  dbPath: "unused-in-tests.db",
  minAgent: "1.0.0",
  minMobile: "1.0.0",
  latestAgentVersion: "1.0.0",
  macUrl: "https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg",
  winUrl: "https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe",
  rateLimitsEnabled: false,
};

export const allowAll: RateLimiter = { limit: async () => true };
export const unlimited: RateLimiters = { loginIp: allowAll, loginEmail: allowAll, registerIp: allowAll, upgradeIp: allowAll };

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

// ---- per-test environment: a temp directory with a migrated SQLite DB and a hub registry -------

interface TestEnv {
  dir: string;
  db: Db;
  hubs: HubRegistry;
  registries: HubRegistry[];
}

let current: TestEnv | null = null;
const cleanups: (() => unknown)[] = [];

function testEnv(): TestEnv {
  if (current === null) {
    const dir = mkdtempSync(join(tmpdir(), "shellx-relay-test-"));
    const db = Db.open(join(dir, "relay.db"));
    migrate(db);
    const hubs = new HubRegistry({ db });
    current = { dir, db, hubs, registries: [hubs] };
  }
  return current;
}

/** This test's database (created, and migrated, on first use). */
export function db(): Db {
  return testEnv().db;
}

/** This test's hub registry, shared by every app of the test (like the Durable Object namespace). */
export function hubs(): HubRegistry {
  return testEnv().hubs;
}

/** This test's temporary directory (deleted after the test). */
export function tempDir(): string {
  return testEnv().dir;
}

/** A second registry over this test's database (e.g. with a frozen clock); drained after the test. */
export function newHubRegistry(now?: () => number): HubRegistry {
  const env = testEnv();
  const registry = new HubRegistry({ db: env.db, now });
  env.registries.push(registry);
  return registry;
}

/** Runs `fn` after the current test, before its database is closed (last registered runs first). */
export function onCleanup(fn: () => unknown): void {
  cleanups.push(fn);
}

afterEach(async () => {
  for (const fn of cleanups.splice(0).reverse()) await fn();
  if (current === null) return;
  const env = current;
  current = null;
  // Server-side close events of the sockets just terminated still update last_seen_at.
  await Promise.race([
    Promise.all(env.registries.map((registry) => registry.whenEmpty())),
    new Promise((resolve) => setTimeout(resolve, 1000)),
  ]);
  env.db.close();
  rmSync(env.dir, { recursive: true, force: true });
});

// ---- test relays --------------------------------------------------------------------------------

/** A relay listening on a random 127.0.0.1 port; started in the background by `makeApp`. */
export interface TestApp {
  readonly ready: Promise<RunningRelay>;
}

/**
 * Starts a real relay (HTTP server + WebSocket upgrade) for this test, over the test's database and
 * hub registry, with rate limits off. `deps` overrides any dependency for this app only; `listen`
 * overrides listen options other than the address.
 */
export function makeApp(deps: Partial<AppDeps> = {}, listen: Partial<ListenOptions> = {}): TestApp {
  const ready = startRelay(
    { config: TEST_CONFIG, db: db(), hubs: hubs(), limiters: unlimited, ...deps },
    { ...listen, host: "127.0.0.1", port: 0 },
  );
  onCleanup(async () => {
    const relay = await ready;
    relay.server.closeAllConnections();
    await new Promise<void>((resolve) => relay.server.close(() => resolve()));
  });
  return { ready };
}

/** A buffered HTTP response (`json<T>()` is generic, like the Workers `Response` the tests were written for). */
export class TestResponse {
  constructor(
    readonly status: number,
    readonly headers: Headers,
    private readonly body: Buffer,
  ) {}

  async text(): Promise<string> {
    return this.body.toString("utf8");
  }

  async json<T = any>(): Promise<T> {
    return JSON.parse(this.body.toString("utf8")) as T;
  }
}

export interface CallOptions {
  body?: unknown;
  token?: string;
  /**
   * Sent as X-Real-IP (default 203.0.113.7; the test client connects from 127.0.0.1, a trusted
   * proxy address). `null` sends no X-Real-IP at all.
   */
  ip?: string | null;
  headers?: Record<string, string>;
}

/**
 * One HTTP request to the relay with `node:http` (fetch() refuses headers like `Upgrade`). A JSON
 * body gets `Content-Type: application/json` and a `Content-Length`; `chunks` sends a streamed
 * (chunked) body without one.
 */
export async function call(app: TestApp, method: string, path: string, options: CallOptions = {}): Promise<TestResponse> {
  const headers: Record<string, string> = { ...options.headers };
  if (options.token !== undefined) headers.Authorization = `Bearer ${options.token}`;
  if (options.ip !== null) headers["X-Real-IP"] = options.ip ?? "203.0.113.7";
  let body: Buffer | undefined;
  if (options.body !== undefined) {
    body = Buffer.from(typeof options.body === "string" ? options.body : JSON.stringify(options.body), "utf8");
    headers["Content-Type"] = "application/json";
    headers["Content-Length"] = String(body.length);
  }
  return request(app, method, path, headers, body === undefined ? [] : [body]);
}

/** Like `call`, but the body is streamed in `chunks` with no Content-Length (chunked encoding). */
export async function callStreamed(app: TestApp, method: string, path: string, chunks: Uint8Array[]): Promise<TestResponse> {
  return request(app, method, path, { "Content-Type": "application/json", "X-Real-IP": "203.0.113.7" }, chunks, (req) => {
    // The old Workers fixture asserted this on the Request object before sending it: prove this
    // harness genuinely exercises the no-Content-Length (counted-as-it-streams) code path too,
    // rather than accidentally taking the same fast path as a request with a known length.
    expect(req.getHeader("content-length")).toBeUndefined();
  });
}

async function request(
  app: TestApp, method: string, path: string, headers: Record<string, string>, chunks: Uint8Array[],
  onRequest?: (req: http.ClientRequest) => void,
): Promise<TestResponse> {
  const { port } = await app.ready;
  return new Promise((resolve, reject) => {
    const req = http.request({ host: "127.0.0.1", port, method, path, headers, agent: false }, (res) => {
      const received: Buffer[] = [];
      res.on("data", (chunk: Buffer) => received.push(chunk));
      res.on("end", () => {
        const responseHeaders = new Headers();
        for (const [name, value] of Object.entries(res.headers)) {
          if (value !== undefined) responseHeaders.set(name, Array.isArray(value) ? value.join(", ") : value);
        }
        resolve(new TestResponse(res.statusCode ?? 0, responseHeaders, Buffer.concat(received)));
      });
      res.on("error", reject);
    });
    onRequest?.(req);
    req.on("error", reject);
    for (const chunk of chunks) req.write(chunk);
    req.end();
  });
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

/** A UUIDv7 (RFC 9562) for unix-millisecond timestamp `ms`, lower case, random in the other bits. */
export function uuidv7(ms: number): string {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  for (let i = 0; i < 6; i++) bytes[i] = Math.floor(ms / 2 ** (8 * (5 - i))) % 256;
  bytes[6] = 0x70 | (bytes[6]! & 0x0f); // version 7
  bytes[8] = 0x80 | (bytes[8]! & 0x3f); // variant 10
  const h = hex(bytes);
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

let lastPairingMs = 0;
/** A pairing id as the agent generates it (UUIDv7), strictly newer than every one returned before. */
export function newPairingId(): string {
  lastPairingMs = Math.max(Date.now(), lastPairingMs + 1);
  return uuidv7(lastPairingMs);
}

/** POST /v1/pairings as `agentToken`, with a fresh agent-generated pairing id unless one is given. */
export async function pair(
  app: TestApp,
  agentToken: string,
  mobileId: string,
  pairingId: string = newPairingId(),
): Promise<TestResponse> {
  return call(app, "POST", "/v1/pairings", { token: agentToken, body: { mobile_id: mobileId, pairing_id: pairingId } });
}

/** The `pairing_id` of the row for (agent, mobile), or null when there is no row. */
export async function pairingIdOf(agentId: string, mobileId: string): Promise<string | null> {
  return db().get<{ pairing_id: string }>("SELECT pairing_id FROM pairings WHERE agent_id = ? AND mobile_id = ?", agentId, mobileId)
    ?.pairing_id ?? null;
}

export async function errorCode(res: TestResponse): Promise<string> {
  const body = await res.json<{ error: { code: string; message: string } }>();
  return body.error.code;
}

export interface CloseInfo {
  code: number;
  reason: string;
}

/** Client end of a relay WebSocket (the `ws` library) with an awaitable message queue. */
export class TestSocket {
  private readonly queue: (Uint8Array | string)[] = [];
  private notify: (() => void) | null = null;
  readonly closed: Promise<CloseInfo>;

  constructor(readonly ws: WebSocket) {
    ws.on("message", (data: Buffer, isBinary: boolean) => {
      this.queue.push(isBinary ? new Uint8Array(data) : data.toString("utf8"));
      this.notify?.();
    });
    ws.on("error", () => {
      // surfaced through `closed` (ws always emits "close" after "error")
    });
    this.closed = new Promise((resolve) => {
      ws.on("close", (code: number, reason: Buffer) => {
        resolve({ code, reason: reason.toString("utf8") });
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

function openSocket(relay: RunningRelay, headers: Record<string, string>): WebSocket {
  const ws = new WebSocket(`ws://127.0.0.1:${relay.port}/v1/ws`, { headers });
  onCleanup(() => ws.terminate());
  return ws;
}

/** Opens a real WebSocket to /v1/ws with `token`; throws `upgrade failed: <status>` if refused. */
export async function connect(app: TestApp, token: string | undefined, headers: Record<string, string> = {}): Promise<TestSocket> {
  const relay = await app.ready;
  const ws = openSocket(relay, { ...(token === undefined ? {} : { Authorization: `Bearer ${token}` }), ...headers });
  const socket = new TestSocket(ws); // listens before "open": the hub may send PRESENCE right away
  await new Promise<void>((resolve, reject) => {
    ws.once("open", () => resolve());
    ws.once("unexpected-response", (_req, res) => reject(new Error(`upgrade failed: ${res.statusCode}`)));
    ws.once("error", reject);
  });
  return socket;
}

/** The HTTP status a refused WebSocket upgrade got (101 means it was accepted, and is closed again). */
export async function upgradeStatus(app: TestApp, token: string | undefined, headers: Record<string, string> = {}): Promise<number> {
  const relay = await app.ready;
  const ws = openSocket(relay, { ...(token === undefined ? {} : { Authorization: `Bearer ${token}` }), ...headers });
  return new Promise((resolve) => {
    ws.once("open", () => {
      ws.terminate();
      resolve(101);
    });
    ws.once("unexpected-response", (_req, res) => {
      resolve(res.statusCode ?? 0);
      res.resume();
      ws.terminate();
    });
    ws.on("error", () => {
      // reported through the status above
    });
  });
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

/**
 * An argon2 backend whose operations finish only when the test says so (in start order), recording
 * how many ran at once and which passwords started, in order.
 */
export function gatedBackend() {
  const gates: (() => void)[] = [];
  const startedWith: string[] = [];
  let running = 0;
  let peak = 0;
  const run = async <T>(password: Uint8Array, value: T): Promise<T> => {
    running++;
    peak = Math.max(peak, running);
    startedWith.push(Buffer.from(password).toString("utf8"));
    await new Promise<void>((resolve) => gates.push(resolve));
    running--;
    return value;
  };
  const backend: Argon2Backend = {
    hash: (password) => run(password, "$argon2id$v=19$m=19456,t=2,p=1$c2FsdHNhbHRzYWx0c2FsdA$aGFzaA"),
    verify: (_phc, password) => run(password, true),
  };
  return {
    backend,
    /** Operations running right now (started and not yet released). */
    started: () => gates.length,
    startedWith: () => [...startedWith],
    peak: () => peak,
    releaseOne: () => gates.shift()?.(),
  };
}

/** In-memory stand-in for a `ws` socket: records what the hub sends and how it closes it. */
export class FakeSocket implements HubSocket {
  readyState = 1;
  /** Bytes queued but not yet written to the network (a slow receiver has a lot); set by tests. */
  bufferedAmount = 0;
  /**
   * Sends whose write has not completed yet, like `WsHubSocket`'s count: every `send` adds one and
   * nothing takes it back until the test calls `drain()` (the writes completed). Tests may also set
   * it directly (a stuck reader piles them up).
   */
  pendingSends = 0;
  readonly sent: (Uint8Array | string)[] = [];
  closedWith: { code: number; reason: string } | null = null;
  terminated = false;

  send(data: Uint8Array | string): void {
    if (this.readyState !== 1) throw new Error("socket is not open");
    this.sent.push(data);
    this.pendingSends++;
  }

  /** Every queued write completed (what `ws`'s send callbacks report for a socket that reads). */
  drain(): void {
    this.pendingSends = 0;
  }

  close(code: number, reason: string): void {
    if (this.readyState !== 1) return;
    this.closedWith = { code, reason };
    this.readyState = 2;
  }

  terminate(): void {
    this.terminated = true;
    this.readyState = 3;
  }

  /** Hex of every binary frame received so far, then forgets them. */
  take(): string[] {
    return this.sent.splice(0).map((m) => (typeof m === "string" ? `text:${m}` : hex(m)));
  }
}

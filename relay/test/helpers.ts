import { mkdtempSync, rmSync } from "node:fs";
import http from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach } from "vitest";
import type { AppDeps } from "../src/app.js";
import type { Config } from "../src/config.js";
import { Db } from "../src/db/db.js";
import { migrate } from "../src/db/migrate.js";
import type { HubSocket } from "../src/hub/user-hub.js";
import { startRelay, type RunningRelay } from "../src/relay.js";

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

// ---- per-test environment: a temp directory with a migrated SQLite DB -------------------------

interface TestEnv {
  dir: string;
  db: Db;
}

let current: TestEnv | null = null;
const cleanups: (() => unknown)[] = [];

function testEnv(): TestEnv {
  if (current === null) {
    const dir = mkdtempSync(join(tmpdir(), "shellx-relay-test-"));
    const db = Db.open(join(dir, "relay.db"));
    migrate(db);
    current = { dir, db };
  }
  return current;
}

/** This test's database (created, and migrated, on first use). */
export function db(): Db {
  return testEnv().db;
}

/** This test's temporary directory (deleted after the test). */
export function tempDir(): string {
  return testEnv().dir;
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
  env.db.close();
  rmSync(env.dir, { recursive: true, force: true });
});

// ---- test relays --------------------------------------------------------------------------------

/** A relay listening on a random 127.0.0.1 port; started in the background by `makeApp`. */
export interface TestApp {
  readonly ready: Promise<RunningRelay>;
}

/**
 * Starts a real relay (HTTP server) for this test, over the test's database. `deps` overrides any
 * dependency for this app only.
 */
export function makeApp(deps: Partial<AppDeps> = {}): TestApp {
  const ready = startRelay({ config: TEST_CONFIG, db: db(), ...deps }, { host: "127.0.0.1", port: 0 });
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
  return request(app, method, path, { "Content-Type": "application/json", "X-Real-IP": "203.0.113.7" }, chunks);
}

async function request(
  app: TestApp, method: string, path: string, headers: Record<string, string>, chunks: Uint8Array[],
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

/** In-memory stand-in for a `ws` socket: records what the hub sends and how it closes it. */
export class FakeSocket implements HubSocket {
  readyState = 1;
  readonly sent: (Uint8Array | string)[] = [];
  closedWith: { code: number; reason: string } | null = null;
  terminated = false;

  send(data: Uint8Array | string): void {
    if (this.readyState !== 1) throw new Error("socket is not open");
    this.sent.push(data);
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

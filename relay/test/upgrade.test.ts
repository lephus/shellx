import { once } from "node:events";
import { IncomingMessage } from "node:http";
import { createConnection, type Socket } from "node:net";
import { describe, expect, it } from "vitest";
import { type RateLimiter, SlidingWindowLimiter, UPGRADES_PER_IP } from "../src/auth/rate-limit.js";
import { connect, makeApp, registerAccount, type TestApp, unlimited, upgradeStatus, waitFor } from "./helpers.js";

// Residual R2: a WebSocket upgrade reset (RST) while its valid token was still being checked leaked
// @hono/node-server's pending waiter for the socket; and nothing limited upgrades per IP.

/** A limiter that allows everything; while `hold` is set, each call first waits for `release()`. */
class GatedLimiter implements RateLimiter {
  hold = false;
  calls = 0;
  private readonly waiting: (() => void)[] = [];

  async limit(): Promise<boolean> {
    this.calls++;
    if (this.hold) await new Promise<void>((resolve) => this.waiting.push(resolve));
    return true;
  }

  release(): void {
    for (const resolve of this.waiting.splice(0)) resolve();
  }
}

/**
 * Runs `during` with Map.prototype.set patched just long enough to spot @hono/node-server's map of
 * pending WebSocket waiters (2.1.1: keyed by the upgrade's IncomingMessage, each value carrying the
 * connection's `connectionSymbol`), and returns that map so the test can count what it still holds.
 */
async function adaptorWaiters(during: () => Promise<void>): Promise<Map<unknown, unknown>> {
  const original = Map.prototype.set;
  let found: Map<unknown, unknown> | null = null;
  Map.prototype.set = function (this: Map<unknown, unknown>, key: unknown, value: unknown) {
    if (found === null && key instanceof IncomingMessage && typeof value === "object" && value !== null && "connectionSymbol" in value) {
      found = this;
    }
    return original.call(this, key, value);
  };
  try {
    await during();
  } finally {
    Map.prototype.set = original;
  }
  if (found === null) throw new Error("the adaptor's waiter map was not found: did @hono/node-server change?");
  return found;
}

function upgradeRequest(token: string): string {
  return (
    "GET /v1/ws HTTP/1.1\r\nHost: relay.shellx.pro\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n" +
    `Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nAuthorization: Bearer ${token}\r\n\r\n`
  );
}

async function relayPort(app: TestApp) {
  return (await app.ready).port;
}

describe("per-IP WebSocket upgrade limit (R2)", () => {
  it("answers the 61st upgrade from one IP within 60 s with 429, valid token or not; other IPs are unaffected", async () => {
    const frozen = 1_900_000_000_000;
    const upgradeIp = new SlidingWindowLimiter({ limit: UPGRADES_PER_IP, now: () => frozen });
    const app = makeApp({ limiters: { ...unlimited, upgradeIp } });
    const account = await registerAccount(app);
    const ip = { "X-Real-IP": "198.51.100.7" };
    for (let i = 0; i < UPGRADES_PER_IP; i++) {
      const valid = i % 2 === 0; // bad tokens count too: the limit runs before the token check
      expect(await upgradeStatus(app, valid ? account.agent.token : "A".repeat(43), ip)).toBe(valid ? 101 : 401);
    }
    expect(await upgradeStatus(app, account.agent.token, ip)).toBe(429);
    expect(await upgradeStatus(app, "A".repeat(43), ip)).toBe(429);
    expect(await upgradeStatus(app, account.agent.token, { "X-Real-IP": "198.51.100.8" })).toBe(101);
  });
});

describe("a reset during the upgrade's token check (R2)", () => {
  it("leaves no pending adaptor waiter behind, however many times a valid-token client does it", async () => {
    const gate = new GatedLimiter();
    const app = makeApp({ limiters: { ...unlimited, upgradeIp: gate } });
    const account = await registerAccount(app);
    const relay = await app.ready;
    const serverSockets: Socket[] = [];
    const closes = new Map<Socket, number>(); // 'close' events seen on each accepted connection
    relay.server.on("connection", (socket: Socket) => {
      serverSockets.push(socket);
      closes.set(socket, 0);
      socket.on("close", () => closes.set(socket, closes.get(socket)! + 1));
    });

    // One normal upgrade finds the adaptor's waiter map; `ws` takes its socket over.
    const waiters = await adaptorWaiters(async () => {
      const normal = await connect(app, account.agent.token);
      normal.close();
      await normal.closed;
    });
    const normalSocket = serverSockets[0]!;
    await waitFor(async () => (closes.get(normalSocket)! > 0 ? true : null));
    expect(waiters.size).toBe(0);

    let created = 0;
    const set = waiters.set.bind(waiters);
    waiters.set = (key: unknown, value: unknown) => {
      created++;
      return set(key, value);
    };

    gate.hold = true;
    const ATTEMPTS = 5;
    for (let i = 0; i < ATTEMPTS; i++) {
      const client = createConnection(await relayPort(app), "127.0.0.1");
      client.on("error", () => {});
      await once(client, "connect");
      client.write(upgradeRequest(account.agent.token));
      await waitFor(async () => (gate.calls === 2 + i ? true : null)); // held inside the upgrade's checks
      const server = serverSockets.at(-1)!;
      client.resetAndDestroy();
      await waitFor(async () => (closes.get(server)! > 0 ? true : null)); // the relay saw the reset...
      gate.release(); // ...before the (valid) token check finished: the adaptor now expects `ws`
      await waitFor(async () => (created === i + 1 ? true : null));
      await new Promise((resolve) => setImmediate(resolve));
      expect(waiters.size).toBe(0);
      expect(closes.get(server)).toBeLessThanOrEqual(2); // the real close, plus at most one re-emitted
    }
    expect(closes.get(normalSocket)).toBe(1); // a socket that `ws` took over never gets an extra close

    gate.hold = false;
    const alive = await connect(app, account.agent.token);
    alive.send("ping");
    expect(await alive.next()).toBe("pong");
  });
});

import { type ChildProcess, spawn } from "node:child_process";
import { createServer } from "node:net";
import { describe, expect, it } from "vitest";
import { WebSocket } from "ws";
import { formatResult, runRelay2Smoke } from "../scripts/relay2-smoke.js";
import {
  approvePairing, call, loginDesktop, makeApp, onCleanup, registerAccount, registerMachine, requestPairing,
  TEST_CONFIG, type Session, type TestApp,
} from "./helpers.js";

const BIN = process.env.CMUX_RELAY_BIN;
const SECRET = "0123456789abcdef0123456789abcdef";
const OTHER_SECRET = "fedcba9876543210fedcba9876543210";

async function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const s = createServer();
    s.once("error", reject);
    s.listen(0, "127.0.0.1", () => {
      const { port } = s.address() as { port: number };
      s.close(() => resolve(port));
    });
  });
}

async function startCmuxRelay(): Promise<number> {
  const port = await freePort();
  const child: ChildProcess = spawn(BIN!, ["serve"], {
    env: { CMUX_RELAY_HMAC_SECRET: SECRET, CMUX_RELAY_ISSUER: "shellx-relay", CMUX_RELAY_BIND: `127.0.0.1:${port}` },
    stdio: "ignore",
  });
  let exited = false;
  child.once("exit", () => { exited = true; });
  onCleanup(() => { if (!exited) child.kill("SIGKILL"); });
  const deadline = Date.now() + 10_000;
  for (;;) {
    if (exited) throw new Error("cmux-relay exited before it was healthy");
    try {
      const res = await fetch(`http://127.0.0.1:${port}/healthz`);
      if (res.ok) return port;
    } catch { /* not listening yet */ }
    if (Date.now() > deadline) throw new Error("cmux-relay did not become healthy");
    await new Promise((r) => setTimeout(r, 50));
  }
}

/** A WebSocket to the relay with a message queue; `next()` resolves with the next JSON text frame. */
function open(port: number): Promise<{ send(msg: unknown): void; next(): Promise<Record<string, unknown>> }> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${port}/v1/relay`);
    const queue: Record<string, unknown>[] = [];
    const waiters: ((m: Record<string, unknown>) => void)[] = [];
    ws.on("message", (data, isBinary) => {
      if (isBinary) return;
      const msg = JSON.parse(data.toString()) as Record<string, unknown>;
      const w = waiters.shift();
      if (w) w(msg); else queue.push(msg);
    });
    ws.once("error", reject);
    onCleanup(() => ws.terminate());
    ws.once("open", () => resolve({
      send: (m) => ws.send(JSON.stringify(m)),
      next: () => new Promise((res, rej) => {
        const q = queue.shift();
        if (q) { res(q); return; }
        const t = setTimeout(() => rej(new Error("no relay message within 5 s")), 5000);
        waiters.push((m) => { clearTimeout(t); res(m); });
      }),
    }));
  });
}

interface Desk { session: Session; machineId: string; slot: string }

async function world(app: TestApp) {
  const account = await registerAccount(app);
  const desk = async (): Promise<Desk> => {
    const session = await loginDesktop(app, account);
    const m = await registerMachine(app, session.token);
    return { session, machineId: m.machine_id, slot: m.slot };
  };
  const a = await desk(); // target
  const b = await desk(); // requester
  const { pairing_id } = await requestPairing(app, b.session.token, b.machineId, a.machineId);
  await approvePairing(app, a.session.token, pairing_id);
  return { a, b };
}

async function ticket(app: TestApp, d: Desk, body: Record<string, unknown>): Promise<string> {
  const res = await call(app, "POST", "/v2/relay/tickets", { token: d.session.token, body: { machine_id: d.machineId, ...body } });
  if (res.status !== 200) throw new Error(`mint failed: ${res.status}`);
  return (await res.json<{ ticket: string }>()).ticket;
}

const registerTicket = (app: TestApp, a: Desk) => ticket(app, a, { permission: "register" });
const connectTicket = (app: TestApp, b: Desk, a: Desk) =>
  ticket(app, b, { permission: "connect", target_machine_id: a.machineId });

const connectMsg = (slot: string, t: string) => ({ type: "connect", protocol: 5, slot, ticket: t, lane: "control", generation: 1 });
const registerMsg = (slot: string, t: string) => ({ type: "register", protocol: 5, slot, ticket: t });

function flipLast(t: string): string {
  return t.slice(0, -1) + (t.endsWith("A") ? "B" : "A");
}

async function setup(config: Partial<typeof TEST_CONFIG> = {}, now?: () => number) {
  const port = await startCmuxRelay();
  const relayV2Url = `ws://127.0.0.1:${port}/v1/relay`;
  const app = makeApp({ config: { ...TEST_CONFIG, relayV2Url, ...config }, ...(now ? { now } : {}) });
  await app.ready;
  const w = await world(app);
  return { port, app, ...w };
}

describe.skipIf(BIN === undefined)("API-minted tickets against the real cmux-relay", () => {
  it("register ticket from the API is accepted", async () => {
    const { port, app, a } = await setup();
    const ws = await open(port);
    ws.send(registerMsg(a.slot, await registerTicket(app, a)));
    expect(await ws.next()).toMatchObject({ type: "registered", lease_seconds: 30 });
  });

  it("connect ticket from the API reaches the registered daemon", async () => {
    const { port, app, a, b } = await setup();
    const daemon = await open(port);
    daemon.send(registerMsg(a.slot, await registerTicket(app, a)));
    expect((await daemon.next()).type).toBe("registered");
    const client = await open(port);
    client.send(connectMsg(a.slot, await connectTicket(app, b, a)));
    expect((await client.next()).type).toBe("allocated");
    expect((await daemon.next()).type).toBe("incoming");
  });

  it("a tampered ticket is refused", async () => {
    const { port, app, a } = await setup();
    const ws = await open(port);
    ws.send(registerMsg(a.slot, flipLast(await registerTicket(app, a))));
    expect(await ws.next()).toMatchObject({ type: "error", code: "invalid-ticket" });
  });

  it("a register ticket cannot connect", async () => {
    const { port, app, a } = await setup();
    const ws = await open(port);
    ws.send(connectMsg(a.slot, await registerTicket(app, a)));
    expect(await ws.next()).toMatchObject({ type: "error", code: "invalid-ticket" });
  });

  it("a ticket signed with another secret is refused", async () => {
    const { port, a } = await setup();
    const other = makeApp({ config: { ...TEST_CONFIG, relayHmacSecret: new TextEncoder().encode(OTHER_SECRET) } });
    await other.ready;
    const account = await registerAccount(other);
    const session = await loginDesktop(other, account);
    const m = await registerMachine(other, session.token);
    const foreign = await ticket(other, { session, machineId: m.machine_id, slot: m.slot }, { permission: "register" });
    const ws = await open(port);
    ws.send(registerMsg(a.slot, foreign));
    expect(await ws.next()).toMatchObject({ type: "error", code: "invalid-ticket" });
  });

  it("an expired ticket is refused", async () => {
    const { port, app, a } = await setup({}, () => Date.now() - 200_000);
    const ws = await open(port);
    ws.send(registerMsg(a.slot, await registerTicket(app, a)));
    expect((await ws.next()).type).toBe("error");
  });

  it("the relay2 smoke script registers against the real cmux-relay and cleans up", async () => {
    const port = await startCmuxRelay();
    const app = makeApp({ config: { ...TEST_CONFIG, relayV2Url: `ws://127.0.0.1:${port}/v1/relay` } });
    const running = await app.ready;
    const account = await registerAccount(app);
    const result = await runRelay2Smoke({ base: running.url, email: account.email, password: account.password });
    expect(result).toEqual({ ok: true, lease: 30 });
    expect(formatResult(result)).toBe("relay2 smoke: OK (registered, lease 30 s)");
    const bad = await runRelay2Smoke({ base: running.url, email: account.email, password: "wrong password!" });
    expect(formatResult(bad)).toMatch(/^relay2 smoke: FAIL at login \(401 /);
  });
});

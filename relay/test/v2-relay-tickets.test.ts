import { afterEach, describe, expect, it, vi } from "vitest";
import { mintTicket } from "../src/v2/tickets.js";
import {
  approvePairing, call, CountingLimiter, errorCode, loginDesktop, loginDevice, makeApp, registerAccount,
  registerMachine, requestPairing, TEST_CONFIG, unlimited, type Session, type TestApp,
} from "./helpers.js";

const SECRET = new TextEncoder().encode("0123456789abcdef0123456789abcdef");
const CLOCK = 1_760_000_000_500;

interface Desk { session: Session; machineId: string; slot: string }

async function setup(app: TestApp) {
  const account = await registerAccount(app);
  const desk = async (acc = account): Promise<Desk> => {
    const session = await loginDesktop(app, acc);
    const m = await registerMachine(app, session.token);
    return { session, machineId: m.machine_id, slot: m.slot };
  };
  const a = await desk();
  const b = await desk();
  const c = await desk();
  const d = await desk(await registerAccount(app));
  return { account, a, b, c, d };
}

function mint(app: TestApp, token: string, body: Record<string, unknown>) {
  return call(app, "POST", "/v2/relay/tickets", { token, body });
}

function claimsOf(ticket: string): Record<string, unknown> {
  return JSON.parse(Buffer.from(ticket.split(".")[1]!, "base64url").toString("utf8")) as Record<string, unknown>;
}

afterEach(() => vi.restoreAllMocks());

describe("register", () => {
  it("mints a daemon ticket for the caller's own slot", async () => {
    const app = makeApp({ now: () => CLOCK });
    const { a } = await setup(app);
    const res = await mint(app, a.session.token, { machine_id: a.machineId, permission: "register" });
    expect(res.status).toBe(200);
    const body = await res.json<{ ticket: string; expires_at_unix: number; relay_url: string }>();
    expect(Object.keys(body).sort()).toEqual(["expires_at_unix", "relay_url", "ticket"]);
    expect(body.expires_at_unix).toBe(Math.floor(CLOCK / 1000) + 120);
    expect(body.relay_url).toBe(TEST_CONFIG.relayV2Url);
    const claims = claimsOf(body.ticket);
    expect(claims).toMatchObject({ permission: "register", role: "daemon", slot: a.slot, issuer: "shellx-relay" });
    expect(body.ticket).toBe(mintTicket(SECRET, claims as never));
  });

  it("refuses another machine of the account (403), another account's (404) and a bad permission (400)", async () => {
    const app = makeApp({ now: () => CLOCK });
    const { a, c, d } = await setup(app);
    const other = await mint(app, a.session.token, { machine_id: c.machineId, permission: "register" });
    expect(other.status).toBe(403);
    expect(await errorCode(other)).toBe("forbidden");
    const foreign = await mint(app, a.session.token, { machine_id: d.machineId, permission: "register" });
    expect(foreign.status).toBe(404);
    expect(await errorCode(foreign)).toBe("machine_not_found");
    expect((await mint(app, a.session.token, { machine_id: a.machineId, permission: "join" })).status).toBe(400);
    expect((await mint(app, a.session.token, { machine_id: a.machineId })).status).toBe(400);
  });
});

describe("connect", () => {
  it("needs a grant, then uses the target's slot as a client", async () => {
    const app = makeApp({ now: () => CLOCK });
    const { a, b } = await setup(app);
    const body = { machine_id: a.machineId, permission: "connect", target_machine_id: b.machineId };
    const denied = await mint(app, a.session.token, body);
    expect(denied.status).toBe(403);
    expect(await errorCode(denied)).toBe("not_granted");

    const { pairing_id } = await requestPairing(app, a.session.token, a.machineId, b.machineId);
    await approvePairing(app, b.session.token, pairing_id);
    const ok = await mint(app, a.session.token, body);
    expect(ok.status).toBe(200);
    const claims = claimsOf((await ok.json<{ ticket: string }>()).ticket);
    expect(claims).toMatchObject({ permission: "connect", role: "client", slot: b.slot });
    // The grant is one way.
    const back = await mint(app, b.session.token, { machine_id: b.machineId, permission: "connect", target_machine_id: a.machineId });
    expect(back.status).toBe(403);
  });

  it("stops after the target rotates its key", async () => {
    const app = makeApp({ now: () => CLOCK });
    const { a, b } = await setup(app);
    const { pairing_id } = await requestPairing(app, a.session.token, a.machineId, b.machineId);
    await approvePairing(app, b.session.token, pairing_id);
    const body = { machine_id: a.machineId, permission: "connect", target_machine_id: b.machineId };
    expect((await mint(app, a.session.token, body)).status).toBe(200);
    await registerMachine(app, b.session.token); // new random key
    expect((await mint(app, a.session.token, body)).status).toBe(403);
  });

  it("answers 404 after the target is deleted, 400 without a target", async () => {
    const app = makeApp({ now: () => CLOCK });
    const { a, b, d } = await setup(app);
    const body = { machine_id: a.machineId, permission: "connect", target_machine_id: b.machineId };
    expect((await mint(app, a.session.token, { machine_id: a.machineId, permission: "connect" })).status).toBe(400);
    expect((await mint(app, a.session.token, { ...body, target_machine_id: d.machineId })).status).toBe(404);
    expect((await call(app, "DELETE", `/v2/machines/${b.machineId}`, { token: a.session.token })).status).toBe(204);
    const gone = await mint(app, a.session.token, body);
    expect(gone.status).toBe(404);
    expect(await errorCode(gone)).toBe("machine_not_found");
  });

  it("lets a machine connect to itself without a grant (D3), with its own slot", async () => {
    const app = makeApp({ now: () => CLOCK });
    const { a } = await setup(app);
    const res = await mint(app, a.session.token, { machine_id: a.machineId, permission: "connect", target_machine_id: a.machineId });
    expect(res.status).toBe(200);
    expect(claimsOf((await res.json<{ ticket: string }>()).ticket)).toMatchObject({ role: "client", slot: a.slot });
  });

  it("never takes the slot from the body", async () => {
    const app = makeApp({ now: () => CLOCK });
    const { a, c } = await setup(app);
    const res = await mint(app, a.session.token, { machine_id: a.machineId, permission: "register", slot: c.slot });
    expect(claimsOf((await res.json<{ ticket: string }>()).ticket).slot).toBe(a.slot);
  });
});

describe("guards", () => {
  it("answers 503 when relay v2 is not configured", async () => {
    const app = makeApp({ config: { ...TEST_CONFIG, relayHmacSecret: null, relayV2DisabledReason: "missing_secret" } });
    const { a } = await setup(app);
    const res = await mint(app, a.session.token, { machine_id: a.machineId, permission: "register" });
    expect(res.status).toBe(503);
    expect(await errorCode(res)).toBe("relay_v2_unavailable");
  });

  it("limits minting per device", async () => {
    const limiter = new CountingLimiter(1);
    const app = makeApp({ limiters: { ...unlimited, ticketMint: limiter } });
    const { a } = await setup(app);
    const body = { machine_id: a.machineId, permission: "register" };
    expect((await mint(app, a.session.token, body)).status).toBe(200);
    expect((await mint(app, a.session.token, body)).status).toBe(429);
    expect(limiter.calls).toEqual([a.session.deviceId, a.session.deviceId]);
  });

  it("refuses an agent token and no token", async () => {
    const app = makeApp();
    const { account, a } = await setup(app);
    const agent = await loginDevice(app, account, "agent");
    const res = await mint(app, agent.token, { machine_id: a.machineId, permission: "register" });
    expect(res.status).toBe(403);
    expect(await errorCode(res)).toBe("desktop_only");
    expect((await call(app, "POST", "/v2/relay/tickets", { body: {} })).status).toBe(401);
  });

  it("does not log the ticket, the slot or any v2. prefix", async () => {
    const app = makeApp({ now: () => CLOCK });
    const { a, b } = await setup(app);
    const lines: string[] = [];
    vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => { lines.push(args.map(String).join(" ")); });
    vi.spyOn(console, "error").mockImplementation((...args: unknown[]) => { lines.push(args.map(String).join(" ")); });
    const res = await mint(app, a.session.token, { machine_id: a.machineId, permission: "register" });
    const { ticket } = await res.json<{ ticket: string }>();
    expect(lines.some((l) => l.includes("relay_ticket"))).toBe(true);
    for (const line of lines) {
      expect(line).not.toContain(ticket);
      expect(line).not.toContain(a.slot);
      expect(line).not.toContain(b.slot);
      expect(line).not.toContain("v2.");
    }
  });
});

import { afterEach, describe, expect, it, vi } from "vitest";
import {
  approvePairing, call, errorCode, loginDesktop, makeApp, registerAccount, registerMachine,
  requestPairing, type TestApp,
} from "./helpers.js";

const CLOCK = 1_760_000_000_500;

async function desk(app: TestApp, account: Awaited<ReturnType<typeof registerAccount>>) {
  const session = await loginDesktop(app, account);
  const m = await registerMachine(app, session.token);
  return { session, machineId: m.machine_id, slot: m.slot, linkSlot: m.link_slot };
}

function mint(app: TestApp, token: string, body: Record<string, unknown>) {
  return call(app, "POST", "/v2/relay/tickets", { token, body });
}

function claimsOf(ticket: string): Record<string, unknown> {
  return JSON.parse(Buffer.from(ticket.split(".")[1]!, "base64url").toString("utf8")) as Record<string, unknown>;
}

afterEach(() => vi.restoreAllMocks());

describe("link_slot", () => {
  it("is a 22 char slot distinct from slot and stable across re-registration", async () => {
    const app = makeApp({ now: () => CLOCK });
    const account = await registerAccount(app);
    const session = await loginDesktop(app, account);
    const first = await call(app, "POST", "/v2/machines", {
      token: session.token,
      body: { name: "Mac", platform: "macos", os_version: "15.2", app_version: "1.0.0", noise_public_key_b64: Buffer.alloc(32, 7).toString("base64") },
    });
    expect(first.status).toBe(201);
    const a = await first.json<{ slot: string; link_slot: string }>();
    expect(a.link_slot).toMatch(/^[A-Za-z0-9_-]{22}$/);
    expect(a.link_slot).not.toBe(a.slot);
    const again = await registerMachine(app, session.token);
    expect(again.link_slot).toBe(a.link_slot);
    expect(again.slot).toBe(a.slot);
  });
});

describe("lane link tickets", () => {
  it("uses link_slot for register and for connecting to itself", async () => {
    const app = makeApp({ now: () => CLOCK });
    const a = await desk(app, await registerAccount(app));
    const reg = await mint(app, a.session.token, { machine_id: a.machineId, permission: "register", lane: "link" });
    expect(reg.status).toBe(200);
    expect(claimsOf((await reg.json<{ ticket: string }>()).ticket)).toMatchObject({ role: "daemon", slot: a.linkSlot });
    const self = await mint(app, a.session.token, { machine_id: a.machineId, permission: "connect", target_machine_id: a.machineId, lane: "link" });
    expect(claimsOf((await self.json<{ ticket: string }>()).ticket)).toMatchObject({ role: "client", slot: a.linkSlot });
    const plain = await mint(app, a.session.token, { machine_id: a.machineId, permission: "register" });
    expect(claimsOf((await plain.json<{ ticket: string }>()).ticket)).toMatchObject({ slot: a.slot });
  });

  it("rejects any other lane with 400", async () => {
    const app = makeApp({ now: () => CLOCK });
    const a = await desk(app, await registerAccount(app));
    for (const lane of ["terminal", "", null, 1, "LINK"]) {
      const res = await mint(app, a.session.token, { machine_id: a.machineId, permission: "register", lane });
      expect(res.status).toBe(400);
    }
  });

  it("needs a grant for another machine, then uses its link_slot", async () => {
    const app = makeApp({ now: () => CLOCK });
    const account = await registerAccount(app);
    const a = await desk(app, account);
    const b = await desk(app, account);
    const body = { machine_id: a.machineId, permission: "connect", target_machine_id: b.machineId, lane: "link" };
    const denied = await mint(app, a.session.token, body);
    expect(denied.status).toBe(403);
    expect(await errorCode(denied)).toBe("not_granted");
    const { pairing_id } = await requestPairing(app, a.session.token, a.machineId, b.machineId);
    await approvePairing(app, b.session.token, pairing_id);
    const ok = await mint(app, a.session.token, body);
    expect(ok.status).toBe(200);
    expect(claimsOf((await ok.json<{ ticket: string }>()).ticket)).toMatchObject({ slot: b.linkSlot });
  });
});

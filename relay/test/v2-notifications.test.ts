import { describe, expect, it } from "vitest";
import type { PushResult } from "../src/push/fcm.js";
import type { ApnsGateway, ApnsMessage } from "../src/push/apns.js";
import { TOKEN_IDLE_TTL_MS } from "../src/auth/tokens.js";
import {
  call, CountingLimiter, db, errorCode, loginDesktop, loginDevice, makeApp, registerAccount, registerMachine, unlimited,
  type Account, type Session, type TestApp,
} from "./helpers.js";

/** Records every push; answers `results[token]`, "ok" by default. */
class FakeApns implements ApnsGateway {
  readonly sent: ApnsMessage[] = [];
  constructor(private readonly results: Record<string, PushResult> = {}) {}
  async send(message: ApnsMessage): Promise<PushResult> {
    this.sent.push(message);
    return this.results[message.token] ?? "ok";
  }
}

const tokenOf = (n: number) => n.toString(16).padStart(2, "0").repeat(32);

function b64(bytes = 32): string {
  return Buffer.from(crypto.getRandomValues(new Uint8Array(bytes))).toString("base64");
}

/** A Mac (desktop + machine) of `account`. */
async function mac(app: TestApp, account: Account): Promise<{ session: Session; machineId: string }> {
  const session = await loginDesktop(app, account);
  const { machine_id } = await registerMachine(app, session.token);
  return { session, machineId: machine_id };
}

/** A phone of `account` granted `machine`, with an APNs token (unless `token` is null). */
async function grantedPhone(
  app: TestApp, account: Account, machine: { session: Session; machineId: string },
  token: string | null, apns: { apns_topic: string; apns_env: string } | null = { apns_topic: "com.shellx.prod", apns_env: "production" },
): Promise<Session> {
  const phone = await loginDevice(app, account, "mobile");
  const req = await call(app, "POST", "/v2/phone-pairings", {
    token: phone.token, body: { machine_id: machine.machineId, client_key_b64: b64(), proof_b64: b64() },
  });
  const { pairing_id } = await req.json<{ pairing_id: string }>();
  expect((await call(app, "POST", `/v2/phone-pairings/${pairing_id}/approve`, { token: machine.session.token })).status).toBe(204);
  if (token !== null) {
    const put = await call(app, "PUT", "/v1/devices/me/push-token", { token: phone.token, body: { token, platform: "ios", ...apns } });
    expect(put.status).toBe(204);
  }
  return phone;
}

function notify(app: TestApp, token: string | undefined, body: Record<string, unknown>) {
  return call(app, "POST", "/v2/notifications", { token, body });
}

const NEEDS_YOU = { kind: "needs_you", request_id: "req-1", agent: "Claude Code", workspace_title: "shellx" };

describe("POST /v2/notifications", () => {
  it("tells every phone granted this Mac that an agent needs it, without what it asks", async () => {
    const apns = new FakeApns();
    const app = makeApp({ apns, now: () => 1_800_000_000_000 });
    const account = await registerAccount(app);
    const m = await mac(app, account);
    await grantedPhone(app, account, m, tokenOf(1));
    await grantedPhone(app, account, m, tokenOf(2), { apns_topic: "com.shellx.dev", apns_env: "sandbox" });

    const res = await notify(app, m.session.token, NEEDS_YOU);

    expect(res.status).toBe(202);
    expect(await res.json()).toEqual({ sent: 2 });
    expect(apns.sent.map((s) => [s.token, s.topic, s.environment])).toEqual(
      expect.arrayContaining([[tokenOf(1), "com.shellx.prod", "production"], [tokenOf(2), "com.shellx.dev", "sandbox"]]));
    expect(apns.sent[0]).toMatchObject({
      pushType: "alert", priority: 10, collapseId: "req-1", expiresAtSec: 1_800_000_000 + 24 * 60 * 60,
      payload: {
        aps: {
          alert: { "title-loc-key": "push.title", "loc-key": "push.needsYou.workspace", "loc-args": ["Claude Code", "shellx"] },
          sound: "default", "thread-id": m.machineId,
        },
        shellx: { kind: "needs_you", machine_id: m.machineId, request_id: "req-1" },
      },
    });
  });

  it("uses the words without a workspace when the Mac gives none", async () => {
    const apns = new FakeApns();
    const app = makeApp({ apns });
    const account = await registerAccount(app);
    const m = await mac(app, account);
    await grantedPhone(app, account, m, tokenOf(1));

    await notify(app, m.session.token, { ...NEEDS_YOU, workspace_title: "" });

    expect(apns.sent[0]!.payload).toMatchObject({ aps: { alert: { "loc-key": "push.needsYou", "loc-args": ["Claude Code"] } } });
  });

  it("wakes the phones quietly when the request was handled, so they take the notification away", async () => {
    const apns = new FakeApns();
    const app = makeApp({ apns });
    const account = await registerAccount(app);
    const m = await mac(app, account);
    await grantedPhone(app, account, m, tokenOf(1));

    const res = await notify(app, m.session.token, { kind: "resolved", request_id: "req-1" });

    expect(res.status).toBe(202);
    expect(apns.sent[0]).toMatchObject({
      pushType: "background", priority: 5,
      payload: { aps: { "content-available": 1 }, shellx: { kind: "resolved", machine_id: m.machineId, request_id: "req-1" } },
    });
    expect(apns.sent[0]!.collapseId).toBeUndefined();
  });

  it("skips phones of another Mac or account, phones without an APNs token, and phones signed out for 90 days", async () => {
    let now = 1_800_000_000_000;
    const apns = new FakeApns();
    const app = makeApp({ apns, now: () => now });
    const account = await registerAccount(app);
    const m = await mac(app, account);
    const other = await mac(app, account);
    await grantedPhone(app, account, other, tokenOf(1));
    await grantedPhone(app, account, m, "fcm-token", null);
    await grantedPhone(app, account, m, null);
    const idle = await grantedPhone(app, account, m, tokenOf(4));
    const stranger = await registerAccount(app);
    await grantedPhone(app, stranger, await mac(app, stranger), tokenOf(5));
    db().run("UPDATE tokens SET last_used_at = ? WHERE device_id = ?", now - TOKEN_IDLE_TTL_MS - 1, idle.deviceId);
    now += 1;

    const res = await notify(app, m.session.token, NEEDS_YOU);

    expect(await res.json()).toEqual({ sent: 0 });
    expect(apns.sent).toEqual([]);
  });

  it("deletes the tokens APNs says are gone", async () => {
    const apns = new FakeApns({ [tokenOf(1)]: "invalid_token", [tokenOf(2)]: "error" });
    const app = makeApp({ apns });
    const account = await registerAccount(app);
    const m = await mac(app, account);
    const gone = await grantedPhone(app, account, m, tokenOf(1));
    const flaky = await grantedPhone(app, account, m, tokenOf(2));

    expect(await (await notify(app, m.session.token, NEEDS_YOU)).json()).toEqual({ sent: 0 });

    const left = db().all<{ device_id: string }>("SELECT device_id FROM push_tokens").map((r) => r.device_id);
    expect(left).toEqual([flaky.deviceId]);
    expect(left).not.toContain(gone.deviceId);
  });

  it("is for a Mac only: a phone or an agent gets 403 desktop_only, no token 401", async () => {
    const app = makeApp({ apns: new FakeApns() });
    const account = await registerAccount(app);
    const phone = await loginDevice(app, account, "mobile");
    for (const token of [phone.token, account.agent.token]) {
      const res = await notify(app, token, NEEDS_YOU);
      expect(res.status).toBe(403);
      expect(await errorCode(res)).toBe("desktop_only");
    }
    expect((await notify(app, undefined, NEEDS_YOU)).status).toBe(401);
  });

  it("needs the Mac's machine (404) and a relay set up for APNs (503 push_unavailable)", async () => {
    const app = makeApp({ apns: new FakeApns() });
    const account = await registerAccount(app);
    const desktop = await loginDesktop(app, account);
    expect((await notify(app, desktop.token, NEEDS_YOU)).status).toBe(404);

    const off = makeApp();
    const offAccount = await registerAccount(off);
    const m = await mac(off, offAccount);
    const res = await notify(off, m.session.token, NEEDS_YOU);
    expect(res.status).toBe(503);
    expect(await errorCode(res)).toBe("push_unavailable");
  });

  it("refuses an unknown kind, a missing or over-64-byte request id, and a needs_you without agent (400)", async () => {
    const apns = new FakeApns();
    const app = makeApp({ apns });
    const account = await registerAccount(app);
    const m = await mac(app, account);
    await grantedPhone(app, account, m, tokenOf(1));
    for (const body of [
      { ...NEEDS_YOU, kind: "done" },
      { kind: "needs_you", agent: "Claude Code" },
      { ...NEEDS_YOU, request_id: "" },
      { ...NEEDS_YOU, request_id: "é".repeat(33) },
      { ...NEEDS_YOU, agent: "" },
      { ...NEEDS_YOU, agent: 7 },
      { ...NEEDS_YOU, agent: "a".repeat(65) },
      { ...NEEDS_YOU, workspace_title: "w".repeat(201) },
    ]) {
      const res = await notify(app, m.session.token, body);
      expect(res.status, JSON.stringify(body).slice(0, 80)).toBe(400);
    }
    expect(apns.sent).toEqual([]);
    expect((await notify(app, m.session.token, { ...NEEDS_YOU, request_id: "r".repeat(64) })).status).toBe(202);
  });

  it("counts each call against the Mac's device (429 past the limit)", async () => {
    const limiter = new CountingLimiter(1);
    const app = makeApp({ apns: new FakeApns(), limiters: { ...unlimited, notifyAgent: limiter } });
    const account = await registerAccount(app);
    const m = await mac(app, account);
    expect((await notify(app, m.session.token, NEEDS_YOU)).status).toBe(202);
    expect((await notify(app, m.session.token, NEEDS_YOU)).status).toBe(429);
    expect(limiter.calls).toEqual([m.session.deviceId, m.session.deviceId]);
  });

  it("does not count a resolved against the limit, so alert removals survive a busy Mac", async () => {
    const limiter = new CountingLimiter(1);
    const apns = new FakeApns();
    const app = makeApp({ apns, limiters: { ...unlimited, notifyAgent: limiter } });
    const account = await registerAccount(app);
    const m = await mac(app, account);
    await grantedPhone(app, account, m, tokenOf(1));
    expect((await notify(app, m.session.token, NEEDS_YOU)).status).toBe(202);
    expect((await notify(app, m.session.token, { kind: "resolved", request_id: "req-1" })).status).toBe(202);
    expect((await notify(app, m.session.token, { kind: "resolved", request_id: "req-1" })).status).toBe(202);
    expect(limiter.calls).toEqual([m.session.deviceId]);
  });

  it("counts a needs_you only once its body is valid", async () => {
    const limiter = new CountingLimiter(10);
    const app = makeApp({ apns: new FakeApns(), limiters: { ...unlimited, notifyAgent: limiter } });
    const account = await registerAccount(app);
    const m = await mac(app, account);
    expect((await notify(app, m.session.token, { ...NEEDS_YOU, agent: "" })).status).toBe(400);
    expect((await notify(app, m.session.token, { ...NEEDS_YOU, kind: "done" })).status).toBe(400);
    expect(limiter.calls).toEqual([]);
  });
});

import { afterEach, describe, expect, it, vi } from "vitest";
import type { FcmDataGateway, FcmDataMessage, PushResult } from "../src/push/fcm.js";
import type { ApnsGateway, ApnsMessage } from "../src/push/apns.js";
import { TOKEN_IDLE_TTL_MS } from "../src/auth/tokens.js";
import {
  call, CountingLimiter, db, errorCode, loginDesktop, loginDevice, makeApp, registerAccount, registerMachine, unlimited,
  type Account, type Session, type TestApp,
} from "./helpers.js";

afterEach(() => vi.restoreAllMocks());

/** Records every push; answers `results[token]`, "ok" by default, or rejects on "throw". */
class FakeApns implements ApnsGateway {
  readonly sent: ApnsMessage[] = [];
  constructor(private readonly results: Record<string, PushResult | "throw"> = {}) {}
  async send(message: ApnsMessage): Promise<PushResult> {
    this.sent.push(message);
    const result = this.results[message.token] ?? "ok";
    if (result === "throw") throw new TypeError("fetch failed");
    return result;
  }
}

/** Records every FCM data message; answers like `FakeApns`. */
class FakeFcm implements FcmDataGateway {
  readonly sent: FcmDataMessage[] = [];
  constructor(private readonly results: Record<string, PushResult | "throw"> = {}) {}
  async sendData(message: FcmDataMessage): Promise<PushResult> {
    this.sent.push(message);
    const result = this.results[message.token] ?? "ok";
    if (result === "throw") throw new TypeError("fetch failed");
    return result;
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

/** Pairs `phone` with `machine` and approves it on the Mac. */
async function grant(app: TestApp, machine: { session: Session; machineId: string }, phone: Session): Promise<void> {
  const req = await call(app, "POST", "/v2/phone-pairings", {
    token: phone.token, body: { machine_id: machine.machineId, client_key_b64: b64(), proof_b64: b64() },
  });
  const { pairing_id } = await req.json<{ pairing_id: string }>();
  expect((await call(app, "POST", `/v2/phone-pairings/${pairing_id}/approve`, { token: machine.session.token })).status).toBe(204);
}

/** A phone of `account` granted `machine`, with an APNs token (unless `token` is null). */
async function grantedPhone(
  app: TestApp, account: Account, machine: { session: Session; machineId: string },
  token: string | null, apns: { apns_topic: string; apns_env: string } | null = { apns_topic: "com.shellx.prod", apns_env: "production" },
): Promise<Session> {
  const phone = await loginDevice(app, account, "mobile");
  await grant(app, machine, phone);
  if (token !== null) {
    const put = await call(app, "PUT", "/v1/devices/me/push-token", { token: phone.token, body: { token, platform: "ios", ...apns } });
    expect(put.status).toBe(204);
  }
  return phone;
}

/**
 * An Android phone signs in as a mobile device with platform "android". `loginDesktop`'s overrides
 * replace every field of the device body, `kind` included, so it is spelled out here.
 */
function loginAndroid(app: TestApp, account: Account): Promise<Session> {
  return loginDesktop(app, account, { kind: "mobile", platform: "android", name: "Pixel 9" });
}

/** An Android phone granted `machine`, with an FCM token (unless `token` is null). */
async function grantedAndroidPhone(
  app: TestApp, account: Account, machine: { session: Session; machineId: string }, token: string | null,
): Promise<Session> {
  const phone = await loginAndroid(app, account);
  await grant(app, machine, phone);
  if (token !== null) {
    const put = await call(app, "PUT", "/v1/devices/me/push-token", { token: phone.token, body: { token, platform: "android" } });
    expect(put.status).toBe(204);
  }
  return phone;
}

function captureLogs(): string[] {
  const lines: string[] = [];
  vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => { lines.push(args.map(String).join(" ")); });
  return lines;
}

function eventsOf(lines: string[]): Record<string, unknown>[] {
  const events: Record<string, unknown>[] = [];
  for (const line of lines) {
    try {
      const parsed: unknown = JSON.parse(line);
      if (typeof parsed === "object" && parsed !== null) events.push(parsed as Record<string, unknown>);
    } catch { /* not a JSON line */ }
  }
  return events;
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

describe("POST /v2/notifications to Android phones (FCM data messages)", () => {
  it("sends each granted Android phone a data-only needs_you: high priority, 24 h, collapsed by request id, beside the iPhones' alert", async () => {
    const apns = new FakeApns();
    const fcm = new FakeFcm();
    const app = makeApp({ apns, fcm });
    const account = await registerAccount(app);
    const m = await mac(app, account);
    await grantedPhone(app, account, m, tokenOf(1));
    await grantedAndroidPhone(app, account, m, "fcm-a");
    await grantedAndroidPhone(app, account, m, "fcm-b");

    const res = await notify(app, m.session.token, NEEDS_YOU);

    expect(res.status).toBe(202);
    expect(await res.json()).toEqual({ sent: 3 });
    expect(apns.sent.map((s) => s.token)).toEqual([tokenOf(1)]);
    expect(fcm.sent.map((s) => s.token).sort()).toEqual(["fcm-a", "fcm-b"]);
    expect(fcm.sent.find((s) => s.token === "fcm-a")).toEqual({
      token: "fcm-a",
      data: { kind: "needs_you", machine_id: m.machineId, request_id: "req-1", agent: "Claude Code", workspace_title: "shellx" },
      priority: "high", ttlSec: 24 * 60 * 60, collapseKey: "req-1",
    });
  });

  it("passes the workspace title through as the Mac sent it, and an empty one when the Mac hides it or sends none", async () => {
    const fcm = new FakeFcm();
    const app = makeApp({ fcm });
    const account = await registerAccount(app);
    const m = await mac(app, account);
    await grantedAndroidPhone(app, account, m, "fcm-a");
    for (const body of [
      { ...NEEDS_YOU, workspace_title: "Dự án 🚀" },
      { ...NEEDS_YOU, workspace_title: "" },
      { kind: "needs_you", request_id: "req-2", agent: "Codex" },
    ]) expect((await notify(app, m.session.token, body)).status).toBe(202);
    expect(fcm.sent.map((s) => [s.data.agent, s.data.workspace_title])).toEqual([
      ["Claude Code", "Dự án 🚀"], ["Claude Code", ""], ["Codex", ""],
    ]);
  });

  it("tells Android phones a request was handled: normal priority, the same collapse key and TTL, and only the ids", async () => {
    const fcm = new FakeFcm();
    const app = makeApp({ fcm });
    const account = await registerAccount(app);
    const m = await mac(app, account);
    await grantedAndroidPhone(app, account, m, "fcm-a");

    const res = await notify(app, m.session.token, { kind: "resolved", request_id: "req-1", agent: "Claude Code", workspace_title: "shellx" });

    expect(res.status).toBe(202);
    expect(fcm.sent).toEqual([{
      token: "fcm-a",
      data: { kind: "resolved", machine_id: m.machineId, request_id: "req-1" },
      priority: "normal", ttlSec: 24 * 60 * 60, collapseKey: "req-1",
    }]);
  });

  it("skips Android phones of another Mac or account, not granted, without a token or idle past the sign-in lifetime, and an iPhone's FCM-style token", async () => {
    let now = 1_800_000_000_000;
    const apns = new FakeApns();
    const fcm = new FakeFcm();
    const app = makeApp({ apns, fcm, now: () => now });
    const account = await registerAccount(app);
    const m = await mac(app, account);
    await grantedAndroidPhone(app, account, await mac(app, account), "fcm-other-mac");
    await grantedAndroidPhone(app, account, m, null);
    const idle = await grantedAndroidPhone(app, account, m, "fcm-idle");
    await grantedPhone(app, account, m, "fcm-style-iphone-token", null);
    const notGranted = await loginAndroid(app, account);
    expect((await call(app, "PUT", "/v1/devices/me/push-token", {
      token: notGranted.token, body: { token: "fcm-not-granted", platform: "android" },
    })).status).toBe(204);
    const stranger = await registerAccount(app);
    await grantedAndroidPhone(app, stranger, await mac(app, stranger), "fcm-stranger");
    db().run("UPDATE tokens SET last_used_at = ? WHERE device_id = ?", now - TOKEN_IDLE_TTL_MS - 1, idle.deviceId);
    now += 1;

    const res = await notify(app, m.session.token, NEEDS_YOU);

    expect(await res.json()).toEqual({ sent: 0 });
    expect(fcm.sent).toEqual([]);
    expect(apns.sent).toEqual([]);
  });

  it("deletes the Android tokens FCM says are gone and keeps the others", async () => {
    const fcm = new FakeFcm({ "fcm-gone": "invalid_token", "fcm-flaky": "error" });
    const app = makeApp({ fcm });
    const account = await registerAccount(app);
    const m = await mac(app, account);
    const gone = await grantedAndroidPhone(app, account, m, "fcm-gone");
    const flaky = await grantedAndroidPhone(app, account, m, "fcm-flaky");

    expect(await (await notify(app, m.session.token, NEEDS_YOU)).json()).toEqual({ sent: 0 });

    const left = db().all<{ device_id: string }>("SELECT device_id FROM push_tokens").map((r) => r.device_id);
    expect(left).toEqual([flaky.deviceId]);
    expect(left).not.toContain(gone.deviceId);
  });

  it("never lets one phone's failed send stop the others: a send that throws counts as not sent and is logged by kind", async () => {
    const lines = captureLogs();
    const apns = new FakeApns({ [tokenOf(2)]: "throw" });
    const fcm = new FakeFcm({ "fcm-throws": "throw" });
    const app = makeApp({ apns, fcm });
    const account = await registerAccount(app);
    const m = await mac(app, account);
    await grantedPhone(app, account, m, tokenOf(1));
    await grantedPhone(app, account, m, tokenOf(2));
    await grantedAndroidPhone(app, account, m, "fcm-ok");
    await grantedAndroidPhone(app, account, m, "fcm-throws");

    const res = await notify(app, m.session.token, NEEDS_YOU);

    expect(res.status).toBe(202);
    expect(await res.json()).toEqual({ sent: 2 });
    expect(apns.sent.map((s) => s.token).sort()).toEqual([tokenOf(1), tokenOf(2)]);
    expect(fcm.sent.map((s) => s.token).sort()).toEqual(["fcm-ok", "fcm-throws"]);
    const events = eventsOf(lines);
    expect(events).toContainEqual({ ts: expect.any(Number), event: "v2_notification_send_failed", via: "apns", error: "TypeError" });
    expect(events).toContainEqual({ ts: expect.any(Number), event: "v2_notification_send_failed", via: "fcm", error: "TypeError" });
    expect(db().get<{ n: number }>("SELECT COUNT(*) AS n FROM push_tokens")!.n).toBe(4);
  });

  it("answers 503 push_unavailable only when neither APNs nor FCM is set up; with one of them the other platform's phones are skipped", async () => {
    const fcmOnly = new FakeFcm();
    const a = makeApp({ fcm: fcmOnly });
    const accountA = await registerAccount(a);
    const macA = await mac(a, accountA);
    await grantedPhone(a, accountA, macA, tokenOf(1));
    await grantedAndroidPhone(a, accountA, macA, "fcm-a");
    const resA = await notify(a, macA.session.token, NEEDS_YOU);
    expect(resA.status).toBe(202);
    expect(await resA.json()).toEqual({ sent: 1 });
    expect(fcmOnly.sent.map((s) => s.token)).toEqual(["fcm-a"]);

    const apnsOnly = new FakeApns();
    const b = makeApp({ apns: apnsOnly });
    const accountB = await registerAccount(b);
    const macB = await mac(b, accountB);
    await grantedPhone(b, accountB, macB, tokenOf(2));
    await grantedAndroidPhone(b, accountB, macB, "fcm-b");
    expect(await (await notify(b, macB.session.token, NEEDS_YOU)).json()).toEqual({ sent: 1 });
    expect(apnsOnly.sent.map((s) => s.token)).toEqual([tokenOf(2)]);

    const off = makeApp();
    const offAccount = await registerAccount(off);
    const offMac = await mac(off, offAccount);
    const resOff = await notify(off, offMac.session.token, NEEDS_YOU);
    expect(resOff.status).toBe(503);
    expect(await errorCode(resOff)).toBe("push_unavailable");
  });

  it("counts a needs_you once against the Mac however many iPhones and Android phones it reaches, and a resolved never", async () => {
    const limiter = new CountingLimiter(10);
    const app = makeApp({ apns: new FakeApns(), fcm: new FakeFcm(), limiters: { ...unlimited, notifyAgent: limiter } });
    const account = await registerAccount(app);
    const m = await mac(app, account);
    await grantedPhone(app, account, m, tokenOf(1));
    await grantedAndroidPhone(app, account, m, "fcm-a");
    await grantedAndroidPhone(app, account, m, "fcm-b");

    expect(await (await notify(app, m.session.token, NEEDS_YOU)).json()).toEqual({ sent: 3 });
    expect(await (await notify(app, m.session.token, { kind: "resolved", request_id: "req-1" })).json()).toEqual({ sent: 3 });
    expect(limiter.calls).toEqual([m.session.deviceId]);
  });

  it("logs the kind and the counts only: never the agent, the workspace, the request id or a token", async () => {
    const lines = captureLogs();
    const app = makeApp({ apns: new FakeApns(), fcm: new FakeFcm() });
    const account = await registerAccount(app);
    const m = await mac(app, account);
    await grantedPhone(app, account, m, tokenOf(1));
    await grantedAndroidPhone(app, account, m, "fcm-secret-token");

    await notify(app, m.session.token, { kind: "needs_you", request_id: "req-secret-7", agent: "Claude Code", workspace_title: "Dự án bí mật" });

    expect(eventsOf(lines).filter((e) => e.event === "v2_notification")).toEqual([{
      ts: expect.any(Number), event: "v2_notification", device_id: m.session.deviceId, kind: "needs_you",
      recipients: 2, fcm_recipients: 1, sent: 2, tokens_removed: 0,
    }]);
    const output = lines.join("\n");
    for (const secret of ["Claude Code", "Dự án bí mật", "req-secret-7", tokenOf(1), "fcm-secret-token"]) expect(output).not.toContain(secret);
  });
});

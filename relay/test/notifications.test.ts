import { describe, expect, it } from "vitest";
import type { PushGateway, PushMessage, PushResult } from "../src/push/fcm.js";
import { TOKEN_IDLE_TTL_MS } from "../src/auth/tokens.js";
import {
  call, CountingLimiter, db, errorCode, loginDevice, makeApp, pair, registerAccount, type Session, type TestApp, unlimited,
} from "./helpers.js";

/** Records every message; answers `results[token]` (default "ok"). */
class FakeGateway implements PushGateway {
  readonly sent: PushMessage[] = [];
  constructor(readonly results: Record<string, PushResult> = {}) {}
  async send(message: PushMessage): Promise<PushResult> {
    this.sent.push(message);
    return this.results[message.token] ?? "ok";
  }
}

async function setToken(app: TestApp, phone: Session, token: string, platform = "android"): Promise<void> {
  const res = await call(app, "PUT", "/v1/devices/me/push-token", { token: phone.token, body: { token, platform } });
  expect(res.status).toBe(204);
}

function notify(app: TestApp, token: string, body: unknown) {
  return call(app, "POST", "/v1/notifications", { token, body });
}

const NOTE = { title: "MacBook · Session 1", body: "✓ npm test · 3 min 12 s", data: { session_id: "7", kind: "command" } };

describe("POST /v1/notifications", () => {
  it("sends to every paired phone with a token, adds agent_id, and answers 202 {sent}", async () => {
    const push = new FakeGateway();
    const app = makeApp({ push });
    const account = await registerAccount(app);
    const a = await loginDevice(app, account, "mobile");
    const b = await loginDevice(app, account, "mobile");
    for (const phone of [a, b]) expect((await pair(app, account.agent.token, phone.deviceId)).status).toBe(201);
    await setToken(app, a, "token-a");
    await setToken(app, b, "token-b", "ios");

    const res = await notify(app, account.agent.token, NOTE);
    expect(res.status).toBe(202);
    expect(await res.json()).toEqual({ sent: 2 });
    expect(push.sent.map((m) => m.token).sort()).toEqual(["token-a", "token-b"]);
    for (const m of push.sent) {
      expect(m).toMatchObject({ title: NOTE.title, body: NOTE.body });
      expect(m.data).toEqual({ session_id: "7", kind: "command", agent_id: account.agent.deviceId });
    }
  });

  it("skips phones that are not paired with this agent, have no token or are signed out", async () => {
    const push = new FakeGateway();
    const app = makeApp({ push });
    const account = await registerAccount(app);
    const paired = await loginDevice(app, account, "mobile");
    const unpaired = await loginDevice(app, account, "mobile");
    const noToken = await loginDevice(app, account, "mobile");
    const signedOut = await loginDevice(app, account, "mobile");
    for (const phone of [paired, noToken, signedOut]) await pair(app, account.agent.token, phone.deviceId);
    await setToken(app, paired, "paired");
    await setToken(app, unpaired, "unpaired");
    await setToken(app, signedOut, "signed-out");
    // A sign-out that left the push token behind (e.g. a token revoked by a password change).
    db().run("DELETE FROM tokens WHERE device_id = ?", signedOut.deviceId);

    const res = await notify(app, account.agent.token, NOTE);
    expect(await res.json()).toEqual({ sent: 1 });
    expect(push.sent.map((m) => m.token)).toEqual(["paired"]);
  });

  it("skips phones whose sign-in has been idle past the token lifetime", async () => {
    const push = new FakeGateway();
    let now = Date.now();
    const app = makeApp({ push, now: () => now });
    const account = await registerAccount(app);
    const phone = await loginDevice(app, account, "mobile");
    await pair(app, account.agent.token, phone.deviceId);
    await setToken(app, phone, "t");
    db().run("UPDATE tokens SET last_used_at = ? WHERE device_id = ?", now - TOKEN_IDLE_TTL_MS - 1, phone.deviceId);
    now += 1;
    expect(await (await notify(app, account.agent.token, NOTE)).json()).toEqual({ sent: 0 });
    expect(push.sent).toEqual([]);
  });

  it("never reaches phones of another account", async () => {
    const push = new FakeGateway();
    const app = makeApp({ push });
    const mine = await registerAccount(app);
    const other = await registerAccount(app);
    const theirs = await loginDevice(app, other, "mobile");
    await pair(app, other.agent.token, theirs.deviceId);
    await setToken(app, theirs, "theirs");
    expect(await (await notify(app, mine.agent.token, NOTE)).json()).toEqual({ sent: 0 });
    expect(push.sent).toEqual([]);
  });

  it("deletes tokens FCM reports as gone, keeps the others, and counts only accepted sends", async () => {
    const push = new FakeGateway({ gone: "invalid_token", flaky: "error" });
    const app = makeApp({ push });
    const account = await registerAccount(app);
    const phones = [await loginDevice(app, account, "mobile"), await loginDevice(app, account, "mobile"), await loginDevice(app, account, "mobile")];
    const tokens = ["gone", "flaky", "fine"];
    for (const [i, phone] of phones.entries()) {
      await pair(app, account.agent.token, phone.deviceId);
      await setToken(app, phone, tokens[i]!);
    }
    expect(await (await notify(app, account.agent.token, NOTE)).json()).toEqual({ sent: 1 });
    const left = db().all<{ token: string }>("SELECT token FROM push_tokens ORDER BY token").map((r) => r.token);
    expect(left).toEqual(["fine", "flaky"]);
  });

  it("is for agents only (403 agent_only)", async () => {
    const app = makeApp({ push: new FakeGateway() });
    const account = await registerAccount(app);
    const phone = await loginDevice(app, account, "mobile");
    const res = await notify(app, phone.token, NOTE);
    expect(res.status).toBe(403);
    expect(await errorCode(res)).toBe("agent_only");
  });

  it("requires a token (401)", async () => {
    expect((await call(makeApp({ push: new FakeGateway() }), "POST", "/v1/notifications", { body: NOTE })).status).toBe(401);
  });

  it("answers 503 push_unavailable when the relay has no Firebase configuration", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const res = await notify(app, account.agent.token, NOTE);
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({
      error: { code: "push_unavailable", message: "Push notifications are not configured on this relay" },
    });
  });

  it("validates title (1..200), body (1..1000) and data (≤ 10 string values, no FCM-reserved keys)", async () => {
    const push = new FakeGateway();
    const app = makeApp({ push });
    const account = await registerAccount(app);
    const tenKeys = Object.fromEntries(Array.from({ length: 10 }, (_, i) => [`k${i}`, "v"]));
    const elevenKeys = { ...tenKeys, k10: "v" };
    const bad: unknown[] = [
      { body: "b" },
      { title: "", body: "b" },
      { title: "   ", body: "b" },
      { title: "t".repeat(201), body: "b" },
      { title: 5, body: "b" },
      { title: "t" },
      { title: "t", body: "" },
      { title: "t", body: "b".repeat(1001) },
      { title: "t", body: "b", data: elevenKeys },
      { title: "t", body: "b", data: { n: 1 } },
      { title: "t", body: "b", data: ["x"] },
      { title: "t", body: "b", data: "x" },
      { title: "t", body: "b", data: { from: "x" } },
      { title: "t", body: "b", data: { google_x: "x" } },
      { title: "t", body: "b", data: { gcm_x: "x" } },
      { title: "t", body: "b", data: { agent_id: "spoofed" } },
      { title: "t", body: "b", data: { "": "x" } },
    ];
    for (const body of bad) {
      const res = await notify(app, account.agent.token, body);
      expect(res.status, JSON.stringify(body).slice(0, 80)).toBe(400);
      expect(await errorCode(res)).toBe("bad_request");
    }
    // Limits count characters (code points), not UTF-16 units or bytes.
    for (const body of [
      { title: "✓".repeat(200), body: "é".repeat(1000), data: tenKeys },
      { title: "😀".repeat(200), body: "b" },
      { title: "t", body: "b", data: null },
    ]) {
      expect((await notify(app, account.agent.token, body)).status).toBe(202);
    }
  });

  it("limits each agent (429 rate_limited from the notifyAgent limiter, keyed by device id)", async () => {
    const notifyAgent = new CountingLimiter(2);
    const app = makeApp({ push: new FakeGateway(), limiters: { ...unlimited, notifyAgent } });
    const account = await registerAccount(app);
    expect((await notify(app, account.agent.token, NOTE)).status).toBe(202);
    expect((await notify(app, account.agent.token, NOTE)).status).toBe(202);
    const res = await notify(app, account.agent.token, NOTE);
    expect(res.status).toBe(429);
    expect(await errorCode(res)).toBe("rate_limited");
    expect(notifyAgent.calls).toEqual([account.agent.deviceId, account.agent.deviceId, account.agent.deviceId]);
  });
});

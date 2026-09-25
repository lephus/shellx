import { env } from "cloudflare:workers";
import { afterEach, describe, expect, it, vi } from "vitest";
import { DEVICE_ID_HEADER, DEVICE_KIND_HEADER } from "../src/hub/user-hub";
import { encodeData, encodeError, encodePresence, MAX_FRAME_BYTES, RelayErrorCode } from "../src/protocol/frames";
import { buildHubHeaders } from "../src/routes/ws";
import {
  call, connect, errorCode, hex, loginDevice, makeApp, registerAccount, TestSocket, type TestApp, waitFor,
} from "./helpers";

const CH = Uint8Array.from([9, 8, 7, 6, 5, 4, 3, 2]);

afterEach(() => {
  vi.restoreAllMocks();
});

async function accountWithAgentAndMobile() {
  const app = makeApp();
  const account = await registerAccount(app);
  const mobile = await loginDevice(app, account, "mobile");
  return { app, account, agent: account.agent, mobile };
}

describe("GET /v1/ws", () => {
  it("rejects a plain GET with 426 upgrade_required", async () => {
    const res = await call(makeApp(), "GET", "/v1/ws");
    expect(res.status).toBe(426);
    expect(await errorCode(res)).toBe("upgrade_required");
  });

  it("refuses a missing, unknown or expired token with HTTP 401 unauthorized before upgrading", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const later = makeApp({ now: () => Date.now() + 91 * 24 * 60 * 60 * 1000 });
    const attempts: [TestApp, string | undefined][] = [[app, undefined], [app, "A".repeat(43)], [later, account.agent.token]];
    for (const [client, token] of attempts) {
      const res = await call(client, "GET", "/v1/ws", { token, headers: { Upgrade: "websocket" } });
      expect(res.status).toBe(401);
      expect(res.webSocket).toBeNull();
      expect(await errorCode(res)).toBe("unauthorized");
    }
  });

  it("buildHubHeaders forwards only the allowlisted upgrade headers, never arbitrary client headers", () => {
    // A hostile client's raw request: real upgrade headers, plus a session cookie, a forwarded-for
    // header, a made-up header, and a duplicate-cased spoof attempt at the hub's own identity headers.
    const clientHeaders = new Headers([
      ["Upgrade", "websocket"],
      ["Connection", "Upgrade"],
      ["Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ=="],
      ["Sec-WebSocket-Version", "13"],
      ["Cookie", "session=abc123"],
      ["X-Forwarded-For", "203.0.113.7"],
      ["X-Evil", "haxx"],
      ["Authorization", "Bearer should-never-be-forwarded"],
      // lower-cased on purpose: Headers is case-insensitive, so this is the same header as
      // DEVICE_ID_HEADER ("X-Shellx-Device-Id") — proves case doesn't let a spoof slip through.
      ["x-shellx-device-id", "11111111-1111-1111-1111-111111111111"],
      ["X-Shellx-Device-Kind", "agent"],
    ]);
    const auth = { deviceId: "22222222-2222-2222-2222-222222222222", kind: "mobile" as const };

    const headers = buildHubHeaders(clientHeaders, auth);

    // Allowlisted upgrade headers pass through unchanged.
    expect(headers.get("Upgrade")).toBe("websocket");
    expect(headers.get("Connection")).toBe("Upgrade");
    expect(headers.get("Sec-WebSocket-Key")).toBe("dGhlIHNhbXBsZSBub25jZQ==");
    expect(headers.get("Sec-WebSocket-Version")).toBe("13");
    // Not sent by the client, so absent (not merely empty).
    expect(headers.has("Sec-WebSocket-Protocol")).toBe(false);
    expect(headers.has("Sec-WebSocket-Extensions")).toBe(false);

    // Identity headers come from the validated token, not the client's spoof attempt.
    expect(headers.get(DEVICE_ID_HEADER)).toBe(auth.deviceId);
    expect(headers.get(DEVICE_KIND_HEADER)).toBe(auth.kind);

    // Everything else the client sent is gone, including Authorization and the spoofed identity.
    expect(headers.has("Cookie")).toBe(false);
    expect(headers.has("X-Forwarded-For")).toBe(false);
    expect(headers.has("X-Evil")).toBe(false);
    expect(headers.has("Authorization")).toBe(false);

    // Exhaustive: exactly these six headers reach the hub, nothing more.
    expect([...headers.keys()].sort()).toEqual(
      ["connection", "sec-websocket-key", "sec-websocket-version", "upgrade", "x-shellx-device-id", "x-shellx-device-kind"],
    );
  });

  it("integration: an upgrade carrying hostile extra headers still connects and identifies the token's device", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    await a.expectSilence(100);

    // A client connecting with mobile's token, sending a cookie, a spoofed device id/kind, and
    // claiming (via headers) to be the agent device — buildHubHeaders is what actually stops this;
    // this end-to-end check just confirms the wiring still works after the refactor.
    const res = await call(app, "GET", "/v1/ws", {
      token: mobile.token,
      headers: {
        Upgrade: "websocket",
        Cookie: "session=abc123",
        "X-Shellx-Device-Id": agent.deviceId,
        "X-Shellx-Device-Kind": "agent",
      },
    });
    if (res.status !== 101 || res.webSocket === null) throw new Error(`upgrade failed: ${res.status}`);
    const m = new TestSocket(res.webSocket);

    // Presence announces the token's real device (mobile), never the spoofed agent id.
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));

    // Frames it sends arrive at the peer sourced from the token's device, not the spoofed one.
    m.send(encodeData(agent.deviceId, CH, Uint8Array.of(4, 9)));
    expect(hex(await a.nextBinary())).toBe(hex(encodeData(mobile.deviceId, CH, Uint8Array.of(4, 9))));
  });
});

describe("UserHub presence and routing", () => {
  it("sends a presence snapshot to the newcomer and announces it to the others", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    await a.expectSilence(100); // alone in the hub: nothing to report
    const m = await connect(app, mobile.token);
    expect(hex(await m.nextBinary())).toBe(hex(encodePresence(agent.deviceId, true)));
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
  });

  it("answers the text heartbeat 'ping' with 'pong'", async () => {
    const { app, agent } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    a.send("ping");
    expect(await a.next()).toBe("pong");
  });

  it("routes DATA to the peer with the peer field rewritten to the sender", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    const m = await connect(app, mobile.token);
    await m.nextBinary();
    await a.nextBinary();
    const payload = Uint8Array.from([0x01, 0xde, 0xad, 0xbe, 0xef]);
    m.send(encodeData(agent.deviceId, CH, payload));
    expect(hex(await a.nextBinary())).toBe(hex(encodeData(mobile.deviceId, CH, payload)));
    a.send(encodeData(mobile.deviceId, CH, payload));
    expect(hex(await m.nextBinary())).toBe(hex(encodeData(agent.deviceId, CH, payload)));
  });

  it("replies ERROR peer_offline (with peer and channel) when the target is not connected", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const m = await connect(app, mobile.token);
    m.send(encodeData(agent.deviceId, CH, Uint8Array.of(4)));
    expect(hex(await m.nextBinary())).toBe(hex(encodeError(RelayErrorCode.peerOffline, agent.deviceId, CH)));
  });

  it("never routes frames to another account, even when that device is online", async () => {
    const app = makeApp();
    const alice = await registerAccount(app);
    const aliceMobile = await loginDevice(app, alice, "mobile");
    const bob = await registerAccount(app);
    const bobAgent = await connect(app, bob.agent.token);
    const attacker = await connect(app, aliceMobile.token);
    await attacker.expectSilence(100); // Bob's agent is not in Alice's presence snapshot
    attacker.send(encodeData(bob.agent.deviceId, CH, Uint8Array.of(4, 1, 2, 3)));
    expect(hex(await attacker.nextBinary())).toBe(hex(encodeError(RelayErrorCode.peerOffline, bob.agent.deviceId, CH)));
    await bobAgent.expectSilence();
  });

  it("enforces the 64 KiB frame limit", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    const m = await connect(app, mobile.token);
    await m.nextBinary();
    await a.nextBinary();
    const exact = encodeData(agent.deviceId, CH, new Uint8Array(MAX_FRAME_BYTES - 26));
    expect(exact.length).toBe(65536);
    m.send(exact);
    expect((await a.nextBinary()).length).toBe(65536);
    m.send(encodeData(agent.deviceId, CH, new Uint8Array(MAX_FRAME_BYTES - 25)));
    expect(hex(await m.nextBinary())).toBe(hex(encodeError(RelayErrorCode.frameTooLarge, agent.deviceId, CH)));
    await a.expectSilence();
  });

  it("answers malformed frames with ERROR bad_frame and keeps the connection", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    const m = await connect(app, mobile.token);
    await m.nextBinary();
    await a.nextBinary();
    const badFrame = hex(encodeError(RelayErrorCode.badFrame));
    const wrongVersion = encodeData(agent.deviceId, CH, Uint8Array.of(4));
    wrongVersion[0] = 2;
    for (const bad of [new Uint8Array(10), wrongVersion, encodePresence(agent.deviceId, true)]) {
      m.send(bad);
      expect(hex(await m.nextBinary())).toBe(badFrame);
    }
    m.send("hello");
    expect(hex(await m.nextBinary())).toBe(badFrame);
    m.send(encodeData(agent.deviceId, CH, Uint8Array.of(4)));
    expect((await a.nextBinary()).length).toBe(27);
    await a.expectSilence(50);
  });

  it("replaces an older connection of the same device with 4001 without announcing it offline", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    const m1 = await connect(app, mobile.token);
    await m1.nextBinary();
    await a.nextBinary();

    const m2 = await connect(app, mobile.token);
    expect(await m1.closed).toEqual({ code: 4001, reason: "replaced" });
    expect(hex(await m2.nextBinary())).toBe(hex(encodePresence(agent.deviceId, true)));
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    await a.expectSilence(); // no "offline" for the replaced socket

    a.send(encodeData(mobile.deviceId, CH, Uint8Array.of(4)));
    expect((await m2.nextBinary()).length).toBe(27);
  });

  it("announces offline and records last_seen_at when a device disconnects", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    const m = await connect(app, mobile.token);
    await m.nextBinary();
    await a.nextBinary();
    const before = Date.now();
    m.close();
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, false)));
    const lastSeen = await waitFor(async () =>
      (await env.DB.prepare("SELECT last_seen_at FROM devices WHERE id = ?").bind(mobile.deviceId)
        .first<{ last_seen_at: number | null }>())?.last_seen_at,
    );
    expect(lastSeen).toBeGreaterThanOrEqual(before);
  });

  it("tolerates a failing last_seen_at write, logging metadata only and still announcing offline", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    const m = await connect(app, mobile.token);
    await m.nextBinary();
    await a.nextBinary();

    const lines: string[] = [];
    vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    });
    vi.spyOn(env.DB, "prepare").mockImplementation(() => {
      throw new Error("D1 is down");
    });

    m.close();
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, false)));

    const output = lines.join("\n");
    expect(output).toContain("last_seen_write_failed");
    expect(output).toContain(mobile.deviceId);
    expect(output).not.toContain("D1 is down");
  });

  it("logs frame metadata but never the payload", async () => {
    const lines: string[] = [];
    vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    });
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const m = await connect(app, mobile.token);
    const payload = new TextEncoder().encode("SECRET-PAYLOAD-MARKER".padEnd(MAX_FRAME_BYTES, "!"));
    m.send(encodeData(agent.deviceId, CH, payload));
    await m.nextBinary();
    const output = lines.join("\n");
    expect(output).toContain("ws_frame_too_large");
    expect(output).not.toContain("SECRET-PAYLOAD-MARKER");
  });
});

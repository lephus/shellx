import { afterEach, describe, expect, it, vi } from "vitest";
import type { HubRegistry } from "../src/hub/registry.js";
import { WebSocket } from "ws";
import { type ConnectionMeta, type HubSocket, TRY_AGAIN_LATER } from "../src/hub/user-hub.js";
import { type CloseCode, encodeData, encodeError, encodePresence, MAX_FRAME_BYTES, RelayErrorCode } from "../src/protocol/frames.js";
import {
  call, connect, db, errorCode, hex, hubs, loginDevice, makeApp, registerAccount, type TestApp, TestSocket, upgradeStatus,
  waitFor,
} from "./helpers.js";

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

/**
 * A registry that behaves like the test's real one, except that `connect` first runs `before` —
 * the point between the ws route's authenticate() and the socket landing in the hub.
 */
function registryRacingConnect(before: () => Promise<void>, after?: () => Promise<void>): HubRegistry {
  const real = hubs();
  return {
    forUser: (userId: string) => {
      const hub = real.forUser(userId);
      return {
        connect: async (socket: HubSocket, meta: ConnectionMeta) => {
          await before();
          await hub.connect(socket, meta);
          await after?.();
        },
        receive: (socket: HubSocket, data: ArrayBuffer | string) => hub.receive(socket, data),
        ping: (socket: HubSocket, deviceId: string) => hub.ping(socket, deviceId),
        disconnected: (socket: HubSocket) => hub.disconnected(socket),
        closeConnection: (connId: string, code: CloseCode) => hub.closeConnection(connId, code),
      };
    },
  } as unknown as HubRegistry;
}

/**
 * A registry whose connect() holds every one of the first `count` callers at a barrier until all
 * of them have arrived — proving they are genuinely pending at the same time, rather than the
 * async token hash before this point coincidentally letting one finish before the next starts —
 * then releases them all together into the real hub in the same tick (Review Focus 1).
 */
function registryBarrierForConnects(count: number, onArrival: (pending: number) => void): HubRegistry {
  const real = hubs();
  let pending = 0;
  let release: (() => void) | undefined;
  const barrier = new Promise<void>((resolve) => {
    release = resolve;
  });
  return {
    forUser: (userId: string) => {
      const hub = real.forUser(userId);
      return {
        connect: async (socket: HubSocket, meta: ConnectionMeta) => {
          pending++;
          onArrival(pending); // fires while every caller so far is still stuck below, not yet in the hub
          if (pending >= count) release!();
          await barrier;
          return hub.connect(socket, meta);
        },
        receive: (socket: HubSocket, data: ArrayBuffer | string) => hub.receive(socket, data),
        ping: (socket: HubSocket, deviceId: string) => hub.ping(socket, deviceId),
        disconnected: (socket: HubSocket) => hub.disconnected(socket),
        closeConnection: (connId: string, code: CloseCode) => hub.closeConnection(connId, code),
      };
    },
  } as unknown as HubRegistry;
}

/** A registry like the test's real one that also records every socket the ws route hands the hub. */
function registryCapturingSockets(joined: HubSocket[]): HubRegistry {
  const real = hubs();
  return {
    forUser: (userId: string) => {
      const hub = real.forUser(userId);
      return {
        connect: (socket: HubSocket, meta: ConnectionMeta) => {
          joined.push(socket);
          return hub.connect(socket, meta);
        },
        receive: (socket: HubSocket, data: ArrayBuffer | string) => hub.receive(socket, data),
        ping: (socket: HubSocket, deviceId: string) => hub.ping(socket, deviceId),
        disconnected: (socket: HubSocket) => hub.disconnected(socket),
        closeConnection: (connId: string, code: CloseCode) => hub.closeConnection(connId, code),
      };
    },
  } as unknown as HubRegistry;
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
      expect(await errorCode(res)).toBe("unauthorized");
      expect(await upgradeStatus(client, token)).toBe(401); // a real WebSocket handshake gets the same status
    }
  });

  it("answers 426 to a valid token on a request that is not a real upgrade (no Connection: upgrade)", async () => {
    const { app, agent } = await accountWithAgentAndMobile();
    const res = await call(app, "GET", "/v1/ws", { token: agent.token, headers: { Upgrade: "websocket" } });
    expect(res.status).toBe(426);
    expect(await errorCode(res)).toBe("upgrade_required");
  });

  it("an upgrade carrying hostile extra headers still connects and identifies the token's device", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    await a.expectSilence(100);

    // Mobile's token, plus a cookie and headers claiming to be the agent device: only the token counts.
    const m = await connect(app, mobile.token, {
      Cookie: "session=abc123",
      "X-Shellx-Device-Id": agent.deviceId,
      "X-Shellx-Device-Kind": "agent",
      "X-Shellx-Conn-Id": "44444444-4444-4444-4444-444444444444",
    });
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    m.send(encodeData(agent.deviceId, CH, Uint8Array.of(4, 9)));
    expect(hex(await a.nextBinary())).toBe(hex(encodeData(mobile.deviceId, CH, Uint8Array.of(4, 9))));
  });

  it("closes the socket with 4002 if the token is revoked in the gap between auth and the socket joining the hub", async () => {
    const { app, mobile } = await accountWithAgentAndMobile();
    const racing = makeApp({
      hubs: registryRacingConnect(async () => {
        db().run("DELETE FROM tokens WHERE device_id = ?", mobile.deviceId);
      }),
    });
    const socket = await connect(racing, mobile.token); // the upgrade itself still succeeds...
    expect(await socket.closed).toEqual({ code: 4002, reason: "revoked" }); // ...but is then closed
    expect((await call(app, "GET", "/v1/version")).status).toBe(200); // the normal app is unaffected
  });

  it("closes the socket with 1011 internal_error if the hub rejects the join, e.g. a database error", async () => {
    const { mobile } = await accountWithAgentAndMobile();
    const racing = makeApp({
      hubs: registryRacingConnect(async () => {
        throw Object.assign(new Error("database is locked"), { code: "SQLITE_BUSY" });
      }),
    });
    const socket = await connect(racing, mobile.token); // the upgrade itself still succeeds...
    expect(await socket.closed).toEqual({ code: 1011, reason: "internal_error" }); // ...but is then closed
  });

  it("fails closed if the post-join re-check itself errors, e.g. a database error", async () => {
    const { app, mobile } = await accountWithAgentAndMobile();
    const realGet = db().get.bind(db());
    let calls = 0;
    const spy = vi.spyOn(db(), "get").mockImplementation((sql: string, ...params) => {
      if (sql.includes("FROM tokens t JOIN devices d")) {
        calls++;
        // Call 1 is the route's own authenticate(); call 2 is the re-check after the join.
        if (calls === 2) throw Object.assign(new Error("database is locked"), { code: "SQLITE_BUSY" });
      }
      return realGet(sql, ...params);
    });
    const socket = await connect(app, mobile.token);
    expect(await socket.closed).toEqual({ code: 4002, reason: "revoked" });
    spy.mockRestore();
    expect(calls).toBe(2);
  });

  it("targets only the stale connection: a legitimate reconnect that already replaced it is untouched", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const stale = await loginDevice(app, account, "mobile");
    let fresh: TestSocket | undefined;
    const racing = makeApp({
      hubs: registryRacingConnect(
        async () => {},
        async () => {
          // After the stale socket joined: the same device logs in again (invalidating the stale
          // token) and connects through the normal app, replacing the stale socket with 4001.
          const again = await loginDevice(app, account, "mobile", stale.publicKey);
          fresh = await connect(app, again.token);
        },
      ),
    });
    const staleSocket = await connect(racing, stale.token);
    expect(await staleSocket.closed).toEqual({ code: 4001, reason: "replaced" }); // not the re-check
    await waitFor(async () => fresh);
    await fresh!.expectSilence(100);
    fresh!.send("ping");
    expect(await fresh!.next()).toBe("pong");
  });

  it("two sockets of the same device racing in one tick: exactly one survives, peers never see it offline", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    let maxPending = 0;
    const racing = makeApp({
      hubs: registryBarrierForConnects(2, (pending) => {
        maxPending = Math.max(maxPending, pending);
      }),
    });
    const [first, second] = await Promise.all([connect(racing, mobile.token), connect(racing, mobile.token)]);
    // Proves the barrier really held both connects pending at once: this can only reach 2 if the
    // second call arrived while the first was still stuck below, not after the first had already
    // finished (which is what the async token hash alone let happen, undetected, before this fix).
    expect(maxPending).toBe(2);
    const closed = await Promise.race([
      first.closed.then((info) => ({ loser: first, winner: second, info })),
      second.closed.then((info) => ({ loser: second, winner: first, info })),
    ]);
    expect(closed.info).toEqual({ code: 4001, reason: "replaced" });
    closed.winner.send("ping");
    let reply = await closed.winner.next();
    while (reply !== "pong") reply = await closed.winner.next(); // skip its PRESENCE snapshot
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    await a.expectSilence(); // no offline in between or after
    const devices = await call(app, "GET", "/v1/devices", { token: agent.token });
    const listed = await devices.json<{ id: string; online: boolean }[]>();
    expect(listed.find((d) => d.id === mobile.deviceId)?.online).toBe(true);
  });
});

describe("hub presence and routing over real sockets", () => {
  it("sends a presence snapshot to the newcomer and announces it to the others", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    await a.expectSilence(100);
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
    await attacker.expectSilence(100);
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

  it("closes a receiver that stops reading with 1013 once its backlog passes 4 MiB; the sender stays connected", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    const m = await connect(app, mobile.token);
    await m.nextBinary();
    await a.nextBinary();
    m.ws.pause(); // the phone stops reading: kernel buffers fill, then the relay's own buffer grows
    const full = encodeData(mobile.deviceId, CH, new Uint8Array(MAX_FRAME_BYTES - 26));
    // 400 × 64 KiB = 25 MiB: well past the cap plus what the kernel can buffer, within the 500-frame burst.
    for (let i = 0; i < 400; i++) a.send(full);
    const offline = hex(encodePresence(mobile.deviceId, false));
    for (;;) {
      const message = await a.nextBinary(10_000); // after the close, further frames get peer_offline
      if (hex(message) === offline) break;
    }
    m.ws.resume();
    expect(await m.closed).toEqual({ code: TRY_AGAIN_LATER, reason: "try again later" });
    a.send("ping");
    for (;;) if ((await a.next()) === "pong") break; // skip the peer_offline replies still queued
    expect(a.ws.readyState).toBe(WebSocket.OPEN);
  }, 30_000);

  it("closes a socket that sends a message over 1 MiB with 1009 (ws maxPayload)", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    const m = await connect(app, mobile.token);
    await m.nextBinary();
    await a.nextBinary();
    m.send(new Uint8Array(1024 * 1024 + 1));
    expect((await m.closed).code).toBe(1009);
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, false)));
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
    await a.expectSilence();

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
      db().get<{ last_seen_at: number | null }>("SELECT last_seen_at FROM devices WHERE id = ?", mobile.deviceId)?.last_seen_at,
    );
    expect(lastSeen).toBeGreaterThanOrEqual(before);
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

describe("queued sends of a real ws socket", () => {
  it("counts sends until their write completes: rises while the peer does not read, back to 0 once it drains", async () => {
    const { agent } = await accountWithAgentAndMobile();
    const joined: HubSocket[] = [];
    const app = makeApp({ hubs: registryCapturingSockets(joined) });
    const a = await connect(app, agent.token);
    const server = await waitFor(async () => joined[0]);
    expect(server.pendingSends).toBe(0);

    a.ws.pause(); // stops reading: kernel buffers fill, then the relay's own write queue grows
    const frame = new Uint8Array(64 * 1024);
    // 400 × 64 KiB = 25 MiB: more than the kernel can buffer, so the writes stay queued in the relay.
    for (let i = 0; i < 400; i++) server.send(frame);
    expect(server.pendingSends).toBe(400); // a write never completes synchronously
    await new Promise((resolve) => setTimeout(resolve, 100));
    expect(server.pendingSends).toBeGreaterThan(0);
    expect(server.bufferedAmount).toBeGreaterThan(0);

    a.ws.resume();
    await waitFor(async () => (server.pendingSends === 0 ? true : null), 10_000);
    expect(server.bufferedAmount).toBe(0);
  }, 30_000);

  it("counts a send that fails as done too: the connection dropped with writes queued, or a send after the close", async () => {
    const { agent } = await accountWithAgentAndMobile();
    const joined: HubSocket[] = [];
    const app = makeApp({ hubs: registryCapturingSockets(joined) });
    const a = await connect(app, agent.token);
    const server = await waitFor(async () => joined[0]);
    a.ws.pause();
    const frame = new Uint8Array(64 * 1024);
    for (let i = 0; i < 400; i++) server.send(frame);
    await new Promise((resolve) => setTimeout(resolve, 100));
    expect(server.pendingSends).toBeGreaterThan(0);

    server.terminate(); // every queued write now fails
    await waitFor(async () => (server.pendingSends === 0 ? true : null));
    expect(server.readyState).toBe(WebSocket.CLOSED);
    server.send(Uint8Array.of(1)); // too late: fails, without throwing
    expect(server.pendingSends).toBe(1);
    await waitFor(async () => (server.pendingSends === 0 ? true : null));
    a.ws.resume(); // lets the client see the dropped connection
    expect((await a.closed).code).toBe(1006);
  }, 30_000);
});

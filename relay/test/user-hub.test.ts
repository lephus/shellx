import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import { Db } from "../src/db/db.js";
import { migrate } from "../src/db/migrate.js";
import { HubRegistry } from "../src/hub/registry.js";
import { FRAMES_PER_SECOND } from "../src/hub/token-bucket.js";
import {
  GOING_AWAY, MAX_BUFFERED_BYTES, SLOW_RECEIVER_CLOSE_MS, TRY_AGAIN_LATER, type UserHub,
} from "../src/hub/user-hub.js";
import {
  CloseCode, encodeData, encodeError, encodePresence, MAX_FRAME_BYTES, pairingRemovedEvent, RelayErrorCode,
} from "../src/protocol/frames.js";
import { db, FakeSocket, hex, newPairingId, tempDir } from "./helpers.js";

const CH = Uint8Array.from([9, 8, 7, 6, 5, 4, 3, 2]);

afterEach(() => {
  vi.restoreAllMocks();
});

/** The client (or the network) closed the socket: what the ws route reports to the hub. */
function clientCloses(hub: UserHub, socket: FakeSocket): void {
  socket.readyState = 3;
  hub.disconnected(socket);
}

/** A user row and one device row, written directly (no argon2 needed at this level). */
function seedUser(database: Db = db()): { userId: string; device: (kind: "agent" | "mobile") => string } {
  const userId = crypto.randomUUID();
  database.run("INSERT INTO users VALUES (?, ?, 'x', 1, 1)", userId, `${userId}@example.com`);
  return {
    userId,
    device(kind) {
      const id = crypto.randomUUID();
      database.run(
        "INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at) VALUES (?, ?, ?, 'n', ?, ?, 1)",
        id, userId, kind, kind === "agent" ? "macos" : "ios", crypto.getRandomValues(new Uint8Array(32)),
      );
      return id;
    },
  };
}

async function joinHub(hub: UserHub, socket: FakeSocket, deviceId: string, kind: "agent" | "mobile" = "mobile", connId = crypto.randomUUID()) {
  await hub.connect(socket, { deviceId, kind, connId });
  return connId;
}

function setup(now?: () => number) {
  const registry = new HubRegistry({ db: db(), now });
  const user = seedUser();
  const agentId = user.device("agent");
  const mobileId = user.device("mobile");
  return { registry, hub: registry.forUser(user.userId), userId: user.userId, agentId, mobileId, user };
}

describe("presence and routing", () => {
  it("sends a presence snapshot to the newcomer and announces it to the others", async () => {
    const { hub, agentId, mobileId } = setup();
    const a = new FakeSocket();
    const m = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    expect(a.take()).toEqual([]);
    await joinHub(hub, m, mobileId);
    expect(m.take()).toEqual([hex(encodePresence(agentId, true))]);
    expect(a.take()).toEqual([hex(encodePresence(mobileId, true))]);
    expect((await hub.online()).sort()).toEqual([agentId, mobileId].sort());
  });

  it("routes DATA to the peer with the peer field rewritten to the sender, and answers peer_offline otherwise", async () => {
    const { hub, agentId, mobileId } = setup();
    const a = new FakeSocket();
    const m = new FakeSocket();
    await joinHub(hub, m, mobileId);
    hub.receive(m, encodeData(agentId, CH, Uint8Array.of(4)).buffer as ArrayBuffer);
    await hub.idle();
    expect(m.take()).toEqual([hex(encodeError(RelayErrorCode.peerOffline, agentId, CH))]);

    await joinHub(hub, a, agentId, "agent");
    a.take();
    m.take();
    hub.receive(m, encodeData(agentId, CH, Uint8Array.of(0xde, 0xad)));
    await hub.idle();
    expect(a.take()).toEqual([hex(encodeData(mobileId, CH, Uint8Array.of(0xde, 0xad)))]);
  });

  it("never routes to a device of another account", async () => {
    const registry = new HubRegistry({ db: db() });
    const alice = seedUser();
    const bob = seedUser();
    const aliceMobile = alice.device("mobile");
    const bobAgent = bob.device("agent");
    const attacker = new FakeSocket();
    const victim = new FakeSocket();
    await joinHub(registry.forUser(bob.userId), victim, bobAgent, "agent");
    await joinHub(registry.forUser(alice.userId), attacker, aliceMobile);
    expect(attacker.take()).toEqual([]); // Bob's agent is not in Alice's snapshot
    registry.forUser(alice.userId).receive(attacker, encodeData(bobAgent, CH, Uint8Array.of(4, 1)));
    await registry.forUser(alice.userId).idle();
    expect(attacker.take()).toEqual([hex(encodeError(RelayErrorCode.peerOffline, bobAgent, CH))]);
    expect(victim.take()).toEqual([]);
  });

  it("enforces the 64 KiB frame limit and answers malformed frames and stray text with bad_frame", async () => {
    const { hub, agentId, mobileId } = setup();
    const a = new FakeSocket();
    const m = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    await joinHub(hub, m, mobileId);
    a.take();
    m.take();
    hub.receive(m, encodeData(agentId, CH, new Uint8Array(MAX_FRAME_BYTES - 26)));
    hub.receive(m, encodeData(agentId, CH, new Uint8Array(MAX_FRAME_BYTES - 25)));
    hub.receive(m, new Uint8Array(10));
    hub.receive(m, "hello");
    await hub.idle();
    expect(a.sent.map((f) => (f as Uint8Array).length)).toEqual([65536]);
    expect(m.take()).toEqual([
      hex(encodeError(RelayErrorCode.frameTooLarge, agentId, CH)),
      hex(encodeError(RelayErrorCode.badFrame)),
      hex(encodeError(RelayErrorCode.badFrame)),
    ]);
    expect(m.closedWith).toBeNull();
  });

  it("replaces an older connection of the same device with 4001 without announcing it offline", async () => {
    const { hub, agentId, mobileId } = setup();
    const a = new FakeSocket();
    const m1 = new FakeSocket();
    const m2 = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    await joinHub(hub, m1, mobileId);
    a.take();
    await joinHub(hub, m2, mobileId);
    expect(m1.closedWith).toEqual({ code: 4001, reason: "replaced" });
    expect(m2.take()).toEqual([hex(encodePresence(agentId, true))]);
    clientCloses(hub, m1); // the replaced socket's close event arrives later
    await hub.idle();
    expect(a.take()).toEqual([hex(encodePresence(mobileId, true))]); // no offline
    hub.receive(a, encodeData(mobileId, CH, Uint8Array.of(4)));
    await hub.idle();
    expect(m2.sent.length).toBe(1);
  });

  it("announces offline and records last_seen_at when a device's socket closes", async () => {
    const { hub, agentId, mobileId } = setup(() => 1_900_000_000_000);
    const a = new FakeSocket();
    const m = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    await joinHub(hub, m, mobileId);
    a.take();
    clientCloses(hub, m);
    await hub.idle();
    expect(a.take()).toEqual([hex(encodePresence(mobileId, false))]);
    expect(db().get("SELECT last_seen_at FROM devices WHERE id = ?", mobileId)).toEqual({ last_seen_at: 1_900_000_000_000 });
  });

  it("tolerates a failing last_seen_at write, logging metadata only and still announcing offline", async () => {
    const { hub, agentId, mobileId } = setup();
    const a = new FakeSocket();
    const m = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    await joinHub(hub, m, mobileId);
    a.take();
    const lines: string[] = [];
    vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    });
    vi.spyOn(db(), "run").mockImplementation(() => {
      throw Object.assign(new Error("disk I/O error at /data/relay.db"), { code: "SQLITE_IOERR" });
    });
    clientCloses(hub, m);
    await hub.idle();
    expect(a.take()).toEqual([hex(encodePresence(mobileId, false))]);
    expect(lines.join("\n")).toContain(`"event":"last_seen_write_failed","device_id":"${mobileId}","error":"SQLITE_IOERR"`);
    expect(lines.join("\n")).not.toContain("disk I/O");
  });
});

describe("frame budget (500 frames/s per device)", () => {
  it("sends ERROR rate_limited, closes with 4003 and announces offline once the budget is spent", async () => {
    const frozen = 1_900_000_000_000;
    const { hub, agentId, mobileId } = setup(() => frozen);
    const a = new FakeSocket();
    const m = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    await joinHub(hub, m, mobileId);
    a.take();
    m.take();
    for (let i = 0; i < 600; i++) hub.receive(m, encodeData(agentId, CH, Uint8Array.of(4)));
    await hub.idle();
    expect(a.sent.length).toBe(FRAMES_PER_SECOND + 1); // 500 frames + PRESENCE offline
    expect(hex(a.sent.at(-1) as Uint8Array)).toBe(hex(encodePresence(mobileId, false)));
    expect(m.take()).toEqual([hex(encodeError(RelayErrorCode.rateLimited))]);
    expect(m.closedWith).toEqual({ code: 4003, reason: "rate_limited" });
  });

  it("keeps a spent budget across a reconnect and across the hub being dropped and re-created", async () => {
    const frozen = 1_900_000_000_000;
    const { registry, userId, agentId, mobileId } = setup(() => frozen);
    const m = new FakeSocket();
    await joinHub(registry.forUser(userId), m, mobileId);
    for (let i = 0; i < 450; i++) registry.forUser(userId).receive(m, encodeData(agentId, CH, Uint8Array.of(4)));
    clientCloses(registry.forUser(userId), m);
    await registry.forUser(userId).idle();
    await registry.whenEmpty();
    expect(registry.size).toBe(0); // the hub is gone...

    const again = new FakeSocket();
    await joinHub(registry.forUser(userId), again, mobileId);
    for (let i = 0; i < 51; i++) registry.forUser(userId).receive(again, encodeData(agentId, CH, Uint8Array.of(4)));
    await registry.forUser(userId).idle();
    // ...but the device still had only 50 frames left: the 51st trips the limit.
    expect(again.closedWith).toEqual({ code: 4003, reason: "rate_limited" });
  });

  it("counts text pings against the same budget: the 501st gets ERROR rate_limited and 4003, not a pong (R1)", async () => {
    const frozen = 1_900_000_000_000;
    const { hub, agentId, mobileId } = setup(() => frozen);
    const a = new FakeSocket();
    const m = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    await joinHub(hub, m, mobileId);
    a.take();
    m.take();
    for (let i = 0; i < FRAMES_PER_SECOND + 1; i++) hub.ping(m, mobileId);
    await hub.idle();
    const replies = m.take();
    expect(replies.slice(0, FRAMES_PER_SECOND)).toEqual(Array<string>(FRAMES_PER_SECOND).fill("text:pong"));
    expect(replies.slice(FRAMES_PER_SECOND)).toEqual([hex(encodeError(RelayErrorCode.rateLimited))]);
    expect(m.closedWith).toEqual({ code: 4003, reason: "rate_limited" });
    expect(a.take()).toEqual([hex(encodePresence(mobileId, false))]);
  });

  it("shares the budget between pings and binary frames (R1)", async () => {
    const frozen = 1_900_000_000_000;
    const { hub, agentId, mobileId } = setup(() => frozen);
    const m = new FakeSocket();
    await joinHub(hub, m, mobileId);
    for (let i = 0; i < 400; i++) hub.ping(m, mobileId);
    for (let i = 0; i < 100; i++) hub.receive(m, encodeData(agentId, CH, Uint8Array.of(4)));
    await hub.idle();
    expect(m.closedWith).toBeNull(); // exactly 500 so far
    hub.ping(m, mobileId);
    await hub.idle();
    expect(m.closedWith).toEqual({ code: 4003, reason: "rate_limited" });
  });
});

describe("slow receivers (backpressure)", () => {
  const NOW = 1_900_000_000_000;

  function captureLogs(): string[] {
    const lines: string[] = [];
    vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    });
    return lines;
  }

  it("closes a DATA target whose unsent backlog is over 4 MiB with 1013 instead of relaying; the sender is unaffected", async () => {
    expect(MAX_BUFFERED_BYTES).toBe(4 * 1024 * 1024);
    const { hub, agentId, mobileId } = setup(() => NOW);
    const a = new FakeSocket();
    const m = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    await joinHub(hub, m, mobileId);
    a.take();
    m.take();
    const lines = captureLogs();
    m.bufferedAmount = MAX_BUFFERED_BYTES + 1;
    hub.receive(a, encodeData(mobileId, CH, Uint8Array.of(0xde, 0xad)));
    await hub.idle();

    expect(m.closedWith).toEqual({ code: TRY_AGAIN_LATER, reason: "try again later" });
    expect(m.sent).toEqual([]); // the frame was not queued on top of the backlog
    expect(a.closedWith).toBeNull();
    expect(a.take()).toEqual([hex(encodePresence(mobileId, false))]); // only told that the peer left
    expect(await hub.online()).toEqual([agentId]);
    expect(db().get("SELECT last_seen_at FROM devices WHERE id = ?", mobileId)).toEqual({ last_seen_at: NOW });
    const logged = lines.map((line) => JSON.parse(line) as Record<string, unknown>).filter((e) => e.event === "slow_receiver");
    expect(logged).toHaveLength(1);
    expect(Object.keys(logged[0]!).sort()).toEqual(["device_id", "event", "ts"]); // metadata only
    expect(logged[0]!.device_id).toBe(mobileId);

    // The sender keeps working, and the slow socket's own close event later changes nothing.
    clientCloses(hub, m);
    hub.receive(a, encodeData(mobileId, CH, Uint8Array.of(1)));
    await hub.idle();
    expect(a.take()).toEqual([hex(encodeError(RelayErrorCode.peerOffline, mobileId, CH))]);
    expect(a.closedWith).toBeNull();
  });

  it("still relays to a target whose backlog is exactly at the cap", async () => {
    const { hub, agentId, mobileId } = setup();
    const a = new FakeSocket();
    const m = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    await joinHub(hub, m, mobileId);
    a.take();
    m.take();
    m.bufferedAmount = MAX_BUFFERED_BYTES;
    hub.receive(a, encodeData(mobileId, CH, Uint8Array.of(7)));
    await hub.idle();
    expect(m.take()).toEqual([hex(encodeData(agentId, CH, Uint8Array.of(7)))]);
    expect(m.closedWith).toBeNull();
  });

  it("applies the same cap to ERROR replies: a sender that never reads them is closed with 1013", async () => {
    const { hub, agentId, mobileId } = setup();
    const m = new FakeSocket();
    await joinHub(hub, m, mobileId);
    m.bufferedAmount = MAX_BUFFERED_BYTES + 1;
    hub.receive(m, encodeData(agentId, CH, Uint8Array.of(4))); // the agent is offline: an ERROR would be queued
    await hub.idle();
    expect(m.sent).toEqual([]);
    expect(m.closedWith).toEqual({ code: TRY_AGAIN_LATER, reason: "try again later" });
    expect(await hub.online()).toEqual([]);
  });

  it("applies the same cap to PRESENCE: a slow peer is closed instead of being sent the newcomer's arrival", async () => {
    const { hub, agentId, mobileId } = setup();
    const a = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    a.bufferedAmount = MAX_BUFFERED_BYTES + 1;
    const m = new FakeSocket();
    await joinHub(hub, m, mobileId);
    expect(a.sent).toEqual([]);
    expect(a.closedWith).toEqual({ code: TRY_AGAIN_LATER, reason: "try again later" });
    // The newcomer saw the agent in its snapshot, then saw it leave.
    expect(m.take()).toEqual([hex(encodePresence(agentId, true)), hex(encodePresence(agentId, false))]);
  });

  it("answers ping with pong outside the queue, but closes a slow receiver with 1013 instead", async () => {
    const { hub, agentId, mobileId } = setup();
    const a = new FakeSocket();
    const m = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    await joinHub(hub, m, mobileId);
    a.take();
    m.take();
    hub.ping(m, mobileId);
    expect(m.take()).toEqual(["text:pong"]); // synchronously, not through the queue

    m.bufferedAmount = MAX_BUFFERED_BYTES + 1;
    hub.ping(m, mobileId);
    await hub.idle();
    expect(m.sent).toEqual([]);
    expect(m.closedWith).toEqual({ code: TRY_AGAIN_LATER, reason: "try again later" });
    expect(a.take()).toEqual([hex(encodePresence(mobileId, false))]);
  });

  it("never answers a ping while the socket still has unsent bytes, and keeps the socket open (R1)", async () => {
    const { hub, mobileId } = setup();
    const m = new FakeSocket();
    await joinHub(hub, m, mobileId);
    m.bufferedAmount = 1; // a pong would queue behind it: bufferedAmount counts 4 bytes, the heap far more
    hub.ping(m, mobileId);
    hub.ping(m, mobileId);
    await hub.idle();
    expect(m.sent).toEqual([]);
    expect(m.closedWith).toBeNull(); // the client's own heartbeat times out on a stuck socket

    m.bufferedAmount = 0; // drained: heartbeats are answered again
    hub.ping(m, mobileId);
    expect(m.take()).toEqual(["text:pong"]);
  });

  it("terminates a slow receiver that has not finished closing 1 s after its 1013, with an unref'd timer (R1)", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
    // Spies on the fake setTimeout; restored before the real timers come back (see finally).
    const setTimer = vi.spyOn(globalThis, "setTimeout");
    try {
      const { hub, agentId, mobileId } = setup();
      const a = new FakeSocket();
      const m = new FakeSocket();
      await joinHub(hub, a, agentId, "agent");
      await joinHub(hub, m, mobileId);
      m.bufferedAmount = MAX_BUFFERED_BYTES + 1; // never drains
      hub.receive(a, encodeData(mobileId, CH, Uint8Array.of(1)));
      await hub.idle();
      expect(m.closedWith).toEqual({ code: TRY_AGAIN_LATER, reason: "try again later" });
      expect(SLOW_RECEIVER_CLOSE_MS).toBe(1000);
      const timer = setTimer.mock.results.find((r, i) => setTimer.mock.calls[i]![1] === SLOW_RECEIVER_CLOSE_MS)?.value as NodeJS.Timeout;
      expect(timer.hasRef()).toBe(false); // never keeps the process alive

      vi.advanceTimersByTime(SLOW_RECEIVER_CLOSE_MS - 1);
      expect(m.terminated).toBe(false);
      vi.advanceTimersByTime(1);
      expect(m.terminated).toBe(true);
      expect(a.terminated).toBe(false);
    } finally {
      setTimer.mockRestore();
      vi.useRealTimers();
    }
  });

  it("does not terminate a slow receiver whose close completes within 1 s: the timer is cleared on close (R1)", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
    try {
      const { hub, agentId, mobileId } = setup();
      const a = new FakeSocket();
      const m = new FakeSocket();
      await joinHub(hub, a, agentId, "agent");
      await joinHub(hub, m, mobileId);
      m.bufferedAmount = MAX_BUFFERED_BYTES + 1;
      hub.receive(a, encodeData(mobileId, CH, Uint8Array.of(1)));
      await hub.idle();
      vi.advanceTimersByTime(SLOW_RECEIVER_CLOSE_MS - 1);
      clientCloses(hub, m); // the close handshake finished in time
      await hub.idle();
      expect(vi.getTimerCount()).toBe(0);
      vi.advanceTimersByTime(10 * SLOW_RECEIVER_CLOSE_MS);
      expect(m.terminated).toBe(false);
    } finally {
      vi.useRealTimers();
    }
  });
});

describe("lingering sockets (R1)", () => {
  it("a reconnect terminates the device's earlier socket that is still closing; the one it replaces still gets 4001", async () => {
    const { hub, agentId, mobileId } = setup();
    const a = new FakeSocket();
    const m1 = new FakeSocket();
    const m2 = new FakeSocket();
    const m3 = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    await joinHub(hub, m1, mobileId);
    await joinHub(hub, m2, mobileId);
    expect(m1.closedWith).toEqual({ code: 4001, reason: "replaced" }); // closing; its close event has not arrived
    expect(m1.terminated).toBe(false);

    await joinHub(hub, m3, mobileId);
    expect(m1.terminated).toBe(true); // at most one earlier socket per device is left holding memory
    expect(m2.closedWith).toEqual({ code: 4001, reason: "replaced" }); // the normal close handshake
    expect(m2.terminated).toBe(false);
    expect(a.terminated).toBe(false); // other devices are never touched
    expect(a.closedWith).toBeNull();
  });

  it("a reconnect terminates the device's slow receiver still stuck in its 1013 close", async () => {
    const { hub, agentId, mobileId } = setup();
    const a = new FakeSocket();
    const slow = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    await joinHub(hub, slow, mobileId);
    slow.bufferedAmount = MAX_BUFFERED_BYTES + 1;
    hub.receive(a, encodeData(mobileId, CH, Uint8Array.of(1)));
    await hub.idle();
    expect(slow.closedWith).toEqual({ code: TRY_AGAIN_LATER, reason: "try again later" });

    const again = new FakeSocket();
    await joinHub(hub, again, mobileId);
    expect(slow.terminated).toBe(true);
    expect(again.closedWith).toBeNull();
    expect(await hub.online()).toEqual(expect.arrayContaining([agentId, mobileId]));
  });
});

describe("pairing_removed tombstones", () => {
  it("records the tombstone even for an online agent, sends the event live, and replays it on every connect", async () => {
    const { hub, agentId, mobileId } = setup();
    const a = new FakeSocket();
    const m = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    await joinHub(hub, m, mobileId);
    a.take();
    m.take();
    const id = newPairingId();
    await hub.notifyPairingRemoved(agentId, mobileId, id);
    const event = hex(pairingRemovedEvent(agentId, mobileId, id));
    expect(a.take()).toEqual([event]);
    expect(m.take()).toEqual([event]);

    for (let i = 0; i < 2; i++) {
      const again = new FakeSocket();
      await joinHub(hub, again, agentId, "agent");
      expect(again.take()).toEqual([hex(encodePresence(mobileId, true)), event]); // snapshot first
    }
  });

  it("keeps one tombstone per (agent, mobile) holding the newest id", async () => {
    const { hub, agentId, mobileId, user } = setup();
    const other = user.device("mobile");
    const [w, x, y, z] = [newPairingId(), newPairingId(), newPairingId(), newPairingId()];
    await hub.notifyPairingRemoved(agentId, mobileId, x);
    await hub.notifyPairingRemoved(agentId, other, z);
    await hub.notifyPairingRemoved(agentId, mobileId, y); // newer: overwrites x
    await hub.notifyPairingRemoved(agentId, mobileId, w); // older: y stays
    const a = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    expect(a.take().sort()).toEqual(
      [hex(pairingRemovedEvent(agentId, mobileId, y)), hex(pairingRemovedEvent(agentId, other, z))].sort(),
    );
  });

  it("never lets another account's hub overwrite a tombstone row that belongs to this account", async () => {
    const registry = new HubRegistry({ db: db() });
    const [alice, bob] = [seedUser(), seedUser()];
    const agentId = alice.device("agent");
    const mobileId = alice.device("mobile");
    const [older, newer] = [newPairingId(), newPairingId()];
    await registry.forUser(alice.userId).notifyPairingRemoved(agentId, mobileId, older);
    await registry.forUser(bob.userId).notifyPairingRemoved(agentId, mobileId, newer); // Alice's device ids, Bob's hub
    expect(db().all("SELECT user_id, pairing_id FROM pending_pairing_removed WHERE agent_id = ?", agentId)).toEqual([
      { user_id: alice.userId, pairing_id: older },
    ]);
    const a = new FakeSocket();
    await joinHub(registry.forUser(alice.userId), a, agentId, "agent");
    expect(a.take()).toEqual([hex(pairingRemovedEvent(agentId, mobileId, older))]);
  });

  it("admitPairing refuses ids not newer than the tombstone (keeping it) and clears it for a newer id", async () => {
    const { hub } = setup();
    const agentId = crypto.randomUUID();
    const mobileId = crypto.randomUUID();
    const [w, x, y] = [newPairingId(), newPairingId(), newPairingId()];
    expect(await hub.admitPairing(agentId, mobileId, x)).toBe(true);
    await hub.notifyPairingRemoved(agentId, mobileId, x);
    expect(await hub.admitPairing(agentId, mobileId, x)).toBe(false);
    expect(await hub.admitPairing(agentId, mobileId, w)).toBe(false);
    expect(await hub.admitPairing(crypto.randomUUID(), mobileId, w)).toBe(true); // other agent: untouched
    expect(await hub.admitPairing(agentId, mobileId, x)).toBe(false);
    expect(await hub.admitPairing(agentId, mobileId, y)).toBe(true); // newer: clears x's tombstone
    expect(await hub.admitPairing(agentId, mobileId, w)).toBe(true);
    expect(await hub.purgeAll()).toBe(0);
  });

  it("purgeAgent and purgeAll remove only this account's rows and report how many", async () => {
    const registry = new HubRegistry({ db: db() });
    const [alice, bob] = [seedUser(), seedUser()];
    const aliceHub = registry.forUser(alice.userId);
    const bobHub = registry.forUser(bob.userId);
    const [a1, a2, b1] = [crypto.randomUUID(), crypto.randomUUID(), crypto.randomUUID()];
    await aliceHub.notifyPairingRemoved(a1, crypto.randomUUID(), newPairingId());
    await aliceHub.notifyPairingRemoved(a1, crypto.randomUUID(), newPairingId());
    await aliceHub.notifyPairingRemoved(a2, crypto.randomUUID(), newPairingId());
    await bobHub.notifyPairingRemoved(b1, crypto.randomUUID(), newPairingId());
    expect(await aliceHub.purgeAgent(a1)).toBe(2);
    expect(await aliceHub.purgeAgent(a1)).toBe(0);
    expect(await bobHub.purgeAgent(a2)).toBe(0); // another account's agent id
    expect(await aliceHub.purgeAll()).toBe(1);
    expect(await bobHub.purgeAll()).toBe(1);
  });

  it("survives a relay restart: a new registry over the reopened database still replays it", async () => {
    const path = join(tempDir(), "restart.db");
    const first = Db.open(path);
    migrate(first);
    const user = seedUser(first);
    const agentId = user.device("agent");
    const mobileId = crypto.randomUUID();
    const id = newPairingId();
    await new HubRegistry({ db: first }).forUser(user.userId).notifyPairingRemoved(agentId, mobileId, id);
    first.close();

    const second = Db.open(path);
    try {
      migrate(second);
      const a = new FakeSocket();
      await new HubRegistry({ db: second }).forUser(user.userId).connect(a, { deviceId: agentId, kind: "agent", connId: "c" });
      expect(a.take()).toEqual([hex(pairingRemovedEvent(agentId, mobileId, id))]);
    } finally {
      second.close();
    }
  });
});

describe("REST-side operations", () => {
  it("disconnect closes the given devices with the code, announces them offline, and is a no-op when gone", async () => {
    const { hub, agentId, mobileId } = setup();
    const a = new FakeSocket();
    const m = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    await joinHub(hub, m, mobileId);
    a.take();
    await hub.disconnect([mobileId], CloseCode.revoked);
    expect(m.closedWith).toEqual({ code: 4002, reason: "revoked" });
    expect(a.take()).toEqual([hex(encodePresence(mobileId, false))]);
    expect(await hub.online()).toEqual([agentId]);
    await hub.disconnect([mobileId], CloseCode.revoked);
    expect(a.take()).toEqual([]);
  });

  it("disconnectAllExcept closes every other device, including one whose join was queued in the same tick just before it", async () => {
    const { hub, agentId, mobileId, user } = setup();
    const secondAgent = user.device("agent");
    const [a, m, a2] = [new FakeSocket(), new FakeSocket(), new FakeSocket()];
    await joinHub(hub, a, agentId, "agent");
    await joinHub(hub, m, mobileId);
    // Both queued before either runs: the hub uses its own live list when the disconnect runs.
    const joining = joinHub(hub, a2, secondAgent, "agent");
    const closing = hub.disconnectAllExcept(agentId, CloseCode.revoked);
    expect(a2.closedWith).toBeNull(); // nothing has run yet
    await Promise.all([joining, closing]);
    expect(m.closedWith?.code).toBe(4002);
    expect(a2.closedWith?.code).toBe(4002);
    expect(a.closedWith).toBeNull();
  });

  it("closeAccount closes with 4002 a socket whose join was queued in the same tick just before it, and purges the tombstones", async () => {
    const { hub, agentId, mobileId } = setup();
    await hub.notifyPairingRemoved(agentId, mobileId, newPairingId());
    const late = new FakeSocket();
    // Both queued before either runs: the join lands after any device list a route could have read.
    const joining = joinHub(hub, late, mobileId);
    const closing = hub.closeAccount();
    expect(late.closedWith).toBeNull(); // nothing has run yet
    await Promise.all([joining, closing]);
    expect(late.closedWith).toEqual({ code: 4002, reason: "revoked" });
    expect(await hub.purgeAll()).toBe(0);
  });

  it("closeConnection closes only that exact connection, never a newer one of the same device", async () => {
    const { hub, mobileId } = setup();
    const stale = new FakeSocket();
    const staleConn = await joinHub(hub, stale, mobileId);
    const fresh = new FakeSocket();
    await joinHub(hub, fresh, mobileId); // replaces the stale one (4001)
    await hub.closeConnection(staleConn, CloseCode.revoked);
    expect(stale.closedWith).toEqual({ code: 4001, reason: "replaced" });
    expect(fresh.closedWith).toBeNull();

    const freshConn = await joinHub(hub, new FakeSocket(), crypto.randomUUID());
    await hub.closeConnection(freshConn, CloseCode.revoked);
    expect(await hub.online()).toEqual([mobileId]);
  });
});

describe("serial queue and lifecycle", () => {
  it("runs operations in arrival order and survives a failing one, logging only its kind", async () => {
    const { hub, agentId, mobileId } = setup();
    const lines: string[] = [];
    vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    });
    const order: string[] = [];
    const first = hub.admitPairing(agentId, mobileId, newPairingId()).then(() => order.push("first"));
    const spy = vi.spyOn(db(), "run").mockImplementationOnce(() => {
      throw Object.assign(new Error("database is locked: INSERT INTO pending_pairing_removed ..."), { code: "SQLITE_BUSY" });
    });
    const failing = hub.notifyPairingRemoved(agentId, mobileId, newPairingId()).catch((err: unknown) => {
      order.push("failed");
      return err;
    });
    const third = hub.online().then(() => order.push("third"));
    await Promise.all([first, failing, third]);
    spy.mockRestore();
    expect(order).toEqual(["first", "failed", "third"]);
    expect(await failing).toMatchObject({ code: "SQLITE_BUSY" });
    const output = lines.join("\n");
    expect(output).toContain('"event":"hub_op_failed"');
    expect(output).toContain('"op":"notify_pairing_removed"');
    expect(output).toContain('"error":"SQLITE_BUSY"');
    expect(output).not.toContain("INSERT INTO");
    expect(await hub.admitPairing(agentId, mobileId, newPairingId())).toBe(true); // still working
  });

  it("drops a hub once it has no socket and no queued work, and never one that still holds a socket", async () => {
    const { registry, userId, mobileId } = setup();
    await registry.forUser(userId).online();
    await registry.whenEmpty();
    expect(registry.size).toBe(0);

    const m = new FakeSocket();
    await joinHub(registry.forUser(userId), m, mobileId);
    await registry.forUser(userId).idle();
    expect(registry.size).toBe(1);
    clientCloses(registry.forUser(userId), m);
    await registry.whenEmpty();
    expect(registry.size).toBe(0);

    registry.forUser(crypto.randomUUID()); // a handle alone creates no state
    expect(registry.size).toBe(0);
    registry.stateFor(crypto.randomUUID()); // state created, but nothing ever queued on it
    expect(registry.size).toBe(1);
    await registry.whenEmpty(); // released by the microtask queued at creation
    expect(registry.size).toBe(0);
  });

  it("ignores a socket that closed after its join was queued but before its turn came", async () => {
    const { hub, agentId, mobileId } = setup();
    const a = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    const gone = new FakeSocket();
    const joining = joinHub(hub, gone, mobileId);
    clientCloses(hub, gone); // same tick: the close event is queued behind the join
    await joining;
    await hub.idle();
    expect(gone.sent).toEqual([]);
    expect(gone.closedWith).toBeNull();
    expect(a.take()).toEqual([]); // never announced online, so never offline either
    expect(await hub.online()).toEqual([agentId]);
  });

  it("rejects a join whose tombstones cannot be read, leaving the socket out of the hub", async () => {
    const { hub, agentId } = setup();
    vi.spyOn(db(), "all").mockImplementationOnce(() => {
      throw Object.assign(new Error("database is locked"), { code: "SQLITE_BUSY" });
    });
    const a = new FakeSocket();
    await expect(joinHub(hub, a, agentId, "agent")).rejects.toMatchObject({ code: "SQLITE_BUSY" });
    expect(await hub.online()).toEqual([]);
    // Untouched: the ws route closes it with 1011, the hub neither sent to it nor closed it.
    expect(a.sent).toEqual([]);
    expect(a.closedWith).toBeNull();
    expect(a.terminated).toBe(false);
  });

  it("accepts synchronous tasks only: an async task would let other operations run at its await", () => {
    const { registry, userId } = setup();
    const state = registry.stateFor(userId);
    // Compile-time check (npm run typecheck): never called.
    const _asyncTaskIsRejected = () =>
      // @ts-expect-error — enqueue's task must not return a promise
      state["enqueue"]("async", async () => undefined);
    expect(typeof _asyncTaskIsRejected).toBe("function");
    const _syncTaskIsAccepted = () => state["enqueue"]("sync", () => 1);
    expect(typeof _syncTaskIsAccepted).toBe("function");
  });

  it("goAway closes every socket with 1001, refuses later joins the same way, and empties the registry", async () => {
    const { registry, userId, agentId, mobileId } = setup();
    const a = new FakeSocket();
    const m = new FakeSocket();
    await joinHub(registry.forUser(userId), a, agentId, "agent");
    await joinHub(registry.forUser(userId), m, mobileId);
    const done = registry.goAway();
    await registry.forUser(userId).idle();
    expect(a.closedWith).toEqual({ code: GOING_AWAY, reason: "going away" });
    expect(m.closedWith).toEqual({ code: GOING_AWAY, reason: "going away" });

    const late = new FakeSocket();
    await joinHub(registry.forUser(userId), late, crypto.randomUUID());
    expect(late.closedWith).toEqual({ code: GOING_AWAY, reason: "going away" });

    clientCloses(registry.forUser(userId), a);
    clientCloses(registry.forUser(userId), m);
    await done;
    expect(registry.size).toBe(0);
  });

  it("goAway records last_seen_at for every device still connected (their close events are ignored)", async () => {
    const now = 1_900_000_000_000;
    const { registry, userId, agentId, mobileId, user } = setup(() => now);
    const replacedEarlier = user.device("mobile");
    const a = new FakeSocket();
    const m = new FakeSocket();
    await joinHub(registry.forUser(userId), a, agentId, "agent");
    await joinHub(registry.forUser(userId), m, mobileId);
    db().run("UPDATE devices SET last_seen_at = 5 WHERE id = ?", replacedEarlier); // not connected: untouched
    const done = registry.goAway();
    await registry.forUser(userId).idle();
    const seen = (id: string) => db().get<{ last_seen_at: number | null }>("SELECT last_seen_at FROM devices WHERE id = ?", id)!.last_seen_at;
    expect(seen(agentId)).toBe(now);
    expect(seen(mobileId)).toBe(now);
    expect(seen(replacedEarlier)).toBe(5);
    clientCloses(registry.forUser(userId), a);
    clientCloses(registry.forUser(userId), m);
    await done;
  });

  it("goAway still closes every socket with 1001 when the last_seen_at write fails, logging the error kind only", async () => {
    const { registry, userId, agentId, mobileId } = setup();
    const a = new FakeSocket();
    const m = new FakeSocket();
    await joinHub(registry.forUser(userId), a, agentId, "agent");
    await joinHub(registry.forUser(userId), m, mobileId);
    const lines: string[] = [];
    vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    });
    vi.spyOn(db(), "run").mockImplementation(() => {
      throw Object.assign(new Error("database is locked: UPDATE devices ..."), { code: "SQLITE_BUSY" });
    });
    const done = registry.goAway();
    await registry.forUser(userId).idle();
    expect(a.closedWith).toEqual({ code: GOING_AWAY, reason: "going away" });
    expect(m.closedWith).toEqual({ code: GOING_AWAY, reason: "going away" });
    const output = lines.join("\n");
    expect(output).toContain(`"event":"last_seen_write_failed","device_id":"${agentId}","error":"SQLITE_BUSY"`);
    expect(output).toContain(`"event":"last_seen_write_failed","device_id":"${mobileId}","error":"SQLITE_BUSY"`);
    expect(output).not.toContain("UPDATE devices");
    expect(output).not.toContain("hub_op_failed"); // best effort: the operation itself succeeded
    clientCloses(registry.forUser(userId), a);
    clientCloses(registry.forUser(userId), m);
    await done;
  });

  it("terminateAll drops sockets that never answered the close handshake", async () => {
    const { registry, userId, agentId } = setup();
    const a = new FakeSocket();
    await joinHub(registry.forUser(userId), a, agentId, "agent");
    void registry.goAway();
    await registry.forUser(userId).idle();
    registry.terminateAll();
    expect(a.terminated).toBe(true);
  });
});

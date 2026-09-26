import { describe, expect, it } from "vitest";
import { FRAMES_PER_SECOND, TokenBucket } from "../src/hub/token-bucket.js";
import { encodeData, encodeError, encodePresence, RelayErrorCode } from "../src/protocol/frames.js";
import { connect, hex, loginDevice, makeApp, newHubRegistry, registerAccount } from "./helpers.js";

const CH = Uint8Array.from([1, 1, 2, 3, 5, 8, 13, 21]);

describe("TokenBucket", () => {
  it("allows a burst of `capacity`, then refills at the configured rate", () => {
    const bucket = new TokenBucket(500, 500, 0);
    for (let i = 0; i < 500; i++) expect(bucket.take(0)).toBe(true);
    expect(bucket.take(0)).toBe(false);
    expect(bucket.take(1)).toBe(false); // 0.5 token
    expect(bucket.take(2)).toBe(true); // 1 token after 2 ms
    expect(bucket.take(2)).toBe(false);
  });

  it("never stores more than `capacity` tokens", () => {
    const bucket = new TokenBucket(500, 500, 0);
    bucket.take(0);
    let allowed = 0;
    while (bucket.take(60_000)) allowed++;
    expect(allowed).toBe(500);
    expect(FRAMES_PER_SECOND).toBe(500);
  });
});

/**
 * Two connected devices on a relay whose hubs read a frozen clock, so the token math is exact no
 * matter how long the sends take on the host (the Workers version froze Date.now with fake timers;
 * here the registry's clock is injected instead, which leaves the sockets' own timers alone).
 */
async function hubWithTwoDevices(frozen = true) {
  const app = makeApp(frozen ? { hubs: newHubRegistry(() => 1_900_000_000_000) } : {});
  const account = await registerAccount(app);
  const mobile = await loginDevice(app, account, "mobile");
  const a = await connect(app, account.agent.token);
  const m = await connect(app, mobile.token);
  await m.nextBinary();
  await a.nextBinary();
  return { app, account, agent: account.agent, mobile, a, m };
}

describe("per-connection frame rate limit", () => {
  it("lets a burst of 400 frames through (real clock)", async () => {
    const { agent, a, m } = await hubWithTwoDevices(false);
    for (let i = 0; i < 400; i++) m.send(encodeData(agent.deviceId, CH, Uint8Array.of(4, i & 0xff)));
    for (let i = 0; i < 400; i++) await a.nextBinary();
    await m.expectSilence(100);
  });

  it("sends ERROR rate_limited, then closes with 4003 and announces offline", async () => {
    const { agent, mobile, a, m } = await hubWithTwoDevices();
    for (let i = 0; i < 1000; i++) m.send(encodeData(agent.deviceId, CH, Uint8Array.of(4)));
    expect(hex(await m.nextBinary())).toBe(hex(encodeError(RelayErrorCode.rateLimited)));
    expect(await m.closed).toEqual({ code: 4003, reason: "rate_limited" });

    let delivered = 0;
    for (;;) {
      const frame = await a.nextBinary();
      if (frame[1] === 0x02) {
        expect(hex(frame)).toBe(hex(encodePresence(mobile.deviceId, false)));
        break;
      }
      delivered++;
    }
    // With the clock frozen, exactly the fresh bucket's capacity is delivered.
    expect(delivered).toBe(FRAMES_PER_SECOND);
  });

  it("counts text pings too: a ping flood gets ERROR rate_limited and 4003 like any other frame (R1)", async () => {
    const { mobile, a, m } = await hubWithTwoDevices();
    for (let i = 0; i < 2 * FRAMES_PER_SECOND; i++) m.send("ping");
    let pongs = 0;
    let reply = await m.next();
    while (reply === "pong") {
      pongs++;
      reply = await m.next();
    }
    expect(hex(reply as Uint8Array)).toBe(hex(encodeError(RelayErrorCode.rateLimited)));
    expect(pongs).toBeLessThanOrEqual(FRAMES_PER_SECOND); // never one past the budget
    expect(await m.closed).toEqual({ code: 4003, reason: "rate_limited" });
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, false)));
  });
});

describe("budget survives reconnects", () => {
  it("keeps the exhausted budget across a reconnect instead of granting a fresh one", async () => {
    const { app, agent, mobile, a, m } = await hubWithTwoDevices();

    for (let i = 0; i < 450; i++) m.send(encodeData(agent.deviceId, CH, Uint8Array.of(4)));
    for (let i = 0; i < 450; i++) await a.nextBinary();

    const m2 = await connect(app, mobile.token);
    expect((await m.closed).code).toBe(4001);
    expect(hex(await m2.nextBinary())).toBe(hex(encodePresence(agent.deviceId, true)));

    // The clock never advanced, so exactly 50 tokens remain.
    for (let i = 0; i < 50; i++) m2.send(encodeData(agent.deviceId, CH, Uint8Array.of(4)));
    for (let i = 0; i < 50; i++) await a.nextBinary();
    m2.send(encodeData(agent.deviceId, CH, Uint8Array.of(4, 1)));
    expect(hex(await m2.nextBinary())).toBe(hex(encodeError(RelayErrorCode.rateLimited)));
    expect(await m2.closed).toEqual({ code: 4003, reason: "rate_limited" });
  });

  it("keeps it even when every socket of the account closed and the hub was dropped in between", async () => {
    const hubs = newHubRegistry(() => 1_900_000_000_000);
    const app = makeApp({ hubs });
    const account = await registerAccount(app);
    const m = await connect(app, account.agent.token);
    for (let i = 0; i < 499; i++) m.send(encodeData(crypto.randomUUID(), CH, Uint8Array.of(4)));
    for (let i = 0; i < 499; i++) await m.nextBinary(); // peer_offline replies
    m.close();
    await m.closed;
    await hubs.whenEmpty();
    expect(hubs.size).toBe(0);

    const again = await connect(app, account.agent.token);
    again.send(encodeData(crypto.randomUUID(), CH, Uint8Array.of(4))); // the 500th frame: allowed
    expect((await again.nextBinary())[3]).toBe(RelayErrorCode.peerOffline);
    again.send(encodeData(crypto.randomUUID(), CH, Uint8Array.of(4))); // the 501st: over budget
    expect(hex(await again.nextBinary())).toBe(hex(encodeError(RelayErrorCode.rateLimited)));
    expect(await again.closed).toEqual({ code: 4003, reason: "rate_limited" });
  });

  it("keeps routing, presence, replacement and heartbeat working after the hub is dropped and re-created", async () => {
    const hubs = newHubRegistry();
    const app = makeApp({ hubs });
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    for (const socket of [await connect(app, account.agent.token), await connect(app, mobile.token)]) {
      socket.close();
      await socket.closed;
    }
    await hubs.whenEmpty();
    expect(hubs.size).toBe(0);

    const a = await connect(app, account.agent.token);
    const m = await connect(app, mobile.token);
    expect(hex(await m.nextBinary())).toBe(hex(encodePresence(account.agent.deviceId, true)));
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    m.send("ping");
    expect(await m.next()).toBe("pong");
    m.send(encodeData(account.agent.deviceId, CH, Uint8Array.of(4, 2)));
    expect(hex(await a.nextBinary())).toBe(hex(encodeData(mobile.deviceId, CH, Uint8Array.of(4, 2))));
    const m2 = await connect(app, mobile.token);
    expect((await m.closed).code).toBe(4001);
    expect(hex(await m2.nextBinary())).toBe(hex(encodePresence(account.agent.deviceId, true)));
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
  });
});

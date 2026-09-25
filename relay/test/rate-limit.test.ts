import { evictDurableObject } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { afterEach, describe, expect, it, vi } from "vitest";
import { FRAMES_PER_SECOND, TokenBucket } from "../src/hub/token-bucket";
import { encodeData, encodeError, encodePresence, RelayErrorCode } from "../src/protocol/frames";
import { connect, hex, loginDevice, makeApp, registerAccount } from "./helpers";

const CH = Uint8Array.from([1, 1, 2, 3, 5, 8, 13, 21]);

afterEach(() => {
  vi.useRealTimers();
});

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

async function hubWithTwoDevices() {
  const app = makeApp();
  const account = await registerAccount(app);
  const mobile = await loginDevice(app, account, "mobile");
  const a = await connect(app, account.agent.token);
  const m = await connect(app, mobile.token);
  await m.nextBinary();
  await a.nextBinary();
  const stub = env.USER_HUB.get(env.USER_HUB.idFromName(account.agent.userId));
  return { app, account, agent: account.agent, mobile, a, m, stub };
}

describe("per-connection frame rate limit", () => {
  it("lets a burst of 400 frames through", async () => {
    const { agent, a, m } = await hubWithTwoDevices();
    for (let i = 0; i < 400; i++) m.send(encodeData(agent.deviceId, CH, Uint8Array.of(4, i & 0xff)));
    for (let i = 0; i < 400; i++) await a.nextBinary();
    await m.expectSilence(100);
  });

  it("sends ERROR rate_limited, then closes with 4003 and announces offline", async () => {
    // Freeze Date.now() (shared with the Durable Object — see task-7-report.md) so the token math
    // below is exact regardless of how long these 1000 sends actually take on the host: a naive
    // real-clock version can, under load, let enough of the bucket refill mid-flood that fewer than
    // `FRAMES_PER_SECOND` frames get delivered before the limiter trips, or (rarely) enough to blow
    // past the 1000-message budget entirely — this is the flaky test flagged in task-8-report.md.
    vi.useFakeTimers();
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
    // With the clock frozen, exactly the fresh bucket's capacity is delivered before the 501st send
    // trips the limiter — no more, no less.
    expect(delivered).toBe(FRAMES_PER_SECOND);
  });
});

describe("budget survives reconnects", () => {
  it("keeps the exhausted budget across a reconnect instead of granting a fresh one", async () => {
    // Freeze Date.now() (shared with the Durable Object — see task-7-report.md) so the token math
    // below is exact regardless of how long these round trips actually take on the host: a naive
    // real-clock version that waits for 450 individual responses can, under load, let enough of the
    // bucket refill before the reconnect that the "still limited" flood below never trips it.
    vi.useFakeTimers();
    const { app, agent, mobile, a, m } = await hubWithTwoDevices();

    // Spend 450 of the 500 tokens on the first connection.
    for (let i = 0; i < 450; i++) m.send(encodeData(agent.deviceId, CH, Uint8Array.of(4)));
    for (let i = 0; i < 450; i++) await a.nextBinary();

    // Reconnect the same device (same token => same device id): the hub replaces the old socket.
    const m2 = await connect(app, mobile.token);
    expect((await m.closed).code).toBe(4001);
    expect(hex(await m2.nextBinary())).toBe(hex(encodePresence(agent.deviceId, true)));

    // The clock never advanced, so exactly 50 tokens remain. A fresh (buggy) reset would allow
    // 500 more; the persisted bucket allows exactly 50 more before tripping.
    for (let i = 0; i < 50; i++) m2.send(encodeData(agent.deviceId, CH, Uint8Array.of(4)));
    for (let i = 0; i < 50; i++) await a.nextBinary();
    m2.send(encodeData(agent.deviceId, CH, Uint8Array.of(4, 1)));
    expect(hex(await m2.nextBinary())).toBe(hex(encodeError(RelayErrorCode.rateLimited)));
    expect(await m2.closed).toEqual({ code: 4003, reason: "rate_limited" });
  });
});

describe("hibernation", () => {
  it("keeps routing, presence, replacement, heartbeat and rate limiting working after eviction", async () => {
    const { app, agent, mobile, a, m, stub } = await hubWithTwoDevices();
    await evictDurableObject(stub); // sockets are hibernated, in-memory state (token buckets) is dropped

    m.send("ping");
    expect(await m.next()).toBe("pong");
    m.send(encodeData(agent.deviceId, CH, Uint8Array.of(4, 2)));
    expect(hex(await a.nextBinary())).toBe(hex(encodeData(mobile.deviceId, CH, Uint8Array.of(4, 2))));

    const m2 = await connect(app, mobile.token);
    expect((await m.closed).code).toBe(4001);
    expect(hex(await m2.nextBinary())).toBe(hex(encodePresence(agent.deviceId, true)));
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));

    await evictDurableObject(stub);
    // Freeze the clock (same trick as "budget survives reconnects" above — see task-7-report.md for
    // why this works: the Durable Object's Date.now() is the same faked clock as the test's) so the
    // rebuilt post-hibernation bucket is exercised exactly, regardless of host speed. A real-clock
    // version that waits for 400 individual responses before flooding can, under load, let enough of
    // the fresh bucket refill that the flood never trips the limiter (hanging until timeout); one big
    // enough to out-race any plausible refill instead risks blowing the test's own wall-clock budget
    // while it processes thousands of messages under that same load.
    vi.useFakeTimers();
    for (let i = 0; i < 400; i++) m2.send(encodeData(agent.deviceId, CH, Uint8Array.of(4)));
    for (let i = 0; i < 400; i++) await a.nextBinary();
    // Exactly 100 tokens remain of the fresh 500-token capacity (clock frozen, so no refill since
    // hibernation); spend them, then one more must trip the limiter.
    for (let i = 0; i < 100; i++) m2.send(encodeData(agent.deviceId, CH, Uint8Array.of(4)));
    for (let i = 0; i < 100; i++) await a.nextBinary();
    m2.send(encodeData(agent.deviceId, CH, Uint8Array.of(4, 9)));
    expect(hex(await m2.nextBinary())).toBe(hex(encodeError(RelayErrorCode.rateLimited)));
    expect(await m2.closed).toEqual({ code: 4003, reason: "rate_limited" });
  });
});

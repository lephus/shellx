import { evictDurableObject } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { FRAMES_PER_SECOND, TokenBucket } from "../src/hub/token-bucket";
import { encodeData, encodeError, encodePresence, RelayErrorCode } from "../src/protocol/frames";
import { connect, hex, loginDevice, makeApp, registerAccount } from "./helpers";

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
    expect(delivered).toBeGreaterThanOrEqual(FRAMES_PER_SECOND);
    expect(delivered).toBeLessThan(1000);
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
    for (let i = 0; i < 400; i++) m2.send(encodeData(agent.deviceId, CH, Uint8Array.of(4)));
    for (let i = 0; i < 400; i++) await a.nextBinary();
    for (let i = 0; i < 1000; i++) m2.send(encodeData(agent.deviceId, CH, Uint8Array.of(4)));
    expect((await m2.closed).code).toBe(4003);
  });
});

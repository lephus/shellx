import { describe, expect, it } from "vitest";
import { clientIp } from "../src/auth/client-ip.js";
import {
  createRateLimiters, LOGIN_PER_EMAIL, LOGIN_PER_IP, RATE_WINDOW_MS, REGISTER_PER_IP, SlidingWindowLimiter, UPGRADES_PER_IP,
} from "../src/auth/rate-limit.js";

function clock(start = 1_800_000_000_000) {
  let now = start;
  return { now: () => now, advance: (ms: number) => (now += ms) };
}

async function allowed(limiter: SlidingWindowLimiter, key: string, times: number): Promise<boolean[]> {
  const results: boolean[] = [];
  for (let i = 0; i < times; i++) results.push(await limiter.limit(key));
  return results;
}

describe("SlidingWindowLimiter", () => {
  it("allows `limit` calls per key inside the window, then refuses", async () => {
    const t = clock();
    const limiter = new SlidingWindowLimiter({ limit: 3, now: t.now });
    expect(await allowed(limiter, "203.0.113.7", 4)).toEqual([true, true, true, false]);
    expect(await limiter.limit("198.51.100.1")).toBe(true); // other keys are independent
  });

  it("slides: a slot frees up exactly one window after the call that used it", async () => {
    const t = clock();
    const limiter = new SlidingWindowLimiter({ limit: 2, now: t.now });
    await limiter.limit("k"); // t = 0
    t.advance(30_000);
    await limiter.limit("k"); // t = 30 s
    expect(await limiter.limit("k")).toBe(false);
    t.advance(29_999); // 59.999 s: the first call is still inside the window
    expect(await limiter.limit("k")).toBe(false);
    t.advance(1); // 60 s: the first call has left the window
    expect(await limiter.limit("k")).toBe(true);
    expect(await limiter.limit("k")).toBe(false);
  });

  it("does not count refused calls, so hammering does not extend the lockout", async () => {
    const t = clock();
    const limiter = new SlidingWindowLimiter({ limit: 1, now: t.now });
    expect(await limiter.limit("k")).toBe(true);
    for (let i = 0; i < 50; i++) {
      t.advance(1000);
      expect(await limiter.limit("k")).toBe(false);
    }
    t.advance(RATE_WINDOW_MS - 50_000);
    expect(await limiter.limit("k")).toBe(true);
  });

  it("sweeps keys whose calls all left the window, at most once per window", async () => {
    const t = clock();
    const limiter = new SlidingWindowLimiter({ limit: 5, now: t.now });
    for (let i = 0; i < 100; i++) await limiter.limit(`attacker-${i}@example.com`);
    expect(limiter.size).toBe(100);
    t.advance(RATE_WINDOW_MS);
    await limiter.limit("next@example.com"); // triggers the sweep
    expect(limiter.size).toBe(1);
  });
});

describe("createRateLimiters (production wiring)", () => {
  it("enforces login 10/IP, login 5/email and register 3/IP", async () => {
    expect([LOGIN_PER_IP, LOGIN_PER_EMAIL, REGISTER_PER_IP, RATE_WINDOW_MS]).toEqual([10, 5, 3, 60_000]);
    const t = clock();
    const limiters = createRateLimiters({ rateLimitsEnabled: true }, t.now);
    const count = async (limiter: { limit(k: string): Promise<boolean> }) => {
      let n = 0;
      while (n < 100 && (await limiter.limit("same-key"))) n++;
      return n;
    };
    expect(await count(limiters.loginIp)).toBe(10);
    expect(await count(limiters.loginEmail)).toBe(5);
    expect(await count(limiters.registerIp)).toBe(3);
  });

  it("limits WebSocket upgrades to 60 per IP per 60 s (R2)", async () => {
    expect(UPGRADES_PER_IP).toBe(60);
    const t = clock();
    const limiters = createRateLimiters({ rateLimitsEnabled: true }, t.now);
    for (let i = 0; i < 60; i++) expect(await limiters.upgradeIp.limit("198.51.100.1")).toBe(true);
    expect(await limiters.upgradeIp.limit("198.51.100.1")).toBe(false);
    expect(await limiters.upgradeIp.limit("198.51.100.2")).toBe(true); // per IP
    t.advance(RATE_WINDOW_MS);
    expect(await limiters.upgradeIp.limit("198.51.100.1")).toBe(true); // the window slid
  });

  it("RATE_LIMITS_ENABLED=false turns every limiter off", async () => {
    const limiters = createRateLimiters({ rateLimitsEnabled: false });
    for (let i = 0; i < 20; i++) {
      expect(await limiters.loginIp.limit("k")).toBe(true);
      expect(await limiters.loginEmail.limit("k")).toBe(true);
      expect(await limiters.registerIp.limit("k")).toBe(true);
    }
    for (let i = 0; i < 100; i++) expect(await limiters.upgradeIp.limit("k")).toBe(true);
  });
});

describe("clientIp", () => {
  it("uses X-Real-IP when the TCP peer is nginx-proxy on a private or loopback address", () => {
    for (const peer of ["172.18.0.3", "::ffff:172.18.0.3", "10.1.2.3", "192.168.1.9", "127.0.0.1", "::1", "fd00::5"]) {
      expect(clientIp("203.0.113.7", peer)).toBe("203.0.113.7");
    }
    expect(clientIp(" 2001:db8::1 ", "172.18.0.3")).toBe("2001:db8:0:0::/64"); // IPv6: keyed by its /64
  });

  it("ignores X-Real-IP from a public peer: a client that bypasses the proxy cannot pick its key", () => {
    expect(clientIp("198.51.100.99", "203.0.113.50")).toBe("203.0.113.50");
    expect(clientIp("198.51.100.99", "2001:db8::77")).toBe("2001:db8:0:0::/64");
  });

  it("falls back to the peer address when X-Real-IP is missing or not an IP address", () => {
    expect(clientIp(undefined, "127.0.0.1")).toBe("127.0.0.1");
    expect(clientIp("", "::ffff:127.0.0.1")).toBe("127.0.0.1");
    expect(clientIp("not-an-ip", "172.18.0.3")).toBe("172.18.0.3");
    expect(clientIp("203.0.113.7, 10.0.0.1", "172.18.0.3")).toBe("172.18.0.3");
    expect(clientIp(undefined, undefined)).toBe("unknown");
  });

  it("keys IPv6 clients by their /64, since one subscriber usually holds a whole /64 (M12)", () => {
    const key = (address: string) => clientIp(address, "172.18.0.3");
    // Every address of one /64, however it is written, shares one key...
    const sameNetwork = ["2001:db8:1:2::1", "2001:db8:1:2:aaaa:bbbb:cccc:dddd", "2001:DB8:1:2::FFFF", "2001:0db8:0001:0002::9"];
    expect(new Set(sameNetwork.map(key))).toEqual(new Set(["2001:db8:1:2::/64"]));
    // ...and the neighbouring /64s do not.
    expect(key("2001:db8:1:3::1")).toBe("2001:db8:1:3::/64");
    expect(key("2001:db8:1::1")).toBe("2001:db8:1:0::/64");
    expect(key("::1")).toBe("0:0:0:0::/64");
    expect(key("fe80::1%eth0")).toBe("fe80:0:0:0::/64");
    expect(key("64:ff9b::198.51.100.7")).toBe("64:ff9b:0:0::/64");
    // The same applies to a public IPv6 peer that connected directly.
    expect(clientIp(undefined, "2001:db8:1:2::7")).toBe("2001:db8:1:2::/64");
  });

  it("leaves IPv4 and IPv4-mapped IPv6 addresses as plain IPv4 keys", () => {
    expect(clientIp("203.0.113.7", "172.18.0.3")).toBe("203.0.113.7");
    expect(clientIp("::ffff:203.0.113.7", "172.18.0.3")).toBe("203.0.113.7");
    expect(clientIp(undefined, "::ffff:198.51.100.4")).toBe("198.51.100.4");
  });
});

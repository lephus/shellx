import type { Config } from "../config.js";

/** Returns true when the call is allowed, false when the key is over its limit. */
export interface RateLimiter {
  limit(key: string): Promise<boolean>;
}

export interface RateLimiters {
  loginIp: RateLimiter;
  loginEmail: RateLimiter;
  registerIp: RateLimiter;
  /** Every WebSocket upgrade attempt on /v1/ws, counted before its token is checked. */
  upgradeIp: RateLimiter;
}

/** Spec §5.2: 60-second window; login 10/IP and 5/email, register 3/IP. */
export const RATE_WINDOW_MS = 60_000;
export const LOGIN_PER_IP = 10;
export const LOGIN_PER_EMAIL = 5;
export const REGISTER_PER_IP = 3;
/**
 * WebSocket upgrades per IP per window (residual R2, defence in depth): far above what reconnecting
 * clients with backoff need, low enough that one address cannot churn upgrades against the relay.
 */
export const UPGRADES_PER_IP = 60;

export interface SlidingWindowOptions {
  /** Allowed calls per key within any window of `windowMs`. */
  limit: number;
  windowMs?: number;
  now?: () => number;
}

/**
 * In-memory sliding-window limiter (replaces the Workers rate limiting binding). Each key keeps the
 * timestamps of its allowed calls inside the window (at most `limit` of them); a refused call is
 * not recorded, so hammering does not extend a lockout. Keys whose newest call left the window are
 * swept at most once per window, on the next call, so memory stays bounded by recent traffic.
 * Keys are IP addresses or e-mail addresses and are never logged.
 */
export class SlidingWindowLimiter implements RateLimiter {
  private readonly hits = new Map<string, number[]>();
  private readonly windowMs: number;
  private readonly now: () => number;
  private lastSweep: number;

  constructor(private readonly options: SlidingWindowOptions) {
    this.windowMs = options.windowMs ?? RATE_WINDOW_MS;
    this.now = options.now ?? Date.now;
    this.lastSweep = this.now();
  }

  /** Number of keys currently tracked (for tests and memory checks). */
  get size(): number {
    return this.hits.size;
  }

  async limit(key: string): Promise<boolean> {
    const now = this.now();
    if (now - this.lastSweep >= this.windowMs) this.sweep(now);
    const since = now - this.windowMs;
    const recent = (this.hits.get(key) ?? []).filter((t) => t > since);
    if (recent.length >= this.options.limit) {
      this.hits.set(key, recent);
      return false;
    }
    recent.push(now);
    this.hits.set(key, recent);
    return true;
  }

  /** Drops every key with no call inside the window. */
  sweep(now: number = this.now()): void {
    this.lastSweep = now;
    const since = now - this.windowMs;
    for (const [key, times] of this.hits) {
      if (times.length === 0 || times[times.length - 1]! <= since) this.hits.delete(key);
    }
  }
}

const allowAll: RateLimiter = { limit: async () => true };

/** Production wiring: one limiter set per process. RATE_LIMITS_ENABLED=false turns all four off. */
export function createRateLimiters(config: Pick<Config, "rateLimitsEnabled">, now: () => number = Date.now): RateLimiters {
  if (!config.rateLimitsEnabled) return { loginIp: allowAll, loginEmail: allowAll, registerIp: allowAll, upgradeIp: allowAll };
  return {
    loginIp: new SlidingWindowLimiter({ limit: LOGIN_PER_IP, now }),
    loginEmail: new SlidingWindowLimiter({ limit: LOGIN_PER_EMAIL, now }),
    registerIp: new SlidingWindowLimiter({ limit: REGISTER_PER_IP, now }),
    upgradeIp: new SlidingWindowLimiter({ limit: UPGRADES_PER_IP, now }),
  };
}

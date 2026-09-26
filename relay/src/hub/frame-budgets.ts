import { FRAMES_PER_SECOND, TokenBucket } from "./token-bucket.js";

/** How often idle buckets are dropped, and after how long a bucket counts as idle. */
const SWEEP_INTERVAL_MS = 60_000;
const IDLE_MS = 1000;

/**
 * The 500 frames/s budget of every device (spec §6.2), kept by the registry rather than by a hub so
 * that neither a reconnect nor the hub being dropped and re-created refills it early. A bucket
 * untouched for one second has refilled to its full capacity, exactly like a new one, so dropping
 * it in `sweep` changes nothing observable while keeping memory bounded.
 */
export class FrameBudgets {
  private readonly buckets = new Map<string, { bucket: TokenBucket; lastUsed: number }>();
  private lastSweep: number;

  constructor(private readonly now: () => number) {
    this.lastSweep = now();
  }

  get size(): number {
    return this.buckets.size;
  }

  /** Spends one frame of `deviceId`'s budget; false when it is exhausted. */
  take(deviceId: string): boolean {
    const now = this.now();
    if (now - this.lastSweep >= SWEEP_INTERVAL_MS) this.sweep(now);
    let entry = this.buckets.get(deviceId);
    if (entry === undefined) {
      entry = { bucket: new TokenBucket(FRAMES_PER_SECOND, FRAMES_PER_SECOND, now), lastUsed: now };
      this.buckets.set(deviceId, entry);
    }
    entry.lastUsed = now;
    return entry.bucket.take(now);
  }

  sweep(now: number = this.now()): void {
    this.lastSweep = now;
    for (const [deviceId, entry] of this.buckets) {
      if (now - entry.lastUsed >= IDLE_MS) this.buckets.delete(deviceId);
    }
  }
}

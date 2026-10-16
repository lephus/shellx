/** Classic token bucket: `capacity` burst, refilled continuously at `refillPerSecond`. */
export class TokenBucket {
  private tokens: number;
  private updatedAt: number;

  constructor(
    private readonly capacity: number,
    private readonly refillPerSecond: number,
    now: number,
  ) {
    this.tokens = capacity;
    this.updatedAt = now;
  }

  take(now: number): boolean {
    const elapsed = Math.max(0, now - this.updatedAt);
    this.tokens = Math.min(this.capacity, this.tokens + (elapsed * this.refillPerSecond) / 1000);
    this.updatedAt = now;
    if (this.tokens < 1) return false;
    this.tokens -= 1;
    return true;
  }
}

/** Spec §6.2: at most 500 frames per second per connection. */
export const FRAMES_PER_SECOND = 500;

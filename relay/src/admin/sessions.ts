import { createHash, randomBytes } from "node:crypto";

/** A signed-in admin stays signed in this long (the cookie's Max-Age is the same). */
export const ADMIN_SESSION_TTL_MS = 12 * 60 * 60 * 1000;
/** Most sessions kept at once; signing in beyond it ends the oldest. */
export const MAX_ADMIN_SESSIONS = 16;

/** 32 random bytes, base64url without padding. */
const SESSION_ID_RE = /^[A-Za-z0-9_-]{43}$/;

function digest(id: string): string {
  return createHash("sha256").update(id).digest("hex");
}

/**
 * Admin sessions, in memory only: a relay restart signs every admin out, which is fine for one
 * person's dashboard and leaves nothing on disk. Only the SHA-256 of each session id is kept, so a
 * heap snapshot or a debugger never shows a cookie value that could be replayed. Expiry is absolute
 * (12 h after sign-in), and the number of live sessions is capped.
 */
export class AdminSessions {
  /** Digest of each session id → its expiry (unix ms); Map order is creation order. */
  private readonly sessions = new Map<string, number>();

  constructor(private readonly now: () => number) {}

  /** Starts a session and returns its id (the cookie value). */
  create(): string {
    this.sweep();
    while (this.sessions.size >= MAX_ADMIN_SESSIONS) this.sessions.delete(this.sessions.keys().next().value!);
    const id = randomBytes(32).toString("base64url");
    this.sessions.set(digest(id), this.now() + ADMIN_SESSION_TTL_MS);
    return id;
  }

  /** True while `id` names a session that has not expired or ended. */
  isValid(id: string | undefined): boolean {
    if (id === undefined || !SESSION_ID_RE.test(id)) return false;
    const key = digest(id);
    const expiresAt = this.sessions.get(key);
    if (expiresAt === undefined) return false;
    if (this.now() >= expiresAt) {
      this.sessions.delete(key);
      return false;
    }
    return true;
  }

  /** Ends the session `id` (sign-out); a no-op for an unknown id. */
  end(id: string | undefined): void {
    if (id !== undefined && SESSION_ID_RE.test(id)) this.sessions.delete(digest(id));
  }

  /** Sessions held right now, expired ones not yet swept included (tests). */
  get size(): number {
    return this.sessions.size;
  }

  private sweep(): void {
    const now = this.now();
    for (const [key, expiresAt] of this.sessions) if (now >= expiresAt) this.sessions.delete(key);
  }
}

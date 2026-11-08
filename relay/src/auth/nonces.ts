import type { Db } from "../db/db.js";
import { Errors } from "../http/errors.js";
import { generateToken, hashToken } from "./tokens.js";

export const NONCE_TTL_MS = 600_000;
export const MAX_LIVE_NONCES = 50_000;

const NONCE_RE = /^[A-Za-z0-9_-]{43}$/;

/** A one-time sign-in nonce (S1 §6.2). Only its SHA-256 is stored; 429 while 50 000 are live. */
export async function issueNonce(db: Db, nowMs: number): Promise<string> {
  const nonce = generateToken();
  const hash = await hashToken(nonce);
  // Synchronous from here on: the cleanup, the cap check and the insert are one step.
  db.run("DELETE FROM auth_nonces WHERE expires_at <= ?", nowMs);
  const live = db.get<{ n: number }>("SELECT COUNT(*) AS n FROM auth_nonces")!.n;
  if (live >= MAX_LIVE_NONCES) throw Errors.rateLimited();
  db.run("INSERT INTO auth_nonces (nonce_hash, expires_at) VALUES (?, ?)", hash, nowMs + NONCE_TTL_MS);
  return nonce;
}

/** True exactly once for a live nonce this relay issued; false for anything else. */
export async function consumeNonce(db: Db, nonce: unknown, nowMs: number): Promise<boolean> {
  if (typeof nonce !== "string" || !NONCE_RE.test(nonce)) return false;
  const hash = await hashToken(nonce);
  return db.run("DELETE FROM auth_nonces WHERE nonce_hash = ? AND expires_at > ?", hash, nowMs).changes === 1;
}

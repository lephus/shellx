import { randomInt, timingSafeEqual } from "node:crypto";
import type { Db } from "../db/db.js";
import { generateToken, hashToken } from "./tokens.js";

/**
 * Email sign-in challenges (spec 2026-11-10 §4 and §5): one row of `email_codes` per pending code. Neither
 * the challenge id nor the code is stored, only SHA-256 of each; a row goes when the code is used, expired,
 * guessed wrong five times, replaced by a newer code for the same address, or when its mail could not be
 * sent. Nothing in this file logs: an address, a code and a challenge id must never reach a log line.
 */
export const EMAIL_CODE_TTL_MS = 600_000;
/** Advice for the client's Resend button (`resend_in`); the relay enforces only its rate limiters. */
export const EMAIL_CODE_RESEND_SEC = 60;
export const EMAIL_CODE_MAX_ATTEMPTS = 5;
export const MAX_LIVE_EMAIL_CODES = 50_000;

const CHALLENGE_ID_RE = /^[A-Za-z0-9_-]{43}$/;

/** Six digits, zero-padded, from the CSPRNG (`randomInt` is unbiased). */
export function generateEmailCode(): string {
  return String(randomInt(0, 1_000_000)).padStart(6, "0");
}

export interface IssuedEmailCode {
  /** The row's UUID: the Idempotency-Key of the mail, and the handle to discard the challenge. */
  id: string;
  /** 32 random bytes, base64url: handed to the client, never stored. */
  challengeId: string;
}

/**
 * Stores a new challenge for `email` (already normalized) and `code`, valid for EMAIL_CODE_TTL_MS. In one
 * transaction: expired rows go, then the cap is checked (null while MAX_LIVE_EMAIL_CODES are live, and
 * nothing else changes), then the address's older challenge goes, so only the newest code of an address
 * is ever valid.
 */
export async function issueEmailCode(db: Db, email: string, code: string, nowMs: number): Promise<IssuedEmailCode | null> {
  const challengeId = generateToken();
  const challengeHash = await hashToken(challengeId);
  const codeHash = await hashToken(`${challengeId}:${code}`);
  const id = crypto.randomUUID();
  return db.transaction((): IssuedEmailCode | null => {
    db.run("DELETE FROM email_codes WHERE expires_at <= ?", nowMs);
    const live = db.get<{ n: number }>("SELECT COUNT(*) AS n FROM email_codes")!.n;
    if (live >= MAX_LIVE_EMAIL_CODES) return null;
    db.run("DELETE FROM email_codes WHERE email = ?", email);
    db.run(
      "INSERT INTO email_codes (id, challenge_hash, code_hash, email, attempts, created_at, expires_at) VALUES (?, ?, ?, ?, 0, ?, ?)",
      id, challengeHash, codeHash, email, nowMs, nowMs + EMAIL_CODE_TTL_MS,
    );
    return { id, challengeId };
  });
}

/** Removes a challenge whose mail was not sent. */
export function discardEmailCode(db: Db, id: string): void {
  db.run("DELETE FROM email_codes WHERE id = ?", id);
}

export type RedeemedEmailCode = { ok: true; email: string } | { ok: false; reason: "invalid_code" | "code_expired" };

/**
 * One guess at a challenge. `ok` exactly once, for the right six-digit string, while the challenge is live;
 * the row is gone afterwards. `invalid_code`: a wrong guess that left the challenge (guesses 1 to 4).
 * `code_expired`: no such challenge (unknown, malformed, used, replaced, at or after its expiry), or this
 * was the fifth wrong guess, which deletes it.
 *
 * The awaits come first; the transaction is synchronous, so concurrent calls run it one after another. Its
 * order is the security rule: the guess is counted before it is compared, the row is found by
 * `challenge_hash` alone (`code_hash` never appears in a WHERE), and the two SHA-256 digests are compared
 * with `timingSafeEqual`, once per guess, for right and wrong codes alike.
 */
export async function redeemEmailCode(db: Db, challengeId: unknown, code: unknown, nowMs: number): Promise<RedeemedEmailCode> {
  if (typeof challengeId !== "string" || !CHALLENGE_ID_RE.test(challengeId)) return { ok: false, reason: "code_expired" };
  const challengeHash = await hashToken(challengeId);
  // A code that is not a string hashes as the empty guess, which no six-digit code equals.
  const guessHash = new Uint8Array(await hashToken(`${challengeId}:${typeof code === "string" ? code : ""}`));
  return db.transaction((): RedeemedEmailCode => {
    db.run("DELETE FROM email_codes WHERE expires_at <= ?", nowMs);
    const row = db.get<{ id: string; code_hash: Uint8Array; email: string }>(
      "SELECT id, code_hash, email FROM email_codes WHERE challenge_hash = ?", challengeHash,
    );
    if (row === undefined) return { ok: false, reason: "code_expired" };
    const attempts = db.get<{ attempts: number }>("UPDATE email_codes SET attempts = attempts + 1 WHERE id = ? RETURNING attempts", row.id)!.attempts;
    const match = row.code_hash.length === guessHash.length && timingSafeEqual(row.code_hash, guessHash);
    if (match || attempts >= EMAIL_CODE_MAX_ATTEMPTS) db.run("DELETE FROM email_codes WHERE id = ?", row.id);
    if (match) return { ok: true, email: row.email };
    return { ok: false, reason: attempts >= EMAIL_CODE_MAX_ATTEMPTS ? "code_expired" : "invalid_code" };
  });
}

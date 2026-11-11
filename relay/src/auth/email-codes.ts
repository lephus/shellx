import { createHmac, randomBytes, randomInt, timingSafeEqual } from "node:crypto";
import type { Db } from "../db/db.js";
import { generateToken } from "./tokens.js";

/**
 * Email sign-in challenges (spec 2026-11-10 §4 and §5): one row of `email_codes` per pending code. Neither
 * the challenge id nor the code is stored, only HMAC-SHA-256 of each under the relay's challenge key; a row
 * goes when the code is used, expired, guessed wrong five times, replaced by a newer code for the same
 * address, or when its mail could not be sent. Nothing in this file logs: an address, a code, a challenge
 * id and the key must never reach a log line.
 *
 * The key is why a copy of the database opens no account (review I1): `/code` hands the challenge id to
 * whoever asks, so with a plain hash the reader of a live row could try the 10^6 codes offline. The key is
 * 32 random bytes made when the relay starts (`newEmailCodeKey`, called once by `createApp`), held in memory
 * only: never stored, configured or logged. A restart makes a new key, so a challenge issued before it is
 * unknown afterwards (410 `code_expired`) and the user asks for a new code.
 */
export type EmailCodeKey = Uint8Array;

export function newEmailCodeKey(): EmailCodeKey {
  return randomBytes(32);
}

/**
 * HMAC-SHA-256 of `value` under `key`: 32 bytes. The two stored inputs, `challenge_id` and
 * `challenge_id:code`, cannot collide, since a challenge id is base64url and has no colon.
 */
function keyedHash(key: EmailCodeKey, value: string): Buffer {
  return createHmac("sha256", key).update(value, "utf8").digest();
}

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
 * is ever valid. Both hashes are taken under `key`.
 */
export async function issueEmailCode(db: Db, email: string, code: string, nowMs: number, key: EmailCodeKey): Promise<IssuedEmailCode | null> {
  const challengeId = generateToken();
  const challengeHash = keyedHash(key, challengeId);
  const codeHash = keyedHash(key, `${challengeId}:${code}`);
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
 * `code_expired`: no such challenge (unknown, malformed, used, replaced, at or after its expiry, or issued
 * under another key, that is before the relay's last restart; none of these counts a guess), or this was
 * the fifth wrong guess, which deletes it.
 *
 * The hashing and the transaction are synchronous, so concurrent calls run one after another. The
 * transaction's order is the security rule: the guess is counted before it is compared, the row is found by
 * `challenge_hash` alone (`code_hash` never appears in a WHERE), and the two 32-byte HMACs are compared
 * with `timingSafeEqual`, once per guess, for right and wrong codes alike.
 */
export async function redeemEmailCode(db: Db, challengeId: unknown, code: unknown, nowMs: number, key: EmailCodeKey): Promise<RedeemedEmailCode> {
  if (typeof challengeId !== "string" || !CHALLENGE_ID_RE.test(challengeId)) return { ok: false, reason: "code_expired" };
  const challengeHash = keyedHash(key, challengeId);
  // A code that is not a string hashes as the empty guess, which no six-digit code equals.
  const guessHash = keyedHash(key, `${challengeId}:${typeof code === "string" ? code : ""}`);
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

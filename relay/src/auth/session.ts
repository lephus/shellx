import type { MiddlewareHandler } from "hono";
import type { AppEnv } from "../app.js";
import { Errors } from "../http/errors.js";
import type { DeviceKind } from "./device.js";
import { hashToken, parseBearer, TOKEN_IDLE_TTL_MS, TOKEN_TOUCH_INTERVAL_MS } from "./tokens.js";

export interface AuthContext {
  userId: string;
  deviceId: string;
  kind: DeviceKind;
}

interface TokenRow {
  device_id: string;
  last_used_at: number;
  user_id: string;
  kind: DeviceKind;
}

export function insertTokenStatement(db: D1Database, tokenHash: ArrayBuffer, deviceId: string, now: number) {
  return db
    .prepare("INSERT INTO tokens (token_hash, device_id, created_at, last_used_at) VALUES (?, ?, ?, ?)")
    .bind(tokenHash, deviceId, now, now);
}

/**
 * Inserts the token only while the user's password hash is still `verifiedHash` — the one the
 * login just verified against. A password change that commits in between (argon2 takes tens of
 * milliseconds) makes this insert nothing (`meta.changes === 0`), so no token is ever minted under
 * a password that is no longer valid (final review M1).
 */
export function insertTokenIfPasswordUnchangedStatement(
  db: D1Database, tokenHash: ArrayBuffer, deviceId: string, now: number, userId: string, verifiedHash: string,
) {
  return db
    .prepare(
      `INSERT INTO tokens (token_hash, device_id, created_at, last_used_at)
       SELECT ?, ?, ?, ? WHERE (SELECT password_hash FROM users WHERE id = ?) = ?`,
    )
    .bind(tokenHash, deviceId, now, now, userId, verifiedHash);
}

/**
 * Resolves a bearer token. Tokens idle for more than 90 days are deleted and rejected;
 * `last_used_at` is refreshed at most once per hour.
 */
export async function authenticate(db: D1Database, token: string | null, now: number): Promise<AuthContext | null> {
  if (token === null) return null;
  const tokenHash = await hashToken(token);
  const row = await db
    .prepare(
      `SELECT t.device_id, t.last_used_at, d.user_id, d.kind
         FROM tokens t JOIN devices d ON d.id = t.device_id
        WHERE t.token_hash = ?`,
    )
    .bind(tokenHash)
    .first<TokenRow>();
  if (row === null) return null;
  if (now - row.last_used_at > TOKEN_IDLE_TTL_MS) {
    await db.prepare("DELETE FROM tokens WHERE token_hash = ?").bind(tokenHash).run();
    return null;
  }
  if (now - row.last_used_at >= TOKEN_TOUCH_INTERVAL_MS) {
    await db.prepare("UPDATE tokens SET last_used_at = ? WHERE token_hash = ?").bind(now, tokenHash).run();
  }
  return { userId: row.user_id, deviceId: row.device_id, kind: row.kind };
}

export const requireAuth: MiddlewareHandler<AppEnv> = async (c, next) => {
  const auth = await authenticate(c.env.DB, parseBearer(c.req.header("Authorization")), c.get("now")());
  if (auth === null) throw Errors.unauthorized();
  c.set("auth", auth);
  await next();
};

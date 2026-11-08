import { Hono } from "hono";
import type { AppEnv } from "../app.js";
import { revokeAppleTokens } from "../auth/apple-rest.js";
import { REAUTH_MAX_AGE_SEC } from "../auth/id-token.js";
import { consumeNonce } from "../auth/nonces.js";
import { isOverlongPassword } from "../auth/password-policy.js";
import { requireAuth } from "../auth/session.js";
import { jsonBodyLimit } from "../http/body-limit.js";
import { Errors, readJsonObject } from "../http/errors.js";
import { logMeta } from "../log.js";

export const accountRoutes = new Hono<AppEnv>();

/**
 * DELETE /v1/account — any signed-in device (spec §5.2, App Store 5.1.1(v)). Confirmed by a fresh Google
 * or Apple ID token of one of the account's own sign-ins `{id_token, nonce}` (iat at most 300 s old), or,
 * only while PASSWORD_LOGIN is on and the account still has a password, by `{password}`. Deletes the user
 * (devices, tokens, identities and pairings go with it, ON DELETE CASCADE), asks Apple to revoke the stored
 * refresh tokens, then closes every device's socket with 4002. Confirmations share the 5/email/60 s budget.
 */
accountRoutes.delete("/", requireAuth, jsonBodyLimit, async (c) => {
  const auth = c.get("auth");
  const body = await readJsonObject(c.req.raw);
  const db = c.get("db");
  const user = db.get<{ email: string; password_hash: string | null }>("SELECT email, password_hash FROM users WHERE id = ?", auth.userId);
  if (user === undefined) throw Errors.unauthorized();
  if (!(await c.get("limiters").loginEmail.limit(user.email))) throw Errors.rateLimited();
  const denied = (error: () => Error): never => {
    logMeta("account_delete_denied", { device_id: auth.deviceId });
    throw error();
  };

  if (typeof body.id_token === "string") {
    const now = c.get("now")();
    const verified = await c.get("idTokens").verify(body.id_token, {
      providers: ["google", "apple", "test"], nonce: typeof body.nonce === "string" ? body.nonce : "", maxAgeSec: REAUTH_MAX_AGE_SEC, nowMs: now,
    });
    if (verified === null || !(await consumeNonce(db, body.nonce, now))) return denied(Errors.invalidCredentials);
    const owner = db.get<{ user_id: string }>("SELECT user_id FROM identities WHERE provider = ? AND subject = ?", verified.provider, verified.subject);
    if (owner?.user_id !== auth.userId) return denied(Errors.invalidCredentials);
  } else if (typeof body.password === "string" && c.get("config").passwordLogin && user.password_hash !== null) {
    // Over 128 code points can never match; refuse it before argon2 sees it (final review I2).
    if (isOverlongPassword(body.password) || !(await c.get("passwords").verify(body.password, user.password_hash))) {
      return denied(Errors.invalidCredentials);
    }
  } else {
    return denied(Errors.reauthRequired);
  }

  const appleRows = db.all<{ apple_client_id: string | null; apple_refresh_token: string | null }>(
    "SELECT apple_client_id, apple_refresh_token FROM identities WHERE user_id = ? AND provider = 'apple'", auth.userId,
  );
  db.run("DELETE FROM users WHERE id = ?", auth.userId);
  // Revocation never blocks the deletion; it logs what it could not do.
  await revokeAppleTokens(c.get("appleTokens"), appleRows);
  // The delete is irreversible: a hub failure from here on must not turn a successful account
  // deletion into a 500. closeAccount() closes every socket live in the hub *now* and purges the
  // tombstones; best-effort only, logging metadata (no email) on failure.
  try {
    await c.get("hubs").forUser(auth.userId).closeAccount();
  } catch {
    logMeta("account_close_failed", { device_id: auth.deviceId });
  }
  logMeta("account_deleted", { device_id: auth.deviceId });
  return c.body(null, 204);
});

import { Hono } from "hono";
import type { AppEnv } from "../app.js";
import { verifyPassword } from "../auth/password.js";
import { isOverlongPassword } from "../auth/password-policy.js";
import { requireAuth } from "../auth/session.js";
import { hubFor } from "../hub/user-hub.js";
import { jsonBodyLimit } from "../http/body-limit.js";
import { Errors, readJsonObject } from "../http/errors.js";
import { logMeta } from "../log.js";

export const accountRoutes = new Hono<AppEnv>();

/**
 * DELETE /v1/account {password} — any signed-in device (spec §5.2, App Store 5.1.1(v)).
 * Deletes the user; devices, tokens and pairings go with it (ON DELETE CASCADE), then every
 * device's socket is closed with 4002. Password attempts share the 5/email/60 s login budget.
 */
accountRoutes.delete("/", requireAuth, jsonBodyLimit, async (c) => {
  const auth = c.get("auth");
  const body = await readJsonObject(c.req.raw);
  const db = c.env.DB;
  const user = await db
    .prepare("SELECT email, password_hash FROM users WHERE id = ?")
    .bind(auth.userId)
    .first<{ email: string; password_hash: string }>();
  if (user === null) throw Errors.unauthorized();
  if (!(await c.get("limiters").loginEmail.limit(user.email))) throw Errors.rateLimited();
  const password = typeof body.password === "string" ? body.password : "";
  // Over 128 code points can never match; refuse it before argon2 sees it (final review I2).
  if (isOverlongPassword(password) || !(await verifyPassword(password, user.password_hash))) {
    logMeta("account_delete_denied", { device_id: auth.deviceId });
    throw Errors.invalidCredentials();
  }

  await db.prepare("DELETE FROM users WHERE id = ?").bind(auth.userId).run();
  // The delete is irreversible (fix round 1): a hub outage from here on must not turn a successful
  // account deletion into a 500. closeAccount() closes every socket *currently* live in the hub
  // (no stale device-id snapshot to go stale — see UserHub.closeAccount) and purges the durable
  // queue; best-effort only, logging metadata (no email) on failure.
  try {
    await hubFor(c.env, auth.userId).closeAccount();
  } catch {
    logMeta("account_close_failed", { device_id: auth.deviceId });
  }
  logMeta("account_deleted", { device_id: auth.deviceId });
  return c.body(null, 204);
});

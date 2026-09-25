import { Hono } from "hono";
import type { AppEnv } from "../app";
import { verifyPassword } from "../auth/password";
import { requireAuth } from "../auth/session";
import { hubFor } from "../hub/user-hub";
import { Errors, readJsonObject } from "../http/errors";
import { logMeta } from "../log";
import { CloseCode } from "../protocol/frames";

export const accountRoutes = new Hono<AppEnv>();

/**
 * DELETE /v1/account {password} — any signed-in device (spec §5.2, App Store 5.1.1(v)).
 * Deletes the user; devices, tokens and pairings go with it (ON DELETE CASCADE), then every
 * device's socket is closed with 4002. Password attempts share the 5/email/60 s login budget.
 */
accountRoutes.delete("/", requireAuth, async (c) => {
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
  if (!(await verifyPassword(password, user.password_hash))) {
    logMeta("account_delete_denied", { device_id: auth.deviceId });
    throw Errors.invalidCredentials();
  }

  const { results } = await db.prepare("SELECT id FROM devices WHERE user_id = ?").bind(auth.userId).all<{ id: string }>();
  await db.prepare("DELETE FROM users WHERE id = ?").bind(auth.userId).run();
  await hubFor(c.env, auth.userId).disconnect(results.map((r) => r.id), CloseCode.revoked);
  logMeta("account_deleted", { device_id: auth.deviceId });
  return c.body(null, 204);
});

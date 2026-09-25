import { Hono, type Context } from "hono";
import type { AppEnv } from "../app";
import { parseDevice, type DeviceInput } from "../auth/device";
import { checkEmail, normalizeEmail } from "../auth/email";
import { hashPassword, verifyPassword } from "../auth/password";
import { isAcceptablePassword, isOverlongPassword } from "../auth/password-policy";
import { insertTokenStatement, requireAuth } from "../auth/session";
import { generateToken, hashToken, parseBearer } from "../auth/tokens";
import { hubFor } from "../hub/user-hub";
import { jsonBodyLimit } from "../http/body-limit";
import { Errors, readJsonObject } from "../http/errors";
import { logMeta } from "../log";
import { CloseCode } from "../protocol/frames";

export const authRoutes = new Hono<AppEnv>();

function clientIp(c: Context<AppEnv>): string {
  return c.req.header("CF-Connecting-IP") ?? "unknown";
}

function upsertDeviceStatement(db: D1Database, userId: string, device: DeviceInput, now: number) {
  // Same public key in the same account → same device_id (spec §5.2); name/platform refreshed.
  return db
    .prepare(
      `INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT (user_id, public_key) DO UPDATE SET name = excluded.name, platform = excluded.platform
       RETURNING id`,
    )
    .bind(crypto.randomUUID(), userId, device.kind, device.name, device.platform, device.publicKey, now);
}

let dummyPhc: Promise<string> | undefined;
/** Verifying against a throwaway hash keeps unknown-email logins as slow as wrong-password ones. */
function dummyHash(): Promise<string> {
  dummyPhc ??= hashPassword("shellx-dummy-password");
  return dummyPhc;
}

authRoutes.post("/register", jsonBodyLimit, async (c) => {
  if (!(await c.get("limiters").registerIp.limit(clientIp(c)))) throw Errors.rateLimited();
  const body = await readJsonObject(c.req.raw);
  const email = checkEmail(body.email);
  if (!email.ok) throw email.code === "invalid_email" ? Errors.invalidEmail() : Errors.disposableEmail();
  if (!isAcceptablePassword(body.password)) throw Errors.weakPassword();
  const device = parseDevice(body.device);
  if (device === null) throw Errors.invalidDevice();

  const db = c.env.DB;
  if ((await db.prepare("SELECT 1 FROM users WHERE email = ?").bind(email.email).first()) !== null) {
    throw Errors.emailTaken();
  }
  const now = c.get("now")();
  const userId = crypto.randomUUID();
  const deviceId = crypto.randomUUID();
  const passwordHash = await hashPassword(body.password);
  const token = generateToken();
  try {
    await db.batch([
      db
        .prepare("INSERT INTO users (id, email, password_hash, password_changed_at, created_at) VALUES (?, ?, ?, ?, ?)")
        .bind(userId, email.email, passwordHash, now, now),
      db
        .prepare(
          "INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(deviceId, userId, device.kind, device.name, device.platform, device.publicKey, now),
      insertTokenStatement(db, await hashToken(token), deviceId, now),
    ]);
  } catch (err) {
    if (String(err).includes("UNIQUE constraint failed: users.email")) throw Errors.emailTaken();
    throw err;
  }
  logMeta("register", { device_id: deviceId });
  return c.json({ user_id: userId, device_id: deviceId, token }, 201);
});

authRoutes.post("/login", jsonBodyLimit, async (c) => {
  const limiters = c.get("limiters");
  if (!(await limiters.loginIp.limit(clientIp(c)))) throw Errors.rateLimited();
  const body = await readJsonObject(c.req.raw);
  const email = typeof body.email === "string" ? normalizeEmail(body.email) : "";
  if (!(await limiters.loginEmail.limit(email))) throw Errors.rateLimited();
  const device = parseDevice(body.device);
  if (device === null) throw Errors.invalidDevice();
  const password = typeof body.password === "string" ? body.password : "";
  // No account can have a password over 128 code points; refuse it before argon2 sees it (I2).
  if (isOverlongPassword(password)) {
    logMeta("login_failed");
    throw Errors.invalidCredentials();
  }

  const db = c.env.DB;
  const user = await db
    .prepare("SELECT id, password_hash FROM users WHERE email = ?")
    .bind(email)
    .first<{ id: string; password_hash: string }>();
  const passwordOk = await verifyPassword(password, user?.password_hash ?? (await dummyHash()));
  if (user === null || !passwordOk) {
    logMeta("login_failed");
    throw Errors.invalidCredentials();
  }

  const now = c.get("now")();
  const row = await upsertDeviceStatement(db, user.id, device, now).first<{ id: string }>();
  const deviceId = row!.id;
  const token = generateToken();
  // One live token per device: logging in again replaces the previous token.
  await db.batch([
    db.prepare("DELETE FROM tokens WHERE device_id = ?").bind(deviceId),
    insertTokenStatement(db, await hashToken(token), deviceId, now),
  ]);
  logMeta("login", { device_id: deviceId });
  return c.json({ user_id: user.id, device_id: deviceId, token }, 200);
});

/**
 * POST /v1/auth/logout — deletes this token; for an agent also every pairing it owns (spec §5.2).
 *
 * Notify-before-delete (task 9 ruling, same safe order as `DELETE /v1/pairings`): every pairing is
 * reported to the hub — which durably queues the event for the agent before doing anything live —
 * before any D1 row is deleted. If a hub RPC throws, nothing here has been deleted yet, so a retried
 * logout can still notify and delete it; the relay may only ever *remove* trust, so a lost
 * pairing_removed is unsafe but a duplicate (from a retry re-notifying an already-queued pair) is
 * not (spec §5.4–5.5, constraint 8).
 */
authRoutes.post("/logout", requireAuth, async (c) => {
  const auth = c.get("auth");
  const db = c.env.DB;
  const tokenHash = await hashToken(parseBearer(c.req.header("Authorization"))!);
  if (auth.kind === "agent") {
    const { results } = await db
      .prepare("SELECT mobile_id FROM pairings WHERE agent_id = ?")
      .bind(auth.deviceId)
      .all<{ mobile_id: string }>();
    const hub = hubFor(c.env, auth.userId);
    for (const { mobile_id: mobileId } of results) await hub.notifyPairingRemoved(auth.deviceId, mobileId);
    await db.batch([
      db.prepare("DELETE FROM tokens WHERE token_hash = ?").bind(tokenHash),
      db.prepare("DELETE FROM pairings WHERE agent_id = ?").bind(auth.deviceId),
    ]);
    // The token and pairings are already gone (fix round 1): a hub outage from here on must not
    // turn a successful logout into a 500. This agent's own pairings are all gone now, so it has no
    // trust list left to reconcile against any row still queued for it from before this logout —
    // drop them best-effort, logging metadata only on failure.
    try {
      await hub.purgeAgent(auth.deviceId);
    } catch {
      logMeta("agent_purge_failed", { device_id: auth.deviceId });
    }
  } else {
    await db.prepare("DELETE FROM tokens WHERE token_hash = ?").bind(tokenHash).run();
  }
  logMeta("logout", { device_id: auth.deviceId });
  return c.body(null, 204);
});

/**
 * POST /v1/auth/password {new_password} — agent token only, no old password (spec §5.2).
 * Revokes every other device's tokens and closes their sockets with 4002. Pairings are kept.
 */
authRoutes.post("/password", requireAuth, jsonBodyLimit, async (c) => {
  const auth = c.get("auth");
  if (auth.kind !== "agent") throw Errors.agentOnly();
  const body = await readJsonObject(c.req.raw);
  if (!isAcceptablePassword(body.new_password)) throw Errors.weakPassword();

  const db = c.env.DB;
  const now = c.get("now")();
  const passwordHash = await hashPassword(body.new_password);
  const { results } = await db
    .prepare("SELECT id FROM devices WHERE user_id = ? AND id != ?")
    .bind(auth.userId, auth.deviceId)
    .all<{ id: string }>();
  await db.batch([
    db.prepare("UPDATE users SET password_hash = ?, password_changed_at = ? WHERE id = ?").bind(passwordHash, now, auth.userId),
    db
      .prepare("DELETE FROM tokens WHERE device_id IN (SELECT id FROM devices WHERE user_id = ? AND id != ?)")
      .bind(auth.userId, auth.deviceId),
  ]);
  if (results.length > 0) {
    await hubFor(c.env, auth.userId).disconnect(results.map((r) => r.id), CloseCode.revoked);
  }
  logMeta("password_changed", { device_id: auth.deviceId });
  return c.body(null, 204);
});

import { Hono, type Context } from "hono";
import type { AppEnv } from "../app.js";
import { clientIp } from "../auth/client-ip.js";
import { parseDevice } from "../auth/device.js";
import { checkEmail, normalizeEmail } from "../auth/email.js";
import { hashPassword } from "../auth/password.js";
import { isAcceptablePassword, isOverlongPassword } from "../auth/password-policy.js";
import { insertToken, insertTokenIfPasswordUnchanged, requireAuth } from "../auth/session.js";
import { generateToken, hashToken, parseBearer } from "../auth/tokens.js";
import { jsonBodyLimit } from "../http/body-limit.js";
import { Errors, readJsonObject } from "../http/errors.js";
import { logMeta } from "../log.js";
import { CloseCode } from "../protocol/frames.js";

export const authRoutes = new Hono<AppEnv>();

/** Rate-limit key: X-Real-IP from nginx-proxy, else the socket address (see auth/client-ip.ts). */
function requestIp(c: Context<AppEnv>): string {
  return clientIp(c.req.header("X-Real-IP"), c.env.incoming.socket.remoteAddress);
}

let dummyPhc: Promise<string> | undefined;
/** Verifying against a throwaway hash keeps unknown-email logins as slow as wrong-password ones. */
function dummyHash(): Promise<string> {
  dummyPhc ??= hashPassword("shellx-dummy-password");
  return dummyPhc;
}

authRoutes.post("/register", jsonBodyLimit, async (c) => {
  if (!(await c.get("limiters").registerIp.limit(requestIp(c)))) throw Errors.rateLimited();
  const body = await readJsonObject(c.req.raw);
  const email = checkEmail(body.email);
  if (!email.ok) throw email.code === "invalid_email" ? Errors.invalidEmail() : Errors.disposableEmail();
  if (!isAcceptablePassword(body.password)) throw Errors.weakPassword();
  const device = parseDevice(body.device);
  if (device === null) throw Errors.invalidDevice();

  const db = c.get("db");
  if (db.get("SELECT 1 FROM users WHERE email = ?", email.email) !== undefined) throw Errors.emailTaken();
  const now = c.get("now")();
  const userId = crypto.randomUUID();
  const deviceId = crypto.randomUUID();
  const passwordHash = await c.get("passwords").hash(body.password);
  const token = generateToken();
  const tokenHash = await hashToken(token);
  try {
    db.transaction(() => {
      db.run(
        "INSERT INTO users (id, email, password_hash, password_changed_at, created_at) VALUES (?, ?, ?, ?, ?)",
        userId, email.email, passwordHash, now, now,
      );
      db.run(
        "INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
        deviceId, userId, device.kind, device.name, device.platform, device.publicKey, now,
      );
      insertToken(db, tokenHash, deviceId, now);
    });
  } catch (err) {
    if (String(err).includes("UNIQUE constraint failed: users.email")) throw Errors.emailTaken();
    throw err;
  }
  logMeta("register", { device_id: deviceId });
  return c.json({ user_id: userId, device_id: deviceId, token }, 201);
});

authRoutes.post("/login", jsonBodyLimit, async (c) => {
  const limiters = c.get("limiters");
  if (!(await limiters.loginIp.limit(requestIp(c)))) throw Errors.rateLimited();
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

  const db = c.get("db");
  const user = db.get<{ id: string; password_hash: string }>("SELECT id, password_hash FROM users WHERE email = ?", email);
  const passwordOk = await c.get("passwords").verify(password, user?.password_hash ?? (await dummyHash()));
  if (user === undefined || !passwordOk) {
    logMeta("login_failed");
    throw Errors.invalidCredentials();
  }

  const now = c.get("now")();
  // Same public key in the same account → same device_id (spec §5.2); name/platform refreshed.
  const deviceId = db.get<{ id: string }>(
    `INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT (user_id, public_key) DO UPDATE SET name = excluded.name, platform = excluded.platform
     RETURNING id`,
    crypto.randomUUID(), user.id, device.kind, device.name, device.platform, device.publicKey, now,
  )!.id;
  const token = generateToken();
  const tokenHash = await hashToken(token);
  // One live token per device: logging in again replaces the previous token. Both statements only
  // apply while the password is still the one verified above: a change that committed meanwhile
  // (M1) must neither get a token minted under the old password nor sign this device out.
  const unchanged = "(SELECT password_hash FROM users WHERE id = ?) = ?";
  const inserted = db.transaction(() => {
    db.run(`DELETE FROM tokens WHERE device_id = ? AND ${unchanged}`, deviceId, user.id, user.password_hash);
    return insertTokenIfPasswordUnchanged(db, tokenHash, deviceId, now, user.id, user.password_hash);
  });
  if (inserted !== 1) {
    logMeta("login_failed", { device_id: deviceId });
    throw Errors.invalidCredentials();
  }
  logMeta("login", { device_id: deviceId });
  return c.json({ user_id: user.id, device_id: deviceId, token }, 200);
});

/**
 * POST /v1/auth/logout — deletes this token; for an agent also every pairing it owns (spec §5.2).
 *
 * Notify-before-delete (same safe order as `DELETE /v1/pairings`): every pairing is reported to the
 * hub — which durably records the tombstone for the agent before doing anything live — before any
 * row is deleted. If a hub call throws, nothing here has been deleted yet, so a retried logout can
 * still notify and delete it; a lost pairing_removed is unsafe, a duplicate is not.
 */
authRoutes.post("/logout", requireAuth, async (c) => {
  const auth = c.get("auth");
  const db = c.get("db");
  const hubs = c.get("hubs");
  const tokenHash = await hashToken(parseBearer(c.req.header("Authorization"))!);
  if (auth.kind === "agent") {
    const rows = db.all<{ mobile_id: string; pairing_id: string }>(
      "SELECT mobile_id, pairing_id FROM pairings WHERE agent_id = ?",
      auth.deviceId,
    );
    for (const row of rows) await hubs.forUser(auth.userId).notifyPairingRemoved(auth.deviceId, row.mobile_id, row.pairing_id);
    db.transaction(() => {
      db.run("DELETE FROM tokens WHERE token_hash = ?", tokenHash);
      db.run("DELETE FROM pairings WHERE agent_id = ?", auth.deviceId);
    });
    // The token and pairings are already gone: a hub failure from here on must not turn a
    // successful logout into a 500. The agent has no trust list left to reconcile against rows
    // still queued for it, so drop them best-effort, logging metadata only on failure.
    try {
      await hubs.forUser(auth.userId).purgeAgent(auth.deviceId);
    } catch {
      logMeta("agent_purge_failed", { device_id: auth.deviceId });
    }
  } else {
    db.run("DELETE FROM tokens WHERE token_hash = ?", tokenHash);
  }
  logMeta("logout", { device_id: auth.deviceId });
  return c.body(null, 204);
});

/**
 * POST /v1/auth/password {new_password} — agent token only, no old password (spec §5.2).
 * Revokes every other device's tokens and closes their sockets with 4002. Pairings are kept.
 * The sockets are closed by the hub from its own live list once the change has committed; a socket
 * that lands in the hub only after this runs is caught by the ws route's post-upgrade re-check.
 */
authRoutes.post("/password", requireAuth, jsonBodyLimit, async (c) => {
  const auth = c.get("auth");
  if (auth.kind !== "agent") throw Errors.agentOnly();
  const body = await readJsonObject(c.req.raw);
  if (!isAcceptablePassword(body.new_password)) throw Errors.weakPassword();

  const db = c.get("db");
  const now = c.get("now")();
  const passwordHash = await c.get("passwords").hash(body.new_password);
  db.transaction(() => {
    db.run("UPDATE users SET password_hash = ?, password_changed_at = ? WHERE id = ?", passwordHash, now, auth.userId);
    db.run("DELETE FROM tokens WHERE device_id IN (SELECT id FROM devices WHERE user_id = ? AND id != ?)", auth.userId, auth.deviceId);
  });
  await c.get("hubs").forUser(auth.userId).disconnectAllExcept(auth.deviceId, CloseCode.revoked);
  logMeta("password_changed", { device_id: auth.deviceId });
  return c.body(null, 204);
});

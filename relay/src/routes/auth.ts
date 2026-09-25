import { Hono, type Context } from "hono";
import type { AppEnv } from "../app";
import { parseDevice, type DeviceInput } from "../auth/device";
import { checkEmail, normalizeEmail } from "../auth/email";
import { hashPassword, verifyPassword } from "../auth/password";
import { isAcceptablePassword } from "../auth/password-policy";
import { insertTokenStatement } from "../auth/session";
import { generateToken, hashToken } from "../auth/tokens";
import { Errors, readJsonObject } from "../http/errors";
import { logMeta } from "../log";

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

authRoutes.post("/register", async (c) => {
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

authRoutes.post("/login", async (c) => {
  const limiters = c.get("limiters");
  if (!(await limiters.loginIp.limit(clientIp(c)))) throw Errors.rateLimited();
  const body = await readJsonObject(c.req.raw);
  const email = typeof body.email === "string" ? normalizeEmail(body.email) : "";
  if (!(await limiters.loginEmail.limit(email))) throw Errors.rateLimited();
  const device = parseDevice(body.device);
  if (device === null) throw Errors.invalidDevice();
  const password = typeof body.password === "string" ? body.password : "";

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

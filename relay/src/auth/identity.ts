import type { Db } from "../db/db.js";
import type { DeviceInput } from "./device.js";
import type { VerifiedIdToken } from "./id-token.js";
import type { IdentityProvider } from "./providers.js";
import { type AuthMethod, insertToken } from "./session.js";

/**
 * Account resolution and identity rows (S1 §6.3). Every function here is synchronous and meant to run
 * inside one `db.transaction`, after the route has done all its awaits.
 */
export type AccountMatch =
  | { kind: "identity"; userId: string; identityId: string }
  | { kind: "email"; userId: string; hasPrimary: boolean }
  | { kind: "switch_required" }
  | { kind: "none" };

/**
 * S1 §6.3 steps 1 and 2: an identity with this (provider, subject) wins; else the account holding this
 * email: with `passwordLogin` on and a password still set, the user must switch from a signed-in device
 * (`switch_required`); otherwise the email links (`hasPrimary`: it already has a Google sign-in).
 * Only the Google route links on `email`; the Apple route signs in on `identity` alone (S1 §6.3 step 4).
 */
export function matchAccount(db: Db, token: VerifiedIdToken, passwordLogin: boolean): AccountMatch {
  const identity = db.get<{ id: string; user_id: string }>(
    "SELECT id, user_id FROM identities WHERE provider = ? AND subject = ?", token.provider, token.subject,
  );
  if (identity !== undefined) return { kind: "identity", userId: identity.user_id, identityId: identity.id };
  const user = db.get<{ id: string; password_hash: string | null }>("SELECT id, password_hash FROM users WHERE email = ?", token.email);
  if (user === undefined) return { kind: "none" };
  if (passwordLogin && user.password_hash !== null) return { kind: "switch_required" };
  const primary = db.get("SELECT 1 FROM identities WHERE user_id = ? AND provider != 'apple'", user.id);
  return { kind: "email", userId: user.id, hasPrimary: primary !== undefined };
}

export interface NewIdentity {
  provider: IdentityProvider;
  subject: string;
  email: string;
  isPrivateEmail: boolean;
  appleRefreshToken: string | null;
  appleClientId: string | null;
  linkedViaDeviceId: string | null;
}

export function identityFromToken(token: VerifiedIdToken): NewIdentity {
  return {
    provider: token.provider, subject: token.subject, email: token.email, isPrivateEmail: token.isPrivateEmail,
    appleRefreshToken: null, appleClientId: null, linkedViaDeviceId: null,
  };
}

/** Inserts an identity for `userId`; returns its new UUID (the API's identity_id). */
export function insertIdentity(db: Db, userId: string, identity: NewIdentity, now: number): string {
  const id = crypto.randomUUID();
  db.run(
    `INSERT INTO identities (id, provider, subject, user_id, email, is_private_email, apple_refresh_token, apple_client_id,
                             linked_via_device_id, created_at, last_used_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    id, identity.provider, identity.subject, userId, identity.email, identity.isPrivateEmail ? 1 : 0,
    identity.appleRefreshToken, identity.appleClientId, identity.linkedViaDeviceId, now, now,
  );
  return id;
}

/** Removes the password and signs out the password sessions; returns how many sessions went. */
export function dropPasswordAccess(db: Db, userId: string): number {
  db.run("UPDATE users SET password_hash = NULL WHERE id = ?", userId);
  return db.run(
    "DELETE FROM tokens WHERE auth_method = 'password' AND device_id IN (SELECT id FROM devices WHERE user_id = ?)", userId,
  ).changes;
}

/** Same public key in the same account → same device_id; name and platform refreshed (as /login does). */
export function upsertDevice(db: Db, userId: string, device: DeviceInput, now: number): string {
  return db.get<{ id: string }>(
    `INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT (user_id, public_key) DO UPDATE SET name = excluded.name, platform = excluded.platform
     RETURNING id`,
    crypto.randomUUID(), userId, device.kind, device.name, device.platform, device.publicKey, now,
  )!.id;
}

/** One live token per device: deletes the device's tokens, then stores the new one. */
export function replaceDeviceToken(
  db: Db, deviceId: string, tokenHash: ArrayBuffer, authMethod: AuthMethod, identityId: string | null, now: number,
): void {
  db.run("DELETE FROM tokens WHERE device_id = ?", deviceId);
  insertToken(db, tokenHash, deviceId, now, authMethod, identityId);
}

export function signInDevice(
  db: Db, userId: string, device: DeviceInput, tokenHash: ArrayBuffer, authMethod: AuthMethod, identityId: string | null, now: number,
): string {
  const deviceId = upsertDevice(db, userId, device, now);
  replaceDeviceToken(db, deviceId, tokenHash, authMethod, identityId, now);
  return deviceId;
}

export function accountEmail(db: Db, userId: string): string {
  return db.get<{ email: string }>("SELECT email FROM users WHERE id = ?", userId)!.email;
}

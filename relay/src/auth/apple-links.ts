import type { Db } from "../db/db.js";
import { Errors } from "../http/errors.js";
import { upsertDevice, insertIdentity } from "./identity.js";
import { generateToken, hashToken } from "./tokens.js";

/** The link token of an Apple sign-in that matched no account lives 10 minutes (S1 §6.4). */
export const APPLE_LINK_TTL_MS = 600_000;
/** Rows are purged a day after creation. */
export const APPLE_LINK_RETENTION_MS = 86_400_000;

const LINK_TOKEN_RE = /^[A-Za-z0-9_-]{43}$/;

export interface AppleLinkRow {
  id: string;
  token_hash: Buffer;
  subject: string;
  email: string;
  is_private_email: number;
  apple_client_id: string;
  apple_refresh_token: string | null;
  device_name: string;
  device_public_key: Buffer;
  created_at: number;
  expires_at: number;
  redeemed_at: number | null;
}

export interface NewAppleLink {
  subject: string;
  email: string;
  isPrivateEmail: boolean;
  appleClientId: string;
  appleRefreshToken: string | null;
  deviceName: string;
  devicePublicKey: Uint8Array;
}

/** Stores the link (only the SHA-256 of its token) and returns the token for the iPhone. */
export async function createAppleLink(db: Db, link: NewAppleLink, nowMs: number): Promise<string> {
  const token = generateToken();
  const hash = await hashToken(token);
  db.run(
    `INSERT INTO apple_links (id, token_hash, subject, email, is_private_email, apple_client_id, apple_refresh_token,
                              device_name, device_public_key, created_at, expires_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    crypto.randomUUID(), hash, link.subject, link.email, link.isPrivateEmail ? 1 : 0, link.appleClientId, link.appleRefreshToken,
    link.deviceName, link.devicePublicKey, nowMs, nowMs + APPLE_LINK_TTL_MS,
  );
  return token;
}

/** The link of a 43-character token that has not expired and has not handed out its session yet. */
export async function findLiveAppleLink(db: Db, linkToken: unknown, nowMs: number): Promise<AppleLinkRow | undefined> {
  if (typeof linkToken !== "string" || !LINK_TOKEN_RE.test(linkToken)) return undefined;
  return db.get<AppleLinkRow>(
    "SELECT * FROM apple_links WHERE token_hash = ? AND expires_at > ? AND redeemed_at IS NULL", await hashToken(linkToken), nowMs,
  );
}

/** Deletes links created more than a day ago (their pairing requests go with them). */
export function purgeAppleLinks(db: Db, nowMs: number): void {
  db.run("DELETE FROM apple_links WHERE created_at < ?", nowMs - APPLE_LINK_RETENTION_MS);
}

/**
 * Runs inside the approve transaction of a phone pairing made with a link token: creates (or finds) the
 * iPhone's device in the Mac's account, attaches the Apple ID to that account and points the pairing at
 * the device. Returns the device id. The session token is minted later, by the status call.
 */
export function approveAppleLinkPairing(db: Db, pairing: { id: string; user_id: string; apple_link_id: string }, nowMs: number): string {
  const link = db.get<AppleLinkRow>("SELECT * FROM apple_links WHERE id = ?", pairing.apple_link_id);
  if (link === undefined || link.expires_at <= nowMs || link.redeemed_at !== null) throw Errors.pairingExpired();
  const existing = db.get<{ id: string; user_id: string }>("SELECT id, user_id FROM identities WHERE provider = 'apple' AND subject = ?", link.subject);
  if (existing !== undefined && existing.user_id !== pairing.user_id) throw Errors.identityInUse();
  const deviceId = upsertDevice(db, pairing.user_id, { kind: "mobile", name: link.device_name, platform: "ios", publicKey: link.device_public_key }, nowMs);
  if (existing === undefined) {
    insertIdentity(db, pairing.user_id, {
      provider: "apple", subject: link.subject, email: link.email, isPrivateEmail: link.is_private_email === 1,
      appleRefreshToken: link.apple_refresh_token,
      appleClientId: link.apple_refresh_token === null ? null : link.apple_client_id,
      linkedViaDeviceId: deviceId,
    }, nowMs);
  } else {
    db.run("UPDATE identities SET last_used_at = ? WHERE id = ?", nowMs, existing.id);
    if (link.apple_refresh_token !== null) {
      db.run("UPDATE identities SET apple_refresh_token = ?, apple_client_id = ? WHERE id = ?", link.apple_refresh_token, link.apple_client_id, existing.id);
    }
  }
  db.run("UPDATE phone_pairings SET device_id = ? WHERE id = ?", deviceId, pairing.id);
  return deviceId;
}

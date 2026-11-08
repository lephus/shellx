import { Hono } from "hono";
import type { AppEnv } from "../app.js";
import { findLiveAppleLink, purgeAppleLinks } from "../auth/apple-links.js";
import { requestIp } from "../auth/client-ip.js";
import { accountEmail, replaceDeviceToken } from "../auth/identity.js";
import { generateToken, hashToken } from "../auth/tokens.js";
import { jsonBodyLimit } from "../http/body-limit.js";
import { Errors, readJsonObject } from "../http/errors.js";
import { logMeta } from "../log.js";
import { parseUuid } from "../protocol/uuid.js";
import { decodeB64 } from "../v2/encoding.js";
import { accountMachine } from "../v2/guard.js";
import { MAX_PENDING_PER_TARGET, PAIRING_TTL_MS } from "../v2/pairings.js";
import { phonePairingHousekeeping } from "../v2/phones.js";
import { CLIENT_VERSION_HEADER, recordAppVersion } from "../versions.js";

/**
 * An iPhone whose Apple ID matched no account asks a Mac to link it (S1 §6.4). Mounted at
 * /v1/auth/apple/link; the link token from POST /v1/auth/apple is the only credential.
 */
export const appleLinkRoutes = new Hono<AppEnv>();

/** POST / {link_token, machine_id, client_key_b64, proof_b64} — the request the Mac shows as a QR-pairing sheet. */
appleLinkRoutes.post("/", jsonBodyLimit, async (c) => {
  if (!(await c.get("limiters").loginIp.limit(requestIp(c)))) throw Errors.rateLimited();
  const body = await readJsonObject(c.req.raw);
  const db = c.get("db");
  const now = c.get("now")();
  purgeAppleLinks(db, now);
  const link = await findLiveAppleLink(db, body.link_token, now);
  if (link === undefined) throw Errors.invalidCredentials();
  if (db.get("SELECT 1 FROM phone_pairings WHERE apple_link_id = ? AND status = 'approved'", link.id) !== undefined) {
    throw Errors.invalidCredentials();
  }
  // The machine may belong to any account: the Mac's Allow decides, and the Apple ID joins that account.
  const machineId = parseUuid(body.machine_id);
  const machine = machineId === null ? undefined : db.get<{ id: string; user_id: string }>("SELECT id, user_id FROM machines WHERE id = ?", machineId);
  if (machine === undefined) throw Errors.machineNotFound();
  const key = decodeB64(body.client_key_b64, 32, 32);
  const proof = decodeB64(body.proof_b64, 32, 32);
  if (key === null || proof === null) throw Errors.badRequest();

  phonePairingHousekeeping(db, now);
  const id = crypto.randomUUID();
  db.transaction(() => {
    db.run("UPDATE phone_pairings SET status = 'expired' WHERE apple_link_id = ? AND status = 'pending'", link.id);
    const pending = db.get<{ n: number }>(
      "SELECT COUNT(*) AS n FROM phone_pairings WHERE machine_id = ? AND status = 'pending' AND created_at >= ?",
      machine.id, now - PAIRING_TTL_MS,
    )!.n;
    if (pending >= MAX_PENDING_PER_TARGET) throw Errors.rateLimited();
    db.run(
      `INSERT INTO phone_pairings (id, user_id, device_id, machine_id, client_key, proof, status, created_at, apple_link_id)
       VALUES (?, ?, NULL, ?, ?, ?, 'pending', ?, ?)`,
      id, machine.user_id, machine.id, key, Buffer.from(proof).toString("base64"), now, link.id,
    );
  });
  logMeta("apple_link_requested", { pairing_id: id });
  return c.json({ pairing_id: id }, 201);
});

/** POST /status {link_token, pairing_id} — the iPhone polls; the approved session is handed out exactly once. */
appleLinkRoutes.post("/status", jsonBodyLimit, async (c) => {
  const body = await readJsonObject(c.req.raw);
  const db = c.get("db");
  const now = c.get("now")();
  const link = await findLiveAppleLink(db, body.link_token, now);
  if (link === undefined) throw Errors.invalidCredentials();
  phonePairingHousekeeping(db, now);
  const pairingId = parseUuid(body.pairing_id);
  const pairing =
    pairingId === null
      ? undefined
      : db.get<{ id: string; user_id: string; device_id: string | null; machine_id: string; status: string }>(
          "SELECT id, user_id, device_id, machine_id, status FROM phone_pairings WHERE id = ? AND apple_link_id = ?", pairingId, link.id,
        );
  if (pairing === undefined) throw Errors.pairingNotFound();
  if (pairing.status !== "approved") return c.json({ status: pairing.status });

  const machine = accountMachine(db, pairing.user_id, pairing.machine_id);
  if (machine === undefined || pairing.device_id === null) throw Errors.pairingNotFound();
  const deviceId = pairing.device_id;
  const token = generateToken();
  const tokenHash = await hashToken(token);
  db.transaction(() => {
    // Exactly once: the conditional update decides which call gets the session.
    if (db.run("UPDATE apple_links SET redeemed_at = ? WHERE id = ? AND redeemed_at IS NULL", now, link.id).changes !== 1) {
      throw Errors.invalidCredentials();
    }
    const identity = db.get<{ id: string }>(
      "SELECT id FROM identities WHERE provider = 'apple' AND subject = ? AND user_id = ?", link.subject, pairing.user_id,
    );
    if (identity === undefined) throw Errors.invalidCredentials();
    replaceDeviceToken(db, deviceId, tokenHash, "apple", identity.id, now);
  });
  recordAppVersion(db, deviceId, c.req.header(CLIENT_VERSION_HEADER));
  logMeta("apple_link_redeemed", { device_id: deviceId, pairing_id: pairing.id });
  return c.json({
    status: "approved",
    session: { user_id: pairing.user_id, device_id: deviceId, token, email: accountEmail(db, pairing.user_id) },
    machine: { machine_id: machine.id, name: machine.name, link_slot: machine.link_slot },
  });
});

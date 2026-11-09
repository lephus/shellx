import { Hono } from "hono";
import type { AppEnv } from "../app.js";
import { approveAppleLinkPairing } from "../auth/apple-links.js";
import { requireAuth } from "../auth/session.js";
import type { Db } from "../db/db.js";
import { jsonBodyLimit } from "../http/body-limit.js";
import { Errors, readJsonObject } from "../http/errors.js";
import { logMeta } from "../log.js";
import { parseUuid } from "../protocol/uuid.js";
import { decodeB64, unixSeconds } from "./encoding.js";
import { accountMachine, ONLINE_WINDOW_MS, ownMachine, requireDesktop, requireMobile } from "./guard.js";
import { MAX_PENDING_PER_TARGET, PAIRING_TTL_MS } from "./pairings.js";

/** Rows are deleted this long after they were created (grants are kept). */
const PHONE_PAIRING_RETENTION_MS = 24 * 60 * 60_000;

/** Purge, then the lazy expiry: a pending request older than PAIRING_TTL_MS is written `expired`. */
export function phonePairingHousekeeping(db: Db, nowMs: number): void {
  db.transaction(() => {
    db.run("DELETE FROM phone_pairings WHERE created_at < ?", nowMs - PHONE_PAIRING_RETENTION_MS);
    db.run("UPDATE phone_pairings SET status = 'expired' WHERE status = 'pending' AND created_at < ?", nowMs - PAIRING_TTL_MS);
  });
}

interface PhonePairingRow {
  id: string;
  user_id: string;
  device_id: string | null;
  apple_link_id: string | null;
  machine_id: string;
  client_key: Buffer;
  proof: string;
  status: "pending" | "approved" | "denied" | "expired";
  created_at: number;
  decided_at: number | null;
}

/** A phone pairing of this account by id (undefined for a malformed id or another account's request). */
function accountPhonePairing(db: Db, userId: string, pairingId: unknown): PhonePairingRow | undefined {
  const id = parseUuid(pairingId);
  if (id === null) return undefined;
  return db.get<PhonePairingRow>("SELECT * FROM phone_pairings WHERE id = ? AND user_id = ?", id, userId);
}

/** 403 unless the caller's own machine is the request's target. */
function requireTargetMachine(db: Db, deviceId: string, pairing: PhonePairingRow): void {
  const machine = ownMachine(db, deviceId);
  if (machine === undefined || machine.id !== pairing.machine_id) throw Errors.forbidden();
}

export const phonePairingRoutes = new Hono<AppEnv>();

/** POST /v2/phone-pairings {machine_id, client_key_b64, proof_b64} — a phone asks a machine of its account. */
phonePairingRoutes.post("/", requireAuth, requireMobile, jsonBodyLimit, async (c) => {
  const auth = c.get("auth");
  const db = c.get("db");
  const now = c.get("now")();
  if (!(await c.get("limiters").pairingCreate.limit(auth.deviceId))) throw Errors.rateLimited();
  const body = await readJsonObject(c.req.raw);
  phonePairingHousekeeping(db, now);

  const machine = accountMachine(db, auth.userId, body.machine_id);
  if (machine === undefined) throw Errors.machineNotFound();
  const key = decodeB64(body.client_key_b64, 32, 32);
  const proof = decodeB64(body.proof_b64, 32, 32);
  if (key === null || proof === null) throw Errors.badRequest();

  const id = crypto.randomUUID();
  db.transaction(() => {
    // A newer request from the same phone to the same machine supersedes the older one.
    db.run(
      "UPDATE phone_pairings SET status = 'expired' WHERE device_id = ? AND machine_id = ? AND status = 'pending'",
      auth.deviceId, machine.id,
    );
    const pending = db.get<{ n: number }>(
      "SELECT COUNT(*) AS n FROM phone_pairings WHERE machine_id = ? AND status = 'pending' AND created_at >= ?",
      machine.id, now - PAIRING_TTL_MS,
    )!.n;
    if (pending >= MAX_PENDING_PER_TARGET) throw Errors.rateLimited(); // also rolls the supersede back
    db.run(
      `INSERT INTO phone_pairings (id, user_id, device_id, machine_id, client_key, proof, status, created_at)
       VALUES (?, ?, ?, ?, ?, ?, 'pending', ?)`,
      id, auth.userId, auth.deviceId, machine.id, key, Buffer.from(proof).toString("base64"), now,
    );
  });
  logMeta("phone_pairing_created", { device_id: auth.deviceId, pairing_id: id });
  return c.json({ pairing_id: id }, 201);
});

/** GET /v2/phone-pairings/:id — the sending phone polls; once approved it learns the machine's link slot. */
phonePairingRoutes.get("/:id", requireAuth, requireMobile, async (c) => {
  const auth = c.get("auth");
  const db = c.get("db");
  phonePairingHousekeeping(db, c.get("now")());
  const pairing = accountPhonePairing(db, auth.userId, c.req.param("id"));
  // Another phone of the same account gets the same 404: the request is the sender's business only.
  if (pairing === undefined || pairing.device_id !== auth.deviceId) throw Errors.pairingNotFound();
  if (pairing.status !== "approved") return c.json({ status: pairing.status });
  const machine = accountMachine(db, auth.userId, pairing.machine_id);
  if (machine === undefined) throw Errors.pairingNotFound();
  return c.json({ status: "approved", machine: { machine_id: machine.id, name: machine.name, link_slot: machine.link_slot } });
});

/** GET /v2/phone-pairings?role=target — pending requests to the caller's machine. */
phonePairingRoutes.get("/", requireAuth, requireDesktop, async (c) => {
  const auth = c.get("auth");
  const db = c.get("db");
  const now = c.get("now")();
  if (c.req.query("role") !== "target") throw Errors.badRequest();
  phonePairingHousekeeping(db, now);
  const machine = ownMachine(db, auth.deviceId);
  if (machine === undefined) return c.json({ pairings: [] });
  // Apple-link requests (made with a link token, S1 §6.4) are listed only with apple_links=1: an older
  // desktop never shows a sheet that lacks the Apple warning.
  const rows = db.all<PhonePairingRow & { device_name: string; platform: string }>(
    `SELECT p.*, COALESCE(d.name, l.device_name) AS device_name, COALESCE(d.platform, 'ios') AS platform
       FROM phone_pairings p
       LEFT JOIN devices d ON d.id = p.device_id
       LEFT JOIN apple_links l ON l.id = p.apple_link_id
      WHERE p.machine_id = ? AND p.status = 'pending' AND p.created_at >= ?
        AND (p.apple_link_id IS NULL OR (? = 1 AND l.expires_at > ?))
      ORDER BY p.created_at DESC, p.rowid DESC`,
    machine.id, now - PAIRING_TTL_MS, c.req.query("apple_links") === "1" ? 1 : 0, now,
  );
  return c.json({
    pairings: rows.map((p) => ({
      pairing_id: p.id,
      device_name: p.device_name,
      platform: p.platform,
      client_key_b64: p.client_key.toString("base64"),
      proof_b64: p.proof,
      created_at_unix: unixSeconds(p.created_at),
      links_apple_id: p.apple_link_id !== null,
    })),
  });
});

/** POST /v2/phone-pairings/:id/approve — the target machine only; grants the phone link access. */
phonePairingRoutes.post("/:id/approve", requireAuth, requireDesktop, async (c) => {
  const auth = c.get("auth");
  const db = c.get("db");
  const now = c.get("now")();
  const pairing = accountPhonePairing(db, auth.userId, c.req.param("id"));
  if (pairing === undefined) throw Errors.pairingNotFound();
  requireTargetMachine(db, auth.deviceId, pairing);

  phonePairingHousekeeping(db, now);
  db.transaction(() => {
    // The status condition makes a concurrent second approval (or one after a deny) change nothing.
    const updated = db.run(
      "UPDATE phone_pairings SET status = 'approved', decided_at = ? WHERE id = ? AND status = 'pending' AND created_at >= ?",
      now, pairing.id, now - PAIRING_TTL_MS,
    );
    if (updated.changes === 0) {
      throw pairing.created_at < now - PAIRING_TTL_MS ? Errors.pairingExpired() : Errors.pairingNotPending();
    }
    // An Apple-link request has no device yet: approving it creates the iPhone's device, attaches the
    // Apple ID to this account and may throw (identity_in_use, pairing_expired), rolling the status back.
    const deviceId =
      pairing.apple_link_id === null
        ? pairing.device_id!
        : approveAppleLinkPairing(db, { id: pairing.id, user_id: pairing.user_id, apple_link_id: pairing.apple_link_id }, now);
    db.run(
      `INSERT INTO phone_grants (id, user_id, device_id, machine_id, client_key, pairing_id, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT (device_id, machine_id) DO UPDATE SET
         client_key = excluded.client_key, pairing_id = excluded.pairing_id, created_at = excluded.created_at`,
      crypto.randomUUID(), pairing.user_id, deviceId, pairing.machine_id, pairing.client_key, pairing.id, now,
    );
  });
  logMeta("phone_pairing_approved", { device_id: auth.deviceId, pairing_id: pairing.id });
  return c.body(null, 204);
});

/** POST /v2/phone-pairings/:id/deny — the target machine denies, or the sending phone cancels, a pending request. */
phonePairingRoutes.post("/:id/deny", requireAuth, async (c) => {
  const auth = c.get("auth");
  const db = c.get("db");
  const now = c.get("now")();
  if (auth.kind !== "desktop" && auth.kind !== "mobile") throw Errors.desktopOnly();
  const pairing = accountPhonePairing(db, auth.userId, c.req.param("id"));
  if (pairing === undefined) throw Errors.pairingNotFound();
  if (auth.kind === "desktop") requireTargetMachine(db, auth.deviceId, pairing);
  else if (pairing.device_id !== auth.deviceId) throw Errors.forbidden();

  phonePairingHousekeeping(db, now);
  const updated = db.run(
    "UPDATE phone_pairings SET status = 'denied', decided_at = ? WHERE id = ? AND status = 'pending' AND created_at >= ?",
    now, pairing.id, now - PAIRING_TTL_MS,
  );
  if (updated.changes === 0) {
    const status = db.get<{ status: string }>("SELECT status FROM phone_pairings WHERE id = ?", pairing.id)?.status;
    if (status === "denied") return c.body(null, 204);
    throw Errors.pairingNotPending();
  }
  logMeta("phone_pairing_denied", { device_id: auth.deviceId, pairing_id: pairing.id });
  return c.body(null, 204);
});

export const phoneGrantRoutes = new Hono<AppEnv>();

/** GET /v2/phone-grants — a phone: its machines; a desktop: the phones allowed on its machine. */
phoneGrantRoutes.get("/", requireAuth, async (c) => {
  const auth = c.get("auth");
  const db = c.get("db");
  const now = c.get("now")();

  if (auth.kind === "mobile") {
    const rows = db.all<{
      id: string; machine_id: string; name: string; platform: string; link_slot: string; fingerprint: string; last_seen_at: number | null;
    }>(
      `SELECT g.id, g.machine_id, m.name, m.platform, m.link_slot, m.fingerprint, m.last_seen_at
         FROM phone_grants g JOIN machines m ON m.id = g.machine_id
        WHERE g.device_id = ? AND g.user_id = ?
        ORDER BY g.created_at, g.rowid`,
      auth.deviceId, auth.userId,
    );
    return c.json({
      grants: rows.map((g) => ({
        grant_id: g.id,
        machine_id: g.machine_id,
        name: g.name,
        platform: g.platform,
        online: g.last_seen_at !== null && now - g.last_seen_at <= ONLINE_WINDOW_MS,
        link_slot: g.link_slot,
        fingerprint: g.fingerprint,
      })),
    });
  }

  if (auth.kind !== "desktop") throw Errors.desktopOnly();
  const machine = ownMachine(db, auth.deviceId);
  if (machine === undefined) return c.json({ grants: [] });
  const rows = db.all<{
    id: string; device_id: string; device_name: string; platform: string; client_key: Buffer; created_at: number; last_seen_at: number | null;
  }>(
    `SELECT g.id, g.device_id, d.name AS device_name, d.platform, g.client_key, g.created_at, d.last_seen_at
       FROM phone_grants g JOIN devices d ON d.id = g.device_id
      WHERE g.machine_id = ? AND g.user_id = ?
      ORDER BY g.created_at, g.rowid`,
    machine.id, auth.userId,
  );
  return c.json({
    grants: rows.map((g) => ({
      grant_id: g.id,
      device_id: g.device_id,
      device_name: g.device_name,
      platform: g.platform,
      client_key_b64: g.client_key.toString("base64"),
      created_at_unix: unixSeconds(g.created_at),
      last_seen_unix: g.last_seen_at === null ? null : unixSeconds(g.last_seen_at),
    })),
  });
});

/** DELETE /v2/phone-grants/:id — the owning phone, or the desktop of the machine, removes access. */
phoneGrantRoutes.delete("/:id", requireAuth, async (c) => {
  const auth = c.get("auth");
  const db = c.get("db");
  if (auth.kind !== "desktop" && auth.kind !== "mobile") throw Errors.desktopOnly();
  const id = parseUuid(c.req.param("id"));
  const grant = id === null ? undefined : db.get<{ id: string; device_id: string; machine_id: string }>(
    "SELECT id, device_id, machine_id FROM phone_grants WHERE id = ? AND user_id = ?", id, auth.userId,
  );
  if (grant === undefined) throw Errors.notFound();
  if (auth.kind === "mobile") {
    if (grant.device_id !== auth.deviceId) throw Errors.forbidden();
  } else if (ownMachine(db, auth.deviceId)?.id !== grant.machine_id) {
    throw Errors.forbidden();
  }
  db.run("DELETE FROM phone_grants WHERE id = ?", grant.id);
  logMeta("phone_grant_removed", { device_id: auth.deviceId, grant_id: grant.id });
  return c.body(null, 204);
});

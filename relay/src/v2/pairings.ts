import { randomInt } from "node:crypto";
import { Hono } from "hono";
import type { AppEnv } from "../app.js";
import { requireAuth } from "../auth/session.js";
import type { Db } from "../db/db.js";
import { jsonBodyLimit } from "../http/body-limit.js";
import { ApiError, Errors, readJsonObject } from "../http/errors.js";
import { logMeta } from "../log.js";
import { parseUuid } from "../protocol/uuid.js";
import { decodeB64 } from "./encoding.js";
import { accountMachine, ownMachine, requireDesktop } from "./guard.js";

/** A pending request can be approved for 5 minutes (K1); after that it reads `expired`. */
export const PAIRING_TTL_MS = 300_000;
/** Requests stay listed (and an approved invite stays fetchable) for 10 minutes. */
export const PAIRING_VISIBLE_MS = 600_000;
/** At most this many live pending requests per target machine. */
export const MAX_PENDING_PER_TARGET = 10;
/** Largest sealed invite (decoded bytes) the server stores. */
export const SEALED_INVITE_MAX_BYTES = 8192;
/** Rows are deleted this long after they were created (grants are kept). */
const PAIRING_RETENTION_MS = 24 * 60 * 60_000;
/** Draws of a fresh code before giving up on a target whose pending requests hold every drawn code. */
const CODE_DRAWS = 10;
const CODE_RE = /^\d{6}$/;
/** What a decrypted invite starts with; a sealed one never may (ledger §8.5: the PSK never reaches the server in clear). */
const PLAINTEXT_PREFIX = "cmux://";

/** The default `AppDeps.pairingCode`: 6 uniformly random decimal digits. */
export function randomPairingCode(): string {
  return String(randomInt(0, 1_000_000)).padStart(6, "0");
}

/** True when `fromMachineId` may connect to `toMachineId` (an approved pairing, not revoked since). */
export function hasGrant(db: Db, fromMachineId: string, toMachineId: string): boolean {
  return db.get("SELECT 1 AS x FROM machine_grants WHERE from_machine_id = ? AND to_machine_id = ?", fromMachineId, toMachineId) !== undefined;
}

/**
 * Housekeeping, run at the start of every /v2/pairings request: drops sealed invites decided more
 * than PAIRING_VISIBLE_MS ago and deletes rows older than 24 h. Grants are kept.
 */
export function purgePairings(db: Db, nowMs: number): void {
  db.run("UPDATE machine_pairings SET sealed_invite = NULL WHERE sealed_invite IS NOT NULL AND decided_at < ?", nowMs - PAIRING_VISIBLE_MS);
  db.run("DELETE FROM machine_pairings WHERE created_at < ?", nowMs - PAIRING_RETENTION_MS);
}

/** Purge, then the lazy expiry: a pending request older than PAIRING_TTL_MS is written `expired`. */
function housekeeping(db: Db, nowMs: number): void {
  db.transaction(() => {
    purgePairings(db, nowMs);
    db.run("UPDATE machine_pairings SET status = 'expired' WHERE status = 'pending' AND created_at < ?", nowMs - PAIRING_TTL_MS);
  });
}

interface PairingRow {
  id: string;
  user_id: string;
  from_machine_id: string;
  to_machine_id: string;
  requester_x25519: Buffer;
  requester_fingerprint: string;
  code: string;
  status: "pending" | "approved" | "denied" | "expired";
  sealed_invite: string | null;
  created_at: number;
  decided_at: number | null;
}

/** A pairing of this account by id (undefined for a malformed id or another account's pairing). */
function accountPairing(db: Db, userId: string, pairingId: unknown): PairingRow | undefined {
  const id = parseUuid(pairingId);
  if (id === null) return undefined;
  return db.get<PairingRow>("SELECT * FROM machine_pairings WHERE id = ? AND user_id = ?", id, userId);
}

/** 403 unless the caller's own machine is one of `allowed` (same account: the pairing's existence is no secret). */
function requireCallerMachine(db: Db, deviceId: string, allowed: readonly string[]): void {
  const machine = ownMachine(db, deviceId);
  if (machine === undefined || !allowed.includes(machine.id)) throw Errors.forbidden();
}

export const machinePairingRoutes = new Hono<AppEnv>();

/** POST /v2/pairings {from_machine_id, to_machine_id, requester_x25519_b64} — the requester asks the target. */
machinePairingRoutes.post("/", requireAuth, requireDesktop, jsonBodyLimit, async (c) => {
  const auth = c.get("auth");
  const db = c.get("db");
  const now = c.get("now")();
  if (!(await c.get("limiters").pairingCreate.limit(auth.deviceId))) throw Errors.rateLimited();
  const body = await readJsonObject(c.req.raw);
  housekeeping(db, now);

  const from = accountMachine(db, auth.userId, body.from_machine_id);
  if (from === undefined) throw Errors.machineNotFound();
  if (from.device_id !== auth.deviceId) throw Errors.forbidden();
  const to = accountMachine(db, auth.userId, body.to_machine_id);
  if (to === undefined) throw Errors.machineNotFound();
  if (to.id === from.id) throw Errors.badRequest();
  const x25519 = decodeB64(body.requester_x25519_b64, 32, 32);
  if (x25519 === null) throw Errors.badRequest();

  // Code and fingerprint are the server's: `code`, `requester_fingerprint` and `status` in the body are ignored.
  const pairingCode = c.get("pairingCode");
  const id = crypto.randomUUID();
  const code = db.transaction(() => {
    // A newer request from the same requester to the same target supersedes the older one.
    db.run(
      "UPDATE machine_pairings SET status = 'expired' WHERE from_machine_id = ? AND to_machine_id = ? AND status = 'pending'",
      from.id, to.id,
    );
    const pending = db.all<{ code: string }>(
      "SELECT code FROM machine_pairings WHERE to_machine_id = ? AND status = 'pending' AND created_at >= ?",
      to.id, now - PAIRING_TTL_MS,
    );
    if (pending.length >= MAX_PENDING_PER_TARGET) throw Errors.rateLimited(); // also rolls the supersede back
    const taken = new Set(pending.map((p) => p.code));
    let drawn: string | null = null;
    for (let i = 0; i < CODE_DRAWS && drawn === null; i++) {
      const candidate = pairingCode();
      if (CODE_RE.test(candidate) && !taken.has(candidate)) drawn = candidate;
    }
    if (drawn === null) {
      logMeta("pairing_code_exhausted", { device_id: auth.deviceId });
      throw new ApiError(500, "internal_error", "Internal error");
    }
    db.run(
      `INSERT INTO machine_pairings (id, user_id, from_machine_id, to_machine_id, requester_x25519,
                                     requester_fingerprint, code, status, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?)`,
      id, auth.userId, from.id, to.id, x25519, from.fingerprint, drawn, now,
    );
    return drawn;
  });
  logMeta("pairing_created", { device_id: auth.deviceId, pairing_id: id });
  return c.json({ pairing_id: id, code }, 201);
});

/** GET /v2/pairings?role=target|requester — requests to (or from) the caller's machine, newest first. */
machinePairingRoutes.get("/", requireAuth, requireDesktop, async (c) => {
  const auth = c.get("auth");
  const db = c.get("db");
  const now = c.get("now")();
  const role = c.req.query("role");
  if (role !== "target" && role !== "requester") throw Errors.badRequest();
  housekeeping(db, now);
  const machine = ownMachine(db, auth.deviceId);
  if (machine === undefined) return c.json({ pairings: [] });

  const rows = db.all<PairingRow>(
    `SELECT * FROM machine_pairings
      WHERE ${role === "target" ? "to_machine_id" : "from_machine_id"} = ? AND (created_at >= ? OR status = 'pending')
      ORDER BY created_at DESC, rowid DESC`,
    machine.id, now - PAIRING_VISIBLE_MS,
  );
  return c.json({
    pairings: rows.map((p) => ({
      pairing_id: p.id,
      from_machine_id: p.from_machine_id,
      to_machine_id: p.to_machine_id,
      requester_fingerprint: p.requester_fingerprint,
      // A public key (K1, D2): the target seals the invite to it.
      requester_x25519_b64: p.requester_x25519.toString("base64"),
      code: p.code,
      status: p.status,
      // Only the requester ever gets the invite back, and only until it is purged.
      ...(role === "requester" && p.status === "approved" && p.sealed_invite !== null ? { sealed_invite_b64: p.sealed_invite } : {}),
    })),
  });
});

/** POST /v2/pairings/:id/approve {sealed_invite_b64} — the target only; stores the ciphertext verbatim and grants `connect`. */
machinePairingRoutes.post("/:id/approve", requireAuth, requireDesktop, jsonBodyLimit, async (c) => {
  const auth = c.get("auth");
  const db = c.get("db");
  const now = c.get("now")();
  const pairing = accountPairing(db, auth.userId, c.req.param("id"));
  if (pairing === undefined) throw Errors.pairingNotFound();
  requireCallerMachine(db, auth.deviceId, [pairing.to_machine_id]);

  // A length check and a plaintext guard, nothing more: the server never looks inside the invite.
  const sealed = (await readJsonObject(c.req.raw)).sealed_invite_b64;
  const bytes = typeof sealed === "string" ? decodeB64(sealed, 1, SEALED_INVITE_MAX_BYTES) : null;
  if (typeof sealed !== "string" || bytes === null) throw Errors.badRequest();
  if (Buffer.from(bytes.subarray(0, PLAINTEXT_PREFIX.length)).toString("latin1").toLowerCase() === PLAINTEXT_PREFIX) {
    throw Errors.plaintextInvite();
  }

  housekeeping(db, now);
  db.transaction(() => {
    // The status condition makes a concurrent second approval (or one after a deny) change nothing.
    const updated = db.run(
      `UPDATE machine_pairings SET status = 'approved', sealed_invite = ?, decided_at = ?
        WHERE id = ? AND status = 'pending' AND created_at >= ?`,
      sealed, now, pairing.id, now - PAIRING_TTL_MS,
    );
    if (updated.changes === 0) {
      throw pairing.created_at < now - PAIRING_TTL_MS ? Errors.pairingExpired() : Errors.pairingNotPending();
    }
    db.run(
      `INSERT INTO machine_grants (from_machine_id, to_machine_id, pairing_id, created_at) VALUES (?, ?, ?, ?)
       ON CONFLICT (from_machine_id, to_machine_id) DO UPDATE SET pairing_id = excluded.pairing_id, created_at = excluded.created_at`,
      pairing.from_machine_id, pairing.to_machine_id, pairing.id, now,
    );
  });
  logMeta("pairing_approved", { device_id: auth.deviceId, pairing_id: pairing.id });
  return c.body(null, 204);
});

/** POST /v2/pairings/:id/deny — the target denies, or the requester cancels, a pending request. */
machinePairingRoutes.post("/:id/deny", requireAuth, requireDesktop, async (c) => {
  const auth = c.get("auth");
  const db = c.get("db");
  const now = c.get("now")();
  const pairing = accountPairing(db, auth.userId, c.req.param("id"));
  if (pairing === undefined) throw Errors.pairingNotFound();
  requireCallerMachine(db, auth.deviceId, [pairing.to_machine_id, pairing.from_machine_id]);

  housekeeping(db, now);
  const updated = db.run(
    `UPDATE machine_pairings SET status = 'denied', decided_at = ?
      WHERE id = ? AND status = 'pending' AND created_at >= ?`,
    now, pairing.id, now - PAIRING_TTL_MS,
  );
  if (updated.changes === 0) {
    const status = db.get<{ status: string }>("SELECT status FROM machine_pairings WHERE id = ?", pairing.id)?.status;
    if (status === "denied") return c.body(null, 204);
    throw Errors.pairingNotPending();
  }
  logMeta("pairing_denied", { device_id: auth.deviceId, pairing_id: pairing.id });
  return c.body(null, 204);
});

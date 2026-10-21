import { createHash, timingSafeEqual } from "node:crypto";
import { Hono } from "hono";
import { cors } from "hono/cors";
import type { AppEnv } from "../app.js";
import { requestIp } from "../auth/client-ip.js";
import { requireAuth } from "../auth/session.js";
import { jsonBodyLimit } from "../http/body-limit.js";
import { Errors, readJsonObject } from "../http/errors.js";
import { logMeta } from "../log.js";
import { unixSeconds } from "./encoding.js";
import { requireDesktop } from "./guard.js";
import { mintTicket, ticketClaims } from "./tickets.js";

/** Share ids are 8 characters of the Crockford-style base32 alphabet without i, l, o, u. */
const ID_PLAIN = /^[0-9a-hjkmnp-tv-z]{8}$/;
const ID_DASHED = /^[0-9a-hjkmnp-tv-z]{4}-[0-9a-hjkmnp-tv-z]{4}$/;
const ACCESS_RE = /^[A-Za-z0-9_-]{43}$/;
const VIEWER_RE = /^[A-Za-z0-9_-]{16,64}$/;

const MAX_LIVE_SHARES_PER_DEVICE = 20;
const LIFETIME_MS = { "15m": 15 * 60_000, "1h": 60 * 60_000, until_quit: 24 * 60 * 60_000 } as const;
const CLAIM_WINDOW_MS = 2 * 60_000;
/** A viewer ticket needs a host ticket (every 90 s) newer than this (R6). */
const HOST_ONLINE_WINDOW_MS = 150_000;

type Permission = "view" | "type";
type Lifetime = keyof typeof LIFETIME_MS;

interface ShareRow {
  id: string;
  user_id: string;
  device_id: string;
  slot: string;
  permission: Permission;
  lifetime: Lifetime;
  one_time: number;
  access_hash: string;
  created_at: number;
  expires_at: number;
  claim_until: number | null;
  viewer_hash: string | null;
  revoked_at: number | null;
  host_seen_at: number;
}

/** The 8-character id of `raw` (lower-cased, `xxxx-xxxx` accepted), or null when it is not an id. */
function parseShareId(raw: string): string | null {
  const id = raw.toLowerCase();
  if (ID_PLAIN.test(id)) return id;
  return ID_DASHED.test(id) ? id.replace("-", "") : null;
}

/** True when `err` is the primary-key violation of `shares.id` (a racing insert of the same id). */
export function isShareIdCollision(err: unknown): boolean {
  const code = (err as { code?: unknown } | null)?.code;
  return code === "SQLITE_CONSTRAINT_PRIMARYKEY" || String(err).includes("UNIQUE constraint failed: shares.id");
}

const sha256Hex = (value: string): string => createHash("sha256").update(value, "utf8").digest("hex");

function sameHash(a: string, b: string): boolean {
  const left = Buffer.from(a, "utf8");
  const right = Buffer.from(b, "utf8");
  return left.length === right.length && timingSafeEqual(left, right);
}

/** An owner route's share: the caller's own device's, else 404 (another device or account looks like no share). */
function ownShare(db: AppEnv["Variables"]["db"], deviceId: string, rawId: string): ShareRow {
  const id = parseShareId(rawId);
  const row = id === null ? undefined : db.get<ShareRow>("SELECT * FROM shares WHERE id = ?", id);
  if (row === undefined || row.device_id !== deviceId) throw Errors.shareNotFound();
  return row;
}

export const shareRoutes = new Hono<AppEnv>();

// The viewer page on shellx.pro calls only this route cross-origin; no other route answers CORS.
shareRoutes.use(
  "/:id/ticket",
  cors({
    origin: (origin, c) => (origin === c.get("config").shareAllowedOrigin ? origin : null),
    allowMethods: ["POST", "OPTIONS"],
    allowHeaders: ["Content-Type"],
    maxAge: 600,
  }),
);

/** POST /v2/shares {id, permission, lifetime, one_time?, access} — a new share on its own relay slot. */
shareRoutes.post("/", requireAuth, requireDesktop, jsonBodyLimit, async (c) => {
  const auth = c.get("auth");
  const db = c.get("db");
  if (!(await c.get("limiters").shareCreate.limit(auth.deviceId))) throw Errors.rateLimited();

  const body = await readJsonObject(c.req.raw);
  if ("secret" in body) throw Errors.badRequest(); // the fragment secret must never reach the API (R4)
  const oneTime = body.one_time ?? false;
  if (typeof oneTime !== "boolean") throw Errors.badRequest();
  if (body.permission !== "view" && body.permission !== "type") throw Errors.badRequest();
  if (body.lifetime !== "15m" && body.lifetime !== "1h" && body.lifetime !== "until_quit") throw Errors.badRequest();
  if (typeof body.access !== "string" || !ACCESS_RE.test(body.access)) throw Errors.badRequest();
  const id = typeof body.id === "string" ? parseShareId(body.id) : null;
  if (id === null) throw Errors.badRequest();

  // R5: the QR share is `type`, until_quit (24 h cap), claimed within 2 minutes by the first viewer.
  const permission: Permission = oneTime ? "type" : body.permission;
  const lifetime: Lifetime = oneTime ? "until_quit" : body.lifetime;
  const now = c.get("now")();
  const expiresAt = now + LIFETIME_MS[lifetime];
  const claimUntil = oneTime ? now + CLAIM_WINDOW_MS : null;
  const accessHash = sha256Hex(body.access);

  const { slot } = db.transaction(() => {
    const live = db.get<{ n: number }>(
      "SELECT COUNT(*) AS n FROM shares WHERE device_id = ? AND revoked_at IS NULL AND expires_at > ?", auth.deviceId, now,
    )!.n;
    if (live >= MAX_LIVE_SHARES_PER_DEVICE) throw Errors.shareLimit();
    // slot is UNIQUE: on a collision draw one fresh slot, then give up.
    let slot = c.get("shareSlot")();
    if (db.get("SELECT 1 FROM shares WHERE slot = ?", slot) !== undefined) {
      slot = c.get("shareSlot")();
      if (db.get("SELECT 1 FROM shares WHERE slot = ?", slot) !== undefined) throw new Error("could not allocate a share slot");
    }
    // Any state, any owner: the answer reveals only that the id is taken.
    if (db.get("SELECT 1 FROM shares WHERE id = ?", id) !== undefined) throw Errors.shareIdTaken();
    try {
      db.run(
        `INSERT INTO shares (id, user_id, device_id, slot, permission, lifetime, one_time, access_hash,
                             created_at, expires_at, claim_until, viewer_hash, revoked_at, host_seen_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?)`,
        id, auth.userId, auth.deviceId, slot, permission, lifetime, oneTime ? 1 : 0, accessHash, now, expiresAt, claimUntil, now,
      );
    } catch (err) {
      if (isShareIdCollision(err)) throw Errors.shareIdTaken();
      throw err;
    }
    return { slot };
  });

  logMeta("share_created", { device_id: auth.deviceId, permission, lifetime, one_time: oneTime });
  return c.json(
    { id, slot, expires_at_unix: unixSeconds(expiresAt), claim_until_unix: claimUntil === null ? null : unixSeconds(claimUntil) },
    201,
  );
});

/** GET /v2/shares — this device's shares that have not expired yet. */
shareRoutes.get("/", requireAuth, requireDesktop, (c) => {
  const rows = c.get("db").all<ShareRow>(
    "SELECT * FROM shares WHERE device_id = ? AND expires_at > ? ORDER BY created_at, id", c.get("auth").deviceId, c.get("now")(),
  );
  return c.json({
    shares: rows.map((r) => ({
      id: r.id, permission: r.permission, lifetime: r.lifetime, expires_at_unix: unixSeconds(r.expires_at), revoked: r.revoked_at !== null,
    })),
  });
});

/** DELETE /v2/shares/:id — revokes (idempotent). */
shareRoutes.delete("/:id", requireAuth, requireDesktop, (c) => {
  const db = c.get("db");
  const share = ownShare(db, c.get("auth").deviceId, c.req.param("id"));
  db.run("UPDATE shares SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL", c.get("now")(), share.id);
  logMeta("share_revoked", { device_id: share.device_id });
  return c.body(null, 204);
});

/** POST /v2/shares/:id/host-ticket — a `register` ticket on the share's slot; also the host's heartbeat. */
shareRoutes.post("/:id/host-ticket", requireAuth, requireDesktop, async (c) => {
  const auth = c.get("auth");
  const db = c.get("db");
  const config = c.get("config");
  if (config.relayHmacSecret === null) throw Errors.relayV2Unavailable();
  if (!(await c.get("limiters").ticketMint.limit(auth.deviceId))) throw Errors.rateLimited();

  const share = ownShare(db, auth.deviceId, c.req.param("id"));
  const now = c.get("now")();
  if (share.revoked_at !== null) throw Errors.shareRevoked();
  if (now >= share.expires_at) throw Errors.shareExpired();

  db.run("UPDATE shares SET host_seen_at = ? WHERE id = ?", now, share.id);
  const claims = ticketClaims("register", share.slot, config.relayIssuer, now);
  logMeta("share_host_ticket", { device_id: auth.deviceId });
  return c.json({ ticket: mintTicket(config.relayHmacSecret, claims), expires_at_unix: claims.expires_at_unix, relay_url: config.relayV2Url });
});

/** POST /v2/shares/:id/ticket {access, viewer} — anonymous: a `connect` ticket for whoever knows the access token. */
shareRoutes.post("/:id/ticket", jsonBodyLimit, async (c) => {
  const db = c.get("db");
  const config = c.get("config");
  if (config.relayHmacSecret === null) throw Errors.relayV2Unavailable();
  if (!(await c.get("limiters").shareTicket.limit(requestIp(c)))) throw Errors.rateLimited();

  const body = await readJsonObject(c.req.raw);
  if ("secret" in body) throw Errors.badRequest(); // checked before the id so a secret is always a 400
  const id = parseShareId(c.req.param("id"));
  if (id === null) throw Errors.shareNotFound();
  if (typeof body.access !== "string" || !ACCESS_RE.test(body.access)) throw Errors.badRequest();
  if (typeof body.viewer !== "string" || !VIEWER_RE.test(body.viewer)) throw Errors.badRequest();

  const now = c.get("now")();
  const accessHash = sha256Hex(body.access);
  const viewerHash = sha256Hex(body.viewer);
  const share = db.transaction(() => {
    const row = db.get<ShareRow>("SELECT * FROM shares WHERE id = ?", id);
    // A wrong access token answers like a missing share: nobody learns which ids exist.
    if (row === undefined || !sameHash(row.access_hash, accessHash)) throw Errors.shareNotFound();
    if (row.revoked_at !== null) throw Errors.shareRevoked();
    if (now >= row.expires_at) throw Errors.shareExpired();
    if (row.one_time === 1) {
      if (row.viewer_hash === null) {
        if (row.claim_until !== null && now >= row.claim_until) throw Errors.shareExpired();
      } else if (!sameHash(row.viewer_hash, viewerHash)) {
        throw Errors.shareUsed();
      }
    }
    if (now - row.host_seen_at > HOST_ONLINE_WINDOW_MS) throw Errors.hostOffline();
    if (row.one_time === 1 && row.viewer_hash === null) {
      const { changes } = db.run("UPDATE shares SET viewer_hash = ? WHERE id = ? AND viewer_hash IS NULL", viewerHash, id);
      if (changes !== 1) throw Errors.shareUsed();
    }
    return row;
  });

  const claims = ticketClaims("connect", share.slot, config.relayIssuer, now);
  logMeta("share_viewer_ticket", { permission: share.permission });
  return c.json({
    ticket: mintTicket(config.relayHmacSecret, claims), expires_at_unix: claims.expires_at_unix, relay_url: config.relayV2Url, slot: share.slot,
  });
});

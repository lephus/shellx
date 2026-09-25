import { Hono } from "hono";
import type { AppEnv } from "../app";
import { requireAuth } from "../auth/session";
import { hubFor } from "../hub/user-hub";
import { Errors, readJsonObject } from "../http/errors";
import { parseUuid } from "../protocol/uuid";

export const pairingRoutes = new Hono<AppEnv>();

/** POST /v1/pairings {mobile_id} — agent only; the record is informational (trust lives on the agent). */
pairingRoutes.post("/", requireAuth, async (c) => {
  const auth = c.get("auth");
  if (auth.kind !== "agent") throw Errors.agentOnly();
  const body = await readJsonObject(c.req.raw);
  const mobileId = parseUuid(body.mobile_id);
  if (mobileId === null) throw Errors.deviceNotFound();
  const db = c.env.DB;
  const mobile = await db
    .prepare("SELECT 1 FROM devices WHERE id = ? AND user_id = ? AND kind = 'mobile'")
    .bind(mobileId, auth.userId)
    .first();
  if (mobile === null) throw Errors.deviceNotFound();
  await db
    .prepare(
      `INSERT INTO pairings (agent_id, mobile_id, created_at) VALUES (?, ?, ?)
       ON CONFLICT (agent_id, mobile_id) DO UPDATE SET created_at = excluded.created_at`,
    )
    .bind(auth.deviceId, mobileId, c.get("now")())
    .run();
  return c.body(null, 201);
});

/**
 * DELETE /v1/pairings/:agent_id/:mobile_id — either party; idempotent; notifies the hub.
 *
 * Notify-before-delete: the relay may only ever *remove* trust, so a failure must never lose a
 * pairing_removed event. We first check the row exists (scoped to the caller's account, defence
 * in depth), then call the hub — which durably queues the event for the agent before doing
 * anything live (see UserHub.notifyPairingRemoved) — and only delete the D1 row once that
 * succeeds. If the hub call throws, the row is left in place so a retry finds it again and can
 * still deliver the event; the worst case is a duplicate delivery, which clients handle
 * idempotently, never a lost one.
 */
pairingRoutes.delete("/:agent_id/:mobile_id", requireAuth, async (c) => {
  const auth = c.get("auth");
  const agentId = parseUuid(c.req.param("agent_id"));
  const mobileId = parseUuid(c.req.param("mobile_id"));
  if (agentId === null || mobileId === null || (auth.deviceId !== agentId && auth.deviceId !== mobileId)) {
    throw Errors.forbidden();
  }
  const db = c.env.DB;
  const existing = await db
    .prepare(
      `SELECT 1 FROM pairings
        WHERE agent_id = ? AND mobile_id = ? AND agent_id IN (SELECT id FROM devices WHERE user_id = ?)`,
    )
    .bind(agentId, mobileId, auth.userId)
    .first();
  if (existing !== null) {
    await hubFor(c.env, auth.userId).notifyPairingRemoved(agentId, mobileId);
    await db
      .prepare(
        `DELETE FROM pairings
          WHERE agent_id = ? AND mobile_id = ? AND agent_id IN (SELECT id FROM devices WHERE user_id = ?)`,
      )
      .bind(agentId, mobileId, auth.userId)
      .run();
  }
  return c.body(null, 204);
});

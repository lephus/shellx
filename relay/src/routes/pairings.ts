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

/** DELETE /v1/pairings/:agent_id/:mobile_id — either party; idempotent; notifies the hub. */
pairingRoutes.delete("/:agent_id/:mobile_id", requireAuth, async (c) => {
  const auth = c.get("auth");
  const agentId = parseUuid(c.req.param("agent_id"));
  const mobileId = parseUuid(c.req.param("mobile_id"));
  if (agentId === null || mobileId === null || (auth.deviceId !== agentId && auth.deviceId !== mobileId)) {
    throw Errors.forbidden();
  }
  const result = await c.env.DB.prepare("DELETE FROM pairings WHERE agent_id = ? AND mobile_id = ?")
    .bind(agentId, mobileId)
    .run();
  if (result.meta.changes > 0) await hubFor(c.env, auth.userId).notifyPairingRemoved(agentId, mobileId);
  return c.body(null, 204);
});

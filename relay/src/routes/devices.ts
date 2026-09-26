import { Hono } from "hono";
import type { AppEnv } from "../app.js";
import type { DeviceKind, DevicePlatform } from "../auth/device.js";
import { requireAuth } from "../auth/session.js";
import { TOKEN_IDLE_TTL_MS } from "../auth/tokens.js";
import { hubFor } from "../hub/user-hub.js";

interface DeviceRow {
  id: string;
  kind: DeviceKind;
  name: string;
  platform: DevicePlatform;
  last_seen_at: number | null;
  paired_with_me: number;
}

export const deviceRoutes = new Hono<AppEnv>();

/**
 * GET /v1/devices — devices of the caller's account that are signed in (hold a non-expired token),
 * including the caller. Public keys are never returned.
 */
deviceRoutes.get("/", requireAuth, async (c) => {
  const auth = c.get("auth");
  const { results } = await c.env.DB.prepare(
    `SELECT d.id, d.kind, d.name, d.platform, d.last_seen_at,
            EXISTS (SELECT 1 FROM pairings p
                     WHERE (p.agent_id = d.id AND p.mobile_id = ?)
                        OR (p.mobile_id = d.id AND p.agent_id = ?)) AS paired_with_me
       FROM devices d
      WHERE d.user_id = ?
        AND EXISTS (SELECT 1 FROM tokens t WHERE t.device_id = d.id AND t.last_used_at >= ?)
      ORDER BY d.created_at, d.id`,
  )
    .bind(auth.deviceId, auth.deviceId, auth.userId, c.get("now")() - TOKEN_IDLE_TTL_MS)
    .all<DeviceRow>();
  const online = new Set(await hubFor(c.env, auth.userId).online());
  return c.json(
    results.map((d) => ({
      id: d.id,
      kind: d.kind,
      name: d.name,
      platform: d.platform,
      online: online.has(d.id),
      last_seen_at: d.last_seen_at,
      paired_with_me: d.paired_with_me === 1,
    })),
  );
});

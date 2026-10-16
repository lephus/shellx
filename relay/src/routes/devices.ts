import { Hono } from "hono";
import type { AppEnv } from "../app.js";
import type { DeviceKind, DevicePlatform } from "../auth/device.js";
import { requireAuth } from "../auth/session.js";
import { TOKEN_IDLE_TTL_MS } from "../auth/tokens.js";
import { jsonBodyLimit } from "../http/body-limit.js";
import { Errors, readJsonObject } from "../http/errors.js";
import { logMeta } from "../log.js";

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
  const results = c.get("db").all<DeviceRow>(
    `SELECT d.id, d.kind, d.name, d.platform, d.last_seen_at,
            EXISTS (SELECT 1 FROM pairings p
                     WHERE (p.agent_id = d.id AND p.mobile_id = ?)
                        OR (p.mobile_id = d.id AND p.agent_id = ?)) AS paired_with_me
       FROM devices d
      WHERE d.user_id = ?
        AND EXISTS (SELECT 1 FROM tokens t WHERE t.device_id = d.id AND t.last_used_at >= ?)
      ORDER BY d.created_at, d.id`,
    auth.deviceId,
    auth.deviceId,
    auth.userId,
    c.get("now")() - TOKEN_IDLE_TTL_MS,
  );
  const online = new Set(await c.get("hubs").forUser(auth.userId).online());
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

/** Longest FCM registration token accepted (real ones are ~160 characters). */
export const PUSH_TOKEN_MAX_CHARS = 4096;
const PUSH_PLATFORMS = ["android", "ios"] as const;

/**
 * PUT /v1/devices/me/push-token {token, platform} — phones only (push spec §5). Stores the phone's
 * FCM registration token; a token already held by another device (the same phone signed into
 * another account, or a reinstall) moves to the caller. 204. The token is never logged.
 */
deviceRoutes.put("/me/push-token", requireAuth, jsonBodyLimit, async (c) => {
  const auth = c.get("auth");
  if (auth.kind !== "mobile") throw Errors.mobileOnly();
  const body = await readJsonObject(c.req.raw);
  const token = body.token;
  const platform = body.platform;
  if (typeof token !== "string" || token.length === 0 || [...token].length > PUSH_TOKEN_MAX_CHARS) throw Errors.badRequest();
  if (typeof platform !== "string" || !(PUSH_PLATFORMS as readonly string[]).includes(platform)) throw Errors.badRequest();
  const db = c.get("db");
  const now = c.get("now")();
  db.transaction(() => {
    db.run("DELETE FROM push_tokens WHERE token = ? AND device_id != ?", token, auth.deviceId);
    db.run(
      `INSERT INTO push_tokens (device_id, token, platform, updated_at) VALUES (?, ?, ?, ?)
       ON CONFLICT (device_id) DO UPDATE SET token = excluded.token, platform = excluded.platform, updated_at = excluded.updated_at`,
      auth.deviceId, token, platform, now,
    );
  });
  logMeta("push_token_set", { device_id: auth.deviceId });
  return c.body(null, 204);
});

/** DELETE /v1/devices/me/push-token — removes the caller's push token, if any. 204, idempotent. */
deviceRoutes.delete("/me/push-token", requireAuth, async (c) => {
  const auth = c.get("auth");
  c.get("db").run("DELETE FROM push_tokens WHERE device_id = ?", auth.deviceId);
  return c.body(null, 204);
});

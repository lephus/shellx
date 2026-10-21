import { Hono } from "hono";
import type { AppEnv } from "../app.js";
import { requireAuth } from "../auth/session.js";
import { TOKEN_IDLE_TTL_MS } from "../auth/tokens.js";
import { jsonBodyLimit } from "../http/body-limit.js";
import { Errors, readJsonObject } from "../http/errors.js";
import { logMeta } from "../log.js";
import { decodeB64, fingerprint, newSlot, unixSeconds } from "./encoding.js";
import { accountMachine, ONLINE_WINDOW_MS, ownMachine, requireDesktop } from "./guard.js";

const OS_VERSION_RE = /^\d{1,4}(\.\d{1,6}){0,3}$/;
const APP_VERSION_RE = /^\d{1,6}\.\d{1,6}\.\d{1,6}$/;
const PLATFORMS = ["macos", "windows"] as const;

export const machineRoutes = new Hono<AppEnv>();

interface MachineInput {
  name: string;
  platform: (typeof PLATFORMS)[number];
  osVersion: string;
  appVersion: string;
  key: Uint8Array;
}

function parseMachine(body: Record<string, unknown>): MachineInput {
  const name = typeof body.name === "string" ? body.name.trim() : "";
  const platform = PLATFORMS.find((p) => p === body.platform);
  const osVersion = body.os_version;
  const appVersion = body.app_version;
  const key = decodeB64(body.noise_public_key_b64, 32, 32);
  if (
    name.length < 1 || name.length > 100 || platform === undefined ||
    typeof osVersion !== "string" || !OS_VERSION_RE.test(osVersion) ||
    typeof appVersion !== "string" || !APP_VERSION_RE.test(appVersion) ||
    key === null
  ) {
    throw Errors.invalidMachine();
  }
  return { name, platform, osVersion, appVersion, key };
}

/** POST /v2/machines — registers (or refreshes) the caller's one machine. */
machineRoutes.post("/", requireAuth, requireDesktop, jsonBodyLimit, async (c) => {
  const auth = c.get("auth");
  const db = c.get("db");
  const input = parseMachine(await readJsonObject(c.req.raw));
  const key = Buffer.from(input.key);
  const existing = ownMachine(db, auth.deviceId);

  if (existing === undefined) {
    const id = crypto.randomUUID();
    const slot = newSlot();
    db.run(
      `INSERT INTO machines (id, user_id, device_id, name, platform, os_version, app_version,
                             noise_public_key, fingerprint, slot, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      id, auth.userId, auth.deviceId, input.name, input.platform, input.osVersion, input.appVersion,
      key, fingerprint(input.key), slot, c.get("now")(),
    );
    logMeta("machine_registered", { device_id: auth.deviceId, machine_id: id });
    return c.json({ machine_id: id, slot }, 201);
  }

  db.transaction(() => {
    db.run("UPDATE machines SET name = ?, os_version = ?, app_version = ? WHERE id = ?",
      input.name, input.osVersion, input.appVersion, existing.id);
    if (!key.equals(existing.noise_public_key)) {
      // A new daemon identity must be approved again.
      db.run("UPDATE machines SET noise_public_key = ?, fingerprint = ? WHERE id = ?", key, fingerprint(input.key), existing.id);
      db.run("DELETE FROM machine_grants WHERE from_machine_id = ? OR to_machine_id = ?", existing.id, existing.id);
      db.run(
        `UPDATE machine_pairings SET status = 'expired'
          WHERE status = 'pending' AND (from_machine_id = ? OR to_machine_id = ?)`,
        existing.id, existing.id,
      );
    }
  });
  logMeta("machine_registered", { device_id: auth.deviceId, machine_id: existing.id });
  return c.json({ machine_id: existing.id, slot: existing.slot }, 200);
});

/** GET /v2/machines — machines of the account whose device is signed in, own included. */
machineRoutes.get("/", requireAuth, requireDesktop, async (c) => {
  const auth = c.get("auth");
  const now = c.get("now")();
  const rows = c.get("db").all<{
    id: string; name: string; platform: string; fingerprint: string; last_seen_at: number | null;
  }>(
    `SELECT m.id, m.name, m.platform, m.fingerprint, m.last_seen_at
       FROM machines m
      WHERE m.user_id = ?
        AND EXISTS (SELECT 1 FROM tokens t WHERE t.device_id = m.device_id AND t.last_used_at >= ?)
      ORDER BY m.created_at, m.id`,
    auth.userId,
    now - TOKEN_IDLE_TTL_MS,
  );
  return c.json({
    machines: rows.map((m) => ({
      machine_id: m.id,
      name: m.name,
      platform: m.platform,
      online: m.last_seen_at !== null && now - m.last_seen_at <= ONLINE_WINDOW_MS,
      last_seen_unix: m.last_seen_at === null ? null : unixSeconds(m.last_seen_at),
      fingerprint: m.fingerprint,
    })),
  });
});

/** POST /v2/machines/:id/heartbeat — owner only. */
machineRoutes.post("/:id/heartbeat", requireAuth, requireDesktop, async (c) => {
  const auth = c.get("auth");
  const db = c.get("db");
  const machine = accountMachine(db, auth.userId, c.req.param("id"));
  if (machine === undefined) throw Errors.machineNotFound();
  if (machine.device_id !== auth.deviceId) throw Errors.forbidden();
  db.run("UPDATE machines SET last_seen_at = ? WHERE id = ?", c.get("now")(), machine.id);
  return c.body(null, 204);
});

/** DELETE /v2/machines/:id — any desktop of the account; grants and pairings go by cascade. */
machineRoutes.delete("/:id", requireAuth, requireDesktop, async (c) => {
  const auth = c.get("auth");
  const db = c.get("db");
  const machine = accountMachine(db, auth.userId, c.req.param("id"));
  if (machine === undefined) throw Errors.machineNotFound();
  db.run("DELETE FROM machines WHERE id = ?", machine.id);
  logMeta("machine_deleted", { device_id: auth.deviceId, machine_id: machine.id });
  return c.body(null, 204);
});

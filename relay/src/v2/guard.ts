import type { MiddlewareHandler } from "hono";
import type { AppEnv } from "../app.js";
import type { Db } from "../db/db.js";
import { Errors } from "../http/errors.js";
import { parseUuid } from "../protocol/uuid.js";

/** A machine counts as online while its last heartbeat is at most this old (K1). */
export const ONLINE_WINDOW_MS = 90_000;

export interface MachineRow {
  id: string;
  user_id: string;
  device_id: string;
  name: string;
  platform: "macos" | "windows";
  os_version: string;
  app_version: string;
  noise_public_key: Buffer;
  fingerprint: string;
  slot: string;
  created_at: number;
  last_seen_at: number | null;
}

/** Only a native desktop token may use /v2 machine routes; run after `requireAuth`. */
export const requireDesktop: MiddlewareHandler<AppEnv> = async (c, next) => {
  if (c.get("auth").kind !== "desktop") throw Errors.desktopOnly();
  await next();
};

/** The machine registered by this device, if any. */
export function ownMachine(db: Db, deviceId: string): MachineRow | undefined {
  return db.get<MachineRow>("SELECT * FROM machines WHERE device_id = ?", deviceId);
}

/** A machine of this account by id (any input; undefined for a malformed id or another account's machine). */
export function accountMachine(db: Db, userId: string, machineId: unknown): MachineRow | undefined {
  const id = parseUuid(machineId);
  if (id === null) return undefined;
  return db.get<MachineRow>("SELECT * FROM machines WHERE id = ? AND user_id = ?", id, userId);
}

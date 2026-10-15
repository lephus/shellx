import type { DeviceKind } from "../auth/device.js";
import type { Db } from "../db/db.js";
import type { LiveDevice } from "../hub/registry.js";
import { compareVersions } from "../versions.js";

const DAY_MS = 24 * 60 * 60 * 1000;
/** Days in `signups_by_day`, today (UTC) included. */
export const SIGNUP_DAYS = 30;

/** Platforms listed for each kind even at zero, so the dashboard always shows both. */
const PLATFORMS: Record<DeviceKind, readonly string[]> = { agent: ["macos", "windows"], mobile: ["ios", "android"] };

export interface DeviceStats {
  /** Every device row of this kind, signed in or not. */
  total: number;
  /** Devices of this kind with a live WebSocket now; null when unknown. */
  online: number | null;
  by_platform: Record<string, number>;
}

export interface VersionCount {
  /** The x.y.z last reported; null for devices that never reported one (builds before the header). */
  version: string | null;
  count: number;
}

export interface AdminStats {
  generated_at: number;
  users: { total: number; new_24h: number; new_7d: number; new_30d: number; active_7d: number; active_30d: number };
  devices: Record<DeviceKind, DeviceStats>;
  versions: Record<DeviceKind, VersionCount[]>;
  signups_by_day: { day: string; count: number }[];
}

/** YYYY-MM-DD of a unix-millisecond time, in UTC. */
function utcDay(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

/** Newest version first; devices that never reported one last. */
function byVersionDesc(a: VersionCount, b: VersionCount): number {
  if (a.version === null || b.version === null) return (a.version === null ? 1 : 0) - (b.version === null ? 1 : 0);
  return compareVersions(b.version, a.version) || (a.version < b.version ? 1 : a.version > b.version ? -1 : 0);
}

/**
 * The admin dashboard's numbers. A handful of aggregate queries over the whole tables: cheap for
 * the relay's database size (one row per account and per device), and only run when the admin
 * opens or refreshes the dashboard. `live` comes from the hubs (null when not available).
 */
export function adminStats(db: Db, now: number, live: LiveDevice[] | null): AdminStats {
  const users = db.get<{ total: number; new_24h: number; new_7d: number; new_30d: number }>(
    `SELECT COUNT(*) AS total,
            COALESCE(SUM(created_at >= ?), 0) AS new_24h,
            COALESCE(SUM(created_at >= ?), 0) AS new_7d,
            COALESCE(SUM(created_at >= ?), 0) AS new_30d
       FROM users`,
    now - DAY_MS, now - 7 * DAY_MS, now - 30 * DAY_MS,
  )!;

  // Active = any device of the account seen on a socket (last_seen_at is written when a socket
  // closes), used its token (refreshed at most hourly by REST calls and upgrades), or online now.
  const onlineUsers = new Set((live ?? []).map((device) => device.userId));
  const activeSince = (since: number): number => {
    const ids = new Set(onlineUsers);
    const rows = db.all<{ user_id: string }>(
      `SELECT DISTINCT d.user_id FROM devices d
        WHERE d.last_seen_at >= ?
           OR EXISTS (SELECT 1 FROM tokens t WHERE t.device_id = d.id AND t.last_used_at >= ?)`,
      since, since,
    );
    for (const row of rows) ids.add(row.user_id);
    return ids.size;
  };

  const devices: Record<DeviceKind, DeviceStats> = {
    agent: { total: 0, online: live === null ? null : 0, by_platform: Object.fromEntries(PLATFORMS.agent.map((p) => [p, 0])) },
    mobile: { total: 0, online: live === null ? null : 0, by_platform: Object.fromEntries(PLATFORMS.mobile.map((p) => [p, 0])) },
  };
  for (const row of db.all<{ kind: DeviceKind; platform: string; count: number }>(
    "SELECT kind, platform, COUNT(*) AS count FROM devices GROUP BY kind, platform",
  )) {
    devices[row.kind].total += row.count;
    devices[row.kind].by_platform[row.platform] = row.count;
  }
  for (const device of live ?? []) devices[device.kind].online! += 1;

  const versions: Record<DeviceKind, VersionCount[]> = { agent: [], mobile: [] };
  for (const row of db.all<{ kind: DeviceKind; version: string | null; count: number }>(
    "SELECT kind, app_version AS version, COUNT(*) AS count FROM devices GROUP BY kind, app_version",
  )) {
    versions[row.kind].push({ version: row.version, count: row.count });
  }
  versions.agent.sort(byVersionDesc);
  versions.mobile.sort(byVersionDesc);

  const firstDay = Math.floor(now / DAY_MS) * DAY_MS - (SIGNUP_DAYS - 1) * DAY_MS;
  const signups = new Map(
    db.all<{ day: string; count: number }>(
      "SELECT date(created_at / 1000, 'unixepoch') AS day, COUNT(*) AS count FROM users WHERE created_at >= ? GROUP BY day",
      firstDay,
    ).map((row) => [row.day, row.count]),
  );
  const signupsByDay = Array.from({ length: SIGNUP_DAYS }, (_, i) => {
    const day = utcDay(firstDay + i * DAY_MS);
    return { day, count: signups.get(day) ?? 0 };
  });

  return {
    generated_at: now,
    users: { ...users, active_7d: activeSince(now - 7 * DAY_MS), active_30d: activeSince(now - 30 * DAY_MS) },
    devices,
    versions,
    signups_by_day: signupsByDay,
  };
}

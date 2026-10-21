import type { Config } from "./config.js";
import type { Db } from "./db/db.js";
import type { NativeLatest } from "./native-latest.js";
import type { Audience } from "./versions.js";

/** The settings the admin dashboard may override (rows of `app_settings`). */
export const MIN_VERSION_KEYS = ["min_agent", "min_mobile"] as const;
export type MinVersionKey = (typeof MIN_VERSION_KEYS)[number];

/** The admin's overrides currently stored; a key without a row follows the environment. */
export function minVersionOverrides(db: Db): Partial<Record<MinVersionKey, string>> {
  const rows = db.all<{ key: string; value: string }>("SELECT key, value FROM app_settings WHERE key IN ('min_agent', 'min_mobile')");
  return Object.fromEntries(rows.map((row) => [row.key, row.value]));
}

/** MIN_AGENT / MIN_MOBILE from the environment (deploy/relay.env). */
export function envMinVersions(config: Config): Record<MinVersionKey, string> {
  return { min_agent: config.minAgent, min_mobile: config.minMobile };
}

/**
 * The minimum versions GET /v1/version serves: the admin's override when there is one, else the
 * environment. Read on every request (one tiny indexed query), so a change made on the dashboard
 * reaches the apps' next check without a restart.
 */
export function minVersions(db: Db, config: Config): Record<MinVersionKey, string> {
  return { ...envMinVersions(config), ...minVersionOverrides(db) };
}

/** Sets (a version) or removes (null, back to the environment) one override. */
export function setMinVersionOverride(db: Db, key: MinVersionKey, value: string | null, now: number): void {
  if (value === null) {
    db.run("DELETE FROM app_settings WHERE key = ?", key);
  } else {
    db.run(
      `INSERT INTO app_settings (key, value, updated_at) VALUES (?, ?, ?)
       ON CONFLICT (key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`,
      key, value, now,
    );
  }
}

/**
 * Per-platform minimums of GET /v1/version (K6). Read from `app_settings` but deliberately not in
 * MIN_VERSION_KEYS: no admin route can set them yet (W3 A1b), so nobody can force an update to a
 * version that is not downloadable.
 */
export const PLATFORM_MIN_KEYS = ["min_macos", "min_windows", "min_flutter_macos14", "min_flutter_windows"] as const;
export type PlatformMinKey = (typeof PLATFORM_MIN_KEYS)[number];

function platformMin(db: Db, key: PlatformMinKey): string | undefined {
  return db.get<{ value: string }>("SELECT value FROM app_settings WHERE key = ?", key)?.value;
}

export interface VersionBody {
  min_agent: string;
  min_mobile: string;
  latest_agent: { version: string; mac_url: string; win_url: string };
}

/** The body of GET /v1/version for one audience (K6 table). `legacy` is exactly today's answer. */
export function versionAnswer(
  db: Db,
  config: Config,
  audience: Audience,
  latest: { macos: NativeLatest | null; windows: NativeLatest | null },
): VersionBody {
  const min = minVersions(db, config);
  let minAgent = min.min_agent;
  const legacyLatest = { version: config.latestAgentVersion, mac_url: config.macUrl, win_url: config.winUrl };
  let latestAgent = legacyLatest;
  switch (audience) {
    case "native-macos":
      minAgent = platformMin(db, "min_macos") ?? config.minMacos;
      if (latest.macos !== null) latestAgent = { version: latest.macos.version, mac_url: latest.macos.url, win_url: config.winUrl };
      break;
    case "native-windows":
      minAgent = platformMin(db, "min_windows") ?? config.minWindows;
      if (latest.windows !== null) latestAgent = { version: latest.windows.version, mac_url: config.macUrl, win_url: latest.windows.url };
      break;
    case "flutter-macos-14":
      minAgent = platformMin(db, "min_flutter_macos14") ?? min.min_agent;
      if (latest.macos !== null) latestAgent = { version: latest.macos.version, mac_url: latest.macos.url, win_url: config.winUrl };
      break;
    case "flutter-windows":
      minAgent = platformMin(db, "min_flutter_windows") ?? min.min_agent;
      break;
    case "legacy":
      break;
  }
  return { min_agent: minAgent, min_mobile: min.min_mobile, latest_agent: latestAgent };
}

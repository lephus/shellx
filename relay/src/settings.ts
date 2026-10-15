import type { Config } from "./config.js";
import type { Db } from "./db/db.js";

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

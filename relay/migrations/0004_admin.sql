-- Admin dashboard (admin.shellx.pro) and force update.
-- The x.y.z each device last reported in X-ShellX-Version; NULL = never reported (a build from
-- before the apps sent the header).
ALTER TABLE devices ADD COLUMN app_version TEXT;

-- Values the admin set from the dashboard. Keys: `min_agent`, `min_mobile` (each overrides MIN_AGENT /
-- MIN_MOBILE of relay.env in GET /v1/version while its row exists; deleting the row falls back to env).
CREATE TABLE app_settings (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

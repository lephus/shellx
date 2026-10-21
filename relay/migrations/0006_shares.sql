-- ShellX share links (L7): a browser viewer reaches a desktop through its own relay slot.
-- The API stores only sha256(access); the secret in the link fragment never reaches it.
CREATE TABLE shares (
  id           TEXT PRIMARY KEY,                                   -- 8 chars of 0123456789abcdefghjkmnpqrstvwxyz
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id    TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  slot         TEXT NOT NULL UNIQUE,                               -- b64url(16 random bytes), never a machines.slot
  permission   TEXT NOT NULL CHECK (permission IN ('view', 'type')),
  lifetime     TEXT NOT NULL CHECK (lifetime IN ('15m', '1h', 'until_quit')),
  one_time     INTEGER NOT NULL DEFAULT 0 CHECK (one_time IN (0, 1)),
  access_hash  TEXT NOT NULL,                                      -- sha256(access) hex
  created_at   INTEGER NOT NULL,                                   -- unix ms
  expires_at   INTEGER NOT NULL,
  claim_until  INTEGER,                                            -- one-time: first viewer ticket must come before this
  viewer_hash  TEXT,                                               -- one-time: sha256(viewer) of the bound viewer
  revoked_at   INTEGER,
  host_seen_at INTEGER NOT NULL                                    -- last host ticket (created_at until the first)
);
CREATE INDEX shares_device_id ON shares (device_id);

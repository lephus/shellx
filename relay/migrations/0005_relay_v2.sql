-- migrate: foreign_keys=off
-- ShellX relay v2 (native desktop): the `desktop` device kind and the machine / pairing tables.
-- devices: same columns as 0001+0004, CHECK now allows 'desktop' (SQLite cannot alter a CHECK: rebuild,
-- the 12-step procedure of sqlite.org/lang_altertable.html section 7; foreign keys are off for it).
CREATE TABLE devices_new (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind         TEXT NOT NULL CHECK (kind IN ('agent', 'mobile', 'desktop')),
  name         TEXT NOT NULL,
  platform     TEXT NOT NULL CHECK (platform IN ('macos', 'windows', 'ios', 'android')),
  public_key   BLOB NOT NULL,
  created_at   INTEGER NOT NULL,
  last_seen_at INTEGER,
  app_version  TEXT,
  UNIQUE (user_id, public_key)
);
INSERT INTO devices_new (id, user_id, kind, name, platform, public_key, created_at, last_seen_at, app_version)
  SELECT id, user_id, kind, name, platform, public_key, created_at, last_seen_at, app_version FROM devices;
DROP TABLE devices;
ALTER TABLE devices_new RENAME TO devices;

CREATE TABLE machines (
  id               TEXT PRIMARY KEY,                       -- UUIDv4
  user_id          TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id        TEXT NOT NULL UNIQUE REFERENCES devices(id) ON DELETE CASCADE,  -- one machine per device
  name             TEXT NOT NULL,
  platform         TEXT NOT NULL CHECK (platform IN ('macos','windows')),
  os_version       TEXT NOT NULL,
  app_version      TEXT NOT NULL,
  noise_public_key BLOB NOT NULL,                          -- 32 bytes
  fingerprint      TEXT NOT NULL,                          -- first 16 hex of SHA-256(noise_public_key)
  slot             TEXT NOT NULL UNIQUE,                   -- b64url(16 random bytes), 22 chars
  created_at       INTEGER NOT NULL,
  last_seen_at     INTEGER                                 -- last heartbeat, NULL = never
);
CREATE INDEX machines_user_id ON machines (user_id);

CREATE TABLE machine_pairings (
  id                    TEXT PRIMARY KEY,                  -- UUIDv4
  user_id               TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  from_machine_id       TEXT NOT NULL REFERENCES machines(id) ON DELETE CASCADE,  -- requester
  to_machine_id         TEXT NOT NULL REFERENCES machines(id) ON DELETE CASCADE,  -- target
  requester_x25519      BLOB NOT NULL,                     -- 32 bytes, for sealing only
  requester_fingerprint TEXT NOT NULL,                     -- copied from machines.fingerprint of from_machine_id
  code                  TEXT NOT NULL,                     -- 6 digits
  status                TEXT NOT NULL CHECK (status IN ('pending','approved','denied','expired')),
  sealed_invite         TEXT,                              -- client's b64 text, verbatim; NULL after purge
  created_at            INTEGER NOT NULL,
  decided_at            INTEGER,
  CHECK (from_machine_id != to_machine_id)
);
CREATE INDEX machine_pairings_to ON machine_pairings (to_machine_id, status);
CREATE INDEX machine_pairings_from ON machine_pairings (from_machine_id);

CREATE TABLE machine_grants (
  from_machine_id TEXT NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
  to_machine_id   TEXT NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
  pairing_id      TEXT NOT NULL,
  created_at      INTEGER NOT NULL,
  PRIMARY KEY (from_machine_id, to_machine_id)
);

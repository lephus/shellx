-- ShellX Link P2: a phone (a `mobile` device) asks a machine of the same account for access and, once
-- the Mac approves, may take link-lane tickets for that machine.
-- phone_pairings: one request. `client_key` is the phone's 32 byte Noise key; `proof` is the standard
-- base64 text of 32 bytes the phone derives from the pairing code. The relay never verifies the proof
-- (it does not know the code): it only relays it to the target Mac.
CREATE TABLE phone_pairings (
  id         TEXT PRIMARY KEY,                                                -- UUIDv4
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id  TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,          -- the phone
  machine_id TEXT NOT NULL REFERENCES machines(id) ON DELETE CASCADE,         -- the target
  client_key BLOB NOT NULL CHECK (length(client_key) = 32),
  proof      TEXT NOT NULL,
  status     TEXT NOT NULL CHECK (status IN ('pending','approved','denied','expired')),
  created_at INTEGER NOT NULL,
  decided_at INTEGER
);
CREATE INDEX phone_pairings_machine ON phone_pairings (machine_id, status);
CREATE INDEX phone_pairings_device ON phone_pairings (device_id);

-- phone_grants: an approved phone. Removed by the phone, by the machine, or with either row.
CREATE TABLE phone_grants (
  id         TEXT PRIMARY KEY,                                                -- UUIDv4
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id  TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  machine_id TEXT NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
  client_key BLOB NOT NULL CHECK (length(client_key) = 32),
  pairing_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  UNIQUE (device_id, machine_id)
);
CREATE INDEX phone_grants_machine ON phone_grants (machine_id);

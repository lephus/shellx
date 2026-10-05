-- FCM registration tokens of signed-in phones (push spec §5). One token per device; a token belongs
-- to one device only (registering it again elsewhere moves it). Removed on logout, with the device
-- (ON DELETE CASCADE) and when FCM reports it UNREGISTERED / INVALID_ARGUMENT.
CREATE TABLE push_tokens (
  device_id  TEXT PRIMARY KEY REFERENCES devices(id) ON DELETE CASCADE,
  token      TEXT NOT NULL,
  platform   TEXT NOT NULL CHECK (platform IN ('android', 'ios')),
  updated_at INTEGER NOT NULL
);

CREATE UNIQUE INDEX push_tokens_token ON push_tokens (token);

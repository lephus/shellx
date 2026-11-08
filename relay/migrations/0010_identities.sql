-- migrate: foreign_keys=off
-- Sign in with Google and Apple (S1 §6.1). users and phone_pairings are rebuilt to drop a NOT NULL (the
-- 12-step procedure of sqlite.org/lang_altertable.html section 7, as in 0005; foreign keys are off).
CREATE TABLE users_new (
  id                  TEXT PRIMARY KEY,
  email               TEXT NOT NULL UNIQUE,
  password_hash       TEXT,                        -- NULL: no password (Google account, or after the cut-over)
  password_changed_at INTEGER NOT NULL,
  created_at          INTEGER NOT NULL
);
INSERT INTO users_new (id, email, password_hash, password_changed_at, created_at)
  SELECT id, email, password_hash, password_changed_at, created_at FROM users;
DROP TABLE users;
ALTER TABLE users_new RENAME TO users;

CREATE TABLE identities (
  id                   TEXT PRIMARY KEY,                                       -- UUIDv4: the API's identity_id
  provider             TEXT NOT NULL CHECK (provider IN ('google', 'apple', 'test')),
  subject              TEXT NOT NULL,                                          -- the ID token's sub
  user_id              TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  email                TEXT NOT NULL,                                          -- normalized, as verified when linked
  is_private_email     INTEGER NOT NULL DEFAULT 0 CHECK (is_private_email IN (0, 1)),
  apple_refresh_token  TEXT,                                                   -- Apple only: revoked on removal / deletion
  apple_client_id      TEXT,                                                   -- the bundle id that refresh token belongs to
  linked_via_device_id TEXT REFERENCES devices(id) ON DELETE SET NULL,         -- the iPhone that linked this Apple ID by QR
  created_at           INTEGER NOT NULL,
  last_used_at         INTEGER NOT NULL,
  UNIQUE (provider, subject)
);
CREATE INDEX identities_user_id ON identities (user_id);
-- One Google (or test) sign-in per account (S1 §3); Apple IDs are not limited.
CREATE UNIQUE INDEX identities_one_primary ON identities (user_id) WHERE provider != 'apple';

-- How each token was minted (every older row was a password sign-in; the cut-over deletes those), and the
-- sign-in it came from: removing an Apple ID deletes its tokens.
ALTER TABLE tokens ADD COLUMN auth_method TEXT NOT NULL DEFAULT 'password'
  CHECK (auth_method IN ('password', 'google', 'apple', 'test'));
ALTER TABLE tokens ADD COLUMN identity_id TEXT REFERENCES identities(id) ON DELETE CASCADE;
CREATE INDEX tokens_identity_id ON tokens (identity_id);

-- One-time nonces of POST /v1/auth/nonce: only their SHA-256; a row goes when used or expired.
CREATE TABLE auth_nonces (
  nonce_hash BLOB PRIMARY KEY,
  expires_at INTEGER NOT NULL
);
CREATE INDEX auth_nonces_expires_at ON auth_nonces (expires_at);

-- An Apple sign-in that matched no account (S1 §6.4). The link token (only its SHA-256 here) lets that
-- iPhone ask a Mac, for 10 minutes, to link the Apple ID to the Mac's account.
CREATE TABLE apple_links (
  id                  TEXT PRIMARY KEY,
  token_hash          BLOB NOT NULL UNIQUE,
  subject             TEXT NOT NULL,
  email               TEXT NOT NULL,
  is_private_email    INTEGER NOT NULL CHECK (is_private_email IN (0, 1)),
  apple_client_id     TEXT NOT NULL,
  apple_refresh_token TEXT,
  device_name         TEXT NOT NULL,
  device_public_key   BLOB NOT NULL CHECK (length(device_public_key) = 32),
  created_at          INTEGER NOT NULL,
  expires_at          INTEGER NOT NULL,
  redeemed_at         INTEGER                                                  -- set when the approved session was handed out
);

CREATE TABLE phone_pairings_new (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id     TEXT REFERENCES devices(id) ON DELETE CASCADE,                -- NULL for an Apple link until approved
  machine_id    TEXT NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
  client_key    BLOB NOT NULL CHECK (length(client_key) = 32),
  proof         TEXT NOT NULL,
  status        TEXT NOT NULL CHECK (status IN ('pending','approved','denied','expired')),
  created_at    INTEGER NOT NULL,
  decided_at    INTEGER,
  apple_link_id TEXT REFERENCES apple_links(id) ON DELETE CASCADE,            -- set for a request made with a link token
  CHECK (device_id IS NOT NULL OR apple_link_id IS NOT NULL)
);
INSERT INTO phone_pairings_new (id, user_id, device_id, machine_id, client_key, proof, status, created_at, decided_at)
  SELECT id, user_id, device_id, machine_id, client_key, proof, status, created_at, decided_at FROM phone_pairings;
DROP TABLE phone_pairings;
ALTER TABLE phone_pairings_new RENAME TO phone_pairings;
CREATE INDEX phone_pairings_machine ON phone_pairings (machine_id, status);
CREATE INDEX phone_pairings_device ON phone_pairings (device_id);
CREATE INDEX phone_pairings_apple_link ON phone_pairings (apple_link_id);

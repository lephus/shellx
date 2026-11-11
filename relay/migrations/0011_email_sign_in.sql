-- migrate: foreign_keys=off
-- Sign in with an email code (spec 2026-11-10 §5). identities and tokens are rebuilt to widen a CHECK
-- (the 12-step procedure of sqlite.org/lang_altertable.html section 7, as in 0005 and 0010; foreign keys
-- are off). identities goes first: tokens.identity_id refers to it by name.
CREATE TABLE identities_new (
  id                   TEXT PRIMARY KEY,                                       -- UUIDv4: the API's identity_id
  provider             TEXT NOT NULL CHECK (provider IN ('google', 'apple', 'email', 'test')),
  subject              TEXT NOT NULL,                                          -- the ID token's sub; for email, the normalized address
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
INSERT INTO identities_new (id, provider, subject, user_id, email, is_private_email, apple_refresh_token, apple_client_id,
                            linked_via_device_id, created_at, last_used_at)
  SELECT id, provider, subject, user_id, email, is_private_email, apple_refresh_token, apple_client_id,
         linked_via_device_id, created_at, last_used_at FROM identities;
DROP TABLE identities;
ALTER TABLE identities_new RENAME TO identities;
CREATE INDEX identities_user_id ON identities (user_id);
-- One Google (or test) sign-in and one email sign-in per account; Apple IDs are not limited.
CREATE UNIQUE INDEX identities_one_primary ON identities (user_id) WHERE provider IN ('google', 'test');
CREATE UNIQUE INDEX identities_one_email ON identities (user_id) WHERE provider = 'email';

CREATE TABLE tokens_new (
  token_hash   BLOB PRIMARY KEY,
  device_id    TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  created_at   INTEGER NOT NULL,
  last_used_at INTEGER NOT NULL,
  auth_method  TEXT NOT NULL DEFAULT 'password' CHECK (auth_method IN ('password', 'google', 'apple', 'email', 'test')),
  identity_id  TEXT REFERENCES identities(id) ON DELETE CASCADE
);
INSERT INTO tokens_new (token_hash, device_id, created_at, last_used_at, auth_method, identity_id)
  SELECT token_hash, device_id, created_at, last_used_at, auth_method, identity_id FROM tokens;
DROP TABLE tokens;
ALTER TABLE tokens_new RENAME TO tokens;
CREATE INDEX tokens_device_id ON tokens (device_id);
CREATE INDEX tokens_identity_id ON tokens (identity_id);

-- One row per pending email code (POST /v1/auth/email/code). Neither the challenge id nor the code is
-- stored: only their SHA-256. A row goes when the code is used, expired, guessed wrong 5 times or replaced.
CREATE TABLE email_codes (
  id             TEXT PRIMARY KEY,                 -- UUIDv4, also the Idempotency-Key sent to Resend
  challenge_hash BLOB NOT NULL UNIQUE,             -- sha256(challenge_id)
  code_hash      BLOB NOT NULL,                    -- sha256(challenge_id || ':' || code)
  email          TEXT NOT NULL,                    -- normalized; lives at most 10 minutes
  attempts       INTEGER NOT NULL DEFAULT 0,
  created_at     INTEGER NOT NULL,
  expires_at     INTEGER NOT NULL
);
CREATE INDEX email_codes_email ON email_codes (email);
CREATE INDEX email_codes_expires_at ON email_codes (expires_at);

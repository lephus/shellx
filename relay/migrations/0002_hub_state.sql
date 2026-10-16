-- Durable pairing_removed tombstones of the in-process UserHub (VPS spec §4.2). Same columns as the
-- Durable Object's former `pending_pairing_removed` table plus `user_id`: at most one row per
-- (agent, mobile), holding the newest removed pairing_id.
CREATE TABLE pending_pairing_removed (
  user_id    TEXT NOT NULL,
  agent_id   TEXT NOT NULL,
  mobile_id  TEXT NOT NULL,
  pairing_id TEXT NOT NULL,
  UNIQUE (agent_id, mobile_id)
);

CREATE INDEX pending_pairing_removed_user_agent ON pending_pairing_removed (user_id, agent_id);

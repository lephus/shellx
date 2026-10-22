-- ShellX Link: a second relay slot per machine, so the Link daemon never replaces the cmux-tui
-- daemon on `slot` (a second `register` on one slot wins). Same format as `slot`:
-- b64url(16 random bytes), 22 chars, the last one carrying 2 bits only.
ALTER TABLE machines ADD COLUMN link_slot TEXT;

-- Plain SQL has no base64: build the 22 chars from random bytes. Each char takes a fresh byte
-- (two hex nibbles, 0..255) modulo 64; the 22nd takes one nibble modulo 4 times 16 (0, 16, 32 or 48).
WITH RECURSIVE gen(id, n, s) AS (
  SELECT id, 0, '' FROM machines
  UNION ALL
  SELECT id, n + 1,
    s || CASE WHEN n < 21
      THEN substr('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_',
             1 + (((instr('0123456789ABCDEF', substr(hex(randomblob(1)), 1, 1)) - 1) * 16
                 + (instr('0123456789ABCDEF', substr(hex(randomblob(1)), 2, 1)) - 1)) % 64), 1)
      ELSE substr('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_',
             1 + (instr('0123456789ABCDEF', substr(hex(randomblob(1)), 1, 1)) - 1) % 4 * 16, 1)
    END
  FROM gen WHERE n < 22
)
UPDATE machines SET link_slot = (SELECT s FROM gen WHERE gen.id = machines.id AND gen.n = 22);

CREATE UNIQUE INDEX machines_link_slot ON machines (link_slot);

-- ALTER cannot add NOT NULL without a default and a rebuild would touch every referencing table:
-- the same guarantee as triggers.
CREATE TRIGGER machines_link_slot_insert BEFORE INSERT ON machines WHEN NEW.link_slot IS NULL
BEGIN SELECT RAISE(ABORT, 'machines.link_slot must not be NULL'); END;
CREATE TRIGGER machines_link_slot_update BEFORE UPDATE OF link_slot ON machines WHEN NEW.link_slot IS NULL
BEGIN SELECT RAISE(ABORT, 'machines.link_slot must not be NULL'); END;

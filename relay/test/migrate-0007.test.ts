import { copyFileSync, mkdirSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { Db } from "../src/db/db.js";
import { migrate, MIGRATIONS_DIR } from "../src/db/migrate.js";
import { tempDir } from "./helpers.js";

describe("migration 0007", () => {
  it("gives every existing machine a unique 22 char link_slot and enforces it afterwards", () => {
    const oldDir = join(tempDir(), "v6");
    mkdirSync(oldDir);
    for (const name of readdirSync(MIGRATIONS_DIR)) {
      if (name < "0007") copyFileSync(join(MIGRATIONS_DIR, name), join(oldDir, name));
    }
    const db = Db.open(join(tempDir(), "v6.db"));
    try {
      migrate(db, oldDir);
      db.run("INSERT INTO users VALUES ('u1', 'a@example.com', 'x', 1, 1)");
      const ids = Array.from({ length: 50 }, (_, i) => `m${i}`);
      ids.forEach((id, i) => {
        db.run("INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at) VALUES (?, 'u1', 'desktop', 'Mac', 'macos', ?, 1)", `d${i}`, new Uint8Array([i]));
        db.run(
          `INSERT INTO machines (id, user_id, device_id, name, platform, os_version, app_version, noise_public_key, fingerprint, slot, created_at)
           VALUES (?, 'u1', ?, 'Mac', 'macos', '15.2', '1.0.0', ?, 'f', ?, 1)`,
          id, `d${i}`, new Uint8Array([i]), `slot${i}`,
        );
      });
      expect(migrate(db)).toEqual(["0007_link_slot.sql"]);
      const rows = db.all<{ link_slot: string }>("SELECT link_slot FROM machines");
      expect(rows).toHaveLength(50);
      for (const r of rows) expect(r.link_slot).toMatch(/^[A-Za-z0-9_-]{22}$/);
      expect(new Set(rows.map((r) => r.link_slot)).size).toBe(50);
      // the last char of a base64url 16 byte value carries 2 bits only, like Buffer.toString("base64url")
      for (const r of rows) expect(Buffer.from(r.link_slot, "base64url").toString("base64url")).toBe(r.link_slot);
      expect(() => db.run("UPDATE machines SET link_slot = NULL WHERE id = 'm0'")).toThrow();
      expect(() => db.run("UPDATE machines SET link_slot = ? WHERE id = 'm1'", rows[0]!.link_slot)).toThrow(/UNIQUE/);
      expect(db.all("PRAGMA foreign_key_check")).toEqual([]);
    } finally {
      db.close();
    }
  });
});

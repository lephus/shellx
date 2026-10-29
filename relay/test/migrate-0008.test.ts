import { copyFileSync, mkdirSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { Db } from "../src/db/db.js";
import { migrate, MIGRATIONS_DIR } from "../src/db/migrate.js";
import { tempDir } from "./helpers.js";

describe("migration 0008", () => {
  it("creates phone_pairings and phone_grants and cascades on device and machine deletion", () => {
    const oldDir = join(tempDir(), "v7");
    mkdirSync(oldDir);
    for (const name of readdirSync(MIGRATIONS_DIR)) {
      if (name < "0008") copyFileSync(join(MIGRATIONS_DIR, name), join(oldDir, name));
    }
    const db = Db.open(join(tempDir(), "v7.db"));
    try {
      migrate(db, oldDir);
      expect(migrate(db)).toEqual(["0008_phones.sql"]);
      db.run("INSERT INTO users VALUES ('u1', 'a@example.com', 'x', 1, 1)");
      const devices: [string, string, string, number][] = [["dm", "desktop", "macos", 1], ["dp1", "mobile", "ios", 2], ["dp2", "mobile", "ios", 3]];
      for (const [id, kind, platform, k] of devices) {
        db.run("INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at) VALUES (?, 'u1', ?, 'n', ?, ?, 1)", id, kind, platform, new Uint8Array([k]));
      }
      db.run(
        `INSERT INTO machines (id, user_id, device_id, name, platform, os_version, app_version, noise_public_key, fingerprint, slot, link_slot, created_at)
         VALUES ('m1', 'u1', 'dm', 'Mac', 'macos', '15', '1', ?, 'f', 's', 'ls', 1)`, new Uint8Array(32),
      );
      const key = new Uint8Array(32);
      for (const dev of ["dp1", "dp2"]) {
        db.run("INSERT INTO phone_pairings (id, user_id, device_id, machine_id, client_key, proof, status, created_at) VALUES (?, 'u1', ?, 'm1', ?, 'p', 'pending', 1)", `pp-${dev}`, dev, key);
        db.run("INSERT INTO phone_grants (id, user_id, device_id, machine_id, client_key, pairing_id, created_at) VALUES (?, 'u1', ?, 'm1', ?, ?, 1)", `g-${dev}`, dev, key, `pp-${dev}`);
      }
      expect(() => db.run("INSERT INTO phone_pairings (id, user_id, device_id, machine_id, client_key, proof, status, created_at) VALUES ('x', 'u1', 'dp1', 'm1', ?, 'p', 'bogus', 1)", key)).toThrow(/CHECK/);
      expect(() => db.run("INSERT INTO phone_grants (id, user_id, device_id, machine_id, client_key, pairing_id, created_at) VALUES ('y', 'u1', 'dp1', 'm1', ?, 'pp-dp1', 1)", key)).toThrow(/UNIQUE/);
      db.run("DELETE FROM devices WHERE id = 'dp1'");
      expect(db.all("SELECT id FROM phone_pairings")).toEqual([{ id: "pp-dp2" }]);
      expect(db.all("SELECT id FROM phone_grants")).toEqual([{ id: "g-dp2" }]);
      db.run("DELETE FROM machines WHERE id = 'm1'");
      expect(db.all("SELECT id FROM phone_pairings")).toEqual([]);
      expect(db.all("SELECT id FROM phone_grants")).toEqual([]);
      expect(db.all("PRAGMA foreign_key_check")).toEqual([]);
    } finally {
      db.close();
    }
  });
});

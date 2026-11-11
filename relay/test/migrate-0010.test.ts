import { copyFileSync, mkdirSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { authenticate } from "../src/auth/session.js";
import { hashToken } from "../src/auth/tokens.js";
import { Db } from "../src/db/db.js";
import { migrate, MIGRATIONS_DIR } from "../src/db/migrate.js";
import { tempDir } from "./helpers.js";

const MACHINE = `INSERT INTO machines (id, user_id, device_id, name, platform, os_version, app_version, noise_public_key, fingerprint, slot, link_slot, created_at)
                 VALUES ('m1', 'u1', 'dm', 'Mac', 'macos', '15', '1', ?, 'f', 's', 'ls', 1)`;
const DEVICE = "INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at) VALUES (?, 'u1', ?, 'n', ?, ?, 1)";

describe("migration 0010", () => {
  it("keeps every row and token, marks old tokens as password sign-ins and allows accounts without a password", async () => {
    const oldDir = join(tempDir(), "v9");
    mkdirSync(oldDir);
    for (const name of readdirSync(MIGRATIONS_DIR)) if (name < "0010") copyFileSync(join(MIGRATIONS_DIR, name), join(oldDir, name));
    const db = Db.open(join(tempDir(), "v9.db"));
    try {
      migrate(db, oldDir);
      const legacy = "legacy-token-0123456789abcdef0123456789abcdef";
      db.run("INSERT INTO users VALUES ('u1', 'a@example.com', 'x', 1, 1)");
      db.run(DEVICE, "dm", "desktop", "macos", new Uint8Array([1]));
      db.run(DEVICE, "dp", "mobile", "ios", new Uint8Array([2]));
      db.run("INSERT INTO tokens (token_hash, device_id, created_at, last_used_at) VALUES (?, 'dp', 1, ?)", await hashToken(legacy), Date.now());
      db.run(MACHINE, new Uint8Array(32));
      db.run("INSERT INTO phone_pairings (id, user_id, device_id, machine_id, client_key, proof, status, created_at) VALUES ('pp', 'u1', 'dp', 'm1', ?, 'p', 'pending', 1)", new Uint8Array(32));
      const counts = () => ["users", "devices", "tokens", "machines", "phone_pairings"].map((t) => db.get<{ n: number }>(`SELECT COUNT(*) AS n FROM ${t}`)!.n);
      const before = counts();

      expect(migrate(db)).toEqual(["0010_identities.sql", "0011_email_sign_in.sql"]);

      expect(counts()).toEqual(before);
      expect(db.get("SELECT auth_method, identity_id FROM tokens")).toEqual({ auth_method: "password", identity_id: null });
      expect(await authenticate(db, legacy, Date.now())).toMatchObject({ deviceId: "dp", kind: "mobile" });
      db.run("INSERT INTO users (id, email, password_hash, password_changed_at, created_at) VALUES ('u2', 'b@example.com', NULL, 1, 1)");
      expect(db.get("PRAGMA foreign_keys")).toEqual({ foreign_keys: 1 });
      expect(db.all("PRAGMA foreign_key_check")).toEqual([]);
    } finally {
      db.close();
    }
  });

  it("allows one Google sign-in per account, any number of Apple IDs, and cascades from identities, links and users", () => {
    const db = Db.open(join(tempDir(), "v10.db"));
    try {
      migrate(db);
      db.run("INSERT INTO users VALUES ('u1', 'a@example.com', NULL, 1, 1)");
      db.run(DEVICE, "dm", "desktop", "macos", new Uint8Array([1]));
      db.run(DEVICE, "dp", "mobile", "ios", new Uint8Array([2]));
      const identity = (id: string, provider: string, subject: string) =>
        db.run("INSERT INTO identities (id, provider, subject, user_id, email, created_at, last_used_at) VALUES (?, ?, ?, 'u1', 'a@example.com', 1, 1)", id, provider, subject);
      identity("i-g", "google", "g1");
      identity("i-a1", "apple", "a1");
      identity("i-a2", "apple", "a2");
      expect(() => identity("i-g2", "google", "g2")).toThrow(/UNIQUE/);
      expect(() => identity("i-t", "test", "t1")).toThrow(/UNIQUE/);
      expect(() => identity("i-x", "apple", "a1")).toThrow(/UNIQUE/);
      expect(() => identity("i-f", "facebook", "f1")).toThrow(/CHECK/);
      db.run("INSERT INTO tokens (token_hash, device_id, created_at, last_used_at, auth_method, identity_id) VALUES (x'aa', 'dp', 1, 1, 'apple', 'i-a1')");
      expect(() => db.run("INSERT INTO tokens (token_hash, device_id, created_at, last_used_at, auth_method) VALUES (x'bb', 'dp', 1, 1, 'magic')")).toThrow(/CHECK/);
      db.run("DELETE FROM identities WHERE id = 'i-a1'");
      expect(db.get("SELECT COUNT(*) AS n FROM tokens")).toEqual({ n: 0 });
      db.run("UPDATE identities SET linked_via_device_id = 'dp' WHERE id = 'i-a2'");

      db.run(MACHINE, new Uint8Array(32));
      db.run(`INSERT INTO apple_links (id, token_hash, subject, email, is_private_email, apple_client_id, device_name, device_public_key, created_at, expires_at)
              VALUES ('l1', x'cc', 'a9', 'h@privaterelay.appleid.com', 1, 'com.shellx.dev', 'iPhone', ?, 1, 600001)`, new Uint8Array(32));
      const pairing = (id: string, deviceId: string | null, linkId: string | null) =>
        db.run("INSERT INTO phone_pairings (id, user_id, device_id, machine_id, client_key, proof, status, created_at, apple_link_id) VALUES (?, 'u1', ?, 'm1', ?, 'p', 'pending', 1, ?)", id, deviceId, new Uint8Array(32), linkId);
      expect(() => pairing("p0", null, null)).toThrow(/CHECK/);
      pairing("p1", null, "l1");
      db.run("DELETE FROM apple_links WHERE id = 'l1'");
      expect(db.get("SELECT COUNT(*) AS n FROM phone_pairings")).toEqual({ n: 0 });

      db.run("DELETE FROM devices WHERE id = 'dp'");
      expect(db.get("SELECT linked_via_device_id FROM identities WHERE id = 'i-a2'")).toEqual({ linked_via_device_id: null });
      db.run("DELETE FROM users WHERE id = 'u1'");
      for (const t of ["identities", "devices", "machines"]) expect(db.get<{ n: number }>(`SELECT COUNT(*) AS n FROM ${t}`)!.n).toBe(0);
    } finally {
      db.close();
    }
  });
});

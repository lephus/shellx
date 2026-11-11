import { copyFileSync, mkdirSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { authenticate } from "../src/auth/session.js";
import { hashToken } from "../src/auth/tokens.js";
import { Db } from "../src/db/db.js";
import { migrate, MIGRATIONS_DIR } from "../src/db/migrate.js";
import { tempDir } from "./helpers.js";

const DEVICE = "INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at) VALUES (?, 'u1', ?, 'n', ?, ?, 1)";
const IDENTITY = "INSERT INTO identities (id, provider, subject, user_id, email, linked_via_device_id, created_at, last_used_at) VALUES (?, ?, ?, ?, ?, ?, 1, 1)";
const TOKEN = "INSERT INTO tokens (token_hash, device_id, created_at, last_used_at, auth_method, identity_id) VALUES (?, ?, 1, ?, ?, ?)";

describe("migration 0011", () => {
  it("keeps every identity and token of a populated 0010 database, with its method, identity and cascade", async () => {
    const oldDir = join(tempDir(), "v10");
    mkdirSync(oldDir);
    for (const name of readdirSync(MIGRATIONS_DIR)) if (name < "0011") copyFileSync(join(MIGRATIONS_DIR, name), join(oldDir, name));
    const db = Db.open(join(tempDir(), "v10.db"));
    try {
      migrate(db, oldDir);
      db.run("INSERT INTO users VALUES ('u1', 'a@example.com', NULL, 1, 1)");
      db.run(DEVICE, "dm", "desktop", "macos", new Uint8Array([1]));
      db.run(DEVICE, "dp", "mobile", "ios", new Uint8Array([2]));
      db.run(IDENTITY, "i-g", "google", "g1", "u1", "a@example.com", null);
      db.run(IDENTITY, "i-a", "apple", "a1", "u1", "h@privaterelay.appleid.com", "dp");
      const google = "google-session-0123456789abcdef0123456789ab";
      db.run(TOKEN, await hashToken(google), "dm", Date.now(), "google", "i-g");
      db.run(TOKEN, await hashToken("apple-session"), "dp", Date.now(), "apple", "i-a");
      db.run(TOKEN, await hashToken("legacy-session"), "dp", Date.now(), "password", null);
      const snapshot = () => [db.all("SELECT * FROM identities ORDER BY id"), db.all("SELECT * FROM tokens ORDER BY auth_method")];
      const before = snapshot();

      expect(migrate(db)).toEqual(["0011_email_sign_in.sql"]);

      expect(snapshot()).toEqual(before);
      expect(await authenticate(db, google, Date.now())).toMatchObject({ deviceId: "dm", kind: "desktop" });
      expect(db.get("PRAGMA foreign_keys")).toEqual({ foreign_keys: 1 });
      expect(db.all("PRAGMA foreign_key_check")).toEqual([]);
      const indexes = db.all<{ name: string }>(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name IN ('identities', 'tokens', 'email_codes') AND name NOT LIKE 'sqlite_%' ORDER BY name",
      );
      expect(indexes.map((r) => r.name)).toEqual([
        "email_codes_email", "email_codes_expires_at", "identities_one_email", "identities_one_primary", "identities_user_id",
        "tokens_device_id", "tokens_identity_id",
      ]);
      db.run("DELETE FROM identities WHERE id = 'i-a'");
      expect(db.all("SELECT auth_method FROM tokens ORDER BY auth_method")).toEqual([{ auth_method: "google" }, { auth_method: "password" }]);
    } finally {
      db.close();
    }
  });

  it("allows an email sign-in beside Google and Apple: one per account, one account per address, tokens of method email", () => {
    const db = Db.open(join(tempDir(), "v11.db"));
    try {
      migrate(db);
      db.run("INSERT INTO users VALUES ('u1', 'a@example.com', NULL, 1, 1)");
      db.run("INSERT INTO users VALUES ('u2', 'b@example.com', NULL, 1, 1)");
      db.run(DEVICE, "dm", "desktop", "macos", new Uint8Array([1]));
      const identity = (id: string, provider: string, subject: string, userId = "u1") => db.run(IDENTITY, id, provider, subject, userId, "a@example.com", null);
      identity("i-g", "google", "g1");
      identity("i-e", "email", "a@example.com");
      identity("i-a", "apple", "a1");
      expect(() => identity("i-e2", "email", "other@example.com")).toThrow(/UNIQUE/); // one email sign-in per account
      expect(() => identity("i-e3", "email", "a@example.com", "u2")).toThrow(/UNIQUE/); // one account per address
      expect(() => identity("i-t", "test", "t1")).toThrow(/UNIQUE/); // google and test share the one primary slot
      expect(() => identity("i-f", "facebook", "f1")).toThrow(/CHECK/);
      db.run(TOKEN, new Uint8Array([0xaa]), "dm", 1, "email", "i-e");
      expect(() => db.run(TOKEN, new Uint8Array([0xbb]), "dm", 1, "magic", null)).toThrow(/CHECK/);
      db.run("DELETE FROM identities WHERE id = 'i-e'");
      expect(db.get("SELECT COUNT(*) AS n FROM tokens")).toEqual({ n: 0 });
      const code = "INSERT INTO email_codes (id, challenge_hash, code_hash, email, created_at, expires_at) VALUES (?, ?, x'02', 'a@example.com', 1, 600001)";
      db.run(code, "c1", new Uint8Array([1]));
      expect(db.get("SELECT attempts FROM email_codes")).toEqual({ attempts: 0 });
      expect(() => db.run(code, "c2", new Uint8Array([1]))).toThrow(/UNIQUE/);
    } finally {
      db.close();
    }
  });
});

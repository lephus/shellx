import { copyFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { authenticate } from "../src/auth/session.js";
import { hashToken } from "../src/auth/tokens.js";
import { Db } from "../src/db/db.js";
import { migrate, MIGRATIONS_DIR } from "../src/db/migrate.js";
import { tempDir } from "./helpers.js";

const TABLES = ["users", "devices", "tokens", "pairings", "push_tokens", "app_settings"];

describe("migration 0005", () => {
  it("0005 keeps every v1 row and token, and devices accepts kind desktop", async () => {
    const oldDir = join(tempDir(), "v1");
    mkdirSync(oldDir);
    for (const name of ["0001_init.sql", "0002_hub_state.sql", "0003_push_tokens.sql", "0004_admin.sql"]) {
      copyFileSync(join(MIGRATIONS_DIR, name), join(oldDir, name));
    }
    const db = Db.open(join(tempDir(), "v1.db"));
    try {
      migrate(db, oldDir);
      const now = Date.now();
      const agentToken = "agent-token-0123456789abcdef0123456789abcdef";
      const mobileToken = "mobile-token-0123456789abcdef0123456789abcdef";
      db.run("INSERT INTO users VALUES ('u1', 'a@example.com', 'x', 1, 1)");
      db.run("INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at, app_version) VALUES ('da', 'u1', 'agent', 'Mac', 'macos', x'01', 1, '1.2.3')");
      db.run("INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at) VALUES ('dm', 'u1', 'mobile', 'Phone', 'ios', x'02', 1)");
      db.run("INSERT INTO tokens VALUES (?, 'da', 1, ?)", await hashToken(agentToken), now);
      db.run("INSERT INTO tokens VALUES (?, 'dm', 1, ?)", await hashToken(mobileToken), now);
      db.run("INSERT INTO pairings VALUES ('da', 'dm', 'p1', 1)");
      db.run("INSERT INTO push_tokens VALUES ('dm', 'fcm', 'ios', 1)");
      db.run("INSERT INTO app_settings (key, value, updated_at) VALUES ('min_agent', '1.0.0', 1)");
      const before = TABLES.map((t) => db.get<{ n: number }>(`SELECT COUNT(*) AS n FROM ${t}`)!.n);
      expect(before).toEqual([1, 2, 2, 1, 1, 1]);

      expect(migrate(db)).toEqual(["0005_relay_v2.sql"]);

      expect(TABLES.map((t) => db.get<{ n: number }>(`SELECT COUNT(*) AS n FROM ${t}`)!.n)).toEqual(before);
      expect(db.get<{ app_version: string }>("SELECT app_version FROM devices WHERE id = 'da'")).toEqual({ app_version: "1.2.3" });
      expect(await authenticate(db, agentToken, now)).toMatchObject({ kind: "agent", deviceId: "da" });
      expect(await authenticate(db, mobileToken, now)).toMatchObject({ kind: "mobile", deviceId: "dm" });
      expect(db.get("PRAGMA foreign_keys")).toEqual({ foreign_keys: 1 });
      expect(db.all("PRAGMA foreign_key_check")).toEqual([]);

      db.run("INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at) VALUES ('dd', 'u1', 'desktop', 'Mac', 'macos', x'03', 1)");
      expect(() =>
        db.run("INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at) VALUES ('dr', 'u1', 'robot', 'R', 'macos', x'04', 1)"),
      ).toThrow(/CHECK constraint failed/);

      db.run("DELETE FROM users");
      for (const t of ["tokens", "devices", "pairings"]) {
        expect(db.get<{ n: number }>(`SELECT COUNT(*) AS n FROM ${t}`)!.n).toBe(0);
      }
    } finally {
      db.close();
    }
  });
});

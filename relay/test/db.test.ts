import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import Database from "better-sqlite3";
import { describe, expect, it } from "vitest";
import { Db } from "../src/db/db.js";
import { migrate, MIGRATIONS_DIR } from "../src/db/migrate.js";
import { tempDir } from "./helpers.js";

function openFresh(name = "fresh.db", options = {}): Db {
  const db = Db.open(join(tempDir(), name), options);
  return db;
}

describe("Db", () => {
  it("opens with WAL, foreign keys and a 5 s busy timeout, creating missing directories", () => {
    const db = Db.open(join(tempDir(), "nested", "dir", "relay.db"));
    try {
      expect(db.get<{ journal_mode: string }>("PRAGMA journal_mode")).toEqual({ journal_mode: "wal" });
      expect(db.get<{ foreign_keys: number }>("PRAGMA foreign_keys")).toEqual({ foreign_keys: 1 });
      expect(db.get<{ timeout: number }>("PRAGMA busy_timeout")).toEqual({ timeout: 5000 });
    } finally {
      db.close();
    }
  });

  it("get/all/run bind parameters, store ArrayBuffers as BLOBs and report changes", () => {
    const db = openFresh();
    try {
      db.exec("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, blob BLOB)");
      const hash = new Uint8Array([1, 2, 3, 255]).buffer;
      expect(db.run("INSERT INTO t (name, blob) VALUES (?, ?)", "a", hash)).toEqual({ changes: 1 });
      db.run("INSERT INTO t (name, blob) VALUES (?, ?)", "b", new Uint8Array([9]));
      expect(db.get<{ name: string }>("SELECT name FROM t WHERE blob = ?", hash)).toEqual({ name: "a" });
      expect(db.get("SELECT name FROM t WHERE name = ?", "zzz")).toBeUndefined();
      expect(db.all<{ name: string }>("SELECT name FROM t ORDER BY id").map((r) => r.name)).toEqual(["a", "b"]);
      expect(db.run("DELETE FROM t WHERE name = ?", "nope")).toEqual({ changes: 0 });
    } finally {
      db.close();
    }
  });

  it("transaction commits on return and rolls back everything on throw", () => {
    const db = openFresh();
    try {
      db.exec("CREATE TABLE t (name TEXT)");
      expect(db.transaction(() => {
        db.run("INSERT INTO t VALUES ('kept')");
        return 42;
      })).toBe(42);
      expect(() =>
        db.transaction(() => {
          db.run("INSERT INTO t VALUES ('lost')");
          throw new Error("boom");
        }),
      ).toThrow("boom");
      expect(db.all<{ name: string }>("SELECT name FROM t").map((r) => r.name)).toEqual(["kept"]);
    } finally {
      db.close();
    }
  });

  it("enforces ON DELETE CASCADE (foreign keys are on)", () => {
    const db = openFresh();
    try {
      migrate(db);
      db.run("INSERT INTO users VALUES ('u1', 'a@example.com', 'x', 1, 1)");
      db.run("INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at) VALUES ('d1', 'u1', 'agent', 'n', 'macos', x'00', 1)");
      db.run("DELETE FROM users WHERE id = 'u1'");
      expect(db.get("SELECT 1 FROM devices WHERE id = 'd1'")).toBeUndefined();
    } finally {
      db.close();
    }
  });

  it("fails with SQLITE_BUSY after the busy timeout while another connection holds the write lock", () => {
    const path = join(tempDir(), "busy.db");
    const db = Db.open(path, { busyTimeoutMs: 50 });
    const other = new Database(path);
    try {
      db.exec("CREATE TABLE t (n INTEGER)");
      other.exec("BEGIN IMMEDIATE");
      const started = Date.now();
      expect(() => db.run("INSERT INTO t VALUES (1)")).toThrow(expect.objectContaining({ code: "SQLITE_BUSY" }));
      expect(Date.now() - started).toBeGreaterThanOrEqual(40);
      other.exec("ROLLBACK");
      expect(db.run("INSERT INTO t VALUES (1)")).toEqual({ changes: 1 });
    } finally {
      other.close();
      db.close();
    }
  });

  it("fileMustExist refuses to create a database (or its directory)", () => {
    for (const path of [join(tempDir(), "missing.db"), join(tempDir(), "no-dir", "relay.db")]) {
      expect(() => Db.open(path, { fileMustExist: true })).toThrow(expect.objectContaining({ code: "ENOENT" }));
    }
  });
});

describe("migrate", () => {
  it("applies every migration once, in file-name order, and records them", () => {
    const db = openFresh();
    try {
      expect(migrate(db)).toEqual(["0001_init.sql", "0002_hub_state.sql"]);
      const rows = db.all<{ name: string; applied_at: number }>("SELECT name, applied_at FROM schema_migrations ORDER BY name");
      expect(rows.map((r) => r.name)).toEqual(["0001_init.sql", "0002_hub_state.sql"]);
      for (const row of rows) expect(row.applied_at).toBeGreaterThan(1_700_000_000_000);
    } finally {
      db.close();
    }
  });

  it("skips migrations that already ran (a restart applies nothing and keeps the data)", () => {
    const path = join(tempDir(), "restart.db");
    const first = Db.open(path);
    migrate(first);
    first.run("INSERT INTO users VALUES ('u1', 'a@example.com', 'x', 1, 1)");
    first.close();

    const second = Db.open(path);
    try {
      expect(migrate(second)).toEqual([]);
      expect(second.get("SELECT id FROM users")).toEqual({ id: "u1" });
    } finally {
      second.close();
    }
  });

  it("applies only the new file when a migration is added later", () => {
    const dir = join(tempDir(), "migrations");
    mkdirSync(dir);
    writeFileSync(join(dir, "0001_a.sql"), "CREATE TABLE a (x INTEGER);");
    const db = openFresh();
    try {
      expect(migrate(db, dir)).toEqual(["0001_a.sql"]);
      writeFileSync(join(dir, "0002_b.sql"), "CREATE TABLE b (y INTEGER);");
      writeFileSync(join(dir, "README.txt"), "not a migration");
      expect(migrate(db, dir)).toEqual(["0002_b.sql"]);
      expect(migrate(db, dir)).toEqual([]);
    } finally {
      db.close();
    }
  });

  it("rolls back a failing migration completely and does not record it", () => {
    const dir = join(tempDir(), "broken");
    mkdirSync(dir);
    writeFileSync(join(dir, "0001_ok.sql"), "CREATE TABLE ok (x INTEGER);");
    writeFileSync(join(dir, "0002_broken.sql"), "CREATE TABLE half (x INTEGER); INSERT INTO nowhere VALUES (1);");
    const db = openFresh();
    try {
      expect(() => migrate(db, dir)).toThrow(expect.objectContaining({ code: "SQLITE_ERROR" }));
      expect(db.all<{ name: string }>("SELECT name FROM schema_migrations").map((r) => r.name)).toEqual(["0001_ok.sql"]);
      expect(db.get("SELECT 1 FROM sqlite_master WHERE name = 'half'")).toBeUndefined();
    } finally {
      db.close();
    }
  });

  it("0002 creates the tombstone table with user_id and a (user_id, agent_id) index", () => {
    const db = openFresh();
    try {
      migrate(db, MIGRATIONS_DIR);
      const columns = db.all<{ name: string; type: string; notnull: number }>("PRAGMA table_info(pending_pairing_removed)");
      expect(columns.map((c) => [c.name, c.type, c.notnull])).toEqual([
        ["user_id", "TEXT", 1],
        ["agent_id", "TEXT", 1],
        ["mobile_id", "TEXT", 1],
        ["pairing_id", "TEXT", 1],
      ]);
      const index = db.all<{ name: string }>("PRAGMA index_info(pending_pairing_removed_user_agent)");
      expect(index.map((c) => c.name)).toEqual(["user_id", "agent_id"]);
    } finally {
      db.close();
    }
  });
});

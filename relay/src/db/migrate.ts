import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type { Db } from "./db.js";

/** `relay/migrations/`: `src/db/` and `dist/db/` are both two levels below the package root. */
export const MIGRATIONS_DIR = fileURLToPath(new URL("../../migrations/", import.meta.url));

/**
 * First line of a migration that rebuilds a table other tables reference (SQLite cannot alter a
 * CHECK): foreign keys are off while it runs, then verified with `PRAGMA foreign_key_check`.
 */
export const FOREIGN_KEYS_OFF_DIRECTIVE = "-- migrate: foreign_keys=off";

/**
 * Applies every `*.sql` file of `dir` that is not yet recorded in `schema_migrations`, in file-name
 * order, each in its own transaction together with its bookkeeping row (spec §4.2). Returns the
 * names applied by this call. There are no down-migrations: fix a mistake with a new file.
 */
export function migrate(db: Db, dir: string = MIGRATIONS_DIR): string[] {
  db.exec("CREATE TABLE IF NOT EXISTS schema_migrations (name TEXT PRIMARY KEY, applied_at INTEGER NOT NULL)");
  const done = new Set(db.all<{ name: string }>("SELECT name FROM schema_migrations").map((row) => row.name));
  const pending = readdirSync(dir)
    .filter((name) => name.endsWith(".sql") && !done.has(name))
    .sort();
  for (const name of pending) {
    const sql = readFileSync(join(dir, name), "utf8");
    // A UTF-8 BOM and trailing whitespace on the directive line are tolerated.
    const firstLine = (sql.split(/\r?\n/, 1)[0] ?? "").replace(/^\uFEFF/, "").trimEnd();
    const foreignKeysOff = firstLine === FOREIGN_KEYS_OFF_DIRECTIVE;
    // With foreign keys on, DROP TABLE of a referenced table silently cascade-deletes its children.
    if (!foreignKeysOff && /drop\s+table/i.test(sql)) {
      throw new Error(`${name} contains DROP TABLE but lacks the "${FOREIGN_KEYS_OFF_DIRECTIVE}" first line`);
    }
    // The pragma is a no-op inside a transaction, so it is switched outside it and restored in `finally`.
    if (foreignKeysOff) db.exec("PRAGMA foreign_keys = OFF");
    try {
      db.transaction(() => {
        db.exec(sql);
        if (foreignKeysOff && db.all("PRAGMA foreign_key_check").length > 0) {
          throw new Error(`foreign_key_check failed for ${name}`);
        }
        db.run("INSERT INTO schema_migrations (name, applied_at) VALUES (?, ?)", name, Date.now());
      });
    } finally {
      if (foreignKeysOff) db.exec("PRAGMA foreign_keys = ON");
    }
  }
  return pending;
}

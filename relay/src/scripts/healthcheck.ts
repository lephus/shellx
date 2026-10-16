// Container healthcheck (compose: ["CMD", "node", "dist/scripts/healthcheck.js"], timeout 5 s).
// Healthy — exit 0, prints nothing — when both hold:
//   1. GET http://127.0.0.1:$PORT/v1/version answers 200 within 3 s;
//   2. the database at $DB_PATH opens read-only (never created) and answers SELECT 1.
// Otherwise exit 1 after one line on stderr naming each failed check and its error kind only, e.g.
// `healthcheck: version ECONNREFUSED; database SQLITE_CANTOPEN`. PORT and DB_PATH are read with
// the relay's own defaults (src/config.ts); nothing else in the environment is needed.
import { existsSync } from "node:fs";
import Database from "better-sqlite3";
import { DEFAULT_DB_PATH, DEFAULT_PORT } from "../config.js";
import { errorKind } from "../log.js";

const VERSION_TIMEOUT_MS = 3000;
/** Wait at most this long for another connection's lock; keeps the whole check under 5 s. */
const DB_BUSY_TIMEOUT_MS = 1000;

function setting(name: string, fallback: string): string {
  const value = process.env[name]?.trim();
  return value === undefined || value === "" ? fallback : value;
}

/** Null when /v1/version answered 200, else the error kind (`ECONNREFUSED`, `TimeoutError`, `HTTP_503`). */
async function checkVersion(port: string): Promise<string | null> {
  try {
    const response = await fetch(`http://127.0.0.1:${port}/v1/version`, { signal: AbortSignal.timeout(VERSION_TIMEOUT_MS) });
    await response.body?.cancel();
    return response.status === 200 ? null : `HTTP_${response.status}`;
  } catch (err) {
    // fetch() wraps network errors as `TypeError: fetch failed` with the system error as its cause.
    return errorKind((err as { cause?: unknown }).cause ?? err);
  }
}

/** Null when the database opened read-only and answered SELECT 1, else the error kind. */
function checkDatabase(path: string): string | null {
  if (!existsSync(path)) return "ENOENT";
  let sqlite: Database.Database | undefined;
  try {
    sqlite = new Database(path, { readonly: true, fileMustExist: true, timeout: DB_BUSY_TIMEOUT_MS });
    sqlite.prepare("SELECT 1").get();
    return null;
  } catch (err) {
    return errorKind(err);
  } finally {
    try {
      sqlite?.close();
    } catch {
      // nothing to release
    }
  }
}

const failures: string[] = [];
const version = await checkVersion(setting("PORT", String(DEFAULT_PORT)));
if (version !== null) failures.push(`version ${version}`);
const database = checkDatabase(setting("DB_PATH", DEFAULT_DB_PATH));
if (database !== null) failures.push(`database ${database}`);
if (failures.length > 0) console.error(`healthcheck: ${failures.join("; ")}`);
// Exit explicitly: fetch() may keep an idle keep-alive connection that would delay the exit.
process.exit(failures.length === 0 ? 0 : 1);

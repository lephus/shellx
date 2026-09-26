import { existsSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import Database from "better-sqlite3";

/** Values a statement parameter may take. ArrayBuffers (SHA-256 token hashes) are stored as BLOBs. */
export type SqlValue = string | number | bigint | null | Uint8Array | ArrayBuffer;

export interface RunResult {
  /** Rows inserted, updated or deleted by the statement. */
  changes: number;
}

export interface DbOptions {
  /** How long a statement waits for another connection's lock before failing with SQLITE_BUSY. */
  busyTimeoutMs?: number;
  /** Refuse to create the file (admin scripts must open the relay's existing database). */
  fileMustExist?: boolean;
}

/** Default `busy_timeout` (spec §4.2). */
export const BUSY_TIMEOUT_MS = 5000;

/**
 * The relay's only database access path: a thin, synchronous wrapper over one better-sqlite3
 * connection with WAL, foreign keys and a busy timeout. Prepared statements are cached per SQL
 * string. Replaces D1: `batch()` becomes `transaction()`, `first()` becomes `get()`.
 */
export class Db {
  private readonly statements = new Map<string, Database.Statement>();

  private constructor(private readonly sqlite: Database.Database) {}

  /** Opens (creating it and its directory unless `fileMustExist`) the database at `path`. */
  static open(path: string, options: DbOptions = {}): Db {
    if (options.fileMustExist) {
      if (!existsSync(path)) throw Object.assign(new Error("database file does not exist"), { code: "ENOENT" });
    } else {
      mkdirSync(dirname(path), { recursive: true });
    }
    const sqlite = new Database(path, {
      fileMustExist: options.fileMustExist ?? false,
      timeout: options.busyTimeoutMs ?? BUSY_TIMEOUT_MS,
    });
    try {
      sqlite.pragma("journal_mode = WAL");
      sqlite.pragma("foreign_keys = ON");
      sqlite.pragma(`busy_timeout = ${options.busyTimeoutMs ?? BUSY_TIMEOUT_MS}`);
    } catch (err) {
      sqlite.close();
      throw err;
    }
    return new Db(sqlite);
  }

  /** One row, or undefined when the query returns none. */
  get<T>(sql: string, ...params: SqlValue[]): T | undefined {
    return this.statement(sql).get(...params.map(toSqlite)) as T | undefined;
  }

  all<T>(sql: string, ...params: SqlValue[]): T[] {
    return this.statement(sql).all(...params.map(toSqlite)) as T[];
  }

  run(sql: string, ...params: SqlValue[]): RunResult {
    return { changes: this.statement(sql).run(...params.map(toSqlite)).changes };
  }

  /** Runs one or more statements without parameters (migrations). */
  exec(sql: string): void {
    this.sqlite.exec(sql);
  }

  /**
   * Runs `fn` in one transaction (BEGIN IMMEDIATE): committed if it returns, rolled back if it
   * throws. `fn` must be synchronous; nothing else can run on this connection in the meantime.
   */
  transaction<T>(fn: () => T): T {
    return this.sqlite.transaction(fn).immediate();
  }

  get isOpen(): boolean {
    return this.sqlite.open;
  }

  close(): void {
    if (this.sqlite.open) this.sqlite.close();
    this.statements.clear();
  }

  private statement(sql: string): Database.Statement {
    let statement = this.statements.get(sql);
    if (statement === undefined) {
      statement = this.sqlite.prepare(sql);
      this.statements.set(sql, statement);
    }
    return statement;
  }
}

function toSqlite(value: SqlValue): string | number | bigint | null | Buffer {
  if (value instanceof ArrayBuffer) return Buffer.from(value);
  if (value instanceof Uint8Array) return Buffer.from(value.buffer, value.byteOffset, value.byteLength);
  return value;
}

// Password cut-over (S1 §7 step 5), run once the apps sign in with Google and Apple. On the VPS, after
// setting PASSWORD_LOGIN=off and recreating the relay:
//
//   docker compose exec relay npm run -s password-cutover            # dry run: counts only
//   docker compose exec relay npm run -s password-cutover -- --yes   # removes every password and password session
//
// Removes every password hash and every token with auth_method = 'password'; Google, Apple and test
// sessions stay. Afterwards an account's email links straight to its Google sign-in. Cannot be undone
// except by restoring a backup. Prints counts only, never an email or a SQL statement.
import { pathToFileURL } from "node:url";
import { parseArgs } from "node:util";
import { DEFAULT_DB_PATH } from "../config.js";
import { Db } from "../db/db.js";
import { errorKind } from "../log.js";

export interface CutoverCounts {
  passwords: number;
  sessions: number;
}

/** Accounts that still have a password, and password sessions. */
export function passwordState(db: Db): CutoverCounts {
  return {
    passwords: db.get<{ n: number }>("SELECT COUNT(*) AS n FROM users WHERE password_hash IS NOT NULL")!.n,
    sessions: db.get<{ n: number }>("SELECT COUNT(*) AS n FROM tokens WHERE auth_method = 'password'")!.n,
  };
}

/** One transaction: clears the passwords and deletes the password sessions; returns how many of each. */
export function cutOverPasswords(db: Db): CutoverCounts {
  return db.transaction(() => ({
    passwords: db.run("UPDATE users SET password_hash = NULL WHERE password_hash IS NOT NULL").changes,
    sessions: db.run("DELETE FROM tokens WHERE auth_method = 'password'").changes,
  }));
}

function main(): number {
  if (process.env.PASSWORD_LOGIN?.trim() !== "off") {
    console.error("password-cutover: set PASSWORD_LOGIN=off and recreate the relay first");
    return 1;
  }
  const { values } = parseArgs({ options: { yes: { type: "boolean", default: false } } });
  let db: Db | undefined;
  try {
    db = Db.open(process.env.DB_PATH?.trim() || DEFAULT_DB_PATH, { fileMustExist: true });
    if (!values.yes) {
      const state = passwordState(db);
      console.log(`password-cutover: dry run: ${state.passwords} account(s) with a password, ${state.sessions} password session(s); run again with --yes to remove them.`);
    } else {
      const done = cutOverPasswords(db);
      console.log(`password-cutover: removed ${done.passwords} password(s) and ${done.sessions} password session(s).`);
    }
    return 0;
  } catch (err) {
    console.error(`password-cutover: database error (${errorKind(err)})`);
    return 1;
  } finally {
    db?.close();
  }
}

if (process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = main();
}

/** SQL string literal with single quotes doubled (e-mail local parts may contain `'`). */
export function sqlString(value: string): string {
  return `'${value.replaceAll("'", "''")}'`;
}

/**
 * Statements run by scripts/reset-password.ts through `wrangler d1 execute`.
 * The first statement reports whether the account exists (`n` = 0 or 1).
 */
export function buildResetSql(email: string, phc: string, now: number, revokeTokens: boolean): string {
  if (!Number.isSafeInteger(now)) throw new TypeError("now must be an integer (unix ms)");
  const e = sqlString(email);
  const statements = [
    `SELECT COUNT(*) AS n FROM users WHERE email = ${e};`,
    `UPDATE users SET password_hash = ${sqlString(phc)}, password_changed_at = ${now} WHERE email = ${e};`,
  ];
  if (revokeTokens) {
    statements.push(
      `DELETE FROM tokens WHERE device_id IN (SELECT id FROM devices WHERE user_id = (SELECT id FROM users WHERE email = ${e}));`,
    );
  }
  return statements.join("\n");
}

/**
 * What a `wrangler d1 execute --json` run of `buildResetSql` did, as far as its output tells:
 * - `reset`: the first statement counted exactly one account, so the UPDATE matched it;
 * - `no_account`: it counted none, so nothing changed;
 * - `unconfirmed`: the output is not JSON or not the expected shape. wrangler exited 0, so the
 *   UPDATE may well have run — never report "nothing changed" for this (final review M2).
 */
export type ResetOutcome = "reset" | "no_account" | "unconfirmed";

export function resetOutcomeFromWranglerJson(stdout: string): ResetOutcome {
  let parsed: unknown;
  try {
    parsed = JSON.parse(stdout);
  } catch {
    return "unconfirmed";
  }
  if (!Array.isArray(parsed)) return "unconfirmed";
  const first: unknown = parsed[0];
  if (typeof first !== "object" || first === null) return "unconfirmed";
  const rows = (first as { results?: unknown }).results;
  if (!Array.isArray(rows) || rows.length !== 1) return "unconfirmed";
  const row: unknown = rows[0];
  if (typeof row !== "object" || row === null) return "unconfirmed";
  const n = (row as { n?: unknown }).n;
  if (n === 1) return "reset";
  if (n === 0) return "no_account";
  return "unconfirmed";
}

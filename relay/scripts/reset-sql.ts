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
 * Parse wrangler d1 execute --json output and check if account exists.
 * Returns true if the first result set has exactly one row with n=1.
 */
export function accountExistsFromWranglerJson(stdout: string): boolean {
  try {
    const results = JSON.parse(stdout) as { results?: { n?: number }[] }[];
    return results[0]?.results?.[0]?.n === 1;
  } catch {
    return false;
  }
}

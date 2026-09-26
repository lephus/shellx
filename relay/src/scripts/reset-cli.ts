/**
 * Pure functions for reset-password CLI decision logic.
 * Extracted for testability (no I/O side effects).
 */

import { normalizeEmail } from "../auth/email.js";
import { errorKind } from "../log.js";
import type { ResetOutcome } from "./reset-db.js";

/** The database holds real accounts: an interactive confirmation is required unless `--yes`. */
export function needsConfirmation(yes: boolean): boolean {
  return !yes;
}

/**
 * Check if typed confirmation matches the expected email.
 * Normalizes both strings before comparison.
 */
export function confirmationMatches(expectedEmail: string, typedEmail: string): boolean {
  const normalized = normalizeEmail(typedEmail.trim());
  return normalized === expectedEmail;
}

/**
 * Determine which password source to use.
 * Order: argv '-' → stdin; argv value → argv (+warning); else env; else generate.
 */
export function choosePasswordSource(argv?: string, env?: string): "stdin" | "argv" | "env" | "generate" {
  if (argv === "-") return "stdin";
  if (argv) return "argv";
  if (env) return "env";
  return "generate";
}

/**
 * One-line message for a failed database step: the SQLite error code (e.g. `SQLITE_BUSY`) or
 * the error's class, never its message, which could quote SQL, the e-mail address or the hash.
 */
export function failureMessage(err: unknown): string {
  return `database error (${errorKind(err)})`;
}

export interface ResetReport {
  stdout: string[];
  stderr: string[];
  exitCode: number;
}

/**
 * What the script prints and its exit status for an outcome. A generated password is printed
 * only when the reset happened, never for `no_account`.
 */
export function resetReport(
  outcome: ResetOutcome,
  ctx: { email: string; target: string; generatedPassword?: string; revokeTokens: boolean },
): ResetReport {
  switch (outcome) {
    case "reset":
      return {
        stdout: [
          `Password reset for ${ctx.email} in ${ctx.target}.`,
          ...(ctx.generatedPassword === undefined ? [] : [`Temporary password: ${ctx.generatedPassword}`]),
          ...(ctx.revokeTokens ? ["All device tokens of this account were revoked."] : []),
        ],
        stderr: [],
        exitCode: 0,
      };
    case "no_account":
      return { stdout: [], stderr: [`No account with email ${ctx.email} in ${ctx.target}; nothing changed.`], exitCode: 1 };
  }
}

/**
 * Pure functions for reset-password CLI decision logic.
 * Extracted for testability (no I/O side effects).
 */

import { normalizeEmail } from "../src/auth/email";
import type { ResetOutcome } from "./reset-sql";

/**
 * Determine if confirmation is required for this environment.
 */
export function needsConfirmation(env: string, yes: boolean): boolean {
  return (env === "staging" || env === "production") && !yes;
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
 * One-line message for a failed `wrangler d1 execute` run. Never uses the error's own message:
 * `execFileSync` puts the whole argv there, and the argv carries the SQL with the e-mail address and
 * the new argon2 hash. Only the exit status, the signal, or a spawn error code (e.g. ENOENT) is kept.
 */
export function wranglerFailureMessage(err: unknown): string {
  const e = (typeof err === "object" && err !== null ? err : {}) as { status?: unknown; signal?: unknown; code?: unknown };
  if (typeof e.status === "number") return `wrangler d1 execute failed (exit ${e.status})`;
  if (typeof e.signal === "string" && /^SIG[A-Z0-9]+$/.test(e.signal)) return `wrangler d1 execute failed (${e.signal})`;
  if (typeof e.code === "string" && /^[A-Z0-9_]+$/.test(e.code)) return `wrangler d1 execute failed (${e.code})`;
  return "wrangler d1 execute failed";
}

/** Exit status when wrangler succeeded but its output could not confirm the reset. */
export const EXIT_UNCONFIRMED = 2;

export interface ResetReport {
  stdout: string[];
  stderr: string[];
  exitCode: number;
}

/**
 * What the script prints and its exit status for an outcome. A generated password is printed
 * whenever the UPDATE may have run — including `unconfirmed`, where dropping it could lock the user
 * out with a password nobody knows (final review M2) — and never for `no_account`.
 */
export function resetReport(
  outcome: ResetOutcome,
  ctx: { email: string; target: string; generatedPassword?: string; revokeTokens: boolean },
): ResetReport {
  const temporary = ctx.generatedPassword === undefined ? [] : [`Temporary password: ${ctx.generatedPassword}`];
  switch (outcome) {
    case "reset":
      return {
        stdout: [
          `Password reset for ${ctx.email} in ${ctx.target}.`,
          ...temporary,
          ...(ctx.revokeTokens ? ["All device tokens of this account were revoked."] : []),
        ],
        stderr: [],
        exitCode: 0,
      };
    case "no_account":
      return { stdout: [], stderr: [`No account with email ${ctx.email} in ${ctx.target}; nothing changed.`], exitCode: 1 };
    case "unconfirmed":
      return {
        stdout: temporary,
        stderr: [
          `Warning: could not confirm the result from wrangler's output. The password for ${ctx.email} in ${ctx.target} ` +
            `may have been changed${ctx.revokeTokens ? " and its device tokens revoked" : ""} — verify manually ` +
            "(e.g. log in with the new password).",
        ],
        exitCode: EXIT_UNCONFIRMED,
      };
  }
}

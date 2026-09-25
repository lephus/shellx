/**
 * Pure functions for reset-password CLI decision logic.
 * Extracted for testability (no I/O side effects).
 */

import { normalizeEmail } from "../src/auth/email";

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

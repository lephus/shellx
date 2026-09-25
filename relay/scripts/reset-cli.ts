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

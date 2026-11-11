/**
 * Sign-in providers (S1 §6.2). `test` is the test identity provider of test relays; it counts as an account's
 * Google sign-in. `email` is a sign-in by a code mailed to the address (spec 2026-11-10); its subject is the
 * normalized address.
 */
export type IdentityProvider = "google" | "apple" | "email" | "test";

export const GOOGLE_ISSUERS: readonly string[] = ["https://accounts.google.com", "accounts.google.com"];
export const APPLE_ISSUER = "https://appleid.apple.com";
export const TEST_IDP_AUDIENCE = "shellx-test-idp";
export const DEFAULT_APPLE_CLIENT_IDS: readonly string[] = ["com.shellx.prod", "com.shellx.dev"];

/** Google and test are an account's one primary sign-in; Apple IDs are unlimited; an email sign-in is not primary. */
export function isPrimaryProvider(provider: IdentityProvider): boolean {
  return provider === "google" || provider === "test";
}

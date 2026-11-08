/** Sign-in providers (S1 §6.2). `test` is the test identity provider of test relays; it counts as an account's Google sign-in. */
export type IdentityProvider = "google" | "apple" | "test";

export const GOOGLE_ISSUERS: readonly string[] = ["https://accounts.google.com", "accounts.google.com"];
export const APPLE_ISSUER = "https://appleid.apple.com";
export const TEST_IDP_AUDIENCE = "shellx-test-idp";
export const DEFAULT_APPLE_CLIENT_IDS: readonly string[] = ["com.shellx.prod", "com.shellx.dev"];

/** Google and test are an account's one primary sign-in; Apple IDs are unlimited. */
export function isPrimaryProvider(provider: IdentityProvider): boolean {
  return provider === "google" || provider === "test";
}

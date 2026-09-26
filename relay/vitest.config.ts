import { defineConfig } from "vitest/config";

/** Test files still written for the Workers pool; removed from this list as each is ported. */
const NOT_YET_PORTED = [
  "test/account.test.ts",
  "test/auth.test.ts",
  "test/devices-pairings.test.ts",
  "test/hub.test.ts",
  "test/limits.test.ts",
  "test/rate-limit.test.ts",
  "test/reset-password.test.ts",
];

export default defineConfig({
  test: {
    // Each test file runs in its own child process: better-sqlite3 and @node-rs/argon2 are native
    // addons, and the server tests spawn `src/server.ts` with signals.
    pool: "forks",
    include: ["test/**/*.test.ts"],
    exclude: NOT_YET_PORTED,
    testTimeout: 15_000,
    hookTimeout: 15_000,
  },
});

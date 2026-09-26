import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Each test file runs in its own child process: better-sqlite3 and @node-rs/argon2 are native
    // addons, and the server tests spawn `src/server.ts` with signals.
    pool: "forks",
    include: ["test/**/*.test.ts"],
    testTimeout: 15_000,
    hookTimeout: 15_000,
  },
});

import { applyD1Migrations } from "cloudflare:test";
import { env } from "cloudflare:workers";

// Idempotent: applyD1Migrations records applied migrations in the d1_migrations table.
await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);

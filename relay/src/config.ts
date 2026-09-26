/**
 * Relay configuration, read once from environment variables at startup (spec §4.2). Unknown
 * variables are ignored. A missing or malformed value throws `ConfigError` with a one-line message;
 * `src/server.ts` prints it and exits 1.
 */
export interface Config {
  /** Interface to listen on; `0.0.0.0` in the container, `127.0.0.1` for `npm run dev`. */
  host: string;
  /** 0 picks a free port (used by the process-level tests). */
  port: number;
  /** SQLite database file; its directory is created if missing. */
  dbPath: string;
  minAgent: string;
  minMobile: string;
  latestAgentVersion: string;
  macUrl: string;
  winUrl: string;
  /** Only the exact string "false" in RATE_LIMITS_ENABLED turns the limits off (local dev / E2E). */
  rateLimitsEnabled: boolean;
}

export class ConfigError extends Error {
  override name = "ConfigError";
}

export const REQUIRED_VARIABLES = ["MIN_AGENT", "MIN_MOBILE", "LATEST_AGENT_VERSION", "MAC_URL", "WIN_URL"] as const;

export const DEFAULT_PORT = 8080;
export const DEFAULT_HOST = "0.0.0.0";
export const DEFAULT_DB_PATH = "/data/relay.db";

export function loadConfig(env: Readonly<Record<string, string | undefined>>): Config {
  const value = (name: string): string | undefined => {
    const raw = env[name]?.trim();
    return raw === undefined || raw === "" ? undefined : raw;
  };
  const missing = REQUIRED_VARIABLES.filter((name) => value(name) === undefined);
  if (missing.length > 0) {
    throw new ConfigError(`missing required environment variable${missing.length > 1 ? "s" : ""}: ${missing.join(", ")}`);
  }
  const portText = value("PORT");
  const port = portText === undefined ? DEFAULT_PORT : Number(portText);
  if (!Number.isInteger(port) || port < 0 || port > 65535) {
    throw new ConfigError(`PORT must be an integer from 0 to 65535, got "${portText}"`);
  }
  return {
    host: value("HOST") ?? DEFAULT_HOST,
    port,
    dbPath: value("DB_PATH") ?? DEFAULT_DB_PATH,
    minAgent: value("MIN_AGENT")!,
    minMobile: value("MIN_MOBILE")!,
    latestAgentVersion: value("LATEST_AGENT_VERSION")!,
    macUrl: value("MAC_URL")!,
    winUrl: value("WIN_URL")!,
    rateLimitsEnabled: env.RATE_LIMITS_ENABLED !== "false",
  };
}

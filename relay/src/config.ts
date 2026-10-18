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
  /** MIN_WINDOWS / MIN_MACOS: minimum native version for `X-ShellX-Platform: windows|macos` (default 2.0.0). */
  minMacos: string;
  minWindows: string;
  /** Directory holding `latest-macos.json` / `latest-windows.json` (NATIVE_MANIFEST_DIR), mounted read-only. */
  nativeManifestDir: string;
  /** Only the exact string "false" in RATE_LIMITS_ENABLED turns the limits off (local dev / E2E). */
  rateLimitsEnabled: boolean;
  /**
   * Host name of the admin dashboard (ADMIN_HOST, lower-case, no port): requests whose Host is this
   * name are answered by the admin app alone (src/admin/app.ts), never by the relay's routes.
   */
  adminHost: string;
  /**
   * ADMIN_PASSWORD, or null when unset. Admin is enabled only when it has at least
   * ADMIN_PASSWORD_MIN_CHARS characters; a shorter one is not a startup error (the relay itself does
   * not need it), it only keeps admin disabled and is logged once as `admin_disabled`.
   */
  adminPassword: string | null;
  /**
   * CMUX_RELAY_HMAC_SECRET as raw UTF-8 bytes (read untrimmed, as cmux-relay does), or null when
   * unset or shorter than RELAY_HMAC_SECRET_MIN_BYTES; then v2 tickets answer 503, the relay keeps running.
   */
  relayHmacSecret: Uint8Array | null;
  relayV2DisabledReason: "missing_secret" | "short_secret" | null;
  /** Ticket issuer (CMUX_RELAY_ISSUER); must equal the issuer cmux-relay is started with. */
  relayIssuer: string;
  /** WebSocket URL of the v2 relay handed to clients (RELAY_V2_URL). */
  relayV2Url: string;
}

export class ConfigError extends Error {
  override name = "ConfigError";
}

export const REQUIRED_VARIABLES = ["MIN_AGENT", "MIN_MOBILE", "LATEST_AGENT_VERSION", "MAC_URL", "WIN_URL"] as const;

export const DEFAULT_PORT = 8080;
export const DEFAULT_HOST = "0.0.0.0";
export const DEFAULT_DB_PATH = "/data/relay.db";
export const DEFAULT_NATIVE_MIN = "2.0.0";
export const DEFAULT_NATIVE_MANIFEST_DIR = "/srv/downloads/desktop";
export const DEFAULT_ADMIN_HOST = "admin.shellx.pro";
export const DEFAULT_RELAY_ISSUER = "shellx-relay";
export const DEFAULT_RELAY_V2_URL = "wss://relay.shellx.pro/v2/relay";
export const RELAY_HMAC_SECRET_MIN_BYTES = 32;

/** Letters, digits, dots and hyphens: what a DNS name in a Host header looks like. */
const HOST_NAME_RE = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$/;

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
  const adminHost = (value("ADMIN_HOST") ?? DEFAULT_ADMIN_HOST).toLowerCase();
  if (!HOST_NAME_RE.test(adminHost)) {
    throw new ConfigError(`ADMIN_HOST must be a host name such as ${DEFAULT_ADMIN_HOST} (no scheme, port or path), got "${adminHost}"`);
  }
  const relayIssuer = value("CMUX_RELAY_ISSUER") ?? DEFAULT_RELAY_ISSUER;
  const issuerBytes = Buffer.byteLength(relayIssuer, "utf8");
  if (issuerBytes < 1 || issuerBytes > 256 || /[\r\n]/.test(relayIssuer)) {
    throw new ConfigError("CMUX_RELAY_ISSUER must be 1-256 bytes without line breaks");
  }
  const relayV2Url = value("RELAY_V2_URL") ?? DEFAULT_RELAY_V2_URL;
  let relayV2Protocol: string | null = null;
  try {
    relayV2Protocol = new URL(relayV2Url).protocol;
  } catch {
    // reported below
  }
  if (relayV2Protocol !== "ws:" && relayV2Protocol !== "wss:") {
    throw new ConfigError("RELAY_V2_URL must be a ws:// or wss:// URL");
  }
  const secretText = env.CMUX_RELAY_HMAC_SECRET;
  const secretBytes = secretText === undefined || secretText === "" ? null : new Uint8Array(Buffer.from(secretText, "utf8"));
  const relayHmacSecret = secretBytes !== null && secretBytes.length >= RELAY_HMAC_SECRET_MIN_BYTES ? secretBytes : null;
  const relayV2DisabledReason = relayHmacSecret !== null ? null : secretBytes === null ? "missing_secret" : "short_secret";
  return {
    host: value("HOST") ?? DEFAULT_HOST,
    port,
    dbPath: value("DB_PATH") ?? DEFAULT_DB_PATH,
    minAgent: value("MIN_AGENT")!,
    minMobile: value("MIN_MOBILE")!,
    latestAgentVersion: value("LATEST_AGENT_VERSION")!,
    macUrl: value("MAC_URL")!,
    winUrl: value("WIN_URL")!,
    minMacos: value("MIN_MACOS") ?? DEFAULT_NATIVE_MIN,
    minWindows: value("MIN_WINDOWS") ?? DEFAULT_NATIVE_MIN,
    nativeManifestDir: value("NATIVE_MANIFEST_DIR") ?? DEFAULT_NATIVE_MANIFEST_DIR,
    rateLimitsEnabled: env.RATE_LIMITS_ENABLED !== "false",
    adminHost,
    adminPassword: value("ADMIN_PASSWORD") ?? null,
    relayHmacSecret,
    relayV2DisabledReason,
    relayIssuer,
    relayV2Url,
  };
}

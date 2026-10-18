import { describe, expect, it } from "vitest";
import { ConfigError, loadConfig } from "../src/config.js";

const REQUIRED = {
  MIN_AGENT: "1.0.0",
  MIN_MOBILE: "1.0.1",
  LATEST_AGENT_VERSION: "1.2.0",
  MAC_URL: "https://download.shellx.pro/desktop/1.2.0/ShellX-1.2.0.dmg",
  WIN_URL: "https://download.shellx.pro/desktop/1.2.0/ShellX-Setup-1.2.0.exe",
};

describe("loadConfig", () => {
  it("reads the version variables and applies the defaults", () => {
    expect(loadConfig(REQUIRED)).toEqual({
      host: "0.0.0.0",
      port: 8080,
      dbPath: "/data/relay.db",
      minAgent: "1.0.0",
      minMobile: "1.0.1",
      latestAgentVersion: "1.2.0",
      macUrl: REQUIRED.MAC_URL,
      winUrl: REQUIRED.WIN_URL,
      minMacos: "2.0.0",
      minWindows: "2.0.0",
      nativeManifestDir: "/srv/downloads/desktop",
      rateLimitsEnabled: true,
      adminHost: "admin.shellx.pro",
      adminPassword: null,
      relayHmacSecret: null,
      relayV2DisabledReason: "missing_secret",
      relayIssuer: "shellx-relay",
      relayV2Url: "wss://relay.shellx.pro/v2/relay",
    });
  });

  it("reads HOST, PORT, DB_PATH and RATE_LIMITS_ENABLED", () => {
    const config = loadConfig({ ...REQUIRED, HOST: "127.0.0.1", PORT: "8787", DB_PATH: ".data/relay.db", RATE_LIMITS_ENABLED: "false" });
    expect(config).toMatchObject({ host: "127.0.0.1", port: 8787, dbPath: ".data/relay.db", rateLimitsEnabled: false });
  });

  it('keeps rate limits on for every value except the exact string "false"', () => {
    for (const flag of ["true", "", "False", "0", "no"]) {
      expect(loadConfig({ ...REQUIRED, RATE_LIMITS_ENABLED: flag }).rateLimitsEnabled).toBe(true);
    }
  });

  it("names every missing or blank required variable in one line", () => {
    const { MIN_AGENT: _a, MAC_URL: _m, ...rest } = REQUIRED;
    const run = () => loadConfig({ ...rest, WIN_URL: "   " });
    expect(run).toThrow(ConfigError);
    expect(run).toThrow("missing required environment variables: MIN_AGENT, MAC_URL, WIN_URL");
    expect(() => loadConfig({ ...REQUIRED, MIN_MOBILE: undefined })).toThrow("missing required environment variable: MIN_MOBILE");
  });

  it("reads ADMIN_HOST (lower-cased) and ADMIN_PASSWORD; a short password is not a startup error", () => {
    expect(loadConfig({ ...REQUIRED, ADMIN_HOST: "Admin.Example.COM", ADMIN_PASSWORD: "0123456789abcdef" })).toMatchObject({
      adminHost: "admin.example.com",
      adminPassword: "0123456789abcdef",
    });
    // admin stays disabled (src/admin/app.ts adminStatus) and the relay starts as usual
    expect(loadConfig({ ...REQUIRED, ADMIN_PASSWORD: "short" }).adminPassword).toBe("short");
    expect(loadConfig({ ...REQUIRED, ADMIN_PASSWORD: "  " }).adminPassword).toBeNull();
  });

  it("refuses an ADMIN_HOST that is not a bare host name", () => {
    for (const host of ["https://admin.shellx.pro", "admin.shellx.pro:443", "admin.shellx.pro/", "admin shellx", "-admin.shellx.pro"]) {
      expect(() => loadConfig({ ...REQUIRED, ADMIN_HOST: host })).toThrow(ConfigError);
    }
    expect(loadConfig({ ...REQUIRED, ADMIN_HOST: "admin.localhost" }).adminHost).toBe("admin.localhost");
  });

  it("refuses a PORT that is not an integer from 0 to 65535 (0 picks a free port)", () => {
    for (const port of ["abc", "65536", "80.5", "-1"]) {
      expect(() => loadConfig({ ...REQUIRED, PORT: port })).toThrow(`PORT must be an integer from 0 to 65535, got "${port}"`);
    }
    expect(loadConfig({ ...REQUIRED, PORT: "0" }).port).toBe(0);
  });

  describe("relay v2", () => {
    const SECRET = "0123456789abcdef0123456789abcdef";
    it("keeps the secret untrimmed (36 bytes with its spaces)", () => {
      const c = loadConfig({ ...REQUIRED, CMUX_RELAY_HMAC_SECRET: `  ${SECRET}  ` });
      expect(c.relayHmacSecret?.length).toBe(36);
      expect(new TextDecoder().decode(c.relayHmacSecret!)).toBe(`  ${SECRET}  `);
      expect(c.relayV2DisabledReason).toBeNull();
    });
    it("a 31-byte secret disables v2 without failing", () => {
      const c = loadConfig({ ...REQUIRED, CMUX_RELAY_HMAC_SECRET: SECRET.slice(1) });
      expect(c.relayHmacSecret).toBeNull();
      expect(c.relayV2DisabledReason).toBe("short_secret");
    });
    it("unset or empty secret is missing_secret", () => {
      expect(loadConfig(REQUIRED).relayV2DisabledReason).toBe("missing_secret");
      expect(loadConfig({ ...REQUIRED, CMUX_RELAY_HMAC_SECRET: "" }).relayV2DisabledReason).toBe("missing_secret");
    });
    it("validates CMUX_RELAY_ISSUER and RELAY_V2_URL", () => {
      expect(loadConfig({ ...REQUIRED, CMUX_RELAY_ISSUER: "x" }).relayIssuer).toBe("x");
      expect(() => loadConfig({ ...REQUIRED, CMUX_RELAY_ISSUER: "a\nb" })).toThrow(ConfigError);
      expect(() => loadConfig({ ...REQUIRED, CMUX_RELAY_ISSUER: "a".repeat(257) })).toThrow(ConfigError);
      expect(loadConfig({ ...REQUIRED, RELAY_V2_URL: "ws://127.0.0.1:1/v1/relay" }).relayV2Url).toBe("ws://127.0.0.1:1/v1/relay");
      expect(() => loadConfig({ ...REQUIRED, RELAY_V2_URL: "https://x" })).toThrow(ConfigError);
      expect(() => loadConfig({ ...REQUIRED, RELAY_V2_URL: "nonsense" })).toThrow(ConfigError);
    });
  });
});

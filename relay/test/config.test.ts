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
      rateLimitsEnabled: true,
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

  it("refuses a PORT that is not an integer from 0 to 65535 (0 picks a free port)", () => {
    for (const port of ["abc", "65536", "80.5", "-1"]) {
      expect(() => loadConfig({ ...REQUIRED, PORT: port })).toThrow(`PORT must be an integer from 0 to 65535, got "${port}"`);
    }
    expect(loadConfig({ ...REQUIRED, PORT: "0" }).port).toBe(0);
  });
});

import { describe, expect, it } from "vitest";
import { call, db, makeApp } from "./helpers.js";

describe("app skeleton", () => {
  it("GET /v1/version returns the configured versions", async () => {
    const res = await call(makeApp(), "GET", "/v1/version");
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      min_agent: "1.0.0",
      min_mobile: "1.0.0",
      latest_agent: {
        version: "1.0.0",
        mac_url: "https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg",
        win_url: "https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe",
      },
    });
  });

  it("unknown routes return the JSON error shape", async () => {
    const res = await call(makeApp(), "GET", "/v1/nope");
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: { code: "not_found", message: "Not found" } });
  });

  it("migrations created the four tables of 0001 and the tombstone table of 0002", () => {
    const names = db()
      .all<{ name: string }>(
        `SELECT name FROM sqlite_master WHERE type = 'table'
           AND name IN ('users','devices','tokens','pairings','pending_pairing_removed') ORDER BY name`,
      )
      .map((r) => r.name);
    expect(names).toEqual(["devices", "pairings", "pending_pairing_removed", "tokens", "users"]);
  });

  it("pairings carries the agent-generated pairing_id (TEXT NOT NULL) and keeps its (agent, mobile) key", () => {
    const columns = db().all<{ name: string; type: string; notnull: number; pk: number }>("PRAGMA table_info(pairings)");
    expect(columns.map((c) => [c.name, c.type, c.notnull, c.pk])).toEqual([
      ["agent_id", "TEXT", 1, 1],
      ["mobile_id", "TEXT", 1, 2],
      ["pairing_id", "TEXT", 1, 0],
      ["created_at", "INTEGER", 1, 0],
    ]);
  });
});

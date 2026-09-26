import { connect } from "node:net";
import { describe, expect, it } from "vitest";
import { call, db, makeApp, upgradeStatus, waitFor } from "./helpers.js";

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

  it("answers a non-WebSocket Upgrade request with 400 instead of hanging the socket, and a WebSocket upgrade with a bad token still gets 401", async () => {
    const app = makeApp();
    const relay = await app.ready;

    const response = await new Promise<string>((resolve, reject) => {
      const socket = connect(relay.port, "127.0.0.1", () => {
        socket.write(
          "GET /v1/version HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: Upgrade\r\nUpgrade: h2c\r\n\r\n",
        );
      });
      let data = "";
      const timer = setTimeout(() => {
        socket.destroy();
        reject(new Error(`no response within 2s (got: ${JSON.stringify(data)})`));
      }, 2000);
      socket.on("data", (chunk: Buffer) => {
        data += chunk.toString("utf8");
        clearTimeout(timer);
        socket.destroy();
        resolve(data);
      });
      socket.on("error", reject);
    });
    expect(response.startsWith("HTTP/1.1 400")).toBe(true);

    expect(await upgradeStatus(app, "not-a-real-token")).toBe(401);
  });

  const refusedUpgrades = [
    ["a non-WebSocket upgrade (400)", "GET /v1/version HTTP/1.1\r\nHost: x\r\nConnection: Upgrade\r\nUpgrade: h2c\r\n\r\n", "HTTP/1.1 400"],
    [
      "a WebSocket upgrade with a bad token (401)",
      "GET /v1/ws HTTP/1.1\r\nHost: x\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\n" +
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nAuthorization: Bearer bogus\r\n\r\n",
      "HTTP/1.1 401",
    ],
  ] as const;
  for (const [name, request, status] of refusedUpgrades) {
    it(`destroys the socket of ${name} once the linger expires, even if the client keeps its end open`, async () => {
      const relay = await makeApp({}, { refusedUpgradeLingerMs: 100 }).ready;
      const socket = connect({ port: relay.port, host: "127.0.0.1", allowHalfOpen: true });
      socket.on("error", () => {
        // the relay may reset it; only the server-side connection count matters here
      });
      socket.write(request);
      const answer = await new Promise<string>((resolve) => socket.once("data", (chunk: Buffer) => resolve(chunk.toString("latin1"))));
      expect(answer.startsWith(status)).toBe(true);
      const openConnections = () =>
        new Promise<number>((resolve, reject) => relay.server.getConnections((err, count) => (err ? reject(err) : resolve(count))));
      expect(await openConnections()).toBe(1); // our FIN is sent; the client never sends its own
      await waitFor(async () => ((await openConnections()) === 0 ? true : null), 2000);
      socket.destroy();
    });
  }
});

import { spawn } from "node:child_process";
import { existsSync, writeFileSync } from "node:fs";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { db, makeApp, onCleanup, tempDir } from "./helpers.js";

const RELAY_DIR = join(import.meta.dirname, "..");

interface Outcome {
  code: number | null;
  stdout: string;
  stderr: string;
}

/**
 * Runs the container healthcheck (`node dist/scripts/healthcheck.js` in the image; the TypeScript
 * source through tsx here) with exactly PORT and DB_PATH, plus PATH/HOME.
 */
function healthcheck(env: { PORT: string; DB_PATH: string }): Promise<Outcome> {
  const child = spawn(process.execPath, ["--import", "tsx", "src/scripts/healthcheck.ts"], {
    cwd: RELAY_DIR,
    env: { PATH: process.env.PATH ?? "", HOME: process.env.HOME ?? "", ...env },
  });
  let stdout = "";
  let stderr = "";
  child.stdout.on("data", (chunk: Buffer) => (stdout += chunk.toString("utf8")));
  child.stderr.on("data", (chunk: Buffer) => (stderr += chunk.toString("utf8")));
  return new Promise((resolve) => child.on("close", (code) => resolve({ code, stdout, stderr })));
}

/** A plain HTTP server on a free port that handles every request with `handler`. */
async function fakeRelay(handler: Parameters<typeof createServer>[1]): Promise<number> {
  const server: Server = createServer(handler);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  onCleanup(() => {
    server.closeAllConnections();
    return new Promise((resolve) => server.close(resolve));
  });
  return (server.address() as AddressInfo).port;
}

/** A port that nothing listens on. */
async function closedPort(): Promise<number> {
  const server = createServer();
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address() as AddressInfo;
  await new Promise((resolve) => server.close(resolve));
  return port;
}

describe("container healthcheck (src/scripts/healthcheck.ts)", () => {
  it("exits 0 and prints nothing when /v1/version answers 200 and the database answers SELECT 1", async () => {
    const relay = await makeApp().ready;
    db(); // the test relay's database exists
    const outcome = await healthcheck({ PORT: String(relay.port), DB_PATH: join(tempDir(), "relay.db") });
    expect(outcome).toEqual({ code: 0, stdout: "", stderr: "" });
  });

  it("exits 1 with one line when the database file is missing, and does not create it", async () => {
    const relay = await makeApp().ready;
    const missing = join(tempDir(), "missing.db");
    const outcome = await healthcheck({ PORT: String(relay.port), DB_PATH: missing });
    expect(outcome).toEqual({ code: 1, stdout: "", stderr: "healthcheck: database ENOENT\n" });
    expect(existsSync(missing)).toBe(false);
  });

  it("exits 1 when the database file is not a SQLite database, naming only the error kind", async () => {
    const relay = await makeApp().ready;
    const garbage = join(tempDir(), "garbage.db");
    writeFileSync(garbage, "this is not a database ".repeat(100));
    const outcome = await healthcheck({ PORT: String(relay.port), DB_PATH: garbage });
    expect(outcome).toEqual({ code: 1, stdout: "", stderr: "healthcheck: database SQLITE_NOTADB\n" });
  });

  it("exits 1 when nothing listens on PORT", async () => {
    db();
    const outcome = await healthcheck({ PORT: String(await closedPort()), DB_PATH: join(tempDir(), "relay.db") });
    expect(outcome).toEqual({ code: 1, stdout: "", stderr: "healthcheck: version ECONNREFUSED\n" });
  });

  it("exits 1 when /v1/version answers anything but 200", async () => {
    db();
    const port = await fakeRelay((_req, res) => {
      res.statusCode = 503;
      res.end("{}");
    });
    const outcome = await healthcheck({ PORT: String(port), DB_PATH: join(tempDir(), "relay.db") });
    expect(outcome).toEqual({ code: 1, stdout: "", stderr: "healthcheck: version HTTP_503\n" });
  });

  it("gives up on /v1/version after 3 s and exits 1", async () => {
    db();
    const port = await fakeRelay(() => {
      // never answers
    });
    const started = Date.now();
    const outcome = await healthcheck({ PORT: String(port), DB_PATH: join(tempDir(), "relay.db") });
    expect(outcome).toEqual({ code: 1, stdout: "", stderr: "healthcheck: version TimeoutError\n" });
    expect(Date.now() - started).toBeGreaterThanOrEqual(2900);
    expect(Date.now() - started).toBeLessThan(6000);
  });

  it("reports both failures on one line", async () => {
    const outcome = await healthcheck({ PORT: String(await closedPort()), DB_PATH: join(tempDir(), "missing.db") });
    expect(outcome).toEqual({ code: 1, stdout: "", stderr: "healthcheck: version ECONNREFUSED; database ENOENT\n" });
  });
});

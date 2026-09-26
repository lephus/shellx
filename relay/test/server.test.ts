import { type ChildProcess, spawn } from "node:child_process";
import { chmodSync, mkdirSync, writeFileSync } from "node:fs";
import { request as httpRequest } from "node:http";
import { createConnection } from "node:net";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { passwords, type PasswordHasher } from "../src/auth/password.js";
import { Db } from "../src/db/db.js";
import { HubRegistry } from "../src/hub/registry.js";
import { GOING_AWAY } from "../src/hub/user-hub.js";
import { pairingRemovedEvent } from "../src/protocol/frames.js";
import type { RunningRelay } from "../src/relay.js";
import {
  call, connect, db, deviceBody, hex, loginDevice, makeApp, newPairingId, onCleanup, pair, PASSWORD, randomEmail,
  registerAccount, tempDir, type TestApp, waitFor,
} from "./helpers.js";

const RELAY_DIR = join(import.meta.dirname, "..");

const VERSION_ENV = {
  MIN_AGENT: "1.0.0",
  MIN_MOBILE: "1.0.0",
  LATEST_AGENT_VERSION: "1.0.0",
  MAC_URL: "https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg",
  WIN_URL: "https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe",
};

interface Exit {
  code: number | null;
  stdout: string;
  stderr: string;
}

/** Starts `src/server.ts` (through tsx) with exactly `env` (plus PATH/HOME). */
function startServer(env: Record<string, string>): { child: ChildProcess; exit: Promise<Exit>; output: () => string } {
  const child = spawn(process.execPath, ["--import", "tsx", "src/server.ts"], {
    cwd: RELAY_DIR,
    env: { PATH: process.env.PATH ?? "", HOME: process.env.HOME ?? "", ...env },
  });
  let stdout = "";
  let stderr = "";
  child.stdout!.on("data", (chunk: Buffer) => (stdout += chunk.toString("utf8")));
  child.stderr!.on("data", (chunk: Buffer) => (stderr += chunk.toString("utf8")));
  const exit = new Promise<Exit>((resolve) => child.on("exit", (code) => resolve({ code, stdout, stderr })));
  return { child, exit, output: () => stdout };
}

async function waitForListening(output: () => string): Promise<number> {
  for (let i = 0; i < 200; i++) {
    const match = /"event":"relay_started","port":(\d+)/.exec(output());
    if (match) return Number(match[1]);
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error(`relay did not start: ${output()}`);
}

/** A TestApp for a relay started elsewhere: `call` and `connect` only need its port. */
function remote(port: number): TestApp {
  return { ready: Promise.resolve({ port, url: `http://127.0.0.1:${port}` } as RunningRelay) };
}

/** Sends `request` on a raw TCP connection, returns the status line of the answer and resets (RST) the connection. */
function statusThenReset(port: number, request: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const socket = createConnection(port, "127.0.0.1", () => socket.write(request));
    const timer = setTimeout(() => {
      socket.destroy();
      reject(new Error("no answer within 2s"));
    }, 2000);
    socket.once("data", (chunk: Buffer) => {
      clearTimeout(timer);
      socket.resetAndDestroy();
      resolve(chunk.toString("latin1").split("\r\n")[0]!);
    });
    socket.on("error", (err) => {
      clearTimeout(timer);
      reject(err);
    });
  });
}

const BAD_TOKEN_WEBSOCKET_UPGRADE =
  "GET /v1/ws HTTP/1.1\r\nHost: relay.shellx.pro\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n" +
  "Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nAuthorization: Bearer bogus\r\n\r\n";
const H2C_UPGRADE = "GET /v1/version HTTP/1.1\r\nHost: relay.shellx.pro\r\nConnection: Upgrade\r\nUpgrade: h2c\r\n\r\n";

describe("startup failures exit 1 with a one-line error", () => {
  it("a missing required variable", async () => {
    const { MIN_AGENT: _missing, ...rest } = VERSION_ENV;
    const { exit } = startServer({ ...rest, HOST: "127.0.0.1", PORT: "8799", DB_PATH: join(tempDir(), "relay.db") });
    const result = await exit;
    expect(result.code).toBe(1);
    expect(result.stderr).toBe("relay: missing required environment variable: MIN_AGENT\n");
    expect(result.stdout).not.toContain("relay_started");
  });

  it("a database path whose directory is a regular file (volume mounted wrong)", async () => {
    const file = join(tempDir(), "not-a-directory");
    writeFileSync(file, "x");
    const { exit } = startServer({ ...VERSION_ENV, HOST: "127.0.0.1", PORT: "0", DB_PATH: join(file, "relay.db") });
    const result = await exit;
    expect(result.code).toBe(1);
    expect(result.stderr).toMatch(/^relay: cannot open database at .*not-a-directory\/relay\.db \((ENOTDIR|EEXIST)\)\n$/);
  });

  it("a file that is not a SQLite database", async () => {
    const path = join(tempDir(), "garbage.db");
    writeFileSync(path, "this is not a database ".repeat(100));
    const { exit } = startServer({ ...VERSION_ENV, HOST: "127.0.0.1", PORT: "0", DB_PATH: path });
    const result = await exit;
    expect(result.code).toBe(1);
    expect(result.stderr).toBe(`relay: cannot open database at ${path} (SQLITE_NOTADB)\n`);
  });

  it.skipIf(process.getuid?.() === 0)("a read-only data directory (the container user cannot write the volume)", async () => {
    const dir = join(tempDir(), "readonly");
    mkdirSync(dir);
    chmodSync(dir, 0o555);
    try {
      const { exit } = startServer({ ...VERSION_ENV, HOST: "127.0.0.1", PORT: "0", DB_PATH: join(dir, "relay.db") });
      const result = await exit;
      expect(result.code).toBe(1);
      expect(result.stderr).toBe(`relay: cannot open database at ${join(dir, "relay.db")} (SQLITE_CANTOPEN)\n`);
    } finally {
      chmodSync(dir, 0o755);
    }
  });
});

describe("hostile clients", () => {
  it("survives a client that resets the connection right after a refused upgrade (401, then 400)", async () => {
    const server = startServer({ ...VERSION_ENV, HOST: "127.0.0.1", PORT: "0", DB_PATH: join(tempDir(), "relay.db") });
    onCleanup(() => server.child.kill("SIGKILL"));
    const port = await waitForListening(server.output);
    const settle = () => new Promise((resolve) => setTimeout(resolve, 200)); // the RST reaches the relay

    expect(await statusThenReset(port, BAD_TOKEN_WEBSOCKET_UPGRADE)).toBe("HTTP/1.1 401 Unauthorized");
    await settle();
    expect(server.child.exitCode).toBeNull();
    expect(await statusThenReset(port, H2C_UPGRADE)).toBe("HTTP/1.1 400 Bad Request");
    await settle();
    expect(server.child.exitCode).toBeNull();
    expect((await call(remote(port), "GET", "/v1/version")).status).toBe(200);

    server.child.kill("SIGTERM");
    const result = await server.exit;
    expect(result.code).toBe(0);
    expect(result.stderr).toBe("");
  });
});

describe("graceful shutdown (spec §4.3)", () => {
  it("on SIGTERM closes every socket with 1001, refuses new connections and exits 0", async () => {
    const dbPath = join(tempDir(), "relay.db");
    const server = startServer({ ...VERSION_ENV, HOST: "127.0.0.1", PORT: "0", DB_PATH: dbPath, RATE_LIMITS_ENABLED: "false" });
    const port = await waitForListening(server.output);
    const app = remote(port);
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const a = await connect(app, account.agent.token);
    const m = await connect(app, mobile.token);

    const started = Date.now();
    server.child.kill("SIGTERM");
    expect(await a.closed).toEqual({ code: GOING_AWAY, reason: "going away" });
    expect(await m.closed).toEqual({ code: GOING_AWAY, reason: "going away" });
    const result = await server.exit;
    expect(result.code).toBe(0);
    expect(Date.now() - started).toBeLessThan(10_000);
    expect(result.stdout).toContain('"event":"relay_stopping","signal":"SIGTERM"');
    expect(result.stdout).toContain('"event":"relay_stopped"');
    await expect(call(app, "GET", "/v1/version")).rejects.toThrow(/ECONNREFUSED/);

    // Everything committed before the signal is on disk.
    const reopened = Db.open(dbPath, { fileMustExist: true });
    try {
      expect(reopened.get("SELECT COUNT(*) AS n FROM devices")).toEqual({ n: 2 });
    } finally {
      reopened.close();
    }
  }, 30_000);

  it("ignores a second SIGTERM while it waits for an in-flight request, which still completes; exit 0", async () => {
    const server = startServer({ ...VERSION_ENV, HOST: "127.0.0.1", PORT: "0", DB_PATH: join(tempDir(), "relay.db"), RATE_LIMITS_ENABLED: "false" });
    onCleanup(() => server.child.kill("SIGKILL"));
    const port = await waitForListening(server.output);
    const body = Buffer.from(JSON.stringify({ email: randomEmail(), password: PASSWORD, device: deviceBody("agent") }), "utf8");

    // A registration whose body is still arriving: the relay is inside the route, awaiting the rest.
    // `Expect: 100-continue` makes the relay confirm it has dispatched the request before we go on.
    let sendRest: () => void = () => {};
    let dispatched: () => void = () => {};
    const inRoute = new Promise<void>((resolve) => (dispatched = resolve));
    const registered = new Promise<number>((resolve, reject) => {
      const req = httpRequest(
        {
          host: "127.0.0.1", port, method: "POST", path: "/v1/auth/register", agent: false,
          headers: { "Content-Type": "application/json", "Content-Length": String(body.length), Expect: "100-continue" },
        },
        (res) => {
          res.resume();
          res.on("end", () => resolve(res.statusCode ?? 0));
        },
      );
      req.on("error", reject);
      req.on("continue", () => {
        req.write(body.subarray(0, 10));
        sendRest = () => req.end(body.subarray(10));
        dispatched();
      });
      req.flushHeaders();
    });
    await inRoute;

    server.child.kill("SIGTERM");
    await waitFor(async () => (server.output().includes('"event":"relay_stopping"') ? true : null));
    server.child.kill("SIGTERM"); // mid-shutdown: must change nothing
    await new Promise((resolve) => setTimeout(resolve, 300));
    expect(server.child.exitCode).toBeNull(); // still waiting for the request
    expect(server.child.signalCode).toBeNull();

    sendRest();
    expect(await registered).toBe(201);
    const result = await server.exit;
    expect(result.code).toBe(0);
    expect(result.stdout.match(/"event":"relay_stopping"/g)).toHaveLength(1);
    expect(result.stdout.match(/"event":"relay_stopped"/g)).toHaveLength(1);
    expect(result.stderr).toBe("");
  });

  it("lets an in-flight REST call that touches the hub finish before the database closes", async () => {
    let releaseHash: () => void = () => {};
    const gate = new Promise<void>((resolve) => (releaseHash = resolve));
    let hashing: () => void = () => {};
    const hashStarted = new Promise<void>((resolve) => (hashing = resolve));
    const gatedPasswords: PasswordHasher = {
      hash: async (password) => {
        hashing();
        await gate;
        return passwords.hash(password);
      },
      verify: (password, phc) => passwords.verify(password, phc),
    };
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const relay = await makeApp({ passwords: gatedPasswords }).ready;
    const gated = remote(relay.port);
    const m = await connect(gated, mobile.token);

    const change = call(gated, "POST", "/v1/auth/password", { token: account.agent.token, body: { new_password: "brand new password" } });
    await hashStarted; // the request is now in flight, inside argon2
    const stopped = relay.shutdown(5000);
    expect(await m.closed).toEqual({ code: GOING_AWAY, reason: "going away" });
    let finished = false;
    void stopped.then(() => (finished = true));
    await new Promise((resolve) => setTimeout(resolve, 100));
    expect(finished).toBe(false); // still waiting for the request

    releaseHash();
    expect((await change).status).toBe(204); // completed normally, not a 500
    await stopped;
    const login = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: "brand new password", device: { kind: "mobile", name: "x", platform: "ios", public_key: mobile.publicKey } },
    });
    expect(login.status).toBe(200);
  });

  it("gives up waiting after the grace period and drops sockets that never answered", async () => {
    const hubs = new HubRegistry({ db: db() });
    const relay = await makeApp({ hubs }).ready;
    const app = remote(relay.port);
    const account = await registerAccount(app);
    const a = await connect(app, account.agent.token);
    a.ws.pause(); // never reads the close frame, so never answers it
    const started = Date.now();
    await relay.shutdown(300);
    expect(Date.now() - started).toBeLessThan(2000);
    a.ws.resume();
    expect((await a.closed).code).toBeGreaterThan(0);
  });
});

describe("restart", () => {
  it("keeps pairing_removed tombstones: a fresh relay on the same database replays them", async () => {
    const before = makeApp();
    const account = await registerAccount(before);
    const mobile = await loginDevice(before, account, "mobile");
    const pairingId = newPairingId();
    await pair(before, account.agent.token, mobile.deviceId, pairingId);
    expect((await call(before, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token })).status).toBe(204);

    // A new process: new database connection, new (empty) in-memory hubs.
    const reopened = Db.open(join(tempDir(), "relay.db"));
    const after = makeApp({ db: reopened, hubs: new HubRegistry({ db: reopened }) });
    const a = await connect(after, account.agent.token);
    expect(hex(await a.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, pairingId)));
    await a.expectSilence();
    a.close();
    await a.closed;
    await (await after.ready).shutdown(1000);
    reopened.close();
  });
});

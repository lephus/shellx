import { spawnSync } from "node:child_process";
import { join } from "node:path";
import { expect, it } from "vitest";
import { authenticate } from "../src/auth/session.js";
import { mintSmokeToken } from "../src/scripts/mint-smoke-token.js";
import { call, db, makeApp, registerMachine, tempDir } from "./helpers.js";

it("keeps one passwordless smoke account and device; each mint replaces the previous token (auth_method test)", async () => {
  const app = makeApp();
  const first = await mintSmokeToken(db(), Date.now());
  const second = await mintSmokeToken(db(), Date.now());
  expect(first).toMatch(/^[A-Za-z0-9_-]{43}$/);
  expect((await call(app, "GET", "/v1/devices", { token: first })).status).toBe(401);
  const me = (await authenticate(db(), second, Date.now()))!;
  expect(me.kind).toBe("desktop");
  expect(db().get("SELECT email, password_hash FROM users WHERE id = ?", me.userId)).toEqual({ email: "relay2-smoke@smoke.invalid", password_hash: null });
  expect(db().get("SELECT COUNT(*) AS n FROM devices WHERE user_id = ?", me.userId)).toEqual({ n: 1 });
  expect(db().get("SELECT auth_method FROM tokens WHERE device_id = ?", me.deviceId)).toEqual({ auth_method: "test" });
  await registerMachine(app, second);
});

it("the script prints the token and nothing else", () => {
  db();
  const r = spawnSync(process.execPath, ["--import", "tsx", "src/scripts/mint-smoke-token.ts"], {
    cwd: join(import.meta.dirname, ".."), encoding: "utf8", env: { ...process.env, DB_PATH: join(tempDir(), "relay.db") }, timeout: 20_000,
  });
  expect([r.status, r.stderr]).toEqual([0, ""]);
  expect(r.stdout).toMatch(/^[A-Za-z0-9_-]{43}\n$/);
});

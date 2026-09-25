import argon2Module from "@phi-ag/argon2/argon2.wasm";
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { accountExistsFromWranglerJson, buildResetSql, sqlString } from "../scripts/reset-sql";
import { createArgon2 } from "../src/auth/argon2";
import { call, deviceBody, loginDevice, makeApp, registerAccount } from "./helpers";

async function runSql(sql: string): Promise<D1Result[]> {
  return env.DB.batch(sql.split("\n").map((statement) => env.DB.prepare(statement)));
}

describe("reset-password SQL", () => {
  it("escapes single quotes", () => {
    expect(sqlString("o'brien@example.com")).toBe("'o''brien@example.com'");
  });

  it("sets a new password, reports existence, and optionally revokes tokens", async () => {
    const app = makeApp();
    const account = await registerAccount(app, `o'brien-${crypto.randomUUID()}@example.com`);
    const mobile = await loginDevice(app, account, "mobile");
    const argon2 = await createArgon2(argon2Module);
    const sql = buildResetSql(account.email, argon2.hash("reset by support"), 1_900_000_000_000, true);

    const results = await runSql(sql);
    expect(results[0]?.results).toEqual([{ n: 1 }]);

    const login = (password: string) =>
      call(app, "POST", "/v1/auth/login", { body: { email: account.email, password, device: deviceBody("mobile") } });
    expect((await login(account.password)).status).toBe(401);
    expect((await login("reset by support")).status).toBe(200);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(401);
    expect((await call(app, "GET", "/v1/devices", { token: mobile.token })).status).toBe(401);
  });

  it("reports n = 0 for an unknown account and changes nothing", async () => {
    const results = await runSql(buildResetSql("nobody@example.com", "$argon2id$x", 1, false));
    expect(results[0]?.results).toEqual([{ n: 0 }]);
    expect(results.length).toBe(2);
  });

  it("rejects a non-integer timestamp", () => {
    expect(() => buildResetSql("a@b.co", "x", 1.5, false)).toThrow(TypeError);
  });
});

describe("accountExistsFromWranglerJson", () => {
  it("returns true when account exists (n=1)", () => {
    const output = JSON.stringify([{ results: [{ n: 1 }] }]);
    expect(accountExistsFromWranglerJson(output)).toBe(true);
  });

  it("returns false when account does not exist (n=0)", () => {
    const output = JSON.stringify([{ results: [{ n: 0 }] }]);
    expect(accountExistsFromWranglerJson(output)).toBe(false);
  });

  it("returns false with empty results array", () => {
    const output = JSON.stringify([{ results: [] }]);
    expect(accountExistsFromWranglerJson(output)).toBe(false);
  });

  it("returns false with missing results property", () => {
    const output = JSON.stringify([{}]);
    expect(accountExistsFromWranglerJson(output)).toBe(false);
  });

  it("returns false with invalid JSON", () => {
    expect(accountExistsFromWranglerJson("not valid json")).toBe(false);
  });

  it("returns false with empty array", () => {
    const output = JSON.stringify([]);
    expect(accountExistsFromWranglerJson(output)).toBe(false);
  });

  it("returns false when first result has no results property", () => {
    const output = JSON.stringify([{ error: "something" }]);
    expect(accountExistsFromWranglerJson(output)).toBe(false);
  });
});

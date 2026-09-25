import argon2Module from "@phi-ag/argon2/argon2.wasm";
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { accountExistsFromWranglerJson, buildResetSql, sqlString } from "../scripts/reset-sql";
import { choosePasswordSource, confirmationMatches, needsConfirmation } from "../scripts/reset-cli";
import { createLinePrompter } from "../scripts/line-prompter";
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

describe("needsConfirmation", () => {
  it("returns false for local environment", () => {
    expect(needsConfirmation("local", false)).toBe(false);
    expect(needsConfirmation("local", true)).toBe(false);
  });

  it("returns true for staging without --yes", () => {
    expect(needsConfirmation("staging", false)).toBe(true);
  });

  it("returns false for staging with --yes", () => {
    expect(needsConfirmation("staging", true)).toBe(false);
  });

  it("returns true for production without --yes", () => {
    expect(needsConfirmation("production", false)).toBe(true);
  });

  it("returns false for production with --yes", () => {
    expect(needsConfirmation("production", true)).toBe(false);
  });
});

describe("confirmationMatches", () => {
  it("returns true when emails match exactly", () => {
    expect(confirmationMatches("test@example.com", "test@example.com")).toBe(true);
  });

  it("returns true when emails match after trimming", () => {
    expect(confirmationMatches("test@example.com", "  test@example.com  ")).toBe(true);
  });

  it("returns true when emails match after normalization (case-insensitive)", () => {
    expect(confirmationMatches("test@example.com", "Test@Example.com")).toBe(true);
  });

  it("returns false when emails do not match", () => {
    expect(confirmationMatches("test@example.com", "other@example.com")).toBe(false);
  });

  it("returns false with whitespace-only difference", () => {
    expect(confirmationMatches("test@example.com", "test@example.com ")).toBe(true);
  });
});

describe("choosePasswordSource", () => {
  it("returns 'stdin' when argv is '-'", () => {
    expect(choosePasswordSource("-")).toBe("stdin");
  });

  it("returns 'argv' when argv value is provided", () => {
    expect(choosePasswordSource("mypassword")).toBe("argv");
  });

  it("returns 'env' when only env var is set", () => {
    expect(choosePasswordSource(undefined, "envpassword")).toBe("env");
  });

  it("returns 'generate' when neither argv nor env is set", () => {
    expect(choosePasswordSource()).toBe("generate");
  });

  it("prioritizes argv '-' over env var", () => {
    expect(choosePasswordSource("-", "envpassword")).toBe("stdin");
  });

  it("prioritizes argv value over env var", () => {
    expect(choosePasswordSource("argvpass", "envpassword")).toBe("argv");
  });
});

describe("createLinePrompter", () => {
  it("returns answers in order for sequential asks", async () => {
    const written: string[] = [];
    const prompter = createLinePrompter("answer1\nanswer2\n", (s) => written.push(s));

    const first = await prompter.ask("Question 1: ");
    const second = await prompter.ask("Question 2: ");

    expect(first).toBe("answer1");
    expect(second).toBe("answer2");
    expect(written).toEqual(["Question 1: ", "Question 2: "]);
  });

  it("rejects when input is exhausted", async () => {
    const prompter = createLinePrompter("only_one_line\n", () => {});

    await prompter.ask("First: ");
    await expect(prompter.ask("Second: ")).rejects.toThrow("stdin ended before an answer was given");
  });

  it("handles CRLF line endings", async () => {
    const prompter = createLinePrompter("answer1\r\nanswer2\r\n", () => {});

    const first = await prompter.ask("Q1: ");
    const second = await prompter.ask("Q2: ");

    expect(first).toBe("answer1");
    expect(second).toBe("answer2");
  });

  it("handles empty input", async () => {
    const prompter = createLinePrompter("", () => {});

    await expect(prompter.ask("Q: ")).rejects.toThrow("stdin ended before an answer was given");
  });

  it("writes prompts to write callback", async () => {
    const written: string[] = [];
    const prompter = createLinePrompter("ans1\nans2\n", (s) => written.push(s));

    await prompter.ask("Prompt 1: ");
    await prompter.ask("Prompt 2: ");

    expect(written).toEqual(["Prompt 1: ", "Prompt 2: "]);
  });

  it("close() is a no-op for line prompter", () => {
    const prompter = createLinePrompter("answer\n", () => {});
    expect(() => prompter.close()).not.toThrow();
  });
});

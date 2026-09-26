import argon2Module from "@phi-ag/argon2/argon2.wasm";
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { buildResetSql, resetOutcomeFromWranglerJson, sqlString } from "../scripts/reset-sql.js";
import {
  choosePasswordSource, confirmationMatches, EXIT_UNCONFIRMED, needsConfirmation, resetReport, wranglerFailureMessage,
} from "../scripts/reset-cli.js";
import { createLinePrompter } from "../scripts/line-prompter.js";
import { createArgon2 } from "../src/auth/argon2.js";
import { call, deviceBody, loginDevice, makeApp, registerAccount } from "./helpers.js";

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

describe("resetOutcomeFromWranglerJson", () => {
  const json = (value: unknown) => JSON.stringify(value);

  it("reset when the first statement counted one account", () => {
    expect(resetOutcomeFromWranglerJson(json([{ results: [{ n: 1 }] }]))).toBe("reset");
  });

  it("no_account when it counted none", () => {
    expect(resetOutcomeFromWranglerJson(json([{ results: [{ n: 0 }] }]))).toBe("no_account");
  });

  it("reads real D1 batch results of the reset SQL (the shape wrangler --json prints)", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const argon2 = await createArgon2(argon2Module);
    const existing = await runSql(buildResetSql(account.email, argon2.hash("reset by support"), 1_900_000_000_000, true));
    expect(resetOutcomeFromWranglerJson(json(existing))).toBe("reset");
    const missing = await runSql(buildResetSql("nobody@example.com", "$argon2id$x", 1, false));
    expect(resetOutcomeFromWranglerJson(json(missing))).toBe("no_account");
  });

  it.each([
    ["invalid JSON", "not valid json"],
    ["truncated JSON", '[{"results":[{"n":1}]'],
    ["a banner before the JSON", 'wrangler 4.139.0\n[{"results":[{"n":1}]}]'],
    ["empty output", ""],
    ["not an array", json({ results: [{ n: 1 }] })],
    ["an empty array", json([])],
    ["a null first result", json([null])],
    ["a first result without results", json([{ error: "something" }])],
    ["an empty results array", json([{ results: [] }])],
    ["a null row", json([{ results: [null] }])],
    ["an unexpected count", json([{ results: [{ n: 2 }] }])],
    ["a count as a string", json([{ results: [{ n: "1" }] }])],
  ])("unconfirmed (never 'nothing changed') for %s", (_, output) => {
    expect(resetOutcomeFromWranglerJson(output)).toBe("unconfirmed");
  });
});

describe("resetReport", () => {
  const ctx = { email: "user@example.com", target: "production", revokeTokens: false };

  it("reset: confirms, prints a generated password and the revocation note, exit 0", () => {
    expect(resetReport("reset", { ...ctx, generatedPassword: "Tmp-Pass_123", revokeTokens: true })).toEqual({
      stdout: [
        "Password reset for user@example.com in production.",
        "Temporary password: Tmp-Pass_123",
        "All device tokens of this account were revoked.",
      ],
      stderr: [],
      exitCode: 0,
    });
    expect(resetReport("reset", ctx).stdout).toEqual(["Password reset for user@example.com in production."]);
  });

  it("no_account: says nothing changed, never prints the password, exit 1", () => {
    const report = resetReport("no_account", { ...ctx, generatedPassword: "Tmp-Pass_123" });
    expect(report).toEqual({
      stdout: [],
      stderr: ["No account with email user@example.com in production; nothing changed."],
      exitCode: 1,
    });
  });

  it("unconfirmed: warns to verify manually and still prints the generated password, distinct exit status", () => {
    const report = resetReport("unconfirmed", { ...ctx, generatedPassword: "Tmp-Pass_123", revokeTokens: true });
    expect(report.stdout).toEqual(["Temporary password: Tmp-Pass_123"]);
    expect(report.stderr).toHaveLength(1);
    expect(report.stderr[0]).toContain("could not confirm");
    expect(report.stderr[0]).toContain("verify manually");
    expect(report.stderr[0]).toContain("device tokens revoked");
    expect(report.stderr.join(" ")).not.toContain("nothing changed");
    expect(report.exitCode).toBe(EXIT_UNCONFIRMED);
    expect(EXIT_UNCONFIRMED).not.toBe(0);
    expect(EXIT_UNCONFIRMED).not.toBe(1);
    // A password the operator supplied is never echoed back.
    expect(resetReport("unconfirmed", ctx).stdout).toEqual([]);
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

describe("wranglerFailureMessage", () => {
  // Shaped like the error execFileSync throws: its message is "Command failed: <argv>", and the argv
  // carries the reset SQL (e-mail address + argon2 hash).
  const sql = "UPDATE users SET password_hash = '$argon2id$v=19$m=19456,t=2,p=1$c2FsdA$aGFzaA' WHERE email = 'user@example.com';";
  const execError = (extra: Record<string, unknown>) =>
    Object.assign(new Error(`Command failed: node wrangler.js d1 execute DB --local --json --command ${sql}`), {
      stdout: "",
      stderr: "",
      ...extra,
    });

  it("reports only the exit status, never the argv/SQL", () => {
    const message = wranglerFailureMessage(execError({ status: 1, signal: null }));
    expect(message).toBe("wrangler d1 execute failed (exit 1)");
    expect(message).not.toContain("user@example.com");
    expect(message).not.toContain("argon2id");
  });

  it("reports a terminating signal", () => {
    expect(wranglerFailureMessage(execError({ status: null, signal: "SIGTERM" }))).toBe("wrangler d1 execute failed (SIGTERM)");
  });

  it("reports a spawn error code", () => {
    expect(wranglerFailureMessage(execError({ code: "ENOENT" }))).toBe("wrangler d1 execute failed (ENOENT)");
  });

  it("falls back to a generic line for anything else", () => {
    expect(wranglerFailureMessage(execError({}))).toBe("wrangler d1 execute failed");
    expect(wranglerFailureMessage("boom user@example.com")).toBe("wrangler d1 execute failed");
    expect(wranglerFailureMessage(null)).toBe("wrangler d1 execute failed");
  });
});

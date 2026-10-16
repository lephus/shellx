import { spawnSync } from "node:child_process";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { hashPassword } from "../src/auth/password.js";
import { createLinePrompter } from "../src/scripts/line-prompter.js";
import {
  choosePasswordSource, confirmationMatches, failureMessage, needsConfirmation, resetReport,
} from "../src/scripts/reset-cli.js";
import { resetPassword } from "../src/scripts/reset-db.js";
import { call, db, deviceBody, loginDevice, makeApp, registerAccount, tempDir } from "./helpers.js";

const RELAY_DIR = join(import.meta.dirname, "..");

describe("resetPassword (SQLite)", () => {
  it("sets a new password, reports the account, and optionally revokes every token", async () => {
    const app = makeApp();
    const account = await registerAccount(app, `o'brien-${crypto.randomUUID()}@example.com`);
    const mobile = await loginDevice(app, account, "mobile");
    expect(resetPassword(db(), account.email, await hashPassword("reset by support"), 1_900_000_000_000, true)).toBe("reset");

    const login = (password: string) =>
      call(app, "POST", "/v1/auth/login", { body: { email: account.email, password, device: deviceBody("mobile") } });
    expect((await login(account.password)).status).toBe(401);
    expect((await login("reset by support")).status).toBe(200);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(401);
    expect((await call(app, "GET", "/v1/devices", { token: mobile.token })).status).toBe(401);
    expect(db().get("SELECT password_changed_at FROM users WHERE id = ?", account.agent.userId)).toEqual({
      password_changed_at: 1_900_000_000_000,
    });
  });

  it("keeps the tokens (and pairings) without revokeTokens", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    expect(resetPassword(db(), account.email, await hashPassword("reset by support"), 1, false)).toBe("reset");
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(200);
  });

  it("reports no_account for an unknown e-mail and changes nothing", () => {
    expect(resetPassword(db(), "nobody@example.com", "$argon2id$x", 1, true)).toBe("no_account");
  });

  it("rejects a non-integer timestamp", () => {
    expect(() => resetPassword(db(), "a@b.co", "x", 1.5, false)).toThrow(TypeError);
  });
});

describe("resetReport", () => {
  const ctx = { email: "user@example.com", target: "/data/relay.db", revokeTokens: false };

  it("reset: confirms, prints a generated password and the revocation note, exit 0", () => {
    expect(resetReport("reset", { ...ctx, generatedPassword: "Tmp-Pass_123", revokeTokens: true })).toEqual({
      stdout: [
        "Password reset for user@example.com in /data/relay.db.",
        "Temporary password: Tmp-Pass_123",
        "All device tokens of this account were revoked.",
      ],
      stderr: [],
      exitCode: 0,
    });
    expect(resetReport("reset", ctx).stdout).toEqual(["Password reset for user@example.com in /data/relay.db."]);
  });

  it("no_account: says nothing changed, never prints the password, exit 1", () => {
    expect(resetReport("no_account", { ...ctx, generatedPassword: "Tmp-Pass_123" })).toEqual({
      stdout: [],
      stderr: ["No account with email user@example.com in /data/relay.db; nothing changed."],
      exitCode: 1,
    });
  });
});

describe("failureMessage", () => {
  it("reports only the SQLite code or the error class, never the message", () => {
    const busy = Object.assign(new Error("database is locked: UPDATE users SET password_hash = '$argon2id$…' WHERE email = 'user@example.com'"), {
      code: "SQLITE_BUSY",
    });
    expect(failureMessage(busy)).toBe("database error (SQLITE_BUSY)");
    expect(failureMessage(new TypeError("user@example.com"))).toBe("database error (TypeError)");
    expect(failureMessage("boom user@example.com")).toBe("database error (unknown)");
    expect(failureMessage(null)).toBe("database error (unknown)");
  });
});

describe("needsConfirmation", () => {
  it("asks unless --yes", () => {
    expect(needsConfirmation(false)).toBe(true);
    expect(needsConfirmation(true)).toBe(false);
  });
});

describe("confirmationMatches", () => {
  it("matches after trimming and normalising the case", () => {
    expect(confirmationMatches("test@example.com", "test@example.com")).toBe(true);
    expect(confirmationMatches("test@example.com", "  test@example.com  ")).toBe(true);
    expect(confirmationMatches("test@example.com", "Test@Example.com")).toBe(true);
    expect(confirmationMatches("test@example.com", "other@example.com")).toBe(false);
  });
});

describe("choosePasswordSource", () => {
  it("prefers argv '-' (stdin), then an argv value, then the env var, else generates", () => {
    expect(choosePasswordSource("-")).toBe("stdin");
    expect(choosePasswordSource("mypassword")).toBe("argv");
    expect(choosePasswordSource(undefined, "envpassword")).toBe("env");
    expect(choosePasswordSource()).toBe("generate");
    expect(choosePasswordSource("-", "envpassword")).toBe("stdin");
    expect(choosePasswordSource("argvpass", "envpassword")).toBe("argv");
  });
});

describe("createLinePrompter", () => {
  it("returns answers in order and writes each question", async () => {
    const written: string[] = [];
    const prompter = createLinePrompter("answer1\r\nanswer2\n", (s) => written.push(s));
    expect(await prompter.ask("Question 1: ")).toBe("answer1");
    expect(await prompter.ask("Question 2: ")).toBe("answer2");
    expect(written).toEqual(["Question 1: ", "Question 2: "]);
    await expect(prompter.ask("Question 3: ")).rejects.toThrow("stdin ended before an answer was given");
    expect(() => prompter.close()).not.toThrow();
  });

  it("rejects on empty input", async () => {
    await expect(createLinePrompter("", () => {}).ask("Q: ")).rejects.toThrow("stdin ended before an answer was given");
  });
});

/** Runs the real script (through tsx) against `dbPath`; stdin is `input`. */
function runScript(dbPath: string, args: string[], input = "", env: Record<string, string> = {}) {
  const result = spawnSync(process.execPath, ["--import", "tsx", "src/scripts/reset-password.ts", ...args], {
    cwd: RELAY_DIR,
    input,
    encoding: "utf8",
    env: { ...process.env, DB_PATH: dbPath, ...env },
    timeout: 20_000,
  });
  return { status: result.status, stdout: result.stdout, stderr: result.stderr };
}

describe("reset-password script (end to end)", () => {
  it("resets through the typed confirmation, prints one-line results, and never prints SQL", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const dbPath = join(tempDir(), "relay.db");
    const run = runScript(dbPath, ["--email", account.email, "--password", "-", "--revoke-tokens"], `a new password\n${account.email}\n`);
    expect(run.stderr).not.toMatch(/SELECT|UPDATE|DELETE/);
    expect(run.stdout.trim().split("\n")).toEqual([
      `Password reset for ${account.email} in ${dbPath}.`,
      "All device tokens of this account were revoked.",
    ]);
    expect(run.status).toBe(0);
    const login = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: "a new password", device: deviceBody("mobile") },
    });
    expect(login.status).toBe(200);
  });

  it("aborts on a mismatched confirmation, and exits 1 for an unknown account", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const dbPath = join(tempDir(), "relay.db");
    const mismatch = runScript(dbPath, ["--email", account.email], "someone-else@example.com\n");
    expect(mismatch.status).toBe(1);
    expect(mismatch.stderr).toContain("Email mismatch; operation aborted.");
    const unknown = runScript(dbPath, ["--email", "nobody@example.com", "--yes"]);
    expect(unknown.status).toBe(1);
    expect(unknown.stderr).toContain(`No account with email nobody@example.com in ${dbPath}; nothing changed.`);
    expect(unknown.stdout).not.toContain("Temporary password");
  });

  it("refuses to create a database that does not exist, in one line", () => {
    const missing = join(tempDir(), "nope", "relay.db");
    const run = runScript(missing, ["--email", "user@example.com", "--yes"]);
    expect(run.status).toBe(1);
    expect(run.stderr.trim().split("\n").at(-1)).toBe(`cannot open database at ${missing} (ENOENT)`);
  });

  it("generates and prints a temporary password when none is given", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const run = runScript(join(tempDir(), "relay.db"), ["--email", account.email, "--yes"]);
    expect(run.status).toBe(0);
    const temporary = /Temporary password: ([A-Za-z0-9_-]{16})/.exec(run.stdout)?.[1];
    expect(temporary).toBeDefined();
    const login = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: temporary, device: deviceBody("mobile") },
    });
    expect(login.status).toBe(200);
  });
});

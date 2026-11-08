import { spawnSync } from "node:child_process";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { cutOverPasswords, passwordState } from "../src/scripts/password-cutover.js";
import { call, db, googleSession, loginDevice, makeApp, registerAccount, tempDir } from "./helpers.js";

const RELAY_DIR = join(import.meta.dirname, "..");
const run = (args: string[], env: Record<string, string>) =>
  spawnSync(process.execPath, ["--import", "tsx", "src/scripts/password-cutover.ts", ...args], {
    cwd: RELAY_DIR, encoding: "utf8", env: { ...process.env, DB_PATH: join(tempDir(), "relay.db"), ...env }, timeout: 20_000,
  });

describe("password cut-over (S1 §7 step 5)", () => {
  it("clears every password and password session, keeps other sessions, and lets the email link straight in afterwards", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const phone = await loginDevice(app, account, "mobile");
    const google = await googleSession(app);
    expect(passwordState(db())).toEqual({ passwords: 1, sessions: 2 });
    expect(cutOverPasswords(db())).toEqual({ passwords: 1, sessions: 2 });
    expect(passwordState(db())).toEqual({ passwords: 0, sessions: 0 });
    for (const token of [account.agent.token, phone.token]) expect((await call(app, "GET", "/v1/devices", { token })).status).toBe(401);
    expect((await call(app, "GET", "/v1/devices", { token: google.token })).status).toBe(200);
    expect((await googleSession(app, { email: account.email })).userId).toBe(account.agent.userId);
  });

  it("the script refuses unless PASSWORD_LOGIN=off, dry-runs without --yes and prints counts only", async () => {
    await registerAccount(makeApp());
    const refused = run(["--yes"], { PASSWORD_LOGIN: "on" });
    expect([refused.status, refused.stderr]).toEqual([1, "password-cutover: set PASSWORD_LOGIN=off and recreate the relay first\n"]);
    const dry = run([], { PASSWORD_LOGIN: "off" });
    expect([dry.status, dry.stdout]).toEqual([0, "password-cutover: dry run: 1 account(s) with a password, 1 password session(s); run again with --yes to remove them.\n"]);
    expect(passwordState(db()).passwords).toBe(1);
    const real = run(["--yes"], { PASSWORD_LOGIN: "off" });
    expect([real.status, real.stdout]).toEqual([0, "password-cutover: removed 1 password(s) and 1 password session(s).\n"]);
    expect(passwordState(db())).toEqual({ passwords: 0, sessions: 0 });
  });
});

// Emergency support tool (spec §5.2): sets a new password for one account directly in D1.
//
//   npm run reset-password -- --env <local|staging|production> --email <address> [--password <new>] [--revoke-tokens] [--yes]
//
// Without --password a random 16-character password is generated and printed once.
// Password can also be read from SHELLX_RESET_PASSWORD env var or stdin with `--password -`.
// --revoke-tokens also signs out every device of the account (their open sockets stay up until they
// reconnect). Pairings are never touched. Remote environments need `npx wrangler login` first.
// --env staging and --env production require either interactive email confirmation or --yes flag.
import { execFileSync, execSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { parseArgs } from "node:util";
import { createArgon2 } from "../src/auth/argon2";
import { isValidEmail, normalizeEmail } from "../src/auth/email";
import { isAcceptablePassword } from "../src/auth/password-policy";
import { base64UrlEncode } from "../src/auth/tokens";
import { accountExistsFromWranglerJson, buildResetSql } from "./reset-sql";

const { values } = parseArgs({
  options: {
    env: { type: "string" },
    email: { type: "string" },
    password: { type: "string" },
    "revoke-tokens": { type: "boolean", default: false },
    yes: { type: "boolean", default: false },
  },
});

// Validation: all error handling uses console.error + process.exit(1) for clean one-line errors
const target = values.env;
if (target !== "local" && target !== "staging" && target !== "production") {
  console.error("--env must be one of: local, staging, production");
  process.exit(1);
}
const email = normalizeEmail(values.email ?? "");
if (!isValidEmail(email)) {
  console.error("--email is not a valid address");
  process.exit(1);
}

// Confirmation guard for remote environments (staging, production)
if (target !== "local" && !values.yes) {
  // Interactive confirmation: read typed email from TTY
  process.stderr.write(`Confirm email for ${target}: `);
  const confirmed = execSync("cat", { encoding: "utf8" }).trim();
  if (confirmed !== email) {
    console.error("Email mismatch; operation aborted.");
    process.exit(1);
  }
}

// Password input: from env var, stdin (with --password -), argv (with warning), or generate random
let password: string;
if (values.password === "-") {
  // Read from stdin
  password = execSync("cat", { encoding: "utf8" }).trim();
} else if (values.password) {
  // From argv: print warning to stderr about visibility
  console.error("Warning: --password in argv is visible in shell history and process lists; consider --password - or SHELLX_RESET_PASSWORD env var");
  password = values.password;
} else {
  // Try env var or generate random
  password = process.env.SHELLX_RESET_PASSWORD ?? base64UrlEncode(crypto.getRandomValues(new Uint8Array(12)));
}

if (!isAcceptablePassword(password)) {
  console.error("password must be 8-128 characters");
  process.exit(1);
}

const require = createRequire(import.meta.url);
const wasm = readFileSync(require.resolve("@phi-ag/argon2/argon2.wasm"));
const argon2 = await createArgon2(new WebAssembly.Module(wasm));
const sql = buildResetSql(email, argon2.hash(password), Date.now(), values["revoke-tokens"]);

const wrangler = join(dirname(require.resolve("wrangler/package.json")), "bin", "wrangler.js");
const where = target === "local" ? ["--local"] : ["--env", target, "--remote"];
const output = execFileSync(process.execPath, [wrangler, "d1", "execute", "DB", ...where, "--json", "--command", sql], {
  encoding: "utf8",
  stdio: ["inherit", "pipe", "inherit"],
});

// Use pure function to check if account exists
if (!accountExistsFromWranglerJson(output)) {
  console.error(`No account with email ${email} in ${target}; nothing changed.`);
  process.exit(1);
}

console.log(`Password reset for ${email} in ${target}.`);
if (values.password === undefined && !process.env.SHELLX_RESET_PASSWORD) console.log(`Temporary password: ${password}`);
if (values["revoke-tokens"]) console.log("All device tokens of this account were revoked.");

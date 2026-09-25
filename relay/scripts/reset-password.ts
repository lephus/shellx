// Emergency support tool (spec §5.2): sets a new password for one account directly in D1.
//
//   npm run reset-password -- --env <local|staging|production> --email <address> [--password <new>] [--revoke-tokens] [--yes]
//
// Without --password a random 16-character password is generated and printed once.
// Password can also be read from SHELLX_RESET_PASSWORD env var or stdin with `--password -`.
// --revoke-tokens also signs out every device of the account (their open sockets stay up until they
// reconnect). Pairings are never touched. Remote environments need `npx wrangler login` first.
// --env staging and --env production require either interactive email confirmation or --yes flag.
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { parseArgs } from "node:util";
import { createArgon2 } from "../src/auth/argon2";
import { isValidEmail, normalizeEmail } from "../src/auth/email";
import { isAcceptablePassword } from "../src/auth/password-policy";
import { base64UrlEncode } from "../src/auth/tokens";
import { buildResetSql, resetOutcomeFromWranglerJson } from "./reset-sql";
import { choosePasswordSource, confirmationMatches, needsConfirmation, resetReport, wranglerFailureMessage } from "./reset-cli";
import { createPrompter } from "./prompter";

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

// Password input first (if --password -, read from stdin before confirmation)
const passwordSource = choosePasswordSource(values.password, process.env.SHELLX_RESET_PASSWORD);
const prompter = createPrompter();
let password: string;

try {
  if (passwordSource === "stdin") {
    // Read password from stdin
    password = await prompter.ask("Password: ");
  } else if (passwordSource === "argv") {
    // From argv: print warning to stderr about visibility
    console.error("Warning: --password in argv is visible in shell history and process lists; consider --password - or SHELLX_RESET_PASSWORD env var");
    password = values.password!;
  } else if (passwordSource === "env") {
    // From env var
    password = process.env.SHELLX_RESET_PASSWORD!;
  } else {
    // Generate random password
    password = base64UrlEncode(crypto.getRandomValues(new Uint8Array(12)));
  }

  if (!isAcceptablePassword(password)) {
    console.error("password must be 8-128 characters");
    process.exit(1);
  }

  // Confirmation guard for remote environments (staging, production)
  if (needsConfirmation(target, values.yes)) {
    const typed = await prompter.ask(`Confirm email for ${target}: `);
    if (!confirmationMatches(email, typed)) {
      console.error("Email mismatch; operation aborted.");
      process.exit(1);
    }
  } else if (values.yes && target !== "local") {
    // Bypass confirmation with --yes: print note
    console.error(`Confirmation bypassed with --yes for ${target}.`);
  }

  // Close prompter before spawning wrangler
  prompter.close();

  // Hash password and build SQL
  const require = createRequire(import.meta.url);
  const wasm = readFileSync(require.resolve("@phi-ag/argon2/argon2.wasm"));
  const argon2 = await createArgon2(new WebAssembly.Module(wasm));
  const sql = buildResetSql(email, argon2.hash(password), Date.now(), values["revoke-tokens"]);

  // Execute via wrangler d1
  const wrangler = join(dirname(require.resolve("wrangler/package.json")), "bin", "wrangler.js");
  const where = target === "local" ? ["--local"] : ["--env", target, "--remote"];
  let output: string;
  try {
    output = execFileSync(process.execPath, [wrangler, "d1", "execute", "DB", ...where, "--json", "--command", sql], {
      encoding: "utf8",
      stdio: ["inherit", "pipe", "inherit"],
    });
  } catch (err) {
    // The error's message embeds the argv (SQL with e-mail + hash): report the exit status only.
    throw new Error(wranglerFailureMessage(err));
  }

  // Pure decision + report (unit-tested): reset, no account, or unconfirmed (output unreadable).
  const report = resetReport(resetOutcomeFromWranglerJson(output), {
    email,
    target,
    generatedPassword: passwordSource === "generate" ? password : undefined,
    revokeTokens: values["revoke-tokens"],
  });
  for (const line of report.stderr) console.error(line);
  for (const line of report.stdout) console.log(line);
  if (report.exitCode !== 0) process.exit(report.exitCode);
} catch (err) {
  prompter.close();
  if (err instanceof Error) {
    console.error(err.message);
  } else {
    console.error("An unknown error occurred");
  }
  process.exit(1);
}

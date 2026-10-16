// Emergency support tool (spec §5.2, VPS spec §4.4): sets a new password for one account directly
// in the relay's SQLite database. On the VPS:
//
//   docker compose exec relay node dist/scripts/reset-password.js --email <address> [--password <new>|-] [--revoke-tokens] [--yes]
//
// Locally (against .data/relay.db from `npm run dev`): npm run reset-password -- --email <address> …
//
// The database is DB_PATH (default /data/relay.db). Without --password a random 16-character
// password is generated and printed once. The password can also come from SHELLX_RESET_PASSWORD or
// from stdin with `--password -`. --revoke-tokens also signs out every device of the account (open
// sockets stay up until they reconnect). Pairings are never touched. Without --yes the operator
// must type the account's e-mail address to confirm.
import { parseArgs } from "node:util";
import { isValidEmail, normalizeEmail } from "../auth/email.js";
import { hashPassword } from "../auth/password.js";
import { isAcceptablePassword } from "../auth/password-policy.js";
import { base64UrlEncode } from "../auth/tokens.js";
import { DEFAULT_DB_PATH } from "../config.js";
import { Db } from "../db/db.js";
import { errorKind } from "../log.js";
import { createPrompter } from "./prompter.js";
import { choosePasswordSource, confirmationMatches, failureMessage, needsConfirmation, resetReport } from "./reset-cli.js";
import { resetPassword } from "./reset-db.js";

const { values } = parseArgs({
  options: {
    email: { type: "string" },
    password: { type: "string" },
    "revoke-tokens": { type: "boolean", default: false },
    yes: { type: "boolean", default: false },
  },
});

const target = process.env.DB_PATH?.trim() || DEFAULT_DB_PATH;
const prompter = createPrompter();

/** Prints one line to stderr and exits 1, restoring the terminal first. */
function fail(message: string): never {
  prompter.close();
  console.error(message);
  process.exit(1);
}

const email = normalizeEmail(values.email ?? "");
if (!isValidEmail(email)) fail("--email is not a valid address");

const passwordSource = choosePasswordSource(values.password, process.env.SHELLX_RESET_PASSWORD);
let password: string;
try {
  if (passwordSource === "stdin") {
    password = await prompter.ask("Password: ", { hidden: true });
  } else if (passwordSource === "argv") {
    console.error("Warning: --password in argv is visible in shell history and process lists; consider --password - or SHELLX_RESET_PASSWORD env var");
    password = values.password!;
  } else if (passwordSource === "env") {
    password = process.env.SHELLX_RESET_PASSWORD!;
  } else {
    password = base64UrlEncode(crypto.getRandomValues(new Uint8Array(12)));
  }
} catch (err) {
  fail(err instanceof Error ? err.message : "An unknown error occurred");
}
if (!isAcceptablePassword(password)) fail("password must be 8-128 characters");

if (needsConfirmation(values.yes)) {
  let typed: string;
  try {
    typed = await prompter.ask(`Confirm email for ${target}: `);
  } catch (err) {
    fail(err instanceof Error ? err.message : "An unknown error occurred");
  }
  if (!confirmationMatches(email, typed)) fail("Email mismatch; operation aborted.");
} else {
  console.error(`Confirmation bypassed with --yes for ${target}.`);
}
prompter.close();

let db: Db;
try {
  db = Db.open(target, { fileMustExist: true });
} catch (err) {
  fail(`cannot open database at ${target} (${errorKind(err)})`);
}
try {
  const outcome = resetPassword(db, email, await hashPassword(password), Date.now(), values["revoke-tokens"]);
  const report = resetReport(outcome, {
    email,
    target,
    generatedPassword: passwordSource === "generate" ? password : undefined,
    revokeTokens: values["revoke-tokens"],
  });
  for (const line of report.stderr) console.error(line);
  for (const line of report.stdout) console.log(line);
  db.close();
  process.exit(report.exitCode);
} catch (err) {
  db.close();
  fail(failureMessage(err));
}

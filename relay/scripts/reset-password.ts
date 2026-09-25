// Emergency support tool (spec §5.2): sets a new password for one account directly in D1.
//
//   npm run reset-password -- --env <local|staging|production> --email <address> [--password <new>] [--revoke-tokens]
//
// Without --password a random 16-character password is generated and printed once.
// --revoke-tokens also signs out every device of the account (their open sockets stay up until they
// reconnect). Pairings are never touched. Remote environments need `npx wrangler login` first.
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { parseArgs } from "node:util";
import { createArgon2 } from "../src/auth/argon2";
import { isValidEmail, normalizeEmail } from "../src/auth/email";
import { isAcceptablePassword } from "../src/auth/password-policy";
import { base64UrlEncode } from "../src/auth/tokens";
import { buildResetSql } from "./reset-sql";

const { values } = parseArgs({
  options: {
    env: { type: "string" },
    email: { type: "string" },
    password: { type: "string" },
    "revoke-tokens": { type: "boolean", default: false },
  },
});

const target = values.env;
if (target !== "local" && target !== "staging" && target !== "production") {
  throw new Error("--env must be one of: local, staging, production");
}
const email = normalizeEmail(values.email ?? "");
if (!isValidEmail(email)) throw new Error("--email is not a valid address");
const password = values.password ?? base64UrlEncode(crypto.getRandomValues(new Uint8Array(12)));
if (!isAcceptablePassword(password)) throw new Error("password must be 8-128 characters");

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
const results = JSON.parse(output) as { results: { n?: number }[] }[];
if (results[0]?.results[0]?.n !== 1) {
  console.error(`No account with email ${email} in ${target}; nothing changed.`);
  process.exit(1);
}
console.log(`Password reset for ${email} in ${target}.`);
if (values.password === undefined) console.log(`Temporary password: ${password}`);
if (values["revoke-tokens"]) console.log("All device tokens of this account were revoked.");

// Mints a session token for the relay2 smoke test (scripts/relay2-smoke.ts) now that registration is
// closed and passwords are going away. On the VPS:
//
//   docker compose exec -T relay npm run -s mint-smoke-token
//
// Prints exactly the token and a newline. It belongs to a dedicated passwordless smoke account (no
// identity, an email on the reserved .invalid domain) and one fixed desktop device; each mint replaces
// the previous token. The token is a normal bearer token (auth_method "test").
import { createHash } from "node:crypto";
import { pathToFileURL } from "node:url";
import { replaceDeviceToken, upsertDevice } from "../auth/identity.js";
import { generateToken, hashToken } from "../auth/tokens.js";
import { DEFAULT_DB_PATH } from "../config.js";
import { Db } from "../db/db.js";
import { errorKind } from "../log.js";

export const SMOKE_EMAIL = "relay2-smoke@smoke.invalid";
export const SMOKE_DEVICE_NAME = "relay2-smoke";

export async function mintSmokeToken(db: Db, nowMs: number): Promise<string> {
  const token = generateToken();
  const tokenHash = await hashToken(token);
  db.transaction(() => {
    const existing = db.get<{ id: string }>("SELECT id FROM users WHERE email = ?", SMOKE_EMAIL);
    const userId = existing?.id ?? crypto.randomUUID();
    if (existing === undefined) {
      db.run("INSERT INTO users (id, email, password_hash, password_changed_at, created_at) VALUES (?, ?, NULL, ?, ?)", userId, SMOKE_EMAIL, nowMs, nowMs);
    }
    const deviceId = upsertDevice(db, userId, {
      kind: "desktop", name: SMOKE_DEVICE_NAME, platform: "macos",
      publicKey: new Uint8Array(createHash("sha256").update("shellx-relay2-smoke").digest()),
    }, nowMs);
    replaceDeviceToken(db, deviceId, tokenHash, "test", null, nowMs);
  });
  return token;
}

async function main(): Promise<number> {
  let db: Db | undefined;
  try {
    db = Db.open(process.env.DB_PATH?.trim() || DEFAULT_DB_PATH, { fileMustExist: true });
    console.log(await mintSmokeToken(db, Date.now()));
    return 0;
  } catch (err) {
    console.error(`mint-smoke-token: database error (${errorKind(err)})`);
    return 1;
  } finally {
    db?.close();
  }
}

if (process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = await main();
}

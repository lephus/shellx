import { Hono } from "hono";
import type { AppEnv } from "../app.js";
import { requestIp } from "../auth/client-ip.js";
import { parseDevice } from "../auth/device.js";
import { accountEmail, dropPasswordAccess, identityFromToken, insertIdentity, matchAccount, signInDevice } from "../auth/identity.js";
import { ID_TOKEN_MAX_AGE_SEC } from "../auth/id-token.js";
import { consumeNonce, issueNonce, NONCE_TTL_MS } from "../auth/nonces.js";
import { generateToken, hashToken } from "../auth/tokens.js";
import { jsonBodyLimit } from "../http/body-limit.js";
import { Errors, readJsonObject } from "../http/errors.js";
import { logMeta } from "../log.js";
import { CLIENT_VERSION_HEADER, recordAppVersion } from "../versions.js";

/** Sign-in routes mounted at /v1/auth (S1 §6): nonce, Google, Apple. */
export const signInRoutes = new Hono<AppEnv>();

/** POST /v1/auth/nonce — a single-use nonce for the next ID token; the body is not read. */
signInRoutes.post("/nonce", jsonBodyLimit, async (c) => {
  if (!(await c.get("limiters").nonceIp.limit(requestIp(c)))) throw Errors.rateLimited();
  const nonce = await issueNonce(c.get("db"), c.get("now")());
  return c.json({ nonce, expires_in: NONCE_TTL_MS / 1000 }, 201);
});

/**
 * POST /v1/auth/google {id_token, nonce, device} — sign in with Google (or the test provider). Awaits
 * first (token check, nonce use, hashing), then resolves the account and writes in one synchronous
 * transaction (S1 §6.3): an identity, else the account with this email, else a new account.
 */
signInRoutes.post("/google", jsonBodyLimit, async (c) => {
  if (!(await c.get("limiters").loginIp.limit(requestIp(c)))) throw Errors.rateLimited();
  const body = await readJsonObject(c.req.raw);
  const device = parseDevice(body.device);
  if (device === null || device.kind === "agent") throw Errors.invalidDevice();
  const db = c.get("db");
  const now = c.get("now")();
  const verified = await c.get("idTokens").verify(body.id_token, {
    providers: ["google", "test"], nonce: typeof body.nonce === "string" ? body.nonce : "", maxAgeSec: ID_TOKEN_MAX_AGE_SEC, nowMs: now,
  });
  if (verified === null) throw Errors.invalidCredentials();
  if (!(await consumeNonce(db, body.nonce, now))) {
    logMeta("sign_in_refused", { provider: verified.provider, reason: "nonce" });
    throw Errors.invalidCredentials();
  }
  const token = generateToken();
  const tokenHash = await hashToken(token);
  const passwordLogin = c.get("config").passwordLogin;

  let dropped = 0;
  let via: "identity" | "email" | "new_account" = "identity";
  const result = db.transaction(() => {
    const match = matchAccount(db, verified, passwordLogin);
    if (match.kind === "switch_required") throw Errors.switchFromSignedInDevice();
    let userId: string;
    let identityId: string;
    if (match.kind === "identity") {
      userId = match.userId;
      identityId = match.identityId;
      db.run("UPDATE identities SET last_used_at = ? WHERE id = ?", now, identityId);
    } else if (match.kind === "email") {
      if (match.hasPrimary) {
        // A recycled address: this account already has a Google sign-in, which is not this one.
        logMeta("sign_in_refused", { provider: verified.provider, reason: "other_google_identity" });
        throw Errors.invalidCredentials();
      }
      userId = match.userId;
      dropped = dropPasswordAccess(db, userId);
      identityId = insertIdentity(db, userId, identityFromToken(verified), now);
      via = "email";
    } else {
      userId = crypto.randomUUID();
      db.run("INSERT INTO users (id, email, password_hash, password_changed_at, created_at) VALUES (?, ?, NULL, ?, ?)", userId, verified.email, now, now);
      identityId = insertIdentity(db, userId, identityFromToken(verified), now);
      via = "new_account";
    }
    const deviceId = signInDevice(db, userId, device, tokenHash, verified.provider, identityId, now);
    return { userId, deviceId, email: accountEmail(db, userId) };
  });

  recordAppVersion(db, result.deviceId, c.req.header(CLIENT_VERSION_HEADER));
  logMeta("sign_in", { device_id: result.deviceId, provider: verified.provider, via });
  if (dropped > 0) logMeta("password_access_dropped", { sessions: dropped });
  return c.json({ user_id: result.userId, device_id: result.deviceId, token, email: result.email });
});

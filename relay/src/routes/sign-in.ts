import { Hono } from "hono";
import type { AppEnv } from "../app.js";
import { requestIp } from "../auth/client-ip.js";
import { APPLE_LINK_TTL_MS, createAppleLink, purgeAppleLinks } from "../auth/apple-links.js";
import { parseDevice } from "../auth/device.js";
import { accountEmail, dropPasswordAccess, identityFromToken, insertIdentity, matchAccount, replaceDeviceToken, signInDevice } from "../auth/identity.js";
import { ID_TOKEN_MAX_AGE_SEC } from "../auth/id-token.js";
import { consumeNonce, issueNonce, NONCE_TTL_MS } from "../auth/nonces.js";
import { requireAuth } from "../auth/session.js";
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

/**
 * POST /v1/auth/google/link {id_token, nonce} — a signed-in device (any kind) adds a Google sign-in to
 * its account in place (S1 §6.3b). The email of the account becomes Google's; the password and the
 * other devices are untouched; only this device gets a new `google` token.
 */
signInRoutes.post("/google/link", requireAuth, jsonBodyLimit, async (c) => {
  const auth = c.get("auth");
  const body = await readJsonObject(c.req.raw);
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

  const email = db.transaction(() => {
    const existing = db.get<{ id: string; user_id: string }>(
      "SELECT id, user_id FROM identities WHERE provider = ? AND subject = ?", verified.provider, verified.subject,
    );
    if (existing !== undefined && existing.user_id !== auth.userId) throw Errors.identityInUse();
    let identityId: string;
    if (existing === undefined) {
      if (db.get("SELECT 1 FROM identities WHERE user_id = ? AND provider != 'apple'", auth.userId) !== undefined) {
        throw Errors.identityInUse();
      }
      if (verified.email !== accountEmail(db, auth.userId)) {
        if (db.get("SELECT 1 FROM users WHERE email = ? AND id != ?", verified.email, auth.userId) !== undefined) throw Errors.emailInUse();
        db.run("UPDATE users SET email = ? WHERE id = ?", verified.email, auth.userId);
      }
      identityId = insertIdentity(db, auth.userId, identityFromToken(verified), now);
    } else {
      identityId = existing.id;
      db.run("UPDATE identities SET last_used_at = ? WHERE id = ?", now, identityId);
    }
    replaceDeviceToken(db, auth.deviceId, tokenHash, verified.provider, identityId, now);
    return accountEmail(db, auth.userId);
  });

  logMeta("google_linked", { device_id: auth.deviceId });
  return c.json({ user_id: auth.userId, device_id: auth.deviceId, token, email });
});

/**
 * POST /v1/auth/apple {identity_token, authorization_code, nonce, device} — sign in with Apple on an
 * iPhone. An Apple ID that matches an account signs in; one that matches none (or only an account that
 * still has a password) gets 202 `link_required` with a link token, to be approved on a Mac (S1 §6.4).
 */
signInRoutes.post("/apple", jsonBodyLimit, async (c) => {
  if (!(await c.get("limiters").loginIp.limit(requestIp(c)))) throw Errors.rateLimited();
  const body = await readJsonObject(c.req.raw);
  const device = parseDevice(body.device);
  if (device === null || device.kind !== "mobile" || device.platform !== "ios") throw Errors.invalidDevice();
  const db = c.get("db");
  const now = c.get("now")();
  const verified = await c.get("idTokens").verify(body.identity_token, {
    providers: ["apple"], nonce: typeof body.nonce === "string" ? body.nonce : "", maxAgeSec: ID_TOKEN_MAX_AGE_SEC, nowMs: now,
  });
  if (verified === null) throw Errors.invalidCredentials();
  if (!(await consumeNonce(db, body.nonce, now))) {
    logMeta("sign_in_refused", { provider: "apple", reason: "nonce" });
    throw Errors.invalidCredentials();
  }
  const code = typeof body.authorization_code === "string" && body.authorization_code !== "" ? body.authorization_code : null;
  const passwordLogin = c.get("config").passwordLogin;
  // `switch_required` is treated like `none`: the QR link proves ownership through the Mac's Allow and
  // attaches the Apple ID to the Mac's account, never to the email-matched one (decision 2026-11-07).
  const pre = matchAccount(db, verified, passwordLogin);

  const gateway = c.get("appleTokens");
  let refresh: string | null = null;
  if (gateway !== null && code !== null) {
    let wanted = pre.kind !== "identity";
    if (pre.kind === "identity") {
      const stored = db.get<{ apple_refresh_token: string | null; apple_client_id: string | null }>(
        "SELECT apple_refresh_token, apple_client_id FROM identities WHERE id = ?", pre.identityId,
      );
      wanted = stored?.apple_refresh_token == null || stored.apple_client_id !== verified.audience;
    }
    if (wanted) refresh = await gateway.exchangeCode(verified.audience, code);
  }

  purgeAppleLinks(db, now);
  if (pre.kind === "none" || pre.kind === "switch_required") {
    const linkToken = await createAppleLink(db, {
      subject: verified.subject, email: verified.email, isPrivateEmail: verified.isPrivateEmail, appleClientId: verified.audience,
      appleRefreshToken: refresh, deviceName: device.name, devicePublicKey: device.publicKey,
    }, now);
    logMeta("apple_link_required", {});
    return c.json({ status: "link_required", link_token: linkToken, expires_in: APPLE_LINK_TTL_MS / 1000 }, 202);
  }

  const token = generateToken();
  const tokenHash = await hashToken(token);
  let dropped = 0;
  let via: "identity" | "email" = "identity";
  const result = db.transaction(() => {
    const match = matchAccount(db, verified, passwordLogin);
    if (match.kind === "switch_required" || match.kind === "none") throw Errors.invalidCredentials();
    let identityId: string;
    if (match.kind === "identity") {
      identityId = match.identityId;
      db.run("UPDATE identities SET last_used_at = ? WHERE id = ?", now, identityId);
      if (refresh !== null) {
        db.run("UPDATE identities SET apple_refresh_token = ?, apple_client_id = ? WHERE id = ?", refresh, verified.audience, identityId);
      }
    } else {
      dropped = dropPasswordAccess(db, match.userId);
      identityId = insertIdentity(db, match.userId, {
        ...identityFromToken(verified), appleRefreshToken: refresh, appleClientId: refresh === null ? null : verified.audience,
      }, now);
      via = "email";
    }
    const deviceId = signInDevice(db, match.userId, device, tokenHash, "apple", identityId, now);
    return { userId: match.userId, deviceId, email: accountEmail(db, match.userId) };
  });

  recordAppVersion(db, result.deviceId, c.req.header(CLIENT_VERSION_HEADER));
  logMeta("sign_in", { device_id: result.deviceId, provider: "apple", via });
  if (dropped > 0) logMeta("password_access_dropped", { sessions: dropped });
  return c.json({ user_id: result.userId, device_id: result.deviceId, token, email: result.email });
});

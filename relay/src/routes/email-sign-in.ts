import { Hono } from "hono";
import type { AppEnv } from "../app.js";
import { requestIp } from "../auth/client-ip.js";
import { parseDevice } from "../auth/device.js";
import { checkEmail } from "../auth/email.js";
import { discardEmailCode, EMAIL_CODE_RESEND_SEC, EMAIL_CODE_TTL_MS, issueEmailCode, redeemEmailCode } from "../auth/email-codes.js";
import { accountEmail, dropPasswordAccess, identityFromToken, insertIdentity, matchAccount, signInDevice } from "../auth/identity.js";
import type { VerifiedIdToken } from "../auth/id-token.js";
import { generateToken, hashToken } from "../auth/tokens.js";
import type { EmailSendResult } from "../email/resend.js";
import { type EmailLocale, signInCodeEmail } from "../email/sign-in-code.js";
import { jsonBodyLimit } from "../http/body-limit.js";
import { type ApiError, Errors, readJsonObject } from "../http/errors.js";
import { errorKind, logMeta } from "../log.js";
import { CloseCode } from "../protocol/frames.js";
import { CLIENT_VERSION_HEADER, recordAppVersion } from "../versions.js";

/**
 * Sign-in with a 6-digit code mailed to an address, mounted at /v1/auth/email (spec 2026-11-10 §4).
 * No log line here ever carries an address, a code, a challenge id or an IP.
 */
export const emailSignInRoutes = new Hono<AppEnv>();

/**
 * What `errorKind` returns: an error code or a class name, never a message. At most 40 characters, so
 * nothing the length of a token or a challenge id (43) passes.
 */
const ERROR_KIND_RE = /^[A-Za-z][A-Za-z0-9_]{0,39}$/;

/**
 * POST /v1/auth/email/code {email, locale?} — mails a code and answers 202 with the challenge to verify
 * it against. The answer, the mail and the work are the same whether or not the address has an account:
 * this handler reads neither `users` nor `identities`. Order: 503 without a gateway (before anything is
 * counted or read), the IP limit, the address check, the two per-address limits (minute, then hour), the
 * challenge (which replaces the address's older one), the mail. A mail that cannot be sent removes its
 * challenge and answers 502; the relay never retries.
 */
emailSignInRoutes.post("/code", jsonBodyLimit, async (c) => {
  const refuse = (reason: string, error: () => ApiError): never => {
    logMeta("email_code_refused", { reason });
    throw error();
  };
  const gateway = c.get("email");
  if (gateway === null) return refuse("disabled", Errors.emailSignInDisabled);
  const limiters = c.get("limiters");
  if (!(await limiters.emailCodeIp.limit(requestIp(c)))) return refuse("rate_limited_ip", Errors.rateLimited);
  const body = await readJsonObject(c.req.raw);
  const check = checkEmail(body.email);
  if (!check.ok) return refuse(check.code, check.code === "invalid_email" ? Errors.invalidEmail : Errors.disposableEmail);
  // From here on the address is the normalized one and nothing else: limiter keys, the stored row, the mail.
  const email = check.email;
  if (!(await limiters.emailCodeEmail.limit(email))) return refuse("rate_limited_email", Errors.rateLimited);
  if (!(await limiters.emailCodeEmailHour.limit(email))) return refuse("rate_limited_email", Errors.rateLimited);
  const locale: EmailLocale = body.locale === "vi" ? "vi" : "en";
  const db = c.get("db");
  const code = c.get("emailCode")();
  const issued = await issueEmailCode(db, email, code, c.get("now")());
  if (issued === null) return refuse("too_many_live", Errors.rateLimited);

  let sent: EmailSendResult;
  try {
    sent = await gateway.send({ to: email, ...signInCodeEmail(code, locale), idempotencyKey: issued.id });
  } catch (err) {
    // A gateway must not throw; one that does has not sent the mail as far as the relay can tell.
    sent = { ok: false, error: errorKind(err) };
  }
  if (!sent.ok) {
    discardEmailCode(db, issued.id);
    // `error` is a kind such as `TimeoutError`; anything that does not look like one is not logged.
    const kind = sent.error !== undefined && ERROR_KIND_RE.test(sent.error) ? sent.error : "unknown";
    logMeta("email_send_failed", sent.status !== undefined ? { status: sent.status } : { error: kind });
    throw Errors.emailSendFailed();
  }
  logMeta("email_code_sent", { locale });
  return c.json({ challenge_id: issued.challengeId, expires_in: EMAIL_CODE_TTL_MS / 1000, resend_in: EMAIL_CODE_RESEND_SEC, email }, 202);
});

/**
 * POST /v1/auth/email/verify {challenge_id, code, device} — one guess at a challenge; the right code signs
 * the device in, with the answer of /v1/auth/google. The device is checked first, so a bad one spends no
 * guess. The code is redeemed in its own committed transaction before the account is looked at: a right
 * code is spent whatever the answer, and the address comes from the challenge row alone (the body has none).
 * The account is then resolved in a second transaction, as for Google (`matchAccount`):
 *
 * - an email sign-in for this address: sign in;
 * - an account with this address whose password still works (PASSWORD_LOGIN on): 409;
 * - an account with this address that has a Google sign-in (Google verified the address): the email sign-in
 *   is added, and nothing else of the account changes;
 * - an account with this address and no Google sign-in: its address was never verified (a legacy password
 *   account). With any other sign-in attached (an Apple ID), 409 and nothing changes. With none, the code
 *   claims it: the password and every earlier session of the account go (their live sockets are closed
 *   with 4002, as after a password change), then the email sign-in is added;
 * - no account: a new one.
 */
emailSignInRoutes.post("/verify", jsonBodyLimit, async (c) => {
  if (!(await c.get("limiters").loginIp.limit(requestIp(c)))) throw Errors.rateLimited();
  const body = await readJsonObject(c.req.raw);
  const device = parseDevice(body.device);
  if (device === null || device.kind === "agent") throw Errors.invalidDevice();
  const db = c.get("db");
  const now = c.get("now")();
  const token = generateToken();
  const tokenHash = await hashToken(token);
  const refuse = (reason: string, error: () => ApiError): never => {
    logMeta("sign_in_refused", { provider: "email", reason });
    throw error();
  };

  // The last await. When it returns the guess is counted and a right code is spent (committed); the account
  // transaction below is synchronous and reads the account afresh.
  const redeemed = await redeemEmailCode(db, body.challenge_id, body.code, now);
  if (!redeemed.ok) return refuse(redeemed.reason, redeemed.reason === "invalid_code" ? Errors.invalidCode : Errors.codeExpired);
  const verified: VerifiedIdToken = { provider: "email", subject: redeemed.email, email: redeemed.email, isPrivateEmail: false, audience: "" };
  const passwordLogin = c.get("config").passwordLogin;

  let dropped = 0;
  let claimed = false;
  let via: "identity" | "email" | "new_account" = "identity";
  const result = db.transaction(() => {
    const match = matchAccount(db, verified, passwordLogin);
    // A refusal throws: the transaction rolls back, so nothing of the account was written.
    if (match.kind === "switch_required") return refuse("switch_required", Errors.switchFromSignedInDevice);
    let userId: string;
    let identityId: string;
    if (match.kind === "identity") {
      userId = match.userId;
      identityId = match.identityId;
      db.run("UPDATE identities SET last_used_at = ? WHERE id = ?", now, identityId);
    } else if (match.kind === "email") {
      userId = match.userId;
      if (!match.hasPrimary) {
        // Nobody verified this account's address. Whoever registered it first may have attached another
        // sign-in (only an Apple ID is possible), which would stay in the account the mailbox owner enters.
        if (db.get("SELECT 1 FROM identities WHERE user_id = ?", userId) !== undefined) {
          return refuse("other_sign_in", Errors.switchFromSignedInDevice);
        }
        dropped = dropPasswordAccess(db, userId);
        dropped += db.run("DELETE FROM tokens WHERE device_id IN (SELECT id FROM devices WHERE user_id = ?)", userId).changes;
        claimed = true;
      }
      identityId = insertIdentity(db, userId, identityFromToken(verified), now);
      via = "email";
    } else {
      userId = crypto.randomUUID();
      db.run("INSERT INTO users (id, email, password_hash, password_changed_at, created_at) VALUES (?, ?, NULL, ?, ?)", userId, verified.email, now, now);
      identityId = insertIdentity(db, userId, identityFromToken(verified), now);
      via = "new_account";
    }
    const deviceId = signInDevice(db, userId, device, tokenHash, "email", identityId, now);
    return { userId, deviceId, email: accountEmail(db, userId) };
  });

  if (claimed) {
    // The earlier sessions have no token any more; a device that is connected right now would keep its
    // socket until it reconnects. Close them, as a password change does. The sign-in is committed: a hub
    // failure here must not turn it into a 500.
    try {
      await c.get("hubs").forUser(result.userId).disconnectAllExcept(result.deviceId, CloseCode.revoked);
    } catch (err) {
      logMeta("session_close_failed", { device_id: result.deviceId, error: errorKind(err) });
    }
  }
  recordAppVersion(db, result.deviceId, c.req.header(CLIENT_VERSION_HEADER));
  logMeta("sign_in", { device_id: result.deviceId, provider: "email", via });
  if (dropped > 0) logMeta("password_access_dropped", { sessions: dropped });
  return c.json({ user_id: result.userId, device_id: result.deviceId, token, email: result.email });
});

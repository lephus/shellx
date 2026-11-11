import { Hono } from "hono";
import type { AppEnv } from "../app.js";
import { requestIp } from "../auth/client-ip.js";
import { checkEmail } from "../auth/email.js";
import { discardEmailCode, EMAIL_CODE_RESEND_SEC, EMAIL_CODE_TTL_MS, issueEmailCode } from "../auth/email-codes.js";
import type { EmailSendResult } from "../email/resend.js";
import { type EmailLocale, signInCodeEmail } from "../email/sign-in-code.js";
import { jsonBodyLimit } from "../http/body-limit.js";
import { type ApiError, Errors, readJsonObject } from "../http/errors.js";
import { errorKind, logMeta } from "../log.js";

/**
 * Sign-in with a 6-digit code mailed to an address, mounted at /v1/auth/email (spec 2026-11-10 §4).
 * No log line here ever carries an address, a code, a challenge id or an IP.
 */
export const emailSignInRoutes = new Hono<AppEnv>();

/** What `errorKind` returns: an error code or a class name, never a message. */
const ERROR_KIND_RE = /^[A-Za-z][A-Za-z0-9_]{0,63}$/;

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

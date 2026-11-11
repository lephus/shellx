import { createHash, createHmac } from "node:crypto";
import { afterEach, describe, expect, it, vi } from "vitest";
import { createRateLimiters } from "../src/auth/rate-limit.js";
import { FakeEmailGateway } from "./fake-email.js";
import { call, CountingLimiter, db, deviceBody, errorCode, googleSession, makeApp, requestEmailCode, type TestApp, unlimited } from "./helpers.js";

const T0 = 1_800_000_000_000;
/** The relay's challenge key (random per process in production; injected here to check the stored values). */
const KEY = new Uint8Array(32).fill(7);
const hmac = (value: string) => createHmac("sha256", KEY).update(value, "utf8").digest();
const sha256 = (value: string) => createHash("sha256").update(value, "utf8").digest();
const ask = (app: TestApp, email: unknown, extra: Record<string, unknown> = {}, ip?: string) =>
  call(app, "POST", "/v1/auth/email/code", { ip, body: { email, ...extra } });
const codes = () => db().get<{ n: number }>("SELECT COUNT(*) AS n FROM email_codes")!.n;
afterEach(() => vi.restoreAllMocks());

describe("POST /v1/auth/email/code", () => {
  it("answers 202 with a challenge for 600 s, mails the code once, and stores neither the code nor the challenge id, only HMACs under the relay's key", async () => {
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail, now: () => T0, emailCode: () => "004217", emailCodeKey: KEY });
    const res = await ask(app, "  Ann.Lee@Example.COM ");
    expect(res.status).toBe(202);
    const body = await res.json<{ challenge_id: string }>();
    expect(body).toEqual({ challenge_id: expect.stringMatching(/^[A-Za-z0-9_-]{43}$/), expires_in: 600, resend_in: 60, email: "ann.lee@example.com" });
    const row = db().get<{ id: string }>("SELECT * FROM email_codes")!;
    expect(row).toEqual({
      id: expect.stringMatching(/^[0-9a-f-]{36}$/), challenge_hash: hmac(body.challenge_id),
      code_hash: hmac(`${body.challenge_id}:004217`), email: "ann.lee@example.com", attempts: 0, created_at: T0, expires_at: T0 + 600_000,
    });
    expect(mail.sent).toEqual([{
      to: "ann.lee@example.com", subject: "Your ShellX sign-in code is 004217", idempotencyKey: row.id,
      text: expect.stringContaining("004217"), html: expect.stringContaining("004217"),
    }]);
  });

  it("leaves a reader of the database nothing to test codes against: with the challenge id /code handed out, none of the 10^6 codes matches code_hash (review I1)", async () => {
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail, now: () => T0 }); // the relay's own key, as in production
    const { challengeId, code } = await requestEmailCode(app, mail, "victim@example.com");
    const row = db().get<{ challenge_hash: Buffer; code_hash: Buffer }>("SELECT challenge_hash, code_hash FROM email_codes")!;
    // The reviewer's probe: every six-digit code, hashed with the requester's own challenge id.
    const matches: string[] = [];
    for (let n = 0; n < 1_000_000; n++) {
      const guess = String(n).padStart(6, "0");
      if (sha256(`${challengeId}:${guess}`).equals(row.code_hash)) matches.push(guess);
    }
    expect(matches).toEqual([]);
    expect(row.challenge_hash.equals(sha256(challengeId))).toBe(false);
    // The challenge itself is sound: the mailed code signs in.
    const res = await call(app, "POST", "/v1/auth/email/verify", { body: { challenge_id: challengeId, code, device: deviceBody("mobile") } });
    expect(res.status).toBe(200);
  }, 60_000);

  it("answers the same 202 whether or not the address has an account, and touches no account", async () => {
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail, now: () => T0 });
    await googleSession(app, { email: "known@example.com" });
    const accounts = () => [db().all("SELECT * FROM users"), db().all("SELECT * FROM identities")];
    const before = accounts();
    for (const email of ["known@example.com", "nobody@example.com"]) {
      const res = await ask(app, email);
      expect(res.status).toBe(202);
      expect(await res.json()).toEqual({ challenge_id: expect.stringMatching(/^[A-Za-z0-9_-]{43}$/), expires_in: 600, resend_in: 60, email });
    }
    expect(mail.sent.map((m) => [m.to, m.subject.replace(/[0-9]{6}/, "######")])).toEqual([
      ["known@example.com", "Your ShellX sign-in code is ######"], ["nobody@example.com", "Your ShellX sign-in code is ######"],
    ]);
    expect(accounts()).toEqual(before);
  });

  it("writes the mail in Vietnamese for locale vi and in English for anything else", async () => {
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail, emailCode: () => "731946" });
    for (const locale of ["vi", "en", "fr", 7, undefined]) expect((await ask(app, `${String(locale)}@example.com`, { locale })).status).toBe(202);
    expect(mail.sent.map((m) => m.subject)).toEqual([
      "Mã đăng nhập ShellX của bạn là 731946", ...Array(4).fill("Your ShellX sign-in code is 731946"),
    ]);
  });

  it("refuses an invalid address (400 invalid_email) and a disposable one (400 disposable_email), sending nothing", async () => {
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail });
    for (const email of ["", "no-at-sign", "a@b", "ann lee@example.com", "ann@exam ple.com", "ann@example.com\nbcc: x@example.com", 42, null, undefined, ["a@example.com"]]) {
      const res = await ask(app, email);
      expect([res.status, await errorCode(res)]).toEqual([400, "invalid_email"]);
    }
    const disposable = await ask(app, "someone@Mailinator.com");
    expect([disposable.status, await errorCode(disposable)]).toEqual([400, "disposable_email"]);
    const notJson = await call(app, "POST", "/v1/auth/email/code", { body: "{oops" });
    expect([notJson.status, await errorCode(notJson)]).toEqual([400, "bad_request"]);
    expect([mail.sent.length, codes()]).toEqual([0, 0]);
  });

  it("keeps only the newest challenge of an address, also when two requests race", async () => {
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail, now: () => T0, emailCodeKey: KEY });
    const first = await requestEmailCode(app, mail, "ann.lee@example.com");
    const second = await requestEmailCode(app, mail, "ANN.LEE@example.com");
    expect(db().all("SELECT challenge_hash FROM email_codes")).toEqual([{ challenge_hash: hmac(second.challengeId) }]);
    expect(first.challengeId).not.toBe(second.challengeId);
    const raced = await Promise.all([ask(app, "bob@example.com"), ask(app, "bob@example.com"), ask(app, "bob@example.com")]);
    expect(raced.map((r) => r.status)).toEqual([202, 202, 202]);
    expect(db().get("SELECT COUNT(*) AS n FROM email_codes WHERE email = 'bob@example.com'")).toEqual({ n: 1 });
  });

  it("limits by IP, and by the normalized address per minute and per hour: every spelling of an address shares one budget", async () => {
    const mail = new FakeEmailGateway();
    const emailCodeIp = new CountingLimiter(100);
    const emailCodeEmail = new CountingLimiter(2);
    const emailCodeEmailHour = new CountingLimiter(100);
    const app = makeApp({ email: mail, limiters: { ...unlimited, emailCodeIp, emailCodeEmail, emailCodeEmailHour } });
    const statuses: number[] = [];
    for (const spelling of ["Ann.Lee@Example.com", "  ann.lee@example.com ", "ANN.LEE@EXAMPLE.COM"]) statuses.push((await ask(app, spelling, {}, "198.51.100.9")).status);
    expect(statuses).toEqual([202, 202, 429]);
    expect(emailCodeIp.calls).toEqual(Array(3).fill("198.51.100.9"));
    expect(emailCodeEmail.calls).toEqual(Array(3).fill("ann.lee@example.com"));
    expect(emailCodeEmailHour.calls).toEqual(Array(2).fill("ann.lee@example.com"));
    expect(mail.sent).toHaveLength(2);
    expect(db().all("SELECT email FROM email_codes")).toEqual([{ email: "ann.lee@example.com" }]);

    const hourly = makeApp({ email: mail, limiters: { ...unlimited, emailCodeEmailHour: new CountingLimiter(1) } });
    expect([(await ask(hourly, "bob@example.com")).status, (await ask(hourly, "Bob@example.com")).status]).toEqual([202, 429]);
    const perIp = makeApp({ email: mail, limiters: { ...unlimited, emailCodeIp: new CountingLimiter(1) } });
    expect([(await ask(perIp, "c1@example.com")).status, (await ask(perIp, "c2@example.com")).status]).toEqual([202, 429]);
    expect(await errorCode(await ask(perIp, "not an address"))).toBe("rate_limited"); // counted before the body is read
  });

  it("in production allows 3 codes per address per minute, 10 per address per hour and 10 per IP per minute", async () => {
    let now = T0;
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail, now: () => now, limiters: createRateLimiters({ rateLimitsEnabled: true }, () => now) });
    const from = (n: number) => `198.51.100.${n}`;
    const burst = async (email: string, ip: string) => {
      const statuses: number[] = [];
      for (let i = 0; i < 4; i++) statuses.push((await ask(app, email, {}, ip)).status);
      return statuses;
    };
    expect(await burst("ann@example.com", from(1))).toEqual([202, 202, 202, 429]);
    now += 60_000;
    expect(await burst("ann@example.com", from(2))).toEqual([202, 202, 202, 429]);
    now += 60_000;
    expect(await burst("ann@example.com", from(3))).toEqual([202, 202, 202, 429]);
    now += 60_000;
    expect(await burst("ann@example.com", from(4))).toEqual([202, 429, 429, 429]); // the 10th of the hour, then the hourly limit
    now += 60_000;
    expect((await ask(app, "bob@example.com", {}, from(4))).status).toBe(202); // another address is not affected
    now = T0 + 3_600_000;
    expect((await ask(app, "ann@example.com", {}, from(5))).status).toBe(202);
    const perIp: number[] = [];
    for (let i = 0; i < 11; i++) perIp.push((await ask(app, `user${i}@example.com`, {}, from(6))).status);
    expect(perIp).toEqual([...Array(10).fill(202), 429]);
  });

  it("answers 429 while 50 000 challenges are live", async () => {
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail, now: () => T0 });
    db().run(`WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 50000)
              INSERT INTO email_codes (id, challenge_hash, code_hash, email, created_at, expires_at)
              SELECT 'seed-' || i, randomblob(32), randomblob(32), 'seed-' || i || '@example.com', ?, ? FROM n`, T0, T0 + 600_000);
    const res = await ask(app, "ann@example.com");
    expect([res.status, await errorCode(res), mail.sent.length]).toEqual([429, "rate_limited", 0]);
  });

  it("answers 503 email_sign_in_disabled without a gateway, before anything is counted or stored", async () => {
    const emailCodeIp = new CountingLimiter(100);
    const app = makeApp({ limiters: { ...unlimited, emailCodeIp } });
    for (const email of ["ann@example.com", "not an address"]) {
      const res = await ask(app, email);
      expect([res.status, await errorCode(res)]).toEqual([503, "email_sign_in_disabled"]);
    }
    expect([emailCodeIp.calls.length, codes()]).toEqual([0, 0]);
  });

  it("answers 502 email_send_failed when the mail cannot be sent, and leaves no challenge behind", async () => {
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail, now: () => T0 });
    await requestEmailCode(app, mail, "ann@example.com");
    for (const result of [{ ok: false, status: 500 }, { ok: false, error: "TimeoutError" }] as const) {
      mail.result = result;
      const res = await ask(app, "ann@example.com");
      expect([res.status, await errorCode(res)]).toEqual([502, "email_send_failed"]);
      expect(await res.json()).toEqual({ error: { code: "email_send_failed", message: expect.any(String) } });
      expect(codes()).toBe(0);
    }
    const throwing = makeApp({ email: { send: async () => { throw new Error("boom ann@example.com"); } } });
    expect((await ask(throwing, "ann@example.com")).status).toBe(502);
    expect(codes()).toBe(0);
  });

  it("logs events without the address, the code, the challenge id or the IP", async () => {
    const lines: string[] = [];
    for (const level of ["log", "info", "warn", "error"] as const) vi.spyOn(console, level).mockImplementation((...args: unknown[]) => void lines.push(args.map(String).join(" ")));
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail, emailCode: () => "731946", limiters: { ...unlimited, emailCodeEmail: new CountingLimiter(2) } });
    const sent = await requestEmailCode(app, mail, "secret.mailbox@example.com", { locale: "vi", ip: "198.51.100.77" });
    mail.result = { ok: false, status: 422 };
    await ask(app, "secret.mailbox@example.com", {}, "198.51.100.77");
    await ask(app, "secret.mailbox@example.com", {}, "198.51.100.77");
    await ask(app, "secret.mailbox@mailinator.com", {}, "198.51.100.77");
    const output = lines.map((line) => line.replace(/"ts":[0-9]+,?/, "")).join("\n");
    for (const event of ['"event":"email_code_sent","locale":"vi"', '"event":"email_send_failed","status":422', '"event":"email_code_refused","reason":"rate_limited_email"', '"event":"email_code_refused","reason":"disposable_email"']) {
      expect(output).toContain(event);
    }
    for (const secret of ["secret.mailbox", "731946", sent.challengeId, "198.51.100.77"]) expect(output).not.toContain(secret);
    expect(output).not.toMatch(/[A-Za-z0-9_-]{43,}/);
  });
});

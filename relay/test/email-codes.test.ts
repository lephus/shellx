import { describe, expect, it } from "vitest";
import {
  discardEmailCode, EMAIL_CODE_MAX_ATTEMPTS, EMAIL_CODE_TTL_MS, generateEmailCode, issueEmailCode, MAX_LIVE_EMAIL_CODES, redeemEmailCode,
} from "../src/auth/email-codes.js";
import { hashToken } from "../src/auth/tokens.js";
import { db } from "./helpers.js";

const T0 = 1_800_000_000_000;
const EMAIL = "ann.lee@example.com";
const rows = () => db().get<{ n: number }>("SELECT COUNT(*) AS n FROM email_codes")!.n;
const issue = async (code = "048213", email = EMAIL, now = T0) => (await issueEmailCode(db(), email, code, now))!;

describe("email codes", () => {
  it("generates six digits, zero-padded", () => {
    const codes = Array.from({ length: 2000 }, generateEmailCode);
    for (const code of codes) expect(code).toMatch(/^[0-9]{6}$/);
    expect(new Set(codes).size).toBeGreaterThan(1900);
  });

  it("stores only SHA-256 of the challenge id and of `challenge_id:code`, for 600 s", async () => {
    const { id, challengeId } = await issue();
    expect(challengeId).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(id).toMatch(/^[0-9a-f-]{36}$/);
    expect([EMAIL_CODE_TTL_MS, EMAIL_CODE_MAX_ATTEMPTS, MAX_LIVE_EMAIL_CODES]).toEqual([600_000, 5, 50_000]);
    expect(db().get("SELECT * FROM email_codes")).toEqual({
      id, challenge_hash: Buffer.from(await hashToken(challengeId)), code_hash: Buffer.from(await hashToken(`${challengeId}:048213`)),
      email: EMAIL, attempts: 0, created_at: T0, expires_at: T0 + 600_000,
    });
  });

  it("redeems the right code once; a used challenge is gone", async () => {
    const { challengeId } = await issue();
    expect(await redeemEmailCode(db(), challengeId, "048213", T0 + 1)).toEqual({ ok: true, email: EMAIL });
    expect(rows()).toBe(0);
    expect(await redeemEmailCode(db(), challengeId, "048213", T0 + 2)).toEqual({ ok: false, reason: "code_expired" });
  });

  it("counts every guess before comparing: four wrong ones leave the challenge, the fifth guess may still be right, a fifth wrong one burns it", async () => {
    const a = await issue();
    for (let n = 1; n <= 4; n++) {
      expect(await redeemEmailCode(db(), a.challengeId, "000000", T0)).toEqual({ ok: false, reason: "invalid_code" });
      expect(db().get("SELECT attempts FROM email_codes")).toEqual({ attempts: n });
    }
    expect(await redeemEmailCode(db(), a.challengeId, "048213", T0)).toEqual({ ok: true, email: EMAIL });

    const b = await issue();
    for (let n = 1; n <= 4; n++) await redeemEmailCode(db(), b.challengeId, "000000", T0);
    expect(await redeemEmailCode(db(), b.challengeId, "000000", T0)).toEqual({ ok: false, reason: "code_expired" });
    expect(rows()).toBe(0);
    expect(await redeemEmailCode(db(), b.challengeId, "048213", T0)).toEqual({ ok: false, reason: "code_expired" });
  });

  it("never redeems a code that is not the six-digit string, an unknown or malformed challenge id, or anything at or after the expiry", async () => {
    for (const code of [48213, "48213", "0482130", " 048213", null, undefined]) {
      const fresh = await issue();
      expect(await redeemEmailCode(db(), fresh.challengeId, code, T0)).toEqual({ ok: false, reason: "invalid_code" });
      expect(db().get("SELECT attempts FROM email_codes")).toEqual({ attempts: 1 });
    }
    const live = await issue();
    for (const id of [live.challengeId.slice(1), `${live.challengeId}x`, "n".repeat(43), 42, null, undefined]) {
      expect(await redeemEmailCode(db(), id, "048213", T0)).toEqual({ ok: false, reason: "code_expired" });
    }
    expect(db().get("SELECT attempts FROM email_codes")).toEqual({ attempts: 0 });
    expect(await redeemEmailCode(db(), live.challengeId, "048213", T0 + 600_000)).toEqual({ ok: false, reason: "code_expired" });
    expect(rows()).toBe(0);
    const late = await issue();
    await issue("333333", "bob@example.com", T0 - 1);
    expect(await redeemEmailCode(db(), late.challengeId, "048213", T0 + 599_999)).toEqual({ ok: true, email: EMAIL });
    expect(rows()).toBe(0); // bob's expired row went with it
  });

  it("keeps one live challenge per address: a new one replaces the old; other addresses are untouched", async () => {
    const first = await issue("111111");
    const other = await issue("333333", "bob@example.com");
    const second = await issue("222222");
    expect(rows()).toBe(2);
    expect(await redeemEmailCode(db(), first.challengeId, "111111", T0)).toEqual({ ok: false, reason: "code_expired" });
    expect(await redeemEmailCode(db(), second.challengeId, "222222", T0)).toEqual({ ok: true, email: EMAIL });
    expect(await redeemEmailCode(db(), other.challengeId, "333333", T0)).toEqual({ ok: true, email: "bob@example.com" });
  });

  it("deletes expired rows when the next code is issued, refuses a new one while 50 000 are live, and discards by id", async () => {
    db().run(`WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 50000)
              INSERT INTO email_codes (id, challenge_hash, code_hash, email, created_at, expires_at)
              SELECT 'seed-' || i, randomblob(32), randomblob(32), 'seed-' || i || '@example.com', ?, ? FROM n`, T0, T0 + 600_000);
    expect(await issueEmailCode(db(), EMAIL, "048213", T0)).toBeNull();
    expect(rows()).toBe(50_000);
    const issued = await issueEmailCode(db(), EMAIL, "048213", T0 + 600_000);
    expect(rows()).toBe(1);
    discardEmailCode(db(), issued!.id);
    expect(rows()).toBe(0);
  });

  it("lets exactly one of several concurrent redeems of a challenge succeed, and never compares more than five guesses", async () => {
    const right = await issue();
    const results = await Promise.all(Array.from({ length: 6 }, () => redeemEmailCode(db(), right.challengeId, "048213", T0)));
    expect(results.map((r) => (r.ok ? "ok" : r.reason)).sort()).toEqual([...Array(5).fill("code_expired"), "ok"]);

    const wrong = await issue();
    const guesses = await Promise.all(Array.from({ length: 9 }, (_, i) => redeemEmailCode(db(), wrong.challengeId, `00000${i}`, T0)));
    expect(guesses.map((r) => (r.ok ? "ok" : r.reason)).sort()).toEqual([...Array(5).fill("code_expired"), ...Array(4).fill("invalid_code")]);
    expect(await redeemEmailCode(db(), wrong.challengeId, "048213", T0)).toEqual({ ok: false, reason: "code_expired" });
  });
});

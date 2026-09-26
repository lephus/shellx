import { describe, expect, it } from "vitest";
import { parseBlocklist, renderDomainsJson } from "../scripts/blocklist.js";
import disposableDomains from "../src/auth/disposable-domains.json" with { type: "json" };
import { checkEmail, isDisposableDomain, isValidEmail, normalizeEmail } from "../src/auth/email.js";
import { isAcceptablePassword } from "../src/auth/password-policy.js";

describe("email normalisation and validation", () => {
  it("trims whitespace (including NBSP and newlines) and lowercases", () => {
    expect(normalizeEmail("  Alice.Nguyen@Example.COM \n")).toBe("alice.nguyen@example.com");
    expect(checkEmail(" Bob@Example.com\t")).toEqual({ ok: true, email: "bob@example.com" });
  });

  it.each([
    "user@example.com", "first.last+tag@sub.example.co", "o'brien@example.org", "a@b.io", "x_y-z@my-domain.vn",
  ])("accepts %s", (email) => {
    expect(isValidEmail(email)).toBe(true);
  });

  it.each([
    "", "plainaddress", "@example.com", "user@", "user@example", "user@@example.com", "user name@example.com",
    ".user@example.com", "user.@example.com", "us..er@example.com", "user@-example.com", "user@example-.com",
    "user@example.c", "user@example.com.", "user@exa_mple.com", "nguyễn@example.com", `${"a".repeat(65)}@example.com`,
    `a@${"b".repeat(63)}.${"c".repeat(63)}.${"d".repeat(63)}.${"e".repeat(60)}.com`,
  ])("rejects %j", (email) => {
    expect(isValidEmail(email)).toBe(false);
  });

  it("reports invalid_email for non-strings", () => {
    expect(checkEmail(undefined)).toEqual({ ok: false, code: "invalid_email" });
    expect(checkEmail(42)).toEqual({ ok: false, code: "invalid_email" });
  });
});

describe("disposable domains", () => {
  it("ships a bundled list that includes well-known providers", () => {
    expect(disposableDomains.length).toBeGreaterThan(1000);
    expect(disposableDomains).toContain("yopmail.com");
    expect(disposableDomains).toContain("mailinator.com");
  });

  it("blocks the domain itself and every subdomain of it", () => {
    expect(isDisposableDomain("yopmail.com")).toBe(true);
    expect(isDisposableDomain("x.yopmail.com")).toBe(true);
    expect(isDisposableDomain("a.b.c.mailinator.com")).toBe(true);
    expect(isDisposableDomain("example.com")).toBe(false);
    expect(isDisposableDomain("notyopmail.com")).toBe(false);
  });

  it("classifies after normalisation: uppercase / padded subdomain addresses are still disposable", () => {
    expect(checkEmail("  Someone@X.YOPMAIL.COM ")).toEqual({ ok: false, code: "disposable_email" });
    expect(checkEmail("someone@mailinator.com")).toEqual({ ok: false, code: "disposable_email" });
  });
});

describe("blocklist parsing (scripts/blocklist.ts)", () => {
  it("drops comments and blanks, lowercases, dedupes and sorts", () => {
    const parsed = parseBlocklist("# comment\r\nZZZ.example\n\n  yopmail.com  \nYOPMAIL.com\naaa.example\n");
    expect(parsed).toEqual(["aaa.example", "yopmail.com", "zzz.example"]);
  });
  it("renders one domain per line as valid JSON", () => {
    const json = renderDomainsJson(["a.example", "b.example"]);
    expect(json).toBe('[\n  "a.example",\n  "b.example"\n]\n');
    expect(JSON.parse(json)).toEqual(["a.example", "b.example"]);
  });
});

describe("password policy", () => {
  it("accepts 8..128 characters counted as code points", () => {
    expect(isAcceptablePassword("12345678")).toBe(true);
    expect(isAcceptablePassword("x".repeat(128))).toBe(true);
    expect(isAcceptablePassword("🔑".repeat(128))).toBe(true); // 256 UTF-16 units, 128 characters
    expect(isAcceptablePassword("mật khẩu")).toBe(true); // 8 characters
  });
  it("rejects too short, too long and non-strings", () => {
    expect(isAcceptablePassword("1234567")).toBe(false);
    expect(isAcceptablePassword("x".repeat(129))).toBe(false);
    expect(isAcceptablePassword("🔑".repeat(129))).toBe(false);
    expect(isAcceptablePassword(12345678)).toBe(false);
    expect(isAcceptablePassword(undefined)).toBe(false);
  });
  it("counts an NFD-typed Vietnamese password by its NFC length", () => {
    const nfd = "mật khẩu".normalize("NFD"); // more than 8 code points before normalisation
    expect([...nfd].length).toBeGreaterThan(8);
    expect(isAcceptablePassword(nfd)).toBe(true);
    expect(isAcceptablePassword("mật khẩ".normalize("NFD"))).toBe(false);
  });
});

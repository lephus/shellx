import { describe, expect, it } from "vitest";
import { decodeB64, fingerprint, newSlot, unixSeconds } from "../src/v2/encoding.js";

const key = new Uint8Array(32).map((_, i) => i * 8 + 1);
const std = Buffer.from(key).toString("base64");
const url = Buffer.from(key).toString("base64url");

describe("v2 encoding", () => {
  it("fingerprint of 32 zero bytes", () => {
    expect(fingerprint(new Uint8Array(32))).toBe("66687aadf862bd77");
  });
  it("newSlot is 22 url-safe chars and unique", () => {
    const a = newSlot();
    expect(a).toMatch(/^[A-Za-z0-9_-]{22}$/);
    expect(newSlot()).not.toBe(a);
  });
  it("unixSeconds floors", () => {
    expect(unixSeconds(1_760_000_000_999)).toBe(1_760_000_000);
  });
  it("decodeB64 accepts standard, unpadded and url forms", () => {
    expect(std).toMatch(/=$/);
    for (const v of [std, std.replace(/=+$/, ""), url]) {
      expect(Buffer.from(decodeB64(v, 32, 32)!).equals(Buffer.from(key))).toBe(true);
    }
  });
  it("decodeB64 rejects bad input", () => {
    expect(decodeB64("a b", 1, 10)).toBeNull();
    expect(decodeB64("ab$c", 1, 10)).toBeNull();
    expect(decodeB64("a+b_", 1, 10)).toBeNull();
    expect(decodeB64(Buffer.alloc(31).toString("base64"), 32, 32)).toBeNull();
    expect(decodeB64(Buffer.alloc(33).toString("base64"), 32, 32)).toBeNull();
    for (const v of [null, undefined, 5, {}, []]) expect(decodeB64(v, 0, 10)).toBeNull();
  });
});

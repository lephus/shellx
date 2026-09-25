import argon2Module from "@phi-ag/argon2/argon2.wasm";
import { describe, expect, it } from "vitest";
import { createArgon2 } from "../src/auth/argon2";
import { hashPassword, verifyPassword } from "../src/auth/password";

// Known answers computed independently with Node's crypto.argon2Sync and @noble/hashes argon2id.
const SALT = new TextEncoder().encode("shellx-kat-salt!");
const KAT_ASCII =
  "$argon2id$v=19$m=19456,t=2,p=1$c2hlbGx4LWthdC1zYWx0IQ$luGaBaUIJTDe62MbzyomlSXbM2S500nqgv2BH+y/TeA";
const KAT_VIETNAMESE =
  "$argon2id$v=19$m=19456,t=2,p=1$c2hlbGx4LWthdC1zYWx0IQ$V9qO2xHVO7Iw1zYXHNX5/Txu9PgL0V1DtJajq+T+7vk";

describe("argon2id (static WASM in workerd)", () => {
  it("matches the ASCII known-answer vector", async () => {
    const argon2 = await createArgon2(argon2Module);
    expect(argon2.hash("correct horse battery", SALT)).toBe(KAT_ASCII);
  });

  it("hashes every UTF-8 byte of a Vietnamese password", async () => {
    const argon2 = await createArgon2(argon2Module);
    expect(argon2.hash("mậtkhẩuđẹplắm1", SALT)).toBe(KAT_VIETNAMESE);
  });

  it("produces a PHC string with the spec parameters and verifies it", async () => {
    const phc = await hashPassword("correct horse battery");
    expect(phc).toMatch(/^\$argon2id\$v=19\$m=19456,t=2,p=1\$[A-Za-z0-9+/]{22}\$[A-Za-z0-9+/]{43}$/);
    expect(await verifyPassword("correct horse battery", phc)).toBe(true);
    expect(await verifyPassword("correct horse batterY", phc)).toBe(false);
  });

  it("rejects a password that only shares a UTF-16-length prefix", async () => {
    const phc = await hashPassword("mậtkhẩuđẹplắm1");
    expect(await verifyPassword("mậtkhẩuđẹpXXXX", phc)).toBe(false);
  });

  it("treats NFC and NFD spellings of the same password as equal", async () => {
    const nfc = "Mật khẩu 2026".normalize("NFC");
    const nfd = nfc.normalize("NFD");
    expect(nfd).not.toBe(nfc);
    const phc = await hashPassword(nfd);
    expect(await verifyPassword(nfc, phc)).toBe(true);
  });

  it("returns false for malformed PHC strings", async () => {
    expect(await verifyPassword("whatever1", "")).toBe(false);
    expect(await verifyPassword("whatever1", "not-a-phc")).toBe(false);
    expect(await verifyPassword("whatever1", "$argon2id$v=19$m=19456,t=2,p=1$garbage")).toBe(false);
    expect(await verifyPassword("whatever1", KAT_ASCII.replace("$argon2id$", "$argon2i$"))).toBe(false);
  });

  it("hash + verify stays within the 500 ms budget (median of 5)", async () => {
    await hashPassword("warm-up-password"); // instantiate the module outside the measurement
    const samples: number[] = [];
    for (let i = 0; i < 5; i++) {
      const started = performance.now();
      const phc = await hashPassword("correct horse battery");
      await verifyPassword("correct horse battery", phc);
      samples.push(performance.now() - started);
    }
    samples.sort((a, b) => a - b);
    const median = samples[2]!;
    console.log(JSON.stringify({ event: "argon2_timing", median_ms: median, samples_ms: samples }));
    expect(median).toBeGreaterThan(0);
    expect(median).toBeLessThan(500);
  });
});

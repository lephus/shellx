import argon2Module from "@phi-ag/argon2/argon2.wasm";
import { describe, expect, it } from "vitest";
import { ARGON2_SALT_BYTES, buildArgon2, createArgon2, type Argon2Exports } from "../src/auth/argon2.js";
import { hashPassword, verifyPassword } from "../src/auth/password.js";

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

/**
 * A fake `Argon2Exports` backed by a plain ArrayBuffer "heap" and a bump allocator,
 * so tests can force `malloc` to fail on a chosen call (simulating real WASM
 * allocation failure) without needing to exhaust the real WASM instance's memory.
 */
function makeFakeExports(opts: { failMallocOnCall: number }): {
  ex: Argon2Exports;
  freed: number[];
  heap: () => Uint8Array;
} {
  const buffer = new ArrayBuffer(1 << 16);
  const freed: number[] = [];
  let nextPtr = 8; // keep 0 reserved for "null"/allocation failure
  let mallocCalls = 0;

  const ex: Argon2Exports = {
    memory: { buffer } as unknown as WebAssembly.Memory,
    _initialize() {},
    malloc(size) {
      mallocCalls++;
      if (mallocCalls === opts.failMallocOnCall) return 0;
      const ptr = nextPtr;
      nextPtr += Math.max(size, 1);
      return ptr;
    },
    free(ptr) {
      freed.push(ptr);
    },
    argon2_hash() {
      throw new Error("argon2_hash must not run once an earlier allocation has failed");
    },
    argon2_verify() {
      throw new Error("argon2_verify must not run once an earlier allocation has failed");
    },
    argon2_encodedlen() {
      return 128;
    },
  };

  return { ex, freed, heap: () => new Uint8Array(buffer) };
}

describe("argon2 buffer cleanup on allocation failure", () => {
  it("wipes and frees the password buffer when a later allocation fails during hash()", () => {
    // 1st malloc call copies in the password (succeeds); 2nd copies in the salt (fails).
    const { ex, freed, heap } = makeFakeExports({ failMallocOnCall: 2 });
    const argon2 = buildArgon2(ex);
    const password = "correct horse battery";
    const passwordBytes = new TextEncoder().encode(password.normalize("NFC"));

    expect(() => argon2.hash(password, new Uint8Array(ARGON2_SALT_BYTES))).toThrow("argon2: out of memory");

    // The password pointer (the first, and only successful, allocation) must have
    // been freed, and its bytes zeroed before that free — not leaked in the heap.
    expect(freed).toEqual([8]);
    expect(heap().subarray(8, 8 + passwordBytes.length)).toEqual(new Uint8Array(passwordBytes.length));
  });

  it("wipes and frees the password buffer when a later allocation fails during verify()", () => {
    // 1st malloc call copies in the password (succeeds); 2nd copies in the encoded PHC (fails).
    const { ex, freed, heap } = makeFakeExports({ failMallocOnCall: 2 });
    const argon2 = buildArgon2(ex);
    const password = "whatever1";
    const passwordBytes = new TextEncoder().encode(password.normalize("NFC"));

    expect(() => argon2.verify(password, "$argon2id$v=19$m=19456,t=2,p=1$c2FsdA$aGFzaA")).toThrow(
      "argon2: out of memory",
    );

    expect(freed).toEqual([8]);
    expect(heap().subarray(8, 8 + passwordBytes.length)).toEqual(new Uint8Array(passwordBytes.length));
  });

  it("propagates the error without freeing anything when the very first allocation fails", () => {
    // 1st malloc call (the password buffer itself) fails immediately.
    const { ex, freed } = makeFakeExports({ failMallocOnCall: 1 });
    const argon2 = buildArgon2(ex);

    expect(() => argon2.hash("correct horse battery")).toThrow("argon2: out of memory");
    expect(freed).toEqual([]);
  });
});

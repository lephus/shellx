import { describe, expect, it } from "vitest";
import {
  type Argon2Backend, createPasswordHasher, hashPassword, MAX_CONCURRENT_HASHES, nodeArgon2, passwordBytes, Semaphore,
  verifyPassword,
} from "../src/auth/password.js";

// Known answers computed with the relay's former argon2 WASM build and cross-checked with Node's
// crypto.argon2Sync and @noble/hashes: hashes stored by the Cloudflare relay still verify.
const SALT = new TextEncoder().encode("shellx-kat-salt!");
const KAT_ASCII =
  "$argon2id$v=19$m=19456,t=2,p=1$c2hlbGx4LWthdC1zYWx0IQ$luGaBaUIJTDe62MbzyomlSXbM2S500nqgv2BH+y/TeA";
const KAT_VIETNAMESE =
  "$argon2id$v=19$m=19456,t=2,p=1$c2hlbGx4LWthdC1zYWx0IQ$V9qO2xHVO7Iw1zYXHNX5/Txu9PgL0V1DtJajq+T+7vk";

describe("argon2id (@node-rs/argon2)", () => {
  it("matches the ASCII known-answer vector", async () => {
    expect(await nodeArgon2.hash(passwordBytes("correct horse battery"), SALT)).toBe(KAT_ASCII);
  });

  it("hashes every UTF-8 byte of a Vietnamese password", async () => {
    expect(await nodeArgon2.hash(passwordBytes("mậtkhẩuđẹplắm1"), SALT)).toBe(KAT_VIETNAMESE);
  });

  it("verifies hashes written by the former WASM implementation", async () => {
    expect(await verifyPassword("correct horse battery", KAT_ASCII)).toBe(true);
    expect(await verifyPassword("mậtkhẩuđẹplắm1", KAT_VIETNAMESE)).toBe(true);
    expect(await verifyPassword("correct horse batterY", KAT_ASCII)).toBe(false);
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

  it("returns false (never throws) for malformed or non-argon2id PHC strings", async () => {
    expect(await verifyPassword("whatever1", "")).toBe(false);
    expect(await verifyPassword("whatever1", "not-a-phc")).toBe(false);
    expect(await verifyPassword("whatever1", "$argon2id$v=19$m=19456,t=2,p=1$garbage")).toBe(false);
    expect(await verifyPassword("whatever1", KAT_ASCII.replace("$argon2id$", "$argon2i$"))).toBe(false);
  });

  it("hash + verify stays within the 500 ms budget (median of 5)", async () => {
    await hashPassword("warm-up-password");
    const samples: number[] = [];
    for (let i = 0; i < 5; i++) {
      const started = performance.now();
      const phc = await hashPassword("correct horse battery");
      await verifyPassword("correct horse battery", phc);
      samples.push(performance.now() - started);
    }
    samples.sort((a, b) => a - b);
    expect(samples[2]!).toBeGreaterThan(0);
    expect(samples[2]!).toBeLessThan(500);
  });
});

/** A backend whose operations finish only when the test says so, recording how many ran at once. */
function gatedBackend() {
  const gates: (() => void)[] = [];
  let running = 0;
  let peak = 0;
  const run = async <T>(value: T): Promise<T> => {
    running++;
    peak = Math.max(peak, running);
    await new Promise<void>((resolve) => gates.push(resolve));
    running--;
    return value;
  };
  const backend: Argon2Backend = {
    hash: () => run("$argon2id$v=19$m=19456,t=2,p=1$c2FsdHNhbHRzYWx0c2FsdA$aGFzaA"),
    verify: () => run(true),
  };
  return {
    backend,
    started: () => gates.length,
    peak: () => peak,
    releaseOne: () => gates.shift()?.(),
  };
}

const tick = () => new Promise((resolve) => setImmediate(resolve));

describe("concurrency cap (risk R-VPS4)", () => {
  it("runs at most 4 hashes at once; the 5th waits for a free slot", async () => {
    expect(MAX_CONCURRENT_HASHES).toBe(4);
    const gated = gatedBackend();
    const hasher = createPasswordHasher(gated.backend);
    const results = Array.from({ length: 5 }, (_, i) => hasher.hash(`password-${i}`));
    await tick();
    expect(gated.started()).toBe(4);

    gated.releaseOne();
    await tick();
    expect(gated.started()).toBe(4); // three still running + the 5th, which just started

    for (let i = 0; i < 4; i++) {
      gated.releaseOne();
      await tick();
    }
    await Promise.all(results);
    expect(gated.peak()).toBe(4);
  });

  it("counts verifications against the same cap as hashes", async () => {
    const gated = gatedBackend();
    const hasher = createPasswordHasher(gated.backend);
    const work = [
      hasher.hash("a-password"),
      hasher.verify("b-password", "$argon2id$v=19$m=19456,t=2,p=1$c2FsdHNhbHRzYWx0c2FsdA$aGFzaA"),
      hasher.hash("c-password"),
      hasher.verify("d-password", "$argon2id$v=19$m=19456,t=2,p=1$c2FsdHNhbHRzYWx0c2FsdA$aGFzaA"),
      hasher.verify("e-password", "$argon2id$v=19$m=19456,t=2,p=1$c2FsdHNhbHRzYWx0c2FsdA$aGFzaA"),
    ];
    await tick();
    expect(gated.started()).toBe(4);
    while (gated.started() > 0) {
      gated.releaseOne();
      await tick();
    }
    await Promise.all(work);
    expect(gated.peak()).toBe(4);
  });

  it("frees the slot when an operation fails", async () => {
    const slots = new Semaphore(1);
    await expect(slots.run(async () => {
      throw new Error("backend failed");
    })).rejects.toThrow("backend failed");
    expect(await slots.run(async () => "next")).toBe("next");
    expect(slots.running).toBe(0);
    expect(slots.queued).toBe(0);
  });
});

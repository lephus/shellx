import { hash, verify } from "@node-rs/argon2";

// Spec §5.2 / VPS spec §4.2: argon2id, m = 19456 KiB, t = 2, p = 1, 32-byte hash, PHC string.
export const ARGON2_MEMORY_KIB = 19456;
export const ARGON2_ITERATIONS = 2;
export const ARGON2_PARALLELISM = 1;
export const ARGON2_HASH_BYTES = 32;
/** Hashes running at once; the next one waits. Bounds argon2 RAM to 4 × 19 MiB (risk R-VPS4). */
export const MAX_CONCURRENT_HASHES = 4;

/** `Algorithm.Argon2id` and `Version.V0x13` of @node-rs/argon2 (declared as const enums, so not importable). */
const ARGON2ID = 2;
const VERSION_0X13 = 1;

const OPTIONS = {
  algorithm: ARGON2ID,
  version: VERSION_0X13,
  memoryCost: ARGON2_MEMORY_KIB,
  timeCost: ARGON2_ITERATIONS,
  parallelism: ARGON2_PARALLELISM,
  outputLen: ARGON2_HASH_BYTES,
};

export interface PasswordHasher {
  /** Returns a PHC string `$argon2id$v=19$m=19456,t=2,p=1$<salt>$<hash>`. */
  hash(password: string): Promise<string>;
  /** False for a wrong password and for any malformed or non-argon2id PHC string; never throws for those. */
  verify(password: string, phc: string): Promise<boolean>;
}

/** The raw argon2 operations, injectable so tests can observe the concurrency cap. */
export interface Argon2Backend {
  hash(password: Uint8Array, salt?: Uint8Array): Promise<string>;
  verify(phc: string, password: Uint8Array): Promise<boolean>;
}

export const nodeArgon2: Argon2Backend = {
  hash: (password, salt) => hash(password, salt === undefined ? OPTIONS : { ...OPTIONS, salt }),
  verify: (phc, password) => verify(phc, password),
};

/** Same password typed on macOS (may be NFD) and on a phone (NFC) must match; every UTF-8 byte counts. */
export function passwordBytes(password: string): Uint8Array {
  return Buffer.from(password.normalize("NFC"), "utf8");
}

/** A counting semaphore: at most `limit` holders; later callers wait in FIFO order. */
export class Semaphore {
  private active = 0;
  private readonly waiting: (() => void)[] = [];

  constructor(private readonly limit: number) {}

  get running(): number {
    return this.active;
  }

  get queued(): number {
    return this.waiting.length;
  }

  async run<T>(task: () => Promise<T>): Promise<T> {
    if (this.active >= this.limit) await new Promise<void>((resolve) => this.waiting.push(resolve));
    else this.active++;
    try {
      return await task();
    } finally {
      const next = this.waiting.shift();
      if (next === undefined) this.active--;
      else next(); // the slot passes straight to the next waiter
    }
  }
}

export function createPasswordHasher(
  backend: Argon2Backend = nodeArgon2,
  maxConcurrent: number = MAX_CONCURRENT_HASHES,
): PasswordHasher {
  const slots = new Semaphore(maxConcurrent);
  return {
    hash: (password) => slots.run(() => backend.hash(passwordBytes(password))),
    async verify(password, phc) {
      if (!phc.startsWith("$argon2id$")) return false;
      try {
        return await slots.run(() => backend.verify(phc, passwordBytes(password)));
      } catch {
        return false; // malformed PHC ("Decoding failed")
      }
    },
  };
}

/** The process-wide hasher (4 concurrent hashes). */
export const passwords = createPasswordHasher();

export function hashPassword(password: string): Promise<string> {
  return passwords.hash(password);
}

export function verifyPassword(password: string, phc: string): Promise<boolean> {
  return passwords.verify(password, phc);
}

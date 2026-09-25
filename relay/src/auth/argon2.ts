// Thin wrapper over the raw C exports of the argon2 reference implementation
// compiled to WebAssembly (the `argon2.wasm` file shipped by @phi-ag/argon2).
// We intentionally do NOT use the package's JS class: it passes
// `password.length` (UTF-16 code units) as the byte length, which silently
// truncates non-ASCII passwords (e.g. Vietnamese) before hashing.

export const ARGON2_MEMORY_KIB = 19456;
export const ARGON2_ITERATIONS = 2;
export const ARGON2_PARALLELISM = 1;
export const ARGON2_HASH_BYTES = 32;
export const ARGON2_SALT_BYTES = 16;

const ARGON2_TYPE_ID = 2;
const ARGON2_VERSION_13 = 0x13;
const ARGON2_OK = 0;

interface Argon2Exports {
  memory: WebAssembly.Memory;
  _initialize(): void;
  malloc(size: number): number;
  free(ptr: number): void;
  argon2_hash(
    tCost: number, mCost: number, parallelism: number,
    pwd: number, pwdLen: number, salt: number, saltLen: number,
    hash: number, hashLen: number, encoded: number, encodedLen: number,
    type: number, version: number,
  ): number;
  argon2_verify(encoded: number, pwd: number, pwdLen: number, type: number): number;
  argon2_encodedlen(
    tCost: number, mCost: number, parallelism: number, saltLen: number, hashLen: number, type: number,
  ): number;
}

export interface Argon2 {
  /** Returns a PHC string `$argon2id$v=19$m=19456,t=2,p=1$<salt>$<hash>`. */
  hash(password: string, salt?: Uint8Array): string;
  /** Constant-time verification (done inside argon2_verify). False for any malformed PHC. */
  verify(password: string, phc: string): boolean;
}

const utf8 = new TextEncoder();
const utf8Decoder = new TextDecoder();

export async function createArgon2(module: WebAssembly.Module): Promise<Argon2> {
  const instance = await WebAssembly.instantiate(module, {});
  const ex = instance.exports as unknown as Argon2Exports;
  ex._initialize();

  const alloc = (size: number): number => {
    const ptr = ex.malloc(Math.max(size, 1));
    if (ptr === 0) throw new Error("argon2: out of memory");
    return ptr;
  };
  const copyIn = (bytes: Uint8Array): number => {
    const ptr = alloc(bytes.length);
    new Uint8Array(ex.memory.buffer, ptr, bytes.length).set(bytes);
    return ptr;
  };
  const wipeAndFree = (ptr: number, length: number): void => {
    new Uint8Array(ex.memory.buffer, ptr, length).fill(0);
    ex.free(ptr);
  };
  // Same password typed on macOS (may be NFD) and on a phone (NFC) must match.
  const passwordBytes = (password: string): Uint8Array => utf8.encode(password.normalize("NFC"));

  return {
    hash(password, salt = crypto.getRandomValues(new Uint8Array(ARGON2_SALT_BYTES))) {
      const pwd = passwordBytes(password);
      const encodedLen = ex.argon2_encodedlen(
        ARGON2_ITERATIONS, ARGON2_MEMORY_KIB, ARGON2_PARALLELISM, salt.length, ARGON2_HASH_BYTES, ARGON2_TYPE_ID,
      );
      const pwdPtr = copyIn(pwd);
      const saltPtr = copyIn(salt);
      const hashPtr = alloc(ARGON2_HASH_BYTES);
      const encodedPtr = alloc(encodedLen);
      try {
        const rc = ex.argon2_hash(
          ARGON2_ITERATIONS, ARGON2_MEMORY_KIB, ARGON2_PARALLELISM,
          pwdPtr, pwd.length, saltPtr, salt.length,
          hashPtr, ARGON2_HASH_BYTES, encodedPtr, encodedLen,
          ARGON2_TYPE_ID, ARGON2_VERSION_13,
        );
        if (rc !== ARGON2_OK) throw new Error(`argon2_hash failed with code ${rc}`);
        const encoded = new Uint8Array(ex.memory.buffer, encodedPtr, encodedLen);
        const end = encoded.indexOf(0);
        return utf8Decoder.decode(encoded.slice(0, end < 0 ? encodedLen : end));
      } finally {
        wipeAndFree(pwdPtr, pwd.length);
        ex.free(saltPtr);
        wipeAndFree(hashPtr, ARGON2_HASH_BYTES);
        ex.free(encodedPtr);
      }
    },
    verify(password, phc) {
      if (!phc.startsWith("$argon2id$")) return false;
      const pwd = passwordBytes(password);
      const encoded = utf8.encode(`${phc}\0`);
      const pwdPtr = copyIn(pwd);
      const encodedPtr = copyIn(encoded);
      try {
        return ex.argon2_verify(encodedPtr, pwdPtr, pwd.length, ARGON2_TYPE_ID) === ARGON2_OK;
      } finally {
        wipeAndFree(pwdPtr, pwd.length);
        ex.free(encodedPtr);
      }
    },
  };
}

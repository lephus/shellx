# ShellX v1.0 — Plan 01: Relay (Worker + UserHub + D1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `relay/`, the Cloudflare relay of ShellX: REST API for accounts, devices and pairings, plus a per-account WebSocket hub that forwards end-to-end encrypted frames between devices of the same account, served locally by `npm run dev` on `127.0.0.1:8787` for the plan-03 E2E suite and plan-06 CI.

**Architecture:** A Hono app on Cloudflare Workers validates bearer tokens against D1 and hands every WebSocket upgrade to the account's Durable Object `UserHub` (`idFromName(user_id)`), so routing between accounts is impossible by construction. `UserHub` uses the WebSocket Hibernation API (`acceptWebSocket`, `serializeAttachment`, `setWebSocketAutoResponse`) and keeps only a small durable queue in its SQLite storage; everything else is D1. Passwords use argon2id through a statically imported WASM module; rate limits go through a small `RateLimiter` interface backed by Workers rate limiting bindings.

**Tech Stack:** TypeScript 5.9, Hono 4.13, Wrangler 4.139, Cloudflare Workers + Durable Objects (SQLite backend) + D1 + rate limiting bindings, `@phi-ag/argon2` 0.5.28 (its `argon2.wasm` only), Vitest 4.1 + `@cloudflare/vitest-pool-workers` 0.22, `tsx` for Node scripts.

**Spec:** `docs/superpowers/specs/2026-09-25-shellx-v1-design.md` (§5.2, §5.3, §5.5, §6.1, §6.2, §10, §12, §13, §15 R1/R2). Binding contracts: `docs/superpowers/plans/2026-09-25-shellx-v1-00-overview.md` §2, §4.1 and §4.3 (byte-for-byte).

All commands run from `relay/` unless a step says "from the repository root". Commit steps always run from the repository root.

---

## Global Constraints

Everything in overview §2 applies. Values specific to this plan, copied from the spec/overview:

- Relay stack: TypeScript, Hono, wrangler, D1, Durable Object with **SQLite storage** and **WebSocket Hibernation API**, rate limiting binding. argon2id runs from a **statically imported WASM module** (Workers forbid compiling WASM at runtime). **Workers Paid** plan.
- Every error is JSON `{"error": {"code": "<snake_case>", "message": "<text>"}}`. Timestamps in JSON are integer unix **milliseconds** or `null`. UUIDs in JSON are lowercase `8-4-4-4-12`.
- Email: trim, lowercase, pragmatic RFC 5322 regex; the domain **and every parent domain** must not be in `disposable-email-domains` (bundled into the Worker by a script).
- Password **8–128** characters; argon2id **m = 19 456 KiB, t = 2, p = 1**, stored as a PHC string.
- Device token: **32 random bytes**, base64url, `Authorization: Bearer <token>`; D1 stores only **SHA-256**; expires when `last_used_at` is older than **90 days**; `last_used_at` updated at most **once per hour**.
- Rate limits (Workers rate limiting binding, 60 s period): login **10/IP** and **5/email**; register **3/IP**; over the limit → HTTP **429** `rate_limited`. Local dev sets `RATE_LIMITS_ENABLED = "false"` (all limits off); staging/production set `"true"` (always on).
- WebSocket: `wss://relay.shellx.pro/v1/ws`; text frames only `ping` → `pong` via `setWebSocketAutoResponse`; binary frames are relay frames (overview §4.1).
- Frame limit **64 KiB for the whole binary frame including the 26-byte DATA header** (`byteLength > 65536` → ERROR `frame_too_large`); **500 frames/s per connection** (token bucket) → ERROR `rate_limited` then close **4003**.
- ERROR codes `1 peer_offline`, `2 frame_too_large`, `3 rate_limited`, `4 bad_frame`; ERROR without a peer uses the nil UUID and 8 zero bytes. Close codes **4001 replaced**, **4002 revoked**, **4003 rate_limited**.
- EVENT is a CBOR map with text-string keys and values only (major types 5 and 3), hand-encoded: `{"event": "pairing_removed", "agent_id", "mobile_id"}`.
- Domains: `relay.shellx.pro` (production), `relay-staging.shellx.pro` (staging). Config file `relay/wrangler.jsonc`; version vars `MIN_AGENT`, `MIN_MOBILE`, `LATEST_AGENT_VERSION`, `MAC_URL`, `WIN_URL`.
- `npm run dev` applies local D1 migrations, then serves `127.0.0.1:8787`, and accepts `-- --ip 127.0.0.1 --port 8787`.
- Logs carry metadata only (time, device_id, error code, frame size). **Never** payloads, tokens, passwords (and, by this plan's choice, never e-mail addresses).

**Contract decisions this plan fixes where the spec is silent (plans 02/03/05 rely on them):**

1. Missing/invalid/expired token → HTTP **401** `unauthorized` on every authenticated route, including `GET /v1/ws`, which is refused **before** any upgrade. `invalid_credentials` is used only for a wrong email/password (login, `DELETE /v1/account`). A non-upgrade `GET /v1/ws` → **426** `upgrade_required`.
2. Other error codes: `400 bad_request` (body is not a JSON object), `400 invalid_device`, `403 forbidden` (DELETE of a pairing the caller is not part of), `404 not_found` (unknown route), `500 internal_error`.
3. `device.public_key` must be unpadded base64url of exactly 32 bytes (43 characters); `name` is trimmed, 1–100 characters; `kind`/`platform` must be one of the spec's enum values (combinations are not checked).
4. Login with a known public key reuses the `device_id`, refreshes `name`/`platform`, and **replaces** that device's previous token (one live token per device).
5. Passwords are NFC-normalised before the length check, hashing and verification (the same Vietnamese password typed as NFD on macOS and NFC on a phone must match).
6. `GET /v1/devices` returns the caller's account devices that are **signed in** (hold a token unused for less than 90 days), **including the caller**, ordered by `created_at`.
7. PRESENCE snapshot on connect lists every other online device (not the connecting one). A device that reconnects is announced `online` again; its replaced socket is closed with 4001 and is **never** announced offline.
8. `pairing_removed` is sent to **both** devices of the pairing when connected (clients must handle it idempotently). If the agent is offline, the event is stored in the hub's SQLite storage and delivered once, right after the PRESENCE snapshot, on the agent's next connection. It is sent only when a pairing row was actually deleted. Agent logout sends it for every pairing it removes.
9. `POST /v1/pairings` → `201` with an empty body (idempotent); `DELETE /v1/pairings/…` → `204` even if already gone; a malformed or foreign `mobile_id` → `404 device_not_found`; non-agent caller → `403 agent_only`.
10. `DELETE /v1/account {password}` shares the 5/email/60 s login budget (→ 429) to stop password guessing with a stolen token.

**Tooling (versions checked with `npm view` on 2026-09-25):** `hono ^4.13.9`, `wrangler ^4.139.0`, `@cloudflare/vitest-pool-workers ^0.22.0` (peer `vitest ^4.1.0`: **do not** install vitest 5.0.1), `vitest ~4.1.11`, `@cloudflare/workers-types ^5.20260925.1`, `typescript ^5.9.3`, `@types/node ^24.13.6`, `tsx ^4.23.15`, `@phi-ag/argon2 0.5.28` (**exact**: we call its WASM exports directly). `compatibility_date` is `2026-08-15` because the pool's bundled workerd only supports dates up to 2026-08-22.

## Review Focus

1. **Email with whitespace/uppercase, subdomain of a disposable domain (`x.yopmail.com`), login with a differently-cased email** (overview §6 line 5, owned here): normalised to one account; subdomains still blocked. Tests: Task 3 `policy.test.ts` ("trims whitespace…", "blocks the domain itself and every subdomain…", "classifies after normalisation…") and Task 5 `auth.test.ts` ("normalises the email…", the `x.yopmail.com` rows, "409 email_taken … different case", "logs in with a differently-cased, padded email…").
2. **Vietnamese / non-ASCII passwords:** every UTF-8 byte must be hashed (the `@phi-ag/argon2` JS class truncates to `password.length` UTF-16 units, so `mậtkhẩuđẹplắm1` and `mậtkhẩuđẹpXXXX` would match), and NFD vs NFC spellings must match. Tests: Task 1 (Vietnamese known-answer vector, "rejects a password that only shares a UTF-16-length prefix", "NFC and NFD…"), Task 3 (length counted after NFC), Task 5 (register NFD, log in NFC).
3. **A device reconnects before its old socket is noticed dead** (network flap, app restart): old socket closed 4001, peers must **not** see it go offline, frames go to the new socket. Test: Task 6 "replaces an older connection … without announcing it offline".
4. **Revoked or expired token at WebSocket connect** (after a password change or 90 idle days): plain HTTP 401 before the upgrade so clients go back to login instead of reconnecting forever. Test: Task 6 "refuses a missing, unknown or expired token with HTTP 401…".
5. **Durable Object hibernation/eviction with sockets open:** routing, presence, replacement, heartbeat and the 500 frames/s limit must keep working after wake-up (attachments are persisted, token buckets are rebuilt). Test: Task 7 "keeps routing, presence, replacement, heartbeat and rate limiting working after eviction".
6. **Mobile un-pairs while the agent is offline:** the agent must still learn it (trust lives on the agent, spec §5.4), exactly once. Test: Task 8 "queues the event for an offline agent and delivers it after the presence snapshot".

---

## Facts verified while writing this plan (2026-09-25, Node 25, macOS)

- **R1 spike result:** `import argon2Module from "@phi-ag/argon2/argon2.wasm"` yields a precompiled `WebAssembly.Module` both inside `@cloudflare/vitest-pool-workers` 0.22.0 and in `wrangler deploy --dry-run` (bundled as a separate `.wasm` module, 28.9 KB). The module has no imports and exports `memory, argon2_hash, malloc, free, argon2_verify, argon2_error_message, argon2_encodedlen, _initialize`. Median hash + verify with the spec parameters: **29 ms** in local workerd (pure-JS `@noble/hashes` fallback: 233 ms). Known-answer vectors were cross-checked with Node's `crypto.argon2Sync` and `@noble/hashes`.
- With `compatibility_date` 2026-08-15, a JS `WebSocket` client inside workerd receives binary messages as `Blob` unless `binaryType = "arraybuffer"` (the test helper sets it). Hibernation handlers still receive `ArrayBuffer`.
- `wrangler dev --ip X --ip X` fails ("expects a single value"), so the `dev` script passes no `--ip/--port`; the `dev` block of `wrangler.jsonc` provides them.
- `wrangler d1 migrations apply` prompts only in interactive terminals; CI is non-interactive.
- D1 enforces `ON DELETE CASCADE`. `cloudflare:test` exports `evictDurableObject(stub)` (hibernates sockets) and `applyD1Migrations`.
- An exception thrown by a Durable Object RPC method inside a test is reported by Vitest as an unhandled error that fails the run, so hub RPC methods take typed arguments instead of throwing on bad input.
- `https://raw.githubusercontent.com/disposable-email-domains/disposable-email-domains/main/disposable_email_blocklist.conf` returns HTTP 200 with 8,971 domains (includes `yopmail.com`, `mailinator.com`).

## File map (`relay/`)

| File | Responsibility | Task |
|---|---|---|
| `package.json`, `package-lock.json`, `tsconfig.json`, `.gitignore`, `vitest.config.ts`, `wrangler.jsonc` | Tooling, bindings, environments | 1, 3, 4, 6, 10 |
| `src/types/wasm.d.ts` | Typing for `*.wasm` imports | 1 |
| `src/auth/argon2.ts` | argon2id over the raw WASM exports (also used by the Node reset script) | 1 |
| `src/auth/password.ts` | `hashPassword` / `verifyPassword` (static WASM import) | 1 |
| `src/protocol/uuid.ts`, `cbor.ts`, `frames.ts` | Wire format of overview §4.1 | 2 |
| `src/auth/email.ts`, `password-policy.ts`, `disposable-domains.json` | Input policy | 3 |
| `scripts/blocklist.ts`, `scripts/update-disposable-domains.ts`, `scripts/tsconfig.json` | Disposable-domain list refresh | 3 |
| `migrations/0001_init.sql` | D1 schema (spec §10.3) | 4 |
| `src/env.ts`, `src/log.ts`, `src/http/errors.ts`, `src/auth/rate-limit.ts`, `src/app.ts`, `src/index.ts` | Worker skeleton | 4, 5, 6, 8, 9 |
| `src/auth/tokens.ts`, `device.ts`, `session.ts`, `src/routes/auth.ts` | Tokens, device input, auth middleware, `/v1/auth/*` | 5, 9 |
| `src/hub/user-hub.ts`, `src/routes/ws.ts` | Durable Object hub and `/v1/ws` | 6, 7, 8 |
| `src/hub/token-bucket.ts` | 500 frames/s limiter | 7 |
| `src/routes/devices.ts`, `src/routes/pairings.ts` | `/v1/devices`, `/v1/pairings` | 8 |
| `src/routes/account.ts` | `DELETE /v1/account` | 9 |
| `scripts/reset-sql.ts`, `scripts/reset-password.ts` | Emergency password reset | 10 |
| `test/*.ts` | Vitest suites + helpers (run inside workerd) | all |
| `README.md` | Local dev + deployment runbook + cost check | 11 |

---

### Task 1: Scaffold `relay/` and the R1 spike — argon2id from a static WASM module in workerd

**R1 decision (spec §15):** use the precompiled `argon2.wasm` shipped by `@phi-ag/argon2`, imported statically, with our own wrapper around its C exports (`src/auth/argon2.ts`). The package's own JS class is **not** used: it passes `password.length` (UTF-16 code units) as the byte length, which silently truncates non-ASCII passwords (reproduced: a hash of `mậtkhẩuđẹplắm1` verified `mậtkhẩuđẹpXXXX`). This spike was run successfully while writing the plan (29 ms median hash + verify). Step 7 is a pre-written fallback for the unlikely case that it fails on your machine.

**Files:**
- Create: `relay/package.json`, `relay/tsconfig.json`, `relay/wrangler.jsonc`, `relay/vitest.config.ts`, `relay/.gitignore`, `relay/src/types/wasm.d.ts`, `relay/src/index.ts`, `relay/src/auth/argon2.ts`, `relay/src/auth/password.ts`
- Generated: `relay/package-lock.json`
- Test: `relay/test/password.test.ts`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `src/auth/argon2.ts`: `ARGON2_MEMORY_KIB = 19456`, `ARGON2_ITERATIONS = 2`, `ARGON2_PARALLELISM = 1`, `ARGON2_HASH_BYTES = 32`, `ARGON2_SALT_BYTES = 16`; `interface Argon2 { hash(password: string, salt?: Uint8Array): string; verify(password: string, phc: string): boolean }`; `createArgon2(module: WebAssembly.Module): Promise<Argon2>` (NFC-normalises passwords).
  - `src/auth/password.ts`: `hashPassword(password: string): Promise<string>`, `verifyPassword(password: string, phc: string): Promise<boolean>`.
  - `npm test` (Vitest in workerd) and `npm run typecheck`.

- [ ] **Step 1: Create `relay/package.json` and install**

```json
{
  "name": "shellx-relay",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "engines": {
    "node": ">=22"
  },
  "scripts": {
    "test": "vitest run",
    "typecheck": "tsc -p tsconfig.json"
  },
  "dependencies": {
    "@phi-ag/argon2": "0.5.28",
    "hono": "^4.13.9"
  },
  "devDependencies": {
    "@cloudflare/vitest-pool-workers": "^0.22.0",
    "@cloudflare/workers-types": "^5.20260925.1",
    "@types/node": "^24.13.6",
    "tsx": "^4.23.15",
    "typescript": "^5.9.3",
    "vitest": "~4.1.11",
    "wrangler": "^4.139.0"
  }
}
```

Run: `mkdir -p relay && cd relay && npm install`
Expected: `package-lock.json` is created; `npx vitest --version` prints `vitest/4.1.x`.

- [ ] **Step 2: Create the tooling files**

`relay/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "es2023",
    "module": "es2022",
    "moduleResolution": "bundler",
    "lib": ["es2023"],
    "types": ["@cloudflare/workers-types", "@cloudflare/vitest-pool-workers/types"],
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noEmit": true,
    "skipLibCheck": true,
    "isolatedModules": true,
    "resolveJsonModule": true,
    "verbatimModuleSyntax": true
  },
  "include": ["src", "test"]
}
```

`relay/wrangler.jsonc` (minimal; Task 4 replaces it):

```jsonc
{
  "$schema": "node_modules/wrangler/config-schema.json",
  "name": "shellx-relay",
  "main": "src/index.ts",
  // Must not be newer than the workerd bundled with @cloudflare/vitest-pool-workers,
  // otherwise `npm test` fails with "This Worker requires compatibility date ...".
  "compatibility_date": "2026-08-15"
}
```

`relay/vitest.config.ts` (Task 4 replaces it):

```ts
import { cloudflareTest } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [cloudflareTest({ wrangler: { configPath: "./wrangler.jsonc" } })],
});
```

`relay/.gitignore`:

```gitignore
node_modules/
.wrangler/
dist/
```

`relay/src/types/wasm.d.ts`:

```ts
// wrangler and @cloudflare/vitest-pool-workers turn `import x from "*.wasm"`
// into a precompiled WebAssembly.Module (Workers forbid compiling WASM from bytes at runtime).
declare module "*.wasm" {
  const module: WebAssembly.Module;
  export default module;
}
```

`relay/src/index.ts` (placeholder Worker so the pool can start; Task 4 replaces it):

```ts
export default {
  async fetch(): Promise<Response> {
    return Response.json({ error: { code: "not_found", message: "Not found" } }, { status: 404 });
  },
} satisfies ExportedHandler;
```

- [ ] **Step 3: Write the failing test** — `relay/test/password.test.ts`

```ts
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
```

- [ ] **Step 4: Run it to verify it fails**

Run: `npx vitest run test/password.test.ts`
Expected: FAIL — `Error: Cannot find module '../src/auth/argon2' imported from …/test/password.test.ts`

- [ ] **Step 5: Implement** — `relay/src/auth/argon2.ts`

```ts
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
```

`relay/src/auth/password.ts`:

```ts
import argon2Module from "@phi-ag/argon2/argon2.wasm";
import { createArgon2, type Argon2 } from "./argon2";

let hasher: Promise<Argon2> | undefined;

function getHasher(): Promise<Argon2> {
  hasher ??= createArgon2(argon2Module);
  return hasher;
}

export async function hashPassword(password: string): Promise<string> {
  return (await getHasher()).hash(password);
}

export async function verifyPassword(password: string, phc: string): Promise<boolean> {
  return (await getHasher()).verify(password, phc);
}
```

- [ ] **Step 6: Run the spike and record the timing**

Run: `npx vitest run test/password.test.ts --reporter verbose --silent=false`
Expected: PASS, `7 passed (7)`, and a log line like `{"event":"argon2_timing","median_ms":29,"samples_ms":[…]}`. Write the measured median into the commit message of Step 9. (Timers only advance like this in local workerd; in production use `wrangler tail`/dashboard CPU time.)

- [ ] **Step 7: Fallback — only if Step 6 fails while loading or instantiating `argon2.wasm`**

Symptoms: an error mentioning `argon2.wasm`, `No loader is configured for ".wasm"`, or `Wasm code generation disallowed`. Any other failure is a bug to fix, not a reason to fall back.

Acceptance criterion for the fallback (state it in the commit message): `@noble/hashes` argon2id (pure JS, no WASM) is acceptable only if **all 7 tests of `test/password.test.ts` pass, including hash + verify median < 500 ms** in local workerd (measured 233 ms while planning). That is roughly 0.25 s of CPU per register/login in production, inside the Workers Paid default CPU limit (30 s) but 8× the WASM cost.

Run: `npm uninstall @phi-ag/argon2 && npm install @noble/hashes@^2.4.0`

Replace `relay/src/auth/argon2.ts` with:

```ts
// FALLBACK implementation (pure JS, @noble/hashes). Used only if the static-WASM spike failed.
import { argon2id } from "@noble/hashes/argon2.js";

export const ARGON2_MEMORY_KIB = 19456;
export const ARGON2_ITERATIONS = 2;
export const ARGON2_PARALLELISM = 1;
export const ARGON2_HASH_BYTES = 32;
export const ARGON2_SALT_BYTES = 16;

const PHC_RE = /^\$argon2id\$v=19\$m=(\d{1,6}),t=(\d{1,2}),p=(\d{1,2})\$([A-Za-z0-9+/]{11,64})\$([A-Za-z0-9+/]{11,128})$/;

export interface Argon2 {
  hash(password: string, salt?: Uint8Array): string;
  verify(password: string, phc: string): boolean;
}

const utf8 = new TextEncoder();

function b64(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/=+$/, "");
}

function unb64(text: string): Uint8Array {
  const padded = text + "=".repeat((4 - (text.length % 4)) % 4);
  return Uint8Array.from(atob(padded), (ch) => ch.charCodeAt(0));
}

function derive(password: string, salt: Uint8Array, m: number, t: number, p: number, dkLen: number): Uint8Array {
  return argon2id(utf8.encode(password.normalize("NFC")), salt, { m, t, p, dkLen });
}

/** The optional module argument keeps the WASM-variant signature; it is ignored here. */
export async function createArgon2(_module?: unknown): Promise<Argon2> {
  return {
    hash(password, salt = crypto.getRandomValues(new Uint8Array(ARGON2_SALT_BYTES))) {
      const tag = derive(password, salt, ARGON2_MEMORY_KIB, ARGON2_ITERATIONS, ARGON2_PARALLELISM, ARGON2_HASH_BYTES);
      return `$argon2id$v=19$m=${ARGON2_MEMORY_KIB},t=${ARGON2_ITERATIONS},p=${ARGON2_PARALLELISM}$${b64(salt)}$${b64(tag)}`;
    },
    verify(password, phc) {
      const match = PHC_RE.exec(phc);
      if (match === null) return false;
      const [m, t, p] = [Number(match[1]), Number(match[2]), Number(match[3])];
      if (m > 65536 || t < 1 || t > 10 || p < 1 || p > 4) return false; // refuse attacker-sized work
      let salt: Uint8Array;
      let expected: Uint8Array;
      try {
        salt = unb64(match[4]!);
        expected = unb64(match[5]!);
      } catch {
        return false;
      }
      const actual = derive(password, salt, m, t, p, expected.length);
      let diff = 0;
      for (let i = 0; i < expected.length; i++) diff |= actual[i]! ^ expected[i]!;
      return diff === 0;
    },
  };
}
```

Replace `relay/src/auth/password.ts` with:

```ts
import { createArgon2, type Argon2 } from "./argon2";

let hasher: Promise<Argon2> | undefined;

function getHasher(): Promise<Argon2> {
  hasher ??= createArgon2();
  return hasher;
}

export async function hashPassword(password: string): Promise<string> {
  return (await getHasher()).hash(password);
}

export async function verifyPassword(password: string, phc: string): Promise<boolean> {
  return (await getHasher()).verify(password, phc);
}
```

In `relay/test/password.test.ts`, delete the line `import argon2Module from "@phi-ag/argon2/argon2.wasm";` and change both `createArgon2(argon2Module)` calls to `createArgon2()`. If you took this fallback, Task 10 needs the same two changes in `test/reset-password.test.ts`, and in `scripts/reset-password.ts` the line `import { readFileSync } from "node:fs";` is deleted and the two lines `const wasm = readFileSync(…);` / `const argon2 = await createArgon2(new WebAssembly.Module(wasm));` become `const argon2 = await createArgon2();`. Re-run Step 6.

- [ ] **Step 8: Typecheck**

Run: `npm run typecheck`
Expected: exit code 0, no output.

- [ ] **Step 9: Commit** (from the repository root)

```bash
git add relay/package.json relay/package-lock.json relay/tsconfig.json relay/wrangler.jsonc relay/vitest.config.ts relay/.gitignore relay/src relay/test
git commit -m "feat(relay): scaffold relay and argon2id via static WASM (R1 spike: median hash+verify <N> ms)"
```

(Replace `<N>` with the median from Step 6.)

---

### Task 2: Wire format — UUID bytes, minimal CBOR text map, relay frames

**Files:**
- Create: `relay/src/protocol/uuid.ts`, `relay/src/protocol/cbor.ts`, `relay/src/protocol/frames.ts`
- Test: `relay/test/protocol.test.ts`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `uuid.ts`: `NIL_UUID`; `parseUuid(value: unknown): string | null` (lowercase canonical or null); `uuidToBytes(uuid: string): Uint8Array` (TypeError if malformed); `uuidFromBytes(bytes: Uint8Array): string`.
  - `cbor.ts`: `encodeTextMap(map: Readonly<Record<string, string>>): Uint8Array`.
  - `frames.ts`: `RELAY_PROTOCOL_VERSION = 1`, `MAX_FRAME_BYTES = 65536`, `DATA_HEADER_BYTES = 26`, `CHANNEL_ID_BYTES = 8`, `FrameType`, `RelayErrorCode` (const object + type), `CloseCode` (const object + type `4001 | 4002 | 4003`), `ZERO_CHANNEL`, `interface DataHeader { peer: string; channel: Uint8Array }`, `parseDataHeader(frame: Uint8Array): DataHeader | null`, `withPeer(frame: Uint8Array, source: string): Uint8Array`, `encodeData(peer: string, channel: Uint8Array, payload: Uint8Array): Uint8Array`, `encodePresence(deviceId: string, online: boolean): Uint8Array`, `encodeError(code: RelayErrorCode, deviceId?: string, channel?: Uint8Array): Uint8Array`, `encodeEvent(event: Readonly<Record<string, string>>): Uint8Array`, `pairingRemovedEvent(agentId: string, mobileId: string): Uint8Array`.

- [ ] **Step 1: Write the failing test** — `relay/test/protocol.test.ts` (the EVENT vector was decoded with an independent CBOR library while planning)

```ts
import { describe, expect, it } from "vitest";
import { encodeTextMap } from "../src/protocol/cbor";
import {
  CloseCode, encodeData, encodeError, encodeEvent, encodePresence, MAX_FRAME_BYTES,
  pairingRemovedEvent, parseDataHeader, RelayErrorCode, withPeer,
} from "../src/protocol/frames";
import { NIL_UUID, parseUuid, uuidFromBytes, uuidToBytes } from "../src/protocol/uuid";

const hex = (bytes: Uint8Array): string => Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
const fromHex = (h: string): Uint8Array => Uint8Array.from(h.match(/../g)!.map((x) => Number.parseInt(x, 16)));

const A = "0123abcd-4567-4def-8123-456789abcdef";
const A_HEX = "0123abcd45674def8123456789abcdef";
const B = "fedcba98-7654-4321-8fed-cba987654321";
const B_HEX = "fedcba98765443218fedcba987654321";
const CH = fromHex("0102030405060708");

describe("uuid", () => {
  it("round-trips in textual byte order", () => {
    expect(hex(uuidToBytes(A))).toBe(A_HEX);
    expect(uuidFromBytes(uuidToBytes(A))).toBe(A);
  });
  it("canonicalises to lowercase and rejects garbage", () => {
    expect(parseUuid(A.toUpperCase())).toBe(A);
    expect(parseUuid("not-a-uuid")).toBeNull();
    expect(parseUuid(42)).toBeNull();
    expect(() => uuidToBytes("nope")).toThrow(TypeError);
    expect(hex(uuidToBytes(NIL_UUID))).toBe("00".repeat(16));
  });
});

describe("cbor text map (RFC 8949 Appendix A vectors)", () => {
  it("encodes {} and a one-entry map", () => {
    expect(hex(encodeTextMap({}))).toBe("a0");
    expect(hex(encodeTextMap({ a: "b" }))).toBe("a161616162");
  });
  it("encodes the five-entry map vector", () => {
    expect(hex(encodeTextMap({ a: "A", b: "B", c: "C", d: "D", e: "E" }))).toBe(
      "a56161614161626142616361436164614461656145",
    );
  });
  it("uses UTF-8 byte length and 1-byte / 2-byte length headers", () => {
    expect(hex(encodeTextMap({ "ü": "" }))).toBe("a162c3bc60");
    expect(hex(encodeTextMap({ k: "x".repeat(24) }).slice(0, 5))).toBe("a1616b7818");
    expect(hex(encodeTextMap({ k: "y".repeat(256) }).slice(0, 6))).toBe("a1616b790100");
  });
});

describe("relay frames (overview §4.1)", () => {
  it("DATA: header layout and peer rewrite", () => {
    const frame = encodeData(B, CH, fromHex("04aabb"));
    expect(hex(frame)).toBe(`0101${B_HEX}010203040506070804aabb`);
    expect(parseDataHeader(frame)).toEqual({ peer: B, channel: CH });
    const rewritten = withPeer(frame, A);
    expect(hex(rewritten)).toBe(`0101${A_HEX}010203040506070804aabb`);
    expect(parseDataHeader(frame)?.peer).toBe(B); // original buffer untouched
  });
  it("DATA parse rejects short, wrong-version and non-DATA frames", () => {
    expect(parseDataHeader(new Uint8Array(25))).toBeNull();
    const frame = encodeData(B, CH, new Uint8Array());
    expect(frame.length).toBe(26);
    expect(parseDataHeader(frame)).not.toBeNull();
    const v2 = frame.slice();
    v2[0] = 2;
    expect(parseDataHeader(v2)).toBeNull();
    const presence = frame.slice();
    presence[1] = 0x02;
    expect(parseDataHeader(presence)).toBeNull();
  });
  it("PRESENCE is 19 bytes", () => {
    expect(hex(encodePresence(A, true))).toBe(`0102${A_HEX}01`);
    expect(hex(encodePresence(A, false))).toBe(`0102${A_HEX}00`);
  });
  it("ERROR is 28 bytes with a big-endian code; defaults to nil device and zero channel", () => {
    expect(hex(encodeError(RelayErrorCode.peerOffline, B, CH))).toBe(`01030001${B_HEX}0102030405060708`);
    expect(hex(encodeError(RelayErrorCode.badFrame))).toBe(`01030004${"00".repeat(24)}`);
    expect(hex(encodeError(RelayErrorCode.frameTooLarge).slice(2, 4))).toBe("0002");
    expect(hex(encodeError(RelayErrorCode.rateLimited).slice(2, 4))).toBe("0003");
  });
  it("EVENT pairing_removed matches the byte-for-byte vector", () => {
    expect(hex(pairingRemovedEvent(A, B))).toBe(
      "0104a3656576656e746f70616972696e675f72656d6f766564686167656e745f6964782430313233616263642d34" +
        "3536372d346465662d383132332d343536373839616263646566696d6f62696c655f69647824666564636261" +
        "39382d373635342d343332312d386665642d636261393837363534333231",
    );
    expect(encodeEvent({})).toEqual(Uint8Array.from([1, 4, 0xa0]));
  });
  it("constants match the wire contract", () => {
    expect(MAX_FRAME_BYTES).toBe(65536);
    expect(CloseCode).toEqual({ replaced: 4001, revoked: 4002, rateLimited: 4003 });
    expect(RelayErrorCode).toEqual({ peerOffline: 1, frameTooLarge: 2, rateLimited: 3, badFrame: 4 });
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `npx vitest run test/protocol.test.ts`
Expected: FAIL — `Error: Cannot find module '../src/protocol/cbor' imported from …/test/protocol.test.ts`

- [ ] **Step 3: Implement** — `relay/src/protocol/uuid.ts`

```ts
export const NIL_UUID = "00000000-0000-0000-0000-000000000000";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** Returns the canonical lowercase 8-4-4-4-12 form, or null if `value` is not a UUID string. */
export function parseUuid(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const lower = value.toLowerCase();
  return UUID_RE.test(lower) ? lower : null;
}

/** 16 bytes in textual order (the hex digits read left to right). Throws on malformed input. */
export function uuidToBytes(uuid: string): Uint8Array {
  const canonical = parseUuid(uuid);
  if (canonical === null) throw new TypeError("invalid UUID");
  const hex = canonical.replaceAll("-", "");
  const out = new Uint8Array(16);
  for (let i = 0; i < 16; i++) out[i] = Number.parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return out;
}

export function uuidFromBytes(bytes: Uint8Array): string {
  if (bytes.length !== 16) throw new TypeError("UUID must be 16 bytes");
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}
```

`relay/src/protocol/cbor.ts`:

```ts
// Minimal CBOR (RFC 8949) encoder for the only structure the relay emits:
// a map (major type 5) whose keys and values are all text strings (major type 3).
// Keys are written in insertion order; definite lengths only; no tags.

const utf8 = new TextEncoder();

function header(majorType: number, length: number): number[] {
  const mt = majorType << 5;
  if (length < 24) return [mt | length];
  if (length < 0x100) return [mt | 24, length];
  if (length < 0x10000) return [mt | 25, length >> 8, length & 0xff];
  return [mt | 26, (length >>> 24) & 0xff, (length >>> 16) & 0xff, (length >>> 8) & 0xff, length & 0xff];
}

function textString(value: string): number[] {
  const bytes = utf8.encode(value);
  return [...header(3, bytes.length), ...bytes];
}

export function encodeTextMap(map: Readonly<Record<string, string>>): Uint8Array {
  const entries = Object.entries(map);
  const out: number[] = header(5, entries.length);
  for (const [key, value] of entries) out.push(...textString(key), ...textString(value));
  return Uint8Array.from(out);
}
```

`relay/src/protocol/frames.ts`:

```ts
import { encodeTextMap } from "./cbor";
import { NIL_UUID, uuidFromBytes, uuidToBytes } from "./uuid";

export const RELAY_PROTOCOL_VERSION = 1;
export const MAX_FRAME_BYTES = 64 * 1024;
export const DATA_HEADER_BYTES = 26;
export const CHANNEL_ID_BYTES = 8;

export const FrameType = { data: 0x01, presence: 0x02, error: 0x03, event: 0x04 } as const;

export const RelayErrorCode = { peerOffline: 1, frameTooLarge: 2, rateLimited: 3, badFrame: 4 } as const;
export type RelayErrorCode = (typeof RelayErrorCode)[keyof typeof RelayErrorCode];

export const CloseCode = { replaced: 4001, revoked: 4002, rateLimited: 4003 } as const;
export type CloseCode = (typeof CloseCode)[keyof typeof CloseCode];

export const ZERO_CHANNEL = new Uint8Array(CHANNEL_ID_BYTES);

export interface DataHeader {
  peer: string;
  channel: Uint8Array;
}

/** Parses the header of a client → hub DATA frame; null if it is not a well-formed DATA frame. */
export function parseDataHeader(frame: Uint8Array): DataHeader | null {
  if (frame.length < DATA_HEADER_BYTES) return null;
  if (frame[0] !== RELAY_PROTOCOL_VERSION || frame[1] !== FrameType.data) return null;
  return { peer: uuidFromBytes(frame.slice(2, 18)), channel: frame.slice(18, DATA_HEADER_BYTES) };
}

/** Copy of a DATA frame with bytes [2..17] replaced by `source` (hub → destination). */
export function withPeer(frame: Uint8Array, source: string): Uint8Array {
  const out = frame.slice();
  out.set(uuidToBytes(source), 2);
  return out;
}

export function encodeData(peer: string, channel: Uint8Array, payload: Uint8Array): Uint8Array {
  if (channel.length !== CHANNEL_ID_BYTES) throw new TypeError("channel id must be 8 bytes");
  const out = new Uint8Array(DATA_HEADER_BYTES + payload.length);
  out[0] = RELAY_PROTOCOL_VERSION;
  out[1] = FrameType.data;
  out.set(uuidToBytes(peer), 2);
  out.set(channel, 18);
  out.set(payload, DATA_HEADER_BYTES);
  return out;
}

export function encodePresence(deviceId: string, online: boolean): Uint8Array {
  const out = new Uint8Array(19);
  out[0] = RELAY_PROTOCOL_VERSION;
  out[1] = FrameType.presence;
  out.set(uuidToBytes(deviceId), 2);
  out[18] = online ? 1 : 0;
  return out;
}

export function encodeError(
  code: RelayErrorCode,
  deviceId: string = NIL_UUID,
  channel: Uint8Array = ZERO_CHANNEL,
): Uint8Array {
  if (channel.length !== CHANNEL_ID_BYTES) throw new TypeError("channel id must be 8 bytes");
  const out = new Uint8Array(28);
  out[0] = RELAY_PROTOCOL_VERSION;
  out[1] = FrameType.error;
  out[2] = code >> 8;
  out[3] = code & 0xff;
  out.set(uuidToBytes(deviceId), 4);
  out.set(channel, 20);
  return out;
}

export function encodeEvent(event: Readonly<Record<string, string>>): Uint8Array {
  const body = encodeTextMap(event);
  const out = new Uint8Array(2 + body.length);
  out[0] = RELAY_PROTOCOL_VERSION;
  out[1] = FrameType.event;
  out.set(body, 2);
  return out;
}

export function pairingRemovedEvent(agentId: string, mobileId: string): Uint8Array {
  return encodeEvent({ event: "pairing_removed", agent_id: agentId, mobile_id: mobileId });
}
```

- [ ] **Step 4: Run tests**

Run: `npx vitest run test/protocol.test.ts && npm run typecheck`
Expected: PASS, `11 passed (11)`; typecheck exits 0.

- [ ] **Step 5: Commit** (from the repository root)

```bash
git add relay/src/protocol relay/test/protocol.test.ts
git commit -m "feat(relay): relay frame, UUID and minimal CBOR encoders"
```

---

### Task 3: Email and password policy, bundled disposable-domain list

**Files:**
- Create: `relay/src/auth/email.ts`, `relay/src/auth/password-policy.ts`, `relay/scripts/blocklist.ts`, `relay/scripts/update-disposable-domains.ts`, `relay/scripts/tsconfig.json`
- Generated (committed): `relay/src/auth/disposable-domains.json`
- Modify: `relay/package.json` (scripts)
- Test: `relay/test/policy.test.ts`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `email.ts`: `normalizeEmail(raw: string): string`, `isValidEmail(email: string): boolean`, `isDisposableDomain(domain: string): boolean`, `type EmailCheck = { ok: true; email: string } | { ok: false; code: "invalid_email" | "disposable_email" }`, `checkEmail(raw: unknown): EmailCheck`.
  - `password-policy.ts`: `PASSWORD_MIN_CHARS = 8`, `PASSWORD_MAX_CHARS = 128`, `isAcceptablePassword(value: unknown): value is string` (code points after NFC). Kept separate from `password.ts` so Node scripts can import it without the WASM module.
  - `scripts/blocklist.ts`: `parseBlocklist(text: string): string[]`, `renderDomainsJson(domains: readonly string[]): string`.
  - `npm run domains:update`; `npm run typecheck` now also checks `scripts/`.

- [ ] **Step 1: Write the failing test** — `relay/test/policy.test.ts`

```ts
import { describe, expect, it } from "vitest";
import { parseBlocklist, renderDomainsJson } from "../scripts/blocklist";
import disposableDomains from "../src/auth/disposable-domains.json";
import { checkEmail, isDisposableDomain, isValidEmail, normalizeEmail } from "../src/auth/email";
import { isAcceptablePassword } from "../src/auth/password-policy";

describe("email normalisation and validation", () => {
  it("trims whitespace (including NBSP and newlines) and lowercases", () => {
    expect(normalizeEmail("  Alice.Nguyen@Example.COM \n")).toBe("alice.nguyen@example.com");
    expect(checkEmail(" Bob@Example.com\t")).toEqual({ ok: true, email: "bob@example.com" });
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `npx vitest run test/policy.test.ts`
Expected: FAIL — `Error: Cannot find module '../scripts/blocklist' imported from …/test/policy.test.ts`

- [ ] **Step 3: Implement the list tooling** — `relay/scripts/blocklist.ts`

```ts
/** Parses disposable_email_blocklist.conf: one domain per line, `#` comments, blank lines ignored. */
export function parseBlocklist(text: string): string[] {
  const domains = new Set<string>();
  for (const line of text.split(/\r?\n/)) {
    const domain = line.trim().toLowerCase();
    if (domain === "" || domain.startsWith("#")) continue;
    domains.add(domain);
  }
  return [...domains].sort();
}

/** One domain per line so that list refreshes produce readable diffs. */
export function renderDomainsJson(domains: readonly string[]): string {
  return `[\n${domains.map((d) => `  ${JSON.stringify(d)}`).join(",\n")}\n]\n`;
}
```

`relay/scripts/update-disposable-domains.ts`:

```ts
// Refreshes src/auth/disposable-domains.json from the upstream blocklist.
// Usage: npm run domains:update   (then review the diff and commit it)
import { writeFile } from "node:fs/promises";
import { parseBlocklist, renderDomainsJson } from "./blocklist";

const SOURCE_URL =
  "https://raw.githubusercontent.com/disposable-email-domains/disposable-email-domains/main/disposable_email_blocklist.conf";
const OUTPUT = new URL("../src/auth/disposable-domains.json", import.meta.url);
const MIN_EXPECTED = 1000;

const response = await fetch(SOURCE_URL);
if (!response.ok) throw new Error(`download failed: HTTP ${response.status}`);
const domains = parseBlocklist(await response.text());
if (domains.length < MIN_EXPECTED) throw new Error(`only ${domains.length} domains downloaded; refusing to write`);
await writeFile(OUTPUT, renderDomainsJson(domains), "utf8");
console.log(`wrote ${domains.length} domains to src/auth/disposable-domains.json`);
```

`relay/scripts/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "es2023",
    "module": "es2022",
    "moduleResolution": "bundler",
    "lib": ["es2023", "dom"],
    "types": ["node"],
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noEmit": true,
    "skipLibCheck": true,
    "resolveJsonModule": true
  },
  "include": ["./*.ts"]
}
```

In `relay/package.json` replace:

```json
  "scripts": {
    "test": "vitest run",
    "typecheck": "tsc -p tsconfig.json"
  },
```

with:

```json
  "scripts": {
    "test": "vitest run",
    "typecheck": "tsc -p tsconfig.json && tsc -p scripts/tsconfig.json",
    "domains:update": "tsx scripts/update-disposable-domains.ts"
  },
```

- [ ] **Step 4: Generate the bundled list**

Run: `npm run domains:update`
Expected: `wrote 8971 domains to src/auth/disposable-domains.json` (the count drifts upstream; the script refuses to write fewer than 1000). The file is a JSON array, one lowercase domain per line, sorted. It is committed so builds and tests are reproducible; `README.md` (Task 11) tells releasers to refresh it.

- [ ] **Step 5: Implement the policies** — `relay/src/auth/email.ts`

```ts
import disposableDomains from "./disposable-domains.json";

const DISPOSABLE = new Set<string>(disposableDomains);

// Pragmatic subset of RFC 5322: dot-atom local part, LDH domain labels, alphabetic TLD.
// Applied to the already-normalised (trimmed, lowercased) address.
const EMAIL_RE =
  /^[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*@(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/;

export function normalizeEmail(raw: string): string {
  return raw.trim().toLowerCase();
}

export function isValidEmail(email: string): boolean {
  if (email.length > 254) return false;
  const at = email.lastIndexOf("@");
  if (at < 1 || at > 64) return false;
  return EMAIL_RE.test(email);
}

/** True if `domain` or any parent domain (x.yopmail.com → yopmail.com → com) is on the blocklist. */
export function isDisposableDomain(domain: string): boolean {
  const labels = domain.toLowerCase().split(".");
  for (let i = 0; i < labels.length; i++) {
    if (DISPOSABLE.has(labels.slice(i).join("."))) return true;
  }
  return false;
}

export type EmailCheck =
  | { ok: true; email: string }
  | { ok: false; code: "invalid_email" | "disposable_email" };

export function checkEmail(raw: unknown): EmailCheck {
  if (typeof raw !== "string") return { ok: false, code: "invalid_email" };
  const email = normalizeEmail(raw);
  if (!isValidEmail(email)) return { ok: false, code: "invalid_email" };
  if (isDisposableDomain(email.slice(email.lastIndexOf("@") + 1))) return { ok: false, code: "disposable_email" };
  return { ok: true, email };
}
```

`relay/src/auth/password-policy.ts`:

```ts
export const PASSWORD_MIN_CHARS = 8;
export const PASSWORD_MAX_CHARS = 128;

/** 8–128 characters, counted as Unicode code points after NFC normalisation. */
export function isAcceptablePassword(value: unknown): value is string {
  if (typeof value !== "string") return false;
  const length = [...value.normalize("NFC")].length;
  return length >= PASSWORD_MIN_CHARS && length <= PASSWORD_MAX_CHARS;
}
```

- [ ] **Step 6: Run tests**

Run: `npx vitest run test/policy.test.ts && npm run typecheck`
Expected: PASS, `33 passed (33)`; typecheck exits 0.

- [ ] **Step 7: Commit** (from the repository root)

```bash
git add relay/package.json relay/scripts relay/src/auth/email.ts relay/src/auth/password-policy.ts relay/src/auth/disposable-domains.json relay/test/policy.test.ts
git commit -m "feat(relay): email/password policy and bundled disposable-domain list"
```

---

### Task 4: D1 schema, Worker skeleton, rate-limiter interface, `/v1/version`, environments, `npm run dev`

**Files:**
- Create: `relay/migrations/0001_init.sql`, `relay/src/env.ts`, `relay/src/log.ts`, `relay/src/http/errors.ts`, `relay/src/auth/rate-limit.ts`, `relay/src/app.ts`, `relay/test/env.d.ts`, `relay/test/apply-migrations.ts`, `relay/test/helpers.ts`
- Replace: `relay/src/index.ts`, `relay/wrangler.jsonc`, `relay/vitest.config.ts`
- Modify: `relay/package.json` (scripts)
- Test: `relay/test/app.test.ts`

**Interfaces:**
- Consumes: nothing from earlier tasks at runtime.
- Produces:
  - `env.ts`: `interface Env { DB: D1Database; LOGIN_IP_LIMITER: RateLimit; LOGIN_EMAIL_LIMITER: RateLimit; REGISTER_IP_LIMITER: RateLimit; RATE_LIMITS_ENABLED: string; MIN_AGENT: string; MIN_MOBILE: string; LATEST_AGENT_VERSION: string; MAC_URL: string; WIN_URL: string }` (Task 6 adds `USER_HUB`).
  - `log.ts`: `type LogValue = string | number | boolean | null`; `logMeta(event: string, fields?: Readonly<Record<string, LogValue>>): void`.
  - `http/errors.ts`: `class ApiError extends Error { status; code }`, `Errors.{badRequest, invalidEmail, disposableEmail, weakPassword, invalidDevice, unauthorized, invalidCredentials, agentOnly, forbidden, deviceNotFound, notFound, emailTaken, upgradeRequired, rateLimited}()`, `errorBody(code, message)`, `readJsonObject(request: Request): Promise<Record<string, unknown>>`.
  - `auth/rate-limit.ts`: `interface RateLimiter { limit(key: string): Promise<boolean> }` (true = allowed), `interface RateLimiters { loginIp; loginEmail; registerIp }`, `bindingLimiter(binding: RateLimit): RateLimiter`, `limitersFromEnv(env: Env): RateLimiters` (all-allow when `RATE_LIMITS_ENABLED === "false"`).
  - `app.ts`: `interface AppDeps { limiters?: (env: Env) => RateLimiters; now?: () => number }`, `interface AppVariables { limiters; now }`, `type AppEnv`, `createApp(deps?: AppDeps): Hono<AppEnv>`.
  - `test/helpers.ts`: `BASE`, `allowAll`, `unlimited`, `CountingLimiter`, `TestApp`, `makeApp(deps?)` (injects `unlimited` unless overridden), `CallOptions { body?; token?; ip?; headers?; bindings? }`, `call(app, method, path, options?)`.
  - `npm run dev` on `127.0.0.1:8787` with local migrations applied.

- [ ] **Step 1: Schema, configuration and test harness**

`relay/migrations/0001_init.sql` (spec §10.3 plus two indexes):

```sql
-- ShellX relay schema v1 (spec §10.3). All timestamps are unix milliseconds.
CREATE TABLE users (
  id                  TEXT PRIMARY KEY,
  email               TEXT NOT NULL UNIQUE,
  password_hash       TEXT NOT NULL,
  password_changed_at INTEGER NOT NULL,
  created_at          INTEGER NOT NULL
);

CREATE TABLE devices (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind         TEXT NOT NULL CHECK (kind IN ('agent', 'mobile')),
  name         TEXT NOT NULL,
  platform     TEXT NOT NULL CHECK (platform IN ('macos', 'windows', 'ios', 'android')),
  public_key   BLOB NOT NULL,
  created_at   INTEGER NOT NULL,
  last_seen_at INTEGER,
  UNIQUE (user_id, public_key)
);

CREATE TABLE tokens (
  token_hash   BLOB PRIMARY KEY,
  device_id    TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  created_at   INTEGER NOT NULL,
  last_used_at INTEGER NOT NULL
);

CREATE TABLE pairings (
  agent_id   TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  mobile_id  TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (agent_id, mobile_id)
);

CREATE INDEX tokens_device_id ON tokens (device_id);
CREATE INDEX pairings_mobile_id ON pairings (mobile_id);
```

`relay/wrangler.jsonc` (replace the whole file):

```jsonc
{
  "$schema": "node_modules/wrangler/config-schema.json",
  "name": "shellx-relay",
  "main": "src/index.ts",
  // Must not be newer than the workerd bundled with @cloudflare/vitest-pool-workers,
  // otherwise `npm test` fails with "This Worker requires compatibility date ...".
  "compatibility_date": "2026-08-15",
  "observability": { "enabled": true },

  // ---- Top level = local development only (`npm run dev`, `npm test`). Never deployed. ----
  "workers_dev": false,
  "dev": { "ip": "127.0.0.1", "port": 8787 },
  "d1_databases": [
    {
      "binding": "DB",
      "database_name": "shellx-local",
      "database_id": "00000000-0000-4000-8000-000000000001",
      "migrations_dir": "migrations"
    }
  ],
  "ratelimits": [
    { "name": "LOGIN_IP_LIMITER", "namespace_id": "9001", "simple": { "limit": 10, "period": 60 } },
    { "name": "LOGIN_EMAIL_LIMITER", "namespace_id": "9002", "simple": { "limit": 5, "period": 60 } },
    { "name": "REGISTER_IP_LIMITER", "namespace_id": "9003", "simple": { "limit": 3, "period": 60 } }
  ],
  "vars": {
    // Local only: the plan-03 E2E suite creates many accounts from 127.0.0.1 (overview §4.3).
    "RATE_LIMITS_ENABLED": "false",
    "MIN_AGENT": "1.0.0",
    "MIN_MOBILE": "1.0.0",
    "LATEST_AGENT_VERSION": "1.0.0",
    "MAC_URL": "https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg",
    "WIN_URL": "https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe"
  },

  "env": {
    "staging": {
      "workers_dev": false,
      "routes": [{ "pattern": "relay-staging.shellx.pro", "custom_domain": true }],
      // database_id is added by the runbook (relay/README.md) after `wrangler d1 create shellx-staging`.
      "d1_databases": [{ "binding": "DB", "database_name": "shellx-staging", "migrations_dir": "migrations" }],
      "ratelimits": [
        { "name": "LOGIN_IP_LIMITER", "namespace_id": "2001", "simple": { "limit": 10, "period": 60 } },
        { "name": "LOGIN_EMAIL_LIMITER", "namespace_id": "2002", "simple": { "limit": 5, "period": 60 } },
        { "name": "REGISTER_IP_LIMITER", "namespace_id": "2003", "simple": { "limit": 3, "period": 60 } }
      ],
      "vars": {
        "RATE_LIMITS_ENABLED": "true",
        "MIN_AGENT": "1.0.0",
        "MIN_MOBILE": "1.0.0",
        "LATEST_AGENT_VERSION": "1.0.0",
        "MAC_URL": "https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg",
        "WIN_URL": "https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe"
      }
    },
    "production": {
      "workers_dev": false,
      "routes": [{ "pattern": "relay.shellx.pro", "custom_domain": true }],
      // database_id is added by the runbook (relay/README.md) after `wrangler d1 create shellx-production`.
      "d1_databases": [{ "binding": "DB", "database_name": "shellx-production", "migrations_dir": "migrations" }],
      "ratelimits": [
        { "name": "LOGIN_IP_LIMITER", "namespace_id": "1001", "simple": { "limit": 10, "period": 60 } },
        { "name": "LOGIN_EMAIL_LIMITER", "namespace_id": "1002", "simple": { "limit": 5, "period": 60 } },
        { "name": "REGISTER_IP_LIMITER", "namespace_id": "1003", "simple": { "limit": 3, "period": 60 } }
      ],
      "vars": {
        "RATE_LIMITS_ENABLED": "true",
        "MIN_AGENT": "1.0.0",
        "MIN_MOBILE": "1.0.0",
        "LATEST_AGENT_VERSION": "1.0.0",
        "MAC_URL": "https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg",
        "WIN_URL": "https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe"
      }
    }
  }
}
```

`relay/vitest.config.ts` (replace the whole file):

```ts
import { fileURLToPath } from "node:url";
import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [
    cloudflareTest(async () => ({
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: {
        bindings: {
          TEST_MIGRATIONS: await readD1Migrations(fileURLToPath(new URL("./migrations", import.meta.url))),
        },
      },
    })),
  ],
  test: {
    setupFiles: ["./test/apply-migrations.ts"],
  },
});
```

`relay/test/env.d.ts`:

```ts
import type { D1Migration } from "cloudflare:test";
import type { Env as RelayEnv } from "../src/env";

declare global {
  namespace Cloudflare {
    interface Env extends RelayEnv {
      TEST_MIGRATIONS: D1Migration[];
    }
  }
}
```

`relay/test/apply-migrations.ts`:

```ts
import { applyD1Migrations } from "cloudflare:test";
import { env } from "cloudflare:workers";

// Idempotent: applyD1Migrations records applied migrations in the d1_migrations table.
await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
```

`relay/test/helpers.ts` (Tasks 5 and 6 append to it):

```ts
import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { createApp, type AppDeps } from "../src/app";
import type { RateLimiter, RateLimiters } from "../src/auth/rate-limit";

export const BASE = "http://relay.test";

export const allowAll: RateLimiter = { limit: async () => true };
export const unlimited: RateLimiters = { loginIp: allowAll, loginEmail: allowAll, registerIp: allowAll };

/** Fake limiter: allows `max` calls per key, then refuses; records every key it saw. */
export class CountingLimiter implements RateLimiter {
  readonly calls: string[] = [];
  private readonly counts = new Map<string, number>();
  constructor(private readonly max: number) {}
  async limit(key: string): Promise<boolean> {
    this.calls.push(key);
    const next = (this.counts.get(key) ?? 0) + 1;
    this.counts.set(key, next);
    return next <= this.max;
  }
}

export type TestApp = ReturnType<typeof createApp>;

export function makeApp(deps: AppDeps = {}): TestApp {
  return createApp({ limiters: () => unlimited, ...deps });
}

export interface CallOptions {
  body?: unknown;
  token?: string;
  ip?: string;
  headers?: Record<string, string>;
  /** Overrides individual bindings/vars for this request only. */
  bindings?: Partial<typeof env>;
}

export async function call(app: TestApp, method: string, path: string, options: CallOptions = {}): Promise<Response> {
  const headers = new Headers(options.headers);
  if (options.body !== undefined) headers.set("Content-Type", "application/json");
  if (options.token !== undefined) headers.set("Authorization", `Bearer ${options.token}`);
  headers.set("CF-Connecting-IP", options.ip ?? "203.0.113.7");
  const request = new Request(`${BASE}${path}`, {
    method,
    headers,
    body: options.body === undefined ? undefined : typeof options.body === "string" ? options.body : JSON.stringify(options.body),
  });
  const ctx = createExecutionContext();
  const response = await app.fetch(request, { ...env, ...options.bindings }, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}
```

In `relay/package.json` replace:

```json
  "scripts": {
    "test": "vitest run",
    "typecheck": "tsc -p tsconfig.json && tsc -p scripts/tsconfig.json",
    "domains:update": "tsx scripts/update-disposable-domains.ts"
  },
```

with:

```json
  "scripts": {
    "dev": "wrangler d1 migrations apply DB --local && wrangler dev",
    "test": "vitest run",
    "typecheck": "tsc -p tsconfig.json && tsc -p scripts/tsconfig.json",
    "db:migrate:local": "wrangler d1 migrations apply DB --local",
    "db:migrate:staging": "wrangler d1 migrations apply DB --env staging --remote",
    "db:migrate:production": "wrangler d1 migrations apply DB --env production --remote",
    "deploy:staging": "wrangler deploy --env staging",
    "deploy:production": "wrangler deploy --env production",
    "domains:update": "tsx scripts/update-disposable-domains.ts"
  },
```

- [ ] **Step 2: Write the failing test** — `relay/test/app.test.ts`

```ts
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { bindingLimiter, limitersFromEnv } from "../src/auth/rate-limit";
import { call, makeApp } from "./helpers";

describe("app skeleton", () => {
  it("GET /v1/version returns the configured versions", async () => {
    const res = await call(makeApp(), "GET", "/v1/version");
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      min_agent: "1.0.0",
      min_mobile: "1.0.0",
      latest_agent: {
        version: "1.0.0",
        mac_url: "https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg",
        win_url: "https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe",
      },
    });
  });

  it("unknown routes return the JSON error shape", async () => {
    const res = await call(makeApp(), "GET", "/v1/nope");
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: { code: "not_found", message: "Not found" } });
  });

  it("D1 migrations created the four tables", async () => {
    const { results } = await env.DB.prepare(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('users','devices','tokens','pairings') ORDER BY name",
    ).all<{ name: string }>();
    expect(results.map((r) => r.name)).toEqual(["devices", "pairings", "tokens", "users"]);
  });

  it("bindingLimiter maps the binding outcome and passes the key through", async () => {
    const seen: string[] = [];
    const limiter = bindingLimiter({
      limit: async ({ key }) => {
        seen.push(key);
        return { success: key !== "blocked" };
      },
    });
    expect(await limiter.limit("203.0.113.7")).toBe(true);
    expect(await limiter.limit("blocked")).toBe(false);
    expect(seen).toEqual(["203.0.113.7", "blocked"]);
  });

  it("the local config disables rate limits and still wires the three bindings", async () => {
    expect(env.RATE_LIMITS_ENABLED).toBe("false");
    expect(await bindingLimiter(env.LOGIN_IP_LIMITER).limit("wiring-check")).toBe(true);
    expect(await bindingLimiter(env.LOGIN_EMAIL_LIMITER).limit("wiring-check")).toBe(true);
    expect(await bindingLimiter(env.REGISTER_IP_LIMITER).limit("wiring-check")).toBe(true);
  });

  const refuse: RateLimit = { limit: async () => ({ success: false }) };
  const refusingEnv = (flag: string) => ({
    ...env,
    RATE_LIMITS_ENABLED: flag,
    LOGIN_IP_LIMITER: refuse,
    LOGIN_EMAIL_LIMITER: refuse,
    REGISTER_IP_LIMITER: refuse,
  });

  it('RATE_LIMITS_ENABLED = "false" turns every limiter off', async () => {
    const limiters = limitersFromEnv(refusingEnv("false"));
    expect(await limiters.loginIp.limit("k")).toBe(true);
    expect(await limiters.loginEmail.limit("k")).toBe(true);
    expect(await limiters.registerIp.limit("k")).toBe(true);
  });

  it('any other value ("true" in staging/production) enforces the bindings', async () => {
    for (const flag of ["true", "", "False", "0"]) {
      const limiters = limitersFromEnv(refusingEnv(flag));
      expect(await limiters.loginIp.limit("k")).toBe(false);
      expect(await limiters.loginEmail.limit("k")).toBe(false);
      expect(await limiters.registerIp.limit("k")).toBe(false);
    }
  });
});
```

- [ ] **Step 3: Run it to verify it fails**

Run: `npx vitest run test/app.test.ts`
Expected: FAIL — `Error: Cannot find module '../src/auth/rate-limit' imported from …/test/app.test.ts`

- [ ] **Step 4: Implement** — `relay/src/env.ts`

```ts
export interface Env {
  DB: D1Database;
  LOGIN_IP_LIMITER: RateLimit;
  LOGIN_EMAIL_LIMITER: RateLimit;
  REGISTER_IP_LIMITER: RateLimit;
  /** "false" disables every rate limit (local dev / E2E only); any other value keeps them on. */
  RATE_LIMITS_ENABLED: string;
  MIN_AGENT: string;
  MIN_MOBILE: string;
  LATEST_AGENT_VERSION: string;
  MAC_URL: string;
  WIN_URL: string;
}
```

`relay/src/log.ts`:

```ts
// Metadata-only structured logging (spec §10.5): time, device_id, error codes, frame sizes.
// NEVER pass payloads, tokens, passwords or e-mail addresses to this function.
export type LogValue = string | number | boolean | null;

export function logMeta(event: string, fields: Readonly<Record<string, LogValue>> = {}): void {
  console.log(JSON.stringify({ ts: Date.now(), event, ...fields }));
}
```

`relay/src/http/errors.ts`:

```ts
import type { ContentfulStatusCode } from "hono/utils/http-status";

/** Every API error is rendered as `{"error": {"code", "message"}}` (overview §4.3). */
export class ApiError extends Error {
  constructor(
    readonly status: ContentfulStatusCode,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

export const Errors = {
  badRequest: () => new ApiError(400, "bad_request", "Malformed request body"),
  invalidEmail: () => new ApiError(400, "invalid_email", "Email address is not valid"),
  disposableEmail: () => new ApiError(400, "disposable_email", "Disposable email addresses are not allowed"),
  weakPassword: () => new ApiError(400, "weak_password", "Password must be 8-128 characters"),
  invalidDevice: () => new ApiError(400, "invalid_device", "Device information is not valid"),
  unauthorized: () => new ApiError(401, "unauthorized", "Missing, invalid or expired token"),
  invalidCredentials: () => new ApiError(401, "invalid_credentials", "Email or password is incorrect"),
  agentOnly: () => new ApiError(403, "agent_only", "Only a desktop agent may do this"),
  forbidden: () => new ApiError(403, "forbidden", "Not allowed"),
  deviceNotFound: () => new ApiError(404, "device_not_found", "Device not found"),
  notFound: () => new ApiError(404, "not_found", "Not found"),
  emailTaken: () => new ApiError(409, "email_taken", "Email is already registered"),
  upgradeRequired: () => new ApiError(426, "upgrade_required", "Expected a WebSocket upgrade"),
  rateLimited: () => new ApiError(429, "rate_limited", "Too many requests, try again later"),
} as const;

export function errorBody(code: string, message: string): { error: { code: string; message: string } } {
  return { error: { code, message } };
}

export async function readJsonObject(request: Request): Promise<Record<string, unknown>> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    throw Errors.badRequest();
  }
  if (typeof body !== "object" || body === null || Array.isArray(body)) throw Errors.badRequest();
  return body as Record<string, unknown>;
}
```

`relay/src/auth/rate-limit.ts`:

```ts
import type { Env } from "../env";

/** Returns true when the call is allowed, false when the key is over its limit. */
export interface RateLimiter {
  limit(key: string): Promise<boolean>;
}

export interface RateLimiters {
  loginIp: RateLimiter;
  loginEmail: RateLimiter;
  registerIp: RateLimiter;
}

export function bindingLimiter(binding: RateLimit): RateLimiter {
  return {
    async limit(key) {
      const { success } = await binding.limit({ key });
      return success;
    },
  };
}

const allowAll: RateLimiter = { limit: async () => true };

/**
 * Production wiring: Workers rate limiting bindings (60 s period, limits set in wrangler.jsonc).
 * Only the exact string "false" in RATE_LIMITS_ENABLED turns them off (local dev for the E2E suite).
 */
export function limitersFromEnv(env: Env): RateLimiters {
  if (env.RATE_LIMITS_ENABLED === "false") {
    return { loginIp: allowAll, loginEmail: allowAll, registerIp: allowAll };
  }
  return {
    loginIp: bindingLimiter(env.LOGIN_IP_LIMITER),
    loginEmail: bindingLimiter(env.LOGIN_EMAIL_LIMITER),
    registerIp: bindingLimiter(env.REGISTER_IP_LIMITER),
  };
}
```

`relay/src/app.ts`:

```ts
import { Hono } from "hono";
import { limitersFromEnv, type RateLimiters } from "./auth/rate-limit";
import type { Env } from "./env";
import { ApiError, errorBody, Errors } from "./http/errors";
import { logMeta } from "./log";

export interface AppDeps {
  /** Tests inject fakes; production uses the Workers rate limiting bindings. */
  limiters?: (env: Env) => RateLimiters;
  /** Unix milliseconds; injectable for token-expiry tests. */
  now?: () => number;
}

export interface AppVariables {
  limiters: RateLimiters;
  now: () => number;
}

export type AppEnv = { Bindings: Env; Variables: AppVariables };

export function createApp(deps: AppDeps = {}): Hono<AppEnv> {
  const app = new Hono<AppEnv>();

  app.use("*", async (c, next) => {
    c.set("limiters", (deps.limiters ?? limitersFromEnv)(c.env));
    c.set("now", deps.now ?? Date.now);
    await next();
  });

  app.get("/v1/version", (c) =>
    c.json({
      min_agent: c.env.MIN_AGENT,
      min_mobile: c.env.MIN_MOBILE,
      latest_agent: { version: c.env.LATEST_AGENT_VERSION, mac_url: c.env.MAC_URL, win_url: c.env.WIN_URL },
    }),
  );

  app.notFound((c) => {
    const e = Errors.notFound();
    return c.json(errorBody(e.code, e.message), e.status);
  });

  app.onError((err, c) => {
    if (err instanceof ApiError) return c.json(errorBody(err.code, err.message), err.status);
    logMeta("unhandled_error", { method: c.req.method, path: new URL(c.req.url).pathname, error: err.name });
    return c.json(errorBody("internal_error", "Internal error"), 500);
  });

  return app;
}
```

`relay/src/index.ts` (replace the whole file):

```ts
import { createApp } from "./app";
import type { Env } from "./env";

const app = createApp();

export default {
  fetch: (request, env, ctx) => app.fetch(request, env, ctx),
} satisfies ExportedHandler<Env>;
```

- [ ] **Step 5: Run tests**

Run: `npx vitest run && npm run typecheck`
Expected: PASS, `58 passed (58)` (all suites so far); typecheck exits 0.

- [ ] **Step 6: Check the dev server contract (overview §4.3)**

Run: `npm run dev -- --ip 127.0.0.1 --port 8787` in a second terminal (first interactive run asks to apply `0001_init.sql`: answer `y`), then:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8787/v1/version
curl -s http://127.0.0.1:8787/v1/nope
```

Expected: `200`, then `{"error":{"code":"not_found","message":"Not found"}}`. Stop the server with Ctrl+C; `npm run dev` without arguments must behave the same (host/port come from `wrangler.jsonc`).

- [ ] **Step 7: Commit** (from the repository root)

```bash
git add relay/package.json relay/wrangler.jsonc relay/vitest.config.ts relay/migrations relay/src relay/test
git commit -m "feat(relay): D1 schema, Hono skeleton, rate-limiter interface, /v1/version and dev server"
```

---

### Task 5: Tokens, device input, `POST /v1/auth/register` and `POST /v1/auth/login`

**Files:**
- Create: `relay/src/auth/tokens.ts`, `relay/src/auth/device.ts`, `relay/src/auth/session.ts`, `relay/src/routes/auth.ts`
- Modify: `relay/src/app.ts`, `relay/test/helpers.ts` (append)
- Test: `relay/test/auth.test.ts`

**Interfaces:**
- Consumes: `hashPassword`, `verifyPassword` (Task 1); `checkEmail`, `normalizeEmail`, `isAcceptablePassword` (Task 3); `Errors`, `readJsonObject`, `logMeta`, `AppEnv`, `createApp`, `RateLimiters`, test `call`/`makeApp`/`CountingLimiter`/`unlimited` (Task 4).
- Produces:
  - `tokens.ts`: `TOKEN_BYTES = 32`, `TOKEN_IDLE_TTL_MS = 90 d`, `TOKEN_TOUCH_INTERVAL_MS = 1 h`, `base64UrlEncode(bytes: Uint8Array): string`, `base64UrlDecode(input: string): Uint8Array | null`, `generateToken(): string`, `hashToken(token: string): Promise<ArrayBuffer>`, `parseBearer(header: string | null | undefined): string | null`.
  - `device.ts`: `type DeviceKind = "agent" | "mobile"`, `type DevicePlatform`, `DEVICE_KINDS`, `DEVICE_PLATFORMS`, `DEVICE_NAME_MAX_CHARS = 100`, `interface DeviceInput { kind; name; platform; publicKey: Uint8Array }`, `isDeviceKind(value: unknown)`, `parseDevice(value: unknown): DeviceInput | null`.
  - `session.ts`: `interface AuthContext { userId: string; deviceId: string; kind: DeviceKind }`, `insertTokenStatement(db, tokenHash: ArrayBuffer, deviceId: string, now: number): D1PreparedStatement`, `authenticate(db: D1Database, token: string | null, now: number): Promise<AuthContext | null>`, `requireAuth: MiddlewareHandler<AppEnv>` (sets `c.get("auth")`, else 401 `unauthorized`).
  - `routes/auth.ts`: `authRoutes` (`POST /register` → 201, `POST /login` → 200, both `{user_id, device_id, token}`), mounted at `/v1/auth`.
  - `AppVariables.auth: AuthContext`.
  - Test helpers: `PASSWORD`, `randomEmail()`, `randomPublicKey()`, `type Kind`, `deviceBody(kind, overrides?)`, `interface Session { userId; deviceId; token; publicKey }`, `interface Account { email; password; agent: Session }`, `registerAccount(app, email?, password?): Promise<Account>`, `loginDevice(app, account, kind, publicKey?): Promise<Session>`, `errorCode(res): Promise<string>`.

- [ ] **Step 1: Write the failing test**

Append to `relay/test/helpers.ts` (leave one blank line before it):

```ts
export const PASSWORD = "correct horse battery";

export function randomEmail(): string {
  return `user-${crypto.randomUUID()}@example.com`;
}

export function randomPublicKey(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

export type Kind = "agent" | "mobile";

export function deviceBody(kind: Kind, overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    kind,
    name: kind === "agent" ? "MacBook-Pro" : "iPhone 16",
    platform: kind === "agent" ? "macos" : "ios",
    public_key: randomPublicKey(),
    ...overrides,
  };
}

export interface Session {
  userId: string;
  deviceId: string;
  token: string;
  publicKey: string;
}

export interface Account {
  email: string;
  password: string;
  agent: Session;
}

/** Registers a fresh account whose first device is an agent. */
export async function registerAccount(app: TestApp, email = randomEmail(), password = PASSWORD): Promise<Account> {
  const device = deviceBody("agent");
  const res = await call(app, "POST", "/v1/auth/register", { body: { email, password, device } });
  if (res.status !== 201) throw new Error(`register failed: ${res.status} ${await res.text()}`);
  const body = await res.json<{ user_id: string; device_id: string; token: string }>();
  return {
    email,
    password,
    agent: { userId: body.user_id, deviceId: body.device_id, token: body.token, publicKey: device.public_key as string },
  };
}

/** Logs in an additional device (new key unless `publicKey` is given). */
export async function loginDevice(app: TestApp, account: Account, kind: Kind, publicKey = randomPublicKey()): Promise<Session> {
  const res = await call(app, "POST", "/v1/auth/login", {
    body: { email: account.email, password: account.password, device: deviceBody(kind, { public_key: publicKey }) },
  });
  if (res.status !== 200) throw new Error(`login failed: ${res.status} ${await res.text()}`);
  const body = await res.json<{ user_id: string; device_id: string; token: string }>();
  return { userId: body.user_id, deviceId: body.device_id, token: body.token, publicKey };
}

export async function errorCode(res: Response): Promise<string> {
  const body = await res.json<{ error: { code: string; message: string } }>();
  return body.error.code;
}
```

Create `relay/test/auth.test.ts`:

```ts
import { env } from "cloudflare:workers";
import { afterEach, describe, expect, it, vi } from "vitest";
import { createApp } from "../src/app";
import { authenticate } from "../src/auth/session";
import { hashToken, TOKEN_IDLE_TTL_MS, TOKEN_TOUCH_INTERVAL_MS } from "../src/auth/tokens";
import {
  call, CountingLimiter, deviceBody, errorCode, loginDevice, makeApp, PASSWORD, randomEmail, randomPublicKey,
  registerAccount, unlimited,
} from "./helpers";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

afterEach(() => {
  vi.restoreAllMocks();
});

describe("POST /v1/auth/register", () => {
  it("creates user, device and token; stores only hashes", async () => {
    const app = makeApp();
    const email = randomEmail();
    const device = deviceBody("agent");
    const res = await call(app, "POST", "/v1/auth/register", { body: { email, password: PASSWORD, device } });
    expect(res.status).toBe(201);
    const body = await res.json<{ user_id: string; device_id: string; token: string }>();
    expect(body.user_id).toMatch(UUID_RE);
    expect(body.device_id).toMatch(UUID_RE);
    expect(body.token).toMatch(/^[A-Za-z0-9_-]{43}$/);

    const user = await env.DB.prepare("SELECT email, password_hash FROM users WHERE id = ?")
      .bind(body.user_id).first<{ email: string; password_hash: string }>();
    expect(user?.email).toBe(email);
    expect(user?.password_hash).toMatch(/^\$argon2id\$v=19\$m=19456,t=2,p=1\$/);

    const tokenRow = await env.DB.prepare("SELECT device_id FROM tokens WHERE token_hash = ?")
      .bind(await hashToken(body.token)).first<{ device_id: string }>();
    expect(tokenRow?.device_id).toBe(body.device_id);
    const rawToken = await env.DB.prepare("SELECT COUNT(*) AS n FROM tokens WHERE token_hash = ?")
      .bind(body.token).first<{ n: number }>();
    expect(rawToken?.n).toBe(0);
  });

  it("normalises the email (whitespace + uppercase) before storing", async () => {
    const app = makeApp();
    const local = `Mixed.Case-${crypto.randomUUID()}`;
    const res = await call(app, "POST", "/v1/auth/register", {
      body: { email: `  ${local}@Example.COM \n`, password: PASSWORD, device: deviceBody("agent") },
    });
    expect(res.status).toBe(201);
    const { user_id } = await res.json<{ user_id: string }>();
    const row = await env.DB.prepare("SELECT email FROM users WHERE id = ?").bind(user_id).first<{ email: string }>();
    expect(row?.email).toBe(`${local.toLowerCase()}@example.com`);
  });

  it.each([
    [{ email: "not-an-email" }, 400, "invalid_email"],
    [{ email: 42 }, 400, "invalid_email"],
    [{ email: "someone@yopmail.com" }, 400, "disposable_email"],
    [{ email: "someone@x.yopmail.com" }, 400, "disposable_email"],
    [{ email: "  Someone@X.YOPMAIL.com " }, 400, "disposable_email"],
    [{ password: "1234567" }, 400, "weak_password"],
    [{ password: "x".repeat(129) }, 400, "weak_password"],
    [{ password: 12345678 }, 400, "weak_password"],
    [{ device: undefined }, 400, "invalid_device"],
    [{ device: deviceBody("agent", { kind: "tablet" }) }, 400, "invalid_device"],
    [{ device: deviceBody("agent", { platform: "linux" }) }, 400, "invalid_device"],
    [{ device: deviceBody("agent", { name: "   " }) }, 400, "invalid_device"],
    [{ device: deviceBody("agent", { name: "n".repeat(101) }) }, 400, "invalid_device"],
    [{ device: deviceBody("agent", { public_key: "AAAA" }) }, 400, "invalid_device"],
    [{ device: deviceBody("agent", { public_key: `${randomPublicKey()}=` }) }, 400, "invalid_device"],
  ])("rejects %j with %i %s", async (override, status, code) => {
    const body = { email: randomEmail(), password: PASSWORD, device: deviceBody("agent"), ...override };
    const res = await call(makeApp(), "POST", "/v1/auth/register", { body });
    expect(res.status).toBe(status);
    expect(await errorCode(res)).toBe(code);
  });

  it("rejects a non-JSON body with 400 bad_request", async () => {
    const res = await call(makeApp(), "POST", "/v1/auth/register", { body: "{not json" });
    expect(res.status).toBe(400);
    expect(await errorCode(res)).toBe("bad_request");
  });

  it("returns 409 email_taken for the same address in a different case", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const res = await call(app, "POST", "/v1/auth/register", {
      body: { email: ` ${account.email.toUpperCase()} `, password: PASSWORD, device: deviceBody("agent") },
    });
    expect(res.status).toBe(409);
    expect(await errorCode(res)).toBe("email_taken");
  });

  it("returns 429 rate_limited once the per-IP register limiter refuses", async () => {
    const registerIp = new CountingLimiter(3);
    const app = makeApp({ limiters: () => ({ ...unlimited, registerIp }) });
    for (let i = 0; i < 3; i++) {
      const ok = await call(app, "POST", "/v1/auth/register", {
        ip: "198.51.100.1",
        body: { email: randomEmail(), password: PASSWORD, device: deviceBody("agent") },
      });
      expect(ok.status).toBe(201);
    }
    const res = await call(app, "POST", "/v1/auth/register", {
      ip: "198.51.100.1",
      body: { email: randomEmail(), password: PASSWORD, device: deviceBody("agent") },
    });
    expect(res.status).toBe(429);
    expect(await errorCode(res)).toBe("rate_limited");
    expect(registerIp.calls).toEqual(Array(4).fill("198.51.100.1"));
  });
});

describe("production rate-limit wiring (no injected fakes)", () => {
  const refuse: RateLimit = { limit: async () => ({ success: false }) };
  const refusing = { LOGIN_IP_LIMITER: refuse, LOGIN_EMAIL_LIMITER: refuse, REGISTER_IP_LIMITER: refuse };
  const register = (flag: string) =>
    call(createApp(), "POST", "/v1/auth/register", {
      bindings: { ...refusing, RATE_LIMITS_ENABLED: flag },
      body: { email: randomEmail(), password: PASSWORD, device: deviceBody("agent") },
    });

  it('answers 429 when RATE_LIMITS_ENABLED is "true" and the binding refuses', async () => {
    const res = await register("true");
    expect(res.status).toBe(429);
    expect(await errorCode(res)).toBe("rate_limited");
  });

  it('ignores the bindings when RATE_LIMITS_ENABLED is "false"', async () => {
    expect((await register("false")).status).toBe(201);
  });
});

describe("POST /v1/auth/login", () => {
  it("logs in with a differently-cased, padded email and creates a new device for a new key", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const res = await call(app, "POST", "/v1/auth/login", {
      body: { email: `\t${account.email.toUpperCase()}  `, password: PASSWORD, device: deviceBody("mobile") },
    });
    expect(res.status).toBe(200);
    const body = await res.json<{ user_id: string; device_id: string; token: string }>();
    expect(body.user_id).toBe(account.agent.userId);
    expect(body.device_id).not.toBe(account.agent.deviceId);
    expect(body.token).toMatch(/^[A-Za-z0-9_-]{43}$/);
  });

  it("reuses the device_id for a known public key and replaces its previous token", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const first = await loginDevice(app, account, "mobile");
    const second = await loginDevice(app, account, "mobile", first.publicKey);
    expect(second.deviceId).toBe(first.deviceId);
    const now = Date.now();
    expect(await authenticate(env.DB, first.token, now)).toBeNull();
    expect(await authenticate(env.DB, second.token, now)).toEqual({
      userId: account.agent.userId, deviceId: first.deviceId, kind: "mobile",
    });
  });

  it("returns 401 invalid_credentials for a wrong password or an unknown email", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const wrong = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: "wrong password", device: deviceBody("mobile") },
    });
    expect(wrong.status).toBe(401);
    expect(await errorCode(wrong)).toBe("invalid_credentials");
    const unknown = await call(app, "POST", "/v1/auth/login", {
      body: { email: randomEmail(), password: PASSWORD, device: deviceBody("mobile") },
    });
    expect(unknown.status).toBe(401);
    expect(await errorCode(unknown)).toBe("invalid_credentials");
  });

  it("accepts an NFC password for an account registered with the NFD spelling", async () => {
    const app = makeApp();
    const nfc = "Mật khẩu đẹp 2026".normalize("NFC");
    const account = await registerAccount(app, randomEmail(), nfc.normalize("NFD"));
    const res = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: nfc, device: deviceBody("mobile") },
    });
    expect(res.status).toBe(200);
  });

  it("rate limits per IP (10) and per normalised email (5)", async () => {
    const loginIp = new CountingLimiter(10);
    const loginEmail = new CountingLimiter(5);
    const app = makeApp({ limiters: () => ({ ...unlimited, loginIp, loginEmail }) });
    const account = await registerAccount(app);
    const attempt = (email: string, ip: string) =>
      call(app, "POST", "/v1/auth/login", { ip, body: { email, password: "wrong password", device: deviceBody("mobile") } });

    // 5 attempts for one email from 5 different IPs (with case variants) are allowed ...
    for (let i = 0; i < 5; i++) expect((await attempt(i % 2 ? account.email.toUpperCase() : account.email, `192.0.2.${i}`)).status).toBe(401);
    // ... the 6th for the same email is refused even from a fresh IP.
    const sixth = await attempt(` ${account.email} `, "192.0.2.99");
    expect(sixth.status).toBe(429);
    expect(await errorCode(sixth)).toBe("rate_limited");
    expect(new Set(loginEmail.calls)).toEqual(new Set([account.email]));

    // 10 attempts from one IP (different emails) are allowed, the 11th is refused.
    for (let i = 0; i < 10; i++) expect((await attempt(randomEmail(), "198.51.100.200")).status).toBe(401);
    const eleventh = await attempt(randomEmail(), "198.51.100.200");
    expect(eleventh.status).toBe(429);
  });

  it("never logs passwords, tokens or email addresses", async () => {
    const lines: string[] = [];
    const capture = (...args: unknown[]) => { lines.push(args.map(String).join(" ")); };
    vi.spyOn(console, "log").mockImplementation(capture);
    vi.spyOn(console, "info").mockImplementation(capture);
    vi.spyOn(console, "warn").mockImplementation(capture);
    vi.spyOn(console, "error").mockImplementation(capture);
    const app = makeApp();
    const password = "Secret-Pa55word-XYZ";
    const account = await registerAccount(app, randomEmail(), password);
    await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: "Wrong-Pa55word-XYZ", device: deviceBody("mobile") },
    });
    const session = await loginDevice(app, account, "mobile");
    const output = lines.join("\n");
    expect(lines.length).toBeGreaterThan(0);
    for (const secret of [password, "Wrong-Pa55word-XYZ", account.agent.token, session.token, account.email]) {
      expect(output).not.toContain(secret);
    }
  });
});

describe("token lifetime", () => {
  it("expires after 90 idle days and refreshes last_used_at at most hourly", async () => {
    const t0 = 1_800_000_000_000;
    const app = makeApp({ now: () => t0 });
    const account = await registerAccount(app);
    const hash = await hashToken(account.agent.token);
    const lastUsed = async () =>
      (await env.DB.prepare("SELECT last_used_at FROM tokens WHERE token_hash = ?").bind(hash)
        .first<{ last_used_at: number }>())?.last_used_at;

    expect(await authenticate(env.DB, account.agent.token, t0 + 30 * 60 * 1000)).not.toBeNull();
    expect(await lastUsed()).toBe(t0);
    const t1 = t0 + TOKEN_TOUCH_INTERVAL_MS;
    expect(await authenticate(env.DB, account.agent.token, t1)).not.toBeNull();
    expect(await lastUsed()).toBe(t1);

    expect(await authenticate(env.DB, account.agent.token, t1 + TOKEN_IDLE_TTL_MS)).not.toBeNull();
    const t2 = t1 + TOKEN_IDLE_TTL_MS;
    expect(await authenticate(env.DB, account.agent.token, t2 + TOKEN_IDLE_TTL_MS + 1)).toBeNull();
    expect(await lastUsed()).toBeUndefined();
  });

  it("rejects missing and malformed tokens", async () => {
    expect(await authenticate(env.DB, null, Date.now())).toBeNull();
    expect(await authenticate(env.DB, "A".repeat(43), Date.now())).toBeNull();
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `npx vitest run test/auth.test.ts`
Expected: FAIL — `Error: Cannot find module '../src/auth/session' imported from …/test/auth.test.ts`

- [ ] **Step 3: Implement** — `relay/src/auth/tokens.ts`

```ts
export const TOKEN_BYTES = 32;
export const TOKEN_IDLE_TTL_MS = 90 * 24 * 60 * 60 * 1000;
export const TOKEN_TOUCH_INTERVAL_MS = 60 * 60 * 1000;

const BASE64URL_RE = /^[A-Za-z0-9_-]*$/;
const TOKEN_RE = /^[A-Za-z0-9_-]{43}$/;

export function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

/** Strict unpadded base64url; null on any invalid input. */
export function base64UrlDecode(input: string): Uint8Array | null {
  if (!BASE64URL_RE.test(input) || input.length % 4 === 1) return null;
  const padded = input.replaceAll("-", "+").replaceAll("_", "/") + "=".repeat((4 - (input.length % 4)) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, (ch) => ch.charCodeAt(0));
}

/** 32 random bytes, base64url without padding (43 characters). */
export function generateToken(): string {
  return base64UrlEncode(crypto.getRandomValues(new Uint8Array(TOKEN_BYTES)));
}

/** SHA-256 of the token string; this is the only form stored in D1. */
export async function hashToken(token: string): Promise<ArrayBuffer> {
  return crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
}

export function parseBearer(header: string | null | undefined): string | null {
  if (!header) return null;
  const match = /^Bearer ([A-Za-z0-9_-]+)$/.exec(header.trim());
  if (!match || !TOKEN_RE.test(match[1]!)) return null;
  return match[1]!;
}
```

`relay/src/auth/device.ts`:

```ts
import { base64UrlDecode } from "./tokens";

export type DeviceKind = "agent" | "mobile";
export type DevicePlatform = "macos" | "windows" | "ios" | "android";

export const DEVICE_KINDS: readonly DeviceKind[] = ["agent", "mobile"];
export const DEVICE_PLATFORMS: readonly DevicePlatform[] = ["macos", "windows", "ios", "android"];
export const DEVICE_NAME_MAX_CHARS = 100;

export interface DeviceInput {
  kind: DeviceKind;
  name: string;
  platform: DevicePlatform;
  publicKey: Uint8Array; // X25519, 32 bytes
}

export function isDeviceKind(value: unknown): value is DeviceKind {
  return typeof value === "string" && (DEVICE_KINDS as readonly string[]).includes(value);
}

/** Validates `{kind, name, platform, public_key}` (spec §10.2); null when anything is off. */
export function parseDevice(value: unknown): DeviceInput | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return null;
  const v = value as Record<string, unknown>;
  if (!isDeviceKind(v.kind)) return null;
  if (typeof v.platform !== "string" || !(DEVICE_PLATFORMS as readonly string[]).includes(v.platform)) return null;
  if (typeof v.name !== "string") return null;
  const name = v.name.trim();
  const nameLength = [...name].length;
  if (nameLength < 1 || nameLength > DEVICE_NAME_MAX_CHARS) return null;
  if (typeof v.public_key !== "string") return null;
  const publicKey = base64UrlDecode(v.public_key);
  if (publicKey === null || publicKey.length !== 32) return null;
  return { kind: v.kind, name, platform: v.platform as DevicePlatform, publicKey };
}
```

`relay/src/auth/session.ts`:

```ts
import type { MiddlewareHandler } from "hono";
import type { AppEnv } from "../app";
import { Errors } from "../http/errors";
import type { DeviceKind } from "./device";
import { hashToken, parseBearer, TOKEN_IDLE_TTL_MS, TOKEN_TOUCH_INTERVAL_MS } from "./tokens";

export interface AuthContext {
  userId: string;
  deviceId: string;
  kind: DeviceKind;
}

interface TokenRow {
  device_id: string;
  last_used_at: number;
  user_id: string;
  kind: DeviceKind;
}

export function insertTokenStatement(db: D1Database, tokenHash: ArrayBuffer, deviceId: string, now: number) {
  return db
    .prepare("INSERT INTO tokens (token_hash, device_id, created_at, last_used_at) VALUES (?, ?, ?, ?)")
    .bind(tokenHash, deviceId, now, now);
}

/**
 * Resolves a bearer token. Tokens idle for more than 90 days are deleted and rejected;
 * `last_used_at` is refreshed at most once per hour.
 */
export async function authenticate(db: D1Database, token: string | null, now: number): Promise<AuthContext | null> {
  if (token === null) return null;
  const tokenHash = await hashToken(token);
  const row = await db
    .prepare(
      `SELECT t.device_id, t.last_used_at, d.user_id, d.kind
         FROM tokens t JOIN devices d ON d.id = t.device_id
        WHERE t.token_hash = ?`,
    )
    .bind(tokenHash)
    .first<TokenRow>();
  if (row === null) return null;
  if (now - row.last_used_at > TOKEN_IDLE_TTL_MS) {
    await db.prepare("DELETE FROM tokens WHERE token_hash = ?").bind(tokenHash).run();
    return null;
  }
  if (now - row.last_used_at >= TOKEN_TOUCH_INTERVAL_MS) {
    await db.prepare("UPDATE tokens SET last_used_at = ? WHERE token_hash = ?").bind(now, tokenHash).run();
  }
  return { userId: row.user_id, deviceId: row.device_id, kind: row.kind };
}

export const requireAuth: MiddlewareHandler<AppEnv> = async (c, next) => {
  const auth = await authenticate(c.env.DB, parseBearer(c.req.header("Authorization")), c.get("now")());
  if (auth === null) throw Errors.unauthorized();
  c.set("auth", auth);
  await next();
};
```

`relay/src/routes/auth.ts`:

```ts
import { Hono, type Context } from "hono";
import type { AppEnv } from "../app";
import { parseDevice, type DeviceInput } from "../auth/device";
import { checkEmail, normalizeEmail } from "../auth/email";
import { hashPassword, verifyPassword } from "../auth/password";
import { isAcceptablePassword } from "../auth/password-policy";
import { insertTokenStatement } from "../auth/session";
import { generateToken, hashToken } from "../auth/tokens";
import { Errors, readJsonObject } from "../http/errors";
import { logMeta } from "../log";

export const authRoutes = new Hono<AppEnv>();

function clientIp(c: Context<AppEnv>): string {
  return c.req.header("CF-Connecting-IP") ?? "unknown";
}

function upsertDeviceStatement(db: D1Database, userId: string, device: DeviceInput, now: number) {
  // Same public key in the same account → same device_id (spec §5.2); name/platform refreshed.
  return db
    .prepare(
      `INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT (user_id, public_key) DO UPDATE SET name = excluded.name, platform = excluded.platform
       RETURNING id`,
    )
    .bind(crypto.randomUUID(), userId, device.kind, device.name, device.platform, device.publicKey, now);
}

let dummyPhc: Promise<string> | undefined;
/** Verifying against a throwaway hash keeps unknown-email logins as slow as wrong-password ones. */
function dummyHash(): Promise<string> {
  dummyPhc ??= hashPassword("shellx-dummy-password");
  return dummyPhc;
}

authRoutes.post("/register", async (c) => {
  if (!(await c.get("limiters").registerIp.limit(clientIp(c)))) throw Errors.rateLimited();
  const body = await readJsonObject(c.req.raw);
  const email = checkEmail(body.email);
  if (!email.ok) throw email.code === "invalid_email" ? Errors.invalidEmail() : Errors.disposableEmail();
  if (!isAcceptablePassword(body.password)) throw Errors.weakPassword();
  const device = parseDevice(body.device);
  if (device === null) throw Errors.invalidDevice();

  const db = c.env.DB;
  if ((await db.prepare("SELECT 1 FROM users WHERE email = ?").bind(email.email).first()) !== null) {
    throw Errors.emailTaken();
  }
  const now = c.get("now")();
  const userId = crypto.randomUUID();
  const deviceId = crypto.randomUUID();
  const passwordHash = await hashPassword(body.password);
  const token = generateToken();
  try {
    await db.batch([
      db
        .prepare("INSERT INTO users (id, email, password_hash, password_changed_at, created_at) VALUES (?, ?, ?, ?, ?)")
        .bind(userId, email.email, passwordHash, now, now),
      db
        .prepare(
          "INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(deviceId, userId, device.kind, device.name, device.platform, device.publicKey, now),
      insertTokenStatement(db, await hashToken(token), deviceId, now),
    ]);
  } catch (err) {
    if (String(err).includes("UNIQUE constraint failed: users.email")) throw Errors.emailTaken();
    throw err;
  }
  logMeta("register", { device_id: deviceId });
  return c.json({ user_id: userId, device_id: deviceId, token }, 201);
});

authRoutes.post("/login", async (c) => {
  const limiters = c.get("limiters");
  if (!(await limiters.loginIp.limit(clientIp(c)))) throw Errors.rateLimited();
  const body = await readJsonObject(c.req.raw);
  const email = typeof body.email === "string" ? normalizeEmail(body.email) : "";
  if (!(await limiters.loginEmail.limit(email))) throw Errors.rateLimited();
  const device = parseDevice(body.device);
  if (device === null) throw Errors.invalidDevice();
  const password = typeof body.password === "string" ? body.password : "";

  const db = c.env.DB;
  const user = await db
    .prepare("SELECT id, password_hash FROM users WHERE email = ?")
    .bind(email)
    .first<{ id: string; password_hash: string }>();
  const passwordOk = await verifyPassword(password, user?.password_hash ?? (await dummyHash()));
  if (user === null || !passwordOk) {
    logMeta("login_failed");
    throw Errors.invalidCredentials();
  }

  const now = c.get("now")();
  const row = await upsertDeviceStatement(db, user.id, device, now).first<{ id: string }>();
  const deviceId = row!.id;
  const token = generateToken();
  // One live token per device: logging in again replaces the previous token.
  await db.batch([
    db.prepare("DELETE FROM tokens WHERE device_id = ?").bind(deviceId),
    insertTokenStatement(db, await hashToken(token), deviceId, now),
  ]);
  logMeta("login", { device_id: deviceId });
  return c.json({ user_id: user.id, device_id: deviceId, token }, 200);
});
```

Wire it into the app:

In `relay/src/app.ts` replace:

```ts
import { limitersFromEnv, type RateLimiters } from "./auth/rate-limit";
```

with:

```ts
import { limitersFromEnv, type RateLimiters } from "./auth/rate-limit";
import type { AuthContext } from "./auth/session";
```

In `relay/src/app.ts` replace:

```ts
import { logMeta } from "./log";
```

with:

```ts
import { logMeta } from "./log";
import { authRoutes } from "./routes/auth";
```

In `relay/src/app.ts` replace:

```ts
  now: () => number;
}
```

with:

```ts
  now: () => number;
  /** Set by `requireAuth` on authenticated routes only. */
  auth: AuthContext;
}
```

In `relay/src/app.ts` replace:

```ts
  app.notFound((c) => {
```

with:

```ts
  app.route("/v1/auth", authRoutes);

  app.notFound((c) => {
```

- [ ] **Step 4: Run tests**

Run: `npx vitest run && npm run typecheck`
Expected: PASS, `88 passed (88)`; typecheck exits 0.

- [ ] **Step 5: Commit** (from the repository root)

```bash
git add relay/src relay/test
git commit -m "feat(relay): device tokens, register and login with rate limits"
```

---

### Task 6: `UserHub` Durable Object and `GET /v1/ws` — presence, routing, errors, 64 KiB limit, replacement

Hibernation design: the hub keeps **no** in-memory state that matters. Each socket's `{device_id, kind, closing?}` lives in its attachment (`serializeAttachment`), sockets are tagged with their `device_id` (`acceptWebSocket(server, [deviceId])`), and every decision re-reads `ctx.getWebSockets(...)`, so a hub woken from hibernation behaves exactly like one that never slept. `closing` marks sockets the hub closed itself (4001/4002/4003) so their later close events are ignored.

**Files:**
- Create: `relay/src/hub/user-hub.ts`, `relay/src/routes/ws.ts`
- Replace: `relay/src/env.ts`, `relay/src/index.ts`, `relay/wrangler.jsonc`
- Modify: `relay/src/app.ts`, `relay/test/helpers.ts` (append)
- Test: `relay/test/hub.test.ts`

**Interfaces:**
- Consumes: `authenticate`, `parseBearer` (Task 5); frame encoders, `parseDataHeader`, `withPeer`, `CloseCode`, `RelayErrorCode`, `MAX_FRAME_BYTES`, `parseUuid` (Task 2); `logMeta`, `Errors` (Task 4); test helpers from Tasks 4–5.
- Produces:
  - `hub/user-hub.ts`: `DEVICE_ID_HEADER = "X-Shellx-Device-Id"`, `DEVICE_KIND_HEADER = "X-Shellx-Device-Kind"`, `hubFor(env: Env, userId: string): DurableObjectStub<UserHub>`, `interface Attachment { device_id: string; kind: DeviceKind; closing?: boolean }`, `class UserHub extends DurableObject<Env>` with `fetch`, `webSocketMessage`, `webSocketClose`, `webSocketError`; private helpers `socketGone`, `closeSocket(ws, code: CloseCode)`, `markOffline(deviceId: string): Promise<void>`, `socketsOf(deviceId)`, `liveDeviceIds()`, `broadcast(frame, exceptDeviceId)`.
  - `routes/ws.ts`: `webSocketRoute(c: Context<AppEnv>): Promise<Response>` at `GET /v1/ws`.
  - `Env.USER_HUB: DurableObjectNamespace<UserHub>`; `wrangler.jsonc` binding `USER_HUB` + migration `v1` `new_sqlite_classes: ["UserHub"]` in every environment.
  - Test helpers: `interface CloseInfo { code; reason }`, `class TestSocket` (`next`, `nextBinary`, `expectSilence`, `send`, `close`, `closed`), `connect(app, token): Promise<TestSocket>`, `hex(bytes)`, `waitFor(probe, timeoutMs?)`.

- [ ] **Step 1: Write the failing test**

Append to `relay/test/helpers.ts` (leave one blank line before it):

```ts
export interface CloseInfo {
  code: number;
  reason: string;
}

/** Client end of a relay WebSocket with an awaitable message queue. */
export class TestSocket {
  private readonly queue: (Uint8Array | string)[] = [];
  private notify: (() => void) | null = null;
  readonly closed: Promise<CloseInfo>;

  constructor(readonly ws: WebSocket) {
    // With current compatibility dates the standard default is "blob"; frames are easier as bytes.
    ws.binaryType = "arraybuffer";
    ws.accept();
    ws.addEventListener("message", (event) => {
      this.queue.push(typeof event.data === "string" ? event.data : new Uint8Array(event.data as ArrayBuffer));
      this.notify?.();
    });
    this.closed = new Promise((resolve) => {
      ws.addEventListener("close", (event) => {
        resolve({ code: event.code, reason: event.reason });
        this.notify?.();
      });
    });
  }

  async next(timeoutMs = 2000): Promise<Uint8Array | string> {
    const deadline = Date.now() + timeoutMs;
    while (this.queue.length === 0) {
      const remaining = deadline - Date.now();
      if (remaining <= 0) throw new Error("timed out waiting for a message");
      await new Promise<void>((resolve) => {
        const timer = setTimeout(resolve, remaining);
        this.notify = () => {
          clearTimeout(timer);
          resolve();
        };
      });
      this.notify = null;
    }
    return this.queue.shift()!;
  }

  async nextBinary(timeoutMs = 2000): Promise<Uint8Array> {
    const message = await this.next(timeoutMs);
    if (typeof message === "string") throw new Error(`expected a binary frame, got text ${JSON.stringify(message)}`);
    return message;
  }

  /** Resolves if nothing arrives within `ms`; throws with the unexpected message otherwise. */
  async expectSilence(ms = 250): Promise<void> {
    await new Promise((resolve) => setTimeout(resolve, ms));
    if (this.queue.length > 0) throw new Error(`unexpected message: ${String(this.queue[0])}`);
  }

  send(data: Uint8Array | string): void {
    this.ws.send(data);
  }

  close(code = 1000): void {
    this.ws.close(code, "bye");
  }
}

export async function connect(app: TestApp, token: string | undefined): Promise<TestSocket> {
  const res = await call(app, "GET", "/v1/ws", { token, headers: { Upgrade: "websocket" } });
  if (res.status !== 101 || res.webSocket === null) throw new Error(`upgrade failed: ${res.status}`);
  return new TestSocket(res.webSocket);
}

export function hex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

export async function waitFor<T>(probe: () => Promise<T | null | undefined>, timeoutMs = 2000): Promise<T> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const value = await probe();
    if (value !== null && value !== undefined) return value;
    if (Date.now() > deadline) throw new Error("condition not met in time");
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
}
```

Create `relay/test/hub.test.ts`:

```ts
import { env } from "cloudflare:workers";
import { afterEach, describe, expect, it, vi } from "vitest";
import { encodeData, encodeError, encodePresence, MAX_FRAME_BYTES, RelayErrorCode } from "../src/protocol/frames";
import {
  call, connect, errorCode, hex, loginDevice, makeApp, registerAccount, type TestApp, waitFor,
} from "./helpers";

const CH = Uint8Array.from([9, 8, 7, 6, 5, 4, 3, 2]);

afterEach(() => {
  vi.restoreAllMocks();
});

async function accountWithAgentAndMobile() {
  const app = makeApp();
  const account = await registerAccount(app);
  const mobile = await loginDevice(app, account, "mobile");
  return { app, account, agent: account.agent, mobile };
}

describe("GET /v1/ws", () => {
  it("rejects a plain GET with 426 upgrade_required", async () => {
    const res = await call(makeApp(), "GET", "/v1/ws");
    expect(res.status).toBe(426);
    expect(await errorCode(res)).toBe("upgrade_required");
  });

  it("refuses a missing, unknown or expired token with HTTP 401 unauthorized before upgrading", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const later = makeApp({ now: () => Date.now() + 91 * 24 * 60 * 60 * 1000 });
    const attempts: [TestApp, string | undefined][] = [[app, undefined], [app, "A".repeat(43)], [later, account.agent.token]];
    for (const [client, token] of attempts) {
      const res = await call(client, "GET", "/v1/ws", { token, headers: { Upgrade: "websocket" } });
      expect(res.status).toBe(401);
      expect(res.webSocket).toBeNull();
      expect(await errorCode(res)).toBe("unauthorized");
    }
  });
});

describe("UserHub presence and routing", () => {
  it("sends a presence snapshot to the newcomer and announces it to the others", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    await a.expectSilence(100); // alone in the hub: nothing to report
    const m = await connect(app, mobile.token);
    expect(hex(await m.nextBinary())).toBe(hex(encodePresence(agent.deviceId, true)));
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
  });

  it("answers the text heartbeat 'ping' with 'pong'", async () => {
    const { app, agent } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    a.send("ping");
    expect(await a.next()).toBe("pong");
  });

  it("routes DATA to the peer with the peer field rewritten to the sender", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    const m = await connect(app, mobile.token);
    await m.nextBinary();
    await a.nextBinary();
    const payload = Uint8Array.from([0x01, 0xde, 0xad, 0xbe, 0xef]);
    m.send(encodeData(agent.deviceId, CH, payload));
    expect(hex(await a.nextBinary())).toBe(hex(encodeData(mobile.deviceId, CH, payload)));
    a.send(encodeData(mobile.deviceId, CH, payload));
    expect(hex(await m.nextBinary())).toBe(hex(encodeData(agent.deviceId, CH, payload)));
  });

  it("replies ERROR peer_offline (with peer and channel) when the target is not connected", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const m = await connect(app, mobile.token);
    m.send(encodeData(agent.deviceId, CH, Uint8Array.of(4)));
    expect(hex(await m.nextBinary())).toBe(hex(encodeError(RelayErrorCode.peerOffline, agent.deviceId, CH)));
  });

  it("never routes frames to another account, even when that device is online", async () => {
    const app = makeApp();
    const alice = await registerAccount(app);
    const aliceMobile = await loginDevice(app, alice, "mobile");
    const bob = await registerAccount(app);
    const bobAgent = await connect(app, bob.agent.token);
    const attacker = await connect(app, aliceMobile.token);
    await attacker.expectSilence(100); // Bob's agent is not in Alice's presence snapshot
    attacker.send(encodeData(bob.agent.deviceId, CH, Uint8Array.of(4, 1, 2, 3)));
    expect(hex(await attacker.nextBinary())).toBe(hex(encodeError(RelayErrorCode.peerOffline, bob.agent.deviceId, CH)));
    await bobAgent.expectSilence();
  });

  it("enforces the 64 KiB frame limit", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    const m = await connect(app, mobile.token);
    await m.nextBinary();
    await a.nextBinary();
    const exact = encodeData(agent.deviceId, CH, new Uint8Array(MAX_FRAME_BYTES - 26));
    expect(exact.length).toBe(65536);
    m.send(exact);
    expect((await a.nextBinary()).length).toBe(65536);
    m.send(encodeData(agent.deviceId, CH, new Uint8Array(MAX_FRAME_BYTES - 25)));
    expect(hex(await m.nextBinary())).toBe(hex(encodeError(RelayErrorCode.frameTooLarge, agent.deviceId, CH)));
    await a.expectSilence();
  });

  it("answers malformed frames with ERROR bad_frame and keeps the connection", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    const m = await connect(app, mobile.token);
    await m.nextBinary();
    await a.nextBinary();
    const badFrame = hex(encodeError(RelayErrorCode.badFrame));
    const wrongVersion = encodeData(agent.deviceId, CH, Uint8Array.of(4));
    wrongVersion[0] = 2;
    for (const bad of [new Uint8Array(10), wrongVersion, encodePresence(agent.deviceId, true)]) {
      m.send(bad);
      expect(hex(await m.nextBinary())).toBe(badFrame);
    }
    m.send("hello");
    expect(hex(await m.nextBinary())).toBe(badFrame);
    m.send(encodeData(agent.deviceId, CH, Uint8Array.of(4)));
    expect((await a.nextBinary()).length).toBe(27);
    await a.expectSilence(50);
  });

  it("replaces an older connection of the same device with 4001 without announcing it offline", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    const m1 = await connect(app, mobile.token);
    await m1.nextBinary();
    await a.nextBinary();

    const m2 = await connect(app, mobile.token);
    expect(await m1.closed).toEqual({ code: 4001, reason: "replaced" });
    expect(hex(await m2.nextBinary())).toBe(hex(encodePresence(agent.deviceId, true)));
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    await a.expectSilence(); // no "offline" for the replaced socket

    a.send(encodeData(mobile.deviceId, CH, Uint8Array.of(4)));
    expect((await m2.nextBinary()).length).toBe(27);
  });

  it("announces offline and records last_seen_at when a device disconnects", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    const m = await connect(app, mobile.token);
    await m.nextBinary();
    await a.nextBinary();
    const before = Date.now();
    m.close();
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, false)));
    const lastSeen = await waitFor(async () =>
      (await env.DB.prepare("SELECT last_seen_at FROM devices WHERE id = ?").bind(mobile.deviceId)
        .first<{ last_seen_at: number | null }>())?.last_seen_at,
    );
    expect(lastSeen).toBeGreaterThanOrEqual(before);
  });

  it("logs frame metadata but never the payload", async () => {
    const lines: string[] = [];
    vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    });
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const m = await connect(app, mobile.token);
    const payload = new TextEncoder().encode("SECRET-PAYLOAD-MARKER".padEnd(MAX_FRAME_BYTES, "!"));
    m.send(encodeData(agent.deviceId, CH, payload));
    await m.nextBinary();
    const output = lines.join("\n");
    expect(output).toContain("ws_frame_too_large");
    expect(output).not.toContain("SECRET-PAYLOAD-MARKER");
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `npx vitest run test/hub.test.ts`
Expected: FAIL — 12 failed; first ones `AssertionError: expected 404 to be 426` and `expected 404 to be 401`, the rest `Error: upgrade failed: 404`.

- [ ] **Step 3: Implement the hub** — `relay/src/hub/user-hub.ts`

```ts
import { DurableObject } from "cloudflare:workers";
import type { DeviceKind } from "../auth/device";
import type { Env } from "../env";
import { logMeta } from "../log";
import {
  CloseCode, encodeError, encodePresence, MAX_FRAME_BYTES, parseDataHeader, RelayErrorCode, withPeer,
} from "../protocol/frames";
import { parseUuid } from "../protocol/uuid";

/** Set by the Worker after token validation; the hub is not reachable from the Internet directly. */
export const DEVICE_ID_HEADER = "X-Shellx-Device-Id";
export const DEVICE_KIND_HEADER = "X-Shellx-Device-Kind";

/** The account's hub: exactly one per user (`idFromName(user_id)`, spec §4). */
export function hubFor(env: Env, userId: string): DurableObjectStub<UserHub> {
  return env.USER_HUB.get(env.USER_HUB.idFromName(userId));
}

/** Persisted with serializeAttachment, so it survives hibernation. */
export interface Attachment {
  device_id: string;
  kind: DeviceKind;
  /** True once the hub itself closed this socket (4001/4002/4003); its close event is then ignored. */
  closing?: boolean;
}

const CLOSE_REASONS: Record<CloseCode, string> = {
  [CloseCode.replaced]: "replaced",
  [CloseCode.revoked]: "revoked",
  [CloseCode.rateLimited]: "rate_limited",
};

/**
 * One instance per account (`idFromName(user_id)`): every device of the account connects here, so
 * frames can only ever be routed between devices of the same account.
 */
export class UserHub extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    // Heartbeat is answered by the runtime without waking the object (spec §6.1).
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
  }

  async fetch(request: Request): Promise<Response> {
    const deviceId = parseUuid(request.headers.get(DEVICE_ID_HEADER));
    const kind = request.headers.get(DEVICE_KIND_HEADER);
    if (
      deviceId === null ||
      (kind !== "agent" && kind !== "mobile") ||
      request.headers.get("Upgrade")?.toLowerCase() !== "websocket"
    ) {
      return new Response("bad hub request", { status: 400 });
    }

    // One connection per device: the newest wins; the old socket gets 4001 and no offline is announced.
    for (const old of this.socketsOf(deviceId)) this.closeSocket(old, CloseCode.replaced);

    const { 0: client, 1: server } = new WebSocketPair();
    this.ctx.acceptWebSocket(server, [deviceId]);
    server.serializeAttachment({ device_id: deviceId, kind } satisfies Attachment);

    for (const other of this.liveDeviceIds()) {
      if (other !== deviceId) server.send(encodePresence(other, true));
    }
    this.broadcast(encodePresence(deviceId, true), deviceId);
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const me = attachmentOf(ws);
    if (me === null || me.closing) return;

    if (typeof message === "string") {
      // Only "ping" is valid text, and the runtime answers it before we get here.
      safeSend(ws, encodeError(RelayErrorCode.badFrame));
      return;
    }
    const frame = new Uint8Array(message);
    const header = parseDataHeader(frame);
    if (frame.length > MAX_FRAME_BYTES) {
      safeSend(ws, encodeError(RelayErrorCode.frameTooLarge, header?.peer, header?.channel));
      logMeta("ws_frame_too_large", { device_id: me.device_id, size: frame.length });
      return;
    }
    if (header === null) {
      safeSend(ws, encodeError(RelayErrorCode.badFrame));
      return;
    }
    const targets = this.socketsOf(header.peer);
    if (targets.length === 0) {
      safeSend(ws, encodeError(RelayErrorCode.peerOffline, header.peer, header.channel));
      return;
    }
    const routed = withPeer(frame, me.device_id);
    for (const target of targets) safeSend(target, routed);
  }

  async webSocketClose(ws: WebSocket): Promise<void> {
    await this.socketGone(ws);
  }

  async webSocketError(ws: WebSocket): Promise<void> {
    await this.socketGone(ws);
  }

  // ---- helpers -------------------------------------------------------------------------------

  private async socketGone(ws: WebSocket): Promise<void> {
    const me = attachmentOf(ws);
    if (me === null || me.closing) return; // the hub closed it on purpose and already handled it
    ws.serializeAttachment({ ...me, closing: true } satisfies Attachment);
    try {
      ws.close(1000, "closed");
    } catch {
      // already closed
    }
    await this.markOffline(me.device_id);
  }

  /** Marks the socket as closed by the hub, then closes it with `code`. */
  private closeSocket(ws: WebSocket, code: CloseCode): void {
    const me = attachmentOf(ws);
    if (me === null || me.closing) return;
    ws.serializeAttachment({ ...me, closing: true } satisfies Attachment);
    try {
      ws.close(code, CLOSE_REASONS[code]);
    } catch {
      // already closed
    }
  }

  /**
   * Announces offline and records last_seen_at, unless the device still has a live socket (it just
   * reconnected). Callers mark the departing socket as `closing` first, so it is never counted.
   */
  private async markOffline(deviceId: string): Promise<void> {
    if (this.socketsOf(deviceId).length > 0) return;
    this.broadcast(encodePresence(deviceId, false), deviceId);
    await this.env.DB.prepare("UPDATE devices SET last_seen_at = ? WHERE id = ?").bind(Date.now(), deviceId).run();
  }

  /** Open, not-being-closed sockets of one device (normally zero or one). */
  private socketsOf(deviceId: string): WebSocket[] {
    return this.ctx.getWebSockets(deviceId).filter(isLive);
  }

  private liveDeviceIds(): string[] {
    const ids = new Set<string>();
    for (const ws of this.ctx.getWebSockets()) {
      if (isLive(ws)) ids.add(attachmentOf(ws)!.device_id);
    }
    return [...ids];
  }

  private broadcast(frame: Uint8Array, exceptDeviceId: string): void {
    for (const ws of this.ctx.getWebSockets()) {
      if (isLive(ws) && attachmentOf(ws)!.device_id !== exceptDeviceId) safeSend(ws, frame);
    }
  }
}

function attachmentOf(ws: WebSocket): Attachment | null {
  return (ws.deserializeAttachment() as Attachment | null) ?? null;
}

function isLive(ws: WebSocket): boolean {
  const a = attachmentOf(ws);
  return a !== null && !a.closing && ws.readyState === WebSocket.OPEN;
}

function safeSend(ws: WebSocket, data: Uint8Array): void {
  try {
    ws.send(data);
  } catch {
    // the peer vanished between the check and the send; its close handler will clean up
  }
}
```

`relay/src/routes/ws.ts`:

```ts
import type { Context } from "hono";
import type { AppEnv } from "../app";
import { authenticate } from "../auth/session";
import { parseBearer } from "../auth/tokens";
import { DEVICE_ID_HEADER, DEVICE_KIND_HEADER, hubFor } from "../hub/user-hub";
import { Errors } from "../http/errors";

/**
 * GET /v1/ws — validates the bearer token, then hands the upgrade to the account's UserHub.
 * A missing/revoked/expired token is refused with plain HTTP 401 `unauthorized` before any
 * upgrade happens (shellx_core maps that to the `revoked` state).
 */
export async function webSocketRoute(c: Context<AppEnv>): Promise<Response> {
  if (c.req.header("Upgrade")?.toLowerCase() !== "websocket") throw Errors.upgradeRequired();
  const auth = await authenticate(c.env.DB, parseBearer(c.req.header("Authorization")), c.get("now")());
  if (auth === null) throw Errors.unauthorized();

  const headers = new Headers(c.req.raw.headers);
  headers.delete("Authorization");
  headers.set(DEVICE_ID_HEADER, auth.deviceId);
  headers.set(DEVICE_KIND_HEADER, auth.kind);
  return hubFor(c.env, auth.userId).fetch(new Request("https://user-hub/connect", { headers }));
}
```

`relay/src/env.ts` (replace the whole file):

```ts
import type { UserHub } from "./hub/user-hub";

export interface Env {
  DB: D1Database;
  USER_HUB: DurableObjectNamespace<UserHub>;
  LOGIN_IP_LIMITER: RateLimit;
  LOGIN_EMAIL_LIMITER: RateLimit;
  REGISTER_IP_LIMITER: RateLimit;
  /** "false" disables every rate limit (local dev / E2E only); any other value keeps them on. */
  RATE_LIMITS_ENABLED: string;
  MIN_AGENT: string;
  MIN_MOBILE: string;
  LATEST_AGENT_VERSION: string;
  MAC_URL: string;
  WIN_URL: string;
}
```

`relay/src/index.ts` (replace the whole file):

```ts
import { createApp } from "./app";
import type { Env } from "./env";

export { UserHub } from "./hub/user-hub";

const app = createApp();

export default {
  fetch: (request, env, ctx) => app.fetch(request, env, ctx),
} satisfies ExportedHandler<Env>;
```

`relay/wrangler.jsonc` (replace the whole file; adds `migrations` and a `durable_objects` block to the top level and to both environments):

```jsonc
{
  "$schema": "node_modules/wrangler/config-schema.json",
  "name": "shellx-relay",
  "main": "src/index.ts",
  // Must not be newer than the workerd bundled with @cloudflare/vitest-pool-workers,
  // otherwise `npm test` fails with "This Worker requires compatibility date ...".
  "compatibility_date": "2026-08-15",
  "observability": { "enabled": true },
  // Inherited by every environment. SQLite-backed class (required for new Durable Objects).
  "migrations": [{ "tag": "v1", "new_sqlite_classes": ["UserHub"] }],

  // ---- Top level = local development only (`npm run dev`, `npm test`). Never deployed. ----
  "workers_dev": false,
  "dev": { "ip": "127.0.0.1", "port": 8787 },
  "durable_objects": { "bindings": [{ "name": "USER_HUB", "class_name": "UserHub" }] },
  "d1_databases": [
    {
      "binding": "DB",
      "database_name": "shellx-local",
      "database_id": "00000000-0000-4000-8000-000000000001",
      "migrations_dir": "migrations"
    }
  ],
  "ratelimits": [
    { "name": "LOGIN_IP_LIMITER", "namespace_id": "9001", "simple": { "limit": 10, "period": 60 } },
    { "name": "LOGIN_EMAIL_LIMITER", "namespace_id": "9002", "simple": { "limit": 5, "period": 60 } },
    { "name": "REGISTER_IP_LIMITER", "namespace_id": "9003", "simple": { "limit": 3, "period": 60 } }
  ],
  "vars": {
    // Local only: the plan-03 E2E suite creates many accounts from 127.0.0.1 (overview §4.3).
    "RATE_LIMITS_ENABLED": "false",
    "MIN_AGENT": "1.0.0",
    "MIN_MOBILE": "1.0.0",
    "LATEST_AGENT_VERSION": "1.0.0",
    "MAC_URL": "https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg",
    "WIN_URL": "https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe"
  },

  "env": {
    "staging": {
      "workers_dev": false,
      "routes": [{ "pattern": "relay-staging.shellx.pro", "custom_domain": true }],
      "durable_objects": { "bindings": [{ "name": "USER_HUB", "class_name": "UserHub" }] },
      // database_id is added by the runbook (relay/README.md) after `wrangler d1 create shellx-staging`.
      "d1_databases": [{ "binding": "DB", "database_name": "shellx-staging", "migrations_dir": "migrations" }],
      "ratelimits": [
        { "name": "LOGIN_IP_LIMITER", "namespace_id": "2001", "simple": { "limit": 10, "period": 60 } },
        { "name": "LOGIN_EMAIL_LIMITER", "namespace_id": "2002", "simple": { "limit": 5, "period": 60 } },
        { "name": "REGISTER_IP_LIMITER", "namespace_id": "2003", "simple": { "limit": 3, "period": 60 } }
      ],
      "vars": {
        "RATE_LIMITS_ENABLED": "true",
        "MIN_AGENT": "1.0.0",
        "MIN_MOBILE": "1.0.0",
        "LATEST_AGENT_VERSION": "1.0.0",
        "MAC_URL": "https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg",
        "WIN_URL": "https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe"
      }
    },
    "production": {
      "workers_dev": false,
      "routes": [{ "pattern": "relay.shellx.pro", "custom_domain": true }],
      "durable_objects": { "bindings": [{ "name": "USER_HUB", "class_name": "UserHub" }] },
      // database_id is added by the runbook (relay/README.md) after `wrangler d1 create shellx-production`.
      "d1_databases": [{ "binding": "DB", "database_name": "shellx-production", "migrations_dir": "migrations" }],
      "ratelimits": [
        { "name": "LOGIN_IP_LIMITER", "namespace_id": "1001", "simple": { "limit": 10, "period": 60 } },
        { "name": "LOGIN_EMAIL_LIMITER", "namespace_id": "1002", "simple": { "limit": 5, "period": 60 } },
        { "name": "REGISTER_IP_LIMITER", "namespace_id": "1003", "simple": { "limit": 3, "period": 60 } }
      ],
      "vars": {
        "RATE_LIMITS_ENABLED": "true",
        "MIN_AGENT": "1.0.0",
        "MIN_MOBILE": "1.0.0",
        "LATEST_AGENT_VERSION": "1.0.0",
        "MAC_URL": "https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg",
        "WIN_URL": "https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe"
      }
    }
  }
}
```

Route it:

In `relay/src/app.ts` replace:

```ts
import { authRoutes } from "./routes/auth";
```

with:

```ts
import { authRoutes } from "./routes/auth";
import { webSocketRoute } from "./routes/ws";
```

In `relay/src/app.ts` replace:

```ts
  app.route("/v1/auth", authRoutes);
```

with:

```ts
  app.route("/v1/auth", authRoutes);
  app.get("/v1/ws", webSocketRoute);
```

- [ ] **Step 4: Run tests**

Run: `npx vitest run && npm run typecheck`
Expected: PASS, `100 passed (100)`; typecheck exits 0.

- [ ] **Step 5: Commit** (from the repository root)

```bash
git add relay/wrangler.jsonc relay/src relay/test
git commit -m "feat(relay): UserHub durable object with presence, routing and /v1/ws"
```

---

### Task 7: 500 frames/s per connection (token bucket) and hibernation behaviour

Why the bucket may live in memory: a Durable Object hibernates only after about 10 s without events. A 500-token bucket refilling at 500/s is full again after 1 s, so a bucket lost to hibernation is indistinguishable from a kept one; persisting it would cost a storage write per frame. Eviction for deploys/restarts drops the sockets anyway. The bucket is keyed by `device_id` (one socket per device) and reset whenever that device connects again.

**Files:**
- Create: `relay/src/hub/token-bucket.ts`
- Modify: `relay/src/hub/user-hub.ts`
- Test: `relay/test/rate-limit.test.ts`

**Interfaces:**
- Consumes: `UserHub` internals (Task 6): `closeSocket`, `markOffline`, `safeSend`; `encodeError`, `RelayErrorCode`, `CloseCode`; `evictDurableObject` from `cloudflare:test`.
- Produces: `class TokenBucket { constructor(capacity: number, refillPerSecond: number, now: number); take(now: number): boolean }`, `FRAMES_PER_SECOND = 500`; hub behaviour: over-limit → ERROR `rate_limited` (nil device, zero channel), close `4003 "rate_limited"`, PRESENCE offline to the others.

- [ ] **Step 1: Write the failing test** — `relay/test/rate-limit.test.ts`

```ts
import { evictDurableObject } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { FRAMES_PER_SECOND, TokenBucket } from "../src/hub/token-bucket";
import { encodeData, encodeError, encodePresence, RelayErrorCode } from "../src/protocol/frames";
import { connect, hex, loginDevice, makeApp, registerAccount } from "./helpers";

const CH = Uint8Array.from([1, 1, 2, 3, 5, 8, 13, 21]);

describe("TokenBucket", () => {
  it("allows a burst of `capacity`, then refills at the configured rate", () => {
    const bucket = new TokenBucket(500, 500, 0);
    for (let i = 0; i < 500; i++) expect(bucket.take(0)).toBe(true);
    expect(bucket.take(0)).toBe(false);
    expect(bucket.take(1)).toBe(false); // 0.5 token
    expect(bucket.take(2)).toBe(true); // 1 token after 2 ms
    expect(bucket.take(2)).toBe(false);
  });

  it("never stores more than `capacity` tokens", () => {
    const bucket = new TokenBucket(500, 500, 0);
    bucket.take(0);
    let allowed = 0;
    while (bucket.take(60_000)) allowed++;
    expect(allowed).toBe(500);
    expect(FRAMES_PER_SECOND).toBe(500);
  });
});

async function hubWithTwoDevices() {
  const app = makeApp();
  const account = await registerAccount(app);
  const mobile = await loginDevice(app, account, "mobile");
  const a = await connect(app, account.agent.token);
  const m = await connect(app, mobile.token);
  await m.nextBinary();
  await a.nextBinary();
  const stub = env.USER_HUB.get(env.USER_HUB.idFromName(account.agent.userId));
  return { app, account, agent: account.agent, mobile, a, m, stub };
}

describe("per-connection frame rate limit", () => {
  it("lets a burst of 400 frames through", async () => {
    const { agent, a, m } = await hubWithTwoDevices();
    for (let i = 0; i < 400; i++) m.send(encodeData(agent.deviceId, CH, Uint8Array.of(4, i & 0xff)));
    for (let i = 0; i < 400; i++) await a.nextBinary();
    await m.expectSilence(100);
  });

  it("sends ERROR rate_limited, then closes with 4003 and announces offline", async () => {
    const { agent, mobile, a, m } = await hubWithTwoDevices();
    for (let i = 0; i < 1000; i++) m.send(encodeData(agent.deviceId, CH, Uint8Array.of(4)));
    expect(hex(await m.nextBinary())).toBe(hex(encodeError(RelayErrorCode.rateLimited)));
    expect(await m.closed).toEqual({ code: 4003, reason: "rate_limited" });

    let delivered = 0;
    for (;;) {
      const frame = await a.nextBinary();
      if (frame[1] === 0x02) {
        expect(hex(frame)).toBe(hex(encodePresence(mobile.deviceId, false)));
        break;
      }
      delivered++;
    }
    expect(delivered).toBeGreaterThanOrEqual(FRAMES_PER_SECOND);
    expect(delivered).toBeLessThan(1000);
  });
});

describe("hibernation", () => {
  it("keeps routing, presence, replacement, heartbeat and rate limiting working after eviction", async () => {
    const { app, agent, mobile, a, m, stub } = await hubWithTwoDevices();
    await evictDurableObject(stub); // sockets are hibernated, in-memory state (token buckets) is dropped

    m.send("ping");
    expect(await m.next()).toBe("pong");
    m.send(encodeData(agent.deviceId, CH, Uint8Array.of(4, 2)));
    expect(hex(await a.nextBinary())).toBe(hex(encodeData(mobile.deviceId, CH, Uint8Array.of(4, 2))));

    const m2 = await connect(app, mobile.token);
    expect((await m.closed).code).toBe(4001);
    expect(hex(await m2.nextBinary())).toBe(hex(encodePresence(agent.deviceId, true)));
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));

    await evictDurableObject(stub);
    for (let i = 0; i < 400; i++) m2.send(encodeData(agent.deviceId, CH, Uint8Array.of(4)));
    for (let i = 0; i < 400; i++) await a.nextBinary();
    for (let i = 0; i < 1000; i++) m2.send(encodeData(agent.deviceId, CH, Uint8Array.of(4)));
    expect((await m2.closed).code).toBe(4003);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `npx vitest run test/rate-limit.test.ts`
Expected: FAIL — `Error: Cannot find module '../src/hub/token-bucket' imported from …/test/rate-limit.test.ts`

- [ ] **Step 3: Implement** — `relay/src/hub/token-bucket.ts`

```ts
/** Classic token bucket: `capacity` burst, refilled continuously at `refillPerSecond`. */
export class TokenBucket {
  private tokens: number;
  private updatedAt: number;

  constructor(
    private readonly capacity: number,
    private readonly refillPerSecond: number,
    now: number,
  ) {
    this.tokens = capacity;
    this.updatedAt = now;
  }

  take(now: number): boolean {
    const elapsed = Math.max(0, now - this.updatedAt);
    this.tokens = Math.min(this.capacity, this.tokens + (elapsed * this.refillPerSecond) / 1000);
    this.updatedAt = now;
    if (this.tokens < 1) return false;
    this.tokens -= 1;
    return true;
  }
}

/** Spec §6.2: at most 500 frames per second per connection. */
export const FRAMES_PER_SECOND = 500;
```

Then six edits in `relay/src/hub/user-hub.ts`:

In `relay/src/hub/user-hub.ts` replace:

```ts
import { parseUuid } from "../protocol/uuid";
```

with:

```ts
import { parseUuid } from "../protocol/uuid";
import { FRAMES_PER_SECOND, TokenBucket } from "./token-bucket";
```

In `relay/src/hub/user-hub.ts` replace:

```ts
export class UserHub extends DurableObject<Env> {
  constructor(
```

with:

```ts
export class UserHub extends DurableObject<Env> {
  /**
   * Per-device frame budget, in memory only. It is lost when the object hibernates, which is
   * harmless: hibernation needs ~10 s without events, after which a 500-token bucket refilling at
   * 500/s is full anyway — exactly what a fresh bucket starts with. Persisting it would cost a
   * storage write per frame.
   */
  private readonly buckets = new Map<string, TokenBucket>();

  constructor(
```

In `relay/src/hub/user-hub.ts` replace:

```ts
    for (const old of this.socketsOf(deviceId)) this.closeSocket(old, CloseCode.replaced);
```

with:

```ts
    for (const old of this.socketsOf(deviceId)) this.closeSocket(old, CloseCode.replaced);
    this.buckets.delete(deviceId); // the new connection starts with a full budget
```

In `relay/src/hub/user-hub.ts` replace:

```ts
    if (me === null || me.closing) return;

    if (typeof message === "string") {
```

with:

```ts
    if (me === null || me.closing) return;

    if (!this.takeToken(me.device_id)) {
      safeSend(ws, encodeError(RelayErrorCode.rateLimited));
      this.closeSocket(ws, CloseCode.rateLimited);
      logMeta("ws_rate_limited", { device_id: me.device_id });
      await this.markOffline(me.device_id);
      return;
    }

    if (typeof message === "string") {
```

In `relay/src/hub/user-hub.ts` replace:

```ts
  private async socketGone(ws: WebSocket): Promise<void> {
```

with:

```ts
  private takeToken(deviceId: string): boolean {
    const now = Date.now();
    let bucket = this.buckets.get(deviceId);
    if (bucket === undefined) {
      bucket = new TokenBucket(FRAMES_PER_SECOND, FRAMES_PER_SECOND, now);
      this.buckets.set(deviceId, bucket);
    }
    return bucket.take(now);
  }

  private async socketGone(ws: WebSocket): Promise<void> {
```

In `relay/src/hub/user-hub.ts` replace:

```ts
    if (this.socketsOf(deviceId).length > 0) return;
```

with:

```ts
    if (this.socketsOf(deviceId).length > 0) return;
    this.buckets.delete(deviceId);
```

- [ ] **Step 4: Run tests**

Run: `npx vitest run test/rate-limit.test.ts test/hub.test.ts && npx vitest run && npm run typecheck`
Expected: PASS, `17 passed (17)` for the two files, then `105 passed (105)`; typecheck exits 0.

- [ ] **Step 5: Commit** (from the repository root)

```bash
git add relay/src/hub relay/test/rate-limit.test.ts
git commit -m "feat(relay): 500 frames/s per-connection limit with 4003 close"
```

---

### Task 8: Hub RPC, `GET /v1/devices`, `POST`/`DELETE /v1/pairings`, `pairing_removed` delivery

**Files:**
- Create: `relay/src/routes/devices.ts`, `relay/src/routes/pairings.ts`
- Modify: `relay/src/hub/user-hub.ts`, `relay/src/app.ts`
- Test: `relay/test/devices-pairings.test.ts`

**Interfaces:**
- Consumes: `requireAuth`, `TOKEN_IDLE_TTL_MS` (Task 5); `hubFor` (Task 6); `pairingRemovedEvent`, `parseUuid` (Task 2); `Errors`, `readJsonObject` (Task 4).
- Produces:
  - `UserHub` RPC (spec §10.4): `online(): string[]`; `disconnect(deviceIds: string[], code: CloseCode): Promise<void>` (closes with `code`, announces offline, writes `last_seen_at`); `notifyPairingRemoved(agentId: string, mobileId: string): void` (EVENT to both if connected; queued in SQLite table `pending_events` when the agent is offline, delivered after the PRESENCE snapshot on its next connect).
  - `deviceRoutes` at `/v1/devices`: `GET /` → `200 [{id, kind, name, platform, online, last_seen_at, paired_with_me}]`.
  - `pairingRoutes` at `/v1/pairings`: `POST /` `{mobile_id}` → `201`; `DELETE /:agent_id/:mobile_id` → `204`.

- [ ] **Step 1: Write the failing test** — `relay/test/devices-pairings.test.ts`

```ts
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { hubFor } from "../src/hub/user-hub";
import { encodePresence, pairingRemovedEvent } from "../src/protocol/frames";
import { call, connect, errorCode, hex, loginDevice, makeApp, registerAccount, type TestApp } from "./helpers";

interface DeviceJson {
  id: string;
  kind: string;
  name: string;
  platform: string;
  online: boolean;
  last_seen_at: number | null;
  paired_with_me: boolean;
}

async function listDevices(app: TestApp, token: string): Promise<DeviceJson[]> {
  const res = await call(app, "GET", "/v1/devices", { token });
  expect(res.status).toBe(200);
  return res.json<DeviceJson[]>();
}

async function pair(app: TestApp, agentToken: string, mobileId: string): Promise<Response> {
  return call(app, "POST", "/v1/pairings", { token: agentToken, body: { mobile_id: mobileId } });
}

describe("GET /v1/devices", () => {
  it("requires a valid token", async () => {
    const res = await call(makeApp(), "GET", "/v1/devices");
    expect(res.status).toBe(401);
    expect(await errorCode(res)).toBe("unauthorized");
  });

  it("lists signed-in devices of the caller's account with presence, and no public keys", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const other = await registerAccount(app); // another account: must never appear
    const socket = await connect(app, account.agent.token);

    const devices = await listDevices(app, mobile.token);
    expect(devices).toEqual([
      { id: account.agent.deviceId, kind: "agent", name: "MacBook-Pro", platform: "macos", online: true, last_seen_at: null, paired_with_me: false },
      { id: mobile.deviceId, kind: "mobile", name: "iPhone 16", platform: "ios", online: false, last_seen_at: null, paired_with_me: false },
    ]);
    expect(JSON.stringify(devices)).not.toContain(account.agent.publicKey);
    expect(devices.map((d) => d.id)).not.toContain(other.agent.deviceId);
    socket.close();
  });

  it("hides devices whose tokens are gone (signed out)", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await env.DB.prepare("DELETE FROM tokens WHERE device_id = ?").bind(mobile.deviceId).run();
    expect((await listDevices(app, account.agent.token)).map((d) => d.id)).toEqual([account.agent.deviceId]);
  });
});

describe("POST /v1/pairings", () => {
  it("records a pairing visible as paired_with_me from both sides; idempotent", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    expect((await pair(app, account.agent.token, mobile.deviceId)).status).toBe(201);
    expect((await pair(app, account.agent.token, mobile.deviceId.toUpperCase())).status).toBe(201);

    const fromMobile = await listDevices(app, mobile.token);
    expect(fromMobile.find((d) => d.id === account.agent.deviceId)?.paired_with_me).toBe(true);
    expect(fromMobile.find((d) => d.id === mobile.deviceId)?.paired_with_me).toBe(false);
    const fromAgent = await listDevices(app, account.agent.token);
    expect(fromAgent.find((d) => d.id === mobile.deviceId)?.paired_with_me).toBe(true);
    const count = await env.DB.prepare("SELECT COUNT(*) AS n FROM pairings WHERE agent_id = ?")
      .bind(account.agent.deviceId).first<{ n: number }>();
    expect(count?.n).toBe(1);
  });

  it("is agent-only", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const res = await pair(app, mobile.token, mobile.deviceId);
    expect(res.status).toBe(403);
    expect(await errorCode(res)).toBe("agent_only");
  });

  it("returns 404 device_not_found for unknown ids, agents and other accounts' mobiles", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const otherAgent = await loginDevice(app, account, "agent");
    const stranger = await registerAccount(app);
    const strangerMobile = await loginDevice(app, stranger, "mobile");
    for (const id of [crypto.randomUUID(), "not-a-uuid", otherAgent.deviceId, strangerMobile.deviceId]) {
      const res = await pair(app, account.agent.token, id);
      expect(res.status).toBe(404);
      expect(await errorCode(res)).toBe("device_not_found");
    }
  });
});

describe("DELETE /v1/pairings/:agent_id/:mobile_id", () => {
  it("lets the agent remove a pairing and notifies the connected mobile", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await pair(app, account.agent.token, mobile.deviceId);
    const m = await connect(app, mobile.token);

    const res = await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, {
      token: account.agent.token,
    });
    expect(res.status).toBe(204);
    expect(hex(await m.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId)));
    const fromMobile = await listDevices(app, mobile.token);
    expect(fromMobile.find((d) => d.id === account.agent.deviceId)?.paired_with_me).toBe(false);
  });

  it("lets the mobile remove a pairing and notifies the connected agent", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await pair(app, account.agent.token, mobile.deviceId);
    const a = await connect(app, account.agent.token);

    const res = await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, {
      token: mobile.token,
    });
    expect(res.status).toBe(204);
    expect(hex(await a.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId)));
  });

  it("queues the event for an offline agent and delivers it after the presence snapshot", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await pair(app, account.agent.token, mobile.deviceId);
    const m = await connect(app, mobile.token);
    await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token });
    expect(hex(await m.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId)));

    const a = await connect(app, account.agent.token);
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    expect(hex(await a.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId)));
    a.close();
    await new Promise((resolve) => setTimeout(resolve, 50));
    const again = await connect(app, account.agent.token);
    expect(hex(await again.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    await again.expectSilence(); // delivered exactly once
  });

  it("is idempotent and forbidden to devices that are not a party", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const bystander = await loginDevice(app, account, "mobile");
    await pair(app, account.agent.token, mobile.deviceId);
    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`;
    const forbidden = await call(app, "DELETE", path, { token: bystander.token });
    expect(forbidden.status).toBe(403);
    expect(await errorCode(forbidden)).toBe("forbidden");
    expect((await call(app, "DELETE", path, { token: mobile.token })).status).toBe(204);
    expect((await call(app, "DELETE", path, { token: mobile.token })).status).toBe(204);
  });
});

describe("UserHub RPC", () => {
  it("online() lists connected devices and disconnect() closes them with the given code", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const a = await connect(app, account.agent.token);
    const m = await connect(app, mobile.token);
    await m.nextBinary();
    await a.nextBinary();
    const hub = hubFor(env, account.agent.userId);
    expect((await hub.online()).sort()).toEqual([account.agent.deviceId, mobile.deviceId].sort());

    await hub.disconnect([mobile.deviceId], 4002);
    expect(await m.closed).toEqual({ code: 4002, reason: "revoked" });
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, false)));
    expect(await hub.online()).toEqual([account.agent.deviceId]);
    await hub.disconnect([mobile.deviceId], 4002); // already gone: no-op
    await a.expectSilence();
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `npx vitest run test/devices-pairings.test.ts`
Expected: FAIL — 11 failed (HTTP 404 for the new routes; `TypeError: The RPC receiver does not implement "online"` for the RPC test).

- [ ] **Step 3: Implement the RPC methods and the durable event queue**

In `relay/src/hub/user-hub.ts` replace:

```ts
  CloseCode, encodeError, encodePresence, MAX_FRAME_BYTES, parseDataHeader, RelayErrorCode, withPeer,
} from "../protocol/frames";
```

with:

```ts
  CloseCode, encodeError, encodePresence, MAX_FRAME_BYTES, pairingRemovedEvent, parseDataHeader, RelayErrorCode,
  withPeer,
} from "../protocol/frames";
```

In `relay/src/hub/user-hub.ts` replace:

```ts
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
  }
```

with:

```ts
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
    // Durable (SQLite-backed) queue of EVENT frames for an agent that was offline when they happened.
    ctx.storage.sql.exec(
      "CREATE TABLE IF NOT EXISTS pending_events (id INTEGER PRIMARY KEY AUTOINCREMENT, device_id TEXT NOT NULL, frame BLOB NOT NULL)",
    );
  }
```

In `relay/src/hub/user-hub.ts` replace:

```ts
    this.broadcast(encodePresence(deviceId, true), deviceId);
    return new Response(null, { status: 101, webSocket: client });
  }
```

with:

```ts
    this.broadcast(encodePresence(deviceId, true), deviceId);
    this.deliverPending(server, deviceId);
    return new Response(null, { status: 101, webSocket: client });
  }

  // ---- RPC for the Worker (spec §10.4) -------------------------------------------------------

  /** Device ids that currently have a live connection. */
  online(): string[] {
    return this.liveDeviceIds();
  }

  /** Closes every connection of `deviceIds` with `code` (4002 after a password change) and announces offline. */
  async disconnect(deviceIds: string[], code: CloseCode): Promise<void> {
    for (const deviceId of new Set(deviceIds)) {
      const sockets = this.socketsOf(deviceId);
      if (sockets.length === 0) continue;
      for (const ws of sockets) this.closeSocket(ws, code);
      await this.markOffline(deviceId);
    }
  }

  /**
   * Sends EVENT pairing_removed to both devices if connected (clients handle it idempotently).
   * If the agent is offline the event is queued durably and delivered on its next connection,
   * because the agent is the source of truth for trust (spec §5.4–5.5).
   */
  notifyPairingRemoved(agentId: string, mobileId: string): void {
    const frame = pairingRemovedEvent(agentId, mobileId);
    const agentSockets = this.socketsOf(agentId);
    if (agentSockets.length === 0) {
      this.ctx.storage.sql.exec("INSERT INTO pending_events (device_id, frame) VALUES (?, ?)", agentId, frame.buffer);
    }
    for (const ws of agentSockets) safeSend(ws, frame);
    if (mobileId !== agentId) for (const ws of this.socketsOf(mobileId)) safeSend(ws, frame);
  }
```

In `relay/src/hub/user-hub.ts` replace:

```ts
  // ---- helpers -------------------------------------------------------------------------------

```

with:

```ts
  // ---- helpers -------------------------------------------------------------------------------

  private deliverPending(ws: WebSocket, deviceId: string): void {
    const rows = this.ctx.storage.sql
      .exec<{ frame: ArrayBuffer }>("SELECT frame FROM pending_events WHERE device_id = ? ORDER BY id", deviceId)
      .toArray();
    if (rows.length === 0) return;
    for (const row of rows) ws.send(new Uint8Array(row.frame));
    this.ctx.storage.sql.exec("DELETE FROM pending_events WHERE device_id = ?", deviceId);
  }

```

`relay/src/routes/devices.ts`:

```ts
import { Hono } from "hono";
import type { AppEnv } from "../app";
import type { DeviceKind, DevicePlatform } from "../auth/device";
import { requireAuth } from "../auth/session";
import { TOKEN_IDLE_TTL_MS } from "../auth/tokens";
import { hubFor } from "../hub/user-hub";

interface DeviceRow {
  id: string;
  kind: DeviceKind;
  name: string;
  platform: DevicePlatform;
  last_seen_at: number | null;
  paired_with_me: number;
}

export const deviceRoutes = new Hono<AppEnv>();

/**
 * GET /v1/devices — devices of the caller's account that are signed in (hold a non-expired token),
 * including the caller. Public keys are never returned.
 */
deviceRoutes.get("/", requireAuth, async (c) => {
  const auth = c.get("auth");
  const { results } = await c.env.DB.prepare(
    `SELECT d.id, d.kind, d.name, d.platform, d.last_seen_at,
            EXISTS (SELECT 1 FROM pairings p
                     WHERE (p.agent_id = d.id AND p.mobile_id = ?)
                        OR (p.mobile_id = d.id AND p.agent_id = ?)) AS paired_with_me
       FROM devices d
      WHERE d.user_id = ?
        AND EXISTS (SELECT 1 FROM tokens t WHERE t.device_id = d.id AND t.last_used_at >= ?)
      ORDER BY d.created_at, d.id`,
  )
    .bind(auth.deviceId, auth.deviceId, auth.userId, c.get("now")() - TOKEN_IDLE_TTL_MS)
    .all<DeviceRow>();
  const online = new Set(await hubFor(c.env, auth.userId).online());
  return c.json(
    results.map((d) => ({
      id: d.id,
      kind: d.kind,
      name: d.name,
      platform: d.platform,
      online: online.has(d.id),
      last_seen_at: d.last_seen_at,
      paired_with_me: d.paired_with_me === 1,
    })),
  );
});
```

`relay/src/routes/pairings.ts`:

```ts
import { Hono } from "hono";
import type { AppEnv } from "../app";
import { requireAuth } from "../auth/session";
import { hubFor } from "../hub/user-hub";
import { Errors, readJsonObject } from "../http/errors";
import { parseUuid } from "../protocol/uuid";

export const pairingRoutes = new Hono<AppEnv>();

/** POST /v1/pairings {mobile_id} — agent only; the record is informational (trust lives on the agent). */
pairingRoutes.post("/", requireAuth, async (c) => {
  const auth = c.get("auth");
  if (auth.kind !== "agent") throw Errors.agentOnly();
  const body = await readJsonObject(c.req.raw);
  const mobileId = parseUuid(body.mobile_id);
  if (mobileId === null) throw Errors.deviceNotFound();
  const db = c.env.DB;
  const mobile = await db
    .prepare("SELECT 1 FROM devices WHERE id = ? AND user_id = ? AND kind = 'mobile'")
    .bind(mobileId, auth.userId)
    .first();
  if (mobile === null) throw Errors.deviceNotFound();
  await db
    .prepare(
      `INSERT INTO pairings (agent_id, mobile_id, created_at) VALUES (?, ?, ?)
       ON CONFLICT (agent_id, mobile_id) DO UPDATE SET created_at = excluded.created_at`,
    )
    .bind(auth.deviceId, mobileId, c.get("now")())
    .run();
  return c.body(null, 201);
});

/** DELETE /v1/pairings/:agent_id/:mobile_id — either party; idempotent; notifies the hub. */
pairingRoutes.delete("/:agent_id/:mobile_id", requireAuth, async (c) => {
  const auth = c.get("auth");
  const agentId = parseUuid(c.req.param("agent_id"));
  const mobileId = parseUuid(c.req.param("mobile_id"));
  if (agentId === null || mobileId === null || (auth.deviceId !== agentId && auth.deviceId !== mobileId)) {
    throw Errors.forbidden();
  }
  const result = await c.env.DB.prepare("DELETE FROM pairings WHERE agent_id = ? AND mobile_id = ?")
    .bind(agentId, mobileId)
    .run();
  if (result.meta.changes > 0) await hubFor(c.env, auth.userId).notifyPairingRemoved(agentId, mobileId);
  return c.body(null, 204);
});
```

Route them:

In `relay/src/app.ts` replace:

```ts
import { authRoutes } from "./routes/auth";
```

with:

```ts
import { authRoutes } from "./routes/auth";
import { deviceRoutes } from "./routes/devices";
import { pairingRoutes } from "./routes/pairings";
```

In `relay/src/app.ts` replace:

```ts
  app.get("/v1/ws", webSocketRoute);
```

with:

```ts
  app.route("/v1/devices", deviceRoutes);
  app.route("/v1/pairings", pairingRoutes);
  app.get("/v1/ws", webSocketRoute);
```

- [ ] **Step 4: Run tests**

Run: `npx vitest run && npm run typecheck`
Expected: PASS, `116 passed (116)`; typecheck exits 0.

- [ ] **Step 5: Commit** (from the repository root)

```bash
git add relay/src relay/test/devices-pairings.test.ts
git commit -m "feat(relay): devices list, pairings API and pairing_removed events"
```

---

### Task 9: Logout, password change (revokes others with 4002), account deletion

**Files:**
- Create: `relay/src/routes/account.ts`
- Modify: `relay/src/routes/auth.ts` (imports + append), `relay/src/app.ts`
- Test: `relay/test/account.test.ts`

**Interfaces:**
- Consumes: `requireAuth`, `parseBearer`, `hashToken` (Task 5); `hubFor`, `UserHub.disconnect`, `UserHub.notifyPairingRemoved` (Tasks 6, 8); `hashPassword`, `verifyPassword` (Task 1); `isAcceptablePassword` (Task 3); `CloseCode` (Task 2).
- Produces:
  - `POST /v1/auth/logout` → `204`; deletes the calling token; for an agent also deletes its pairings and sends `pairing_removed` for each.
  - `POST /v1/auth/password {new_password}` → `204`; `403 agent_only`; `400 weak_password`; revokes every other device's tokens, closes their sockets with 4002, keeps pairings.
  - `accountRoutes` at `/v1/account`: `DELETE /` `{password}` → `204`; `401 invalid_credentials`; `429 rate_limited`; deletes the user (cascade devices/tokens/pairings) and closes every socket with 4002.

- [ ] **Step 1: Write the failing test** — `relay/test/account.test.ts` (the DELETE requests carry a JSON body; `call` sends it with `Content-Type: application/json`)

```ts
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { encodePresence, pairingRemovedEvent } from "../src/protocol/frames";
import {
  call, connect, CountingLimiter, deviceBody, errorCode, hex, loginDevice, makeApp, registerAccount, unlimited,
} from "./helpers";

const NEW_PASSWORD = "brand new password";

describe("POST /v1/auth/password", () => {
  it("is agent-only and validates the new password", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const byMobile = await call(app, "POST", "/v1/auth/password", { token: mobile.token, body: { new_password: NEW_PASSWORD } });
    expect(byMobile.status).toBe(403);
    expect(await errorCode(byMobile)).toBe("agent_only");
    const weak = await call(app, "POST", "/v1/auth/password", { token: account.agent.token, body: { new_password: "short" } });
    expect(weak.status).toBe(400);
    expect(await errorCode(weak)).toBe("weak_password");
    expect((await call(app, "POST", "/v1/auth/password", { body: { new_password: NEW_PASSWORD } })).status).toBe(401);
  });

  it("changes the password, revokes every other device (4002) and keeps pairings", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const secondAgent = await loginDevice(app, account, "agent");
    expect((await call(app, "POST", "/v1/pairings", { token: account.agent.token, body: { mobile_id: mobile.deviceId } })).status).toBe(201);

    const a = await connect(app, account.agent.token);
    const m = await connect(app, mobile.token);
    const a2 = await connect(app, secondAgent.token);
    const before = Date.now();

    const res = await call(app, "POST", "/v1/auth/password", { token: account.agent.token, body: { new_password: NEW_PASSWORD } });
    expect(res.status).toBe(204);
    expect((await m.closed).code).toBe(4002);
    expect((await a2.closed).code).toBe(4002);

    // The caller keeps its token and its socket; the others' tokens are gone.
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(200);
    expect((await call(app, "GET", "/v1/devices", { token: mobile.token })).status).toBe(401);
    expect((await call(app, "GET", "/v1/devices", { token: secondAgent.token })).status).toBe(401);
    const offline = new Set<string>();
    while (offline.size < 2) {
      const frame = await a.nextBinary();
      if (frame[1] === 0x02 && frame[18] === 0) offline.add(hex(frame));
    }
    expect(offline).toEqual(new Set([hex(encodePresence(mobile.deviceId, false)), hex(encodePresence(secondAgent.deviceId, false))]));

    // Old password is dead, new one works; pairing survived.
    const oldLogin = await call(app, "POST", "/v1/auth/login", { body: { email: account.email, password: account.password, device: deviceBody("mobile") } });
    expect(oldLogin.status).toBe(401);
    const newLogin = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: NEW_PASSWORD, device: deviceBody("mobile", { public_key: mobile.publicKey }) },
    });
    expect(newLogin.status).toBe(200);
    const pairing = await env.DB.prepare("SELECT COUNT(*) AS n FROM pairings WHERE agent_id = ? AND mobile_id = ?")
      .bind(account.agent.deviceId, mobile.deviceId).first<{ n: number }>();
    expect(pairing?.n).toBe(1);
    const changed = await env.DB.prepare("SELECT password_changed_at FROM users WHERE id = ?")
      .bind(account.agent.userId).first<{ password_changed_at: number }>();
    expect(changed?.password_changed_at).toBeGreaterThanOrEqual(before);
  });
});

describe("POST /v1/auth/logout", () => {
  it("mobile: deletes only its token; pairings stay", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await call(app, "POST", "/v1/pairings", { token: account.agent.token, body: { mobile_id: mobile.deviceId } });
    expect((await call(app, "POST", "/v1/auth/logout", { token: mobile.token })).status).toBe(204);
    expect((await call(app, "GET", "/v1/devices", { token: mobile.token })).status).toBe(401);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(200);
    const pairing = await env.DB.prepare("SELECT COUNT(*) AS n FROM pairings WHERE mobile_id = ?")
      .bind(mobile.deviceId).first<{ n: number }>();
    expect(pairing?.n).toBe(1);
  });

  it("agent: deletes its token and all its pairings, and tells connected mobiles", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await call(app, "POST", "/v1/pairings", { token: account.agent.token, body: { mobile_id: mobile.deviceId } });
    const m = await connect(app, mobile.token);

    expect((await call(app, "POST", "/v1/auth/logout", { token: account.agent.token })).status).toBe(204);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(401);
    const pairing = await env.DB.prepare("SELECT COUNT(*) AS n FROM pairings WHERE agent_id = ?")
      .bind(account.agent.deviceId).first<{ n: number }>();
    expect(pairing?.n).toBe(0);
    expect(hex(await m.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId)));
  });

  it("requires a token", async () => {
    const res = await call(makeApp(), "POST", "/v1/auth/logout");
    expect(res.status).toBe(401);
  });
});

describe("DELETE /v1/account", () => {
  const countRows = async (sql: string, id: string) =>
    (await env.DB.prepare(sql).bind(id).first<{ n: number }>())?.n;

  it("refuses a wrong password with 401 invalid_credentials and deletes nothing", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const res = await call(app, "DELETE", "/v1/account", { token: account.agent.token, body: { password: "not my password" } });
    expect(res.status).toBe(401);
    expect(await errorCode(res)).toBe("invalid_credentials");
    const missing = await call(app, "DELETE", "/v1/account", { token: account.agent.token, body: {} });
    expect(missing.status).toBe(401);
    expect(await countRows("SELECT COUNT(*) AS n FROM users WHERE id = ?", account.agent.userId)).toBe(1);
  });

  it("requires a token and a JSON body", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    expect((await call(app, "DELETE", "/v1/account", { body: { password: account.password } })).status).toBe(401);
    const notJson = await call(app, "DELETE", "/v1/account", { token: account.agent.token, body: "{oops" });
    expect(notJson.status).toBe(400);
    expect(await errorCode(notJson)).toBe("bad_request");
  });

  it("deletes user, devices, tokens and pairings, and closes every socket with 4002", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await call(app, "POST", "/v1/pairings", { token: account.agent.token, body: { mobile_id: mobile.deviceId } });
    const a = await connect(app, account.agent.token);
    const m = await connect(app, mobile.token);

    const res = await call(app, "DELETE", "/v1/account", { token: mobile.token, body: { password: account.password } });
    expect(res.status).toBe(204);
    expect((await a.closed).code).toBe(4002);
    expect((await m.closed).code).toBe(4002);

    expect(await countRows("SELECT COUNT(*) AS n FROM users WHERE id = ?", account.agent.userId)).toBe(0);
    expect(await countRows("SELECT COUNT(*) AS n FROM devices WHERE user_id = ?", account.agent.userId)).toBe(0);
    expect(await countRows("SELECT COUNT(*) AS n FROM tokens WHERE device_id = ?", mobile.deviceId)).toBe(0);
    expect(await countRows("SELECT COUNT(*) AS n FROM tokens WHERE device_id = ?", account.agent.deviceId)).toBe(0);
    expect(await countRows("SELECT COUNT(*) AS n FROM pairings WHERE agent_id = ?", account.agent.deviceId)).toBe(0);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(401);

    // The e-mail address is free again.
    const again = await call(app, "POST", "/v1/auth/register", {
      body: { email: account.email, password: "a fresh password", device: deviceBody("agent") },
    });
    expect(again.status).toBe(201);
  });

  it("rate limits password attempts per account email", async () => {
    const loginEmail = new CountingLimiter(5);
    const app = makeApp({ limiters: () => ({ ...unlimited, loginEmail }) });
    const account = await registerAccount(app);
    for (let i = 0; i < 5; i++) {
      const res = await call(app, "DELETE", "/v1/account", { token: account.agent.token, body: { password: "wrong password" } });
      expect(res.status).toBe(401);
    }
    const blocked = await call(app, "DELETE", "/v1/account", { token: account.agent.token, body: { password: account.password } });
    expect(blocked.status).toBe(429);
    expect(loginEmail.calls).toEqual(Array(6).fill(account.email));
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `npx vitest run test/account.test.ts`
Expected: FAIL — 9 failed, e.g. `AssertionError: expected 404 to be 403 // Object.is equality`.

- [ ] **Step 3: Implement logout and password change**

In `relay/src/routes/auth.ts` replace:

```ts
import { insertTokenStatement } from "../auth/session";
import { generateToken, hashToken } from "../auth/tokens";
```

with:

```ts
import { insertTokenStatement, requireAuth } from "../auth/session";
import { generateToken, hashToken, parseBearer } from "../auth/tokens";
import { hubFor } from "../hub/user-hub";
```

In `relay/src/routes/auth.ts` replace:

```ts
import { logMeta } from "../log";
```

with:

```ts
import { logMeta } from "../log";
import { CloseCode } from "../protocol/frames";
```

Append to the end of `relay/src/routes/auth.ts` (leave one blank line before it):

```ts
/** POST /v1/auth/logout — deletes this token; for an agent also every pairing it owns (spec §5.2). */
authRoutes.post("/logout", requireAuth, async (c) => {
  const auth = c.get("auth");
  const db = c.env.DB;
  const tokenHash = await hashToken(parseBearer(c.req.header("Authorization"))!);
  const statements = [db.prepare("DELETE FROM tokens WHERE token_hash = ?").bind(tokenHash)];
  let removedMobiles: string[] = [];
  if (auth.kind === "agent") {
    const { results } = await db
      .prepare("SELECT mobile_id FROM pairings WHERE agent_id = ?")
      .bind(auth.deviceId)
      .all<{ mobile_id: string }>();
    removedMobiles = results.map((r) => r.mobile_id);
    statements.push(db.prepare("DELETE FROM pairings WHERE agent_id = ?").bind(auth.deviceId));
  }
  await db.batch(statements);
  if (removedMobiles.length > 0) {
    const hub = hubFor(c.env, auth.userId);
    for (const mobileId of removedMobiles) await hub.notifyPairingRemoved(auth.deviceId, mobileId);
  }
  logMeta("logout", { device_id: auth.deviceId });
  return c.body(null, 204);
});

/**
 * POST /v1/auth/password {new_password} — agent token only, no old password (spec §5.2).
 * Revokes every other device's tokens and closes their sockets with 4002. Pairings are kept.
 */
authRoutes.post("/password", requireAuth, async (c) => {
  const auth = c.get("auth");
  if (auth.kind !== "agent") throw Errors.agentOnly();
  const body = await readJsonObject(c.req.raw);
  if (!isAcceptablePassword(body.new_password)) throw Errors.weakPassword();

  const db = c.env.DB;
  const now = c.get("now")();
  const passwordHash = await hashPassword(body.new_password);
  const { results } = await db
    .prepare("SELECT id FROM devices WHERE user_id = ? AND id != ?")
    .bind(auth.userId, auth.deviceId)
    .all<{ id: string }>();
  await db.batch([
    db.prepare("UPDATE users SET password_hash = ?, password_changed_at = ? WHERE id = ?").bind(passwordHash, now, auth.userId),
    db
      .prepare("DELETE FROM tokens WHERE device_id IN (SELECT id FROM devices WHERE user_id = ? AND id != ?)")
      .bind(auth.userId, auth.deviceId),
  ]);
  if (results.length > 0) {
    await hubFor(c.env, auth.userId).disconnect(results.map((r) => r.id), CloseCode.revoked);
  }
  logMeta("password_changed", { device_id: auth.deviceId });
  return c.body(null, 204);
});
```

- [ ] **Step 4: Implement account deletion** — `relay/src/routes/account.ts`

```ts
import { Hono } from "hono";
import type { AppEnv } from "../app";
import { verifyPassword } from "../auth/password";
import { requireAuth } from "../auth/session";
import { hubFor } from "../hub/user-hub";
import { Errors, readJsonObject } from "../http/errors";
import { logMeta } from "../log";
import { CloseCode } from "../protocol/frames";

export const accountRoutes = new Hono<AppEnv>();

/**
 * DELETE /v1/account {password} — any signed-in device (spec §5.2, App Store 5.1.1(v)).
 * Deletes the user; devices, tokens and pairings go with it (ON DELETE CASCADE), then every
 * device's socket is closed with 4002. Password attempts share the 5/email/60 s login budget.
 */
accountRoutes.delete("/", requireAuth, async (c) => {
  const auth = c.get("auth");
  const body = await readJsonObject(c.req.raw);
  const db = c.env.DB;
  const user = await db
    .prepare("SELECT email, password_hash FROM users WHERE id = ?")
    .bind(auth.userId)
    .first<{ email: string; password_hash: string }>();
  if (user === null) throw Errors.unauthorized();
  if (!(await c.get("limiters").loginEmail.limit(user.email))) throw Errors.rateLimited();
  const password = typeof body.password === "string" ? body.password : "";
  if (!(await verifyPassword(password, user.password_hash))) {
    logMeta("account_delete_denied", { device_id: auth.deviceId });
    throw Errors.invalidCredentials();
  }

  const { results } = await db.prepare("SELECT id FROM devices WHERE user_id = ?").bind(auth.userId).all<{ id: string }>();
  await db.prepare("DELETE FROM users WHERE id = ?").bind(auth.userId).run();
  await hubFor(c.env, auth.userId).disconnect(results.map((r) => r.id), CloseCode.revoked);
  logMeta("account_deleted", { device_id: auth.deviceId });
  return c.body(null, 204);
});
```

Route it:

In `relay/src/app.ts` replace:

```ts
import { authRoutes } from "./routes/auth";
```

with:

```ts
import { accountRoutes } from "./routes/account";
import { authRoutes } from "./routes/auth";
```

In `relay/src/app.ts` replace:

```ts
  app.route("/v1/auth", authRoutes);
```

with:

```ts
  app.route("/v1/auth", authRoutes);
  app.route("/v1/account", accountRoutes);
```

- [ ] **Step 5: Run tests**

Run: `npx vitest run && npm run typecheck`
Expected: PASS, `125 passed (125)`; typecheck exits 0.

- [ ] **Step 6: Commit** (from the repository root)

```bash
git add relay/src relay/test/account.test.ts
git commit -m "feat(relay): logout, password change with 4002 revocation, account deletion"
```

---

### Task 10: Emergency `reset-password` admin script

**Files:**
- Create: `relay/scripts/reset-sql.ts`, `relay/scripts/reset-password.ts`
- Modify: `relay/package.json` (scripts)
- Test: `relay/test/reset-password.test.ts`

**Interfaces:**
- Consumes: `createArgon2` (Task 1), `normalizeEmail`, `isValidEmail` (Task 3), `isAcceptablePassword` (Task 3), `base64UrlEncode` (Task 5).
- Produces: `sqlString(value: string): string`; `buildResetSql(email: string, phc: string, now: number, revokeTokens: boolean): string` (first statement `SELECT COUNT(*) AS n …` reports whether the account exists); `npm run reset-password -- --env <local|staging|production> --email <address> [--password <new>] [--revoke-tokens]`, which runs `wrangler d1 execute DB … --json --command <sql>` through `process.execPath` (no shell, works on Windows).

- [ ] **Step 1: Write the failing test** — `relay/test/reset-password.test.ts`

```ts
import argon2Module from "@phi-ag/argon2/argon2.wasm";
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { buildResetSql, sqlString } from "../scripts/reset-sql";
import { createArgon2 } from "../src/auth/argon2";
import { call, deviceBody, loginDevice, makeApp, registerAccount } from "./helpers";

async function runSql(sql: string): Promise<D1Result[]> {
  return env.DB.batch(sql.split("\n").map((statement) => env.DB.prepare(statement)));
}

describe("reset-password SQL", () => {
  it("escapes single quotes", () => {
    expect(sqlString("o'brien@example.com")).toBe("'o''brien@example.com'");
  });

  it("sets a new password, reports existence, and optionally revokes tokens", async () => {
    const app = makeApp();
    const account = await registerAccount(app, `o'brien-${crypto.randomUUID()}@example.com`);
    const mobile = await loginDevice(app, account, "mobile");
    const argon2 = await createArgon2(argon2Module);
    const sql = buildResetSql(account.email, argon2.hash("reset by support"), 1_900_000_000_000, true);

    const results = await runSql(sql);
    expect(results[0]?.results).toEqual([{ n: 1 }]);

    const login = (password: string) =>
      call(app, "POST", "/v1/auth/login", { body: { email: account.email, password, device: deviceBody("mobile") } });
    expect((await login(account.password)).status).toBe(401);
    expect((await login("reset by support")).status).toBe(200);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(401);
    expect((await call(app, "GET", "/v1/devices", { token: mobile.token })).status).toBe(401);
  });

  it("reports n = 0 for an unknown account and changes nothing", async () => {
    const results = await runSql(buildResetSql("nobody@example.com", "$argon2id$x", 1, false));
    expect(results[0]?.results).toEqual([{ n: 0 }]);
    expect(results.length).toBe(2);
  });

  it("rejects a non-integer timestamp", () => {
    expect(() => buildResetSql("a@b.co", "x", 1.5, false)).toThrow(TypeError);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `npx vitest run test/reset-password.test.ts`
Expected: FAIL — `Error: Cannot find module '../scripts/reset-sql' imported from …/test/reset-password.test.ts`

- [ ] **Step 3: Implement** — `relay/scripts/reset-sql.ts`

```ts
/** SQL string literal with single quotes doubled (e-mail local parts may contain `'`). */
export function sqlString(value: string): string {
  return `'${value.replaceAll("'", "''")}'`;
}

/**
 * Statements run by scripts/reset-password.ts through `wrangler d1 execute`.
 * The first statement reports whether the account exists (`n` = 0 or 1).
 */
export function buildResetSql(email: string, phc: string, now: number, revokeTokens: boolean): string {
  if (!Number.isSafeInteger(now)) throw new TypeError("now must be an integer (unix ms)");
  const e = sqlString(email);
  const statements = [
    `SELECT COUNT(*) AS n FROM users WHERE email = ${e};`,
    `UPDATE users SET password_hash = ${sqlString(phc)}, password_changed_at = ${now} WHERE email = ${e};`,
  ];
  if (revokeTokens) {
    statements.push(
      `DELETE FROM tokens WHERE device_id IN (SELECT id FROM devices WHERE user_id = (SELECT id FROM users WHERE email = ${e}));`,
    );
  }
  return statements.join("\n");
}
```

`relay/scripts/reset-password.ts`:

```ts
// Emergency support tool (spec §5.2): sets a new password for one account directly in D1.
//
//   npm run reset-password -- --env <local|staging|production> --email <address> [--password <new>] [--revoke-tokens]
//
// Without --password a random 16-character password is generated and printed once.
// --revoke-tokens also signs out every device of the account (their open sockets stay up until they
// reconnect). Pairings are never touched. Remote environments need `npx wrangler login` first.
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { parseArgs } from "node:util";
import { createArgon2 } from "../src/auth/argon2";
import { isValidEmail, normalizeEmail } from "../src/auth/email";
import { isAcceptablePassword } from "../src/auth/password-policy";
import { base64UrlEncode } from "../src/auth/tokens";
import { buildResetSql } from "./reset-sql";

const { values } = parseArgs({
  options: {
    env: { type: "string" },
    email: { type: "string" },
    password: { type: "string" },
    "revoke-tokens": { type: "boolean", default: false },
  },
});

const target = values.env;
if (target !== "local" && target !== "staging" && target !== "production") {
  throw new Error("--env must be one of: local, staging, production");
}
const email = normalizeEmail(values.email ?? "");
if (!isValidEmail(email)) throw new Error("--email is not a valid address");
const password = values.password ?? base64UrlEncode(crypto.getRandomValues(new Uint8Array(12)));
if (!isAcceptablePassword(password)) throw new Error("password must be 8-128 characters");

const require = createRequire(import.meta.url);
const wasm = readFileSync(require.resolve("@phi-ag/argon2/argon2.wasm"));
const argon2 = await createArgon2(new WebAssembly.Module(wasm));
const sql = buildResetSql(email, argon2.hash(password), Date.now(), values["revoke-tokens"]);

const wrangler = join(dirname(require.resolve("wrangler/package.json")), "bin", "wrangler.js");
const where = target === "local" ? ["--local"] : ["--env", target, "--remote"];
const output = execFileSync(process.execPath, [wrangler, "d1", "execute", "DB", ...where, "--json", "--command", sql], {
  encoding: "utf8",
  stdio: ["inherit", "pipe", "inherit"],
});
const results = JSON.parse(output) as { results: { n?: number }[] }[];
if (results[0]?.results[0]?.n !== 1) {
  console.error(`No account with email ${email} in ${target}; nothing changed.`);
  process.exit(1);
}
console.log(`Password reset for ${email} in ${target}.`);
if (values.password === undefined) console.log(`Temporary password: ${password}`);
if (values["revoke-tokens"]) console.log("All device tokens of this account were revoked.");
```

In `relay/package.json` replace:

```json
  "scripts": {
    "dev": "wrangler d1 migrations apply DB --local && wrangler dev",
    "test": "vitest run",
    "typecheck": "tsc -p tsconfig.json && tsc -p scripts/tsconfig.json",
    "db:migrate:local": "wrangler d1 migrations apply DB --local",
    "db:migrate:staging": "wrangler d1 migrations apply DB --env staging --remote",
    "db:migrate:production": "wrangler d1 migrations apply DB --env production --remote",
    "deploy:staging": "wrangler deploy --env staging",
    "deploy:production": "wrangler deploy --env production",
    "domains:update": "tsx scripts/update-disposable-domains.ts"
  },
```

with:

```json
  "scripts": {
    "dev": "wrangler d1 migrations apply DB --local && wrangler dev",
    "test": "vitest run",
    "typecheck": "tsc -p tsconfig.json && tsc -p scripts/tsconfig.json",
    "db:migrate:local": "wrangler d1 migrations apply DB --local",
    "db:migrate:staging": "wrangler d1 migrations apply DB --env staging --remote",
    "db:migrate:production": "wrangler d1 migrations apply DB --env production --remote",
    "deploy:staging": "wrangler deploy --env staging",
    "deploy:production": "wrangler deploy --env production",
    "domains:update": "tsx scripts/update-disposable-domains.ts",
    "reset-password": "tsx scripts/reset-password.ts"
  },
```

- [ ] **Step 4: Run tests**

Run: `npx vitest run && npm run typecheck`
Expected: PASS, `129 passed (129)`; typecheck exits 0.

- [ ] **Step 5: Smoke-test against the local dev server**

With `npm run dev` running in another terminal:

```bash
KEY=$(node -e 'console.log(Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString("base64url"))')
curl -s -X POST http://127.0.0.1:8787/v1/auth/register -H 'Content-Type: application/json' \
  -d "{\"email\":\"smoke@example.com\",\"password\":\"initial password\",\"device\":{\"kind\":\"agent\",\"name\":\"smoke-mac\",\"platform\":\"macos\",\"public_key\":\"$KEY\"}}"
npm run -s reset-password -- --env local --email Smoke@Example.com --password "support reset 1"
curl -s -o /dev/null -w "%{http_code}\n" -X POST http://127.0.0.1:8787/v1/auth/login -H 'Content-Type: application/json' \
  -d "{\"email\":\"smoke@example.com\",\"password\":\"support reset 1\",\"device\":{\"kind\":\"agent\",\"name\":\"smoke-mac\",\"platform\":\"macos\",\"public_key\":\"$KEY\"}}"
npm run -s reset-password -- --env local --email nobody@example.com; echo "exit=$?"
```

Expected: a `201` JSON body `{"user_id":…,"device_id":…,"token":…}` (use a new address if `smoke@example.com` already exists locally), `Password reset for smoke@example.com in local.`, `200`, then `No account with email nobody@example.com in local; nothing changed.` and `exit=1`.

- [ ] **Step 6: Commit** (from the repository root)

```bash
git add relay/package.json relay/scripts/reset-sql.ts relay/scripts/reset-password.ts relay/test/reset-password.test.ts
git commit -m "feat(relay): emergency reset-password admin script"
```

---

### Task 11: `relay/README.md` — local dev, deployment runbook, cost check; final verification

**Files:**
- Create: `relay/README.md`

**Interfaces:**
- Consumes: every npm script and the `wrangler.jsonc` layout from Tasks 1–10.
- Produces: the operator runbook referenced by plan 06 (release) and by spec §15 R2.

- [ ] **Step 1: Write `relay/README.md`**

````markdown
# ShellX relay

Cloudflare Worker (Hono) + Durable Object `UserHub` (SQLite-backed, WebSocket Hibernation API) + D1.
It stores accounts, devices and pairings, and forwards end-to-end encrypted frames between devices of
the same account. Design: `docs/superpowers/specs/2026-09-25-shellx-v1-design.md` §5, §6, §10.

## Local development

Requires Node.js ≥ 22.

```bash
cd relay
npm ci
npm test            # Vitest inside workerd (real D1 + Durable Objects); no network needed
npm run typecheck   # Worker/test sources and Node scripts
npm run dev         # applies local D1 migrations, then serves http://127.0.0.1:8787
```

- Host and port come from the `dev` block of `wrangler.jsonc`; `npm run dev -- --ip 127.0.0.1 --port 8787`
  (what CI and the plan-03 E2E suite run) is equivalent. Do not add `--ip`/`--port` to the npm script
  itself: wrangler rejects a flag given twice.
- The first run in an interactive terminal asks to confirm applying the migrations (answer `y`);
  non-interactive shells (CI) skip the prompt.
- Local state lives in `.wrangler/state/`; delete that directory to start from an empty database.
- Rate limits are off locally (`RATE_LIMITS_ENABLED = "false"` in the top-level `vars`) because the E2E
  suite creates many accounts from 127.0.0.1. Staging and production set `"true"`; only the exact
  string `"false"` disables them.
- `compatibility_date` must not be newer than the workerd bundled with
  `@cloudflare/vitest-pool-workers`, otherwise `npm test` fails with
  "This Worker requires compatibility date …". Bump both together.

## Deployment runbook

### Prerequisites (once)

1. A Cloudflare account on the **Workers Paid** plan. Password hashing (argon2id, m = 19456 KiB,
   t = 2) needs tens of milliseconds of CPU per login/registration, beyond the Free plan's 10 ms CPU limit.
2. The `shellx.pro` zone is active in the same Cloudflare account (its DNS is served by Cloudflare).
3. `npx wrangler login` on the machine that deploys (or `CLOUDFLARE_API_TOKEN` with permission to edit
   Workers scripts, D1, and Workers custom domains/routes on `shellx.pro`).

### Create an environment (staging first, then production)

1. Create the database close to the users (Vietnam → `apac`):

   ```bash
   npx wrangler d1 create shellx-staging --location apac
   ```

   Copy the printed `database_id` into `env.staging.d1_databases[0].database_id` in `wrangler.jsonc`
   and commit it. (Production: `shellx-production` → `env.production.d1_databases[0].database_id`.)
2. Apply the schema: `npm run db:migrate:staging` (production: `npm run db:migrate:production`).
3. Deploy: `npm run deploy:staging` (production: `npm run deploy:production`). This creates the Worker
   `shellx-relay-staging` / `shellx-relay-production`, the `UserHub` Durable Object namespace
   (migration tag `v1`), and the custom domain `relay-staging.shellx.pro` / `relay.shellx.pro`.
4. DNS: custom domains create their DNS record and certificate automatically. If a DNS record named
   `relay` or `relay-staging` already exists in the zone, delete it first or the deploy fails.
5. Verify:

   ```bash
   curl https://relay-staging.shellx.pro/v1/version
   curl https://relay.shellx.pro/v1/version
   ```

Rate limiting `namespace_id`s must be unique within the account: 1001–1003 production,
2001–2003 staging, 9001–9003 local only.

### Every release

1. Refresh the disposable-domain list: `npm run domains:update`, review the diff, `npm test`, commit.
2. Staging first: `npm run db:migrate:staging && npm run deploy:staging`, check `/v1/version`, then the
   same for production. Always apply migrations before deploying code that needs them.
3. New desktop build or minimum versions: edit `MIN_AGENT`, `MIN_MOBILE`, `LATEST_AGENT_VERSION`,
   `MAC_URL`, `WIN_URL` in the environment's `vars` block and deploy.

### Operations

- Live logs: `npx wrangler tail --env production`. Logs carry metadata only (time, device_id, error
  codes, frame sizes); never payloads, tokens, passwords or e-mail addresses.
- Emergency password reset (spec §5.2):

  ```bash
  npm run reset-password -- --env production --email user@example.com
  npm run reset-password -- --env production --email user@example.com --password "new password" --revoke-tokens
  ```

  Without `--password` a temporary password is generated and printed once. `--revoke-tokens` signs out
  every device of the account (sockets already open stay up until they reconnect). Pairings are kept.
- Roll back code: `npx wrangler rollback --env production`. D1 migrations are not rolled back; write a
  new forward migration instead.

## Cost check before opening public sign-up (spec §15, risk R2)

Check the current prices on Cloudflare's pricing pages; do not rely on numbers copied from elsewhere.

- **Durable Objects:** requests (incoming WebSocket messages are billed as requests at a reduced
  ratio: check the current ratio), duration (GB-s: hibernation stops idle sockets from accruing it),
  and whether `setWebSocketAutoResponse` ping/pong counts as a request.
- **Workers:** requests (REST calls and WebSocket upgrades) and CPU time (argon2id on register/login).
- **D1:** rows read/written (token lookups on every authenticated request, `last_seen_at` on every
  disconnect) and storage.
- **R2 (`download.shellx.pro`, plan 06):** storage and Class B (read) operations; confirm egress is still free.
- **Per-user estimate:** an interactive session sends at most ~62 frames/s per open channel from the
  agent (16 ms batching) plus one frame per keystroke from the phone; every connected device sends a
  `ping` every 30 s. Monthly messages ≈ active-session-seconds × average frames/s + connected-minutes × 2.
  Write the estimate and the assumptions into this section before launch.
````

- [ ] **Step 2: Final verification (no real deploy)**

Run:

```bash
npm test
npm run typecheck
npx wrangler deploy --dry-run --env production --outdir dist
npx wrangler deploy --dry-run --env staging --outdir dist
```

Expected: `129 passed (129)`; typecheck exits 0; each dry run prints `--dry-run: exiting now.` after listing `env.USER_HUB (UserHub)`, `env.DB (shellx-production|shellx-staging)`, the three limiters as `10 requests/60s`, `5 requests/60s`, `3 requests/60s`, and `env.RATE_LIMITS_ENABLED ("true")`. `dist/` is git-ignored.

Then start `npm run dev -- --ip 127.0.0.1 --port 8787` and run:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8787/v1/version
curl -s -w " %{http_code}\n" -H "Upgrade: websocket" -H "Connection: Upgrade" -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" http://127.0.0.1:8787/v1/ws
```

Expected: `200`, then `{"error":{"code":"unauthorized","message":"Missing, invalid or expired token"}} 401`. Stop the server.

- [ ] **Step 3: Commit** (from the repository root)

```bash
git add relay/README.md
git commit -m "docs(relay): local development and deployment runbook"
```

---

## Spec coverage

| Spec / overview item | Task |
|---|---|
| §5.2 email normalisation, regex, disposable domain + parents, list bundled by script | 3, 5 |
| §5.2 password 8–128, argon2id m=19456 t=2 p=1 PHC | 1, 3 |
| §5.2 register/login with `device`, reuse `device_id` by public key | 5 |
| §5.2 token 32 B base64url, SHA-256 in D1, 90-day idle expiry, hourly `last_used_at` | 5 |
| §5.2 rate limits 10/IP, 5/email, 3/IP → 429; `RATE_LIMITS_ENABLED` | 4, 5 |
| §5.2 password change (agent only, revoke others, 4002, pairings kept) | 9 |
| §5.2 agent/mobile logout; account deletion | 9 |
| §5.2 `relay/scripts/reset-password.ts` via `wrangler d1` | 10 |
| §5.3 `POST /v1/pairings` (server side), §5.5 `DELETE` + `pairing_removed` | 8 |
| §6.1 `/v1/ws`, bearer header, ping/pong auto-response | 6 |
| §6.2 / overview §4.1 frame layout, ERROR codes, EVENT CBOR, close codes, 64 KiB, 500/s, PRESENCE, `last_seen_at` | 2, 6, 7, 8 |
| §10.1 stack, static WASM, Workers Paid | 1, 11 |
| §10.2 / overview §4.3 every route and error | 4, 5, 6, 8, 9 |
| §10.3 D1 schema | 4 |
| §10.4 `UserHub`: acceptWebSocket, attachment, 4001, RPC `online`/`disconnect`/`notifyPairingRemoved` | 6, 7, 8 |
| §10.5 staging + production, D1 migrations, metadata-only logs | 4, 6, 11 (+ log tests in 5, 6) |
| §12 relay side: 429, 4001/4002/4003 | 5, 6, 7, 9 |
| §13 relay tests: register/login, email + disposable, tokens, password change revocation, no cross-account routing, PRESENCE, frame limits, 4001/4002/4003 | 3, 5, 6, 7, 9 |
| §15 R1 spike, R2 cost check | 1, 11 |

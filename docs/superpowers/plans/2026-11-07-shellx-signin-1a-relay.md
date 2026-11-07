# ShellX Sign-in 1A: Relay — Google / Apple Sign-in, Identities, Account Deletion, Password Cut-over Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The relay accepts Google and Apple ID tokens (plus a test provider), finds or creates the right account by the rules of S1 §6.3, links hidden-email Apple IDs through a Mac's QR code, deletes accounts after a fresh provider sign-in, closes registration and gets the `PASSWORD_LOGIN` switch and cut-over tooling.

**Architecture:** New routes live in three Hono sub-apps: `routes/sign-in.ts` (mounted at `/v1/auth`), `routes/apple-link.ts` (at `/v1/auth/apple/link`) and `routes/identities.ts` (at `/v1/account/identities`). One verifier module (`auth/id-token.ts`, jose 6.2.13, cached remote JWKS) is injected through `AppDeps.idTokens`, so tests swap in local key sets. Every route does its awaits first (token check, nonce use, Apple REST, token hashing). It then resolves the account and writes inside one synchronous `db.transaction`, so two requests never interleave inside a resolution. Migration 0010 rebuilds `users` and `phone_pairings` to drop two NOT NULLs, under the existing `-- migrate: foreign_keys=off` directive.

**Decision: the approved Apple-link status hands the session out exactly once.** A conditional `UPDATE apple_links SET redeemed_at = ? WHERE … AND redeemed_at IS NULL` decides which call gets it, and the session token is minted at that moment, so no token sits in the database in clear. Minting a session on every call would make the 10-minute link token a bearer credential for the whole account. A lost answer can still be recovered: the Apple ID is linked by then, so the phone signs in with Apple again and lands on the same account and the same device, with its grant.

**Tech Stack:** Node ≥ 22, TypeScript 5.9 (`module: nodenext`, `verbatimModuleSyntax`), Hono 4, better-sqlite3, vitest ~4.1, `jose` 6.2.13. Deploy and website tests use `node:test`. The website is built with Astro.

**Spec:** `docs/superpowers/specs/2026-11-07-shellx-google-sign-in-design.md` (S1): §5, §6.1–§6.4 (incl. §6.3b), §6.8, §6.9, and the relay parts of §7, §8 and §9. The API it implements and every cross-plan name come from `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` §1–§2 (the contracts). Read both before Task 1.

## Global Constraints

- **Dependencies:** add only `jose`, pinned exactly `6.2.13` (MIT, no dependencies, no install scripts, published 2026-10-20). Never hand-write signature checks (S1 §5).
- **Errors:** every error keeps the shape `{"error": {"code", "message"}}`. New `Errors` names, statuses and codes are exactly those of contracts §2.
- **Nonce:** `POST /v1/auth/nonce` → `201 {nonce, expires_in}`. The nonce is 43-char base64url (32 random bytes), single use, and lives 600 s. Only its SHA-256 is stored.
- **ID-token checks (S1 §6.2):**
  - signature checked through the provider's JWKS;
  - `iss` is that provider's issuer;
  - `aud` is in the configured list;
  - `exp` has not passed (60 s clock tolerance);
  - `iat` is at most 600 s old (300 s for `DELETE /v1/account`) and at most 60 s in the future;
  - the nonce was issued by the relay and not used yet. Google and test tokens carry the raw nonce; for Apple the claim must equal `sha256_hex(nonce)`;
  - `email_verified` is true and `email` is a non-empty string.
- **Failure answer:** any failed check → 401 `invalid_credentials`, with no reason given to the client.
- **Issuers and endpoints:**
  - Google issuers: `https://accounts.google.com` and `accounts.google.com`; JWKS `https://www.googleapis.com/oauth2/v3/certs`.
  - Apple issuer: `https://appleid.apple.com`; JWKS `https://appleid.apple.com/auth/keys`.
  - Apple REST: `https://appleid.apple.com/auth/token` and `https://appleid.apple.com/auth/revoke`.
  - Apple client secret: an ES256 JWT with header `{alg: "ES256", kid: APPLE_SIWA_KEY_ID}` and claims `{iss: APPLE_TEAM_ID, sub: <bundle id>, aud: "https://appleid.apple.com", iat, exp: iat + 300}`.
- **Emails:** match with `normalizeEmail` only (trim + lowercase, `relay/src/auth/email.ts`). Do not fold Gmail dots or `+tag`.
- **Devices:** same account + same public key → same `device_id`. One live token per device: a sign-in deletes the device's previous token.
- **Env names (contracts §2), exactly:** `GOOGLE_CLIENT_IDS`, `APPLE_CLIENT_IDS` (default `com.shellx.prod,com.shellx.dev`), `APPLE_TEAM_ID`, `APPLE_SIWA_KEY_ID`, `APPLE_SIWA_KEY_PATH`, `PASSWORD_LOGIN` (`on` default | `off`), `TEST_IDP_ISSUER`, `TEST_IDP_JWKS_PATH`. The two `TEST_IDP_*` never appear in `deploy/`.
- **Token values:**
  - `tokens.auth_method`: `password` | `google` | `apple` | `test`. Existing rows default to `password`.
  - Provider values: `google`, `apple`, `test`. The test provider counts as an account's "Google sign-in".
- **Logs:** use `logMeta` only.
  - Never log an email, ID token, `sub`, nonce, authorization code, Apple refresh token, link token or session token.
  - New event names: `sign_in`, `sign_in_refused`, `id_token_rejected`, `google_linked`, `apple_link_required`, `apple_link_requested`, `apple_link_redeemed`, `identity_removed`, `password_access_dropped`, `apple_token_exchange_failed`, `apple_revoke_failed`, `apple_revoke_skipped`.
  - New startup events: `google_sign_in_disabled`, `test_idp_enabled`, `password_login_off`, `apple_siwa_enabled`, `apple_siwa_disabled`.
- **Storage:** session tokens, nonces and link tokens are stored only as SHA-256. Apple refresh tokens are stored as they are, because revoking needs them.
- **Commands:**
  - relay: `(cd relay && npm test && npm run typecheck)`;
  - one test file: `(cd relay && npx vitest run test/<name>.test.ts)`;
  - deploy: `node --test deploy/tests/compose.test.mjs`;
  - website: `(cd web && npm run build)`. It builds, then runs the site tests: `npm test` alone reads a stale `dist/`;
  - share e2e: `node scripts/shellx/share-e2e.mjs`.
- **Scope:** this plan changes no Swift, Rust, iOS, Android or desktop code, so no Mac test is needed. Never quit, relaunch or replace the user's running ShellX or cmux.
- **Copy:** the website is English only (`web/tests/site.test.mjs`: "The site is English only since 2026-10-29"). Relay `message` texts are English API messages; clients localize by `code`.
- **Commits:** each task commits once, test and code together, with an explicit `git add <paths>`. Never commit this plan or the contracts file on the feature branch (Task 0).

## Review Focus

1. **Password login against a passwordless account, using the dummy password `shellx-dummy-password`.** Today `/login` verifies against `user?.password_hash ?? dummyHash`. Once `password_hash` can be NULL, that password would verify. The expected answer is 401 and no device created in that account. Pinned in Task 2.
2. **The same email in another case or with spaces.** Google reports `Ann.Lee@Gmail.com`, the account holds `ann.lee@gmail.com`: they are one account for the 409 and link decisions. Pinned in Task 5.
3. **The iPhone loses the "approved" answer and polls again.** The second answer is 401. A fresh Apple sign-in then lands in the Mac's account, on the same `device_id`, with its grant. Pinned in Task 9.
4. **Removing one Apple ID.** It signs out only the devices that signed in with that Apple ID. The Mac, the Google devices and the phone grant stay. Pinned in Task 10.
5. **A recycled Workspace address.** A new Google account carries the email of an account that already has a Google sign-in. It must get 401: no takeover, and no 500 from the one-Google-per-account index. Pinned in Task 5.

## File map

| File | Responsibility |
| --- | --- |
| `relay/migrations/0010_identities.sql` | schema: identities, `tokens.auth_method` / `identity_id`, nonces, Apple links, nullable `users.password_hash` and `phone_pairings.device_id` |
| `relay/src/auth/providers.ts` | provider names, issuers, test audience, default Apple bundle ids |
| `relay/src/auth/id-token.ts` | `IdTokenVerifier` (jose): issuer dispatch, claims, nonce rule, cached JWKS |
| `relay/src/auth/nonces.ts` | issue / consume one-time nonces |
| `relay/src/auth/identity.ts` | account resolution (S1 §6.3), identity rows, device + token writes |
| `relay/src/auth/apple-rest.ts` | Apple client secret, code exchange, revoke, `loadAppleSiwa` |
| `relay/src/auth/apple-links.ts` | link tokens and the approval of an Apple-link pairing |
| `relay/src/routes/sign-in.ts` | `/v1/auth/nonce`, `/google`, `/google/link`, `/apple` |
| `relay/src/routes/apple-link.ts` | `/v1/auth/apple/link`, `/v1/auth/apple/link/status` |
| `relay/src/routes/identities.ts` | `GET` / `DELETE /v1/account/identities` |
| `relay/src/scripts/password-cutover.ts`, `relay/src/scripts/mint-smoke-token.ts` | operator scripts run inside the container |
| `relay/scripts/test-idp.ts` | test issuer (key pair, JWKS, signing) for tests and harnesses; not in the image |
| `relay/test/fake-idp.ts` | fake Google / Apple / test issuers, claim builders, `testIdTokens()`, `FakeAppleTokens` |

---

### Task 0: Set up the worktree

**Files:** none.

**Prerequisites:** none. No other plan has to be merged first (contracts §1). Plan 3F also changes `relay/` and may land on `develop` before or after this plan (Task 16 Step 3 handles the merge).

- [ ] **Step 1: Create the worktree with superpowers:using-git-worktrees**

Use the skill, with this location and branch:

```bash
git -C /Users/lehuuphu/Documents/myProjects/shellx worktree add .claude/worktrees/signin-1a-relay -b feat/shellx-signin-1a-relay develop
cd /Users/lehuuphu/Documents/myProjects/shellx/.claude/worktrees/signin-1a-relay
```

Expected: `Preparing worktree (new branch 'feat/shellx-signin-1a-relay')`. Every later path is relative to this worktree.

- [ ] **Step 2: Make the plan and the contracts readable**

If `docs/superpowers/plans/2026-11-07-shellx-signin-1a-relay.md` or `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` is missing in the worktree, read it from `/Users/lehuuphu/Documents/myProjects/shellx/docs/superpowers/plans/`. They may be uncommitted there. Do not copy or commit them on this branch.

- [ ] **Step 3: Install and take the baseline**

```bash
(cd relay && npm ci) && (cd web && npm ci)
(cd relay && npm test && npm run typecheck)
node --test deploy/tests/compose.test.mjs
```

Expected:
- vitest's summary has no `failed` count;
- `tsc` prints no `error TS` line;
- node:test ends with `# fail 0`.

If the untouched branch already fails, stop and report: do not fix unrelated failures.

---

### Task 1: Configuration, provider constants, error codes and the PASSWORD_LOGIN switch

**Files:**
- Create: `relay/src/auth/providers.ts`
- Modify: `relay/src/config.ts` (interface at lines 6-48, `loadConfig` at lines 70-133)
- Modify: `relay/src/http/errors.ts:14-49`
- Modify: `relay/src/routes/auth.ts` (`/login` at line 69, `/password` at line 173)
- Modify: `relay/src/routes/account.ts:16-41`
- Modify: `relay/test/helpers.ts:19-40` (`TEST_CONFIG`)
- Modify: `scripts/shellx/share-e2e.mjs:175-186` (the hand-built config)
- Test: `relay/test/config.test.ts`, `relay/test/errors.test.ts` (new), `relay/test/password-login.test.ts` (new)

**Interfaces:**
- Produces, in `relay/src/auth/providers.ts`:
  - `export type IdentityProvider = "google" | "apple" | "test";`
  - `export const GOOGLE_ISSUERS: readonly string[] = ["https://accounts.google.com", "accounts.google.com"];`
  - `export const APPLE_ISSUER = "https://appleid.apple.com";`
  - `export const TEST_IDP_AUDIENCE = "shellx-test-idp";`
  - `export const DEFAULT_APPLE_CLIENT_IDS: readonly string[] = ["com.shellx.prod", "com.shellx.dev"];`
  - `export function isPrimaryProvider(provider: IdentityProvider): boolean` (true for `google` and `test`).
- Produces, on `Config`:
  - `googleClientIds: string[]`
  - `appleClientIds: string[]`
  - `passwordLogin: boolean`
  - `testIdp: { issuer: string; jwksPath: string } | null`
- Produces, on `Errors`: `switchFromSignedInDevice`, `emailInUse`, `identityInUse`, `lastGoogleIdentity`, `registrationClosed`, `passwordSignInRemoved`, `reauthRequired`, `identityNotFound`.

- [ ] **Step 1: Write the failing tests**

In `relay/test/config.test.ts`, append these four fields to the expected object of the first test (`"reads the version variables and applies the defaults"`): `googleClientIds: [], appleClientIds: ["com.shellx.prod", "com.shellx.dev"], passwordLogin: true, testIdp: null`. Then add:

```ts
it("reads the sign-in settings", () => {
  const config = loadConfig({
    ...REQUIRED, GOOGLE_CLIENT_IDS: " a.apps.googleusercontent.com, b.apps.googleusercontent.com ,, ",
    APPLE_CLIENT_IDS: "com.shellx.dev", PASSWORD_LOGIN: "off",
    TEST_IDP_ISSUER: "https://test-idp.shellx.invalid", TEST_IDP_JWKS_PATH: "/tmp/jwks.json",
  });
  expect(config).toMatchObject({
    googleClientIds: ["a.apps.googleusercontent.com", "b.apps.googleusercontent.com"], appleClientIds: ["com.shellx.dev"],
    passwordLogin: false, testIdp: { issuer: "https://test-idp.shellx.invalid", jwksPath: "/tmp/jwks.json" },
  });
  expect(loadConfig({ ...REQUIRED, PASSWORD_LOGIN: "on" }).passwordLogin).toBe(true);
  expect(loadConfig({ ...REQUIRED, PASSWORD_LOGIN: " " }).passwordLogin).toBe(true);
});

it.each(["OFF", "false", "no", "1"])("refuses PASSWORD_LOGIN=%s", (flag) => {
  expect(() => loadConfig({ ...REQUIRED, PASSWORD_LOGIN: flag })).toThrow(`PASSWORD_LOGIN must be "on" or "off", got "${flag}"`);
});

it("refuses an empty Apple list, half a test provider and a test issuer that is Google's or Apple's", () => {
  expect(() => loadConfig({ ...REQUIRED, APPLE_CLIENT_IDS: " , " })).toThrow("APPLE_CLIENT_IDS must list at least one bundle id");
  for (const half of [{ TEST_IDP_ISSUER: "https://t.invalid" }, { TEST_IDP_JWKS_PATH: "/k.json" }]) {
    expect(() => loadConfig({ ...REQUIRED, ...half })).toThrow("TEST_IDP_ISSUER and TEST_IDP_JWKS_PATH must be set together");
  }
  for (const issuer of ["https://accounts.google.com", "accounts.google.com", "https://appleid.apple.com"]) {
    expect(() => loadConfig({ ...REQUIRED, TEST_IDP_ISSUER: issuer, TEST_IDP_JWKS_PATH: "/k.json" }))
      .toThrow("TEST_IDP_ISSUER must not be a Google or Apple issuer");
  }
});
```

`relay/test/errors.test.ts`:

```ts
import { expect, it } from "vitest";
import { Errors } from "../src/http/errors.js";

it.each([
  ["switchFromSignedInDevice", 409, "switch_from_signed_in_device"], ["emailInUse", 409, "email_in_use"],
  ["identityInUse", 409, "identity_in_use"], ["lastGoogleIdentity", 409, "last_google_identity"],
  ["registrationClosed", 410, "registration_closed"], ["passwordSignInRemoved", 410, "password_sign_in_removed"],
  ["reauthRequired", 401, "reauth_required"], ["identityNotFound", 404, "identity_not_found"],
] as const)("Errors.%s() is %i %s (contracts §2)", (name, status, code) => {
  const e = Errors[name]();
  expect([e.status, e.code]).toEqual([status, code]);
});
```

`relay/test/password-login.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { call, db, deviceBody, errorCode, makeApp, registerAccount, TEST_CONFIG } from "./helpers.js";

const off = () => makeApp({ config: { ...TEST_CONFIG, passwordLogin: false } });

describe("PASSWORD_LOGIN=off (S1 §6.9)", () => {
  it("answers 410 password_sign_in_removed to login and password change; signed-in sessions keep working", async () => {
    const account = await registerAccount(makeApp());
    const app = off();
    const login = await call(app, "POST", "/v1/auth/login", { body: { email: account.email, password: account.password, device: deviceBody("mobile") } });
    expect([login.status, await errorCode(login)]).toEqual([410, "password_sign_in_removed"]);
    const change = await call(app, "POST", "/v1/auth/password", { token: account.agent.token, body: { new_password: "brand new password" } });
    expect([change.status, await errorCode(change)]).toEqual([410, "password_sign_in_removed"]);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(200);
  });

  it("no longer takes the password to delete an account: 401 reauth_required, nothing deleted", async () => {
    const account = await registerAccount(makeApp());
    const res = await call(off(), "DELETE", "/v1/account", { token: account.agent.token, body: { password: account.password } });
    expect([res.status, await errorCode(res)]).toEqual([401, "reauth_required"]);
    expect(db().get("SELECT COUNT(*) AS n FROM users WHERE id = ?", account.agent.userId)).toEqual({ n: 1 });
  });
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `(cd relay && npx vitest run test/config.test.ts test/errors.test.ts test/password-login.test.ts)`
Expected: FAIL. The config default object lacks the new fields, `Errors[name]` is not a function, and the login answers 200 instead of 410.

- [ ] **Step 3: Implement**

`relay/src/auth/providers.ts`: the constants exactly as listed in the Interfaces block above.

`relay/src/config.ts`:
- Add the four fields to `Config`, with doc comments naming their env variables.
- In `loadConfig`, use the existing `value()` helper, so a blank value counts as unset:
  - `GOOGLE_CLIENT_IDS`: split on `,`, trim each entry, drop empty entries. Unset → `[]`.
  - `APPLE_CLIENT_IDS`: unset → `[...DEFAULT_APPLE_CLIENT_IDS]`. Set but empty after splitting → `ConfigError("APPLE_CLIENT_IDS must list at least one bundle id")`.
  - `PASSWORD_LOGIN`: unset or `on` → `true`; `off` → `false`; anything else → ``ConfigError(`PASSWORD_LOGIN must be "on" or "off", got "${text}"`)``.
  - `TEST_IDP_ISSUER` / `TEST_IDP_JWKS_PATH`:
    - both unset → `null`;
    - exactly one set → `ConfigError("TEST_IDP_ISSUER and TEST_IDP_JWKS_PATH must be set together")`;
    - an issuer that is in `GOOGLE_ISSUERS` or equals `APPLE_ISSUER` → `ConfigError("TEST_IDP_ISSUER must not be a Google or Apple issuer")`;
    - otherwise `{ issuer, jwksPath }`.

`relay/src/http/errors.ts`: add the entries, using exactly these messages:

```ts
switchFromSignedInDevice: () => new ApiError(409, "switch_from_signed_in_device", "This email already has a ShellX account: switch it to Google from a device that is signed in"),
emailInUse: () => new ApiError(409, "email_in_use", "Another account already uses this email address"),
identityInUse: () => new ApiError(409, "identity_in_use", "This sign-in is already used by another account"),
lastGoogleIdentity: () => new ApiError(409, "last_google_identity", "The Google sign-in of an account cannot be removed"),
registrationClosed: () => new ApiError(410, "registration_closed", "Registration is closed: sign in with Google or Apple"),
passwordSignInRemoved: () => new ApiError(410, "password_sign_in_removed", "Password sign-in was removed: sign in with Google or Apple"),
reauthRequired: () => new ApiError(401, "reauth_required", "Sign in again with Google or Apple to confirm"),
identityNotFound: () => new ApiError(404, "identity_not_found", "Sign-in method not found"),
```

`relay/src/routes/auth.ts`:
- Add a middleware `passwordLoginOn: MiddlewareHandler<AppEnv>` that throws `Errors.passwordSignInRemoved()` when `!c.get("config").passwordLogin`.
- Put it first on `/login` (`authRoutes.post("/login", passwordLoginOn, jsonBodyLimit, …)`) and first on `/password`, ahead of `requireAuth`.

`relay/src/routes/account.ts`: right after the `loginEmail` limiter call, when `!c.get("config").passwordLogin`, log `account_delete_denied` with the device id and throw `Errors.reauthRequired()`.

`relay/test/helpers.ts`: add `googleClientIds: [], appleClientIds: ["com.shellx.prod", "com.shellx.dev"], passwordLogin: true, testIdp: null` to `TEST_CONFIG`.

`scripts/shellx/share-e2e.mjs`: add the same four fields to `config` (after `shareAllowedOrigin: ORIGIN,`). Its in-process relay would otherwise read `passwordLogin` as `undefined`, which means off.

- [ ] **Step 4: Run the tests to see them pass**

Run: `(cd relay && npx vitest run test/config.test.ts test/errors.test.ts test/password-login.test.ts)`, then `(cd relay && npm test && npm run typecheck)` and `node --check scripts/shellx/share-e2e.mjs`.
Expected: `Test Files  3 passed (3)`; the full suite has no failed file; no `error TS` line; `node --check` prints nothing.

- [ ] **Step 5: Commit**

```bash
git add relay/src/auth/providers.ts relay/src/config.ts relay/src/http/errors.ts relay/src/routes/auth.ts relay/src/routes/account.ts relay/test/helpers.ts relay/test/config.test.ts relay/test/errors.test.ts relay/test/password-login.test.ts scripts/shellx/share-e2e.mjs
git commit -m "feat(relay): sign-in settings, new error codes and the PASSWORD_LOGIN switch"
```

---

### Task 2: Migration 0010 and passwordless accounts in the password routes

**Files:**
- Create: `relay/migrations/0010_identities.sql`
- Test: `relay/test/migrate-0010.test.ts` (new)
- Modify: `relay/test/db.test.ts:104`, `relay/test/migrate-0005.test.ts:36`, `relay/test/migrate-0007.test.ts:28`, `relay/test/migrate-0008.test.ts:18`: append `"0010_identities.sql"` to each expected migration list.
- Modify: `relay/src/routes/auth.ts:85-91` (login), `relay/src/routes/account.ts` (password check)
- Modify: `relay/test/helpers.ts` (`TestApp`, `makeApp`, new `seedUser`)
- Test: `relay/test/auth.test.ts`, `relay/test/account.test.ts`

**Interfaces:**
- Produces:
  - `relay/test/helpers.ts`: `export interface TestApp { readonly ready: Promise<RunningRelay>; readonly now?: () => number }`. `makeApp` returns `now: deps.now ?? Date.now`; `remote(port)` apps leave it out.
  - `relay/test/helpers.ts`: `export async function seedUser(email: string, password: string | null, nowMs: number = Date.now()): Promise<string>` inserts a `users` row straight into `db()`: a new UUID, `normalizeEmail(email)`, `hashPassword(password)` or NULL, `password_changed_at = created_at = nowMs`. It returns the id.
  - Tables and columns of the SQL below, used by every later task.

- [ ] **Step 1: Write the migration test and the two route tests**

`relay/test/migrate-0010.test.ts`:

```ts
import { copyFileSync, mkdirSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { authenticate } from "../src/auth/session.js";
import { hashToken } from "../src/auth/tokens.js";
import { Db } from "../src/db/db.js";
import { migrate, MIGRATIONS_DIR } from "../src/db/migrate.js";
import { tempDir } from "./helpers.js";

const MACHINE = `INSERT INTO machines (id, user_id, device_id, name, platform, os_version, app_version, noise_public_key, fingerprint, slot, link_slot, created_at)
                 VALUES ('m1', 'u1', 'dm', 'Mac', 'macos', '15', '1', ?, 'f', 's', 'ls', 1)`;
const DEVICE = "INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at) VALUES (?, 'u1', ?, 'n', ?, ?, 1)";

describe("migration 0010", () => {
  it("keeps every row and token, marks old tokens as password sign-ins and allows accounts without a password", async () => {
    const oldDir = join(tempDir(), "v9");
    mkdirSync(oldDir);
    for (const name of readdirSync(MIGRATIONS_DIR)) if (name < "0010") copyFileSync(join(MIGRATIONS_DIR, name), join(oldDir, name));
    const db = Db.open(join(tempDir(), "v9.db"));
    try {
      migrate(db, oldDir);
      const legacy = "legacy-token-0123456789abcdef0123456789abcdef";
      db.run("INSERT INTO users VALUES ('u1', 'a@example.com', 'x', 1, 1)");
      db.run(DEVICE, "dm", "desktop", "macos", new Uint8Array([1]));
      db.run(DEVICE, "dp", "mobile", "ios", new Uint8Array([2]));
      db.run("INSERT INTO tokens (token_hash, device_id, created_at, last_used_at) VALUES (?, 'dp', 1, ?)", await hashToken(legacy), Date.now());
      db.run(MACHINE, new Uint8Array(32));
      db.run("INSERT INTO phone_pairings (id, user_id, device_id, machine_id, client_key, proof, status, created_at) VALUES ('pp', 'u1', 'dp', 'm1', ?, 'p', 'pending', 1)", new Uint8Array(32));
      const counts = () => ["users", "devices", "tokens", "machines", "phone_pairings"].map((t) => db.get<{ n: number }>(`SELECT COUNT(*) AS n FROM ${t}`)!.n);
      const before = counts();

      expect(migrate(db)).toEqual(["0010_identities.sql"]);

      expect(counts()).toEqual(before);
      expect(db.get("SELECT auth_method, identity_id FROM tokens")).toEqual({ auth_method: "password", identity_id: null });
      expect(await authenticate(db, legacy, Date.now())).toMatchObject({ deviceId: "dp", kind: "mobile" });
      db.run("INSERT INTO users (id, email, password_hash, password_changed_at, created_at) VALUES ('u2', 'b@example.com', NULL, 1, 1)");
      expect(db.get("PRAGMA foreign_keys")).toEqual({ foreign_keys: 1 });
      expect(db.all("PRAGMA foreign_key_check")).toEqual([]);
    } finally {
      db.close();
    }
  });

  it("allows one Google sign-in per account, any number of Apple IDs, and cascades from identities, links and users", () => {
    const db = Db.open(join(tempDir(), "v10.db"));
    try {
      migrate(db);
      db.run("INSERT INTO users VALUES ('u1', 'a@example.com', NULL, 1, 1)");
      db.run(DEVICE, "dm", "desktop", "macos", new Uint8Array([1]));
      db.run(DEVICE, "dp", "mobile", "ios", new Uint8Array([2]));
      const identity = (id: string, provider: string, subject: string) =>
        db.run("INSERT INTO identities (id, provider, subject, user_id, email, created_at, last_used_at) VALUES (?, ?, ?, 'u1', 'a@example.com', 1, 1)", id, provider, subject);
      identity("i-g", "google", "g1");
      identity("i-a1", "apple", "a1");
      identity("i-a2", "apple", "a2");
      expect(() => identity("i-g2", "google", "g2")).toThrow(/UNIQUE/);
      expect(() => identity("i-t", "test", "t1")).toThrow(/UNIQUE/);
      expect(() => identity("i-x", "apple", "a1")).toThrow(/UNIQUE/);
      expect(() => identity("i-f", "facebook", "f1")).toThrow(/CHECK/);
      db.run("INSERT INTO tokens (token_hash, device_id, created_at, last_used_at, auth_method, identity_id) VALUES (x'aa', 'dp', 1, 1, 'apple', 'i-a1')");
      expect(() => db.run("INSERT INTO tokens (token_hash, device_id, created_at, last_used_at, auth_method) VALUES (x'bb', 'dp', 1, 1, 'magic')")).toThrow(/CHECK/);
      db.run("DELETE FROM identities WHERE id = 'i-a1'");
      expect(db.get("SELECT COUNT(*) AS n FROM tokens")).toEqual({ n: 0 });
      db.run("UPDATE identities SET linked_via_device_id = 'dp' WHERE id = 'i-a2'");

      db.run(MACHINE, new Uint8Array(32));
      db.run(`INSERT INTO apple_links (id, token_hash, subject, email, is_private_email, apple_client_id, device_name, device_public_key, created_at, expires_at)
              VALUES ('l1', x'cc', 'a9', 'h@privaterelay.appleid.com', 1, 'com.shellx.dev', 'iPhone', ?, 1, 600001)`, new Uint8Array(32));
      const pairing = (id: string, deviceId: string | null, linkId: string | null) =>
        db.run("INSERT INTO phone_pairings (id, user_id, device_id, machine_id, client_key, proof, status, created_at, apple_link_id) VALUES (?, 'u1', ?, 'm1', ?, 'p', 'pending', 1, ?)", id, deviceId, new Uint8Array(32), linkId);
      expect(() => pairing("p0", null, null)).toThrow(/CHECK/);
      pairing("p1", null, "l1");
      db.run("DELETE FROM apple_links WHERE id = 'l1'");
      expect(db.get("SELECT COUNT(*) AS n FROM phone_pairings")).toEqual({ n: 0 });

      db.run("DELETE FROM devices WHERE id = 'dp'");
      expect(db.get("SELECT linked_via_device_id FROM identities WHERE id = 'i-a2'")).toEqual({ linked_via_device_id: null });
      db.run("DELETE FROM users WHERE id = 'u1'");
      for (const t of ["identities", "devices", "machines"]) expect(db.get<{ n: number }>(`SELECT COUNT(*) AS n FROM ${t}`)!.n).toBe(0);
    } finally {
      db.close();
    }
  });
});
```

In `relay/test/auth.test.ts`, inside `describe("POST /v1/auth/login")` (add `seedUser` to the import from `./helpers.js`):

```ts
it("refuses an account without a password, even with the dummy password, and adds no device to it", async () => {
  const app = makeApp();
  const email = randomEmail();
  const userId = await seedUser(email, null);
  const res = await call(app, "POST", "/v1/auth/login", { body: { email, password: "shellx-dummy-password", device: deviceBody("mobile") } });
  expect([res.status, await errorCode(res)]).toEqual([401, "invalid_credentials"]);
  expect(db().get("SELECT COUNT(*) AS n FROM devices WHERE user_id = ?", userId)).toEqual({ n: 0 });
});
```

In `relay/test/account.test.ts`, inside `describe("DELETE /v1/account")`:

```ts
it("answers 401 reauth_required to a password for an account that has none, and deletes nothing", async () => {
  const app = makeApp();
  const account = await registerAccount(app);
  db().run("UPDATE users SET password_hash = NULL WHERE id = ?", account.agent.userId);
  const res = await call(app, "DELETE", "/v1/account", { token: account.agent.token, body: { password: account.password } });
  expect([res.status, await errorCode(res)]).toEqual([401, "reauth_required"]);
  expect(countRows("SELECT COUNT(*) AS n FROM users WHERE id = ?", account.agent.userId)).toBe(1);
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `(cd relay && npx vitest run test/migrate-0010.test.ts test/auth.test.ts test/account.test.ts)`
Expected: FAIL. `migrate(db)` returns `[]`, `seedUser` is not exported, and the NULL update hits `NOT NULL constraint failed: users.password_hash`.

- [ ] **Step 3: Write the migration**

`relay/migrations/0010_identities.sql` must start with the directive line, exactly:

```sql
-- migrate: foreign_keys=off
-- Sign in with Google and Apple (S1 §6.1). users and phone_pairings are rebuilt to drop a NOT NULL (the
-- 12-step procedure of sqlite.org/lang_altertable.html section 7, as in 0005; foreign keys are off).
CREATE TABLE users_new (
  id                  TEXT PRIMARY KEY,
  email               TEXT NOT NULL UNIQUE,
  password_hash       TEXT,                        -- NULL: no password (Google account, or after the cut-over)
  password_changed_at INTEGER NOT NULL,
  created_at          INTEGER NOT NULL
);
INSERT INTO users_new (id, email, password_hash, password_changed_at, created_at)
  SELECT id, email, password_hash, password_changed_at, created_at FROM users;
DROP TABLE users;
ALTER TABLE users_new RENAME TO users;

CREATE TABLE identities (
  id                   TEXT PRIMARY KEY,                                       -- UUIDv4: the API's identity_id
  provider             TEXT NOT NULL CHECK (provider IN ('google', 'apple', 'test')),
  subject              TEXT NOT NULL,                                          -- the ID token's sub
  user_id              TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  email                TEXT NOT NULL,                                          -- normalized, as verified when linked
  is_private_email     INTEGER NOT NULL DEFAULT 0 CHECK (is_private_email IN (0, 1)),
  apple_refresh_token  TEXT,                                                   -- Apple only: revoked on removal / deletion
  apple_client_id      TEXT,                                                   -- the bundle id that refresh token belongs to
  linked_via_device_id TEXT REFERENCES devices(id) ON DELETE SET NULL,         -- the iPhone that linked this Apple ID by QR
  created_at           INTEGER NOT NULL,
  last_used_at         INTEGER NOT NULL,
  UNIQUE (provider, subject)
);
CREATE INDEX identities_user_id ON identities (user_id);
-- One Google (or test) sign-in per account (S1 §3); Apple IDs are not limited.
CREATE UNIQUE INDEX identities_one_primary ON identities (user_id) WHERE provider != 'apple';

-- How each token was minted (every older row was a password sign-in; the cut-over deletes those), and the
-- sign-in it came from: removing an Apple ID deletes its tokens.
ALTER TABLE tokens ADD COLUMN auth_method TEXT NOT NULL DEFAULT 'password'
  CHECK (auth_method IN ('password', 'google', 'apple', 'test'));
ALTER TABLE tokens ADD COLUMN identity_id TEXT REFERENCES identities(id) ON DELETE CASCADE;
CREATE INDEX tokens_identity_id ON tokens (identity_id);

-- One-time nonces of POST /v1/auth/nonce: only their SHA-256; a row goes when used or expired.
CREATE TABLE auth_nonces (
  nonce_hash BLOB PRIMARY KEY,
  expires_at INTEGER NOT NULL
);
CREATE INDEX auth_nonces_expires_at ON auth_nonces (expires_at);

-- An Apple sign-in that matched no account (S1 §6.4). The link token (only its SHA-256 here) lets that
-- iPhone ask a Mac, for 10 minutes, to link the Apple ID to the Mac's account.
CREATE TABLE apple_links (
  id                  TEXT PRIMARY KEY,
  token_hash          BLOB NOT NULL UNIQUE,
  subject             TEXT NOT NULL,
  email               TEXT NOT NULL,
  is_private_email    INTEGER NOT NULL CHECK (is_private_email IN (0, 1)),
  apple_client_id     TEXT NOT NULL,
  apple_refresh_token TEXT,
  device_name         TEXT NOT NULL,
  device_public_key   BLOB NOT NULL CHECK (length(device_public_key) = 32),
  created_at          INTEGER NOT NULL,
  expires_at          INTEGER NOT NULL,
  redeemed_at         INTEGER                                                  -- set when the approved session was handed out
);

CREATE TABLE phone_pairings_new (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id     TEXT REFERENCES devices(id) ON DELETE CASCADE,                -- NULL for an Apple link until approved
  machine_id    TEXT NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
  client_key    BLOB NOT NULL CHECK (length(client_key) = 32),
  proof         TEXT NOT NULL,
  status        TEXT NOT NULL CHECK (status IN ('pending','approved','denied','expired')),
  created_at    INTEGER NOT NULL,
  decided_at    INTEGER,
  apple_link_id TEXT REFERENCES apple_links(id) ON DELETE CASCADE,            -- set for a request made with a link token
  CHECK (device_id IS NOT NULL OR apple_link_id IS NOT NULL)
);
INSERT INTO phone_pairings_new (id, user_id, device_id, machine_id, client_key, proof, status, created_at, decided_at)
  SELECT id, user_id, device_id, machine_id, client_key, proof, status, created_at, decided_at FROM phone_pairings;
DROP TABLE phone_pairings;
ALTER TABLE phone_pairings_new RENAME TO phone_pairings;
CREATE INDEX phone_pairings_machine ON phone_pairings (machine_id, status);
CREATE INDEX phone_pairings_device ON phone_pairings (device_id);
CREATE INDEX phone_pairings_apple_link ON phone_pairings (apple_link_id);
```

`relay/src/db/migrate.ts` needs no change: the first line switches foreign keys off and `foreign_key_check` runs before the commit. Append `"0010_identities.sql"` to the four expected lists named under **Files**.

- [ ] **Step 4: Make the password routes handle NULL hashes, and add the helpers**

In `relay/src/routes/auth.ts`, `/login`:
- Type the row as `{ id: string; password_hash: string | null }`.
- Keep the verify against `user?.password_hash ?? (await dummyHash(passwords))`, so timing is unchanged.
- Refuse with `invalid_credentials` (logging `login_failed`) when `user === undefined || user.password_hash === null || !passwordOk`. Do this before the device upsert.

In `relay/src/routes/account.ts`, type `password_hash: string | null`. A NULL hash logs `account_delete_denied` and throws `Errors.reauthRequired()` before argon2 runs.

In `relay/test/helpers.ts`, add `TestApp.now`, `makeApp`'s `now` and `seedUser` as described in the Interfaces block.

- [ ] **Step 5: Run the tests to see them pass**

Run: `(cd relay && npx vitest run test/migrate-0010.test.ts test/auth.test.ts test/account.test.ts test/db.test.ts test/migrate-0005.test.ts test/migrate-0007.test.ts test/migrate-0008.test.ts)`, then `(cd relay && npm test && npm run typecheck)`.
Expected: `Test Files  7 passed (7)`; the full suite has no failed file; no `error TS` line.

- [ ] **Step 6: Commit**

```bash
git add relay/migrations/0010_identities.sql relay/test/migrate-0010.test.ts relay/test/db.test.ts relay/test/migrate-0005.test.ts relay/test/migrate-0007.test.ts relay/test/migrate-0008.test.ts relay/src/routes/auth.ts relay/src/routes/account.ts relay/test/helpers.ts relay/test/auth.test.ts relay/test/account.test.ts
git commit -m "feat(relay): migration 0010 (identities, nonces, Apple links, passwordless accounts)"
```

---

### Task 3: ID-token verifier, test issuer and fake identity providers

**Files:**
- Modify: `relay/package.json`, `relay/package-lock.json` (through npm)
- Create: `relay/src/auth/id-token.ts`, `relay/scripts/test-idp.ts`, `relay/test/fake-idp.ts`
- Test: `relay/test/id-token.test.ts` (new)

**Interfaces:**
- Consumes: `relay/src/auth/providers.ts` (Task 1).
- Produces, in `relay/src/auth/id-token.ts`:
  - `export const GOOGLE_JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs"`
  - `export const APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"`
  - `export const ID_TOKEN_MAX_AGE_SEC = 600`, `export const REAUTH_MAX_AGE_SEC = 300`
  - `export const CLOCK_TOLERANCE_SEC = 60`, `export const MAX_ID_TOKEN_CHARS = 8192`
  - `export interface VerifiedIdToken { provider: IdentityProvider; subject: string; email: string; isPrivateEmail: boolean; audience: string }`. `email` is already `normalizeEmail`'d; `audience` is the matched client id (for Apple, the bundle id).
  - `export interface VerifyOptions { providers: readonly IdentityProvider[]; nonce: string; maxAgeSec: number; nowMs: number }`
  - `export interface IdTokenVerifier { verify(token: unknown, options: VerifyOptions): Promise<VerifiedIdToken | null> }`. It never throws for a bad token.
  - `export interface IdTokenVerifierOptions { googleClientIds: readonly string[]; appleClientIds: readonly string[]; testIdp: { issuer: string; keys: JWTVerifyGetKey } | null; googleKeys?: JWTVerifyGetKey; appleKeys?: JWTVerifyGetKey }`. The key defaults are `createRemoteJWKSet(new URL(GOOGLE_JWKS_URL))` and `createRemoteJWKSet(new URL(APPLE_JWKS_URL))`; jose caches them.
  - `export function createIdTokenVerifier(options: IdTokenVerifierOptions): IdTokenVerifier`
  - `export function loadIdTokenVerifier(config: Pick<Config, "googleClientIds" | "appleClientIds" | "testIdp">, readFile: (path: string) => string = (p) => readFileSync(p, "utf8")): IdTokenVerifier`. It throws `ConfigError("TEST_IDP_JWKS_PATH is not a readable JWKS file")` when the file is unreadable, not JSON, or not accepted by `createLocalJWKSet`.
  - `export function sha256Hex(text: string): string` (lower-case hex of the UTF-8 bytes).
- Produces, in `relay/scripts/test-idp.ts`:
  - `export interface TestIssuer { readonly issuer: string; readonly jwks: JSONWebKeySet; readonly keys: JWTVerifyGetKey; sign(claims: JWTPayload, header?: Partial<JWTHeaderParameters>): Promise<string> }`. `jwks` holds the public keys, each with `kid`, `alg` and `use: "sig"`. `keys` is `createLocalJWKSet(jwks)`. `sign` uses the claims exactly as given; the header is `{alg, kid, typ: "JWT", ...header}`.
  - `export async function createTestIssuer(issuer: string, alg: "ES256" | "RS256" = "ES256"): Promise<TestIssuer>`
  - `export function testIdTokenClaims(issuer: string, input: { sub: string; email: string; nonce: string; nowSec?: number }): JWTPayload` returns `{iss, aud: TEST_IDP_AUDIENCE, sub, email, email_verified: true, nonce, iat: nowSec, exp: nowSec + 600}`.
- Produces, in `relay/test/fake-idp.ts`:
  - `export const GOOGLE_AUD = "1234-desktop.apps.googleusercontent.com"`, `export const APPLE_AUD = "com.shellx.dev"`, `export const TEST_ISSUER = "https://test-idp.shellx.invalid"`
  - `export interface FakeIssuer { readonly issuer: string; readonly keys: JWTVerifyGetKey; sign(claims: JWTPayload, header?: Partial<JWTHeaderParameters>): Promise<string>; jwks(): Promise<JSONWebKeySet> }`
  - `export function fakeIssuer(issuer: string, alg: "ES256" | "RS256"): FakeIssuer`. It calls `createTestIssuer` once, on first use (lazily, so files that never sign pay no key generation).
  - `export const fakeGoogle` (`https://accounts.google.com`, RS256), `export const fakeApple` (`APPLE_ISSUER`, RS256), `export const fakeTestIdp` (`TEST_ISSUER`, ES256)
  - `export interface ClaimInput { nonce: string; sub?: string; email?: string; nowSec?: number; extra?: Record<string, unknown> }`
  - `export function googleClaims(input: ClaimInput): JWTPayload`: `{iss: "https://accounts.google.com", aud: GOOGLE_AUD, sub (default "g-" + randomUUID()), email (default "g-" + randomUUID() + "@example.com"), email_verified: true, nonce, iat: nowSec (default now), exp: nowSec + 3600, ...extra}`
  - `export function appleClaims(input: ClaimInput & { isPrivateEmail?: boolean }): JWTPayload`: `{iss: APPLE_ISSUER, aud: APPLE_AUD, sub (default "a-…"), email (default "a-…@example.com"), email_verified: "true", is_private_email: "true" | "false", nonce: sha256Hex(nonce), iat, exp: iat + 600, ...extra}`
  - `export function testClaims(input: ClaimInput): JWTPayload` (`testIdTokenClaims(TEST_ISSUER, …)` plus `extra`)
  - `export function testIdTokens(): IdTokenVerifier`. Its options: `googleClientIds: [GOOGLE_AUD]`, `appleClientIds: [...DEFAULT_APPLE_CLIENT_IDS]`, `testIdp: { issuer: TEST_ISSUER, keys: fakeTestIdp.keys }`, `googleKeys: fakeGoogle.keys`, `appleKeys: fakeApple.keys`.

- [ ] **Step 1: Add the dependency**

Run: `(cd relay && npm install --save-exact jose@6.2.13)`
Expected: `relay/package.json` `dependencies` gains `"jose": "6.2.13"`, and `relay/package-lock.json` changes.

- [ ] **Step 2: Write the failing test**

`relay/test/id-token.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { createIdTokenVerifier, loadIdTokenVerifier, sha256Hex } from "../src/auth/id-token.js";
import { createTestIssuer, testIdTokenClaims } from "../scripts/test-idp.js";
import { appleClaims, fakeApple, fakeGoogle, fakeTestIdp, GOOGLE_AUD, googleClaims, TEST_ISSUER, testIdTokens } from "./fake-idp.js";

const NOW = 1_800_000_000_000;
const nowSec = NOW / 1000;
const NONCE = "n".repeat(43);
const verifier = testIdTokens();
const signIn = { providers: ["google", "test"] as const, nonce: NONCE, maxAgeSec: 600, nowMs: NOW };
const google = async (extra: Record<string, unknown> = {}) =>
  fakeGoogle.sign(googleClaims({ nonce: NONCE, nowSec, sub: "g-1", email: " Ann.Lee@Gmail.com ", extra }));

describe("Google ID tokens", () => {
  it("accept a valid token (either issuer spelling) and normalize the email", async () => {
    expect(await verifier.verify(await google(), signIn)).toEqual({
      provider: "google", subject: "g-1", email: "ann.lee@gmail.com", isPrivateEmail: false, audience: GOOGLE_AUD,
    });
    expect(await verifier.verify(await google({ iss: "accounts.google.com" }), signIn)).toMatchObject({ provider: "google" });
  });

  it.each([
    ["an unknown audience", { aud: "someone-else.apps.googleusercontent.com" }], ["another issuer", { iss: "https://evil.example" }],
    ["an expired token", { exp: nowSec - 61 }], ["an iat older than 600 s", { iat: nowSec - 601 }],
    ["an iat over 60 s ahead", { iat: nowSec + 61 }], ["an unverified email", { email_verified: false }],
    ["email_verified as a string", { email_verified: "true" }], ["no email", { email: undefined }],
    ["another nonce", { nonce: "m".repeat(43) }], ["the Apple form of the nonce", { nonce: sha256Hex(NONCE) }],
    ["no sub", { sub: undefined }],
  ])("refuse %s", async (_, extra) => {
    expect(await verifier.verify(await google(extra), signIn)).toBeNull();
  });

  it("use the age limit asked for: 600 s and 60 s ahead pass, 300 s for re-authentication", async () => {
    expect(await verifier.verify(await google({ iat: nowSec - 600 }), signIn)).not.toBeNull();
    expect(await verifier.verify(await google({ iat: nowSec + 60 }), signIn)).not.toBeNull();
    expect(await verifier.verify(await google({ iat: nowSec - 300 }), { ...signIn, maxAgeSec: 300 })).not.toBeNull();
    expect(await verifier.verify(await google({ iat: nowSec - 301 }), { ...signIn, maxAgeSec: 300 })).toBeNull();
  });

  it("refuse a forged key under the real kid, alg none, a non-string, an oversized token and a provider not asked for", async () => {
    const kid = (await fakeGoogle.jwks()).keys[0]!.kid;
    const impostor = await createTestIssuer("https://accounts.google.com", "RS256");
    const forged = await impostor.sign(googleClaims({ nonce: NONCE, nowSec }), { kid });
    expect(await verifier.verify(forged, signIn)).toBeNull();
    const b64 = (v: unknown) => Buffer.from(JSON.stringify(v)).toString("base64url");
    expect(await verifier.verify(`${b64({ alg: "none" })}.${b64(googleClaims({ nonce: NONCE, nowSec }))}.`, signIn)).toBeNull();
    expect(await verifier.verify(42, signIn)).toBeNull();
    expect(await verifier.verify("x".repeat(8193), signIn)).toBeNull();
    expect(await verifier.verify(await google(), { ...signIn, providers: ["apple"] as const })).toBeNull();
  });

  it("refuse every Google token while GOOGLE_CLIENT_IDS is empty", async () => {
    const none = createIdTokenVerifier({ googleClientIds: [], appleClientIds: [], testIdp: null, googleKeys: fakeGoogle.keys });
    expect(await none.verify(await google(), signIn)).toBeNull();
  });
});

describe("Apple identity tokens", () => {
  const options = { ...signIn, providers: ["apple"] as const };
  const apple = async (extra: Record<string, unknown> = {}) =>
    fakeApple.sign(appleClaims({ nonce: NONCE, nowSec, sub: "a-1", email: "h1@privaterelay.appleid.com", isPrivateEmail: true, extra }));

  it("accept sha256_hex(nonce) and email_verified true or \"true\", and report a private email", async () => {
    expect(await verifier.verify(await apple(), options)).toEqual({
      provider: "apple", subject: "a-1", email: "h1@privaterelay.appleid.com", isPrivateEmail: true, audience: "com.shellx.dev",
    });
    expect(await verifier.verify(await apple({ email_verified: true, is_private_email: false }), options)).toMatchObject({ isPrivateEmail: false });
  });

  it.each([["the raw nonce", { nonce: NONCE }], ["an unverified email", { email_verified: "false" }], ["another bundle id", { aud: "com.example.other" }]])(
    "refuse %s", async (_, extra) => {
      expect(await verifier.verify(await apple(extra), options)).toBeNull();
    },
  );
});

describe("test identity provider", () => {
  it("is accepted only when configured, for aud shellx-test-idp only", async () => {
    const claims = testIdTokenClaims(TEST_ISSUER, { sub: "t-1", email: "e2e@example.com", nonce: NONCE, nowSec });
    expect(await verifier.verify(await fakeTestIdp.sign(claims), signIn)).toMatchObject({ provider: "test", subject: "t-1" });
    expect(await verifier.verify(await fakeTestIdp.sign({ ...claims, aud: GOOGLE_AUD }), signIn)).toBeNull();
    const noTest = createIdTokenVerifier({ googleClientIds: [GOOGLE_AUD], appleClientIds: [], testIdp: null, googleKeys: fakeGoogle.keys });
    expect(await noTest.verify(await fakeTestIdp.sign(claims), signIn)).toBeNull();
  });

  it("reads TEST_IDP_JWKS_PATH and refuses an unreadable or malformed file", async () => {
    const idp = await createTestIssuer("https://t.invalid");
    const files: Record<string, string> = { "/ok.json": JSON.stringify(idp.jwks), "/bad.json": '{"keys": 3}' };
    const read = (path: string) => {
      const text = files[path];
      if (text === undefined) throw Object.assign(new Error("no such file"), { code: "ENOENT" });
      return text;
    };
    const config = (jwksPath: string) => ({ googleClientIds: [], appleClientIds: [], testIdp: { issuer: "https://t.invalid", jwksPath } });
    const loaded = loadIdTokenVerifier(config("/ok.json"), read);
    const token = await idp.sign(testIdTokenClaims("https://t.invalid", { sub: "s", email: "e@example.com", nonce: NONCE, nowSec }));
    expect(await loaded.verify(token, signIn)).toMatchObject({ provider: "test" });
    for (const path of ["/missing.json", "/bad.json"]) {
      expect(() => loadIdTokenVerifier(config(path), read)).toThrow("TEST_IDP_JWKS_PATH is not a readable JWKS file");
    }
  });

  it("sha256Hex is lower-case hex", () => {
    expect(sha256Hex("abc")).toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  });
});
```

- [ ] **Step 3: Run it to see it fail**

Run: `(cd relay && npx vitest run test/id-token.test.ts)`
Expected: FAIL. The import of `../src/auth/id-token.js` cannot be resolved (the file does not exist yet).

- [ ] **Step 4: Implement the three files**

`createIdTokenVerifier(options).verify(token, { providers, nonce, maxAgeSec, nowMs })` follows this order. Any failure logs `id_token_rejected` with `{provider: <name or "unknown">, reason}` and returns null.

1. `token` must be a string of at most `MAX_ID_TOKEN_CHARS` characters, else reason `malformed`.
2. Read `iss` with jose `decodeJwt` (throws → `malformed`). Map it to a provider:
   - in `GOOGLE_ISSUERS` → `google`;
   - `APPLE_ISSUER` → `apple`;
   - `options.testIdp?.issuer` → `test`;
   - anything else → reason `issuer`.

   A provider that is not in `providers` → reason `provider`.
3. Allowed audiences: Google → `googleClientIds`; Apple → `appleClientIds`; test → `[TEST_IDP_AUDIENCE]`. An empty list → reason `audience`.
4. Call `jwtVerify(token, <that provider's keys>, { issuer: <its issuer list>, audience, algorithms, clockTolerance: CLOCK_TOLERANCE_SEC, currentDate: new Date(nowMs), requiredClaims: ["sub", "iat", "exp", "nonce", "email"] })`.
   - `algorithms` is `["RS256"]` for Google and Apple, and `["ES256", "RS256"]` for test.
   - Do not use jose's `maxTokenAge`: it adds the tolerance to the age.
   - A throw gives reason `errorKind(err)` (jose codes such as `ERR_JWT_EXPIRED`).
5. Check the `iat` window yourself: `nowSec - iat <= maxAgeSec` and `iat - nowSec <= CLOCK_TOLERANCE_SEC`, else reason `iat`.
6. `sub` must be a non-empty string. The `nonce` claim must equal `nonce` (Google, test) or `sha256Hex(nonce)` (Apple), else reason `nonce`.
7. `email_verified`: Google and test need `=== true`; Apple needs `=== true` or `=== "true"`. `normalizeEmail(email)` must be non-empty. Otherwise reason `email`.
8. `isPrivateEmail` is Apple only: true when `is_private_email` is `true` or `"true"`. `audience` is `aud` when it is a string, else its first entry that is in the allowed list.

`loadIdTokenVerifier` reads and parses the JWKS file only when `config.testIdp` is set, then calls `createIdTokenVerifier` with the remote defaults for Google and Apple.

`scripts/test-idp.ts`:
- Use jose `generateKeyPair(alg)` and `exportJWK(publicKey)`.
- `kid` is `crypto.randomUUID()`.
- Sign with `new SignJWT(claims).setProtectedHeader(...)`.

`test/fake-idp.ts` exactly as in the Interfaces block.

- [ ] **Step 5: Run the tests to see them pass**

Run: `(cd relay && npx vitest run test/id-token.test.ts)`, then `(cd relay && npm test && npm run typecheck)`.
Expected: `Test Files  1 passed (1)`; the full suite has no failed file; no `error TS` line.

- [ ] **Step 6: Commit**

```bash
git add relay/package.json relay/package-lock.json relay/src/auth/id-token.ts relay/scripts/test-idp.ts relay/test/fake-idp.ts relay/test/id-token.test.ts
git commit -m "feat(relay): verify Google, Apple and test-provider ID tokens with jose 6.2.13"
```

---

### Task 4: One-time nonces

**Files:**
- Create: `relay/src/auth/nonces.ts`, `relay/src/routes/sign-in.ts`
- Modify: `relay/src/app.ts:120` (add `app.route("/v1/auth", signInRoutes);` on the line after `app.route("/v1/auth", authRoutes);`)
- Modify: `relay/src/auth/rate-limit.ts` (lines 8-24, 26-42, 111-126)
- Modify: `relay/test/helpers.ts` (`unlimited`, new `newNonce`)
- Test: `relay/test/nonce.test.ts` (new), `relay/test/limiter.test.ts`, `relay/test/limits.test.ts:72-78`

**Interfaces:**
- Produces, in `relay/src/auth/nonces.ts`:
  - `export const NONCE_TTL_MS = 600_000`, `export const MAX_LIVE_NONCES = 50_000`
  - `export async function issueNonce(db: Db, nowMs: number): Promise<string>`
  - `export async function consumeNonce(db: Db, nonce: unknown, nowMs: number): Promise<boolean>`. True once for a live nonce, false for anything else.
- Produces `export const signInRoutes = new Hono<AppEnv>()` in `relay/src/routes/sign-in.ts`. Tasks 5, 6 and 8 add routes to it.
- Produces `RateLimiters.nonceIp` and `export const NONCES_PER_IP = 30`.
- Produces `export async function newNonce(app: TestApp, ip?: string): Promise<string>` in helpers (POST, throws unless 201).

- [ ] **Step 1: Write the failing tests**

`relay/test/nonce.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { consumeNonce, MAX_LIVE_NONCES } from "../src/auth/nonces.js";
import { createRateLimiters } from "../src/auth/rate-limit.js";
import { hashToken } from "../src/auth/tokens.js";
import { call, CountingLimiter, db, errorCode, makeApp, newNonce, unlimited } from "./helpers.js";

const T0 = 1_800_000_000_000;
const ask = (app: ReturnType<typeof makeApp>, ip?: string) => call(app, "POST", "/v1/auth/nonce", { ip, body: {} });

describe("POST /v1/auth/nonce", () => {
  it("answers 201 with a 43-character base64url nonce for 600 s and stores only its SHA-256", async () => {
    const app = makeApp({ now: () => T0 });
    const res = await ask(app);
    expect(res.status).toBe(201);
    const body = await res.json<{ nonce: string; expires_in: number }>();
    expect(body).toEqual({ nonce: expect.stringMatching(/^[A-Za-z0-9_-]{43}$/), expires_in: 600 });
    expect(db().get("SELECT expires_at FROM auth_nonces WHERE nonce_hash = ?", await hashToken(body.nonce))).toEqual({ expires_at: T0 + 600_000 });
    expect(db().get("SELECT COUNT(*) AS n FROM auth_nonces WHERE nonce_hash = ?", Buffer.from(body.nonce))).toEqual({ n: 0 });
  });

  it("is used at most once and never at or after its expiry", async () => {
    const app = makeApp({ now: () => T0 });
    const once = await newNonce(app);
    expect(await consumeNonce(db(), once, T0 + 1)).toBe(true);
    expect(await consumeNonce(db(), once, T0 + 2)).toBe(false);
    expect(await consumeNonce(db(), await newNonce(app), T0 + 600_000)).toBe(false);
    expect(await consumeNonce(db(), "n".repeat(43), T0)).toBe(false);
    expect(await consumeNonce(db(), 42, T0)).toBe(false);
  });

  it("deletes expired nonces when the next one is issued, and answers 429 while 50 000 are live", async () => {
    let now = T0;
    const app = makeApp({ now: () => now });
    expect(MAX_LIVE_NONCES).toBe(50_000);
    db().run(`WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 50000)
              INSERT INTO auth_nonces (nonce_hash, expires_at) SELECT randomblob(32), ? FROM n`, T0 + 600_000);
    const full = await ask(app);
    expect([full.status, await errorCode(full)]).toEqual([429, "rate_limited"]);
    now += 600_000;
    expect((await ask(app)).status).toBe(201);
    expect(db().get("SELECT COUNT(*) AS n FROM auth_nonces")).toEqual({ n: 1 });
  });

  it("is limited per X-Real-IP: 30 per minute in production, nothing with RATE_LIMITS_ENABLED=false", async () => {
    const nonceIp = new CountingLimiter(2);
    const counted = makeApp({ limiters: { ...unlimited, nonceIp } });
    for (const status of [201, 201, 429]) expect((await ask(counted, "198.51.100.9")).status).toBe(status);
    expect(nonceIp.calls).toEqual(Array(3).fill("198.51.100.9"));
    const production = makeApp({ limiters: createRateLimiters({ rateLimitsEnabled: true }) });
    for (let i = 0; i < 30; i++) expect((await ask(production, "198.51.100.10")).status).toBe(201);
    expect((await ask(production, "198.51.100.10")).status).toBe(429);
    expect((await ask(production, "198.51.100.11")).status).toBe(201);
    const off = makeApp({ limiters: createRateLimiters({ rateLimitsEnabled: false }) });
    for (let i = 0; i < 40; i++) expect((await ask(off, "198.51.100.12")).status).toBe(201);
  });
});
```

In `relay/test/limiter.test.ts`:
- Import `NONCES_PER_IP`.
- Add a test `"limits POST /v1/auth/nonce to 30 per IP per 60 s"` in the style of the upgrade test at lines 89-98: 30 `true`, then `false`, another IP `true`, and after `t.advance(RATE_WINDOW_MS)` `true` again.
- Add `expect(await limiters.nonceIp.limit("k")).toBe(true);` inside the loop of `"RATE_LIMITS_ENABLED=false turns every limiter off"`.

In `relay/test/limits.test.ts`, append to `routes`: `["POST /v1/auth/nonce", { method: "POST", path: () => "/v1/auth/nonce", token: "none" }]`.

- [ ] **Step 2: Run them to see them fail**

Run: `(cd relay && npx vitest run test/nonce.test.ts test/limiter.test.ts test/limits.test.ts)`
Expected: FAIL. `../src/auth/nonces.js` cannot be resolved, `NONCES_PER_IP` is not exported, and `POST /v1/auth/nonce` answers 404.

- [ ] **Step 3: Implement**

`issueNonce`:
1. `nonce = generateToken()`; hash it with `await hashToken(nonce)`.
2. Then, synchronously: `DELETE FROM auth_nonces WHERE expires_at <= ?` (now).
3. If `SELECT COUNT(*) FROM auth_nonces` ≥ `MAX_LIVE_NONCES`, throw `Errors.rateLimited()`.
4. Insert `(hash, now + NONCE_TTL_MS)` and return the nonce.

`consumeNonce`:
- Anything that is not a string matching `/^[A-Za-z0-9_-]{43}$/` → false.
- Otherwise run `DELETE FROM auth_nonces WHERE nonce_hash = ? AND expires_at > ?`; the result is `changes === 1`.

Route `signInRoutes.post("/nonce", jsonBodyLimit, …)`:
- `nonceIp.limit(requestIp(c))` → otherwise 429.
- The body is not read.
- Answer `c.json({ nonce, expires_in: NONCE_TTL_MS / 1000 }, 201)`.

`rate-limit.ts`:
- Add the field `nonceIp`, doc-commented "POST /v1/auth/nonce, keyed by client IP".
- Add `NONCES_PER_IP = 30`.
- Wire it in both branches of `createRateLimiters`.

`helpers.ts`: add `nonceIp: allowAll` to `unlimited`, and `newNonce`.

- [ ] **Step 4: Run the tests to see them pass**

Run: `(cd relay && npx vitest run test/nonce.test.ts test/limiter.test.ts test/limits.test.ts)`, then `(cd relay && npm test && npm run typecheck)`.
Expected: `Test Files  3 passed (3)`; the full suite has no failed file; no `error TS` line.

- [ ] **Step 5: Commit**

```bash
git add relay/src/auth/nonces.ts relay/src/routes/sign-in.ts relay/src/app.ts relay/src/auth/rate-limit.ts relay/test/helpers.ts relay/test/nonce.test.ts relay/test/limiter.test.ts relay/test/limits.test.ts
git commit -m "feat(relay): one-time sign-in nonces (POST /v1/auth/nonce)"
```

---

### Task 5: Google sign-in and the account-resolution rules

**Files:**
- Create: `relay/src/auth/identity.ts`
- Modify: `relay/src/auth/session.ts:22-24` (`insertToken`)
- Modify: `relay/src/routes/sign-in.ts` (add `POST /google`)
- Modify: `relay/src/app.ts:32-66` and `:93-105` (`idTokens` dependency)
- Modify: `relay/src/server.ts:22-27`, `:57-61` (load the verifier, startup logs)
- Modify: `relay/test/helpers.ts` (`makeApp` defaults to `idTokens: testIdTokens()`; Google helpers)
- Test: `relay/test/auth-google.test.ts` (new), `relay/test/server.test.ts`, `relay/test/limits.test.ts`

**Interfaces:**
- Consumes: Task 3's verifier and fakes; Task 4's nonces and `signInRoutes`; Task 2's schema and `seedUser`.
- Produces, in `relay/src/auth/session.ts`:
  - `export type AuthMethod = "password" | "google" | "apple" | "test";`
  - `export function insertToken(db: Db, tokenHash: ArrayBuffer, deviceId: string, now: number, authMethod: AuthMethod = "password", identityId: string | null = null): void`. Existing callers do not change.
- Produces, in `relay/src/auth/identity.ts`. All of these are synchronous and meant to run inside `db.transaction`:
  - `export type AccountMatch = { kind: "identity"; userId: string; identityId: string } | { kind: "email"; userId: string; hasPrimary: boolean } | { kind: "switch_required" } | { kind: "none" }`
  - `export function matchAccount(db: Db, token: VerifiedIdToken, passwordLogin: boolean): AccountMatch`. It applies S1 §6.3 steps 1 and 2:
    - an identity with this `(provider, subject)` → `identity`;
    - else a user whose `email` equals `token.email`: if `passwordLogin && password_hash !== null` → `switch_required`; else `email`, where `hasPrimary` is true when that user already has an identity with `provider != 'apple'`;
    - else `none`.
  - `export interface NewIdentity { provider: IdentityProvider; subject: string; email: string; isPrivateEmail: boolean; appleRefreshToken: string | null; appleClientId: string | null; linkedViaDeviceId: string | null }`
  - `export function identityFromToken(token: VerifiedIdToken): NewIdentity` (the three trailing fields are null)
  - `export function insertIdentity(db: Db, userId: string, identity: NewIdentity, now: number): string` (returns the new UUIDv4)
  - `export function dropPasswordAccess(db: Db, userId: string): number`. It sets `password_hash = NULL` and deletes the account's `auth_method = 'password'` tokens; it returns how many tokens it deleted.
  - `export function upsertDevice(db: Db, userId: string, device: DeviceInput, now: number): string`. This is the `/login` upsert: `ON CONFLICT (user_id, public_key) DO UPDATE SET name, platform … RETURNING id`.
  - `export function replaceDeviceToken(db: Db, deviceId: string, tokenHash: ArrayBuffer, authMethod: AuthMethod, identityId: string | null, now: number): void` (deletes the device's tokens, then `insertToken`)
  - `export function signInDevice(db: Db, userId: string, device: DeviceInput, tokenHash: ArrayBuffer, authMethod: AuthMethod, identityId: string | null, now: number): string` (`upsertDevice` + `replaceDeviceToken`; returns the device id)
  - `export function accountEmail(db: Db, userId: string): string`
- Produces in `relay/src/app.ts`: `AppDeps.idTokens?: IdTokenVerifier` (default `loadIdTokenVerifier(deps.config)`, built once per `createApp`) and `AppVariables.idTokens: IdTokenVerifier`.
- Produces, in `relay/test/helpers.ts`:
  - `export interface GoogleSignInOptions { idp?: "google" | "test"; sub?: string; email?: string; kind?: "desktop" | "mobile"; publicKey?: string; claims?: Record<string, unknown>; headers?: Record<string, string>; ip?: string }`
  - `export async function googleIdToken(app: TestApp, options?: GoogleSignInOptions): Promise<{ id_token: string; nonce: string }>`: a fresh nonce, plus a token from `fakeGoogle` (or `fakeTestIdp` when `idp: "test"`) with `iat` taken from the app's clock.
  - `export async function signInGoogle(app: TestApp, options?: GoogleSignInOptions): Promise<TestResponse>`: `googleIdToken`, then `POST /v1/auth/google` with `device: deviceBody(kind ?? "desktop", { public_key: publicKey })`, where `publicKey = options.publicKey ?? randomPublicKey()`. Defaults: `sub` is `"g-" + randomUUID()` and `email` is `randomEmail()`. Never pass `undefined` into `deviceBody` overrides, because that replaces its defaults.
  - `export interface GoogleSession extends Session { sub: string; email: string }`
  - `export async function googleSession(app: TestApp, options?: GoogleSignInOptions): Promise<GoogleSession>`. It throws unless 200. It returns the `sub` and `publicKey` it used; `email` is the response's `email`.

- [ ] **Step 1: Write the failing tests**

`relay/test/auth-google.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { hashToken } from "../src/auth/tokens.js";
import { fakeGoogle, googleClaims } from "./fake-idp.js";
import {
  call, CountingLimiter, db, deviceBody, errorCode, googleSession, loginDevice, makeApp, newNonce, randomEmail,
  registerAccount, seedUser, signInGoogle, TEST_CONFIG, unlimited,
} from "./helpers.js";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const devices = (app: ReturnType<typeof makeApp>, token: string) => call(app, "GET", "/v1/devices", { token });

describe("POST /v1/auth/google", () => {
  it("creates an account on the first sign-in: Google email, no password, one identity, a google token", async () => {
    const app = makeApp();
    const s = await googleSession(app, { email: "  New.User@Gmail.com " });
    expect(s.email).toBe("new.user@gmail.com");
    expect(db().get("SELECT email, password_hash FROM users WHERE id = ?", s.userId)).toEqual({ email: "new.user@gmail.com", password_hash: null });
    expect(db().all("SELECT provider, subject, email FROM identities WHERE user_id = ?", s.userId)).toEqual([{ provider: "google", subject: s.sub, email: "new.user@gmail.com" }]);
    const row = db().get<{ auth_method: string; identity_id: string }>("SELECT auth_method, identity_id FROM tokens WHERE token_hash = ?", await hashToken(s.token));
    expect(row?.auth_method).toBe("google");
    expect(row?.identity_id).toMatch(UUID_RE);
    expect((await devices(app, s.token)).status).toBe(200);
  });

  it("signs the same Google account in to the same account whatever its email says now; same key, same device", async () => {
    const app = makeApp();
    const first = await googleSession(app, { kind: "mobile" });
    const again = await googleSession(app, { sub: first.sub, email: randomEmail(), kind: "mobile", publicKey: first.publicKey });
    expect([again.userId, again.deviceId, again.email]).toEqual([first.userId, first.deviceId, first.email]);
    expect((await devices(app, first.token)).status).toBe(401);
    const desk = await googleSession(app, { sub: first.sub, kind: "desktop" });
    expect(desk.userId).toBe(first.userId);
    expect(desk.deviceId).not.toBe(first.deviceId);
  });

  it("answers 409 switch_from_signed_in_device for the email (any case) of an account that still has a password", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const res = await signInGoogle(app, { email: ` ${account.email.toUpperCase()}` });
    expect([res.status, await errorCode(res)]).toEqual([409, "switch_from_signed_in_device"]);
    expect(db().get("SELECT COUNT(*) AS n FROM identities")).toEqual({ n: 0 });
    const login = await call(app, "POST", "/v1/auth/login", { body: { email: account.email, password: account.password, device: deviceBody("mobile") } });
    expect(login.status).toBe(200);
  });

  it("links by email (any case) to an account without a password", async () => {
    const app = makeApp();
    const email = randomEmail();
    const userId = await seedUser(email, null);
    expect((await googleSession(app, { email: email.toUpperCase() })).userId).toBe(userId);
    expect(db().get("SELECT COUNT(*) AS n FROM identities WHERE user_id = ?", userId)).toEqual({ n: 1 });
  });

  it("with PASSWORD_LOGIN=off links by email to an account that still has a password, removes it and signs out its password sessions", async () => {
    const account = await registerAccount(makeApp());
    const phone = await loginDevice(makeApp(), account, "mobile");
    const app = makeApp({ config: { ...TEST_CONFIG, passwordLogin: false } });
    const s = await googleSession(app, { email: account.email });
    expect(s.userId).toBe(account.agent.userId);
    expect(db().get("SELECT password_hash FROM users WHERE id = ?", s.userId)).toEqual({ password_hash: null });
    for (const token of [account.agent.token, phone.token]) expect((await devices(app, token)).status).toBe(401);
    expect((await devices(app, s.token)).status).toBe(200);
  });

  it("refuses (401) a new Google account whose email is that of an account that already has a Google sign-in", async () => {
    const app = makeApp();
    const first = await googleSession(app);
    const res = await signInGoogle(app, { email: first.email });
    expect([res.status, await errorCode(res)]).toEqual([401, "invalid_credentials"]);
    expect(db().get("SELECT COUNT(*) AS n FROM identities")).toEqual({ n: 1 });
  });

  it("uses a nonce once, and only one the relay issued", async () => {
    const app = makeApp();
    const nonce = await newNonce(app);
    const body = { id_token: await fakeGoogle.sign(googleClaims({ nonce })), nonce, device: deviceBody("desktop") };
    expect((await call(app, "POST", "/v1/auth/google", { body })).status).toBe(200);
    const replay = await call(app, "POST", "/v1/auth/google", { body });
    expect([replay.status, await errorCode(replay)]).toEqual([401, "invalid_credentials"]);
    const forged = "f".repeat(43);
    const res = await call(app, "POST", "/v1/auth/google", { body: { id_token: await fakeGoogle.sign(googleClaims({ nonce: forged })), nonce: forged, device: deviceBody("desktop") } });
    expect(res.status).toBe(401);
  });

  it.each([
    ["an unknown audience", { aud: "someone-else.apps.googleusercontent.com" }],
    ["an unverified email", { email_verified: false }],
    ["an Apple issuer", { iss: "https://appleid.apple.com" }],
  ])("answers 401 invalid_credentials to %s", async (_, claims) => {
    const res = await signInGoogle(makeApp(), { claims });
    expect([res.status, await errorCode(res)]).toEqual([401, "invalid_credentials"]);
  });

  it("answers 400 invalid_device to an agent, a malformed or a missing device, and 400 bad_request to non-JSON", async () => {
    const app = makeApp();
    for (const device of [deviceBody("agent"), deviceBody("desktop", { platform: "ios" }), undefined]) {
      const res = await call(app, "POST", "/v1/auth/google", { body: { id_token: "x", nonce: await newNonce(app), device } });
      expect([res.status, await errorCode(res)]).toEqual([400, "invalid_device"]);
    }
    expect(await errorCode(await call(app, "POST", "/v1/auth/google", { body: "{oops" }))).toBe("bad_request");
  });

  it("is limited per IP by the login limiter", async () => {
    const loginIp = new CountingLimiter(1);
    const app = makeApp({ limiters: { ...unlimited, loginIp } });
    expect((await signInGoogle(app, { ip: "198.51.100.7" })).status).toBe(200);
    expect((await signInGoogle(app, { ip: "198.51.100.7" })).status).toBe(429);
    expect(loginIp.calls).toEqual(["198.51.100.7", "198.51.100.7"]);
  });

  it("accepts the test identity provider as provider test, auth_method test", async () => {
    const s = await googleSession(makeApp(), { idp: "test" });
    expect(db().get("SELECT provider FROM identities WHERE user_id = ?", s.userId)).toEqual({ provider: "test" });
    expect(db().get("SELECT auth_method FROM tokens WHERE device_id = ?", s.deviceId)).toEqual({ auth_method: "test" });
  });

  it("records X-ShellX-Version on the device", async () => {
    const s = await googleSession(makeApp(), { headers: { "X-ShellX-Version": "1.8.0" } });
    expect(db().get("SELECT app_version FROM devices WHERE id = ?", s.deviceId)).toEqual({ app_version: "1.8.0" });
  });
});
```

In `relay/test/server.test.ts`, add a describe. Import `createTestIssuer` and `testIdTokenClaims` from `../scripts/test-idp.js`, and `writeFileSync` (already imported).

```ts
describe("test identity provider (TEST_IDP_ISSUER, TEST_IDP_JWKS_PATH)", () => {
  it("signs in with a token of the configured test issuer and logs it; an unreadable JWKS file stops the relay", async () => {
    const issuer = "https://test-idp.shellx.invalid";
    const idp = await createTestIssuer(issuer);
    const jwksFile = join(tempDir(), "test-idp.json");
    writeFileSync(jwksFile, JSON.stringify(idp.jwks));
    const env = { ...VERSION_ENV, HOST: "127.0.0.1", PORT: "0", DB_PATH: join(tempDir(), "relay.db"), RATE_LIMITS_ENABLED: "false", TEST_IDP_ISSUER: issuer };
    const server = startServer({ ...env, TEST_IDP_JWKS_PATH: jwksFile });
    onCleanup(() => server.child.kill("SIGKILL"));
    const app = remote(await waitForListening(server.output));
    expect(server.output()).toContain('"event":"test_idp_enabled"');
    expect(server.output()).toContain('"event":"google_sign_in_disabled"');
    const { nonce } = await (await call(app, "POST", "/v1/auth/nonce", { body: {} })).json<{ nonce: string }>();
    const id_token = await idp.sign(testIdTokenClaims(issuer, { sub: "t-1", email: "e2e@example.com", nonce }));
    const res = await call(app, "POST", "/v1/auth/google", { body: { id_token, nonce, device: deviceBody("desktop") } });
    expect(res.status).toBe(200);
    expect(db().get("SELECT auth_method FROM tokens WHERE device_id = ?", (await res.json<{ device_id: string }>()).device_id)).toEqual({ auth_method: "test" });
    server.child.kill("SIGTERM");
    expect((await server.exit).code).toBe(0);

    const broken = await startServer({ ...env, TEST_IDP_JWKS_PATH: join(tempDir(), "missing.json") }).exit;
    expect([broken.code, broken.stderr]).toEqual([1, "relay: TEST_IDP_JWKS_PATH is not a readable JWKS file\n"]);
  });
});
```

In `relay/test/limits.test.ts`, append `["POST /v1/auth/google", { method: "POST", path: () => "/v1/auth/google", token: "none" }]`.

- [ ] **Step 2: Run them to see them fail**

Run: `(cd relay && npx vitest run test/auth-google.test.ts test/server.test.ts test/limits.test.ts)`
Expected: FAIL. `googleSession` is not exported and `/v1/auth/google` answers 404.

- [ ] **Step 3: Implement `identity.ts`, `insertToken` and the route**

`signInRoutes.post("/google", jsonBodyLimit, …)`, in order:
1. `loginIp.limit(requestIp(c))` → otherwise 429.
2. Read the body. `parseDevice(body.device)` is null or `kind === "agent"` → `Errors.invalidDevice()`.
3. `verified = await idTokens.verify(body.id_token, { providers: ["google", "test"], nonce: typeof body.nonce === "string" ? body.nonce : "", maxAgeSec: ID_TOKEN_MAX_AGE_SEC, nowMs: now })`. Null → `invalidCredentials`.
4. `await consumeNonce(db, body.nonce, now)` is false → log `sign_in_refused` `{provider, reason: "nonce"}`, then `invalidCredentials`.
5. `token = generateToken()`, `tokenHash = await hashToken(token)`.
6. `db.transaction`. Run `matchAccount(db, verified, config.passwordLogin)`, then:
   - `switch_required` → `Errors.switchFromSignedInDevice()`;
   - `email` with `hasPrimary` → log `sign_in_refused` `{provider, reason: "other_google_identity"}`, then `invalidCredentials`;
   - `identity` → update `last_used_at`;
   - `email` → `dropped = dropPasswordAccess(db, userId)`, then `insertIdentity(db, userId, identityFromToken(verified), now)`;
   - `none` → insert `users (id, email, NULL, now, now)`, then `insertIdentity`.

   Then `deviceId = signInDevice(db, userId, device, tokenHash, verified.provider, identityId, now)`.
7. After the commit: `recordAppVersion(db, deviceId, c.req.header(CLIENT_VERSION_HEADER))`; log `sign_in` `{device_id, provider, via: "identity" | "email" | "new_account"}`; when `dropped > 0`, also log `password_access_dropped` `{sessions: dropped}`.
8. Answer `200 {user_id, device_id, token, email: accountEmail(db, userId)}`.

`app.ts`:
- `const idTokens = deps.idTokens ?? loadIdTokenVerifier(deps.config);` before the middleware.
- `c.set("idTokens", idTokens)`.

`server.ts`:
- Right after `loadConfig`, call `loadIdTokenVerifier(config)` inside the same try/catch shape (`fail(err instanceof ConfigError ? err.message : "invalid configuration")`).
- Log `google_sign_in_disabled` when `config.googleClientIds.length === 0`, `test_idp_enabled` when `config.testIdp !== null`, and `password_login_off` when `!config.passwordLogin`.
- Pass `idTokens` to `startRelay`.

`helpers.ts`:
- `makeApp` passes `idTokens: testIdTokens()` ahead of `...deps`, so a test can override it.
- Add the Google helpers from the Interfaces block.

- [ ] **Step 4: Run the tests to see them pass**

Run: `(cd relay && npx vitest run test/auth-google.test.ts test/server.test.ts test/limits.test.ts)`, then `(cd relay && npm test && npm run typecheck)`.
Expected: `Test Files  3 passed (3)`; the full suite has no failed file; no `error TS` line.

- [ ] **Step 5: Commit**

```bash
git add relay/src/auth/identity.ts relay/src/auth/session.ts relay/src/routes/sign-in.ts relay/src/app.ts relay/src/server.ts relay/test/helpers.ts relay/test/auth-google.test.ts relay/test/server.test.ts relay/test/limits.test.ts
git commit -m "feat(relay): POST /v1/auth/google with the account-resolution rules of S1 §6.3"
```

---

### Task 6: Switch a password session to Google in place

**Files:**
- Modify: `relay/src/routes/sign-in.ts` (add `POST /google/link`)
- Test: `relay/test/auth-google-link.test.ts` (new), `relay/test/limits.test.ts`

**Interfaces:**
- Consumes: `identity.ts`, the verifier and `consumeNonce`; `googleIdToken` and `googleSession` from helpers (Task 5).
- Produces: `POST /v1/auth/google/link` (contracts §2).

- [ ] **Step 1: Write the failing test**

`relay/test/auth-google-link.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { hashToken } from "../src/auth/tokens.js";
import { call, db, deviceBody, errorCode, googleIdToken, googleSession, loginDevice, makeApp, registerAccount, type TestApp } from "./helpers.js";

const link = (app: TestApp, token: string | undefined, body: Record<string, unknown>) => call(app, "POST", "/v1/auth/google/link", { token, body });

describe("POST /v1/auth/google/link (S1 §6.3b)", () => {
  it("links Google to the signed-in account even with another email; only this device moves to a google token", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const phone = await loginDevice(app, account, "mobile");
    const sub = `g-${crypto.randomUUID()}`;
    const res = await link(app, account.agent.token, await googleIdToken(app, { sub, email: "Owner@Gmail.com" }));
    expect(res.status).toBe(200);
    const body = await res.json<{ user_id: string; device_id: string; token: string; email: string }>();
    expect(body).toMatchObject({ user_id: account.agent.userId, device_id: account.agent.deviceId, email: "owner@gmail.com" });
    expect(db().get("SELECT email, password_hash IS NOT NULL AS has_password FROM users WHERE id = ?", account.agent.userId)).toEqual({ email: "owner@gmail.com", has_password: 1 });
    expect(db().get("SELECT auth_method FROM tokens WHERE token_hash = ?", await hashToken(body.token))).toEqual({ auth_method: "google" });
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(401);
    expect((await call(app, "GET", "/v1/devices", { token: phone.token })).status).toBe(200);
    const login = await call(app, "POST", "/v1/auth/login", { body: { email: "owner@gmail.com", password: account.password, device: deviceBody("mobile") } });
    expect(login.status).toBe(200);
    expect((await googleSession(app, { sub, kind: "mobile" })).userId).toBe(account.agent.userId);
  });

  it("answers 409 email_in_use when another account has that email, changing nothing", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const other = await registerAccount(app);
    const res = await link(app, account.agent.token, await googleIdToken(app, { email: other.email }));
    expect([res.status, await errorCode(res)]).toEqual([409, "email_in_use"]);
    expect(db().get("SELECT COUNT(*) AS n FROM identities")).toEqual({ n: 0 });
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(200);
  });

  it("answers 409 identity_in_use for a Google account of another account, or a second Google account for this one", async () => {
    const app = makeApp();
    const taken = await googleSession(app);
    const account = await registerAccount(app);
    const desk = await loginDevice(app, account, "desktop");
    const res = await link(app, account.agent.token, await googleIdToken(app, { sub: taken.sub, email: taken.email }));
    expect([res.status, await errorCode(res)]).toEqual([409, "identity_in_use"]);
    expect((await link(app, account.agent.token, await googleIdToken(app, { sub: "g-first" }))).status).toBe(200);
    const second = await link(app, desk.token, await googleIdToken(app, { sub: "g-second" }));
    expect([second.status, await errorCode(second)]).toEqual([409, "identity_in_use"]);
    const again = await link(app, desk.token, await googleIdToken(app, { sub: "g-first" }));
    expect(again.status).toBe(200);
    expect(db().get("SELECT COUNT(*) AS n FROM identities WHERE user_id = ?", account.agent.userId)).toEqual({ n: 1 });
  });

  it("needs a bearer token, a valid ID token and an unused nonce", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const fresh = await loginDevice(app, account, "mobile"); // before the link below changes the account's email
    expect(await errorCode(await link(app, undefined, await googleIdToken(app)))).toBe("unauthorized");
    const bad = await link(app, account.agent.token, { ...(await googleIdToken(app)), id_token: "not-a-jwt" });
    expect([bad.status, await errorCode(bad)]).toEqual([401, "invalid_credentials"]);
    const used = await googleIdToken(app);
    expect((await link(app, account.agent.token, used)).status).toBe(200);
    expect((await link(app, fresh.token, used)).status).toBe(401);
  });
});
```

In `relay/test/limits.test.ts`, append `["POST /v1/auth/google/link", { method: "POST", path: () => "/v1/auth/google/link", token: "agent" }]`.

- [ ] **Step 2: Run it to see it fail**

Run: `(cd relay && npx vitest run test/auth-google-link.test.ts test/limits.test.ts)`
Expected: FAIL, because `/v1/auth/google/link` answers 404.

- [ ] **Step 3: Implement `signInRoutes.post("/google/link", requireAuth, jsonBodyLimit, …)`**

1. Verify the token as in Task 5 step 3 (Google and test providers, 600 s), then consume the nonce. A failure → `invalidCredentials`.
2. Precompute the token and its hash.
3. In a transaction:
   - `existing` = the identity with `(provider, subject)`. If it belongs to another user → `Errors.identityInUse()`.
   - With no `existing`, the account already has an identity with `provider != 'apple'` → `identityInUse`.
   - With no `existing`: when `verified.email` differs from the account's email, another user holding that email → `Errors.emailInUse()`; otherwise `UPDATE users SET email`. Then `insertIdentity`.
   - `existing` of this account → only `last_used_at` changes.
   - Finally `replaceDeviceToken(db, auth.deviceId, tokenHash, verified.provider, identityId, now)`. The old token goes, and other devices and the password do not change.
4. Log `google_linked` `{device_id}`, then answer `200 {user_id, device_id, token, email}`.

No rate limiter: contracts §2 lists no 429 for this route.

- [ ] **Step 4: Run the tests to see them pass**

Run: `(cd relay && npx vitest run test/auth-google-link.test.ts test/limits.test.ts)`, then `(cd relay && npm test && npm run typecheck)`.
Expected: `Test Files  2 passed (2)`; the full suite has no failed file; no `error TS` line.

- [ ] **Step 5: Commit**

```bash
git add relay/src/routes/sign-in.ts relay/test/auth-google-link.test.ts relay/test/limits.test.ts
git commit -m "feat(relay): switch a signed-in password session to Google in place (POST /v1/auth/google/link)"
```

---

### Task 7: Sign in with Apple REST client

**Files:**
- Create: `relay/src/auth/apple-rest.ts`
- Modify: `relay/src/app.ts` (`appleTokens` dependency), `relay/src/server.ts:41-45` (load it next to APNs)
- Modify: `relay/test/fake-idp.ts` (add `FakeAppleTokens`)
- Test: `relay/test/apple-rest.test.ts` (new)

**Interfaces:**
- Produces, in `relay/src/auth/apple-rest.ts`:
  - `export const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token"`, `export const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke"`
  - `export const APPLE_REST_TIMEOUT_MS = 5000`, `export const APPLE_CLIENT_SECRET_TTL_SEC = 300`
  - `export interface AppleSiwaKey { teamId: string; keyId: string; privateKeyPem: string }`
  - `export interface AppleTokenGateway { exchangeCode(clientId: string, code: string): Promise<string | null>; revoke(clientId: string, refreshToken: string): Promise<boolean> }`. Neither method ever throws.
  - `export function appleClientSecret(key: AppleSiwaKey, clientId: string, nowMs: number): Promise<string>`
  - `export class AppleRestClient implements AppleTokenGateway { constructor(options: { key: AppleSiwaKey; fetch?: typeof fetch; now?: () => number }) }`. The constructor throws unless the key is an EC P-256 private key.
  - `export type AppleSiwaSetup = { gateway: AppleTokenGateway } | { gateway: null; reason: "not_configured" | "unreadable" | "invalid" }`
  - `export function loadAppleSiwa(env: Readonly<Record<string, string | undefined>>, options?: { readFile?: (path: string) => string; fetch?: typeof fetch }): AppleSiwaSetup`
  - `export async function revokeAppleTokens(gateway: AppleTokenGateway | null, rows: readonly { apple_client_id: string | null; apple_refresh_token: string | null }[]): Promise<void>`
- Produces: `AppDeps.appleTokens?: AppleTokenGateway | null`, `AppVariables.appleTokens: AppleTokenGateway | null` (default null).
- Produces, in `relay/test/fake-idp.ts`, `export class FakeAppleTokens implements AppleTokenGateway` with these members:
  - `readonly exchanges: { clientId: string; code: string }[]`
  - `readonly revokes: { clientId: string; refreshToken: string }[]`
  - `refreshToken: string | null = "apple-refresh-token-1"`
  - `revokeOk = true`

  It records every call and answers the configured values.

- [ ] **Step 1: Write the failing test**

`relay/test/apple-rest.test.ts`:

```ts
import { createPublicKey, generateKeyPairSync } from "node:crypto";
import { jwtVerify } from "jose";
import { afterEach, describe, expect, it, vi } from "vitest";
import { appleClientSecret, AppleRestClient, loadAppleSiwa, revokeAppleTokens } from "../src/auth/apple-rest.js";
import { FakeAppleTokens } from "./fake-idp.js";

const pem = { privateKeyEncoding: { type: "pkcs8", format: "pem" }, publicKeyEncoding: { type: "spki", format: "pem" } } as const;
const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1", ...pem });
const KEY = { teamId: "W4RF3W4VTZ", keyId: "ABC123DEFG", privateKeyPem: privateKey };
const NOW = 1_800_000_000_000;
afterEach(() => vi.restoreAllMocks());

function captureLog(): () => string {
  const lines: string[] = [];
  vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => void lines.push(args.map(String).join(" ")));
  return () => lines.join("\n");
}

function fakeFetch(answers: { status: number; body: string }[] | Error) {
  const calls: { url: string; form: URLSearchParams; contentType: string | null }[] = [];
  const fn = (async (url: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(url), form: new URLSearchParams(String(init?.body)), contentType: new Headers(init?.headers).get("content-type") });
    if (answers instanceof Error) throw answers;
    const answer = answers.shift()!;
    return new Response(answer.body, { status: answer.status });
  }) as typeof fetch;
  return { fn, calls };
}

describe("Apple REST", () => {
  it("signs the client secret as ES256 with the key id: iss team, sub bundle id, aud appleid, 300 s", async () => {
    const { payload, protectedHeader } = await jwtVerify(await appleClientSecret(KEY, "com.shellx.dev", NOW), createPublicKey(publicKey), { currentDate: new Date(NOW) });
    expect(protectedHeader).toMatchObject({ alg: "ES256", kid: "ABC123DEFG" });
    expect(payload).toEqual({ iss: "W4RF3W4VTZ", sub: "com.shellx.dev", aud: "https://appleid.apple.com", iat: 1_800_000_000, exp: 1_800_000_300 });
  });

  it("exchanges an authorization code for the refresh token", async () => {
    const f = fakeFetch([{ status: 200, body: JSON.stringify({ access_token: "a", refresh_token: "r-1", id_token: "i", token_type: "Bearer", expires_in: 3600 }) }]);
    expect(await new AppleRestClient({ key: KEY, fetch: f.fn, now: () => NOW }).exchangeCode("com.shellx.dev", "code-1")).toBe("r-1");
    expect([f.calls[0]!.url, f.calls[0]!.contentType]).toEqual(["https://appleid.apple.com/auth/token", "application/x-www-form-urlencoded"]);
    expect(Object.fromEntries(f.calls[0]!.form)).toMatchObject({ client_id: "com.shellx.dev", code: "code-1", grant_type: "authorization_code" });
    await expect(jwtVerify(f.calls[0]!.form.get("client_secret")!, createPublicKey(publicKey), { currentDate: new Date(NOW) })).resolves.toBeDefined();
  });

  it.each([
    ["a 400 answer", [{ status: 400, body: '{"error":"invalid_grant"}' }]],
    ["a 200 without refresh_token", [{ status: 200, body: "{}" }]],
    ["no answer", new Error("ECONNRESET")],
  ] as const)("answers null to %s and logs metadata only", async (_, answers) => {
    const log = captureLog();
    const client = new AppleRestClient({ key: KEY, fetch: fakeFetch(Array.isArray(answers) ? [...answers] : answers).fn, now: () => NOW });
    expect(await client.exchangeCode("com.shellx.dev", "secret-code")).toBeNull();
    expect(log()).toContain("apple_token_exchange_failed");
    expect(log()).not.toContain("secret-code");
  });

  it("revokes a refresh token: true on 200, false otherwise, never logging the token", async () => {
    const ok = fakeFetch([{ status: 200, body: "" }]);
    expect(await new AppleRestClient({ key: KEY, fetch: ok.fn, now: () => NOW }).revoke("com.shellx.prod", "r-9")).toBe(true);
    expect(ok.calls[0]!.url).toBe("https://appleid.apple.com/auth/revoke");
    expect(Object.fromEntries(ok.calls[0]!.form)).toMatchObject({ client_id: "com.shellx.prod", token: "r-9", token_type_hint: "refresh_token" });
    const log = captureLog();
    expect(await new AppleRestClient({ key: KEY, fetch: fakeFetch([{ status: 400, body: "{}" }]).fn }).revoke("com.shellx.prod", "r-9")).toBe(false);
    expect(log()).toContain("apple_revoke_failed");
    expect(log()).not.toContain("r-9");
  });

  it("revokeAppleTokens revokes each stored token and logs what it skipped", async () => {
    const log = captureLog();
    const fake = new FakeAppleTokens();
    await revokeAppleTokens(fake, [{ apple_client_id: "com.shellx.dev", apple_refresh_token: "r-1" }, { apple_client_id: null, apple_refresh_token: null }]);
    expect(fake.revokes).toEqual([{ clientId: "com.shellx.dev", refreshToken: "r-1" }]);
    await revokeAppleTokens(null, [{ apple_client_id: "com.shellx.dev", apple_refresh_token: "r-2" }]);
    expect(log()).toContain('"event":"apple_revoke_skipped","reason":"no_refresh_token"');
    expect(log()).toContain('"event":"apple_revoke_skipped","reason":"not_configured"');
    expect(log()).not.toContain("r-2");
  });

  it("loadAppleSiwa: off without all three variables, unreadable or not a P-256 key; on with one", () => {
    const env = { APPLE_TEAM_ID: "W4RF3W4VTZ", APPLE_SIWA_KEY_ID: "ABC123DEFG", APPLE_SIWA_KEY_PATH: "/secrets/siwa.p8" };
    const file = (text: string) => ({ readFile: () => text });
    expect(loadAppleSiwa({ ...env, APPLE_TEAM_ID: " " })).toEqual({ gateway: null, reason: "not_configured" });
    expect(loadAppleSiwa(env, { readFile: () => { throw new Error("ENOENT"); } })).toEqual({ gateway: null, reason: "unreadable" });
    expect(loadAppleSiwa(env, file("not a key"))).toEqual({ gateway: null, reason: "invalid" });
    expect(loadAppleSiwa(env, file(generateKeyPairSync("rsa", { modulusLength: 2048, ...pem }).privateKey))).toEqual({ gateway: null, reason: "invalid" });
    expect(loadAppleSiwa(env, file(privateKey)).gateway).toBeInstanceOf(AppleRestClient);
  });
});
```

- [ ] **Step 2: Run it to see it fail**

Run: `(cd relay && npx vitest run test/apple-rest.test.ts)`
Expected: FAIL. `../src/auth/apple-rest.js` cannot be resolved.

- [ ] **Step 3: Implement**

Key handling:
- Build a `KeyObject` with `createPrivateKey(pem)`. Check `asymmetricKeyType === "ec"` and `asymmetricKeyDetails?.namedCurve === "prime256v1"`.
- Sign with jose: `new SignJWT({ sub: clientId }).setProtectedHeader({ alg: "ES256", kid }).setIssuer(teamId).setAudience("https://appleid.apple.com").setIssuedAt(nowSec).setExpirationTime(nowSec + 300).sign(keyObject)`.

Requests:
- Each request is `POST` with `Content-Type: application/x-www-form-urlencoded`, a `URLSearchParams` body and `signal: AbortSignal.timeout(APPLE_REST_TIMEOUT_MS)`.
- The exchange sends `client_id, client_secret, code, grant_type=authorization_code`.
- The revoke sends `client_id, client_secret, token, token_type_hint=refresh_token`.

Failures:
- A failed exchange logs `apple_token_exchange_failed`, with `{status}` for an HTTP answer or `{error: errorKind(err)}` for a throw. This includes a 200 without a string `refresh_token`.
- A failed revoke logs `apple_revoke_failed` in the same two forms.

`revokeAppleTokens`, for each row:
- no refresh token → log `apple_revoke_skipped` `{reason: "no_refresh_token"}`;
- no gateway → log `apple_revoke_skipped` `{reason: "not_configured"}`;
- else `await gateway.revoke(row.apple_client_id!, row.apple_refresh_token)`.

`loadAppleSiwa` mirrors `loadApns` (`relay/src/push/apns.ts:187-205`), reading `APPLE_TEAM_ID`, `APPLE_SIWA_KEY_ID` and `APPLE_SIWA_KEY_PATH`.

`server.ts`:
- Log `apple_siwa_disabled` `{reason}` or `apple_siwa_enabled`.
- Pass `appleTokens: siwa.gateway` to `startRelay`.

`app.ts`: `c.set("appleTokens", deps.appleTokens ?? null)`.

- [ ] **Step 4: Run the tests to see them pass**

Run: `(cd relay && npx vitest run test/apple-rest.test.ts)`, then `(cd relay && npm test && npm run typecheck)`.
Expected: `Test Files  1 passed (1)`; the full suite has no failed file; no `error TS` line.

- [ ] **Step 5: Commit**

```bash
git add relay/src/auth/apple-rest.ts relay/src/app.ts relay/src/server.ts relay/test/fake-idp.ts relay/test/apple-rest.test.ts
git commit -m "feat(relay): Sign in with Apple REST client (client secret, code exchange, revoke)"
```

---

### Task 8: Apple sign-in (sign in, or `link_required`)

**Files:**
- Create: `relay/src/auth/apple-links.ts`
- Modify: `relay/src/routes/sign-in.ts` (add `POST /apple`)
- Modify: `relay/test/helpers.ts` (Apple helpers)
- Test: `relay/test/auth-apple.test.ts` (new), `relay/test/limits.test.ts`

**Interfaces:**
- Consumes: `identity.ts` (Task 5), `AppleTokenGateway` and `FakeAppleTokens` (Task 7).
- Produces, in `relay/src/auth/apple-links.ts`:
  - `export const APPLE_LINK_TTL_MS = 600_000`, `export const APPLE_LINK_RETENTION_MS = 86_400_000`
  - `export interface AppleLinkRow { id: string; token_hash: Buffer; subject: string; email: string; is_private_email: number; apple_client_id: string; apple_refresh_token: string | null; device_name: string; device_public_key: Buffer; created_at: number; expires_at: number; redeemed_at: number | null }`
  - `export interface NewAppleLink { subject: string; email: string; isPrivateEmail: boolean; appleClientId: string; appleRefreshToken: string | null; deviceName: string; devicePublicKey: Uint8Array }`
  - `export async function createAppleLink(db: Db, link: NewAppleLink, nowMs: number): Promise<string>`. It returns the link token (`generateToken()`) and stores only its hash, with `expires_at = nowMs + APPLE_LINK_TTL_MS`.
  - `export async function findLiveAppleLink(db: Db, linkToken: unknown, nowMs: number): Promise<AppleLinkRow | undefined>`. It needs a 43-char base64url string, `expires_at > nowMs` and `redeemed_at IS NULL`.
  - `export function purgeAppleLinks(db: Db, nowMs: number): void` (deletes rows with `created_at < nowMs - APPLE_LINK_RETENTION_MS`)
- Produces, in `relay/test/helpers.ts`:
  - `export interface AppleSignInOptions { sub?: string; email?: string; isPrivateEmail?: boolean; publicKey?: string; name?: string; authorizationCode?: string | null; claims?: Record<string, unknown>; ip?: string }`
  - `export async function appleIdToken(app: TestApp, options?: AppleSignInOptions): Promise<{ identity_token: string; nonce: string }>`
  - `export async function signInApple(app: TestApp, options?: AppleSignInOptions): Promise<TestResponse>`. The body is `{identity_token, authorization_code, nonce, device}`.
    - `device` is `deviceBody("mobile", overrides)`, where `overrides` holds only the options that are set: `name`, and `public_key: publicKey`. Without them, the defaults stay ("iPhone 16", a random key).
    - `authorization_code` defaults to `"code-" + randomUUID()`; `null` leaves it out.
    - `sub` defaults to `"a-" + randomUUID()`; `email` defaults to `randomEmail()`.

- [ ] **Step 1: Write the failing test**

`relay/test/auth-apple.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { hashToken } from "../src/auth/tokens.js";
import { FakeAppleTokens } from "./fake-idp.js";
import { appleIdToken, call, db, deviceBody, errorCode, makeApp, randomEmail, randomPublicKey, registerAccount, seedUser, signInApple } from "./helpers.js";

describe("POST /v1/auth/apple", () => {
  it("answers 202 link_required for an Apple ID that matches no account; keeps the link hash, the iPhone key and the refresh token", async () => {
    const tokens = new FakeAppleTokens();
    const app = makeApp({ appleTokens: tokens });
    const publicKey = randomPublicKey();
    const res = await signInApple(app, { sub: "a-new", email: "h@privaterelay.appleid.com", isPrivateEmail: true, publicKey, authorizationCode: "code-1" });
    expect(res.status).toBe(202);
    const body = await res.json<{ status: string; link_token: string; expires_in: number }>();
    expect(body).toEqual({ status: "link_required", link_token: expect.stringMatching(/^[A-Za-z0-9_-]{43}$/), expires_in: 600 });
    const link = db().get<{ token_hash: Buffer; subject: string; is_private_email: number; apple_refresh_token: string; device_public_key: Buffer }>("SELECT * FROM apple_links")!;
    expect(Buffer.from(link.token_hash).equals(Buffer.from(await hashToken(body.link_token)))).toBe(true);
    expect([link.subject, link.is_private_email, link.apple_refresh_token]).toEqual(["a-new", 1, "apple-refresh-token-1"]);
    expect(Buffer.from(link.device_public_key).toString("base64url")).toBe(publicKey);
    expect(tokens.exchanges).toEqual([{ clientId: "com.shellx.dev", code: "code-1" }]);
    expect(db().get("SELECT (SELECT COUNT(*) FROM users) AS users, (SELECT COUNT(*) FROM identities) AS identities")).toEqual({ users: 0, identities: 0 });
  });

  it("links by email to an account without a password (auth_method apple) and signs that Apple ID straight in afterwards", async () => {
    const app = makeApp({ appleTokens: new FakeAppleTokens() });
    const email = randomEmail();
    const userId = await seedUser(email, null);
    const publicKey = randomPublicKey();
    const first = await signInApple(app, { sub: "a-1", email: email.toUpperCase(), publicKey });
    expect(first.status).toBe(200);
    const s = await first.json<{ user_id: string; device_id: string; token: string; email: string }>();
    expect([s.user_id, s.email]).toEqual([userId, email]);
    expect(db().get("SELECT auth_method FROM tokens WHERE token_hash = ?", await hashToken(s.token))).toEqual({ auth_method: "apple" });
    const again = await (await signInApple(app, { sub: "a-1", email: "renamed@example.com", publicKey })).json<{ user_id: string; device_id: string }>();
    expect([again.user_id, again.device_id]).toEqual([userId, s.device_id]);
  });

  it("answers 202 link_required for the email of an account that still has a password, and links nothing to that account", async () => {
    const tokens = new FakeAppleTokens();
    const app = makeApp({ appleTokens: tokens });
    const account = await registerAccount(app);
    const res = await signInApple(app, { email: account.email });
    expect(res.status).toBe(202);
    expect((await res.json<{ status: string }>()).status).toBe("link_required");
    expect(db().get("SELECT COUNT(*) AS n FROM identities WHERE user_id = ?", account.agent.userId)).toEqual({ n: 0 });
  });

  it("asks Apple for a refresh token only while the identity has none for this bundle id; a failed exchange never blocks", async () => {
    const tokens = new FakeAppleTokens();
    tokens.refreshToken = null;
    const app = makeApp({ appleTokens: tokens });
    const email = randomEmail();
    await seedUser(email, null);
    expect((await signInApple(app, { sub: "a-2", email })).status).toBe(200);
    expect(db().get("SELECT apple_refresh_token FROM identities WHERE subject = 'a-2'")).toEqual({ apple_refresh_token: null });
    tokens.refreshToken = "apple-refresh-token-2";
    expect((await signInApple(app, { sub: "a-2", email })).status).toBe(200);
    expect(db().get("SELECT apple_refresh_token, apple_client_id FROM identities WHERE subject = 'a-2'")).toEqual({ apple_refresh_token: "apple-refresh-token-2", apple_client_id: "com.shellx.dev" });
    expect((await signInApple(app, { sub: "a-2", email })).status).toBe(200);
    expect(tokens.exchanges).toHaveLength(2);
  });

  it("signs in without an authorization code or without an Apple key, never calling Apple", async () => {
    const tokens = new FakeAppleTokens();
    const email = randomEmail();
    await seedUser(email, null);
    expect((await signInApple(makeApp({ appleTokens: tokens }), { email, authorizationCode: null })).status).toBe(200);
    expect((await signInApple(makeApp(), { email: randomEmail() })).status).toBe(202);
    expect(tokens.exchanges).toEqual([]);
  });

  it("refuses a non-iPhone device (400 invalid_device) and a token that carries the raw nonce (401)", async () => {
    const app = makeApp();
    for (const device of [deviceBody("desktop"), deviceBody("mobile", { platform: "android" })]) {
      const res = await call(app, "POST", "/v1/auth/apple", { body: { ...(await appleIdToken(app)), authorization_code: "c", device } });
      expect([res.status, await errorCode(res)]).toEqual([400, "invalid_device"]);
    }
    const raw = await appleIdToken(app);
    const res = await call(app, "POST", "/v1/auth/apple", {
      body: { ...(await appleIdToken(app, { claims: { nonce: raw.nonce } })), nonce: raw.nonce, authorization_code: "c", device: deviceBody("mobile") },
    });
    expect([res.status, await errorCode(res)]).toEqual([401, "invalid_credentials"]);
  });
});
```

In `relay/test/limits.test.ts`, append `["POST /v1/auth/apple", { method: "POST", path: () => "/v1/auth/apple", token: "none" }]`.

- [ ] **Step 2: Run it to see it fail**

Run: `(cd relay && npx vitest run test/auth-apple.test.ts test/limits.test.ts)`
Expected: FAIL. `signInApple` is not exported and `/v1/auth/apple` answers 404.

- [ ] **Step 3: Implement `signInRoutes.post("/apple", jsonBodyLimit, …)`**

1. `loginIp` → otherwise 429.
2. Read the body. `parseDevice(body.device)` must be `kind === "mobile" && platform === "ios"`, else `invalidDevice`.
3. Verify with `providers: ["apple"]` and 600 s → otherwise 401. Consume the nonce → otherwise 401.
4. `code` = `body.authorization_code` when it is a non-empty string, else null. `pre = matchAccount(db, verified, config.passwordLogin)`. For Apple, `switch_required` is treated exactly like `none` (step 7): the QR link proves ownership through the Mac's Allow and attaches the Apple ID to the **Mac's** account, never to the email-matched one, so it is safe before the cut-over and avoids a dead end for an iPhone user whose real Apple email matches an old password account (decision 2026-11-07, replaces Spec note 9).
5. Call `appleTokens.exchangeCode(verified.audience, code)` only when the gateway is non-null, `code` is non-null, and either `pre.kind !== "identity"` or that identity lacks a refresh token for `verified.audience`. The result (a refresh token, or null) is `refresh`.
6. `purgeAppleLinks(db, now)`.
7. When `pre.kind === "none"` or `pre.kind === "switch_required"`:
   - `createAppleLink` with `{subject, email, isPrivateEmail, appleClientId: verified.audience, appleRefreshToken: refresh, deviceName: device.name, devicePublicKey: device.publicKey}`;
   - log `apple_link_required`;
   - answer `202 {status: "link_required", link_token, expires_in: 600}`.
8. Otherwise precompute the token, then run a transaction that redoes `matchAccount`:
   - `switch_required` or `none` (the account changed meanwhile) → `invalidCredentials`;
   - `identity` → update `last_used_at`. When `refresh` is non-null, also store `apple_refresh_token = refresh` and `apple_client_id = verified.audience`;
   - `email` → `dropPasswordAccess`, then `insertIdentity`, with `appleRefreshToken: refresh` and `appleClientId: refresh === null ? null : verified.audience`. Apple IDs are not limited per account.

   Then `signInDevice(…, "apple", identityId, now)`. Record the app version, log `sign_in`, and answer `200 {user_id, device_id, token, email}`.

- [ ] **Step 4: Run the tests to see them pass**

Run: `(cd relay && npx vitest run test/auth-apple.test.ts test/limits.test.ts)`, then `(cd relay && npm test && npm run typecheck)`.
Expected: `Test Files  2 passed (2)`; the full suite has no failed file; no `error TS` line.

- [ ] **Step 5: Commit**

```bash
git add relay/src/auth/apple-links.ts relay/src/routes/sign-in.ts relay/test/helpers.ts relay/test/auth-apple.test.ts relay/test/limits.test.ts
git commit -m "feat(relay): POST /v1/auth/apple (sign in, or link_required with a link token)"
```

---

### Task 9: Link a hidden-email Apple ID through the Mac's QR code

**Files:**
- Create: `relay/src/routes/apple-link.ts`
- Modify: `relay/src/auth/apple-links.ts` (add `approveAppleLinkPairing`)
- Modify: `relay/src/app.ts` (add `app.route("/v1/auth/apple/link", appleLinkRoutes);` next to the other `/v1/auth` mounts)
- Modify: `relay/src/v2/phones.ts`
  - lines 17-22: rename `housekeeping` to an exported `phonePairingHousekeeping`;
  - lines 24-34: `device_id: string | null; apple_link_id: string | null`;
  - lines 102-128: the list;
  - lines 130-159: approve.
- Modify: `relay/test/v2-phones.test.ts:158-163` (the expected entry gains `links_apple_id: false`)
- Modify: `relay/test/helpers.ts` (`linkAppleIdByQr`)
- Test: `relay/test/apple-link.test.ts` (new), `relay/test/limits.test.ts`

**Interfaces:**
- Consumes: `findLiveAppleLink`, `purgeAppleLinks`, `upsertDevice`, `insertIdentity`, `replaceDeviceToken`, `accountEmail`, `MAX_PENDING_PER_TARGET`, `PAIRING_TTL_MS`.
- Produces `export function approveAppleLinkPairing(db: Db, pairing: { id: string; user_id: string; apple_link_id: string }, nowMs: number): string` in `apple-links.ts`. It is synchronous, runs inside the approve transaction, and returns the phone's device id. Its algorithm is in Step 3.
- Produces `GET /v2/phone-pairings?role=target&apple_links=1`. Apple-link requests are listed only with this parameter. Every entry gains `links_apple_id: boolean` (contracts §2 and "Contract additions" below).
- Produces, in `relay/test/helpers.ts`:
  - `export interface LinkedApple { sub: string; email: string; pairingId: string; session: Session }`
  - `export async function linkAppleIdByQr(app: TestApp, desktopToken: string, machineId: string, options?: AppleSignInOptions): Promise<LinkedApple>`. It runs `signInApple` (expects 202), `POST /v1/auth/apple/link`, the approve with `desktopToken`, then `POST /v1/auth/apple/link/status` (expects `approved`).

- [ ] **Step 1: Write the failing test**

`relay/test/apple-link.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { MAX_PENDING_PER_TARGET, PAIRING_TTL_MS } from "../src/v2/pairings.js";
import { FakeAppleTokens } from "./fake-idp.js";
import {
  call, CountingLimiter, db, errorCode, googleSession, makeApp, randomPublicKey, registerMachine, signInApple, unlimited, type TestApp,
} from "./helpers.js";

const T0 = 1_800_000_000_000;
const b64 = () => Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString("base64");

async function setup(app: TestApp) {
  const owner = await googleSession(app, { kind: "desktop" });
  const machine = await registerMachine(app, owner.token);
  const sub = `a-${crypto.randomUUID()}`;
  const phoneKey = randomPublicKey();
  const link = async () => (await (await signInApple(app, { sub, email: "hidden@privaterelay.appleid.com", isPrivateEmail: true, publicKey: phoneKey, name: "Ann's iPhone" })).json<{ link_token: string }>()).link_token;
  return { owner, machineId: machine.machine_id, linkSlot: machine.link_slot, sub, phoneKey, link };
}
const ask = (app: TestApp, linkToken: string, machineId: string, extra: Record<string, unknown> = {}) =>
  call(app, "POST", "/v1/auth/apple/link", { body: { link_token: linkToken, machine_id: machineId, client_key_b64: b64(), proof_b64: b64(), ...extra } });
const status = (app: TestApp, linkToken: string, pairingId: string) => call(app, "POST", "/v1/auth/apple/link/status", { body: { link_token: linkToken, pairing_id: pairingId } });
const approve = (app: TestApp, token: string, id: string) => call(app, "POST", `/v2/phone-pairings/${id}/approve`, { token });
const pairingOf = async (res: Awaited<ReturnType<typeof ask>>) => (await res.json<{ pairing_id: string }>()).pairing_id;

describe("Apple ID link through the Mac (S1 §6.4)", () => {
  it("shows the request to the Mac only with apple_links=1, flagged and named after the iPhone", async () => {
    const app = makeApp({ now: () => T0 });
    const s = await setup(app);
    const key = b64();
    const proof = b64();
    const res = await ask(app, await s.link(), s.machineId, { client_key_b64: key, proof_b64: proof });
    expect(res.status).toBe(201);
    const id = await pairingOf(res);
    expect(await (await call(app, "GET", "/v2/phone-pairings?role=target&apple_links=1", { token: s.owner.token })).json()).toEqual({
      pairings: [{ pairing_id: id, device_name: "Ann's iPhone", platform: "ios", client_key_b64: key, proof_b64: proof, created_at_unix: T0 / 1000, links_apple_id: true }],
    });
    expect(await (await call(app, "GET", "/v2/phone-pairings?role=target", { token: s.owner.token })).json()).toEqual({ pairings: [] });
  });

  it("links the Apple ID to the Mac's account on approval and hands the session out exactly once", async () => {
    const app = makeApp({ now: () => T0, appleTokens: new FakeAppleTokens() });
    const s = await setup(app);
    const linkToken = await s.link();
    const id = await pairingOf(await ask(app, linkToken, s.machineId));
    expect(await (await status(app, linkToken, id)).json()).toEqual({ status: "pending" });
    expect((await approve(app, s.owner.token, id)).status).toBe(204);
    const phone = db().get<{ id: string }>("SELECT id FROM devices WHERE public_key = ?", Buffer.from(s.phoneKey, "base64url"))!;
    expect(db().get("SELECT user_id, email, is_private_email, apple_refresh_token, linked_via_device_id FROM identities WHERE provider = 'apple'")).toEqual({
      user_id: s.owner.userId, email: "hidden@privaterelay.appleid.com", is_private_email: 1, apple_refresh_token: "apple-refresh-token-1", linked_via_device_id: phone.id,
    });
    const answer = await status(app, linkToken, id);
    const body = await answer.json<{ session: { token: string } }>();
    expect(body).toEqual({
      status: "approved",
      session: { user_id: s.owner.userId, device_id: phone.id, token: expect.stringMatching(/^[A-Za-z0-9_-]{43}$/), email: s.owner.email },
      machine: { machine_id: s.machineId, name: "Mac-Studio", link_slot: s.linkSlot },
    });
    expect(db().get("SELECT auth_method FROM tokens WHERE device_id = ?", phone.id)).toEqual({ auth_method: "apple" });
    const grants = await (await call(app, "GET", "/v2/phone-grants", { token: body.session.token })).json<{ grants: { machine_id: string }[] }>();
    expect(grants.grants.map((g) => g.machine_id)).toEqual([s.machineId]);
    const second = await status(app, linkToken, id);
    expect([second.status, await errorCode(second)]).toEqual([401, "invalid_credentials"]);
    const direct = await (await signInApple(app, { sub: s.sub, publicKey: s.phoneKey })).json<{ user_id: string; device_id: string }>();
    expect([direct.user_id, direct.device_id]).toEqual([s.owner.userId, phone.id]);
  });

  it("deny: the iPhone reads denied and nothing is linked", async () => {
    const app = makeApp({ now: () => T0 });
    const s = await setup(app);
    const linkToken = await s.link();
    const id = await pairingOf(await ask(app, linkToken, s.machineId));
    expect((await call(app, "POST", `/v2/phone-pairings/${id}/deny`, { token: s.owner.token })).status).toBe(204);
    expect(await (await status(app, linkToken, id)).json()).toEqual({ status: "denied" });
    expect(db().get("SELECT (SELECT COUNT(*) FROM identities WHERE provider = 'apple') AS i, (SELECT COUNT(*) FROM phone_grants) AS g")).toEqual({ i: 0, g: 0 });
  });

  it("expires a request after 5 minutes and a link token after 10", async () => {
    let now = T0;
    const app = makeApp({ now: () => now });
    const s = await setup(app);
    const linkToken = await s.link();
    const id = await pairingOf(await ask(app, linkToken, s.machineId));
    now += PAIRING_TTL_MS + 1;
    const late = await approve(app, s.owner.token, id);
    expect([late.status, await errorCode(late)]).toEqual([410, "pairing_expired"]);
    expect(await (await status(app, linkToken, id)).json()).toEqual({ status: "expired" });
    const id2 = await pairingOf(await ask(app, linkToken, s.machineId));
    now = T0 + 600_000;
    expect((await status(app, linkToken, id2)).status).toBe(401);
    expect((await ask(app, linkToken, s.machineId)).status).toBe(401);
    const lateApprove = await approve(app, s.owner.token, id2);
    expect([lateApprove.status, await errorCode(lateApprove)]).toEqual([410, "pairing_expired"]);
  });

  it("refuses a bad link token, an unknown machine, malformed keys and a pairing of another link", async () => {
    const app = makeApp({ now: () => T0 });
    const s = await setup(app);
    const a = await s.link();
    const b = await s.link();
    expect(await errorCode(await ask(app, "x".repeat(43), s.machineId))).toBe("invalid_credentials");
    expect(await errorCode(await ask(app, a, crypto.randomUUID()))).toBe("machine_not_found");
    expect((await ask(app, a, s.machineId, { client_key_b64: "AAAA" })).status).toBe(400);
    const id = await pairingOf(await ask(app, a, s.machineId));
    expect(await errorCode(await status(app, b, id))).toBe("pairing_not_found");
  });

  it("lets a newer request of the same link supersede the older one; a link already approved cannot ask again", async () => {
    const app = makeApp({ now: () => T0 });
    const s = await setup(app);
    const linkToken = await s.link();
    const first = await pairingOf(await ask(app, linkToken, s.machineId));
    const second = await pairingOf(await ask(app, linkToken, s.machineId));
    expect(await (await status(app, linkToken, first)).json()).toEqual({ status: "expired" });
    expect((await approve(app, s.owner.token, second)).status).toBe(204);
    expect((await ask(app, linkToken, s.machineId)).status).toBe(401);
  });

  it("answers 409 identity_in_use when the Apple ID already signs in to another account, leaving the request pending", async () => {
    const app = makeApp({ now: () => T0 });
    const s = await setup(app);
    const other = await googleSession(app, { kind: "desktop" });
    const otherMachine = await registerMachine(app, other.token);
    const toOther = await pairingOf(await ask(app, await s.link(), otherMachine.machine_id));
    const mine = await pairingOf(await ask(app, await s.link(), s.machineId));
    expect((await approve(app, s.owner.token, mine)).status).toBe(204);
    const clash = await approve(app, other.token, toOther);
    expect([clash.status, await errorCode(clash)]).toEqual([409, "identity_in_use"]);
    expect(db().get("SELECT status FROM phone_pairings WHERE id = ?", toOther)).toEqual({ status: "pending" });
  });

  it("caps live pending requests per machine (429)", async () => {
    const app = makeApp({ now: () => T0 });
    const s = await setup(app);
    for (let i = 0; i < MAX_PENDING_PER_TARGET; i++) expect((await ask(app, await s.link(), s.machineId)).status).toBe(201);
    expect((await ask(app, await s.link(), s.machineId)).status).toBe(429);
  });

  it("limits link requests per IP with the login limiter", async () => {
    const loginIp = new CountingLimiter(3);
    const app = makeApp({ now: () => T0, limiters: { ...unlimited, loginIp } });
    const s = await setup(app); // call 1: the Google sign-in
    const linkToken = await s.link(); // call 2: the Apple sign-in
    expect((await ask(app, linkToken, s.machineId)).status).toBe(201); // call 3
    expect((await ask(app, linkToken, s.machineId)).status).toBe(429); // call 4
  });
});
```

In `relay/test/v2-phones.test.ts`, add `links_apple_id: false` to the entry expected at lines 159-162.

In `relay/test/limits.test.ts`, append rows for `POST /v1/auth/apple/link` and `POST /v1/auth/apple/link/status`, both with `token: "none"`.

- [ ] **Step 2: Run it to see it fail**

Run: `(cd relay && npx vitest run test/apple-link.test.ts test/v2-phones.test.ts test/limits.test.ts)`
Expected: FAIL. `/v1/auth/apple/link` answers 404 and the v2-phones entry lacks `links_apple_id`.

- [ ] **Step 3: Implement**

`appleLinkRoutes.post("/", jsonBodyLimit, …)` creates the request:
1. `loginIp` → otherwise 429.
2. `purgeAppleLinks`; `link = await findLiveAppleLink(db, body.link_token, now)` → missing means `invalidCredentials`. A link that already has an `approved` pairing → `invalidCredentials`.
3. Look up the machine with `SELECT id, user_id FROM machines WHERE id = ?` on `parseUuid(body.machine_id)`; it may belong to any account. Not found → `machineNotFound`.
4. `decodeB64` the key and the proof (32 bytes each); a failure → `badRequest`.
5. Run `phonePairingHousekeeping(db, now)`.
6. In a transaction:
   - mark this link's `pending` rows `expired`;
   - `MAX_PENDING_PER_TARGET` live pending rows on the machine → `rateLimited`;
   - insert the row: `device_id NULL`, `apple_link_id = link.id`, `user_id = machine.user_id`, the proof as standard base64 text.
7. Log `apple_link_requested` `{pairing_id}`, then answer `201 {pairing_id}`.

`appleLinkRoutes.post("/status", jsonBodyLimit, …)` reports or redeems:
1. Find the live link → otherwise 401. Run the housekeeping.
2. `pairing` = the row with `id = parseUuid(body.pairing_id)` and `apple_link_id = link.id` → otherwise `pairingNotFound`.
3. Not approved → `200 {status}`.
4. Approved:
   - `accountMachine(db, pairing.user_id, pairing.machine_id)` gone → `pairingNotFound`;
   - precompute the token;
   - in a transaction: `UPDATE apple_links SET redeemed_at = ? WHERE id = ? AND redeemed_at IS NULL` must change 1 row, else `invalidCredentials`. The Apple identity with `link.subject` and `user_id = pairing.user_id` must exist, else `invalidCredentials`. Then `replaceDeviceToken(db, pairing.device_id!, hash, "apple", identityId, now)`;
   - record the app version, and log `apple_link_redeemed` `{device_id, pairing_id}`;
   - answer `200 {status: "approved", session: {user_id, device_id, token, email: accountEmail(db, pairing.user_id)}, machine: {machine_id, name, link_slot}}`.

`approveAppleLinkPairing(db, pairing, nowMs)`:
1. `link` = the row of `apple_links`. Missing, `expires_at <= nowMs` or `redeemed_at !== null` → `Errors.pairingExpired()`.
2. `existing` = the identity with `('apple', link.subject)`. It belongs to another `user_id` → `Errors.identityInUse()`.
3. `deviceId = upsertDevice(db, pairing.user_id, { kind: "mobile", name: link.device_name, platform: "ios", publicKey: link.device_public_key }, nowMs)`.
4. No `existing` → `insertIdentity`:
   - `provider: "apple"`, with `subject`, `email` and `isPrivateEmail` from the link;
   - `appleRefreshToken: link.apple_refresh_token`;
   - `appleClientId: link.apple_refresh_token === null ? null : link.apple_client_id`;
   - `linkedViaDeviceId: deviceId`.

   `existing` → update `last_used_at` and, when the link has a refresh token, the refresh token and client id.
5. `UPDATE phone_pairings SET device_id = ? WHERE id = ?`, then return `deviceId`.

`phones.ts` approve:
- Keep the conditional status `UPDATE` first, so a request that is not pending still gets 409 and an expired one 410.
- Then `const deviceId = pairing.apple_link_id === null ? pairing.device_id! : approveAppleLinkPairing(db, { id: pairing.id, user_id: pairing.user_id, apple_link_id: pairing.apple_link_id }, now);`.
- Use `deviceId` in the `phone_grants` upsert.
- Everything stays inside the existing transaction, so a throw rolls the status back.

`phones.ts` list:
- `LEFT JOIN devices d ON d.id = p.device_id LEFT JOIN apple_links l ON l.id = p.apple_link_id`.
- `COALESCE(d.name, l.device_name) AS device_name`, `COALESCE(d.platform, 'ios') AS platform`.
- Add `AND (p.apple_link_id IS NULL OR (? = 1 AND l.expires_at > ?))`, binding `c.req.query("apple_links") === "1" ? 1 : 0` and `now`.
- Map `links_apple_id: p.apple_link_id !== null`.

`helpers.ts`: add `linkAppleIdByQr`.

- [ ] **Step 4: Run the tests to see them pass**

Run: `(cd relay && npx vitest run test/apple-link.test.ts test/v2-phones.test.ts test/limits.test.ts)`, then `(cd relay && npm test && npm run typecheck)`.
Expected: `Test Files  3 passed (3)`; the full suite has no failed file; no `error TS` line.

- [ ] **Step 5: Commit**

```bash
git add relay/src/routes/apple-link.ts relay/src/auth/apple-links.ts relay/src/app.ts relay/src/v2/phones.ts relay/test/v2-phones.test.ts relay/test/helpers.ts relay/test/apple-link.test.ts relay/test/limits.test.ts
git commit -m "feat(relay): link a hidden-email Apple ID through the Mac's QR code (S1 §6.4)"
```

---

### Task 10: List and remove sign-in methods

**Files:**
- Create: `relay/src/routes/identities.ts`
- Modify: `relay/src/app.ts` (add `app.route("/v1/account/identities", identityRoutes);` after the `/v1/account` mount)
- Test: `relay/test/identities.test.ts` (new)

**Interfaces:**
- Consumes: `revokeAppleTokens` (Task 7), `linkAppleIdByQr` (Task 9).
- Produces: `GET /v1/account/identities` and `DELETE /v1/account/identities/:identity_id`, as in contracts §2.

- [ ] **Step 1: Write the failing test**

`relay/test/identities.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { FakeAppleTokens } from "./fake-idp.js";
import { call, db, errorCode, googleSession, linkAppleIdByQr, makeApp, registerMachine, type TestApp } from "./helpers.js";

const T0 = 1_800_000_000_000;
const UUID = /^[0-9a-f-]{36}$/;
const list = (app: TestApp, token: string) => call(app, "GET", "/v1/account/identities", { token });
const remove = (app: TestApp, token: string, id: string) => call(app, "DELETE", `/v1/account/identities/${id}`, { token });

async function owner(app: TestApp) {
  const desk = await googleSession(app, { kind: "desktop" });
  const machine = await registerMachine(app, desk.token);
  const apple = await linkAppleIdByQr(app, desk.token, machine.machine_id, { email: "hidden@privaterelay.appleid.com", isPrivateEmail: true, name: "Ann's iPhone" });
  return { desk, apple };
}

describe("/v1/account/identities", () => {
  it("lists the Google sign-in and each Apple ID with the iPhone that linked it", async () => {
    const app = makeApp({ now: () => T0, appleTokens: new FakeAppleTokens() });
    const { desk } = await owner(app);
    await googleSession(app);
    expect(await (await list(app, desk.token)).json()).toEqual({
      identities: [
        { identity_id: expect.stringMatching(UUID), provider: "google", email: desk.email, is_private_email: false, linked_via_device_name: null, created_at_unix: T0 / 1000 },
        { identity_id: expect.stringMatching(UUID), provider: "apple", email: "hidden@privaterelay.appleid.com", is_private_email: true, linked_via_device_name: "Ann's iPhone", created_at_unix: T0 / 1000 },
      ],
    });
  });

  it("removes an Apple ID: its devices are signed out, Apple is asked to revoke, the phone grant and the Mac stay", async () => {
    const tokens = new FakeAppleTokens();
    const app = makeApp({ now: () => T0, appleTokens: tokens });
    const { desk, apple } = await owner(app);
    const id = (await (await list(app, desk.token)).json<{ identities: { identity_id: string; provider: string }[] }>()).identities.find((i) => i.provider === "apple")!.identity_id;
    expect((await remove(app, desk.token, id)).status).toBe(204);
    expect((await call(app, "GET", "/v1/devices", { token: apple.session.token })).status).toBe(401);
    expect((await call(app, "GET", "/v1/devices", { token: desk.token })).status).toBe(200);
    expect(tokens.revokes).toEqual([{ clientId: "com.shellx.dev", refreshToken: "apple-refresh-token-1" }]);
    expect(db().get("SELECT COUNT(*) AS n FROM phone_grants WHERE device_id = ?", apple.session.deviceId)).toEqual({ n: 1 });
  });

  it("keeps the Apple ID when the iPhone is unpaired", async () => {
    const app = makeApp({ now: () => T0, appleTokens: new FakeAppleTokens() });
    const { desk, apple } = await owner(app);
    const grant = db().get<{ id: string }>("SELECT id FROM phone_grants WHERE device_id = ?", apple.session.deviceId)!;
    expect((await call(app, "DELETE", `/v2/phone-grants/${grant.id}`, { token: desk.token })).status).toBe(204);
    expect(db().get("SELECT COUNT(*) AS n FROM identities WHERE provider = 'apple'")).toEqual({ n: 1 });
  });

  it("refuses the Google sign-in (409 last_google_identity), unknown or foreign ids (404) and a missing token (401)", async () => {
    const app = makeApp({ now: () => T0, appleTokens: new FakeAppleTokens() });
    const { desk } = await owner(app);
    const other = await googleSession(app);
    const mine = (await (await list(app, desk.token)).json<{ identities: { identity_id: string; provider: string }[] }>()).identities;
    const google = await remove(app, desk.token, mine.find((i) => i.provider === "google")!.identity_id);
    expect([google.status, await errorCode(google)]).toEqual([409, "last_google_identity"]);
    const foreign = db().get<{ id: string }>("SELECT id FROM identities WHERE user_id = ?", other.userId)!.id;
    for (const id of ["not-a-uuid", crypto.randomUUID(), foreign]) expect(await errorCode(await remove(app, desk.token, id))).toBe("identity_not_found");
    expect((await call(app, "GET", "/v1/account/identities")).status).toBe(401);
  });
});
```

- [ ] **Step 2: Run it to see it fail**

Run: `(cd relay && npx vitest run test/identities.test.ts)`
Expected: FAIL, because the routes answer 404 `not_found`.

- [ ] **Step 3: Implement `relay/src/routes/identities.ts`**

`GET /` (requireAuth):
- `SELECT i.id, i.provider, i.email, i.is_private_email, d.name AS linked_via_device_name, i.created_at FROM identities i LEFT JOIN devices d ON d.id = i.linked_via_device_id WHERE i.user_id = ? ORDER BY i.created_at, i.rowid`.
- Map each row to `{identity_id, provider, email, is_private_email: boolean, linked_via_device_name, created_at_unix: unixSeconds(created_at)}`.

`DELETE /:id` (requireAuth):
1. The row with `id = parseUuid(param)` and `user_id = auth.userId` → otherwise `identityNotFound`.
2. For a provider other than `apple`: when `SELECT COUNT(*) … WHERE user_id = ? AND provider != 'apple'` is ≤ 1 → `lastGoogleIdentity`.
3. Delete the identity; its tokens cascade.
4. `await revokeAppleTokens(c.get("appleTokens"), [row])` for an Apple row.
5. Log `identity_removed` `{device_id, identity_id}`, then answer 204.

- [ ] **Step 4: Run the tests to see them pass**

Run: `(cd relay && npx vitest run test/identities.test.ts)`, then `(cd relay && npm test && npm run typecheck)`.
Expected: `Test Files  1 passed (1)`; the full suite has no failed file; no `error TS` line.

- [ ] **Step 5: Commit**

```bash
git add relay/src/routes/identities.ts relay/src/app.ts relay/test/identities.test.ts
git commit -m "feat(relay): list and remove sign-in methods (/v1/account/identities)"
```

---

### Task 11: Delete an account after a fresh sign-in

**Files:**
- Modify: `relay/src/routes/account.ts`
- Test: `relay/test/account.test.ts`, `relay/test/signin-logs.test.ts` (new)

**Interfaces:**
- Consumes: the verifier with `REAUTH_MAX_AGE_SEC`, `consumeNonce`, `revokeAppleTokens`, and the helpers `googleIdToken`, `appleIdToken` and `linkAppleIdByQr`.
- Produces: `DELETE /v1/account` (contracts §2).

- [ ] **Step 1: Write the failing tests**

In `relay/test/account.test.ts`, in `"refuses a wrong password with 401 invalid_credentials and deletes nothing"`, add `expect(await errorCode(missing)).toBe("reauth_required");` after the `{}` call. Then add (importing `FakeAppleTokens` and the helpers):

```ts
describe("DELETE /v1/account with a fresh sign-in (S1 §6.8)", () => {
  const del = (app: TestApp, token: string, body: Record<string, unknown>) => call(app, "DELETE", "/v1/account", { token, body });
  const gone = (userId: string) => db().get("SELECT COUNT(*) AS n FROM users WHERE id = ?", userId);

  it("deletes for a fresh Google token of the account's own Google account", async () => {
    const app = makeApp();
    const s = await googleSession(app);
    expect((await del(app, s.token, await googleIdToken(app, { sub: s.sub }))).status).toBe(204);
    expect(gone(s.userId)).toEqual({ n: 0 });
    expect(db().get("SELECT COUNT(*) AS n FROM identities")).toEqual({ n: 0 });
  });

  it("deletes for a fresh Apple token and asks Apple to revoke the stored refresh token, even when Apple refuses", async () => {
    const tokens = new FakeAppleTokens();
    tokens.revokeOk = false;
    const app = makeApp({ appleTokens: tokens });
    const desk = await googleSession(app, { kind: "desktop" });
    const machine = await registerMachine(app, desk.token);
    const apple = await linkAppleIdByQr(app, desk.token, machine.machine_id);
    const { identity_token, nonce } = await appleIdToken(app, { sub: apple.sub });
    expect((await del(app, apple.session.token, { id_token: identity_token, nonce })).status).toBe(204);
    expect(tokens.revokes).toEqual([{ clientId: "com.shellx.dev", refreshToken: "apple-refresh-token-1" }]);
    expect(gone(desk.userId)).toEqual({ n: 0 });
  });

  it("refuses (401 invalid_credentials, nothing deleted) a token over 300 s old, another account's token and a reused nonce", async () => {
    const app = makeApp();
    const s = await googleSession(app);
    const other = await googleSession(app);
    const old = await googleIdToken(app, { sub: s.sub, claims: { iat: Math.floor(Date.now() / 1000) - 301 } });
    const foreign = await googleIdToken(app, { sub: other.sub });
    for (const body of [old, foreign]) {
      const res = await del(app, s.token, body);
      expect([res.status, await errorCode(res)]).toEqual([401, "invalid_credentials"]);
    }
    const used = await googleIdToken(app, { sub: other.sub });
    expect((await del(app, other.token, used)).status).toBe(204);
    expect((await del(app, s.token, used)).status).toBe(401);
    expect(gone(s.userId)).toEqual({ n: 1 });
  });

  it("answers 401 reauth_required to an empty body and to a password for a Google account", async () => {
    const app = makeApp();
    const s = await googleSession(app);
    for (const body of [{}, { password: "anything at all" }]) expect(await errorCode(await del(app, s.token, body))).toBe("reauth_required");
  });
});
```

`relay/test/signin-logs.test.ts`. It covers every new flow, and no log line may carry a secret or a 43+ character base64url or hex run. Tokens, nonces, `sha256_hex` nonces and JWT segments are all such runs, while UUIDs are 36 characters.

```ts
import { afterEach, expect, it, vi } from "vitest";
import { FakeAppleTokens } from "./fake-idp.js";
import { call, googleIdToken, googleSession, linkAppleIdByQr, makeApp, registerAccount, registerMachine } from "./helpers.js";

afterEach(() => vi.restoreAllMocks());

it("never logs emails, subs, codes, refresh tokens, nonces, ID tokens, link tokens or session tokens", async () => {
  const lines: string[] = [];
  const capture = (...args: unknown[]) => void lines.push(args.map(String).join(" "));
  for (const level of ["log", "info", "warn", "error"] as const) vi.spyOn(console, level).mockImplementation(capture);
  const app = makeApp({ appleTokens: new FakeAppleTokens() });
  const desk = await googleSession(app, { kind: "desktop", sub: "g-secret-sub", email: "secret.owner@example.com" });
  const machine = await registerMachine(app, desk.token);
  const apple = await linkAppleIdByQr(app, desk.token, machine.machine_id, { sub: "a-secret-sub", email: "secret.hidden@privaterelay.appleid.com", authorizationCode: "code-secret-1" });
  const account = await registerAccount(app);
  await call(app, "POST", "/v1/auth/google/link", { token: account.agent.token, body: await googleIdToken(app, { sub: "g-secret-link", email: "secret.linked@example.com" }) });
  await call(app, "DELETE", "/v1/account", { token: desk.token, body: await googleIdToken(app, { sub: "g-secret-sub" }) });
  const output = lines.join("\n");
  expect(output).toContain('"event":"sign_in"');
  expect(output).toContain('"event":"apple_link_redeemed"');
  for (const secret of ["secret.owner", "secret.hidden", "secret.linked", "g-secret-sub", "a-secret-sub", "g-secret-link", "code-secret-1", "apple-refresh-token-1", apple.session.token]) {
    expect(output).not.toContain(secret);
  }
  expect(output).not.toMatch(/[A-Za-z0-9_-]{43,}/);
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `(cd relay && npx vitest run test/account.test.ts test/signin-logs.test.ts)`
Expected: FAIL. The ID-token deletion answers 401 `reauth_required` instead of 204, because the route only takes passwords.

- [ ] **Step 3: Implement the route**

Order of `DELETE /v1/account` (requireAuth, jsonBodyLimit):
1. Read the body. Load the user (`email`, `password_hash`); a missing user → `unauthorized`. Apply `loginEmail.limit(user.email)` → otherwise 429.
2. When `body.id_token` is a string:
   - verify with `providers: ["google", "apple", "test"]` and `maxAgeSec: REAUTH_MAX_AGE_SEC`;
   - then `consumeNonce`;
   - then the identity with `(provider, subject)` must have `user_id = auth.userId`.

   Any failure → log `account_delete_denied` `{device_id}`, then `invalidCredentials`.
3. Otherwise, when `body.password` is a string, `config.passwordLogin` is on and `user.password_hash !== null`, keep today's check (over-long password, argon2 verify) → otherwise `invalidCredentials`.
4. Every other body → log `account_delete_denied`, then `reauthRequired`. This replaces the Task 1 and Task 2 guards.
5. `rows = SELECT apple_client_id, apple_refresh_token FROM identities WHERE user_id = ? AND provider = 'apple'`. Then `DELETE FROM users WHERE id = ?` (everything cascades), then `await revokeAppleTokens(c.get("appleTokens"), rows)`. Revocation never blocks the deletion.
6. Keep the existing best-effort `closeAccount()`, the `account_deleted` log and the 204.

- [ ] **Step 4: Run the tests to see them pass**

Run: `(cd relay && npx vitest run test/account.test.ts test/signin-logs.test.ts test/password-login.test.ts test/limits.test.ts)`, then `(cd relay && npm test && npm run typecheck)`.
Expected: `Test Files  4 passed (4)`; the full suite has no failed file; no `error TS` line.

- [ ] **Step 5: Commit**

```bash
git add relay/src/routes/account.ts relay/test/account.test.ts relay/test/signin-logs.test.ts
git commit -m "feat(relay): delete an account after a fresh Google or Apple sign-in; revoke Apple tokens"
```

---

### Task 12: Close registration

**Files:**
- Modify: `relay/src/routes/auth.ts:31-67`: `/register` becomes a one-line 410. Drop the imports nothing uses any more (`checkEmail`, `insertToken`).
- Modify: `relay/src/auth/rate-limit.ts`: remove `registerIp` and `REGISTER_PER_IP`.
- Modify: `relay/test/helpers.ts:43-46` (`unlimited`), `:271-281` (`registerAccount`)
- Modify: `relay/test/auth.test.ts:20-154` and `:287-319`
- Modify: `relay/test/hasher-busy.test.ts` (whole file)
- Modify: `relay/test/server.test.ts:185-228`
- Modify: `relay/test/versions.test.ts:44-69`
- Modify: `relay/test/limits.test.ts:73`, `relay/test/account.test.ts:237-240`, `relay/test/limiter.test.ts:75-87` and `:113-122`
- Modify: `scripts/shellx/share-e2e.mjs` (imports, `startApi` lines 187-194, `desktopAccount` lines 220-228)

**Interfaces:**
- Consumes: `createTestIssuer` and `testIdTokenClaims` (Task 3), `createIdTokenVerifier` (Task 3), the nonce and Google routes.
- Produces: `registerAccount(app, email?, password?)` keeps its signature and `Account` result. It now writes the account directly through `seedUser`:
  - an `agent` device named `MacBook-Pro` on `macos`, with the key from `deviceBody("agent")`;
  - a password token through `insertToken`;
  - all at `(app.now ?? Date.now)()`.

  It goes through no route and no rate limiter.

- [ ] **Step 1: Write the failing test**

Replace `describe("POST /v1/auth/register", …)` in `relay/test/auth.test.ts` with:

```ts
describe("POST /v1/auth/register (closed, contracts §2)", () => {
  it.each([
    ["a valid body", { email: "new@example.com", password: PASSWORD, device: deviceBody("agent") }],
    ["a malformed body", "{not json"],
    ["no body", undefined],
  ])("answers 410 registration_closed to %s and creates nothing", async (_, body) => {
    const res = await call(makeApp(), "POST", "/v1/auth/register", { body });
    expect([res.status, await errorCode(res)]).toEqual([410, "registration_closed"]);
    expect(db().get("SELECT COUNT(*) AS n FROM users")).toEqual({ n: 0 });
  });
});
```

- [ ] **Step 2: Run it to see it fail**

Run: `(cd relay && npx vitest run test/auth.test.ts -t "registration_closed")`
Expected: FAIL in all three cases, because the route still registers:
- the valid body gets 201, and `errorCode` throws reading the missing `error` field;
- the malformed body and the missing body get 400 `bad_request`.

- [ ] **Step 3: Close the route and move every test off it**

- `auth.ts`: `authRoutes.post("/register", () => { throw Errors.registrationClosed(); });` — no limiter and no body read. `rate-limit.ts` and `helpers.ts` (`unlimited`): drop `registerIp`.
- `helpers.ts`: rewrite `registerAccount` as described in the Interfaces block.
- `auth.test.ts`:
  - In `describe("production rate limits …")`, delete its first two tests: they registered accounts, and the nonce tests in Task 4 now cover the production wiring. Keep `"logs neither the IP nor the email of a refused request"`.
  - In `"database contention"`, the write becomes `call(app, "POST", "/v1/auth/nonce", { body: {} })`. Expect 500 while the lock is held and 201 after `ROLLBACK`. Drop the `email` variable and its `not.toContain(email)`; keep `not.toContain("INSERT")`.
- `hasher-busy.test.ts`: rewrite the test around login only. The header comment still holds (this file asks for the dummy hash first). The new body:

```ts
it("answers 429 rate_limited to login while no hash can start or wait, then recovers", async () => {
  const gated = gatedBackend();
  const app = makeApp({ passwords: createPasswordHasher(gated.backend, 1, 0) });
  const running = () => waitFor(async () => (gated.started() === 1 ? true : null));
  const login = (email: string) => call(app, "POST", "/v1/auth/login", { body: { email, password: PASSWORD, device: deviceBody("mobile") } });
  const alice = randomEmail();
  await seedUser(alice, PASSWORD); // registration is closed; the gated backend accepts any stored hash
  const first = login(alice);
  await running();
  const refused = await login(randomEmail()); // the dummy hash for an unknown email cannot start
  expect([refused.status, await errorCode(refused)]).toEqual([429, "rate_limited"]);
  const known = await login(alice); // a real account's verify cannot start either
  expect([known.status, await errorCode(known)]).toEqual([429, "rate_limited"]);
  gated.releaseOne();
  expect((await first).status).toBe(200);
  const later = login(randomEmail()); // recovered, and the refused dummy hash was not cached
  await running();
  gated.releaseOne();
  await running();
  gated.releaseOne();
  const answer = await later;
  expect([answer.status, await errorCode(answer)]).toEqual([401, "invalid_credentials"]);
});
```

- `server.test.ts` (`"ignores a second SIGTERM …"`):
  - the slow request becomes `POST /v1/auth/login` with body `{ email: randomEmail(), password: PASSWORD, device: deviceBody("mobile") }`;
  - rename `registered` to `answered`;
  - expect `401` (completed normally) instead of `201`;
  - the comment reads "A sign-in whose body is still arriving".
- `versions.test.ts:44`:
  - rename the test to `"at login, only once the request succeeded"`;
  - delete the register request and its `agentId` / `"1.2.3"` assertion;
  - keep everything from `const account = await registerAccount(app);` on.
- `limits.test.ts`: delete the `POST /v1/auth/register` row.
- `account.test.ts:237-240`: replace the re-register with `expect(db().get("SELECT 1 AS x FROM users WHERE email = ?", account.email)).toBeUndefined();`.
- `limiter.test.ts`:
  - remove `REGISTER_PER_IP` from the import and from the first test, whose name becomes `"enforces login 10/IP and login 5/email"` and whose tuple becomes `[LOGIN_PER_IP, LOGIN_PER_EMAIL, RATE_WINDOW_MS]` → `[10, 5, 60_000]`;
  - drop the `registerIp` lines.

- [ ] **Step 4: Run the relay suite**

Run: `(cd relay && npm test && npm run typecheck)` and `(cd relay && grep -rn "auth/register\|registerIp\|REGISTER_PER_IP" src test scripts)`.
Expected:
- no failed test file and no `error TS` line;
- the grep prints exactly two lines, both in `test/auth.test.ts`: the new describe title and its `call(…, "/v1/auth/register", …)`. The route line `authRoutes.post("/register", …)` does not contain `auth/register`.

- [ ] **Step 5: Switch share-e2e to the test identity provider**

In `scripts/shellx/share-e2e.mjs`:
- Next to the other relay imports, add `createTestIssuer` and `testIdTokenClaims` from `scripts/test-idp.ts` and `createIdTokenVerifier` from `src/auth/id-token.ts`, both loaded through `fileUrl(join(RELAY_DIR, …))`.
- Add `const TEST_ISSUER = 'https://test-idp.shellx.invalid';` and `const testIdp = await createTestIssuer(TEST_ISSUER);`.
- In `startApi`:
  - in the limiter name list, replace `'registerIp'` with `'nonceIp'`;
  - pass `idTokens: createIdTokenVerifier({ googleClientIds: [], appleClientIds: [], testIdp: { issuer: TEST_ISSUER, keys: testIdp.keys } })` to `startRelay`.
- `desktopAccount(base)`:
  - `POST /v1/auth/nonce` (expect 201);
  - `POST /v1/auth/google` with `{ id_token: await testIdp.sign(testIdTokenClaims(TEST_ISSUER, { sub: email, email, nonce })), nonce, device: device('desktop') }` (expect 200, else throw `google sign-in: <status> <body>`);
  - return `body.token`;
  - drop the password.

Run: `grep -n "auth/register\|auth/login\|registerIp" scripts/shellx/share-e2e.mjs`, then `node scripts/shellx/share-e2e.mjs`. The first run builds `cmux-relay` and the Swift `share-e2e-host`, which takes minutes. `CMUX_RELAY_BIN` may point at an existing binary.
Expected: the grep prints nothing; the last line of the e2e run is `share-e2e: <n> checks passed`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add relay/src/routes/auth.ts relay/src/auth/rate-limit.ts relay/test/helpers.ts relay/test/auth.test.ts relay/test/hasher-busy.test.ts relay/test/server.test.ts relay/test/versions.test.ts relay/test/limits.test.ts relay/test/account.test.ts relay/test/limiter.test.ts scripts/shellx/share-e2e.mjs
git commit -m "feat(relay): close registration (410 registration_closed); tests seed accounts, share-e2e signs in via the test provider"
```

---

### Task 13: Operator scripts (password cut-over, smoke token) and the relay2 smoke

**Files:**
- Create: `relay/src/scripts/password-cutover.ts`, `relay/src/scripts/mint-smoke-token.ts`
- Modify: `relay/package.json` (`scripts`), `relay/scripts/relay2-smoke.ts`
- Test: `relay/test/password-cutover.test.ts` (new), `relay/test/mint-smoke-token.test.ts` (new), `relay/test/relay2-smoke.test.ts`

**Interfaces:**
- Produces, in `relay/src/scripts/password-cutover.ts`:
  - `export interface CutoverCounts { passwords: number; sessions: number }`
  - `export function passwordState(db: Db): CutoverCounts` counts users with a password and tokens with `auth_method = 'password'`.
  - `export function cutOverPasswords(db: Db): CutoverCounts`. In one transaction it runs `UPDATE users SET password_hash = NULL WHERE password_hash IS NOT NULL` and `DELETE FROM tokens WHERE auth_method = 'password'`, and returns both change counts.
  - A `main()` guarded by `import.meta.url === pathToFileURL(process.argv[1]).href` (as in `relay/scripts/relay2-smoke.ts:171`).
- Produces, in `relay/src/scripts/mint-smoke-token.ts`:
  - `export const SMOKE_EMAIL = "relay2-smoke@smoke.invalid"`, `export const SMOKE_DEVICE_NAME = "relay2-smoke"`
  - `export async function mintSmokeToken(db: Db, nowMs: number): Promise<string>`. It creates the smoke user if it is missing: no password, no identity, `password_changed_at = created_at = nowMs`. It upserts the one `desktop` / `macos` device, whose public key is fixed: `sha256("shellx-relay2-smoke")` (32 bytes). It then runs `replaceDeviceToken(…, "test", null, nowMs)` and returns the token.
  - A guarded `main()`.
- Produces, in `relay/scripts/relay2-smoke.ts`:
  - `SmokeOptions { base: string; token: string; fetch?; WebSocket?; registerTimeoutMs? }` (no `email` or `password`);
  - `runRelay2Smoke` skips the login step;
  - `main()` reads `SHELLX_SMOKE_TOKEN` and otherwise asks `Smoke token: ` (hidden).
- Produces, in `relay/package.json` `scripts`: `"password-cutover": "node dist/scripts/password-cutover.js"` and `"mint-smoke-token": "node dist/scripts/mint-smoke-token.js"`. Both run inside the container, where `dist/` exists.

- [ ] **Step 1: Write the failing tests**

`relay/test/password-cutover.test.ts`:

```ts
import { spawnSync } from "node:child_process";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { cutOverPasswords, passwordState } from "../src/scripts/password-cutover.js";
import { call, db, googleSession, loginDevice, makeApp, registerAccount, tempDir } from "./helpers.js";

const RELAY_DIR = join(import.meta.dirname, "..");
const run = (args: string[], env: Record<string, string>) =>
  spawnSync(process.execPath, ["--import", "tsx", "src/scripts/password-cutover.ts", ...args], {
    cwd: RELAY_DIR, encoding: "utf8", env: { ...process.env, DB_PATH: join(tempDir(), "relay.db"), ...env }, timeout: 20_000,
  });

describe("password cut-over (S1 §7 step 5)", () => {
  it("clears every password and password session, keeps other sessions, and lets the email link straight in afterwards", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const phone = await loginDevice(app, account, "mobile");
    const google = await googleSession(app);
    expect(passwordState(db())).toEqual({ passwords: 1, sessions: 2 });
    expect(cutOverPasswords(db())).toEqual({ passwords: 1, sessions: 2 });
    expect(passwordState(db())).toEqual({ passwords: 0, sessions: 0 });
    for (const token of [account.agent.token, phone.token]) expect((await call(app, "GET", "/v1/devices", { token })).status).toBe(401);
    expect((await call(app, "GET", "/v1/devices", { token: google.token })).status).toBe(200);
    expect((await googleSession(app, { email: account.email })).userId).toBe(account.agent.userId);
  });

  it("the script refuses unless PASSWORD_LOGIN=off, dry-runs without --yes and prints counts only", async () => {
    await registerAccount(makeApp());
    const refused = run(["--yes"], { PASSWORD_LOGIN: "on" });
    expect([refused.status, refused.stderr]).toEqual([1, "password-cutover: set PASSWORD_LOGIN=off and recreate the relay first\n"]);
    const dry = run([], { PASSWORD_LOGIN: "off" });
    expect([dry.status, dry.stdout]).toEqual([0, "password-cutover: dry run: 1 account(s) with a password, 1 password session(s); run again with --yes to remove them.\n"]);
    expect(passwordState(db()).passwords).toBe(1);
    const real = run(["--yes"], { PASSWORD_LOGIN: "off" });
    expect([real.status, real.stdout]).toEqual([0, "password-cutover: removed 1 password(s) and 1 password session(s).\n"]);
    expect(passwordState(db())).toEqual({ passwords: 0, sessions: 0 });
  });
});
```

`relay/test/mint-smoke-token.test.ts`:

```ts
import { spawnSync } from "node:child_process";
import { join } from "node:path";
import { expect, it } from "vitest";
import { authenticate } from "../src/auth/session.js";
import { mintSmokeToken } from "../src/scripts/mint-smoke-token.js";
import { call, db, makeApp, registerMachine, tempDir } from "./helpers.js";

it("keeps one passwordless smoke account and device; each mint replaces the previous token (auth_method test)", async () => {
  const app = makeApp();
  const first = await mintSmokeToken(db(), Date.now());
  const second = await mintSmokeToken(db(), Date.now());
  expect(first).toMatch(/^[A-Za-z0-9_-]{43}$/);
  expect((await call(app, "GET", "/v1/devices", { token: first })).status).toBe(401);
  const me = (await authenticate(db(), second, Date.now()))!;
  expect(me.kind).toBe("desktop");
  expect(db().get("SELECT email, password_hash FROM users WHERE id = ?", me.userId)).toEqual({ email: "relay2-smoke@smoke.invalid", password_hash: null });
  expect(db().get("SELECT COUNT(*) AS n FROM devices WHERE user_id = ?", me.userId)).toEqual({ n: 1 });
  expect(db().get("SELECT auth_method FROM tokens WHERE device_id = ?", me.deviceId)).toEqual({ auth_method: "test" });
  await registerMachine(app, second);
});

it("the script prints the token and nothing else", () => {
  db();
  const r = spawnSync(process.execPath, ["--import", "tsx", "src/scripts/mint-smoke-token.ts"], {
    cwd: join(import.meta.dirname, ".."), encoding: "utf8", env: { ...process.env, DB_PATH: join(tempDir(), "relay.db") }, timeout: 20_000,
  });
  expect([r.status, r.stderr]).toEqual([0, ""]);
  expect(r.stdout).toMatch(/^[A-Za-z0-9_-]{43}\n$/);
});
```

In `relay/test/relay2-smoke.test.ts`:
- `run` becomes `runRelay2Smoke({ base, token: "t".repeat(43), fetch: fetchFn, registerTimeoutMs: 50 })`.
- The describe name becomes `"relay2 smoke refuses to send the token over an insecure URL"`.
- The accepted-bases test expects `step: "machine"`.
- Add:

```ts
it("sends the minted token as the bearer of its first request and never logs in", async () => {
  const fetchFn = vi.fn().mockRejectedValue(new Error("offline"));
  await run("https://relay.shellx.pro", fetchFn as unknown as typeof fetch);
  const [url, init] = fetchFn.mock.calls[0]! as [URL, RequestInit];
  expect(url.pathname).toBe("/v2/machines");
  expect((init.headers as Record<string, string>).Authorization).toBe(`Bearer ${"t".repeat(43)}`);
  expect(fetchFn.mock.calls.some(([u]) => String(u).includes("/v1/auth/login"))).toBe(false);
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `(cd relay && npx vitest run test/password-cutover.test.ts test/mint-smoke-token.test.ts test/relay2-smoke.test.ts)`
Expected: FAIL. The two script modules cannot be resolved, and the smoke still starts at `login`.

- [ ] **Step 3: Implement**

`password-cutover.ts` `main`:
1. `process.env.PASSWORD_LOGIN?.trim() !== "off"` → print that refusal line to stderr, exit 1.
2. Open `Db.open(process.env.DB_PATH?.trim() || DEFAULT_DB_PATH, { fileMustExist: true })`.
3. Without `--yes` (via `parseArgs`): print the dry-run line with `passwordState`.
4. With `--yes`: run `cutOverPasswords` and print the "removed" line.
5. A database error prints `password-cutover: database error (<errorKind>)` to stderr and exits 1. No SQL is ever printed.

`mint-smoke-token.ts` `main`:
- On success, print exactly the token followed by a newline.
- On failure, print `mint-smoke-token: database error (<errorKind>)` to stderr and exit 1.

`relay2-smoke.ts`:
- Drop the `login` step and its device body. The token comes from `options.token`.
- The `finally` block still deletes the machine and logs out: each minted token is single use.
- Update the header comment, `isSecureBase`'s doc ("the token must never cross the network in clear"), and `main()`'s prompts (no e-mail or password).

`package.json`: add the two scripts.

- [ ] **Step 4: Run the tests to see them pass, and build**

Run: `(cd relay && npx vitest run test/password-cutover.test.ts test/mint-smoke-token.test.ts test/relay2-smoke.test.ts)`, then `(cd relay && npm test && npm run typecheck && npm run build && ls dist/scripts/password-cutover.js dist/scripts/mint-smoke-token.js)`.
Expected: `Test Files  3 passed (3)`; the full suite has no failed file; no `error TS` line; `ls` prints both paths.

- [ ] **Step 5: Commit**

```bash
git add relay/src/scripts/password-cutover.ts relay/src/scripts/mint-smoke-token.ts relay/package.json relay/scripts/relay2-smoke.ts relay/test/password-cutover.test.ts relay/test/mint-smoke-token.test.ts relay/test/relay2-smoke.test.ts
git commit -m "feat(relay): password cut-over and smoke-token scripts; relay2 smoke uses a minted token"
```

---

### Task 14: Deploy configuration and runbooks

**Files:**
- Modify: `deploy/docker-compose.yml:39-44` (after `APNS_TEAM_ID`)
- Test: `deploy/tests/compose.test.mjs` (append at the end of the file)
- Modify: `deploy/README.md`: a new section before `## Admin (admin.shellx.pro)` (line 240), and bullets under `## Operations` (next to line 438)
- Modify: `relay/README.md`: lines 35-56 (configuration), 90-97 (rate limits, argon2), new sections before `## Healthcheck`, and the reset section at line 230

**Interfaces:**
- Consumes: the env names (contracts §2), the scripts (Task 13), and the startup events (Tasks 5 and 7).

- [ ] **Step 1: Write the failing test**

Append to `deploy/tests/compose.test.mjs`:

```js
test('sign-in: the relay takes the Google/Apple sign-in settings and PASSWORD_LOGIN from .env, never a test identity provider', () => {
  const relay = service('relay');
  for (const name of ['GOOGLE_CLIENT_IDS', 'APPLE_CLIENT_IDS', 'APPLE_TEAM_ID', 'APPLE_SIWA_KEY_ID', 'APPLE_SIWA_KEY_PATH', 'PASSWORD_LOGIN']) {
    assert.match(relay, new RegExp(`^ {6}${name}: \\$\\{${name}:-\\}$`, 'm'), name);
  }
  assert.doesNotMatch(compose, /TEST_IDP/);
  assert.doesNotMatch(readFileSync(join(deployDir, 'relay.env'), 'utf8'), /TEST_IDP|GOOGLE_CLIENT|APPLE_|PASSWORD_LOGIN/);
});
```

- [ ] **Step 2: Run it to see it fail**

Run: `node --test deploy/tests/compose.test.mjs`
Expected: `# fail 1`, with `GOOGLE_CLIENT_IDS` named in the assertion message.

- [ ] **Step 3: Edit the compose file and both READMEs**

`deploy/docker-compose.yml`: after the `APNS_TEAM_ID` line, add a comment and six lines, each of the form `NAME: ${NAME:-}`:
- The comment says: Sign in with Google and Apple (S1 §6.2), set by hand in `.env`; see deploy/README.md "Sign in with Google and Apple".
- The lines are `GOOGLE_CLIENT_IDS`, `APPLE_CLIENT_IDS`, `APPLE_TEAM_ID`, `APPLE_SIWA_KEY_ID`, `APPLE_SIWA_KEY_PATH` and `PASSWORD_LOGIN`.
- An empty value falls back to the relay's default (`APPLE_CLIENT_IDS` → both bundle ids, `PASSWORD_LOGIN` → `on`).

`deploy/README.md`, new section `## Sign in with Google and Apple (once, by hand)`, modeled on "iPhone push (APNs)":
- the values:
  - `GOOGLE_CLIENT_IDS` = the iOS clients of `com.shellx.prod` and `com.shellx.dev`, the Web client (Android's `serverClientId`) and the Desktop client, comma-separated, no spaces;
  - `APPLE_TEAM_ID=W4RF3W4VTZ`;
  - `APPLE_SIWA_KEY_ID=<key id>`;
  - `APPLE_SIWA_KEY_PATH=/secrets/siwa.p8`, a key with Sign in with Apple enabled (it may be the APNs key if that key has both services);
  - `APPLE_CLIENT_IDS` stays unset;
- the upload commands: `mkdir -m 700 -p ~/siwa-upload`, `scp`, `sudo install -o 1000 -g 1000 -m 400 … ~/phu/shellx/secrets/siwa.p8`, `rm -rf ~/siwa-upload`;
- the `printf … >> ~/phu/shellx/.env` line;
- `docker compose up -d --force-recreate relay`;
- `docker compose logs relay | grep -E 'google_sign_in|apple_siwa'`: expect `apple_siwa_enabled` and no `google_sign_in_disabled`;
- one sentence each on what happens without the Google list (every Google sign-in is 401) and without the key (no exchange and no revocation);
- "never set `TEST_IDP_ISSUER` or `TEST_IDP_JWKS_PATH` here";
- a `### Password cut-over (the day password sign-in ends)` subsection, in this order:
  1. `sed -i '/^PASSWORD_LOGIN=/d' .env && echo 'PASSWORD_LOGIN=off' >> .env && docker compose up -d --force-recreate relay`; the log shows `password_login_off`;
  2. `docker compose exec relay npm run -s password-cutover`, a dry run;
  3. `docker compose exec relay npm run -s password-cutover -- --yes`;

  then a note that step 3 cannot be undone except by restoring a backup.

`deploy/README.md` `## Operations`, add two bullets:
- **Smoke test of relay2:** from your machine, in `relay/`, run `SHELLX_SMOKE_TOKEN="$(ssh <deploy-user>@<vps> 'cd ~/phu/shellx && docker compose exec -T relay npm run -s mint-smoke-token')" npm run relay2:smoke`. Each mint replaces the previous token, and the smoke logs it out.
- **Emergency password reset:** add "(until the password cut-over)".

`relay/README.md`:
- Add the env rows to the configuration table. Give `TEST_IDP_*` the bold "Test relays only, never production" note and its constraints (both or neither; no Google or Apple issuer; logs `test_idp_enabled`).
- Mention `0010_identities.sql` in the migrations paragraph.
- Rate limits: replace "register 3/IP" with "nonce 30/IP"; Google and Apple sign-in and Apple link requests share login 10/IP.
- argon2 line: "beyond that login, password change and password account deletion answer 429".
- A new `## Sign-in (Google and Apple)` section:
  - a route table copied from contracts §2;
  - the ID-token checks;
  - the §6.3 rules, including the `PASSWORD_LOGIN=off` link;
  - the in-place link;
  - the Apple link flow, with `apple_links=1` and the exactly-once handoff;
  - identities;
  - deletion with Apple revocation;
  - registration 410;
  - the test provider (`relay/scripts/test-idp.ts`, aud `shellx-test-idp`).
- `## Password cut-over` and `## Smoke token` sections with the in-container commands of the deploy README.

- [ ] **Step 4: Run the tests to see them pass**

Run: `node --test deploy/tests/compose.test.mjs`
Expected: `# fail 0`.

- [ ] **Step 5: Commit**

```bash
git add deploy/docker-compose.yml deploy/tests/compose.test.mjs deploy/README.md relay/README.md
git commit -m "docs(deploy): Google and Apple sign-in settings, password cut-over and smoke-token runbooks"
```

---

### Task 15: Privacy policy

**Files:**
- Modify: `web/src/pages/privacy.md`
- Modify: `web/tests/site.test.mjs:127`

**Interfaces:**
- Produces: the in-app deletion path label `Settings › Account › Delete Account…`, exactly the phone apps' wording (contracts §12; "Contract additions" below).

- [ ] **Step 1: Make the site test expect the new in-app path**

In `web/tests/site.test.mjs:127`, change `'Settings → Delete account'` to `'Settings › Account › Delete Account…'`.

- [ ] **Step 2: Run it to see it fail**

Run: `(cd web && npm run build)`
Expected: FAIL with `privacy page /privacy/ must describe in-app deletion (Settings › Account › Delete Account…)`.

- [ ] **Step 3: Rewrite the affected parts of `web/src/pages/privacy.md`**

Keep every other line. Keep the `delete-account` anchor, and keep the facts the test asserts: `argon2id`, `SHA-256`, `X25519`, `90`, `256 KiB`, `Noise`. Set `updated:` to the commit day (`date +%F`).

The edits, with exact copy:

- **Summary, bullet 2** (line 15) becomes:
  > - We store only what is needed to run your account: your email, the Google account or Apple ID you sign in with, device information and pairing records. You sign in with Google, or with Apple on iPhone; we never see your Google or Apple password.

- **§1, the `**Account**` list** (lines 22-26) becomes:
  > **Account**
  >
  > - **Email** — the email of your account, stored in lowercase: the address Google (or, for an iPhone that signs in with Apple, your Apple ID) reported when the account was created. We do not send verification or marketing emails.
  > - **Sign-in methods** — for each Google account or Apple ID that can sign in to your account: the provider, the stable account identifier it gives ShellX (not your password), the email it reported when it was linked, whether that email is an Apple "Hide My Email" address, when it was linked and last used and, for an Apple ID linked by scanning your computer's QR code, which iPhone linked it. For Apple IDs we also keep the refresh token Apple issues to ShellX, only so that we can revoke ShellX's access when you remove that Apple ID or delete your account.
  > - **Password (older accounts only)** — accounts created before sign-in with Google keep their password until password sign-in is switched off. The server stores only an **argon2id** hash, from which the password cannot be recovered, and deletes it on that day.
  > - When the account was created (and, for older accounts, when the password was last changed).

- **Devices, line 28:** "each time you register or sign in on a device" → "each time you sign in on a device".

- **Access tokens, line 36:** after "stores only its SHA-256 hash," insert "how the device signed in (Google, Apple or a password),".

- **Push token, line 38:** "that phone's push token (FCM token), its platform (iOS or Android)" → "that phone's push token (an Apple Push Notification service device token on iPhone, a Firebase Cloud Messaging token on Android), its platform".

- **IP addresses, line 42:** "to limit sign-in and registration attempts per 60-second window (to stop password guessing and abuse)" → "to limit sign-in attempts per 60-second window (to stop guessing and abuse)".

- **New paragraph after the IP addresses one:**
  > **Sign-in requests** — each sign-in uses a random one-time code that the server keeps, as a SHA-256 hash, for at most 10 minutes. When an iPhone that signed in with a hidden-email Apple ID asks to join your computer's account, the server keeps that request — the Apple ID's identifier and email, the iPhone's name and public key — for at most 24 hours.

- **§3, Push tokens bullet (line 66)** becomes:
  > - **Push tokens.** When you allow notifications, the iPhone app receives a device token from Apple Push Notification service and the Android app a token from Google Firebase Cloud Messaging, and sends it to our server. The server keeps it until you sign out on that phone, delete your account, turn off ShellX notifications in the phone's settings (the next time the app opens), or Apple or Firebase reports the token is no longer valid.

- **§5, first bullet, second sentence** becomes:
  > The Android app uses Firebase Cloud Messaging only to receive push notifications, and none of Firebase's analytics services; the iPhone app receives them from Apple Push Notification service directly.

- **§7, at the start of the second paragraph:**
  > When you sign in, Google (Sign in with Google) or Apple (Sign in with Apple) confirms who you are under its own policy and tells ShellX the account identifier and email described in section 1.

- **§8, Access tokens bullet** becomes:
  > - **Access tokens:** deleted when you sign out on that device, when you remove the Apple ID it signed in with, or when the account is deleted; a token expires after 90 days without use. Older password sessions are deleted when password sign-in is switched off.

  In the push tokens bullet, "or when Firebase reports" → "or when Apple or Firebase reports". Add after the pairing records bullet:
  > - **Sign-in methods:** until you remove that Apple ID (desktop app → Settings → Account) or delete the account; the Google sign-in of an account is kept as long as the account exists.
  > - **Sign-in codes:** at most 10 minutes. **Requests to link an Apple ID through your computer:** at most 24 hours.
  > - **Passwords of older accounts:** deleted when password sign-in is switched off.

- **§9, the first paragraph** (line 113) becomes:
  > You can delete your ShellX account yourself in the iPhone or Android app: open **Settings › Account › Delete Account…**, read what will be deleted, then sign in again with Google or Apple to confirm. Deletion takes effect immediately and cannot be undone: the server permanently deletes the account with all of its devices, sign-in methods, access tokens, push tokens and pairing records, and every device is signed out. If an Apple ID could sign in to the account, the server also asks Apple to revoke ShellX's access to it. The phone then clears its own data, as when you sign out. A desktop app that was signed in shows the sign-in screen again; its Settings → Account links to this section.

  The email, logs and on-device paragraphs stay.

- **§10, second paragraph** becomes:
  > In the apps you can view your devices, revoke or remove pairings, see the Google account and Apple IDs that can sign in and remove an Apple ID (desktop app → Settings → Account), sign out, and delete your account (iPhone and Android app).

- **§11:** replace "passwords are hashed with argon2id;" with "sign-ins are checked against the public keys Google and Apple publish, and each one-time sign-in code works once; the remaining passwords of older accounts are hashed with argon2id until password sign-in is switched off;".

Localization audit (`skills/cmux-localization/SKILL.md`), to report at hand-off:
- the changed surface is one English page;
- the site is English only by design (`web/tests/site.test.mjs`), so no other locale exists;
- the relay's new `message` texts are English API messages that clients map by `code`.

- [ ] **Step 4: Run the tests to see them pass**

Run: `(cd web && npm run build)`
Expected: Astro finishes the build, then node:test ends with `# fail 0`.

- [ ] **Step 5: Commit**

```bash
git add web/src/pages/privacy.md web/tests/site.test.mjs
git commit -m "docs(web): privacy policy for Google and Apple sign-in, APNs/FCM tokens and account deletion"
```

---

### Task 16: Verify and hand off

**Files:** none (unless review findings need fixes).

- [ ] **Step 1: Run the full verification in the worktree**

```bash
(cd relay && npm ci && npm test && npm run typecheck && npm run build)
node --test deploy/tests/*.test.mjs
(cd web && npm run build)
node scripts/shellx/share-e2e.mjs
python3 scripts/verify-local.py
```

Expected:
- the relay has no failed test file, no `error TS` line, and the build succeeds;
- both node:test runs end with `# fail 0`; tests that need a missing `sqlite3` CLI are reported as skipped;
- share-e2e ends with `share-e2e: <n> checks passed`;
- verify-local prints `PASSED: <n>/<m> selected checks ran.`

Fix anything red before continuing.

- [ ] **Step 2: Whole-branch review**

Follow `skills/cmux-review/SKILL.md` "Default pre-merge review" and superpowers:requesting-code-review. Give a fresh review subagent:
- the task intent (this plan's Goal);
- `git merge-base develop HEAD` as base and `HEAD`;
- the exact diff.

Ask for correctness first, specifically:
- the §6.3 rules and the `PASSWORD_LOGIN` interplay;
- nonce single use;
- the exactly-once handoff;
- migration safety on a copy of a populated database;
- log hygiene;
- then repository rules.

Fix confirmed findings and rerun Step 1's relay command. Get a fresh review of a non-trivial repair delta.

- [ ] **Step 3: Land on develop (contracts §1; standing user directive, memory `shellx-working-preferences`)**

```bash
cd /Users/lehuuphu/Documents/myProjects/shellx
git branch --show-current                                                    # must print develop; otherwise stop
git status --short --untracked-files=no -- relay web deploy scripts         # must print nothing; stop otherwise (the user's own edits elsewhere, e.g. docs/, are fine)
git fetch origin && git merge --ff-only origin/develop
git merge --no-ff feat/shellx-signin-1a-relay -m "Merge branch 'feat/shellx-signin-1a-relay' into develop"
(cd relay && npm ci && npm test && npm run typecheck)
git push origin develop
```

Expected: the merge commit is created, the relay suite passes on `develop`, and the push succeeds.

If the merge conflicts (plan 3F also edits `relay/`), resolve it keeping both sides' behavior, rerun the relay suite, and get a fresh review of the resolution before pushing.

Never merge to `main`, deploy, run `deploy/vps-deploy.sh`, upload to a store or publish a release: those steps are plan 1D's and the user's.

This plan has no **USER** step. The Google Cloud and Apple Developer setup, the `.env` values on the VPS, the deploy and the cut-over date belong to plan 1D.

- [ ] **Step 4: Report**

Report:
- the merge SHA;
- the verification results;
- the localization audit of Task 15;
- the "Spec notes" and "Contract additions" below, which plans 1B, 1C, 1D and 3D need.

If a cmux socket is available, `cmux notify` the user that 1A is on `develop`.

---

## Spec notes

1. **Identity id.** S1 §6.1 makes `(provider, subject)` the primary key. The plan uses `id TEXT PRIMARY KEY` (the API's `identity_id`, needed by `DELETE /v1/account/identities/:identity_id`) with `UNIQUE (provider, subject)`.
2. **Two extra columns.**
   - `identities.apple_client_id`: revocation needs the bundle id the refresh token was issued to.
   - `tokens.identity_id` (`ON DELETE CASCADE`): removing an Apple ID deletes exactly the tokens minted with it (S1 §6.4).
3. **Nonce store.** It is a table, `auth_nonces` (SHA-256 only), capped at 50 000 live rows, beyond which it answers 429.
4. **Linking an account that still has a password.** S1 §9 ("nối tài khoản có mật khẩu thì xoá mật khẩu và đăng xuất thiết bị khác") contradicts §6.3b ("thiết bị khác và mật khẩu không đổi"). The plan reconciles them:
   - the in-place link keeps the password and the other devices;
   - linking by email into an account that still has a password, reachable only with `PASSWORD_LOGIN=off`, clears the password and that account's password sessions (Task 5). That is safe even if the cut-over script has not run yet.
5. **When the iPhone's session is created.** S1 §6.4 step 5 creates the iPhone's token in the approval transaction. The plan creates the device, identity and grant there, but mints the token on the first status call after approval, exactly once (see Architecture). No session token is ever stored in clear.
6. **Apple IDs without a verified email are refused.** S1 requires `email_verified` on every token, which shuts out "Sign in with Apple at Work & School" accounts.
7. **Device kinds.** Google sign-in accepts `device.kind` `desktop` or `mobile`; `agent` gets 400 `invalid_device`. The Flutter agent is gone, and an agent device could re-add a password through `POST /v1/auth/password`.
8. **Recycled addresses.** Suppose a Google token's email matches an account that already has a Google sign-in (for example a recycled Workspace address). The plan answers 401 `invalid_credentials` instead of linking: one Google per account (S1 §3), and no takeover.
9. **Apple email matching a password account (resolved 2026-11-07).** Instead of 409 `switch_from_signed_in_device`, `POST /v1/auth/apple` answers 202 `link_required` in that case: the QR link attaches the Apple ID to the Mac's account after the Mac's Allow, so there is no dead end before the cut-over and nothing is linked by email to a password account.
10. **Rate limits.**
    - Removed: `registerIp`.
    - Added: `nonceIp`, 30/IP/60 s.
    - Google, Apple and Apple-link requests share `loginIp` (S1 §6.2).
    - `google/link` and `apple/link/status` get no limiter, since contracts §2 lists no 429 for them.
11. **Removing `reset-password` (S1 §6.9)** is left to the cut-over plan (1D). Passwords are live in phase 1. After the cut-over, a reset password changes nothing: login answers 410, and linking by email ignores and clears it.
12. **Other harnesses.** S1 §9 also names `scripts/shellx/remote-e2e/harness.py` and `shellx-core/fake-api`; both drive shellx-core and belong to 1B. 1A provides `TEST_IDP_*` and `relay/scripts/test-idp.ts`.
13. **Website, other pages.** `web/src/pages/terms.md` (§2, §3, §8: passwords, "Settings → Delete account") and the homepage copy in `web/src/i18n/ui.ts` (`step1`, `security3`, `faqA3`) still describe passwords. They are left for 1D's cut-over pass.
14. **Website, publish timing.** The privacy page now promises in-app deletion on iPhone and Android, which becomes true only when 1C and 3D ship. 1D should publish the website no earlier than the iPhone build that has deletion.
15. **Smoke account.** Its email is `relay2-smoke@smoke.invalid`. `.invalid` is a reserved top-level domain, so no Google or Apple account can claim it by email.
16. **Revocation without a refresh token.** Apple revocation is skipped, and logged, when no refresh token was ever stored (every exchange failed), because the contracts' `DELETE /v1/account` body has no authorization code.

## Contract additions

For the owner of the contracts file to merge into §2. They are written here instead because this plan may not edit that file.

1. `GET /v2/phone-pairings?role=target&apple_links=1` lists Apple-link requests (`links_apple_id: true`). Without the parameter they are left out, so a desktop ≤ 1.7.0 never shows a request whose sheet lacks the Apple warning (S1 §8). Owner 1A; consumer 1B's Mac, which must send the parameter.
2. `POST /v2/phone-pairings/:id/approve`, for an Apple-link request, can also answer:
   - 409 `identity_in_use`: that Apple ID already signs in to another account;
   - 410 `pairing_expired`: also when the link token expired.
3. `POST /v1/auth/apple` never answers `switch_from_signed_in_device`: an Apple email matching a password account gets 202 `link_required` (Spec note 9). `POST /v1/auth/apple/link` can also answer 400 `bad_request` (malformed key or proof).
4. On `POST /v1/auth/google/link`, `identity_in_use` also covers "this account already has a different Google account".
5. `link_token` is a 43-char base64url string. `/v1/auth/apple/link/status` hands out the approved session exactly once; a later call with that link token answers 401 `invalid_credentials`. The phone recovers by signing in with Apple again.
6. Test identity provider tokens:
   - claims: `iss` = `TEST_IDP_ISSUER`, `aud` = `shellx-test-idp`, `sub`, `email`, `email_verified: true`, the raw `nonce`, `iat`, `exp`;
   - signed ES256 or RS256 with a key from `TEST_IDP_JWKS_PATH` (`{"keys": [public JWK with kid and alg]}`);
   - accepted by `POST /v1/auth/google`, `/v1/auth/google/link` and `DELETE /v1/account`, as provider `test` (`auth_method` `test`, also used by the smoke token);
   - helper: `relay/scripts/test-idp.ts` (`createTestIssuer`, `testIdTokenClaims`).
7. In-app deletion label: **Settings › Account › Delete Account…** (Vietnamese "Cài đặt › Tài khoản › Xoá tài khoản…"), the phone apps' strings (contracts §12). The privacy page, which is the Google Play deletion URL, describes it with exactly these words.
8. Operator interface (consumer 1D):
   - `npm run -s mint-smoke-token` prints only the token;
   - `SHELLX_SMOKE_TOKEN` feeds `npm run relay2:smoke`;
   - `npm run -s password-cutover [-- --yes]` refuses unless `PASSWORD_LOGIN=off`;
   - startup events: `google_sign_in_disabled`, `apple_siwa_enabled` / `apple_siwa_disabled`, `test_idp_enabled`, `password_login_off`.

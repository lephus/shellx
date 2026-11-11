# ShellX Email-Code Sign-in: Relay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Execution (decided):** one implementer runs Tasks 0–10 in order with superpowers:executing-plans on branch `feat/shellx-email-code-signin-relay`, then the whole branch is reviewed once. The implementer stops before landing; the orchestrator merges.

**Goal:** The relay signs a person in with an email address and a 6-digit code it mails through Resend, into the same accounts, devices and sessions as Google sign-in, and lets an account be deleted with such a code.

**Architecture:** Two routes in a new Hono sub-app `routes/email-sign-in.ts` (mounted at `/v1/auth/email`). `auth/email-codes.ts` owns the challenges: it stores only SHA-256 hashes and redeems a challenge in one synchronous transaction, so a challenge is counted, compared and burnt atomically. The code is redeemed first and committed; the account is then resolved in a second transaction with the existing `matchAccount`, so a right code is spent whatever the answer. Mail goes through an `EmailGateway` injected by `AppDeps.email` (`ResendClient` in production, a fake in every test). Migration 0011 rebuilds `identities` and `tokens` under the existing `-- migrate: foreign_keys=off` directive.

**Tech Stack:** Node ≥ 22, TypeScript 5.9 (`module: nodenext`, `verbatimModuleSyntax`), Hono 4, better-sqlite3, vitest ~4.1; deploy tests use `node:test`. No new dependency.

**Spec:** `docs/superpowers/specs/2026-11-10-shellx-email-code-sign-in-design.md` (Vietnamese; called S4 here): §4, §5, §6 and the relay lines of §2, §8, §9, §10. The user answered its §11: (1) all four apps; (2) yes, a code signs in to the account created with Google for the same verified address; (3) sender `ShellX <sign-in@shellx.pro>` through `EMAIL_FROM`; (4) every small default stands. Conventions come from `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` §1–§2 and the earlier relay plan `2026-11-07-shellx-signin-1a-relay.md`.

**How this plan was checked:** every test in this plan was run green against a throwaway reference implementation in a scratch copy of `relay/` (Node 26.11.1, full suite 63 files / 807 tests passed, `tsc` clean, `npm run build` ok); the migration SQL was also applied with the `sqlite3` CLI to a populated 0010 database. Nothing in the repository was changed. The implementation is yours to write from the Interfaces and rules below; the test code is exact.

## Global Constraints

Copied from S4 (translated; identifiers and values unchanged). Every task's requirements include this section.

- **API (S4 §4), verbatim:**

  ```
  POST /v1/auth/email/code     {email, locale?: "en"|"vi"}
    -> 202 {challenge_id, expires_in: 600, resend_in: 60, email}      email normalised (trim, lowercase)
       400 invalid_email | 400 disposable_email | 429 rate_limited
       503 email_sign_in_disabled (the relay has no RESEND_API_KEY)
       502 email_send_failed (Resend failed / took over 10 s; the challenge is deleted)

  POST /v1/auth/email/verify   {challenge_id, code, device}           device as for /v1/auth/google (kind ≠ agent)
    -> 200 {user_id, device_id, token, email}                          the exact shape of /v1/auth/google
       401 invalid_code          wrong code; the challenge stays and one more guess is counted
       410 code_expired          no such challenge, expired, already used, or this was the 5th wrong guess (challenge deleted)
       409 switch_from_signed_in_device   a password account while PASSWORD_LOGIN=on (like Google)
       400 invalid_device | 429 rate_limited

  DELETE /v1/account           bearer + {challenge_id, code}           a third way to confirm
    -> 204; 401 invalid_code | 410 code_expired | 401 reauth_required (the code's email is not the account's email)
  ```

- **Errors:** the shape stays `{"error":{"code","message"}}`; bodies are limited to 16 KiB (`jsonBodyLimit`) like the other sign-in routes.
- **Challenge id:** 32 random bytes, base64url (43 characters, `generateToken()`); the database keeps only `sha256(challenge_id)`.
- **Code:** 6 digits from `crypto.randomInt(0, 1_000_000)`, zero-padded; the database keeps only `sha256(challenge_id + ":" + code)`; hashes are compared with `timingSafeEqual`.
- **Lifetime:** 10 minutes (600 s); at most 5 guesses per code; only the newest code of an address is valid (asking for a new one deletes that address's older challenge); at most 50 000 live challenges (→ 429), like nonces.
- **Limiters** (the existing `SlidingWindowLimiter`, added to `RateLimiters` and to the tests' `unlimited`): `emailCodeIp` 10 per minute per IP; `emailCodeEmail` 3 per minute **and** 10 per hour per email (two limiters, windows 60 s and 3 600 s); `/verify` uses the existing `loginIp` 10 per minute; `DELETE /v1/account` keeps `loginEmail` 5 per email (`relay/src/routes/account.ts`).
- **Addresses:** checked by `checkEmail` (`relay/src/auth/email.ts`): bad syntax → `invalid_email`; a disposable domain → `disposable_email`, also when the account already exists. Matching is `normalizeEmail` only (trim + lowercase); Gmail dots and `+tag` are never folded (plan 1A).
- **No enumeration:** 202 for every valid address; nothing tells whether an account exists (the first `/verify` creates it).
- **Mail:** no link. Subject `Your ShellX sign-in code is 123456` / `Mã đăng nhập ShellX của bạn là 123456`; body (text + minimal HTML, no image): enter the code within 10 minutes; if you did not ask for it, ignore the mail, nobody gets in without the code; ShellX never asks for this code. Sender: `EMAIL_FROM`. Language: `vi` → Vietnamese, anything else English.
- **Logs:** `logMeta` only: `email_code_sent {locale}`, `email_code_refused {reason}`, `sign_in {provider: "email", via}`, `email_send_failed {status|error}`. Never an email address, a code, a challenge, an IP.
- **Identity:** `provider = 'email'`, `subject` = the normalised address. `IdentityProvider` and `AuthMethod` gain `"email"`; `tokens.auth_method = 'email'`, `tokens.identity_id` points at that identity.
- **Accounts (S4 §5):** resolution reuses `matchAccount` with a synthetic `VerifiedIdToken {provider: "email", subject: email, email, isPrivateEmail: false}`:

  | `matchAccount` | Google (unchanged) | Email (new) |
  | --- | --- | --- |
  | `identity` | sign in, update `last_used_at` | like Google |
  | `switch_required` (PASSWORD_LOGIN=on, password still set) | 409 | 409 |
  | `email`, `hasPrimary` = it has a Google identity | 401 (recycled address) | **link**: add the `email` identity; the account keeps Google and email |
  | `email`, no `hasPrimary` | drop the password + add the identity | like Google (narrowed by Ruling 12) |
  | `none` | new account + identity | like Google |

- **Schema:** migration `relay/migrations/0011_email_sign_in.sql` (`-- migrate: foreign_keys=off`): `provider IN ('google','apple','email','test')`, `auth_method IN ('password','google','apple','email','test')`; `identities_one_primary` → `WHERE provider IN ('google','test')`; new `identities_one_email` `UNIQUE (user_id) WHERE provider = 'email'`; the `email_codes` table exactly as in S4 §5 (Task 1 has it).
- **Gateway:** `EmailGateway { send(message: {to, subject, text, html, idempotencyKey}): Promise<{ok: true} | {ok: false, status?, error?}> }`. `ResendClient` (`relay/src/email/resend.ts`): `POST https://api.resend.com/emails`, `Authorization: Bearer <RESEND_API_KEY>`, `Idempotency-Key`, body `{from, to: [email], subject, text, html}`, `AbortSignal.timeout(10_000)`, injectable `fetch` like `AppleRestClient`. 2xx is sent; anything else → `email_send_failed`; the relay never retries.
- **Configuration:** `RESEND_API_KEY` (a secret: only in the VPS's `.env`, passed through `deploy/docker-compose.yml`) and `EMAIL_FROM` (`ShellX <sign-in@shellx.pro>`). Both set → on (`logMeta("email_sign_in_enabled")`); both missing → off (`/code` answers 503 `email_sign_in_disabled`); exactly one → `ConfigError`, the relay stops (like the `TEST_IDP_*` pair).
- **Anti-goals (S4 §2):** a code that can be guessed online; a relay that does not start without Resend; an email address in a log; two account models side by side; an old app broken by the new relay (old shapes and old error codes stay).
- **Never:** send real mail or need a real key in a test or a step (none exists on this machine); write a secret into a file or a command; deploy; push or merge to `main`; change anything under `web/`; quit, relaunch or replace the user's running ShellX or cmux.
- **Commands:**
  - one test file: `(cd relay && npx vitest run test/<name>.test.ts)`;
  - relay: `(cd relay && npm test && npm run typecheck)`;
  - deploy: `node --test deploy/tests/compose.test.mjs`;
  - on this Mac the user's global instructions route test, build and install output through `toknix run <command>`.
- **Commits:** two per task, as `CLAUDE.md` "CI, review and merge" asks: first the failing tests (`test(relay): …`), after you have seen them fail; then the implementation (`feat(relay): …`), after the same command passes. Always `git add <explicit paths>`. Note the red and the green result of each task's focused command for the final report.

## Review Focus

Security is the point of this part. Each line names the condition, what must happen, and the task whose tests pin it.

1. **Is this address registered?** `/code` answers the same 202, sends the same mail and reads no account, whether or not the address has one. Task 5 (`answers the same 202 whether or not the address has an account`).
2. **Timing of the comparison.** The stored hash is compared with `timingSafeEqual` on two 32-byte digests, once per guess, for right and wrong codes alike; it is never compared in SQL or with `===`. Task 4 (`email-codes-compare.test.ts`).
3. **More than five guesses, also in parallel.** A guess is counted before it is compared; the fifth wrong one deletes the challenge; nine parallel wrong guesses get exactly four 401. Tasks 4 and 6 (`counts every guess…`, `…compares at most five concurrent guesses`).
4. **A used or expired challenge.** It never signs in again: after a success, at or after 600 s, after a newer code for that address, after a failed send, after a 409. Tasks 4, 5, 6.
5. **Secrets at rest and in logs.** The row holds only the two SHA-256 values; no log line has the address, the code, the challenge id or the IP. Tasks 4, 5 and 8 (`stores only SHA-256…`, `logs events without…`, `signin-logs.test.ts`).
6. **Another spelling of the same address.** The limiter keys, the stored `email`, the identity `subject` and the account match all use the one `checkEmail` result: `Ann.Lee@Example.com`, ` ann.lee@example.com ` and `ANN.LEE@EXAMPLE.COM` share one budget and one account. Tasks 5 and 6.
7. **An account found by email that the code must not open.** A code attaches only to an account whose address Google verified (it has a Google sign-in), or to one with no sign-in left at all, and then only after its password and every earlier session are removed. A working password, or an Apple ID attached under a never-verified address, answers 409 and changes nothing. It never matches a dot or `+tag` variant, nor an address that only an identity row carries. Task 6 (the five tests from `links into the account created with Google…` to `refuses (409) an account whose address was never verified…`).
8. **The same challenge verified twice at once.** Six parallel verifies with the right code: one 200, five 410; one user, one device, one token. Tasks 4 and 6.
9. **A code with leading zeros** (`004217`) is mailed, stored and verified as a six-character string; `4217` and the number `4217` are wrong guesses. Tasks 5 and 6.
10. **A double tap on Send.** Racing requests for one address leave exactly one live challenge; the older `challenge_id` answers 410. Task 5.

## Rulings

Where S4 and the code disagree the plan follows the code; where S4 is silent the plan decides. One line each.

1. S4 names one limiter `emailCodeEmail` for two windows. The plan has `emailCodeEmail` (3 per 60 s) and `emailCodeEmailHour` (10 per 3 600 s), asked in that order, so a call the minute limiter refuses does not use up the hour.
2. `resend_in: 60` is advice for the client's button. The relay enforces only the limiters (a 60 s server lock would make "3 per minute" meaningless).
3. `VerifiedIdToken` has a required `audience` that S4's synthetic token omits: it is `""`.
4. The code is redeemed in its own committed transaction before the account is resolved, so a right code is spent even when the answer is 409 (S4 does not say).
5. `/verify` checks the device first: 400 `invalid_device` spends no guess. A `code` that is not the right six-digit string (a number, 4 digits, a space) is a wrong guess: 401, counted. A missing, malformed or unknown `challenge_id` is 410.
6. A challenge is dead at `now >= expires_at`, like a nonce. Expired rows are deleted on every `/code`, `/verify` and delete-by-code call (S4: only on `/code`), so an unused address does not sit in the table until the next request for a code.
7. An unknown or missing `locale` means English; it is never a 400.
8. On `/code` the 503 comes first, before the IP limiter and before the body is read. `/verify` and delete-by-code have no 503: with the feature off no challenge can be made, so they answer 410 (a challenge made in the 10 minutes before a restart that switched the feature off still works).
9. Configuration lives in `Config.emailSignIn: {resendApiKey, from} | null`, checked in `loadConfig` (where `TEST_IDP_*` is checked). Added: `EMAIL_FROM` must be `address` or `Name <address>`, else `ConfigError` at start instead of a 502 on every request. No error message contains the key.
10. `ResendClient` also sends `User-Agent: shellx-relay` (Resend's API reference: requests without a User-Agent get 403; read 2026-11-11) and sets `redirect: "error"`. Its timeout is a constructor option so the test does not wait 10 s. It never logs; the route logs `email_send_failed`.
11. Log details S4 leaves open: `email_code_refused` reasons are `disabled`, `rate_limited_ip`, `invalid_email`, `disposable_email`, `rate_limited_email`, `too_many_live`; a refused `/verify` logs plan 1A's `sign_in_refused {provider: "email", reason}` with `invalid_code`, `code_expired`, `switch_required` or `other_sign_in`; start-up logs `email_sign_in_enabled` or `email_sign_in_disabled`; `/google/link` logs `identity_removed` when it drops the email sign-in.
12. **Narrower than S4 §5, row "`email`, no `hasPrimary`".** `users.email` of a legacy password account was never verified (registration sent no mail). The plan lets a code claim such an account only when it has no identity at all, and then removes the password and every session of the account, not just password sessions. If it has an identity (only an Apple ID is possible there), the answer is 409 `switch_from_signed_in_device` and nothing changes: otherwise whoever registered that address first would keep an Apple session in the account the mailbox owner just entered. To go back to S4's literal row, delete the identity check and its test (Task 6).
13. Delete by code compares the code's address with `users.email` (S4: "the account's email"). An ID token in the same body wins. A code for another address answers `reauth_required` and is spent.
14. S4 calls the challenge id "128 bit"; `generateToken()` gives 256 bits. No effect.
15. S4 lists four `!= 'apple'` sites under one rule, but its own next paragraph gives the identity-removal site a different list. The plan: `identity.ts:31` and `sign-in.ts:115` → `IN ('google', 'test')`; the index in the migration → `IN ('google', 'test')`; `identities.ts:55` → `IN ('google', 'test', 'email')`, which changes no behaviour (once `email` exists, `!= 'apple'` already means that list) and only makes the rule explicit. The JavaScript test `row.provider !== "apple"` at `identities.ts:54` stays.
16. `email_codes_email` stays a plain index as S4 writes it. "One live challenge per address" is held by delete + insert in one transaction and pinned by tests, including racing requests.
17. At the 50 000 cap the order is: delete expired rows, check the cap, delete the address's older challenge, insert. A refusal at the cap changes nothing.
18. Six tests assert the complete list of migrations (`db.test.ts:104`, `versions.test.ts:128`, `migrate-0005.test.ts:36`, `migrate-0007.test.ts:28`, `migrate-0008.test.ts:18`, `migrate-0010.test.ts:32`); each gains `0011_email_sign_in.sql`.
19. Mail copy: S4's "ShellX never asks for this code" becomes "ShellX will never ask you for this code by email, phone or chat", because the app's own sign-in screen does ask for it.
20. Two relay messages are reworded, codes unchanged: `last_google_identity` → "An account must keep at least one way to sign in", `reauth_required` → "Confirm with a fresh sign-in or an email code". Clients localise by code.
21. `scripts/shellx/share-e2e.mjs` builds its own config and limiter set by name; it gains `emailSignIn: null` and the three limiter names.
22. An account that kept its password after linking Google in place answers 409 to an email code while `PASSWORD_LOGIN=on` (`switch_required` is checked first), although its Google sign-in works. S4 accepts this until the cut-over.
23. The process-level test starts a relay with a placeholder key to see `email_sign_in_enabled`. It never calls `/code` on that process, so no request leaves the machine.
24. This plan edits neither `docs/superpowers/HANDOFF-shellx-mobile.md` nor `web/` (see Follow-ups).

## File map

| File | Responsibility |
| --- | --- |
| `relay/migrations/0011_email_sign_in.sql` | wider CHECKs on `identities.provider` and `tokens.auth_method`, the two partial unique indexes, `email_codes` |
| `relay/src/auth/email-codes.ts` | generate a code; issue, discard and redeem a challenge (hashes only, attempts, expiry, cap) |
| `relay/src/email/resend.ts` | `EmailMessage`, `EmailSendResult`, `EmailGateway`, `ResendClient` |
| `relay/src/email/sign-in-code.ts` | the mail's subject, text and HTML in English and Vietnamese |
| `relay/src/routes/email-sign-in.ts` | `POST /v1/auth/email/code`, `POST /v1/auth/email/verify` |
| `relay/src/routes/account.ts` | `DELETE /v1/account` also takes `{challenge_id, code}` |
| `relay/src/routes/sign-in.ts`, `relay/src/routes/identities.ts`, `relay/src/auth/identity.ts` | Google and email sign-ins in one account |
| `relay/src/config.ts`, `relay/src/http/errors.ts`, `relay/src/auth/rate-limit.ts`, `relay/src/app.ts`, `relay/src/server.ts` | settings, error codes, limiters, wiring, start-up event |
| `relay/test/fake-email.ts` | `FakeEmailGateway`: records mail, hands tests the code |
| `relay/test/helpers.ts` | `requestEmailCode`, `signInEmail`, `emailSession` |
| `deploy/docker-compose.yml`, `deploy/README.md`, `relay/README.md` | env passthrough and runbooks |

---

### Task 0: Worktree and baseline

**Files:** none.

- [ ] **Step 1: Create the worktree** (superpowers:using-git-worktrees, with this location and branch)

```bash
git -C /Users/richard/Documents/helper/shellx worktree add .worktrees/email-code-signin-relay -b feat/shellx-email-code-signin-relay develop
cd /Users/richard/Documents/helper/shellx/.worktrees/email-code-signin-relay
```

Every later path is relative to this worktree. Do not touch the main checkout or the two other worktrees under `.worktrees/`.

- [ ] **Step 2: Read the inputs**

S4 and the contracts file are in the worktree. This plan is not committed: read it at `/Users/richard/Documents/helper/shellx/docs/superpowers/plans/2026-11-11-shellx-email-code-signin-relay.md`; never copy or commit it on this branch.

- [ ] **Step 3: Install and take the baseline**

```bash
(cd relay && npm ci)
(cd relay && npm test && npm run typecheck)
node --test deploy/tests/compose.test.mjs
```

Expected (2026-11-11, Node 26.11.1): vitest `Test Files  57 passed | 1 skipped (58)` and `Tests  747 passed | 7 skipped (754)`; `tsc` prints nothing; node:test `pass 20`, `fail 0`. If the untouched branch fails, stop and report; do not fix unrelated failures.

---

### Task 1: Migration 0011 and the `email` provider

**Files:**
- Create: `relay/migrations/0011_email_sign_in.sql`
- Modify: `relay/src/auth/providers.ts:2`, `relay/src/auth/session.ts:22`
- Test: `relay/test/migrate-0011.test.ts` (new); the six lists of Ruling 18

**Interfaces:**
- Produces: `IdentityProvider = "google" | "apple" | "email" | "test"`; `AuthMethod = "password" | "google" | "apple" | "email" | "test"`; table `email_codes (id, challenge_hash, code_hash, email, attempts, created_at, expires_at)`; indexes `identities_one_primary`, `identities_one_email`.

- [ ] **Step 1: Write the failing tests**

`relay/test/migrate-0011.test.ts`:

```ts
import { copyFileSync, mkdirSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { authenticate } from "../src/auth/session.js";
import { hashToken } from "../src/auth/tokens.js";
import { Db } from "../src/db/db.js";
import { migrate, MIGRATIONS_DIR } from "../src/db/migrate.js";
import { tempDir } from "./helpers.js";

const DEVICE = "INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at) VALUES (?, 'u1', ?, 'n', ?, ?, 1)";
const IDENTITY = "INSERT INTO identities (id, provider, subject, user_id, email, linked_via_device_id, created_at, last_used_at) VALUES (?, ?, ?, ?, ?, ?, 1, 1)";
const TOKEN = "INSERT INTO tokens (token_hash, device_id, created_at, last_used_at, auth_method, identity_id) VALUES (?, ?, 1, ?, ?, ?)";

describe("migration 0011", () => {
  it("keeps every identity and token of a populated 0010 database, with its method, identity and cascade", async () => {
    const oldDir = join(tempDir(), "v10");
    mkdirSync(oldDir);
    for (const name of readdirSync(MIGRATIONS_DIR)) if (name < "0011") copyFileSync(join(MIGRATIONS_DIR, name), join(oldDir, name));
    const db = Db.open(join(tempDir(), "v10.db"));
    try {
      migrate(db, oldDir);
      db.run("INSERT INTO users VALUES ('u1', 'a@example.com', NULL, 1, 1)");
      db.run(DEVICE, "dm", "desktop", "macos", new Uint8Array([1]));
      db.run(DEVICE, "dp", "mobile", "ios", new Uint8Array([2]));
      db.run(IDENTITY, "i-g", "google", "g1", "u1", "a@example.com", null);
      db.run(IDENTITY, "i-a", "apple", "a1", "u1", "h@privaterelay.appleid.com", "dp");
      const google = "google-session-0123456789abcdef0123456789ab";
      db.run(TOKEN, await hashToken(google), "dm", Date.now(), "google", "i-g");
      db.run(TOKEN, await hashToken("apple-session"), "dp", Date.now(), "apple", "i-a");
      db.run(TOKEN, await hashToken("legacy-session"), "dp", Date.now(), "password", null);
      const snapshot = () => [db.all("SELECT * FROM identities ORDER BY id"), db.all("SELECT * FROM tokens ORDER BY auth_method")];
      const before = snapshot();

      expect(migrate(db)).toEqual(["0011_email_sign_in.sql"]);

      expect(snapshot()).toEqual(before);
      expect(await authenticate(db, google, Date.now())).toMatchObject({ deviceId: "dm", kind: "desktop" });
      expect(db.get("PRAGMA foreign_keys")).toEqual({ foreign_keys: 1 });
      expect(db.all("PRAGMA foreign_key_check")).toEqual([]);
      const indexes = db.all<{ name: string }>(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name IN ('identities', 'tokens', 'email_codes') AND name NOT LIKE 'sqlite_%' ORDER BY name",
      );
      expect(indexes.map((r) => r.name)).toEqual([
        "email_codes_email", "email_codes_expires_at", "identities_one_email", "identities_one_primary", "identities_user_id",
        "tokens_device_id", "tokens_identity_id",
      ]);
      db.run("DELETE FROM identities WHERE id = 'i-a'");
      expect(db.all("SELECT auth_method FROM tokens ORDER BY auth_method")).toEqual([{ auth_method: "google" }, { auth_method: "password" }]);
    } finally {
      db.close();
    }
  });

  it("allows an email sign-in beside Google and Apple: one per account, one account per address, tokens of method email", () => {
    const db = Db.open(join(tempDir(), "v11.db"));
    try {
      migrate(db);
      db.run("INSERT INTO users VALUES ('u1', 'a@example.com', NULL, 1, 1)");
      db.run("INSERT INTO users VALUES ('u2', 'b@example.com', NULL, 1, 1)");
      db.run(DEVICE, "dm", "desktop", "macos", new Uint8Array([1]));
      const identity = (id: string, provider: string, subject: string, userId = "u1") => db.run(IDENTITY, id, provider, subject, userId, "a@example.com", null);
      identity("i-g", "google", "g1");
      identity("i-e", "email", "a@example.com");
      identity("i-a", "apple", "a1");
      expect(() => identity("i-e2", "email", "other@example.com")).toThrow(/UNIQUE/); // one email sign-in per account
      expect(() => identity("i-e3", "email", "a@example.com", "u2")).toThrow(/UNIQUE/); // one account per address
      expect(() => identity("i-t", "test", "t1")).toThrow(/UNIQUE/); // google and test share the one primary slot
      expect(() => identity("i-f", "facebook", "f1")).toThrow(/CHECK/);
      db.run(TOKEN, new Uint8Array([0xaa]), "dm", 1, "email", "i-e");
      expect(() => db.run(TOKEN, new Uint8Array([0xbb]), "dm", 1, "magic", null)).toThrow(/CHECK/);
      db.run("DELETE FROM identities WHERE id = 'i-e'");
      expect(db.get("SELECT COUNT(*) AS n FROM tokens")).toEqual({ n: 0 });
      const code = "INSERT INTO email_codes (id, challenge_hash, code_hash, email, created_at, expires_at) VALUES (?, ?, x'02', 'a@example.com', 1, 600001)";
      db.run(code, "c1", new Uint8Array([1]));
      expect(db.get("SELECT attempts FROM email_codes")).toEqual({ attempts: 0 });
      expect(() => db.run(code, "c2", new Uint8Array([1]))).toThrow(/UNIQUE/);
    } finally {
      db.close();
    }
  });
});
```

In each of the six lists of Ruling 18, add `"0011_email_sign_in.sql"` after `"0010_identities.sql"`.

- [ ] **Step 2: Run them to see them fail**

Run: `(cd relay && npx vitest run test/migrate-0011.test.ts test/db.test.ts test/versions.test.ts test/migrate-0005.test.ts test/migrate-0007.test.ts test/migrate-0008.test.ts test/migrate-0010.test.ts)`
Expected: FAIL in all seven files: `migrate(db)` returns no `0011_email_sign_in.sql`, and the `email` identity fails the old CHECK.

- [ ] **Step 3: Commit the failing tests**

```bash
git add relay/test/migrate-0011.test.ts relay/test/db.test.ts relay/test/versions.test.ts relay/test/migrate-0005.test.ts relay/test/migrate-0007.test.ts relay/test/migrate-0008.test.ts relay/test/migrate-0010.test.ts
git commit -m "test(relay): migration 0011 widens the identity and token CHECKs and adds email_codes"
```

- [ ] **Step 4: Implement**

`relay/migrations/0011_email_sign_in.sql`, exactly (`identities` first: `tokens.identity_id` refers to it by name):

```sql
-- migrate: foreign_keys=off
-- Sign in with an email code (spec 2026-11-10 §5). identities and tokens are rebuilt to widen a CHECK
-- (the 12-step procedure of sqlite.org/lang_altertable.html section 7, as in 0005 and 0010; foreign keys
-- are off). identities goes first: tokens.identity_id refers to it by name.
CREATE TABLE identities_new (
  id                   TEXT PRIMARY KEY,                                       -- UUIDv4: the API's identity_id
  provider             TEXT NOT NULL CHECK (provider IN ('google', 'apple', 'email', 'test')),
  subject              TEXT NOT NULL,                                          -- the ID token's sub; for email, the normalized address
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
INSERT INTO identities_new (id, provider, subject, user_id, email, is_private_email, apple_refresh_token, apple_client_id,
                            linked_via_device_id, created_at, last_used_at)
  SELECT id, provider, subject, user_id, email, is_private_email, apple_refresh_token, apple_client_id,
         linked_via_device_id, created_at, last_used_at FROM identities;
DROP TABLE identities;
ALTER TABLE identities_new RENAME TO identities;
CREATE INDEX identities_user_id ON identities (user_id);
-- One Google (or test) sign-in and one email sign-in per account; Apple IDs are not limited.
CREATE UNIQUE INDEX identities_one_primary ON identities (user_id) WHERE provider IN ('google', 'test');
CREATE UNIQUE INDEX identities_one_email ON identities (user_id) WHERE provider = 'email';

CREATE TABLE tokens_new (
  token_hash   BLOB PRIMARY KEY,
  device_id    TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  created_at   INTEGER NOT NULL,
  last_used_at INTEGER NOT NULL,
  auth_method  TEXT NOT NULL DEFAULT 'password' CHECK (auth_method IN ('password', 'google', 'apple', 'email', 'test')),
  identity_id  TEXT REFERENCES identities(id) ON DELETE CASCADE
);
INSERT INTO tokens_new (token_hash, device_id, created_at, last_used_at, auth_method, identity_id)
  SELECT token_hash, device_id, created_at, last_used_at, auth_method, identity_id FROM tokens;
DROP TABLE tokens;
ALTER TABLE tokens_new RENAME TO tokens;
CREATE INDEX tokens_device_id ON tokens (device_id);
CREATE INDEX tokens_identity_id ON tokens (identity_id);

-- One row per pending email code (POST /v1/auth/email/code). Neither the challenge id nor the code is
-- stored: only their SHA-256. A row goes when the code is used, expired, guessed wrong 5 times or replaced.
CREATE TABLE email_codes (
  id             TEXT PRIMARY KEY,                 -- UUIDv4, also the Idempotency-Key sent to Resend
  challenge_hash BLOB NOT NULL UNIQUE,             -- sha256(challenge_id)
  code_hash      BLOB NOT NULL,                    -- sha256(challenge_id || ':' || code)
  email          TEXT NOT NULL,                    -- normalized; lives at most 10 minutes
  attempts       INTEGER NOT NULL DEFAULT 0,
  created_at     INTEGER NOT NULL,
  expires_at     INTEGER NOT NULL
);
CREATE INDEX email_codes_email ON email_codes (email);
CREATE INDEX email_codes_expires_at ON email_codes (expires_at);
```

`relay/src/auth/providers.ts` and `relay/src/auth/session.ts`: add `"email"` to the two unions as in Interfaces. `isPrimaryProvider` stays `google` or `test`.

- [ ] **Step 5: Run the tests to see them pass**

Run: the command of Step 2, then `(cd relay && npm test && npm run typecheck)`.
Expected: `Test Files  7 passed (7)`; the full suite has no failed file; no `error TS` line.

- [ ] **Step 6: Commit**

```bash
git add relay/migrations/0011_email_sign_in.sql relay/src/auth/providers.ts relay/src/auth/session.ts
git commit -m "feat(relay): migration 0011: email identities and tokens, the email_codes table"
```

---

### Task 2: Settings, error codes and limiters

**Files:**
- Modify: `relay/src/config.ts` (interface at 8-58, `loadConfig` at 80-166), `relay/src/http/errors.ts:14-57`, `relay/src/auth/rate-limit.ts`, `relay/test/helpers.ts:23-54`, `scripts/shellx/share-e2e.mjs:179-195`
- Test: `relay/test/config.test.ts`, `relay/test/errors.test.ts`, `relay/test/limiter.test.ts`

**Interfaces:**
- Produces, on `Config`: `emailSignIn: { resendApiKey: string; from: string } | null`.
- Produces, on `Errors`: `invalidCode` (401 `invalid_code`), `codeExpired` (410 `code_expired`), `emailSignInDisabled` (503 `email_sign_in_disabled`), `emailSendFailed` (502 `email_send_failed`).
- Produces, on `RateLimiters`: `emailCodeIp`, `emailCodeEmail`, `emailCodeEmailHour`; constants `EMAIL_CODES_PER_IP = 10`, `EMAIL_CODES_PER_EMAIL = 3`, `EMAIL_CODES_PER_EMAIL_HOUR = 10`, `EMAIL_CODES_HOUR_WINDOW_MS = 3_600_000`.

- [ ] **Step 1: Write the failing tests**

`relay/test/config.test.ts`: add `emailSignIn: null,` to the expected object of `"reads the version variables and applies the defaults"`, and add before the `SHARE_ALLOWED_ORIGIN` test:

```ts
  it("reads the email sign-in settings: both or neither, never the key in an error", () => {
    const KEY = "placeholder-not-a-real-key";
    expect(loadConfig({ ...REQUIRED, RESEND_API_KEY: ` ${KEY} `, EMAIL_FROM: " ShellX <sign-in@shellx.pro> " }).emailSignIn)
      .toEqual({ resendApiKey: KEY, from: "ShellX <sign-in@shellx.pro>" });
    expect(loadConfig({ ...REQUIRED, RESEND_API_KEY: KEY, EMAIL_FROM: "sign-in@shellx.pro" }).emailSignIn?.from).toBe("sign-in@shellx.pro");
    expect(loadConfig({ ...REQUIRED, RESEND_API_KEY: " ", EMAIL_FROM: "" }).emailSignIn).toBeNull();
    for (const half of [{ RESEND_API_KEY: KEY }, { EMAIL_FROM: "ShellX <sign-in@shellx.pro>" }, { RESEND_API_KEY: KEY, EMAIL_FROM: " " }]) {
      expect(() => loadConfig({ ...REQUIRED, ...half })).toThrow("RESEND_API_KEY and EMAIL_FROM must be set together");
    }
    for (const from of ["ShellX", "ShellX <sign-in>", "ShellX <sign-in@shellx.pro", "a@shellx.pro\nBcc: b@shellx.pro"]) {
      const load = () => loadConfig({ ...REQUIRED, RESEND_API_KEY: KEY, EMAIL_FROM: from });
      expect(load).toThrow('EMAIL_FROM must be an email address or "Name <address>"');
      expect(load).not.toThrow(KEY);
    }
  });
```

`relay/test/errors.test.ts`: add these rows to the table:

```ts
  ["invalidCode", 401, "invalid_code"], ["codeExpired", 410, "code_expired"],
  ["emailSignInDisabled", 503, "email_sign_in_disabled"], ["emailSendFailed", 502, "email_send_failed"],
```

`relay/test/limiter.test.ts`: import `EMAIL_CODES_HOUR_WINDOW_MS, EMAIL_CODES_PER_EMAIL, EMAIL_CODES_PER_EMAIL_HOUR, EMAIL_CODES_PER_IP` from `../src/auth/rate-limit.js` and add inside `describe("createRateLimiters (production wiring)")`:

```ts
  it("limits email codes to 10 per IP and 3 per address per 60 s, and to 10 per address per hour", async () => {
    expect([EMAIL_CODES_PER_IP, EMAIL_CODES_PER_EMAIL, EMAIL_CODES_PER_EMAIL_HOUR, EMAIL_CODES_HOUR_WINDOW_MS]).toEqual([10, 3, 10, 3_600_000]);
    const t = clock();
    const limiters = createRateLimiters({ rateLimitsEnabled: true }, t.now);
    const count = async (limiter: { limit(k: string): Promise<boolean> }, key: string) => {
      let n = 0;
      while (n < 100 && (await limiter.limit(key))) n++;
      return n;
    };
    expect(await count(limiters.emailCodeIp, "198.51.100.1")).toBe(10);
    expect(await count(limiters.emailCodeEmail, "a@example.com")).toBe(3);
    expect(await count(limiters.emailCodeEmailHour, "a@example.com")).toBe(10);
    expect(await limiters.emailCodeEmail.limit("b@example.com")).toBe(true); // per address
    t.advance(RATE_WINDOW_MS);
    expect(await limiters.emailCodeIp.limit("198.51.100.1")).toBe(true);
    expect(await limiters.emailCodeEmail.limit("a@example.com")).toBe(true);
    expect(await limiters.emailCodeEmailHour.limit("a@example.com")).toBe(false); // an hour, not a minute
    t.advance(EMAIL_CODES_HOUR_WINDOW_MS - RATE_WINDOW_MS);
    expect(await limiters.emailCodeEmailHour.limit("a@example.com")).toBe(true);
    const off = createRateLimiters({ rateLimitsEnabled: false });
    for (let i = 0; i < 20; i++) {
      for (const limiter of [off.emailCodeIp, off.emailCodeEmail, off.emailCodeEmailHour]) expect(await limiter.limit("k")).toBe(true);
    }
  });
```

- [ ] **Step 2: Run them to see them fail**

Run: `(cd relay && npx vitest run test/config.test.ts test/errors.test.ts test/limiter.test.ts)`
Expected: FAIL: the default config has no `emailSignIn`, `Errors[name]` is not a function, the limiters are undefined.

- [ ] **Step 3: Commit the failing tests**

```bash
git add relay/test/config.test.ts relay/test/errors.test.ts relay/test/limiter.test.ts
git commit -m "test(relay): email sign-in settings, error codes and limiters"
```

- [ ] **Step 4: Implement**

`relay/src/config.ts`, with the existing `value()` helper (a blank value is unset):
- `RESEND_API_KEY` and `EMAIL_FROM` both unset → `emailSignIn: null`; both set → `{ resendApiKey, from }`;
- exactly one set → `ConfigError("RESEND_API_KEY and EMAIL_FROM must be set together")`;
- `EMAIL_FROM` not matching `/^(?:[^<>"\r\n]*<[^\s<>@]+@[^\s<>@]+>|[^\s<>@]+@[^\s<>@]+)$/` → `ConfigError('EMAIL_FROM must be an email address or "Name <address>"')`.
Give the field a doc comment naming both variables. No message may contain either value.

`relay/src/http/errors.ts`: add, and reword two messages (Ruling 20):

```ts
invalidCode: () => new ApiError(401, "invalid_code", "That code is not right"),
codeExpired: () => new ApiError(410, "code_expired", "That code has expired or was already used: ask for a new one"),
emailSignInDisabled: () => new ApiError(503, "email_sign_in_disabled", "Signing in with an email code is not available on this relay"),
emailSendFailed: () => new ApiError(502, "email_send_failed", "The email could not be sent: try again"),
```

`relay/src/auth/rate-limit.ts`: the three fields on `RateLimiters` (doc comments with key and limit), the four constants, `allowAll` for each when limits are off, and `SlidingWindowLimiter`s otherwise (`emailCodeEmailHour` with `windowMs: EMAIL_CODES_HOUR_WINDOW_MS`).

`relay/test/helpers.ts`: `emailSignIn: null` in `TEST_CONFIG`; the three limiters as `allowAll` in `unlimited`.

`scripts/shellx/share-e2e.mjs`: `emailSignIn: null` in `config`; `'emailCodeIp', 'emailCodeEmail', 'emailCodeEmailHour'` in the limiter name list.

- [ ] **Step 5: Run the tests to see them pass**

Run: the command of Step 2, then `(cd relay && npm test && npm run typecheck)` and `node --check scripts/shellx/share-e2e.mjs`.
Expected: `Test Files  3 passed (3)`; no failed file; no `error TS` line; `node --check` prints nothing.

- [ ] **Step 6: Commit**

```bash
git add relay/src/config.ts relay/src/http/errors.ts relay/src/auth/rate-limit.ts relay/test/helpers.ts scripts/shellx/share-e2e.mjs
git commit -m "feat(relay): RESEND_API_KEY and EMAIL_FROM, email-code error codes and limiters"
```

---

### Task 3: The mail gateway, the Resend client and the mail

**Files:**
- Create: `relay/src/email/resend.ts`, `relay/src/email/sign-in-code.ts`, `relay/test/fake-email.ts`
- Test: `relay/test/resend.test.ts` (new)

**Interfaces:**
- Produces, in `relay/src/email/resend.ts`:
  - `export const RESEND_EMAILS_URL = "https://api.resend.com/emails"; export const RESEND_TIMEOUT_MS = 10_000; export const RESEND_USER_AGENT = "shellx-relay";`
  - `export interface EmailMessage { to: string; subject: string; text: string; html: string; idempotencyKey: string }`
  - `export type EmailSendResult = { ok: true } | { ok: false; status?: number; error?: string }`
  - `export interface EmailGateway { send(message: EmailMessage): Promise<EmailSendResult> }` (never throws, never logs)
  - `export class ResendClient implements EmailGateway { constructor(options: { apiKey: string; from: string; fetch?: typeof fetch; timeoutMs?: number }) }`
- Produces, in `relay/src/email/sign-in-code.ts`: `export type EmailLocale = "en" | "vi"; export function signInCodeEmail(code: string, locale: EmailLocale): { subject: string; text: string; html: string }`.
- Produces, in `relay/test/fake-email.ts`: `FakeEmailGateway` with `sent: EmailMessage[]`, `result: EmailSendResult` and `codeFor(to: string): string`.

- [ ] **Step 1: Write the failing tests**

`relay/test/resend.test.ts` (the key is a placeholder; `fetch` is always fake):

```ts
import { afterEach, describe, expect, it, vi } from "vitest";
import { RESEND_EMAILS_URL, RESEND_TIMEOUT_MS, ResendClient } from "../src/email/resend.js";
import { signInCodeEmail } from "../src/email/sign-in-code.js";

afterEach(() => vi.restoreAllMocks());

const KEY = "placeholder-not-a-real-key";
const MESSAGE = { to: "ann.lee@example.com", subject: "s", text: "t", html: "<p>h</p>", idempotencyKey: "7f1c0a52-3b0e-4d3a-9a39-0d5b0c7f2a11" };

function fakeFetch(answer: { status: number; body?: string } | Error | "hang") {
  const calls: { url: string; init: RequestInit }[] = [];
  const fn = (async (url: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(url), init: init ?? {} });
    if (answer === "hang") {
      const signal = init!.signal!;
      return new Promise<Response>((_, reject) => signal.addEventListener("abort", () => reject(signal.reason)));
    }
    if (answer instanceof Error) throw answer;
    return new Response(answer.body ?? "{}", { status: answer.status });
  }) as typeof fetch;
  return { fn, calls };
}

describe("ResendClient", () => {
  it("posts one JSON message to Resend with the key, the idempotency key and a User-Agent, for at most 10 s", async () => {
    const f = fakeFetch({ status: 200, body: '{"id":"49a3999c"}' });
    expect(await new ResendClient({ apiKey: KEY, from: "ShellX <sign-in@shellx.pro>", fetch: f.fn }).send(MESSAGE)).toEqual({ ok: true });
    expect([RESEND_EMAILS_URL, RESEND_TIMEOUT_MS]).toEqual(["https://api.resend.com/emails", 10_000]);
    expect(f.calls).toHaveLength(1);
    const { url, init } = f.calls[0]!;
    const headers = new Headers(init.headers);
    expect([url, init.method, init.redirect]).toEqual(["https://api.resend.com/emails", "POST", "error"]);
    expect([headers.get("authorization"), headers.get("content-type"), headers.get("idempotency-key"), headers.get("user-agent")])
      .toEqual([`Bearer ${KEY}`, "application/json", MESSAGE.idempotencyKey, "shellx-relay"]);
    expect(JSON.parse(String(init.body))).toEqual({ from: "ShellX <sign-in@shellx.pro>", to: ["ann.lee@example.com"], subject: "s", text: "t", html: "<p>h</p>" });
    expect(init.signal).toBeInstanceOf(AbortSignal);
  });

  it.each([400, 401, 403, 422, 429, 500, 503])("answers {ok: false, status} to a %i, without retrying", async (status) => {
    const f = fakeFetch({ status, body: '{"message":"ann.lee@example.com is not allowed"}' });
    expect(await new ResendClient({ apiKey: KEY, from: "sign-in@shellx.pro", fetch: f.fn }).send(MESSAGE)).toEqual({ ok: false, status });
    expect(f.calls).toHaveLength(1);
  });

  it("answers {ok: false, error} when the request fails or outlasts the timeout; never throws and never logs", async () => {
    const lines: string[] = [];
    for (const level of ["log", "info", "warn", "error"] as const) vi.spyOn(console, level).mockImplementation((...args: unknown[]) => void lines.push(args.map(String).join(" ")));
    const reset = Object.assign(new Error("connect ECONNRESET 203.0.113.9:443"), { code: "ECONNRESET" });
    const down = new ResendClient({ apiKey: KEY, from: "sign-in@shellx.pro", fetch: fakeFetch(reset).fn });
    expect(await down.send(MESSAGE)).toEqual({ ok: false, error: "ECONNRESET" });
    const slow = new ResendClient({ apiKey: KEY, from: "sign-in@shellx.pro", fetch: fakeFetch("hang").fn, timeoutMs: 20 });
    expect(await slow.send(MESSAGE)).toEqual({ ok: false, error: "TimeoutError" });
    expect(lines).toEqual([]);
  });
});

describe("the sign-in code email", () => {
  it("has the fixed subjects and the same three sentences as text and as HTML, in English and Vietnamese", () => {
    const en = signInCodeEmail("048213", "en");
    const vn = signInCodeEmail("048213", "vi");
    expect(en.subject).toBe("Your ShellX sign-in code is 048213");
    expect(vn.subject).toBe("Mã đăng nhập ShellX của bạn là 048213");
    expect(en.text).toBe(
      "Your ShellX sign-in code is 048213\n\nEnter this code in ShellX within 10 minutes.\n\n" +
      "If you did not ask for it, ignore this email: nobody can sign in without the code. ShellX will never ask you for this code by email, phone or chat.\n",
    );
    expect(vn.text).toBe(
      "Mã đăng nhập ShellX của bạn là 048213\n\nNhập mã này vào ShellX trong vòng 10 phút.\n\n" +
      "Nếu bạn không yêu cầu mã, hãy bỏ qua email này: không ai đăng nhập được nếu không có mã. ShellX không bao giờ hỏi bạn mã này qua email, điện thoại hay tin nhắn.\n",
    );
    for (const mail of [en, vn]) {
      for (const sentence of mail.text.split("\n").filter((line) => line !== "").slice(1)) expect(mail.html).toContain(sentence);
      expect(mail.html).toContain(">048213<");
    }
    expect([en.html.includes('lang="en"'), vn.html.includes('lang="vi"')]).toEqual([true, true]);
  });

  it("has nothing to click or load: no link, image, script or remote reference", () => {
    for (const locale of ["en", "vi"] as const) {
      const mail = signInCodeEmail("048213", locale);
      expect(mail.html).not.toMatch(/https?:|www\.|href|<a[\s>]|<img|<script|<link|<style|src=|url\(|@import/i);
      expect(mail.text).not.toMatch(/https?:|www\./i);
    }
  });
});
```

`relay/test/fake-email.ts`:

```ts
import type { EmailGateway, EmailMessage, EmailSendResult } from "../src/email/resend.js";

/** Records every mail instead of sending it; `result` is what the next sends answer. */
export class FakeEmailGateway implements EmailGateway {
  readonly sent: EmailMessage[] = [];
  result: EmailSendResult = { ok: true };

  async send(message: EmailMessage): Promise<EmailSendResult> {
    this.sent.push(message);
    return this.result;
  }

  /** The six-digit code of the newest mail to `to`, read from its subject. */
  codeFor(to: string): string {
    const mail = this.sent.findLast((m) => m.to === to);
    const code = mail === undefined ? null : /\b([0-9]{6})\b/.exec(mail.subject);
    if (code === null) throw new Error("no code was mailed to that address");
    return code[1]!;
  }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `(cd relay && npx vitest run test/resend.test.ts)`
Expected: FAIL: `../src/email/resend.js` cannot be found.

- [ ] **Step 3: Commit the failing tests**

```bash
git add relay/test/resend.test.ts relay/test/fake-email.ts
git commit -m "test(relay): the Resend client and the sign-in code mail"
```

- [ ] **Step 4: Implement**

`ResendClient.send`: one `fetch` (the injected one, else the global) to `RESEND_EMAILS_URL` with `method: "POST"`, the four headers the test names, `body: JSON.stringify({ from, to: [message.to], subject, text, html })`, `redirect: "error"`, `signal: AbortSignal.timeout(timeoutMs ?? RESEND_TIMEOUT_MS)`. Status 200–299 → `{ ok: true }`; any other → `{ ok: false, status }`; a thrown error → `{ ok: false, error: errorKind(err) }` (`relay/src/log.ts`). Cancel the answer's body unread (`res.body?.cancel()`): it may quote the recipient. No log call in this file.

`signInCodeEmail`: subject = lead + space + code; text = subject, blank line, sentence 2, blank line, sentence 3, final newline; HTML = one `<div lang="en|vi">` holding four `<p>` (the lead, the code alone in a larger `<p>`, sentence 2, sentence 3), inline `style` for font sizes only, no colour. Copy, exactly:

| | English | Vietnamese |
| --- | --- | --- |
| lead | `Your ShellX sign-in code is` | `Mã đăng nhập ShellX của bạn là` |
| sentence 2 | `Enter this code in ShellX within 10 minutes.` | `Nhập mã này vào ShellX trong vòng 10 phút.` |
| sentence 3 | `If you did not ask for it, ignore this email: nobody can sign in without the code. ShellX will never ask you for this code by email, phone or chat.` | `Nếu bạn không yêu cầu mã, hãy bỏ qua email này: không ai đăng nhập được nếu không có mã. ShellX không bao giờ hỏi bạn mã này qua email, điện thoại hay tin nhắn.` |

- [ ] **Step 5: Run the tests to see them pass**

Run: `(cd relay && npx vitest run test/resend.test.ts)`, then `(cd relay && npm test && npm run typecheck)`.
Expected: `Test Files  1 passed (1)`; no failed file; no `error TS` line.

- [ ] **Step 6: Commit**

```bash
git add relay/src/email/resend.ts relay/src/email/sign-in-code.ts
git commit -m "feat(relay): EmailGateway, the Resend client and the sign-in code mail (en, vi)"
```

---

### Task 4: Email challenges

**Files:**
- Create: `relay/src/auth/email-codes.ts`
- Test: `relay/test/email-codes.test.ts`, `relay/test/email-codes-compare.test.ts` (both new)

**Interfaces:**
- Consumes: `generateToken`, `hashToken` (`relay/src/auth/tokens.ts`); table `email_codes` (Task 1).
- Produces:
  - `export const EMAIL_CODE_TTL_MS = 600_000; export const EMAIL_CODE_RESEND_SEC = 60; export const EMAIL_CODE_MAX_ATTEMPTS = 5; export const MAX_LIVE_EMAIL_CODES = 50_000;`
  - `export function generateEmailCode(): string`
  - `export interface IssuedEmailCode { id: string; challengeId: string }`
  - `export async function issueEmailCode(db: Db, email: string, code: string, nowMs: number): Promise<IssuedEmailCode | null>` (`null` at the cap)
  - `export function discardEmailCode(db: Db, id: string): void`
  - `export type RedeemedEmailCode = { ok: true; email: string } | { ok: false; reason: "invalid_code" | "code_expired" }`
  - `export async function redeemEmailCode(db: Db, challengeId: unknown, code: unknown, nowMs: number): Promise<RedeemedEmailCode>`

- [ ] **Step 1: Write the failing tests**

`relay/test/email-codes.test.ts`:

```ts
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
```

`relay/test/email-codes-compare.test.ts` (its own file: it replaces `timingSafeEqual` of `node:crypto` with a recording wrapper for the whole file):

```ts
import { expect, it, vi } from "vitest";

const compared = vi.hoisted(() => ({ calls: [] as [number, number][] }));
vi.mock("node:crypto", async (importOriginal) => {
  const actual = await importOriginal<typeof import("node:crypto")>();
  return {
    ...actual,
    timingSafeEqual: (a: NodeJS.ArrayBufferView, b: NodeJS.ArrayBufferView) => {
      compared.calls.push([a.byteLength, b.byteLength]);
      return actual.timingSafeEqual(a, b);
    },
  };
});

import { issueEmailCode, redeemEmailCode } from "../src/auth/email-codes.js";
import { db } from "./helpers.js";

it("compares code hashes with timingSafeEqual: once per guess at a live challenge, right or wrong, on two 32-byte digests", async () => {
  const T0 = 1_800_000_000_000;
  const { challengeId } = (await issueEmailCode(db(), "ann.lee@example.com", "048213", T0))!;
  await redeemEmailCode(db(), "n".repeat(43), "048213", T0); // unknown challenge: nothing to compare
  expect(compared.calls).toEqual([]);
  expect(await redeemEmailCode(db(), challengeId, "048214", T0)).toEqual({ ok: false, reason: "invalid_code" }); // last digit off
  expect(await redeemEmailCode(db(), challengeId, "948213", T0)).toEqual({ ok: false, reason: "invalid_code" }); // first digit off
  expect(await redeemEmailCode(db(), challengeId, "048213", T0)).toEqual({ ok: true, email: "ann.lee@example.com" });
  expect(compared.calls).toEqual([[32, 32], [32, 32], [32, 32]]);
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `(cd relay && npx vitest run test/email-codes.test.ts test/email-codes-compare.test.ts)`
Expected: FAIL: `../src/auth/email-codes.js` cannot be found.

- [ ] **Step 3: Commit the failing tests**

```bash
git add relay/test/email-codes.test.ts relay/test/email-codes-compare.test.ts
git commit -m "test(relay): email challenges keep hashes only, count guesses and are redeemed once"
```

- [ ] **Step 4: Implement `relay/src/auth/email-codes.ts`**

- `generateEmailCode`: `String(randomInt(0, 1_000_000)).padStart(6, "0")` (`node:crypto`).
- `issueEmailCode`: `challengeId = generateToken()`; hash it and `` `${challengeId}:${code}` `` with `hashToken`; `id = crypto.randomUUID()`. Then, in one `db.transaction` and in this order (Ruling 17): delete rows with `expires_at <= nowMs`; if `COUNT(*) >= MAX_LIVE_EMAIL_CODES` return `null`; delete the rows of this `email`; insert `(id, challenge_hash, code_hash, email, 0, nowMs, nowMs + EMAIL_CODE_TTL_MS)`; return `{ id, challengeId }`.
- `discardEmailCode`: `DELETE FROM email_codes WHERE id = ?`.
- `redeemEmailCode`: a `challengeId` that is not a string matching `/^[A-Za-z0-9_-]{43}$/` → `code_expired` without touching the database. Otherwise hash the id and `` `${challengeId}:${typeof code === "string" ? code : ""}` `` (awaits first), then run exactly this transaction. The order is the security rule: the guess is counted before it is compared, and the row is looked up by `challenge_hash` only (`code_hash` never appears in a `WHERE`).

```ts
return db.transaction((): RedeemedEmailCode => {
  db.run("DELETE FROM email_codes WHERE expires_at <= ?", nowMs);
  const row = db.get<{ id: string; code_hash: Uint8Array; email: string }>(
    "SELECT id, code_hash, email FROM email_codes WHERE challenge_hash = ?", challengeHash,
  );
  if (row === undefined) return { ok: false, reason: "code_expired" };
  const attempts = db.get<{ attempts: number }>("UPDATE email_codes SET attempts = attempts + 1 WHERE id = ? RETURNING attempts", row.id)!.attempts;
  const match = row.code_hash.length === guessHash.length && timingSafeEqual(row.code_hash, guessHash);
  if (match || attempts >= EMAIL_CODE_MAX_ATTEMPTS) db.run("DELETE FROM email_codes WHERE id = ?", row.id);
  if (match) return { ok: true, email: row.email };
  return { ok: false, reason: attempts >= EMAIL_CODE_MAX_ATTEMPTS ? "code_expired" : "invalid_code" };
});
```

(`guessHash` is `new Uint8Array(await hashToken(…))`.) Nothing in this file logs.

- [ ] **Step 5: Run the tests to see them pass**

Run: the command of Step 2, then `(cd relay && npm test && npm run typecheck)`.
Expected: `Test Files  2 passed (2)`; no failed file; no `error TS` line.

- [ ] **Step 6: Commit**

```bash
git add relay/src/auth/email-codes.ts
git commit -m "feat(relay): email challenges: hashes only, 600 s, five counted guesses, one per address"
```

---

### Task 5: `POST /v1/auth/email/code`

**Files:**
- Create: `relay/src/routes/email-sign-in.ts`
- Modify: `relay/src/app.ts` (`AppDeps` 37-66, `AppVariables` 68-84, the `c.set` block 112-127, the routes 142-157), `relay/src/server.ts` (before the database opens, and the `startRelay` call at 79-82), `relay/test/helpers.ts`
- Test: `relay/test/auth-email-code.test.ts` (new), `relay/test/server.test.ts`

**Interfaces:**
- Consumes: Tasks 2, 3, 4.
- Produces:
  - `AppDeps.email?: EmailGateway | null` and `AppDeps.emailCode?: () => string`; `AppVariables.email: EmailGateway | null` and `AppVariables.emailCode: () => string` (defaults `null` and `generateEmailCode`);
  - `export const emailSignInRoutes: Hono<AppEnv>`, mounted with `app.route("/v1/auth/email", emailSignInRoutes)`;
  - test helper `requestEmailCode(app, mail, email, options?)` → `{ challengeId, code, email }`.

- [ ] **Step 1: Write the failing tests**

`relay/test/helpers.ts`: import `type { FakeEmailGateway } from "./fake-email.js"` and add before the "Apple sign-in" section:

```ts
// ---- Email-code sign-in (the fake gateway of fake-email.ts) ---------------------------------------

/** POST /v1/auth/email/code; throws unless 202. `code` is read from the mail the fake gateway recorded. */
export async function requestEmailCode(
  app: TestApp, mail: FakeEmailGateway, email: string, options: { locale?: string; ip?: string } = {},
): Promise<{ challengeId: string; code: string; email: string }> {
  const res = await call(app, "POST", "/v1/auth/email/code", { ip: options.ip, body: { email, locale: options.locale } });
  if (res.status !== 202) throw new Error(`email code request failed: ${res.status} ${await res.text()}`);
  const body = await res.json<{ challenge_id: string; email: string }>();
  return { challengeId: body.challenge_id, code: mail.codeFor(body.email), email: body.email };
}
```

`relay/test/auth-email-code.test.ts`:

```ts
import { afterEach, describe, expect, it, vi } from "vitest";
import { createRateLimiters } from "../src/auth/rate-limit.js";
import { hashToken } from "../src/auth/tokens.js";
import { FakeEmailGateway } from "./fake-email.js";
import { call, CountingLimiter, db, errorCode, googleSession, makeApp, requestEmailCode, type TestApp, unlimited } from "./helpers.js";

const T0 = 1_800_000_000_000;
const ask = (app: TestApp, email: unknown, extra: Record<string, unknown> = {}, ip?: string) =>
  call(app, "POST", "/v1/auth/email/code", { ip, body: { email, ...extra } });
const codes = () => db().get<{ n: number }>("SELECT COUNT(*) AS n FROM email_codes")!.n;
afterEach(() => vi.restoreAllMocks());

describe("POST /v1/auth/email/code", () => {
  it("answers 202 with a challenge for 600 s, mails the code once, and stores neither the code nor the challenge id", async () => {
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail, now: () => T0, emailCode: () => "004217" });
    const res = await ask(app, "  Ann.Lee@Example.COM ");
    expect(res.status).toBe(202);
    const body = await res.json<{ challenge_id: string }>();
    expect(body).toEqual({ challenge_id: expect.stringMatching(/^[A-Za-z0-9_-]{43}$/), expires_in: 600, resend_in: 60, email: "ann.lee@example.com" });
    const row = db().get<{ id: string }>("SELECT * FROM email_codes")!;
    expect(row).toEqual({
      id: expect.stringMatching(/^[0-9a-f-]{36}$/), challenge_hash: Buffer.from(await hashToken(body.challenge_id)),
      code_hash: Buffer.from(await hashToken(`${body.challenge_id}:004217`)), email: "ann.lee@example.com", attempts: 0, created_at: T0, expires_at: T0 + 600_000,
    });
    expect(mail.sent).toEqual([{
      to: "ann.lee@example.com", subject: "Your ShellX sign-in code is 004217", idempotencyKey: row.id,
      text: expect.stringContaining("004217"), html: expect.stringContaining("004217"),
    }]);
  });

  it("answers the same 202 whether or not the address has an account, and touches no account", async () => {
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail, now: () => T0 });
    await googleSession(app, { email: "known@example.com" });
    const accounts = () => [db().all("SELECT * FROM users"), db().all("SELECT * FROM identities")];
    const before = accounts();
    for (const email of ["known@example.com", "nobody@example.com"]) {
      const res = await ask(app, email);
      expect(res.status).toBe(202);
      expect(await res.json()).toEqual({ challenge_id: expect.stringMatching(/^[A-Za-z0-9_-]{43}$/), expires_in: 600, resend_in: 60, email });
    }
    expect(mail.sent.map((m) => [m.to, m.subject.replace(/[0-9]{6}/, "######")])).toEqual([
      ["known@example.com", "Your ShellX sign-in code is ######"], ["nobody@example.com", "Your ShellX sign-in code is ######"],
    ]);
    expect(accounts()).toEqual(before);
  });

  it("writes the mail in Vietnamese for locale vi and in English for anything else", async () => {
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail, emailCode: () => "731946" });
    for (const locale of ["vi", "en", "fr", 7, undefined]) expect((await ask(app, `${String(locale)}@example.com`, { locale })).status).toBe(202);
    expect(mail.sent.map((m) => m.subject)).toEqual([
      "Mã đăng nhập ShellX của bạn là 731946", ...Array(4).fill("Your ShellX sign-in code is 731946"),
    ]);
  });

  it("refuses an invalid address (400 invalid_email) and a disposable one (400 disposable_email), sending nothing", async () => {
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail });
    for (const email of ["", "no-at-sign", "a@b", "ann lee@example.com", "ann@exam ple.com", "ann@example.com\nbcc: x@example.com", 42, null, undefined, ["a@example.com"]]) {
      const res = await ask(app, email);
      expect([res.status, await errorCode(res)]).toEqual([400, "invalid_email"]);
    }
    const disposable = await ask(app, "someone@Mailinator.com");
    expect([disposable.status, await errorCode(disposable)]).toEqual([400, "disposable_email"]);
    const notJson = await call(app, "POST", "/v1/auth/email/code", { body: "{oops" });
    expect([notJson.status, await errorCode(notJson)]).toEqual([400, "bad_request"]);
    expect([mail.sent.length, codes()]).toEqual([0, 0]);
  });

  it("keeps only the newest challenge of an address, also when two requests race", async () => {
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail, now: () => T0 });
    const first = await requestEmailCode(app, mail, "ann.lee@example.com");
    const second = await requestEmailCode(app, mail, "ANN.LEE@example.com");
    expect(db().all("SELECT challenge_hash FROM email_codes")).toEqual([{ challenge_hash: Buffer.from(await hashToken(second.challengeId)) }]);
    expect(first.challengeId).not.toBe(second.challengeId);
    const raced = await Promise.all([ask(app, "bob@example.com"), ask(app, "bob@example.com"), ask(app, "bob@example.com")]);
    expect(raced.map((r) => r.status)).toEqual([202, 202, 202]);
    expect(db().get("SELECT COUNT(*) AS n FROM email_codes WHERE email = 'bob@example.com'")).toEqual({ n: 1 });
  });

  it("limits by IP, and by the normalized address per minute and per hour: every spelling of an address shares one budget", async () => {
    const mail = new FakeEmailGateway();
    const emailCodeIp = new CountingLimiter(100);
    const emailCodeEmail = new CountingLimiter(2);
    const emailCodeEmailHour = new CountingLimiter(100);
    const app = makeApp({ email: mail, limiters: { ...unlimited, emailCodeIp, emailCodeEmail, emailCodeEmailHour } });
    const statuses: number[] = [];
    for (const spelling of ["Ann.Lee@Example.com", "  ann.lee@example.com ", "ANN.LEE@EXAMPLE.COM"]) statuses.push((await ask(app, spelling, {}, "198.51.100.9")).status);
    expect(statuses).toEqual([202, 202, 429]);
    expect(emailCodeIp.calls).toEqual(Array(3).fill("198.51.100.9"));
    expect(emailCodeEmail.calls).toEqual(Array(3).fill("ann.lee@example.com"));
    expect(emailCodeEmailHour.calls).toEqual(Array(2).fill("ann.lee@example.com"));
    expect(mail.sent).toHaveLength(2);
    expect(db().all("SELECT email FROM email_codes")).toEqual([{ email: "ann.lee@example.com" }]);

    const hourly = makeApp({ email: mail, limiters: { ...unlimited, emailCodeEmailHour: new CountingLimiter(1) } });
    expect([(await ask(hourly, "bob@example.com")).status, (await ask(hourly, "Bob@example.com")).status]).toEqual([202, 429]);
    const perIp = makeApp({ email: mail, limiters: { ...unlimited, emailCodeIp: new CountingLimiter(1) } });
    expect([(await ask(perIp, "c1@example.com")).status, (await ask(perIp, "c2@example.com")).status]).toEqual([202, 429]);
    expect(await errorCode(await ask(perIp, "not an address"))).toBe("rate_limited"); // counted before the body is read
  });

  it("in production allows 3 codes per address per minute, 10 per address per hour and 10 per IP per minute", async () => {
    let now = T0;
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail, now: () => now, limiters: createRateLimiters({ rateLimitsEnabled: true }, () => now) });
    const from = (n: number) => `198.51.100.${n}`;
    const burst = async (email: string, ip: string) => {
      const statuses: number[] = [];
      for (let i = 0; i < 4; i++) statuses.push((await ask(app, email, {}, ip)).status);
      return statuses;
    };
    expect(await burst("ann@example.com", from(1))).toEqual([202, 202, 202, 429]);
    now += 60_000;
    expect(await burst("ann@example.com", from(2))).toEqual([202, 202, 202, 429]);
    now += 60_000;
    expect(await burst("ann@example.com", from(3))).toEqual([202, 202, 202, 429]);
    now += 60_000;
    expect(await burst("ann@example.com", from(4))).toEqual([202, 429, 429, 429]); // the 10th of the hour, then the hourly limit
    now += 60_000;
    expect((await ask(app, "bob@example.com", {}, from(4))).status).toBe(202); // another address is not affected
    now = T0 + 3_600_000;
    expect((await ask(app, "ann@example.com", {}, from(5))).status).toBe(202);
    const perIp: number[] = [];
    for (let i = 0; i < 11; i++) perIp.push((await ask(app, `user${i}@example.com`, {}, from(6))).status);
    expect(perIp).toEqual([...Array(10).fill(202), 429]);
  });

  it("answers 429 while 50 000 challenges are live", async () => {
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail, now: () => T0 });
    db().run(`WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 50000)
              INSERT INTO email_codes (id, challenge_hash, code_hash, email, created_at, expires_at)
              SELECT 'seed-' || i, randomblob(32), randomblob(32), 'seed-' || i || '@example.com', ?, ? FROM n`, T0, T0 + 600_000);
    const res = await ask(app, "ann@example.com");
    expect([res.status, await errorCode(res), mail.sent.length]).toEqual([429, "rate_limited", 0]);
  });

  it("answers 503 email_sign_in_disabled without a gateway, before anything is counted or stored", async () => {
    const emailCodeIp = new CountingLimiter(100);
    const app = makeApp({ limiters: { ...unlimited, emailCodeIp } });
    for (const email of ["ann@example.com", "not an address"]) {
      const res = await ask(app, email);
      expect([res.status, await errorCode(res)]).toEqual([503, "email_sign_in_disabled"]);
    }
    expect([emailCodeIp.calls.length, codes()]).toEqual([0, 0]);
  });

  it("answers 502 email_send_failed when the mail cannot be sent, and leaves no challenge behind", async () => {
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail, now: () => T0 });
    await requestEmailCode(app, mail, "ann@example.com");
    for (const result of [{ ok: false, status: 500 }, { ok: false, error: "TimeoutError" }] as const) {
      mail.result = result;
      const res = await ask(app, "ann@example.com");
      expect([res.status, await errorCode(res)]).toEqual([502, "email_send_failed"]);
      expect(await res.json()).toEqual({ error: { code: "email_send_failed", message: expect.any(String) } });
      expect(codes()).toBe(0);
    }
    const throwing = makeApp({ email: { send: async () => { throw new Error("boom ann@example.com"); } } });
    expect((await ask(throwing, "ann@example.com")).status).toBe(502);
    expect(codes()).toBe(0);
  });

  it("logs events without the address, the code, the challenge id or the IP", async () => {
    const lines: string[] = [];
    for (const level of ["log", "info", "warn", "error"] as const) vi.spyOn(console, level).mockImplementation((...args: unknown[]) => void lines.push(args.map(String).join(" ")));
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail, emailCode: () => "731946", limiters: { ...unlimited, emailCodeEmail: new CountingLimiter(2) } });
    const sent = await requestEmailCode(app, mail, "secret.mailbox@example.com", { locale: "vi", ip: "198.51.100.77" });
    mail.result = { ok: false, status: 422 };
    await ask(app, "secret.mailbox@example.com", {}, "198.51.100.77");
    await ask(app, "secret.mailbox@example.com", {}, "198.51.100.77");
    await ask(app, "secret.mailbox@mailinator.com", {}, "198.51.100.77");
    const output = lines.map((line) => line.replace(/"ts":[0-9]+,?/, "")).join("\n");
    for (const event of ['"event":"email_code_sent","locale":"vi"', '"event":"email_send_failed","status":422', '"event":"email_code_refused","reason":"rate_limited_email"', '"event":"email_code_refused","reason":"disposable_email"']) {
      expect(output).toContain(event);
    }
    for (const secret of ["secret.mailbox", "731946", sent.challengeId, "198.51.100.77"]) expect(output).not.toContain(secret);
    expect(output).not.toMatch(/[A-Za-z0-9_-]{43,}/);
  });
});
```

`relay/test/server.test.ts`: add `errorCode` to the `./helpers.js` import and append:

```ts
describe("email sign-in configuration (RESEND_API_KEY, EMAIL_FROM)", () => {
  it("is off without the two variables (503), on with both, and half of the pair stops the relay; the key is never printed", async () => {
    const KEY = "placeholder-not-a-real-key";
    const env = { ...VERSION_ENV, HOST: "127.0.0.1", PORT: "0", DB_PATH: join(tempDir(), "relay.db") };
    const off = startServer(env);
    onCleanup(() => off.child.kill("SIGKILL"));
    const port = await waitForListening(off.output);
    expect(off.output()).toContain('"event":"email_sign_in_disabled"');
    const res = await call(remote(port), "POST", "/v1/auth/email/code", { body: { email: "ann@example.com" } });
    expect([res.status, await errorCode(res)]).toEqual([503, "email_sign_in_disabled"]);
    off.child.kill("SIGTERM");
    expect((await off.exit).code).toBe(0);

    // This process holds a real ResendClient: nothing may call POST /v1/auth/email/code on it.
    const on = startServer({ ...env, RESEND_API_KEY: KEY, EMAIL_FROM: "ShellX <sign-in@shellx.pro>" });
    onCleanup(() => on.child.kill("SIGKILL"));
    await waitForListening(on.output);
    expect(on.output()).toContain('"event":"email_sign_in_enabled"');
    on.child.kill("SIGTERM");
    const stopped = await on.exit;
    expect(stopped.code).toBe(0);
    expect(stopped.stdout + stopped.stderr).not.toContain(KEY);

    for (const half of [{ RESEND_API_KEY: KEY }, { EMAIL_FROM: "ShellX <sign-in@shellx.pro>" }] as Record<string, string>[]) {
      const broken = await startServer({ ...env, ...half }).exit;
      expect([broken.code, broken.stderr]).toEqual([1, "relay: RESEND_API_KEY and EMAIL_FROM must be set together\n"]);
    }
  });
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `(cd relay && npx vitest run test/auth-email-code.test.ts test/server.test.ts)`
Expected: FAIL: the route answers 404 `not_found`, and the relay logs no `email_sign_in_disabled`.

- [ ] **Step 3: Commit the failing tests**

```bash
git add relay/test/helpers.ts relay/test/auth-email-code.test.ts relay/test/server.test.ts
git commit -m "test(relay): POST /v1/auth/email/code: same answer for every address, limits, 503, 502"
```

- [ ] **Step 4: Implement**

`relay/src/app.ts`: the two `AppDeps` fields with doc comments, the two variables, `c.set("email", deps.email ?? null)`, `c.set("emailCode", deps.emailCode ?? generateEmailCode)`, and the route mount after the Apple link routes.

`relay/src/server.ts`: after the Apple block, `const email = config.emailSignIn === null ? null : new ResendClient({ apiKey: config.emailSignIn.resendApiKey, from: config.emailSignIn.from })`, then `logMeta(email === null ? "email_sign_in_disabled" : "email_sign_in_enabled")`, and pass `email` to `startRelay`.

`POST /code` (`jsonBodyLimit`), in this order; every refusal logs `email_code_refused {reason}` (Ruling 11) before it throws:
1. `c.get("email") === null` → `disabled`, `Errors.emailSignInDisabled()`.
2. `emailCodeIp.limit(requestIp(c))` refused → `rate_limited_ip`, 429.
3. `readJsonObject`; `checkEmail(body.email)` not ok → its code as the reason, `Errors.invalidEmail()` or `Errors.disposableEmail()`. From here on `email` is `check.email` and nothing else.
4. `emailCodeEmail.limit(email)`, then `emailCodeEmailHour.limit(email)`; either refused → `rate_limited_email`, 429.
5. `locale = body.locale === "vi" ? "vi" : "en"`; `code = c.get("emailCode")()`; `issueEmailCode(db, email, code, now)`; `null` → `too_many_live`, 429.
6. `gateway.send({ to: email, ...signInCodeEmail(code, locale), idempotencyKey: issued.id })`; a rejected promise counts as `{ ok: false, error: errorKind(err) }`.
7. Not ok → `discardEmailCode(db, issued.id)`, `logMeta("email_send_failed", { status })` or `{ error }`, `Errors.emailSendFailed()`.
8. `logMeta("email_code_sent", { locale })`; answer 202 `{ challenge_id: issued.challengeId, expires_in: EMAIL_CODE_TTL_MS / 1000, resend_in: EMAIL_CODE_RESEND_SEC, email }`.

The handler reads neither `users` nor `identities` (Review Focus 1).

- [ ] **Step 5: Run the tests to see them pass**

Run: the command of Step 2, then `(cd relay && npm test && npm run typecheck)`.
Expected: `Test Files  2 passed (2)`; no failed file; no `error TS` line.

- [ ] **Step 6: Commit**

```bash
git add relay/src/routes/email-sign-in.ts relay/src/app.ts relay/src/server.ts
git commit -m "feat(relay): POST /v1/auth/email/code mails a sign-in code through the email gateway"
```

---

### Task 6: `POST /v1/auth/email/verify` and the account rules

**Files:**
- Modify: `relay/src/routes/email-sign-in.ts`, `relay/test/helpers.ts`
- Test: `relay/test/auth-email-verify.test.ts` (new)

**Interfaces:**
- Consumes: `redeemEmailCode` (Task 4); `matchAccount`, `identityFromToken`, `insertIdentity`, `dropPasswordAccess`, `signInDevice`, `accountEmail` (`relay/src/auth/identity.ts`); `parseDevice`; `generateToken`, `hashToken`; `recordAppVersion`, `CLIENT_VERSION_HEADER`.
- Produces: the route; test helpers `signInEmail(app, mail, options?)` → `TestResponse` and `emailSession(app, mail, options?)` → `EmailSession` (`Session` + `email`).

- [ ] **Step 1: Write the failing tests**

`relay/test/helpers.ts`, after `requestEmailCode`:

```ts
export interface EmailSignInOptions {
  email?: string;
  kind?: "desktop" | "mobile";
  publicKey?: string;
  headers?: Record<string, string>;
  ip?: string;
}

/** Asks for a code and verifies it with a new device. */
export async function signInEmail(app: TestApp, mail: FakeEmailGateway, options: EmailSignInOptions = {}): Promise<TestResponse> {
  const { challengeId, code } = await requestEmailCode(app, mail, options.email ?? randomEmail(), { ip: options.ip });
  return call(app, "POST", "/v1/auth/email/verify", {
    ip: options.ip, headers: options.headers,
    body: { challenge_id: challengeId, code, device: deviceBody(options.kind ?? "desktop", { public_key: options.publicKey ?? randomPublicKey() }) },
  });
}

export interface EmailSession extends Session {
  email: string;
}

/** Signs in with an email code; throws unless 200. */
export async function emailSession(app: TestApp, mail: FakeEmailGateway, options: EmailSignInOptions = {}): Promise<EmailSession> {
  const publicKey = options.publicKey ?? randomPublicKey();
  const res = await signInEmail(app, mail, { ...options, publicKey });
  if (res.status !== 200) throw new Error(`email sign-in failed: ${res.status} ${await res.text()}`);
  const body = await res.json<{ user_id: string; device_id: string; token: string; email: string }>();
  return { userId: body.user_id, deviceId: body.device_id, token: body.token, publicKey, email: body.email };
}
```

`relay/test/auth-email-verify.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import type { AppDeps } from "../src/app.js";
import { insertToken } from "../src/auth/session.js";
import { hashToken } from "../src/auth/tokens.js";
import { FakeEmailGateway } from "./fake-email.js";
import {
  call, CountingLimiter, db, deviceBody, emailSession, errorCode, googleSession, loginDevice, makeApp, registerAccount, requestEmailCode,
  seedUser, signInEmail, TEST_CONFIG, type TestApp, unlimited,
} from "./helpers.js";

const T0 = 1_800_000_000_000;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const CODE = "004217";

function setup(deps: Partial<AppDeps> = {}) {
  const mail = new FakeEmailGateway();
  return { mail, app: makeApp({ email: mail, emailCode: () => CODE, ...deps }) };
}
const verify = (app: TestApp, challengeId: unknown, code: unknown, device: unknown = deviceBody("mobile")) =>
  call(app, "POST", "/v1/auth/email/verify", { body: { challenge_id: challengeId, code, device } });
const devices = (app: TestApp, token: string) => call(app, "GET", "/v1/devices", { token });
const identities = (userId: string) =>
  db().all<{ provider: string; subject: string }>("SELECT provider, subject FROM identities WHERE user_id = ? ORDER BY provider", userId);
const count = (table: string) => db().get<{ n: number }>(`SELECT COUNT(*) AS n FROM ${table}`)!.n;
const seedAppleIdentity = (userId: string, subject: string, email: string) =>
  db().run(
    "INSERT INTO identities (id, provider, subject, user_id, email, is_private_email, created_at, last_used_at) VALUES (?, 'apple', ?, ?, ?, 1, 1, 1)",
    crypto.randomUUID(), subject, userId, email,
  );

describe("POST /v1/auth/email/verify", () => {
  it("creates an account on the first code: the normalized address, no password, one email identity, an email token", async () => {
    const { mail, app } = setup();
    const res = await signInEmail(app, mail, { email: "  New.User@Example.com " });
    expect(res.status).toBe(200);
    const body = await res.json<{ user_id: string; device_id: string; token: string }>();
    expect(body).toEqual({
      user_id: expect.stringMatching(UUID_RE), device_id: expect.stringMatching(UUID_RE), token: expect.stringMatching(/^[A-Za-z0-9_-]{43}$/), email: "new.user@example.com",
    });
    expect(db().get("SELECT email, password_hash FROM users WHERE id = ?", body.user_id)).toEqual({ email: "new.user@example.com", password_hash: null });
    expect(db().all("SELECT provider, subject, email, is_private_email FROM identities")).toEqual([
      { provider: "email", subject: "new.user@example.com", email: "new.user@example.com", is_private_email: 0 },
    ]);
    const row = db().get<{ auth_method: string; identity_id: string }>("SELECT auth_method, identity_id FROM tokens WHERE token_hash = ?", await hashToken(body.token));
    expect(row?.auth_method).toBe("email");
    expect(row?.identity_id).toMatch(UUID_RE);
    expect((await devices(app, body.token)).status).toBe(200);
    expect(count("email_codes")).toBe(0);
  });

  it("signs the same address in to the same account; same key, same device, one live token per device", async () => {
    const { mail, app } = setup();
    const first = await emailSession(app, mail, { email: "ann@example.com", kind: "mobile" });
    const again = await emailSession(app, mail, { email: "ANN@example.com", kind: "mobile", publicKey: first.publicKey });
    expect([again.userId, again.deviceId, again.email]).toEqual([first.userId, first.deviceId, "ann@example.com"]);
    expect((await devices(app, first.token)).status).toBe(401);
    const desk = await emailSession(app, mail, { email: "ann@example.com", kind: "desktop" });
    expect(desk.userId).toBe(first.userId);
    expect(desk.deviceId).not.toBe(first.deviceId);
    expect(identities(first.userId)).toEqual([{ provider: "email", subject: "ann@example.com" }]);
  });

  it("answers 401 invalid_code to a wrong guess and counts it; the fifth guess may be right, a fifth wrong one answers 410 and burns the code", async () => {
    const { mail, app } = setup();
    const a = await requestEmailCode(app, mail, "ann@example.com");
    for (let n = 1; n <= 4; n++) {
      const res = await verify(app, a.challengeId, "004218");
      expect([res.status, await errorCode(res)]).toEqual([401, "invalid_code"]);
      expect(db().get("SELECT attempts FROM email_codes")).toEqual({ attempts: n });
    }
    expect((await verify(app, a.challengeId, CODE)).status).toBe(200);

    const b = await requestEmailCode(app, mail, "bob@example.com");
    for (const guess of ["4217", 4217, "004216", " 004217"]) expect(await errorCode(await verify(app, b.challengeId, guess))).toBe("invalid_code");
    const fifth = await verify(app, b.challengeId, "000000");
    expect([fifth.status, await errorCode(fifth)]).toEqual([410, "code_expired"]);
    const late = await verify(app, b.challengeId, CODE);
    expect([late.status, await errorCode(late)]).toEqual([410, "code_expired"]);
    expect(db().all("SELECT email FROM users")).toEqual([{ email: "ann@example.com" }]);
  });

  it("answers 410 code_expired to a used, replaced, expired, unknown or malformed challenge: none of them signs in", async () => {
    let now = T0;
    const { mail, app } = setup({ now: () => now });
    const used = await requestEmailCode(app, mail, "ann@example.com");
    expect((await verify(app, used.challengeId, CODE)).status).toBe(200);
    const replaced = await requestEmailCode(app, mail, "bob@example.com");
    const expired = await requestEmailCode(app, mail, "bob@example.com");
    const stale = await verify(app, replaced.challengeId, CODE);
    expect([stale.status, await errorCode(stale)]).toEqual([410, "code_expired"]);
    now = T0 + 600_000;
    for (const id of [used.challengeId, expired.challengeId, "n".repeat(43), "short", 42, undefined]) {
      const res = await verify(app, id, CODE);
      expect([res.status, await errorCode(res)]).toEqual([410, "code_expired"]);
    }
    expect([count("users"), count("email_codes")]).toEqual([1, 0]);
    now = T0;
    const fresh = await requestEmailCode(app, mail, "carol@example.com");
    now = T0 + 599_999;
    expect((await verify(app, fresh.challengeId, CODE)).status).toBe(200);
  });

  it("signs in at most once when one challenge is verified concurrently, and compares at most five concurrent guesses", async () => {
    const { mail, app } = setup();
    const right = await requestEmailCode(app, mail, "ann@example.com");
    const answers = await Promise.all(Array.from({ length: 6 }, () => verify(app, right.challengeId, CODE)));
    expect(answers.map((r) => r.status).sort()).toEqual([200, 410, 410, 410, 410, 410]);
    expect([count("users"), count("devices"), count("tokens"), count("identities")]).toEqual([1, 1, 1, 1]);

    const wrong = await requestEmailCode(app, mail, "bob@example.com");
    const guesses = await Promise.all(Array.from({ length: 9 }, (_, i) => verify(app, wrong.challengeId, `99999${i}`)));
    expect(guesses.map((r) => r.status).sort()).toEqual([401, 401, 401, 401, 410, 410, 410, 410, 410]);
    expect((await verify(app, wrong.challengeId, CODE)).status).toBe(410);
    expect(count("users")).toBe(1);
  });

  it("links into the account created with Google for that address, in any spelling; the account keeps both sign-ins and its sessions", async () => {
    const { mail, app } = setup();
    const g = await googleSession(app, { email: "ann.lee@example.com" });
    const s = await emailSession(app, mail, { email: " Ann.Lee@EXAMPLE.com " });
    expect([s.userId, s.email]).toEqual([g.userId, "ann.lee@example.com"]);
    expect(identities(g.userId)).toEqual([{ provider: "email", subject: "ann.lee@example.com" }, { provider: "google", subject: g.sub }]);
    expect((await devices(app, g.token)).status).toBe(200);
    expect(count("users")).toBe(1);
  });

  it("never matches another spelling of a mailbox (dots, +tag) or an address that only an identity carries", async () => {
    const { mail, app } = setup();
    const g = await googleSession(app, { email: "ann.lee@example.com" });
    seedAppleIdentity(g.userId, "a-1", "hidden@icloud.example");
    for (const email of ["annlee@example.com", "ann.lee+shellx@example.com", "hidden@icloud.example"]) {
      const s = await emailSession(app, mail, { email });
      expect(s.userId).not.toBe(g.userId);
      expect(s.email).toBe(email);
    }
    expect(identities(g.userId).map((i) => i.provider)).toEqual(["apple", "google"]);
    expect(count("users")).toBe(4);
  });

  it("answers 409 switch_from_signed_in_device for an account whose password still works: nothing is attached and the code is spent", async () => {
    const { mail, app } = setup();
    const account = await registerAccount(app);
    const { challengeId } = await requestEmailCode(app, mail, account.email.toUpperCase());
    for (const [status, code] of [[409, "switch_from_signed_in_device"], [410, "code_expired"]] as const) {
      const res = await verify(app, challengeId, CODE);
      expect([res.status, await errorCode(res)]).toEqual([status, code]);
    }
    expect([count("identities"), count("devices")]).toEqual([0, 1]);
    const login = await call(app, "POST", "/v1/auth/login", { body: { email: account.email, password: account.password, device: deviceBody("mobile") } });
    expect(login.status).toBe(200);
  });

  it("claims an account that has no sign-in left (password off or already cleared): the password and every earlier session go", async () => {
    const account = await registerAccount(makeApp());
    const phone = await loginDevice(makeApp(), account, "mobile");
    const other = "other-session-0123456789abcdef0123456789abc"; // 43 characters; minted without an identity, like the smoke token
    insertToken(db(), await hashToken(other), account.agent.deviceId, Date.now(), "test", null);
    expect((await devices(makeApp(), other)).status).toBe(200);
    const { mail, app } = setup({ config: { ...TEST_CONFIG, passwordLogin: false } });
    const s = await emailSession(app, mail, { email: account.email });
    expect(s.userId).toBe(account.agent.userId);
    expect(db().get("SELECT password_hash FROM users WHERE id = ?", s.userId)).toEqual({ password_hash: null });
    for (const token of [account.agent.token, phone.token, other]) expect((await devices(app, token)).status).toBe(401);
    expect(db().get("SELECT COUNT(*) AS n FROM tokens t JOIN devices d ON d.id = t.device_id WHERE d.user_id = ?", s.userId)).toEqual({ n: 1 });
    expect(identities(s.userId)).toEqual([{ provider: "email", subject: account.email }]);

    const cleared = await seedUser("cleared@example.com", null); // after the cut-over, PASSWORD_LOGIN still on
    const on = setup();
    expect((await emailSession(on.app, on.mail, { email: "cleared@example.com" })).userId).toBe(cleared);
  });

  it("refuses (409) an account whose address was never verified and that has another sign-in (an Apple ID, no Google): nothing changes", async () => {
    const { mail, app } = setup({ config: { ...TEST_CONFIG, passwordLogin: false } });
    const userId = await seedUser("legacy@example.com", "correct horse battery");
    seedAppleIdentity(userId, "a-legacy", "legacy@example.com");
    const res = await signInEmail(app, mail, { email: "legacy@example.com" });
    expect([res.status, await errorCode(res)]).toEqual([409, "switch_from_signed_in_device"]);
    expect(identities(userId)).toEqual([{ provider: "apple", subject: "a-legacy" }]);
    expect(db().get("SELECT password_hash IS NOT NULL AS kept FROM users WHERE id = ?", userId)).toEqual({ kept: 1 });
    expect([count("devices"), count("users")]).toEqual([0, 1]);
  });

  it("answers 400 invalid_device to an agent, a malformed or a missing device without spending a guess, and 400 bad_request to non-JSON", async () => {
    const { mail, app } = setup();
    const { challengeId } = await requestEmailCode(app, mail, "ann@example.com");
    for (const device of [deviceBody("agent"), deviceBody("desktop", { platform: "ios" }), null]) {
      const res = await verify(app, challengeId, CODE, device);
      expect([res.status, await errorCode(res)]).toEqual([400, "invalid_device"]);
    }
    expect(await errorCode(await call(app, "POST", "/v1/auth/email/verify", { body: "{oops" }))).toBe("bad_request");
    expect(db().get("SELECT attempts FROM email_codes")).toEqual({ attempts: 0 });
    expect((await verify(app, challengeId, CODE)).status).toBe(200);
  });

  it("is limited per IP by the login limiter, and records X-ShellX-Version on the device", async () => {
    const loginIp = new CountingLimiter(1);
    const { mail, app } = setup({ limiters: { ...unlimited, loginIp } });
    const s = await emailSession(app, mail, { ip: "198.51.100.7", headers: { "X-ShellX-Version": "1.8.0" } });
    expect(db().get("SELECT app_version FROM devices WHERE id = ?", s.deviceId)).toEqual({ app_version: "1.8.0" });
    const blocked = await signInEmail(app, mail, { ip: "198.51.100.7" });
    expect([blocked.status, await errorCode(blocked)]).toEqual([429, "rate_limited"]);
    expect(loginIp.calls).toEqual(["198.51.100.7", "198.51.100.7"]);
  });
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `(cd relay && npx vitest run test/auth-email-verify.test.ts)`
Expected: FAIL: `/v1/auth/email/verify` answers 404 `not_found`.

- [ ] **Step 3: Commit the failing tests**

```bash
git add relay/test/helpers.ts relay/test/auth-email-verify.test.ts
git commit -m "test(relay): POST /v1/auth/email/verify: guesses, expiry, one sign-in per challenge, account rules"
```

- [ ] **Step 4: Implement `POST /verify`** (`jsonBodyLimit`), in this order:

1. `loginIp.limit(requestIp(c))` refused → 429.
2. `readJsonObject`; `parseDevice(body.device)` null or kind `agent` → `Errors.invalidDevice()` (before any guess is spent).
3. Mint the session token and hash it (`generateToken`, `hashToken`).
4. `redeemed = await redeemEmailCode(db, body.challenge_id, body.code, now)`. Not ok → `logMeta("sign_in_refused", { provider: "email", reason })`, then `Errors.invalidCode()` for `invalid_code`, `Errors.codeExpired()` for `code_expired`.
5. `verified: VerifiedIdToken = { provider: "email", subject: redeemed.email, email: redeemed.email, isPrivateEmail: false, audience: "" }`. The address comes from the challenge row only; the body carries none.
6. One `db.transaction`, shaped like the Google route's (`routes/sign-in.ts:52-79`), with `match = matchAccount(db, verified, config.passwordLogin)`:
   - `switch_required` → reason `switch_required`, 409 `Errors.switchFromSignedInDevice()`;
   - `identity` → update `last_used_at`; `via = "identity"`;
   - `email` with `hasPrimary` → `insertIdentity(db, userId, identityFromToken(verified), now)`; `via = "email"`. Nothing else of the account changes;
   - `email` without `hasPrimary` (Ruling 12): if `SELECT 1 FROM identities WHERE user_id = ?` finds a row → reason `other_sign_in`, 409 `Errors.switchFromSignedInDevice()`, nothing written. Otherwise `dropped = dropPasswordAccess(db, userId)`, then `DELETE FROM tokens WHERE device_id IN (SELECT id FROM devices WHERE user_id = ?)` (add its `changes` to `dropped`), then `insertIdentity`; `via = "email"`;
   - `none` → insert the user (`password_hash` NULL, as the Google route does) and the identity; `via = "new_account"`;
   - then `signInDevice(db, userId, device, tokenHash, "email", identityId, now)` and return `{ userId, deviceId, email: accountEmail(db, userId) }`.
   Log `sign_in_refused {provider: "email", reason}` for the two 409s.
7. `recordAppVersion`; `logMeta("sign_in", { device_id, provider: "email", via })`; `password_access_dropped {sessions: dropped}` when `dropped > 0`; answer 200 `{ user_id, device_id, token, email }`.

- [ ] **Step 5: Run the tests to see them pass**

Run: `(cd relay && npx vitest run test/auth-email-verify.test.ts test/auth-email-code.test.ts)`, then `(cd relay && npm test && npm run typecheck)`.
Expected: `Test Files  2 passed (2)`; no failed file; no `error TS` line.

- [ ] **Step 6: Commit**

```bash
git add relay/src/routes/email-sign-in.ts
git commit -m "feat(relay): POST /v1/auth/email/verify signs in with an email code; links by verified email"
```

---

### Task 7: Google and email sign-ins in one account

**Files:**
- Modify: `relay/src/auth/identity.ts:31`, `relay/src/routes/sign-in.ts:108-133`, `relay/src/routes/identities.ts:42-57`
- Test: `relay/test/auth-google.test.ts`, `relay/test/auth-google-link.test.ts`, `relay/test/identities.test.ts`

**Interfaces:**
- Consumes: `emailSession` and `FakeEmailGateway`.
- Produces: `hasPrimary` means "has a Google or test identity"; `/google/link` works on an account that has only an email sign-in and removes that sign-in when the account's email changes; an identity can be removed while another of Google / test / email remains.

- [ ] **Step 1: Write the failing tests**

In each file import `FakeEmailGateway` from `./fake-email.js` and `emailSession` from `./helpers.js`.

`relay/test/auth-google.test.ts`, inside the `describe`:

```ts
  it("joins an account created with an email code for the same address; a second Google account with it is still refused", async () => {
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail });
    const e = await emailSession(app, mail, { email: "ann.lee@example.com" });
    const g = await googleSession(app, { email: "Ann.Lee@Example.com" });
    expect(g.userId).toBe(e.userId);
    expect(db().all("SELECT provider FROM identities WHERE user_id = ? ORDER BY provider", e.userId)).toEqual([{ provider: "email" }, { provider: "google" }]);
    expect((await devices(app, e.token)).status).toBe(200);
    const other = await signInGoogle(app, { email: "ann.lee@example.com" });
    expect([other.status, await errorCode(other)]).toEqual([401, "invalid_credentials"]);
  });
```

`relay/test/auth-google-link.test.ts`, inside the `describe`:

```ts
  it("links Google to an account created with an email code; a different Google address becomes the account's and removes the email sign-in", async () => {
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail });
    const providers = (userId: string) => db().all<{ provider: string }>("SELECT provider FROM identities WHERE user_id = ? ORDER BY provider", userId).map((r) => r.provider);
    const same = await emailSession(app, mail, { email: "same@example.com" });
    expect((await link(app, same.token, await googleIdToken(app, { email: "Same@Example.com" }))).status).toBe(200);
    expect(providers(same.userId)).toEqual(["email", "google"]);

    const phone = await emailSession(app, mail, { email: "old@example.com", kind: "mobile" });
    const desk = await emailSession(app, mail, { email: "old@example.com", kind: "desktop" });
    const moved = await link(app, desk.token, await googleIdToken(app, { email: "New@Example.org" }));
    expect(moved.status).toBe(200);
    const body = await moved.json<{ user_id: string; token: string; email: string }>();
    expect([body.user_id, body.email]).toEqual([desk.userId, "new@example.org"]);
    expect(providers(desk.userId)).toEqual(["google"]);
    expect((await call(app, "GET", "/v1/devices", { token: phone.token })).status).toBe(401); // signed in with the address that went
    expect((await call(app, "GET", "/v1/devices", { token: body.token })).status).toBe(200);
    expect((await emailSession(app, mail, { email: "old@example.com" })).userId).not.toBe(desk.userId);
    expect((await emailSession(app, mail, { email: "new@example.org" })).userId).toBe(desk.userId);
  });
```

`relay/test/identities.test.ts`, inside the `describe`:

```ts
  it("lists an email sign-in and removes Google or email while the other remains, but never the last of them", async () => {
    const mail = new FakeEmailGateway();
    const app = makeApp({ now: () => T0, email: mail });
    const g = await googleSession(app, { email: "ann@example.com", kind: "desktop" });
    const e = await emailSession(app, mail, { email: "ann@example.com", kind: "mobile" });
    const listed = (await (await list(app, g.token)).json<{ identities: { identity_id: string; provider: string }[] }>()).identities;
    expect(listed).toEqual([
      { identity_id: expect.stringMatching(UUID), provider: "google", email: "ann@example.com", is_private_email: false, linked_via_device_name: null, created_at_unix: T0 / 1000 },
      { identity_id: expect.stringMatching(UUID), provider: "email", email: "ann@example.com", is_private_email: false, linked_via_device_name: null, created_at_unix: T0 / 1000 },
    ]);
    const idOf = (provider: string) => listed.find((i) => i.provider === provider)!.identity_id;
    expect((await remove(app, g.token, idOf("email"))).status).toBe(204);
    expect((await call(app, "GET", "/v1/devices", { token: e.token })).status).toBe(401);
    const last = await remove(app, g.token, idOf("google"));
    expect([last.status, await errorCode(last)]).toEqual([409, "last_google_identity"]);

    const back = await emailSession(app, mail, { email: "ann@example.com", kind: "mobile" });
    expect((await remove(app, back.token, idOf("google"))).status).toBe(204);
    expect((await call(app, "GET", "/v1/devices", { token: g.token })).status).toBe(401);
    const emailId = db().get<{ id: string }>("SELECT id FROM identities WHERE user_id = ?", back.userId)!.id;
    expect(await errorCode(await remove(app, back.token, emailId))).toBe("last_google_identity");
  });
```

- [ ] **Step 2: Run them to see them fail**

Run: `(cd relay && npx vitest run test/auth-google.test.ts test/auth-google-link.test.ts test/identities.test.ts)`
Expected: `Test Files  2 failed | 1 passed (3)`: Google answers 401 for the email-created account and `/google/link` answers 409 `identity_in_use`. The new `identities.test.ts` test passes already (Ruling 15): it records the rule so the SQL edit cannot change it.

- [ ] **Step 3: Commit the failing tests**

```bash
git add relay/test/auth-google.test.ts relay/test/auth-google-link.test.ts relay/test/identities.test.ts
git commit -m "test(relay): Google and email sign-ins share an account; an email change drops the email sign-in"
```

- [ ] **Step 4: Implement** (Ruling 15)

- `relay/src/auth/identity.ts:31`: `provider != 'apple'` → `provider IN ('google', 'test')`. Update the doc comment of `matchAccount`.
- `relay/src/routes/sign-in.ts:115`: the same replacement. In the branch that updates `users.email` (118-121), after the update, `DELETE FROM identities WHERE user_id = ? AND provider = 'email' RETURNING id` (its tokens cascade; the caller's new token is written just after by `replaceDeviceToken`). After the transaction, when a row was deleted, `logMeta("identity_removed", { device_id: auth.deviceId, identity_id })`.
- `relay/src/routes/identities.ts:55`: count `provider IN ('google', 'test', 'email')`; `<= 1` → `Errors.lastGoogleIdentity()` (same behaviour, explicit list). Update the two doc comments ("The Google sign-in cannot be removed" is no longer true).

- [ ] **Step 5: Run the tests to see them pass**

Run: the command of Step 2, then `(cd relay && npm test && npm run typecheck)`.
Expected: `Test Files  3 passed (3)`; no failed file; no `error TS` line.

- [ ] **Step 6: Commit**

```bash
git add relay/src/auth/identity.ts relay/src/routes/sign-in.ts relay/src/routes/identities.ts
git commit -m "feat(relay): Google and email sign-ins live in one account"
```

---

### Task 8: Delete an account with an email code

**Files:**
- Modify: `relay/src/routes/account.ts:14-48`
- Test: `relay/test/account.test.ts`, `relay/test/signin-logs.test.ts`

**Interfaces:**
- Consumes: `redeemEmailCode`; `Errors.invalidCode`, `Errors.codeExpired`, `Errors.reauthRequired`.
- Produces: `DELETE /v1/account` with `{challenge_id, code}`.

- [ ] **Step 1: Write the failing tests**

`relay/test/account.test.ts`: import `FakeEmailGateway` from `./fake-email.js`, add `emailSession` and `requestEmailCode` to the `./helpers.js` import, and append:

```ts
describe("DELETE /v1/account with an email code (spec 2026-11-10 §4)", () => {
  const T0 = 1_800_000_000_000;
  const CODE = "004217";
  const del = (app: TestApp, token: string, body: Record<string, unknown>) => call(app, "DELETE", "/v1/account", { token, body });
  const users = (userId: string) => db().get<{ n: number }>("SELECT COUNT(*) AS n FROM users WHERE id = ?", userId)!.n;
  const codes = () => db().get<{ n: number }>("SELECT COUNT(*) AS n FROM email_codes")!.n;

  it("deletes for a code sent to the account's own address, from an email session and from a Google session of that account", async () => {
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail, emailCode: () => CODE });
    const s = await emailSession(app, mail, { email: "ann@example.com" });
    const c = await requestEmailCode(app, mail, " ANN@example.com");
    expect((await del(app, s.token, { challenge_id: c.challengeId, code: CODE })).status).toBe(204);
    expect([users(s.userId), codes(), db().get<{ n: number }>("SELECT COUNT(*) AS n FROM identities")!.n]).toEqual([0, 0, 0]);
    expect((await call(app, "GET", "/v1/devices", { token: s.token })).status).toBe(401);
    expect((await emailSession(app, mail, { email: "ann@example.com" })).userId).not.toBe(s.userId); // the address is free again

    const g = await googleSession(app, { email: "bob@example.com" });
    const forGoogle = await requestEmailCode(app, mail, "bob@example.com");
    expect((await del(app, g.token, { challenge_id: forGoogle.challengeId, code: CODE })).status).toBe(204);
    expect(users(g.userId)).toBe(0);
  });

  it("answers 401 invalid_code to a wrong code and counts it, and 410 code_expired once the code is burnt, expired or unknown; nothing is deleted", async () => {
    let now = T0;
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail, emailCode: () => CODE, now: () => now });
    const s = await emailSession(app, mail, { email: "ann@example.com" });
    const c = await requestEmailCode(app, mail, "ann@example.com");
    for (let n = 1; n <= 4; n++) {
      const wrong = await del(app, s.token, { challenge_id: c.challengeId, code: "004218" });
      expect([wrong.status, await errorCode(wrong)]).toEqual([401, "invalid_code"]);
      expect(db().get("SELECT attempts FROM email_codes")).toEqual({ attempts: n });
    }
    const fifth = await del(app, s.token, { challenge_id: c.challengeId, code: "004218" });
    expect([fifth.status, await errorCode(fifth)]).toEqual([410, "code_expired"]);
    const late = await requestEmailCode(app, mail, "ann@example.com");
    now = T0 + 600_000;
    for (const challengeId of [c.challengeId, late.challengeId, "n".repeat(43)]) {
      const res = await del(app, s.token, { challenge_id: challengeId, code: CODE });
      expect([res.status, await errorCode(res)]).toEqual([410, "code_expired"]);
    }
    expect(users(s.userId)).toBe(1);
  });

  it("answers 401 reauth_required to a code that went to another address (the code is spent) and to a code without a challenge id", async () => {
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail, emailCode: () => CODE });
    const s = await emailSession(app, mail, { email: "ann@example.com" });
    const other = await requestEmailCode(app, mail, "bob@example.com");
    for (const body of [{ challenge_id: other.challengeId, code: CODE }, { code: CODE }]) {
      const res = await del(app, s.token, body);
      expect([res.status, await errorCode(res)]).toEqual([401, "reauth_required"]);
    }
    expect([users(s.userId), codes()]).toEqual([1, 0]);
  });

  it("shares the 5 per account email per minute budget; a refused call spends no guess", async () => {
    const loginEmail = new CountingLimiter(1);
    const mail = new FakeEmailGateway();
    const app = makeApp({ email: mail, emailCode: () => CODE, limiters: { ...unlimited, loginEmail } });
    const s = await emailSession(app, mail, { email: "ann@example.com" });
    const c = await requestEmailCode(app, mail, "ann@example.com");
    expect((await del(app, s.token, { challenge_id: c.challengeId, code: "004218" })).status).toBe(401);
    expect((await del(app, s.token, { challenge_id: c.challengeId, code: CODE })).status).toBe(429);
    expect(loginEmail.calls).toEqual(["ann@example.com", "ann@example.com"]);
    expect(db().get("SELECT attempts FROM email_codes")).toEqual({ attempts: 1 });
    expect(users(s.userId)).toBe(1);
  });
});
```

`relay/test/signin-logs.test.ts`: import `FakeEmailGateway`, add `deviceBody` and `requestEmailCode` to the `./helpers.js` import, and append:

```ts
it("never logs the address, the code or the challenge id of an email sign-in, a wrong guess or a deletion by code", async () => {
  const lines: string[] = [];
  const capture = (...args: unknown[]) => void lines.push(args.map(String).join(" "));
  for (const level of ["log", "info", "warn", "error"] as const) vi.spyOn(console, level).mockImplementation(capture);
  const mail = new FakeEmailGateway();
  const app = makeApp({ email: mail, emailCode: () => "731946" });
  const verify = (challengeId: string, code: string) =>
    call(app, "POST", "/v1/auth/email/verify", { body: { challenge_id: challengeId, code, device: deviceBody("mobile") } });
  const first = await requestEmailCode(app, mail, "secret.mailbox@example.com");
  await verify(first.challengeId, "731947");
  const session = await (await verify(first.challengeId, "731946")).json<{ token: string }>();
  const second = await requestEmailCode(app, mail, "secret.mailbox@example.com");
  await call(app, "DELETE", "/v1/account", { token: session.token, body: { challenge_id: second.challengeId, code: "731946" } });
  const output = lines.map((line) => line.replace(/"ts":[0-9]+,?/, "")).join("\n");
  for (const event of [
    '"event":"email_code_sent"', '"event":"sign_in_refused","provider":"email","reason":"invalid_code"', '"provider":"email","via":"new_account"', '"event":"account_deleted"',
  ]) expect(output).toContain(event);
  for (const secret of ["secret.mailbox", "731946", "731947", first.challengeId, second.challengeId, session.token]) expect(output).not.toContain(secret);
  expect(output).not.toMatch(/[A-Za-z0-9_-]{43,}/);
});
```

- [ ] **Step 2: Run them to see them fail**

Run: `(cd relay && npx vitest run test/account.test.ts test/signin-logs.test.ts)`
Expected: FAIL: a code body answers 401 `reauth_required` and deletes nothing.

- [ ] **Step 3: Commit the failing tests**

```bash
git add relay/test/account.test.ts relay/test/signin-logs.test.ts
git commit -m "test(relay): DELETE /v1/account with an email code; email flows log no address, code or challenge"
```

- [ ] **Step 4: Implement**

In `relay/src/routes/account.ts`, a new branch between the ID-token branch and the password branch, after the existing `loginEmail` check (Ruling 13):

- `typeof body.challenge_id === "string"` → `redeemed = await redeemEmailCode(db, body.challenge_id, body.code, c.get("now")())`;
- not ok → `denied(Errors.invalidCode)` for `invalid_code`, `denied(Errors.codeExpired)` for `code_expired`;
- `redeemed.email !== user.email` → `denied(Errors.reauthRequired)`;
- otherwise fall through to the existing delete.

Update the route's doc comment (three confirmations).

- [ ] **Step 5: Run the tests to see them pass**

Run: the command of Step 2, then `(cd relay && npm test && npm run typecheck)`.
Expected: `Test Files  2 passed (2)`; no failed file; no `error TS` line.

- [ ] **Step 6: Commit**

```bash
git add relay/src/routes/account.ts
git commit -m "feat(relay): delete an account after a code sent to its own address"
```

---

### Task 9: Deploy passthrough and runbooks

**Files:**
- Modify: `deploy/docker-compose.yml` (after `PASSWORD_LOGIN`), `deploy/README.md` (a new section before "Admin (admin.shellx.pro)"), `relay/README.md`
- Test: `deploy/tests/compose.test.mjs`

- [ ] **Step 1: Write the failing test**

Append to `deploy/tests/compose.test.mjs`:

```js
test('email sign-in: the relay takes RESEND_API_KEY and EMAIL_FROM from .env only, and no Resend key is written in the deploy files', () => {
  const relay = service('relay');
  for (const name of ['RESEND_API_KEY', 'EMAIL_FROM']) {
    assert.match(relay, new RegExp(`^ {6}${name}: \\$\\{${name}:-\\}$`, 'm'), name);
  }
  const relayEnv = readFileSync(join(deployDir, 'relay.env'), 'utf8');
  assert.doesNotMatch(relayEnv, /RESEND|EMAIL_FROM/);
  const readme = readFileSync(join(deployDir, 'README.md'), 'utf8');
  assert.match(readme, /^## Email sign-in \(once, by hand\)$/m);
  // Resend keys start with "re_": none may appear in the compose file, relay.env or the runbook.
  assert.doesNotMatch(compose + relayEnv + readme, /\bre_[A-Za-z0-9]{8,}/);
});
```

- [ ] **Step 2: Run it to see it fail**

Run: `node --test deploy/tests/compose.test.mjs`
Expected: `fail 1`: the relay service has no `RESEND_API_KEY` line.

- [ ] **Step 3: Commit the failing test**

```bash
git add deploy/tests/compose.test.mjs
git commit -m "test(deploy): the relay takes RESEND_API_KEY and EMAIL_FROM from .env only"
```

- [ ] **Step 4: Implement**

`deploy/docker-compose.yml`, in the relay's `environment`, after `PASSWORD_LOGIN`:

```yaml
      # Sign-in with an email code, sent through Resend (deploy/README.md, "Email sign-in"), set once by hand
      # in .env: the Resend API key (a secret, never in this repository) and the sender, e.g.
      # EMAIL_FROM="ShellX <sign-in@shellx.pro>". Both empty: POST /v1/auth/email/code answers 503 and the
      # relay runs as before; exactly one set: the relay refuses to start.
      RESEND_API_KEY: ${RESEND_API_KEY:-}
      EMAIL_FROM: ${EMAIL_FROM:-}
```

`deploy/README.md`, a new section before `## Admin (admin.shellx.pro)`, exactly:

````markdown
## Email sign-in (once, by hand)

The relay can sign people in with a 6-digit code it mails through Resend (`POST /v1/auth/email/code`;
relay README, "Sign-in"). It is off until both variables below are in the VPS's `.env`; with only one of
them the relay refuses to start.

1. Create a Resend account and add the sending domain (`shellx.pro`). Resend shows DKIM and SPF records:
   add them to the domain's DNS and wait until Resend shows the domain as **Verified**. Before that Resend
   only sends from `onboarding@resend.dev` to the account owner's own address, which is enough for a first try.
2. Create an API key with **Sending access**, limited to that domain. It is a secret: it goes into `.env`
   on the VPS and nowhere else (not this repository, not `relay.env`, not a chat).
3. On the VPS (the key is typed at a prompt, so it is not echoed and not kept in the shell history):

   ```bash
   cd ~/phu/shellx
   [ -z "$(tail -c1 .env)" ] || echo >> .env          # end .env with a newline first
   read -rsp 'Resend API key: ' RESEND_KEY && echo
   printf 'RESEND_API_KEY=%s\nEMAIL_FROM="ShellX <sign-in@shellx.pro>"\n' "$RESEND_KEY" >> .env && unset RESEND_KEY
   docker compose config | grep EMAIL_FROM            # EMAIL_FROM: ShellX <sign-in@shellx.pro>
   docker compose up -d --force-recreate relay
   docker compose logs relay | grep email_sign_in     # email_sign_in_enabled
   ```

4. Ask for a code in an app with your own address. If no mail arrives, look in the spam folder and at
   the domain's status in Resend; the relay logs `email_send_failed` with Resend's status code (never
   the address). Resend's free plan sends 100 mails a day: past that, codes fail with 502 until the next day.

To switch it off, remove both lines from `.env` and recreate the relay: `/v1/auth/email/code` answers 503,
the apps show "not available", and Google and Apple sign-in are not affected.
````

`relay/README.md`, these facts in the existing places:
- Configuration table: a row for `RESEND_API_KEY`, `EMAIL_FROM` (default unset): what they are; both set → on, `email_sign_in_enabled`; both unset → off, `email_sign_in_disabled`, `/v1/auth/email/code` answers 503; exactly one, or an `EMAIL_FROM` that is not `address` or `Name <address>`, stops the relay; for local development export both in the shell and never put the key into `dev.env` (it is committed).
- The migrations paragraph: `0011_email_sign_in.sql` adds `email_codes` and lets `identities.provider` and `tokens.auth_method` be `email`.
- "Rate limits": email codes 10 per IP per minute, and per address 3 per minute and 10 per hour.
- The "Sign-in" section: the two new routes and the third `DELETE /v1/account` body in the table (shapes and codes of Global Constraints); a paragraph "Email code" (hashes only, 600 s, 5 guesses, newest only, same 202 for every address, no link in the mail); the account rules of Task 6 and Task 7; identities: one of Google / email must remain; deletion also by a code sent to the account's address.

- [ ] **Step 5: Run the tests to see them pass**

Run: `node --test deploy/tests/compose.test.mjs`
Expected: `pass 21`, `fail 0`.

- [ ] **Step 6: Commit**

```bash
git add deploy/docker-compose.yml deploy/README.md relay/README.md
git commit -m "docs(deploy): RESEND_API_KEY and EMAIL_FROM passthrough; email sign-in runbook and relay README"
```

---

### Task 10: Contracts §29, final verification and report

**Files:**
- Modify: `docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md` (append §29; if `develop` gained a §29 meanwhile, say so in the report and let the orchestrator renumber at the merge)

- [ ] **Step 1: Append the contracts section, exactly**

````markdown
## 29. Additions from the email-code sign-in plan, relay part

Spec S4 `docs/superpowers/specs/2026-11-10-shellx-email-code-sign-in-design.md`; plan
`2026-11-11-shellx-email-code-signin-relay.md`. Owner: the relay; consumers: the Android, iPhone, shellx-core / Mac and
Windows plans of S4. Amends §2: provider values gain `email`; `tokens.auth_method` gains `email`; `DELETE /v1/account`
takes a third body.

New `Errors` entries (name → status, code); `invalid_email` and `disposable_email` (both 400) existed:

| Name | Status | Code |
| --- | --- | --- |
| `invalidCode` | 401 | `invalid_code` |
| `codeExpired` | 410 | `code_expired` |
| `emailSignInDisabled` | 503 | `email_sign_in_disabled` |
| `emailSendFailed` | 502 | `email_send_failed` |

Routes:

| Route | Auth | Body | Success | Errors |
| --- | --- | --- | --- | --- |
| `POST /v1/auth/email/code` | none | `{email, locale?}` (`locale` `"en"` or `"vi"`; anything else is English) | 202 `{challenge_id, expires_in, resend_in, email}` (43-char base64url, 600, 60, the address trimmed and lower-cased) | 400 `invalid_email`, 400 `disposable_email`, 429 `rate_limited`, 503 `email_sign_in_disabled`, 502 `email_send_failed` |
| `POST /v1/auth/email/verify` | none | `{challenge_id, code, device}` (`code`: a string of 6 digits; `device` as for `/v1/auth/google`, kind `desktop` or `mobile`) | 200 `{user_id, device_id, token, email}` | 401 `invalid_code`, 410 `code_expired`, 409 `switch_from_signed_in_device`, 400 `invalid_device`, 429 `rate_limited` |
| `DELETE /v1/account` | bearer | `{challenge_id, code}` | 204 | 401 `invalid_code`, 410 `code_expired`, 401 `reauth_required`, 429 `rate_limited` |

Rules the clients rely on:
- A relay without this feature answers 404 `not_found` to both routes; a relay without Resend answers 503
  `email_sign_in_disabled` to `/code`. Clients show the button always and treat both as "not available" (S4 §7).
- `/code` answers the same 202 for every valid address, with or without an account. One live code per address: a new
  request makes the earlier `challenge_id` answer 410, so the client always keeps the newest answer's `challenge_id`.
- `resend_in` is the client's lock on its Resend button. The relay's own limits are 10 requests per IP per minute and,
  per address, 3 per minute and 10 per hour; past them it answers 429 `rate_limited`.
- The code is a string of 6 digits and keeps its leading zeros (`"004217"`). It lives 600 s and takes 5 guesses: wrong
  guesses 1 to 4 answer 401 `invalid_code` and the challenge stays; the 5th wrong guess answers 410 `code_expired`. On
  410 the client goes back to asking for a new code. `/verify` shares the 10 per IP per minute login limit.
- `/verify` creates the account on first use, or signs in to the account that has this address: one made by email code,
  or one made with Google for the same address, which then lists both sign-ins. The session's `auth_method` is `email`.
- `/verify` 409 `switch_from_signed_in_device`: the address belongs to an account a code cannot open (its password still
  works, or its address was never verified and it has an Apple ID attached). The code is spent.
- `GET /v1/account/identities` lists `provider: "email"` (`email` is the address, `is_private_email` false).
  `DELETE /v1/account/identities/:identity_id` answers 409 `last_google_identity` for the account's last sign-in among
  Google and email (the code keeps its name for old apps; it now means "keep at least one way to sign in"). Removing
  the email sign-in signs out the devices that used it.
- `POST /v1/auth/google/link` works on an account made by email code. When Google's address differs from the account's,
  the account's email becomes Google's and the email sign-in is removed: devices signed in by code are signed out, and
  the calling device gets its new `google` token in the answer.
- Delete by code: the client asks `/code` for the account's own address and sends `{challenge_id, code}` with its
  bearer. A code that went to another address answers 401 `reauth_required`; wrong guesses count as on `/verify`.
- Env (through `deploy/docker-compose.yml`): `RESEND_API_KEY`, `EMAIL_FROM` (`ShellX <sign-in@shellx.pro>`); both or
  neither. Start-up events: `email_sign_in_enabled`, `email_sign_in_disabled`.
- Mail subjects: `Your ShellX sign-in code is 123456`, `Mã đăng nhập ShellX của bạn là 123456`; the mail has no link.
````

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/plans/2026-11-07-shellx-mobile-contracts.md
git commit -m "docs(shellx): contracts §29: email-code sign-in API, error codes and client rules"
```

- [ ] **Step 3: Run the full verification**

```bash
(cd relay && npm ci && npm test && npm run typecheck && npm run build && rm -rf dist)
node --test deploy/tests/compose.test.mjs
node --check scripts/shellx/share-e2e.mjs
python3 scripts/verify-local.py
git diff --stat develop...HEAD -- web/
git diff develop...HEAD | grep -cE '^\+.*\bre_[A-Za-z0-9]{8,}'
git log --oneline develop..HEAD
```

Expected:
- vitest `Test Files  63 passed | 1 skipped (64)`, `Tests  807 passed | 7 skipped (814)` (or more, if `develop` moved); no `error TS` line; the build succeeds;
- the compose tests end with `pass 21`, `fail 0`. The other deploy test files run on their own fixtures and read none of the files this branch changes; on this Mac `deploy/tests/backup.test.mjs` already has one failing test on `develop` (2026-11-11), which is not yours;
- `node --check` prints nothing;
- `verify-local.py`: the hand-off's "Known noise" applies (`feature-flags` may fail on a date unrelated to this branch); anything else red is yours;
- the `web/` diff is empty; the `grep -c` prints `0` (no added line looks like a Resend key); the log shows two commits per task (one for Task 10).

Fix anything red before reporting. Do not merge, push, deploy or run `deploy/vps-deploy.sh`.

- [ ] **Step 4: Report**

Report: the branch tip; the red and green result of each task's focused command; the final verification output; any deviation from this plan and why; the Follow-ups below. The whole-branch review and the merge into `develop` are the orchestrator's.

---

## Spec notes

For the reviewer and the user: where S4 looks wrong or risky. None of these is fixed here unless a Ruling says so.

1. **Sending is open to anyone.** `/code` needs no account, and the limits are 10 per minute per IP with no global ceiling: one client on one IP can use up Resend's free 100 mails a day in ten minutes (email sign-in then fails for everyone until the next day), or send ShellX mail to many strangers, which hurts the sender domain's reputation. Dot and `+tag` variants of one Gmail mailbox are separate limiter keys, so one mailbox can get far more than 10 mails an hour. A global hourly ceiling and an hourly per-IP limit would bound this; S4 fixes the limiter set, so the plan adds neither.
2. **Anyone who knows an address can lock its owner out of email sign-in.** Each request replaces the pending code, and 10 requests use up the hour. Existing sessions and Google sign-in are not affected.
3. **Never-verified addresses (Ruling 12).** The same hole exists today on the Google route (`relay/src/routes/sign-in.ts:61-70`): a Google sign-in links by email into a legacy account that has no Google sign-in and removes only password sessions, so an Apple ID attached by whoever registered that address first keeps its session. Out of scope here; it needs a decision.
4. **A session token can now take over an account.** With S4's rules, a stolen bearer token of an account made by email code can call `POST /v1/auth/google/link` with any Google account: the account's email changes and the owner's email sign-in is removed. For an account with Google and email, the token can first remove the Google sign-in (allowed while email remains) and then do the same. Before S4 an account made with Google was safe from this (`identity_in_use`, and Google could not be removed). Asking for a fresh code or ID token on `/google/link` and on identity removal would close it; that changes the client contract, so it is left to the user.
5. **S4 §9 says a pending address is exposed "for at most 10 minutes".** Rows are deleted only when a later request arrives (Ruling 6 adds `/verify` and delete-by-code to `/code`); on an idle relay an expired row can stay longer. It cannot be used.
6. **The Idempotency-Key does nothing today:** the relay never retries and every request has a new row id. It is harmless and kept as S4 asks.
7. **Limiters live in memory:** a relay restart (every deploy) resets the per-address and per-IP budgets. Existing behaviour of every limiter.
8. **Not checked against the live service:** no Resend key exists on this machine, so the request shape is checked against Resend's API reference only (endpoint, `Idempotency-Key` of at most 256 characters kept 24 h, mandatory User-Agent, 2xx = accepted). The `EMAIL_FROM="…"` quoting in `.env` follows Compose's env-file syntax and was not run; the runbook's `docker compose config` line checks it on the VPS.

## Follow-ups (not in this plan)

- `web/src/pages/privacy.md` (S4 §8): "We do not send verification or marketing emails" → "We send a sign-in code by email only when you ask for one (through Resend, resend.com); no marketing email", and the email sign-in under "Sign-in methods". It goes out with the user's own push to `main`.
- `docs/superpowers/HANDOFF-shellx-mobile.md`: the landing entry and the user's Resend steps (domain DNS, key, the two variables), with plan 1D. Before 1D deploys, run migration 0011 on a copy of the production database (`PRAGMA foreign_key_check` empty), as the Relay v2 runbook does for 0005.
- The client plans (Android, iPhone, shellx-core + Mac, Windows) match "The API contract" below and contracts §29.
- Decisions for the user: Spec notes 1, 3 and 4.

## The API contract for the client plans

```
POST /v1/auth/email/code     {email, locale?: "en"|"vi"}
  -> 202 {challenge_id, expires_in: 600, resend_in: 60, email}
     400 invalid_email | 400 disposable_email | 429 rate_limited | 503 email_sign_in_disabled | 502 email_send_failed

POST /v1/auth/email/verify   {challenge_id, code, device}      code: string of 6 digits; device.kind: "desktop" | "mobile"
  -> 200 {user_id, device_id, token, email}
     401 invalid_code | 410 code_expired | 409 switch_from_signed_in_device | 400 invalid_device | 429 rate_limited

DELETE /v1/account           Authorization: Bearer <token>, {challenge_id, code}
  -> 204 | 401 invalid_code | 410 code_expired | 401 reauth_required | 429 rate_limited

every error: {"error": {"code", "message"}}; a relay without the feature: 404 not_found
identity provider "email" (subject and email = the normalised address); session auth_method "email"
```

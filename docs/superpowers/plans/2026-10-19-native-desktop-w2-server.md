# ShellX native desktop — Wave 2 server: API v2 + relay v2 (sprint lane L4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Tóm tắt (cho người dùng):** Lane L4 làm phần máy chủ cho việc Mac/Windows xem nhau: thêm loại thiết bị `desktop`, bảng máy / ghép cặp / quyền vào SQLite của relay hiện có, các API `/v2/machines`, `/v2/pairings`, `/v2/relay/tickets` đúng hợp đồng K1, cấp ticket HMAC mà `cmux-relay` thật chấp nhận (đã kiểm bằng binary thật), mã ghép cặp 6 số hết hạn sau 5 phút, máy chủ chỉ giữ bản mã của lời mời (khoá PSK không bao giờ đi qua máy chủ ở dạng rõ), `/v1/version` trả mức tối thiểu riêng cho từng nền tảng mà không làm hỏng app Flutter, và container `relay2` (ảnh build trên CI của fork) chạy sau `nginx-proxy` tại `wss://relay.shellx.pro/v2/relay`. Ở cổng G2 bạn tự đặt secret trên VPS (không dán vào chat), bật ảnh `shellx-relay2` thành công khai, và quyết định cách deploy (xem "Câu hỏi mở" số 1: deploy chỉ chạy được từ `main`). Bản Flutter 1.0.1 chỉ được sửa code trên nhánh riêng, không phát hành.

**Goal:** Implement contracts K1 (ShellX API v2) and K2 (relay v2 on the VPS) of the 2026-10-19 sprint exactly, test-first, ready to deploy at gate G2 (~T+3:30), plus C15 (`/v1/version` per platform) and the Flutter 1.0.1 code change (no release).

**Architecture:** Everything server-side stays in the existing Node 22 + Hono + better-sqlite3 relay (`relay/`): one forward-only migration adds the `desktop` device kind (table rebuild, foreign keys off for that migration only) and three tables (`machines`, `machine_pairings`, `machine_grants`); a new `relay/src/v2/` folder holds the routes and the pure ticket/encoding helpers. The opaque packet relay is the fork's MIT-declared `cmux-relay` crate in its own container `relay2`, built and pushed by fork CI, pinned by commit sha in `deploy/docker-compose.yml`, reached through `nginx-proxy` on the existing `relay.shellx.pro` host by an exact-match path route (subdomain fallback kept ready).

**Tech Stack:** shellx repo: Node 22, Hono 4, better-sqlite3 13, vitest 4, `node:crypto` (HMAC-SHA256, SHA-256, `randomBytes`, `randomInt`), `ws` 8 (already a dependency), Docker Compose behind `nginx-proxy` + acme-companion, GitHub Actions `deploy.yml`. Fork: Rust 1.95.0 (`cmux-tui/rust-toolchain.toml`), `cmux-relay` 0.1.0, Docker, GitHub Actions on `lephus/shellx`, Python 3 stdlib `unittest`.

**Spec:** `docs/superpowers/specs/2026-10-18-shellx-native-desktop-design.md` (§5, §8.5, §11 "Chuyển người dùng bản Flutter", C15, C16, D-W0-1 amendments). Master plan (binding: K1, K2, Global Constraints, Review Focus #2/#3, gate G2, Clock row L4): `docs/superpowers/plans/2026-10-19-native-desktop-12h-sprint.md`. Ledger (binding facts): `docs/superpowers/ledgers/native-desktop.md` — "Ticket format the ShellX API must mint", "Spec implication (§8.5)", relay opacity spike, D-W0-1. C15 shape: K6 table in `docs/superpowers/plans/2026-10-19-native-desktop-w3-release-share.md` (Task A1); implementing it here lets W3 A1 take its skip condition.

## Global Constraints

- Branches: shellx `feat/relay-v2` in worktree `~/Documents/myProjects/shellx-wt-l4` (from `main`); fork `shellx/l4-relay2` in worktree `~/Documents/myProjects/shellx-wt-l4` (from `shellx/sprint`); Flutter change on shellx `feat/flutter-1.0.1` in worktree `~/Documents/myProjects/shellx-wt-l4-flutter` (from `main`). Paths below are relative to the matching worktree.
- Never push shellx `main` (master rule). Never push shellx feature branches either unless L0 asks (user preference: local merges only). Fork branch pushes are allowed (free CI): `git push git@phule9225.github.com:lephus/shellx.git shellx/l4-relay2`.
- K1 paths, bodies, status codes and field names are frozen; errors always `{"error":{"code","message"}}` from `relay/src/http/errors.ts`; every authenticated route uses `requireAuth` (`relay/src/auth/session.ts`), then `jsonBodyLimit` for bodies.
- Ticket format exactly as the ledger: `"v2." + b64url_nopad(json) + "." + b64url_nopad(HMAC-SHA256(key, signing_payload))`, issuer `shellx-relay`, lifetime 120 s, key = raw bytes of `CMUX_RELAY_HMAC_SECRET` (never trimmed), `circuit`/`lane`/`generation` = `null`.
- The server never sees an invitation in clear: it stores and returns `sealed_invite_b64` verbatim, never decodes it beyond a length check and a plaintext guard.
- Never put a secret value in chat, a commit, a log line or a test fixture that looks real; test secrets are the literal `0123456789abcdef0123456789abcdef` (32 bytes). `logMeta` never receives tickets, slots, codes, keys, invites, e-mail or IPs.
- Times: unix milliseconds in SQLite (repo convention), unix seconds in every `*_unix` API field.
- No new npm or Cargo dependencies. No third-party services or telemetry. No BUSL code: the relay2 image build context is an allowlist that excludes `cmux-tui/relays/` (BUSL `cloudflare-do`).
- Every relay change must keep `cd relay && npm run typecheck && npm test` green (the image build runs both; a red test blocks deploy) and `node --test deploy/tests/*.test.mjs` green.

## Review Focus

1. **Migration 0005 on the production database** (rebuilds `devices` to allow `kind = 'desktop'`): every user, device, token, v1 pairing, push token and setting must survive, existing phones and Flutter agents must stay signed in, and foreign-key cascades must still work afterwards. Test: Task 1 `0005 keeps every v1 row and token` (a database migrated to 0004 and filled first).
2. **A ticket the Node API mints but the real `cmux-relay` refuses** (secret trimmed on one side, issuer mismatch, JSON vs signing payload, clock skew) — the remote feature would be dead on arrival while every unit test passes. Tests: Task 2 golden vectors (signatures produced independently with `openssl` and checked against the `cmux-relay ticket` CLI on 2026-10-19), Task 2 `keeps CMUX_RELAY_HMAC_SECRET verbatim`, Task 6 interop suite against the real binary.
3. **Approval spoofing** (master Review Focus #3): a requester cannot choose its code or fingerprint, cannot approve itself, another machine cannot approve, an expired or already-decided request cannot be approved, and two pending requests to one target never share a code. Test: Task 4 `spoofing` describe block (incl. concurrent double approve).
4. **The new `desktop` kind leaking into v1** — admin dashboard stats (`devices[row.kind]` would throw), `/v1/ws` hub (a desktop is neither agent nor phone), Flutter phones listing devices. Expected: admin works and counts desktops, `/v1/ws` refuses desktops with 403, phones keep working (they skip unknown kinds, `packages/shellx_core/lib/src/api/shellx_api.dart:88`). Test: Task 1 `desktop-kind.test.ts`.
5. **Flutter 1.0.0 clients after C15** — no `X-ShellX-Platform` header, `flutter-macos` 12/13, `flutter-windows`: the `/v1/version` body must stay byte-for-byte what they get today. Test: Task 9 `legacy audiences keep today's body`.

---

## Clock (agent wall-clock, CI included; master row L4)

| Task | Window | Notes |
| --- | --- | --- |
| 1 Migration 0005 + desktop kind | 0:00–0:35 | tests first (master: "API v2 tests first") |
| 2 Config, errors, encoding, ticket mint | 0:35–1:00 | golden vectors already computed below |
| 3 Machines API | 1:00–1:30 | |
| 4 Pairings API | 1:30–2:10 | security-heavy |
| 5 Relay tickets API | 2:10–2:30 | |
| 6 Interop vs real `cmux-relay` + smoke script | 2:30–2:50 | needs the fork binary |
| 7 Fork: relay2 image + CI | 0:45–1:30 (parallel) | second implementer; CI cold build ~15–25 min |
| 8 Compose, nginx-proxy path route, rollout, runbook | 2:50–3:10 | |
| 10 Security review (tickets, pairings) | 3:10–3:25 | blocks G2 |
| 9 C15 `/v1/version` per platform | 3:00–3:30 (parallel) | if not green by 3:25, G2 ships without it |
| 11 Gate G2 + verification + lane report | ~3:30–4:15 | user gate |
| 12 Flutter 1.0.1 change (no release) | 4:15–5:00 | own branch |
| buffer / L5 support | 5:00–6:00 | then "support, hardening" per master |

---

## File Structure

shellx repo (`~/Documents/myProjects/shellx-wt-l4`):

```
relay/migrations/0005_relay_v2.sql      devices rebuild (+ 'desktop'), machines, machine_pairings, machine_grants
relay/src/db/migrate.ts                 "-- migrate: foreign_keys=off" directive
relay/src/auth/device.ts                DeviceKind + "desktop" (macos|windows only)
relay/src/admin/stats.ts, relay/admin/admin.js   desktop counted and shown
relay/src/routes/ws.ts                  /v1/ws refuses desktop tokens (403)
relay/src/routes/auth.ts                logout of a desktop deletes its machine
relay/src/auth/rate-limit.ts            ticketMint, pairingCreate limiters
relay/src/config.ts                     CMUX_RELAY_HMAC_SECRET, CMUX_RELAY_ISSUER, RELAY_V2_URL, MIN_MACOS, MIN_WINDOWS, NATIVE_MANIFEST_DIR
relay/src/http/errors.ts                v2 error codes
relay/src/server.ts                     logs relay_v2_enabled / relay_v2_disabled {reason}
relay/src/v2/encoding.ts                strict base64, fingerprint, slot
relay/src/v2/tickets.ts                 claims, signing payload, mint (pure)
relay/src/v2/guard.ts                   requireDesktop middleware, machine lookups
relay/src/v2/machines.ts                /v2/machines routes
relay/src/v2/pairings.ts                /v2/pairings routes, grants
relay/src/v2/relay-tickets.ts           /v2/relay/tickets route
relay/src/app.ts                        mounts /v2/*, /v1/version per platform (Task 9)
relay/src/versions.ts, relay/src/settings.ts, relay/src/native-latest.ts   C15 (Task 9)
relay/scripts/relay2-smoke.ts           post-deploy smoke (user runs it at G2)
relay/README.md                         API v2 section
relay/test/{migrate-0005,desktop-kind,v2-encoding,v2-tickets,v2-machines,v2-pairings,v2-relay-tickets,relay2-interop,native-latest}.test.ts
relay/test/{helpers,db,config,versions,app}.test.ts / helpers.ts   extended
deploy/docker-compose.yml               relay2 service, secret + manifest mount for relay
deploy/relay.env                        CMUX_RELAY_ISSUER, RELAY_V2_URL, MIN_MACOS, MIN_WINDOWS
deploy/nginx-proxy/relay.shellx.pro     timeouts 330 s
deploy/rollout.sh                       waits for relay2 too, prunes relay2 images
deploy/tests/{compose,rollout}.test.mjs
deploy/README.md                        "Relay v2" runbook
.github/workflows/deploy.yml            post-deploy checks for /v2/relay and /v2/relay/tickets
```

fork (`~/Documents/myProjects/shellx-wt-l4`):

```
scripts/shellx/relay2/Dockerfile                 test + build cmux-relay, debian-slim runtime, non-root
scripts/shellx/relay2/Dockerfile.dockerignore    allowlist of the cmux-tui/ context
.github/workflows/shellx-relay2.yml              build, smoke, push ghcr.io/lephus/shellx-relay2:<sha>
tests/test_shellx_relay2.py (+ tests/test-execution.toml entry, lane linux-guard)
```

---

### Task 1: Migration 0005 and the `desktop` device kind

**Files:**
- Create: `relay/migrations/0005_relay_v2.sql`, `relay/test/migrate-0005.test.ts`, `relay/test/desktop-kind.test.ts`
- Modify: `relay/src/db/migrate.ts`, `relay/src/auth/device.ts`, `relay/src/admin/stats.ts:10-12,76-96`, `relay/admin/admin.js`, `relay/src/routes/ws.ts:80-86`, `relay/test/helpers.ts`, `relay/test/db.test.ts`

**Interfaces:**
- Produces: `FOREIGN_KEYS_OFF_DIRECTIVE = "-- migrate: foreign_keys=off"` (first line of a migration file); `type DeviceKind = "agent" | "mobile" | "desktop"`; `parseDevice` accepts `desktop` only with platform `macos`/`windows`; `AdminStats.devices.desktop` / `versions.desktop`; test helpers `type Kind = "agent" | "mobile" | "desktop"`, `deviceBody("desktop")` (name `Mac-Studio`, platform `macos`), `loginDesktop(app, account, overrides?: Record<string, unknown>): Promise<Session>`.
- Schema (later tasks rely on these names exactly):

```sql
-- migrate: foreign_keys=off
-- devices: same columns as 0001+0004, CHECK now allows 'desktop' (SQLite cannot alter a CHECK: rebuild).
CREATE TABLE devices_new (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind         TEXT NOT NULL CHECK (kind IN ('agent', 'mobile', 'desktop')),
  name         TEXT NOT NULL,
  platform     TEXT NOT NULL CHECK (platform IN ('macos', 'windows', 'ios', 'android')),
  public_key   BLOB NOT NULL,
  created_at   INTEGER NOT NULL,
  last_seen_at INTEGER,
  app_version  TEXT,
  UNIQUE (user_id, public_key)
);
INSERT INTO devices_new (id, user_id, kind, name, platform, public_key, created_at, last_seen_at, app_version)
  SELECT id, user_id, kind, name, platform, public_key, created_at, last_seen_at, app_version FROM devices;
DROP TABLE devices;
ALTER TABLE devices_new RENAME TO devices;

CREATE TABLE machines (
  id               TEXT PRIMARY KEY,                       -- UUIDv4
  user_id          TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id        TEXT NOT NULL UNIQUE REFERENCES devices(id) ON DELETE CASCADE,  -- one machine per device
  name             TEXT NOT NULL,
  platform         TEXT NOT NULL CHECK (platform IN ('macos','windows')),
  os_version       TEXT NOT NULL,
  app_version      TEXT NOT NULL,
  noise_public_key BLOB NOT NULL,                          -- 32 bytes
  fingerprint      TEXT NOT NULL,                          -- first 16 hex of SHA-256(noise_public_key)
  slot             TEXT NOT NULL UNIQUE,                   -- b64url(16 random bytes), 22 chars
  created_at       INTEGER NOT NULL,
  last_seen_at     INTEGER                                 -- last heartbeat, NULL = never
);
CREATE INDEX machines_user_id ON machines (user_id);

CREATE TABLE machine_pairings (
  id                    TEXT PRIMARY KEY,                  -- UUIDv4
  user_id               TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  from_machine_id       TEXT NOT NULL REFERENCES machines(id) ON DELETE CASCADE,  -- requester
  to_machine_id         TEXT NOT NULL REFERENCES machines(id) ON DELETE CASCADE,  -- target
  requester_x25519      BLOB NOT NULL,                     -- 32 bytes, for sealing only
  requester_fingerprint TEXT NOT NULL,                     -- copied from machines.fingerprint of from_machine_id
  code                  TEXT NOT NULL,                     -- 6 digits
  status                TEXT NOT NULL CHECK (status IN ('pending','approved','denied','expired')),
  sealed_invite         TEXT,                              -- client's b64 text, verbatim; NULL after purge
  created_at            INTEGER NOT NULL,
  decided_at            INTEGER,
  CHECK (from_machine_id != to_machine_id)
);
CREATE INDEX machine_pairings_to ON machine_pairings (to_machine_id, status);
CREATE INDEX machine_pairings_from ON machine_pairings (from_machine_id);

CREATE TABLE machine_grants (
  from_machine_id TEXT NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
  to_machine_id   TEXT NOT NULL REFERENCES machines(id) ON DELETE CASCADE,
  pairing_id      TEXT NOT NULL,
  created_at      INTEGER NOT NULL,
  PRIMARY KEY (from_machine_id, to_machine_id)
);
```

- [ ] **Step 1: Write the failing tests**

`relay/test/migrate-0005.test.ts` — `it("0005 keeps every v1 row and token, and devices accepts kind desktop")`: copy `0001`–`0004` from `MIGRATIONS_DIR` into a temp dir (as `versions.test.ts` does), `migrate(db, oldDir)`, insert one user, an agent and a mobile device, a token for each (`hashToken`), a v1 `pairings` row, a `push_tokens` row, an `app_settings` row and `devices.app_version`; then `expect(migrate(db)).toEqual(["0005_relay_v2.sql"])`, every table count unchanged, `await authenticate(db, agentToken, now)` → `{kind: "agent"}`, `db.get("PRAGMA foreign_keys")` → `{foreign_keys: 1}`, `db.all("PRAGMA foreign_key_check")` → `[]`, inserting a `desktop` device works, inserting kind `robot` throws `/CHECK constraint failed/`, `DELETE FROM users` leaves 0 tokens/devices/pairings (cascades still active).

`relay/test/db.test.ts` — add `it("a foreign_keys=off migration that leaves a dangling reference is rolled back and foreign keys are on again")`: directive migration inserting a token for a missing device → `migrate` throws `/foreign_key_check/`, its name is not in `schema_migrations`, `PRAGMA foreign_keys` = 1. And `it("a migration without the directive still runs with foreign keys on")`.

`relay/test/desktop-kind.test.ts`:
- login with `deviceBody("desktop")` → 200, `devices.kind = 'desktop'`; with `platform: "ios"` → 400 `invalid_device`.
- `upgradeStatus(app, desktop.token)` → `403`.
- desktop token on `POST /v1/pairings` → 403 `agent_only`.
- agent's `GET /v1/devices` lists the desktop with `kind: "desktop"`.
- `adminStats(db(), now, [])` with one desktop: `devices.desktop` = `{total: 1, online: 0, by_platform: {macos: 1, windows: 0}}`, `versions.desktop` has one entry, `devices.agent` unchanged.

- [ ] **Step 2: Run** `cd relay && npx vitest run test/migrate-0005.test.ts test/db.test.ts test/desktop-kind.test.ts` — Expected: FAIL (no 0005, `invalid_device` for desktop, stats throw `Cannot read properties of undefined`).

- [ ] **Step 3: Implement.** `migrate()`: when the file's first line is exactly the directive, run `PRAGMA foreign_keys = OFF` before `db.transaction`, run `PRAGMA foreign_key_check` inside it after the SQL (any row → throw `Error("foreign_key_check failed for <name>")`, which rolls back), and `PRAGMA foreign_keys = ON` in a `finally` (the pragma is a no-op inside a transaction, hence outside). Write `0005_relay_v2.sql` (devices rebuild = the 12-step procedure of sqlite.org/lang_altertable.html §7). `device.ts`: add the kind and the platform rule. `stats.ts`: `PLATFORMS.desktop = ["macos","windows"]`, init `devices.desktop` / `versions.desktop`, sort it. `admin.js`: a third device card titled "Máy tính (bản mới)" using the same widget as the agent card. `ws.ts` `webSocketAuth`: after `authenticate`, `if (auth.kind === "desktop") throw Errors.forbidden();` (before the upgrade check, so the status is 403). Helpers as in Interfaces.

- [ ] **Step 4: Run** the three files, then `npm run typecheck && npm test` — Expected: all PASS (the existing 404 tests included).

- [ ] **Step 5: Commit** `git add relay && git commit -m "feat(relay): desktop device kind and v2 tables (migration 0005, foreign keys off for the rebuild only)"`

### Task 2: Config, errors, encoding and ticket minting

**Files:**
- Create: `relay/src/v2/encoding.ts`, `relay/src/v2/tickets.ts`, `relay/test/v2-encoding.test.ts`, `relay/test/v2-tickets.test.ts`
- Modify: `relay/src/config.ts`, `relay/src/http/errors.ts`, `relay/src/auth/rate-limit.ts`, `relay/src/server.ts`, `relay/test/config.test.ts`, `relay/test/helpers.ts` (`TEST_CONFIG`, `unlimited`)

**Interfaces:**
- Produces (config): `Config.relayHmacSecret: Uint8Array | null`, `Config.relayV2DisabledReason: "missing_secret" | "short_secret" | null`, `Config.relayIssuer: string` (env `CMUX_RELAY_ISSUER`, default `"shellx-relay"`, 1–256 bytes without CR/LF else `ConfigError`), `Config.relayV2Url: string` (env `RELAY_V2_URL`, default `"wss://relay.shellx.pro/v2/relay"`, must be a `ws:`/`wss:` URL else `ConfigError`). The secret is read from `env.CMUX_RELAY_HMAC_SECRET` **without** the `value()` trim; empty/unset → reason `missing_secret`; fewer than 32 UTF-8 bytes → `short_secret` (relay keeps running, v2 tickets answer 503 — same pattern as `ADMIN_PASSWORD`). `TEST_CONFIG` gets the literal test secret, issuer `shellx-relay`, `relayV2Url: "ws://127.0.0.1:1/v1/relay"`.
- Produces (errors): `desktopOnly` 403 `desktop_only`; `invalidMachine` 400 `invalid_machine`; `machineNotFound` 404 `machine_not_found`; `pairingNotFound` 404 `pairing_not_found`; `notGranted` 403 `not_granted`; `pairingNotPending` 409 `pairing_not_pending`; `pairingExpired` 410 `pairing_expired`; `plaintextInvite` 400 `plaintext_invite`; `relayV2Unavailable` 503 `relay_v2_unavailable`.
- Produces (limits): `RateLimiters.ticketMint` (60 per 60 s, keyed by device id), `RateLimiters.pairingCreate` (10 per 60 s, keyed by device id); both `allowAll` when limits are off.
- Produces (encoding): `decodeB64(value: unknown, minBytes: number, maxBytes: number): Uint8Array | null` — accepts the standard or URL alphabet, optional `=` padding, rejects anything else (`/^[A-Za-z0-9+/_-]*={0,2}$/`, no mixing of `+/` with `-_`); `fingerprint(noiseKey: Uint8Array): string`; `newSlot(): string` (16 bytes from `randomBytes`, b64url no pad); `unixSeconds(ms: number): number` (floor).
- Produces (tickets): `TICKET_LIFETIME_SECONDS = 120`; `interface RelayTicketClaims {version: 2; issuer: string; permission: "register" | "connect"; role: "daemon" | "client"; slot: string; circuit: null; lane: null; generation: null; issued_at_unix: number; expires_at_unix: number}`; `ticketClaims(permission, slot: string, issuer: string, nowMs: number): RelayTicketClaims` (role from permission); `signingPayload(c: RelayTicketClaims): string`; `mintTicket(secret: Uint8Array, c: RelayTicketClaims): string`. The JSON key order is the field order above (serde order of `RelayTicketClaims`, `cmux-remote-protocol/src/relay.rs:34-47`).

- [ ] **Step 1: Write the failing tests**

`v2-tickets.test.ts` (golden values computed with `openssl dgst -sha256 -hmac` and matched against a `cmux-relay ticket` CLI ticket on 2026-10-19):

```ts
const SECRET = new TextEncoder().encode("0123456789abcdef0123456789abcdef");
const SLOT = "AAAAAAAAAAAAAAAAAAAAAA";
const register = ticketClaims("register", SLOT, "shellx-relay", 1_760_000_000_999);
expect(register).toEqual({ version: 2, issuer: "shellx-relay", permission: "register", role: "daemon", slot: SLOT,
  circuit: null, lane: null, generation: null, issued_at_unix: 1760000000, expires_at_unix: 1760000120 });
expect(signingPayload(register)).toBe("cmux-relay-ticket-v2\n2\nshellx-relay\nregister\ndaemon\nAAAAAAAAAAAAAAAAAAAAAA\n\n\n\n1760000000\n1760000120");
expect(mintTicket(SECRET, register)).toBe("v2.eyJ2ZXJzaW9uIjoyLCJpc3N1ZXIiOiJzaGVsbHgtcmVsYXkiLCJwZXJtaXNzaW9uIjoicmVnaXN0ZXIiLCJyb2xlIjoiZGFlbW9uIiwic2xvdCI6IkFBQUFBQUFBQUFBQUFBQUFBQUFBQUEiLCJjaXJjdWl0IjpudWxsLCJsYW5lIjpudWxsLCJnZW5lcmF0aW9uIjpudWxsLCJpc3N1ZWRfYXRfdW5peCI6MTc2MDAwMDAwMCwiZXhwaXJlc19hdF91bml4IjoxNzYwMDAwMTIwfQ.VInR0V5-tlMiyx-l9LHTof_G3y2N8ltcwULy2OqiiVY");
const connect = ticketClaims("connect", SLOT, "shellx-relay", 1_760_000_000_000);
expect(connect.role).toBe("client");
expect(mintTicket(SECRET, connect).split(".")[2]).toBe("bC7VtVqsFdcI6ldQ9BhFFH5OL_e6hFJTzVCQGbZLXnY");
expect(mintTicket(SECRET, register).length).toBeLessThanOrEqual(4096);
```

`v2-encoding.test.ts`: `fingerprint(new Uint8Array(32))` → `"66687aadf862bd77"`; `newSlot()` matches `/^[A-Za-z0-9_-]{22}$/` and two calls differ; `decodeB64` accepts the same 32 bytes as standard padded, standard unpadded and URL alphabet; rejects `"a b"`, `"ab$c"`, a mix of `+` and `_`, 31 or 33 bytes for `(…, 32, 32)`, non-strings.

`config.test.ts`: secret `"  0123456789abcdef0123456789abcdef  "` is kept with its spaces (36 bytes); 31 bytes → `relayHmacSecret: null, relayV2DisabledReason: "short_secret"`; unset → `"missing_secret"`; `CMUX_RELAY_ISSUER` default and `"a\nb"` → `ConfigError`; `RELAY_V2_URL=https://x` → `ConfigError`.

- [ ] **Step 2: Run** `npx vitest run test/v2-tickets.test.ts test/v2-encoding.test.ts test/config.test.ts` — Expected: FAIL (modules missing).
- [ ] **Step 3: Implement** with `node:crypto` (`createHmac("sha256", secret).update(payload, "utf8").digest("base64url")`, `createHash`, `randomBytes`), `Buffer.from(json).toString("base64url")`. `server.ts`: `logMeta("relay_v2_enabled")` or `logMeta("relay_v2_disabled", {reason})` at start (never the secret or its length).
- [ ] **Step 4: Run** the same files, then `npm run typecheck && npm test` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -am "feat(relay): v2 config, errors, strict base64, fingerprint and cmux-relay compatible tickets"` (add the new files first).

### Task 3: Machines API (`/v2/machines`)

**Files:**
- Create: `relay/src/v2/guard.ts`, `relay/src/v2/machines.ts`, `relay/test/v2-machines.test.ts`
- Modify: `relay/src/app.ts` (mount), `relay/src/routes/auth.ts:159-165` (desktop logout), `relay/test/helpers.ts` (`registerMachine`)

**Interfaces:**
- Consumes: Task 1 schema, Task 2 errors/encoding.
- Produces: `requireDesktop: MiddlewareHandler<AppEnv>` (403 `desktop_only` unless `auth.kind === "desktop"`); `interface MachineRow {id, user_id, device_id, name, platform, os_version, app_version, noise_public_key: Buffer, fingerprint, slot, created_at, last_seen_at: number | null}`; `ownMachine(db, deviceId): MachineRow | undefined`; `accountMachine(db, userId, machineId: unknown): MachineRow | undefined` (`parseUuid` first; undefined for other accounts); `ONLINE_WINDOW_MS = 90_000`; `machineRoutes` mounted at `/v2/machines`; helper `registerMachine(app, token, overrides?) → {machine_id, slot, noiseKey: string}`.
- Rules (decisions, K1 leaves them open): one machine per device: a second `POST` by the same device returns **200** with the same `{machine_id, slot}` and refreshes `name`, `os_version`, `app_version`; if `noise_public_key_b64` changed it also updates key + fingerprint, deletes every `machine_grants` row from or to it and marks its pending pairings `expired` (a new daemon identity must be approved again). Validation → 400 `invalid_machine`: `name` 1–100 chars after trim, `platform` `macos`|`windows`, `os_version` `/^\d{1,4}(\.\d{1,6}){0,3}$/`, `app_version` `/^\d{1,6}\.\d{1,6}\.\d{1,6}$/`, key 32 bytes. `GET` lists machines of the caller's account whose device holds a live token (same rule as `GET /v1/devices`), the caller's own included, ordered by `created_at, id`, never `slot` or keys. Heartbeat: owner only (same account non-owner → 403 `forbidden`). `DELETE`: any desktop of the same account (removes a dead machine from the sidebar); grants and pairings go by cascade. Other account or unknown id → 404 `machine_not_found` everywhere. Logout of a desktop deletes its machine in the same transaction as its token.

- [ ] **Step 1: Write the failing tests** (`makeApp({ now: () => clock })` for time):
  - `POST` → 201, `machine_id` UUID, `slot` `/^[A-Za-z0-9_-]{22}$/`; again → 200 same ids, new name visible in `GET`.
  - again with a new key → 200, same ids, `fingerprint` changed, a grant row inserted beforehand is gone, a pending pairing to it now reads `expired`.
  - agent token → 403 `desktop_only`; no token → 401; each invalid field of the table above → 400 `invalid_machine`.
  - `GET` from account A never shows account B's machines; `fingerprint` = `createHash("sha256").update(key).digest("hex").slice(0, 16)`; before any heartbeat `online: false, last_seen_unix: null`.
  - heartbeat at `clock = 1_760_000_000_500` → 204; `GET` at `+90_000` → `online: true, last_seen_unix: 1760000000`; at `+90_001` → `online: false`.
  - heartbeat on a same-account machine → 403 `forbidden`; on account B's → 404; on `"not-a-uuid"` → 404.
  - `DELETE` own → 204 and its grants gone; same-account other → 204; account B's → 404.
  - desktop `POST /v1/auth/logout` → its machine is gone; after an agent's `POST /v1/auth/password` the other desktop's machine disappears from `GET`.
- [ ] **Step 2: Run** `npx vitest run test/v2-machines.test.ts` — Expected: FAIL (404 for `/v2/machines`).
- [ ] **Step 3: Implement** `guard.ts` and `machines.ts` (Hono sub-app like `routes/devices.ts`; `crypto.randomUUID()` ids; `logMeta("machine_registered" | "machine_deleted", {device_id, machine_id})`); mount in `app.ts` next to the v1 routes; logout change in `auth.ts`.
- [ ] **Step 4: Run** the file, then `npm run typecheck && npm test` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "feat(relay): /v2/machines — one machine per desktop, heartbeat online window 90 s, fingerprint"`

### Task 4: Pairings API (`/v2/pairings`) with on-site approval

**Files:**
- Create: `relay/src/v2/pairings.ts`, `relay/test/v2-pairings.test.ts`
- Modify: `relay/src/app.ts` (mount; `AppDeps.pairingCode?: () => string`, default `randomInt(0, 1_000_000)` zero-padded to 6), `relay/test/helpers.ts` (`requestPairing`, `approvePairing`)

**Interfaces:**
- Consumes: `requireDesktop`, `ownMachine`, `accountMachine` (Task 3), `decodeB64` (Task 2), limiter `pairingCreate`.
- Produces: `PAIRING_TTL_MS = 300_000`; `PAIRING_VISIBLE_MS = 600_000`; `MAX_PENDING_PER_TARGET = 10`; `SEALED_INVITE_MAX_BYTES = 8192`; `hasGrant(db, fromMachineId: string, toMachineId: string): boolean`; `purgePairings(db, nowMs): void` (sets `sealed_invite = NULL` where `decided_at < now - PAIRING_VISIBLE_MS`, deletes rows older than 24 h); `machinePairingRoutes` mounted at `/v2/pairings`.
- Rules: `POST` — `from_machine_id` must be the caller's own machine (same account other → 403 `forbidden`, else 404 `machine_not_found`); `to_machine_id` in the account (else 404), `!= from` (400 `bad_request`); `requester_x25519_b64` 32 bytes (400); fingerprint copied from the requester's `machines` row and code from `pairingCode()` — body fields `code`, `requester_fingerprint`, `status` are ignored; a code already used by a live pending pairing of the same target is redrawn (max 10 tries, then 500); an existing pending request with the same (from, to) becomes `expired`; more than `MAX_PENDING_PER_TARGET` live pending → 429 `rate_limited`. Status read: stored `pending` older than `PAIRING_TTL_MS` is reported (and written lazily) as `expired`. `GET ?role=target|requester` (else 400) — rows where the caller's machine is `to`/`from`, `created_at >= now - PAIRING_VISIBLE_MS` or still pending, newest first; `sealed_invite_b64` present only for `role=requester` and `approved` (and not purged); `requester_x25519_b64` (stored bytes, standard base64) present on every `role=target` item, since the target seals the invite to it (L0 ruling D2, public key, not a secret); a caller with no machine gets `{pairings: []}`. `approve` — target machine only (requester or third machine of the account → 403 `forbidden`; other account or unknown → 404 `pairing_not_found`); `sealed_invite_b64` decodes to 1–`SEALED_INVITE_MAX_BYTES` bytes (400 `bad_request`) and must not start with ASCII `cmux://` (400 `plaintext_invite`: the PSK must never reach the server in clear, ledger §8.5); one transaction: `UPDATE … SET status='approved', sealed_invite=?, decided_at=? WHERE id=? AND status='pending' AND created_at >= ?` — 0 rows → 410 `pairing_expired` if the TTL passed, else 409 `pairing_not_pending`; then upsert `machine_grants (from, to, pairing_id)`. `deny` — target (deny) or requester (cancel); pending → `denied`; already `denied` → 204; `approved`/`expired` → 409.

- [ ] **Step 1: Write the failing tests**
  - happy path: A requests B → 201 `{pairing_id, code: /^\d{6}$/}`; B `GET ?role=target` shows `{status: "pending", requester_fingerprint: <A's fingerprint>, code: <same>}` and no `sealed_invite_b64` key; B approves `{sealed_invite_b64: S}` → 204; A `GET ?role=requester` returns exactly `S` (byte-identical string, standard or URL alphabet); `hasGrant(db(), A, B)` true, `hasGrant(db(), B, A)` false.
  - `describe("spoofing")`: (a) A sends `from_machine_id` = C's (same account) → 403, no row; (b) body `code: "123456"`, `requester_fingerprint: "0".repeat(16)` with `pairingCode: () => "654321"` → response and stored code `654321`, stored fingerprint = A's; (c) A approves its own request → 403; C approves → 403; account-2 desktop approves → 404; (d) approve at `created + 300_001` → 410, `GET` shows `expired`, no grant; (e) second approve → 409; deny after approve → 409; (f) `pairingCode` yields `"111111","111111","222222"`: two pending to B get `111111` and `222222`; (g) 11th live pending to B → 429; (h) `Promise.all` of two approves → statuses `[204, 409]` in some order and one grant row.
  - validation: `to` in account 2 → 404; `to == from` → 400; 31-byte x25519 → 400; invite of 8193 bytes → 400; invite whose bytes are `cmux://enroll/abc` → 400 `plaintext_invite`; `?role=both` → 400.
  - supersede: A requests B twice → first reads `expired`.
  - purge: approved at `t`, `GET ?role=requester` at `t + 600_001` → no `sealed_invite_b64`, DB column `NULL`.
  - deny: B denies → 204, `denied`, no grant; A cancels its own → 204; deny twice → 204.
- [ ] **Step 2: Run** `npx vitest run test/v2-pairings.test.ts` — Expected: FAIL.
- [ ] **Step 3: Implement** `pairings.ts` (`logMeta("pairing_created" | "pairing_approved" | "pairing_denied", {device_id, pairing_id})` — never code, keys, invite).
- [ ] **Step 4: Run** the file, then `npm run typecheck && npm test` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "feat(relay): /v2/pairings — 6-digit code, 5-minute expiry, target-only approval, sealed invite stored as ciphertext"`

### Task 5: Relay tickets API (`/v2/relay/tickets`) and API docs

**Files:**
- Create: `relay/src/v2/relay-tickets.ts`, `relay/test/v2-relay-tickets.test.ts`
- Modify: `relay/src/app.ts` (mount at `/v2/relay/tickets`), `relay/README.md` (API v2 section: table of K1 routes, error codes of Task 2, rules of Tasks 3–5)

**Interfaces:**
- Consumes: `ticketClaims`, `mintTicket`, `unixSeconds` (Task 2); `ownMachine`, `accountMachine` (Task 3); `hasGrant` (Task 4); limiter `ticketMint`.
- Produces: `POST /v2/relay/tickets` → `200 {ticket, expires_at_unix, relay_url}`.
- Rules, in this order: `requireAuth` → `requireDesktop` → `jsonBodyLimit` → `config.relayHmacSecret === null` → 503 `relay_v2_unavailable` → `ticketMint.limit(deviceId)` → body: `permission` ∈ `register|connect` (else 400), `machine_id` must be the caller's own machine (same account other → 403 `forbidden`, else 404 `machine_not_found`); `register` → slot = own slot; `connect` → `target_machine_id` required, in the account (404); `target_machine_id == machine_id` → allowed without a grant, slot = own slot (L0 ruling D3: the host mints it for `remote enroll create` and it travels only inside the sealed invite; the daemon's enrollment PSK and on-site approval still gate access; `register` is never allowed for another machine); otherwise `hasGrant(own, target)` (else 403 `not_granted`), slot = target's slot. Slot always from the database, never from the body. `relay_url = config.relayV2Url`. `logMeta("relay_ticket", {device_id, permission})`.

- [ ] **Step 1: Write the failing tests**
  - register own → 200; `expires_at_unix === Math.floor(clock / 1000) + 120`; `relay_url === TEST_CONFIG.relayV2Url`; decoded claims `{permission: "register", role: "daemon", slot: <own slot>, issuer: "shellx-relay"}`; `ticket === mintTicket(SECRET, claims)`.
  - register for C (same account) → 403; for account 2 → 404; `permission: "join"` → 400.
  - connect A→B without grant → 403 `not_granted`; after Task 4 approval → 200 with `slot` = B's and `role: "client"`; after B rotates its key (Task 3 rule) → 403; after `DELETE` of B → 404; missing target → 400; target = self → 200 with own slot and `role: "client"` (D3).
  - `makeApp({config: {...TEST_CONFIG, relayHmacSecret: null, relayV2DisabledReason: "missing_secret"}})` → 503 `relay_v2_unavailable`.
  - limiter: `limiters: {...unlimited, ticketMint: new CountingLimiter(1)}` → second call 429.
  - agent token → 403 `desktop_only`.
  - no leak: spy on `console.log` during a mint; no line contains the ticket, the slot or any `v2.` prefix.
- [ ] **Step 2: Run** `npx vitest run test/v2-relay-tickets.test.ts` — Expected: FAIL.
- [ ] **Step 3: Implement** the route; write the README section.
- [ ] **Step 4: Run** the file, then `npm run typecheck && npm test` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "feat(relay): /v2/relay/tickets — register for own slot, connect only with a grant, 120 s lifetime"`

### Task 6: Interop with the real `cmux-relay` and the post-deploy smoke script

**Files:**
- Create: `relay/test/relay2-interop.test.ts`, `relay/scripts/relay2-smoke.ts`
- Modify: `relay/package.json` (script `"relay2:smoke": "tsx scripts/relay2-smoke.ts"`)

**Interfaces:**
- Consumes: the whole v2 API (Tasks 3–5); `createTtyPrompter` from `relay/src/scripts/prompter.ts` (`ask(question, {hidden: true})`).
- Wire facts (verified 2026-10-19 against `cmux-tui/target/debug/cmux-relay` on 127.0.0.1): daemon sends text `{"type":"register","protocol":5,"slot":S,"ticket":T}` → `{"type":"registered","lease_seconds":30}`; client sends `{"type":"connect","protocol":5,"slot":S,"ticket":T,"lane":"control","generation":1}` → client gets `{"type":"allocated",…}`, daemon gets `{"type":"incoming",…}`; a bad signature or a register ticket used to connect → `{"type":"error","code":"invalid-ticket",…}`; any `Origin` header → HTTP 403; plain `GET /v1/relay` → 400; `GET /healthz` → `{"status":"ok",…}`.

- [ ] **Step 1: Write the interop test** — `describe.skipIf(!process.env.CMUX_RELAY_BIN)` (so the image build and `npm test` skip it): spawn `$CMUX_RELAY_BIN serve` with `env: {CMUX_RELAY_HMAC_SECRET: <test secret>, CMUX_RELAY_ISSUER: "shellx-relay", CMUX_RELAY_BIND: "127.0.0.1:<free port>"}` (no inherited env), poll `/healthz`; `makeApp({config: {...TEST_CONFIG, relayV2Url: "ws://127.0.0.1:<port>/v1/relay"}})`; desktops A (target) and B (requester), machines, pairing approved. Cases: `register ticket from the API is accepted` (A → `registered`); `connect ticket from the API reaches the registered daemon` (B → `allocated`, A → `incoming`); `a tampered ticket is refused` (last signature char flipped → `invalid-ticket`); `a register ticket cannot connect`; `a ticket signed with another secret is refused` (second app with `"fedcba9876543210fedcba9876543210"`); `an expired ticket is refused` (app clock = real time − 200 s → `type: "error"`). Kill the relay in `onCleanup`.
- [ ] **Step 2: Run** in the fork: `cd ~/Documents/myProjects/shellx/cmux-tui && cargo build -p cmux-relay --locked`; then `cd relay && CMUX_RELAY_BIN=~/Documents/myProjects/shellx/cmux-tui/target/debug/cmux-relay npx vitest run test/relay2-interop.test.ts` — Expected: PASS (all 6). Without the env var the file reports skipped.
- [ ] **Step 3: Write the smoke script** `relay2-smoke.ts`: asks API base (default `https://relay.shellx.pro`), e-mail, password (hidden); logs in with `kind: "desktop"`, name `relay2-smoke`, a random key; `POST /v2/machines`; mints `register`; opens `new WebSocket(relay_url)` (no `Origin`), sends `register`, expects `registered` within 5 s; then `DELETE /v2/machines/:id` and `POST /v1/auth/logout` in `finally`. Prints only `relay2 smoke: OK (registered, lease <n> s)` or `relay2 smoke: FAIL at <step> (<http status> <error code>)`; never prints token, ticket, slot or password. Run it once against a local `npm run dev` relay with `RELAY_V2_URL=ws://127.0.0.1:<port>/v1/relay` and the local `cmux-relay` → OK.
- [ ] **Step 4: Run** `npm run typecheck && npm test` — Expected: PASS (interop skipped).
- [ ] **Step 5: Commit** `git commit -m "test(relay): API-minted tickets accepted by the real cmux-relay; relay2 smoke script"`

### Task 7 (fork, parallel from T+0:45): relay2 container image built by fork CI

**Files (fork `shellx/l4-relay2`):**
- Create: `scripts/shellx/relay2/Dockerfile`, `scripts/shellx/relay2/Dockerfile.dockerignore`, `.github/workflows/shellx-relay2.yml`, `tests/test_shellx_relay2.py`
- Modify: `tests/test-execution.toml` (entry `path = "tests/test_shellx_relay2.py"`, `lane = "linux-guard"`)

**Interfaces:**
- Produces: image `ghcr.io/lephus/shellx-relay2:<40-hex fork commit sha>`; entrypoint `/usr/local/bin/cmux-relay`, cmd `serve`, listens where `CMUX_RELAY_BIND` says (compose sets `0.0.0.0:8787`), runs as uid 10001, labels `org.opencontainers.image.source=https://github.com/lephus/shellx` and `org.opencontainers.image.revision=<sha>` (the corresponding source for the published binary).
- Decisions: build context = `cmux-tui/`; `Dockerfile.dockerignore` is an allowlist: `*` then `!Cargo.toml`, `!Cargo.lock`, `!rust-toolchain.toml`, `!crates`, `!bindings`, `!vendor`, `!build-support` (keeps every workspace member manifest; `relays/` — BUSL `cloudflare-do` — never enters the context). Stages: `rust:1.95.0-bookworm` runs `cargo test -p cmux-relay --locked` then `cargo build -p cmux-relay --locked --release` (an image only exists if the relay tests pass, like the shellx relay image); runtime `debian:bookworm-slim`, binary only, `USER 10001:10001`, `EXPOSE 8787`. No healthcheck tool is installed; compose probes `/healthz` with bash `/dev/tcp` (Task 8). Workflow: `on: push: branches: [shellx/l4-relay2, shellx/sprint, main]` with `paths: [cmux-tui/crates/cmux-relay/**, cmux-tui/crates/cmux-remote-protocol/**, cmux-tui/Cargo.lock, scripts/shellx/relay2/**, .github/workflows/shellx-relay2.yml]`, plus `workflow_dispatch`; `permissions: {contents: read, packages: write}`; `actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2` (the pin the fork already uses), no other actions; `docker login ghcr.io` with `GITHUB_TOKEN` via stdin; build; **smoke** = run the image with `CMUX_RELAY_HMAC_SECRET` from `openssl rand -base64 48` generated inside the step (never echoed, never stored), wait for `/healthz` `"status":"ok"` through `docker exec … bash -c` (same probe as compose), plus `docker run … cmux-relay serve` **without** a secret must exit non-zero (refuses an open non-loopback relay, `config.rs` validate); then `docker push`. Concurrency group per ref.

- [ ] **Step 1: Write the failing static test** `tests/test_shellx_relay2.py` (`unittest`): Dockerfile contains `cargo test -p cmux-relay --locked` before `cargo build -p cmux-relay --locked --release`, has `USER 10001:10001`, `ENTRYPOINT ["/usr/local/bin/cmux-relay"]`, no `relays`; dockerignore first non-comment line is `*` and its `!` lines are exactly the seven above; workflow has `packages: write`, the pinned checkout sha, image `ghcr.io/lephus/shellx-relay2:${{ github.sha }}`, no `secrets.` other than `secrets.GITHUB_TOKEN`, no `uses:` other than the checkout, and no `manaflow` string.
- [ ] **Step 2: Run** `python3 tests/test_shellx_relay2.py` — Expected: FAIL (files missing).
- [ ] **Step 3: Implement** the three files.
- [ ] **Step 4: Run** `python3 tests/test_shellx_relay2.py` and `python3 scripts/verify-local.py` → PASS; `cd cmux-tui && cargo test -p cmux-relay --locked` → PASS; if Docker runs on the Mac, `docker build -f scripts/shellx/relay2/Dockerfile cmux-tui` → success (else CI only). Commit `ci(shellx): relay2 image (cmux-relay) built, smoke-tested and pushed by fork CI`; push `git push git@phule9225.github.com:lephus/shellx.git shellx/l4-relay2`; watch **Actions → shellx-relay2** green; record the commit sha `R` for Task 8.
- [ ] **Step 5:** report to L0 "ready <sha>" for `shellx/l4-relay2` (merge into `shellx/sprint` is L0's).

### Task 8: Compose `relay2`, nginx-proxy path route, rollout and runbook

**Files:**
- Modify: `deploy/docker-compose.yml`, `deploy/relay.env`, `deploy/nginx-proxy/relay.shellx.pro`, `deploy/rollout.sh` (health loop, prune), `deploy/tests/compose.test.mjs`, `deploy/tests/rollout.test.mjs`, `deploy/README.md` (section "Relay v2"), `.github/workflows/deploy.yml` (post-deploy checks)
- Create (side branch `feat/relay-v2-subdomain`, one commit on top of this task, not merged): the K2 fallback.

**Interfaces:**
- Consumes: image sha `R` (Task 7); `CMUX_RELAY_ISSUER`, `RELAY_V2_URL` (Task 2).
- Produces (compose `relay2` service): `image: ghcr.io/lephus/shellx-relay2:<R>`; `restart: unless-stopped`; `mem_limit: 256m`, `memswap_limit: 256m`; `read_only: true`; `environment`: `VIRTUAL_HOST: relay.shellx.pro`, `VIRTUAL_PATH: "= /v2/relay"`, `VIRTUAL_DEST: /v1/relay`, `VIRTUAL_PORT: "8787"`, **no** `LETSENCRYPT_HOST` (the `relay` service already owns that certificate), `CMUX_RELAY_BIND: 0.0.0.0:8787`, `CMUX_RELAY_HMAC_SECRET: ${CMUX_RELAY_HMAC_SECRET:-}`, `CMUX_RELAY_ISSUER: shellx-relay`; `healthcheck: ["CMD", "bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/8787 && printf 'GET /healthz HTTP/1.1\\r\\nHost: l\\r\\nConnection: close\\r\\n\\r\\n' >&3 && grep -q '\"status\":\"ok\"' <&3"]` (interval 10 s, retries 3, start 10 s); `logging: *logging`; `networks: [proxy]`; no ports, no volumes. `relay` service gains `CMUX_RELAY_HMAC_SECRET: ${CMUX_RELAY_HMAC_SECRET:-}` (empty → v2 tickets 503, v1 untouched). `relay.env` gains `CMUX_RELAY_ISSUER=shellx-relay` and `RELAY_V2_URL=wss://relay.shellx.pro/v2/relay`.
- Why exact match (`= /v2/relay`): a prefix `location /v2/relay` would also capture `POST /v2/relay/tickets` (K1, served by the Node relay). `VIRTUAL_DEST` rewrites to the crate's only WebSocket path `/v1/relay` (`cmux-relay/src/relay.rs:243-245`); the client keeps a non-root path verbatim (`cmux-remote/src/provider/relay.rs:1670-1672`). Unverified on the VPS's nginx-proxy version → open question 2, checked at G2.
- `nginx-proxy/relay.shellx.pro`: `proxy_read_timeout 330s; proxy_send_timeout 330s;` (above `cmux-relay`'s 300 s circuit idle timeout, `config.rs` `DEFAULT_IDLE_TIMEOUT_SECONDS`; v1 clients ping every 30 s, unaffected). The file applies to the whole server block, so both locations.
- `rollout.sh`: health loop over `relay relay2 web`; success line `relay, relay2 and web are healthy on <tag>`; hint `docker compose logs --tail 50 relay relay2 web`; a second prune with `--filter label=org.opencontainers.image.source=https://github.com/lephus/shellx --filter until=168h`.
- `deploy.yml` check step: also `curl -s -o /dev/null -w '%{http_code}' https://relay.shellx.pro/v2/relay` must be `400` or `426` (cmux-relay refuses a plain GET; the Node relay would answer 404 JSON), and `curl -s -X POST https://relay.shellx.pro/v2/relay/tickets` must be `401` with body containing `"code":"unauthorized"` (the Node relay still owns that path). Same retry loop as the existing checks.
- Fallback commit (branch `feat/relay-v2-subdomain`): `relay2` with `VIRTUAL_HOST`/`LETSENCRYPT_HOST: relay2.shellx.pro`, no `VIRTUAL_PATH`/`VIRTUAL_DEST`; `RELAY_V2_URL=wss://relay2.shellx.pro/v1/relay`; new `deploy/nginx-proxy/relay2.shellx.pro` (access log off, timeouts 330 s); deploy.yml checks `https://relay2.shellx.pro/v1/relay` → 400/426; compose test variant.

- [ ] **Step 1: Write the failing tests** — `compose.test.mjs`: `relay2` exists with every value listed above (image regex `/^ghcr\.io\/lephus\/shellx-relay2:[0-9a-f]{40}$/`, no `LETSENCRYPT_HOST`, no `ports`/`volumes`, `read_only`, mem/memswap equal); `relay` and `relay2` take `CMUX_RELAY_HMAC_SECRET` from `.env` only (`${CMUX_RELAY_HMAC_SECRET:-}`); `relay2`'s `CMUX_RELAY_ISSUER` equals `relay.env`'s; `relay.env` has `RELAY_V2_URL=wss://relay.shellx.pro/v2/relay` and no line matching `/SECRET/`; the vhost file has both 330 s timeouts and still `access_log off`. `rollout.test.mjs`: fake `compose ps -q relay2` → `relay2-container-id`, unhealthy when a marker file `relay2-broken` exists → rollback path taken and `docker compose logs --tail 50 relay relay2 web` hinted; healthy run asserts `compose ps -q relay2` was called and the new success line; prune called with both source labels.
- [ ] **Step 2: Run** `node --test deploy/tests/*.test.mjs` — Expected: FAIL.
- [ ] **Step 3: Implement** compose, env, vhost, rollout, deploy.yml checks, README "Relay v2" (what relay2 is, secret by hand, making the package public, copying the vhost file, verifying with `nginx -T`, the fallback, rollback); then the fallback commit on `feat/relay-v2-subdomain` (`git switch -c feat/relay-v2-subdomain`, commit, `git switch feat/relay-v2`).
- [ ] **Step 4: Run** `node --test deploy/tests/*.test.mjs` → PASS; `IMAGE_TAG=x PROXY_NETWORK=x docker compose -f deploy/docker-compose.yml config -q` → exit 0 if Docker is available (CI preflight runs it anyway); `cd relay && npm test` → PASS.
- [ ] **Step 5: Commit** `git commit -m "feat(deploy): relay2 (cmux-relay) behind nginx-proxy at wss://relay.shellx.pro/v2/relay; rollout waits for it"`

### Task 9: C15 — `/v1/version` per platform (K6 shape), Flutter clients unchanged

Implements W3 Task A1 (`docs/superpowers/plans/2026-10-19-native-desktop-w3-release-share.md`) **without** the admin write path (W3 A1b keeps it): the four new keys are read from `app_settings` but no admin route can set them yet, so nobody can force an update to a version that is not downloadable.

**Files:**
- Create: `relay/src/native-latest.ts`, `relay/test/native-latest.test.ts`
- Modify: `relay/src/versions.ts`, `relay/src/settings.ts`, `relay/src/config.ts`, `relay/src/app.ts` (the `/v1/version` handler), `deploy/relay.env`, `deploy/docker-compose.yml`, `relay/test/helpers.ts` (`TEST_CONFIG.minMacos/minWindows/nativeManifestDir` = a per-test temp dir), `relay/test/versions.test.ts`, `relay/test/app.test.ts`, `relay/test/admin.test.ts`, `deploy/tests/compose.test.mjs`

**Interfaces (names fixed by W3 A1; reuse exactly):**
- `PLATFORM_HEADER = "X-ShellX-Platform"`, `OS_VERSION_HEADER = "X-ShellX-OS-Version"`; `audienceOf(platform: string | undefined, osVersion: string | undefined): "native-macos" | "native-windows" | "flutter-macos-14" | "flutter-windows" | "legacy"` (exact, case-sensitive platform match; OS major = integer before the first `.`; unparsable → `legacy`).
- `readNativeLatest(dir: string, platform: "macos" | "windows", now: number): {version, url, sha256, minOs} | null` — file `latest-<platform>.json`, ≤ 4 KB, `version` semver, `url` starts with `https://download.shellx.pro/desktop/<version>/`; invalid → `null` + `logMeta("native_latest_invalid", {platform})`; 60 s cache per platform; injectable reader for tests.
- `PLATFORM_MIN_KEYS = ["min_macos", "min_windows", "min_flutter_macos14", "min_flutter_windows"] as const` (not added to `MIN_VERSION_KEYS`, so the admin page is untouched); `versionAnswer(db, config, audience, latest: {macos: NativeLatest | null, windows: NativeLatest | null}): {min_agent, min_mobile, latest_agent: {version, mac_url, win_url}}` per the K6 table (W3 plan): native-macos `min_macos` → `MIN_MACOS` (default `2.0.0`); native-windows `min_windows` → `MIN_WINDOWS` (default `2.0.0`); flutter-macos-14 `min_flutter_macos14` → `min_agent`; flutter-windows `min_flutter_windows` → `min_agent`; legacy = today's answer. `latest_agent` from the manifest where K6 says so, legacy env otherwise.
- `Config.minMacos`, `Config.minWindows`, `Config.nativeManifestDir` (env `NATIVE_MANIFEST_DIR`, default `/srv/downloads/desktop`).

- [ ] **Step 1: Write the failing tests** — the full W3 A1 Step 1 table for `audienceOf` (9 rows incl. `("FLUTTER-MACOS","14.0") → legacy`) and for `readNativeLatest`; plus `describe("legacy audiences keep today's body")`: for no headers, `flutter-macos`/`13.6`, `flutter-macos`/`abc`, `flutter-windows`/`10.0.22631`, the body `toEqual` the exact object of `app.test.ts` "GET /v1/version returns the configured versions" (same key order `["min_agent","min_mobile","latest_agent"]`); `macos`/`14.5` → `min_agent "2.0.0"`; with `app_settings` row `min_flutter_macos14 = 2.0.0` and a macos manifest 2.0.0, `flutter-macos`/`15.0` → `{min_agent: "2.0.0", latest_agent: {version: "2.0.0", mac_url: "https://download.shellx.pro/desktop/2.0.0/ShellX-2.0.0.dmg"}}`; same without manifest → legacy `latest_agent`; `PUT /api/settings {"min_macos":"2.0.0"}` on the admin host is still refused (key unknown to admin). `compose.test.mjs`: relay volume `./downloads/desktop:/srv/downloads/desktop:ro`.
- [ ] **Step 2: Run** `npx vitest run test/versions.test.ts test/native-latest.test.ts test/app.test.ts test/admin.test.ts` and `node --test deploy/tests/compose.test.mjs` — Expected: FAIL.
- [ ] **Step 3: Implement**; add `MIN_MACOS=2.0.0`, `MIN_WINDOWS=2.0.0` to `deploy/relay.env` and the read-only volume to the `relay` service (`rollout.sh` already creates `downloads/desktop`).
- [ ] **Step 4: Run** `npm run typecheck && npm test` and `node --test deploy/tests/*.test.mjs` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "feat(relay): /v1/version per platform from X-ShellX-Platform (C15, K6 shape); Flutter 1.0.0 answers unchanged"`. Tell L0 to note in the ledger that W3 A1 may take its skip condition (A1b still to do).

### Task 10: Security review of tickets and pairings (blocks G2)

**Files:** none new; fixes land in the files of Tasks 1–9.

- [ ] **Step 1:** Dispatch one reviewer with superpowers:requesting-code-review on `git diff main...feat/relay-v2 -- relay deploy .github` with this checklist (each item answered with file:line evidence):
  1. Authorization matrix for every `/v2` route: no token 401; agent/mobile 403 `desktop_only`; other account 404 (no existence leak); same-account non-owner 403 where Tasks 3–5 say so.
  2. Tickets: slot only from the database; role tied to permission; issuer from config; lifetime 120 s; secret never logged, returned, or trimmed; 503 when disabled; rate limit present.
  3. Pairings: code and fingerprint server-made; approve target-only with a conditional UPDATE (race-safe); expiry enforced at approve time, not only on read; supersede; per-target cap; sealed invite stored verbatim, never parsed, capped, plaintext `cmux://` refused, purged after 10 min, returned only to the requester.
  4. Grants removed on key rotation, machine delete, desktop logout, account deletion (cascade).
  5. Migration 0005: foreign keys restored on every path; `foreign_key_check` enforced.
  6. Logs: grep every `logMeta(` under `relay/src/v2` and the changed files — only ids, permission, reason.
  7. Deploy: secret only via `.env` interpolation; exact-match path keeps `/v2/relay/tickets` on the Node relay; no `Origin` injected (crate refuses it); `relay2` read-only, non-root, no ports.
  8. Ledger §8.5: nothing in the API lets the server obtain the PSK; the approval data the target sees (code + fingerprint) cannot be set by the requester.
- [ ] **Step 2:** Fix every Critical/Important finding test-first (new failing test, fix, `npm test`), commit each `fix(relay): …`. Minor findings go to the lane report.
- [ ] **Step 3:** Re-run `npm run typecheck && npm test`, `node --test deploy/tests/*.test.mjs`, and the Task 6 interop suite → all PASS.

### Task 11: Gate G2 — deploy relay2 + API v2 (user, ~T+3:30) and verification

Pre-check (agent): `git diff --stat main...feat/relay-v2` lists only `relay/`, `deploy/`, `.github/workflows/deploy.yml`, `docs/` (no `apps/`, `packages/`, `web/`); all tests green; image `ghcr.io/lephus/shellx-relay2:<R>` exists (fork run green).

**User steps (batched, ~10–15 min; never paste values in chat):**
- [ ] **G2.1 ghcr:** github.com/lephus → Packages → `shellx-relay2` → Package settings → Change visibility → **Public** (like `shellx-relay`, deploy/README step 4; it holds no secret).
- [ ] **G2.2 secret, on the VPS** (prints nothing):
  `cd ~/phu/shellx && printf 'CMUX_RELAY_HMAC_SECRET=%s\n' "$(openssl rand -base64 48)" >> .env && chmod 600 .env && grep -c '^CMUX_RELAY_HMAC_SECRET=' .env` → `1` (48 bytes → 64 base64 characters on one line, no `=` padding; ≥ 32 bytes as `cmux-relay` requires).
- [ ] **G2.3 nginx-proxy version, on the VPS:** `docker ps --format '{{.Image}}' | grep -i nginx-proxy` → tell the agent the image tag only. If it predates `VIRTUAL_PATH` support (open question 2) or you prefer no risk: add DNS `A relay2.shellx.pro` → the VPS now and say "subdomain"; the agent then deploys `feat/relay-v2-subdomain` instead.
- [ ] **G2.4 deploy route decision** (open question 1): `deploy.yml` only deploys commits on `main` (M2 ancestor check + `production` environment limited to `main`), so a `workflow_dispatch` on `feat/relay-v2` is refused by design. Recommended: say **"go main server-only"** — L0 merges `feat/relay-v2` into `main` and pushes; `deploy.yml` deploys; `release-desktop.yml` also starts but its `prepare` job sees `1.0.0` already on `download.shellx.pro` (`resolve-version.mjs`, verified 200 on 2026-10-19) and builds nothing (≈1 ubuntu minute, not ~300). Otherwise say **"wait"** and the deploy happens at the T+12 close (L5/L6 keep using local relays until then).
- [ ] **G2.5 after the deploy run is green:** copy the updated `~/phu/shellx/nginx-proxy/relay.shellx.pro` (and `relay2.shellx.pro` on the fallback) into nginx-proxy's `vhost.d` and recreate per deploy/README step 5; then `docker exec <nginx-proxy> nginx -T 2>/dev/null | grep -c 'location = /v2/relay'` → `1` (path route only).
- [ ] **G2.6 smoke (your terminal, password typed hidden):** `! cd ~/Documents/myProjects/shellx-wt-l4/relay && npm run relay2:smoke` → `relay2 smoke: OK (registered, lease 30 s)`. It leaves a signed-out device named `relay2-smoke` in your account (v1 keeps device rows).

**Agent verification (no secrets needed):**
- [ ] `curl -s -o /dev/null -w '%{http_code}\n' https://relay.shellx.pro/v2/relay` → `400` (or `426`); `curl -s -X POST https://relay.shellx.pro/v2/relay/tickets` → `{"error":{"code":"unauthorized",…}}`; `curl -s https://relay.shellx.pro/v1/version` → today's body; `curl -s -H 'X-ShellX-Platform: macos' -H 'X-ShellX-OS-Version: 15.1' https://relay.shellx.pro/v1/version` → `min_agent "2.0.0"` (if Task 9 shipped); the existing Flutter app on this Mac still connects (menu shows online).
- [ ] Rollback (if any check fails): **Actions → Deploy → Run workflow** with the previous `main` sha (allowed: it is an ancestor of `main`). Migration 0005 stays applied (forward-only); the old code ignores `machines*` tables, but its admin stats throw on `desktop` rows and its `/v1/ws` would admit a desktop token as a non-agent — so after a rollback, quit the native sprint builds until the fix is redeployed (open question 7).
- [ ] Lane report to L0: "ready <sha>" for `feat/relay-v2` (and `shellx/l4-relay2`), deploy run id, image sha `R`, route used (path or subdomain), `relay_url` value for L5/L6, open questions left.

### Task 12: Flutter 1.0.1 change — send platform and OS version (no release)

Implements W3 Task A2 exactly (files, interfaces `clientPlatformHeader`, `clientOsVersionHeader`, `ShellxApi(…, clientPlatform, clientOsVersion)`, `flutterPlatformName()`, `normalizedOsVersion(…)`, and its test table) on shellx branch `feat/flutter-1.0.1` in `~/Documents/myProjects/shellx-wt-l4-flutter`. Master: "Flutter 1.0.1 change (no release)" — the pubspec stays `1.0.0+1`; `bump.mjs` is W3 A3, after the sprint.

- [ ] **Step 1:** Write the W3 A2 Step 1 tests (`packages/shellx_core/test/api/shellx_api_test.dart`, `apps/desktop/test/platform/system_info_test.dart`), with the header values matching Task 9's `audienceOf` (`flutter-macos`, `flutter-windows`; OS `14.5`, `15.1.1`, `12.7.6`, `10.0.22631`).
- [ ] **Step 2:** Run `cd packages/shellx_core && flutter test test/api/shellx_api_test.dart` and `cd apps/desktop && flutter test test/platform/system_info_test.dart` — Expected: FAIL.
- [ ] **Step 3:** Implement per W3 A2 Step 3.
- [ ] **Step 4:** Run `flutter test` in `packages/shellx_core`, `apps/desktop`, `apps/mobile` — Expected: PASS; `git diff main -- apps/desktop/pubspec.yaml` is empty.
- [ ] **Step 5:** Commit `feat(desktop): send X-ShellX-Platform and X-ShellX-OS-Version (1.0.1 code only, C15)`; do not push; tell L0 the branch name for the ledger (W3 A2 skip condition).

---

## Open questions and risks (for L0; none blocks Tasks 1–7)

1. **G2 deploy route.** `deploy.yml` refuses any ref not on `main` and the `production` environment is limited to `main` (deploy/README.md lines 51, 95–97), so master G2's "workflow_dispatch on `feat/relay-v2`" cannot work without weakening those guards. A server-only `main` push costs ~1 ubuntu minute for `release-desktop.yml` (pubspec still `1.0.0`, already published), not ~300. Needs an explicit user/L0 ruling against the master "never push main" rule.
2. **nginx-proxy path routing** (`VIRTUAL_PATH: "= /v2/relay"` + `VIRTUAL_DEST: /v1/relay`, the other container on `/`): needs an nginx-proxy release with path routing, and that its template accepts an exact-match (`=`) location; not verified (VPS image version unknown). A plain prefix route would steal `/v2/relay/tickets`. Fallback branch ready; G2.3 decides.
3. **K1 ambiguities resolved here (please confirm with L5):** `*_b64` accepts standard or URL alphabet, returned verbatim; `requester_fingerprint` = fingerprint of the requester **machine's noise key** (not of `requester_x25519_b64`); re-`POST /v2/machines` returns 200 and a key change revokes grants; `DELETE /v2/machines/:id` allowed for any desktop of the account; `deny` also lets the requester cancel; pairings stay listed 10 min.
4. **Desktop accounts cannot change the password** (`POST /v1/auth/password` is agent-only); fine for the sprint, decide before 2.0.0.
5. **`relay2` ghcr package visibility:** the first fork push creates it private; the VPS pulls anonymously (G2.1). Publishing a public image of the `cmux-relay` binary is distribution: labels point to the exact fork source; the MIT-vs-GPL question to Manaflow (ledger draft) is still unsent.
6. **Long-idle circuits:** nginx timeouts raised to 330 s (crate idle 300 s); whether cmux-remote sends keepalives on idle terminal circuits is unverified — watch for drops after ~5 idle minutes in L5's e2e.
7. **Rollback after 0005** leaves `desktop` rows that pre-sprint code mishandles (admin stats 500; `/v1/ws` admits them as non-agents). Acceptable for a short rollback window; a cleanup needs a hand-run SQL that the runbook currently forbids.
8. **Browsers cannot use relay2 directly:** `cmux-relay` answers 403 to any request with an `Origin` header (verified) — L7's share viewer needs a bridge or a crate change.

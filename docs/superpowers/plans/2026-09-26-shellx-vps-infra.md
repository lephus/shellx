# ShellX — Move the infrastructure from Cloudflare to the VPS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run ShellX on the user's own VPS instead of Cloudflare: the relay becomes a Node.js process (same REST/WebSocket protocol, SQLite instead of D1, an in-process hub instead of the Durable Object), the website and the installers are served by an nginx container, and a push to `main` builds, tests and deploys everything into one folder, `~/phu/shellx`, with an automatic rollback.

**Architecture:** `relay/` keeps Hono and all business logic and swaps only the Cloudflare parts: `@hono/node-server` + `ws` for HTTP/WebSocket, a small synchronous `Db` over `better-sqlite3` with file migrations, a `HubRegistry` of per-account hubs whose operations run through one serial queue, `@node-rs/argon2` with a 4-hash cap, and an in-memory sliding-window rate limiter keyed by `X-Real-IP`. Two images (`shellx-relay`, whose build runs every relay test, and `shellx-web`, nginx + the Astro build) run with a daily SQLite backup container behind the VPS's existing `nginx-proxy` + letsencrypt-companion. `deploy.yml` builds and pushes both images to GHCR, rsyncs `deploy/` into `~/phu/shellx`, and runs `deploy/rollout.sh` over SSH, which restores the previous image tag if the relay is not healthy within 60 s.

**Tech Stack:** Node.js 22 (container `node:22-bookworm-slim`; Node 25 works locally), TypeScript 5.9 (`module: nodenext`), Hono 4.13, `@hono/node-server` 2.1.1, `ws` 8.22.0, `better-sqlite3` 13.0.3, `@node-rs/argon2` 2.2.1, Vitest 4.1 (Node, `forks` pool), Astro 7, nginx:alpine, Docker Compose v2, GitHub Actions (CD only), rsync/ssh.

**Spec:** `docs/superpowers/specs/2026-09-26-shellx-vps-infra-design.md` (approved 2026-09-26; decision **V8 added by the user on 2026-09-27**: everything ShellX puts on the VPS lives in ONE folder `phu/shellx` in the deploy user's home, read by workflows from the GitHub variable `VPS_APP_DIR`, with the database as a bind mount `./data`; the only file outside it is the nginx-proxy per-vhost config in `vhost.d`). The v1 spec `docs/superpowers/specs/2026-09-25-shellx-v1-design.md` §5, §6 and §10.2 stay the behavioural contract of the relay.

All relay commands run from `relay/` unless a step says "from the repository root". Commit steps always run from the repository root.

**Task order and in-between states.** Tasks 1–5 port the relay one layer at a time. Until Task 5 the not-yet-ported Cloudflare files stay in the repository but are listed in an `exclude` array in `relay/tsconfig.json` and a `NOT_YET_PORTED` array in `relay/vitest.config.ts`; each task removes exactly the entries it ports, and Task 5 deletes both lists. `npm run dev` does not work between Task 1 (Worker entry removed) and Task 5 (Node entry added). Every task ends with `npm run typecheck` and `npm test` green; the counts after each task are 66, 86, 110, 239 and 263 tests.

---

## Global Constraints

- **Protocol unchanged:** REST paths and bodies, error codes and the JSON shape `{"error": {"code", "message"}}`, WebSocket close codes **4001 replaced / 4002 revoked / 4003 rate_limited**, the binary frame layout and CBOR `pairing_removed` EVENT, pairing and tombstone rules are those of the v1 spec (§5, §6, §10.2). `packages/`, `apps/desktop/` and `apps/mobile/` are not modified.
- **argon2id:** m = 19456 KiB, t = 2, p = 1, 32-byte hash, stored as PHC `$argon2id$v=19$m=19456,t=2,p=1$<salt>$<hash>`; passwords are NFC-normalised UTF-8; **at most 4 hashes run at once, the 5th waits**.
- **Rate limits:** login **10/IP** and **5/email**, register **3/IP**, per **60 s** window, in memory; over the limit → HTTP 429 `rate_limited`. Only `RATE_LIMITS_ENABLED=false` turns them off (local dev and E2E only).
- **Client IP:** `X-Real-IP` set by nginx-proxy, trusted only from loopback/private peers; otherwise (and when absent) the socket address. Used only by the in-memory limiters.
- **WebSocket limits:** frames over 64 KiB → ERROR `frame_too_large`; 500 frames/s per device → ERROR `rate_limited` then close 4003; text `ping` → `pong` immediately, outside the hub queue.
- **Logging:** `logMeta` JSON lines with metadata only (time, `device_id`, error kind). **Never log IP addresses, e-mail addresses, tokens, passwords or payloads.** Errors are logged by kind (`SQLITE_BUSY`, class name), never by message.
- **Exact dependency pins** (new): `better-sqlite3` **13.0.3**, `@node-rs/argon2` **2.2.1**, `@hono/node-server` **2.1.1**, `ws` **8.22.0**, `@types/better-sqlite3` **9.6.0**, `@types/ws` **8.18.1**, `@types/node` **22.20.4**. Keep `hono ^4.13.9`, `tsx ^4.23.15`, `typescript ^5.9.3` (not 7.x) and `vitest ~4.1.11` (not 5.x). `relay/.npmrc` has `ignore-scripts=true`.
- **Relay config** (`src/config.ts`, read once): `PORT` (8080), `HOST` (`0.0.0.0`), `DB_PATH` (`/data/relay.db`), required `MIN_AGENT`, `MIN_MOBILE`, `LATEST_AGENT_VERSION`, `MAC_URL`, `WIN_URL`, optional `RATE_LIMITS_ENABLED`. A missing/bad value → one line `relay: …` on stderr, exit 1.
- **SQLite:** `journal_mode=WAL`, `foreign_keys=ON`, `busy_timeout=5000`; migrations `relay/migrations/*.sql` applied in file-name order at startup, one transaction each, recorded in `schema_migrations(name, applied_at)`; `0001_init.sql` unchanged; no down-migrations.
- **Graceful shutdown:** SIGTERM/SIGINT → stop accepting connections → close every socket with **1001** "going away" → wait for requests and hub queues at most **5 s** → close the DB → exit 0; all under Compose's `stop_grace_period: 10s`.
- **Local dev:** `npm run dev` serves `127.0.0.1:8787` with `DB_PATH=.data/relay.db` and `RATE_LIMITS_ENABLED=false`; `shellx_e2e` must pass 7/7 against it with `SHELLX_E2E_RELAY=http://127.0.0.1:8787`.
- **Images:** `ghcr.io/lephus/shellx-relay:<commit sha>` and `ghcr.io/lephus/shellx-web:<commit sha>`, public, no secrets inside. The relay image only exists if `npm run typecheck && npm test` passed in its `test` stage (V6).
- **VPS layout (V8, user decision 2026-09-27):** everything in `$HOME/phu/shellx` of the SSH deploy user = GitHub **variable** `VPS_APP_DIR` (default `phu/shellx`, relative to that home): `docker-compose.yml`, `relay.env`, `.env` (`IMAGE_TAG`, `PROXY_NETWORK`), `data/` (bind mount `./data:/data`, owned by uid **1000**), `backups/`, `downloads/desktop/<version>/`, `nginx-proxy/` (originals of the vhost.d files), `backup/` (backup scripts). **CD never writes outside `VPS_APP_DIR`.** The only files outside it are the nginx-proxy per-vhost files, copied once by the user into `vhost.d`.
- **Compose:** project `name: shellx`; services `relay`, `web`, `backup`; `relay` and `web` on the external network `${PROXY_NETWORK}`; json-file logs `max-size 10m`, `max-file 3`; `relay` healthcheck `GET /v1/version`, `restart: unless-stopped`, `stop_grace_period: 10s`.
- **Backup:** daily at **03:00** VPS time, `sqlite3 /data/relay.db ".backup …"` into `backups/relay-<YYYY-MM-DD>.db`, **keep the 14 newest**, `./data` mounted read-only.
- **nginx:** `access_log off` for `shellx.pro`, `www.shellx.pro`, `download.shellx.pro` (web container) and in the vhost.d files; `www` → `301 https://shellx.pro$request_uri`; `download.shellx.pro` serves `/srv/downloads` with no directory listing and `Content-Disposition: attachment`; relay vhost: `proxy_read_timeout 120s`, `proxy_send_timeout 120s`, `client_max_body_size 32k`.
- **GitHub:** repository secrets `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY`, `VPS_KNOWN_HOSTS` (strict host key checking); variable `VPS_APP_DIR`; remove `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` and the `R2_BUCKET` env. **No CI**: `ci.yml` is deleted; only `deploy.yml` (push `main` touching `relay/**`, `web/**`, `deploy/**`, `.github/workflows/deploy.yml`; `workflow_dispatch` input `ref`; `concurrency: deploy-production`, not cancelled) and `release-desktop.yml`.
- **`[quốc gia]` marker:** the privacy policy and terms (vi and en) name the hosting country as the literal placeholder `[quốc gia]` until the user supplies it; `npm run build` in `web/` (and therefore the web image and every deploy) refuses to build while any page contains it.
- Vietnamese user-facing text is kept verbatim; the plan prose is English.

## Review Focus

The five inputs or failure modes most likely to hurt a real user that the spec implies but no ported test covered; each has a pinning test in the owning task:

1. **Two sockets of the same device racing in one tick** (a phone that reconnects twice during a network flap): exactly one survives, the other gets 4001, peers see the device come online (never offline in between) and `GET /v1/devices` reports it online. Test: Task 4, `test/hub.test.ts` "two sockets of the same device racing in one tick…".
2. **SIGTERM during an in-flight REST call that touches the hub** (a deploy while someone changes their password): the call finishes with its normal answer (204, never a 500 from a closed database), sockets get 1001, the database closes only afterwards, and the change is on disk. Test: Task 5, `test/server.test.ts` "lets an in-flight REST call that touches the hub finish before the database closes".
3. **SQLite busy/locked** (the reset-password script or another connection holding the write lock): the request fails cleanly with 500 `internal_error`, the log says only `SQLITE_BUSY`, nothing half-written, the relay keeps serving and the same request succeeds once the lock is gone; a failing hub operation rejects only its caller and the queue keeps going. Tests: Task 1 `test/db.test.ts` "fails with SQLITE_BUSY after the busy timeout…", Task 3 `test/user-hub.test.ts` "runs operations in arrival order and survives a failing one…", Task 4 `test/auth.test.ts` "database contention".
4. **`X-Real-IP` spoofing when a request does not come through nginx-proxy** (the container port exposed by mistake): a public peer cannot choose its rate-limit key; a request without the header is keyed by its socket address. Tests: Task 2 `test/limiter.test.ts` "ignores X-Real-IP from a public peer…", Task 4 `test/auth.test.ts` "keys a request without X-Real-IP by its socket address".
5. **Unusable data volume at startup** (wrong owner, read-only, a file where the directory should be, a corrupt file): the relay prints one line and exits 1 without listening, so the healthcheck fails and the deploy rolls back; the deploy refuses a `data/` not owned by uid 1000 before touching anything. Tests: Task 5 `test/server.test.ts` "startup failures exit 1 with a one-line error" (4 cases), Task 7 `deploy/tests/rollout.test.mjs` "refuses to deploy when data/ does not belong to the relay user".

A sixth hazard found while prototyping is designed out rather than tested at the edges: a route that keeps a hub across an `await` must not talk to a hub the registry already dropped (Task 3: `UserHub` is a stateless handle over the live `HubState`; Task 4 `test/hub.test.ts` "closes the socket with 4002 if the token is revoked in the gap…" exercises it).

---

## Facts verified while writing this plan (2026-09-27; macOS arm64, Node 25.0.0, npm 11.7.0, Docker 20.10.23)

The whole port was built in a scratch copy first; every code block below is copied from files that passed. Tasks 1–5 were then replayed in order on a fresh copy of `relay/` at 0091c23: typecheck and tests were green after each task (66 → 86 → 110 → 239 → 263 tests) and the result was byte-identical to the prototype. `shellx_e2e` passed 7/7 against `npm run dev` of the Node relay; the relay suite passed 5 runs in a row (≈ 9 s each).

- **better-sqlite3 13.0.3** bundles N-API prebuilds for darwin/linux/linuxmusl/win32 × x64/arm64 inside the package (`"gypfile": false`, no install script), so it loads on Node 25 locally and Node 22.23.3 in the container without compiling. npm 11 respects that; **npm 10.9.9 (bundled with Node 22) still runs `node-gyp rebuild` and fails without Python**, hence `relay/.npmrc` with `ignore-scripts=true` (no dependency needs an install script; `tsx`/esbuild work without esbuild's postinstall). It binds `Buffer`/`Uint8Array` as BLOB but **throws TypeError for `ArrayBuffer`** (the `crypto.subtle` token hashes) and booleans → `Db` converts `ArrayBuffer` to `Buffer`. `get()` returns `undefined` for no row. Errors are `SqliteError` with `code` (`SQLITE_BUSY`, `SQLITE_CANTOPEN`, `SQLITE_NOTADB`). With `fileMustExist` and a missing directory it throws a plain `TypeError`, so `Db.open` checks existence itself (`ENOENT`).
- **@node-rs/argon2 2.2.1:** `hash(password: string | Uint8Array, { algorithm, version, memoryCost, timeCost, parallelism, outputLen, salt? }) → Promise<string>` (PHC), `verify(phc, password) → Promise<boolean>`. `Algorithm` and `Version` are `const enum`s (an empty object at runtime; not importable under `isolatedModules`), so the code uses `2` (Argon2id) and `1` (version 0x13). It reproduces **both known-answer vectors of the old WASM build byte for byte**, so hashes already stored verify unchanged. A malformed PHC makes `verify` throw `InvalidArg: Decoding failed` → the wrapper returns `false`; a `$argon2i$` string returns `false`. Hash + verify ≈ 16 ms; operations run on the libuv thread pool.
- **@hono/node-server 2.1.1** has built-in `ws` support: `createAdaptorServer({ fetch, websocket: { server: new WebSocketServer({ noServer: true }) } })` handles the `upgrade` event, runs the Hono route with `c.env = { incoming, outgoing: undefined }`, and completes the handshake only if the route answered through its `upgradeWebSocket(createEvents)`; otherwise it writes the route's status (401, 426) **with an empty body**. `onOpen(event, ws)` gets `ws.raw` = the `ws` WebSocket; `onMessage` gets text as `string` and binary as `ArrayBuffer`; messages that arrive before `onOpen` are buffered. `createEvents` receives a loosely typed `Context`. Node only emits `upgrade` when the request has `Connection: upgrade`.
- `fetch()` (undici) refuses an `Upgrade` request header (`invalid upgrade header`), so the test harness sends requests with `node:http`.
- **ws 8.22.0:** `maxPayload` closes the socket with 1009; the client emits `unexpected-response` for a refused upgrade.
- TypeScript `module: nodenext` requires `.js` on relative imports and `with { type: "json" }` on JSON imports; `tsc` copies the imported `disposable-domains.json` into `dist/`.
- **`sqlite3 .backup` through a read-only mount** works while the relay runs (it holds the WAL/SHM files open); with the relay stopped it fails with "unable to open database file". A stopped relay changes nothing, so the backup script logs a one-line skip. `sqlite3` would silently create (and back up) an empty database if the file were missing, so the script checks first.
- **Images:** relay image 278 MB; its `test` stage ran the 263 tests as uid 1000 in ≈ 10 s; adding a failing test makes `docker build` exit 1 with no image. Base images at the time: node 22.23.3, nginx 1.31.6 (alpine), alpine 3.22.6. `web/Dockerfile.dockerignore` (BuildKit) limits the repository-root build context to `web/` and `deploy/web/`.
- **nginx in the web image** (checked with `curl -H Host:`): `/privacy` → 301 `Location: /privacy/`; unknown path → 404 with `404.html`; `www` → 301 `https://shellx.pro…`; installers → 200 `application/octet-stream`, `Content-Disposition: attachment`; directories → 404; zero request lines in the container log.
- **Compose run of the real `deploy/docker-compose.yml`** with local images: relay healthy after ≈ 12 s; `deploy/rollout.sh` with an image that never becomes healthy restored the previous `IMAGE_TAG` and exited 1.
- **nginx-proxy `vhost.d`:** a symlink to `~/phu/shellx/...` would dangle inside the proxy container, and docker-gen only includes `vhost.d/<host>` if the file existed when it last generated its configuration → the runbook copies the files and recreates the ShellX containers.
- The `actionlint` npm package (wasm 2.0.6) predates the `vars` context and reports false positives; `python3` with PyYAML is available locally and is used to validate the workflows.

## File Structure

| Path | Responsibility | Task |
|---|---|---|
| `relay/.npmrc` | `ignore-scripts=true` (no native compile) | 1 |
| `relay/package.json`, `package-lock.json` | Node dependencies and scripts (`build`, `dev`, `test`, `typecheck`, `domains:update`, `reset-password`) | 1, 2, 4, 5 |
| `relay/tsconfig.json`, `relay/tsconfig.build.json`, `relay/vitest.config.ts` | Type checking of src/test/scripts; `tsc` build of `src/` into `dist/`; Vitest on Node | 1–5 |
| `relay/src/config.ts` | Environment → `Config`, one-line `ConfigError` | 1 |
| `relay/src/db/db.ts`, `relay/src/db/migrate.ts` | `Db` over better-sqlite3; file migrations + `schema_migrations` | 1 |
| `relay/migrations/0002_hub_state.sql` | Hub tombstones `pending_pairing_removed` with `user_id` | 1 |
| `relay/src/log.ts` | `logMeta` (unchanged) + `errorKind` | 1 |
| `relay/src/app.ts` | Hono app, dependency injection through `c.get(...)` | 1, 4 |
| `relay/src/relay.ts` | `startRelay`: HTTP server, `ws` upgrade, graceful `shutdown` | 1, 4, 5 |
| `relay/src/server.ts` | Container entry: config, DB + migrations, signals | 5 |
| `relay/src/auth/password.ts`, `rate-limit.ts`, `client-ip.ts` | argon2id with a 4-hash cap; sliding-window limiters; rate-limit key | 2 |
| `relay/src/hub/frame-budgets.ts`, `user-hub.ts`, `registry.ts` | 500 frames/s budgets; per-account hub state + serial queue; registry | 3 |
| `relay/src/auth/session.ts`, `relay/src/routes/*.ts` | Token auth and the REST/WebSocket routes on `Db` and the registry | 4 |
| `relay/src/scripts/*.ts` | `reset-password` on SQLite (moved from `relay/scripts/`) | 5 |
| `relay/scripts/blocklist.ts`, `update-disposable-domains.ts` | Unchanged dev tools (run with `tsx`) | — |
| `relay/test/*.ts` | Harness (`helpers.ts`) and 16 test files | 1–5 |
| `relay/dev.env`, `relay/.gitignore`, `relay/README.md` | Local dev settings, ignores, Node/VPS docs | 5 |
| `relay/Dockerfile`, `relay/.dockerignore` | deps → test → build → runtime image | 6 |
| `web/Dockerfile`, `web/Dockerfile.dockerignore`, `deploy/web/nginx.conf` | Astro build + nginx image, three server blocks | 6 |
| `web/scripts/check-placeholders.mjs`, `web/tests/placeholders.test.mjs`, `web/package.json` | `[quốc gia]` build guard | 6 |
| `deploy/docker-compose.yml`, `deploy/relay.env` | Compose project `shellx` for `~/phu/shellx` | 7 |
| `deploy/backup/entrypoint.sh`, `deploy/backup/backup-once.sh` | Daily 03:00 backup, keep 14 | 7 |
| `deploy/nginx-proxy/{relay.shellx.pro,shellx.pro,www.shellx.pro,download.shellx.pro}` | vhost.d originals | 7 |
| `deploy/rollout.sh`, `deploy/tests/*.test.mjs`, `deploy/README.md` | Remote rollout with rollback, its tests, the runbook | 7 |
| `.github/workflows/deploy.yml`, `release-desktop.yml`, `ci.yml` (deleted), `release/README.md` | CD | 8 |
| `docs/superpowers/specs/2026-09-25-shellx-v1-design.md`, `web/src/pages/{,en/}{privacy,terms}.md`, `web/README.md`, `web/astro.config.mjs`, `web/src/pages/404.astro`, `web/src/lib/site.ts`, `web/tests/site.test.mjs`, `docs/superpowers/HANDOFF.md` | Docs, legal text with `[quốc gia]` | 9 |

Files deleted: `relay/wrangler.jsonc`, `relay/src/index.ts`, `relay/src/env.ts`, `relay/src/auth/argon2.ts`, `relay/src/types/wasm.d.ts`, `relay/scripts/reset-sql.ts`, `relay/scripts/tsconfig.json`, `relay/test/apply-migrations.ts`, `relay/test/env.d.ts`, `.github/workflows/ci.yml`.

**Why 9 tasks and not the 8 of the brief:** "Auth on Node" was split. Its primitives (argon2, limiter, client IP) are Task 2; its routes moved into Task 4 together with the WebSocket route, because `logout`, `password` and account deletion call the hub (Task 3), and every WebSocket, account and pairing test needs register/login and the pairing routes: splitting routes from the WebSocket would leave route code untested by its own task.

---
### Task 1: Node foundation — tooling, config, `Db`, migrations, test harness, `/v1/version` on Node

The test runner switches from the Workers pool to plain Node, the relay gets its configuration, database and migration layer, and a real HTTP server serves `/v1/version`. Routes that still use D1 stay in the repository but are excluded from type checking and tests until Task 4 ports them.

**Files:**
- Create: `relay/.npmrc`, `relay/src/config.ts`, `relay/src/db/db.ts`, `relay/src/db/migrate.ts`, `relay/migrations/0002_hub_state.sql`, `relay/src/relay.ts`, `relay/test/config.test.ts`, `relay/test/db.test.ts`
- Modify: `relay/package.json`, `relay/package-lock.json` (by npm), `relay/tsconfig.json`, `relay/vitest.config.ts`, `relay/src/app.ts`, `relay/src/log.ts`, `relay/src/auth/email.ts` (JSON import attribute), `relay/test/helpers.ts`, `relay/test/app.test.ts`, `relay/test/policy.test.ts` (JSON import attribute), every `*.ts` under `relay/src`, `relay/test`, `relay/scripts` (relative imports get `.js`)
- Delete: `relay/src/index.ts`, `relay/src/env.ts`, `relay/test/apply-migrations.ts`, `relay/test/env.d.ts`, `relay/scripts/tsconfig.json`

**Interfaces:**
- Consumes: nothing new (existing `src/http/errors.ts`: `ApiError`, `Errors`, `errorBody`; `src/log.ts`: `logMeta`).
- Produces:
  - `src/config.ts`: `interface Config { host: string; port: number; dbPath: string; minAgent: string; minMobile: string; latestAgentVersion: string; macUrl: string; winUrl: string; rateLimitsEnabled: boolean }`, `class ConfigError extends Error`, `loadConfig(env: Readonly<Record<string, string | undefined>>): Config`, `REQUIRED_VARIABLES`, `DEFAULT_PORT = 8080`, `DEFAULT_HOST = "0.0.0.0"`, `DEFAULT_DB_PATH = "/data/relay.db"`.
  - `src/db/db.ts`: `type SqlValue = string | number | bigint | null | Uint8Array | ArrayBuffer`, `interface RunResult { changes: number }`, `interface DbOptions { busyTimeoutMs?: number; fileMustExist?: boolean }`, `BUSY_TIMEOUT_MS = 5000`, `class Db { static open(path: string, options?: DbOptions): Db; get<T>(sql: string, ...params: SqlValue[]): T | undefined; all<T>(sql, ...params): T[]; run(sql, ...params): RunResult; exec(sql: string): void; transaction<T>(fn: () => T): T; get isOpen(): boolean; close(): void }`.
  - `src/db/migrate.ts`: `MIGRATIONS_DIR: string`, `migrate(db: Db, dir?: string): string[]` (names applied by this call).
  - `src/log.ts`: `logMeta(event, fields?)` (unchanged), `errorKind(err: unknown): string`.
  - `src/app.ts` (this task's version): `interface AppDeps { config: Config; db: Db; now?: () => number }`, `interface AppVariables { config; db; now }`, `interface AppBindings { incoming: IncomingMessage }`, `type AppEnv`, `createApp(deps: AppDeps): Hono<AppEnv>`.
  - `src/relay.ts` (this task's version): `interface ListenOptions { host: string; port: number }`, `interface RunningRelay { readonly server: Server; readonly port: number; readonly url: string }`, `startRelay(deps: AppDeps, listen: ListenOptions): Promise<RunningRelay>`.
  - `test/helpers.ts` (this task's version): `TEST_CONFIG`, `db()`, `tempDir()`, `onCleanup(fn)`, `interface TestApp { readonly ready: Promise<RunningRelay> }`, `makeApp(deps?: Partial<AppDeps>): TestApp`, `class TestResponse { status; headers; text(); json<T = any>() }`, `interface CallOptions { body?; token?; ip?: string | null; headers? }`, `call(app, method, path, options?)`, `callStreamed(app, method, path, chunks: Uint8Array[])`, `PASSWORD`, `randomEmail()`, `randomPublicKey()`, `type Kind`, `deviceBody(kind, overrides?)`, `interface Session`, `interface Account`, `registerAccount(app, email?, password?)`, `loginDevice(app, account, kind, publicKey?)`, `uuidv7(ms)`, `newPairingId()`, `pair(app, agentToken, mobileId, pairingId?)`, `pairingIdOf(agentId, mobileId)`, `errorCode(res)`, `hex(bytes)`, `waitFor(probe, timeoutMs?)`. Every test's database is a fresh migrated SQLite file in its own temp directory, created on first use and deleted after the test.

- [ ] **Step 1: Stop npm from compiling native modules, swap the dependencies**

Create `relay/.npmrc`:

```ini
# better-sqlite3 and @node-rs/argon2 ship prebuilt binaries; npm 10 (bundled with Node 22) would
# still try `node-gyp rebuild` for better-sqlite3 and fail without Python. No dependency needs an
# install script.
ignore-scripts=true
```

Then run (network needed):

```bash
npm uninstall @cloudflare/vitest-pool-workers @cloudflare/workers-types
npm install --save-exact better-sqlite3@13.0.3 @hono/node-server@2.1.1
npm install --save-exact --save-dev @types/better-sqlite3@9.6.0 @types/node@22.20.4
npm pkg set scripts.typecheck="tsc -p tsconfig.json"
```

`dependencies` must now read `"@hono/node-server": "2.1.1"`, `"@phi-ag/argon2": "0.5.28"`, `"better-sqlite3": "13.0.3"`, `"hono": "^4.13.9"`; `devDependencies` `"@types/better-sqlite3": "9.6.0"`, `"@types/node": "22.20.4"`, `"tsx": "^4.23.15"`, `"typescript": "^5.9.3"`, `"vitest": "~4.1.11"`, `"wrangler": "^4.139.0"` (`@phi-ag/argon2` goes in Task 2, `wrangler` in Task 5). Leave the other scripts alone for now.

- [ ] **Step 2: Delete the Workers entry point and the Workers test plumbing**

```bash
git rm -q src/index.ts src/env.ts test/apply-migrations.ts test/env.d.ts scripts/tsconfig.json
```

(`scripts/*.ts` are now type-checked by the main `tsconfig.json`.)

- [ ] **Step 3: Add `.js` to every relative import (Node ESM)**

Run this one-off codemod from `relay/` (it prints `added .js extensions in 29 files`):

```bash
node --input-type=module <<'CODEMOD'
// Adds ".js" to every extensionless relative import/export specifier (Node ESM + "module": "nodenext").
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
const files = (dir) => readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
  e.isDirectory() ? files(join(dir, e.name)) : e.name.endsWith(".ts") ? [join(dir, e.name)] : []);
const specifier = /(\bfrom\s*|\bimport\s*\(\s*|\bimport\s+)(["'])(\.\.?\/[^"']*?)\2/g;
let changed = 0;
for (const file of ["src", "test", "scripts"].flatMap(files)) {
  const before = readFileSync(file, "utf8");
  const after = before.replace(specifier, (m, lead, q, spec) =>
    /\.(js|json|wasm)$/.test(spec) ? m : `${lead}${q}${spec}.js${q}`);
  if (after !== before) {
    writeFileSync(file, after);
    changed++;
  }
}
console.log(`added .js extensions in ${changed} files`);
CODEMOD
```

Then give the two JSON imports an import attribute. In `src/auth/email.ts` replace the first line

```ts
import disposableDomains from "./disposable-domains.json";
```

with

```ts
import disposableDomains from "./disposable-domains.json" with { type: "json" };
```

and in `test/policy.test.ts` replace

```ts
import disposableDomains from "../src/auth/disposable-domains.json";
```

with

```ts
import disposableDomains from "../src/auth/disposable-domains.json" with { type: "json" };
```

- [ ] **Step 4: Node type checking and the Node test runner, with the porting lists**

Replace `relay/tsconfig.json` (the `exclude` list names the files still written for Cloudflare; Tasks 2–5 remove its entries):

```jsonc
{
  "compilerOptions": {
    "target": "es2023",
    "module": "nodenext",
    "moduleResolution": "nodenext",
    "lib": ["es2023"],
    "types": ["node"],
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noEmit": true,
    "skipLibCheck": true,
    "isolatedModules": true,
    "resolveJsonModule": true,
    "verbatimModuleSyntax": true
  },
  "include": ["src", "test", "scripts", "vitest.config.ts"],
  // Still Cloudflare code; removed from this list by the plan task that ports each file.
  "exclude": [
    "src/auth/argon2.ts",
    "src/auth/password.ts",
    "src/auth/rate-limit.ts",
    "src/auth/session.ts",
    "src/hub/user-hub.ts",
    "src/routes",
    "src/types",
    "scripts/reset-password.ts",
    "test/account.test.ts",
    "test/auth.test.ts",
    "test/devices-pairings.test.ts",
    "test/hub.test.ts",
    "test/limits.test.ts",
    "test/password.test.ts",
    "test/rate-limit.test.ts",
    "test/reset-password.test.ts"
  ]
}
```

Replace `relay/vitest.config.ts`:

```ts
import { defineConfig } from "vitest/config";

/** Test files still written for the Workers pool; removed from this list as each is ported. */
const NOT_YET_PORTED = [
  "test/account.test.ts",
  "test/auth.test.ts",
  "test/devices-pairings.test.ts",
  "test/hub.test.ts",
  "test/limits.test.ts",
  "test/password.test.ts",
  "test/rate-limit.test.ts",
  "test/reset-password.test.ts",
];

export default defineConfig({
  test: {
    // Each test file runs in its own child process: better-sqlite3 and @node-rs/argon2 are native
    // addons, and the server tests spawn `src/server.ts` with signals.
    pool: "forks",
    include: ["test/**/*.test.ts"],
    exclude: NOT_YET_PORTED,
    testTimeout: 15_000,
    hookTimeout: 15_000,
  },
});
```

- [ ] **Step 5: Write the harness and the failing tests**

Replace `relay/test/helpers.ts` (a real relay on `127.0.0.1:<random port>` per `makeApp()`, a fresh migrated SQLite file per test, `node:http` requests because `fetch()` refuses `Upgrade` headers):

```ts
import { mkdtempSync, rmSync } from "node:fs";
import http from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach } from "vitest";
import type { AppDeps } from "../src/app.js";
import type { Config } from "../src/config.js";
import { Db } from "../src/db/db.js";
import { migrate } from "../src/db/migrate.js";
import { startRelay, type RunningRelay } from "../src/relay.js";

// ---- configuration used by every test relay ---------------------------------------------------

export const TEST_CONFIG: Config = {
  host: "127.0.0.1",
  port: 0,
  dbPath: "unused-in-tests.db",
  minAgent: "1.0.0",
  minMobile: "1.0.0",
  latestAgentVersion: "1.0.0",
  macUrl: "https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg",
  winUrl: "https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe",
  rateLimitsEnabled: false,
};

// ---- per-test environment: a temp directory with a migrated SQLite DB -------------------------

interface TestEnv {
  dir: string;
  db: Db;
}

let current: TestEnv | null = null;
const cleanups: (() => unknown)[] = [];

function testEnv(): TestEnv {
  if (current === null) {
    const dir = mkdtempSync(join(tmpdir(), "shellx-relay-test-"));
    const db = Db.open(join(dir, "relay.db"));
    migrate(db);
    current = { dir, db };
  }
  return current;
}

/** This test's database (created, and migrated, on first use). */
export function db(): Db {
  return testEnv().db;
}

/** This test's temporary directory (deleted after the test). */
export function tempDir(): string {
  return testEnv().dir;
}

/** Runs `fn` after the current test, before its database is closed (last registered runs first). */
export function onCleanup(fn: () => unknown): void {
  cleanups.push(fn);
}

afterEach(async () => {
  for (const fn of cleanups.splice(0).reverse()) await fn();
  if (current === null) return;
  const env = current;
  current = null;
  env.db.close();
  rmSync(env.dir, { recursive: true, force: true });
});

// ---- test relays --------------------------------------------------------------------------------

/** A relay listening on a random 127.0.0.1 port; started in the background by `makeApp`. */
export interface TestApp {
  readonly ready: Promise<RunningRelay>;
}

/**
 * Starts a real relay (HTTP server) for this test, over the test's database. `deps` overrides any
 * dependency for this app only.
 */
export function makeApp(deps: Partial<AppDeps> = {}): TestApp {
  const ready = startRelay({ config: TEST_CONFIG, db: db(), ...deps }, { host: "127.0.0.1", port: 0 });
  onCleanup(async () => {
    const relay = await ready;
    relay.server.closeAllConnections();
    await new Promise<void>((resolve) => relay.server.close(() => resolve()));
  });
  return { ready };
}

/** A buffered HTTP response (`json<T>()` is generic, like the Workers `Response` the tests were written for). */
export class TestResponse {
  constructor(
    readonly status: number,
    readonly headers: Headers,
    private readonly body: Buffer,
  ) {}

  async text(): Promise<string> {
    return this.body.toString("utf8");
  }

  async json<T = any>(): Promise<T> {
    return JSON.parse(this.body.toString("utf8")) as T;
  }
}

export interface CallOptions {
  body?: unknown;
  token?: string;
  /**
   * Sent as X-Real-IP (default 203.0.113.7; the test client connects from 127.0.0.1, a trusted
   * proxy address). `null` sends no X-Real-IP at all.
   */
  ip?: string | null;
  headers?: Record<string, string>;
}

/**
 * One HTTP request to the relay with `node:http` (fetch() refuses headers like `Upgrade`). A JSON
 * body gets `Content-Type: application/json` and a `Content-Length`; `chunks` sends a streamed
 * (chunked) body without one.
 */
export async function call(app: TestApp, method: string, path: string, options: CallOptions = {}): Promise<TestResponse> {
  const headers: Record<string, string> = { ...options.headers };
  if (options.token !== undefined) headers.Authorization = `Bearer ${options.token}`;
  if (options.ip !== null) headers["X-Real-IP"] = options.ip ?? "203.0.113.7";
  let body: Buffer | undefined;
  if (options.body !== undefined) {
    body = Buffer.from(typeof options.body === "string" ? options.body : JSON.stringify(options.body), "utf8");
    headers["Content-Type"] = "application/json";
    headers["Content-Length"] = String(body.length);
  }
  return request(app, method, path, headers, body === undefined ? [] : [body]);
}

/** Like `call`, but the body is streamed in `chunks` with no Content-Length (chunked encoding). */
export async function callStreamed(app: TestApp, method: string, path: string, chunks: Uint8Array[]): Promise<TestResponse> {
  return request(app, method, path, { "Content-Type": "application/json", "X-Real-IP": "203.0.113.7" }, chunks);
}

async function request(
  app: TestApp, method: string, path: string, headers: Record<string, string>, chunks: Uint8Array[],
): Promise<TestResponse> {
  const { port } = await app.ready;
  return new Promise((resolve, reject) => {
    const req = http.request({ host: "127.0.0.1", port, method, path, headers, agent: false }, (res) => {
      const received: Buffer[] = [];
      res.on("data", (chunk: Buffer) => received.push(chunk));
      res.on("end", () => {
        const responseHeaders = new Headers();
        for (const [name, value] of Object.entries(res.headers)) {
          if (value !== undefined) responseHeaders.set(name, Array.isArray(value) ? value.join(", ") : value);
        }
        resolve(new TestResponse(res.statusCode ?? 0, responseHeaders, Buffer.concat(received)));
      });
      res.on("error", reject);
    });
    req.on("error", reject);
    for (const chunk of chunks) req.write(chunk);
    req.end();
  });
}

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

/** A UUIDv7 (RFC 9562) for unix-millisecond timestamp `ms`, lower case, random in the other bits. */
export function uuidv7(ms: number): string {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  for (let i = 0; i < 6; i++) bytes[i] = Math.floor(ms / 2 ** (8 * (5 - i))) % 256;
  bytes[6] = 0x70 | (bytes[6]! & 0x0f); // version 7
  bytes[8] = 0x80 | (bytes[8]! & 0x3f); // variant 10
  const h = hex(bytes);
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

let lastPairingMs = 0;
/** A pairing id as the agent generates it (UUIDv7), strictly newer than every one returned before. */
export function newPairingId(): string {
  lastPairingMs = Math.max(Date.now(), lastPairingMs + 1);
  return uuidv7(lastPairingMs);
}

/** POST /v1/pairings as `agentToken`, with a fresh agent-generated pairing id unless one is given. */
export async function pair(
  app: TestApp,
  agentToken: string,
  mobileId: string,
  pairingId: string = newPairingId(),
): Promise<TestResponse> {
  return call(app, "POST", "/v1/pairings", { token: agentToken, body: { mobile_id: mobileId, pairing_id: pairingId } });
}

/** The `pairing_id` of the row for (agent, mobile), or null when there is no row. */
export async function pairingIdOf(agentId: string, mobileId: string): Promise<string | null> {
  return db().get<{ pairing_id: string }>("SELECT pairing_id FROM pairings WHERE agent_id = ? AND mobile_id = ?", agentId, mobileId)
    ?.pairing_id ?? null;
}

export async function errorCode(res: TestResponse): Promise<string> {
  const body = await res.json<{ error: { code: string; message: string } }>();
  return body.error.code;
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

Replace `relay/test/app.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { call, db, makeApp } from "./helpers.js";

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

  it("migrations created the four tables of 0001 and the tombstone table of 0002", () => {
    const names = db()
      .all<{ name: string }>(
        `SELECT name FROM sqlite_master WHERE type = 'table'
           AND name IN ('users','devices','tokens','pairings','pending_pairing_removed') ORDER BY name`,
      )
      .map((r) => r.name);
    expect(names).toEqual(["devices", "pairings", "pending_pairing_removed", "tokens", "users"]);
  });

  it("pairings carries the agent-generated pairing_id (TEXT NOT NULL) and keeps its (agent, mobile) key", () => {
    const columns = db().all<{ name: string; type: string; notnull: number; pk: number }>("PRAGMA table_info(pairings)");
    expect(columns.map((c) => [c.name, c.type, c.notnull, c.pk])).toEqual([
      ["agent_id", "TEXT", 1, 1],
      ["mobile_id", "TEXT", 1, 2],
      ["pairing_id", "TEXT", 1, 0],
      ["created_at", "INTEGER", 1, 0],
    ]);
  });
});
```

Create `relay/test/config.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { ConfigError, loadConfig } from "../src/config.js";

const REQUIRED = {
  MIN_AGENT: "1.0.0",
  MIN_MOBILE: "1.0.1",
  LATEST_AGENT_VERSION: "1.2.0",
  MAC_URL: "https://download.shellx.pro/desktop/1.2.0/ShellX-1.2.0.dmg",
  WIN_URL: "https://download.shellx.pro/desktop/1.2.0/ShellX-Setup-1.2.0.exe",
};

describe("loadConfig", () => {
  it("reads the version variables and applies the defaults", () => {
    expect(loadConfig(REQUIRED)).toEqual({
      host: "0.0.0.0",
      port: 8080,
      dbPath: "/data/relay.db",
      minAgent: "1.0.0",
      minMobile: "1.0.1",
      latestAgentVersion: "1.2.0",
      macUrl: REQUIRED.MAC_URL,
      winUrl: REQUIRED.WIN_URL,
      rateLimitsEnabled: true,
    });
  });

  it("reads HOST, PORT, DB_PATH and RATE_LIMITS_ENABLED", () => {
    const config = loadConfig({ ...REQUIRED, HOST: "127.0.0.1", PORT: "8787", DB_PATH: ".data/relay.db", RATE_LIMITS_ENABLED: "false" });
    expect(config).toMatchObject({ host: "127.0.0.1", port: 8787, dbPath: ".data/relay.db", rateLimitsEnabled: false });
  });

  it('keeps rate limits on for every value except the exact string "false"', () => {
    for (const flag of ["true", "", "False", "0", "no"]) {
      expect(loadConfig({ ...REQUIRED, RATE_LIMITS_ENABLED: flag }).rateLimitsEnabled).toBe(true);
    }
  });

  it("names every missing or blank required variable in one line", () => {
    const { MIN_AGENT: _a, MAC_URL: _m, ...rest } = REQUIRED;
    const run = () => loadConfig({ ...rest, WIN_URL: "   " });
    expect(run).toThrow(ConfigError);
    expect(run).toThrow("missing required environment variables: MIN_AGENT, MAC_URL, WIN_URL");
    expect(() => loadConfig({ ...REQUIRED, MIN_MOBILE: undefined })).toThrow("missing required environment variable: MIN_MOBILE");
  });

  it("refuses a PORT that is not an integer from 0 to 65535 (0 picks a free port)", () => {
    for (const port of ["abc", "65536", "80.5", "-1"]) {
      expect(() => loadConfig({ ...REQUIRED, PORT: port })).toThrow(`PORT must be an integer from 0 to 65535, got "${port}"`);
    }
    expect(loadConfig({ ...REQUIRED, PORT: "0" }).port).toBe(0);
  });
});
```

Create `relay/test/db.test.ts` (it also pins Review Focus 3 at the database level: a held write lock makes a statement fail with `SQLITE_BUSY` after the busy timeout, and the connection works again once the lock is gone):

```ts
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import Database from "better-sqlite3";
import { describe, expect, it } from "vitest";
import { Db } from "../src/db/db.js";
import { migrate, MIGRATIONS_DIR } from "../src/db/migrate.js";
import { tempDir } from "./helpers.js";

function openFresh(name = "fresh.db", options = {}): Db {
  const db = Db.open(join(tempDir(), name), options);
  return db;
}

describe("Db", () => {
  it("opens with WAL, foreign keys and a 5 s busy timeout, creating missing directories", () => {
    const db = Db.open(join(tempDir(), "nested", "dir", "relay.db"));
    try {
      expect(db.get<{ journal_mode: string }>("PRAGMA journal_mode")).toEqual({ journal_mode: "wal" });
      expect(db.get<{ foreign_keys: number }>("PRAGMA foreign_keys")).toEqual({ foreign_keys: 1 });
      expect(db.get<{ timeout: number }>("PRAGMA busy_timeout")).toEqual({ timeout: 5000 });
    } finally {
      db.close();
    }
  });

  it("get/all/run bind parameters, store ArrayBuffers as BLOBs and report changes", () => {
    const db = openFresh();
    try {
      db.exec("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, blob BLOB)");
      const hash = new Uint8Array([1, 2, 3, 255]).buffer;
      expect(db.run("INSERT INTO t (name, blob) VALUES (?, ?)", "a", hash)).toEqual({ changes: 1 });
      db.run("INSERT INTO t (name, blob) VALUES (?, ?)", "b", new Uint8Array([9]));
      expect(db.get<{ name: string }>("SELECT name FROM t WHERE blob = ?", hash)).toEqual({ name: "a" });
      expect(db.get("SELECT name FROM t WHERE name = ?", "zzz")).toBeUndefined();
      expect(db.all<{ name: string }>("SELECT name FROM t ORDER BY id").map((r) => r.name)).toEqual(["a", "b"]);
      expect(db.run("DELETE FROM t WHERE name = ?", "nope")).toEqual({ changes: 0 });
    } finally {
      db.close();
    }
  });

  it("transaction commits on return and rolls back everything on throw", () => {
    const db = openFresh();
    try {
      db.exec("CREATE TABLE t (name TEXT)");
      expect(db.transaction(() => {
        db.run("INSERT INTO t VALUES ('kept')");
        return 42;
      })).toBe(42);
      expect(() =>
        db.transaction(() => {
          db.run("INSERT INTO t VALUES ('lost')");
          throw new Error("boom");
        }),
      ).toThrow("boom");
      expect(db.all<{ name: string }>("SELECT name FROM t").map((r) => r.name)).toEqual(["kept"]);
    } finally {
      db.close();
    }
  });

  it("enforces ON DELETE CASCADE (foreign keys are on)", () => {
    const db = openFresh();
    try {
      migrate(db);
      db.run("INSERT INTO users VALUES ('u1', 'a@example.com', 'x', 1, 1)");
      db.run("INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at) VALUES ('d1', 'u1', 'agent', 'n', 'macos', x'00', 1)");
      db.run("DELETE FROM users WHERE id = 'u1'");
      expect(db.get("SELECT 1 FROM devices WHERE id = 'd1'")).toBeUndefined();
    } finally {
      db.close();
    }
  });

  it("fails with SQLITE_BUSY after the busy timeout while another connection holds the write lock", () => {
    const path = join(tempDir(), "busy.db");
    const db = Db.open(path, { busyTimeoutMs: 50 });
    const other = new Database(path);
    try {
      db.exec("CREATE TABLE t (n INTEGER)");
      other.exec("BEGIN IMMEDIATE");
      const started = Date.now();
      expect(() => db.run("INSERT INTO t VALUES (1)")).toThrow(expect.objectContaining({ code: "SQLITE_BUSY" }));
      expect(Date.now() - started).toBeGreaterThanOrEqual(40);
      other.exec("ROLLBACK");
      expect(db.run("INSERT INTO t VALUES (1)")).toEqual({ changes: 1 });
    } finally {
      other.close();
      db.close();
    }
  });

  it("fileMustExist refuses to create a database (or its directory)", () => {
    for (const path of [join(tempDir(), "missing.db"), join(tempDir(), "no-dir", "relay.db")]) {
      expect(() => Db.open(path, { fileMustExist: true })).toThrow(expect.objectContaining({ code: "ENOENT" }));
    }
  });
});

describe("migrate", () => {
  it("applies every migration once, in file-name order, and records them", () => {
    const db = openFresh();
    try {
      expect(migrate(db)).toEqual(["0001_init.sql", "0002_hub_state.sql"]);
      const rows = db.all<{ name: string; applied_at: number }>("SELECT name, applied_at FROM schema_migrations ORDER BY name");
      expect(rows.map((r) => r.name)).toEqual(["0001_init.sql", "0002_hub_state.sql"]);
      for (const row of rows) expect(row.applied_at).toBeGreaterThan(1_700_000_000_000);
    } finally {
      db.close();
    }
  });

  it("skips migrations that already ran (a restart applies nothing and keeps the data)", () => {
    const path = join(tempDir(), "restart.db");
    const first = Db.open(path);
    migrate(first);
    first.run("INSERT INTO users VALUES ('u1', 'a@example.com', 'x', 1, 1)");
    first.close();

    const second = Db.open(path);
    try {
      expect(migrate(second)).toEqual([]);
      expect(second.get("SELECT id FROM users")).toEqual({ id: "u1" });
    } finally {
      second.close();
    }
  });

  it("applies only the new file when a migration is added later", () => {
    const dir = join(tempDir(), "migrations");
    mkdirSync(dir);
    writeFileSync(join(dir, "0001_a.sql"), "CREATE TABLE a (x INTEGER);");
    const db = openFresh();
    try {
      expect(migrate(db, dir)).toEqual(["0001_a.sql"]);
      writeFileSync(join(dir, "0002_b.sql"), "CREATE TABLE b (y INTEGER);");
      writeFileSync(join(dir, "README.txt"), "not a migration");
      expect(migrate(db, dir)).toEqual(["0002_b.sql"]);
      expect(migrate(db, dir)).toEqual([]);
    } finally {
      db.close();
    }
  });

  it("rolls back a failing migration completely and does not record it", () => {
    const dir = join(tempDir(), "broken");
    mkdirSync(dir);
    writeFileSync(join(dir, "0001_ok.sql"), "CREATE TABLE ok (x INTEGER);");
    writeFileSync(join(dir, "0002_broken.sql"), "CREATE TABLE half (x INTEGER); INSERT INTO nowhere VALUES (1);");
    const db = openFresh();
    try {
      expect(() => migrate(db, dir)).toThrow(expect.objectContaining({ code: "SQLITE_ERROR" }));
      expect(db.all<{ name: string }>("SELECT name FROM schema_migrations").map((r) => r.name)).toEqual(["0001_ok.sql"]);
      expect(db.get("SELECT 1 FROM sqlite_master WHERE name = 'half'")).toBeUndefined();
    } finally {
      db.close();
    }
  });

  it("0002 creates the tombstone table with user_id and a (user_id, agent_id) index", () => {
    const db = openFresh();
    try {
      migrate(db, MIGRATIONS_DIR);
      const columns = db.all<{ name: string; type: string; notnull: number }>("PRAGMA table_info(pending_pairing_removed)");
      expect(columns.map((c) => [c.name, c.type, c.notnull])).toEqual([
        ["user_id", "TEXT", 1],
        ["agent_id", "TEXT", 1],
        ["mobile_id", "TEXT", 1],
        ["pairing_id", "TEXT", 1],
      ]);
      const index = db.all<{ name: string }>("PRAGMA index_info(pending_pairing_removed_user_agent)");
      expect(index.map((c) => c.name)).toEqual(["user_id", "agent_id"]);
    } finally {
      db.close();
    }
  });
});
```

- [ ] **Step 6: Run the tests to verify they fail**

Run: `npx vitest run test/config.test.ts test/db.test.ts test/app.test.ts`
Expected: FAIL — `Error: Cannot find module '../src/config.js' imported from …/test/config.test.ts` (and the same for `../src/db/db.js` and `../src/relay.js`).

- [ ] **Step 7: Implement configuration, database, migrations, logging, app and server**

Create `relay/src/config.ts`:

```ts
/**
 * Relay configuration, read once from environment variables at startup (spec §4.2). Unknown
 * variables are ignored. A missing or malformed value throws `ConfigError` with a one-line message;
 * `src/server.ts` prints it and exits 1.
 */
export interface Config {
  /** Interface to listen on; `0.0.0.0` in the container, `127.0.0.1` for `npm run dev`. */
  host: string;
  /** 0 picks a free port (used by the process-level tests). */
  port: number;
  /** SQLite database file; its directory is created if missing. */
  dbPath: string;
  minAgent: string;
  minMobile: string;
  latestAgentVersion: string;
  macUrl: string;
  winUrl: string;
  /** Only the exact string "false" in RATE_LIMITS_ENABLED turns the limits off (local dev / E2E). */
  rateLimitsEnabled: boolean;
}

export class ConfigError extends Error {
  override name = "ConfigError";
}

export const REQUIRED_VARIABLES = ["MIN_AGENT", "MIN_MOBILE", "LATEST_AGENT_VERSION", "MAC_URL", "WIN_URL"] as const;

export const DEFAULT_PORT = 8080;
export const DEFAULT_HOST = "0.0.0.0";
export const DEFAULT_DB_PATH = "/data/relay.db";

export function loadConfig(env: Readonly<Record<string, string | undefined>>): Config {
  const value = (name: string): string | undefined => {
    const raw = env[name]?.trim();
    return raw === undefined || raw === "" ? undefined : raw;
  };
  const missing = REQUIRED_VARIABLES.filter((name) => value(name) === undefined);
  if (missing.length > 0) {
    throw new ConfigError(`missing required environment variable${missing.length > 1 ? "s" : ""}: ${missing.join(", ")}`);
  }
  const portText = value("PORT");
  const port = portText === undefined ? DEFAULT_PORT : Number(portText);
  if (!Number.isInteger(port) || port < 0 || port > 65535) {
    throw new ConfigError(`PORT must be an integer from 0 to 65535, got "${portText}"`);
  }
  return {
    host: value("HOST") ?? DEFAULT_HOST,
    port,
    dbPath: value("DB_PATH") ?? DEFAULT_DB_PATH,
    minAgent: value("MIN_AGENT")!,
    minMobile: value("MIN_MOBILE")!,
    latestAgentVersion: value("LATEST_AGENT_VERSION")!,
    macUrl: value("MAC_URL")!,
    winUrl: value("WIN_URL")!,
    rateLimitsEnabled: env.RATE_LIMITS_ENABLED !== "false",
  };
}
```

Create `relay/src/db/db.ts`:

```ts
import { existsSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import Database from "better-sqlite3";

/** Values a statement parameter may take. ArrayBuffers (SHA-256 token hashes) are stored as BLOBs. */
export type SqlValue = string | number | bigint | null | Uint8Array | ArrayBuffer;

export interface RunResult {
  /** Rows inserted, updated or deleted by the statement. */
  changes: number;
}

export interface DbOptions {
  /** How long a statement waits for another connection's lock before failing with SQLITE_BUSY. */
  busyTimeoutMs?: number;
  /** Refuse to create the file (admin scripts must open the relay's existing database). */
  fileMustExist?: boolean;
}

/** Default `busy_timeout` (spec §4.2). */
export const BUSY_TIMEOUT_MS = 5000;

/**
 * The relay's only database access path: a thin, synchronous wrapper over one better-sqlite3
 * connection with WAL, foreign keys and a busy timeout. Prepared statements are cached per SQL
 * string. Replaces D1: `batch()` becomes `transaction()`, `first()` becomes `get()`.
 */
export class Db {
  private readonly statements = new Map<string, Database.Statement>();

  private constructor(private readonly sqlite: Database.Database) {}

  /** Opens (creating it and its directory unless `fileMustExist`) the database at `path`. */
  static open(path: string, options: DbOptions = {}): Db {
    if (options.fileMustExist) {
      if (!existsSync(path)) throw Object.assign(new Error("database file does not exist"), { code: "ENOENT" });
    } else {
      mkdirSync(dirname(path), { recursive: true });
    }
    const sqlite = new Database(path, {
      fileMustExist: options.fileMustExist ?? false,
      timeout: options.busyTimeoutMs ?? BUSY_TIMEOUT_MS,
    });
    try {
      sqlite.pragma("journal_mode = WAL");
      sqlite.pragma("foreign_keys = ON");
      sqlite.pragma(`busy_timeout = ${options.busyTimeoutMs ?? BUSY_TIMEOUT_MS}`);
    } catch (err) {
      sqlite.close();
      throw err;
    }
    return new Db(sqlite);
  }

  /** One row, or undefined when the query returns none. */
  get<T>(sql: string, ...params: SqlValue[]): T | undefined {
    return this.statement(sql).get(...params.map(toSqlite)) as T | undefined;
  }

  all<T>(sql: string, ...params: SqlValue[]): T[] {
    return this.statement(sql).all(...params.map(toSqlite)) as T[];
  }

  run(sql: string, ...params: SqlValue[]): RunResult {
    return { changes: this.statement(sql).run(...params.map(toSqlite)).changes };
  }

  /** Runs one or more statements without parameters (migrations). */
  exec(sql: string): void {
    this.sqlite.exec(sql);
  }

  /**
   * Runs `fn` in one transaction (BEGIN IMMEDIATE): committed if it returns, rolled back if it
   * throws. `fn` must be synchronous; nothing else can run on this connection in the meantime.
   */
  transaction<T>(fn: () => T): T {
    return this.sqlite.transaction(fn).immediate();
  }

  get isOpen(): boolean {
    return this.sqlite.open;
  }

  close(): void {
    if (this.sqlite.open) this.sqlite.close();
    this.statements.clear();
  }

  private statement(sql: string): Database.Statement {
    let statement = this.statements.get(sql);
    if (statement === undefined) {
      statement = this.sqlite.prepare(sql);
      this.statements.set(sql, statement);
    }
    return statement;
  }
}

function toSqlite(value: SqlValue): string | number | bigint | null | Buffer {
  if (value instanceof ArrayBuffer) return Buffer.from(value);
  if (value instanceof Uint8Array) return Buffer.from(value.buffer, value.byteOffset, value.byteLength);
  return value;
}
```

Create `relay/src/db/migrate.ts`:

```ts
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type { Db } from "./db.js";

/** `relay/migrations/`: `src/db/` and `dist/db/` are both two levels below the package root. */
export const MIGRATIONS_DIR = fileURLToPath(new URL("../../migrations/", import.meta.url));

/**
 * Applies every `*.sql` file of `dir` that is not yet recorded in `schema_migrations`, in file-name
 * order, each in its own transaction together with its bookkeeping row (spec §4.2). Returns the
 * names applied by this call. There are no down-migrations: fix a mistake with a new file.
 */
export function migrate(db: Db, dir: string = MIGRATIONS_DIR): string[] {
  db.exec("CREATE TABLE IF NOT EXISTS schema_migrations (name TEXT PRIMARY KEY, applied_at INTEGER NOT NULL)");
  const done = new Set(db.all<{ name: string }>("SELECT name FROM schema_migrations").map((row) => row.name));
  const pending = readdirSync(dir)
    .filter((name) => name.endsWith(".sql") && !done.has(name))
    .sort();
  for (const name of pending) {
    const sql = readFileSync(join(dir, name), "utf8");
    db.transaction(() => {
      db.exec(sql);
      db.run("INSERT INTO schema_migrations (name, applied_at) VALUES (?, ?)", name, Date.now());
    });
  }
  return pending;
}
```

Create `relay/migrations/0002_hub_state.sql` (`0001_init.sql` stays byte for byte as it is):

```sql
-- Durable pairing_removed tombstones of the in-process UserHub (VPS spec §4.2). Same columns as the
-- Durable Object's former `pending_pairing_removed` table plus `user_id`: at most one row per
-- (agent, mobile), holding the newest removed pairing_id.
CREATE TABLE pending_pairing_removed (
  user_id    TEXT NOT NULL,
  agent_id   TEXT NOT NULL,
  mobile_id  TEXT NOT NULL,
  pairing_id TEXT NOT NULL,
  UNIQUE (agent_id, mobile_id)
);

CREATE INDEX pending_pairing_removed_user_agent ON pending_pairing_removed (user_id, agent_id);
```

Replace `relay/src/log.ts`:

```ts
// Metadata-only structured logging (spec §10.5): time, device_id, error codes, frame sizes.
// NEVER pass payloads, tokens, passwords, e-mail or IP addresses to this function.
export type LogValue = string | number | boolean | null;

export function logMeta(event: string, fields: Readonly<Record<string, LogValue>> = {}): void {
  console.log(JSON.stringify({ ts: Date.now(), event, ...fields }));
}

/**
 * A loggable kind for an unknown error: an upper-case code such as `SQLITE_BUSY` when it has one,
 * else the error's class name. Never the message, which may quote SQL or user input.
 */
export function errorKind(err: unknown): string {
  if (typeof err === "object" && err !== null) {
    const code = (err as { code?: unknown }).code;
    if (typeof code === "string" && /^[A-Z][A-Z0-9_]*$/.test(code)) return code;
    const name = (err as { name?: unknown }).name;
    if (typeof name === "string" && /^[A-Za-z][A-Za-z0-9_]*$/.test(name)) return name;
  }
  return "unknown";
}
```

Replace `relay/src/app.ts` (routes are mounted again in Task 4):

```ts
import type { IncomingMessage } from "node:http";
import { Hono } from "hono";
import type { Config } from "./config.js";
import type { Db } from "./db/db.js";
import { ApiError, errorBody, Errors } from "./http/errors.js";
import { errorKind, logMeta } from "./log.js";

export interface AppDeps {
  config: Config;
  db: Db;
  /** Unix milliseconds; injectable for token-expiry tests. */
  now?: () => number;
}

export interface AppVariables {
  config: Config;
  db: Db;
  now: () => number;
}

/** What @hono/node-server passes as `c.env`; `incoming.socket.remoteAddress` is the TCP peer. */
export interface AppBindings {
  incoming: IncomingMessage;
}

export type AppEnv = { Bindings: AppBindings; Variables: AppVariables };

export function createApp(deps: AppDeps): Hono<AppEnv> {
  const app = new Hono<AppEnv>();

  app.use("*", async (c, next) => {
    c.set("config", deps.config);
    c.set("db", deps.db);
    c.set("now", deps.now ?? Date.now);
    await next();
  });

  app.get("/v1/version", (c) => {
    const config = c.get("config");
    return c.json({
      min_agent: config.minAgent,
      min_mobile: config.minMobile,
      latest_agent: { version: config.latestAgentVersion, mac_url: config.macUrl, win_url: config.winUrl },
    });
  });

  app.notFound((c) => {
    const e = Errors.notFound();
    return c.json(errorBody(e.code, e.message), e.status);
  });

  app.onError((err, c) => {
    if (err instanceof ApiError) return c.json(errorBody(err.code, err.message), err.status);
    logMeta("unhandled_error", { method: c.req.method, path: new URL(c.req.url).pathname, error: errorKind(err) });
    return c.json(errorBody("internal_error", "Internal error"), 500);
  });

  return app;
}
```

Create `relay/src/relay.ts` (HTTP only in this task; Task 4 adds the WebSocket upgrade, Task 5 the graceful shutdown):

```ts
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { createAdaptorServer } from "@hono/node-server";
import { createApp, type AppDeps } from "./app.js";

export interface ListenOptions {
  host: string;
  /** 0 picks a free port (tests). */
  port: number;
}

export interface RunningRelay {
  readonly server: Server;
  readonly port: number;
  /** `http://<host>:<port>` */
  readonly url: string;
}

/** Serves the app on `listen` (HTTP only for now; the WebSocket upgrade is added with the hub). */
export async function startRelay(deps: AppDeps, listen: ListenOptions): Promise<RunningRelay> {
  const app = createApp(deps);
  const server = createAdaptorServer({ fetch: app.fetch }) as Server;
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(listen.port, listen.host, () => {
      server.off("error", reject);
      resolve();
    });
  });
  const { port } = server.address() as AddressInfo;
  const host = listen.host.includes(":") ? `[${listen.host}]` : listen.host;
  return { server, port, url: `http://${host}:${port}` };
}
```

- [ ] **Step 8: Run the tests and the type check**

Run: `npx vitest run test/config.test.ts test/db.test.ts test/app.test.ts`
Expected: PASS (3 files).

Run: `npm run typecheck && npm test`
Expected: `tsc` prints nothing; Vitest `Test Files  5 passed (5)`, `Tests  66 passed (66)` (app, config, db, protocol, policy).

- [ ] **Step 9: Commit**

```bash
git add -A relay
git commit -m "feat(relay): Node test harness, config, SQLite Db and migrations; /v1/version on Node"
```

### Task 2: Passwords, rate limits and client IP on Node

argon2id moves from the WASM build to `@node-rs/argon2` (same parameters, same PHC strings — the old known-answer vectors still match) with a cap of 4 concurrent hashes; the Workers rate limiting binding becomes an in-memory sliding window; the client IP comes from `X-Real-IP` only when the TCP peer is a trusted proxy address.

The old fail-open tests for a *throwing rate-limit binding* are not ported: an in-memory limiter cannot have an outage. The production-wiring behaviour they protected is re-tested in Task 4 (`auth.test.ts` "production rate limits…").

**Files:**
- Create: `relay/src/auth/client-ip.ts`, `relay/test/limiter.test.ts`
- Modify: `relay/src/auth/password.ts` (rewrite), `relay/src/auth/rate-limit.ts` (rewrite), `relay/test/password.test.ts` (rewrite), `relay/package.json`, `relay/package-lock.json`, `relay/tsconfig.json`, `relay/vitest.config.ts`
- Delete: `relay/src/auth/argon2.ts`, `relay/src/types/wasm.d.ts`

**Interfaces:**
- Consumes: `Config` (Task 1; only `rateLimitsEnabled`).
- Produces:
  - `src/auth/password.ts`: `ARGON2_MEMORY_KIB = 19456`, `ARGON2_ITERATIONS = 2`, `ARGON2_PARALLELISM = 1`, `ARGON2_HASH_BYTES = 32`, `MAX_CONCURRENT_HASHES = 4`; `interface PasswordHasher { hash(password: string): Promise<string>; verify(password: string, phc: string): Promise<boolean> }` (`verify` never throws for a malformed PHC); `interface Argon2Backend { hash(password: Uint8Array, salt?: Uint8Array): Promise<string>; verify(phc: string, password: Uint8Array): Promise<boolean> }`; `nodeArgon2: Argon2Backend`; `passwordBytes(password: string): Uint8Array` (NFC, UTF-8); `class Semaphore { constructor(limit: number); run<T>(task: () => Promise<T>): Promise<T>; readonly running: number; readonly queued: number }`; `createPasswordHasher(backend?: Argon2Backend, maxConcurrent?: number): PasswordHasher`; `passwords: PasswordHasher` (process-wide); `hashPassword(password): Promise<string>`; `verifyPassword(password, phc): Promise<boolean>`.
  - `src/auth/rate-limit.ts`: `interface RateLimiter { limit(key: string): Promise<boolean> }`, `interface RateLimiters { loginIp; loginEmail; registerIp }`, `RATE_WINDOW_MS = 60_000`, `LOGIN_PER_IP = 10`, `LOGIN_PER_EMAIL = 5`, `REGISTER_PER_IP = 3`, `interface SlidingWindowOptions { limit: number; windowMs?: number; now?: () => number }`, `class SlidingWindowLimiter implements RateLimiter { readonly size: number; limit(key); sweep(now?) }`, `createRateLimiters(config: Pick<Config, "rateLimitsEnabled">, now?: () => number): RateLimiters`.
  - `src/auth/client-ip.ts`: `clientIp(realIpHeader: string | undefined, remoteAddress: string | undefined): string`.

- [ ] **Step 1: Swap the argon2 dependency and remove the WASM plumbing**

```bash
npm uninstall @phi-ag/argon2
npm install --save-exact @node-rs/argon2@2.2.1
git rm -q src/auth/argon2.ts src/types/wasm.d.ts
```

- [ ] **Step 2: Write the failing tests**

Replace `relay/test/password.test.ts`:

```ts
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
```

Create `relay/test/limiter.test.ts` (the `clientIp` cases pin Review Focus 4):

```ts
import { describe, expect, it } from "vitest";
import { clientIp } from "../src/auth/client-ip.js";
import {
  createRateLimiters, LOGIN_PER_EMAIL, LOGIN_PER_IP, RATE_WINDOW_MS, REGISTER_PER_IP, SlidingWindowLimiter,
} from "../src/auth/rate-limit.js";

function clock(start = 1_800_000_000_000) {
  let now = start;
  return { now: () => now, advance: (ms: number) => (now += ms) };
}

async function allowed(limiter: SlidingWindowLimiter, key: string, times: number): Promise<boolean[]> {
  const results: boolean[] = [];
  for (let i = 0; i < times; i++) results.push(await limiter.limit(key));
  return results;
}

describe("SlidingWindowLimiter", () => {
  it("allows `limit` calls per key inside the window, then refuses", async () => {
    const t = clock();
    const limiter = new SlidingWindowLimiter({ limit: 3, now: t.now });
    expect(await allowed(limiter, "203.0.113.7", 4)).toEqual([true, true, true, false]);
    expect(await limiter.limit("198.51.100.1")).toBe(true); // other keys are independent
  });

  it("slides: a slot frees up exactly one window after the call that used it", async () => {
    const t = clock();
    const limiter = new SlidingWindowLimiter({ limit: 2, now: t.now });
    await limiter.limit("k"); // t = 0
    t.advance(30_000);
    await limiter.limit("k"); // t = 30 s
    expect(await limiter.limit("k")).toBe(false);
    t.advance(29_999); // 59.999 s: the first call is still inside the window
    expect(await limiter.limit("k")).toBe(false);
    t.advance(1); // 60 s: the first call has left the window
    expect(await limiter.limit("k")).toBe(true);
    expect(await limiter.limit("k")).toBe(false);
  });

  it("does not count refused calls, so hammering does not extend the lockout", async () => {
    const t = clock();
    const limiter = new SlidingWindowLimiter({ limit: 1, now: t.now });
    expect(await limiter.limit("k")).toBe(true);
    for (let i = 0; i < 50; i++) {
      t.advance(1000);
      expect(await limiter.limit("k")).toBe(false);
    }
    t.advance(RATE_WINDOW_MS - 50_000);
    expect(await limiter.limit("k")).toBe(true);
  });

  it("sweeps keys whose calls all left the window, at most once per window", async () => {
    const t = clock();
    const limiter = new SlidingWindowLimiter({ limit: 5, now: t.now });
    for (let i = 0; i < 100; i++) await limiter.limit(`attacker-${i}@example.com`);
    expect(limiter.size).toBe(100);
    t.advance(RATE_WINDOW_MS);
    await limiter.limit("next@example.com"); // triggers the sweep
    expect(limiter.size).toBe(1);
  });
});

describe("createRateLimiters (production wiring)", () => {
  it("enforces login 10/IP, login 5/email and register 3/IP", async () => {
    expect([LOGIN_PER_IP, LOGIN_PER_EMAIL, REGISTER_PER_IP, RATE_WINDOW_MS]).toEqual([10, 5, 3, 60_000]);
    const t = clock();
    const limiters = createRateLimiters({ rateLimitsEnabled: true }, t.now);
    const count = async (limiter: { limit(k: string): Promise<boolean> }) => {
      let n = 0;
      while (n < 100 && (await limiter.limit("same-key"))) n++;
      return n;
    };
    expect(await count(limiters.loginIp)).toBe(10);
    expect(await count(limiters.loginEmail)).toBe(5);
    expect(await count(limiters.registerIp)).toBe(3);
  });

  it("RATE_LIMITS_ENABLED=false turns every limiter off", async () => {
    const limiters = createRateLimiters({ rateLimitsEnabled: false });
    for (let i = 0; i < 20; i++) {
      expect(await limiters.loginIp.limit("k")).toBe(true);
      expect(await limiters.loginEmail.limit("k")).toBe(true);
      expect(await limiters.registerIp.limit("k")).toBe(true);
    }
  });
});

describe("clientIp", () => {
  it("uses X-Real-IP when the TCP peer is nginx-proxy on a private or loopback address", () => {
    for (const peer of ["172.18.0.3", "::ffff:172.18.0.3", "10.1.2.3", "192.168.1.9", "127.0.0.1", "::1", "fd00::5"]) {
      expect(clientIp("203.0.113.7", peer)).toBe("203.0.113.7");
    }
    expect(clientIp(" 2001:db8::1 ", "172.18.0.3")).toBe("2001:db8::1");
  });

  it("ignores X-Real-IP from a public peer: a client that bypasses the proxy cannot pick its key", () => {
    expect(clientIp("198.51.100.99", "203.0.113.50")).toBe("203.0.113.50");
    expect(clientIp("198.51.100.99", "2001:db8::77")).toBe("2001:db8::77");
  });

  it("falls back to the peer address when X-Real-IP is missing or not an IP address", () => {
    expect(clientIp(undefined, "127.0.0.1")).toBe("127.0.0.1");
    expect(clientIp("", "::ffff:127.0.0.1")).toBe("127.0.0.1");
    expect(clientIp("not-an-ip", "172.18.0.3")).toBe("172.18.0.3");
    expect(clientIp("203.0.113.7, 10.0.0.1", "172.18.0.3")).toBe("172.18.0.3");
    expect(clientIp(undefined, undefined)).toBe("unknown");
  });
});
```

In `relay/tsconfig.json` delete these five lines from `exclude`:

```jsonc
    "src/auth/argon2.ts",
    "src/auth/password.ts",
    "src/auth/rate-limit.ts",
    "src/types",
    "test/password.test.ts",
```

and in `relay/vitest.config.ts` delete this line from `NOT_YET_PORTED`:

```ts
  "test/password.test.ts",
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `npx vitest run test/password.test.ts test/limiter.test.ts`
Expected: FAIL — `Error: Cannot find module '../src/auth/client-ip.js' imported from …/test/limiter.test.ts`, and `password.test.ts` fails to load the old `src/auth/password.ts` (its `@phi-ag/argon2/argon2.wasm` import no longer resolves).

- [ ] **Step 4: Implement**

Replace `relay/src/auth/password.ts`:

```ts
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
```

Replace `relay/src/auth/rate-limit.ts`:

```ts
import type { Config } from "../config.js";

/** Returns true when the call is allowed, false when the key is over its limit. */
export interface RateLimiter {
  limit(key: string): Promise<boolean>;
}

export interface RateLimiters {
  loginIp: RateLimiter;
  loginEmail: RateLimiter;
  registerIp: RateLimiter;
}

/** Spec §5.2: 60-second window; login 10/IP and 5/email, register 3/IP. */
export const RATE_WINDOW_MS = 60_000;
export const LOGIN_PER_IP = 10;
export const LOGIN_PER_EMAIL = 5;
export const REGISTER_PER_IP = 3;

export interface SlidingWindowOptions {
  /** Allowed calls per key within any window of `windowMs`. */
  limit: number;
  windowMs?: number;
  now?: () => number;
}

/**
 * In-memory sliding-window limiter (replaces the Workers rate limiting binding). Each key keeps the
 * timestamps of its allowed calls inside the window (at most `limit` of them); a refused call is
 * not recorded, so hammering does not extend a lockout. Keys whose newest call left the window are
 * swept at most once per window, on the next call, so memory stays bounded by recent traffic.
 * Keys are IP addresses or e-mail addresses and are never logged.
 */
export class SlidingWindowLimiter implements RateLimiter {
  private readonly hits = new Map<string, number[]>();
  private readonly windowMs: number;
  private readonly now: () => number;
  private lastSweep: number;

  constructor(private readonly options: SlidingWindowOptions) {
    this.windowMs = options.windowMs ?? RATE_WINDOW_MS;
    this.now = options.now ?? Date.now;
    this.lastSweep = this.now();
  }

  /** Number of keys currently tracked (for tests and memory checks). */
  get size(): number {
    return this.hits.size;
  }

  async limit(key: string): Promise<boolean> {
    const now = this.now();
    if (now - this.lastSweep >= this.windowMs) this.sweep(now);
    const since = now - this.windowMs;
    const recent = (this.hits.get(key) ?? []).filter((t) => t > since);
    if (recent.length >= this.options.limit) {
      this.hits.set(key, recent);
      return false;
    }
    recent.push(now);
    this.hits.set(key, recent);
    return true;
  }

  /** Drops every key with no call inside the window. */
  sweep(now: number = this.now()): void {
    this.lastSweep = now;
    const since = now - this.windowMs;
    for (const [key, times] of this.hits) {
      if (times.length === 0 || times[times.length - 1]! <= since) this.hits.delete(key);
    }
  }
}

const allowAll: RateLimiter = { limit: async () => true };

/** Production wiring: one limiter set per process. RATE_LIMITS_ENABLED=false turns all three off. */
export function createRateLimiters(config: Pick<Config, "rateLimitsEnabled">, now: () => number = Date.now): RateLimiters {
  if (!config.rateLimitsEnabled) return { loginIp: allowAll, loginEmail: allowAll, registerIp: allowAll };
  return {
    loginIp: new SlidingWindowLimiter({ limit: LOGIN_PER_IP, now }),
    loginEmail: new SlidingWindowLimiter({ limit: LOGIN_PER_EMAIL, now }),
    registerIp: new SlidingWindowLimiter({ limit: REGISTER_PER_IP, now }),
  };
}
```

Create `relay/src/auth/client-ip.ts`:

```ts
import { BlockList, isIP } from "node:net";

/**
 * Peers allowed to tell us the client address in `X-Real-IP`: loopback and private networks, which
 * is where nginx-proxy connects from (the relay container publishes no port). A request that
 * reaches the relay from anywhere else cannot choose its own rate-limit key (Review Focus 4).
 */
const TRUSTED_PEERS = new BlockList();
TRUSTED_PEERS.addSubnet("127.0.0.0", 8, "ipv4");
TRUSTED_PEERS.addSubnet("10.0.0.0", 8, "ipv4");
TRUSTED_PEERS.addSubnet("172.16.0.0", 12, "ipv4");
TRUSTED_PEERS.addSubnet("192.168.0.0", 16, "ipv4");
TRUSTED_PEERS.addSubnet("100.64.0.0", 10, "ipv4");
TRUSTED_PEERS.addAddress("::1", "ipv6");
TRUSTED_PEERS.addSubnet("fc00::", 7, "ipv6");

/** `::ffff:10.0.0.5` → `10.0.0.5`; anything else unchanged. */
function unmapped(address: string): string {
  const match = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/i.exec(address);
  return match ? match[1]! : address;
}

function isTrustedPeer(address: string): boolean {
  const family = isIP(address);
  return family !== 0 && TRUSTED_PEERS.check(address, family === 4 ? "ipv4" : "ipv6");
}

/**
 * The client address used as the rate-limit key (spec §4.2): `X-Real-IP` set by nginx-proxy when
 * the TCP peer is a trusted proxy and the header holds a valid IP, otherwise the peer address
 * itself. Used only in memory by the limiters; never logged.
 */
export function clientIp(realIpHeader: string | undefined, remoteAddress: string | undefined): string {
  const peer = remoteAddress === undefined ? undefined : unmapped(remoteAddress);
  if (peer !== undefined && isTrustedPeer(peer)) {
    const forwarded = realIpHeader?.trim();
    if (forwarded !== undefined && isIP(forwarded) !== 0) return unmapped(forwarded);
  }
  return peer ?? "unknown";
}
```

- [ ] **Step 5: Run the tests and the type check**

Run: `npx vitest run test/password.test.ts test/limiter.test.ts`
Expected: PASS (11 + 9 tests).

Run: `npm run typecheck && npm test`
Expected: `Test Files  7 passed (7)`, `Tests  86 passed (86)`.

- [ ] **Step 6: Commit**

```bash
git add -A relay
git commit -m "feat(relay): argon2id via @node-rs/argon2 (4 at once), in-memory sliding-window limits, X-Real-IP from trusted proxies"
```

### Task 3: In-process hub — `HubRegistry`, `UserHub` and its serial queue

The Durable Object becomes plain in-process state: at most one `HubState` per account with a Promise-chain queue through which every socket event, frame and REST call runs in arrival order; `UserHub` (what `registry.forUser(userId)` returns) is a stateless handle that always reaches the live state, so a handle kept across an `await` can never talk to a state the registry already dropped. Tombstones move to the SQLite table from Task 1. Frame budgets (500/s per device) live in the registry so neither reconnecting nor the hub being dropped refills them early. This task tests the hub directly with in-memory fake sockets; Task 4 connects it to real WebSockets.

**Files:**
- Create: `relay/src/hub/frame-budgets.ts`, `relay/src/hub/registry.ts`, `relay/test/user-hub.test.ts`
- Modify: `relay/src/hub/user-hub.ts` (rewrite), `relay/test/helpers.ts` (append `FakeSocket`), `relay/tsconfig.json`
- Unchanged: `relay/src/hub/token-bucket.ts`

**Interfaces:**
- Consumes: `Db` (Task 1), `errorKind`/`logMeta` (Task 1), `TokenBucket`, `FRAMES_PER_SECOND` (`src/hub/token-bucket.ts`), frames/`CloseCode`/`RelayErrorCode` (`src/protocol/frames.ts`), `DeviceKind` (`src/auth/device.ts`).
- Produces:
  - `src/hub/user-hub.ts`: `interface HubSocket { readonly readyState: number; send(data: Uint8Array | string): void; close(code: number, reason: string): void; terminate(): void }` (a `ws` WebSocket satisfies it), `SOCKET_OPEN = 1`, `GOING_AWAY = 1001`, `interface ConnectionMeta { deviceId: string; kind: DeviceKind; connId: string }`, `interface Attachment { device_id; kind; conn_id; closing: boolean }`, `interface HubHost`, `class HubState` (internal), and `class UserHub` with: `connect(socket, meta): Promise<void>` (rejects, leaving the socket out, if the tombstones cannot be read), `receive(socket, data: ArrayBuffer | Uint8Array | string): void`, `disconnected(socket): void`, `online(): Promise<string[]>`, `disconnect(deviceIds: string[], code: CloseCode): Promise<void>`, `disconnectAllExcept(exceptDeviceId: string, code: CloseCode): Promise<void>`, `notifyPairingRemoved(agentId, mobileId, pairingId): Promise<void>`, `admitPairing(agentId, mobileId, pairingId): Promise<boolean>`, `purgeAgent(agentId): Promise<number>`, `purgeAll(): Promise<number>`, `closeAccount(): Promise<void>`, `closeConnection(connId: string, code: CloseCode): Promise<void>`, `idle(): Promise<void>`, `readonly socketCount: number`.
  - `src/hub/registry.ts`: `interface HubRegistryOptions { db: Db; now?: () => number }`, `class HubRegistry { constructor(options); forUser(userId: string): UserHub; readonly size: number; readonly shuttingDown: boolean; whenEmpty(): Promise<void>; goAway(): Promise<void>; terminateAll(): void; readonly db; readonly now; readonly budgets }`.
  - `src/hub/frame-budgets.ts`: `class FrameBudgets { constructor(now: () => number); take(deviceId: string): boolean; sweep(now?: number): void; readonly size: number }`.
  - `test/helpers.ts`: `class FakeSocket implements HubSocket { readyState; sent; closedWith: { code; reason } | null; terminated; take(): string[] }`.
  - Rule for Task 4 and later: routes call `c.get("hubs").forUser(userId).<method>()`; failures of a REST call reject that call only (and are logged as `hub_op_failed` with the op name and error kind).

- [ ] **Step 1: Write the failing tests**

In `relay/test/helpers.ts`, add this import after the `import { migrate } from "../src/db/migrate.js";` line:

```ts
import type { HubSocket } from "../src/hub/user-hub.js";
```

and append at the end of the file:

```ts
/** In-memory stand-in for a `ws` socket: records what the hub sends and how it closes it. */
export class FakeSocket implements HubSocket {
  readyState = 1;
  readonly sent: (Uint8Array | string)[] = [];
  closedWith: { code: number; reason: string } | null = null;
  terminated = false;

  send(data: Uint8Array | string): void {
    if (this.readyState !== 1) throw new Error("socket is not open");
    this.sent.push(data);
  }

  close(code: number, reason: string): void {
    if (this.readyState !== 1) return;
    this.closedWith = { code, reason };
    this.readyState = 2;
  }

  terminate(): void {
    this.terminated = true;
    this.readyState = 3;
  }

  /** Hex of every binary frame received so far, then forgets them. */
  take(): string[] {
    return this.sent.splice(0).map((m) => (typeof m === "string" ? `text:${m}` : hex(m)));
  }
}
```

Create `relay/test/user-hub.test.ts` (the "serial queue" test pins Review Focus 3 at the hub level):

```ts
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";
import { Db } from "../src/db/db.js";
import { migrate } from "../src/db/migrate.js";
import { HubRegistry } from "../src/hub/registry.js";
import { FRAMES_PER_SECOND } from "../src/hub/token-bucket.js";
import { GOING_AWAY, type UserHub } from "../src/hub/user-hub.js";
import {
  CloseCode, encodeData, encodeError, encodePresence, MAX_FRAME_BYTES, pairingRemovedEvent, RelayErrorCode,
} from "../src/protocol/frames.js";
import { db, FakeSocket, hex, newPairingId, tempDir } from "./helpers.js";

const CH = Uint8Array.from([9, 8, 7, 6, 5, 4, 3, 2]);

afterEach(() => {
  vi.restoreAllMocks();
});

/** The client (or the network) closed the socket: what the ws route reports to the hub. */
function clientCloses(hub: UserHub, socket: FakeSocket): void {
  socket.readyState = 3;
  hub.disconnected(socket);
}

/** A user row and one device row, written directly (no argon2 needed at this level). */
function seedUser(database: Db = db()): { userId: string; device: (kind: "agent" | "mobile") => string } {
  const userId = crypto.randomUUID();
  database.run("INSERT INTO users VALUES (?, ?, 'x', 1, 1)", userId, `${userId}@example.com`);
  return {
    userId,
    device(kind) {
      const id = crypto.randomUUID();
      database.run(
        "INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at) VALUES (?, ?, ?, 'n', ?, ?, 1)",
        id, userId, kind, kind === "agent" ? "macos" : "ios", crypto.getRandomValues(new Uint8Array(32)),
      );
      return id;
    },
  };
}

async function joinHub(hub: UserHub, socket: FakeSocket, deviceId: string, kind: "agent" | "mobile" = "mobile", connId = crypto.randomUUID()) {
  await hub.connect(socket, { deviceId, kind, connId });
  return connId;
}

function setup(now?: () => number) {
  const registry = new HubRegistry({ db: db(), now });
  const user = seedUser();
  const agentId = user.device("agent");
  const mobileId = user.device("mobile");
  return { registry, hub: registry.forUser(user.userId), userId: user.userId, agentId, mobileId, user };
}

describe("presence and routing", () => {
  it("sends a presence snapshot to the newcomer and announces it to the others", async () => {
    const { hub, agentId, mobileId } = setup();
    const a = new FakeSocket();
    const m = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    expect(a.take()).toEqual([]);
    await joinHub(hub, m, mobileId);
    expect(m.take()).toEqual([hex(encodePresence(agentId, true))]);
    expect(a.take()).toEqual([hex(encodePresence(mobileId, true))]);
    expect((await hub.online()).sort()).toEqual([agentId, mobileId].sort());
  });

  it("routes DATA to the peer with the peer field rewritten to the sender, and answers peer_offline otherwise", async () => {
    const { hub, agentId, mobileId } = setup();
    const a = new FakeSocket();
    const m = new FakeSocket();
    await joinHub(hub, m, mobileId);
    hub.receive(m, encodeData(agentId, CH, Uint8Array.of(4)).buffer as ArrayBuffer);
    await hub.idle();
    expect(m.take()).toEqual([hex(encodeError(RelayErrorCode.peerOffline, agentId, CH))]);

    await joinHub(hub, a, agentId, "agent");
    a.take();
    m.take();
    hub.receive(m, encodeData(agentId, CH, Uint8Array.of(0xde, 0xad)));
    await hub.idle();
    expect(a.take()).toEqual([hex(encodeData(mobileId, CH, Uint8Array.of(0xde, 0xad)))]);
  });

  it("never routes to a device of another account", async () => {
    const registry = new HubRegistry({ db: db() });
    const alice = seedUser();
    const bob = seedUser();
    const aliceMobile = alice.device("mobile");
    const bobAgent = bob.device("agent");
    const attacker = new FakeSocket();
    const victim = new FakeSocket();
    await joinHub(registry.forUser(bob.userId), victim, bobAgent, "agent");
    await joinHub(registry.forUser(alice.userId), attacker, aliceMobile);
    expect(attacker.take()).toEqual([]); // Bob's agent is not in Alice's snapshot
    registry.forUser(alice.userId).receive(attacker, encodeData(bobAgent, CH, Uint8Array.of(4, 1)));
    await registry.forUser(alice.userId).idle();
    expect(attacker.take()).toEqual([hex(encodeError(RelayErrorCode.peerOffline, bobAgent, CH))]);
    expect(victim.take()).toEqual([]);
  });

  it("enforces the 64 KiB frame limit and answers malformed frames and stray text with bad_frame", async () => {
    const { hub, agentId, mobileId } = setup();
    const a = new FakeSocket();
    const m = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    await joinHub(hub, m, mobileId);
    a.take();
    m.take();
    hub.receive(m, encodeData(agentId, CH, new Uint8Array(MAX_FRAME_BYTES - 26)));
    hub.receive(m, encodeData(agentId, CH, new Uint8Array(MAX_FRAME_BYTES - 25)));
    hub.receive(m, new Uint8Array(10));
    hub.receive(m, "hello");
    await hub.idle();
    expect(a.sent.map((f) => (f as Uint8Array).length)).toEqual([65536]);
    expect(m.take()).toEqual([
      hex(encodeError(RelayErrorCode.frameTooLarge, agentId, CH)),
      hex(encodeError(RelayErrorCode.badFrame)),
      hex(encodeError(RelayErrorCode.badFrame)),
    ]);
    expect(m.closedWith).toBeNull();
  });

  it("replaces an older connection of the same device with 4001 without announcing it offline", async () => {
    const { hub, agentId, mobileId } = setup();
    const a = new FakeSocket();
    const m1 = new FakeSocket();
    const m2 = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    await joinHub(hub, m1, mobileId);
    a.take();
    await joinHub(hub, m2, mobileId);
    expect(m1.closedWith).toEqual({ code: 4001, reason: "replaced" });
    expect(m2.take()).toEqual([hex(encodePresence(agentId, true))]);
    clientCloses(hub, m1); // the replaced socket's close event arrives later
    await hub.idle();
    expect(a.take()).toEqual([hex(encodePresence(mobileId, true))]); // no offline
    hub.receive(a, encodeData(mobileId, CH, Uint8Array.of(4)));
    await hub.idle();
    expect(m2.sent.length).toBe(1);
  });

  it("announces offline and records last_seen_at when a device's socket closes", async () => {
    const { hub, agentId, mobileId } = setup(() => 1_900_000_000_000);
    const a = new FakeSocket();
    const m = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    await joinHub(hub, m, mobileId);
    a.take();
    clientCloses(hub, m);
    await hub.idle();
    expect(a.take()).toEqual([hex(encodePresence(mobileId, false))]);
    expect(db().get("SELECT last_seen_at FROM devices WHERE id = ?", mobileId)).toEqual({ last_seen_at: 1_900_000_000_000 });
  });

  it("tolerates a failing last_seen_at write, logging metadata only and still announcing offline", async () => {
    const { hub, agentId, mobileId } = setup();
    const a = new FakeSocket();
    const m = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    await joinHub(hub, m, mobileId);
    a.take();
    const lines: string[] = [];
    vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    });
    vi.spyOn(db(), "run").mockImplementation(() => {
      throw new Error("disk I/O error at /data/relay.db");
    });
    clientCloses(hub, m);
    await hub.idle();
    expect(a.take()).toEqual([hex(encodePresence(mobileId, false))]);
    expect(lines.join("\n")).toContain("last_seen_write_failed");
    expect(lines.join("\n")).toContain(mobileId);
    expect(lines.join("\n")).not.toContain("disk I/O");
  });
});

describe("frame budget (500 frames/s per device)", () => {
  it("sends ERROR rate_limited, closes with 4003 and announces offline once the budget is spent", async () => {
    const frozen = 1_900_000_000_000;
    const { hub, agentId, mobileId } = setup(() => frozen);
    const a = new FakeSocket();
    const m = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    await joinHub(hub, m, mobileId);
    a.take();
    m.take();
    for (let i = 0; i < 600; i++) hub.receive(m, encodeData(agentId, CH, Uint8Array.of(4)));
    await hub.idle();
    expect(a.sent.length).toBe(FRAMES_PER_SECOND + 1); // 500 frames + PRESENCE offline
    expect(hex(a.sent.at(-1) as Uint8Array)).toBe(hex(encodePresence(mobileId, false)));
    expect(m.take()).toEqual([hex(encodeError(RelayErrorCode.rateLimited))]);
    expect(m.closedWith).toEqual({ code: 4003, reason: "rate_limited" });
  });

  it("keeps a spent budget across a reconnect and across the hub being dropped and re-created", async () => {
    const frozen = 1_900_000_000_000;
    const { registry, userId, agentId, mobileId } = setup(() => frozen);
    const m = new FakeSocket();
    await joinHub(registry.forUser(userId), m, mobileId);
    for (let i = 0; i < 450; i++) registry.forUser(userId).receive(m, encodeData(agentId, CH, Uint8Array.of(4)));
    clientCloses(registry.forUser(userId), m);
    await registry.forUser(userId).idle();
    await registry.whenEmpty();
    expect(registry.size).toBe(0); // the hub is gone...

    const again = new FakeSocket();
    await joinHub(registry.forUser(userId), again, mobileId);
    for (let i = 0; i < 51; i++) registry.forUser(userId).receive(again, encodeData(agentId, CH, Uint8Array.of(4)));
    await registry.forUser(userId).idle();
    // ...but the device still had only 50 frames left: the 51st trips the limit.
    expect(again.closedWith).toEqual({ code: 4003, reason: "rate_limited" });
  });
});

describe("pairing_removed tombstones", () => {
  it("records the tombstone even for an online agent, sends the event live, and replays it on every connect", async () => {
    const { hub, agentId, mobileId } = setup();
    const a = new FakeSocket();
    const m = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    await joinHub(hub, m, mobileId);
    a.take();
    m.take();
    const id = newPairingId();
    await hub.notifyPairingRemoved(agentId, mobileId, id);
    const event = hex(pairingRemovedEvent(agentId, mobileId, id));
    expect(a.take()).toEqual([event]);
    expect(m.take()).toEqual([event]);

    for (let i = 0; i < 2; i++) {
      const again = new FakeSocket();
      await joinHub(hub, again, agentId, "agent");
      expect(again.take()).toEqual([hex(encodePresence(mobileId, true)), event]); // snapshot first
    }
  });

  it("keeps one tombstone per (agent, mobile) holding the newest id", async () => {
    const { hub, agentId, mobileId, user } = setup();
    const other = user.device("mobile");
    const [w, x, y, z] = [newPairingId(), newPairingId(), newPairingId(), newPairingId()];
    await hub.notifyPairingRemoved(agentId, mobileId, x);
    await hub.notifyPairingRemoved(agentId, other, z);
    await hub.notifyPairingRemoved(agentId, mobileId, y); // newer: overwrites x
    await hub.notifyPairingRemoved(agentId, mobileId, w); // older: y stays
    const a = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    expect(a.take().sort()).toEqual(
      [hex(pairingRemovedEvent(agentId, mobileId, y)), hex(pairingRemovedEvent(agentId, other, z))].sort(),
    );
  });

  it("admitPairing refuses ids not newer than the tombstone (keeping it) and clears it for a newer id", async () => {
    const { hub } = setup();
    const agentId = crypto.randomUUID();
    const mobileId = crypto.randomUUID();
    const [w, x, y] = [newPairingId(), newPairingId(), newPairingId()];
    expect(await hub.admitPairing(agentId, mobileId, x)).toBe(true);
    await hub.notifyPairingRemoved(agentId, mobileId, x);
    expect(await hub.admitPairing(agentId, mobileId, x)).toBe(false);
    expect(await hub.admitPairing(agentId, mobileId, w)).toBe(false);
    expect(await hub.admitPairing(crypto.randomUUID(), mobileId, w)).toBe(true); // other agent: untouched
    expect(await hub.admitPairing(agentId, mobileId, x)).toBe(false);
    expect(await hub.admitPairing(agentId, mobileId, y)).toBe(true); // newer: clears x's tombstone
    expect(await hub.admitPairing(agentId, mobileId, w)).toBe(true);
    expect(await hub.purgeAll()).toBe(0);
  });

  it("purgeAgent and purgeAll remove only this account's rows and report how many", async () => {
    const registry = new HubRegistry({ db: db() });
    const [alice, bob] = [seedUser(), seedUser()];
    const aliceHub = registry.forUser(alice.userId);
    const bobHub = registry.forUser(bob.userId);
    const [a1, a2, b1] = [crypto.randomUUID(), crypto.randomUUID(), crypto.randomUUID()];
    await aliceHub.notifyPairingRemoved(a1, crypto.randomUUID(), newPairingId());
    await aliceHub.notifyPairingRemoved(a1, crypto.randomUUID(), newPairingId());
    await aliceHub.notifyPairingRemoved(a2, crypto.randomUUID(), newPairingId());
    await bobHub.notifyPairingRemoved(b1, crypto.randomUUID(), newPairingId());
    expect(await aliceHub.purgeAgent(a1)).toBe(2);
    expect(await aliceHub.purgeAgent(a1)).toBe(0);
    expect(await bobHub.purgeAgent(a2)).toBe(0); // another account's agent id
    expect(await aliceHub.purgeAll()).toBe(1);
    expect(await bobHub.purgeAll()).toBe(1);
  });

  it("survives a relay restart: a new registry over the reopened database still replays it", async () => {
    const path = join(tempDir(), "restart.db");
    const first = Db.open(path);
    migrate(first);
    const user = seedUser(first);
    const agentId = user.device("agent");
    const mobileId = crypto.randomUUID();
    const id = newPairingId();
    await new HubRegistry({ db: first }).forUser(user.userId).notifyPairingRemoved(agentId, mobileId, id);
    first.close();

    const second = Db.open(path);
    try {
      migrate(second);
      const a = new FakeSocket();
      await new HubRegistry({ db: second }).forUser(user.userId).connect(a, { deviceId: agentId, kind: "agent", connId: "c" });
      expect(a.take()).toEqual([hex(pairingRemovedEvent(agentId, mobileId, id))]);
    } finally {
      second.close();
    }
  });
});

describe("REST-side operations", () => {
  it("disconnect closes the given devices with the code, announces them offline, and is a no-op when gone", async () => {
    const { hub, agentId, mobileId } = setup();
    const a = new FakeSocket();
    const m = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    await joinHub(hub, m, mobileId);
    a.take();
    await hub.disconnect([mobileId], CloseCode.revoked);
    expect(m.closedWith).toEqual({ code: 4002, reason: "revoked" });
    expect(a.take()).toEqual([hex(encodePresence(mobileId, false))]);
    expect(await hub.online()).toEqual([agentId]);
    await hub.disconnect([mobileId], CloseCode.revoked);
    expect(a.take()).toEqual([]);
  });

  it("disconnectAllExcept closes every other device, including one that joined after the caller started", async () => {
    const { hub, agentId, mobileId, user } = setup();
    const secondAgent = user.device("agent");
    const [a, m, a2] = [new FakeSocket(), new FakeSocket(), new FakeSocket()];
    await joinHub(hub, a, agentId, "agent");
    await joinHub(hub, m, mobileId);
    await joinHub(hub, a2, secondAgent, "agent");
    await hub.disconnectAllExcept(agentId, CloseCode.revoked);
    expect(m.closedWith?.code).toBe(4002);
    expect(a2.closedWith?.code).toBe(4002);
    expect(a.closedWith).toBeNull();
  });

  it("closeAccount closes whatever is live now with 4002 and purges the tombstones", async () => {
    const { hub, agentId, mobileId } = setup();
    await hub.notifyPairingRemoved(agentId, mobileId, newPairingId());
    const late = new FakeSocket();
    await joinHub(hub, late, mobileId); // lands after any device list a route could have read
    await hub.closeAccount();
    expect(late.closedWith).toEqual({ code: 4002, reason: "revoked" });
    expect(await hub.purgeAll()).toBe(0);
  });

  it("closeConnection closes only that exact connection, never a newer one of the same device", async () => {
    const { hub, mobileId } = setup();
    const stale = new FakeSocket();
    const staleConn = await joinHub(hub, stale, mobileId);
    const fresh = new FakeSocket();
    await joinHub(hub, fresh, mobileId); // replaces the stale one (4001)
    await hub.closeConnection(staleConn, CloseCode.revoked);
    expect(stale.closedWith).toEqual({ code: 4001, reason: "replaced" });
    expect(fresh.closedWith).toBeNull();

    const freshConn = await joinHub(hub, new FakeSocket(), crypto.randomUUID());
    await hub.closeConnection(freshConn, CloseCode.revoked);
    expect(await hub.online()).toEqual([mobileId]);
  });
});

describe("serial queue and lifecycle", () => {
  it("runs operations in arrival order and survives a failing one, logging only its kind", async () => {
    const { hub, agentId, mobileId } = setup();
    const lines: string[] = [];
    vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    });
    const order: string[] = [];
    const first = hub.admitPairing(agentId, mobileId, newPairingId()).then(() => order.push("first"));
    const spy = vi.spyOn(db(), "run").mockImplementationOnce(() => {
      throw Object.assign(new Error("database is locked: INSERT INTO pending_pairing_removed ..."), { code: "SQLITE_BUSY" });
    });
    const failing = hub.notifyPairingRemoved(agentId, mobileId, newPairingId()).catch((err: unknown) => {
      order.push("failed");
      return err;
    });
    const third = hub.online().then(() => order.push("third"));
    await Promise.all([first, failing, third]);
    spy.mockRestore();
    expect(order).toEqual(["first", "failed", "third"]);
    expect(await failing).toMatchObject({ code: "SQLITE_BUSY" });
    const output = lines.join("\n");
    expect(output).toContain('"event":"hub_op_failed"');
    expect(output).toContain('"op":"notify_pairing_removed"');
    expect(output).toContain('"error":"SQLITE_BUSY"');
    expect(output).not.toContain("INSERT INTO");
    expect(await hub.admitPairing(agentId, mobileId, newPairingId())).toBe(true); // still working
  });

  it("drops a hub once it has no socket and no queued work, and never one that still holds a socket", async () => {
    const { registry, userId, mobileId } = setup();
    await registry.forUser(userId).online();
    await registry.whenEmpty();
    expect(registry.size).toBe(0);

    const m = new FakeSocket();
    await joinHub(registry.forUser(userId), m, mobileId);
    await registry.forUser(userId).idle();
    expect(registry.size).toBe(1);
    clientCloses(registry.forUser(userId), m);
    await registry.whenEmpty();
    expect(registry.size).toBe(0);

    registry.forUser(crypto.randomUUID()); // looked up, never used
    await registry.whenEmpty();
    expect(registry.size).toBe(0);
  });

  it("ignores a socket that closed before its turn to join came", async () => {
    const { hub, agentId, mobileId } = setup();
    const a = new FakeSocket();
    await joinHub(hub, a, agentId, "agent");
    const gone = new FakeSocket();
    gone.readyState = 3;
    await joinHub(hub, gone, mobileId);
    hub.disconnected(gone);
    await hub.idle();
    expect(a.take()).toEqual([]);
    expect(await hub.online()).toEqual([agentId]);
  });

  it("rejects a join whose tombstones cannot be read, leaving the socket out of the hub", async () => {
    const { hub, agentId } = setup();
    vi.spyOn(db(), "all").mockImplementationOnce(() => {
      throw Object.assign(new Error("database is locked"), { code: "SQLITE_BUSY" });
    });
    const a = new FakeSocket();
    await expect(joinHub(hub, a, agentId, "agent")).rejects.toMatchObject({ code: "SQLITE_BUSY" });
    expect(await hub.online()).toEqual([]);
  });

  it("goAway closes every socket with 1001, refuses later joins the same way, and empties the registry", async () => {
    const { registry, userId, agentId, mobileId } = setup();
    const a = new FakeSocket();
    const m = new FakeSocket();
    await joinHub(registry.forUser(userId), a, agentId, "agent");
    await joinHub(registry.forUser(userId), m, mobileId);
    const done = registry.goAway();
    await registry.forUser(userId).idle();
    expect(a.closedWith).toEqual({ code: GOING_AWAY, reason: "going away" });
    expect(m.closedWith).toEqual({ code: GOING_AWAY, reason: "going away" });

    const late = new FakeSocket();
    await joinHub(registry.forUser(userId), late, crypto.randomUUID());
    expect(late.closedWith).toEqual({ code: GOING_AWAY, reason: "going away" });

    clientCloses(registry.forUser(userId), a);
    clientCloses(registry.forUser(userId), m);
    await done;
    expect(registry.size).toBe(0);
  });

  it("terminateAll drops sockets that never answered the close handshake", async () => {
    const { registry, userId, agentId } = setup();
    const a = new FakeSocket();
    await joinHub(registry.forUser(userId), a, agentId, "agent");
    void registry.goAway();
    await registry.forUser(userId).idle();
    registry.terminateAll();
    expect(a.terminated).toBe(true);
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `npx vitest run test/user-hub.test.ts`
Expected: FAIL — `Error: Cannot find module '../src/hub/registry.js' imported from …/test/user-hub.test.ts`.

- [ ] **Step 3: Implement**

Create `relay/src/hub/frame-budgets.ts`:

```ts
import { FRAMES_PER_SECOND, TokenBucket } from "./token-bucket.js";

/** How often idle buckets are dropped, and after how long a bucket counts as idle. */
const SWEEP_INTERVAL_MS = 60_000;
const IDLE_MS = 1000;

/**
 * The 500 frames/s budget of every device (spec §6.2), kept by the registry rather than by a hub so
 * that neither a reconnect nor the hub being dropped and re-created refills it early. A bucket
 * untouched for one second has refilled to its full capacity, exactly like a new one, so dropping
 * it in `sweep` changes nothing observable while keeping memory bounded.
 */
export class FrameBudgets {
  private readonly buckets = new Map<string, { bucket: TokenBucket; lastUsed: number }>();
  private lastSweep: number;

  constructor(private readonly now: () => number) {
    this.lastSweep = now();
  }

  get size(): number {
    return this.buckets.size;
  }

  /** Spends one frame of `deviceId`'s budget; false when it is exhausted. */
  take(deviceId: string): boolean {
    const now = this.now();
    if (now - this.lastSweep >= SWEEP_INTERVAL_MS) this.sweep(now);
    let entry = this.buckets.get(deviceId);
    if (entry === undefined) {
      entry = { bucket: new TokenBucket(FRAMES_PER_SECOND, FRAMES_PER_SECOND, now), lastUsed: now };
      this.buckets.set(deviceId, entry);
    }
    entry.lastUsed = now;
    return entry.bucket.take(now);
  }

  sweep(now: number = this.now()): void {
    this.lastSweep = now;
    for (const [deviceId, entry] of this.buckets) {
      if (now - entry.lastUsed >= IDLE_MS) this.buckets.delete(deviceId);
    }
  }
}
```

Replace `relay/src/hub/user-hub.ts`:

```ts
import type { DeviceKind } from "../auth/device.js";
import type { Db } from "../db/db.js";
import { errorKind, logMeta } from "../log.js";
import {
  CloseCode, encodeError, encodePresence, MAX_FRAME_BYTES, pairingRemovedEvent, parseDataHeader, RelayErrorCode,
  withPeer,
} from "../protocol/frames.js";
import type { FrameBudgets } from "./frame-budgets.js";

/**
 * The server end of one WebSocket, as the hub uses it: a `ws` WebSocket in production, a fake in
 * unit tests. `readyState` 1 is OPEN.
 */
export interface HubSocket {
  readonly readyState: number;
  send(data: Uint8Array | string): void;
  close(code: number, reason: string): void;
  terminate(): void;
}

export const SOCKET_OPEN = 1;
/** Sent to every socket when the relay shuts down (spec §4.3); clients reconnect with backoff. */
export const GOING_AWAY = 1001;

/** Identity of one connection, set by the ws route from the validated token. */
export interface ConnectionMeta {
  deviceId: string;
  kind: DeviceKind;
  /** Random per upgrade; lets `closeConnection` target this exact socket (never the client's value). */
  connId: string;
}

/** Metadata kept for each socket (the Durable Object's `serializeAttachment`, spec §4.2). */
export interface Attachment {
  device_id: string;
  kind: DeviceKind;
  conn_id: string;
  /** True once the hub itself closed this socket (4001/4002/4003/1001); its close event is then ignored. */
  closing: boolean;
}

/** What a hub needs from its registry. */
export interface HubHost {
  readonly db: Db;
  readonly now: () => number;
  readonly budgets: FrameBudgets;
  readonly shuttingDown: boolean;
  /** The account's live state, created on demand. */
  stateFor(userId: string): HubState;
  /** The account's live state if there is one (never creates it). */
  existingState(userId: string): HubState | undefined;
  /** Called when the state has no socket and no queued work left. */
  release(state: HubState): void;
}

const CLOSE_REASONS: Record<CloseCode, string> = {
  [CloseCode.replaced]: "replaced",
  [CloseCode.revoked]: "revoked",
  [CloseCode.rateLimited]: "rate_limited",
};

/**
 * The in-memory state of one account's hub (spec §4.3): its sockets and its serial queue. Every
 * operation that reads or changes it (a socket joining or closing, an incoming frame, a call from
 * a REST route) runs through the queue, in arrival order, like the Durable Object's input gate. A
 * failing operation is logged by kind and rejects its own caller only; the queue keeps going.
 * Dropped by the registry once it has no socket and no queued work; reached through `UserHub`.
 */
export class HubState {
  private readonly sockets = new Map<HubSocket, Attachment>();
  private tail: Promise<unknown> = Promise.resolve();
  private pending = 0;

  constructor(
    readonly userId: string,
    private readonly host: HubHost,
  ) {}

  /** Sockets held by this hub, including ones it is closing whose close event has not arrived yet. */
  get socketCount(): number {
    return this.sockets.size;
  }

  // ---- sockets (called by the ws route) -------------------------------------------------------

  /**
   * Adds a freshly upgraded socket. One connection per device: the newest wins, the old socket gets
   * 4001 and no offline is announced. The newcomer gets a PRESENCE snapshot of the other online
   * devices, then (for an agent) every pairing_removed tombstone; the others see it come online.
   * Rejects (with the socket untouched) if the tombstones cannot be read, so the caller can close it.
   */
  connect(socket: HubSocket, meta: ConnectionMeta): Promise<void> {
    return this.enqueue("connect", () => {
      if (socket.readyState !== SOCKET_OPEN) return; // the client left before its turn came
      if (this.host.shuttingDown) {
        safeClose(socket, GOING_AWAY, "going away");
        return;
      }
      const tombstones = this.tombstonesOf(meta.deviceId); // may throw: nothing has changed yet
      for (const old of this.socketsOf(meta.deviceId)) this.closeSocket(old, CloseCode.replaced);
      // The device's frame budget is deliberately NOT reset here (see FrameBudgets).
      this.sockets.set(socket, { device_id: meta.deviceId, kind: meta.kind, conn_id: meta.connId, closing: false });
      for (const other of this.liveDeviceIds()) {
        if (other !== meta.deviceId) safeSend(socket, encodePresence(other, true));
      }
      this.broadcast(encodePresence(meta.deviceId, true), meta.deviceId);
      for (const row of tombstones) {
        safeSend(socket, pairingRemovedEvent(meta.deviceId, row.mobile_id, row.pairing_id));
      }
    });
  }

  /** A binary relay frame (or any text other than "ping", which the ws route answers itself). */
  receive(socket: HubSocket, data: ArrayBuffer | Uint8Array | string): void {
    void this.enqueue("frame", () => this.handleFrame(socket, data));
  }

  /** The socket's close event: forget it and announce the device offline unless the hub closed it. */
  disconnected(socket: HubSocket): void {
    void this.enqueue("close", () => {
      const me = this.sockets.get(socket);
      if (me === undefined) return;
      this.sockets.delete(socket);
      if (!me.closing) this.markOffline(me.device_id);
    });
  }

  // ---- calls from REST routes (the former Durable Object RPC, spec §10.4) --------------------

  /** Device ids that currently have a live connection. */
  online(): Promise<string[]> {
    return this.enqueue("online", () => this.liveDeviceIds());
  }

  /** Closes every connection of `deviceIds` with `code` and announces them offline. */
  disconnect(deviceIds: string[], code: CloseCode): Promise<void> {
    return this.enqueue("disconnect", () => this.disconnectNow(deviceIds, code));
  }

  /**
   * Closes every live socket except those of `exceptDeviceId` with `code`: called after a password
   * change commits. Uses the hub's own live list at the moment it runs, not a list read earlier.
   */
  disconnectAllExcept(exceptDeviceId: string, code: CloseCode): Promise<void> {
    return this.enqueue("disconnect_all_except", () =>
      this.disconnectNow(this.liveDeviceIds().filter((id) => id !== exceptDeviceId), code),
    );
  }

  /**
   * Records the pairing_removed tombstone for the agent (always, even when it looks online: a live
   * socket can be silently dead), then sends the EVENT to both devices if connected. One tombstone
   * per (agent, mobile), keeping the newest pairing id; replayed on every connect of the agent until
   * `admitPairing` (newer id), `purgeAgent` (logout) or `purgeAll` (account deletion) removes it.
   */
  notifyPairingRemoved(agentId: string, mobileId: string, pairingId: string): Promise<void> {
    return this.enqueue("notify_pairing_removed", () => {
      this.host.db.run(
        `INSERT INTO pending_pairing_removed (user_id, agent_id, mobile_id, pairing_id) VALUES (?, ?, ?, ?)
         ON CONFLICT (agent_id, mobile_id) DO UPDATE SET pairing_id = excluded.pairing_id
         WHERE excluded.pairing_id > pending_pairing_removed.pairing_id`,
        this.userId,
        agentId,
        mobileId,
        pairingId,
      );
      const frame = pairingRemovedEvent(agentId, mobileId, pairingId);
      for (const socket of this.socketsOf(agentId)) safeSend(socket, frame);
      if (mobileId !== agentId) for (const socket of this.socketsOf(mobileId)) safeSend(socket, frame);
    });
  }

  /**
   * May pairing `pairingId` of (agent, mobile) be recorded? False when the tombstone's id is the
   * same or newer (kept); otherwise an older tombstone is deleted and the answer is true. Check and
   * delete run in one queued operation, so no notifyPairingRemoved can interleave.
   */
  admitPairing(agentId: string, mobileId: string, pairingId: string): Promise<boolean> {
    return this.enqueue("admit_pairing", () => {
      const tombstone = this.host.db.get<{ pairing_id: string }>(
        "SELECT pairing_id FROM pending_pairing_removed WHERE user_id = ? AND agent_id = ? AND mobile_id = ?",
        this.userId,
        agentId,
        mobileId,
      );
      if (tombstone === undefined) return true;
      if (tombstone.pairing_id >= pairingId) return false;
      this.host.db.run(
        "DELETE FROM pending_pairing_removed WHERE user_id = ? AND agent_id = ? AND mobile_id = ?",
        this.userId,
        agentId,
        mobileId,
      );
      return true;
    });
  }

  /** Deletes every tombstone of one agent (its logout). Returns the number of rows removed. */
  purgeAgent(agentId: string): Promise<number> {
    return this.enqueue("purge_agent", () =>
      this.host.db.run("DELETE FROM pending_pairing_removed WHERE user_id = ? AND agent_id = ?", this.userId, agentId)
        .changes,
    );
  }

  /** Deletes every tombstone of the account. Returns the number of rows removed. */
  purgeAll(): Promise<number> {
    return this.enqueue("purge_all", () =>
      this.host.db.run("DELETE FROM pending_pairing_removed WHERE user_id = ?", this.userId).changes,
    );
  }

  /** Account deletion: closes whatever is live right now with 4002, then purges the tombstones. */
  closeAccount(): Promise<void> {
    return this.enqueue("close_account", () => {
      this.disconnectNow(this.liveDeviceIds(), CloseCode.revoked);
      this.host.db.run("DELETE FROM pending_pairing_removed WHERE user_id = ?", this.userId);
    });
  }

  /**
   * Closes the one socket whose connection id is `connId`, if still live; a no-op if that exact
   * connection is already gone (replaced by a newer connection of the same device, for example).
   * Used by the ws route's post-upgrade token re-check.
   */
  closeConnection(connId: string, code: CloseCode): Promise<void> {
    return this.enqueue("close_connection", () => {
      for (const [socket, me] of this.sockets) {
        if (me.conn_id === connId && isLive(socket, me)) {
          this.closeSocket(socket, code);
          this.markOffline(me.device_id);
          return;
        }
      }
    });
  }

  /** Shutdown: closes every socket with 1001 "going away". */
  goAway(): Promise<void> {
    return this.enqueue("go_away", () => {
      for (const [socket, me] of this.sockets) {
        if (me.closing) continue;
        me.closing = true;
        safeClose(socket, GOING_AWAY, "going away");
      }
    });
  }

  /** Last step of a shutdown that ran out of time: drops every socket without a close handshake. */
  terminateAll(): void {
    for (const socket of this.sockets.keys()) {
      try {
        socket.terminate();
      } catch {
        // already gone
      }
    }
  }

  /** Resolves once every operation queued so far has run. */
  idle(): Promise<void> {
    return this.tail.then(() => undefined);
  }

  // ---- internals ------------------------------------------------------------------------------

  private enqueue<T>(op: string, task: () => T): Promise<T> {
    this.pending++;
    const result = this.tail.then(task);
    this.tail = result.then(
      () => this.settle(),
      (err: unknown) => {
        logMeta("hub_op_failed", { op, error: errorKind(err) });
        this.settle();
      },
    );
    return result;
  }

  private settle(): void {
    this.pending--;
    this.releaseIfIdle();
  }

  /** Hands the state back to the registry when it holds no socket and has no queued work. */
  releaseIfIdle(): void {
    if (this.pending === 0 && this.sockets.size === 0) this.host.release(this);
  }

  private handleFrame(socket: HubSocket, data: ArrayBuffer | Uint8Array | string): void {
    const me = this.sockets.get(socket);
    if (me === undefined || me.closing) return;

    if (!this.host.budgets.take(me.device_id)) {
      safeSend(socket, encodeError(RelayErrorCode.rateLimited));
      this.closeSocket(socket, CloseCode.rateLimited);
      logMeta("ws_rate_limited", { device_id: me.device_id });
      this.markOffline(me.device_id);
      return;
    }
    if (typeof data === "string") {
      safeSend(socket, encodeError(RelayErrorCode.badFrame));
      return;
    }
    const frame = data instanceof Uint8Array ? data : new Uint8Array(data);
    const header = parseDataHeader(frame);
    if (frame.length > MAX_FRAME_BYTES) {
      safeSend(socket, encodeError(RelayErrorCode.frameTooLarge, header?.peer, header?.channel));
      logMeta("ws_frame_too_large", { device_id: me.device_id, size: frame.length });
      return;
    }
    if (header === null) {
      safeSend(socket, encodeError(RelayErrorCode.badFrame));
      return;
    }
    const targets = this.socketsOf(header.peer);
    if (targets.length === 0) {
      safeSend(socket, encodeError(RelayErrorCode.peerOffline, header.peer, header.channel));
      return;
    }
    const routed = withPeer(frame, me.device_id);
    for (const target of targets) safeSend(target, routed);
  }

  private disconnectNow(deviceIds: string[], code: CloseCode): void {
    for (const deviceId of new Set(deviceIds)) {
      const sockets = this.socketsOf(deviceId);
      if (sockets.length === 0) continue;
      for (const socket of sockets) this.closeSocket(socket, code);
      this.markOffline(deviceId);
    }
  }

  private tombstonesOf(deviceId: string): { mobile_id: string; pairing_id: string }[] {
    return this.host.db.all<{ mobile_id: string; pairing_id: string }>(
      "SELECT mobile_id, pairing_id FROM pending_pairing_removed WHERE user_id = ? AND agent_id = ? ORDER BY rowid",
      this.userId,
      deviceId,
    );
  }

  /** Marks the socket as closed by the hub, then closes it with `code`. */
  private closeSocket(socket: HubSocket, code: CloseCode): void {
    const me = this.sockets.get(socket);
    if (me === undefined || me.closing) return;
    me.closing = true;
    safeClose(socket, code, CLOSE_REASONS[code]);
  }

  /**
   * Announces offline and records last_seen_at, unless the device still has a live socket (it just
   * reconnected). Callers mark the departing socket as closing (or forget it) first.
   */
  private markOffline(deviceId: string): void {
    if (this.socketsOf(deviceId).length > 0) return;
    this.broadcast(encodePresence(deviceId, false), deviceId);
    try {
      this.host.db.run("UPDATE devices SET last_seen_at = ? WHERE id = ?", this.host.now(), deviceId);
    } catch {
      // Best-effort bookkeeping: a database error must not stop routing/presence.
      logMeta("last_seen_write_failed", { device_id: deviceId });
    }
  }

  /** Open, not-being-closed sockets of one device (normally zero or one). */
  private socketsOf(deviceId: string): HubSocket[] {
    const result: HubSocket[] = [];
    for (const [socket, me] of this.sockets) if (me.device_id === deviceId && isLive(socket, me)) result.push(socket);
    return result;
  }

  private liveDeviceIds(): string[] {
    const ids = new Set<string>();
    for (const [socket, me] of this.sockets) if (isLive(socket, me)) ids.add(me.device_id);
    return [...ids];
  }

  private broadcast(frame: Uint8Array, exceptDeviceId: string): void {
    for (const [socket, me] of this.sockets) {
      if (me.device_id !== exceptDeviceId && isLive(socket, me)) safeSend(socket, frame);
    }
  }
}

function isLive(socket: HubSocket, me: Attachment): boolean {
  return !me.closing && socket.readyState === SOCKET_OPEN;
}

function safeSend(socket: HubSocket, data: Uint8Array | string): void {
  try {
    socket.send(data);
  } catch {
    // the peer vanished between the check and the send; its close event will clean up
  }
}

function safeClose(socket: HubSocket, code: number, reason: string): void {
  try {
    socket.close(code, reason);
  } catch {
    // already closed
  }
}

/**
 * One account's hub, as routes see it: `registry.forUser(userId).<method>()` (spec §4.3). A thin
 * handle with no state of its own: every call reaches the account's live `HubState`, creating it
 * if needed, so a handle kept across an `await` can never talk to a state the registry already
 * dropped.
 */
export class UserHub {
  constructor(
    readonly userId: string,
    private readonly host: HubHost,
  ) {}

  private get state(): HubState {
    return this.host.stateFor(this.userId);
  }

  /** See `HubState.connect`. */
  connect(socket: HubSocket, meta: ConnectionMeta): Promise<void> {
    return this.state.connect(socket, meta);
  }

  receive(socket: HubSocket, data: ArrayBuffer | Uint8Array | string): void {
    this.state.receive(socket, data);
  }

  disconnected(socket: HubSocket): void {
    this.state.disconnected(socket);
  }

  online(): Promise<string[]> {
    return this.state.online();
  }

  disconnect(deviceIds: string[], code: CloseCode): Promise<void> {
    return this.state.disconnect(deviceIds, code);
  }

  disconnectAllExcept(exceptDeviceId: string, code: CloseCode): Promise<void> {
    return this.state.disconnectAllExcept(exceptDeviceId, code);
  }

  notifyPairingRemoved(agentId: string, mobileId: string, pairingId: string): Promise<void> {
    return this.state.notifyPairingRemoved(agentId, mobileId, pairingId);
  }

  admitPairing(agentId: string, mobileId: string, pairingId: string): Promise<boolean> {
    return this.state.admitPairing(agentId, mobileId, pairingId);
  }

  purgeAgent(agentId: string): Promise<number> {
    return this.state.purgeAgent(agentId);
  }

  purgeAll(): Promise<number> {
    return this.state.purgeAll();
  }

  closeAccount(): Promise<void> {
    return this.state.closeAccount();
  }

  closeConnection(connId: string, code: CloseCode): Promise<void> {
    return this.state.closeConnection(connId, code);
  }

  /** Resolves once everything queued so far for this account has run (creates nothing). */
  idle(): Promise<void> {
    return this.host.existingState(this.userId)?.idle() ?? Promise.resolve();
  }

  /** Sockets the account's hub holds right now (0 when it has no state). */
  get socketCount(): number {
    return this.host.existingState(this.userId)?.socketCount ?? 0;
  }
}
```

Create `relay/src/hub/registry.ts`:

```ts
import type { Db } from "../db/db.js";
import { FrameBudgets } from "./frame-budgets.js";
import { HubState, UserHub, type HubHost } from "./user-hub.js";

export interface HubRegistryOptions {
  db: Db;
  /** Unix milliseconds; injectable so frame-budget tests can freeze time. */
  now?: () => number;
}

/**
 * Every account's hub in this process (replaces the Durable Object namespace, spec §4.2): at most
 * one `HubState` per user id, created on first use (a connection or a REST call) and dropped once
 * it has no socket and no queued work. `forUser` hands out `UserHub` handles that always reach the
 * live state.
 */
export class HubRegistry implements HubHost {
  readonly db: Db;
  readonly now: () => number;
  readonly budgets: FrameBudgets;
  private readonly states = new Map<string, HubState>();
  private stopping = false;
  private emptyWaiters: (() => void)[] = [];

  constructor(options: HubRegistryOptions) {
    this.db = options.db;
    this.now = options.now ?? Date.now;
    this.budgets = new FrameBudgets(this.now);
  }

  forUser(userId: string): UserHub {
    return new UserHub(userId, this);
  }

  stateFor(userId: string): HubState {
    let state = this.states.get(userId);
    if (state === undefined) {
      const created = new HubState(userId, this);
      this.states.set(userId, created);
      // A caller that never queues anything must not leave the state behind.
      queueMicrotask(() => created.releaseIfIdle());
      state = created;
    }
    return state;
  }

  existingState(userId: string): HubState | undefined {
    return this.states.get(userId);
  }

  /** Accounts whose hub state is in memory right now. */
  get size(): number {
    return this.states.size;
  }

  /** True once `goAway` ran: hubs close new sockets with 1001 instead of admitting them. */
  get shuttingDown(): boolean {
    return this.stopping;
  }

  release(state: HubState): void {
    if (this.states.get(state.userId) === state) this.states.delete(state.userId);
    if (this.states.size === 0) for (const resolve of this.emptyWaiters.splice(0)) resolve();
  }

  /** Resolves when no hub state is left in memory (every socket closed, every queue drained). */
  whenEmpty(): Promise<void> {
    if (this.states.size === 0) return Promise.resolve();
    return new Promise((resolve) => this.emptyWaiters.push(resolve));
  }

  /**
   * Shutdown steps 2–3 (spec §4.3): every socket is closed with 1001 and later connections are
   * refused the same way. Resolves once every hub has drained and every socket reported its close.
   */
  async goAway(): Promise<void> {
    this.stopping = true;
    await Promise.all([...this.states.values()].map((state) => state.goAway()));
    await this.whenEmpty();
  }

  /** Drops every remaining socket without a close handshake (after the shutdown grace period). */
  terminateAll(): void {
    for (const state of this.states.values()) state.terminateAll();
  }
}
```

In `relay/tsconfig.json` delete this line from `exclude`:

```jsonc
    "src/hub/user-hub.ts",
```

- [ ] **Step 4: Run the tests and the type check**

Run: `npx vitest run test/user-hub.test.ts`
Expected: PASS (24 tests).

Run: `npm run typecheck && npm test`
Expected: `Test Files  8 passed (8)`, `Tests  110 passed (110)`.

- [ ] **Step 5: Commit**

```bash
git add -A relay
git commit -m "feat(relay): in-process UserHub with a serial queue, SQLite tombstones and a HubRegistry"
```

### Task 4: HTTP routes and the WebSocket upgrade on Node

`session.ts` and the five route files move from D1 to `Db` and from `hubFor(env, …)`/`stub.fetch` to `c.get("hubs").forUser(…)`. `GET /v1/ws` authenticates first (401 before any upgrade, 426 for a non-upgrade request) and then lets `@hono/node-server`'s `upgradeWebSocket` complete the handshake with `ws`; the socket joins the hub in `onOpen`, the token is re-checked after the join (TOCTOU guard kept), `ping` is answered in `onMessage` outside the queue. The Workers test files are ported onto the Node harness.

Not split further: every WebSocket, account and pairing test needs register/login and the pairing routes, and `logout`, `password` and account deletion call the hub, so routes and the WebSocket route land together.

What changed in the ported tests (all assertions kept unless listed):
- `env.DB.prepare(sql).bind(a, b).first<T>()` → `db().get<T>(sql, a, b)` (returns `undefined` instead of `null`); `.all<T>()` → `db().all<T>(…)`; `.run()` → `db().run(…)`.
- `hubFor(env, id)` → `hubs().forUser(id)`; `bindings: { USER_HUB: fake }` → a second app `makeApp({ hubs: fakeHubs({ … }) })` over the same test database.
- `bindings: { DB: dbRacingFirstBatch(hook) }` → `makeApp({ passwords: hasherRacing("verify" | "hash", hook) })`: with synchronous SQLite the race window is the argon2 `await` just before the write.
- `makeApp({ limiters: () => ({ … }) })` → `makeApp({ limiters: { … } })`; `CF-Connecting-IP` → `X-Real-IP` (`ip:` option; `ip: null` sends none).
- `res.webSocket` / `new TestSocket(res.webSocket)` → `connect(app, token, extraHeaders?)`; a refused real handshake is checked with `upgradeStatus(app, token)`.
- `vi.useFakeTimers()` (frozen `Date.now` for the frame budget) → `newHubRegistry(() => frozenTime)`; fake timers would also freeze the sockets' own timers.
- `evictDurableObject` (hibernation) → the hub state is dropped when its last socket closes (`hubs.whenEmpty()`, `hubs.size === 0`); the budget and tombstones survive it.
- `buildHubHeaders` no longer exists (no header forwarding into a Durable Object); its guarantee is kept by the integration test "an upgrade carrying hostile extra headers still connects and identifies the token's device".
- The "rate-limit binding failures fail open" tests are replaced by "production rate limits (createRateLimiters, keyed by X-Real-IP)".
- New: two sockets racing (Review Focus 1), 426 for a valid token without `Connection: upgrade`, 1009 over 1 MiB, the hub dropped and re-created, a request without `X-Real-IP` (Review Focus 4), database contention (Review Focus 3).

**Files:**
- Modify: `relay/src/auth/session.ts`, `relay/src/routes/auth.ts`, `relay/src/routes/account.ts`, `relay/src/routes/devices.ts`, `relay/src/routes/pairings.ts`, `relay/src/routes/ws.ts`, `relay/src/app.ts`, `relay/src/relay.ts`, `relay/test/helpers.ts`, `relay/test/auth.test.ts`, `relay/test/account.test.ts`, `relay/test/devices-pairings.test.ts`, `relay/test/hub.test.ts`, `relay/test/limits.test.ts`, `relay/test/rate-limit.test.ts`, `relay/package.json`, `relay/package-lock.json`, `relay/tsconfig.json`, `relay/vitest.config.ts`

**Interfaces:**
- Consumes: Task 1 (`Config`, `Db`, `errorKind`, `startRelay` shape), Task 2 (`PasswordHasher`, `passwords`, `hashPassword`, `RateLimiters`, `createRateLimiters`, `clientIp`), Task 3 (`HubRegistry`, `UserHub`, `HubSocket`, `ConnectionMeta`, `FakeSocket`).
- Produces:
  - `src/app.ts`: `interface AppDeps { config: Config; db: Db; hubs: HubRegistry; limiters: RateLimiters; passwords?: PasswordHasher; now?: () => number }`, `interface AppVariables { config; db; hubs; limiters; passwords; now; auth: AuthContext }`, `interface AppBindings { incoming: IncomingMessage }`, `type AppEnv`, `createApp(deps): Hono<AppEnv>`.
  - `src/auth/session.ts`: `interface AuthContext { userId; deviceId; kind }`, `insertToken(db, tokenHash: ArrayBuffer, deviceId, now): void`, `insertTokenIfPasswordUnchanged(db, tokenHash, deviceId, now, userId, verifiedHash): number`, `authenticate(db: Db, token: string | null, now: number): Promise<AuthContext | null>`, `requireAuth`.
  - `src/routes/ws.ts`: `webSocketAuth: MiddlewareHandler<AppEnv>`, `webSocketUpgrade`, `INTERNAL_ERROR_CLOSE = 1011` (a socket the hub could not admit).
  - `src/relay.ts`: `MAX_WS_MESSAGE_BYTES = 1024 * 1024`, `startRelay(deps: AppDeps, listen: ListenOptions): Promise<RunningRelay>` with the WebSocket upgrade.
  - `test/helpers.ts` (final): adds `allowAll`, `unlimited`, `CountingLimiter`, `hubs()`, `newHubRegistry(now?)`, `interface CloseInfo`, `class TestSocket { ws; closed: Promise<CloseInfo>; next(); nextBinary(); expectSilence(); send(); close() }`, `connect(app, token, headers?)`, `upgradeStatus(app, token)`; `makeApp` defaults `hubs: hubs()` and `limiters: unlimited`.

- [ ] **Step 1: Add `ws`**

```bash
npm install --save-exact ws@8.22.0
npm install --save-exact --save-dev @types/ws@8.18.1
```

- [ ] **Step 2: Write the failing tests**

Replace `relay/test/helpers.ts` with its final version:

```ts
import { mkdtempSync, rmSync } from "node:fs";
import http from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach } from "vitest";
import { WebSocket } from "ws";
import type { AppDeps } from "../src/app.js";
import type { RateLimiter, RateLimiters } from "../src/auth/rate-limit.js";
import type { Config } from "../src/config.js";
import { Db } from "../src/db/db.js";
import { migrate } from "../src/db/migrate.js";
import { HubRegistry } from "../src/hub/registry.js";
import type { HubSocket } from "../src/hub/user-hub.js";
import { startRelay, type RunningRelay } from "../src/relay.js";

// ---- configuration used by every test relay ---------------------------------------------------

export const TEST_CONFIG: Config = {
  host: "127.0.0.1",
  port: 0,
  dbPath: "unused-in-tests.db",
  minAgent: "1.0.0",
  minMobile: "1.0.0",
  latestAgentVersion: "1.0.0",
  macUrl: "https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg",
  winUrl: "https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe",
  rateLimitsEnabled: false,
};

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

// ---- per-test environment: a temp directory with a migrated SQLite DB and a hub registry -------

interface TestEnv {
  dir: string;
  db: Db;
  hubs: HubRegistry;
  registries: HubRegistry[];
}

let current: TestEnv | null = null;
const cleanups: (() => unknown)[] = [];

function testEnv(): TestEnv {
  if (current === null) {
    const dir = mkdtempSync(join(tmpdir(), "shellx-relay-test-"));
    const db = Db.open(join(dir, "relay.db"));
    migrate(db);
    const hubs = new HubRegistry({ db });
    current = { dir, db, hubs, registries: [hubs] };
  }
  return current;
}

/** This test's database (created, and migrated, on first use). */
export function db(): Db {
  return testEnv().db;
}

/** This test's hub registry, shared by every app of the test (like the Durable Object namespace). */
export function hubs(): HubRegistry {
  return testEnv().hubs;
}

/** This test's temporary directory (deleted after the test). */
export function tempDir(): string {
  return testEnv().dir;
}

/** A second registry over this test's database (e.g. with a frozen clock); drained after the test. */
export function newHubRegistry(now?: () => number): HubRegistry {
  const env = testEnv();
  const registry = new HubRegistry({ db: env.db, now });
  env.registries.push(registry);
  return registry;
}

/** Runs `fn` after the current test, before its database is closed (last registered runs first). */
export function onCleanup(fn: () => unknown): void {
  cleanups.push(fn);
}

afterEach(async () => {
  for (const fn of cleanups.splice(0).reverse()) await fn();
  if (current === null) return;
  const env = current;
  current = null;
  // Server-side close events of the sockets just terminated still update last_seen_at.
  await Promise.race([
    Promise.all(env.registries.map((registry) => registry.whenEmpty())),
    new Promise((resolve) => setTimeout(resolve, 1000)),
  ]);
  env.db.close();
  rmSync(env.dir, { recursive: true, force: true });
});

// ---- test relays --------------------------------------------------------------------------------

/** A relay listening on a random 127.0.0.1 port; started in the background by `makeApp`. */
export interface TestApp {
  readonly ready: Promise<RunningRelay>;
}

/**
 * Starts a real relay (HTTP server + WebSocket upgrade) for this test, over the test's database and
 * hub registry, with rate limits off. `deps` overrides any dependency for this app only.
 */
export function makeApp(deps: Partial<AppDeps> = {}): TestApp {
  const ready = startRelay(
    { config: TEST_CONFIG, db: db(), hubs: hubs(), limiters: unlimited, ...deps },
    { host: "127.0.0.1", port: 0 },
  );
  onCleanup(async () => {
    const relay = await ready;
    relay.server.closeAllConnections();
    await new Promise<void>((resolve) => relay.server.close(() => resolve()));
  });
  return { ready };
}

/** A buffered HTTP response (`json<T>()` is generic, like the Workers `Response` the tests were written for). */
export class TestResponse {
  constructor(
    readonly status: number,
    readonly headers: Headers,
    private readonly body: Buffer,
  ) {}

  async text(): Promise<string> {
    return this.body.toString("utf8");
  }

  async json<T = any>(): Promise<T> {
    return JSON.parse(this.body.toString("utf8")) as T;
  }
}

export interface CallOptions {
  body?: unknown;
  token?: string;
  /**
   * Sent as X-Real-IP (default 203.0.113.7; the test client connects from 127.0.0.1, a trusted
   * proxy address). `null` sends no X-Real-IP at all.
   */
  ip?: string | null;
  headers?: Record<string, string>;
}

/**
 * One HTTP request to the relay with `node:http` (fetch() refuses headers like `Upgrade`). A JSON
 * body gets `Content-Type: application/json` and a `Content-Length`; `chunks` sends a streamed
 * (chunked) body without one.
 */
export async function call(app: TestApp, method: string, path: string, options: CallOptions = {}): Promise<TestResponse> {
  const headers: Record<string, string> = { ...options.headers };
  if (options.token !== undefined) headers.Authorization = `Bearer ${options.token}`;
  if (options.ip !== null) headers["X-Real-IP"] = options.ip ?? "203.0.113.7";
  let body: Buffer | undefined;
  if (options.body !== undefined) {
    body = Buffer.from(typeof options.body === "string" ? options.body : JSON.stringify(options.body), "utf8");
    headers["Content-Type"] = "application/json";
    headers["Content-Length"] = String(body.length);
  }
  return request(app, method, path, headers, body === undefined ? [] : [body]);
}

/** Like `call`, but the body is streamed in `chunks` with no Content-Length (chunked encoding). */
export async function callStreamed(app: TestApp, method: string, path: string, chunks: Uint8Array[]): Promise<TestResponse> {
  return request(app, method, path, { "Content-Type": "application/json", "X-Real-IP": "203.0.113.7" }, chunks);
}

async function request(
  app: TestApp, method: string, path: string, headers: Record<string, string>, chunks: Uint8Array[],
): Promise<TestResponse> {
  const { port } = await app.ready;
  return new Promise((resolve, reject) => {
    const req = http.request({ host: "127.0.0.1", port, method, path, headers, agent: false }, (res) => {
      const received: Buffer[] = [];
      res.on("data", (chunk: Buffer) => received.push(chunk));
      res.on("end", () => {
        const responseHeaders = new Headers();
        for (const [name, value] of Object.entries(res.headers)) {
          if (value !== undefined) responseHeaders.set(name, Array.isArray(value) ? value.join(", ") : value);
        }
        resolve(new TestResponse(res.statusCode ?? 0, responseHeaders, Buffer.concat(received)));
      });
      res.on("error", reject);
    });
    req.on("error", reject);
    for (const chunk of chunks) req.write(chunk);
    req.end();
  });
}

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

/** A UUIDv7 (RFC 9562) for unix-millisecond timestamp `ms`, lower case, random in the other bits. */
export function uuidv7(ms: number): string {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  for (let i = 0; i < 6; i++) bytes[i] = Math.floor(ms / 2 ** (8 * (5 - i))) % 256;
  bytes[6] = 0x70 | (bytes[6]! & 0x0f); // version 7
  bytes[8] = 0x80 | (bytes[8]! & 0x3f); // variant 10
  const h = hex(bytes);
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

let lastPairingMs = 0;
/** A pairing id as the agent generates it (UUIDv7), strictly newer than every one returned before. */
export function newPairingId(): string {
  lastPairingMs = Math.max(Date.now(), lastPairingMs + 1);
  return uuidv7(lastPairingMs);
}

/** POST /v1/pairings as `agentToken`, with a fresh agent-generated pairing id unless one is given. */
export async function pair(
  app: TestApp,
  agentToken: string,
  mobileId: string,
  pairingId: string = newPairingId(),
): Promise<TestResponse> {
  return call(app, "POST", "/v1/pairings", { token: agentToken, body: { mobile_id: mobileId, pairing_id: pairingId } });
}

/** The `pairing_id` of the row for (agent, mobile), or null when there is no row. */
export async function pairingIdOf(agentId: string, mobileId: string): Promise<string | null> {
  return db().get<{ pairing_id: string }>("SELECT pairing_id FROM pairings WHERE agent_id = ? AND mobile_id = ?", agentId, mobileId)
    ?.pairing_id ?? null;
}

export async function errorCode(res: TestResponse): Promise<string> {
  const body = await res.json<{ error: { code: string; message: string } }>();
  return body.error.code;
}

export interface CloseInfo {
  code: number;
  reason: string;
}

/** Client end of a relay WebSocket (the `ws` library) with an awaitable message queue. */
export class TestSocket {
  private readonly queue: (Uint8Array | string)[] = [];
  private notify: (() => void) | null = null;
  readonly closed: Promise<CloseInfo>;

  constructor(readonly ws: WebSocket) {
    ws.on("message", (data: Buffer, isBinary: boolean) => {
      this.queue.push(isBinary ? new Uint8Array(data) : data.toString("utf8"));
      this.notify?.();
    });
    ws.on("error", () => {
      // surfaced through `closed` (ws always emits "close" after "error")
    });
    this.closed = new Promise((resolve) => {
      ws.on("close", (code: number, reason: Buffer) => {
        resolve({ code, reason: reason.toString("utf8") });
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

function openSocket(relay: RunningRelay, headers: Record<string, string>): WebSocket {
  const ws = new WebSocket(`ws://127.0.0.1:${relay.port}/v1/ws`, { headers });
  onCleanup(() => ws.terminate());
  return ws;
}

/** Opens a real WebSocket to /v1/ws with `token`; throws `upgrade failed: <status>` if refused. */
export async function connect(app: TestApp, token: string | undefined, headers: Record<string, string> = {}): Promise<TestSocket> {
  const relay = await app.ready;
  const ws = openSocket(relay, { ...(token === undefined ? {} : { Authorization: `Bearer ${token}` }), ...headers });
  const socket = new TestSocket(ws); // listens before "open": the hub may send PRESENCE right away
  await new Promise<void>((resolve, reject) => {
    ws.once("open", () => resolve());
    ws.once("unexpected-response", (_req, res) => reject(new Error(`upgrade failed: ${res.statusCode}`)));
    ws.once("error", reject);
  });
  return socket;
}

/** The HTTP status a refused WebSocket upgrade got (101 means it was accepted, and is closed again). */
export async function upgradeStatus(app: TestApp, token: string | undefined): Promise<number> {
  const relay = await app.ready;
  const ws = openSocket(relay, token === undefined ? {} : { Authorization: `Bearer ${token}` });
  return new Promise((resolve) => {
    ws.once("open", () => {
      ws.terminate();
      resolve(101);
    });
    ws.once("unexpected-response", (_req, res) => {
      resolve(res.statusCode ?? 0);
      res.resume();
      ws.terminate();
    });
    ws.on("error", () => {
      // reported through the status above
    });
  });
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

/** In-memory stand-in for a `ws` socket: records what the hub sends and how it closes it. */
export class FakeSocket implements HubSocket {
  readyState = 1;
  readonly sent: (Uint8Array | string)[] = [];
  closedWith: { code: number; reason: string } | null = null;
  terminated = false;

  send(data: Uint8Array | string): void {
    if (this.readyState !== 1) throw new Error("socket is not open");
    this.sent.push(data);
  }

  close(code: number, reason: string): void {
    if (this.readyState !== 1) return;
    this.closedWith = { code, reason };
    this.readyState = 2;
  }

  terminate(): void {
    this.terminated = true;
    this.readyState = 3;
  }

  /** Hex of every binary frame received so far, then forgets them. */
  take(): string[] {
    return this.sent.splice(0).map((m) => (typeof m === "string" ? `text:${m}` : hex(m)));
  }
}
```

Replace `relay/test/hub.test.ts` (its racing test pins Review Focus 1):

```ts
import { afterEach, describe, expect, it, vi } from "vitest";
import type { HubRegistry } from "../src/hub/registry.js";
import type { ConnectionMeta, HubSocket } from "../src/hub/user-hub.js";
import { type CloseCode, encodeData, encodeError, encodePresence, MAX_FRAME_BYTES, RelayErrorCode } from "../src/protocol/frames.js";
import {
  call, connect, db, errorCode, hex, hubs, loginDevice, makeApp, registerAccount, type TestApp, TestSocket, upgradeStatus,
  waitFor,
} from "./helpers.js";

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

/**
 * A registry that behaves like the test's real one, except that `connect` first runs `before` —
 * the point between the ws route's authenticate() and the socket landing in the hub.
 */
function registryRacingConnect(before: () => Promise<void>, after?: () => Promise<void>): HubRegistry {
  const real = hubs();
  return {
    forUser: (userId: string) => {
      const hub = real.forUser(userId);
      return {
        connect: async (socket: HubSocket, meta: ConnectionMeta) => {
          await before();
          await hub.connect(socket, meta);
          await after?.();
        },
        receive: (socket: HubSocket, data: ArrayBuffer | string) => hub.receive(socket, data),
        disconnected: (socket: HubSocket) => hub.disconnected(socket),
        closeConnection: (connId: string, code: CloseCode) => hub.closeConnection(connId, code),
      };
    },
  } as unknown as HubRegistry;
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
      expect(await errorCode(res)).toBe("unauthorized");
      expect(await upgradeStatus(client, token)).toBe(401); // a real WebSocket handshake gets the same status
    }
  });

  it("answers 426 to a valid token on a request that is not a real upgrade (no Connection: upgrade)", async () => {
    const { app, agent } = await accountWithAgentAndMobile();
    const res = await call(app, "GET", "/v1/ws", { token: agent.token, headers: { Upgrade: "websocket" } });
    expect(res.status).toBe(426);
    expect(await errorCode(res)).toBe("upgrade_required");
  });

  it("an upgrade carrying hostile extra headers still connects and identifies the token's device", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    await a.expectSilence(100);

    // Mobile's token, plus a cookie and headers claiming to be the agent device: only the token counts.
    const m = await connect(app, mobile.token, {
      Cookie: "session=abc123",
      "X-Shellx-Device-Id": agent.deviceId,
      "X-Shellx-Device-Kind": "agent",
      "X-Shellx-Conn-Id": "44444444-4444-4444-4444-444444444444",
    });
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    m.send(encodeData(agent.deviceId, CH, Uint8Array.of(4, 9)));
    expect(hex(await a.nextBinary())).toBe(hex(encodeData(mobile.deviceId, CH, Uint8Array.of(4, 9))));
  });

  it("closes the socket with 4002 if the token is revoked in the gap between auth and the socket joining the hub", async () => {
    const { app, mobile } = await accountWithAgentAndMobile();
    const racing = makeApp({
      hubs: registryRacingConnect(async () => {
        db().run("DELETE FROM tokens WHERE device_id = ?", mobile.deviceId);
      }),
    });
    const socket = await connect(racing, mobile.token); // the upgrade itself still succeeds...
    expect(await socket.closed).toEqual({ code: 4002, reason: "revoked" }); // ...but is then closed
    await call(app, "GET", "/v1/version"); // the normal app is unaffected
  });

  it("fails closed if the post-join re-check itself errors, e.g. a database error", async () => {
    const { app, mobile } = await accountWithAgentAndMobile();
    const realGet = db().get.bind(db());
    let calls = 0;
    const spy = vi.spyOn(db(), "get").mockImplementation((sql: string, ...params) => {
      if (sql.includes("FROM tokens t JOIN devices d")) {
        calls++;
        // Call 1 is the route's own authenticate(); call 2 is the re-check after the join.
        if (calls === 2) throw Object.assign(new Error("database is locked"), { code: "SQLITE_BUSY" });
      }
      return realGet(sql, ...params);
    });
    const socket = await connect(app, mobile.token);
    expect(await socket.closed).toEqual({ code: 4002, reason: "revoked" });
    spy.mockRestore();
    expect(calls).toBe(2);
  });

  it("targets only the stale connection: a legitimate reconnect that already replaced it is untouched", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const stale = await loginDevice(app, account, "mobile");
    let fresh: TestSocket | undefined;
    const racing = makeApp({
      hubs: registryRacingConnect(
        async () => {},
        async () => {
          // After the stale socket joined: the same device logs in again (invalidating the stale
          // token) and connects through the normal app, replacing the stale socket with 4001.
          const again = await loginDevice(app, account, "mobile", stale.publicKey);
          fresh = await connect(app, again.token);
        },
      ),
    });
    const staleSocket = await connect(racing, stale.token);
    expect(await staleSocket.closed).toEqual({ code: 4001, reason: "replaced" }); // not the re-check
    await waitFor(async () => fresh);
    await fresh!.expectSilence(100);
    fresh!.send("ping");
    expect(await fresh!.next()).toBe("pong");
  });

  it("two sockets of the same device racing in one tick: exactly one survives, peers never see it offline", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    const [first, second] = await Promise.all([connect(app, mobile.token), connect(app, mobile.token)]);
    const closed = await Promise.race([
      first.closed.then((info) => ({ loser: first, winner: second, info })),
      second.closed.then((info) => ({ loser: second, winner: first, info })),
    ]);
    expect(closed.info).toEqual({ code: 4001, reason: "replaced" });
    closed.winner.send("ping");
    let reply = await closed.winner.next();
    while (reply !== "pong") reply = await closed.winner.next(); // skip its PRESENCE snapshot
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    await a.expectSilence(); // no offline in between or after
    const devices = await call(app, "GET", "/v1/devices", { token: agent.token });
    const listed = await devices.json<{ id: string; online: boolean }[]>();
    expect(listed.find((d) => d.id === mobile.deviceId)?.online).toBe(true);
  });
});

describe("hub presence and routing over real sockets", () => {
  it("sends a presence snapshot to the newcomer and announces it to the others", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    await a.expectSilence(100);
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
    await attacker.expectSilence(100);
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

  it("closes a socket that sends a message over 1 MiB with 1009 (ws maxPayload)", async () => {
    const { app, agent, mobile } = await accountWithAgentAndMobile();
    const a = await connect(app, agent.token);
    const m = await connect(app, mobile.token);
    await m.nextBinary();
    await a.nextBinary();
    m.send(new Uint8Array(1024 * 1024 + 1));
    expect((await m.closed).code).toBe(1009);
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, false)));
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
    await a.expectSilence();

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
      db().get<{ last_seen_at: number | null }>("SELECT last_seen_at FROM devices WHERE id = ?", mobile.deviceId)?.last_seen_at,
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

Replace `relay/test/rate-limit.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { FRAMES_PER_SECOND, TokenBucket } from "../src/hub/token-bucket.js";
import { encodeData, encodeError, encodePresence, RelayErrorCode } from "../src/protocol/frames.js";
import { connect, hex, loginDevice, makeApp, newHubRegistry, registerAccount } from "./helpers.js";

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

/**
 * Two connected devices on a relay whose hubs read a frozen clock, so the token math is exact no
 * matter how long the sends take on the host (the Workers version froze Date.now with fake timers;
 * here the registry's clock is injected instead, which leaves the sockets' own timers alone).
 */
async function hubWithTwoDevices(frozen = true) {
  const app = makeApp(frozen ? { hubs: newHubRegistry(() => 1_900_000_000_000) } : {});
  const account = await registerAccount(app);
  const mobile = await loginDevice(app, account, "mobile");
  const a = await connect(app, account.agent.token);
  const m = await connect(app, mobile.token);
  await m.nextBinary();
  await a.nextBinary();
  return { app, account, agent: account.agent, mobile, a, m };
}

describe("per-connection frame rate limit", () => {
  it("lets a burst of 400 frames through (real clock)", async () => {
    const { agent, a, m } = await hubWithTwoDevices(false);
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
    // With the clock frozen, exactly the fresh bucket's capacity is delivered.
    expect(delivered).toBe(FRAMES_PER_SECOND);
  });
});

describe("budget survives reconnects", () => {
  it("keeps the exhausted budget across a reconnect instead of granting a fresh one", async () => {
    const { app, agent, mobile, a, m } = await hubWithTwoDevices();

    for (let i = 0; i < 450; i++) m.send(encodeData(agent.deviceId, CH, Uint8Array.of(4)));
    for (let i = 0; i < 450; i++) await a.nextBinary();

    const m2 = await connect(app, mobile.token);
    expect((await m.closed).code).toBe(4001);
    expect(hex(await m2.nextBinary())).toBe(hex(encodePresence(agent.deviceId, true)));

    // The clock never advanced, so exactly 50 tokens remain.
    for (let i = 0; i < 50; i++) m2.send(encodeData(agent.deviceId, CH, Uint8Array.of(4)));
    for (let i = 0; i < 50; i++) await a.nextBinary();
    m2.send(encodeData(agent.deviceId, CH, Uint8Array.of(4, 1)));
    expect(hex(await m2.nextBinary())).toBe(hex(encodeError(RelayErrorCode.rateLimited)));
    expect(await m2.closed).toEqual({ code: 4003, reason: "rate_limited" });
  });

  it("keeps it even when every socket of the account closed and the hub was dropped in between", async () => {
    const hubs = newHubRegistry(() => 1_900_000_000_000);
    const app = makeApp({ hubs });
    const account = await registerAccount(app);
    const m = await connect(app, account.agent.token);
    for (let i = 0; i < 499; i++) m.send(encodeData(crypto.randomUUID(), CH, Uint8Array.of(4)));
    for (let i = 0; i < 499; i++) await m.nextBinary(); // peer_offline replies
    m.close();
    await m.closed;
    await hubs.whenEmpty();
    expect(hubs.size).toBe(0);

    const again = await connect(app, account.agent.token);
    again.send(encodeData(crypto.randomUUID(), CH, Uint8Array.of(4))); // the 500th frame: allowed
    expect((await again.nextBinary())[3]).toBe(RelayErrorCode.peerOffline);
    again.send(encodeData(crypto.randomUUID(), CH, Uint8Array.of(4))); // the 501st: over budget
    expect(hex(await again.nextBinary())).toBe(hex(encodeError(RelayErrorCode.rateLimited)));
    expect((await again.closed).code).toBe(4003);
  });

  it("keeps routing, presence, replacement and heartbeat working after the hub is dropped and re-created", async () => {
    const hubs = newHubRegistry();
    const app = makeApp({ hubs });
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    for (const socket of [await connect(app, account.agent.token), await connect(app, mobile.token)]) {
      socket.close();
      await socket.closed;
    }
    await hubs.whenEmpty();
    expect(hubs.size).toBe(0);

    const a = await connect(app, account.agent.token);
    const m = await connect(app, mobile.token);
    expect(hex(await m.nextBinary())).toBe(hex(encodePresence(account.agent.deviceId, true)));
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    m.send("ping");
    expect(await m.next()).toBe("pong");
    m.send(encodeData(account.agent.deviceId, CH, Uint8Array.of(4, 2)));
    expect(hex(await a.nextBinary())).toBe(hex(encodeData(mobile.deviceId, CH, Uint8Array.of(4, 2))));
    const m2 = await connect(app, mobile.token);
    expect((await m.closed).code).toBe(4001);
    expect(hex(await m2.nextBinary())).toBe(hex(encodePresence(account.agent.deviceId, true)));
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
  });
});
```

Replace `relay/test/auth.test.ts` (its last tests pin Review Focus 3 and 4 over HTTP):

```ts
import { join } from "node:path";
import Database from "better-sqlite3";
import { afterEach, describe, expect, it, vi } from "vitest";
import { createRateLimiters } from "../src/auth/rate-limit.js";
import { authenticate } from "../src/auth/session.js";
import { hashToken, TOKEN_IDLE_TTL_MS, TOKEN_TOUCH_INTERVAL_MS } from "../src/auth/tokens.js";
import { Db } from "../src/db/db.js";
import { HubRegistry } from "../src/hub/registry.js";
import {
  call, CountingLimiter, db, deviceBody, errorCode, loginDevice, makeApp, PASSWORD, randomEmail, randomPublicKey,
  registerAccount, tempDir, unlimited,
} from "./helpers.js";

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

    const user = db().get<{ email: string; password_hash: string }>("SELECT email, password_hash FROM users WHERE id = ?", body.user_id);
    expect(user?.email).toBe(email);
    expect(user?.password_hash).toMatch(/^\$argon2id\$v=19\$m=19456,t=2,p=1\$/);

    const tokenRow = db().get<{ device_id: string }>("SELECT device_id FROM tokens WHERE token_hash = ?", await hashToken(body.token));
    expect(tokenRow?.device_id).toBe(body.device_id);
    const rawToken = db().get<{ n: number }>("SELECT COUNT(*) AS n FROM tokens WHERE token_hash = ?", body.token);
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
    const row = db().get<{ email: string }>("SELECT email FROM users WHERE id = ?", user_id);
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
    const app = makeApp({ limiters: { ...unlimited, registerIp } });
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

describe("production rate limits (createRateLimiters, keyed by X-Real-IP)", () => {
  const register = (app: ReturnType<typeof makeApp>, ip?: string) =>
    call(app, "POST", "/v1/auth/register", {
      ip,
      body: { email: randomEmail(), password: PASSWORD, device: deviceBody("agent") },
    });

  it("allows 3 registrations per X-Real-IP per minute, then answers 429; another IP is unaffected", async () => {
    const app = makeApp({ limiters: createRateLimiters({ rateLimitsEnabled: true }) });
    for (let i = 0; i < 3; i++) expect((await register(app, "198.51.100.10")).status).toBe(201);
    const refused = await register(app, "198.51.100.10");
    expect(refused.status).toBe(429);
    expect(await errorCode(refused)).toBe("rate_limited");
    expect((await register(app, "198.51.100.11")).status).toBe(201);
  });

  it('turns every limit off when RATE_LIMITS_ENABLED is "false"', async () => {
    const app = makeApp({ limiters: createRateLimiters({ rateLimitsEnabled: false }) });
    for (let i = 0; i < 5; i++) expect((await register(app, "198.51.100.12")).status).toBe(201);
  });

  it("logs neither the IP nor the email of a refused request", async () => {
    const app = makeApp({ limiters: createRateLimiters({ rateLimitsEnabled: true }) });
    const lines: string[] = [];
    vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    });
    const email = randomEmail();
    for (let i = 0; i < 12; i++) {
      await call(app, "POST", "/v1/auth/login", {
        ip: "198.51.100.13",
        body: { email, password: "wrong password", device: deviceBody("mobile") },
      });
    }
    const output = lines.join("\n");
    expect(output).not.toContain("198.51.100.13");
    expect(output).not.toContain(email);
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
    expect(await authenticate(db(), first.token, now)).toBeNull();
    expect(await authenticate(db(), second.token, now)).toEqual({
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
    const app = makeApp({ limiters: { ...unlimited, loginIp, loginEmail } });
    const account = await registerAccount(app);
    const attempt = (email: string, ip: string) =>
      call(app, "POST", "/v1/auth/login", { ip, body: { email, password: "wrong password", device: deviceBody("mobile") } });

    for (let i = 0; i < 5; i++) expect((await attempt(i % 2 ? account.email.toUpperCase() : account.email, `192.0.2.${i}`)).status).toBe(401);
    const sixth = await attempt(` ${account.email} `, "192.0.2.99");
    expect(sixth.status).toBe(429);
    expect(await errorCode(sixth)).toBe("rate_limited");
    expect(new Set(loginEmail.calls)).toEqual(new Set([account.email]));

    for (let i = 0; i < 10; i++) expect((await attempt(randomEmail(), "198.51.100.200")).status).toBe(401);
    const eleventh = await attempt(randomEmail(), "198.51.100.200");
    expect(eleventh.status).toBe(429);
  });

  it("keys a request without X-Real-IP by its socket address", async () => {
    const loginIp = new CountingLimiter(10);
    const app = makeApp({ limiters: { ...unlimited, loginIp } });
    await call(app, "POST", "/v1/auth/login", {
      ip: null,
      body: { email: randomEmail(), password: "wrong password", device: deviceBody("mobile") },
    });
    expect(loginIp.calls).toEqual(["127.0.0.1"]);
  });

  it("never logs passwords, tokens or email addresses", async () => {
    const lines: string[] = [];
    const capture = (...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    };
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
    const lastUsed = () => db().get<{ last_used_at: number }>("SELECT last_used_at FROM tokens WHERE token_hash = ?", hash)?.last_used_at;

    expect(await authenticate(db(), account.agent.token, t0 + 30 * 60 * 1000)).not.toBeNull();
    expect(lastUsed()).toBe(t0);
    const t1 = t0 + TOKEN_TOUCH_INTERVAL_MS;
    expect(await authenticate(db(), account.agent.token, t1)).not.toBeNull();
    expect(lastUsed()).toBe(t1);

    expect(await authenticate(db(), account.agent.token, t1 + TOKEN_IDLE_TTL_MS)).not.toBeNull();
    const t2 = t1 + TOKEN_IDLE_TTL_MS;
    expect(await authenticate(db(), account.agent.token, t2 + TOKEN_IDLE_TTL_MS + 1)).toBeNull();
    expect(lastUsed()).toBeUndefined();
  });

  it("rejects missing and malformed tokens", async () => {
    expect(await authenticate(db(), null, Date.now())).toBeNull();
    expect(await authenticate(db(), "A".repeat(43), Date.now())).toBeNull();
  });
});

describe("database contention", () => {
  it("answers 500 internal_error while another process holds the write lock, logs only SQLITE_BUSY, and recovers", async () => {
    db(); // create the test database file
    const path = join(tempDir(), "relay.db");
    const impatient = Db.open(path, { busyTimeoutMs: 100 });
    const app = makeApp({ db: impatient, hubs: new HubRegistry({ db: impatient }) });
    const lines: string[] = [];
    vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    });
    const other = new Database(path); // e.g. the reset-password script in the same volume
    const email = randomEmail();
    const register = () =>
      call(app, "POST", "/v1/auth/register", { body: { email, password: PASSWORD, device: deviceBody("agent") } });
    try {
      other.exec("BEGIN IMMEDIATE");
      const blocked = await register();
      expect(blocked.status).toBe(500);
      expect(await blocked.json()).toEqual({ error: { code: "internal_error", message: "Internal error" } });
      expect((await call(app, "GET", "/v1/version")).status).toBe(200); // still serving
      other.exec("ROLLBACK");
      expect((await register()).status).toBe(201); // nothing half-written by the failed attempt
    } finally {
      other.close();
      impatient.close();
    }
    const output = lines.join("\n");
    expect(output).toContain('"event":"unhandled_error"');
    expect(output).toContain('"error":"SQLITE_BUSY"');
    expect(output).not.toContain(email);
    expect(output).not.toContain("INSERT");
  });
});
```

Replace `relay/test/account.test.ts`:

```ts
import { describe, expect, it, vi } from "vitest";
import { passwords, type PasswordHasher } from "../src/auth/password.js";
import type { HubRegistry } from "../src/hub/registry.js";
import { encodePresence, pairingRemovedEvent } from "../src/protocol/frames.js";
import {
  call, connect, CountingLimiter, db, deviceBody, errorCode, FakeSocket, hex, hubs, loginDevice, makeApp, newPairingId,
  pair, registerAccount, type TestSocket, unlimited,
} from "./helpers.js";

const NEW_PASSWORD = "brand new password";

/** A registry whose `forUser(...)` returns `hub` for every account (hub methods the test fakes). */
function fakeHubs(hub: Record<string, unknown>): HubRegistry {
  return { forUser: () => hub } as unknown as HubRegistry;
}

/**
 * The real argon2id hasher, except that the first `hash` (or `verify`) finishes only after `hook`
 * ran: a concurrent request landing between a route's password check and its write, deterministically.
 */
function hasherRacing(on: "hash" | "verify", hook: () => Promise<void>): PasswordHasher {
  let fired = false;
  const race = async () => {
    if (!fired) {
      fired = true;
      await hook();
    }
  };
  return {
    async hash(password) {
      const phc = await passwords.hash(password);
      if (on === "hash") await race();
      return phc;
    },
    async verify(password, phc) {
      const ok = await passwords.verify(password, phc);
      if (on === "verify") await race();
      return ok;
    },
  };
}

async function settle<T>(promise: Promise<T>, ms = 1500): Promise<T | "timeout"> {
  return Promise.race([promise, new Promise<"timeout">((resolve) => setTimeout(() => resolve("timeout"), ms))]);
}

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
    expect((await pair(app, account.agent.token, mobile.deviceId)).status).toBe(201);

    const a = await connect(app, account.agent.token);
    const m = await connect(app, mobile.token);
    const a2 = await connect(app, secondAgent.token);
    const before = Date.now();

    const res = await call(app, "POST", "/v1/auth/password", { token: account.agent.token, body: { new_password: NEW_PASSWORD } });
    expect(res.status).toBe(204);
    expect((await m.closed).code).toBe(4002);
    expect((await a2.closed).code).toBe(4002);

    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(200);
    expect((await call(app, "GET", "/v1/devices", { token: mobile.token })).status).toBe(401);
    expect((await call(app, "GET", "/v1/devices", { token: secondAgent.token })).status).toBe(401);
    const offline = new Set<string>();
    while (offline.size < 2) {
      const frame = await a.nextBinary();
      if (frame[1] === 0x02 && frame[18] === 0) offline.add(hex(frame));
    }
    expect(offline).toEqual(new Set([hex(encodePresence(mobile.deviceId, false)), hex(encodePresence(secondAgent.deviceId, false))]));

    const oldLogin = await call(app, "POST", "/v1/auth/login", { body: { email: account.email, password: account.password, device: deviceBody("mobile") } });
    expect(oldLogin.status).toBe(401);
    const newLogin = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: NEW_PASSWORD, device: deviceBody("mobile", { public_key: mobile.publicKey }) },
    });
    expect(newLogin.status).toBe(200);
    const pairing = db().get<{ n: number }>(
      "SELECT COUNT(*) AS n FROM pairings WHERE agent_id = ? AND mobile_id = ?", account.agent.deviceId, mobile.deviceId,
    );
    expect(pairing?.n).toBe(1);
    const changed = db().get<{ password_changed_at: number }>("SELECT password_changed_at FROM users WHERE id = ?", account.agent.userId);
    expect(changed?.password_changed_at).toBeGreaterThanOrEqual(before);
  });
});

describe("password change races (final review M1)", () => {
  it("a login that verified the old password gets no token once the change has committed", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const device = deviceBody("mobile");
    // Between this login's argon2 verify (old hash) and its token insert, the agent changes the password.
    const racing = makeApp({
      passwords: hasherRacing("verify", async () => {
        const changed = await call(app, "POST", "/v1/auth/password", { token: account.agent.token, body: { new_password: NEW_PASSWORD } });
        expect(changed.status).toBe(204);
      }),
    });
    const res = await call(racing, "POST", "/v1/auth/login", { body: { email: account.email, password: account.password, device } });
    expect(res.status).toBe(401);
    expect(await errorCode(res)).toBe("invalid_credentials");
    const tokens = db().get<{ n: number }>(
      "SELECT COUNT(*) AS n FROM tokens t JOIN devices d ON d.id = t.device_id WHERE d.user_id = ? AND d.public_key = ?",
      account.agent.userId,
      Buffer.from(device.public_key as string, "base64url"),
    );
    expect(tokens?.n).toBe(0);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(200);
    const fresh = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: NEW_PASSWORD, device: deviceBody("mobile") },
    });
    expect(fresh.status).toBe(200);
  });

  it("closes a device that connected after any device list would have been read, but keeps the caller", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const caller = await connect(app, account.agent.token);
    let late: TestSocket | undefined;
    // A phone signs in and connects after the route hashed the new password but before the change commits.
    const racing = makeApp({
      passwords: hasherRacing("hash", async () => {
        const mobile = await loginDevice(app, account, "mobile");
        late = await connect(app, mobile.token);
      }),
    });
    const res = await call(racing, "POST", "/v1/auth/password", {
      token: account.agent.token,
      body: { new_password: NEW_PASSWORD },
    });
    expect(res.status).toBe(204);
    expect(late).toBeDefined();
    expect(await settle(late!.closed)).toEqual({ code: 4002, reason: "revoked" });
    expect(await settle(caller.closed, 300)).toBe("timeout");
  });
});

describe("POST /v1/auth/logout", () => {
  it("mobile: deletes only its token; pairings stay", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await pair(app, account.agent.token, mobile.deviceId);
    expect((await call(app, "POST", "/v1/auth/logout", { token: mobile.token })).status).toBe(204);
    expect((await call(app, "GET", "/v1/devices", { token: mobile.token })).status).toBe(401);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(200);
    expect(db().get<{ n: number }>("SELECT COUNT(*) AS n FROM pairings WHERE mobile_id = ?", mobile.deviceId)?.n).toBe(1);
  });

  it("agent: deletes its token and all its pairings, and tells each connected mobile its pairing's id", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const mobile2 = await loginDevice(app, account, "mobile");
    const [first, second] = [newPairingId(), newPairingId()];
    await pair(app, account.agent.token, mobile.deviceId, first);
    await pair(app, account.agent.token, mobile2.deviceId, second);
    const m = await connect(app, mobile.token);
    const m2 = await connect(app, mobile2.token);
    expect(hex(await m.nextBinary())).toBe(hex(encodePresence(mobile2.deviceId, true)));
    expect(hex(await m2.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));

    expect((await call(app, "POST", "/v1/auth/logout", { token: account.agent.token })).status).toBe(204);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(401);
    expect(db().get<{ n: number }>("SELECT COUNT(*) AS n FROM pairings WHERE agent_id = ?", account.agent.deviceId)?.n).toBe(0);
    expect(hex(await m.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, first)));
    expect(hex(await m2.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile2.deviceId, second)));
    await m.expectSilence();
    await m2.expectSilence();
  });

  it("requires a token", async () => {
    const res = await call(makeApp(), "POST", "/v1/auth/logout");
    expect(res.status).toBe(401);
  });
});

describe("DELETE /v1/account", () => {
  const countRows = (sql: string, id: string) => db().get<{ n: number }>(sql, id)?.n;

  it("refuses a wrong password with 401 invalid_credentials and deletes nothing", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const res = await call(app, "DELETE", "/v1/account", { token: account.agent.token, body: { password: "not my password" } });
    expect(res.status).toBe(401);
    expect(await errorCode(res)).toBe("invalid_credentials");
    const missing = await call(app, "DELETE", "/v1/account", { token: account.agent.token, body: {} });
    expect(missing.status).toBe(401);
    expect(countRows("SELECT COUNT(*) AS n FROM users WHERE id = ?", account.agent.userId)).toBe(1);
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
    await pair(app, account.agent.token, mobile.deviceId);
    const a = await connect(app, account.agent.token);
    const m = await connect(app, mobile.token);

    const res = await call(app, "DELETE", "/v1/account", { token: mobile.token, body: { password: account.password } });
    expect(res.status).toBe(204);
    expect((await a.closed).code).toBe(4002);
    expect((await m.closed).code).toBe(4002);

    expect(countRows("SELECT COUNT(*) AS n FROM users WHERE id = ?", account.agent.userId)).toBe(0);
    expect(countRows("SELECT COUNT(*) AS n FROM devices WHERE user_id = ?", account.agent.userId)).toBe(0);
    expect(countRows("SELECT COUNT(*) AS n FROM tokens WHERE device_id = ?", mobile.deviceId)).toBe(0);
    expect(countRows("SELECT COUNT(*) AS n FROM tokens WHERE device_id = ?", account.agent.deviceId)).toBe(0);
    expect(countRows("SELECT COUNT(*) AS n FROM pairings WHERE agent_id = ?", account.agent.deviceId)).toBe(0);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(401);

    const again = await call(app, "POST", "/v1/auth/register", {
      body: { email: account.email, password: "a fresh password", device: deviceBody("agent") },
    });
    expect(again.status).toBe(201);
  });

  it("rate limits password attempts per account email", async () => {
    const loginEmail = new CountingLimiter(5);
    const app = makeApp({ limiters: { ...unlimited, loginEmail } });
    const account = await registerAccount(app);
    for (let i = 0; i < 5; i++) {
      const res = await call(app, "DELETE", "/v1/account", { token: account.agent.token, body: { password: "wrong password" } });
      expect(res.status).toBe(401);
    }
    const blocked = await call(app, "DELETE", "/v1/account", { token: account.agent.token, body: { password: account.password } });
    expect(blocked.status).toBe(429);
    expect(loginEmail.calls).toEqual(Array(6).fill(account.email));
  });

  it("purges the hub's durable pairing_removed queue once the account is gone", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await pair(app, account.agent.token, mobile.deviceId);
    const unpaired = await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token });
    expect(unpaired.status).toBe(204);

    const res = await call(app, "DELETE", "/v1/account", { token: mobile.token, body: { password: account.password } });
    expect(res.status).toBe(204);
    // A leftover row would make this second purge return more than 0.
    expect(await hubs().forUser(account.agent.userId).purgeAll()).toBe(0);
  });

  it("closes a device whose socket lands in the hub only after any device-id snapshot would have been taken", async () => {
    // closeAccount takes no device list: it closes whatever is live when it runs. Simulate a socket
    // that joins the hub after the user row is already gone (its upgrade passed authenticate()
    // earlier) by joining it directly, right before the real closeAccount runs.
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const late = new FakeSocket();
    const lateJoin = makeApp({
      hubs: fakeHubs({
        closeAccount: async () => {
          const hub = hubs().forUser(account.agent.userId);
          await hub.connect(late, { deviceId: mobile.deviceId, kind: "mobile", connId: crypto.randomUUID() });
          return hub.closeAccount();
        },
      }),
    });
    const res = await call(lateJoin, "DELETE", "/v1/account", { token: account.agent.token, body: { password: account.password } });
    expect(res.status).toBe(204);
    expect(late.closedWith).toEqual({ code: 4002, reason: "revoked" });
  });

  it("still deletes the account and returns 204 if closing the hub afterward throws, logging metadata only", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const throwing = makeApp({
      hubs: fakeHubs({
        closeAccount: async () => {
          throw new Error("hub is down");
        },
      }),
    });
    const lines: string[] = [];
    const spy = vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    });
    const res = await call(throwing, "DELETE", "/v1/account", { token: account.agent.token, body: { password: account.password } });
    spy.mockRestore();

    expect(res.status).toBe(204);
    expect(db().get("SELECT 1 FROM users WHERE id = ?", account.agent.userId)).toBeUndefined();
    const output = lines.join("\n");
    expect(output).toContain("account_close_failed");
    expect(output).not.toContain("hub is down");
  });
});

describe("agent logout: safe notify-then-delete order and queue purge", () => {
  it("keeps the token and pairing intact when a hub call fails, so a retried logout can still deliver the event", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await pair(app, account.agent.token, mobile.deviceId);

    let calls = 0;
    const failing = makeApp({
      hubs: fakeHubs({
        notifyPairingRemoved: async () => {
          calls++;
          throw new Error("boom");
        },
        purgeAgent: async () => 0,
      }),
    });
    const failed = await call(failing, "POST", "/v1/auth/logout", { token: account.agent.token });
    expect(failed.status).toBe(500);
    expect(await errorCode(failed)).toBe("internal_error");
    expect(calls).toBe(1);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(200);
    expect(db().get("SELECT 1 FROM pairings WHERE agent_id = ?", account.agent.deviceId)).toBeDefined();

    const retried = await call(app, "POST", "/v1/auth/logout", { token: account.agent.token });
    expect(retried.status).toBe(204);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(401);
    expect(db().get("SELECT 1 FROM pairings WHERE agent_id = ?", account.agent.deviceId)).toBeUndefined();
  });

  it("purges any pairing_removed rows still queued for the agent, even ones unrelated to this logout's own pairings", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await pair(app, account.agent.token, mobile.deviceId);
    const unpaired = await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token });
    expect(unpaired.status).toBe(204);
    const mobile2 = await loginDevice(app, account, "mobile");
    await pair(app, account.agent.token, mobile2.deviceId);

    expect((await call(app, "POST", "/v1/auth/logout", { token: account.agent.token })).status).toBe(204);
    expect(await hubs().forUser(account.agent.userId).purgeAgent(account.agent.deviceId)).toBe(0);
  });

  it("an agent that signs in again after logout gets no replay of tombstones from before the logout", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    await pair(app, account.agent.token, mobile.deviceId, pairingId);
    await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token });
    const before = await connect(app, account.agent.token);
    expect(hex(await before.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, pairingId)));
    before.close();
    await before.closed;

    expect((await call(app, "POST", "/v1/auth/logout", { token: account.agent.token })).status).toBe(204);
    const again = await loginDevice(app, account, "agent", account.agent.publicKey);
    expect(again.deviceId).toBe(account.agent.deviceId);
    const after = await connect(app, again.token);
    await after.expectSilence();
  });

  it("still logs the agent out (204) if purging its queue afterward throws, logging metadata only", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const throwing = makeApp({
      hubs: fakeHubs({
        notifyPairingRemoved: async () => {},
        purgeAgent: async () => {
          throw new Error("hub is down");
        },
      }),
    });
    const lines: string[] = [];
    const spy = vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    });
    const res = await call(throwing, "POST", "/v1/auth/logout", { token: account.agent.token });
    spy.mockRestore();

    expect(res.status).toBe(204);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(401);
    const output = lines.join("\n");
    expect(output).toContain("agent_purge_failed");
    expect(output).not.toContain("hub is down");
  });
});
```

Replace `relay/test/devices-pairings.test.ts`:

```ts
import { describe, expect, it, vi } from "vitest";
import type { HubRegistry } from "../src/hub/registry.js";
import { encodePresence, pairingRemovedEvent } from "../src/protocol/frames.js";
import {
  call, connect, db, errorCode, hex, hubs, loginDevice, makeApp, newPairingId, pair, pairingIdOf, registerAccount,
  type TestApp, uuidv7,
} from "./helpers.js";

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

async function countPairings(agentId: string): Promise<number> {
  return db().get<{ n: number }>("SELECT COUNT(*) AS n FROM pairings WHERE agent_id = ?", agentId)?.n ?? 0;
}

/** A registry whose `forUser(...)` returns `hub` for every account (the hub methods a test fakes). */
function fakeHubs(hub: Record<string, unknown>): HubRegistry {
  return { forUser: () => hub } as unknown as HubRegistry;
}

const settle = () => new Promise((resolve) => setTimeout(resolve, 50));

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
    db().run("DELETE FROM tokens WHERE device_id = ?", mobile.deviceId);
    expect((await listDevices(app, account.agent.token)).map((d) => d.id)).toEqual([account.agent.deviceId]);
  });

  it("lists devices, not pairing rows: no pairing_id appears", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    expect((await pair(app, account.agent.token, mobile.deviceId, pairingId)).status).toBe(201);
    const res = await call(app, "GET", "/v1/devices", { token: mobile.token });
    const text = await res.text();
    expect(text).not.toContain(pairingId);
    expect(text).not.toContain("pairing_id");
  });
});

describe("POST /v1/pairings", () => {
  it("records a pairing visible as paired_with_me from both sides; idempotent", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    expect((await pair(app, account.agent.token, mobile.deviceId, pairingId)).status).toBe(201);
    expect((await pair(app, account.agent.token, mobile.deviceId.toUpperCase(), pairingId)).status).toBe(201);

    const fromMobile = await listDevices(app, mobile.token);
    expect(fromMobile.find((d) => d.id === account.agent.deviceId)?.paired_with_me).toBe(true);
    expect(fromMobile.find((d) => d.id === mobile.deviceId)?.paired_with_me).toBe(false);
    const fromAgent = await listDevices(app, account.agent.token);
    expect(fromAgent.find((d) => d.id === mobile.deviceId)?.paired_with_me).toBe(true);
    expect(await countPairings(account.agent.deviceId)).toBe(1);
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

describe("POST /v1/pairings: pairing_id (agent-generated, one per pairing)", () => {
  it("requires pairing_id to be a lower-case canonical UUIDv7 string: 400 bad_request (usual error shape), nothing recorded", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const bodies: Record<string, unknown>[] = [
      { mobile_id: mobile.deviceId },
      { mobile_id: mobile.deviceId, pairing_id: "not-a-uuid" },
      { mobile_id: mobile.deviceId, pairing_id: "" },
      { mobile_id: mobile.deviceId, pairing_id: 42 },
      { mobile_id: mobile.deviceId, pairing_id: null },
      { mobile_id: mobile.deviceId, pairing_id: [newPairingId()] },
      { mobile_id: mobile.deviceId, pairing_id: crypto.randomUUID() }, // v4
      { mobile_id: mobile.deviceId, pairing_id: "00000000-0000-0000-0000-000000000000" },
      { mobile_id: mobile.deviceId, pairing_id: newPairingId().replace(/^(.{14})7/, (_, head: string) => `${head}8`) }, // v8
      { mobile_id: mobile.deviceId, pairing_id: newPairingId().toUpperCase() }, // not lower case
    ];
    for (const body of bodies) {
      const res = await call(app, "POST", "/v1/pairings", { token: account.agent.token, body });
      expect(res.status).toBe(400);
      expect(await res.json()).toEqual({ error: { code: "bad_request", message: "Malformed request body" } });
    }
    expect(await countPairings(account.agent.deviceId)).toBe(0);
  });

  it("stores the id exactly as sent; the same id again is 201 and changes nothing", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    expect((await pair(app, account.agent.token, mobile.deviceId, pairingId)).status).toBe(201);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(pairingId);
    expect((await pair(app, account.agent.token, mobile.deviceId, pairingId)).status).toBe(201);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(pairingId);
    expect(await countPairings(account.agent.deviceId)).toBe(1);
  });

  it("re-pairing the same phone under a new id replaces the row's id (no tombstone, no event)", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const [x, y] = [newPairingId(), newPairingId()];
    expect((await pair(app, account.agent.token, mobile.deviceId, x)).status).toBe(201);
    expect((await pair(app, account.agent.token, mobile.deviceId, y)).status).toBe(201);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(y);
    expect(await countPairings(account.agent.deviceId)).toBe(1);
    const a = await connect(app, account.agent.token);
    await a.expectSilence();
  });

  it("answers 410 pairing_removed when this exact pairing was already removed: no row, tombstone kept", async () => {
    // The agent's first POST committed but its response was lost; the phone unpaired; the agent's
    // retry (same pairing id) must not bring the pairing back (plan 03 Task 9 review).
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    expect((await pair(app, account.agent.token, mobile.deviceId, pairingId)).status).toBe(201);
    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`;
    expect((await call(app, "DELETE", path, { token: mobile.token })).status).toBe(204);

    for (let attempt = 0; attempt < 2; attempt++) {
      const retry = await pair(app, account.agent.token, mobile.deviceId, pairingId);
      expect(retry.status).toBe(410);
      expect(await retry.json()).toEqual({ error: { code: "pairing_removed", message: expect.any(String) } });
    }
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBeNull();

    // The tombstone is still there, still for this pairing.
    const a = await connect(app, account.agent.token);
    expect(hex(await a.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, pairingId)));
    await a.expectSilence();
  });

  it("a POST with a newer id clears the older pairing's tombstone and records the new id", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const [x, y] = [newPairingId(), newPairingId()];
    await pair(app, account.agent.token, mobile.deviceId, x);
    await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token });

    expect((await pair(app, account.agent.token, mobile.deviceId, y)).status).toBe(201);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(y);
    const a = await connect(app, account.agent.token);
    await a.expectSilence(); // the tombstone of pairing x is gone
  });

  it("refuses a stale POST whose id is older than the tombstone: 410, no row, the newer tombstone still replays", async () => {
    // An old pairing's POST (x) was still in flight — or retried — after the user paired the phone
    // again (y) and then unpaired it: it must neither clear y's tombstone nor record x.
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const [x, y] = [newPairingId(), newPairingId()];
    expect((await pair(app, account.agent.token, mobile.deviceId, y)).status).toBe(201);
    expect((await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token })).status).toBe(204);

    const stale = await pair(app, account.agent.token, mobile.deviceId, x);
    expect(stale.status).toBe(410);
    expect(await errorCode(stale)).toBe("pairing_removed");
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBeNull();
    const a = await connect(app, account.agent.token);
    expect(hex(await a.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, y)));
    await a.expectSilence();
  });

  it("refuses a stale POST whose id is older than the current row: 410, the newer row is kept", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const [x, y] = [newPairingId(), newPairingId()];
    expect((await pair(app, account.agent.token, mobile.deviceId, y)).status).toBe(201);

    const stale = await pair(app, account.agent.token, mobile.deviceId, x);
    expect(stale.status).toBe(410);
    expect(await errorCode(stale)).toBe("pairing_removed");
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(y);
    const a = await connect(app, account.agent.token);
    await a.expectSilence(); // no tombstone either
  });

  it("orders ids by their UUIDv7 timestamp, not by when the requests arrive", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const base = Date.now() - 60 * 60 * 1000;
    const later = uuidv7(base);
    const earlier = uuidv7(base - 24 * 60 * 60 * 1000);
    expect((await pair(app, account.agent.token, mobile.deviceId, later)).status).toBe(201);
    expect((await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token })).status).toBe(204);
    expect((await pair(app, account.agent.token, mobile.deviceId, earlier)).status).toBe(410);
    const newest = uuidv7(base + 1);
    expect((await pair(app, account.agent.token, mobile.deviceId, newest)).status).toBe(201);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(newest);
  });

  it("refuses (410) an id whose UUIDv7 timestamp is more than 24 h ahead of the relay's clock: no row, no tombstone", async () => {
    const now = Date.UTC(2027, 5, 1);
    const app = makeApp({ now: () => now });
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const day = 24 * 60 * 60 * 1000;

    const tooFar = await pair(app, account.agent.token, mobile.deviceId, uuidv7(now + day + 1));
    expect(tooFar.status).toBe(410);
    expect(await errorCode(tooFar)).toBe("pairing_removed");
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBeNull();
    const a = await connect(app, account.agent.token);
    await a.expectSilence(); // no tombstone was written for it
    a.close();

    // Exactly 24 h ahead is still accepted (clock skew), and later ids keep working.
    const edge = uuidv7(now + day);
    expect((await pair(app, account.agent.token, mobile.deviceId, edge)).status).toBe(201);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(edge);
  });

  it("asks the hub before writing the row and again after, and answers 410 (removing the row) if the pairing was removed in between", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    const seen: { args: unknown[]; row: string | null }[] = [];
    // First answer: "fine to record"; second: "this pairing has been removed meanwhile" (a phone
    // DELETE that read the fresh row and wrote its tombstone between the upsert and the re-check).
    const answers = [true, false];
    const racing = makeApp({
      hubs: fakeHubs({
        admitPairing: async (...args: unknown[]) => {
          seen.push({ args, row: await pairingIdOf(account.agent.deviceId, mobile.deviceId) });
          return answers.shift();
        },
      }),
    });

    const res = await call(racing, "POST", "/v1/pairings", {
      token: account.agent.token,
      body: { mobile_id: mobile.deviceId, pairing_id: pairingId },
    });
    expect(res.status).toBe(410);
    expect(await errorCode(res)).toBe("pairing_removed");
    const args = [account.agent.deviceId, mobile.deviceId, pairingId];
    expect(seen).toEqual([{ args, row: null }, { args, row: pairingId }]);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBeNull();
  });

  it("a 410 also removes a row left behind under that same id, and never a row with another id", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const [x, y] = [newPairingId(), newPairingId()];
    const refusing = makeApp({ hubs: fakeHubs({ admitPairing: async () => false }) });
    const post = (id: string) =>
      call(refusing, "POST", "/v1/pairings", { token: account.agent.token, body: { mobile_id: mobile.deviceId, pairing_id: id } });

    await pair(app, account.agent.token, mobile.deviceId, x);
    expect((await post(y)).status).toBe(410);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(x); // another pairing's row stays
    expect((await post(x)).status).toBe(410);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBeNull();
  });

  it("fails closed when the hub cannot be asked: 500, nothing recorded, nothing secret logged", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const throwing = makeApp({
      hubs: fakeHubs({
        admitPairing: async () => {
          throw new Error("hub is down");
        },
      }),
    });
    const lines: string[] = [];
    const spy = vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
      lines.push(args.map(String).join(" "));
    });
    const res = await call(throwing, "POST", "/v1/pairings", {
      token: account.agent.token,
      body: { mobile_id: mobile.deviceId, pairing_id: newPairingId() },
    });
    spy.mockRestore();
    expect(res.status).toBe(500);
    expect(await errorCode(res)).toBe("internal_error");
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBeNull();
    const output = lines.join("\n");
    expect(output).not.toContain("hub is down");
    expect(output).not.toContain(account.agent.token);
  });
});

describe("POST /v1/pairings: hub failure after the row was written", () => {
  it("answers 500 if the re-check throws (the row may already be recorded); a retry with the same id converges to 201", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    let calls = 0;
    const failingRecheck = makeApp({
      hubs: fakeHubs({
        admitPairing: async () => {
          calls++;
          if (calls === 2) throw new Error("hub is down");
          return true;
        },
      }),
    });

    const failed = await call(failingRecheck, "POST", "/v1/pairings", {
      token: account.agent.token,
      body: { mobile_id: mobile.deviceId, pairing_id: pairingId },
    });
    expect(failed.status).toBe(500);
    expect(await errorCode(failed)).toBe("internal_error");
    expect(calls).toBe(2);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(pairingId); // already recorded

    expect((await pair(app, account.agent.token, mobile.deviceId, pairingId)).status).toBe(201);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(pairingId);
    expect(await countPairings(account.agent.deviceId)).toBe(1);
  });

  it("a retry after that 500 still answers 410 if the phone unpaired meanwhile", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    let calls = 0;
    const failingRecheck = makeApp({
      hubs: fakeHubs({
        admitPairing: async () => {
          calls++;
          if (calls === 2) throw new Error("hub is down");
          return true;
        },
      }),
    });
    await call(failingRecheck, "POST", "/v1/pairings", {
      token: account.agent.token,
      body: { mobile_id: mobile.deviceId, pairing_id: pairingId },
    });
    expect((await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token })).status).toBe(204);

    const retry = await pair(app, account.agent.token, mobile.deviceId, pairingId);
    expect(retry.status).toBe(410);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBeNull();
  });
});

describe("DELETE /v1/pairings/:agent_id/:mobile_id", () => {
  it("lets the agent remove a pairing and notifies the connected mobile", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    await pair(app, account.agent.token, mobile.deviceId, pairingId);
    const m = await connect(app, mobile.token);

    const res = await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, {
      token: account.agent.token,
    });
    expect(res.status).toBe(204);
    expect(hex(await m.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, pairingId)));
    const fromMobile = await listDevices(app, mobile.token);
    expect(fromMobile.find((d) => d.id === account.agent.deviceId)?.paired_with_me).toBe(false);
  });

  it("lets the mobile remove a pairing and notifies the connected agent", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    await pair(app, account.agent.token, mobile.deviceId, pairingId);
    const a = await connect(app, account.agent.token);

    const res = await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, {
      token: mobile.token,
    });
    expect(res.status).toBe(204);
    expect(hex(await a.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, pairingId)));
  });

  it("queues the event for an offline agent and delivers it after the presence snapshot", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    const event = hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, pairingId));
    await pair(app, account.agent.token, mobile.deviceId, pairingId);
    const m = await connect(app, mobile.token);
    await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token });
    expect(hex(await m.nextBinary())).toBe(event);

    const a = await connect(app, account.agent.token);
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    expect(hex(await a.nextBinary())).toBe(event);
    await a.expectSilence();
  });

  it("replays a queued event (tombstone) on every agent connect until the phone is paired again under a new id", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    const event = hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, pairingId));
    await pair(app, account.agent.token, mobile.deviceId, pairingId);
    // The agent is offline when the phone unpairs.
    expect((await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token })).status).toBe(204);

    // Not deleted on send: a connect whose socket dies right after the replay must not lose it.
    for (let i = 0; i < 3; i++) {
      const a = await connect(app, account.agent.token);
      expect(hex(await a.nextBinary())).toBe(event);
      await a.expectSilence();
      a.close();
      await settle();
    }

    // Re-pairing the same phone (a new pairing, so a new id) clears the tombstone.
    expect((await pair(app, account.agent.token, mobile.deviceId)).status).toBe(201);
    const after = await connect(app, account.agent.token);
    await after.expectSilence();
  });

  it("never replays a stale event after unpair → re-pair of the same phone (agent online throughout)", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`;
    const pairingId = newPairingId();
    await pair(app, account.agent.token, mobile.deviceId, pairingId);
    const a = await connect(app, account.agent.token);

    expect((await call(app, "DELETE", path, { token: mobile.token })).status).toBe(204);
    expect(hex(await a.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, pairingId)));
    // The user pairs the same phone again (same device ids, new pairing id), then the desktop reconnects.
    expect((await pair(app, account.agent.token, mobile.deviceId)).status).toBe(201);
    a.close();
    await settle();

    const again = await connect(app, account.agent.token);
    await again.expectSilence(); // a replayed pairing_removed would drop the freshly re-paired phone
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
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).not.toBeNull(); // the bystander's 403 must not touch the row
    expect((await call(app, "DELETE", path, { token: mobile.token })).status).toBe(204);
    expect((await call(app, "DELETE", path, { token: mobile.token })).status).toBe(204);
  });

  it("replays the event to an agent that was online when it fired, on its next connect", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    const event = hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, pairingId));
    await pair(app, account.agent.token, mobile.deviceId, pairingId);
    const a = await connect(app, account.agent.token);

    const res = await call(app, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, {
      token: mobile.token,
    });
    expect(res.status).toBe(204);
    expect(hex(await a.nextBinary())).toBe(event);
    a.close();
    await settle();

    // A silently-dead live socket must not lose the event: it was queued too, and is replayed here.
    const again = await connect(app, account.agent.token);
    expect(hex(await again.nextBinary())).toBe(event);
    await again.expectSilence();
  });

  it("collapses repeated pair/unpair cycles while the agent is offline into one tombstone, for the latest pairing", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`;
    const ids = [newPairingId(), newPairingId(), newPairingId()];
    for (const id of ids) {
      expect((await pair(app, account.agent.token, mobile.deviceId, id)).status).toBe(201);
      expect((await call(app, "DELETE", path, { token: mobile.token })).status).toBe(204);
    }

    const a = await connect(app, account.agent.token);
    expect(hex(await a.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, ids[2]!)));
    await a.expectSilence(); // exactly one queued row survived three cycles, not three
  });

  it("keeps the pairing row when the hub RPC fails, so a retry can still deliver the event", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    await pair(app, account.agent.token, mobile.deviceId, pairingId);
    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`;

    let calls = 0;
    const failingOnce = makeApp({
      hubs: fakeHubs({
        notifyPairingRemoved: async () => {
          calls++;
          if (calls === 1) throw new Error("boom");
        },
      }),
    });

    const failed = await call(failingOnce, "DELETE", path, { token: mobile.token });
    expect(failed.status).toBe(500);
    expect(await errorCode(failed)).toBe("internal_error");
    // The failed hub call must not have deleted the row.
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(pairingId);

    const retried = await call(app, "DELETE", path, { token: mobile.token });
    expect(retried.status).toBe(204);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBeNull();

    const a = await connect(app, account.agent.token);
    expect(hex(await a.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, pairingId)));
  });
});

describe("DELETE /v1/pairings: ?pairing_id= (the agent's revoke) and the phone's unpair", () => {
  it("with a matching id deletes the row; the live event and the replayed tombstone carry that id", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    const event = hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, pairingId));
    await pair(app, account.agent.token, mobile.deviceId, pairingId);
    const m = await connect(app, mobile.token);

    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}?pairing_id=${pairingId}`;
    expect((await call(app, "DELETE", path, { token: account.agent.token })).status).toBe(204);
    expect(hex(await m.nextBinary())).toBe(event);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBeNull();

    const a = await connect(app, account.agent.token);
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    expect(hex(await a.nextBinary())).toBe(event);
    await a.expectSilence();
  });

  it("with a mismatching id is a no-op: 204, row kept, no tombstone, no event (a revoke landing after a re-pair)", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const [x, y] = [newPairingId(), newPairingId()];
    await pair(app, account.agent.token, mobile.deviceId, x);
    // The user revoked pairing x on the desktop and quickly paired the phone again (y) before the
    // revoke's DELETE reached the relay.
    await pair(app, account.agent.token, mobile.deviceId, y);
    const m = await connect(app, mobile.token);
    const a = await connect(app, account.agent.token);
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    expect(hex(await m.nextBinary())).toBe(hex(encodePresence(account.agent.deviceId, true)));

    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}?pairing_id=${x}`;
    expect((await call(app, "DELETE", path, { token: account.agent.token })).status).toBe(204);
    expect((await call(app, "DELETE", path, { token: mobile.token })).status).toBe(204);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(y);
    await m.expectSilence();
    await a.expectSilence();
    a.close();
    await settle();
    const again = await connect(app, account.agent.token);
    expect(hex(await again.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    await again.expectSilence(); // no tombstone was written
  });

  it("with an id but no row at all is a no-op: 204, no tombstone, no event", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const m = await connect(app, mobile.token);
    const a = await connect(app, account.agent.token);
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    expect(hex(await m.nextBinary())).toBe(hex(encodePresence(account.agent.deviceId, true)));

    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}?pairing_id=${newPairingId()}`;
    expect((await call(app, "DELETE", path, { token: account.agent.token })).status).toBe(204);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBeNull();
    await m.expectSilence();
    await a.expectSilence();
    a.close();
    await settle();
    const again = await connect(app, account.agent.token);
    expect(hex(await again.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, true)));
    await again.expectSilence(); // no tombstone was written
  });

  it("without an id deletes whatever row exists and reports that row's id", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const [x, y] = [newPairingId(), newPairingId()];
    await pair(app, account.agent.token, mobile.deviceId, x);
    await pair(app, account.agent.token, mobile.deviceId, y);
    const a = await connect(app, account.agent.token);

    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`;
    expect((await call(app, "DELETE", path, { token: mobile.token })).status).toBe(204);
    expect(hex(await a.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, y)));
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBeNull();
  });

  it("refuses an invalid (non-UUIDv7 or not lower case) pairing_id query with 400 bad_request and leaves the row alone", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const pairingId = newPairingId();
    await pair(app, account.agent.token, mobile.deviceId, pairingId);
    const base = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`;
    const queries = [
      "?pairing_id=not-a-uuid", "?pairing_id=", "?pairing_id", `?pairing_id=${crypto.randomUUID()}`,
      `?pairing_id=${pairingId.toUpperCase()}`,
    ];
    for (const query of queries) {
      const res = await call(app, "DELETE", `${base}${query}`, { token: account.agent.token });
      expect(res.status).toBe(400);
      expect(await errorCode(res)).toBe("bad_request");
    }
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(pairingId);
  });

  it("the revoke only deletes the row it notified about, even if a re-pair replaces the row in between", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const [x, y] = [newPairingId(), newPairingId()];
    await pair(app, account.agent.token, mobile.deviceId, x);
    const notified: unknown[][] = [];
    const racing = makeApp({
      hubs: fakeHubs({
        notifyPairingRemoved: async (...args: unknown[]) => {
          notified.push(args);
          // A re-pair's POST lands between the DELETE's read and its delete.
          db().run("UPDATE pairings SET pairing_id = ? WHERE agent_id = ? AND mobile_id = ?", y, account.agent.deviceId, mobile.deviceId);
        },
      }),
    });

    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}?pairing_id=${x}`;
    const res = await call(racing, "DELETE", path, { token: account.agent.token });
    expect(res.status).toBe(204);
    expect(notified).toEqual([[account.agent.deviceId, mobile.deviceId, x]]);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBe(y);
  });

  it("the phone's unpair tries again when the row was replaced in between, and reports the id it deleted", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const [x, y] = [newPairingId(), newPairingId()];
    await pair(app, account.agent.token, mobile.deviceId, x);
    const notified: unknown[][] = [];
    const racing = makeApp({
      hubs: fakeHubs({
        notifyPairingRemoved: async (...args: unknown[]) => {
          notified.push(args);
          if (notified.length === 1) {
            db().run("UPDATE pairings SET pairing_id = ? WHERE agent_id = ? AND mobile_id = ?", y, account.agent.deviceId, mobile.deviceId);
          }
        },
      }),
    });

    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`;
    const res = await call(racing, "DELETE", path, { token: mobile.token });
    expect(res.status).toBe(204);
    expect(notified).toEqual([
      [account.agent.deviceId, mobile.deviceId, x],
      [account.agent.deviceId, mobile.deviceId, y],
    ]);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).toBeNull();
  });

  it("gives up with 500 (row kept) rather than loop forever if the row keeps changing", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    await pair(app, account.agent.token, mobile.deviceId);
    let calls = 0;
    const churning = makeApp({
      hubs: fakeHubs({
        notifyPairingRemoved: async () => {
          calls++;
          db().run("UPDATE pairings SET pairing_id = ? WHERE agent_id = ? AND mobile_id = ?", newPairingId(), account.agent.deviceId, mobile.deviceId);
        },
      }),
    });

    const path = `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`;
    const res = await call(churning, "DELETE", path, { token: mobile.token });
    expect(res.status).toBe(500);
    expect(await errorCode(res)).toBe("internal_error");
    expect(calls).toBe(3);
    expect(await pairingIdOf(account.agent.deviceId, mobile.deviceId)).not.toBeNull();
  });
});

describe("UserHub calls from routes", () => {
  it("online() lists connected devices and disconnect() closes them with the given code", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const a = await connect(app, account.agent.token);
    const m = await connect(app, mobile.token);
    await m.nextBinary();
    await a.nextBinary();
    const hub = hubs().forUser(account.agent.userId);
    expect((await hub.online()).sort()).toEqual([account.agent.deviceId, mobile.deviceId].sort());

    await hub.disconnect([mobile.deviceId], 4002);
    expect(await m.closed).toEqual({ code: 4002, reason: "revoked" });
    expect(hex(await a.nextBinary())).toBe(hex(encodePresence(mobile.deviceId, false)));
    expect(await hub.online()).toEqual([account.agent.deviceId]);
    await hub.disconnect([mobile.deviceId], 4002); // already gone: no-op
    await a.expectSilence();
  });

  it("keeps one tombstone per (agent, mobile) holding the newest id: a newer removal overwrites it, an older one does not", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const other = await loginDevice(app, account, "mobile");
    const [w, x, y, z] = [newPairingId(), newPairingId(), newPairingId(), newPairingId()];
    const hub = hubs().forUser(account.agent.userId);
    await hub.notifyPairingRemoved(account.agent.deviceId, mobile.deviceId, x);
    await hub.notifyPairingRemoved(account.agent.deviceId, other.deviceId, z);
    await hub.notifyPairingRemoved(account.agent.deviceId, mobile.deviceId, y); // newer: overwrites x
    await hub.notifyPairingRemoved(account.agent.deviceId, mobile.deviceId, w); // older: y stays

    const a = await connect(app, account.agent.token);
    const replayed = [hex(await a.nextBinary()), hex(await a.nextBinary())].sort();
    expect(replayed).toEqual([
      hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, y)),
      hex(pairingRemovedEvent(account.agent.deviceId, other.deviceId, z)),
    ].sort());
    await a.expectSilence();
  });

  it("admitPairing() refuses ids not newer than the tombstone (keeping it), and clears it for a newer id", async () => {
    const agentId = crypto.randomUUID();
    const mobileId = crypto.randomUUID();
    const [w, x, y] = [newPairingId(), newPairingId(), newPairingId()];
    const hub = hubs().forUser(crypto.randomUUID());
    expect(await hub.admitPairing(agentId, mobileId, x)).toBe(true); // no tombstone at all
    await hub.notifyPairingRemoved(agentId, mobileId, x);
    expect(await hub.admitPairing(agentId, mobileId, x)).toBe(false); // the removed pairing itself
    expect(await hub.admitPairing(agentId, mobileId, w)).toBe(false); // an older pairing
    expect(await hub.admitPairing(agentId, mobileId, x)).toBe(false); // still there
    expect(await hub.admitPairing(crypto.randomUUID(), mobileId, w)).toBe(true); // other agent: untouched
    expect(await hub.admitPairing(agentId, mobileId, x)).toBe(false);
    expect(await hub.admitPairing(agentId, mobileId, y)).toBe(true); // newer: clears x's tombstone
    expect(await hub.admitPairing(agentId, mobileId, w)).toBe(true);
    expect(await hub.purgeAll()).toBe(0);
  });
});
```

Replace `relay/test/limits.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { hashPassword } from "../src/auth/password.js";
import { call, callStreamed, db, deviceBody, errorCode, loginDevice, makeApp, registerAccount } from "./helpers.js";

// Final review I2: login and DELETE /v1/account passed any-length passwords to argon2, and no route
// capped its request body.

const BODY_LIMIT = 16 * 1024;
const TOO_LONG = "x".repeat(129); // 129 code points: one over the 8-128 policy

/** Stores the argon2id hash of `password` for the user directly, bypassing the policy check. */
async function plantPassword(userId: string, password: string): Promise<void> {
  db().run("UPDATE users SET password_hash = ? WHERE id = ?", await hashPassword(password), userId);
}

/** A JSON object with the fields of `base` plus padding, exactly `bytes` UTF-8 bytes long. */
function paddedJson(base: Record<string, unknown>, bytes: number): string {
  const skeleton = new TextEncoder().encode(JSON.stringify({ ...base, pad: "" })).length;
  if (skeleton > bytes) throw new Error("base is already larger than the requested size");
  const body = JSON.stringify({ ...base, pad: "p".repeat(bytes - skeleton) });
  expect(new TextEncoder().encode(body).length).toBe(bytes);
  return body;
}

describe("password length cap on login and account deletion", () => {
  it("login refuses a password over 128 code points as invalid_credentials, even one that would verify", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    await plantPassword(account.agent.userId, TOO_LONG);
    const res = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: TOO_LONG, device: deviceBody("mobile") },
    });
    expect(res.status).toBe(401);
    expect(await errorCode(res)).toBe("invalid_credentials");
  });

  it("counts code points after NFC: 128 characters typed as NFD or as astral symbols still log in", async () => {
    const app = makeApp();
    const nfc = "ệ".normalize("NFC").repeat(128);
    const account = await registerAccount(app, undefined, nfc);
    expect([...nfc.normalize("NFD")].length).toBe(384);
    const nfdLogin = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: nfc.normalize("NFD"), device: deviceBody("mobile") },
    });
    expect(nfdLogin.status).toBe(200);

    const astral = "😀".repeat(128); // 256 UTF-16 code units, 128 code points
    await plantPassword(account.agent.userId, astral);
    const astralLogin = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: astral, device: deviceBody("mobile") },
    });
    expect(astralLogin.status).toBe(200);
  });

  it("account deletion refuses a password over 128 code points before verifying, deleting nothing", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    await plantPassword(account.agent.userId, TOO_LONG);
    const res = await call(app, "DELETE", "/v1/account", { token: account.agent.token, body: { password: TOO_LONG } });
    expect(res.status).toBe(401);
    expect(await errorCode(res)).toBe("invalid_credentials");
    expect(db().get("SELECT 1 FROM users WHERE id = ?", account.agent.userId)).toBeDefined();
  });
});

describe("request body limit (16 KiB) on the JSON routes", () => {
  interface Route {
    method: string;
    path: (ids: { mobileId: string }) => string;
    token: "none" | "agent";
  }
  const routes: [string, Route][] = [
    ["POST /v1/auth/register", { method: "POST", path: () => "/v1/auth/register", token: "none" }],
    ["POST /v1/auth/login", { method: "POST", path: () => "/v1/auth/login", token: "none" }],
    ["POST /v1/auth/password", { method: "POST", path: () => "/v1/auth/password", token: "agent" }],
    ["DELETE /v1/account", { method: "DELETE", path: () => "/v1/account", token: "agent" }],
    ["POST /v1/pairings", { method: "POST", path: () => "/v1/pairings", token: "agent" }],
  ];

  it.each(routes)("%s answers 413 payload_too_large (JSON error shape) one byte over the limit", async (_, route) => {
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const body = paddedJson(
      { email: account.email, password: account.password, new_password: "another password", mobile_id: mobile.deviceId, device: deviceBody("mobile") },
      BODY_LIMIT + 1,
    );
    const res = await call(app, route.method, route.path({ mobileId: mobile.deviceId }), {
      body,
      token: route.token === "agent" ? account.agent.token : undefined,
    });
    expect(res.status).toBe(413);
    expect(await res.json()).toEqual({ error: { code: "payload_too_large", message: "Request body is too large" } });
    // Nothing happened: the account and its password are unchanged.
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(200);
  });

  it("accepts a body of exactly 16 KiB", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const body = paddedJson({ email: account.email, password: account.password, device: deviceBody("mobile") }, BODY_LIMIT);
    expect((await call(app, "POST", "/v1/auth/login", { body })).status).toBe(200);
  });

  it("also caps a streamed body that has no Content-Length", async () => {
    const chunk = new TextEncoder().encode(" ".repeat(4096));
    const res = await callStreamed(makeApp(), "POST", "/v1/auth/login", Array(5).fill(chunk));
    expect(res.status).toBe(413);
    expect(await errorCode(res)).toBe("payload_too_large");
  });

  it("keeps 401 unauthorized ahead of the size check on authenticated routes", async () => {
    const res = await call(makeApp(), "DELETE", "/v1/account", { body: paddedJson({}, BODY_LIMIT + 1) });
    expect(res.status).toBe(401);
    expect(await errorCode(res)).toBe("unauthorized");
  });
});
```

In `relay/vitest.config.ts` delete these lines from `NOT_YET_PORTED` (only `"test/reset-password.test.ts"` stays):

```ts
  "test/account.test.ts",
  "test/auth.test.ts",
  "test/devices-pairings.test.ts",
  "test/hub.test.ts",
  "test/limits.test.ts",
  "test/rate-limit.test.ts",
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `npx vitest run test/hub.test.ts test/auth.test.ts`
Expected: FAIL — mostly `Error: register failed: 404 {"error":{"code":"not_found","message":"Not found"}}` (the routes are not mounted yet).

- [ ] **Step 4: Implement the routes on `Db` and the registry**

Replace `relay/src/auth/session.ts`:

```ts
import type { MiddlewareHandler } from "hono";
import type { AppEnv } from "../app.js";
import type { Db } from "../db/db.js";
import { Errors } from "../http/errors.js";
import type { DeviceKind } from "./device.js";
import { hashToken, parseBearer, TOKEN_IDLE_TTL_MS, TOKEN_TOUCH_INTERVAL_MS } from "./tokens.js";

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

export function insertToken(db: Db, tokenHash: ArrayBuffer, deviceId: string, now: number): void {
  db.run("INSERT INTO tokens (token_hash, device_id, created_at, last_used_at) VALUES (?, ?, ?, ?)", tokenHash, deviceId, now, now);
}

/**
 * Inserts the token only while the user's password hash is still `verifiedHash` — the one the
 * login just verified against. A password change that commits in between (argon2 takes tens of
 * milliseconds) makes this insert nothing (returns 0), so no token is ever minted under a password
 * that is no longer valid (final review M1). Returns the number of rows inserted.
 */
export function insertTokenIfPasswordUnchanged(
  db: Db, tokenHash: ArrayBuffer, deviceId: string, now: number, userId: string, verifiedHash: string,
): number {
  return db.run(
    `INSERT INTO tokens (token_hash, device_id, created_at, last_used_at)
     SELECT ?, ?, ?, ? WHERE (SELECT password_hash FROM users WHERE id = ?) = ?`,
    tokenHash, deviceId, now, now, userId, verifiedHash,
  ).changes;
}

/**
 * Resolves a bearer token. Tokens idle for more than 90 days are deleted and rejected;
 * `last_used_at` is refreshed at most once per hour.
 */
export async function authenticate(db: Db, token: string | null, now: number): Promise<AuthContext | null> {
  if (token === null) return null;
  const tokenHash = await hashToken(token);
  const row = db.get<TokenRow>(
    `SELECT t.device_id, t.last_used_at, d.user_id, d.kind
       FROM tokens t JOIN devices d ON d.id = t.device_id
      WHERE t.token_hash = ?`,
    tokenHash,
  );
  if (row === undefined) return null;
  if (now - row.last_used_at > TOKEN_IDLE_TTL_MS) {
    db.run("DELETE FROM tokens WHERE token_hash = ?", tokenHash);
    return null;
  }
  if (now - row.last_used_at >= TOKEN_TOUCH_INTERVAL_MS) {
    db.run("UPDATE tokens SET last_used_at = ? WHERE token_hash = ?", now, tokenHash);
  }
  return { userId: row.user_id, deviceId: row.device_id, kind: row.kind };
}

export const requireAuth: MiddlewareHandler<AppEnv> = async (c, next) => {
  const auth = await authenticate(c.get("db"), parseBearer(c.req.header("Authorization")), c.get("now")());
  if (auth === null) throw Errors.unauthorized();
  c.set("auth", auth);
  await next();
};
```

Replace `relay/src/routes/auth.ts`:

```ts
import { Hono, type Context } from "hono";
import type { AppEnv } from "../app.js";
import { clientIp } from "../auth/client-ip.js";
import { parseDevice } from "../auth/device.js";
import { checkEmail, normalizeEmail } from "../auth/email.js";
import { hashPassword } from "../auth/password.js";
import { isAcceptablePassword, isOverlongPassword } from "../auth/password-policy.js";
import { insertToken, insertTokenIfPasswordUnchanged, requireAuth } from "../auth/session.js";
import { generateToken, hashToken, parseBearer } from "../auth/tokens.js";
import { jsonBodyLimit } from "../http/body-limit.js";
import { Errors, readJsonObject } from "../http/errors.js";
import { logMeta } from "../log.js";
import { CloseCode } from "../protocol/frames.js";

export const authRoutes = new Hono<AppEnv>();

/** Rate-limit key: X-Real-IP from nginx-proxy, else the socket address (see auth/client-ip.ts). */
function requestIp(c: Context<AppEnv>): string {
  return clientIp(c.req.header("X-Real-IP"), c.env.incoming.socket.remoteAddress);
}

let dummyPhc: Promise<string> | undefined;
/** Verifying against a throwaway hash keeps unknown-email logins as slow as wrong-password ones. */
function dummyHash(): Promise<string> {
  dummyPhc ??= hashPassword("shellx-dummy-password");
  return dummyPhc;
}

authRoutes.post("/register", jsonBodyLimit, async (c) => {
  if (!(await c.get("limiters").registerIp.limit(requestIp(c)))) throw Errors.rateLimited();
  const body = await readJsonObject(c.req.raw);
  const email = checkEmail(body.email);
  if (!email.ok) throw email.code === "invalid_email" ? Errors.invalidEmail() : Errors.disposableEmail();
  if (!isAcceptablePassword(body.password)) throw Errors.weakPassword();
  const device = parseDevice(body.device);
  if (device === null) throw Errors.invalidDevice();

  const db = c.get("db");
  if (db.get("SELECT 1 FROM users WHERE email = ?", email.email) !== undefined) throw Errors.emailTaken();
  const now = c.get("now")();
  const userId = crypto.randomUUID();
  const deviceId = crypto.randomUUID();
  const passwordHash = await c.get("passwords").hash(body.password);
  const token = generateToken();
  const tokenHash = await hashToken(token);
  try {
    db.transaction(() => {
      db.run(
        "INSERT INTO users (id, email, password_hash, password_changed_at, created_at) VALUES (?, ?, ?, ?, ?)",
        userId, email.email, passwordHash, now, now,
      );
      db.run(
        "INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
        deviceId, userId, device.kind, device.name, device.platform, device.publicKey, now,
      );
      insertToken(db, tokenHash, deviceId, now);
    });
  } catch (err) {
    if (String(err).includes("UNIQUE constraint failed: users.email")) throw Errors.emailTaken();
    throw err;
  }
  logMeta("register", { device_id: deviceId });
  return c.json({ user_id: userId, device_id: deviceId, token }, 201);
});

authRoutes.post("/login", jsonBodyLimit, async (c) => {
  const limiters = c.get("limiters");
  if (!(await limiters.loginIp.limit(requestIp(c)))) throw Errors.rateLimited();
  const body = await readJsonObject(c.req.raw);
  const email = typeof body.email === "string" ? normalizeEmail(body.email) : "";
  if (!(await limiters.loginEmail.limit(email))) throw Errors.rateLimited();
  const device = parseDevice(body.device);
  if (device === null) throw Errors.invalidDevice();
  const password = typeof body.password === "string" ? body.password : "";
  // No account can have a password over 128 code points; refuse it before argon2 sees it (I2).
  if (isOverlongPassword(password)) {
    logMeta("login_failed");
    throw Errors.invalidCredentials();
  }

  const db = c.get("db");
  const user = db.get<{ id: string; password_hash: string }>("SELECT id, password_hash FROM users WHERE email = ?", email);
  const passwordOk = await c.get("passwords").verify(password, user?.password_hash ?? (await dummyHash()));
  if (user === undefined || !passwordOk) {
    logMeta("login_failed");
    throw Errors.invalidCredentials();
  }

  const now = c.get("now")();
  // Same public key in the same account → same device_id (spec §5.2); name/platform refreshed.
  const deviceId = db.get<{ id: string }>(
    `INSERT INTO devices (id, user_id, kind, name, platform, public_key, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT (user_id, public_key) DO UPDATE SET name = excluded.name, platform = excluded.platform
     RETURNING id`,
    crypto.randomUUID(), user.id, device.kind, device.name, device.platform, device.publicKey, now,
  )!.id;
  const token = generateToken();
  const tokenHash = await hashToken(token);
  // One live token per device: logging in again replaces the previous token. Both statements only
  // apply while the password is still the one verified above: a change that committed meanwhile
  // (M1) must neither get a token minted under the old password nor sign this device out.
  const unchanged = "(SELECT password_hash FROM users WHERE id = ?) = ?";
  const inserted = db.transaction(() => {
    db.run(`DELETE FROM tokens WHERE device_id = ? AND ${unchanged}`, deviceId, user.id, user.password_hash);
    return insertTokenIfPasswordUnchanged(db, tokenHash, deviceId, now, user.id, user.password_hash);
  });
  if (inserted !== 1) {
    logMeta("login_failed", { device_id: deviceId });
    throw Errors.invalidCredentials();
  }
  logMeta("login", { device_id: deviceId });
  return c.json({ user_id: user.id, device_id: deviceId, token }, 200);
});

/**
 * POST /v1/auth/logout — deletes this token; for an agent also every pairing it owns (spec §5.2).
 *
 * Notify-before-delete (same safe order as `DELETE /v1/pairings`): every pairing is reported to the
 * hub — which durably records the tombstone for the agent before doing anything live — before any
 * row is deleted. If a hub call throws, nothing here has been deleted yet, so a retried logout can
 * still notify and delete it; a lost pairing_removed is unsafe, a duplicate is not.
 */
authRoutes.post("/logout", requireAuth, async (c) => {
  const auth = c.get("auth");
  const db = c.get("db");
  const hubs = c.get("hubs");
  const tokenHash = await hashToken(parseBearer(c.req.header("Authorization"))!);
  if (auth.kind === "agent") {
    const rows = db.all<{ mobile_id: string; pairing_id: string }>(
      "SELECT mobile_id, pairing_id FROM pairings WHERE agent_id = ?",
      auth.deviceId,
    );
    for (const row of rows) await hubs.forUser(auth.userId).notifyPairingRemoved(auth.deviceId, row.mobile_id, row.pairing_id);
    db.transaction(() => {
      db.run("DELETE FROM tokens WHERE token_hash = ?", tokenHash);
      db.run("DELETE FROM pairings WHERE agent_id = ?", auth.deviceId);
    });
    // The token and pairings are already gone: a hub failure from here on must not turn a
    // successful logout into a 500. The agent has no trust list left to reconcile against rows
    // still queued for it, so drop them best-effort, logging metadata only on failure.
    try {
      await hubs.forUser(auth.userId).purgeAgent(auth.deviceId);
    } catch {
      logMeta("agent_purge_failed", { device_id: auth.deviceId });
    }
  } else {
    db.run("DELETE FROM tokens WHERE token_hash = ?", tokenHash);
  }
  logMeta("logout", { device_id: auth.deviceId });
  return c.body(null, 204);
});

/**
 * POST /v1/auth/password {new_password} — agent token only, no old password (spec §5.2).
 * Revokes every other device's tokens and closes their sockets with 4002. Pairings are kept.
 * The sockets are closed by the hub from its own live list once the change has committed; a socket
 * that lands in the hub only after this runs is caught by the ws route's post-upgrade re-check.
 */
authRoutes.post("/password", requireAuth, jsonBodyLimit, async (c) => {
  const auth = c.get("auth");
  if (auth.kind !== "agent") throw Errors.agentOnly();
  const body = await readJsonObject(c.req.raw);
  if (!isAcceptablePassword(body.new_password)) throw Errors.weakPassword();

  const db = c.get("db");
  const now = c.get("now")();
  const passwordHash = await c.get("passwords").hash(body.new_password);
  db.transaction(() => {
    db.run("UPDATE users SET password_hash = ?, password_changed_at = ? WHERE id = ?", passwordHash, now, auth.userId);
    db.run("DELETE FROM tokens WHERE device_id IN (SELECT id FROM devices WHERE user_id = ? AND id != ?)", auth.userId, auth.deviceId);
  });
  await c.get("hubs").forUser(auth.userId).disconnectAllExcept(auth.deviceId, CloseCode.revoked);
  logMeta("password_changed", { device_id: auth.deviceId });
  return c.body(null, 204);
});
```

Replace `relay/src/routes/account.ts`:

```ts
import { Hono } from "hono";
import type { AppEnv } from "../app.js";
import { isOverlongPassword } from "../auth/password-policy.js";
import { requireAuth } from "../auth/session.js";
import { jsonBodyLimit } from "../http/body-limit.js";
import { Errors, readJsonObject } from "../http/errors.js";
import { logMeta } from "../log.js";

export const accountRoutes = new Hono<AppEnv>();

/**
 * DELETE /v1/account {password} — any signed-in device (spec §5.2, App Store 5.1.1(v)).
 * Deletes the user; devices, tokens and pairings go with it (ON DELETE CASCADE), then every
 * device's socket is closed with 4002. Password attempts share the 5/email/60 s login budget.
 */
accountRoutes.delete("/", requireAuth, jsonBodyLimit, async (c) => {
  const auth = c.get("auth");
  const body = await readJsonObject(c.req.raw);
  const db = c.get("db");
  const user = db.get<{ email: string; password_hash: string }>("SELECT email, password_hash FROM users WHERE id = ?", auth.userId);
  if (user === undefined) throw Errors.unauthorized();
  if (!(await c.get("limiters").loginEmail.limit(user.email))) throw Errors.rateLimited();
  const password = typeof body.password === "string" ? body.password : "";
  // Over 128 code points can never match; refuse it before argon2 sees it (final review I2).
  if (isOverlongPassword(password) || !(await c.get("passwords").verify(password, user.password_hash))) {
    logMeta("account_delete_denied", { device_id: auth.deviceId });
    throw Errors.invalidCredentials();
  }

  db.run("DELETE FROM users WHERE id = ?", auth.userId);
  // The delete is irreversible: a hub failure from here on must not turn a successful account
  // deletion into a 500. closeAccount() closes every socket live in the hub *now* and purges the
  // tombstones; best-effort only, logging metadata (no email) on failure.
  try {
    await c.get("hubs").forUser(auth.userId).closeAccount();
  } catch {
    logMeta("account_close_failed", { device_id: auth.deviceId });
  }
  logMeta("account_deleted", { device_id: auth.deviceId });
  return c.body(null, 204);
});
```

Replace `relay/src/routes/devices.ts`:

```ts
import { Hono } from "hono";
import type { AppEnv } from "../app.js";
import type { DeviceKind, DevicePlatform } from "../auth/device.js";
import { requireAuth } from "../auth/session.js";
import { TOKEN_IDLE_TTL_MS } from "../auth/tokens.js";

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
  const results = c.get("db").all<DeviceRow>(
    `SELECT d.id, d.kind, d.name, d.platform, d.last_seen_at,
            EXISTS (SELECT 1 FROM pairings p
                     WHERE (p.agent_id = d.id AND p.mobile_id = ?)
                        OR (p.mobile_id = d.id AND p.agent_id = ?)) AS paired_with_me
       FROM devices d
      WHERE d.user_id = ?
        AND EXISTS (SELECT 1 FROM tokens t WHERE t.device_id = d.id AND t.last_used_at >= ?)
      ORDER BY d.created_at, d.id`,
    auth.deviceId,
    auth.deviceId,
    auth.userId,
    c.get("now")() - TOKEN_IDLE_TTL_MS,
  );
  const online = new Set(await c.get("hubs").forUser(auth.userId).online());
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

Replace `relay/src/routes/pairings.ts`:

```ts
import { Hono } from "hono";
import type { AppEnv } from "../app.js";
import { requireAuth } from "../auth/session.js";
import { jsonBodyLimit } from "../http/body-limit.js";
import { Errors, readJsonObject } from "../http/errors.js";
import { parseUuid, parseUuidV7, uuidV7Millis } from "../protocol/uuid.js";

export const pairingRoutes = new Hono<AppEnv>();

/**
 * How often DELETE re-reads a row that was replaced between its read and its delete before giving
 * up with a 500 (the caller retries). Each extra round needs another re-pair landing inside the
 * same few milliseconds, so in practice the second round always settles it.
 */
const MAX_DELETE_ROUNDS = 3;

/**
 * How far a pairing id's UUIDv7 timestamp may run ahead of the relay's clock. Ids order pairings by
 * the agent's clock, so an id stamped years ahead (a clock that jumped forward) would otherwise stay
 * "newest" — refusing every later pairing of that phone — until real time caught up with it.
 */
export const MAX_PAIRING_ID_LEAD_MS = 24 * 60 * 60 * 1000;

/**
 * POST /v1/pairings {mobile_id, pairing_id} — agent only; the record is informational (trust
 * lives on the agent). `pairing_id` is a lower-case canonical UUIDv7 generated by the agent at
 * pair.confirm, one per pairing, and is what tombstones, events and the agent's revoke DELETE are
 * matched by. All ids of one (agent, mobile) pair come from that agent's clock, so a greater id is
 * a newer pairing. An id stamped more than MAX_PAIRING_ID_LEAD_MS ahead of the relay's clock is
 * refused with 410 (nothing written): the agent drops the pairing and the user pairs again once the
 * clock is fixed.
 *
 * The hub is asked before the upsert (UserHub.admitPairing): a tombstone with the same or a
 * newer id means the phone already unpaired this pairing (an earlier attempt of this POST
 * committed, its response was lost) or a newer one (this POST is stale) → 410 `pairing_removed`,
 * no row; an older tombstone is cleared, so re-pairing is never undone by a stale replay. The
 * upsert never replaces a row with a newer id (a stale POST → 410 as well). The hub is asked again
 * after the upsert, so a phone DELETE that read the fresh row and wrote its tombstone in between
 * also ends in 410 with the row removed, rather than in a row the phone already unpaired. A 410
 * removes a row only if it carries this same id. There is no best-effort path: if the hub cannot
 * be asked, the request fails with 500, since the relay cannot then tell 201 from 410 — before
 * anything is written if the first call fails, with the row possibly already recorded if the
 * re-check fails. Either way the agent retries with the same id, which converges (201 or 410).
 */
pairingRoutes.post("/", requireAuth, jsonBodyLimit, async (c) => {
  const auth = c.get("auth");
  if (auth.kind !== "agent") throw Errors.agentOnly();
  const body = await readJsonObject(c.req.raw);
  const pairingId = parseUuidV7(body.pairing_id);
  if (pairingId === null) throw Errors.badRequest();
  const mobileId = parseUuid(body.mobile_id);
  if (mobileId === null) throw Errors.deviceNotFound();
  const db = c.get("db");
  const hubs = c.get("hubs");
  const mobile = db.get("SELECT 1 FROM devices WHERE id = ? AND user_id = ? AND kind = 'mobile'", mobileId, auth.userId);
  if (mobile === undefined) throw Errors.deviceNotFound();
  if (uuidV7Millis(pairingId) > c.get("now")() + MAX_PAIRING_ID_LEAD_MS) throw Errors.pairingRemoved();

  if (await hubs.forUser(auth.userId).admitPairing(auth.deviceId, mobileId, pairingId)) {
    const upserted = db.run(
      `INSERT INTO pairings (agent_id, mobile_id, pairing_id, created_at) VALUES (?, ?, ?, ?)
       ON CONFLICT (agent_id, mobile_id) DO UPDATE SET pairing_id = excluded.pairing_id, created_at = excluded.created_at
       WHERE excluded.pairing_id >= pairings.pairing_id`,
      auth.deviceId,
      mobileId,
      pairingId,
      c.get("now")(),
    );
    // No change means the row already holds a newer pairing: this POST is stale.
    if (upserted.changes > 0 && (await hubs.forUser(auth.userId).admitPairing(auth.deviceId, mobileId, pairingId))) {
      return c.body(null, 201);
    }
  }
  // A tombstone (or the newer row) already tells the agent, so no new event is needed here.
  db.run("DELETE FROM pairings WHERE agent_id = ? AND mobile_id = ? AND pairing_id = ?", auth.deviceId, mobileId, pairingId);
  throw Errors.pairingRemoved();
});

/**
 * DELETE /v1/pairings/:agent_id/:mobile_id[?pairing_id=<uuidv7>] — either party; idempotent; notifies
 * the hub. With `pairing_id` (the agent's revoke) only the row of that pairing is deleted, so a
 * revoke that lands after a quick re-pair never removes the newer pairing; without it (the
 * phone's unpair) whatever row exists is deleted. Either way the tombstone and the event carry the
 * id of the row actually deleted.
 *
 * Notify-before-delete: the relay may only ever *remove* trust, so a failure must never lose a
 * pairing_removed event. We first read the row (scoped to the caller's account, defence in depth),
 * then call the hub — which durably records the tombstone for the agent before doing anything
 * live (see UserHub.notifyPairingRemoved) — and only then delete the row, and only if it still
 * carries the id we notified about. If the hub call throws, the row is left in place so a retry
 * finds it again and can still deliver the event; the worst case is a duplicate delivery, which
 * clients handle idempotently, never a lost one. If a re-pair replaced the row in between, nothing
 * is deleted and the row is read again: a revoke then finds another id and stops, an unpair
 * removes the new pairing too. Both 500s (hub failure; row still changing after MAX_DELETE_ROUNDS)
 * leave the row in place, and callers must retry them — the phone's unpair especially, since it is
 * the only way the agent learns about it.
 */
pairingRoutes.delete("/:agent_id/:mobile_id", requireAuth, async (c) => {
  const auth = c.get("auth");
  const agentId = parseUuid(c.req.param("agent_id"));
  const mobileId = parseUuid(c.req.param("mobile_id"));
  if (agentId === null || mobileId === null || (auth.deviceId !== agentId && auth.deviceId !== mobileId)) {
    throw Errors.forbidden();
  }
  const query = c.req.query("pairing_id");
  const only = query === undefined ? null : parseUuidV7(query);
  if (query !== undefined && only === null) throw Errors.badRequest();

  const db = c.get("db");
  const scope = "agent_id = ? AND mobile_id = ? AND agent_id IN (SELECT id FROM devices WHERE user_id = ?)";
  for (let round = 0; round < MAX_DELETE_ROUNDS; round++) {
    const row = db.get<{ pairing_id: string }>(`SELECT pairing_id FROM pairings WHERE ${scope}`, agentId, mobileId, auth.userId);
    if (row === undefined || (only !== null && row.pairing_id !== only)) return c.body(null, 204);
    await c.get("hubs").forUser(auth.userId).notifyPairingRemoved(agentId, mobileId, row.pairing_id);
    const deleted = db.run(`DELETE FROM pairings WHERE ${scope} AND pairing_id = ?`, agentId, mobileId, auth.userId, row.pairing_id);
    if (deleted.changes > 0) return c.body(null, 204);
  }
  throw new Error("pairing row kept changing");
});
```

Replace `relay/src/routes/ws.ts`:

```ts
import { randomUUID } from "node:crypto";
import { upgradeWebSocket } from "@hono/node-server";
import type { Context, MiddlewareHandler } from "hono";
import type { WebSocket } from "ws";
import type { AppEnv } from "../app.js";
import { authenticate } from "../auth/session.js";
import { parseBearer } from "../auth/tokens.js";
import type { HubSocket } from "../hub/user-hub.js";
import { Errors } from "../http/errors.js";
import { logMeta } from "../log.js";
import { CloseCode } from "../protocol/frames.js";

/** Close code for a connection the hub could not admit (its tombstones could not be read). */
export const INTERNAL_ERROR_CLOSE = 1011;

function hasUpgradeToken(connection: string | undefined): boolean {
  return (connection ?? "").split(",").some((token) => token.trim().toLowerCase() === "upgrade");
}

/**
 * GET /v1/ws, step 1 — validates the bearer token before any upgrade. A missing/revoked/expired
 * token is refused with HTTP 401 `unauthorized` (shellx_core maps it to the `revoked` state). A
 * plain GET — or one carrying `Upgrade: websocket` without `Connection: upgrade`, which Node never
 * treats as an upgrade — gets 426 `upgrade_required`.
 */
export const webSocketAuth: MiddlewareHandler<AppEnv> = async (c, next) => {
  if (c.req.header("Upgrade")?.toLowerCase() !== "websocket") throw Errors.upgradeRequired();
  const auth = await authenticate(c.get("db"), parseBearer(c.req.header("Authorization")), c.get("now")());
  if (auth === null) throw Errors.unauthorized();
  if (!hasUpgradeToken(c.req.header("Connection"))) throw Errors.upgradeRequired();
  c.set("auth", auth);
  await next();
};

/**
 * GET /v1/ws, step 2 — @hono/node-server completes the upgrade with `ws` and calls these handlers.
 * The socket joins the account's hub; `ping` is answered right here, outside the hub's queue
 * (spec §4.2). Only the validated token decides the device id and kind; nothing the client sends
 * in headers reaches the hub.
 */
export const webSocketUpgrade = upgradeWebSocket(
  (context) => {
    const c = context as Context<AppEnv>; // node-server types the context loosely
    const auth = c.get("auth");
    const db = c.get("db");
    const hubs = c.get("hubs");
    const now = c.get("now");
    const token = parseBearer(c.req.header("Authorization"));
    const connId = randomUUID();
    let socket: HubSocket | null = null;

    const admit = async (joined: HubSocket): Promise<void> => {
      try {
        await hubs.forUser(auth.userId).connect(joined, { deviceId: auth.deviceId, kind: auth.kind, connId });
      } catch {
        logMeta("ws_join_failed", { device_id: auth.deviceId });
        try {
          joined.close(INTERNAL_ERROR_CLOSE, "internal_error");
        } catch {
          // already closed
        }
        return;
      }
      // TOCTOU guard: a revocation (password change, account deletion) can commit — and run its own
      // disconnect — between the authenticate() above and this socket joining the hub. Re-validate
      // the same token now that the socket is live, and close exactly this connection (never
      // whatever socket the device has by now) if it is no longer valid. A re-check that cannot
      // complete (database error) fails closed, the same as "revoked".
      try {
        if ((await authenticate(db, token, now())) === null) {
          await hubs.forUser(auth.userId).closeConnection(connId, CloseCode.revoked);
        }
      } catch {
        logMeta("ws_recheck_failed", { device_id: auth.deviceId });
        try {
          await hubs.forUser(auth.userId).closeConnection(connId, CloseCode.revoked);
        } catch {
          // Nothing more to do; the hub logged the failure by kind.
        }
      }
    };

    return {
      onOpen(_event, ws) {
        socket = ws.raw as unknown as WebSocket;
        void admit(socket);
      },
      onMessage(event, ws) {
        if (socket === null) return;
        if (event.data === "ping") {
          ws.send("pong");
          return;
        }
        const data = event.data;
        hubs.forUser(auth.userId).receive(socket, typeof data === "string" || data instanceof ArrayBuffer ? data : "");
      },
      onClose() {
        if (socket !== null) hubs.forUser(auth.userId).disconnected(socket);
      },
    };
  },
  { onError: () => logMeta("ws_handler_error") },
);
```

Replace `relay/src/app.ts`:

```ts
import type { IncomingMessage } from "node:http";
import { Hono } from "hono";
import type { PasswordHasher } from "./auth/password.js";
import { passwords as defaultPasswords } from "./auth/password.js";
import type { RateLimiters } from "./auth/rate-limit.js";
import type { AuthContext } from "./auth/session.js";
import type { Config } from "./config.js";
import type { Db } from "./db/db.js";
import type { HubRegistry } from "./hub/registry.js";
import { ApiError, errorBody, Errors } from "./http/errors.js";
import { errorKind, logMeta } from "./log.js";
import { accountRoutes } from "./routes/account.js";
import { authRoutes } from "./routes/auth.js";
import { deviceRoutes } from "./routes/devices.js";
import { pairingRoutes } from "./routes/pairings.js";
import { webSocketAuth, webSocketUpgrade } from "./routes/ws.js";

export interface AppDeps {
  config: Config;
  db: Db;
  hubs: HubRegistry;
  limiters: RateLimiters;
  /** Defaults to the process-wide argon2id hasher (at most 4 hashes at once). */
  passwords?: PasswordHasher;
  /** Unix milliseconds; injectable for token-expiry tests. */
  now?: () => number;
}

export interface AppVariables {
  config: Config;
  db: Db;
  hubs: HubRegistry;
  limiters: RateLimiters;
  passwords: PasswordHasher;
  now: () => number;
  /** Set by `requireAuth` / `webSocketAuth` on authenticated routes only. */
  auth: AuthContext;
}

/** What @hono/node-server passes as `c.env`; `incoming.socket.remoteAddress` is the TCP peer. */
export interface AppBindings {
  incoming: IncomingMessage;
}

export type AppEnv = { Bindings: AppBindings; Variables: AppVariables };

export function createApp(deps: AppDeps): Hono<AppEnv> {
  const app = new Hono<AppEnv>();

  app.use("*", async (c, next) => {
    c.set("config", deps.config);
    c.set("db", deps.db);
    c.set("hubs", deps.hubs);
    c.set("limiters", deps.limiters);
    c.set("passwords", deps.passwords ?? defaultPasswords);
    c.set("now", deps.now ?? Date.now);
    await next();
  });

  app.get("/v1/version", (c) => {
    const config = c.get("config");
    return c.json({
      min_agent: config.minAgent,
      min_mobile: config.minMobile,
      latest_agent: { version: config.latestAgentVersion, mac_url: config.macUrl, win_url: config.winUrl },
    });
  });

  app.route("/v1/auth", authRoutes);
  app.route("/v1/account", accountRoutes);
  app.route("/v1/devices", deviceRoutes);
  app.route("/v1/pairings", pairingRoutes);
  app.get("/v1/ws", webSocketAuth, webSocketUpgrade);

  app.notFound((c) => {
    const e = Errors.notFound();
    return c.json(errorBody(e.code, e.message), e.status);
  });

  app.onError((err, c) => {
    if (err instanceof ApiError) return c.json(errorBody(err.code, err.message), err.status);
    logMeta("unhandled_error", { method: c.req.method, path: new URL(c.req.url).pathname, error: errorKind(err) });
    return c.json(errorBody("internal_error", "Internal error"), 500);
  });

  return app;
}
```

Replace `relay/src/relay.ts` (adds the `ws` server; Task 5 adds `shutdown`):

```ts
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { createAdaptorServer } from "@hono/node-server";
import { WebSocketServer } from "ws";
import { createApp, type AppDeps } from "./app.js";

/**
 * Largest WebSocket message `ws` will read (Cloudflare's limit was also 1 MiB). Frames above
 * MAX_FRAME_BYTES (64 KiB) up to this size still reach the hub and get ERROR frame_too_large;
 * anything larger closes the socket with 1009.
 */
export const MAX_WS_MESSAGE_BYTES = 1024 * 1024;

export interface ListenOptions {
  host: string;
  /** 0 picks a free port (tests). */
  port: number;
}

export interface RunningRelay {
  readonly server: Server;
  readonly port: number;
  /** `http://<host>:<port>` */
  readonly url: string;
}

/**
 * Serves the app on `listen`. @hono/node-server hands `upgrade` events for `/v1/ws` to the Hono
 * route, and completes the handshake with this `ws` server once the route validated the token.
 */
export async function startRelay(deps: AppDeps, listen: ListenOptions): Promise<RunningRelay> {
  const app = createApp(deps);
  const wss = new WebSocketServer({
    noServer: true,
    maxPayload: MAX_WS_MESSAGE_BYTES,
    perMessageDeflate: false,
    clientTracking: false,
  });
  const server = createAdaptorServer({ fetch: app.fetch, websocket: { server: wss } }) as Server;
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(listen.port, listen.host, () => {
      server.off("error", reject);
      resolve();
    });
  });
  const { port } = server.address() as AddressInfo;
  const host = listen.host.includes(":") ? `[${listen.host}]` : listen.host;
  return { server, port, url: `http://${host}:${port}` };
}
```

In `relay/tsconfig.json` delete these lines from `exclude` (only `"scripts/reset-password.ts"` and `"test/reset-password.test.ts"` stay):

```jsonc
    "src/auth/session.ts",
    "src/routes",
    "test/account.test.ts",
    "test/auth.test.ts",
    "test/devices-pairings.test.ts",
    "test/hub.test.ts",
    "test/limits.test.ts",
    "test/rate-limit.test.ts",
```

- [ ] **Step 5: Run the tests and the type check**

Run: `npx vitest run test/hub.test.ts test/auth.test.ts test/account.test.ts test/devices-pairings.test.ts test/limits.test.ts test/rate-limit.test.ts`
Expected: PASS (6 files).

Run: `npm run typecheck && npm test`
Expected: `Test Files  14 passed (14)`, `Tests  239 passed (239)`. Run `npm test` twice more: the WebSocket tests must not be flaky.

- [ ] **Step 6: Commit**

```bash
git add -A relay
git commit -m "feat(relay): REST routes on SQLite and the in-process hub; /v1/ws via @hono/node-server + ws"
```

### Task 5: Server entry, graceful shutdown, admin scripts, dependency cleanup

`src/server.ts` becomes the container entry (`node dist/server.js`): configuration (one-line error, exit 1), database + migrations (one-line error, exit 1 — Review Focus 5), `startRelay`, and SIGTERM/SIGINT handling through `relay.shutdown()`. `reset-password` moves into `src/scripts/` and talks to SQLite directly (no wrangler, no SQL printed; the old "unconfirmed" outcome disappears because the result of a direct transaction is always known). Wrangler goes away, `npm run dev` serves `127.0.0.1:8787`, and the README is rewritten for Node/VPS.

**Files:**
- Create: `relay/src/server.ts`, `relay/src/scripts/reset-db.ts`, `relay/dev.env`, `relay/tsconfig.build.json`, `relay/test/server.test.ts`
- Move: `relay/scripts/prompter.ts`, `relay/scripts/line-prompter.ts`, `relay/scripts/reset-cli.ts`, `relay/scripts/reset-password.ts` → `relay/src/scripts/`
- Modify: `relay/src/relay.ts` (final), `relay/src/scripts/line-prompter.ts` (comment), `relay/src/scripts/reset-cli.ts`, `relay/src/scripts/reset-password.ts`, `relay/test/reset-password.test.ts`, `relay/package.json`, `relay/package-lock.json`, `relay/tsconfig.json` (final), `relay/vitest.config.ts` (final), `relay/.gitignore`, `relay/README.md`
- Delete: `relay/wrangler.jsonc`, `relay/scripts/reset-sql.ts`
- Unchanged, still in `relay/scripts/`: `blocklist.ts`, `update-disposable-domains.ts`

**Interfaces:**
- Consumes: everything from Tasks 1–4 (`loadConfig`, `ConfigError`, `Db`, `migrate`, `HubRegistry.goAway/terminateAll/whenEmpty`, `createRateLimiters`, `hashPassword`, `errorKind`, `createApp`).
- Produces:
  - `src/relay.ts`: `SHUTDOWN_GRACE_MS = 5000`; `RunningRelay.shutdown(graceMs?: number): Promise<void>` — stops accepting connections, closes every socket with 1001, waits for in-flight requests and hub queues (at most `graceMs`), then drops what is left; the caller closes the database.
  - `src/server.ts`: process entry; logs `relay_started` (with `port`), `relay_stopping` (with `signal`), `relay_stopped`; exits 1 with `relay: missing required environment variable…`, `relay: PORT must be…` or `relay: cannot open database at <path> (<kind>)`; hard exit after 9 s if a shutdown hangs.
  - `src/scripts/reset-db.ts`: `type ResetOutcome = "reset" | "no_account"`, `resetPassword(db: Db, email: string, phc: string, now: number, revokeTokens: boolean): ResetOutcome`.
  - `src/scripts/reset-cli.ts`: `needsConfirmation(yes: boolean): boolean`, `confirmationMatches(expected, typed)`, `choosePasswordSource(argv?, env?)`, `failureMessage(err: unknown): string` (`database error (<kind>)`), `interface ResetReport`, `resetReport(outcome, ctx)`.
  - `node dist/scripts/reset-password.js --email <address> [--password <new>|-] [--revoke-tokens] [--yes]` (database = `DB_PATH`, default `/data/relay.db`; refuses to create it).
  - npm scripts: `build` (`tsc -p tsconfig.build.json` → `dist/server.js`, `dist/scripts/reset-password.js`), `dev`, `test`, `typecheck`, `domains:update`, `reset-password`.

- [ ] **Step 1: Remove wrangler and set the scripts**

```bash
npm uninstall wrangler
npm pkg delete scripts.db:migrate:local scripts.db:migrate:staging scripts.db:migrate:production scripts.deploy:staging scripts.deploy:production
npm pkg set scripts.build="tsc -p tsconfig.build.json" scripts.dev="node --env-file=dev.env --import tsx src/server.ts" scripts.reset-password="node --env-file=dev.env --import tsx src/scripts/reset-password.ts"
git rm -q wrangler.jsonc scripts/reset-sql.ts
mkdir -p src/scripts
git mv scripts/prompter.ts scripts/line-prompter.ts scripts/reset-cli.ts scripts/reset-password.ts src/scripts/
```

`relay/package.json` must now contain exactly these values (npm may order the `scripts` keys differently):

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
    "build": "tsc -p tsconfig.build.json",
    "dev": "node --env-file=dev.env --import tsx src/server.ts",
    "test": "vitest run",
    "typecheck": "tsc -p tsconfig.json",
    "domains:update": "tsx scripts/update-disposable-domains.ts",
    "reset-password": "node --env-file=dev.env --import tsx src/scripts/reset-password.ts"
  },
  "dependencies": {
    "@hono/node-server": "2.1.1",
    "@node-rs/argon2": "2.2.1",
    "better-sqlite3": "13.0.3",
    "hono": "^4.13.9",
    "ws": "8.22.0"
  },
  "devDependencies": {
    "@types/better-sqlite3": "9.6.0",
    "@types/node": "22.20.4",
    "@types/ws": "8.18.1",
    "tsx": "^4.23.15",
    "typescript": "^5.9.3",
    "vitest": "~4.1.11"
  }
}
```

- [ ] **Step 2: Write the failing tests**

Create `relay/test/server.test.ts` (it pins Review Focus 2 — "lets an in-flight REST call that touches the hub finish…" — and Review Focus 5 — "startup failures exit 1 with a one-line error"; the read-only-directory case is skipped only when the tests run as root):

```ts
import { type ChildProcess, spawn } from "node:child_process";
import { chmodSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { passwords, type PasswordHasher } from "../src/auth/password.js";
import { Db } from "../src/db/db.js";
import { HubRegistry } from "../src/hub/registry.js";
import { GOING_AWAY } from "../src/hub/user-hub.js";
import { pairingRemovedEvent } from "../src/protocol/frames.js";
import type { RunningRelay } from "../src/relay.js";
import {
  call, connect, db, hex, loginDevice, makeApp, newPairingId, pair, registerAccount, tempDir, type TestApp,
} from "./helpers.js";

const RELAY_DIR = join(import.meta.dirname, "..");

const VERSION_ENV = {
  MIN_AGENT: "1.0.0",
  MIN_MOBILE: "1.0.0",
  LATEST_AGENT_VERSION: "1.0.0",
  MAC_URL: "https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg",
  WIN_URL: "https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe",
};

interface Exit {
  code: number | null;
  stdout: string;
  stderr: string;
}

/** Starts `src/server.ts` (through tsx) with exactly `env` (plus PATH/HOME). */
function startServer(env: Record<string, string>): { child: ChildProcess; exit: Promise<Exit>; output: () => string } {
  const child = spawn(process.execPath, ["--import", "tsx", "src/server.ts"], {
    cwd: RELAY_DIR,
    env: { PATH: process.env.PATH ?? "", HOME: process.env.HOME ?? "", ...env },
  });
  let stdout = "";
  let stderr = "";
  child.stdout!.on("data", (chunk: Buffer) => (stdout += chunk.toString("utf8")));
  child.stderr!.on("data", (chunk: Buffer) => (stderr += chunk.toString("utf8")));
  const exit = new Promise<Exit>((resolve) => child.on("exit", (code) => resolve({ code, stdout, stderr })));
  return { child, exit, output: () => stdout };
}

async function waitForListening(output: () => string): Promise<number> {
  for (let i = 0; i < 200; i++) {
    const match = /"event":"relay_started","port":(\d+)/.exec(output());
    if (match) return Number(match[1]);
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error(`relay did not start: ${output()}`);
}

/** A TestApp for a relay started elsewhere: `call` and `connect` only need its port. */
function remote(port: number): TestApp {
  return { ready: Promise.resolve({ port, url: `http://127.0.0.1:${port}` } as RunningRelay) };
}

describe("startup failures exit 1 with a one-line error", () => {
  it("a missing required variable", async () => {
    const { MIN_AGENT: _missing, ...rest } = VERSION_ENV;
    const { exit } = startServer({ ...rest, HOST: "127.0.0.1", PORT: "8799", DB_PATH: join(tempDir(), "relay.db") });
    const result = await exit;
    expect(result.code).toBe(1);
    expect(result.stderr).toBe("relay: missing required environment variable: MIN_AGENT\n");
    expect(result.stdout).not.toContain("relay_started");
  });

  it("a database path whose directory is a regular file (volume mounted wrong)", async () => {
    const file = join(tempDir(), "not-a-directory");
    writeFileSync(file, "x");
    const { exit } = startServer({ ...VERSION_ENV, HOST: "127.0.0.1", PORT: "0", DB_PATH: join(file, "relay.db") });
    const result = await exit;
    expect(result.code).toBe(1);
    expect(result.stderr).toMatch(/^relay: cannot open database at .*not-a-directory\/relay\.db \((ENOTDIR|EEXIST)\)\n$/);
  });

  it("a file that is not a SQLite database", async () => {
    const path = join(tempDir(), "garbage.db");
    writeFileSync(path, "this is not a database ".repeat(100));
    const { exit } = startServer({ ...VERSION_ENV, HOST: "127.0.0.1", PORT: "0", DB_PATH: path });
    const result = await exit;
    expect(result.code).toBe(1);
    expect(result.stderr).toBe(`relay: cannot open database at ${path} (SQLITE_NOTADB)\n`);
  });

  it.skipIf(process.getuid?.() === 0)("a read-only data directory (the container user cannot write the volume)", async () => {
    const dir = join(tempDir(), "readonly");
    mkdirSync(dir);
    chmodSync(dir, 0o555);
    try {
      const { exit } = startServer({ ...VERSION_ENV, HOST: "127.0.0.1", PORT: "0", DB_PATH: join(dir, "relay.db") });
      const result = await exit;
      expect(result.code).toBe(1);
      expect(result.stderr).toBe(`relay: cannot open database at ${join(dir, "relay.db")} (SQLITE_CANTOPEN)\n`);
    } finally {
      chmodSync(dir, 0o755);
    }
  });
});

describe("graceful shutdown (spec §4.3)", () => {
  it("on SIGTERM closes every socket with 1001, refuses new connections and exits 0", async () => {
    const dbPath = join(tempDir(), "relay.db");
    const server = startServer({ ...VERSION_ENV, HOST: "127.0.0.1", PORT: "0", DB_PATH: dbPath, RATE_LIMITS_ENABLED: "false" });
    const port = await waitForListening(server.output);
    const app = remote(port);
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const a = await connect(app, account.agent.token);
    const m = await connect(app, mobile.token);

    const started = Date.now();
    server.child.kill("SIGTERM");
    expect(await a.closed).toEqual({ code: GOING_AWAY, reason: "going away" });
    expect(await m.closed).toEqual({ code: GOING_AWAY, reason: "going away" });
    const result = await server.exit;
    expect(result.code).toBe(0);
    expect(Date.now() - started).toBeLessThan(10_000);
    expect(result.stdout).toContain('"event":"relay_stopping","signal":"SIGTERM"');
    expect(result.stdout).toContain('"event":"relay_stopped"');
    await expect(call(app, "GET", "/v1/version")).rejects.toThrow(/ECONNREFUSED/);

    // Everything committed before the signal is on disk.
    const reopened = Db.open(dbPath, { fileMustExist: true });
    try {
      expect(reopened.get("SELECT COUNT(*) AS n FROM devices")).toEqual({ n: 2 });
    } finally {
      reopened.close();
    }
  }, 30_000);

  it("lets an in-flight REST call that touches the hub finish before the database closes", async () => {
    let releaseHash: () => void = () => {};
    const gate = new Promise<void>((resolve) => (releaseHash = resolve));
    let hashing: () => void = () => {};
    const hashStarted = new Promise<void>((resolve) => (hashing = resolve));
    const gatedPasswords: PasswordHasher = {
      hash: async (password) => {
        hashing();
        await gate;
        return passwords.hash(password);
      },
      verify: (password, phc) => passwords.verify(password, phc),
    };
    const app = makeApp();
    const account = await registerAccount(app);
    const mobile = await loginDevice(app, account, "mobile");
    const relay = await makeApp({ passwords: gatedPasswords }).ready;
    const gated = remote(relay.port);
    const m = await connect(gated, mobile.token);

    const change = call(gated, "POST", "/v1/auth/password", { token: account.agent.token, body: { new_password: "brand new password" } });
    await hashStarted; // the request is now in flight, inside argon2
    const stopped = relay.shutdown(5000);
    expect(await m.closed).toEqual({ code: GOING_AWAY, reason: "going away" });
    let finished = false;
    void stopped.then(() => (finished = true));
    await new Promise((resolve) => setTimeout(resolve, 100));
    expect(finished).toBe(false); // still waiting for the request

    releaseHash();
    expect((await change).status).toBe(204); // completed normally, not a 500
    await stopped;
    const login = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: "brand new password", device: { kind: "mobile", name: "x", platform: "ios", public_key: mobile.publicKey } },
    });
    expect(login.status).toBe(200);
  });

  it("gives up waiting after the grace period and drops sockets that never answered", async () => {
    const hubs = new HubRegistry({ db: db() });
    const relay = await makeApp({ hubs }).ready;
    const app = remote(relay.port);
    const account = await registerAccount(app);
    const a = await connect(app, account.agent.token);
    a.ws.pause(); // never reads the close frame, so never answers it
    const started = Date.now();
    await relay.shutdown(300);
    expect(Date.now() - started).toBeLessThan(2000);
    a.ws.resume();
    expect((await a.closed).code).toBeGreaterThan(0);
  });
});

describe("restart", () => {
  it("keeps pairing_removed tombstones: a fresh relay on the same database replays them", async () => {
    const before = makeApp();
    const account = await registerAccount(before);
    const mobile = await loginDevice(before, account, "mobile");
    const pairingId = newPairingId();
    await pair(before, account.agent.token, mobile.deviceId, pairingId);
    expect((await call(before, "DELETE", `/v1/pairings/${account.agent.deviceId}/${mobile.deviceId}`, { token: mobile.token })).status).toBe(204);

    // A new process: new database connection, new (empty) in-memory hubs.
    const reopened = Db.open(join(tempDir(), "relay.db"));
    const after = makeApp({ db: reopened, hubs: new HubRegistry({ db: reopened }) });
    const a = await connect(after, account.agent.token);
    expect(hex(await a.nextBinary())).toBe(hex(pairingRemovedEvent(account.agent.deviceId, mobile.deviceId, pairingId)));
    await a.expectSilence();
    a.close();
    await a.closed;
    await (await after.ready).shutdown(1000);
    reopened.close();
  });
});
```

Replace `relay/test/reset-password.test.ts`:

```ts
import { spawnSync } from "node:child_process";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { hashPassword } from "../src/auth/password.js";
import { createLinePrompter } from "../src/scripts/line-prompter.js";
import {
  choosePasswordSource, confirmationMatches, failureMessage, needsConfirmation, resetReport,
} from "../src/scripts/reset-cli.js";
import { resetPassword } from "../src/scripts/reset-db.js";
import { call, db, deviceBody, loginDevice, makeApp, registerAccount, tempDir } from "./helpers.js";

const RELAY_DIR = join(import.meta.dirname, "..");

describe("resetPassword (SQLite)", () => {
  it("sets a new password, reports the account, and optionally revokes every token", async () => {
    const app = makeApp();
    const account = await registerAccount(app, `o'brien-${crypto.randomUUID()}@example.com`);
    const mobile = await loginDevice(app, account, "mobile");
    expect(resetPassword(db(), account.email, await hashPassword("reset by support"), 1_900_000_000_000, true)).toBe("reset");

    const login = (password: string) =>
      call(app, "POST", "/v1/auth/login", { body: { email: account.email, password, device: deviceBody("mobile") } });
    expect((await login(account.password)).status).toBe(401);
    expect((await login("reset by support")).status).toBe(200);
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(401);
    expect((await call(app, "GET", "/v1/devices", { token: mobile.token })).status).toBe(401);
    expect(db().get("SELECT password_changed_at FROM users WHERE id = ?", account.agent.userId)).toEqual({
      password_changed_at: 1_900_000_000_000,
    });
  });

  it("keeps the tokens (and pairings) without revokeTokens", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    expect(resetPassword(db(), account.email, await hashPassword("reset by support"), 1, false)).toBe("reset");
    expect((await call(app, "GET", "/v1/devices", { token: account.agent.token })).status).toBe(200);
  });

  it("reports no_account for an unknown e-mail and changes nothing", () => {
    expect(resetPassword(db(), "nobody@example.com", "$argon2id$x", 1, true)).toBe("no_account");
  });

  it("rejects a non-integer timestamp", () => {
    expect(() => resetPassword(db(), "a@b.co", "x", 1.5, false)).toThrow(TypeError);
  });
});

describe("resetReport", () => {
  const ctx = { email: "user@example.com", target: "/data/relay.db", revokeTokens: false };

  it("reset: confirms, prints a generated password and the revocation note, exit 0", () => {
    expect(resetReport("reset", { ...ctx, generatedPassword: "Tmp-Pass_123", revokeTokens: true })).toEqual({
      stdout: [
        "Password reset for user@example.com in /data/relay.db.",
        "Temporary password: Tmp-Pass_123",
        "All device tokens of this account were revoked.",
      ],
      stderr: [],
      exitCode: 0,
    });
    expect(resetReport("reset", ctx).stdout).toEqual(["Password reset for user@example.com in /data/relay.db."]);
  });

  it("no_account: says nothing changed, never prints the password, exit 1", () => {
    expect(resetReport("no_account", { ...ctx, generatedPassword: "Tmp-Pass_123" })).toEqual({
      stdout: [],
      stderr: ["No account with email user@example.com in /data/relay.db; nothing changed."],
      exitCode: 1,
    });
  });
});

describe("failureMessage", () => {
  it("reports only the SQLite code or the error class, never the message", () => {
    const busy = Object.assign(new Error("database is locked: UPDATE users SET password_hash = '$argon2id$…' WHERE email = 'user@example.com'"), {
      code: "SQLITE_BUSY",
    });
    expect(failureMessage(busy)).toBe("database error (SQLITE_BUSY)");
    expect(failureMessage(new TypeError("user@example.com"))).toBe("database error (TypeError)");
    expect(failureMessage("boom user@example.com")).toBe("database error (unknown)");
    expect(failureMessage(null)).toBe("database error (unknown)");
  });
});

describe("needsConfirmation", () => {
  it("asks unless --yes", () => {
    expect(needsConfirmation(false)).toBe(true);
    expect(needsConfirmation(true)).toBe(false);
  });
});

describe("confirmationMatches", () => {
  it("matches after trimming and normalising the case", () => {
    expect(confirmationMatches("test@example.com", "test@example.com")).toBe(true);
    expect(confirmationMatches("test@example.com", "  test@example.com  ")).toBe(true);
    expect(confirmationMatches("test@example.com", "Test@Example.com")).toBe(true);
    expect(confirmationMatches("test@example.com", "other@example.com")).toBe(false);
  });
});

describe("choosePasswordSource", () => {
  it("prefers argv '-' (stdin), then an argv value, then the env var, else generates", () => {
    expect(choosePasswordSource("-")).toBe("stdin");
    expect(choosePasswordSource("mypassword")).toBe("argv");
    expect(choosePasswordSource(undefined, "envpassword")).toBe("env");
    expect(choosePasswordSource()).toBe("generate");
    expect(choosePasswordSource("-", "envpassword")).toBe("stdin");
    expect(choosePasswordSource("argvpass", "envpassword")).toBe("argv");
  });
});

describe("createLinePrompter", () => {
  it("returns answers in order and writes each question", async () => {
    const written: string[] = [];
    const prompter = createLinePrompter("answer1\r\nanswer2\n", (s) => written.push(s));
    expect(await prompter.ask("Question 1: ")).toBe("answer1");
    expect(await prompter.ask("Question 2: ")).toBe("answer2");
    expect(written).toEqual(["Question 1: ", "Question 2: "]);
    await expect(prompter.ask("Question 3: ")).rejects.toThrow("stdin ended before an answer was given");
    expect(() => prompter.close()).not.toThrow();
  });

  it("rejects on empty input", async () => {
    await expect(createLinePrompter("", () => {}).ask("Q: ")).rejects.toThrow("stdin ended before an answer was given");
  });
});

/** Runs the real script (through tsx) against `dbPath`; stdin is `input`. */
function runScript(dbPath: string, args: string[], input = "", env: Record<string, string> = {}) {
  const result = spawnSync(process.execPath, ["--import", "tsx", "src/scripts/reset-password.ts", ...args], {
    cwd: RELAY_DIR,
    input,
    encoding: "utf8",
    env: { ...process.env, DB_PATH: dbPath, ...env },
    timeout: 20_000,
  });
  return { status: result.status, stdout: result.stdout, stderr: result.stderr };
}

describe("reset-password script (end to end)", () => {
  it("resets through the typed confirmation, prints one-line results, and never prints SQL", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const dbPath = join(tempDir(), "relay.db");
    const run = runScript(dbPath, ["--email", account.email, "--password", "-", "--revoke-tokens"], `a new password\n${account.email}\n`);
    expect(run.stderr).not.toMatch(/SELECT|UPDATE|DELETE/);
    expect(run.stdout.trim().split("\n")).toEqual([
      `Password reset for ${account.email} in ${dbPath}.`,
      "All device tokens of this account were revoked.",
    ]);
    expect(run.status).toBe(0);
    const login = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: "a new password", device: deviceBody("mobile") },
    });
    expect(login.status).toBe(200);
  });

  it("aborts on a mismatched confirmation, and exits 1 for an unknown account", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const dbPath = join(tempDir(), "relay.db");
    const mismatch = runScript(dbPath, ["--email", account.email], "someone-else@example.com\n");
    expect(mismatch.status).toBe(1);
    expect(mismatch.stderr).toContain("Email mismatch; operation aborted.");
    const unknown = runScript(dbPath, ["--email", "nobody@example.com", "--yes"]);
    expect(unknown.status).toBe(1);
    expect(unknown.stderr).toContain(`No account with email nobody@example.com in ${dbPath}; nothing changed.`);
    expect(unknown.stdout).not.toContain("Temporary password");
  });

  it("refuses to create a database that does not exist, in one line", () => {
    const missing = join(tempDir(), "nope", "relay.db");
    const run = runScript(missing, ["--email", "user@example.com", "--yes"]);
    expect(run.status).toBe(1);
    expect(run.stderr.trim().split("\n").at(-1)).toBe(`cannot open database at ${missing} (ENOENT)`);
  });

  it("generates and prints a temporary password when none is given", async () => {
    const app = makeApp();
    const account = await registerAccount(app);
    const run = runScript(join(tempDir(), "relay.db"), ["--email", account.email, "--yes"]);
    expect(run.status).toBe(0);
    const temporary = /Temporary password: ([A-Za-z0-9_-]{16})/.exec(run.stdout)?.[1];
    expect(temporary).toBeDefined();
    const login = await call(app, "POST", "/v1/auth/login", {
      body: { email: account.email, password: temporary, device: deviceBody("mobile") },
    });
    expect(login.status).toBe(200);
  });
});

```

Replace `relay/vitest.config.ts` (no more porting list):

```ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Each test file runs in its own child process: better-sqlite3 and @node-rs/argon2 are native
    // addons, and the server tests spawn `src/server.ts` with signals.
    pool: "forks",
    include: ["test/**/*.test.ts"],
    testTimeout: 15_000,
    hookTimeout: 15_000,
  },
});
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `npx vitest run test/server.test.ts test/reset-password.test.ts`
Expected: FAIL — `Error: Cannot find module '../src/scripts/reset-db.js' imported from …/test/reset-password.test.ts`; in `server.test.ts` the spawned `src/server.ts` does not exist (exit codes and stderr do not match) and `relay.shutdown is not a function`.

- [ ] **Step 4: Implement shutdown, the entry point and the reset tooling**

Replace `relay/src/relay.ts`:

```ts
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { createAdaptorServer } from "@hono/node-server";
import { WebSocketServer } from "ws";
import { createApp, type AppDeps } from "./app.js";

/**
 * Largest WebSocket message `ws` will read (Cloudflare's limit was also 1 MiB). Frames above
 * MAX_FRAME_BYTES (64 KiB) up to this size still reach the hub and get ERROR frame_too_large;
 * anything larger closes the socket with 1009.
 */
export const MAX_WS_MESSAGE_BYTES = 1024 * 1024;

/** Shutdown waits at most this long for sockets to close and requests to finish (spec §4.3). */
export const SHUTDOWN_GRACE_MS = 5000;

export interface ListenOptions {
  host: string;
  /** 0 picks a free port (tests). */
  port: number;
}

export interface RunningRelay {
  readonly server: Server;
  readonly port: number;
  /** `http://<host>:<port>` */
  readonly url: string;
  /**
   * Graceful stop (spec §4.3): stops accepting connections, closes every socket with 1001, waits
   * for in-flight requests and hub queues (at most `graceMs`), then drops whatever is left. The
   * caller closes the database afterwards.
   */
  shutdown(graceMs?: number): Promise<void>;
}

/** Counts requests in flight so shutdown can wait for them. */
class Inflight {
  private count = 0;
  private waiters: (() => void)[] = [];

  async track<T>(work: () => Promise<T>): Promise<T> {
    this.count++;
    try {
      return await work();
    } finally {
      this.count--;
      if (this.count === 0) for (const resolve of this.waiters.splice(0)) resolve();
    }
  }

  idle(): Promise<void> {
    return this.count === 0 ? Promise.resolve() : new Promise((resolve) => this.waiters.push(resolve));
  }
}

/**
 * Serves the app on `listen`. @hono/node-server hands `upgrade` events for `/v1/ws` to the Hono
 * route, and completes the handshake with this `ws` server once the route validated the token.
 */
export async function startRelay(deps: AppDeps, listen: ListenOptions): Promise<RunningRelay> {
  const app = createApp(deps);
  const inflight = new Inflight();
  const wss = new WebSocketServer({
    noServer: true,
    maxPayload: MAX_WS_MESSAGE_BYTES,
    perMessageDeflate: false,
    clientTracking: false,
  });
  const server = createAdaptorServer({
    fetch: (request, env) => inflight.track(async () => app.fetch(request, env)),
    websocket: { server: wss },
  }) as Server;

  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(listen.port, listen.host, () => {
      server.off("error", reject);
      resolve();
    });
  });
  const { port } = server.address() as AddressInfo;
  const host = listen.host.includes(":") ? `[${listen.host}]` : listen.host;

  let stopping: Promise<void> | null = null;
  return {
    server,
    port,
    url: `http://${host}:${port}`,
    shutdown(graceMs = SHUTDOWN_GRACE_MS) {
      stopping ??= (async () => {
        server.close(); // no new connections; idle keep-alive connections are closed too
        server.closeIdleConnections();
        let timer: NodeJS.Timeout | undefined;
        const deadline = new Promise<void>((resolve) => {
          timer = setTimeout(resolve, graceMs);
        });
        await Promise.race([Promise.all([deps.hubs.goAway(), inflight.idle()]), deadline]);
        clearTimeout(timer);
        deps.hubs.terminateAll();
        server.closeAllConnections();
      })();
      return stopping;
    },
  };
}
```

Create `relay/src/server.ts`:

```ts
// Entry point of the relay container: `node dist/server.js` (dev: `npm run dev`).
import { createRateLimiters } from "./auth/rate-limit.js";
import { ConfigError, loadConfig, type Config } from "./config.js";
import { Db } from "./db/db.js";
import { migrate } from "./db/migrate.js";
import { HubRegistry } from "./hub/registry.js";
import { errorKind, logMeta } from "./log.js";
import { startRelay } from "./relay.js";

/** Hard stop if a graceful shutdown hangs; stays under Compose's 10 s stop_grace_period. */
const FORCE_EXIT_MS = 9000;

function fail(message: string): never {
  console.error(`relay: ${message}`);
  process.exit(1);
}

let config: Config;
try {
  config = loadConfig(process.env);
} catch (err) {
  fail(err instanceof ConfigError ? err.message : "invalid configuration");
}

let db: Db;
try {
  db = Db.open(config.dbPath);
  migrate(db);
} catch (err) {
  fail(`cannot open database at ${config.dbPath} (${errorKind(err)})`);
}

const hubs = new HubRegistry({ db });
const relay = await startRelay(
  { config, db, hubs, limiters: createRateLimiters(config) },
  { host: config.host, port: config.port },
).catch((err: unknown) => fail(`cannot listen on ${config.host}:${config.port} (${errorKind(err)})`));
logMeta("relay_started", { port: relay.port });

let stopping = false;
async function stop(signal: string): Promise<void> {
  if (stopping) return;
  stopping = true;
  logMeta("relay_stopping", { signal });
  setTimeout(() => process.exit(1), FORCE_EXIT_MS).unref();
  await relay.shutdown();
  db.close();
  logMeta("relay_stopped");
  process.exit(0);
}
process.on("SIGTERM", () => void stop("SIGTERM"));
process.on("SIGINT", () => void stop("SIGINT"));
```

Create `relay/src/scripts/reset-db.ts`:

```ts
import type { Db } from "../db/db.js";

/** What `resetPassword` did: `reset` (exactly one account updated) or `no_account` (nothing changed). */
export type ResetOutcome = "reset" | "no_account";

/**
 * Sets the password hash of the account `email` (already normalised) in one transaction, and with
 * `revokeTokens` deletes every device token of that account. Pairings are never touched. Sockets
 * already open stay up until they reconnect (this runs outside the relay process).
 */
export function resetPassword(db: Db, email: string, phc: string, now: number, revokeTokens: boolean): ResetOutcome {
  if (!Number.isSafeInteger(now)) throw new TypeError("now must be an integer (unix ms)");
  return db.transaction(() => {
    const user = db.get<{ id: string }>("SELECT id FROM users WHERE email = ?", email);
    if (user === undefined) return "no_account";
    db.run("UPDATE users SET password_hash = ?, password_changed_at = ? WHERE id = ?", phc, now, user.id);
    if (revokeTokens) {
      db.run("DELETE FROM tokens WHERE device_id IN (SELECT id FROM devices WHERE user_id = ?)", user.id);
    }
    return "reset";
  });
}
```

Replace `relay/src/scripts/reset-cli.ts`:

```ts
/**
 * Pure functions for reset-password CLI decision logic.
 * Extracted for testability (no I/O side effects).
 */

import { normalizeEmail } from "../auth/email.js";
import { errorKind } from "../log.js";
import type { ResetOutcome } from "./reset-db.js";

/** The database holds real accounts: an interactive confirmation is required unless `--yes`. */
export function needsConfirmation(yes: boolean): boolean {
  return !yes;
}

/**
 * Check if typed confirmation matches the expected email.
 * Normalizes both strings before comparison.
 */
export function confirmationMatches(expectedEmail: string, typedEmail: string): boolean {
  const normalized = normalizeEmail(typedEmail.trim());
  return normalized === expectedEmail;
}

/**
 * Determine which password source to use.
 * Order: argv '-' → stdin; argv value → argv (+warning); else env; else generate.
 */
export function choosePasswordSource(argv?: string, env?: string): "stdin" | "argv" | "env" | "generate" {
  if (argv === "-") return "stdin";
  if (argv) return "argv";
  if (env) return "env";
  return "generate";
}

/**
 * One-line message for a failed database step: the SQLite error code (e.g. `SQLITE_BUSY`) or
 * the error's class, never its message, which could quote SQL, the e-mail address or the hash.
 */
export function failureMessage(err: unknown): string {
  return `database error (${errorKind(err)})`;
}

export interface ResetReport {
  stdout: string[];
  stderr: string[];
  exitCode: number;
}

/**
 * What the script prints and its exit status for an outcome. A generated password is printed
 * only when the reset happened, never for `no_account`.
 */
export function resetReport(
  outcome: ResetOutcome,
  ctx: { email: string; target: string; generatedPassword?: string; revokeTokens: boolean },
): ResetReport {
  switch (outcome) {
    case "reset":
      return {
        stdout: [
          `Password reset for ${ctx.email} in ${ctx.target}.`,
          ...(ctx.generatedPassword === undefined ? [] : [`Temporary password: ${ctx.generatedPassword}`]),
          ...(ctx.revokeTokens ? ["All device tokens of this account were revoked."] : []),
        ],
        stderr: [],
        exitCode: 0,
      };
    case "no_account":
      return { stdout: [], stderr: [`No account with email ${ctx.email} in ${ctx.target}; nothing changed.`], exitCode: 1 };
  }
}
```

Replace `relay/src/scripts/reset-password.ts`:

```ts
// Emergency support tool (spec §5.2, VPS spec §4.4): sets a new password for one account directly
// in the relay's SQLite database. On the VPS:
//
//   docker compose exec relay node dist/scripts/reset-password.js --email <address> [--password <new>|-] [--revoke-tokens] [--yes]
//
// Locally (against .data/relay.db from `npm run dev`): npm run reset-password -- --email <address> …
//
// The database is DB_PATH (default /data/relay.db). Without --password a random 16-character
// password is generated and printed once. The password can also come from SHELLX_RESET_PASSWORD or
// from stdin with `--password -`. --revoke-tokens also signs out every device of the account (open
// sockets stay up until they reconnect). Pairings are never touched. Without --yes the operator
// must type the account's e-mail address to confirm.
import { parseArgs } from "node:util";
import { isValidEmail, normalizeEmail } from "../auth/email.js";
import { hashPassword } from "../auth/password.js";
import { isAcceptablePassword } from "../auth/password-policy.js";
import { base64UrlEncode } from "../auth/tokens.js";
import { DEFAULT_DB_PATH } from "../config.js";
import { Db } from "../db/db.js";
import { errorKind } from "../log.js";
import { createPrompter } from "./prompter.js";
import { choosePasswordSource, confirmationMatches, failureMessage, needsConfirmation, resetReport } from "./reset-cli.js";
import { resetPassword } from "./reset-db.js";

const { values } = parseArgs({
  options: {
    email: { type: "string" },
    password: { type: "string" },
    "revoke-tokens": { type: "boolean", default: false },
    yes: { type: "boolean", default: false },
  },
});

const target = process.env.DB_PATH?.trim() || DEFAULT_DB_PATH;
const prompter = createPrompter();

/** Prints one line to stderr and exits 1, restoring the terminal first. */
function fail(message: string): never {
  prompter.close();
  console.error(message);
  process.exit(1);
}

const email = normalizeEmail(values.email ?? "");
if (!isValidEmail(email)) fail("--email is not a valid address");

const passwordSource = choosePasswordSource(values.password, process.env.SHELLX_RESET_PASSWORD);
let password: string;
try {
  if (passwordSource === "stdin") {
    password = await prompter.ask("Password: ", { hidden: true });
  } else if (passwordSource === "argv") {
    console.error("Warning: --password in argv is visible in shell history and process lists; consider --password - or SHELLX_RESET_PASSWORD env var");
    password = values.password!;
  } else if (passwordSource === "env") {
    password = process.env.SHELLX_RESET_PASSWORD!;
  } else {
    password = base64UrlEncode(crypto.getRandomValues(new Uint8Array(12)));
  }
} catch (err) {
  fail(err instanceof Error ? err.message : "An unknown error occurred");
}
if (!isAcceptablePassword(password)) fail("password must be 8-128 characters");

if (needsConfirmation(values.yes)) {
  let typed: string;
  try {
    typed = await prompter.ask(`Confirm email for ${target}: `);
  } catch (err) {
    fail(err instanceof Error ? err.message : "An unknown error occurred");
  }
  if (!confirmationMatches(email, typed)) fail("Email mismatch; operation aborted.");
} else {
  console.error(`Confirmation bypassed with --yes for ${target}.`);
}
prompter.close();

let db: Db;
try {
  db = Db.open(target, { fileMustExist: true });
} catch (err) {
  fail(`cannot open database at ${target} (${errorKind(err)})`);
}
try {
  const outcome = resetPassword(db, email, await hashPassword(password), Date.now(), values["revoke-tokens"]);
  const report = resetReport(outcome, {
    email,
    target,
    generatedPassword: passwordSource === "generate" ? password : undefined,
    revokeTokens: values["revoke-tokens"],
  });
  for (const line of report.stderr) console.error(line);
  for (const line of report.stdout) console.log(line);
  db.close();
  process.exit(report.exitCode);
} catch (err) {
  db.close();
  fail(failureMessage(err));
}
```

Replace `relay/src/scripts/line-prompter.ts` (only its header comment changes; `src/scripts/prompter.ts` stays exactly as moved):

```ts
/**
 * The prompter interface and its pure, non-TTY implementation (unit-tested in
 * `test/reset-password.test.ts`). The TTY-backed prompters live in `prompter.ts`.
 */

export interface AskOptions {
  /** The answer is a secret (a password): an interactive terminal must not echo what is typed. */
  hidden?: boolean;
}

export interface Prompter {
  ask(question: string, options?: AskOptions): Promise<string>;
  close(): void;
}

/**
 * Create a prompter for non-TTY (piped) input.
 * Splits input on newlines and returns each line on demand.
 * Rejects with "stdin ended" error when input is exhausted.
 * `hidden` needs nothing here: piped input is never echoed by a terminal, and only the question
 * (never the answer) is written.
 */
export function createLinePrompter(input: string, write: (s: string) => void): Prompter {
  // Split on newlines and filter out the trailing empty line if input ends with newline
  let lines = input.split(/\r?\n/);
  if (lines.length > 0 && lines[lines.length - 1] === "") {
    lines = lines.slice(0, -1);
  }
  let index = 0;

  return {
    async ask(question: string): Promise<string> {
      write(question);
      if (index >= lines.length) {
        throw new Error("stdin ended before an answer was given");
      }
      const answer = lines[index++];
      return answer ?? "";
    },
    close(): void {
      // No-op for line prompter
    },
  };
}
```

Replace `relay/tsconfig.json` (no more porting list):

```jsonc
{
  "compilerOptions": {
    "target": "es2023",
    "module": "nodenext",
    "moduleResolution": "nodenext",
    "lib": ["es2023"],
    "types": ["node"],
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noEmit": true,
    "skipLibCheck": true,
    "isolatedModules": true,
    "resolveJsonModule": true,
    "verbatimModuleSyntax": true
  },
  "include": ["src", "test", "scripts", "vitest.config.ts"]
}
```

Create `relay/tsconfig.build.json`:

```json
{
  "extends": "./tsconfig.json",
  "compilerOptions": {
    "noEmit": false,
    "rootDir": "src",
    "outDir": "dist"
  },
  "include": ["src"]
}
```

Create `relay/dev.env`:

```ini
# Local development only (`npm run dev`, `npm run reset-password`); production reads deploy/relay.env.
HOST=127.0.0.1
PORT=8787
DB_PATH=.data/relay.db
# The shellx_e2e suite creates many accounts from 127.0.0.1.
RATE_LIMITS_ENABLED=false
MIN_AGENT=1.0.0
MIN_MOBILE=1.0.0
LATEST_AGENT_VERSION=1.0.0
MAC_URL=https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg
WIN_URL=https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe
```

Replace `relay/.gitignore`:

```gitignore
node_modules/
dist/
.data/
```

- [ ] **Step 5: Run the tests, the type check and the build**

Run: `npx vitest run test/server.test.ts test/reset-password.test.ts`
Expected: PASS (8 + 16 tests).

Run: `npm run typecheck && npm test`
Expected: `Test Files  16 passed (16)`, `Tests  263 passed (263)`.

Run: `rm -rf dist && npm run build && ls dist/server.js dist/scripts/reset-password.js dist/auth/disposable-domains.json`
Expected: the three paths are listed.

- [ ] **Step 6: Rewrite `relay/README.md` for Node and the VPS**

Replace `relay/README.md`:

````markdown
# ShellX relay

Node.js 22 + TypeScript: [Hono](https://hono.dev) on `@hono/node-server`, WebSockets with `ws`,
SQLite with `better-sqlite3`, argon2id with `@node-rs/argon2`. It stores accounts, devices and
pairings, and forwards end-to-end encrypted frames between devices of the same account through one
in-process hub per account. Design: `docs/superpowers/specs/2026-09-25-shellx-v1-design.md` §5, §6,
§10 and `docs/superpowers/specs/2026-09-26-shellx-vps-infra-design.md` §4. It runs on the VPS as the
`relay` container of `deploy/docker-compose.yml`; `deploy/README.md` is the runbook.

## Local development

Requires Node.js 22 or later (the container runs Node 22).

```bash
cd relay
npm ci
npm test            # Vitest on Node: a temp SQLite database, a real server and real WebSockets per test
npm run typecheck   # src/, test/ and scripts/
npm run dev         # http://127.0.0.1:8787 with .data/relay.db (created on first run)
npm run build       # tsc → dist/ (what the image runs: node dist/server.js)
```

- `npm run dev` reads `dev.env`: `HOST=127.0.0.1`, `PORT=8787`, `DB_PATH=.data/relay.db`,
  `RATE_LIMITS_ENABLED=false` (the E2E suite creates many accounts from 127.0.0.1) and the version
  variables. Delete `.data/` to start from an empty database. Ctrl-C stops it gracefully.
- End-to-end check with the Dart packages, while `npm run dev` runs:

  ```bash
  flutter pub get                 # from the repository root, once
  cd packages/shellx_e2e && SHELLX_E2E_RELAY=http://127.0.0.1:8787 dart test   # 7 tests
  ```
- `relay/.npmrc` sets `ignore-scripts=true`: `better-sqlite3` and `@node-rs/argon2` ship prebuilt
  binaries, and npm 10 (bundled with Node 22) would otherwise try to compile `better-sqlite3`.

## Configuration

Read once at startup from environment variables (`src/config.ts`); a missing or malformed value
stops the relay with one line on stderr and exit status 1.

| Variable | Default | Meaning |
|---|---|---|
| `MIN_AGENT`, `MIN_MOBILE`, `LATEST_AGENT_VERSION`, `MAC_URL`, `WIN_URL` | required | Served by `GET /v1/version` |
| `PORT` | `8080` | Listening port (`0` = any free port) |
| `HOST` | `0.0.0.0` | Listening address (`npm run dev` uses `127.0.0.1`) |
| `DB_PATH` | `/data/relay.db` | SQLite file; its directory is created if missing |
| `RATE_LIMITS_ENABLED` | on | Only the exact value `false` turns the login/register limits off |

On startup the relay applies every `migrations/*.sql` not yet listed in `schema_migrations`, in
file-name order, one transaction per file. There are no down-migrations: fix a mistake with a new
file. `0001_init.sql` is the original schema; `0002_hub_state.sql` holds the hub's
`pairing_removed` tombstones.

## Behaviour worth knowing

- **Hub:** one `HubState` per account with a serial queue for everything that touches it (sockets
  joining/closing, frames, REST calls). Routes reach it with `registry.forUser(userId).<method>()`.
  Text `ping` is answered with `pong` immediately, outside the queue.
- **Rate limits:** in memory, 60-second sliding window: login 10/IP and 5/email, register 3/IP. The
  IP is `X-Real-IP` when the TCP peer is a private or loopback address (nginx-proxy), otherwise the
  peer address. IPs and e-mail addresses are never logged.
- **argon2id:** m = 19456 KiB, t = 2, p = 1; at most 4 hashes run at once, the rest wait.
- **Limits:** JSON bodies over 16 KiB → 413 `payload_too_large`; a password over 128 code points is
  refused as `invalid_credentials` before hashing; WebSocket frames over 64 KiB → ERROR
  `frame_too_large`, messages over 1 MiB close the socket with 1009; 500 frames/s per device →
  ERROR `rate_limited`, close 4003.
- **Shutdown:** on SIGTERM/SIGINT the relay stops accepting connections, closes every socket with
  1001 "going away", waits at most 5 s for requests and hub queues, closes the database and exits 0.
  Clients reconnect with their usual backoff.
- **Logs:** one JSON line per event with metadata only (time, `device_id`, error kind). Never
  payloads, tokens, passwords, e-mail or IP addresses.

## Emergency password reset (spec §5.2)

On the VPS, inside the running container (it uses the same `DB_PATH`):

```bash
cd ~/phu/shellx
# generates a temporary password and prints it once
docker compose exec relay node dist/scripts/reset-password.js --email user@example.com
# your own password, not echoed and not in shell history; --revoke-tokens signs every device out
docker compose exec relay node dist/scripts/reset-password.js --email user@example.com --password - --revoke-tokens
```

The script asks you to type the account's e-mail address to confirm (skip with `--yes`). The
password can also come from `SHELLX_RESET_PASSWORD` (`docker compose exec -e SHELLX_RESET_PASSWORD=…`).
`--password <value>` works too but warns that it is visible in shell history. Sockets that are
already open stay up until they reconnect; pairings are kept. Exit status: `0` reset, `1` nothing
changed (unknown address, wrong confirmation, bad arguments, database error — printed as one line
such as `database error (SQLITE_BUSY)`, never SQL). Locally: `npm run reset-password -- --email …`
works on `.data/relay.db`.

## Disposable e-mail domains

`npm run domains:update` downloads the upstream blocklist into `src/auth/disposable-domains.json`;
review the diff, run `npm test`, commit. A deploy ships it.
````

- [ ] **Step 7: Verify `npm run dev` and the end-to-end suite (7/7)**

In one terminal (from `relay/`):

```bash
rm -rf .data && npm run dev
```

Expected: one line `{"ts":…,"event":"relay_started","port":8787}` and `.data/relay.db` exists.

In a second terminal, from the repository root:

```bash
curl -s http://127.0.0.1:8787/v1/version
flutter pub get
cd packages/shellx_e2e && SHELLX_E2E_RELAY=http://127.0.0.1:8787 dart test
```

Expected: the version JSON (`"min_agent":"1.0.0"`…), then `+7: All tests passed!`. Then check the admin script against the dev database: `npm run reset-password -- --email nobody@example.com --yes` (from `relay/`) prints `No account with email nobody@example.com in .data/relay.db; nothing changed.` and exits 1. Finally press Ctrl-C in the first terminal: it prints `relay_stopping` with `"signal":"SIGINT"` and `relay_stopped`, and exits.

- [ ] **Step 8: Commit**

```bash
git add -A relay
git commit -m "feat(relay): Node entry with graceful shutdown, reset-password on SQLite, drop wrangler; README for Node/VPS"
```

### Task 6: Docker images — relay (tests inside the build), web (nginx) and the `[quốc gia]` build guard

**Files:**
- Create: `relay/Dockerfile`, `relay/.dockerignore`, `web/Dockerfile`, `web/Dockerfile.dockerignore`, `deploy/web/nginx.conf`, `web/scripts/check-placeholders.mjs`, `web/tests/placeholders.test.mjs`
- Modify: `web/package.json` (`build` and `test` scripts)

**Interfaces:**
- Consumes: `relay/` scripts `typecheck`, `test`, `build` and `relay/.npmrc` (Tasks 1, 5); `web/` `npm run build` (Astro + `tests/site.test.mjs`).
- Produces:
  - `docker build -t <name> relay` → runtime image: `node:22-bookworm-slim`, user `node` (uid 1000), `WORKDIR /app` with `dist/`, `migrations/`, pruned `node_modules`, `package.json`; `/data` owned by uid 1000; `EXPOSE 8080`; `CMD ["node", "dist/server.js"]`; label `org.opencontainers.image.source=https://github.com/lephus/shellx`. No image unless `npm run typecheck && npm test` passed.
  - `docker build -f web/Dockerfile -t <name> .` (context = repository root) → `nginx:alpine` with the Astro `dist/` in `/usr/share/nginx/html` and `deploy/web/nginx.conf` as `/etc/nginx/conf.d/default.conf`; serves `/srv/downloads` for `download.shellx.pro`.
  - `web/scripts/check-placeholders.mjs`: `export const MARKER = '[quốc gia]'`, `export function findPlaceholders(dir: string): string[]` (`file:line`, NFC-normalised); CLI `node scripts/check-placeholders.mjs [dir=src]` exits 1 with `Refusing to build: replace the [quốc gia] placeholder (the country where the VPS is hosted) in:` and one indented `file:line` per hit.
  - `web/package.json`: `"build": "node scripts/check-placeholders.mjs && astro build && node --test tests/site.test.mjs tests/placeholders.test.mjs"`, `"test": "node --test tests/site.test.mjs tests/placeholders.test.mjs"`.

- [ ] **Step 1: Write the failing test of the build guard**

Create `web/tests/placeholders.test.mjs`:

```js
// Checks scripts/check-placeholders.mjs, the guard `npm run build` runs before `astro build`.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const script = join(dirname(fileURLToPath(import.meta.url)), '..', 'scripts', 'check-placeholders.mjs');

function run(files) {
  const dir = mkdtempSync(join(tmpdir(), 'shellx-web-'));
  for (const [name, text] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, name)), { recursive: true });
    writeFileSync(join(dir, name), text);
  }
  return spawnSync(process.execPath, [script, dir], { encoding: 'utf8', cwd: dir });
}

test('fails and names every file and line that still has the placeholder', () => {
  const result = run({
    'pages/privacy.md': 'intro\nmáy chủ riêng do ShellX thuê tại **[quốc gia]**\n',
    'pages/en/privacy.md': 'a private server rented by ShellX in **[quốc gia]**\n',
    'pages/terms.md': 'nothing to fill in\n',
  });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Refusing to build: replace the \[quốc gia\] placeholder/);
  assert.match(result.stderr, /pages\/privacy\.md:2/);
  assert.match(result.stderr, /pages\/en\/privacy\.md:1/);
  assert.doesNotMatch(result.stderr, /terms\.md/);
});

test('also finds the placeholder typed in decomposed (NFD) form', () => {
  const result = run({ 'pages/privacy.md': `tại ${'[quốc gia]'.normalize('NFD')}\n` });
  assert.equal(result.status, 1);
});

test('passes once the country is filled in', () => {
  const result = run({ 'pages/privacy.md': 'máy chủ riêng do ShellX thuê tại **Singapore**\n' });
  assert.equal(result.status, 0);
  assert.equal(result.stderr, '');
});
```

- [ ] **Step 2: Run it to verify it fails**

Run (from `web/`): `node --test tests/placeholders.test.mjs`
Expected: FAIL — 3 failing tests (the script `scripts/check-placeholders.mjs` does not exist, so `spawnSync` reports `Cannot find module`).

- [ ] **Step 3: Implement the guard and wire it into the build**

Create `web/scripts/check-placeholders.mjs`:

```js
// Refuses to build the site while any page still contains the "[quốc gia]" placeholder: the country
// where the VPS is hosted must be written into the privacy policy before the public site is
// deployed (VPS spec §9). Usage: node scripts/check-placeholders.mjs [dir]   (default: src)
import { readdirSync, readFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { pathToFileURL } from 'node:url';

export const MARKER = '[quốc gia]';

/** Every `file:line` under `dir` whose text (NFC-normalised) contains MARKER. */
export function findPlaceholders(dir) {
  const hits = [];
  const walk = (current) => {
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      const path = join(current, entry.name);
      if (entry.isDirectory()) {
        walk(path);
        continue;
      }
      const lines = readFileSync(path, 'utf8').normalize('NFC').split('\n');
      lines.forEach((line, index) => {
        if (line.includes(MARKER)) hits.push(`${relative(process.cwd(), path)}:${index + 1}`);
      });
    }
  };
  walk(dir);
  return hits;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const hits = findPlaceholders(process.argv[2] ?? 'src');
  if (hits.length > 0) {
    console.error(`Refusing to build: replace the ${MARKER} placeholder (the country where the VPS is hosted) in:`);
    for (const hit of hits) console.error(`  ${hit}`);
    process.exit(1);
  }
}
```

Then (from `web/`):

```bash
npm pkg set scripts.build="node scripts/check-placeholders.mjs && astro build && node --test tests/site.test.mjs tests/placeholders.test.mjs"
npm pkg set scripts.test="node --test tests/site.test.mjs tests/placeholders.test.mjs"
```

- [ ] **Step 4: Run the web checks**

Run (from `web/`): `npm ci && npm run build`
Expected: the guard prints nothing (no page has the marker yet — Task 9 adds it), Astro builds, and `node --test` ends with `ℹ pass 19` and `ℹ skipped 1` (the network check `CHECK_DOWNLOADS`), `ℹ fail 0`.

- [ ] **Step 5: Write the Dockerfiles and the nginx configuration**

Create `relay/Dockerfile`:

```dockerfile
# syntax=docker/dockerfile:1
# ShellX relay image (VPS spec §4.6). Build from relay/: docker build -t shellx-relay relay
# The runtime stage is built FROM the test stage's output, so an image only exists if every relay
# test passed (V6). Everything before `runtime` runs as the unprivileged `node` user (uid 1000).

FROM node:22-bookworm-slim AS deps
WORKDIR /app
RUN chown node:node /app
USER node
COPY --chown=node:node package.json package-lock.json .npmrc ./
RUN npm ci

FROM deps AS test
COPY --chown=node:node . .
RUN npm run typecheck && npm test

FROM test AS build
RUN npm run build && npm prune --omit=dev

FROM node:22-bookworm-slim AS runtime
LABEL org.opencontainers.image.source="https://github.com/lephus/shellx"
ENV NODE_ENV=production
WORKDIR /app
# /data is where ./data is bind-mounted (the SQLite database); it must be writable by uid 1000.
RUN mkdir -p /data && chown node:node /data
COPY --from=build /app/package.json ./
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/migrations ./migrations
USER node
EXPOSE 8080
CMD ["node", "dist/server.js"]
```

Create `relay/.dockerignore`:

```gitignore
node_modules
dist
.data
*.log
```

Create `web/Dockerfile`:

```dockerfile
# syntax=docker/dockerfile:1
# ShellX website image (VPS spec §4.6). Build from the repository root, because it also needs
# deploy/web/nginx.conf:  docker build -f web/Dockerfile -t shellx-web .
# `npm run build` refuses to build while a page still has the "[quốc gia]" placeholder, then runs
# the page and link checks of tests/site.test.mjs.

FROM node:22-bookworm-slim AS build
WORKDIR /web
ENV ASTRO_TELEMETRY_DISABLED=1
COPY web/package.json web/package-lock.json ./
RUN npm ci
COPY web/ ./
RUN npm run build

FROM nginx:alpine AS runtime
LABEL org.opencontainers.image.source="https://github.com/lephus/shellx"
COPY deploy/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /web/dist /usr/share/nginx/html
```

Create `web/Dockerfile.dockerignore` (BuildKit reads `<Dockerfile>.dockerignore`; the build context is the repository root):

```gitignore
# Build context of web/Dockerfile is the repository root: send only web/ and deploy/web/.
*
!web/
!deploy/web/
web/node_modules
web/dist
web/.astro
```

Create `deploy/web/nginx.conf`:

```nginx
# nginx of the `web` container (VPS spec §3), installed as /etc/nginx/conf.d/default.conf.
# nginx-proxy terminates TLS and forwards by Host to port 80 here. Nothing is logged per request:
# no access log, and no "file not found" lines (they would carry the client address) — the privacy
# policy promises that visits are not logged.

# shellx.pro: the Astro site. /privacy answers 301 → /privacy/ (relative Location, so it stays on
# https behind the proxy), unknown paths answer 404 with the site's 404 page.
server {
    listen 80 default_server;
    server_name shellx.pro;
    root /usr/share/nginx/html;
    index index.html;
    access_log off;
    log_not_found off;
    server_tokens off;
    absolute_redirect off;
    error_page 404 /404.html;

    location / {
    }

    location = /404.html {
        internal;
    }
}

# www.shellx.pro → https://shellx.pro, keeping the path and query.
server {
    listen 80;
    server_name www.shellx.pro;
    access_log off;
    log_not_found off;
    server_tokens off;
    return 301 https://shellx.pro$request_uri;
}

# download.shellx.pro: installers rsynced by release-desktop.yml into downloads/desktop/<version>/.
# Files only: a directory (with or without the trailing slash) answers 404, never a listing.
# Found files are always downloads and never change (a new release gets a new version path).
server {
    listen 80;
    server_name download.shellx.pro;
    root /srv/downloads;
    access_log off;
    log_not_found off;
    server_tokens off;
    autoindex off;

    location / {
        try_files $uri =404;
        add_header Content-Disposition "attachment";
        add_header Cache-Control "public, max-age=31536000, immutable";
        add_header X-Content-Type-Options "nosniff";
    }
}
```

- [ ] **Step 6: Build the relay image — the tests run inside it (V6)**

Start Docker if needed (`open -a Docker` on the Mac, then wait until `docker info` succeeds). From the repository root:

```bash
docker build --progress=plain -t shellx-relay:local relay 2>&1 | grep -E "Test Files|Tests "
docker run --rm shellx-relay:local sh -c 'id -u; node -v; ls /app; stat -c %u /data'
```

Expected: `Test Files  16 passed (16)` and `Tests  263 passed (263)` (the read-only-directory test runs because the stage is not root), then `1000`, `v22.…`, `dist migrations node_modules package.json`, `1000`.

Prove that a failing test blocks the image, then undo it:

```bash
printf 'import { expect, it } from "vitest";\n\nit("fails on purpose", () => {\n  expect(1).toBe(2);\n});\n' > relay/test/zz-must-fail.test.ts
docker build -q -t shellx-relay:must-not-exist relay; echo "exit=$?"
rm relay/test/zz-must-fail.test.ts
docker image inspect shellx-relay:must-not-exist > /dev/null 2>&1 && echo "IMAGE EXISTS (wrong)" || echo "no image (right)"
```

Expected: `exit=1` and `no image (right)`.

Check the container end to end (graceful stop included):

```bash
docker run -d --name relay-check -p 18080:8080 -e MIN_AGENT=1.0.0 -e MIN_MOBILE=1.0.0 -e LATEST_AGENT_VERSION=1.0.0 \
  -e MAC_URL=https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg -e WIN_URL=https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe \
  -v shellx-check-data:/data shellx-relay:local
sleep 2 && curl -s http://127.0.0.1:18080/v1/version && echo
docker exec relay-check node -e "fetch('http://127.0.0.1:8080/v1/version').then((r) => process.exit(r.ok ? 0 : 1), () => process.exit(1))"; echo "healthcheck exit=$?"
docker stop relay-check && docker logs relay-check
docker rm relay-check && docker volume rm shellx-check-data
```

Expected: the version JSON; `healthcheck exit=0`; the logs show `relay_started`, `relay_stopping` with `"signal":"SIGTERM"`, `relay_stopped`.

- [ ] **Step 7: Build the web image and check nginx per host name**

From the repository root:

```bash
docker build -q -f web/Dockerfile -t shellx-web:local .
mkdir -p /tmp/shellx-dl/desktop/1.0.0 && printf 'dmg' > /tmp/shellx-dl/desktop/1.0.0/ShellX-1.0.0.dmg
docker run -d --name web-check -p 18081:80 -v /tmp/shellx-dl:/srv/downloads:ro shellx-web:local && sleep 1
t() { printf '%-50s ' "$1 $2"; curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' -H "Host: $1" "http://127.0.0.1:18081$2"; }
t shellx.pro /; t shellx.pro /privacy; t shellx.pro /no-such-page; t www.shellx.pro "/en/privacy/?a=1"
t download.shellx.pro /desktop/1.0.0/ShellX-1.0.0.dmg; t download.shellx.pro /desktop/1.0.0/; t download.shellx.pro /desktop/1.0.0
curl -sI -H "Host: download.shellx.pro" http://127.0.0.1:18081/desktop/1.0.0/ShellX-1.0.0.dmg | grep -i -E '^content-disposition|^cache-control'
docker logs web-check 2>&1 | grep -c 'GET /' ; docker rm -f web-check; rm -rf /tmp/shellx-dl
```

Expected, in order: `200`; `301 http://127.0.0.1:18081/privacy/` (curl resolves the relative `Location: /privacy/`); `404`; `301 https://shellx.pro/en/privacy/?a=1`; `200`; `404`; `404`; the headers `Content-Disposition: attachment` and `Cache-Control: public, max-age=31536000, immutable`; and `0` request lines in the log.

Prove the guard stops the image build, then undo it:

```bash
cp web/src/pages/privacy.md /tmp/privacy.md.bak
printf '\n**[quốc gia]**\n' >> web/src/pages/privacy.md
docker build --progress=plain -f web/Dockerfile -t shellx-web:must-not-exist . 2>&1 | grep -E "Refusing|privacy.md:"
cp /tmp/privacy.md.bak web/src/pages/privacy.md && git diff --exit-code web/src/pages/privacy.md && echo restored
```

Expected: `Refusing to build: replace the [quốc gia] placeholder …` and `src/pages/privacy.md:<line>`, then `restored`.

- [ ] **Step 8: Commit**

```bash
git add relay/Dockerfile relay/.dockerignore web/Dockerfile web/Dockerfile.dockerignore deploy/web/nginx.conf web/scripts/check-placeholders.mjs web/tests/placeholders.test.mjs web/package.json
git commit -m "feat(deploy): relay image (tests in the build), web image (nginx), [quốc gia] build guard"
```

### Task 7: `deploy/` — Compose project for `~/phu/shellx`, backups, vhost files, rollout with rollback, runbook

Everything the VPS needs lives in the one folder `~/phu/shellx` (V8, user decision 2026-09-27). `deploy.yml` (Task 8) rsyncs `docker-compose.yml`, `relay.env`, `nginx-proxy/` and `backup/` into it and streams `deploy/rollout.sh` over SSH. `backup/` is synced in addition to the spec's list because the backup container needs its script on the host (inlining it into the Compose file would need `$$` escaping and could not be tested).

**Files:**
- Create: `deploy/docker-compose.yml`, `deploy/relay.env`, `deploy/backup/entrypoint.sh`, `deploy/backup/backup-once.sh`, `deploy/nginx-proxy/relay.shellx.pro`, `deploy/nginx-proxy/shellx.pro`, `deploy/nginx-proxy/www.shellx.pro`, `deploy/nginx-proxy/download.shellx.pro`, `deploy/rollout.sh`, `deploy/tests/rollout.test.mjs`, `deploy/tests/backup.test.mjs`, `deploy/README.md`

**Interfaces:**
- Consumes: the images of Task 6 (`ghcr.io/lephus/shellx-relay:<tag>`, `ghcr.io/lephus/shellx-web:<tag>`), the relay's env variables and `GET /v1/version` (Tasks 1, 5), `node dist/scripts/reset-password.js` (Task 5).
- Produces (used by Task 8):
  - Compose project `shellx` with services `relay`, `web`, `backup`; interpolates `IMAGE_TAG` and `PROXY_NETWORK` from `.env` (fails fast if either is missing).
  - `deploy/rollout.sh <image-tag> <app-dir>` run on the VPS (`ssh vps bash -s -- "$SHA" "$APP_DIR" < deploy/rollout.sh`): relative `<app-dir>` is under `$HOME`; creates `data backups downloads/desktop nginx-proxy backup`; refuses (exit 1, before any docker call) if `.env` has no `PROXY_NETWORK` or `data/` is not owned by uid 1000; pulls with the new tag first (a failed pull leaves `.env` and the stack untouched); writes `IMAGE_TAG`; `docker compose up -d --remove-orphans`; waits up to 60 s for the relay healthcheck; otherwise restores the previous `IMAGE_TAG`, runs `up -d` again and exits 1. Test knobs: `HEALTH_TIMEOUT_SECONDS`, `RELAY_UID`.
  - `deploy/backup/backup-once.sh` (test knobs `DATA_DB`, `BACKUP_DIR`, `KEEP`, `BACKUP_DATE`), run daily at 03:00 by `entrypoint.sh`.
  - `node --test deploy/tests/*.test.mjs` (run from the repository root).

- [ ] **Step 1: Write the failing tests**

Create `deploy/tests/rollout.test.mjs` (runs `rollout.sh` against a fake `docker`; the "does not belong to the relay user" case pins Review Focus 5 on the deploy side):

```js
// Tests for deploy/rollout.sh with a fake `docker` on PATH (no Docker needed):
//   node --test deploy/tests/*.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const script = join(dirname(fileURLToPath(import.meta.url)), '..', 'rollout.sh');

// Fake docker: logs every call; `compose pull` fails for tag "unpullable"; the relay container is
// healthy unless .env's IMAGE_TAG is "broken".
const FAKE_DOCKER = `#!/usr/bin/env bash
echo "docker $* [IMAGE_TAG=\${IMAGE_TAG:-}]" >> "$CALLS"
if [[ "$1 $2" == "compose pull" && "\${IMAGE_TAG:-}" == unpullable ]]; then exit 1; fi
if [[ "$1 $2" == "compose ps" ]]; then echo relay-container-id; exit 0; fi
if [[ "$1" == inspect ]]; then
  if grep -q '^IMAGE_TAG=broken$' .env; then echo unhealthy; else echo healthy; fi
  exit 0
fi
exit 0
`;

function setup({ env = 'PROXY_NETWORK=proxy-net\nIMAGE_TAG=old\n', ownData = true } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'shellx-rollout-'));
  const home = join(root, 'home');
  const app = join(home, 'phu', 'shellx');
  const bin = join(root, 'bin');
  mkdirSync(app, { recursive: true });
  mkdirSync(bin);
  if (ownData) mkdirSync(join(app, 'data'));
  writeFileSync(join(app, '.env'), env);
  writeFileSync(join(bin, 'docker'), FAKE_DOCKER);
  chmodSync(join(bin, 'docker'), 0o755);
  const calls = join(root, 'calls.log');
  writeFileSync(calls, '');
  const run = (tag, appDir = 'phu/shellx', relayUid = String(process.getuid())) =>
    spawnSync('bash', [script, tag, appDir], {
      encoding: 'utf8',
      env: {
        PATH: `${bin}:${process.env.PATH}`, HOME: home, CALLS: calls, HEALTH_TIMEOUT_SECONDS: '3', RELAY_UID: relayUid,
      },
    });
  return { app, run, env: () => readFileSync(join(app, '.env'), 'utf8'), calls: () => readFileSync(calls, 'utf8') };
}

test('healthy: pulls with the new tag, then writes it to .env and restarts once; keeps PROXY_NETWORK', () => {
  const s = setup();
  const result = s.run('abc123');
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /relay is healthy on abc123/);
  assert.equal(s.env(), 'PROXY_NETWORK=proxy-net\nIMAGE_TAG=abc123\n');
  const calls = s.calls();
  assert.match(calls, /docker compose pull \[IMAGE_TAG=abc123\]/);
  assert.equal(calls.match(/compose up -d --remove-orphans/g).length, 1);
});

test('unhealthy: puts the previous tag back, restarts again and fails', () => {
  const s = setup();
  const result = s.run('broken');
  assert.equal(result.status, 1);
  assert.match(result.stderr, /not healthy within 3s on broken; rolling back to old/);
  assert.equal(s.env(), 'PROXY_NETWORK=proxy-net\nIMAGE_TAG=old\n');
  assert.equal(s.calls().match(/compose up -d --remove-orphans/g).length, 2);
});

test('first deploy unhealthy: nothing to roll back to, fails without a second restart', () => {
  const s = setup({ env: 'PROXY_NETWORK=proxy-net\n' });
  const result = s.run('broken');
  assert.equal(result.status, 1);
  assert.match(result.stderr, /rolling back to nothing/);
  assert.equal(s.calls().match(/compose up -d/g).length, 1);
});

test('images that cannot be pulled leave .env and the running stack untouched', () => {
  const s = setup();
  const result = s.run('unpullable');
  assert.equal(result.status, 1);
  assert.equal(s.env(), 'PROXY_NETWORK=proxy-net\nIMAGE_TAG=old\n');
  assert.doesNotMatch(s.calls(), /compose up/);
});

test('refuses to deploy without PROXY_NETWORK in .env', () => {
  const s = setup({ env: 'IMAGE_TAG=old\n' });
  const result = s.run('abc123');
  assert.equal(result.status, 1);
  assert.match(result.stderr, /PROXY_NETWORK is not set in .*phu\/shellx\/\.env/);
  assert.equal(s.calls(), '');
});

test('refuses to deploy when data/ does not belong to the relay user', () => {
  const s = setup();
  const result = s.run('abc123', 'phu/shellx', '1000' === String(process.getuid()) ? '4242' : '1000');
  assert.equal(result.status, 1);
  assert.match(result.stderr, /phu\/shellx\/data must belong to uid/);
  assert.equal(s.calls(), '');
});

test('creates the folder layout and accepts an absolute app dir', () => {
  const s = setup();
  const result = s.run('abc123', s.app);
  assert.equal(result.status, 0, result.stderr);
  for (const dir of ['data', 'backups', 'downloads/desktop', 'nginx-proxy', 'backup']) {
    assert.ok(statSync(join(s.app, dir)).isDirectory(), dir);
  }
});
```

Create `deploy/tests/backup.test.mjs` (uses the local `sqlite3` CLI; macOS ships one):

```js
// Tests for deploy/backup/backup-once.sh with the local sqlite3 CLI (skipped without it):
//   node --test deploy/tests/*.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const script = join(dirname(fileURLToPath(import.meta.url)), '..', 'backup', 'backup-once.sh');
const hasSqlite = spawnSync('sqlite3', ['-version']).status === 0;

function world() {
  const root = mkdtempSync(join(tmpdir(), 'shellx-backup-'));
  const db = join(root, 'data', 'relay.db');
  const dir = join(root, 'backups');
  mkdirSync(dirname(db));
  mkdirSync(dir);
  const sql = (file, statement) => spawnSync('sqlite3', [file, statement], { encoding: 'utf8' }).stdout.trim();
  const backup = (day) =>
    spawnSync('sh', [script], { encoding: 'utf8', env: { ...process.env, DATA_DB: db, BACKUP_DIR: dir, BACKUP_DATE: day } });
  return { db, dir, sql, backup };
}

test('writes relay-<date>.db with the data, and keeps only the 14 newest', { skip: !hasSqlite }, () => {
  const w = world();
  w.sql(w.db, "PRAGMA journal_mode=WAL; CREATE TABLE users (id TEXT); INSERT INTO users VALUES ('u1');");
  for (let day = 1; day <= 16; day++) {
    const result = w.backup(`2026-01-${String(day).padStart(2, '0')}`);
    assert.equal(result.status, 0, result.stderr);
  }
  const files = readdirSync(w.dir).sort();
  assert.equal(files.length, 14);
  assert.equal(files[0], 'relay-2026-01-03.db');
  assert.equal(files.at(-1), 'relay-2026-01-16.db');
  assert.equal(w.sql(join(w.dir, 'relay-2026-01-16.db'), 'SELECT id FROM users;'), 'u1');
});

test('a missing database is skipped with one line: no empty database, no backup, nothing rotated', { skip: !hasSqlite }, () => {
  const w = world();
  const result = w.backup('2026-02-01');
  assert.equal(result.status, 1);
  assert.equal(result.stderr, `backup: skipped 2026-02-01: ${w.db} is missing or empty\n`);
  assert.equal(existsSync(w.db), false);
  assert.deepEqual(readdirSync(w.dir), []);
});

test('an unreadable database is skipped with one line and leaves no partial file', { skip: !hasSqlite }, () => {
  const w = world();
  writeFileSync(w.db, 'this is not a database '.repeat(100));
  const result = w.backup('2026-02-02');
  assert.equal(result.status, 1);
  assert.equal(result.stderr, `backup: skipped 2026-02-02: cannot read ${w.db} (is the relay running?)\n`);
  assert.deepEqual(readdirSync(w.dir), []);
});
```

- [ ] **Step 2: Run them to verify they fail**

Run (from the repository root): `node --test deploy/tests/*.test.mjs`
Expected: FAIL — every rollout test fails (`bash: …/deploy/rollout.sh: No such file or directory`, exit 127) and the backup tests fail (`sh: …/deploy/backup/backup-once.sh: No such file or directory`).

- [ ] **Step 3: Implement the rollout script and the backup scripts**

Create `deploy/rollout.sh` and make it executable (`chmod +x deploy/rollout.sh`):

```bash
#!/usr/bin/env bash
# Runs ON THE VPS, streamed by deploy.yml:  ssh vps bash -s -- <image-tag> <app-dir> < deploy/rollout.sh
# (VPS spec §6.1 step 4). Pulls the new images, points .env at them, restarts the stack and waits up
# to 60 s for the relay's healthcheck; if it is not healthy, puts the previous IMAGE_TAG back,
# restarts again and fails. Touches nothing outside <app-dir> (relative paths are under $HOME).
set -euo pipefail

new_tag="$1"
app_dir="$2"
health_timeout="${HEALTH_TIMEOUT_SECONDS:-60}"
relay_uid="${RELAY_UID:-1000}"
case "$app_dir" in
  /*) ;;
  *) app_dir="$HOME/$app_dir" ;;
esac
cd "$app_dir"

mkdir -p data backups downloads/desktop nginx-proxy backup
if [[ "$(ls -nd data | awk '{print $3}')" != "$relay_uid" ]]; then
  echo "::error::$app_dir/data must belong to uid $relay_uid (the relay's node user): sudo chown $relay_uid:$relay_uid $app_dir/data" >&2
  exit 1
fi
touch .env
if ! grep -q '^PROXY_NETWORK=.' .env; then
  echo "::error::PROXY_NETWORK is not set in $app_dir/.env (deploy/README.md, step 2)" >&2
  exit 1
fi
old_tag="$(sed -n 's/^IMAGE_TAG=//p' .env | tail -n 1)"

set_tag() {
  local tmp
  tmp="$(mktemp .env.XXXXXX)"
  grep -v '^IMAGE_TAG=' .env > "$tmp" || true
  printf 'IMAGE_TAG=%s\n' "$1" >> "$tmp"
  mv "$tmp" .env
}

relay_health() {
  local id
  id="$(docker compose ps -q relay)"
  if [[ -z "$id" ]]; then
    echo missing
    return
  fi
  docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$id"
}

wait_healthy() {
  local deadline=$((SECONDS + health_timeout))
  while ((SECONDS < deadline)); do
    if [[ "$(relay_health)" == healthy ]]; then return 0; fi
    sleep 2
  done
  return 1
}

# Pull first: if the images cannot be pulled, .env and the running stack stay as they were.
IMAGE_TAG="$new_tag" docker compose pull
set_tag "$new_tag"
docker compose up -d --remove-orphans
if wait_healthy; then
  echo "relay is healthy on $new_tag"
  exit 0
fi

echo "::error::relay not healthy within ${health_timeout}s on $new_tag; rolling back to ${old_tag:-nothing}" >&2
docker compose logs --no-color --tail 50 relay >&2 || true
if [[ -n "$old_tag" ]]; then
  set_tag "$old_tag"
  docker compose up -d --remove-orphans
  if ! wait_healthy; then echo "::error::the previous release ($old_tag) is not healthy either" >&2; fi
fi
exit 1
```

Create `deploy/backup/backup-once.sh`:

```sh
#!/bin/sh
# One backup of the relay database to /backups/relay-<YYYY-MM-DD>.db, keeping the KEEP newest.
# Uses SQLite's online backup, so it is consistent while the relay keeps writing. /data is mounted
# read-only: that works while the relay runs (it holds the WAL files open); while the relay is
# stopped the read fails, nothing is written, and nothing is lost either (a stopped relay changes
# nothing) — the next day's run tries again. Overridable for tests: DATA_DB, BACKUP_DIR, KEEP,
# BACKUP_DATE.
set -eu
db="${DATA_DB:-/data/relay.db}"
dir="${BACKUP_DIR:-/backups}"
keep="${KEEP:-14}"
day="${BACKUP_DATE:-$(date +%F)}"
target="$dir/relay-$day.db"
tmp="$dir/.relay-$day.db.tmp"

rm -f "$tmp"
# sqlite3 would silently create (and back up) an empty database if the file were missing.
if [ ! -s "$db" ]; then
  echo "backup: skipped $day: $db is missing or empty" >&2
  exit 1
fi
if ! sqlite3 "$db" ".backup '$tmp'" 2>/dev/null; then
  rm -f "$tmp"
  echo "backup: skipped $day: cannot read $db (is the relay running?)" >&2
  exit 1
fi
if [ "$(sqlite3 "$tmp" 'PRAGMA integrity_check;')" != "ok" ]; then
  rm -f "$tmp"
  echo "backup: skipped $day: the copy failed its integrity check" >&2
  exit 1
fi
mv "$tmp" "$target"
echo "backup: wrote $target"

# Names sort by date: keep the KEEP newest, delete the rest.
ls -1 "$dir"/relay-*.db 2>/dev/null | sort -r | tail -n "+$((keep + 1))" | while read -r old; do
  rm -f "$old"
  echo "backup: removed $old"
done
```

Create `deploy/backup/entrypoint.sh`:

```sh
#!/bin/sh
# Entry point of the `backup` container (VPS spec §3): installs the sqlite3 CLI, then runs
# backup-once.sh every day at 03:00 in the VPS's time zone (busybox crond; /etc/localtime is
# mounted from the host). Job output goes to the container log.
set -eu
apk add --no-cache sqlite >/dev/null
echo "0 3 * * * /bin/sh /backup/backup-once.sh >/proc/1/fd/1 2>/proc/1/fd/2" > /etc/crontabs/root
echo "backup: scheduled daily at 03:00 $(date +%Z)"
exec crond -f -l 8
```

- [ ] **Step 4: Run the tests**

Run: `node --test deploy/tests/*.test.mjs`
Expected: `ℹ pass 10`, `ℹ fail 0` (7 rollout + 3 backup).

Also run the backup script under busybox, as on the VPS:

```bash
docker run --rm -v "$PWD/deploy/backup:/backup:ro" alpine:3.22 sh -c 'apk add --no-cache sqlite >/dev/null; mkdir -p /data /backups; sqlite3 /data/relay.db "PRAGMA journal_mode=WAL; CREATE TABLE t(x); INSERT INTO t VALUES (1);" >/dev/null; for d in 01 02 03; do BACKUP_DATE=2026-03-$d KEEP=2 sh /backup/backup-once.sh; done; ls /backups'
```

Expected: three `backup: wrote …` lines, one `backup: removed /backups/relay-2026-03-01.db`, then `relay-2026-03-02.db relay-2026-03-03.db`.

- [ ] **Step 5: Write the Compose project, relay settings and vhost files**

Create `deploy/docker-compose.yml`:

```yaml
# ShellX on the VPS (VPS spec §3). Lives in ~/phu/shellx (GitHub variable VPS_APP_DIR) next to
# relay.env and .env; deploy.yml syncs this file and sets IMAGE_TAG in .env. PROXY_NETWORK is
# written into .env once by hand (deploy/README.md, step 2).
name: shellx

x-logging: &logging
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"

services:
  relay:
    image: ghcr.io/lephus/shellx-relay:${IMAGE_TAG:?IMAGE_TAG is not set in .env}
    restart: unless-stopped
    env_file: relay.env
    environment:
      VIRTUAL_HOST: relay.shellx.pro
      VIRTUAL_PORT: "8080"
      LETSENCRYPT_HOST: relay.shellx.pro
      HOST: 0.0.0.0
      PORT: "8080"
      DB_PATH: /data/relay.db
    volumes:
      # SQLite database; the directory must belong to uid 1000 (the image's `node` user).
      - ./data:/data
    healthcheck:
      test: ["CMD", "node", "-e", "fetch('http://127.0.0.1:8080/v1/version').then((r) => process.exit(r.ok ? 0 : 1), () => process.exit(1))"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 20s
    # SIGTERM → sockets closed with 1001, requests drained (≤ 5 s), database closed (spec §4.3).
    stop_grace_period: 10s
    logging: *logging
    networks: [proxy]

  web:
    image: ghcr.io/lephus/shellx-web:${IMAGE_TAG:?IMAGE_TAG is not set in .env}
    restart: unless-stopped
    environment:
      VIRTUAL_HOST: shellx.pro,www.shellx.pro,download.shellx.pro
      VIRTUAL_PORT: "80"
      LETSENCRYPT_HOST: shellx.pro,www.shellx.pro,download.shellx.pro
    volumes:
      - ./downloads:/srv/downloads:ro
    logging: *logging
    networks: [proxy]

  backup:
    image: alpine:3.22
    restart: unless-stopped
    entrypoint: ["/bin/sh", "/backup/entrypoint.sh"]
    volumes:
      - ./data:/data:ro
      - ./backups:/backups
      - ./backup:/backup:ro
      # 03:00 in the VPS's own time zone.
      - /etc/localtime:/etc/localtime:ro
    logging: *logging
    # Not on the proxy network; the project's default network lets it install sqlite at start.

networks:
  proxy:
    name: ${PROXY_NETWORK:?PROXY_NETWORK is not set in .env}
    external: true
```

Create `deploy/relay.env`:

```ini
# Relay settings shipped with every deploy (VPS spec §3). No secrets. Change a value, push main,
# and deploy.yml restarts the relay with it; `GET /v1/version` serves these to the apps.
MIN_AGENT=1.0.0
MIN_MOBILE=1.0.0
LATEST_AGENT_VERSION=1.0.0
MAC_URL=https://download.shellx.pro/desktop/1.0.0/ShellX-1.0.0.dmg
WIN_URL=https://download.shellx.pro/desktop/1.0.0/ShellX-Setup-1.0.0.exe
RATE_LIMITS_ENABLED=true
```

Create `deploy/nginx-proxy/relay.shellx.pro`:

```nginx
# nginx-proxy settings for relay.shellx.pro (VPS spec §3), included in its server block. Lives in
# ~/phu/shellx/nginx-proxy/ and is copied once into nginx-proxy's vhost.d (deploy/README.md, step 5).
# No access log: the privacy policy promises that requests (and client IPs) are not logged.
access_log off;
# Clients ping every 30 s; idle WebSockets must survive well past that.
proxy_read_timeout 120s;
proxy_send_timeout 120s;
# The relay caps JSON bodies at 16 KiB (413 with its own error code); stop anything far bigger here.
client_max_body_size 32k;
```

Create `deploy/nginx-proxy/shellx.pro`:

```nginx
# nginx-proxy settings for shellx.pro, copied once into nginx-proxy's vhost.d (deploy/README.md, step 5).
# No access log: the privacy policy promises that visits (and client IPs) are not logged.
access_log off;
```

Create `deploy/nginx-proxy/www.shellx.pro`:

```nginx
# nginx-proxy settings for www.shellx.pro, copied once into nginx-proxy's vhost.d (deploy/README.md, step 5).
# No access log: the privacy policy promises that visits (and client IPs) are not logged.
access_log off;
```

Create `deploy/nginx-proxy/download.shellx.pro`:

```nginx
# nginx-proxy settings for download.shellx.pro, copied once into nginx-proxy's vhost.d (deploy/README.md, step 5).
# No access log: the privacy policy promises that visits (and client IPs) are not logged.
access_log off;
```

(Spec §3 names only `relay.shellx.pro`; the three one-line files for the web names keep the privacy promise "no access log" true at the proxy too — see the plan's report. They are the same kind of vhost.d exception.)

- [ ] **Step 6: Validate the Compose file**

From the repository root:

```bash
cd deploy && IMAGE_TAG=test PROXY_NETWORK=proxy-net docker compose config --quiet && echo "compose OK"
IMAGE_TAG=test PROXY_NETWORK=proxy-net docker compose config | grep -E '^name:|image:|max-size|stop_grace_period|external: true'
docker compose config --quiet 2>&1 | head -1; cd ..
```

Expected: `compose OK`; the second command shows `name: shellx`, the three images (`ghcr.io/lephus/shellx-relay:test`, `ghcr.io/lephus/shellx-web:test`, `alpine:3.22`), `max-size: 10m` four times (the `x-logging` anchor and its three uses), `stop_grace_period: 10s` and `external: true`; the last command (no variables) must fail — recent Compose prints `required variable IMAGE_TAG is missing a value: IMAGE_TAG is not set in .env`, Compose 2.15 prints `invalid interpolation format for services.relay.image.`

- [ ] **Step 7: Run the real stack locally with `rollout.sh` (healthy, then rollback)**

This uses the images built in Task 6 under the GHCR names and a wrapper that skips `docker compose pull` (the images are local only). From the repository root:

```bash
W=$(mktemp -d) && mkdir -p "$W/home/phu/shellx" "$W/bin"
cp deploy/docker-compose.yml deploy/relay.env "$W/home/phu/shellx/" && cp -R deploy/backup deploy/nginx-proxy "$W/home/phu/shellx/"
printf 'PROXY_NETWORK=shellx-local-proxy\n' > "$W/home/phu/shellx/.env" && docker network create shellx-local-proxy
docker tag shellx-relay:local ghcr.io/lephus/shellx-relay:good && docker tag shellx-web:local ghcr.io/lephus/shellx-web:good && docker tag shellx-web:local ghcr.io/lephus/shellx-web:broken
printf 'FROM shellx-relay:local\nCMD ["node", "-e", "setInterval(() => {}, 1000)"]\n' | docker build -q -t ghcr.io/lephus/shellx-relay:broken -
printf '#!/bin/sh\nif [ "$1 $2" = "compose pull" ]; then exit 0; fi\nexec %s "$@"\n' "$(command -v docker)" > "$W/bin/docker" && chmod +x "$W/bin/docker"
env PATH="$W/bin:$PATH" HOME="$W/home" RELAY_UID="$(id -u)" bash deploy/rollout.sh good phu/shellx; echo "exit=$?"
env PATH="$W/bin:$PATH" HOME="$W/home" RELAY_UID="$(id -u)" HEALTH_TIMEOUT_SECONDS=20 bash deploy/rollout.sh broken phu/shellx; echo "exit=$?"
cat "$W/home/phu/shellx/.env"
(cd "$W/home/phu/shellx" && docker compose exec -T backup sh /backup/backup-once.sh && docker compose exec -T relay node dist/scripts/reset-password.js --email nobody@example.com --yes; docker compose ps)
(cd "$W/home/phu/shellx" && docker compose down) && docker network rm shellx-local-proxy
docker image rm ghcr.io/lephus/shellx-relay:good ghcr.io/lephus/shellx-relay:broken ghcr.io/lephus/shellx-web:good ghcr.io/lephus/shellx-web:broken
```

Expected: `relay is healthy on good` and `exit=0` (after ≈ 12 s); then `::error::relay not healthy within 20s on broken; rolling back to good` and `exit=1`; `.env` ends with `IMAGE_TAG=good`; `backup: wrote /backups/relay-<today>.db`; the reset script prints `No account with email nobody@example.com in /data/relay.db; nothing changed.`; `docker compose ps` shows `relay` on `…shellx-relay:good` `(healthy)`, `web` and `backup` up.

- [ ] **Step 8: Write the runbook**

Create `deploy/README.md`:

````markdown
# Deploying ShellX to the VPS

Everything ShellX puts on the VPS lives in **one folder, `~/phu/shellx`**, in the home of the SSH
user that deploys (decision V8, `docs/superpowers/specs/2026-09-26-shellx-vps-infra-design.md`).
The only exception is four small files copied once into nginx-proxy's `vhost.d` directory (step 5).

```
~/phu/shellx/
  docker-compose.yml     # from deploy/docker-compose.yml (compose project "shellx")
  relay.env              # from deploy/relay.env (versions, download links; no secrets)
  .env                   # IMAGE_TAG (written by deploy.yml) and PROXY_NETWORK (written by you, once)
  data/relay.db          # the SQLite database (bind mount ./data:/data, owned by uid 1000)
  backups/relay-<YYYY-MM-DD>.db   # daily at 03:00, the 14 newest are kept
  downloads/desktop/<version>/    # installers, uploaded by release-desktop.yml
  nginx-proxy/           # from deploy/nginx-proxy/: the originals of the vhost.d files (step 5)
  backup/                # from deploy/backup/: the backup container's scripts
```

| Container | Image | What it does |
|---|---|---|
| `relay` | `ghcr.io/lephus/shellx-relay:<commit>` | `relay.shellx.pro` (REST + WebSocket), port 8080 on the proxy network only |
| `web` | `ghcr.io/lephus/shellx-web:<commit>` | `shellx.pro`, `www.shellx.pro` (→ `shellx.pro`), `download.shellx.pro` |
| `backup` | `alpine:3.22` + sqlite | `sqlite3 .backup` of `data/relay.db` every day at 03:00 VPS time |

Pushing to `main` a change under `relay/`, `web/`, `deploy/` or `.github/workflows/deploy.yml` runs
`.github/workflows/deploy.yml`: build both images (the relay build runs every relay test; the web
build refuses the `[quốc gia]` placeholder and checks pages and links), push them to GHCR, rsync
`docker-compose.yml`, `relay.env`, `nginx-proxy/` and `backup/` into `~/phu/shellx`, then run
`deploy/rollout.sh` over SSH: pull, set `IMAGE_TAG`, `docker compose up -d --remove-orphans`, wait
up to 60 s for the relay's healthcheck, and put the previous `IMAGE_TAG` back if it never turns
healthy. Finally it checks `https://relay.shellx.pro/v1/version` and `https://shellx.pro/`.

## First-time setup

Do this after the DNS A records of `shellx.pro`, `www`, `relay` and `download` point at the VPS:
letsencrypt-companion can only get certificates for names that resolve to it. Run the commands on
the VPS as the deploy user unless a step says otherwise.

1. **Deploy user and folder.** Use an existing user or create one (`sudo adduser shellx`); it must be
   in the `docker` group (`sudo usermod -aG docker <user>`, then log in again). On your own machine,
   create a key used only for deploys: `ssh-keygen -t ed25519 -f shellx-deploy -C shellx-deploy -N ''`,
   and append `shellx-deploy.pub` to the deploy user's `~/.ssh/authorized_keys`. Then, on the VPS:

   ```bash
   mkdir -p ~/phu/shellx/{data,backups,downloads/desktop,nginx-proxy,backup}
   sudo chown 1000:1000 ~/phu/shellx/data      # the relay runs as uid 1000 (node) and must write here
   ```
2. **Proxy network.** Find the Docker network of nginx-proxy (`docker network ls`; it is the network
   the `nginx-proxy` container is attached to, see `docker inspect nginx-proxy`) and record it:

   ```bash
   echo "PROXY_NETWORK=<that network name>" > ~/phu/shellx/.env
   ```
3. **GitHub.** On your machine run `ssh-keyscan -t ed25519 <VPS address>` and compare the printed key
   with the VPS's own `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` fingerprint (`ssh-keygen -lf -`
   on the scanned line). Then, in the repository: Settings → Secrets and variables → Actions:
   - **Repository secrets:** `VPS_HOST` (address), `VPS_USER` (deploy user), `VPS_SSH_KEY` (the whole
     private key file `shellx-deploy`), `VPS_KNOWN_HOSTS` (the verified `ssh-keyscan` line).
   - **Variables:** `VPS_APP_DIR` = `phu/shellx` (optional: that is the default). It is relative to
     the deploy user's home.
   - Remove the old `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` secrets.
4. **First deploy.** Push to `main` or run **Actions → Deploy → Run workflow**. The first run pushes
   the two images to GHCR as *private* packages, so the VPS cannot pull them and the run fails at
   the pull step. Make both public once — github.com/lephus → Packages → `shellx-relay` and
   `shellx-web` → Package settings → Change visibility → Public (they contain no secrets) — then
   re-run the workflow.
5. **nginx-proxy settings (the only files outside the folder).** After the first deploy synced
   `~/phu/shellx/nginx-proxy/`, copy its four files into nginx-proxy's `vhost.d` directory, then
   recreate the ShellX containers so nginx-proxy regenerates its configuration:

   ```bash
   PROXY=nginx-proxy   # the name of the nginx-proxy container (docker ps)
   VHOST_D="$(docker inspect "$PROXY" --format '{{range .Mounts}}{{if eq .Destination "/etc/nginx/vhost.d"}}{{.Source}}{{end}}{{end}}')"
   echo "$VHOST_D"     # must print a directory; stop here if it is empty
   for f in relay.shellx.pro shellx.pro www.shellx.pro download.shellx.pro; do
     sudo cp ~/phu/shellx/nginx-proxy/$f "$VHOST_D/$f"
   done
   cd ~/phu/shellx && docker compose up -d --force-recreate relay web
   docker exec "$PROXY" nginx -T 2>/dev/null | grep -A3 'server_name relay.shellx.pro' | head   # shows the include
   ```

   Copy, do not symlink: a link to `~/phu/shellx/...` would point nowhere inside the proxy
   container. A plain `nginx -s reload` is not enough either: nginx-proxy only includes
   `vhost.d/<host>` if the file existed when it last generated its configuration, which it does on
   container start/stop events. The letsencrypt companion may append its own
   `## Start of configuration add by letsencrypt container` block to these files; keep it. These
   files turn access logs off for the four names (the privacy policy promises no access logs), give
   the relay's WebSockets 120 s timeouts and cap request bodies at 32 KiB. If `deploy/nginx-proxy/`
   ever changes, edit the copies in `vhost.d` the same way (keeping the companion's block) and
   recreate the containers again.
6. **Check.**

   ```bash
   curl https://relay.shellx.pro/v1/version
   curl -sI https://shellx.pro/ | head -1                   # HTTP/2 200
   curl -sI https://www.shellx.pro/privacy/ | grep -i ^location   # https://shellx.pro/privacy/
   docker compose -f ~/phu/shellx/docker-compose.yml ps     # relay (healthy), web, backup
   ```

The website only builds once the country hosting the VPS replaces `[quốc gia]` in
`web/src/pages/privacy.md`, `web/src/pages/en/privacy.md`, `web/src/pages/terms.md` and
`web/src/pages/en/terms.md` (update their `updated:` dates too). Until then every deploy stops at the
web image build, so fill it in before the first deploy.

## Operations

All commands run in `~/phu/shellx`.

- **Logs:** `docker compose logs -f relay` (metadata only: time, `device_id`, error kind; never IPs,
  e-mail addresses, tokens or payloads). Docker keeps at most 3 × 10 MB per container.
- **Roll back:** Actions → Deploy → Run workflow with `ref` = an older commit SHA (images are rebuilt
  from that commit), or on the VPS set `IMAGE_TAG=<older sha>` in `.env` and run
  `docker compose up -d`. Images of every deployed commit stay in GHCR.
- **Versions and download links:** edit `deploy/relay.env` and push `main`.
- **Emergency password reset:** see `relay/README.md` (`docker compose exec relay node dist/scripts/reset-password.js …`).
- **Backups:** `backups/relay-<date>.db`, written at 03:00 VPS time; the 14 newest are kept. The
  backup reads the live database through a read-only mount, which needs the relay running; while
  the relay is stopped the backup is skipped (`docker compose logs backup` says so) and nothing is
  lost, since a stopped relay changes nothing. Copy them off the VPS if you like, e.g. from your
  machine: `rsync -a <user>@<vps>:phu/shellx/backups/ ./shellx-backups/` — and delete copies older
  than 14 days, because the privacy policy says deleted data survives in backups for at most 14 days.
- **Restore a backup:**

  ```bash
  docker compose stop relay
  cp backups/relay-2026-10-01.db data/relay.db && rm -f data/relay.db-wal data/relay.db-shm
  sudo chown 1000:1000 data/relay.db
  docker compose start relay
  ```
- **Rebuild on a new VPS:** repeat the first-time setup, copy the newest backup to `data/relay.db`
  (as above) and the installers to `downloads/`, then re-run the Deploy workflow.

## Tests of the deploy scripts

`node --test deploy/tests/*.test.mjs` runs `rollout.sh` against a fake `docker` (health, rollback,
pull failure, missing `PROXY_NETWORK`, wrong `data/` owner) and `backup/backup-once.sh` with the
local `sqlite3` (rotation, missing and unreadable databases).
````

- [ ] **Step 9: Commit**

```bash
git add deploy
git commit -m "feat(deploy): compose project for ~/phu/shellx, daily backups, vhost files, rollout with rollback, runbook"
```

### Task 8: Workflows — `deploy.yml` (CD), `release-desktop.yml` over rsync, delete `ci.yml`

There is no CI any more (V5): `ci.yml` goes. `deploy.yml` builds both images (the relay build runs the relay tests, the web build refuses `[quốc gia]`), pushes them to GHCR with the commit SHA as tag, syncs the deploy files into `VPS_APP_DIR` and runs `deploy/rollout.sh` over SSH with a pinned host key, then checks the public endpoints with retries. `release-desktop.yml` keeps build/sign/notarize and uploads the installers with rsync into `VPS_APP_DIR/downloads/desktop/<version>/`. No third-party actions are added: GHCR login, SSH and rsync use the runner's own tools.

**Files:**
- Create: `.github/workflows/deploy.yml`
- Modify: `.github/workflows/release-desktop.yml`, `release/README.md`
- Delete: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `relay/Dockerfile`, `web/Dockerfile` (Task 6); `deploy/docker-compose.yml`, `deploy/relay.env`, `deploy/nginx-proxy/`, `deploy/backup/`, `deploy/rollout.sh <image-tag> <app-dir>` (Task 7).
- Produces: workflow `Deploy` (push `main` with changes under `relay/**`, `web/**`, `deploy/**`, `.github/workflows/deploy.yml`, or manual with input `ref`); repository secrets `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY`, `VPS_KNOWN_HOSTS` and variable `VPS_APP_DIR` (default `phu/shellx`) used by both workflows; `release-desktop.yml` job `publish` named "Upload to download.shellx.pro".

- [ ] **Step 1: Write the failing check**

From the repository root, this check encodes the goal (valid YAML, no Cloudflare left, no CI):

```bash
cat > /tmp/check-workflows.sh <<'CHECK'
set -e
if test -e .github/workflows/ci.yml; then echo "ci.yml still exists"; exit 1; fi
python3 -c 'import sys, yaml; [yaml.safe_load(open(f)) for f in sys.argv[1:]]; print("yaml OK")' .github/workflows/deploy.yml .github/workflows/release-desktop.yml
if grep -n -i -E "cloudflare|wrangler|R2_BUCKET|\bR2\b" .github/workflows/*.yml release/README.md | grep -v "Delete the old .CLOUDFLARE_API_TOKEN"; then
  echo "Cloudflare/R2 still mentioned (lines above)"; exit 1
fi
grep -q "VPS_APP_DIR || 'phu/shellx'" .github/workflows/deploy.yml
grep -q "VPS_APP_DIR || 'phu/shellx'" .github/workflows/release-desktop.yml
grep -q "StrictHostKeyChecking yes" .github/workflows/deploy.yml
grep -q "StrictHostKeyChecking yes" .github/workflows/release-desktop.yml
echo "workflows OK"
CHECK
bash /tmp/check-workflows.sh
```

- [ ] **Step 2: Run it to verify it fails**

Expected: FAIL — `ci.yml still exists`.

- [ ] **Step 3: Create `deploy.yml`, delete `ci.yml`, rewrite the publish job**

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy

# Continuous deployment to the VPS (VPS spec §6.1). There is no CI (decision V5): building the relay
# image runs every relay test, so a failing test stops the deploy before anything is pushed.
on:
  push:
    branches: [main]
    paths:
      - 'relay/**'
      - 'web/**'
      - 'deploy/**'
      - '.github/workflows/deploy.yml'
  workflow_dispatch:
    inputs:
      ref:
        description: 'Commit SHA, tag or branch to deploy (empty = the selected branch). Pick an older commit to roll back.'
        required: false
        type: string

permissions:
  contents: read
  packages: write

concurrency:
  group: deploy-production
  cancel-in-progress: false

env:
  RELAY_IMAGE: ghcr.io/lephus/shellx-relay
  WEB_IMAGE: ghcr.io/lephus/shellx-web
  # ShellX's one folder on the VPS, relative to the deploy user's home (decision V8).
  APP_DIR: ${{ vars.VPS_APP_DIR || 'phu/shellx' }}

jobs:
  deploy:
    name: Build, push and roll out
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v7
        with:
          ref: ${{ inputs.ref || github.sha }}

      - name: Resolve the commit and check VPS_APP_DIR
        id: commit
        run: |
          echo "sha=$(git rev-parse HEAD)" >> "$GITHUB_OUTPUT"
          if [[ ! "$APP_DIR" =~ ^[A-Za-z0-9._/-]+$ ]]; then
            echo "::error::VPS_APP_DIR may contain only letters, digits and . _ - /"
            exit 1
          fi

      - name: Log in to GHCR
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: printf '%s' "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_ACTOR" --password-stdin

      - name: Build the relay image (runs the relay tests)
        env:
          SHA: ${{ steps.commit.outputs.sha }}
        run: docker build -t "$RELAY_IMAGE:$SHA" relay

      - name: Build the web image (refuses the [quốc gia] placeholder, checks pages and links)
        env:
          SHA: ${{ steps.commit.outputs.sha }}
        run: docker build -f web/Dockerfile -t "$WEB_IMAGE:$SHA" .

      - name: Push both images
        env:
          SHA: ${{ steps.commit.outputs.sha }}
        run: |
          docker push "$RELAY_IMAGE:$SHA"
          docker push "$WEB_IMAGE:$SHA"

      - name: Install the deploy SSH key (host key pinned by VPS_KNOWN_HOSTS)
        env:
          VPS_HOST: ${{ secrets.VPS_HOST }}
          VPS_USER: ${{ secrets.VPS_USER }}
          VPS_SSH_KEY: ${{ secrets.VPS_SSH_KEY }}
          VPS_KNOWN_HOSTS: ${{ secrets.VPS_KNOWN_HOSTS }}
        run: |
          install -d -m 700 ~/.ssh
          printf '%s\n' "$VPS_SSH_KEY" > ~/.ssh/deploy_key
          chmod 600 ~/.ssh/deploy_key
          printf '%s\n' "$VPS_KNOWN_HOSTS" > ~/.ssh/known_hosts
          chmod 644 ~/.ssh/known_hosts
          {
            echo "Host vps"
            echo "  HostName $VPS_HOST"
            echo "  User $VPS_USER"
            echo "  IdentityFile ~/.ssh/deploy_key"
            echo "  IdentitiesOnly yes"
            echo "  StrictHostKeyChecking yes"
            echo "  UserKnownHostsFile ~/.ssh/known_hosts"
            echo "  BatchMode yes"
          } > ~/.ssh/config
          chmod 600 ~/.ssh/config

      - name: Sync the deploy files into VPS_APP_DIR
        run: |
          ssh vps "mkdir -p '$APP_DIR/nginx-proxy' '$APP_DIR/backup'"
          rsync -rt --chmod=D755,F644 deploy/docker-compose.yml deploy/relay.env "vps:$APP_DIR/"
          rsync -rt --delete --chmod=D755,F644 deploy/nginx-proxy/ "vps:$APP_DIR/nginx-proxy/"
          rsync -rt --delete --chmod=D755,F644 deploy/backup/ "vps:$APP_DIR/backup/"

      - name: Roll out (the previous IMAGE_TAG comes back if the relay is not healthy within 60 s)
        env:
          SHA: ${{ steps.commit.outputs.sha }}
        run: ssh vps bash -s -- "$SHA" "$APP_DIR" < deploy/rollout.sh

      - name: Check the public endpoints (retries while a first certificate is issued)
        run: |
          check() {
            for attempt in $(seq 1 10); do
              if curl -fsS -o /dev/null "$1"; then
                echo "$1 answers"
                return 0
              fi
              echo "$1 not answering yet (attempt $attempt/10)"
              sleep 15
            done
            echo "::error::$1 did not answer after 10 attempts"
            return 1
          }
          check https://relay.shellx.pro/v1/version
          check https://shellx.pro/

      - name: Remove the SSH key
        if: always()
        run: rm -f ~/.ssh/deploy_key ~/.ssh/config
```

```bash
git rm -q .github/workflows/ci.yml
```

Apply the `release-desktop.yml` changes with this script (save it as `/tmp/edit-release-desktop.py`, run `python3 /tmp/edit-release-desktop.py` from the repository root; it refuses to write anything if a block is not found exactly once). It removes `WRANGLER_VERSION`/`R2_BUCKET`, adds `APP_DIR`, drops the Cloudflare secrets and the `setup-node` step of `publish`, installs the SSH key with strict host checking, replaces the wrangler upload with rsync, keeps the "refuse to overwrite" and "verify public download URLs" (size) steps, and removes the key at the end:

```python
# Task 8: rewrites the Cloudflare/R2 parts of release-desktop.yml. Run from the repository root:
#   python3 edit-release-desktop.py
# Every replaced block must occur exactly once, otherwise nothing is written.
from pathlib import Path

path = Path(".github/workflows/release-desktop.yml")
text = path.read_text(encoding="utf-8")
EDITS = [
    (
        "        description: 'Dry run: build and package only, skip signing, notarization and upload to R2'",
        "        description: 'Dry run: build and package only, skip signing, notarization and upload to download.shellx.pro'",
    ),
    (
        """env:
  FLUTTER_VERSION: 3.41.7
  NODE_VERSION: 22
  WRANGLER_VERSION: 4.139.0
  R2_BUCKET: shellx-downloads
  DOWNLOAD_BASE_URL: https://download.shellx.pro
""",
        """env:
  FLUTTER_VERSION: 3.41.7
  NODE_VERSION: 22
  DOWNLOAD_BASE_URL: https://download.shellx.pro
  # ShellX's one folder on the VPS, relative to the deploy user's home (VPS spec V8).
  APP_DIR: ${{ vars.VPS_APP_DIR || 'phu/shellx' }}
""",
    ),
    (
        """    # The 13 signing/publish secrets live only in this GitHub Environment, admitted for
    # desktop-v* tags and main branch (dry runs on main use no secrets; publish also requires
    # a desktop-v* tag). Non-dry-run steps access secrets; dry runs fall back to ad-hoc signing.""",
        """    # The 11 signing secrets live only in this GitHub Environment, admitted for desktop-v* tags and
    # main branch (dry runs on main use no secrets; publish also requires a desktop-v* tag). Non-dry-run
    # steps access secrets; dry runs fall back to ad-hoc signing.""",
    ),
    (
        """  publish:
    name: Upload to R2
""",
        """  publish:
    name: Upload to download.shellx.pro
""",
    ),
    (
        """    # See the comment on the macos job: the Cloudflare secrets live only in this Environment.
    environment: release
    env:
      VERSION: ${{ needs.prepare.outputs.version }}
      CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
      CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
      WRANGLER_SEND_METRICS: false
    steps:
      - uses: actions/setup-node@v7
        with:
          node-version: ${{ env.NODE_VERSION }}
      - uses: actions/download-artifact@v8""",
        """    # Same Environment gate as the signing jobs. The VPS_* secrets are repository secrets shared
    # with deploy.yml; this job only ever writes into $APP_DIR/downloads on the VPS.
    environment: release
    env:
      VERSION: ${{ needs.prepare.outputs.version }}
    steps:
      - uses: actions/download-artifact@v8""",
    ),
    (
        """              000) echo "::error::cannot reach $DOWNLOAD_BASE_URL (is the R2 custom domain set up?)"; exit 1 ;;""",
        """              000) echo "::error::cannot reach $DOWNLOAD_BASE_URL (is the web container on the VPS running?)"; exit 1 ;;""",
    ),
    (
        """      - name: Upload installers
        run: |
          put() {
            npx --yes "wrangler@$WRANGLER_VERSION" r2 object put "$R2_BUCKET/desktop/$VERSION/$1" \\
              --remote --file "dist/$1" --content-type "$2" \\
              --content-disposition "attachment; filename=\\"$1\\"" \\
              --cache-control "public, max-age=31536000, immutable"
          }
          put "ShellX-$VERSION.dmg" application/x-apple-diskimage
          put "ShellX-Setup-$VERSION.exe" application/vnd.microsoft.portable-executable
""",
        """      - name: Install the deploy SSH key (host key pinned by VPS_KNOWN_HOSTS)
        env:
          VPS_HOST: ${{ secrets.VPS_HOST }}
          VPS_USER: ${{ secrets.VPS_USER }}
          VPS_SSH_KEY: ${{ secrets.VPS_SSH_KEY }}
          VPS_KNOWN_HOSTS: ${{ secrets.VPS_KNOWN_HOSTS }}
        run: |
          if [[ ! "$APP_DIR" =~ ^[A-Za-z0-9._/-]+$ ]]; then
            echo "::error::VPS_APP_DIR may contain only letters, digits and . _ - /"
            exit 1
          fi
          install -d -m 700 ~/.ssh
          printf '%s\\n' "$VPS_SSH_KEY" > ~/.ssh/deploy_key
          chmod 600 ~/.ssh/deploy_key
          printf '%s\\n' "$VPS_KNOWN_HOSTS" > ~/.ssh/known_hosts
          chmod 644 ~/.ssh/known_hosts
          {
            echo "Host vps"
            echo "  HostName $VPS_HOST"
            echo "  User $VPS_USER"
            echo "  IdentityFile ~/.ssh/deploy_key"
            echo "  IdentitiesOnly yes"
            echo "  StrictHostKeyChecking yes"
            echo "  UserKnownHostsFile ~/.ssh/known_hosts"
            echo "  BatchMode yes"
          } > ~/.ssh/config
          chmod 600 ~/.ssh/config
      - name: Upload installers (rsync into VPS_APP_DIR/downloads/desktop/<version>/)
        run: |
          ssh vps "mkdir -p '$APP_DIR/downloads/desktop/$VERSION'"
          rsync -t --chmod=F644 "dist/ShellX-$VERSION.dmg" "dist/ShellX-Setup-$VERSION.exe" \\
            "vps:$APP_DIR/downloads/desktop/$VERSION/"
""",
    ),
]
for old, new in EDITS:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one occurrence, found {count}: {old[:70]!r}")
    text = text.replace(old, new)
text = text.rstrip("\n") + """
      - name: Remove the SSH key
        if: always()
        run: rm -f ~/.ssh/deploy_key ~/.ssh/config
"""
path.write_text(text, encoding="utf-8")
print(f"release-desktop.yml: {len(EDITS)} edits applied")
```

After it, the `publish` job must read exactly:

```yaml
  publish:
    name: Upload to download.shellx.pro
    needs: [prepare, macos, windows]
    # Defense in depth: dry_run == 'false' already requires a desktop-v* tag (resolve-version.mjs
    # refuses a manual real release from a branch), but require the tag here too so publish never
    # runs from anywhere else even if that check regresses.
    if: needs.prepare.outputs.dry_run == 'false' && startsWith(github.ref, 'refs/tags/desktop-v')
    runs-on: ubuntu-latest
    timeout-minutes: 15
    # Same Environment gate as the signing jobs. The VPS_* secrets are repository secrets shared
    # with deploy.yml; this job only ever writes into $APP_DIR/downloads on the VPS.
    environment: release
    env:
      VERSION: ${{ needs.prepare.outputs.version }}
    steps:
      - uses: actions/download-artifact@v8
        with:
          path: dist
          merge-multiple: true
      - name: Refuse to overwrite a published version
        run: |
          for name in "ShellX-$VERSION.dmg" "ShellX-Setup-$VERSION.exe"; do
            test -f "dist/$name" || { echo "::error::missing artifact $name"; exit 1; }
            url="$DOWNLOAD_BASE_URL/desktop/$VERSION/$name"
            # Unique query string: never read (or seed) a cached 404 for the real URL.
            code="$(curl -s -o /dev/null -w '%{http_code}' "$url?precheck=$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT" || true)"
            case "$code" in
              404) echo "$url is free" ;;
              000) echo "::error::cannot reach $DOWNLOAD_BASE_URL (is the web container on the VPS running?)"; exit 1 ;;
              *) echo "::error::$url already answers HTTP $code; bump the version instead of overwriting"; exit 1 ;;
            esac
          done
      - name: Install the deploy SSH key (host key pinned by VPS_KNOWN_HOSTS)
        env:
          VPS_HOST: ${{ secrets.VPS_HOST }}
          VPS_USER: ${{ secrets.VPS_USER }}
          VPS_SSH_KEY: ${{ secrets.VPS_SSH_KEY }}
          VPS_KNOWN_HOSTS: ${{ secrets.VPS_KNOWN_HOSTS }}
        run: |
          if [[ ! "$APP_DIR" =~ ^[A-Za-z0-9._/-]+$ ]]; then
            echo "::error::VPS_APP_DIR may contain only letters, digits and . _ - /"
            exit 1
          fi
          install -d -m 700 ~/.ssh
          printf '%s\n' "$VPS_SSH_KEY" > ~/.ssh/deploy_key
          chmod 600 ~/.ssh/deploy_key
          printf '%s\n' "$VPS_KNOWN_HOSTS" > ~/.ssh/known_hosts
          chmod 644 ~/.ssh/known_hosts
          {
            echo "Host vps"
            echo "  HostName $VPS_HOST"
            echo "  User $VPS_USER"
            echo "  IdentityFile ~/.ssh/deploy_key"
            echo "  IdentitiesOnly yes"
            echo "  StrictHostKeyChecking yes"
            echo "  UserKnownHostsFile ~/.ssh/known_hosts"
            echo "  BatchMode yes"
          } > ~/.ssh/config
          chmod 600 ~/.ssh/config
      - name: Upload installers (rsync into VPS_APP_DIR/downloads/desktop/<version>/)
        run: |
          ssh vps "mkdir -p '$APP_DIR/downloads/desktop/$VERSION'"
          rsync -t --chmod=F644 "dist/ShellX-$VERSION.dmg" "dist/ShellX-Setup-$VERSION.exe" \
            "vps:$APP_DIR/downloads/desktop/$VERSION/"
      - name: Verify public download URLs
        run: |
          {
            echo "## ShellX desktop $VERSION"
            echo
            echo "| File | URL | SHA-256 |"
            echo "|---|---|---|"
          } >> "$GITHUB_STEP_SUMMARY"
          for name in "ShellX-$VERSION.dmg" "ShellX-Setup-$VERSION.exe"; do
            url="$DOWNLOAD_BASE_URL/desktop/$VERSION/$name"
            remote_size="$(curl -sfIL "$url?verify=$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT" | tr -d '\r' | awk 'tolower($1) == "content-length:" { size = $2 } END { print size }')"
            local_size="$(stat -c %s "dist/$name")"
            if [[ "$remote_size" != "$local_size" ]]; then
              echo "::error::$url has size '$remote_size', expected $local_size"
              exit 1
            fi
            echo "| $name | $url | $(sha256sum "dist/$name" | cut -d' ' -f1) |" >> "$GITHUB_STEP_SUMMARY"
          done
      - name: Remove the SSH key
        if: always()
        run: rm -f ~/.ssh/deploy_key ~/.ssh/config
```

Apply the `release/README.md` changes the same way (`/tmp/edit-release-readme.py`, run from the repository root):

```python
# Task 8: replaces the R2/Cloudflare/CI parts of release/README.md. Run from the repository root.
# Every replaced block must occur exactly once, otherwise nothing is written.
from pathlib import Path

path = Path("release/README.md")
text = path.read_text(encoding="utf-8")
EDITS = [
    (
        "- Pushing a tag `desktop-vX.Y.Z` runs a real release: build, sign, notarize, upload to R2.",
        "- Pushing a tag `desktop-vX.Y.Z` runs a real release: build, sign, notarize, upload to\n"
        "  `download.shellx.pro` (rsync into the VPS folder `downloads/desktop/<version>/`).",
    ),
    (
        """**Why `wrangler r2 object put` for the upload:** it is the tool the relay already uses, it
authenticates with one Cloudflare API token (no separate S3 access key pair, endpoint URL or AWS
CLI configuration), and it sets `Content-Type`, `Content-Disposition` and `Cache-Control` in one
command. Its 300 MiB single-upload limit is far above the installer sizes. `--remote` is
mandatory: without it Wrangler 4 writes to a local simulated bucket and still reports success.""",
        """**Upload:** the `publish` job rsyncs both files over SSH into
`$VPS_APP_DIR/downloads/desktop/<version>/` on the VPS (default `~/phu/shellx`), with the same
`VPS_*` secrets as `deploy.yml`. The `web` container serves that folder at `download.shellx.pro`
with `Content-Disposition: attachment` and a one-year immutable `Cache-Control`
(`deploy/web/nginx.conf`). rsync writes to a temporary name and renames it, so a half-uploaded file
is never served under the real name.""",
    ),
    (
        "All 13 secrets below must be created as **Environment secrets** of a GitHub Environment named",
        "All 11 secrets below must be created as **Environment secrets** of a GitHub Environment named",
    ),
    (
        """| `CLOUDFLARE_API_TOKEN` | publish | API token with **Account → Workers R2 Storage → Edit** |
| `CLOUDFLARE_ACCOUNT_ID` | publish | Cloudflare account ID that owns the R2 bucket and the `shellx.pro` zone |

The bucket name (`shellx-downloads`), the public base URL (`https://download.shellx.pro`), Flutter
3.41.7 and Wrangler 4.139.0 are pinned in the workflow's `env:` block. The workflow expects the
names fixed by `apps/desktop`: `ShellX.app` with bundle id `pro.shellx.desktop`, and `ShellX.exe`.""",
        """The `publish` job also reads the **repository** secrets `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY`,
`VPS_KNOWN_HOSTS` and the variable `VPS_APP_DIR`, shared with `deploy.yml` (see `deploy/README.md`).
Delete the old `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` secrets.

The public base URL (`https://download.shellx.pro`) and Flutter 3.41.7 are pinned in the workflow's
`env:` block. The workflow expects the names fixed by `apps/desktop`: `ShellX.app` with bundle id
`pro.shellx.desktop`, and `ShellX.exe`.""",
    ),
    (
        """### 3. Cloudflare R2 and `download.shellx.pro`

1. R2 → **Create bucket** → name `shellx-downloads`.
2. Bucket → Settings → **Custom Domains** → Add → `download.shellx.pro` → Connect. Leave the
   `r2.dev` public URL disabled.
3. My Profile → API Tokens → **Create Token** → Custom token → Permissions: **Account → Workers R2
   Storage → Edit**, Account resources: the ShellX account → `CLOUDFLARE_API_TOKEN`.
4. Account ID (Workers & Pages overview, right column) → `CLOUDFLARE_ACCOUNT_ID`.
5. Check: `curl -s -o /dev/null -w '%{http_code}\\n' https://download.shellx.pro/desktop/0.0.0/none`
   prints `404`.""",
        """### 3. `download.shellx.pro` on the VPS

1. Set up the VPS as described in `deploy/README.md`: the `web` container serves
   `~/phu/shellx/downloads/` at `download.shellx.pro`, and the four `VPS_*` repository secrets let
   the `publish` job upload into it.
2. Check: `curl -s -o /dev/null -w '%{http_code}\\n' https://download.shellx.pro/desktop/0.0.0/none`
   prints `404`.""",
    ),
    (
        """   access secrets; optionally add required reviewers), then add the 13 secrets above to it""",
        """   access secrets; optionally add required reviewers), then add the 11 secrets above to it""",
    ),
    (
        """4. After the first full CI run on `feat/shellx-v1` → `main` finishes, make the `CI result` check
   required on `main`: Settings → Branches (or Rules → Rulesets) → add a rule for `main` →
   **Require status checks to pass before merging** → select `CI result`.""",
        """4. There is no CI (VPS spec, decision V5): run the Dart, desktop and mobile tests on your machine
   before merging to `main` and before tagging.""",
    ),
    (
        """`"desktopVersion": "1.0.0"` (see `web/README.md`). If the website is deployed before this
procedure has published `1.0.0` to R2, its download buttons 404. Run this whole procedure for
`1.0.0` — through step 5 (Relay) at least — before the branch containing `web/` is merged to `main`
and deployed by Cloudflare Pages; step 6 below then only has to confirm the version already
matches.""",
        """`"desktopVersion": "1.0.0"` (see `web/README.md`). If the website is deployed before this
procedure has published `1.0.0` to `download.shellx.pro`, its download buttons 404. Run this whole
procedure for `1.0.0` — through step 5 (Relay) at least — before the branch containing `web/` is
merged to `main` and deployed by `deploy.yml`; step 6 below then only has to confirm the version
already matches.""",
    ),
    (
        """1. Set `version: X.Y.Z+N` in `apps/desktop/pubspec.yaml` (increase `N` every release), merge to
   `main`, wait for CI.""",
        """1. Set `version: X.Y.Z+N` in `apps/desktop/pubspec.yaml` (increase `N` every release), run the
   desktop tests locally, merge to `main`.""",
    ),
    (
        """5. **Relay:** in `relay/wrangler.jsonc`, edit the `vars` of the production environment
   (`env.production.vars`), which feed `GET /v1/version`:""",
        """5. **Relay:** in `deploy/relay.env`, edit the values that feed `GET /v1/version`:""",
    ),
    (
        """   Deploy the relay to production (see `relay/README.md`), then check that""",
        """   Push to `main`: `deploy.yml` restarts the relay with the new values. Then check that""",
    ),
    (
        """   pass), merge to `main`. Cloudflare Pages deploys it.""",
        """   pass), merge to `main`; `deploy.yml` deploys it.""",
    ),
    (
        """website. The relay and the website must never link to files that are not on R2 yet.""",
        """website. The relay and the website must never link to files that are not on `download.shellx.pro` yet.""",
    ),
    (
        """- **`publish` failed after uploading one file:** delete it with
  `npx wrangler@4.139.0 r2 object delete shellx-downloads/desktop/X.Y.Z/<file> --remote`, then
  **Re-run failed jobs**.""",
        """- **`publish` failed after uploading one file:** delete it on the VPS
  (`rm ~/phu/shellx/downloads/desktop/X.Y.Z/<file>`), then **Re-run failed jobs**.""",
    ),
]
for old, new in EDITS:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one occurrence, found {count}: {old[:70]!r}")
    text = text.replace(old, new)
path.write_text(text, encoding="utf-8")
print(f"release/README.md: {len(EDITS)} edits applied")
```

- [ ] **Step 4: Run the check**

Run: `bash /tmp/check-workflows.sh`
Expected: `yaml OK`, then `workflows OK`.

If `actionlint` is on your `PATH`, also run `actionlint .github/workflows/deploy.yml .github/workflows/release-desktop.yml` (expect no findings; very old actionlint builds wrongly flag the `vars` context). The release script tests are unaffected: `node --test release/tests/*.test.mjs` still passes (the macOS-only ones skip elsewhere).

- [ ] **Step 5: Commit**

```bash
git add -A .github release/README.md
git commit -m "ci: replace CI and the R2 upload with CD to the VPS (deploy.yml, rsync installers)"
```

### Task 9: Docs — v1 spec amendments, privacy and terms with `[quốc gia]`, web README, HANDOFF

The legal pages stop naming Cloudflare and name the hosting country as the placeholder `[quốc gia]` (vi and en), which the Task 6 guard refuses to build: the public site cannot be deployed until the user fills it in (spec §9, §12 item 1). Deleted data now survives only in the 14 daily backups. The v1 spec is amended wherever it names a Cloudflare product, pointing to the VPS spec.

Interpretation used: the VPS spec's "§3 sơ đồ" is the architecture diagram, which is in §4 of the v1 spec; its list (D7, D8, diagram, components table, §10, §11, §13, §15) is extended to every v1 section that still describes Cloudflare or CI (header, §1, §4.2, §4.3, §5.2, §6.1, §6.2, §14), otherwise the v1 spec would contradict the VPS spec.

**Files:**
- Modify: `docs/superpowers/specs/2026-09-25-shellx-v1-design.md`, `web/src/pages/privacy.md`, `web/src/pages/en/privacy.md`, `web/src/pages/terms.md`, `web/src/pages/en/terms.md`, `web/README.md`, `web/astro.config.mjs`, `web/src/pages/404.astro`, `web/src/lib/site.ts`, `web/tests/site.test.mjs`, `docs/superpowers/HANDOFF.md`

**Interfaces:**
- Consumes: the guard `web/scripts/check-placeholders.mjs` and the web `build`/`test` scripts (Task 6); `deploy/README.md` (Task 7); the workflows (Task 8); the relay test count printed by Task 5.
- Produces: the literal placeholder `[quốc gia]` in exactly four files (`web/src/pages/privacy.md`, `web/src/pages/en/privacy.md`, `web/src/pages/terms.md`, `web/src/pages/en/terms.md`); `npm run build` in `web/` fails until it is replaced.

- [ ] **Step 1: Write the failing check**

From the repository root:

```bash
cat > /tmp/check-docs.sh <<'CHECK'
set -e
if grep -rn -i -E "cloudflare|pages\.dev|\bR2\b" web/src web/astro.config.mjs web/tests web/README.md; then
  echo "Cloudflare still mentioned in web/ (lines above)"; exit 1
fi
if grep -n -i -E "wrangler|durable object|workers paid|cloudflare pages" docs/superpowers/specs/2026-09-25-shellx-v1-design.md; then
  echo "Cloudflare still described in the v1 spec (lines above)"; exit 1
fi
grep -q "2026-09-26-shellx-vps-infra-design.md" docs/superpowers/specs/2026-09-25-shellx-v1-design.md
test "$(grep -l '\[quốc gia\]' web/src/pages/privacy.md web/src/pages/en/privacy.md web/src/pages/terms.md web/src/pages/en/terms.md | wc -l | tr -d ' ')" = 4
grep -q "phu/shellx" docs/superpowers/HANDOFF.md
echo "docs OK"
CHECK
bash /tmp/check-docs.sh
```

- [ ] **Step 2: Run it to verify it fails**

Expected: FAIL — the Cloudflare lines of `web/src/pages/privacy.md`, `web/src/pages/terms.md`, their English versions, `web/astro.config.mjs`, `web/src/pages/404.astro`, `web/src/lib/site.ts`, `web/tests/site.test.mjs` and `web/README.md` are listed, then `Cloudflare still mentioned in web/ (lines above)`.

- [ ] **Step 3: Legal pages and web sources**

Save as `/tmp/edit-web-docs.py` and run `python3 /tmp/edit-web-docs.py` from the repository root (it stops before writing a file whose expected text is not found exactly once):

```python
# Task 9: legal pages (vi + en) get the "[quốc gia]" placeholder instead of Cloudflare, and the web
# sources stop mentioning Cloudflare Pages/R2. Run from the repository root. Every replaced block
# must occur exactly once per file, otherwise the script stops before writing that file.
from pathlib import Path

FILES = {
    "web/src/pages/privacy.md": [
        ('updated: "2026-09-25"', 'updated: "2026-09-27"'),
        (
            "Dịch vụ chạy trên hạ tầng của Cloudflare, Inc. (Workers, Durable Objects, D1, R2, Pages). Dữ liệu có thể được xử lý tại các trung tâm dữ liệu của Cloudflare bên ngoài Việt Nam. Cloudflare xử lý dữ liệu thay mặt chúng tôi và cũng xử lý địa chỉ IP cùng thông tin kỹ thuật của kết nối để vận chuyển dữ liệu và chống tấn công, theo chính sách của Cloudflare.",
            "Dịch vụ chạy trên máy chủ riêng do ShellX thuê tại **[quốc gia]**: máy chủ chuyển tiếp, cơ sở dữ liệu tài khoản cùng các bản sao lưu, trang web và bản cài đặt. Dữ liệu được lưu và xử lý tại **[quốc gia]**. Chúng tôi không dùng mạng phân phối nội dung (CDN) hay dịch vụ phân tích của bên thứ ba.",
        ),
        (
            "- **Nhật ký vận hành:** không quá 30 ngày.\n",
            "- **Nhật ký vận hành:** không quá 30 ngày.\n- **Bản sao lưu cơ sở dữ liệu:** mỗi ngày một bản, giữ 14 bản gần nhất.\n",
        ),
        (
            "Dữ liệu đã xóa cũng có thể còn tồn tại tối đa 30 ngày trong bản sao lưu khôi phục theo thời điểm (point-in-time recovery) của nhà cung cấp cơ sở dữ liệu trước khi tự hết hạn.",
            "Dữ liệu đã xóa cũng có thể còn trong các bản sao lưu hằng ngày của cơ sở dữ liệu tối đa 14 ngày, rồi bị xóa cùng bản sao lưu đó.",
        ),
    ],
    "web/src/pages/en/privacy.md": [
        ('updated: "2026-09-25"', 'updated: "2026-09-27"'),
        (
            "The Service runs on Cloudflare, Inc. infrastructure (Workers, Durable Objects, D1, R2, Pages). Data may be processed in Cloudflare data centers outside Vietnam. Cloudflare processes data on our behalf, and also processes IP addresses and connection metadata to deliver traffic and block attacks, under Cloudflare's own policies.",
            "The Service runs on a private server rented by ShellX in **[quốc gia]**: the relay server, the account database and its backups, the website and the installers. Data is stored and processed in **[quốc gia]**. We use no content delivery network (CDN) and no third-party analytics.",
        ),
        (
            "- **Operational logs:** no longer than 30 days.\n",
            "- **Operational logs:** no longer than 30 days.\n- **Database backups:** one per day; the 14 most recent are kept.\n",
        ),
        (
            "Deleted data may also remain for up to 30 days in the database provider's point-in-time recovery backups before it expires.",
            "Deleted data may also remain in the daily database backups for up to 14 days, and is removed together with those backups.",
        ),
    ],
    "web/src/pages/terms.md": [
        ('updated: "2026-09-25"', 'updated: "2026-09-27"'),
        ("Dịch vụ chạy trên hạ tầng của Cloudflare.", "Dịch vụ chạy trên máy chủ riêng do ShellX thuê tại **[quốc gia]**."),
    ],
    "web/src/pages/en/terms.md": [
        ('updated: "2026-09-25"', 'updated: "2026-09-27"'),
        ("The Service runs on Cloudflare infrastructure.", "The Service runs on a private server rented by ShellX in **[quốc gia]**."),
    ],
    "web/astro.config.mjs": [
        (
            """// Static site for Cloudflare Pages. Every page is emitted as <path>/index.html, so internal
// links use a trailing slash (/privacy/, /en/terms/); Pages redirects /privacy to /privacy/.""",
            """// Static site served by nginx in the `web` container (deploy/web/nginx.conf). Every page is emitted
// as <path>/index.html, so internal links use a trailing slash (/privacy/, /en/terms/); nginx
// redirects /privacy to /privacy/.""",
        ),
    ],
    "web/src/pages/404.astro": [
        (
            """// Cloudflare Pages serves dist/404.html for unknown paths. Without it, Pages would treat the
// site as a single-page app and answer every unknown path with the home page and HTTP 200.""",
            """// nginx serves dist/404.html with status 404 for unknown paths (deploy/web/nginx.conf).""",
        ),
    ],
    "web/src/lib/site.ts": [
        (
            "// Installer file names must match what release/ uploads to R2:",
            "// Installer file names must match what release-desktop.yml uploads to download.shellx.pro:",
        ),
    ],
    "web/tests/site.test.mjs": [
        (
            "test('404 page exists so Cloudflare Pages does not fall back to SPA mode', () => {",
            "test('404 page exists (nginx answers unknown paths with it and status 404)', () => {",
        ),
    ],
}
for name, edits in FILES.items():
    path = Path(name)
    text = path.read_text(encoding="utf-8")
    for old, new in edits:
        count = text.count(old)
        if count != 1:
            raise SystemExit(f"{name}: expected exactly one occurrence, found {count}: {old[:70]!r}")
        text = text.replace(old, new)
    path.write_text(text, encoding="utf-8")
    print(f"{name}: {len(edits)} edits applied")
```

Replace `web/README.md`:

````markdown
# shellx.pro website

Static [Astro](https://astro.build) site for `https://shellx.pro` (spec §11): a minimal home page with
download links, the privacy policy and the terms of use, in Vietnamese (default, at `/`) and English
(under `/en/`). Marketing content and design are out of scope for v1.0.

| Path | Page |
|---|---|
| `/` · `/en/` | Home page with download links |
| `/privacy/` · `/en/privacy/` | Privacy policy (`#delete-account` explains account deletion) |
| `/terms/` · `/en/terms/` | Terms of use |
| any other path | `404.html` |

## Commands (Node 22.12 or later)

| Command | What it does |
|---|---|
| `npm ci` | Install the locked dependencies |
| `npm run dev` | Dev server at http://localhost:4321 |
| `npm run build` | Refuse the `[quốc gia]` placeholder, `astro build` into `dist/`, then check pages and links (`tests/`) |
| `npm test` | Re-run the checks against an existing `dist/` |
| `CHECK_DOWNLOADS=1 npm test` | Also sends HEAD requests to the installer URLs (needs network) |

## Links and version

`src/site.config.json` is the only file to edit for links:

- `desktopVersion` — the desktop version the home page links to:
  `https://download.shellx.pro/desktop/<v>/ShellX-<v>.dmg` and
  `https://download.shellx.pro/desktop/<v>/ShellX-Setup-<v>.exe`.
  Bump it only after `release-desktop.yml` has published that version (see `release/README.md`),
  and run `CHECK_DOWNLOADS=1 npm run build` before merging.
- `appStoreUrl`, `googlePlayUrl` — `null` shows "Sắp ra mắt" / "Coming soon". Once the listings
  are live, set `googlePlayUrl` to `https://play.google.com/store/apps/details?id=pro.shellx.mobile`
  and `appStoreUrl` to the App Store listing URL (`https://apps.apple.com/app/id` followed by the
  numeric Apple ID that App Store Connect assigns to `pro.shellx.mobile`).
- `supportEmail` — shown in the footer. The legal pages name `support@shellx.pro` in their text.

Legal text lives in `src/pages/privacy.md`, `src/pages/terms.md` and the English versions in
`src/pages/en/`. Change both languages together and update `updated:` in the front matter. The
privacy policy promises no analytics, cookies or third-party scripts; the build checks fail if a
page loads an external script, stylesheet or iframe.

## Deployment

The site runs on the VPS as the `web` container (nginx:alpine with `dist/` and
`deploy/web/nginx.conf`), built by `web/Dockerfile` and deployed by `.github/workflows/deploy.yml`
on every push to `main` that changes `web/`, `relay/` or `deploy/`. See `deploy/README.md`.

- `npm run build` first runs `scripts/check-placeholders.mjs`, which refuses to build while any page
  still contains `[quốc gia]`: the privacy policy and terms must name the country where the VPS is
  hosted before the site is public (VPS spec §9). Replace every occurrence (vi and en), update
  `updated:` in their front matter, and commit.
- nginx answers `/privacy` with `301 /privacy/`, unknown paths with `dist/404.html` and status 404,
  `www.shellx.pro` with `301 https://shellx.pro…`, and serves `download.shellx.pro` from the VPS
  folder `downloads/` (files only, always as downloads). It writes no access log.
- Build the image locally from the repository root: `docker build -f web/Dockerfile -t shellx-web .`

## Verify production

```bash
curl -sIL https://shellx.pro/privacy | grep -iE '^(HTTP|location)'
# Expected: a redirect to /privacy/, then a final "HTTP/2 200"
curl -s -o /dev/null -w '%{http_code}\n' https://shellx.pro/en/terms/
# Expected: 200
curl -s -o /dev/null -w '%{http_code}\n' https://shellx.pro/no-such-page
# Expected: 404 (dist/404.html)
curl -sI https://www.shellx.pro/terms/ | grep -i '^location'
# Expected: location: https://shellx.pro/terms/
```

## URLs for the store listings

- Privacy policy URL (App Store Connect, Google Play Console): `https://shellx.pro/privacy`
  (spec §14; redirects to `/privacy/`). English: `https://shellx.pro/en/privacy/`.
- Google Play "Delete account" URL: `https://shellx.pro/en/privacy/#delete-account`.
````

- [ ] **Step 4: Check the website still builds its pages — and that the guard now refuses the public build**

From `web/`:

```bash
npm run build; echo "exit=$?"
npx astro build > /dev/null && node --test tests/site.test.mjs tests/placeholders.test.mjs
```

Expected: `npm run build` prints `Refusing to build: replace the [quốc gia] placeholder (the country where the VPS is hosted) in:` followed by `src/pages/en/privacy.md:68`, `src/pages/en/terms.md:64`, `src/pages/privacy.md:68`, `src/pages/terms.md:64`, then `exit=1`. The second command ends with `ℹ pass 19`, `ℹ skipped 1`, `ℹ fail 0` (the privacy pages still mention argon2id, SHA-256, X25519, 90, 256 KiB and Noise).

- [ ] **Step 5: Amend the v1 spec**

Save as `/tmp/edit-v1-spec.py` and run it from the repository root:

```python
# Task 9: amends the Cloudflare parts of the v1 spec to point at the VPS design. Run from the
# repository root. Every replaced block must occur exactly once, otherwise nothing is written.
from pathlib import Path

path = Path("docs/superpowers/specs/2026-09-25-shellx-v1-design.md")
text = path.read_text(encoding="utf-8")
EDITS = []


def rep(old, new):
    EDITS.append((old, new))


rep("""- **Trạng thái:** Đã chốt qua brainstorming; chuyển sang lập kế hoạch triển khai
- **Phạm vi:** Desktop agent (macOS/Windows), mobile app (iOS/Android), relay trên Cloudflare, vị trí landing page trong kiến trúc""",
"""- **Trạng thái:** Đã chốt qua brainstorming; chuyển sang lập kế hoạch triển khai
- **Phạm vi:** Desktop agent (macOS/Windows), mobile app (iOS/Android), relay trên VPS riêng, vị trí landing page trong kiến trúc
- **Sửa đổi 2026-09-26/27:** hạ tầng chuyển từ Cloudflare sang VPS riêng theo `2026-09-26-shellx-vps-infra-design.md`. Các mục D7, D8, §1, §4, §5.2, §6.1, §6.2, §10, §11, §13, §14 và §15 đã được sửa theo tài liệu đó; khi hai tài liệu khác nhau về hạ tầng, tài liệu VPS là chuẩn.""")
rep("""thông qua một relay trên Cloudflare, với kênh mã hóa đầu cuối mà relay không đọc được.""",
"""thông qua một relay chạy trên VPS riêng, với kênh mã hóa đầu cuối mà relay không đọc được.""")
rep("""| D7 | Hạ tầng | Cloudflare (Workers, Durable Objects, D1, R2, Pages) thay cho VPS. Tên miền `shellx.pro` |
| D8 | Landing page | Astro, triển khai trên Cloudflare Pages. Nội dung marketing làm ở spec riêng |""",
"""| D7 | Hạ tầng | VPS riêng của người dùng (Docker sau `nginx-proxy` + letsencrypt-companion): relay Node.js + SQLite, trang web và nơi tải bản cài, tất cả trong thư mục `~/phu/shellx`. Tên miền `shellx.pro`. Sửa 2026-09-26 (trước đây: Cloudflare), xem `2026-09-26-shellx-vps-infra-design.md` |
| D8 | Landing page | Astro, xuất trang tĩnh, phục vụ bằng nginx trong container `web` trên VPS. Nội dung marketing làm ở spec riêng |""")
rep("""                         ┌──────────────────────────────────────────────┐
                         │  Cloudflare                                  │
                         │  shellx.pro           → Landing page (Astro) │
                         │  download.shellx.pro  → R2: bản cài desktop  │
                         │  relay.shellx.pro     → Worker + Durable     │
                         │                         Object + D1          │
                         └───────▲──────────────────────────▲───────────┘""",
"""                         ┌──────────────────────────────────────────────┐
                         │  VPS (nginx-proxy, HTTPS Let's Encrypt)      │
                         │  shellx.pro           → web: Astro (nginx)   │
                         │  download.shellx.pro  → web: bản cài desktop │
                         │  relay.shellx.pro     → relay: Node.js, hub  │
                         │                         trong tiến trình,    │
                         │                         SQLite               │
                         └───────▲──────────────────────────▲───────────┘""")
rep("""- Worker xác thực token rồi chuyển WebSocket vào **Durable Object `UserHub` của tài khoản** (mỗi tài khoản đúng một hub, `idFromName(user_id)`). Vì mọi thiết bị của một tài khoản nối vào cùng một hub, việc "chỉ chuyển gói tin trong cùng tài khoản" được đảm bảo bởi cấu trúc.""",
"""- Relay xác thực token rồi chuyển WebSocket vào **`UserHub` của tài khoản** trong tiến trình relay (mỗi tài khoản đúng một hub, `registry.forUser(user_id)`). Vì mọi thiết bị của một tài khoản nối vào cùng một hub, việc "chỉ chuyển gói tin trong cùng tài khoản" được đảm bảo bởi cấu trúc.""")
rep("""| **Relay** (`relay/`, TypeScript) | Đăng ký/đăng nhập, lưu thiết bị và ghép nối trong D1, theo dõi online/offline, chuyển tiếp khung giữa các thiết bị cùng tài khoản |""",
"""| **Relay** (`relay/`, TypeScript, Node.js) | Đăng ký/đăng nhập, lưu thiết bị và ghép nối trong SQLite, theo dõi online/offline, chuyển tiếp khung giữa các thiết bị cùng tài khoản |""")
rep("""| `shellx.pro` | Landing page (Cloudflare Pages) |
| `relay.shellx.pro` | Worker production |
| `relay-staging.shellx.pro` | Worker staging |
| `download.shellx.pro` | R2 bucket công khai chứa bản cài desktop |""",
"""| `shellx.pro` | Landing page (container `web` trên VPS); `www.shellx.pro` chuyển về đây |
| `relay.shellx.pro` | Relay (container `relay` trên VPS). Không có môi trường staging |
| `download.shellx.pro` | Bản cài desktop (container `web`, thư mục `downloads/` trên VPS) |""")
rep("""  relay/                     # Worker (Hono) + Durable Object UserHub + D1 migrations (wrangler)
  web/                       # Astro""",
"""  relay/                     # Node.js (Hono) + UserHub trong tiến trình + SQLite migrations
  web/                       # Astro
  deploy/                    # docker-compose, cấu hình nginx, sao lưu, runbook VPS""")
rep("""danh sách được đóng gói vào Worker lúc build bằng script.""","""danh sách được đóng gói vào relay lúc build bằng script.""")
rep("""D1 chỉ lưu SHA-256 của token.""","""Cơ sở dữ liệu chỉ lưu SHA-256 của token.""")
rep("""- **Giới hạn tần suất** (rate limiting binding của Workers, chu kỳ 60 giây): đăng nhập 10 lần/IP và 5 lần/email; đăng ký 3 lần/IP. Vượt giới hạn trả HTTP 429.""",
"""- **Giới hạn tần suất** (bộ giới hạn cửa sổ trượt trong bộ nhớ của relay, cửa sổ 60 giây; IP lấy từ `X-Real-IP` của nginx-proxy): đăng nhập 10 lần/IP và 5 lần/email; đăng ký 3 lần/IP. Vượt giới hạn trả HTTP 429.""")
rep("""xóa các bản ghi ghép nối của agent trong D1,""","""xóa các bản ghi ghép nối của agent trong cơ sở dữ liệu,""")
rep("""- **Hỗ trợ khẩn cấp:** script quản trị `relay/scripts/reset-password.ts` chạy qua `wrangler d1` để đặt lại mật khẩu thủ công.""",
"""- **Hỗ trợ khẩn cấp:** script quản trị `relay/src/scripts/reset-password.ts` đặt lại mật khẩu thủ công, chạy trong container: `docker compose exec relay node dist/scripts/reset-password.js`.""")
rep("""- **Khung văn bản** chỉ dùng cho nhịp tim: client gửi `ping` mỗi 30 giây, hub trả `pong` bằng `setWebSocketAutoResponse` (không đánh thức Durable Object). Không nhận `pong` trong 10 giây thì client coi như mất kết nối.""",
"""- **Khung văn bản** chỉ dùng cho nhịp tim: client gửi `ping` mỗi 30 giây, relay trả `pong` ngay trong handler nhận tin, không qua hàng đợi của hub. Không nhận `pong` trong 10 giây thì client coi như mất kết nối.""")
rep("""Khi ngắt, hub báo offline và ghi `last_seen_at` vào D1.""","""Khi ngắt, hub báo offline và ghi `last_seen_at` vào cơ sở dữ liệu.""")
rep("""TypeScript, Hono, wrangler, D1, Durable Object dùng SQLite storage và WebSocket Hibernation API, rate limiting binding. argon2id chạy bằng module WASM **import tĩnh** (Workers không cho biên dịch WASM động lúc chạy). Cần gói Workers Paid.""",
"""Node.js 22 + TypeScript, Hono trên `@hono/node-server`, WebSocket bằng `ws`, SQLite bằng `better-sqlite3` (WAL), argon2id bằng `@node-rs/argon2` (tối đa 4 lần băm cùng lúc), bộ giới hạn tần suất trong bộ nhớ. Một tiến trình, một container `relay` trên VPS (chi tiết: `2026-09-26-shellx-vps-infra-design.md` §4).""")
rep("""| `GET /v1/ws` | token | — | `101` → chuyển vào `UserHub` |""","""| `GET /v1/ws` | token | — | `101` → chuyển vào `UserHub` của tài khoản |""")
rep("""### 10.3 D1
""","""### 10.3 Cơ sở dữ liệu (SQLite)

`relay/migrations/0001_init.sql` (bên dưới) và `0002_hub_state.sql` (bảng bia mộ `pending_pairing_removed` của hub, có thêm `user_id`). Relay tự chạy migration khi khởi động, ghi vào `schema_migrations`.
""")
rep("""### 10.4 Durable Object `UserHub`

- Nhận WebSocket từ Worker kèm `device_id` và `kind` đã xác thực; `ctx.acceptWebSocket(ws)` và lưu `{device_id, kind}` bằng `serializeAttachment`.""",
"""### 10.4 `UserHub` trong tiến trình

- `HubRegistry` giữ tối đa một hub cho mỗi tài khoản, tạo khi cần và bỏ khi không còn socket. Mọi thao tác của hub (socket vào/ra, khung đến, lời gọi từ route REST) đi qua một hàng đợi tuần tự.
- Nhận WebSocket từ route `/v1/ws` kèm `device_id` và `kind` đã xác thực, lưu `{device_id, kind, conn_id, closing}` cho socket đó.""")
rep("""- Phương thức RPC cho Worker: `online(): string[]`,""","""- Phương thức cho các route REST (`registry.forUser(userId).<method>()`): `online(): string[]`,""")
rep("""- Hai môi trường `staging` và `production` trong `relay/wrangler.jsonc`; migration bằng `wrangler d1 migrations`.""",
"""- Một môi trường production trên VPS, triển khai bằng `.github/workflows/deploy.yml` khi push `main`; runbook ở `deploy/README.md`. Sao lưu SQLite hằng ngày, giữ 14 bản.""")
rep("""- Astro, xuất trang tĩnh, triển khai trên Cloudflare Pages tại `shellx.pro`.""","""- Astro, xuất trang tĩnh, phục vụ bằng nginx trong container `web` trên VPS tại `shellx.pro` (triển khai bằng `deploy.yml`).""")
rep("""- **Relay:** Vitest với `@cloudflare/vitest-pool-workers` (workerd thật, có D1 và Durable Object): đăng ký/đăng nhập,""",
"""- **Relay:** Vitest trên Node (mỗi test một cơ sở dữ liệu SQLite tạm, server thật trên cổng ngẫu nhiên, client `ws` thật; chạy cả trong bước build image): đăng ký/đăng nhập,""")
rep("""chạy với relay cục bộ `wrangler dev`:""","""chạy với relay cục bộ `npm run dev` (Node.js, `127.0.0.1:8787`):""")
rep("""- **CI (GitHub Actions):** test Dart packages, test relay, test tích hợp desktop trên `macos-latest` và `windows-latest`, test widget mobile, test end-to-end.""",
"""- **Không có CI** (quyết định V5 ngày 2026-09-26): test Dart, desktop, mobile và end-to-end chạy ở máy dev trước khi push. GitHub Actions chỉ còn CD: `deploy.yml` (push `main`: build image, chạy test relay, deploy lên VPS) và `release-desktop.yml` (tag `desktop-v*`).""")
rep("""- Bản cài desktop tải lên R2 theo đường dẫn `desktop/<version>/…`, phục vụ qua `download.shellx.pro`.""",
"""- Bản cài desktop được `rsync` lên VPS vào `downloads/desktop/<version>/…`, phục vụ qua `download.shellx.pro`.""")
rep("""| R1 | argon2id trên Workers: module WASM phải import tĩnh và vừa giới hạn CPU/bộ nhớ | Làm spike đầu tiên khi dựng relay; đo thời gian băm với tham số ở mục 5.2 |
| R2 | Chi phí Cloudflare tính theo số tin nhắn WebSocket vào Durable Object | Kiểm bảng giá hiện hành và ước tính chi phí mỗi người dùng trước khi mở đăng ký công khai; thiết kế đã gom tin 16 ms và giới hạn cửa sổ gửi |""",
"""| R1, R2 | (Đã thay) Rủi ro của Cloudflare Workers | Thay bằng R-VPS1…R-VPS6 trong `2026-09-26-shellx-vps-infra-design.md` §10: một VPS là điểm lỗi duy nhất, không có lớp chống DDoS, không có CI, RAM của argon2, deploy làm rớt WebSocket, chứng chỉ khi DNS chưa đồng bộ |""")

for old, new in EDITS:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one occurrence, found {count}: {old[:70]!r}")
    text = text.replace(old, new)
path.write_text(text, encoding="utf-8")
print(f"v1 spec: {len(EDITS)} edits applied")
```

- [ ] **Step 6: Update the handoff**

Save as `/tmp/edit-handoff.py` and run it from the repository root. If Task 5 printed a relay test count other than 263, change `263 test` in the script to that number before running it:

```python
# Task 9: updates docs/superpowers/HANDOFF.md for the VPS move. Run from the repository root.
# Every replaced block must occur exactly once, otherwise nothing is written.
from pathlib import Path

path = Path("docs/superpowers/HANDOFF.md")
s = path.read_text(encoding="utf-8")
E=[
("# ShellX v1.0 — Bàn giao để tiếp tục (cập nhật 2026-09-26: cả 6 plan đã merge)",
 "# ShellX v1.0 — Bàn giao để tiếp tục (cập nhật 2026-09-27: 6 plan đã merge; hạ tầng đã chuyển sang VPS trong code, chưa deploy)"),
("- Sản phẩm: điều khiển terminal máy tính (macOS/Windows) từ điện thoại, qua relay Cloudflare, mã hóa đầu cuối Noise.",
 "- Sản phẩm: điều khiển terminal máy tính (macOS/Windows) từ điện thoại, qua relay chạy trên VPS riêng (Node.js + SQLite trong Docker), mã hóa đầu cuối Noise.\n- Hạ tầng: `docs/superpowers/specs/2026-09-26-shellx-vps-infra-design.md` (thay các phần Cloudflare của spec v1); plan `docs/superpowers/plans/2026-09-26-shellx-vps-infra.md`; runbook `deploy/README.md`."),
("| 05 | Mobile (Flutter) | đã merge (0e9ca47), worktree đã xóa | ✅ Xong (mobile 501 test; build debug APK + iOS đã chạy). App id `com.shellx.prod`, logo mới. Ledger: `docs/superpowers/ledgers/plan05-mobile.md` |",
 "| 05 | Mobile (Flutter) | đã merge (0e9ca47), worktree đã xóa | ✅ Xong (mobile 501 test; build debug APK + iOS đã chạy). App id `com.shellx.prod`, logo mới. Ledger: `docs/superpowers/ledgers/plan05-mobile.md` |\n| VPS | Chuyển hạ tầng Cloudflare → VPS | `docs/superpowers/plans/2026-09-26-shellx-vps-infra.md` | ✅ Code xong: relay chạy Node.js (263 test, cũng chạy trong bước build image), e2e 7/7 với `npm run dev`; `deploy/`, `deploy.yml`, image relay/web. **Chưa deploy** (xem mục 4) |"),
("1. **Push + PR vào `main`** để CI chạy trên Windows (desktop Windows chưa kiểm chứng; checklist trong `ledgers/plan04-desktop.md`), rồi bật check \"CI result\" bắt buộc.\n2. **Triển khai Cloudflare** (mục 4).",
 "1. **Không còn CI** (quyết định V5): desktop Windows chưa kiểm chứng — chạy test trên một máy Windows thật (checklist trong `ledgers/plan04-desktop.md`) trước khi phát hành.\n2. **Dựng VPS và deploy lần đầu** theo `deploy/README.md` (mục 4). Push `main` là deploy."),
("- **Cloudflare**: mua `shellx.pro` (DNS trên Cloudflare), gói Workers Paid; khi relay xong sẽ nhờ chạy `! npx wrangler login` (OAuth, không gửi key qua chat). Mọi thao tác tạo tài nguyên/deploy phải hỏi trước.\n- **GitHub Environment `release`** (tag `desktop-v*` + nhánh `main`) với 13 secret — xem `release/README.md`.",
 "- **VPS** (runbook `deploy/README.md`): quốc gia đặt VPS — thay mọi `[quốc gia]` trong `web/src/pages/{privacy,terms}.md` và `web/src/pages/en/{privacy,terms}.md` (bước build web từ chối build tới khi điền); user deploy trong nhóm `docker`, `~/phu/shellx/data` thuộc uid 1000; tên network của nginx-proxy vào `~/phu/shellx/.env`; 4 repository secret `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY`, `VPS_KNOWN_HOSTS` và biến `VPS_APP_DIR` (mặc định `phu/shellx`); sau lần deploy đầu: công khai 2 package GHCR `shellx-relay`, `shellx-web` và symlink 4 file `~/phu/shellx/nginx-proxy/*` vào `vhost.d` của nginx-proxy. Mọi lệnh trên VPS do người dùng chạy hoặc cho phép rõ ràng.\n- **Dọn Cloudflare** (khi nameserver đã về nhà đăng ký): xóa zone `shellx.pro` trên Cloudflare, `npx wrangler logout`, xóa secret `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`.\n- **GitHub Environment `release`** (tag `desktop-v*` + nhánh `main`) với 11 secret ký — xem `release/README.md`."),
("- Không push, không deploy, không tạo tài nguyên Cloudflare khi chưa hỏi.",
 "- Không push, không deploy, không chạy lệnh trên VPS khi chưa hỏi."),
]
for old, new in E:
    count = s.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one occurrence, found {count}: {old[:70]!r}")
    s = s.replace(old, new)
s=s.rstrip()+"""

## 8. Hạ tầng VPS (quyết định 2026-09-26/27)

- V1–V7 (2026-09-26): bỏ Cloudflare; relay, trang web và nơi tải bản cài chạy trên VPS của người dùng (Ubuntu, Docker, `jwilder/nginx-proxy` + letsencrypt-companion); relay chuyển sang Node.js giữ nguyên giao thức; không CI, chỉ CD (`deploy.yml` khi push `main`, `release-desktop.yml` khi tag `desktop-v*`); build image relay chạy toàn bộ test relay.
- V8 (2026-09-27): mọi thứ của ShellX trên VPS nằm trong **một thư mục `~/phu/shellx`** (biến GitHub `VPS_APP_DIR`), kể cả database (`./data`, bind mount). Ngoại lệ duy nhất: các file vhost của nginx-proxy trong `vhost.d` (bản gốc ở `~/phu/shellx/nginx-proxy/`).
- Việc còn mở: quốc gia đặt VPS (điền `[quốc gia]`), tên network của nginx-proxy.
"""
path.write_text(s, encoding="utf-8")
print(f"HANDOFF.md: {len(E)} edits applied, section 8 appended")
```

- [ ] **Step 7: Run the check**

Run: `bash /tmp/check-docs.sh`
Expected: `docs OK`.

- [ ] **Step 8: Commit**

```bash
git add docs/superpowers/specs/2026-09-25-shellx-v1-design.md docs/superpowers/HANDOFF.md web
git commit -m "docs: VPS hosting in the v1 spec, privacy/terms with the [quốc gia] placeholder, web README and handoff"
```

---

## Spec coverage (self-review)

| Spec section | Where |
|---|---|
| §1 V1–V7 (drop Cloudflare, VPS with nginx-proxy + companion, DNS, Node relay keeping Hono, CD only, tests in the image build, D1 deleted) | Tasks 1–8; V7 already done |
| §1 V8 (2026-09-27: one folder `phu/shellx`, `VPS_APP_DIR`, `./data` bind mount, vhost.d exception) | Global Constraints; Task 7 (compose, rollout.sh, runbook); Task 8 (`APP_DIR` in both workflows) |
| §2 goals (three HTTPS names, protocol unchanged, push = deploy with health check and rollback) | Tasks 4–5 (protocol tests, e2e 7/7), Task 6 (nginx hosts), Task 7 (rollout.sh), Task 8 (deploy.yml) |
| §3 layout, services, nginx server blocks, vhost.d | Task 6 (`nginx.conf`), Task 7 (compose, backup, `deploy/nginx-proxy/`, runbook) |
| §4.1 modules kept | Tasks 2–4 (only D1/hub calls change; `token-bucket.ts`, `protocol/`, `http/`, `log.ts` behaviour unchanged) |
| §4.2 Worker runtime → `@hono/node-server` + `ws` | Task 1 (`startRelay`), Task 4 (upgrade), Task 5 (`server.ts`) |
| §4.2 D1 → `better-sqlite3` `Db` (WAL, FK, busy_timeout, transactions) | Task 1 |
| §4.2 migrations + `schema_migrations`, `0001` verbatim, `0002_hub_state.sql` | Task 1 |
| §4.2 Durable Object → `HubRegistry`, tombstones in SQLite, auto-response ping, attachment metadata | Task 3; ping in Task 4 (`ws.ts`) |
| §4.2 rate limiting → `SlidingWindowLimiter`; argon2 → `@node-rs/argon2` with 4 at once; `config.ts`; `X-Real-IP` | Task 2 (limiter, argon2, client IP), Task 1 (config), Task 4 (wiring) |
| §4.3 serial queue, behaviours (4001, 4002, account deletion, presence, DATA, EVENT, 500/s), REST → `forUser().<method>()`, graceful shutdown | Task 3, Task 4, Task 5 (`shutdown`, `server.ts`) |
| §4.4 `reset-password` on SQLite in the container; `update-disposable-domains`/`blocklist` unchanged | Task 5 |
| §4.5 packages, `tsc` build, `npm run dev` on 127.0.0.1:8787, `wrangler.jsonc` deleted, README | Tasks 1, 2, 4, 5 |
| §4.6 relay Dockerfile stages; web Dockerfile | Task 6 |
| §5 tests on Node with temp DB, real server, real `ws`; new tests (migrations once, tombstones after restart, 1001 on shutdown, `X-Real-IP`, 5th hash queues, missing env exits); e2e 7/7; post-deploy curls | Task 1 (`db.test`), Task 3/5 (restart), Task 5 (`server.test`), Task 2 (`limiter.test`, `password.test`), Task 1 (`config.test`) + Task 5 (exit), Task 5 Step 7, Task 8 |
| §6.1 `deploy.yml` (paths, concurrency, GHCR, SSH strict, rsync, rollout, 60 s, rollback, curl retries 10 × 15 s, `workflow_dispatch` `ref`, public images) | Task 8 (+ Task 7 `rollout.sh`, runbook for making the packages public) |
| §6.2 `release-desktop.yml` rsync + size check, Cloudflare secrets dropped | Task 8 |
| §6.3 secrets and `VPS_APP_DIR` | Task 8, runbook in Task 7 |
| §7 first-time setup runbook | Task 7 (`deploy/README.md`) |
| §8 operations (logs 10m × 3, backups, restore, rollback, relay.env) | Task 7 (compose, backup scripts, runbook) |
| §9 privacy/terms, `[quốc gia]` guard, v1 spec, HANDOFF, READMEs | Task 6 (guard), Task 9 (text), Task 5 (`relay/README.md`), Task 7 (`deploy/README.md`) |
| §10 risks R-VPS1…6 | Mitigations: backups (7), limits (2), tests in the image (6), 4-hash cap (2), reconnect behaviour unchanged (4–5), curl retries (8); recorded in the v1 spec (9) |
| §11 Cloudflare clean-up in the repo | Tasks 1, 2, 5 (dependencies, `wrangler.jsonc`), 8 (R2 step), 9 (Pages docs); user-side steps listed in HANDOFF (9) |
| §12 open items (country, proxy network) | `[quốc gia]` guard (6, 9); runbook step 2 (7) |

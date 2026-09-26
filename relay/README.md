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
- **Slow receivers:** before sending anything (DATA, ERROR, PRESENCE, EVENT, `pong`) the hub checks
  the socket's unsent backlog; over 4 MiB it sends nothing more and closes the socket with 1013
  "try again later" (logged as `slow_receiver`). Clients reconnect with backoff and catch up from
  the agent's replay buffer; frames are never skipped (that would break the Noise stream).
- **Rate limits:** in memory, 60-second sliding window: login 10/IP and 5/email, register 3/IP. The
  IP is `X-Real-IP` when the TCP peer is a private or loopback address (nginx-proxy), otherwise the
  peer address; an IPv6 address counts as its /64. IPs and e-mail addresses are never logged.
- **argon2id:** m = 19456 KiB, t = 2, p = 1; at most 4 hashes run at once and up to 32 wait; beyond
  that register, login and password change answer 429 `rate_limited`. The image sets
  `UV_THREADPOOL_SIZE=8` so the 4 hashes never take the whole libuv thread pool.
- **Refused upgrades:** a WebSocket upgrade with a bad token (401) or any other `Upgrade` (400) is
  answered and its socket destroyed after 5 s if the client does not close it; a client resetting
  the connection never affects the relay.
- **Limits:** JSON bodies over 16 KiB → 413 `payload_too_large`; a password over 128 code points is
  refused as `invalid_credentials` before hashing; WebSocket frames over 64 KiB → ERROR
  `frame_too_large`, messages over 1 MiB close the socket with 1009; 500 frames/s per device →
  ERROR `rate_limited`, close 4003.
- **Shutdown:** on SIGTERM/SIGINT the relay stops accepting connections, closes every socket with
  1001 "going away" (recording `last_seen_at` of those devices), waits at most 5 s for requests and
  hub queues, closes the database and exits 0 (1 if the shutdown failed; logged by kind). A second
  signal is ignored. Clients reconnect with their usual backoff.
- **Logs:** one JSON line per event with metadata only (time, `device_id`, error kind). Never
  payloads, tokens, passwords, e-mail or IP addresses.

## Healthcheck

Compose runs `node dist/scripts/healthcheck.js` in the container. It exits 0 and prints nothing
when `GET http://127.0.0.1:$PORT/v1/version` answers 200 within 3 s and the database at `$DB_PATH`
opens read-only (it is never created) and answers `SELECT 1`. Otherwise it prints one line such as
`healthcheck: version ECONNREFUSED; database SQLITE_CANTOPEN` (error kinds only) and exits 1.

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

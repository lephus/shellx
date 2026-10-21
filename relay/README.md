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
  cd packages/shellx_e2e && SHELLX_E2E_RELAY=http://127.0.0.1:8787 dart test
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
| `RATE_LIMITS_ENABLED` | on | Only the exact value `false` turns the login/register/upgrade/notification limits off |
| `FCM_SERVICE_ACCOUNT` | unset | Path of the Firebase service account JSON key (push notifications). Unset, unreadable or invalid → push is off, the relay runs normally, logs `push_disabled` with the reason once, and `POST /v1/notifications` answers 503 `push_unavailable` |
| `ADMIN_HOST` | `admin.shellx.pro` | Host name of the admin dashboard (see "Admin dashboard" below); a value that is not a bare host name stops the relay |
| `ADMIN_PASSWORD` | unset | The admin dashboard's password. Unset or shorter than 16 characters → admin is off (`admin_disabled` logged once with the reason, never the password) and the relay runs normally |
| `FCM_ENDPOINT`, `FCM_TOKEN_ENDPOINT` | Google | **Tests only:** base URL of the FCM API and the OAuth token URL, e.g. a fake FCM server. Honoured only for loopback `http(s)://127.0.0.1`/`localhost`/`[::1]` URLs, ignored otherwise |

On startup the relay applies every `migrations/*.sql` not yet listed in `schema_migrations`, in
file-name order, one transaction per file. There are no down-migrations: fix a mistake with a new
file. `0001_init.sql` is the original schema; `0002_hub_state.sql` holds the hub's
`pairing_removed` tombstones; `0003_push_tokens.sql` holds the phones' FCM tokens; `0004_admin.sql`
adds `devices.app_version` and the admin's `app_settings`.

## Behaviour worth knowing

- **Hub:** one `HubState` per account with a serial queue for everything that touches it (sockets
  joining/closing, frames, REST calls). Routes reach it with `registry.forUser(userId).<method>()`.
  Text `ping` is answered with `pong` immediately, outside the queue — but it counts against the
  device's 500 frames/s budget like any frame, and it goes unanswered once more than 64 KiB or more
  than 64 sends wait to go out to that socket (a slow but healthy link keeps its heartbeat; a client
  that stops reading cannot pile up pongs, and its own heartbeat times out). A skipped ping is
  dropped, not answered later. WebSocket control PING frames are never answered (`autoPong: false`):
  `ws` would answer them outside every bound; the heartbeat is the text `ping` only.
- **Slow receivers:** before sending anything (DATA, ERROR, PRESENCE, EVENT, `pong`) the hub checks
  the socket's backlog, in bytes and in sends (the ws route wraps each socket in `WsHubSocket`,
  which counts sends until `ws` reports their write done or failed). Over 4 MiB unsent, or over 1024
  sends queued, it sends nothing more and closes the socket with 1013 "try again later" (logged as
  `slow_receiver`). The count matters for tiny frames: each queued send pins ~400 B of heap that
  the byte count does not see, so a stuck socket fed tiny ERROR or DATA frames used to pin ~57 MB
  before reaching 4 MiB; it now pins about 1 MB. Clients reconnect with backoff and catch up from
  the agent's replay buffer; frames are never skipped (that would break the Noise stream). The one
  exception to the check is a newcomer's own connect snapshot (PRESENCE of the others, then an
  agent's `pairing_removed` tombstones): the socket is brand new, and an agent with over ~1000
  tombstones would otherwise be closed by its own replay on every connect.
- **Closing sockets:** every close the hub starts (1013, 4001 replaced, 4002 revoked, 4003 rate
  limited) is followed by an outright drop (the client sees 1006) if the close has not completed 1 s
  later: the close frame waits behind the socket's backlog, and a closing socket no longer counts as
  live. Any other close (1001 on shutdown, 1011, the 1013 of a refused device) is dropped by `ws`
  after 2 s (`closeTimeout`, instead of its default 30 s). When a device connects, any earlier socket
  of it that is still closing is dropped too, so a device reconnecting in a loop never piles up
  closing sockets.
- **Devices online per account:** at most 16 devices of one account are connected at once. A
  17th device is refused with 1013 "too many devices online" (logged as `account_device_cap` with its
  `device_id`) and retries with backoff; the 16 connected ones are untouched. A device that is
  already connected can always reconnect: its new socket replaces the old one.
- **Rate limits:** in memory, 60-second sliding window: login 10/IP and 5/email, register 3/IP,
  WebSocket upgrades 60/IP (every attempt, counted before its token is checked; over the limit the
  upgrade is refused with HTTP 429 and clients retry with backoff). The IP is `X-Real-IP` when the
  TCP peer is a private or loopback address (nginx-proxy), otherwise the peer address; an IPv6
  address counts as its /64. IPs and e-mail addresses are never logged.
- **argon2id:** m = 19456 KiB, t = 2, p = 1; at most 4 hashes run at once and up to 32 wait; beyond
  that register, login and password change answer 429 `rate_limited`. The image sets
  `UV_THREADPOOL_SIZE=8` so the 4 hashes never take the whole libuv thread pool.
- **Refused upgrades:** a WebSocket upgrade with a bad token (401), over the upgrade limit (429) or
  with any other `Upgrade` (400) is answered and its socket destroyed after 5 s if the client does
  not close it. A client that resets the connection (RST) at any point of an upgrade, even while its
  valid token is still being checked, does not crash the relay and leaves nothing pending behind
  (@hono/node-server's waiter for that socket is released too); the per-IP upgrade limit bounds how
  fast one address can repeat that.
- **Limits:** JSON bodies over 16 KiB → 413 `payload_too_large`; a password over 128 code points is
  refused as `invalid_credentials` before hashing; WebSocket frames over 64 KiB → ERROR
  `frame_too_large`, messages over 1 MiB close the socket with 1009; 500 frames/s per device (text
  `ping` included) → ERROR `rate_limited`, close 4003; per socket, 4 MiB unsent or 1024 queued
  sends → close 1013; 16 devices online per account → close 1013 for the next one. The container is
  capped at 512 MB, swap included (`mem_limit` and `memswap_limit` in `deploy/docker-compose.yml`):
  past it only the relay is killed,
  and `restart: unless-stopped` brings it back.
- **Shutdown:** on SIGTERM/SIGINT the relay stops accepting connections, closes every socket with
  1001 "going away" (recording `last_seen_at` of those devices), waits at most 5 s for requests and
  hub queues, closes the database and exits 0 (1 if the shutdown failed; logged by kind). A second
  signal is ignored. Clients reconnect with their usual backoff.
- **Logs:** one JSON line per event with metadata only (time, `device_id`, error kind). Never
  payloads, tokens, passwords, e-mail or IP addresses.

## API v2

Native desktop apps (`kind = "desktop"`, logged in through the v1 `/v1/auth` flow) use these routes
with the same bearer token. Every route needs a desktop token (an agent or phone token gets 403
`desktop_only`); bodies are JSON, errors are `{"error":{"code","message"}}`.

| Method + path | Body | Response |
|---|---|---|
| `POST /v2/machines` | `{name, platform: "macos"\|"windows", os_version, app_version, noise_public_key_b64}` | `201 {machine_id, slot}` (`200` with the same ids when the device is already registered) |
| `GET /v2/machines` | | `{machines: [{machine_id, name, platform, online, last_seen_unix, fingerprint}]}` |
| `POST /v2/machines/:id/heartbeat` | | `204` |
| `DELETE /v2/machines/:id` | | `204` |
| `POST /v2/relay/tickets` | `{machine_id, permission: "register"\|"connect", target_machine_id?}` | `{ticket, expires_at_unix, relay_url}` |
| `POST /v2/pairings` | `{from_machine_id, to_machine_id, requester_x25519_b64}` | `201 {pairing_id, code}` |
| `GET /v2/pairings?role=target\|requester` | | `{pairings: [{pairing_id, from_machine_id, to_machine_id, requester_fingerprint, requester_x25519_b64, code, status, sealed_invite_b64?}]}` |
| `POST /v2/pairings/:id/approve` | `{sealed_invite_b64}` | `204` |
| `POST /v2/pairings/:id/deny` | | `204` |

Error codes: `desktop_only` (403), `invalid_machine` (400), `machine_not_found` (404),
`pairing_not_found` (404), `not_granted` (403), `pairing_not_pending` (409), `pairing_expired` (410),
`plaintext_invite` (400), `relay_v2_unavailable` (503), plus the generic `bad_request`, `forbidden`,
`rate_limited` and `unauthorized`.

- **Machines:** one machine per device token. A second `POST` refreshes `name`, `os_version` and
  `app_version`; a changed `noise_public_key_b64` also updates the fingerprint (first 16 hex of
  SHA-256 of the key), deletes every grant from or to the machine and expires its pending pairings.
  `slot` (16 random bytes, base64url) is the machine's address on relay2; it is returned only to its
  owner and never listed. `online` = heartbeat within 90 s; the heartbeat is owner only (403
  `forbidden` for another machine of the account), `DELETE` works for any desktop of the account and
  removes the machine's grants and pairings. Other accounts' machines are always 404.
- **Pairings:** `from` must be the caller's own machine, `to` another machine of the account. The
  server draws the 6-digit `code` (distinct among a target's pending requests) and takes the
  fingerprint from the stored key; nothing of either is read from the body. Pending requests expire
  after 5 minutes; a newer request from the same requester supersedes the older one; at most 10
  pending per target (429). `requester_x25519_b64` (the public key to seal the invite to) is on both
  roles' items and must equal the requester machine's `noise_public_key_b64` (D1; else 400). Only the target approves (a second approve after the TTL is 410, after a decision
  409); approving stores `sealed_invite_b64` verbatim (at most 8192 decoded bytes) and grants
  `from -> to` `connect`. The server never reads the invite beyond a length check and a guard that
  refuses a plaintext `cmux://` URI (case-insensitive, 400 `plaintext_invite`). Only the requester
  gets the invite back. The target or the requester can deny.
- **Relay tickets:** checks run in this order: auth, desktop, body size, relay v2 configured (503
  `relay_v2_unavailable` when `CMUX_RELAY_HMAC_SECRET` is missing or under 32 bytes), per-device
  rate limit, then the body: `permission` must be `register` or `connect` (400), `machine_id` must
  be the caller's own machine (another machine of the account 403 `forbidden`, anything else 404).
  `register` signs the caller's own slot (never another machine's). `connect` needs
  `target_machine_id` (400) in the account (404); connecting to your own machine needs no grant
  (the host mints it for an enrollment invite); any other target needs an approved pairing
  (403 `not_granted`, revoked by a key rotation or by deleting either machine) and signs the
  target's slot. The slot always comes from the database, never from the body. The ticket lives
  120 s; `relay_url` is `RELAY_V2_URL`. Tickets, slots and secrets are never logged.
- **Configuration:** `CMUX_RELAY_HMAC_SECRET` (at least 32 bytes, used verbatim),
  `CMUX_RELAY_ISSUER` (default `shellx-relay`), `RELAY_V2_URL`. Without a usable secret the relay
  runs and `/v2/relay/tickets` answers 503. The exact path `/v2/relay` is the relay2 WebSocket
  behind nginx and is not served by this app.

## Push notifications

Design: `docs/superpowers/specs/2026-10-05-push-notifications-design.md` §5.

- `PUT /v1/devices/me/push-token {token, platform}` (phones only, `403 mobile_only` otherwise; token
  1..4096 characters, platform `android` or `ios`) stores the phone's FCM token; a token registered
  again by another device moves to it. `DELETE /v1/devices/me/push-token` removes it. Logout removes
  it too, and deleting the account removes it with the device.
- `POST /v1/notifications {title, body, data?}` (agents only): title 1..200, body 1..1000
  characters, `data` at most 10 string values (FCM-reserved keys such as `from`, `google…`, `gcm…`
  are refused with 400; the relay adds `agent_id`). Recipients are the phones with a pairing record
  to this agent, a push token and a live sign-in. Answers `202 {sent}` after FCM answered for each;
  tokens FCM reports `UNREGISTERED`/`INVALID_ARGUMENT` are deleted; other FCM errors are logged by
  kind and not retried. 120 per agent per hour (`429 rate_limited`). 503 `push_unavailable` without
  configuration.
- `src/push/fcm.ts` talks to FCM HTTP v1 with an OAuth token from a JWT (RS256, `node:crypto`)
  signed with the service account key; the token is cached until a minute before it expires.
- Logs never contain titles, bodies or tokens (only counts and the agent's `device_id`).
- **Local test against a fake FCM server:** `npm run fake-fcm-account -- .data/fake-fcm.json`, then
  `FCM_SERVICE_ACCOUNT=.data/fake-fcm.json FCM_ENDPOINT=http://127.0.0.1:8788
  FCM_TOKEN_ENDPOINT=http://127.0.0.1:8788/token npm run dev` (environment variables win over
  `dev.env`). `packages/shellx_e2e/test/push_e2e_test.dart` runs that fake server on port 8788.

## Admin dashboard

A request whose `Host` (port and case ignored) is `ADMIN_HOST` is answered only by the admin app
(`src/admin/`): the static UI in `admin/` (`/`, `/admin.css`, `/admin.js`) and a JSON API under
`/api/` (`session`, `login`, `logout`, `stats`, `settings`). No relay route answers on that host and
no admin path answers on any other.

- **Sign-in:** one shared password (`ADMIN_PASSWORD`, compared as SHA-256 digests in constant time).
  The session id lives in the `shellx_admin` cookie (HttpOnly, Secure, SameSite=Strict, 12 h); the
  relay keeps only its digest, in memory, so a restart signs the admin out. 5 failed sign-ins per IP
  within 15 minutes → 429 for that IP, even with the right password (independent of
  `RATE_LIMITS_ENABLED`).
- **Mutating calls** (POST/PUT) need `Content-Type: application/json` and, when the browser sends an
  `Origin`, `https://<ADMIN_HOST>` (or `http://<ADMIN_HOST>[:port]` for dev); else 403 `forbidden`.
  Every admin response carries a strict CSP (`script-src 'self'`, no inline code), `nosniff`,
  `no-referrer`, `X-Frame-Options: DENY` and `Cache-Control: no-store`.
- **Minimum versions:** `PUT /api/settings {min_agent?, min_mobile?}` stores an override in
  `app_settings` that `GET /v1/version` serves instead of `MIN_AGENT`/`MIN_MOBILE` (read per request,
  no restart); `null` removes it. `latest_agent` stays env only.
- **App versions:** the apps send their `x.y.z` in `X-ShellX-Version`; on every authenticated call,
  WebSocket upgrade, register and login the relay stores it in `devices.app_version` when it changed
  (anything not `\d{1,6}.\d{1,6}.\d{1,6}` is ignored). `GET /api/stats` reports the distribution.
- **Locally:** `npm run dev` sets `ADMIN_HOST=admin.localhost` and a dev-only password; open
  http://admin.localhost:8787 (Chrome and Firefox resolve `*.localhost` to 127.0.0.1 and accept the
  Secure cookie there).

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

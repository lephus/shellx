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
  codes, frame sizes); never payloads, tokens, passwords or e-mail addresses. Workers Logs
  **invocation logs are turned off** on purpose (`observability.logs.invocation_logs: false` in
  `wrangler.jsonc`): invocation logs record request metadata for every call, including the client IP
  (`cf-connecting-ip`), and the privacy policy only allows using the IP transiently for rate limiting —
  not storing it in logs. Our own structured `console.log` lines (the metadata above) are unaffected
  and still show up in `wrangler tail` and Workers Logs.
- Emergency password reset (spec §5.2):

  ```bash
  # generates a temporary password and prints it once
  npm run reset-password -- --env production --email user@example.com

  # supply your own password without it landing in shell history or a process list
  npm run reset-password -- --env production --email user@example.com --password - --revoke-tokens
  # then type the password at the prompt; or non-interactively:
  SHELLX_RESET_PASSWORD='new password' npm run reset-password -- --env production --email user@example.com --revoke-tokens
  ```

  `--password <value>` directly on the command line also works but prints a warning, since it is
  visible in shell history and process lists — prefer `--password -` (reads one line from stdin) or the
  `SHELLX_RESET_PASSWORD` environment variable. Without any of these a random password is generated and
  printed once. `--env staging` and `--env production` ask you to type the account's e-mail address to
  confirm before touching anything remote; pass `--yes` to skip that prompt for scripting. `--env local`
  never asks. `--revoke-tokens` signs out every device of the account (sockets already open stay up
  until they reconnect). Pairings are kept.
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

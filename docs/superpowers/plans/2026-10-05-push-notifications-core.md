# Push notifications core (stream N-a) — implementation plan

- **Spec:** `docs/superpowers/specs/2026-10-05-push-notifications-design.md` §1–§5, §8, §10 (mobile/desktop bullets excluded: stream N-b).
- **Branch:** `feat/push-core`. Not touched: `apps/mobile`, `apps/desktop`, `web/`.
- **Goal:** relay push gateway (tokens, `POST /v1/notifications`, FCM HTTP v1), `ShellxApi` calls, agent event detection + sending, shell hooks for ShellX sessions and shared desktop terminals, and an e2e over the local relay with a fake FCM server.

## Task 1 — relay: schema and push tokens
- `relay/migrations/0003_push_tokens.sql` (spec §5 table + unique index on `token`).
- `relay/src/routes/devices.ts`: `PUT /v1/devices/me/push-token` (mobile only → else `403 mobile_only`; token 1..4096, platform `android|ios` → else `400 bad_request`; upsert, a token moves from any other device), `DELETE /v1/devices/me/push-token` (`204`, idempotent).
- `relay/src/routes/auth.ts`: logout deletes the device's push token (both branches); account deletion cascades (FK).
- Tests (`test/push-tokens.test.ts`): mobile only, validation, upsert + move, delete, logout, account delete cascade; `db.test.ts`/`app.test.ts` migration lists.

## Task 2 — relay: FcmClient and config
- `relay/src/push/fcm.ts`: `parseServiceAccount`, `FcmClient` (JWT RS256 with `node:crypto`, token cache until 60 s before expiry, one token request in flight, `messages:send` body per spec §5, result `ok | invalid_token | error`; `UNREGISTERED`/`INVALID_ARGUMENT` → `invalid_token`; 401 drops the cached token; 10 s timeout).
- `relay/src/push/config.ts`: `loadPush(env, readFile)` → gateway or `null` + reason (`not_configured | unreadable | invalid`); `FCM_ENDPOINT` / `FCM_TOKEN_ENDPOINT` honoured only for loopback `http://` URLs (tests).
- `src/server.ts` logs `push_enabled` / `push_disabled {reason}` once.
- Tests (`test/fcm.test.ts`): JWT shape and signature verified with the public key, cache, refresh, error mapping, config loading.

## Task 3 — relay: `POST /v1/notifications`
- `relay/src/routes/notifications.ts`: agent only → `503 push_unavailable` without gateway → `429` (new `notifyAgent` limiter 120/h/agent, off with `RATE_LIMITS_ENABLED=false`) → validation (title 1..200, body 1..1000 code points, `data` ≤ 10 string→string, FCM-reserved keys refused) → recipients = phones of the same account with a pairing to this agent, a push token and a live token → send all, delete `invalid_token` tokens → `202 {sent}`. `data.agent_id` is set by the relay.
- Tests (`test/notifications.test.ts`) with a fake gateway.
- `deploy/docker-compose.yml` (`./secrets:/secrets:ro`, `FCM_SERVICE_ACCOUNT: ${FCM_SERVICE_ACCOUNT:-}`), `deploy/README.md` step, `relay/README.md`; `relay/scripts/fake-fcm-service-account.ts` for local e2e.

## Task 4 — shellx_core
- `PushPlatform {android, ios}`, `ShellxApi.registerPushToken(token, platform)`, `deletePushToken()`, `sendNotification(title, body, {data})` → `int sent`. Tests with `MockClient`.

## Task 5 — agent: `lib/src/notify/`
- `osc_event_parser.dart`: `OscEventParser.feed(bytes) → List<OscEvent>` (133 C/D, 633 E with VS Code unescaping, OSC 9 except `<digits>;`, OSC 777 notify; 4 KiB cap; BEL/ST; chunk-safe; malformed UTF-8 tolerated; 200-char truncation).
- `command_tracker.dart`: `CommandTracker(threshold: Duration? Function(), now)`.
- `notification_text.dart`: vi/en titles, bodies, durations.
- `notification_sender.dart`: 6/min sliding window, never throws, drops on error, counts drops.
- `agent_notifications.dart`: `NotificationsConfig` (api, threshold, machineName, locale) → `AgentNotifications` → `SessionNotifier` per session (`forShell(id, index)`, `forDesktop(id, app, title)`).
- Wiring: optional `notifications:` on `SessionManager` (live pty output) and `DesktopSessionManager` (live `out` only; parser reset on a new link; never the snapshot). Existing tests untouched.
- Tests with `fake_async`.

## Task 6 — agent: shell hooks for ShellX sessions
- `lib/src/pty/shell_integration.dart`: `ShellIntegration(directory)` → `apply(command, environment)`; zsh (ZDOTDIR shim, `.zshenv` only, see rulings), bash (`--rcfile`, emulates login files when the command was a login shell), PowerShell (`-NoExit -Command ". '<script>'"`), anything else unchanged; files rewritten when missing; failures fall back to the plain command.
- Optional `shellIntegration:` on `SessionManager`.
- Tests: real `zsh -i` / `bash -i` via `Process` (interactive without a tty runs preexec/precmd/DEBUG/PROMPT_COMMAND; verified), user files still loaded, `shellx notify`, an existing `shellx` command wins; PowerShell script checked as text (no pwsh on this machine).

## Task 7 — term blocks
- Inner-shell branch of `term/shell/block.zsh` / `block.bash` / `block.ps1` installs the same hooks; ASCII; nothing defined when not wrapping.
- Tests in `term/tests/block.rs` with the real binary: inner zsh and bash emit 633;E, 133;C, 133;D;1; text tests in `blocks_text.rs`.

## Task 8 — e2e
- `packages/shellx_e2e/test/push_e2e_test.dart`: fake FCM HTTP server on `SHELLX_E2E_FAKE_FCM_PORT`; phone registers a token, pairs; ShellX session (`zsh -i` with hooks, threshold 0) runs `sleep 1; false` → fake FCM gets token, title, body.
- Run against `npm run dev` started with the fake-FCM env, then stopped.

## Gates
`npm run typecheck`, `npm test` (relay); `dart analyze` + `dart test` (shellx_core, shellx_agent, shellx_e2e); `cargo fmt --check`, `cargo clippy`, `cargo test --features test-hooks` (term).

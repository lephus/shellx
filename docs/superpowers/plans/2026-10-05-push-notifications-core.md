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

## Rulings (decided during implementation)

- Ruling: the zsh shim holds only `.zshenv`, which restores the user's `ZDOTDIR` at once and installs the hooks through a one-shot `precmd` at the first prompt (spec §4.4 named four shim files) — macOS `/etc/zshrc` derives `HISTFILE` from `ZDOTDIR`, so a shim kept until `.zshrc` would put history in the agent's directory; a `ZDOTDIR` the user sets in `.zshenv` is honoured; the hooks run first in `precmd_functions` — cost if wrong: a `.zshrc` that empties `precmd_functions` loses the hook (no command notifications, nothing else).
- Ruling: bash `--rcfile` reads the login files (`/etc/profile`, first of `~/.bash_profile`/`~/.bash_login`/`~/.profile`) when the resolved command was a login shell (`-l`, what macOS starts), else `~/.bashrc` — `--rcfile` only applies to non-login shells — cost: `shopt login_shell` is off in ShellX bash sessions.
- Ruling: bash is not hooked when a `DEBUG` trap already exists (bash-preexec etc.); `PROMPT_COMMAND` is joined with newlines and re-wrapped by the trap if the startup files replace it — cost: those users get no command notifications.
- Ruling: PowerShell does not dot-source the profile (PowerShell loads it before `-Command`), and E/C come from wrapping `PSConsoleHostReadLine` (VS Code's method) instead of `AddToHistoryHandler`/`CommandValidationHandler`; a `prompt` the profile sets after the hook is wrapped again at the next line read — cost: without PSReadLine no command notifications.
- Ruling: the relay sets `data.agent_id` from the agent's token; a client-supplied `agent_id` and FCM-reserved keys (`from`, `notification`, `message_type`, `collapse_key`, `google*`, `gcm*`) are refused with 400 — FCM would answer INVALID_ARGUMENT and the relay would then delete the phone's token — cost: none known.
- Ruling: recipients also need a live sign-in (a token used within 90 days), not only a push token — a phone signed out by a password change keeps its push token row — cost: none.
- Ruling: order of checks `agent_only` → `503 push_unavailable` → `429` → `400` — an agent on a relay without push does not spend its budget — cost: invalid bodies count against the 120/h.
- Ruling: `FCM_ENDPOINT`/`FCM_TOKEN_ENDPOINT` are honoured only for loopback URLs — a stray value in production can never send the access token elsewhere — cost: none.
- Ruling: push configuration is loaded by `src/push/config.ts`, separate from `Config` (whose tests compare the whole object) — cost: none.
- Ruling: the `notifyAgent` limiter follows `RATE_LIMITS_ENABLED=false` like the others (dev relay, e2e) — cost: none.
- Ruling: titles `<machine> · <session>` (session: `Phiên n`/`Session n`, desktop `<app> — <window title>`); durations leave out zero parts (`3 phút`, `1 giờ`); English `exit`, `s`, `min`, `h`; control characters in a command line become one space — cost: wording only.
- Ruling: the sender clips the title to 200 and the body to 1000 characters (with `…`) before sending — cost: none.
- Ruling: shared terminals reset the OSC parser on every new link (a sequence cut by a reconnection is dropped) but keep the command tracker (a command started before still ends after) — cost: none.
- Ruling: the zsh block's inner branch is now `SHELLX_TERM` non-empty and equal to `$TTY` (login handling nested inside, unchanged); hooks are therefore also defined in nested shells and in `shellx-term`'s fallback shell — cost: a fallback (unwrapped) window sends OSC 133 to the terminal app (ignored, or command marks in iTerm2).
- Ruling: `ShellIntegration` hooks only plain starts (`-i`, `-l`, `--login`, PowerShell `-NoLogo`/`-Login`/`-NoExit`); anything else starts unchanged; hook files are rewritten before each start when missing or stale (temporary directories get cleaned) — cost: none.
- Ruling: hook tests run real `zsh -i`/`bash -i` through `Process` without a tty (interactive shells run preexec/precmd/DEBUG/PROMPT_COMMAND without one — verified), the blocks through the term crate's real-PTY harness; PowerShell was verified by hand with a portable pwsh 7.4.6 in a pty (not in the automated suite; Windows PowerShell 5.1 not run) — cost: a PowerShell regression is only caught by hand or by the Windows CI's existing block tests.
- Ruling: the e2e fake FCM listens on a fixed port (8788, `SHELLX_E2E_FAKE_FCM_PORT`); the relay is started by hand with `FCM_SERVICE_ACCOUNT` from `npm run fake-fcm-account` and the two loopback overrides — cost: one more manual step for that test (it is skipped without `SHELLX_E2E_RELAY`).

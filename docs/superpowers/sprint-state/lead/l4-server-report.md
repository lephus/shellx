# l4-server — lane report (W2 server: API v2 + relay v2), 2026-10-19

## Branches
- `feat/relay-v2` (worktree ~/Documents/myProjects/shellx-wt-l4), head **4912e397a3d55bfdfb1c169543f1162d686454d1**, pushed to origin (lephus/shellx). **ready 4912e397a3** (merge with `git merge --no-ff`, see below).
- `feat/relay-v2-subdomain` (K2 fallback, relay2.shellx.pro), head ec805422df, local only (one commit on top of feat/relay-v2).
- `feat/flutter-1.0.1` (worktree ~/Documents/myProjects/shellx-wt-l4-flutter, from d53d608a88 = last commit with the Flutter tree), head 38becef892, local only, pubspec unchanged (1.0.0+1). W3 A2 is done.

## Tasks
1–10 done and reviewed. 11 (G2) is prepared only: no deploy, no ssh. 12 is done. Nothing was cut.
- T1 migration 0005 + `desktop` kind · T2 config/errors/encoding/tickets · T3 /v2/machines · T4 /v2/pairings · T5 /v2/relay/tickets + README API v2 · T6 interop vs the real cmux-relay + `npm run relay2:smoke` · T7 relay2 recipe (Dockerfile, source-tarball.sh, CI build + smoke, publishes nothing) · T8 compose relay2 (profile `relay2`, built on the VPS from pinned commit 57dd520ccf, nginx path `= /v2/relay` → `/v1/relay`), rollout, deploy.yml checks, runbook "Relay v2" · T9 C15 `/v1/version` per platform (K6) · T10 security review + fixes · final whole-branch review + fixes.

## Tests / CI (verified by the controller at 4912e397)
- relay: typecheck clean; vitest 36 files, 551 passed, 7 skipped (the interop suite skips without a binary).
- interop against the real `cmux-relay` binary (built from crate sources identical to this branch): 7/7. API-minted register and connect tickets are accepted; tampered, wrong-secret, expired and register-as-connect tickets are refused; the smoke function returns OK with a 30 s lease.
- deploy: `node --test deploy/tests/*.test.mjs` 53/53 on both branches. `docker compose config -q` exits 0 with and without `COMPOSE_PROFILES=relay2`. `tests/test_shellx_relay2.py` OK.
- CI: shellx-relay2 run **39165705648** is green (Docker build from the tarball plus smoke). deploy.yml runs only on main and was not triggered.

## Reviews
- Each task had a task review: T8 needed one fix round, T7 one re-review of its CI hardening.
- The T10 security review answered checklist items 1–8 PASS. Its one Important finding (N-I1) is fixed: the pairing key is now bound to the machine key (R17).
- The final review (opus) said "with fixes". The fixes were procedural: merge with `--no-ff`, and run the FK pre-check before pushing main. Both are fixed and re-reviewed clean.

## Rulings (in order; cost if wrong)
- R1 (superseded by R4/R10) relay2 pinned to a fork sha — one sed.
- R2 recipe in parallel with Tasks 1–6 — none.
- R3 no local docker build; CI only — a Dockerfile bug surfaces in CI (it is green).
- R4 relay2 source reaches the VPS as a `git archive` tarball of the pinned commit, built by compose `build:`, local tag, `pull_policy: never` — one scp, or one compose line to switch to a git context.
- R5 Dockerfile COPY allowlist; no BUSL code in any layer — none.
- R6 CI does build + smoke only, `contents: read` — CI minutes.
- R7 relay2 sits behind compose profile `relay2`; the deploy.yml `/v2/relay` check is gated on `vars.RELAY2_ENABLED` — one .env line plus one variable.
- R8 CI hardening (timeout, masked secret, paths filter) — one amend.
- R9 keep the database-wide `foreign_key_check` in 0005, plus a pre-check on the VPS DB copy — one blocked deploy.
- R10 recipe follows the repo move: trigger on [feat/relay-v2, main], label lephus/shellx, R = 57dd520ccf — one-line edit.
- R11 fix 2 re-reviewed together with the repo-move fix — one review seat.
- R12 Flutter 1.0.1 branch based on d53d608a88, because main has no Flutter tree — a rebase onto whatever Flutter maintenance branch L0 names.
- R13 `requester_x25519_b64` also on role=requester items — drop one field.
- R14 second approve after TTL returns 410; `cmux://` guard is case-insensitive; code exhaustion returns 500; limiter counts before validation — small edits.
- R15 interop ran on a copy of the debug binary built from 36d7697869 (crate sources identical) — one cargo build.
- R16 the four platform keys live in `PLATFORM_MIN_KEYS`, not `MIN_VERSION_KEYS`; no admin write until W3 A1b — A1b moves 4 keys.
- R17 the server enforces D1: `requester_x25519_b64` must equal the requester machine's `noise_public_key` (400) — a non-D1 client gets 400.
- R18 the T10 wave also took cheap pre-deploy minors: runbook FK pre-check, issuer whitespace → ConfigError, relay2 `cap_drop ALL` + no-new-privileges, smoke script https-only — one small revert each.
- Final wave (unnumbered, review-driven): migrate.ts refuses `DROP TABLE` without the foreign_keys=off directive (otherwise every token is silently cascade-deleted) and tolerates a BOM; runbook notes for `--no-ff`, push timing, `$PROXY`, relay2 pre-build, rollback check — small revert.

## K-change requests
None. R17 makes a K1 rule stricter without changing its shape; please record it in the ledger for L5/L6.

## Notes for L0 / L5 / L6
- `relay_url` = `wss://relay.shellx.pro/v2/relay` (fallback `wss://relay2.shellx.pro/v1/relay`). Ticket issuer `shellx-relay`, lifetime 120 s.
- L5/L6 must send `requester_x25519_b64` = the D1 device key, which is the same key as `noise_public_key_b64`. The target app should compute the fingerprint itself from `requester_x25519_b64` rather than trust `requester_fingerprint`.
- `POST /v2/machines` returns 200 on re-register. `last_seen_unix` is null before the first heartbeat. Stale machines (after a state_dir wipe) need a DELETE in the UI.
- Browsers cannot use relay2 directly: cmux-relay refuses any `Origin` (relevant to L7).
- Ledger: W3 A1 may take its skip condition (A1b, the admin write path with the "downloadable" guard, is still to do). W3 A2 is done on `feat/flutter-1.0.1` 38becef892.

## Needs user (G2; never paste values in chat)
1. Before pushing main: run the "Pre-check" in deploy/README.md "Relay v2": `PRAGMA foreign_key_check` on a COPY of relay.db; any row means stop.
2. Merge `feat/relay-v2` into main with `git merge --no-ff` (keeps 57dd520ccf reachable) and push main. That push is the production deploy; relay2 stays off.
3. VPS secret: append `CMUX_RELAY_HMAC_SECRET` via `openssl rand` to `~/phu/shellx/.env`, per the README.
4. nginx-proxy image tag: does it support `VIRTUAL_PATH "= /v2/relay"`? If not, use DNS `relay2.shellx.pro` and the `feat/relay-v2-subdomain` branch.
5. Stage the relay2 source: on the Mac run `scripts/shellx/relay2/source-tarball.sh 57dd520ccf… <dir>`, scp it, extract to `relay2-src/`, check the sha256.
6. Pre-build once with `docker compose --profile relay2 build relay2`, then set `COMPOSE_PROFILES=relay2` and the repo variable `RELAY2_ENABLED=true`.
7. Copy the vhost file (330 s timeouts) into nginx-proxy's vhost.d, then check `nginx -T`.
8. Run `npm run relay2:smoke` in your own terminal (password hidden); expected output `relay2 smoke: OK (registered, lease 30 s)`.

## Deferred minors (none blocks the merge; triaged by the final review)
- Before enabling relay2: README step 7's `sed` drops the whole `COMPOSE_PROFILES` line.
- Later:
  - Pairings purge only runs on /v2/pairings requests; housekeeping is a write transaction per request; no (status, created_at) index.
  - `decodeB64` is lenient; v1 login has no proof of possession (N-M1); a whitespace-prefixed `cmux://` slips the guard.
  - Admin desktop "online" count is always 0; the smoke run leaves a device row.
  - Rust build cache is never pruned; relay2 `mem_limit` 256m; when enabled, relay2 couples v1 rollouts.
  - Test-coverage nits across T2–T9; manifest url `..`; A1b must validate on write.

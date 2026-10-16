# SDD ledger — plan: docs/superpowers/plans/2026-09-25-shellx-v1-01-relay.md

Worktree: /Users/lehuuphu/Documents/myProjects/shellx/.worktrees/relay (branch feat/shellx-v1-relay, from feat/shellx-v1 @ 3267da6)
Spec: docs/superpowers/specs/2026-09-25-shellx-v1-design.md ; Overview: docs/superpowers/plans/2026-09-25-shellx-v1-00-overview.md

## Pre-flight scan

Evidence: plan author built the relay in scratch, rendered every code block from those files, and replayed tasks 1–11 in order: each task's tests + full suite + typecheck pass after each task (129 tests); final replay byte-identical to prototype. Real checks: npm run dev (with and without -- --ip/--port), 5 registrations from one IP (limits off), reset-password --env local, WS ping/pong, bad token → 401, plain GET /v1/ws → 426, DELETE /v1/account → 204, wrangler deploy --dry-run prod + staging.

| Tasks | Shared file / interface | Producer → consumer | Finding |
|---|---|---|---|
| 1,3,4,6,10 | package.json, wrangler.jsonc, vitest.config.ts | incremental edits per task | OK — replay verified ordering |
| 1 → 5,9,10 | src/auth/argon2.ts, password.ts (hashPassword/verifyPassword) | 1 produces | OK |
| 2 → 6,7,8 | src/protocol/frames.ts, cbor.ts, uuid.ts | 2 produces | OK |
| 3 → 5 | email.ts, password-policy.ts | OK |
| 4 → 5–9 | src/app.ts, env.ts, errors.ts, rate-limit.ts | incremental route wiring | OK |
| 5 → 6,8,9 | tokens.ts, session.ts (auth middleware) | OK |
| 6 → 7,8,9 | src/hub/user-hub.ts | 7 adds token bucket, 8 adds RPC, 9 uses disconnect | OK |
| each 1–11 | self-consistency | verified by replay | OK |

Rulings:
- Ruling: accept plan-01 contract decisions 1–10 (401 unauthorized before WS upgrade, extra error codes, one live token per device, NFC passwords, /v1/devices lists signed-in devices incl. caller, presence snapshot excludes self, pairing_removed to both sides + offline queue, POST pairings 201 empty/idempotent, DELETE /v1/account shares 5/email budget) — consistent with spec and overview; plan 03 handles pairing_removed idempotently — cost if wrong: small client adjustments.
- Ruling: argon2id via @phi-ag/argon2 0.5.28 WASM (exact pin) with own wrapper (package JS class truncates UTF-8) — R1 spike passed at 29 ms median — cost if wrong: switch to written-out @noble/hashes fallback (233 ms).

Model plan: implementers sonnet for 1,4,5,6,7,8,9 (env/DO complexity), haiku for 2,3,10,11; reviewers sonnet; final review opus.

## Progress
Task 1: implementer a289c1036ea7af696 (sonnet) dispatched, base 3267da6
Task 1: implemented by a289c1036ea7af696, commit a712f6f (median 68 ms); review dispatched (sonnet)
Task 1: review — spec ✅, 1 Important (plan-mandated): argon2.ts hash()/verify() allocate outside try/finally → password buffer may leak unwiped on mid-sequence alloc failure. npm audit: 0 prod vulns; 4 high dev-only (miniflare→sharp).
Task 1: Ruling: fix the plan-mandated allocation pattern now (allocate every buffer inside try, finally wipes+frees each non-zero pointer) — spec requires never leaving password material resident; tiny change — cost if wrong: none.
Task 1: minor (deferred): malformed-PHC tests lack truncated-salt/hash case
Task 1: ⚠️ real edge deploy + KAT values — resolved: plan author verified wrangler deploy --dry-run and cross-checked KATs with node crypto.argon2Sync and @noble/hashes.
Task 1: fix round 1/5 dispatched to a289c1036ea7af696 (FIX_BASE a712f6f)
Task 1: fix round 1/5 (1 addressed, 0 open — argon2 allocations inside try; commits a712f6f..f7f1c9b)
Task 1: minor (deferred): JS-side password Uint8Array not zeroed after use
Task 1: minor (deferred): 4 high npm audit advisories are dev-only (miniflare→sharp)
Task 1: complete (commits 3267da6..f7f1c9b, review clean)
Task 2: implementer a0ffc0f72ec6d1a59 (haiku) dispatched, base f7f1c9b
Task 2: implemented commit b8250cf; review dispatched (sonnet) with cross-check vs Dart core golden vectors
Task 2: review spec ✅ Approved; cross-plan byte comparison with Dart frames_test.dart: DATA/PRESENCE/ERROR(nil peer)/EVENT layouts identical.
Task 2: minor (deferred): parseUuid checks shape only (no RFC 4122 version nibble) — intended
Task 2: complete (commits f7f1c9b..b8250cf, review clean)
Task 3: implementer a6a565942a28217ca (haiku) dispatched, base b8250cf
Task 3: implemented commit f809e1e (8,981 domains); review dispatched (sonnet)
Task 3: ⚠️ README documents domains:update — resolved: Task 11 scope.
Task 3: minor (deferred): parent-domain walk reaches bare TLD; safe only while list has no public-suffix entries (plan-mandated) — consider guard in hardening
Task 3: minor (deferred): update script lets fetch() network errors surface as unhandled rejection
Task 3: complete (commits b8250cf..f809e1e, review clean)
Task 4: implementer a1b62e630172c002a (sonnet) dispatched, base f809e1e
Task 4: implemented commit fd7484e; review dispatched (sonnet)
Task 4: ⚠️ USER_HUB binding (Task 6), prod/staging database_id (runbook), limiter wiring on routes (Task 5) — resolved: later tasks / runbook.
Task 4: Ruling: rate-limiter binding *errors* fail open (allow request, log `rate_limit_error` metadata only) — Cloudflare binding outages are rare, argon2id already makes guessing expensive, and a blanket 500 on login would lock every user out — applied in Task 5 dispatch — cost if wrong: brief window without throttling during a binding outage.
Task 4: minor (deferred): logMeta string values are convention-only protection against logging secrets
Task 4: complete (commits f809e1e..fd7484e, review clean)
Task 5: implementer a3c0f6bba93b1da86 (sonnet) dispatched with fail-open ruling, base fd7484e
Task 5: implemented commits 5543f90 0945a22 (fail-open ruling); review dispatched (sonnet)
Task 5: ⚠️ requireAuth/parseBearer not yet mounted/tested via header — resolved: exercised when later tasks mount protected routes (Tasks 6, 8, 9); final review to confirm.
Task 5: minor (deferred): UNIQUE race detection matches SQLite error text (plan-mandated)
Task 5: minor (deferred): fail-open login test doesn't assert loginEmail label
Task 5: minor (deferred): device name length counts code points, not graphemes
Task 5: complete (commits fd7484e..0945a22, review clean)
Task 6: implementer af1c7755a6ed7b33f (sonnet) dispatched, base 0945a22
Task 6: implemented commit ca7f9a0 (105 tests; count drift only); review dispatched (opus)
Task 6: review (opus) spec ✅ Approved — cross-account isolation by construction, header spoofing prevented by Headers.set, replacement race handled.
Task 6: Ruling: fold three cheap hardening items into Task 7 (same files): forward only an allowlist of headers from /v1/ws to the hub; add a regression test that a client-sent X-Shellx-Device-Id/Kind is overridden by the token's values; wrap the close-time last_seen_at D1 write in try/catch with logMeta("last_seen_write_failed", {device_id}) — security-critical path, low cost — cost if wrong: none.
Task 6: minor (deferred): no test that a replaced socket leaves last_seen_at unwritten
Task 6: minor (deferred): self-addressed DATA loops back to sender
Task 6: minor (deferred): last_seen_at may be written after a quick reconnect (slightly stale value)
Task 6: complete (commits 0945a22..ca7f9a0, review clean)
Task 7: implementer addb8ab42c61b66fe (sonnet) dispatched with Task 6 hardening ruling, base ca7f9a0
Ruling (from plan 06 final review): verify whether Workers Logs invocation logs (observability) record client IP/headers; if so, disable invocation logs in wrangler.jsonc so only logMeta lines are kept (privacy policy promises IP used only transiently for rate limiting) — to apply in a later relay task (Task 11 README/runbook task or earlier) — cost if wrong: privacy statement inaccurate.
Task 7: implemented commits 8a9c350 94fadbd (112 tests; concerns: spoof test non-discriminating, hibernation test timing-sensitive); review dispatched (sonnet)
Task 7: review spec ✅ (brief + ruling items 1,3 correct); 3 Important: (a) spoof test non-discriminating; (b) hibernation test timing-flaky (plan-mandated); (c) bucket reset on reconnect → rate-limit bypass (plan-mandated design gap).
Task 7: Ruling: fix all three — real allowlist test with RED against copy-all; deterministic limiter test (injected clock / fake timers / full-bucket flood); keep a device's bucket across reconnects — cost if wrong: none.
Task 7: minor (deferred): Sec-WebSocket-Protocol/Extensions forwarded but never negotiated by the DO
Task 7: fix round 1/5 dispatched to addb8ab42c61b66fe (FIX_BASE 94fadbd)
Task 7: fix round 1/5 (3 addressed, 0 open — real allowlist test; fake-timer limiter tests; bucket kept across reconnects; commits 94fadbd..60eab5c)
Task 7: minor (deferred): buckets Map grows with distinct devices until hibernation; devices per account uncapped (pre-existing)
Task 7: minor (deferred): TestSocket 2000 ms receive timeout can flake under extreme CPU starvation (test/helpers.ts:148)
Task 7: complete (commits ca7f9a0..60eab5c, review clean)
Task 8: implementer a53ebe891a809ed3a (sonnet) dispatched, base 60eab5c
Task 8: implemented commit 0154279 (125 tests); review dispatched (opus)
Task 8: review (opus) spec ✅; authorization sound (no cross-account/mobile-created pairing, no IDOR leak, no hub race). 2 Important (plan-mandated): pairing_removed lost when hub believes a dead agent socket is live; lost when hub notify fails after D1 delete.
Task 8: Ruling: always persist pairing_removed for the agent (dedupe one row per agent/mobile, encode at delivery), deliver on every connect after the snapshot; DELETE = check row (account-scoped) → notify hub (durable) → delete row; fold in account-scoped DELETE — safe failure direction is duplicate removal, never lost removal — cost if wrong: duplicate events (clients idempotent).
Task 8: ⚠️ carry to Task 9: account deletion must clear the hub's SQLite storage (ctx.storage.deleteAll or pending table purge); agent logout should purge its pending_events.
Task 8: minor (deferred): POST pairings check-then-insert not atomic (FK failure → 500 instead of 404)
Task 8: minor (deferred): GET /v1/devices returns 500 if the hub RPC fails (could fall back to offline)
Task 8: minor (deferred): test gaps — both parties connected; paired_with_me from a second agent; 90-day cutoff via injectable now
Task 8: fix round 1/5 dispatched to a53ebe891a809ed3a (FIX_BASE 0154279)
Task 8: fix round 1 commit f6c86eb (128 tests x2); re-review dispatched (sonnet). Ruling: convert the remaining real-clock 'sends ERROR rate_limited' flood test to fake timers in Task 9 (flakes ~2/8 under parallel load) — CI reliability — cost if wrong: none.
Task 8: fix round 1/5 (4 addressed, 0 open — always-persist + dedupe pairing_removed; check→notify→delete; account-scoped; commits 0154279..f6c86eb)
Task 8: minor (deferred): crash between notify and D1 delete leaves a stale pairings row (safe direction; retry fixes)
Task 8: complete (commits 60eab5c..f6c86eb, review clean)
Task 9: implementer a61cfcf623731ecea (sonnet) dispatched with rulings (hub purge on account deletion/agent logout; safe pairing deletion on logout; fake-timer flood test), base f6c86eb
Task 9: implemented commits 73a99c6 e9ead66 (140 tests x5); review dispatched (opus)
Task 9: review (opus) spec ✅ Approved; Important (plan design gap): TOCTOU between token check and hub upgrade lets a just-revoked device keep a socket.
Task 9: Ruling: fix now — re-check token after 101 and self-disconnect with 4002; account deletion via one hub RPC closeAccount() (close all sockets 4002 + purge) in try/catch after commit → 204; purgeAgent try/catch; test assertions/renames — lost-phone advice depends on it — cost if wrong: none.
Task 9: minor (deferred): purgeAgent relies on agent clearing its trust list on self-logout; remote logout with stolen agent token leaves trust/D1 divergence (no new trust granted)
Task 9: minor (deferred): logout deletes WHERE agent_id=? (could restrict to notified pairs); sequential hub RPC per pairing
Task 9: fix round 1/5 dispatched to a61cfcf623731ecea (FIX_BASE e9ead66)
Task 9: fix round 1/5 (3 addressed; 2 new Important in the new guard — unguarded re-check exception → phantom socket + 500; device-id-targeted disconnect can close a newer legitimate reconnection; commits e9ead66..3fe84da)
Task 9: fix round 2/5 dispatched to a61cfcf623731ecea (FIX_BASE 3fe84da) — always return 101, fail-closed re-check, per-connection id (X-Shellx-Conn-Id via buildHubHeaders) + hub closeConnection(connId, code)
Task 9: fix round 2 commit 3680b10 (146 tests x3); re-review dispatched (sonnet)
Task 9: fix round 2/5 (2 addressed, 0 open — always return 101 + fail-closed re-check; connection-targeted closeConnection via server-generated conn id; commits 3fe84da..3680b10)
Task 9: minor (deferred): no hibernate-then-reconnect test for conn_id; inner best-effort close swallows a second failure silently
Task 9: complete (commits f6c86eb..3680b10, review clean after 2 fix rounds)
Task 10: implementer acfbd3fcfee016faa (haiku) dispatched, base 3680b10
Task 10: implemented commit e9e3fbb (150 tests); review dispatched (sonnet)
Task 10: review spec ✅ Approved (SQL injection-safe, CSPRNG); 3 Important (plan-mandated): no production confirmation guard; --password only via argv; CLI existence check/exit paths untested.
Task 10: Ruling: fix all three (typed-email confirmation or --yes for staging/production; SHELLX_RESET_PASSWORD env or `--password -` stdin + argv warning; pure-function wrangler-JSON check + arg/confirm logic tests; clean one-line errors) — emergency tool on production — cost if wrong: none.
Task 10: minor (deferred): multi-row n>1 treated as not found (email UNIQUE makes it unreachable)
Task 10: fix round 1/5 dispatched to acfbd3fcfee016faa (FIX_BASE e9e3fbb)
Task 10: fix round 1/5 (partial — env var + argv warning + JSON check OK; NEW Critical: execSync("cat") never reads the terminal (stdio pipe) and needs a shell/no cat on Windows; decision logic not extracted; commits e9e3fbb..94daad6)
Task 10: fix round 2/5 dispatched to acfbd3fcfee016faa (FIX_BASE 94daad6) — readline/promises single reader, pure decision functions + tests, local smoke via piped stdin
Task 10: fix round 2 commit 10876cf (173 tests; readline single reader; reset-cli.ts pure functions); re-review dispatched (sonnet)
Task 10: fix round 2/5 (single-prompt cases fixed; NEW Critical: second readline question on piped stdin never resolves → exit 13 for --password - + staging confirmation; EOF catch unreachable; commits 94daad6..10876cf)
Task 10: fix round 3/5 dispatched to acfbd3fcfee016faa (FIX_BASE 10876cf) — prompter.ts: line prompter for non-TTY (readFileSync(0), lazy), TTY prompter rejecting on close; one-line errors; 4 subprocess smoke cases
PAUSED 2026-09-25 (user request): Task 10 fix round 3 implementer was STOPPED mid-work; its partial changes were saved as WIP commit (see `git log -1` on feat/shellx-v1-relay, message starts "wip(relay): Task 10 fix round 3"). On resume: dispatch a fresh implementer for round 3 with the same instructions (see round-3 dispatch text in session notes / handoff doc) starting from that WIP commit (FIX_BASE 10876cf), then scoped re-review. Remaining after Task 10: Task 11 (README/runbook + ruling: verify/disable Workers invocation logs if they capture client IP), then final whole-branch review, fix wave, merge.
RESUMED 2026-09-25: Task 10 fix round 3/5 re-dispatched to fresh implementer abf11764abb89f731 (sonnet) from WIP 87303d6 (instructed git reset --soft 10876cf → one commit), FIX_BASE 10876cf
Task 10: fix round 3 commit 08e01b2 (179 tests; typecheck; 4 smoke cases pass; added "node" to relay/tsconfig.json types — flagged); re-review dispatched (sonnet)
Task 10: fix round 3/5 (2 addressed, 0 open — line prompter for non-TTY, TTY prompter rejects on close, one-line errors, 4 smoke cases; commits 10876cf..08e01b2)
Task 10: minor (deferred → FOLD INTO FINAL FIX WAVE): "node" added to relay/tsconfig.json types widens Node globals into src/ typecheck — give scripts/+their tests a separate tsconfig instead
Task 10: minor (deferred → FOLD INTO FINAL FIX WAVE): early process.exit(1) paths (password length, email mismatch) skip prompter.close() (TTY left in raw mode); wrangler failure prints execFileSync message incl. argv/SQL with the argon2 hash — print a generic one-line error
Task 10: complete (commits 3680b10..08e01b2, review clean after 3 fix rounds)
Task 11: Ruling: disable Workers invocation logs (observability.logs.invocation_logs=false), keep our own structured logs — invocation logs carry request headers/cf metadata that may include the client IP, contradicting the privacy policy (IP only transient for rate limiting) — cost if wrong: less per-request debugging data in the dashboard (metrics/analytics still available)
Task 11: implementer a826a23ac9a889fa0 (sonnet) dispatched, base 08e01b2
Task 11: implemented commits 1620143 (invocation logs off) d1b7778 (README; reset section rewritten to real CLI); 179 tests, typecheck, dry-run prod/staging OK; review dispatched (sonnet)
Task 11: review (sonnet) spec ✅ Approved (README commands checked against package.json/wrangler.jsonc/reset CLI; observability inherits whole-object into env blocks)
Task 11: minor (deferred): cost-check section is the brief's template without numbers — fill before launch (pre-launch gate)
Task 11: complete (commits 08e01b2..d1b7778, review clean)
FINAL: whole-branch review dispatched (opus), range 3267da6..d1b7778
FINAL: review (opus) 'With fixes' — Important 1: stale pairing_removed replays after re-pair and silently drops the re-paired phone (reproduced); Important 2: unbounded password/body on login + DELETE account bloats/crashes isolates (argon2 WASM memory never shrinks); Minors: login token can outlive a concurrent password change; reset script 'nothing changed' on JSON parse failure loses the generated password; queued events deleted right after send; --password - echoes on TTY; no periodic token re-check on open sockets. Triage: items 25 (tsconfig node) + 26 (generic wrangler error) fix before merge; all other ledger minors stay deferred.
FINAL: Ruling: fix wave = Important 1 (tombstone rows: replayed on every agent connect, cleared by POST pairing / agent logout / account deletion; regression test unpair→re-pair→reconnect) + Important 2 (bodyLimit 16 KiB on JSON routes; login + DELETE account reject passwords > 128 code points after NFC as invalid_credentials before argon2) + ledger 25/26 + Minor 1 (conditional token insert on unchanged password_hash; hub closes other sockets after commit) + Minor 2 (distinct parse-failure outcome that still prints the generated password) + Minor 4 (mute TTY echo or document) — each is local and cheap — cost if wrong: small diff churn
FINAL: Ruling: defer the periodic hub token re-check alarm to v1.1 (ledger) — main revocation paths already close sockets; the alarm only covers failure/operator paths — cost if wrong: a stolen phone keeps access after an operator reset until it reconnects
FINAL: fix wave dispatched a7265e5e6cb3f42f7 (opus), FIX_BASE d1b7778; findings file final-fix-findings.md
FINAL: fix wave commits 23e289a..d09b248 (211 tests x2, typecheck, 4 smoke cases; new 413 payload_too_large documented; M4 verified by hand in a pty); concerns: workers-types still declares Buffer/process as any; optional argon2 rebuild skipped (caps bound heap to 512 B/request); constraints item 8 superseded by I1 tombstones; scoped re-review dispatched (opus)
FINAL: re-review (opus) — all 7 findings ADDRESSED, ready to merge (211/211 re-run)
FINAL: parked — password change now always calls hub.disconnectAllExcept without try/catch → a hub failure turns a committed change into 500 — Ruling: real, deferred (rare; retry is safe; logout/deletion pattern differs) — cost if wrong: a confusing 500 after a successful change
FINAL: parked — plan-01 doc text still says 'delivered once' (overview on feat/shellx-v1 is updated; plan text is historical) — Ruling: leave plan text — cost if wrong: none
FINAL: parked (minors) — dedupe test no longer exercises INSERT OR IGNORE directly; losing M1 login leaves a token-less device row; forced terminal:true when stderr redirected; wrangler failing after a remote UPDATE prints no generated password (re-run recovers)
FINAL: complete — merging feat/shellx-v1-relay into feat/shellx-v1 (local, no push)

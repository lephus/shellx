# SDD ledger — plan: docs/superpowers/plans/2026-09-26-shellx-vps-infra.md

Spec: docs/superpowers/specs/2026-09-26-shellx-vps-infra-design.md. The user approved it on 2026-09-26 ("ok, triển khai"). V8 was added on 2026-09-27: everything lives in `~/phu/shellx`.
Branch: feat/shellx-vps, worktree .worktrees/vps, based on feat/shellx-v1 at 437c12e.
User instructions: start right away ("bắt đầu triển khai luôn", "commit, rồi giao Task 1 ngay"). Do not push or deploy without asking.

## Pre-flight scan

**Per task (text agrees with itself):** the plan author built the whole port in a scratch copy first, then replayed Tasks 1–5 in order on a fresh `relay/` at 0091c23. Typecheck and tests were green after each task (66 → 86 → 110 → 239 → 263 tests), and the result was byte-identical to the prototype. Tasks 6–9 were verified against the prototype: docker build, nginx behaviour, a compose rollout and rollback run, and YAML parsing.

**Pairs that share files or interfaces:**

| Tasks | Shared file / interface | Finding |
|---|---|---|
| 1 → 2 → 4 → 5 | relay/package.json deps, tsconfig `exclude`, vitest `NOT_YET_PORTED` | Each task removes exactly the entries it ports; Task 5 deletes the lists. Consistent (replayed). |
| 1 → 4 | src/app.ts (`createApp`, `AppDeps`), test/helpers.ts | Task 4 extends the Task 1 versions. Replayed green. |
| 1 → 5 | src/relay.ts `startRelay` → src/server.ts | Consistent. |
| 3 → 4 | HubRegistry/UserHub/HubState → routes/ws.ts | The stateless-handle design is pinned by a test in Task 4. |
| 2 → 4 | argon2/limiter/client-ip → auth routes | Consistent. |
| 5 → 6 | npm scripts (`typecheck`, `test`, `build`) → Dockerfile test stage | Consistent. |
| 6 → 7 → 8 | image names, `deploy/` layout, `rollout.sh` → deploy.yml | Consistent with the Global Constraints (VPS_APP_DIR, name: shellx). |
| 6 ↔ 9 | `[quốc gia]` guard ↔ privacy/terms marker | Intended. The web image, and so every deploy, is blocked until the user gives the country. The user was told. |

Ruling: no pre-flight conflicts. The author's verified replay stands as the per-task consistency check. Cost if wrong: the review loop catches it.
Note: the plan author may still land self-review edits to Tasks 2–9. Before dispatching each task, re-sync the plan from feat/shellx-v1 and re-extract its brief.

Task 1: implementer ac90841ed2a8fbc45 (sonnet) dispatched, base 437c12e

## Plan author's proposed rulings (accepted by controller, 2026-09-27)
- Ruling: "§3 diagram" = v1 §4 diagram; amend every Cloudflare/CI mention in v1 spec (§1, §4.2, §4.3, §5.2, §6.1, §6.2, §14) — why: spec intent — cost if wrong: doc edits
- Ruling: UserHub is a stateless handle over registry-owned HubState — why: a hub kept across an await could orphan a socket (found in prototype, pinned by a Task 4 test) — cost if wrong: none
- Ruling: refused WebSocket upgrades (401/426) return the status with an empty body (clients read only the status) — cost if wrong: a client parsing the JSON body on a failed upgrade (none do)
- Ruling: X-Real-IP trusted only from loopback/private peers — why: exposed-port spoofing (Review Focus 4)
- Ruling: config adds HOST (default 0.0.0.0) and allows PORT=0 for tests
- Ruling: 500 frames/s budget kept per device in the registry (reconnect/hub drop can't refill); messages > 1 MiB close with 1009 (Cloudflare's limit)
- Ruling: reset-password drops --env, uses DB_PATH, refuses to create a DB, confirms unless --yes; no "unconfirmed" exit 2
- Ruling: backup container on the default network only; deploy/backup/ rsynced; backup through read-only mount logs a skip while the relay is stopped
- Ruling: four vhost.d files (relay + three web hosts, access_log off), copied not symlinked; runbook recreates ShellX containers after copying
- Ruling: privacy "deleted data may remain in backups ≤ 14 days"; backup retention line; "no CDN / no third-party analytics"
- Ruling: the [quốc gia] guard blocks the whole deploy (single job) — user informed
- Late plan edit (Task 6 Step 6: docker build --no-cache so test lines show) saved as scratchpad/plan-task6-nocache.patch; apply to the plan on this branch before Task 6's brief.
## Open items for the user (ask at deploy time)
- Privacy promises operational logs ≤ 30 days, but Docker rotates by size (10 MB × 3): change wording or add periodic recreation — user decision.
- nginx-proxy error logs may contain client IPs (only access logs are off).
- GHCR packages start private: user must make shellx-relay/shellx-web public (runbook) or the first pull fails.
- VPS CPU architecture: images built amd64; an arm64 VPS needs arm runners.
- VPS country ([quốc gia]); nginx-proxy network name.
Task 1: implemented commit 2a15f95 (66 tests; typecheck clean); review dispatched (sonnet)
Task 1: review (sonnet) spec ✅ Approved (verbatim; 0002 matches the DO table; exclude lists clean; real SQLITE_BUSY test; 66/66 re-run)
Task 1: complete (commits 437c12e..2a15f95, review clean)
Task 2: implementer a5d747fa5de84bbd6 (sonnet) dispatched, base 2a15f95
Task 2: implemented commit a17d84d (86 tests); review dispatched (sonnet)
Task 2: review (sonnet) spec ✅ (verbatim; KAT vectors; deterministic cap test; boundary-exact window; no timers; 86/86 re-run); 'Important' fe80::/10 not in TRUSTED_PEERS (plan-mandated)
Task 2: Ruling: waive fe80::/10 — Docker bridge traffic never arrives from link-local addresses; missing it only under-trusts (fail-safe, cannot be spoofed) — cost if wrong: a link-local proxy peer would be keyed by its own address (all users behind it share a bucket)
Task 2: minor (deferred): no test with 2+ simultaneous waiters proving FIFO release (code is FIFO by inspection)
Task 2: complete (commits 2a15f95..a17d84d, review clean)
Task 3: implementer a9657fec8eb4d88a8 (sonnet) dispatched, base a17d84d
Task 3: implemented commit 9167f67 (110 tests, 3 stable runs); review dispatched (opus — concurrency semantics)
Task 3: review (opus) spec ✅ Approved — byte-identical to brief; full parity table vs old DO (all same or stricter); queue/registry/handle concurrency verified; 110/110 re-run
Task 3: FOLD INTO FINAL FIX WAVE: (m1) tombstone upsert conflict path ignores user_id (user-hub.ts:158-161; add AND user_id = excluded.user_id); (m2) frame-budgets.ts has no unit test (sweep/IDLE_MS coupling); (m3) some hub test names claim same-tick races they don't exercise (:326/:339/:413/:408/:426); (m4) last_seen_write_failed logs no errorKind (:359-361); (m5) enqueue accepts async tasks (type-constrain or document)
Task 3: ⚠️ carry to Task 4 review: ping answered outside the queue; disconnected() on close AND error; socket closed when connect() rejects; ConnectionMeta UUID/kind validation now lives in the route
Task 3: complete (commits a17d84d..9167f67, review clean)
Task 4: implementer a9d509f052b828c88 (sonnet) dispatched, base 9167f67
Task 4: implemented commit dbce6d7 (239 tests, 3 stable runs); review dispatched (opus — protocol parity)
Task 4: review (opus) spec ❌ — parity exact (126→129 tests, removals justified); Important: (1) non-websocket Upgrade requests hang unanswered (fd exhaustion), (2) Review Focus 1 test never races, (3) 1011 close on rejected connect untested
Task 4: Ruling: (1) moves into Task 5 (Task 5 replaces relay.ts wholesale) with a raw net test; fix (2),(3) + minors (ws error kinds, 429 assertion, version status, content-length guard, 4003 reason) now — cost if wrong: none
Task 4: fix round 1/5 dispatched to a9d509f052b828c88 (FIX_BASE dbce6d7)
Task 4: fix round 1 commit 7776592 (240 tests; barrier proven by stripping it → maxPending 1; 1011 proven by removing the close → timeout); controller read the diff — addressed
Task 4: fix round 1/5 (6 addressed, 0 open; item 1 moved to Task 5; commits dbce6d7..7776592)
Task 4: complete (commits 9167f67..7776592, review clean)
Task 5: implementer dispatched (sonnet), base 7776592, carrying Task 4 item 1 (non-websocket Upgrade → 400 in the final relay.ts + raw net test)
Task 5: implemented commits c75d4aa b18274e (265 tests; e2e 7/7 against npm run dev; ruling fix in its own commit, red→green); review dispatched (sonnet)
Task 5: review (sonnet) spec ✅ Approved — shutdown order race-free (gated in-flight test), wrapper verified against @hono/node-server source (single listener), reset-password hardened (parameterised, fileMustExist); 265/265 + build re-run
Task 5: FOLD INTO FINAL FIX WAVE: (m1) server.ts stop() has no catch around relay.shutdown() under void; (m2) no test for a second SIGTERM mid-shutdown
Task 5: complete (commits 7776592..b18274e, review clean)
Plan: late Task 6 edit applied (9178921, docker build --no-cache)
Task 6: implementer aa0078dbf804f1ecc (sonnet) dispatched, base 9178921
Task 6: implemented commit c07bbe2 (relay image test stage 265/265, failing test blocks image; web image curl checks all match; guard blocks build); note: Docker Desktop was hung at start — implementer force-killed its processes (pkill) to recover, quit it at the end; review dispatched (sonnet)
Task 6: review (controller, 10 KB diff read in full): spec ✅ — Dockerfile test stage precedes build/runtime (image only after tests), runs as uid 1000, /data owned by node; web nginx: 3 server blocks, access_log/log_not_found off, relative redirects, download files-only with attachment/immutable headers; guard NFC-aware with 3 tests; implementer's evidence covers docker build/curl/guard both ways — Approved
Task 6: complete (commits 9178921..c07bbe2, review clean)
Task 7: implementer ad43e7c99012b4133 (sonnet) dispatched, base c07bbe2
Task 7: implemented commit 843eb95 (deploy tests 10/10; compose config validated; relay 265/265); Docker daemon stuck in 'starting' — Step 7 real-stack rollout/rollback rehearsal and busybox backup smoke NOT run (no force-kill this time)
Task 7: Ruling: carry the real-stack rehearsal (Step 7) + backup smoke to the final verification before any VPS deploy; needs a working Docker Desktop (ask the user to restart it if still stuck) — cost if wrong: an untested compose healthcheck/rollback path on first deploy (prototype had passed it)
Task 7: review dispatched (sonnet)
Task 7: review (sonnet) ❌ Critical: rollout.sh first 'compose up -d' unguarded under set -e → a hard failure (network/volume/daemon) exits without rollback, .env left on the bad tag (reproduced); minor: data/ ownership check after mkdir -p
Task 7: Ruling: fix both + tests (failing up → rollback + exit 1; both ups failing → diagnostic + old tag) — cost if wrong: none
Task 7: fix round 1/5 dispatched to ad43e7c99012b4133 (FIX_BASE 843eb95)
Task 7: fix round 1 commit 23fa1d2 (deploy tests 13/13; new tests red first 17≠1, 0≠1); controller read the rollout.sh diff — failing up → rollback branch, rollback up guarded, data/ checked before any mkdir — addressed
Task 7: fix round 1/5 (2 addressed, 0 open; commits 843eb95..23fa1d2)
Task 7: complete (commits c07bbe2..23fa1d2, review clean); real-stack rehearsal carried to final verification
Task 8: implementer a65c0b2bdfbd47795 (sonnet) dispatched, base 23fa1d2
Task 8: implemented commit f49e58a (YAML ok; no Cloudflare refs; secret names exact; release tests 27/27; nothing run end to end); review dispatched (opus — secrets/SSH/injection)
Task 9: implementer dispatched (sonnet), base f49e58a, in parallel with the Task 8 review (disjoint files: docs/spec, web pages, web README, HANDOFF). Rulings: HANDOFF line must say COPY (not symlink) the vhost.d files (plan Facts: symlinks dangle in the proxy container); relay test count 265 (not 263); add the open item 'log retention wording vs size-based rotation' to HANDOFF §4
Task 9: implemented commit 866ad1a (web build fails on 4 [quốc gia] hits as intended; web npm test 19 pass; docs check OK; rulings applied); review dispatched (sonnet)
Task 8: review (opus) — security sound (no ${{}} in run, strict host keys, scoped rsync, validated version/app dir); Important (plan-mandated): rollback doesn't restore relay.env/compose (bad relay.env → both releases dead), README first-release order impossible with web-served downloads; 8 minors
Task 8: Ruling: (b) stage to .incoming/ + swap with .prev/ restore in rollout.sh AND (a) runner preflight (compose config -q + relay loadConfig with relay.env); rewrite first-release order; fold minors incl. VPS_* secrets moved to environments production(main-only)+release — why: a deploy key with docker-group access is root-equivalent — cost if wrong: one extra environment to configure
Task 8: fix round 1/5 dispatched to a65c0b2bdfbd47795 (FIX_BASE 866ad1a — after Task 9's commit)
Task 9: review (sonnet) spec ✅ Approved — facts match real files; legal promises byte-identical; guard fires on exactly 4 pages; rulings applied; 265 re-run
Task 9: complete (commits f49e58a..866ad1a, review clean)
Task 8: fix round 1 commit cc3149d (deploy+release tests 44/44; 4 new swap/restore tests red first; extra: =~ pattern moved into a variable — bash 3.2 stripped backslashes); re-review dispatched (sonnet)
Task 8: re-review (sonnet) 9/9 ADDRESSED; path walk clean; residual: swap not crash-atomic (sub-ms window; inherent in ruling 1(b))
Task 8: FOLD INTO FINAL FIX WAVE: make stage_config crash-safe (build .prev.new then rename; or a marker) 
Task 8: fix round 1/5 (9 addressed, 0 open; commits 866ad1a..cc3149d)
Task 8: complete (commits 23fa1d2..cc3149d, review clean)
ALL 9 TASKS COMPLETE (head cc3149d). Next: final whole-branch review (opus).
FINAL: whole-branch review (opus) dispatched on 437c12e..cc3149d (package 557 KB); journeys: first deploy per runbook, relay.env change/bad, deploy with live clients, first desktop release, backup/restore
FINAL: review (opus) 'With fixes' — C1 unauthenticated RST after refused upgrade crashes the relay (reproduced); C2 backups stop after deploy 3 (backup container never recreated); I1 no backpressure (memory DoS); I2 restore fails for non-1000 deploy user; I3 proxy redirect blocks log IPs; I4 no image pruning; M1–M12
FINAL: Ruling: ONE fix wave split in two parallel implementers on disjoint files — Part A relay (C1+M4, I1 close slow receiver 1013/1011, M1, M8, M10 healthcheck script, M12, T2/T3/T5 folds) and Part B deploy/workflows/web/docs (C2, I2, I3 doc+user item, I4, M2, M3, M5, T8 crash-safe swap, M6, M7, M9, M10 wiring, M11, VPS_APP_DIR job-level env); interface: node dist/scripts/healthcheck.js exit 0/1 — cost if wrong: merge conflict (files disjoint)
FINAL: fix wave dispatched (A: opus, B: sonnet), FIX_BASE cc3149d
FINAL: Part B commits 4d52d24 7411097 e239f87 (deploy+release 51/51; YAML ok; relay/** untouched); concerns: M9 0600 test can't go red locally (macOS sqlite3 forces 0600), M7 as a copy/skip/warn branch, workflow logic untested beyond parse
FINAL: Part A commits 9f4e8b7 21e62d4 a3f195a 6ccf385 73eb7d6 738cf4e (relay 300/300 ×2; C1 repro crashed before, alive after; 1013 chosen — relay_connection.dart:436 reconnects on any code but 4001/4002, live dart:io run); beyond-ruling: 4 MiB cap on all hub sends; 429 mapping global (password/account routes too); failed shutdown exits 1; stop logic in src/stop.ts
FINAL: re-review (opus) — addressed: C1 C2 I2–I4 M1–M12 T2 T3 T5 T8; open: I1 pong path (~160 MB pinned at the 4 MiB cap, 30 s linger, reconnect loop); NEW Important: NB-1 stale .prev restored on code-only failure (+ backup inode), NB-2 dispatch fetch without credentials, NB-3 valid-token RST leaks adaptor waiter
FINAL: Ruling: residual follow-up (load-bearing): R1 pings in frame budget + no pong while buffered + terminate slow receiver after 1 s + terminate lingering socket on reconnect; R2 re-emit close for the adaptor + per-IP upgrade limiter 60/60 s; R3 swapped flag + recreate backup after restore; R4 delete the fetch line; R5 minors — cost if wrong: one more small review
FINAL: residual follow-up dispatched (opus), base 738cf4e
FINAL: residual commits d05fb64 6723b5c (relay 311/311 ×2; deploy+release 58/58; repros: ping flood heap 161→13 MB, slow receiver 30 s→1 s, lingering 20→2 sockets, adaptor waiter leak 1113→0, stale .prev fixed; backup recreated after any config change; backups chowned to backups/ owner)
FINAL: Ruling (controller, on concern 1): 'no pong while any bytes are buffered' is too strict — a slow but healthy streaming link would miss pongs and reconnect-loop; allow a pong while bufferedAmount ≤ 64 KiB (pings already count in the 500/s budget; pong payload ≤ 64 KiB bounds heap to a few MB); also note the upgrade limit + 1 s termination in v1 spec §5.2 limits line — cost if wrong: none
FINAL: residual round 2 sent to a7c3fead306b12c4d
FINAL: residual round 2 commit c1d5aa7 (pong allowed ≤ 64 KiB buffered; relay 312/312 ×2; worst-case stuck pinging phone +2.8 MB heap; specs updated incl. pings in the 500/s budget); residual review dispatched (opus)
FINAL: residual review (opus): R1–R5 + pong ruling ADDRESSED; relay 312/312, deploy 58/58, repros reproduced; Ready to merge (local): yes
FINAL: minor (deferred): spurious recreate warning on first-deploy pull failure (IMAGE_TAG interpolation); fresh-VPS failed first deploy → backup restart-loops until next deploy; no backup recreate when the rollback up itself fails; specs omit the 64 KiB pong rule (v1 :193, VPS :99); two doc inaccuracies (crash-before-swapped header, README :225)
FINAL: PRE-DEPLOY (Important, pre-existing): heap amplification via ERROR/small DATA up to the 4 MiB cap (~57 MB per stuck device; no per-account device cap) — track before the first public deploy (HANDOFF §4)
FINAL: Needs Docker/VPS: image builds; real rollout/rollback rehearsal (Task 7 Step 7); busybox ls/awk/chown in alpine on backups/; real --force-recreate backup rebinding; workflow_dispatch origin/main on a private repo; release chmod; X-Real-IP + 429 behind real nginx-proxy; pong ≤ 64 KiB over a slow link; R2 reclaim timing on Linux; nginx-proxy port-80 logging (I3); acme-companion append (M7); amd64 vs arm64
FINAL: plan complete — merging feat/shellx-vps into feat/shellx-v1
POST-MERGE: PRE-DEPLOY memory item CLOSED by `fix/relay-memory-bounds` (commits b82013a 71c9469 + fix round 1): 1024 queued sends per socket → 1013; pong only at ≤ 64 sends and ≤ 64 KiB; 16 live devices per account (17th → 1013 "too many devices online"); control PINGs not auto-answered (autoPong false); every hub close (1013/4001/4002/4003) dropped after 1 s, ws closeTimeout 2 s; connect snapshot exempt from the send check; relay mem_limit + memswap_limit 512m. Probes (from the reviews, not in the repo): ERROR +56.5 → +0.9 MB, small DATA +58.7 → +0.8 MB, 300k control PINGs +58.9 → +0.3 MB, 4003 linger +3.5 MB for ~30 s → freed within 1.5 s, 1100 tombstones 1013 → delivered. Deferred: M4 (a skipped pong is not answered later) → VPS check "pong over a slow link"; Docker check: `docker inspect` Memory/MemorySwap = 536870912 536870912

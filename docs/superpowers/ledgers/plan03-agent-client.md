# SDD ledger — plan: docs/superpowers/plans/2026-09-25-shellx-v1-03-agent-client.md

Worktree: /Users/lehuuphu/Documents/myProjects/shellx/.worktrees/agent-client (branch feat/shellx-v1-agent-client = feat/shellx-v1 @ cf04828 + merge of in-progress feat/shellx-v1-core @ b38ff2d → ac81aae)
Spec: docs/superpowers/specs/2026-09-25-shellx-v1-design.md ; Overview: docs/superpowers/plans/2026-09-25-shellx-v1-00-overview.md

## Pre-flight scan

Evidence: plan author compiled/tested every block in a scratch workspace against a STUB shellx_core (real CBOR + X25519, simplified Noise) — agent 96, client 42, e2e 5 (scratch relay); replay of the plan into an empty tree reproduced sources byte-for-byte. NOT yet run against the real core (plan 02) or the real relay (plan 01).

| Tasks | Shared file / interface | Producer → consumer | Finding |
|---|---|---|---|
| 1,10,15 | root pubspec.yaml workspace list | each adds one line | OK |
| 1 → 2,4 | Pty/PtyFactory/ShellCommand | OK |
| 3 → 4 | RingBuffer | OK |
| 4,6 → 12 | test/support/{fake_pty,drive,fake_relay}.dart copied byte-for-byte into shellx_client | Note: never edit copies |
| 5 → 8,9 | TrustedStore, PairingCodeManager | OK |
| 7,8 → 9 | AgentChannel, HandshakeResponder (internal) | OK |
| 9 → 12,14,15 | AgentService, AgentRevoked | OK |
| 10 → 11,12,13,14 | client types, PinnedStore | OK |
| all | consume shellx_core via overview §5.1–5.5 | RISK: verified vs stub core — real core differences (NoiseHandshake.split one-shot; remoteStatic null until msg1 authenticates; RelayConnection being hardened in core Task 11 fix round: serialized connects) may need small adaptations |

Rulings:
- Ruling: start plan 03 before core plan finishes (tasks 1–5 depend only on finished core tasks 1–9); merge final core into this branch before Task 6 (fake relay harness uses RelayConnection) — cost if wrong: a re-merge.
- Ruling: implementers adapt minimally to real-core API differences and report each adaptation; they must not change shellx_core — cost if wrong: plan text drifts from code.
- Ruling: plan text "spec §5.2: Agent nhận 4002 thì xử lý như đăng xuất" is outdated; spec now says keep key + trust list; plan 03 only emits AgentRevoked, so no code impact.

Model plan: haiku for 1,2,3,5,10 (full code, small); sonnet for 4,6,7,8,9,11,12,13,14,15; opus reviews for 8, 9, 12, 14 (security/concurrency); final review opus.

## Progress
Task 1: implementer a2157e11088005908 (haiku) dispatched, base ac81aae
Task 1: implemented commit 30fea8b; review dispatched (sonnet)
Task 1: review spec ✅; 1 Important (plan-mandated): macOS user only from USER/LOGNAME, no `id -un` fallback.
Task 1: Ruling: add `id -un` fallback via injected runner and fall back to /bin/zsh -l when UserShell path doesn't exist (injectable fileExists) — cheap robustness for GUI-launched agents — cost if wrong: none.
Task 1: minor (deferred): Windows PATH lookup doesn't follow PATHEXT/quoted entries
Task 1: fix round 1/5 dispatched to a2157e11088005908 (FIX_BASE 30fea8b)
Task 1: fix round 1/5 (3 addressed, 0 open — id -un fallback, missing-shell fallback, tests; commits 30fea8b..4b333a0)
Task 1: complete (commits ac81aae..4b333a0, review clean)
Task 2: implementer a0b21b9706876ddb1 (haiku) dispatched, base 4b333a0
Task 2: implemented commit 1c18fca; review dispatched (sonnet)
Task 2: minor (deferred): _pendingWrites unbounded after spawn failure (plan-mandated)
Task 2: minor (deferred): non-TTY: backgrounded grandchild holding pipes can keep output open (E2E-only factory)
Task 2: complete (commits 4b333a0..1c18fca, review clean)
Task 3: implementer a125c323a2e901eff (haiku) dispatched, base 1c18fca
Task 3: implemented commit c4ca5c1; review dispatched (sonnet)
Task 3: minor (deferred): negative capacity throws RangeError from Uint8List before the guard (plan-mandated)
Task 3: minor (deferred): no explicit aliasing test (read result unaffected by later append); check-order quirk
Task 3: complete (commits 1c18fca..c4ca5c1, review clean)
Task 4: implementer a7c308ec20f26e330 (sonnet) dispatched, base c4ca5c1
Task 4: implemented commit 1c73555 (no real-core adaptations); review dispatched (opus)
Task 4: review (opus) spec ✅; invariants hold (window, attached-only input). 2 Important (plan-mandated): output tail lost at exit with full window; ack-clamp test non-discriminating.
Task 4: Ruling: fix both + fold in minors (closeAll/revoke racing pending open leaks a shell; tray-close + attach during grace; advance `sent` before emit + document no sync re-entry). Drain policy: while attached, keep pumping after exit until acked==end, detach/disconnect, or 30 s timeout — cost if wrong: exited message delayed up to 30 s on a stalled phone.
Task 4: minor (deferred): reset forgives in-flight bytes → real in-flight < 2× window
Task 4: minor (deferred): session.close from non-attached phone gets no reply (plan allows)
Task 4: minor (deferred): PTY output errors swallowed silently; no dispose(); untested exit-before-output-done & 2 s grace paths (FakePty closes both together)
Task 4: ⚠️ carry to plan 04: FlutterPtyAdapter.kill() must terminate the whole tree or tray-closed sessions linger
Task 4: fix round 1/5 dispatched to a7c308ec20f26e330 (FIX_BASE 1c73555)
Task 4: fix round 1 commit 1fdf2ec; Ruling: my item1/item4 wording conflicted — accept implementer's unification (closing sessions stay internal for draining, hidden from list/attach); closing sessions still count toward the 10-session cap for ≤30 s — cost if wrong: a user hitting the cap briefly after closing sessions. Re-review dispatched (opus)
Task 4: fix round 1/5 (5 addressed, 0 open; commits 1c73555..1fdf2ec)
Task 4: minor (deferred → FOLD INTO FINAL FIX WAVE): N1 draining session still accepts input/resize (skip closing sessions for input/resize, keep ack routing)
Task 4: minor (deferred → FOLD INTO FINAL FIX WAVE): N2 global epoch bump in closeSessionsAttachedTo kills other phones' pending opens (use per-mobile epoch; keep global for closeAll) — regression from the round-1 ruling
Task 4: minor (deferred → FOLD INTO FINAL FIX WAVE): N3 detach-path drain test vacuous (assert pendingTimers empty after mobileDisconnected); N4 30 s timeout not pinned (elapse 29 s assert no exited)
Task 4: minor (deferred): N5 draining session counts against the limit/holds index; N6 tray `changes` not fired when a session starts draining; doc "tolerates" overstatement; pre-existing: reset forgives in-flight bytes; mobileDisconnected doesn't invalidate that phone's pending open
Task 4: complete (commits c4ca5c1..1fdf2ec, review clean)
Task 5: implementer a81553bc9a62e6dbd (haiku) dispatched, base 1fdf2ec
Task 5: implemented commit 8394c90; review dispatched (sonnet)
Task 5: review spec ✅; Important (plan-mandated): pairing secret returned by reference (aliases live state).
Task 5: Ruling: copy secrets in/out; validate trusted public key length (skip corrupt entries); document one shared TrustedStore instance — cost if wrong: none.
Task 5: fix round 1/5 dispatched to a81553bc9a62e6dbd (FIX_BASE 8394c90)
Task 5: fix round 1/5 (3 addressed, 0 open — secret copies; key-length validation + skip corrupt entries; shared-instance doc; commits 8394c90..7ecd651)
Task 5: Ruling: accept TrustedDevice constructor no longer `const` (needed to copy publicKey); overview §5.6 updated — cost if wrong: callers can't use const TrustedDevice (none do).
Task 5: complete (commits 1fdf2ec..7ecd651, review clean)
Task 6: implementer af0dfdb431eca53c0 (sonnet) dispatched, base 5ca2597 (real core RelayConnection merged)
Task 6: implemented commit 57658b7 (no real-core adaptations); review dispatched (sonnet) incl. fake-vs-real relay divergence check
Task 6: review spec ✅ (verbatim); fake-vs-real divergence check found: (Critical) presence offline/online flicker on same-device replace; (Important) pairing_removed only to the other party, not persisted/replayed for an offline agent; (Important) no pre-upgrade 401 path (StateError instead of WebSocketException 401).
Task 6: Ruling: make FakeRelay match the real relay on these + frame_too_large peer/channel — later integration tests must not pass on behaviour the real relay doesn't have — cost if wrong: none.
Task 6: minor (deferred): no rate limiting, devices list without sign-out concept, non-ping text silently ignored, no password/account routes (out of harness scope)
Task 6: fix round 1/5 dispatched to af0dfdb431eca53c0 (FIX_BASE 57658b7)
Task 6: fix round 1 commit 1cc10c6 (13 harness tests, 84 package); re-review dispatched (sonnet)
PAUSED 2026-09-25 (user request): Task 6 fix round 1 is COMMITTED (1cc10c6); its scoped re-review was stopped before reporting. On resume: re-run the scoped re-review of c29cbdd..1cc10c6 (findings: presence on replace, durable pairing_removed, 401 revoke, frame_too_large peer/channel), then continue with Task 7.
RESUMED 2026-09-25: Task 6 fix round 1 scoped re-review re-dispatched aada4062395d1cdb1 (sonnet), diff c29cbdd..1cc10c6
Task 6: fix round 1/5 (4 addressed, 0 open — presence on replace; durable deduped pairing_removed; 401 revoke; frame_too_large peer/channel; commits c29cbdd..1cc10c6)
Task 6: minor (deferred): _onClientFrame decodes before size check; a non-FormatException from oversized EVENT CBOR could escape (harness only sends DATA)
Task 6: minor (deferred): fake lacks the real relay's post-upgrade token re-check (TOCTOU) path; httpClient builds a new MockClient per access
Task 6: complete (commits 5ca2597..1cc10c6, review clean)
Task 7: implementer adcce0c766d888dc4 (sonnet) dispatched, base 1cc10c6
Task 7: implemented commit c82e82f (7/7, suite 91/91); concern: SecureChannel built outside fakeAsync hangs (NoiseTransport Future queues) — test fixture moved inside fakeAsync via drive(); review dispatched (sonnet)
Task 7: ⚠️ carry to Tasks 9, 11–14: build SecureChannel/Noise pairs INSIDE the fakeAsync zone (drive(async, …)), never in setUp()
Task 7: review (sonnet) spec ✅ Approved; Important (plan-mandated): flush() silently drops a batch when seal throws or send() returns false (channel keeps going with a gap)
Task 7: Ruling: fix now — on a seal error or send()==false the channel marks itself failed, stops sending (like close) and calls an optional onFailure callback exactly once; Task 9 wires it to drop the channel (phone re-handshakes and re-attaches from last_seq, the ring buffer covers the gap) — a silent gap corrupts the terminal stream — cost if wrong: one extra optional constructor param
Task 7: minor (deferred): splitIntoBatches relies on each message ≤ kMaxSealedBatchBytes (kMaxOutputChunk upstream) without an assert; timer-cancel repeated 3×; header allowance always 3
Task 7: fix round 1/5 dispatched to adcce0c766d888dc4 (FIX_BASE c82e82f)
Cross-plan (from desktop Task 3 review): SessionManager.closeSession sets closing=true before pty.kill() and returns early when already closing — if a kill fails the session stays 'closing' with no retry; SessionClose during the 30 s drain calls kill() on an exited pty. Desktop now signals the root even when ps fails; consider in the plan 03 final review.
Task 7: fix round 1 commit 68016e3 (10/10, suite 94/94; onFailure + _fail; 3 covering tests incl. in-flight close); re-review dispatched (sonnet)
Task 7: fix round 1/5 (1 addressed, 0 open — onFailure + fail-stop on seal error / send false; commits c82e82f..68016e3)
Task 7: minor (deferred): a throwing onFailure callback could surface as an unhandled Future error on the last batch (Task 9 owns the callback)
Task 7: complete (commits 1cc10c6..68016e3, review clean)
Task 8: implementer a0715fee0b655f989 (sonnet) dispatched, base 68016e3
Task 8: implemented commit 7a8c63b (11 new, suite 105; real API matched, brief verbatim); review dispatched (opus — security-critical)
Task 8: review (opus) spec ✅ Approved; security answers all sound (trust bound to peer id + key, prologue binds relay peer id, no aliasing, no logging)
Task 8: minor (deferred → FOLD INTO FINAL FIX WAVE): HandshakeAnswer doc overstates IKpsk2 ok (only 'a code was active'; proof is a decrypted pair.confirm); exceptions from buildPrologue/find escape answer() (fail closed) — wrap → null; test gaps: decryptable HS1 with malformed payload, IKpsk2 + proto 2, expired code → pairing_invalid
Task 8: minor (deferred): HS2 length/timing reveals whether a pairing code is active (inherent to spec statuses); future HS1 that fails v1 decoding gets silence instead of proto_unsupported
Task 8: ⚠️ carry to Task 9: revoke() must be serialized through _inbox or trust re-checked before installing a channel (revoke race); consume the pairing code only at a decrypted pair.confirm after a constant-time re-check of activeSecret; treat an exception from answer() as null; wire AgentChannel.onFailure (Task 7 ruling)
Task 8: complete (commits 68016e3..7a8c63b, review clean)
Task 9: implementer af1aae22027a5904f (opus — integration heart + carried rulings: onFailure wiring, pair.confirm code consumption, answer() exceptions → null, revoke serialized through inbox, duplicate pairing_removed no-op), base 7a8c63b
⚠️ Cross-plan (relay final fix I1, 2026-09-26): real relay now keeps pairing_removed as TOMBSTONES — replayed on EVERY agent connect after the snapshot, cleared only by POST /v1/pairings for that pair, agent logout, or account deletion (no longer removed once delivered). FakeRelay must be updated to match after Task 9 lands (small follow-up commit + re-review); agent handling must be idempotent (Task 9 told).
Task 9: implemented commits 746b7fc (brief) a48bc41 (rulings 2–5 + 11 tests); 132/132 ×3; concerns: (1) tombstone replay + fire-and-forget POST /v1/pairings → a failed POST after re-pair loses the new trust on next reconnect; (2) revoke kills only attached sessions; (3) peer_offline path untested (FakeRelay can't inject ERROR); (4) duplicate pairing_removed rewrites trust store
Task 9: Ruling: (1) agent keeps a persisted set of 'unregistered pairings' (trusted locally, POST /v1/pairings not yet acknowledged); while a mobile is in it, pairing_removed for that mobile is ignored; POST is retried after every relay connect and with backoff until 2xx (a 4xx other than 401/429 drops the entry — the relay refused the pairing); on success the entry is removed (relay clears the tombstone on POST) — only local fix that survives the replay race; clock-based or relay-side alternatives are unsound — cost if wrong: a phone unpaired while its POST was pending stays trusted until revoked from the tray
Task 9: Ruling: (2) no change — spec §5.5 says revoke closes the channels and sessions attached to that phone; unattached sessions are not owned by a phone and the revoked phone can no longer attach — cost if wrong: user expectation mismatch, revisit in v1.1
Task 9: Ruling: (3)+(cross-plan) update FakeRelay now to match the real relay: pairing_removed tombstones replayed on every agent connect until POST /v1/pairings (or agent logout) clears them; add an ERROR-injection hook so the peer_offline path gets a test — cost if wrong: none
Task 9: minor (deferred): duplicate pairing_removed rewrites the trust store (harmless; skip write when absent)
Task 9: pre-review fix dispatched to af1aae22027a5904f (FIX_BASE a48bc41)
Task 9: pre-review fix commits 890b08a 68c77e5 (144/144 ×3; pending_pairing_posts + ignore rule + retry/backoff + DELETE-after-revoke; FakeRelay tombstones + sendError hook); concerns: TrustedStore gained members (overview §5.6 to update); phone unpairing before POST lands stays trusted (ruled); tiny tombstone-delay window; review dispatched (opus) over 7a8c63b..68c77e5
Task 9: review (opus) spec ✅ (all 7 rulings verified; inbox/lifecycle traced clean) but Needs fixes — Important (ruling-mandated): an unpair made while a pairing is pending can be lost for good (POST#1 commits, response lost → phone unpairs → ignored → POST#2 clears the tombstone and re-creates the row → stale trust forever); report claim at task-9-report.md:207 is false. Minors: markRegistered not tied to a specific pairing (stale 2xx / DELETE after quick re-pair); mark without trust entry still POSTed; _onHello ignores relay.send result; registration Backoff not injectable; overview §5.6 TrustedStore out of date
Task 9: Ruling: replace the 'ignore while pending' design with agent-generated PAIRING IDS across relay + core + agent: rows and tombstones carry pairing_id; POST {mobile_id,pairing_id} → 410 pairing_removed if a same-id tombstone exists, else clears older-id tombstones + upserts; agent DELETE ?pairing_id= deletes only the matching row; event carries pairing_id; agent removes trust only when ids match, drops trust on 410 — removes all ordering ambiguity without clocks; nothing deployed so 0001_init.sql is edited in place — cost if wrong: one more contract field across three packages
Task 9: contract change runs in .worktrees/pairing-id (branch feat/shellx-v1-pairing-id from feat/shellx-v1); then merge feat/shellx-v1 into this branch and run Task 9 fix round 1 (agent side + FakeRelay + minors 1–4); Task 10+ may proceed meanwhile (client scaffold does not touch agent_service)
Task 9: OPEN — fix round 1 pending the contract change (not complete)
Task 9: parked pending contract change — Ruling: Task 10–12 (client side) proceed now; they do not build on agent pairing internals — cost if wrong: none
Task 10: implementer a7ad5c25be6ba4699 (sonnet) dispatched, base 68c77e5
Task 10: implemented commit 334b6de (client 4/4, agent 144/144); review dispatched (sonnet)
Task 10: review (sonnet) spec ✅ Approved
Task 10: minor (deferred): PinnedMachine keeps the caller's publicKey buffer by reference (brief code; persisted via toJson immediately)
Task 10: complete (commits 68c77e5..334b6de, review clean)
Task 11: implementer a2f8671caa71d42c3 (sonnet) dispatched, base 334b6de
Task 11: implemented commit 3387ea8 (client 11/11); review dispatched (sonnet)
Task 11: review (sonnet) spec ✅ Approved (seq/ack semantics cross-checked with SessionManager)
Task 11: minor (deferred): beginAttach doesn't cancel a pending ack timer (no-op when it fires); backlog replays to the first listener only (by design)
Task 11: complete (commits 334b6de..3387ea8, review clean)
Task 12: implementer a5896829cf9216f44 (opus) dispatched, base 3387ea8
Task 9 (pairing-id contract, branch feat/shellx-v1-pairing-id): commits 22e01bf 0e6195f 0c0c9d6 (relay 229 ×2, core 255). Rulings: POST fails closed on hub outage (500; agent retries) — accepted; extra race guards accepted; residual accepted — a phone unpair before the agent's first POST commits leaves stale trust (documented; tray can revoke) — cost if wrong: stale trust in a sub-second window; Ruling: pairing ids are UUIDv7 generated by the agent and the relay refuses a POST whose id is not newer than the tombstone (410) — fixes a stale old-id retry clearing a newer tombstone — cost if wrong: an agent clock stepping backwards makes a re-pair fail closed (user pairs again). Follow-up dispatched to ac6d3df9e19457e26 before review. Carry to Task 9 fix round: generate lower-case UUIDv7 ids; pending set tied to the id (replace on re-pair, drop on revoke); 410 → drop trust only if the trusted entry has that id
Pairing-id follow-up: commits 5554b42 ef5f95e (relay 233 ×2, core 255). Ruling: accept implementer additions — DELETE ?pairing_id must be v7; POST never replaces a row with a newer id (stale POST → 410); tombstone keeps the newest id; clock-backwards → 410 until the clock passes (fail closed, logout clears) — each closes a stale-trust path — cost if wrong: a re-pair refused after a clock step back. Whole-change review dispatched (opus) ce08bdb..ef5f95e
Task 12: implemented commit b416dbb (client 31/31 ×3, agent 144/144); beyond brief: concurrent attach of the same session; relay/agent loss during handshake fails connect at once; wrong-length pin → untrusted + forgotten; seal/send failure drops channel; carry to Task 13: harness must record the pairing on the fake relay (unpair/revoke tests); review dispatched (opus)
Pairing-id whole review (opus): ready to merge with doc fixes; 24 interleavings checked, only the documented residual + a rare clock-regression edge remain. Rulings: 410 drops trust only for the exact id + retry only the current id (agent requirement); relay refuses (410) UUIDv7 ids >24 h ahead of relay time (forward clock jump) — cost if wrong: a pairing refused on a machine with a clock >24 h fast; reject non-lower-case pairing_id with 400 — cost if wrong: none; document DELETE 500s + caller retry. Final fix pass sent to ac6d3df9e19457e26. Declined items for plan 03/05: phone cannot match pairing_removed by id (forgets its pin on any event for the agent); revoke with id and no row writes no tombstone (plan 03 may re-send DELETE on a 201 for a revoked id)
Task 12: review (opus) spec ✅; four deviations accepted as improvements; Important (plan-mandated): ClientService.start() not re-entrant — overlapping starts double-subscribe relay.frames and kill every channel (verified); stop() during start leaves it started — plan 05 maps resume/suspend to start/stop
Task 12: Ruling: fix the Important now, and fold in M2 (guard decrypt-failure _channelLost with identical(secure,_secure)), M3 (capture _losses at the top of _handshakeNow), M4 (unexpected exceptions in _handshakeNow must not leave MachineConnecting — build prologue before _setState + catch-all → _fail(timeout)) and M5 test gaps (assert no session.attach for unknown id, no session.close for a detached tab) — M3/M4 are load-bearing for Task 14's resume — cost if wrong: none
Task 12: minor (deferred): FIFO reply matching attributes a late reply to the next request; _known never pruned; plan test-count drift (+6) for Tasks 13/14
Task 12: fix round 1/5 dispatched to a5896829cf9216f44 (FIX_BASE b416dbb)
Pairing-id: final fixes re-review clean → merged into feat/shellx-v1 (54705aa; record docs/superpowers/ledgers/pairing-id.md). NEXT here after Task 12's fix round: merge feat/shellx-v1 into this branch (relay + pairing ids + doc fixes), then Task 9 fix round 1 per task-9-fix1-findings.md
Task 12: fix round 1 commit 77d9fa9 (client 39/39 ×3, agent 144/144; 5 items, each RED first); carry: Task 13 replaces client_service.dart wholesale — must keep the new start/stop code; Task 14 edit 3 anchor → if (identical(secure,_secure)) { _channelLost(); unawaited(_resume()); }; re-review dispatched (sonnet)
Task 12: fix round 1/5 (5 addressed, 0 open — re-entrant start/stop; guarded stale decrypt failure; losses captured early; no stuck MachineConnecting; relay-level no-send tests; commits b416dbb..77d9fa9)
Task 12: minor (deferred): catch-all in _handshakeNow maps Errors (bugs) to timeout too (debuggability)
Task 12: complete (commits 3387ea8..77d9fa9, review clean)
Merged feat/shellx-v1 into plan 03 (f0777c5): relay + pairing ids + docs. Expected: shellx_agent no longer compiles against the new createPairing(…, pairingId:) until Task 9 fix round 1 lands (7 analyzer errors)
Task 9: fix round 1/5 dispatched to af1aae22027a5904f (FIX_BASE f0777c5) with task-9-fix1-findings.md
Task 9: fix round 1 commits 391cc00 91f7fe7 8550db8 (agent 160/160 ×3, client 39/39; registration mark stored inside the trust entry; all matches by pairing id); Ruling: revoke's DELETE tried once, errors ignored — accept for v1: the agent's trust list is authoritative, a stale relay row only affects display and the phone gets 'untrusted' on its next handshake — cost if wrong: phone shows the machine as paired until it next connects; scoped re-review dispatched (opus)
Task 9: fix round 1/5 (I1, M1–M5, rulings 1–8 all addressed, 0 open; commits f0777c5..8550db8)
Task 9: minor (deferred → FOLD INTO FINAL FIX WAVE): persist the pairing-id generator's high-water mark (clock regression across restart → re-pair 410); a clock >24 h ahead pins _lastMillis ahead until restart
Task 9: minor (deferred): old-id POST ending in retry after a re-pair delays the new id's POST by one backoff; dead 'pending_pairing_posts' key on dev installs
Task 9: ⚠️ carry to Task 13 (phone side): the phone can receive pairing_removed with an OLD pairing id (agent take-back DELETE / revoke DELETE racing a re-pair); the phone does not know ids — Ruling: the phone must NOT delete its pin on pairing_removed; treat it as 'verify': mark the machine for re-check, and forget the pin only when an IK handshake returns untrusted (spec §12 flow, 'Máy không còn tin cậy điện thoại này. Hãy ghép nối lại.'); if the agent is offline, verify on the next connect attempt — cost if wrong: a revoked phone keeps listing the machine until it next tries to connect
Task 9: complete (commits 7a8c63b..8550db8, review clean after pre-review fix + fix round 1)
Task 13: Ruling: merge the brief's new ClientService members into the current file (keep Task 12's re-entrant start/stop) instead of the brief's wholesale replacement — cost if wrong: none
Task 13: Ruling: unpair retries the id-less DELETE up to 3× on 5xx/network before propagating (contract: callers must retry DELETE 500) — cost if wrong: a slower error on a dead relay
Task 13: implementer a74c1b96a06a3c56c (opus) dispatched, base 8550db8
Task 13: implemented commit 368b974 (client 66/66 ×3, agent 160/160); beyond brief: re-pair of a connected machine drops the old channel; agent offline during pairing → agentOffline at once; ⚠️ carry to Task 14: auto-resume should also run after a pairing_removed/re-pair channel drop; review dispatched (opus)
Task 13: review (opus) spec ✅ Approved — trust invariants hold (pin from QR only after ok + pair.confirm sent; relay cannot add or silently remove trust)
Task 13: ⚠️ carry to Task 14: dropChannel() during an in-flight IK handshake is a no-op → a just-dropped channel can be installed (liveness) — mark stale/bump _losses so it is dropped right after install; pairing timeout/late-HS2 path should drop the machine channel once HS1 was sent; auto-resume should also run after a pairing_removed/re-pair channel drop
Task 13: minor (deferred → FOLD INTO FINAL FIX WAVE): test that the phone's unpair DELETE carries no pairing_id (capture query via phoneHttpFault)
Task 13: minor (deferred): dead 32-byte length check (PairingUri enforces it); pairedAt clock not injectable
Task 13: complete (commits 8550db8..368b974, review clean)
Task 14: implementer a4aef1f81bb22d97d (opus) dispatched, base 368b974 (rulings: apply edits to current code; resume also after pairing_removed/re-pair drop; in-flight-handshake drop + pair() finally-drop liveness fixes)
Task 14: implemented commits 8a690ec ce9e368 (client 83/83 ×3, agent 160/160); beyond brief: trigger mid-resume reruns once; resume joins an app-started handshake; PRESENCE online drops a live channel; pair() drops the channel in finally after pair.confirm; concern: an automatic IK handshake inside a pairing's HS1→confirm window replaces the pairing channel → agent ignores pair.confirm while the phone pins
Task 14: Ruling: fix before review — while ClientService.pair(agentId) is in flight, MachineClient for that agent must not start an automatic (or app-requested) IK handshake; defer it until pair() finishes (then resume once) — a 'paired' success the agent never recorded is a user-visible broken pairing — cost if wrong: resume delayed by one pairing round-trip
Task 14: pre-review fix sent to a4aef1f81bb22d97d
Task 14: pre-review fix commit c90a351 (client 85/85 ×3; per-agent pairing gate for every IK handshake; deferred resume once after pair()); review dispatched (opus) over 368b974..c90a351
Task 14: review (opus) spec ✅ (gate deadlock-free; triggers coalesce; no storms) but Needs fixes — Important (plan-mandated): a re-attach timing out (MachineConnectionException) escapes the per-tab loop → remaining isAttached tabs never re-attached and frozen while MachineReady
Task 14: Ruling: fix + fold in — per-tab MachineConnectionException: continue unless the channel is gone; track 'attached on the current channel' and resume stale tabs whenever a channel is installed (closes failed-resume gaps incl. app-initiated connect); wait at the gate at the top of the handshake (or re-read the pin + check losses after the wait); on 'untrusted' end the machine's tabs (TabError) so later triggers don't redo _fail — cost if wrong: none
Task 14: minor (deferred → v1.1 hardening): no backoff on repeated decrypt errors (relay corrupting frames → re-handshake loop paced by round trips)
Task 14: fix round 1/5 dispatched to a4aef1f81bb22d97d (FIX_BASE c90a351)
Task 14: fix round 1 commit 24fd0b4 (client 89/89 ×3); note for plan 05: on untrusted the client ends tabs with TabError(sessionNotFound) (core has no untrusted code) — the mobile UI must show the machine-level untrusted text, not a per-tab 'session not found'; scoped re-review dispatched (sonnet)
Task 14: fix round 1/5 (1 Important + 3 folds addressed, 0 open; commits c90a351..24fd0b4)
Task 14: minor (deferred): an existing tab's failed public attach() doesn't remove it from _attachedHere (harmless: isAttached gates staleness); the no-pin early return in _resumeOnce is unobservable
Task 14: complete (commits 368b974..24fd0b4, review clean)
Task 15: implementer a7c83c7052643a299 (opus) dispatched, base 24fd0b4 (local relay via wrangler dev; + scenarios: re-pair survives tombstone replay; revoke → untrusted)
Task 15: implemented commit 716f3ed (e2e 7/7 × 15 runs vs local relay; agent 160, client 89; mutation checks); adaptations: async waitUntil, agent relay/connector exposed, http wrapper to hold POST /v1/pairings, scenarios wait for the relay row; review dispatched (sonnet)
Task 15: review (sonnet) spec ✅ Approved (genuinely end-to-end; CI e2e job already matches)
Task 15: complete (commits 24fd0b4..716f3ed, review clean)
FINAL: whole-branch review dispatched (opus), range fb76b5f7c78bac45914e7f51eec48e4f9b75a9a5..716f3ed
FINAL: review (opus) 'With fixes' — Important: I1 kill/write/resize after the shell exited (PID reuse → Windows taskkill could hit an unrelated tree; absorbs N1); I2 closeTab with no channel leaves the session running forever; minors M1–M7; triage: N1, N3/N4, T8 fix-before-merge, everything else stays deferred (T9 high-water mark, T14 decrypt backoff v1.1)
FINAL: Ruling: fix wave = I1 + I2 + M1 (close unmatched session.opened) + M2 (retry revoke DELETE) + M3 (per-message isolation) + M4 (hold input for stale tabs) + M5 + M7 + N3/N4/T8 tests + N2 doc (findings in final-fix-findings.md) — each cheap and user-visible or safety-relevant — cost if wrong: diff churn
FINAL: note for plan 05: unpair forgets the pin before a DELETE that may fail (M6) — the UI should surface the error with a retry
FINAL: fix wave dispatched ad74ef8fe63f40d66 (opus), FIX_BASE 716f3ed
FINAL: fix wave commits 716f3ed..9096444 (agent 167 ×3, client 96 ×3, e2e 7/7 local relay); Ruling: accept M1 extension (timed-out opens/lists keep their queue place + session.list on timeout; no wire change) and I2's handshake on close-without-channel; Ruling: M4 exceeded the ruling (offline input buffered and executed after reconnect — unsafe) → narrowed to the re-attach window only, sent back to the same implementer within the wave — cost if wrong: none
FINAL: ⚠️ carry to desktop fix wave: FlutterPtyAdapter.kill must no-op once the shell exited (updated §5.6 Pty contract)
FINAL: M4 correction commit b87c974 (client 98 ×3, agent 167 ×3, e2e 7/7); scoped re-review of the whole wave dispatched (opus) 716f3ed..b87c974
FINAL: re-review (opus) — all addressed, ready to merge (agent 167, client 98 re-run)
FINAL: parked — M3 per-message catch has no debug log (packages have no logging at all; same as before) — Ruling: accept for v1 — cost if wrong: harder debugging of a failing handle
FINAL: parked — a close queued offline can kill a session another device took over during the outage (phone's stale tab treated as authoritative, consistent with resume) — Ruling: accept — cost if wrong: a rare surprise close on the other device
FINAL: parked — pending closes lost if the first send on the new channel fails (narrow) — Ruling: accept for v1 — cost if wrong: an orphan session until closed from the tray
FINAL: parked (out of scope, existing) — open reply lost with a channel drop leaves an unattached session (listable, counts toward the cap)
FINAL: complete — merging feat/shellx-v1-agent-client into feat/shellx-v1 (local, no push)

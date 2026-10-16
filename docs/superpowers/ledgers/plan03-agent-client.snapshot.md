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

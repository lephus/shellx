# SDD ledger — plan: docs/superpowers/plans/2026-09-25-shellx-v1-02-core.md

Worktree: /Users/lehuuphu/Documents/myProjects/shellx/.worktrees/core (branch feat/shellx-v1-core, from feat/shellx-v1 @ e4cb760)
Spec: docs/superpowers/specs/2026-09-25-shellx-v1-design.md ; Overview/contracts: docs/superpowers/plans/2026-09-25-shellx-v1-00-overview.md

## Pre-flight scan

Evidence: the plan author rebuilt the package from the plan text alone in a fresh repo (scratchpad/plan02/ws, assemble.py/simulate.py): every task's test failed first with the stated error, then passed; dart analyze --fatal-infos and dart format clean after each task; final `dart test` = 228 passed.

| Tasks | Shared file / interface | Producer → consumer | Finding |
|---|---|---|---|
| 1–10 | packages/shellx_core/lib/shellx_core.dart (barrel) | each task appends its export lines | OK — additive; replay confirmed no ordering conflict |
| 1 → 2,6,7,9 | lib/src/util/bytes.dart (uuidToBytes, base64UrlNoPad, hexToBytes, concatBytes, constantTimeEquals) | 1 produces, later consume | OK |
| 2 → 5 | lib/src/util/cbor_values.dart (internal) | 2 produces, 5 consumes | OK |
| 3 → 4 | noise primitives, NoiseCipherState/NoiseSymmetricState | 3 produces, 4 consumes | OK |
| 4,5 → 6 | NoiseTransport, encodeBatch/decodeBatch → SecureChannel | OK |
| 10 → 11 | lib/src/relay/relay_connection.dart | 10 creates RelaySocket/connector/Backoff; 11 adds RelayConnection in same file | OK — sequential edits |
| 12 | contract_test.dart covers overview §5.1–5.5 incl. ShellxApi.deleteAccount | OK |
| each task 1–12 | self-consistency of tests vs code vs files | verified by author replay | OK |

Rulings:
- Ruling: accept plan-02 extra public helpers listed under "Bổ sung ngoài danh sách overview" (bytesToHex, kMaxSealedBatchBytes, fromWire helpers, ShellxApi token semantics, RelayConnection connectTimeout 15 s / ping on connect / backoff reset on pong) — overview allows additive helpers; plans 03–05 were told about them — cost if wrong: small API churn later.
- Ruling: `pubspec.lock` gitignored during parallel v1 development (overview §3 updated) — cost if wrong: less reproducible CI until lockfile is committed pre-release.

Model plan: implementers haiku for transcription tasks (1,2,6,7,8,10,12), sonnet for large tasks (3,4,5,9,11); reviewers sonnet, opus for crypto tasks 3–4 and the final review.

## Progress
Task 1: implemented by acb03cc91d423767c (haiku), commit 93ea6e0; review dispatched (sonnet)
Task 1: ⚠️ overview §2 applicability — resolved by controller: task 1 is pure byte utils; §2 items (logging, limits, crypto) not touched.
Task 1: minor (deferred): bytesToHex accepts out-of-range ints silently (plan-prescribed signature)
Task 1: minor (deferred): no zero-length base64UrlNoPad test
Task 1: complete (commits e4cb760..93ea6e0, review clean)
Task 2: dispatched implementer aedc99371269e1555 (haiku), base 93ea6e0
Task 2: implemented by aedc99371269e1555 (haiku), commit c02a134; review dispatched (sonnet)
Task 2: ⚠️ 64 KiB whole-frame enforcement — resolved: enforced by SecureChannel.seal/kMaxSealedBatchBytes (Task 6) on send and by the relay hub; decode side needs no cap.
Task 2: minor (deferred): DataFrame ==/hashCode scan full payload (plan-mandated)
Task 2: minor (deferred): DataFrame.peer not validated until encode() (plan-mandated contract type)
Task 2: complete (commits 93ea6e0..c02a134, review clean)
Task 3: implementer a60b7117ee6cc26d4 (sonnet) dispatched, base c02a134
Task 3: implemented by a60b7117ee6cc26d4, commit e3f726f; review dispatched (opus, crypto)
Task 3: review (opus) spec ✅ Approved; reviewer cross-checked HMAC KATs and a full SymmetricState/Split transcript against an independent Python Noise reference (byte-identical).
Task 3: minor (deferred): NoiseCipherState.decryptWithAd not re-entrant (Task 4 NoiseTransport serializes receives) — plan-mandated
Task 3: minor (deferred): encryptWithAd throws sync on nonce exhaustion vs async in decrypt — unreachable
Task 3: minor (deferred): SymmetricState tests self-consistency only (Task 4 vectors cover)
Task 3: minor (deferred): NoiseKeyPair constructor keeps caller buffers by reference (contract shape)
Task 3: Ruling: pin DartX25519() and DartChacha20.poly1305Aead() in primitives.dart (like DartBlake2s) so every platform runs the vector-tested pure-Dart backend and errors stay NoiseException; plan 05 drops cryptography_flutter — applied as part of Task 4 dispatch — cost if wrong: slower handshake/AEAD on mobile (pure Dart), acceptable at ≤ ~1 MB/s terminal traffic.
Task 3: complete (commits c02a134..e3f726f, review clean)
Task 4: implementer abbad695aff453f90 (sonnet) dispatched with Dart-backend pin ruling, base e3f726f
Task 4: implemented commits ff2e076 04e828a 96707b8 (incl. Dart-backend pin in primitives + key pairs); review dispatched (opus)
Task 4: review (opus) spec ✅ (rev 34 exact, vectors, pure-Dart pin); Needs fixes — 2 Important (plan-mandated), both reproduced by reviewer: (1) remoteStatic set before message-1 authentication → forged key visible after failed read; (2) split() callable repeatedly → same keys at nonce 0 (key/nonce reuse).
Task 4: Ruling: fix both now — assign _rs only after message-1 payload decrypts and return null from remoteStatic when failed; split() one-shot (second call StateError) and drop handshake secrets after split — security-relevant API that SecureChannel/agent build on — cost if wrong: none.
Task 4: minor (deferred): handshakeHash readable before completion/after failure
Task 4: minor (deferred): `ephemeral` param lacks test-only doc
Task 4: minor (deferred): ArgumentError.value keeps psk bytes in invalidValue (plan-mandated)
Task 4: minor (deferred): 65535-byte Noise message limit not enforced on handshake read/write and transport decrypt input
Task 4: minor (deferred): NoiseTransport.encrypt queues caller buffer without copy
Task 4: minor (deferred): ephemeral/psk/ck not cleared after completion (best-effort in Dart)
Task 4: minor (deferred): fetch tool does not verify fixture SHA-256
Task 4: minor (deferred): test gaps — concurrent calls, IK msg2 tamper, tag-only tamper
Task 4: fix round 1/5 dispatched to abbad695aff453f90 (FIX_BASE 96707b8)
Task 4: fix round 1/5 (2 addressed, 0 open — remoteStatic withheld until msg1 authenticates; split one-shot; commits 96707b8..d51a140)
Task 4: minor (deferred): handshakeHash after split returns cached instance, not a copy
Task 4: minor (deferred): forged-message test lacks positive control
Task 4: complete (commits e3f726f..d51a140, review clean)
Task 5: implementer a20a58e90ef9fa7dd (sonnet) dispatched, base d51a140
Task 5: implemented commit c7ebd41; review dispatched (sonnet)
Task 5: ⚠️ CBOR bignum (tag 2/3) → CborBigInt.toInt() wraps instead of throwing (in Task 2's cbor_values.dart) — resolved as minor: only reachable from an authenticated peer after Noise; deferred for final review.
Task 5: minor (deferred): decodeCbor should reject bignum tags rather than truncating (cbor_values.dart, Task 2)
Task 5: minor (deferred): no explicit 2^53 seq / 2^31 id boundary round-trip test (reviewer verified manually)
Task 5: complete (commits d51a140..c7ebd41, review clean)
Task 6: implementer a2416ffaffacd3d6b (haiku) dispatched, base c7ebd41
Task 6: implemented commit 1596049; review dispatched (sonnet)
Task 6: ⚠️ non-TRANSPORT kind rejection lives in callers (plan 03 AgentService/MachineClient); empty batch behavior from Task 5 — resolved: carry to plan 03 review focus.
Task 6: minor (deferred): no test that a rejected seal leaves the channel usable (correct by inspection)
Task 6: minor (deferred): no exact-boundary test (65493-byte batch → 65536-byte frame)
Task 6: minor (deferred): ArgumentError.value names 'messages' but reports byte length (plan-mandated)
Task 6: complete (commits c7ebd41..1596049, review clean)
Task 7: implementer ae06baf8e8166ebde (haiku) dispatched, base 1596049
Task 7: implemented commit e17a2c9; review dispatched (sonnet)
Task 7: minor (deferred): duplicate query params resolve to last value instead of rejecting
Task 7: minor (deferred): constructor doesn't lowercase agentDeviceId (plan-mandated)
Task 7: minor (deferred): agentPublicKey/secret stored by reference (plan-mandated)
Task 7: minor (deferred): no literal toUriString→parse composition test
Task 7: complete (commits 1596049..e17a2c9, review clean)
Task 8: implementer aa2c54227a3fb85a9 (haiku) dispatched, base e17a2c9
Task 8: implemented commit 1b48764; review dispatched (sonnet)
Task 8: review spec ✅; 1 Important (plan-mandated): in-flight guard keyed by store instance — two instances over the same storage could each generate a key.
Task 8: Ruling: do not redesign; document that apps must share ONE KeyValueStore instance per storage for the process (plans 04/05 must provide it as a singleton), and add a retry-after-failed-write test — cost if wrong: an app wiring two instances could lose a pairing on first launch.
Task 8: minor (deferred): KeyValueStore doc mentions flutter_secure_storage
Task 8: fix round 1/5 dispatched to aa2c54227a3fb85a9 (FIX_BASE 1b48764)
Task 8: fix round 1/5 (2 addressed, 0 open — shared-store contract documented; retry-after-failed-write test; commits 1b48764..3b2f562)
Task 8: complete (commits e17a2c9..3b2f562, review clean)
Task 9: implementer a8ac6b9722da79a09 (sonnet) dispatched, base 3b2f562
Task 9: implemented commit bb7f696 (196 tests); review dispatched (sonnet)
Task 9: review spec ✅ Approved; cross-plan check vs relay auth.ts/device.ts/errors.ts/tokens.ts: no mismatch. ⚠️ devices/pairings/account/version routes not yet in relay — resolved: E2E (plan 03) + integration.
Task 9: minor (deferred): two independent 20 s timeouts (headers + body) → worst case ~40 s (plan-mandated)
Task 9: minor (deferred): compareVersions int precision on web (theoretical)
Task 9: complete (commits 3b2f562..bb7f696, review clean)
Task 10: implementer af4072f5dc4162bc2 (haiku) dispatched, base bb7f696
Task 10: implemented commit 518f7e4 (203 tests); review dispatched (sonnet)
Task 10: minor (deferred): jitter lower bound ceil(base/2) for odd bases (plan-mandated)
Task 10: minor (deferred): doc references RelayConnection before it exists; unreachable StateError branch in messages map
Task 10: complete (commits bb7f696..518f7e4, review clean)
Task 11: implementer a241e7813041bf43a (sonnet) dispatched, base 518f7e4
Task 11: implemented commit b38ff2d (226 tests, 3x deterministic); review dispatched (opus)
Task 11: review (opus) spec ✅; Needs fixes — 1 Important (plan-mandated): abandoned connect attempts not cancelled → relay "newest wins" can 4001 the live socket → permanent `replaced` (reproduced in scenarios).
Task 11: Ruling: fix now — serialize connect attempts (never two outstanding upgrades; stale late sockets closed), bound OS connect via per-attempt HttpClient connectionTimeout 10 s in ioRelaySocketConnector; fold in same-file minors: ping-timer leak on failed first ping, sync throw from connector/token() stuck state, close socket on error path — cost if wrong: none.
Task 11: minor (deferred): send() true means handed to socket, not delivered; _onMessage catches only FrameFormatException; no dispose() for broadcast controllers
Task 11: fix round 1/5 dispatched to a241e7813041bf43a (FIX_BASE b38ff2d)
User decision (2026-09-25): auto-merge finished plan branches into feat/shellx-v1 locally after final review; no push.
Task 11: fix round 1/5 (4 addressed, 1 new Important open — unbounded dial gate → stuck `connecting` when an upgrade never settles; + minor connecting flash before revoke; commits b38ff2d..4d97cbf)
Task 11: fix round 2/5 dispatched to a241e7813041bf43a (FIX_BASE 4d97cbf) — overall 12 s upgrade deadline with client.close(force) + bounded gate wait + no connecting flash
Task 11: out-of-scope (deferred): custom RelaySocket whose messages.listen throws leaves state connecting (pre-existing)
Task 11: fix round 2 commit 91fd143 (connector 12 s deadline + force close; bounded gate + _dialGivenUpOn; no connecting flash); re-review dispatched (opus)
Task 11: fix round 2/5 (2 addressed, 0 open — 12 s connector deadline with force close; bounded gate + hard cap; no connecting flash; commits 4d97cbf..91fd143)
Task 11: minor (deferred): doc comments overclaim ("can never register later", "never two outstanding") — soften
Task 11: minor (deferred): 12 s wall-clock connector test (could inject deadline); test title nit at :403
Task 11: parked — relay may still process a zombie upgrade after a fresh one → 4001 on live socket → client `replaced` (unlikely; needs relay reordering) — Ruling: accept for v1; relay-side mitigation idea (ignore registrations closed immediately / confirm liveness before 4001) noted for final review — cost if wrong: rare manual reconnect needed.
Task 11: complete (commits 518f7e4..91fd143, review clean after 2 fix rounds)
Task 12: implementer a5a0df3eda034b3a9 (haiku) dispatched, base 91fd143
Task 12: implemented commit 1784f6d (239 tests); review dispatched (haiku)
Task 12: review Approved; reviewer-labelled Important: contract test touches only 2 of 4 HandshakeStatus values — Ruling: downgrade to minor (wire values for every HandshakeStatus are round-trip tested in Task 5); include in final fix wave if cheap — cost if wrong: an enum-value removal caught by Task 5 tests instead of the contract test.
Task 12: complete (commits 91fd143..1784f6d, review clean)
Final review: dispatched ac39e2b5e16e695f1 (opus) over e4cb760..1784f6d
Final review: With fixes — Important: (1) TLS HandshakeException escapes ShellxApi; (2) deeply nested CBOR → StackOverflowError + ~1 s CPU in all 4 decoders (HS1 decoded pre-trust); Minor: bad_response message can contain token text; ChannelId.bytes mutable; no ShellxApi.close(). All other deferred minors triaged "can wait" except T11 _onMessage catch (folded into #2).
Ruling: one fix wave for Important 1–2 + minors 3–7 (incl. psk ArgumentError, HandshakeStatus contract coverage, int64 overflow → FormatException) — cost if wrong: none.
Cross-plan notes (from final review, for plans 03/04): desktop needs a recovery path from `replaced` (tray Reconnect or slow auto retry); stop the relay before api.logout() to avoid a spurious AgentRevoked; device name must be truncated to ≤100 chars for the relay; commit root pubspec.lock before release (currently resolves test 1.32.0 in pure-Dart workspace; green on 1.30.0).
Final fix wave: dispatched a0f47453d948f7a3c (sonnet), FIX_BASE 1784f6d
Final fix wave: commits d1a779c 166afb3 67f40dc (253 tests); scoped re-review dispatched (sonnet)
Final fix wave re-review: items 1–7 ADDRESSED, no new breakage (nit: 8-byte length with top bit set falls through pre-scan to cbor.decode bounds check).
Plan 02 complete — merged into feat/shellx-v1.

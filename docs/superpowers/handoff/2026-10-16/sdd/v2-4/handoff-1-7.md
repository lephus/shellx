# V2-4 hand-off — chunk 1 (Tasks 1–7) → chunk 2 (Tasks 8–14) and the top-level controller

Plan: `docs/superpowers/plans/2026-10-15-v2-4-tools-phone.md`. Worktree `.claude/worktrees/v2-4`, branch `v2-4`, from `shellx-v2` at 130d8aa. Ledger (every ruling, every deferred minor, every agent id): `.superpowers/sdd/2026-10-15-v2-4-tools-phone/progress.md` — the authority; this file summarizes it. Nothing was pushed by this chunk (origin/v2-4 = 14387fe is the top-level controller's own backup push; HEAD is ahead of it).

## Tasks done (all reviewed; every Critical/Important fixed or ruled; 52 Minor findings deferred in the ledger as `Task N: minor (deferred)`)

| Task | Commits | Review |
|---|---|---|
| 1 `tool.*` messages, `tools` flag, frozen V2-2 decoder, `splitIntoBatches` in the core, project ledger | 130d8aa..eedf79e | clean |
| 2 request/header/gate rules (`tool_rules.dart`) | eedf79e..6013311 | clean |
| 3 flow control (`tool_flow.dart`) | 6013311..a399e5d (57c0b47 + fix a399e5d) | clean after fix round 1 |
| 4 `ToolEndpoint`/slot, router case + `tools` flag, channel 48 KiB flush | a399e5d..4ba847d | clean |
| 5 desktop proxy: list, open, HTTP (`tool_catalog`, `tool_forwarding`, `tool_proxy`, rig) | 4ba847d..14387fe (7d4edc2 + implementer fix 14387fe) | clean |
| 6 WebSockets through the proxy | 14387fe..5a13d3a (5c9d025 + implementer fix 5de9682 + review fix 5a13d3a) | clean after fix round 1 |
| 7 `tool.serve` over the mux | 5a13d3a..cadc3cd (8a6e73a + review fix cadc3cd) | clean after fix round 1 |

Final pass (chunk end): shellx_core analyze clean, 404/404; shellx_agent clean, 962/962 (re-run at cadc3cd); shellx_client clean, 159/159; shellx_e2e clean, 16 passed + 9 skipped (no relay); apps/mobile 1262/1262 (analyze: only the pre-existing `unnecessary_import` info in `test/features/terminal/ime_in_place_edit_test.dart`); apps/desktop clean, 3578 passed + 6 skipped (the plan's "3574 + 10 skipped": same 3584 total, 4 environment-dependent tests run on this machine).

## Rulings made in this chunk (in order; each "decision — why — cost if wrong")

Top-level rulings ledgered verbatim (chunking 1–7/8–14/15–16; nothing pushed; the plan's own ledger `docs/superpowers/ledgers/v2-4-tools-phone.md` used as written — corrected by the top-level controller).

Pre-flight:
1. F1 — the frozen V2-2 decoder is created with V2-2b's exact recipe, so `test/protocol/frozen/messages_v2.dart` + `frozen/messages_v2_ai.dart` are byte-identical to V2-2b's commit 329dce0 (blobs 1e77cd7…, 76fc49a…) instead of the plan's `ai_messages_v2.dart` — identical blobs merge cleanly — cost: the header names V2-2b on `v2-4` until the merge.
2. F2 — acks follow E8 (one `tool.ack` per 50 ms), not §5's "every 64 KiB or 50 ms" — cost: per-phone throughput window-bound (≈ 512 KiB per RTT + 50 ms).
3. F3 — R7's own WebSocket handshake over §5's `WebSocket.connect` — cost: ~40 lines.
4. F4 — R6's CORS-preflight exception to E11's "every request needs the cookie" (E4 needs it) — cost: another app can make an `OPTIONS` request reach a served tool.
5. F5 — Task 1's `SessionListResult` constructor edit is additive (E6 requires the field) — cost: none.
6. F6 — commit trailers are the committing model's own — cost: none.
7. F7 — the plan's R1–R23 stand — cost: the review loop catches the rest.
During tasks:
8. Task 2 concern 1 — no change for planted duplicate gate cookies: Task 9's `_hasGate` accepts any matching pair — cost: none.
9. **Task 2 concern 2 (SECURITY, provisional — needs the top-level controller before Task 9):** the gate cookie is sent by the web view to every `localhost` port (cookies ignore ports; SameSite ignores ports), so an app on the phone listening on a port the page requests (the tool's own port in E3 alias mode, by definition) gets the secret and the tool's cookies; spec and plan do not address it; chunk 1 changed nothing — cost: spec criterion 6 does not hold under that condition. Possible mitigations: a `Content-Security-Policy` the phone adds to HTML responses (connect/img/script/frame sources limited to the served origins + https:), or refusing alias mode; both have compatibility costs.
10. Task 3 I1 — the pacer's refill clamps idle time at 60 s (int64 overflow after ~12.7 idle days stalled all tool traffic for days) — cost: none.
11. Task 3 I2 — every `tool.ws.msg` piece costs `toolWsPieceCost(length) = max(1, length)` against the windows and in ack totals at BOTH ends; `ToolWsOut` also pauses at 64 queued messages — cost: a flood of empty messages can still queue one window of pieces (~262k/stream) at a stalled receiver.
12. Task 3 I3 — RF3 tests added (paced late grant, shared wake-up) — cost: shellx_core count +9 over the plan.
13. Task 3 — keep `max(1, length)`, not `max(64, length)` — cost: as 11.
14. Task 5 A — a stream's stall clock restarts when a piece goes into an empty window (E10 drops only with bytes in flight) — cost: none.
15. Task 5 B — a listing is re-sent when only `available` changes (empty list = "no list yet" bytes) — cost: one more message.
16. Task 5 C — a target whose built path starts with `//` (dot segments) is `bad_request` (Review Focus 4) — cost: none.
17. Task 5 obs 1 — keep keep-alive reuse of loopback tool connections; cost update: a tool sending a non-100 1xx (103 Early Hints) makes dart:io throw an uncaught (logged, non-fatal: the service runs a Flutter engine) error per request and the 1xx becomes the final response — `persistentConnection = false` (one line) is flagged for the final review.
18. Task 6 D1 — an unanswered upgrade's connection is dropped when its stream ends — cost: none.
19. Task 6 D2 — the 101's subprotocol header read as a list; two values or an unoffered one fail the connection (RFC 6455 §4.1) — cost: none.
20. Task 6 D3 — the close reason cut once at a UTF-8 boundary to ≤ 123 bytes — cost: none.
21. Task 6 I1 — the "1009 either way" test now covers tool → phone — cost: none.
22. Task 6 I2 — one `_Stream._forward` for HTTP responses and refused upgrades — cost: none.
23. Task 7 I1 — the mux tests pass alone and in any order — cost: none.
24. Task 7 — a portless `http://localhost/` tool is served on its effective port 80 (E1/V2-3 D1: port 1–65535; alias mode on the phone) — cost: an explicit-port rule would be one line.

## What the next chunk (Tasks 8–14) must know

- **Counts shift:** shellx_core is 404 (plan 395), shellx_agent 962 (plan 955); shellx_client 159, shellx_e2e 16 + 9, mobile 1262, desktop 3578 + 6 as at baseline — the plan's later "a → b" counts are deltas.
- **WebSocket ack unit:** any code or test that computes a WebSocket acknowledgement total by hand must use `toolWsPieceCost` (exported from shellx_core). `ToolSession` (Task 9) uses `ToolWsIn`/`ToolWsOut`, so it is automatic there; check Task 9's test pipes and Task 10.
- **Phone side must tolerate (from Task 6's review):** a `tool.ack` for an id after its `tool.end` (ignore it); a refused upgrade — a non-101 `tool.res` plus `tool.data` on a `ws: true` id, acknowledged in bytes; raw close codes from the desktop (1005, 1006, other reserved) — Task 9's planned `_sendable` filter (1000–1003, 1007–1011, 3000–4999, else a bare `close()`) handles them: keep it.
- **Flow-control contracts:** end outlets with `cancel()` (never a bare `window.close()` while pumping); callbacks passed to outlets/inlets must not throw (`ToolCredit` wakes waiters synchronously).
- **`ToolProxy` public API is as the plan says** (`ToolProxy({pacer, connect, headTimeout, idleTimeout, maxRequestBody, maxWsMessage})`, `serve`, `close`, `catalog`); internal changes (Task 5 A/B/C, Task 6 D1–D3, `_forward`) do not change it. Listings are now also re-sent when only `available` flips (Task 8's `listings` may see `available: true` with an empty list after `available: false`).
- **Task 11** must set `MuxServer.tools` to the service's proxy, advertise `tools` in `hello.caps`, and never clear or replace that proxy on `onUiChanged(false)` or a relay restart (mux_server.dart:168–170), or "the last list stays" breaks.
- **Task 15 (chunk 3)** must gate on `tools` in `hello.caps` (an older service routes `tool.serve` through its default path, which marks the link primed), build `b` with `ToolCatalog.serveBody` (`termFrame` throws over 64 KiB at the sender), and should plug the slot before phones can list (R2: a phone learns of tools at its next `session.list`).
- **Name clash:** `ToolEnd` (the core message) vs `enum ToolEnd` in `packages/shellx_ai/lib/src/model/timeline.dart:52` — only a file importing both the AI timeline and shellx_core would hit it; `hide ToolEnd` on the shellx_ai import fixes it.
- **Timing-sensitive tests:** shellx_core "path performance" (pre-existing) and Task 5's fix-A idle test (200 ms / 600 ms / 150 ms) — rerun alone on a loaded machine before suspecting a change.
- **Harness note** (controller-common.md 17:30) applies to every dispatch.

## For the top-level controller

1. **Decide the Task 2 concern-2 security question (ruling 9) before chunk 2 starts Task 9** (gate secret sent to any localhost port; alias mode hands it to the app holding the tool's port).
2. **Integration with V2-2b:** the frozen decoder files are byte-identical to V2-2b's (clean merge). Textual merges expected in `packages/shellx_core/lib/src/protocol/messages.dart` (the `part` list; the `ai.` and `tool.` dispatch arms side by side; V2-2b's `encodeBatch` change and `_Fields` helpers — no name clash: V2-4's helpers are `_strings`/`_integers` in a private extension inside `tool_messages.dart`), and later `session_router.dart` / `lib/shellx_agent.dart` (V2-2b's plan edits them too). Never take one side whole: both add lines.
3. Final-review triage candidates among the deferred minors: Task 5 `persistentConnection = false` (1xx), Task 5 `tool.list` replies unpaced (RF2-adjacent), Task 4 the unpinned flush-counter reset (RF2), Task 6 `ws.close()` without a time limit, Task 5/7 no test pinning that the service drops non-loopback/https list entries (RF4), Task 6 no test for the bodyless branch (HEAD/204/304).
4. No relay change, no build, no app launch in this chunk.

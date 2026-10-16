# V2-4 hand-off — chunk 2 (Tasks 8–14) → chunk 3 (Tasks 15–16 + final review) and the top-level controller

Plan: `docs/superpowers/plans/2026-10-15-v2-4-tools-phone.md`. Worktree `.claude/worktrees/v2-4`, branch `v2-4`. Ledger (every ruling verbatim, every deferred minor with file:line, every agent id): `.superpowers/sdd/2026-10-15-v2-4-tools-phone/progress.md`, section "Chunk 2" — the authority; this file summarizes it. Nothing was pushed. Two account usage-limit stops (~20:20–21:21 and ~01:30–09:17) interrupted this chunk; the top-level controller resumed it both times; no work was lost (each stop fell between commits). Not compacted.

## Tasks done (every Critical/Important fixed or ruled; 57 Minor findings deferred in the ledger as `Task N: minor (deferred)` with file:line — Task 8: 8, Task 9: 11, Task 10: 9, Task 11: 3, Task 12: 4, Task 13: 17, Task 14: 5; none parked at a breaker)

| Task | Commits | Review |
|---|---|---|
| 8 `MachineTools` (list, open, routing, paced outbox) | cadc3cd..d979f72 (1e65408 + fix d979f72) | clean after fix round 1 (listener callbacks isolated) |
| 9 `ToolSession` (the phone's loopback server) + top-level CSP | d979f72..308526f (81e5ffb brief, 1db3d49 CSP, 9faaec6 N2/N3, 4f99452 own fixes, 28b57eb docs, b169bd2/8f8b3e1/0053b27/308526f round 1) | clean after fix round 1 (opus re-review) |
| 10 end to end (in process; real relay) | 308526f..1fefcb9 (394b9ba + 1fefcb9) | clean after fix round 1 |
| 11 desktop agent side (slot, daemon proxy, `tools` cap) | 1fefcb9..071f832 | clean (Approved) |
| 12 mobile foundation (webview pins, ATS/cleartext, strings, seam) | 071f832..0051313 | clean (Approved) |
| 13 the tool page + Settings › clear tool data | 0051313..c2f6791 (692b879, a82bbb2; round 1 d87ffc7..eec4c47; round 2 323840b..769128f; round 3 a4ffcca, c2f6791) | clean after fix round 3 (opus re-reviews) |
| 14 the Tool group in the picker | c2f6791..d127c04 | clean (Approved; extra tests and a small fake extension judged warranted) |

Final pass (chunk end): at d127c04 — shellx_client analyze clean, 218/218; shellx_e2e analyze clean, 16 passed + 10 skipped (no relay); apps/desktop analyze clean, 3581 passed + 6 skipped; apps/mobile analyze only the pre-existing `unnecessary_import` info (`test/features/terminal/ime_in_place_edit_test.dart`), 1355/1355; shellx_core and shellx_agent untouched in chunk 2 (404 / 962 at chunk 1's end). Worktree clean; both Podfile.locks keep `COCOAPODS: 1.16.2`; no pubspec.lock tracked. Range cadc3cd..d127c04: 29 commits.

## Count offsets (later "a → b" counts in the plan are deltas)

- shellx_core 404 (plan 395, +9 from chunk 1); shellx_agent 962 (plan 955, +7 from chunk 1) — unchanged in chunk 2.
- shellx_client 159 → 218 (plan 185): Task 8 +13 (plan +7), Task 9 +43 (plan +17: CSP 7, N2/N3 7, own fixes 2, round 1 10), Task 10 +3 (plan +2: one burst pin).
- shellx_e2e 16 passed + 10 skipped without a relay (as the plan).
- apps/desktop 3578 + 6 skipped → 3581 + 6 (plan "3574 → 3577, 10 skipped": the same 3584 tests, 4 environment-dependent ones run here); Task 15 adds +3.
- apps/mobile 1262 → 1355 (plan 1285): Task 12 +2, Task 13 +72 (plan +17: round 1 +29, round 2 +10, round 3 +16), Task 14 +19 (plan +4: 2 extra widget tests, 13 in a new `tool_watch_test.dart`).

## Rulings (in order; "decision — why — cost if wrong"; verbatim in the ledger)

Top-level (verbatim in the ledger and, for the CSP, in `docs/superpowers/ledgers/v2-4-tools-phone.md` "## Execution rulings"): the CSP ruling (one `Content-Security-Policy` on every response of the phone's tool server: `default-src 'self' <S> https: wss: data: blob: 'unsafe-inline' 'unsafe-eval'; form-action 'self' <H> https:` over the served ports, never merged or replacing a tool's own); counts; no launches; iOS Podfile.lock keeps `COCOAPODS: 1.16.2`; context; flakes; scratch hygiene (23:40).

Controller (chunk 2):
1. R-C2-1 — the CSP is `toolContentSecurityPolicy(Iterable<int> ports)` (exported, deduplicated, ascending) plus one helper on every response head (`noFolding` + `add` before the tool's headers; never `set` over a tool's CSP); ports read from `_servers` per head — cost: none.
2. R-C2-2 — Task 9 brief defect (verified with a probe): `_answer`'s second `drain()` threw synchronously and skipped `response.close()` (answers without a text hung) — fixed, every answer closes — cost: none.
3. R-C2-3 — every end of an `_HttpStream` cancels its body outlet (built as a pass-through + read-and-drop, since cancelling the request makes dart:io drop the connection before the answer) — cost: a little memory if wrong.
4. R-C2-4 — Task 12's `flutter build ios --config-only` (pod install) run as the plan says — cost: one pod-spec fetch.
5. R-C2-5 — Task 10's real-relay run done (`npm ci`, relay on 8799 started with a shell `&`, stopped by PID, `lsof` empty) — cost: none (done).
6. R-C2-6 — shellx_client counts above the plan from Task 9 — cost: none.
7. R-C2-7 — Task 13's Settings anchor is the licences `_Row`, not the footer — cost: none.
8. Task 8 I1 — `MachineTools` isolates every `ToolStreamListener` callback (silent catch, E18) so a throwing tool stream cannot drop a sealed batch's terminal/AI messages or abort `_channelLost` — cost: a tool-stream bug fails quietly.
9. Task 9 I1 (security; tightens plan R5/R21) — a port is servable only when held on 127.0.0.1 AND [::1] (IPv6 loopback decided by an ephemeral [::1]:0 bind); else alias (main) or not served (sibling) — why: the web view resolves `localhost` to ::1 first, so an app on [::1]:P got the entry nonce and the gate cookie — cost: where something holds [::1]:P, the tool opens on an alias port with E3's banner.
10. Task 9 I2 — WebSocket pieces and an early close arriving with the 101 are kept in order until the upgraded socket is ready — cost: none.
11. Task 9 I3 — an unreadable entry query → 403; a handler throw → 400 with the response closed — cost: none.
12. Task 9 I4 — RF 5 pins added (wrong secret, expired entry, foreign/non-preflight OPTIONS, foreign/cross-site upgrade) — cost: none.
13. Task 9 / Task 13 re-review model — opus for their scoped re-reviews (security), not the generic sonnet — cost: extra opus seats.
14. R-C2-8 — Task 10's end-to-end tests run in same-port mode through Task 9's `TestTool.samePort` + `connectTestTool` (the plan's [::1] + `ipv6Only` now yields alias mode) — cost: alias mode untested end to end (unit-tested in Task 9).
15. Task 10 I1 — the 8 MB and real-relay tests record frame rates as headroom only (in-process throughput ~2.6 MB/s is below both limiters, so they cannot pin RF 2); an end-to-end burst pin of the phone's outbox added (red when the outbox is bypassed) — cost: RF 2's desktop pacing pinned only at unit level (Tasks 3, 5).
16. Task 11 — keep the brief's shutdown order (the background service lets phones go silently before `tools.close()`; phones see "reconnecting") — cost: on a service quit a tool page shows "Đang kết nối lại…" instead of "Mở ShellX trên máy tính…"; one line moves `tools.close()` first (Task 15's in-process quit tells phones `desktop_closed`).
17. Task 13 C1 — the Android download loop (DownloadListener re-entering the policy) is broken: an address let through that comes back before a page start is stopped with one toast (+ a backstop on the third pass); Android only, fragments included; iOS has no guard — cost: a rare same-URL re-navigation before a page start is stopped once.
18. Task 13 I1 → round 2/3 (security, Review Focus 5) — the web view's history never outlives the served origins: an entry `ToolLoad` gets a fresh web view only when the served origin set changed (old view blanked first); pause, leaving the page, and the closing phases (disabled/gone/unavailable) send the view to `about:blank`; Android back only while the page is shown and served — why: Android back and the page's own `history.back()` bypass the navigation policy and would carry the live gate cookie to a port another app holds — cost: a blank entry in history after an app switch on the same ports; history lost when the ports change.
19. Task 13 I2 — the real `WebViewToolEngine`'s safeguards are tested on a fake `WebViewPlatform` (+2 dev dependencies, caret ranges matching the pins) — cost: none.
20. Task 13 I3 — a main-frame load error ends the load — cost: an iOS navigation superseded by another ends the progress line early (cosmetic).
21. Task 13 I4 — iOS "Xóa dữ liệu của tool" also removes every `WebsiteDataType` via the pinned plugin's generated API (implementation import, `// ignore: implementation_imports`) — cost: one `src/` import to revisit when the webview packages move with Flutter; Cache API / service-worker data still not clearable without native code.
22. Task 13 Android POST navigations — no change (the CSP is the top-level's): Android never offers POST navigations to the policy, so with `form-action … https:` a tool's https form POST loads that site inside the tool web view without E12's question (iOS asks) — top-level decision below.
23. Task 13 `beforeunload` — accepted: on Android a page's `beforeunload` can veto the ruled blanks (the WebView's own confirm dialog; "stay" keeps the page running while unserved) — cost: that sequence leaves a page running with the shared cookie store; device check below.
(Task 14: no ruling — reviewed clean.)

## What chunk 3 (Tasks 15–16, final review) must know

- **Task 15** (needs V2-3 Task 1, cherry-picked by the top-level): gate on `tools` in the service's `hello.caps` (Task 11 advertises it: `kDaemonCaps = ['agent', 'cli', 'tools']`); build `b` with `ToolCatalog.serveBody`; plug the slot before phones can list (R2). Task 11's background-service quit lets phones go silently (ruling 16) while Task 15's `quitApp()` runs `stopToolPhone` first — the final review may align them.
- **Task 16** (ledger, compatibility matrix, privacy sweep, real relay): the real-relay result is already measured — 50 MB through a local relay (port 8799) whole and byte-exact, ~19 s, 0 `ws_rate_limited`/`slow_receiver`/`frame_too_large` (3 runs). RF 2's biting pins are Task 3 (pacer), Task 5 (50 MB ≤ 150 frames/s, ≤ 8 MiB/s), Task 8 (outbox ≤ 100 frames/s) and Task 10's burst test; the plan's RF 2 list naming Task 10's rate checks should say they record headroom. The CSP ruling is already in the plan's ledger doc under "## Execution rulings" (Task 9 added the section; Task 16 appends "Execution" results after it).
- **Test support for later tests:** same-port mode needs `TestTool.samePort` + `connectTestTool` (shellx_client `test/support/test_tool.dart`); `TestTool.port` is the listed port (≠ `tool.server.port` in same-port mode). `MachineTools` swallows listener throws — never `expect` inside a `ToolStreamListener` callback. The mobile `FakeToolPage`/`FakeToolMachine` differ from the real session on close/pause/resume/setPhase and `watch()` cannot fail (Task 12 minor); `FakeToolPage.siblingPorts` exists; `FakeToolWebEngines` hands out several fake engines.
- **APIs unchanged from the plan:** `ToolSession`'s public API (constructor, getters, `start/home/pause/resume/close`), `ToolPageSession`/`ToolMachine`, `ToolRoute`/`ToolRouteArgs`. New public: `toolContentSecurityPolicy` (shellx_client); `ToolWebCallbacks.onLoadError`; `WebViewToolData` has an injectable "remove all website data" seam.

## For the top-level controller

1. **Decisions to take (security):**
   - Android POST navigations bypass E12 (ruling 22): options — drop `https:` from the CSP's `form-action` (a tool form posting to an https site then fails on the phone), or an Android `onPageStarted` guard that stops an unserved main-frame load and asks.
   - Task 9's IPv6-loopback probe can be defeated by an app exhausting [::1]'s ephemeral range (then 127.0.0.1:P is served alone) — cheap hardening: remember a successful [::1] bind for the process, or `NetworkInterface.list(includeLoopback: true)`, or treat iOS/Android as having ::1.
2. **Manual checks for spec §10 (devices):**
   - (top-level) a tool page that requests an unserved `localhost` port is blocked by the CSP, and no request reaches that port.
   - iPhone and Android: with another listener on [::1]:P, opening the tool goes to alias mode with E3's banner and that listener receives no request; with nothing there, same-port mode.
   - Android: a link to a PDF/zip/attachment (with and without `Content-Disposition`, with a `#fragment`) shows one toast and does not loop; Android back after the tool reopened on another port leaves the page and sends nothing to the old port; a page with unsaved changes (`beforeunload`) left or turned off on the computer shows the WebView's confirm dialog; after an app switch on the same ports, back lands once on a white page.
   - iOS: a failed navigation (a file iOS cannot show) ends the progress line; "Xóa dữ liệu của tool" signs out a tool that keeps its login in IndexedDB (e.g. Firebase Auth).
   - Both: leaving a tool page stops its scripts (no request reaches the tool's ports afterwards).
3. **Cross-branch merge notes:** chunk 2 touched `packages/shellx_client/lib/src/machine_client.dart` (V2-2b edits it too: put both sides' lines; never take one side whole), `lib/shellx_client.dart` (two exports), the mobile picker/terminal page (Task 14; V2-2b edits them), `apps/mobile/pubspec.yaml` (webview pins + two dev dependencies; V2-3 pins the same webview versions on the desktop), `apps/mobile/lib/l10n/*.arb` + generated l10n (21 keys appended after `aiPlan`; V2-2b may append keys too — regenerate after merging), `app_router.dart`/`.gr.dart` and `dependency.config.dart` (regenerate with build_runner after merging), `apps/mobile/ios/Podfile.lock` (wkwebview lines written by CocoaPods 1.17.0 with the 1.16.2 version line kept; a later `pod install` under 1.16.2 may rewrite the checksum line — harmless).
4. **Final-review triage candidates (chunk 2)** — all in the ledger with file:line: Task 9 M1 (a non-101 1xx passed on as final — with chunk 1's `persistentConnection = false`); Task 9 M2 (phase set after `_unserve`; siblings bound after a pause/close race stay bound); Task 9 M4 (phone-side `setsToolGateCookie` check); Task 9 two policy lines on an unreadable non-ASCII `to`; Task 8 token-cap test gap and O(n²) outbox re-encode; Task 8 `_onFrame` without per-message isolation (pre-existing); Task 10 "nothing served" probe IPv4-only and the 128 KiB-periodic byte pattern; Task 11 misleading shutdown comment; Task 12 fake fidelity and platform-test strictness; Task 13 blank-history UX (back during first load, reload of the blank), dialogs across a retired view, two reconnecting banners, `busy` cover over a shown page, resume lost during a pause in progress, `inactive` not pinned as foreground, dialog stacking, Settings clear without error handling, stale round-2 comments.
5. No relay change; no app launch; the only build-like step was Task 12's `flutter build ios --config-only` (pod install); the relay was run locally for Task 10 and stopped.

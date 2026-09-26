# SDD ledger — plan: docs/superpowers/plans/2026-09-25-shellx-v1-05-mobile.md

Worktree: /Users/lehuuphu/Documents/myProjects/shellx/.worktrees/mobile (branch feat/shellx-v1-mobile from feat/shellx-v1 @ efbfb1c: shellx_core + relay + rewritten plan 05)
Spec: docs/superpowers/specs/2026-09-25-shellx-v1-design.md ; Overview: docs/superpowers/plans/2026-09-25-shellx-v1-00-overview.md ; Design (binding for UI tasks 2,4,7,14,15,16,18,19): docs/superpowers/design/2026-09-25-shellx-mobile-ui.html
Base project (read-only): /Users/lehuuphu/Documents/workspace/DigitalUnicorn/flutter-base/yallabb

## Plan provenance
Rewritten 2026-09-26 by an opus agent (commit efbfb1c): 19 tasks, 14,370 lines. The author replayed every code block/command task by task in a scratch workspace (real shellx_core, copies of shellx_agent + apps/desktop, a STUB shellx_client from Task 9): analyze clean, task tests + whole suite green after each task (suite totals 141…334), regenerate-after-commit left no diff; apk debug + iOS simulator debug builds OK. NOT verified: real devices, real ClientService/MachineClient/pairing (plan 03 Tasks 12–14), the CI freshness job on GitHub. Deviations from HANDOFF §6: json_serializable dropped; ios/Podfile.lock committed fresh in Task 19.
Gates: Tasks 1–8 need only shellx_core; Task 9 needs plan 03 Task 10 (shellx_client scaffold); Tasks 10–19 need plan 03 Tasks 11–14 (+ pairing ids from the Task 9 fix round / Task 13).
Plan-author rulings are in the plan header (auto_route pinned 11.1.0; device_info_plus ^12.3.0; flutter_secure_storage ^10.3.4 / package_info_plus ^9.0.1 to co-resolve with desktop; app_settings 7.0.0; exact generator pins; lock is an overlay not a guard; controllers never navigate; store URL via dart-define; …).

## Pre-flight scan
Full table: .superpowers/sdd/2026-09-25-shellx-v1-05-mobile/preflight.md (sonnet scan). Counts: task-vs-task contradictions 0; per-task self-consistency 0; spec/design/contract conflicts 1; rubric-defect mandates 1 (+1 dead-code note). All §12 texts verbatim; all 5 approved extras present and matching the design.
- Conflict: plan 05 Task 12 `TerminalTabController.reattach()` (plan L8456-8474) catches only `AppErrorException(sessionNotFound)`; the real MachineClient (plan 03 Task 12, b416dbb) throws `MachineConnectionException(agentOffline|timeout)` immediately when there is no channel; the terminal page wires `onReattach: tab.reattach` to a button without guard (L10230/10245/10295) → uncaught error, user sees nothing.
  Ruling: Task 12 (plan 05) must catch `MachineConnectionException` in `reattach()` and surface it through the same notice/ErrorText path as every other machine call (`_run`/`guard`); Task 14's button goes through that guarded path; add a widget/unit test — spec §12: every failure shows its text — cost if wrong: none.
- Pairing-id contract: zero touchpoints in plan 05 (mobile pairs/unpairs only through ClientService.pair/unpair of plan 03) — OK.
- Dead code: `RegisterController.submit`'s `status != 429` guards (L13699-13713) — Ruling: leave (harmless) — cost if wrong: none.
- Ruling: Tasks 10–19 were replayed only against a STUB shellx_client; each of those dispatches must tell the implementer to check the REAL shellx_client API on the branch it merges (plan 03 Tasks 10–14) and adapt mechanically, NEEDS_CONTEXT otherwise — cost if wrong: none.
- Ruling: Tasks 1–8 run now on feat/shellx-v1-mobile (only shellx_core needed); before Task 9 merge the plan 03 branch (or feat/shellx-v1 after plan 03 merges) into this branch — cost if wrong: a re-merge.

## Progress
Task 1: implementer a590088bd4c68f7e0 (sonnet) dispatched, base efbfb1c
Task 1: implemented commit bbbe277 (164 files; 141 tests; analyze clean; freshness check clean; pins exact); review dispatched (sonnet)
Task 1: review (sonnet) spec ✅ Approved (identity/platform/ARB parity/CI/generated freshness independently verified); Important (plan constraint): base files paging_state_signal.dart:86,116 (unconditional log) and app_lifecycle_widget.dart:28,40,42 (print behind enableLifeCircleLog) violate 'only debugPrint inside kDebugMode'
Task 1: Ruling: fix now (wrap in kDebugMode/debugPrint; never log error.toString() beyond runtimeType) — global logging rule — cost if wrong: none
Task 1: minor (deferred): brief sequencing — Step 5 RED fails at asset bundling before Step 7 creates fonts/licences
Task 1: fix round 1/5 dispatched to a590088bd4c68f7e0 (FIX_BASE bbbe277)
Task 1: fix round 1 commit 9c30add (141 tests, analyze, freshness clean); re-review dispatched (haiku)
Task 1: fix round 1/5 (1 addressed, 0 open — debug-only logging; commits bbbe277..9c30add)
Task 1: complete (commits efbfb1c..9c30add, review clean)
Task 2: implementer a3e652f7335d13ed1 (sonnet) dispatched, base 9c30add
Task 2: implemented commit 4516988 (146/146; all values checked against the design file); Ruling: format checks apply to files a task touches — generated intl files and base-kept sized_box.dart differ only by formatter-version drift (dart_style 3.1.7 vs SDK) and CI does not run dart format — cost if wrong: none; review dispatched (sonnet)
Task 2: review (sonnet) spec ✅ (40+ colours independently verified); Important (plan-mandated): password visibility IconButton has no tooltip/semantic label (every password field)
Task 2: Ruling: fix — localized tooltip 'Hiện mật khẩu'/'Ẩn mật khẩu' (en 'Show password'/'Hide password') via new ARB keys; fold in: ShellxLogo as one semantics node labelled 'ShellX' (glyph excluded), StatusCircle excluded from semantics (decorative next to text) — accessibility — cost if wrong: none
Task 2: minor (deferred): logo radius 17.92 vs 18; AppButton fixed 54 pt height at large text scale; HighlightedText overlapping-part keys
Task 2: fix round 1/5 dispatched to a3e652f7335d13ed1 (FIX_BASE 4516988)
Task 2: fix round 1 commit 358b8d8 (149/149; localized toggle tooltip; logo semantics; StatusCircle excluded); re-review dispatched (haiku)
Task 2: fix round 1/5 (3 addressed, 0 open — password toggle tooltip vi/en; logo semantics; StatusCircle excluded; commits 4516988..358b8d8)
Task 2: complete (commits 9c30add..358b8d8, review clean)
Task 3: implementer a87d4f3326fe3ab00 (sonnet) dispatched, base 358b8d8
Task 3: implemented commit 819f50d (164 tests; analyze; freshness); note: forgetAccount uses the raw key 'pinned_machines_<userId>' — must equal shellx_client PinnedStore's key (plan 03 Task 10, on feat/shellx-v1-agent-client); review dispatched (sonnet)
Task 3: review (sonnet) spec ✅ Approved (single KeyValueStore wiped first; forgetAccount removes token keys + device key + exactly pinned_machines_<userId>, matching PinnedStore)
Task 3: minor (deferred → FOLD INTO FINAL FIX WAVE): describeThisDevice has no fallback — a PlatformException in a @preResolve dependency blocks app start; fall back to a generic name
Task 3: minor (deferred): Android secure storage resetOnError defaults to true (a keystore error wipes storage → re-pair) — library default, acceptable for v1
Task 3: complete (commits 358b8d8..819f50d, review clean)
Task 4: implementer a055df38d5bd3e8a6 (sonnet) dispatched, base 819f50d
Task 4: implemented commit c9d633f (174 tests; added BlockSemantics over the locked branch beyond the brief); review dispatched (sonnet)
Task 4: review (sonnet) spec ✅ (Face ID sheet lifecycle handled; strict >5 min; BlockSemantics correct); Important (plan-mandated): LocalAuthBiometricAuthenticator.kind() catches only PlatformException but local_auth_android 2.0.8 throws LocalAuthException(uiUnavailable) → uncaught out of prepareLaunch() → app stuck on splash
Task 4: Ruling: fix — catch LocalAuthException (and any error) in kind()/isAvailable() with safe fallbacks; SplashPage must never be stuck: prepareLaunch failures fall through to navigation; fold in tests: concurrent unlock() returns false without a second prompt; taps on the content under the lock do nothing — cost if wrong: none
Task 4: ⚠️ carry to Task 16 (settings): call AppLockController.settingChanged() right after AppSettings.setBiometricLock()
Task 4: minor (deferred): wall-clock background timer; Android reports strong/weak so 'vân tay' label never shows (known limitation)
Task 4: fix round 1/5 dispatched to a055df38d5bd3e8a6 (FIX_BASE c9d633f)
- ⚠️ from plan 03 Task 14: on HS2 untrusted the client ends that machine's tabs with TabError(AppErrorCode.sessionNotFound) (no core code for untrusted) and MachineFailed(untrusted) — plan 05 Tasks 12/14 must show the machine-level text 'Máy không còn tin cậy điện thoại này. Hãy ghép nối lại.' rather than a per-tab session-not-found message when the machine is MachineFailed(untrusted)
Task 4: fix round 1 commit 283c1fb (179 tests; kind()/isAvailable() catch all; prepareLaunch guards detectKind; guardLaunch helper for SplashPage; concurrency + tap-through tests); re-review dispatched (sonnet)
Task 4: fix round 1/5 (3 addressed, 0 open; commits c9d633f..283c1fb)
Task 4: Ruling: an availability-detection failure lets the user in without a prompt (never locks the user out) — spec §5.6 lock is a local privacy layer, lock-out is worse — cost if wrong: a device whose biometric API errors is not locked
Task 4: minor (deferred): no unit test of LocalAuthBiometricAuthenticator's own catch against a platform stub
Task 4: complete (commits 819f50d..283c1fb, review clean)
Task 5: implementer ae1bb5b751ce8039d (haiku) dispatched, base 283c1fb
Task 5: implemented commit c8b3a83 (8 new, 187/187); review dispatched (sonnet)
Task 5: review (sonnet) spec ✅ (sequences verified vs xterm 4.0.0 source); Important (plan-mandated, forward): terminalShortcuts maps to Flutter's PasteTextIntent/CopySelectionTextIntent, which xterm's internal TerminalActions intercepts (raw terminal.paste) before any app Actions → hardware-keyboard paste bypasses normalizePastedText (Review Focus 5)
Task 5: Ruling: fix now — terminalShortcuts maps to ShellX-specific intents (e.g. ShellxPasteIntent, ShellxCopyIntent) that TerminalView's internal actions don't handle, so Task 7's app-level Actions can paste via normalizePastedText + terminal.paste; update tests — cost if wrong: none
Task 5: ⚠️ carry to Task 7: handle ShellxPasteIntent/ShellxCopyIntent in an Actions widget outside TerminalView (paste = normalizePastedText then terminal.paste, which adds bracketed-paste markers itself)
Task 5: minor (deferred): CursorKeysInputHandler overrides Shift+Home/End/Up/Down (keytab scroll actions were non-functional in xterm 4.0.0 anyway)
Task 5: fix round 1/5 dispatched to ae1bb5b751ce8039d (FIX_BASE c8b3a83)
Task 5: fix round 1 commit 7fe5b38 (188/188; ShellxPasteIntent/ShellxCopyIntent); re-review dispatched (haiku)
Task 5: fix round 1/5 (1 addressed, 0 open — ShellX paste/copy intents; commits c8b3a83..7fe5b38)
Task 5: complete (commits 283c1fb..7fe5b38, review clean)
Task 6: implementer aa87d78b9caaf2c73 (haiku) dispatched, base 7fe5b38
Task 6: implemented commit ddbd6fc (13 new, 201/201); review dispatched (sonnet)
Task 6: review (sonnet) spec ✅ Approved (no issues)
Task 6: complete (commits 7fe5b38..ddbd6fc, review clean)
Task 7: implementer a2699d3ddad9cdb2d (sonnet) dispatched, base ddbd6fc
Task 7: ⚠️ carry to Task 14: the terminal page must handle ShellxPasteIntent (read clipboard → terminal.paste(text); ShellxTerminal.paste normalises + brackets) and ShellxCopyIntent (copy selection) in an Actions widget outside TerminalView — otherwise hardware-keyboard paste/copy do nothing
- ⚠️ from plan 03 final review (M6): ClientService.unpair forgets the pin before its DELETE (3 attempts over ~1.5 s); if it still fails the agent keeps trusting the phone — plan 05 Task 16 (settings 'Bỏ ghép nối') must surface the failure with a retry (unpair works without a pin)
Task 7: implemented commit dea2e4a (13 new, 214/214); review dispatched (sonnet)
Task 7: review (sonnet) spec ✅ (paste/IME/key mapping verified vs xterm source) but Needs fixes — Important: a hardware-keyboard letter typed while a touch-armed sticky Ctrl/Alt is active is silently dropped (TerminalView._handleKeyEvent has no textInput fallback when keyInput returns false)
Task 7: Ruling: fix — ShellxTerminal.keyInput handles a text key itself when sticky modifiers are active (map key→char, uppercase letters with shift, apply + consume modifiers, emit, return true) so both hardware and soft paths work; test through TerminalView with a simulated hardware key event; fold in: locked dot inside the key (design top/right 4), no drop shadow on the one-shot cap, localized semantics labels for glyph-only caps (↑ ↓ ← → | ~ / -) in vi + en — cost if wrong: Shift+symbol on hardware with sticky Alt uses the unshifted symbol (layout-dependent, accepted)
Task 7: fix round 1/5 dispatched to a2699d3ddad9cdb2d (FIX_BASE dea2e4a)
Task 7: fix round 1 commit a364afd (220 tests; hardware path detected via HardwareKeyboard.isLogicalKeyPressed; dot/shadow/semantics folds); residual: possible double emission if a device echoes hardware keys via IME too — add to the manual device checklist; re-review dispatched (sonnet)
Task 7: fix round 1/5 (4 addressed, 0 open; commits dea2e4a..a364afd)
Task 7: minor (deferred): hardware key auto-repeat after a consumed one-shot drops the repeated letter (same as before); possible IME double delivery on real devices → manual checklist
Task 7: complete (commits ddbd6fc..a364afd, review clean)
Task 8: implementer add326afb2a977356 (sonnet) dispatched, base a364afd
Task 8: implemented commit ce3e1d7 (7 new, 227 total); review dispatched (sonnet)
Task 8: review (sonnet) spec ✅ Approved (xterm char-size equivalence independently verified)
Task 8: minor (deferred): pinch_zoom.dart deep-imports app_settings instead of the core barrel (brief code)
Task 8: complete (commits a364afd..ce3e1d7, review clean)
RESUME GATE: merged feat/shellx-v1 (plan 03 final: shellx_client/agent/e2e + relay) into this branch (0015f27); 227/227 green
Task 9: implementer af12731a1b5111a26 (sonnet) dispatched, base 0015f27 (real shellx_client API; untrusted text wins over per-tab sessionNotFound; 410/413 → generic)
Task 9: implemented commit b9017ff (11 new, 238 total); note: PairingException/PairingFailure/MachineFailed/MachineConnectionException live in shellx_client (briefs say core); review dispatched (sonnet)
Task 9: review (sonnet) spec ✅ Approved (exhaustive switches vs real enums; §12 verbatim)
Task 9: minor (deferred): no explicit test for 410/413 → generic (same branch as 500)
Task 9: complete (commits 0015f27..b9017ff, review clean)
Task 10: implementer a7262dce7438d3116 (opus) dispatched, base b9017ff (real shellx_client behaviours documented on the ports)
Task 10: implemented commit 670ac16 (4 new, 242 total); adaptations: machine() asks ClientService each time (stale session after untrusted/failed unpair); unpair drops the session before DELETE; fakes throw MachineConnectionException and model replay/untrusted/unpairError; review dispatched (opus)
Task 10: ⚠️ carry to Task 14: the terminal page must react to MachineFailed(untrusted) on states (show 'Máy không còn tin cậy điện thoại này. Hãy ghép nối lại.' + go back), not only per-tab 'Phiên đã kết thúc'
Task 10: ⚠️ carry to Task 16: when unpair throws, keep the machine visible and offer retry (registry not cleared; unpair works without a pin)
Task 10: ⚠️ carry to Task 17: synthetic offline PRESENCE on relay loss must NOT stamp 'Lần cuối online' = now; only a real offline while the relay is connected (or devices() last_seen_at) updates last-seen
Task 10: review (opus) spec ✅ (3 deviations accepted); Needs fixes — Important: FakeBackend.unpair keeps handles/session alive, contradicting the port contract (hides the Task 16 failed-unpair path)
Task 10: Ruling: fix the fake (close handles + session shut down on unpair, both success and unpairError paths) and fold minors (emitState, divergence doc, closeTab identity, terminal dispose, port doc wording, test teardown); don't change other fake semantics — later briefs' tests rely on them — cost if wrong: later tests written against lenient fakes may miss real-client paths (documented list)
Task 10: fix round 1/5 dispatched to a7262dce7438d3116 (FIX_BASE 670ac16)
Task 10: fix round 1 commit a8caf89 (247 tests; 5 new); re-review dispatched (sonnet)
Task 10: fix round 1/5 (6 addressed, 0 open; commits 670ac16..a8caf89)
Task 10: complete (commits b9017ff..a8caf89, review clean)
RESUME GATE: merged feat/shellx-v1 (plan 04 desktop + core I3 logout-token-if-unchanged + F6 RelayConnection.stop awaits dial) into this branch (5627e94); core 261, client 98, agent 167, desktop 269, mobile 247 green; analyze clean
Task 11: implementer a41825a9a27c9ac9e (opus) dispatched, base 5627e94
Task 11: Ruling R1: sign-out fail-closed — stored token deleted before the network logout; logout bounded 10 s, any error swallowed — why: desktop final-review I4 precedent; a kill during logout must not leave the phone signed in — cost if wrong: none (relay deletes the token on next login anyway)
Task 11: Ruling R2: _signOut re-entrant (one SignedOutEvent, one dispose) — why: logout + 4002 can overlap — cost if wrong: none
Task 11: Ruling R3: deleteAccount failure after the relay already revoked (lost response) → sign out revoked, rethrow — why: the ignored 4002 would otherwise strand a dead session — cost if wrong: an extra sign-out on a rare path
Task 11: implemented commit 0c57b97 (24 new, 271 total; R1–R3 + VersionGate FormatException + deleteAccount fail-closed on forgetAccount error); concerns: dispose() throw unhandled on the 4002 path; deleteAccount not blocked during sign-out; 401 on delete w/o revoked keeps session; both deletes failing keeps token; review dispatched (opus)
Task 11: review (opus) spec ✅; Needs fixes — Important: token deletion awaits the real teardown (RelayConnection.stop waits ≤15 s for an in-flight dial) → fail-closed not held on a black-holed network
Task 11: Ruling: start teardown un-awaited, deleteToken, bounded logout, then await teardown (caught) before token=null + emit; same in deleteAccount; fold minors (R3 original error kept, in-flight sign-out guards for login/delete + identical-session clear, resume error handling, VersionGate 5 s bound, vacuous test fix + guard-reset test) — cost if wrong: none
Task 11: fix round 1/5 dispatched to a41825a9a27c9ac9e (FIX_BASE 0c57b97)
Task 11: fix round 1 commit a27d827 (280 tests; 9 new); deleteAccount now signs out via _signOut(accountDeleted); concerns (UI-unreachable): login in flight when sign-out starts may lose its stored token / race the old dial; delete succeeding during an in-flight logout keeps device key + pins; re-review dispatched (sonnet)
Task 11: fix round 1/5 (6 addressed + doc note, 0 open; commits 0c57b97..a27d827)
Task 11: ⚠️ carry to Task 16: settings 'Đăng xuất' and 'Xóa tài khoản' must be mutually exclusive while either is in flight (a logout landing in deleteAccount's DELETE window joins it as loggedOut → device key/pins kept); keep the delete flow modal
Task 11: ⚠️ carry to Task 19: the login/register form must not submit while a sign-out is in flight (SessionHolder awaits it anyway; the route should only show after SignedOutEvent)
Task 11: minor (deferred): a login already in flight when a sign-out starts may lose its stored token (stays in memory; next launch signed out) or be 4001'd by the old dial (recoverable) — UI-unreachable
Task 11: complete (commits 5627e94..a27d827, review clean)
Task 12: implementer a53864dbf94af25d7 (sonnet) dispatched, base a27d827
Task 12: Ruling (refines pre-flight): reattach() leaves the controller intact on any non-sessionNotFound failure and RETHROWS; Task 14 routes 'Gắn lại' through _run (same ErrorText notice path); tests: MachineConnectionException rethrown + state kept + second reattach works; reuseHandles=true (real behaviour) → no double subscription/duplicated output — why: the notice path lives in Task 14's page controller — cost if wrong: Task 14 must wire it (carry)
Task 12: ⚠️ carry to Task 14: onReattach must go through TerminalPageController._run (never a bare tab.reattach on a VoidCallback)
Task 12: implemented commit 7a8fdca (15 new, 295 total); review dispatched (sonnet)
Task 12: review (sonnet) spec ✅ Approved (ruling tests verified; OSC/resize checked vs xterm 4.0.0)
Task 12: minor (deferred): _sendResize <1 guard unreachable via xterm (clamps) — defence in depth; no test for TabError(sessionLimit) (same branch as spawnFailed)
Task 12: complete (commits a27d827..7a8fdca, review clean)
Task 13: Ruling: WorkspaceRegistry.forMachine asks backend.machine(agentId) every time; a cached workspace whose machine is not identical (unpair/re-pair, untrusted-forgotten) is disposed and replaced; StateError also drops a cached workspace; tabCount is reactive to workspace creation/removal (version signal) — why: Task 10's machine() returns a new adapter after the MachineClient changes; the machine list pill reads tabCount in a computed — cost if wrong: stale workspace bound to a dead session / stale 'N tab' pill
Task 13: implementer aa3ee87ef2c8601fe (sonnet) dispatched, base 7a8fdca
Task 13: implemented commit 2aa96ef (13 new, 308 total; ruling applied); review dispatched (sonnet)
Task 14: rulings R1–R6 written to task-14-rulings.md (machine-state untrusted/protoUnsupported without a UI request; reattach via _run; hardware paste/copy Actions; no disposed-signal reads after exit; auto_route pitfall; forMachine StateError at page build)
Task 13: review (sonnet) spec ❌ plan-mandated Important: close() doesn't track the active tab by identity (closing an earlier tab silently switches the active tab)
Task 13: Ruling: fix — keep the active tab by identity; neighbour at the same index when the active tab itself closes — cost if wrong: none
Task 13: fix round 1/5 dispatched to aa3ee87ef2c8601fe (FIX_BASE 2aa96ef)
Task 13: fix round 1 commit eaebe08 (311 tests; 3 new, red first); controller read the 18-line diff: active tab kept by identity, neighbour on closing the active one — addressed
Task 13: fix round 1/5 (2 addressed, 0 open; commits 2aa96ef..eaebe08)
Task 13: complete (commits 7a8fdca..eaebe08, review clean)
Task 14: implementer dispatched (opus), base eaebe08, rulings task-14-rulings.md
Task 14: implementer a33220c53fefa7101 (opus)
Tasks 15–17: rulings written ahead (task-15/16/17-rulings.md): 15 auto_route scannerBuilder pitfall + devices() name fallback; 16 failed unpair stays visible with retry + registry.remove in finally + delete page modal while busy; 17 synthetic offline PRESENCE keeps lastSeenAt
Task 14: implemented commits 70b4530 (brief) + 361a8fc (rulings R1–R6), 29 new, 340 total; deviations: closing signal gates Watches before workspace dispose; untrusted pop doesn't await unpair; pop post-frame after closing sheets; R6 → pop untrusted w/o unpair; controller keeps its backend after sign-out; reconnect via _run; review dispatched (opus)
Task 14: review (opus) spec ✅ Approved (R1–R6 verified vs real client/xterm/signals; 8 deviations judged sound; 29 tests, 0 disposed-signal reads)
Task 14: FOLD INTO FINAL FIX WAVE: (m1) replaceWithNew gated on dispose — leaving mid-request leaves the ended tab behind (terminal_page_controller.dart:137; gate on _startClosing only); (m2) no test for leaving while a _run is in flight; (m3) _onMachineFailure's pre-await part unguarded under unawaited (:169, :219); (m4) requireBackend in the initializer outside the R6 fallback (:32); (m5, plan-mandated) status line says 'Đang kết nối…' for replaced/Failed states (terminal_page.dart:371-376)
Task 14: ⚠️ carry to Task 19: popUntil in terminal_page.dart:66 covers the nearest navigator only; showConfirmDialog uses the root navigator — keep TerminalRoute on the root navigator (or pop dialogs from the root too)
Task 14: complete (commits eaebe08..361a8fc, review clean)
Task 15: implementer dispatched (sonnet), base 361a8fc, rulings task-15-rulings.md
Task 15: implemented commit 3adcb7b (13 new, 353 total; R1 kept the constructor param — public top-level default compiles); review dispatched (sonnet)
Task 15: review (sonnet) ❌ Critical: _step write after a second await without a _disposed re-check (close during devices() name lookup → SignalsWriteAfterDisposeError, unhandled); Important: no test pins R2 (devices() failure after success → 'Máy không xác định')
Task 15: Ruling: fix both (re-check after every await + test; R2 test); defer R1 route-args function equality (latent) and camera-denied test (manual checklist) — cost if wrong: none
Task 15: fix round 1/5 dispatched to aeac9b5539811ef3e (FIX_BASE 3adcb7b)
Task 15: fix round 1 commit 170370a (355 tests; crash regression red first; R2 test verified by breaking the fallback); controller read the lib diff — addressed
Task 15: FOLD INTO FINAL FIX WAVE: (m1) qr_scanner_page.dart _onCode catchError rethrows with 'throw error' (loses the stack; use Error.throwWithStackTrace); (m2) code comments cite 'fix round 1' (process noise) — reword as plain rationale
Task 15: fix round 1/5 (2 addressed, 0 open; commits 3adcb7b..170370a)
Task 15: complete (commits 361a8fc..170370a, review clean)
Task 16: implementer dispatched (sonnet), base 170370a, rulings task-16-rulings.md
Tasks 18–19: rulings written ahead (task-18/19-rulings.md): 18 untrusted covers not-pinned, scanner replace loses TerminalExit (accepted), null lastSeen display; 19 sign-out while terminal open vs enforcer replaceAll, root navigator, forms blocked during sign-out, launch never crashes on storage errors, full verification incl. builds
Task 16: implemented commit 01129b3 (12 new, 367 total; R1 failedUnpair row + retry, registry.remove in finally; R3 PopScope/Hủy disabled while busy + logout guard); review dispatched (sonnet)
Task 16: review (sonnet) spec ✅ (R1–R4), Needs fixes — Important (plan-mandated): load()/_loadPaired() unguarded → secure-storage error = unhandled + endless spinner
Task 16: Ruling: guard load with a usable failure state + test; fold: disable 'Xóa tài khoản' while logging out; two-failed-unpairs + offline-names tests — cost if wrong: none
Task 16: fix round 1/5 dispatched to a74b067d340391ea5 (FIX_BASE 01129b3)
Task 16: fix round 1 commit 6ca4357 (370 tests; pinnedMachines-throws test red first); controller read the lib diff — load/_loadPaired guarded, failed rows or empty list on failure, delete row disabled while logging out — addressed
Task 16: fix round 1/5 (3 addressed, 0 open; commits 01129b3..6ca4357)
Task 16: complete (commits 170370a..6ca4357, review clean)
Task 17: implementer dispatched (sonnet), base 6ca4357, rulings task-17-rulings.md
Task 17: implemented commit 65d30d4 (8 new, 378 total; R1: offline frame is synthetic when backend.relayState is not connected at handling time — relay flips state synchronously before emitting; emitRelayLoss knob); review dispatched (sonnet)
Task 17: review (sonnet) spec ✅ (R1 ordering independently verified; live relayState read is required on the suspend path); Needs fixes — Important (plan-mandated): reconnectReplaced unguarded
Task 17: Ruling: guard reconnectReplaced + test; fold refresh generation guard + test — cost if wrong: none
Task 17: fix round 1/5 dispatched to a10fb061386001c9c (FIX_BASE 65d30d4)
Task 17: fix round 1 commit ed17b2f (380 tests; both new tests red first); controller read the lib diff — reconnectReplaced guarded, refresh generation guard — addressed
Task 17: minor (deferred): a stale refresh that FAILS after a newer one succeeded still sets state.error (generation check only on success)
Task 17: fix round 1/5 (2 addressed, 0 open; commits 65d30d4..ed17b2f)
Task 17: complete (commits 6ca4357..ed17b2f, review clean)
Task 18: implementer dispatched (sonnet), base ed17b2f, rulings task-18-rulings.md
Task 18: first run stalled (watchdog 600s, nothing written); resumed same agent; implemented commit f2f8036 (8 new, 388 total; R3 kept 'Lần cuối online: không rõ' for null lastSeenAt); review dispatched (sonnet)
Task 18: review (sonnet) ❌ Important: R3 not followed — offline + null lastSeenAt shows 'Lần cuối online: không rõ' (common: freshly paired never-connected machine) instead of 'Offline'
Task 18: Ruling: fix per R3 + test; fold UpdateRequiredPage widget test — cost if wrong: none
Task 18: fix round 1/5 dispatched to afea7ed4fa52b94f9 (FIX_BASE f2f8036)
Task 18: fix round 1 commit 9731244 (392 tests; null-lastSeen test red first; +3 UpdateRequiredPage tests); controller read the lib diff — addressed
Task 18: FOLD INTO FINAL FIX WAVE: machine_list_page.dart:230 comment cites 'R3' (process note) — reword
Task 18: fix round 1/5 (2 addressed, 0 open; commits f2f8036..9731244)
Task 18: complete (commits ed17b2f..9731244, review clean)
Task 19: implementer dispatched (opus), base 9731244, rulings task-19-rulings.md
Task 19: implemented commits 394e811..276b070 (32 new, 424 total; analyze clean; generators fresh; apk debug + ios debug no-codesign + ios simulator built); deviations: splash replaced itself with RootApp (dialogs crashed on the splash navigator), terminal self-pop skipped when its route is off the navigator, restore() wrapped + detectKind guard kept (brief would open unlocked), keyboard 'done' respects the disabled button; Podfile.lock committed; review dispatched (opus)
USER DECISION (2026-09-26): mobile bundle id + Android applicationId = com.shellx.prod (was pro.shellx.mobile). Ruling: also move the Android namespace + Kotlin package (com/shellx/prod) and RunnerTests (com.shellx.prod.RunnerTests), Play Store URL id=com.shellx.prod, tests; desktop keeps pro.shellx.desktop (user said 'app' + applicationId = mobile) — cost if wrong: one more rename. Applied after the Task 19 review returns (reviewer is running tests in this worktree).
Task 19: review (opus) — 4 deviations judged correct; Needs fixes — Important: secure-storage error at launch (AppSettings.load in DI / fresh-install wipe, outside guardLaunch) strands a blank splash; R4 test setup order hides it
Task 19: Ruling: fix (AppSettings.load fail-closed defaults, wipe failure continues, _start catches) + tests; fold password length in code points (relay NFC code points), process-note comment cleanup; apply the user's id change com.shellx.prod in the same round with builds — cost if wrong: none
Task 19: fix round 1/5 dispatched to ad88527989bf77944 (FIX_BASE 276b070)
Task 19: fix round 1 commits 21e705b f43823a db02856 9f979b1 (430 tests; red first for items 1–2; built ids: Android com.shellx.prod minSdk 26, iOS com.shellx.prod 15.0); concerns: DI failure → base error widget with 'Thử lại' + getIt.reset() at startApp; NFC gap in code-point count; old id kept in historical docs; re-review dispatched (sonnet)
USER REQUEST (2026-09-26): new mobile logo (logo_shellx_rounded.png + logo_shellx_square.png, 512², opaque; rounded has WHITE corners). Ruling: iOS AppIcon from the square (RGB, no alpha; 1024 upscaled — ask for a 1024/vector source), Android adaptive icon (bg #16181D, foreground square at 72/108, monochrome), legacy PNGs from the rounded with an anti-aliased mask, ShellxLogo draws assets/images/logo.png; sources + tool/gen_app_icons.py committed; brief logo-brief.md; dispatched after the Task 19 re-review (worktree in use)
Task 19: re-review (sonnet) 4/4 ADDRESSED, no new breakage; getIt.reset() + splash DI-failure retry judged safe; note: canRun omits SessionEnforcer (untriggerable)
Task 19: fix round 1/5 (4 addressed, 0 open; commits 276b070..9f979b1)
Task 19: complete (commits 9731244..9f979b1, review clean)
ALL 19 TASKS COMPLETE (head 9f979b1, 430 tests). Next: logo work (user request) in parallel with the final whole-branch review on a detached snapshot at 9f979b1.
FINAL: whole-branch review (opus) dispatched on detached snapshot 9f979b1 (scratchpad/review-mobile-9f979b1), package final-review-25ddd75..9f979b1.diff (325 KB); logo agent a84b98dd3808b2f05 (sonnet) runs in parallel on the branch (its commits get their own small review)
LOGO: commits e48b13a (icons: iOS RGB all sizes, Android adaptive + monochrome + legacy with measured r≈114/512 mask; sources in assets/branding, tool/gen_app_icons.py deterministic) + c79aa65 (ShellxLogo draws Assets.images.logo; +1 test); 431 tests; controller checked the contact sheet (scratchpad/icon-check.png) and the lib/pubspec/res diff — clean. Note: square source has a 1px (51,53,57) last row/col artifact, patched in the generator only.
FINAL: review (opus) 'With fixes' — 0 Critical; Important: I1 bracketed-paste escape (pastejacking → command execution), I2 Android re-scan dead end (noDuplicates), I3 spawn_failed never shown in a tab with the real client (spec §12); 10 Minor
FINAL: Ruling: ONE fix wave = I1–I3 + M1–M11 (privacy cover, persisted pending unpairs, no DELETE on untrusted exit, camera restart, scanner catch-all, fire-and-forget sweep, vi InfoPlist.strings, pill only on paired, back consumed while locked, pin xterm/signals, backup rules) + ledgered FOLD items (T14 m1–m5, T17 stale error, T19 canRun, comment sweep); deferred: e2e integration test (follow-up), manual checklist additions — cost if wrong: a larger wave (opus)
FINAL: fix wave dispatched (opus), FIX_BASE c79aa65, findings final-fix-findings.md
FINAL: fix wave commits e3f5016 d6adb30 9b2c09d e1969b3 46c2994 c5687d7 (490 tests, +59; analyze clean; generators fresh at HEAD; apk + ios debug built; manifest backup rules + vi/en InfoPlist.strings verified); deviations: failed tab titled 'shell'; page restarts camera itself; back consumed via binding observer; launchUrl false → toast; privacy cover also shows during in-app system sheets; untrusted relay row kept until re-pair; signals_core/preact_signals still transitive ^6.3.1; test names with R-notes remain; scoped re-review dispatched (opus)
FINAL: re-review (opus) — all findings ADDRESSED; deviations accepted (M10 pin short of signals_core); NEW: B1 Important Android permission-request loop (restart on every resume while denied), B2 focus dropped by the privacy cover, B3 older failing refresh erases newer error; out of scope: IME paste bypasses the sanitiser
FINAL: Ruling: residual follow-up (like desktop's) — fix B1, B2, B3, S1 (sanitise IME text), P1 (pin signals_core) — why: B1 load-bearing, all small — cost if wrong: one small extra commit set; defer: test-name labels, PendingUnpairs.retry re-pair window (narrow)
FINAL: residual commits 480f368 e2cb849 7e42ad0 2a31883 def4783 (501 tests, +11 red first; analyze clean; generators fresh); controller read the lib diff — B1 flag armed by 'Mở Cài đặt' only, B2 ExcludeFocus only while locked, B3 refresh writes nothing when superseded (no mainStateGuard), S1 normalizeTypedText strips controls, P1 signals_core 6.3.1 — addressed
FINAL: found via the B1 tests — _ScanFrame's CustomPaint (hitTest default true) sits over the centred camera-denied content and swallows taps on 'Mở Cài đặt' on real devices; Ruling: fix (IgnorePointer on the decorative frame) + geometric tap test — dispatched to a8c1b3646624362f0
FINAL: scan-frame fix b752728 (IgnorePointer; geometric tap test red first; 501 tests)
FINAL: plan 05 complete — merging feat/shellx-v1-mobile (b752728) into feat/shellx-v1

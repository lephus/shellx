# SDD ledger — plan: docs/superpowers/plans/2026-09-25-shellx-v1-04-desktop.md

Worktree: /Users/lehuuphu/Documents/myProjects/shellx/.worktrees/desktop (branch feat/shellx-v1-desktop from feat/shellx-v1-agent-client @ c29cbdd: final shellx_core + shellx_agent tasks 1–5)
Spec: docs/superpowers/specs/2026-09-25-shellx-v1-design.md ; Overview: docs/superpowers/plans/2026-09-25-shellx-v1-00-overview.md

## Pre-flight scan
Evidence: plan author compiled/tested every block against STUB shellx_core/shellx_agent (112 widget/unit tests; 6/6 real-PTY integration tests on macOS; debug ShellX.app launched 25 s). Not yet run against the real packages.

| Tasks | Shared file / interface | Finding |
|---|---|---|
| 1 → all | apps/desktop scaffold, root pubspec workspace line | OK |
| 3 | FlutterPtyFactory implements shellx_agent Pty (real, Task 1 of plan 03) | OK — interface exists |
| 4 | SecureKeyValueStore implements core KeyValueStore | must be ONE shared instance (DeviceIdentity + TrustedStore contracts) |
| 6,7 | AgentRuntime/AgentController over AgentService (plan 03 Task 9 — NOT YET BUILT) | BLOCKED until plan 03 Task 9 merges |
| 8–11 | tray/windows/main over controller | after 6–7 |

Rulings:
- Ruling: start plan 04 now with tasks 1–5 only (depend on existing core/agent interfaces); pause before Task 6 until plan 03's AgentService (Task 9) is merged into this branch — cost if wrong: a re-merge.
- Ruling (carried from core/agent reviews, apply in the owning tasks): (a) one shared SecureKeyValueStore instance app-wide (Task 4/6); (b) one shared TrustedStore instance (Task 6); (c) desktop needs a recovery path from RelayConnectionState.replaced (tray "Reconnect" or slow auto retry) (Task 7/8); (d) stop the relay before api.logout() to avoid a spurious AgentRevoked (Task 7); (e) FlutterPtyAdapter.kill() must terminate the whole tree and output must close on exit (Task 3 — plan already does); (f) device name ≤ 100 chars for the relay (plan caps at 64 — OK).

Model plan: sonnet implementers (Flutter + platform code); opus review for Task 3 (PTY/process-tree), 7 (controller), final; sonnet reviews otherwise.

## Progress
Task 1: implementer ad7a7a0eba38cbabb (sonnet) dispatched, base c29cbdd
Task 1: implemented commit 0703842 (build macOS debug OK); review dispatched (sonnet)
Task 1: ⚠️ Windows build/hidden launch — resolved: Windows CI (plan 06 desktop job).
Task 1: ⚠️ carry to Task 9/11: windows/runner/main.cpp keeps SetQuitOnClose(true) — closing a window must hide to tray, not quit (verify window_manager close intercept in Task 9/11)
Task 1: minor (deferred): pbxproj still references shellx_desktop.app for RunnerTests TEST_HOST (scaffold quirk)
Task 1: complete (commits c29cbdd..0703842, review clean)
Task 2: implementer abe69f303b4895ee0 (haiku) dispatched, base 0703842
PAUSED 2026-09-25 (user request): Task 2 implementer was STOPPED mid-work (it had just written the failing test and started ARB/l10n files); partial work saved as WIP commit on feat/shellx-v1-desktop ("wip(desktop): Task 2 l10n in progress"). On resume: re-dispatch Task 2 from base 0703842 treating the WIP as a starting point (verify against the brief), then review. Tasks 3–5 next; STOP before Task 6 until plan 03 Task 9 (AgentService) is merged into this branch.
RESUMED 2026-09-25: Task 2 re-dispatched to fresh implementer a148fefeeb6ba33b4 (sonnet) from WIP ac112cc (instructed git reset --soft 0703842), base 0703842
Task 2: implemented commit 8558f00 (l10n 4/4, full 6/6; fixed curly quotes in 2 keys of the WIP draft); review dispatched ad6c9c8e2d054424c (sonnet)
Task 2: review (sonnet) spec ✅ Approved (ARBs compared programmatically to the brief); ⚠️ flutter_localizations/intl deps — verified present in apps/desktop/pubspec.yaml (Task 1)
Task 2: minor (deferred): authForgotPasswordHint / onboardingTrayHint full strings (curly quotes) not pinned by a test
Task 2: complete (commits 0703842..8558f00, review clean)
Task 3: implementer aab37265d0287c84f (sonnet) dispatched, base 8558f00
Task 3: implemented commit 377d5b1 (unit 16/16, full 22/22, macOS integration 6/6; Windows paths only via fakes → Windows CI); review dispatched (opus)
Task 3: review (opus) spec ✅ (byte-identical to brief) but Needs fixes — all plan-mandated: (1) flutter_pty 0.4.2 duplicates the exe on the Windows command line (pwsh sessions die); (2) POSIX tree kill misses children forked by re-parented HUP-ignoring survivors (reproduced); (3) failed Windows spawn leaks conhost + non-ASCII cwd fallback fails; (4) swallowed kill errors / ps failure / uncaught zone error; minors 5–9 (stale-pid kill after exit, Job Object, weak integration tests, flutter_pty fd leak + tail loss, cleanups). Full text: task-3-fix1-findings.md
Task 3: Ruling: R1 vendor flutter_pty 0.4.2 to third_party/flutter_pty (MIT kept, SHELLX_PATCHES.md) and patch it: skip duplicate argv[0], UTF-8→UTF-16 via MultiByteToWideChar, ClosePseudoConsole + handle cleanup incl. failure paths, Job Object (KILL_ON_JOB_CLOSE, CREATE_SUSPENDED) with kill=TerminateJobObject, POSIX slave close + CLOEXEC + master close, stdout port closed on EOF not on exit code; CI desktop filter includes third_party/flutter_pty — the upstream plugin is broken on Windows and leaks fds on macOS; no adapter-only fix exists — cost if wrong: we maintain a ~1k-line fork; Windows C unverified until Windows CI runs
Task 3: Ruling: R2 delete obsolete Windows workarounds (ASCII short paths, ConsoleHostTracker, Toolhelp32 table, taskkill killer); keep windowsQuoteArg — root causes fixed in the fork — cost if wrong: re-add from 377d5b1
Task 3: Ruling: R3 POSIX kill = SIGHUP root first, then freeze (SIGSTOP) the descendant closure of every known victim to a fixpoint, SIGHUP+SIGCONT, grace, freeze again, SIGKILL — plan 03 contract says the whole tree dies — cost if wrong: brief SIGSTOP of processes that were going to die anyway
Task 3: Ruling: R4 no swallowed errors (root signalled even if ps fails; kill() catches + reports via onError with pid/reason only; spawn errors rethrown); R5 no POSIX tree kill after exit (stale pid); R6 stronger integration tests — cost if wrong: none
Task 3: fix round 1/5 dispatched to a FRESH implementer aac4d17e7a6474a6c (opus) — native C + design beyond the brief (Ruling: fresh, more capable implementer for round 1 because the fix is a plan correction, not a transcription slip), FIX_BASE 377d5b1
Task 3: minor (deferred): CommandRunner duplicates shellx_agent ProcessRunner (moot if taskkill code deleted); Windows helper placement
Task 3: fix round 1 commits e25d13a..e300de2 (8 commits; macOS unit 35/35, integration 12/12 repeated, build macos OK, shellx_agent 77/77; Windows C syntax-checked only against a stub Windows.h)
Task 3: Ruling: accept R3 amendment — freeze descendants while the shell still runs, then SIGHUP everything (shell always signalled, also when ps fails); the literal order failed the late-child case and stopping the shell first could leave a stopped zsh if the agent exits mid-kill — cost if wrong: none observed
Task 3: Ruling: output reader started before ResumeThread (CREATE_SUSPENDED) is equivalent to 'before CreateProcessW' — accept — cost if wrong: lost first bytes on Windows (Windows CI output test would show it)
Task 3: Ruling: exit codes lost when a dart:io Process runs (caffeinate per spec §8, ps) — fix in the vendored plugin: macOS captures exit status with kqueue EVFILT_PROC NOTE_EXIT|NOTE_EXITSTATUS (fallback waitpid, then -1) instead of changing the spec's caffeinate — the phone shows the exit code — cost if wrong: -1 shown in 'Phiên đã kết thúc'
Task 3: Ruling: Windows AssignProcessToJobObject failure must not fail the spawn — continue without the job (kill falls back to terminating the root, failure reported via onError) — cost if wrong: weaker tree kill only on machines that refuse job nesting
Task 3: Ruling: on natural shell exit clear JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE before closing the job (no tree kill after natural exit, same as POSIX R5) — cost if wrong: leftovers of an exited shell keep running on Windows as they do on macOS
Task 3: pre-review follow-up sent to aac4d17e7a6474a6c
Task 3: follow-up commit 6349844 (kqueue exit status; tolerant job setup; clear KILL_ON_JOB_CLOSE at natural exit; unit 36/36, integration 13/13 ×2, build OK); scoped re-review dispatched (opus) over e25d13a..6349844 (pristine vendor commit e25d13a verified separately)
Task 3: re-review (opus) — all 9 findings + R1–R6 + amendments ADDRESSED; pristine vendor copy verified by diff -r; no new Critical/Important
Task 3: minor (deferred → FOLD INTO FINAL FIX WAVE): sync-pipe write can raise SIGPIPE and kill the agent if the child exits before reading (TIOCSCTTY failure) → F_SETNOSIGPIPE on sync_pipe[1]; POSIX pthread_create/malloc failures still count as a successful spawn (Windows fails the spawn) → fail the spawn and clean up
Task 3: ⚠️ carry to Task 7/11 (quit/logout/shutdown path): await pending PTY kills before the agent exits — re-parented HUP-ignoring survivors frozen by the final freeze stay stopped forever if the agent exits mid-kill
Task 3: minor (deferred): errno read after forkpty's own close() (spawn_failed message may show wrong errno); slave on fd 0–2 keeps CLOEXEC after dup2 onto itself; docs say Windows leftovers 'keep running' but ClosePseudoConsole ends console-attached ones; 'could not terminate the job object' text in no-job mode; upstream: non-async-signal-safe calls between fork/exec, inherited signal mask, no timeout on ps, FlushFileBuffers on UI isolate; win32/ffi deps maybe unused
Task 3: WINDOWS CI CHECKLIST (must pass before desktop ships): (1) output right before exit delivered (pty_test 314-337, flaky risk); (2) kill() ends shell + detached hidden ping (job works); (3) leftover of naturally exited shell keeps running (read with 2); (4) two Vietnamese tests (cwd + env UTF-16); (5) output closes ≤2 s, nothing left behind, unstartable shell throws with no conhost; (6) pwsh/powershell echo shellx-ok (exe once); (7) MSVC compiles flutter_pty_win.c; (8) no 'started without a job object' log line. Windows 10 1809 behaviour unverified (CI is Server 2022)
Task 3: complete (commits 8558f00..6349844, review clean after fix round 1 + follow-up)
Task 4: implementer aa93e29f90167d90d (sonnet) dispatched, base 6349844
Task 4: implemented commits b606240 3db18d0 (storage 3/3, full 39/39); review dispatched (sonnet)
Task 4: review (sonnet) spec ✅ Approved; Important (plan-mandated): Windows storage doc says DPAPI .dat file — false for flutter_secure_storage_windows 4.1.0 (Credential Manager key + AES-GCM per-key .secure files)
Task 4: Ruling: fix the comment (no internal details) + correct spec §5.1 and the vi/en privacy pages on feat/shellx-v1 (e20364c) — a privacy page must not misdescribe storage — cost if wrong: none
Task 4: fix round 1/5 dispatched to aa93e29f90167d90d (FIX_BASE 3db18d0)
Task 4: fix round 1/5 (2 addressed, 0 open — accurate Windows storage doc; shared-instance wording; commits 3db18d0..70c788f)
Task 4: complete (commits 6349844..70c788f, review clean)
Task 5: implementer aed8f8ecaa6e9df1c (sonnet) dispatched, base 70c788f
Task 5: implemented commit f8d0ece (full 45/45; build macos OK; Windows paths unverified at runtime); review dispatched (sonnet)
Task 5: review (sonnet) spec ✅ (verbatim; pinned APIs verified) but Needs fixes — Important (plan-mandated): CaffeinateKeepAwake's _queue poisons after one failure (every later setEnabled rethrows the stale error, _apply never runs again) — reproduced
Task 5: Ruling: fix — each call returns its own result but the queue continues (queue = next.catchError(ignore)); fold in: SetThreadExecutionState returning 0 → throw to the caller; activationRequests compares the basename; test the caffeinate spawn-failure path (fail once, next enable works) — keep-awake is default-on per spec §8 — cost if wrong: none
Task 5: minor (deferred): activationRequests creates a new Directory.watch per call (single use today)
Task 5: fix round 1/5 dispatched to aed8f8ecaa6e9df1c (FIX_BASE f8d0ece)
Task 5: fix round 1 commit 40a9804 (48/48; queue recovers; SetThreadExecutionState 0 → StateError; exact basename); re-review dispatched (haiku)
Task 5: fix round 1/5 (3 addressed, 0 open — queue recovers after failed spawn; SetThreadExecutionState 0 → StateError; exact basename; commits f8d0ece..40a9804)
Task 5: complete (commits 70c788f..40a9804, review clean)
PAUSE (by design): Tasks 1–5 done. Task 6+ wait until plan 03's AgentService (Task 9 fix round) is reviewed; then merge feat/shellx-v1-agent-client into this branch and continue with Task 6 (carry: one shared SecureKeyValueStore/TrustedStore; TrustedDevice.pairingId; recovery from replaced; stop relay before api.logout(); SetQuitOnClose → hide to tray; await pending PTY kills before exit; SIGPIPE/pthread minors FOLD INTO FINAL FIX WAVE)
RESUME: merged feat/shellx-v1-agent-client (8550db8: AgentService with pairing ids + shellx_client + relay) into this branch (752e061; workspace list union); analyze clean, 48/48
Task 6: implementer ac2646a340beef051 (opus) dispatched, base 752e061
Task 6: implemented commit 24f0bd2 (63/63; deviations with tests: reconnectNow also recovers from replaced (4001) and is a no-op before start/after stop; evaluateUpdate returns null on malformed versions; clock injected into AgentService); review dispatched (sonnet)
Task 6: ⚠️ carry to Task 7: handleWake() calls reconnectNow() ONLY when the relay is disconnected (never after 4001, spec §12); create the single TrustedStore once in DesktopServices, not in the controller's build()
Task 6: ⚠️ carry to Task 8: tray 'Reconnect' item for the replaced state + new l10n label (vi/en)
Task 6: ⚠️ carry to Task 11: pass onError to FlutterPtyFactory.forCurrentPlatform and surface it; Ruling (e): add FlutterPtyFactory.killsSettled() (Future that completes when all in-flight tree kills finish) and await it with a timeout (e.g. 3 s) on quit and logout
Task 6: review (sonnet) spec ✅ Approved (deviations verified against real RelayConnection/compareVersions)
Task 6: ⚠️ carry to Task 7/11: appVersion must be PackageInfo.version (no '+build' suffix) or evaluateUpdate's strict semver gate disables update checks forever
Task 6: minor (deferred): PairingView.expiresAt and the code manager read the clock separately (countdown may end a few µs early)
Task 6: complete (commits 752e061..24f0bd2, review clean)
Task 7: implementer ae722e811018f50e6 (opus) dispatched, base 24f0bd2 (with rulings: single TrustedStore, stop relay before logout, handleWake only when disconnected, PackageInfo.version, awaitPtyKills seam)
Task 7: implemented commit abeb5c8 (118/118, 55 new; ruling tests fail against the brief's controller); beyond brief: 401 on revoke's DELETE (remote access off) signs out like 4002; token without device_id/user_id starts signed out; DesktopServices no longer const (owns TrustedStore); carry: Task 8 controller reconnect(); Tasks 9/10 tests use h.trusted; Task 11 killsSettled() + single bootstrap(); review dispatched (opus)
Task 7: review (opus) spec ✅ Approved — all §5.2 flows, §12 and the five rulings pinned by tests; two additions sound
Task 7: minor (deferred → FOLD INTO FINAL FIX WAVE): (1) a late logout HTTP (10 s give-up, request up to 20 s) nulls a NEW session's api.token via ShellxApi.logout's finally — fix in core (clear only if token == sent) or make signIn await the pending logout (bounded); (2) signIn has no in-flight guard (concurrent logins → 401 false sign-out); (3) bootstrap() not idempotent / sign-out during bootstrap undone; (4) off→on toggle during a slow stop overlaps two runtimes (old upgrade can 4001 the new link) — await the pending stop
Task 7: minor (deferred): launch-at-startup revert may show the wrong value; 'doubled signal' test doesn't exercise _revoking; keychain failure in _clearSignedInData leaves a signed-in-looking limbo; offline sign-out leaves relay pairings/token until a later login
Task 7: complete (commits 24f0bd2..abeb5c8, review clean)
Task 8: implementer a4283cbb708aa2c96 (sonnet) dispatched, base abeb5c8 (+ Ruling: tray Reconnect item for replaced + AgentController.reconnect() + vi/en strings)
Task 8: implemented commit d6e20ce (tray 18/18, full 138/138; Reconnect action + reconnect() + vi/en strings); ⚠️ carry to Task 9: route TrayAction Reconnect → AgentController.reconnect(); instantiate TrayManagerHost/TrayPresenter with the real isWindows; review dispatched (sonnet)
Task 8: review (sonnet) spec ✅ Approved (icons byte-identical to a fresh generator run; key round-trip adversarial ids OK)
Task 8: ⚠️ carry to Task 9: onMenuItemClick fire-and-forgets onAction — the action router must catch every error (no unhandled Future errors)
Task 8: minor (deferred): status line shows 'Mất kết nối — đang thử lại…' for revoked/stopped (transient); loading phase shows 'Chưa đăng nhập'
Task 8: complete (commits abeb5c8..d6e20ce, review clean)
Task 9: implementer aef1c1f69415122d0 (sonnet) dispatched, base d6e20ce (+ rulings: route Reconnect; TrayActions.handle never throws; close hides to tray incl. SetQuitOnClose check; h.trusted)
Task 9: implemented commit 8f5a424 (18/18, full 154/154); setPreventClose(true) short-circuits WM_CLOSE before SetQuitOnClose — no main.cpp change (Windows CI to confirm hide-to-tray); TrayActions.handle never throws (notifier errorUnexpected(code)); review dispatched (sonnet)
Task 9: review (sonnet) spec ✅ Approved (close-to-tray verified in window_manager + runner sources); 'Important' = report test-count miscount (16 in window_flow_test, not 18) — Ruling: parked, controller re-ran the full suite: 154/154 — cost if wrong: none
Task 9: minor (deferred → FOLD INTO FINAL FIX WAVE): WindowRouter._leave unawaited(completeOnboarding()) can surface an unhandled Future error if the settings write fails
Task 9: minor (deferred): WindowPresenter.apply relies on in-order channel calls (no explicit serialization); no standalone test for a second confirm while one is open
Task 9: complete (commits d6e20ce..8f5a424, review clean)
Task 10: implementer a613b1112764cbb49 (sonnet) dispatched, base 8f5a424 (+ Ruling: validPasswordLength counts code points like the relay)
Task 10: implemented commit cf70ad9 (24 focused, full 178/178; code-point password length; qr_flutter matched); review dispatched (sonnet)
Task 10: review (sonnet) spec ✅ Approved (Enter double-submit verified harmless; QR data exact and never shown/logged)
Task 10: minor (deferred): password controllers not cleared after failure/success; duplicated submit shape
Task 10: complete (commits 8f5a424..cf70ad9, review clean)
Task 11: implementer afa6e21dcae9eae59 (opus) dispatched, base cf70ad9 (carried rulings: PackageInfo.version; PTY onError surfaced + killsSettled() → awaitPtyKills; single stores; bootstrap once; tray/window wiring; optional local-relay launch check)
Task 11: implemented commits d7064c2 060ce7d 42a8d84 (184/184, integration 13/13; real launch: login window + grey tray icon, single instance OK, local relay reached); concerns: bootstrap() throwing leaves the app loading with no window (FOLD candidate); PTY notifications not rate-limited, body untranslated; GUI sign-in/onboarding/pairing not exercised (human step); review dispatched (opus)
Task 11: review (opus) spec ✅ (order exact; rulings wired; killsSettled correct) but Needs fixes — Important (plan-mandated): any throw after the single-instance lock (window_manager init, PackageInfo, notifier setup, prefs, DesktopServices assert) leaves an invisible process holding the lock (every later launch exits silently)
Task 11: Ruling: fix — guard the post-lock startup: on failure log runtimeType, show a visible error (Windows MessageBox localized; macOS best-effort notification), release the lock, exit(1); fold in: bootstrap() failure → notify + signedOut (never stuck in loading); PTY-problem notification body localized with pid only (reason in the log) and coalesced; debounce activation requests; quitApp: timeout on tray destroy so exit always happens; remove the ⌘Q key equivalent (Quit must go through the tray's shutdown path) — cost if wrong: none
Task 11: minor (deferred): macOS Finder reopen of a running agent goes through LaunchServices reopen (no applicationShouldHandleReopen) — tray icon remains the entry point
Task 11: fix round 1/5 dispatched to afa6e21dcae9eae59 (FIX_BASE 42a8d84)
Task 11: fix round 1 commit 8bacb2f (201/201, integration 13/13, build; forced startup failure → exit 1 with one log line); Ruling: accept releasing the lock BEFORE showing the blocking startup error (a relaunch during a modal MessageBox must not be turned away) — cost if wrong: none; notes: ⌘Q removal verified by xib diff only; macOS notifications use a deprecated API (banner setting) — check in the manual run; re-review dispatched (sonnet)
Task 11: fix round 1/5 (6 addressed, 0 open; commits 42a8d84..8bacb2f)
Task 11: complete (commits cf70ad9..8bacb2f, review clean)
FINAL: all 11 tasks complete; whole-branch review dispatched (opus) over c29cbdd..HEAD limited to apps/desktop, third_party/flutter_pty, .github, docs (plan 03 packages reviewed separately)
FOLD (from plan 03 final wave): FlutterPtyAdapter.kill must be a no-op once the shell has exited on BOTH platforms per the updated overview §5.6 Pty contract (POSIX already guarded by R5; confirm Windows job path)
FINAL: review (opus) 'With fixes' — Important: I1 blocking PTY write freezes the agent isolate (macOS); I2 relay-supplied update URL opened unchecked (file:/UNC/options → local program launch); I3 late logout wipes a new token (core finally); I4 sign-out not fail-closed; I5 login page drops keychain errors unhandled; + FOLD F6–F16
FINAL: Ruling: fix wave = I1 (POSIX writer thread + bounded queue; Windows drop FlushFileBuffers) + I2 (https + shellx.pro hosts only) + I3 (core: clear token only if unchanged) + I4 (clear local state first, throwaway API logout) + I5 + F6 (core stop() awaits in-flight dial, bounded) + F7–F16 + T3 doc (final-fix-findings.md) — cost if wrong: diff churn; Windows native unverified until CI
FINAL: merged feat/shellx-v1 (plan 03 final) into desktop first (12e8fd5; 201/201)
FINAL: fix wave dispatched a6dc0ef983a8d6d2e (opus), FIX_BASE 12e8fd5
FINAL: fix wave commits 12e8fd5..f47c8b0 (18; desktop 266, PTY integration 21, core 261, agent 167, client 98; build; real launch incl. macOS reopen); notes: tests-only native hook pty_debug_fail shipped; I4 local data cleared when stop is invoked; F6 stop settling up to 15 s; new API createApi/shutdownTimeout; Windows unverified (pty_write w/o FlushFileBuffers, kill-after-exit no-op) — CI checklist additions in the report; scoped re-review dispatched (opus)
FINAL: scoped re-review (opus): I1–I5, F6–F16, T3 all ADDRESSED; desktop 266/266 re-run by reviewer; ready to merge. New Minor: (a) a trusted list that fails to clear outlives user_id → carries into the next account's sign-in; (b) shutdown/_handleRevoked may wait ≤15 s for an in-flight dial to settle (bounded). Out of scope: Ctrl+C queued behind a big paste (by design), pty_debug_fail compiled into release (inert), percent-encoded hosts accepted by isTrustedDownloadUrl (harmless), pre-existing sign-in-during-bootstrap race, resize may overtake queued input.
FINAL: Ruling: fix (a) now as a tiny residual follow-up (keep user_id when the trusted clear fails, so the account-switch check still clears it) plus the host-charset tidy — security-relevant, two small edits, cheaper than tracking — cost if wrong: one extra small commit
FINAL: Ruling: defer (b) — bounded (Quit has a 10 s deadline; 401 path ≤15 s lag), responsiveness only — cost if wrong: a slow Quit on a black-holing network
FINAL: Ruling: defer pty_debug_fail #ifndef, sign-in-during-bootstrap race (login page only shows after bootstrap settles), resize ordering (disclosed) — cost if wrong: none user-visible
FINAL: residual fixes 3ce3bbc (trusted clear failure keeps user_id; regression test red first) + f71c8eb (ASCII hostname check); desktop 269/269; controller read the diff — clean
FINAL: plan 04 complete — merging feat/shellx-v1-desktop (f71c8eb) into feat/shellx-v1

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

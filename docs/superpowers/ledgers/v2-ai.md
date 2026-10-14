# V2 AI — execution ledger (branch shellx-v2)

## V2-1a (foundation) — planning rulings

Plan: `docs/superpowers/plans/2026-10-14-v2-ai-foundation.md` (spec `docs/superpowers/specs/2026-10-14-ai-pane-design.md`, approved by the user with "bắt đầu làm đi", 2026-10-14). The user fast-tracks: no separate plan-review stop.

Ruling R1: host code (login env, agent catalog/resolver, process, crash registry, checkpoints, runtime) lives in `package:shellx_ai/host.dart` (pure Dart), not `apps/desktop/lib/src/ai/` — `dart test` with real processes and git on macOS and the Windows CI; the desktop only wires it (V2-1b) — cost if wrong: one move.
Ruling R2: Gemini CLI runs from the pinned npm package `@google/gemini-cli@0.64.0` (bin from its package.json, `--acp`), like the ACP registry, not `gemini` from PATH; OpenCode stays `opencode acp` from PATH — cost if wrong: one catalog entry.
Ruling R3: checkpoints use plumbing (`add -A`, `write-tree`, `commit-tree`, `update-ref`), never `git commit`; every call passes `-c core.autocrlf=false -c core.fsmonitor=false -c commit.gpgSign=false -c gc.auto=0 -c maintenance.auto=false -c core.logAllRefUpdates=false -c core.hooksPath=<shadow>/hooks`; `$GIT_DIR/info/attributes` = `* -text -filter -ident -working-tree-encoding`; inherited `GIT_*` removed — no hook, no GPG, byte-exact restore — cost if wrong: undo off, never the user's repo.
Ruling R4: before every snapshot, nested repositories (untracked entries ending in `/`) and new files over 50 MiB go into the managed `info/exclude` and out of the shadow index — verified 2026-10-14 (git 2.56): with GIT_DIR elsewhere, `git add -A` aborts the whole add on a nested repo without commits — cost if wrong: such files cannot be undone.
Ruling R5: restore writes back files present in the checkpoint with `git restore --source --worktree --pathspec-from-file`, and deletes in Dart the files absent from it plus the folders left empty — cost if wrong: an empty folder stays.
Ruling R6: a remembered "Bypass permissions" mode is never re-applied to a new session (Review Focus 6, never auto-allow) — cost if wrong: one extra click.
Ruling R7: V2-1 splits into V2-1a (pure-Dart foundation, this plan) and V2-1b (desktop tab) — the foundation is testable without Flutter.

## V2-1a — baseline (2026-10-14, before Task 1)
0e71bb6 docs(v2): spec V2-1 — desktop AI tab without a terminal
- Dart SDK version: 3.11.1 (stable) (Tue Feb 24 00:03:07 2026 -0800) on "macos_arm64"
- git version 2.56.0
- v26.11.1
- agents on PATH: claude 
- shellx_core: 341 passing; shellx_agent: 778 passing (dart test, 2026-10-14)

## V2-1a (foundation) — execution

Task 4 (spec §12 checks, run by the controller, 2026-10-14):
- §12.1 Claude recorded (adapter 0.90.0, bin `dist/index.js`, engines node >=22; node v26.11.1). Protocol 1, `loadSession` true, prompt → `end_turn`, hello.txt edited. 57 messages kept (5 `_`-extension messages dropped; `_meta` stripped; project → `/project`; the user's installed plugin/skill commands and plugin agent personas removed). Recording cost $0.26 on the user's own account. Findings:
  - `tool_call` arrives with a generic title ("Read File", "Edit", "Terminal") and empty rawInput; `tool_call_update`s refine title ("Read hello.txt", "ls"), locations, rawInput and the diff — the card must show the merged, updated title.
  - Only Edit asked permission (default mode lets Read and a read-only `ls` run); options were allow-once / allow-with-updates ("Yes, allow all edits during this session") / reject — as in the spec.
  - `usage_update` carries `size` 1 000 000 and a `cost`; `session_info_update` with the title arrives after the turn; the prompt result carries an extra `usage` object (ignored).
  - `configOptions`: mode, model, effort (`thought_level`), fast (`model_config`, a select on/off — not a boolean), agent (no category; lists installed plugin personas).
  - `initialize` also sends `auth.logout`, `providers` (unknown, ignored) and session capabilities list/resume/close/delete/fork/additionalDirectories.
  - `session/load` replays the user message, the finished tool calls (final titles) and the agent text as one chunk; its result repeats `sessionId`, modes and configOptions.
- §12.2 Codex: not installed here — pending manual (spec §9). `@agentclientprotocol/codex-acp@2.2.2`: bin `dist/index.js`, no `engines` field (npm view).
- §12.3 D17 Flutter packages: moved to plan V2-1b.
- §12.4 Gemini CLI without `fs/*`: not installed here — pending manual. `@google/gemini-cli@0.64.0`: bin `bundle/gemini.js`, engines node >=20.
- §12.5 Claude elicitation form for multiple-choice: not observed (the recording asked no question) — pending manual.
- No finding contradicts the spec.

## V2-1b (desktop) — execution

Prerequisite (2026-10-14): `git log --oneline -1` on shellx-v2: `f6a5946 fix(v2-ai): AiHost.startup after a launch does not sweep the agents of this run` (V2-1a Tasks 1–9 landed); apps/desktop `flutter test`: 3091 passing, 10 skipped (`All other tests passed!`).
- Task 1 (D17): flutter_markdown_plus 1.0.12, re_editor 0.10.0, re_highlight 0.0.3, diff_match_patch 0.4.1 resolve and build on Flutter 3.41.4 (macOS debug build ok); re_editor needs autofocus false + showCursorWhenReadOnly false in tests.
- Task 30 (2026-10-14): flutter analyze: `No issues found!`; flutter test: 3248 passing, 10 skipped; flutter build macos --debug: `✓ Built build/macos/Build/Products/Debug/ShellX.app` (the build only rewrites the `COCOAPODS:` version line of `macos/Podfile.lock` with the local CocoaPods 1.17.0; not committed); Windows (`windows-check` or a PC): pending; packages/shellx_acp and packages/shellx_ai untouched by V2-1b: yes (the diff since Task 1 is empty).
- Review greps (§8, D20, D21): `debugPrint(` only `ai_startup.dart` `'ShellX: stopped $stopped stray agent(s)'`, a count; "Claude Code" only `agentNamesClaude` and `aiSettingClaudeDesc`, EN and VI; `hide-claude-auth`: nothing; `answerPermission(` only `ai_permission_bar.dart` (a key or a click).
- ⚠ Manual checks (spec §9): 1 Claude: pending; 2 Codex: pending; 3 Gemini CLI, OpenCode: pending; 4 Telex, VoiceOver, Narrator: pending; 5 large project: pending; 6 proxy, no Node, no Command Line Tools: pending; 7 drop, processes, .cmd shim, run sheet colours, keys stay in the pane: pending.
- Findings that contradict the spec or the rulings B1–B16: none. The landed V2-1a against its plan: `AiRuntime.start` checks the folder with async `Directory(cwd).exists()` (the plan had `existsSync`), real IO that never completes under a widget test's fake clock; `test/support/ai_fakes.dart` (Task 10) answers that check from `existsSync()` in the test's zone, for the fake runtimes' folders only. Nothing else needed a change: the desktop code compiled against the landed API as the plan wrote it.

V2-1a results (2026-10-14, subagent-driven; each task reviewed, fix rounds re-reviewed):
- Task 1 JSON-RPC 38ded65 · Task 2 ACP types + schema conformance a19bab7..c598566 · Task 3 AcpClient + fake agent ba7c0ef..c55207f · Task 4 recorded Claude session 26e3786..e5097f9 · Task 5 session model d948971 · Task 6 login env/catalog/resolver da8c1ab · Task 7 process/registry 5e04dc8 · Task 8 checkpoints 5d5608f..a802e4b · Task 9 runtime/host ef8272e, f6a5946, b5c5d4f.
- Suites at b5c5d4f: shellx_acp 87, shellx_ai 383, shellx_core 341, shellx_agent 778, shellx_client 113, shellx_e2e 16 (+9 skipped), desktop 3096 → 3253 with V2-1b, mobile 839.
- Review fixes beyond the plan (each with a failing test first): redacted toString pinned for every ACP class by a source scan; the fake agent ends a turn cleanly when the client hangs up mid-question; on Windows an explicit `.cmd`/`.bat` agent is never run; checkpoints clear a stale `index.lock`, never delete `.git` paths, retry a failed git lookup, init with `--template=` (a global template hook cannot veto checkpoints); a resumed tab keeps its `session/load` replay after a sign-in or setup card; Stop clears "needs input"; undo is re-probed after a transient failure; `AiHost.launch` waits for the crash sweep.
- Privacy/safety sweep (Task 10 Step 2): no content logging in either package, no `runInShell`, no `--hide-claude-auth`, the only `PermissionSelected` is the user's own pick, model and protocol libraries are `dart:io`-free.
- Pending manual (spec §9): Windows (CI and a real machine), Codex/Gemini/OpenCode sessions, Telex and screen readers, a ~100 000-file project.

V2-1b results (2026-10-14/15, away mode; patch series of 30 tasks, then reviews):
- Reviews: six cluster reviews (1–9, 10–11, 12–16, 17–19, 20–24, 25–29) → fix wave F1–F3 (parallel worktrees, cherry-picked); final whole-branch review (opus, 0 Critical / 6 Important / 11 Minor) → fix wave G1–G3 + follow-ups G1b, G3 rounds 1–3; every fix round re-reviewed. Ledger: `.superpowers/sdd/2026-10-14-v2-ai-desktop/progress.md`.
- Fixed from the final review: a home folder or disk root is never a default project (and gets no checkpoints / `@` index); a paste with text + picture keeps the text; question cards keep their picks off-screen; "Check again" after installing Node/git/CLI (Windows PATH from the registry); output capped by characters (1 MB line 22.8 s → 5 ms); a session that cannot reopen offers "Start a new session"; quit asks while AI works; stopping an agent kills its leftover children (never ShellX or its ancestors; Windows pid by pid, never `taskkill /T`); restored titles kept; pane-level 1–9/Esc; Time Machine exclusion of the AI data.
- Suites at 39406cb (main): shellx_acp 87, shellx_ai 536, shellx_core 341, shellx_agent 778, shellx_client 113, shellx_e2e 16 (+9 skipped), desktop 3544 (+5 skipped), mobile 839.
- Launch smoke (macOS, isolated profile: bundle id `pro.shellx.desktop.smoketest`, scratch HOME): the app stays up, AI first tab renders (widget tree read over the VM service), no exception.
- Not fixed: M-10 (with the background service on, an AI tab's terminal pane can come back as its own tab after a relaunch — needs a restore-schema change). Out of the AI path, pre-existing: `taskkill /T` in `process_tree.dart` via `pr_status.dart` and `agent_command_runner.dart`.
- Windows CI: branch `windows-check/v2-ai` at 39406cb (result to be read in GitHub Actions). Manual checks of spec §9: all pending.

## V2-2a (phone) — execution

- Tasks 1–11 subagent-driven in worktrees, pair reviews (1+2, 3+4, 5+6, 7+8, 9+10) and a review of Task 11; integrated on `v2-2-int` (shellx-v2 + V2-2) and reviewed whole (opus: 0 Critical / 4 Important / 11 Minor) → fix wave P1 (hub, pushes, resync) + Task 9 rounds; every round re-reviewed. Ledger: `.superpowers/sdd/2026-10-14-v2-2-phone-ai/progress.md`.
- Compatibility matrix (Task 12 Step 2): shellx_core compatibility 3, shellx_client compatibility 2, mux/router 7 — all pass (old phone ↔ new desktop, new phone ↔ old desktop, new window ↔ old service).
- Privacy sweep (Step 3): only error runtimeTypes logged; no config path from phones; answers only from the hub's checked `_answer`, the controller's tap methods and the source's forwarding; `remote` and the client are `dart:io`-free.
- Rulings beyond the spec (spec §13): resync when > 120 items behind; pushes when the watching phone is silent 10 s or leaves, and after 60 s even if the desktop shows the session; question pushes carry no question text; `on_computer` refusal for no-approval options from a phone; D15 starts only never-started runtimes; one re-attach after `unavailable`; a 400 ms settle guard on the phone's permission/question panels and Stop.
- Manual checks of spec §10: all pending (real phone, push on a locked screen, Wi-Fi drop mid-stream, a 500-item session, VoiceOver/TalkBack, Telex).
- Next (spec §11.2, V2-2b): answering on the notification, config changes from the phone, images and the voice composer, undo on the phone, full big cards, session history, AI sessions on the machine list, reconnect after a desktop restart, "You · from the phone" on the desktop.

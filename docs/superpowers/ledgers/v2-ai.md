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

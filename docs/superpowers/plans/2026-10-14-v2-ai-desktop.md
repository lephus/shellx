# ShellX V2-1b — Desktop AI tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the AI tab of the desktop app on top of the V2-1a foundation. A person who does not want a terminal opens "New AI session", chats with Claude (or Codex, Gemini CLI, OpenCode, a custom ACP agent), sees every action as a card, answers permission requests with one key, reviews diffs and undoes a turn, and gets the tab back after a restart. Nobody has to open a terminal. Terminal users keep today's app exactly as it is.

**Architecture:**
- **Tab model (D2/D3).** `TerminalTab` gains `kind` and `aiPanes`. An AI tab has a synthetic id (≥ `kSyntheticTabIdBase`) and one AI pane: a negative leaf in the A3 pane tree, whose record (`AiPaneState`: agent, folder, title, session id) lives in the tab list. `focused` becomes `PaneSession?`, so the compiler finds every reader. A terminal pane can join the AI tab below it (72 %).
- **Runtimes.** One `AiRuntime` (V2-1a, `package:shellx_ai/host.dart`) per AI pane, created lazily by the desktop registry `AiRuntimes` (`apps/desktop/lib/src/ai/ai_runtimes.dart`) through a factory provider. Widget tests swap that provider for `FakeLauncher` from `package:shellx_ai/testing.dart`, so no process, login shell or git ever runs under fake async.
- **The registry also wires the rest of the app:**
  - the runtime's title and session id go into the tab model (sidebar, window title, `layout.json`);
  - its `AiStatus` goes into A12's `AgentStatusNotifier` (badges, A4 notifications, CLI events, D13);
  - quitting stops every agent.
- **Smoothness.**
  - Views never listen to `AiSessionState` directly. `AiFrameNotifier` turns its hundreds of updates per second into at most one notification per frame.
  - The timeline is a virtualized `ListView.builder` that reuses each item's widget until the item's `rev` changes. Markdown is split into blocks, so only the last block of a streaming message rebuilds.
  - Diffs and project file indexes run off the UI isolate.
  - The login environment and agent readiness warm up after the first frame.
- **UI.** `apps/desktop/lib/src/ui/ai/` holds:
  - the pane: a 34 px header, a conversation column of at most 760 px, a dock (plan, permission bar, queue, composer), a 268 px Changes/Files panel and overlays (viewer, run sheet, resume card);
  - Settings › Agents, onboarding's question and the one-time intro card.
- **Keyboard.** The window hands one terminal focus node to the focused pane. An AI pane holds it in a `Focus` of its own, with a key handler that replaces the one the last terminal view left on it. It passes the keyboard to its own input node (composer, folder field). Keys typed in the AI pane never reach a hidden shell.
- **Restore (D14).** `layout.json` stays `v: 1` and gets a top-level `aiTabs` array. The V1 parser ignores it; a frozen copy of that parser pins this in a test.

**Tech Stack:** Flutter 3.41.4 (`~/fvm/versions/3.41.4/bin`), Dart ^3.11, Riverpod 3 (`flutter_riverpod` 3.3.x), `flutter_test`, the vendored `xterm` and `flutter_pty`, `package:shellx_ai` and `package:shellx_acp` (V2-1a). D17 packages pinned exactly: `flutter_markdown_plus 1.0.12`, `re_editor 0.10.0`, `re_highlight 0.0.3`, `diff_match_patch 0.4.1`.

**Spec:** `docs/superpowers/specs/2026-10-14-ai-pane-design.md` (binding, Vietnamese) and the foundation plan `docs/superpowers/plans/2026-10-14-v2-ai-foundation.md` (its Interfaces blocks are the API this plan consumes). Layout: `docs/superpowers/design/2026-10-14-ai-pane-demo/` (binding for layout; colours and sizes from `ShellxDesktopColors`, `ShellxSpace`, `ShellxSizes`, `ShellxText`).

## Prerequisite and how this plan was made

Work on branch `shellx-v2`. Tasks 1–9 are **independent of V2-1a**. They only touch `apps/desktop` and can start now, in a separate worktree (`superpowers:using-git-worktrees`), while V2-1a Tasks 5–10 land in `packages/`. Tasks 10 and later need V2-1a Task 9 (`AiHost`/`AiRuntime`) on `shellx-v2`; merge or rebase the worktree onto it first.

How this plan was checked, before writing (2026-10-14):

**Reading:**
- the spec, the demo (`demo.js` layout, strings and states), the V2-1a plan (header, rulings, every Interfaces block, and the full code of `AiSessionState`, `Timeline`, `AiRuntime`, `AiHost`, `FakeLauncher`), the ledger, and every desktop file named below;
- the reader list of spec §2 was re-grepped: `searchAllSources` (`ui/config/search_all_overlay.dart:34`) indexes `tab.panes[id]!` for every leaf. It crashes on an AI leaf, and the analyzer cannot see it.

**A scratch copy** of the repo (`git archive HEAD`, outside the repo, its own `pub get --offline`):
- Making `focused` nullable gives 23 analyzer errors in `lib/` and 125 in `test/`. Task 3 fixes the `lib/` ones by hand (the exact edits are below). The `test/` ones are fixed by two scripts given in Task 3 (insert `!`, then remove the `!` the analyzer calls unnecessary).
- After that, and with `isSplit = layout is PaneSplit` and `paneCount = paneOrder.length`, **the whole desktop suite passed: 3094 tests, 10 skipped.**
- Task 3's model tests pass. Task 2's strings generate, and the l10n tests pass.
- The D17 packages resolve **offline** with this workspace on Flutter 3.41.4 (`markdown 7.3.1`, `isolate_manager 4.1.5+1` come with them). A widget smoke test of all four passes. `re_editor` leaves a cursor-blink timer unless `autofocus: false, showCursorWhenReadOnly: false` (Task 1 pins this). Its highlighter already runs in an isolate.
- `package:shellx_ai`, extracted from the V2-1a plan's code into the scratch copy, analyzes clean. Tasks 10 onwards were compiled against it.

**Checks before Task 10.** If V2-1a's landed API differs from the names used here:
- the V2-1a Interfaces blocks are the contract: adapt the call, not the foundation;
- record the difference in the ledger.

Run first, and record in the ledger under a new heading `## V2-1b (desktop) — execution`:

```bash
git switch shellx-v2 && git log --oneline -1
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test 2>&1 | tail -1; cd ../..
```

## Rulings (deviations from the spec, each with "cost if wrong")

- **B1 — `focused` is null whenever the focused pane is not a terminal pane**, also in an AI tab that has a terminal pane while the AI pane has the focus. The spec says "null when the tab has no terminal pane". This version is stricter, so copy, paste, find and copy mode never reach a terminal the user is not in. *Cost if wrong:* to act on that terminal, the user clicks it first.
- **B2 — `isSplit` means "the layout is a split", and `paneCount` counts leaves (the A6 rule).** Closing the terminal pane of an AI tab then keeps the tab (D3). For terminal tabs nothing changes: the full suite passes. *Cost if wrong:* none known.
- **B3 — an AI tab's terminal pane is not saved.** `aiTabs[].layout` is the AI leaf `{"ai": key}` alone; the parser accepts any tree that contains that leaf. After a restart the AI tab comes back without its terminal pane. *Cost if wrong:* one click on "Terminal", and that pane's scrollback is not restored.
- **B4 — `aiTabs` entries carry four more keys than D14 lists:** `name` (the user's tab name), `agentName`, and A11's `pinned`/`desc`/`status`, written only when set. *Cost if wrong:* keys V1 never reads.
- **B5 — custom agents are not reported to the A12 model**, because `AgentKind` has no value for them. Their sidebar row shows the agent's name alone, and their pane header shows the runtime's own state (Starting… / Running · 0:12 / Needs input / Idle, Task 17). They raise no system notification and no CLI `agent.status`. *Cost if wrong:* one enum value and four switch cases later.
- **B6 — AI panes use the AI agent's name** ("Claude", D21) in their A12 badge text and notifications, not A12's "Claude Code". The A12 quiet decay (20 s without output turns "running" into "idle") is off for AI panes, because their runtime knows when a turn runs. *Cost if wrong:* none.
- **B7 — "Choose project folder" is a typed path, validated as absolute and existing**, like Settings › Projects. No native folder picker: that would be a native plugin and a pinned version. *Cost if wrong:* add `file_selector` later.
- **B8 — in an SSH workspace, `new_tab` and `+` stay terminal tabs even with `new-tab-kind = ai`.** The agent runs on this computer, but the workspace's folder is on the server. *Cost if wrong:* one menu click.
- **B9 — `aiNodeMissing` takes the version as a placeholder** ("{agent} needs Node.js {version} or newer"), because Codex and Gemini need 20. For Claude it reads exactly as the spec. *Cost if wrong:* none.
- **B10 — closed AI tabs are not offered by ⌘⇧T (A11 D14), and pane moves refuse AI tabs both ways** (break, join, swap, "Move pane to tab"). *Cost if wrong:* the terminal pane of an AI tab cannot be moved out.
- **B11 — a restored AI tab starts its agent when it is first shown** (selected and laid out). There is no "Resume" click: the "Resume session" card shows while `session/load` replays. *Cost if wrong:* an agent starts when the user only looks at the tab.
- **B12 — @-mention and the Files panel use ShellX's own `.gitignore` matcher** (the project's `.gitignore` files; no global excludes, no `.git/info/exclude`) and never run git against the project's own `.git`. *Cost if wrong:* a file that only a global excludes file hides shows up.
- **B13 — the `new-tab-kind` row is the last row of Settings › General**, after the update row, so the rows above keep their place (the A12 update tests reach the update button without scrolling). *Cost if wrong:* the row sits lower on the page.
- **B14 — the undo dialog is a three-button `showDialog`, with the first focus on Cancel.** The window router's confirm has two buttons. *Cost if wrong:* none.
- **B15 — markdown from the agent never loads images** (the alt text shows instead), and links open only on click, http/https only (§5). *Cost if wrong:* no inline pictures from agents.
- **B16 — "Reviewed" (§4.4) is tied to the file's change as the panel sees it** (its kind and its +/− counts), not to a hash of its bytes; another edit with the very same counts keeps the mark. Hashing every changed file on each refresh would read them all on the UI side. *Cost if wrong:* a mark survives a same-size re-edit.

## Global Constraints

- **Branch and scope:**
  - Branch `shellx-v2` only.
  - Never touch the relay, `packages/shellx_core/lib/src/protocol/`, the daemon (`daemon_main.dart`, `src/mux/*`) or `apps/mobile`.
  - Never change `packages/shellx_acp` or `packages/shellx_ai` (V2-1a owns them); consume them only.
- **Where code goes:**
  - New code goes in `apps/desktop/lib/src/ai/` (non-UI) and `apps/desktop/lib/src/ui/ai/` (widgets).
  - Additions allowed elsewhere: one tab kind, the settings keys `new-tab-kind`, `ai-agent-claude` and `ai-checkpoint-days`, the actions `new_ai_session` and `new_terminal_tab`, ARB strings, and the `aiTabs` key in `layout.json`.
- **Layout:**
  - AI pane header 34 px; conversation column max 760 px; right panel 268 px; composer max 140 px.
  - The terminal pane under the AI pane: split top–bottom, the AI pane on top at 72 %.
- **Look:**
  - `ShellxDesktopColors` / `ShellxSpace` / `ShellxSizes` / `ShellxText` only.
  - No looping animation.
  - Transitions ≤ 150 ms, only on a user action, through `ShellxMotion.of` (reduced motion → 0).
- **Keys:**
  - `new_ai_session` = ⌘⇧E / Ctrl+Shift+E.
  - Permission bar: 1–9 pick `options` in the agent's order. Esc picks the first `reject_*`; with none, it answers `cancelled`.
  - The bar never takes the focus. When the composer has text, or the IME is composing, digits go to the composer.
  - Keys act on key-down.
- **Turns:**
  - Esc with no permission pending → `session/cancel`; the UI shows "Stopping…" at once. "Force stop" appears after 10 s.
  - At most 5 queued prompts.
  - Enter sends unless the IME is composing; Shift+Enter is a new line.
- **Restore:**
  - `layout.json` stays `v: 1`, with a top-level `aiTabs`.
  - AI tab keys sit in `workspaces[].tabs` in sidebar order.
  - Never any conversation content.
  - The V1 parser (= `restore_snapshot.dart` at `164bba6`, identical to HEAD) must still load the file.
- **Privacy (D20, §5):**
  - Never log prompts, agent text, tool output, paths or file names. Log only agent names, event kinds, counts and exit codes (`debugPrint('…: ${error.runtimeType}')` style).
  - `AiPaneState.toString()` is `'…'`.
  - stderr is shown only in "View log".
- **Credentials (D8, D21):**
  - ShellX never reads, stores or relays a credential.
  - The run sheet's output is never parsed or kept.
  - Never pass `--hide-claude-auth`; never put any `SHELLX_*` variable in an agent's environment.
- **Naming:** "Claude" (or "Claude Agent") in menus and feature names; "Claude Code" only in descriptions ("Runs Claude Code …").
- **Permissions:** nothing ever picks an `allow_*` option for the user.
- **Elicitation URLs:** http/https only, opened after a click, the full URL shown first.
- **Smoothness:**
  - Frame budget: no synchronous file system or process call on the UI isolate in a hot path. Line diffs over 2 000 lines, project file indexes and big file reads run through `aiOffThreadProvider` (`Isolate.run`); tests swap it for an inline runner.
  - Views listen to `AiFrameNotifier` (one notification per frame), never to `AiSessionState` directly.
  - Timeline items reuse their widget until `rev` changes; markdown re-renders only its last block while streaming.
  - Virtualized lists only: no `shrinkWrap` list of all items.
  - Stick to the bottom only while the user is there, with "Jump to latest" otherwise.
  - Tool output shows the first and last 200 lines, with "Show all N lines"; collapsed bodies are not built.
- **Warm start:** after the first frame, resolve the login-shell environment and the agents' readiness in the background (`startAi` → `aiReadinessProvider.warmUp`). `AiHost.startup()` runs once per launch and is never skipped: V2-1a's `launch` waits for its sweep.
- **Instant feedback:**
  - a new AI tab shows in the same frame (its runtime is made right after it, never while building);
  - a sent prompt shows at once, and Stop shows "Stopping…" at once;
  - a hidden pane's views hear nothing until shown (`AiFrameNotifier.active`).
- **Tests:**
  - `flutter_test` only, with this repo's helpers (`pumpConfiguredWorkspace`, `cliContainer`, `FakeLocalSessions`, `TestHarness`, `FakePtyFactory`).
  - No real `dart:io` async call inside `testWidgets`: inject seams (`aiRuntimeFactoryProvider`, `aiReadinessSourceProvider`, `aiPtyFactoryProvider`, `aiProjectFilesProvider`, `aiOffThreadProvider`, `aiFolderExistsProvider`, `aiMakeFolderProvider`, `aiDeleteCheckpointsProvider`, and the pane hooks `AiPaneUi.clipboardImage` / `readImageFile`).
  - Real FS in plain `test()` only, in temp dirs.
- **Commands** (run from `apps/desktop`):
  - test: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test <file>`;
  - analyze: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze` (must print `No issues found!`);
  - format: `PATH=~/fvm/versions/3.41.4/bin:$PATH dart format <files>`, only on what the task touches: at HEAD `lib/src/platform/scroll_trace.dart`, `lib/src/ui/settings/pages/projects_page.dart`, `lib/src/ui/terminal/session_sidebar.dart`, `test/ime/ime_in_place_edit_test.dart` and `test/platform/single_instance_test.dart` are not formatter-clean (Task 19 commits the one line of `session_sidebar.dart`);
  - strings: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n`; the generated `lib/l10n/app_localizations*.dart` files are committed.
- **Commits:**
  - `feat(v2-ai): …` / `test(v2-ai): …` / `docs(v2-ai): …`, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
  - `pubspec.lock` is git-ignored: never add it.
- **Defaults:** `new-tab-kind = terminal`, `ai-agent-claude = on`, `ai-checkpoint-days = 14`.

## Review Focus

These are the five failure modes most likely to hurt a user that the spec's tests do not cover yet. Each has a pinning test in its owning task.

1. **The A12 badge lies about an AI pane.**
   - A long silent turn turns "Running" into "Idle/Done": A12 decays a pane with no terminal output after 20 s, and an agent thinking for a minute sends nothing. "Done" notifications then fire too early.
   - Esc while a permission question is open leaves the badge on "Needs input" forever: A12 keeps `needsInput` on an `idle` event, and the runtime cancels the question quietly.

   [Task 4 "an AI pane stays running past the quiet decay"; Task 10 "a cancelled question ends as idle, not needs input"]
2. **Only AI tabs open at quit.** `pickSnapshot` treats the layout as empty and restores an older generation's terminal tabs, or the layout writer drops its generations. [Task 6 "a layout with only AI tabs is the one restored"]
3. **A background-service reconnect rebuilds the tab list.** That drops the AI tabs and orphans their agent processes. [Task 3 "AI tabs outlive a rebuild of the tab list"; Task 10 "a pane that leaves stops its agent"]
4. **Streaming jank or a privacy leak in agent text.**
   - 2 000 chunks must not rebuild the conversation 2 000 times.
   - Markdown must never fetch `![](https://…)`.

   [Task 12 "2 000 chunks: one rebuild per frame, of that message only, and of its last block only" and "markdown never loads images"]
5. **Keys typed in the AI pane reach a hidden shell.**
   - The window has one terminal focus node, and `FocusNode.attach` keeps the key handler of the last terminal view that held it.
   - A composer holding that node, or a pane that does not replace the handler, sends Enter, Backspace and the arrows to the shell of another tab. That shell may then run a half-typed command.

   [Task 17 "keys typed in the pane stay there: the window focus node keeps no terminal key handler (Backspace, arrows)" and "signed out: the composer waits and keeps the keyboard"]

---
## File Structure

Paths are under `apps/desktop/` unless they start with `docs/` or `agent-skills/`.

| File | Responsibility | Task |
|---|---|---|
| Modify `pubspec.yaml` | D17 pins (Task 1); `shellx_acp`, `shellx_ai` (Task 10) | 1, 10 |
| Create `test/ai/d17_packages_test.dart` | the four D17 packages render on 3.41.4 | 1 |
| Modify `lib/l10n/app_en.arb`, `lib/l10n/app_vi.arb`, generated `lib/l10n/app_localizations*.dart`; Create `test/l10n/ai_strings_test.dart` | every V2-1b string, EN + VI; §4.6 wording, plurals, D21 naming | 2 |
| Create `lib/src/ai/ai_pane_state.dart`, `lib/src/terminal/terminal_tabs_ai.dart` (part) | `TabKind`, `isAiPaneId`, `AiPaneState`; `openAiTab`, `updateAiPane`, `addAiTerminal`, `kAiPaneRatio` | 3 |
| Modify `lib/src/terminal/{terminal_tabs,terminal_tabs_panes,terminal_tabs_config}.dart`, `lib/src/ui/terminal/{session_sidebar,session_tab_row,sidebar_remote,terminal_workspace_page}.dart` | D2/D3 model, AI tabs survive a rebuild, moves refused; null-safe readers | 3 |
| Modify 25 files under `test/` (scripted `!`); Create `test/support/ai_tabs.dart`, `test/terminal/ai_tab_model_test.dart` | `focused`/`terminal`/`selection` nullable; AI tab helper; model tests | 3 |
| Modify `lib/src/terminal/{agent_status_notifier,tab_attention,focus_history,closed_items}.dart`; Create `test/terminal/ai_status_readers_test.dart` | D13 readers: AI panes are live panes; no quiet decay; AI name; `addAiNotice` | 4 |
| Create `lib/src/ui/ai/ai_pane_view.dart` | Task 5's stand-in; the real pane (Task 17) | 5, 17 |
| Modify `lib/src/terminal/{agent_names,terminal_tabs_ai}.dart`, `lib/src/ui/terminal/{pane_tree_view,session_tab_row,close_tab,terminal_workspace_page,terminal_workspace_notices}.dart`, `lib/src/ui/config/search_all_overlay.dart`; Create `test/ui/ai_tab_screens_test.dart` | §4.7 UI readers; an AI tab without a terminal pane goes through every screen | 5 |
| Modify `lib/src/restore/{restore_snapshot,restore_capture,restore_persistence,restore_store}.dart`, `lib/src/terminal/terminal_tabs_restore.dart`; Create `test/restore/v1/restore_snapshot_v1.dart`, `test/restore/ai_tabs_restore_test.dart` | D14 `aiTabs`; frozen V1 parser | 6 |
| Modify `lib/src/cli/{ui_command_handler,cli_targets,cli_event_bus}.dart`; Create `test/cli/ui_ai_tabs_test.dart` | D19 | 7 |
| Modify `lib/src/config/{shellx_config,settings_schema,config_show,config_template}.dart`, `lib/src/ui/settings/{settings_values,pages/general_page}.dart`, `lib/src/platform/settings_store.dart`, `test/config/settings_schema_test.dart`, `test/agent/settings_ownership_test.dart`; Create `test/config/ai_settings_test.dart` | D4/D12/D21 keys, UI keys | 8 |
| Modify `lib/src/config/{keybindings,keybind_actions}.dart`, `lib/src/ui/terminal/{terminal_intents,shortcut_labels}.dart`, `lib/src/ui/config/action_labels.dart`, `test/ui/shortcut_golden_test.dart`, `test/config/keybindings_test.dart`, `agent-skills/shellx-config/SKILL.md` | D5 actions | 9 |
| Create `lib/src/ai/{ai_off_thread,ai_frame_notifier,ai_host_provider,ai_agents,ai_runtimes}.dart`, `test/support/ai_fakes.dart`, `test/ai/{ai_frame_notifier,ai_agents,ai_runtimes}_test.dart` | off-thread runner; one notification per frame; agents, readiness, remembered config; runtimes, tab sync, D13 bridge | 10 |
| Create `lib/src/ai/ai_startup.dart`, `test/ai/ai_startup_test.dart`; Modify `lib/main.dart`, `lib/src/platform/process_tree.dart` | host at startup (crash sweep of whole trees, retention, warm-up), stop on quit | 11 |
| Create `lib/src/ui/ai/{ai_theme,ai_scope,ai_markdown,ai_timeline}.dart`, `test/support/ai_parts.dart`, `test/ui/ai/ai_timeline_test.dart` | virtualized, rev-cached timeline; block markdown; messages, thoughts | 12 |
| Create `lib/src/ai/line_diff.dart`, `lib/src/ui/ai/{ai_labels,ai_diff_view,ai_tool_card}.dart`, `test/ai/line_diff_test.dart`, `test/ui/ai/ai_tool_card_test.dart` | cards per `kind`, capped output, diffs off-thread | 13 |
| Create `lib/src/ui/ai/{ai_log_dialog,ai_notice_card,ai_turn_summary}.dart`, `test/ui/ai/ai_notice_card_test.dart` | §4.5 notices, turn summary, "View log" | 14 |
| Create `lib/src/ui/ai/{ai_composer,ai_dock}.dart`, `test/ui/ai/ai_composer_test.dart` | composer, plan bar, queue, stop / force stop | 15 |
| Create `lib/src/ui/ai/ai_permission_bar.dart`, `test/ui/ai/ai_permission_bar_test.dart` | D10 | 16 |
| Create `lib/src/ai/ai_folders.dart`, `lib/src/ui/ai/{ai_header,ai_folder_card}.dart`, `lib/src/ui/settings/settings_start_page.dart`, `test/ui/ai/ai_pane_test.dart`; Modify `lib/src/ai/{ai_frame_notifier,ai_runtimes}.dart`, `lib/src/ui/ai/{ai_scope,ai_composer}.dart`, `lib/src/ui/settings/settings_overlay.dart`, `test/ui/ai_tab_screens_test.dart` | the real pane: header, lazy start, folder card, resume card, focus | 17 |
| Create `lib/src/ui/ai/ai_run_sheet.dart`, `test/ui/ai/ai_run_sheet_test.dart`; Modify `lib/src/ai/ai_folders.dart`, `lib/src/ui/ai/ai_pane_view.dart`, `test/support/ai_fakes.dart` | D8 sign-in and install | 18 |
| Create `lib/src/ai/ai_open.dart`, `test/ui/ai/ai_open_test.dart`; Modify `lib/src/remote/ssh_actions.dart`, `lib/src/terminal/terminal_tabs.dart`, `lib/src/ui/terminal/{terminal_workspace_page,sidebar_new_button,session_sidebar}.dart` | D5 | 19 |
| Create `lib/src/ai/ai_project_files.dart`, `lib/src/ui/ai/{ai_editor,ai_changes_panel,ai_diff_overlay,ai_side_panel}.dart`, `test/support/fake_project.dart`, `test/ui/ai/ai_changes_test.dart`; Modify `lib/src/ui/ai/{ai_scope,ai_pane_view,ai_tool_card}.dart` | §4.4 Changes, undo, B14 | 20 |
| Create `lib/src/ui/ai/ai_config_chips.dart`, `test/ui/ai/ai_config_chips_test.dart`; Modify `ai_composer.dart` | D11 | 21 |
| Create `lib/src/ui/ai/ai_ask_card.dart`, `test/ui/ai/ai_ask_card_test.dart`; Modify `ai_timeline.dart` | D22 | 22 |
| Create `lib/src/ui/ai/ai_intro.dart`, `test/ui/ai/ai_intro_test.dart`; Modify `lib/src/ui/pages/onboarding_page.dart`, `lib/src/ui/terminal/session_sidebar.dart`, `test/support/fakes.dart` | D4 | 23 |
| Create `lib/src/ui/ai/ai_agents_section.dart`, `test/ui/ai/ai_agents_settings_test.dart`; Modify `lib/src/ai/ai_agents.dart`, `lib/src/ui/settings/pages/agents_page.dart` | D7/D12/D21/D23 | 24 |
| Create `lib/src/ai/ai_gitignore.dart`, `lib/src/ui/ai/{ai_files_panel,ai_file_viewer}.dart`, `test/ai/ai_gitignore_test.dart`, `test/ui/ai/ai_files_test.dart`; Modify `lib/src/ai/ai_project_files.dart`, `lib/src/ui/ai/{ai_pane_view,ai_tool_card}.dart`, `test/support/fake_project.dart` | B12; Files tab; read-only viewer | 25 |
| Create `lib/src/ui/ai/ai_history.dart`, `test/ui/ai/ai_history_test.dart`; Modify `ai_pane_view.dart` | D15 | 26 |
| Create `lib/src/ui/ai/ai_completer.dart`, `test/ui/ai/ai_mention_test.dart`; Modify `lib/src/ui/ai/{ai_composer,ai_scope,ai_pane_view}.dart` | D16 `@` | 27 |
| Create `test/ui/ai/ai_commands_test.dart`; Modify `lib/src/ui/ai/{ai_completer,ai_composer}.dart` | D16 `/` | 28 |
| Create `lib/src/ui/ai/ai_images.dart`, `test/ui/ai/ai_image_test.dart`; Modify `lib/src/ui/ai/{ai_scope,ai_pane_view,ai_dock,ai_composer}.dart` | D16 images | 29 |
| Modify `docs/superpowers/ledgers/v2-ai.md` | results, ⚠ manual checks | 1, 30 |

---

### Task 1: D17 packages — pins, smoke test, build [independent of V2-1a]

The spec's Task-1 item §12.3 ("`pub get` and build with the D17 packages on Flutter 3.41.4"), moved here by V2-1a. Resolution was checked offline on a scratch copy of this workspace: `flutter_markdown_plus 1.0.12` (brings `markdown 7.3.1`), `re_editor 0.10.0` (brings `isolate_manager 4.1.5+1`; its highlighter runs in an isolate), `re_highlight 0.0.3`, `diff_match_patch 0.4.1` (pure Dart; its `sdk <3.0.0` bound is read as `<4.0.0` by Dart 3). `re_editor` starts a cursor-blink timer on focus, even read-only: every use passes `autofocus: false, showCursorWhenReadOnly: false` (pinned by the test).

**Files:**
- Modify: `apps/desktop/pubspec.yaml`
- Test: `apps/desktop/test/ai/d17_packages_test.dart`
- Modify: `docs/superpowers/ledgers/v2-ai.md` (one line)

**Interfaces:**
- Consumes: nothing.
- Produces: the packages `flutter_markdown_plus`, `re_editor`, `re_highlight`, `diff_match_patch` for Tasks 13, 14, 20, 25.

- [ ] **Step 1: Write the failing test**

`apps/desktop/test/ai/d17_packages_test.dart`:

```dart
import 'package:diff_match_patch/diff_match_patch.dart' as dmp;
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

void main() {
  testWidgets('flutter_markdown_plus renders a heading, a list and code', (
    t,
  ) async {
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownBody(
            data: '# Title\n\n- one\n- two\n\n```dart\nvoid main() {}\n```',
          ),
        ),
      ),
    );
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('one'), findsOneWidget);
    expect(find.textContaining('void main()'), findsOneWidget);
  });

  testWidgets('re_editor shows read-only highlighted code', (t) async {
    final controller = CodeLineEditingController.fromText(
      'void main() {}\nint x = 1;',
    );
    addTearDown(controller.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CodeEditor(
            controller: controller,
            readOnly: true,
            autofocus: false,
            showCursorWhenReadOnly: false,
            style: CodeEditorStyle(
              codeTheme: CodeHighlightTheme(
                languages: {'dart': CodeHighlightThemeMode(mode: langDart)},
                theme: atomOneDarkTheme,
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 50));
    expect(find.byType(CodeEditor), findsOneWidget);
    expect(controller.codeLines.length, 2);
    await t.pumpWidget(const SizedBox());
  });

  test('diff_match_patch diffs two texts', () {
    final d = dmp.diff('a\nb\nc\n', 'a\nB\nc\n', checklines: false);
    expect(d.any((x) => x.operation == dmp.DIFF_INSERT), isTrue);
    expect(d.any((x) => x.operation == dmp.DIFF_DELETE), isTrue);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ai/d17_packages_test.dart`
Expected: compilation fails, `Couldn't resolve the package 'diff_match_patch'`.

- [ ] **Step 3: Pin the packages**

In `apps/desktop/pubspec.yaml`, replace

```yaml
  desktop_drop: 0.8.4
```

with

```yaml
  desktop_drop: 0.8.4
  # V2-1 D17: line diffs for the AI tab (pure Dart).
  diff_match_patch: 0.4.1
```

replace

```yaml
  flutter_secure_storage: ^10.3.4
```

with

```yaml
  # V2-1 D17: the AI tab's markdown.
  flutter_markdown_plus: 1.0.12
  flutter_secure_storage: ^10.3.4
```

and replace

```yaml
  qr_flutter: ^4.1.0
```

with

```yaml
  qr_flutter: ^4.1.0
  # V2-1 D17: the AI tab's read-only code view and its highlighting.
  re_editor: 0.10.0
  re_highlight: 0.0.3
```

Then, at the repo root: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get` (online is fine; `--offline` works when the pub cache already has them).

- [ ] **Step 4: Run the test and build the app**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ai/d17_packages_test.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter build macos --debug 2>&1 | tail -3
```

Expected: `All tests passed!` (3 tests); `No issues found!`; `✓ Built build/macos/Build/Products/Debug/ShellX.app` (name as the project builds it). If the build fails only because of one of these packages, follow D17: pin the previous version that builds and say so in the ledger; with none, drop the package and write the minimal widget yourself in the task that needs it.

- [ ] **Step 5: Ledger and commit**

Append to `docs/superpowers/ledgers/v2-ai.md`, under the `## V2-1b (desktop) — execution` heading the prerequisite step added, this line:
`- Task 1 (D17): flutter_markdown_plus 1.0.12, re_editor 0.10.0, re_highlight 0.0.3, diff_match_patch 0.4.1 resolve and build on Flutter 3.41.4 (macOS debug build ok); re_editor needs autofocus false + showCursorWhenReadOnly false in tests.`

```bash
git add apps/desktop/pubspec.yaml apps/desktop/test/ai/d17_packages_test.dart docs/superpowers/ledgers/v2-ai.md
git commit -m "feat(v2-ai): pin the D17 packages (markdown, code view, highlight, diff) for the AI tab

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: Every V2-1b string, English and Vietnamese [independent of V2-1a]

All strings land in one task so later tasks never touch the ARB files (no merge conflicts between parallel tasks). The §4.6 keys keep the spec's names and wording; ruling B9 adds `{version}` to `aiNodeMissing`. A12's state words are reused for the status (`agentStateRunning`… "Đang chạy / Cần bạn trả lời / Đang chờ / Xong").

**Files:**
- Modify: `apps/desktop/lib/l10n/app_en.arb`, `apps/desktop/lib/l10n/app_vi.arb`
- Regenerate (committed): `apps/desktop/lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_vi.dart`
- Test: `apps/desktop/test/l10n/ai_strings_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `AppLocalizations` getters/methods for every key below (e.g. `aiNewSession`, `aiComposerHint(String agent)`, `aiTurnSummary(int n, String time, int count)`, `aiNodeMissing(String agent, int version)`, `aiNewSessionTooltip(String shortcut)`, `aiShowAllLines(int count)`), used by Tasks 3–29.

- [ ] **Step 1: Write the failing test**

`apps/desktop/test/l10n/ai_strings_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final vi = lookupAppLocalizations(const Locale('vi'));

  test('V2-1 §4.6: the main strings, word for word', () {
    expect(vi.aiNewSession, 'Phiên AI mới');
    expect(vi.aiNewTabKindLabel, 'Tab mới mở dạng');
    expect(vi.aiNewTabKindAi, 'Giao diện AI');
    expect(vi.aiNewTabKindTerminal, 'Terminal');
    expect(vi.aiOnboardingTitle, 'Bạn muốn làm việc theo kiểu nào?');
    expect(
      vi.aiComposerHint('Claude'),
      'Nhắn cho Claude… (@ nhắc tệp, / gọi lệnh)',
    );
    expect(vi.aiPermTitle('Claude', 'Sửa a.ts'), 'Claude xin quyền: Sửa a.ts');
    expect(
      [
        vi.aiPermAllowOnce,
        vi.aiPermAllowAlways,
        vi.aiPermRejectOnce,
        vi.aiPermRejectAlways,
      ],
      ['Cho phép', 'Luôn cho phép', 'Từ chối', 'Luôn từ chối'],
    );
    expect(vi.aiTurnSummary(3, '0:41', 2), 'Lượt 3 · 0:41 · 2 tệp đổi');
    expect(vi.aiRevertTurn, 'Hoàn tác lượt');
    expect(vi.aiRevertSession, 'Hoàn tác cả phiên');
    expect(vi.aiChangedAfterTurn, 'đã sửa sau lượt');
    expect(vi.aiLoginNeeded('Claude'), 'Claude cần đăng nhập');
    expect(vi.aiRunSheetLogin('Claude'), 'Đăng nhập Claude');
    expect(vi.aiRunSheetInstall('Claude'), 'Cài Claude');
    expect(vi.aiNodeMissing('Claude', 22), 'Claude cần Node.js 22 trở lên');
    expect(
      vi.aiAgentExited('Claude', 1),
      'Claude dừng bất ngờ (mã thoát 1)',
    );
    expect(vi.aiForceStop, 'Dừng hẳn');
    expect(vi.aiResumeSession, 'Tiếp tục phiên');
    expect(vi.aiHistory, 'Lịch sử phiên');
    expect(
      vi.aiNoUndo('không tìm thấy git'),
      'Hoàn tác đang tắt cho dự án này (không tìm thấy git)',
    );
    expect(
      vi.aiBypassConfirm('Claude'),
      'Claude sẽ sửa tệp và chạy lệnh mà không hỏi.',
    );
  });

  test('English counts read right', () {
    expect(en.aiTurnSummary(1, '0:05', 1), 'Turn 1 · 0:05 · 1 file changed');
    expect(en.aiTurnSummary(2, '0:41', 3), 'Turn 2 · 0:41 · 3 files changed');
    expect(en.aiReverted(1), 'Reverted 1 file.');
    expect(en.aiNodeMissing('Codex', 20), 'Codex needs Node.js 20 or newer');
  });

  test('feature names say Claude, never Claude Code (D21)', () {
    for (final l in [en, vi]) {
      for (final s in [
        l.aiNewSession,
        l.aiSettingClaude,
        l.aiMenuAgentsSettings,
        l.actionNewAiSession,
      ]) {
        expect(s, isNot(contains('Claude Code')));
      }
    }
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/l10n/ai_strings_test.dart`
Expected: compilation fails, `The getter 'aiNewSession' isn't defined for the type 'AppLocalizations'`.

- [ ] **Step 3: Add the English strings**

In `apps/desktop/lib/l10n/app_en.arb`, replace the last entry and the closing brace

```json
  "configProblemAgentCommandBad": "agent-event-command must start with an absolute path or ~/, and have no hidden characters or unclosed quotes"
}
```

with

```json
  "configProblemAgentCommandBad": "agent-event-command must start with an absolute path or ~/, and have no hidden characters or unclosed quotes",
  "aiNewSession": "New AI session",
  "aiNewTabKindLabel": "New tabs open as",
  "aiNewTabKindAi": "AI interface",
  "aiNewTabKindTerminal": "Terminal",
  "aiOnboardingTitle": "How do you want to work?",
  "aiComposerHint": "Message {agent}… (@ file, / command)",
  "@aiComposerHint": {"placeholders": {"agent": {"type": "String"}}},
  "aiPermTitle": "{agent} asks: {action}",
  "@aiPermTitle": {"placeholders": {"agent": {"type": "String"}, "action": {"type": "String"}}},
  "aiPermAllowOnce": "Allow",
  "aiPermAllowAlways": "Always allow",
  "aiPermRejectOnce": "Reject",
  "aiPermRejectAlways": "Always reject",
  "aiTurnSummary": "Turn {n} · {time} · {count, plural, =1{1 file changed} other{{count} files changed}}",
  "@aiTurnSummary": {"placeholders": {"n": {"type": "int"}, "time": {"type": "String"}, "count": {"type": "int"}}},
  "aiRevertTurn": "Revert turn",
  "aiRevertSession": "Revert session",
  "aiChangedAfterTurn": "changed after the turn",
  "aiLoginNeeded": "{agent} needs you to sign in",
  "@aiLoginNeeded": {"placeholders": {"agent": {"type": "String"}}},
  "aiRunSheetLogin": "Sign in to {agent}",
  "@aiRunSheetLogin": {"placeholders": {"agent": {"type": "String"}}},
  "aiRunSheetInstall": "Install {agent}",
  "@aiRunSheetInstall": {"placeholders": {"agent": {"type": "String"}}},
  "aiNodeMissing": "{agent} needs Node.js {version} or newer",
  "@aiNodeMissing": {"placeholders": {"agent": {"type": "String"}, "version": {"type": "int"}}},
  "aiAgentExited": "{agent} stopped unexpectedly (exit {code})",
  "@aiAgentExited": {"placeholders": {"agent": {"type": "String"}, "code": {"type": "int"}}},
  "aiForceStop": "Force stop",
  "aiResumeSession": "Resume session",
  "aiHistory": "Session history",
  "aiNoUndo": "Undo is off for this project ({reason})",
  "@aiNoUndo": {"placeholders": {"reason": {"type": "String"}}},
  "aiBypassConfirm": "{agent} will edit files and run commands without asking.",
  "@aiBypassConfirm": {"placeholders": {"agent": {"type": "String"}}},
  "aiPaneLabel": "AI session with {agent}",
  "@aiPaneLabel": {"placeholders": {"agent": {"type": "String"}}},
  "aiTabRowLabel": "AI session",
  "aiStatusStarting": "Starting…",
  "aiStatusNotRunning": "Agent not running",
  "aiStatusSignIn": "Sign-in needed",
  "aiStatusStopped": "Stopped",
  "aiStatusWithTime": "{state} · {time}",
  "@aiStatusWithTime": {"placeholders": {"state": {"type": "String"}, "time": {"type": "String"}}},
  "aiHeaderPanel": "Changes and files",
  "aiHeaderTerminal": "Terminal in this tab",
  "aiHeaderZoom": "Zoom",
  "aiHeaderMore": "More",
  "aiMenuAgentsSettings": "Settings › Agents",
  "aiMenuRestart": "Restart agent",
  "aiMenuViewLog": "View log",
  "aiLogTitle": "Agent log (stderr)",
  "aiLogNote": "Kept in memory for this view only; ShellX does not write it to its own log.",
  "aiLogEmpty": "(empty)",
  "aiResumeLoading": "Loading the conversation…",
  "aiYou": "You",
  "aiThinking": "Thinking",
  "aiToolRead": "Read",
  "aiToolEdit": "Edit",
  "aiToolCreate": "Create",
  "aiToolDelete": "Delete",
  "aiToolMove": "Rename",
  "aiToolSearch": "Search",
  "aiToolExecute": "Run",
  "aiToolFetch": "Fetch",
  "aiToolModeChanged": "Mode changed: {title}",
  "@aiToolModeChanged": {"placeholders": {"title": {"type": "String"}}},
  "aiToolPending": "waiting",
  "aiToolAwaiting": "waiting for you",
  "aiToolRunning": "running · {seconds} s",
  "@aiToolRunning": {"placeholders": {"seconds": {"type": "String"}}},
  "aiToolDone": "done",
  "aiToolRejected": "rejected",
  "aiToolStopped": "stopped",
  "aiToolFailed": "error",
  "aiToolTook": "{seconds} s",
  "@aiToolTook": {"placeholders": {"seconds": {"type": "String"}}},
  "aiToolNoOutput": "No output. The Changes panel still sees the files a command changed.",
  "aiToolInput": "Input",
  "aiToolResult": "Result",
  "aiViewFile": "View whole file",
  "aiOpenInEditor": "Open in editor",
  "aiPermWaiting": "Waiting for your answer below — keys 1–{n}, Esc to reject",
  "@aiPermWaiting": {"placeholders": {"n": {"type": "int"}}},
  "aiPermChosen": "You chose: {label} ({name})",
  "@aiPermChosen": {"placeholders": {"label": {"type": "String"}, "name": {"type": "String"}}},
  "aiPermCancelled": "The turn stopped before you answered",
  "aiPermAlwaysNote": "“{label}” as {agent} puts it: {name}",
  "@aiPermAlwaysNote": {"placeholders": {"label": {"type": "String"}, "agent": {"type": "String"}, "name": {"type": "String"}}},
  "aiTurnStopped": "Stopped turn {n} · {time}",
  "@aiTurnStopped": {"placeholders": {"n": {"type": "int"}, "time": {"type": "String"}}},
  "aiTurnInterrupted": "Turn {n} was interrupted · {time}",
  "@aiTurnInterrupted": {"placeholders": {"n": {"type": "int"}, "time": {"type": "String"}}},
  "aiTurnFailed": "Turn {n} failed · {time}",
  "@aiTurnFailed": {"placeholders": {"n": {"type": "int"}, "time": {"type": "String"}}},
  "aiTurnNoChanges": "no files changed",
  "aiTurnView": "View",
  "aiNotInstalled": "{agent} is not installed",
  "@aiNotInstalled": {"placeholders": {"agent": {"type": "String"}}},
  "aiInstall": "Install",
  "aiNoNpm": "npm was not found next to Node.js.",
  "aiNodeGuide": "Installation guide",
  "aiCommandMissing": "Command not found: {command}",
  "@aiCommandMissing": {"placeholders": {"command": {"type": "String"}}},
  "aiCommandShimOnly": "Only a .cmd or .bat file was found; ShellX runs programs directly.",
  "aiAgentOutputInvalid": "{agent} sent output ShellX cannot read and was stopped",
  "@aiAgentOutputInvalid": {"placeholders": {"agent": {"type": "String"}}},
  "aiStartFailed": "{agent} could not start",
  "@aiStartFailed": {"placeholders": {"agent": {"type": "String"}}},
  "aiRestart": "Restart",
  "aiRetry": "Try again",
  "aiCannotResume": "This agent cannot restore the previous session; a new session started.",
  "aiFolderMissing": "The project folder no longer exists",
  "aiChooseFolder": "Choose folder",
  "aiChooseFolderTitle": "Choose a project folder",
  "aiChooseFolderBody": "The agent works in this folder.",
  "aiFolderField": "Folder",
  "aiFolderInvalid": "Enter the absolute path of an existing folder.",
  "aiFolderUse": "Use this folder",
  "aiUndoNoGit": "git was not found",
  "aiUndoNoCommandLineTools": "the Command Line Tools are not installed",
  "aiUndoGitTooOld": "git is older than 2.26",
  "aiUndoTooManyFiles": "more than 200,000 files",
  "aiUndoTooSlow": "the first snapshot took over 30 s",
  "aiUndoFailed": "a snapshot failed",
  "aiNoUndoTurn": "Undo is off for this turn ({reason})",
  "@aiNoUndoTurn": {"placeholders": {"reason": {"type": "String"}}},
  "aiClaudeOff": "The Claude integration is turned off (ai-agent-claude = off).",
  "aiAgentUnknown": "This agent is no longer in Settings › Agents.",
  "aiSend": "Send",
  "aiQueue": "Queue",
  "aiStop": "Stop",
  "aiQueued": "Queued: “{text}” — sent when this turn ends",
  "@aiQueued": {"placeholders": {"text": {"type": "String"}}},
  "aiQueueRemove": "Remove",
  "aiQueueFull": "At most 5 messages can wait.",
  "aiCannotSend": "The agent cannot take a message now.",
  "aiContextUsed": "Context {percent}%",
  "@aiContextUsed": {"placeholders": {"percent": {"type": "int"}}},
  "aiPlan": "Plan · {done}/{total} done",
  "@aiPlan": {"placeholders": {"done": {"type": "int"}, "total": {"type": "int"}}},
  "aiPlanHigh": "priority",
  "aiComposerWaiting": "Waiting for the agent…",
  "aiMention": "Mention a file (@)",
  "aiCommands": "Agent commands (/)",
  "aiAttachImage": "Attach an image (paste or drop)",
  "aiRemoveImage": "Remove image",
  "aiImageUnsupported": "{agent} does not take images.",
  "@aiImageUnsupported": {"placeholders": {"agent": {"type": "String"}}},
  "aiNoMatches": "No matches",
  "aiPanelChanges": "Changes",
  "aiPanelFiles": "Files",
  "aiScopeTurn": "This turn",
  "aiScopeSession": "Whole session",
  "aiChangesNoTurn": "No turn yet. Before each turn, ShellX snapshots the project into a hidden git repository; every change after that shows here, even from shell commands.",
  "aiChangesEmpty": "No changes since then.",
  "aiReviewed": "Reviewed",
  "aiRevertFile": "Revert this file",
  "aiCheckpoint": "Restore point: before turn {n} · {hash}",
  "@aiCheckpoint": {"placeholders": {"n": {"type": "int"}, "hash": {"type": "String"}}},
  "aiIgnoredNote": "Files that .gitignore ignores are not tracked and cannot be reverted.",
  "aiOutsideNote": "Changes outside the project folder are not tracked.",
  "aiRevertDialogTitle": "Some files changed after this turn",
  "aiRevertDialogBody": "{files} changed after the turn ended, maybe by you or another session. Reverting overwrites that too.",
  "@aiRevertDialogBody": {"placeholders": {"files": {"type": "String"}}},
  "aiRevertOnlyClean": "Only revert unchanged files",
  "aiRevertAll": "Revert all",
  "aiRevertBusy": "Wait for the running turn to finish.",
  "aiReverted": "{count, plural, =1{Reverted 1 file.} other{Reverted {count} files.}}",
  "@aiReverted": {"placeholders": {"count": {"type": "int"}}},
  "aiRevertFailed": "The revert did not work.",
  "aiVsTurnStart": "compared with the start of the turn",
  "aiVsSessionStart": "compared with the start of the session",
  "aiReadOnly": "read-only",
  "aiMentionInChat": "Mention in chat",
  "aiBinaryFile": "Binary file",
  "aiFileTooLarge": "Too large to show",
  "aiIgnored": "ignored",
  "aiFilesNote": "Files the agent changed carry M or A. Click a file to view it (read-only).",
  "aiModeDefault": "Ask first",
  "aiModeAcceptEdits": "Auto-edit files",
  "aiModePlan": "Plan",
  "aiModeAuto": "Auto",
  "aiModeBypass": "Bypass permissions",
  "aiBypassTitle": "Turn on “Bypass permissions”?",
  "aiBypassNote": "Restore points still run before each turn, but they cannot undo what left this computer (git push, API calls, email).",
  "aiBypassTurnOn": "Turn on",
  "aiConfigModel": "Model: {name}",
  "@aiConfigModel": {"placeholders": {"name": {"type": "String"}}},
  "aiConfigEffort": "Thinking: {name}",
  "@aiConfigEffort": {"placeholders": {"name": {"type": "String"}}},
  "aiConfigOther": "{name}: {value}",
  "@aiConfigOther": {"placeholders": {"name": {"type": "String"}, "value": {"type": "String"}}},
  "aiAskSend": "Send",
  "aiAskDecline": "Decline",
  "aiAskCancel": "Cancel",
  "aiAskOpen": "Open in browser",
  "aiAskUrlNote": "{agent} asks you to open this page:",
  "@aiAskUrlNote": {"placeholders": {"agent": {"type": "String"}}},
  "aiAskAnswered": "Answered",
  "aiAskDeclined": "Declined",
  "aiAskCancelled": "Cancelled",
  "aiAskCompleted": "Done",
  "aiAskRequired": "Required",
  "aiAskInvalid": "Check the marked answers.",
  "aiAskUnsupported": "This question uses an answer type ShellX does not support yet",
  "aiOnboardingAiBody": "A new tab is an AI session: chat, see what the agent does, review changes, no commands to type.",
  "aiOnboardingTerminalBody": "As ShellX works today: a new tab is a shell.",
  "aiOnboardingNote": "You can change this any time in Settings › General.",
  "aiIntroText": "New: an AI interface. How should new tabs open?",
  "aiSettingsSection": "AI interface",
  "aiAgentReady": "Ready",
  "aiAgentNeedsNode": "Needs Node {version}",
  "@aiAgentNeedsNode": {"placeholders": {"version": {"type": "int"}}},
  "aiAgentNotInstalled": "Not installed",
  "aiAgentNeedsLogin": "Needs sign-in",
  "aiAgentError": "Error",
  "aiAgentChecking": "Checking…",
  "aiAgentLogin": "Sign in",
  "aiDefaultAgent": "Default agent",
  "aiAddCustomAgent": "Add a custom agent",
  "aiCustomName": "Name",
  "aiCustomCommand": "Command (absolute path or a name on PATH)",
  "aiCustomArgs": "Arguments, one per line",
  "aiCustomEnv": "Environment, NAME=value per line",
  "aiCustomSave": "Save",
  "aiCustomRemove": "Remove",
  "aiCustomInvalid": "Enter a name and a command.",
  "aiSettingClaude": "Claude in the AI interface",
  "aiSettingClaudeDesc": "Runs Claude Code through the Claude Agent adapter. Off hides Claude everywhere.",
  "aiSettingOn": "On",
  "aiSettingOff": "Off",
  "aiSettingCheckpointDays": "Keep restore points (days)",
  "aiSettingCheckpointDaysDesc": "Older restore points are deleted at start.",
  "aiSettingNewTabKindDesc": "⌘T / Ctrl+Shift+T, the + button and the empty window open this kind of tab.",
  "aiDeleteCheckpoints": "Delete all restore points",
  "aiDeleteCheckpointsTitle": "Delete all restore points?",
  "aiDeleteCheckpointsBody": "Undo will not reach turns before now. Your projects are not touched.",
  "aiDeleteCheckpointsDone": "Restore points deleted.",
  "actionNewAiSession": "New AI session",
  "actionNewTerminalTab": "New terminal tab",
  "aiNewSessionTooltip": "New AI session  {shortcut}",
  "@aiNewSessionTooltip": {"placeholders": {"shortcut": {"type": "String"}}},
  "aiCloseRunningTitle": "Stop the turn and close?",
  "aiCloseRunningBody": "{agent} is still working in this tab.",
  "@aiCloseRunningBody": {"placeholders": {"agent": {"type": "String"}}},
  "aiCloseRunningAction": "Stop and close",
  "aiHistoryEmpty": "No earlier sessions for this folder.",
  "aiHistoryCurrent": "current session",
  "aiHistoryUnavailable": "{agent} does not list its sessions.",
  "@aiHistoryUnavailable": {"placeholders": {"agent": {"type": "String"}}},
  "aiHistoryUntitled": "Untitled session",
  "aiRunSheetFailed": "Ended with exit code {code}",
  "@aiRunSheetFailed": {"placeholders": {"code": {"type": "int"}}},
  "aiRunSheetNote": "This is the agent's own program; ShellX does not read or keep what happens here.",
  "aiLoginFailed": "Sign-in did not work.",
  "aiJumpToLatest": "Jump to latest",
  "aiShowAllLines": "Show all {count} lines",
  "@aiShowAllLines": {"placeholders": {"count": {"type": "int"}}},
  "aiOutputCut": "{count} lines hidden",
  "@aiOutputCut": {"placeholders": {"count": {"type": "int"}}},
  "aiStopping": "Stopping…",
  "aiTurnDone": "Turn {n} · {time}",
  "@aiTurnDone": {"placeholders": {"n": {"type": "int"}, "time": {"type": "String"}}},
  "aiFileMissing": "This file is not there any more."
}
```

- [ ] **Step 4: Add the Vietnamese strings**

In `apps/desktop/lib/l10n/app_vi.arb`, replace

```json
  "configProblemAgentCommandBad": "agent-event-command phải bắt đầu bằng đường dẫn tuyệt đối hoặc ~/, không có ký tự ẩn và không thiếu dấu nháy đóng"
}
```

with

```json
  "configProblemAgentCommandBad": "agent-event-command phải bắt đầu bằng đường dẫn tuyệt đối hoặc ~/, không có ký tự ẩn và không thiếu dấu nháy đóng",
  "aiNewSession": "Phiên AI mới",
  "aiNewTabKindLabel": "Tab mới mở dạng",
  "aiNewTabKindAi": "Giao diện AI",
  "aiNewTabKindTerminal": "Terminal",
  "aiOnboardingTitle": "Bạn muốn làm việc theo kiểu nào?",
  "aiComposerHint": "Nhắn cho {agent}… (@ nhắc tệp, / gọi lệnh)",
  "aiPermTitle": "{agent} xin quyền: {action}",
  "aiPermAllowOnce": "Cho phép",
  "aiPermAllowAlways": "Luôn cho phép",
  "aiPermRejectOnce": "Từ chối",
  "aiPermRejectAlways": "Luôn từ chối",
  "aiTurnSummary": "Lượt {n} · {time} · {count} tệp đổi",
  "aiRevertTurn": "Hoàn tác lượt",
  "aiRevertSession": "Hoàn tác cả phiên",
  "aiChangedAfterTurn": "đã sửa sau lượt",
  "aiLoginNeeded": "{agent} cần đăng nhập",
  "aiRunSheetLogin": "Đăng nhập {agent}",
  "aiRunSheetInstall": "Cài {agent}",
  "aiNodeMissing": "{agent} cần Node.js {version} trở lên",
  "aiAgentExited": "{agent} dừng bất ngờ (mã thoát {code})",
  "aiForceStop": "Dừng hẳn",
  "aiResumeSession": "Tiếp tục phiên",
  "aiHistory": "Lịch sử phiên",
  "aiNoUndo": "Hoàn tác đang tắt cho dự án này ({reason})",
  "aiBypassConfirm": "{agent} sẽ sửa tệp và chạy lệnh mà không hỏi.",
  "aiPaneLabel": "Phiên AI với {agent}",
  "aiTabRowLabel": "Phiên AI",
  "aiStatusStarting": "Đang khởi động…",
  "aiStatusNotRunning": "Agent chưa chạy",
  "aiStatusSignIn": "Cần đăng nhập",
  "aiStatusStopped": "Đã dừng",
  "aiStatusWithTime": "{state} · {time}",
  "aiHeaderPanel": "Thay đổi và tệp",
  "aiHeaderTerminal": "Terminal trong tab này",
  "aiHeaderZoom": "Phóng to",
  "aiHeaderMore": "Thêm",
  "aiMenuAgentsSettings": "Cài đặt › Agents",
  "aiMenuRestart": "Khởi động lại agent",
  "aiMenuViewLog": "Xem log",
  "aiLogTitle": "Log của agent (stderr)",
  "aiLogNote": "Chỉ giữ trong bộ nhớ cho mục này; ShellX không ghi vào log của mình.",
  "aiLogEmpty": "(trống)",
  "aiResumeLoading": "Đang nạp hội thoại…",
  "aiYou": "Bạn",
  "aiThinking": "Suy nghĩ",
  "aiToolRead": "Đọc",
  "aiToolEdit": "Sửa",
  "aiToolCreate": "Tạo",
  "aiToolDelete": "Xoá",
  "aiToolMove": "Đổi tên",
  "aiToolSearch": "Tìm",
  "aiToolExecute": "Chạy",
  "aiToolFetch": "Tải",
  "aiToolModeChanged": "Đổi chế độ: {title}",
  "aiToolPending": "chờ",
  "aiToolAwaiting": "chờ bạn",
  "aiToolRunning": "đang chạy · {seconds} s",
  "aiToolDone": "xong",
  "aiToolRejected": "bị từ chối",
  "aiToolStopped": "đã dừng",
  "aiToolFailed": "lỗi",
  "aiToolTook": "{seconds} s",
  "aiToolNoOutput": "Không có đầu ra. Panel Thay đổi vẫn thấy tệp mà lệnh đã đổi.",
  "aiToolInput": "Tham số",
  "aiToolResult": "Kết quả",
  "aiViewFile": "Xem cả tệp",
  "aiOpenInEditor": "Mở trong editor",
  "aiPermWaiting": "Chờ bạn trả lời ở thanh xin quyền phía dưới — phím 1–{n}, Esc để từ chối",
  "aiPermChosen": "Bạn chọn: {label} ({name})",
  "aiPermCancelled": "Lượt bị dừng trước khi bạn trả lời",
  "aiPermAlwaysNote": "“{label}” theo lời agent: {name}",
  "aiTurnStopped": "Đã dừng lượt {n} · {time}",
  "aiTurnInterrupted": "Lượt {n} bị gián đoạn · {time}",
  "aiTurnFailed": "Lượt {n} lỗi · {time}",
  "aiTurnNoChanges": "không đổi tệp nào",
  "aiTurnView": "Xem",
  "aiNotInstalled": "{agent} chưa được cài",
  "aiInstall": "Cài đặt",
  "aiNoNpm": "Không tìm thấy npm cạnh Node.js.",
  "aiNodeGuide": "Hướng dẫn cài",
  "aiCommandMissing": "Không tìm thấy lệnh: {command}",
  "aiCommandShimOnly": "Chỉ tìm thấy tệp .cmd hoặc .bat; ShellX chạy chương trình trực tiếp.",
  "aiAgentOutputInvalid": "{agent} gửi dữ liệu ShellX không đọc được nên đã bị dừng",
  "aiStartFailed": "{agent} không khởi động được",
  "aiRestart": "Khởi động lại",
  "aiRetry": "Thử lại",
  "aiCannotResume": "Agent này không khôi phục được phiên cũ; đã mở phiên mới.",
  "aiFolderMissing": "Thư mục dự án không còn",
  "aiChooseFolder": "Chọn thư mục",
  "aiChooseFolderTitle": "Chọn thư mục dự án",
  "aiChooseFolderBody": "Agent làm việc trong thư mục này.",
  "aiFolderField": "Thư mục",
  "aiFolderInvalid": "Nhập đường dẫn tuyệt đối của một thư mục có thật.",
  "aiFolderUse": "Dùng thư mục này",
  "aiUndoNoGit": "không tìm thấy git",
  "aiUndoNoCommandLineTools": "chưa cài Command Line Tools",
  "aiUndoGitTooOld": "git cũ hơn 2.26",
  "aiUndoTooManyFiles": "hơn 200 000 tệp",
  "aiUndoTooSlow": "lần chụp đầu quá 30 s",
  "aiUndoFailed": "chụp điểm khôi phục lỗi",
  "aiNoUndoTurn": "Hoàn tác đang tắt cho lượt này ({reason})",
  "aiClaudeOff": "Tích hợp Claude đang tắt (ai-agent-claude = off).",
  "aiAgentUnknown": "Agent này không còn trong Cài đặt › Agents.",
  "aiSend": "Gửi",
  "aiQueue": "Xếp hàng",
  "aiStop": "Dừng",
  "aiQueued": "Xếp hàng: “{text}” — gửi khi lượt này xong",
  "aiQueueRemove": "Bỏ",
  "aiQueueFull": "Tối đa 5 tin có thể chờ.",
  "aiCannotSend": "Agent chưa nhận tin lúc này.",
  "aiContextUsed": "Ngữ cảnh {percent}%",
  "aiPlan": "Kế hoạch · {done}/{total} xong",
  "aiPlanHigh": "ưu tiên",
  "aiComposerWaiting": "Đang chờ agent…",
  "aiMention": "Nhắc một tệp (@)",
  "aiCommands": "Lệnh của agent (/)",
  "aiAttachImage": "Đính ảnh (dán hoặc kéo thả)",
  "aiRemoveImage": "Bỏ ảnh",
  "aiImageUnsupported": "{agent} không nhận ảnh.",
  "aiNoMatches": "Không có kết quả",
  "aiPanelChanges": "Thay đổi",
  "aiPanelFiles": "Tệp",
  "aiScopeTurn": "Lượt này",
  "aiScopeSession": "Cả phiên",
  "aiChangesNoTurn": "Chưa có lượt nào. Trước mỗi lượt, ShellX chụp thư mục dự án vào một repo git ẩn; mọi thay đổi sau đó hiện ở đây, kể cả khi agent sửa bằng lệnh shell.",
  "aiChangesEmpty": "Không có thay đổi nào từ lúc đó.",
  "aiReviewed": "Đã xem",
  "aiRevertFile": "Hoàn tác tệp này",
  "aiCheckpoint": "Điểm khôi phục: trước lượt {n} · {hash}",
  "aiIgnoredNote": "Không theo dõi tệp bị .gitignore bỏ qua.",
  "aiOutsideNote": "Không theo dõi thay đổi bên ngoài thư mục dự án.",
  "aiRevertDialogTitle": "Có tệp đã đổi sau lượt này",
  "aiRevertDialogBody": "{files} đã bị sửa sau khi lượt kết thúc, có thể do bạn hoặc một phiên khác. Hoàn tác sẽ ghi đè cả thay đổi đó.",
  "aiRevertOnlyClean": "Chỉ hoàn tác tệp chưa sửa",
  "aiRevertAll": "Hoàn tác tất cả",
  "aiRevertBusy": "Đợi lượt đang chạy xong.",
  "aiReverted": "Đã hoàn tác {count} tệp.",
  "aiRevertFailed": "Hoàn tác không thành công.",
  "aiVsTurnStart": "so với đầu lượt",
  "aiVsSessionStart": "so với đầu phiên",
  "aiReadOnly": "chỉ đọc",
  "aiMentionInChat": "Nhắc trong chat",
  "aiBinaryFile": "Tệp nhị phân",
  "aiFileTooLarge": "Tệp quá lớn để hiện",
  "aiIgnored": "bỏ qua",
  "aiFilesNote": "Tệp do agent sửa có nhãn M/A. Bấm một tệp để xem (chỉ đọc).",
  "aiModeDefault": "Hỏi trước",
  "aiModeAcceptEdits": "Tự sửa tệp",
  "aiModePlan": "Lập kế hoạch",
  "aiModeAuto": "Tự động",
  "aiModeBypass": "Bỏ qua mọi quyền",
  "aiBypassTitle": "Bật “Bỏ qua mọi quyền”?",
  "aiBypassNote": "Điểm khôi phục vẫn chạy trước mỗi lượt, nhưng không lấy lại được việc đã ra ngoài máy (git push, gọi API, gửi email).",
  "aiBypassTurnOn": "Bật",
  "aiConfigModel": "Model: {name}",
  "aiConfigEffort": "Suy nghĩ: {name}",
  "aiConfigOther": "{name}: {value}",
  "aiAskSend": "Gửi",
  "aiAskDecline": "Từ chối",
  "aiAskCancel": "Huỷ",
  "aiAskOpen": "Mở trong trình duyệt",
  "aiAskUrlNote": "{agent} nhờ bạn mở trang này:",
  "aiAskAnswered": "Đã trả lời",
  "aiAskDeclined": "Đã từ chối",
  "aiAskCancelled": "Đã huỷ",
  "aiAskCompleted": "Xong",
  "aiAskRequired": "Bắt buộc",
  "aiAskInvalid": "Kiểm tra lại các câu trả lời được đánh dấu.",
  "aiAskUnsupported": "Câu hỏi này dùng kiểu trả lời ShellX chưa hỗ trợ",
  "aiOnboardingAiBody": "Tab mới là một phiên AI: trò chuyện, xem agent làm gì, duyệt thay đổi, không cần gõ lệnh.",
  "aiOnboardingTerminalBody": "Như ShellX hiện nay: tab mới là một shell.",
  "aiOnboardingNote": "Đổi lại được bất cứ lúc nào trong Cài đặt › Chung.",
  "aiIntroText": "Mới: giao diện AI. Bạn muốn tab mới mở theo kiểu nào?",
  "aiSettingsSection": "Giao diện AI",
  "aiAgentReady": "Sẵn sàng",
  "aiAgentNeedsNode": "Thiếu Node {version}",
  "aiAgentNotInstalled": "Chưa cài",
  "aiAgentNeedsLogin": "Cần đăng nhập",
  "aiAgentError": "Lỗi",
  "aiAgentChecking": "Đang kiểm tra…",
  "aiAgentLogin": "Đăng nhập",
  "aiDefaultAgent": "Agent mặc định",
  "aiAddCustomAgent": "Thêm agent tuỳ chỉnh",
  "aiCustomName": "Tên",
  "aiCustomCommand": "Lệnh (đường dẫn tuyệt đối hoặc tên trên PATH)",
  "aiCustomArgs": "Tham số, mỗi dòng một",
  "aiCustomEnv": "Biến môi trường, TÊN=giá trị mỗi dòng",
  "aiCustomSave": "Lưu",
  "aiCustomRemove": "Xoá",
  "aiCustomInvalid": "Nhập tên và lệnh.",
  "aiSettingClaude": "Claude trong giao diện AI",
  "aiSettingClaudeDesc": "Chạy Claude Code qua adapter Claude Agent. Tắt thì ẩn Claude ở mọi nơi.",
  "aiSettingOn": "Bật",
  "aiSettingOff": "Tắt",
  "aiSettingCheckpointDays": "Giữ điểm khôi phục (ngày)",
  "aiSettingCheckpointDaysDesc": "Điểm khôi phục cũ hơn bị xoá khi mở ShellX.",
  "aiSettingNewTabKindDesc": "⌘T / Ctrl+Shift+T, nút + và cửa sổ trống mở loại tab này.",
  "aiDeleteCheckpoints": "Xoá mọi điểm khôi phục",
  "aiDeleteCheckpointsTitle": "Xoá mọi điểm khôi phục?",
  "aiDeleteCheckpointsBody": "Không hoàn tác được các lượt trước lúc này. Dự án của bạn không bị đụng tới.",
  "aiDeleteCheckpointsDone": "Đã xoá điểm khôi phục.",
  "actionNewAiSession": "Phiên AI mới",
  "actionNewTerminalTab": "Tab terminal mới",
  "aiNewSessionTooltip": "Phiên AI mới  {shortcut}",
  "aiCloseRunningTitle": "Dừng lượt và đóng?",
  "aiCloseRunningBody": "{agent} vẫn đang làm việc trong tab này.",
  "aiCloseRunningAction": "Dừng và đóng",
  "aiHistoryEmpty": "Chưa có phiên nào trước đây cho thư mục này.",
  "aiHistoryCurrent": "phiên hiện tại",
  "aiHistoryUnavailable": "{agent} không liệt kê phiên.",
  "aiHistoryUntitled": "Phiên chưa đặt tên",
  "aiRunSheetFailed": "Kết thúc với mã thoát {code}",
  "aiRunSheetNote": "Đây là chương trình của chính agent; ShellX không đọc và không lưu những gì diễn ra ở đây.",
  "aiLoginFailed": "Đăng nhập không thành công.",
  "aiJumpToLatest": "Xuống tin mới nhất",
  "aiShowAllLines": "Hiện cả {count} dòng",
  "aiOutputCut": "Ẩn {count} dòng",
  "aiStopping": "Đang dừng…",
  "aiTurnDone": "Lượt {n} · {time}",
  "aiFileMissing": "Tệp này không còn nữa."
}
```

- [ ] **Step 5: Generate and run the tests**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/l10n
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `gen-l10n` prints only its note about `l10n.yaml`; `All tests passed!` (the existing "both ARB files define exactly the same non-empty messages" test included); `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add apps/desktop/lib/l10n/app_en.arb apps/desktop/lib/l10n/app_vi.arb apps/desktop/lib/l10n/app_localizations.dart apps/desktop/lib/l10n/app_localizations_en.dart apps/desktop/lib/l10n/app_localizations_vi.dart apps/desktop/test/l10n/ai_strings_test.dart
git commit -m "feat(v2-ai): English and Vietnamese strings for the AI tab

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: The tab model — AI tabs, AI panes, nullable `focused` [independent of V2-1a]

D2/D3. `focused` becomes `PaneSession?` (ruling B1), so the analyzer lists every reader. Here the `lib/` readers get null-safe code that behaves exactly as before for terminal tabs; their AI-specific behaviour is Tasks 4, 5 and 7. `isSplit`/`paneCount` follow the layout (ruling B2). The 125 test sites are fixed by script. On a scratch copy this whole task left the desktop suite green (3094 passing).

**Files:**
- Create: `apps/desktop/lib/src/ai/ai_pane_state.dart`
- Create: `apps/desktop/lib/src/terminal/terminal_tabs_ai.dart` (a `part` of `terminal_tabs.dart`)
- Modify: `apps/desktop/lib/src/terminal/terminal_tabs.dart`, `terminal_tabs_panes.dart`, `terminal_tabs_config.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, `session_tab_row.dart`, `sidebar_remote.dart`, `terminal_workspace_page.dart`
- Modify (scripted): 25 files under `apps/desktop/test/` (list in Step 8)
- Create: `apps/desktop/test/support/ai_tabs.dart`
- Test: `apps/desktop/test/terminal/ai_tab_model_test.dart`

**Interfaces:**
- Consumes: `kSyntheticTabIdBase`, `_syntheticTabIds`, `_guardedOpen`, `_adoptPane`, `setRatio`, `focusPane`, `restorePlacementProvider` (existing tab-list internals).
- Produces:
  - `enum TabKind { terminal, ai }`; `bool isAiPaneId(int id)` (negative ids).
  - `final class AiPaneState({required int id, required String agentId, required String agentName, required String title, String? cwd, String? sessionId})` with `copyWith({String? title, Object? cwd, Object? sessionId})`, value equality, `toString() => '…'`. Exported from `terminal/terminal_tabs.dart`.
  - `TerminalTab`: `kind`, `aiPanes`, `isAi`, `AiPaneState? ai`, `bool hasPane(int id)`, `PaneSession? focused`, `DesktopTerminal? terminal`, `DesktopTerminalController? selection`, `TerminalTab aiOnly()`, `factory TerminalTab.ai({required int id, required AiPaneState pane, String? customTitle, TabMeta meta})`; `isSplit => layout is PaneSplit`; `paneCount => paneOrder.length`; `copyWith(... Map<int, AiPaneState>? aiPanes)`.
  - `TerminalTabsState.tabOfPane(int id)`.
  - `TerminalTabs`: `bool Function(int tabId)? aiBusy` (set by Task 10); extension `TerminalTabsAi`: `int openAiTab({required String agentId, required String agentName, required String title, String? cwd, String? sessionId, String? workspace, bool select = true, String? customTitle, TabMeta meta = TabMeta.empty})`, `void updateAiPane(int paneId, AiPaneState Function(AiPaneState) change)`, `Future<int> addAiTerminal(int tabId)`; `const double kAiPaneRatio = 0.72`.
  - Test helper `TerminalTab openTestAiTab(ProviderContainer c, {String agentId = 'claude', String agentName = 'Claude', String title = 'New AI session', String? cwd = '/w/project', String? sessionId, String? workspace, bool select = true})`.

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/support/ai_tabs.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

/// Opens an AI tab through the tab list (V2-1 D2, D3) and returns it.
TerminalTab openTestAiTab(
  ProviderContainer c, {
  String agentId = 'claude',
  String agentName = 'Claude',
  String title = 'New AI session',
  String? cwd = '/w/project',
  String? sessionId,
  String? workspace,
  bool select = true,
}) {
  final id = c
      .read(terminalTabsProvider.notifier)
      .openAiTab(
        agentId: agentId,
        agentName: agentName,
        title: title,
        cwd: cwd,
        sessionId: sessionId,
        workspace: workspace,
        select: select,
      );
  return c.read(terminalTabsProvider).tabs.firstWhere((t) => t.id == id);
}
```

`apps/desktop/test/terminal/ai_tab_model_test.dart`:

```dart
import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart' show LocalSessions;
import 'package:shellx_core/shellx_core.dart' show DriverSide;
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart'
    show settingsStoreProvider;
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../cli/support/cli_container.dart';
import '../support/ai_tabs.dart';
import '../support/fake_local_sessions.dart';

void main() {
  late FakeLocalSessions local;
  late ProviderContainer c;

  TerminalTabsState tabs() => c.read(terminalTabsProvider);
  TerminalTab tabById(int id) => tabs().tabs.firstWhere((t) => t.id == id);

  setUp(() async {
    local = FakeLocalSessions();
    c = cliContainer(local);
    await c.read(terminalTabsProvider.notifier).openTab(); // session 100
  });

  test('an AI tab: synthetic id, one negative AI leaf, selected (D2, D3)', () {
    final tab = openTestAiTab(c, title: 'Fix login');
    expect(tab.id, greaterThanOrEqualTo(kSyntheticTabIdBase));
    expect(tab.isAi, isTrue);
    expect(tab.ai!.id, lessThan(0));
    expect(isAiPaneId(tab.ai!.id), isTrue);
    expect(tab.layout, PaneLeaf(tab.ai!.id));
    expect(tab.panes, isEmpty);
    expect(tab.paneOrder, [tab.ai!.id]);
    expect(tab.paneCount, 1);
    expect(tab.isSplit, isFalse);
    expect(tabs().selectedId, tab.id);
    expect(tabs().tabOfPane(tab.ai!.id)?.id, tab.id);
    expect(tabs().tabOfSession(tab.ai!.id), isNull);
  });

  test('getters of a tab without a terminal pane are null or empty (D2)', () {
    final tab = openTestAiTab(c, title: 'Fix login', cwd: '/w/shop');
    expect(tab.focused, isNull);
    expect(tab.label, 'Fix login');
    expect(tab.automaticLabel, 'Fix login');
    expect(tab.cwd, '/w/shop');
    expect(tab.terminal, isNull);
    expect(tab.selection, isNull);
    expect(tab.runningCommand, isFalse);
    expect(tab.exitCode, isNull);
    expect(tab.exited, isFalse);
    expect(tab.gitBranch, isNull);
    expect(tab.ports, isEmpty);
    expect(tab.hasContext, isFalse);
    expect(tab.driver, DriverSide.desktop);
    expect(tab.noticeLabel(tab.ai!.id), 'Fix login');
    expect(tab.ai.toString(), '…');
  });

  test('ids never repeat; a custom name wins over the session title', () {
    final a = openTestAiTab(c);
    final b = openTestAiTab(c, select: false);
    expect(b.id, isNot(a.id));
    expect(b.ai!.id, lessThan(a.ai!.id));
    expect(tabs().selectedId, a.id, reason: 'select: false keeps it');
    c.read(terminalTabsProvider.notifier).rename(a.id, 'Mine');
    expect(tabById(a.id).label, 'Mine');
  });

  test('updateAiPane changes title, folder and session, and only then', () {
    final tab = openTestAiTab(c, cwd: null);
    final paneId = tab.ai!.id;
    final before = tabs();
    c.read(terminalTabsProvider.notifier).updateAiPane(paneId, (p) => p);
    expect(identical(tabs(), before), isTrue);
    c
        .read(terminalTabsProvider.notifier)
        .updateAiPane(
          paneId,
          (p) => p.copyWith(title: 'Login bug', cwd: '/w', sessionId: 's-1'),
        );
    final ai = tabById(tab.id).ai!;
    expect([ai.title, ai.cwd, ai.sessionId], ['Login bug', '/w', 's-1']);
    expect(tabById(tab.id).label, 'Login bug');
  });

  test('focusPane reaches the AI pane; pane moves refuse AI tabs (D3)', () {
    final ai = openTestAiTab(c);
    final notifier = c.read(terminalTabsProvider.notifier);
    notifier.select(100);
    notifier.focusPane(ai.ai!.id);
    expect(tabs().selectedId, ai.id, reason: 'as for a terminal pane');
    expect(tabById(ai.id).focusedPaneId, ai.ai!.id);
    expect(notifier.joinPane(100, ai.id), isFalse);
    expect(notifier.breakPane(ai.ai!.id), isFalse);
  });

  test('the Terminal button adds one pane under the AI pane, 72 % above; '
      'closing it keeps the tab (D3)', () async {
    final ai = openTestAiTab(c, cwd: '/w/shop');
    final notifier = c.read(terminalTabsProvider.notifier);
    final term = await notifier.addAiTerminal(ai.id);
    var tab = tabById(ai.id);
    expect(tab.isSplit, isTrue);
    expect(tab.paneCount, 2);
    final split = tab.layout as PaneSplit;
    expect(split.axis, SplitAxis.column);
    expect(split.ratio, closeTo(kAiPaneRatio, 0.001));
    expect(split.first, PaneLeaf(ai.ai!.id));
    expect(split.second, PaneLeaf(term));
    expect(tab.focused?.id, term);
    expect(local.openCwds.last, '/w/shop');
    expect(local.openTabIds.last, ai.id);
    expect(await notifier.addAiTerminal(ai.id), term, reason: 'one only');
    notifier.closePane(term);
    tab = tabById(ai.id);
    expect(tab.panes, isEmpty);
    expect(tab.layout, PaneLeaf(ai.ai!.id));
    expect(tab.focusedPaneId, ai.ai!.id);
  });

  test('AI tabs outlive a rebuild of the tab list (Review Focus 3)', () async {
    // A new background-service link is a new LocalSessions: the tab list
    // rebuilds from its sessions.
    final first = FakeLocalSessions();
    final link = NotifierProvider<_Link, LocalSessions>(() => _Link(first));
    final r = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWith((ref) => ref.watch(link)),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      ],
    );
    await r.read(terminalTabsProvider.notifier).openTab();
    final ai = openTestAiTab(r, title: 'Kept');
    await r.read(terminalTabsProvider.notifier).addAiTerminal(ai.id);
    r.read(link.notifier).set(FakeLocalSessions());
    final again = r.read(terminalTabsProvider);
    final kept = again.tabs.where((t) => t.id == ai.id).single;
    expect(kept.ai!.title, 'Kept');
    expect(kept.panes, isEmpty, reason: 'the old sessions are gone');
    expect(kept.layout, PaneLeaf(ai.ai!.id));
    expect(again.selectedId, ai.id);
  });

  test('closing an AI tab removes it', () {
    final ai = openTestAiTab(c);
    c.read(terminalTabsProvider.notifier).close(ai.id);
    expect(tabs().tabs.any((t) => t.id == ai.id), isFalse);
  });
}

class _Link extends Notifier<LocalSessions> {
  _Link(this.first);
  final LocalSessions first;

  @override
  LocalSessions build() => first;

  void set(LocalSessions next) => state = next;
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/ai_tab_model_test.dart`
Expected: compilation fails, `The method 'openAiTab' isn't defined for the type 'TerminalTabs'`.

- [ ] **Step 3: Create `AiPaneState`**

`apps/desktop/lib/src/ai/ai_pane_state.dart`:

```dart
import 'package:flutter/foundation.dart';

/// V2-1 D2: what a tab mainly holds.
enum TabKind { terminal, ai }

/// V2-1 D3: AI pane ids are negative, counted down from -1 by the tab list
/// and never reused in a run. Session ids (the daemon counts from 1) and
/// tab ids (session ids, or the synthetic range from 2e9) are positive, so
/// the spaces never meet. A negative pane id must never reach
/// `LocalSessions`, the terminal links, or restore's `keyOf` (which negates
/// tab ids for a displaced tab, A11 D20).
bool isAiPaneId(int id) => id < 0;

const Object _unset = Object();

/// The tab list's record of an AI pane (V2-1 D2, D3, D14). The conversation
/// lives in the pane's runtime (`ai/ai_runtimes.dart`), never here; nothing
/// here is ever logged ([toString] is `…`, D20).
@immutable
final class AiPaneState {
  const AiPaneState({
    required this.id,
    required this.agentId,
    required this.agentName,
    required this.title,
    this.cwd,
    this.sessionId,
  });

  /// The pane's leaf id in its tab's tree: negative.
  final int id;

  /// A catalog id (`claude`, `codex`, `gemini`, `opencode`) or a custom
  /// agent's id.
  final String agentId;

  /// What the header, the sidebar and notifications call the agent
  /// ("Claude", never "Claude Code": D21).
  final String agentName;

  /// The automatic tab title (D2): the session title, else the first
  /// prompt (40 characters), else "New AI session" in the app language.
  final String title;

  /// The project folder; null until the user chooses one (D5).
  final String? cwd;

  /// The agent's session; a runtime made while it is set reopens it with
  /// `session/load` (D14, D15). Null before the first session exists.
  final String? sessionId;

  AiPaneState copyWith({
    String? title,
    Object? cwd = _unset,
    Object? sessionId = _unset,
  }) => AiPaneState(
    id: id,
    agentId: agentId,
    agentName: agentName,
    title: title ?? this.title,
    cwd: identical(cwd, _unset) ? this.cwd : cwd as String?,
    sessionId: identical(sessionId, _unset)
        ? this.sessionId
        : sessionId as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is AiPaneState &&
      other.id == id &&
      other.agentId == agentId &&
      other.agentName == agentName &&
      other.title == title &&
      other.cwd == cwd &&
      other.sessionId == sessionId;

  @override
  int get hashCode =>
      Object.hash(id, agentId, agentName, title, cwd, sessionId);

  @override
  String toString() => '…';
}
```

- [ ] **Step 4: Create the AI part of the tab list**

`apps/desktop/lib/src/terminal/terminal_tabs_ai.dart`:

```dart
part of 'terminal_tabs.dart';

// V2-1 D2, D3: AI tabs — a tab whose main pane is an AI pane (a negative
// leaf, its record in [TerminalTab.aiPanes]). The agent and the
// conversation live in the AI runtimes; the tab list holds only what the
// sidebar, the window, the command line and restore need.

/// D3: the AI pane's share of its tab once a terminal pane joins it.
const double kAiPaneRatio = 0.72;

/// Uses [TerminalTabs._ref] and [TerminalTabs._state], as the other parts.
extension TerminalTabsAi on TerminalTabs {
  /// D5: a new AI tab holding one AI pane, placed like any desktop tab (in
  /// the current workspace) or straight into [workspace]; selected unless
  /// [select] is false. [cwd] null: the pane asks for a folder first.
  /// [sessionId]: the session it reopens (`session/load`, D14/D15). Starts
  /// nothing: the pane starts its agent when it is shown. Returns the id.
  int openAiTab({
    required String agentId,
    required String agentName,
    required String title,
    String? cwd,
    String? sessionId,
    String? workspace,
    bool select = true,
    String? customTitle,
    TabMeta meta = TabMeta.empty,
  }) {
    final tab = TerminalTab.ai(
      id: kSyntheticTabIdBase + _syntheticTabIds++,
      pane: AiPaneState(
        id: _nextAiPaneId--,
        agentId: agentId,
        agentName: agentName,
        title: title,
        cwd: cwd,
        sessionId: sessionId,
      ),
      customTitle: customTitle,
      meta: meta,
    );
    // Before the tab appears: the sidebar takes it as it places the tab.
    if (workspace != null) {
      _ref.read(restorePlacementProvider).pending[tab.id] = workspace;
    }
    if (select) _restoreMaySelect = false;
    _set(
      tabs: [..._state.tabs, tab],
      selectedId: select ? tab.id : _state.selectedId ?? tab.id,
    );
    return tab.id;
  }

  /// Changes AI pane [paneId] (title, folder, session). Nothing when the
  /// pane is gone or nothing changed (no rebuild, no layout save).
  void updateAiPane(int paneId, AiPaneState Function(AiPaneState pane) change) {
    final tab = _state.tabOfPane(paneId);
    final pane = tab?.aiPanes[paneId];
    if (tab == null || pane == null) return;
    final next = change(pane);
    if (next == pane) return;
    _replaceTab(tab.copyWith(aiPanes: {...tab.aiPanes, paneId: next}));
  }

  /// D3 "Terminal": a terminal pane under tab [tabId]'s AI pane, in the
  /// session's folder, focused; the AI pane keeps [kAiPaneRatio]. With one
  /// there already, that one is focused. Returns the terminal pane's id.
  /// Throws as [splitPaneFor] does.
  Future<int> addAiTerminal(int tabId) async {
    final tab = _tab(tabId);
    final ai = tab?.ai;
    if (tab == null || ai == null) throw const PaneGoneException();
    final existing = tab.paneOrder.where(tab.panes.containsKey).firstOrNull;
    if (existing != null) {
      focusPane(existing);
      return existing;
    }
    if (_state.opening) throw const OpenBusyException();
    final TerminalGrid grid = (
      cols: _grid.cols,
      rows: max(1, (_grid.rows * (1 - kAiPaneRatio)).floor() - 1),
    );
    return _guardedOpen(
      () => _local.open(
        cols: grid.cols,
        rows: grid.rows,
        cwd: ai.cwd,
        tabId: tab.id,
      ),
      (id) {
        _adoptPane(
          id,
          tabId: tab.id,
          target: ai.id,
          axis: SplitAxis.column,
          size: grid,
          focus: true,
        );
        if (_state.tabOfSession(id) == null) throw const PaneGoneException();
        setRatio(tab.id, '', kAiPaneRatio);
        return id;
      },
    );
  }
}
```

- [ ] **Step 5: Change `TerminalTab`, the state and the notifier**

In `apps/desktop/lib/src/terminal/terminal_tabs.dart`, replace:

```dart
import '../agent/desktop_services.dart' show clockProvider;
```

with:

```dart
import '../agent/desktop_services.dart' show clockProvider;
import '../ai/ai_pane_state.dart';
```

In `apps/desktop/lib/src/terminal/terminal_tabs.dart`, replace:

```dart
part 'terminal_tabs_config.dart';
```

with:

```dart
export '../ai/ai_pane_state.dart';

part 'terminal_tabs_ai.dart';
part 'terminal_tabs_config.dart';
```

In `apps/desktop/lib/src/terminal/terminal_tabs.dart`, replace:

```dart
/// A sidebar tab (A3 P1): a tree of panes, one session each. Its id is the
/// id of the session that created it and never changes (D1). The A1/A2
/// getters read the focused pane, so the sidebar, the workspaces and A4
/// read a tab exactly as before.
@immutable
final class TerminalTab {
  const TerminalTab({
    required this.id,
    required this.origin,
    required this.layout,
    required this.panes,
    required this.focusedPaneId,
    this.zoomedPaneId,
    this.paneHistory = const [],
    this.customTitle,
    this.meta = TabMeta.empty,
  });
```

with:

```dart
/// A sidebar tab (A3 P1): a tree of panes, one session each. Its id is the
/// id of the session that created it and never changes (D1). The A1/A2
/// getters read the focused pane, so the sidebar, the workspaces and A4
/// read a tab exactly as before.
///
/// V2-1 D2/D3: an AI tab ([kind] [TabKind.ai]) has a synthetic id and one
/// AI pane, a negative leaf whose record is in [aiPanes]; a terminal pane
/// may join it under the AI pane. Its [focused] is null whenever the AI
/// pane has the focus, and the terminal getters then answer null or empty.
@immutable
final class TerminalTab {
  const TerminalTab({
    required this.id,
    required this.origin,
    required this.layout,
    required this.panes,
    required this.focusedPaneId,
    this.zoomedPaneId,
    this.paneHistory = const [],
    this.customTitle,
    this.meta = TabMeta.empty,
    this.kind = TabKind.terminal,
    this.aiPanes = const {},
  });

  /// V2-1 D2/D3: an AI tab with its one AI pane and no terminal pane.
  factory TerminalTab.ai({
    required int id,
    required AiPaneState pane,
    String? customTitle,
    TabMeta meta = TabMeta.empty,
  }) => TerminalTab(
    id: id,
    origin: SessionOrigin.desktop,
    layout: PaneLeaf(pane.id),
    panes: const {},
    focusedPaneId: pane.id,
    paneHistory: [pane.id],
    customTitle: customTitle,
    meta: meta,
    kind: TabKind.ai,
    aiPanes: {pane.id: pane},
  );
```

In `apps/desktop/lib/src/terminal/terminal_tabs.dart`, replace:

```dart
  /// A11 D18: pin, one-line description and status, all the user's.
  final TabMeta meta;

  PaneSession get focused => panes[focusedPaneId]!;

  /// D23: reading order.
  List<int> get paneOrder => paneIds(layout);
  int get paneCount => panes.length;
  bool get isSplit => panes.length > 1;

  /// 1-based position of [sessionId] in [paneOrder] ("Pane 2 of 3").
  int paneNumber(int sessionId) => paneOrder.indexOf(sessionId) + 1;

  int get index => focused.index;
  String get shell => focused.shell;
  String get title => focused.title;
  bool get runningCommand => focused.runningCommand;
  DesktopTerminal get terminal => focused.terminal;
  DesktopTerminalController get selection => focused.selection;
  String? get cwd => focused.cwd;
  String? get gitBranch => focused.gitBranch;
  List<int> get ports => focused.ports;
  int? get exitCode => focused.exitCode;
  bool get exited => focused.exited;
  String get automaticLabel => focused.automaticLabel;
```

with:

```dart
  /// A11 D18: pin, one-line description and status, all the user's.
  final TabMeta meta;

  /// V2-1 D2.
  final TabKind kind;

  /// V2-1 D3: the AI pane of an AI tab, by its negative leaf id. Not a
  /// session: never in [panes].
  final Map<int, AiPaneState> aiPanes;

  bool get isAi => kind == TabKind.ai;

  /// The AI pane of an AI tab (exactly one, D3); null for a terminal tab.
  AiPaneState? get ai => aiPanes.values.firstOrNull;

  /// Pane [id] (a session or an AI pane) is a leaf of this tab.
  bool hasPane(int id) => panes.containsKey(id) || aiPanes.containsKey(id);

  /// The focused pane when it is a terminal pane; null while an AI pane
  /// has the focus (V2-1 D2): readers must not reach a terminal then.
  PaneSession? get focused => panes[focusedPaneId];

  /// D23: reading order (V2-1: the AI pane is a leaf too).
  List<int> get paneOrder => paneIds(layout);

  /// The leaves: terminal panes and the AI pane (V2-1 D3).
  int get paneCount => paneOrder.length;
  bool get isSplit => layout is PaneSplit;

  /// 1-based position of [sessionId] in [paneOrder] ("Pane 2 of 3").
  int paneNumber(int sessionId) => paneOrder.indexOf(sessionId) + 1;

  int get index => focused?.index ?? 0;
  String get shell => focused?.shell ?? '';
  String get title => isAi ? ai?.title ?? '' : focused?.title ?? '';
  bool get runningCommand => focused?.runningCommand ?? false;
  DesktopTerminal? get terminal => focused?.terminal;
  DesktopTerminalController? get selection => focused?.selection;

  /// V2-1 D2: an AI tab's folder is its session's.
  String? get cwd => isAi ? ai?.cwd : focused?.cwd;
  String? get gitBranch => isAi ? null : focused?.gitBranch;
  List<int> get ports => isAi ? const [] : focused?.ports ?? const [];
  int? get exitCode => focused?.exitCode;
  bool get exited => focused?.exited ?? false;

  /// V2-1 D2: an AI tab's automatic title is its session's.
  String get automaticLabel =>
      isAi ? ai?.title ?? '' : focused?.automaticLabel ?? '';
```

In `apps/desktop/lib/src/terminal/terminal_tabs.dart`, replace:

```dart
  bool get hasContext => focused.hasContext;
```

with:

```dart
  /// V2-1 §4.7: an AI tab's second line is its agent's state instead.
  bool get hasContext => !isAi && (focused?.hasContext ?? false);
```

In `apps/desktop/lib/src/terminal/terminal_tabs.dart`, replace:

```dart
  DriverSide get driver => phoneDriving ? DriverSide.phone : focused.driver;
```

with:

```dart
  DriverSide get driver =>
      phoneDriving ? DriverSide.phone : focused?.driver ?? DriverSide.desktop;
```

In `apps/desktop/lib/src/terminal/terminal_tabs.dart`, replace:

```dart
  TerminalTab withPane(int id, PaneSession Function(PaneSession pane) change) {
    final pane = panes[id];
    return pane == null ? this : copyWith(panes: {...panes, id: change(pane)});
  }
```

with:

```dart
  TerminalTab withPane(int id, PaneSession Function(PaneSession pane) change) {
    final pane = panes[id];
    return pane == null ? this : copyWith(panes: {...panes, id: change(pane)});
  }

  /// V2-1 D2: this AI tab with its AI pane alone (its terminal panes'
  /// sessions are gone: a rebuild of the tab list).
  TerminalTab aiOnly() {
    final pane = ai;
    if (pane == null) return this;
    return copyWith(
      layout: PaneLeaf(pane.id),
      panes: const {},
      focusedPaneId: pane.id,
      zoomedPaneId: null,
      paneHistory: [pane.id],
    );
  }
```

In `apps/desktop/lib/src/terminal/terminal_tabs.dart`, replace:

```dart
    Object? customTitle = _unset,
    TabMeta? meta,
  }) => TerminalTab(
```

with:

```dart
    Object? customTitle = _unset,
    TabMeta? meta,
    Map<int, AiPaneState>? aiPanes,
  }) => TerminalTab(
```

In `apps/desktop/lib/src/terminal/terminal_tabs.dart`, replace:

```dart
    meta: meta ?? this.meta,
  );
}

@immutable
final class TerminalTabsState {
```

with:

```dart
    meta: meta ?? this.meta,
    kind: kind,
    aiPanes: aiPanes ?? this.aiPanes,
  );
}

@immutable
final class TerminalTabsState {
```

In `apps/desktop/lib/src/terminal/terminal_tabs.dart`, replace:

```dart
  /// The tab holding session [sessionId] (A3 D1: not always `tab.id`).
  TerminalTab? tabOfSession(int sessionId) {
    for (final tab in tabs) {
      if (tab.panes.containsKey(sessionId)) return tab;
    }
    return null;
  }
}
```

with:

```dart
  /// The tab holding session [sessionId] (A3 D1: not always `tab.id`).
  TerminalTab? tabOfSession(int sessionId) {
    for (final tab in tabs) {
      if (tab.panes.containsKey(sessionId)) return tab;
    }
    return null;
  }

  /// V2-1 D3: the tab holding pane [id] — a session or an AI pane.
  TerminalTab? tabOfPane(int id) {
    for (final tab in tabs) {
      if (tab.hasPane(id)) return tab;
    }
    return null;
  }
}
```

In `apps/desktop/lib/src/terminal/terminal_tabs.dart`, replace:

```dart
  /// A11 D20: tab ids handed out when a broken-out pane's own id is already
  /// a tab's (see [kSyntheticTabIdBase]).
  int _syntheticTabIds = 0;
```

with:

```dart
  /// A11 D20: tab ids handed out when a broken-out pane's own id is already
  /// a tab's (see [kSyntheticTabIdBase]). V2-1 D2: AI tabs take theirs from
  /// the same counter.
  int _syntheticTabIds = 0;

  /// V2-1 D3: the next AI pane id; counts down, never repeats in a run.
  int _nextAiPaneId = -1;

  /// V2-1 D2: the last state, so AI tabs outlive a rebuild ([build]).
  TerminalTabsState? _lastState;

  /// V2-1 D3: whether tab [tabId]'s AI pane runs a turn; set by the AI
  /// runtimes (a close then asks first). Null: never.
  bool Function(int tabId)? aiBusy;
```

In `apps/desktop/lib/src/terminal/terminal_tabs.dart`, replace:

```dart
    _changes = _local.changes.listen((_) => _sync());
    ref.onDispose(_dispose);
    final tabs = _merge(const []);
    return TerminalTabsState(tabs: tabs, selectedId: tabs.firstOrNull?.id);
  }
```

with:

```dart
    _changes = _local.changes.listen((_) => _sync());
    ref.onDispose(_dispose);
    // V2-1 D2: AI tabs are no session's: a rebuild (a new background-service
    // link) keeps them, without the terminal panes of the old sessions.
    final carried = [
      for (final t in _lastState?.tabs ?? const <TerminalTab>[])
        if (t.isAi) t.aiOnly(),
    ];
    listenSelf((_, next) => _lastState = next);
    final tabs = [..._merge(const []), ...carried];
    final kept = _lastState?.selectedId;
    return TerminalTabsState(
      tabs: tabs,
      selectedId: carried.any((t) => t.id == kept)
          ? kept
          : tabs.firstOrNull?.id,
    );
  }
```

- [ ] **Step 6: Refuse pane moves for AI tabs; focus AI panes**

In `apps/desktop/lib/src/terminal/terminal_tabs_panes.dart`, replace:

```dart
    final tab = _state.selected;
    if (tab == null || !tab.isSplit) return false;
    final layout = moves.swapInDirection(
```

with:

```dart
    final tab = _state.selected;
    // V2-1 D3: an AI tab's panes stay where they are.
    if (tab == null || !tab.isSplit || tab.isAi) return false;
    final layout = moves.swapInDirection(
```

In `apps/desktop/lib/src/terminal/terminal_tabs_panes.dart`, replace:

```dart
    return tab != null &&
        tab.isSplit &&
        neighbourPane(
```

with:

```dart
    return tab != null &&
        tab.isSplit &&
        !tab.isAi &&
        neighbourPane(
```

In `apps/desktop/lib/src/terminal/terminal_tabs_panes.dart`, replace:

```dart
  bool breakPane(int sessionId) {
    final tab = _state.tabOfSession(sessionId);
    if (tab == null || !tab.isSplit) return false;
```

with:

```dart
  bool breakPane(int sessionId) {
    final tab = _state.tabOfSession(sessionId);
    // V2-1 D3: a pane never leaves an AI tab.
    if (tab == null || !tab.isSplit || tab.isAi) return false;
```

In `apps/desktop/lib/src/terminal/terminal_tabs_panes.dart`, replace:

```dart
    final from = _state.tabOfSession(sessionId);
    final to = _tab(toTabId);
    if (from == null || to == null || from.id == to.id) return false;
```

with:

```dart
    final from = _state.tabOfSession(sessionId);
    final to = _tab(toTabId);
    if (from == null || to == null || from.id == to.id) return false;
    // V2-1 D3: no pane moves into or out of an AI tab.
    if (from.isAi || to.isAi) return false;
```

In `apps/desktop/lib/src/terminal/terminal_tabs_panes.dart`, replace:

```dart
  void focusPane(int sessionId) {
    final tab = _state.tabOfSession(sessionId);
```

with:

```dart
  void focusPane(int sessionId) {
    // V2-1 D3: an AI pane is focused like a terminal pane.
    final tab = _state.tabOfPane(sessionId);
```

- [ ] **Step 7: Make the `lib/` readers null-safe**

Same behaviour for terminal tabs; for an AI tab these readers now do nothing instead of crashing.

In `apps/desktop/lib/src/terminal/terminal_tabs_config.dart`, replace:

```dart
      WorkingDirectoryKind.inherit =>
        _state.selected?.focused.remote?.launch.host != null
            ? null
            : _state.selected?.focused.cwd,
```

with:

```dart
      // V2-1 §4.7: an AI tab gives its session's folder (its `cwd`).
      WorkingDirectoryKind.inherit =>
        _state.selected?.focused?.remote?.launch.host != null
            ? null
            : _state.selected?.cwd,
```

In `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, replace:

```dart
  Future<void> _openPort(TerminalTab tab, int port) =>
      ref.read(remotePortForwardsProvider.notifier).open(tab.focused, port);
```

with:

```dart
  Future<void> _openPort(TerminalTab tab, int port) async {
    // V2-1 D2: an AI pane has no ports.
    final pane = tab.focused;
    if (pane == null) return;
    await ref.read(remotePortForwardsProvider.notifier).open(pane, port);
  }
```

In `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, replace:

```dart
              remote: tab.focused.remote != null,
```

with:

```dart
              remote: tab.focused?.remote != null,
```

In `apps/desktop/lib/src/ui/terminal/session_tab_row.dart`, replace:

```dart
    final remote = tab.focused.remote;
    final windows =
        remote == null && defaultTargetPlatform == TargetPlatform.windows;
    final home = remote == null ? widget.home : (remote.home ?? '');
    final parts = <String>[
      '${tab.label}${remoteSemantics(l10n, tab.focused)}',
```

with:

```dart
    final pane = tab.focused;
    final remote = pane?.remote;
    final windows =
        remote == null && defaultTargetPlatform == TargetPlatform.windows;
    final home = remote == null ? widget.home : (remote.home ?? '');
    final parts = <String>[
      '${tab.label}${pane == null ? '' : remoteSemantics(l10n, pane)}',
```

In `apps/desktop/lib/src/ui/terminal/session_tab_row.dart`, replace:

```dart
                    if (tab.focused.remote != null) ...[
                      const SizedBox(width: ShellxSpace.s4),
                      RemoteMark(tab.focused),
                    ],
```

with:

```dart
                    if (tab.focused case final pane?
                        when pane.remote != null) ...[
                      const SizedBox(width: ShellxSpace.s4),
                      RemoteMark(pane),
                    ],
```

In `apps/desktop/lib/src/ui/terminal/session_tab_row.dart`, replace:

```dart
                                  tab.focused.remote != null ||
```

with:

```dart
                                  tab.focused?.remote != null ||
```

In `apps/desktop/lib/src/ui/terminal/session_tab_row.dart`, replace:

```dart
    if (tab.focused.remoteState == RemoteState.connecting) {
```

with:

```dart
    if (tab.focused?.remoteState == RemoteState.connecting) {
```

In `apps/desktop/lib/src/ui/terminal/session_tab_row.dart`, replace:

```dart
    final remote = tab.focused.remote;
    final windows =
        remote == null && defaultTargetPlatform == TargetPlatform.windows;
    final style = ShellxText.caption.copyWith(
```

with:

```dart
    final remote = tab.focused?.remote;
    final windows =
        remote == null && defaultTargetPlatform == TargetPlatform.windows;
    final style = ShellxText.caption.copyWith(
```

In `apps/desktop/lib/src/ui/terminal/sidebar_remote.dart`, replace:

```dart
  final key = tab.focused.remote?.hostKey;
```

with:

```dart
  final key = tab.focused?.remote?.hostKey;
```

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

```dart
        tab.focused.automaticLabel,
      ),
```

with:

```dart
        tab.focused?.automaticLabel ?? tab.label,
      ),
```

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

```dart
            ref.read(terminalTabsProvider).selected?.selection.selection !=
            null,
```

with:

```dart
            ref.read(terminalTabsProvider).selected?.selection?.selection !=
            null,
```

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

```dart
            .selected
            ?.focused
            .terminal
            .sendUserText(editLineSequence(i.op)),
```

with:

```dart
            .selected
            ?.focused
            ?.terminal
            .sendUserText(editLineSequence(i.op)),
```

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

```dart
  void _copy() {
    final tab = ref.read(terminalTabsProvider).selected;
    final range = tab?.selection.selection;
    if (tab == null || range == null) return;
    unawaited(
      Clipboard.setData(
        ClipboardData(
          text: selectionText(
            tab.terminal.buffer,
            range,
            tab.selection.selectionMode,
          ),
        ),
      ),
    );
    tab.selection.clearSelection();
  }
```

with:

```dart
  void _copy() {
    // V2-1 D2: only a terminal pane has a terminal selection.
    final pane = ref.read(terminalTabsProvider).selected?.focused;
    final range = pane?.selection.selection;
    if (pane == null || range == null) return;
    unawaited(
      Clipboard.setData(
        ClipboardData(
          text: selectionText(
            pane.terminal.buffer,
            range,
            pane.selection.selectionMode,
          ),
        ),
      ),
    );
    pane.selection.clearSelection();
  }
```

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

```dart
  void _selectAll() {
    final tab = ref.read(terminalTabsProvider).selected;
    if (tab == null) return;
    final buffer = tab.terminal.buffer;
    tab.selection.setSelection(
      buffer.createAnchor(0, 0),
      buffer.createAnchor(tab.terminal.viewWidth, buffer.height - 1),
      mode: SelectionMode.line,
    );
  }
```

with:

```dart
  void _selectAll() {
    // V2-1 D2: with the AI pane focused, its own fields take ⌘A.
    final pane = ref.read(terminalTabsProvider).selected?.focused;
    if (pane == null) return;
    final buffer = pane.terminal.buffer;
    pane.selection.setSelection(
      buffer.createAnchor(0, 0),
      buffer.createAnchor(pane.terminal.viewWidth, buffer.height - 1),
      mode: SelectionMode.line,
    );
  }
```

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

```dart
    final terminal = tab.focused.terminal;
```

with:

```dart
    // V2-1 D2: nothing to paste into while the AI pane has the focus (its
    // composer takes ⌘V itself).
    final terminal = tab.focused?.terminal;
    if (terminal == null) return;
```

Run `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze lib` → `No issues found!`.

- [ ] **Step 8: Fix the test sites by script**

Write the two scripts to a temp folder outside the repo (they are tools, not committed):

`$TMPDIR/v21b-tools/add_bang.py`:

```python
#!/usr/bin/env python3
"""Adds `!` where `dart analyze --format=machine` reports a nullable value
used as non-null (unchecked_use_of_nullable_value) or passed where a
non-null type is needed (argument_type_not_assignable from `X?` to `X`).
Reads the analyzer output on stdin; edits only files under test/."""
import collections, re, sys

fixes = collections.defaultdict(list)  # path -> [(line, col, len, code)]
for raw in sys.stdin:
    parts = raw.rstrip('\n').split('|')
    if len(parts) < 8 or parts[0] != 'ERROR':
        continue
    code, path = parts[2], parts[3]
    if '/test/' not in path:
        continue
    line, col, length = int(parts[4]), int(parts[5]), int(parts[6])
    msg = '|'.join(parts[7:])
    if code == 'UNCHECKED_USE_OF_NULLABLE_VALUE':
        fixes[path].append((line, col, length, 'recv'))
    elif code == 'ARGUMENT_TYPE_NOT_ASSIGNABLE' and re.search(r"type '(\w+)\?' can't be assigned", msg):
        fixes[path].append((line, col, length, 'arg'))

for path, items in fixes.items():
    lines = open(path).read().split('\n')
    # Right to left on each line so earlier columns stay valid.
    for line, col, length, kind in sorted(items, key=lambda x: (x[0], -x[1])):
        text = lines[line - 1]
        i = col - 1
        if kind == 'arg':
            at = i + length
            lines[line - 1] = text[:at] + '!' + text[at:]
            continue
        j = i - 1
        while j >= 0 and text[j] in ' \t':
            j -= 1
        if j < 0 or text[j] != '.':
            print(f'skip {path}:{line}:{col}', file=sys.stderr)
            continue
        if j >= 1 and text[j - 1] == '?':
            print(f'skip ?. {path}:{line}:{col}', file=sys.stderr)
            continue
        lines[line - 1] = text[:j] + '!' + text[j:]
    open(path, 'w').write('\n'.join(lines))
    print(f'{path}: {len(items)}')
```

`$TMPDIR/v21b-tools/drop_bang.py`:

```python
#!/usr/bin/env python3
"""Removes the `!` that `dart analyze --format=machine` reports as
unnecessary_non_null_assertion, in files under test/ (stdin)."""
import collections, sys

hits = collections.defaultdict(list)
for raw in sys.stdin:
    parts = raw.rstrip('\n').split('|')
    if len(parts) < 8 or parts[2] != 'UNNECESSARY_NON_NULL_ASSERTION':
        continue
    if '/test/' not in parts[3]:
        continue
    hits[parts[3]].append((int(parts[4]), int(parts[5])))
for path, items in hits.items():
    lines = open(path).read().split('\n')
    for line, col in sorted(items, key=lambda x: (x[0], -x[1])):
        text = lines[line - 1]
        i = col - 1
        if text[i:i + 1] == '!':
            lines[line - 1] = text[:i] + text[i + 1:]
        else:
            print(f'skip {path}:{line}:{col}', file=sys.stderr)
    open(path, 'w').write('\n'.join(lines))
    print(f'{path}: {len(items)}')
```

Run them from `apps/desktop`:

```bash
mkdir -p "$TMPDIR/v21b-tools"   # then save the two files above there
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart analyze --format=machine test | python3 -I "$TMPDIR/v21b-tools/add_bang.py"
PATH=~/fvm/versions/3.41.4/bin:$PATH dart analyze --format=machine test | python3 -I "$TMPDIR/v21b-tools/drop_bang.py"
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: the first script lists 25 files (`test/cli/ui_command_handler_send_test.dart: 3`, `test/restore/restore_persistence_test.dart: 2`, `test/restore/restore_remote_test.dart: 1`, `test/terminal/config_behaviour_test.dart: 11`, `test/terminal/terminal_tabs_panes_test.dart: 3`, `test/terminal/terminal_tabs_resize_test.dart: 10`, `test/terminal/terminal_tabs_restore_test.dart: 3`, `test/terminal/terminal_tabs_test.dart: 17`, `test/ui/command_palette_test.dart: 5`, `test/ui/config_shortcuts_test.dart: 2`, `test/ui/confirm_close_panes_test.dart: 2`, `test/ui/copy_mode_ui_test.dart: 10`, `test/ui/drop_and_image_test.dart: 1`, `test/ui/edit_line_ui_test.dart: 1`, `test/ui/key_sequence_test.dart: 4`, `test/ui/link_layer_test.dart: 13`, `test/ui/pane_find_test.dart: 10`, `test/ui/pane_moves_ui_test.dart: 5`, `test/ui/paste_flow_test.dart: 1`, `test/ui/reopen_closed_ui_test.dart: 7`, `test/ui/resume_banner_ui_test.dart: 1`, `test/ui/search_all_ui_test.dart: 4`, `test/ui/sidebar_remote_test.dart: 1`, `test/ui/terminal_shortcuts_test.dart: 4`, `test/ui/terminal_workspace_test.dart: 4`); the second removes 9 unnecessary `!`; then `No issues found!`. If a count differs (the suite moved on), keep running the pair until `flutter analyze` is clean: the scripts only touch what the analyzer reports. Then format only the files the scripts changed (`git diff --name-only -- test | xargs env PATH=~/fvm/versions/3.41.4/bin:$PATH dart format`; a plain `dart format test` would also rewrap `test/ime/ime_in_place_edit_test.dart` and `test/platform/single_instance_test.dart`, which are not formatter-clean at HEAD) and check that `git diff test` touches only `!` characters (`git diff -U0 test | grep '^[-+] ' | head`).

- [ ] **Step 9: Run the model tests and the whole suite**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/ai lib/src/terminal test/terminal/ai_tab_model_test.dart test/support/ai_tabs.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/ai_tab_model_test.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test 2>&1 | tail -1
```

Expected: `+8: All tests passed!`; the whole suite passes with the baseline count plus 8.

- [ ] **Step 10: Commit**

```bash
git add apps/desktop/lib/src/ai/ai_pane_state.dart apps/desktop/lib/src/terminal apps/desktop/lib/src/ui/terminal apps/desktop/test
git commit -m "feat(v2-ai): AI tabs in the tab model (kind, AI panes, nullable focused pane)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4: Status and attention readers accept AI panes (D13 infrastructure) [independent of V2-1a]

The non-UI readers of spec §2 and §4.7:
- `AgentStatusNotifier` accepts events for a live AI pane: it uses `tabOfPane`, and an AI pane is "alive" while it sits in its tab.
- No 20 s quiet decay for AI panes (Review Focus 1).
- Notices say the AI agent's own name (B6). With no session to carry them, they go straight to `TabAttention.addAiNotice`, which follows the same A4 path as a pane notice: the focused-pane rule, the badge, the panel, and the system notification with its limits.
- Jumps and focus history reach AI panes.
- Closed AI tabs are not offered back (B10).

The runtime that sends these events arrives in Task 10. Here the tests call `ingest` directly.

**Files:**
- Modify: `apps/desktop/lib/src/terminal/agent_status_notifier.dart`, `tab_attention.dart`, `focus_history.dart`, `closed_items.dart`
- Test: `apps/desktop/test/terminal/ai_status_readers_test.dart`

**Interfaces:**
- Consumes: Task 3 (`tabOfPane`, `hasPane`, `isAiPaneId`, `aiPanes`, `openTestAiTab`).
- Produces: `void TabAttention.addAiNotice(int tabId, int paneId, {String? title, required String body})`; `AgentStatusNotifier.ingest` accepts `AgentEvent(pane: <AI pane id>, …)` (Task 10's bridge uses it).

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/terminal/ai_status_readers_test.dart`:

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';
import 'package:shellx_desktop/src/terminal/agent_status_notifier.dart';
import 'package:shellx_desktop/src/terminal/closed_items.dart';
import 'package:shellx_desktop/src/terminal/focus_history.dart';
import 'package:shellx_desktop/src/terminal/tab_attention.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../cli/support/cli_container.dart';
import '../support/ai_tabs.dart';
import '../support/fake_local_sessions.dart';

void main() {
  late FakeLocalSessions local;
  late ProviderContainer c;

  AgentEvent event(int pane, AgentEventKind kind) => AgentEvent(
    pane: pane,
    agent: AgentKind.claude,
    kind: kind,
    at: DateTime.now(),
  );

  setUp(() async {
    local = FakeLocalSessions();
    c = cliContainer(local);
    await c.read(terminalTabsProvider.notifier).openTab(); // tab 100
  });

  test('an AI pane takes A12 events while it is in its tab (D13)', () {
    final ai = openTestAiTab(c, select: false);
    final pane = ai.ai!.id;
    final status = c.read(agentStatusProvider.notifier);
    expect(status.ingest(event(pane, AgentEventKind.start)), isTrue);
    expect(status.ingest(event(pane, AgentEventKind.running)), isTrue);
    expect(c.read(agentStatusProvider)[pane]?.state, AgentState.running);
    expect(c.read(agentTabBadgeProvider(ai.id))?.state, AgentState.running);
    c.read(terminalTabsProvider.notifier).close(ai.id);
    expect(c.read(agentStatusProvider)[pane], isNull);
    expect(status.ingest(event(pane, AgentEventKind.running)), isFalse);
  });

  test('an AI pane stays running past the quiet decay (Review Focus 1)', () {
    fakeAsync((async) {
      final r = cliContainer(FakeLocalSessions());
      final ai = openTestAiTab(r);
      final status = r.read(agentStatusProvider.notifier);
      status.ingest(event(ai.ai!.id, AgentEventKind.start));
      status.ingest(event(ai.ai!.id, AgentEventKind.running));
      async.elapse(kAgentQuietDecay * 3);
      expect(r.read(agentStatusProvider)[ai.ai!.id]?.state, AgentState.running);
      r.dispose();
    });
  });

  test('a question in a hidden AI tab: one entry, one system notification '
      'titled by the tab, in the agent\'s own name (D13, B6)', () async {
    final ai = openTestAiTab(c, title: 'Fix login', select: false);
    final status = c.read(agentStatusProvider.notifier);
    status.ingest(event(ai.ai!.id, AgentEventKind.start));
    status.ingest(event(ai.ai!.id, AgentEventKind.needsInput));
    await pumpEventQueue();
    final entry = c.read(tabAttentionProvider).history.first;
    expect(entry.tabId, ai.id);
    expect(entry.paneId, ai.ai!.id);
    expect(entry.tabLabel, 'Fix login');
    expect(c.read(tabAttentionProvider).unread[ai.id]?.count, 1);
    final sent = systemNotificationsSent(c).single;
    expect(sent.title, 'Fix login');
    expect(sent.body, 'Claude needs your input');
    expect(local.notified, isEmpty, reason: 'no session carries it');
  });

  test('jumping to the notice selects the AI tab and its AI pane', () async {
    final ai = openTestAiTab(c, select: false);
    final status = c.read(agentStatusProvider.notifier);
    status.ingest(event(ai.ai!.id, AgentEventKind.start));
    status.ingest(event(ai.ai!.id, AgentEventKind.needsInput));
    await pumpEventQueue();
    expect(c.read(tabAttentionProvider.notifier).jumpTo(ai.id), isTrue);
    final tabs = c.read(terminalTabsProvider);
    expect(tabs.selectedId, ai.id);
    expect(tabs.selected!.focusedPaneId, ai.ai!.id);
    expect(c.read(tabAttentionProvider).unread[ai.id], isNull);
  });

  test('focus history goes back to an AI pane', () {
    final ai = openTestAiTab(c);
    final tabs = c.read(terminalTabsProvider.notifier);
    c.read(focusHistoryProvider);
    tabs.select(100);
    expect(c.read(focusHistoryProvider.notifier).go(back: true), isTrue);
    expect(c.read(terminalTabsProvider).selectedId, ai.id);
  });

  test('a closed AI tab is not offered back (B10)', () {
    final ai = openTestAiTab(c);
    c.read(closedItemsProvider);
    final before = c.read(closedItemsProvider).length;
    c.read(terminalTabsProvider.notifier).close(ai.id);
    expect(c.read(closedItemsProvider).length, before);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/ai_status_readers_test.dart`
Expected: FAIL. `ingest` answers false for the AI pane (`Expected: true`); `addAiNotice` does not exist yet, so the notice tests find no entry; the focus-history test does not go back; the reopen test finds one more closed item.

- [ ] **Step 3: Implement**

In `apps/desktop/lib/src/terminal/agent_status_notifier.dart`, replace:

```dart
import 'sidebar_workspaces.dart' show settingsStoreProvider;
import 'terminal_tabs.dart';
```

with:

```dart
import 'sidebar_workspaces.dart' show settingsStoreProvider;
import 'tab_attention.dart' show tabAttentionProvider;
import 'terminal_tabs.dart';
```

In `apps/desktop/lib/src/terminal/agent_status_notifier.dart`, replace:

```dart
  bool paneVisible(int pane) {
    final tabs = ref.read(terminalTabsProvider);
    final tab = tabs.tabOfSession(pane);
```

with:

```dart
  bool paneVisible(int pane) {
    final tabs = ref.read(terminalTabsProvider);
    // V2-1 D13: an AI pane is watched like a terminal pane.
    final tab = tabs.tabOfPane(pane);
```

In `apps/desktop/lib/src/terminal/agent_status_notifier.dart`, replace:

```dart
    if (!ref.mounted) return false;
    final pane = ref
        .read(terminalTabsProvider)
        .tabOfSession(e.pane)
        ?.panes[e.pane];
    if (pane == null || pane.exited) {
      return false;
    }
```

with:

```dart
    if (!ref.mounted) return false;
    final tab = ref.read(terminalTabsProvider).tabOfPane(e.pane);
    // V2-1 D13: an AI pane is live while it is in its tab; a terminal pane
    // while its shell runs.
    final live =
        tab != null &&
        (tab.aiPanes.containsKey(e.pane) ||
            !(tab.panes[e.pane]?.exited ?? true));
    if (!live) return false;
```

In `apps/desktop/lib/src/terminal/agent_status_notifier.dart`, replace:

```dart
    final l10n = ref.read(appL10nProvider);
    final name = agentDisplayName(l10n, e.agent);
```

with:

```dart
    final l10n = ref.read(appL10nProvider);
    // V2-1 B6: an AI pane says its own agent's name ("Claude", D21).
    final tab = ref.read(terminalTabsProvider).tabOfPane(e.pane);
    final name =
        tab?.aiPanes[e.pane]?.agentName ?? agentDisplayName(l10n, e.agent);
```

In `apps/desktop/lib/src/terminal/agent_status_notifier.dart`, replace:

```dart
    _noticeAt[e.pane] = e.at;
    final now = _now;
```

with:

```dart
    _noticeAt[e.pane] = e.at;
    if (isAiPaneId(e.pane)) {
      // V2-1 D13: no session carries an AI pane's notice: A4's path
      // directly (same focused-pane rule and limits). The tab names the
      // system notification; the body already says who asks.
      if (tab != null) {
        ref
            .read(tabAttentionProvider.notifier)
            .addAiNotice(tab.id, e.pane, body: body);
      }
      return;
    }
    final now = _now;
```

In `apps/desktop/lib/src/terminal/agent_status_notifier.dart`, replace:

```dart
      final tab = ref.read(terminalTabsProvider).tabOfSession(id)?.id;
      _changes.add(
```

with:

```dart
      final tab = ref.read(terminalTabsProvider).tabOfPane(id)?.id;
      _changes.add(
```

In `apps/desktop/lib/src/terminal/agent_status_notifier.dart`, replace:

```dart
  void _updateLive(int id, AgentPane? before, AgentPane? next) {
    final tab = ref.read(terminalTabsProvider).tabOfSession(id);
```

with:

```dart
  void _updateLive(int id, AgentPane? before, AgentPane? next) {
    final tab = ref.read(terminalTabsProvider).tabOfPane(id);
```

In `apps/desktop/lib/src/terminal/agent_status_notifier.dart`, replace:

```dart
      final others = tab.panes.keys.any(
```

with:

```dart
      final others = tab.paneOrder.any(
```

In `apps/desktop/lib/src/terminal/agent_status_notifier.dart`, replace:

```dart
  void _armQuiet(int id, AgentPane? p) {
    if (p == null || p.state != AgentState.running) {
```

with:

```dart
  void _armQuiet(int id, AgentPane? p) {
    // V2-1 B6: an AI pane's runtime says when a turn ends; its silence (an
    // agent thinking) is not idleness.
    if (p == null || p.state != AgentState.running || isAiPaneId(id)) {
```

In `apps/desktop/lib/src/terminal/agent_status_notifier.dart`, replace:

```dart
    for (final id in trackedPanes) {
      if (tabs.tabOfSession(id) == null) _forget(id);
    }
```

with:

```dart
    for (final id in trackedPanes) {
      if (tabs.tabOfPane(id) == null) _forget(id);
    }
```

In `apps/desktop/lib/src/terminal/agent_status_notifier.dart`, replace:

```dart
    for (final id in state.keys.toList()) {
      final pane = tabs.tabOfSession(id)?.panes[id];
      // A lost server pane keeps its record: a reconnect gives it a new id
      // and the record follows (A8 D22).
      if (pane == null || (pane.exited && !pane.canReconnect)) {
```

with:

```dart
    for (final id in state.keys.toList()) {
      final tab = tabs.tabOfPane(id);
      final pane = tab?.panes[id];
      // V2-1 D13: an AI pane's record lives as long as the pane.
      final ai = tab?.aiPanes.containsKey(id) ?? false;
      // A lost server pane keeps its record: a reconnect gives it a new id
      // and the record follows (A8 D22).
      if (!ai && (pane == null || (pane.exited && !pane.canReconnect))) {
```

In `apps/desktop/lib/src/terminal/tab_attention.dart`, replace:

```dart
  void _onNotice(SessionNotice notice) {
    if (!ref.mounted) return;
    final tabs = ref.read(terminalTabsProvider);
    final tab = tabs.tabOfSession(notice.sessionId);
    if (tab == null) return; // not (or no longer) a pane of this window
    // A12 D10: what a hook event already told (an OSC / bell right after
    // it) is not told twice.
    if (ref.read(agentStatusProvider.notifier).swallowNotice(notice)) return;
    final pane = notice.sessionId;
```

with:

```dart
  void _onNotice(SessionNotice notice) {
    if (!ref.mounted) return;
    final tabs = ref.read(terminalTabsProvider);
    final tab = tabs.tabOfSession(notice.sessionId);
    if (tab == null) return; // not (or no longer) a pane of this window
    // A12 D10: what a hook event already told (an OSC / bell right after
    // it) is not told twice.
    if (ref.read(agentStatusProvider.notifier).swallowNotice(notice)) return;
    _record(tabs, tab, notice);
  }

  /// V2-1 D13: a notice from AI pane [paneId] of tab [tabId] (no session
  /// carries it): the same path as a pane's own notice — the focused-pane
  /// rule, the badge, the panel and the system notification with its
  /// limits (A4).
  void addAiNotice(
    int tabId,
    int paneId, {
    String? title,
    required String body,
  }) {
    if (!ref.mounted) return;
    final tabs = ref.read(terminalTabsProvider);
    final tab = tabs.tabs.where((t) => t.id == tabId).firstOrNull;
    if (tab == null || !tab.aiPanes.containsKey(paneId)) return;
    _record(
      tabs,
      tab,
      SessionNotice(
        sessionId: paneId,
        kind: SessionNoticeKind.message,
        at: DateTime.now(),
        title: title,
        body: body,
      ),
    );
  }

  void _record(TerminalTabsState tabs, TerminalTab tab, SessionNotice notice) {
    final pane = notice.sessionId;
```

In `apps/desktop/lib/src/terminal/tab_attention.dart`, replace:

```dart
    bool paneGone(int tabId, int paneId) =>
        tabId != kCommandLineTabId &&
        !(present[tabId]?.panes.containsKey(paneId) ?? false);
```

with:

```dart
    bool paneGone(int tabId, int paneId) =>
        tabId != kCommandLineTabId &&
        !(present[tabId]?.hasPane(paneId) ?? false);
```

In `apps/desktop/lib/src/terminal/tab_attention.dart`, replace:

```dart
    final tab = ref.read(terminalTabsProvider).tabOfSession(newest ?? -1);
```

with:

```dart
    // V2-1 D13: an AI pane too (negative ids: never a `-1` default here).
    final tab = newest == null
        ? null
        : ref.read(terminalTabsProvider).tabOfPane(newest);
```

In `apps/desktop/lib/src/terminal/focus_history.dart`, replace:

```dart
    if (from != null && next.tabOfSession(from.paneId)?.id != from.tabId) {
```

with:

```dart
    if (from != null && next.tabOfPane(from.paneId)?.id != from.tabId) {
```

In `apps/desktop/lib/src/terminal/focus_history.dart`, replace:

```dart
      ref.read(terminalTabsProvider).tabOfSession(e.paneId)?.id == e.tabId;
```

with:

```dart
      ref.read(terminalTabsProvider).tabOfPane(e.paneId)?.id == e.tabId;
```

In `apps/desktop/lib/src/terminal/closed_items.dart`, replace:

```dart
        for (final MapEntry(key: id, value: pane) in t.panes.entries) {
          if (still.panes.containsKey(id) ||
```

with:

```dart
        // V2-1 B10: nothing of an AI tab is offered back.
        if (t.isAi) continue;
        for (final MapEntry(key: id, value: pane) in t.panes.entries) {
          if (still.panes.containsKey(id) ||
```

In `apps/desktop/lib/src/terminal/closed_items.dart`, replace:

```dart
  void _captureTab(TerminalTab t, DateTime now) {
    final keys = <int, String>{};
```

with:

```dart
  void _captureTab(TerminalTab t, DateTime now) {
    // V2-1 B10: a closed AI tab is not offered back.
    if (t.isAi) return;
    final keys = <int, String>{};
```

- [ ] **Step 4: Run the tests and the A12/A4 suites**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/terminal/ai_status_readers_test.dart test/terminal test/cli test/ui/agent_notify_ui_test.dart test/ui/notifications_panel_test.dart 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `All tests passed!`; `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/terminal/agent_status_notifier.dart apps/desktop/lib/src/terminal/tab_attention.dart apps/desktop/lib/src/terminal/focus_history.dart apps/desktop/lib/src/terminal/closed_items.dart apps/desktop/test/terminal/ai_status_readers_test.dart
git commit -m "feat(v2-ai): A12 status, A4 attention and focus history accept AI panes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: The UI readers of §4.7 — sidebar row, pane tree, shortcuts, palette, close [independent of V2-1a]

The UI side of D2/§4.7:
- **Pane tree:** an AI leaf draws an `AiPaneView`. Here it is a placeholder: header, agent and title, plus the window's keyboard focus. Task 17 replaces its body; the constructor stays.
- **Sidebar row:** an AI mark instead of the shell dot; line 2 shows "{A12 state} · {agent}"; no ports and no branch.
- **Keys in the AI pane:** ⌘A, ⌘C, ⌘V, ⌘F and copy mode do nothing (the composer of Task 15 takes ⌘A/⌘C/⌘V itself). ⌘D opens the tab's terminal (D3).
- **Search all** skips AI leaves (it crashed before).
- **Palette:** no "Move pane to tab" into or out of AI tabs (B10).
- **Close:** ⌘W on the AI pane closes the tab, and asks "Stop the turn and close?" while `aiBusy` says a turn runs.

**Files:**
- Create: `apps/desktop/lib/src/ui/ai/ai_pane_view.dart` (placeholder)
- Modify: `apps/desktop/lib/src/terminal/agent_names.dart`, `terminal_tabs_ai.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/pane_tree_view.dart`, `session_tab_row.dart`, `terminal_workspace_page.dart`, `terminal_workspace_notices.dart`, `close_tab.dart`
- Modify: `apps/desktop/lib/src/ui/config/search_all_overlay.dart`
- Test: `apps/desktop/test/ui/ai_tab_screens_test.dart`

**Interfaces:**
- Consumes: Task 3 (`openAiTab`, `addAiTerminal`, `aiBusy`, `isAiPaneId`), Task 4 (A12 accepts AI panes), Task 2 strings (`aiPaneLabel`, `aiTabRowLabel`, `aiCloseRunning*`).
- Produces:
  - `class AiPaneView({Key? key, required TerminalTab tab, required AiPaneState pane, required bool selected, FocusNode? focusNode})` (Task 17 keeps this constructor).
  - `String agentStatusLabelNamed(AppLocalizations l10n, String name, AgentState state)`.
  - `Future<void> TerminalTabs.openAiTerminal(int tabId)` (used by Task 17's header button).
  - Widget keys `Key('dot.ai')`, `Key('row.ai.<tabId>')`, `Key('ai.header.title')`.

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/ui/ai_tab_screens_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';
import 'package:shellx_desktop/src/terminal/agent_status_notifier.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/config/search_all_overlay.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../support/ai_tabs.dart';
import '../support/config_workspace.dart';

/// V2-1 §7: an AI tab without a terminal pane goes through every screen of
/// §4.7 without a crash, and each does the AI thing.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<void> chord(
    WidgetTester t,
    LogicalKeyboardKey key, {
    bool shift = false,
  }) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(key);
    if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pumpAndSettle();
  }

  Future<(ProviderContainer, TerminalTab)> aiWorkspace(WidgetTester t) async {
    final w = await pumpConfiguredWorkspace(t, platform: TargetPlatform.macOS);
    final ai = openTestAiTab(w.container, title: 'Fix login');
    w.container.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    return (w.container, ai);
  }

  testWidgets('the sidebar row: AI mark, title, agent line, A12 state', (
    t,
  ) async {
    final (c, ai) = await aiWorkspace(t);
    expect(find.byKey(const Key('dot.ai')), findsOneWidget);
    expect(find.text('Fix login'), findsWidgets);
    expect(t.widget<Text>(find.byKey(Key('row.ai.${ai.id}'))).data, 'Claude');
    final status = c.read(agentStatusProvider.notifier);
    for (final kind in [AgentEventKind.start, AgentEventKind.needsInput]) {
      status.ingest(
        AgentEvent(
          pane: ai.ai!.id,
          agent: AgentKind.claude,
          kind: kind,
          at: DateTime.now(),
        ),
      );
    }
    await t.pumpAndSettle();
    expect(
      t.widget<Text>(find.byKey(Key('row.ai.${ai.id}'))).data,
      'Needs input · Claude',
    );
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('⌘A, ⌘C, ⌘V, ⌘F and copy mode do nothing in the AI pane', (
    t,
  ) async {
    final (c, ai) = await aiWorkspace(t);
    for (final key in [
      LogicalKeyboardKey.keyA,
      LogicalKeyboardKey.keyC,
      LogicalKeyboardKey.keyV,
      LogicalKeyboardKey.keyF,
    ]) {
      await chord(t, key);
    }
    await chord(t, LogicalKeyboardKey.keyM, shift: true);
    expect(t.takeException(), isNull);
    expect(find.byKey(ValueKey('find.${ai.ai!.id}')), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('search all lists terminal panes only', (t) async {
    final (c, ai) = await aiWorkspace(t);
    final sources = searchAllSources(c.read(terminalTabsProvider));
    expect(sources.map((s) => s.tabId), isNot(contains(ai.id)));
    expect(sources, isNotEmpty);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('the palette offers no pane moves into or out of an AI tab', (
    t,
  ) async {
    final (c, _) = await aiWorkspace(t);
    await chord(t, LogicalKeyboardKey.keyP, shift: true);
    await t.enterText(find.byType(TextField).last, 'move pane');
    await t.pumpAndSettle();
    expect(find.textContaining('Move pane to tab'), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    // A second terminal tab: tab 100 is a destination, the AI tab is not.
    await c.read(terminalTabsProvider.notifier).openTab();
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    await chord(t, LogicalKeyboardKey.keyP, shift: true);
    await t.enterText(find.byType(TextField).last, 'move pane');
    await t.pumpAndSettle();
    expect(find.textContaining('Move pane to tab'), findsWidgets);
    expect(find.text('Move pane to tab Fix login'), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('⌘D in the AI pane opens a terminal under it (D3)', (t) async {
    final (c, ai) = await aiWorkspace(t);
    await chord(t, LogicalKeyboardKey.keyD);
    final tab = c
        .read(terminalTabsProvider)
        .tabs
        .firstWhere((x) => x.id == ai.id);
    expect(tab.panes, hasLength(1));
    expect((tab.layout as PaneSplit).ratio, closeTo(kAiPaneRatio, 0.01));
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('⌘W closes the AI tab; a running turn asks first (D3)', (
    t,
  ) async {
    final (c, ai) = await aiWorkspace(t);
    final tabs = c.read(terminalTabsProvider.notifier)..aiBusy = (_) => true;
    await chord(t, LogicalKeyboardKey.keyW);
    final request = c.read(windowRouterProvider).confirm!;
    expect(request.title, 'Stop the turn and close?');
    expect(request.body, 'Claude is still working in this tab.');
    request.complete(true);
    await t.pumpAndSettle();
    expect(
      c.read(terminalTabsProvider).tabs.any((x) => x.id == ai.id),
      isFalse,
    );
    tabs.aiBusy = null;
    await disposeWorkspace(t, c);
  }, variant: mac);
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai_tab_screens_test.dart`
Expected: FAIL. The first test throws `Null check operator used on a null value` from `pane_tree_view.dart` (`tab.panes[id]!` on the AI leaf). The others fail on missing keys or `searchAllSources`' null check.

- [ ] **Step 3: The placeholder AI pane**

`apps/desktop/lib/src/ui/ai/ai_pane_view.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';

/// V2-1 D3: an AI pane, the negative leaf of an AI tab. Until the runtime
/// is wired (V2-1b Task 17) it shows the agent and the title, and holds the
/// keyboard the window gives it ([focusNode] is the window's terminal
/// focus while this pane is the selected tab's focused pane).
class AiPaneView extends StatelessWidget {
  const AiPaneView({
    super.key,
    required this.tab,
    required this.pane,
    required this.selected,
    this.focusNode,
  });

  final TerminalTab tab;
  final AiPaneState pane;

  /// The pane's tab is the selected one.
  final bool selected;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      label: l10n.aiPaneLabel(pane.agentName),
      child: ColoredBox(
        color: ShellxDesktopColors.bgTerminal,
        child: Focus(
          focusNode: focusNode,
          autofocus: focusNode != null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 34,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ShellxSpace.s12,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        size: ShellxSizes.icon,
                        color: ShellxDesktopColors.accent,
                      ),
                      const SizedBox(width: ShellxSpace.s6),
                      Text(
                        pane.agentName,
                        style: ShellxText.bodyStrong.copyWith(
                          color: ShellxDesktopColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: ShellxSpace.s8),
                      Expanded(
                        child: Text(
                          tab.label,
                          key: const Key('ai.header.title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ShellxText.small.copyWith(
                            color: ShellxDesktopColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: ShellxDesktopColors.line),
              const Expanded(child: SizedBox.expand()),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: `openAiTerminal` (toasts like ⌘D)**

In `apps/desktop/lib/src/terminal/terminal_tabs_ai.dart`, replace:

```dart
        setRatio(tab.id, '', kAiPaneRatio);
        return id;
      },
    );
  }
}
```

with:

```dart
        setRatio(tab.id, '', kAiPaneRatio);
        return id;
      },
    );
  }

  /// D3 "Terminal" (the header button, ⌘D in the AI pane):
  /// [addAiTerminal], its failures shown as [split]'s are.
  Future<void> openAiTerminal(int tabId) async {
    try {
      await addAiTerminal(tabId);
    } on PaneNoRoomException {
      if (_ref.mounted) _set(notice: const PaneNoRoomNotice());
    } on SessionLimitException catch (error) {
      if (_ref.mounted) _set(notice: SessionLimitNotice(error.max));
    } on SpawnFailedException catch (error) {
      if (_ref.mounted) _set(notice: spawnNoticeFor(error));
    } on PaneGoneException {
      // The new shell ended before it could be placed: nothing to show.
    } on OpenBusyException {
      // Another open is in flight: nothing to add.
    }
  }
}
```

- [ ] **Step 5: The readers**

In `apps/desktop/lib/src/terminal/agent_names.dart`, replace:

```dart
String agentStatusLabel(
  AppLocalizations l10n,
  AgentKind kind,
  AgentState state,
) {
  final name = agentDisplayName(l10n, kind);
  return state == AgentState.needsInput
      ? l10n.agentStatusAnnounce(name)
      : l10n.agentStatusTooltip(name, agentStateWord(l10n, state));
}
```

with:

```dart
String agentStatusLabel(
  AppLocalizations l10n,
  AgentKind kind,
  AgentState state,
) => agentStatusLabelNamed(l10n, agentDisplayName(l10n, kind), state);

/// [agentStatusLabel] for an agent called [name]: an AI pane's own agent
/// ("Claude", V2-1 B6).
String agentStatusLabelNamed(
  AppLocalizations l10n,
  String name,
  AgentState state,
) => state == AgentState.needsInput
    ? l10n.agentStatusAnnounce(name)
    : l10n.agentStatusTooltip(name, agentStateWord(l10n, state));
```

In `apps/desktop/lib/src/ui/terminal/pane_tree_view.dart`, replace:

```dart
    final tab = widget.tab;
    _keys.removeWhere((id, _) => !tab.panes.containsKey(id));
```

with:

```dart
    final tab = widget.tab;
    // V2-1 D3: the AI pane keeps its key (and state) too.
    _keys.removeWhere((id, _) => !tab.hasPane(id));
```

In `apps/desktop/lib/src/ui/terminal/pane_tree_view.dart`, replace:

```dart
  Widget _pane(int id) {
    final l10n = AppLocalizations.of(context);
    final tab = widget.tab;
    final pane = tab.panes[id]!;
```

with:

```dart
  Widget _pane(int id) {
    if (isAiPaneId(id)) return _aiPane(id);
    final l10n = AppLocalizations.of(context);
    final tab = widget.tab;
    final pane = tab.panes[id]!;
```

In `apps/desktop/lib/src/ui/terminal/pane_tree_view.dart`, replace:

```dart
  /// A1 ruling I6 entries; the pane under the pointer is focused first
  /// (D21) so the window actions act on it.
```

with:

```dart
  /// V2-1 D3: the AI pane, a negative leaf with its own header and
  /// composer, no terminal. Keyed like a terminal pane, so a split or a
  /// zoom moves it without losing its state.
  Widget _aiPane(int id) {
    final tab = widget.tab;
    final ai = tab.aiPanes[id];
    final focused = id == tab.focusedPaneId;
    final appearance = ref.watch(terminalAppearanceProvider);
    return KeyedSubtree(
      key: _keyFor(id),
      child: Listener(
        onPointerDown: (_) => _pointerDown(id),
        child: Stack(
          children: [
            Positioned.fill(
              child: ai == null
                  ? const SizedBox.shrink()
                  : AiPaneView(
                      key: ValueKey('ai.$id'),
                      tab: tab,
                      pane: ai,
                      selected: widget.selected,
                      focusNode: widget.selected && focused
                          ? widget.terminalFocus
                          : null,
                    ),
            ),
            // UI-A3 §2.5: the focus outline of a split tab, as for a
            // terminal pane.
            if (tab.isSplit && focused && tab.zoomedPaneId == null)
              Positioned.fill(
                child: IgnorePointer(
                  child: DevicePixelOutline(
                    key: const Key('pane.focusOutline'),
                    color: appearance.focusOutline,
                    devicePixelRatio: View.of(context).devicePixelRatio,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// A1 ruling I6 entries; the pane under the pointer is focused first
  /// (D21) so the window actions act on it.
```

In `apps/desktop/lib/src/ui/terminal/session_tab_row.dart`, replace:

```dart
      if (tab.isSplit) l10n.sidebarPaneCount(tab.paneCount),
      if (tab.exited)
        l10n.sidebarStatusExited(tab.exitCode!)
```

with:

```dart
      if (tab.isSplit) l10n.sidebarPaneCount(tab.paneCount),
      // V2-1 §4.7: an AI tab says so and who its agent is.
      if (tab.ai case final ai?) ...[
        l10n.aiTabRowLabel,
        if (widget.agentStatus == null) ai.agentName,
      ] else if (tab.exited)
        l10n.sidebarStatusExited(tab.exitCode!)
```

In `apps/desktop/lib/src/ui/terminal/session_tab_row.dart`, replace:

```dart
      if (widget.agentStatus case final a?)
        agentStatusLabel(l10n, a.agent, a.state),
      if (tab.gitBranch case final branch?)
```

with:

```dart
      if (widget.agentStatus case final a?)
        switch (tab.ai) {
          final ai? => agentStatusLabelNamed(l10n, ai.agentName, a.state),
          null => agentStatusLabel(l10n, a.agent, a.state),
        },
      if (tab.gitBranch case final branch?)
```

In `apps/desktop/lib/src/ui/terminal/session_tab_row.dart`, replace:

```dart
    final withContext = tab.hasContext;
```

with:

```dart
    // V2-1 §4.7: an AI tab always has its second line (state · agent).
    final withContext = tab.isAi || tab.hasContext;
```

In `apps/desktop/lib/src/ui/terminal/session_tab_row.dart`, replace:

```dart
          child: Center(child: TabStatusDot(tab)),
```

with:

```dart
          child: Center(
            child: tab.isAi ? const _AiTabIcon() : TabStatusDot(tab),
          ),
```

In `apps/desktop/lib/src/ui/terminal/session_tab_row.dart`, replace:

```dart
                    if (widget.agentStatus case final a?) ...[
                      const SizedBox(width: ShellxSpace.s4),
                      AgentBadge(
```

with:

```dart
                    // V2-1 §4.7: an AI tab shows its state on line 2.
                    if (widget.agentStatus case final a? when !tab.isAi) ...[
                      const SizedBox(width: ShellxSpace.s4),
                      AgentBadge(
```

In `apps/desktop/lib/src/ui/terminal/session_tab_row.dart`, replace:

```dart
                            child: _ContextLine(
                              tab: tab,
                              home: widget.home,
                              onOpenPort: widget.onOpenPort,
                              portTooltip: widget.portTooltip,
                              pr: widget.pr,
                              onOpenPr: widget.onOpenPr,
                            ),
```

with:

```dart
                            child: tab.isAi
                                ? _AiStatusLine(
                                    tab: tab,
                                    status: widget.agentStatus,
                                  )
                                : _ContextLine(
                                    tab: tab,
                                    home: widget.home,
                                    onOpenPort: widget.onOpenPort,
                                    portTooltip: widget.portTooltip,
                                    pr: widget.pr,
                                    onOpenPr: widget.onOpenPr,
                                  ),
```

In `apps/desktop/lib/src/ui/terminal/session_tab_row.dart`, replace:

```dart
/// UI-A2 §2: branch · ~/path · :ports, laid out by [layoutContextLine].
```

with:

```dart
/// V2-1 §4.7: an AI tab's mark in the status-dot slot.
class _AiTabIcon extends StatelessWidget {
  const _AiTabIcon();

  @override
  Widget build(BuildContext context) => const Icon(
    Icons.auto_awesome,
    key: Key('dot.ai'),
    size: ShellxSizes.dotSlot - 4,
    color: ShellxDesktopColors.accent,
  );
}

/// V2-1 §4.7: an AI tab's second line — A12's "{state} · {agent}" in the
/// badge's colour, or the agent alone before it reports anything. The
/// row's label says it to screen readers.
class _AiStatusLine extends StatelessWidget {
  const _AiStatusLine({required this.tab, required this.status});
  final TerminalTab tab;
  final AgentBadgeInfo? status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = tab.ai?.agentName ?? '';
    final s = status;
    final look = s == null ? null : agentBadgeLook(s.state);
    final color = look?.color ?? ShellxDesktopColors.textSecondary;
    return ExcludeSemantics(
      child: Row(
        children: [
          if (look != null) ...[
            Icon(look.icon, size: ShellxSizes.agentBadgeRowIcon, color: color),
            const SizedBox(width: ShellxSpace.s4),
          ],
          Flexible(
            child: Text(
              s == null ? name : '${agentStateWord(l10n, s.state)} · $name',
              key: Key('row.ai.${tab.id}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ShellxText.caption.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// UI-A2 §2: branch · ~/path · :ports, laid out by [layoutContextLine].
```

In `apps/desktop/lib/src/ui/config/search_all_overlay.dart`, replace:

```dart
      for (final id in tab.paneOrder)
        PaneSource(
          tabId: tab.id,
          paneId: id,
          tabLabel: tab.label,
          paneNumber: tab.paneNumber(id),
          terminal: tab.panes[id]!.terminal,
        ),
```

with:

```dart
      for (final id in tab.paneOrder)
        // V2-1 §4.7: an AI pane has no terminal to search.
        if (tab.panes[id] case final pane?)
          PaneSource(
            tabId: tab.id,
            paneId: id,
            tabLabel: tab.label,
            paneNumber: tab.paneNumber(id),
            terminal: pane.terminal,
          ),
```

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

```dart
          ..ensureVisualUpdate();
      }, enabled: (_) => ref.read(terminalTabsProvider).selected != null),
      NavigateSearchIntent: run<NavigateSearchIntent>((intent) {
```

with:

```dart
          ..ensureVisualUpdate();
        // V2-1 D2: only a focused terminal pane has something to find.
      }, enabled: (_) => _terminalFocused()),
      NavigateSearchIntent: run<NavigateSearchIntent>((intent) {
```

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

```dart
        ref.read(copyModeProvider.notifier).toggle(tab.focusedPaneId);
        focusTerminal();
      }, enabled: (_) => ref.read(terminalTabsProvider).selected != null),
```

with:

```dart
        ref.read(copyModeProvider.notifier).toggle(tab.focusedPaneId);
        focusTerminal();
        // V2-1 D2: copy mode is a terminal pane's.
      }, enabled: (_) => _terminalFocused()),
```

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

```dart
        // Outside the terminal (sidebar, a toast…) the key does nothing.
        enabled: (intent) =>
            ref.read(terminalTabsProvider).selected != null &&
            (intent.fromMenu || terminalFocus.hasFocus),
```

with:

```dart
        // Outside the terminal (sidebar, a toast…) the key does nothing;
        // V2-1 D2: so does it in the AI pane (its fields take ⌘A).
        enabled: (intent) =>
            _terminalFocused() && (intent.fromMenu || terminalFocus.hasFocus),
```

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

```dart
  /// A10 D4: the find bar of the selected tab's focused pane, if open.
```

with:

```dart
  /// V2-1 D2: the selected tab's focused pane is a terminal pane (not the
  /// AI pane): find, copy mode and select-all apply.
  bool _terminalFocused() =>
      ref.read(terminalTabsProvider).selected?.focused != null;

  /// A10 D4: the find bar of the selected tab's focused pane, if open.
```

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_notices.dart`, replace:

```dart
      for (final id
          in side.orderedTabIds
              .where((id) => id != selected.id)
              .where((id) => tabs.tabs.any((t) => t.id == id))
              .take(20))
        entry(
          'join-pane:$id',
          l10n.movePaneToTab(tabs.tabs.firstWhere((t) => t.id == id).label),
          JoinPaneIntent(tabId: id),
        ),
```

with:

```dart
      // V2-1 B10: no pane moves into or out of an AI tab.
      if (!selected.isAi)
        for (final id
            in side.orderedTabIds
                .where((id) => id != selected.id)
                .where((id) => tabs.tabs.any((t) => t.id == id && !t.isAi))
                .take(20))
          entry(
            'join-pane:$id',
            l10n.movePaneToTab(tabs.tabs.firstWhere((t) => t.id == id).label),
            JoinPaneIntent(tabId: id),
          ),
```

In `apps/desktop/lib/src/ui/terminal/close_tab.dart`, replace:

```dart
  final running = tabs.runningPaneCount(tab.id);
  // A11 D18: a pinned tab asks too, unless the user turned the question
  // off (confirm-close-surface = false).
  final pinned = tab.meta.pinned && confirm != ConfirmClose.never;
  // A9 D20: Ghostty's confirm-close-surface; `true` = A1 D15 / A3 D28.
  final ask =
      pinned ||
      switch (confirm) {
        ConfirmClose.never => false,
        ConfirmClose.always => true,
        ConfirmClose.whenRunning => running > 0,
      };
  if (ask) {
    final ok = await router.confirm(
      ConfirmRequest(
        title: pinned
```

with:

```dart
  final running = tabs.runningPaneCount(tab.id);
  // V2-1 D3: an AI tab whose agent is working counts as running.
  final aiBusy = tab.isAi && (tabs.aiBusy?.call(tab.id) ?? false);
  // A11 D18: a pinned tab asks too, unless the user turned the question
  // off (confirm-close-surface = false).
  final pinned = tab.meta.pinned && confirm != ConfirmClose.never;
  // A9 D20: Ghostty's confirm-close-surface; `true` = A1 D15 / A3 D28.
  final ask =
      pinned ||
      switch (confirm) {
        ConfirmClose.never => false,
        ConfirmClose.always => true,
        ConfirmClose.whenRunning => running > 0 || aiBusy,
      };
  if (ask && aiBusy && !pinned) {
    // V2-1 D3: "Stop the turn and close?"
    final ok = await router.confirm(
      ConfirmRequest(
        title: l10n.aiCloseRunningTitle,
        body: l10n.aiCloseRunningBody(tab.ai?.agentName ?? ''),
        confirmLabel: l10n.aiCloseRunningAction,
      ),
    );
    if (!ok) return;
  } else if (ask) {
    final ok = await router.confirm(
      ConfirmRequest(
        title: pinned
```

In `apps/desktop/lib/src/ui/terminal/close_tab.dart`, replace:

```dart
  ConfirmClose confirm = ConfirmClose.whenRunning,
}) async {
  final pane = tab.panes[paneId];
  if (pane == null) return;
```

with:

```dart
  ConfirmClose confirm = ConfirmClose.whenRunning,
}) async {
  // V2-1 D3: closing the AI pane closes its tab.
  if (isAiPaneId(paneId)) {
    return closeTabWithConfirm(
      tabs: tabs,
      router: router,
      l10n: l10n,
      tab: tab,
      confirm: confirm,
    );
  }
  final pane = tab.panes[paneId];
  if (pane == null) return;
```

In `apps/desktop/lib/src/ui/terminal/pane_tree_view.dart`, replace:

```dart
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
```

with:

```dart
import '../../terminal/terminal_tabs.dart';
import '../ai/ai_pane_view.dart';
import '../theme/shellx_desktop_theme.dart';
```

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

```dart
  Future<void> _splitPane(SplitAxis axis) async {
    final origin = ref.read(terminalTabsProvider).selected;
    if (origin == null) return;
```

with:

```dart
  Future<void> _splitPane(SplitAxis axis) async {
    final origin = ref.read(terminalTabsProvider).selected;
    if (origin == null) return;
    // V2-1 D3: in the AI pane, ⌘D / ⌘⇧D open the tab's terminal under it.
    if (origin.isAi && origin.focused == null) {
      await ref.read(terminalTabsProvider.notifier).openAiTerminal(origin.id);
      if (mounted) focusTerminal();
      return;
    }
```

- [ ] **Step 6: Run the tests and the suites around them**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/ui/ai lib/src/terminal/agent_names.dart lib/src/terminal/terminal_tabs_ai.dart test/ui/ai_tab_screens_test.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai_tab_screens_test.dart test/ui 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `All tests passed!`; `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add apps/desktop/lib/src/ui/ai/ai_pane_view.dart apps/desktop/lib/src/terminal/agent_names.dart apps/desktop/lib/src/terminal/terminal_tabs_ai.dart apps/desktop/lib/src/ui/terminal/pane_tree_view.dart apps/desktop/lib/src/ui/terminal/session_tab_row.dart apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart apps/desktop/lib/src/ui/terminal/terminal_workspace_notices.dart apps/desktop/lib/src/ui/terminal/close_tab.dart apps/desktop/lib/src/ui/config/search_all_overlay.dart apps/desktop/test/ui/ai_tab_screens_test.dart
git commit -m "feat(v2-ai): sidebar, pane tree, shortcuts, palette and close handle AI tabs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 6: Restore — `aiTabs` in `layout.json`, V1-compatible (D14) [independent of V2-1a]

`layout.json` stays `v: 1` and gains a top-level `aiTabs` array:
- each entry is `{key, title, name?, focused, zoomed, agent, agentName, session, cwd, layout: {"ai": key}, pinned?, desc?, status?}` (B3, B4);
- AI keys sit in `workspaces[].tabs` in sidebar order;
- no conversation content, ever.

How the pieces behave:
- **AI keys:** `aiKeyOf` keeps them apart from `keyOf`. `keyOf` already uses negative ids for displaced tabs, and AI pane ids are negative.
- **Capture:** AI tabs are never captured into `tabs`.
- **Reopen:** AI tabs come back at once, inside the restore, before any activation can open a blank tab. They come back with their title, folder and session. No agent starts (B11).
- **`hasTabs`:** `pickSnapshot`, the generation rotation and the "last tab closed" rule use it, so a layout with only AI tabs is never treated as empty (Review Focus 2).
- **V1 compatibility:** pinned with a frozen copy of the V1 parser (`restore_snapshot.dart` at `164bba6`, identical to HEAD before this task). V1's `loadLayout` renames to `.bak` exactly when its `tryParse` returns null, so a non-null V1 parse is the spec's "no `.bak`" criterion.

**Files:**
- Create: `apps/desktop/test/restore/v1/restore_snapshot_v1.dart` (frozen V1 parser; Step 1)
- Modify: `apps/desktop/lib/src/restore/restore_snapshot.dart`, `restore_capture.dart`, `restore_persistence.dart`, `restore_store.dart`
- Modify: `apps/desktop/lib/src/terminal/terminal_tabs_restore.dart`
- Test: `apps/desktop/test/restore/ai_tabs_restore_test.dart`

**Interfaces:**
- Consumes: Task 3 (`TerminalTab.ai`, `AiPaneState`, `_nextAiPaneId`, `_syntheticTabIds`, `tabOfPane`), Task 2 (`aiNewSession`).
- Produces:
  - `final class SavedAiTab({required String key, required String title, required String agent, required String agentName, String? name, String? session, String? cwd, bool pinned, String description, TabStatus status})` with `toJson()`, `static SavedAiTab? tryParse(Object?)`, `meta`.
  - `RestoreSnapshot.aiTabs` (default `const []`), `bool get hasTabs`.
  - `captureSnapshot(..., String Function(int aiPaneId)? aiKeyOf)`.
  - `RestorePersistence.aiKeyOf(int aiPaneId)`; `RestoreOutcome.aiKeyByPane`.

- [ ] **Step 1: Freeze the V1 parser (before touching `restore_snapshot.dart`)**

```bash
mkdir -p apps/desktop/test/restore/v1
{ printf '%s\n' '// Frozen copy of lib/src/restore/restore_snapshot.dart at 164bba6 (the V1' '// parser), for V2-1 D14'"'"'s compatibility test. Never edit it.'
  git show 164bba6:apps/desktop/lib/src/restore/restore_snapshot.dart \
    | sed "s#import '../terminal/#import 'package:shellx_desktop/src/terminal/#"
} > apps/desktop/test/restore/v1/restore_snapshot_v1.dart
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH dart format test/restore/v1 && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze test/restore/v1
```

Expected: `No issues found!` (it is HEAD's file with package imports).

- [ ] **Step 2: Write the failing tests**

`apps/desktop/test/restore/ai_tabs_restore_test.dart`:

```dart
import 'dart:convert';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart'
    show clockProvider;
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/restore/restore_capture.dart';
import 'package:shellx_desktop/src/restore/restore_persistence.dart';
import 'package:shellx_desktop/src/restore/restore_snapshot.dart';
import 'package:shellx_desktop/src/restore/restore_store.dart';
import 'package:shellx_desktop/src/terminal/local_sessions_provider.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/tab_meta.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/ai_tabs.dart';
import '../support/fake_local_sessions.dart';
import '../support/restore_fakes.dart';
import 'v1/restore_snapshot_v1.dart' as v1;

void main() {
  late FakeLocalSessions local;
  late RecordingFiles files;
  late ProviderContainer c;

  void boot() {
    c = ProviderContainer.test(
      overrides: [
        localSessionsProvider.overrideWithValue(local),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        restoreStoreProvider.overrideWithValue(files),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 14, 9)),
        appL10nProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
      ],
    );
    c.read(sidebarWorkspacesProvider);
  }

  setUp(() {
    local = FakeLocalSessions();
    files = RecordingFiles();
    boot();
  });

  final aiKey = 'a' * 32;
  final termKey = 'b' * 32;

  RestoreSnapshot capture({bool withAi = true}) {
    final keys = <int, String>{};
    return captureSnapshot(
      tabs: c.read(terminalTabsProvider),
      sidebar: c.read(sidebarWorkspacesProvider),
      keyOf: (id) => keys.putIfAbsent(id, () => termKey),
      now: DateTime(2026, 10, 14, 9),
      cleanExit: true,
      aiKeyOf: withAi ? (_) => aiKey : null,
    );
  }

  Future<TerminalTab> twoTabs() async {
    await c.read(terminalTabsProvider.notifier).openTab(); // 100
    final ai = openTestAiTab(
      c,
      title: 'Fix login',
      cwd: '/w/shop',
      sessionId: 'sess-1',
    );
    c.read(terminalTabsProvider.notifier).rename(ai.id, 'Mine');
    return ai;
  }

  test(
    'an AI tab is saved in aiTabs; its key sits in its workspace (D14)',
    () async {
      await twoTabs();
      final s = capture();
      expect(s.tabs.map((t) => t.key), [termKey]);
      final ai = s.aiTabs.single;
      expect(
        [ai.key, ai.title, ai.name, ai.agent, ai.agentName, ai.session, ai.cwd],
        [aiKey, 'Fix login', 'Mine', 'claude', 'Claude', 'sess-1', '/w/shop'],
      );
      expect(s.workspaces.single.tabs, [termKey, aiKey]);
      expect(s.selectedTab, aiKey);
      final json = jsonDecode(s.encode()) as Map<String, Object?>;
      expect(json['v'], 1);
      final entry = (json['aiTabs']! as List).single as Map<String, Object?>;
      expect(entry['layout'], {'ai': aiKey});
      expect(entry['focused'], aiKey);
      expect(entry.containsKey('zoomed'), isTrue);
      expect(s.encode(), isNot(contains('Claude Code')));
    },
  );

  test('without AI tabs the layout has no aiTabs key at all', () async {
    await c.read(terminalTabsProvider.notifier).openTab();
    final json = jsonDecode(capture().encode()) as Map<String, Object?>;
    expect(json.containsKey('aiTabs'), isFalse);
  });

  test('round trip: what was written reads back', () async {
    await twoTabs();
    final back = RestoreSnapshot.tryParse(capture().encode())!;
    final ai = back.aiTabs.single;
    expect([ai.title, ai.session, ai.cwd], ['Fix login', 'sess-1', '/w/shop']);
    expect(back.selectedTab, aiKey);
    expect(back.workspaces.single.tabs, [termKey, aiKey]);
    expect(back.hasTabs, isTrue);
  });

  test('V1 compatibility: the V1 parser keeps the terminal tabs, ignores '
      'aiTabs and the AI keys, and never fails (no .bak)', () async {
    await twoTabs();
    final old = v1.RestoreSnapshot.tryParse(capture().encode());
    expect(old, isNotNull);
    expect(old!.tabs.map((t) => t.key), [termKey]);
    expect(old.workspaces.single.tabs, [termKey]);
    expect(old.selectedTab, isNull, reason: 'it was the AI tab');
  });

  test('a damaged AI tab is dropped, the file still loads', () async {
    await c.read(terminalTabsProvider.notifier).openTab();
    final json = jsonDecode(capture().encode()) as Map<String, Object?>;
    json['aiTabs'] = [
      {'key': 'nope'},
      {'key': aiKey, 'agent': 'claude', 'layout': <String, Object?>{}},
      42,
    ];
    final back = RestoreSnapshot.tryParse(jsonEncode(json))!;
    expect(back.aiTabs, isEmpty);
    expect(back.tabs, hasLength(1));
  });

  test('a layout with only AI tabs is the one restored (Review Focus 2)', () {
    final aiOnly = RestoreSnapshot(
      savedAt: DateTime(2026, 10, 14),
      cleanExit: false,
      workspaces: const [],
      tabs: const [],
      aiTabs: [
        SavedAiTab(
          key: aiKey,
          title: 'Fix login',
          agent: 'claude',
          agentName: 'Claude',
        ),
      ],
    );
    final older = RestoreSnapshot(
      savedAt: DateTime(2026, 10, 13),
      cleanExit: true,
      workspaces: const [],
      tabs: [
        SavedTab(
          key: termKey,
          focused: termKey,
          layout: SavedPane(key: termKey, cwd: '/w'),
        ),
      ],
    );
    final pick = pickSnapshot(current: aiOnly, generations: [older]);
    expect(pick.snapshot, same(aiOnly));
    expect(pick.recovered, isFalse);
  });

  test(
    'restore reopens AI tabs as saved, selected, and starts nothing',
    () async {
      final snapshot = RestoreSnapshot(
        savedAt: DateTime(2026, 10, 14),
        cleanExit: true,
        selectedTab: aiKey,
        workspaces: [
          SavedWorkspace(id: 'default', tabs: [aiKey]),
        ],
        tabs: const [],
        aiTabs: [
          SavedAiTab(
            key: aiKey,
            title: 'Fix login',
            name: 'Mine',
            agent: 'claude',
            agentName: 'Claude',
            session: 'sess-1',
            cwd: '/w/shop',
            pinned: true,
            status: TabStatus.inProgress,
          ),
        ],
      );
      final outcome = await c
          .read(terminalTabsProvider.notifier)
          .restore(RestorePlan(snapshot: snapshot, textByKey: const {}));
      final tabs = c.read(terminalTabsProvider);
      final tab = tabs.tabs.single;
      expect(tab.isAi, isTrue);
      expect(tab.label, 'Mine');
      expect(tab.meta.pinned, isTrue);
      expect(tab.meta.status, TabStatus.inProgress);
      expect(
        [tab.ai!.title, tab.ai!.sessionId, tab.ai!.cwd],
        ['Fix login', 'sess-1', '/w/shop'],
      );
      expect(tabs.selectedId, tab.id);
      expect(outcome.tabIdByKey[aiKey], tab.id);
      expect(outcome.aiKeyByPane[tab.ai!.id], aiKey);
      expect(local.opens, isEmpty, reason: 'no shell, no agent');
    },
  );

  test('persistence writes AI tabs with keys stable across writes', () async {
    c.read(restorePersistenceProvider.notifier).start();
    await twoTabs();
    await c.read(restorePersistenceProvider.notifier).flushAll(clean: false);
    final first = files.layouts.last.aiTabs.single.key;
    c
        .read(terminalTabsProvider.notifier)
        .rename(c.read(terminalTabsProvider).selectedId!, 'Other');
    await c.read(restorePersistenceProvider.notifier).flushAll(clean: false);
    expect(files.layouts.last.aiTabs.single.key, first);
    expect(files.layouts.last.aiTabs.single.name, 'Other');
  });
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/restore/ai_tabs_restore_test.dart`
Expected: compilation fails, `The named parameter 'aiKeyOf' isn't defined` / `Undefined name 'SavedAiTab'`.

- [ ] **Step 4: Implement**

In `apps/desktop/lib/src/restore/restore_snapshot.dart`, replace:

```dart
/// Same bound as A2's stored workspace ids (`Workspace.decode`).
const int _maxWorkspaceId = 64;
```

with:

```dart
/// Same bound as A2's stored workspace ids (`Workspace.decode`).
const int _maxWorkspaceId = 64;

/// V2-1 D14: an AI tab's agent id (`claude`, a custom agent's id).
final RegExp _agentId = RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$');

/// V2-1 D14: an AI tab's saved title, at most this many characters.
const int _maxAiTitle = 200;
```

In `apps/desktop/lib/src/restore/restore_snapshot.dart`, replace:

```dart
final class SavedWorkspace {
```

with:

```dart
/// V2-1 D14: one AI tab of `layout.json` (`aiTabs`). Its key is the key
/// of its AI leaf (`{"ai": key}`); ruling B3: that leaf is all the layout
/// holds. Never any conversation: the agent keeps it, under [session].
final class SavedAiTab {
  const SavedAiTab({
    required this.key,
    required this.title,
    required this.agent,
    required this.agentName,
    this.name,
    this.session,
    this.cwd,
    this.pinned = false,
    this.description = '',
    this.status = TabStatus.none,
  });

  final String key;

  /// The automatic title (the session's, or the first prompt).
  final String title;

  /// The user's name for the tab (B4); null: automatic.
  final String? name;
  final String agent;
  final String agentName;

  /// The agent's session id, already a valid A12 session id.
  final String? session;
  final String? cwd;
  final bool pinned;
  final String description;
  final TabStatus status;

  TabMeta get meta =>
      TabMeta(pinned: pinned, description: description, status: status);

  Map<String, Object?> toJson() => {
    'key': key,
    'title': title,
    'name': ?name,
    'focused': key,
    'zoomed': null,
    'agent': agent,
    'agentName': agentName,
    'session': session,
    'cwd': cwd,
    'layout': {'ai': key},
    if (pinned) 'pinned': true,
    if (description.isNotEmpty) 'desc': description,
    if (status != TabStatus.none) 'status': status.wire,
  };

  /// Null for anything that is not a well-formed AI tab: the entry is then
  /// dropped, never the file. Damaged optional fields are repaired.
  static SavedAiTab? tryParse(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final key = raw['key'];
    final agent = raw['agent'];
    if (key is! String || !isPaneKey(key)) return null;
    if (agent is! String || !_agentId.hasMatch(agent)) return null;
    if (!_hasAiLeaf(raw['layout'], key, 0)) return null;
    final title = raw['title'];
    final name = raw['name'];
    final agentName = raw['agentName'];
    final session = raw['session'];
    final cwd = raw['cwd'];
    return SavedAiTab(
      key: key,
      title: title is String ? _cleanTitle(title) : '',
      name: name is String && name.isNotEmpty && name.length <= _maxName
          ? name
          : null,
      agent: agent,
      agentName:
          agentName is String &&
              agentName.trim().isNotEmpty &&
              agentName.length <= _maxName
          ? agentName
          : agent,
      session: session is String && isValidSessionId(session) ? session : null,
      cwd: cwd is String && isRestorableCwd(cwd) ? cwd : null,
      pinned: raw['pinned'] == true,
      description: switch (raw['desc']) {
        final String d => TabMeta.cleanDescription(d),
        _ => '',
      },
      status: TabStatus.fromWire(raw['status']),
    );
  }

  static bool _hasAiLeaf(Object? node, String key, int depth) {
    if (depth > _maxDepth || node is! Map<String, Object?>) return false;
    if (node['ai'] == key) return true;
    return _hasAiLeaf(node['first'], key, depth + 1) ||
        _hasAiLeaf(node['second'], key, depth + 1);
  }

  static String _cleanTitle(String text) {
    final clean = text.replaceAll(_control, ' ').trim();
    final runes = clean.runes;
    return runes.length <= _maxAiTitle
        ? clean
        : String.fromCharCodes(runes.take(_maxAiTitle));
  }
}

final class SavedWorkspace {
```

In `apps/desktop/lib/src/restore/restore_snapshot.dart`, replace:

```dart
    required this.workspaces,
    required this.tabs,
  });

  final DateTime savedAt;
```

with:

```dart
    required this.workspaces,
    required this.tabs,
    this.aiTabs = const [],
  });

  final DateTime savedAt;
```

In `apps/desktop/lib/src/restore/restore_snapshot.dart`, replace:

```dart
  final List<SavedTab> tabs;

  Set<String> get paneKeys => {
```

with:

```dart
  final List<SavedTab> tabs;

  /// V2-1 D14: the AI tabs (top-level `aiTabs`, which V1 ignores).
  final List<SavedAiTab> aiTabs;

  /// Something to restore: a terminal tab or an AI tab (Review Focus 2).
  bool get hasTabs => tabs.isNotEmpty || aiTabs.isNotEmpty;

  Set<String> get paneKeys => {
```

In `apps/desktop/lib/src/restore/restore_snapshot.dart`, replace:

```dart
        workspaces: workspaces,
        tabs: tabs,
      );

  /// Equal apart from [savedAt] and [cleanExit]: no write needed.
```

with:

```dart
        workspaces: workspaces,
        tabs: tabs,
        aiTabs: aiTabs,
      );

  /// Equal apart from [savedAt] and [cleanExit]: no write needed.
```

In `apps/desktop/lib/src/restore/restore_snapshot.dart`, replace:

```dart
          if (t.status != TabStatus.none) 'status': t.status.wire,
        },
    ],
  };
```

with:

```dart
          if (t.status != TabStatus.none) 'status': t.status.wire,
        },
    ],
    // V2-1 D14: only when there is one, so a terminal-only layout is
    // byte-identical to before.
    if (aiTabs.isNotEmpty) 'aiTabs': [for (final t in aiTabs) t.toJson()],
  };
```

In `apps/desktop/lib/src/restore/restore_snapshot.dart`, replace:

```dart
      if (seen.length > _maxPanes) return null;
```

with:

```dart
      if (seen.length > _maxPanes) return null;
      // V2-1 D14: the AI tabs; a damaged one is dropped, never the file.
      final aiTabs = <SavedAiTab>[];
      final aiKeys = <String>{};
      if (root['aiTabs'] case final List<Object?> list) {
        for (final raw in list) {
          final t = SavedAiTab.tryParse(raw);
          if (t == null || tabKeys.contains(t.key) || seen.contains(t.key)) {
            continue;
          }
          if (aiKeys.add(t.key)) aiTabs.add(t);
        }
      }
```

In `apps/desktop/lib/src/restore/restore_snapshot.dart`, replace:

```dart
          if (tabKeys.contains(key)) members.add(key);
```

with:

```dart
          if (tabKeys.contains(key) || aiKeys.contains(key)) {
            members.add(key);
          }
```

In `apps/desktop/lib/src/restore/restore_snapshot.dart`, replace:

```dart
        selectedTab: tabKeys.contains(selected) ? selected : null,
        workspaces: workspaces,
        tabs: tabs,
      );
```

with:

```dart
        selectedTab: tabKeys.contains(selected) || aiKeys.contains(selected)
            ? selected
            : null,
        workspaces: workspaces,
        tabs: tabs,
        aiTabs: aiTabs,
      );
```

In `apps/desktop/lib/src/restore/restore_capture.dart`, replace:

```dart
import '../terminal/pane_layout.dart';
```

with:

```dart
import '../terminal/agent_status.dart' show isValidSessionId;
import '../terminal/pane_layout.dart';
```

In `apps/desktop/lib/src/restore/restore_capture.dart`, replace:

```dart
/// D20), the tab's key is [keyOf] of the negated tab id instead: a pane key
/// of its own that no leaf of any tab carries, so the file still loads.
RestoreSnapshot captureSnapshot({
  required TerminalTabsState tabs,
  required SidebarState sidebar,
  required String Function(int sessionId) keyOf,
  required DateTime now,
  required bool cleanExit,
  String? daemon,
  SavedAgent? Function(int sessionId)? agentOf,
}) {
  final saved = <int, SavedTab>{};
  for (final tab in tabs.tabs) {
    final layout = savePaneTree(tab.layout, tab, keyOf, agentOf: agentOf);
```

with:

```dart
/// D20), the tab's key is [keyOf] of the negated tab id instead: a pane key
/// of its own that no leaf of any tab carries, so the file still loads.
///
/// V2-1 D14: AI tabs go to `aiTabs`, keyed by [aiKeyOf] of their AI pane
/// (never [keyOf]: AI pane ids are negative, as displaced tabs' are); none
/// without [aiKeyOf].
RestoreSnapshot captureSnapshot({
  required TerminalTabsState tabs,
  required SidebarState sidebar,
  required String Function(int sessionId) keyOf,
  required DateTime now,
  required bool cleanExit,
  String? daemon,
  SavedAgent? Function(int sessionId)? agentOf,
  String Function(int aiPaneId)? aiKeyOf,
}) {
  final saved = <int, SavedTab>{};
  final savedAi = <int, SavedAiTab>{};
  for (final tab in tabs.tabs) {
    if (tab.isAi) {
      final ai = tab.ai;
      if (ai == null || aiKeyOf == null) continue;
      final session = ai.sessionId;
      final cwd = ai.cwd;
      savedAi[tab.id] = SavedAiTab(
        key: aiKeyOf(ai.id),
        title: ai.title,
        name: tab.customTitle,
        agent: ai.agentId,
        agentName: ai.agentName,
        session: session != null && isValidSessionId(session) ? session : null,
        cwd: cwd != null && isRestorableCwd(cwd) ? cwd : null,
        pinned: tab.meta.pinned,
        description: tab.meta.description,
        status: tab.meta.status,
      );
      continue;
    }
    final layout = savePaneTree(tab.layout, tab, keyOf, agentOf: agentOf);
```

In `apps/desktop/lib/src/restore/restore_capture.dart`, replace:

```dart
    selectedTab: saved[tabs.selectedId]?.key,
    workspaces: [
      for (final w in sidebar.workspaces)
        SavedWorkspace(
          id: w.id,
          tabs: [for (final id in sidebar.tabsOf(w.id)) ?saved[id]?.key],
        ),
    ],
    tabs: [
      for (final id in ordered) ?saved[id],
      // Tabs the sidebar has not placed yet keep creation order.
      for (final t in tabs.tabs)
        if (!placed.contains(t.id)) ?saved[t.id],
    ],
  );
```

with:

```dart
    selectedTab: saved[tabs.selectedId]?.key ?? savedAi[tabs.selectedId]?.key,
    workspaces: [
      for (final w in sidebar.workspaces)
        SavedWorkspace(
          id: w.id,
          tabs: [
            for (final id in sidebar.tabsOf(w.id))
              ?(saved[id]?.key ?? savedAi[id]?.key),
          ],
        ),
    ],
    tabs: [
      for (final id in ordered) ?saved[id],
      // Tabs the sidebar has not placed yet keep creation order.
      for (final t in tabs.tabs)
        if (!placed.contains(t.id)) ?saved[t.id],
    ],
    aiTabs: [
      for (final id in ordered) ?savedAi[id],
      for (final t in tabs.tabs)
        if (!placed.contains(t.id)) ?savedAi[t.id],
    ],
  );
```

In `apps/desktop/lib/src/restore/restore_persistence.dart`, replace:

```dart
  final _keys = <int, String>{};
```

with:

```dart
  final _keys = <int, String>{};

  /// V2-1 D14: AI pane id → its AI tab's key, apart from [_keys] (AI pane
  /// ids are negative, as [_keys]' displaced-tab entries are).
  final _aiKeys = <int, String>{};
```

In `apps/desktop/lib/src/restore/restore_persistence.dart`, replace:

```dart
  Future<bool> hasSavedScrollback() => _files.hasScrollback();
```

with:

```dart
  /// V2-1 D14: an AI tab's key, made when its pane is first saved.
  String aiKeyOf(int aiPaneId) => _aiKeys.putIfAbsent(aiPaneId, newPaneKey);

  Future<bool> hasSavedScrollback() => _files.hasScrollback();
```

In `apps/desktop/lib/src/restore/restore_persistence.dart`, replace:

```dart
      _keys.addAll(outcome.keyBySession);
      _filed.addAll(outcome.keyBySession.values);
```

with:

```dart
      _keys.addAll(outcome.keyBySession);
      _aiKeys.addAll(outcome.aiKeyByPane);
      _filed.addAll(outcome.keyBySession.values);
```

In `apps/desktop/lib/src/restore/restore_persistence.dart`, replace:

```dart
      daemon: currentDaemon,
      agentOf: _agentOf,
    );
```

with:

```dart
      daemon: currentDaemon,
      agentOf: _agentOf,
      aiKeyOf: aiKeyOf,
    );
```

In `apps/desktop/lib/src/restore/restore_persistence.dart`, replace:

```dart
          : tabs.tabOfSession(id) == null && !tabs.tabs.any((t) => t.id == id),
    );
```

with:

```dart
          : tabs.tabOfSession(id) == null && !tabs.tabs.any((t) => t.id == id),
    );
    _aiKeys.removeWhere((id, _) => tabs.tabOfPane(id) == null);
```

In `apps/desktop/lib/src/restore/restore_persistence.dart`, replace:

```dart
    if (next.tabs.isNotEmpty) {
      _hadTabs = true;
```

with:

```dart
    // V2-1 D14: AI tabs count (Review Focus 2).
    if (next.hasTabs) {
      _hadTabs = true;
```

In `apps/desktop/lib/src/restore/restore_store.dart`, replace:

```dart
  if (current != null && current.tabs.isNotEmpty) {
    return (snapshot: current, recovered: false);
  }
  final fallback = generations.where((g) => g != null && g.tabs.isNotEmpty);
```

with:

```dart
  // V2-1 D14: a layout with only AI tabs is not empty (Review Focus 2).
  if (current != null && current.hasTabs) {
    return (snapshot: current, recovered: false);
  }
  final fallback = generations.where((g) => g != null && g.hasTabs);
```

In `apps/desktop/lib/src/restore/restore_store.dart`, replace:

```dart
    if (newest != null && newest.tabs.isNotEmpty) {
```

with:

```dart
    if (newest != null && newest.hasTabs) {
```

In `apps/desktop/lib/src/restore/restore_store.dart`, replace:

```dart
      if (current != null && current.tabs.isNotEmpty && text != null) {
```

with:

```dart
      if (current != null && current.hasTabs && text != null) {
```

In `apps/desktop/lib/src/terminal/terminal_tabs_restore.dart`, replace:

```dart
final class RestoreOutcome {
  const RestoreOutcome({
    required this.keyBySession,
    required this.tabIdByKey,
    required this.panesFailed,
  });

  /// The saved pane key of every reopened session.
  final Map<int, String> keyBySession;
```

with:

```dart
final class RestoreOutcome {
  const RestoreOutcome({
    required this.keyBySession,
    required this.tabIdByKey,
    required this.panesFailed,
    this.aiKeyByPane = const {},
  });

  /// The saved pane key of every reopened session.
  final Map<int, String> keyBySession;

  /// V2-1 D14: the saved key of every reopened AI tab, by its AI pane.
  final Map<int, String> aiKeyByPane;
```

In `apps/desktop/lib/src/terminal/terminal_tabs_restore.dart`, replace:

```dart
  Future<RestoreOutcome> _runRestore(FutureOr<RestorePlan?> pending) async {
    final keyBySession = <int, String>{};
    final tabIdByKey = <String, int>{};
```

with:

```dart
  Future<RestoreOutcome> _runRestore(FutureOr<RestorePlan?> pending) async {
    final keyBySession = <int, String>{};
    final tabIdByKey = <String, int>{};
    final aiKeyByPane = <int, String>{};
```

In `apps/desktop/lib/src/terminal/terminal_tabs_restore.dart`, replace:

```dart
      if (plan.reattach) return _layOver(plan.snapshot, local);
      final snapshot = plan.snapshot;
      final workspaceOf = {
        for (final w in snapshot.workspaces)
          for (final key in w.tabs) key: w.id,
      };
```

with:

```dart
      if (plan.reattach) return _layOver(plan.snapshot, local);
      final snapshot = plan.snapshot;
      final workspaceOf = {
        for (final w in snapshot.workspaces)
          for (final key in w.tabs) key: w.id,
      };
      // V2-1 D14: AI tabs at once (no process to start, B11).
      _restoreAiTabs(snapshot, workspaceOf, tabIdByKey, aiKeyByPane);
```

In `apps/desktop/lib/src/terminal/terminal_tabs_restore.dart`, replace:

```dart
    return RestoreOutcome(
      keyBySession: keyBySession,
      tabIdByKey: tabIdByKey,
      panesFailed: failed,
    );
  }

  /// A5b D14: the saved tabs over the sessions that are alive (their panes
```

with:

```dart
    return RestoreOutcome(
      keyBySession: keyBySession,
      tabIdByKey: tabIdByKey,
      panesFailed: failed,
      aiKeyByPane: aiKeyByPane,
    );
  }

  /// V2-1 D14: the saved AI tabs, each with its title, agent, folder and
  /// session, placed in its workspace; selected when it was. No agent
  /// starts: a pane starts its agent when it is first shown (B11).
  void _restoreAiTabs(
    RestoreSnapshot snapshot,
    Map<String, String> workspaceOf,
    Map<String, int> tabIdByKey,
    Map<int, String> aiKeyByPane,
  ) {
    final fallback = _ref.read(appL10nProvider).aiNewSession;
    for (final saved in snapshot.aiTabs) {
      final tab = TerminalTab.ai(
        id: kSyntheticTabIdBase + _syntheticTabIds++,
        pane: AiPaneState(
          id: _nextAiPaneId--,
          agentId: saved.agent,
          agentName: saved.agentName,
          title: saved.title.isEmpty ? fallback : saved.title,
          cwd: saved.cwd,
          sessionId: saved.session,
        ),
        customTitle: saved.name,
        meta: saved.meta,
      );
      // Before the tab appears: the sidebar takes it as it places the tab.
      _ref.read(restorePlacementProvider).pending[tab.id] =
          workspaceOf[saved.key];
      final select = _restoreMaySelect && saved.key == snapshot.selectedTab;
      if (select) _restoreMaySelect = false;
      _set(
        tabs: [..._state.tabs, tab],
        selectedId: select ? tab.id : _state.selectedId ?? tab.id,
      );
      tabIdByKey[saved.key] = tab.id;
      aiKeyByPane[tab.ai!.id] = saved.key;
    }
  }

  /// A5b D14: the saved tabs over the sessions that are alive (their panes
```

In `apps/desktop/lib/src/terminal/terminal_tabs_restore.dart`, replace:

```dart
    final selected = snapshot.selectedTab == null
        ? null
        : tabIdByKey[snapshot.selectedTab];
    _set(
      tabs: [...tabs, ...rest],
      selectedId: selected ?? tabs.firstOrNull?.id ?? _state.selectedId,
    );
    return RestoreOutcome(
      keyBySession: keyBySession,
      tabIdByKey: tabIdByKey,
      panesFailed: failed,
    );
```

with:

```dart
    final selected = snapshot.selectedTab == null
        ? null
        : tabIdByKey[snapshot.selectedTab];
    _set(
      tabs: [...tabs, ...rest],
      selectedId: selected ?? tabs.firstOrNull?.id ?? _state.selectedId,
    );
    // V2-1 D14: the AI tabs too (the service never held them).
    final workspaceOf = {
      for (final w in snapshot.workspaces)
        for (final key in w.tabs) key: w.id,
    };
    final aiKeyByPane = <int, String>{};
    _restoreMaySelect = selected == null;
    _restoreAiTabs(snapshot, workspaceOf, tabIdByKey, aiKeyByPane);
    _restoreMaySelect = false;
    return RestoreOutcome(
      keyBySession: keyBySession,
      tabIdByKey: tabIdByKey,
      panesFailed: failed,
      aiKeyByPane: aiKeyByPane,
    );
```

- [ ] **Step 5: Run the restore suites and analyze**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/restore lib/src/terminal/terminal_tabs_restore.dart test/restore/ai_tabs_restore_test.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/restore test/terminal/terminal_tabs_restore_test.dart 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `All tests passed!` (on the scratch copy: 236 passing, 2 skipped); `No issues found!`.

- [ ] **Step 6: Commit**

```bash
git add apps/desktop/lib/src/restore apps/desktop/lib/src/terminal/terminal_tabs_restore.dart apps/desktop/test/restore/v1/restore_snapshot_v1.dart apps/desktop/test/restore/ai_tabs_restore_test.dart
git commit -m "feat(v2-ai): save and reopen AI tabs in layout.json (aiTabs, V1-compatible)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 7: Command line — `ui.ls` lists AI tabs (D19) [independent of V2-1a]

- **`ui.ls`:** every tab gets `kind` (`"terminal"` or `"ai"`); an AI tab also gets its `cwd`, and its `panes` lists only its terminal panes. `focusedPane` is a terminal pane, or null while an AI pane has the focus. Older CLIs ignore the new keys.
- **Pane commands:** on an AI tab they target its terminal pane — the focused one, else the first. With none, they answer `not_found`, as for any missing pane.
- **Events:** no `pane.focused` for an AI pane.

**Files:**
- Modify: `apps/desktop/lib/src/cli/ui_command_handler.dart`, `cli_targets.dart`, `cli_event_bus.dart`
- Test: `apps/desktop/test/cli/ui_ai_tabs_test.dart`

**Interfaces:**
- Consumes: Task 3 (`isAi`, `focused`, `isAiPaneId`, `openTestAiTab`, `addAiTerminal`).
- Produces: the `ui.ls` fields above; `resolvePane` semantics for AI tabs.

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/cli/ui_ai_tabs_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/cli/cli_event_bus.dart';
import 'package:shellx_desktop/src/cli/cli_targets.dart';
import 'package:shellx_desktop/src/cli/ui_command_handler.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../support/ai_tabs.dart';
import '../support/fake_local_sessions.dart';
import 'support/cli_container.dart';

void main() {
  late FakeLocalSessions local;
  late ProviderContainer c;

  Future<Map<String, Object?>> ls() => c
      .read(uiCommandHandlerProvider)
      .handle(const MuxMessage('ui.ls', q: 1, fields: {}));

  List<Map<String, Object?>> tabsOf(Map<String, Object?> ls) => [
    for (final t
        in ((ls['workspaces']! as List).single as Map)['tabs']! as List)
      t as Map<String, Object?>,
  ];

  Matcher notFound() => throwsA(
    isA<CliFailure>().having((e) => e.code, 'code', MuxError.notFound),
  );

  setUp(() async {
    local = FakeLocalSessions();
    c = cliContainer(local);
    await c.read(terminalTabsProvider.notifier).openTab(); // 100
  });

  test('ui.ls lists an AI tab: kind ai, title, cwd, no pane (D19)', () async {
    final ai = openTestAiTab(c, title: 'Fix login', cwd: '/w/shop');
    final got = await ls();
    final tabs = tabsOf(got);
    expect(tabs.first['kind'], 'terminal');
    final row = tabs.last;
    expect(row['id'], ai.id);
    expect(row['kind'], 'ai');
    expect(row['title'], 'Fix login');
    expect(row['cwd'], '/w/shop');
    expect(row['panes'], isEmpty);
    expect(got['selectedTab'], ai.id);
    expect(got['focusedPane'], isNull, reason: 'no terminal pane in focus');
  });

  test('an AI tab with a terminal pane lists it; targets reach it', () async {
    final ai = openTestAiTab(c);
    final term = await c
        .read(terminalTabsProvider.notifier)
        .addAiTerminal(ai.id);
    final row = tabsOf(await ls()).last;
    expect([for (final p in row['panes']! as List) (p as Map)['id']], [term]);
    c.read(terminalTabsProvider.notifier).focusPane(ai.ai!.id);
    final s = c.read(terminalTabsProvider);
    expect(resolvePane(s, TabRef(ai.id)), term);
    expect(resolvePane(s, const FocusedRef()), term);
  });

  test('a pane command on an AI tab without terminal is not_found', () {
    final ai = openTestAiTab(c);
    final s = c.read(terminalTabsProvider);
    expect(() => resolvePane(s, TabRef(ai.id)), notFound());
    expect(() => resolvePane(s, const FocusedRef()), notFound());
    expect(() => resolvePane(s, PaneRef(ai.ai!.id)), notFound());
    expect(resolveTab(s, TabRef(ai.id)), ai.id);
  });

  test('focusing the AI pane emits no pane.focused', () async {
    final got = <Map<String, Object?>>[];
    c.read(cliEventBusProvider).events.listen(got.add);
    final ai = openTestAiTab(c);
    final term = await c
        .read(terminalTabsProvider.notifier)
        .addAiTerminal(ai.id);
    await pumpEventQueue();
    got.clear();
    c.read(terminalTabsProvider.notifier).focusPane(ai.ai!.id);
    c.read(terminalTabsProvider.notifier).focusPane(term);
    await pumpEventQueue();
    final focused = [
      for (final e in got)
        if (e['kind'] == 'pane.focused') e['pane'],
    ];
    expect(focused, [term]);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/cli/ui_ai_tabs_test.dart`
Expected: FAIL. `row['kind']` is null; `resolvePane` returns the AI pane's negative id instead of throwing; a `pane.focused` event carries a negative pane.

- [ ] **Step 3: Implement**

In `apps/desktop/lib/src/cli/ui_command_handler.dart`, replace:

```dart
    Map<String, Object?> tab(TerminalTab tab) => {
      'id': tab.id,
      'title': tab.label,
```

with:

```dart
    Map<String, Object?> tab(TerminalTab tab) => {
      'id': tab.id,
      // V2-1 D19: older CLIs ignore the key.
      'kind': tab.isAi ? 'ai' : 'terminal',
      'title': tab.label,
      if (tab.isAi) 'cwd': tab.cwd,
```

In `apps/desktop/lib/src/cli/ui_command_handler.dart`, replace:

```dart
      'selectedTab': tabs.selectedId,
      'focusedPane': tabs.selected?.focusedPaneId,
```

with:

```dart
      'selectedTab': tabs.selectedId,
      // V2-1 D19: a terminal pane only (null while an AI pane has focus).
      'focusedPane': tabs.selected?.focused?.id,
```

In `apps/desktop/lib/src/cli/cli_targets.dart`, replace:

```dart
/// A terminal pane id; a tab gives its focused pane. Throws `not_found`.
int resolvePane(TerminalTabsState s, CliTarget target) => switch (target) {
  FocusedRef() => (s.selected ?? (throw _noSelection)).focusedPaneId,
  PaneRef(:final id) => s.tabOfSession(id) != null ? id : throw _noPane(id),
  TabRef(:final id) => (_tabById(s, id) ?? (throw _noTab(id))).focusedPaneId,
};
```

with:

```dart
/// A terminal pane id; a tab gives its focused pane. Throws `not_found`.
/// V2-1 D19: an AI tab gives its terminal pane — the focused one, else the
/// first — and `not_found` when it has none.
int resolvePane(TerminalTabsState s, CliTarget target) => switch (target) {
  FocusedRef() => _terminalPaneOf(s.selected ?? (throw _noSelection)),
  PaneRef(:final id) => s.tabOfSession(id) != null ? id : throw _noPane(id),
  TabRef(:final id) => _terminalPaneOf(_tabById(s, id) ?? (throw _noTab(id))),
};

int _terminalPaneOf(TerminalTab tab) =>
    tab.focused?.id ??
    tab.paneOrder.where(tab.panes.containsKey).firstOrNull ??
    (throw _noPane(tab.focusedPaneId));
```

In `apps/desktop/lib/src/cli/cli_event_bus.dart`, replace:

```dart
      if (o.focusedPaneId != t.focusedPaneId &&
          _swappedEnd(o.focusedPaneId) != t.focusedPaneId) {
```

with:

```dart
      // V2-1 §4.7: never for an AI pane (negative id).
      if (o.focusedPaneId != t.focusedPaneId &&
          !isAiPaneId(t.focusedPaneId) &&
          _swappedEnd(o.focusedPaneId) != t.focusedPaneId) {
```

- [ ] **Step 4: Run the CLI suite and analyze**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/cli test/cli/ui_ai_tabs_test.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/cli 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `All tests passed!`; `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/cli/ui_command_handler.dart apps/desktop/lib/src/cli/cli_targets.dart apps/desktop/lib/src/cli/cli_event_bus.dart apps/desktop/test/cli/ui_ai_tabs_test.dart
git commit -m "feat(v2-ai): ui.ls lists AI tabs (kind ai); pane commands skip AI panes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 8: Settings keys — `new-tab-kind`, `ai-agent-claude`, `ai-checkpoint-days`, UI keys [independent of V2-1a]

D4, D21, D12. Three file keys follow the `agent-resume` pattern (parser, `config_show`, template, Settings value, schema row):
- **`new-tab-kind`**: `terminal` | `ai`, default `terminal`. Its row is the last one of the General page (B13).
- **`ai-agent-claude`**: `on` | `off`, default `on`; `true`/`false` are accepted too.
- **`ai-checkpoint-days`**: 1–90, default 14.

The last two have rows on the Agents page, rendered by Task 24. The UI-owned store gets `ai_intro_shown`, `ai_default_agent`, `ai_custom_agents` and `ai_agent_config`, recorded in `test/agent/settings_ownership_test.dart` (the spec's ownership test).

**Files:**
- Modify: `apps/desktop/lib/src/config/shellx_config.dart`, `settings_schema.dart`, `config_show.dart`, `config_template.dart`
- Modify: `apps/desktop/lib/src/ui/settings/settings_values.dart`, `apps/desktop/lib/src/ui/settings/pages/general_page.dart`
- Modify: `apps/desktop/lib/src/platform/settings_store.dart`
- Modify: `apps/desktop/test/config/settings_schema_test.dart`, `apps/desktop/test/agent/settings_ownership_test.dart`
- Test: `apps/desktop/test/config/ai_settings_test.dart`

**Interfaces:**
- Consumes: Task 2 strings.
- Produces:
  - `enum NewTabKind { terminal, ai }`;
  - `ShellxConfig.newTabKind`, `.aiAgentClaude`, `.aiCheckpointDays`;
  - `kAiCheckpointDaysDefault = 14`, `kAiCheckpointDaysMin = 1`, `kAiCheckpointDaysMax = 90`;
  - `SettingKeys.aiIntroShown`, `.aiDefaultAgent`, `.aiCustomAgents`, `.aiAgentConfig` (UI-owned);
  - the Settings rows `new-tab-kind`, `ai-agent-claude`, `ai-checkpoint-days`.

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/config/ai_settings_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_problem.dart';
import 'package:shellx_desktop/src/config/config_syntax.dart';
import 'package:shellx_desktop/src/config/settings_schema.dart';
import 'package:shellx_desktop/src/config/shellx_config.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/ui/settings/pages/page_parts.dart'
    show settingById;

({ShellxConfig config, List<ConfigProblem> problems}) build(
  Map<String, String> kv,
) {
  final problems = <ConfigProblem>[];
  var n = 0;
  final config = buildShellxConfig(
    ghostty: const [],
    shellx: [
      for (final e in kv.entries)
        ConfigEntry(file: '/c', line: ++n, key: e.key, value: e.value),
    ],
    problems: problems,
    macos: true,
    home: '/Users/me',
  );
  return (config: config, problems: problems);
}

void main() {
  test('defaults: terminal tabs, Claude on, 14 days (D4, D21, D12)', () {
    final c = build({}).config;
    expect(c.newTabKind, NewTabKind.terminal);
    expect(c.aiAgentClaude, isTrue);
    expect(c.aiCheckpointDays, 14);
  });

  test('values and bad values', () {
    expect(build({'new-tab-kind': 'ai'}).config.newTabKind, NewTabKind.ai);
    expect(build({'ai-agent-claude': 'off'}).config.aiAgentClaude, isFalse);
    expect(build({'ai-agent-claude': 'on'}).config.aiAgentClaude, isTrue);
    expect(build({'ai-checkpoint-days': '30'}).config.aiCheckpointDays, 30);
    for (final (key, value) in [
      ('new-tab-kind', 'browser'),
      ('ai-agent-claude', 'maybe'),
      ('ai-checkpoint-days', 'x'),
    ]) {
      final r = build({key: value});
      expect(r.problems.single.code, ConfigProblemCode.badValue, reason: key);
    }
    final far = build({'ai-checkpoint-days': '400'});
    expect(far.config.aiCheckpointDays, kAiCheckpointDaysMax);
  });

  test('the rows: new-tab-kind on General, the AI keys on Agents', () {
    expect(settingById('new-tab-kind').page, SettingPage.general);
    expect(settingById('ai-agent-claude').page, SettingPage.agents);
    expect(settingById('ai-checkpoint-days').page, SettingPage.agents);
  });

  test('the AI keys of the settings store are the UI\'s (A5b D13)', () {
    for (final key in [
      SettingKeys.aiIntroShown,
      SettingKeys.aiDefaultAgent,
      SettingKeys.aiCustomAgents,
      SettingKeys.aiAgentConfig,
    ]) {
      expect(SettingKeys.all, contains(key));
      expect(UiSettingKeys.all, contains(key));
      expect(DaemonSettingKeys.all, isNot(contains(key)));
    }
  });
}
```

In `apps/desktop/test/config/settings_schema_test.dart`, replace:

```dart
      'agent-resume',
      'pr-status',
      'link-editor',
    };
```

with:

```dart
      'agent-resume',
      'pr-status',
      'link-editor',
      // V2-1.
      'new-tab-kind',
      'ai-agent-claude',
      'ai-checkpoint-days',
    };
```

In `apps/desktop/test/agent/settings_ownership_test.dart`, replace:

```dart
  // A12 D19: the window reads it once at start; the service keeps the
  // system language.
  'app_language',
};
```

with:

```dart
  // A12 D19: the window reads it once at start; the service keeps the
  // system language.
  'app_language',
  // V2-1 D4, D7, D11, D23: the AI interface lives in the window.
  'ai_intro_shown',
  'ai_default_agent',
  'ai_custom_agents',
  'ai_agent_config',
};
```

In `apps/desktop/test/agent/settings_ownership_test.dart`, replace:

```dart
    expect(SettingKeys.all, hasLength(30));
```

with:

```dart
    expect(SettingKeys.all, hasLength(34));
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/config/ai_settings_test.dart test/agent/settings_ownership_test.dart test/config/settings_schema_test.dart`
Expected: compilation fails, `The getter 'newTabKind' isn't defined for the type 'ShellxConfig'`.

- [ ] **Step 3: Implement**

In `apps/desktop/lib/src/config/shellx_config.dart`, replace:

```dart
const int kScrollbackMax = 100000;
```

with:

```dart
const int kScrollbackMax = 100000;

/// V2-1 D12 `ai-checkpoint-days`: how long the AI tab's restore points are
/// kept, in days.
const int kAiCheckpointDaysDefault = 14;
const int kAiCheckpointDaysMin = 1;
const int kAiCheckpointDaysMax = 90;
```

In `apps/desktop/lib/src/config/shellx_config.dart`, replace:

```dart
enum AgentResume { ask, off }
```

with:

```dart
enum AgentResume { ask, off }

/// V2-1 D4 `new-tab-kind`: what ⌘T / Ctrl+Shift+T, `+`, the empty window's
/// button and the startup tab open. The names are the wire values.
enum NewTabKind { terminal, ai }
```

In `apps/desktop/lib/src/config/shellx_config.dart`, replace:

```dart
    this.agentResume = AgentResume.ask,
    this.linkEditor = LinkEditor.auto,
```

with:

```dart
    this.agentResume = AgentResume.ask,
    this.newTabKind = NewTabKind.terminal,
    this.aiAgentClaude = true,
    this.aiCheckpointDays = kAiCheckpointDaysDefault,
    this.linkEditor = LinkEditor.auto,
```

In `apps/desktop/lib/src/config/shellx_config.dart`, replace:

```dart
  /// `agent-resume` (ShellX file only, A12 D13).
  final AgentResume agentResume;
```

with:

```dart
  /// `agent-resume` (ShellX file only, A12 D13).
  final AgentResume agentResume;

  /// `new-tab-kind` (ShellX file only, V2-1 D4): `terminal` by default.
  final NewTabKind newTabKind;

  /// `ai-agent-claude = on | off` (ShellX file only, V2-1 D21): off hides
  /// Claude from the AI interface everywhere.
  final bool aiAgentClaude;

  /// `ai-checkpoint-days` (ShellX file only, V2-1 D12).
  final int aiCheckpointDays;
```

In `apps/desktop/lib/src/config/shellx_config.dart`, replace:

```dart
  var agentResume = AgentResume.ask;
  var linkEditor = LinkEditor.auto;
```

with:

```dart
  var agentResume = AgentResume.ask;
  var newTabKind = NewTabKind.terminal;
  var aiAgentClaude = true;
  var aiCheckpointDays = kAiCheckpointDaysDefault;
  var linkEditor = LinkEditor.auto;
```

In `apps/desktop/lib/src/config/shellx_config.dart`, replace:

```dart
        if (mode == null) return _badValue(e, g, 'ask, off');
        agentResume = mode;
```

with:

```dart
        if (mode == null) return _badValue(e, g, 'ask, off');
        agentResume = mode;
      case 'new-tab-kind':
        final kind = switch (v) {
          '' || 'terminal' => NewTabKind.terminal,
          'ai' => NewTabKind.ai,
          _ => null,
        };
        if (kind == null) return _badValue(e, g, 'terminal, ai');
        newTabKind = kind;
      case 'ai-agent-claude':
        final on = switch (v) {
          '' || 'on' || 'true' => true,
          'off' || 'false' => false,
          _ => null,
        };
        if (on == null) return _badValue(e, g, 'on, off');
        aiAgentClaude = on;
      case 'ai-checkpoint-days':
        if (v.isEmpty) {
          aiCheckpointDays = kAiCheckpointDaysDefault;
        } else {
          final days = _ranged(
            e,
            v,
            kAiCheckpointDaysMin.toDouble(),
            kAiCheckpointDaysMax.toDouble(),
            g,
            integer: true,
          );
          if (days == null) return;
          aiCheckpointDays = days.toInt();
        }
```

In `apps/desktop/lib/src/config/shellx_config.dart`, replace:

```dart
    agentResume: agentResume,
    linkEditor: linkEditor,
```

with:

```dart
    agentResume: agentResume,
    newTabKind: newTabKind,
    aiAgentClaude: aiAgentClaude,
    aiCheckpointDays: aiCheckpointDays,
    linkEditor: linkEditor,
```

In `apps/desktop/lib/src/config/settings_schema.dart`, replace:

```dart
import 'config_state.dart';
```

with:

```dart
import 'config_state.dart';
import 'shellx_config.dart' show kAiCheckpointDaysMax, kAiCheckpointDaysMin;
```

In `apps/desktop/lib/src/config/settings_schema.dart`, replace:

```dart
  SettingDef(
    id: 'launch-at-startup',
```

with:

```dart
  // V2-1 D4: what a new tab is (file key, as `agent-resume`).
  SettingDef(
    id: 'new-tab-kind',
    owner: SettingOwner.file,
    page: SettingPage.general,
    control: SettingControl.segmented,
    fileKey: 'new-tab-kind',
    label: (l) => l.aiNewTabKindLabel,
    description: (l) => l.aiSettingNewTabKindDesc,
    keywords: const ['ai', 'agent', 'tab', 'claude', 'giao diện ai'],
    choices: [
      SettingChoice('terminal', (l) => l.aiNewTabKindTerminal),
      SettingChoice('ai', (l) => l.aiNewTabKindAi),
    ],
    sampleValues: const [
      SettingSample('ai', 'ai'),
      SettingSample('terminal', 'terminal'),
    ],
  ),
  SettingDef(
    id: 'launch-at-startup',
```

In `apps/desktop/lib/src/config/settings_schema.dart`, replace:

```dart
  SettingDef(
    id: 'pr-status',
```

with:

```dart
  // V2-1 D21: the switch that turns the Claude integration off.
  SettingDef(
    id: 'ai-agent-claude',
    owner: SettingOwner.file,
    page: SettingPage.agents,
    control: SettingControl.segmented,
    fileKey: 'ai-agent-claude',
    label: (l) => l.aiSettingClaude,
    description: (l) => l.aiSettingClaudeDesc,
    keywords: const ['claude', 'ai', 'agent', 'anthropic'],
    choices: [
      SettingChoice('on', (l) => l.aiSettingOn),
      SettingChoice('off', (l) => l.aiSettingOff),
    ],
    sampleValues: const [
      SettingSample('off', 'off'),
      SettingSample('on', 'on'),
    ],
  ),
  // V2-1 D12: how long restore points are kept.
  SettingDef(
    id: 'ai-checkpoint-days',
    owner: SettingOwner.file,
    page: SettingPage.agents,
    control: SettingControl.slider,
    fileKey: 'ai-checkpoint-days',
    min: kAiCheckpointDaysMin.toDouble(),
    max: kAiCheckpointDaysMax.toDouble(),
    step: 1,
    label: (l) => l.aiSettingCheckpointDays,
    description: (l) => l.aiSettingCheckpointDaysDesc,
    keywords: const ['undo', 'restore point', 'checkpoint', 'hoàn tác'],
    sampleValues: const [SettingSample('7', '7'), SettingSample('30', '30')],
  ),
  SettingDef(
    id: 'pr-status',
```

In `apps/desktop/lib/src/config/config_show.dart`, replace:

```dart
    v('agent-resume', c.agentResume.name),
```

with:

```dart
    v('agent-resume', c.agentResume.name),
    v('new-tab-kind', c.newTabKind.name),
    v('ai-agent-claude', c.aiAgentClaude ? 'on' : 'off'),
    v('ai-checkpoint-days', '${c.aiCheckpointDays}'),
```

In `apps/desktop/lib/src/config/config_template.dart`, replace:

```dart
    '# agent-event-command = ~/bin/on-agent --fast  (run when an agent starts, needs input or ends; read from this file only, ShellX asks before running a new command)',
```

with:

```dart
    '# agent-event-command = ~/bin/on-agent --fast  (run when an agent starts, needs input or ends; read from this file only, ShellX asks before running a new command)',
    '',
    '# --- AI interface ---',
    '# new-tab-kind = terminal  (ai: new tabs are AI sessions)',
    '# ai-agent-claude = on  (off: hide Claude from the AI interface)',
    '# ai-checkpoint-days = 14  (days the AI tab keeps restore points, 1 to 90)',
```

In `apps/desktop/lib/src/ui/settings/settings_values.dart`, replace:

```dart
  'agent-resume' => c.agentResume.name,
```

with:

```dart
  'agent-resume' => c.agentResume.name,
  'new-tab-kind' => c.newTabKind.name,
  'ai-agent-claude' => c.aiAgentClaude ? 'on' : 'off',
  'ai-checkpoint-days' => '${c.aiCheckpointDays}',
```

In `apps/desktop/lib/src/ui/settings/pages/general_page.dart`, replace:

```dart
        const _UpdateRow(),
      ],
```

with:

```dart
        const _UpdateRow(),
        // V2-1 D4. Last, so the rows above keep their place.
        settingWidget(settingById('new-tab-kind')),
      ],
```

In `apps/desktop/lib/src/platform/settings_store.dart`, replace:

```dart
  static const String appLanguage = 'app_language';

  static const Set<String> all = {
```

with:

```dart
  static const String appLanguage = 'app_language';

  /// V2-1 D4: the one-time "how do you want to work?" card was answered or
  /// closed. UI-owned.
  static const String aiIntroShown = 'ai_intro_shown';

  /// V2-1 D23: the agent "New AI session" starts, a one-element list (an
  /// agent id); missing: the first ready one. UI-owned.
  static const String aiDefaultAgent = 'ai_default_agent';

  /// V2-1 D7: the user's own agents, one JSON object per element. UI-owned.
  static const String aiCustomAgents = 'ai_custom_agents';

  /// V2-1 D11: the remembered choices per agent, one
  /// `agent<TAB>config<TAB>json value` per element. UI-owned.
  static const String aiAgentConfig = 'ai_agent_config';

  static const Set<String> all = {
```

In `apps/desktop/lib/src/platform/settings_store.dart`, replace:

```dart
    agentCommandApproved,
    appLanguage,
  };
}
```

with:

```dart
    agentCommandApproved,
    appLanguage,
    aiIntroShown,
    aiDefaultAgent,
    aiCustomAgents,
    aiAgentConfig,
  };
}
```

In `apps/desktop/lib/src/platform/settings_store.dart`, replace:

```dart
    SettingKeys.agentCommandApproved,
    SettingKeys.appLanguage,
  };
}
```

with:

```dart
    SettingKeys.agentCommandApproved,
    SettingKeys.appLanguage,
    SettingKeys.aiIntroShown,
    SettingKeys.aiDefaultAgent,
    SettingKeys.aiCustomAgents,
    SettingKeys.aiAgentConfig,
  };
}
```

- [ ] **Step 4: Run the config and settings suites**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/config lib/src/ui/settings/settings_values.dart lib/src/ui/settings/pages/general_page.dart lib/src/platform/settings_store.dart test/config test/agent/settings_ownership_test.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/config test/agent/settings_ownership_test.dart test/ui/settings_overlay_test.dart test/ui/settings_general_a12_test.dart test/ui/pages_test.dart test/l10n 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `All tests passed!` (the sample round-trip test now covers six more samples); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/config apps/desktop/lib/src/ui/settings/settings_values.dart apps/desktop/lib/src/ui/settings/pages/general_page.dart apps/desktop/lib/src/platform/settings_store.dart apps/desktop/test/config/settings_schema_test.dart apps/desktop/test/agent/settings_ownership_test.dart apps/desktop/test/config/ai_settings_test.dart
git commit -m "feat(v2-ai): settings new-tab-kind, ai-agent-claude, ai-checkpoint-days and the AI UI keys

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 9: Keys — `new_ai_session` (⌘⇧E / Ctrl+Shift+E) and `new_terminal_tab` [independent of V2-1a]

D5. Two A9 actions, in the keys table, the palette and the shortcut sheet:
- `new_ai_session`, bound by default to ⌘⇧E / Ctrl+Shift+E (`shifted(keyE)`; free on both platforms);
- `new_terminal_tab`, with no chord (a terminal tab even when `new-tab-kind = ai`).

Both go after `tmux_attach` in the tabs group, so the shortcut sheet keeps its first rows (an SSH test reads `tmux_attach` there). The golden test gets a V2-1 additions set. The window's handlers arrive in Task 19; until then the palette hides both entries (it lists only intents the window can run).

**Files:**
- Modify: `apps/desktop/lib/src/config/keybindings.dart`, `keybind_actions.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_intents.dart`, `shortcut_labels.dart`, `apps/desktop/lib/src/ui/config/action_labels.dart`
- Modify: `apps/desktop/test/ui/shortcut_golden_test.dart`, `apps/desktop/test/config/keybindings_test.dart`
- Modify: `agent-skills/shellx-config/SKILL.md`

**Interfaces:**
- Consumes: Task 2 (`actionNewAiSession`, `actionNewTerminalTab`).
- Produces: `class NewAiSessionIntent`, `class NewTerminalTabIntent`, `String? newAiSessionShortcutLabel()`.

- [ ] **Step 1: Write the failing tests**

In `apps/desktop/test/ui/shortcut_golden_test.dart`, replace:

```dart
void main() {
  // No browser map: A6 is not merged ("browser pending A6").
```

with:

```dart
/// V2-1 D5: "New AI session" (⌘⇧E / Ctrl+Shift+E).
Set<String> v21Additions(String platform) => platform == 'mac'
    ? const {'shift+meta+65 norepeat -> NewAiSessionIntent'}
    : const {'ctrl+shift+65 norepeat -> NewAiSessionIntent'};

void main() {
  // No browser map: A6 is not merged ("browser pending A6").
```

In `apps/desktop/test/ui/shortcut_golden_test.dart`, replace:

```dart
              .union(a11Changes(name)),
```

with:

```dart
              .union(a11Changes(name))
              .union(v21Additions(name)),
```

In `apps/desktop/test/config/keybindings_test.dart`, replace:

```dart
  test('unbind, clear, ignore, empty value', () {
```

with:

```dart
  test('V2-1 D5: new_ai_session is ⌘⇧E / Ctrl+Shift+E; new_terminal_tab '
      'has no chord', () {
    var (b, problems) = resolve('');
    expect(problems, isEmpty);
    expect(lookup(b, 'super+shift+e'), isA<NewAiSessionIntent>());
    expect(b.labelOf(const KeyAction('new_ai_session')), '⌘⇧E');
    expect(b.labelOf(const KeyAction('new_terminal_tab')), isNull);
    (b, problems) = resolve('', platform: win);
    expect(lookup(b, 'ctrl+shift+e'), isA<NewAiSessionIntent>());
    expect(b.labelOf(const KeyAction('new_ai_session')), 'Ctrl+Shift+E');
    (b, problems) = resolve('keybind = super+t=new_terminal_tab');
    expect(problems, isEmpty);
    expect(lookup(b, 'super+t'), isA<NewTerminalTabIntent>());
  });

  test('unbind, clear, ignore, empty value', () {
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/config/keybindings_test.dart test/ui/shortcut_golden_test.dart`
Expected: compilation fails, `Undefined name 'NewAiSessionIntent'`.

- [ ] **Step 3: Implement**

In `apps/desktop/lib/src/config/keybindings.dart`, replace:

```dart
    b(shifted(LogicalKeyboardKey.keyN), 'new_workspace'),
```

with:

```dart
    b(shifted(LogicalKeyboardKey.keyN), 'new_workspace'),
    // V2-1 D5: ⌘⇧E / Ctrl+Shift+E (free on both).
    b(shifted(LogicalKeyboardKey.keyE), 'new_ai_session'),
```

In `apps/desktop/lib/src/config/keybind_actions.dart`, replace:

```dart
    const ActionSpec('tmux_attach', ActionGroup.tabs),
```

with:

```dart
    const ActionSpec('tmux_attach', ActionGroup.tabs),
    // V2-1 D5: an AI tab; and a terminal tab whatever `new-tab-kind` says.
    const ActionSpec('new_ai_session', ActionGroup.tabs),
    const ActionSpec('new_terminal_tab', ActionGroup.tabs),
```

In `apps/desktop/lib/src/config/keybind_actions.dart`, replace:

```dart
  'new_tab' => const NewTabIntent(),
```

with:

```dart
  'new_tab' => const NewTabIntent(),
  'new_ai_session' => const NewAiSessionIntent(),
  'new_terminal_tab' => const NewTerminalTabIntent(),
```

In `apps/desktop/lib/src/ui/terminal/terminal_intents.dart`, replace:

```dart
class NewTabIntent extends Intent {
  const NewTabIntent();
}
```

with:

```dart
class NewTabIntent extends Intent {
  const NewTabIntent();
}

/// V2-1 D5: ⌘⇧E / Ctrl+Shift+E, the sidebar's button, the `+` menu.
class NewAiSessionIntent extends Intent {
  const NewAiSessionIntent();
}

/// V2-1 D5: a terminal tab even when `new-tab-kind = ai` (palette, `+`
/// menu).
class NewTerminalTabIntent extends Intent {
  const NewTerminalTabIntent();
}
```

In `apps/desktop/lib/src/ui/config/action_labels.dart`, replace:

```dart
  'new_tab' => l10n.actionNewTab,
```

with:

```dart
  'new_tab' => l10n.actionNewTab,
  'new_ai_session' => l10n.actionNewAiSession,
  'new_terminal_tab' => l10n.actionNewTerminalTab,
```

In `apps/desktop/lib/src/ui/terminal/shortcut_labels.dart`, replace:

```dart
String? newTabShortcutLabel() =>
    actionShortcutLabel(const KeyAction('new_tab'));
```

with:

```dart
String? newTabShortcutLabel() =>
    actionShortcutLabel(const KeyAction('new_tab'));
String? newAiSessionShortcutLabel() =>
    actionShortcutLabel(const KeyAction('new_ai_session'));
```

In `agent-skills/shellx-config/SKILL.md`, replace:

```markdown
Actions: `new_tab`, `close_surface`
```

with:

```markdown
Actions: `new_tab`, `new_ai_session` (New AI session; Cmd+Shift+E / Ctrl+Shift+E), `new_terminal_tab` (a terminal tab even when `new-tab-kind = ai`; no default chord), `close_surface`
```

- [ ] **Step 4: Run the key suites and the whole suite**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/config lib/src/ui/terminal/terminal_intents.dart lib/src/ui/terminal/shortcut_labels.dart lib/src/ui/config/action_labels.dart test/config/keybindings_test.dart test/ui/shortcut_golden_test.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/config/keybindings_test.dart test/ui/shortcut_golden_test.dart test/ui/shortcuts_sheet_test.dart test/ui/ssh_connect_route_test.dart test/ui/command_palette_test.dart 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `All tests passed!` twice (the whole suite: the baseline plus Tasks 1–9's tests; on the scratch copy 3140 passing, 10 skipped); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/config/keybindings.dart apps/desktop/lib/src/config/keybind_actions.dart apps/desktop/lib/src/ui/terminal/terminal_intents.dart apps/desktop/lib/src/ui/terminal/shortcut_labels.dart apps/desktop/lib/src/ui/config/action_labels.dart apps/desktop/test/ui/shortcut_golden_test.dart apps/desktop/test/config/keybindings_test.dart agent-skills/shellx-config/SKILL.md
git commit -m "feat(v2-ai): new_ai_session (Cmd+Shift+E / Ctrl+Shift+E) and new_terminal_tab actions

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: AI services — agents, readiness, runtimes, the D13 bridge, smoothness plumbing [needs V2-1a Task 9]

The desktop side of `package:shellx_ai/host.dart`. It provides:
- **The agent list** (D23 order, Claude switch D21, custom agents D7) and the default agent: the user's choice, else the first ready agent, else Claude. No wait, ever.
- **Readiness**, resolved in the background: `warmUp` once per run, after the first frame (Task 11 calls it), and `refresh`.
- **Remembered choices** (D11). Never Bypass (R6).
- **`AiRuntimes`**, the registry:
  - each AI pane's runtime is made on first use through `aiRuntimeFactoryProvider` (the test seam);
  - the session's title and id go into the tab model;
  - its `AiStatus` goes into A12 as events (D13), with the needs-input → running → idle fix (Review Focus 1);
  - custom agents are left out (B5);
  - a pane that leaves stops its agent (Review Focus 3);
  - `stopAll` serves quit;
  - `aiBusy` feeds the D3 close question.
- **Smoothness plumbing:** `AiFrameNotifier` (one notification per frame) and `aiOffThreadProvider` (`Isolate.run`; tests use the inline runner).

**Files:**
- Modify: `apps/desktop/pubspec.yaml` (`shellx_acp`, `shellx_ai`; V2-1a already put both in the root workspace)
- Create: `apps/desktop/lib/src/ai/ai_off_thread.dart`, `ai_frame_notifier.dart`, `ai_host_provider.dart`, `ai_agents.dart`, `ai_runtimes.dart`
- Create: `apps/desktop/test/support/ai_fakes.dart`
- Test: `apps/desktop/test/ai/ai_frame_notifier_test.dart`, `ai_agents_test.dart`, `ai_runtimes_test.dart`

**Interfaces:**
- Consumes:
  - V2-1a: `AiHost.runtime(...)`, `AiHost.env`, `AiHost.resolver`, `AiRuntime` (`start`, `send`, `cancel`, `whenIdle`, `dispose`, `state`, `onStatus`), `AiStatus`, `AiSessionState` (`label`, `sessionId`, `phase`, `turn`, `currentPermission`, `addListener`), `AgentPhase`, `kKnownAgents`, `AgentSpec`, `CustomLaunch`, `AgentReadiness`/`AgentReady`/`AgentNeedsInstall`, `AgentCommand`; `FakeLauncher`, `FakeScenario`, `FakeSteps` (`package:shellx_ai/testing.dart`).
  - Tasks 3 and 4: `updateAiPane`, `aiBusy`, `tabOfPane`, A12 `ingest` for AI panes.
  - Task 8: `aiAgentClaude`, `SettingKeys.ai*`.
- Produces:
  - `typedef OffThread`; `aiOffThreadProvider`; `inlineOffThread`.
  - `final class AiFrameNotifier extends ChangeNotifier { AiFrameNotifier(AiSessionState state); }`.
  - `aiHostProvider` (overridden by `main.dart`).
  - `kClaudeAgentId`; `CustomAgent` (`spec`, `encode`, `decode`, `toString => '…'`); `aiCustomAgentsProvider` (`add`, `remove`); `aiAgentsProvider`; `aiAgentById`; `agentKindOf`.
  - `aiReadinessSourceProvider`; `aiReadinessProvider` (`warmUp`, `refresh`); `aiNeedsLoginProvider`; `aiDefaultAgentChoiceProvider` (`set`); `aiDefaultAgentProvider`; `rememberedConfig`; `rememberConfig`.
  - `AiRuntimeRequest`; `aiRuntimeFactoryProvider`; `aiRuntimesProvider` with `AiRuntimes.runtimeFor(int paneId)`, `existing`, `busy`, `stopAll`.
  - Test support: `FakeAiRuntimes(FakeScenario first, {later, checkpoints, readiness})` with `.overrides`, `.made`, `.requests`, `.launcher`, `.agent(n)`, and `String get testAiCwd`.

- [ ] **Step 1: Add the packages**

In `apps/desktop/pubspec.yaml`, replace:

```yaml
  shellx_agent: any
  shellx_core: any
```

with:

```yaml
  # V2-1 (V2-1a): the ACP client and the AI session model and host.
  shellx_acp: any
  shellx_agent: any
  shellx_ai: any
  shellx_core: any
```

Then at the repo root: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get`.

- [ ] **Step 2: Write the failing tests and the fakes**

`apps/desktop/test/support/ai_fakes.dart`:

```dart
import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_agents.dart';
import 'package:shellx_desktop/src/ai/ai_off_thread.dart';
import 'package:shellx_desktop/src/ai/ai_runtimes.dart';

/// A folder that exists (the runtime checks it, D6) and that nothing
/// writes to: these runtimes never touch the disk.
String get testAiCwd => Directory.systemTemp.path;

/// AI runtimes over [FakeLauncher] (V2-1a): no process, no login shell,
/// no git (undo off unless [checkpoints]), every agent ready unless
/// [readiness] says otherwise, off-thread work done inline.
final class FakeAiRuntimes {
  FakeAiRuntimes(
    FakeScenario first, {
    List<FakeScenario> later = const [],
    this.checkpoints,
    this.readiness,
  }) : launcher = FakeLauncher(first, later);

  final FakeLauncher launcher;
  final Checkpoints? checkpoints;
  final AgentReadiness? readiness;
  final made = <AiRuntime>[];
  final requests = <AiRuntimeRequest>[];

  static const ready = AgentReady(AgentCommand(executable: 'fake-agent'));

  AiRuntime make(AiRuntimeRequest r) {
    requests.add(r);
    final ckpt = checkpoints;
    final runtime = AiRuntime(
      state: AiSessionState(
        agentId: r.agent.id,
        agentName: r.agent.name,
        cwd: r.cwd,
      ),
      resolve: () async => readiness ?? ready,
      launch: launcher.call,
      clientVersion: 'test',
      checkpoints: ckpt == null ? null : () async => (ckpt, null),
      resumeSessionId: r.resumeSessionId,
      preferredConfig: r.preferredConfig,
    );
    made.add(runtime);
    return runtime;
  }

  /// The agent of launch [n] (0: the first).
  FakeAgent agent([int n = 0]) => launcher.channels[n].agent;

  List<Override> get overrides => [
    aiRuntimeFactoryProvider.overrideWithValue(make),
    aiOffThreadProvider.overrideWithValue(inlineOffThread),
    aiReadinessSourceProvider.overrideWithValue(
      (_) async => readiness ?? ready,
    ),
  ];
}
```

`apps/desktop/test/ai/ai_frame_notifier_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_desktop/src/ai/ai_frame_notifier.dart';

void main() {
  testWidgets('a burst of 2 000 updates is one notification per frame', (
    t,
  ) async {
    final state = AiSessionState(
      agentId: 'claude',
      agentName: 'Claude',
      cwd: '/w',
    );
    final frames = AiFrameNotifier(state);
    var heard = 0;
    frames.addListener(() => heard++);
    final at = DateTime(2026, 10, 14);
    for (var i = 0; i < 2000; i++) {
      state.applyUpdate(AgentMessageChunk(TextBlock('x')), at);
    }
    expect(heard, 0, reason: 'nothing before the frame');
    await t.pump();
    expect(heard, 1);
    await t.pump();
    expect(heard, 1, reason: 'no news, no notification');
    state.applyUpdate(AgentMessageChunk(TextBlock('y')), at);
    await t.pump();
    expect(heard, 2);
    frames.dispose();
    state.applyUpdate(AgentMessageChunk(TextBlock('z')), at);
    await t.pump();
    expect(heard, 2, reason: 'disposed: unhooked');
  });
}
```

`apps/desktop/test/ai/ai_agents_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_desktop/src/ai/ai_agents.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart'
    show settingsStoreProvider;

import '../support/config_harness.dart';
import '../support/memory_config_fs.dart';

void main() {
  late InMemorySettingsStore settings;
  late MemoryConfigFs fs;

  Future<ProviderContainer> container({
    String config = '',
    Future<AgentReadiness> Function(AgentSpec)? source,
  }) async {
    if (config.isNotEmpty) fs.write(testConfigPaths().shellx, config);
    final c = ProviderContainer.test(
      overrides: [
        settingsStoreProvider.overrideWithValue(settings),
        ...configOverrides(fs),
        aiReadinessSourceProvider.overrideWithValue(
          source ?? (_) async => const AgentNeedsInstall(null),
        ),
      ],
    );
    await loadConfig(c);
    return c;
  }

  setUp(() {
    settings = InMemorySettingsStore();
    fs = MemoryConfigFs();
  });

  test('D23 order; ai-agent-claude = off hides Claude (D21)', () async {
    var c = await container();
    expect(c.read(aiAgentsProvider).map((a) => a.id), [
      'claude',
      'codex',
      'gemini',
      'opencode',
    ]);
    expect(c.read(aiAgentsProvider).first.name, 'Claude');
    c = await container(config: 'ai-agent-claude = off\n');
    expect(
      c.read(aiAgentsProvider).map((a) => a.id),
      isNot(contains('claude')),
    );
  });

  test(
    'custom agents: added, kept, listed after the known ones, removed',
    () async {
      final c = await container();
      final added = await c
          .read(aiCustomAgentsProvider.notifier)
          .add(
            name: ' Mine ',
            command: '/opt/mine',
            args: ['--acp'],
            env: {'A': '1'},
          );
      expect(added.id, matches(RegExp(r'^custom-[0-9a-f]{8}$')));
      expect(c.read(aiAgentsProvider).last.id, added.id);
      expect(c.read(aiAgentsProvider).last.name, 'Mine');
      expect(settings.getStrings(SettingKeys.aiCustomAgents), hasLength(1));
      expect(added.toString(), '…');
      final again = await container();
      final kept = again.read(aiCustomAgentsProvider).single;
      expect(
        [kept.command, kept.args, kept.env],
        [
          '/opt/mine',
          ['--acp'],
          {'A': '1'},
        ],
      );
      await c.read(aiCustomAgentsProvider.notifier).remove(added.id);
      expect(settings.getStrings(SettingKeys.aiCustomAgents), isEmpty);
      expect(CustomAgent.decode('not json'), isNull);
      expect(CustomAgent.decode('{"id":"x","name":"a","command":"b"}'), isNull);
    },
  );

  test('A12 kinds for the known agents only (B5)', () {
    expect(agentKindOf('claude'), AgentKind.claude);
    expect(agentKindOf('opencode'), AgentKind.opencode);
    expect(agentKindOf('custom-0a0b0c0d'), isNull);
  });

  test('the default agent: the choice, else the first ready, else the first '
      '(never a wait, D23)', () async {
    final c = await container(
      source: (a) async => a.id == 'codex'
          ? const AgentReady(AgentCommand(executable: 'node'))
          : const AgentNeedsInstall(null),
    );
    expect(c.read(aiDefaultAgentProvider)?.id, 'claude', reason: 'unknown yet');
    await c.read(aiReadinessProvider.notifier).warmUp();
    expect(c.read(aiReadinessProvider), hasLength(4));
    expect(c.read(aiDefaultAgentProvider)?.id, 'codex');
    await c.read(aiDefaultAgentChoiceProvider.notifier).set('gemini');
    expect(c.read(aiDefaultAgentProvider)?.id, 'gemini');
    expect(settings.getStrings(SettingKeys.aiDefaultAgent), ['gemini']);
  });

  test('warm-up runs once; refresh runs again', () async {
    var calls = 0;
    final c = await container(
      source: (_) async {
        calls++;
        return const AgentNeedsInstall(null);
      },
    );
    final notifier = c.read(aiReadinessProvider.notifier);
    await Future.wait([notifier.warmUp(), notifier.warmUp()]);
    expect(calls, 4);
    await notifier.refresh();
    expect(calls, 8);
  });

  test('remembered choices per agent; Bypass permissions never (R6)', () async {
    await rememberConfig(settings, 'claude', 'model', 'opus');
    await rememberConfig(settings, 'claude', 'mode', 'acceptEdits');
    await rememberConfig(settings, 'claude', 'mode', 'bypassPermissions');
    await rememberConfig(settings, 'codex', 'model', 'gpt');
    expect(rememberedConfig(settings, 'claude'), {
      'model': 'opus',
      'mode': 'acceptEdits',
    });
    await rememberConfig(settings, 'claude', 'model', 'sonnet');
    expect(rememberedConfig(settings, 'claude')['model'], 'sonnet');
    expect(rememberedConfig(settings, 'codex'), {'model': 'gpt'});
  });
}
```

`apps/desktop/test/ai/ai_runtimes_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_agents.dart';
import 'package:shellx_desktop/src/ai/ai_runtimes.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';
import 'package:shellx_desktop/src/terminal/agent_status_notifier.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../cli/support/cli_container.dart';
import '../support/ai_fakes.dart';
import '../support/ai_tabs.dart';
import '../support/fake_local_sessions.dart';

void main() {
  late ProviderContainer c;
  late FakeAiRuntimes fakes;

  ProviderContainer boot(FakeScenario scenario) {
    fakes = FakeAiRuntimes(scenario);
    c = cliContainer(FakeLocalSessions(), overrides: fakes.overrides);
    return c;
  }

  AiRuntimes runtimes() => c.read(aiRuntimesProvider.notifier);
  TerminalTab tab(int id) =>
      c.read(terminalTabsProvider).tabs.firstWhere((t) => t.id == id);
  AgentState? a12(int pane) => c.read(agentStatusProvider)[pane]?.state;

  test('made on first use, with the folder and session; none without a '
      'folder (D5, D14)', () {
    boot(const FakeScenario());
    final none = openTestAiTab(c, cwd: null);
    expect(runtimes().runtimeFor(none.ai!.id), isNull);
    final ai = openTestAiTab(c, cwd: testAiCwd, sessionId: 'sess-9');
    final r = runtimes().runtimeFor(ai.ai!.id)!;
    expect(runtimes().runtimeFor(ai.ai!.id), same(r));
    expect(fakes.requests.single.cwd, testAiCwd);
    expect(fakes.requests.single.resumeSessionId, 'sess-9');
    expect(fakes.requests.single.agent.name, 'Claude');
    expect(fakes.launcher.channels, isEmpty, reason: 'made, not started');
  });

  test('the session title and id flow into the tab (D2, D14)', () async {
    boot(const FakeScenario(sessionId: 'sess-1'));
    final ai = openTestAiTab(c, cwd: testAiCwd);
    final r = runtimes().runtimeFor(ai.ai!.id)!;
    await r.start();
    await r.send([const TextBlock('Fix   the login\nbug please')]);
    await r.whenIdle();
    await pumpEventQueue();
    expect(tab(ai.id).ai!.sessionId, 'sess-1');
    expect(tab(ai.id).label, 'Fix the login bug please');
  });

  test('status reaches A12: running, then idle (D13)', () async {
    boot(const FakeScenario());
    final ai = openTestAiTab(c, cwd: testAiCwd, select: false);
    final r = runtimes().runtimeFor(ai.ai!.id)!;
    await r.start();
    await r.send([const TextBlock('hi')]);
    await r.whenIdle();
    await pumpEventQueue();
    expect(a12(ai.ai!.id), AgentState.done, reason: 'not watched: done');
  });

  test('a cancelled question ends as idle, not needs input '
      '(Review Focus 1)', () async {
    boot(
      FakeScenario(
        turns: [
          [FakeSteps.permission('t1', 'Edit a.ts')],
        ],
      ),
    );
    final ai = openTestAiTab(c, cwd: testAiCwd, select: false);
    final r = runtimes().runtimeFor(ai.ai!.id)!;
    await r.start();
    await r.send([const TextBlock('edit')]);
    await pumpEventQueue();
    expect(r.state.currentPermission, isNotNull);
    expect(a12(ai.ai!.id), AgentState.needsInput);
    r.cancel();
    await r.whenIdle();
    await pumpEventQueue();
    expect(a12(ai.ai!.id), isNot(AgentState.needsInput));
  });

  test('a pane that leaves stops its agent (Review Focus 3)', () async {
    boot(const FakeScenario());
    final ai = openTestAiTab(c, cwd: testAiCwd);
    await runtimes().runtimeFor(ai.ai!.id)!.start();
    c.read(terminalTabsProvider.notifier).close(ai.id);
    await pumpEventQueue();
    expect(fakes.launcher.channels.single.stopCalls, 1);
    expect(runtimes().existing(ai.ai!.id), isNull);
  });

  test('stopAll stops every agent (quit, §6)', () async {
    boot(const FakeScenario());
    for (var i = 0; i < 2; i++) {
      final ai = openTestAiTab(c, cwd: testAiCwd);
      await runtimes().runtimeFor(ai.ai!.id)!.start();
    }
    await runtimes().stopAll();
    expect([for (final ch in fakes.launcher.channels) ch.stopCalls], [1, 1]);
    expect([for (final ch in fakes.launcher.channels) ch.exited], [true, true]);
  });

  test('aiBusy is true while a turn runs (D3 close asks)', () async {
    boot(
      FakeScenario(
        turns: [
          [FakeSteps.waitCancel()],
        ],
      ),
    );
    final ai = openTestAiTab(c, cwd: testAiCwd);
    final r = runtimes().runtimeFor(ai.ai!.id)!;
    await r.start();
    final tabs = c.read(terminalTabsProvider.notifier);
    expect(tabs.aiBusy!(ai.id), isFalse);
    await r.send([const TextBlock('go')]);
    await pumpEventQueue();
    expect(tabs.aiBusy!(ai.id), isTrue);
    r.cancel();
    await r.whenIdle();
    expect(tabs.aiBusy!(ai.id), isFalse);
  });

  test('a custom agent is not reported to A12 (B5)', () async {
    boot(const FakeScenario());
    final agent = await c
        .read(aiCustomAgentsProvider.notifier)
        .add(name: 'Mine', command: '/opt/mine');
    final ai = openTestAiTab(
      c,
      agentId: agent.id,
      agentName: 'Mine',
      cwd: testAiCwd,
      select: false,
    );
    final r = runtimes().runtimeFor(ai.ai!.id)!;
    await r.start();
    await r.send([const TextBlock('hi')]);
    await r.whenIdle();
    expect(c.read(agentStatusProvider)[ai.ai!.id], isNull);
  });

  test('a sign-in request marks the agent in Settings › Agents (D7)', () async {
    boot(
      const FakeScenario(
        requireAuth: true,
        authMethods: [
          {
            'id': 'claude-login',
            'name': 'Log in with Claude',
            'type': 'terminal',
          },
        ],
      ),
    );
    final ai = openTestAiTab(c, cwd: testAiCwd);
    await runtimes().runtimeFor(ai.ai!.id)!.start();
    await pumpEventQueue();
    expect(c.read(aiNeedsLoginProvider), contains('claude'));
  });
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ai`
Expected: the test does not compile, `Error when reading 'lib/src/ai/ai_frame_notifier.dart': No such file or directory`.

- [ ] **Step 4: Implement**

`apps/desktop/lib/src/ai/ai_off_thread.dart`:

```dart
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs [work] on [input] away from the UI isolate and returns its result
/// (smoothness: the frame budget). [work] must be a top-level or static
/// function and [input] sendable.
typedef OffThread = Future<R> Function<Q, R>(R Function(Q input) work, Q input);

Future<R> _onIsolate<Q, R>(R Function(Q input) work, Q input) =>
    Isolate.run(() => work(input));

/// Runs [work] right here: tests (a real isolate never runs under fake
/// async) and work too small to be worth a trip.
Future<R> inlineOffThread<Q, R>(R Function(Q input) work, Q input) async =>
    work(input);

/// Line diffs over 2 000 lines, project file indexes, big file reads.
final aiOffThreadProvider = Provider<OffThread>((ref) => _onIsolate);
```

`apps/desktop/lib/src/ai/ai_frame_notifier.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:shellx_ai/shellx_ai.dart';

/// Smoothness: [AiSessionState] calls its listeners on every update, which
/// is hundreds of times a second while an agent streams. Views listen here
/// instead: at most one notification per frame, at the start of that frame
/// (before it builds), never one for nothing.
final class AiFrameNotifier extends ChangeNotifier {
  AiFrameNotifier(this.state) {
    state.addListener(_changed);
  }

  final AiSessionState state;
  var _scheduled = false;
  var _disposed = false;

  void _changed() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    state.removeListener(_changed);
    super.dispose();
  }
}
```

`apps/desktop/lib/src/ai/ai_host_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_ai/host.dart';

/// The app's one [AiHost] (agents, login environment, checkpoints, crash
/// registry). `main.dart` overrides it (V2-1b Task 11); a test that needs
/// one overrides it too — reading it unset is a programming error.
final aiHostProvider = Provider<AiHost>(
  (ref) => throw StateError('aiHostProvider is set by main.dart'),
);
```

`apps/desktop/lib/src/ai/ai_agents.dart`:

```dart
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_ai/host.dart';

import '../config/config_controller.dart' show shellxConfigProvider;
import '../platform/settings_store.dart';
import '../terminal/agent_status.dart' show AgentKind;
import '../terminal/sidebar_workspaces.dart' show settingsStoreProvider;
import 'ai_host_provider.dart';

/// The catalog id of Claude (D21: `ai-agent-claude = off` hides it).
const kClaudeAgentId = 'claude';

/// V2-1 D7: an agent the user added in Settings › Agents — any program that
/// speaks ACP on stdin/stdout. Its environment is the user's own setting:
/// never logged ([toString] is `…`).
@immutable
final class CustomAgent {
  const CustomAgent({
    required this.id,
    required this.name,
    required this.command,
    this.args = const [],
    this.env = const {},
  });

  /// `custom-` and 8 hex digits.
  final String id;
  final String name;

  /// An absolute path, or a name found on the login shell's PATH.
  final String command;
  final List<String> args;
  final Map<String, String> env;

  AgentSpec get spec => AgentSpec(
    id: id,
    name: name,
    launch: CustomLaunch(command: command, args: args, env: env),
  );

  String encode() => jsonEncode({
    'id': id,
    'name': name,
    'command': command,
    'args': args,
    'env': env,
  });

  /// Null for anything that is not one (a hand edit, a damaged entry).
  static CustomAgent? decode(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map<String, Object?>) return null;
      final id = m['id'];
      final name = m['name'];
      final command = m['command'];
      if (id is! String || !id.startsWith('custom-')) return null;
      if (name is! String || name.trim().isEmpty) return null;
      if (command is! String || command.trim().isEmpty) return null;
      final args = m['args'];
      final env = m['env'];
      return CustomAgent(
        id: id,
        name: name,
        command: command,
        args: args is List
            ? [for (final a in args) ?(a is String ? a : null)]
            : const [],
        env: env is Map
            ? {
                for (final e in env.entries)
                  if (e.key is String && e.value is String)
                    e.key as String: e.value as String,
              }
            : const {},
      );
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() => '…';
}

/// V2-1 D7: the user's agents, kept in the settings store.
final aiCustomAgentsProvider =
    NotifierProvider<AiCustomAgents, List<CustomAgent>>(AiCustomAgents.new);

class AiCustomAgents extends Notifier<List<CustomAgent>> {
  @override
  List<CustomAgent> build() => [
    for (final raw
        in ref
            .watch(settingsStoreProvider)
            .getStrings(SettingKeys.aiCustomAgents))
      ?CustomAgent.decode(raw),
  ];

  /// Adds an agent called [name] that runs [command]; returns it.
  Future<CustomAgent> add({
    required String name,
    required String command,
    List<String> args = const [],
    Map<String, String> env = const {},
  }) async {
    final r = Random.secure();
    final hex = [
      for (var i = 0; i < 4; i++)
        r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    final agent = CustomAgent(
      id: 'custom-$hex',
      name: name.trim(),
      command: command.trim(),
      args: args,
      env: env,
    );
    await _save([...state, agent]);
    return agent;
  }

  Future<void> remove(String id) => _save([
    for (final a in state)
      if (a.id != id) a,
  ]);

  Future<void> _save(List<CustomAgent> next) async {
    state = next;
    await ref.read(settingsStoreProvider).setStrings(
      SettingKeys.aiCustomAgents,
      [for (final a in next) a.encode()],
    );
  }
}

/// V2-1 D23: the agents of the AI interface in their default order —
/// Claude (unless `ai-agent-claude = off`, D21), Codex, Gemini CLI,
/// OpenCode — then the user's own.
final aiAgentsProvider = Provider<List<AgentSpec>>((ref) {
  final claude = ref.watch(
    shellxConfigProvider.select((s) => s.config.aiAgentClaude),
  );
  return [
    for (final a in kKnownAgents)
      if (claude || a.id != kClaudeAgentId) a,
    for (final c in ref.watch(aiCustomAgentsProvider)) c.spec,
  ];
});

AgentSpec? aiAgentById(List<AgentSpec> agents, String id) =>
    agents.where((a) => a.id == id).firstOrNull;

/// A12's kind for an AI agent; null for a custom agent (ruling B5).
AgentKind? agentKindOf(String agentId) => switch (agentId) {
  'claude' => AgentKind.claude,
  'codex' => AgentKind.codex,
  'gemini' => AgentKind.gemini,
  'opencode' => AgentKind.opencode,
  _ => null,
};

/// V2-1 D7/D23: how an agent's readiness is learned; tests swap it.
final aiReadinessSourceProvider =
    Provider<Future<AgentReadiness> Function(AgentSpec agent)>((ref) {
      final host = ref.read(aiHostProvider);
      return (agent) async =>
          host.resolver.resolve(agent, await host.env.resolve());
    });

/// V2-1 D7/D23: each agent's readiness as last resolved; absent: not known
/// yet.
final aiReadinessProvider =
    NotifierProvider<AiReadiness, Map<String, AgentReadiness>>(AiReadiness.new);

class AiReadiness extends Notifier<Map<String, AgentReadiness>> {
  Future<void>? _warm;

  @override
  Map<String, AgentReadiness> build() => const {};

  /// Smoothness (warm start): once per run, after the first frame. The login
  /// shell and every agent's checks run in the background, so the first
  /// "New AI session" never waits for them.
  Future<void> warmUp() => _warm ??= refresh();

  /// Resolves every offered agent again (Settings › Agents, after an
  /// install or a sign-in).
  Future<void> refresh() async {
    final source = ref.read(aiReadinessSourceProvider);
    for (final agent in ref.read(aiAgentsProvider)) {
      try {
        final r = await source(agent);
        if (!ref.mounted) return;
        state = {...state, agent.id: r};
      } on Object catch (error) {
        debugPrint('ShellX: agent check failed: ${error.runtimeType}');
      }
    }
  }
}

/// V2-1 D7: agents a session found signed out (`-32000`): Settings ›
/// Agents says "Needs sign-in" for them until a session opens.
final aiNeedsLoginProvider = NotifierProvider<AiNeedsLogin, Set<String>>(
  AiNeedsLogin.new,
);

class AiNeedsLogin extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void set(String agentId, bool needed) {
    if (state.contains(agentId) == needed) return;
    state = needed ? {...state, agentId} : ({...state}..remove(agentId));
  }
}

/// V2-1 D23: the user's choice of default agent (an id), kept in the
/// settings store; null: none.
final aiDefaultAgentChoiceProvider =
    NotifierProvider<AiDefaultAgentChoice, String?>(AiDefaultAgentChoice.new);

class AiDefaultAgentChoice extends Notifier<String?> {
  @override
  String? build() => ref
      .watch(settingsStoreProvider)
      .getStrings(SettingKeys.aiDefaultAgent)
      .firstOrNull;

  Future<void> set(String agentId) async {
    state = agentId;
    await ref.read(settingsStoreProvider).setStrings(
      SettingKeys.aiDefaultAgent,
      [agentId],
    );
  }
}

/// V2-1 D23: what "New AI session" starts — the user's choice while it is
/// offered, else the first agent known to be ready, else the first one
/// (Claude). Never a wait (smoothness: instant feedback); null only with
/// no agent at all.
final aiDefaultAgentProvider = Provider<AgentSpec?>((ref) {
  final agents = ref.watch(aiAgentsProvider);
  final chosen = ref.watch(aiDefaultAgentChoiceProvider);
  final readiness = ref.watch(aiReadinessProvider);
  return (chosen == null ? null : aiAgentById(agents, chosen)) ??
      agents.where((a) => readiness[a.id] is AgentReady).firstOrNull ??
      agents.firstOrNull;
});

/// V2-1 D11: the choices remembered for [agentId]'s new sessions.
Map<String, Object> rememberedConfig(SettingsStore store, String agentId) {
  final out = <String, Object>{};
  for (final line in store.getStrings(SettingKeys.aiAgentConfig)) {
    final parts = line.split('\t');
    if (parts.length != 3 || parts[0] != agentId) continue;
    try {
      final value = jsonDecode(parts[2]);
      if (value is String || value is bool) out[parts[1]] = value as Object;
    } on FormatException {
      continue;
    }
  }
  return out;
}

/// V2-1 D11: remembers [value] of [configId] for [agentId]'s new sessions.
/// "Bypass permissions" is never remembered (ruling R6, never auto-allow).
Future<void> rememberConfig(
  SettingsStore store,
  String agentId,
  String configId,
  Object value,
) async {
  if (value == 'bypassPermissions') return;
  final prefix = '$agentId\t$configId\t';
  await store.setStrings(SettingKeys.aiAgentConfig, [
    for (final line in store.getStrings(SettingKeys.aiAgentConfig))
      if (!line.startsWith(prefix)) line,
    '$prefix${jsonEncode(value)}',
  ]);
}
```

`apps/desktop/lib/src/ai/ai_runtimes.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../terminal/agent_status.dart';
import '../terminal/agent_status_notifier.dart';
import '../terminal/sidebar_workspaces.dart' show settingsStoreProvider;
import '../terminal/terminal_tabs.dart';
import 'ai_agents.dart';
import 'ai_host_provider.dart';

/// What an AI pane needs to start its agent (D6, D11, D14).
@immutable
final class AiRuntimeRequest {
  const AiRuntimeRequest({
    required this.agent,
    required this.cwd,
    this.resumeSessionId,
    this.preferredConfig = const {},
  });

  final AgentSpec agent;
  final String cwd;

  /// `session/load` this session (a restored or a history tab, D14/D15).
  final String? resumeSessionId;

  /// D11: the remembered choices (never "Bypass permissions", R6).
  final Map<String, Object> preferredConfig;

  @override
  String toString() => '…';
}

/// Makes one AI pane's runtime. Tests swap it for runtimes over
/// `FakeLauncher` (`test/support/ai_fakes.dart`): no process, no login
/// shell, no git.
final aiRuntimeFactoryProvider =
    Provider<AiRuntime Function(AiRuntimeRequest request)>(
      (ref) =>
          (r) => ref
              .read(aiHostProvider)
              .runtime(
                agent: r.agent,
                cwd: r.cwd,
                resumeSessionId: r.resumeSessionId,
                preferredConfig: r.preferredConfig,
              ),
    );

/// The runtime of every AI pane: made on first use, stopped when its pane
/// goes, all stopped on quit. It also carries each runtime's news into the
/// rest of the app:
/// - the session title and id into the tab (sidebar, window, `layout.json`);
/// - its status into A12 (badges, A4 notifications, CLI events, D13).
final aiRuntimesProvider = NotifierProvider<AiRuntimes, void>(AiRuntimes.new);

class AiRuntimes extends Notifier<void> {
  final _runtimes = <int, AiRuntime>{};
  final _agentOf = <int, String>{};
  final _last = <int, AiStatus>{};
  final _listeners = <int, void Function()>{};
  final _queued = <int>{};
  final _stopping = <Future<void>>{};

  @override
  void build() {
    ref.listen<TerminalTabsState>(terminalTabsProvider, (_, next) {
      for (final id in [..._runtimes.keys]) {
        if (next.tabOfPane(id) == null) _drop(id);
      }
    });
    // D3: a close asks first while a turn runs.
    ref.read(terminalTabsProvider.notifier).aiBusy = busy;
    ref.onDispose(() {
      for (final id in [..._runtimes.keys]) {
        _drop(id);
      }
    });
  }

  /// The runtime of AI pane [paneId] if one was made.
  AiRuntime? existing(int paneId) => _runtimes[paneId];

  /// The runtime of AI pane [paneId], made (not started) on the first call.
  /// Null while the pane has no folder (D5), is gone, or its agent is not
  /// offered (switched off, removed). Never call it while building: it may
  /// make a runtime.
  AiRuntime? runtimeFor(int paneId) {
    final made = _runtimes[paneId];
    if (made != null) return made;
    final pane = ref
        .read(terminalTabsProvider)
        .tabOfPane(paneId)
        ?.aiPanes[paneId];
    final cwd = pane?.cwd;
    if (pane == null || cwd == null) return null;
    final agent = aiAgentById(ref.read(aiAgentsProvider), pane.agentId);
    if (agent == null) return null;
    final runtime = ref.read(aiRuntimeFactoryProvider)(
      AiRuntimeRequest(
        agent: agent,
        cwd: cwd,
        resumeSessionId: pane.sessionId,
        preferredConfig: rememberedConfig(
          ref.read(settingsStoreProvider),
          agent.id,
        ),
      ),
    );
    _runtimes[paneId] = runtime;
    _agentOf[paneId] = agent.id;
    runtime.onStatus = (status) => _report(paneId, status);
    void listener() => _queueSync(paneId);
    _listeners[paneId] = listener;
    runtime.state.addListener(listener);
    return runtime;
  }

  /// D3: tab [tabId]'s AI pane runs a turn.
  bool busy(int tabId) {
    final tab = ref
        .read(terminalTabsProvider)
        .tabs
        .where((t) => t.id == tabId)
        .firstOrNull;
    final ai = tab?.ai;
    return ai != null && _runtimes[ai.id]?.state.turn != null;
  }

  /// Quit (§6): every agent stops — stdin closed, 2 s, then its process
  /// tree. Completes when all have.
  Future<void> stopAll() async {
    for (final id in [..._runtimes.keys]) {
      _drop(id);
    }
    await Future.wait([..._stopping]);
  }

  void _drop(int paneId) {
    final runtime = _runtimes.remove(paneId);
    if (runtime == null) return;
    final listener = _listeners.remove(paneId);
    if (listener != null) runtime.state.removeListener(listener);
    runtime.onStatus = null;
    _agentOf.remove(paneId);
    _last.remove(paneId);
    late final Future<void> stop;
    stop = runtime
        .dispose()
        .catchError((Object error) {
          debugPrint('ShellX: agent stop failed: ${error.runtimeType}');
        })
        .whenComplete(() => _stopping.remove(stop));
    _stopping.add(stop);
  }

  /// The tab follows its session: title and id. Once per burst of updates
  /// (a streaming answer touches the state hundreds of times a second).
  void _queueSync(int paneId) {
    if (!_queued.add(paneId)) return;
    scheduleMicrotask(() {
      _queued.remove(paneId);
      final runtime = _runtimes[paneId];
      if (runtime == null || !ref.mounted) return;
      final s = runtime.state;
      ref
          .read(terminalTabsProvider.notifier)
          .updateAiPane(
            paneId,
            (p) => p.copyWith(
              title: s.label ?? p.title,
              sessionId: s.sessionId ?? p.sessionId,
            ),
          );
      final agentId = _agentOf[paneId];
      if (agentId == null) return;
      // D7: Settings › Agents says "Needs sign-in" until a session opens.
      final login = ref.read(aiNeedsLoginProvider.notifier);
      if (s.phase == AgentPhase.needsAuth) {
        login.set(agentId, true);
      } else if (s.phase == AgentPhase.ready) {
        login.set(agentId, false);
      }
    });
  }

  /// D13: the runtime's status, as A12 events for the pane.
  void _report(int paneId, AiStatus status) {
    final kind = agentKindOf(_agentOf[paneId] ?? '');
    if (kind == null || !ref.mounted) return; // B5: a custom agent
    final notifier = ref.read(agentStatusProvider.notifier);
    void send(AgentEventKind k) => notifier.ingest(
      AgentEvent(pane: paneId, agent: kind, kind: k, at: DateTime.now()),
    );
    final last = _last[paneId];
    if (last == null && status != AiStatus.ended) send(AgentEventKind.start);
    switch (status) {
      case AiStatus.running:
        send(AgentEventKind.running);
      case AiStatus.needsInput:
        send(AgentEventKind.needsInput);
      case AiStatus.idle:
        // Review Focus 1: A12 keeps "needs input" through an idle; a
        // question the turn's end cancelled is no longer asked.
        if (last == AiStatus.needsInput) send(AgentEventKind.running);
        send(AgentEventKind.idle);
      case AiStatus.ended:
        send(AgentEventKind.end);
    }
    if (status == AiStatus.ended) {
      _last.remove(paneId);
    } else {
      _last[paneId] = status;
    }
  }
}
```

- [ ] **Step 5: Run the tests**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/ai test/ai test/support/ai_fakes.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ai test/terminal/ai_status_readers_test.dart 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `All tests passed!` (`test/ai`: 19 on the scratch copy); `No issues found!`. Run `test/ai/ai_runtimes_test.dart` three times; it must pass every time (no timing flake).

- [ ] **Step 6: Commit**

```bash
git add apps/desktop/pubspec.yaml apps/desktop/lib/src/ai apps/desktop/test/support/ai_fakes.dart apps/desktop/test/ai/ai_frame_notifier_test.dart apps/desktop/test/ai/ai_agents_test.dart apps/desktop/test/ai/ai_runtimes_test.dart
git commit -m "feat(v2-ai): AI runtimes registry, agents, readiness and the A12 status bridge

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 11: App wiring — the host at startup, warm start, stop on quit [needs V2-1a Task 9]

What `main.dart` adds:
- **The host:** `AiHost(supportDir: <app support>, clientVersion: <app version>, killTree: killProcessTree, running: RunningAgents(<support>/ai/running.json, killPid: killProcessTreeByPid))` (D6, §6). V2-1a's defaults kill the process alone; ShellX kills the whole tree, and so for an agent a crash left behind too (`killProcessTreeByPid`: `taskkill /F /T`, or the A10 `PosixProcessTreeKiller`). `killProcessTree(Process, {killer})` tears off as V2-1a's `KillTree`.
- **The run sheet's PTY factory:** the app's own `FlutterPtyFactory`, for Task 18.
- **After the first frame, in the background** (smoothness: warm start): `startup` stops the agents a crash left (`running.json`, §6) and prunes restore points older than `ai-checkpoint-days` (D12); then the login environment and every agent's readiness resolve. `startup` runs once per launch and is never skipped: V2-1a's `AiHost.launch` waits for its sweep, so an AI tab opened earlier simply waits.
- **Quit:** the first quit step stops every agent (bounded to 4 s: stdin closed, 2 s grace, then the process tree).

**Files:**
- Create: `apps/desktop/lib/src/ai/ai_startup.dart`
- Modify: `apps/desktop/lib/src/platform/process_tree.dart`, `apps/desktop/lib/main.dart`
- Test: `apps/desktop/test/ai/ai_startup_test.dart`

**Interfaces:**
- Consumes: Task 10 (`aiHostProvider`, `aiReadinessProvider.warmUp`, `AiRuntimes.stopAll`); V2-1a `AiHost`, `AiHost.startup({Duration retention})`, `RunningAgents(File, {KillPid? killPid})`, `RunningRecord`, `LoginShellEnv`, `CheckpointStores`, `GitLocator`; `killProcessTree`, `ProcessTreeKiller`, `PosixProcessTreeKiller` (`platform/`).
- Produces: `aiPtyFactoryProvider` (`Provider<PtyFactory>`, used by Task 18); `AiHost buildAiHost({required String supportDir, required String version})`; `Future<void> startAi(ProviderContainer)`; `Future<void> stopAi(ProviderContainer)`; `Future<void> killProcessTreeByPid(int pid, {ProcessTreeKiller? killer})`.

- [ ] **Step 1: Write the failing test**

`apps/desktop/test/ai/ai_startup_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_desktop/src/ai/ai_agents.dart';
import 'package:shellx_desktop/src/ai/ai_host_provider.dart';
import 'package:shellx_desktop/src/ai/ai_startup.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart'
    show settingsStoreProvider;

import '../support/config_harness.dart';
import '../support/memory_config_fs.dart';

Future<bool> alive(int pid) async =>
    (await Process.run('kill', ['-0', '$pid'])).exitCode == 0;

void main() {
  test('the host lives under <support>/ai and names the app version', () {
    final host = buildAiHost(supportDir: '/support', version: '2.0.0');
    expect(host.supportDir, '/support');
    expect(host.clientVersion, '2.0.0');
  });

  test(
    'an agent a crash left behind stops with its whole tree (§6)',
    () async {
      final tmp = Directory.systemTemp.createTempSync('ai_sweep');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final pidFile = File('${tmp.path}/grandchild.pid');
      // An "agent" with a child of its own, as `node` runs its adapter.
      final agent = await Process.start('/bin/sh', [
        '-c',
        'sh -c \'sleep 60 & echo \$! > "${pidFile.path}"; wait\' & wait',
      ]);
      unawaited(agent.stdout.drain<void>());
      unawaited(agent.stderr.drain<void>());
      for (var i = 0; i < 100 && !pidFile.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final grandchild = int.parse(pidFile.readAsStringSync().trim());
      final host = buildAiHost(supportDir: tmp.path, version: 'test');
      await host.running.add(
        RunningRecord(
          pid: agent.pid,
          command: '/bin/sh',
          startedAt: DateTime.now(),
        ),
      );
      expect(await host.running.sweep(), 1);
      await agent.exitCode;
      var gone = false;
      for (var i = 0; i < 40 && !gone; i++) {
        gone = !await alive(grandchild);
        if (!gone) await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(gone, isTrue, reason: 'the agent\'s child survived the sweep');
    },
    skip: Platform.isWindows,
  );

  test('start: sweep, prune and warm-up, and nothing throws', () async {
    final tmp = Directory.systemTemp.createTempSync('ai_start');
    addTearDown(() => tmp.deleteSync(recursive: true));
    var checked = 0;
    final host = AiHost(
      supportDir: tmp.path,
      clientVersion: 'test',
      // No login shell, no git: the start must still finish.
      env: LoginShellEnv(
        processEnv: const {'PATH': '/usr/bin'},
        run: (_, _, _, _) async => throw StateError('no shell here'),
      ),
      checkpoints: CheckpointStores(
        root: '${tmp.path}/ai/checkpoints',
        locator: GitLocator(probe: (_, _, {environment}) async => null),
      ),
    );
    final c = ProviderContainer.test(
      overrides: [
        aiHostProvider.overrideWithValue(host),
        aiReadinessSourceProvider.overrideWithValue((_) async {
          checked++;
          return const AgentNeedsInstall(null);
        }),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        ...configOverrides(MemoryConfigFs()),
      ],
    );
    await startAi(c);
    expect(checked, 4, reason: 'every agent, once');
    await startAi(c);
    expect(checked, 4, reason: 'warm-up runs once a run');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ai/ai_startup_test.dart`
Expected: the test does not compile, `Error when reading 'lib/src/ai/ai_startup.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/ai/ai_startup.dart`:

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shellx_agent/shellx_agent.dart' show PtyFactory;
import 'package:shellx_ai/host.dart';

import '../config/config_controller.dart' show shellxConfigProvider;
import '../platform/process_tree.dart';
import 'ai_agents.dart';
import 'ai_host_provider.dart';
import 'ai_runtimes.dart';

/// V2-1 D8: the PTYs of the run sheet (sign-ins, installs). `main.dart`
/// gives it the app's own factory; tests a fake one.
final aiPtyFactoryProvider = Provider<PtyFactory>(
  (ref) => throw StateError('aiPtyFactoryProvider is set by main.dart'),
);

/// The app's AI host: agents and restore points under `<support>/ai` (D6,
/// D12). A stopped agent's whole process tree goes, and so does that of an
/// agent a crash left behind (§6): the package's defaults kill the process
/// alone.
AiHost buildAiHost({required String supportDir, required String version}) =>
    AiHost(
      supportDir: supportDir,
      clientVersion: version,
      killTree: killProcessTree,
      running: RunningAgents(
        File(p.join(supportDir, 'ai', 'running.json')),
        killPid: killProcessTreeByPid,
      ),
    );

/// After the first frame (smoothness: warm start), once per launch and never
/// skipped: V2-1a's `AiHost.launch` waits for this sweep. The agents a crash
/// left behind stop (§6), restore points older than `ai-checkpoint-days` go
/// (D12), then the login environment and every agent's readiness resolve,
/// so the first "New AI session" waits for none of it. Never throws.
Future<void> startAi(ProviderContainer container) async {
  final days = container.read(shellxConfigProvider).config.aiCheckpointDays;
  try {
    final stopped = await container
        .read(aiHostProvider)
        .startup(retention: Duration(days: days));
    if (stopped > 0) debugPrint('ShellX: stopped $stopped stray agent(s)');
  } on Object catch (error) {
    debugPrint('ShellX: AI startup failed: ${error.runtimeType}');
  }
  await container.read(aiReadinessProvider.notifier).warmUp();
}

/// Quit (§6): every agent stops before the app exits.
Future<void> stopAi(ProviderContainer container) =>
    container.read(aiRuntimesProvider.notifier).stopAll();
```

In `apps/desktop/lib/src/platform/process_tree.dart`, replace:

```dart
Future<void> killProcessTree(
  Process process, {
  ProcessTreeKiller? killer,
}) async {
  try {
    if (Platform.isWindows) {
      await Process.run('taskkill', [
        '/F',
        '/T',
        '/PID',
        '${process.pid}',
      ]).timeout(const Duration(seconds: 3));
    } else {
      await (killer ??
              PosixProcessTreeKiller(grace: const Duration(milliseconds: 300)))
          .killTree(process.pid);
    }
  } on Object {
    // Best effort: the process itself is killed below.
  }
  process.kill(ProcessSignal.sigkill);
}
```

with:

```dart
Future<void> killProcessTree(
  Process process, {
  ProcessTreeKiller? killer,
}) async {
  await _killTreeOf(process.pid, killer);
  process.kill(ProcessSignal.sigkill);
}

/// [killProcessTree] by pid, for a process this run did not start: an AI
/// agent a crash left behind (V2-1 §6, `running.json`). Never throws.
Future<void> killProcessTreeByPid(int pid, {ProcessTreeKiller? killer}) async {
  await _killTreeOf(pid, killer);
  Process.killPid(pid, ProcessSignal.sigkill);
}

Future<void> _killTreeOf(int pid, ProcessTreeKiller? killer) async {
  try {
    if (Platform.isWindows) {
      await Process.run('taskkill', [
        '/F',
        '/T',
        '/PID',
        '$pid',
      ]).timeout(const Duration(seconds: 3));
    } else {
      await (killer ??
              PosixProcessTreeKiller(grace: const Duration(milliseconds: 300)))
          .killTree(pid);
    }
  } on Object {
    // Best effort: the process itself is killed after.
  }
}
```

In `apps/desktop/lib/main.dart`, replace:

```dart
import 'src/agent/ui_services.dart';
```

with:

```dart
import 'src/agent/ui_services.dart';
import 'src/ai/ai_host_provider.dart';
import 'src/ai/ai_startup.dart';
```

In `apps/desktop/lib/main.dart`, replace:

```dart
  Future<void> quitApp() async {
    // A11 D22: the global shortcut goes first, so nothing toggles a window
    // that is being torn down. The system drops it with the process anyway.
```

with:

```dart
  Future<void> quitApp() async {
    // V2-1 §6: no agent outlives the app (stdin closed, 2 s, process tree).
    await runBounded(
      () => stopAi(container),
      timeout: const Duration(seconds: 4),
      label: 'stopping AI agents',
    );
    // A11 D22: the global shortcut goes first, so nothing toggles a window
    // that is being torn down. The system drops it with the process anyway.
```

In `apps/desktop/lib/main.dart`, replace:

```dart
  container = ProviderContainer(
    overrides: [
      desktopServicesProvider.overrideWithValue(services),
```

with:

```dart
  container = ProviderContainer(
    overrides: [
      desktopServicesProvider.overrideWithValue(services),
      // V2-1: the AI host (agents, restore points) and the run sheet's PTYs.
      aiHostProvider.overrideWithValue(
        buildAiHost(supportDir: supportDirectory.path, version: info.version),
      ),
      aiPtyFactoryProvider.overrideWithValue(ptyFactory),
```

In `apps/desktop/lib/main.dart`, replace:

```dart
  layoutReady.complete();
  await handleActivation(container);
}
```

with:

```dart
  layoutReady.complete();
  // V2-1 smoothness (warm start): stray agents, old restore points, the
  // login environment and every agent's readiness, in the background.
  _unawaitedLogged(startAi(container), 'AI startup');
  await handleActivation(container);
}
```

- [ ] **Step 4: Test, analyze, build**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ai test/platform/process_tree_test.dart 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter build macos --debug 2>&1 | tail -1
```

Expected: `All tests passed!`; `No issues found!`; the build succeeds. Optional when a display is available: launch the built app and quit it with ⌘Q. Then `pgrep -fl claude-agent-acp` prints nothing, and `~/Library/Application Support/<bundle id>/ai/` exists.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/ai/ai_startup.dart apps/desktop/lib/src/platform/process_tree.dart apps/desktop/lib/main.dart apps/desktop/test/ai/ai_startup_test.dart
git commit -m "feat(v2-ai): AI host at startup (crash sweep of whole process trees, pruning, warm start), agents stop on quit

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 12: The conversation — timeline, markdown, messages, thoughts [needs V2-1a Task 9]

The conversation column (spec §4.1–§4.2) as a part that can be tested on its own. Later tasks plug their cards into `aiTimelineItem`.

**Smoothness:**
- **Virtualized:** a `ListView.builder`.
- **Rev cache:** each item's widget is reused while the item's `rev` is unchanged, so a streaming message rebuilds itself only.
- **Bottom:** the view follows the bottom only while the user is there; scrolled up, the position stays and "Jump to latest" shows. It also follows extent corrections, through `ScrollMetricsNotification`.
- **Markdown blocks (D17):** markdown is split into blocks; unchanged blocks keep their widget, so only the last block re-renders while streaming. A block over 20 000 characters is plain text.
- **Thoughts:** folded, and their text is built only when opened.

**Privacy (B15):** markdown never loads images; links open on a click only, http/https only.

**Placeholders until their tasks:** tool cards show their title (Task 13); turn ends and notices are blank (Task 14); a question shows its text and a "Decline" button (Task 22), so a turn never waits on nothing.

**Files:**
- Create: `apps/desktop/lib/src/ui/ai/ai_theme.dart`, `ai_scope.dart`, `ai_markdown.dart`, `ai_timeline.dart`
- Create: `apps/desktop/test/support/ai_parts.dart`
- Test: `apps/desktop/test/ui/ai/ai_timeline_test.dart`

**Interfaces:**
- Consumes: Task 10 (`AiFrameNotifier`, `FakeAiRuntimes`, `AiRuntimeRequest`), Task 2 strings; V2-1a model (`TimelineItem` and subclasses, `rev`, `AiSessionState.applyUpdate/beginTurn/endTurn`, `TurnOutcome`), ACP blocks.
- Produces:
  - `AiSizes` (`header` 34, `column` 760, `panel` 268, `composerMax` 140, `outputLines` 200, `markdownBlockMax` 20000), `kAiMono`.
  - `class AiPaneScope extends InheritedWidget({runtime, frames, tab, pane, ui, child})` with `static of`, `state`.
  - `final class AiPaneUi extends ChangeNotifier` (`overlay`, `showOverlay`, `closeOverlay`, `panelOpen`, `togglePanel`, `openPanel`, `insert`).
  - `List<String> splitMarkdownBlocks(String)`; `class AiMarkdown({required String text})`.
  - `Widget aiTimelineItem(TimelineItem)`; `class AiTimeline`; `AiUserMessage`, `AiAgentText`, `AiThought`.
  - Test support: `AiRuntime partRuntime(FakeAiRuntimes)`, `pumpAiPart(t, child, {required runtime, overrides, locale})` returning `(container, ui, harness)`.

- [ ] **Step 1: Write the failing test and the helper**

`apps/desktop/test/support/ai_parts.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_desktop/l10n/app_localizations.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/ai/ai_frame_notifier.dart';
import 'package:shellx_desktop/src/ai/ai_runtimes.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/ai/ai_scope.dart';
import 'package:shellx_desktop/src/ui/theme/shellx_desktop_theme.dart';

import 'ai_fakes.dart';
import 'fakes.dart';

/// A runtime over [FakeAiRuntimes] for one part of the pane (made, not
/// started), with Claude as its agent.
AiRuntime partRuntime(FakeAiRuntimes fakes) =>
    fakes.make(AiRuntimeRequest(agent: kKnownAgents.first, cwd: testAiCwd));

/// Pumps [child] inside an AI pane's scope over [runtime].
Future<({ProviderContainer container, AiPaneUi ui, TestHarness harness})>
pumpAiPart(
  WidgetTester t,
  Widget child, {
  required AiRuntime runtime,
  List<Override> overrides = const [],
  Locale locale = const Locale('en'),
}) async {
  final h = TestHarness(locale: locale);
  final c = ProviderContainer(
    overrides: [
      desktopServicesProvider.overrideWithValue(h.services()),
      ...overrides,
    ],
  );
  final frames = AiFrameNotifier(runtime.state);
  final ui = AiPaneUi();
  addTearDown(() {
    frames.dispose();
    ui.dispose();
    c.dispose();
  });
  final tab = TerminalTab.ai(
    id: kSyntheticTabIdBase,
    pane: AiPaneState(
      id: -1,
      agentId: runtime.state.agentId,
      agentName: runtime.state.agentName,
      title: 'New AI session',
      cwd: runtime.state.cwd,
    ),
  );
  t.view.physicalSize = const Size(1000, 700);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: buildDesktopTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Scaffold(
          body: AiPaneScope(
            runtime: runtime,
            frames: frames,
            tab: tab,
            pane: tab.ai!,
            ui: ui,
            child: child,
          ),
        ),
      ),
    ),
  );
  return (container: c, ui: ui, harness: h);
}
```

`apps/desktop/test/ui/ai/ai_timeline_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ui/ai/ai_markdown.dart';
import 'package:shellx_desktop/src/ui/ai/ai_timeline.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';

void main() {
  final at = DateTime(2026, 10, 14, 9);

  testWidgets('the user, the answer as markdown, a folded thought', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    final s = runtime.state;
    s.beginTurn([const TextBlock('Fix the login')], at);
    s.applyUpdate(AgentThoughtChunk(const TextBlock('secret plan')), at);
    s.applyUpdate(AgentMessageChunk(const TextBlock('**Done.**')), at);
    await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Fix the login'), findsOneWidget);
    expect(find.textContaining('Done.', findRichText: true), findsOneWidget);
    expect(find.text('Thinking'), findsOneWidget);
    expect(find.text('secret plan'), findsNothing, reason: 'folded, not built');
    await t.tap(find.text('Thinking'));
    await t.pump();
    expect(find.text('secret plan'), findsOneWidget);
  });

  testWidgets('2 000 chunks: one rebuild per frame, of that message only, '
      'and of its last block only (Review Focus 4)', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    final s = runtime.state..beginTurn([const TextBlock('go')], at);
    await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    AiTimeline.debugItemBuilds = 0;
    AiMarkdown.debugBlockBuilds = 0;
    for (var frame = 0; frame < 20; frame++) {
      for (var i = 0; i < 100; i++) {
        // A new paragraph every 50 chunks: 40 blocks in the end.
        final text = i % 50 == 49 ? 'end.\n\n' : 'word ';
        s.applyUpdate(AgentMessageChunk(TextBlock(text)), at);
      }
      await t.pump();
    }
    expect(AiTimeline.debugItemBuilds, lessThanOrEqualTo(21));
    expect(AiMarkdown.debugBlockBuilds, lessThanOrEqualTo(20 + 40 + 2));
  });

  testWidgets('markdown never loads images; links open on a click, '
      'http/https only (B15)', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    runtime.state
      ..beginTurn([const TextBlock('go')], at)
      ..applyUpdate(
        AgentMessageChunk(
          const TextBlock(
            '![tracker](https://tracker.example/p.png) '
            '[site](https://shellx.pro) [local](file:///etc/passwd)',
          ),
        ),
        at,
      );
    final w = await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('[tracker]', findRichText: true), findsWidgets);
    expect(w.harness.urlOpener.webLinks, isEmpty, reason: 'no click yet');
    await t.tapOnText(find.textRange.ofSubstring('site'));
    await t.pump();
    await t.tapOnText(find.textRange.ofSubstring('local'));
    await t.pump();
    expect(w.harness.urlOpener.webLinks, [Uri.parse('https://shellx.pro')]);
  });

  testWidgets('it follows the bottom; scrolled up it stays, with Jump to '
      'latest', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    final s = runtime.state;
    for (var i = 0; i < 30; i++) {
      s.beginTurn([TextBlock('question $i')], at);
      s.applyUpdate(AgentMessageChunk(TextBlock('answer $i\n\nmore')), at);
      s.endTurn(outcome: TurnOutcome.finished, at: at);
    }
    await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pumpAndSettle();
    ScrollPosition pos() =>
        t.state<ScrollableState>(find.byType(Scrollable).first).position;
    expect(pos().pixels, pos().maxScrollExtent);
    await t.drag(find.byKey(const Key('ai.timeline')), const Offset(0, 400));
    await t.pumpAndSettle();
    final kept = pos().pixels;
    expect(find.byKey(const Key('ai.jumpToLatest')), findsOneWidget);
    s.applyUpdate(AgentMessageChunk(const TextBlock(' and more')), at);
    await t.pumpAndSettle();
    expect(pos().pixels, kept, reason: 'the reader keeps their place');
    await t.tap(find.byKey(const Key('ai.jumpToLatest')));
    await t.pumpAndSettle();
    expect(pos().pixels, pos().maxScrollExtent);
    expect(find.byKey(const Key('ai.jumpToLatest')), findsNothing);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai/ai_timeline_test.dart`
Expected: the test does not compile, `Error when reading 'lib/src/ui/ai/ai_scope.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/ui/ai/ai_theme.dart`:

```dart
import 'package:flutter/painting.dart';

import '../theme/shellx_desktop_theme.dart';

/// V2-1 §4.1: the AI pane's sizes (the demo's layout; colours, spacing and
/// type come from the desktop theme).
abstract final class AiSizes {
  static const double header = 34;
  static const double column = 760;
  static const double panel = 268;
  static const double composerMax = 140;

  /// Smoothness: a tool card shows this many first and last lines of its
  /// output; "Show all N lines" shows the rest (in a scrolled box).
  static const int outputLines = 200;

  /// Smoothness: one markdown block longer than this is shown as plain
  /// text (a parse that long would cost a frame).
  static const int markdownBlockMax = 20000;
}

/// Code, diffs, commands: the terminal's font.
const TextStyle kAiMono = TextStyle(
  fontFamily: 'JetBrainsMono',
  fontSize: 12,
  height: 17 / 12,
  color: ShellxDesktopColors.textPrimary,
);
```

`apps/desktop/lib/src/ui/ai/ai_scope.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../ai/ai_frame_notifier.dart';
import '../../terminal/terminal_tabs.dart';

/// What every part of an AI pane reads: the runtime (its state, and the
/// frame-coalesced notifier views listen to), the tab and pane records, and
/// the pane's own UI state.
class AiPaneScope extends InheritedWidget {
  const AiPaneScope({
    super.key,
    required this.runtime,
    required this.frames,
    required this.tab,
    required this.pane,
    required this.ui,
    required super.child,
  });

  final AiRuntime runtime;
  final AiFrameNotifier frames;
  final TerminalTab tab;
  final AiPaneState pane;
  final AiPaneUi ui;

  AiSessionState get state => runtime.state;

  static AiPaneScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AiPaneScope>();
    assert(scope != null, 'no AiPaneScope above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(AiPaneScope old) =>
      !identical(runtime, old.runtime) ||
      !identical(tab, old.tab) ||
      pane != old.pane;
}

/// The AI pane's own UI state, which its parts change: the overlay over the
/// conversation (run sheet, viewer), the side panel, and text for the
/// composer (Files › "Mention in chat").
final class AiPaneUi extends ChangeNotifier {
  Widget? _overlay;
  var _panel = false;

  Widget? get overlay => _overlay;
  bool get panelOpen => _panel;

  /// Text the composer inserts at its cursor, then clears.
  final insert = ValueNotifier<String?>(null);

  void showOverlay(Widget overlay) {
    _overlay = overlay;
    notifyListeners();
  }

  void closeOverlay() {
    if (_overlay == null) return;
    _overlay = null;
    notifyListeners();
  }

  void togglePanel() {
    _panel = !_panel;
    notifyListeners();
  }

  void openPanel() {
    if (_panel) return;
    _panel = true;
    notifyListeners();
  }

  @override
  void dispose() {
    insert.dispose();
    super.dispose();
  }
}
```

`apps/desktop/lib/src/ui/ai/ai_markdown.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/desktop_services.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_theme.dart';

/// D17: splits [text] into blocks at blank lines outside fenced code, so a
/// streaming message re-renders only its last block.
List<String> splitMarkdownBlocks(String text) {
  final blocks = <String>[];
  final current = StringBuffer();
  String? fence;
  for (final line in text.split('\n')) {
    final trimmed = line.trimLeft();
    if (fence == null &&
        (trimmed.startsWith('```') || trimmed.startsWith('~~~'))) {
      fence = trimmed.substring(0, 3);
    } else if (fence != null && trimmed.startsWith(fence)) {
      fence = null;
    }
    if (fence == null && line.trim().isEmpty) {
      if (current.isNotEmpty) {
        blocks.add(current.toString());
        current.clear();
      }
      continue;
    }
    if (current.isNotEmpty) current.write('\n');
    current.write(line);
  }
  if (current.isNotEmpty) blocks.add(current.toString());
  return blocks;
}

/// The agent's markdown (D17). Smoothness: one widget per block, and a
/// block whose text did not change is the same widget, so streaming
/// rebuilds the last block only; a block over [AiSizes.markdownBlockMax]
/// characters is plain text. Privacy (B15): images never load (their alt
/// text shows), links open only on a click, and only http/https.
class AiMarkdown extends StatefulWidget {
  const AiMarkdown({super.key, required this.text});
  final String text;

  /// Times a block was (re)built (tests: the streaming bound).
  @visibleForTesting
  static int debugBlockBuilds = 0;

  @override
  State<AiMarkdown> createState() => _AiMarkdownState();
}

class _AiMarkdownState extends State<AiMarkdown> {
  var _blocks = <(String, Widget)>[];

  @override
  Widget build(BuildContext context) {
    final texts = splitMarkdownBlocks(widget.text);
    _blocks = [
      for (final (i, t) in texts.indexed)
        i < _blocks.length && _blocks[i].$1 == t
            ? _blocks[i]
            : (t, _Block(key: ValueKey(i), text: t)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final (_, w) in _blocks) w],
    );
  }
}

class _Block extends ConsumerWidget {
  const _Block({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AiMarkdown.debugBlockBuilds++;
    const body = TextStyle(
      fontSize: 13,
      height: 20 / 13,
      color: ShellxDesktopColors.textPrimary,
    );
    final child = text.length > AiSizes.markdownBlockMax
        ? Text(text, style: kAiMono)
        : MarkdownBody(
            data: text,
            // B15: never fetch what an agent's text points at.
            imageBuilder: (uri, title, alt) => Text(
              '[${alt ?? title ?? ''}]',
              style: body.copyWith(color: ShellxDesktopColors.textSecondary),
            ),
            onTapLink: (text, href, title) => _open(ref, href),
            styleSheet: MarkdownStyleSheet(
              p: body,
              a: body.copyWith(
                color: ShellxDesktopColors.accent,
                decoration: TextDecoration.underline,
              ),
              code: kAiMono.copyWith(
                backgroundColor: ShellxDesktopColors.surfaceInset,
              ),
              codeblockDecoration: BoxDecoration(
                color: ShellxDesktopColors.surfaceInset,
                borderRadius: BorderRadius.circular(ShellxRadius.r6),
                border: Border.all(color: ShellxDesktopColors.border),
              ),
              codeblockPadding: const EdgeInsets.all(ShellxSpace.s8),
              h1: ShellxText.emptyTitle.copyWith(
                color: ShellxDesktopColors.textTitle,
              ),
              h2: ShellxText.bodyStrong.copyWith(
                fontSize: 14,
                color: ShellxDesktopColors.textTitle,
              ),
              h3: ShellxText.bodyStrong.copyWith(
                color: ShellxDesktopColors.textTitle,
              ),
              listBullet: body,
              blockquote: body.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
              blockquoteDecoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: ShellxDesktopColors.line, width: 3),
                ),
              ),
              tableBody: body,
              tableHead: body.copyWith(fontWeight: FontWeight.w600),
              horizontalRuleDecoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: ShellxDesktopColors.line),
                ),
              ),
            ),
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: ShellxSpace.s8),
      child: child,
    );
  }

  static void _open(WidgetRef ref, String? href) {
    final uri = href == null ? null : Uri.tryParse(href);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return;
    }
    unawaited(
      ref.read(desktopServicesProvider).urlOpener.openWebLink(uri).catchError((
        Object e,
      ) {
        debugPrint('ShellX: link not opened: ${e.runtimeType}');
      }),
    );
  }
}
```

`apps/desktop/lib/src/ui/ai/ai_timeline.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../../l10n/app_localizations.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_markdown.dart';
import 'ai_scope.dart';
import 'ai_theme.dart';

/// One conversation item's widget (spec §4.2).
Widget aiTimelineItem(TimelineItem item) => switch (item) {
  UserItem() => AiUserMessage(item: item),
  AgentTextItem() => AiAgentText(item: item),
  ThoughtItem() => AiThought(item: item),
  ToolItem() => _PlainLine(text: item.fields.title ?? ''),
  AskItem() => _AskFallback(item: item),
  TurnEndItem() => const SizedBox(height: ShellxSpace.s8),
  NoticeItem() => const SizedBox.shrink(),
};

/// The conversation (spec §4.1, §4.2). Smoothness:
/// - virtualized ([ListView.builder]), newest at the bottom;
/// - an item's widget is reused until the item's `rev` changes, so a
///   streaming message rebuilds that message only;
/// - it follows the bottom only while the user is there; scrolled up, the
///   position stays and "Jump to latest" shows.
class AiTimeline extends StatefulWidget {
  const AiTimeline({super.key});

  /// Item widgets made (tests: the streaming bound).
  @visibleForTesting
  static int debugItemBuilds = 0;

  @override
  State<AiTimeline> createState() => _AiTimelineState();
}

final class _Built {
  _Built(this.rev, this.epoch, this.widget);
  final int rev;
  final int epoch;
  final Widget widget;
}

class _AiTimelineState extends State<AiTimeline> {
  final _scroll = ScrollController();
  final _cache = Expando<_Built>();

  /// Bumped when what every item reads changes (language, the scope).
  var _epoch = 0;
  var _stick = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _epoch++;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final p = _scroll.position;
    final atBottom = p.maxScrollExtent - p.pixels <= 24;
    if (atBottom != _stick) setState(() => _stick = atBottom);
  }

  void _followBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_stick || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (_scroll.position.pixels != max) _scroll.jumpTo(max);
    });
  }

  void _jumpToLatest() {
    setState(() => _stick = true);
    _followBottom();
  }

  Widget _item(TimelineItem item) {
    final hit = _cache[item];
    if (hit != null && hit.rev == item.rev && hit.epoch == _epoch) {
      return hit.widget;
    }
    AiTimeline.debugItemBuilds++;
    final widget = KeyedSubtree(
      key: ObjectKey(item),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AiSizes.column),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ShellxSpace.s16,
              vertical: ShellxSpace.s4,
            ),
            child: aiTimelineItem(item),
          ),
        ),
      ),
    );
    _cache[item] = _Built(item.rev, _epoch, widget);
    return widget;
  }

  @override
  Widget build(BuildContext context) {
    final scope = AiPaneScope.of(context);
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: scope.frames,
      builder: (context, _) {
        final items = scope.state.timeline.items;
        if (_stick) _followBottom();
        return Stack(
          children: [
            Positioned.fill(
              // Item extents are estimated until laid out: a growing extent
              // moves the bottom, which a stuck view follows.
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: (_) {
                  if (_stick) _followBottom();
                  return false;
                },
                child: ListView.builder(
                  key: const Key('ai.timeline'),
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(
                    vertical: ShellxSpace.s16,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _item(items[i]),
                ),
              ),
            ),
            if (!_stick)
              Positioned(
                left: 0,
                right: 0,
                bottom: ShellxSpace.s12,
                child: Center(
                  child: FilledButton.tonalIcon(
                    key: const Key('ai.jumpToLatest'),
                    onPressed: _jumpToLatest,
                    icon: const Icon(Icons.arrow_downward, size: 14),
                    label: Text(l10n.aiJumpToLatest),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The user's message: its text, its file mentions and images as chips.
class AiUserMessage extends StatelessWidget {
  const AiUserMessage({super.key, required this.item});
  final UserItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = [
      for (final b in item.blocks)
        if (b is TextBlock) b.text,
    ].join();
    final chips = [
      for (final b in item.blocks)
        if (b is ResourceLinkBlock)
          '@${b.name}'
        else if (b is ImageBlock)
          l10n.aiAttachImage,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.aiYou,
          style: ShellxText.caption.copyWith(
            color: ShellxDesktopColors.textSecondary,
          ),
        ),
        const SizedBox(height: ShellxSpace.s4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: ShellxSpace.s12,
            vertical: ShellxSpace.s8,
          ),
          decoration: BoxDecoration(
            color: ShellxDesktopColors.surface,
            borderRadius: BorderRadius.circular(ShellxRadius.r8),
            border: Border.all(color: ShellxDesktopColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (text.isNotEmpty)
                SelectableText(
                  text,
                  style: ShellxText.body.copyWith(
                    color: ShellxDesktopColors.textPrimary,
                  ),
                ),
              if (chips.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: ShellxSpace.s6),
                  child: Wrap(
                    spacing: ShellxSpace.s6,
                    runSpacing: ShellxSpace.s4,
                    children: [
                      for (final c in chips)
                        Chip(
                          label: Text(c, style: ShellxText.caption),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The agent's answer (`agent_message_chunk`, merged), as markdown.
class AiAgentText extends StatelessWidget {
  const AiAgentText({super.key, required this.item});
  final AgentTextItem item;

  @override
  Widget build(BuildContext context) =>
      SelectionArea(child: AiMarkdown(text: item.text));
}

/// A thought (`agent_thought_chunk`): folded; its text is built only once
/// opened (smoothness: collapsed bodies cost nothing).
class AiThought extends StatefulWidget {
  const AiThought({super.key, required this.item});
  final ThoughtItem item;

  @override
  State<AiThought> createState() => _AiThoughtState();
}

class _AiThoughtState extends State<AiThought> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const dim = ShellxDesktopColors.textSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(ShellxRadius.r4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _open ? Icons.expand_more : Icons.chevron_right,
                size: 16,
                color: dim,
              ),
              Text(
                l10n.aiThinking,
                style: ShellxText.small.copyWith(color: dim),
              ),
            ],
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(left: ShellxSpace.s16),
            child: SelectableText(
              widget.item.text,
              style: ShellxText.small.copyWith(color: dim),
            ),
          ),
      ],
    );
  }
}

class _PlainLine extends StatelessWidget {
  const _PlainLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: ShellxText.small.copyWith(color: ShellxDesktopColors.textSecondary),
  );
}

/// Until the question cards (D22) land: the agent's question and a way to
/// say no, so a turn never waits on nothing.
class _AskFallback extends StatelessWidget {
  const _AskFallback({required this.item});
  final AskItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final runtime = AiPaneScope.of(context).runtime;
    return Row(
      children: [
        Expanded(child: _PlainLine(text: item.request.message)),
        if (item.response == null && !item.autoDeclined)
          TextButton(
            onPressed: () => runtime.answerAsk(item.id, const ElicitDecline()),
            child: Text(l10n.aiAskDecline),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the test**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/ui/ai test/ui/ai test/support/ai_parts.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai/ai_timeline_test.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `+4: All tests passed!`; `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/ui/ai/ai_theme.dart apps/desktop/lib/src/ui/ai/ai_scope.dart apps/desktop/lib/src/ui/ai/ai_markdown.dart apps/desktop/lib/src/ui/ai/ai_timeline.dart apps/desktop/test/support/ai_parts.dart apps/desktop/test/ui/ai/ai_timeline_test.dart
git commit -m "feat(v2-ai): the AI conversation — virtualized timeline, block markdown, messages

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 13: Tool cards per `kind`, line diffs off the UI isolate [needs V2-1a Task 9]

Spec §4.2.

**Headers:** one card per `tool_call` (keyed by `toolCallId`, updated in place by V2-1a's merge, so Claude's generic "Read File" becomes "Read hello.txt"). Each header has the icon, the verb, a target relative to the session folder, +/− for edits, and a text status:
- "waiting";
- "waiting for you" (`warn`);
- "● running · 2.1 s" (once a second, never animated);
- ✓, plus the run time for commands;
- "rejected" / "stopped" / "error".

**Bodies:**
- An edit waiting for permission opens by itself, and so does a finished command.
- Edits show the diff (3 lines of context) and "Open in editor" (the `link-editor` app, else reveal).
- Commands show their output, or "No output…" with the Changes-panel hint.
- `other` shows `rawInput` and the result; `mcp__a__b` reads "a · b"; `switch_mode` is one line.
- Under the card: "Waiting for your answer below — keys 1–n, Esc to reject", "You chose: Allow (Yes)", or "The turn stopped before you answered".

**Smoothness:**
- Bodies are built only when open.
- Output shows its first and last 200 lines, with "Show all N lines" (then a virtualized box).
- A diff over 2 000 lines runs through `aiOffThreadProvider` (`computeLineDiff` is top-level, so it can run on an isolate). A long diff view is a fixed-height virtualized list.

**Files:**
- Create: `apps/desktop/lib/src/ai/line_diff.dart`, `apps/desktop/lib/src/ui/ai/ai_labels.dart`, `ai_diff_view.dart`, `ai_tool_card.dart`
- Modify: `apps/desktop/lib/src/ui/ai/ai_timeline.dart`
- Test: `apps/desktop/test/ai/line_diff_test.dart`, `apps/desktop/test/ui/ai/ai_tool_card_test.dart`

**Interfaces:**
- Consumes: Task 12 (`AiPaneScope`, `aiTimelineItem`, `pumpAiPart`, `partRuntime`, `kAiMono`, `AiSizes`), Task 10 (`aiOffThreadProvider`), `editorFor` + `editorDetectorProvider` (A10), V2-1a `ToolItem` (`fields`, `end`, `startedAt`, `endedAt`, `awaitingPermission`, `permissionAnswer`, `permissionCancelled`), `AiSessionState.permissions`/`addPermission`/`resolvePermission`.
- Produces:
  - `enum DiffOp`; `DiffLine`; `typedef DiffStat`; `diffStat`; `kInlineDiffLines = 2000`; `List<DiffLine> computeLineDiff((String, String))`; `Future<List<DiffLine>> lineDiff(OffThread run, String old, String now)`; `List<DiffLine?> withContext(List<DiffLine>, {int context = 3})`.
  - `String aiPermissionLabel(AppLocalizations, PermissionOption)`; `aiRelativePath`; `aiClock(Duration)` ("0:41"); `aiSeconds(Duration, String localeName)`.
  - `class AiDiffView({required List<DiffLine?> lines, double height = 360})`.
  - `aiToolLabel(...)`; `class AiToolCard({required ToolItem item})`.

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/ai/line_diff_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/ai/ai_off_thread.dart';
import 'package:shellx_desktop/src/ai/line_diff.dart';

void main() {
  test('a line diff: same, removed, added, with line numbers', () {
    final d = computeLineDiff(('a\nb\nc\n', 'a\nB\nc\nd\n'));
    expect(
      [for (final l in d) (l.op, l.text)],
      [
        (DiffOp.same, 'a'),
        (DiffOp.removed, 'b'),
        (DiffOp.added, 'B'),
        (DiffOp.same, 'c'),
        (DiffOp.added, 'd'),
      ],
    );
    expect(d[2].newNo, 2);
    expect(d[1].oldNo, 2);
    expect(diffStat(d), (added: 2, removed: 1));
  });

  test('CRLF and LF read the same (§6 Windows); a new file is all added', () {
    expect(
      computeLineDiff((
        'a\r\nb\r\n',
        'a\nb\n',
      )).every((l) => l.op == DiffOp.same),
      isTrue,
    );
    expect(diffStat(computeLineDiff(('', 'x\ny\n'))), (added: 2, removed: 0));
  });

  test('context: three lines around each change, gaps as null', () {
    final old = [for (var i = 0; i < 20; i++) 'l$i'].join('\n');
    final now = old.replaceFirst('l10', 'L10');
    final shown = withContext(computeLineDiff((old, now)));
    expect(shown.first, isNull);
    expect(shown.last, isNull);
    expect(shown.whereType<DiffLine>().length, 3 + 2 + 3);
  });

  test('long texts go off the UI isolate; short ones never do', () async {
    var trips = 0;
    Future<R> counting<Q, R>(R Function(Q) work, Q input) async {
      trips++;
      return work(input);
    }

    await lineDiff(counting, 'a\n', 'b\n');
    expect(trips, 0);
    final big = List.filled(kInlineDiffLines + 1, 'x').join('\n');
    final d = await lineDiff(counting, big, '$big\ny');
    expect(trips, 1);
    expect(diffStat(d).added, 1);
    expect(inlineOffThread(computeLineDiff, ('a', 'a')), completes);
  });
}
```

`apps/desktop/test/ui/ai/ai_tool_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ui/ai/ai_timeline.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';

void main() {
  final at = DateTime(2026, 10, 14, 9);

  void tool(
    AiSessionState s,
    String id,
    ToolKind kind,
    String title, {
    ToolCallStatus? status,
    List<ToolContent>? content,
    List<ToolLocation>? locations,
    Object? rawInput,
  }) => s.applyUpdate(
    ToolCallStarted(
      id,
      ToolCallFields(
        title: title,
        kind: kind,
        status: status,
        content: content,
        locations: locations,
        rawInput: rawInput,
      ),
    ),
    at,
  );

  testWidgets('one card per kind, with its verb and target (spec §4.2)', (
    t,
  ) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final runtime = partRuntime(fakes);
    final s = runtime.state..beginTurn([const TextBlock('go')], at);
    final cwd = s.cwd;
    tool(
      s,
      'r',
      ToolKind.read,
      'Read File',
      locations: [ToolLocation('$cwd/src/a.ts', 3)],
    );
    tool(
      s,
      'c',
      ToolKind.edit,
      'Write',
      content: [ToolDiff(path: '$cwd/new.ts', newText: 'x\n')],
    );
    tool(
      s,
      'e',
      ToolKind.edit,
      'Edit',
      content: [
        ToolDiff(path: '$cwd/b.ts', oldText: 'a\nb\n', newText: 'a\nB\nc\n'),
      ],
    );
    tool(
      s,
      'd',
      ToolKind.delete,
      'Delete',
      locations: [ToolLocation('$cwd/old.ts')],
    );
    tool(s, 's', ToolKind.search, 'TODO in src');
    tool(s, 'x', ToolKind.execute, 'npm test');
    tool(s, 'f', ToolKind.fetch, 'https://example.com');
    tool(s, 'm', ToolKind.other, 'mcp__github__create_issue');
    tool(s, 'w', ToolKind.switchMode, 'plan');
    await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    for (final text in [
      'src/a.ts',
      'new.ts',
      'b.ts',
      'old.ts',
      'TODO in src',
      'npm test',
      'https://example.com',
      'github · create_issue',
      'Mode changed: plan',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    for (final verb in [
      'Read',
      'Create',
      'Edit',
      'Delete',
      'Search',
      'Run',
      'Fetch',
    ]) {
      expect(find.text(verb), findsOneWidget, reason: verb);
    }
    expect(find.text('+2'), findsOneWidget);
    expect(find.text('−1'), findsOneWidget);
  });

  testWidgets('status: waiting, running, done, error, rejected, stopped', (
    t,
  ) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final runtime = partRuntime(fakes);
    final s = runtime.state..beginTurn([const TextBlock('go')], at);
    tool(s, 'p', ToolKind.read, 'pending one');
    tool(
      s,
      'r',
      ToolKind.search,
      'running one',
      status: ToolCallStatus.inProgress,
    );
    tool(s, 'f', ToolKind.search, 'failed one', status: ToolCallStatus.failed);
    final w = await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    final texts = [
      for (final e in find.byKey(const Key('ai.tool.status')).evaluate())
        (e.widget as Text).data,
    ];
    expect(texts, contains('waiting'));
    expect(texts.any((x) => x!.startsWith('running · ')), isTrue);
    expect(texts, contains('error'));
    s.endTurn(outcome: TurnOutcome.cancelled, at: at);
    await t.pump();
    expect(find.text('stopped'), findsNWidgets(2));
    expect(w.ui.overlay, isNull);
  });

  testWidgets('a long output shows its ends and "Show all N lines"', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    final s = runtime.state..beginTurn([const TextBlock('go')], at);
    final out = [for (var i = 0; i < 1000; i++) 'line $i'].join('\n');
    tool(
      s,
      'x',
      ToolKind.execute,
      'yes',
      status: ToolCallStatus.completed,
      content: [ToolContentBlock(TextBlock(out))],
    );
    await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    expect(find.text('600 lines hidden'), findsOneWidget);
    expect(find.textContaining('line 500'), findsNothing);
    await t.ensureVisible(find.byKey(const Key('ai.tool.showAll')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ai.tool.showAll')));
    await t.pump();
    expect(find.byKey(const Key('ai.tool.showAll')), findsNothing);
  });

  testWidgets('a command with no output says the Changes panel still sees '
      'its files', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    final s = runtime.state..beginTurn([const TextBlock('go')], at);
    tool(s, 'y', ToolKind.execute, 'true', status: ToolCallStatus.completed);
    await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    expect(find.textContaining('No output.'), findsOneWidget);
  });

  testWidgets('an edit asking permission opens and says how to answer (D10)', (
    t,
  ) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final runtime = partRuntime(fakes);
    final s = runtime.state..beginTurn([const TextBlock('go')], at);
    s.addPermission(
      PermissionRequest(
        sessionId: 's',
        toolCallId: 't1',
        toolCall: ToolCallFields(
          title: 'Edit a.ts',
          kind: ToolKind.edit,
          content: [
            ToolDiff(path: '${s.cwd}/a.ts', oldText: 'a\n', newText: 'b\n'),
          ],
        ),
        options: const [
          PermissionOption(
            optionId: 'y',
            name: 'Yes',
            kind: PermissionKind.allowOnce,
          ),
          PermissionOption(
            optionId: 'a',
            name: 'Yes, always',
            kind: PermissionKind.allowAlways,
          ),
          PermissionOption(
            optionId: 'n',
            name: 'No',
            kind: PermissionKind.rejectOnce,
          ),
        ],
      ),
      at,
    );
    await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    expect(find.text('waiting for you'), findsOneWidget);
    expect(
      find.text('Waiting for your answer below — keys 1–3, Esc to reject'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('ai.tool.editor')),
      findsOneWidget,
      reason: 'opened',
    );
    s.resolvePermission(s.permissions.single.id, const PermissionSelected('y'));
    await t.pump();
    expect(find.text('You chose: Allow (Yes)'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ai/line_diff_test.dart test/ui/ai/ai_tool_card_test.dart`
Expected: the test does not compile, `Error when reading 'lib/src/ai/line_diff.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/ai/line_diff.dart`:

```dart
import 'package:diff_match_patch/diff_match_patch.dart' as dmp;
import 'package:flutter/foundation.dart';

import 'ai_off_thread.dart';

enum DiffOp { same, added, removed }

/// One line of a line diff, with its numbers in the old and the new text.
@immutable
final class DiffLine {
  const DiffLine(this.op, this.text, {this.oldNo, this.newNo});
  final DiffOp op;
  final String text;
  final int? oldNo;
  final int? newNo;

  @override
  String toString() => '…';
}

/// Lines added and removed.
typedef DiffStat = ({int added, int removed});

DiffStat diffStat(List<DiffLine> lines) => (
  added: lines.where((l) => l.op == DiffOp.added).length,
  removed: lines.where((l) => l.op == DiffOp.removed).length,
);

/// Above this many lines in all, a diff runs off the UI isolate.
const int kInlineDiffLines = 2000;

List<String> _lines(String text) {
  // §6 Windows: shown without CR, so a CRLF file does not differ on every
  // line (revert still writes the exact bytes).
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  return lines;
}

/// D17: a line-mode diff of `(old, new)`: diff_match_patch on one code unit
/// per distinct line (its own "line mode"). One argument, top-level: it
/// can run on another isolate ([lineDiff]).
List<DiffLine> computeLineDiff((String, String) texts) {
  final a = _lines(texts.$1);
  final b = _lines(texts.$2);
  final index = <String, int>{};
  final table = <String>[];
  // One BMP code unit per distinct line, never a surrogate.
  int code(String line) => index.putIfAbsent(line, () {
    table.add(line);
    final n = table.length;
    return n < 0xD800 ? n : n + 0x800;
  });
  final ca = a.map(code).toList();
  final cb = b.map(code).toList();
  if (table.length > 0xFFFF - 0x800 - 1) {
    // Too many distinct lines to encode: all out, all in.
    return [
      for (final (i, l) in a.indexed) DiffLine(DiffOp.removed, l, oldNo: i + 1),
      for (final (i, l) in b.indexed) DiffLine(DiffOp.added, l, newNo: i + 1),
    ];
  }
  String lineOf(int unit) => table[(unit < 0xD800 ? unit : unit - 0x800) - 1];
  final diffs = dmp.diff(
    String.fromCharCodes(ca),
    String.fromCharCodes(cb),
    checklines: false,
    timeout: 2,
  );
  final out = <DiffLine>[];
  var oldNo = 0;
  var newNo = 0;
  for (final d in diffs) {
    for (final unit in d.text.codeUnits) {
      final text = lineOf(unit);
      switch (d.operation) {
        case dmp.DIFF_EQUAL:
          out.add(DiffLine(DiffOp.same, text, oldNo: ++oldNo, newNo: ++newNo));
        case dmp.DIFF_DELETE:
          out.add(DiffLine(DiffOp.removed, text, oldNo: ++oldNo));
        default:
          out.add(DiffLine(DiffOp.added, text, newNo: ++newNo));
      }
    }
  }
  return out;
}

/// [computeLineDiff], off the UI isolate when the texts are long
/// (smoothness: the frame budget).
Future<List<DiffLine>> lineDiff(OffThread run, String old, String now) {
  final lines = '\n'.allMatches(old).length + '\n'.allMatches(now).length;
  return lines > kInlineDiffLines
      ? run(computeLineDiff, (old, now))
      : SynchronousFuture(computeLineDiff((old, now)));
}

/// The changed lines with [context] lines around each run; null stands for
/// the lines left out.
List<DiffLine?> withContext(List<DiffLine> lines, {int context = 3}) {
  final keep = List.filled(lines.length, false);
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].op == DiffOp.same) continue;
    for (var j = i - context; j <= i + context; j++) {
      if (j >= 0 && j < lines.length) keep[j] = true;
    }
  }
  final out = <DiffLine?>[];
  var gap = false;
  for (var i = 0; i < lines.length; i++) {
    if (keep[i]) {
      out.add(lines[i]);
      gap = false;
    } else if (!gap) {
      out.add(null);
      gap = true;
    }
  }
  return out;
}
```

`apps/desktop/lib/src/ui/ai/ai_labels.dart`:

```dart
import 'package:shellx_acp/shellx_acp.dart';

import '../../../l10n/app_localizations.dart';

/// D10: the main label of a permission option comes from its kind; the
/// agent's own words stay as the second line (only the agent knows what
/// "always" covers).
String aiPermissionLabel(AppLocalizations l10n, PermissionOption option) =>
    switch (option.kind) {
      PermissionKind.allowOnce => l10n.aiPermAllowOnce,
      PermissionKind.allowAlways => l10n.aiPermAllowAlways,
      PermissionKind.rejectOnce => l10n.aiPermRejectOnce,
      PermissionKind.rejectAlways => l10n.aiPermRejectAlways,
      PermissionKind.other => option.name,
    };

/// [path] relative to the session folder [cwd] when it is inside it.
String aiRelativePath(String path, String cwd) {
  final root = cwd.endsWith('/') || cwd.endsWith(r'\') ? cwd : '$cwd/';
  if (path.startsWith(root)) return path.substring(root.length);
  final win = root.replaceAll('/', r'\');
  return path.startsWith(win) ? path.substring(win.length) : path;
}

/// "0:41" (spec §4.2 turn summary, the header clock).
String aiClock(Duration d) {
  final s = d.inSeconds;
  final m = s ~/ 60;
  return m >= 60
      ? '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}'
      : '$m:${(s % 60).toString().padLeft(2, '0')}';
}

/// "2,1" / "2.1" seconds, in the language's decimal mark.
String aiSeconds(Duration d, String localeName) {
  final tenths = (d.inMilliseconds / 100).round();
  final text = '${tenths ~/ 10}.${tenths % 10}';
  return localeName.startsWith('vi') ? text.replaceAll('.', ',') : text;
}
```

`apps/desktop/lib/src/ui/ai/ai_diff_view.dart`:

```dart
import 'package:flutter/material.dart';

import '../../ai/line_diff.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_theme.dart';

/// A line diff (D17): removed lines on `err`, added on `ok`, the gaps as
/// "⋯". Smoothness: past 40 rows it is a fixed-height virtualized list.
class AiDiffView extends StatelessWidget {
  const AiDiffView({super.key, required this.lines, this.height = 360});

  /// From [withContext] (null: lines left out) or a whole diff.
  final List<DiffLine?> lines;
  final double height;

  static const double _row = 17;

  @override
  Widget build(BuildContext context) {
    Widget row(int i) => _Row(line: lines[i]);
    final body = lines.length <= 40
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (var i = 0; i < lines.length; i++) row(i)],
          )
        : SizedBox(
            height: height,
            child: ListView.builder(
              itemExtent: _row,
              itemCount: lines.length,
              itemBuilder: (context, i) => row(i),
            ),
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ShellxDesktopColors.surfaceInset,
        borderRadius: BorderRadius.circular(ShellxRadius.r6),
        border: Border.all(color: ShellxDesktopColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ShellxRadius.r6),
        child: body,
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.line});
  final DiffLine? line;

  @override
  Widget build(BuildContext context) {
    final l = line;
    if (l == null) {
      return const SizedBox(
        height: AiDiffView._row,
        child: Center(
          child: Text(
            '⋯',
            style: TextStyle(color: ShellxDesktopColors.dim, fontSize: 11),
          ),
        ),
      );
    }
    final (bg, mark, color) = switch (l.op) {
      DiffOp.added => (
        ShellxDesktopColors.ok.withValues(alpha: 0.12),
        '+',
        ShellxDesktopColors.ok,
      ),
      DiffOp.removed => (
        ShellxDesktopColors.err.withValues(alpha: 0.12),
        '−',
        ShellxDesktopColors.err,
      ),
      DiffOp.same => (
        Colors.transparent,
        ' ',
        ShellxDesktopColors.textSecondary,
      ),
    };
    final no = '${l.newNo ?? l.oldNo ?? ''}'.padLeft(4);
    return Container(
      height: AiDiffView._row,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s6),
      child: Text(
        '$no $mark ${l.text}',
        maxLines: 1,
        overflow: TextOverflow.clip,
        softWrap: false,
        style: kAiMono.copyWith(
          color: l.op == DiffOp.same ? ShellxDesktopColors.textPrimary : color,
        ),
      ),
    );
  }
}
```

`apps/desktop/lib/src/ui/ai/ai_tool_card.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/desktop_services.dart';
import '../../ai/ai_off_thread.dart';
import '../../ai/line_diff.dart';
import '../../config/config_controller.dart' show shellxConfigProvider;
import '../../platform/editor_links.dart';
import '../terminal/link_layer.dart' show editorDetectorProvider;
import '../theme/shellx_desktop_theme.dart';
import 'ai_diff_view.dart';
import 'ai_labels.dart';
import 'ai_scope.dart';
import 'ai_theme.dart';

/// What a tool card's header says (spec §4.2): a verb, its target, and
/// whether the target reads as code. The title is the merged one (V2-1a:
/// updates refine the generic first title).
({String verb, String target, bool mono}) aiToolLabel(
  AppLocalizations l10n,
  ToolItem item,
  String cwd,
) {
  final f = item.fields;
  final title = f.title ?? '';
  final diff = f.content?.whereType<ToolDiff>().firstOrNull;
  final loc = f.locations?.firstOrNull?.path;
  String rel(String? path) => path == null ? title : aiRelativePath(path, cwd);
  return switch (f.kind) {
    ToolKind.read => (verb: l10n.aiToolRead, target: rel(loc), mono: true),
    ToolKind.edit => (
      verb: diff != null && diff.oldText == null
          ? l10n.aiToolCreate
          : l10n.aiToolEdit,
      target: rel(diff?.path ?? loc),
      mono: true,
    ),
    ToolKind.delete => (verb: l10n.aiToolDelete, target: rel(loc), mono: true),
    ToolKind.move => (verb: l10n.aiToolMove, target: rel(loc), mono: true),
    ToolKind.search => (verb: l10n.aiToolSearch, target: title, mono: true),
    ToolKind.execute => (verb: l10n.aiToolExecute, target: title, mono: true),
    ToolKind.fetch => (verb: l10n.aiToolFetch, target: title, mono: false),
    ToolKind.think => (verb: l10n.aiThinking, target: title, mono: false),
    ToolKind.switchMode => (
      verb: '',
      target: l10n.aiToolModeChanged(title),
      mono: false,
    ),
    ToolKind.other || null => _mcp(title),
  };
}

/// `mcp__server__tool` reads "server · tool".
({String verb, String target, bool mono}) _mcp(String title) {
  final m = RegExp(r'^mcp__(.+?)__(.+)$').firstMatch(title);
  return m == null
      ? (verb: '', target: title, mono: false)
      : (verb: '', target: '${m[1]} · ${m[2]}', mono: true);
}

IconData _icon(ToolKind? kind) => switch (kind) {
  ToolKind.read => Icons.description_outlined,
  ToolKind.edit => Icons.edit_outlined,
  ToolKind.delete => Icons.delete_outline,
  ToolKind.move => Icons.drive_file_rename_outline,
  ToolKind.search => Icons.search,
  ToolKind.execute => Icons.terminal,
  ToolKind.fetch => Icons.cloud_download_outlined,
  ToolKind.think => Icons.psychology_outlined,
  ToolKind.switchMode => Icons.swap_horiz,
  ToolKind.other || null => Icons.extension_outlined,
};

/// One tool call (spec §4.2, D10 notes under it). Smoothness: its body is
/// built only when open; long output shows its first and last
/// [AiSizes.outputLines] lines; a long diff runs off the UI isolate.
class AiToolCard extends ConsumerStatefulWidget {
  const AiToolCard({super.key, required this.item});
  final ToolItem item;

  @override
  ConsumerState<AiToolCard> createState() => _AiToolCardState();
}

class _AiToolCardState extends ConsumerState<AiToolCard> {
  /// Null: the automatic rule ([_autoOpen]).
  bool? _open;
  ToolDiff? _diffOf;
  List<DiffLine>? _diff;

  ToolItem get item => widget.item;

  bool get _expandable => switch (item.fields.kind) {
    ToolKind.read || ToolKind.switchMode => false,
    _ => true,
  };

  /// Spec §4.2: an edit waiting for an answer, and a command that
  /// finished, open by themselves.
  bool get _autoOpen =>
      (item.awaitingPermission && item.fields.kind == ToolKind.edit) ||
      (item.fields.kind == ToolKind.execute && item.end == ToolEnd.completed);

  bool get _isOpen => _expandable && (_open ?? _autoOpen);

  void _ensureDiff() {
    final d = item.fields.content?.whereType<ToolDiff>().firstOrNull;
    if (d == null || identical(d, _diffOf)) return;
    _diffOf = d;
    _diff = null;
    final pending = lineDiff(
      ref.read(aiOffThreadProvider),
      d.oldText ?? '',
      d.newText,
    );
    if (pending is SynchronousFuture<List<DiffLine>>) {
      unawaited(pending.then((lines) => _diff = lines));
    } else {
      unawaited(
        pending.then((lines) {
          if (mounted && identical(_diffOf, d)) setState(() => _diff = lines);
        }),
      );
    }
  }

  Future<void> _openInEditor(String path, String cwd) async {
    final abs = p.isAbsolute(path) ? path : p.join(cwd, path);
    final opener = ref.read(desktopServicesProvider).urlOpener;
    try {
      final editor = await editorFor(
        ref.read(shellxConfigProvider).config.linkEditor,
        ref.read(editorDetectorProvider),
      );
      if (editor != null) {
        await opener.openInEditor(editor, abs);
      } else {
        await opener.reveal(abs, isDirectory: false);
      }
    } on Object catch (error) {
      debugPrint('ShellX: editor not opened: ${error.runtimeType}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = AiPaneScope.of(context).state;
    _ensureDiff();
    final label = aiToolLabel(l10n, item, state.cwd);
    if (item.fields.kind == ToolKind.switchMode) {
      return Text(
        label.target,
        style: ShellxText.small.copyWith(
          color: ShellxDesktopColors.textSecondary,
        ),
      );
    }
    final diff = _diff;
    final stat = diff == null ? null : diffStat(diff);
    final asking = item.awaitingPermission;
    final header = InkWell(
      onTap: _expandable ? () => setState(() => _open = !_isOpen) : null,
      borderRadius: BorderRadius.circular(ShellxRadius.r8),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ShellxSpace.s8,
          vertical: ShellxSpace.s6,
        ),
        child: Row(
          children: [
            Icon(
              _icon(item.fields.kind),
              size: 14,
              color: ShellxDesktopColors.textSecondary,
            ),
            const SizedBox(width: ShellxSpace.s6),
            if (label.verb.isNotEmpty) ...[
              Text(
                label.verb,
                style: ShellxText.bodyStrong.copyWith(
                  color: ShellxDesktopColors.textPrimary,
                ),
              ),
              const SizedBox(width: ShellxSpace.s6),
            ],
            Expanded(
              child: Text(
                label.target,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: label.mono
                    ? kAiMono
                    : ShellxText.body.copyWith(
                        color: ShellxDesktopColors.textPrimary,
                      ),
              ),
            ),
            if (stat != null) ...[
              Text(
                '+${stat.added}',
                style: kAiMono.copyWith(color: ShellxDesktopColors.ok),
              ),
              const SizedBox(width: ShellxSpace.s4),
              Text(
                '−${stat.removed}',
                style: kAiMono.copyWith(color: ShellxDesktopColors.err),
              ),
              const SizedBox(width: ShellxSpace.s8),
            ],
            _Status(item: item),
            if (_expandable)
              Icon(
                _isOpen ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: ShellxDesktopColors.textSecondary,
              ),
          ],
        ),
      ),
    );
    final note = _permissionNote(l10n, state);
    return Container(
      decoration: BoxDecoration(
        color: ShellxDesktopColors.surface,
        borderRadius: BorderRadius.circular(ShellxRadius.r8),
        border: Border.all(
          color: asking
              ? ShellxDesktopColors.warnBorder
              : ShellxDesktopColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (_isOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ShellxSpace.s8,
                0,
                ShellxSpace.s8,
                ShellxSpace.s8,
              ),
              child: _body(l10n, state.cwd),
            ),
          ?note,
        ],
      ),
    );
  }

  Widget _body(AppLocalizations l10n, String cwd) {
    final f = item.fields;
    final d = _diffOf;
    final output = [
      for (final c in f.content ?? const <ToolContent>[])
        if (c case ToolContentBlock(block: TextBlock(:final text))) text,
    ].join('\n');
    final parts = <Widget>[];
    if (d != null) {
      final diff = _diff;
      parts.add(
        diff == null
            ? const SizedBox(height: 17)
            : AiDiffView(lines: withContext(diff)),
      );
      parts.add(
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('ai.tool.editor'),
            onPressed: () => unawaited(_openInEditor(d.path, cwd)),
            icon: const Icon(Icons.open_in_new, size: 14),
            label: Text(l10n.aiOpenInEditor),
          ),
        ),
      );
    }
    if (f.kind == ToolKind.other && f.rawInput != null) {
      parts
        ..add(_Caption(l10n.aiToolInput))
        ..add(
          _Output(text: const JsonEncoder.withIndent('  ').convert(f.rawInput)),
        );
      if (output.isNotEmpty) parts.add(_Caption(l10n.aiToolResult));
    }
    if (output.isNotEmpty && d == null) {
      parts.add(_Output(text: output));
    } else if (f.kind == ToolKind.execute && item.end != null) {
      parts.add(
        Text(
          l10n.aiToolNoOutput,
          style: ShellxText.small.copyWith(
            color: ShellxDesktopColors.textSecondary,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: parts,
    );
  }

  /// D10 under the card: how to answer, or what was chosen.
  Widget? _permissionNote(AppLocalizations l10n, AiSessionState state) {
    Widget note(IconData icon, Color color, String text) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ShellxSpace.s8,
        vertical: ShellxSpace.s6,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: ShellxDesktopColors.line)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: ShellxSpace.s6),
          Expanded(
            child: Text(text, style: ShellxText.small.copyWith(color: color)),
          ),
        ],
      ),
    );
    if (item.awaitingPermission) {
      final n =
          state.permissions
              .where((p) => identical(p.item, item))
              .firstOrNull
              ?.request
              .options
              .length ??
          0;
      return note(
        Icons.warning_amber_rounded,
        ShellxDesktopColors.warn,
        l10n.aiPermWaiting(n),
      );
    }
    final answer = item.permissionAnswer;
    if (answer != null) {
      final no = answer.kind.isReject;
      return note(
        no ? Icons.close : Icons.check,
        no ? ShellxDesktopColors.err : ShellxDesktopColors.ok,
        l10n.aiPermChosen(aiPermissionLabel(l10n, answer), answer.name),
      );
    }
    if (item.permissionCancelled) {
      return note(
        Icons.stop_circle_outlined,
        ShellxDesktopColors.textSecondary,
        l10n.aiPermCancelled,
      );
    }
    return null;
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: ShellxSpace.s6, bottom: ShellxSpace.s4),
    child: Text(
      text,
      style: ShellxText.caption.copyWith(
        color: ShellxDesktopColors.textSecondary,
      ),
    ),
  );
}

/// The card's status (spec §4.2): text, never a looping animation.
class _Status extends StatelessWidget {
  const _Status({required this.item});
  final ToolItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget text(String s, Color c) => Text(
      s,
      key: const Key('ai.tool.status'),
      style: ShellxText.caption.copyWith(color: c),
    );
    if (item.awaitingPermission) {
      return text(l10n.aiToolAwaiting, ShellxDesktopColors.warn);
    }
    switch (item.end) {
      case ToolEnd.completed:
        final ended = item.endedAt;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check,
              size: 14,
              color: ShellxDesktopColors.ok,
              semanticLabel: l10n.aiToolDone,
            ),
            if (item.fields.kind == ToolKind.execute && ended != null)
              text(
                l10n.aiToolTook(
                  aiSeconds(ended.difference(item.startedAt), l10n.localeName),
                ),
                ShellxDesktopColors.textSecondary,
              ),
          ],
        );
      case ToolEnd.failed:
        final rejected = item.permissionAnswer?.kind.isReject ?? false;
        return text(
          rejected ? l10n.aiToolRejected : l10n.aiToolFailed,
          ShellxDesktopColors.err,
        );
      case ToolEnd.stopped:
        return text(l10n.aiToolStopped, ShellxDesktopColors.textSecondary);
      case null:
        return item.fields.status == ToolCallStatus.inProgress
            ? _Running(item: item)
            : text(l10n.aiToolPending, ShellxDesktopColors.textSecondary);
    }
  }
}

/// "● running · 2.1 s": text that changes once a second, no animation.
class _Running extends StatefulWidget {
  const _Running({required this.item});
  final ToolItem item;

  @override
  State<_Running> createState() => _RunningState();
}

class _RunningState extends State<_Running> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final took = DateTime.now().difference(widget.item.startedAt);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.circle, size: 6, color: ShellxDesktopColors.accent),
        const SizedBox(width: ShellxSpace.s4),
        Text(
          l10n.aiToolRunning(aiSeconds(took, l10n.localeName)),
          key: const Key('ai.tool.status'),
          style: ShellxText.caption.copyWith(color: ShellxDesktopColors.accent),
        ),
      ],
    );
  }
}

/// Tool output: the first and last [AiSizes.outputLines] lines, "Show all"
/// for the rest (smoothness: never thousands of rows at once).
class _Output extends StatefulWidget {
  const _Output({required this.text});
  final String text;

  @override
  State<_Output> createState() => _OutputState();
}

class _OutputState extends State<_Output> {
  var _all = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lines = widget.text.split('\n');
    const n = AiSizes.outputLines;
    const box = BoxDecoration(
      color: ShellxDesktopColors.surfaceInset,
      borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r6)),
    );
    if (_all) {
      return Container(
        height: 360,
        decoration: box,
        padding: const EdgeInsets.all(ShellxSpace.s6),
        child: ListView.builder(
          itemExtent: 17,
          itemCount: lines.length,
          itemBuilder: (context, i) => Text(
            lines[i],
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: kAiMono,
          ),
        ),
      );
    }
    final cut = lines.length > 2 * n;
    Widget block(Iterable<String> ls) =>
        SelectableText(ls.join('\n'), style: kAiMono);
    return Container(
      decoration: box,
      padding: const EdgeInsets.all(ShellxSpace.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          block(cut ? lines.take(n) : lines),
          if (cut) ...[
            Row(
              children: [
                Text(
                  l10n.aiOutputCut(lines.length - 2 * n),
                  style: ShellxText.caption.copyWith(
                    color: ShellxDesktopColors.textSecondary,
                  ),
                ),
                const SizedBox(width: ShellxSpace.s8),
                TextButton(
                  key: const Key('ai.tool.showAll'),
                  onPressed: () => setState(() => _all = true),
                  child: Text(l10n.aiShowAllLines(lines.length)),
                ),
              ],
            ),
            block(lines.skip(lines.length - n)),
          ],
        ],
      ),
    );
  }
}
```

In `apps/desktop/lib/src/ui/ai/ai_timeline.dart`, replace:

```dart
import 'ai_theme.dart';
```

with:

```dart
import 'ai_theme.dart';
import 'ai_tool_card.dart';
```

In `apps/desktop/lib/src/ui/ai/ai_timeline.dart`, replace:

```dart
  ToolItem() => _PlainLine(text: item.fields.title ?? ''),
```

with:

```dart
  ToolItem() => AiToolCard(item: item),
```

- [ ] **Step 4: Run the tests**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/ai lib/src/ui/ai test/ai test/ui/ai
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ai/line_diff_test.dart test/ui/ai 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `All tests passed!` (13 on the scratch copy); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/ai/line_diff.dart apps/desktop/lib/src/ui/ai/ai_labels.dart apps/desktop/lib/src/ui/ai/ai_diff_view.dart apps/desktop/lib/src/ui/ai/ai_tool_card.dart apps/desktop/lib/src/ui/ai/ai_timeline.dart apps/desktop/test/ai/line_diff_test.dart apps/desktop/test/ui/ai/ai_tool_card_test.dart
git commit -m "feat(v2-ai): tool cards per kind with diffs, capped output and permission notes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 14: Notice cards, turn summaries, the agent log [needs V2-1a Task 9]

**Notice cards** (spec §4.5, §6). Each notice the runtime adds becomes a card with what can be done about it:
- **Sign-in (D8):** one button per `authMethods` entry, named by the agent. A terminal method asks the pane for the run sheet (`AiPaneUi.onRun`, Task 18). An agent method calls `authenticate`. No method is hidden (D21).
- **Missing Node:** "Installation guide", which opens nodejs.org (https only).
- **Not installed:** "Install", through the run sheet.
- **Command not found:** with the `.cmd`/`.bat` shim note (V2-1a never runs shims).
- **Stopped unexpectedly, or unreadable output:** "Restart" and "View log".
- **Could not start:** "Try again" and "View log".
- **Cannot resume, folder gone ("Choose folder"), undo off:** with its reason.

A notice whose problem went away folds to one dim line.

**Turn summaries** (spec §4.2):
- "Turn N · 0:41 · 2 files changed +44 −5 · View · Revert turn";
- "Stopped turn N…", "Turn N was interrupted…", "Turn N failed…", with the agent's error shown, never logged.

"View" opens the side panel. "Revert turn" calls the pane's `onRevertTurn` (Task 20).

**Files:**
- Create: `apps/desktop/lib/src/ui/ai/ai_log_dialog.dart`, `ai_notice_card.dart`, `ai_turn_summary.dart`
- Modify: `apps/desktop/lib/src/ui/ai/ai_scope.dart`, `ai_timeline.dart`
- Test: `apps/desktop/test/ui/ai/ai_notice_card_test.dart`

**Interfaces:**
- Consumes: Task 12/13 (`AiPaneScope`, `AiPaneUi`, `aiClock`), V2-1a notices (`LoginNeeded`, `NodeMissing`, `AgentNotInstalled`, `AgentMissing`, `AgentExited`, `AgentOutputInvalid`, `StartFailed`, `CannotResume`, `FolderMissing`, `UndoUnavailable`, `UndoOff`), `AiRuntime.restart/retry/authenticate/stderrTail`, `TurnEndItem`, `FileChange`.
- Produces:
  - `sealed class AiRunRequest` with `AiRunLogin(AuthMethodTerminal method)` and `AiRunInstall()`.
  - `AiPaneUi.onRun`, `.onChooseFolder`, `.onRevertTurn`.
  - `Future<void> showAiLogDialog(BuildContext, AiRuntime)`.
  - `kNodeDownloadPage`; `String aiUndoReason(AppLocalizations, UndoOff)`; `class AiNoticeCard`; `class AiTurnSummary`.
  - The string `aiTurnDone` ("Turn {n} · {time}"; Task 2 carries it).

- [ ] **Step 1: Write the failing test**

`apps/desktop/test/ui/ai/ai_notice_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ui/ai/ai_notice_card.dart';
import 'package:shellx_desktop/src/ui/ai/ai_scope.dart';
import 'package:shellx_desktop/src/ui/ai/ai_timeline.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';

void main() {
  final at = DateTime(2026, 10, 14, 9);

  testWidgets('sign-in: one button per method; a terminal one asks for the '
      'run sheet (D8)', (t) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    runtime.state.addNotice(
      const LoginNeeded([
        AuthMethodTerminal(id: 'claude-login', name: 'Log in with Claude'),
        AuthMethodAgent(id: 'api', name: 'Use an API key'),
      ]),
    );
    final w = await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    final asked = <AiRunRequest>[];
    w.ui.onRun = asked.add;
    await t.pump();
    expect(find.text('Claude needs you to sign in'), findsOneWidget);
    expect(find.text('Use an API key'), findsOneWidget);
    await t.tap(find.text('Log in with Claude'));
    expect((asked.single as AiRunLogin).method.id, 'claude-login');
  });

  testWidgets('the others of §4.5: Node, install, exit, resume, folder, undo', (
    t,
  ) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    runtime.state
      ..addNotice(const NodeMissing(required: 22, found: 'v20.1.0'))
      ..addNotice(const AgentNotInstalled())
      ..addNotice(const AgentExited(1))
      ..addNotice(const CannotResume())
      ..addNotice(const FolderMissing())
      ..addNotice(const UndoUnavailable(UndoOff.tooManyFiles))
      ..addNotice(const AgentMissing('opencode', shimOnly: true));
    final w = await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    final asked = <AiRunRequest>[];
    var folder = 0;
    w.ui
      ..onRun = asked.add
      ..onChooseFolder = () => folder++;
    await t.pump();
    expect(find.text('Claude needs Node.js 22 or newer'), findsOneWidget);
    expect(find.text('Claude is not installed'), findsOneWidget);
    expect(find.text('Claude stopped unexpectedly (exit 1)'), findsOneWidget);
    expect(find.textContaining('cannot restore'), findsOneWidget);
    expect(find.text('The project folder no longer exists'), findsOneWidget);
    expect(
      find.text('Undo is off for this project (more than 200,000 files)'),
      findsOneWidget,
    );
    expect(find.textContaining('.cmd or .bat'), findsOneWidget);
    await t.tap(find.byKey(const Key('ai.node.guide')));
    await t.tap(find.byKey(const Key('ai.install')));
    await t.tap(find.byKey(const Key('ai.chooseFolder')));
    await t.pump();
    expect(w.harness.urlOpener.opened.single, kNodeDownloadPage);
    expect(asked.single, isA<AiRunInstall>());
    expect(folder, 1);
    await t.tap(find.byKey(const Key('ai.log')));
    await t.pumpAndSettle();
    expect(find.text('(empty)'), findsOneWidget);
  });

  testWidgets('turn summaries: changes, stopped, interrupted (spec §4.2)', (
    t,
  ) async {
    final runtime = partRuntime(FakeAiRuntimes(const FakeScenario()));
    final s = runtime.state;
    s.beginTurn([const TextBlock('one')], at);
    s.endTurn(
      outcome: TurnOutcome.finished,
      at: at.add(const Duration(seconds: 41)),
      changes: const [
        FileChange(
          path: 'a.ts',
          kind: ChangeKind.modified,
          added: 40,
          removed: 5,
        ),
        FileChange(path: 'b.ts', kind: ChangeKind.added, added: 4, removed: 0),
      ],
    );
    s.beginTurn([const TextBlock('two')], at);
    s.endTurn(
      outcome: TurnOutcome.cancelled,
      at: at.add(const Duration(seconds: 5)),
    );
    s.beginTurn([const TextBlock('three')], at);
    s.endTurn(
      outcome: TurnOutcome.interrupted,
      at: at.add(const Duration(seconds: 2)),
    );
    final w = await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await t.pump();
    expect(find.text('Turn 1 · 0:41 · 2 files changed'), findsOneWidget);
    expect(find.text('+44'), findsOneWidget);
    expect(find.text('−5'), findsOneWidget);
    expect(find.text('Stopped turn 2 · 0:05'), findsOneWidget);
    expect(find.text('Turn 3 was interrupted · 0:02'), findsOneWidget);
    await t.tap(find.byKey(const Key('ai.turn.view')));
    expect(w.ui.panelOpen, isTrue);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai/ai_notice_card_test.dart`
Expected: the test does not compile, `Error when reading 'lib/src/ui/ai/ai_notice_card.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/ui/ai/ai_log_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shellx_ai/host.dart';

import '../../../l10n/app_localizations.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_theme.dart';

/// "View log" (D20): the agent's stderr, kept in memory only (the last
/// 256 KiB). Shown, never logged.
Future<void> showAiLogDialog(BuildContext context, AiRuntime runtime) {
  final l10n = AppLocalizations.of(context);
  final text = runtime.stderrTail;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.aiLogTitle),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.aiLogNote,
              style: ShellxText.small.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
            const SizedBox(height: ShellxSpace.s8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: SingleChildScrollView(
                child: SelectableText(
                  text.isEmpty ? l10n.aiLogEmpty : text,
                  key: const Key('ai.log.text'),
                  style: kAiMono,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionClose),
        ),
      ],
    ),
  );
}
```

`apps/desktop/lib/src/ui/ai/ai_notice_card.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/desktop_services.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_log_dialog.dart';
import 'ai_scope.dart';

/// Node's download page ("Installation guide", spec §4.5).
final Uri kNodeDownloadPage = Uri.parse('https://nodejs.org/en/download');

/// The reason undo is off, in words (`aiNoUndo`, spec §6).
String aiUndoReason(AppLocalizations l10n, UndoOff reason) => switch (reason) {
  UndoOff.noGit => l10n.aiUndoNoGit,
  UndoOff.noCommandLineTools => l10n.aiUndoNoCommandLineTools,
  UndoOff.gitTooOld => l10n.aiUndoGitTooOld,
  UndoOff.tooManyFiles => l10n.aiUndoTooManyFiles,
  UndoOff.tooSlow => l10n.aiUndoTooSlow,
  UndoOff.failed => l10n.aiUndoFailed,
};

/// A notice in the conversation (spec §4.5, §6) with what can be done
/// about it. A notice whose problem went away folds to one dim line.
class AiNoticeCard extends ConsumerWidget {
  const AiNoticeCard({super.key, required this.item});
  final NoticeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scope = AiPaneScope.of(context);
    final runtime = scope.runtime;
    final agent = scope.state.agentName;
    void log() => unawaited(showAiLogDialog(context, runtime));
    Widget button(String label, VoidCallback onPressed, {Key? key}) =>
        OutlinedButton(key: key, onPressed: onPressed, child: Text(label));
    final (
      IconData icon,
      Color color,
      String text,
      List<Widget> actions,
    ) = switch (item.notice) {
      LoginNeeded(:final methods) => (
        Icons.key_outlined,
        ShellxDesktopColors.warn,
        l10n.aiLoginNeeded(agent),
        [
          for (final m in methods)
            switch (m) {
              AuthMethodTerminal() => button(
                m.name,
                () => scope.ui.onRun?.call(AiRunLogin(m)),
                key: ValueKey('ai.login.${m.id}'),
              ),
              AuthMethodAgent() => button(
                m.name,
                () => unawaited(runtime.authenticate(m.id)),
                key: ValueKey('ai.login.${m.id}'),
              ),
              AuthMethodOther() => Text(m.name),
            },
        ],
      ),
      NodeMissing(:final required) => (
        Icons.info_outline,
        ShellxDesktopColors.warn,
        l10n.aiNodeMissing(agent, required),
        [
          button(l10n.aiNodeGuide, () {
            unawaited(
              ref
                  .read(desktopServicesProvider)
                  .urlOpener
                  .open(kNodeDownloadPage)
                  .catchError((Object e) {
                    debugPrint('ShellX: page not opened: ${e.runtimeType}');
                  }),
            );
          }, key: const Key('ai.node.guide')),
        ],
      ),
      AgentNotInstalled(:final canInstall) => (
        Icons.download_outlined,
        ShellxDesktopColors.warn,
        canInstall
            ? l10n.aiNotInstalled(agent)
            : '${l10n.aiNotInstalled(agent)}. ${l10n.aiNoNpm}',
        [
          if (canInstall)
            button(
              l10n.aiInstall,
              () => scope.ui.onRun?.call(const AiRunInstall()),
              key: const Key('ai.install'),
            ),
        ],
      ),
      AgentMissing(:final command, :final shimOnly) => (
        Icons.search_off,
        ShellxDesktopColors.err,
        shimOnly
            ? '${l10n.aiCommandMissing(command)}. ${l10n.aiCommandShimOnly}'
            : l10n.aiCommandMissing(command),
        const <Widget>[],
      ),
      AgentExited(:final exitCode) => (
        Icons.error_outline,
        ShellxDesktopColors.err,
        l10n.aiAgentExited(agent, exitCode),
        [
          button(
            l10n.aiRestart,
            () => unawaited(runtime.restart()),
            key: const Key('ai.restart'),
          ),
          button(l10n.aiMenuViewLog, log, key: const Key('ai.log')),
        ],
      ),
      AgentOutputInvalid() => (
        Icons.error_outline,
        ShellxDesktopColors.err,
        l10n.aiAgentOutputInvalid(agent),
        [
          button(
            l10n.aiRestart,
            () => unawaited(runtime.restart()),
            key: const Key('ai.restart'),
          ),
          button(l10n.aiMenuViewLog, log, key: const Key('ai.log')),
        ],
      ),
      StartFailed() => (
        Icons.error_outline,
        ShellxDesktopColors.err,
        l10n.aiStartFailed(agent),
        [
          button(
            l10n.aiRetry,
            () => unawaited(runtime.retry()),
            key: const Key('ai.retry'),
          ),
          button(l10n.aiMenuViewLog, log, key: const Key('ai.log')),
        ],
      ),
      CannotResume() => (
        Icons.history,
        ShellxDesktopColors.textSecondary,
        l10n.aiCannotResume,
        const <Widget>[],
      ),
      FolderMissing() => (
        Icons.folder_off_outlined,
        ShellxDesktopColors.err,
        l10n.aiFolderMissing,
        [
          button(
            l10n.aiChooseFolder,
            () => scope.ui.onChooseFolder?.call(),
            key: const Key('ai.chooseFolder'),
          ),
        ],
      ),
      UndoUnavailable(:final reason, :final turnOnly) => (
        Icons.undo,
        ShellxDesktopColors.textSecondary,
        turnOnly
            ? l10n.aiNoUndoTurn(aiUndoReason(l10n, reason))
            : l10n.aiNoUndo(aiUndoReason(l10n, reason)),
        const <Widget>[],
      ),
    };
    if (item.resolved) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: ShellxText.small.copyWith(color: ShellxDesktopColors.dim),
      );
    }
    final warn = color == ShellxDesktopColors.warn;
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(ShellxSpace.s12),
        decoration: BoxDecoration(
          color: warn
              ? ShellxDesktopColors.warnBg
              : ShellxDesktopColors.surface,
          borderRadius: BorderRadius.circular(ShellxRadius.r8),
          border: Border.all(
            color: warn
                ? ShellxDesktopColors.warnBorder
                : ShellxDesktopColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: ShellxSpace.s8),
                Expanded(
                  child: Text(
                    text,
                    style: ShellxText.body.copyWith(
                      color: ShellxDesktopColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: ShellxSpace.s8),
              Wrap(
                spacing: ShellxSpace.s8,
                runSpacing: ShellxSpace.s6,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

`apps/desktop/lib/src/ui/ai/ai_turn_summary.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../../l10n/app_localizations.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_labels.dart';
import 'ai_scope.dart';

/// The end of a turn (spec §4.2): "Turn N · 0:41 · 2 files changed +44 −5 ·
/// View · Revert turn", or "Stopped turn N…", "Turn N was interrupted…".
/// "View" and "Revert turn" are the Changes panel's (Task 20).
class AiTurnSummary extends StatelessWidget {
  const AiTurnSummary({super.key, required this.item});
  final TurnEndItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ui = AiPaneScope.of(context).ui;
    final time = aiClock(item.elapsed);
    final n = item.turn;
    final changes = item.changes;
    final head = switch (item.outcome) {
      TurnOutcome.finished =>
        changes == null || changes.isEmpty
            ? l10n.aiTurnDone(n, time)
            : l10n.aiTurnSummary(n, time, changes.length),
      TurnOutcome.cancelled => l10n.aiTurnStopped(n, time),
      TurnOutcome.interrupted => l10n.aiTurnInterrupted(n, time),
      TurnOutcome.failed => l10n.aiTurnFailed(n, time),
    };
    final added = changes?.fold(0, (a, c) => a + (c.added ?? 0)) ?? 0;
    final removed = changes?.fold(0, (a, c) => a + (c.removed ?? 0)) ?? 0;
    final dim = ShellxText.small.copyWith(
      color: ShellxDesktopColors.textSecondary,
    );
    final stopped = item.outcome != TurnOutcome.finished;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ShellxSpace.s4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: ShellxSpace.s8,
        children: [
          Text(
            head,
            key: const Key('ai.turn.summary'),
            style: dim.copyWith(
              color: stopped ? ShellxDesktopColors.warn : null,
            ),
          ),
          if (changes != null && changes.isNotEmpty) ...[
            Text('+$added', style: dim.copyWith(color: ShellxDesktopColors.ok)),
            Text(
              '−$removed',
              style: dim.copyWith(color: ShellxDesktopColors.err),
            ),
            TextButton(
              key: const Key('ai.turn.view'),
              onPressed: ui.openPanel,
              child: Text(l10n.aiTurnView),
            ),
            if (item.checkpoint != null && ui.onRevertTurn != null)
              TextButton.icon(
                key: const Key('ai.turn.revert'),
                onPressed: () => ui.onRevertTurn?.call(n),
                icon: const Icon(Icons.undo, size: 14),
                label: Text(l10n.aiRevertTurn),
              ),
          ] else if (item.outcome == TurnOutcome.finished && changes != null)
            Text(l10n.aiTurnNoChanges, style: dim),
          if (item.error case final error?)
            Text(error, style: dim.copyWith(color: ShellxDesktopColors.err)),
        ],
      ),
    );
  }
}
```

In `apps/desktop/lib/src/ui/ai/ai_scope.dart`, replace:

```dart
import 'package:flutter/widgets.dart';
import 'package:shellx_ai/host.dart';
```

with:

```dart
import 'package:flutter/widgets.dart';
import 'package:shellx_acp/shellx_acp.dart' show AuthMethodTerminal;
import 'package:shellx_ai/host.dart';
```

In `apps/desktop/lib/src/ui/ai/ai_scope.dart`, replace:

```dart
  /// Text the composer inserts at its cursor, then clears.
  final insert = ValueNotifier<String?>(null);
```

with:

```dart
  /// Text the composer inserts at its cursor, then clears.
  final insert = ValueNotifier<String?>(null);

  /// Set by the pane: the run sheet (D8).
  void Function(AiRunRequest request)? onRun;

  /// Set by the pane: the folder card (D5, §6 "folder gone").
  void Function()? onChooseFolder;

  /// Set by the pane: "Revert turn" N (§4.4).
  void Function(int turn)? onRevertTurn;
```

In `apps/desktop/lib/src/ui/ai/ai_scope.dart`, replace:

```dart
/// The AI pane's own UI state, which its parts change: the overlay over the
```

with:

```dart
/// D8: what a card asks the run sheet to run.
sealed class AiRunRequest {
  const AiRunRequest();
}

/// One of the agent's terminal sign-in methods: its own command plus the
/// method's args and env. Nothing in it is ever read back.
final class AiRunLogin extends AiRunRequest {
  const AiRunLogin(this.method);
  final AuthMethodTerminal method;
}

/// The agent's pinned npm install (D6, D7).
final class AiRunInstall extends AiRunRequest {
  const AiRunInstall();
}

/// The AI pane's own UI state, which its parts change: the overlay over the
```

In `apps/desktop/lib/src/ui/ai/ai_timeline.dart`, replace:

```dart
import 'ai_markdown.dart';
```

with:

```dart
import 'ai_markdown.dart';
import 'ai_notice_card.dart';
```

In `apps/desktop/lib/src/ui/ai/ai_timeline.dart`, replace:

```dart
import 'ai_tool_card.dart';
```

with:

```dart
import 'ai_tool_card.dart';
import 'ai_turn_summary.dart';
```

In `apps/desktop/lib/src/ui/ai/ai_timeline.dart`, replace:

```dart
  TurnEndItem() => const SizedBox(height: ShellxSpace.s8),
  NoticeItem() => const SizedBox.shrink(),
```

with:

```dart
  TurnEndItem() => AiTurnSummary(item: item),
  NoticeItem() => AiNoticeCard(item: item),
```

- [ ] **Step 4: Run the tests**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/ui/ai test/ui/ai
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `All tests passed!` (12 on the scratch copy); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/ui/ai/ai_log_dialog.dart apps/desktop/lib/src/ui/ai/ai_notice_card.dart apps/desktop/lib/src/ui/ai/ai_turn_summary.dart apps/desktop/lib/src/ui/ai/ai_scope.dart apps/desktop/lib/src/ui/ai/ai_timeline.dart apps/desktop/test/ui/ai/ai_notice_card_test.dart
git commit -m "feat(v2-ai): notice cards (sign-in, Node, install, exit, folder, undo), turn summaries, agent log

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 15: The composer and the dock — send, queue, stop, force stop, plan [needs V2-1a Task 9]

D16, spec §1.4, §1.10, §4.1.

**The field:** `AiComposer` grows to 140 px.
- Enter sends; Shift+Enter is a new line.
- While the input method composes (Telex), Enter belongs to the input method.
- ⌘A/⌘C/⌘V/⌘X are the field's (`textEditingShortcuts`, as the palette does).

**Sending and stopping:**
- The prompt goes out at once: `send` starts the turn synchronously, so the user's message is in the next frame.
- During a turn, or while the agent starts, the button reads "Queue". Queued prompts show in the dock with a remove button, at most 5. A full queue or a refusal puts the text back with a note.
- Esc with no question open, or the Stop button: `cancel`. The button turns into "Stopping…" at once. After the 10 s grace, "Force stop" kills the agent; the next prompt restarts it with `session/load`.

**The dock** (`AiDock`): the plan (folds) and the queue above the composer, with a slot for the permission bar (Task 16). The composer also shows the context use ("Context 16%"), and inserts the text other parts ask for (`AiPaneUi.insert`, used by Task 25).

**Smoothness:**
- The composer rebuilds only when phase, turn, stop state or usage change. It never rebuilds per streamed chunk, so it never drops keystrokes.
- The plan and the queue listen per frame.

**Files:**
- Create: `apps/desktop/lib/src/ui/ai/ai_composer.dart`, `ai_dock.dart`
- Test: `apps/desktop/test/ui/ai/ai_composer_test.dart`

**Interfaces:**
- Consumes: Task 12 (`AiPaneScope`, `AiPaneUi.insert`, `AiSizes`), `textEditingShortcuts`, `destructiveButtonStyle`, V2-1a `AiRuntime.send/cancel/forceStop`, `AiSessionState` (`phase`, `turn.cancelRequested/canForceStop`, `queue`, `removeQueued`, `plan`, `usage.percent`, `maxQueue`).
- Produces:
  - `typedef AiKeyHook = bool Function(KeyEvent event, {required bool hasText})`;
  - `class AiComposer({FocusNode? focusNode, AiKeyHook? keyHook})`;
  - `class AiDock({FocusNode? focusNode, Widget? permissionBar, AiKeyHook? keyHook})`;
  - `class AiPlanBar`;
  - widget keys `ai.composer`, `ai.send`, `ai.stop`, `ai.forceStop`, `ai.context`, `ai.plan`.

- [ ] **Step 1: Write the failing test**

`apps/desktop/test/ui/ai/ai_composer_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ui/ai/ai_dock.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';

void main() {
  Future<(FakeAiRuntimes, AiRuntime)> ready(
    WidgetTester t,
    FakeScenario scenario,
  ) async {
    final fakes = FakeAiRuntimes(scenario);
    final runtime = partRuntime(fakes);
    await runtime.start();
    await pumpAiPart(t, const AiDock(), runtime: runtime);
    await t.tap(find.byKey(const Key('ai.composer')));
    await t.pump();
    return (fakes, runtime);
  }

  List<String> prompts(FakeAiRuntimes f) => [
    for (final r in f.agent().received)
      if (r.startsWith('session/prompt:')) r.substring(15),
  ];

  testWidgets('Enter sends; Shift+Enter and IME composing never do '
      '(D16, §1.10)', (t) async {
    final (fakes, runtime) = await ready(t, const FakeScenario());
    await t.enterText(find.byKey(const Key('ai.composer')), 'hello');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(prompts(fakes), ['hello']);
    expect(find.text('hello'), findsNothing, reason: 'the field is empty');
    await t.enterText(find.byKey(const Key('ai.composer')), 'two');
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump();
    t.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'tieng',
        composing: TextRange(start: 0, end: 5),
      ),
    );
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(prompts(fakes), ['hello']);
    await runtime.dispose();
  });

  testWidgets('during a turn: Queue, shown, then sent when the turn ends; '
      'Esc stops at once (D16, §1.4)', (t) async {
    final (fakes, runtime) = await ready(
      t,
      FakeScenario(
        turns: [
          [FakeSteps.waitCancel()],
          const [],
        ],
      ),
    );
    await t.enterText(find.byKey(const Key('ai.composer')), 'one');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(find.text('Stop  Esc'), findsOneWidget);
    await t.enterText(find.byKey(const Key('ai.composer')), 'two');
    await t.pump();
    expect(find.text('Queue  ⏎'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(
      find.text('Queued: “two” — sent when this turn ends'),
      findsOneWidget,
    );
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    await t.pump();
    expect(prompts(fakes), ['one', 'two']);
    await runtime.dispose();
  });

  testWidgets('a turn that ignores Stop: Stopping…, then Force stop after '
      '10 s (§1.4)', (t) async {
    final (fakes, runtime) = await ready(
      t,
      FakeScenario(
        turns: [
          [FakeSteps.hang()],
        ],
      ),
    );
    await t.enterText(find.byKey(const Key('ai.composer')), 'go');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(find.text('Stopping…'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
    await t.pump();
    expect(find.byKey(const Key('ai.forceStop')), findsOneWidget);
    await t.tap(find.byKey(const Key('ai.forceStop')));
    await t.pump();
    await t.pump();
    expect(fakes.launcher.channels.single.killCalls, 1);
    expect(runtime.state.turn, isNull);
    await runtime.dispose();
  });

  testWidgets('context use and the plan (spec §4.1)', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final runtime = partRuntime(fakes);
    final at = DateTime(2026, 10, 14);
    runtime.state
      ..applyUpdate(UsageUpdated(const Usage(used: 160000, size: 1000000)), at)
      ..applyUpdate(
        PlanUpdated(const [
          PlanEntry(content: 'Read the code', status: PlanStatus.completed),
          PlanEntry(content: 'Fix the bug', status: PlanStatus.inProgress),
          PlanEntry(content: 'Run the tests', status: PlanStatus.pending),
        ]),
        at,
      );
    await pumpAiPart(t, const AiDock(), runtime: runtime);
    await t.pump();
    expect(find.text('Context 16%'), findsOneWidget);
    expect(find.text('Plan · 1/3 done'), findsOneWidget);
    expect(find.text('Fix the bug'), findsNothing);
    await t.tap(find.byKey(const Key('ai.plan')));
    await t.pump();
    expect(find.text('Fix the bug'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai/ai_composer_test.dart`
Expected: the test does not compile, `Error when reading 'lib/src/ui/ai/ai_dock.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/ui/ai/ai_composer.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../../l10n/app_localizations.dart';
import '../text_editing_shortcuts.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_scope.dart';
import 'ai_theme.dart';

/// A key the composer offers to others first (the permission bar, D10):
/// [handled] true stops it there.
typedef AiKeyHook = bool Function(KeyEvent event, {required bool hasText});

/// What the composer's buttons and hint depend on: rebuilt only when this
/// changes, never per streamed chunk (smoothness: no dropped keystrokes).
typedef _View = ({
  AgentPhase phase,
  bool running,
  bool stopping,
  bool force,
  int? usage,
});

/// The composer (D16, spec §4.1): a field that grows to 140 px and, under
/// it, the context use and Send / Queue / Stop / Force stop.
/// - Enter sends; Shift+Enter is a new line; while the input method is
///   composing (Telex), Enter is the input method's (§1.10).
/// - Sending while a turn runs (or the agent starts) queues (at most 5).
/// - Esc with no question open stops the turn: "Stopping…" at once, "Force
///   stop" after 10 s (§1.4).
class AiComposer extends StatefulWidget {
  const AiComposer({super.key, this.focusNode, this.keyHook});

  /// The window's terminal focus while this pane is the focused one.
  final FocusNode? focusNode;

  /// Keys offered to the permission bar first (Task 16).
  final AiKeyHook? keyHook;

  @override
  State<AiComposer> createState() => _AiComposerState();
}

class _AiComposerState extends State<AiComposer> {
  final _text = TextEditingController();
  final _ownFocus = FocusNode(debugLabel: 'ai composer');
  AiPaneScope? _scope;
  _View? _view;
  String? _note;

  FocusNode get _focus => widget.focusNode ?? _ownFocus;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AiPaneScope.of(context);
    if (!identical(scope.frames, _scope?.frames)) {
      _scope?.frames.removeListener(_onFrame);
      _scope?.ui.insert.removeListener(_onInsert);
      scope.frames.addListener(_onFrame);
      scope.ui.insert.addListener(_onInsert);
    }
    _scope = scope;
    _view = _read(scope.state);
  }

  @override
  void dispose() {
    _scope?.frames.removeListener(_onFrame);
    _scope?.ui.insert.removeListener(_onInsert);
    _text.dispose();
    _ownFocus.dispose();
    super.dispose();
  }

  _View _read(AiSessionState s) => (
    phase: s.phase,
    running: s.turn != null,
    stopping: s.turn?.cancelRequested ?? false,
    force: s.turn?.canForceStop ?? false,
    usage: s.usage?.percent,
  );

  void _onFrame() {
    final next = _read(_scope!.state);
    if (next != _view) setState(() => _view = next);
  }

  /// Files › "Mention in chat" (D18): text at the cursor.
  void _onInsert() {
    final insert = _scope!.ui.insert;
    final add = insert.value;
    if (add == null) return;
    insert.value = null;
    final v = _text.value;
    final at = v.selection.isValid ? v.selection.start : v.text.length;
    final end = v.selection.isValid ? v.selection.end : v.text.length;
    _text.value = TextEditingValue(
      text: v.text.replaceRange(at, end, add),
      selection: TextSelection.collapsed(offset: at + add.length),
    );
    _focus.requestFocus();
  }

  bool get _canSend => switch (_view!.phase) {
    AgentPhase.needsAuth || AgentPhase.failed => false,
    _ => true,
  };

  Future<void> _send() async {
    final text = _text.text;
    if (text.trim().isEmpty || !_canSend) return;
    final scope = _scope!;
    final l10n = AppLocalizations.of(context);
    _text.clear();
    setState(() => _note = null);
    final ok = await scope.runtime.send([TextBlock(text.trim())]);
    if (ok || !mounted) return;
    _text.text = text;
    setState(
      () => _note = scope.state.queue.length >= AiSessionState.maxQueue
          ? l10n.aiQueueFull
          : l10n.aiCannotSend,
    );
  }

  void _stop() {
    final runtime = _scope!.runtime;
    final turn = runtime.state.turn;
    if (turn == null) return;
    if (turn.canForceStop) {
      unawaited(runtime.forceStop());
    } else {
      runtime.cancel();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    // §1.10: the input method's keys while it composes.
    if (_text.value.composing.isValid) return KeyEventResult.ignored;
    if (widget.keyHook?.call(event, hasText: _text.text.isNotEmpty) ?? false) {
      return KeyEventResult.handled;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        return KeyEventResult.ignored;
      }
      unawaited(_send());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && _view!.running) {
      _stop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scope = _scope!;
    final view = _view!;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        ShellxSpace.s16,
        ShellxSpace.s4,
        ShellxSpace.s16,
        ShellxSpace.s12,
      ),
      decoration: BoxDecoration(
        color: ShellxDesktopColors.surface,
        borderRadius: BorderRadius.circular(ShellxRadius.r8),
        border: Border.all(color: ShellxDesktopColors.borderInput),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: AiSizes.composerMax),
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _onKey,
              child: Shortcuts(
                shortcuts: textEditingShortcuts(),
                child: TextField(
                  key: const Key('ai.composer'),
                  controller: _text,
                  focusNode: _focus,
                  enabled: _canSend,
                  minLines: 2,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: ShellxText.body.copyWith(
                    color: ShellxDesktopColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: l10n.aiComposerHint(scope.state.agentName),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.all(ShellxSpace.s12),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ShellxSpace.s8,
              0,
              ShellxSpace.s8,
              ShellxSpace.s8,
            ),
            child: Row(
              children: [
                if (_note case final note?)
                  Expanded(
                    child: Text(
                      note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ShellxText.caption.copyWith(
                        color: ShellxDesktopColors.warn,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (view.usage case final percent?)
                  Padding(
                    padding: const EdgeInsets.only(right: ShellxSpace.s8),
                    child: Text(
                      l10n.aiContextUsed(percent),
                      key: const Key('ai.context'),
                      style: ShellxText.caption.copyWith(
                        color: ShellxDesktopColors.textSecondary,
                      ),
                    ),
                  ),
                _SendButton(
                  view: view,
                  hasText: _text,
                  onSend: () => unawaited(_send()),
                  onStop: _stop,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Send (⏎) / Queue (⏎) / Stop (Esc) / Stopping… / Force stop.
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.view,
    required this.hasText,
    required this.onSend,
    required this.onStop,
  });

  final _View view;
  final TextEditingController hasText;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: hasText,
      builder: (context, value, _) {
        final text = value.text.trim().isNotEmpty;
        if (view.running && !text) {
          if (view.force) {
            return FilledButton.icon(
              key: const Key('ai.forceStop'),
              style: destructiveButtonStyle(),
              onPressed: onStop,
              icon: const Icon(Icons.stop_circle_outlined, size: 16),
              label: Text(l10n.aiForceStop),
            );
          }
          return OutlinedButton.icon(
            key: const Key('ai.stop'),
            onPressed: view.stopping ? null : onStop,
            icon: const Icon(Icons.stop, size: 16),
            label: Text(
              view.stopping ? l10n.aiStopping : '${l10n.aiStop}  Esc',
            ),
          );
        }
        return FilledButton.icon(
          key: const Key('ai.send'),
          onPressed: text ? onSend : null,
          icon: const Icon(Icons.send, size: 16),
          label: Text('${view.running ? l10n.aiQueue : l10n.aiSend}  ⏎'),
        );
      },
    );
  }
}
```

`apps/desktop/lib/src/ui/ai/ai_dock.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shellx_acp/shellx_acp.dart';

import '../../../l10n/app_localizations.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_composer.dart';
import 'ai_scope.dart';
import 'ai_theme.dart';

/// The dock under the conversation (spec §4.1), top to bottom: the plan
/// (folds), the permission bar (Task 16), the queue, the composer.
class AiDock extends StatelessWidget {
  const AiDock({super.key, this.focusNode, this.permissionBar, this.keyHook});

  final FocusNode? focusNode;

  /// The permission bar (Task 16); null: none.
  final Widget? permissionBar;
  final AiKeyHook? keyHook;

  @override
  Widget build(BuildContext context) {
    final scope = AiPaneScope.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AiSizes.column),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListenableBuilder(
              listenable: scope.frames,
              builder: (context, _) {
                final s = scope.state;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (s.plan.isNotEmpty) AiPlanBar(entries: s.plan),
                    for (final q in s.queue)
                      _Queued(
                        text: q.text,
                        onRemove: () => s.removeQueued(q.id),
                      ),
                  ],
                );
              },
            ),
            ?permissionBar,
            AiComposer(focusNode: focusNode, keyHook: keyHook),
          ],
        ),
      ),
    );
  }
}

/// The agent's plan (`plan` updates): one line that folds open.
class AiPlanBar extends StatefulWidget {
  const AiPlanBar({super.key, required this.entries});
  final List<PlanEntry> entries;

  @override
  State<AiPlanBar> createState() => _AiPlanBarState();
}

class _AiPlanBarState extends State<AiPlanBar> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final done = widget.entries
        .where((e) => e.status == PlanStatus.completed)
        .length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            key: const Key('ai.plan'),
            onPressed: () => setState(() => _open = !_open),
            icon: Icon(_open ? Icons.expand_less : Icons.expand_more, size: 16),
            label: Text(l10n.aiPlan(done, widget.entries.length)),
          ),
          if (_open)
            for (final e in widget.entries)
              Padding(
                padding: const EdgeInsets.only(
                  left: ShellxSpace.s12,
                  bottom: ShellxSpace.s4,
                ),
                child: Row(
                  children: [
                    Icon(
                      switch (e.status) {
                        PlanStatus.completed => Icons.check,
                        PlanStatus.inProgress => Icons.circle,
                        PlanStatus.pending => Icons.circle_outlined,
                      },
                      size: 12,
                      color: e.status == PlanStatus.inProgress
                          ? ShellxDesktopColors.accent
                          : ShellxDesktopColors.textSecondary,
                    ),
                    const SizedBox(width: ShellxSpace.s6),
                    Expanded(
                      child: Text(
                        e.content,
                        style: ShellxText.small.copyWith(
                          color: e.status == PlanStatus.completed
                              ? ShellxDesktopColors.textSecondary
                              : ShellxDesktopColors.textPrimary,
                        ),
                      ),
                    ),
                    if (e.priority == 'high')
                      Text(
                        l10n.aiPlanHigh,
                        style: ShellxText.caption.copyWith(
                          color: ShellxDesktopColors.warn,
                        ),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _Queued extends StatelessWidget {
  const _Queued({required this.text, required this.onRemove});
  final String text;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final short = text.length > 60 ? '${text.substring(0, 60)}…' : text;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s16),
      child: Row(
        children: [
          const Icon(
            Icons.schedule,
            size: 14,
            color: ShellxDesktopColors.textSecondary,
          ),
          const SizedBox(width: ShellxSpace.s6),
          Expanded(
            child: Text(
              l10n.aiQueued(short),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ShellxText.small.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.aiQueueRemove,
            iconSize: 14,
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/ui/ai test/ui/ai
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `All tests passed!` (16 on the scratch copy); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/ui/ai/ai_composer.dart apps/desktop/lib/src/ui/ai/ai_dock.dart apps/desktop/test/ui/ai/ai_composer_test.dart
git commit -m "feat(v2-ai): composer and dock — Enter sends (IME-safe), queue, stop, force stop, plan

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 16: The permission bar — keys 1–9 and Esc, never focused, never auto-allowing (D10) [needs V2-1a Task 9]

D10, spec §4.3, §1.3.

**What it shows:** the current request, one at a time (the next waits). Its first line is "{agent} asks: {card title}", a live region that is read once. Then one button per option, in the agent's order: the key number and the label by `kind` (Allow / Always allow / Reject / Always reject; the agent's own name for `other`). The first `reject_*` also shows Esc. For an `*_always` option, the agent's own words stay visible under the buttons.

**Focus:** the bar never takes the focus (`ExcludeFocus`). Its keys come through the composer's `AiKeyHook`, on key-down:
- 1–9 pick an option, except while the composer has text, while the input method composes, or with ⌘/Ctrl/Alt (⌘1 picks a tab);
- Esc picks the first reject, or answers `cancelled` when there is none.

**Never auto-allow:** nothing answers by itself (pinned).

**Files:**
- Create: `apps/desktop/lib/src/ui/ai/ai_permission_bar.dart`
- Test: `apps/desktop/test/ui/ai/ai_permission_bar_test.dart`

**Interfaces:**
- Consumes: Task 15 (`AiDock`, `AiKeyHook`), Task 13 (`aiPermissionLabel`), V2-1a `AiSessionState.currentPermission` (`PendingPermission.id/request/title`), `AiRuntime.answerPermission(int id, String? optionId)`.
- Produces: `bool aiPermissionKeys(AiRuntime runtime, KeyEvent event, {required bool hasText})`; `class AiPermissionBar`; keys `ai.permission`, `ai.permission.<n>`.

- [ ] **Step 1: Write the failing test**

`apps/desktop/test/ui/ai/ai_permission_bar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ui/ai/ai_dock.dart';
import 'package:shellx_desktop/src/ui/ai/ai_permission_bar.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';

void main() {
  Future<(FakeAiRuntimes, AiRuntime)> asking(
    WidgetTester t, {
    List<Map<String, Object?>> options = FakeSteps.claudeOptions,
  }) async {
    final fakes = FakeAiRuntimes(
      FakeScenario(
        turns: [
          [
            FakeSteps.permission('t1', 'Edit a.ts', options: options),
            FakeSteps.text('done'),
          ],
        ],
      ),
    );
    final runtime = partRuntime(fakes);
    await runtime.start();
    await pumpAiPart(
      t,
      AiDock(
        permissionBar: const AiPermissionBar(),
        keyHook: (e, {required hasText}) =>
            aiPermissionKeys(runtime, e, hasText: hasText),
      ),
      runtime: runtime,
    );
    await t.tap(find.byKey(const Key('ai.composer')));
    await runtime.send([const TextBlock('edit it')]);
    await t.pump();
    await t.pump();
    return (fakes, runtime);
  }

  List<String> answers(FakeAiRuntimes f) => [
    for (final r in f.agent().received)
      if (r.startsWith('permission:')) r.substring(11),
  ];

  testWidgets('the bar: title, options by kind with keys, the agent words '
      'for "always" (§4.3)', (t) async {
    final (fakes, runtime) = await asking(t);
    expect(find.text('Claude asks: Edit a.ts'), findsOneWidget);
    expect(find.text('Allow'), findsOneWidget);
    expect(find.text('Always allow'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
    expect(find.text('Esc'), findsOneWidget);
    expect(
      find.text(
        '“Always allow” as Claude puts it: Yes, allow all edits during '
        'this session',
      ),
      findsOneWidget,
    );
    expect(answers(fakes), isEmpty, reason: 'never answers by itself');
    await runtime.dispose();
  });

  testWidgets('key 2 picks the second option, in the agent order (D10)', (
    t,
  ) async {
    final (fakes, runtime) = await asking(t);
    await t.sendKeyEvent(LogicalKeyboardKey.digit2);
    await t.pump();
    expect(answers(fakes), ['allow-with-updates']);
    expect(find.byKey(const Key('ai.permission')), findsNothing);
    await runtime.whenIdle();
    await runtime.dispose();
  });

  testWidgets('Esc picks the first reject; with none it is cancelled', (
    t,
  ) async {
    var (fakes, runtime) = await asking(t);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(answers(fakes), ['reject']);
    await runtime.dispose();
    (fakes, runtime) = await asking(
      t,
      options: const [
        {'optionId': 'ok', 'name': 'Yes', 'kind': 'allow_once'},
      ],
    );
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(answers(fakes), ['cancelled']);
    await runtime.dispose();
  });

  testWidgets('with text in the composer, or while composing, digits are '
      'text; ⌘1 is the window\'s (D10, §1.10)', (t) async {
    final (fakes, runtime) = await asking(t);
    await t.enterText(find.byKey(const Key('ai.composer')), 'x');
    await t.sendKeyEvent(LogicalKeyboardKey.digit1);
    await t.pump();
    expect(answers(fakes), isEmpty);
    await t.enterText(find.byKey(const Key('ai.composer')), '');
    t.testTextInput.updateEditingValue(
      const TextEditingValue(text: 'a', composing: TextRange(start: 0, end: 1)),
    );
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.digit1);
    await t.pump();
    expect(answers(fakes), isEmpty);
    t.testTextInput.updateEditingValue(TextEditingValue.empty);
    await t.pump();
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.digit1);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pump();
    expect(answers(fakes), isEmpty);
    await runtime.dispose();
  });

  testWidgets('the bar never takes the focus from the composer', (t) async {
    final (_, runtime) = await asking(t);
    final composer = t
        .widget<TextField>(find.byKey(const Key('ai.composer')))
        .focusNode!;
    expect(composer.hasPrimaryFocus, isTrue);
    await t.tap(find.text('Claude asks: Edit a.ts'));
    await t.pump();
    expect(composer.hasPrimaryFocus, isTrue);
    await runtime.dispose();
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai/ai_permission_bar_test.dart`
Expected: the test does not compile, `Error when reading 'lib/src/ui/ai/ai_permission_bar.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/ui/ai/ai_permission_bar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/host.dart';

import '../../../l10n/app_localizations.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_labels.dart';
import 'ai_scope.dart';

const _digits = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

const _numpad = [
  LogicalKeyboardKey.numpad1,
  LogicalKeyboardKey.numpad2,
  LogicalKeyboardKey.numpad3,
  LogicalKeyboardKey.numpad4,
  LogicalKeyboardKey.numpad5,
  LogicalKeyboardKey.numpad6,
  LogicalKeyboardKey.numpad7,
  LogicalKeyboardKey.numpad8,
  LogicalKeyboardKey.numpad9,
];

/// D10: the permission bar's keys, offered by the composer before its own
/// (the bar never takes the focus). On key-down:
/// - 1–9 pick the options in the agent's order — not while the composer
///   has text (they are typing) and never with ⌘/Ctrl/Alt (⌘1 picks a tab);
/// - Esc picks the first `reject_*` option, or answers `cancelled` when
///   there is none.
/// Nothing ever picks an `allow_*` option by itself.
bool aiPermissionKeys(
  AiRuntime runtime,
  KeyEvent event, {
  required bool hasText,
}) {
  final pending = runtime.state.currentPermission;
  if (pending == null || event is! KeyDownEvent) return false;
  final key = event.logicalKey;
  if (key == LogicalKeyboardKey.escape) {
    final reject = pending.request.options
        .where((o) => o.kind.isReject)
        .firstOrNull;
    runtime.answerPermission(pending.id, reject?.optionId);
    return true;
  }
  if (hasText) return false;
  final hw = HardwareKeyboard.instance;
  if (hw.isMetaPressed || hw.isControlPressed || hw.isAltPressed) return false;
  var n = _digits.indexOf(key);
  if (n < 0) n = _numpad.indexOf(key);
  final options = pending.request.options;
  if (n < 0 || n >= options.length) return false;
  runtime.answerPermission(pending.id, options[n].optionId);
  return true;
}

/// D10, spec §4.3: the request being asked (one at a time; the next waits
/// its turn). The first line is a live region, read once; each option is a
/// button with its key; the first reject also shows Esc; the agent's own
/// words for an "always" option stay visible under them.
class AiPermissionBar extends StatelessWidget {
  const AiPermissionBar({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AiPaneScope.of(context);
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: scope.frames,
      builder: (context, _) {
        final pending = scope.state.currentPermission;
        if (pending == null) return const SizedBox.shrink();
        final options = pending.request.options;
        final firstReject = options.indexWhere((o) => o.kind.isReject);
        final always = options
            .where(
              (o) =>
                  o.kind == PermissionKind.allowAlways ||
                  o.kind == PermissionKind.rejectAlways,
            )
            .firstOrNull;
        return ExcludeFocus(
          child: Container(
            key: const Key('ai.permission'),
            margin: const EdgeInsets.fromLTRB(
              ShellxSpace.s16,
              ShellxSpace.s4,
              ShellxSpace.s16,
              0,
            ),
            padding: const EdgeInsets.all(ShellxSpace.s12),
            decoration: BoxDecoration(
              color: ShellxDesktopColors.warnBg,
              borderRadius: BorderRadius.circular(ShellxRadius.r8),
              border: Border.all(color: ShellxDesktopColors.warnBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.aiPermTitle(scope.state.agentName, pending.title),
                    style: ShellxText.bodyStrong.copyWith(
                      color: ShellxDesktopColors.textTitle,
                    ),
                  ),
                ),
                const SizedBox(height: ShellxSpace.s8),
                Wrap(
                  spacing: ShellxSpace.s8,
                  runSpacing: ShellxSpace.s6,
                  children: [
                    for (final (i, o) in options.indexed)
                      _OptionButton(
                        key: ValueKey('ai.permission.${i + 1}'),
                        number: i + 1,
                        label: aiPermissionLabel(l10n, o),
                        tooltip: o.name,
                        esc: i == firstReject,
                        reject: o.kind.isReject,
                        onPressed: () => scope.runtime.answerPermission(
                          pending.id,
                          o.optionId,
                        ),
                      ),
                  ],
                ),
                if (always != null) ...[
                  const SizedBox(height: ShellxSpace.s6),
                  Text(
                    l10n.aiPermAlwaysNote(
                      aiPermissionLabel(l10n, always),
                      scope.state.agentName,
                      always.name,
                    ),
                    style: ShellxText.small.copyWith(
                      color: ShellxDesktopColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    super.key,
    required this.number,
    required this.label,
    required this.tooltip,
    required this.esc,
    required this.reject,
    required this.onPressed,
  });

  final int number;
  final String label;
  final String tooltip;
  final bool esc;
  final bool reject;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    Widget kbd(String k) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: ShellxDesktopColors.border),
        borderRadius: BorderRadius.circular(ShellxRadius.r4),
      ),
      child: Text(k, style: ShellxText.caption),
    );
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            kbd('$number'),
            const SizedBox(width: ShellxSpace.s6),
            Text(
              label,
              style: TextStyle(
                color: reject
                    ? ShellxDesktopColors.err
                    : ShellxDesktopColors.textPrimary,
              ),
            ),
            if (esc) ...[const SizedBox(width: ShellxSpace.s6), kbd('Esc')],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/ui/ai test/ui/ai
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `All tests passed!` (21 on the scratch copy); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/ui/ai/ai_permission_bar.dart apps/desktop/test/ui/ai/ai_permission_bar_test.dart
git commit -m "feat(v2-ai): permission bar — keys 1-9 and Esc on key-down, never focused, never auto-allowing

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


### Task 17: The AI pane — header, conversation, dock, folder, resume, lazy start (§4.1, D3, D5, D14) [needs V2-1a Task 9]

Spec §4.1, D3, D5, D14, D21; rulings B7, B11.

**What the pane is:** Task 5's stand-in becomes the real pane.
- **Header (34 px):** the agent, the session title, and the status in A12's words, with a clock while a turn runs ("Running · 0:12"). Then Terminal, Zoom (only while the tab is split) and ⋯ (Settings › Agents, Restart agent, View log). History and Changes · Files come in Tasks 26 and 20.
- **Below the header:** the conversation (Task 12), and under it the dock (Tasks 15–16).
- **Over the conversation:** the pane's overlay (the run sheet in Task 18, the viewer in Task 25) and the "Resume session" card.

**When the agent starts:**
- **Instant feedback:** the pane shows at once. Its runtime is made right after that first frame (never while building).
- **B11:** the agent starts when its tab is first shown, once per runtime.
- **Smoothness:** a hidden pane's views hear nothing (`AiFrameNotifier.active = false`) and catch up with one notification when shown.

**When the pane shows something else:**
- **D5:** with no folder, the pane shows "Choose a project folder" (B7: a typed path, absolute, `~` allowed, existing — checked through the `aiFolderExistsProvider` seam).
- **§6:** "Choose folder" on a "folder gone" card shows the same card. The chosen folder means a new runtime: `AiRuntimes.forget` stops the old one; the session id stays, and the agent says whether it can reopen it there.
- **D14:** a pane made for a session to reopen shows "Resume session — Loading the conversation…" until the session has loaded.
- **D21:** `ai-agent-claude = off` stops a running Claude at once, and its pane says why; so does a removed custom agent ("This agent is no longer in Settings › Agents").

**Focus (found while verifying this task):**
- The window has a single terminal focus node, which it hands to the focused pane of the selected tab. `FocusNode.attach` keeps the key handler of the last widget that attached the node with one. A text field attaching it passes none.
- So if the composer held that node, the hidden shell tab's xterm handler would take Enter, Backspace and the arrows, and send them to that shell.
- The fix:
  - The pane holds the window's node in its own `Focus`, with a handler that ignores every key (replacing the stale one).
  - It hands the keyboard on to its own input node (composer or folder field) whenever the window focuses it.
  - Pinned on Windows, where Backspace and ← are framework shortcuts.
  - That `Focus` stays in the tree with or without the window's node. A wrapper that came and went with the selection rebuilt the whole pane at every tab switch, losing the composer's text and the panels' state (pinned: "away and back").
- **The composer while signed out:** it is read-only, never `enabled: false`. A disabled field gives up the keyboard, and the keyboard would not come back once the agent is ready.

**Files:**
- Create: `apps/desktop/lib/src/ai/ai_folders.dart`, `apps/desktop/lib/src/ui/ai/ai_folder_card.dart`, `apps/desktop/lib/src/ui/ai/ai_header.dart`, `apps/desktop/lib/src/ui/settings/settings_start_page.dart`
- Replace: `apps/desktop/lib/src/ui/ai/ai_pane_view.dart` (Task 5's stand-in, same constructor)
- Modify: `apps/desktop/lib/src/ai/ai_runtimes.dart`, `apps/desktop/lib/src/ai/ai_frame_notifier.dart`, `apps/desktop/lib/src/ui/ai/ai_scope.dart`, `apps/desktop/lib/src/ui/ai/ai_composer.dart`, `apps/desktop/lib/src/ui/settings/settings_overlay.dart`, `apps/desktop/test/ui/ai_tab_screens_test.dart`
- Test: `apps/desktop/test/ui/ai/ai_pane_test.dart`

**Interfaces:**
- Consumes:
  - Task 3 (`updateAiPane`, `openAiTerminal`, `focusPane`, `toggleZoom`, `TerminalTab.label/isSplit/ai`);
  - Task 5 (the pane's place in `pane_tree_view.dart`: `focusNode` is the window's terminal focus while the pane is the selected tab's focused pane);
  - Task 10 (`aiRuntimesProvider` `runtimeFor`, `aiAgentsProvider`, `aiAgentById`, `kClaudeAgentId`, `AiFrameNotifier`, `FakeAiRuntimes`, `testAiCwd`);
  - Tasks 12–16 (`AiTimeline`, `AiDock`, `AiPermissionBar`, `aiPermissionKeys`, `AiPaneScope`, `AiPaneUi.onChooseFolder`, `showAiLogDialog`);
  - V2-1a `AiRuntime.start/restart/stderrTail`, `AiSessionState.phase/turn/needsInput`, `AgentPhase`.
- Produces:
  - widgets and helpers: `AiPaneView` (real); `AiHeader`, `typedef AiHeaderView`, `aiHeaderViewOf`, `aiStatusOf`; `AiSelect<T>({frames, select, builder})`; `AiFolderCard({onChosen, initial, focusNode})`;
  - providers and functions: `aiFolderExistsProvider`, `String? aiFolderFrom(String typed, {required String home})`, `settingsStartPageProvider` (`SettingPage?`, `set`);
  - additions to Task 10: `AiRuntimes.forget(int paneId)`, `AiFrameNotifier.active`;
  - keys `ai.header.title`, `ai.header.status`, `ai.terminal`, `ai.zoom`, `ai.more`, `ai.more.settings`, `ai.more.restart`, `ai.more.log`, `ai.folder`, `ai.folder.field`, `ai.folder.use`, `ai.resume`, `ai.message`.

- [ ] **Step 1: Write the failing test**

`apps/desktop/test/ui/ai/ai_pane_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_folders.dart';
import 'package:shellx_desktop/src/ai/ai_frame_notifier.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/settings/pages/agents_page.dart';
import 'package:shellx_desktop/src/ui/settings/settings_start_page.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_tabs.dart';
import '../../support/config_harness.dart';
import '../../support/config_workspace.dart';

/// V2-1 §4.1, D3, D5, D14, B11: the AI pane in the window.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  workspace(WidgetTester t, FakeAiRuntimes fakes) => pumpConfiguredWorkspace(
    t,
    platform: TargetPlatform.macOS,
    extra: [
      ...fakes.overrides,
      aiFolderExistsProvider.overrideWithValue(
        (path) async => path == testAiCwd,
      ),
    ],
  );

  testWidgets('a new AI tab starts its agent once shown; a prompt '
      'round-trips and names the tab (D2, D3)', (t) async {
    final fakes = FakeAiRuntimes(
      FakeScenario(
        turns: [
          [FakeSteps.text('Hello back')],
        ],
      ),
    );
    final c = (await workspace(t, fakes)).container;
    final ai = openTestAiTab(c, cwd: testAiCwd);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    expect(fakes.launcher.channels, hasLength(1));
    expect(fakes.requests.single.cwd, testAiCwd);
    await t.enterText(find.byKey(const Key('ai.composer')), 'Say hello');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(fakes.agent().received, contains('session/prompt:Say hello'));
    expect(
      find.textContaining('Hello back', findRichText: true),
      findsOneWidget,
    );
    expect(
      t.widget<Text>(find.byKey(const Key('ai.header.title'))).data,
      'Say hello',
    );
    final tab = c
        .read(terminalTabsProvider)
        .tabs
        .firstWhere((x) => x.id == ai.id);
    expect(tab.label, 'Say hello');
    expect(tab.ai!.sessionId, 'sess-1');
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('keys typed in the pane stay there: the window focus node '
      'keeps no terminal key handler (Backspace, arrows)', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.windows,
      extra: fakes.overrides,
    );
    final c = w.container;
    // The shell tab's terminal held the window's focus node first.
    final shell = c.read(terminalTabsProvider).tabs.single.id;
    openTestAiTab(c, cwd: testAiCwd);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ai.composer')), 'abcx');
    await t.sendKeyEvent(LogicalKeyboardKey.backspace);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pump();
    final field = t.widget<TextField>(find.byKey(const Key('ai.composer')));
    expect(field.controller!.text, 'abc');
    expect(field.controller!.selection.baseOffset, 2);
    expect(w.local.views[shell]!.writes, isEmpty);
    await disposeWorkspace(t, c);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('away and back: the pane keeps what was typed and its panel '
      'state (no rebuild from scratch)', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final c = (await workspace(t, fakes)).container;
    final shell = c.read(terminalTabsProvider).tabs.single.id;
    final ai = openTestAiTab(c, cwd: testAiCwd);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ai.composer')), 'half a thought');
    await t.pump();
    final tabs = c.read(terminalTabsProvider.notifier)..select(shell);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    tabs.select(ai.id);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    expect(
      t
          .widget<TextField>(find.byKey(const Key('ai.composer')))
          .controller!
          .text,
      'half a thought',
    );
    expect(fakes.made, hasLength(1));
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('B11: a tab opened in the background starts nothing until '
      'it is shown, then once', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final c = (await workspace(t, fakes)).container;
    final first = c.read(terminalTabsProvider).tabs.single.id;
    final ai = openTestAiTab(c, cwd: testAiCwd, select: false);
    await t.pumpAndSettle();
    expect(fakes.launcher.channels, isEmpty);
    final tabs = c.read(terminalTabsProvider.notifier)..select(ai.id);
    await t.pumpAndSettle();
    expect(fakes.launcher.channels, hasLength(1));
    tabs.select(first);
    await t.pumpAndSettle();
    tabs.select(ai.id);
    await t.pumpAndSettle();
    expect(fakes.launcher.channels, hasLength(1));
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('D5: without a folder the pane asks for one, then starts '
      'there', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final c = (await workspace(t, fakes)).container;
    final ai = openTestAiTab(c, cwd: null);
    await t.pumpAndSettle();
    expect(find.text('Choose a project folder'), findsOneWidget);
    expect(fakes.made, isEmpty);
    await t.enterText(find.byKey(const Key('ai.folder.field')), 'not/here');
    await t.tap(find.byKey(const Key('ai.folder.use')));
    await t.pumpAndSettle();
    expect(
      find.text('Enter the absolute path of an existing folder.'),
      findsOneWidget,
    );
    await t.enterText(find.byKey(const Key('ai.folder.field')), testAiCwd);
    await t.tap(find.byKey(const Key('ai.folder.use')));
    await t.pumpAndSettle();
    final pane = c
        .read(terminalTabsProvider)
        .tabs
        .firstWhere((x) => x.id == ai.id)
        .ai!;
    expect(pane.cwd, testAiCwd);
    expect(fakes.requests.single.cwd, testAiCwd);
    expect(fakes.launcher.channels, hasLength(1));
    expect(find.byKey(const Key('ai.composer')), findsOneWidget);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('§6: the folder is gone: "Choose folder" starts a new runtime '
      'in the chosen one', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final c = (await workspace(t, fakes)).container;
    openTestAiTab(c, cwd: '/gone/project');
    await t.pumpAndSettle();
    expect(find.text('The project folder no longer exists'), findsOneWidget);
    expect(fakes.launcher.channels, isEmpty);
    await t.tap(find.byKey(const Key('ai.chooseFolder')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ai.folder.field')), testAiCwd);
    await t.tap(find.byKey(const Key('ai.folder.use')));
    await t.pumpAndSettle();
    expect(fakes.requests.map((r) => r.cwd), ['/gone/project', testAiCwd]);
    expect(fakes.launcher.channels, hasLength(1));
    expect(find.text('The project folder no longer exists'), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('D14: a reopened session shows "Resume session" until it has '
      'loaded', (t) async {
    final fakes = FakeAiRuntimes(
      const FakeScenario(
        history: [
          {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': 'Login fixed.'},
          },
        ],
      ),
    );
    final c = (await workspace(t, fakes)).container;
    openTestAiTab(c, cwd: testAiCwd, sessionId: 'sess-9');
    await t.pump();
    expect(find.byKey(const Key('ai.resume')), findsOneWidget);
    expect(find.text('Loading the conversation…'), findsOneWidget);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.resume')), findsNothing);
    expect(fakes.agent().received, contains('session/load:sess-9'));
    expect(
      find.textContaining('Login fixed.', findRichText: true),
      findsOneWidget,
    );
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('header: Terminal adds a shell under the pane; Zoom shows '
      'once split (D3, §4.1)', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final c = (await workspace(t, fakes)).container;
    final ai = openTestAiTab(c, cwd: testAiCwd);
    await t.pumpAndSettle();
    TerminalTab tab() =>
        c.read(terminalTabsProvider).tabs.firstWhere((x) => x.id == ai.id);
    expect(find.byKey(const Key('ai.zoom')), findsNothing);
    await t.tap(find.byKey(const Key('ai.terminal')));
    await t.pumpAndSettle();
    expect(tab().panes, hasLength(1));
    await t.tap(find.byKey(const Key('ai.zoom')));
    await t.pumpAndSettle();
    expect(tab().zoomedPaneId, ai.ai!.id);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('⋯: View log shows the agent stderr; Settings › Agents opens '
      'Settings on that page (§4.1)', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final c = (await workspace(t, fakes)).container;
    openTestAiTab(c, cwd: testAiCwd);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ai.more')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ai.more.log')));
    await t.pumpAndSettle();
    expect(
      t.widget<SelectableText>(find.byKey(const Key('ai.log.text'))).data,
      contains('RECV initialize'),
    );
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ai.more')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ai.more.settings')));
    await t.pumpAndSettle();
    expect(find.byType(AgentsPage), findsOneWidget);
    expect(c.read(settingsStartPageProvider), isNull);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('D21: ai-agent-claude = off stops a running Claude and the '
      'pane says why', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final w = await workspace(t, fakes);
    final c = w.container;
    openTestAiTab(c, cwd: testAiCwd);
    await t.pumpAndSettle();
    expect(fakes.launcher.channels.single.exited, isFalse);
    w.fs.write(testConfigPaths().shellx, 'ai-agent-claude = off\n');
    await loadConfig(c);
    await t.pumpAndSettle();
    expect(fakes.launcher.channels.single.stopCalls, 1);
    expect(
      find.text(
        'The Claude integration is turned off (ai-agent-claude = off).',
      ),
      findsOneWidget,
    );
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('signed out: the composer waits and keeps the keyboard', (
    t,
  ) async {
    final fakes = FakeAiRuntimes(const FakeScenario(requireAuth: true));
    final c = (await workspace(t, fakes)).container;
    openTestAiTab(c, cwd: testAiCwd);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    expect(find.text('Waiting for the agent…'), findsOneWidget);
    final field = t.widget<TextField>(find.byKey(const Key('ai.composer')));
    expect(field.focusNode!.hasPrimaryFocus, isTrue);
    expect(field.readOnly, isTrue);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('smoothness: a hidden pane hears nothing, then catches up '
      'once', (t) async {
    final state = AiSessionState(
      agentId: 'claude',
      agentName: 'Claude',
      cwd: testAiCwd,
    );
    final frames = AiFrameNotifier(state)..active = false;
    addTearDown(frames.dispose);
    var heard = 0;
    frames.addListener(() => heard++);
    state
      ..touch()
      ..touch();
    await t.pump();
    expect(heard, 0);
    frames.active = true;
    await t.pump();
    expect(heard, 1);
  });
}
```

The Task 5 screen tests now get a real pane, which starts its agent when shown: give them fake runtimes and a folder that exists.

In `apps/desktop/test/ui/ai_tab_screens_test.dart`, replace:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';
```

with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/terminal/agent_status.dart';
```

In `apps/desktop/test/ui/ai_tab_screens_test.dart`, replace:

```dart
import '../support/ai_tabs.dart';
```

with:

```dart
import '../support/ai_fakes.dart';
import '../support/ai_tabs.dart';
```

In `apps/desktop/test/ui/ai_tab_screens_test.dart`, replace:

```dart
    final w = await pumpConfiguredWorkspace(t, platform: TargetPlatform.macOS);
    final ai = openTestAiTab(w.container, title: 'Fix login');
```

with:

```dart
    // V2-1b Task 17: the AI pane starts its runtime when shown.
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: FakeAiRuntimes(const FakeScenario()).overrides,
    );
    final ai = openTestAiTab(w.container, title: 'Fix login', cwd: testAiCwd);
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai/ai_pane_test.dart`
Expected: the test does not compile, `Error when reading 'lib/src/ai/ai_folders.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/ai/ai_folders.dart`:

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// D5: whether [path] is a folder that exists. A seam: widget tests never
/// touch the disk under fake async.
final aiFolderExistsProvider = Provider<Future<bool> Function(String path)>(
  (ref) =>
      (path) => Directory(path).exists(),
);

/// D5: what the user typed as a project folder, made absolute: `~` is the
/// home folder. Null when it is not an absolute path.
String? aiFolderFrom(String typed, {required String home}) {
  var text = typed.trim();
  if (text == '~') text = home;
  if (text.startsWith('~/') || text.startsWith(r'~\')) {
    text = p.join(home, text.substring(2));
  }
  if (text.isEmpty || !p.isAbsolute(text)) return null;
  return p.normalize(text);
}
```

`apps/desktop/lib/src/ui/settings/settings_start_page.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/settings_schema.dart';

/// The page Settings opens on next (V2-1 D7: the AI pane's "Settings ›
/// Agents"); null: the usual first page. The overlay clears it.
final settingsStartPageProvider =
    NotifierProvider<SettingsStartPage, SettingPage?>(SettingsStartPage.new);

class SettingsStartPage extends Notifier<SettingPage?> {
  @override
  SettingPage? build() => null;

  void set(SettingPage? page) => state = page;
}
```

`apps/desktop/lib/src/ui/ai/ai_folder_card.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../ai/ai_folders.dart';
import '../../terminal/local_sessions_provider.dart' show homeDirectoryProvider;
import '../text_editing_shortcuts.dart';
import '../theme/shellx_desktop_theme.dart';

/// D5 "Choose a project folder" (ruling B7: a typed path, as Settings ›
/// Projects takes one): absolute, `~` allowed, and it must exist.
class AiFolderCard extends ConsumerStatefulWidget {
  const AiFolderCard({
    super.key,
    required this.onChosen,
    this.initial,
    this.focusNode,
  });

  final void Function(String folder) onChosen;
  final String? initial;
  final FocusNode? focusNode;

  @override
  ConsumerState<AiFolderCard> createState() => _AiFolderCardState();
}

class _AiFolderCardState extends ConsumerState<AiFolderCard> {
  late final _text = TextEditingController(text: widget.initial ?? '');
  var _invalid = false;
  var _checking = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _use() async {
    final folder = aiFolderFrom(
      _text.text,
      home: ref.read(homeDirectoryProvider),
    );
    setState(() => _checking = true);
    final ok = folder != null && await ref.read(aiFolderExistsProvider)(folder);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _invalid = !ok;
    });
    if (ok) widget.onChosen(folder);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(ShellxSpace.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.aiChooseFolderTitle,
                style: ShellxText.emptyTitle.copyWith(
                  color: ShellxDesktopColors.textTitle,
                ),
              ),
              const SizedBox(height: ShellxSpace.s4),
              Text(
                l10n.aiChooseFolderBody,
                style: ShellxText.body.copyWith(
                  color: ShellxDesktopColors.textSecondary,
                ),
              ),
              const SizedBox(height: ShellxSpace.s16),
              Shortcuts(
                shortcuts: textEditingShortcuts(),
                child: TextField(
                  key: const Key('ai.folder.field'),
                  controller: _text,
                  focusNode: widget.focusNode,
                  autofocus: widget.focusNode == null,
                  onSubmitted: (_) => unawaited(_use()),
                  decoration: InputDecoration(
                    labelText: l10n.aiFolderField,
                    hintText: '~/code/project',
                    errorText: _invalid ? l10n.aiFolderInvalid : null,
                  ),
                ),
              ),
              const SizedBox(height: ShellxSpace.s12),
              FilledButton(
                key: const Key('ai.folder.use'),
                onPressed: _checking ? null : () => unawaited(_use()),
                child: Text(l10n.aiFolderUse),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

`apps/desktop/lib/src/ui/ai/ai_header.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/agent_names.dart' show agentStateWord;
import '../../terminal/agent_status.dart';
import '../../terminal/agent_status_notifier.dart' show agentPaneBadgeProvider;
import '../theme/shellx_desktop_theme.dart';
import 'ai_labels.dart';
import 'ai_theme.dart';

/// What the header shows of a session. Compared once per frame, so the
/// header rebuilds when its status changes, never per streamed chunk.
typedef AiHeaderView = ({
  AgentPhase phase,
  bool needsInput,
  DateTime? started,
  bool stopping,
});

AiHeaderView aiHeaderViewOf(AiSessionState s) => (
  phase: s.phase,
  needsInput: s.needsInput,
  started: s.turn?.startedAt,
  stopping: s.turn?.cancelRequested ?? false,
);

/// The header's status (spec §4.1, A12's words): a question first, then a
/// running turn, then the agent's phase; at rest, A12's "Done" after a turn
/// (it knows "Done" from "Idle"), else "Idle".
({String text, Color color, IconData? icon}) aiStatusOf(
  AppLocalizations l10n,
  AiHeaderView v,
  AgentState? a12,
) {
  if (v.stopping) {
    return (text: l10n.aiStopping, color: ShellxDesktopColors.warn, icon: null);
  }
  if (v.needsInput) {
    return (
      text: agentStateWord(l10n, AgentState.needsInput),
      color: ShellxDesktopColors.warn,
      icon: Icons.warning_amber_rounded,
    );
  }
  if (v.started != null) {
    return (
      text: agentStateWord(l10n, AgentState.running),
      color: ShellxDesktopColors.accent,
      icon: Icons.circle,
    );
  }
  return switch (v.phase) {
    AgentPhase.starting => (
      text: l10n.aiStatusStarting,
      color: ShellxDesktopColors.textSecondary,
      icon: null,
    ),
    AgentPhase.needsAuth => (
      text: l10n.aiStatusSignIn,
      color: ShellxDesktopColors.warn,
      icon: Icons.key_outlined,
    ),
    AgentPhase.failed => (
      text: l10n.aiStatusStopped,
      color: ShellxDesktopColors.err,
      icon: Icons.error_outline,
    ),
    AgentPhase.stopped => (
      text: l10n.aiStatusNotRunning,
      color: ShellxDesktopColors.textSecondary,
      icon: null,
    ),
    AgentPhase.ready || AgentPhase.running =>
      a12 == AgentState.done
          ? (
              text: agentStateWord(l10n, AgentState.done),
              color: ShellxDesktopColors.ok,
              icon: Icons.check,
            )
          : (
              text: agentStateWord(l10n, AgentState.idle),
              color: ShellxDesktopColors.textSecondary,
              icon: Icons.circle_outlined,
            ),
  };
}

/// The AI pane's header (spec §4.1, 34 px): the agent, the session title,
/// the status (with a clock while a turn runs: "Running · 0:12"), then
/// History, Changes · Files, Terminal, Zoom and ⋯. A button whose action
/// is null is not shown.
class AiHeader extends ConsumerWidget {
  const AiHeader({
    super.key,
    required this.paneId,
    required this.agentName,
    required this.title,
    required this.view,
    this.onHistory,
    this.onPanel,
    this.panelOpen = false,
    required this.onTerminal,
    this.onZoom,
    required this.onMore,
  });

  final int paneId;
  final String agentName;
  final String title;
  final AiHeaderView view;
  final VoidCallback? onHistory;
  final VoidCallback? onPanel;
  final bool panelOpen;
  final VoidCallback onTerminal;
  final VoidCallback? onZoom;

  /// ⋯, with the point under the button (global) for the menu.
  final void Function(Offset at) onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final a12 = ref.watch(agentPaneBadgeProvider(paneId))?.state;
    final status = aiStatusOf(l10n, view, a12);
    final started = view.started;
    Widget button(
      IconData glyph,
      String tip,
      VoidCallback onPressed,
      Key key, {
      bool on = false,
    }) => IconButton(
      key: key,
      tooltip: tip,
      iconSize: 16,
      visualDensity: VisualDensity.compact,
      color: on
          ? ShellxDesktopColors.accent
          : ShellxDesktopColors.textSecondary,
      onPressed: onPressed,
      icon: Icon(glyph),
    );
    return SizedBox(
      height: AiSizes.header,
      child: Padding(
        padding: const EdgeInsets.only(
          left: ShellxSpace.s12,
          right: ShellxSpace.s4,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.auto_awesome,
              size: 14,
              color: ShellxDesktopColors.accent,
            ),
            const SizedBox(width: ShellxSpace.s6),
            Text(
              agentName,
              style: ShellxText.bodyStrong.copyWith(
                color: ShellxDesktopColors.textPrimary,
              ),
            ),
            const SizedBox(width: ShellxSpace.s8),
            Flexible(
              child: Text(
                title,
                key: const Key('ai.header.title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ShellxText.small.copyWith(
                  color: ShellxDesktopColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: ShellxSpace.s12),
            Semantics(
              liveRegion: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (status.icon case final glyph?) ...[
                    Icon(glyph, size: 12, color: status.color),
                    const SizedBox(width: ShellxSpace.s4),
                  ],
                  if (started == null)
                    Text(
                      status.text,
                      key: const Key('ai.header.status'),
                      style: ShellxText.caption.copyWith(color: status.color),
                    )
                  else
                    _Clock(
                      key: const Key('ai.header.status'),
                      label: status.text,
                      since: started,
                      color: status.color,
                    ),
                ],
              ),
            ),
            const Spacer(),
            if (onHistory case final open?)
              button(
                Icons.history,
                l10n.aiHistory,
                open,
                const Key('ai.history'),
              ),
            if (onPanel case final toggle?)
              button(
                Icons.vertical_split_outlined,
                l10n.aiHeaderPanel,
                toggle,
                const Key('ai.panel'),
                on: panelOpen,
              ),
            button(
              Icons.terminal,
              l10n.aiHeaderTerminal,
              onTerminal,
              const Key('ai.terminal'),
            ),
            if (onZoom case final zoom?)
              button(
                Icons.fullscreen,
                l10n.aiHeaderZoom,
                zoom,
                const Key('ai.zoom'),
              ),
            Builder(
              builder: (context) =>
                  button(Icons.more_horiz, l10n.aiHeaderMore, () {
                    final box = context.findRenderObject()! as RenderBox;
                    onMore(box.localToGlobal(Offset(0, box.size.height)));
                  }, const Key('ai.more')),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Running · 0:12": the time since [since], once a second (text, never an
/// animation).
class _Clock extends StatefulWidget {
  const _Clock({
    super.key,
    required this.label,
    required this.since,
    required this.color,
  });

  final String label;
  final DateTime since;
  final Color color;

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Text(
      l10n.aiStatusWithTime(
        widget.label,
        aiClock(DateTime.now().difference(widget.since)),
      ),
      style: ShellxText.caption.copyWith(color: widget.color),
    );
  }
}
```

Replace the whole of Task 5's stand-in, `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../../l10n/app_localizations.dart';
import '../../ai/ai_agents.dart';
import '../../ai/ai_frame_notifier.dart';
import '../../ai/ai_runtimes.dart';
import '../../config/settings_schema.dart' show SettingPage;
import '../../terminal/terminal_tabs.dart';
import '../config/config_ui_request.dart';
import '../settings/settings_start_page.dart';
import '../terminal/shellx_menu.dart';
import '../terminal/terminal_intents.dart' show TogglePaneZoomIntent;
import '../theme/shellx_desktop_theme.dart';
import 'ai_dock.dart';
import 'ai_folder_card.dart';
import 'ai_header.dart';
import 'ai_log_dialog.dart';
import 'ai_permission_bar.dart';
import 'ai_scope.dart';
import 'ai_timeline.dart';

enum _More { settings, restart, log }

/// V2-1 D3, spec §4.1: an AI pane, the negative leaf of an AI tab — its
/// header, the conversation (at most 760 px wide) with the dock under it,
/// and the overlay over it (run sheet, viewer, "Resume session").
/// - Instant feedback: the pane shows at once; its runtime is made right
///   after that first frame (never while building).
/// - B11: the agent starts when the pane's tab is first shown, once per
///   runtime; a hidden pane's views hear nothing until it shows again.
/// - [focusNode] is the window's terminal focus while this pane is the
///   selected tab's focused pane. The whole pane holds it and hands the
///   keyboard on to the composer (or the folder field), so the window's
///   shortcuts and `focusTerminal` reach the pane.
class AiPaneView extends ConsumerStatefulWidget {
  const AiPaneView({
    super.key,
    required this.tab,
    required this.pane,
    required this.selected,
    this.focusNode,
  });

  final TerminalTab tab;
  final AiPaneState pane;

  /// The pane's tab is the selected one.
  final bool selected;
  final FocusNode? focusNode;

  @override
  ConsumerState<AiPaneView> createState() => _AiPaneViewState();
}

class _AiPaneViewState extends ConsumerState<AiPaneView> {
  final _ui = AiPaneUi();

  /// The composer's (or the folder field's) focus: the pane's own, never
  /// the window's (a text field would keep a terminal view's key handler
  /// on it, below).
  final _input = FocusNode(debugLabel: 'ai input');
  AiRuntime? _runtime;
  AiFrameNotifier? _frames;

  /// The runtime this pane started: each runtime starts once (B11).
  AiRuntime? _started;
  var _attachQueued = false;

  /// "Choose folder" on a "folder gone" card (§6).
  var _choosing = false;

  /// D14: the pane reopens a session (a restored tab, History): "Resume
  /// session" shows while it loads.
  late final bool _resuming = widget.pane.sessionId != null;

  @override
  void initState() {
    super.initState();
    _ui.onChooseFolder = () => setState(() => _choosing = true);
    widget.focusNode?.addListener(_onWindowFocus);
    _attachSoon();
  }

  @override
  void didUpdateWidget(AiPaneView old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode?.removeListener(_onWindowFocus);
      widget.focusNode?.addListener(_onWindowFocus);
    }
    _frames?.active = widget.selected;
    if (old.selected != widget.selected || old.pane.cwd != widget.pane.cwd) {
      _attachSoon();
    }
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_onWindowFocus);
    _frames?.dispose();
    _ui.dispose();
    _input.dispose();
    super.dispose();
  }

  /// The window focused this pane (`focusTerminal`, a click): the keyboard
  /// goes on to the composer or the folder field when one is shown.
  void _onWindowFocus() {
    if (widget.focusNode?.hasPrimaryFocus ?? false) _forward();
  }

  void _forward() {
    if (_input.context != null && _input.canRequestFocus) {
      _input.requestFocus();
    }
  }

  void _attachSoon() {
    if (_attachQueued) return;
    _attachQueued = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        _attachQueued = false;
        if (mounted) _attach();
      })
      ..ensureVisualUpdate();
  }

  /// The pane's runtime: made on first use, swapped when it changes (a new
  /// folder, the agent switched off), started once when the tab is shown.
  void _attach() {
    final runtime = ref
        .read(aiRuntimesProvider.notifier)
        .runtimeFor(widget.pane.id);
    if (!identical(runtime, _runtime)) {
      final old = _frames;
      setState(() {
        _runtime = runtime;
        _frames = runtime == null
            ? null
            : (AiFrameNotifier(runtime.state)..active = widget.selected);
      });
      old?.dispose();
    }
    if (runtime != null && widget.selected && !identical(_started, runtime)) {
      _started = runtime;
      unawaited(runtime.start());
    }
  }

  /// D5: the folder the user chose. Another folder is another runtime: the
  /// old one stops; the session id stays (the agent says whether it can
  /// reopen it there, D14).
  void _useFolder(String folder) {
    final old = _frames;
    setState(() {
      _choosing = false;
      _runtime = null;
      _frames = null;
    });
    old?.dispose();
    ref.read(aiRuntimesProvider.notifier).forget(widget.pane.id);
    ref
        .read(terminalTabsProvider.notifier)
        .updateAiPane(widget.pane.id, (p) => p.copyWith(cwd: folder));
    _attachSoon();
  }

  /// Through the window's action when there is one (it also announces).
  void _zoom() {
    final tabs = ref.read(terminalTabsProvider.notifier)
      ..focusPane(widget.pane.id);
    const intent = TogglePaneZoomIntent();
    final action = Actions.maybeFind<TogglePaneZoomIntent>(
      context,
      intent: intent,
    );
    if (action != null && action.isEnabled(intent)) {
      Actions.invoke(context, intent);
    } else {
      tabs.toggleZoom();
    }
  }

  Future<void> _more(Offset at) async {
    final l10n = AppLocalizations.of(context);
    final runtime = _runtime;
    final choice = await showShellxMenu<_More>(
      context: context,
      at: at,
      entries: [
        ShellxMenuEntry(
          value: _More.settings,
          label: l10n.aiMenuAgentsSettings,
          key: const Key('ai.more.settings'),
        ),
        ShellxMenuEntry(
          value: _More.restart,
          label: l10n.aiMenuRestart,
          enabled: runtime != null,
          key: const Key('ai.more.restart'),
        ),
        ShellxMenuEntry(
          value: _More.log,
          label: l10n.aiMenuViewLog,
          enabled: runtime != null,
          key: const Key('ai.more.log'),
        ),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case _More.settings:
        ref.read(settingsStartPageProvider.notifier).set(SettingPage.agents);
        ref
            .read(configUiRequestProvider.notifier)
            .request(ConfigUiRequest.settings);
      case _More.restart:
        if (runtime != null) unawaited(runtime.restart());
      case _More.log:
        if (runtime != null) unawaited(showAiLogDialog(context, runtime));
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pane = widget.pane;
    // D21, D7: an agent switched off or removed; the runtimes stop it.
    ref.listen(aiAgentsProvider, (_, _) => _attachSoon());
    final offered = ref.watch(
      aiAgentsProvider.select((a) => aiAgentById(a, pane.agentId) != null),
    );
    final runtime = _runtime;
    final frames = _frames;
    final needsFolder = pane.cwd == null || _choosing;
    final Widget body;
    if (!offered) {
      body = _Message(
        text: pane.agentId == kClaudeAgentId
            ? l10n.aiClaudeOff
            : l10n.aiAgentUnknown,
      );
    } else if (needsFolder) {
      body = AiFolderCard(
        key: const Key('ai.folder'),
        initial: pane.cwd,
        focusNode: _input,
        onChosen: _useFolder,
      );
    } else if (runtime == null || frames == null) {
      body = _Message(text: '', resuming: _resuming);
    } else {
      body = AiPaneScope(
        runtime: runtime,
        frames: frames,
        tab: widget.tab,
        pane: pane,
        ui: _ui,
        child: _Conversation(input: _input, resuming: _resuming),
      );
    }
    final tabs = ref.read(terminalTabsProvider.notifier);
    Widget header(AiHeaderView view) => AiHeader(
      paneId: pane.id,
      agentName: pane.agentName,
      title: widget.tab.label,
      view: view,
      onTerminal: () => unawaited(tabs.openAiTerminal(widget.tab.id)),
      onZoom: widget.tab.isSplit ? _zoom : null,
      onMore: (at) => unawaited(_more(at)),
    );
    final content = Semantics(
      container: true,
      label: l10n.aiPaneLabel(pane.agentName),
      child: ColoredBox(
        color: ShellxDesktopColors.bgTerminal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (frames != null && offered && !needsFolder)
              AiSelect<AiHeaderView>(
                frames: frames,
                select: aiHeaderViewOf,
                builder: (context, view) => header(view),
              )
            else
              header((
                phase: offered && !needsFolder
                    ? AgentPhase.starting
                    : AgentPhase.stopped,
                needsInput: false,
                started: null,
                stopping: false,
              )),
            const Divider(height: 1, color: ShellxDesktopColors.line),
            Expanded(child: body),
          ],
        ),
      ),
    );
    final window = widget.focusNode;
    if (window != null) {
      // A field that just appeared (the composer once the runtime is there,
      // the folder card) takes the keyboard the pane holds.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && window.hasPrimaryFocus) _forward();
      });
    }
    // Always a `Focus` here, with or without the window's node: a wrapper
    // that came and went with the selection would rebuild the whole pane
    // from scratch (the composer's text, the panels, the scroll place).
    return Focus(
      focusNode: window,
      canRequestFocus: window == null ? false : null,
      skipTraversal: window == null ? true : null,
      // `FocusNode.attach` keeps the key handler the last terminal view
      // put on the window's node unless a new one is given: without this,
      // Enter, Backspace and the arrows typed here would go to that
      // (hidden) terminal.
      onKeyEvent: window == null ? null : (_, _) => KeyEventResult.ignored,
      child: content,
    );
  }
}

/// The conversation, the dock under it, and what lies over it.
class _Conversation extends StatelessWidget {
  const _Conversation({required this.input, required this.resuming});

  final FocusNode input;
  final bool resuming;

  @override
  Widget build(BuildContext context) {
    final scope = AiPaneScope.of(context);
    final runtime = scope.runtime;
    return Stack(
      children: [
        Positioned.fill(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(child: AiTimeline()),
              AiDock(
                focusNode: input,
                permissionBar: const AiPermissionBar(),
                keyHook: (event, {required hasText}) =>
                    aiPermissionKeys(runtime, event, hasText: hasText),
              ),
            ],
          ),
        ),
        if (resuming)
          AiSelect<bool>(
            frames: scope.frames,
            select: (s) =>
                s.phase == AgentPhase.stopped || s.phase == AgentPhase.starting,
            builder: (context, loading) =>
                loading ? const _ResumeCard() : const SizedBox.shrink(),
          ),
        ListenableBuilder(
          listenable: scope.ui,
          builder: (context, _) => switch (scope.ui.overlay) {
            final overlay? => Positioned.fill(child: overlay),
            null => const SizedBox.shrink(),
          },
        ),
      ],
    );
  }
}

/// A pane without a conversation (no runtime yet, or none to have): a
/// line of text.
class _Message extends StatelessWidget {
  const _Message({required this.text, this.resuming = false});

  final String text;
  final bool resuming;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Center(
        child: Padding(
          padding: const EdgeInsets.all(ShellxSpace.s24),
          child: Text(
            text,
            key: const Key('ai.message'),
            textAlign: TextAlign.center,
            style: ShellxText.body.copyWith(
              color: ShellxDesktopColors.textSecondary,
            ),
          ),
        ),
      ),
      if (resuming) const _ResumeCard(),
    ],
  );
}

/// D14: "Resume session — Loading the conversation…" while a reopened
/// session loads (no spinner: no looping animation).
class _ResumeCard extends StatelessWidget {
  const _ResumeCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        key: const Key('ai.resume'),
        margin: const EdgeInsets.all(ShellxSpace.s24),
        padding: const EdgeInsets.all(ShellxSpace.s12),
        decoration: BoxDecoration(
          color: ShellxDesktopColors.surface,
          borderRadius: BorderRadius.circular(ShellxRadius.r8),
          border: Border.all(color: ShellxDesktopColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.history,
                  size: 16,
                  color: ShellxDesktopColors.accent,
                ),
                const SizedBox(width: ShellxSpace.s6),
                Text(
                  l10n.aiResumeSession,
                  style: ShellxText.bodyStrong.copyWith(
                    color: ShellxDesktopColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: ShellxSpace.s4),
            Text(
              l10n.aiResumeLoading,
              style: ShellxText.small.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

In `apps/desktop/lib/src/ai/ai_runtimes.dart`, replace:

```dart
    // D3: a close asks first while a turn runs.
    ref.read(terminalTabsProvider.notifier).aiBusy = busy;
```

with:

```dart
    // D21: an agent switched off (`ai-agent-claude = off`) or removed stops
    // at once; its panes say why.
    ref.listen<List<AgentSpec>>(aiAgentsProvider, (_, next) {
      for (final id in [..._runtimes.keys]) {
        if (aiAgentById(next, _agentOf[id] ?? '') == null) _drop(id);
      }
    });
    // D3: a close asks first while a turn runs.
    ref.read(terminalTabsProvider.notifier).aiBusy = busy;
```

In `apps/desktop/lib/src/ai/ai_runtimes.dart`, replace:

```dart
  /// The runtime of AI pane [paneId] if one was made.
  AiRuntime? existing(int paneId) => _runtimes[paneId];
```

with:

```dart
  /// The runtime of AI pane [paneId] if one was made.
  AiRuntime? existing(int paneId) => _runtimes[paneId];

  /// The pane chose another folder (D5, §6): its runtime stops; the next
  /// [runtimeFor] makes one in the new folder.
  void forget(int paneId) => _drop(paneId);
```

In `apps/desktop/lib/src/ai/ai_frame_notifier.dart`, replace:

```dart
  final AiSessionState state;
  var _scheduled = false;
  var _disposed = false;

  void _changed() {
    if (_scheduled || _disposed) return;
```

with:

```dart
  final AiSessionState state;
  var _scheduled = false;
  var _disposed = false;
  var _active = true;
  var _missed = false;

  /// Smoothness: a hidden pane (another tab is selected) hears nothing; it
  /// catches up with one notification when it shows again.
  set active(bool value) {
    if (_active == value) return;
    _active = value;
    if (value && _missed) {
      _missed = false;
      _changed();
    }
  }

  void _changed() {
    if (!_active) {
      _missed = true;
      return;
    }
    if (_scheduled || _disposed) return;
```

In `apps/desktop/lib/src/ui/ai/ai_scope.dart`, replace:

```dart
  @override
  void dispose() {
    insert.dispose();
    super.dispose();
  }
}
```

with:

```dart
  @override
  void dispose() {
    insert.dispose();
    super.dispose();
  }
}

/// Smoothness: [builder] runs again only when [select] of the session
/// gives another value (checked once per frame), never per streamed chunk.
class AiSelect<T> extends StatefulWidget {
  const AiSelect({
    super.key,
    required this.frames,
    required this.select,
    required this.builder,
  });

  final AiFrameNotifier frames;
  final T Function(AiSessionState state) select;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<AiSelect<T>> createState() => _AiSelectState<T>();
}

class _AiSelectState<T> extends State<AiSelect<T>> {
  late T _value = widget.select(widget.frames.state);

  @override
  void initState() {
    super.initState();
    widget.frames.addListener(_changed);
  }

  @override
  void didUpdateWidget(AiSelect<T> old) {
    super.didUpdateWidget(old);
    if (!identical(old.frames, widget.frames)) {
      old.frames.removeListener(_changed);
      widget.frames.addListener(_changed);
    }
    _value = widget.select(widget.frames.state);
  }

  @override
  void dispose() {
    widget.frames.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final next = widget.select(widget.frames.state);
    if (next != _value) setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
                  focusNode: _focus,
                  enabled: _canSend,
```

with:

```dart
                  focusNode: _focus,
                  // Never `enabled: false`: a disabled field gives up the
                  // keyboard, and it would not come back once the agent is
                  // ready (signed in, restarted).
                  readOnly: !_canSend,
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
                    hintText: l10n.aiComposerHint(scope.state.agentName),
```

with:

```dart
                    hintText: _canSend
                        ? l10n.aiComposerHint(scope.state.agentName)
                        : l10n.aiComposerWaiting,
```

In `apps/desktop/lib/src/ui/settings/settings_overlay.dart`, replace:

```dart
import 'settings_row.dart';
import 'settings_values.dart';
```

with:

```dart
import 'settings_row.dart';
import 'settings_start_page.dart';
import 'settings_values.dart';
```

In `apps/desktop/lib/src/ui/settings/settings_overlay.dart`, replace:

```dart
  Timer? _announceLock;
  bool _announceDirty = false;

  @override
  void dispose() {
```

with:

```dart
  Timer? _announceLock;
  bool _announceDirty = false;

  @override
  void initState() {
    super.initState();
    // V2-1 D7: "Settings › Agents" from an AI pane opens on that page.
    final start = ref.read(settingsStartPageProvider);
    if (start != null) {
      _page = start;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(settingsStartPageProvider.notifier).set(null);
      });
    }
  }

  @override
  void dispose() {
```

- [ ] **Step 4: Run the tests**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/ai lib/src/ui/ai lib/src/ui/settings/settings_start_page.dart lib/src/ui/settings/settings_overlay.dart test/ui/ai test/ui/ai_tab_screens_test.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai test/ui/ai_tab_screens_test.dart test/ui/settings_overlay_test.dart test/ai 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `All tests passed!` (`test/ui/ai`: 33 on the scratch copy); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/ai/ai_folders.dart apps/desktop/lib/src/ui/ai/ai_folder_card.dart apps/desktop/lib/src/ui/ai/ai_header.dart apps/desktop/lib/src/ui/settings/settings_start_page.dart apps/desktop/lib/src/ui/ai/ai_pane_view.dart apps/desktop/lib/src/ai/ai_runtimes.dart apps/desktop/lib/src/ai/ai_frame_notifier.dart apps/desktop/lib/src/ui/ai/ai_scope.dart apps/desktop/lib/src/ui/ai/ai_composer.dart apps/desktop/lib/src/ui/settings/settings_overlay.dart apps/desktop/test/ui/ai_tab_screens_test.dart apps/desktop/test/ui/ai/ai_pane_test.dart
git commit -m "feat(v2-ai): the AI pane — header, conversation, dock, folder card, resume card, lazy start; keys never reach a hidden terminal

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 18: The run sheet — sign-ins and installs in a real terminal (D8) [needs V2-1a Task 9]

Spec D8, §4.5, §6 ("install failed"), §5.

**What it is:** a terminal of its own over the conversation: a PTY from `aiPtyFactoryProvider` (Task 11) and an xterm view, as a terminal pane has. It is not in the pane tree and has no background session. It runs exactly one command:
- **A terminal sign-in** (an `authMethods` entry of type `terminal`): the agent's own command plus the method's `args` and `env` (`AiRuntime.loginCommand`), in the session folder. ShellX never calls `authenticate` for it.
- **The agent's pinned install** (`AgentNeedsInstall.install`, resolved again when the user asks): in its own folder `<support>/ai/agents/<id>`. That folder does not exist before the first install, so it is made first (`aiMakeFolderProvider`, a seam), or npm could not start there.

**The environment:** the command's own, plus `TERM=xterm-256color` and `COLORTERM=truecolor`, because a sign-in is an interactive program. The agents themselves keep the login environment's `TERM=dumb`.

**After it ends:**
- **Exit 0:** the sheet closes and the session goes on. A sign-in reopens the session (`retry`, which calls `session/new` again); an install starts the agent and refreshes the readiness Settings › Agents shows.
- **Any other code:** the sheet stays, with "Ended with exit code N" ("Sign-in did not work." first for a sign-in), "Try again" and Close.

**What ShellX does with the output:** nothing. It is never parsed, logged or kept; closing the sheet stops a program that still runs.

**Files:**
- Create: `apps/desktop/lib/src/ui/ai/ai_run_sheet.dart`
- Modify: `apps/desktop/lib/src/ai/ai_folders.dart`, `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, `apps/desktop/test/support/ai_fakes.dart`
- Test: `apps/desktop/test/ui/ai/ai_run_sheet_test.dart`

**Interfaces:**
- Consumes:
  - Task 11 `aiPtyFactoryProvider` (`PtyFactory.spawn(ShellCommand, {workingDirectory, environment, cols, rows})`);
  - Task 10 `aiReadinessSourceProvider`, `aiReadinessProvider.refresh`;
  - Task 14 `AiRunLogin` / `AiRunInstall` (the cards' buttons), `AiPaneUi.onRun/showOverlay/closeOverlay`;
  - `DesktopTerminal`, `desktopTerminalStyle`, `terminalAppearanceProvider`, `terminalFontSizeProvider`;
  - V2-1a `AiRuntime.loginCommand(AuthMethodTerminal)`, `AiRuntime.retry()`, `AgentCommand` (`executable`, `args`, `environment`, `workingDirectory`), `AgentNeedsInstall.install`.
- Produces:
  - `class AiRunSheet({title, command, workingDirectory, makeFolder, failureNote, onDone, onClose})`, used by Task 24 too;
  - `aiMakeFolderProvider`; `FakeAiRuntimes.readiness` (now settable);
  - keys `ai.runSheet`, `ai.runSheet.close`, `ai.runSheet.retry`, `ai.runSheet.failed`.

- [ ] **Step 1: Write the failing test**

`apps/desktop/test/ui/ai/ai_run_sheet_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_folders.dart';
import 'package:shellx_desktop/src/ai/ai_startup.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_tabs.dart';
import '../../support/config_workspace.dart';
import '../../support/fake_pty.dart';

/// The run sheet's PTYs, with what each was started with.
final class SheetPtys implements PtyFactory {
  final spawned =
      <
        ({
          ShellCommand command,
          String cwd,
          Map<String, String> env,
          FakePty pty,
        })
      >[];

  @override
  Pty spawn(
    ShellCommand command, {
    required String workingDirectory,
    required Map<String, String> environment,
    required int cols,
    required int rows,
  }) {
    final pty = FakePty(initialCols: cols, initialRows: rows);
    spawned.add((
      command: command,
      cwd: workingDirectory,
      env: environment,
      pty: pty,
    ));
    return pty;
  }
}

/// V2-1 D8: sign-ins and installs in the run sheet.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<ProviderContainer> workspace(
    WidgetTester t,
    FakeAiRuntimes fakes,
    SheetPtys ptys, {
    List<String>? made,
  }) async {
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: [
        ...fakes.overrides,
        aiPtyFactoryProvider.overrideWithValue(ptys),
        aiMakeFolderProvider.overrideWithValue((path) async => made?.add(path)),
      ],
    );
    openTestAiTab(w.container, cwd: testAiCwd);
    await t.pumpAndSettle();
    return w.container;
  }

  testWidgets('a terminal sign-in runs the agent\'s own command with the '
      'method\'s args and env in a real terminal; exit 0 opens the session', (
    t,
  ) async {
    final auth = Directory.systemTemp.createTempSync('ai_auth');
    addTearDown(() => auth.deleteSync(recursive: true));
    final fakes = FakeAiRuntimes(
      FakeScenario(
        requireAuth: true,
        authFile: '${auth.path}/signed-in',
        authMethods: const [
          {
            'id': 'claude-login',
            'name': 'Log in with Claude',
            'type': 'terminal',
            'args': ['/login'],
            'env': {'CLAUDE_LOGIN': '1'},
          },
        ],
      ),
    );
    final ptys = SheetPtys();
    final c = await workspace(t, fakes, ptys);
    expect(find.text('Claude needs you to sign in'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ai.login.claude-login')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.runSheet')), findsOneWidget);
    expect(find.text('Sign in to Claude'), findsOneWidget);
    final run = ptys.spawned.single;
    expect(run.command.executable, 'fake-agent');
    expect(run.command.arguments, ['/login']);
    expect(run.cwd, testAiCwd);
    expect(run.env['CLAUDE_LOGIN'], '1');
    expect(run.env['TERM'], 'xterm-256color');
    expect(run.env['COLORTERM'], 'truecolor');
    // The user signs in there; ShellX reads none of it.
    run.pty.emit('Opening your browser…\r\n');
    File('${auth.path}/signed-in').writeAsStringSync('ok');
    run.pty.exit(0);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.runSheet')), findsNothing);
    expect(fakes.made.single.state.phase, AgentPhase.ready);
    expect(
      fakes.agent().received.where((r) => r == 'session/new'),
      hasLength(2),
    );
    expect(fakes.agent().received, isNot(contains(startsWith('authenticate'))));
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a failed sign-in keeps the sheet with its exit code; Try '
      'again runs it again; Close stops what still runs', (t) async {
    final fakes = FakeAiRuntimes(
      const FakeScenario(
        requireAuth: true,
        authMethods: [
          {'id': 'login', 'name': 'Log in', 'type': 'terminal'},
        ],
      ),
    );
    final ptys = SheetPtys();
    final c = await workspace(t, fakes, ptys);
    await t.tap(find.byKey(const ValueKey('ai.login.login')));
    await t.pumpAndSettle();
    ptys.spawned.single.pty.exit(1);
    await t.pumpAndSettle();
    expect(
      find.text('Sign-in did not work. Ended with exit code 1'),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('ai.runSheet.retry')));
    await t.pumpAndSettle();
    expect(ptys.spawned, hasLength(2));
    expect(find.byKey(const Key('ai.runSheet.failed')), findsNothing);
    await t.tap(find.byKey(const Key('ai.runSheet.close')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.runSheet')), findsNothing);
    expect(ptys.spawned.last.pty.killed, isTrue);
    expect(ptys.spawned.first.pty.killed, isFalse, reason: 'it had ended');
    expect(fakes.made.single.state.phase, AgentPhase.needsAuth);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('Install runs the pinned install in its folder, made first, '
      'with a real terminal; then the agent starts (D6, D7)', (t) async {
    const install = AgentCommand(
      executable: '/usr/local/bin/node',
      args: ['/usr/local/lib/node_modules/npm/bin/npm-cli.js', 'install'],
      environment: {'PATH': '/usr/local/bin:/usr/bin', 'TERM': 'dumb'},
      workingDirectory: '/support/ai/agents/claude',
    );
    final fakes = FakeAiRuntimes(
      const FakeScenario(),
      readiness: const AgentNeedsInstall(install),
    );
    final ptys = SheetPtys();
    final made = <String>[];
    final c = await workspace(t, fakes, ptys, made: made);
    expect(find.text('Claude is not installed'), findsOneWidget);
    await t.tap(find.byKey(const Key('ai.install')));
    await t.pumpAndSettle();
    expect(made, ['/support/ai/agents/claude']);
    final run = ptys.spawned.single;
    expect(run.command.executable, '/usr/local/bin/node');
    expect(run.command.arguments, install.args);
    expect(run.cwd, '/support/ai/agents/claude');
    expect(run.env['PATH'], '/usr/local/bin:/usr/bin');
    expect(run.env['TERM'], 'xterm-256color', reason: 'not the agents\' dumb');
    expect(find.text('Install Claude'), findsOneWidget);
    fakes.readiness = null;
    run.pty.exit(0);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.runSheet')), findsNothing);
    expect(fakes.launcher.channels, hasLength(1));
    expect(fakes.made.single.state.phase, AgentPhase.ready);
    await disposeWorkspace(t, c);
  }, variant: mac);
}
```

`FakeAiRuntimes.readiness` becomes settable (an install that worked):

In `apps/desktop/test/support/ai_fakes.dart`, replace:

```dart
  final FakeLauncher launcher;
  final Checkpoints? checkpoints;
  final AgentReadiness? readiness;
```

with:

```dart
  final FakeLauncher launcher;
  final Checkpoints? checkpoints;

  /// What every agent's check answers (null: ready); a test may change it
  /// (an install that worked).
  AgentReadiness? readiness;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai/ai_run_sheet_test.dart`
Expected: the test does not compile, `Undefined name 'aiMakeFolderProvider'`.

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/ui/ai/ai_run_sheet.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart' show Pty, ShellCommand;
import 'package:shellx_ai/host.dart';
import 'package:xterm/xterm.dart';

import '../../../l10n/app_localizations.dart';
import '../../ai/ai_folders.dart';
import '../../ai/ai_startup.dart';
import '../../terminal/desktop_terminal.dart';
import '../../terminal/terminal_appearance.dart';
import '../../terminal/terminal_font_size.dart';
import '../../terminal/terminal_style.dart';
import '../theme/shellx_desktop_theme.dart';

/// D8: the run sheet — a terminal of its own over the AI pane (a PTY and
/// xterm, as a terminal pane has; not in the pane tree, no background
/// session) that runs exactly [command]: an agent's terminal sign-in, or
/// its pinned install. Exit 0 calls [onDone]; another code keeps the sheet
/// with the code, "Try again" and "Close".
/// - ShellX never parses, logs or keeps what runs here (§5).
/// - The program gets a real terminal (`TERM=xterm-256color`,
///   `COLORTERM=truecolor`) on top of [command]'s environment; the agents
///   themselves keep the `TERM=dumb` of the login environment.
class AiRunSheet extends ConsumerStatefulWidget {
  const AiRunSheet({
    super.key,
    required this.title,
    required this.command,
    required this.workingDirectory,
    this.makeFolder = false,
    this.failureNote,
    required this.onDone,
    required this.onClose,
  });

  final String title;
  final AgentCommand command;
  final String workingDirectory;

  /// An install's folder (`<support>/ai/agents/<id>`) does not exist before
  /// the first install: it is made first.
  final bool makeFolder;

  /// Said before the exit code when the program fails ("Sign-in did not
  /// work.").
  final String? failureNote;
  final VoidCallback onDone;
  final VoidCallback onClose;

  @override
  ConsumerState<AiRunSheet> createState() => _AiRunSheetState();
}

class _AiRunSheetState extends ConsumerState<AiRunSheet> {
  final _terminal = DesktopTerminal(maxLines: 2000);
  final _focus = FocusNode(debugLabel: 'ai run sheet');
  Pty? _pty;
  StreamSubscription<String>? _output;

  /// The program runs (spawned, not exited).
  var _running = false;

  /// The exit code of a run that failed; null while it runs (or before).
  int? _failed;

  @override
  void initState() {
    super.initState();
    _terminal
      ..onUserInput = _send
      ..onReply = _send
      ..onResize = (cols, rows, _, _) => _pty?.resize(cols, rows);
    unawaited(_run());
  }

  @override
  void dispose() {
    unawaited(_output?.cancel());
    // Closed while it still runs: the program goes with the sheet.
    if (_running) _pty?.kill();
    _focus.dispose();
    super.dispose();
  }

  void _send(String data) => _pty?.write(utf8.encode(data));

  Future<void> _run() async {
    final command = widget.command;
    try {
      if (widget.makeFolder) {
        await ref.read(aiMakeFolderProvider)(widget.workingDirectory);
      }
      if (!mounted) return;
      final pty = ref
          .read(aiPtyFactoryProvider)
          .spawn(
            ShellCommand(
              executable: command.executable,
              arguments: command.args,
              name: command.executable.split(RegExp(r'[/\\]')).last,
            ),
            workingDirectory: widget.workingDirectory,
            environment: {
              ...command.environment,
              'TERM': 'xterm-256color',
              'COLORTERM': 'truecolor',
            },
            cols: _terminal.viewWidth,
            rows: _terminal.viewHeight,
          );
      _pty = pty;
      _running = true;
      _output = const Utf8Decoder(
        allowMalformed: true,
      ).bind(pty.output).listen(_terminal.write);
      final code = await pty.exitCode;
      if (!identical(_pty, pty)) return;
      _running = false;
      if (!mounted) return;
      if (code == 0) {
        widget.onDone();
      } else {
        setState(() => _failed = code);
      }
    } on Object catch (error) {
      debugPrint('ShellX: run sheet did not start: ${error.runtimeType}');
      if (mounted) setState(() => _failed = -1);
    }
  }

  void _retry() {
    unawaited(_output?.cancel());
    _output = null;
    _pty = null;
    setState(() => _failed = null);
    _terminal.write('\r\n');
    unawaited(_run());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appearance = ref.watch(terminalAppearanceProvider);
    final style = desktopTerminalStyle(
      ref.watch(terminalFontSizeProvider),
      families: appearance.families,
      regular: appearance.regular,
      cellHeightPercent: appearance.cellHeightPercent,
    );
    final failed = _failed;
    return Container(
      key: const Key('ai.runSheet'),
      margin: const EdgeInsets.all(ShellxSpace.s16),
      decoration: BoxDecoration(
        color: ShellxDesktopColors.surface,
        borderRadius: BorderRadius.circular(ShellxRadius.r8),
        border: Border.all(color: ShellxDesktopColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ShellxSpace.s12,
              ShellxSpace.s8,
              ShellxSpace.s4,
              ShellxSpace.s4,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.terminal,
                  size: 16,
                  color: ShellxDesktopColors.accent,
                ),
                const SizedBox(width: ShellxSpace.s6),
                Expanded(
                  child: Text(
                    widget.title,
                    style: ShellxText.bodyStrong.copyWith(
                      color: ShellxDesktopColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('ai.runSheet.close'),
                  tooltip: l10n.actionClose,
                  iconSize: 16,
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s12),
            child: Text(
              l10n.aiRunSheetNote,
              style: ShellxText.small.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: ShellxSpace.s8),
          Expanded(
            child: ColoredBox(
              color: appearance.background,
              child: TerminalView(
                _terminal,
                focusNode: _focus,
                autofocus: true,
                theme: appearance.theme,
                textStyle: style,
                cursorType: appearance.cursor,
                padding: appearance.padding,
              ),
            ),
          ),
          if (failed != null)
            Padding(
              padding: const EdgeInsets.all(ShellxSpace.s8),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 16,
                    color: ShellxDesktopColors.err,
                  ),
                  const SizedBox(width: ShellxSpace.s6),
                  Expanded(
                    child: Text(
                      [
                        ?widget.failureNote,
                        l10n.aiRunSheetFailed(failed),
                      ].join(' '),
                      key: const Key('ai.runSheet.failed'),
                      style: ShellxText.small.copyWith(
                        color: ShellxDesktopColors.err,
                      ),
                    ),
                  ),
                  OutlinedButton(
                    key: const Key('ai.runSheet.retry'),
                    onPressed: _retry,
                    child: Text(l10n.aiRetry),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
```

In `apps/desktop/lib/src/ai/ai_folders.dart`, replace:

```dart
/// D5: what the user typed as a project folder, made absolute: `~` is the
```

with:

```dart
/// D8: makes [path] and its parents. An install's folder
/// (`<support>/ai/agents/<id>`) does not exist before the first install, and
/// npm cannot start in it until it does. A seam, as above.
final aiMakeFolderProvider = Provider<Future<void> Function(String path)>(
  (ref) =>
      (path) => Directory(path).create(recursive: true),
);

/// D5: what the user typed as a project folder, made absolute: `~` is the
```

In `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, replace:

```dart
import 'ai_permission_bar.dart';
import 'ai_scope.dart';
```

with:

```dart
import 'ai_permission_bar.dart';
import 'ai_run_sheet.dart';
import 'ai_scope.dart';
```

In `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, replace:

```dart
    _ui.onChooseFolder = () => setState(() => _choosing = true);
    widget.focusNode?.addListener(_onWindowFocus);
```

with:

```dart
    _ui.onChooseFolder = () => setState(() => _choosing = true);
    _ui.onRun = (request) => unawaited(_run(request));
    widget.focusNode?.addListener(_onWindowFocus);
```

In `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, replace:

```dart
  /// Through the window's action when there is one (it also announces).
  void _zoom() {
```

with:

```dart
  /// D8: a card's sign-in or install, in the run sheet over the
  /// conversation. Exit 0 closes the sheet and the session goes on: a
  /// sign-in reopens the session (`retry`), an install starts the agent and
  /// refreshes Settings › Agents.
  Future<void> _run(AiRunRequest request) async {
    final runtime = _runtime;
    if (runtime == null) return;
    final l10n = AppLocalizations.of(context);
    final name = widget.pane.agentName;
    switch (request) {
      case AiRunLogin(:final method):
        final command = runtime.loginCommand(method);
        if (command == null) return;
        _ui.showOverlay(
          AiRunSheet(
            key: UniqueKey(),
            title: l10n.aiRunSheetLogin(name),
            command: command,
            workingDirectory: runtime.state.cwd,
            failureNote: l10n.aiLoginFailed,
            onDone: () {
              _ui.closeOverlay();
              unawaited(runtime.retry());
            },
            onClose: _ui.closeOverlay,
          ),
        );
      case AiRunInstall():
        final agent = aiAgentById(
          ref.read(aiAgentsProvider),
          widget.pane.agentId,
        );
        if (agent == null) return;
        final readiness = await ref.read(aiReadinessSourceProvider)(agent);
        if (!mounted || !identical(runtime, _runtime)) return;
        final install = readiness is AgentNeedsInstall
            ? readiness.install
            : null;
        if (install == null) {
          // Installed meanwhile, or npm went away: the next start says.
          unawaited(runtime.retry());
          return;
        }
        final folder = install.workingDirectory;
        _ui.showOverlay(
          AiRunSheet(
            key: UniqueKey(),
            title: l10n.aiRunSheetInstall(name),
            command: install,
            workingDirectory: folder ?? runtime.state.cwd,
            makeFolder: folder != null,
            onDone: () {
              _ui.closeOverlay();
              unawaited(ref.read(aiReadinessProvider.notifier).refresh());
              unawaited(runtime.retry());
            },
            onClose: _ui.closeOverlay,
          ),
        );
    }
  }

  /// Through the window's action when there is one (it also announces).
  void _zoom() {
```

- [ ] **Step 4: Run the tests**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/ai lib/src/ui/ai test/ui/ai test/support
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai test/ai test/ui/ai_tab_screens_test.dart 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `All tests passed!` (68 on the scratch copy); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/ui/ai/ai_run_sheet.dart apps/desktop/lib/src/ai/ai_folders.dart apps/desktop/lib/src/ui/ai/ai_pane_view.dart apps/desktop/test/support/ai_fakes.dart apps/desktop/test/ui/ai/ai_run_sheet_test.dart
git commit -m "feat(v2-ai): run sheet — terminal sign-ins and pinned installs in a real terminal, output never read

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 19: Opening AI tabs — ⌘⇧E, the sidebar button, the `+` menu, `new-tab-kind` (D5) [needs V2-1a Task 9]

Spec D5, D23; rulings B8, B11.

**Where "New AI session" comes from:**
- ⌘⇧E / Ctrl+Shift+E and the palette (Task 9's `new_ai_session`);
- a "New AI session" button at the foot of the sidebar. It is not a Tab stop (⌘⇧E is the keyboard's way), so Tab keeps going sidebar → strip → terminal;
- the `+` button's menu (right click, Shift+F10).

**What it opens:** an AI tab, selected, in the current workspace, with the default agent (Task 10, D23).
- **Its folder (D5):** the workspace's project root; else the folder of the tab in front (never a server's path); else none, and the pane asks (Task 17).
- **Instant feedback:** the tab is there in the same frame. Nothing starts until the pane shows (B11).

**`new-tab-kind = ai`:** ⌘T, both `+` buttons (sidebar header and workspace header), the empty window's "Open new tab" and the first tab of a start or an activation (`ensureTab`) open AI sessions.
- **B8:** in a server's workspace they keep opening the server.
- **"New terminal tab"** (`new_terminal_tab`: palette, and the `+` menu while the kind is `ai`) always opens a shell.

**Note:** `dart format` also joins one existing line of `session_sidebar.dart` (the gear's `onPressed`). The file at HEAD is not formatter-stable there; that is not this task's change.

**Files:**
- Create: `apps/desktop/lib/src/ai/ai_open.dart`
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, `apps/desktop/lib/src/remote/ssh_actions.dart`, `apps/desktop/lib/src/terminal/terminal_tabs.dart`, `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, `apps/desktop/lib/src/ui/terminal/sidebar_new_button.dart`
- Test: `apps/desktop/test/ui/ai/ai_open_test.dart`

**Interfaces:**
- Consumes:
  - Task 3 `TerminalTabs.openAiTab`;
  - Task 8 `NewTabKind`, `ShellxConfig.newTabKind`;
  - Task 9 `NewAiSessionIntent`, `NewTerminalTabIntent`, `newAiSessionShortcutLabel()`, strings `aiNewSession`, `aiNewSessionTooltip`, `actionNewTerminalTab`;
  - Task 10 `aiDefaultAgentProvider`;
  - `SidebarWorkspaces.openTabIn/setCollapsed/setRoot/createForHost/workspace`, `Workspace.root/ssh`, `appL10nProvider`.
- Produces:
  - `aiOpenerProvider`: `AiOpener.newSession({String? workspaceId}) → int?`, `AiOpener.newTabIn(String workspaceId)`, `AiOpener.firstTab() → bool`;
  - the window actions for `NewAiSessionIntent` and `NewTerminalTabIntent`;
  - keys `sidebar.newAi`, `menu.new.ai`, `menu.new.terminal`.

- [ ] **Step 1: Write the failing test**

`apps/desktop/test/ui/ai/ai_open_test.dart`:

```dart
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_open.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';

import '../../support/ai_fakes.dart';
import '../../support/config_workspace.dart';

/// V2-1 D5: where AI tabs come from.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<void> chord(
    WidgetTester t,
    LogicalKeyboardKey key, {
    bool shift = false,
  }) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(key);
    if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pumpAndSettle();
  }

  List<TerminalTab> aiTabs(ProviderContainer c) => [
    for (final tab in c.read(terminalTabsProvider).tabs)
      if (tab.isAi) tab,
  ];

  testWidgets('⌘⇧E: an AI tab with the default agent in the workspace\'s '
      'project root, selected and started', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: fakes.overrides,
    );
    w.container
        .read(sidebarWorkspacesProvider.notifier)
        .setRoot(kDefaultWorkspaceId, testAiCwd);
    await chord(t, LogicalKeyboardKey.keyE, shift: true);
    final ai = aiTabs(w.container).single;
    expect(ai.ai!.agentId, 'claude');
    expect(ai.ai!.agentName, 'Claude');
    expect(ai.ai!.title, 'New AI session');
    expect(ai.cwd, testAiCwd);
    expect(w.container.read(terminalTabsProvider).selectedId, ai.id);
    expect(fakes.launcher.channels, hasLength(1));
    // No root: the folder of the tab in front (here the AI tab's).
    w.container
        .read(sidebarWorkspacesProvider.notifier)
        .setRoot(kDefaultWorkspaceId, null);
    await chord(t, LogicalKeyboardKey.keyE, shift: true);
    expect(aiTabs(w.container).map((x) => x.cwd), [testAiCwd, testAiCwd]);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('no root and a shell in front without a folder: the pane '
      'asks for one (D5)', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: fakes.overrides,
    );
    await t.tap(find.byKey(const Key('sidebar.newAi')));
    await t.pumpAndSettle();
    expect(aiTabs(w.container).single.cwd, isNull);
    expect(find.text('Choose a project folder'), findsOneWidget);
    expect(fakes.made, isEmpty);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('new-tab-kind = ai: ⌘T, the + button and an empty start open '
      'AI tabs; "New terminal tab" still opens a shell', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      config: 'new-tab-kind = ai\n',
      extra: fakes.overrides,
    );
    final c = w.container;
    await chord(t, LogicalKeyboardKey.keyT);
    expect(aiTabs(w.container), hasLength(1));
    await t.tap(find.byKey(const Key('sidebar.newTab')));
    await t.pumpAndSettle();
    expect(aiTabs(w.container), hasLength(2));
    final shells = w.local.opens.length;
    await t.tap(
      find.byKey(const Key('sidebar.newTab')),
      buttons: kSecondaryButton,
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('menu.new.ai')), findsOneWidget);
    await t.tap(find.byKey(const Key('menu.new.terminal')));
    await t.pumpAndSettle();
    expect(w.local.opens, hasLength(shells + 1));
    expect(c.read(terminalTabsProvider).selected!.isAi, isFalse);
    // Nothing open: start-up and activation open an AI session too.
    final tabs = c.read(terminalTabsProvider.notifier);
    for (final tab in [...c.read(terminalTabsProvider).tabs]) {
      tabs.close(tab.id);
    }
    await t.pumpAndSettle();
    await tabs.ensureTab();
    await t.pumpAndSettle();
    expect(c.read(terminalTabsProvider).tabs.single.isAi, isTrue);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('B8: in a server\'s workspace a new tab stays on the server '
      'even with new-tab-kind = ai', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      config: 'new-tab-kind = ai\n',
      extra: fakes.overrides,
    );
    final server = w.container
        .read(sidebarWorkspacesProvider.notifier)
        .createForHost(SshTarget.parse('devbox')!);
    await w.container.read(aiOpenerProvider).newTabIn(server);
    await t.pumpAndSettle();
    expect(aiTabs(w.container), isEmpty);
    expect(w.local.openLaunches.last, isA<SshLaunch>());
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('new-tab-kind = terminal (the default): ⌘T and + stay shells; '
      'the + menu offers "New AI session"', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: fakes.overrides,
    );
    await chord(t, LogicalKeyboardKey.keyT);
    expect(aiTabs(w.container), isEmpty);
    await t.tap(
      find.byKey(const Key('sidebar.newTab')),
      buttons: kSecondaryButton,
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('menu.new.terminal')), findsNothing);
    await t.tap(find.byKey(const Key('menu.new.ai')));
    await t.pumpAndSettle();
    expect(aiTabs(w.container), hasLength(1));
    await disposeWorkspace(t, w.container);
  }, variant: mac);
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai/ai_open_test.dart`
Expected: the test does not compile, `Error when reading 'lib/src/ai/ai_open.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/ai/ai_open.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/config_controller.dart' show shellxConfigProvider;
import '../config/shellx_config.dart' show NewTabKind;
import '../terminal/local_sessions_provider.dart' show appL10nProvider;
import '../terminal/sidebar_workspaces.dart';
import '../terminal/terminal_tabs.dart';
import 'ai_agents.dart';

/// V2-1 D5: how AI tabs open — "New AI session", and "a new tab" when
/// `new-tab-kind = ai`.
final aiOpenerProvider = Provider<AiOpener>(AiOpener.new);

final class AiOpener {
  AiOpener(this._ref);
  final Ref _ref;

  /// "New AI session" (⌘⇧E, the sidebar's button, the `+` menu, the
  /// palette): an AI tab, selected, in workspace [workspaceId] (by default
  /// the current one), with the default agent (D23). Its folder is the
  /// workspace's project root, else the folder of the tab in front (never a
  /// server's), else none: the pane asks for one (D5). Nothing starts until
  /// the pane shows (B11). Returns the tab's id; null when no agent is
  /// offered.
  int? newSession({String? workspaceId}) {
    final side = _ref.read(sidebarWorkspacesProvider);
    final id = workspaceId ?? side.currentId;
    final agent = _ref.read(aiDefaultAgentProvider);
    if (agent == null) return null;
    final selected = _ref.read(terminalTabsProvider).selected;
    final front = selected == null
        ? null
        : selected.isAi
        ? selected.ai?.cwd
        : (selected.focused?.remote == null ? selected.focused?.cwd : null);
    _ref.read(sidebarWorkspacesProvider.notifier).setCollapsed(id, false);
    return _ref
        .read(terminalTabsProvider.notifier)
        .openAiTab(
          agentId: agent.id,
          agentName: agent.name,
          title: _ref.read(appL10nProvider).aiNewSession,
          cwd: side.workspace(id)?.root ?? front,
          workspace: id,
        );
  }

  /// D5: "a new tab" in workspace [workspaceId] (⌘T, the `+` buttons, the
  /// empty window): an AI session when `new-tab-kind = ai` and the
  /// workspace is on this computer (B8: a server's workspace keeps opening
  /// its server), else a terminal tab.
  Future<void> newTabIn(String workspaceId) async {
    if (_wantsAi(workspaceId) && newSession(workspaceId: workspaceId) != null) {
      return;
    }
    await _ref.read(sidebarWorkspacesProvider.notifier).openTabIn(workspaceId);
  }

  /// D5, D11: the tab that start-up and activation open when there is none,
  /// under the same rule. False: the caller opens a terminal tab.
  bool firstTab() {
    if (!_aiKind) return false;
    final id = _ref.read(sidebarWorkspacesProvider).currentId;
    return _wantsAi(id) && newSession(workspaceId: id) != null;
  }

  bool get _aiKind =>
      _ref.read(shellxConfigProvider).config.newTabKind == NewTabKind.ai;

  bool _wantsAi(String workspaceId) {
    if (!_aiKind) return false;
    final w = _ref.read(sidebarWorkspacesProvider).workspace(workspaceId);
    return w != null && w.ssh == null;
  }
}
```

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

```dart
import '../../agent/agent_state.dart';
import '../../config/config_controller.dart';
```

with:

```dart
import '../../agent/agent_state.dart';
import '../../ai/ai_open.dart';
import '../../config/config_controller.dart';
```

In `apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart`, replace:

```dart
      NewTabIntent: run<NewTabIntent>((_) {
        closePanel();
        unawaited(ref.read(sshActionsProvider).newTab());
        focusTerminal();
      }),
```

with:

```dart
      NewTabIntent: run<NewTabIntent>((_) {
        closePanel();
        unawaited(ref.read(sshActionsProvider).newTab());
        focusTerminal();
      }),
      // V2-1 D5: ⌘⇧E, the sidebar's button, the `+` menu, the palette.
      NewAiSessionIntent: run<NewAiSessionIntent>((_) {
        closePanel();
        ref.read(aiOpenerProvider).newSession();
        focusTerminal();
      }),
      // V2-1 D5: a terminal tab, whatever `new-tab-kind` says.
      NewTerminalTabIntent: run<NewTerminalTabIntent>((_) {
        closePanel();
        unawaited(
          workspaces.openTabIn(ref.read(sidebarWorkspacesProvider).currentId),
        );
        focusTerminal();
      }),
```

In `apps/desktop/lib/src/remote/ssh_actions.dart`, replace:

```dart
import '../agent/agent_controller_base.dart';
import '../platform/settings_store.dart';
```

with:

```dart
import '../agent/agent_controller_base.dart';
import '../ai/ai_open.dart';
import '../platform/settings_store.dart';
```

In `apps/desktop/lib/src/remote/ssh_actions.dart`, replace:

```dart
  /// ⌘T, sidebar `+` (D23). Opens in the current workspace so its SSH
  /// target (D23) or local project root (cmux gap 36) both apply.
  Future<void> newTab() =>
      _side.openTabIn(_ref.read(sidebarWorkspacesProvider).currentId);
```

with:

```dart
  /// ⌘T, sidebar `+` (D23). Opens in the current workspace so its SSH
  /// target (D23) or local project root (cmux gap 36) both apply. V2-1 D5:
  /// an AI session there when `new-tab-kind = ai` (not on a server, B8).
  Future<void> newTab() => _ref
      .read(aiOpenerProvider)
      .newTabIn(_ref.read(sidebarWorkspacesProvider).currentId);
```

In `apps/desktop/lib/src/terminal/terminal_tabs.dart`, replace:

```dart
import '../ai/ai_pane_state.dart';
```

with:

```dart
import '../ai/ai_open.dart' show aiOpenerProvider;
import '../ai/ai_pane_state.dart';
```

In `apps/desktop/lib/src/terminal/terminal_tabs.dart`, replace:

```dart
    if (state.tabs.isEmpty && !state.opening) await openTab();
  }
```

with:

```dart
    if (state.tabs.isEmpty && !state.opening) {
      // V2-1 D5: an AI session when `new-tab-kind = ai`.
      if (_ref.read(aiOpenerProvider).firstTab()) return;
      await openTab();
    }
  }
```

In `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, replace:

```dart
import '../../agent/desktop_services.dart' show desktopServicesProvider;
```

with:

```dart
import '../../agent/desktop_services.dart' show desktopServicesProvider;
import '../../ai/ai_open.dart';
```

In `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, replace:

```dart
      case _HeaderAction.newTab:
        await workspaces.openTabIn(w.id);
```

with:

```dart
      case _HeaderAction.newTab:
        await ref.read(aiOpenerProvider).newTabIn(w.id);
```

In `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, replace:

```dart
              onNewTab: () => unawaited(workspaces.openTabIn(w.id)),
```

with:

```dart
              onNewTab: () =>
                  unawaited(ref.read(aiOpenerProvider).newTabIn(w.id)),
```

In `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, replace:

```dart
                          child: MouseRegion(
                            cursor: SystemMouseCursors.grabbing,
                            opaque: false,
                            hitTestBehavior: HitTestBehavior.translucent,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

with:

```dart
                          child: MouseRegion(
                            cursor: SystemMouseCursors.grabbing,
                            opaque: false,
                            hitTestBehavior: HitTestBehavior.translucent,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // V2-1 D5: "New AI session" at the foot of the sidebar. Not a Tab
          // stop (⌘⇧E is the keyboard's way): Tab keeps going sidebar →
          // strip → terminal.
          FocusTraversalGroup(
            descendantsAreTraversable: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                ShellxSpace.s8,
                ShellxSpace.s4,
                ShellxSpace.s8,
                ShellxSpace.s8,
              ),
              child: Tooltip(
                message: switch (newAiSessionShortcutLabel()) {
                  final shortcut? => l10n.aiNewSessionTooltip(shortcut),
                  null => l10n.aiNewSession,
                },
                child: TextButton.icon(
                  key: const Key('sidebar.newAi'),
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    foregroundColor: ShellxDesktopColors.textSecondary,
                  ),
                  onPressed: () =>
                      Actions.maybeInvoke(context, const NewAiSessionIntent()),
                  icon: const Icon(Icons.auto_awesome, size: 14),
                  label: Text(l10n.aiNewSession),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

In `apps/desktop/lib/src/ui/terminal/sidebar_new_button.dart`, replace:

```dart
import '../../../l10n/app_localizations.dart';
import '../../remote/ssh_actions.dart';
```

with:

```dart
import '../../../l10n/app_localizations.dart';
import '../../config/config_controller.dart' show shellxConfigProvider;
import '../../config/shellx_config.dart' show NewTabKind;
import '../../remote/ssh_actions.dart';
```

In `apps/desktop/lib/src/ui/terminal/sidebar_new_button.dart`, replace:

```dart
import 'shortcut_labels.dart';
import 'terminal_overlays.dart';

enum _NewAction { tab, ssh, tmux }
```

with:

```dart
import 'shortcut_labels.dart';
import 'terminal_intents.dart';
import 'terminal_overlays.dart';

enum _NewAction { tab, ai, terminal, ssh, tmux }
```

In `apps/desktop/lib/src/ui/terminal/sidebar_new_button.dart`, replace:

```dart
          label: l10n.terminalNewTab,
          shortcut: newTabShortcutLabel(),
        ),
        ShellxMenuEntry(
          key: const Key('menu.new.ssh'),
```

with:

```dart
          label: l10n.terminalNewTab,
          shortcut: newTabShortcutLabel(),
        ),
        // V2-1 D5: an AI session; a terminal tab while "a new tab" is one.
        ShellxMenuEntry(
          key: const Key('menu.new.ai'),
          value: _NewAction.ai,
          label: l10n.aiNewSession,
          shortcut: newAiSessionShortcutLabel(),
        ),
        if (ai)
          ShellxMenuEntry(
            key: const Key('menu.new.terminal'),
            value: _NewAction.terminal,
            label: l10n.actionNewTerminalTab,
          ),
        ShellxMenuEntry(
          key: const Key('menu.new.ssh'),
```

In `apps/desktop/lib/src/ui/terminal/sidebar_new_button.dart`, replace:

```dart
  Future<void> _menu(BuildContext context, WidgetRef ref, Offset at) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showShellxMenu<_NewAction>(
```

with:

```dart
  Future<void> _menu(BuildContext context, WidgetRef ref, Offset at) async {
    final l10n = AppLocalizations.of(context);
    final ai =
        ref.read(shellxConfigProvider).config.newTabKind == NewTabKind.ai;
    final choice = await showShellxMenu<_NewAction>(
```

In `apps/desktop/lib/src/ui/terminal/sidebar_new_button.dart`, replace:

```dart
      case _NewAction.tab:
        unawaited(ref.read(sshActionsProvider).newTab());
```

with:

```dart
      case _NewAction.tab:
        unawaited(ref.read(sshActionsProvider).newTab());
      case _NewAction.ai:
        if (context.mounted) {
          Actions.maybeInvoke(context, const NewAiSessionIntent());
        }
      case _NewAction.terminal:
        if (context.mounted) {
          Actions.maybeInvoke(context, const NewTerminalTabIntent());
        }
```

- [ ] **Step 4: Run the whole suite**

The sidebar gains a row and the tab list a new first-tab rule: run everything.

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/ai lib/src/ui/terminal lib/src/remote/ssh_actions.dart lib/src/terminal/terminal_tabs.dart test/ui/ai
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `All other tests passed!` (3 204 passing, 10 skipped on the scratch copy); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/ai/ai_open.dart apps/desktop/lib/src/ui/terminal/terminal_workspace_page.dart apps/desktop/lib/src/remote/ssh_actions.dart apps/desktop/lib/src/terminal/terminal_tabs.dart apps/desktop/lib/src/ui/terminal/session_sidebar.dart apps/desktop/lib/src/ui/terminal/sidebar_new_button.dart apps/desktop/test/ui/ai/ai_open_test.dart
git commit -m "feat(v2-ai): open AI tabs — ⌘⇧E, sidebar button, + menu, new-tab-kind (servers keep their shells)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 20: The Changes panel and undo — this turn, the whole session, the dialog (§4.4, D12, B14) [needs V2-1a Task 9]

Spec §4.4, D12, §6 (two tabs on one project); rulings B14, B16.

**The panel:** the header's "Changes and files" button opens the right panel (268 px). Its Changes tab shows:
- "This turn | Whole session".
- One row per file: M/A/D, the path with its folder dimmed, +/− (or "Binary file"), "Reviewed" (B16), "Revert this file", and "changed after the turn" in `warn` when the file changed after the turn ended. Another tab on the same project shows that way too.
- A row opens its diff over the conversation: the file before the turn (or the session) against the disk now. Over 2 000 lines the diff runs off the UI isolate. "Open in editor" uses `link-editor`, now shared with the tool cards (`aiOpenInEditor`).
- At the foot: "Restore point: before turn N · <hash>", "Revert turn" / "Revert session", the last result ("Reverted 2 files."), and the `.gitignore` and outside-the-folder notes.
- The panel reloads when a turn starts or ends, on a scope switch and after a revert.

**Undo:**
- **The dialog (B14):** files changed after the turn ended ask first, in a three-button dialog: Cancel (the first focus), "Only revert unchanged files" (only when some are unchanged), and "Revert all" (destructive).
- **"Revert turn" on a turn summary** runs the same flow and opens the panel.
- **While a turn runs:** reverting waits ("Wait for the running turn to finish."); the runtime refuses it too.

**Files:**
- Create: `apps/desktop/lib/src/ai/ai_project_files.dart`, `apps/desktop/lib/src/ui/ai/ai_editor.dart`, `apps/desktop/lib/src/ui/ai/ai_changes_panel.dart`, `apps/desktop/lib/src/ui/ai/ai_diff_overlay.dart`, `apps/desktop/lib/src/ui/ai/ai_side_panel.dart`, `apps/desktop/test/support/fake_project.dart`
- Modify: `apps/desktop/lib/src/ui/ai/ai_scope.dart`, `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, `apps/desktop/lib/src/ui/ai/ai_tool_card.dart`
- Test: `apps/desktop/test/ui/ai/ai_changes_test.dart`

**Interfaces:**
- Consumes:
  - V2-1a `AiRuntime.changesSince(int)`, `sessionChanges()`, `changedAfterTurn(int)`, `revert(int, Iterable<String>)`, `revertSession(Iterable<String>)`, `fileBefore(int, String)`, `checkpointOf(int)`;
  - V2-1a `Checkpoints` (the fake implements it), `FileChange`, `ChangeKind`, `Checkpoint`, `TurnEndItem.checkpoint`, `ActiveTurn.checkpoint`;
  - Task 13 `lineDiff`, `withContext`, `AiDiffView`; Task 14 `AiTurnSummary` (`onRevertTurn`, `openPanel`); Task 17 `AiHeader.onPanel/panelOpen`.
- Produces:
  - the seam: `aiProjectFilesProvider` (`AiProjectFiles.read(String path) → Future<AiFileContent>`: `AiFileText` / `AiFileBinary` / `AiFileTooLarge` / `AiFileMissing`), `aiFileContentOf(List<int>?)`, `kAiFileViewMax`;
  - the panel: `AiSidePanel({Widget? files})`, `AiChangesPanel`, `AiDiffOverlay({path, turn, session})`;
  - undo: `aiRevert(context, runtime, ui, {int? turn, String? only})`, `showAiRevertDialog`, `AiRevertChoice`, `aiTurnsOf`, `AiTurns`, `aiReviewKey`, `aiOpenInEditor(WidgetRef, path, cwd)`;
  - `AiPaneUi.panelTab/showTab/note/changes/reviewed/changesChanged`, `enum AiPanelTab`;
  - test support: `FakeProject`;
  - keys `ai.sidePanel`, `ai.change.<path>`, `ai.changes.turn|session|revert|note|checkpoint`, `ai.diff`, `ai.diff.close`, `ai.diff.note`, `ai.revert.cancel|clean|all`.

- [ ] **Step 1: Write the failing test**

`apps/desktop/test/support/fake_project.dart`:

```dart
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_desktop/src/ai/ai_project_files.dart';

/// A project in memory: its files ([files], path relative to [root] →
/// text), its restore points (V2-1a `Checkpoints`) and the reader the pane
/// uses (`AiProjectFiles`). Nothing touches the disk or git.
final class FakeProject implements Checkpoints, AiProjectFiles {
  FakeProject(this.root, Map<String, String> files) : files = {...files};

  final String root;

  /// The project as it is now.
  final Map<String, String> files;

  /// Runs right after each restore point is taken, with its ref
  /// (`<session>/<turn>`): what the agent does during that turn.
  void Function(String ref)? onSnapshot;

  /// Every restore: (commit, paths).
  final restored = <(String, List<String>)>[];

  final _trees = <String, Map<String, String>>{};
  var _n = 0;

  @override
  UndoOff? off;

  String _keep() {
    final tree = 't${_n++}';
    _trees[tree] = {...files};
    return tree;
  }

  @override
  Future<Checkpoint?> snapshot(String ref) async {
    final tree = _keep();
    onSnapshot?.call(ref);
    return Checkpoint(commit: 'c$tree', tree: tree);
  }

  @override
  Future<String?> currentTree() async => _keep();

  Map<String, String> _tree(String treeish) =>
      _trees[treeish.startsWith('c') ? treeish.substring(1) : treeish]!;

  @override
  Future<List<FileChange>> changes(String fromTree, [String? toTree]) async {
    final from = _tree(fromTree);
    final to = toTree == null ? files : _tree(toTree);
    int lines(String? s) =>
        s == null || s.isEmpty ? 0 : '\n'.allMatches(s).length;
    return [
      for (final path in {...from.keys, ...to.keys}.toList()..sort())
        if (from[path] != to[path])
          FileChange(
            path: path,
            kind: !from.containsKey(path)
                ? ChangeKind.added
                : !to.containsKey(path)
                ? ChangeKind.deleted
                : ChangeKind.modified,
            added: lines(to[path]),
            removed: lines(from[path]),
          ),
    ];
  }

  @override
  Future<Set<String>> changedSince(String tree) async {
    final then = _tree(tree);
    return {
      for (final path in {...then.keys, ...files.keys})
        if (then[path] != files[path]) path,
    };
  }

  @override
  Future<List<int>?> fileAt(String treeish, String path) async {
    final text = _tree(treeish)[path];
    return text == null ? null : utf8.encode(text);
  }

  @override
  Future<void> restore(String treeish, Iterable<String> paths) async {
    final then = _tree(treeish);
    final list = [...paths];
    for (final path in list) {
      final text = then[path];
      if (text == null) {
        files.remove(path);
      } else {
        files[path] = text;
      }
    }
    restored.add((treeish, list));
  }

  @override
  Future<AiFileContent> read(String path) async {
    final text = files[p.relative(path, from: root)];
    return text == null ? const AiFileMissing() : AiFileText(text);
  }
}
```

`apps/desktop/test/ui/ai/ai_changes_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_project_files.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_tabs.dart';
import '../../support/config_workspace.dart';
import '../../support/fake_project.dart';

/// V2-1 §4.4, D12, B14: the Changes panel and undo.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  /// A project where turn 1 edits `lib/a.dart`, adds `new.txt` and deletes
  /// `old.txt` (what the agent did, as the restore points see it).
  FakeProject project() =>
      FakeProject(testAiCwd, {'lib/a.dart': 'one\n', 'old.txt': 'gone\n'})
        ..onSnapshot = null;

  Future<(ProviderContainer, FakeAiRuntimes)> afterTurn(
    WidgetTester t,
    FakeProject files, {
    List<List<Map<String, Object?>>>? turns,
  }) async {
    files.onSnapshot = (ref) {
      if (!ref.endsWith('/1')) return;
      files.files
        ..['lib/a.dart'] = 'one\ntwo\n'
        ..['new.txt'] = 'hi\n'
        ..remove('old.txt');
    };
    final fakes = FakeAiRuntimes(
      FakeScenario(
        turns:
            turns ??
            [
              [FakeSteps.text('Done.')],
            ],
      ),
      checkpoints: files,
    );
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: [
        ...fakes.overrides,
        aiProjectFilesProvider.overrideWithValue(files),
      ],
    );
    final c = w.container;
    openTestAiTab(c, cwd: testAiCwd);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('ai.composer')), 'go');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    if (turns == null) {
      await t.pumpAndSettle();
    } else {
      for (var i = 0; i < 5; i++) {
        await t.pump();
      }
    }
    return (c, fakes);
  }

  testWidgets('the panel lists this turn\'s files (M/A/D, +/−), shows a '
      'diff, and the restore point', (t) async {
    final files = project();
    final (c, _) = await afterTurn(t, files);
    expect(find.text('Turn 1 · 0:00 · 3 files changed'), findsOneWidget);
    await t.tap(find.byKey(const Key('ai.panel')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.sidePanel')), findsOneWidget);
    for (final path in ['lib/a.dart', 'new.txt', 'old.txt']) {
      expect(find.byKey(ValueKey('ai.change.$path')), findsOneWidget);
    }
    expect(find.text('Restore point: before turn 1 · ct1'), findsOneWidget);
    expect(find.text('Revert turn'), findsWidgets);
    await t.tap(find.byKey(const ValueKey('ai.change.lib/a.dart')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.diff')), findsOneWidget);
    expect(find.text('compared with the start of the turn'), findsOneWidget);
    await t.tap(find.byKey(const Key('ai.diff.close')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.diff')), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('B14: a file changed after the turn asks first, Cancel has '
      'the focus; "Only revert unchanged files" keeps it', (t) async {
    final files = project();
    final (c, _) = await afterTurn(t, files);
    files.files['new.txt'] = 'mine\n';
    await t.tap(find.byKey(const Key('ai.turn.revert')));
    await t.pumpAndSettle();
    expect(find.text('Some files changed after this turn'), findsOneWidget);
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(
      focused.findAncestorWidgetOfExactType<TextButton>()?.key,
      const Key('ai.revert.cancel'),
    );
    await t.tap(find.byKey(const Key('ai.revert.clean')));
    await t.pumpAndSettle();
    expect(files.restored.single.$2, ['lib/a.dart', 'old.txt']);
    expect(files.files, {
      'lib/a.dart': 'one\n',
      'old.txt': 'gone\n',
      'new.txt': 'mine\n',
    });
    expect(find.text('Reverted 2 files.'), findsOneWidget);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('one file reverts alone; "Reviewed" stays with an unchanged '
      'file; "Whole session" reverts the session', (t) async {
    final files = project();
    final (c, _) = await afterTurn(t, files);
    await t.tap(find.byKey(const Key('ai.panel')));
    await t.pumpAndSettle();
    final row = find.byKey(const ValueKey('ai.change.lib/a.dart'));
    await t.tap(find.descendant(of: row, matching: find.byType(Checkbox)));
    await t.pumpAndSettle();
    await t.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ai.change.new.txt')),
        matching: find.byIcon(Icons.undo),
      ),
    );
    await t.pumpAndSettle();
    expect(files.restored.single.$2, ['new.txt']);
    expect(files.files.containsKey('new.txt'), isFalse);
    expect(find.byKey(const ValueKey('ai.change.new.txt')), findsNothing);
    expect(
      t
          .widget<Checkbox>(
            find.descendant(of: row, matching: find.byType(Checkbox)),
          )
          .value,
      isTrue,
    );
    await t.tap(find.byKey(const Key('ai.changes.session')));
    await t.pumpAndSettle();
    expect(find.text('Revert session'), findsOneWidget);
    await t.tap(find.byKey(const Key('ai.changes.revert')));
    await t.pumpAndSettle();
    expect(files.files, {'lib/a.dart': 'one\n', 'old.txt': 'gone\n'});
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('while a turn runs the changes show but revert waits', (t) async {
    final files = project();
    final (c, _) = await afterTurn(
      t,
      files,
      turns: [
        [FakeSteps.waitCancel()],
      ],
    );
    await t.tap(find.byKey(const Key('ai.panel')));
    await t.pump();
    await t.pump();
    expect(find.byKey(const ValueKey('ai.change.new.txt')), findsOneWidget);
    expect(find.text('Wait for the running turn to finish.'), findsOneWidget);
    expect(
      t
          .widget<OutlinedButton>(find.byKey(const Key('ai.changes.revert')))
          .onPressed,
      isNull,
    );
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    await t.pump();
    await disposeWorkspace(t, c);
  }, variant: mac);
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai/ai_changes_test.dart`
Expected: the test does not compile, `Error when reading 'lib/src/ai/ai_project_files.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/ai/ai_project_files.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a file holds, as the AI pane shows it (§4.4).
sealed class AiFileContent {
  const AiFileContent();
}

final class AiFileText extends AiFileContent {
  const AiFileText(this.text);
  final String text;

  @override
  String toString() => '…';
}

/// A NUL byte in its first 8 000 bytes (git's own test): "Binary file".
final class AiFileBinary extends AiFileContent {
  const AiFileBinary();
}

/// Over [kAiFileViewMax]: "Too large to show".
final class AiFileTooLarge extends AiFileContent {
  const AiFileTooLarge();
}

/// Not there: deleted, or added after the restore point.
final class AiFileMissing extends AiFileContent {
  const AiFileMissing();
}

/// The largest file the viewer and the diffs show (1 MiB).
const int kAiFileViewMax = 1 << 20;

/// [bytes] as the pane shows them; null: missing.
AiFileContent aiFileContentOf(List<int>? bytes) {
  if (bytes == null) return const AiFileMissing();
  if (bytes.length > kAiFileViewMax) return const AiFileTooLarge();
  final head = bytes.length < 8000 ? bytes.length : 8000;
  for (var i = 0; i < head; i++) {
    if (bytes[i] == 0) return const AiFileBinary();
  }
  return AiFileText(utf8.decode(bytes, allowMalformed: true));
}

/// The project's files as the AI pane reads them (the diff of a change, the
/// viewer). A seam: widget tests never touch the disk under fake async.
abstract interface class AiProjectFiles {
  /// The file at [path] (absolute).
  Future<AiFileContent> read(String path);
}

final class DiskProjectFiles implements AiProjectFiles {
  const DiskProjectFiles();

  @override
  Future<AiFileContent> read(String path) async {
    try {
      final file = File(path);
      if (await file.length() > kAiFileViewMax) return const AiFileTooLarge();
      return aiFileContentOf(await file.readAsBytes());
    } on FileSystemException {
      return const AiFileMissing();
    }
  }
}

final aiProjectFilesProvider = Provider<AiProjectFiles>(
  (ref) => const DiskProjectFiles(),
);
```

`apps/desktop/lib/src/ui/ai/ai_editor.dart`:

```dart
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../agent/desktop_services.dart';
import '../../config/config_controller.dart' show shellxConfigProvider;
import '../../platform/editor_links.dart';
import '../terminal/link_layer.dart' show editorDetectorProvider;

/// "Open in editor" (§4.2, §4.4): [path] (relative to [cwd] unless it is
/// absolute) in the editor `link-editor` picks (A10), else shown in the
/// file manager. Never throws; logs only the error's type.
Future<void> aiOpenInEditor(WidgetRef ref, String path, String cwd) async {
  final abs = p.isAbsolute(path) ? path : p.join(cwd, path);
  final opener = ref.read(desktopServicesProvider).urlOpener;
  try {
    final editor = await editorFor(
      ref.read(shellxConfigProvider).config.linkEditor,
      ref.read(editorDetectorProvider),
    );
    if (editor != null) {
      await opener.openInEditor(editor, abs);
    } else {
      await opener.reveal(abs, isDirectory: false);
    }
  } on Object catch (error) {
    debugPrint('ShellX: editor not opened: ${error.runtimeType}');
  }
}
```

`apps/desktop/lib/src/ui/ai/ai_changes_panel.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../../l10n/app_localizations.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_diff_overlay.dart';
import 'ai_scope.dart';

/// "This turn" or "Whole session" (§4.4).
enum AiChangesScope { turn, session }

/// The session's turns that have a restore point: the first, the last (the
/// running one counts), the last finished one; and whether a turn runs.
typedef AiTurns = ({int? first, int? last, int? lastFinished, bool running});

AiTurns aiTurnsOf(AiSessionState s) {
  int? first, last, lastFinished;
  for (final item in s.timeline.items) {
    if (item is TurnEndItem && item.checkpoint != null) {
      first ??= item.turn;
      last = item.turn;
      lastFinished = item.turn;
    }
  }
  final running = s.turn;
  if (running != null && running.checkpoint != null) {
    first ??= running.index;
    last = running.index;
  }
  return (
    first: first,
    last: last,
    lastFinished: lastFinished,
    running: running != null,
  );
}

/// B14: what the undo dialog chose.
enum AiRevertChoice { onlyUnchanged, all }

/// B14, §4.4: "Some files changed after this turn" — Cancel (the first
/// focus) / Only revert unchanged files / Revert all (destructive). The
/// middle choice shows only when some files are unchanged.
Future<AiRevertChoice?> showAiRevertDialog(
  BuildContext context, {
  required List<String> touched,
  required bool someUnchanged,
}) => showDialog<AiRevertChoice>(
  context: context,
  builder: (context) {
    final l10n = AppLocalizations.of(context);
    final names = touched.length <= 3
        ? touched.join(', ')
        : '${touched.take(3).join(', ')}…';
    return AlertDialog(
      title: Text(l10n.aiRevertDialogTitle),
      content: Text(l10n.aiRevertDialogBody(names)),
      actions: [
        TextButton(
          key: const Key('ai.revert.cancel'),
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        if (someUnchanged)
          OutlinedButton(
            key: const Key('ai.revert.clean'),
            onPressed: () =>
                Navigator.of(context).pop(AiRevertChoice.onlyUnchanged),
            child: Text(l10n.aiRevertOnlyClean),
          ),
        FilledButton(
          key: const Key('ai.revert.all'),
          style: destructiveButtonStyle(),
          onPressed: () => Navigator.of(context).pop(AiRevertChoice.all),
          child: Text(l10n.aiRevertAll),
        ),
      ],
    );
  },
);

/// "Revert turn" [turn], "Revert session" ([turn] null), or one file
/// ([only]), §4.4: the files changed since the restore point go back. Files
/// changed after the turn ended ask first (B14). Refused while a turn runs.
/// The result shows at the foot of the Changes panel, which opens.
Future<void> aiRevert(
  BuildContext context,
  AiRuntime runtime,
  AiPaneUi ui, {
  int? turn,
  String? only,
}) async {
  final l10n = AppLocalizations.of(context);
  ui.openPanel();
  if (runtime.state.turn != null) {
    ui.note.value = l10n.aiRevertBusy;
    return;
  }
  final last = turn ?? aiTurnsOf(runtime.state).lastFinished;
  final changes = turn == null
      ? await runtime.sessionChanges()
      : await runtime.changesSince(turn);
  var paths = [
    for (final c in changes ?? const <FileChange>[])
      if (only == null || c.path == only) c.path,
  ];
  if (paths.isEmpty) return;
  final after = last == null
      ? const <String>{}
      : await runtime.changedAfterTurn(last) ?? const <String>{};
  final touched = [
    for (final path in paths)
      if (after.contains(path)) path,
  ];
  if (touched.isNotEmpty) {
    if (!context.mounted) return;
    final choice = await showAiRevertDialog(
      context,
      touched: touched,
      someUnchanged: touched.length < paths.length,
    );
    if (choice == null) return;
    if (choice == AiRevertChoice.onlyUnchanged) {
      paths = [
        for (final path in paths)
          if (!after.contains(path)) path,
      ];
    }
  }
  var ok = false;
  try {
    ok = turn == null
        ? await runtime.revertSession(paths)
        : await runtime.revert(turn, paths);
  } on Object catch (error) {
    debugPrint('ShellX: revert failed: ${error.runtimeType}');
  }
  ui.note.value = ok ? l10n.aiReverted(paths.length) : l10n.aiRevertFailed;
  ui.changesChanged();
}

/// "Reviewed" (§4.4) belongs to a file as it is: a change with other
/// counts is another review (ruling B16).
String aiReviewKey(FileChange c) =>
    '${c.path}\u0000${c.kind.name}\u0000${c.added}\u0000${c.removed}';

/// The Changes tab (spec §4.4): this turn's or the whole session's files,
/// each with M/A/D, its folder dimmed, +/−, "Reviewed", "Revert this file"
/// and "changed after the turn"; the restore point and "Revert turn" /
/// "Revert session" at the foot. A row opens its diff over the
/// conversation. It reloads when a turn starts or ends and after a revert.
class AiChangesPanel extends StatefulWidget {
  const AiChangesPanel({super.key});

  @override
  State<AiChangesPanel> createState() => _AiChangesPanelState();
}

class _AiChangesPanelState extends State<AiChangesPanel> {
  var _scope = AiChangesScope.turn;
  AiPaneScope? _pane;
  AiTurns? _turns;
  List<FileChange>? _changes;
  Set<String> _after = const {};
  var _loaded = false;
  var _gen = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pane = AiPaneScope.of(context);
    if (!identical(pane.frames, _pane?.frames)) {
      _pane?.frames.removeListener(_onFrame);
      _pane?.ui.changes.removeListener(_reload);
      pane.frames.addListener(_onFrame);
      pane.ui.changes.addListener(_reload);
      _pane = pane;
      _turns = aiTurnsOf(pane.state);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }
    _pane = pane;
  }

  @override
  void dispose() {
    _pane?.frames.removeListener(_onFrame);
    _pane?.ui.changes.removeListener(_reload);
    super.dispose();
  }

  void _onFrame() {
    final next = aiTurnsOf(_pane!.state);
    if (next == _turns) return;
    _turns = next;
    unawaited(_load());
  }

  void _reload() => unawaited(_load());

  int? get _turn =>
      _scope == AiChangesScope.turn ? _turns?.last : _turns?.first;

  Future<void> _load() async {
    final gen = ++_gen;
    final pane = _pane!;
    final turns = _turns!;
    final turn = _turn;
    if (turn == null) {
      setState(() {
        _loaded = true;
        _changes = null;
        _after = const {};
      });
      return;
    }
    final runtime = pane.runtime;
    final changes = _scope == AiChangesScope.turn
        ? await runtime.changesSince(turn)
        : await runtime.sessionChanges();
    final last = _scope == AiChangesScope.turn ? turn : turns.lastFinished;
    final after = last == null ? null : await runtime.changedAfterTurn(last);
    if (!mounted || gen != _gen) return;
    setState(() {
      _loaded = true;
      _changes = changes;
      _after = after ?? const {};
    });
  }

  void _open(FileChange c) {
    final pane = _pane!;
    final turn = _turn;
    if (turn == null) return;
    pane.ui.showOverlay(
      AiDiffOverlay(
        key: ValueKey('ai.diff.${c.path}'),
        path: c.path,
        turn: turn,
        session: _scope == AiChangesScope.session,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pane = _pane!;
    final turns = _turns!;
    final turn = _turn;
    final changes = _changes;
    final dim = ShellxText.caption.copyWith(
      color: ShellxDesktopColors.textSecondary,
    );
    final Widget body;
    if (!_loaded) {
      body = const SizedBox.shrink();
    } else if (turn == null || changes == null) {
      body = Padding(
        padding: const EdgeInsets.all(ShellxSpace.s12),
        child: Text(l10n.aiChangesNoTurn, style: dim),
      );
    } else if (changes.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(ShellxSpace.s12),
        child: Text(l10n.aiChangesEmpty, style: dim),
      );
    } else {
      body = ListView.builder(
        itemCount: changes.length,
        itemBuilder: (context, i) {
          final c = changes[i];
          final key = aiReviewKey(c);
          return _ChangeRow(
            key: ValueKey('ai.change.${c.path}'),
            change: c,
            after: _after.contains(c.path),
            reviewed: pane.ui.reviewed.contains(key),
            onOpen: () => _open(c),
            onReviewed: (on) => setState(
              () =>
                  on ? pane.ui.reviewed.add(key) : pane.ui.reviewed.remove(key),
            ),
            onRevert: () => unawaited(
              aiRevert(
                context,
                pane.runtime,
                pane.ui,
                turn: _scope == AiChangesScope.turn ? turn : null,
                only: c.path,
              ),
            ),
          );
        },
      );
    }
    final checkpoint = turn == null ? null : pane.runtime.checkpointOf(turn);
    final canRevert =
        !turns.running && checkpoint != null && (changes?.isNotEmpty ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(ShellxSpace.s8),
          child: SegmentedButton<AiChangesScope>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: AiChangesScope.turn,
                label: Text(
                  l10n.aiScopeTurn,
                  key: const Key('ai.changes.turn'),
                ),
              ),
              ButtonSegment(
                value: AiChangesScope.session,
                label: Text(
                  l10n.aiScopeSession,
                  key: const Key('ai.changes.session'),
                ),
              ),
            ],
            selected: {_scope},
            onSelectionChanged: (s) {
              setState(() => _scope = s.single);
              unawaited(_load());
            },
          ),
        ),
        Expanded(child: body),
        const Divider(height: 1, color: ShellxDesktopColors.line),
        Padding(
          padding: const EdgeInsets.all(ShellxSpace.s8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (turn != null && checkpoint != null)
                Text(
                  l10n.aiCheckpoint(
                    turn,
                    checkpoint.commit.length > 7
                        ? checkpoint.commit.substring(0, 7)
                        : checkpoint.commit,
                  ),
                  key: const Key('ai.changes.checkpoint'),
                  style: dim,
                ),
              const SizedBox(height: ShellxSpace.s4),
              OutlinedButton.icon(
                key: const Key('ai.changes.revert'),
                onPressed: canRevert
                    ? () => unawaited(
                        aiRevert(
                          context,
                          pane.runtime,
                          pane.ui,
                          turn: _scope == AiChangesScope.turn ? turn : null,
                        ),
                      )
                    : null,
                icon: const Icon(Icons.undo, size: 14),
                label: Text(
                  _scope == AiChangesScope.turn
                      ? l10n.aiRevertTurn
                      : l10n.aiRevertSession,
                ),
              ),
              if (turns.running)
                Text(
                  l10n.aiRevertBusy,
                  style: dim.copyWith(color: ShellxDesktopColors.warn),
                ),
              ValueListenableBuilder<String?>(
                valueListenable: pane.ui.note,
                builder: (context, note, _) => note == null
                    ? const SizedBox.shrink()
                    : Semantics(
                        liveRegion: true,
                        child: Text(
                          note,
                          key: const Key('ai.changes.note'),
                          style: ShellxText.small.copyWith(
                            color: ShellxDesktopColors.textPrimary,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: ShellxSpace.s4),
              Text(l10n.aiIgnoredNote, style: dim),
              Text(l10n.aiOutsideNote, style: dim),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({
    super.key,
    required this.change,
    required this.after,
    required this.reviewed,
    required this.onOpen,
    required this.onReviewed,
    required this.onRevert,
  });

  final FileChange change;
  final bool after;
  final bool reviewed;
  final VoidCallback onOpen;
  final ValueChanged<bool> onReviewed;
  final VoidCallback onRevert;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = change;
    final (letter, color) = switch (c.kind) {
      ChangeKind.added => ('A', ShellxDesktopColors.ok),
      ChangeKind.modified => ('M', ShellxDesktopColors.warn),
      ChangeKind.deleted => ('D', ShellxDesktopColors.err),
    };
    final slash = c.path.lastIndexOf('/');
    final dir = slash < 0 ? '' : c.path.substring(0, slash + 1);
    final name = c.path.substring(slash + 1);
    final small = ShellxText.small;
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ShellxSpace.s8,
          vertical: ShellxSpace.s2,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              child: Text(letter, style: small.copyWith(color: color)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: dir,
                          style: small.copyWith(
                            color: ShellxDesktopColors.textSecondary,
                          ),
                        ),
                        TextSpan(
                          text: name,
                          style: small.copyWith(
                            color: ShellxDesktopColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (after)
                    Text(
                      l10n.aiChangedAfterTurn,
                      style: ShellxText.caption.copyWith(
                        color: ShellxDesktopColors.warn,
                      ),
                    ),
                ],
              ),
            ),
            if (c.binary)
              Text(
                l10n.aiBinaryFile,
                style: ShellxText.caption.copyWith(
                  color: ShellxDesktopColors.textSecondary,
                ),
              )
            else ...[
              Text(
                '+${c.added}',
                style: ShellxText.caption.copyWith(
                  color: ShellxDesktopColors.ok,
                ),
              ),
              const SizedBox(width: ShellxSpace.s4),
              Text(
                '−${c.removed}',
                style: ShellxText.caption.copyWith(
                  color: ShellxDesktopColors.err,
                ),
              ),
            ],
            Tooltip(
              message: l10n.aiReviewed,
              child: Checkbox(
                visualDensity: VisualDensity.compact,
                value: reviewed,
                onChanged: (on) => onReviewed(on ?? false),
              ),
            ),
            IconButton(
              tooltip: l10n.aiRevertFile,
              iconSize: 14,
              visualDensity: VisualDensity.compact,
              onPressed: onRevert,
              icon: const Icon(Icons.undo),
            ),
          ],
        ),
      ),
    );
  }
}
```

`apps/desktop/lib/src/ui/ai/ai_diff_overlay.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../l10n/app_localizations.dart';
import '../../ai/ai_off_thread.dart';
import '../../ai/ai_project_files.dart';
import '../../ai/line_diff.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_diff_view.dart';
import 'ai_editor.dart';
import 'ai_scope.dart';

/// A changed file's diff over the conversation (§4.1 overlay, §4.4): the
/// file before turn [turn] (or before the session: [session]) against the
/// disk now. Binary and over-1-MiB files say so instead. Esc or × closes it.
class AiDiffOverlay extends ConsumerStatefulWidget {
  const AiDiffOverlay({
    super.key,
    required this.path,
    required this.turn,
    required this.session,
  });

  /// Relative to the session folder.
  final String path;
  final int turn;
  final bool session;

  @override
  ConsumerState<AiDiffOverlay> createState() => _AiDiffOverlayState();
}

class _AiDiffOverlayState extends ConsumerState<AiDiffOverlay> {
  List<DiffLine?>? _lines;
  String? _note;
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_load(AiPaneScope.of(context)));
  }

  Future<void> _load(AiPaneScope pane) async {
    final l10n = AppLocalizations.of(context);
    final before = aiFileContentOf(
      await pane.runtime.fileBefore(widget.turn, widget.path),
    );
    final now = await ref
        .read(aiProjectFilesProvider)
        .read(p.join(pane.state.cwd, widget.path));
    if (!mounted) return;
    if (before is AiFileBinary || now is AiFileBinary) {
      setState(() => _note = l10n.aiBinaryFile);
      return;
    }
    if (before is AiFileTooLarge || now is AiFileTooLarge) {
      setState(() => _note = l10n.aiFileTooLarge);
      return;
    }
    final lines = await lineDiff(
      ref.read(aiOffThreadProvider),
      before is AiFileText ? before.text : '',
      now is AiFileText ? now.text : '',
    );
    if (mounted) setState(() => _lines = withContext(lines));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pane = AiPaneScope.of(context);
    final lines = _lines;
    final note = _note;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): pane.ui.closeOverlay,
      },
      child: Focus(
        autofocus: true,
        child: Container(
          key: const Key('ai.diff'),
          margin: const EdgeInsets.all(ShellxSpace.s16),
          padding: const EdgeInsets.all(ShellxSpace.s12),
          decoration: BoxDecoration(
            color: ShellxDesktopColors.surface,
            borderRadius: BorderRadius.circular(ShellxRadius.r8),
            border: Border.all(color: ShellxDesktopColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ShellxText.bodyStrong.copyWith(
                        color: ShellxDesktopColors.textPrimary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => unawaited(
                      aiOpenInEditor(ref, widget.path, pane.state.cwd),
                    ),
                    child: Text(l10n.aiOpenInEditor),
                  ),
                  IconButton(
                    key: const Key('ai.diff.close'),
                    tooltip: l10n.actionClose,
                    iconSize: 16,
                    onPressed: pane.ui.closeOverlay,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                widget.session ? l10n.aiVsSessionStart : l10n.aiVsTurnStart,
                style: ShellxText.caption.copyWith(
                  color: ShellxDesktopColors.textSecondary,
                ),
              ),
              const SizedBox(height: ShellxSpace.s8),
              Expanded(
                child: note != null
                    ? Text(
                        note,
                        key: const Key('ai.diff.note'),
                        style: ShellxText.body.copyWith(
                          color: ShellxDesktopColors.textSecondary,
                        ),
                      )
                    : lines == null
                    ? const SizedBox.shrink()
                    : LayoutBuilder(
                        builder: (context, box) => SingleChildScrollView(
                          child: AiDiffView(
                            lines: lines,
                            height: box.maxHeight,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

`apps/desktop/lib/src/ui/ai/ai_side_panel.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_changes_panel.dart';
import 'ai_scope.dart';
import 'ai_theme.dart';

/// The AI pane's right panel (spec §4.1, §4.4), 268 px: "Changes", and
/// "Files" once [files] is given (Task 25). The tabs switch at once (no
/// animation); which one shows is the pane's ([AiPaneUi.panelTab]).
class AiSidePanel extends StatelessWidget {
  const AiSidePanel({super.key, this.files});

  /// The Files tab; null: Changes alone.
  final Widget? files;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ui = AiPaneScope.of(context).ui;
    final files = this.files;
    Widget tab(AiPanelTab which, String label, Key key) {
      final on = ui.panelTab == which;
      return TextButton(
        key: key,
        onPressed: () => ui.showTab(which),
        child: Text(
          label,
          style: ShellxText.bodyStrong.copyWith(
            color: on
                ? ShellxDesktopColors.textPrimary
                : ShellxDesktopColors.textSecondary,
          ),
        ),
      );
    }

    return SizedBox(
      key: const Key('ai.sidePanel'),
      width: AiSizes.panel,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: ShellxDesktopColors.bgSidebar,
          border: Border(left: BorderSide(color: ShellxDesktopColors.line)),
        ),
        child: ListenableBuilder(
          listenable: ui,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s4),
                child: Row(
                  children: [
                    tab(
                      AiPanelTab.changes,
                      l10n.aiPanelChanges,
                      const Key('ai.panel.changes'),
                    ),
                    if (files != null)
                      tab(
                        AiPanelTab.files,
                        l10n.aiPanelFiles,
                        const Key('ai.panel.files'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: files == null
                    ? const AiChangesPanel()
                    : IndexedStack(
                        index: ui.panelTab.index,
                        sizing: StackFit.expand,
                        children: [const AiChangesPanel(), files],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

In `apps/desktop/lib/src/ui/ai/ai_scope.dart`, replace:

```dart
/// The AI pane's own UI state, which its parts change: the overlay over the
```

with:

```dart
/// The right panel's tabs (§4.4).
enum AiPanelTab { changes, files }

/// The AI pane's own UI state, which its parts change: the overlay over the
```

In `apps/desktop/lib/src/ui/ai/ai_scope.dart`, replace:

```dart
  Widget? _overlay;
  var _panel = false;

  Widget? get overlay => _overlay;
  bool get panelOpen => _panel;
```

with:

```dart
  Widget? _overlay;
  var _panel = false;
  var _tab = AiPanelTab.changes;

  Widget? get overlay => _overlay;
  bool get panelOpen => _panel;
  AiPanelTab get panelTab => _tab;

  /// The Changes panel's last result ("Reverted 2 files.", "Wait for the
  /// running turn to finish.").
  final note = ValueNotifier<String?>(null);

  /// Goes up when the project changed under the Changes panel (a revert).
  final changes = ValueNotifier<int>(0);

  /// "Reviewed" marks (`aiReviewKey`), kept while the pane lives.
  final reviewed = <String>{};
```

In `apps/desktop/lib/src/ui/ai/ai_scope.dart`, replace:

```dart
  void openPanel() {
    if (_panel) return;
    _panel = true;
    notifyListeners();
  }

  @override
  void dispose() {
    insert.dispose();
    super.dispose();
  }
```

with:

```dart
  /// Opens the panel on its Changes tab ("View" on a turn summary).
  void openPanel() => showTab(AiPanelTab.changes);

  void showTab(AiPanelTab tab) {
    if (_panel && _tab == tab) return;
    _panel = true;
    _tab = tab;
    notifyListeners();
  }

  void changesChanged() => changes.value++;

  @override
  void dispose() {
    insert.dispose();
    note.dispose();
    changes.dispose();
    super.dispose();
  }
```

In `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, replace:

```dart
import 'ai_dock.dart';
import 'ai_folder_card.dart';
```

with:

```dart
import 'ai_changes_panel.dart';
import 'ai_dock.dart';
import 'ai_folder_card.dart';
```

In `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, replace:

```dart
import 'ai_scope.dart';
import 'ai_timeline.dart';
```

with:

```dart
import 'ai_scope.dart';
import 'ai_side_panel.dart';
import 'ai_timeline.dart';
```

In `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, replace:

```dart
    _ui.onRun = (request) => unawaited(_run(request));
```

with:

```dart
    _ui.onRun = (request) => unawaited(_run(request));
    _ui.onRevertTurn = (turn) {
      final runtime = _runtime;
      if (runtime == null) return;
      unawaited(aiRevert(context, runtime, _ui, turn: turn));
    };
```

In `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, replace:

```dart
        child: _Conversation(input: _input, resuming: _resuming),
      );
    }
```

with:

```dart
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Conversation(input: _input, resuming: _resuming),
            ),
            // §4.4: the right panel, 268 px.
            ListenableBuilder(
              listenable: _ui,
              builder: (context, _) =>
                  _ui.panelOpen ? const AiSidePanel() : const SizedBox.shrink(),
            ),
          ],
        ),
      );
    }
```

In `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, replace:

```dart
    Widget header(AiHeaderView view) => AiHeader(
      paneId: pane.id,
      agentName: pane.agentName,
      title: widget.tab.label,
      view: view,
      onTerminal: () => unawaited(tabs.openAiTerminal(widget.tab.id)),
      onZoom: widget.tab.isSplit ? _zoom : null,
      onMore: (at) => unawaited(_more(at)),
    );
```

with:

```dart
    Widget header(AiHeaderView view) => ListenableBuilder(
      listenable: _ui,
      builder: (context, _) => AiHeader(
        paneId: pane.id,
        agentName: pane.agentName,
        title: widget.tab.label,
        view: view,
        onPanel: runtime == null ? null : _ui.togglePanel,
        panelOpen: _ui.panelOpen,
        onTerminal: () => unawaited(tabs.openAiTerminal(widget.tab.id)),
        onZoom: widget.tab.isSplit ? _zoom : null,
        onMore: (at) => unawaited(_more(at)),
      ),
    );
```

In `apps/desktop/lib/src/ui/ai/ai_tool_card.dart`, replace:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shellx_acp/shellx_acp.dart';
```

with:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_acp/shellx_acp.dart';
```

In `apps/desktop/lib/src/ui/ai/ai_tool_card.dart`, replace:

```dart
import '../../../l10n/app_localizations.dart';
import '../../agent/desktop_services.dart';
import '../../ai/ai_off_thread.dart';
import '../../ai/line_diff.dart';
import '../../config/config_controller.dart' show shellxConfigProvider;
import '../../platform/editor_links.dart';
import '../terminal/link_layer.dart' show editorDetectorProvider;
import '../theme/shellx_desktop_theme.dart';
import 'ai_diff_view.dart';
```

with:

```dart
import '../../../l10n/app_localizations.dart';
import '../../ai/ai_off_thread.dart';
import '../../ai/line_diff.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_diff_view.dart';
import 'ai_editor.dart';
```

In `apps/desktop/lib/src/ui/ai/ai_tool_card.dart`, replace:

```dart
  Future<void> _openInEditor(String path, String cwd) async {
    final abs = p.isAbsolute(path) ? path : p.join(cwd, path);
    final opener = ref.read(desktopServicesProvider).urlOpener;
    try {
      final editor = await editorFor(
        ref.read(shellxConfigProvider).config.linkEditor,
        ref.read(editorDetectorProvider),
      );
      if (editor != null) {
        await opener.openInEditor(editor, abs);
      } else {
        await opener.reveal(abs, isDirectory: false);
      }
    } on Object catch (error) {
      debugPrint('ShellX: editor not opened: ${error.runtimeType}');
    }
  }
```

with:

```dart

```

In `apps/desktop/lib/src/ui/ai/ai_tool_card.dart`, replace:

```dart
            onPressed: () => unawaited(_openInEditor(d.path, cwd)),
```

with:

```dart
            onPressed: () => unawaited(aiOpenInEditor(ref, d.path, cwd)),
```

- [ ] **Step 4: Run the tests**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/ai lib/src/ui/ai test/ui/ai test/support
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai test/ai test/ui/ai_tab_screens_test.dart 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `All tests passed!` (77 on the scratch copy); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/ai/ai_project_files.dart apps/desktop/lib/src/ui/ai/ai_editor.dart apps/desktop/lib/src/ui/ai/ai_changes_panel.dart apps/desktop/lib/src/ui/ai/ai_diff_overlay.dart apps/desktop/lib/src/ui/ai/ai_side_panel.dart apps/desktop/lib/src/ui/ai/ai_scope.dart apps/desktop/lib/src/ui/ai/ai_pane_view.dart apps/desktop/lib/src/ui/ai/ai_tool_card.dart apps/desktop/test/support/fake_project.dart apps/desktop/test/ui/ai/ai_changes_test.dart
git commit -m "feat(v2-ai): Changes panel — this turn / whole session, diffs, revert with the changed-after dialog

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 21: Mode, model and thinking chips; "Bypass permissions" asks first (D11) [needs V2-1a Task 9]

Spec D11, §4.1 (the composer's row); ruling R6 (V2-1a).

**What the chips show:** the session's settings, in the composer's row: one chip per `select` or `boolean` entry of `configOptions`, else one chip for the legacy `modes`.
- The labels use the agent's names. Claude's known mode ids read in the app's words: Ask first, Auto-edit files, Plan, Auto, Bypass permissions.
- Model and thinking read "Model: …" and "Thinking: …"; other entries read "{name}: {value}".
- Smoothness: the chips rebuild only when the options change.

**What a choice does:**
- It goes to the agent: `session/set_config_option`, or `session/set_mode` for legacy modes.
- It is remembered for the agent's next sessions (Task 10 `rememberConfig`).
- "Bypass permissions" always asks first, with Cancel as the first focus, and is never remembered (R6).
- An agent that refuses keeps its value; only the error's type is logged.

**Files:**
- Create: `apps/desktop/lib/src/ui/ai/ai_config_chips.dart`
- Modify: `apps/desktop/lib/src/ui/ai/ai_composer.dart`
- Test: `apps/desktop/test/ui/ai/ai_config_chips_test.dart`

**Interfaces:**
- Consumes: V2-1a `AiRuntime.setConfig(String, Object)`, `AiRuntime.setMode(String)`, `AiSessionState.configOptions/modes`, `ConfigOption` (`id`, `name`, `kind`, `category`, `currentValue`, `choices`), `SessionModes`; Task 10 `rememberConfig`, `rememberedConfig`, `kClaudeAgentId`; Task 17 `AiSelect`.
- Produces: `AiConfigChips`; `aiModeName(l10n, {agentId, id, name})`; `confirmAiBypass(context, agent) → Future<bool>`; `kAiBypassMode`; keys `ai.config.<id>`, `ai.config.<id>.<value>`, `ai.bypass.cancel`, `ai.bypass.on`.

- [ ] **Step 1: Write the failing test**

`apps/desktop/test/ui/ai/ai_config_chips_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_agents.dart';
import 'package:shellx_desktop/src/terminal/sidebar_workspaces.dart'
    show settingsStoreProvider;
import 'package:shellx_desktop/src/ui/ai/ai_dock.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';

/// Claude's own `configOptions` (adapter 0.90.0, trimmed).
const _claudeOptions = <Map<String, Object?>>[
  {
    'id': 'mode',
    'name': 'Mode',
    'category': 'mode',
    'type': 'select',
    'currentValue': 'default',
    'options': [
      {'value': 'default', 'name': 'Manual'},
      {'value': 'acceptEdits', 'name': 'Accept edits'},
      {'value': 'plan', 'name': 'Plan'},
      {'value': 'bypassPermissions', 'name': 'Bypass permissions'},
    ],
  },
  {
    'id': 'model',
    'name': 'Model',
    'category': 'model',
    'type': 'select',
    'currentValue': 'opus',
    'options': [
      {'value': 'opus', 'name': 'Opus 5.5'},
      {'value': 'sonnet', 'name': 'Sonnet 5.5'},
    ],
  },
  {
    'id': 'effort',
    'name': 'Effort',
    'category': 'thought_level',
    'type': 'select',
    'currentValue': 'high',
    'options': [
      {'value': 'low', 'name': 'Low'},
      {'value': 'high', 'name': 'High'},
    ],
  },
];

/// V2-1 D11: mode, model and thinking chips.
void main() {
  Future<(FakeAiRuntimes, AiRuntime, ProviderContainer)> dock(
    WidgetTester t,
    FakeScenario scenario,
  ) async {
    final fakes = FakeAiRuntimes(scenario);
    final runtime = partRuntime(fakes);
    await runtime.start();
    final part = await pumpAiPart(t, const AiDock(), runtime: runtime);
    return (fakes, runtime, part.container);
  }

  Future<void> pick(WidgetTester t, String chip, String value) async {
    await t.tap(find.byKey(Key('ai.config.$chip')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key('ai.config.$chip.$value')).last);
    await t.pumpAndSettle();
  }

  testWidgets('Claude\'s mode in the app\'s words, the model, the thinking; '
      'a choice goes to the agent and is remembered', (t) async {
    final (fakes, runtime, c) = await dock(
      t,
      const FakeScenario(configOptions: _claudeOptions),
    );
    expect(find.text('Ask first'), findsOneWidget);
    expect(find.text('Model: Opus 5.5'), findsOneWidget);
    expect(find.text('Thinking: High'), findsOneWidget);
    await pick(t, 'model', 'sonnet');
    expect(
      fakes.agent().received,
      contains('session/set_config_option:model=sonnet'),
    );
    expect(find.text('Model: Sonnet 5.5'), findsOneWidget);
    expect(rememberedConfig(c.read(settingsStoreProvider), 'claude'), {
      'model': 'sonnet',
    });
    await runtime.dispose();
  });

  testWidgets('"Bypass permissions" asks first (Cancel changes nothing), '
      'and is never remembered (R6)', (t) async {
    final (fakes, runtime, c) = await dock(
      t,
      const FakeScenario(configOptions: _claudeOptions),
    );
    await pick(t, 'mode', 'bypassPermissions');
    expect(find.text('Turn on “Bypass permissions”?'), findsOneWidget);
    expect(
      find.text('Claude will edit files and run commands without asking.'),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('ai.bypass.cancel')));
    await t.pumpAndSettle();
    expect(
      fakes.agent().received.where((r) => r.startsWith('session/set_config')),
      isEmpty,
    );
    await pick(t, 'mode', 'bypassPermissions');
    await t.tap(find.byKey(const Key('ai.bypass.on')));
    await t.pumpAndSettle();
    expect(
      fakes.agent().received,
      contains('session/set_config_option:mode=bypassPermissions'),
    );
    expect(find.text('Bypass permissions'), findsOneWidget);
    expect(rememberedConfig(c.read(settingsStoreProvider), 'claude'), isEmpty);
    await runtime.dispose();
  });

  testWidgets('an agent with legacy modes only: session/set_mode', (t) async {
    final (fakes, runtime, _) = await dock(
      t,
      const FakeScenario(
        modes: {
          'currentModeId': 'ask',
          'availableModes': [
            {'id': 'ask', 'name': 'Ask'},
            {'id': 'code', 'name': 'Code'},
          ],
        },
      ),
    );
    expect(find.text('Ask'), findsOneWidget);
    await pick(t, 'mode', 'code');
    expect(fakes.agent().received, contains('session/set_mode:code'));
    expect(find.text('Code'), findsOneWidget);
    await runtime.dispose();
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai/ai_config_chips_test.dart`
Expected: FAIL — `Expected: exactly one matching candidate` for `find.text('Ask first')` (no chips yet).

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/ui/ai/ai_config_chips.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_acp/shellx_acp.dart';

import '../../../l10n/app_localizations.dart';
import '../../ai/ai_agents.dart' show kClaudeAgentId, rememberConfig;
import '../../terminal/sidebar_workspaces.dart' show settingsStoreProvider;
import '../terminal/shellx_menu.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_scope.dart';

/// The mode that lets an agent act without asking (D11, ruling R6).
const String kAiBypassMode = 'bypassPermissions';

/// D11: Claude's known mode ids in the app's words; any other agent's
/// modes keep the agent's own names.
String aiModeName(
  AppLocalizations l10n, {
  required String agentId,
  required String id,
  required String name,
}) => agentId != kClaudeAgentId
    ? name
    : switch (id) {
        'default' => l10n.aiModeDefault,
        'acceptEdits' => l10n.aiModeAcceptEdits,
        'plan' => l10n.aiModePlan,
        'auto' => l10n.aiModeAuto,
        kAiBypassMode => l10n.aiModeBypass,
        _ => name,
      };

bool _isMode(ConfigOption o) => o.category == 'mode' || o.id == 'mode';

/// D11: "Turn on “Bypass permissions”?" — Cancel (the first focus) / Turn
/// on (destructive). True: turn it on.
Future<bool> confirmAiBypass(BuildContext context, String agent) async {
  final on = await showDialog<bool>(
    context: context,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      return AlertDialog(
        title: Text(l10n.aiBypassTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.aiBypassConfirm(agent)),
            const SizedBox(height: ShellxSpace.s8),
            Text(
              l10n.aiBypassNote,
              style: ShellxText.small.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('ai.bypass.cancel'),
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            key: const Key('ai.bypass.on'),
            style: destructiveButtonStyle(),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.aiBypassTurnOn),
          ),
        ],
      );
    },
  );
  return on ?? false;
}

/// D11, spec §4.1: the session's settings as chips in the composer's row —
/// mode, model, thinking and the agent's others (`configOptions`), or the
/// legacy `modes`. A choice goes to the agent (`session/set_config_option`
/// or `session/set_mode`) and is remembered for the agent's next sessions,
/// except "Bypass permissions", which always asks first and is never
/// remembered (R6). Rebuilt only when the options change.
class AiConfigChips extends ConsumerWidget {
  const AiConfigChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = AiPaneScope.of(context);
    return AiSelect<(List<ConfigOption>?, SessionModes?)>(
      frames: scope.frames,
      select: (s) => (s.configOptions, s.modes),
      builder: (context, v) {
        final (options, modes) = v;
        final chips = <Widget>[
          if (options != null)
            for (final o in options)
              if (o.kind != ConfigKind.other) _OptionChip(option: o),
          if (options == null && modes != null) _ModeChip(modes: modes),
        ];
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: chips),
        );
      },
    );
  }
}

Offset _below(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset(0, box.size.height));
}

Widget _chip(String label, VoidCallback onPressed, Key key) => TextButton(
  key: key,
  style: TextButton.styleFrom(
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s6),
    foregroundColor: ShellxDesktopColors.textSecondary,
  ),
  onPressed: onPressed,
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: ShellxText.caption),
      const Icon(Icons.expand_more, size: 12),
    ],
  ),
);

class _OptionChip extends ConsumerWidget {
  const _OptionChip({required this.option});
  final ConfigOption option;

  String _choiceName(AppLocalizations l10n, String agentId, ConfigChoice c) =>
      _isMode(option)
      ? aiModeName(l10n, agentId: agentId, id: c.value, name: c.name)
      : c.name;

  String _label(AppLocalizations l10n, String agentId) {
    final o = option;
    if (o.kind == ConfigKind.boolean) {
      return l10n.aiConfigOther(
        o.name,
        o.currentValue == true ? l10n.aiSettingOn : l10n.aiSettingOff,
      );
    }
    final current = o.choices.where((c) => c.value == o.currentValue);
    final name = current.isEmpty
        ? '${o.currentValue ?? ''}'
        : _choiceName(l10n, agentId, current.first);
    return switch (o.category) {
      _ when _isMode(o) => name,
      'model' => l10n.aiConfigModel(name),
      'thought_level' => l10n.aiConfigEffort(name),
      _ => l10n.aiConfigOther(o.name, name),
    };
  }

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref,
    AiPaneScope scope,
    Object value,
  ) async {
    if (value == kAiBypassMode &&
        !await confirmAiBypass(context, scope.state.agentName)) {
      return;
    }
    try {
      await scope.runtime.setConfig(option.id, value);
      await rememberConfig(
        ref.read(settingsStoreProvider),
        scope.state.agentId,
        option.id,
        value,
      );
    } on Object catch (error) {
      debugPrint('ShellX: setting not applied: ${error.runtimeType}');
    }
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final scope = AiPaneScope.of(context);
    final o = option;
    if (o.kind == ConfigKind.boolean) {
      return _apply(context, ref, scope, o.currentValue != true);
    }
    final agentId = scope.state.agentId;
    final choice = await showShellxMenu<String>(
      context: context,
      at: _below(context),
      entries: [
        for (final c in o.choices)
          ShellxMenuEntry(
            key: Key('ai.config.${o.id}.${c.value}'),
            value: c.value,
            label: _choiceName(l10n, agentId, c),
            checked: c.value == o.currentValue,
          ),
      ],
    );
    if (choice == null || choice == o.currentValue || !context.mounted) return;
    await _apply(context, ref, scope, choice);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final agentId = AiPaneScope.of(context).state.agentId;
    return Builder(
      builder: (context) => _chip(
        _label(l10n, agentId),
        () => unawaited(_pick(context, ref)),
        Key('ai.config.${option.id}'),
      ),
    );
  }
}

/// An agent with legacy `modes` only (D11): `session/set_mode`.
class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.modes});
  final SessionModes modes;

  Future<void> _pick(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final scope = AiPaneScope.of(context);
    final agentId = scope.state.agentId;
    final choice = await showShellxMenu<String>(
      context: context,
      at: _below(context),
      entries: [
        for (final m in modes.available)
          ShellxMenuEntry(
            key: Key('ai.config.mode.${m.id}'),
            value: m.id,
            label: aiModeName(l10n, agentId: agentId, id: m.id, name: m.name),
            checked: m.id == modes.currentModeId,
          ),
      ],
    );
    if (choice == null || choice == modes.currentModeId || !context.mounted) {
      return;
    }
    if (choice == kAiBypassMode &&
        !await confirmAiBypass(context, scope.state.agentName)) {
      return;
    }
    try {
      await scope.runtime.setMode(choice);
    } on Object catch (error) {
      debugPrint('ShellX: mode not applied: ${error.runtimeType}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final agentId = AiPaneScope.of(context).state.agentId;
    final current = modes.available
        .where((m) => m.id == modes.currentModeId)
        .firstOrNull;
    return _chip(
      aiModeName(
        l10n,
        agentId: agentId,
        id: modes.currentModeId,
        name: current?.name ?? modes.currentModeId,
      ),
      () => unawaited(_pick(context)),
      const Key('ai.config.mode'),
    );
  }
}
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
import '../theme/shellx_desktop_theme.dart';
import 'ai_scope.dart';
```

with:

```dart
import '../theme/shellx_desktop_theme.dart';
import 'ai_config_chips.dart';
import 'ai_scope.dart';
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
                  )
                else
                  const Spacer(),
```

with:

```dart
                  )
                else
                  // D11: mode, model, thinking.
                  const Expanded(child: AiConfigChips()),
```

- [ ] **Step 4: Run the tests**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/ui/ai test/ui/ai
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai test/ai test/ui/ai_tab_screens_test.dart 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `All tests passed!` (80 on the scratch copy); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/ui/ai/ai_config_chips.dart apps/desktop/lib/src/ui/ai/ai_composer.dart apps/desktop/test/ui/ai/ai_config_chips_test.dart
git commit -m "feat(v2-ai): mode, model and thinking chips; Bypass permissions confirmed, never remembered

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 22: The agent's questions — form and URL cards (D22) [needs V2-1a Task 9]

Spec D22, D13 (a question is "needs input"), §5 (URLs).

**What changes:** Task 12's stand-in for questions (the message and a Decline button) becomes the real card.

**The form card:** text (the keyboard follows `format`; `maxLength` limits it), number (an integer for `integer`), yes/no, one choice (chips) and several choices (filter chips). Required fields are marked.
- **Send** answers `accept`, with only the fields the user gave, once V2-1a's `ElicitationForm.accepts` takes them. Otherwise "Check the marked answers." shows and nothing is sent.
- **Decline** answers `decline`, **Cancel** answers `cancel`.

**The URL card:**
- It shows "{agent} asks you to open this page:" and the whole URL (selectable) first.
- "Open in browser" works only for http/https, through `UrlOpener.openWebLink` and only on a click. It then answers `accept`.
- `elicitation/complete` marks the card done.

**A type ShellX cannot show:** V2-1a already declined it. The card says "This question uses an answer type ShellX does not support yet".

**Once answered:** the card folds to one line: "… — Answered / Declined / Cancelled / Done".

**Files:**
- Create: `apps/desktop/lib/src/ui/ai/ai_ask_card.dart`
- Modify: `apps/desktop/lib/src/ui/ai/ai_timeline.dart`
- Test: `apps/desktop/test/ui/ai/ai_ask_card_test.dart`

**Interfaces:**
- Consumes: V2-1a `AskItem` (`id`, `request`, `response`, `autoDeclined`, `completed`), `AiRuntime.answerAsk(int, ElicitationResponse)`; `shellx_acp` `ElicitationForm` (`fields`, `accepts`), `ElicitationUrl` (`url`, `isWebUrl`), `ElicitTextField` / `ElicitNumberField` / `ElicitBoolField` / `ElicitChoiceField` / `ElicitMultiChoiceField` / `ElicitUnsupportedField`, `ElicitAccept` / `ElicitDecline` / `ElicitCancel`; `FakeSteps.ask`, `FakeSteps.completeAsk`; `UrlOpener.openWebLink`.
- Produces: `AiAskCard`; keys `ai.ask`, `ai.ask.<field>`, `ai.ask.<field>.<value>`, `ai.ask.send|decline|cancel|open|url|invalid|done|unsupported`.

- [ ] **Step 1: Write the failing test**

`apps/desktop/test/ui/ai/ai_ask_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ui/ai/ai_timeline.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';
import '../../support/fakes.dart';

const _form = <String, Object?>{
  'mode': 'form',
  'message': 'A few details',
  'requestedSchema': {
    'type': 'object',
    'properties': {
      'name': {'type': 'string', 'title': 'Name'},
      'age': {'type': 'integer', 'title': 'Age', 'minimum': 0},
      'ok': {'type': 'boolean', 'title': 'Agree'},
      'color': {
        'type': 'string',
        'title': 'Color',
        'enum': ['red', 'blue'],
      },
      'tags': {
        'type': 'array',
        'title': 'Tags',
        'items': {
          'type': 'string',
          'enum': ['a', 'b', 'c'],
        },
      },
    },
    'required': ['name'],
  },
};

/// V2-1 D22: the agent's questions in the conversation.
void main() {
  Future<(FakeAiRuntimes, AiRuntime, TestHarness)> asked(
    WidgetTester t,
    List<Map<String, Object?>> steps,
  ) async {
    final fakes = FakeAiRuntimes(FakeScenario(turns: [steps]));
    final runtime = partRuntime(fakes);
    await runtime.start();
    final part = await pumpAiPart(t, const AiTimeline(), runtime: runtime);
    await runtime.send([const TextBlock('go')]);
    await t.pump();
    await t.pump();
    return (fakes, runtime, part.harness);
  }

  testWidgets('a form: text, number, yes/no, one and several choices; Send '
      'answers accept with the values, and the card folds', (t) async {
    final (fakes, runtime, _) = await asked(t, [FakeSteps.ask(_form)]);
    expect(find.text('A few details'), findsOneWidget);
    expect(find.text('Required'), findsOneWidget);
    await t.enterText(find.byKey(const Key('ai.ask.name')), 'Ann');
    await t.enterText(find.byKey(const Key('ai.ask.age')), '30');
    await t.tap(find.byKey(const Key('ai.ask.ok')));
    await t.tap(find.byKey(const Key('ai.ask.color.red')));
    await t.tap(find.byKey(const Key('ai.ask.tags.a')));
    await t.tap(find.byKey(const Key('ai.ask.tags.b')));
    await t.pump();
    await t.tap(find.byKey(const Key('ai.ask.send')));
    await t.pump();
    await t.pump();
    expect(
      fakes.agent().received,
      contains(
        'ask:accept={"name":"Ann","age":30,"ok":true,"color":"red",'
        '"tags":["a","b"]}',
      ),
    );
    expect(find.text('A few details — Answered'), findsOneWidget);
    await runtime.dispose();
  });

  testWidgets('a required field left empty says so and sends nothing; '
      'Decline answers decline', (t) async {
    final (fakes, runtime, _) = await asked(t, [FakeSteps.ask(_form)]);
    await t.tap(find.byKey(const Key('ai.ask.send')));
    await t.pump();
    expect(find.text('Check the marked answers.'), findsOneWidget);
    expect(fakes.agent().received.where((r) => r.startsWith('ask:')), isEmpty);
    await t.tap(find.byKey(const Key('ai.ask.decline')));
    await t.pump();
    await t.pump();
    expect(fakes.agent().received, contains('ask:decline'));
    expect(find.text('A few details — Declined'), findsOneWidget);
    await runtime.dispose();
  });

  testWidgets('a URL: shown whole, opened only on a click, then accept; '
      'elicitation/complete marks it done', (t) async {
    const url = 'https://github.com/login/device';
    final (fakes, runtime, h) = await asked(t, [
      FakeSteps.ask({
        'mode': 'url',
        'message': 'Sign in to GitHub',
        'elicitationId': 'e1',
        'url': url,
      }),
      FakeSteps.completeAsk('e1'),
    ]);
    expect(find.text('Claude asks you to open this page:'), findsOneWidget);
    expect(
      t.widget<SelectableText>(find.byKey(const Key('ai.ask.url'))).data,
      url,
    );
    expect(h.urlOpener.webLinks, isEmpty);
    await t.tap(find.byKey(const Key('ai.ask.open')));
    await t.pump();
    await t.pump();
    expect(h.urlOpener.webLinks, [Uri.parse(url)]);
    expect(fakes.agent().received, contains('ask:accept'));
    expect(find.text('Sign in to GitHub — Done'), findsOneWidget);
    await runtime.dispose();
  });

  testWidgets('a URL that is not http/https cannot be opened', (t) async {
    final (_, runtime, _) = await asked(t, [
      FakeSteps.ask({
        'mode': 'url',
        'message': 'Look',
        'elicitationId': 'e2',
        'url': 'file:///etc/hosts',
      }),
    ]);
    expect(
      t.widget<FilledButton>(find.byKey(const Key('ai.ask.open'))).onPressed,
      isNull,
    );
    await t.tap(find.byKey(const Key('ai.ask.cancel')));
    await t.pump();
    await runtime.dispose();
  });

  testWidgets('a type ShellX cannot show was declined; the card says so', (
    t,
  ) async {
    final (fakes, runtime, _) = await asked(t, [
      FakeSteps.ask({
        'mode': 'form',
        'message': 'Pick a file',
        'requestedSchema': {
          'type': 'object',
          'properties': {
            'file': {'type': 'object'},
          },
        },
      }),
    ]);
    expect(fakes.agent().received, contains('ask:decline'));
    expect(
      find.text(
        'Pick a file — This question uses an answer type ShellX does not '
        'support yet',
      ),
      findsOneWidget,
    );
    await runtime.dispose();
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai/ai_ask_card_test.dart`
Expected: FAIL — `Expected: exactly one matching candidate` for `find.text('Required')` (the stand-in shows no form).

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/ui/ai/ai_ask_card.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/desktop_services.dart';
import '../text_editing_shortcuts.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_scope.dart';
import 'ai_theme.dart';

/// D22: the agent's question in the conversation (it counts as "needs
/// input", D13).
/// - A form: text, number, yes/no, one choice and several choices; Send
///   answers `accept` with the values once every required field is valid,
///   Decline answers `decline`, Cancel `cancel`.
/// - A URL: the whole URL first, "Open in browser" (http/https only, on a
///   click) answers `accept`; `elicitation/complete` marks it done.
/// - A type ShellX cannot show was declined already: the card says so.
/// Once answered it folds to one line.
class AiAskCard extends ConsumerStatefulWidget {
  const AiAskCard({super.key, required this.item});
  final AskItem item;

  @override
  ConsumerState<AiAskCard> createState() => _AiAskCardState();
}

class _AiAskCardState extends ConsumerState<AiAskCard> {
  final _text = <String, TextEditingController>{};
  final _values = <String, Object>{};
  var _invalid = false;

  @override
  void initState() {
    super.initState();
    final request = widget.item.request;
    if (request is! ElicitationForm) return;
    for (final f in request.fields) {
      switch (f) {
        case ElicitTextField(:final defaultValue):
          _text[f.key] = TextEditingController(text: defaultValue ?? '');
        case ElicitNumberField(:final defaultValue):
          _text[f.key] = TextEditingController(
            text: defaultValue == null ? '' : '$defaultValue',
          );
        case ElicitBoolField(:final defaultValue?):
          _values[f.key] = defaultValue;
        case ElicitChoiceField(:final defaultValue?):
          _values[f.key] = defaultValue;
        case ElicitMultiChoiceField(:final defaultValue?):
          _values[f.key] = [...defaultValue];
        case ElicitBoolField() ||
            ElicitChoiceField() ||
            ElicitMultiChoiceField() ||
            ElicitUnsupportedField():
          break;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _answer(ElicitationResponse response) =>
      AiPaneScope.of(context).runtime.answerAsk(widget.item.id, response);

  /// The form's answer: only fields the user gave (an empty text is none).
  Map<String, Object> _content(ElicitationForm form) {
    final out = <String, Object>{};
    for (final f in form.fields) {
      final text = _text[f.key]?.text.trim();
      final Object? value = switch (f) {
        ElicitTextField() => text == null || text.isEmpty ? null : text,
        ElicitNumberField(:final integer) =>
          text == null || text.isEmpty
              ? null
              : (integer
                        ? int.tryParse(text)
                        : num.tryParse(text.replaceAll(',', '.'))) ??
                    text,
        _ => _values[f.key],
      };
      if (value != null) out[f.key] = value;
    }
    return out;
  }

  void _send(ElicitationForm form) {
    final content = _content(form);
    if (!form.accepts(content)) {
      setState(() => _invalid = true);
      return;
    }
    _answer(ElicitAccept(content));
  }

  Future<void> _open(ElicitationUrl request) async {
    try {
      await ref
          .read(desktopServicesProvider)
          .urlOpener
          .openWebLink(Uri.parse(request.url));
    } on Object catch (error) {
      debugPrint('ShellX: page not opened: ${error.runtimeType}');
      return;
    }
    if (mounted) _answer(const ElicitAccept());
  }

  Widget _field(AppLocalizations l10n, ElicitField f) {
    final label = Row(
      children: [
        Flexible(
          child: Text(
            f.title ?? f.key,
            style: ShellxText.bodyStrong.copyWith(
              color: ShellxDesktopColors.textPrimary,
            ),
          ),
        ),
        if (f.required) ...[
          const SizedBox(width: ShellxSpace.s6),
          Text(
            l10n.aiAskRequired,
            style: ShellxText.caption.copyWith(color: ShellxDesktopColors.warn),
          ),
        ],
      ],
    );
    final Widget input = switch (f) {
      ElicitTextField() || ElicitNumberField() => Shortcuts(
        shortcuts: textEditingShortcuts(),
        child: TextField(
          key: Key('ai.ask.${f.key}'),
          controller: _text[f.key],
          keyboardType: switch (f) {
            ElicitNumberField() => const TextInputType.numberWithOptions(
              decimal: true,
            ),
            ElicitTextField(format: 'email') => TextInputType.emailAddress,
            ElicitTextField(format: 'uri') => TextInputType.url,
            _ => TextInputType.text,
          },
          inputFormatters: [
            if (f case ElicitTextField(:final maxLength?))
              LengthLimitingTextInputFormatter(maxLength),
          ],
          decoration: const InputDecoration(isDense: true),
        ),
      ),
      ElicitBoolField() => Switch(
        key: Key('ai.ask.${f.key}'),
        value: _values[f.key] == true,
        onChanged: (on) => setState(() => _values[f.key] = on),
      ),
      ElicitChoiceField(:final options) => Wrap(
        spacing: ShellxSpace.s6,
        children: [
          for (final o in options)
            ChoiceChip(
              key: Key('ai.ask.${f.key}.${o.value}'),
              label: Text(o.title),
              selected: _values[f.key] == o.value,
              onSelected: (_) => setState(() => _values[f.key] = o.value),
            ),
        ],
      ),
      ElicitMultiChoiceField(:final options) => Wrap(
        spacing: ShellxSpace.s6,
        children: [
          for (final o in options)
            FilterChip(
              key: Key('ai.ask.${f.key}.${o.value}'),
              label: Text(o.title),
              selected:
                  (_values[f.key] as List<String>?)?.contains(o.value) ?? false,
              onSelected: (on) => setState(() {
                final list = [...?(_values[f.key] as List<String>?)];
                on ? list.add(o.value) : list.remove(o.value);
                _values[f.key] = list;
              }),
            ),
        ],
      ),
      ElicitUnsupportedField() => const SizedBox.shrink(),
    };
    return Padding(
      padding: const EdgeInsets.only(top: ShellxSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label,
          if (f.description case final d?)
            Text(
              d,
              style: ShellxText.small.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
          const SizedBox(height: ShellxSpace.s4),
          input,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final item = widget.item;
    final request = item.request;
    final agent = AiPaneScope.of(context).state.agentName;
    final dim = ShellxText.small.copyWith(
      color: ShellxDesktopColors.textSecondary,
    );
    if (item.autoDeclined) {
      return Text(
        '${request.message} — ${l10n.aiAskUnsupported}',
        key: const Key('ai.ask.unsupported'),
        style: dim,
      );
    }
    final response = item.response;
    if (response != null) {
      final word = switch (response) {
        ElicitAccept() when item.completed => l10n.aiAskCompleted,
        ElicitAccept() => l10n.aiAskAnswered,
        ElicitDecline() => l10n.aiAskDeclined,
        ElicitCancel() => l10n.aiAskCancelled,
      };
      return Text(
        '${request.message} — $word',
        key: const Key('ai.ask.done'),
        style: dim,
      );
    }
    final children = <Widget>[
      Text(
        request.message,
        style: ShellxText.body.copyWith(color: ShellxDesktopColors.textPrimary),
      ),
    ];
    final actions = <Widget>[];
    switch (request) {
      case ElicitationForm(:final title, :final description, :final fields):
        if (title != null) {
          children.add(Text(title, style: ShellxText.bodyStrong));
        }
        if (description != null) children.add(Text(description, style: dim));
        children.addAll([for (final f in fields) _field(l10n, f)]);
        if (_invalid) {
          children.add(
            Padding(
              padding: const EdgeInsets.only(top: ShellxSpace.s8),
              child: Text(
                l10n.aiAskInvalid,
                key: const Key('ai.ask.invalid'),
                style: ShellxText.small.copyWith(
                  color: ShellxDesktopColors.err,
                ),
              ),
            ),
          );
        }
        actions.addAll([
          FilledButton(
            key: const Key('ai.ask.send'),
            onPressed: () => _send(request),
            child: Text(l10n.aiAskSend),
          ),
          OutlinedButton(
            key: const Key('ai.ask.decline'),
            onPressed: () => _answer(const ElicitDecline()),
            child: Text(l10n.aiAskDecline),
          ),
        ]);
      case ElicitationUrl(:final url, :final isWebUrl):
        children.addAll([
          Text(l10n.aiAskUrlNote(agent), style: dim),
          SelectableText(url, key: const Key('ai.ask.url'), style: kAiMono),
        ]);
        actions.add(
          FilledButton(
            key: const Key('ai.ask.open'),
            onPressed: isWebUrl ? () => unawaited(_open(request)) : null,
            child: Text(l10n.aiAskOpen),
          ),
        );
      case ElicitationOther():
        break;
    }
    actions.add(
      TextButton(
        key: const Key('ai.ask.cancel'),
        onPressed: () => _answer(const ElicitCancel()),
        child: Text(l10n.aiAskCancel),
      ),
    );
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        key: const Key('ai.ask'),
        padding: const EdgeInsets.all(ShellxSpace.s12),
        decoration: BoxDecoration(
          color: ShellxDesktopColors.warnBg,
          borderRadius: BorderRadius.circular(ShellxRadius.r8),
          border: Border.all(color: ShellxDesktopColors.warnBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...children,
            const SizedBox(height: ShellxSpace.s12),
            Wrap(spacing: ShellxSpace.s8, children: actions),
          ],
        ),
      ),
    );
  }
}
```

In `apps/desktop/lib/src/ui/ai/ai_timeline.dart`, replace:

```dart
import 'ai_markdown.dart';
```

with:

```dart
import 'ai_ask_card.dart';
import 'ai_markdown.dart';
```

In `apps/desktop/lib/src/ui/ai/ai_timeline.dart`, replace:

```dart
  AskItem() => _AskFallback(item: item),
```

with:

```dart
  AskItem() => AiAskCard(item: item),
```

In `apps/desktop/lib/src/ui/ai/ai_timeline.dart`, replace:

```dart

class _PlainLine extends StatelessWidget {
  const _PlainLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: ShellxText.small.copyWith(color: ShellxDesktopColors.textSecondary),
  );
}

/// Until the question cards (D22) land: the agent's question and a way to
/// say no, so a turn never waits on nothing.
class _AskFallback extends StatelessWidget {
  const _AskFallback({required this.item});
  final AskItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final runtime = AiPaneScope.of(context).runtime;
    return Row(
      children: [
        Expanded(child: _PlainLine(text: item.request.message)),
        if (item.response == null && !item.autoDeclined)
          TextButton(
            onPressed: () => runtime.answerAsk(item.id, const ElicitDecline()),
            child: Text(l10n.aiAskDecline),
          ),
      ],
    );
  }
}
```

with:

```dart

```

- [ ] **Step 4: Run the tests**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/ui/ai test/ui/ai
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai test/ai test/ui/ai_tab_screens_test.dart 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `All tests passed!` (85 on the scratch copy); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/ui/ai/ai_ask_card.dart apps/desktop/lib/src/ui/ai/ai_timeline.dart apps/desktop/test/ui/ai/ai_ask_card_test.dart
git commit -m "feat(v2-ai): the agent's questions — form and URL cards, http/https only on a click

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 23: "How do you want to work?" — onboarding and the one-time intro card (D4) [needs V2-1a Task 9]

Spec D4, D5.

**New installs:** onboarding gains "How do you want to work?". AI interface or Terminal, each with its line; the answer goes to the configuration file at once as `new-tab-kind`, as Settings › General writes it. Then "You can change this any time in Settings › General."
- The question sits after the existing sections, so nothing above it moves.
- "Finish" marks the intro card done (`ai_intro_shown`).

**People who finished onboarding before V2:** they see "New: an AI interface. How should new tabs open?" once, at the foot of the sidebar above "New AI session". "AI interface" / "Terminal" write the same key; × only closes the card. Either way the card never comes back.
- Whether onboarding is done comes from the agent controller's state: the UI never reads a daemon key (`settings_ownership_test`).
- The card's buttons are not Tab stops, like the button under them.
- `TestHarness` marks the card done by default, as it does the tour, so other tests never meet it.

**Files:**
- Create: `apps/desktop/lib/src/ui/ai/ai_intro.dart`
- Modify: `apps/desktop/lib/src/ui/pages/onboarding_page.dart`, `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, `apps/desktop/test/support/fakes.dart`
- Test: `apps/desktop/test/ui/ai/ai_intro_test.dart`

**Interfaces:**
- Consumes: Task 8 `new-tab-kind` (`settingById`, `NewTabKind`), `SettingKeys.aiIntroShown`; `settingsWriterProvider.set(SettingDef, String) → SettingsWrite` (`Saved`); `agentControllerProvider` (`onboardingDone`); Task 19's sidebar foot.
- Produces: `chooseNewTabKind(WidgetRef, NewTabKind)`; `aiIntroDueProvider` (`AiIntroDue.done()`); `AiOnboardingChoice`; `AiIntroCard`; keys `onboarding.ai`, `onboarding.terminal`, `ai.intro`, `ai.intro.ai`, `ai.intro.terminal`, `ai.intro.close`.

- [ ] **Step 1: Write the failing test**

`apps/desktop/test/ui/ai/ai_intro_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/agent/agent_controller.dart';
import 'package:shellx_desktop/src/agent/desktop_services.dart';
import 'package:shellx_desktop/src/platform/settings_store.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/ai/ai_intro.dart';
import 'package:shellx_desktop/src/ui/app.dart';
import 'package:shellx_desktop/src/ui/window_router.dart';

import '../../support/ai_fakes.dart';
import '../../support/config_harness.dart';
import '../../support/config_workspace.dart';
import '../../support/fakes.dart';
import '../../support/memory_config_fs.dart';

/// V2-1 D4: how new tabs open — onboarding's question and the one-time card.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets('onboarding asks "How do you want to work?"; the answer is '
      'written to the file; Finish marks the intro card done', (t) async {
    final h = TestHarness(settings: {SettingKeys.aiIntroShown: false});
    final fs = MemoryConfigFs();
    final c = ProviderContainer(
      overrides: [
        desktopServicesProvider.overrideWithValue(h.services()),
        ...configOverrides(fs),
      ],
    );
    addTearDown(c.dispose);
    await loadConfig(c);
    t.view.physicalSize = const Size(1100, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const ShellxDesktopApp(locale: Locale('en')),
      ),
    );
    c.read(windowRouterProvider.notifier).open(const OnboardingRoute());
    await t.pumpAndSettle();
    expect(find.text('How do you want to work?'), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('onboarding.ai')));
    await t.tap(find.byKey(const Key('onboarding.ai')));
    await t.pumpAndSettle();
    expect(fs.text(testConfigPaths().shellx), contains('new-tab-kind = ai'));
    await t.tap(find.byKey(const Key('onboarding.finish')));
    await t.pumpAndSettle();
    expect(c.read(agentControllerProvider).onboardingDone, isTrue);
    expect(
      h.settings.getBool(SettingKeys.aiIntroShown, defaultValue: false),
      isTrue,
    );
  });

  testWidgets('someone from before V2 sees the card once; "AI interface" '
      'writes the file, and ⌘T opens AI sessions from then on', (t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final h = TestHarness(
      settings: {
        SettingKeys.onboardingDone: true,
        SettingKeys.aiIntroShown: false,
      },
    );
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      harness: h,
      extra: fakes.overrides,
    );
    expect(
      find.text('New: an AI interface. How should new tabs open?'),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('ai.intro.ai')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.intro')), findsNothing);
    expect(w.fs.text(testConfigPaths().shellx), contains('new-tab-kind = ai'));
    expect(
      h.settings.getBool(SettingKeys.aiIntroShown, defaultValue: false),
      isTrue,
    );
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyT);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pumpAndSettle();
    expect(w.container.read(terminalTabsProvider).selected!.isAi, isTrue);
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  testWidgets('× closes the card for good and changes nothing', (t) async {
    final h = TestHarness(
      settings: {
        SettingKeys.onboardingDone: true,
        SettingKeys.aiIntroShown: false,
      },
    );
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      harness: h,
    );
    await t.tap(find.byKey(const Key('ai.intro.close')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.intro')), findsNothing);
    expect(w.fs.files, isEmpty, reason: 'no configuration was written');
    expect(
      h.settings.getBool(SettingKeys.aiIntroShown, defaultValue: false),
      isTrue,
    );
    await disposeWorkspace(t, w.container);
  }, variant: mac);

  test('a new install never gets the card (onboarding asks)', () {
    final h = TestHarness(settings: {SettingKeys.aiIntroShown: false});
    final c = ProviderContainer.test(
      overrides: [desktopServicesProvider.overrideWithValue(h.services())],
    );
    expect(c.read(aiIntroDueProvider), isFalse);
  });
}
```

`TestHarness` keeps the card out of every other test (as it keeps the tour):

In `apps/desktop/test/support/fakes.dart`, replace:

```dart
         // A11 D24: the first-run tour is its own tests' business.
         SettingKeys.tourDone: true,
```

with:

```dart
         // A11 D24: the first-run tour is its own tests' business.
         SettingKeys.tourDone: true,
         // V2-1 D4: so is the AI intro card.
         SettingKeys.aiIntroShown: true,
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai/ai_intro_test.dart`
Expected: the test does not compile, `Error when reading 'lib/src/ui/ai/ai_intro.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/ui/ai/ai_intro.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/agent_controller.dart';
import '../../config/config_controller.dart' show shellxConfigProvider;
import '../../config/shellx_config.dart' show NewTabKind;
import '../../platform/settings_store.dart';
import '../../terminal/sidebar_workspaces.dart' show settingsStoreProvider;
import '../settings/pages/page_parts.dart' show settingById;
import '../settings/settings_writer.dart';
import '../theme/shellx_desktop_theme.dart';

/// D4: how new tabs open, written to the configuration file as
/// `new-tab-kind` (as Settings › General writes it). Never throws.
Future<void> chooseNewTabKind(WidgetRef ref, NewTabKind kind) async {
  final result = await ref
      .read(settingsWriterProvider)
      .set(settingById('new-tab-kind'), kind.name);
  if (result is! Saved) {
    debugPrint('ShellX: new-tab-kind not saved: ${result.runtimeType}');
  }
}

/// D4: the one-time "New: an AI interface" card is due — for someone who
/// finished onboarding before V2 and has not answered it (`ai_intro_shown`).
/// Onboarding itself asks the question, so it marks the card done.
final aiIntroDueProvider = NotifierProvider<AiIntroDue, bool>(AiIntroDue.new);

class AiIntroDue extends Notifier<bool> {
  @override
  bool build() {
    // Onboarding is the agent's to know (a daemon key): its state, not the
    // store.
    final onboarded = ref.watch(
      agentControllerProvider.select((s) => s.onboardingDone),
    );
    return onboarded &&
        !ref
            .read(settingsStoreProvider)
            .getBool(SettingKeys.aiIntroShown, defaultValue: false);
  }

  /// Answered or closed: never again. Never throws.
  Future<void> done() async {
    state = false;
    try {
      await ref
          .read(settingsStoreProvider)
          .setBool(SettingKeys.aiIntroShown, true);
    } on Object catch (error) {
      debugPrint('ShellX: intro not saved: ${error.runtimeType}');
    }
  }
}

/// D4: onboarding's "How do you want to work?" — AI interface or Terminal,
/// written at once; "You can change this any time in Settings › General."
class AiOnboardingChoice extends ConsumerWidget {
  const AiOnboardingChoice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final kind = ref.watch(
      shellxConfigProvider.select((s) => s.config.newTabKind),
    );
    Widget option(NewTabKind value, String title, String body, Key key) {
      final on = kind == value;
      return Semantics(
        selected: on,
        button: true,
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(ShellxRadius.r6),
          onTap: () => unawaited(chooseNewTabKind(ref, value)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: ShellxSpace.s6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  on
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: on
                      ? ShellxDesktopColors.accent
                      : ShellxDesktopColors.textSecondary,
                ),
                const SizedBox(width: ShellxSpace.s8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.bodyLarge),
                      Text(body, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.aiOnboardingTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: ShellxSpace.s4),
        option(
          NewTabKind.ai,
          l10n.aiNewTabKindAi,
          l10n.aiOnboardingAiBody,
          const Key('onboarding.ai'),
        ),
        option(
          NewTabKind.terminal,
          l10n.aiNewTabKindTerminal,
          l10n.aiOnboardingTerminalBody,
          const Key('onboarding.terminal'),
        ),
        Text(l10n.aiOnboardingNote, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// D4: the one-time card for people who knew ShellX before V2, at the foot
/// of the sidebar: "New: an AI interface. How should new tabs open?" — AI
/// interface / Terminal / ×. Nothing when it is not due.
class AiIntroCard extends ConsumerWidget {
  const AiIntroCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(aiIntroDueProvider)) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final intro = ref.read(aiIntroDueProvider.notifier);
    Future<void> pick(NewTabKind kind) async {
      await chooseNewTabKind(ref, kind);
      await intro.done();
    }

    return Container(
      key: const Key('ai.intro'),
      margin: const EdgeInsets.fromLTRB(
        ShellxSpace.s8,
        ShellxSpace.s4,
        ShellxSpace.s8,
        0,
      ),
      padding: const EdgeInsets.fromLTRB(
        ShellxSpace.s8,
        ShellxSpace.s4,
        0,
        ShellxSpace.s8,
      ),
      decoration: BoxDecoration(
        color: ShellxDesktopColors.surface,
        borderRadius: BorderRadius.circular(ShellxRadius.r8),
        border: Border.all(color: ShellxDesktopColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 14,
                color: ShellxDesktopColors.accent,
              ),
              const SizedBox(width: ShellxSpace.s6),
              Expanded(
                child: Text(
                  l10n.aiIntroText,
                  style: ShellxText.small.copyWith(
                    color: ShellxDesktopColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                key: const Key('ai.intro.close'),
                tooltip: l10n.actionClose,
                iconSize: 14,
                visualDensity: VisualDensity.compact,
                onPressed: () => unawaited(intro.done()),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Wrap(
            spacing: ShellxSpace.s6,
            children: [
              OutlinedButton(
                key: const Key('ai.intro.ai'),
                onPressed: () => unawaited(pick(NewTabKind.ai)),
                child: Text(l10n.aiNewTabKindAi),
              ),
              TextButton(
                key: const Key('ai.intro.terminal'),
                onPressed: () => unawaited(pick(NewTabKind.terminal)),
                child: Text(l10n.aiNewTabKindTerminal),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

In `apps/desktop/lib/src/ui/pages/onboarding_page.dart`, replace:

```dart
import '../../platform/url_opener.dart';
import '../dialogs/dialog_layout.dart';
```

with:

```dart
import '../../platform/url_opener.dart';
import '../ai/ai_intro.dart';
import '../dialogs/dialog_layout.dart';
```

In `apps/desktop/lib/src/ui/pages/onboarding_page.dart`, replace:

```dart
        Text(
          l10n.onboardingTrayHint(isMac ? 'macos' : 'windows'),
          style: theme.textTheme.bodySmall,
        ),
      ],
```

with:

```dart
        Text(
          l10n.onboardingTrayHint(isMac ? 'macos' : 'windows'),
          style: theme.textTheme.bodySmall,
        ),
        // V2-1 D4: how new tabs open (`new-tab-kind`).
        const SizedBox(height: ShellxSpace.s16),
        const AiOnboardingChoice(),
      ],
```

In `apps/desktop/lib/src/ui/pages/onboarding_page.dart`, replace:

```dart
          onPressed: () async {
            await agent.completeOnboarding();
```

with:

```dart
          onPressed: () async {
            // V2-1 D4: asked here, so the intro card never comes.
            await ref.read(aiIntroDueProvider.notifier).done();
            await agent.completeOnboarding();
```

In `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, replace:

```dart
import '../../ai/ai_open.dart';
```

with:

```dart
import '../../ai/ai_open.dart';
import '../ai/ai_intro.dart';
```

In `apps/desktop/lib/src/ui/terminal/session_sidebar.dart`, replace:

```dart
          // V2-1 D5: "New AI session" at the foot of the sidebar. Not a Tab
          // stop (⌘⇧E is the keyboard's way): Tab keeps going sidebar →
          // strip → terminal.
          FocusTraversalGroup(
```

with:

```dart
          // V2-1 D4: the one-time intro card (nothing when it is not due).
          FocusTraversalGroup(
            descendantsAreTraversable: false,
            child: const AiIntroCard(),
          ),
          // V2-1 D5: "New AI session" at the foot of the sidebar. Not a Tab
          // stop (⌘⇧E is the keyboard's way): Tab keeps going sidebar →
          // strip → terminal.
          FocusTraversalGroup(
```

- [ ] **Step 4: Run the whole suite**

The sidebar, onboarding and `TestHarness` change: run everything.

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/ui/ai lib/src/ui/pages/onboarding_page.dart lib/src/ui/terminal/session_sidebar.dart test/ui/ai test/support/fakes.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `All other tests passed!` (3 220 passing, 10 skipped on the scratch copy); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/ui/ai/ai_intro.dart apps/desktop/lib/src/ui/pages/onboarding_page.dart apps/desktop/lib/src/ui/terminal/session_sidebar.dart apps/desktop/test/support/fakes.dart apps/desktop/test/ui/ai/ai_intro_test.dart
git commit -m "feat(v2-ai): ask how new tabs open — onboarding step and a one-time card for existing users

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 24: Settings › Agents — the AI interface section (D7, D12, D21, D23) [needs V2-1a Task 9]

Spec D7, D8, D12 (cleanup), D21, D23.

**Where:** a new "AI interface" section at the end of Settings › Agents, so A12's rows keep their place.

**What it holds:**
- **The Claude switch** (`ai-agent-claude`, Task 8).
- **One row per agent** with its state, as an icon and a word: Ready / Needs Node N / Not installed / Needs sign-in / Error / Checking…. A command that is not there says so, with the Windows `.cmd`/`.bat` note when that is all there is; npm missing says so.
- **Install** runs the pinned install in the run sheet (Task 18), in a dialog, and its folder is made first.
- **Sign in** shows only while a session of that agent is waiting for a sign-in: only that session knows the agent's methods, and ShellX never opens a session just to check (D7). It runs the agent's own login in the run sheet, then reopens that session.
- **The default agent**; **custom agents** (name, command, args one per line, env `NAME=value` per line) to add and remove.
- **Restore points:** `ai-checkpoint-days`, and "Delete all restore points", asked first and run through a seam.

**Checks:** opening the section checks every agent again, after the first frame. A check that fails shows "Error": `AiReadiness` keeps the failed ids. A window without the AI host (a test of something else) gets a failed check instead of a broken provider, because the readiness source now reads the host only when asked.

**Files:**
- Create: `apps/desktop/lib/src/ui/ai/ai_agents_section.dart`
- Modify: `apps/desktop/lib/src/ai/ai_agents.dart`, `apps/desktop/lib/src/ui/settings/pages/agents_page.dart`
- Test: `apps/desktop/test/ui/ai/ai_agents_settings_test.dart`

**Interfaces:**
- Consumes:
  - Task 10 `aiAgentsProvider`, `aiReadinessProvider` (`refresh`), `aiReadinessSourceProvider`, `aiNeedsLoginProvider`, `aiCustomAgentsProvider` (`add`, `remove`), `aiDefaultAgentChoiceProvider`, `aiDefaultAgentProvider`, `aiRuntimesProvider.existing`;
  - Task 18 `AiRunSheet`, `aiMakeFolderProvider`; Task 11 `aiPtyFactoryProvider`; Task 8 settings `ai-agent-claude`, `ai-checkpoint-days`;
  - `PageFrame`, `SectionHeader`, `ActionRow`, `settingWidget`, `settingById`;
  - V2-1a `AgentReady` / `AgentNeedsNode` / `AgentNeedsInstall` / `AgentNotFound` (`shimOnly`), `AiRuntime.state.authMethods`, `AiRuntime.loginCommand`, `AiRuntime.retry`, `AiHost.checkpoints.deleteAll()`.
- Produces: `AiAgentsSection`; `aiDeleteCheckpointsProvider`; `aiAgentStatus(l10n, readiness, {needsLogin, failed})`; `AiReadiness.failed`; keys `ai.settings`, `ai.agent.<id>`, `ai.agent.status.<id>`, `ai.agent.install.<id>`, `ai.agent.signin.<id>`, `ai.agent.remove.<id>`, `ai.defaultAgent`, `ai.custom.name|command|args|env|save|invalid`, `ai.checkpoints`, `ai.checkpoints.cancel|delete`.

- [ ] **Step 1: Write the failing test**

`apps/desktop/test/ui/ai/ai_agents_settings_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_agents.dart';
import 'package:shellx_desktop/src/ai/ai_folders.dart';
import 'package:shellx_desktop/src/ai/ai_startup.dart';
import 'package:shellx_desktop/src/config/settings_schema.dart';
import 'package:shellx_desktop/src/ui/ai/ai_agents_section.dart';
import 'package:shellx_desktop/src/ui/config/config_ui_request.dart';
import 'package:shellx_desktop/src/ui/settings/pages/agents_page.dart';
import 'package:shellx_desktop/src/ui/settings/settings_start_page.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_tabs.dart';
import '../../support/config_workspace.dart';
import 'ai_run_sheet_test.dart' show SheetPtys;

const _install = AgentCommand(
  executable: '/usr/local/bin/node',
  args: ['/usr/local/lib/node_modules/npm/bin/npm-cli.js', 'install'],
  environment: {'TERM': 'dumb'},
  workingDirectory: '/support/ai/agents/codex',
);

/// V2-1 D7, D12, D21, D23: Settings › Agents › AI interface.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<void> openAgents(WidgetTester t, ProviderContainer c) async {
    c.read(settingsStartPageProvider.notifier).set(SettingPage.agents);
    c.read(configUiRequestProvider.notifier).request(ConfigUiRequest.settings);
    await t.pumpAndSettle();
    expect(find.byType(AgentsPage), findsOneWidget);
  }

  /// Scrolls Agents until [target] is built (a lazy list), then to it.
  Future<void> reveal(WidgetTester t, Finder target) async {
    final list = find
        .descendant(
          of: find.byType(AgentsPage),
          matching: find.byType(ListView),
        )
        .first;
    for (var n = 0; n < 24 && target.evaluate().isEmpty; n++) {
      await t.drag(list, const Offset(0, -200));
      await t.pump();
    }
    await t.ensureVisible(target);
    await t.pumpAndSettle();
  }

  String status(WidgetTester t, String id) =>
      t.widget<Text>(find.byKey(Key('ai.agent.status.$id'))).data!;

  testWidgets('one row per agent with its state; Install runs in the run '
      'sheet; the default agent', (t) async {
    var installed = false;
    final ptys = SheetPtys();
    final made = <String>[];
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: [
        aiReadinessSourceProvider.overrideWithValue(
          (agent) async => switch (agent.id) {
            'claude' => const AgentReady(AgentCommand(executable: 'node')),
            'codex' =>
              installed
                  ? const AgentReady(AgentCommand(executable: 'node'))
                  : const AgentNeedsInstall(_install),
            'gemini' => const AgentNeedsNode(required: 20, found: 'v18.0.0'),
            _ => const AgentNotFound('opencode'),
          },
        ),
        aiPtyFactoryProvider.overrideWithValue(ptys),
        aiMakeFolderProvider.overrideWithValue((path) async => made.add(path)),
      ],
    );
    final c = w.container;
    await openAgents(t, c);
    await reveal(t, find.byKey(const Key('ai.defaultAgent')));
    expect(status(t, 'claude'), 'Ready');
    expect(status(t, 'codex'), 'Not installed');
    expect(status(t, 'gemini'), 'Needs Node 20');
    expect(status(t, 'opencode'), 'Not installed');
    expect(find.text('Command not found: opencode'), findsOneWidget);
    await reveal(t, find.byKey(const Key('ai.agent.install.codex')));
    await t.tap(find.byKey(const Key('ai.agent.install.codex')));
    await t.pumpAndSettle();
    expect(find.text('Install Codex'), findsOneWidget);
    expect(made, ['/support/ai/agents/codex']);
    final run = ptys.spawned.single;
    expect(run.command.executable, '/usr/local/bin/node');
    expect(run.env['TERM'], 'xterm-256color');
    installed = true;
    run.pty.exit(0);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.runSheet')), findsNothing);
    expect(status(t, 'codex'), 'Ready');
    await reveal(t, find.byKey(const Key('ai.defaultAgent')));
    await t.tap(find.byKey(const Key('ai.defaultAgent')));
    await t.pumpAndSettle();
    await t.tap(find.text('Codex').last);
    await t.pumpAndSettle();
    expect(c.read(aiDefaultAgentChoiceProvider), 'codex');
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a custom agent needs a name and a command; it is added with '
      'its args and env, and removed', (t) async {
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: [
        aiReadinessSourceProvider.overrideWithValue(
          (_) async => const AgentNotFound('x'),
        ),
      ],
    );
    final c = w.container;
    await openAgents(t, c);
    await reveal(t, find.byKey(const Key('ai.custom.save')));
    await t.tap(find.byKey(const Key('ai.custom.save')));
    await t.pumpAndSettle();
    expect(find.text('Enter a name and a command.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('ai.custom.name')), 'Local');
    await t.enterText(
      find.byKey(const Key('ai.custom.command')),
      '/usr/local/bin/my-agent',
    );
    await t.enterText(find.byKey(const Key('ai.custom.args')), 'acp\n--fast');
    await t.enterText(find.byKey(const Key('ai.custom.env')), 'TOKEN=x\nBAD');
    await t.tap(find.byKey(const Key('ai.custom.save')));
    await t.pumpAndSettle();
    final agent = c.read(aiCustomAgentsProvider).single;
    expect(agent.name, 'Local');
    expect(agent.command, '/usr/local/bin/my-agent');
    expect(agent.args, ['acp', '--fast']);
    expect(agent.env, {'TOKEN': 'x'});
    await reveal(t, find.byKey(Key('ai.agent.remove.${agent.id}')));
    await t.tap(find.byKey(Key('ai.agent.remove.${agent.id}')));
    await t.pumpAndSettle();
    expect(c.read(aiCustomAgentsProvider), isEmpty);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('the Claude switch and "Delete all restore points" (asked '
      'first)', (t) async {
    var deleted = 0;
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: [
        aiReadinessSourceProvider.overrideWithValue(
          (_) async => const AgentNotFound('x'),
        ),
        aiDeleteCheckpointsProvider.overrideWithValue(() async => deleted++),
      ],
    );
    final c = w.container;
    await openAgents(t, c);
    await reveal(t, find.byKey(const Key('ai.checkpoints')));
    expect(find.byKey(const ValueKey('row.ai-agent-claude')), findsOneWidget);
    await t.tap(
      find.descendant(
        of: find.byKey(const Key('ai.checkpoints')),
        matching: find.byType(OutlinedButton),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Delete all restore points?'), findsOneWidget);
    await t.tap(find.byKey(const Key('ai.checkpoints.delete')));
    await t.pumpAndSettle();
    expect(deleted, 1);
    expect(find.text('Restore points deleted.'), findsOneWidget);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('Sign in runs the agent\'s own login from the session that '
      'met it; the session opens', (t) async {
    final auth = Directory.systemTemp.createTempSync('ai_auth');
    addTearDown(() => auth.deleteSync(recursive: true));
    final fakes = FakeAiRuntimes(
      FakeScenario(
        requireAuth: true,
        authFile: '${auth.path}/signed-in',
        authMethods: const [
          {
            'id': 'login',
            'name': 'Log in',
            'type': 'terminal',
            'args': ['/login'],
          },
        ],
      ),
    );
    final ptys = SheetPtys();
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: [...fakes.overrides, aiPtyFactoryProvider.overrideWithValue(ptys)],
    );
    final c = w.container;
    openTestAiTab(c, cwd: testAiCwd);
    await t.pumpAndSettle();
    expect(fakes.made.single.state.phase, AgentPhase.needsAuth);
    await openAgents(t, c);
    await reveal(t, find.byKey(const Key('ai.agent.signin.claude')));
    expect(status(t, 'claude'), 'Needs sign-in');
    await t.tap(find.byKey(const Key('ai.agent.signin.claude')));
    await t.pumpAndSettle();
    final run = ptys.spawned.single;
    expect(run.command.arguments, ['/login']);
    File('${auth.path}/signed-in').writeAsStringSync('ok');
    run.pty.exit(0);
    await t.pumpAndSettle();
    expect(fakes.made.single.state.phase, AgentPhase.ready);
    expect(status(t, 'claude'), 'Ready');
    await disposeWorkspace(t, c);
  }, variant: mac);
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai/ai_agents_settings_test.dart`
Expected: the test does not compile, `Error when reading 'lib/src/ui/ai/ai_agents_section.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/ui/ai/ai_agents_section.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_acp/shellx_acp.dart' show AuthMethodTerminal;
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../../l10n/app_localizations.dart';
import '../../ai/ai_agents.dart';
import '../../ai/ai_host_provider.dart';
import '../../ai/ai_runtimes.dart';
import '../../terminal/local_sessions_provider.dart' show homeDirectoryProvider;
import '../../terminal/terminal_tabs.dart';
import '../settings/pages/page_parts.dart';
import '../text_editing_shortcuts.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_run_sheet.dart';

/// D12: "Delete all restore points" (every project's). A seam: widget tests
/// never delete folders under fake async.
final aiDeleteCheckpointsProvider = Provider<Future<void> Function()>(
  (ref) =>
      () => ref.read(aiHostProvider).checkpoints.deleteAll(),
);

/// D7's words for an agent's state ("Checking…" until its first check).
String aiAgentStatus(
  AppLocalizations l10n,
  AgentReadiness? r, {
  required bool needsLogin,
  required bool failed,
}) {
  if (failed) return l10n.aiAgentError;
  return switch (r) {
    null => l10n.aiAgentChecking,
    AgentReady() => needsLogin ? l10n.aiAgentNeedsLogin : l10n.aiAgentReady,
    AgentNeedsNode(:final required) => l10n.aiAgentNeedsNode(required),
    AgentNeedsInstall() || AgentNotFound() => l10n.aiAgentNotInstalled,
  };
}

/// V2-1 D7, D21, D23, D12: Settings › Agents › "AI interface".
/// - The Claude switch (`ai-agent-claude`).
/// - One row per agent with its state (Ready / Needs Node N / Not installed /
///   Needs sign-in / Error), and Install or Sign in, which run in the run
///   sheet (D8), never in a terminal tab. Sign in uses the session that
///   met the sign-in (only it knows the agent's methods).
/// - The default agent; custom agents (name, command, args, env) to add
///   and remove.
/// - How long restore points stay, and "Delete all restore points".
/// The agents are checked again when the section opens.
class AiAgentsSection extends ConsumerStatefulWidget {
  const AiAgentsSection({super.key});

  @override
  ConsumerState<AiAgentsSection> createState() => _AiAgentsSectionState();
}

class _AiAgentsSectionState extends ConsumerState<AiAgentsSection> {
  String? _note;

  @override
  void initState() {
    super.initState();
    // Not while building: the check runs the login shell and probes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(aiReadinessProvider.notifier).refresh());
    });
  }

  Future<void> _sheet(Widget Function(VoidCallback close) build) =>
      showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: SizedBox(
            width: 720,
            height: 440,
            child: build(() => Navigator.of(context).pop()),
          ),
        ),
      );

  Future<void> _install(AgentSpec agent, AgentCommand install) {
    final l10n = AppLocalizations.of(context);
    final folder = install.workingDirectory;
    return _sheet(
      (close) => AiRunSheet(
        title: l10n.aiRunSheetInstall(agent.name),
        command: install,
        workingDirectory: folder ?? ref.read(homeDirectoryProvider),
        makeFolder: folder != null,
        onDone: () {
          close();
          unawaited(ref.read(aiReadinessProvider.notifier).refresh());
        },
        onClose: close,
      ),
    );
  }

  /// A live session of [agentId] that is waiting for a sign-in.
  AiRuntime? _signingIn(String agentId) {
    final runtimes = ref.read(aiRuntimesProvider.notifier);
    for (final tab in ref.read(terminalTabsProvider).tabs) {
      final ai = tab.ai;
      if (ai == null || ai.agentId != agentId) continue;
      final runtime = runtimes.existing(ai.id);
      if (runtime?.state.phase == AgentPhase.needsAuth) return runtime;
    }
    return null;
  }

  Future<void> _signIn(AgentSpec agent) async {
    final l10n = AppLocalizations.of(context);
    final runtime = _signingIn(agent.id);
    final method = runtime?.state.authMethods
        .whereType<AuthMethodTerminal>()
        .firstOrNull;
    final command = method == null ? null : runtime!.loginCommand(method);
    if (runtime == null || command == null) return;
    await _sheet(
      (close) => AiRunSheet(
        title: l10n.aiRunSheetLogin(agent.name),
        command: command,
        workingDirectory: runtime.state.cwd,
        failureNote: l10n.aiLoginFailed,
        onDone: () {
          close();
          unawaited(runtime.retry());
        },
        onClose: close,
      ),
    );
  }

  Future<void> _deleteCheckpoints() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.aiDeleteCheckpointsTitle),
        content: Text(l10n.aiDeleteCheckpointsBody),
        actions: [
          TextButton(
            key: const Key('ai.checkpoints.cancel'),
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            key: const Key('ai.checkpoints.delete'),
            style: destructiveButtonStyle(),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.aiDeleteCheckpoints),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(aiDeleteCheckpointsProvider)();
      if (mounted) setState(() => _note = l10n.aiDeleteCheckpointsDone);
    } on Object catch (error) {
      debugPrint('ShellX: restore points not deleted: ${error.runtimeType}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final agents = ref.watch(aiAgentsProvider);
    final readiness = ref.watch(aiReadinessProvider);
    final failed = ref.read(aiReadinessProvider.notifier).failed;
    final needsLogin = ref.watch(aiNeedsLoginProvider);
    final custom = {for (final c in ref.watch(aiCustomAgentsProvider)) c.id};
    final chosen = ref.watch(aiDefaultAgentProvider);
    // Keeps Settings in step with a session that meets a sign-in.
    ref.watch(terminalTabsProvider.select((t) => t.tabs.length));
    return Column(
      key: const Key('ai.settings'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(l10n.aiSettingsSection),
        settingWidget(settingById('ai-agent-claude')),
        for (final agent in agents)
          _AgentRow(
            agent: agent,
            status: aiAgentStatus(
              l10n,
              readiness[agent.id],
              needsLogin: needsLogin.contains(agent.id),
              failed: failed.contains(agent.id),
            ),
            readiness: readiness[agent.id],
            onInstall: switch (readiness[agent.id]) {
              AgentNeedsInstall(:final install?) => () => unawaited(
                _install(agent, install),
              ),
              _ => null,
            },
            onSignIn:
                needsLogin.contains(agent.id) && _signingIn(agent.id) != null
                ? () => unawaited(_signIn(agent))
                : null,
            onRemove: custom.contains(agent.id)
                ? () => unawaited(
                    ref.read(aiCustomAgentsProvider.notifier).remove(agent.id),
                  )
                : null,
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.aiDefaultAgent,
                  style: ShellxText.body.copyWith(
                    color: ShellxDesktopColors.textPrimary,
                  ),
                ),
              ),
              DropdownButton<String>(
                key: const Key('ai.defaultAgent'),
                value: chosen?.id,
                items: [
                  for (final a in agents)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (id) {
                  if (id == null) return;
                  unawaited(
                    ref.read(aiDefaultAgentChoiceProvider.notifier).set(id),
                  );
                },
              ),
            ],
          ),
        ),
        const _CustomAgentForm(),
        settingWidget(settingById('ai-checkpoint-days')),
        ActionRow(
          key: const Key('ai.checkpoints'),
          label: l10n.aiDeleteCheckpoints,
          button: l10n.aiDeleteCheckpoints,
          caption: _note,
          onPressed: () => unawaited(_deleteCheckpoints()),
        ),
      ],
    );
  }
}

class _AgentRow extends StatelessWidget {
  const _AgentRow({
    required this.agent,
    required this.status,
    required this.readiness,
    required this.onInstall,
    required this.onSignIn,
    required this.onRemove,
  });

  final AgentSpec agent;
  final String status;
  final AgentReadiness? readiness;
  final VoidCallback? onInstall;
  final VoidCallback? onSignIn;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ready = readiness is AgentReady && onSignIn == null;
    final captions = [
      if (readiness case AgentNotFound(:final command, :final shimOnly)) ...[
        l10n.aiCommandMissing(command),
        if (shimOnly) l10n.aiCommandShimOnly,
      ],
      if (readiness case AgentNeedsInstall(install: null)) l10n.aiNoNpm,
    ];
    final small = ShellxText.small.copyWith(
      color: ShellxDesktopColors.textSecondary,
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Padding(
        key: Key('ai.agent.${agent.id}'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(
                        agent.name,
                        style: ShellxText.body.copyWith(
                          color: ShellxDesktopColors.textPrimary,
                        ),
                      ),
                      // An icon and a word: never colour alone.
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ExcludeSemantics(
                            child: Icon(
                              ready
                                  ? Icons.check_circle_outline
                                  : Icons.circle_outlined,
                              size: ShellxSizes.icon,
                              color: ready
                                  ? ShellxDesktopColors.ok
                                  : ShellxDesktopColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            status,
                            key: Key('ai.agent.status.${agent.id}'),
                            style: small,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onInstall case final install?)
                  OutlinedButton(
                    key: Key('ai.agent.install.${agent.id}'),
                    onPressed: install,
                    child: Text(l10n.aiInstall),
                  ),
                if (onSignIn case final signIn?)
                  OutlinedButton(
                    key: Key('ai.agent.signin.${agent.id}'),
                    onPressed: signIn,
                    child: Text(l10n.aiAgentLogin),
                  ),
                if (onRemove case final remove?)
                  TextButton(
                    key: Key('ai.agent.remove.${agent.id}'),
                    onPressed: remove,
                    child: Text(l10n.aiCustomRemove),
                  ),
              ],
            ),
            for (final c in captions) Text(c, style: small),
          ],
        ),
      ),
    );
  }
}

/// D7 (4): a custom agent — any program that speaks ACP on stdin/stdout.
class _CustomAgentForm extends ConsumerStatefulWidget {
  const _CustomAgentForm();

  @override
  ConsumerState<_CustomAgentForm> createState() => _CustomAgentFormState();
}

class _CustomAgentFormState extends ConsumerState<_CustomAgentForm> {
  final _name = TextEditingController();
  final _command = TextEditingController();
  final _args = TextEditingController();
  final _env = TextEditingController();
  var _invalid = false;

  @override
  void dispose() {
    _name.dispose();
    _command.dispose();
    _args.dispose();
    _env.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final command = _command.text.trim();
    if (name.isEmpty || command.isEmpty) {
      setState(() => _invalid = true);
      return;
    }
    final env = <String, String>{};
    for (final line in _env.text.split('\n')) {
      final eq = line.indexOf('=');
      final key = eq <= 0 ? '' : line.substring(0, eq).trim();
      if (key.isNotEmpty) env[key] = line.substring(eq + 1);
    }
    await ref
        .read(aiCustomAgentsProvider.notifier)
        .add(
          name: name,
          command: command,
          args: [
            for (final a in _args.text.split('\n'))
              if (a.trim().isNotEmpty) a.trim(),
          ],
          env: env,
        );
    if (!mounted) return;
    _name.clear();
    _command.clear();
    _args.clear();
    _env.clear();
    setState(() => _invalid = false);
    unawaited(ref.read(aiReadinessProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget field(
      TextEditingController c,
      String label,
      Key key, {
      int? lines,
    }) => Padding(
      padding: const EdgeInsets.only(top: ShellxSpace.s6),
      child: Shortcuts(
        shortcuts: textEditingShortcuts(),
        child: TextField(
          key: key,
          controller: c,
          minLines: lines,
          maxLines: lines == null ? 1 : lines + 2,
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.aiAddCustomAgent,
            style: ShellxText.body.copyWith(
              color: ShellxDesktopColors.textPrimary,
            ),
          ),
          field(_name, l10n.aiCustomName, const Key('ai.custom.name')),
          field(_command, l10n.aiCustomCommand, const Key('ai.custom.command')),
          field(
            _args,
            l10n.aiCustomArgs,
            const Key('ai.custom.args'),
            lines: 2,
          ),
          field(_env, l10n.aiCustomEnv, const Key('ai.custom.env'), lines: 2),
          if (_invalid)
            Padding(
              padding: const EdgeInsets.only(top: ShellxSpace.s4),
              child: Text(
                l10n.aiCustomInvalid,
                key: const Key('ai.custom.invalid'),
                style: ShellxText.small.copyWith(
                  color: ShellxDesktopColors.err,
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: ShellxSpace.s8),
              child: FilledButton(
                key: const Key('ai.custom.save'),
                onPressed: () => unawaited(_save()),
                child: Text(l10n.aiCustomSave),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

In `apps/desktop/lib/src/ai/ai_agents.dart`, replace:

```dart
final aiReadinessSourceProvider =
    Provider<Future<AgentReadiness> Function(AgentSpec agent)>((ref) {
      final host = ref.read(aiHostProvider);
      return (agent) async =>
          host.resolver.resolve(agent, await host.env.resolve());
    });
```

with:

```dart
final aiReadinessSourceProvider =
    Provider<Future<AgentReadiness> Function(AgentSpec agent)>(
      (ref) => (agent) async {
        // Read when asked: a window without the AI host (a test of
        // something else) gets a failed check, never a broken provider.
        final host = ref.read(aiHostProvider);
        return host.resolver.resolve(agent, await host.env.resolve());
      },
    );
```

In `apps/desktop/lib/src/ai/ai_agents.dart`, replace:

```dart
  Future<void>? _warm;

  @override
  Map<String, AgentReadiness> build() => const {};
```

with:

```dart
  Future<void>? _warm;

  /// Agents whose last check failed: Settings › Agents says "Error".
  final failed = <String>{};

  @override
  Map<String, AgentReadiness> build() => const {};
```

In `apps/desktop/lib/src/ai/ai_agents.dart`, replace:

```dart
      try {
        final r = await source(agent);
        if (!ref.mounted) return;
        state = {...state, agent.id: r};
      } on Object catch (error) {
        debugPrint('ShellX: agent check failed: ${error.runtimeType}');
      }
```

with:

```dart
      try {
        final r = await source(agent);
        if (!ref.mounted) return;
        failed.remove(agent.id);
        state = {...state, agent.id: r};
      } on Object catch (error) {
        debugPrint('ShellX: agent check failed: ${error.runtimeType}');
        if (!ref.mounted) return;
        failed.add(agent.id);
        state = {...state}..remove(agent.id);
      }
```

In `apps/desktop/lib/src/ui/settings/pages/agents_page.dart`, replace:

```dart
import '../../theme/shellx_desktop_theme.dart';
import '../settings_row.dart' show SettingsScope;
```

with:

```dart
import '../../ai/ai_agents_section.dart';
import '../../theme/shellx_desktop_theme.dart';
import '../settings_row.dart' show SettingsScope;
```

In `apps/desktop/lib/src/ui/settings/pages/agents_page.dart`, replace:

```dart
        _PrStatusRow(),
        const _AgentCommandRow(),
      ],
```

with:

```dart
        _PrStatusRow(),
        const _AgentCommandRow(),
        // V2-1 D7: the AI interface's agents (last, so the rows above keep
        // their place).
        const AiAgentsSection(),
      ],
```

- [ ] **Step 4: Run the whole suite**

Settings › Agents is A12's page too: run everything.

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/ai lib/src/ui/ai lib/src/ui/settings/pages/agents_page.dart test/ui/ai
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `All other tests passed!` (3 224 passing, 10 skipped on the scratch copy); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/ui/ai/ai_agents_section.dart apps/desktop/lib/src/ai/ai_agents.dart apps/desktop/lib/src/ui/settings/pages/agents_page.dart apps/desktop/test/ui/ai/ai_agents_settings_test.dart
git commit -m "feat(v2-ai): Settings › Agents — AI agents' state, install and sign-in in the run sheet, default, custom agents, restore points

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 25: The Files tab and the read-only viewer; ShellX's `.gitignore` reading (D17, D18, B12) [needs V2-1a Task 9]

Spec §4.4 (Files), §4.2 (`read` cards, "View whole file"), D17, D18; ruling B12.

**`.gitignore` (B12):** ShellX reads the project's `.gitignore` files itself and never runs git on the project. It covers comments, `!`, a trailing `/`, anchoring, `*`, `?`, `[...]` and `**`; a deeper file wins, and an ignored folder's contents are ignored.

**The walks:** both run off the UI isolate (`aiOffThreadProvider`), behind the `AiProjectFiles` seam that Task 20 began.
- `aiListDir` gives one folder of the tree: folders first, `.git` hidden, each entry marked ignored or not.
- `aiIndexProject` gives every kept file, for `@` (Task 27). It never enters an ignored folder or `.git`, never follows a link, and stops at 20 000 files.

**The Files tab:**
- The session folder as a tree, loaded a folder at a time.
- Files changed in the session carry M or A; ignored entries are dimmed "ignored".
- It reloads when a turn ends and when its tab comes back to the front (D18: never continuously); so does the Changes tab.

**The viewer:** a file opens over the conversation, read-only: `re_editor` with line numbers, coloured by `re_highlight` for about 25 languages, at a line when one is given.
- "Mention in chat" puts `@path ` in the composer; "Open in editor" uses `link-editor`; Esc or × closes it.
- Binary, over-1-MiB and missing files say so.

**From the tool cards:** a `read` card opens its file at `locations[0].line`, and edit cards gain "View whole file".

**Files:**
- Create: `apps/desktop/lib/src/ai/ai_gitignore.dart`, `apps/desktop/lib/src/ui/ai/ai_files_panel.dart`, `apps/desktop/lib/src/ui/ai/ai_file_viewer.dart`
- Modify: `apps/desktop/lib/src/ai/ai_project_files.dart`, `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, `apps/desktop/lib/src/ui/ai/ai_tool_card.dart`, `apps/desktop/test/support/fake_project.dart`
- Test: `apps/desktop/test/ai/ai_gitignore_test.dart`, `apps/desktop/test/ui/ai/ai_files_test.dart`

**Interfaces:**
- Consumes: Task 20 `AiProjectFiles`, `AiSidePanel(files:)`, `aiTurnsOf`, `FakeProject`; Task 10 `aiOffThreadProvider` (`OffThread`); Task 13 `AiToolCard`; Task 15 `AiPaneUi.insert` (the composer inserts it); D17 `re_editor` 0.10.0 (`CodeEditor`, `CodeLineEditingController`, `CodeLineSelection`, `DefaultCodeLineNumber`) and `re_highlight` 0.0.3; V2-1a `AiRuntime.sessionChanges()`, `ToolLocation`.
- Produces: `AiGitIgnore` (`add(base, text)`, `ignores(path, {dir})`), `AiDirEntry`, `aiListDir((root, dir))`, `aiIndexProject(root)`, `kAiIndexMax`; `AiProjectFiles.list/index`, `DiskProjectFiles(OffThread)`; `AiFilesPanel`; `AiFileViewer({path, line})`, `aiLanguageOf(path)`; keys `ai.panel.files`, `ai.file.<path>`, `ai.viewer`, `ai.viewer.code|mention|close|note`, `ai.tool.view`; string `aiFileMissing` (Task 2's list).

- [ ] **Step 1: Write the failing tests**

`apps/desktop/test/ai/ai_gitignore_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shellx_desktop/src/ai/ai_gitignore.dart';

/// V2-1 B12: ShellX's own `.gitignore` reading, and the folder walks.
void main() {
  group('AiGitIgnore', () {
    AiGitIgnore rules(String text) => AiGitIgnore()..add('', text);

    test('names match at any depth; a trailing / is folders only', () {
      final r = rules('*.log\nbuild/\n# a comment\n\n');
      expect(r.ignores('a.log', dir: false), isTrue);
      expect(r.ignores('src/deep/a.log', dir: false), isTrue);
      expect(r.ignores('build', dir: true), isTrue);
      expect(r.ignores('app/build', dir: true), isTrue);
      expect(r.ignores('build', dir: false), isFalse);
      expect(r.ignores('a.txt', dir: false), isFalse);
    });

    test('a slash anchors to the file\'s folder; ** spans folders', () {
      final r = rules('/root.txt\ndocs/*.md\n**/gen\nsecret/**\n');
      expect(r.ignores('root.txt', dir: false), isTrue);
      expect(r.ignores('sub/root.txt', dir: false), isFalse);
      expect(r.ignores('docs/a.md', dir: false), isTrue);
      expect(r.ignores('docs/x/a.md', dir: false), isFalse);
      expect(r.ignores('gen', dir: true), isTrue);
      expect(r.ignores('a/b/gen', dir: true), isTrue);
      expect(r.ignores('secret/x/y.txt', dir: false), isTrue);
    });

    test('! takes a file back; the last matching line wins; classes', () {
      final r = rules('*.log\n!keep.log\n[ab].txt\n');
      expect(r.ignores('x.log', dir: false), isTrue);
      expect(r.ignores('keep.log', dir: false), isFalse);
      expect(r.ignores('a.txt', dir: false), isTrue);
      expect(r.ignores('c.txt', dir: false), isFalse);
    });

    test('a deeper .gitignore wins over the root one', () {
      final r = AiGitIgnore()
        ..add('', '*.tmp\n')
        ..add('pkg', '!*.tmp\n');
      expect(r.ignores('a.tmp', dir: false), isTrue);
      expect(r.ignores('pkg/a.tmp', dir: false), isFalse);
    });
  });

  group('walks', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('ai_walk');
      void file(String rel, [String text = 'x']) => File(p.join(root.path, rel))
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
      file('.gitignore', 'build/\n*.log\n');
      file('.git/HEAD', 'ref');
      file('b.txt');
      file('a.log');
      file('src/main.dart');
      file('build/out.js');
      file('build/inner/deep.js');
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('a folder: folders first, .git hidden, ignored marked', () {
      final top = aiListDir((root.path, ''));
      expect(
        [for (final e in top) e.path],
        ['build', 'src', '.gitignore', 'a.log', 'b.txt'],
      );
      expect(
        [for (final e in top) e.ignored],
        [true, false, false, true, false],
      );
      final inner = aiListDir((root.path, 'build'));
      expect(inner.every((e) => e.ignored), isTrue, reason: 'under build/');
    });

    test('the index keeps what .gitignore keeps and never enters .git', () {
      expect(aiIndexProject(root.path), [
        '.gitignore',
        'b.txt',
        'src/main.dart',
      ]);
    });
  });
}
```

`apps/desktop/test/ui/ai/ai_files_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ai/ai_project_files.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/window_focus.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_tabs.dart';
import '../../support/config_workspace.dart';
import '../../support/fake_project.dart';

/// V2-1 D18, §4.4 (Files), §4.2 (`read` cards): the tree and the viewer.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<(ProviderContainer, FakeProject)> pane(
    WidgetTester t, {
    List<List<Map<String, Object?>>> turns = const [],
  }) async {
    final files = FakeProject(testAiCwd, {
      '.gitignore': 'dist/\n',
      'lib/a.dart': 'one\ntwo\nthree\n',
      'README.md': '# Hi\n',
      'dist/app.js': 'x\n',
    });
    files.onSnapshot = (ref) {
      if (ref.endsWith('/1')) files.files['lib/new.dart'] = 'n\n';
    };
    final fakes = FakeAiRuntimes(
      FakeScenario(turns: turns),
      checkpoints: files,
    );
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: [
        ...fakes.overrides,
        aiProjectFilesProvider.overrideWithValue(files),
      ],
    );
    final c = w.container;
    openTestAiTab(c, cwd: testAiCwd);
    c.read(terminalFocusRequestProvider.notifier).request();
    await t.pumpAndSettle();
    return (c, files);
  }

  Future<void> files(WidgetTester t) async {
    await t.tap(find.byKey(const Key('ai.panel')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ai.panel.files')));
    await t.pumpAndSettle();
  }

  testWidgets('the tree: folders first, ignored dimmed, M/A after a turn; a '
      'folder opens in place', (t) async {
    final (c, _) = await pane(
      t,
      turns: [
        [FakeSteps.text('ok')],
      ],
    );
    await t.enterText(find.byKey(const Key('ai.composer')), 'go');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    await files(t);
    for (final path in ['dist', 'lib', '.gitignore', 'README.md']) {
      expect(find.byKey(ValueKey('ai.file.$path')), findsOneWidget);
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ai.file.dist')),
        matching: find.text('ignored'),
      ),
      findsOneWidget,
    );
    await t.tap(find.byKey(const ValueKey('ai.file.lib')));
    await t.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ai.file.lib/new.dart')),
        matching: find.text('A'),
      ),
      findsOneWidget,
    );
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('the tree looks again when its tab comes back to the front '
      '(D18)', (t) async {
    final (c, project) = await pane(t);
    await files(t);
    project.files['NEW.md'] = 'n\n';
    final tabs = c.read(terminalTabsProvider.notifier);
    final ai = c.read(terminalTabsProvider).selectedId!;
    tabs.select(c.read(terminalTabsProvider).tabs.first.id);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai.file.NEW.md')), findsNothing);
    tabs.select(ai);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai.file.NEW.md')), findsOneWidget);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a file opens read-only; "Mention in chat" puts @path in the '
      'composer', (t) async {
    final (c, _) = await pane(t);
    await files(t);
    await t.tap(find.byKey(const ValueKey('ai.file.README.md')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    final code = t.widget<CodeEditor>(find.byKey(const Key('ai.viewer.code')));
    expect(code.controller!.text, '# Hi\n');
    expect(code.readOnly, isTrue);
    expect(find.text('read-only'), findsOneWidget);
    await t.tap(find.byKey(const Key('ai.viewer.mention')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.viewer')), findsNothing);
    expect(
      t
          .widget<TextField>(find.byKey(const Key('ai.composer')))
          .controller!
          .text,
      '@README.md ',
    );
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('a read card opens the file at its line', (t) async {
    final (c, _) = await pane(
      t,
      turns: [
        [
          FakeSteps.tool(
            't1',
            'Read a.dart',
            kind: 'read',
            status: 'completed',
            locations: [
              {'path': '$testAiCwd/lib/a.dart', 'line': 2},
            ],
          ),
        ],
      ],
    );
    await t.enterText(find.byKey(const Key('ai.composer')), 'read');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    await t.tap(find.text('lib/a.dart'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    final code = t.widget<CodeEditor>(find.byKey(const Key('ai.viewer.code')));
    expect(code.controller!.selection.baseIndex, 1);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ai.viewer')), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);
}
```

`FakeProject` lists and indexes its map the way the disk version does:

In `apps/desktop/test/support/fake_project.dart`, replace:

```dart
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_desktop/src/ai/ai_project_files.dart';
```

with:

```dart
import 'package:shellx_ai/shellx_ai.dart';
import 'package:shellx_desktop/src/ai/ai_gitignore.dart';
import 'package:shellx_desktop/src/ai/ai_project_files.dart';
```

In `apps/desktop/test/support/fake_project.dart`, replace:

```dart
  @override
  Future<AiFileContent> read(String path) async {
    final text = files[p.relative(path, from: root)];
    return text == null ? const AiFileMissing() : AiFileText(text);
  }
}
```

with:

```dart
  @override
  Future<AiFileContent> read(String path) async {
    final text = files[p.relative(path, from: root)];
    return text == null ? const AiFileMissing() : AiFileText(text);
  }

  /// The project's `.gitignore` files, as the disk version reads them.
  AiGitIgnore _rules() {
    final rules = AiGitIgnore();
    for (final MapEntry(:key, :value) in files.entries) {
      if (key == '.gitignore') rules.add('', value);
      if (key.endsWith('/.gitignore')) {
        rules.add(key.substring(0, key.length - '/.gitignore'.length), value);
      }
    }
    return rules;
  }

  bool _inIgnoredFolder(AiGitIgnore rules, String path) {
    final parts = path.split('/');
    for (var i = 1; i < parts.length; i++) {
      if (rules.ignores(parts.take(i).join('/'), dir: true)) return true;
    }
    return false;
  }

  @override
  Future<List<AiDirEntry>> list(String root, String dir) async {
    final rules = _rules();
    final prefix = dir.isEmpty ? '' : '$dir/';
    final dirs = <String>{};
    final names = <String>{};
    for (final path in files.keys) {
      if (!path.startsWith(prefix)) continue;
      final rest = path.substring(prefix.length);
      final slash = rest.indexOf('/');
      slash < 0 ? names.add(rest) : dirs.add(rest.substring(0, slash));
    }
    AiDirEntry entry(String name, {required bool dir}) {
      final rel = '$prefix$name';
      return AiDirEntry(
        rel,
        dir: dir,
        ignored: _inIgnoredFolder(rules, rel) || rules.ignores(rel, dir: dir),
      );
    }

    return [
      for (final d in dirs.toList()..sort()) entry(d, dir: true),
      for (final n in names.toList()..sort()) entry(n, dir: false),
    ];
  }

  @override
  Future<List<String>> index(String root) async {
    final rules = _rules();
    return [
      for (final path in files.keys.toList()..sort())
        if (!_inIgnoredFolder(rules, path) && !rules.ignores(path, dir: false))
          path,
    ];
  }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ai/ai_gitignore_test.dart`
Expected: the test does not compile, `Error when reading 'lib/src/ai/ai_gitignore.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/ai/ai_gitignore.dart`:

```dart
import 'dart:io';

import 'package:path/path.dart' as p;

/// One line of a `.gitignore`, compiled (ruling B12).
final class _Rule {
  const _Rule(this.re, {required this.negate, required this.dirOnly});
  final RegExp re;
  final bool negate;
  final bool dirOnly;
}

/// B12: ShellX's own reading of a project's `.gitignore` files, for `@` and
/// the Files panel. It never runs git, and never touches the project's own
/// `.git`. It covers `#` comments, `!` re-inclusion, a trailing `/` (folders
/// only), anchoring by a `/`, `*`, `?`, `[...]` and `**`; a deeper
/// `.gitignore` wins over a shallower one, and the last matching line of a
/// file wins. Global excludes and `.git/info/exclude` are not read.
final class AiGitIgnore {
  final _sets = <(String, List<_Rule>)>[];

  /// The `.gitignore` of folder [base] ('' is the project root), relative to
  /// the root with `/` separators.
  void add(String base, String text) {
    final rules = <_Rule>[];
    for (var line in text.split('\n')) {
      line = line.replaceAll('\r', '');
      if (line.isEmpty || line.startsWith('#')) continue;
      // Trailing spaces go unless escaped.
      while (line.endsWith(' ') && !line.endsWith(r'\ ')) {
        line = line.substring(0, line.length - 1);
      }
      if (line.isEmpty) continue;
      var negate = false;
      if (line.startsWith('!')) {
        negate = true;
        line = line.substring(1);
      } else if (line.startsWith(r'\!') || line.startsWith(r'\#')) {
        line = line.substring(1);
      }
      var dirOnly = false;
      if (line.endsWith('/')) {
        dirOnly = true;
        line = line.substring(0, line.length - 1);
      }
      if (line.isEmpty) continue;
      final re = _compile(line);
      if (re != null) rules.add(_Rule(re, negate: negate, dirOnly: dirOnly));
    }
    if (rules.isNotEmpty) _sets.add((base, rules));
  }

  /// Whether [path] (relative to the root, `/` separators) is ignored by the
  /// rules added so far. A folder above an ignored folder is the caller's
  /// to check: git never looks inside an ignored folder.
  bool ignores(String path, {required bool dir}) {
    bool? result;
    for (final (base, rules) in _sets) {
      final String rel;
      if (base.isEmpty) {
        rel = path;
      } else if (path.startsWith('$base/')) {
        rel = path.substring(base.length + 1);
      } else {
        continue;
      }
      for (final r in rules) {
        if (r.dirOnly && !dir) continue;
        if (r.re.hasMatch(rel)) result = !r.negate;
      }
    }
    return result ?? false;
  }

  static RegExp? _compile(String pattern) {
    var pat = pattern;
    final anchored = pat.contains('/');
    if (pat.startsWith('/')) pat = pat.substring(1);
    final b = StringBuffer('^');
    if (!anchored) b.write('(?:.*/)?');
    for (var i = 0; i < pat.length; i++) {
      final c = pat[i];
      if (c == '*') {
        final twin = i + 1 < pat.length && pat[i + 1] == '*';
        final atStart = i == 0 || pat[i - 1] == '/';
        final atEnd = i + 2 >= pat.length || pat[i + 2] == '/';
        if (twin && atStart && atEnd) {
          if (i + 2 >= pat.length) {
            b.write('.*');
            i += 1;
          } else {
            b.write('(?:.*/)?');
            i += 2;
          }
        } else {
          b.write('[^/]*');
          if (twin) i += 1;
        }
      } else if (c == '?') {
        b.write('[^/]');
      } else if (c == '[') {
        final close = pat.indexOf(']', i + 2);
        if (close < 0) {
          b.write(r'\[');
          continue;
        }
        var body = pat.substring(i + 1, close);
        if (body.startsWith('!')) body = '^${body.substring(1)}';
        b.write('[${body.replaceAll(r'\', r'\\')}]');
        i = close;
      } else if (c == r'\' && i + 1 < pat.length) {
        b.write(RegExp.escape(pat[i + 1]));
        i += 1;
      } else {
        b.write(RegExp.escape(c));
      }
    }
    b.write(r'$');
    try {
      return RegExp(b.toString());
    } on FormatException {
      return null;
    }
  }
}

/// One entry of a project folder (§4.4 Files).
final class AiDirEntry {
  const AiDirEntry(this.path, {required this.dir, required this.ignored});

  /// Relative to the project root, `/` separators.
  final String path;
  final bool dir;

  /// `.gitignore` drops it (or a folder above it).
  final bool ignored;

  String get name => path.substring(path.lastIndexOf('/') + 1);

  @override
  String toString() => '…';
}

/// The most files `@` indexes in one project (D16).
const int kAiIndexMax = 20000;

String _rel(String root, String path) =>
    p.relative(path, from: root).replaceAll(r'\', '/');

void _addIgnore(AiGitIgnore rules, String root, String dirAbs) {
  final file = File(p.join(dirAbs, '.gitignore'));
  try {
    if (file.existsSync()) {
      final base = dirAbs == root ? '' : _rel(root, dirAbs);
      rules.add(base, file.readAsStringSync());
    }
  } on FileSystemException {
    // Unreadable: nothing ignored by it.
  }
}

/// D18, B12: folder [args.$2] of project [args.$1] ('' is the root) — folders
/// first, then files, each by name; never `.git`; each marked ignored when a
/// `.gitignore` says so or a folder above it is ignored. Blocking: run it
/// off the UI isolate (`aiOffThreadProvider`).
List<AiDirEntry> aiListDir((String, String) args) {
  final (root, dir) = args;
  final rules = AiGitIgnore();
  _addIgnore(rules, root, root);
  var above = false;
  if (dir.isNotEmpty) {
    final parts = dir.split('/');
    for (var i = 0; i < parts.length; i++) {
      final rel = parts.take(i + 1).join('/');
      if (rules.ignores(rel, dir: true)) above = true;
      _addIgnore(rules, root, p.join(root, rel));
    }
  }
  final folder = Directory(dir.isEmpty ? root : p.join(root, dir));
  final dirs = <AiDirEntry>[];
  final files = <AiDirEntry>[];
  try {
    for (final e in folder.listSync(followLinks: false)) {
      final name = p.basename(e.path);
      if (name == '.git') continue;
      final rel = dir.isEmpty ? name : '$dir/$name';
      final isDir = e is Directory;
      final entry = AiDirEntry(
        rel,
        dir: isDir,
        ignored: above || rules.ignores(rel, dir: isDir),
      );
      (isDir ? dirs : files).add(entry);
    }
  } on FileSystemException {
    return const [];
  }
  int byName(AiDirEntry a, AiDirEntry b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  return [...dirs..sort(byName), ...files..sort(byName)];
}

/// D16, B12: every file of project [root] that the `.gitignore` files keep
/// (relative, `/` separators, sorted), at most [kAiIndexMax]; ignored
/// folders and `.git` are never entered, links never followed. Blocking: run
/// it off the UI isolate.
List<String> aiIndexProject(String root) {
  final rules = AiGitIgnore();
  final out = <String>[];
  final queue = <String>[''];
  while (queue.isNotEmpty && out.length < kAiIndexMax) {
    final dir = queue.removeAt(0);
    final abs = dir.isEmpty ? root : p.join(root, dir);
    _addIgnore(rules, root, abs);
    final List<FileSystemEntity> list;
    try {
      list = Directory(abs).listSync(followLinks: false);
    } on FileSystemException {
      continue;
    }
    for (final e in list) {
      final name = p.basename(e.path);
      if (name == '.git') continue;
      final rel = dir.isEmpty ? name : '$dir/$name';
      if (e is Directory) {
        if (!rules.ignores(rel, dir: true)) queue.add(rel);
      } else if (e is File && !rules.ignores(rel, dir: false)) {
        out.add(rel);
        if (out.length >= kAiIndexMax) break;
      }
    }
  }
  return out..sort();
}
```

`apps/desktop/lib/src/ui/ai/ai_files_panel.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../../l10n/app_localizations.dart';
import '../../ai/ai_gitignore.dart';
import '../../ai/ai_project_files.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_changes_panel.dart' show aiTurnsOf, AiTurns;
import 'ai_file_viewer.dart';
import 'ai_scope.dart';

/// D18, §4.4: the Files tab — the session folder as a tree, folders before
/// files, `.git` hidden, loaded a folder at a time (off the UI isolate).
/// Files the session changed carry M or A; what `.gitignore` drops is
/// dimmed "ignored" (B12). A file opens in the viewer. It reloads when a
/// turn ends and when its tab comes back to the front (D18; never
/// continuously).
class AiFilesPanel extends ConsumerStatefulWidget {
  const AiFilesPanel({super.key});

  @override
  ConsumerState<AiFilesPanel> createState() => _AiFilesPanelState();
}

typedef _Row = ({AiDirEntry entry, int depth});

class _AiFilesPanelState extends ConsumerState<AiFilesPanel> {
  AiPaneScope? _pane;
  AiTurns? _turns;
  final _open = <String>{};
  final _children = <String, List<AiDirEntry>>{};
  Map<String, ChangeKind> _changed = const {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pane = AiPaneScope.of(context);
    if (!identical(pane.frames, _pane?.frames)) {
      _pane?.frames.removeListener(_onFrame);
      _pane?.ui.changes.removeListener(_onChanges);
      pane.frames.addListener(_onFrame);
      pane.ui.changes.addListener(_onChanges);
      _pane = pane;
      _turns = aiTurnsOf(pane.state);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_reload());
      });
    }
    _pane = pane;
  }

  @override
  void dispose() {
    _pane?.frames.removeListener(_onFrame);
    _pane?.ui.changes.removeListener(_onChanges);
    super.dispose();
  }

  void _onChanges() => unawaited(_reload());

  void _onFrame() {
    final next = aiTurnsOf(_pane!.state);
    final ended = next.lastFinished != _turns?.lastFinished;
    _turns = next;
    if (ended) unawaited(_reload());
  }

  Future<void> _reload() async {
    await Future.wait([
      for (final dir in ['', ..._open]) _load(dir),
    ]);
    final changes = await _pane!.runtime.sessionChanges();
    if (!mounted) return;
    setState(() {
      _changed = {
        for (final c in changes ?? const <FileChange>[]) c.path: c.kind,
      };
    });
  }

  Future<void> _load(String dir) async {
    final entries = await ref
        .read(aiProjectFilesProvider)
        .list(_pane!.state.cwd, dir);
    if (mounted) setState(() => _children[dir] = entries);
  }

  void _toggle(AiDirEntry folder) {
    final path = folder.path;
    if (_open.remove(path)) {
      setState(() {});
      return;
    }
    setState(() => _open.add(path));
    if (!_children.containsKey(path)) unawaited(_load(path));
  }

  List<_Row> _rows() {
    final out = <_Row>[];
    void walk(String dir, int depth) {
      for (final e in _children[dir] ?? const <AiDirEntry>[]) {
        out.add((entry: e, depth: depth));
        if (e.dir && _open.contains(e.path)) walk(e.path, depth + 1);
      }
    }

    walk('', 0);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = _rows();
    final dim = ShellxText.caption.copyWith(
      color: ShellxDesktopColors.textSecondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(ShellxSpace.s8),
          child: Text(l10n.aiFilesNote, style: dim),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemExtent: 24,
            itemBuilder: (context, i) {
              final (:entry, :depth) = rows[i];
              final mark = switch (_changed[entry.path]) {
                ChangeKind.modified => 'M',
                ChangeKind.added => 'A',
                _ => null,
              };
              return InkWell(
                key: ValueKey('ai.file.${entry.path}'),
                onTap: entry.dir
                    ? () => _toggle(entry)
                    : () => _pane!.ui.showOverlay(
                        AiFileViewer(
                          key: ValueKey('ai.viewer.${entry.path}'),
                          path: entry.path,
                        ),
                      ),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: ShellxSpace.s8 + depth * 12.0,
                    right: ShellxSpace.s8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        entry.dir
                            ? (_open.contains(entry.path)
                                  ? Icons.expand_more
                                  : Icons.chevron_right)
                            : Icons.description_outlined,
                        size: 14,
                        color: ShellxDesktopColors.textSecondary,
                      ),
                      const SizedBox(width: ShellxSpace.s4),
                      Expanded(
                        child: Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ShellxText.small.copyWith(
                            color: entry.ignored
                                ? ShellxDesktopColors.textSecondary
                                : ShellxDesktopColors.textPrimary,
                          ),
                        ),
                      ),
                      if (mark != null)
                        Text(
                          mark,
                          style: ShellxText.caption.copyWith(
                            color: mark == 'A'
                                ? ShellxDesktopColors.ok
                                : ShellxDesktopColors.warn,
                          ),
                        )
                      else if (entry.ignored)
                        Text(l10n.aiIgnored, style: dim),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
```

`apps/desktop/lib/src/ui/ai/ai_file_viewer.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/dockerfile.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/scss.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart' show Mode;
import 'package:re_highlight/styles/atom-one-dark.dart';

import '../../../l10n/app_localizations.dart';
import '../../ai/ai_project_files.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_editor.dart';
import 'ai_scope.dart';
import 'ai_theme.dart';

/// D17: how a file is coloured, by its name; null: plain text.
Mode? aiLanguageOf(String path) {
  final name = p.basename(path).toLowerCase();
  if (name == 'dockerfile') return langDockerfile;
  return switch (p.extension(name)) {
    '.dart' => langDart,
    '.js' || '.mjs' || '.cjs' || '.jsx' => langJavascript,
    '.ts' || '.tsx' => langTypescript,
    '.json' => langJson,
    '.yaml' || '.yml' => langYaml,
    '.py' => langPython,
    '.go' => langGo,
    '.rs' => langRust,
    '.java' => langJava,
    '.kt' || '.kts' => langKotlin,
    '.swift' => langSwift,
    '.c' || '.h' => langC,
    '.cc' || '.cpp' || '.hpp' || '.mm' => langCpp,
    '.cs' => langCsharp,
    '.rb' => langRuby,
    '.php' => langPhp,
    '.sh' || '.bash' || '.zsh' => langBash,
    '.md' => langMarkdown,
    '.html' || '.xml' || '.svg' => langXml,
    '.css' => langCss,
    '.scss' => langScss,
    '.sql' => langSql,
    '.toml' || '.ini' || '.cfg' => langIni,
    _ => null,
  };
}

/// §4.4 (Files), §4.2 (`read` cards, "View whole file"): a file of the
/// session folder over the conversation, read-only (D17 `re_editor`), at
/// [line] when given. "Mention in chat" puts `@path` in the composer;
/// "Open in editor" uses `link-editor`. Binary and over-1-MiB files say so.
/// Esc or × closes it.
class AiFileViewer extends ConsumerStatefulWidget {
  const AiFileViewer({super.key, required this.path, this.line});

  /// Relative to the session folder.
  final String path;

  /// 1-based (ACP `locations[].line`).
  final int? line;

  @override
  ConsumerState<AiFileViewer> createState() => _AiFileViewerState();
}

class _AiFileViewerState extends ConsumerState<AiFileViewer> {
  CodeLineEditingController? _code;
  AiFileContent? _content;
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_load(AiPaneScope.of(context).state.cwd));
  }

  @override
  void dispose() {
    _code?.dispose();
    super.dispose();
  }

  Future<void> _load(String cwd) async {
    final content = await ref
        .read(aiProjectFilesProvider)
        .read(p.join(cwd, widget.path));
    if (!mounted) return;
    setState(() {
      _content = content;
      if (content is AiFileText) {
        _code = CodeLineEditingController.fromText(content.text);
      }
    });
    final code = _code;
    final line = widget.line;
    if (code == null || line == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = (line - 1).clamp(0, code.codeLines.length - 1);
      code.selection = CodeLineSelection.collapsed(index: index, offset: 0);
      code.makeCursorCenterIfInvisible();
    });
  }

  void _mention() {
    final ui = AiPaneScope.of(context).ui;
    ui.insert.value = '@${widget.path} ';
    ui.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pane = AiPaneScope.of(context);
    final content = _content;
    final code = _code;
    final language = aiLanguageOf(widget.path);
    final Widget body = switch (content) {
      null => const SizedBox.shrink(),
      AiFileBinary() => _Note(l10n.aiBinaryFile),
      AiFileTooLarge() => _Note(l10n.aiFileTooLarge),
      AiFileMissing() => _Note(l10n.aiFileMissing),
      AiFileText() => CodeEditor(
        key: const Key('ai.viewer.code'),
        controller: code,
        readOnly: true,
        autofocus: false,
        showCursorWhenReadOnly: false,
        wordWrap: false,
        style: CodeEditorStyle(
          fontFamily: kAiMono.fontFamily,
          fontSize: kAiMono.fontSize,
          backgroundColor: ShellxDesktopColors.surfaceInset,
          textColor: ShellxDesktopColors.textPrimary,
          codeTheme: CodeHighlightTheme(
            languages: {
              if (language != null)
                'code': CodeHighlightThemeMode(mode: language),
            },
            theme: atomOneDarkTheme,
          ),
        ),
        indicatorBuilder:
            (context, editingController, chunkController, notifier) =>
                DefaultCodeLineNumber(
                  controller: editingController,
                  notifier: notifier,
                ),
      ),
    };
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): pane.ui.closeOverlay,
      },
      child: Focus(
        autofocus: true,
        child: Container(
          key: const Key('ai.viewer'),
          margin: const EdgeInsets.all(ShellxSpace.s16),
          padding: const EdgeInsets.all(ShellxSpace.s12),
          decoration: BoxDecoration(
            color: ShellxDesktopColors.surface,
            borderRadius: BorderRadius.circular(ShellxRadius.r8),
            border: Border.all(color: ShellxDesktopColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ShellxText.bodyStrong.copyWith(
                            color: ShellxDesktopColors.textPrimary,
                          ),
                        ),
                        Text(
                          l10n.aiReadOnly,
                          style: ShellxText.caption.copyWith(
                            color: ShellxDesktopColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('ai.viewer.mention'),
                    tooltip: l10n.aiMentionInChat,
                    iconSize: 16,
                    onPressed: _mention,
                    icon: const Icon(Icons.alternate_email),
                  ),
                  IconButton(
                    tooltip: l10n.aiOpenInEditor,
                    iconSize: 16,
                    onPressed: () => unawaited(
                      aiOpenInEditor(ref, widget.path, pane.state.cwd),
                    ),
                    icon: const Icon(Icons.open_in_new),
                  ),
                  IconButton(
                    key: const Key('ai.viewer.close'),
                    tooltip: l10n.actionClose,
                    iconSize: 16,
                    onPressed: pane.ui.closeOverlay,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: ShellxSpace.s8),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    key: const Key('ai.viewer.note'),
    style: ShellxText.body.copyWith(color: ShellxDesktopColors.textSecondary),
  );
}
```

In `apps/desktop/lib/src/ai/ai_project_files.dart`, replace:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
```

with:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_gitignore.dart';
import 'ai_off_thread.dart';
```

In `apps/desktop/lib/src/ai/ai_project_files.dart`, replace:

```dart
/// The project's files as the AI pane reads them (the diff of a change, the
/// viewer). A seam: widget tests never touch the disk under fake async.
abstract interface class AiProjectFiles {
  /// The file at [path] (absolute).
  Future<AiFileContent> read(String path);
}

final class DiskProjectFiles implements AiProjectFiles {
  const DiskProjectFiles();
```

with:

```dart
/// The project's files as the AI pane reads them (the diff of a change, the
/// viewer, the Files tree, `@`). A seam: widget tests never touch the disk
/// under fake async.
abstract interface class AiProjectFiles {
  /// The file at [path] (absolute).
  Future<AiFileContent> read(String path);

  /// D18: folder [dir] of project [root] ('' is the root), as [aiListDir].
  Future<List<AiDirEntry>> list(String root, String dir);

  /// D16: the files `@` offers, as [aiIndexProject].
  Future<List<String>> index(String root);
}

/// The disk; listings and the index run off the UI isolate.
final class DiskProjectFiles implements AiProjectFiles {
  const DiskProjectFiles(this._run);
  final OffThread _run;

  @override
  Future<List<AiDirEntry>> list(String root, String dir) =>
      _run(aiListDir, (root, dir));

  @override
  Future<List<String>> index(String root) => _run(aiIndexProject, root);
```

In `apps/desktop/lib/src/ai/ai_project_files.dart`, replace:

```dart
final aiProjectFilesProvider = Provider<AiProjectFiles>(
  (ref) => const DiskProjectFiles(),
);
```

with:

```dart
final aiProjectFilesProvider = Provider<AiProjectFiles>(
  (ref) => DiskProjectFiles(ref.read(aiOffThreadProvider)),
);
```

In `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, replace:

```dart
    _frames?.active = widget.selected;
    if (old.selected != widget.selected || old.pane.cwd != widget.pane.cwd) {
```

with:

```dart
    _frames?.active = widget.selected;
    // D18: the panels look again when the tab comes back to the front.
    if (widget.selected && !old.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ui.changesChanged();
      });
    }
    if (old.selected != widget.selected || old.pane.cwd != widget.pane.cwd) {
```

In `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, replace:

```dart
import 'ai_dock.dart';
import 'ai_folder_card.dart';
```

with:

```dart
import 'ai_dock.dart';
import 'ai_files_panel.dart';
import 'ai_folder_card.dart';
```

In `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, replace:

```dart
              builder: (context, _) =>
                  _ui.panelOpen ? const AiSidePanel() : const SizedBox.shrink(),
```

with:

```dart
              builder: (context, _) => _ui.panelOpen
                  ? const AiSidePanel(files: AiFilesPanel())
                  : const SizedBox.shrink(),
```

In `apps/desktop/lib/src/ui/ai/ai_tool_card.dart`, replace:

```dart
import 'ai_editor.dart';
import 'ai_labels.dart';
```

with:

```dart
import 'ai_editor.dart';
import 'ai_file_viewer.dart';
import 'ai_labels.dart';
```

In `apps/desktop/lib/src/ui/ai/ai_tool_card.dart`, replace:

```dart
    final asking = item.awaitingPermission;
    final header = InkWell(
      onTap: _expandable ? () => setState(() => _open = !_isOpen) : null,
```

with:

```dart
    final asking = item.awaitingPermission;
    // §4.2: a `read` card opens the file at its line.
    final at = item.fields.kind == ToolKind.read
        ? item.fields.locations?.firstOrNull
        : null;
    final header = InkWell(
      onTap: _expandable
          ? () => setState(() => _open = !_isOpen)
          : at == null
          ? null
          : () => _view(at.path, at.line),
```

In `apps/desktop/lib/src/ui/ai/ai_tool_card.dart`, replace:

```dart
      parts.add(
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('ai.tool.editor'),
            onPressed: () => unawaited(aiOpenInEditor(ref, d.path, cwd)),
            icon: const Icon(Icons.open_in_new, size: 14),
            label: Text(l10n.aiOpenInEditor),
          ),
        ),
      );
```

with:

```dart
      parts.add(
        Wrap(
          spacing: ShellxSpace.s8,
          children: [
            TextButton.icon(
              key: const Key('ai.tool.view'),
              onPressed: () => _view(d.path, null),
              icon: const Icon(Icons.article_outlined, size: 14),
              label: Text(l10n.aiViewFile),
            ),
            TextButton.icon(
              key: const Key('ai.tool.editor'),
              onPressed: () => unawaited(aiOpenInEditor(ref, d.path, cwd)),
              icon: const Icon(Icons.open_in_new, size: 14),
              label: Text(l10n.aiOpenInEditor),
            ),
          ],
        ),
      );
```

In `apps/desktop/lib/src/ui/ai/ai_tool_card.dart`, replace:

```dart
  void _ensureDiff() {
```

with:

```dart
  /// The viewer over the conversation (§4.2 "View whole file", `read`).
  void _view(String path, int? line) {
    final scope = AiPaneScope.of(context);
    scope.ui.showOverlay(
      AiFileViewer(
        key: UniqueKey(),
        path: aiRelativePath(path, scope.state.cwd),
        line: line,
      ),
    );
  }

  void _ensureDiff() {
```

- [ ] **Step 4: Run the tests**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/ai lib/src/ui/ai test/ui/ai test/ai test/support/fake_project.dart
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai test/ai test/ui/ai_tab_screens_test.dart test/l10n 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `All tests passed!` (120 on the scratch copy); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/ai/ai_gitignore.dart apps/desktop/lib/src/ai/ai_project_files.dart apps/desktop/lib/src/ui/ai/ai_files_panel.dart apps/desktop/lib/src/ui/ai/ai_file_viewer.dart apps/desktop/lib/src/ui/ai/ai_pane_view.dart apps/desktop/lib/src/ui/ai/ai_tool_card.dart apps/desktop/test/support/fake_project.dart apps/desktop/test/ai/ai_gitignore_test.dart apps/desktop/test/ui/ai/ai_files_test.dart
git commit -m "feat(v2-ai): Files tab and read-only viewer; ShellX's own .gitignore reading, walks off the UI isolate

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 26: Session history (D15) [needs V2-1a Task 9]

Spec D15, D14, §4.1 (the header's History).

**The button:** History shows in the header only for an agent that lists its sessions (`sessionCapabilities.list`). It asks `session/list {cwd}` and shows the sessions:
- each with its title ("Untitled session" without one) and when it was last updated, in local time;
- the current one marked "current session" and not offered;
- "No earlier sessions for this folder." when there is none.

**Choosing one:** it opens a new AI tab of the same agent and folder, titled like the session. That tab reopens it with `session/load` when shown (D14, Task 17's resume card).

**Files:**
- Create: `apps/desktop/lib/src/ui/ai/ai_history.dart`
- Modify: `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`
- Test: `apps/desktop/test/ui/ai/ai_history_test.dart`

**Interfaces:**
- Consumes: V2-1a `AiRuntime.listSessions({cursor}) → ListSessionsResult?` (`sessions`: `sessionId`, `title`, `updatedAt`), `AgentCapabilities.listSessions`; Task 3 `openAiTab`; Task 17 `AiHeader.onHistory`.
- Produces: `showAiHistory(context, runtime, {onOpen})`; `aiHistoryWhen(String?)`; keys `ai.history`, `ai.history.dialog`, `ai.history.<sessionId>`.

- [ ] **Step 1: Write the failing test**

`apps/desktop/test/ui/ai/ai_history_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/terminal/terminal_tabs.dart';
import 'package:shellx_desktop/src/ui/ai/ai_history.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_tabs.dart';
import '../../support/config_workspace.dart';

/// V2-1 D15: Session history.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<(ProviderContainer, FakeAiRuntimes)> pane(
    WidgetTester t,
    FakeScenario scenario,
  ) async {
    final fakes = FakeAiRuntimes(scenario);
    final w = await pumpConfiguredWorkspace(
      t,
      platform: TargetPlatform.macOS,
      extra: fakes.overrides,
    );
    openTestAiTab(w.container, cwd: testAiCwd);
    await t.pumpAndSettle();
    return (w.container, fakes);
  }

  testWidgets('History lists this folder\'s sessions (the current one '
      'marked); one opens in a new tab that reopens it', (t) async {
    final (c, fakes) = await pane(
      t,
      FakeScenario(
        sessions: [
          {
            'sessionId': 'sess-0',
            'cwd': testAiCwd,
            'title': 'Fix login',
            'updatedAt': '2026-10-13T09:30:00Z',
          },
          {'sessionId': 'sess-1', 'cwd': testAiCwd, 'title': 'Now'},
        ],
      ),
    );
    await t.tap(find.byKey(const Key('ai.history')));
    await t.pumpAndSettle();
    expect(fakes.agent().received, contains('session/list'));
    expect(find.text('Fix login'), findsOneWidget);
    expect(find.text(aiHistoryWhen('2026-10-13T09:30:00Z')), findsOneWidget);
    expect(find.text('current session'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ai.history.sess-0')));
    await t.pumpAndSettle();
    final tab = c.read(terminalTabsProvider).selected!;
    expect(tab.ai!.sessionId, 'sess-0');
    expect(tab.label, 'Fix login');
    expect(fakes.agent(1).received, contains('session/load:sess-0'));
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('no earlier session says so', (t) async {
    final (c, _) = await pane(t, const FakeScenario());
    await t.tap(find.byKey(const Key('ai.history')));
    await t.pumpAndSettle();
    expect(find.text('No earlier sessions for this folder.'), findsOneWidget);
    await disposeWorkspace(t, c);
  }, variant: mac);

  testWidgets('an agent that does not list sessions has no History', (t) async {
    final (c, _) = await pane(t, const FakeScenario(listSessions: false));
    expect(find.byKey(const Key('ai.history')), findsNothing);
    await disposeWorkspace(t, c);
  }, variant: mac);
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai/ai_history_test.dart`
Expected: the test does not compile, `Error when reading 'lib/src/ui/ai/ai_history.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/ui/ai/ai_history.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shellx_ai/host.dart';

import '../../../l10n/app_localizations.dart';
import '../theme/shellx_desktop_theme.dart';

/// "2026-10-13 09:30" in local time; the agent's text when it is no date.
String aiHistoryWhen(String? updatedAt) {
  final at = updatedAt == null ? null : DateTime.tryParse(updatedAt);
  if (at == null) return updatedAt ?? '';
  final t = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}

/// D15, spec §4.1: "Session history" — the agent's earlier sessions for
/// this folder (`session/list {cwd}`). The current one is marked and not
/// offered; another opens in a new AI tab that reopens it (`session/load`,
/// D14) through [onOpen].
Future<void> showAiHistory(
  BuildContext context,
  AiRuntime runtime, {
  required void Function(String sessionId, String? title) onOpen,
}) async {
  final result = await runtime.listSessions();
  if (!context.mounted) return;
  final state = runtime.state;
  await showDialog<void>(
    context: context,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      final dim = ShellxText.small.copyWith(
        color: ShellxDesktopColors.textSecondary,
      );
      final sessions = result?.sessions ?? const [];
      final Widget body;
      if (result == null) {
        body = Text(l10n.aiHistoryUnavailable(state.agentName), style: dim);
      } else if (sessions.isEmpty) {
        body = Text(l10n.aiHistoryEmpty, style: dim);
      } else {
        body = ListView.builder(
          itemCount: sessions.length,
          itemBuilder: (context, i) {
            final s = sessions[i];
            return ListTile(
              key: ValueKey('ai.history.${s.sessionId}'),
              dense: true,
              enabled: s.sessionId != state.sessionId,
              title: Text(
                (s.title?.trim().isNotEmpty ?? false)
                    ? s.title!
                    : l10n.aiHistoryUntitled,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(aiHistoryWhen(s.updatedAt), style: dim),
              trailing: s.sessionId == state.sessionId
                  ? Text(l10n.aiHistoryCurrent, style: dim)
                  : null,
              onTap: () {
                Navigator.of(context).pop();
                onOpen(s.sessionId, s.title);
              },
            );
          },
        );
      }
      return AlertDialog(
        key: const Key('ai.history.dialog'),
        title: Text(l10n.aiHistory),
        content: SizedBox(width: 480, height: 360, child: body),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.actionClose),
          ),
        ],
      );
    },
  );
}
```

In `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, replace:

```dart
import 'ai_header.dart';
import 'ai_log_dialog.dart';
```

with:

```dart
import 'ai_header.dart';
import 'ai_history.dart';
import 'ai_log_dialog.dart';
```

In `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, replace:

```dart
  /// Through the window's action when there is one (it also announces).
  void _zoom() {
```

with:

```dart
  /// D15: an earlier session of this folder, in a new AI tab of the same
  /// agent that reopens it (D14).
  Future<void> _history(AiRuntime runtime) => showAiHistory(
    context,
    runtime,
    onOpen: (sessionId, title) {
      final l10n = AppLocalizations.of(context);
      final pane = widget.pane;
      ref
          .read(terminalTabsProvider.notifier)
          .openAiTab(
            agentId: pane.agentId,
            agentName: pane.agentName,
            title: (title?.trim().isNotEmpty ?? false)
                ? title!
                : l10n.aiNewSession,
            cwd: runtime.state.cwd,
            sessionId: sessionId,
          );
    },
  );

  /// Through the window's action when there is one (it also announces).
  void _zoom() {
```

In `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, replace:

```dart
        view: view,
        onPanel: runtime == null ? null : _ui.togglePanel,
```

with:

```dart
        view: view,
        // D15: only for an agent that lists its sessions.
        onHistory: runtime != null && runtime.state.capabilities.listSessions
            ? () => unawaited(_history(runtime))
            : null,
        onPanel: runtime == null ? null : _ui.togglePanel,
```

- [ ] **Step 4: Run the tests**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/ui/ai test/ui/ai
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai test/ai test/ui/ai_tab_screens_test.dart 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `All tests passed!` (106 on the scratch copy); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/ui/ai/ai_history.dart apps/desktop/lib/src/ui/ai/ai_pane_view.dart apps/desktop/test/ui/ai/ai_history_test.dart
git commit -m "feat(v2-ai): session history — an earlier session reopens in a new AI tab

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 27: `@` mentions — the project's files, sent as `resource_link` (D16) [needs V2-1a Task 9]

Spec D16, §4.1 (the composer's row); ruling B12 (Task 25's index).

**Typing `@…`:** the composer shows the project's files that `.gitignore` keeps (Task 25's index, read off the UI isolate and read again after each turn). They are ranked: the name starting with the text, then containing it, then the path; at most 8.
- ↑/↓ move, Enter or Tab take one, a click takes one, Esc closes the list until another `@` starts.
- An open list takes Enter and Esc first: Esc then never stops the turn or answers a question.

**Sending:** every file still mentioned in the text goes along as a `resource_link` (`file://` URI, name, the relative path as title). This covers files picked here and Files › "Mention in chat"; the text itself is sent as typed.

**The "@" button:** a mention starts at the cursor.

**Files:**
- Create: `apps/desktop/lib/src/ui/ai/ai_completer.dart`
- Modify: `apps/desktop/lib/src/ui/ai/ai_composer.dart`, `apps/desktop/lib/src/ui/ai/ai_scope.dart`, `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`
- Test: `apps/desktop/test/ui/ai/ai_mention_test.dart`

**Interfaces:**
- Consumes: Task 25 `AiProjectFiles.index`; Task 20 `aiTurnsOf`; Task 15 `AiComposer` (`_onKey`, `_send`, `_onInsert`); `shellx_acp` `ResourceLinkBlock`, `TextBlock`.
- Produces: `AiCompleter` (`update`, `move`, `dismiss`, `accept`), `AiSuggestion`, `aiMatchFiles`, `kAiSuggestMax`; `AiPaneUi.fileIndex`; keys `ai.mention`, `ai.suggest.<i>`.

- [ ] **Step 1: Write the failing test**

`apps/desktop/test/ui/ai/ai_mention_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ui/ai/ai_completer.dart';
import 'package:shellx_desktop/src/ui/ai/ai_dock.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';

/// V2-1 D16: `@` mentions.
void main() {
  const files = ['README.md', 'lib/src/main.dart', 'src/domain.dart', 'x.txt'];

  test('ranking: the name starting with it, then containing it, then the '
      'path; shorter first', () {
    expect(
      [for (final s in aiMatchFiles(files, 'ma')) s.label],
      ['lib/src/main.dart', 'src/domain.dart'],
    );
    expect(
      [for (final s in aiMatchFiles(files, 'src')) s.label],
      ['src/domain.dart', 'lib/src/main.dart'],
    );
  });

  Future<(FakeAiRuntimes, AiRuntime)> dock(WidgetTester t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final runtime = partRuntime(fakes);
    await runtime.start();
    final part = await pumpAiPart(t, const AiDock(), runtime: runtime);
    part.ui.fileIndex = () async => files;
    await t.tap(find.byKey(const Key('ai.composer')));
    await t.pump();
    return (fakes, runtime);
  }

  String text(WidgetTester t) => t
      .widget<TextField>(find.byKey(const Key('ai.composer')))
      .controller!
      .text;

  testWidgets('@ offers the project\'s files; ↓ and Enter take one; the file '
      'goes along as a resource_link', (t) async {
    final (fakes, runtime) = await dock(t);
    await t.enterText(find.byKey(const Key('ai.composer')), 'look at @ma');
    await t.pump();
    expect(find.byKey(const Key('ai.suggest.0')), findsOneWidget);
    expect(find.text('lib/src/main.dart'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(text(t), 'look at @src/domain.dart ');
    expect(find.byKey(const Key('ai.suggest.0')), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    final prompt = fakes.agent().params['session/prompt']!['prompt']! as List;
    expect(prompt.first, {'type': 'text', 'text': 'look at @src/domain.dart'});
    expect(prompt.last, {
      'type': 'resource_link',
      'uri': Uri.file('$testAiCwd/src/domain.dart').toString(),
      'name': 'domain.dart',
      'title': 'src/domain.dart',
    });
    await runtime.dispose();
  });

  testWidgets('Esc closes the list and keeps the text (no Stop, no answer); '
      'the @ button starts a mention', (t) async {
    final (fakes, runtime) = await dock(t);
    await t.tap(find.byKey(const Key('ai.mention')));
    await t.pump();
    expect(text(t), '@');
    await t.pump();
    expect(find.byKey(const Key('ai.suggest.0')), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(find.byKey(const Key('ai.suggest.0')), findsNothing);
    expect(text(t), '@');
    await t.tap(find.byKey(const Key('ai.mention')));
    await t.pump();
    expect(fakes.agent().received.where((r) => r.contains('prompt')), isEmpty);
    await runtime.dispose();
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai/ai_mention_test.dart`
Expected: the test does not compile, `Error when reading 'lib/src/ui/ai/ai_completer.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/ui/ai/ai_completer.dart`:

```dart
import 'package:flutter/widgets.dart';

/// One line of the composer's suggestions (D16): what replaces the typed
/// token, what the line shows, and the file it mentions (null: none).
typedef AiSuggestion = ({
  String insert,
  String label,
  String? detail,
  String? mention,
});

/// The most suggestions shown at once.
const int kAiSuggestMax = 8;

/// D16: the files matching [query] (case-insensitive), best first — the
/// name starting with it, then the name containing it, then the path
/// containing it; shorter paths first among equals.
List<AiSuggestion> aiMatchFiles(List<String> files, String query) {
  final q = query.toLowerCase();
  int rank(String path) {
    final lower = path.toLowerCase();
    final name = lower.substring(lower.lastIndexOf('/') + 1);
    if (name.startsWith(q)) return 0;
    if (name.contains(q)) return 1;
    return lower.contains(q) ? 2 : 3;
  }

  final hits = [
    for (final f in files)
      if (rank(f) < 3) f,
  ];
  hits.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : a.length.compareTo(b.length);
  });
  return [
    for (final f in hits.take(kAiSuggestMax))
      (insert: '@$f ', label: f, detail: null, mention: f),
  ];
}

/// D16: what the composer offers while the user types `@…` (the project's
/// files that `.gitignore` keeps, Task 25's index). ↑/↓ move, Enter or Tab
/// take one, Esc closes the list until the token changes.
final class AiCompleter extends ChangeNotifier {
  AiCompleter({required this.files});

  /// The project's files; loaded when `@` is first typed.
  final Future<List<String>> Function() files;

  List<AiSuggestion> _items = const [];
  var _selected = 0;
  var _start = -1;
  var _closedAt = -1;
  var _gen = 0;

  List<AiSuggestion> get items => _items;
  int get selected => _selected;
  bool get active => _items.isNotEmpty;

  /// The text or the cursor moved: the token before the cursor decides.
  Future<void> update(TextEditingValue value) async {
    final gen = ++_gen;
    final sel = value.selection;
    if (!sel.isValid || !sel.isCollapsed) return _clear();
    final before = value.text.substring(0, sel.baseOffset);
    final at = RegExp(r'(?:^|\s)@([^\s@]*)$').firstMatch(before);
    if (at == null) {
      _closedAt = -1;
      return _clear();
    }
    final query = at.group(1)!;
    final start = before.length - query.length - 1;
    if (start == _closedAt) return _clear();
    final all = await files();
    if (gen != _gen) return;
    _show(start, aiMatchFiles(all, query));
  }

  void _show(int start, List<AiSuggestion> items) {
    _start = start;
    _items = items;
    _selected = 0;
    notifyListeners();
  }

  void _clear() {
    if (_items.isEmpty) return;
    _items = const [];
    notifyListeners();
  }

  void move(int delta) {
    if (_items.isEmpty) return;
    _selected = (_selected + delta) % _items.length;
    notifyListeners();
  }

  /// Esc: closed until another token starts.
  void dismiss() {
    _closedAt = _start;
    _clear();
  }

  /// [value] with the token replaced by suggestion [index] (the selected
  /// one by default), the cursor after it.
  (TextEditingValue, AiSuggestion) accept(
    TextEditingValue value, [
    int? index,
  ]) {
    final pick = _items[index ?? _selected];
    final end = value.selection.baseOffset;
    final text = value.text.replaceRange(_start, end, pick.insert);
    _clear();
    return (
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: _start + pick.insert.length),
      ),
      pick,
    );
  }
}
```

In `apps/desktop/lib/src/ui/ai/ai_scope.dart`, replace:

```dart
  /// Set by the pane: "Revert turn" N (§4.4).
  void Function(int turn)? onRevertTurn;
```

with:

```dart
  /// Set by the pane: "Revert turn" N (§4.4).
  void Function(int turn)? onRevertTurn;

  /// Set by the pane: the project's files for `@` (D16), read off the UI
  /// isolate and kept until a turn ends.
  Future<List<String>> Function()? fileIndex;
```

In `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, replace:

```dart
import '../../ai/ai_frame_notifier.dart';
```

with:

```dart
import '../../ai/ai_frame_notifier.dart';
import '../../ai/ai_project_files.dart';
```

In `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, replace:

```dart
    _ui.onRun = (request) => unawaited(_run(request));
```

with:

```dart
    _ui.onRun = (request) => unawaited(_run(request));
    _ui.fileIndex = _fileIndex;
```

In `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, replace:

```dart
  /// D15: an earlier session of this folder, in a new AI tab of the same
```

with:

```dart
  Future<List<String>>? _index;
  int? _indexTurn;

  /// D16: the project's files for `@`, read again after each turn.
  Future<List<String>> _fileIndex() {
    final runtime = _runtime;
    if (runtime == null) return Future.value(const []);
    final turn = aiTurnsOf(runtime.state).lastFinished;
    if (_index == null || _indexTurn != turn) {
      _indexTurn = turn;
      _index = ref
          .read(aiProjectFilesProvider)
          .index(runtime.state.cwd)
          .catchError((Object _) => const <String>[]);
    }
    return _index!;
  }

  /// D15: an earlier session of this folder, in a new AI tab of the same
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shellx_acp/shellx_acp.dart';
```

with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shellx_acp/shellx_acp.dart';
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
import '../theme/shellx_desktop_theme.dart';
import 'ai_config_chips.dart';
```

with:

```dart
import '../theme/shellx_desktop_theme.dart';
import 'ai_completer.dart';
import 'ai_config_chips.dart';
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
  AiPaneScope? _scope;
  _View? _view;
  String? _note;

  FocusNode get _focus => widget.focusNode ?? _ownFocus;
```

with:

```dart
  AiPaneScope? _scope;
  _View? _view;
  String? _note;

  /// D16: `@` file suggestions; the files mentioned so far (sent along as
  /// `resource_link` while their `@path` is still in the text).
  late final _completer = AiCompleter(
    files: () => _scope?.ui.fileIndex?.call() ?? Future.value(const []),
  );
  final _mentions = <String>{};

  FocusNode get _focus => widget.focusNode ?? _ownFocus;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onText);
  }

  void _onText() => unawaited(_completer.update(_text.value));
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
    _scope?.ui.insert.removeListener(_onInsert);
    _text.dispose();
    _ownFocus.dispose();
    super.dispose();
  }
```

with:

```dart
    _scope?.ui.insert.removeListener(_onInsert);
    _text.dispose();
    _ownFocus.dispose();
    _completer.dispose();
    super.dispose();
  }
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
    _text.value = TextEditingValue(
      text: v.text.replaceRange(at, end, add),
      selection: TextSelection.collapsed(offset: at + add.length),
    );
    _focus.requestFocus();
  }
```

with:

```dart
    _text.value = TextEditingValue(
      text: v.text.replaceRange(at, end, add),
      selection: TextSelection.collapsed(offset: at + add.length),
    );
    if (add.startsWith('@')) _mentions.add(add.substring(1).trim());
    _focus.requestFocus();
  }

  /// A suggestion goes in place of what was typed.
  void _take([int? index]) {
    final (value, pick) = _completer.accept(_text.value, index);
    _text.value = value;
    if (pick.mention case final path?) _mentions.add(path);
  }

  /// The "@" button: a mention starts at the cursor.
  void _startMention() {
    final v = _text.value;
    final at = v.selection.isValid ? v.selection.start : v.text.length;
    final space = at > 0 && v.text[at - 1].trim().isNotEmpty ? ' ' : '';
    _text.value = TextEditingValue(
      text: v.text.replaceRange(at, at, '$space@'),
      selection: TextSelection.collapsed(offset: at + space.length + 1),
    );
    _focus.requestFocus();
  }
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
    _text.clear();
    setState(() => _note = null);
    final ok = await scope.runtime.send([TextBlock(text.trim())]);
```

with:

```dart
    // D16: each file still mentioned goes along as a `resource_link`.
    final cwd = scope.state.cwd;
    final blocks = <ContentBlock>[
      TextBlock(text.trim()),
      for (final path in _mentions)
        if (text.contains('@$path'))
          ResourceLinkBlock(
            uri: Uri.file(p.join(cwd, path)).toString(),
            name: p.basename(path),
            title: path,
          ),
    ];
    _mentions.clear();
    _text.clear();
    setState(() => _note = null);
    final ok = await scope.runtime.send(blocks);
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
    if (_text.value.composing.isValid) return KeyEventResult.ignored;
    if (widget.keyHook?.call(event, hasText: _text.text.isNotEmpty) ?? false) {
```

with:

```dart
    if (_text.value.composing.isValid) return KeyEventResult.ignored;
    // D16: an open suggestion list takes its keys first (Esc closes it,
    // never a question).
    if (_completer.active) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowDown:
          _completer.move(1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp:
          _completer.move(-1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.enter ||
            LogicalKeyboardKey.numpadEnter ||
            LogicalKeyboardKey.tab:
          _take();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.escape:
          _completer.dismiss();
          return KeyEventResult.handled;
      }
    }
    if (widget.keyHook?.call(event, hasText: _text.text.isNotEmpty) ?? false) {
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: AiSizes.composerMax),
```

with:

```dart
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListenableBuilder(
            listenable: _completer,
            builder: (context, _) => _completer.active
                ? _Suggestions(completer: _completer, onPick: _take)
                : const SizedBox.shrink(),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: AiSizes.composerMax),
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
            child: Row(
              children: [
                if (_note case final note?)
```

with:

```dart
            child: Row(
              children: [
                IconButton(
                  key: const Key('ai.mention'),
                  tooltip: l10n.aiMention,
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  onPressed: _canSend ? _startMention : null,
                  icon: const Icon(Icons.alternate_email),
                ),
                if (_note case final note?)
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
/// Send (⏎) / Queue (⏎) / Stop (Esc) / Stopping… / Force stop.
```

with:

```dart
/// D16: the suggestions over the field: the selected one lit; a click
/// takes one.
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.completer, required this.onPick});

  final AiCompleter completer;
  final void Function(int index) onPick;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.all(ShellxSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, s) in completer.items.indexed)
            InkWell(
              key: Key('ai.suggest.$i'),
              onTap: () => onPick(i),
              child: Container(
                color: i == completer.selected
                    ? ShellxDesktopColors.rowSelected
                    : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: ShellxSpace.s8,
                  vertical: ShellxSpace.s2,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kAiMono,
                      ),
                    ),
                    if (s.detail case final detail?)
                      Flexible(
                        child: Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ShellxText.caption.copyWith(
                            color: ShellxDesktopColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Send (⏎) / Queue (⏎) / Stop (Esc) / Stopping… / Force stop.
```

- [ ] **Step 4: Run the tests**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/ui/ai test/ui/ai
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai test/ai test/ui/ai_tab_screens_test.dart 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `All tests passed!` (109 on the scratch copy); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/ui/ai/ai_completer.dart apps/desktop/lib/src/ui/ai/ai_composer.dart apps/desktop/lib/src/ui/ai/ai_scope.dart apps/desktop/lib/src/ui/ai/ai_pane_view.dart apps/desktop/test/ui/ai/ai_mention_test.dart
git commit -m "feat(v2-ai): @ mentions of the project's files, sent as resource links

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 28: `/` commands from `available_commands_update` (D16) [needs V2-1a Task 9]

Spec D16.

**Typing `/…` at the start of the message:** the composer lists the agent's commands as last announced (`available_commands_update`). Names starting with the text come first, then names containing it, with the description and the input hint.
- Taking one puts `/name ` in place; the message is sent as typed (ACP commands are prompts).
- A `/` later in the text is only text.

**The "/" button:** a command starts the message.

**Files:**
- Modify: `apps/desktop/lib/src/ui/ai/ai_completer.dart`, `apps/desktop/lib/src/ui/ai/ai_composer.dart`
- Test: `apps/desktop/test/ui/ai/ai_commands_test.dart`

**Interfaces:**
- Consumes: Task 27 `AiCompleter`; V2-1a `AiSessionState.commands`; `shellx_acp` `AvailableCommand` (`name`, `description`, `hint`), `CommandsUpdated`.
- Produces: `aiMatchCommands(commands, query)`; `AiCompleter(commands:)`; key `ai.commands`.

- [ ] **Step 1: Write the failing test**

`apps/desktop/test/ui/ai/ai_commands_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ui/ai/ai_completer.dart';
import 'package:shellx_desktop/src/ui/ai/ai_dock.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';

const _commands = [
  AvailableCommand(name: 'review', description: 'Review the changes'),
  AvailableCommand(
    name: 'init',
    description: 'Write CLAUDE.md',
    hint: 'what to cover',
  ),
  AvailableCommand(name: 'pr-comments', description: 'Read PR comments'),
];

/// V2-1 D16: `/` lists the agent's commands.
void main() {
  test('names starting with the text first, then containing it', () {
    expect(
      [for (final s in aiMatchCommands(_commands, 'r')) s.label],
      ['/review', '/pr-comments'],
    );
    expect(
      aiMatchCommands(_commands, 'init').single.detail,
      'Write CLAUDE.md — what to cover',
    );
  });

  Future<(FakeAiRuntimes, AiRuntime)> dock(WidgetTester t) async {
    final fakes = FakeAiRuntimes(const FakeScenario());
    final runtime = partRuntime(fakes);
    await runtime.start();
    runtime.state.applyUpdate(
      const CommandsUpdated(_commands),
      DateTime(2026, 10, 14),
    );
    await pumpAiPart(t, const AiDock(), runtime: runtime);
    await t.tap(find.byKey(const Key('ai.composer')));
    await t.pump();
    return (fakes, runtime);
  }

  testWidgets('/ at the start lists the commands; one is taken and sent as '
      'typed', (t) async {
    final (fakes, runtime) = await dock(t);
    await t.enterText(find.byKey(const Key('ai.composer')), '/re');
    await t.pump();
    expect(find.text('/review'), findsOneWidget);
    expect(find.text('Review the changes'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(
      t
          .widget<TextField>(find.byKey(const Key('ai.composer')))
          .controller!
          .text,
      '/review ',
    );
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(fakes.agent().received, contains('session/prompt:/review'));
    await runtime.dispose();
  });

  testWidgets('a / later in the text is only text; the / button starts a '
      'command', (t) async {
    final (_, runtime) = await dock(t);
    await t.enterText(find.byKey(const Key('ai.composer')), 'and /re');
    await t.pump();
    expect(find.byKey(const Key('ai.suggest.0')), findsNothing);
    await t.enterText(find.byKey(const Key('ai.composer')), '');
    await t.tap(find.byKey(const Key('ai.commands')));
    await t.pump();
    await t.pump();
    expect(find.text('/init'), findsOneWidget);
    await runtime.dispose();
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai/ai_commands_test.dart`
Expected: the test does not compile, `Method not found: 'aiMatchCommands'`.

- [ ] **Step 3: Implement**

In `apps/desktop/lib/src/ui/ai/ai_completer.dart`, replace:

```dart
import 'package:flutter/widgets.dart';
```

with:

```dart
import 'package:flutter/widgets.dart';
import 'package:shellx_acp/shellx_acp.dart' show AvailableCommand;
```

In `apps/desktop/lib/src/ui/ai/ai_completer.dart`, replace:

```dart
/// D16: what the composer offers while the user types `@…` (the project's
/// files that `.gitignore` keeps, Task 25's index). ↑/↓ move, Enter or Tab
/// take one, Esc closes the list until the token changes.
final class AiCompleter extends ChangeNotifier {
  AiCompleter({required this.files});

  /// The project's files; loaded when `@` is first typed.
  final Future<List<String>> Function() files;
```

with:

```dart
/// D16: the agent's commands (`available_commands_update`) matching
/// [query]: the name starting with it, then containing it; at most 8.
List<AiSuggestion> aiMatchCommands(
  List<AvailableCommand> commands,
  String query,
) {
  final q = query.toLowerCase();
  final starts = [
    for (final c in commands)
      if (c.name.toLowerCase().startsWith(q)) c,
  ];
  final contains = [
    for (final c in commands)
      if (!c.name.toLowerCase().startsWith(q) &&
          c.name.toLowerCase().contains(q))
        c,
  ];
  return [
    for (final c in [...starts, ...contains].take(kAiSuggestMax))
      (
        insert: '/${c.name} ',
        label: '/${c.name}',
        detail: [c.description, ?c.hint].where((s) => s.isNotEmpty).join(' — '),
        mention: null,
      ),
  ];
}

/// D16: what the composer offers while the user types `@…` (the project's
/// files that `.gitignore` keeps, Task 25's index) or, at the start, `/…`
/// (the agent's commands). ↑/↓ move, Enter or Tab take one, Esc closes the
/// list until the token changes.
final class AiCompleter extends ChangeNotifier {
  AiCompleter({required this.files, required this.commands});

  /// The project's files; loaded when `@` is first typed.
  final Future<List<String>> Function() files;

  /// The agent's commands as last announced.
  final List<AvailableCommand> Function() commands;
```

In `apps/desktop/lib/src/ui/ai/ai_completer.dart`, replace:

```dart
    final before = value.text.substring(0, sel.baseOffset);
    final at = RegExp(r'(?:^|\s)@([^\s@]*)$').firstMatch(before);
```

with:

```dart
    final before = value.text.substring(0, sel.baseOffset);
    final slash = RegExp(r'^/(\S*)$').firstMatch(before);
    if (slash != null) {
      if (_closedAt == 0) return _clear();
      return _show(0, aiMatchCommands(commands(), slash.group(1)!));
    }
    final at = RegExp(r'(?:^|\s)@([^\s@]*)$').firstMatch(before);
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
  late final _completer = AiCompleter(
    files: () => _scope?.ui.fileIndex?.call() ?? Future.value(const []),
  );
```

with:

```dart
  late final _completer = AiCompleter(
    files: () => _scope?.ui.fileIndex?.call() ?? Future.value(const []),
    commands: () => _scope?.state.commands ?? const [],
  );
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
  /// The "@" button: a mention starts at the cursor.
```

with:

```dart
  /// The "/" button: a command starts the message.
  void _startCommand() {
    final text = _text.text.startsWith('/') ? _text.text : '/${_text.text}';
    _text.value = TextEditingValue(
      text: text,
      selection: const TextSelection.collapsed(offset: 1),
    );
    _focus.requestFocus();
  }

  /// The "@" button: a mention starts at the cursor.
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
                  onPressed: _canSend ? _startMention : null,
                  icon: const Icon(Icons.alternate_email),
                ),
```

with:

```dart
                  onPressed: _canSend ? _startMention : null,
                  icon: const Icon(Icons.alternate_email),
                ),
                IconButton(
                  key: const Key('ai.commands'),
                  tooltip: l10n.aiCommands,
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  onPressed: _canSend ? _startCommand : null,
                  icon: const Icon(Icons.terminal),
                ),
```

- [ ] **Step 4: Run the tests**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/ui/ai test/ui/ai
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai test/ai test/ui/ai_tab_screens_test.dart 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `All tests passed!` (112 on the scratch copy); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/ui/ai/ai_completer.dart apps/desktop/lib/src/ui/ai/ai_composer.dart apps/desktop/test/ui/ai/ai_commands_test.dart
git commit -m "feat(v2-ai): / lists the agent's commands in the composer

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 29: Images — paste and drop on the composer (D16) [needs V2-1a Task 9]

Spec D16 ("paste or drag an image → `image`, if the agent declares `promptCapabilities.image`").

**Paste:** ⌘V / Ctrl+V (and Ctrl+Shift+V) in the composer look for an image on the clipboard first (A10's `ClipboardMedia`, through a pane hook); otherwise they paste the text at the cursor.

**Drop:** image files dropped on the composer go with the next message, each at most 10 MiB. A hidden pane takes no drop: its `TickerMode` is off.

**Which images:** PNG, JPEG, GIF and WebP, told by their first bytes; at most 5 per message, each shown above the field with "Remove image".
- An agent that takes no images: "{agent} does not take images." and nothing is attached.

**Sending:** the images go as `image` blocks (base64 and MIME type); a message may be images alone.

**Manual check (spec §9):** dragging an image from Finder / Explorer. `desktop_drop` cannot be driven from a widget test; it is listed in Task 30.

**Files:**
- Create: `apps/desktop/lib/src/ui/ai/ai_images.dart`
- Modify: `apps/desktop/lib/src/ui/ai/ai_scope.dart`, `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, `apps/desktop/lib/src/ui/ai/ai_dock.dart`, `apps/desktop/lib/src/ui/ai/ai_composer.dart`
- Test: `apps/desktop/test/ui/ai/ai_image_test.dart`

**Interfaces:**
- Consumes: `clipboardMediaProvider` (`ClipboardMedia.image()`); `desktop_drop` `DropTarget`; `shellx_acp` `ImageBlock`, `PromptCapabilities.image`; Task 15 `AiDock`/`AiComposer`; `textEditingShortcuts()`.
- Produces: `AiPasteIntent`, `AiImageInput`, `AiAttachments`, `aiAttachImage`, `aiImageMime`, `kAiImagesMax`; `AiPaneUi.images` (`AiImages`: `add`, `remove`, `say`, `clear`), `AiPaneUi.clipboardImage`, `AiPaneUi.readImageFile`; keys `ai.image.<i>`, `ai.image.remove.<i>`, `ai.image.note`.

- [ ] **Step 1: Write the failing test**

`apps/desktop/test/ui/ai/ai_image_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_ai/host.dart';
import 'package:shellx_ai/testing.dart';
import 'package:shellx_desktop/src/ui/ai/ai_dock.dart';
import 'package:shellx_desktop/src/ui/ai/ai_images.dart';
import 'package:shellx_desktop/src/ui/ai/ai_scope.dart';

import '../../support/ai_fakes.dart';
import '../../support/ai_parts.dart';

/// A 1×1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

/// V2-1 D16: images pasted into the composer.
void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

  test('image types by their first bytes', () {
    expect(aiImageMime(_png), 'image/png');
    expect(
      aiImageMime(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])),
      'image/jpeg',
    );
    expect(aiImageMime(Uint8List.fromList(utf8.encode('hello'))), isNull);
  });

  Future<(FakeAiRuntimes, AiRuntime, AiPaneUi)> dock(
    WidgetTester t,
    FakeScenario scenario, {
    Uint8List? clipboard,
  }) async {
    final fakes = FakeAiRuntimes(scenario);
    final runtime = partRuntime(fakes);
    await runtime.start();
    final part = await pumpAiPart(t, const AiDock(), runtime: runtime);
    part.ui.clipboardImage = () async => clipboard;
    await t.tap(find.byKey(const Key('ai.composer')));
    await t.pump();
    return (fakes, runtime, part.ui);
  }

  Future<void> paste(WidgetTester t) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyV);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await t.pump();
    await t.pump();
  }

  testWidgets('⌘V with an image attaches it; it goes as an image block, '
      'with or without text', (t) async {
    final (fakes, runtime, _) = await dock(
      t,
      const FakeScenario(),
      clipboard: _png,
    );
    await paste(t);
    expect(find.byKey(const Key('ai.image.0')), findsOneWidget);
    await t.enterText(find.byKey(const Key('ai.composer')), 'what is this');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    final prompt = fakes.agent().params['session/prompt']!['prompt']! as List;
    expect(prompt, [
      {'type': 'text', 'text': 'what is this'},
      {'type': 'image', 'data': base64Encode(_png), 'mimeType': 'image/png'},
    ]);
    expect(find.byKey(const Key('ai.image.0')), findsNothing);
    await runtime.dispose();
  }, variant: mac);

  testWidgets('"Remove image" takes it off', (t) async {
    final (_, runtime, _) = await dock(
      t,
      const FakeScenario(),
      clipboard: _png,
    );
    await paste(t);
    await t.tap(find.byKey(const Key('ai.image.remove.0')));
    await t.pump();
    expect(find.byKey(const Key('ai.image.0')), findsNothing);
    await runtime.dispose();
  }, variant: mac);

  testWidgets('an agent that takes no images says so', (t) async {
    final (_, runtime, ui) = await dock(
      t,
      const FakeScenario(image: false),
      clipboard: _png,
    );
    await paste(t);
    expect(find.text('Claude does not take images.'), findsOneWidget);
    expect(ui.images.items, isEmpty);
    await runtime.dispose();
  }, variant: mac);

  testWidgets('without an image, ⌘V pastes the text at the cursor', (t) async {
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': 'hello'} : null,
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final (_, runtime, _) = await dock(t, const FakeScenario());
    await paste(t);
    expect(
      t
          .widget<TextField>(find.byKey(const Key('ai.composer')))
          .controller!
          .text,
      'hello',
    );
    await runtime.dispose();
  }, variant: mac);
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test test/ui/ai/ai_image_test.dart`
Expected: the test does not compile, `Error when reading 'lib/src/ui/ai/ai_images.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`apps/desktop/lib/src/ui/ai/ai_images.dart`:

```dart
import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_scope.dart';

/// ⌘V / Ctrl+V (and Ctrl+Shift+V) in the composer, D16: an image on the
/// clipboard first, else the text.
class AiPasteIntent extends Intent {
  const AiPasteIntent();
}

/// The most images one message takes.
const int kAiImagesMax = 5;

/// The image type of [bytes] by their first bytes (PNG, JPEG, GIF, WebP);
/// null: not an image ShellX sends.
String? aiImageMime(Uint8List bytes) {
  bool starts(List<int> sig, [int at = 0]) {
    if (bytes.length < at + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (bytes[at + i] != sig[i]) return false;
    }
    return true;
  }

  if (starts([0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (starts([0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (starts([0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (starts([0x52, 0x49, 0x46, 0x46]) && starts([0x57, 0x45, 0x42, 0x50], 8)) {
    return 'image/webp';
  }
  return null;
}

/// D16: [bytes] go with the next message — when the agent takes images
/// (`promptCapabilities.image`); otherwise the composer says it does not.
void aiAttachImage(AiPaneScope scope, AppLocalizations l10n, Uint8List bytes) {
  final images = scope.ui.images;
  if (!scope.state.capabilities.prompt.image) {
    images.say(l10n.aiImageUnsupported(scope.state.agentName));
    return;
  }
  final mime = aiImageMime(bytes);
  if (mime == null || images.items.length >= kAiImagesMax) return;
  images.add(bytes, mime);
}

/// D16 around the composer: a paste looks for an image on the clipboard
/// first (else pastes the text at the cursor), and images dropped on it go
/// with the next message. A hidden pane takes no drop (`DropTarget` hears
/// drops while invisible).
class AiImageInput extends StatelessWidget {
  const AiImageInput({super.key, required this.child});
  final Widget child;

  Future<void> _paste(BuildContext context) async {
    final scope = AiPaneScope.of(context);
    final l10n = AppLocalizations.of(context);
    final image = await scope.ui.clipboardImage?.call();
    if (image != null) {
      aiAttachImage(scope, l10n, image);
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) scope.ui.insert.value = text;
  }

  Future<void> _drop(BuildContext context, DropDoneDetails details) async {
    final scope = AiPaneScope.of(context);
    final l10n = AppLocalizations.of(context);
    for (final f in details.files) {
      if (f.path.isEmpty) continue;
      final bytes = await scope.ui.readImageFile?.call(f.path);
      if (bytes != null) aiAttachImage(scope, l10n, bytes);
    }
  }

  @override
  Widget build(BuildContext context) => Actions(
    actions: {
      AiPasteIntent: CallbackAction<AiPasteIntent>(
        onInvoke: (_) {
          unawaited(_paste(context));
          return null;
        },
      ),
    },
    child: DropTarget(
      enable: TickerMode.valuesOf(context).enabled,
      onDragDone: (details) => unawaited(_drop(context, details)),
      child: child,
    ),
  );
}

/// The images going with the next message, each with "Remove image", and
/// what the composer has to say about images.
class AiAttachments extends StatelessWidget {
  const AiAttachments({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final images = AiPaneScope.of(context).ui.images;
    return ListenableBuilder(
      listenable: images,
      builder: (context, _) {
        if (images.items.isEmpty && images.note == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            ShellxSpace.s8,
            ShellxSpace.s8,
            ShellxSpace.s8,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: ShellxSpace.s6,
                children: [
                  for (final (i, image) in images.items.indexed)
                    Row(
                      key: Key('ai.image.$i'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(ShellxRadius.r6),
                          child: Image.memory(
                            image.bytes,
                            height: 40,
                            gaplessPlayback: true,
                          ),
                        ),
                        IconButton(
                          key: Key('ai.image.remove.$i'),
                          tooltip: l10n.aiRemoveImage,
                          iconSize: 12,
                          visualDensity: VisualDensity.compact,
                          onPressed: () => images.remove(i),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                ],
              ),
              if (images.note case final note?)
                Text(
                  note,
                  key: const Key('ai.image.note'),
                  style: ShellxText.caption.copyWith(
                    color: ShellxDesktopColors.warn,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
```

In `apps/desktop/lib/src/ui/ai/ai_scope.dart`, replace:

```dart
import 'package:flutter/widgets.dart';
import 'package:shellx_acp/shellx_acp.dart' show AuthMethodTerminal;
```

with:

```dart
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:shellx_acp/shellx_acp.dart' show AuthMethodTerminal;
```

In `apps/desktop/lib/src/ui/ai/ai_scope.dart`, replace:

```dart
/// The right panel's tabs (§4.4).
enum AiPanelTab { changes, files }
```

with:

```dart
/// The right panel's tabs (§4.4).
enum AiPanelTab { changes, files }

/// D16: the images going with the next message, and what the composer has
/// to say about images ("Claude does not take images.").
final class AiImages extends ChangeNotifier {
  final items = <({Uint8List bytes, String mime})>[];
  String? note;

  void add(Uint8List bytes, String mime) {
    items.add((bytes: bytes, mime: mime));
    note = null;
    notifyListeners();
  }

  void remove(int index) {
    items.removeAt(index);
    notifyListeners();
  }

  void say(String? text) {
    note = text;
    notifyListeners();
  }

  void clear() {
    if (items.isEmpty && note == null) return;
    items.clear();
    note = null;
    notifyListeners();
  }
}
```

In `apps/desktop/lib/src/ui/ai/ai_scope.dart`, replace:

```dart
  /// Set by the pane: the project's files for `@` (D16), read off the UI
  /// isolate and kept until a turn ends.
  Future<List<String>> Function()? fileIndex;
```

with:

```dart
  /// Set by the pane: the project's files for `@` (D16), read off the UI
  /// isolate and kept until a turn ends.
  Future<List<String>> Function()? fileIndex;

  /// D16: the images of the next message.
  final images = AiImages();

  /// Set by the pane: an image on the clipboard; null: none.
  Future<Uint8List?> Function()? clipboardImage;

  /// Set by the pane: a dropped file's bytes; null: unreadable or over
  /// 10 MiB.
  Future<Uint8List?> Function(String path)? readImageFile;
```

In `apps/desktop/lib/src/ui/ai/ai_scope.dart`, replace:

```dart
  @override
  void dispose() {
    insert.dispose();
    note.dispose();
    changes.dispose();
    super.dispose();
  }
```

with:

```dart
  @override
  void dispose() {
    insert.dispose();
    note.dispose();
    changes.dispose();
    images.dispose();
    super.dispose();
  }
```

In `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, replace:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
```

with:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
```

In `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, replace:

```dart
import '../../config/settings_schema.dart' show SettingPage;
```

with:

```dart
import '../../config/settings_schema.dart' show SettingPage;
import '../../terminal/clipboard_media.dart' show clipboardMediaProvider;
```

In `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, replace:

```dart
    _ui.fileIndex = _fileIndex;
```

with:

```dart
    _ui.fileIndex = _fileIndex;
    _ui.clipboardImage = () => ref.read(clipboardMediaProvider).image();
    _ui.readImageFile = _readImage;
```

In `apps/desktop/lib/src/ui/ai/ai_pane_view.dart`, replace:

```dart
  Future<List<String>>? _index;
  int? _indexTurn;
```

with:

```dart
  /// D16: a dropped image, at most 10 MiB (agents refuse bigger ones).
  static Future<Uint8List?> _readImage(String path) async {
    try {
      final file = File(path);
      if (await file.length() > 10 << 20) return null;
      return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  Future<List<String>>? _index;
  int? _indexTurn;
```

In `apps/desktop/lib/src/ui/ai/ai_dock.dart`, replace:

```dart
import 'ai_composer.dart';
```

with:

```dart
import 'ai_composer.dart';
import 'ai_images.dart';
```

In `apps/desktop/lib/src/ui/ai/ai_dock.dart`, replace:

```dart
            AiComposer(focusNode: focusNode, keyHook: keyHook),
```

with:

```dart
            // D16: images pasted or dropped on the composer.
            AiImageInput(
              child: AiComposer(focusNode: focusNode, keyHook: keyHook),
            ),
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
```

with:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
import 'ai_config_chips.dart';
import 'ai_scope.dart';
```

with:

```dart
import 'ai_config_chips.dart';
import 'ai_images.dart';
import 'ai_scope.dart';
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
typedef AiKeyHook = bool Function(KeyEvent event, {required bool hasText});
```

with:

```dart
typedef AiKeyHook = bool Function(KeyEvent event, {required bool hasText});

/// The text field's keys: a paste becomes [AiPasteIntent] (an image first,
/// D16); the rest as in every field of the window.
final Map<ShortcutActivator, Intent> _keys = {
  for (final MapEntry(:key, :value) in textEditingShortcuts().entries)
    key: value is PasteTextIntent ? const AiPasteIntent() : value,
};
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
                shortcuts: textEditingShortcuts(),
```

with:

```dart
                shortcuts: _keys,
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
  Future<void> _send() async {
    final text = _text.text;
    if (text.trim().isEmpty || !_canSend) return;
    final scope = _scope!;
    final l10n = AppLocalizations.of(context);
```

with:

```dart
  Future<void> _send() async {
    final text = _text.text;
    final scope = _scope!;
    final images = [...scope.ui.images.items];
    if ((text.trim().isEmpty && images.isEmpty) || !_canSend) return;
    final l10n = AppLocalizations.of(context);
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
    final blocks = <ContentBlock>[
      TextBlock(text.trim()),
      for (final path in _mentions)
```

with:

```dart
    final blocks = <ContentBlock>[
      if (text.trim().isNotEmpty) TextBlock(text.trim()),
      // D16: the images, as `image` blocks.
      for (final i in images)
        ImageBlock(data: base64Encode(i.bytes), mimeType: i.mime),
      for (final path in _mentions)
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
    _mentions.clear();
    _text.clear();
    setState(() => _note = null);
```

with:

```dart
    _mentions.clear();
    scope.ui.images.clear();
    _text.clear();
    setState(() => _note = null);
```

In `apps/desktop/lib/src/ui/ai/ai_composer.dart`, replace:

```dart
          ListenableBuilder(
            listenable: _completer,
            builder: (context, _) => _completer.active
                ? _Suggestions(completer: _completer, onPick: _take)
                : const SizedBox.shrink(),
          ),
```

with:

```dart
          ListenableBuilder(
            listenable: _completer,
            builder: (context, _) => _completer.active
                ? _Suggestions(completer: _completer, onPick: _take)
                : const SizedBox.shrink(),
          ),
          const AiAttachments(),
```

- [ ] **Step 4: Run the whole suite**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/src/ui/ai test/ui/ai
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
```

Expected: `All other tests passed!` (3 248 passing, 10 skipped on the scratch copy); `No issues found!`.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/ui/ai/ai_images.dart apps/desktop/lib/src/ui/ai/ai_scope.dart apps/desktop/lib/src/ui/ai/ai_pane_view.dart apps/desktop/lib/src/ui/ai/ai_dock.dart apps/desktop/lib/src/ui/ai/ai_composer.dart apps/desktop/test/ui/ai/ai_image_test.dart
git commit -m "feat(v2-ai): images pasted or dropped on the composer, for agents that take them

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 30: Finish — the whole check, the ⚠ manual checks, the ledger [needs V2-1a Task 9]

Spec §7, §8, §9. No new code: this task checks what Tasks 1–29 built, lists what only a person in front of a Mac and a Windows PC can check, and records both in the ledger.

**Files:**
- Modify: `docs/superpowers/ledgers/v2-ai.md`

- [ ] **Step 1: The whole suite, the analyzer, a build**

```bash
cd apps/desktop
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test 2>&1 | tail -1
PATH=~/fvm/versions/3.41.4/bin:$PATH flutter build macos --debug 2>&1 | tail -1
git diff --stat "$(git log --format=%H --grep='pin the D17 packages' -n1)~1" HEAD -- ../../packages/shellx_acp ../../packages/shellx_ai
```

Expected:
- `No issues found!`;
- `All other tests passed!` (3 248 passing, 10 skipped on the scratch copy, plus whatever V2-1a added since);
- the build line ends in `ShellX.app`;
- the last command prints nothing: V2-1b never changed V2-1a's packages.

On Windows (or the `windows-check` CI job once the branch is pushed), `flutter test` passes too.

- [ ] **Step 2: The review greps (spec §8, D20, D21)**

```bash
cd apps/desktop
grep -rn "debugPrint(" lib/src/ai lib/src/ui/ai | grep -v runtimeType
grep -n "Claude Code" lib/l10n/app_en.arb lib/l10n/app_vi.arb
grep -rn "hide-claude-auth" lib ../../packages/shellx_ai/lib
grep -rn "answerPermission(" lib/src
```

Expected:
- **The first grep:** one line, `ai_startup.dart: … 'ShellX: stopped $stopped stray agent(s)'`, a count. Nothing logs a prompt, text, output, path or file name.
- **The second grep:** `agentNamesClaude` (A12's name for the terminal program) and `aiSettingClaudeDesc` ("Runs Claude Code through the Claude Agent adapter"), a description as D21 allows. No feature or menu says "Claude Code".
- **The third grep:** nothing.
- **The fourth grep:** only `ai_permission_bar.dart`, all on a key the user pressed or a button the user clicked. Nothing answers a permission by itself.

- [ ] **Step 3: ⚠ Manual checks (spec §9, plus this plan's own)**

Each needs a person in front of a Mac and a Windows PC. Do the ones you can; leave the rest "pending" in the ledger.

1. **Claude (adapter 0.90.x, pinned), macOS and Windows:**
   - a whole turn with a permission (keys 1–3, Esc), Stop, and Force stop after 10 s;
   - sign-in in the run sheet with Claude Subscription and with Anthropic Console;
   - quit and restart: the tab comes back with "Resume session", and the conversation reloads when shown;
   - History opens an earlier session;
   - a multiple-choice question (elicitation).
2. **Codex:**
   - Install in the run sheet (Settings › Agents and the card), the folder `<support>/ai/agents/codex` created first;
   - sign in;
   - one turn that edits a file, reverted from the Changes panel.
3. **Gemini CLI and OpenCode:** one basic turn each.
4. **Typing and screen readers:**
   - Telex in the composer (macOS, Windows): Enter never sends a word being composed;
   - VoiceOver and Narrator read the cards, the permission bar (once) and the header status.
5. **A large project** (about 100 000 files):
   - the first restore point stays in the background, and the threshold says so past 200 000 files or 30 s;
   - `@` and the Files tab stay smooth: walks run off the UI isolate, the index stops at 20 000 files.
6. **Network and machines:** npm behind a proxy (Install in the run sheet); a machine without Node ("needs Node.js 22" card, guide link); macOS without Command Line Tools (undo off, the card says why, no install dialog pops).
7. **This plan's own:**
   - **Drop:** an image dragged from Finder / Explorer onto the composer is attached (Task 29); dropped on a hidden tab, nothing happens.
   - **Processes:** quit with a turn running and `pgrep -fl claude-agent-acp` (Windows: Task Manager) shows nothing. Kill the app (`kill -9`) during a turn, start it again, and the left-over agent and its children are gone (Task 11).
   - **Windows `.cmd` shim:** a custom agent pointing at a `.cmd` name shows "Only a .cmd or .bat file was found; ShellX runs programs directly." (Task 14 card, Task 24 row).
   - **The run sheet looks right:** `claude /login` shows its colours (`TERM=xterm-256color`, `COLORTERM=truecolor`), while the agents themselves run with `TERM=dumb`.
   - **Keys stay in the AI pane:** with a shell tab open before it, typing, Backspace and the arrows in the composer never reach the shell (Review Focus 5).

- [ ] **Step 4: The ledger**

Append under `## V2-1b (desktop) — execution` in `docs/superpowers/ledgers/v2-ai.md` (Task 1 began it), one line per item, filling each `…` with what Steps 1–3 showed:

```markdown
- Task 30 (<date>): flutter analyze: …; flutter test: … passing, … skipped; flutter build macos --debug: …; Windows (`windows-check` or a PC): …; packages/shellx_acp and packages/shellx_ai untouched by V2-1b: ….
- Review greps (§8, D20, D21): …
- ⚠ Manual checks (spec §9): 1 Claude: …; 2 Codex: …; 3 Gemini CLI, OpenCode: …; 4 Telex, VoiceOver, Narrator: …; 5 large project: …; 6 proxy, no Node, no Command Line Tools: …; 7 drop, processes, .cmd shim, run sheet colours, keys stay in the pane: …. Each "done <date>: what was seen" or "pending".
- Findings that contradict the spec or the rulings B1–B16: … (or "none").
```

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/ledgers/v2-ai.md
git commit -m "docs(v2-ai): V2-1b execution — checks run, manual checks recorded

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Self-review

**Spec coverage**, decision by decision:
- **V2-1a's, consumed here:** D1 (ACP v1), D6 (process, environment, npm pins, Node) and D9 (session model). Tasks 10–11 use them, with the desktop's tree killer for stops and for the crash sweep (Task 11).
- **D2–D5:**
  - D2 (tab kind, `label`, null getters): Tasks 3, 5, 10.
  - D3 (AI pane in the tree, terminal under it at 72 %, close asks): Tasks 3, 5, 10, 17.
  - D4 (`new-tab-kind`, onboarding, intro card): Tasks 8, 23.
  - D5 (opening AI tabs, folder rule, default agent): Tasks 9, 19, and Task 17's folder card.
- **D7–D12:**
  - D7 (Settings › Agents): Tasks 10, 24.
  - D8 (sign-in, run sheet): Tasks 14, 18, 24.
  - D10 (permissions): Tasks 13, 16.
  - D11 (chips, Bypass, remembered choices): Tasks 10, 21.
  - D12 (undo and its cleanup in the UI): Tasks 11, 20, 24; the git work is V2-1a's.
- **D13–D18:**
  - D13 (status): Tasks 4, 10.
  - D14 (restore): Tasks 6, 17.
  - D15 (history): Task 26.
  - D16 (composer): Tasks 15, 27, 28, 29.
  - D17 (packages): Tasks 1, 12, 13, 25.
  - D18 (Changes and Files): Tasks 20, 25.
- **D19–D23:**
  - D19 (CLI): Task 7.
  - D20 (privacy): Global Constraints; `toString()` is `'…'` on the desktop's own types; Task 30's greps.
  - D21 (naming, switch): Tasks 8, 10, 17 (off stops a running Claude), 30.
  - D22 (questions): Task 22.
  - D23 (agent list, default): Tasks 10, 24.
- **§4:**
  - §4.1: Tasks 12–17, 20, 25. §4.2: Tasks 12–14, 25. §4.3: Task 16. §4.4: Tasks 20, 25. §4.5: Task 14. §4.6: Task 2.
  - §4.7: Tasks 3–7. In `user_commands.dart` an AI pane has no terminal, so a user command answers `noTerminal` with its existing notice; that row's "use the AI session's folder" applies to `inherit` (Task 3).
- **§5:** Tasks 18 (output never read), 21 (the Bypass note), 11 and 24 (retention, delete), 22 (URLs), 30 (greps).
- **§6:** V2-1a, plus Tasks 11 (quit, crash), 14 (cards), 15 (force stop), 17 (folder gone), 20 ("changed after the turn", outside the folder) and 24 ("Error").
- **§7–§12:** the desktop tests of §7 are in Tasks 5, 6, 8, 9, 13, 15, 16, 18, 22 and 23. §8 maps to the Review Focus above. §9 is Task 30. §12.3 is Task 1.

**Left out, and why:**
- The phone (V2-2), and what spec §10 puts out of scope.
- More than the first page of `session/list`: History shows the agent's first page, which holds its recent sessions. Paging can come with V2-2's history.
- Image drag-and-drop, Telex, VoiceOver and Narrator cannot be driven from a widget test. They are Task 30's manual checks.

**Placeholder scan:**
- No TBD or TODO, and no "similar to Task N".
- Every new file is given whole; every change is an exact replacement.
- The only blanks are Task 30's ledger fields, which record what its Steps 1–3 print.

**Names against V2-1a.** Every V2-1a name used here appears in V2-1a's Interfaces blocks (Tasks 5–9):
- `AiRuntime`: constructor; `start`, `restart`, `retry`, `dispose`, `authenticate`, `loginCommand`; `send`, `cancel`, `forceStop`, `answerPermission`, `answerAsk`; `setConfig`, `setMode`, `listSessions`; `checkpointOf`, `changesSince`, `sessionChanges`, `changedAfterTurn`, `revert`, `revertSession`, `fileBefore`; `stderrTail`, `onStatus`.
- `AiHost` (`running:`, `killTree:`, `runtime`, `startup`), `RunningAgents(file, killPid:)`, `RunningRecord`, `KillTree`.
- `AgentCommand.withArgs` and `workingDirectory`, the four readiness classes, `Checkpoints`, `CheckpointStores.deleteAll`.
- `FakeLauncher` and `FakeAgentChannel` (`channels`, `stopCalls`, `killCalls`, `exited`).
- `AiHost`'s `env`, `resolver`, `checkpoints` and `running` are read as fields: V2-1a's code declares them public `final` fields.

**How the plan itself was checked** (a scratch copy of the workspace, with V2-1a's package taken from its plan):
- **Red, then green:** every task's test was seen failing as its Step 2 says, then passing.
- **Text against code:** a script applied this plan's own text for Tasks 10–30 (new files and exact replacements) to the Task 9 tree and reproduced the verified tree file for file. The only differences are blank lines, which each task's `dart format` step removes. Tasks 1–9 match the same way, except for their scripted steps (the ARB blocks, the `!` scripts, the frozen V1 parser).
- **The finished tree:** `flutter analyze` prints `No issues found!`; `flutter test` passes 3 248 tests, 10 skipped.

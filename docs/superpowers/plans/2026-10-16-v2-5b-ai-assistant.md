# ShellX V2-5b — "Trợ lý AI" (AI Assistant) like the Claude desktop app, with a project picker — Implementation Plan

Status: compact plan (detail level per `SCRATCH/v25-research/compact-plan-rules.md`): every task has Files, Interfaces, Tests, Implementation notes, Commands and a commit message; complete code only for the protocol, capability gating, the history lister and the mode state machine, and the binding safety rules.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. ⚠ tasks (protocol, security, native, state machines) are done with opus.

**Goal:** On the desktop the sidebar switches between **Terminal** and **Trợ lý AI**; the AI mode starts every session the Claude-desktop way (project first, a centred composer card with project · agent · mode · model chips, the first message creates the session), lists sessions by project with "Phiên trước" from the agent's `session/list {cwd}`, and restyles the session page. On the phone a bottom bar (Máy tính · Trợ lý AI · Cài đặt) leads to an AI tab: machine chip → projects → sessions → a type-first new session. Two additive protocol pieces (`ai.folder.history`, `ai.open {text}`) behind feature words, old peers keep working.

**Architecture:**
- **Protocol (additive, `kAiProtocol` stays 2):** `AiFolderHistory` (`ai.folder.history`) and `AiOpen.text` in `shellx_core`; `AiFeature.folderHistory`/`openPrompt` and `AiFolderChoice.branch` in `shellx_ai`; the hub answers with the B17 page encoder; `MachineAi.folderHistory`/`open(text:)` in `shellx_client` gated by `can(...)`.
- **History lister (`shellx_ai/host`):** `AiHistoryLister` reuses a live runtime's client, else one list-only agent process per agent (≤ 2 app-wide, 60 s idle stop, never `session/new`/`authenticate`/prompt), shared by the desktop sidebar and `ai.folder.history`.
- **Desktop mode model:** `TerminalTabsState.mode` + `kNoTabShown = 0` keep "the tab shown" in `selectedId`, with invariant I-mode (`selected == null || selected.kind == mode`); the AI home is "AI mode, `selectedId == kNoTabShown`". New AI widgets: `AiSidebar`, `AiHomeView`, `AiComposerCard`, `AiProjectPicker`, restyled `AiHeader`/timeline. Folder data: `ai_recent_folders`, `ai_agent_options` (window-owned settings), `aiFolderBranchProvider` (`GitHeadReader`), `file_selector` 1.1.0 for "Mở thư mục…".
- **Phone:** `HomeRoute` (`AutoTabsRouter`, three tabs, still one root navigator), `AiHomeRoute`, `AiProjectRoute`, `AiNewSessionRoute`, `AiStartComposer`; the phone only sends listing keys (V2-2 D9).
- **Design (V2-5a):** every icon through `ShellxIcons` roles (B adds 12), A's components (`ShellxSegmented`, `ShellxChip`, `ShellxCard`, `showShellxMenu`, `ShellxBottomBar`, `ShellxWedge`, `ShellxGlass`, `shellxPrimaryButtonStyle()`, `AppButton`), A's type scale (`ShellxText.*` desktop, `AppTypography` phone); no fixed text width anywhere (T49).

**Tech Stack:** Dart 3.11.1 / Flutter 3.41.4 (`~/fvm/versions/3.41.4/bin`); new desktop deps `file_selector` 1.1.0, `file_selector_macos` 0.9.5+1, `file_selector_windows` 0.9.3+6 (exact pins, T26); Riverpod (desktop); signals + get_it + injectable + auto_route 11.1.0 + intl_utils (mobile, generated code committed); `fake_async` for timers.

**Spec (binding, Vietnamese):** `docs/superpowers/specs/2026-10-16-v2-5b-ai-assistant-design.md` — decisions T1–T49, §4.0 icon roles, §6 protocol and compatibility, §8 strings (EN/VI verbatim), §11 tests, §12 Review Focus, §13 manual checks, §14 order. Design names: V2-5a plan `docs/superpowers/plans/2026-10-16-v2-5a-name-and-design-system.md` (Tasks 1–4 written, 5–16 outlined) and V2-5a spec §7.4 (`ShellxIcons`). `SCRATCH` = `/private/tmp/claude-501/-Users-richard-Documents-helper-shellx/c68aea52-eaaf-4b45-9a7d-989a8fedf901/scratchpad`.

## Prerequisite, branches and how this plan was made

- **Worktree and branch:** `.claude/worktrees/v2-5b`, branch `v2-5b`, made from `shellx-v2` **after V2-5a is merged** into it (B uses A's package, roles, components and type scale). **Never push** (a push to `main` releases the desktop app); the controller merges.
- **Split after the protocol step (spec §14):**
  - **Shared, on `v2-5b`:** Tasks 1–7 (pre-checks and icon roles, `shellx_core`, `shellx_ai`, `shellx_agent`, `shellx_client`).
  - **B-desktop:** branch `v2-5b-desktop` in `.claude/worktrees/v2-5b-desktop`, from `v2-5b` after Task 7: Tasks 8–20.
  - **B-phone:** branch `v2-5b-phone` in `.claude/worktrees/v2-5b-phone`, from `v2-5b` after Task 7: Tasks 21–25. V2-5c's overlap on the phone session page (T38, T39) runs after Tasks 24–25.
  - **Back on `v2-5b`:** merge `v2-5b-desktop` then `v2-5b-phone` (only the ARB files and the ledger can both change; take both sides), then Task 26.
  - Run sequentially on `v2-5b` instead if only one executor: the order 1 → 26 works as is.
- **Ledger:** `docs/superpowers/ledgers/v2-5b.md` (Task 1 creates it with the rulings below; each task appends its commits, counts and findings; each branch appends its own section).
- **Code read (2026-10-16):** `shellx-v2` `91b944b` (V2-2b, V2-3, V2-4 merged). V2-5a was not merged yet: its names come from its plan. **If a merged V2-5a name differs from the one used here, use the merged one and note it in the ledger** (P0).
- Symbol anchors below, not line numbers (the tree moves with V2-5a).

## Rulings (each with "cost if wrong")

Task 1 copies these into the ledger.

- **P0 — V2-5a names win.** Names from V2-5a's plan (`ShellxIcons`, `ShellxSegmented<T>`, `ShellxChip`, `ShellxCard`, `ShellxBottomBar`, `ShellxWedge`, `ShellxGlass(blur:)`, `shellxPrimaryButtonStyle()`, `ShellxText.display`, `AppColors.raised`, `AppButton`, `showShellxMenu`) are used as the plan states them; a merged name that differs is used instead, recorded in the ledger. *Cost if wrong:* a rename at the call site.
- **P1 — branch split as above** (spec §14 allows it). *Cost if wrong:* none; sequential execution is the same tasks.
- **P2 — the frozen V2-2b decoder** is a copy of `packages/shellx_core/lib/src/protocol/{messages,ai_messages}.dart` at `91b944b` (`ai_messages.dart` last changed in `a7c65683`, V2-2b B1/B2/B4), saved as `test/protocol/frozen/messages_v2b.dart` and `messages_v2b_ai.dart` (the V2-2a pair `messages_v2.dart`/`messages_v2_ai.dart` at `d8ad686` exists). Ledger records the hash. *Cost if wrong:* none.
- **P3 — `ai.open` with both `text` and `resume` is `refused`, no tab.** Spec silent; the phone never builds it (a resumed session is opened, then typed into). *Cost if wrong:* a later "resume and say" needs its own feature word.
- **P4 — `MachineAi.open(agent, folder, {String? text})`; resume stays `MachineAi.resume(...)`** (the B17 method). Spec §6.1 writes one `open(..., {resume, text})`; two methods avoid churning B17 callers. *Cost if wrong:* none.
- **P5 — the lister launches through `AiHost.launch`** (the `AgentLauncher` that writes `ai/running.json`, spec §6 crash sweep). The lister takes an `AgentLauncher`; the desktop passes `aiHost.launch`; a desktop test pins the wiring; package tests use `FakeLauncher`. *Cost if wrong:* none.
- **P6 — a third agent while two list processes live:** the least recently used idle process stops first; when both are mid-request the third waits (FIFO) for one to finish. *Cost if wrong:* that list waits up to one `session/list` (≤ 15 s).
- **P7 — "needs login" for the lister** is `JsonRpcError.code == -32000` from `initialize` or `session/list`, or a readiness that is not `AgentReady` (checked before launching anything) → `AiListNotReady`. No login card is ever opened by it. *Cost if wrong:* an agent with another auth code shows "Chưa tải được…" instead of "…khi {agent} đã sẵn sàng".
- **P8 — mode lives in `TerminalTabsState.mode`** next to `selectedId`, so mode and selection change in one `_set`: I-mode can never be observed broken by a listener. *Cost if wrong:* none (one more field).
- **P9 — navigation order:** a new `tabNavigationProvider` (`Provider<List<int> Function()?>`, registered by the visible sidebar like `closeSuccessorProvider`) gives ⌘1–9 / Ctrl+Tab their ids; without one, `state.tabs` of the shown mode's kind. *Cost if wrong:* ⌘1–9 in sidebar order only while the sidebar is built (it always is).
- **P10 — `AiAgentOptions.fromJson` filters again** (a hand-edited or older line with a no-approval value never reaches a chip), besides the filter at write time; the chip writes through the existing `rememberConfig`, which refuses such values too. *Cost if wrong:* none.
- **P11 — phone keys `settings_ai_machine` and `settings_ai_last_folder` live in `AppSettings`** (secure storage, like `settings_last_machine`). *Cost if wrong:* none.
- **P12 — the listing's `branch` comes from the window's branch cache only** (`aiFolderBranchProvider`'s last value); building a listing never waits for a git read. A miss starts a read; its result re-sends the listing through `changes`. *Cost if wrong:* the first listing after start may lack a branch for ≤ 1 s.
- **P13 — `ai.folder.history` paging** uses the hub's own `shellx-rest-<n>` cursor per phone, keyed by `(folder, agent)` in a new `_Phone.folderHistoryRest` (B17's `historyRest` is keyed by `sid`). A cursor of the hub's it does not hold now is `refused`. *Cost if wrong:* none.
- **P14 — the phone's `SettingsRoute` becomes tab 3 of `HomeRoute`;** any code that pushed it now selects tab 3 (`context.router.root.navigate(HomeRoute(children: [SettingsRoute()]))`). `DeleteAccountRoute` stays a root push. *Cost if wrong:* a stale push compiles but shows Settings twice; caught by the route test.
- **P15 — desktop 🎙 hidden:** `AiComposerCard(voiceSlot: null)` on the desktop; the phone passes its mic and the reserved `voiceMode` slot (T41). *Cost if wrong:* none.
- **P16 — Windows build of `file_selector`:** the executor builds macOS only (in a throw-away worktree, no launch); Windows is checked by `pub get` resolution plus manual check 2 (§13), recorded pending in the ledger. *Cost if wrong:* a Windows build break surfaces on the teammate's Windows CI; the fallback is spec §15 (lower the platform package, 0.9.4+x).
- **P17 — commit scope `v2-ai`** (the V2 AI scope). *Cost if wrong:* none.
- **P18 — a sealed-class arm lands with the type:** adding `AiFolderHistory` breaks the exhaustive switches in `shellx_agent` (`_towardsPhone`, the hub's `handle`); Task 2 adds the minimal arms (direction false, `unavailable`, `_ridOf`, hub `_refuse`) so every package stays green, Task 6 replaces the hub arm. *Cost if wrong:* none.

## Global Constraints

(Copied from the V2-5a plan header, adapted to V2-5b; then the spec's own.)

- **Branch and scope:**
  - Worktree `.claude/worktrees/v2-5b`, branch `v2-5b` (from the integrated `shellx-v2` with V2-5a merged); split branches per "Prerequisite"; commit there, **never push, merge into `shellx-v2`/`main`, or force**.
  - B may change (spec header): `apps/desktop`, `apps/mobile`; `packages/shellx_core/lib/src/protocol/` (additions only); `packages/shellx_ai` (listing, `AiRuntime.listSessions` by folder, the history lister, the options cache); `packages/shellx_agent` (hub, `AiSessionSource`, mux arms); `packages/shellx_client`; `packages/shellx_design` **only** the 12 new roles of §4.0 in `ShellxIcons` and `icons_test.dart` (T48). **Never:** `relay/**`, `web/**`, `release/**`, `.github/**`, the session model (`AiSessionState`, `Timeline`), A's tokens, components and existing roles.
- **Tooling:**
  - Flutter only via `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter …`; Dart via `~/fvm/versions/3.41.4/bin/dart` (Flutter 3.41.4 / Dart 3.11.1). After a `pubspec.yaml` change: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter pub get` at the repo root.
  - `pubspec.lock` files are git-ignored and never added.
  - After a macOS desktop build in the worktree, revert only the `COCOAPODS:` line of `apps/desktop/macos/Podfile.lock`.
  - The mobile iOS `Podfile.lock` keeps `COCOAPODS: 1.16.2`; new pod lines are committed.
  - Mobile generated code: `PATH=~/fvm/versions/3.41.4/bin:$PATH dart run intl_utils:generate` then `PATH=~/fvm/versions/3.41.4/bin:$PATH dart format lib/shared/src/l10n.dart lib/shared/src/intl/messages_en.dart lib/shared/src/intl/messages_vi.dart`; routes, DI: `PATH=~/fvm/versions/3.41.4/bin:$PATH dart run build_runner build --delete-conflicting-outputs` in `apps/mobile`. Desktop strings: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n` in `apps/desktop`. Generated files are committed.
  - Format only the files a task touches (`dart format <files>`; mobile page width 120 from its `analysis_options.yaml`, everything else 80).
- **Every task that changes code ends green:** each touched package's analyze clean and tests passing, run from its directory:
  - `apps/desktop`, `apps/mobile`, `packages/shellx_design`: `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze` and `PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test` (the mobile analyze may show only the pre-existing `unnecessary_import` info in `test/features/terminal/ime_in_place_edit_test.dart`);
  - `packages/shellx_core`, `shellx_ai`, `shellx_agent`, `shellx_client`, `shellx_e2e`, `shellx_acp`: `~/fvm/versions/3.41.4/bin/dart analyze` and `~/fvm/versions/3.41.4/bin/dart test`.
  - Timing-sensitive pre-existing test: `packages/shellx_core/test/util/terminal_links_test.dart` "path performance" — rerun alone before suspecting a change.
- **Exact values come from the spec** (sizes, roles, glyphs, strings, copied verbatim in the tasks). Product naming: "Claude", never "Claude Code", in UI strings (T1). Vietnamese strings are the spec's, word for word; every new key exists in EN and VI.
- **Security and privacy:** ShellX never reads, stores or relays credentials; never `--hide-claude-auth`; no `SHELLX_*` variable in an agent's environment (the lister uses the runtime's env path); never auto-allow a permission request; **never remember, cache, list on the AI home or re-apply a no-approval mode** (`aiTurnsOnNoApproval`, `aiIsNoApprovalMode`; `_applyPreferred` keeps refusing `bypassPermissions`); the phone never picks a mode before a session exists. **The lister only lists** (never `session/new`, `session/load`, `authenticate`, a prompt; permission/elicitation handlers left unset, so they cancel/decline). **No content in logs** (paths, titles, message text, cursors): errors log `runtimeType` only. **`toString()` of every new message and record returns `Name(…)`**, pinned by a test (T46: `AiFolderHistory`, `AiRecentFolder`, `AiAgentOptions`, `AiFirstMessage`, `AiStart`, `AiHomeDraft`, `AiFolderGroup`, plus `AiListOutcome` subtypes).
- **Phone never browses folders (V2-2 D9, T40):** it sends only keys from the listing; the desktop re-checks the key on every `ai.open`/`ai.folder.history`; the phone never creates, renames or saves a project and has no path field.
- **Compatibility (T45):** `kAiProtocol` stays 2; decoding never drops a channel (a malformed message is `null`, JSON bodies read loosely); frozen V2-2a (`d8ad686`) and V2-2b (`91b944b`, P2) decoders read the new messages; frozen V1 (`164bba6`) and V2.0 (`d8ad686`) layout parsers read a `layout.json` with `mode` without `.bak`.
- **Design (T48, T49):** no `Icons.`/`CupertinoIcons.` outside `ShellxIcons` (A's raw-style guard baseline must not rise); B never sets a font size, weight or family, nor a fixed width on text (only max widths on frames: composer card 720, popover 380, bubble 80 % of the 760 column, sidebar 220); every one-line label ellipsizes with a tooltip or semantics label; paths cut in the middle, names/titles/branches at the end; counts, dots, icons and buttons never cut; each new screen has an overflow test (sidebar 220 px, smallest desktop window, phone 320 pt at 200 % text).
- **App launches:**
  - The desktop app is never launched on the user's real data. Any desktop launch uses V2-5a's isolated recipe (throw-away worktree, bundle id `pro.shellx.desktop.itest`, temporary `HOME` and `CFFIXED_USER_HOME`, own Keychain service). Never `flutter test -d macos` or `flutter run` in the worktree.
  - iOS simulator runs of a test harness are allowed (boot your own simulator and shut it down after). Real devices are manual checks for the user (§13).
  - Task 1's adapter probe runs the agent from the user's machine in a temporary directory pair; it never sends a prompt and never signs in.
- **Processes:** never `pkill`/`killall`; stop only processes you started, by PID.
- **Commits:** conventional messages (`feat(v2-ai): …`, `test(v2-ai): …`, `fix(v2-ai): …`, `docs(v2-ai): …`), at least one per task, each ending with the committing model's own trailer: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` or `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. ⚠ tasks are done with opus.

## Review Focus

Spec §12, each pinned by tests in the task that owns the code.

1. **A hidden tab treated as shown** (`kNoTabShown`, I-mode): ⌘W closes the covered terminal tab on the AI home; A12 swallows a notice; A4 marks read; a hidden AI tab's agent starts. Pinned by Task 8 (`mode_invariant_test.dart`, "nothing acts on a hidden tab") and Task 26's `selectedId` grep.
2. **First message lost or sent twice** (pane rebuilt, mode switched mid-way, `send` refused, phone loses the channel after `ai.open {text}`, the draft path to an old desktop). Pinned by Task 17 (`first_message_test.dart`, exactly once), Task 6 (`ai.open {text}` one `open`), Task 24 (never re-sent).
3. **Extra agent processes** (lister never stops, one per group, orphans). Pinned by Task 4 (limits, 60 s, `stopAll`, generation), Task 14 (opening a group launches nothing), Task 11 (quit calls `stopAll`).
4. **Old versions** (V2-2b daemon meets a new kind, old phone meets many folders, old `layout.json` parsers meet `mode`, old builds meet new `ai_*` keys). Pinned by Tasks 2, 3, 6, 9, 26.
5. **No-approval mode slips through a new path** (options cache stores a bypass `value`, home chip lists it, `rememberConfig` from the home, phone `ai.open`). Pinned by Task 5 (cache filter both ways), Task 16 (home chips never list it), Task 17 (`_applyPreferred` still refuses), Task 24 (no mode before a session).

## File Structure

| File | Responsibility | Task |
|---|---|---|
| Modify `apps/desktop/pubspec.yaml`; `packages/shellx_design/lib/src/icons.dart`, `test/icons_test.dart`; Create `docs/superpowers/ledgers/v2-5b.md`, `packages/shellx_ai/test/fixtures/claude_session_list_cwd.json` | pins, adapter probe, 12 icon roles, ledger | 1 |
| Modify `packages/shellx_core/lib/src/protocol/ai_messages.dart`; Create `test/protocol/ai_messages_v25b_test.dart`, `test/protocol/frozen/messages_v2b{,_ai}.dart`; Modify `packages/shellx_agent/lib/src/mux/mux_ai.dart`, `src/ai/{ai_endpoint,ai_phone_hub}.dart` (arms) | `ai.folder.history`, `ai.open {text}` | 2 |
| Modify `packages/shellx_ai/lib/src/remote/listing.dart`; Create `test/remote/listing_v25b_test.dart`, `test/remote/frozen/listing_v2b.dart` | feature words, `branch` | 3 |
| Modify `packages/shellx_ai/lib/src/host/ai_runtime.dart`; Create `lib/src/host/history_lister.dart`, `test/host/history_lister_test.dart` | list by folder, lister | 4 |
| Create `packages/shellx_ai/lib/src/host/agent_options.dart`, `test/host/agent_options_test.dart` | options cache codec | 5 |
| Modify `packages/shellx_agent/lib/src/ai/{ai_phone_hub,ai_phone_hub_requests}.dart`; Create `test/ai/ai_phone_hub_v25b_test.dart` | hub: folder history, open text | 6 |
| Modify `packages/shellx_client/lib/src/machine_ai.dart`; Create `test/machine_ai_v25b_test.dart` | client gating | 7 |
| Modify `apps/desktop/lib/src/terminal/terminal_tabs.dart`, `ui/terminal/terminal_pane.dart`, `cli/ui_command_handler.dart`, `ui/tools/tool_area.dart`; Create `test/terminal/mode_invariant_test.dart` | mode model, `kNoTabShown` | 8 |
| Modify `apps/desktop/lib/src/restore/restore_snapshot.dart`, restore writer/reader, `ai/ai_open.dart` (`firstTab`), onboarding; Create `test/restore/restore_mode_test.dart` | `mode` in `layout.json`, start mode | 9 |
| Modify `ui/terminal/session_sidebar.dart`, `config/keybind_actions.dart`, `config/settings_schema.dart`, `config/config_template.dart`, `ai/ai_open.dart`, command palette, ARBs | switch, ⌘⇧J, entries, renames | 10 |
| Create `apps/desktop/lib/src/ai/{ai_recent_folders,ai_folder_branch,ai_projects}.dart`; Modify `platform/settings_store.dart`, `ai/ai_paths.dart`, `test/agent/settings_ownership_test.dart` | recent folders, branches, keys | 11 |
| Create `ui/ai/ai_project_picker.dart`, `ai/ai_pick_folder.dart`; Modify `ui/ai/ai_folder_card.dart`, Settings › Projects page | picker, `file_selector`, save as project | 12 |
| Create `apps/desktop/lib/src/ai/ai_sidebar_model.dart` + test | groups, order, filter model | 13 |
| Create `ui/ai/ai_sidebar.dart`, `ui/ai/ai_session_row.dart`, `ai/ai_earlier.dart` + tests | AI sidebar widgets, earlier sessions | 14 |
| Create `ui/ai/ai_composer_card.dart`; Modify `ui/ai/ai_composer.dart` | shared composer card | 15 |
| Create `ui/ai/ai_home.dart`, `ai/ai_home_draft.dart`, `ai/ai_options_cache.dart` | AI home, chips, options cache store | 16 |
| Create `ai/ai_first_message.dart`; Modify `ai/ai_open.dart`, `ui/ai/ai_composer.dart` | first message, `start` | 17 |
| Modify `ui/ai/{ai_header,ai_timeline,ai_tool_card,ai_theme}.dart` | session page | 18 |
| Modify `ui/tools/tool_area.dart`, tool openers | dock by mode | 19 |
| Modify `apps/desktop/lib/src/ai/ai_phone.dart` | phone source: folders, `open(text)`, folder history | 20 |
| Modify `apps/mobile/lib/core/router/app_router.dart` (+ `.gr.dart`), `core/auth/session_enforcer.dart`, `features/notifications/presentation/notification_opener.dart`, `features/machines/...`; Create `features/home/presentation/pages/home_page.dart` | bottom bar, routes | 21 |
| Create `features/ai/presentation/pages/ai_home_page.dart`, `features/ai/domain/ai_folder_group.dart`, controller; Modify `core/settings/app_settings.dart` | AI tab | 22 |
| Create `features/ai/presentation/pages/ai_project_page.dart` + controller | project page | 23 |
| Create `features/ai/presentation/widgets/ai_start_composer.dart`, `pages/ai_new_session_page.dart`, controller; Delete `widgets/ai_new_session_sheet.dart` | type-first new session | 24 |
| Modify `features/ai/presentation/pages/ai_session_page.dart`, `widgets/{ai_dock,ai_timeline,ai_items}.dart` | phone session page | 25 |
| Modify `packages/shellx_e2e/test/...`; ledger | e2e, compat, final review | 26 |

---

### Task 1: ⚠ Pre-checks — `file_selector` pins, the Claude adapter's `session/list {cwd}`, the 12 icon roles, the ledger

**Branch:** `v2-5b` (shared).

**Files:**
- Modify `apps/desktop/pubspec.yaml` (dependencies, next to `webview_flutter: 4.14.1`): `file_selector: 1.1.0`, `file_selector_macos: 0.9.5+1`, `file_selector_windows: 0.9.3+6` (exact, no caret, T26).
- Modify `packages/shellx_design/lib/src/icons.dart` (`ShellxIcons`: 12 `static const IconData` roles + their `roles` map entries), `packages/shellx_design/test/icons_test.dart`.
- Create `packages/shellx_ai/test/fixtures/claude_session_list_cwd.json`, `docs/superpowers/ledgers/v2-5b.md`.

**Interfaces:**
- Consumes: V2-5a Task 8 `ShellxIcons` (`static const Map<String, IconData> roles`, 95 entries).
- Produces: `ShellxIcons.newSession`, `.filterRunning`, `.filterNeedsYou`, `.filterDone`, `.folder`, `.folderOpen`, `.saveProject`, `.branch`, `.copyPath`, `.remove`, `.computer`, `.commands` (`IconData`); a fixed fact for Task 4: `restartPerFolder` (`bool`, true only when the adapter ignores `cwd`).

**Tests first** (`packages/shellx_design/test/icons_test.dart`, extend A's):
- `V2-5b roles use the spec's glyphs`: `ShellxIcons.newSession == CupertinoIcons.plus`, `filterRunning == CupertinoIcons.play_fill`, `filterNeedsYou == CupertinoIcons.hand_raised_fill`, `filterDone == CupertinoIcons.checkmark`, `folder == CupertinoIcons.folder`, `folderOpen == CupertinoIcons.folder_open`, `saveProject == CupertinoIcons.folder_badge_plus`, `branch == CupertinoIcons.arrow_branch`, `copyPath == CupertinoIcons.doc_on_clipboard`, `remove == CupertinoIcons.xmark`, `computer == CupertinoIcons.desktopcomputer`, `commands == CupertinoIcons.slash_circle`.
- A's count test: `roles` has **107** entries (95 + 12) and still matches every `static const IconData` in `icons.dart`; all 12 new ones `fontPackage == 'cupertino_icons'`.

**Steps:**
- [ ] Add the three pins; `flutter pub get` at the root; `PATH=… flutter build macos --debug` in a throw-away worktree of `HEAD` (V2-3 Task 6 recipe; **no launch**); record "builds" + the resolved versions in the ledger. Windows: record "pending, manual check 2" (P16).
- [ ] **Adapter probe** (spec Task 1, R§15): with a scratch Dart script under `SCRATCH/v25b-probe/` (not committed) that uses `AiHost(supportDir: <temp>)`'s `resolver` + `env` for the built-in Claude `AgentSpec`, start the agent with `cwd: <temp>/A` (a `git init`-ed empty folder), `initialize`, then `session/list {cwd: <dir B>}` where B is a real folder the user already ran Claude in (ask the controller for one; never invent). Record in the fixture **only**: `listOffered` (bool), `sessionCount`, `allCwdEqualB` (bool), `nextCursorPresent` (bool) — no titles, ids or paths. Stop the process by PID through `AgentChannel.stop()`. Never `session/new`, never a prompt, never `authenticate`; a `-32000` answer is recorded as `needsLogin: true` and the probe ends.
- [ ] Ledger: `restartPerFolder = !allCwdEqualB` (Task 4 reads it).
- [ ] Add the 12 roles (alphabetic within B's block, with a `// V2-5b §4.0` comment) and to `roles`.

**Commands:** `cd packages/shellx_design && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`; `cd apps/desktop && PATH=… flutter analyze`.

**Commit:** `feat(v2-ai): V2-5b pre-checks — pin file_selector 1.1.0, the Claude adapter's session/list cwd probe, 12 ShellxIcons roles, ledger`

---

### Task 2: ⚠ `shellx_core` — `ai.folder.history` and `ai.open {text}` (T43, T44, T45)

**Branch:** `v2-5b`.

**Files:**
- Modify `packages/shellx_core/lib/src/protocol/ai_messages.dart` (`AiMessage._decode`, `AiOpen`, new `AiFolderHistory` after `AiFolder`; the `AiResult` doc gains `no_list`).
- Create `packages/shellx_core/test/protocol/ai_messages_v25b_test.dart`; `test/protocol/frozen/messages_v2b.dart`, `messages_v2b_ai.dart` (P2: `git show 91b944b:packages/shellx_core/lib/src/protocol/messages.dart` / `ai_messages.dart`, header `// Frozen copy of lib/src/protocol/… at 91b944b (V2-2b). Never edit.` + `// ignore_for_file: type=lint`, class names suffixed like the V2-2a pair does).
- Modify (P18 arms) `packages/shellx_agent/lib/src/mux/mux_ai.dart` (`_towardsPhone`), `packages/shellx_agent/lib/src/ai/ai_endpoint.dart` (`aiUnavailableReply`), `packages/shellx_agent/lib/src/ai/ai_phone_hub.dart` (`handle`, `_ridOf`).

**Interfaces:**
- Produces: `final class AiFolderHistory extends AiMessage {int rid; String folder; String agent; String? cursor}` (`type == 'ai.folder.history'`, `sid == null`); `AiOpen.text` (`String?`).

**Code (complete):**

```dart
// AiMessage._decode — replace the 'ai.open' arm and add one before `_ =>`:
    'ai.open' => AiOpen(
      rid: f.integer('rid'),
      agent: f.string('agent'),
      folder: f.string('folder'),
      resume: f.optionalString('resume'),
      text: f.optionalString('text'),
    ),
    // …
    'ai.folder.history' => AiFolderHistory(
      rid: f.integer('rid'),
      folder: f.string('folder'),
      agent: f.string('agent'),
      cursor: f.optionalString('cursor'),
    ),
```

```dart
/// Phone → desktop: a new AI session with [agent] in [folder] (a key from
/// the listing, never a path the phone made up). With [resume] (V2-2b B17)
/// it reopens that earlier session of the agent instead (an id `ai.history`
/// gave); an older desktop ignores it, so a phone sends it only to a window
/// that offers history. With [text] (V2-5b T44) the new session's first
/// message, at most [kAiMaxPromptBytes]: sent only to a window whose listing
/// names `open_prompt` (an older one would open the tab and drop it).
final class AiOpen extends AiMessage {
  const AiOpen({
    required this.rid,
    required this.agent,
    required this.folder,
    this.resume,
    this.text,
  });
  final int rid;
  final String agent;
  final String folder;
  final String? resume;
  final String? text;
  @override
  String? get sid => null;
  @override
  String get type => 'ai.open';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'rid': rid,
    'agent': agent,
    'folder': folder,
    'resume': ?resume,
    'text': ?text,
  };
}

/// Phone → desktop (V2-5b T43): a page of the earlier sessions of [agent] in
/// [folder] — a key from the listing (V2-2 D9), never a path — [cursor]: the
/// next page. Answered by `ai.result` whose body is an `AiHistoryPage`
/// without `current`, or `refused`, `not_ready`, `no_list`, `busy`,
/// `unavailable`. Sent only when the listing names `folder_history`.
final class AiFolderHistory extends AiMessage {
  const AiFolderHistory({
    required this.rid,
    required this.folder,
    required this.agent,
    this.cursor,
  });
  final int rid;
  final String folder;
  final String agent;
  final String? cursor;
  @override
  String? get sid => null;
  @override
  String get type => 'ai.folder.history';
  @override
  Map<String, Object?> toMap() => {
    't': type,
    'rid': rid,
    'folder': folder,
    'agent': agent,
    'cursor': ?cursor,
  };
}
```

`toString` comes from `AiMessage` (`'$runtimeType(…)'`): never the folder, agent, cursor or text.

```dart
// shellx_agent mux_ai.dart `_towardsPhone`: add to the `=> false` group
  AiFolderHistory() ||
// ai_endpoint.dart `aiUnavailableReply`: add to the rid group
  AiFolderHistory(:final rid) ||
// ai_phone_hub.dart `_ridOf`: add to the rid group
    AiFolderHistory(:final rid) ||
// ai_phone_hub.dart `handle` (placeholder until Task 6):
      case AiFolderHistory(:final rid):
        _refuse(mobileId, rid);
```

**Tests first** (`ai_messages_v25b_test.dart`):
- `ai.folder.history round-trips`: `AppMessage.fromMap(AiFolderHistory(rid: 7, folder: 'ws:abc', agent: 'claude', cursor: 'c-1').toMap())` is an `AiFolderHistory` with `rid 7`, `folder 'ws:abc'`, `agent 'claude'`, `cursor 'c-1'`, `sid null`; without cursor → `cursor == null` and the map has no `cursor` key.
- `a malformed ai.folder.history is skipped, never fatal`: maps missing `rid`, `folder` or `agent` (and `rid: 'x'`) → `AppMessage.fromMap(...) == null`, no throw; a batch `[bad, AiList()]` still yields the `AiList`.
- `toString hides the content`: `AiFolderHistory(...).toString() == 'AiFolderHistory(…)'`; `AiOpen(rid: 1, agent: 'claude', folder: 'ws:a', text: 'sửa nút đăng xuất').toString() == 'AiOpen(…)'` and does not contain `sửa`.
- `ai.open text round-trips`: text `'sửa nút đăng xuất'` survives; absent → `null`; `wire` keeps an unknown key (`'x': 1`).
- `the largest ai.open fits one sealed batch`: `text` of exactly `kAiMaxPromptBytes` (32 768 bytes, mixed ASCII + `ệ`) encodes into one batch ≤ `kMaxSealedBatchBytes`, as `ai_messages_v2b_test.dart` checks `ai.prompt`.
- `frozen V2-2b decoder reads the new messages`: through `messages_v2b.dart`, `ai.folder.history` → its `AiRaw` with `type 'ai.folder.history'`, `rid 7`; `ai.open {text}` → its `AiOpen` (no `text` field), and `wire` still holds `text`.
- `frozen V2-2a decoder skips them`: through `messages_v2.dart` both decode to `null` or an `AiOpen` without throwing; the rest of the batch decodes.

**Commands:** `cd packages/shellx_core && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test`; same in `packages/shellx_agent`, `packages/shellx_client`; `flutter analyze` in `apps/desktop`, `apps/mobile` (add an arm wherever the analyzer reports `non_exhaustive_switch_statement` — the hub/mux ones above are the known ones).

**Commit:** `feat(v2-ai): ai.folder.history and ai.open {text} — decoded loosely, Name(…) toString, frozen V2-2b decoder`

---

### Task 3: ⚠ `shellx_ai` listing — `folder_history`, `open_prompt`, `branch` (T42)

**Branch:** `v2-5b`.

**Files:** Modify `packages/shellx_ai/lib/src/remote/listing.dart` (`AiFeature`, `AiFolderChoice`, a `kAiBranchBytes` constant), export from `lib/remote.dart` if constants are exported there. Create `packages/shellx_ai/test/remote/listing_v25b_test.dart`, `test/remote/frozen/listing_v2b.dart` (copy of `lib/src/remote/listing.dart` at `91b944b`, imports pointed at `package:shellx_ai/src/remote/…`, classes suffixed `V2b`).

**Interfaces:** Produces `AiFeature.folderHistory = 'folder_history'`, `AiFeature.openPrompt = 'open_prompt'`, `AiFolderChoice.branch` (`String?`), `const int kAiBranchBytes = 200`.

**Code (complete):**

```dart
  // in AiFeature:
  /// `ai.folder.history`: a folder's earlier sessions (V2-5b T43).
  static const folderHistory = 'folder_history';

  /// `ai.open {text}`: a new session with its first message (V2-5b T44).
  static const openPrompt = 'open_prompt';
```

```dart
/// V2-5b T42: the longest branch a listing carries.
const int kAiBranchBytes = 200;

final class AiFolderChoice with Redacted {
  const AiFolderChoice({
    required this.key,
    required this.name,
    this.path,
    this.branch,
  });

  final String key;
  final String name;
  final String? path;

  /// V2-5b T42: the folder's git branch (a 7-character SHA when detached);
  /// null when it is no repository or not read yet. An older phone ignores it.
  final String? branch;

  static String? _sendableBranch(String? b) =>
      b == null || b.isEmpty || utf8Length(b) > kAiBranchBytes ? null : b;

  Map<String, Object?> toJson() => {
    'key': key,
    'name': clipText(name, _nameBytes),
    if (path != null) 'path': clipText(path!, _pathBytes),
    if (_sendableBranch(branch) case final b?) 'branch': b,
  };

  static AiFolderChoice? fromJson(Map<String, Object?> j) {
    final key = jString(j, 'key');
    if (key == null || key.isEmpty) return null;
    return AiFolderChoice(
      key: key,
      name: jString(j, 'name') ?? key,
      path: jString(j, 'path'),
      branch: _sendableBranch(jString(j, 'branch')),
    );
  }
}
```

(`jString` returns null for a non-string; the existing `_nameBytes`/`_pathBytes` stay.)

**Tests first** (`listing_v25b_test.dart`):
- `branch round-trips`: `AiFolderChoice(key: 'ws:abc', name: 'shop-web', path: '/Users/me/code/shop-web', branch: 'main')` → `toJson()['branch'] == 'main'` → `fromJson` gives `'main'`.
- `branch is read loosely`: `'branch': 7` → null; `''` → null; 201 bytes → null and not written by `toJson`; other fields intact.
- `the listing names the two new words`: `AiListing(features: {'folder_history', 'open_prompt'})` round-trips; spec §6.2's JSON example (verbatim) decodes with `folders[0].branch == 'main'`, `folders[1].branch == null`, `features.contains(AiFeature.folderHistory)`.
- `a V2-2b phone ignores the new keys`: the same JSON through `AiListingV2b.fromJson` (frozen) gives 2 folders with key/name/path and the 12 words of §6.2 as features, no throw.

**Commands:** `cd packages/shellx_ai && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test`.

**Commit:** `feat(v2-ai): listing words folder_history and open_prompt, a folder's branch read loosely`

---

### Task 4: ⚠ `shellx_ai` — `AiRuntime.listSessions(cwd:)` and `AiHistoryLister` (T14)

**Branch:** `v2-5b`.

**Files:** Modify `packages/shellx_ai/lib/src/host/ai_runtime.dart` (`listSessions`); Create `packages/shellx_ai/lib/src/host/history_lister.dart` (export from the host barrel next to `ai_runtime.dart`); Create `packages/shellx_ai/test/host/history_lister_test.dart`; extend `test/host/ai_runtime_test.dart`.

**Interfaces:**
- Consumes: `AgentLauncher`, `AgentChannel.stop()`, `AgentSpec`, `AgentReadiness`/`AgentReady.command`, `AcpClient`, `JsonRpcConnection`, `InitializeResult.capabilities.listSessions`, `ListSessionsResult`, `JsonRpcError.code`, `SerialQueue.run`, `AiRuntime.state.{phase,cwd,capabilities}`, Task 1's `restartPerFolder`.
- Produces: `AiRuntime.listSessions({String? cwd, String? cursor}) → Future<ListSessionsResult?>`; `sealed class AiListOutcome` with `AiListed(ListSessionsResult page)`, `AiListNotReady()`, `AiListUnsupported()`, `AiListFailed(Type? errorType)`; `final class AiHistoryLister` with `list(AgentSpec agent, String cwd, {String? cursor}) → Future<AiListOutcome>`, `stop(String agentId) → Future<void>`, `stopAll() → Future<void>`, `int get processCount` (`@visibleForTesting`).

**Code (complete):**

```dart
// ai_runtime.dart
  /// `session/list` (spec D15) — for [cwd] (V2-5b T14; default: this
  /// session's folder); null when not offered or the agent refused.
  Future<ListSessionsResult?> listSessions({
    String? cwd,
    String? cursor,
  }) async {
    final client = _client;
    if (client == null || !state.capabilities.listSessions) return null;
    try {
      return await client.listSessions(cwd: cwd ?? state.cwd, cursor: cursor);
    } on JsonRpcError {
      return null;
    } on ConnectionClosed {
      return null;
    }
  }
```

```dart
// history_lister.dart
import 'dart:async';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:shellx_acp/shellx_acp.dart';

import 'agent_catalog.dart';
import 'agent_process.dart';
import 'ai_runtime.dart';
import 'serial_queue.dart';

/// What [AiHistoryLister.list] found. [toString] never shows a session.
sealed class AiListOutcome {
  const AiListOutcome();
}

final class AiListed extends AiListOutcome {
  const AiListed(this.page);
  final ListSessionsResult page;
  @override
  String toString() => 'AiListed(…)';
}

/// Not installed, no Node, needs a sign-in (-32000), turned off meanwhile.
final class AiListNotReady extends AiListOutcome {
  const AiListNotReady();
  @override
  String toString() => 'AiListNotReady(…)';
}

/// The agent offers no `session/list` (`sessionCapabilities.list`).
final class AiListUnsupported extends AiListOutcome {
  const AiListUnsupported();
  @override
  String toString() => 'AiListUnsupported(…)';
}

/// Anything else; [errorType] is all a log may show.
final class AiListFailed extends AiListOutcome {
  const AiListFailed([this.errorType]);
  final Type? errorType;
  @override
  String toString() => 'AiListFailed(…)';
}

/// V2-5b T14: an agent's earlier sessions in a folder, without opening one.
/// A live runtime of the agent lends its client; else one list-only process
/// per agent (at most [maxProcesses] in all) that never makes, loads or
/// prompts a session, never signs in, and stops after [idle] without a
/// request, when its agent is turned off ([stop]) and at quit ([stopAll]).
final class AiHistoryLister {
  AiHistoryLister({
    required AgentLauncher launch,
    required Future<AgentReadiness> Function(AgentSpec agent) resolve,
    required this.clientVersion,
    required AiRuntime? Function(String agentId) liveRuntime,
    this.restartPerFolder = false,
    this.idle = const Duration(seconds: 60),
    this.initializeTimeout = const Duration(seconds: 30),
    this.listTimeout = const Duration(seconds: 15),
    this.maxProcesses = 2,
    DateTime Function()? now,
  }) : _launch = launch,
       _resolve = resolve,
       _liveRuntime = liveRuntime,
       _now = now ?? DateTime.now;

  final String clientVersion;

  /// Task 1: the adapter lists the folder it runs in, whatever `cwd` says.
  final bool restartPerFolder;
  final Duration idle;
  final Duration initializeTimeout;
  final Duration listTimeout;
  final int maxProcesses;

  final AgentLauncher _launch;
  final Future<AgentReadiness> Function(AgentSpec agent) _resolve;
  final AiRuntime? Function(String agentId) _liveRuntime;
  final DateTime Function() _now;

  final _queues = <String, SerialQueue>{};
  final _procs = <String, _ListerProcess>{};
  final _generation = <String, int>{};
  final _waiters = <Completer<void>>[];
  var _disposed = false;

  @visibleForTesting
  int get processCount => _procs.length;

  /// One request at a time per agent; requests of two agents run side by side.
  Future<AiListOutcome> list(
    AgentSpec agent,
    String cwd, {
    String? cursor,
  }) {
    final generation = _generation[agent.id] ?? 0;
    return _queues
        .putIfAbsent(agent.id, SerialQueue.new)
        .run(() => _list(agent, cwd, cursor, generation));
  }

  Future<AiListOutcome> _list(
    AgentSpec agent,
    String cwd,
    String? cursor,
    int generation,
  ) async {
    if (_disposed || (_generation[agent.id] ?? 0) != generation) {
      return const AiListNotReady(); // turned off while it waited
    }
    final live = _liveRuntime(agent.id);
    if (live != null &&
        (live.state.phase == AgentPhase.ready ||
            live.state.phase == AgentPhase.running) &&
        (!restartPerFolder || _same(live.state.cwd, cwd))) {
      if (!live.state.capabilities.listSessions) {
        return const AiListUnsupported();
      }
      final page = await live
          .listSessions(cwd: cwd, cursor: cursor)
          .timeout(listTimeout, onTimeout: () => null);
      return page == null ? const AiListFailed() : AiListed(page);
    }
    var proc = _procs[agent.id];
    if (proc != null && restartPerFolder && !_same(proc.cwd, cwd)) {
      await _stopProc(proc);
      proc = null;
    }
    if (proc == null) {
      final AgentReadiness readiness;
      try {
        readiness = await _resolve(agent);
      } on Object catch (e) {
        return AiListFailed(e.runtimeType);
      }
      if (readiness is! AgentReady) return const AiListNotReady();
      await _makeRoom();
      if (_disposed || (_generation[agent.id] ?? 0) != generation) {
        return const AiListNotReady();
      }
      try {
        proc = await _start(agent.id, cwd, readiness.command);
      } on JsonRpcError catch (e) {
        return e.code == -32000
            ? const AiListNotReady()
            : AiListFailed(e.runtimeType);
      } on Object catch (e) {
        return AiListFailed(e.runtimeType);
      }
    }
    final running = proc;
    running.idleTimer?.cancel();
    running.busy = true;
    try {
      if (!running.listOffered) return const AiListUnsupported();
      final page = await running.client
          .listSessions(cwd: cwd, cursor: cursor)
          .timeout(listTimeout);
      return AiListed(page);
    } on JsonRpcError catch (e) {
      return e.code == -32000
          ? const AiListNotReady()
          : AiListFailed(e.runtimeType);
    } on Object catch (e) {
      await _stopProc(running); // a hung or closed agent is not reused
      return AiListFailed(e.runtimeType);
    } finally {
      running
        ..busy = false
        ..lastUsed = _now();
      if (identical(_procs[agent.id], running) && !_disposed) {
        running.idleTimer = Timer(idle, () => unawaited(_stopProc(running)));
      }
      _wakeOne();
    }
  }

  Future<_ListerProcess> _start(
    String agentId,
    String cwd,
    AgentCommand command,
  ) async {
    final channel = await _launch(command, cwd: cwd);
    // No permission or elicitation handler: the client cancels / declines.
    final client = AcpClient(
      JsonRpcConnection(input: channel.stdout, output: channel.stdin),
    );
    final proc = _ListerProcess(agentId, cwd, channel, client, _now());
    _procs[agentId] = proc;
    unawaited(
      channel.exitCode.then((_) {
        proc.idleTimer?.cancel();
        if (identical(_procs[agentId], proc)) _procs.remove(agentId);
        _wakeOne();
      }).catchError((Object _) {}),
    );
    try {
      final init = await client
          .initialize(clientVersion: clientVersion)
          .timeout(initializeTimeout);
      proc.listOffered = init.capabilities.listSessions;
      return proc;
    } on Object {
      await _stopProc(proc);
      rethrow;
    }
  }

  /// P6: the least recently used idle process goes; with none idle, wait.
  Future<void> _makeRoom() async {
    while (!_disposed && _procs.length >= maxProcesses) {
      final idle = _procs.values.where((p) => !p.busy).toList()
        ..sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
      if (idle.isNotEmpty) {
        await _stopProc(idle.first);
        continue;
      }
      final turn = Completer<void>();
      _waiters.add(turn);
      await turn.future;
    }
  }

  void _wakeOne() {
    if (_waiters.isNotEmpty) _waiters.removeAt(0).complete();
  }

  Future<void> _stopProc(_ListerProcess proc) async {
    proc.idleTimer?.cancel();
    if (identical(_procs[proc.agentId], proc)) _procs.remove(proc.agentId);
    _wakeOne();
    try {
      await proc.channel.stop(); // close stdin, wait, kill the tree
    } on Object {
      // Already gone.
    }
  }

  /// The agent was turned off or removed: its process stops, its waiting
  /// requests answer [AiListNotReady].
  Future<void> stop(String agentId) async {
    _generation[agentId] = (_generation[agentId] ?? 0) + 1;
    final proc = _procs[agentId];
    if (proc != null) await _stopProc(proc);
  }

  /// At quit: every process stops; later calls answer [AiListNotReady].
  Future<void> stopAll() async {
    _disposed = true;
    for (final w in _waiters) {
      w.complete();
    }
    _waiters.clear();
    await Future.wait([for (final proc in [..._procs.values]) _stopProc(proc)]);
  }

  static bool _same(String? a, String b) =>
      a != null && p.canonicalize(a) == p.canonicalize(b);
}

final class _ListerProcess {
  _ListerProcess(this.agentId, this.cwd, this.channel, this.client, this.lastUsed);
  final String agentId;
  final String cwd;
  final AgentChannel channel;
  final AcpClient client;
  DateTime lastUsed;
  bool listOffered = false;
  bool busy = false;
  Timer? idleTimer;
}
```

(Check `AgentPhase` is imported from where `AiRuntime` gets it; `ConnectionClosed` from `shellx_acp`.)

**Tests first** (`history_lister_test.dart`, `FakeLauncher` + the `shellx_acp` fake agent, which records every method it receives; `fake_async` for time):
- `a ready runtime of the agent lends its client`: `liveRuntime` returns a runtime in phase `ready` → `list(claude, '/x')` is `AiListed`, `FakeLauncher` launched **nothing**, the runtime's fake agent got `session/list` with `cwd: '/x'`.
- `without one, a list-only process`: one launch with `cwd: '/x'`; the agent received exactly `['initialize', 'session/list']` — never `session/new`, `session/load`, `authenticate`, `session/prompt`.
- `one process per agent, two in all`: three agents → `processCount` never > 2; the third launch comes after the LRU idle one stopped (P6); two calls for one agent reuse one process and run one after the other (the second starts after the first's answer).
- `session/list over 15 s fails and the process goes`: the fake agent never answers → `AiListFailed` at 15 s, `processCount == 0`.
- `idle 60 s stops it`: after a list, elapse 59 s → still 1; 60 s → 0, `stop()` called on the channel.
- `-32000 is not ready`: from `session/list` → `AiListNotReady`; readiness `AgentNeedsNode` → `AiListNotReady` with no launch.
- `no list capability`: `initialize` without `sessionCapabilities.list` → `AiListUnsupported`.
- `stop(agent) answers waiting requests not ready`; `stopAll` stops every process and later `list` is `AiListNotReady`.
- `restartPerFolder: true restarts in the asked folder` (launch cwd `/y` after `/x`, still ≤ 1 for the agent); a live runtime in `/x` is not used for `/y`.
- `toString` of all four outcomes is `Name(…)` (`'AiListed(…)'`, …).
- `ai_runtime_test.dart`: `listSessions(cwd: '/other')` sends `cwd: '/other'`; without `cwd` sends `state.cwd`.

**Commands:** `cd packages/shellx_ai && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test`.

**Commit:** `feat(v2-ai): AiHistoryLister — a folder's earlier sessions from a live runtime or one list-only process per agent, stopped after 60 s`

---

### Task 5: ⚠ `shellx_ai` — the mode / model options cache codec (T21, Review Focus 5)

**Branch:** `v2-5b`.

**Files:** Create `packages/shellx_ai/lib/src/host/agent_options.dart` (export with the host barrel), `packages/shellx_ai/test/host/agent_options_test.dart`.

**Interfaces:**
- Consumes: `ConfigOption {id, name, kind, category, currentValue, choices}`, `ConfigChoice {value, name}`, `ConfigKind`, `aiTurnsOnNoApproval`, `aiIsNoApprovalMode`, `kAiConfigChoices` (40), `kAiConfigNameChars` (60).
- Produces: `final class AiCachedChoice {String v; String n}`, `final class AiCachedOption {String id; String name; String? cat; String kind; Object? value; List<AiCachedChoice> choices}`, `final class AiAgentOptions {String agent; List<AiCachedOption> options}` with `static AiAgentOptions? fromConfig(String agentId, List<ConfigOption> options)`, `Map<String, Object?> toJson()`, `static AiAgentOptions? fromJson(Object? j)`, `AiCachedOption? get mode`, `AiCachedOption? get model`, `toString() == 'AiAgentOptions(…)'`.

**Code (complete):**

```dart
import 'package:shellx_acp/shellx_acp.dart';

import '../remote/config_view.dart' show kAiConfigChoices, kAiConfigNameChars;
import '../remote/no_approval.dart';

String _clip(String s) {
  final r = s.runes;
  return r.length <= kAiConfigNameChars
      ? s
      : '${String.fromCharCodes(r.take(kAiConfigNameChars - 1))}…';
}

bool _isMode(String id, String? cat) => cat == 'mode' || id == 'mode';
bool _isModel(String id, String? cat) => cat == 'model' || id == 'model';

final class AiCachedChoice {
  const AiCachedChoice(this.v, this.n);
  final String v;
  final String n;
  Map<String, Object?> toJson() => {'v': v, 'n': n};
  @override
  String toString() => 'AiCachedChoice(…)';
}

final class AiCachedOption {
  const AiCachedOption({
    required this.id,
    required this.name,
    required this.cat,
    required this.kind,
    required this.choices,
    this.value,
  });
  final String id;
  final String name;
  final String? cat;
  final String kind; // 'select' only (T21 keeps mode and model)
  final Object? value;
  final List<AiCachedChoice> choices;

  /// Never a no-approval choice, never one as the value (T21, R6).
  static AiCachedOption? safe({
    required String id,
    required String name,
    required String? cat,
    required String kind,
    required Object? value,
    required Iterable<AiCachedChoice> choices,
  }) {
    if (kind != 'select' || !(_isMode(id, cat) || _isModel(id, cat))) {
      return null;
    }
    if (aiIsNoApprovalMode(id)) return null; // an option named like one
    final kept = <AiCachedChoice>[
      for (final c in choices)
        if (!aiTurnsOnNoApproval(configId: id, value: c.v))
          AiCachedChoice(c.v, _clip(c.n)),
    ].take(kAiConfigChoices).toList();
    if (kept.isEmpty) return null;
    final keepValue =
        value is String &&
        !aiTurnsOnNoApproval(configId: id, value: value) &&
        kept.any((c) => c.v == value);
    return AiCachedOption(
      id: id,
      name: _clip(name),
      cat: cat,
      kind: kind,
      value: keepValue ? value : null,
      choices: kept,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'cat': ?cat,
    'kind': kind,
    'value': ?value,
    'choices': [for (final c in choices) c.toJson()],
  };

  @override
  String toString() => 'AiCachedOption(…)';
}

/// V2-5b T21: the mode and model choices an agent offered last, so the AI
/// home can show them before the agent runs. Never holds a no-approval
/// mode, as a choice or as the value — written or read (P10).
final class AiAgentOptions {
  const AiAgentOptions({required this.agent, required this.options});
  final String agent;
  final List<AiCachedOption> options;

  AiCachedOption? get mode =>
      options.where((o) => _isMode(o.id, o.cat)).firstOrNull;
  AiCachedOption? get model =>
      options.where((o) => _isModel(o.id, o.cat)).firstOrNull;

  static AiAgentOptions? fromConfig(String agentId, List<ConfigOption> all) {
    final options = <AiCachedOption>[
      for (final o in all)
        if (o.kind == ConfigKind.select)
          ?AiCachedOption.safe(
            id: o.id,
            name: o.name,
            cat: o.category,
            kind: 'select',
            value: o.currentValue,
            choices: [for (final c in o.choices) AiCachedChoice(c.value, c.name)],
          ),
    ];
    return options.isEmpty ? null : AiAgentOptions(agent: agentId, options: options);
  }

  Map<String, Object?> toJson() => {
    'agent': agent,
    'options': [for (final o in options) o.toJson()],
  };

  static AiAgentOptions? fromJson(Object? j) {
    if (j is! Map<String, Object?>) return null;
    final agent = j['agent'];
    final list = j['options'];
    if (agent is! String || agent.isEmpty || list is! List<Object?>) return null;
    final options = <AiCachedOption>[];
    for (final o in list) {
      if (o is! Map<String, Object?>) continue;
      final id = o['id'], name = o['name'], kind = o['kind'], cat = o['cat'];
      final choices = o['choices'];
      if (id is! String || name is! String || kind is! String) continue;
      if (choices is! List<Object?>) continue;
      final option = AiCachedOption.safe(
        id: id,
        name: name,
        cat: cat is String ? cat : null,
        kind: kind,
        value: o['value'],
        choices: [
          for (final c in choices)
            if (c case {'v': final String v, 'n': final String n})
              AiCachedChoice(v, n),
        ],
      );
      if (option != null) options.add(option);
    }
    return options.isEmpty ? null : AiAgentOptions(agent: agent, options: options);
  }

  @override
  String toString() => 'AiAgentOptions(…)';
}
```

**Tests first** (`agent_options_test.dart`):
- `keeps mode and model only`: options `mode` (cat `mode`), `model` (cat `model`), `thought_level` (cat `thought_level`), a boolean → 2 kept.
- `round-trips`: `fromJson(jsonDecode(jsonEncode(x.toJson())))` equals field by field.
- `caps`: 50 choices → 40; a 70-character name → 60 runes ending `…`.
- `never a no-approval mode`: choices `default`, `acceptEdits`, `plan`, `bypassPermissions` with value `bypassPermissions` → choices without `bypassPermissions`, `value == null`; ids/values containing `yolo`, `full-access`, `dangerously-skip-permissions` dropped; an option **named** `yolo` dropped whole.
- `read filters too (P10)`: a hand-written JSON line with `value: 'bypassPermissions'` and that choice → neither survives `fromJson`.
- `malformed is null, never a throw`: `null`, `[]`, `{'agent': 1}`, choices `[1, {'v': 2}]`.
- `toString` is `'AiAgentOptions(…)'`, `'AiCachedOption(…)'`, `'AiCachedChoice(…)'`.

**Commands:** `cd packages/shellx_ai && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test`.

**Commit:** `feat(v2-ai): AiAgentOptions — the mode and model choices cached per agent, never a no-approval mode`

---

### Task 6: ⚠ `shellx_agent` — the hub answers `ai.folder.history` and `ai.open {text}` (T42–T45)

**Branch:** `v2-5b`.

**Files:** Modify `packages/shellx_agent/lib/src/ai/ai_phone_hub.dart` (`AiSessionSource.open` gains `text`, new `AiSessionSource.folderHistory`; `_offered` set; `handle` arm; `_open`; `_Phone.folderHistoryRest`), `ai_phone_hub_requests.dart` (new `_folderHistory`); every test fake implementing `AiSessionSource` (`packages/shellx_agent/test/**`, `packages/shellx_e2e/**`, `apps/desktop/lib/src/ai/ai_phone.dart` gets a stub returning `AiListNotReady()` until Task 20). Create `packages/shellx_agent/test/ai/ai_phone_hub_v25b_test.dart`; extend `test/mux/mux_ai_test.dart`.

**Interfaces:**
- Consumes: Task 2 messages, Task 3 words, Task 4 `AiListOutcome`, `encodeHistoryPage`, `kAiHistoryPage`, `kAiHistoryCursorBytes`, `kAiMaxPromptBytes`, `utf8Length`.
- Produces: `AiSessionSource.open(String agentId, String folderKey, {String? resume, String? text}) → Future<int?>`; `AiSessionSource.folderHistory(String agentId, String folderKey, {String? cursor}) → Future<AiListOutcome>`.

**Code (complete):**

```dart
// AiSessionSource (doc additions):
  /// … With [text] (V2-5b T44) the new session's first message, sent as the
  /// phone's ("Bạn · từ điện thoại", B24) and queued until the agent is
  /// ready; the folder goes to the window's recent folders.
  Future<int?> open(
    String agentId,
    String folderKey, {
    String? resume,
    String? text,
  });

  /// V2-5b T43: a page of [agentId]'s earlier sessions in folder [folderKey]
  /// (one of [folders]), through the window's history lister.
  Future<AiListOutcome> folderHistory(
    String agentId,
    String folderKey, {
    String? cursor,
  });
```

```dart
// _offered: add
    AiFeature.folderHistory,
    AiFeature.openPrompt,

// handle: replace the Task 2 placeholder
      case AiFolderHistory():
        unawaited(_folderHistory(mobileId, phone, message));

// _Phone:
  /// V2-5b P13: what this phone was not sent yet of a folder's history page
  /// longer than [kAiHistoryPage] (keyed by folder and agent, like
  /// [historyRest] by session).
  ({String folder, String agent, String cursor, List<SessionSummary> rest, String? next})?
  folderHistoryRest;
```

```dart
// _open: the text checks come before anything opens (T44, P3)
  Future<void> _open(String mobileId, _Phone phone, AiOpen o) async {
    int? paneId;
    var code = 'refused';
    try {
      final resume = o.resume;
      final text = o.text;
      final choice = _source.agents.where((a) => a.id == o.agent).firstOrNull;
      if (text != null && utf8Length(text) > kAiMaxPromptBytes) {
        code = 'too_large';
      } else if (text != null && (text.trim().isEmpty || resume != null)) {
        code = 'refused';
      } else if (choice != null &&
          choice.ready &&
          _source.folders.any((f) => f.key == o.folder) &&
          (resume == null ||
              (resume.isNotEmpty && utf8Length(resume) <= kAiAcpIdBytes))) {
        paneId = await _source.open(o.agent, o.folder, resume: resume, text: text);
        if (paneId != null) _rescan();
      }
    } on Object {
      paneId = null;
    }
    _send(
      mobileId,
      AiResult(
        rid: o.rid,
        ok: paneId != null,
        code: paneId == null ? code : null,
        sid: paneId == null ? null : sidOf(paneId),
      ),
      phone,
    );
  }
```

```dart
// ai_phone_hub_requests.dart
  /// V2-5b T43: a folder's earlier sessions for a phone. The key must be
  /// offered now (D9) and the agent known to the window; pages over
  /// [kAiHistoryPage] are split with the hub's own cursor (P13). One answer,
  /// to [phone] only.
  Future<void> _folderHistory(
    String mobileId,
    _Phone phone,
    AiFolderHistory h,
  ) async {
    _Reply reply;
    try {
      reply = await _folderHistoryReply(phone, h);
    } on Object {
      reply = const _Reply.refuse('refused'); // the window's code failed
    }
    _send(
      mobileId,
      AiResult(rid: h.rid, ok: reply.code == null, code: reply.code, body: reply.body),
      phone,
    );
  }

  Future<_Reply> _folderHistoryReply(_Phone phone, AiFolderHistory h) async {
    if (!_source.folders.any((f) => f.key == h.folder) ||
        !_source.agents.any((a) => a.id == h.agent)) {
      return const _Reply.refuse('refused');
    }
    final cursor = h.cursor;
    final held = phone.folderHistoryRest;
    final List<SessionSummary> sessions;
    final String? after;
    if (held != null &&
        held.folder == h.folder &&
        held.agent == h.agent &&
        held.cursor == cursor) {
      sessions = held.rest;
      after = held.next;
    } else {
      if (cursor != null &&
          (cursor.isEmpty ||
              utf8Length(cursor) > kAiHistoryCursorBytes ||
              cursor.startsWith(_historyRestPrefix))) {
        return const _Reply.refuse('refused');
      }
      switch (await _source.folderHistory(h.agent, h.folder, cursor: cursor)) {
        case AiListed(:final page):
          sessions = page.sessions;
          after = page.nextCursor;
        case AiListNotReady():
          return const _Reply.refuse('not_ready');
        case AiListUnsupported():
          return const _Reply.refuse('no_list');
        case AiListFailed():
          return const _Reply.refuse('refused');
      }
    }
    phone.folderHistoryRest = null;
    var next = after;
    if (sessions.length > kAiHistoryPage) {
      final mine = '$_historyRestPrefix${_nextHistoryRest++}';
      phone.folderHistoryRest = (
        folder: h.folder,
        agent: h.agent,
        cursor: mine,
        rest: sessions.sublist(kAiHistoryPage),
        next: after,
      );
      next = mine;
    }
    return _Reply.ok(
      encodeHistoryPage(
        ListSessionsResult(
          sessions: sessions.take(kAiHistoryPage).toList(),
          nextCursor: next,
        ),
      ),
    );
  }
```

(The budget (`busy`) already applies: `_ridOf` has the arm from Task 2.)

**Tests first** (`ai_phone_hub_v25b_test.dart`, the plain-state fake source of the existing hub tests):
- `the listing names folder_history and open_prompt`.
- `folder history: an unknown key is refused` (`path:/etc`), `an unknown agent is refused`; the source's `folderHistory` was never called.
- `not_ready`, `no_list`, `refused` map from `AiListNotReady`, `AiListUnsupported`, `AiListFailed`.
- `a 120-session page is split by the hub's cursor`: first body 50 sessions + `next` starting `shellx-rest-`; asking that cursor gives the next 50 without calling the source again; a stale `shellx-rest-9` → `refused`; the body has no `current`.
- `busy`: 61 `ai.folder.history` at once → the 61st answers `busy`.
- `ai.open text`: `'   '` → `refused`, `open` not called; 32 769 bytes → `too_large`, not called; `text` + `resume` → `refused`, not called (P3); `'sửa nút đăng xuất'` → `open(agent, folder, text: 'sửa nút đăng xuất')` called **exactly once**, result has `sid`.
- `unavailable`: `aiUnavailableReply(AiFolderHistory(rid: 3, …))` → `AiResult(rid: 3, ok: false, code: 'unavailable')`.
- `mux_ai_test.dart`: `ai.folder.history` from a phone is never sent towards a phone; a V2-2b daemon fake that reads it as `AiRaw` passes the wire map on unchanged (keys `folder`, `agent`, `cursor` intact) and `ai.open` with `text` keeps `text` in `wire`.

**Commands:** `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test`; `packages/shellx_e2e` and `apps/desktop` analyze (fakes compile).

**Commit:** `feat(v2-ai): the hub answers ai.folder.history and ai.open {text} — keys checked, pages split, text checked before a tab opens`

---

### Task 7: ⚠ `shellx_client` — `folderHistory` and `open(text:)` gated by the listing (T38, T43, T44)

**Branch:** `v2-5b` (the split point: B-desktop and B-phone branch from here).

**Files:** Modify `packages/shellx_client/lib/src/machine_ai.dart` (`open`, new `folderHistory`); Create `packages/shellx_client/test/machine_ai_v25b_test.dart`.

**Interfaces:**
- Consumes: `MachineAi.can`, `_feature`, `_request`, `AiHistoryPage.fromJson`, `decodeBody`, Task 2/3.
- Produces: `MachineAi.open(String agent, String folder, {String? text}) → Future<String>` (throws `AiRequestException('unsupported')` **without sending** when `text != null && !can(AiFeature.openPrompt)`); `MachineAi.folderHistory(String agent, String folder, {String? cursor}) → Future<AiHistoryPage>` (`unsupported` at once when `!can(AiFeature.folderHistory)`).

**Code (complete):**

```dart
  /// A new session; its sid. With [text] (V2-5b T44) its first message goes
  /// with it — only to a computer whose listing names `open_prompt`: else
  /// this throws `unsupported` at once, sending nothing, and the caller
  /// keeps the text as a draft (T38). Never sent again on a lost channel.
  Future<String> open(String agent, String folder, {String? text}) async {
    final AiResult result;
    if (text == null) {
      result = await _request(
        null,
        (rid) => AiOpen(rid: rid, agent: agent, folder: folder),
      );
    } else {
      result = await _feature(
        AiFeature.openPrompt,
        null,
        (rid) => AiOpen(rid: rid, agent: agent, folder: folder, text: text),
      );
    }
    final sid = result.sid;
    if (sid == null) throw const AiRequestException('refused');
    return sid;
  }

  /// V2-5b T43: a page of [agent]'s earlier sessions in [folder] (a listing
  /// key, never a path: V2-2 D9). Throws [AiRequestException]: `unsupported`
  /// at once (nothing sent) when the computer cannot, `not_ready`,
  /// `no_list`, `refused`, `busy`, `unavailable`.
  Future<AiHistoryPage> folderHistory(
    String agent,
    String folder, {
    String? cursor,
  }) async {
    final result = await _feature(
      AiFeature.folderHistory,
      null,
      (rid) => AiFolderHistory(
        rid: rid,
        folder: folder,
        agent: agent,
        cursor: cursor,
      ),
    );
    return AiHistoryPage.fromJson(decodeBody(result.body) ?? const {});
  }
```

(`_feature` already throws `AiRequestException('unsupported')` without sending when `!can(feature)`.)

**Tests first** (`machine_ai_v25b_test.dart`, the client harness of `machine_ai_test.dart`):
- `folderHistory sends one ai.folder.history when the listing names it` (fields `folder 'ws:abc'`, `agent 'claude'`, `cursor null`), decodes the page (`sessions[0].acp`, `next`).
- `folderHistory is unsupported at once` with `f` lacking `folder_history`, and with protocol `ai: 1`: no frame sent.
- `open(text:) is gated`: listing without `open_prompt` → throws `unsupported`, **no frame**; with it → one `AiOpen` with `text`; `open` without text works on both.
- `codes reach the caller`: `no_list`, `not_ready`, `too_large` come back as `AiRequestException.code`.
- `a lost channel is not retried`: the channel drops after sending `ai.open {text}` → `MachineConnectionException` (or the existing outcome-unknown error), and the harness saw exactly one `ai.open`.

**Commands:** `cd packages/shellx_client && ~/fvm/versions/3.41.4/bin/dart analyze && ~/fvm/versions/3.41.4/bin/dart test`; `apps/mobile` analyze (callers of `open` still compile: positional args unchanged).

**Commit:** `feat(v2-ai): MachineAi.folderHistory and open(text:) — sent only when the computer's listing names the feature`

---

## B-desktop (branch `v2-5b-desktop`, Tasks 8–20)

All paths below are under `apps/desktop/` unless written from the repo root. Commands for every desktop task: `cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter gen-l10n` (when ARBs change) `&& PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`. Strings go to `lib/l10n/app_en.arb` and `app_vi.arb` in the task that first shows them (§8, verbatim).

### Task 8: ⚠ The mode model — `kNoTabShown`, `SidebarMode`, invariant I-mode (T2, T5, T9)

**Files:** Modify `lib/src/terminal/terminal_tabs.dart` (`TerminalTabsState`, `TerminalTabs.select/selectIndex/_step/_sync/_set`, `openAiTab`, `openTab`, new `setMode/toggleMode/showNone`, `tabNavigationProvider`), `lib/src/ui/terminal/terminal_pane.dart` (`IndexedStack` children `selected: false` when hidden; overlay slot), `lib/src/cli/ui_command_handler.dart` (`ui.ls`), `lib/src/ui/window_host.dart` (title reads `selected`). Create `test/terminal/mode_invariant_test.dart`, `test/terminal/hidden_tab_test.dart`.

**Interfaces:**
- Produces: `const int kNoTabShown = 0`; `enum SidebarMode { terminal, ai }`; `extension TerminalTabMode on TerminalTab { SidebarMode get mode }`; `TerminalTabsState.mode` (`SidebarMode`, default `terminal`); `TerminalTabs.setMode(SidebarMode)`, `toggleMode()`, `showNone()`; `final tabNavigationProvider = Provider<TabNavigation>(…)` with `List<int> Function()? order` (P9); `bool get showingHome` on the state (`mode == ai && selectedId == kNoTabShown`).

**Code (complete; adapt the private `_set` signature, keep every other `_set` caller):**

```dart
/// V2-5b T5: `selectedId` when nothing is on screen in the shown mode (the
/// AI home; Terminal mode with no terminal tab). Never a tab id: session
/// ids count from 1, synthetic ids are ≥ 2·10⁹, and [TerminalTabs.select]
/// never takes it.
const int kNoTabShown = 0;

enum SidebarMode { terminal, ai }

extension TerminalTabMode on TerminalTab {
  SidebarMode get mode => ai != null ? SidebarMode.ai : SidebarMode.terminal;
}

// TerminalTabsState: + `this.mode = SidebarMode.terminal`, `final SidebarMode mode;`
//   bool get showingHome => mode == SidebarMode.ai && selectedId == kNoTabShown;

// TerminalTabs (notifier) — the run's memory of each mode's tab (T5 b):
  int? _lastTerminal;
  int? _lastAi;

  /// Every new state goes through here: I-mode (`selected == null ||
  /// selected.mode == mode`) holds in every state anyone can read.
  void _apply(TerminalTabsState next) {
    final s = _normalize(next);
    if (s.selected case final t?) {
      if (t.mode == SidebarMode.ai) {
        _lastAi = t.id;
      } else {
        _lastTerminal = t.id;
      }
    }
    state = s;
  }

  /// T5 (c): a selection that broke I-mode without a deliberate choice
  /// (a successor on close, `_sync` filling the first tab) is replaced by
  /// rule (b). Terminal mode never sits on [kNoTabShown] while it has a
  /// terminal tab; AI mode does (the home).
  TerminalTabsState _normalize(TerminalTabsState s) {
    final shown = s.selected;
    if (shown != null && shown.mode == s.mode) return s;
    if (shown == null &&
        s.selectedId == kNoTabShown &&
        (s.mode == SidebarMode.ai ||
            !s.tabs.any((t) => t.mode == SidebarMode.terminal))) {
      return s;
    }
    return s.copyWith(selectedId: _ruleB(s.tabs, s.mode));
  }

  /// T5 (b): the mode's tab remembered in this run if it is still there;
  /// else Terminal: the first terminal tab in sidebar order, AI: the home.
  int _ruleB(List<TerminalTab> tabs, SidebarMode mode) {
    final last = mode == SidebarMode.ai ? _lastAi : _lastTerminal;
    if (last != null && tabs.any((t) => t.id == last && t.mode == mode)) {
      return last;
    }
    if (mode == SidebarMode.ai) return kNoTabShown;
    return _order(tabs, mode).firstOrNull ?? kNoTabShown;
  }

  /// P9: the visible sidebar's order, else the tab list, of [mode]'s kind.
  List<int> _order(List<TerminalTab> tabs, SidebarMode mode) {
    final ids = ref.read(tabNavigationProvider).order?.call() ??
        [for (final t in tabs) t.id];
    final kind = {for (final t in tabs) t.id: t.mode};
    return [for (final id in ids) if (kind[id] == mode) id];
  }

  /// T5 (a): a deliberate choice switches the mode to the tab's kind first.
  void select(int id) {
    if (id == kNoTabShown) return;
    final tab = _tab(id);
    if (tab == null) return;
    _restoreMaySelect = false;
    _apply(state.copyWith(mode: tab.mode, selectedId: id));
  }

  /// T5 (b) / T4: the other mode, on its remembered tab.
  void setMode(SidebarMode mode) {
    if (state.mode == mode) return;
    _apply(state.copyWith(mode: mode, selectedId: _ruleB(state.tabs, mode)));
  }

  void toggleMode() => setMode(
    state.mode == SidebarMode.ai ? SidebarMode.terminal : SidebarMode.ai,
  );

  /// T5: nothing on screen in this mode (the AI home). Tabs stay alive
  /// (`IndexedStack`) but none is drawn, focused or acted on.
  void showNone() => _apply(state.copyWith(selectedId: kNoTabShown));

  /// ⌘1…⌘9 (T9): the n-th row of the shown mode.
  void selectIndex(int position) {
    final ids = _order(state.tabs, state.mode);
    if (position >= 1 && position <= ids.length) select(ids[position - 1]);
  }

  /// Ctrl+Tab / Ctrl+Shift+Tab (T9): within the shown mode; from the AI
  /// home, forward goes to the first session.
  void _step(int delta) {
    final ids = _order(state.tabs, state.mode);
    if (ids.isEmpty) return;
    final i = ids.indexOf(state.selectedId ?? kNoTabShown);
    final next = i < 0 ? (delta > 0 ? 0 : ids.length - 1) : (i + delta) % ids.length;
    select(ids[next < 0 ? next + ids.length : next]);
  }

  // _sync keeps `state.selectedId ?? tabs.firstOrNull?.id` (T5 d) and goes
  // through _apply, so a first tab of the other kind is normalized.
```

Also: `openAiTab(select: true)` and the user's "new terminal tab" (`openTab`) end in `select(newId)`; `openAiTab(select: false)` (phone, restore) never changes `selectedId` or `mode`. `TerminalPane`: every `PaneTreeView` gets `selected: tab.id == state.selectedId` (false for 0) and the stack is covered by `AiHomeView` (Task 16; a placeholder `SizedBox` until then) when `state.showingHome`, by the A1 empty state when Terminal mode has `selected == null`. `ui.ls` writes `selectedTab: state.selected?.id` (null on the home) and `mode: 'terminal' | 'ai'`. `ToolArea` reads `state.selected` only (no `selectedId`).

**Tests first:**
- `mode_invariant_test.dart` (a `ProviderContainer` with fake sessions; after every action assert `selected == null || selected.mode == mode`): row tap on an AI tab from Terminal mode → AI mode; ⌘1–9 and Ctrl+Tab stay within the mode's ids; closing the shown AI tab whose successor is a terminal tab → the next AI tab or the home; `_sync` adding a first AI tab while in Terminal mode → stays Terminal on the first terminal tab or `kNoTabShown`; an A4 notice "go to tab" on a terminal tab from AI mode → Terminal; a CLI `ui.select` likewise; `setMode` back and forth returns to the remembered tab; remembered tab closed → rule (b); `select(kNoTabShown)` does nothing; restore selecting an AI tab → AI mode.
- `hidden_tab_test.dart` "nothing acts on a hidden tab": on the home (`kNoTabShown`) with a terminal and an AI tab alive: ⌘W, split, rename (F2), copy, close-pane, "Đóng tab" act on nothing; A12 `paneVisible` is false for every pane; A4 dwell does not mark read; `DesktopAiSource.seenOnDesktop(pane)` false; the window title is the app title; `ui.ls` gives `selectedTab: null`, `mode: 'ai'`; the hidden AI tab's runtime is not started by the pane.
- Existing tab tests stay green (default mode `terminal`, AI tabs created with `select: true` switch mode — update only assertions that expected an AI tab shown in Terminal mode).

**Commit:** `feat(v2-ai): Terminal and AI modes over one selection — kNoTabShown, invariant I-mode, navigation by mode`

---

### Task 9: The start mode — `mode` in `layout.json`, `new-tab-kind` as "Start in", onboarding (T6)

**Files:** Modify `lib/src/restore/restore_snapshot.dart` (`RestoreSnapshot.mode`, `toJson`, `tryParse`), the snapshot writer (where `selectedTab` is captured) and the restore apply path (calls `setMode` before `select`), `lib/src/ai/ai_open.dart` (`firstTab`/`ensureTab` by mode, T7), the onboarding step and the one-time intro card (they call `setMode` with the choice), Settings › General row label (`aiNewTabKindLabel`). Create `test/restore/restore_mode_test.dart`.

**Interfaces:** Produces `RestoreSnapshot.mode` (`String?`, only `'ai'` is written); `SidebarMode startupMode({required RestoreSnapshot? snapshot, required bool selectedIsAi, required String newTabKind})` in `lib/src/restore/restore_mode.dart`.

**Code (complete):**

```dart
// RestoreSnapshot: `this.mode` (ctor), `final String? mode;`
// toJson: after 'selectedTab':
    if (mode == 'ai') 'mode': 'ai', // a Terminal-mode layout stays byte-identical
// tryParse:
    mode: root['mode'] is String ? root['mode'] as String : null,

/// V2-5b T6: the mode a window opens in.
SidebarMode startupMode({
  required RestoreSnapshot? snapshot,
  required bool selectedIsAi,
  required String newTabKind,
}) {
  if (snapshot == null) {
    return newTabKind == 'ai' ? SidebarMode.ai : SidebarMode.terminal;
  }
  if (snapshot.mode == 'ai') return SidebarMode.ai;
  if (snapshot.mode == null && selectedIsAi) return SidebarMode.ai; // pre-V2-5b
  return SidebarMode.terminal;
}
```

After restore in AI mode with no AI tab selected → `showNone()`. `ensureTab` at start: Terminal mode with no terminal tab opens one (A1); AI mode opens nothing (home).

**Tests first** (`restore_mode_test.dart`):
- `mode round-trips` (`'ai'` written, Terminal mode has no `mode` key and the JSON equals the pre-V2-5b bytes for the same snapshot).
- `frozen V1 (164bba6) and V2.0 (d8ad686) parsers read a layout with mode` (`test/restore/v1/restore_snapshot_v1.dart`, `v2_0/…`): parse succeeds, no `.bak` rotation.
- `startupMode`: `mode: 'ai'` → ai; no `mode` + selected AI tab → ai; no `mode` + terminal → terminal; null snapshot → `new-tab-kind`; `mode: 'weird'` → terminal.
- `restored AI mode with the selected AI tab gone shows the home`.
- onboarding "Bạn muốn làm việc theo kiểu nào?" choice writes `new-tab-kind` **and** switches mode at once; the intro card likewise; Settings › Chung row reads "Mở ShellX ở chế độ" / "Start in" with options `aiNewTabKindTerminal` / `aiNewTabKindAi` ("Trợ lý AI" / "AI Assistant").

**Commit:** `feat(v2-ai): the window reopens in the mode it closed in — layout.json mode, new-tab-kind becomes "Start in"`

---

### Task 10: The mode switch, ⌘⇧J, entries by mode, the renames (T1, T3, T4, T7, T9)

**Files:** Modify `lib/src/ui/terminal/session_sidebar.dart` (switch under the top strip; Terminal mode lists no AI tab; counts and "no tab" hint count terminal tabs; registers `tabNavigationProvider` and `closeSuccessorProvider` for the shown mode), `lib/src/config/keybind_actions.dart` (`ActionSpec('toggle_ai_mode', ActionGroup.window)`, intent `ToggleAiModeIntent`, default ⌘⇧J / Ctrl+Shift+J), `lib/src/config/settings_schema.dart` (`new-tab-kind` search words `trợ lý ai`, `assistant`, `chế độ`, `mode`), `lib/src/config/config_template.dart` (§8.1's three lines verbatim), `lib/src/ai/ai_open.dart` (`AiOpener.newSession` → `showHome({String? folder, String? agentId})`; `new_tab` by mode), the command palette entries, the `+` menu, ARBs (§8.1 changed values, `aiModeTerminal`, `aiModeAssistant`, `aiModeSwitchLabel`, `aiModeNeedsYou`, `aiModeTerminalUnread`, `actionToggleAiMode`). Tests: `test/ui/terminal/mode_switch_test.dart`, `test/config/keybindings_test.dart` (extend), `test/l10n/ai_strings_test.dart` (extend).

**Interfaces:**
- Consumes: Task 8; V2-5a `ShellxSegmented<T>` (desktop, Task 9 of A).
- Produces: `AiOpener.showHome({String? folder, String? agentId})` (sets `aiHomeRequestProvider` then `setMode(ai)` + `showNone()`; focuses the home composer); `final aiHomeRequestProvider = StateProvider<AiHomeRequest?>`, `AiHomeRequest {String? folder; String? agentId; int serial}`.

**Implementation notes:**
- Switch (T3): `ShellxSegmented<SidebarMode>` full sidebar width, 8 px margins, 28 high, directly under the top strip; labels `aiModeTerminal` / `aiModeAssistant` (text only, no icon) cut with an ellipsis (T49); the unshown segment carries a count (AI: sessions in `needs_input`) or a dot (Terminal: a terminal tab with an unread A4 notice) that is never cut; Tab order ⚙ → 🔔 → + → switch → list; ←/→ switch; semantics "Chế độ: Trợ lý AI, đã chọn, 1 phiên AI cần bạn" (`aiModeSwitchLabel` + `aiModeAssistant` + `aiModeNeedsYou`).
- Entries (T7): ⌘T / `+` / empty-state button: Terminal → terminal tab (B8: SSH workspace opens its server); AI → `showHome()`. ⌘⇧E, palette "Phiên AI mới", Terminal-mode footer "Phiên AI mới", `+` menu "Phiên AI mới" → `showHome()` (no tab). "Tab terminal mới" → `setMode(terminal)` + new terminal tab. Workspace header `+` / "Tab mới trong workspace này" → terminal tab. `+` menu: Terminal mode drops "Tab terminal mới"; AI mode: "Phiên mới" (⌘T), "Mở thư mục…", "Tab terminal mới", "Kết nối SSH…", "Gắn tmux…".
- T1 renames: §8.1 values, including `aiSettingClaudeDesc` without "Claude Code".

**Tests first:**
- `mode_switch_test.dart`: ⌘⇧J flips the mode in one frame (`pump()` once); Terminal sidebar has no AI row; AI segment shows "1" when one AI session needs input; Terminal segment dot on an unread terminal notice; ←/→ change; semantics label exact; ⌘T in AI mode creates **no** tab and shows the home; ⌘⇧E likewise and focuses the composer; "Tab terminal mới" from AI mode → Terminal mode + one new terminal tab; the switch at 220 px with `textScaleFactor` 1.0 and long labels: no `RenderFlex overflowed`.
- `keybindings_test.dart`: `toggle_ai_mode` default `cmd+shift+j` (macOS) / `ctrl+shift+j` (Windows), resettable, in the A9 table; palette shows `actionToggleAiMode` "Chuyển Terminal / Trợ lý AI".
- `ai_strings_test.dart` "feature names say Claude": `aiSettingClaudeDesc` and every §8.1 value contain no "Claude Code"; "Giao diện AI" / "AI interface" appear in no ARB value.
- `config_template` test: the three lines of §8.1 verbatim.

**Commit:** `feat(v2-ai): the sidebar's Terminal | Trợ lý AI switch, ⌘⇧J, entries by mode, "Trợ lý AI" everywhere`

---

### Task 11: Folder data — recent folders, branches, the two window-owned keys (T11 paths, T25, T28, T23)

**Files:** Create `lib/src/ai/ai_recent_folders.dart`, `lib/src/ai/ai_folder_branch.dart`, `lib/src/ai/ai_projects.dart` (`aiWorkspaceForFolder`, `saveFolderAsProject`); Modify `lib/src/platform/settings_store.dart` (`SettingKeys.aiRecentFolders = 'ai_recent_folders'`, `SettingKeys.aiAgentOptions = 'ai_agent_options'`, both in `SettingKeys.all` and `UiSettingKeys`), `lib/src/ai/ai_paths.dart` (`aiSamePath`), the app's quit path (`aiHistoryListerProvider` `stopAll`, provider made here: `AiHistoryLister(launch: aiHost.launch, resolve: …, liveRuntime: …, restartPerFolder: <Task 1>)`), `test/agent/settings_ownership_test.dart`. Tests: `test/ai/ai_recent_folders_test.dart`, `test/ai/ai_folder_branch_test.dart`, `test/ai/ai_history_lister_wiring_test.dart`.

**Interfaces:**
- Produces: `final class AiRecentFolder {String path; DateTime at}` (`toJson` `{"p","at"}`, `fromJson`, `toString() == 'AiRecentFolder(…)'`); `final aiRecentFoldersProvider = NotifierProvider<AiRecentFolders, List<AiRecentFolder>>`; `AiRecentFolders.touch(String path)`, `.remove(String path)`, `.prune()`, `.seed(Iterable<String> cwds)`; `bool aiSamePath(String a, String b)`; `final aiFolderBranchProvider = Provider.family<String?, String>` backed by `AiFolderBranches` notifier (`refresh(String path)`, `refreshAll()`); `String aiWorkspaceForFolder(Ref|WidgetRef ref, String cwd)`; `Future<String?> saveFolderAsProject(WidgetRef ref, String path)`; `final aiHistoryListerProvider = Provider<AiHistoryLister>`.

**Code (complete — persisted format and caps):**

```dart
/// V2-5b T25: one recent folder ("p": normalized absolute path, "at": ms).
final class AiRecentFolder {
  const AiRecentFolder(this.path, this.at);
  final String path;
  final DateTime at;

  String toJson() => jsonEncode({'p': path, 'at': at.millisecondsSinceEpoch});

  static AiRecentFolder? fromJson(String line) {
    try {
      final j = jsonDecode(line);
      if (j case {'p': final String p, 'at': final int at} when p.isNotEmpty) {
        return AiRecentFolder(p, DateTime.fromMillisecondsSinceEpoch(at));
      }
    } on FormatException {
      // skipped
    }
    return null;
  }

  @override
  String toString() => 'AiRecentFolder(…)';
}

const int kAiRecentFolders = 20;
const int kAiRecentPathBytes = 1024;

/// T11: one folder, compared after normalizing; case-blind on Windows.
bool aiSamePath(String a, String b, {bool? isWindows}) {
  final win = isWindows ?? Platform.isWindows;
  final x = p.normalize(a), y = p.normalize(b);
  return win ? x.toLowerCase() == y.toLowerCase() : x == y;
}

// AiRecentFolders.touch(path): no-op when aiFolderIsBroad(path, home: …)
// or utf8.encode(path).length > kAiRecentPathBytes; else
//   [AiRecentFolder(p.normalize(path), now), ...rest where !aiSamePath]
//   .take(kAiRecentFolders), written as SettingKeys.aiRecentFolders strings.
```

**Implementation notes:**
- Writes (T25): on a send from the home (Task 17), the phone's `ai.open` (Task 20), reopening an earlier session (Task 14), choosing a folder for a tab (`AiFolderCard`, `ai.folder` B18, Task 12). Never on a chip choice alone; never a broad folder (`aiFolderIsBroad`, T23); never > 1 024 UTF-8 bytes.
- First run (key absent): `seed` from the restored AI tabs' `cwd` (existing, not broad), order kept.
- `prune()` (when the picker opens; when the AI sidebar shows, ≤ once per 60 s; at start after the first frame): ≤ 50 `Directory(p).exists()` per round, each `.timeout(2 s)`; `false` → removed; timeout/error → kept. Log only `runtimeType`.
- Branch (T28): `GitHeadReader` from `shellx_agent` (≤ 500 ms, LRU 64, `gitdir:` worktrees, 7-char SHA when detached), **never runs git**; a value older than 10 s is re-read when shown; `refreshAll()` on window focus; `refresh(cwd)` when a turn ends in that folder; timeout keeps the old value; no repo → null. `TerminalTab.gitBranch` of an AI tab stays null.
- `aiWorkspaceForFolder(cwd)` (T22): workspace whose `root` is `cwd` (local only, B8), else the workspace of an AI tab with that `cwd`, else Default.
- `saveFolderAsProject(path)` (T27): `createFor(name: basename)` → `setRoot(id, path)` → move every AI tab with `cwd == path` into it → toast `aiPickerSaved` ("Đã lưu “{name}” thành dự án."); returns the workspace id. Broad folders can be saved.
- The lister provider stops one agent when it is turned off or removed in Settings › Agents (`stop(id)`) and everything on quit (`stopAll()` in the same place runtimes stop).

**Tests first:**
- `ai_recent_folders_test.dart`: touch puts first; duplicate (and `C:\Code\x` vs `c:\code\x` with `isWindows: true`) moves to top; 21st drops the oldest; broad (`~`, `/`, `C:\`) and a 1 025-byte path not written; `seed` once; `prune` removes `false`, keeps timeout (fake `exists` that never completes, `fake_async` 2 s); `toString` `'AiRecentFolder(…)'`; malformed lines skipped.
- `settings_ownership_test.dart`: `_expectedUi` gains `ai_recent_folders`, `ai_agent_options` (comment `V2-5b T21, T25`); `hasLength(35)` → `hasLength(37)`.
- `ai_folder_branch_test.dart`: fake reader; 10 s staleness; focus refresh; turn-end refresh; timeout keeps old; detached SHA 7 chars.
- `ai_history_lister_wiring_test.dart`: the provider's launcher is `aiHost.launch` (P5); turning an agent off calls `stop(id)`; app quit calls `stopAll`.

**Commit:** `feat(v2-ai): recent AI folders, folder branches and the history lister for the window`

---

### Task 12: The project picker, "Mở thư mục…" with `file_selector`, "Lưu thành dự án", the folder card (T24, T26, T27, T29)

**Files:** Create `lib/src/ai/ai_pick_folder.dart` (`aiPickFolderProvider`), `lib/src/ui/ai/ai_project_picker.dart` (`AiProjectPicker`, `AiProjectPickerList`, `showAiProjectPicker`); Modify `lib/src/ui/ai/ai_folder_card.dart` (path field → `AiProjectPickerList`), the Settings › Dự án page (local project's "Thư mục dự án" gets a "Chọn…" button), ARBs (`aiPicker*`, `aiSidebarRemoveRecent`, `settingsProjectFolderPick`; remove `aiFolderField`, `aiFolderInvalid`, `aiFolderUse` when grep finds no use). Tests: `test/ui/ai/ai_project_picker_test.dart`, `test/ui/ai/ai_folder_card_test.dart` (rewrite).

**Interfaces:**
- Consumes: Task 11; `foldForSearch` (command palette); V2-5a `showShellxMenu` frame values; `ShellxIcons.search/folder/folderOpen/saveProject/remove/branch/warning`.
- Produces: `typedef AiPickFolder = Future<String?> Function({String? initialDirectory, required String confirmButtonText})`; `final aiPickFolderProvider = Provider<AiPickFolder>` (default: `file_selector.getDirectoryPath(initialDirectory:, confirmButtonText:, canCreateDirectories: true)`); `Future<String?> showAiProjectPicker(BuildContext context, {required Rect anchor})`; `AiProjectPickerList({required ValueChanged<String> onChosen, VoidCallback? onCancel})`.

**Implementation notes (T24, T26):**
- Popover: A's menu frame, width 380, max height 460, anchored to the chip; search field focused (`aiPickerSearch`), matches name and path, accent-blind via `foldForSearch`; sections `aiPickerProjects` (local workspaces with root; gone root: dimmed, `aiPickerGone`, link `aiPickerEditProject`), `aiPickerRecent` (recent not projects; hover: `saveProject` "Lưu thành dự án", `remove` "Bỏ khỏi Gần đây"), then a divider and `folderOpen` `aiPickerOpenFolder` with ⌘O / Ctrl+O. Typed absolute or `~/…` path of an existing directory → first row `aiPickerUsePath`. Row: name cut at end, path middle-cut (home as `~`), branch cut at end and hidden first (T49). Keys ↑/↓/Enter/Esc. Empty: `aiPickerEmpty`.
- `initialDirectory`: parent of the first recent, else home; `confirmButtonText: l10n.aiPickerChoose` ("Chọn"); cancel → nothing; error → toast `aiPickerDialogFailed`, log `runtimeType` only. No entitlement added (app not sandboxed, T26).
- Folder card (T29): title "Chọn thư mục dự án" and "Agent làm việc trong thư mục này." kept; choosing runs today's `_useFolder` then `touch`.

**Tests first:**
- picker: typing "shop" filters in one frame; "sua" finds "Sửa…"; typed `~/code/new-app` (fake fs exists) → "Dùng thư mục ~/code/new-app"; ↑/↓/Enter returns the path; Esc returns null; ⌘O calls the fake `aiPickFolderProvider` with `confirmButtonText: 'Chọn'`; cancel → null, nothing touched; throw → toast "Không mở được hộp chọn thư mục.", log line has no path; save-as-project creates the workspace, root, moves tabs, toast "Đã lưu “scratch” thành dự án."; 380 px with a 200-char path and a 100-char branch: no overflow.
- folder card: picks a recent → `_useFolder` semantics unchanged (other folder → new session; same → reopen) and `touch` called.
- Settings › Dự án "Chọn…" sets the root through the fake picker.

**Commit:** `feat(v2-ai): the project picker — search, projects, recent folders, Open folder… via file_selector, Save as project`

---

### Task 13: The AI sidebar model — groups, order, filters (T11, T12, T15, T16)

**Files:** Create `lib/src/ai/ai_sidebar_model.dart`, `test/ai/ai_sidebar_model_test.dart`.

**Interfaces:**
- Consumes: Task 11 (`aiSamePath`, recent list), tabs state, workspaces (`sidebarWorkspacesProvider`), `aiRemoteStateOf`, `aiLastEndedTurn`.
- Produces: `enum AiStatusFilter { running, needsYou, done }`; `AiStatusFilter? aiFilterOf(AiSessionState? s)`; `final class AiSidebarGroup {String path; String name; bool isProject; String? workspaceId; bool gone; List<int> openTabIds}`; `final class AiSidebarModel {List<AiSidebarGroup> projects; List<AiSidebarGroup> recent; List<int> noFolderTabIds; Map<AiStatusFilter, int> counts}`; `AiSidebarModel buildAiSidebarModel({required List<TerminalTab> aiTabs, required List<SidebarWorkspace> workspaces, required List<AiRecentFolder> recent, required AiSessionState? Function(int paneId) stateOf, required Set<String> goneRoots, bool? isWindows})`; `final aiSidebarModelProvider`.

**Implementation notes:** project = local workspace (no SSH) with `root`, in workspace order, shown even without sessions; `gone` when the last check found no root (T16); recent = folders of open AI tabs not projects + `ai_recent_folders` not projects, in recent order, open-tab folders not in it last; a session belongs to the group of its `cwd` (not its workspace); within a group open tabs by synthetic tab id **descending**; `noFolderTabIds` for AI tabs without `cwd`. Filters: running = `running`; needs you = `needs_input`; done = `idle` and `aiLastEndedTurn != null`; counts include custom agents.

**Tests first:** grouping (project vs recent; SSH workspace never a project; Windows case-blind match); order by id descending, stable when a state changes; recent order incl. open-tab folders last; gone root flagged; filter counts and `aiFilterOf` for each phase; a session in a sub-folder of a project lands in recent.

**Commit:** `feat(v2-ai): the AI sidebar's model — projects, recent folders, sessions by folder, status filters`

---

### Task 14: The AI sidebar — rows, groups, earlier sessions, filters, keys (T10, T12, T13, T15, T16, T17)

**Files:** Create `lib/src/ui/ai/ai_sidebar.dart` (`AiSidebar`), `lib/src/ui/ai/ai_session_row.dart` (`AiSessionRow`), `lib/src/ai/ai_earlier.dart` (`aiEarlierProvider`); Modify `lib/src/ui/terminal/session_sidebar.dart` (AI mode body = `AiSidebar`; no footer in AI mode); ARBs (`aiSidebar*`, `aiFilter*`, `aiRevealMac`, `aiRevealWindows`, `aiCopyPath`). Tests: `test/ui/ai/ai_sidebar_test.dart`, `test/ai/ai_earlier_test.dart`.

**Interfaces:**
- Consumes: Task 13 model, Task 11 lister/branches/recent, Task 10 `showHome`, `openAiTab(sessionId:)`, A's `ShellxChip` (filter selected state), `showShellxMenu`.
- Produces: `final aiEarlierProvider = NotifierProvider.family<AiEarlier, AiEarlierState, (String agentId, String path)>` with `load()`, `more()`; `sealed class AiEarlierState` (`idle`, `loading`, `loaded(List<SessionSummary>, String? next)`, `notReady`, `unsupported`, `failed`).

**Implementation notes:**
- Order top→bottom (T10): "+ Phiên mới" row (`newSession`, `aiSidebarNew`, ⌘⇧E hint hidden when it does not fit, highlighted on the home); filter row; `DỰ ÁN` (`aiSidebarProjects`); `GẦN ĐÂY` (`aiSidebarRecent`); "Chưa có thư mục" (`aiSidebarNoFolder`) when needed. Virtualized, lazy, row height as A2.
- Group head (T11): `chevronRight`/`expand`, `folder` (gone: `warning`, dimmed, `aiSidebarFolderGone`, no "+"), name (rest of width, cut at end), branch (≤ 40 % of row width, cut at end), warning dot when collapsed with a session needing you; hover replaces branch by `newSession` → `showHome(folder: path)` (tooltip `aiSidebarNewIn`). Default open when it has an open session or the shown one; open state per run.
- Up to 8 open sessions then `aiSidebarShowMore` (count); recent shows 8 groups then "Xem thêm {count}". Group without open sessions: `aiSidebarGroupEmpty` above the earlier row.
- Earlier row (T13): `history` + `aiSidebarEarlier` ("Phiên trước · {agent}") + "▾" to pick another agent of Settings › Agents (per group, per run). Agent = newest open session's agent in the group, else default. **Loads only when this row is opened**; 5 rows (title or `aiHistoryUntitled`, short date/time) then `aiSidebarMoreHistory` (+20, `nextCursor` when needed); drop ids equal to an open tab's `sessionId` with the same agent; cache 60 s per (agent, path); states `aiSidebarLoading`, `aiSidebarHistoryNeedsAgent`, `aiHistoryUnavailable`, `aiSidebarHistoryFailed` (tap retries). Tap a row → `openAiTab(agentId, cwd: path, sessionId: id, select: true)` + `touch(path)`.
- Filter row (T15): three icon+count buttons `filterRunning`/`filterNeedsYou`/`filterDone`, tooltip and semantics `aiFilterChipLabel`, selected = A's chip gradient, zero dimmed unless selected, tap again clears; while filtering: header `aiFilterHeader` + `aiFilterClear` (`remove`), flat list with line 2 "{state} · {agent} · {project}", no groups or earlier rows; empty texts `aiFilterNoneRunning`/`…NeedsYou`/`…Done`.
- Session row (T17): drawn status dot (needs you: warning colour; running: accent; done: ok; else dim) + title; line 2 "{state} · {agent}" as `session_tab_row.dart`'s AI row; both cut at end with a tooltip; A4 unread mark; tap → `select`; context menu "Đổi tên…" (`edit`), "Đóng phiên" (`remove`, confirm while a turn runs), `aiRevealMac`/`aiRevealWindows` (`folder`), `aiCopyPath` (`copyPath`); F2, ⌘W; no drag; semantics `aiSidebarRowLabel`.
- Keys (§4.1): ↑/↓ over every row, ←/→ collapse/expand, Enter, F2, Shift+F10/Menu; shares the Terminal sidebar's focus node and F6 region. Registers `tabNavigationProvider.order` = open AI rows top-down (no earlier rows, no heads) and the close successor while AI mode is shown (T9).
- Empty (T16): `aiSidebarEmpty` + `folderOpen` "Mở thư mục…" (opens the picker's OS dialog, then `showHome(folder:)`).

**Tests first:** opening a group launches nothing (fake lister: 0 calls); opening the earlier row calls `list(agent, path)` once; 5 rows then "Xem thêm"; duplicate of an open tab dropped; 60 s cache (fake clock: 59 s no call, 61 s one call); the four states' texts (VI exact); filter counts, flat list, empty texts, clear; group head hover "+" opens the home with that folder; gone root dimmed with "Không thấy thư mục"; context menu items and ⌘W confirm; overflow at 220 px with a 120-char project name, 80-char branch and 200-char title: no overflow, count/dot/icons intact; navigation ⌘1–9 follows AI rows.

**Commit:** `feat(v2-ai): the AI sidebar — projects and recent folders, sessions, earlier sessions on demand, status filters`

---

### Task 15: `AiComposerCard` — one composer card for the home and the session (T19, T41 desktop part)

**Files:** Create `lib/src/ui/ai/ai_composer_card.dart`; Modify `lib/src/ui/ai/ai_composer.dart` (the session composer renders inside the card; keys, IME, queue 5, `_Unchecked` unchanged). Tests: `test/ui/ai/ai_composer_card_test.dart`; existing composer tests stay green.

**Interfaces:**
- Consumes: V2-5a `ShellxCard` (radius 16), `ShellxGlass(blur: false)` on the session transcript (A29), `shellxPrimaryButtonStyle()`, `ShellxIcons.mention/commands/send/queue/stop/expand`.
- Produces: `AiComposerCard({required Widget field, List<Widget> images = const [], required List<Widget> chips, Widget? contextMeter, required Widget action, VoidCallback? onMention, VoidCallback? onCommands, bool commandsEnabled = true, String? commandsDisabledHint, Widget? voiceSlot, bool glass = false})`.

**Implementation notes:** top→bottom: images row; field (2 lines, grows to 140 px); control row inside the card: `@` (`mention`), `/` (`commands`, dimmed with tooltip `commandsDisabledHint` when disabled), chips, context % (session only), action (A's gradient primary; `send`/`queue`/`stop`). The control row is a `Wrap` that **wraps instead of overflowing**, with the action always last on the last line (T49). `voiceSlot` null on the desktop (P15). Text on glass only `textPrimary` and above.

**Tests first:** at the smallest window width with 4 chips of 40-char labels the row wraps, no overflow, Send is the last child of the last run; `/` dimmed shows `aiCommandsLater` tooltip; Enter / Shift+Enter / Esc and the queue keep their existing tests green inside the card; no `mic` icon on desktop.

**Commit:** `feat(v2-ai): AiComposerCard — the shared composer card with an in-card control row that wraps`

---

### Task 16: ⚠ The AI home — greeting, chips, the options cache store (T18, T20, T21, T23; Review Focus 5)

**Files:** Create `lib/src/ui/ai/ai_home.dart` (`AiHomeView`), `lib/src/ai/ai_home_draft.dart` (`AiHomeDraft`, `aiHomeDraftProvider`), `lib/src/ai/ai_options_cache.dart` (`AiOptionsCache`, `aiOptionsCacheProvider`); Modify `lib/src/ai/ai_runtimes.dart` (on `configOptions` from `session/new`, `session/load`, `config_option_update` → `AiOptionsCache.record(agentId, options)`), `lib/src/ui/terminal/terminal_pane.dart` (home overlay), ARBs (`aiHome*`, `aiChip*`, `aiNewWith`, `aiNewInThisProject`). Tests: `test/ui/ai/ai_home_test.dart`, `test/ai/ai_options_cache_test.dart`.

**Interfaces:**
- Consumes: Task 5 `AiAgentOptions`, Tasks 10–12, 15; `rememberedConfig`, `rememberConfig`; `aiAgentsProvider`, `aiDefaultAgentProvider`, agent readiness; `aiFolderIsBroad`; V2-5a `ShellxWedge`, `ShellxText.display`.
- Produces: `final class AiHomeDraft {String? folder; String? agentId; String text; List<AiImage> images; List<String> mentions}` (`toString() == 'AiHomeDraft(…)'`); `aiHomeDraftProvider` (`NotifierProvider`, in memory, kept across leaving/returning in a run, cleared on send); `AiOptionsCache.record(String agentId, List<ConfigOption> options)`, `AiAgentOptions? of(String agentId)`.

**Code (complete — the cache store, security-relevant):**

```dart
/// V2-5b T21: the AI home's mode / model chips before an agent runs.
/// Written when a runtime reports options that differ from the stored ones;
/// never a no-approval mode (Task 5 filters on write and on read).
final class AiOptionsCache {
  AiOptionsCache(this._store);
  final SettingsStore _store;

  AiAgentOptions? of(String agentId) {
    for (final line in _store.getStrings(SettingKeys.aiAgentOptions)) {
      try {
        final o = AiAgentOptions.fromJson(jsonDecode(line));
        if (o != null && o.agent == agentId) return o;
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  Future<void> record(String agentId, List<ConfigOption> options) async {
    final next = AiAgentOptions.fromConfig(agentId, options);
    if (next == null) return;
    final line = jsonEncode(next.toJson());
    final lines = _store.getStrings(SettingKeys.aiAgentOptions);
    final old = lines.where((l) {
      try {
        return AiAgentOptions.fromJson(jsonDecode(l))?.agent == agentId;
      } on FormatException {
        return false;
      }
    }).toList();
    if (old.length == 1 && old.single == line) return;
    await _store.setStrings(SettingKeys.aiAgentOptions, [
      for (final l in lines)
        if (!old.contains(l)) l,
      line,
    ]);
  }
}
```

**Implementation notes:**
- Layout (T18): centred column; greeting by the machine's hour (`aiHomeMorning` 05:00–11:59, `aiHomeAfternoon` 12:00–17:59, `aiHomeEvening` otherwise) in `ShellxText.display`; subtitle `aiHomeSubtitle` / `aiHomeSubtitleNoProject`; `ShellxWedge` behind, top right; `AiComposerCard` max 720 px; greeting + card around 40 % of the height; a note line under the card when needed (`aiHomeBroad` + `aiHomeChooseOther`, `aiHomeFolderGone`, `aiHomeNoAgent`, `aiHomeNeedsProject`). No suggestions, no session list. Focus in the field each time the home shows; Enter sends (dimmed Send: nothing); Esc closes an open chip menu only.
- Chips (T20): project (`folder` + name + branch, `expand`; branch hides first; picker of Task 12); preset order: (1) group folder from "+" / "Phiên mới trong dự án này", (2) the session's folder from "Phiên mới với…", (3) the folder of the AI session shown last this run, (4) first recent, (5) first project; skip broad and gone; none → `aiChipChooseProject`, Send dimmed. Agent chip (`ai` + name + `expand`): every agent of Settings › Agents with its state (Sẵn sàng / Chưa cài / Thiếu Node / Cần đăng nhập / Đang kiểm tra…), not-ready selectable, last item `aiMenuAgentsSettings`; default = default agent or the "Phiên mới với {agent}" one; **never changes the default agent**.
- Mode / model chips (T21): built from `AiOptionsCache.of(agent)`; shown value = `rememberedConfig(agent)[id]` when it is one of the choices, else the cache `value`; choosing → `rememberConfig(store, agent, id, value)` (refuses no-approval). No cache or legacy `modes` only → dimmed `aiChipMode` / `aiChipModel` with tooltip `aiChipLater`. **The home never lists a no-approval choice** (the cache cannot hold one; the menu also filters `aiTurnsOnNoApproval` defensively).
- Broad folder (T23): chip shows `warning`; note `aiHomeBroad`; still sendable.
- Draft: kept in memory per run (text, images, `@`, chips), cleared on send.

**Tests first:**
- `ai_options_cache_test.dart`: record → of; identical options do not rewrite; a `bypassPermissions` current value is never stored; a stored line edited to `bypassPermissions` is not returned (P10); other agents' lines kept.
- `ai_home_test.dart`: greeting at 08:00 / 13:00 / 22:00 / 04:59 (fake clock) — "Chào buổi sáng" / "Chào buổi chiều" / "Chào buổi tối" / "Chào buổi tối"; subtitle "Hôm nay Claude làm gì trong shop-web?"; preset order (each of the five steps; broad and gone skipped; none → "Chọn dự án", Send disabled); agent chip lists every agent with state and does not change the default; mode chip from the cache lists `default`, `acceptEdits`, `plan` and **not** `bypassPermissions` even when the cache JSON was hand-edited; choosing calls `rememberConfig`; no cache → dimmed with "Có sau lần đầu chạy Claude"; broad folder note text exact; draft survives `setMode(terminal)` → `setMode(ai)`; overflow at the smallest window and 720 px.

**Commit:** `feat(v2-ai): the AI home — greeting, project, agent, mode and model chips from a cache that never holds a no-approval mode`

---

### Task 17: ⚠ The first message creates the session — exactly once (T22; Review Focus 2)

**Files:** Create `lib/src/ai/ai_first_message.dart`; Modify `lib/src/ai/ai_open.dart` (`AiOpener.start(AiStart)`), `lib/src/ui/ai/ai_composer.dart` (takes the first message on first build), `lib/src/ui/ai/ai_home.dart` (Send). Tests: `test/ai/first_message_test.dart`.

**Interfaces:**
- Consumes: Tasks 8, 11, 16; `openAiTab`, `AiRuntimes.runtimeFor`, `AiRuntime.send`, `_Unchecked`, `aiProjectFilesProvider`.
- Produces: `final class AiFirstMessage {String text; List<AiImage> images; List<String> mentions}` (`toString() == 'AiFirstMessage(…)'`); `final class AiStart {String agentId; String cwd; AiFirstMessage message}` (`toString() == 'AiStart(…)'`); `final aiFirstMessagesProvider = Provider<AiFirstMessages>`; `AiFirstMessages.put(int paneId, AiFirstMessage m)`, `AiFirstMessage? take(int paneId)`, `void drop(int paneId)`; `Future<int?> AiOpener.start(AiStart start)`.

**Code (complete — the exactly-once hand-off):**

```dart
/// V2-5b T22: what the AI home's Send hands to the new pane. In memory only;
/// [take] removes it, so a rebuilt pane, a second composer or a mode switch
/// never sends it twice; a pane closed before its composer built drops it.
final class AiFirstMessages {
  final _byPane = <int, AiFirstMessage>{};

  void put(int paneId, AiFirstMessage message) => _byPane[paneId] = message;

  AiFirstMessage? take(int paneId) => _byPane.remove(paneId);

  void drop(int paneId) => _byPane.remove(paneId);
}

// AiOpener.start — checks first, nothing opens when one fails (§10):
  Future<int?> start(AiStart s) async {
    final agent = aiAgentById(_ref.read(aiAgentsProvider), s.agentId);
    if (agent == null) return null;
    if (!await Directory(s.cwd).exists()) return null; // note: aiHomeFolderGone
    if (s.message.text.trim().isEmpty && s.message.images.isEmpty) return null;
    await _ref.read(aiRecentFoldersProvider.notifier).touch(s.cwd);
    final tabs = _ref.read(terminalTabsProvider.notifier);
    final tabId = tabs.openAiTab(
      agentId: agent.id,
      agentName: agent.name,
      title: _ref.read(appL10nProvider).aiNewSession,
      cwd: s.cwd,
      workspace: aiWorkspaceForFolder(_ref, s.cwd),
      select: true, // AI mode, this tab shown (T5 a)
    );
    final paneId = _ref.read(terminalTabsProvider).tabs
        .where((t) => t.id == tabId).firstOrNull?.ai?.id;
    if (paneId == null) return null;
    _ref.read(aiFirstMessagesProvider).put(paneId, s.message);
    _ref.read(aiHomeDraftProvider.notifier).clear();
    return paneId;
  }

// AiComposer (session): in initState's first post-frame callback, once:
//   final first = ref.read(aiFirstMessagesProvider).take(paneId);
//   if (first != null) _restore(first) then _send();   // the normal path:
//   queued until ready; images through _Unchecked; `send` false → the text
//   and images stay in this composer with the note "Agent chưa nhận tin lúc
//   này." (aiCannotSend), never re-sent automatically.
// Pane close (TerminalTabs.close / closePane of an AI pane) calls drop(paneId).
```

**Implementation notes:** `@` on the home uses `aiProjectFilesProvider` for the chip's folder (no agent); `/` dimmed with `aiCommandsLater`, typed `/…` is sent as text. Mode/model from the home apply through `preferredConfig = rememberedConfig(agent)` before the first prompt (`_applyPreferred`, which still refuses `bypassPermissions`).

**Tests first** (`first_message_test.dart`, fake runtimes/agent):
- Send creates one tab in `aiWorkspaceForFolder`, AI mode, selected; the sidebar row appears under the right project in the same frame.
- The agent receives the text **exactly once**: rebuild the pane (`pumpWidget` twice), switch modes back and forth before ready, then ready → one `session/prompt`.
- Images before capabilities go through `_Unchecked`; an agent without images returns them to the composer.
- `send` false (login needed before the composer built) → text in the session composer with "Agent chưa nhận tin lúc này.", no prompt later without a tap.
- Pane closed before its composer built → nothing sent, `take` returns null.
- Folder gone at Send → no tab, note "Thư mục này không còn. Chọn thư mục khác."; no agent → no tab.
- Mode chosen on the home (`plan`) is applied before the first prompt; a stored `bypassPermissions` (planted in `ai_agent_config`) is not applied.
- Broad folder: sends, not written to Recent.
- `toString`: `'AiFirstMessage(…)'`, `'AiStart(…)'`, `'AiHomeDraft(…)'`.

**Commit:** `feat(v2-ai): the AI home's first message creates the session and reaches the agent exactly once`

---

### Task 18: The session page — header, bubbles, compact tool cards, folded thinking (T30–T33)

**Files:** Modify `lib/src/ui/ai/ai_header.dart` (`AiHeader`), `lib/src/ui/ai/ai_theme.dart` (header height), `lib/src/ui/ai/ai_timeline.dart` (user bubble, agent text, thinking line), `lib/src/ui/ai/ai_tool_card.dart` (one line, auto-open only while waiting for permission), the ⋯ menu (adds `aiHistory`); ARBs (`aiHeaderBranch`, `aiHeaderProject`). Tests: `test/ui/ai/ai_header_test.dart`, `test/ui/ai/ai_timeline_bubbles_test.dart`, update `ai_tool_card_test.dart` where T32 changes behaviour.

**Interfaces:** Consumes Tasks 10–12, 15; `aiFolderBranchProvider`, `aiStatusOf`, `saveFolderAsProject`, `showHome(folder:, agentId:)`; A's roles `sidePanel`, `terminal`, `tool`, `maximize`, `more`, `history`, `check`, kind roles.

**Implementation notes:**
- Header (T30): 40 px (more if A's line needs it); left→right: title (cut at end, tooltip); project chip (`folder` + name, tooltip = path; menu `aiNewInThisProject` (`newSession`), reveal (`folder`), `aiCopyPath` (`copyPath`), `aiPickerSaveProject` (`saveProject`) when not a project); branch (`branch` + name); agent chip (`ai` + name + `expand`; menu `aiNewWith` for every agent → `showHome(folder: cwd, agentId:)`, then `aiMenuAgentsSettings`); status (A12 with clock, live region). Right: `sidePanel`, `terminal`, `tool`, `maximize` (when > 1 pane), `more`. "Lịch sử phiên" moves into ⋯. Narrowing measured by real text width: status and right buttons never dropped; drop the branch first, then the project chip, when the title would be narrower than 12 characters of the current font (measure `'M' * 12` with the title style); the title tooltip still names project and branch.
- Timeline (T32): user message = right-aligned bubble, max 80 % of the 760 column, A's raised fill (`navy700`), no `BoxShadow` (A44), radius 16, no "Bạn" label; phone messages keep "Bạn · từ điện thoại" above (also in the queue). Agent text full width, no label, markdown as D17. Tool card one line: kind icon, verb + object middle-cut, +/− for edits, status right never cut ("chờ", "chờ bạn", "đang chạy · 2,1 s", `check`, "lỗi · mã 1"); collapsed by default; auto-opens **only** while waiting for permission (no auto-open when a command finishes); tap opens diff/output. Thinking: one dim folded line "Suy nghĩ ›" / "Đang suy nghĩ…". No grouping of cards.
- T33: every V2-1 / V2-2b behaviour of the page kept.

**Tests first:** header shows project, branch, agent, status; menu items; "Phiên mới với Codex" opens the home with this folder and Codex; narrowing at 520 / 420 / 320 px drops branch then project, status remains; bubble right-aligned ≤ 80 %, no `BoxShadow` in a 50-item timeline, no "Bạn" label; phone line kept; finished command card stays collapsed; permission-waiting card opens; thinking folded. Existing V2-1/V2-2b page tests green (only T30/T32 assertions edited).

**Commit:** `feat(v2-ai): the session page — a header with project, branch, agent and status; bubbles, one-line tool cards, folded thinking`

---

### Task 19: The tool dock by mode (T8)

**Files:** Modify `lib/src/ui/tools/tool_area.dart` (workspace resolution), the tool openers (palette, Settings › Dự án), `⌘⇧B` enablement. Tests: `test/ui/tools/tool_dock_mode_test.dart`.

**Interfaces:** Consumes Tasks 8, 11, 16 (`aiHomeDraftProvider.folder`).

**Implementation notes:** Terminal mode: as V2-3. AI mode with a session: the dock of the workspace holding the AI tab; header 🧩 kept. AI home: the dock of the workspace whose `root` equals the project chip's folder, with that workspace's saved open/closed/width; chip not a project → no dock, ⌘⇧B dimmed. Opening a tool in AI mode: the tool's workspace has an AI tab → select its newest AI tab, open the dock; no AI tab but a `root` → home with chip = root, open the dock; no root → `setMode(terminal)` and V2-3 D4. Entering AI mode drops `loose`. No Tool group in the AI sidebar.

**Tests first:** each branch above; ⌘⇧B disabled on the home with a non-project chip; dock state per workspace restored.

**Commit:** `feat(v2-ai): the tool dock follows the mode — the AI home docks the project chip's workspace`

---

### Task 20: ⚠ The desktop as the phone's source — folders with branch, `open(text)`, folder history (T42–T44)

**Files:** Modify `lib/src/ai/ai_phone.dart` (`DesktopAiSource.folders`, `open`, new `folderHistory`; listing `sessions` in AI-sidebar order). Tests: `test/ai/ai_phone_v25b_test.dart`.

**Interfaces:**
- Consumes: Tasks 6, 11, 13, 4 (`aiHistoryListerProvider`), 17 (`touch`).
- Produces: `DesktopAiSource.open(String agentId, String folderKey, {String? resume, String? text})`, `DesktopAiSource.folderHistory(String agentId, String folderKey, {String? cursor}) → Future<AiListOutcome>`.

**Code (complete):**

```dart
  @override
  List<AiFolderChoice> get folders {
    final l10n = _ref.read(appL10nProvider);
    final branches = _ref.read(aiFolderBranchesProvider); // cache only (P12)
    final out = <AiFolderChoice>[];
    final seen = <String>[];
    bool fresh(String path) {
      if (seen.any((s) => aiSamePath(s, path))) return false;
      seen.add(path);
      return true;
    }
    final gone = _ref.read(aiGoneRootsProvider);
    for (final w in _ref.read(sidebarWorkspacesProvider).workspaces) {
      final root = w.root;
      if (root == null || w.ssh != null || gone.contains(root)) continue;
      if (!fresh(root)) continue;
      out.add(AiFolderChoice(
        key: 'ws:${w.id}', name: w.displayName(l10n), path: root,
        branch: branches.cached(root),
      ));
    }
    // T11 recent order: ai_recent_folders first (newest on top), then the
    // folders of open AI tabs that are not in it.
    final recent = [
      for (final r in _ref.read(aiRecentFoldersProvider)) r.path,
      for (final t in _tabsInSidebarOrder()) ?t.ai?.cwd,
    ];
    for (final path in recent) {
      if (!fresh(path)) continue;
      out.add(AiFolderChoice(
        key: 'path:$path', name: p.basename(path), path: path,
        branch: branches.cached(path),
      ));
    }
    return out;
  }

  @override
  Future<int?> open(
    String agentId,
    String folderKey, {
    String? resume,
    String? text,
  }) async {
    final path = folders.where((f) => f.key == folderKey).firstOrNull?.path;
    final agent = aiAgentById(_ref.read(aiAgentsProvider), agentId);
    if (path == null || agent == null) return null; // D9: re-checked here
    final tabId = _ref.read(terminalTabsProvider.notifier).openAiTab(
      agentId: agent.id,
      agentName: agent.name,
      title: _ref.read(appL10nProvider).aiNewSession,
      cwd: path,
      sessionId: resume,
      workspace: aiWorkspaceForFolder(_ref, path),
      select: false, // the computer's user keeps their tab (V2-2 D9)
    );
    final pane = _ref.read(terminalTabsProvider).tabs
        .where((t) => t.id == tabId).firstOrNull?.ai;
    if (pane == null) return null;
    final control = this.control(pane.id, start: true);
    if (control == null) {
      _ref.read(terminalTabsProvider.notifier).close(tabId);
      return null;
    }
    unawaited(_ref.read(aiRecentFoldersProvider.notifier).touch(path));
    if (text != null) {
      // Queued until the agent is ready; shown "Bạn · từ điện thoại" (B24).
      await control.send(AiPhonePrompt(text));
    }
    return pane.id;
  }

  @override
  Future<AiListOutcome> folderHistory(
    String agentId,
    String folderKey, {
    String? cursor,
  }) async {
    final path = folders.where((f) => f.key == folderKey).firstOrNull?.path;
    final agent = aiAgentById(_ref.read(aiAgentsProvider), agentId);
    if (path == null || agent == null) return const AiListNotReady();
    return _ref.read(aiHistoryListerProvider).list(agent, path, cursor: cursor);
  }
```

(`_tabsInSidebarOrder()` returns the AI sidebar's order (T12) from Task 13's model; `aiGoneRootsProvider` is the last existence check of project roots; `aiFolderBranchesProvider.cached(path)` returns the cached value without awaiting and schedules a read on a miss, whose result fires `changes`.)

**Tests first:** folders order = projects (workspace order; no SSH; no gone root) then recent (recent order, open-tab folders last), `branch` from the cache; `open` with an unknown key/agent → null, no tab; `open(text: 'sửa nút đăng xuất')` → one unselected tab, `send` called once with the phone flag, recent touched; `select` and `mode` unchanged; `folderHistory` calls the lister with the key's **path**, never a phone string; listing `sessions` in AI sidebar order; e2e (`packages/shellx_e2e`, fake hub) "ai.open {text} → new tab, first message shows 'Bạn · từ điện thoại'".

**Commit:** `feat(v2-ai): the desktop serves the phone recent folders with branches, ai.open with text, and a folder's earlier sessions`

---

## B-phone (branch `v2-5b-phone`, Tasks 21–25)

All paths under `apps/mobile/` unless written from the root. Commands for every phone task: `cd apps/mobile && PATH=~/fvm/versions/3.41.4/bin:$PATH dart run intl_utils:generate` (when ARBs change, then the `dart format` of the generated files) `&& PATH=~/fvm/versions/3.41.4/bin:$PATH dart run build_runner build --delete-conflicting-outputs` (when routes/DI change) `&& PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test`. Strings go to `lib/l10n/intl_en.arb` / `intl_vi.arb` (§8.3 verbatim) in the task that first shows them.

### Task 21: The bottom bar and the routes — `HomeRoute` with three tabs (T34)

**Files:** Modify `lib/core/router/app_router.dart` (+ regenerated `app_router.gr.dart`), `lib/core/auth/session_enforcer.dart` (`replaceAll([HomeRoute()])`), `lib/features/notifications/presentation/notification_opener.dart` (`popUntilRouteWithName(HomeRoute.name)`; AI notice selects tab 2 and the notice's machine before pushing the session), `lib/features/machines/presentation/pages/machine_list_page.dart` (no ⚙ button; B21 hold only when this tab is shown **and** the route is on top; a tap on the AI line: one session needing you → open it, else → AI tab with that machine), every `SettingsRoute` push (P14); Create `lib/features/home/presentation/pages/home_page.dart` (`HomePage` → `HomeRoute`), a stub `lib/features/ai/presentation/pages/ai_home_page.dart` (`AiHomePage` → `AiHomeRoute`, filled by Task 22); ARBs `navComputers`, `navAssistant`, `navSettings`, `navAssistantBadge`; remove `settingsTooltip` when grep finds no use. Tests: `test/core/router/home_route_test.dart`, update `notification_opener_test.dart`, `session_enforcer_test.dart`, `machine_list_page_test.dart`.

**Interfaces:**
- Consumes: V2-5a `ShellxBottomBar` (Task 10 of A), `ShellxIcons.computer` (B), `.ai`, `.settings`.
- Produces: `HomeRoute`, `AiHomeRoute`; `final class HomeTabs { static const computers = 0, assistant = 1, settings = 2; }`; `AiTabSelection` (singleton, signals): `selectAssistant({String? machineId})`, `ReadonlySignal<int> index`, `ReadonlySignal<String?> requestedMachine`; `ReadonlySignal<int> aiNeedsYouBadge` (sum of `needsInput` of listings the app already holds; no new channel).

**Code (route table, complete):**

```dart
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: UpdateRequiredRoute.page),
    AutoRoute(page: LoginRoute.page, guards: [updateGuard]),
    AutoRoute(page: RegisterRoute.page, guards: [updateGuard]),

    // Signed-in shell (V2-5b T34): AutoTabsRouter builds no nested navigator,
    // so every page and dialog still lives on the root navigator.
    AutoRoute(
      page: HomeRoute.page,
      initial: true,
      guards: [updateGuard, authGuard],
      children: [
        AutoRoute(page: MachineListRoute.page, initial: true),
        AutoRoute(page: AiHomeRoute.page),
        AutoRoute(page: SettingsRoute.page),
      ],
    ),
    // Pushed over the bar with context.router.root.push(...).
    AutoRoute(page: TerminalRoute.page, guards: [authGuard]),
    AutoRoute(page: AiSessionRoute.page, guards: [authGuard]),
    AutoRoute(page: AiProjectRoute.page, guards: [authGuard]),
    AutoRoute(page: AiNewSessionRoute.page, guards: [authGuard]),
    AutoRoute(page: AiItemRoute.page, guards: [authGuard]),
    AutoRoute(page: AiFileDiffRoute.page, guards: [authGuard]),
    AutoRoute(page: ToolRoute.page, guards: [authGuard]),
    AutoRoute(page: QrScannerRoute.page, guards: [authGuard]),
    AutoRoute(page: DeleteAccountRoute.page, guards: [authGuard]),
  ];
```

(`AiProjectRoute`/`AiNewSessionRoute` pages are stubs here, filled by Tasks 23–24.)

**Implementation notes:** `HomePage` = `AutoTabsRouter(lazyLoad: true, homeIndex: 0, routes: [MachineListRoute(), AiHomeRoute(), SettingsRoute()])` + `ShellxBottomBar` (labels one line, A's 1.3× cap; active = gradient tile); badge on tab 2: `navAssistantBadge` semantics, "9+" above 9, drawn number. Android back on tab 2/3 → tab 1; on tab 1 → exit as today. App start: tab 1. Coming back to tab 1 refreshes the machine list (as closing Settings did). Settings has no back button.

**Tests first:** `home_route_test.dart`: three tabs with labels "Máy tính" / "Trợ lý AI" / "Cài đặt"; signed-in start lands on `MachineListRoute` inside `HomeRoute`; `replaceAll([HomeRoute()])` after sign-in; pushing `AiSessionRoute` via `root.push` covers the bar (bar not in the tree of the top route); back on tab 2 → tab 1, back on tab 1 → pops the app; AI notification → tab 2, machine selected, then `AiSessionRoute` pushed; B21 hold released when tab 2 is shown (the machine page stays alive in the `IndexedStack`); badge "9+" for 12; 320 pt at 200 % text: no overflow.

**Commit:** `feat(v2-ai): the phone's bottom bar — Máy tính, Trợ lý AI, Cài đặt — over one root navigator`

---

### Task 22: The AI tab — machine chip, listing hold, open sessions, projects, recent (T35, T36)

**Files:** Modify `lib/core/settings/app_settings.dart` (`aiMachineKey = 'settings_ai_machine'`, `aiLastFolderKey = 'settings_ai_last_folder'`, signals + setters); Create `lib/features/ai/domain/ai_folder_group.dart`, `lib/features/ai/presentation/controllers/ai_home_controller.dart`, fill `pages/ai_home_page.dart`; ARBs `aiTabTitle`, `aiMachineChip`, `aiPickMachine`, `aiNoMachines`, `aiMachineOffline`, `aiOpenSessions`, `aiSeeAll`, `aiProjects`, `aiRecent`, `aiNoFolderGroup`, `aiFolderSessions`, `aiNewNoFolders`. Tests: `test/features/ai/domain/ai_folder_group_test.dart`, `test/features/ai/presentation/ai_home_page_test.dart`.

**Interfaces:**
- Consumes: `WorkspaceRegistry`, `TerminalWorkspace.holdAiListing()`, `MachineAi.listing`, `AppSettings.lastMachineId`, Task 3 `AiFolderChoice.branch`.
- Produces: `final class AiFolderGroup {AiFolderChoice folder; bool isProject; List<AiSessionInfo> sessions; int needsYou}` (`toString() == 'AiFolderGroup(…)'`); `({List<AiSessionInfo> open, List<AiFolderGroup> projects, List<AiFolderGroup> recent, List<AiSessionInfo> noFolder}) groupAiListing(AiListing l)`; `AppSettings.aiMachineId` (`ReadonlySignal<String?>`), `setAiMachineId(String)`, `String? aiLastFolderFor(String machineId)`, `setAiLastFolder(String machineId, String key)` (JSON map, ≤ 20 machines, oldest dropped); `AiHomeController` (signals: `machine`, `listing`, `state` ∈ {noMachines, offline, oldDesktop, unavailable, connecting, ready}).

**Implementation notes:** header "Trợ lý AI" + machine chip (`computer`, drawn online dot, name cut at end, `expand`; sheet of paired machines, offline dimmed and not selectable, `machineLastUsed` "Dùng gần nhất"; one machine → chip not tappable); default machine = `lastMachineId` if online else first online. Data: connect, `session.list {desktop: true}` when `ai` unknown, then `holdAiListing()` **only while the tab is shown and the app is in front**; release on leaving the tab, background, machine change; pull to refresh asks the listing again. Lists: open sessions (needing you first, then listing order; 5 then `aiSeeAll`), `ws:` → projects, any other key → recent, sessions without `cwd` → no-folder group; folder row: `folder`, name (end-cut), path (dim, middle-cut), branch (hidden first), "{n} phiên" never cut, warning dot, `chevronRight`; match sessions by `session.cwd == folder.path`; tap → `AiProjectRoute`. States: `aiNoMachines` + `scanQr` "Quét mã QR"; `aiMachineOffline`; `aiUpdateDesktop`; `aiUnavailable`; spinner. No folders: `aiNewNoFolders`. The start composer (Task 24) sits at the bottom above the bar (placeholder here).

**Tests first:** grouping (`ws:` project, `path:` recent, unknown prefix recent, no `cwd` group, a `cwd` matching no folder only in open sessions); needs-you first; "Xem tất cả (7)"; "2 phiên"; each state's VI text exact ("Ghép đôi một máy tính để dùng Trợ lý AI.", "MacBook đang offline. Mở ShellX trên máy đó rồi thử lại."); hold taken only when shown + foreground, released on tab change and on `AppLifecycleState.paused`; machine choice saved under `settings_ai_machine`; `toString` `'AiFolderGroup(…)'`; 320 pt at 200 %: no overflow.

**Commit:** `feat(v2-ai): the phone's AI tab — a machine chip, open sessions, projects and recent folders from the listing`

---

### Task 23: The project page — open sessions and earlier sessions (T37)

**Files:** Create `lib/features/ai/presentation/pages/ai_project_page.dart` (`AiProjectPage(agentId, machineName, folderKey)` → `AiProjectRoute`), `presentation/controllers/ai_project_controller.dart`; ARBs `aiProjectOpen`, `aiProjectEarlier`, `aiProjectEarlierUpdate`, `aiProjectEarlierNotReady`, `aiProjectEarlierNoList`, `aiProjectEmpty`, `aiProjectGone`. Tests: `test/features/ai/presentation/ai_project_page_test.dart`.

**Interfaces:** Consumes Task 7 `MachineAi.folderHistory`, `MachineAi.resume`, `MachineAi.can`, Task 22 grouping. Produces `AiProjectController` (`load()`, `more()`, `agent` signal, `pastSessions`, `state`).

**Implementation notes:** header: `back`, name, path (middle-cut), branch. "Đang mở": sessions with this `cwd`. "Phiên trước · {agent} ▾": only when `can(AiFeature.folderHistory)`; agent = newest open session's agent here else `default_agent`; "▾" picks another listing agent; page 50, `aiHistoryMore` "Tải thêm"; drop `acp` equal to an open session's; tap → `MachineAi.resume(agent, folderKey, acp)` then push `AiSessionRoute`. No feature → `aiProjectEarlierUpdate`; `not_ready` → `aiProjectEarlierNotReady`; `no_list` → `aiProjectEarlierNoList`. Key gone from the listing while here → `aiProjectGone`, composer dimmed. Bottom: start composer with the project chip fixed (Task 24).

**Tests first:** open sessions listed; earlier page from a fake client (2 rows with "13/10 09:30" style), "Tải thêm" sends `cursor`; duplicate `acp` dropped; agent switch re-asks with the new agent; the three status texts exact (VI); no `ai.folder.history` sent without the feature (the fake sees none); resume sends `ai.open {resume}` then pushes the session; gone key text; overflow 320 pt at 200 %.

**Commit:** `feat(v2-ai): the phone's project page — open sessions and the folder's earlier sessions`

---

### Task 24: ⚠ The type-first new session — `AiStartComposer`, `AiNewSessionRoute` (T38, T40, T41; Review Focus 2, 5)

**Files:** Create `lib/features/ai/presentation/widgets/ai_start_composer.dart`, `presentation/controllers/ai_start_controller.dart`, `pages/ai_new_session_page.dart` (`AiNewSessionPage(agentId, machineName)` → `AiNewSessionRoute`); Modify the machine page's session picker and `widgets/ai_chooser.dart` (open `AiNewSessionRoute` instead of the sheet); Delete `widgets/ai_new_session_sheet.dart` (and `aiNewAgent`, `aiNewFolder`, `aiNewStart` when grep finds no use); ARBs `aiChooseProject`, `aiChooseAgent`, `aiNewTitle`, `aiStarting`, `aiDraftWaiting`. Tests: `test/features/ai/presentation/ai_start_composer_test.dart`.

**Interfaces:**
- Consumes: Task 7 `MachineAi.open(agent, folder, {text})`, `AiDrafts.keep`, `AiWords.failure`, `AppSettings.aiLastFolderFor/setAiLastFolder`, B14 dictation (`mic`), V2-5a `ShellxCard`, `ShellxChip`, `AppButton`.
- Produces: `sealed class AiStartOutcome` (`AiStarted(String sid, {required bool draft})`, `AiStartFailed(String code)`, `AiStartUnknown()`); `AiStartController.send() → Future<AiStartOutcome>`; `AiStartComposer({required String machineId, String? fixedFolderKey, bool startVoice = false})`.

**Code (complete — D9 and never re-sent):**

```dart
/// V2-5b T38/T40: the phone starts a session with keys the computer offered
/// (D9) — it never makes, types or browses a path — and sends at most once.
final class AiStartController {
  AiStartController(this._ai, this._drafts, this._settings, this.machineId);
  final MachineAi _ai;
  final AiDrafts _drafts;
  final AppSettings _settings;
  final String machineId;

  var _sending = false;

  /// The listing's own keys only; null when the key left the listing.
  String? folderKeyOrNull(String? key) {
    final folders = _ai.listing?.folders ?? const <AiFolderChoice>[];
    return key != null && folders.any((f) => f.key == key) ? key : null;
  }

  Future<AiStartOutcome> send({
    required String agent,
    required String? folderKey,
    required String text,
  }) async {
    final key = folderKeyOrNull(folderKey);
    if (_sending || key == null || text.trim().isEmpty) {
      return const AiStartFailed('refused');
    }
    _sending = true;
    try {
      String sid;
      var draft = false;
      if (_ai.can(AiFeature.openPrompt)) {
        sid = await _ai.open(agent, key, text: text); // one request, the text with it
      } else {
        sid = await _ai.open(agent, key); // older computer: the draft path
        _drafts.keep('ai:$machineId/$sid', text);
        draft = true;
      }
      await _settings.setAiLastFolder(machineId, key);
      return AiStarted(sid, draft: draft);
    } on AiRequestException catch (e) {
      return AiStartFailed(e.code); // the text stays in the field
    } on MachineConnectionException {
      return const AiStartUnknown(); // aiOpenOutcomeUnknown; never re-sent
    } finally {
      _sending = false;
    }
  }
}
```

(Use the existing draft key format of `AiDrafts` for a session if it differs from `'ai:{machine}/{sid}'`, as T38 names it.)

**Implementation notes:** A's card; field 1–6 lines, hint "Nhắn cho {agent}…"; chip row one line: project (`folder` + name + `expand`; sheet with "Dự án" / "Gần đây" built **only** from listing keys; fixed and not tappable on the project page), agent (`ai` + name + `expand`; listing agents, not ready dimmed with "cài trên máy tính"), `mic` (B14 dictation kept; stops on leaving the tab/page or background), the `voiceMode` slot to its right left empty for V2-5c, gradient Send (`send`); icons and Send never shrink, the two chips share the rest and cut at the end. Presets: folder = `aiLastFolderFor(machine)` if still in the listing, else first `ws:` key, else first key; agent = `default_agent` if ready, else first ready. Outcomes: `AiStarted(draft: false)` → push `AiSessionRoute` (sid key `ai:{machine}/{sid}`), clear the field; `draft: true` → push it with the composer pre-filled and the strip `aiDraftWaiting`, **no auto-send**; `AiStartFailed` → text kept, `AiWords.failure(code)`; `AiStartUnknown` → `aiOpenOutcomeUnknown`, text kept. No images, `@`, mode or model before a session (§9: the phone never picks a mode first). `startVoice` passes through to `AiSessionRoute` for V2-5c.

**Tests first:**
- `with open_prompt sends one ai.open with text` (fake client records: exactly one `AiOpen{text: 'sửa nút đăng xuất'}`), pushes the session, clears the field.
- `without open_prompt opens, keeps the draft, never sends the text`: one `AiOpen` without text; `AiDrafts.of(key) == 'sửa nút đăng xuất'`; strip "Tin của bạn đang ở ô nhập. Chạm Gửi khi phiên sẵn sàng."; no `ai.prompt` sent.
- `failure keeps the text` (`refused`, `too_large` texts via `AiWords.failure`); `lost channel → aiOpenOutcomeUnknown, no second ai.open` after waiting.
- `a double tap sends once`.
- `only listing keys`: the project sheet shows exactly the listing's keys; a key that leaves the listing → chip back to "Chọn dự án", Send disabled; there is no text field for a path anywhere (find no `TextField` in the sheet).
- presets (last folder per machine, `ws:` fallback; ready default agent); old sheet replaced in the machine page and the AI chooser (finder for `AiNewSessionRoute` push); 320 pt at 200 %: no overflow, Send and mic full size.

**Commit:** `feat(v2-ai): the phone's type-first new session — listing keys only, one ai.open with the text or a kept draft, never re-sent`

---

### Task 25: The phone session page restyle (T39, T41 hooks)

**Files:** Modify `lib/features/ai/presentation/pages/ai_session_page.dart` (header, `startVoice` param reserved for V2-5c), `widgets/ai_dock.dart` (composer card with chips), `widgets/ai_timeline.dart`, `widgets/ai_items.dart` (bubbles, one-line tool items, folded thinking), `widgets/ai_config_sheet.dart` (opened from chips). Tests: `test/features/ai/presentation/ai_session_page_v25b_test.dart`; existing V2-2/V2-2b page tests green (edit only T39 assertions).

**Interfaces:** Consumes A's `ShellxCard`, `ShellxChip`, roles `back`, `folder`, `branch`, `image`, `mic`, `micOn`, `send`, `queue`, `stop`. Produces `AiSessionRoute(..., {bool startVoice = false})` (unused until V2-5c).

**Implementation notes:** header: `back`; title; subtitle "● {agent} · {state}[ · clock] · {project} · {branch}" (drawn dot; project with `folder`, branch with `branch`), state first, cut at end; project name = listing folder whose `path == cwd`, else last folder name; ⋯ as B17/B20. Mode, model, context move into the composer card: chips "Hỏi trước ▾" / "Opus ▾" open the B11 sheet (replacing the tappable subtitle of B11), context ring "16%" (`aiContext`); card: images row, `@` suggestions, field, chips (mode, model cut at end, `image` when `blob`, `mic`, Send/Queue/Stop with V2-2/V2-2b rules). Timeline: right-aligned user bubble (A's `raised`, no shadow), agent text full width, one-line tool items collapsed (auto-open while waiting for permission, as today), thinking folded. Permission panel, questions, queue, 400 ms tap guard, "Xem đủ", Changes / Undo kept. V2-5c hook: when voice mode is on, C's bar replaces the card (dock panels stay above).

**Tests first:** subtitle order and cut (state visible at 320 pt with a 60-char project); chips open the B11 sheet; context ring "16%"; bubble right-aligned without `BoxShadow`; finished tool item stays collapsed; permission item open; 400 ms guard test still green; 320 pt at 200 %: no overflow.

**Commit:** `feat(v2-ai): the phone session page — a subtitle with project and branch, mode and model chips in the composer card, bubbles`

---

## Back on `v2-5b`

### Task 26: Merge, compatibility end to end, strings, icon and `selectedId` sweeps, ledger

**Files:** Merge `v2-5b-desktop` then `v2-5b-phone` into `v2-5b` (ARBs and the ledger may both change: take both sides, regenerate); Modify `packages/shellx_e2e/test/` (new `ai_assistant_e2e_test.dart`); `docs/superpowers/ledgers/v2-5b.md`.

**Tests first** (`ai_assistant_e2e_test.dart`, desktop and phone over the fake hub as V2-2):
- `the listing carries recent folders and branches` (phone sees `ws:` and `path:` keys with `branch`).
- `ai.folder.history through the lister with a fake agent` (page of 2, `next` absent).
- `ai.open {text} opens a tab whose first message shows "Bạn · từ điện thoại"`.
- §6.4 matrix: old phone (frozen V2-2b listing decoder) + V2-5b desktop works and ignores `branch`; V2-5b phone + V2-2b window (no words) → project page "Cập nhật ShellX…", composer draft path; V2-5b phone + `ai: 1` → same; no AI → `aiUpdateDesktop`; V2-5b window behind a V2-2b daemon (reads `AiRaw`) → `ai.folder.history` passes unchanged and answers; no window → `unavailable` at once.

**Steps:**
- [ ] Full runs: analyze + tests for `packages/shellx_core`, `shellx_ai`, `shellx_agent`, `shellx_client`, `shellx_e2e`, `shellx_acp`, `shellx_design`, `apps/desktop`, `apps/mobile`; record counts.
- [ ] Sweeps (record results): `rg -n "Icons\.|CupertinoIcons\." apps/desktop/lib apps/mobile/lib | rg -v shellx_design` → only what A's guard baseline allows (B adds none); `rg -n "selectedId" apps/desktop/lib` → every reader is `TerminalTabs` internals, `TerminalPane`, restore, `ui.ls` (Review Focus 1); `rg -n "Claude Code" apps/*/lib/l10n` → none; `rg -n "debugPrint|log\(" ` in files B touched → no path, title, text or cursor interpolated; EN/VI key sets equal in both apps.
- [ ] macOS build in a throw-away worktree (no launch); optional isolated smoke launch per V2-5a's recipe (bundle id `pro.shellx.desktop.smoketest`, temp HOME, stop by PID).
- [ ] Ledger: counts, sweeps, Task 1 probe facts, P0 name deviations, the 11 manual checks of spec §13 (unchecked) and the follow-ups of §16.

**Commands:** as Global Constraints, every package.

**Commit:** `test(v2-ai): V2-5b end to end and both-way compatibility; docs(v2-ai): V2-5b ledger`

---

## Self-review

- **Spec coverage:** T1 → 10; T2 → 8, 10; T3, T4 → 10; T5 → 8; T6 → 9; T7 → 10, 17; T8 → 19; T9 → 8, 14; T10–T17 → 13, 14; T18, T20, T21, T23 → 16; T19 → 15; T22 → 17; T24, T26, T27, T29 → 12; T25, T28 → 11; T30–T33 → 18; T34 → 21; T35, T36 → 22; T37 → 23; T38, T40 → 24; T39 → 25; T41 → 15, 24, 25; T42 → 3, 20; T43 → 2, 4, 6, 7, 20; T44 → 2, 6, 7, 20; T45 → 2, 3, 6, 26; T46 → every task's `toString` test; T48 → 1 + each UI task; T49 → each UI task's overflow test; §8 → the tasks that show the strings, 26 checks parity; §11 → per task; §12 → Review Focus; §13 → ledger (26).
- **Placeholder scan:** code is complete where the rules require it (protocol, gating, hub, lister, cache, mode state machine, first-message hand-off, D9 start controller); elsewhere exact values and names are given.
- **Type consistency:** `AiListOutcome` (Task 4) is what `AiSessionSource.folderHistory` (6) and `DesktopAiSource.folderHistory` (20) return; `AiFolderChoice.branch` (3) is written by 20 and read by 22–23; `kNoTabShown`/`SidebarMode` (8) are used by 9–19; `AiFirstMessage`/`AiStart` (17) consume `AiHomeDraft` (16); `MachineAi.open(text:)`/`folderHistory` (7) are called by 23–24.

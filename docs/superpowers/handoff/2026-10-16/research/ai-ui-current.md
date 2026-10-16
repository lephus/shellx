# ShellX AI UI today (desktop AI tab, phone AI pages) and what "choose a project" could map to

Research only; nothing in the repository was modified or run. Findings come from reading code and specs.

## 0. Method, versions, path conventions

| Tag | Tree | HEAD when read |
|---|---|---|
| `[2b]` | `/Users/richard/Documents/helper/shellx/.claude/worktrees/v2-2b` (branch `v2-2b`) | `640141b` (other agents were still committing; line numbers may drift) |
| `[3]` | `/Users/richard/Documents/helper/shellx/.claude/worktrees/v2-3` (branch `v2-3`) | `a7df506` |
| `[spec]` | `docs/superpowers/specs/` (same files in every tree) | |

- Paths are relative to the tree's root. Which tree an untagged path refers to: `apps/desktop/lib/src/ai`, `apps/desktop/lib/src/ui/ai`, `apps/mobile/**` and `packages/**` are `[2b]` line numbers; `apps/desktop/lib/src/{terminal,ui/terminal,ui/settings,config,restore,cli,platform,remote,ui/theme}` are `[3]` line numbers (that tree adds the V2-3 tool dock: a right-hand column, an extension-puzzle icon button in the AI header, a sidebar "Tools" group and an "Add tool" button). Docs and specs are identical in both trees.
- The two desktop trees differ in the AI code only by what each branch added: `[2b]` has the V2-2b desktop changes (phone prompt source "You · from your phone", off-thread image encoding, phone file index, `ai_phone.dart` hub source); `[3]` has only the extra tools button in `ui/ai/ai_header.dart` and `ui/ai/ai_pane_view.dart`. The V1-style AI pane behaviour described below is the same in both.
- State of V2-2b in the phone code when read: B19/B20 (phone Changes and Revert) are NOT there: `packages/shellx_agent/lib/src/ai/ai_phone_hub.dart:606-611` still answers `ai.changes`, `ai.diff`, `ai.revert` with `_refuse`, and the session page's "..." menu has only "Session history". B21 (AI line on the machine list) is being written right now: at committed HEAD 640141b it is absent, but the `[2b]` working tree holds uncommitted edits by another agent (`apps/mobile/lib/features/machines/presentation/pages/machine_list_page.dart`, new `.../controllers/machine_ai_lines.dart`, new ARB keys `machineAiLine` and `machineAiSessions`: EN "✦ {n, plural, =1{1 AI session} other{{n} AI sessions}} · {w} need you", VI "✦ {n} phiên AI · {w} cần bạn"); tapping that line opens the one session that waits, else the AI chooser. Everything else in V2-2b (B1-B18, B22-B24 and the push buttons) is committed.

## 0.1 Findings in short

1. The product word is "AI", not "Assistant" or "Trợ lý": zero hits for "Trợ lý", "trợ lý" and "Assistant" in the desktop and mobile ARB files and in every Dart file under `apps/` and `packages/` (the only "trợ lý" in the repo is a macOS native-helper section of the A6 browser spec). The user-facing nouns are "Giao diện AI" / "AI interface" (the feature), "Phiên AI" / "AI session" (one conversation), "agent" (the program, kept in English inside Vietnamese text) and "Claude" (the default agent, never "Claude Code" inside the feature, V2-1 D21). Exact strings in section 1.1 and 2.1.
2. On the desktop there is no agent picker and no project picker. "New AI session" opens a tab immediately with the default agent (a dropdown in Settings > Agents) and a folder chosen by a fixed fallback chain: workspace `root`, else the folder of the tab in front, else a card where the user TYPES an absolute path (no native folder dialog, no recents).
3. A "project" already exists, under two names: the sidebar calls it a **Workspace** (`Workspace {id, name, collapsed, ssh, zoom, root}`), Settings calls the same object a **Project / Dự án** (`apps/desktop/lib/src/ui/settings/pages/projects_page.dart:9-12`: "A 'project' here is a sidebar workspace"). `root` is only the default start folder for NEW tabs in that workspace. An AI tab stores its own `cwd`, so a tab's folder and its workspace are independent.
4. The phone has real pickers (agent radio list + folder radio list), but its folders are only keys that the desktop offers: workspace roots plus folders of currently open AI tabs. It never types or browses a path.
5. There is no "recent folders" list anywhere (the only recents are 10 SSH servers). The only per-folder session history is the agent's own `session/list {cwd}`, shown on desktop as a one-page dialog and on the phone as a paged sheet; ShellX stores no conversations (V2-1 D14, D20).
6. Git knowledge on the desktop is shallow and per terminal pane (branch name read from `.git/HEAD`); AI tabs deliberately show no branch (`terminal_tabs.dart:463`). The AI host keeps one hidden git repository per project folder for undo and never touches the project's own `.git`.

---

## 1. Desktop AI UI (V2-1 "AI tab")

### 1.1 What the UI calls it (exact strings)

Desktop ARB: `apps/desktop/lib/l10n/app_en.arb` and `app_vi.arb` (line numbers are the same in `[2b]` and `[3]` for the AI keys; given as `en:vi`).

| Key (arb line en:vi) | EN | VI |
|---|---|---|
| `aiNewSession` (1215:776), `actionNewAiSession` (1460:983) | New AI session | Phiên AI mới |
| `aiNewSessionTooltip` (1462:985) | New AI session  {shortcut} | Phiên AI mới  {shortcut} |
| `aiNewTabKindLabel` (1216:777) | New tabs open as | Tab mới mở dạng |
| `aiNewTabKindAi` (1217:778) / `aiNewTabKindTerminal` | AI interface / Terminal | Giao diện AI / Terminal |
| `aiOnboardingTitle` (1219:780) | How do you want to work? | Bạn muốn làm việc theo kiểu nào? |
| `aiIntroText` (1430:954) | New: an AI interface. How should new tabs open? | Mới: giao diện AI. Bạn muốn tab mới mở theo kiểu nào? |
| `aiSettingsSection` (1431:955) | AI interface | Giao diện AI |
| `aiSettingClaude` (1449:972) | Claude in the AI interface | Claude trong giao diện AI |
| `aiPaneLabel` (1250:801) | AI session with {agent} | Phiên AI với {agent} |
| `aiTabRowLabel` (1252:802) | AI session | Phiên AI |
| `confirmQuitAiBusy` (129:75) | An AI agent is still working in 1 tab. Quitting stops it. (plural) | Còn {count} tab AI đang làm việc. Thoát sẽ dừng chúng. |
| `aiDefaultAgent` (1440:963) | Default agent | Agent mặc định |
| `settingsPageAgents` (948:547) | Agents | Agent |
| `aiMenuAgentsSettings` | Settings › Agents | Cài đặt › Agents |
| `aiChooseFolderTitle` (1332:868) | Choose a project folder | Chọn thư mục dự án |
| `aiChooseFolderBody` (1333:869) | The agent works in this folder. | Agent làm việc trong thư mục này. |
| `aiFolderField` (1334:870) / `aiFolderUse` (1336:872) | Folder / Use this folder | Thư mục / Dùng thư mục này |
| `aiFolderInvalid` (1335:871) | Enter the absolute path of an existing folder. | Nhập đường dẫn tuyệt đối của một thư mục có thật. |
| `aiFolderMissing` (1330:866), `aiChooseFolder` | The project folder no longer exists, Choose folder | Thư mục dự án không còn, Chọn thư mục |
| `aiHistory` (1245:798) | Session history | Lịch sử phiên |
| `aiHistoryEmpty` (1468:989) | No earlier sessions for this folder. | Chưa có phiên nào trước đây cho thư mục này. |
| `aiComposerHint` (1220:781) | Message {agent}… (@ file, / command) | Nhắn cho {agent}… (@ nhắc tệp, / gọi lệnh) |
| `aiHeaderTerminal` (1260:809) / `aiHeaderPanel` (1259:808) | Terminal in this tab / Changes and files | Terminal trong tab này / Thay đổi và tệp |
| `aiNoUndo` | Undo is off for this project ({reason}) | Hoàn tác đang tắt cho dự án này ({reason}) |
| `settingsPageProjects` (951:550) | Projects | Dự án |
| `settingsProjectsIntro` (952:551) | A project groups your terminals. Give it a folder and new tabs in that project start there. | Dự án là một nhóm terminal. Gán cho dự án một thư mục thì tab mới trong dự án đó sẽ mở tại đây. |
| `settingsProjectFolder` (955:554) | Project folder | Thư mục dự án |
| `workspaceNew` (370:172), `workspaceNewTab` (371:173) | New workspace, New tab in this workspace | Workspace mới, Tab mới trong workspace này |
| `workspaceDefaultName` | Default | Mặc định |
| `toolLimitReached` (v2-3, 1546:1053) | This project already has {count} tools. | Dự án này đã có {count} tool. |
| `agentNamesClaude` | Claude Code (A12 badges of agents running in TERMINAL panes only) | Claude Code |

Notes:
- The agent's own display name comes from `kKnownAgents` (`packages/shellx_ai/lib/src/host/agent_catalog.dart:59-93`): `Claude`, `Codex`, `Gemini CLI`, `OpenCode`, plus user-added custom agents. The AI header, sidebar row and notifications use "Claude" (ruling B6, plan `docs/superpowers/plans/2026-10-14-v2-ai-desktop.md:64`).
- Where Vietnamese text names the feature it keeps the English words "agent" and "AI" ("tab AI", "phiên AI", "giao diện AI"). "Workspace" is never translated.
- Mobile uses the same nouns (section 2.1).

### 1.2 How a user starts an AI session

No dialog. A tab appears at once; the pane shows "Starting…" and the agent process starts only when the pane is first shown (ruling B11, plan line 69). Nothing is asked unless the folder is unknown.

| Entry point | Code | Notes |
|---|---|---|
| Shortcut Cmd+Shift+E / Ctrl+Shift+E (action `new_ai_session`) | `apps/desktop/lib/src/config/keybindings.dart:136`, `keybind_actions.dart:142`, handler `[3] ui/terminal/terminal_workspace_page.dart:469-475` | The window action calls `AiOpener.newSession(workspaceId: <loose workspace>)` |
| Sidebar footer button "New AI session" (sparkle icon, key `sidebar.newAi`) | `[3] ui/terminal/session_sidebar.dart:1950-1985` | In `[3]` it sits beside an icon button "Add tool" (`sidebar.addTool`, `:1990-2007`) |
| `+` in the sidebar header: right-click / Shift+F10 menu | `[3] ui/terminal/sidebar_new_button.dart:34-94` | Entries: New tab, New AI session, (New terminal tab, only when `new-tab-kind = ai`), Connect SSH…, Attach tmux… |
| Workspace header `+` and menu "New tab in this workspace" | `[3] ui/terminal/session_sidebar.dart:1603-1604` (`onNewTab`) and `:1159` (menu), both -> `ai_open.dart:69` | Opens an AI tab when `new-tab-kind = ai` AND the workspace is local; an SSH workspace keeps opening its server (ruling B8, plan line 66) |
| Cmd+T / `+` click / empty window / first tab at launch | `ai_open.dart:69-91` (`newTabIn`, `firstTab`, `_wantsAi`) | Only when the setting `new-tab-kind = ai` (default `terminal`: `config/shellx_config.dart:142`; setting row `config/settings_schema.dart:475-487`, Settings > General, label "New tabs open as") |
| Command palette | action label `actionNewAiSession` | |
| History dialog, "reopen a session" | `ui/ai/ai_pane_view.dart:371-389` | Opens a NEW AI tab (current workspace, selected) with the same agent and folder and `sessionId` set |
| A paired phone (`ai.open`) | `ai/ai_phone.dart:213-245` | Tab goes into the workspace named by the folder key, NOT selected, agent starts at once |
| First run | `ui/ai/ai_intro.dart:61-132` (onboarding page "How do you want to work?"), `:137-216` (one-time card at the foot of the sidebar for people who finished onboarding before V2; setting `ai_intro_shown`) | Writes `new-tab-kind` |

**Agent choice (no picker on the desktop):**
- `AiOpener.newSession` takes `aiDefaultAgentProvider` (`ai/ai_agents.dart:259-266`): the user's choice if it is still offered, else the first agent known to be Ready (`aiReadinessProvider`), else the first in the list (order Claude, Codex, Gemini CLI, OpenCode, then custom). Returns null (nothing opens) with no agent at all.
- The only place to choose is Settings > Agents > "AI interface": a `DropdownButton` "Default agent" (key `ai.defaultAgent`, `ui/ai/ai_agents_section.dart:242-270`), one row per agent with state (Ready / Needs Node {version} / Not installed / Needs sign-in / Error / Checking…), Install and Sign in buttons that run in the run sheet (a mini terminal over the pane, `ui/ai/ai_run_sheet.dart`), the `ai-agent-claude` switch, a custom-agent form, `ai-checkpoint-days` and "Delete all restore points".
- An open tab's agent is fixed: `AiPaneState.agentId/agentName` are set at creation (`ai/ai_pane_state.dart:20-50`); the header shows the agent name as plain text (`ui/ai/ai_header.dart:161-166`). Switching agent means opening another tab.
- Readiness is computed after the first frame (`ai/ai_startup.dart:69-93`), so "New AI session" never waits for it.

**Folder / cwd choice (`AiOpener.newSession`, `ai/ai_open.dart:27-63`):**
1. The workspace's project root `Workspace.root` (`side.workspace(id)?.root`).
2. Else `_frontFolder` (`ai_open.dart:52-63`): the folder of the selected tab, but only if that tab belongs to the same workspace; for an AI tab its `cwd`, for a terminal tab the focused pane's `cwd` unless that pane is remote (SSH). A folder that is "too broad" (home folder, any folder above it, a disk root) counts as none (`aiFolderIsBroad` -> `packages/shellx_ai/lib/src/host/broad_folder.dart:11`, final review I-1).
3. Else `cwd = null`: the pane shows the card "Choose a project folder" (`ui/ai/ai_folder_card.dart:17-136`) instead of a conversation.
- The card is a single text field (hint `~/code/project`), validated as absolute (`~` expanded) and existing (`ai/ai_folders.dart:8-31`). **No native folder dialog and no recent list**: ruling B7 (plan line 65): "No native folder picker: that would be a native plugin and a pinned version. Cost if wrong: add `file_selector` later." The desktop pubspec has no `file_selector`/`file_picker`.
- Choosing a folder (`ai_pane_view.dart:256-274`, `_useFolder`) swaps the runtime: the old one stops, a new session starts unless it is the same folder (then the session reopens). It updates only the pane (`updateAiPane`); it does NOT set `Workspace.root`.
- The same card comes back over a conversation when the folder vanished (notice "The project folder no longer exists" with a "Choose folder" button, `ui/ai/ai_notice_card.dart:203-211`; `Cancel` or Esc returns to the conversation).
- The global terminal setting `working-directory` (home / inherit / path, `config/settings_schema.dart:329`) is NOT used by AI sessions.

**Mode / model chips** (`ui/ai/ai_config_chips.dart:88-281`, in the composer's bottom row, `ui/ai/ai_composer.dart:579`):
- Built from the agent's ACP `configOptions` (any select or boolean option; `ConfigKind.other` skipped), or the legacy `modes` (one chip). Each chip is a text button with a caret that opens a small menu with the current value checked.
- Labels: mode -> the value's name (Claude's known ids translated: Ask first / Auto-edit files / Plan / Auto / Bypass permissions; VI Hỏi trước / Tự sửa tệp / Lập kế hoạch / Tự động / Bỏ qua mọi quyền); category `model` -> "Model: {name}"; `thought_level` -> "Thinking: {name}"; other -> "{name}: {value}".
- A choice goes to the agent (`session/set_config_option` / `session/set_mode`) and is remembered per agent for the next sessions (`ai/ai_agents.dart:273-310`, setting `ai_agent_config`), except any mode that acts without asking (Bypass, Codex "full-access", Gemini "yolo"): those always open the confirmation dialog "Turn on 'Bypass permissions'?" (Cancel has first focus) and are never remembered or re-applied (`ui/ai/ai_config_chips.dart:38-79`, rule R6).
- The chips row is replaced by a one-line warning note when the queue is full or the agent cannot take a message; no chips appear until the agent has reported options.

### 1.3 Timeline and message rendering

- `AiTimeline` (`ui/ai/ai_timeline.dart:32-179`): a virtualized `ListView.builder`, newest at the bottom, column capped at 760 px (`AiSizes.column`, `ui/ai/ai_theme.dart:9`); each item's widget is cached until its `rev` changes; the view follows the bottom only while the user is at the bottom, otherwise a "Jump to latest" button shows (`aiJumpToLatest`: "Jump to latest" / "Xuống tin mới nhất").
- Item map (`ai_timeline.dart:16-24`): `UserItem` -> bordered box labelled "You" (or "You · from your phone", B24) with selectable text and chips for `@` files and images; `AgentTextItem` -> markdown in a `SelectionArea` (`flutter_markdown_plus`, blocks split so only the last one repaints while streaming, images never load, links open only on click and only http/https: `ai_markdown.dart`); `ThoughtItem` -> folded "Thinking"; `ToolItem` -> `AiToolCard` (`ai_tool_card.dart:320`); `AskItem` -> `AiAskCard` (agent elicitation: text, number, yes/no, one/many choices, or a URL with "Open in browser"); `TurnEndItem` -> `AiTurnSummary`; `NoticeItem` -> `AiNoticeCard`.
- Tool cards by ACP `kind` (spec §4.2, `docs/superpowers/specs/2026-10-14-ai-pane-design.md:164-191`): verbs Read / Edit / Create / Delete / Rename / Search / Run / Fetch / "Mode changed: …"; `mcp__a__b` shows as "a · b"; states "waiting", "waiting for you", "running · 2.1 s", "done", "rejected", "stopped", "error"; edit cards expand to a diff with +/− counts, "View whole file" and "Open in editor"; command cards show output (ANSI stripped, capped, "Show all N lines"), exit code and duration. Cards open by themselves while a permission is pending.
- Turn summary: "Turn N · 0:41 · 2 files changed +44 −5 · View · Revert turn" (VI "Lượt N · {time} · {count} tệp đổi"), or "Stopped turn N…", "Turn N was interrupted…", "Turn N failed…".
- Notice cards (`ai_notice_card.dart`): sign-in needed (buttons per auth method, run in the run sheet), Node missing (+ installation guide), agent not installed (+ Install), agent exited (+ Restart, View log), cannot resume (a new session started), folder missing (+ Choose folder), undo off with the reason (`aiNoUndo`).

### 1.4 Header, composer, attachments, permission prompts

**Header** (`ui/ai/ai_header.dart:95-253`, 34 px): sparkle icon + agent name (plain text) + session title (ellipsised; `tab.label`) + status (live region; text only, with a once-a-second clock "Running · 0:12", no spinner) then right-aligned icon buttons:
- History (`Icons.history`, key `ai.history`): only when the agent lists sessions (`ai_pane_view.dart:540-542`).
- Panel (`vertical_split_outlined`, `ai.panel`): toggles the 268 px right panel with tabs Changes and Files (`ai_side_panel.dart`, `ai_changes_panel.dart`, `ai_files_panel.dart`).
- Terminal (`Icons.terminal`, `ai.terminal`): adds a terminal pane under the AI pane (72/28 split, in the session's folder).
- Zoom (only when the tab has more than one pane), More `...` (Settings > Agents, Restart agent, View log: `ai_pane_view.dart:419-462`).
- `[3]` adds an extension-puzzle icon (`ai.tools`, `ai_header.dart:220-227`) that toggles the workspace's tool dock.
- Status words come from `aiStatusOf` (`ai_header.dart:33-89`): Stopping… / A12 "Needs input" / Running / Starting… / Sign-in needed / Stopped / Agent not running / Done / Idle. The folder is NOT shown in the header.

**Dock under the conversation** (`ui/ai/ai_dock.dart:19-78`, column max 760): plan bar (one line "Plan · 2/5 done" that folds open, max 200 px), permission bar, queued-message rows ("Queued: “…” — sent when this turn ends", × to remove; "You · from your phone" prefix for phone messages), then the composer.

**Composer** (`ui/ai/ai_composer.dart:70`, field `:517` min 2 lines, grows to 140 px `:502`):
- Enter sends unless an IME is composing; Shift+Enter newline; Esc stops a running turn (button "Stop  Esc", then "Stopping…", after 10 s "Force stop"); while a turn runs or the agent starts, Send becomes "Queue" (max 5 waiting, `session_state.dart:77`).
- Buttons in the bottom row: `@` (mention a file, key `ai.mention`), `/` (agent commands, `ai.commands`), then the mode/model/thinking chips, "Context {percent}%" (`ai.context`), and Send/Queue/Stop/Force stop (`_SendButton`, `:671`).
- `@` completer (`ai_completer.dart`): files from the project index (respects `.gitignore` through ShellX's own matcher, never git on the project; ruling B12) inserted as ACP `resource_link`; `/` lists `available_commands_update`.

**Attachments / images** (`ui/ai/ai_images.dart`): paste (Cmd+V takes copied image files first, then text, then a clipboard image, `:27`, `:132`) or drag-drop onto the composer (`DropTarget`, `:251`) -> thumbnails strip above the field (`AiAttachments`, `:262`) -> sent as ACP `image` blocks. Limits: 5 images (`kAiImagesMax`), 10 MiB each (`kAiImageMaxBytes`, `packages/shellx_ai/lib/src/remote/images.dart:6-10`); BMP/TIFF are converted to PNG; if the agent does not take images the composer says "{agent} does not take images." (`aiImageUnsupported`). There is no file-attach button: files go in only as `@` mentions of the project; images by paste/drop. No voice on the desktop.

**Permission prompts** (`ui/ai/ai_permission_bar.dart`):
- A warning-coloured bar above the composer (`:118-229`), one request at a time (the rest wait), first line "{agent} asks: {action}" (live region; capped height 112 px so the buttons stay on screen), one button per ACP option in the agent's order, each with a numeric badge; the first reject option also carries "Esc". Main labels come from the option kind (Allow / Always allow / Reject / Always reject); the agent's own words for "always" stay as a note underneath.
- Keys (`aiPermissionKeys`, `:53-91`): 1-9 pick the option when the composer is empty (digits type into the composer otherwise); Esc picks the first reject option or answers `cancelled`; nothing ever picks an allow option by itself. The conversation column also listens so the keys work after clicking the agent's text (`ai_pane_view.dart:619-672`).
- The matching tool card shows "Waiting for your answer below — keys 1–{n}, Esc to reject", afterwards "You chose: Allow (Yes)". An option that would turn on a no-approval mode asks the Bypass confirmation first.

### 1.5 How sessions are listed (tabs, sidebar, workspaces)

- There is **no AI-specific list**. AI sessions are ordinary sidebar tabs (a vertical list at the left, 220 px, `[3] ui/theme/shellx_desktop_theme.dart:71`; there is no horizontal tab strip). Rows are grouped under workspace headers, but headers only show from two workspaces on (`SidebarState.showHeaders`, `[3] terminal/sidebar_workspaces.dart:222`). With only the Default workspace the sidebar is a flat list and no project name is visible anywhere.
- An AI row (`[3] ui/terminal/session_tab_row.dart:1066-1121`): a sparkle mark in the status-dot slot, the tab label as the title (the agent's session title, else the first prompt cut to 40 characters, else "New AI session": `packages/shellx_ai/lib/src/model/session_state.dart:117-132`), and a second line "{A12 state} · {agent}" (for example "Needs input · Claude") in the badge colour. Branch, ports and path are not shown; the folder only appears in the screen-reader label (`session_tab_row.dart:284`).
- Sorting, drag between workspaces, pinning, rename, description and status labels work for AI tabs as for terminals (A2/A11). Closing a tab with a running turn asks "Stop the turn and close?"; quitting asks too (`confirmQuitAiBusy`).
- Closed AI tabs are not offered by the "reopen closed tab" feature (ruling B10; `terminal/closed_items.dart:329,360`).
- Per-folder history: the header's History button -> `AlertDialog` (`ui/ai/ai_history.dart:21-84`): the agent's `session/list {cwd}` for THIS tab's folder, first page only (no "load more"), rows "title / 2026-10-13 09:30", the current one marked "current session", a tap opens a new AI tab (same agent, same folder, `session/load`). Needs the agent running and advertising `sessionCapabilities.list`, otherwise "{agent} does not list its sessions."

### 1.6 How an AI session relates to terminal workspaces, tabs and folders

```
Workspace  (settings key terminal_workspaces: JSON {id,name,collapsed,ssh?,zoom?,root?} per element)
  |   root  = default start folder for NEW local tabs (terminal AND AI) created in this workspace
  |   ssh   = SshTarget key for a server workspace (AI tabs are not opened there by default, B8)
  +-- tab ids in sidebar order (membership lives in memory; layout.json "workspaces[].tabs" restores it)
        +-- terminal tab : id = daemon session id; PaneSession{cwd from shell, gitBranch, ports,...}
        +-- AI tab       : TerminalTab(kind: ai), id >= 2_000_000_000 (kSyntheticTabIdBase), one AI pane
                           aiPanes{ -N : AiPaneState{agentId, agentName, title, cwd?, sessionId?} }
                           + optionally ONE terminal pane under it (header "Terminal", 72% / 28%, cwd = AI folder)
```

- Code: `terminal/terminal_tabs.dart:362-480` (`TerminalTab`, `TerminalTab.ai` at 378, `isAi` 432, `cwd` 462: "an AI tab's folder is its session's", `gitBranch` 463: null for AI), `terminal/terminal_tabs_ai.dart:18-52` (`openAiTab`), `:69-104` (`addAiTerminal`), `ai/ai_pane_state.dart:4-83` (AI pane ids are negative so they never meet session ids).
- A new AI tab is placed by the sidebar's `_reconcile` (`sidebar_workspaces.dart:776-850`) in the workspace passed as `workspace:` (written into `restorePlacementProvider.pending`), else the "current" workspace. It is NOT placed by folder: nothing maps `cwd` back to a workspace except the phone's `path:<cwd>` key (`ai/ai_phone.dart:268-278`).
- The conversation is never stored by ShellX. `layout.json` (macOS `<app support>/restore/layout.json`, `restore/restore_paths.dart`) keeps top-level `aiTabs[]` with `{key, title, name?, agent, agentName, session?, cwd?, pinned?, desc?, status?, layout:{ai:key}}` (`restore/restore_snapshot.dart:161-260`) and `workspaces[]` with tab keys only (`:265-272`); V1 ignores unknown top-level keys (that is why `aiTabs` and `toolDock` are top-level keys). On restart the tab appears with its title and the agent runs when the tab is first shown, then `session/load` replays history ("Resume session" card, `ai_pane_view.dart:758-808`).
- AI panes report into the same A12 status model as terminal agents (badges, notifications, CLI events) except custom agents (ruling B5); `shellx ui.ls` lists AI tabs as `kind:"ai"` with `cwd` (`cli/ui_command_handler.dart:210-212`) but does not expose a workspace `root`.
- Terminal-hosted agents (Claude Code typed into a terminal pane, A12 hooks, "resume offers") are a separate path from the AI tab.

### 1.7 Is there already a notion of "project"?

| Candidate | Exists? | Evidence |
|---|---|---|
| Workspace as project | Yes, with a folder | `Workspace.root` (cmux gap 36, commits `de94054`, `bb75e02`); Settings > Projects page (`projects_page.dart`) with "New project", name, "Project folder" (typed path), tab count, delete; sidebar workspace headers |
| "Project folder" for an AI tab | Yes, per tab | `AiPaneState.cwd`; strings "Choose a project folder", "The project folder no longer exists", "Undo is off for this project" |
| Per-project hidden git repo | Yes, internal | `CheckpointStores.forProject(cwd)` (`packages/shellx_ai/lib/src/host/checkpoint_store.dart:616`), id = first 12 hex chars of sha1(realpath) (`:588`) |
| Recent folders / recent projects | **No** | Only `ssh_recent_targets` (10 servers, `remote/ssh_settings.dart:5-43`, `platform/settings_store.dart:60`) and the command palette's in-memory 8 recent actions |
| Native folder picker | **No** | ruling B7 |
| Git repo detection for a chosen folder | **No** at choice time | branch only per terminal pane (section 4.2) |
| Project-level config | **No** | backlog: `.shellx/config` per project (`docs/superpowers/V2.md:36`) |
| Workspace groups / templates / prebuilt workspaces | **No** | backlog (`V2.md:19`, cmux gap list item 36 `docs/superpowers/research/2026-10-07-cmux-gap-analysis.md:219`) |
| Visible project name in the AI UI | **No** | header, sidebar row and Files panel never name the folder (see 1.4, 1.5); mobile header neither |

Naming collision to be aware of: the sidebar and CLI say "workspace", Settings, the AI undo texts, the phone's "Settings › Projects" hint (`aiNewNoFolders`) and V2-3's tool limit say "project".

### 1.8 ASCII sketch: current desktop window with an AI tab open

`[3]` layout: the V2-3 tool dock is the right-hand column; in `[2b]` that column, the header's tools button and the sidebar "Tools" group do not exist. Sizes: sidebar 220 px (`terminal_workspace_page.dart:1165-1223`, `[3]`), AI header 34 px, conversation column at most 760 px, side panel 268 px (toggle), composer 2 to 140 px, dock 45 % of the content area by default (`[3] tools/tool_dock_state.dart:11-15`, spec V2-3 D3). The AI header spans the conversation and the side panel; the tool dock sits beside the whole pane area.

```
+----------------------+------------------------------------------------------+-------------------+
| [gear] [bell] [+]    | AI header (34 px)                                    | TOOL DOCK (V2-3)  |
| (traffic lights)     | [*] Claude  Fix logout bug  ! Needs input            | [Board][Grafana] +|
|                      | [hist][panel][term][zoom][...][tools]                | Board :4000 local |
+----------------------+--------------------------------------------+---------+-------------------+
| Default (hdr: 2+ ws) | conversation (max 760 px, centred)         | PANEL   | <back><reload>..  |
| [*] Fix logout bug   |  You: ...                                  | 268 px  |                   |
|    Needs input.Claude|  Claude (markdown), > Thinking             | Changes |   (tool page,     |
| [*] Refactor api     |  [Edit src/main.ts +4 -1 waiting v]        | Files   |    default 45%    |
|    Done.Claude       |  Turn 1 . 0:41 . 2 files +44 -5 . View     | M a.ts  |    of the area,   |
| [>] zsh ~/shop main  |                                            | A b.ts  |    min 320 px)    |
+----------------------+--------------------------------------------+---------+                   |
| Tools (V2-3)         | dock: plan bar (folds open)                |         |                   |
|  Board localhost:4000| permission bar                             |         |                   |
|                      |  [1 Allow][2 Always][3 Reject Esc]         |         |                   |
| [intro card, once]   | queued rows (max 5)                        |         |                   |
|                      | +----------------------------------------+ |         |                   |
| [* New AI session][T]| | Message Claude... (@ file, / cmd)      | |         |                   |
|                      | | [@][/][Ask first v][Model v]  [Send]   | |         |                   |
|                      | +----------------------------------------+ |         |                   |
+----------------------+------------------------------------------------------+-------------------+
```

Legend: `[*]` sparkle mark of an AI tab (second line "{A12 state} . {agent}"); `[>]` a terminal tab (second line branch/path/ports); `[T]` the "Add tool" icon button (`[3]`); `Default (hdr: 2+ ws)` the workspace header, drawn only from two workspaces on; "[hist]" shows only when the agent lists sessions; "[zoom]" only in a split tab; a terminal pane appears below the AI pane (72 % / 28 %) after the "Terminal" button. There is no window-level tab strip or toolbar: the macOS traffic lights live in the sidebar's top band.

---

## 2. Mobile AI UI (V2-2 / V2-2b), `apps/mobile/lib` at `[2b]` 640141b

### 2.1 Strings the phone uses (`apps/mobile/lib/l10n/intl_en.arb`, `intl_vi.arb`; lines en:vi)

| Key | EN | VI |
|---|---|---|
| `aiGroup` (478:278), `aiChromeTooltip` (481:281) | AI sessions | Phiên AI |
| `aiNewSession` (479:279), `aiUntitled` | New AI session | Phiên AI mới |
| `aiNewAgent` (496:295) / `aiNewFolder` (497:296) / `aiNewStart` (498:297) | Agent / Folder / Start | Agent / Thư mục / Bắt đầu |
| `aiAgentNotReady` (501:300) | set up on the computer | cài trên máy tính |
| `aiNewNoFolders` (499:298) | Set a folder for a project on the computer first (Settings › Projects). | Hãy đặt thư mục cho một dự án trên máy tính trước (Cài đặt › Dự án). |
| `aiNewNoAgents` (500:299) | No agent is ready on the computer. Set one up in Settings › Agents. | Chưa có agent nào sẵn sàng trên máy tính. Hãy thiết lập trong Cài đặt › Agent. |
| `aiHistory` (647:411), `aiHistoryMore` (648:412) | Session history, Load more | Lịch sử phiên, Tải thêm |
| `aiHistoryEmpty` (649:413) | No earlier sessions in this folder. | Chưa có phiên nào trước đây trong thư mục này. |
| `aiHistoryNotReady` (650:414) | The history shows once the agent runs. | Lịch sử hiện khi agent đang chạy. |
| `aiChooseFolder` (652:416) | Choose a folder for this session | Chọn thư mục cho phiên này |
| `aiUseFolder` (651:415) | Use this folder | Dùng thư mục này |
| `aiStateNoFolder` (489:289) | Choose a folder on the computer | Chọn thư mục trên máy tính |
| `aiAttach` (653:417), `aiAttachPhoto`, `aiTakePhoto` | Add photos, Photo library, Camera | Thêm ảnh, Thư viện ảnh, Chụp ảnh |
| `aiMicTooltip` (667:429) | Speak a message | Nói tin nhắn |
| `aiComposerHint` (502:301) | Message {agent}… | Nhắn cho {agent}… |
| `aiConfigTitle` (637:402) | Mode and model | Chế độ và model |
| `aiPermTitle` (565:349) | {agent} asks: | {agent} xin quyền: |
| `aiUnavailable` (494:293) / `aiUpdateDesktop` (495:294) | Open ShellX on the computer to use AI sessions. / Update ShellX on the computer to use AI sessions from your phone. | Mở ShellX trên máy tính để dùng phiên AI. / Cập nhật ShellX trên máy tính để dùng phiên AI từ điện thoại. |

State words (`aiState*`): Running / Needs your answer / Waiting / Starting / Not started / Sign in on the computer / Error / Choose a folder on the computer / Agent off on the computer / Closed (VI Đang chạy / Cần bạn trả lời / Đang chờ / Đang khởi động / Chưa chạy / Cần đăng nhập trên máy tính / Lỗi / Chọn thư mục trên máy tính / Agent đang tắt trên máy tính / Đã đóng). Row subtitle `aiRowSubtitle` = "{agent} · {state}".

### 2.2 Entry points and the session picker

- AI is reached from the machine's terminal page, not from a separate tab bar: the `+` button opens the session picker (`features/terminal/presentation/pages/terminal_page.dart:187-215`, `_pick`), and a sparkle button with a yellow count of waiting sessions (`_AiButton`, `:634-654`, key `terminal-ai`, tooltip "AI sessions") opens the same picker; it only shows when the desktop's listing says `available` (a window serves AI). Tapping a push notification opens a session directly (`features/notifications/presentation/notification_opener.dart`).
- Picker = modal bottom sheet (`features/terminal/presentation/widgets/session_picker.dart:64-161`): title "This computer has N sessions" (terminals + AI), then a group header "AI SESSIONS" (uppercased `aiGroup`) first, then desktop terminals, then ShellX sessions, then "New session". AI rows (`_AiRow`, `:197-257`): sparkle icon (warning colour when the session needs an answer), title (or "New AI session"), subtitle "Claude · Needs your answer", the waiting task on a third line, and "Open". The last AI row is "+ New AI session" only when at least one agent is ready AND the desktop offers at least one folder (`:166-193`); otherwise a hint (`aiNewNoFolders` / `aiNewNoAgents`). Old desktop -> hint `aiUpdateDesktop`; no window -> `aiUnavailable`.
- "New AI session" sheet (`features/ai/presentation/widgets/ai_new_session_sheet.dart`): two `RadioGroup`s, "AGENT" (all agents the desktop lists; not-ready ones are disabled with "set up on the computer"; default = the desktop's `default_agent` if ready, else the first ready) and "FOLDER" (the desktop's folder choices, name + path, first preselected), button "Start" (key `ai-new-start`). Result -> `ai.open {agent, folder}` -> the page opens the new session. A request that may or may not have gone through says so and is never repeated by itself (V2-2 D13).
- The machine list (home screen) shows no AI row at the committed HEAD; B21 (a line "✦ 2 phiên AI · 1 cần bạn" under each online machine, tap = the waiting session or the AI chooser, `openAiChooser` in `ai_chooser.dart`) is in the uncommitted working tree (see section 0).

### 2.3 The AI session page (`features/ai/presentation/pages/ai_session_page.dart`)

Four independently watched parts: header, strips, conversation, dock (`build` at `:301-323`).

- Header (`_Header`, `:635-739`): back arrow, session title (or "New AI session"), a "⋯" menu (`PopupMenuButton`, key `ai.menu`) that currently holds one entry, "Session history" (B20's "Changes" entry is not there yet), and a status line "dot + Claude · Running · 0:12 · Ask first · <model> · Context 16%" (`_subtitle`, `:352-369`). When the computer offers `config`, the whole line is a 44 pt button with a caret that opens "Mode and model" (`ai_config_sheet.dart`: radio groups for mode, model, thinking and the agent's switches; never an option that acts without asking, `on_computer` refusal text otherwise). The folder is not shown.
- Strips (`_strips`, `:374-407`): connection banner, "Computer is offline…", "Reconnecting… what you see may be behind.", closed-session text with a button "Open the session list" (B22), "Reconnected after ShellX restarted."
- Conversation (`_conversation`, `:409-488`; `ai_timeline.dart`): virtualized, anchored so streaming below or "Load more" above never moves what is read; "Latest" button; user bubble on the right (+ "from phone" label for phone-sent messages), agent markdown, folded "Thinking", tool cards (tap = diff / output / input; "View all" when cut, B16), question line, turn-end line "Turn 3 · 0:41 · 2 files changed +44 −5", notices.
- Dock (`_dock`, `:490-577`): a scrollable column limited to half the screen height holding `AiPlanStrip` ("Plan · 2/5", tap to open), then EITHER `AiPermissionPanel` OR `AiAskPanel`, then `AiQueueRow`; under it the `AiComposer`.
  - `AiPermissionPanel` (`features/ai/presentation/widgets/ai_dock.dart:48-220`): warning-soft card "Claude asks:", the task in bold (3 lines), "N more waiting", one full-width button per option in the agent's order (min height 52 pt; allow-once filled, reject outlined in red, "always" shows the agent's own wording); buttons wait 400 ms after a panel appears or changes and while an answer travels; "Details" scrolls to the tool card; a request without options says "Answer this request on the computer."
  - `AiAskPanel` (`:227-430`): the agent's form (string, number, switch, radio, checkboxes) with "Send answer" and "Decline"; URL or oversized forms say "Answer this question on the computer."
- Composer (`AiComposer`, `ai_dock.dart:496-722`): `Row[ attach (add_photo_alternate_outlined, only if the desktop offers `blob`), TextField (1..6 lines, hint "Message Claude…"), mic (`mic_none`, filled `mic` while listening), force-stop, Stop OR Send/Queue (arrow-up / playlist-add) ]`; above the row: `@` suggestions (up to 8, 4 visible, `_Suggestions` `:792`), the image thumbnails row (`_ImageRow` `:725`), an upload progress bar, and one note line in the error colour. Stop replaces Send only when the field and the image list are empty and a turn runs.

### 2.4 History ("Lịch sử phiên", B17) and "Dùng thư mục này" (B18)

- History: header menu entry (`ai_session_page.dart:342-345`, key `ai.menu.history`) shown only when the session is not closed, the header says `hist` (agent lists sessions) and the desktop's listing names feature `history`. `showAiHistorySheet` (`ai_history_sheet.dart:13-155`): title "Session history", pages of up to 50 sessions (title or "New AI session", date) with "Load more", the open session hidden; spinner while loading (never "no earlier sessions" before the first page), `not_ready` -> "The history shows once the agent runs." and a retry when the header shows the agent running, empty -> "No earlier sessions in this folder.". A tap returns the agent's session id; `AiSessionController.resume` (`ai_session_controller.dart:311-323`) finds the listing folder whose `path == head.cwd` and sends `ai.open {agent, folder, resume: <acp>}`; the desktop opens a new AI tab WITHOUT selecting it and the phone replaces the page with the new session (`ai_session_page.dart:279-298`). So the **folder path is the join key** between a session and the desktop's folder list.
- Choose folder: only for a session whose tab has no folder (`AiRemoteState.noFolder`). The conversation area shows `AiFolderChooser` (`ai_folder_chooser.dart:7-69`): "Choose a folder for this session", the desktop's folders as radio rows (name + path), button "Use this folder" (`ai_session_page.dart:427-438`, needs live link, a non-empty folder list and feature `folder`). Without that it shows the plain text "Choose a folder on the computer" and no composer. Desktop side: `DesktopAiSource.chooseFolder` (`apps/desktop/lib/src/ai/ai_phone.dart:253-266`) does what the tab's own "Use this folder" does.

### 2.5 Attachments and voice

- Photos (B12): attach sheet "Photo library / Camera" (`ai_attach_sheet.dart`); at most 5 images, 10 MB each, 20 MB per message (`kAiMessageImageBytes`, `features/ai/domain/ai_attachments.dart:13`), only JPEG/PNG/GIF/WebP, re-encoded to 2048 px / quality 85 without metadata (`aiWithoutMetadata`, F38); uploaded in parts over `ai.blob`, then `ai.prompt {blobs}`; failures keep text and images and are never auto-resent. Gated by feature `blob` and the agent taking images.
- `@` files (B13): typing `@query` asks `ai.files` after 150 ms (feature `files`), suggestions are paths inside the session folder that the desktop offered; a pick inserts `@path ` and the path goes along as a `resource_link` while still mentioned (`ai_session_page.dart:237-275`, `AiMentions` in `ai_attachments.dart`). No arbitrary files (PDF etc.) and no `@` for folders (V2-2b "Ngoài" list, spec line 252).
- Voice (B14): the mic icon inside the composer (`ai_dock.dart:676-690`) -> `AiDictation` (`features/ai/presentation/controllers/ai_dictation.dart`) which reuses `SpeechInput` and `VoiceCommandParser` (`features/voice/**`); partial/final text is appended to the field; saying "gửi"/"send" at the end sends; listening stops on a lost link, a closed session, leaving the page, backgrounding and Send. This is separate from the terminal page's `VoiceComposer` bar. Errors reuse the terminal's voice words (`voiceNoPermission` ...). The mic is not protocol-gated.

### 2.6 ASCII sketch: the AI session page

Top to bottom: header (back, title, menu, status line), strips, conversation, then the dock (panels, queue) and the composer. The panel stack scrolls inside at most half of the screen height; the composer never scrolls away.

```
+------------------------------------------------+
| <  Fix logout button                     [...] |
|    o Claude . Running . 0:12 . Ask first       |
|      . Opus . Context 16%                    v |
+------------------------------------------------+
| [strip] Reconnecting... / computer offline /   |
|   closed + [Open the session list]             |
|                    Load more                   |
|                   +---------------------------+|
|                   | user bubble (from phone)  ||
|                   +---------------------------+|
|  Claude (markdown, selectable)                 |
|  > Thinking                                    |
|  [Edit main.ts                waiting for you] |
|  Turn 3 . 0:41 . 2 files changed +44 -5        |
|                                       [Latest] |
+------------------------------------------------+
| Plan . 2/5                                   ^ |
| +--------------------------------------------+ |
| | Claude asks:                               | |
| | Edit src/main.ts                           | |
| | [              Allow               ]       | |
| | [           Always allow           ]       | |
| | [              Reject              ]       | |
| |               Details                      | |
| +--------------------------------------------+ |
| Queued: "..."                                x |
| @src/main.ts  @src/app.ts   (suggestions)      |
| [img][img]   (note line / upload progress)     |
| [+img] ( Message Claude...        ) [mic] [^]  |
+------------------------------------------------+
```

Labels in the app (VI): "Phiên AI mới" for an empty title, status "Claude · Đang chạy · 0:12 · Hỏi trước · Opus · Ngữ cảnh 16%", "Tải thêm", "Mới nhất", "Kế hoạch · 2/5", "Claude xin quyền:", "Cho phép / Luôn cho phép / Từ chối", "Xem chi tiết", "Nhắn cho Claude…". The attach button only shows when the desktop offers images (`blob`); the mic always shows; Stop replaces Send when the field is empty and a turn runs.

Picker (left) and "New AI session" sheet (right), both modal bottom sheets over the terminal page (`[*]` = sparkle icon):

```
+----------------------------------------------+   +---------------------------------------------+
| This computer has 3 sessions                 |   | New AI session                              |
| Reopen a session ... or start a new one.     |   | AGENT                                       |
| AI SESSIONS                                  |   |   (o) Claude                                |
|   [*] Fix logout button                 Open |   |   ( ) Codex   set up on the computer        |
|       Claude . Needs your answer             |   | FOLDER                                      |
|       Edit src/main.ts                       |   |   (o) shop-web   /Users/me/shop-web         |
|   [+] New AI session                         |   |   ( ) api        /Users/me/api              |
| TERMINALS ON THE COMPUTER ...                |   |   [              Start               ]      |
| SHELLX SESSIONS ...  [ + New session ]       |   |                                             |
+----------------------------------------------+   +---------------------------------------------+
```

---

## 3. Specs: key UI decisions and explicit "not now" items

Files: `docs/superpowers/specs/2026-10-14-ai-pane-design.md` (V2-1), `2026-10-14-v2-2-phone-ai-design.md` (V2-2), `2026-10-15-v2-2b-phone-ai-more-design.md` (V2-2b), plus `2026-10-15-v2-3-tools-desktop-design.md`, `2026-10-15-v2-4-tools-phone-design.md`. Plan rulings B1-B16 of V2-1b: `docs/superpowers/plans/2026-10-14-v2-ai-desktop.md:59-74`.

### 3.1 V2-1 (desktop AI tab), `ai-pane-design.md`

Key UI decisions (line):
- D2 (119): an AI tab is a kind of tab (`TerminalTab.kind`), synthetic id above 2e9, getters (`label`, `cwd`) route to the AI pane. D3 (120): the AI pane is a negative leaf, exactly one per tab; "Terminal" button adds a terminal pane below (72/28); closing the AI pane closes the tab; its "cost if wrong" column says that wanting several sessions side by side means one tab per session, judged enough for V2-1.
- D4 (121): setting `new-tab-kind` (terminal|ai, default terminal) + onboarding question + one-time card. D5 (122): open via Cmd+Shift+E, sidebar button, `+` menu; with `new-tab-kind=ai` the `+`, Cmd+T and the empty state open AI; folder = `Workspace.root`, else the focused tab's folder, else the pane shows the card "Choose a project folder" before running the agent; agent = default (D23, line 140).
- D7 (124) Settings > Agents "AI interface" with per-agent status and Install/Sign in in the run sheet; D8 (125) sign-in in an in-pane mini terminal; D10 (127) permission labels from `kind`, digits and Esc, never auto-allow; D11 (128) mode/model chips from `configOptions`, Bypass behind a confirmation; D14 (131) restore via `aiTabs`, agent starts lazily, no conversation stored; D15 (132) History button via `session/list {cwd}`; D16 (133) composer rules (`@` files, `/` commands, images, queue of 5); D18 (135) Changes and Files panels; D21 (138) the menu shows "Claude", never "Claude Code" in the feature name, switch `ai-agent-claude`; D23 (140) known agents list and "first Ready" default.
- §4.1 (148-162) layout (header 34 px, column 760 px, panel 268 px, dock order plan > permission > queue > composer), §4.2 (164-191) cards per `kind`, §4.3 (193-202) permission bar, §4.4 (204-214) Changes/Files panels, §4.5 (216-225) notice cards incl. "Folder gone -> button Choose folder", §4.7 (253-269) every reader of a tab that had to learn "no terminal pane".
- D12 (129): restore points = one hidden git repo per project (`GIT_DIR=<support>/ai/checkpoints/<sha1(realpath)[:12]>`), scope follows `.gitignore`, nested repos excluded, off above 200 000 files or a first snapshot over 30 s, never touches the project's `.git`.

Explicit "not now / out of scope" relevant to projects and folders:
- §10 (376): "Worktree riêng cho từng phiên; nhiều pane AI trong một tab." (a separate worktree per session; several AI panes in one tab). Also §10: no editor/LSP, no ACP `fs/*` and `terminal/*`, no install from the ACP registry, no bundled Node.
- §6 (301): folder gone on restore -> card "Thư mục không còn" with a Choose folder button. (304): two AI tabs on the same project -> git operations are serialised, each compares with its own restore point. (305): "Agent ghi ra ngoài thư mục dự án: Không theo dõi" (writes outside the project folder are not tracked).
- Plan ruling B7 (plan:65): typed path, no native picker, "Cost if wrong: add `file_selector` later". B8 (plan:66): in an SSH workspace `new_tab` and `+` stay terminal tabs even with `new-tab-kind=ai`, because the agent runs on this computer while the workspace's folder is on the server. B10 (plan:68): closed AI tabs are not offered by Cmd+Shift+T.
- Final review I-1 (`ai/ai_paths.dart:25-31`): home folder, folders above it and disk roots are never taken as the default project (undo off, no `@` index) but a user who types one is obeyed.
- `docs/superpowers/V2.md:36` backlog: project-level config `.shellx/config` (needs a trust prompt), `:19` workspace groups (fold/pin), layout templates, prebuilt workspaces / "create workspace" commands.

### 3.2 V2-2 (phone AI), `v2-2-phone-ai-design.md`

- D8 (95): the session page is its own route over the terminal page, not a tab among terminal tabs. D10 (97): entry points are the session picker ("Phiên AI" group first, then "Phiên AI mới"), a sparkle button with a count on the terminal page, push taps; the machine list is unchanged (list rows came later as B21). §5.1-5.4 (185-231): picker, session page, permission panel (>= 52 pt buttons), question panel.
- **D9 (96)**: a new session from the phone needs "an agent the computer reports ready" and "a folder the computer offers: the project roots of the local workspaces plus the folders of the open AI tabs. The phone sends a key (`ws:<id>` or `path:<dir>`), never a typed path. The new tab goes into the right workspace, is NOT selected on the computer, and the agent starts at once." Cost if wrong (explicit): "Dự án chưa thuộc workspace nào phải đặt gốc trên máy tính trước" (a project that is not a workspace yet must get its root on the computer first).
- D13 (100): the phone cannot change mode or model in V2-2a, so Bypass cannot be turned on from it. D14 (101): a session that cannot run (no folder / agent off) shows the sentence only, no composer. D16 (103): after a desktop restart the old `sid` is gone; the listing carries `acp` so V2-2b can re-attach.
- §11.2 (378-390) deferred to V2-2b: reply from the push notification, mode/model from the phone, images/files/voice, Changes and undo on the phone, "view full card", **"Lịch sử phiên (session/list), chọn thư mục cho tab chưa có thư mục"** (387), AI sessions on the machine list, auto re-attach, "You · from phone" on the desktop.

### 3.3 V2-2b (more phone AI), `v2-2b-phone-ai-more-design.md`

- B1 (75): a phone uses a V2-2b feature only if both the relay-holding process reports `ai: 2` and the window's listing names the feature in `f` (config, blob, files, changes, revert, item, history, folder, push_answer, acp_head).
- B11 (85) mode/model sheet, bypass never listed; B12 (86) images (<= 5, library + camera, 2048 px, JPEG q85); B13 (87) `@` files (<= 8 suggestions, only inside the session folder, re-checked on the desktop); B14 (88) mic reusing `SpeechInput`, "gửi"/"send" sends; B16 (90) "Xem đủ"; **B17 (91)** history `ai.history {sid, cursor?}` -> `{sessions:[{acp,title,at}], next?, current?}` (50 per page, titles <= 120 chars; agent not ready -> `not_ready`; no `session/list` -> button hidden; open = `ai.open {resume}` + the session's folder key -> a new desktop tab, `select:false`); **B18 (92)** `ai.folder {sid, rid, folder}` for `no_folder` tabs, same effect as the tab's "Use this folder"; B19/B20 (93-94) Changes/Revert (pending in code); B21 (95) machine list AI line for up to 6 online machines (uncommitted in `[2b]` when read); B22/B23 (96-97) re-attach after a desktop restart by matching `acp` + agent + folder (exactly one match, else "Open the session list"); B24 (98) "You · from your phone".
- Out of V2-2b (252): answering without opening the app, arbitrary files from the phone (PDF…), `@` for folders, showing which phone sent a message.

### 3.4 V2-3 / V2-4 (tools; they touch the workspace/project concept)

- V2-3 `§2` row "Workspace" (52): `Workspace {id, name, collapsed, ssh, zoom, root}` is saved in `terminal_workspaces`; `encode()` writes only known keys, so an older build that edits a workspace drops unknown keys -> **D2 (69)** keeps tools in their own key `workspace_tools` instead of inside the workspace JSON. (Same constraint applies to any new per-project field.)
- D3 (70): the tool dock is a third column to the right of the pane area, one dock per workspace; D4 (71): opening a tool of another workspace selects that workspace's nearest tab (or shows a "loose" empty panel); D12 (79): port suggestions per workspace; D21 (88): a "Tools" group under each workspace in the sidebar and an "Add tool" button next to "New AI session"; D22 (89): Settings > Projects cards also list the project's tools; limit string "This project already has {count} tools."
- Out of V2-3 (253-257): tools in SSH workspaces (except via a forwarded URL typed by the user), two tools side by side, agent control of tools, tool downloads.
- V2-4: E1 (62) the phone opens tools by id; E4 (65) when one tool is open the phone also serves every enabled tool of the same workspace; `tool.list.result` carries `ws` (workspace name) and `group` (`ws:<id>`) (lines 109-117), so V2-4 is the first place the phone learns the workspace grouping.

---

## 4. What "choose a project to work in" could map to here

### 4.0 Candidate mappings, from what the code already has

"Project" could be bound to one of three existing things; each has a different amount of machinery behind it.

| Candidate | What exists to build on | What is missing |
|---|---|---|
| **A. Workspace = project** (sidebar group) | Persisted list with name and `root` (`terminal_workspaces`); headers, collapse, drag, rename, delete, CLI create; Settings > Projects page; AI tabs and V2-3 tools already hang off it (`workspace:` argument of `openAiTab`, `workspace_tools`, `toolDock`); the phone's `ws:<id>` keys | A creation flow that takes a folder (Settings > Projects needs a typed path); AI tabs are placed by "current workspace", not by folder; headers are hidden while only Default exists; SSH workspaces have no AI; no visible project name in the AI pane |
| **B. Folder = project** (`AiPaneState.cwd`) | It already keys restore points (sha1 of realpath), agent history (`session/list {cwd}`), the phone's `path:<cwd>` keys and `resume` matching (`f.path == head.cwd`); validity checks (absolute, exists; home and disk roots are refused only as an automatic default, a typed one is obeyed with undo off); "folder gone" card | A list of known folders (no recents, no registry of closed tabs' folders), a native picker, any display of the folder in the AI header or row |
| **C. Git repo = project** | Branch reader per terminal pane (`GitHeadReader`), `gh` PR status, hidden per-project checkpoint repo, `.gitignore` matcher | Repo-root detection for a chosen folder, repo name/branch on AI tabs, worktree awareness (spec V2-1 §10 puts per-session worktrees out of scope); ACP `additionalDirectories` is unused |

Where a chooser could attach (current choke points):
- Desktop "where does a new AI session go": `AiOpener.newSession` (`ai/ai_open.dart:27-63`) is the single path for Cmd+Shift+E, the sidebar button, the `+` menu, the palette, workspace-header `+`, Cmd+T and the empty state. Two paths do NOT go through it and call `openAiTab` directly: the History dialog (`ui/ai/ai_pane_view.dart:371-389`) and the phone (`ai/ai_phone.dart:213-245`).
- Where the user types a folder today: `AiFolderCard` (`ui/ai/ai_folder_card.dart`), shown in-pane only when no folder could be derived.
- Where projects are created and given a folder today: Settings > Projects (`ui/settings/pages/projects_page.dart`).
- What the phone sees as "projects": `DesktopAiSource.folders` (`ai/ai_phone.dart:159-184`), the only producer of `AiListing.folders`.
- Per-folder history: `showAiHistory` (desktop) and `ai.history` / `showAiHistorySheet` (phone, `apps/mobile/lib/features/ai/presentation/widgets/ai_history_sheet.dart`), both on `AiRuntime.listSessions` (`packages/shellx_ai/lib/src/host/ai_runtime.dart:739-745`).

### 4.1 Data that already exists and where it is persisted

| Data | Where persisted / source | Shape and notes |
|---|---|---|
| Workspace (= project) list | `shared_preferences` key `terminal_workspaces` (`platform/settings_store.dart:34`, UI-owned in `UiSettingKeys`; encode `terminal/sidebar_workspaces.dart:84-91`, decode `:94-136`) | JSON per element `{id, name?, collapsed, ssh?, zoom?, root?}`; Default workspace always present and cannot be deleted; created from the sidebar, Settings > Projects ("New project") or the CLI (`ui.workspace.new`, `createFor` `:405`) |
| Project root | `Workspace.root` inside the above; `SidebarWorkspaces.setRoot` (`:513-526`) | Typed path in Settings > Projects only (no picker); used for NEW local tabs (`openTabIn` `:480-496`, `AiOpener.newSession`) |
| Which tab belongs to which workspace | in memory; restored from `layout.json` `workspaces[].tabs` (`restore/restore_snapshot.dart:265-272`) | |
| An AI tab's agent/folder/session | `layout.json` `aiTabs[]` (`restore_snapshot.dart:161-260`): `key, title, name, agent, agentName, session, cwd, pinned, desc, status` | only open tabs; closed tabs vanish; conversation never stored |
| AI default agent, custom agents, remembered per-agent choices, intro flag | `ai_default_agent`, `ai_custom_agents`, `ai_agent_config`, `ai_intro_shown` (`settings_store.dart:100-111`) | config-file keys: `new-tab-kind`, `ai-agent-claude`, `ai-checkpoint-days` |
| Tools per workspace | `workspace_tools` (`[3] settings_store.dart:115`), dock state in `layout.json` `toolDock` | V2-3 |
| Restore points per project folder | `<support>/ai/checkpoints/<sha1(realpath)[:12]>/` with `shellx.json {project, off?}` (`checkpoint_store.dart:588`, `:493`); pruned after `ai-checkpoint-days` (default 14) and when the project folder is gone (`pruneAll` `:638-659`) | incidentally the only on-disk list of "folders an agent worked in recently", but it is pruned, internal and not exposed |
| Session history per folder | NOT stored by ShellX. Asked live from the agent: `AiRuntime.listSessions` -> ACP `session/list` with `cwd` = the tab's folder (`packages/shellx_ai/lib/src/host/ai_runtime.dart:739-745`) | needs a running agent that advertises `sessionCapabilities.list`; desktop shows page 1 only, phone pages by cursor |
| Recent folders | **none** | pattern to copy if wanted: `ssh_recent_targets` (newest first, max 10, `remote/ssh_settings.dart:5-43`) |
| Global default start folder | config file `working-directory` (home / inherit / path) | terminal tabs only |
| Folder safety rules | `isBroadFolder` (home, above home, disk roots; `broad_folder.dart:11`), `aiFolderIsBroad` (`ai/ai_paths.dart:32`), `aiFolderFrom`/`aiFolderExistsProvider` (`ai/ai_folders.dart`) | |

Persistence constraints worth knowing:
- New settings keys must be added to `SettingKeys.all` (the shared_preferences allow-list) and to `UiSettingKeys` (A5b: with the background service each key has exactly one writing process; see `platform/settings_store.dart:133-215` and `settings_ownership_test.dart`).
- `layout.json`: old builds ignore unknown TOP-LEVEL keys but rename the whole file to `.bak` on an unknown node inside a tab tree (V2-1 §2 row "layout.json", V2-3 §2 row "Khôi phục"); that is why `aiTabs` and `toolDock` are top-level keys.
- Workspace JSON is lossy for older builds (V2-3 §2, D2).

### 4.2 What the desktop knows about git repositories

- Per terminal pane only: `GitHeadReader` (`packages/shellx_agent/lib/src/context/git_head.dart:91`, interface `GitBranchLookup.branchFor` `:14`) walks up from the pane's cwd (max 64 levels, follows `gitdir:` files of worktrees/submodules, 500 ms timeout, LRU 64) and reads `.git/HEAD`; wired in `apps/desktop/lib/src/agent/agent_side.dart:92`. Result -> `PaneSession.gitBranch`, shown in the terminal row's context line and sent to phones in `session.list` (`SessionInfo.branch`/`cwd`, `packages/shellx_core/lib/src/protocol/messages.dart:182-228`; the mobile UI does not display them).
- AI tabs: `TerminalTab.gitBranch => isAi ? null : ...` (`terminal_tabs.dart:463`); the sidebar AI row hides branch/ports; no AI header shows a branch; the folder card does not check that the folder is a repo.
- Opt-in PR status via `gh pr view` per terminal tab (`integrations/pr_status.dart`, setting `pr-status`, `config/settings_schema.dart:626`).
- The AI host's own git usage is separate and private: `GitLocator` finds git on the login-shell PATH; `CheckpointStore` runs every command with `GIT_DIR=<hidden>` and `GIT_WORK_TREE=<project>` and never touches the project's `.git` (`checkpoint_store.dart:62-67`, spec D12); nested repositories are excluded from snapshots.
- `.gitignore` is parsed by ShellX's own matcher (`ai/ai_gitignore.dart`) for the `@` index and the Files panel (ruling B12), not by git.
- No repo-root detection, no "is this folder a repo", no worktree awareness for AI sessions. ACP 1.25.0 (the pinned schema `packages/shellx_acp/test/fixtures/acp-schema-1.25.0.json`) has `additionalDirectories` on `session/new` and `session/load`, plus `session/resume`/`close`/`delete`; ShellX uses none of them.

### 4.3 What the phone can already ask the desktop for

Wire (all inside the end-to-end channel; kinds in `packages/shellx_core/lib/src/protocol/ai_messages.dart`, handled by `AiPhoneHub` `packages/shellx_agent/lib/src/ai/ai_phone_hub.dart:546-615`):

| Request | Returns | Project/folder relevance |
|---|---|---|
| `ai.list` (then pushed on every change) | `AiListing` (`packages/shellx_ai/lib/src/remote/listing.dart:63-330`): `sessions[{sid, agent, name, title, state, cwd?, since?, waiting?, acp?}]`, `agents[{id,name,ready}]`, **`folders[{key, name, path}]`**, `default_agent`, `f` (features) | `folders` = workspace roots (`ws:<id>`, name = workspace name) plus the `cwd` of every open AI tab (`path:<cwd>`, name = last path segment), built in `apps/desktop/lib/src/ai/ai_phone.dart:159-184`; SSH workspaces excluded; a folder with no workspace root and no open AI tab is invisible to the phone |
| `ai.open {agent, folder, resume?}` | `ai.result {sid}` | folder must be a current key; tab goes to the workspace of `ws:<id>` or of the AI tab with that cwd (`_workspaceFor`, `ai_phone.dart:268-278`), unselected, agent started |
| `ai.history {sid, cursor?}` | `{sessions:[{acp,title,at}], next?, current?}` for the session's folder | uses `session/list {cwd}`; `cwd` of each past session is dropped on the wire (`history_view.dart` encode) |
| `ai.folder {sid, folder}` | ok / refused | only for tabs with no folder; key must be offered |
| `ai.files {sid, q}` | up to 8 relative paths inside the session folder | |
| `ai.config.get` / `ai.config` | mode/model choices (never a no-approval mode) | |
| `ai.prompt`, `ai.blob`, `ai.answer`, `ai.cancel`, `ai.stop`, `ai.unqueue`, `ai.item`, `ai.attach/detach/ack/earlier` | session control and mirroring | |
| `ai.changes`, `ai.diff`, `ai.revert` | stubbed with `_refuse` at `[2b]` 640141b (B19 pending) | |
| `session.list {desktop:true}` (terminals) | per terminal: `cwd`, `branch`, agent chip | on the wire, not displayed by the mobile app |
| `tool.list` (V2-4, not in `[2b]`) | tools with `ws` name and `group: ws:<id>` | first wire field carrying workspace grouping |

Not available to the phone: browsing or listing arbitrary directories, typing a path, a recents list, creating or renaming a workspace/project, setting a workspace root, any git information for AI sessions, or the workspace id/name of a session (there is no workspace field on `AiSessionInfo`; only `AiFolderChoice.name` carries the workspace's name). By design: "the phone sends a key, never a path" (V2-2 D9).

### 4.4 Observations that matter for a "choose a project" design (facts, no decision)

1. Three possible meanings of "project" already exist and none is the identity of a session: the workspace (named group of tabs, optional `root`), the folder path (`AiPaneState.cwd`, the real unit of undo, history and the phone's `resume` join), and the git repository (only a branch label on terminal panes). Today the folder path is what actually keys restore points, agent history (`session/list {cwd}`) and the phone's folder keys.
2. Starting an AI session never asks "where" unless both the workspace root and the front tab's folder are missing. With a single (Default) workspace the sidebar shows no project grouping, and neither the AI header nor the AI sidebar row shows the folder, so a session's project is invisible in the UI on both desktop and phone.
3. The only existing UI that creates/names a project and sets its folder is Settings > Projects (typed path). The AI folder card's "Use this folder" updates the tab, not `Workspace.root`, and does not remember the choice anywhere.
4. A session picker per project would have to be assembled from: open tabs (sidebar membership, in memory + `layout.json`), the agent's `session/list` (live agent required, desktop page 1 only), and, if wanted, a new persisted "recent folders" list (none exists; model on `ssh_recent_targets`). `shellx_acp`'s `listSessions({cwd?, cursor?})` already allows an unfiltered call and `SessionSummary.cwd` is parsed (`packages/shellx_acp/lib/src/acp_client.dart:103`, `acp_types.dart:356`), but ShellX always passes the tab's folder and the repository has no test of what Claude's adapter returns for an omitted `cwd`.
5. Adding a folder picker on the desktop is a known, pre-agreed follow-up (ruling B7, `file_selector`); `desktop_drop` and `pasteboard` are already dependencies.
6. Phone side: the folder list is already an abstraction over "project" (key + name + path), derived from workspaces and open tabs; widening it (recent folders, git-aware names) would be a desktop-only change to `DesktopAiSource.folders` plus the listing size limits (`listing.dart` cuts names to 200 and paths to 600 bytes; one body must stay under the 48 KiB message cap).
7. Existing guard rails to reuse: `aiFolderIsBroad`/`isBroadFolder`, folder-exists check, the SSH exception (B8), the "folder gone" card, and the per-folder hidden repo id.

### 4.5 Caveats

- Everything here is from reading code and specs; no app, build or test was run.
- Both `[2b]` and `[3]` are active worktrees: B19/B20, B21 and V2-3's Settings > Projects tool cards (spec D22) may land after this reading, and `[2b]` had uncommitted edits (B21) while I read it. At `[3]` a7df506 `ui/settings/pages/projects_page.dart` shows no tool list yet.
- Ledger/progress material for V2-2b lives outside git in `/Users/richard/Documents/helper/shellx/.superpowers/sdd/2026-10-15-v2-2b-phone-ai-more/` (task 26 manual-check list at `task-26-manual-checks.md`).

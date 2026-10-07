# cmux vs ShellX gap analysis (2026-10-07)

Sources: cmux-src = /Users/richardle/.claude/jobs/40d1af65/tmp/cmux-src (v0.65.0). ShellX status is from HANDOFF.md, the A1 ledger and a grep of apps/desktop/lib and apps/mobile/lib. Status marked (?) means "not found by grep, verify". The cmux `ghostty/` submodule is EMPTY in the shallow clone, so Ghostty-internal behaviour is described from the cmux side and from upstream knowledge, not cited from source.
HAVE = equivalent exists; PARTIAL = exists, gap noted; MISSING = none found.

## 1. Desktop feature inventory

### 1.1 Terminal core
| cmux feature (where) | ShellX |
|---|---|
| GPU terminal (libghostty) Sources/GhosttyTerminalView.swift | HAVE (xterm.dart 4.0.0 in Flutter; no GPU path, perf risk on heavy output; benchmark test exists) |
| Reads ~/.config/ghostty/config + cmux-only config.ghostty (docs/customizing-appearance.md) | HAVE (A9 Ghostty-syntax config) |
| Themes + `cmux themes` live picker, Settings > Theme > Choose | PARTIAL (config_theme.dart exists; no live-preview picker (?)) |
| font-family/size, font-feature (ligatures), adjust-cell-height, font-thicken | PARTIAL: family/size/fallbacks yes (terminal_style.dart); no font-feature, no cell-height adjust, no weight/thicken knob. See section 3a |
| Cursor style/blink, window-padding-*, transparency/blur/background-image | MISSING (?) (cursor style/blink/padding/opacity not in shellx_config.dart grep) |
| Font zoom Cmd+= / Cmd+- / 0, per-workspace Cmd+Ctrl+= | HAVE global (increase/decrease/reset_font_size); per-workspace MISSING |
| Find in terminal (Cmd+F, next/prev, selection-as-needle, `hideFind`) | MISSING (no find bar in lib/src/ui/terminal) |
| Global search incl. scrollback of all open terminals (0.65) | MISSING |
| Copy mode (vim keys, `toggleTerminalCopyMode`) | MISSING |
| Text selection: word/line double/triple click, shift-extend, Reflow-hard-wrap-on-copy | PARTIAL (xterm default selection only; verify double/triple click, rectangular) |
| URL / file-path detection, Cmd+click open, hover URL, right-click Reveal in Finder | MISSING (url_opener.dart exists only for app links; no link layer in pane_tree_view.dart) |
| OSC 8 hyperlinks | MISSING (?) |
| Image/file paste (Cmd+V of screenshot -> path; `pasteLastScreenshot`; oversized-image notice) docs/cloud-image-paste.md | MISSING (no clipboard-image handling) |
| Drag & drop file -> inserts shell-escaped path; drop on pane to split (Shift = split) docs/cross-rail-drag-drop.md | MISSING (drop only used for sidebar reorder) |
| Scrollback persisted/restored; scrollbar with agent-prompt markers (0.65) | PARTIAL (A5a scrollback_codec restores text; no scrollbar prompt markers) |
| Scroll position preserved on output / jump-to-bottom affordance, `clearScreenKeepScrollback` | verify (?) |
| Text-editing gestures: Cmd/Option+arrows/delete = line/word at prompt (terminal.textEditingGestures) | PARTIAL (Option+←/→ done in terminal_input.dart; Cmd+←/→/Backspace, Option+Backspace not) |
| Predictive local echo over slow SSH (underlined until confirmed) | MISSING (P2) |
| Password-input lock badge (echo off) | MISSING (P2, nice) |
| Bell handling / visual bell | PARTIAL (?) |
| IME composition, dead keys, Option-as-Alt | PARTIAL, user-reported bug. Section 3b |
| Kitty keyboard/graphics protocol (via Ghostty) | MISSING (xterm.dart lacks it) |
| Sync-output/DECSET 2026, true color, OSC 52, OSC 7 cwd | verify; OSC 7/title yes (cwd shown in sidebar) |

### 1.2 Workspaces, tabs, panes
| Feature | ShellX |
|---|---|
| Vertical sidebar: git branch, PR status/number, cwd, ports, latest notification text | PARTIAL: branch, cwd, ports, notification yes; linked PR status/number MISSING |
| Workspace rename (inline, Cmd+Shift+R), description, checklist/todos, status ("done"/cycle) | PARTIAL (rename yes via inline_name_field; description/status/todos MISSING) |
| Workspace groups (collapse, pinned, group-select) docs/workspace-groups.md | MISSING (P2) |
| Pinned workspaces, drag reorder, move up/down, select by Cmd+1..9, next/prev | PARTIAL (reorder yes; pin (?)) |
| Sidebar density/hover close button; active tab close always visible (TODO.md "UI/UX") | verify |
| Pane surface tab bar (tabs inside pane), wheel-scrolls sideways when overflowing | PARTIAL (A3 splits + tabs; verify tab strip overflow) |
| Splits right/down, focus L/R/U/D, resize, equalize, equalize-on-create, zoom pane | HAVE (goto_split, resize_split, equalize_splits, toggle_split_zoom); equalize-on-create option MISSING |
| Move surface between panes/workspaces/windows; "Swap with session"; break pane | MISSING (move tab to other workspace by drag/menu absent (?)) |
| Multiple windows, show/hide all (global hotkey), full screen | PARTIAL (window_coordinator exists; global show/hide hotkey MISSING) |
| Focus history Back/Forward/Last (`focusHistory*`) | MISSING |
| Reopen closed workspace/tab/browser panel (Cmd+Shift+T style, AppDelegate+ClosedItemHistory.swift) | MISSING |
| Saved layout templates; custom commands/workspaces in cmux.json (command palette launch) | PARTIAL (run_command user_commands.dart; no saved layout templates) |
| Free-form canvas layout (experimental) | MISSING, skip (P3) |
| Dock (right-sidebar pinned TUIs: Files, Find, Sessions, Feed, Dock, Machines) docs/dock.md | MISSING, skip/P2 (file explorer is the likely win) |
| Right sidebar Files explorer + file preview/editor/markdown/diff viewer | MISSING (P2) |

### 1.3 Notifications and agents
| Feature | ShellX |
|---|---|
| Pane ring (blue) + tab lights + unread badge; flash on trigger (`triggerFlash`) | HAVE (A4 rings, attention_marks.dart); verify flash-twice behaviour (cmux TODO bug: ring flashes once) |
| Notification panel, jump to latest unread (Cmd+Shift+U), mark read/unread, clear all, right-click context menu | PARTIAL (panel + jump_to_unread yes; toggle-unread, mark-oldest-and-next, clear-all, context menu verify) |
| OSC 9/99/777 + `cmux notify` + hooks (Claude/Codex/OpenCode/Pi/Grok...) | HAVE OSC, shellx CLI; PARTIAL agent hook installer (no "Install integration" menu, no per-agent hooks beyond what A4 did) |
| Suppress banner only for focused pane / when app focused (docs/notifications.md "suppressOnlyFocusedSurface", "suppressWhenAppFocused") | PARTIAL (notify_threshold.dart; verify focused-pane suppression is per surface not per app) |
| Notification hooks pipeline (cmux.json notifications.hooks, JSON in/out) | MISSING (P2) |
| Dock badge unread count; sound; custom title in "waiting for input" | PARTIAL (attention_badge.dart; sound (?)) |
| Agent status in sidebar (Running / Needs input / Idle), subagents tree | PARTIAL (agent_chip.dart; no subagent tree) |
| Agent session auto-resume on restore (Claude/Codex session ids; Sources/AgentRestore*.swift, AgentAutoResumeCoordinator.swift) | MISSING (A5a restores scrollback + cwd, not agent conversations) |
| Agent hibernation, fork, journal/inbox, Feed | MISSING, skip (cmux product surface) |
| Claude Code Teams (`cmux claude-teams`) | MISSING (P2) |

### 1.4 Browser, SSH, CLI, config
| Feature | ShellX |
|---|---|
| In-app browser panes + agent-browser scripting API (docs/agent-browser-port-spec.md, cmux-browser/) | MISSING (A6 not built; huge, P2) |
| Browser import cookies/history from Chrome/Arc/... | MISSING (depends on A6) |
| `cmux ssh` workspaces, reconnect, tmux attach, remote-daemon, scp image upload, port mirroring | HAVE ssh/tmux/reconnect/forwards (A8); scp-on-drop MISSING |
| Remote agent hooks installed on host; Cmd+click remote file path downloads + previews | MISSING (P2) |
| `cmux local-tmux` / zellij "keep local sessions alive" (docs/local-tmux.md) | N/A (A5b daemon is ShellX's own answer) |
| CLI/socket: workspaces, splits, send, read screen, wait, events stream, window handles, refs `surface:N` | HAVE (A7); verify `events` stream + `terminal screen wait` exit status + short refs |
| `cmux config doctor/validate`, schema | PARTIAL (config problems panel; no CLI validate (?)) |
| Command palette (all commands, switcher, Find Work) | HAVE (A9); cmux added 14 shortcut-only actions to palette, audit parity |
| Keyboard shortcut cheat sheet + settings recorder with conflict/reserved detection (KeyboardShortcutSettings.swift: conflictsWithAction, reservedBySystem, bareKeyNotAllowed) | PARTIAL (shortcuts_sheet.dart; no in-app recorder (?)) |
| Settings UI (one section at a time, search with scroll-to-hit, schema validation, reset) | MISSING as UI; ShellX is file+command-palette only (ShellxMenu). P1 |
| Onboarding / empty states / "learn shortcuts" ? icon | PARTIAL (onboarding_page.dart is login/pair; no first-run terminal tour) |
| Auto-update (Sparkle) + What's New | PARTIAL (update_check.dart notifies only) |
| Menu bar, tray, launch at login, dock badge, Finder "Open With" | HAVE tray/login/badge; Open With MISSING |
| Vault, billing, cloud VMs, team settings, presence, iroh transport | N/A (cmux business; ShellX relay is different) |

### 1.4a UX details that make cmux pleasant (cite for polish pass)
- Notification ring: pane ring + tab highlight; flash on `triggerFlash`; ring clears when pane focused; unread only counts for non-focused panes; "unread" survives restart. Tests: cmuxTests/AgentNotificationGateTests.swift, tests_v2/test_focus_notification_dismiss.py.
- Focus: terminal never grabs focus while hidden/zero-sized (#14276); focus applied once visible; first click on an inactive pane focuses AND passes (cmuxTests/InactivePaneFirstClickFocusTests.swift); cross-workspace sidebar click focuses on 1st click (#14284); startup-focused pane is focused without a keystroke (#13968).
- Sidebar: close button always visible on active row; row text keeps notification text; agent spinners stop when hidden (#14832) to save GPU; hint overlays ("Hold Shift to open as split") always cleaned on drag end.
- Empty state: ShellX has "⌘W on empty state hides window" decided in A1; cmux iOS has Retry + Set Up buttons on "No workspaces yet".
- Paste: fast path for plain text even when clipboard has HTML/RTF (#14121, #13110); paste cancelled/timeout can't race clipboard writes (#12727); bracketed paste; image paste shows brief notice on failure.
- Window: transient sizes never published to the PTY during layout/drag (#12662, #14355); no flicker on display connect/disconnect (#14116); frame restore clamps oversized/offscreen frames (AppDelegateOversizedFrameRestoreTests.swift).
- Crash-safety UX: session snapshots rotated; two quick crashes can't wipe layout (#14824); empty-window-only snapshots are dropped (#14788).

## 2. cmux iOS vs ShellX mobile
cmux iOS (ios/, cmuxPackage/Sources/cmuxFeature, ios/CHANGELOG.md) is a client of the Mac app; ShellX mobile (apps/mobile: auth, lock, machines, notifications, pairing, settings, terminal, voice) is the same shape. Dropped as ShellX-different: Iroh/Tailscale/direct routing, Stack Auth, team picker, Cloud VMs, direct SSH (iOS 'Direct SSH' feature, ShellX may want as P2 but it is a product choice), simulator streaming.
| cmux iOS feature | ShellX mobile |
|---|---|
| Workspace list: groups, pinned above unpinned, unread counts, Recent Activity sort, keeps scroll position when rows change | PARTIAL (machines/sessions list; no groups/sort/unread count per row (?)) |
| Computer picker remembers selection; Retry + See Docs on empty list; Reconnecting status line | PARTIAL (connection_banner.dart; verify retry + remembered machine) |
| Terminal view fits visible area above keyboard + toolbar; "Use Full Terminal Height" option | PARTIAL (verify resize when keyboard shows; avoid driving desktop resize loops) |
| iMessage-style composer with inline send, per-terminal drafts; composer stays literal (no autocorrect) | PARTIAL (voice input is ShellX's own; per-terminal drafts MISSING (?); disable autocorrect check) |
| Shortcut strip/accessory buttons (Esc/Tab/Ctrl/arrows) with legible dark/light state, no edge snapping | HAVE (extra_keys_bar.dart); contrast audit pending per ledger |
| Arrow pad: directional drag sends arrows, accessibility label | MISSING |
| View as Text sheet (select/copy terminal output) | MISSING (P1: copy on a phone is painful) |
| Pinch zoom for font size | HAVE (pinch_zoom.dart) |
| Task Composer with photo/file attachments, paste images | MISSING (P2) |
| Push notifications E2E-encrypted, title+message, grouped history, mark read on foreground, tap while reconnecting waits then opens right tab | PARTIAL (push in progress: FCM spec 2026-10-05; verify tap-while-reconnecting and read-on-foreground) |
| Feed (agent activity), Markdown reader, file browser | MISSING (P2/P3) |
| On-iPhone browser | MISSING (skip) |
| Output batching: big batches during bursts; ~11 fps for busy agent terminals; keystroke echo immediate; heavy output in terminal A never delays typing in B (#13487, #14031, #14699) | verify: need a throttling/priority lane in the relay/client |
| Phone does not make the Mac terminal resize repeatedly (#13498, #13548, #13734, #13761) | HAVE by design (A1: driver-claims, banner grid change non-claiming); keep regression tests |
| Terminal input reaches terminal exactly once (#15432) | PARTIAL: HANDOFF lists "IME VN / physical keyboard sends duplicate" as unverified manual check |
| Network path change: output moves to a working path immediately (#14720); control channel repaired in place (#14695) | PARTIAL (reconnect exists; verify Wi-Fi->LTE switch time) |
| Settings: Copy Debug Information, Support Information, Erase All Data | PARTIAL (verify; Erase-on-device is a cheap P2) |
| Onboarding showing the Mac setting to enable pairing, light/dark still photo | PARTIAL (pairing_page; add "enable remote access on desktop" guidance (?)) |
| What's New / min-Mac-version notice | HAVE update_required_page.dart (version gate) |
| Face ID app lock | HAVE (lock/) |
| iPad / landscape / split-view layout | verify |

## 3. Specific: bold text and input methods

### 3a. Font weight / thickening
- cmux does NOT set a thickening default. grep over Resources/, Sources/, config/ finds `font-thicken` only as an opt-in example at docs/customizing-appearance.md:130 (`font-thicken = true`, plus `font-feature = -calt, -liga, -dlig`, `adjust-cell-height = 10%`). So cmux text weight = Ghostty upstream default (font-thicken = false; on macOS Ghostty rasterises via CoreText into its own atlas with grayscale AA, no extra stem-darkening). Ghostty source is not in cmux-src (submodule empty, docs/ghostty-fork.md lists only renderer/formatter patches, none touching weight).
- Likely causes of ShellX "too bold" (apps/desktop):
  1. xterm 4.0.0 maps weight to only `FontWeight.normal` / `FontWeight.bold` (~/.pub-cache/hosted/pub.dev/xterm-4.0.0/lib/src/ui/terminal_text_style.dart:68). Normal = w400.
  2. pubspec.yaml bundles JetBrainsMono-Regular (400) as the default. JetBrains Mono Regular is visibly heavier than SF Mono/Menlo, and Flutter on macOS draws through Skia/Impeller with CoreText font smoothing (LCD-style stem darkening is on by default in `CGContext` text when smoothing is not disabled), so white-on-dark text looks heavier than Ghostty's grayscale rendering.
  3. SGR bold (Claude Code, ls, prompts) becomes the real Bold ttf (w700), no "bold is bright" choice, so UI chrome of agents looks very heavy.
- Fix options for ShellX (cheap to expensive):
  a. Bundle JetBrainsMono-Light.ttf (300) (or Thin/ExtraLight variants) and declare it in pubspec as the `weight: 400` face (or add family `JetBrainsMonoLight`); keep Bold for 700. Add config key `font-weight = light|regular|medium` (and `font-thicken = false` default). S.
  b. Offer an alternate default family fallback chain: SF Mono / Menlo first on macOS (system fonts are lighter), JetBrains Mono only as fallback. S (font_probe.dart already probes families).
  c. Add config `bold-is-bright` / `font-synthetic-style = false` and map SGR bold to w600 (SemiBold) via a patched TerminalStyle. M (needs fork or override in terminal_pane.dart painter).
  d. Disable smoothing in the text pass (Flutter has no public flag; engine patch) L, skip.
- Verify by screenshot A/B against Ghostty at the same font-size; compare w300 vs w400 at 13pt on Retina.

### 3b. Input methods (marked text, Vietnamese/CJK) in cmux
cmux (AppKit) is an NSTextInputClient: Sources/GhosttyTerminalView.swift: `keyDown` ~7222 sets `keyTextAccumulator`, remembers `markedTextBefore`, captures `KeyboardLayout.id` BEFORE `interpretKeyEvents`, and afterwards:
- if the keyboard layout id changed while no marked text existed, an input method grabbed the key: record `imeConsumedKeyUps`, `syncPreedit`, return without forwarding to Ghostty (~7479);
- `shouldSuppressGhosttyKeyForwardingAfterIMEHandling` (Sources/GhosttyNSView+IMEComposition.swift) uses marked state before/after, accumulated text and input-source id to decide forwarding; Korean 2-Set arrows and Bopomofo preedit are special-cased;
- Shift+Space consumed by AppKit for source switching must not produce a literal space (~8285 `shouldSuppressShiftSpaceFallbackText`); Korean Enter commits and executes (`shouldSendCommittedIMEConfirmKey` ~8294), JP/CN need a second Enter;
- `setMarkedText` (~14395) honours `replacementRange` (Japanese Backspace in conversion, #13581); `unmarkText` (~14465) and `insertText` (~14613) commit and clear preedit; `firstRect(forCharacterRange:)` (~14538) positions the candidate window at the cursor;
- `resignFirstResponder` (~6940) clears `imeConsumedKeyUps`, cancels copy mode, releases mouse buttons, so no stale state after focus moves;
- an observer for `kTISNotifySelectedKeyboardInputSourceChanged` exists (Sources/KeyboardShortcutSettings.swift:1289) to re-resolve shortcuts for non-Latin layouts (Cmd-swapped Dvorak, #13015) and copy-mode vim keys under Korean/Kana/Zhuyin (#5292);
- dead keys: Option+n then a -> "ã" (#4382); numpad dedupe across full/half width (#3292); Korean jamo leak (#2529); Cmd-Space IME switching allowed in text fields (#6956).
- Tests worth porting as scenarios: cmuxTests/CJKIMEInputTests.swift, CJKIMEInputTests+DeadKeyComposition.swift, CJKIMEMarkedSelectionTests.swift, GhosttyPhysicalInputFocusReassertionTests.swift.

### 3c. Probable root cause of ShellX "typing stops after EN<->VI switch" (xterm.dart 4.0.0)
ShellX uses Flutter's TextInput channel via xterm's CustomTextEdit (~/.pub-cache/hosted/pub.dev/xterm-4.0.0/lib/src/ui/custom_text_edit.dart):
1. `_onKeyEvent` (line ~136): `if composing.isCollapsed -> forward key to terminal else return skipRemainingHandlers`. When the user is mid-composition (Telex "vie" underlined) and switches input source, macOS may never send a final `updateEditingValue` with collapsed composing, so `_currentEditingState.composing` stays non-collapsed forever and EVERY key is swallowed. That matches "typing stops" and recovery on focus change.
2. `connectionClosed()` (line ~258) is a no-op: if the engine closes the connection on source change, `_connection.attached` is false and nothing reopens it until focus toggles (`_openOrCloseInputConnectionIfNeeded` only runs on focus change).
3. `updateEditingValue` uses `_connection!` (line ~237) with a null-assert; after a close it throws and aborts the update.
Fixes (M): wrap/patch CustomTextEdit (vendor xterm like flutter_pty is vendored): (a) clear `_currentEditingState` to init on `connectionClosed`, on focus loss and on any `updateEditingValue` whose text equals init; (b) implement `connectionClosed` to reopen when the focus node still has focus; (c) a watchdog: if composing non-collapsed and no update for N ms, call `setEditingState(init)`; (d) don't swallow key events with composing non-collapsed when the key is not a text key (Enter/Esc/arrows after commit); (e) after any source switch re-send `setEditableRect/caretRect` so the candidate window follows the cursor; (f) add an integration test using `TestTextInput`/`tester.testTextInput` that sends a composing value, then a closed connection, then asserts the next key reaches the PTY. Mobile has the same path (VN IME listed as unverified in HANDOFF).

## 4. Known-bug classes ShellX should test (from cmux TODO.md, CHANGELOG, cmuxTests)
Focus
- Hidden / zero-size terminal must not take focus; focus applied when it becomes visible (#14276). Test: create pane in background workspace, switch, assert keys land.
- Focus after opening other panels (cmux TODO: arrow keys die after opening a browser tab) -> ShellX: after opening notifications panel / command palette / dialogs, focus returns to terminal and arrows work (CursorKeysInputHandler).
- First click on inactive pane focuses (InactivePaneFirstClickFocusTests); sidebar click focuses on first click (#14284); startup pane focused without keystroke (#13968); window re-activation reasserts focus (GhosttyEnsureFocusWindowActivationTests, GhosttyPhysicalInputFocusReassertionTests); CLI commands must not steal focus (tests_v2/test_cli_non_focus_commands_preserve_workspace.py, docs/socket-focus-steal-audit.todo.md).
IME / input
- Source switch mid-composition (section 3c); Backspace inside a composition deletes one char (#13581); Option dead keys; Shift+Space doesn't type a space; Cmd-C with no selection doesn't type a stray char on remapped layouts (#13015); Option-as-Alt toggle; Korean/Vietnamese Enter commit semantics; physical-keyboard double send on mobile (#15432).
Resize / layout
- Never publish transient sizes to the PTY during window/pane drag or layout settle (#12662, #14355); TUI redraw corruption after resize; phone viewing must not cause desktop resize loops (iOS #13498, #13734); first resize of a phone-driven tab only records size (ShellX A1 ruling, keep test); tmux "smallest screen wins" resize semantics for multi-attach (TODO.md Issue 151, docs/remote-tmux-sizing-design.md, docs/shared-terminal-sizing.md) - relevant to ShellX phone+desktop attach.
Scroll
- Scroll position stable while output streams; notification jump scrolls to location (AppDelegate+NotificationScroll.swift); scrollback survives restore (AppDelegate+SessionScrollbackCheckpoint.swift); wheel on overflowing tab strip scrolls horizontally (#14985).
Notifications
- Title updates must not be suppressed for unfocused workspaces (cmux TODO P0: Claude loading indicator not updating); unread order after mark-unread; dismiss on focus (tests_v2/test_focus_notification_dismiss.py); notification targets the originating pane, not the focused one (#14781, CLINotificationPaneAttributionTests, AgentNotificationLiveRetargetTests, AgentNotificationMoveRaceTests); no notification storms from subagents (CLIGrokNotificationNoiseTests); signed-out sends nothing (ShellX already).
Restore / crash
- Snapshot rotation, two quick restarts don't wipe layout (#14824); only-empty-windows snapshot dropped (#14788); deep split nesting doesn't overflow autosave (#14787); restore ordering: don't type notices into a shell that isn't ready (#13891), deferred agent restore after old process exits (#14392); frame restore on display change/off-screen (AppDelegateDisplayConfigRestoreTests, ...OversizedFrameRestoreTests, ...FullScreenFrameRestoreTests); restored zsh/bash history is per-workspace (#13851).
Clipboard / paste / DnD
- Large paste and HTML/RTF clipboard are fast (#14121, #13110); paste cancel race (#12727); dropped file inserts a path not a URL (cmux TODO bug); drag state cleanup (sidebar reorder stuck dimmed after drag ends, TODO bug); overlay hints cleared when drag ends / window deactivates (#14384).
Process / daemon (A5b-relevant)
- Cold PTY spawn storms must not wedge the app (#9796); signals blocked in the app leak into child hooks causing stalls (#12383); leaked env (NODE_OPTIONS) into children (#14812); SIGPIPE/closed pipes in CLI (#12503); socket close during read/write (#13292); multibyte args (#13301); deep process trees (#14785); wake from sleep crash (#13611) (ShellX has wake_detector.dart; add test); memory growth in long sessions (#13057, AggregateMemoryRetentionTests).
Fonts/rendering
- Fallback-font CJK/Korean spacing (#14653) and wide-char cell width; display connect flicker (#14116); Light app + dark terminal theme contrast in sidebar (#14841).

## 5. Prioritised gap list for ShellX
(effort S <1d, M 1-3d, L >3d; area D=desktop, M=mobile, C=CLI)

### P0 - bugs, robustness, daily table stakes
1. Typing stops after EN<->VI switch: fix CustomTextEdit composing/connection state (3c) + regression test. M, D+M
2. Text too bold: bundle/declare Light(300) as regular, add `font-weight` knob, consider SF Mono default on macOS (3a). S, D
3. Find in terminal (Cmd+F, next/prev, highlight, selection-as-needle). M, D
4. Clickable URLs and file paths (Cmd+click, hover underline, OSC 8, open in browser/Finder; mobile tap). M, D+M
5. Drag & drop files onto terminal = shell-escaped path(s); image paste writes temp file and inserts path (SSH: scp). M, D
6. Paste robustness: bracketed paste, large/HTML clipboard fast path, cancel-race test. S, D
7. Focus invariants: hidden pane never focuses, focus returns after palette/panels/dialogs, first click focuses+passes; add widget tests. M, D
8. Never publish transient sizes to PTY during drag/layout; tmux smallest-wins for phone+desktop attach; keep resize-loop tests. M, D+M
9. Notification title/ring updates for unfocused workspaces; suppression per focused surface not per app; notification targets originating pane. S, D
10. Restore hardening: snapshot rotation, quick double-crash safety, empty-window drop, off-screen/oversized frame clamp (A5b daemon will make this more important). M, D
11. Mobile: View-as-Text/copy sheet for terminal output. S, M
12. Mobile: output batching/priority (typing never delayed by another terminal's burst; reduced fps for busy terminals). M, M+relay
13. Mobile/desktop IME duplicate send test + disable autocorrect/suggestions in composer. S, M

### P1 - features users notice within a week
14. Settings UI (one section at a time, search, validation, links to config file; theme chooser with live preview, font/size/weight pickers). L, D
15. Copy mode (vim keys) + double/triple click selection + rectangular selection check. M, D
16. Scrollback search across all terminals (global search) and scrollbar markers for agent prompts. M, D
17. Reopen closed tab/workspace (Cmd+Shift+T) with scrollback. M, D
18. Focus history Back/Forward/Last. S, D
19. Sidebar: linked PR status/number (gh), workspace description/status, pinned workspaces, "close always visible on active". M, D
20. Cursor style/blink, padding, opacity/blur, cell-height, font-feature (ligatures off) in config. M, D
21. Cmd/Option text-editing gestures at prompt (Cmd+←/→, Option+Backspace, Cmd+Backspace). S, D
22. Move tab between panes/workspaces (drag + menu), swap panes. M, D
23. Agent hook installer (`shellx integrations install claude|codex|opencode` showing diff, y/n) + sidebar Running/Needs-input/Idle for each. M, C+D
24. Agent session resume after restore (Claude/Codex session ids) - high value for A5b daemon story. L, D+C
25. Global show/hide hotkey, Open With, auto-update install flow + What's New. M, D
26. Per-workspace font zoom; quick-terminal style hotkey window (optional). S/M, D
27. First-run tour + empty states with shortcuts hint ("learn shortcuts" ?). S, D
28. Mobile: workspace list unread counts, remembered machine, retry/setup empty-state, tap-while-reconnecting opens right tab. M, M
29. Mobile: arrow pad drag, per-terminal drafts, keyboard-aware terminal height option. M, M
30. `shellx config validate`/doctor and `shellx events` stream parity; short refs, workspace-relative commands via env var (cmux TODO P0 pattern: use SHELLX_WORKSPACE_ID so background agents don't affect active workspace). S-M, C

### P2 - nice to have / larger bets
31. In-app browser (A6) + agent-browser style scripting, cookie import. L, D+C
32. Right sidebar file explorer + file/markdown/diff preview. L, D
33. Notification hooks pipeline (JSON in/out) and sounds per category. M, D+C
34. Predictive local echo for slow SSH; password-input lock badge. M, D
35. Kitty keyboard protocol/graphics (needs xterm replacement or fork). L, D
36. Workspace groups, saved layout templates, project custom commands/packs. M, D
37. Claude Code Teams as native splits. M, D+C
38. Mobile: attachments in composer, Feed/markdown reader, erase-data/support-info buttons, push grouping and mark read on foreground. M, M
39. Reflow-hard-wrap-on-copy, scrollbar prompt markers polish. S, D
40. Dock/canvas layouts, cloud VMs: skip unless asked.

Excluded as ShellX-different: phone pairing/relay/E2E transport, Stack Auth/cloud/team/billing, Iroh/Tailscale routing, simulator streaming, My Devices mirrors.

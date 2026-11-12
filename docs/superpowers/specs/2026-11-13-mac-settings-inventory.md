# Mac Settings rows: Themes, Terminal, Keyboard Shortcuts, Workspace Colors, Sidebar, App, Reset, shellx.json

Read from source on `develop` (feea7e57ba), not from a running app. Row titles are the English `defaultValue`. Section code: `Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/`; keys and defaults: `Packages/macOS/CmuxSettings/Sources/CmuxSettings/Keys/`.

Conventions used in the tables:

- "Hidden in ShellX?" is `no` unless a ShellX switch or ShellX edit removes the row. None of these eight sections reads `ShellXSwitches` / `ShellXFeatures` directly for a row; the three exceptions are marked.
- A row that is greyed out by another row is "disabled", not hidden; the condition is in the Control column.
- Toggles are switch style. Menu picker = pop-up button; segmented = segmented control.
- `json:` gives the shellx.json path of the row where the code names one. `settings only` = the row has no shellx.json path.

Row counts: Themes 4 rows + the theme gallery; Terminal 39 fixed (+ conditional tmux rows); Keyboard Shortcuts 5 rows + search bar + 166 action rows; Workspace Colors 24; Sidebar 30 (1 conditional) + Right Sidebar Tabs header + 5 tab rows by default; App 54 visible + 1 hidden; Reset 1; shellx.json 2.

---

## 1. Themes

Two cards. Card 1 = rows 1–3, card 2 = rows 4–5.

| # | Row title | Control | Default | What it changes | Depends on | Hidden in ShellX? |
|---|---|---|---|---|---|---|
| 1 | Appearance | Three thumbnail buttons: System / Light / Dark | Dark | Switches the app chrome, the terminal theme side and web pages between light and dark; System follows macOS. `json: app.appearance` | nothing special (web pages part needs the browser pane) | no |
| 2 | Accent Color | Menu picker: ShellX Blue / System / Custom; a colour well appears for Custom | ShellX Blue (#60a5fa) | Colour of the selected workspace, attention ring, agent status and other ShellX-drawn highlights. `json: app.accentColor` (`"cmux"`, `"system"` or `"#RRGGBB"`) | nothing special | no |
| 3 | App Icon | Three icon buttons: Automatic / Light / Dark | Automatic | Dock and app switcher icon. Same key as App row 2 (`app.appIcon`) | macOS Dock / app switcher | no |
| 4 | Terminal Theme | Subtitle shows the current pair ("Light: X · Dark: Y", one name when both are equal, "Ghostty default colors" when none); buttons "Revert" (only while a pick is pending) and "Open in Terminal…" | Light: Catppuccin Latte · Dark: ShellX | Header of the gallery. "Open in Terminal…" runs the `shellx themes` picker in a new terminal tab; Revert restores the previous pair | terminal; ShellX CLI for "Open in Terminal…" | no |
| 5 | (theme gallery, no title) | Search field "Search all themes"; headings "Dark Themes" / "Light Themes" (the side in use first); grid of clickable preview cards | — | Clicking a card sets that side of the light/dark pair and reloads the terminal live | terminal; Ghostty theme files | no |

## 2. Terminal

Four cards. No row is hidden by a ShellX switch.

### Card 1: behaviour (25 rows)

| # | Row title | Control | Default | What it changes | Depends on | Hidden in ShellX? |
|---|---|---|---|---|---|---|
| 1 | Tab Bar Font Size | Slider 8–14, step 0.5, value label "N pt", Reset button | 11 pt | Font size of terminal and browser tab titles at the top of each pane. Saved in the Ghostty config key `surface-tab-bar-font-size`, not shellx.json | pane tab bar | no |
| 2 | Import from Another Terminal | Button "Import…" | — | Runs `shellx import` in a terminal tab to bring over font, colours, cursor and more from iTerm2, Terminal, Alacritty, Kitty, WezTerm or Warp | ShellX CLI; those apps' config files on a Mac | no |
| 3 | Session Content Width | Toggle + number field (pt); minimum 320, step 20 | off (stored −1); the field starts at 980 | Wraps terminal and agent chat content at this width; narrow panes keep their full width. `json: terminal.sessionContentMaxWidth` | nothing special | no |
| 4 | Session Content Alignment | Segmented: Left / Center / Right; disabled unless row 3 is on | Center | Where the width-limited content sits in a wider pane. `json: terminal.sessionContentAlignment` | nothing special | no |
| 5 | Scroll Speed | Slider 0.25–3.0, step 0.05, label "N.NN×", Reset | 1.00× | Multiplier for terminal scroll distance. `json: terminal.scrollSpeed` | nothing special | no |
| 6 | Show Terminal Scroll Bar | Toggle | on | Shows the scroll bar in terminals. `json: terminal.showScrollBar` | nothing special | no |
| 7 | Copy on Selection | Toggle | off | Selecting text copies it. `json: terminal.copyOnSelect` | clipboard | no |
| 8 | Show Copy Confirmation | Toggle | off | Shows a confirmation after a copy. `json: terminal.showCopyConfirmation` | nothing special | no |
| 9 | Reflow Hard-Wrapped Text on Copy | Toggle | off | Joins hard-wrapped lines when copying. `json: terminal.reflowHardWrapOnCopy` | clipboard | no |
| 10 | Confirm Unsafe Pastes | Toggle | off | Asks before pasting text that looks unsafe. `json: terminal.confirmUnsafePaste` | clipboard | no |
| 11 | Text Editing Gestures | Toggle | off | Command and Option arrow and delete keys move and delete by line and word at the shell prompt. `json: terminal.textEditingGestures` | Mac modifier keys (needs a Windows mapping) | no |
| 12 | Command Moves by Word | Toggle; disabled unless row 11 is on | off | Makes Command+arrow move by word instead of by line | row 11 | no |
| 13 | Text Editing Gestures in Full-Screen Apps | Toggle; disabled unless row 11 is on | off | Keeps the gestures active inside full-screen terminal apps | row 11 | no |
| 14 | Password Input Indicator | Toggle | on | Shows a lock badge while sudo/ssh reads a password. `json: terminal.showPasswordInputIndicator` | nothing special | no |
| 15 | Show Typed Password Dots | Toggle; disabled unless row 14 is on | off | Shows a dot per typed password character | row 14 | no |
| 16 | Predictive Local Echo | Toggle | on | Echoes typed characters at once in remote (SSH) terminals. `json: terminal.predictiveLocalEcho` | remote / SSH terminals | no |
| 17 | Resume Agent Sessions on Reopen | Toggle | on | Restarts agent sessions when their terminals are restored. `json: terminal.autoResumeAgentSessions` | agents + session restore | no |
| 18 | Agent Hibernation | Toggle | off | Suspends idle agent terminals. `json: terminal.agentHibernation.enabled` | agents | no |
| 19 | Hibernate After Idle Seconds | Stepper 5…604800, step 60 | 5 | Idle time before an agent terminal hibernates | row 18 | no |
| 20 | Max Live Agent Terminals | Stepper 1…256, step 1 | 12 | How many agent terminals stay live | row 18 | no |
| 21 | Reclaim Offscreen Terminal Memory | Toggle | on | Frees the renderer of terminals that are off screen. `json: terminal.rendererRealization.enabled` | terminal renderer | no |
| 22 | Reclaim After Idle Seconds | Stepper 5…604800, step 10 | 5 | Idle time before an offscreen renderer is released | row 21 | no |
| 23 | Max Warm Renderers | Stepper 1…256, step 1 | 1 | How many offscreen renderers stay ready | row 21 | no |
| 24 | Runaway Memory Guardrail | Toggle | off | Warns when the processes in one pane use too much memory. settings only | per-pane process memory accounting | no |
| 25 | Memory Warning Threshold (GB) | Stepper 1…256, step 1; disabled unless row 24 is on | 8 | Memory level that triggers the warning | row 24 | no |

Whether rows 19, 20, 22 and 23 are disabled while their parent toggle is off: not determined.

### Card 2: Ghostty options (11 rows)

Card note: "These rows show the value in effect and save to ShellX's Ghostty config, which loads after your own Ghostty config. The caption under each row is its config key." Each row's subtitle is the config key. An orange "Overridden by your config (…)" line appears when the user's own config wins. Writes are debounced 250 ms. None of these is in shellx.json.

| # | Row title | Control | Default | What it changes | Depends on | Hidden in ShellX? |
|---|---|---|---|---|---|---|
| 26 | Font | Menu picker: "Default" + installed monospaced font families | Default | Terminal font family (`font-family`) | installed fonts | no |
| 27 | Font Size | Stepper 4…96, step 0.5 | 13 pt | Terminal font size (`font-size`) | nothing special | no |
| 28 | Cursor Style | Segmented: Block / Bar / Underline / Hollow | Block | Cursor shape (`cursor-style`) | nothing special | no |
| 29 | Blinking Cursor | Toggle | on | Cursor blink (`cursor-style-blink`) | nothing special | no |
| 30 | Horizontal Padding | Stepper 0…200 pt, step 1 | 2 pt | Left/right padding inside the terminal (`window-padding-x`) | nothing special | no |
| 31 | Vertical Padding | Stepper 0…200 pt, step 1 | 2 pt | Top/bottom padding inside the terminal (`window-padding-y`) | nothing special | no |
| 32 | Background Opacity | Slider 0–1, step 0.05, shown as % | 100% | Terminal background opacity (`background-opacity`) | window transparency | no |
| 33 | Background Blur | Toggle | off | Blur behind a translucent terminal (`background-blur`) | window blur (macOS) | no |
| 34 | Option as Alt | Menu picker: Automatic / Off / Left Option / Right Option / Both Option Keys | Automatic | Whether Option sends Alt (`macos-option-as-alt`) | Mac keyboard only | no |
| 35 | Scrollback Limit | Number field in MB, 0…100000 | 50 MB | Scrollback memory; applies to new terminals (`scrollback-limit`) | nothing special | no |
| 36 | Middle-Click Paste | Toggle | on | Middle click pastes; apps that use the mouse still get middle clicks (`middle-click-action`) | clipboard | no |

### Card 3: local tmux (2 fixed rows + conditional rows)

| # | Row title | Control | Default | What it changes | Depends on | Hidden in ShellX? |
|---|---|---|---|---|---|---|
| 37 | Keep Local Sessions Alive | Status text ("Checking…" / "No live sessions" / "Live: N") + "Refresh" button + "Details" link (docs/local-tmux.md on GitHub) | — | Shows and refreshes the list of persistent local tmux sessions | tmux installed locally | no |
| 38 | Start Persistent Session | Text field "Session name" + "Start" button | empty | Starts a tmux-backed session that survives the app | tmux | no |
| — | Status (conditional) | Error text | — | Shown only when the tmux query fails | tmux | no |
| — | one row per session (conditional) | "Attach" button or "Stale" label; "Managed"/"Unmanaged", "Clients: N", working directory | — | Attaches a terminal to that session | tmux | no |

### Card 4 (1 row)

| # | Row title | Control | Default | What it changes | Depends on | Hidden in ShellX? |
|---|---|---|---|---|---|---|
| 39 | Resume Commands | Count text (hard-coded "0") + "Open" button | — | Opens shellx.json to review signed command prefixes that can restore non-agent terminals. `json: terminal.resumeCommands` (JSON only) | session restore; shellx.json | no |

## 3. Keyboard Shortcuts

| # | Row title | Control | Default | What it changes | Depends on | Hidden in ShellX? |
|---|---|---|---|---|---|---|
| 1 | Base Keymap | Menu picker: ShellX (Default) / iTerm2 / Terminal.app / tmux-style (Ctrl-B Prefix); "Custom" appears when no preset matches. A pick opens a preview with "Cancel" / "Apply Keymap" | ShellX (Default) | Starts from another terminal's shortcuts; only the differences are written to shellx.json. `json: shortcuts.bindings` | shellx.json | no |
| 2 | Shortcut Chords | Button "Open shellx.json" | — | Opens the file to add tmux-style multi-step shortcuts, for example `["ctrl+b", "c"]` | shellx.json | no (cmux's "Chord docs" link was removed in ShellX by an edit, not a switch) |
| 3 | Show Shortcut Hints While Holding Modifier Keys | Toggle | on | Shows shortcut hints while a modifier key is held. `json: shortcuts.showModifierHoldHints` | hint overlays in sidebar and tabs | no |
| 4 | Pane Resize Step | Stepper 1…200 px, step 1 | 20 px | Distance one Resize Pane shortcut moves a divider. `json: app.paneResizeStepPixels` | split panes | no |
| 5 | Reset Default Shortcuts | Button "Reset Defaults" | — | Restores built-in values for shortcuts managed in app settings | shellx.json | no |
| 6 | (search bar, no title) | Text field "Search shortcuts" + key detector button "Detect Shortcut" / "Listening…" + clear button | empty | Filters the action list by text or by a pressed shortcut | nothing special | no |
| 7–172 | 166 action rows (list in prose B) | Recorder button (width 160) + X button (unbind; becomes a restore arrow after a clear) | per action | Rebinds that action. `json: shortcuts.bindings.<actionId>` | the feature the action drives | no (cloud-only actions are still listed, see B) |

Footer note: "Click a shortcut value to record. Use X to unbind; it changes to restore after a clear."

## 4. Workspace Colors

No row is hidden by a ShellX switch.

| # | Row title | Control | Default | What it changes | Depends on | Hidden in ShellX? |
|---|---|---|---|---|---|---|
| 1 | Workspace Color Indicator | Menu picker: Left Rail / Solid Fill | Left Rail | How a workspace's colour is drawn in its sidebar row. `json: workspaceColors.indicatorStyle` | workspace sidebar | no |
| 2 | Subtle Selection Highlight | Toggle; disabled when Solid Fill | on | Selected workspace gets a faint accent tint with a thin edge instead of a solid fill | workspace sidebar | no |
| 3 | Brighten Colors in Dark Mode | Toggle; disabled when Left Rail | on | Brightens workspace colours on dark chrome | Solid Fill style | no |
| 4 | Unselected Fill Opacity | Slider 0–1, step 0.05, % label; disabled when Left Rail | 70% | Opacity of the colour fill on unselected rows | Solid Fill style | no |
| 5 | Selection Highlight | Colour well (no opacity) + hex or "Default" label + "Reset" when custom | Default (accent) | Colour of the selected workspace row; a custom colour always draws solid. `json: workspaceColors.selectionColor` | workspace sidebar | no |
| 6 | Notification Badge | Colour well + "Reset" when custom | Default | Colour of the unread badge. `json: workspaceColors.notificationBadgeColor` | notifications | no |
| 7 | Pane Flash | Colour well + "Reset" when custom | Default (accent) | Colour of the attention ring and pane flash when a pane needs input. `json: notifications.paneFlashColor` | pane attention ring | no |
| 8–23 | 16 palette rows; title = colour name (Red … Charcoal, list in prose C) | Colour well + hex label; subtitle "Base: #HEX" for built-ins, "Named palette entry." + "Remove" button for added names | the built-in hex | Changes that named colour everywhere it is used. `json: workspaceColors.colors` | workspace colours | no |
| 24 | Reset Palette | Button "Reset" | — | Restores the built-in palette and removes extra named colours | workspace colours | no |

Note above the palette: "Edit shellx.json to add or remove named colors. "Choose Custom Color..." still adds local Custom N entries." Empty palette shows: "No palette entries. Add colors in shellx.json or use "Choose Custom Color..." from a workspace context menu."

## 5. Sidebar

### Card 1 (30 rows, 1 conditional)

Most rows below row 5 are disabled, not hidden, while "Hide All Sidebar Details" is on. No row is hidden by a ShellX switch.

| # | Row title | Control | Default | What it changes | Depends on | Hidden in ShellX? |
|---|---|---|---|---|---|---|
| 1 | Sidebar Background | Menu picker: Follow Theme / Match Terminal / Custom Color | Follow Theme | Follow the terminal theme, use the terminal's own background, or a colour of your own | terminal theme | no |
| 2 | Sidebar Color | Colour well + hex; shown only when row 1 = Custom Color | #100B1D | The sidebar keeps this colour whichever theme is picked. `json: sidebarAppearance.tintColor` | row 1 | no (conditional) |
| 3 | Sidebar Font Size | Slider 10–20, step 0.5, "N pt" label, Reset | 12.5 pt | Size of workspace titles, metadata, badges and shortcut hints in the left sidebar. Saved in the Ghostty config key `sidebar-font-size` | nothing special | no |
| 4 | Dock Max Width | Toggle + number field (pt); minimum 295, maximum 4096 | off (stored −1); the field starts at 1200 | Lets the Dock in the right sidebar grow up to this width while leaving room for terminals. `json: sidebar.rightMaxWidth` | right sidebar Dock tab | no |
| 5 | Hide All Sidebar Details | Toggle | off | Shows only workspace titles in the sidebar | nothing special | no |
| 6 | Wrap Workspace Titles in Sidebar | Toggle | off | Shows long workspace titles in full on several lines | nothing special | no |
| 7 | Show Workspace Description in Sidebar | Toggle | on | Shows custom workspace descriptions below the title | workspace descriptions | no |
| 8 | Workspace Description Color | Colour well + "Reset" | Default (follows theme) | Text colour of workspace descriptions | row 7 | no |
| 9 | Sidebar Branch Layout | Menu picker: Vertical / Inline | Vertical | Whether branches share one line or each get their own. `json: sidebar.branchLayout` | git metadata | no |
| 10 | Stack Branch and Directory | Toggle; shown on and disabled while row 9 = Vertical | off | Shows the branch and directory on separate lines | git metadata | no |
| 11 | Truncate Path From Start | Toggle | off | Shortens long paths from the start so the end stays visible | nothing special | no |
| 12 | Show Notification Message in Sidebar | Toggle | on | Shows the latest notification message below the workspace title | notifications | no |
| 13 | Notification Preview Lines | Stepper 1…50; disabled unless row 12 is on | 12 | Maximum lines shown for the latest notification | row 12 | no |
| 14 | Show Branch + Directory in Sidebar | Toggle | on | Shows git branches and working directories | git metadata | no |
| 15 | Show Cloud and Device Icons in Sidebar | Toggle | on | Shows the cloud machine or device icon | cloud machines / devices (both off in ShellX) | no (still shown although the feature is off) |
| 16 | Show Pull Requests in Sidebar | Toggle | on | Shows review items (PR/MR) with status and number | git host PR lookup | no |
| 17 | Watch Git Status in Sidebar | Toggle | on | Updates branch and PR metadata from file changes without polling git | file watching + git | no |
| 18 | Make Sidebar PR Clickable | Toggle; disabled unless row 16 is on | on | Off: review items stay plain text and clicks select the row | row 16 | no |
| 19 | Open Sidebar PR Links in ShellX Browser | Toggle; disabled unless rows 16 and 18 are on | on | A PR link opens in the built-in browser | built-in browser | no |
| 20 | Open Sidebar Port Links in ShellX Browser | Toggle | on | A port link opens in the built-in browser | built-in browser | no |
| 21 | Show SSH in Sidebar | Toggle | on | Shows the SSH target of remote workspaces in its own row | remote / SSH workspaces | no |
| 22 | Show Listening Ports in Sidebar | Toggle | on | Shows detected listening ports of the active workspace | port detection | no |
| 23 | Show Latest Log in Sidebar | Toggle | on | Shows the latest imperative log/status message | CLI log/status calls | no |
| 24 | Show Progress in Sidebar | Toggle | on | Shows the built-in progress bar from `set_progress` | CLI `set_progress` | no |
| 25 | Show Agent Usage in Sidebar | Toggle; disabled unless row 29 is on | off | Appends model and context window to Claude Code and Codex status entries, plus an estimated API cost for Claude Code | agents + custom metadata | no |
| 26 | Show Loading Spinner | Toggle | on | Spinner on workspaces with running agents or active loaders; stays even when details are hidden. `json: sidebar.showAgentActivity` | agents | no |
| 27 | Loading Spinner Position | Segmented: Left / Right | Left | Spinner on the left (shares the unread badge slot) or the right of the row | row 26 | no |
| 28 | Notification Badge Position | Segmented: Left / Right | Left | Unread badge on the left or right of the row | notifications | no |
| 29 | Show Custom Metadata in Sidebar | Toggle | on | Shows metadata from `report_meta` / `set_status` / `report_meta_block` | CLI metadata calls | no |
| 30 | Compact Agent Status | Toggle | off | Shows agent, unread and PR state as one coloured icon before the title instead of separate rows | agents | no |

### Card 2: Right Sidebar Tabs

| # | Row title | Control | Default | What it changes | Depends on | Hidden in ShellX? |
|---|---|---|---|---|---|---|
| 31 | Right Sidebar Tabs | Header row, no control | — | "Choose which tabs the right sidebar shows and their order. The ⌃1–⌃9 shortcuts follow the visible order." | right sidebar | no |
| 32 | Files | Icon + title + shortcut label + up/down chevrons + visibility toggle | visible | Shows/hides and reorders the tab | right sidebar file explorer | no |
| 33 | Find | same | visible | same | find in directory | no |
| 34 | Vault | same | visible | same | agent sessions vault | no |
| 35 | Dock | same | visible | same | Dock | no |
| 36 | Git | same | visible | same | git | no |
| — | Feed | same | — | same | Feed beta flag (off by default) | row absent unless the beta is on |
| — | Cloud | same | — | same | cloud machines | yes, `ShellXFeatures.remoteMachines = false` |
| — | Custom | same | — | same | custom-sidebars beta + a chosen sidebar | row absent unless the beta is on |

The last visible tab cannot be hidden. Order shown is the enum order (files, find, sessions, feed, dock, machines, git); the stored default order was not separately confirmed. Stored in UserDefaults `rightSidebar.tabs.order` / `rightSidebar.tabs.hidden`.

## 6. App

One card. 54 visible rows + 1 hidden.

| # | Row title | Control | Default | What it changes | Depends on | Hidden in ShellX? |
|---|---|---|---|---|---|---|
| 1 | Language | Menu picker: System, English, Arabic, Bosnian, Chinese Simplified, Chinese Traditional, Danish, German, Spanish, French, Italian, Japanese, Korean, Norwegian, Polish, Português (Brasil), Russian, Thai, Turkish, Tiếng Việt | System | App language; shows "Restart ShellX to apply" after a change. `app.language` | localized strings | no |
| 2 | App Icon | Three icon buttons: Automatic / Light / Dark | Automatic | Dock and app switcher icon (same key as Themes row 3) | macOS Dock | no |
| 3 | New Workspace Placement | Picker: Top / After current / End | After current | Where new workspaces appear in the sidebar | workspace sidebar | no |
| 4 | Workspace Layouts | Button "Customize…" | — | Edits the saved layouts offered in the new-workspace menu | workspace layout templates | no |
| 5 | Inherit Workspace Working Directory | Toggle | on | New workspaces start in the current workspace's directory | nothing special | no |
| 6 | Minimal Mode | Toggle | off | Hides the workspace title bar and shows its controls in the sidebar | custom title bar | no |
| 7 | Keep Workspace Open When Closing Last Surface | Toggle (shows the inverse of the stored value; stored key `app.keepWorkspaceOpenWhenClosingLastSurface` defaults to true) | off | Closing the last surface keeps the workspace open | nothing special | no |
| 8 | Focus Pane on First Click | Toggle | off | Clicking a pane while the app is in the background focuses it at once | window activation | no |
| 9 | Include Panes and Tabs in Focus History | Toggle | off | Back and Forward also return to previous panes and tabs | focus history | no |
| 10 | Equalize Splits on Create | Toggle | off | A new split makes the panes in that direction equal | split panes | no |
| 11 | File Drops | Picker: Drop path text / Open file preview | Drop path text | What dropping files on a terminal or editor does; Shift while dragging does the other | drag and drop; file preview | no |
| 12 | Open Files With | Text field, placeholder "e.g. code, zed, subl" | empty | Command used when Cmd-click previews are off or a file is unsupported; empty = system default | external editor | no |
| 13 | Open Supported Files in ShellX | Toggle | on | Cmd-clicking readable files opens them in the built-in previews | file preview panes | no |
| 14 | Terminal Config | Button "Open Config" | — | Opens the ShellX terminal config and generated preview in one utility window | Ghostty config editor window | no |
| 15 | Global Font Magnification | % label + stepper 50–200, step 10 + Reset | 100% | Scales all text in the app | nothing special | no |
| 16 | Open Markdown in ShellX Viewer | Toggle | on | Cmd-clicking Markdown opens the rendered viewer instead of the generic preview | markdown viewer; row 13 | no |
| 17 | Markdown Viewer Font Size | Stepper 8…96 | 15 | Body font size of newly opened markdown viewers | markdown viewer | no |
| 18 | Markdown Viewer Max Width | Stepper 320…2400, step 20 | 980 | Maximum reading column width, in CSS pixels | markdown viewer | no |
| 19 | Canvas Pane Gap | Stepper 0…64, step 2 | 16 | Spacing between panes in the canvas layout | canvas layout | no |
| 20 | Canvas Snapping | Toggle | on | Pane drags and resizes snap to neighbour edges and the gap | canvas layout | no |
| 21 | Markdown Viewer Font | Text field, placeholder "System" | empty | Body font family of markdown viewers | markdown viewer | no |
| 22 | File Editor Word Wrap | Toggle | off | Wraps long lines in the plain-text file editor | built-in file editor | no |
| 23 | File Editor Syntax Highlighting | Toggle | on | Colours tokens in the file editor | built-in file editor | no |
| 24 | File Editor Line Numbers | Toggle | on | Shows a line-number gutter | built-in file editor | no |
| 25 | File Editor Indent Guides | Toggle | on | Draws vertical guides at indent columns | built-in file editor | no |
| 26 | File Editor Current Line Highlight | Toggle | on | Highlights the caret line when nothing is selected | built-in file editor | no |
| 27 | File Editor Tab Width | Stepper 1…8 | 4 | Columns per tab stop, used by indent guides | built-in file editor | no |
| 28 | iMessage Mode | Toggle | off | Moves a workspace to the top and shows the submitted message when an agent prompt is sent | agents | no |
| 29 | Reorder on Notification | Picker: Off / Notifications / Agent Activity | Notifications | Moves workspaces to the top on a notification; Agent Activity also on prompt, turn end, needs input or failure | notifications; agents | no |
| 30 | Dock Badge | Toggle | on | Unread count on the app icon (Dock and Cmd+Tab) | macOS Dock badge | no |
| 31 | Menu Bar Only | Toggle | off | Hides the Dock icon and Cmd+Tab entry | macOS menu bar item | no |
| 32 | Show in Menu Bar | Toggle; disabled while row 31 is on | on | Keeps a menu bar item for unread notifications and quick actions | macOS menu bar item | no |
| 33 | Unread Pane Ring | Toggle | on | Ring around panes with unread notifications | notifications | no |
| 34 | Pane Flash | Toggle | on | Briefly flashes an outline when a pane is highlighted | pane attention ring | no |
| 35 | Double Blink | Toggle; disabled unless row 34 is on | on | Blinks the flash twice instead of one short pulse | row 34 | no |
| 36 | Flash While Typing | Toggle; disabled unless row 34 is on | on | Flashes the pane when typing dismisses its notification | row 34 | no |
| 37 | Use Theme Foreground | Toggle; disabled unless row 34 is on | off | Flashes use the terminal theme foreground; unread rings stay ShellX blue | row 34 | no |
| 38 | Agent Needs Permission | Toggle | on | Notifies when an agent waits for permission to run a tool | agent hooks | no |
| 39 | Agent Finished | Picker: When idle / Always / Never | When idle | When to notify that an agent finished | agent hooks | no |
| 40 | Agent Waiting for Input | Toggle | on | Notifies when an agent has been idle waiting for input | agent hooks | no |
| 41 | Desktop Notifications | Status label (Permission unknown / Allowed / Denied / Deliver Quietly / Temporary) + "Enable" or "Open System Settings" + "Send Test" | — | Requests or shows the OS notification permission and sends a test | OS notification permission | no |
| 42 | Notification Sound | Picker: Default, Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink, Custom File…, None + preview button (+ "Choose…" / "Clear" for a custom file) | Default | Sound played with a notification | macOS system sounds | no |
| 43 | Sound for Focused Pane | Toggle | off | Plays the sound even when the notifying pane is focused | row 42 | no |
| 44 | Per-Agent Notification Sounds | Matrix: one row per agent × Turn Done / Needs Input / Error / Stalled; each cell a menu (Use Global Sound, each sound, Choose Custom File…) | none set (`{}`) | Overrides the sound for one agent and alert type | agents; row 42 | no |
| 45 | Notification Command | Text field, placeholder `say "done"` | empty | Runs a shell command on each notification with $CMUX_NOTIFICATION_TITLE / _SUBTITLE / _BODY set | shell | no |
| — | Send anonymous telemetry | Toggle | on in the catalog | Shares crash and usage data | telemetry | yes, `AppSection.showsTelemetrySetting = false` |
| 46 | Warn Before Quit | Segmented: Always / Dirty Only / Never | Always | When quitting asks for confirmation | nothing special | no |
| 47 | Warn Before Closing Tab | Toggle | on | Closing a tab asks first | nothing special | no |
| 48 | Warn Before Closing Active Agent Session | Toggle | on | Closing an agent during a turn asks first | agents | no |
| 49 | Warn Before Tab Close Button | Toggle; disabled while row 52 is on | off | The tab's X button asks first | tab close button | no |
| 50 | Warn Before Closing Workspace | Toggle | on | Asks before closing a workspace with a running process, or several at once | nothing special | no |
| 51 | Warn Before Closing Window | Toggle | on | Asks before closing a window with a running process | nothing special | no |
| 52 | Hide Tab Close Button | Toggle | off | Removes the close button from tabs | nothing special | no |
| 53 | Rename Selects Existing Name | Toggle | on | Renaming from the command palette selects the current name | command palette | no |
| 54 | Command Palette Searches All Surfaces | Toggle | off | Palette results include terminal, browser and Markdown surfaces from every workspace | command palette | no |

Catalog keys in `AppCatalogSection` with no row in this section: `app.windowTitleTemplate`, `app.goToWorkspaceOrder`, `app.defaultWorkspacePath`, `app.tabBarVisibility`, `app.titlebarControlsStyle`, `app.workspaceButtonFade`, `app.workspaceTitlebarVisibility`, `app.systemWideHotkeyEnabled` (Global Hotkey section), `app.devWindowDisplay`. Whether another section shows them: not determined except the hotkey.

## 7. Reset

| # | Row title | Control | Default | What it changes | Depends on | Hidden in ShellX? |
|---|---|---|---|---|---|---|
| 1 | (no title) | One centred bordered button "Reset All Settings" | — | Resets every catalog key in UserDefaults and in shellx.json and clears legacy shortcut bindings; then resets the language override, pane chrome, adaptive theme, phone push config and socket listener | shellx.json; UserDefaults | no |

No confirmation dialog in the section code.

## 8. shellx.json

| # | Row title | Control | Default | What it changes | Depends on | Hidden in ShellX? |
|---|---|---|---|---|---|---|
| 1 | User config file | Monospaced path `~/.config/shellx/shellx.json` + "Open" button | — | Opens the file. Subtitle: "Edit ShellX-owned app settings, shortcuts, automation, sidebar, notifications, and browser behavior." | shellx.json | no |
| 2 | Documentation | Link "Open Docs" → https://github.com/lephus/shellx/blob/main/docs/configuration.md | — | Opens the docs. Subtitle: "View supported keys, file locations, schema, and reload behavior." | web browser | no |

---

## A. Themes

**Light/dark pair.** Two terminal themes are stored, one per side. A card click sets only the side of the group it sits in ("Dark Themes" or "Light Themes"). The value is written as `theme = light:<name>,dark:<name>` inside the managed block `# cmux themes start` … `# cmux themes end` in `~/Library/Application Support/pro.shellx.desktop/config.ghostty` (the same writer as the `shellx themes` CLI), then the terminal reloads live. "Revert" puts back the block's previous value. Defaults: light = "Catppuccin Latte", dark = "ShellX". A plain single-theme value fills only the side its background suits; the other side shows the default.

**Which side is active.** The Appearance row (`appearanceMode`: system / light / dark; default dark; legacy `auto` → `system`). System follows the macOS appearance. The app sets `NSApplication.appearance` and synchronizes the Ghostty theme.

**Gallery contents.** Theme files are read from, in order: `$GHOSTTY_RESOURCES_DIR/themes`, the app bundle's `ghostty/themes`, `$XDG_DATA_DIRS/*/ghostty/themes`, `/Applications/Ghostty.app/Contents/Resources/ghostty/themes`, `~/.config/ghostty/themes`, `~/Library/Application Support/pro.shellx.desktop/themes`, `~/Library/Application Support/com.mitchellh.ghostty/themes`. The earlier directory wins a case-insensitive name clash. The repo bundles 464 theme files in `Resources/ghostty/themes` (flat directory, includes `ShellX`): 386 dark, 78 light by the gallery's rule.

**Dark or light rule.** Luminance 0.299R + 0.587G + 0.114B of the theme's `background` below 0.5 = dark; no background = dark.

**What a card previews.** Parsed per theme: `background`, `foreground`, `cursor-color`, `palette = N=#hex` for 0–15. Card: preview height 54, theme background, theme name in the theme's foreground (10 pt monospaced medium), a 5×11 cursor block in the cursor colour, two rows of 8 ANSI swatches (8 pt high). Grid: adaptive columns 128–220 wide, spacing 10. Search field max width 200; empty result text "No themes match your search."; save error "Couldn't save the terminal theme. Please try again." Selected-card styling: not determined.

**Colours a theme defines.** Ghostty theme file keys: `background`, `foreground`, `cursor-color`, `cursor-text`, `selection-background`, `selection-foreground`, `palette` 0–15. The gallery ignores cursor-text and the selection colours; the terminal uses them.

ShellX theme: background #0b0716, foreground #cdc7e0, cursor #60a5fa, cursor-text #0b0716, selection-background #233356, selection-foreground #e6e2f2; ANSI 0–15: #211a37, #e88a8a, #6fd49a, #e8c468, #60a5fa, #c49af0, #6fc8d9, #cdc7e0, #6e6790, #f2a7a7, #93e2b4, #f2d68f, #93c5fd, #d9b8f7, #96dbe7, #e6e2f2.

**How the chrome follows the theme.** Sidebar tint source is `automatic | theme | custom` (`sidebarTintSource`). Following the theme, the sidebar colour is the terminal background moved one step: ShellX theme (#0b0716) → panel #100b1d; another dark theme → +2% white; a light theme → +3% black. Sidebar text (light or dark scheme) is chosen from the readability of the resulting colour. `automatic` follows the theme only while the tint is untouched (#100B1D, opacity ≥ 0.999, no light/dark overrides). "Match Terminal" (`sidebarAppearance.matchTerminalBackground`) makes the sidebar share the terminal backdrop. How the title bar and other chrome derive their colours beyond this: not determined.

ShellX chrome palette (`ShellXPalette`): bg #0b0716, panel #100b1d, raise #171128, line #211a37, border #2a2145, text #cdc7e0, textHi #e6e2f2, muted #8a83a6, primary #60a5fa, primarySoft #60a5fa at 12%, primaryLine #60a5fa at 45%, primaryText #93c5fd, running #e8c468, done #6fd49a, error #e88a8a, selectionTitle #f1f5ff, selectionSecondary #b4c6e6, rowHover #1b1530, unfocusedTabIndicator #5b5478.

**Accent.** "ShellX Blue" = #60a5fa in both light and dark (the function takes `isDark` and ignores it). System = the macOS control accent colour. Custom = `#RRGGBB`, falling back to ShellX Blue when invalid. The accent colours only ShellX-drawn chrome (selected workspace, attention ring, pane swap source, canvas focus, scroll markers, agent status); native controls keep the system accent. The built-in agent-status colour #4C8DFF is drawn with the accent. A custom Selection Highlight or Pane Flash colour wins over the accent.

**Appearance thumbnails.** 76×50, label 10 pt; selected = accent fill at 12% + 2 pt accent stroke, corner 8. App Icon buttons use 48 pt icons.

## B. Keyboard Shortcuts

**Grouping.** The Settings list is flat: no group headers. Order = `ShortcutAction.allCases` minus `showHideAllWindows` (it lives in the Global Hotkey section, default ⌃⌥⌘.), with five right-sidebar actions moved to sit after "Mark as Oldest Unread…". The code has a `ShortcutAction.Group` (App / Workspace / Navigation / Panes / Browser & Find) that Settings does not render; it is in the Group column below.

**Row.** Title, optional caption with the scope ("Only while a browser pane is focused", "Only while the right sidebar is focused", "Only while a terminal pane is focused", "Only while a markdown preview is focused", "Only while a Simulator is focused", or "When: …"), recorder button, X button.

**Rebindable actions in list order (166).** Modifier order ⌃⌥⇧⌘. "None" = unbound by default. Two-key values (`G G`, `] F`, `[ F`) are chords.

| # | Action title | Default | Group (not rendered) | actionId |
|---|---|---|---|---|
| 1 | Settings… | ⌘, | App | `openSettings` |
| 2 | Open Team Picker | ⌥⇧⌘T | App | `openTeamPicker` |
| 3 | Reload Configuration | ⇧⌘, | App | `reloadConfiguration` |
| 4 | Global Search | ⌥⌘F | App | `globalSearch` |
| 5 | New Window | ⇧⌘N | App | `newWindow` |
| 6 | Close Window | ⌃⌘W | App | `closeWindow` |
| 7 | Toggle Full Screen | ⌃⌘F | App | `toggleFullScreen` |
| 8 | Quit cmux | ⌘Q | App | `quit` |
| 9 | Toggle Left Sidebar | ⌘B | Workspace | `toggleSidebar` |
| 10 | Focus Sidebar | ⌃⌘E | Workspace | `focusSidebar` |
| 11 | Click by Hint | ⌘J | Workspace | `showWindowHints` |
| 12 | New Workspace | ⌘N | Workspace | `newTab` |
| 13 | New Local Workspace | ⌃⌥⌘N | Workspace | `newLocalWorkspace` |
| 14 | New Browser Workspace | ⌥⌘N | Workspace | `newBrowserWorkspace` |
| 15 | Save Layout as Template… | ⌃⌘S | Workspace | `saveLayoutTemplate` |
| 16 | Open Folder | ⌘O | Workspace | `openFolder` |
| 17 | Restore Previous App Launch | ⇧⌘O | Workspace | `reopenPreviousSession` |
| 18 | Go to Workspace… | ⌘P | Workspace | `goToWorkspace` |
| 19 | Command Palette… | ⇧⌘P | Workspace | `commandPalette` |
| 20 | Show Agent Inbox | ⇧⌘I | Workspace | `agentInbox` |
| 21 | Command Palette: Next | ⌃N | Workspace | `commandPaletteNext` |
| 22 | Command Palette: Previous | ⌃P | Workspace | `commandPalettePrevious` |
| 23 | Send Feedback | None | Workspace | `sendFeedback` |
| 24 | Show Notifications | ⌘I | Workspace | `showNotifications` |
| 25 | Jump to Latest Unread | ⇧⌘U | Workspace | `jumpToUnread` |
| 26 | Jump to Last Prompt | ⇧⌘B | Workspace | `jumpToLastPrompt` |
| 27 | Toggle Unread | ⌥⌘U | Workspace | `toggleUnread` |
| 28 | Mark as Oldest Unread and Jump to Next Latest Unread | ⌃⌘U | Workspace | `markOldestUnreadAndJumpNext` |
| 29 | Toggle Right Sidebar Focus | ⇧⌘E | Workspace | `focusRightSidebar` |
| 30 | Toggle Right Sidebar | ⌥⌘B | Panes | `toggleRightSidebar` |
| 31 | Find in Directory… | ⇧⌘F | Browser & Find | `findInDirectory` |
| 32 | File Explorer: Open Selection | ↩ | Panes | `fileExplorerOpenSelection` |
| 33 | File Explorer: Open Selection (Finder Alias) | ⌘↓ | Panes | `fileExplorerOpenSelectionFinderAlias` |
| 34 | Mark All Notifications Read | None | Workspace | `markAllNotificationsRead` |
| 35 | Clear All Notifications | None | Workspace | `clearAllNotifications` |
| 36 | Show Sidebar Files | ⌃1 | Workspace | `switchRightSidebarToFiles` |
| 37 | Show Sidebar Find | ⌃2 | Workspace | `switchRightSidebarToFind` |
| 38 | Show Sidebar Vault | ⌃3 | Workspace | `switchRightSidebarToSessions` |
| 39 | Show Sidebar Feed | ⌃4 | Workspace | `switchRightSidebarToFeed` |
| 40 | Show Sidebar Dock | ⌃5 | Workspace | `switchRightSidebarToDock` |
| 41 | Show Sidebar Cloud | ⌃6 | Workspace | `switchRightSidebarToMachines` |
| 42 | Flash Focused Panel | ⇧⌘H | Workspace | `triggerFlash` |
| 43 | Next Surface | ⇧⌘] | Navigation | `nextSurface` |
| 44 | Previous Surface | ⇧⌘[ | Navigation | `prevSurface` |
| 45 | Reorder Surface Left | ⌥⇧⌘[ | Navigation | `moveSurfaceLeft` |
| 46 | Reorder Surface Right | ⌥⇧⌘] | Navigation | `moveSurfaceRight` |
| 47 | Move Surface to Previous Pane | ⌃⇧⌘[ | Navigation | `moveSurfaceToPreviousPane` |
| 48 | Move Surface to Next Pane | ⌃⇧⌘] | Navigation | `moveSurfaceToNextPane` |
| 49 | Move Surface to Pane on Left | ⌥⇧⌘← | Navigation | `moveSurfaceToPaneLeft` |
| 50 | Move Surface to Pane on Right | ⌥⇧⌘→ | Navigation | `moveSurfaceToPaneRight` |
| 51 | Move Surface to Pane Above | ⌥⇧⌘↑ | Navigation | `moveSurfaceToPaneUp` |
| 52 | Move Surface to Pane Below | ⌥⇧⌘↓ | Navigation | `moveSurfaceToPaneDown` |
| 53 | Select Surface 1…9 | ⌃1…9 | Navigation | `selectSurfaceByNumber` |
| 54 | Next Workspace | ⌃⌘] | Navigation | `nextSidebarTab` |
| 55 | Previous Workspace | ⌃⌘[ | Navigation | `prevSidebarTab` |
| 56 | Next Workspace in Group | None | Navigation | `nextSidebarTabInGroup` |
| 57 | Previous Workspace in Group | None | Navigation | `prevSidebarTabInGroup` |
| 58 | Move Workspace Up | ⌃⌥⌘[ | Navigation | `moveWorkspaceUp` |
| 59 | Move Workspace Down | ⌃⌥⌘] | Navigation | `moveWorkspaceDown` |
| 60 | Focus Back | ⌘[ | Navigation | `focusHistoryBack` |
| 61 | Focus Forward | ⌘] | Navigation | `focusHistoryForward` |
| 62 | Focus Last | None | Navigation | `focusHistoryLast` |
| 63 | Select Workspace 1…9 | ⌘1…9 | Navigation | `selectWorkspaceByNumber` |
| 64 | Rename Tab | ⌘R | Navigation | `renameTab` |
| 65 | Rename Workspace | ⇧⌘R | Navigation | `renameWorkspace` |
| 66 | Edit Workspace Description | ⌥⌘E | Navigation | `editWorkspaceDescription` |
| 67 | Mark Workspace as Done | ⌘; | Navigation | `markWorkspaceDone` |
| 68 | Cycle Workspace Status | ⇧⌘; | Navigation | `cycleWorkspaceStatus` |
| 69 | Toggle Checklist Item Complete | ⌘↩ | Navigation | `toggleChecklistItemComplete` |
| 70 | Close Tab | ⌘W | Navigation | `closeTab` |
| 71 | Close Other Tabs in Pane | ⌥⌘T | Navigation | `closeOtherTabsInPane` |
| 72 | Close Workspace | ⇧⌘W | Navigation | `closeWorkspace` |
| 73 | New Workspace Group | ⌃⌘G | Navigation | `newWorkspaceGroup` |
| 74 | Group Selected Workspaces | ⇧⌘G | Navigation | `groupSelectedWorkspaces` |
| 75 | Toggle Focused Workspace's Group Collapse | ⌃⌘. | Navigation | `toggleFocusedWorkspaceGroupCollapsed` |
| 76 | Reopen Closed Workspace | None | Workspace | `reopenClosedWorkspace` |
| 77 | Reopen Last Closed | ⇧⌘T | Navigation | `reopenClosedBrowserPanel` |
| 78 | New Surface | ⌘T | Navigation | `newSurface` |
| 79 | Toggle Terminal Copy Mode | ⇧⌘M | Navigation | `toggleTerminalCopyMode` |
| 80 | Focus TextBox Input | ⇧⌘A | Navigation | `focusTextBoxInput` |
| 81 | Cycle TextBox Submit Action | ⇧⇥ | Navigation | `cycleTextBoxSubmitAction` |
| 82 | Attach File to TextBox Input | ⌥⇧⌘A | Navigation | `attachTextBoxFile` |
| 83 | Send Ctrl-F to Terminal | None | Navigation | `sendCtrlFToTerminal` |
| 84 | Paste Last Screenshot | None | Navigation | `pasteLastScreenshot` |
| 85 | Size Terminal to My Window | ⌃⌥⌘= | Navigation | `sizeTerminalToMyWindow` |
| 86 | Clear Screen (Keep Scrollback) | ⇧⌘K | Navigation | `clearScreenKeepScrollback` |
| 87 | Focus Pane Left | ⌥⌘← | Panes | `focusLeft` |
| 88 | Focus Pane Right | ⌥⌘→ | Panes | `focusRight` |
| 89 | Focus Pane Up | ⌥⌘↑ | Panes | `focusUp` |
| 90 | Focus Pane Down | ⌥⌘↓ | Panes | `focusDown` |
| 91 | Focus Previous Pane | None | Panes | `focusPreviousPane` |
| 92 | Focus Next Pane | None | Panes | `focusNextPane` |
| 93 | Focus Pane 1…9 | ⌃⌘1…9 | Panes | `focusPaneByNumber` |
| 94 | Split Right | ⌘D | Panes | `splitRight` |
| 95 | Split Down | ⇧⌘D | Panes | `splitDown` |
| 96 | New Pane (Auto Layout) | ⌃⌘N | Panes | `newPaneAutoLayout` |
| 97 | Toggle Pane Zoom | ⇧⌘↩ | Panes | `toggleSplitZoom` |
| 98 | Increase Font Size for Workspace Terminals | ⌃⌘= | Panes | `increaseWorkspaceTerminalFontSize` |
| 99 | Decrease Font Size for Workspace Terminals | ⌃⌘- | Panes | `decreaseWorkspaceTerminalFontSize` |
| 100 | Reset Font Size for Workspace Terminals | ⌃⌘0 | Panes | `resetWorkspaceTerminalFontSize` |
| 101 | Equalize Splits | ⌃⇧⌘= | Panes | `equalizeSplits` |
| 102 | Resize Pane Left | ⌃⇧H | Panes | `resizePaneLeft` |
| 103 | Resize Pane Right | ⌃⇧L | Panes | `resizePaneRight` |
| 104 | Resize Pane Up | ⌃⇧K | Panes | `resizePaneUp` |
| 105 | Resize Pane Down | ⌃⇧J | Panes | `resizePaneDown` |
| 106 | Split Browser Right | ⌥⌘D | Panes | `splitBrowserRight` |
| 107 | Split Browser Down | ⌥⇧⌘D | Panes | `splitBrowserDown` |
| 108 | Toggle Canvas Layout | ⌃⌘C | Panes | `toggleCanvasLayout` |
| 109 | Canvas: Reveal Focused Pane | ⌃⌘R | Panes | `canvasRevealFocusedPane` |
| 110 | Canvas: Toggle Overview | ⌃⌘O | Panes | `canvasOverview` |
| 111 | Canvas: Zoom In | ⌥⌘= | Panes | `canvasZoomIn` |
| 112 | Canvas: Zoom Out | ⌥⌘- | Panes | `canvasZoomOut` |
| 113 | Canvas: Actual Size | ⌘0 | Panes | `canvasZoomReset` |
| 114 | Canvas: Tidy Panes | ⌃⌘T | Panes | `canvasTidy` |
| 115 | Canvas: Align Left Edges | None | Panes | `canvasAlignLeft` |
| 116 | Canvas: Align Right Edges | None | Panes | `canvasAlignRight` |
| 117 | Canvas: Align Top Edges | None | Panes | `canvasAlignTop` |
| 118 | Canvas: Align Bottom Edges | None | Panes | `canvasAlignBottom` |
| 119 | Canvas: Equalize Widths | None | Panes | `canvasEqualizeWidths` |
| 120 | Canvas: Equalize Heights | None | Panes | `canvasEqualizeHeights` |
| 121 | Canvas: Distribute Horizontally | None | Panes | `canvasDistributeHorizontally` |
| 122 | Canvas: Distribute Vertically | None | Panes | `canvasDistributeVertically` |
| 123 | Open Diff Viewer | ⌃⇧⌘D | Browser & Find | `openDiffViewer` |
| 124 | Save File Preview | ⌘S | Browser & Find | `saveFilePreview` |
| 125 | Toggle File Editor Word Wrap | ⌥Z | Browser & Find | `toggleFileEditorWordWrap` |
| 126 | Open Browser | ⇧⌘L | Browser & Find | `openBrowser` |
| 127 | Focus Address Bar | ⌘L | Browser & Find | `focusBrowserAddressBar` |
| 128 | Back | ⌘[ | Browser & Find | `browserBack` |
| 129 | Forward | ⌘] | Browser & Find | `browserForward` |
| 130 | Reload Page | ⌘R | Browser & Find | `browserReload` |
| 131 | Hard Refresh | ⇧⌘R | Browser & Find | `browserHardReload` |
| 132 | Zoom In | ⌘= | Browser & Find | `browserZoomIn` |
| 133 | Zoom Out | ⌘- | Browser & Find | `browserZoomOut` |
| 134 | Actual Size | ⌘0 | Browser & Find | `browserZoomReset` |
| 135 | Markdown Viewer: Zoom In | ⌘= | Browser & Find | `markdownZoomIn` |
| 136 | Markdown Viewer: Zoom Out | ⌘- | Browser & Find | `markdownZoomOut` |
| 137 | Markdown Viewer: Actual Size | ⌘0 | Browser & Find | `markdownZoomReset` |
| 138 | Find… | ⌘F | Browser & Find | `find` |
| 139 | Find Next | ⌘G | Browser & Find | `findNext` |
| 140 | Find Previous | ⌥⌘G | Browser & Find | `findPrevious` |
| 141 | Hide Find Bar | ⌥⇧⌘F | Browser & Find | `hideFind` |
| 142 | Use Selection for Find | ⌘E | Browser & Find | `useSelectionForFind` |
| 143 | Toggle Browser Developer Tools | ⌥⌘I | Browser & Find | `toggleBrowserDeveloperTools` |
| 144 | Show Browser JavaScript Console | ⌥⌘C | Browser & Find | `showBrowserJavaScriptConsole` |
| 145 | Enter Browser Focus Mode | ⌥⌘↩ | Browser & Find | `toggleBrowserFocusMode` |
| 146 | Toggle Browser Design Mode | ⌃⌥⌘D | Browser & Find | `toggleBrowserDesignMode` |
| 147 | Toggle React Grab | ⇧⌘G | Browser & Find | `toggleReactGrab` |
| 148 | Viewers: Scroll Down | J | Browser & Find | `diffViewerScrollDown` |
| 149 | Viewers: Scroll Up | K | Browser & Find | `diffViewerScrollUp` |
| 150 | Viewers: Scroll Half Page Down | ⌃D | Browser & Find | `diffViewerScrollHalfPageDown` |
| 151 | Viewers: Scroll Half Page Up | ⌃U | Browser & Find | `diffViewerScrollHalfPageUp` |
| 152 | Viewers: Scroll Down (Emacs) | ⌃N | Browser & Find | `diffViewerScrollDownEmacs` |
| 153 | Viewers: Scroll Up (Emacs) | ⌃P | Browser & Find | `diffViewerScrollUpEmacs` |
| 154 | Viewers: Scroll to Bottom | ⇧G | Browser & Find | `diffViewerScrollToBottom` |
| 155 | Viewers: Scroll to Top | G G | Browser & Find | `diffViewerScrollToTop` |
| 156 | Diff Viewer: Open File Search | / | Browser & Find | `diffViewerOpenFileSearch` |
| 157 | Diff Viewer: Next File | ] F | Browser & Find | `diffViewerNextFile` |
| 158 | Diff Viewer: Previous File | [ F | Browser & Find | `diffViewerPreviousFile` |
| 159 | Diff Viewer: Next Hunk | N | Browser & Find | `diffViewerNextHunk` |
| 160 | Diff Viewer: Previous Hunk | P | Browser & Find | `diffViewerPreviousHunk` |
| 161 | Diff Viewer: Toggle Viewed | V | Browser & Find | `diffViewerToggleViewed` |
| 162 | Simulator: Home | ⇧⌘H | Panes | `simulatorHome` |
| 163 | Simulator: Rotate Left | ⌘← | Panes | `simulatorRotateLeft` |
| 164 | Simulator: Rotate Right | ⌘→ | Panes | `simulatorRotateRight` |
| 165 | Simulator: Toggle Appearance | ⇧⌘A | Panes | `simulatorToggleAppearance` |
| 166 | Simulator: Toggle Software Keyboard | ⌘K | Panes | `simulatorToggleSoftwareKeyboard` |

Notes on the list:

- "Quit cmux" is the literal title in code: unbranded and not localized.
- "Show Sidebar Files … Cloud" show the package table (⌃1–⌃6). At run time the host resolver replaces them with ⌃N = position among the visible right-sidebar tabs, and unbinds a tab that is unavailable. In default ShellX: Files ⌃1, Find ⌃2, Vault ⌃3, Dock ⌃4, Feed and Cloud None.
- Equal defaults coexist through focus scopes: ⌘R Rename Tab vs Reload Page (browser focus), ⌘[ / ⌘] Focus Back/Forward vs browser Back/Forward, ⌘0 / ⌘= / ⌘- across canvas, browser and markdown, ⇧⌘H Flash Focused Panel vs Simulator: Home, ⇧⌘A Focus TextBox Input vs Simulator: Toggle Appearance, ⇧⌘G Group Selected Workspaces vs Toggle React Grab, ⌃N / ⌃P palette vs viewers.
- Cloud-only or Mac-only actions still listed: Open Team Picker, Show Sidebar Cloud, the five Simulator actions.

**Storage.** `~/.config/shellx/shellx.json`, object `shortcuts.bindings.<actionId>`. Forms read:

- object written by the recorder: `{ "first": { "key", "command", "shift", "option", "control", "keyCode"? }, "second"?: { … } }`
- string: `"cmd+shift+p"`
- array of two strings = chord: `["ctrl+b", "c"]` (one-element array = single stroke)
- `null` or `[]` = unbound

Presets write the string form for a stroke, a two-string array for a chord, and `null` for unbound. Optional `shortcuts.when` maps an action to a when-clause. Legacy per-action UserDefaults key `shortcut.<actionId>` (Data) is still read and is cleared on edit. Precedence: shellx.json → legacy UserDefaults → built-in default.

**Conflicts.** A recorded shortcut that collides with another action (same key and modifiers, taking when-clause scope and the 1…9 digit families into account) is rejected and not saved. A red banner appears under the row (red fill 12%, stroke 35%, corner 6): "This shortcut conflicts with %@ (%@)." with an "Undo" link. Other rejections: "Shortcuts must include ⌘ ⌥ ⌃ or ⇧", "This keystroke is reserved by macOS.", "Use a digit from 1 through 9.", "System-wide hotkeys must include Command, Option, or Control."

**Presets.** Applied through the Base Keymap preview (lines "%1$@: %2$@ → %3$@", macOS-conflict warnings, "Kept your own shortcut for %@."). Only the differences from the ShellX defaults are written; choosing ShellX removes them.

- iTerm2: Select Surface 1…9 → ⌘1…9; Select Workspace 1…9 → ⌥⌘1…9; Toggle Terminal Copy Mode → ⇧⌘C; Resize Pane Left/Right/Up/Down → ⌃⌘←/→/↑/↓.
- Terminal.app: Close Other Tabs in Pane → ⌥⌘W; Rename Tab → ⇧⌘I; Show Agent Inbox → unbound.
- tmux-style (prefix ⌃B, then): New Workspace c; Close Tab x; Close Workspace ⇧7 (&); Next/Previous Workspace n/p; Select Workspace 1…9; Rename Workspace , ; Go to Workspace w; Split Right ⇧5 (%); Split Down ⇧' ("); Focus Pane arrows; Focus Next Pane o; Toggle Pane Zoom z; Toggle Terminal Copy Mode [.

**Reset.** "Reset Defaults" removes the whole `shortcuts.bindings` object from shellx.json and every legacy UserDefaults binding; no confirmation in code. The per-row X writes "unbound" and then offers to restore the previous value.

## C. Workspace Colors

**Built-in palette (16, in order).** Red #C0392B, Crimson #922B21, Orange #A04000, Amber #7D6608, Olive #4A5C18, Green #196F3D, Teal #006B6B, Aqua #0E6B8C, Blue #1565C0, Navy #1A5276, Indigo #283593, Purple #6A1B9A, Magenta #AD1457, Rose #880E4F, Brown #7B3F00, Charcoal #3E4B5E.

**ShellX default.** A new workspace starts with Purple, read from the current palette, so editing Purple changes it.

**Indicator styles.** Left Rail, Solid Fill. Stored in UserDefaults `sidebarActiveTabIndicatorStyle`; legacy values migrate: `rail` → Left Rail; `border`, `wash`, `lift`, `typography`, `washRail`, `blueWashColorRail` → Solid Fill.

**Palette storage.** UserDefaults `workspaceTabColor.colors`, a dictionary name → hex; editing one colour persists the full effective palette. shellx.json: `workspaceColors.colors`, plus JSON-only `workspaceColors.paletteOverrides` / `customColors`.

**Choosing a colour outside Settings.**

- Workspace row context menu → submenu "Workspace Color": "Clear Color" (only when the workspace has a manual colour), "Choose Custom Color…" (opens the dialog "Custom Workspace Color" and adds a local "Custom N" entry), then the palette entries.
- Command palette: "Workspace Color: <Name>" per palette entry, and "Reset Workspace Color".

## D. Window shell

**Window.** AppKit `NSWindow` hosting SwiftUI. Content size 980×680; minimum 820×540. Titled, closable, resizable, full-size content view; no minimize; zoom button disabled. Title "Settings". Frame is autosaved. Toolbar has a sidebar toggle.

**Layout.** `NavigationSplitView` (balanced). Sidebar column width 210, sidebar list style. One section pane at a time. The last viewed section is kept in UserDefaults (`selectedSettingsSection`, `selectedSettingsSidebarEntry`); the default section is Account.

**Sidebar row.** Icon slot 16 pt wide, spacing 10, single-line title, optional caption subtitle (the parent section title, for a setting hit).

**Search.** Field in the sidebar, prompt "Search".

- Index: one entry per section (id, title, keywords) plus curated per-row entries (section, id, title, subtitle, shellx.json paths, synonyms).
- Matching: case- and diacritic-folded; every token must match. Ranking: exact → prefix → word boundary → substring → light typo → subsequence. Debounce 100 ms, off the main actor.
- Empty query: the grouped section list. Non-empty: a flat ranked list of hits; "No Results" when none.
- Clicking a hit selects its section, scrolls the row to the vertical centre (a section hit scrolls to the top) and pulses a highlight on the row: rounded rectangle corner 8, accent fill at 24%, 2.5 pt accent stroke, shadow radius 8; ramp-in 0.14 s, hold to 5 s, fade 0.9 s.
- The Keyboard Shortcuts list has its own search bar (80 ms debounce) with the key detector.

**Card and row metrics.**

- Detail pane: vertical stack, spacing 14, padding 20 on all sides.
- Section header: 13 pt semibold, secondary colour, leading padding 2.
- Card: corner radius 13 (continuous), fill = control background at 76%, 1 pt stroke = separator at 50%.
- Row: horizontal stack, spacing 12; padding 14 horizontal, 9 vertical; no fixed height. Title 13 pt medium. Subtitle caption (10 pt), secondary colour, at most 2 lines, 3 pt below the title. Control column width where set: 196, 250, 220, 140, 120, 100, 280, 300 or 330.
- Divider between rows: 1 pt, separator at 50%.
- Note inside a card: caption, padding 14 horizontal, 8 vertical.
- Controls are mostly small control size. Text sizes: body 13, callout 12, caption and footnote 10, headline 13 semibold. All scale with Global Font Magnification.

## E. Storage

**UserDefaults is the store.** Every row writes UserDefaults (domain `pro.shellx.desktop`) under its own key; the app reads from there.

**shellx.json is a sparse override file, not a mirror.** Path `~/.config/shellx/shellx.json` (legacy fallback `~/.config/shellx/settings.json`; schema https://shellx.pro/schema/shellx.json). A key present in the file is imported into UserDefaults as a "managed" value and re-asserted when the file changes; removing the key restores the value that was there before. About 229 paths are supported (`CmuxSettingsFileStore.supportedSettingsJSONPaths` in `Sources/KeyboardShortcutSettingsFileStore.swift`). Rows marked "settings only" have no path.

**What the Settings UI itself writes into shellx.json.** Only `app.accentColor` and `shortcuts.bindings` (rebinds and presets). "Reset All Settings" and "Reset Defaults" remove keys from it. JSON-only keys have no control and are edited by hand: `terminal.resumeCommands`, `workspaceColors.paletteOverrides`, `workspaceColors.customColors`, `notifications.hooks`, `shortcuts.when`, chords.

**Third store: the Ghostty config.** `~/Library/Application Support/pro.shellx.desktop/config.ghostty`, loaded after the user's own `~/.config/ghostty/config`. It holds the terminal look: theme pair, font, font size, cursor, padding, opacity, blur, option-as-alt, scrollback, middle-click, plus Sidebar Font Size and Tab Bar Font Size.

**Docs drift.** `docs/configuration.md` still names `cmux.json` and `~/.config/cmux`.

# ShellX for Windows, Like the Mac: Part 1 Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Windows app a Settings window laid out like the Mac's, with the Themes, Terminal, Keyboard Shortcuts, Workspace Colors, Sidebar, App and Reset rows of spec §5.4 working live and persisted.

**Architecture:** All rules are pure and live in `windows/shellx-model`: a typed `Settings` with Mac defaults and sparse JSON, a row catalogue that drives both rendering and search, Ghostty theme parsing, chrome colours derived from the active theme, workspace card styling and a rebindable keymap. `windows/shellx-app` holds one `SettingsService` entity shared by every window, a small control kit, and a `SettingsView` that runs in its own window or, as a fallback, as a panel in the main window. Stage A builds that foundation in order; Stage B is five independent tracks that only wire behaviour; Stage C finishes search, Reset, docs and the test installer.

**Tech Stack:** Rust 2024 (`windows/` workspace), GPUI `=0.2.2` vendored in `windows/vendor/`, serde/serde_json, libghostty-vt through `cmux-tui/crates/ghostty-vt`, winreg (already a dependency).

**Spec:** `docs/superpowers/specs/2026-11-13-windows-mac-parity-roadmap-design.md` (Vietnamese; binding; this plan covers §5 only). Row facts: `docs/superpowers/specs/2026-11-13-mac-settings-inventory.md` ("the inventory").

## Global Constraints

- Defaults follow the Mac (spec §4 rule 2). The only exception is Confirm Unsafe Pastes, which stays on. With default settings the main window may differ from 1.7.1 only in the rows of the table "Thay đổi so với 1.7.1" (spec §5.4); the chrome colours do not change.
- No dead rows: a row is drawn only when its catalogue entry has `wired: true`, and a task sets that flag only in the commit that makes the row work.
- Never call `stop_propagation` on a plain-text key-down except in a view that uses that key (spec §4 rule 3): on GPUI-Windows a stopped key-down produces no `WM_CHAR`.
- English copy is the Mac's `defaultValue` exactly as the inventory gives it. Vietnamese copy comes from the Mac's Vietnamese string table when the key exists there (search the repo's `.xcstrings` files for the key, e.g. `settings.section.themes`), otherwise it is written in the voice of the existing `strings.rs` entries. Both tables live in `windows/shellx-model/src/strings.rs`.
- Sizes come from the Mac, points mapped 1:1 to logical pixels (inventory §D).
- No new crate. gpui stays `=0.2.2`. No webview.
- Soft colours only: no gradients, glows or coloured shadows. Primary `#60a5fa`; running is yellow.
- Every rule is a pure function in `shellx-model` with tests that run on this Mac; `shellx-app` only wires.
- Commit the failing test before the code (`test(windows): … [red]`, then `feat(windows): …` or `fix(windows): …`).
- Commands, from `windows/`: `cargo test -p shellx-model <name>`; `cargo test --release -p shellx-app <name>` (never a debug build or debug test of `shellx-app`: it trips a known hashbrown assertion); from the repo root `scripts/shellx/check-windows-build.sh --release` type-checks the Windows-only code of the committed HEAD.
- Screenshots: `cargo build --release -p shellx-app`, then `dev/mac-shot.sh <png>` with a scratch `HOME` and `SHELLX_DEV_BACKGROUND=1`. Never touch the user's running `/Applications/ShellX.app`.
- Nothing in a settings file, log line or diagnostics report may hold a token, an email address or terminal content.
- Branches: integration branch `feat/windows-settings` from `develop`, worktree `.worktrees/windows-settings` (link the `ghostty` submodule into the worktree as the README says). Stage B tracks branch from the Stage A tip into `feat/windows-settings-themes`, `-terminal`, `-sidebar-app`, `-colors`, `-shortcuts`, each in its own worktree; the orchestrator merges each `--no-ff` into `feat/windows-settings` after its review. No push to `main`, no release, no publish. Merging into `develop` and building the test installer wait for the user's go-ahead.
- Stage B tracks must not add `Settings` fields, `Key` variants, catalogue rows or `Str` variants: Stage A defines all of them, so the tracks do not collide in `settings.rs`, `settings_catalog.rs` and `strings.rs`. A track that finds one missing adds it on `feat/windows-settings` first and rebases.
- If the day ends early, stop at the end of a task in this order: Stage A, then tracks T, R, S, C, K, then Stage C (spec §5.9). Stage C tasks F2–F4 run on whatever has been merged.

## Review Focus

Inputs a person will meet that no task's main tests would otherwise exercise; each has a test in its owning task.

1. **A `settings.json` that is not what this version wrote:** the 1.7.1 file with only `shell`, a hand-edited file with a number as a string, a value far out of range, an unknown key, an empty file, a UTF-8 BOM. Every readable key still applies, `shell` and unknown keys survive the next write, and nothing blocks the start. Tests: A1 `odd_values_are_skipped_per_key`, A2 `unknown_keys_and_shell_survive_a_write`, `an_unreadable_file_is_set_aside_not_overwritten`.
2. **Two ShellX processes sharing the file:** A changes the font size, then B (started earlier) changes the theme. Both values are in the file afterwards, and B never writes A's old value back. Test: A2 `a_stale_process_writes_only_the_key_it_changed`.
3. **Theme files as people really have them:** CRLF line endings, `#` comments, hex without `#`, no `background`, a `palette` index above 15, a user theme whose name differs from a bundled one only by case, a theme whose foreground equals its background. Tests: T1 `odd_theme_files_parse`, `user_theme_wins_a_case_insensitive_clash`; T2 `contrast_search_terminates_on_equal_colours`.
4. **Keys as GPUI-Windows reports them while rebinding:** `Alt+Shift+=` arriving as `+` with shift consumed, a binding equal to a fixed alias (`Shift+Insert`), `Ctrl+Alt+E` (AltGr), unbinding Settings… and still opening Settings with the gear. Tests: K1 `gpui_windows_shapes_match_their_chords`, `a_user_binding_takes_an_alias`, `altgr_and_system_keys_are_refused`, `an_unbound_action_has_no_chord`; K2 Step 2 confirms the gear does not go through the keymap.
5. **Vietnamese in Settings:** searching `phim tat` finds "Phím tắt", `đ` matches `d`, and a letter typed into the search field while the shortcut recorder is not listening is never swallowed. Tests: A3 `search_folds_vietnamese_marks`; K3 `an_idle_recorder_stops_no_key`.

---

## File Structure

New in `windows/shellx-model/src/`:

| File | Responsibility |
|---|---|
| `settings.rs` | `Settings`, its enums, `Key`, defaults, ranges, sparse JSON in and out |
| `settings_catalog.rs` | Groups, sections and rows: title, subtitle, control, key, search synonyms, `wired` |
| `settings_search.rs` | Folding, matching and ranking over the catalogue |
| `controls.rs` | Pure maths of the controls: slider and stepper values, hex parsing |
| `theme_file.rs` | Ghostty theme parsing, dark or light, the bundled list, the light/dark pair |
| `chrome.rs` | `Chrome` derived from a theme and an accent; contrast |
| `workspace_colors.rs` | The 16-colour palette and the workspace card style |
| `keymap.rs` | Actions, chords, acceptance rule, conflicts, lookup, labels |
| `build.rs` (crate root) | Embeds `Resources/ghostty/themes` as a table |

New in `windows/shellx-app/src/`:

| File | Responsibility |
|---|---|
| `settings_store.rs` | Reads and writes `settings.json` key by key, atomically |
| `ui/settings_service.rs` | The `SettingsService` entity: current `Settings`, debounced writes, change notification |
| `ui/controls/` (`mod.rs`, `toggle.rs`, `segmented.rs`, `picker.rs`, `slider.rs`, `stepper.rs`, `color_well.rs`, `recorder.rs`, `card.rs`) | The control kit |
| `ui/settings/mod.rs` | `SettingsView`: sidebar, search field, detail pane |
| `ui/settings/host.rs` | Own window or panel; `SHELLX_SETTINGS_HOST` |
| `ui/settings/rows.rs` | Draws a catalogue row with its control, bound to its key |
| `ui/settings/sections/` (`account.rs`, `terminal_cards.rs`, `updates.rs`, `about.rs`, `themes.rs`, `workspace_colors.rs`, `shortcuts.rs`, `reset.rs`) | Sections that need more than catalogue rows |
| `ui_state.rs` | `ui-state.json`: Settings window frame and last section |

Changed: `ui/settings.rs` is deleted once its sections have moved (A5). `ui/theme.rs` becomes dynamic (T3). `local_pty/settings.rs` keeps the shell logic and stores through `settings_store.rs` (A2).

---

# Stage A: foundation (in order, on `feat/windows-settings`)

### Task A1: The settings model

**Files:**
- Create: `windows/shellx-model/src/settings.rs`
- Modify: `windows/shellx-model/src/lib.rs` (`pub mod settings;`)

**Interfaces:**
- Produces:

```rust
pub enum LanguageChoice { System, En, Vi }
pub enum Appearance { System, Light, Dark }
pub enum Accent { ShellxBlue, System, Custom(Rgba) }
pub enum Placement { Top, AfterCurrent, End }
pub enum CursorStyle { Block, Bar, Underline, Hollow }
pub enum IndicatorStyle { LeftRail, SolidFill }
pub enum SidebarBackground { FollowTheme, MatchTerminal, Custom }

pub struct Settings { /* one pub field per row below */ }
impl Default for Settings { /* the Default column */ }

pub enum Key { /* one variant per field; */ }
impl Key {
    pub const ALL: &'static [Key];
    pub fn path(self) -> &'static str;
}
impl Settings {
    pub fn from_json(root: &serde_json::Map<String, serde_json::Value>) -> Settings;
    /// `None` when the field equals its default: the key is then absent from the file.
    pub fn to_value(&self, key: Key) -> Option<serde_json::Value>;
    /// Clamps to the range; `false` (and no change) for a value of the wrong type.
    pub fn set_from_value(&mut self, key: Key, value: &serde_json::Value) -> bool;
    pub fn reset(&mut self, key: Key);
}
pub fn get<'a>(root: &'a serde_json::Map<String, serde_json::Value>, path: &str) -> Option<&'a serde_json::Value>;
/// Inserts along a dotted path; `None` removes the key and prunes parents it leaves empty.
pub fn put(root: &mut serde_json::Map<String, serde_json::Value>, path: &str, value: Option<serde_json::Value>);
```

Fields, paths and defaults (ranges are inclusive; step in brackets):

| Field: type | JSON path | Default | Range |
|---|---|---|---|
| `language: LanguageChoice` | `app.language` (`"system"`, `"en"`, `"vi"`) | System | |
| `appearance: Appearance` | `app.appearance` (`"system"`, `"light"`, `"dark"`) | Dark | |
| `accent: Accent` | `app.accentColor` (`"cmux"`, `"system"`, `"#RRGGBB"`) | ShellxBlue | |
| `new_workspace_placement: Placement` | `app.newWorkspacePlacement` | AfterCurrent | |
| `inherit_working_directory: bool` | `app.workspaceInheritWorkingDirectory` | true | |
| `keep_workspace_open: bool` | `app.keepWorkspaceOpenWhenClosingLastSurface`, stored inverted as on the Mac: JSON `true` means the field is `false` | false | |
| `focus_history_includes_panes: bool` | `app.focusHistoryIncludesPanesAndTabs` | false | |
| `equalize_splits: bool` | `app.equalizeSplitsOnCreate` | false | |
| `hide_tab_close_button: bool` | `app.hideTabCloseButton` | false | |
| `theme_light: String` | `terminalConfig.theme.light` | `"Catppuccin Latte"` | |
| `theme_dark: String` | `terminalConfig.theme.dark` | `"ShellX"` | |
| `tab_bar_font_size: f32` | `terminalConfig.surface-tab-bar-font-size` | 11.0 | 8–14 [0.5] |
| `scroll_speed: f32` | `terminal.scrollSpeed` | 1.0 | 0.25–3.0 [0.05] |
| `copy_on_select: bool` | `terminal.copyOnSelect` | false | |
| `confirm_unsafe_paste: bool` | `terminal.confirmUnsafePaste` | **true** | |
| `font_family: Option<String>` | `terminalConfig.font-family` | None | |
| `font_size: f32` | `terminalConfig.font-size` | 13.0 | 4–96 [0.5] |
| `cursor_style: CursorStyle` | `terminalConfig.cursor-style` | Block | |
| `padding_x: u32`, `padding_y: u32` | `terminalConfig.window-padding-x`, `…-y` | 2, 2 | 0–200 |
| `scrollback_mb: u32` | `terminalConfig.scrollback-limit` | 50 | 0–100000 |
| `middle_click_paste: bool` | `terminalConfig.middle-click-action` | true | |
| `indicator_style: IndicatorStyle` | `workspaceColors.indicatorStyle` | LeftRail | |
| `subtle_selection: bool` | `workspaceColors.subtleSelection` | true | |
| `brighten_in_dark: bool` | `workspaceColors.brightenInDarkMode` | true | |
| `unselected_fill_opacity: f32` | `workspaceColors.unselectedFillOpacity` | 0.70 | 0–1 [0.05] |
| `selection_color: Option<Rgba>` | `workspaceColors.selectionColor` | None | |
| `palette: BTreeMap<String, Rgba>` (overrides of the built-in 16 only) | `workspaceColors.colors` (name → `"#RRGGBB"`) | empty | |
| `sidebar_background: SidebarBackground` | `sidebarAppearance.background` (`"theme"`, `"terminal"`, `"custom"`; a Windows key) | FollowTheme | |
| `sidebar_color: Rgba` | `sidebarAppearance.tintColor` | `#100B1D` | |
| `sidebar_font_size: f32` | `terminalConfig.sidebar-font-size` | 12.5 | 10–20 [0.5] |
| `hide_sidebar_details: bool` | `sidebar.hideAllDetails` | false | |
| `wrap_workspace_titles: bool` | `sidebar.wrapWorkspaceTitles` | false | |
| `truncate_path_from_start: bool` | `sidebar.truncatePathFromStart` (a Windows key) | false | |
| `show_branch_directory: bool` | `sidebar.showBranchDirectory` | true | |
| `bindings: BTreeMap<String, Option<String>>` | `shortcuts.bindings` (action id → chord text, or `null` for unbound) | empty | |

Value spellings not listed above (enum strings of `newWorkspacePlacement` and `indicatorStyle`, and the values of every `terminalConfig.*` key including the unit of `scrollback-limit`) are the ones the Mac writes: read them from `Sources/CmuxSettingsFileStore*.swift` and `Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/TerminalGhosttyOptionsCard.swift` and copy them.

- [ ] **Step 1: Write the failing tests** in `settings.rs`:

```rust
#[test] fn defaults_are_the_macs() {
    let s = Settings::default();
    assert_eq!(s.font_size, 13.0); assert_eq!((s.padding_x, s.padding_y), (2, 2));
    assert_eq!(s.scrollback_mb, 50); assert!(s.confirm_unsafe_paste); assert!(s.middle_click_paste);
    assert_eq!(s.appearance, Appearance::Dark); assert_eq!(s.theme_dark, "ShellX");
    assert_eq!(s.theme_light, "Catppuccin Latte"); assert_eq!(s.sidebar_font_size, 12.5);
    assert!(!s.focus_history_includes_panes);
}
#[test] fn a_default_settings_writes_no_key() { /* to_value is None for every Key::ALL */ }
#[test] fn every_key_round_trips() { /* set a non-default value per key, put, from_json, compare */ }
#[test] fn numbers_are_clamped_and_snapped() { /* font-size 500 -> 96; 13.26 -> 13.5; scrollSpeed 0 -> 0.25 */ }
#[test] fn odd_values_are_skipped_per_key() {
    // {"terminalConfig":{"font-size":"big","cursor-style":"bar"},"app":{"appearance":7}}
    // -> font_size 13.0, cursor_style Bar, appearance Dark
}
#[test] fn keep_workspace_open_is_stored_inverted() { /* JSON true -> field false; field true -> JSON false */ }
#[test] fn accent_reads_cmux_system_and_hex() { /* "cmux", "system", "#ff8800"; "#zz" -> ShellxBlue */ }
#[test] fn put_prunes_empty_parents_and_keeps_siblings() { /* put(app.language, None) leaves "shell" and other app.* keys */ }
#[test] fn key_paths_are_unique() {}
```

- [ ] **Step 2:** Run `cargo test -p shellx-model settings::` and see them fail to compile. Commit `[red]`.
- [ ] **Step 3:** Implement `settings.rs` as the Interfaces block says. `from_json` reads each key on its own through `get`, so one bad value never affects another.
- [ ] **Step 4:** Run `cargo test -p shellx-model settings::`; all pass.
- [ ] **Step 5:** Commit `feat(windows): the settings model with the Mac's defaults and sparse JSON`.

### Task A2: The settings file and the service

**Files:**
- Create: `windows/shellx-app/src/settings_store.rs`, `windows/shellx-app/src/ui/settings_service.rs`
- Modify: `windows/shellx-app/src/local_pty/settings.rs` (`SettingsFile` reads and writes through the store), `windows/shellx-app/src/ui/app.rs` (create the service before the window), `windows/shellx-app/src/main.rs` and `ui/mod.rs` (modules)

**Interfaces:**
- Consumes: A1 `Settings`, `Key`, `get`, `put`.
- Produces:

```rust
// settings_store.rs
pub struct SettingsStore { /* path: Option<PathBuf> */ }
impl SettingsStore {
    pub fn new(path: PathBuf) -> Self;
    pub fn at_native_dir() -> Self;                       // paths::native_dir()/settings.json; no folder -> a store that holds nothing
    pub fn load(&self) -> Settings;
    /// Reads the file again, changes only `path`, writes a temporary file and renames it.
    pub fn write(&self, path: &str, value: Option<serde_json::Value>) -> io::Result<()>;
    pub fn read_raw(&self, path: &str) -> Option<serde_json::Value>;
}

// ui/settings_service.rs
pub struct SettingsService { /* settings, store, pending writes */ }
impl SettingsService {
    pub fn init(cx: &mut App);                             // loads, stores the entity in a Global
    pub fn entity(cx: &App) -> Entity<SettingsService>;
    pub fn settings(&self) -> &Settings;
    /// Applies now, notifies observers, writes 300 ms after the last change to this key.
    pub fn set(&mut self, key: Key, value: serde_json::Value, cx: &mut Context<Self>);
    pub fn reset(&mut self, key: Key, cx: &mut Context<Self>);
    pub fn reset_all(&mut self, cx: &mut Context<Self>);   // every Key::ALL, written at once
    pub fn flush(&mut self);                               // pending writes, on quit
}
pub fn current(cx: &App) -> &Settings;
```

A file that exists but is not a JSON object, or is over `SETTINGS_MAX_BYTES`, is renamed to `settings.json.bad-<unix seconds>` before the first write, with one log line that names only the reason category (the pattern of `links_store.rs`). A leading UTF-8 BOM is accepted. `startup::orderly_quit` calls `flush`.

- [ ] **Step 1: Write the failing tests** (`settings_store.rs`, on a temporary folder):

```rust
#[test] fn unknown_keys_and_shell_survive_a_write() { /* {"shell":{...},"future":{"x":1}} then write(app.language) */ }
#[test] fn a_stale_process_writes_only_the_key_it_changed() {
    // store_b.load(); store_a.write("terminalConfig.font-size", 15); store_b.write("terminalConfig.theme.dark", "Dracula");
    // file has font-size 15 and theme.dark Dracula
}
#[test] fn an_unreadable_file_is_set_aside_not_overwritten() { /* "not json": load() gives defaults; after write, a settings.json.bad-* holds the old bytes */ }
#[test] fn a_bom_and_an_empty_file_load_as_defaults_or_values() {}
#[test] fn the_log_line_for_a_bad_file_holds_none_of_its_text() {}
#[test] fn a_store_without_a_folder_loads_defaults_and_fails_writes_quietly() {}
```

and in `local_pty/settings.rs`: `the_shell_choice_keeps_its_1_7_1_shape` (a 1.7.1 file loads the same `ShellChoice`, and saving it leaves the other keys).

- [ ] **Step 2:** Run `cargo test --release -p shellx-app settings_store`; fails to compile. Commit `[red]`.
- [ ] **Step 3:** Implement the store, move `SettingsFile::load`/`save` onto `read_raw("shell")`/`write("shell", …)`, implement the service with a per-key debounce on the GPUI background executor.
- [ ] **Step 4:** Run `cargo test --release -p shellx-app settings_store local_pty::settings`; pass.
- [ ] **Step 5:** Commit `feat(windows): settings.json is written key by key and shared through one service`.

### Task A3: The row catalogue, its strings, and search

**Files:**
- Create: `windows/shellx-model/src/settings_catalog.rs`, `windows/shellx-model/src/settings_search.rs`
- Modify: `windows/shellx-model/src/strings.rs` (new `Str` variants and both tables), `lib.rs`

**Interfaces:**
- Consumes: A1 `Key`, `Settings`; `strings::{Str, Lang, t}`.
- Produces:

```rust
pub enum Group { General, Terminal, Workspace, SidebarAndDock, KeyboardAndAdvanced, ShellX }
pub enum Section { Account, App, Themes, Terminal, WorkspaceColors, Sidebar, KeyboardShortcuts, Reset, Updates, About }
pub enum Control {
    Toggle,
    Segmented(&'static [(Str, &'static str)]),            // label, JSON value
    Picker(&'static [(Str, &'static str)]),
    Slider { min: f32, max: f32, step: f32, unit: Unit },  // Unit: Points, Times, Percent
    Stepper { min: f32, max: f32, step: f32 },
    Number { min: f32, max: f32, unit: Unit },             // Unit::Megabytes
    Color { resettable: bool },
    Custom,                                                // drawn by a section file
}
pub struct Row {
    pub id: &'static str,              // the key's path, or a fixed id for Custom rows
    pub key: Option<Key>,
    pub section: Section,
    pub title: Str,
    pub subtitle: Option<Str>,
    pub control: Control,
    pub synonyms: &'static str,        // space separated, English and unaccented Vietnamese
    pub wired: bool,
    pub enabled: fn(&Settings) -> bool,
    pub visible: fn(&Settings) -> bool,
}
pub fn groups() -> &'static [(Group, &'static [Section])];
pub fn group_title(g: Group) -> Str;
pub fn section_title(s: Section) -> Str;
pub fn rows(section: Section) -> impl Iterator<Item = &'static Row>;
pub fn row(id: &str) -> Option<&'static Row>;

// settings_search.rs
pub struct Hit { pub section: Section, pub row: Option<&'static str>, pub rank: u8 }
pub fn fold(text: &str) -> String;     // lower case, Vietnamese marks removed, đ -> d
pub fn search(query: &str, lang: Lang) -> Vec<Hit>;        // wired rows and their sections only, best first
```

The catalogue holds every row of the tables in spec §5.4, in the Mac's order, plus `Custom` entries for: the Shell card and the Display card (Terminal), the Terminal Theme summary and the gallery (Themes), the 16 palette rows and Reset Palette (Workspace Colors), the shortcut list and Reset Default Shortcuts (Keyboard Shortcuts), Reset All Settings, and the existing Account, Updates and About content. Ranges and options are those of §5.4. Group order and titles: General, Terminal, Workspace, Sidebar & Dock, Keyboard & Advanced, ShellX (spec §5.3). `enabled` and `visible` encode the §5.4 conditions: Subtle Selection Highlight is disabled with Solid Fill; Brighten Colors in Dark Mode and Unselected Fill Opacity are disabled with Left Rail; Sidebar Color is visible only with Custom Color; the rows below Hide All Sidebar Details are disabled while it is on. Every row starts with `wired: false` except the migrated Account, Shell, Display, Updates and About entries.

- [ ] **Step 1: Write the failing tests:**

```rust
// settings_catalog.rs
#[test] fn every_key_has_exactly_one_row_or_is_custom_owned() { /* Key::ALL minus {ThemeLight, ThemeDark, Palette, Bindings} each appear once */ }
#[test] fn sections_follow_the_macs_order() { /* General = [Account, App, Themes]; KeyboardAndAdvanced = [KeyboardShortcuts, Reset]; ShellX = [Updates, About] */ }
#[test] fn english_titles_are_the_macs() {
    assert_eq!(t(Lang::En, row("terminalConfig.font-size").unwrap().title), "Font Size");
    assert_eq!(t(Lang::En, row("workspaceColors.subtleSelection").unwrap().title), "Subtle Selection Highlight");
    assert_eq!(t(Lang::En, row("sidebar.hideAllDetails").unwrap().title), "Hide All Sidebar Details");
}
#[test] fn every_string_has_both_languages() { /* no empty value in either table for the new Str variants */ }
#[test] fn conditions_follow_the_spec() { /* the four enabled/visible rules above */ }
// settings_search.rs
#[test] fn search_folds_vietnamese_marks() { assert_eq!(fold("Phím tắt Đổi"), "phim tat doi"); }
#[test] fn every_token_must_match_and_rank_is_exact_prefix_word_substring() {}
#[test] fn unwired_rows_are_not_found() {}
#[test] fn an_empty_query_has_no_hits() {}
```

- [ ] **Step 2:** Run `cargo test -p shellx-model settings_catalog:: settings_search::`; fails. Commit `[red]`.
- [ ] **Step 3:** Add the `Str` variants (prefix `Settings…`) with both tables, then the catalogue and the search.
- [ ] **Step 4:** Run the same command; pass. Run `cargo test -p shellx-model`; nothing else broke.
- [ ] **Step 5:** Commit `feat(windows): the Settings row catalogue, its strings in two languages, and search`.

### Task A4: The control kit

**Files:**
- Create: `windows/shellx-model/src/controls.rs`; `windows/shellx-app/src/ui/controls/{mod,toggle,segmented,picker,slider,stepper,color_well,card}.rs`
- Modify: `windows/shellx-app/src/ui/mod.rs`

**Interfaces:**
- Produces (model):

```rust
pub fn slider_value(fraction: f32, min: f32, max: f32, step: f32) -> f32;   // fraction of the track, clamped, snapped
pub fn slider_fraction(value: f32, min: f32, max: f32) -> f32;
pub fn stepped(value: f32, steps: i32, min: f32, max: f32, step: f32) -> f32;
pub fn parse_hex(text: &str) -> Option<Rgba>;                                // "#RRGGBB" or "RRGGBB", any case, trimmed
pub fn format_value(value: f32, unit: Unit) -> String;                       // "13 pt", "1.00×", "70%", "50 MB"
```

- Produces (app): stateless controls are functions, controls with their own state are entities.

```rust
pub fn toggle(id: impl Into<ElementId>, on: bool, disabled: bool, on_change: impl Fn(bool, &mut Window, &mut App) + 'static) -> Stateful<Div>;
pub fn segmented(id: impl Into<ElementId>, options: &[(SharedString, &'static str)], selected: &str, disabled: bool, on_pick: impl Fn(&'static str, &mut Window, &mut App) + 'static) -> Stateful<Div>;
pub struct Picker;      // entity: a button showing the selected label; opens ui::menu::popover
pub struct Slider;      // entity: drag, click on the track, Left/Right keys; emits SliderEvent::Changed(f32)
pub struct Stepper;     // entity: value label, − and + buttons, Up/Down keys; emits StepperEvent::Changed(f32)
pub struct ColorWell;   // entity: swatch button; popover with a "#RRGGBB" TextField and a swatch grid; emits ColorEvent::Picked(Rgba)
pub fn card(title: Option<SharedString>) -> Div;                             // radius 13, 1 px border, rows divided by 1 px
pub fn row(title: SharedString, subtitle: Option<SharedString>, control: impl IntoElement, disabled: bool) -> Div;
```

Metrics (spec §5.3, inventory §D): row padding 14 horizontal and 9 vertical, title 13 medium, subtitle 10 in the muted colour with at most 2 lines, card radius 13. Switch 32×18, segmented and picker height 22. A disabled control is drawn at half opacity and takes no input. Every control is reachable with Tab and operable with the keyboard. A control's key handler stops only the keys it uses (Global Constraints).

- [ ] **Step 1: Write the failing tests** in `controls.rs`: `slider_snaps_and_clamps` (0.5 of 8–14 step 0.5 → 11.0; fraction 2.0 → 14.0), `stepped_moves_by_whole_steps`, `hex_parses_with_and_without_hash` (`"#60A5FA"`, `"60a5fa "`; `"#12"`, `"#gggggg"` → None), `values_format_with_their_unit`.
- [ ] **Step 2:** Run `cargo test -p shellx-model controls::`; fails. Commit `[red]`.
- [ ] **Step 3:** Implement `controls.rs`, then the kit. `ColorWell`'s field is the existing `ui::text_field::TextField`; an invalid hex draws the field's border in the error colour and emits nothing.
- [ ] **Step 4:** Run `cargo test -p shellx-model controls::` and `cargo build --release -p shellx-app`; both succeed with no warning.
- [ ] **Step 5:** Commit `feat(windows): the Settings control kit`.

### Task A5: The Settings view, its two hosts, and the old sections moved in

**Files:**
- Create: `windows/shellx-app/src/ui/settings/{mod,host,rows}.rs`, `ui/settings/sections/{account,terminal_cards,updates,about}.rs`, `windows/shellx-app/src/ui_state.rs`
- Delete: `windows/shellx-app/src/ui/settings.rs` (its code moves into the section files)
- Modify: `ui/root.rs` (`settings: Entity<SettingsPanel>` becomes `settings: SettingsHost`; `open_settings`, `show_settings`, `set_settings_open`, `panels`, `close_top_panel`), `ui/app.rs` (`on_window_closed`), `ui/titlebar.rs` (a close-only caption for the Settings window)

**Interfaces:**
- Consumes: A2 `SettingsService`; A3 catalogue; A4 controls.
- Produces:

```rust
// ui/settings/mod.rs
pub struct SettingsView { /* section, search field, scroll handles, per-row control entities */ }
impl SettingsView {
    pub fn new(account: Entity<AccountService>, cx: &mut Context<Self>) -> Self;
    pub fn show_section(&mut self, section: Section, cx: &mut Context<Self>);
    pub fn show_row(&mut self, row_id: &'static str, cx: &mut Context<Self>);   // select its section, scroll to it (F1 adds the highlight)
}
pub enum SettingsViewEvent { Close, OpenSignIn(GooglePurpose), CheckForUpdates }

// ui/settings/host.rs
pub enum HostKind { Window, Panel }
pub fn host_kind(env: Option<&str>) -> HostKind;                // "panel" (trimmed, any case) -> Panel; else Window
pub struct SettingsHost { /* view, kind, the open WindowHandle if any */ }
impl SettingsHost {
    pub fn new(account: Entity<AccountService>, cx: &mut Context<RootView>) -> Self;
    pub fn open(&mut self, section: Option<Section>, window: &mut Window, cx: &mut Context<RootView>);  // second call brings it to the front
    pub fn close(&mut self, cx: &mut Context<RootView>);
    pub fn is_open_as_panel(&self) -> bool;                      // what `Panels { settings }` reads
    pub fn panel_view(&self) -> Option<Entity<SettingsView>>;    // what RootView::render draws
}

// ui/settings/rows.rs
/// The row's card line with its control, reading and writing the row's key through the service.
pub fn catalogue_row(row: &'static Row, view: &mut SettingsView, cx: &mut Context<SettingsView>) -> Option<Div>;  // None: not wired, or not visible

// ui_state.rs
pub struct UiState { pub settings_frame: Option<(f32, f32, f32, f32)>, pub settings_section: Option<String> }
pub fn load() -> UiState;  pub fn save(state: &UiState);        // native_dir()/ui-state.json; an unreadable file is the default
```

Behaviour (spec §5.3): window title "Settings" / "Cài đặt", content 980×680, minimum 820×540, resizable, close button only, same `app_id`. Opened with `cx.open_window`; when that fails, or `SHELLX_SETTINGS_HOST=panel`, the same view is drawn as the panel the app has today (same `Panel::Settings` rules). Esc closes the host when no popover is open. When the last non-Settings window closes, the Settings window closes too and the app quits as today. The frame and the last section are stored in `ui-state.json`; the first section ever is Account. Left column 210 wide with the search field on top (the field filters nothing until F1) and the groups below; a group with no wired row in any section is not drawn; a section with no wired row is not drawn. The detail pane has padding 20 and card spacing 14. "Đăng nhập…" in Account emits `OpenSignIn`; `RootView` activates the main window and opens the sign-in dialog there. `SHELLX_DEV_PREVIEW=settings` keeps working and also accepts `settings:<section id>` (`account`, `app`, `themes`, `terminal`, `workspaceColors`, `sidebar`, `keyboardShortcuts`, `reset`, `updates`, `about`).

- [ ] **Step 1: Write the failing tests:** `host.rs`: `only_panel_selects_the_panel_host` (`None`, `""`, `"window"`, `"1"` → Window; `"panel"`, `" Panel "` → Panel). `ui_state.rs`: `an_unreadable_ui_state_is_the_default`, `the_frame_and_section_round_trip`. `settings/mod.rs`: `sections_without_a_wired_row_are_not_listed` (a pure helper `listed_sections() -> Vec<(Group, Vec<Section>)>`), `the_preview_variable_names_a_section`.
- [ ] **Step 2:** Run `cargo test --release -p shellx-app settings`; fails. Commit `[red]`.
- [ ] **Step 3:** Build the view and both hosts; move the Account, Shell, Display, Updates and About code out of `ui/settings.rs` into the section files without changing what they do; delete `ui/settings.rs`.
- [ ] **Step 4:** Run `cargo test --release -p shellx-app` (all green) and `cargo build --release -p shellx-app`.
- [ ] **Step 5: Screenshots.** `SHELLX_DEV_PREVIEW=settings:account`, `settings:terminal`, `settings:about`, each in the window host and with `SHELLX_SETTINGS_HOST=panel`, in `SHELLX_LANG=vi` and `en`. Check each against inventory §D: 210 column, groups General / Terminal / ShellX only, the old content complete.
- [ ] **Step 6:** Run `scripts/shellx/check-windows-build.sh --release` on the commit; it passes.
- [ ] **Step 7:** Commit `feat(windows): Settings is a window laid out like the Mac's, with a panel fallback; the old sections moved in`.

---

# Stage B: five tracks (independent after Stage A)

## Track T: Themes (`feat/windows-settings-themes`)

### Task T1: Theme files and the bundled list

**Files:**
- Create: `windows/shellx-model/src/theme_file.rs`, `windows/shellx-model/build.rs`
- Modify: `windows/shellx-model/Cargo.toml` (`build = "build.rs"`), `lib.rs`, `scripts/shellx/check-windows-build.sh:74` and `scripts/shellx/release/build-windows-cross.sh:284` (add `Resources/ghostty/themes` to both `git archive` path lists)

**Interfaces:**
- Produces:

```rust
pub struct TermTheme {
    pub name: String,
    pub background: Rgba, pub foreground: Rgba,
    pub cursor: Rgba, pub cursor_text: Rgba,
    pub selection_bg: Rgba, pub selection_fg: Rgba,
    pub ansi: [Rgba; 16],
}
pub fn parse(name: &str, text: &str) -> TermTheme;      // missing keys per spec §5.5
pub fn shellx() -> TermTheme;                            // the bundled "ShellX" file
pub fn is_dark(theme: &TermTheme) -> bool;               // 0.299R + 0.587G + 0.114B of background < 0.5
pub fn bundled() -> &'static [(&'static str, &'static str)];   // name, file text; sorted case-insensitively
pub struct ThemeSet { /* bundled plus user files */ }
impl ThemeSet {
    pub fn new(user: Vec<(String, String)>) -> ThemeSet;       // a user name wins a case-insensitive clash
    pub fn get(&self, name: &str) -> Option<TermTheme>;        // case-insensitive
    pub fn dark(&self, query: &str) -> Vec<&str>;              // names, folded substring match on the query
    pub fn light(&self, query: &str) -> Vec<&str>;
}
/// The theme in use: the pair's side for `dark`, falling back to the default of that side, then to ShellX.
pub fn active(set: &ThemeSet, settings: &Settings, dark: bool) -> TermTheme;
pub fn is_dark_mode(appearance: Appearance, system_dark: bool) -> bool;
```

`build.rs` reads `../../Resources/ghostty/themes` (relative to the crate) and writes a `bundled_themes.rs` of `include_str!` entries into `OUT_DIR`; it prints `cargo:rerun-if-changed` for the folder. Missing keys: `cursor-color` → foreground, `cursor-text` → background, `selection-background` → foreground, `selection-foreground` → background, `palette` slots and `background`/`foreground` → the ShellX theme's.

- [ ] **Step 1: Write the failing tests:** `the_shellx_theme_is_the_bundled_file` (background `#0b0716`, foreground `#cdc7e0`, cursor `#60a5fa`, selection `#233356`/`#e6e2f2`, `ansi[0] == #211a37`, `ansi[5] == #c49af0`), `there_are_464_bundled_themes_386_dark_78_light`, `odd_theme_files_parse` (CRLF, `# comment` lines, `background = 0b0716`, `palette = 16=#ffffff` ignored, a duplicate key keeps the last), `a_theme_without_selection_swaps_foreground_and_background`, `user_theme_wins_a_case_insensitive_clash`, `the_pair_side_follows_dark_mode` (default settings: dark → ShellX, light → Catppuccin Latte), `a_missing_theme_name_falls_back_to_the_side_default`.
- [ ] **Step 2:** Run `cargo test -p shellx-model theme_file::`; fails. Commit `[red]`.
- [ ] **Step 3:** Implement; change the two scripts.
- [ ] **Step 4:** Run `cargo test -p shellx-model theme_file::`; pass. Run `scripts/shellx/check-windows-build.sh --release`; it passes (this proves the archive carries the themes).
- [ ] **Step 5:** Commit `feat(windows): Ghostty theme files, the 464 bundled themes and the light/dark pair`.

### Task T2: Chrome derived from the theme

**Files:**
- Create: `windows/shellx-model/src/chrome.rs`
- Modify: `windows/shellx-model/src/palette.rs` (keep the chrome constants as the ShellX anchor; remove `ANSI`, `TERM_BG`, `TERM_FG`, `TERM_CURSOR`, `TERM_SELECTION` and their tests in T3), `lib.rs`

**Interfaces:**
- Consumes: T1 `TermTheme`, `is_dark`; A1 `Accent`, `SidebarBackground`.
- Produces:

```rust
pub struct Chrome {
    pub dark: bool,
    pub bg: Rgba, pub panel: Rgba, pub raise: Rgba, pub line: Rgba, pub border: Rgba,
    pub text: Rgba, pub text_hi: Rgba, pub muted: Rgba,
    pub primary: Rgba, pub primary_soft: Rgba, pub primary_line: Rgba, pub primary_text: Rgba,
    pub running: Rgba, pub done: Rgba, pub error: Rgba,                 // fills and dots: fixed hues
    pub running_text: Rgba, pub done_text: Rgba, pub error_text: Rgba,  // the same hues adjusted for contrast on `bg`
    pub selection_title: Rgba, pub indicator_unfocused: Rgba,
    pub session_selected: Rgba, pub session_hover: Rgba,
    pub sidebar_bg: Rgba, pub sidebar_text: Rgba, pub sidebar_muted: Rgba,
}
pub fn contrast(a: Rgba, b: Rgba) -> f32;                               // WCAG ratio, 1.0–21.0
/// Moves `fg` away from `bg` (towards white on dark, black on light) until the ratio is at least `min`.
pub fn ensure_contrast(fg: Rgba, bg: Rgba, min: f32) -> Rgba;
pub fn accent_color(accent: &Accent, system: Option<Rgba>) -> Rgba;     // System with None -> #60a5fa
pub fn accent_from_dwm(abgr: u32) -> Rgba;                              // the DWM AccentColor registry value
pub fn chrome(theme: &TermTheme, accent: Rgba, sidebar: SidebarBackground, sidebar_color: Rgba) -> Chrome;
```

Rules (spec §5.5): the ShellX theme with accent `#60a5fa` and `FollowTheme` returns exactly today's constants (`palette.rs` and `SESSION_SELECTED`/`SESSION_HOVER` of `ui/theme.rs`). For another theme the surface steps go from `background` towards `foreground`; `text` comes from `foreground`. Sidebar with `FollowTheme`: ShellX → `#100b1d`, another dark theme → background + 2% white, a light theme → background + 3% black; `MatchTerminal` → the theme background; `Custom` → `sidebar_color`. `sidebar_text` and `sidebar_muted` are chosen for the sidebar background. `text` on `bg`, `sidebar_text` on `sidebar_bg`, `primary_text` on `bg` and the three `*_text` colours on `bg` reach 4.5:1; `muted` on `bg` and `sidebar_muted` on `sidebar_bg` reach 3:1.

- [ ] **Step 1: Write the failing tests:**

```rust
#[test] fn the_shellx_theme_gives_todays_chrome_exactly() {
    let c = chrome(&shellx(), Rgba::rgb(0x60a5fa), SidebarBackground::FollowTheme, Rgba::rgb(0x100b1d));
    assert_eq!(c.bg, palette::BG); assert_eq!(c.panel, palette::PANEL); assert_eq!(c.raise, palette::RAISE);
    assert_eq!(c.line, palette::LINE); assert_eq!(c.border, palette::BORDER); assert_eq!(c.text, palette::TEXT);
    assert_eq!(c.text_hi, palette::TEXT_HI); assert_eq!(c.muted, palette::MUTED);
    assert_eq!(c.primary_text, palette::PRIMARY_TEXT); assert_eq!(c.sidebar_bg, palette::PANEL);
    assert_eq!(c.running_text, palette::RUNNING); assert_eq!(c.session_selected, Rgba::rgb(0x1a1430));
}
#[test] fn every_bundled_theme_is_readable() { /* all 464: the six 4.5:1 pairs and the two 3:1 pairs above */ }
#[test] fn contrast_search_terminates_on_equal_colours() { /* fg == bg, dark and light */ }
#[test] fn sidebar_follows_the_macs_rule() { /* +2% white on a dark theme, +3% black on Catppuccin Latte, custom colour kept */ }
#[test] fn a_custom_accent_colours_primary_only() { /* running/done/error unchanged */ }
#[test] fn the_dwm_value_is_abgr() { assert_eq!(accent_from_dwm(0xff_d7_78_00), Rgba::rgb(0x0078d7)); }
```

- [ ] **Step 2:** Run `cargo test -p shellx-model chrome::`; fails. Commit `[red]`.
- [ ] **Step 3:** Implement. The ShellX case is an explicit branch that returns the constants; the general case is the derivation.
- [ ] **Step 4:** Run `cargo test -p shellx-model chrome::`; pass.
- [ ] **Step 5:** Commit `feat(windows): chrome colours derived from the terminal theme, readable on all 464 themes`.

### Task T3: The live theme in the app

**Files:**
- Modify: `windows/shellx-app/src/ui/theme.rs`, `term_core.rs:10,72-80`, `ui/term_view.rs:69,1206-1207,1677-1727`, every file that names a `palette::` colour or a colour literal (`ui/sidebar.rs`, `tab_bar.rs`, `login.rs`, `pairing.rs`, `root.rs`, `text_field.rs`, `button.rs`, `smoke.rs`, the moved settings sections), `os_info.rs`, `ui/settings_service.rs`
- Modify: `windows/shellx-model/src/palette.rs` (remove the terminal constants)

**Interfaces:**
- Consumes: T1, T2; A2 service.
- Produces:

```rust
// ui/theme.rs
pub struct Active { pub chrome: Chrome, pub term: TermTheme }
pub fn active() -> Active;                                   // a copy of the process-wide current theme
pub fn set_active(active: Active);                           // called by the service; the caller then refreshes every window
pub fn primary() -> Hsla; pub fn primary_soft() -> Hsla; pub fn primary_line() -> Hsla; pub fn primary_text() -> Hsla;
pub fn running() -> Hsla; pub fn error() -> Hsla;            // plus the existing bg(), panel(), raise(), line(), border(), text(), text_hi(), muted(), done()
pub fn running_text() -> Hsla; pub fn done_text() -> Hsla; pub fn error_text() -> Hsla;
pub fn sidebar_bg() -> Hsla; pub fn sidebar_text() -> Hsla; pub fn sidebar_muted() -> Hsla;
pub fn session_selected() -> Hsla; pub fn session_hover() -> Hsla;
// os_info.rs
pub fn system_accent() -> Option<Rgba>;                      // Windows: HKCU\Software\Microsoft\Windows\DWM\AccentColor; elsewhere None
// term_core.rs
impl TermCore { pub fn set_theme(&mut self, theme: &TermTheme); }   // default fg/bg/cursor and the 16 palette slots, at any time
```

The existing zero-argument colour functions keep their signatures and read the current `Active`, so their 139 call sites do not change. The service recomputes `Active` when `appearance`, `accent`, `theme_light`, `theme_dark`, `sidebar_background` or `sidebar_color` changes and when the window appearance changes (`observe_window_appearance`), calls `set_active`, calls `set_theme` on every open `TermCore`, and refreshes every window. If `ghostty-vt` cannot change the palette of a live terminal, add that method to `cmux-tui/crates/ghostty-vt` next to `set_default_colors`. The selection is drawn with `selection_bg` under the cells and `selection_fg` for their text. The Google button keeps its colours.

- [ ] **Step 1: Write the failing tests** (`shellx-app`): `no_ui_file_names_a_palette_colour_or_a_literal` (walks `src/ui` and `src/term_core.rs`; fails on `palette::` followed by an upper-case identifier, `Rgba::rgb(0x` or `rgb(0x`, outside `ui/theme.rs` and `ui/google_button.rs`), `a_new_terminal_starts_with_the_active_theme` (replaces `term_core.rs`'s default-colour test: `frame.default_colors` and `palette_color(0)` equal the ShellX theme's), `set_theme_recolours_a_live_terminal`.
- [ ] **Step 2:** Run `cargo test --release -p shellx-app theme term_core`; the guard fails listing today's 27 `palette::` uses and 45 literals. Commit `[red]`.
- [ ] **Step 3:** Implement `Active`, replace every listed use with a `theme::` function, wire the service.
- [ ] **Step 4:** Run `cargo test --release -p shellx-app` and `cargo test -p shellx-model`; all green.
- [ ] **Step 5: Screenshots.** Before this task, on the Stage A tip, save the main window showing `printf` output in all 16 ANSI colours with a selection. After: the same shot with defaults (chrome identical; the eight ANSI slots and the selection differ as the spec's table says), with `app.appearance = "light"`, and with `terminalConfig.theme.dark` set to `Dracula` and to `Gruvbox Dark` (set in a scratch `settings.json`).
- [ ] **Step 6:** Commit `feat(windows): the app and its terminals follow the active theme`.

### Task T4: The Themes section

**Files:**
- Create: `windows/shellx-app/src/ui/settings/sections/themes.rs`
- Modify: `windows/shellx-model/src/settings_catalog.rs` (`wired: true` for Appearance, Accent Color, Terminal Theme, the gallery), `ui/settings/mod.rs` (dispatch)

**Interfaces:**
- Consumes: T1 `ThemeSet`, T3 `Active`, A4 controls, A2 service.
- Produces: `pub fn render(view: &mut SettingsView, cx: &mut Context<SettingsView>) -> Div`, and in the model `pub fn pair_summary(light: &str, dark: &str, lang: Lang) -> String` ("Light: X · Dark: Y"; one name when both are equal).

Layout (inventory §1 and §A): card 1 has Appearance (three 76×50 thumbnails with a 10 pt label; selected = accent fill at 12% and a 2 px accent border, radius 8) and Accent Color (picker ShellX Blue / System / Custom, with a `ColorWell` when Custom). Card 2 has the Terminal Theme row (subtitle = `pair_summary`; a "Revert" button while a pick made since the section opened can be undone) and the gallery: a "Search all themes" field (max width 200), the headings "Dark Themes" and "Light Themes" with the side in use first, and a grid of cards in adaptive columns 128–220 wide with spacing 10. A card: 54 high on the theme background, the name in the theme foreground (10, monospaced, medium), a 5×11 block in the cursor colour, two rows of eight 8-high ANSI swatches. The card of the side's current theme has the selected border of the thumbnails. A click sets that side of the pair. No match: "No themes match your search." Only visible cards are built (GPUI `uniform_list` or equivalent); user themes are read from `native_dir()/themes` when the section opens.

- [ ] **Step 1: Write the failing test** in `theme_file.rs`: `the_pair_summary_names_one_theme_when_both_sides_match`. Run, see it fail, commit `[red]`.
- [ ] **Step 2:** Implement the section and set the four `wired` flags.
- [ ] **Step 3:** Run `cargo test -p shellx-model` and `cargo test --release -p shellx-app`; green.
- [ ] **Step 4: Screenshots** with `SHELLX_DEV_PREVIEW=settings:themes` in Dark and Light, `vi` and `en`; compare with inventory §A.
- [ ] **Step 5:** Commit `feat(windows): Settings › Themes with Appearance, Accent Color and the theme gallery`.

## Track R: Terminal (`feat/windows-settings-terminal`)

### Task R1: Terminal look

**Files:**
- Modify: `windows/shellx-app/src/ui/term_view.rs:112-114,204-206,1206-1209,1703-1727` (`FONT_SIZE`, `PADDING`, `terminal_font`, the cursor), `term_core.rs:14,70` (`SCROLLBACK_BYTES`), `ui/tab_bar.rs` (title size), `windows/shellx-model/src/settings.rs` (helpers below), `settings_catalog.rs` (flags)

**Interfaces:**
- Consumes: A2 `current(cx)`.
- Produces (model): `pub fn scrollback_bytes(mb: u32) -> usize;` and `pub fn cursor_shape(setting: CursorStyle, program: Option<CursorStyle>) -> CursorStyle` (a shape the program asked for wins). App: `pub fn monospace_families(cx: &App) -> Vec<SharedString>` in `fonts.rs`.

Font, Font Size, Cursor Style and the paddings apply to every open terminal at once (cell metrics are recomputed and the PTY is resized). Scrollback Limit applies to terminals opened afterwards; its row subtitle says so. The Font picker lists "Default" and the installed families whose `i` and `M` have the same advance; a stored family that is not installed draws with the default and the picker shows it as selected with "(not installed)". Bar is a 2 px vertical bar, Underline a 2 px line under the cell, Hollow an outline; an unfocused pane keeps today's hollow block.

- [ ] **Step 1: Write the failing tests** (model): `scrollback_megabytes_convert_with_the_macs_factor`, `a_program_cursor_shape_wins`. Commit `[red]`.
- [ ] **Step 2:** Implement and wire; set `wired: true` for Tab Bar Font Size, Font, Font Size, Cursor Style, Horizontal Padding, Vertical Padding, Scrollback Limit.
- [ ] **Step 3:** Run both test suites; green.
- [ ] **Step 4: Screenshots:** defaults (13 pt, padding 2), then font size 20 with Bar, with Underline, with padding 24; confirm the grid has no gap and the cursor sits on its cell.
- [ ] **Step 5:** Commit `feat(windows): Settings › Terminal changes the font, cursor, padding, scrollback and tab title size`.

### Task R2: Terminal behaviour

**Files:**
- Modify: `windows/shellx-model/src/mouse.rs`, `paste.rs`, `selection.rs`; `windows/shellx-app/src/ui/term_view.rs` (wheel, mouse-up, paste, middle click); `settings_catalog.rs` (flags)

**Interfaces:**
- Produces (model):

```rust
// mouse.rs
pub fn scaled_scroll(lines: f64, speed: f32) -> f64;
// the existing `secondary_click` gains one last parameter, `middle_pastes: bool`; its other parameters and `PaneClick` stay
// paste.rs
pub fn asks_first(text: &str, confirm_unsafe: bool) -> bool;     // more than one line and the setting is on
// selection.rs
pub fn copies_on_release(copy_on_select: bool, selection_visible: bool) -> bool;
```

- [ ] **Step 1: Write the failing tests:** `scroll_speed_scales_before_accumulating` (0.25× of 4 lines accumulates to 1), `middle_click_pastes_only_when_on_and_the_pane_has_focus` (first click on an unfocused pane still only focuses), `a_multi_line_paste_asks_only_while_the_setting_is_on`, `a_single_line_never_asks`, `releasing_a_selection_copies_only_when_on`. Commit `[red]`.
- [ ] **Step 2:** Implement; wire in `term_view.rs`; set `wired: true` for Scroll Speed, Copy on Selection, Confirm Unsafe Pastes, Middle-Click Paste.
- [ ] **Step 3:** Run `cargo test -p shellx-model mouse:: paste:: selection::` and the app suite; green.
- [ ] **Step 4:** Commit `feat(windows): Settings › Terminal sets scroll speed, copy on selection, paste confirmation and middle-click paste`.

## Track S: Sidebar and App (`feat/windows-settings-sidebar-app`)

### Task S1: Sidebar rows

**Files:**
- Modify: `windows/shellx-app/src/ui/sidebar.rs:471-560` (the card), `ui/theme.rs` (sidebar sizes), `cwd.rs:68` (`display_path`), `windows/shellx-model/src/sidebar.rs`, `settings_catalog.rs`

**Interfaces:**
- Produces (model):

```rust
pub struct SidebarSizes { pub brand: f32, pub card_title: f32, pub header: f32, pub small: f32, pub pill: f32 }
pub fn sidebar_sizes(font_size: f32) -> SidebarSizes;            // card_title = font_size; the others scale by font_size / 12.5 from today's 14, 10.5, 11, 10
pub struct CardLines { pub title_wraps: bool, pub branch: Option<String>, pub directory: Option<String> }
pub fn card_lines(settings: &Settings, branch: Option<&str>, directory: Option<&str>) -> CardLines;
pub fn shorten_path(path: &str, max_chars: usize, from_start: bool) -> String;   // "…\src\ui" or "~\proj\sh…"
```

Sidebar Background and Sidebar Color already work through T2/T3 when Track T is merged; this task wires the rows to the keys and, until T3 lands, the sidebar reads `chrome(…).sidebar_bg` through a local helper. Hide All Sidebar Details leaves only titles and disables Wrap, Truncate and Show Branch + Directory.

- [ ] **Step 1: Write the failing tests:** `the_default_size_is_12_5_and_others_scale` (`sidebar_sizes(12.5).brand == 14.0`; `sidebar_sizes(25.0).brand == 28.0`), `hide_all_details_drops_branch_and_directory`, `show_branch_directory_off_drops_both`, `a_long_path_is_cut_at_the_chosen_end` (40 characters cut to 20 from the start keeps the last segment; from the end keeps the first), `a_short_path_is_unchanged`. Commit `[red]`.
- [ ] **Step 2:** Implement; wire; set `wired: true` for the seven Sidebar rows.
- [ ] **Step 3:** Run both suites; green. Screenshot `settings:sidebar` and the main window with font size 18, wrapped titles, and Custom Color `#203040`.
- [ ] **Step 4:** Commit `feat(windows): Settings › Sidebar sets the background, font size and card details`.

### Task S2: App rows

**Files:**
- Modify: `windows/shellx-model/src/tabs.rs:139-196` (`new_tab`, `close_pane`), `history.rs`, `layout.rs:84-90,172`, `strings.rs` (`Lang::from_choice`); `windows/shellx-app/src/ui/root.rs` (`new_tab`, `note_focus`, `split`, `close_pane`), `ui/tab_bar.rs:157-183` (`close_box`), `ui/app.rs` (`Services.lang`), `workspace.rs` (start directory), `settings_catalog.rs`

**Interfaces:**
- Produces (model):

```rust
// tabs.rs
pub fn new_tab_at(&mut self, target: PaneTarget, placement: Placement) -> (TabId, PaneId);   // Top: index 0; AfterCurrent: active + 1; End: last
pub fn close_pane_with(&mut self, pane: PaneId, keep_workspace_open: bool) -> CloseOutcome;  // true: the workspace's last terminal is replaced, not the workspace closed
// history.rs
pub fn records(includes_panes: bool, same_workspace: bool) -> bool;   // a move inside one workspace is recorded only when includes_panes
// layout.rs
pub fn split_with(&mut self, target: SlotId, axis: Axis, new_slot: SlotId, equalize: bool) -> bool;  // true: every region of the split's run along `axis` gets the same size
// strings.rs
impl Lang { pub fn from_choice(choice: LanguageChoice, env: Option<&str>, ui_lang_id: Option<u16>) -> Lang; }  // env wins, then the choice, then Windows
```

Language applies at once: the service sets `Services.lang` and refreshes every window. While `SHELLX_LANG` is set the row is disabled and its subtitle says the variable decides. Inherit Workspace Working Directory starts a new local workspace in the focused terminal's last reported directory (OSC 7); with none known, or the folder gone, it starts where it starts today. Hide Tab Close Button removes the close box from tabs. The last terminal of the last workspace is always replaced by a fresh one, as today.

- [ ] **Step 1: Write the failing tests:** `a_new_workspace_lands_at_top_after_current_or_end`, `closing_the_last_terminal_keeps_the_workspace_when_asked`, `the_last_workspace_is_always_refilled`, `focus_history_skips_moves_inside_a_workspace_by_default`, `equalize_gives_three_regions_a_third_each` (split right twice with `equalize`: widths within one pixel), `without_equalize_the_new_region_halves_its_parent`, `the_language_choice_loses_to_the_environment_and_beats_windows`. Commit `[red]`.
- [ ] **Step 2:** Implement; wire; set `wired: true` for the seven App rows.
- [ ] **Step 3:** Run both suites; green. Screenshot `settings:app` in both languages.
- [ ] **Step 4:** Commit `feat(windows): Settings › App sets the language, workspace placement, start directory, focus history, splits and the tab close button`.

## Track C: Workspace Colors (`feat/windows-settings-colors`)

### Task C1: The palette and the card style

**Files:**
- Create: `windows/shellx-model/src/workspace_colors.rs`
- Modify: `windows/shellx-model/src/tabs.rs:56` (`Tab` gains `pub color: Option<String>`), `lib.rs`

**Interfaces:**
- Produces:

```rust
pub const BUILT_IN: [(&str, u32); 16];     // Red 0xC0392B, Crimson 0x922B21, Orange 0xA04000, Amber 0x7D6608, Olive 0x4A5C18, Green 0x196F3D,
                                           // Teal 0x006B6B, Aqua 0x0E6B8C, Blue 0x1565C0, Navy 0x1A5276, Indigo 0x283593, Purple 0x6A1B9A,
                                           // Magenta 0xAD1457, Rose 0x880E4F, Brown 0x7B3F00, Charcoal 0x3E4B5E
pub const DEFAULT_NAME: &str = "Purple";
pub struct Entry { pub name: &'static str, pub base: Rgba, pub color: Rgba }
pub fn palette(settings: &Settings) -> Vec<Entry>;                       // built-ins with the stored overrides applied
pub fn workspace_color(settings: &Settings, name: Option<&str>) -> Rgba; // None or an unknown name: the current Purple
pub struct CardStyle { pub rail: Option<Rgba>, pub fill: Option<Rgba>, pub border: Option<Rgba> }
pub fn card_style(settings: &Settings, chrome: &Chrome, color: Rgba, selected: bool) -> CardStyle;
// tabs.rs
impl Tabs { pub fn set_color(&mut self, tab: TabId, name: Option<String>) -> bool; }
```

`card_style` reproduces the Mac's drawing for Left Rail and Solid Fill, selected and unselected, with Subtle Selection Highlight on and off, Brighten Colors in Dark Mode, Unselected Fill Opacity and a custom Selection Highlight (which always draws solid). Take the rules and numbers from `Sources/SidebarTabItemSettingsSnapshot.swift`, `Sources/VerticalTabsSidebar+WorkspaceGroups.swift` and `Sources/WorkspaceTabColorSettings.swift`, and write the Mac file and line beside each number in a comment. Without `chrome.rs` (Track T not merged), `card_style` takes the accent and the dark flag as plain arguments instead of `&Chrome`.

- [ ] **Step 1: Write the failing tests:** `the_built_in_palette_is_the_macs_sixteen`, `an_override_changes_one_entry_and_keeps_its_base`, `a_new_workspace_is_purple_and_follows_an_edited_purple`, `left_rail_draws_a_rail_and_no_fill_when_unselected`, `subtle_selection_is_an_accent_tint_with_a_border`, `subtle_off_is_a_solid_accent_fill`, `solid_fill_uses_the_unselected_opacity`, `a_custom_selection_colour_is_always_solid`, `brighten_applies_only_on_dark_chrome_with_solid_fill`. Each asserts the exact colours the Mac rule gives for Purple with accent `#60a5fa`. Commit `[red]`.
- [ ] **Step 2:** Implement.
- [ ] **Step 3:** Run `cargo test -p shellx-model workspace_colors:: tabs::`; green.
- [ ] **Step 4:** Commit `feat(windows): the workspace colour palette and the Mac's card styles`.

### Task C2: The card, its colour menu, and the section

**Files:**
- Create: `windows/shellx-app/src/ui/settings/sections/workspace_colors.rs`
- Modify: `windows/shellx-app/src/ui/sidebar.rs:471-560` (draw with `card_style`; right-click), `ui/root.rs` (`card_menu: Option<(TabId, Point<Pixels>)>`, counted by `dropdown_open` and closed by `close_menus`), `ui/menu.rs` (an item may carry a colour swatch; a menu may open at a point), `settings_catalog.rs`

**Interfaces:**
- Consumes: C1; A4 `ColorWell`.
- Produces: `RootView::open_card_menu(&mut self, tab: TabId, at: Point<Pixels>, cx)`, `RootView::set_workspace_color(&mut self, tab: TabId, name: Option<String>, cx)`; `sections::workspace_colors::render(view, cx) -> Div`.

A right-click on a workspace card opens a menu at the pointer: a disabled heading "Workspace Color", "Clear Color" (only when the workspace has a colour of its own), then the 16 palette entries, each with its swatch and a check mark on the current one. It follows the dropdown rules of the "+ ▾" menu (closes on a click outside, on Esc, when a panel opens). The section draws the catalogue rows of §5.4, then the note and the 16 palette rows (`ColorWell`, hex label, subtitle "Base: #HEX"), then Reset Palette.

- [ ] **Step 1: Write the failing test** (`shellx-app`): `the_card_menu_is_a_dropdown` (`dropdown_open` is true while `card_menu` is set; `close_menus` clears it). Commit `[red]`.
- [ ] **Step 2:** Implement; set `wired: true` for the Workspace Colors rows.
- [ ] **Step 3:** Run both suites; green.
- [ ] **Step 4: Screenshots:** `settings:workspaceColors`; the main window with three workspaces coloured Red, Green and default, in Left Rail and in Solid Fill, selected and unselected; the open card menu (a throwaway start-up edit, not committed, may open it).
- [ ] **Step 5:** Commit `feat(windows): workspace colours on the cards, a colour menu, and Settings › Workspace Colors`.

## Track K: Keyboard Shortcuts (`feat/windows-settings-shortcuts`)

### Task K1: The keymap

**Files:**
- Create: `windows/shellx-model/src/keymap.rs`
- Modify: `windows/shellx-model/src/keys.rs:27-143` (`AppCommand` gains `FocusBack`, `FocusForward`; `map_key` takes a `&Keymap`; `app_binding` is removed), `modal.rs:178` (`stopped_pane_key` passes the keymap on), `lib.rs`

**Interfaces:**
- Produces:

```rust
pub struct Chord { pub ctrl: bool, pub alt: bool, pub shift: bool, pub key: String }
impl Chord {
    pub fn parse(text: &str) -> Option<Chord>;            // "ctrl+shift+n"; lower case; modifiers in ctrl, alt, shift order
    pub fn text(&self) -> String;
    pub fn label(&self) -> String;                        // "Ctrl+Shift+N", "Alt+←", "Ctrl+,"
    pub fn of(k: &KeyIn) -> Chord;                        // normalised: GPUI-Windows "+" with alt -> alt+shift+"=", "_" with alt -> alt+shift+"-"; letters lower case
}
pub enum Action { OpenSettings, ToggleSidebar, NewWorkspace, NewTerminal, CloseTab, NextWorkspace, PrevWorkspace,
                  SplitRight, SplitDown, FocusLeft, FocusRight, FocusUp, FocusDown, FocusBack, FocusForward, Copy, Paste }
impl Action {
    pub const ALL: &'static [Action];                     // the order above, which is the list order
    pub fn id(self) -> &'static str;                      // openSettings, toggleSidebar, newTab, newSurface, closeTab, nextSidebarTab, prevSidebarTab,
                                                          // splitRight, splitDown, focusLeft, focusRight, focusUp, focusDown,
                                                          // focusHistoryBack, focusHistoryForward, copy, paste
    pub fn title(self) -> Str;                            // the Mac's titles: "Settings…", "Toggle Left Sidebar", "New Workspace", "New Surface", "Close Tab",
                                                          // "Next Workspace", "Previous Workspace", "Split Right", "Split Down", "Focus Pane Left" …, "Focus Back", "Focus Forward"; "Copy", "Paste"
    pub fn default_chord(self) -> Option<Chord>;          // README: ctrl+, ; ctrl+shift+b ; ctrl+shift+n ; ctrl+shift+t ; ctrl+shift+w ; ctrl+tab ; ctrl+shift+tab ;
                                                          // alt+shift+= ; alt+shift+- ; alt+left/right/up/down ; Back and Forward: none ; ctrl+shift+c ; ctrl+shift+v
    pub fn command(self) -> AppCommand;
}
pub enum Refused { NeedsModifier, SystemKey, WindowsKey, AltGr }
pub fn accept(chord: &Chord, win: bool) -> Result<(), Refused>;
pub fn takes_from_the_shell(chord: &Chord) -> bool;       // ctrl + a letter, no alt, no shift
pub struct Keymap { /* action -> Option<Chord> */ }
impl Keymap {
    pub fn from_bindings(bindings: &BTreeMap<String, Option<String>>) -> Keymap;   // unknown ids and unparsable chords are ignored
    pub fn chord(&self, action: Action) -> Option<&Chord>;
    pub fn is_default(&self, action: Action) -> bool;
    pub fn holder(&self, chord: &Chord) -> Option<Action>;                         // who has this chord now
    pub fn command(&self, k: &KeyIn, ctx: &KeyCtx) -> Option<AppCommand>;
    /// The `shortcuts.bindings` entry to store: `None` removes the entry (back to default).
    pub fn entry(action: Action, chord: Option<&Chord>) -> Option<Option<String>>;
}
pub fn refusal(lang: Lang, refused: Refused) -> &'static str;
pub fn conflict(lang: Lang, holder: Action) -> String;
```

Acceptance (spec §5.4): a chord needs Ctrl or Alt, or is F1–F12 alone. Refused: a plain key (`NeedsModifier`); `alt+f4` and `alt+space` (`SystemKey`); any chord with the Windows key (`WindowsKey`); Ctrl together with Alt (`AltGr`). Fixed aliases stay in `Keymap::command` after the user bindings: `ctrl+c` copies while a selection exists, `shift+insert` pastes, `ctrl+pagedown` / `ctrl+pageup` are next and previous workspace; a user binding on the same chord wins. Composing, and a held Windows key, still ignore everything, and `Ctrl+Alt` is still text.

- [ ] **Step 1: Write the failing tests:** keep every existing `keys.rs` test passing against `Keymap::from_bindings(&BTreeMap::new())`, and add: `the_default_keymap_is_the_readme_table`, `chords_parse_and_print_round_trip`, `gpui_windows_shapes_match_their_chords` (`alt` + `"+"` equals `alt+shift+=`; `alt` + `"_"` equals `alt+shift+-`), `a_rebound_action_leaves_its_old_chord_to_the_shell` (rebind New Workspace to `ctrl+shift+k`: `ctrl+shift+n` now maps to a terminal chord), `an_unbound_action_has_no_chord` (Settings… unbound: `ctrl+,` runs no command), `a_user_binding_takes_an_alias` (binding Split Right to `shift+insert` is refused as `NeedsModifier`; binding it to `ctrl+pagedown` works and Next Workspace's alias no longer fires), `altgr_and_system_keys_are_refused`, `function_keys_need_no_modifier`, `the_holder_of_a_chord_is_found`, `an_entry_equal_to_the_default_is_removed`, `ctrl_letter_is_flagged_as_taken_from_the_shell`.
- [ ] **Step 2:** Run `cargo test -p shellx-model keymap:: keys:: modal::`; fails. Commit `[red]`.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the same command; pass.
- [ ] **Step 5:** Commit `feat(windows): a keymap that can be rebound, with the README's defaults`.

### Task K2: The app reads the keymap

**Files:**
- Modify: `windows/shellx-app/src/ui/root.rs:479-528,944-962` (`run_command`, `key_action`), `ui/term_view.rs` (its `map_key` call), `ui/titlebar.rs`, `ui/tab_bar.rs:186-257`, `ui/sidebar.rs` (the help menu), `ui/tooltip.rs` callers, `ui/settings_service.rs` (holds the current `Keymap`)

**Interfaces:**
- Consumes: K1.
- Produces: `SettingsService::keymap(&self) -> &Keymap`; `pub fn shortcut_label(action: Action, cx: &App) -> Option<String>` in `ui/settings_service.rs`.

`AppCommand::FocusBack` and `FocusForward` call the existing `focus_back` / `focus_forward`. Every tooltip and menu line that shows a shortcut reads `shortcut_label`; an unbound action shows no shortcut. The gear button and the help menu's "Settings…" open Settings without going through the keymap.

- [ ] **Step 1: Write the failing test** (`shellx-app`): `a_shortcut_label_shows_the_current_binding_or_none` (default: New Workspace → `Ctrl+Shift+N`; rebound to `ctrl+shift+k` → `Ctrl+Shift+K`; unbound → `None`). Commit `[red]`.
- [ ] **Step 2:** Implement. Check by reading the code that the gear's click and the help menu's "Settings…" call `RootView::open_settings` and never `run_command`; say so in the commit message.
- [ ] **Step 3:** Run both suites; green.
- [ ] **Step 4:** Commit `feat(windows): every key and shortcut label goes through the keymap; Back and Forward are commands`.

### Task K3: The recorder and the section

**Files:**
- Create: `windows/shellx-app/src/ui/controls/recorder.rs`, `ui/settings/sections/shortcuts.rs`
- Modify: `windows/shellx-model/src/keymap.rs` (the filter below), `settings_catalog.rs`

**Interfaces:**
- Consumes: K1, K2.
- Produces:

```rust
// keymap.rs
pub enum ListFilter<'a> { Text(&'a str), Chord(&'a Chord) }
pub fn listed(keymap: &Keymap, filter: Option<ListFilter>, lang: Lang) -> Vec<Action>;
// recorder.rs
pub struct Recorder;   // entity: a 160-wide button showing the chord label or "—"; click or Enter starts listening
pub enum RecorderEvent { Recorded(Chord), Cleared, Restored }
pub fn stops_key(listening: bool) -> bool;   // an idle recorder stops no key; a listening one stops every key-down
```

The section (inventory §3 and §B): a search bar with "Search shortcuts", a "Detect Shortcut" button that turns into "Listening…" and filters the list by the next chord pressed, and a clear button; one row per `Action::ALL` with the title, the recorder and an X button (X unbinds; after a clear it becomes a restore arrow that puts the default back); "Reset Default Shortcuts" with a "Reset Defaults" button that removes `shortcuts.bindings`; the footer note "Click a shortcut value to record. Use X to unbind; it changes to restore after a clear." While a recorder listens, Esc stops listening and no app command runs. A refused chord shows `refusal` under the row. A chord another action holds is not saved: a red banner shows `conflict` with an "Undo" button that closes it and leaves both bindings as they were. A row whose chord `takes_from_the_shell` shows a caption saying the key will no longer reach the shell.

- [ ] **Step 1: Write the failing tests:** `an_idle_recorder_stops_no_key`, `the_list_filters_by_text_in_either_language` (`"tach"` finds Split Right in Vietnamese, folded), `the_list_filters_by_chord`. Commit `[red]`.
- [ ] **Step 2:** Implement; set `wired: true` for the shortcut list and Reset Default Shortcuts.
- [ ] **Step 3:** Run both suites; green. Screenshot `settings:keyboardShortcuts` in both languages, and with a conflict banner (a throwaway start-up edit may raise it).
- [ ] **Step 4:** Commit `feat(windows): Settings › Keyboard Shortcuts records, clears, restores and refuses conflicts`.

---

# Stage C: finish (in order, on `feat/windows-settings`, after the tracks that are done have merged)

### Task F1: Search in the Settings sidebar

**Files:**
- Modify: `windows/shellx-app/src/ui/settings/mod.rs`, `ui/settings/rows.rs`

**Interfaces:**
- Consumes: A3 `search`, A5 `show_row`.

An empty field shows the groups. Text shows a flat ranked list: a section hit shows the section title; a row hit shows the row title with the section title as a caption; no hit shows "No Results". A click selects the section, scrolls the row to the vertical centre (a section hit scrolls to the top) and draws the row with an accent fill at 24% and a 2.5 px accent border for 2 seconds, then fades it out. The search field is the existing `TextField`, so Vietnamese input methods work as in the sign-in dialog.

- [ ] **Step 1: Write the failing test:** `a_hit_list_item_names_its_section` (pure helper `hit_label(hit, lang) -> (String, Option<String>)`). Commit `[red]`.
- [ ] **Step 2:** Implement.
- [ ] **Step 3:** Run the app suite; green. Screenshot the hit list for `font` and for `phim tat`.
- [ ] **Step 4:** Commit `feat(windows): search in Settings finds sections and rows and highlights the row`.

### Task F2: Reset, and no dead row

**Files:**
- Create: `windows/shellx-app/src/ui/settings/sections/reset.rs`
- Modify: `windows/shellx-model/src/settings_catalog.rs`, `windows/shellx-app/src/ui/settings_service.rs`

"Reset All Settings" is one centred button with no confirmation (spec §5.4). It calls `SettingsService::reset_all` and sets the shell choice back to Automatic. It does not sign out and does not touch `links.json`, `render.json` or `ui-state.json`.

- [ ] **Step 1: Write the failing tests:** `reset_all_leaves_only_unknown_keys_in_the_file` (store test: after reset the file holds the unknown key and nothing else), `every_catalogued_row_is_wired` (model; if a track did not merge, its rows are removed from the catalogue in this task and listed in the PR description as moved to the next day).
- [ ] **Step 2:** Run; the first fails. Commit `[red]`.
- [ ] **Step 3:** Implement; set `wired: true` for Reset.
- [ ] **Step 4:** Run both suites; green.
- [ ] **Step 5:** Commit `feat(windows): Reset All Settings`.

### Task F3: Documents, screenshots and the Windows compile check

**Files:**
- Modify: `windows/README.md` (sections "Keyboard shortcuts", "Settings", "State directories", "Run the window on a Mac"), `windows/WINDOWS-TEST-CHECKLIST.md` (a new "Settings" part)

- [ ] **Step 1:** Rewrite the README's Settings section for the new window, the sections that exist, `SHELLX_SETTINGS_HOST=panel`, `settings:<section>` previews, `ui-state.json`, the `themes` folder, and say that shortcuts can be changed in Settings. List under "Known limitations" that a second running ShellX picks up changed settings at its next start.
- [ ] **Step 2:** Add the checklist part with these 12 steps, each with what to expect: open Settings with `Ctrl+,` and with the gear; type `phím` in the search field with Unikey or the Windows Vietnamese keyboard; switch Appearance to Light and back; pick another dark theme and see the open terminal change; change Font Size and Cursor Style; rebind New Workspace and use the new key; record a chord another action holds and see the red banner; right-click a workspace card and pick a colour; set Sidebar Background to Custom Color; press Reset All Settings; close and reopen ShellX and see a changed setting kept; set `SHELLX_SETTINGS_HOST=panel` and repeat the first two steps if anything above failed in the window.
- [ ] **Step 3:** Take the final screenshots: every section in `vi` and `en`; the main window with defaults beside the Stage A "before" shot; the main window in Light. Check the default shot against the spec's table of changes and add any difference that is not in the table to the spec (and tell the user).
- [ ] **Step 4:** Run `cargo test -p shellx-model`, `cargo test -p shellx-remote`, `cargo test --release -p shellx-app`, `scripts/shellx/check-windows-build.sh --release` and `python3 scripts/verify-local.py`; record each result.
- [ ] **Step 5:** Commit `docs(windows): README and the hands-on checklist cover Settings`.

### Task F4: Review, and the test installer

- [ ] **Step 1:** Run a review subagent over `develop..feat/windows-settings`, correctness first (`skills/cmux-review/SKILL.md`); fix what it confirms, each with its red test first.
- [ ] **Step 2:** Report to the user: what merged, what moved to the next day, the test results of F3 Step 4, the screenshots, and the open risk that nothing ran on Windows.
- [ ] **Step 3 (after the user's go-ahead):** merge `feat/windows-settings` into `develop`, then build a labelled test installer the way the README's "Building a test installer" section says and leave it on the Desktop of this Mac. Do not publish it.

---

## Self-review notes

- Spec §5.3 → A5. §5.4 Themes → T4; Terminal → R1, R2; Keyboard Shortcuts → K1–K3; Workspace Colors → C1, C2; Sidebar → S1; App → S2; Reset → F2; table of changes → T3 Step 5 and F3 Step 3. §5.5 → T1–T3. §5.6 → A1, A2. §5.7 → A3, F1. §5.8 → F3. §5.9 → the stage order and the Global Constraints.
- Not in this plan by the spec's choice: parts 1b to 8, file watching between processes, `shellx.json`.

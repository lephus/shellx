# ShellX for Windows: Mac parity, wave 1, Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** the Windows app (`windows/`) types correctly, never asks for a password at launch, and has the Mac's header, per-region tab bars, workspace cards, sidebar footer and OS-following language.

**Architecture:**
- Logic lives in GPUI-free code with unit tests that run on the Mac:
  - `windows/shellx-model`;
  - the non-UI modules of `windows/shellx-app`.
- The GPUI views in `windows/shellx-app/src/ui/` are restyled to match the Mac.
- Task 1 makes the GPUI window build and run on macOS (release builds only), so every UI task can be checked with a screenshot.
- Windows-only behaviour gets a final check on a cross-built installer:
  - WM_CHAR typing;
  - ConPTY;
  - Vietnamese input methods;
  - the caption buttons.

**Tech Stack:** Rust 1.91, edition 2024, GPUI `=0.2.2`, libghostty-vt (`cmux-tui/crates/ghostty-vt`), ConPTY (`cmux-pty`), coolicons v4.1 SVGs.

**Spec:** `docs/superpowers/specs/2026-11-01-windows-mac-parity-design.md`. Visual reference: `.superpowers/brainstorm/16640-1793467424/content/mac-vs-win.html`, which holds the Mac window and the user's Windows screenshot.

## Global Constraints

- Branch `feat/windows-mac-parity` (from `develop` 366fccea57). Work in a worktree.
  - A worktree needs the ghostty submodule: run `git submodule update --init ghostty`, or symlink `<worktree>/ghostty` to the main checkout's `ghostty` (same pinned SHA `cb1ef7091c`).
- Run all cargo commands from `windows/`.
- Model tests: `cargo test -p shellx-model`.
- App tests (non-UI modules, on the Mac): `cargo test -p shellx-app`.
- Never build `shellx-app` in debug for running the window on macOS. The debug build trips a hashbrown debug assertion at startup (spec §8). Use `--release`.
- GPUI stays pinned `=0.2.2`. No new crates. New `windows-sys` features are allowed.
- Colours come from `windows/shellx-model/src/palette.rs`. New tokens added in Task 6:
  - `SELECTION_TITLE = 0xf1f5ff`;
  - `INDICATOR_UNFOCUSED = 0x5b5478`;
  - `RAIL_PURPLE = 0x6a1b9a`.
- Each new user-facing string gets a `Str` variant with both `Vi` and `En` values, is added to `Str::ALL`, and the hard-coded count in `all_has_no_duplicates` (`strings.rs:435`) is updated. Wording is copied from the Mac:

  | Str variant (new unless noted) | vi | en |
  |---|---|---|
  | `MachinesHeader` (changed) | Máy của bạn | YOUR MACHINES |
  | `ThisMachine` (changed) | máy này | this PC |
  | `SearchPlaceholder` (changed) | Tìm phiên, máy, lệnh… | Search sessions, machines, commands… |
  | `SignInTitle` | Đăng nhập ShellX | Sign in to ShellX |
  | `EmailAddress` | Địa chỉ email | Email |
  | `SignInEllipsis` | Đăng nhập… | Sign In… |
  | `SignInSubtitle` | Đăng nhập bằng tài khoản ShellX của bạn. | Sign in with your ShellX account. |
  | `Cancel` (existing, check value) | Hủy | Cancel |
  | `NewWorkspace` (replaces `NewTab`) | Phiên mới | New Workspace |
  | `NewWorkspaceOptions` | Tùy chọn phiên mới | New workspace options |
  | `NewTerminalTab` | Tab mới (terminal) | New Tab (Terminal) |
  | `NewTerminal` | Terminal mới | New Terminal |
  | `CloseTab` | Đóng tab | Close Tab |
  | `FocusBack` | Tiêu điểm trước | Focus Back |
  | `FocusForward` | Tiêu điểm sau | Focus Forward |
  | `ShowHideSidebar` | Hiện hoặc ẩn thanh bên | Show or hide the sidebar |
  | `ShowNotifications` | Hiện thông báo | Show notifications |
  | `Help` | Trợ giúp | Help |
  | `SettingsEllipsis` | Cài đặt… | Settings… |
  | `CheckForUpdates` | Kiểm tra cập nhật | Check for Updates |
  | `Docs` | Tài liệu | Docs |
  | `GitHub` | GitHub | GitHub |
  | `LanguageHint` (changed) | Theo ngôn ngữ hiển thị của Windows | Follows the Windows display language |

  `update_available_pill(lang, version)` gives "Có bản cập nhật: {v}" or "Update Available: {v}".
- Shortcuts:
  - Ctrl+Shift+N: new workspace;
  - Ctrl+Shift+T: new terminal tab;
  - Ctrl+Shift+W: close terminal;
  - Ctrl+Shift+B: sidebar;
  - Ctrl+,: settings.
  - Plain Ctrl+letter always reaches the shell.
- No dead controls. Do not add the Mac's right-sidebar toggle, its "New Browser" button or its Share button. The bell and the search field stay display-only, as today.
- Commits: `feat(shellx-windows): …`, `fix(shellx-windows): …`, `test(shellx-windows): …`. One commit per task, except where a task says red, then green.

## Review Focus

1. **IME composition while a dialog is open.** Unikey/EVKey/Windows Telex text in the sign-in fields must arrive. → Task 2 test `composing_and_text_keys_pass_while_a_panel_is_open`.
2. **Back after the target closed.** Back/Forward after the focused terminal of a previous step was closed must skip dead panes, never focus nothing. → Task 7 test `back_skips_closed_panes`.
3. **New terminal on a remote pane.** A "new terminal" on a pane that shows a Mac terminal must open another terminal on that Mac, not a local PowerShell. → Task 5 test `new_surface_uses_the_given_target`, and Task 6 routes through `split_target`.
4. **Folder names with non-ASCII or spaces.** Vietnamese names ("Tài liệu") and spaces in the working directory must display correctly. → Task 8 test `osc7_with_unicode_and_percent_escapes`.
5. **A PowerShell profile without a `prompt` function** (or one that replaces it) must still get a working prompt. → Task 8 hook fallback, checked by the user (Task 11 checklist item 6).

---

### Task 1: Run the Windows window on macOS for development

**Files:**
- Modify: `windows/shellx-app/Cargo.toml` (add a macOS gpui dependency).
- Modify: `windows/shellx-app/src/main.rs:29,70-77` (cfg gates).
- Modify: `windows/shellx-app/src/paths.rs` (`ensure`).
- Modify: `windows/shellx-app/src/ui/titlebar.rs` (caption buttons Windows-only, macOS inset).
- Create: `windows/dev/mac-shot.sh`.
- Modify: `windows/README.md` (new section).

**Interfaces:**
- Produces: `windows/dev/mac-shot.sh <out.png> [wait_seconds=6]`. Later tasks use it to screenshot the window.

- [ ] **Step 1: Write the failing test** in `paths.rs` tests: `#[cfg(unix)] fn created_dirs_are_private()`. It calls `ensure(tmp.join("a/b"))` and asserts that the mode of `a/b` `& 0o077 == 0`.
- [ ] **Step 2: Run it.** `cargo test -p shellx-app created_dirs_are_private`. Expected: FAIL. Today `ensure` uses the default 0755, which shellx-core then rejects with "group/other permissions set (need 0700)".
- [ ] **Step 3: Implement.**
  - **paths.rs:** on unix, `ensure` creates directories with `std::os::unix::fs::DirBuilderExt::mode(0o700)` and is recursive. Windows is unchanged.
  - **Cargo.toml:** add `[target.'cfg(target_os = "macos")'.dependencies] gpui = { version = "=0.2.2", default-features = false, features = ["font-kit", "runtime_shaders"] }`.
  - **main.rs:** `#[cfg(windows)]` becomes `#[cfg(any(windows, target_os = "macos"))]` for `mod ui` and the `ui::run()` call. The fallback message's cfg becomes the negation.
  - **titlebar.rs:** draw the caption buttons only when `cfg!(windows)`. When `cfg!(target_os = "macos")`, put a `MAC_TRAFFIC_LIGHTS_W: f32 = 72.0` spacer first in the bar.
  - **mac-shot.sh:**
    1. Run `windows/target/release/shellx-desktop` in the background, passing the caller's environment (e.g. `SHELLX_LANG`).
    2. Wait `wait_seconds`.
    3. Find the window number with `swift -e` over `CGWindowListCopyWindowInfo`, matching owner name `shellx-desktop`.
    4. Run `screencapture -x -o -l<id> <out.png>`.
    5. Kill the process.
    6. Exit non-zero with a message if no window appeared.
  - **README:** add the section "Run the window on a Mac (development only)": `cargo build --release -p shellx-app`, then `dev/mac-shot.sh`, plus the debug-build warning and the ghostty submodule note.
- [ ] **Step 4: Verify.**
  - `cargo test -p shellx-app created_dirs_are_private` → PASS.
  - `cargo build --release -p shellx-app` → `Finished`.
  - `dev/mac-shot.sh /tmp/t1.png` → a PNG of the ShellX window. It shows the sidebar and a `sh`/`bash` prompt, and no "Lỗi · … need 0700" line.
  - `cargo test -p shellx-model` → PASS.
- [ ] **Step 5: Commit.** `feat(shellx-windows): run the window on macOS for development`

### Task 2: Keys reach text fields and the terminal (the "không type được" bug)

Root cause (verified in GPUI 0.2.2 source):
- `RootView::on_key_down` (`ui/root.rs:556-562`) calls `stop_propagation()` on every key while a panel is open.
- On Windows, GPUI's `handle_keydown_msg` (`gpui-0.2.2/src/platform/windows/events.rs:398-407`) skips `TranslateMessage` for a handled key-down.
- The message loop (`platform.rs:314`) only calls `DispatchMessageW`, so no WM_CHAR is produced and plain letters never reach any field.
- The "+" machine picker (`ui/sidebar.rs:205`, `track_focus(picker_focus)`) is also a panel. It keeps the keyboard until Esc, and `focus_pane` gives the keyboard back to it when the terminal is clicked.

**Files:**
- Modify: `windows/shellx-model/src/modal.rs` (new `RootKey`, `Panels::root_key`; remove `picker`).
- Modify: `windows/shellx-app/src/ui/root.rs:541-573` (`on_key_down`), `:197-224` (`panels`, `focus_terminal`), `:228-238` (`close_top_panel`), plus the `picker_focus` field.
- Modify: `windows/shellx-app/src/ui/sidebar.rs:198-260` (`machine_picker`).

**Interfaces:**
- Produces, in `shellx_model::modal`:
  - `pub enum RootKey { Pass, Swallow, CloseTop, Run(AppCommand) }`;
  - `impl Panels { pub fn root_key(&self, action: &KeyAction, plain_escape: bool) -> RootKey }`.
- `Panel` loses `Picker`. `Panels` loses the `picker` field.

- [ ] **Step 1: Write the failing test** `composing_and_text_keys_pass_while_a_panel_is_open` in `modal.rs` tests. For each of `Panels { settings: true, .. }`, `{ login: true, .. }` and `{ pairing: true, .. }`, assert:
  - `root_key(&KeyAction::Text, false) == RootKey::Pass`;
  - `root_key(&KeyAction::Ignore, false) == RootKey::Pass`;
  - `root_key(&KeyAction::App(AppCommand::NewTab), false) == RootKey::Swallow` (Task 5 renames `NewTab` to `NewWorkspace` later);
  - `root_key(&KeyAction::Chord("ctrl+x".into()), false) == RootKey::Swallow`;
  - `root_key(&KeyAction::Chord("escape".into()), true) == RootKey::CloseTop`.

  Add `root_key` with today's behaviour so the test compiles and fails:
  - any panel open: `CloseTop` for plain Escape, `Swallow` for everything else;
  - none open: `Run` for App, `Pass` otherwise.
- [ ] **Step 2: Run it and commit red.** `cargo test -p shellx-model composing_and_text_keys_pass` → FAIL on the first `Pass` assertion. Record the output in the commit body. Commit: `test(shellx-windows): typed text must pass while a panel is open (red)`.
- [ ] **Step 3: Implement the rule.**
  - **Forced update on top:** Text/Ignore → `Pass`; everything else (Escape included) → `Swallow`.
  - **Any other panel open:**
    - plain Escape → `CloseTop`;
    - Text/Ignore → `Pass`;
    - App/Chord → `Swallow`.
  - **Nothing open:** App → `Run`; everything else → `Pass`.
  - **`root.rs` `on_key_down`:** build `KeyAction` with `map_key` (as today), then match `panels.root_key(..)`:
    - `Pass` → return without `stop_propagation`;
    - `Swallow` → `stop_propagation`;
    - `CloseTop` → `close_top_panel` + `stop_propagation`;
    - `Run(c)` → `stop_propagation` + `run_command(c)`.
- [ ] **Step 4: Make the picker non-modal.**
  - Delete `Panel::Picker`, `Panels::picker`, `RootView::picker_focus`, the `Picker` arms in `focus_terminal`/`close_top_panel`, and the picker cases in the modal tests. Update `esc_closes_the_topmost_one_at_a_time` to use the remaining panels.
  - `machine_picker` drops `track_focus`. It closes through `.on_mouse_down_out(...)`, which calls `PairingPanel::close_picker`, and closes after an entry is clicked.
  - The fix for the stale doc at `modal.rs:2` (it lists Ctrl+Shift+D/E) belongs in this task.
- [ ] **Step 5: Verify green.**
  - `cargo test -p shellx-model` → PASS, with the same focused command now passing. Record it in the commit body.
  - `cargo build --release -p shellx-app` → OK.
  - On the harness, open the "+" picker, click the terminal, type `echo hi⏎`. Expected: it is echoed, and the picker closed on the click.
- [ ] **Step 6: Commit.** `fix(shellx-windows): typed text reaches the focused field and the "+" list never holds the keyboard`

### Task 3: Sign-in moves to Settings → Account (no password prompt at launch)

**Files:**
- Modify: `windows/shellx-app/src/ui/login.rs`. Rename the struct to `SignInDialog` and the events to `SignInEvent::{Opened, Closed}`. Render it as a centred modal.
- Modify: `windows/shellx-app/src/ui/sidebar.rs:58-101`. `render` loses its `login` parameter. The login card at `:84-86` is removed.
- Modify: `windows/shellx-app/src/ui/settings.rs:104-140` (Account section).
- Modify: `windows/shellx-app/src/ui/root.rs` (wiring, the machines "+" when signed out, render order).
- Modify: `windows/shellx-model/src/modal.rs`.
  - Rename `Panel::Login` to `Panel::SignIn` and the field `Panels::login` to `sign_in`.
  - Draw `SignIn` above `Settings`. The order becomes `ForcedUpdate, SignIn, Settings, Pairing`.
  - Set `Str::Cancel` vi to "Hủy" (the Mac's spelling).
- Modify: `windows/shellx-model/src/strings.rs`: `SignInTitle`, `EmailAddress`, `SignInEllipsis`, `SignInSubtitle`.

**Interfaces:**
- Produces:
  - `SignInDialog::open(&mut self, window: &mut Window, cx: &mut Context<Self>)`;
  - `SignInDialog::is_open(&self) -> bool`;
  - `SignInDialog::focus_target(&self, cx: &App) -> FocusHandle`;
  - `RootView::open_sign_in(&mut self, window: &mut Window, cx: &mut Context<Self>)`.
- Settings emits `SettingsEvent::SignInRequested`, which RootView handles by calling `open_sign_in`.

- [ ] **Step 1: Write the failing test** `sign_in_draws_above_settings_and_opens_while_settings_is_open` in `modal.rs`:
  - `Panels { settings: true, sign_in: true, .. }.top() == Some(Panel::SignIn)`;
  - `Panels { settings: true, .. }.may_open(Panel::SignIn)`;
  - `esc_target()` closes SignIn first, then Settings.
- [ ] **Step 2: Run it.** `cargo test -p shellx-model sign_in_draws_above` → FAIL (no `SignIn`).
- [ ] **Step 3: Implement the model rename and order** until the modal tests pass. Then do the UI:
  - **Dialog:**
    - an absolute overlay below the title bar, with backdrop `BG` @0.6 that swallows clicks;
    - a card 340 px wide, padding 20, `RAISE` fill, 1 px `BORDER`, radius 10;
    - title `SignInTitle` 15 px semibold `text_hi`;
    - labels `EmailAddress` and `Password` (existing), each above its `TextField`;
    - the error line (existing `login_failed`);
    - a right-aligned button row:
      - `Cancel` (Secondary);
      - `Login` (Primary). It is disabled until both fields are non-empty, and shows `SigningIn` while busy.
  - **Dialog behaviour:**
    - Enter submits and Esc cancels, both through the existing `TextFieldEvent`.
    - The dialog closes itself on `LoggedIn` (keep the observer at `login.rs:75-94`).
    - The password is cleared after each attempt (unchanged).
  - **Settings Account, signed out:**
    - `NotLoggedIn` (13 px `text_hi`);
    - `SignInSubtitle` (11 px muted);
    - Primary `SignInEllipsis`, which emits `SignInRequested`.
  - **Settings Account, signed in:** unchanged (email or "Đã đăng nhập", then `Logout`).
  - **Machines header "+" (`ui/sidebar.rs:129-168`):** while `account.state()` is not `LoggedIn`, it calls `open_sign_in`; otherwise it toggles the picker (as today).
  - **Account errors** that used to show in the sidebar card (`login.rs:302-311`) now show only in Settings → Account through the existing `notice()` line.
  - **Render order (`root.rs:808-809`):** settings, then the sign-in dialog, then the forced-update overlay.
- [ ] **Step 4: Verify.**
  - `cargo test -p shellx-model` → PASS.
  - Release build OK.
  - Harness shots:
    1. at launch, the sidebar has no "Chưa đăng nhập" card;
    2. Settings shows "Đăng nhập…";
    3. clicking it shows the dialog centred over the window. Typing in Email works on the harness.
- [ ] **Step 5: Commit.** `feat(shellx-windows): sign in from Settings → Account like the Mac; the sidebar never asks for a password`

### Task 4: The UI language follows Windows; Mac wording for existing strings

**Files:**
- Modify: `windows/shellx-model/src/strings.rs:12-21` (language choice), the values in the Global Constraints table marked "changed", and tests `env_parsing` (`:464`) and `exact_vi_strings` (`:442`).
- Modify: `windows/shellx-app/src/os_info.rs` (new fn).
- Modify: `windows/shellx-app/Cargo.toml` (`windows-sys` feature `Win32_Globalization`).
- Modify: `windows/shellx-app/src/ui/app.rs:40`.
- Modify: `windows/shellx-app/src/ui/settings.rs:197-205`, where the Language row shows `LanguageName` · `LanguageHint`.

**Interfaces:**
- Produces:
  - `Lang::from_system(env: Option<&str>, ui_lang_id: Option<u16>) -> Lang`;
  - `os_info::ui_language_id() -> Option<u16>`, which is `GetUserDefaultUILanguage()` on Windows and `None` elsewhere.
- `Lang::from_env`/`from_env_value` are removed. Their callers use `from_system`.

- [ ] **Step 1: Write the failing test** `language_follows_windows_unless_overridden`:
  - `from_system(None, Some(0x042A)) == Vi` (vi-VN);
  - `from_system(None, Some(0x0409)) == En`;
  - `from_system(None, None) == En`;
  - `from_system(Some("en"), Some(0x042A)) == En`;
  - `from_system(Some("vi"), Some(0x0409)) == Vi`;
  - `from_system(Some(""), Some(0x042A)) == Vi`;
  - `from_system(Some("fr"), Some(0x0409)) == En`.
- [ ] **Step 2: Run it.** → FAIL (no `from_system`).
- [ ] **Step 3: Implement.**
  - An env value starting with `en` or `vi` (trimmed, case-insensitive) wins.
  - Otherwise `ui_lang_id & 0x3ff == 0x2a` gives `Vi`, and anything else `En`.
  - Update the changed strings and the exact-string tests.
- [ ] **Step 4: Verify.**
  - `cargo test -p shellx-model` → PASS.
  - Release build OK.
  - `dev/mac-shot.sh` shows English ("YOUR MACHINES").
  - `SHELLX_LANG=vi dev/mac-shot.sh` shows "Máy của bạn".
- [ ] **Step 5: Commit.** `feat(shellx-windows): the UI language follows the Windows display language`

### Task 5: Model: split regions hold a stack of terminals (tabs)

`PaneId` stays "one terminal". `PaneHost`, `RespawnGuard`, the remote code and `TermView` keep using it. The layout tree's leaves become `SlotId` regions, and each region holds a `Stack` of terminals.

**Files:**
- Modify: `windows/shellx-model/src/layout.rs`.
  - Add `pub struct SlotId(pub u64)` (derive like `PaneId`).
  - `Node::Leaf`, `Layout::{new, split, close, contains, rects, neighbor}` and `Close::Closed { focus }` switch from `PaneId` to `SlotId`.
  - `Layout::panes()` becomes `slots()`.
  - Tests use `fn s(n: u64) -> SlotId`.
- Modify: `windows/shellx-model/src/tabs.rs` (Stack, Tab, Tabs).
- Modify: `windows/shellx-model/src/keys.rs`.
  - `AppCommand::NewTab` becomes `NewWorkspace` (Ctrl+Shift+N).
  - New `NewTerminal` (Ctrl+Shift+T).
  - New test `new_workspace_and_new_terminal_bindings`.
- Modify, compile fixes only:
  - `windows/shellx-app/src/workspace.rs:48-53` (`model_panes` → `tab.panes()`) and its tests;
  - `smoke.rs:560-620`;
  - `remote_tabs.rs` tests;
  - `ui/panes.rs:114-119`, which renders each slot's `stack.selected_pane()`.
- Modify: `windows/shellx-app/src/ui/root.rs:382-420`.
  - `NewWorkspace` → `new_tab`.
  - `NewTerminal` → new `fn new_terminal(&mut self, window, cx)`, which mirrors `split` (`:437-447`): it uses `split_target` for the target and the remote plan, then calls `Tabs::new_surface`.

**Interfaces:**
- Produces, in `shellx_model::tabs`:
  - `pub struct Stack { pub panes: Vec<PaneId>, pub selected: usize }` and `impl Stack { pub fn selected_pane(&self) -> PaneId }`.
  - `pub struct Tab { pub id: TabId, pub layout: Layout, pub stacks: BTreeMap<SlotId, Stack>, pub focused: PaneId }`.
  - `impl Tab`:
    - `pub fn panes(&self) -> Vec<PaneId>`: layout slot order, then stack order;
    - `pub fn slot_of(&self, pane: PaneId) -> Option<SlotId>`;
    - `pub fn focused_slot(&self) -> SlotId`;
    - `pub fn contains(&self, pane: PaneId) -> bool`.
  - `impl Tabs`:
    - `pub fn new_surface(&mut self, target: PaneTarget) -> PaneId`;
    - `pub fn contains(&self, pane: PaneId) -> bool`.
  - Existing `Tabs` signatures are unchanged.
- Semantics:
  - **`new_surface`:** inserts right after the selected pane of the focused slot, selects it and focuses it.
  - **`split_focused`:** makes a new slot holding one new pane.
  - **`close_pane`:**
    - If the pane's stack has more panes: remove it; the stack selects the pane now at the same index, else the last one; return `PaneClosed { tab, focus }`, where `focus` is the tab's (possibly new) focused pane.
    - If it was the stack's only pane: close the slot as today. The focus is the selected pane of the slot that `Layout::close` reports.
  - **`focus(pane)`:** makes its tab active, selects it in its stack and focuses it.
  - **`focus_dir`:** moves to the neighbour slot's selected pane.

- [ ] **Step 1: Write the failing tests** in `tabs.rs`:
  - `new_surface_stacks_in_the_focused_slot`: after `new_surface`, the focused slot's stack has 2 panes, the new one selected and focused, and `layout.slots().len() == 1`.
  - `closing_a_stacked_pane_selects_the_one_at_its_index_then_the_last`: a stack [a, b, c] with b selected. Closing b selects c. Closing c selects a.
  - `closing_the_last_pane_of_a_slot_closes_the_slot`.
  - `focus_selects_the_pane_in_its_stack`.
  - `focus_dir_moves_to_the_neighbour_slots_selected_pane`.
  - `split_puts_one_new_pane_in_a_new_slot`.
  - `new_surface_uses_the_given_target`: a remote target is stored for the new pane.
  - `tab_panes_lists_every_stacked_pane`.
- [ ] **Step 2: Run them.** `cargo test -p shellx-model` → compile errors or FAIL.
- [ ] **Step 3: Implement the model changes.**
  - Adapt the existing layout and tabs tests to `SlotId` only where they inspect leaves. Their behaviour assertions stay.
  - Then fix the `shellx-app` compile sites listed above.
- [ ] **Step 4: Verify.**
  - `cargo test -p shellx-model` → PASS.
  - `cargo test -p shellx-app` → PASS.
  - `cargo build --release -p shellx-app` → OK.
  - On the harness, Ctrl+Shift+T replaces the visible terminal with a fresh shell (tab bar not drawn yet). Ctrl+Shift+W returns to the first shell.
- [ ] **Step 5: Commit.** `feat(shellx-windows): split regions stack several terminals`

### Task 6: A tab bar on every region, like the Mac's Bonsplit bar

**Files:**
- Create: `windows/shellx-app/src/ui/tab_bar.rs`.
- Create: `windows/shellx-app/src/ui/tooltip.rs`. Move `Tooltip` there from `ui/sidebar.rs:265-…` and update its uses.
- Modify: `windows/shellx-app/src/ui/panes.rs`. A slot draws `tab_bar::render` (30 px) above the selected pane's view.
- Modify: `windows/shellx-app/src/workspace.rs:28-45`. Replace `SESSION_BAR_H` with `TAB_BAR_H: f32 = 30.0`. `estimate_pane_area` subtracts only `TITLEBAR_H`, because tab bars sit inside each slot rect.
- Modify: `windows/shellx-app/src/ui/root.rs`.
  - Remove `session_bar` (`:623-674`) and its use (`:781`).
  - Add `pub fn close_terminal(&mut self, pane: PaneId, window, cx)`, which routes to `close_pane`.
  - `new_terminal` (Task 5) gains a `slot` parameter that focuses that slot first.
- Modify: `windows/shellx-model/src/palette.rs`: `SELECTION_TITLE`, `INDICATOR_UNFOCUSED`, `RAIL_PURPLE`.
- Modify: `windows/shellx-app/src/icons.rs`, adding `CloseSm` (`close_sm.svg`), `Columns` (`columns.svg`) and `Rows` (`rows.svg`).
- Create: those three SVGs in `windows/shellx-app/assets/icons/`.
- Modify: `windows/shellx-model/src/strings.rs`: `NewTerminal`, `CloseTab`.

**Interfaces:**
- Consumes `Tab::stacks`, `Stack`, `Tab::focused_slot`, `RootView::new_terminal`, `RootView::split`, `RootView::focus_pane` and `RootView::tab_title(pane, lang, cx)` (an existing private fn, made `pub(super)`).
- Produces: `pub(super) fn render(slot: SlotId, stack: &Stack, focused_slot: bool, lang: Lang, cx: &mut Context<RootView>) -> Div`. It reads titles through `RootView::tab_title`.

**Icons:**
- Download `https://github.com/krystonschwarze/coolicons/releases/download/v4.1/coolicons.v4.1.zip` into an empty scratch directory.
- Take the plain SVGs `Close_SM`, `Columns` and `Rows`.
- Prefix each with the same one-line header as `assets/icons/terminal.svg` (`<!-- coolicons v4.1 · <Category> / <Name> · CC BY 4.0 · Kryston Schwarze -->`).
- Set every stroke and fill colour to `currentColor`, as in the existing files.

**Look** (palette names from `palette.rs`):
- **Bar:** height 30, `PANEL` fill, 1 px bottom `LINE`.
- **Tab:**
  - height 30, px 10, gap 6;
  - `Terminal` icon 14 px;
  - title 11 px, truncated, max width 180;
  - a 16×16 close box holding `CloseSm` at 9 px. The close button is muted and turns `TEXT_HI` on hover. Its click calls `close_terminal` and stops propagation.
  - A click on the tab body calls `focus_pane`.
- **Selected tab in the focused slot:** `PRIMARY_SOFT` fill, title `SELECTION_TITLE` semibold, a 2 px `PRIMARY` bar along the bottom.
- **Selected tab in another slot:** `RAISE` fill, a 2 px `INDICATOR_UNFOCUSED` bar.
- **Other tabs:** title `MUTED`, hover fill `SESSION_HOVER`.
- **Right side:** pr 6, gap 2, three 20×20 buttons with 14 px icons, each with a tooltip:
  1. `Terminal` → `new_terminal(slot)`, tooltip `NewTerminal`;
  2. `Columns` → split right, `SplitRight`;
  3. `Rows` → split down, `SplitDown`.

- [ ] **Step 1: Write the failing test** `pane_area_leaves_room_for_the_title_bar_only` in `workspace.rs` tests: `estimate_pane_area(1200.0, 760.0, true) == Rect { x: 0.0, y: 0.0, w: 910.0, h: 720.0 }`.
- [ ] **Step 2: Run it.** `cargo test -p shellx-app pane_area_leaves_room` → FAIL (today h = 684).
- [ ] **Step 3: Implement** the files above.
- [ ] **Step 4: Verify.**
  - `cargo test -p shellx-app` and `cargo test -p shellx-model` → PASS.
  - Release build OK.
  - Harness shot 1: one tab with three buttons on the right, and no "PowerShell › PC" bar.
  - Shot 2: after Ctrl+Shift+T and a click on the Columns button, there are two regions. The left one has 2 tabs and the right one has 1. The focused tab is blue-tinted with a bottom bar.
  - Put the shots next to the Mac reference.
- [ ] **Step 5: Commit.** `feat(shellx-windows): a tab bar on every split region`

### Task 7: The Mac header and focus history

**Files:**
- Create: `windows/shellx-model/src/history.rs`, registered in `shellx-model/src/lib.rs`.
- Modify: `windows/shellx-app/src/ui/titlebar.rs` (rebuilt layout).
- Create: `windows/shellx-app/src/ui/menu.rs`. A small popover menu, used here and by Task 10.
- Modify: `windows/shellx-app/src/ui/root.rs`.
  - New fields `history: FocusHistory`, `last_focus: PaneId`, `new_menu_open: bool`.
  - New fns `focus_back`, `focus_forward`, `note_focus`.
- Modify: `windows/shellx-app/src/icons.rs` plus SVGs `arrow_left_md.svg`, `arrow_right_md.svg`, `folder.svg` (the same way as Task 6).
- Modify: `windows/shellx-model/src/strings.rs`: `NewWorkspace`, `NewWorkspaceOptions`, `NewTerminalTab`, `FocusBack`, `FocusForward`, `ShowHideSidebar`, `ShowNotifications`.

**Interfaces:**
- Produces `shellx_model::history::FocusHistory`:
  - `new() -> Self`;
  - `record(&mut self, from: PaneId, to: PaneId)`:
    - ignored when `from == to`;
    - pushes `from` onto back, capped at 50 (the oldest is dropped);
    - clears forward.
  - `back(&mut self, current: PaneId, alive: &dyn Fn(PaneId) -> bool) -> Option<PaneId>`:
    - pops until it finds an alive pane;
    - pushes `current` onto forward;
    - returns `None` and changes nothing when no alive pane is left.
  - `forward(..)`: the mirror of `back`.
  - `can_back(&self, alive: &dyn Fn(PaneId) -> bool) -> bool` and `can_forward(..)`.
- Produces `menu::popover(items: Vec<MenuItem>, on_close: impl Fn(&mut Window, &mut App) + 'static) -> impl IntoElement`.
  - `MenuItem { label: SharedString, shortcut: Option<&'static str>, on_click: Box<dyn Fn(&mut Window, &mut App)> }`.
  - Drawn with `deferred(anchored()...)`. Closes on `on_mouse_down_out`, and after any item click.
- RootView behaviour:
  - `note_focus()` is called at the end of `after_focus_change`, `select_tab` and `focus_pane`. It records `last_focus → tabs.active().focused` unless `navigating` is set.
  - `focus_back`/`focus_forward` set `navigating`, call `Tabs::focus(p)` and `after_focus_change`, then clear it.

**Header layout:**
- One row, 40 px, `PANEL` fill, 1 px bottom `LINE`, drag area as today.
- **Left group:** gap 6, pl 8 (or the macOS 72 px inset). Buttons are 20×20, radius 6, icon 14 px muted, hover `TEXT_HI`.
  1. `WindowSidebar` → `toggle_sidebar`, tooltip `ShowHideSidebar`.
  2. `BellRing`, display-only, tooltip `ShowNotifications`.
  3. A split button:
     - `AddPlus` → `new_tab` (new workspace), tooltip `NewWorkspace` + " (Ctrl+Shift+N)";
     - `ChevronDown` 10 px → toggles `new_menu_open`, tooltip `NewWorkspaceOptions`.
     - The menu items are `NewWorkspace` "Ctrl+Shift+N" and `NewTerminalTab` "Ctrl+Shift+T".
  4. `ArrowLeftMd` → `focus_back`, tooltip `FocusBack`, opacity 0.4 when it cannot go back.
  5. `ArrowRightMd` → `focus_forward`, tooltip `FocusForward`.
- **Workspace name:** ml 10, `Folder` icon 16 px muted, gap 6, then the active workspace title (`tab_title(active.focused)`) in 13 px semibold `TEXT_HI`, truncated, flex 1, `min_w_0`.
- **Right group:** gap 8, pr 8.
  - The existing display-only search box, resized to 280×24, radius 6, `Search` icon 12 px, placeholder `SearchPlaceholder` 12 px muted.
  - Gear 24×24, `Settings` icon 14 → `open_settings`, tooltip `Settings`.
  - Then the caption buttons (Windows).

- [ ] **Step 1: Write the failing tests** in `history.rs`:
  - `back_and_forward_round_trip`;
  - `back_skips_closed_panes`;
  - `record_clears_forward`;
  - `same_pane_is_not_recorded`;
  - `back_is_capped_at_fifty`;
  - `nothing_alive_changes_nothing`.
- [ ] **Step 2: Run them.** `cargo test -p shellx-model history` → FAIL (module missing).
- [ ] **Step 3: Implement** `history.rs`, then the UI pieces above.
- [ ] **Step 4: Verify.**
  - `cargo test -p shellx-model` → PASS.
  - Release build OK.
  - Harness shot of the header, set next to the Mac title bar. Check the control order and that the workspace name shows.
  - On the harness: open 2 workspaces, switch between them, and check Back returns to the first and Forward returns to the second.
- [ ] **Step 5: Commit.** `feat(shellx-windows): the Mac header with new-workspace menu and focus back/forward`

### Task 8: Working directory and git branch of local terminals

**Files:**
- Create: `windows/shellx-app/src/cwd.rs` (GPUI-free, registered in `main.rs` next to the other modules).
- Modify: `windows/shellx-app/src/local_pty.rs`.
  - `default_shell()` returns `ShellCmd { program: String, args: Vec<String>, env: Vec<(String, String)> }`.
  - `LocalPty::spawn(program: &str, args: &[&str], env: &[(&str, &str)], cols: u16, rows: u16)`.
- Modify: `windows/shellx-app/src/workspace.rs:153-160` (`spawn_local_pane` passes the env).
- Modify: `windows/shellx-app/src/term_core.rs` (add `pub fn pwd(&self) -> Option<String>`, delegating to `ghostty_vt::Terminal::pwd`).
- Modify: `windows/shellx-app/src/ui/term_view.rs` (add `pub(super) fn cwd(&self) -> Option<String>`). It returns the OSC 7 URL of a local pane, `None` for remote panes.

**Interfaces:**
- Produces, in `crate::cwd`:
  - `pub fn cwd_from_osc7(url: &str) -> Option<String>`.
    - Accepts `file://HOST/PATH`.
    - Percent-decodes UTF-8.
    - `/C:/x/y` becomes `C:\x\y`. A unix path stays as it is.
    - Anything that is not `file://` gives `None`.
  - `pub fn display_path(cwd: &str, home: Option<&str>) -> String`.
    - Returns `~` for home itself and `~` + the rest for paths under home, keeping the path's own separator.
    - The comparison is case-insensitive for drive-letter paths.
    - Otherwise the path is returned unchanged.
  - `pub fn git_branch(cwd: &Path) -> Option<String>`.
    - Walks up looking for `.git`.
    - A `.git` directory gives `.git/HEAD`.
    - A `.git` file `gitdir: <p>` gives `<p>/HEAD`, with `<p>` relative to the file's directory.
    - `ref: refs/heads/NAME` gives `NAME`.
    - A detached 40-hex HEAD gives its first 7 characters.
    - No repo gives `None`.
  - `pub struct BranchCache` with `new()` and `get(&mut self, cwd: &str, now: Instant) -> Option<String>`. A cwd's value is reused for 2 s, then read again.

**Shell hooks (exact copy):**
- Windows default:
  - program `powershell.exe`;
  - args `-NoLogo`, `-NoExit`, `-Command`, then:

    ```
    $__shellxPrompt = $function:prompt; function global:prompt { $l = $ExecutionContext.SessionState.Path.CurrentLocation; if ($l.Provider.Name -eq 'FileSystem') { [Console]::Write([char]27 + ']7;file://' + $env:COMPUTERNAME + '/' + ($l.ProviderPath -replace '\\','/') + [char]27 + '\') }; if ($__shellxPrompt) { & $__shellxPrompt } else { "PS $($l.Path)> " } }
    ```
  - no extra env.
- Non-Windows default (dev harness):
  - program `/bin/bash`;
  - args `--noprofile`, `--norc`, `-i`;
  - env `PROMPT_COMMAND=printf '\033]7;file://%s%s\033\\' "$HOSTNAME" "$PWD"`.
- `SHELLX_SHELL` set: that program, no args, no env (unchanged).

- [ ] **Step 1: Write the failing tests** in `cwd.rs` (use `tempfile` for repos):
  - `osc7_windows_path`: `file://PC/C:/Users/Admin` → `C:\Users\Admin`.
  - `osc7_unix_path`.
  - `osc7_with_unicode_and_percent_escapes`: `file://PC/C:/T%C3%A0i%20li%E1%BB%87u` and the raw `file://PC/C:/Tài liệu` both → `C:\Tài liệu`.
  - `osc7_rejects_other_schemes`.
  - `display_path_home_and_below_and_outside`, with the cases:
    - `C:\Users\Admin` → `~`;
    - `c:\users\admin\code` → `~\code`;
    - `D:\x` → `D:\x`;
    - `/Users/a/p` with home `/Users/a` → `~/p`.
  - `git_branch_plain_repo`.
  - `git_branch_from_a_subdirectory`.
  - `git_branch_worktree_gitdir_file`.
  - `git_branch_detached_head_is_short_sha`.
  - `git_branch_none_outside_a_repo`.
  - `branch_cache_rereads_after_two_seconds`.
  - In `local_pty.rs` tests: `default_shell_has_the_osc7_hook`. It checks the non-Windows env has `PROMPT_COMMAND` containing `]7;file://`. On Windows, the args contain `-NoExit` and the hook string.
- [ ] **Step 2: Run them.** `cargo test -p shellx-app cwd` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Verify.**
  - `cargo test -p shellx-app` → PASS.
  - Release build OK.
  - On the harness, `cd` into the repo, then confirm (with a temporary `eprintln!` that you remove before committing, or the Task 9 card) that `TermView::cwd()` gives the repo path.
- [ ] **Step 5: Commit.** `feat(shellx-windows): track the working directory and git branch of local terminals`

### Task 9: Workspace cards and Mac-style sidebar headers

**Files:**
- Modify: `windows/shellx-app/src/ui/sidebar.rs`.
  - `SessionRow` gains `pub path: Option<String>` and `pub branch: Option<String>`.
  - `session_row` (`:419-463`) becomes `workspace_card`.
  - The brand row (`:104`), machines header (`:129`) and group header (`:291`) are restyled.
  - `new_tab_button` (`:171`) is removed from the machine header.
- Modify: `windows/shellx-app/src/ui/root.rs:706-721`. It builds rows with:
  - `path`: `display_path(cwd_from_osc7(view.cwd()), home)`, where `home` is `USERPROFILE`, else `HOME`. For a remote pane, `path` is the Mac's name instead.
  - `branch`: from a `BranchCache` field on `RootView`.

**Look** (Mac values from the spec):
- **Card:**
  - mx 8, my 2, radius 6;
  - a 3 px `RAIL_PURPLE` @0.95 rail on the left edge, full height;
  - content pl 12, pr 8, py 6, gap 2.
- **Card content:**
  - line 1: the title, 12 px semibold. `SELECTION_TITLE` when selected, else `TEXT_HI`. Truncated.
  - line 2, only if there is a branch: `⎇ {branch}`, 11 px `MUTED`, truncated.
  - line 3, only if there is a path: the path, 11 px `MUTED`, truncated.
- **Card state:**
  - selected: `SESSION_SELECTED` fill and a 1 px `BORDER` edge;
  - hover: `SESSION_HOVER`;
  - a click selects the workspace (as today).
- **Brand row:** `Logo` 18 px, then "ShellX" 14 px semibold `TEXT_HI` in the UI font. This replaces the Space Grotesk wordmark, as the Mac uses the system font.
- **Machines header:** `MachinesHeader` 10.5 px medium `MUTED`, and the "+" as `AddPlus` 18 px.
- **Machine row:**
  - `Laptop`/`Desktop` icon 16 px;
  - the title in 12 px semibold `TEXT_HI`;
  - " · {ThisMachine}" in 11 px `MUTED`;
  - a 6 px dot, `DONE` when online, else `MUTED`.

- [ ] **Step 1: Write the failing test** `row_lines_for_local_and_remote_panes` in `cwd.rs`. `root.rs` is UI and has no tests, so the decision lives in a GPUI-free fn:
  - `pub fn row_lines(local_cwd: Option<&str>, remote_machine: Option<&str>, home: Option<&str>) -> (Option<String>, bool)` returns the path line and whether to look up a branch.
  - Test that a remote pane gives `(Some(machine), false)`.
  - Test that a local pane with cwd `C:\Users\Admin\code` and home `C:\Users\Admin` gives `(Some("~\\code"), true)`.
  - Test that a local pane without a cwd gives `(None, false)`.
- [ ] **Step 2: Run it.** → FAIL.
- [ ] **Step 3: Implement** `row_lines` and the sidebar changes.
- [ ] **Step 4: Verify.**
  - `cargo test -p shellx-app` → PASS.
  - Release build OK.
  - Harness: `cd` into the shellx repo and take a shot. The card shows the purple rail, the title, `⎇ feat/windows-mac-parity` and `~/Documents/myProjects/shellx`.
  - Put it next to the Mac sidebar reference.
- [ ] **Step 5: Commit.** `feat(shellx-windows): Mac-style workspace cards with directory and git branch`

### Task 10: Sidebar footer: Help, version, update pill

**Files:**
- Modify: `windows/shellx-app/src/ui/sidebar.rs:476-495`. `footer` is replaced. It gains `account: &Entity<AccountService>` and `help_open: bool` parameters.
- Modify: `windows/shellx-app/src/ui/root.rs`.
  - New field `help_open: bool`.
  - Remove the top update banner at `:739-749`. Keep `required_overlay`.
- Modify: `windows/shellx-app/src/ui/update_banner.rs`. Delete `banner` and keep `required_overlay` and `open_https`.
- Modify: `windows/shellx-app/src/ui/account.rs:177-186`. Delete `banner_visible`/`hide_banner` and the `banner_hidden` field.
- Modify: `windows/shellx-model/src/update.rs:68`. Replace the unused `banner(status, lang)` with `pub fn pill_text(status: &UpdateStatus, lang: Lang) -> Option<String>`.
- Modify: `windows/shellx-model/src/strings.rs`.
  - Add `Help`, `SettingsEllipsis`, `CheckForUpdates`, `Docs`, `GitHub` and `pub fn update_available_pill(lang: Lang, version: &str) -> String`.
  - Remove `E2eFooter`.
- Add: `windows/shellx-app/src/icons.rs` `CircleHelp` with `circle_help.svg` (as in Task 6).

**Interfaces:**
- Consumes `menu::popover` (Task 7), `update_banner::open_https`, `AccountService::{update_status, check_update}` and `RootView::open_settings`.

**Look:**
- Footer: px 6 left, 10 right, py 6, gap 4, 1 px top `LINE`.
- **Help button:**
  - 22×22, `CircleHelp` 14 px muted, tooltip `Help`.
  - A click toggles `help_open` and shows a popover with:
    1. `SettingsEllipsis` → `open_settings`;
    2. `CheckForUpdates` → `check_update`;
    3. `Docs` → `open_https("https://shellx.pro")`;
    4. `GitHub` → `open_https("https://github.com/lephus/shellx")`.
- **Version label:** `v{shellx_model::VERSION}`, 11 px `MUTED`, px 5, height 22.
- Flex spacer.
- **Update pill:** only when `pill_text` is `Some`.
  - Height 22, px 8, fully rounded, `PRIMARY_SOFT` fill, 1 px `PRIMARY_LINE`.
  - Text 11 px medium `PRIMARY_TEXT`.
  - A click calls `open_https(url)` when `download_url(status)` is `Some`.

- [ ] **Step 1: Write the failing test** `pill_text_only_for_an_available_update` in `update.rs`:
  - `Available { version: "1.5.4", .. }` gives `Some("Có bản cập nhật: 1.5.4")` in Vi and `Some("Update Available: 1.5.4")` in En;
  - `UpToDate`, `Unknown` and `Required { .. }` give `None`.
- [ ] **Step 2: Run it.** → FAIL.
- [ ] **Step 3: Implement.** Delete the `banner` tests at `update.rs:187-200` along with `banner`.
- [ ] **Step 4: Verify.**
  - `cargo test -p shellx-model` and `cargo test -p shellx-app` → PASS.
  - Release build OK.
  - Harness shot: the footer shows `?` and `v1.5.3`, with no "Mã hoá đầu cuối" line and no banner at the top.
  - Clicking `?` opens the 4-item menu.
- [ ] **Step 5: Commit.** `feat(shellx-windows): Mac-style sidebar footer with help menu, version and update pill`

### Task 11: Build a Windows installer and hand over the Windows-only checks

**Files:**
- Modify: `windows/README.md`. Update the keyboard-shortcut table (Ctrl+Shift+N/T) and the "Dark theme only; UI text is Vietnamese by default" line. The language now follows Windows.
- Modify: `windows/G1-G3-CHECKLIST.md`. Append the section "Wave 1 parity" with the checklist below.

- [ ] **Step 1: Run every test.** `cargo test -p shellx-model && cargo test -p shellx-app` → PASS. Also `python3 -m unittest discover -s windows/installer -v` → OK.
- [ ] **Step 2: Cross-build.**
  - Run `scripts/shellx/release/build-windows-cross.sh dist/windows-parity`. It needs the VPS ssh master `~/.ssh/cm-shellx-vps`. If it is not open, ask the user to run `ssh -fNM -S ~/.ssh/cm-shellx-vps higio@42.115.41.70` in their own Terminal.
  - Expected: `dist/windows-parity/ShellX-Setup-1.5.3.exe` and its `.sha256`. The build ran `cargo test -p shellx-model` inside the container.
  - This is a test build. Do not publish it, and do not bump the version.
- [ ] **Step 3: Write the checklist** into `G1-G3-CHECKLIST.md`, in Vietnamese like the rest of the file:
  1. Install the test build over 1.5.3. The app opens with no email or password card.
  2. With no input method (Unikey off), click the terminal and type `dir⏎`. The letters appear and the command runs.
  3. Unikey Telex: type `tiếng Việt` in PowerShell. The final text is correct. Do the same with the built-in Windows Vietnamese Telex.
  4. Settings → Account → "Đăng nhập…". Type an email and password with Unikey both off and on. The fields fill, and Enter signs in.
  5. Ctrl+Shift+T adds a tab, Ctrl+Shift+W closes it, Ctrl+Shift+N adds a workspace, and the Columns/Rows buttons split. Back/Forward in the header move between workspaces.
  6. `cd` into a git repo. The card shows `~\…` and `⎇ <branch>`. Do the same with a PowerShell profile that defines its own `prompt` (oh-my-posh, if installed). The prompt still works.
  7. Windows display language English → English UI. Vietnamese → Vietnamese UI.
  8. Caption buttons minimize, maximize and close. Snap layouts appear on hover over maximize.
- [ ] **Step 4: Commit.** `docs(shellx-windows): wave 1 parity checklist and README`. Then tell the user the installer path and the sha256, and ask them to run the checklist on their Windows PC.

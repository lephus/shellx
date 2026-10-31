# ShellX for Windows: parity with the Mac app

- **Date:** 2026-11-01
- **Status:** wave 1 approved by the user ("fix lại win đi"), later waves listed only
- **Scope:** the native Windows app in `windows/` (Rust, GPUI 0.2.2). The Mac app is the reference and is not changed.

## 1. Intent

The user's words: "tôi cần win giống 100% mac". The two problems they named came from opening ShellX on a Windows PC:

- the interface does not look like the Mac app;
- the app asks for an email and a password;
- typing from the keyboard does not work;
- the header does not show all the features.

The evidence is the screenshot comparison `.superpowers/brainstorm/16640-1793467424/content/mac-vs-win.html`: the Mac window and the user's Windows screenshot side by side, with 8 marked differences.

Today the two apps share no UI code:

- **Mac:** a fork of cmux, about 2.3M lines of Swift including vendored packages.
- **Windows:** a separate MVP, about 24k lines of Rust.

Parity therefore comes in waves. Each wave ships something the user can install and try on Windows.

## 2. Goals of wave 1

1. **Typing works:**
   - in the terminal;
   - in every text field;
   - with the Windows Vietnamese keyboard, Unikey and EVKey, and with no input method at all.
2. **No sign-in on launch.**
   - The sidebar never shows email or password fields.
   - Sign-in lives in Settings → Account and opens a "Đăng nhập ShellX" dialog, as on the Mac.
3. **A header like the Mac's.**
   - Left: sidebar toggle, bell, a "+" split button (new workspace, plus a ▾ menu), focus back, focus forward.
   - Then a folder icon and the workspace name.
   - Right: the search field and the settings gear, followed by the Windows caption buttons.
4. **A tab bar on every split region, like Mac's Bonsplit.**
   - A region holds one or more terminals shown as tabs, each with a close button.
   - On the right of the bar: New terminal, Split right, Split down.
5. **Workspace cards in the sidebar, like the Mac's:**
   - a coloured left rail;
   - the title;
   - the working directory as `~\…`;
   - the git branch for local terminals.
6. **A sidebar footer like the Mac's:**
   - a Help button with a menu;
   - the version label `v1.5.3`;
   - an update pill "Có bản cập nhật: X", which replaces the top banner.
7. **The UI language follows Windows.**
   - Vietnamese when the Windows display language is Vietnamese, English otherwise.
   - Wording is copied from the Mac's strings.

## 3. Non-goals for wave 1 (later waves, in this order)

- **Wave 2:**
  - command palette behind the search field;
  - notifications panel behind the bell;
  - workspace groups (CAIRA/ME/AGT style);
  - workspace colour picker.
- **Wave 3:** agent status on cards ("claude-code · Working", skills) through hooks and a Windows CLI.
- **Wave 4:** right sidebar (files, Git Graph) and its title-bar toggle.
- **Wave 5:** embedded browser (WebView2) and the "New Browser" tab-bar button.

## 4. Anti-goals

- **No dead buttons.** A Mac control whose feature Windows lacks is left out until its wave. Today's display-only bell and search field stay as they are.
- **No lost keystrokes.** A keystroke must never be dropped silently because an overlay or list is open somewhere else on screen.
- **Nothing that touches the user's running Mac ShellX** (CLAUDE.md).

## 5. Constraints

- **Stack:**
  - keep Rust, GPUI `=0.2.2`, libghostty-vt and ConPTY;
  - no webview for the main UI;
  - no new crates without a reason written in the plan.
- **Colours:** the ShellX palette `windows/shellx-model/src/palette.rs`. It holds the same values as the Mac's `ShellXPalette`. Dark theme only, as on the Mac.
- **Workspace rail colour:** the Mac's default "Purple" `#6A1B9A` (`Sources/WorkspaceTabColorSettings.swift:32`).
- **Sizes from the Mac:**
  - title-bar controls: 20 pt buttons, 12–16 pt icons, spacing 6;
  - search field: 280×24, radius 6;
  - tab bar: 30 tall, tab title 11 pt, close icon 9 pt in a 16 pt box;
  - selected tab: 2 pt indicator;
  - card rail: 3 pt;
  - card corners: 6 pt.
- **Windows title bar:** keeps its 40 px height and its native caption buttons, so snap layouts keep working.
- **Icons:** coolicons v4.1, the set the Mac uses, as plain SVGs next to the existing ones in `windows/shellx-app/assets/icons/`.

## 6. Decisions

**Decided with the user:**

- Keep the existing Rust/GPUI app; do not rewrite it.
- Work in waves.
- Wave 1 covers the 8 marked differences.

**My calls (the user can override):**

- **Words.** On Windows a sidebar entry is a "workspace": "phiên" in Vietnamese and "Workspace" in English, as on the Mac. A tab in a region's tab bar is a "tab". In code the existing `Tab`/`Tabs` types keep their names and mean "workspace". A split region is a new `SlotId`, and `PaneId` stays "one terminal".
- **Shortcuts.** Plain Ctrl+letter must keep reaching the shell, so the Mac's Cmd shortcuts become Ctrl+Shift:
  - Ctrl+Shift+N: new workspace (Mac Cmd+N);
  - Ctrl+Shift+T: new terminal tab in the focused region (Mac Cmd+T);
  - Ctrl+Shift+W: close terminal;
  - Ctrl+Shift+B: sidebar.
  - Back and Forward have no shortcut in wave 1.
- **The sidebar "+" next to "Máy của bạn".**
  - It keeps opening the list of Macs you can ask for access to.
  - The list is a dropdown that never takes the keyboard. It closes on a click outside it.
  - When signed out, "+" opens the sign-in dialog.
  - Reason: the Mac's "+" adds an SSH machine, and Windows has no SSH.
- **Language.** Windows chooses with `GetUserDefaultUILanguage`: primary language `LANG_VIETNAMESE` (0x2A) gives Vietnamese, anything else English. `SHELLX_LANG` still overrides it.
- **Working directory.** It comes from a PowerShell prompt hook that writes OSC 7 at each prompt. Not for `SHELLX_SHELL` overrides.
- **Git branch.** It is read from `.git/HEAD`, walking up from the working directory, and refreshed at most every 2 s.
- **Development harness.** The Windows UI builds and runs on macOS for development: release builds only, with `windows/dev/mac-shot.sh` for screenshots. The installer is still built only for Windows.

## 7. Verification

- **Logic:** unit tests in `shellx-model` and `shellx-app`, run on the Mac with `cargo test`.
- **Look:** screenshots from the macOS harness, set next to the Mac window.
- **Windows-only behaviour:** WM_CHAR typing, ConPTY, Vietnamese input methods and the caption buttons. These are checked by the user on a cross-built installer (`scripts/shellx/release/build-windows-cross.sh`), using the checklist in the plan's last task.

## 8. Open issue found while preparing

**A debug-build crash in the macOS harness.**

- **Symptom:** a debug assertion in hashbrown 0.17.1, `index < num_buckets`, inside a `serde_json` insert at `core_api::config_set`.
- **Isolation:** the same crate versions do not fail on their own.
- **Suspect:** memory being overwritten somewhere else in the process. In a release build the assertion is off but the write still happens.
- **Status:** tracked as its own investigation, not part of wave 1.

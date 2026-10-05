# Terminal sharing P4 — desktop (switch, installer, menu, build, signing)

- **Spec:** `docs/superpowers/specs/2026-10-01-desktop-terminal-sharing-design.md` §4, §7.6, §10, §11.3, §12. P3 notes: ledger `terminal-sharing.md` "Ghi cho P4".
- **Branch:** `feat/p4-desktop` (from `main`, which has P1–P3).
- **Goal:** on macOS, the menu switch "Chia sẻ terminal với điện thoại (thử nghiệm)" installs `shellx-term` and the shell blocks after a confirmation listing the exact files, starts `TerminalSharing`, and every new Terminal.app window shows up as a desktop session (tray submenu, phone list, notification on attach). Windows: same code paths, unit-tested, switch hidden unless `SHELLX_EXPERIMENTAL=terminal-sharing`. `flutter build macos` bundles `Contents/Helpers/shellx-term`; `flutter build windows` puts `shellx-term.exe` next to `ShellX.exe`; release signing covers both.

## Architecture

All new desktop code lives in `apps/desktop/lib/src/terminal_sharing/`:

| File | Job |
|---|---|
| `shell_blocks.dart` | The three blocks as constants; a test asserts they equal `term/shell/block.{zsh,bash,ps1}` byte for byte |
| `config_text.dart` | Pure: decode/encode (UTF-8, UTF-8 BOM, UTF-16 LE/BE; anything else round-trips byte for byte through latin1), line ending detection, idempotent `insertBlock` / `removeBlock` / `hasBlock` |
| `config_file_editor.dart` | File IO over `config_text`: backup once (`<file>.shellx-backup`, never overwritten), edit through symlinks in place, undo record |
| `sharing_paths.dart` | `bin`, `term`, bundled binary paths per platform (§10.4) |
| `powershell.dart` | Windows: ask each installed PowerShell for `$PROFILE.CurrentUserAllHosts` and its execution policies; classify (ok / needs RemoteSigned / blocked by Group Policy); `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` only on request |
| `term_binary.dart` | Copy bundled → `bin` (macOS temp + rename; Windows rename the old one to `shellx-term.old-<n>.exe`), compare by content, remove `bin`, delete stale `.old-*` |
| `terminal_sharing_setup.dart` | Orchestrator: `prepare()` (the plan shown in the confirmation), `enable()` with rollback, `disable()`, `check()` ("cần thiết lập lại"), startup maintenance (update binary / finish a Windows removal), `cleanup()` for `--terminal-sharing-cleanup` |
| `attach_throttle.dart` | One notification per (phone, terminal) per 10 minutes |
| `availability.dart` | macOS always; Windows only with `SHELLX_EXPERIMENTAL=terminal-sharing` |

Wiring:
- `AgentRuntime` gains `desktopSessions`, `desktopPhoneAttached`, `setTerminalSharing(bool)`, `disconnectDesktopPhone(id)`; `CoreAgentRuntime` owns a `TerminalSharing` over its `DesktopSessionManager`, `SessionRouter(desktopSharing: () => sharing.enabled)`, `sessionChanges` = router changes, `stop()` stops sharing after `closeAll`. The server therefore runs only while the runtime runs (signed in + remote access on).
- `AgentController`: setting `terminal_sharing_enabled`; `enableTerminalSharing(plan)` / `disableTerminalSharing()` / `disconnectDesktopPhone(id)`; on runtime start with the switch on → `setTerminalSharing(true)`; notifications from `desktopPhoneAttached` through the throttle; startup check → `needsSetup`.
- `AgentViewState.terminalSharing` (`available`, `enabled`, `busy`, `needsSetup`, `sessions`).
- Tray: checkbox, submenu "Terminal trên máy tính (N)" with "Ngắt điện thoại" per terminal, warning item (click = set up again). `TrayActions` builds the confirmation (exact files, limits, R2 note on macOS, PowerShell state on Windows) and, on Windows with a fixable policy, a second confirmation whose button is "Cho phép script cục bộ cho tài khoản của tôi".
- `main.dart`: `--terminal-sharing-cleanup` runs `TerminalSharingSetup.cleanup()` and exits before the single-instance lock or any window.

## Tasks

1. **Plan** (this file).
2. **Config text + editor** — tests first (`test/terminal_sharing/config_text_test.dart`, `config_file_editor_test.dart`): insert twice = one block; remove = exact inverse; remove only between markers (unterminated block untouched); encodings UTF-8 / BOM / UTF-16 LE / BE / legacy 8-bit preserved; LF / CRLF preserved, block written with the file's line ending; backup once; undo restores bytes / deletes created file; symlink target edited, link kept; blocks are ASCII and equal `term/shell/*`.
3. **Paths, binary installer, PowerShell probe** — tests with temp dirs and a fake process runner: install, update only when content differs, macOS mode 0755, Windows rename-old path, `.old-*` cleanup, remove `bin`; PowerShell profile query / policy parsing / Group Policy detection / `Set-ExecutionPolicy` only when asked.
4. **Setup orchestrator** — tests: macOS plan (`.zshrc` created, bash files only if present, bash skipped flag), Windows plan (profiles from PowerShell), enable order (binary before blocks), rollback when a step fails (files restored, binary removed, created backups removed), disable (blocks removed everywhere, `bin` removed), `check()` needs-setup rules, startup update, cleanup.
5. **Runtime + controller + throttle** — tests: throttle; controller enable/disable/rollback when the server cannot start, switch persisted, runtime start starts sharing, notification text and throttling, needs-setup at startup; `CoreAgentRuntime` with a real `TermServer` and a fake `shellx-term` client: desktop session survives `closeSession` / `closeAllSessions` / `stop` (P3 note), `stop()` removes `endpoint`.
6. **Tray + l10n + main** — tests: menu (switch shown/hidden, submenu, 📱, warning), key parsing, actions (confirmation body lists files + R2 note, cancel does nothing, Windows policy second step), l10n vi/en parity.
7. **Build** — `apps/desktop/macos/scripts/build_shellx_term.sh` + Xcode Run Script phase (Debug: host arch; Release: universal via `lipo`; ad-hoc/Xcode identity signature), Windows CMake custom target (`cargo build --release`, `+crt-static`) installed next to `ShellX.exe`.
8. **Release** — `sign-app.sh` signs `Contents/Helpers/*` before the app (+ node test), `release-desktop.yml` (Rust targets, check helper present, Authenticode check incl. `shellx-term.exe`), `shellx.iss` `[UninstallRun]` cleanup, `windows-check.yml` desktop job (`flutter test test/terminal_sharing`, `flutter build windows`, check `shellx-term.exe`), docs (ledger, HANDOFF, release README).
9. **Gates + local `flutter build macos --debug`** — `ls` of `Contents/Helpers`.

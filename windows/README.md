# ShellX for Windows (native MVP)

A native Windows terminal for ShellX: GPUI window (Direct3D 11 + DirectWrite), libghostty-vt
grid, ConPTY local shells, and remote terminals on your Macs over relay v2. Version 2.0.0
(sprint build, unsigned). Dark theme only; UI text is Vietnamese by default.

It is a separate app from the Flutter ShellX for Windows and installs next to it.

## Crates

| Crate | What it is | Where it builds / tests |
|---|---|---|
| `shellx-model` | Pure Rust: palette, strings, key mapping, paste encoding, split tree, tabs, sidebar, pairing/connection state machine, update rule, `shellx-core` envelope | `cargo test -p shellx-model` on any OS |
| `shellx-remote` | GPUI-free client for the cmux-tui remote protocol over `cmux-relay`; relay e2e tests are `#[ignore]`d and Unix-only | unit tests on any OS; e2e on Linux CI (`remote-e2e`) |
| `shellx-app` | The `shellx-desktop.exe` window, ConPTY, TermCore | Windows only (`windows-2025` CI). Do not build it on macOS or Linux; there only the headless `--smoke*` paths and some unit tests run |

CI is `.github/workflows/shellx-windows.yml` (jobs `model`, `remote-e2e`, `app`, `installer`).

## Get the build

Builds come from GitHub Actions only. Run ids are listed in one place: the checklist,
`G1-G3-CHECKLIST.md`, section "Run id" (the controller refreshes it).

```
gh run download <run-id> -R lephus/shellx -n shellx-desktop            # shellx-desktop.exe (portable)
gh run download <run-id> -R lephus/shellx -n ShellX-Setup-2.0.0-sprint # ShellX-Setup-2.0.0-sprint.exe
```

The installer is unsigned and per-user (no UAC). SmartScreen shows "Unknown publisher":
choose "More info", then "Run anyway". Installs to `%LOCALAPPDATA%\Programs\ShellX Native`,
Start menu entry "ShellX 2 (thử nghiệm)". Needs Windows 10 1809 (build 17763) or later.

## Command line

| Flag | Effect |
|---|---|
| (none) | Opens the window |
| `--version` | Prints `shellx-desktop <version>` and exits |
| `--smoke` | Headless run (no window): asset checks, then a ConPTY + libghostty-vt session, panes, core/remote/pairing/account flows with fakes; exit 0 on success |
| `--smoke-ui-assets` | Checks only the embedded icons and shell strings; exit 0 on success |
| `--smoke-panes` | Runs only the tabs/splits checks of `--smoke` |

Environment variables:

| Variable | Effect |
|---|---|
| `SHELLX_LANG=en` | English UI strings (any value starting with `en`); anything else or unset is Vietnamese |
| `SHELLX_SHELL` | Program to start in new local panes instead of `powershell.exe -NoLogo` (no arguments) |
| `SHELLX_API_BASE` | API base URL for `config.set`; honored in debug builds only. Release builds always use `https://relay.shellx.pro` |

## State directories

All state is under `%LOCALAPPDATA%\ShellX\native\`:

- `core\` : shellx-core state (device key, session)
- `remote\` : remote client identity, `links.json` (paired Macs), invite/ticket files

These never overlap the Flutter app's data: `%APPDATA%\pro.shellx\ShellX` and
`%LOCALAPPDATA%\ShellX\{bin,term,restore,cli,mux}`, which the Flutter uninstaller deletes.
Uninstalling ShellX 2 removes the program; the `native\` state is kept.

## Keyboard shortcuts

Terminal keys follow Windows Terminal; plain `Ctrl+C` / `Ctrl+V` go to the shell.

| Shortcut | Action |
|---|---|
| `Ctrl+Shift+C` | Copy selection |
| `Ctrl+C` | Copy only while a selection exists; otherwise interrupt (sent to the shell) |
| `Ctrl+Shift+V`, `Shift+Insert` | Paste |
| `Ctrl+Shift+T` | New tab |
| `Ctrl+Shift+W` | Close pane (last pane of last tab opens a fresh local tab) |
| `Ctrl+Tab`, `Ctrl+PageDown` | Next tab |
| `Ctrl+Shift+Tab`, `Ctrl+PageUp` | Previous tab |
| `Alt+Shift+=` (`+`) | Split right |
| `Alt+Shift+-` | Split down |
| `Alt+Arrows` | Focus pane left / right / up / down |
| `Ctrl+Shift+B` | Toggle sidebar |
| `Ctrl+,` | Settings (close with `Esc`) |

Source of truth: `shellx-model/src/keys.rs`. Keys are ignored while an IME is composing
and while the Windows key is held. `Ctrl+Alt` combinations are treated as AltGr text.

## Coexistence with the Flutter ShellX

Different AppId, executable (`shellx-desktop.exe`, never `ShellX.exe`, because the Flutter
installer runs `taskkill /IM ShellX.exe`), install directory (`ShellX Native`), Start-menu
name ("ShellX 2 (thử nghiệm)") and data directories. Installing or uninstalling one never
stops or removes the other. CI checks this statically
(`installer/check_coexistence.py`) and with an install/run/uninstall smoke.

## Accessibility stopgap

GPUI 0.2.2 exposes no UI Automation tree, so Narrator and other screen readers cannot read
the terminal grid or the controls. This is a known gap (expected to fail gate G1) and the
real fix, a UIA provider, is a post-sprint item.

Stopgap in this build: the focused pane writes the window title as
`<cursor line, else terminal title> - ShellX` (just `ShellX` when both are empty), so
Narrator reads the current line with `Insert+T`. Only the focused pane writes it. No other
accessibility features exist yet. For screen-reader-heavy work use Windows Terminal until
UIA lands.

## Latency procedure (gate G1)

Compare against Windows Terminal on the same PC with [Typometer](https://pavelfatin.com/typometer/):

1. Same machine, same power plan, same monitor and scaling; close other heavy apps.
2. Same font and size in both terminals (JetBrains Mono, same pt), same window size.
3. Open PowerShell in each; focus the terminal; point Typometer at it.
4. Run 5 measurement runs per terminal, alternating. Keep each run's numbers.
5. Record median and p95 key-to-pixel latency per terminal, and the ratio ShellX / Windows Terminal.

Report the table in the G1 notes (see `G1-G3-CHECKLIST.md`).

## Licenses and credits

- ShellX code (`shellx-*` crates): GPL-3.0-or-later.
- cmux-tui crates (`cmux-pty`, `cmux-terminal-client`, `cmux-remote`, relay): used as path
  dependencies from this repository under their own licenses.
- Icons: coolicons by Kryston Schwarze, CC BY 4.0.
- Fonts: JetBrains Mono and Space Grotesk, SIL OFL 1.1 (texts in `shellx-app/assets/fonts`).
- GPUI: Apache-2.0 (adapted example code carries a header naming its origin).
- libghostty-vt: from the Ghostty submodule.

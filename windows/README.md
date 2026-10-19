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

CI is `.github/workflows/shellx-windows.yml` (jobs `model`, `remote-e2e`, `app`, `installer`). The `app` job builds
`shellx-desktop`, runs the `shellx-model`, `shellx-remote` and `shellx-app` unit tests (step `Test shellx-app`), then the
headless `--smoke` and `--version`.

## Get the build

Builds come from GitHub Actions only. Run ids are listed in one place: the checklist,
`G1-G3-CHECKLIST.md`, section "Run id" (the controller refreshes it). Artifacts are kept
for 14 days; after that, re-run the workflow for the branch.

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
| `--smoke` | Headless run (no window): asset checks, then core, account, pairing, remote-session and remote-tab flows with fakes, input paths, and a ConPTY + libghostty-vt session; exit 0 on success. The ConPTY part needs Windows; on other OSes it fails after the fake-backed steps |
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

- `core\` : shellx-core state (device key, session); `core\tickets\invite-*.uri` holds a pairing invite
  and is deleted after the first enrolled connect to that Mac
- `remote\` : remote client identity and `links.json` (paired Macs)

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
| `Ctrl+,` | Settings |

While any panel is open (settings, pairing, sign-in, machine picker, forced-update overlay),
app shortcuts are swallowed and `Esc` closes the topmost panel (not the forced-update overlay);
the terminal gets the keyboard back when the last panel closes.

Source of truth: `shellx-model/src/keys.rs`. Keys are ignored while an IME is composing
and while the Windows key is held. `Ctrl+Alt` combinations are treated as AltGr text.

## Remote view (Macs)

Sign in (Settings or the sidebar), then request access to a Mac (sidebar "+", pairing code
shown on both machines, approve on the Mac).

- "Mở" on a granted Mac in the sidebar, or "Mở" in the pairing panel after approval, opens that
  Mac's terminal in a new tab. A second "Mở" opens a new shell on the Mac. Splitting a remote pane
  creates a shell on the Mac; `Ctrl+Shift+T` always opens a local tab.
- Typed and IME-committed text leaves as one UTF-8 write of the committed text.
- A pill over the pane shows the state: "đang kết nối…", "đang kết nối lại…" (with the reason),
  "ngoại tuyến", "Phiên ở xa đã kết thúc", "Khóa của máy không khớp, không kết nối", "Cần xin quyền
  truy cập lại". `SHELLX_LANG=en` shows the English table.
- While the pane is not connected, input is refused and nothing is queued: a short flash
  "Mất kết nối, tạm ngừng nhập" appears. Reconnect uses a freshly minted ticket.
- Exiting a remote shell closes only that pane. Signing out closes every remote tab.
- A shell that exits right after it starts (for example a wrong `SHELLX_SHELL`) is respawned at
  most 5 times in 10 s; then the pane shows "Shell thoát ngay khi khởi động. Kiểm tra
  SHELLX_SHELL." and waits for "Thử lại" or any key.

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

Stopgap in this build: the focused pane (local or remote) writes the window title as
`<cursor line, else terminal title> - ShellX` (just `ShellX` when both are empty). Narrator
is expected NOT to read the terminal grid; at most it reads the window title (`Insert+T`).
Only the focused pane writes the title. No other accessibility features exist yet. For
screen-reader-heavy work use Windows Terminal until UIA lands.

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
- cmux-tui crates used as path dependencies (`cmux-pty`, `ghostty-vt`, `cmux-remote`,
  `cmux-remote-protocol`; relay and daemon only in tests): `cmux-tui/Cargo.toml` declares
  `license = "MIT"` for its workspace; the repository root `LICENSE` states
  GPL-3.0-or-later for cmux material unless a file or notice says otherwise (BUSL-1.1 only in
  the directories it lists, none of which ShellX uses).
- Icons: coolicons by Kryston Schwarze, CC BY 4.0.
- Fonts: JetBrains Mono and Space Grotesk, SIL OFL 1.1 (texts in `shellx-app/assets/fonts`).
- GPUI: Apache-2.0 (adapted example code carries a header naming its origin).
- libghostty-vt: from the Ghostty submodule.

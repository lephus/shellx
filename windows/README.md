# ShellX for Windows (native MVP)

A native Windows terminal for ShellX: GPUI window (Direct3D 11 + DirectWrite), libghostty-vt
grid, ConPTY local shells, and remote terminals on your Macs over relay v2. Version 1.7.0
(unsigned). Dark theme only; the UI language follows the Windows display language
(Vietnamese on a Vietnamese Windows, English otherwise; `SHELLX_LANG` overrides it, see
[Command line](#command-line)).

It is a separate app from the Flutter ShellX for Windows and installs next to it.

## Crates

| Crate | What it is | Where it builds / tests |
|---|---|---|
| `shellx-model` | Pure Rust: palette, strings, key mapping, paste encoding, split tree, tabs, sidebar, pairing/connection state machine, update rule, `shellx-core` envelope | `cargo test -p shellx-model` on any OS |
| `shellx-remote` | GPUI-free client for the cmux-tui remote protocol over `cmux-relay`; relay e2e tests are `#[ignore]`d and Unix-only | unit tests on any OS; e2e on Linux CI (`remote-e2e`) |
| `shellx-app` | The `shellx-desktop.exe` window, ConPTY, TermCore | Windows only (`windows-2025` CI). On macOS it builds for development screenshots only ([see below](#run-the-window-on-a-mac-development-only)); on Linux only the headless `--smoke*` paths and some unit tests run |

CI is `.github/workflows/shellx-windows.yml` (jobs `model`, `remote-e2e`, `app`, `installer`). The `app` job builds
`shellx-desktop`, runs the `shellx-model`, `shellx-remote` and `shellx-app` unit tests (step `Test shellx-app`), then the
headless `--smoke` and `--version`. GitHub Actions has been unavailable since 2026-10-28, so in practice the installer
comes from the cross build on the VPS (see [Building a test installer](#building-a-test-installer)) and nothing
runs the Windows exe automatically: a person runs [the hands-on checklist](WINDOWS-TEST-CHECKLIST.md) on a PC.

## Get the build

Release installers are on the download page (`https://shellx.pro/#download`), with the SHA-256 of the
installer next to the link once the release has one. A test installer comes from
[the cross build](#building-a-test-installer). While GitHub Actions is available, a workflow run also
uploads artifacts (kept for 14 days; the run ids are in `G1-G3-CHECKLIST.md`, section "Run id"):

```
gh run download <run-id> -R lephus/shellx -n shellx-desktop            # shellx-desktop.exe (portable)
gh run download <run-id> -R lephus/shellx -n ShellX-Setup-1.7.0 # ShellX-Setup-1.7.0.exe
```

The installer is unsigned and per-user (no UAC):

- SmartScreen shows "Windows protected your PC" with "Unknown publisher": choose "More info", then
  "Run anyway".
- Smart App Control (Windows 11 in "On" mode) blocks an unsigned installer outright and offers no
  "Run anyway". It cannot be bypassed while the installer is unsigned. The only way past it is to
  turn Smart App Control off in Windows Security › App & browser control, which is your decision about
  your PC, not something ShellX asks for; signing the installer (not done yet) is the real fix.
- Installs to `%LOCALAPPDATA%\Programs\ShellX Native`, with two Start menu entries: "ShellX" and
  "ShellX – Chẩn đoán" ("ShellX – Diagnostics" in an English setup; see [Support](#support)).
- The installer names the running ShellX and asks to close it before it updates or uninstalls it
  (`AppMutex`); ShellX itself still opens as many windows as you like.
- The exe carries version information (File description ShellX, product ShellX, version
  `1.7.0.0`), visible in Properties › Details; Explorer does not show the company, so use
  `(Get-Item "$env:LOCALAPPDATA\Programs\ShellX Native\shellx-desktop.exe").VersionInfo | Format-List *` in
  PowerShell to see every field.
- Needs Windows 10 1809 (build 17763) or later.

## Run the window on a Mac (development only)

The GPUI window also builds on macOS so the UI can be checked with screenshots without a
Windows PC. This is not a product: nothing ships from it, and it opens `/bin/bash` (with the
same OSC 7 prompt hook, so the workspace cards show the directory and branch) instead of
PowerShell. From `windows/`:

```
cargo build --release -p shellx-app
dev/mac-shot.sh /tmp/shellx.png        # optional second argument: seconds to wait (default 6)
```

`dev/mac-shot.sh` starts `target/release/shellx-desktop` with your environment (for example
`SHELLX_LANG=en`), waits, saves a PNG of its window with `screencapture`, and stops it. It
exits non-zero if no window appeared. The first release build takes about 5 minutes.

- Never run a debug build of the window: it crashes at startup (a `hashbrown` debug assertion
  inside `serde_json`; gpui turns on `serde_json`'s `preserve_order` once it is in the build).
  For the same reason `cargo test -p shellx-app` (debug) fails 11 tests on a Mac and one run
  can hang; use `cargo test --release -p shellx-app` there. `cargo test -p shellx-model` is fine.
- The build needs the `ghostty` submodule (the libghostty-vt path dependency); in a git
  worktree, link or init it first.
- The window title bar leaves room for the traffic-light buttons instead of drawing the
  Windows caption buttons.
- State goes to `~/.local/share/shellx-native` (created with mode 0700, which shellx-core
  requires).
- `SHELLX_DEV_BACKGROUND=1` (Mac development build only) opens the window unfocused and without
  activating the app, so a check run does not steal the keyboard. Start the built binary with a scratch
  `HOME` as well, so it never shares state with another run.
- `SHELLX_DEV_PREVIEW=paste|settings` (development only) puts a pending 3-line paste in each new pane
  (`paste`), or opens Settings at start (`settings`), so the multi-line paste bar and the Settings
  panels can be drawn without a person clicking.
- `SHELLX_DEV_SIGN_IN=start|google|code|invalid|switch|expired` (Mac development build only)
  opens the sign-in dialog on that screen for screenshots, with a made-up address and no network
  call: `start` as this build has it (no Google: a Mac build has no Google client), `google` the
  same with the Google button, `code` the code step for you@example.com, `invalid` an address
  with a Vietnamese letter, `switch` the first screen after a 409. `expired` opens no dialog: it
  shows the sidebar's "Sign in again" notice after a server sign-out. With a stored session the
  dialog closes at once, so move `~/.local/share/shellx-native/core/session.json` aside first.

## Command line

| Flag | Effect |
|---|---|
| (none) | Opens the window |
| `--version` | Prints `shellx-desktop <version>` and exits |
| `--smoke` | Headless run (no window): asset checks, then core, account, pairing, remote-session and remote-tab flows with fakes, input paths, and a ConPTY + libghostty-vt session; exit 0 on success. The ConPTY part needs Windows; on other OSes it fails after the fake-backed steps. It starts Windows PowerShell itself, whatever Settings › Terminal and `SHELLX_SHELL` say (it prints that they are not used), because its checks read PowerShell's prompt |
| `--smoke-ui-assets` | Checks only the embedded icons and shell strings; exit 0 on success |
| `--smoke-panes` | Runs only the tabs/splits checks of `--smoke` |
| `--diagnose` | Writes a [diagnostics report](#the-diagnostics-report) into the logs folder, prints its path and opens the folder in Explorer. `--diagnose --no-open` opens nothing (for scripts and CI). Takes a few seconds, at most about 70 s |
| `--crash-test panic\|native\|window` | Developer switch for proving the crash handling on a real PC, see [Crash test](#crash-test). Does nothing unless passed |
| `--report-crash <file>`, `--report-window <file>` | Internal: the exe starts itself with these to show the error dialog from a separate process. Not for people |

`--version`, `--smoke`, `--smoke-ui-assets`, `--smoke-panes` and `--diagnose` print to the console
that started them. ShellX is a GUI-subsystem exe, so **cmd and PowerShell do not wait for it**: the prompt
comes back first, the output appears after it, and `%ERRORLEVEL%` / `$LASTEXITCODE` are not the exe's exit
code. Wait for it like this:

```
:: cmd
start /wait "" "%LOCALAPPDATA%\Programs\ShellX Native\shellx-desktop.exe" --version
"%LOCALAPPDATA%\Programs\ShellX Native\shellx-desktop.exe" --version | more

# PowerShell
& "$env:LOCALAPPDATA\Programs\ShellX Native\shellx-desktop.exe" --version | Out-Host
```

If the output is already redirected to a pipe or a file, ShellX uses that and attaches to nothing.

Environment variables:

| Variable | Effect |
|---|---|
| `SHELLX_LANG` | Overrides the UI language: a value starting with `en` is English, one starting with `vi` is Vietnamese. Anything else or unset follows the Windows display language (Vietnamese on a Vietnamese Windows, English otherwise, and English on a Mac) |
| `SHELLX_SHELL` | A command line to start in new local panes instead of the shell chosen in Settings › Terminal: a program with optional arguments, split by the Windows command-line rules (a path with spaces goes in double quotes, for example `"C:\Program Files\Git\bin\bash.exe" -i`). The program must be a full path or a name found on `PATH`; a relative path such as `.\pwsh.exe` is refused with a sentence, never run. The override gets no prompt hook, so sidebar cards show no directory or branch for it. A program that exists but cannot start makes the pane start the next shell once and say so ("… couldn't start, so … is running instead"); a line that cannot be read or found (an unclosed quote, a missing program) shows its sentence in the pane with "Thử lại" and "Mở Command Prompt" |
| `GPUI_DISABLE_DIRECT_COMPOSITION` | `1` starts ShellX in the [compatible display mode](#display-and-the-compatible-mode) for this run only (it is never remembered). Set it in cmd before starting the exe from there |
| `SHELLX_API_BASE` | API base URL for `config.set`; honored in debug builds only. Release builds always use `https://relay.shellx.pro` |
| `SHELLX_OFFER_ALL_MACS` | `1` offers "Request access" for every Mac in the account, also one the relay does not mark as able to host (`can_host`). Only for trying Part 2 with a test Mac build (design §4.5); never for a Windows PC. Read once at start |

## State directories

All state is under `%LOCALAPPDATA%\ShellX\native\`:

- `core\` : shellx-core state (device key, session); `core\tickets\invite-*.uri` holds a pairing invite
  and is deleted after the first enrolled connect to that Mac
- `remote\` : remote client identity and `links.json` (paired Macs)
- `logs\` : `shellx.log` (rotated at 1 MB, 3 files kept), crash files and diagnostics reports, see
  [Support](#support)
- `render.json` : the remembered display mode (`{"mode":"compatible"}` once the compatible mode has
  rescued a start); `starting.json` is a short-lived "ShellX is starting" marker that is removed once the
  first frame is drawn

These never overlap the Flutter app's data: `%APPDATA%\pro.shellx\ShellX` and
`%LOCALAPPDATA%\ShellX\{bin,term,restore,cli,mux}`, which the Flutter uninstaller deletes.
Uninstalling ShellX removes the program; the `native\` state is kept.

## Keyboard shortcuts

Terminal keys follow Windows Terminal; plain `Ctrl+C` / `Ctrl+V` go to the shell (and so
does every other plain `Ctrl+letter`, for example `Ctrl+N` and `Ctrl+T`).

A workspace is a card in the sidebar; a terminal tab is a tab in the tab bar of one split
region of a workspace.

| Shortcut | Action |
|---|---|
| `Ctrl+Shift+C` | Copy selection |
| `Ctrl+C` | Copy only while a selection exists; otherwise interrupt (sent to the shell) |
| `Ctrl+Shift+V`, `Shift+Insert` | Paste |
| `Ctrl+Shift+N` | New workspace (a local PowerShell) |
| `Ctrl+Shift+T` | New terminal tab in the focused region. In a region that shows a Mac terminal it opens another terminal on that Mac; otherwise a local PowerShell |
| `Ctrl+Shift+W` | Close the focused terminal (the last terminal of the last workspace is replaced by a fresh local one) |
| `Ctrl+Tab`, `Ctrl+PageDown` | Next workspace |
| `Ctrl+Shift+Tab`, `Ctrl+PageUp` | Previous workspace |
| `Alt+Shift+=` (`+`) | Split right |
| `Alt+Shift+-` | Split down |
| `Alt+Arrows` | Focus region left / right / up / down |
| `Ctrl+Shift+B` | Toggle sidebar |
| `Ctrl+,` | Settings |
| `Alt+F4`, `Alt+Space` | Not app shortcuts: Windows keeps them (close the window; the window's system menu), also while a terminal or the forced-update overlay has the keyboard |

The same actions are on screen: the title bar has the sidebar toggle, the "+ ▾" new-workspace
menu, Back / Forward (focus history across workspaces and regions) and the settings gear (there is
no search box and no bell: they come back when they work); each region has a tab bar
with a close box per tab and the New terminal / Split right / Split down buttons; the
sidebar footer has the `?` help menu (Settings…, Check for Updates, Create diagnostics report, Docs, GitHub), the
version and, when a newer version exists, the "Update Available" pill.

While any panel is open (settings, pairing, sign-in, forced-update overlay), app shortcuts are
swallowed and `Esc` closes the topmost panel (not the forced-update overlay); the terminal gets
the keyboard back when the last panel closes. A panel never opens by itself over a terminal you are
typing in: when the server ends the session, the sidebar footer shows "Phiên đăng nhập đã hết hạn."
with a "Đăng nhập lại" button (also in Settings › Account) and the dialog opens only when you press it.
The dropdowns (the "+ ▾" menu, the `?` help menu,
the machines "+" list) are not panels: they close on a click outside them, when a panel opens
or a shortcut runs, and on `Esc`, which then does not reach the shell.

### Mouse and paste

- **Right-click** pastes the clipboard; with a selection it copies the selection instead (like the
  Windows console). Middle-click only focuses.
- A first click (left, right or middle) on a pane that does not have the keyboard only moves the keyboard
  to that pane; it pastes and selects nothing. Click again to paste.
- Clicking while a dropdown menu is open closes the menu and does nothing else.
- **A paste of more than one line asks first** ("Dán 3 dòng? Mỗi dòng sẽ chạy ngay như một lệnh." /
  "Paste 3 lines? Each line will run as a command right away."): a bar inside the pane; Enter pastes, Esc
  cancels, any other key cancels and is typed as usual. A single line, with or without a trailing
  line break, pastes at once. This applies to `Ctrl+Shift+V`, `Shift+Insert` and right-click, in local
  and Mac panes.
- Touchpad scrolling accumulates fractions of a line, so a slow swipe moves a little. In a full-screen
  program (`less`, `vim`) that has not asked for the mouse, the wheel sends the arrow keys.

Source of truth: `shellx-model/src/keys.rs`. Keys are ignored while an IME is composing
and while the Windows key is held. `Ctrl+Alt` combinations are treated as AltGr text.

## Settings

`Ctrl+,` opens Settings. The sections that matter for support:

- **Terminal**: the shell new tabs start. "Tự động" / "Automatic" (the default) is PowerShell 7 when it is
  installed, otherwise Windows PowerShell, otherwise Command Prompt; the list also offers the other shells
  ShellX found (Git Bash, WSL) and a custom command line (a program and arguments, for example
  `wsl.exe -d Ubuntu`; the box says at once when the program cannot be found, and a path with spaces needs
  double quotes). The choice applies to terminals opened after it; open tabs are not touched. While
  `SHELLX_SHELL` is set, Settings says so and uses that value instead. The lookup runs in the
  background, so the list may show only Automatic and Custom for a moment after start.
- **Display** (under Terminal): "Chế độ hiển thị thường" / "Standard display mode" or "Chế độ hiển thị
  tương thích" / "Compatible display mode", see [Display and the compatible mode](#display-and-the-compatible-mode).
- **Account**: signed-in state, "Đăng nhập…" / "Đăng nhập lại" and sign-out (also available when the
  account state shows an error).
- **About**: `ShellX 1.7.0`, or `ShellX 1.7.0 (<label> <commit>)` on a test installer.

The help menu (`?` in the sidebar footer) lists Cài đặt…, Kiểm tra cập nhật, Tạo báo cáo chẩn đoán
(creates the [diagnostics report](#the-diagnostics-report), the window stays usable while it runs),
Tài liệu and GitHub.

## Remote view (Macs)

Sign in with an email code (Settings → Account → "Đăng nhập…", which opens the sign-in dialog; the "+" next
to "Máy của bạn" in the sidebar opens the same dialog while you are signed out): type your email address,
press "Gửi mã", then type the 6-digit code from the email. A first sign-in creates the account. "Tiếp tục
với Google" appears only in a build that has a Google app code. Then request access to a Mac (that "+"
again, pairing code shown on both machines, approve on the Mac). The request button is drawn only for a Mac
the relay marks as able to accept a PC (`can_host`); until a ShellX for Mac does that, the list says "ShellX
cho Mac hiện chưa nhận kết nối từ máy tính Windows" and local terminals work as usual. A Windows PC never gets
a request button.

- "Mở" on a granted Mac in the sidebar, or "Mở" in the pairing panel after approval, opens that
  Mac's terminal in a new workspace. A second "Mở" opens a new shell on the Mac. Splitting a
  remote pane creates a shell on the Mac, and so does `Ctrl+Shift+T` (or the tab bar's New
  terminal button) in a region that shows a Mac terminal. `Ctrl+Shift+N` and the title bar "+"
  always open a local workspace.
- Typed and IME-committed text leaves as one UTF-8 write of the committed text.
- A pill over the pane shows the state: "đang kết nối…", "đang kết nối lại…" (with the reason),
  "ngoại tuyến", "Phiên ở xa đã kết thúc", "Khóa của máy không khớp, không kết nối", "Cần xin quyền
  truy cập lại". `SHELLX_LANG=en` shows the English table.
- While the pane is not connected, input is refused and nothing is queued: a short flash
  "Mất kết nối, tạm ngừng nhập" appears. Reconnect uses a freshly minted ticket.
- Exiting a remote shell closes only that pane. Signing out closes every remote tab.
- A remote paste larger than 8 MB (after encoding) is refused whole with the flash "Nội dung
  dán quá lớn (tối đa 8 MB)"; it is never cut.
- A shell that exits right after it starts (for example a custom command line that quits at once) is
  respawned at most 5 times in 10 s; then the pane shows "Shell thoát ngay khi khởi động. Chọn shell khác
  trong Cài đặt › Terminal." and waits for "Thử lại" or any key. A shell that cannot start at all shows
  "Không khởi động được shell. Chọn shell khác trong Cài đặt › Terminal, hoặc mở Command Prompt." with
  "Thử lại" and "Mở Command Prompt".

## Support

When something does not work, the answer is a file, not a description. Start "ShellX – Chẩn đoán" from the
Start menu (see [the report](#the-diagnostics-report)) and send the file it opens in Explorer. For a test
installer, [the hands-on checklist](WINDOWS-TEST-CHECKLIST.md) says what to look at.

### Logs and crash files

Everything is in `%LOCALAPPDATA%\ShellX\native\logs`:

| File | What it is |
|---|---|
| `shellx.log` | The log of the app, GPUI (GPU name, feature level, device loss, font errors) and the core. First line of a start: `ShellX 1.7.0 starting on Windows 10.0.<build>` (`ShellX 1.7.0 (<label> <commit10>) starting on Windows …` on a test installer), then `render mode: …`, decided before GPUI starts, then GPUI's `Using GPU:` lines. Rotated at 1 MB, 3 files kept |
| `crash.<time>.<pid>.txt` | A panic: message, location, thread, backtrace, version, commit, Windows build. The last line `then: panic in a function that cannot unwind (the process aborts)` means the process was then ended by Windows (a panic inside a window procedure ends in a fast fail, exit code `0xC0000409`) |
| `crash-native.<time>.<pid>.txt` | A crash that is not a panic (for example `0xC0000005`, a bad memory access): exception code, address, module, thread. No minidump |
| `start-failed.<time>.<pid>.txt` | ShellX could not open its window and had no other display mode left to try |
| `diagnostics.<time>.<pid>.txt` | A [diagnostics report](#the-diagnostics-report) |

If the logs folder cannot be written, a crash file is written to the **temp folder** (`%TEMP%`) with the same
name, and the diagnostics report lists it as "(in the temp folder)". If `%LOCALAPPDATA%` itself is unusable,
the logs folder is `%TEMP%\ShellX\logs`. A test installer has a PDB next to its exe, see
[Building a test installer](#building-a-test-installer); it is never in the installer, so frames inside the
exe read `<unknown>` in a crash file until the addresses are mapped with it.

### The crash dialog

A panic or a crash writes its file first, then ShellX starts itself once more as a separate small process (no
GPUI) that shows a box: "ShellX gặp lỗi và đã lưu chi tiết vào: <file> … Mở thư mục chứa file này? Hãy gửi file cho
đội ShellX để được giúp." (English: "ShellX ran into a problem and saved the details to: …"), with Yes (opens
Explorer with the file selected) and No. If the window cannot open and no other display mode is left to try the box reads
"ShellX không mở được cửa sổ" / "ShellX couldn't open its window" and names the `start-failed` file. A start never
shows more than one box.

### The diagnostics report

Three ways to create it, all running `shellx-desktop.exe --diagnose` as a separate process, so the window stays
usable: the Start menu entry **"ShellX – Chẩn đoán"** ("ShellX – Diagnostics" in an English setup), the help menu
item **"Tạo báo cáo chẩn đoán"** (nothing shows for a few seconds and up to about 70 s: press it once), or the
command line (`--diagnose`, `--diagnose --no-open`). The result is `diagnostics.<time>.<pid>.txt` in the logs
folder, shown in Explorer. It is written twice under the same name, first with the quick sections and then
complete, so a hang or crash in the GPU probe still leaves a report.

It has 12 sections: `[app]` (version, commit, build kind), `[windows]` (Windows version and build), `[cpu]`
(CPU and instruction sets), `[displays]` (resolution, scale and work area of each screen, the window size
chosen), `[gpu]` (each adapter with driver and feature level, the one GPUI would use, the display mode in
use, the DWM timing that shows whether the machine is at risk of the vsync bug), `[keyboard]` (installed
layouts and input methods, whether Unikey or EVKey is running), `[shells]` (the shells found, the one a new tab
starts, and a start / first output / echo / Vietnamese text / resize check of it with timings), `[state]`
(whether the state folder is writable), `[account]` (signed in or not, and how), `[relay]` (whether the relay
answers, with the HTTP status and delay), `[crash files]` (the crash files, plus the last five Windows
"Application Error" events for `shellx-desktop.exe`, which show crashes ShellX's own handlers cannot see), and
the last 200 lines of the log.

**It never contains** a token or key, an email address, a one-time code, a challenge code, terminal content,
text you typed, or the names of your other machines. Every line written to the log, a crash file or the report
goes through a redactor (emails become `<email>`, long token-like runs `<token>`, a 6-digit number next to
"code" / "mã" `<code>`, Resend keys `<key>`), the account types do not print the email when formatted for
debugging, and the report runs the redactor once more over the log lines it copies. The redactor knows
nothing about a password written into a command line: do not put one in a custom shell line.

`--diagnose` starts the shell that new tabs start, exactly as a tab does, to check it. A custom command line that
opens an SSH connection (`ssh`, `plink`) therefore opens that connection for up to 10 s; nothing is typed into
it. `--smoke` is different: it always starts Windows PowerShell.

### Display and the compatible mode

ShellX normally draws with DirectComposition ("standard mode"). If the window cannot be opened, ShellX
starts itself again once with `GPUI_DISABLE_DIRECT_COMPOSITION=1` ("compatible mode") and writes that in the
log. If the last start died before its first frame, the next start is the compatible one itself (no second
process) and the log says `previous start died before its first frame`. When the compatible mode draws its first frame, the choice is
**remembered** in `%LOCALAPPDATA%\ShellX\native\render.json` for later starts. If no display mode is left to try the dialog
names `start-failed.*.txt`. A remembered compatible mode resets itself to standard after one start in which
the window could not be opened.

Settings › Display shows which mode this run uses, and why when it is the compatible one. "Thử lại chế độ hiển
thị thường" / "Try standard display mode again" writes `{"mode":"standard"}`; the sentence "Áp dụng khi mở lại
ShellX." / "Takes effect the next time ShellX opens." appears and the next start tries the standard mode again (if
that fails, ShellX falls back to the compatible mode as above). When the compatible mode is on only because
`GPUI_DISABLE_DIRECT_COMPOSITION` is set, Settings says so and has no button.

The log lines to look for: `render mode: standard (default)`, `render mode: compatible (the standard mode
could not open the window)`, `render mode: compatible (remembered)`, `render mode: compatible (set by
GPUI_DISABLE_DIRECT_COMPOSITION)`, then `first frame drawn in standard display mode` or `… compatible display
mode`. A start that finds another ShellX running ends the line with `another ShellX is running`.

### Crash test

`shellx-desktop.exe --crash-test panic|native|window` exists in every build and does nothing unless passed. It
lets a person prove the handling on a real PC. Run each from a new cmd, with `start /wait "" …` if the exit code
matters:

- `panic`: a panic on the UI thread. One dialog, one `crash.*.txt`, the process ends with `0xC0000409`. The next start is
  unchanged.
- `native`: a bad memory access (`0xC0000005`). One ShellX dialog, one `crash-native.*.txt` with exception, address
  and module. Windows may show its own dialog as well. The next start is unchanged.
- `window`: the standard mode "fails to open the window", so ShellX opens in the compatible mode and remembers
  it (`render.json`). **Run it last**, then go to Settings › Display and use "Thử lại chế độ hiển thị
  thường" (or delete `render.json`) before judging anything else on that PC. Run on a PC that is already
  remembered as compatible, it shows the "couldn't open its window" box and resets to standard.

### Support lines

1. **A window is blank while the log says `first frame drawn`.** ShellX cannot see that. Quit it, open cmd and run
   `set GPUI_DISABLE_DIRECT_COMPOSITION=1`, then start `shellx-desktop.exe` from that same cmd. That is the
   compatible mode for this run only; it is never remembered.
2. **ShellX says it cannot open its window on every start.** Delete
   `%LOCALAPPDATA%\ShellX\native\render.json` (the remembered mode resets itself after one failure; this is the manual
   fallback), then start it again.
3. **`--diagnose` starts the chosen shell** as a new tab does, so a custom `ssh` / `plink` line connects for up to 10 s
   and nothing is typed into it. Choose another shell in Settings › Terminal first if that matters.
4. **`--version` shows nothing, or its output appears after the prompt**: see [Command line](#command-line)
   (`start /wait "" … --version`, or `… --version | more`; in PowerShell `… | Out-Host`).

### Building a test installer

A test installer is built from the committed `HEAD` of the checkout on a shared Linux build host (not from
uncommitted files), by cross-compiling in a container; there is no Windows machine and no GitHub Actions
involved. The host is yours to name; this document never contains one:

```
export SHELLX_VPS=<your ssh host>        # ssh destination of the build host
scripts/shellx/release/build-windows-cross.sh --preflight
SHELLX_BUILD_LABEL=test scripts/shellx/release/build-windows-cross.sh <output folder>
```

- `--preflight` is read-only: it checks that the host has enough free disk (default 14 GiB,
  `SHELLX_WINBUILD_MIN_FREE_GIB`) and that no other Windows build holds the lock or runs. Exit 0 means a
  build may start.
- `SHELLX_BUILD_LABEL` is a lower-case letter followed by up to nine lower-case letters or digits. The installer is then
  `ShellX-Setup-<version>-<label>-<commit10>.exe`; About and the report show
  `ShellX 1.7.0 (<label> <commit10>)`. The version inside the exe and the installer stays `1.7.0`. Without a
  label the name is `ShellX-Setup-<version>.exe`. `SHELLX_VPS_SSH_OPTS` and `SHELLX_WINBUILD_DIR` are the
  other variables; the header of the script lists them.
- The output folder gets the installer, its `.sha256`, `SHA256SUMS.remote`, and a folder
  `ShellX-Setup-<version>-<label>-<commit10>-symbols` that holds `shellx-desktop.exe` and `shellx_desktop.pdb`
  of the same build, for mapping a crash file's addresses. **The PDB is never in the installer.**
- Pass signs: the filtered output has Inno Setup's `Successful compile`; the last line is
  `Built <output folder>/ShellX-Setup-<version>-<label>-<commit10>.exe (unsigned); exe and PDB in …-symbols`;
  no PDB warning (the texts are `warning: no intact shellx_desktop.pdb from this build; …`, `warning: the exe for the symbols folder did not download intact …`, and the container's `warning: no …pdb; …`); and no lock is left (`--preflight` afterwards says
  `no Windows build running`). If a run was cut off (lost connection) and the next run refuses because of a held
  lock, `scripts/shellx/release/build-windows-cross.sh --unlock` prints the owner and removes the lock; it
  refuses while a build container runs or the owner is a live process on this Mac.
- The tests of the Windows target and the `--smoke` / `--version` runs do **not** run in this build: try the
  installer on a Windows PC with [the checklist](WINDOWS-TEST-CHECKLIST.md).
- A test installer uses the same app id as the release, so it installs over an existing ShellX; that is intended.
  It is not uploaded to the download page and does not move the update pointer.
- `scripts/shellx/check-windows-build.sh` is the quicker compile-only check of the committed `HEAD` for the
  Windows target (no installer).

## Known limitations

- `Ctrl+Shift+W` on a remote pane only detaches: the shell keeps running on the Mac. Every
  second "Mở" and every remote split creates a new workspace on the Mac (close them there).
- Input typed during the first ~30 s of a relay hiccup may arrive late: while the client
  library recovers the relay link by itself the pane still shows as connected and the
  typed bytes are sent once the link is back (a buffered command may run late). Only after
  that does the pane show "đang kết nối lại…" and refuse input.

## Coexistence with the Flutter ShellX

Different AppId, executable (`shellx-desktop.exe`, never `ShellX.exe`, because the Flutter
installer runs `taskkill /IM ShellX.exe`), install directory (`ShellX Native`) and data
directories. Installing or uninstalling one never stops or removes the other. Since 1.2.0 the
display name and the Start-menu shortcut are "ShellX", like the Flutter app's: the native app
replaces it, so its shortcut takes over the Flutter one, and uninstalling the Flutter app
afterwards removes that shortcut (reinstalling ShellX restores it). CI checks this statically
(`installer/check_coexistence.py`) and with an install/run/uninstall smoke.

## Accessibility stopgap

GPUI 0.2.2 exposes no UI Automation tree, so Narrator and other screen readers cannot read
the terminal grid or the controls. This is a known gap (expected to fail gate G1) and the
real fix, a UIA provider, is a post-sprint item.

The window title never carries screen text by default (it is visible in the taskbar,
Alt+Tab, `GetWindowText` and screen sharing): it is `<terminal title> - ShellX`, or just
`ShellX` when the shell set no title (the terminal title is cut to 80 characters, control
characters removed).

Stopgap in this build, screen-reader mode only: while a screen reader is running
(`SPI_GETSCREENREADER`, which Narrator itself turns on; checked at most once per second) or
when `SHELLX_A11Y_TITLE=1` is set, the focused pane (local or remote) writes its cursor line
instead: `<cursor line, else terminal title> - ShellX`. Narrator is expected NOT to read the
terminal grid; at most it reads the window title (`Insert+T`). Only the focused pane writes
the title. No other accessibility features exist yet. For screen-reader-heavy work use
Windows Terminal until UIA lands.

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

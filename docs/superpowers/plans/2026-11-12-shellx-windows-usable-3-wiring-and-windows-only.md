# ShellX for Windows, Usable: Part 3 Wiring and Windows-Only Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the foundations' rules into the Windows window (first window, scrolling, clicks, keys, paste, shells, Settings › Terminal, git off the UI thread, honest pairing errors) and add what only Windows needs (log, crash files, crash reporter, diagnostics, console flags, compatible display mode, installer mutex, version info, installer entries) plus the three remaining GPUI patches (a), (b), (c).

**Architecture:** Two parts on two branches with disjoint files. Part A (wiring) changes views and GPUI-free app modules whose tests run on this Mac. Part B (Windows-only) owns start-up (`main.rs`, `ui/app.rs`, `shellx-app/Cargo.toml`), adds GPUI-free modules for the log, crashes, start-up and diagnostics (tested on this Mac), thin `cfg(windows)` Win32 shells that `scripts/shellx/check-windows-build.sh` compiles, and three one-file GPUI patches. Every decision is a pure function in `shellx-model` or in a platform-neutral app module; Win32 code holds no decision.

**Tech Stack:** Rust 2024 (toolchain 1.95.0, MSRV 1.91), GPUI 0.2.2 vendored at `windows/vendor/gpui-0.2.2`, windows-sys 0.61.2 (direct), windows 0.61.3 and log 0.4.34 (made direct here; both already in `windows/Cargo.lock`), winreg 0.55, portable-pty through `cmux-pty`, libghostty-vt, Inno Setup 6.7.1, the local Docker compile check.

**Spec:** `docs/superpowers/specs/2026-11-12-shellx-windows-usable-design.md` (Vietnamese, binding): §6 group 3 except sign-in, and group 4. Evidence: `.superpowers/sdd/2026-11-11-windows-usable/review-1-install-launch-render.md` (R1), `review-2-input.md` (R2), `review-3-local-terminal.md` (R3), `part-l-a-review.md` finding M3. Consumed: the foundations plan `docs/superpowers/plans/2026-11-12-shellx-windows-usable-1-foundations.md` ("Interfaces for the later plans"). Lands after: `docs/superpowers/plans/2026-11-11-shellx-email-code-signin-windows.md` (the sign-in plan). Part B's exact patch texts, the crash filter and the diagnostics probes: `docs/superpowers/plans/2026-11-12-shellx-windows-usable-3b-windows-only-details.md` (called "3b" below).

## Coordinator's amendments (2026-11-12; these win over the text below)

1. **Base.** The foundations work is on `develop` (`00e7560fa7`), and so is the Mac development switch `SHELLX_DEV_BACKGROUND` (`157efb7222`). Both parts branch from `develop`.
2. **RUNCHECK** is the amended form under Commands: scratch home plus `SHELLX_DEV_BACKGROUND=1`, for every start of the built binary on this Mac.
3. **WINCHECK has two modes.** `scripts/shellx/check-windows-build.sh` (dev profile) after every task, as written. A task that adds or changes code under `cfg(windows)`, `build.rs`, `Cargo.toml` or the vendored GPUI also runs `scripts/shellx/check-windows-build.sh --release` on its final commit (release-only Windows code, type-check only, with a stand-in shader compiler) and expects `Checked <commit> for Windows (x86_64-pc-windows-msvc, release profile): OK`.
4. **The VPS build script changed on `develop`** (an owned lock, `--unlock`, `--preflight`, option checking): B10's edits to `scripts/shellx/release/build-windows-cross.sh` start from that version. No task runs it: the cross build is run by the user.
5. **Execution in chunks, each reviewed and landed before the next that needs it:** A-1 = A1, A3, A4, A8 (from `develop` now). B-1 = B1 to B8 (from `develop`, after the plan review of Part B). Then the sign-in plan lands. A-2 = A2, A5, A6, A7, A9. B-2 = B9, B10 (needs A-1 on `develop`). Last: A10 (needs B-1 and B-2 on `develop`).
6. **A plan review of Part B and 3b** (the three GPUI patches, the crash filter, the Win32 calls) runs before B-1 starts; its corrections are folded into this file and 3b and marked "(plan review)".

## Global Constraints

- Rules are pure functions in `shellx-model` (or GPUI-free app modules) with tests that run on this Mac; views and Win32 code only wire (spec §4 "Nguyên tắc chung").
- No crate outside `windows/Cargo.lock`. Only two new direct dependencies: `log = "0.4"` (B3) and `windows = "0.61"` (B9); each changes `windows/Cargo.lock` by exactly one line in the `shellx-app` entry (`+ "log",`, `+ "windows",`). windows-sys features never change the lock.
- gpui stays the vendored 0.2.2. Patches (a), (b), (c) touch one file each, one commit each, line 1 of the file is `// Modified by ShellX: <one-line reason>. See windows/vendor/README.md.`, each adds a row to `windows/vendor/README.md`, and `windows/vendor/check-gpui.sh` passes.
- Window builds on this Mac are release builds only (`--release`).
- The version inside the app stays `x.y.z` (`1.7.0`). A test label and commit appear only in the setup file name, Settings › About, the diagnostics report and crash files (spec §4.6).
- Never in a log line, crash file, start-failure file or report: an email address, a token, a sign-in code, a challenge id, a key, terminal content, typed text, another machine's name (spec §4.7). Every line written goes through `shellx_model::redact::redact`. The one exception, the native crash file, carries only numbers, the module path and the time.
- File names written to the logs folder join their parts with `.` (Ruling 13).
- Each new kind of written line has a test that plants an email, a 43-character token and `code 123456` and finds none of them: log records (B3 `every_record_is_redacted_before_it_is_written`, `records_are_one_line_per_text_line_and_redacted`), count lines (B3 `repeat_lines_carry_no_message_text`), panic crash files (B4 `panic_report_is_redacted_line_by_line`), start-failure files (B4 `the_start_failure_file_is_redacted`), the report's new values (foundations `report_redacts_planted_secrets_everywhere`, B9 `the_report_names_only_the_sign_in_method`). The native crash file takes only numbers, a module path and the time by construction (B5 `native_report_formats_codes_addresses_module_and_time`). No line names another machine: nothing this plan writes reads the machine list.
- No new silent exit: a console mode prints why; the GUI leaves a file and shows the reporter's dialog.
- No panic inside the panic hook; no allocation inside the unhandled-exception filter.
- New user-facing sentences come in Vietnamese and English with the exact text this plan gives. Part A adds them to `windows/shellx-model/src/strings.rs` the foundations way (`Str` variant, `Str::ALL`, both `t` arms, `all_has_no_duplicates` = the count on the branch before the task plus the task's additions). Part B's few sentences live in `windows/shellx-model/src/crash_report.rs` (Ruling 1).
- `SHELLX_DEV_PREVIEW` (Mac preview switch) is compiled only under `cfg(target_os = "macos")`.
- UI tasks are proved by model tests, the Mac release build, the Mac run check (Commands) and the reviewer's reading; never by a screenshot.
- Failing test first, commit it, then the fix (CLAUDE.md), wherever a test can exist. A GPUI patch has no test here; its "red" is the unpatched line found by `grep`.
- A Windows-only task ends with: Mac release build and `shellx-app` tests green, commit, then `scripts/shellx/check-windows-build.sh` prints `Checked <commit> for Windows (x86_64-pc-windows-msvc): OK` for that commit.
- No push, no merge to `main`, no deploy, release, signing, VPS run or GitHub Actions dependency. The coordinator merges branches into `develop`.

## Review Focus

Inputs a person on a real PC will meet that no main test exercises; each has a test in its owning task.

1. **Text copied from Notepad or a browser:** CRLF line ends, one line with a trailing newline, several lines with blank lines at the end. One line pastes at once; two or more ask once and paste exactly what was copied. Tests: A5 `paste_line_count_counts_what_the_shell_will_run`, `confirm_keys_paste_cancel_or_pass`; foundations `multi_line_means_text_after_a_newline`.
2. **PowerShell 7 from the Microsoft Store and a PATH with an offline network folder:** the Store alias in `%LOCALAPPDATA%\Microsoft\WindowsApps` is found and the window never freezes while shells are looked up. Tests: A1 `program_files_are_files_folders_are_not_links_are_followed`, `the_first_pane_waits_at_most_the_bound_then_starts_windows_powershell`. The alias itself only on the PC: the diagnostics report lists the shells found.
3. **A user folder with Vietnamese letters and spaces** (`C:\Users\Phú Lê`): the log, crash files, `settings.json`, the reporter's command line and `explorer /select` work. Tests: B4 `reporter_command_line_quotes_paths_with_spaces_and_vietnamese`, B3 `the_log_works_in_a_folder_with_vietnamese_and_spaces`, A1 `the_stored_choice_round_trips_and_keeps_other_keys` (run in such a folder).
4. **A GPU error on every frame** (device removed, failed resize; up to 60 lines a second): the three log files must keep what came before it. Tests: B3 `repeats_collapse_into_one_count_line`, `the_logger_rotates_at_one_mebibyte_and_keeps_three_files`.
5. **Two starts close together, or a start right after a crash or a relaunch:** no start switches another's display mode, a stale marker never forces compatible mode by mistake, and a relaunch happens at most once. Tests: B6 `another_instance_leaves_the_marker_alone`, `a_retry_writes_its_own_marker_and_never_relaunches`, `open_failure_relaunches_once_then_reports`.

---

## Parts, ownership, order

| Path | Owner | Notes |
| --- | --- | --- |
| `windows/shellx-app/src/main.rs`, `src/ui/app.rs`, `windows/shellx-app/Cargo.toml`, `build.rs`, `resources/shellx.rc`, `src/os_info.rs`, `src/paths.rs`, `src/smoke.rs`, `windows/Cargo.lock` | B | Shared files given to B. |
| New in shellx-app: `logger.rs`, `crash.rs`, `crash_native.rs`, `build_info.rs`, `startup.rs`, `console.rs`, `diagnose_run.rs`, `exe_resource.rs` | B | Declared in `main.rs` (B). |
| `windows/shellx-model/src/lib.rs`; new model modules `log_file.rs`, `crash_report.rs`, `start_guard.rs`; edits to `diagnose.rs` | B | |
| `src/links_store.rs`, `src/remote_session.rs`, `src/pairing_service.rs` (one `eprintln!` each → `log::`, and `expect_caught` around the pairing job) | B | |
| `windows/vendor/**`, `windows/installer/**`, `windows/cross/build-in-container.sh`, `scripts/shellx/release/build-windows-cross.sh`, `.github/workflows/shellx-windows.yml` | B | |
| `windows/shellx-model/src/strings.rs`, `paste.rs`, `shell.rs` | A | `strings.rs` is also the sign-in plan's. |
| `src/local_pty.rs`, new `src/local_pty/settings.rs`, `src/workspace.rs`, `src/cwd.rs`, `src/term_core.rs` | A | `local_pty/settings.rs` is a child of `local_pty.rs`, so A never edits `main.rs`. |
| `src/ui/term_view.rs`, `ui/panes.rs`, `ui/titlebar.rs`, `ui/update_banner.rs`, `ui/pairing.rs` | A | |
| `src/ui/settings.rs` | A | Sign-in plan regions: `account_section`, `methods_block`, the method row title. A's: new `terminal_section`, `display_section`, `about_section`, `new`, `open`, `render` body, struct fields. |
| `src/ui/root.rs` | A | Sign-in plan regions: `account_changed`, the end of `new`, fields, the `build_groups` call and the picker. A's: `card_lines` only. |
| `src/ui/sidebar.rs` | A | Sign-in plan regions: `render`'s notice block, `PickerEntry`, `machine_picker`. A's: `help_menu` only. |
| `src/ui/text_field.rs` | A | Sign-in plan adds `composing()`/`dev_set_text` after `set_disabled`; A adds `set_text` after `clear`. |

**Order.** The sign-in plan lands on `develop` first. A2, A5, A6, A7, A9 and A10 edit files the sign-in plan also edits (`strings.rs`, `settings.rs`, `text_field.rs`, `root.rs`, `sidebar.rs`): the first of them starts with `git merge --no-edit develop` once the sign-in branch is there (resolve `Str` additions by keeping both lists and summing the count). A1, A3, A4 and A8 can run before it. Cross-part seams: B9 needs A1 (shell snapshot); A10 needs B3, B4, B6 and B9. The coordinator lands the producing task (or names its reviewed commit to merge) before the consuming task starts.

**Seams between the parts** (exact signatures; the producing task's Interfaces block is the source):

```rust
// A1 → B9 (and smoke)
// windows/shellx-app/src/local_pty.rs
pub struct ShellCmd { pub program: String, pub args: Vec<String>, pub env: Vec<(String, String)>,
                      pub label: String, pub kind: Option<ShellKind> }
pub struct PanePlan { pub first: ShellCmd, pub fallback: Option<ShellCmd> }
pub fn default_shell() -> ShellCmd;                                   // what a new tab starts first
// windows/shellx-app/src/local_pty/settings.rs
pub fn shells() -> &'static Shells;
pub struct ShellSnapshot { pub choice: ShellChoice, pub env_override: Option<String>, pub found: Vec<ShellLaunch>,
                           pub plan: Option<Result<LaunchPlan, ShellError>> }   // plan None until the first probe ends
impl Shells { pub fn snapshot(&self) -> ShellSnapshot; pub fn refresh_now(&self) -> ShellSnapshot /* blocking */; }

// B3, B4, B6, B9 → A10
// log 0.4 is a direct dependency of shellx-app (B3)
// windows/shellx-model/src/start_guard.rs (B6)
pub enum RenderMode { Standard, Compatible }
pub enum StartReason { Default, Remembered, UserEnvironment, RetryAfterOpenFailed, PreviousStartDied }
// windows/shellx-app/src/startup.rs (B6)
pub struct RenderStatus { pub mode: RenderMode, pub reason: StartReason, pub remembered: RenderMode }
pub fn render_status() -> RenderStatus;
pub fn request_standard_next_start() -> std::io::Result<()>;
// windows/shellx-app/src/build_info.rs (B4)
pub fn about_version() -> String;                                     // "ShellX 1.7.0" or "ShellX 1.7.0 (test 5dd1e2dc6a)"
// windows/shellx-app/src/diagnose_run.rs (B9)
pub fn spawn_report_process() -> std::io::Result<()>;                 // starts `<this exe> --diagnose`
```

## Rulings

Where the spec leaves a choice (§9) or is wrong, decided here; each says what it costs if wrong.

1. **Ownership** is the table above. Part A adds no module to `main.rs` or `shellx-model/src/lib.rs`; Part B never edits `strings.rs` (its dialog sentences are helpers in `crash_report.rs`). Cost: none beyond the seams.
2. **The first-window wiring is Part B's** (B2): it is a Win32 read in `os_info.rs` plus `ui/app.rs`, both B files. The rule itself is the foundations' `first_window` with `WorkArea::primary_workspace` (GPUI 0.2.2 places in workspace coordinates; primary monitor, `display_id: None`).
3. **Shell choice storage.** The spec's "existing settings file" does not exist (the app keeps only `remote\links.json` and the core's files). New file `%LOCALAPPDATA%\ShellX\native\settings.json` = `{"shell": <ShellChoice JSON>}`; other keys are kept on rewrite; missing or unreadable means Auto; writes go to a temp file then rename. Cost if wrong: one key moves.
4. **Display-mode memory** is `render.json` (`{"mode":"standard"}` / `{"mode":"compatible"}`) and the start marker `starting.json` (`{"pid":n,"mode":"standard"}`), both in `%LOCALAPPDATA%\ShellX\native`, read before GPUI starts. An unreadable marker counts as a standard start that died.
5. **Compatible mode is applied in-process**: `GPUI_DISABLE_DIRECT_COMPOSITION=1` is set before `Application::new()` (GPUI reads it once, in `WindowsPlatform::new`, `vendor/gpui-0.2.2/src/platform/windows/platform.rs:138-139`). Only an `open_window` failure relaunches the exe, because the flag is fixed once the platform exists. A stale marker switches this start directly ("chạy lại một lần" is then this start). Cost: none.
6. **"First frame"** = the second `Window::on_next_frame` callback after the window opened. GPUI runs next-frame callbacks at the start of a frame request, before drawing (`vendor/gpui-0.2.2/src/window.rs:1024-1034`), so the second one runs after the first frame was drawn and presented. An orderly quit (last window closed) also clears the marker. Cost if wrong: a false "died before first frame" once, which only switches the next start to compatible mode.
7. **Start rules, in order:** a relaunched retry → compatible (reason `RetryAfterOpenFailed`); the variable already set by the user → compatible (`UserEnvironment`), never remembered; another instance running (the mutex existed) → the remembered mode, marker neither judged nor written; a stale marker from a standard start → compatible (`PreviousStartDied`); a stale marker from a compatible start → standard (`PreviousStartDied`); else the remembered mode (`Remembered` or `Default`). A mode is remembered only when a rescue (`RetryAfterOpenFailed`, `PreviousStartDied`) reached its first frame. An open failure relaunches only a start that is standard and not a retry; anything else writes a start-failure file and shows the dialog. No automatic loop: at most one relaunch per start the person makes.
8. **Panic hook:** a crash file for every panic on every thread; the reporter starts at most once per process; panics inside the pairing job's `catch_unwind` (wrapped in `crash::expect_caught`) write a file and start no reporter. The previous hook still runs after ours, so `--smoke` keeps its stderr output. Why every thread: a panic on GPUI's vsync thread leaves the window frozen though the process lives (R1 F6).
9. **Inside the hook:** the OS thread id and "main: yes/no" (the main thread id is recorded at start-up), never `std::thread::current()`; a thread-local re-entry guard read with `try_with`; the log gets one line only through `try_lock`. Cost: crash files show thread ids, not names (the panic location still names the code).
10. **Native crashes** (R1 F3 "lỗi không phải panic"): the filter formats into stack buffers from data prepared at start-up, writes the file with `CreateFileW`/`WriteFile`, signals a watchdog thread created at start-up to launch the reporter, waits at most 5 s, and returns `EXCEPTION_CONTINUE_SEARCH`, so Windows Error Reporting still records the crash. Process creation runs on the watchdog's own stack, so a stack overflow can still report. No minidump (spec).
11. **Release builds keep `debug = false`.** Backtraces are addresses; the crash file carries the exe's base address so offsets can be mapped later. Shipping PDBs is not in this plan.
12. **Log:** `%LOCALAPPDATA%\ShellX\native\logs\shellx.log`, rotated before a write would pass 1 MiB (1 048 576 bytes) into `shellx.log.1` and `shellx.log.2` (three files), level Info and above, identical consecutive records collapsed into one count line (at most 1000 per count line). Only the GUI process writes it; `--diagnose` and the reporter never do. If `LOCALAPPDATA` is unusable the folder is `%TEMP%\ShellX\logs`. Two instances may interleave lines; rotation is best effort and never fails a write.
13. **File names** in the logs folder join their parts with `.`: `crash.20261112-081530.1234.txt`, `crash-native.20261112-081530.1234.txt`, `start-failed.20261112-081530.1234.txt`, `diagnostics.20261112-081530.txt`. The redactor hides any 32+ character run of letters, digits and `-` that has a digit; a `-`-joined name with a large PID would reach 32.
14. **Pairing sentences** (coordinator item, M3): `strings::pairing_failure_sentence` maps the pairing codes first and falls back to `failure_sentence`; `not_found`/`http_404` on the pairing path read `ServerProblem`, never "this way of signing in isn't available". The sign-in plan's Task 8 does not own `ui/pairing.rs`; A9 does.
15. **Shell fallback** runs only when the first program cannot be started (spawn error). A shell that starts and exits is the existing `RespawnGuard`'s; its held pane now also offers "Mở Command Prompt".
16. **Shell lookup never runs on the UI thread** (coordinator requirement): the catalogue and the plan are computed on a background thread and cached. A new pane reads the cache. The very first pane waits at most 2 s for the first probe, then starts Windows PowerShell at `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe` with `%SystemRoot%\System32\cmd.exe` as fallback, with no probing (CreateProcess reports a missing file). Cost: on a PC whose probe takes over 2 s, the first tab may be Windows PowerShell instead of PowerShell 7; later tabs are right.
17. **"Is a program file"** (`exists`): `std::fs::symlink_metadata` says file → true; it says symlink (a name-surrogate reparse point) → `std::fs::metadata` says file; otherwise false. Rust opens with `FILE_FLAG_OPEN_REPARSE_POINT` for `symlink_metadata` and reports a reparse point that is not a name surrogate, such as an App Execution Alias (`IO_REPARSE_TAG_APPEXECLINK`), as a file; following it with `metadata` would fail, because the file system cannot open an alias (only `CreateProcess` resolves it). Folders and drive roots are directories → false. **Inferred** for the alias: proved only by the diagnostics report listing PowerShell 7 on a PC that has it from the Store.
18. **Git Bash's install path** is read from `HKLM\SOFTWARE\GitForWindows` `InstallPath`, then the same key under `HKCU` (per-user installs); only absolute values count (the model rule).
19. **macOS (development)** keeps `/bin/bash --noprofile --norc -i` with the OSC 7 `PROMPT_COMMAND`, whatever the stored choice; Settings › Terminal on a Mac lists Automatic and the custom line only.
20. **Paste confirmation** is a bar inside the pane, checked in `TermView::paste_clipboard`, the single paste entry point, so Ctrl+Shift+V, Shift+Insert, right-click and the root's fallback all ask, in local and Mac panes. Enter pastes, Esc cancels, any other key cancels and is handled as usual; while an IME composes, the bar stays.
21. **Right/middle click:** "the pane is focused" means it held the keyboard before the click. GPUI runs an element's own mouse-down listeners before its focus-on-click listener (`vendor/gpui-0.2.2/src/elements/div.rs:2009-2045` registers the focus listener first; `src/window.rs:3703-3705` runs the bubble phase in reverse order), so the pane reads its focus before GPUI moves it. The pane slot moves the model's focus for every button.
22. **The search box and the bell are deleted**, not hidden behind a flag: the next wave that makes them work adds them back.
23. **Branch reads:** at most one background read per folder at a time; results are kept 2 s (today's TTL); a card shows the last known branch while a new read runs; a read that hangs blocks only re-reads of that folder.
24. **Mac preview switch** `SHELLX_DEV_PREVIEW=paste|settings` (development only) puts a pending 3-line paste in each new pane, or opens Settings at start, so the run check exercises that drawing.
25. **Test label:** env `SHELLX_BUILD_LABEL` (lower-case letter then up to 9 lower-case letters or digits) at build time; the setup becomes `ShellX-Setup-<version>-<label>-<commit10>.exe`; About and reports show `ShellX 1.7.0 (<label> <commit10>)`; the exe's version resource stays `1.7.0`. The commit comes from `SHELLX_BUILD_COMMIT`, else `CMUX_TUI_BUILD_COMMIT` (the cross build sets it), 40 hex only.
26. **Version resource:** `build.rs` writes `$OUT_DIR/shellx-version.rc` from `src/exe_resource.rs::version_resource` (a pure function the crate also compiles under `cfg(test)`; `build.rs` `include!`s it), and `resources/shellx.rc` `#include`s it. Both resource pipelines put `OUT_DIR` on the include path (embed-resource 3.0.12: rc.exe gets `/I out_dir`, `src/windows_msvc.rs:36`; llvm-rc input is preprocessed with `.include(out_dir)`, `src/lib.rs:714-719`). **Inferred** for rc.exe (CI only); the Docker check runs the llvm-rc path.
27. **Mutex:** `ShellXNative-D322DA97-3B0D-49C7-BDB2-8EBFADBA1004` (the native AppId in the name; session namespace, no `Global\`), created by the GUI process only, kept open until exit; a second launch still opens another window (spec §4.6). The installer's `AppMutex` names it.
28. **`os_info::os_version()`** returns `major.minor.build` from `RtlGetVersion`, then the registry, then `10.0`, never `unknown` (the relay refuses `unknown`, contract case `os_version unknown`); off Windows `10.0`.
29. **Console:** for `--version`, `--smoke`, `--smoke-ui-assets`, `--smoke-panes` and `--diagnose` only, and only when stdout has no inherited handle: `AttachConsole(ATTACH_PARENT_PROCESS)`, then `CONOUT$` for stdout and stderr when they are still missing. A pipe or file redirect is never replaced. New prints use `writeln!` with the error ignored (a closed console must not panic).
30. **`--diagnose`** checks only the shell new tabs start, at most 10 s per step, so a report takes under a minute; `--no-open` skips opening the folder (CI).
31. **Developer flags `--crash-test panic|native|window`** exist in every build and do nothing unless passed. They let one run on a real PC prove the crash reporter, the native filter and the compatible-mode rescue. `window` fails the open only in a start that is not a retry.
32. **Patch (a)** returns early from the two key-up handlers for `VK_PACKET` with the value they returned before, minus `TranslateMessage`. Not via lParam bit 31: for `VK_PACKET` the high word of lParam may carry the character (R2 F1), so the bit cannot tell down from up for characters at U+8000 and above.
33. **Patch (c):** `render_target` becomes an `Option`, a failed resize leaves `None` and is retried at the next draw instead of panicking, the device-lost path releases the old objects once (a `released` size) and creates new ones at that size, never derives the composition mode from the `direct_composition` it already took (a new field), and `Drop` skips released objects. Details in 3b.
34. **Patch (b)** changes only the refresh-rate fallback and adds a zero guard; the normal-path numbers do not change. Details in 3b.
35. **The help menu's diagnostics item** starts a separate `--diagnose` process, the same code as the Start shortcut, so the window stays responsive.
36. **The GPU GPUI chose** is read from the last GUI run's log: the last `Using GPU:` line before `Created device with Direct3D` (GPUI logs every adapter it tries, `vendor/gpui-0.2.2/src/platform/windows/directx_devices.rs:121-131`). "Which mode it draws in" for `--diagnose`, a separate process, is the remembered mode plus the last start's log line.
37. **The forced-update overlay** stops every key except `keys::is_window_system_key` (Alt+F4, Alt+Space).

## Interfaces for the docs group (spec §6 group 6)

User-visible changes the README and the checklist must describe: Settings › Terminal (shells, custom command line, applies to new tabs); `SHELLX_SHELL` takes a command line and refuses relative paths; the title bar has no search box and no bell; right-click pastes (copies with a selection), a first click on another pane only focuses it; multi-line pastes ask first; failed shells offer "Thử lại" and "Mở Command Prompt"; logs and crash files in `%LOCALAPPDATA%\ShellX\native\logs`; the crash dialog; `--diagnose`, the help-menu item and the Start entry "ShellX – Chẩn đoán"; `--version` and `--smoke` print in a console; Settings › Display and the compatible mode; `--crash-test`; the developer switch `SHELLX_DEV_PREVIEW`.

---

## Setup (each part, once)

```bash
cd /Users/richard/Documents/helper/shellx
git worktree add .worktrees/windows-usable-wiring -b feat/shellx-windows-usable-wiring develop      # Part A
git worktree add .worktrees/windows-usable-winonly -b feat/shellx-windows-usable-winonly develop    # Part B
```
If the foundations branch is not on `develop` yet, branch from `feat/shellx-windows-usable-foundations` instead and say so in the report. From each worktree's root, fill its empty `ghostty/` from the main checkout at the pinned commit:
```bash
test "$(git -C /Users/richard/Documents/helper/shellx/ghostty rev-parse HEAD)" = "$(git ls-tree HEAD ghostty | awk '{print $3}')"
git -C /Users/richard/Documents/helper/shellx/ghostty archive HEAD | tar -x -C ghostty
```
If the commits differ, stop and report.

**Commands** (every shell starts with the build line; agent shells keep no variables):
- Build line: `export PATH="/opt/homebrew/opt/zig@0.16/bin:$HOME/.cargo/bin:$PATH"`
- MODEL: `(cd windows && cargo test --locked -p shellx-model)` → `test result: ok`
- APP: `(cd windows && nice -n 19 cargo test --release --locked -p shellx-app)` → `test result: ok`
- BUILD: `(cd windows && nice -n 19 cargo build --release --locked -p shellx-app)` → `Finished`, no new warning
- WINCHECK: `scripts/shellx/check-windows-build.sh` → `Checked <HEAD> for Windows (x86_64-pc-windows-msvc): OK` (it compiles the committed `HEAD`: commit first)
- GPUICHECK: `windows/vendor/check-gpui.sh`
- RUNCHECK (after BUILD; `P` is an optional `NAME=value` env prefix, for example `P=SHELLX_DEV_PREVIEW=paste`). **Coordinator's rule:** the window holds a real shell, so a start of the built binary on this Mac must never come to the front or take the keyboard from a person working here, and must never share state with another run. Every start of `target/release/shellx-desktop` on this Mac, in this check and in any other step of this plan (`--crash-test`, `--report-crash`, `--diagnose`, …), uses a fresh scratch home and `SHELLX_DEV_BACKGROUND=1` (in `ui/app.rs` since `d2ad165769` on `develop`: unfocused window, no activation; Mac builds only):
  ```bash
  (cd windows || exit 1; h="$(mktemp -d "${TMPDIR:-/tmp}/shellx-run.XXXXXX")"
   env HOME="$h" SHELLX_DEV_BACKGROUND=1 $P target/release/shellx-desktop >"$h/run.log" 2>&1 & p=$!; sleep 8
   if kill -0 $p 2>/dev/null; then kill $p; wait $p 2>/dev/null; grep -c panicked "$h/run.log"; else echo DIED; cat "$h/run.log"; fi; echo "home: $h")
  ```
  Expected: `0` (alive after 8 s, no panic). Only the binary is backgrounded (`env` execs it, so `$p` is its PID); it starts only this binary and kills only that PID. Where a step below names `~/.local/share/shellx-native/…`, read `$h/.local/share/shellx-native/…`. If the shell tool refuses a foreground `sleep`, run the whole check as a background command. Never run the binary without both variables; if a branch does not contain `d2ad165769` yet, merge `develop` first or record "RUNCHECK: not run".

---

## Part A: wiring (shared code)

### Task A1: Shell catalogue, stored choice and launch plan with one fallback (R3 M1, m4)

**Files:**
- Create: `windows/shellx-app/src/local_pty/settings.rs`
- Modify: `windows/shellx-app/src/local_pty.rs` (`pub mod settings;`; `ShellCmd` gains `label` and `kind`; `ShellCmd::from_launch`; `PanePlan`; `command_prompt`, `command_prompt_for`; `default_shell`; drop `POWERSHELL_HOOK` and `shell_cmd` (the hook now arrives in the model's PowerShell launch arguments); tests)
- Modify: `windows/shellx-app/src/workspace.rs` (`spawn_local_pane_with`; `spawn_local_pane` delegates)
- Modify: `windows/shellx-app/src/ui/term_view.rs` (`TermView::new` starts from the plan; the error text keeps today's form until A2)
- Modify: `windows/shellx-model/src/shell.rs` (`is_absolute` becomes `pub`; `kind_label`, `launch_label`)

**Interfaces:**
- Consumes: foundations `shell::{find_shells, launch_plan, custom_launch, ShellChoice, ShellLaunch, ShellProbe, LaunchPlan, ShellError, ShellKind, POWERSHELL_PROMPT_HOOK}` (rules-b behaviour: absolute paths only, Auto within PowerShell 7, Windows PowerShell and Command Prompt).
- Produces (also the seam for B9):

```rust
// shell.rs (model)
pub fn is_absolute(path: &str) -> bool;                  // was private; body unchanged
pub fn kind_label(kind: ShellKind) -> &'static str;      // "PowerShell 7", "Windows PowerShell", "Command Prompt", "Git Bash", "WSL"
pub fn launch_label(l: &ShellLaunch) -> String;          // kind_label, or the program's file name for a custom line ("bash.exe")
// local_pty.rs
pub struct ShellCmd { pub program: String, pub args: Vec<String>, pub env: Vec<(String, String)>,
                      pub label: String, pub kind: Option<ShellKind> }       // kind None: custom line, Mac bash
impl ShellCmd { pub fn from_launch(l: &ShellLaunch) -> ShellCmd /* env empty; label = launch_label; kind = l.kind */ }
pub struct PanePlan { pub first: ShellCmd, pub fallback: Option<ShellCmd> }
pub fn default_shell() -> ShellCmd;                      // first of shells().plan_for_new_pane(), else Windows PowerShell (smoke)
pub fn command_prompt() -> ShellCmd;                     // command_prompt_for(shells' catalogue, probe); macOS /bin/sh -i
pub fn command_prompt_for(found: &[ShellLaunch], probe: &ShellProbe) -> ShellCmd;
    // the catalogue's Cmd, else %ComSpec% when absolute, else %SystemRoot%\System32\cmd.exe (C:\Windows when SystemRoot is not absolute)
// local_pty/settings.rs
pub enum ShellHost { Windows, MacDev }
pub struct SettingsFile { /* path */ } impl SettingsFile { pub fn new(path: PathBuf) -> Self; pub fn load(&self) -> ShellChoice; pub fn save(&self, choice: &ShellChoice) -> std::io::Result<()> }
pub fn is_program_file(path: &str) -> bool;              // Ruling 17
pub fn probe_from_system() -> ShellProbe;                // SystemRoot, ProgramFiles, ComSpec, PATH; Git: Ruling 18 (cfg(windows) registry)
pub fn startup_plan(probe: &ShellProbe) -> PanePlan;     // Ruling 16, no probing
pub struct Shells { /* Mutex<State> + Condvar */ }
impl Shells {
    pub fn new(file: SettingsFile, probe: ShellProbe, env_override: Option<String>, exists: Arc<dyn Fn(&str) -> bool + Send + Sync>,
               host: ShellHost, first_wait: Duration) -> Shells;
    pub fn choice(&self) -> ShellChoice;
    pub fn set_choice(&self, choice: ShellChoice) -> std::io::Result<()>;   // saves, then recomputes in the background
    pub fn refresh(&self);                                                    // background recompute (std::thread)
    pub fn refresh_now(&self) -> ShellSnapshot;                               // blocking; never on the UI thread
    pub fn snapshot(&self) -> ShellSnapshot;
    pub fn plan_for_new_pane(&self) -> Result<PanePlan, ShellError>;          // cache; first call waits ≤ first_wait
    pub fn probe(&self) -> ShellProbe;
}
pub fn shells() -> &'static Shells;   // settings.json in paths::native_dir(); host from cfg!(windows); first_wait 2 s; env SHELLX_SHELL
// workspace.rs
pub struct StartedPane { pub pane: LocalPane, pub used: String /* label */, pub fell_back: Option<(String /* label */, String /* error */)> }
pub struct StartFailure { pub attempts: Vec<(String /* label */, String /* program */, String /* error */)> }
pub fn spawn_local_pane_with(plan: &PanePlan, cols: u16, rows: u16, extra_args: &[&str]) -> Result<StartedPane, StartFailure>;
```

- [ ] **Step 1: Write the failing tests**

```rust
// shell.rs (model)
#[test] fn shells_have_display_names() {
    // kind_label for each kind as above; launch_label(custom r"C:\Program Files\Git\bin\bash.exe") == "bash.exe"
}
// local_pty/settings.rs (Mac; Windows-style probe: system_root C:\Windows, program_files C:\Program Files,
// comspec C:\Windows\system32\cmd.exe, path C:\Windows\System32; exists = a set of strings)
#[test] fn the_stored_choice_round_trips_and_keeps_other_keys() {
    // in tempdir/"Phú Lê": file {"shell":{"kind":"known","shell":"git_bash"},"future":1} → load == Known{GitBash};
    // save(&Auto) → file parses to {"shell":{"kind":"auto"},"future":1}
}
#[test] fn a_missing_or_unreadable_file_means_auto() { /* none, "{", "[]", {"shell":{"kind":"bash"}} → Auto */ }
#[test] fn the_catalogue_follows_the_choice_and_shellx_shell() {
    // exists {pwsh 7, powershell, cmd}: refresh_now: found kinds [Pwsh, WindowsPowerShell, Cmd]; plan first Pwsh, fallback WindowsPowerShell;
    // ShellCmd::from_launch(first).args == ["-NoLogo", "-NoExit", "-Command", POWERSHELL_PROMPT_HOOK] (the OSC 7 hook, R3 m1), env empty;
    // set_choice(Known{Cmd}) then refresh_now → first Cmd (args []), fallback Pwsh;
    // env_override Some(r"C:\Windows\system32\cmd.exe /k") → first program r"C:\Windows\system32\cmd.exe", args ["/k"];
    // Custom{"nope.exe"} → plan Err(Custom(NotFound("nope.exe")))
}
#[test] fn the_first_pane_waits_at_most_the_bound_then_starts_windows_powershell() {
    // exists sleeps 1 s then answers; first_wait 100 ms; host Windows: plan_for_new_pane returns in < 1 s with
    // first.program == r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" (args with the prompt hook),
    // fallback.program == r"C:\Windows\System32\cmd.exe"
}
#[test] fn a_new_pane_uses_the_catalogue_once_it_is_ready() { /* fast exists; refresh_now(); plan_for_new_pane().first.label == "PowerShell 7" */ }
#[test] fn only_the_first_pane_ever_waits() { /* exists sleeps 1 s; first_wait 100 ms: 1st call ≈100 ms, 2nd call < 20 ms, both Windows PowerShell */ }
#[test] fn the_mac_harness_keeps_bash() { /* host MacDev, choice Known{Cmd}: first.program "/bin/bash", env has PROMPT_COMMAND */ }
#[test] fn program_files_are_files_folders_are_not_links_are_followed() {
    // tempdir: file "a.exe" → true; dir "d" → false; symlink "l.exe"→a.exe → true; dangling symlink → false; missing → false
}
#[test] fn command_prompt_prefers_the_catalogue_then_comspec_then_system32() {
    // found has Cmd r"C:\Windows\system32\cmd.exe" → that program, label "Command Prompt", args [];
    // found empty, comspec r"D:\cmd\cmd.exe" → that; comspec "cmd.exe" (relative) → r"C:\Windows\System32\cmd.exe"
}
// workspace.rs
#[cfg(unix)] #[test] fn the_fallback_starts_once_when_the_first_program_cannot_start() {
    // PanePlan { first: "/nonexistent/shell", fallback: Some("/bin/sh" ["-i"]) } → Ok, used == fallback label,
    // fell_back == Some(("/nonexistent/shell"'s label, error text non-empty)); the shell answers `echo ok-$((6*7))` with ok-42
}
#[cfg(unix)] #[test] fn both_programs_failing_report_both() { /* two missing programs → Err with 2 attempts, in order */ }
```
- [ ] **Step 2: Run to verify they fail.** MODEL and APP → compile errors (`kind_label`, `settings` module, `spawn_local_pane_with` missing). Commit: `test(windows): shell catalogue, stored choice and one fallback [red]`.
- [ ] **Step 3: Implement.** `Shells` keeps `{ choice, computed: Option<Computed>, generation }` under a `Mutex` with a `Condvar`; `refresh` spawns a `std::thread` that runs `find_shells` and `launch_plan` with the injected `exists` and stores the result only if its generation is current; `plan_for_new_pane` on `Windows` starts the probe when none has run or runs, and waits on the condvar only on its first call and only while nothing was ever computed, at most `first_wait`; until the first probe ends every call (that first one after its wait, and all later ones at once) uses `startup_plan`; on `MacDev` it returns today's bash (`ShellCmd` built like the old `shell_cmd(None)` non-Windows branch, with `SHELLX_SHELL` as program and no args when set). `ShellCmd::from_launch` sets `label = launch_label`. `TermView::new` calls `spawn_local_pane_with(&plan, 80, 24, &[])`; a plan error or `StartFailure` sets `self.error` to a one-line English summary (A2 replaces it). `smoke.rs` keeps compiling unchanged (`default_shell`, `spawn_local_pane` signatures kept).
- [ ] **Step 4: Run.** MODEL, APP → all pass; BUILD; RUNCHECK → `0`; RUNCHECK with `P=SHELLX_SHELL=/nonexistent/shell` → `0` (the pane shows the error, no panic).
- [ ] **Step 5: Commit.** `feat(windows): shells are looked up off the UI thread; Auto, the stored choice and SHELLX_SHELL start one shell with one fallback (R3 M1, m4)`. Then WINCHECK → OK.

Windows-only piece: `probe_from_system`'s Git read, `winreg::RegKey::predef(HKEY_LOCAL_MACHINE).open_subkey(r"SOFTWARE\GitForWindows")` then `HKEY_CURRENT_USER`, `get_value::<String, _>("InstallPath")`; any error → `None` (the model then tries `%ProgramFiles%\Git\bin\bash.exe`). Covered by WINCHECK and, on the PC, the report's `[shells]` list.

### Task A2: A pane that cannot start a shell says why and offers Retry and Command Prompt (R3 m4)

Starts after the sign-in plan is on `develop` (merge first).

**Files:**
- Modify: `windows/shellx-app/src/ui/term_view.rs` (start states, `start_local`, buttons, fallback flash, `held_message`)
- Modify: `windows/shellx-model/src/strings.rs` (3 `Str`, 1 changed text, 3 helpers)

**Interfaces:**
- Consumes: A1.
- Produces: `strings::{custom_shell_error(Lang, &CustomShellError) -> String, shell_plan_error(Lang, &ShellError) -> String, shell_fell_back(Lang, tried: &str, used: &str) -> String}`; `Str::{ShellCannotStart, OpenCommandPrompt, NoShellFound}`.

Sentences (vi / en):
- `ShellCannotStart`: "Không khởi động được shell. Chọn shell khác trong Cài đặt › Terminal, hoặc mở Command Prompt." / "The shell couldn't start. Choose another shell in Settings › Terminal, or open Command Prompt."
- `ShellExitsAtStart` (text changes; R3 m4: nobody knows `SHELLX_SHELL`): "Shell thoát ngay khi khởi động. Chọn shell khác trong Cài đặt › Terminal." / "The shell exits as soon as it starts. Choose another shell in Settings › Terminal."
- `OpenCommandPrompt`: "Mở Command Prompt" / "Open Command Prompt"
- `NoShellFound`: "Không tìm thấy shell nào trên máy này." / "No shell was found on this PC."
- `shell_fell_back`: "Không khởi động được {tried}, đang dùng {used}." / "{tried} couldn't start, so {used} is running instead."
- `custom_shell_error`: `Empty` → "Nhập một dòng lệnh, ví dụ wsl.exe -d Ubuntu." / "Type a command line, for example wsl.exe -d Ubuntu."; `UnclosedQuote` → "Thiếu dấu ngoặc kép đóng." / "A closing quotation mark is missing."; `NotFound(p)` where `p` has `\`, `/` or `:` and `!shell::is_absolute(p)` → "Hãy ghi đường dẫn đầy đủ, ví dụ C:\…\{file}, thay cho {p}." / "Use a full path such as C:\…\{file} instead of {p}." (`{file}` = `p`'s last segment); other `NotFound(p)` → "Không tìm thấy chương trình {p}." / "Can't find the program {p}."
- `shell_plan_error`: `NoShellFound` → `NoShellFound`; `Custom(e)` → `custom_shell_error(e)`; `Override(e)` → `"SHELLX_SHELL: "` + `custom_shell_error(e)` (both languages).

Pane rules: a start failure (plan error or every attempt failed) draws, instead of the grid, the error colour line (`ShellCannotStart`, or `shell_plan_error` for a plan error), then one muted small line per attempt `"{label}: {error}"`, then `PressAnyKeyToRetry`, then buttons `held-retry` (`Retry`, Primary) and `held-cmd` (`OpenCommandPrompt`, Secondary). Retry restarts in place from `shells().plan_for_new_pane()`; Command Prompt restarts in place with `PanePlan { first: command_prompt(), fallback: None }`; any key does Retry. The held pane (`RespawnGuard`) draws `ShellExitsAtStart` with the same two buttons: Retry keeps emitting `TermEvent::Retry` (the guard clears its history), Command Prompt restarts in place. After a fallback start the pane flashes `shell_fell_back(lang, tried, used)` (existing `flash`).

- [ ] **Step 1: Write the failing tests** (`strings.rs`): `shell_start_sentences` (exact vi/en of the four `Str`), `custom_shell_errors_say_what_to_do` (each branch, both languages, with `r".\pwsh.exe"` → contains `C:\…\pwsh.exe` and `.\pwsh.exe`; `"nope.exe"` → contains `nope.exe`), `shell_plan_errors_name_shellx_shell`; `exact_vi_strings` gets the new `ShellExitsAtStart`; `all_has_no_duplicates` = branch count + 3.
- [ ] **Step 2: Run.** MODEL → compile errors. Commit `test(windows): sentences for a shell that cannot start [red]`.
- [ ] **Step 3: Implement** the strings, then `TermView`: `start_local(&mut self, plan: Result<PanePlan, ShellError>, cx)` holds today's `new` body (backend, reader task, exit poll) and the failure state; `new` and the buttons call it.
- [ ] **Step 4: Run.** MODEL, APP, BUILD; RUNCHECK with `P=SHELLX_SHELL=/nonexistent/shell` → `0`; with `P=SHELLX_SHELL=/usr/bin/true` (exits at once, the guard holds the pane) → `0`.
- [ ] **Step 5: Commit** `feat(windows): a pane whose shell cannot start explains it and offers Retry and Command Prompt (R3 m4)`.

### Task A3: Touchpad scrolling and the wheel in full-screen programs (R2 F2, F13)

**Files:**
- Modify: `windows/shellx-app/src/ui/term_view.rs` (`on_scroll`, field `scroll: ScrollAccumulator`)
- Modify: `windows/shellx-app/src/term_core.rs` (two accessors, test)

**Interfaces:**
- Consumes: `mouse::{ScrollAccumulator, ScreenModes, WheelAction, wheel_action}`.
- Produces: `TermCore::alternate_screen(&self) -> bool` (`terminal.active_screen() == ghostty_vt::Screen::Alternate`), `TermCore::mouse_tracking(&self) -> bool` (`terminal.mouse_tracking()`).

- [ ] **Step 1: Write the failing test** (`term_core.rs`, existing `FakeLink`): `alternate_screen_and_mouse_tracking_follow_the_modes` — fresh core: both false; feed `"\x1b[?1049h"` → `alternate_screen()`; feed `"\x1b[?1000h"` → `mouse_tracking()`; feed `"\x1b[?1049l\x1b[?1000l"` → both false.
- [ ] **Step 2: Run.** APP → compile error. Commit `test(windows): the terminal reports its alternate screen and mouse tracking [red]`.
- [ ] **Step 3: Implement.** `on_scroll`: `lines = delta.y / line_height` as `f64` (`delta = event.delta.pixel_delta(self.line_height)`, the sign today's code uses); `n = self.scroll.add(lines)`; `modes` from `self.backend.core()` (none → return); `wheel_action(n, modes)`: `Scrollback(k)` → today's `follow_viewport(... core.scroll_lines(-(k as isize)))`; `Arrows { key, count }` → `count` times `core.send_chord(key)` (DECCKM honoured by the encoder; a refused remote link drops them silently); `None` → nothing. `cx.notify()` when something changed.
- [ ] **Step 4: Run.** APP, BUILD, RUNCHECK → `0`. (A trackpad check on the Mac build is the user's; the PC is hands-on step 6.)
- [ ] **Step 5: Commit** `feat(windows): touchpad scrolling accumulates per pane; the wheel sends arrows in full-screen programs (R2 F2, F13)`.

### Task A4: Right and middle click, focus on every click, and system keys over the update overlay (R2 F4, F10, F7)

**Files:**
- Modify: `windows/shellx-app/src/ui/term_view.rs` (two mouse-down listeners), `windows/shellx-app/src/ui/panes.rs` (`region_view` slot: Right and Middle), `windows/shellx-app/src/ui/update_banner.rs` (overlay key listener)

**Interfaces:**
- Consumes: `mouse::{SecondaryButton, PaneClick, secondary_click}`; `keys::{KeyIn, is_window_system_key}`.

- [ ] **Step 1: Red** (no GPUI test harness): `grep -n 'MouseButton::Right\|MouseButton::Middle' windows/shellx-app/src/ui/term_view.rs windows/shellx-app/src/ui/panes.rs` → nothing; `grep -n 'stop_propagation' windows/shellx-app/src/ui/update_banner.rs` → the unconditional stop. The rules are the foundations' tested `secondary_click` and `is_window_system_key`.
- [ ] **Step 2: Implement.** `TermView` root: `.on_mouse_down(MouseButton::Right, …)` and `(Middle, …)` → `focused = self.focus_handle.is_focused(window)` read first (Ruling 21) → `secondary_click(button, focused, self.has_selection())`: `FocusOnly` → `window.focus(&self.focus_handle)`; `Paste` → `self.paste_clipboard(cx)`; `CopySelection` → `self.copy_selection(cx)`; `Nothing`. `panes.rs`: the slot's `on_mouse_down(Left, …)` is repeated for `Right` and `Middle` (`this.focus_pane(pane, …)`; while a panel is open `focus_pane` already swallows it and gives the keyboard back to the panel). `update_banner.rs`: the overlay's listener builds `KeyIn` from the keystroke (as `RootView::key_action`) and calls `cx.stop_propagation()` only when `!is_window_system_key(&key)` (Ruling 37).
- [ ] **Step 3: Run.** APP, BUILD, RUNCHECK → `0`. Read once more: the right-click path reads focus before calling anything that focuses.
- [ ] **Step 4: Commit** `feat(windows): right-click pastes or copies like the Windows console, a first click on another pane only focuses it, Alt+F4 passes the update overlay (R2 F4, F10, F7)`.

### Task A5: Multi-line paste asks first, on every paste path (R2 F18)

Starts after the sign-in plan is on `develop`.

**Files:**
- Modify: `windows/shellx-model/src/paste.rs`, `windows/shellx-model/src/strings.rs`, `windows/shellx-app/src/ui/term_view.rs`

**Interfaces:**
- Consumes: `paste::needs_paste_confirmation`, `keys::KeyIn`.
- Produces: `paste::paste_line_count(text: &str) -> usize` (segments split at `\r\n`, `\n` or `\r`, minus one trailing empty segment); `paste::{ConfirmKey::{Confirm, Cancel, CancelAndPass}, confirm_key(k: &KeyIn) -> ConfirmKey}` (`enter` with no modifier → Confirm; `escape` with no modifier → Cancel; anything else → CancelAndPass); `strings::paste_lines_prompt(Lang, n: usize) -> String`; `Str::PasteConfirmKeys`.

Sentences: `paste_lines_prompt`: "Dán {n} dòng? Mỗi dòng sẽ chạy ngay như một lệnh." / "Paste {n} lines? Each line will run as a command right away."; `PasteConfirmKeys`: "Enter để dán, Esc để hủy" / "Enter to paste, Esc to cancel". Buttons reuse `Str::Paste` and `Str::Cancel`.

- [ ] **Step 1: Write the failing tests**

```rust
#[test] fn paste_line_count_counts_what_the_shell_will_run() {
    // "a\nb" 2; "a\r\nb\r\n" 2; "a\rb" 2; "\nb" 2; "echo 1\necho 2\necho 3\n" 3; "a\n\n\nb" 4; "a\nb\n\n" 3; "x" 1
}
#[test] fn confirm_keys_paste_cancel_or_pass() {
    // enter → Confirm; escape → Cancel; ctrl+enter, shift+enter, "a", "space", ctrl+c, alt+f4 → CancelAndPass
}
// strings.rs: paste_prompt_strings (exact text for n = 3, both languages); count + 1
```
- [ ] **Step 2: Run.** MODEL → compile errors. Commit `test(windows): multi-line paste counts lines and reads its keys [red]`.
- [ ] **Step 3: Implement.** `paste_clipboard` (Ruling 20): read the text; a remote pane that refuses input flashes as today and returns; when `needs_paste_confirmation(&text, core.bracketed_paste())` set `pending_paste = Some(text)` and notify; else paste as today (move today's body to `paste_now(text)`). The bar (bottom of the pane, like `flash_line`, raised card) shows `paste_lines_prompt(lang, paste_line_count(&text))`, buttons `paste-confirm` (`Paste`, Primary) and `paste-cancel` (`Cancel`, Secondary), and the muted `PasteConfirmKeys`. `on_key_down` first: while `pending_paste` is `Some` and not composing, `confirm_key`: Confirm → `paste_now`, stop; Cancel → clear, stop; CancelAndPass → clear and continue as today. Preview (macOS only): `SHELLX_DEV_PREVIEW=paste` sets `pending_paste = Some("echo 1\necho 2\necho 3\n")` in `TermView::new`.
- [ ] **Step 4: Run.** MODEL, APP, BUILD; RUNCHECK with `P=SHELLX_DEV_PREVIEW=paste` → `0`.
- [ ] **Step 5: Commit** `feat(windows): pasting more than one line into a shell without bracketed paste asks first, on every paste path (R2 F18)`.

### Task A6: Settings › Terminal: choose a shell or type a command line (spec §4.4)

Starts after the sign-in plan is on `develop`.

**Files:**
- Modify: `windows/shellx-app/src/ui/settings.rs` (A's regions, Parts table), `windows/shellx-app/src/ui/text_field.rs` (`set_text` after `clear`), `windows/shellx-app/src/local_pty/settings.rs` (`shell_options`), `windows/shellx-model/src/strings.rs`

**Interfaces:**
- Consumes: A1 (`shells()`, `ShellSnapshot`, `is_program_file`), A2 (`custom_shell_error`), `shell::{custom_launch, kind_label}`.
- Produces: `local_pty::settings::{ShellOption::{Auto { resolves_to: Option<String> }, Known(ShellKind), Custom}, shell_options(found: &[ShellLaunch]) -> Vec<ShellOption>, is_selected(&ShellOption, &ShellChoice) -> bool}` (Auto first, resolving to the label of the first found PowerShell 7, Windows PowerShell or Command Prompt; then one `Known` per found kind in `find_shells` order; then `Custom`); `TextField::set_text(&mut self, text: &str, cx)`; `strings::{shell_auto_label(Lang, Option<&str>) -> String, will_run(Lang, program: &str) -> String}`; `Str::{Terminal, CustomCommandLine, CustomShellPlaceholder, AppliesToNewTerminals, ShellEnvOverride}`.

Sentences: `Terminal`: "Terminal" / "Terminal"; `shell_auto_label`: "Tự động ({name})" or "Tự động" / "Automatic ({name})" or "Automatic"; `CustomCommandLine`: "Dòng lệnh tùy chỉnh" / "Custom command line"; `CustomShellPlaceholder`: "Ví dụ: wsl.exe -d Ubuntu" / "For example: wsl.exe -d Ubuntu"; `will_run`: "Sẽ chạy {program}." / "Runs {program}."; `AppliesToNewTerminals`: "Áp dụng cho các terminal mở sau." / "Applies to terminals you open next."; `ShellEnvOverride`: "SHELLX_SHELL đang được đặt nên ShellX dùng giá trị đó thay cho lựa chọn này." / "SHELLX_SHELL is set, so ShellX uses it instead of this choice."

Section (after Account, before Updates): title `Terminal`; one clickable row per `shell_options` entry (`settings-shell-auto`, `settings-shell-<kind>`, `settings-shell-custom`), the selected one marked with `Icon::CircleCheck`; under Custom, when selected: the field (placeholder `CustomShellPlaceholder`, filled with the stored line) and one line: the background check's `custom_shell_error` in the error colour, or `will_run` muted; muted `AppliesToNewTerminals`; `ShellEnvOverride` when `snapshot.env_override` is set. Rows other than Custom call `shells().set_choice(…)` at once. The field's every text change runs `custom_launch(text, &probe, &is_program_file)` with `cx.background_spawn` (a sequence number drops stale answers); an `Ok` stores `Custom { command_line }`; an error shows and keeps the stored choice. `TextFieldEvent::Cancel` closes Settings, `Submit` does nothing more. `open()` starts `refresh_now` in the background and redraws with its snapshot. Preview (macOS only): `SHELLX_DEV_PREVIEW=settings` makes `SettingsPanel::new` start open.

- [ ] **Step 1: Write the failing tests**: `local_pty::settings::tests::shell_options_list_auto_found_and_custom` (all five found → [Auto{"PowerShell 7"}, Known×5, Custom]; only cmd → [Auto{"Command Prompt"}, Known(Cmd), Custom]; none → [Auto{None}, Custom]; `is_selected` per choice); `strings::tests::terminal_settings_strings` (exact text; count + 5).
- [ ] **Step 2: Run** → compile errors. Commit `test(windows): Settings terminal options and sentences [red]`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** MODEL, APP, BUILD; RUNCHECK with `P=SHELLX_DEV_PREVIEW=settings` → `0`.
- [ ] **Step 5: Commit** `feat(windows): Settings › Terminal chooses the shell for new tabs or takes a command line (R3 M1)`.

### Task A7: Git branch reads leave the UI thread (R1 F15, R3 m3)

**Files:** Modify `windows/shellx-app/src/cwd.rs` (`BranchCache`), `windows/shellx-app/src/ui/root.rs` (`card_lines` only)

**Interfaces:**
- Produces: `cwd::BranchLookup { pub branch: Option<String>, pub read: bool }`; `BranchCache::lookup(&mut self, cwd: &str, now: Instant) -> BranchLookup`; `BranchCache::store(&mut self, cwd: &str, branch: Option<String>, now: Instant)` (Ruling 23). `BranchCache::get` is removed.

- [ ] **Step 1: Write the failing tests** (`cwd.rs`, replacing `branch_cache_rereads_after_two_seconds`): `a_new_folder_is_read_once_in_the_background` (lookup → `{None, true}`; again → `{None, false}`; `store(Some("main"))` → `{Some("main"), false}`), `a_stale_branch_shows_while_it_is_read_again` (after 2 s → `{Some("main"), true}`, then `{Some("main"), false}` until `store`), `a_hung_read_is_never_started_twice` (no `store` for 10 s → only the first lookup says `read`).
- [ ] **Step 2: Run** APP → compile errors. Commit `test(windows): branch lookups read in the background, once per folder [red]`.
- [ ] **Step 3: Implement.** `card_lines(&mut self, pane, cx: &mut Context<Self>)`: `lookup`; when `read`, `cx.spawn` a task that awaits `cx.background_executor().spawn(async move { git_branch(Path::new(&dir)) })`, then `this.update` → `branches.store(&dir, branch, Instant::now())` and `cx.notify()`.
- [ ] **Step 4: Run.** APP, BUILD, RUNCHECK → `0`.
- [ ] **Step 5: Commit** `fix(windows): workspace cards read the git branch off the UI thread (R1 F15)`.

### Task A8: The title bar loses its display-only search box and bell (R2 F15)

**Files:** Modify `windows/shellx-app/src/ui/titlebar.rs` (the `bell` child, `search_box` and `SEARCH_W`, the module comment)

- [ ] **Step 1: Red:** `grep -n 'titlebar-bell\|fn search_box' windows/shellx-app/src/ui/titlebar.rs` → two matches.
- [ ] **Step 2: Implement** (Ruling 22). `Icon::BellRing`, `Icon::Search`, `Str::SearchPlaceholder` and `Str::ShowNotifications` stay (icon table, smoke string check, Mac string tests).
- [ ] **Step 3: Run.** The grep prints nothing; APP, BUILD (no new warning), RUNCHECK → `0`.
- [ ] **Step 4: Commit** `feat(windows): the title bar no longer draws the display-only search box and bell (R2 F15)`.

### Task A9: Pairing errors read as sentences (coordinator item 1; M3)

Starts after the sign-in plan is on `develop`.

**Files:** Modify `windows/shellx-model/src/strings.rs`, `windows/shellx-app/src/ui/pairing.rs` (the `PairState::Failed` arm)

Codes that can reach `PairState::Failed` (the request path, `shellx-core/src/pairing.rs` `request`, `relay/src/v2/pairings.ts` `POST /`, `remote_state.rs`, `pairing_service.rs` `execute_caught`): relay `unauthorized`, `desktop_only`, `payload_too_large`, `rate_limited`, `bad_request`, `machine_not_found`, `forbidden`, `internal_error`, body-less `http_<status>`; core `not_logged_in`, `not_configured`, `not_registered`, `invalid_params`, `network`, `server`, store errors (`io`, `crypto`, `state_dir_insecure`, `state_file_insecure`), `unknown_method`; model `bad_response`; app `internal`. Other pairing routes' codes mapped too (review M3): `pairing_expired`, `pairing_not_pending`, `pairing_removed`, `pairing_not_found`, `not_granted`, `host_offline`, `relay_v2_unavailable`.

`pairing_failure_sentence(lang, code)`: `machine_not_found` → `MachineGone`; `unauthorized`, `http_401`, `not_logged_in` → `PairingSessionExpired`; `forbidden`, `desktop_only` → `PairingRefused`; `host_offline` → `HostOffline`; `pairing_not_pending` → `RequestAlreadyAnswered`; `pairing_removed`, `pairing_not_found` → `RequestGone`; `pairing_expired` → existing `Expired`; `not_granted` → existing `NeedsPairing`; `rate_limited` → `RateLimited`; `network` → `RelayUnreachable`; anything else, `not_found` and `http_404` included → `ServerProblem` (Ruling 14).

Sentences: `MachineGone`: "Máy này không còn trong tài khoản của bạn." / "That machine is no longer in your account."; `PairingSessionExpired`: "Phiên đăng nhập đã hết hạn. Đăng nhập lại rồi thử lại." / "Your session expired. Sign in again, then try again."; `PairingRefused`: "Máy chủ không nhận yêu cầu từ máy này. Đăng xuất rồi đăng nhập lại." / "The server didn't accept a request from this PC. Sign out and sign in again."; `HostOffline`: "Máy kia đang ngoại tuyến. Mở ShellX trên máy đó rồi thử lại." / "The other machine is offline. Open ShellX on it, then try again."; `RequestAlreadyAnswered`: "Máy kia đã trả lời yêu cầu này." / "The other machine already answered this request."; `RequestGone`: "Yêu cầu này không còn nữa. Hãy gửi lại." / "This request no longer exists. Send it again."

- [ ] **Step 1: Write the failing tests**: `pairing_failures_have_their_own_sentences` (one assertion per mapped code, both languages); `pairing_failures_never_show_codes` (every code listed above plus `""` and `http_502`: non-empty, no `_`, no `http`); count + 6.
- [ ] **Step 2: Run** MODEL → compile errors. Commit `test(windows): pairing failures have sentences of their own [red]`.
- [ ] **Step 3: Implement**; the panel's failed line becomes `pairing_failure_sentence(lang, &e.code)` alone (no `Str::Error` prefix, no `e.message`).
- [ ] **Step 4: Run** MODEL, APP, BUILD; `grep -n 'e.message' windows/shellx-app/src/ui/pairing.rs` → nothing.
- [ ] **Step 5: Commit** `fix(windows): a failed access request reads as a sentence, never a code or server text (M3)`.

### Task A10: Settings › Display, the test label in About, the diagnostics menu item (needs B3, B4, B6, B9)

**Files:** Modify `windows/shellx-app/src/ui/settings.rs` (`display_section`, `about_section`), `windows/shellx-app/src/ui/sidebar.rs` (`help_menu`), `windows/shellx-model/src/strings.rs`, `windows/shellx-app/src/ui/term_view.rs` (the remote-update `eprintln!` → `log::warn!`)

**Interfaces:**
- Consumes: the B → A seams (top of this plan).
- Produces: `Str::{Display, DisplayStandard, DisplayCompatible, DisplayCompatibleWhy, DisplayCompatibleByEnv, TryStandardDisplay, TakesEffectNextStart, CreateDiagnosticsReport}`.

Sentences: `Display`: "Hiển thị" / "Display"; `DisplayStandard`: "Chế độ hiển thị thường" / "Standard display mode"; `DisplayCompatible`: "Chế độ hiển thị tương thích" / "Compatible display mode"; `DisplayCompatibleWhy`: "ShellX dùng chế độ này vì chế độ thường không mở được cửa sổ trên máy này." / "ShellX uses this mode because the standard mode couldn't open its window on this PC."; `DisplayCompatibleByEnv`: "Biến môi trường GPUI_DISABLE_DIRECT_COMPOSITION đang bật chế độ này." / "The GPUI_DISABLE_DIRECT_COMPOSITION environment variable turns this mode on."; `TryStandardDisplay` (spec verbatim): "Thử lại chế độ hiển thị thường" / "Try standard display mode again"; `TakesEffectNextStart`: "Áp dụng khi mở lại ShellX." / "Takes effect the next time ShellX opens."; `CreateDiagnosticsReport` (spec verbatim): "Tạo báo cáo chẩn đoán" / "Create Diagnostics Report".

Rules: Display (after Terminal) shows `DisplayStandard` or `DisplayCompatible` for this run (`render_status().mode`). When compatible: `DisplayCompatibleByEnv` for `UserEnvironment`; otherwise `DisplayCompatibleWhy` and the button `settings-try-standard` (Secondary), which calls `request_standard_next_start()`; on `Ok` the button is replaced by the muted `TakesEffectNextStart`, on `Err` the error is logged with `log::warn!` and the button stays. About's first line is `about_version()`. The help menu gets `CreateDiagnosticsReport` between "Check for Updates" and "Docs": it calls `spawn_report_process()`; an error is logged with `log::warn!`.

- [ ] **Step 1: Write the failing test**: `display_and_diagnostics_strings` (exact text; count + 8).
- [ ] **Step 2: Run** → compile error. Commit `test(windows): Display and diagnostics sentences [red]`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** MODEL, APP, BUILD; RUNCHECK with `P=SHELLX_DEV_PREVIEW=settings` → `0`; `grep -rn 'eprintln!' windows/shellx-app/src/ui` → nothing.
- [ ] **Step 5: Commit** `feat(windows): Settings shows the display mode and can try the standard one again; About names a test build; the help menu creates a diagnostics report`.

---

## Part B: Windows-only, start-up and GPUI patches

### Task B1: GPUI patch (a): a VK_PACKET key-up is not translated again (R2 F1)

**Files:** Modify `windows/vendor/gpui-0.2.2/src/platform/windows/events.rs` (line 1 notice; `handle_syskeyup_msg`, `handle_keyup_msg`), `windows/vendor/README.md` (row (a))

Exact change, the lines it replaces and why it cannot hurt typing that never used `VK_PACKET`: 3b §1. Win32 facts relied on: `TranslateMessage` posts characters for `WM_KEYDOWN`/`WM_SYSKEYDOWN` only; GPUI's `translate_message` (`events.rs:1285-1297`) rebuilds the message as `WM_KEYDOWN`, which is what made a key-up produce a character (R2 F1; **inferred** for real Windows, ~50 %).

- [ ] **Step 1: Red.** GPUICHECK → `gpui-0.2.2: 1 patched file(s): build.rs`; `grep -n 'VK_PACKET => {' -A3 windows/vendor/gpui-0.2.2/src/platform/windows/events.rs` → the arm calling `translate_message`, reached from both key-up handlers.
- [ ] **Step 2: Patch** exactly as 3b §1; README row (a).
- [ ] **Step 3: Verify.** GPUICHECK → `gpui-0.2.2: 2 patched file(s): build.rs src/platform/windows/events.rs`; BUILD and APP green (the Mac does not compile this file).
- [ ] **Step 4: Commit** `vendor(windows): gpui patch (a): a VK_PACKET key-up is no longer translated as a second key-down (R2 F1)`; WINCHECK → OK.

Covered by: WINCHECK (types), hands-on steps 4 and 5 (behaviour), the diagnostics `[keyboard]` section (which typing tool runs).

### Task B2: The first window fits the screen (R1 F2)

**Files:** Modify `windows/shellx-app/src/os_info.rs`, `windows/shellx-app/src/ui/app.rs` (window bounds), `windows/shellx-app/Cargo.toml` (windows-sys features `Win32_Graphics_Gdi`, `Win32_UI_HiDpi`)

**Interfaces:**
- Consumes: `first_window::{first_window, WorkArea, FirstWindow}`.
- Produces: `os_info::primary_work_area() -> Option<(f32, f32, f32)>` (width px, height px, scale; `cfg(windows)`, `None` elsewhere); `os_info::first_window_placement(work: Option<(f32, f32, f32)>) -> FirstWindow` (pure: `Some` → `first_window(WorkArea::primary_workspace(w, h, s))`; `None` → `first_window(WorkArea { x: 0.0, y: 0.0, width: 0.0, height: 0.0 })`, maximized).

Win32 (`primary_work_area`), every failure → `None` (the window opens maximized):
1. `MonitorFromPoint(POINT { x: 0, y: 0 }, MONITOR_DEFAULTTOPRIMARY)`: the primary monitor contains (0, 0) ("Positioning Objects on a Multiple Display Setup"); with `MONITOR_DEFAULTTOPRIMARY` it never returns null.
2. `GetMonitorInfoW(hmon, &mut MONITORINFO { cbSize: size_of::<MONITORINFO>() as u32, .. })` ≠ 0 → `rcWork`, the work area in virtual-screen physical pixels (the manifest makes the process PerMonitorV2).
3. `GetDpiForMonitor(hmon, MDT_EFFECTIVE_DPI, &mut x, &mut y)` = `S_OK` → scale `x as f32 / 96.0` (per-monitor aware: the real DPI).

- [ ] **Step 1: Write the failing test** (`os_info.rs`): `the_first_window_is_placed_for_the_screens_of_r1` — `(1920.0, 1008.0, 1.5)` → `FirstWindow { x: 40.0, y: 0.0, width: 1200.0, height: 672.0, maximized: false }`; `(1366.0, 720.0, 1.0)` → `(83, 0, 1200, 720, false)`; `(2160.0, 1344.0, 2.0)` → `(0, 0, 1080, 672, false)`; `(2256.0, 1408.0, 2.0)` → `(0, 0, 1128, 704, false)`; taskbar on top (rcWork height 1008, top 72) gives the first case (origin stays 0, 0); `None` → `maximized: true`.
- [ ] **Step 2: Run** APP → compile error. Commit `test(windows): the first window is placed from the primary work area [red]`.
- [ ] **Step 3: Implement.** `app.rs`: on Windows `let fw = first_window_placement(primary_work_area())`, `Bounds { origin: point(px(fw.x), px(fw.y)), size: size(px(fw.width), px(fw.height)) }`, `WindowBounds::Maximized(b)` when `fw.maximized` else `Windowed(b)`, `display_id: None`; macOS keeps `Bounds::centered(None, size(px(1200.0), px(760.0)), cx)`.
- [ ] **Step 4: Run** APP, BUILD, RUNCHECK → `0`. Commit `fix(windows): the first window fits the work area of the primary monitor (R1 F2)`. WINCHECK → OK.

Covered by: Mac test (rule and conversion), WINCHECK (Win32 calls), hands-on step 2.

### Task B3: The log file, redacted line by line (spec §4.7)

**Files:**
- Create: `windows/shellx-model/src/log_file.rs`; Modify `windows/shellx-model/src/lib.rs`
- Create: `windows/shellx-app/src/logger.rs`; Modify `main.rs` (module, install in GUI mode), `paths.rs` (`logs_dir`), `Cargo.toml` (`log = "0.4"`), `windows/Cargo.lock` (+1 line), `ui/app.rs` (fonts error → `log::warn!`), `links_store.rs:88`, `remote_session.rs:453`, `pairing_service.rs:236` (`eprintln!` → `log::warn!`)

**Interfaces:**
- Produces:

```rust
// log_file.rs (model)
pub const LOG_FILE_MAX_BYTES: u64 = 1_048_576;
pub const LOG_FILES_KEPT: usize = 3;                               // shellx.log, shellx.log.1, shellx.log.2
pub fn utc_timestamp(unix_millis: u64) -> String;                 // "2026-11-12T08:15:30.123Z"
pub fn compact_utc(unix_secs: u64) -> String;                     // "20261112-081530"
pub fn format_record(timestamp: &str, level: &str, target: &str, message: &str) -> String;
    // "<ts> <LEVEL> <target>: <first line>\n" + "  <next line>\n" per further line; every line redacted
pub struct LineDedup { /* last: Option<String>, repeats: u32 */ }
impl LineDedup { pub fn push(&mut self, key: &str, line: String, timestamp: &str) -> Vec<String>; }
    // key = level+target+message; same key → nothing written, count; the next other key (or the 1000th repeat) writes
    // "<ts> INFO shellx: the line above repeated <n> more times\n" first
// paths.rs
pub fn logs_dir() -> PathBuf;                                     // native_dir()/logs, else temp_dir()/ShellX/logs; not created
// logger.rs
pub fn install(dir: &Path) -> bool;                               // log::set_logger(&LOGGER) + set_max_level(Info); false = no log
pub fn try_append(line: &str);                                    // try_lock only; for the panic hook
```

- [ ] **Step 1: Write the failing tests**

```rust
// log_file.rs
#[test] fn utc_timestamps_are_iso_8601() { /* 0 → "1970-01-01T00:00:00.000Z"; 1_762_934_400_123 → "2025-11-12T08:00:00.123Z"; compact_utc(1_762_934_400) → "20251112-080000"; 951_782_400_000 (2000-02-29) */ }
#[test] fn records_are_one_line_per_text_line_and_redacted() {
    // format_record("T", "INFO", "gpui::platform::windows", "Using GPU: Intel(R) UHD Graphics 620") == "T INFO gpui::platform::windows: Using GPU: Intel(R) UHD Graphics 620\n"
    // a message "login failed for a@b.co\ntoken <T43>" → two lines, the second starts with two spaces, no "a@b.co", no T43
}
#[test] fn repeats_collapse_into_one_count_line() {
    // push "x" ×5 then "y" → ["x line", "…repeated 4 more times", "y line"]; 1001 × "x" → a count line after the 1001st
}
#[test] fn repeat_lines_carry_no_message_text() { /* the count line for a key holding "a@b.co" contains neither it nor the key */ }
// logger.rs (tempdir)
#[test] fn every_record_is_redacted_before_it_is_written() { /* log through the Logger's write path with a@b.co, T43, "code 123456" → file has none */ }
#[test] fn the_logger_rotates_at_one_mebibyte_and_keeps_three_files() { /* write 3.5 MiB → shellx.log, .1, .2 exist, no .3, each ≤ 1 MiB */ }
#[test] fn the_log_works_in_a_folder_with_vietnamese_and_spaces() { /* dir "Phú Lê/logs" */ }
#[test] fn an_unwritable_log_never_panics() { /* the log path is an existing directory → writes return quietly */ }
```
Tests drive the logger's write path through a `pub(crate) fn write_record(state: &mut LogState, …)` so no test installs the global logger.
- [ ] **Step 2: Run** MODEL, APP → compile errors. Commit `test(windows): log records are redacted, collapsed and rotated [red]`.
- [ ] **Step 3: Implement.** `static LOGGER` with a `Mutex<Option<LogState>>` (const-initialised); `log::Log::enabled` = level ≤ Info; `log` formats, dedups, rotates (Ruling 12: close, remove `.2`, rename `.1`→`.2`, current→`.1`, reopen; errors ignored), writes with one `write_all`; no `unwrap` anywhere. Update the lock with `(cd windows && cargo metadata --format-version 1 --offline >/dev/null)`.
- [ ] **Step 4: Run** MODEL, APP, BUILD; `git diff develop -- windows/Cargo.lock | grep '^[+-] '` → exactly `+ "log",`; RUNCHECK → `0` and `~/.local/share/shellx-native/logs/shellx.log` holds GPUI's lines.
- [ ] **Step 5: Commit** `feat(windows): a rotating log file with every line redacted (R1 F3)`. WINCHECK → OK.

### Task B4: Panics leave a crash file and a dialog from a separate reporter process (R1 F3)

**Files:**
- Create: `windows/shellx-model/src/crash_report.rs` (+ `lib.rs`); `windows/shellx-app/src/crash.rs`, `windows/shellx-app/src/build_info.rs`
- Modify: `main.rs` (reporter modes before anything else, hook install, `--crash-test`), `ui/app.rs` (no `expect` on `open_window`; crash test), `pairing_service.rs` (`execute_caught` body inside `crash::expect_caught`), `Cargo.toml` (windows-sys `Win32_System_LibraryLoader`, `Win32_System_Threading`)

**Interfaces:**
- Consumes: B3 (`logs_dir`, `try_append`, `compact_utc`), `redact`.
- Produces:

```rust
// crash_report.rs (model)
pub enum CrashFileKind { Panic, Native, WindowFailed, Diagnostics }
pub fn crash_file_name(kind: CrashFileKind, compact_utc: &str, pid: u32) -> String;   // Ruling 13 (Diagnostics has no pid)
pub struct PanicFacts { pub utc: String, pub version: String, pub commit: String, pub build: String, pub windows: String,
                        pub exe_base: Option<u64>, pub thread_id: Option<u32>, pub main_thread: bool,
                        pub location: String, pub message: String, pub backtrace: String }
pub fn panic_report(f: &PanicFacts) -> String;            // header lines + "message:" + "backtrace:", every line redacted
pub enum DialogKind { Crash, WindowFailed }
pub struct DialogText { pub title: String, pub body: String }
pub fn report_dialog(lang: Lang, kind: DialogKind, path: &str) -> DialogText;
pub fn reporter_command_line(exe: &str, flag: &str, file: &str) -> String;   // "\"<exe>\" <flag> \"<file>\""
// build_info.rs
pub fn commit() -> Option<&'static str>; pub fn label() -> Option<&'static str>; pub fn build_kind() -> &'static str; pub fn about_version() -> String;
// crash.rs
pub struct CrashContext { pub logs_dir: PathBuf, pub exe: PathBuf, pub version: String, pub commit: String, pub build: String,
                          pub windows: String, pub exe_base: Option<u64>, pub main_thread_id: Option<u32> }
impl CrashContext { pub fn this_process() -> CrashContext }
pub enum HookMode { Dialog, FileOnly }
pub fn install_panic_hook(ctx: CrashContext, mode: HookMode);     // also keeps ctx for context()
pub fn context() -> Option<&'static CrashContext>;                // OnceLock; startup::window_failed uses it
pub fn expect_caught<R>(f: impl FnOnce() -> R) -> R;
pub fn write_window_failure(ctx: &CrashContext, error: &anyhow::Error) -> Option<PathBuf>;   // start-failed file
pub fn start_reporter(ctx: &CrashContext, kind: DialogKind, file: &Path) -> bool;           // once per process
pub fn run_reporter(kind: DialogKind, file: &Path) -> i32;                                  // `--report-crash` / `--report-window`
pub enum CrashTest { Panic, Native, Window }
pub fn set_crash_test(t: Option<CrashTest>); pub fn crash_test() -> Option<CrashTest>;
```

Dialog text (`report_dialog`):
- Crash: title "ShellX gặp lỗi" / "ShellX ran into a problem"; body "ShellX gặp lỗi và đã lưu chi tiết vào:\n{path}\n\nMở thư mục chứa file này? Hãy gửi file cho đội ShellX để được giúp." / "ShellX ran into a problem and saved the details to:\n{path}\n\nOpen the folder that contains it? Send the file to the ShellX team to get help."
- WindowFailed: title "ShellX không mở được cửa sổ" / "ShellX couldn't open its window"; body "ShellX không mở được cửa sổ. Chi tiết nằm trong:\n{path}\n\nMở thư mục chứa file này? Hãy gửi file cho đội ShellX để được giúp." / "ShellX couldn't open its window. The details are in:\n{path}\n\nOpen the folder that contains it? Send the file to the ShellX team to get help." (The file says which display modes were tried.)

Reporter (`run_reporter`, Windows; a separate process, no GPUI, no hook, no log, no mutex): `MessageBoxW(null, body, title, MB_YESNO | MB_ICONERROR | MB_SETFOREGROUND)`; `IDYES` → `Command::new(<%SystemRoot%>\explorer.exe).raw_arg(format!("/select,\"{file}\""))` (paths cannot hold `"`); the language is `Lang::from_system(SHELLX_LANG, ui_language_id())`; off Windows it prints title and body to stderr. Hook details (Rulings 8, 9): payload as `&str` or `String`, else `"<non-string panic payload>"`; location from `PanicHookInfo::location()`; `Backtrace::force_capture()`; thread id `GetCurrentThreadId()` on Windows; exe base `GetModuleHandleW(null)`; write `crash.<utc>.<pid>.txt` (folder created; on error `temp_dir()`); `logger::try_append("panic: see <name>")`; in `Dialog` mode start the reporter once (`std::process::Command`, `--report-crash <file>`), unless `expect_caught` is active; then the previous hook. `--crash-test panic` panics inside a foreground task after the window opened (inside GPUI's window procedure, so the process aborts after the hook: the real path); `--crash-test window` treats the open as failed. `open_window` errors call `write_window_failure` then `start_reporter(WindowFailed)` and exit with code 1 (B6 inserts the relaunch before this). Failures: `MessageBoxW` returning 0 counts as "No"; an `explorer.exe` that does not start is ignored; a crash file that cannot be written in `logs_dir` or `temp_dir()` still starts the reporter, whose dialog then names the intended path.

Covered by: Mac tests (hook body, file names, texts, command line), WINCHECK (`MessageBoxW`, `GetCurrentThreadId`, `GetModuleHandleW`), the optional `--crash-test panic` on the PC.

- [ ] **Step 1: Write the failing tests**: model `crash_file_names_survive_the_redactor` (`u32::MAX` pid, all kinds: `redact(name) == name`), `panic_report_is_redacted_line_by_line` (planted email, T43, "code 123456" in message and backtrace → absent; `location:` and `version:` lines present), `dialog_text_names_the_file_in_both_languages`, `reporter_command_line_quotes_paths_with_spaces_and_vietnamese` (exe `C:\Users\Phú Lê\AppData\Local\Programs\ShellX Native\shellx-desktop.exe` → exactly `"C:\…\shellx-desktop.exe" --report-crash "C:\…\crash.20261112-081530.42.txt"`); app `build_info_validates_label_and_commit` (pure helpers `label_from(Option<&str>)`, `commit_from(Option<&str>, Option<&str>)`; `"test"` ok, `"Test"`, `"test-1"`, `"abcdefghijk"` → None; 40 hex ok, 39 → None; `about_version` with both → `"ShellX 1.7.0 (test 5dd1e2dc6a)"`), `the_hook_writes_a_file_and_asks_for_one_reporter` and `a_caught_panic_writes_a_file_but_starts_no_reporter` (both through `handle_panic(ctx, parts, mode, spawn: &dyn Fn(&Path) -> bool)`, the testable body, in a tempdir; the global hook is never installed in tests), `the_start_failure_file_is_redacted` (`write_window_failure` with an `anyhow` chain holding `a@b.co` and T43 → the file has `error:` and neither value).
- [ ] **Step 2: Run** → compile errors. Commit `test(windows): crash files, reporter text and command line [red]`.
- [ ] **Step 3: Implement** (exact `main` order: 3b §5).
- [ ] **Step 4: Run** MODEL, APP, BUILD, RUNCHECK → `0`; on the Mac `target/release/shellx-desktop --crash-test panic` exits within 10 s and leaves a `~/.local/share/shellx-native/logs/crash.*.txt` whose `location:` line points at the crash-test code; `target/release/shellx-desktop --report-crash "$TMPDIR/x.txt"` prints the dialog's title and body to stderr and exits 0.
- [ ] **Step 5: Commit** `feat(windows): every panic leaves a crash file and a dialog from a separate reporter process (R1 F3)`. WINCHECK → OK.

### Task B5: Native crashes (access violations, illegal instructions) leave a file too

**Files:** Create `windows/shellx-app/src/crash_native.rs` (`cfg(windows)`); Modify `crash_report.rs` (`NativeFacts`, `write_native_report`), `main.rs` (install after start-up, GUI and diagnose), `ui/app.rs` (`--crash-test native`), `Cargo.toml` (windows-sys `Win32_System_Diagnostics_Debug`, `Win32_System_Kernel`, `Win32_Storage_FileSystem`, `Win32_System_SystemInformation`, `Win32_Security`)

**Interfaces:**
- Produces: `crash_report::{NativeFacts<'a> { utc: [u16; 6], header: &'a [u8], code: u32, address: u64, module: &'a [u16], module_offset: Option<u64>, thread_id: u32 }, write_native_report(out: &mut [u8], f: &NativeFacts) -> usize}` (no allocation, never panics, truncates); `crash_native::install(ctx: &CrashContext)`.

Exact Win32 sequence, buffers, failure handling and the watchdog: 3b §2 (Ruling 10).

- [ ] **Step 1: Write the failing tests** (model): `native_report_formats_codes_addresses_module_and_time` (exact text for code `0xC0000005`, address `0x00007FF6A1B2C3D4`, module `C:\Users\Phú Lê\…\shellx-desktop.exe`, offset `0x1B2C3D4`, thread 4242, utc 2026-11-12 08:15:30); `native_report_never_overruns_its_buffer` (buffers of 0, 10, 100 bytes; a module of 4 000 UTF-16 units; lone surrogates → U+FFFD).
- [ ] **Step 2: Run** → compile errors. Commit `test(windows): the native crash report formatter [red]`.
- [ ] **Step 3: Implement** as 3b §2.
- [ ] **Step 4: Run** MODEL, APP, BUILD, RUNCHECK → `0`. Commit `feat(windows): crashes that are not panics leave a minimal crash file and the same dialog (R1 F3)`. WINCHECK → OK.

Covered by: Mac tests (formatter), WINCHECK (Win32), optional `--crash-test native` on the PC (see the hands-on section).

### Task B6: Compatible display mode, the start marker and the installer mutex (R1 F4, F9)

**Files:** Create `windows/shellx-model/src/start_guard.rs` (+ `lib.rs`), `windows/shellx-app/src/startup.rs`; Modify `main.rs`, `ui/app.rs` (first frame, open failure, orderly quit)

**Interfaces:**
- Produces:

```rust
// start_guard.rs (model)
pub const APP_MUTEX_NAME: &str = "ShellXNative-D322DA97-3B0D-49C7-BDB2-8EBFADBA1004";
pub enum RenderMode { Standard, Compatible }            // serde "standard" | "compatible"
pub enum StartReason { Default, Remembered, UserEnvironment, RetryAfterOpenFailed, PreviousStartDied }
pub struct StartInput { pub remembered: RenderMode, pub env_forces_compatible: bool, pub is_retry: bool,
                        pub stale_marker: Option<RenderMode>, pub other_instance: bool }
pub struct StartPlan { pub mode: RenderMode, pub reason: StartReason, pub write_marker: bool }
pub fn plan_start(input: &StartInput) -> StartPlan;                          // Ruling 7
pub enum OpenFailed { RelaunchCompatible, Report }
pub fn on_open_failed(plan: &StartPlan) -> OpenFailed;
pub fn remember_after_first_frame(plan: &StartPlan, remembered: RenderMode) -> Option<RenderMode>;
// startup.rs
pub struct StartPaths { pub marker: PathBuf, pub render: PathBuf }
pub fn plan_gui_start(paths: Option<&StartPaths>, env_forces_compatible: bool, is_retry: bool, other_instance: bool) -> (StartPlan, RenderMode);
                                                                              // reads render.json + marker, writes the marker
pub fn acquire_app_mutex() -> bool;                                           // true = another instance; Windows only (false elsewhere)
pub fn first_frame_drawn(); pub fn orderly_quit(); pub fn window_failed(error: &anyhow::Error) -> !;
pub fn render_status() -> RenderStatus; pub fn request_standard_next_start() -> std::io::Result<()>;
```

`startup` keeps the plan, the remembered mode and whether this start wrote the marker in a `OnceLock`, which `first_frame_drawn`, `window_failed`, `render_status` and the Settings button read. Windows-sys features: `Win32_System_Threading` and `Win32_Security` (added by B4 and B5).

Win32 (`acquire_app_mutex`): `CreateMutexW(null, FALSE, APP_MUTEX_NAME as UTF-16)`; non-null → keep the handle for the process lifetime (stored as `usize` in a static, never closed); `GetLastError() == ERROR_ALREADY_EXISTS (183)` → another instance ("If the mutex is a named mutex and the object existed before this function call … GetLastError returns ERROR_ALREADY_EXISTS", CreateMutexW docs). Null → log the error, return false. Created only in GUI mode (spec: diagnose and reporter do not hold it). The start sequence, the env var's `unsafe` precondition (no thread yet) and the relaunch: 3b §5.

- [ ] **Step 1: Write the failing tests**

```rust
// start_guard.rs
#[test] fn start_plan_follows_the_rules_in_order() {
    // retry+anything → (Compatible, RetryAfterOpenFailed, write_marker true); env → (Compatible, UserEnvironment);
    // other_instance with stale Standard → (remembered, Remembered|Default, write_marker false);
    // stale Standard → (Compatible, PreviousStartDied); stale Compatible + remembered Compatible → (Standard, PreviousStartDied);
    // none → (Standard, Default) or (Compatible, Remembered)
}
#[test] fn open_failure_relaunches_once_then_reports() { /* Standard non-retry → RelaunchCompatible; retry → Report; Compatible remembered → Report */ }
#[test] fn only_a_rescue_is_remembered() { /* RetryAfterOpenFailed/PreviousStartDied with mode ≠ remembered → Some(mode); Default, Remembered, UserEnvironment → None */ }
// startup.rs (tempdir; the tests call the path-taking forms plan_gui_start and first_frame_in(paths, &state);
// the process-wide functions only add the OnceLock)
#[test] fn a_start_writes_the_marker_and_the_first_frame_clears_it() {
    // nothing on disk → (Standard, Default); starting.json == {"pid":<this pid>,"mode":"standard"}; first frame → no starting.json, no render.json
}
#[test] fn a_stale_marker_starts_compatible_and_the_first_frame_remembers_it() {
    // starting.json {"pid":1,"mode":"standard"} → (Compatible, PreviousStartDied); first frame → render.json == {"mode":"compatible"}
}
#[test] fn another_instance_leaves_the_marker_alone() {
    // same marker + other_instance → remembered mode, write_marker false, starting.json unchanged byte for byte, also after first frame
}
#[test] fn a_retry_writes_its_own_marker_and_never_relaunches() {
    // is_retry → (Compatible, RetryAfterOpenFailed), starting.json mode "compatible"; on_open_failed → Report
}
#[test] fn an_unreadable_marker_counts_as_a_failed_standard_start() { /* starting.json "garbage" → (Compatible, PreviousStartDied) */ }
```
- [ ] **Step 2: Run** → compile errors. Commit `test(windows): start rules for the compatible display mode [red]`.
- [ ] **Step 3: Implement** (3b §5); log each decision (`render mode: compatible (previous start died before its first frame)` and the like).
- [ ] **Step 4: Run** MODEL, APP, BUILD. RUNCHECK → `0`, and afterwards `~/.local/share/shellx-native/starting.json` does not exist (the first frame cleared it before the kill) and neither does `render.json`. Then the stale-marker path, end to end on the Mac (the variable has no effect on macOS, the logic runs): `printf '{"pid":1,"mode":"standard"}' > ~/.local/share/shellx-native/starting.json`, RUNCHECK → `0`; `grep 'render mode' ~/.local/share/shellx-native/logs/shellx.log | tail -1` → `render mode: compatible (previous start died before its first frame)`; `cat ~/.local/share/shellx-native/render.json` → `{"mode":"compatible"}`; then `rm ~/.local/share/shellx-native/render.json`.
- [ ] **Step 5: Commit** `feat(windows): compatible display mode when the standard renderer fails, remembered once it rescued a start; the installer's mutex (R1 F4, F9)`. WINCHECK → OK.

Covered by: Mac tests and the Mac stale-marker run (all decisions and files), WINCHECK (`CreateMutexW`), the optional `--crash-test window` on the PC (relaunch, first frame, memory), the installer extra (`AppMutex`). Whether GPUI's composition path fails on a given PC stays unknown until it happens there; the log then says `render mode: compatible (…)`.

### Task B7: GPUI patch (b): the vsync thread never divides by zero (R1 F6)

**Files:** Modify `windows/vendor/gpui-0.2.2/src/platform/windows/vsync.rs`, `windows/vendor/README.md`, `windows/shellx-model/src/diagnose.rs` (`vsync_check`, the mirror for the report)

**Interfaces:** Produces `diagnose::{VsyncCheck { pub interval_us: u64, pub unpatched_divides_by_zero: bool }, vsync_check(qpc_refresh_period: u64, qpc_frequency: u64, rate_numerator: u32, rate_denominator: u32) -> VsyncCheck}`.

- [ ] **Step 1: Write the failing test** (model): `vsync_check_matches_gpui_0_2_2` — `(166_667, 10_000_000, 60, 1)` → `{16_666, false}`; `(166_833, 10_000_000, 60_000, 1001)` → `{16_683, false}`; `(41_667, 10_000_000, 240, 1)` → `{4_166, false}`; `(60, 10_000_000, 60, 1)` (the 29 µs case GPUI's comment cites: rate fallback) → `{16_666, true}`; `(0, 10_000_000, 0, 0)` → `{16_666, true}` (default interval); `(166_667, 500_000, 60, 1)` (QPC under 1 MHz) → `{16_666, true}`. `interval_us` truncates (`as_micros`).
- [ ] **Step 2: Run** MODEL → compile error. Commit `test(windows): the report can tell whether GPUI's vsync would divide by zero [red]`.
- [ ] **Step 3: Patch** vsync.rs exactly as 3b §3 (red first: `grep -n 'counts / ticks_per_microsecond' …vsync.rs` → one match); README row (b); implement `vsync_check` with the unpatched arithmetic for the flag and the patched one for the interval.
- [ ] **Step 4: Run** MODEL; GPUICHECK → `gpui-0.2.2: 3 patched file(s): build.rs src/platform/windows/events.rs src/platform/windows/vsync.rs`; BUILD, APP.
- [ ] **Step 5: Commit** `vendor(windows): gpui patch (b): the vsync thread no longer divides by zero when DWM reports a period under 1 ms (R1 F6)`. WINCHECK → OK.

Covered by: the Mac test (the mirror's arithmetic, both the unpatched flag and the patched interval), WINCHECK (the patch), and on the PC the report's `[gpu]` DWM line, which says whether that PC would have hit the bug.

### Task B8: GPUI patch (c): a lost GPU device no longer crashes the window (R1 F5)

**Files:** Modify `windows/vendor/gpui-0.2.2/src/platform/windows/directx_renderer.rs`, `windows/vendor/README.md`

- [ ] **Step 1: Red.** `grep -n 'render_target_view\[0\].take().unwrap()\|render_target_view\[0\].as_ref().unwrap()\|let disable_direct_composition = self.direct_composition.is_none()' …directx_renderer.rs` → three matches (the panics and the derived mode R1 F5 names).
- [ ] **Step 2: Patch** exactly as 3b §4 (Ruling 33); README row (c).
- [ ] **Step 3: Verify.** The grep → nothing; GPUICHECK → `gpui-0.2.2: 4 patched file(s): build.rs src/platform/windows/directx_renderer.rs src/platform/windows/events.rs src/platform/windows/vsync.rs`; BUILD, APP.
- [ ] **Step 4: Commit** `vendor(windows): gpui patch (c): a failed resize or device-lost recovery leaves no dropped render target and releases nothing twice (R1 F5)`. WINCHECK → OK.

Covered by: WINCHECK only; behaviour needs a GPU reset on the PC (not in the 10 steps; "What stays unverified").

### Task B9: Console output for flags, and `--diagnose` (R1 F12, spec §4.7)

Needs A1 on `develop` (merge first).

**Files:**
- Create: `windows/shellx-app/src/console.rs`, `windows/shellx-app/src/diagnose_run.rs`
- Modify: `main.rs` (console attach, `--diagnose [--no-open]`, `--version` print), `smoke.rs` (`shell_checks`), `os_info.rs` (`os_version` via `RtlGetVersion`, Ruling 28), `windows/shellx-model/src/diagnose.rs` (`typing_tools`, `chosen_gpu_from_log`, `probe_script`), `Cargo.toml` (`windows = { version = "0.61", features = ["Win32_Graphics_Dxgi", "Win32_Graphics_Dxgi_Common", "Win32_Graphics_Direct3D", "Win32_Graphics_Direct3D11"] }` under `cfg(windows)`; windows-sys `Win32_System_Console`, `Wdk_System_SystemServices`, `Win32_Graphics_Dwm`, `Win32_System_Performance`, `Win32_System_Diagnostics_ToolHelp`, `Win32_UI_Input_KeyboardAndMouse`), `windows/Cargo.lock` (+1 line). Why `windows`: adapter enumeration and the feature-level probe are COM interfaces, which windows-sys does not wrap; GPUI already enables these features, so nothing new compiles.

**Interfaces:**
- Consumes: A1 seams; B3 (`logs_dir`, `compact_utc`); B4 (`CrashContext`, `crash_file_name`); B6 (`render_status`); B7 (`vsync_check`); foundations `diagnose::{DiagnosticsReport, format_report, LOG_TAIL_LINES}`, `first_window`.
- Produces: `console::attach_parent_console()`; `diagnose_run::{run(open_folder: bool) -> i32, spawn_report_process() -> std::io::Result<()>}`; `smoke::shell_checks(cmd: &ShellCmd, step_timeout: Duration) -> Vec<Check>`; `diagnose::{typing_tools(exe_names: &[String]) -> Vec<String>, chosen_gpu_from_log(lines: &[String]) -> Option<String>, ProbeScript, probe_script(kind: Option<ShellKind>) -> Option<ProbeScript>}`.

Console (Ruling 29): `GetStdHandle(STD_OUTPUT_HANDLE)` null or `INVALID_HANDLE_VALUE` → `AttachConsole(ATTACH_PARENT_PROCESS)` (fails without a parent console: ignored); then for `STD_OUTPUT_HANDLE` and `STD_ERROR_HANDLE` still missing: `CreateFileW("CONOUT$", GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, null, OPEN_EXISTING, 0, null)` ("CONOUT$" opens the attached console's active screen buffer, CreateFileW documentation, "Consoles") and `SetStdHandle`; a failed call leaves that handle missing, and prints are dropped as they are today. Rust's stdout asks `GetStdHandle` on each write, so later prints reach the console. Every probe of the report, its Win32 calls and its failure text: 3b §6. The report is written to `logs_dir()/diagnostics.<utc>.txt`, the path is printed (`writeln!`, error ignored), then `explorer.exe /select,"<file>"` unless `--no-open`. Each probe runs inside `crash::expect_caught(|| catch_unwind(…))`, so one failing probe writes `failed: <panic message>` in its own line and the report still completes. Exit 0 when the file was written, else 1.

- [ ] **Step 1: Write the failing tests**: model `typing_tools_are_found_by_exe_name` (`["UniKeyNT.exe", "explorer.exe", "EVKey64.exe"]` → `["UniKeyNT.exe", "EVKey64.exe"]`; list: `unikeynt.exe`, `unikey.exe`, `evkey64.exe`, `evkey32.exe`, `evkey.exe`, `openkey64.exe`, `openkey32.exe`, `openkey.exe`, `gotiengviet.exe`, case-insensitive), `chosen_gpu_is_the_last_adapter_tried_before_the_device_was_created`, `probe_scripts_exist_for_powershell_and_cmd_only`; app `the_report_names_only_the_sign_in_method` (session JSON with an email → `sign_in == "signed in with google"`), `the_log_tail_reads_across_rotation` (150 lines in `.1`, 100 in `shellx.log` → 200 lines, oldest first), `crash_files_are_listed_newest_first_by_name`, `os_version_is_never_unknown`.
- [ ] **Step 2: Run** → compile errors. Commit `test(windows): diagnostics helpers [red]`.
- [ ] **Step 3: Implement**; `--version` uses `writeln!` with the error ignored.
- [ ] **Step 4: Run** MODEL, APP, BUILD; on the Mac `target/release/shellx-desktop --diagnose --no-open` prints `Diagnostics report: <path>`, exits 0, and the file has the 12 section headers, `none`/`unknown` for the Windows-only probes, a `[shells]` check of bash, and an `[account]` line that is `sign-in: signed out` or `sign-in: signed in with <method>`; `git diff develop -- windows/Cargo.lock | grep '^[+-] '` → `+ "log",` and `+ "windows",` only.
- [ ] **Step 5: Commit** `feat(windows): --version, --smoke and --diagnose print to the console; --diagnose writes a redacted report and opens its folder (R1 F12)`. WINCHECK → OK.

Covered by: Mac tests and the Mac `--diagnose` run (format, redaction, shell checks, account and relay lines), WINCHECK (console, DXGI/D3D11, DWM, monitors, keyboard, Toolhelp, `RtlGetVersion`), the PC (the report attached to any failed step; `--version` in cmd as an extra).

### Task B10: The exe's version information, the installer's mutex and diagnostics shortcut, baseline CPU, the test label (spec §4.6)

**Files:** Create `windows/shellx-app/src/exe_resource.rs`; Modify `windows/shellx-app/build.rs`, `resources/shellx.rc`, `main.rs` (`#[cfg(test)] mod exe_resource;`), `windows/installer/shellx-native.iss`, `windows/shellx-model/src/start_guard.rs` (test), `windows/cross/build-in-container.sh`, `scripts/shellx/release/build-windows-cross.sh`, `.github/workflows/shellx-windows.yml`

**Interfaces:** Produces `exe_resource::version_resource(version: &str) -> Option<String>` (None unless `x.y.z` digits); exact lines of every file: 3b §7.

- [ ] **Step 1: Write the failing tests**: `exe_resource::tests::the_version_resource_names_shellx_and_the_version` (`"1.7.0"` → contains `FILEVERSION 1,7,0,0`, `PRODUCTVERSION 1,7,0,0`, `VALUE "CompanyName", "ShellX"`, `VALUE "FileDescription", "ShellX"`, `VALUE "ProductName", "ShellX"`, `VALUE "OriginalFilename", "shellx-desktop.exe"`, `VALUE "FileVersion", "1.7.0"`, `VALUE "ProductVersion", "1.7.0"`, `VALUE "Translation", 0x409, 1200`; `"1.7"` and `"1.7.0-test"` → None); `start_guard::tests::the_installer_names_the_app_mutex_and_the_diagnostics_entry` (`include_str!("../../installer/shellx-native.iss")` contains `AppMutex=ShellXNative-D322DA97-3B0D-49C7-BDB2-8EBFADBA1004`, `Parameters: "--diagnose"`, `vietnamese.DiagnoseShortcut=ShellX – Chẩn đoán`, `english.DiagnoseShortcut=ShellX – Diagnostics`).
- [ ] **Step 2: Run** → red. Commit `test(windows): version resource and installer entries [red]`.
- [ ] **Step 3: Implement** 3b §7.
- [ ] **Step 4: Run** MODEL, APP, BUILD; `python3 -I -m unittest discover -s windows/installer -v` → OK; `bash -n` on both scripts → nothing; `grep -c CMUX_GHOSTTY_VT_ZIG_CPU windows/cross/build-in-container.sh .github/workflows/shellx-windows.yml` → `1` each.
- [ ] **Step 5: Commit** `build(windows): version information in the exe, AppMutex and a diagnostics Start entry in the installer, baseline CPU for libghostty-vt everywhere, labelled test installers (R1 F1, F8, F9)`. WINCHECK → OK (this runs `build.rs` and llvm-rc on the new include).

Covered by: Mac tests, WINCHECK (resource compile through llvm-rc), the test-installer build (group 5: ISCC under wine), hands-on step 1 (Properties › Details).

---

## What the hands-on list must show (spec §5.3)

| Step | Validates | If it fails, the diagnostics report shows |
| --- | --- | --- |
| 1. Install | B10 (setup version info, `AppMutex`, "ShellX – Chẩn đoán" entry); exe Properties › Details shows ShellX 1.7.0 | `[app]` version, commit, label |
| 2. Open: whole window, prompt visible | B2, A1 (PowerShell 7 or Windows PowerShell starts), B6 (a renderer failure is rescued), B7 (the window repaints) | `[displays]` work area and first window, `[gpu]` render mode, DWM timing, `[shells]` |
| 3. `dir` + Enter | A1 (shell), B7 (output appears without a resize) | `[shells]` checks, `[gpu]` `would divide by zero` |
| 4. Unikey/EVKey Telex `aa dd tieengs` → `â đ tiếng` | B1 (patch a) | `[keyboard]` layouts, input methods, typing tools running |
| 5. Windows Telex IME | no regression from B1 (key-down path unchanged) | `[keyboard]` |
| 6. `1..500`, touchpad then wheel | A3 | (none: say what moved) |
| 7. Right-click one line; three lines ask first | A4, A5 | (none) |
| 8. Alt+Shift+= splits; Alt+F4 closes | foundations' `map_key` (already wired by `TermView`), A4 (overlay) | (none) |
| 9. Settings › Terminal: change shell, new tab | A6, A1 (stored choice, plan), A2 (failure UI if it does not start) | `[shells]` found, chosen, checks |
| 10. Settings › Account › Sign in | the sign-in plan; A9 if a request fails later | `[account]`, `[relay]` |

Optional extras for the coordinator to ask once (each proves a path no step reaches): `shellx-desktop.exe --crash-test panic` (crash file + dialog), `--crash-test native` (native file + dialog), `--crash-test window` (relaunch in compatible mode, then Settings › Display shows it and "Thử lại chế độ hiển thị thường"), `shellx-desktop.exe --version` in cmd (console output), running the installer while ShellX is open (the `AppMutex` prompt).

**Stays unverified even after the 10 steps:** patch (c) (needs a GPU reset: sleep/resume, driver update, RDP resolution change); patch (b) unless that PC's DWM reports a period under 1 ms (the report says whether it would have); the native crash filter and the reporter (unless the extras run); the rc.exe resource path (CI only); log rotation at 1 MiB and two-instance interleaving; the update-overlay key rule (no forced update in production); a Store-installed PowerShell 7 alias (unless that PC has one); an offline network PATH entry; Git Bash and WSL starts (unless installed); right-click focus with several regions beyond step 7.

## Inferred, and not planned

Inferred (with how the evidence will show it):
- GPUI's forged `WM_KEYDOWN` on a `VK_PACKET` key-up is what doubles Unikey characters, and Unikey/EVKey send down/up pairs (R2 F1) → step 4.
- `std::fs::symlink_metadata` reports an App Execution Alias as a file (Ruling 17) → the report's `[shells]` on a PC with Store PowerShell 7.
- Rust calls the panic hook before the abort for a panic inside GPUI's window procedure → `--crash-test panic`.
- An access violation on the UI thread reaches the top-level filter (not swallowed by a kernel callback; the manifest has no `supportedOS`, which matters only for exceptions inside kernel callbacks) → `--crash-test native`.
- `AttachConsole` plus `CONOUT$` makes `--version` print in cmd and PowerShell (cmd shows the next prompt first) → the extra above.
- `D3D11CreateDevice` with GPUI's arguments on each adapter reports the same feature level GPUI gets → the report's `[gpu]` against the log's `Created device with` line.
- Inno's `AppMutex` sees a session-namespace mutex created by the app → the installer extra.
- rc.exe finds `shellx-version.rc` through `/I OUT_DIR` (Ruling 26) → the first CI run, if Actions returns.
- The Unikey/EVKey/OpenKey process names in `typing_tools`.
- 2 s is enough for the first shell probe on a normal PC (Ruling 16) → `[shells]` timing in the report.

Not planned, and why: the download page and SmartScreen help (group 6); signing; the test installer build and the 10 steps (group 5); spec §7 items (the zig link memory check of §7.1 among them); R2 F19 (focus after the update overlay disappears) and R1 F7, F10, F11, F13, F14 (not in the spec's groups 3–4); upstream Zed fixes for (a), (b), (c), which cannot be read on this machine (only gpui 0.2.2 is in the cargo registry).

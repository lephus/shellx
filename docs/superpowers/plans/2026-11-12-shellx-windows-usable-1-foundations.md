# ShellX for Windows, Usable: Part 1 Foundations (Tooling and Pure Rules) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the Windows sign-in blocker, give the Windows app its pure rules (window size, input, shell, honest machine list, error sentences, diagnostics), and build the tools the later Windows-only work needs (a compile-for-Windows command and a vendored, patchable gpui), all tested on this Mac.

**Architecture:** Two independent parts on two branches. Part T (tooling) adds a Docker check image and command, guards for the VPS cross build, and a pristine copy of gpui 0.2.2 under `[patch.crates-io]` with the shader-build patch (d). Part L (rules) adds pure functions to `windows/shellx-model` (no GPUI), makes `shellx-core` forward `can_host`, puts the relay's answer shapes and request rules in one file under `relay/` that both the relay test and a core test read, and reshapes the fake relay to match. Nothing is wired into the window; later plans call the functions listed under "Interfaces for the later plans".

**Tech Stack:** Rust 2024 (`windows/` workspace, rust-version 1.91; toolchain 1.95.0 in containers), serde/serde_json, shellx-core + `shellx-fake-api` (tiny_http), TypeScript + vitest (relay), Docker (arm64 here, x86_64 on the VPS), cargo-xwin 0.23.1, zig 0.16.0, clang/lld/llvm 18.

**Spec:** `docs/superpowers/specs/2026-11-12-shellx-windows-usable-design.md` (Vietnamese; binding). This plan covers §6 groups 0 and 1 only. Evidence: `.superpowers/sdd/2026-11-11-windows-usable/` (R1–R5, `progress.md`), cited as "R2 F5" etc.

## Global Constraints

- Every rule is a pure function in `shellx-model` (or `shellx-core`) with tests that run on this Mac; `shellx-app` only wires (spec §4 "Nguyên tắc chung").
- No new external crate that is not already in `windows/Cargo.lock` or `shellx-core/Cargo.lock`; Part L adds no dependency at all, so it never changes `windows/Cargo.lock` or `shellx-core/Cargo.lock`.
- gpui stays `=0.2.2`; the copy lives in `windows/vendor/` with its Apache-2.0 licence kept; the first commit is the unmodified crate; each patch is its own commit with its reason; every modified gpui file carries a "Modified by ShellX" notice (Apache-2.0 §4(b)); `windows/Cargo.lock` changes by exactly one entry (gpui loses `source` and `checksum`).
- Patches (a), (b), (c) are NOT in this plan; patch (d) is.
- `shellx-core` changes keep the Mac app working: `swift test --package-path Packages/Shared/ShellXBrand` passes after any change to what `machines.list` returns. Nothing under `Packages/` or `Sources/` changes.
- Relay: only `relay/contract/` (new) and one new relay test; no relay behaviour change. No code compiled in the cross-build container reads `relay/` (the container has only `windows`, `cmux-tui`, `shellx-core`).
- Window builds on this Mac are release builds only (`--release`); a debug build of the window crashes at start.
- The version inside the app stays plain `x.y.z` (`1.7.0`).
- VPS (`ssh higio-vps`, shared with production): at most 4 CPUs and 10 GB per build, check free disk before every run and keep 4 GB free for deploys, never two builds at once, touch only ShellX's build directory and ShellX's own `shellx-winbuild*` images and volumes.
- No deploy, no release, no signing, no push to `main`; nothing depends on a GitHub Actions run.
- Failing test first, then code, then commit, per task. Bug fixes (L2, L9) commit the red test before the fix and record the same command's red and green output (`CLAUDE.md`).
- Branches from `develop`: `feat/shellx-windows-usable-tooling` (Part T, worktree `.worktrees/windows-usable-tooling`), `feat/shellx-windows-usable-rules` (Part L, worktree `.worktrees/windows-usable-rules`). Commit on the branch; do not push or merge (the orchestrator merges `--no-ff` into `develop` after review).
- New user-facing sentences come in Vietnamese and English, in the voice of the existing `strings.rs` entries.

## Review Focus

Inputs a person will meet that no task's main tests would otherwise exercise; each has a test in its owning task.

1. **A relay list item with an odd optional value** (`can_host: null`, `"true"`, `1`; `fingerprint: 42`): the list must still parse and `can_host` reads false. This is exactly Blocker 1's class: one unexpected value in `GET /v2/machines` stopped every sign-in. Tests: L4 `list_survives_odd_can_host_values`, L5 `can_host_reads_true_only_for_json_true`, L2 `null_absent_or_odd_fingerprint_reads_as_empty`.
2. **`SHELLX_SHELL` values people already use**: an unquoted path with spaces that worked before (`C:\Program Files\Git\bin\bash.exe`), a quoted path with arguments, a bare name on PATH (`pwsh`). Each must start the intended program. Test: L12 `shellx_shell_keeps_old_values_working`.
3. **Secrets in the shapes real log lines have**: a token inside JSON quotes, after `Bearer `, in a URL query; a 6-digit code in `?code=123456&state=`; a panic message over two lines. And readable things that must survive: Vietnamese Windows paths, machine UUIDs, a 40-hex commit, GPU driver versions. Tests: L14 `redacts_secrets_in_json_urls_and_headers`, `keeps_paths_ids_and_versions_readable`.
4. **A work area whose origin is not (0, 0)**: taskbar on the left or top, or the window opening on a monitor left of the primary (negative x). The first window must land inside that area. Test: L7 `first_window_stays_inside_a_work_area_that_does_not_start_at_zero`.
5. **A stale verdict from the compile check**: `git archive` stamps files with the commit time, so a kept cargo cache can skip a changed file whose commit is older than the last check. Test: T1 Step 4 runs the red probe after a green run on the same cache.

---

## The two parts, ownership and collisions

| Path | Owner | Notes |
| --- | --- | --- |
| `windows/Cargo.toml`, `windows/Cargo.lock` | Part T | Part L adds no dependency, so it never edits either. If Part L ever sees `Cargo.lock` change, it stops and reports. |
| `windows/shellx-app/Cargo.toml` | Part T | Neither part plans an edit (the patch entry goes in the workspace root). |
| `windows/vendor/**`, `windows/cross/**`, `scripts/shellx/check-windows-build.sh`, `scripts/shellx/release/build-windows-cross.sh`, `.gitattributes` | Part T | |
| `windows/shellx-model/**` | Part L | |
| `windows/shellx-app/src/core_service.rs` (tests), `shell_info.rs`, `remote_tabs.rs` (test literal), `cwd.rs` (tests) | Part L | Only test code and one struct literal (`can_host: false`), needed so `shellx-app` keeps compiling and its tests keep meaning what they say. |
| `shellx-core/**` (incl. `fake-api`), `relay/contract/**`, `relay/test/desktop-contract.test.ts`, `scripts/shellx/remote-e2e/harness.py` | Part L | The harness sends `os_version="e2e"`, which the real relay refuses; L3 changes it. |

Where they can still collide: no file is edited by both. Semantically, Part T's proof that `cargo test --release --locked -p shellx-app` passes is made against registry-free gpui on its branch, and Part L adds `shellx-app` tests on its branch. Whichever branch merges into `develop` second re-runs, on the merge result: `cargo test --locked -p shellx-model`, `cargo test --release --locked -p shellx-app`, `scripts/shellx/check-windows-build.sh`. Both parts build `ghostty` from the main checkout's submodule through `CMUX_GHOSTTY_SRC`; zig's cache there takes concurrent builds.

## Rulings (where the spec was silent or the code disagreed)

1. The compile check uses cargo's dev profile (`cargo xwin check`). In that profile gpui compiles no shaders (`build.rs` `#[cfg(not(debug_assertions))] compile_shaders()`, `directx_renderer.rs:1557` includes `shaders_bytes.rs` only without debug assertions), so no fifth gpui patch is needed to skip wine (spec §5.2 assumed the copy would have to allow it).
2. Sources reach every check and build with fresh modification times (`tar -m`): `git archive` stamps files with the commit time, which can make a kept cargo cache skip a changed file.
3. `windows/Cargo.toml` gets `exclude = ["vendor"]`: path dependencies inside a workspace directory become members, which would put gpui's dev-dependencies into `Cargo.lock` and gpui into `cargo fmt`/`cargo test` runs.
4. The copy is `windows/vendor/gpui-0.2.2/`, the exact contents of `gpui-0.2.2.crate` (sha256 `979b45cfa6ec723b6f42330915a1b3769b930d02b2d505f9697f8ca602bee707`, the checksum in today's `windows/Cargo.lock`), including `Cargo.toml.orig`, `.cargo_vcs_info.json` and its `Cargo.lock`. Provenance (`README.md`) and the checker (`check-gpui.sh`) live beside it, not inside it.
5. Apache-2.0 notice: the first line of each modified gpui file is `// Modified by ShellX: <one-line reason>. See windows/vendor/README.md.` `check-gpui.sh` fails unless "differs from the crate" and "carries the notice" are the same set of files.
6. `build-windows-cross.sh` reads `${SHELLX_VPS_SSH_OPTS-…}` (no colon) so an explicitly empty value really means "no options" (today `:-` falls back to the ControlMaster path).
7. VPS guards: refuse to start with less than 14 GiB free in the build user's home (4 kept for deploys plus up to 10 for the image, caches and target), refuse while a container named `shellx-winbuild-run` runs, and use that one name for every run. 14 is a guess (see the end).
8. `MachineInfo.fingerprint` stays a `String`; null, absent or non-string reads as `""`. Struct literals elsewhere then do not change. `can_host` reads true only for JSON `true`, in both the core and the model.
9. The fake relay's key option is a runtime toggle `FakeApi::set_list_machine_keys(true)` (the style of `set_list_all_pairings`). `list_never_falls_back_to_the_server_fingerprint` is left as it is: it passes in both shapes and means more in the real one.
10. The single source is `relay/contract/desktop-api.json` (format in L3). The core reads it at test run time from `shellx-core/tests/relay_contract.rs`; `fake-api` never compiles it in, so the cross-build container never needs `relay/`.
11. The contract pins status codes too, so the fake answers 201 for a first `POST /v2/machines` and 204 with no body for a heartbeat, and adopts the relay's machine rules (platforms `macos|windows`, name length in UTF-16 units after trim, key in standard or url-safe base64, the version patterns). Tests and the remote e2e harness that send versions the relay refuses change to valid ones.
12. The end-to-end Windows sign-in test lives in `shellx-app` (`core_service.rs` tests, which already have the `drive` helper), the only crate that links both the real core and the model. It uses the password route: the model has no email events yet (the email-first plan adds them), and every route reaches the same `machines.list` step.
13. "Today's code" for the red end-to-end test means today's model with the reshaped fake (L1). Against today's fake, which sends a key, it is green; that is how Blocker 1 hid.
14. `build_groups` keeps its signature and applies the relay rule; `build_groups_with(…, OfferRule)` takes the override. An online machine that cannot host gets `RowAction::None`; a machine with a granted link stays `Open`, a pending one `ShowCode`.
15. The environment override is `SHELLX_OFFER_ALL_MACS`; only the value `1` (after trimming) turns it on.
16. Failure sentences reuse the catalog wording of the paused email-first plan for `ServerProblem`, `RateLimited` and `SignInUnavailable`. `not_found`, `http_404`, `not_configured`, `email_sign_in_disabled` and `password_sign_in_removed` read as `SignInUnavailable` ("…chưa dùng được…", which spec §5.3 step 10 asks for before the new relay is live); `network` as `RelayUnreachable`; `switch_from_signed_in_device` as `SwitchFromSignedInDevice`; anything else as `ServerProblem`. `google_error` falls back to it instead of printing the code.
17. `can_sign_out()` is true in `LoggedIn`, and in `Error` once the core has shown that a session exists (a login or Google sign-in succeeded, a list answered anything but `not_logged_in`/`unauthorized`/`http_401`, or a register answered).
18. First window: shrink 1200×760 to the work area; maximized when the shrunk size is below 720×420 or the work area is not finite or not positive; centred with floored offsets; all in logical pixels.
19. Scroll accumulator: `f64` remainder, truncate toward zero with a 1e-6 tolerance, drop the remainder on a sign change, ignore non-finite input, at most ±1000 lines per event.
20. Alternate screen with mouse reporting on: the wheel does nothing (ShellX does not encode mouse events, R3 m5); on the primary screen the wheel always scrolls back.
21. Middle click on the focused pane does nothing; right click on the focused pane copies when there is a selection, else pastes.
22. Multi-line: a newline is `\n` or `\r`; whitespace is `char::is_whitespace`.
23. Split shapes: `(alt, no shift, "+")` and `(alt, no shift, "_")` split, as GPUI-Windows reports Alt+Shift+= and Alt+Shift+- (R2 F5). Unshifted `Alt+=` and `Alt+-` stay chords. Side effect: Alt with an unshifted `+` key (German layout, numpad plus) also splits.
24. Alt+F4 and Alt+Space return `Ignore` only with exactly Alt held (no Ctrl, Shift or Win).
25. Shells: Auto order is PowerShell 7 (PATH first, then `%ProgramFiles%\PowerShell\7\pwsh.exe`), Windows PowerShell at its absolute path, Command Prompt (`%ComSpec%`, else `%SystemRoot%\System32\cmd.exe`). Git Bash runs `bin\bash.exe --login -i`, WSL `wsl.exe` with no arguments. The fallback is the next Auto shell, once. A chosen shell that is no longer found uses the Auto plan. `SHELLX_SHELL`: a whole value that names an existing file is that program with no arguments (today's behaviour); otherwise it is parsed as a command line.
26. Command lines follow `CommandLineToArgvW` for the program and the msvcrt (2008+) rules for arguments, except that an unclosed quote is an error to show (Windows would accept it).
27. The prompt hook percent-encodes each path segment with `[uri]::EscapeDataString` and keeps `[Console]::Write`; R3's prompt-string variant (for Constrained Language Mode) is not adopted, the spec does not ask for it.
28. Debug formatting also hides machine and device names (`MachineInfo.name`, `SignInMethod.linked_via_device_name`): the spec's "never" list includes other machines' names, which no redactor pattern can catch.
29. The diagnostics formatter runs the redactor over every output line, not only the copied log.

## Interfaces for the later plans

Built here, wired by the plans for spec §6 groups 2–4. Call sites named are today's.

**Window** (wire in `windows/shellx-app/src/ui/app.rs:48`, today `Bounds::centered(None, size(px(1200.0), px(760.0)), cx)`)
- `shellx_model::first_window::{WorkArea { x: f32, y: f32, width: f32, height: f32 }, FirstWindow { x: f32, y: f32, width: f32, height: f32, maximized: bool }, first_window(WorkArea) -> FirstWindow, WorkArea::primary_workspace(width_px: f32, height_px: f32, scale: f32) -> WorkArea}`. `maximized` maps to `WindowBounds::Maximized(bounds)`. **Frame (corrected 2026-11-12 by the review of L7; the earlier text said "`rcWork` divided by the scale", which is wrong for GPUI 0.2.2):** GPUI hands the bounds to `SetWindowPlacement` (`gpui-0.2.2/src/platform/windows/window.rs:464-472`, `:1296-1315`), which reads them in workspace coordinates: (0, 0) is the top-left corner of the primary monitor's work area, not of the screen. So the caller opens the first window on the primary monitor (`display_id: None`) and passes `WorkArea::primary_workspace(rcWork.right - rcWork.left, rcWork.bottom - rcWork.top, scale)`: origin (0, 0), size in logical pixels, a scale that is not finite or not above zero counts as 1.0. It never passes `rcWork` in screen coordinates (that opens the window 48 px too low with the taskbar on top, and 48 px too far right with it on the left). A first window on another monitor is out of scope for this plan: GPUI falls back to its own default bounds unless that monitor's `display_id` is passed (`window.rs:414-418`, `display.rs` `check_given_bounds`), and the bounds would need that monitor's scale and the offset `screen - primary rcWork origin`.

**Keys, wheel, mouse, paste** (wire in `ui/term_view.rs` `on_key_down`/`on_scroll`/mouse handlers, `ui/update_banner.rs:81`, every paste path)
- `keys::map_key` now returns `Ignore` for Alt+F4 and Alt+Space and `App(SplitRight|SplitDown)` for GPUI-Windows' `alt` + `"+"`/`"_"`.
- `keys::is_window_system_key(&KeyIn) -> bool`: the forced-update overlay must not stop these keys.
- `mouse::ScrollAccumulator` (`Default`), `add(&mut self, lines: f64) -> i32`; one per pane; `lines > 0` means toward history (`delta.y / line_height`, the sign today's `on_scroll` uses).
- `mouse::{ScreenModes { alternate: bool, mouse_reporting: bool }, WheelAction::{None, Scrollback(i32), Arrows { key: &'static str, count: u32 }}, wheel_action(lines: i32, modes: ScreenModes) -> WheelAction}`; `key` is a libghostty chord name (`"up"`/`"down"`) for `TermCore`'s chord encoder, so cursor-key mode is honoured.
- `mouse::{SecondaryButton::{Right, Middle}, PaneClick::{FocusOnly, Paste, CopySelection, Nothing}, secondary_click(SecondaryButton, pane_focused: bool, has_selection: bool) -> PaneClick}`.
- `paste::needs_paste_confirmation(text: &str, bracketed: bool) -> bool` (`bracketed` = the pane's mode 2004).

**Local shell** (wire in `local_pty.rs` `shell_cmd`/`default_shell`, Settings › Terminal, the held pane)
- `shell::{ShellKind::{Pwsh, WindowsPowerShell, Cmd, GitBash, Wsl}, ShellLaunch { kind: Option<ShellKind>, program: String, args: Vec<String>, osc7_hook: bool }, ShellProbe { system_root, program_files, comspec, path, git_install_path: Option<String> }, ShellChoice::{Auto, Known { shell }, Custom { command_line }}, LaunchPlan { first: ShellLaunch, fallback: Option<ShellLaunch> }}`.
- `shell::find_shells(&ShellProbe, exists: &dyn Fn(&str) -> bool) -> Vec<ShellLaunch>`.
- `shell::launch_plan(&ShellChoice, env_override: Option<&str>, found: &[ShellLaunch], &ShellProbe, exists) -> Result<LaunchPlan, ShellError>`; `env_override` is `SHELLX_SHELL`; `ShellError::{NoShellFound, Custom(CustomShellError), Override(CustomShellError)}`.
- `shell::custom_launch(line: &str, &ShellProbe, exists) -> Result<ShellLaunch, CustomShellError>` (`Empty`, `UnclosedQuote`, `NotFound(String)`): the Settings field calls it on every edit to report a missing program at once.
- `shell::parse_command_line(&str) -> Result<Vec<String>, CommandLineError>`.
- `shell::POWERSHELL_PROMPT_HOOK: &str` replaces `local_pty.rs` `POWERSHELL_HOOK`; `shell::osc7_url(computer_name: &str, provider_path: &str) -> String` is what the hook sends.
- Stored choice (the later plan picks the file): `{"kind":"auto"}`, `{"kind":"known","shell":"pwsh|windows_powershell|cmd|git_bash|wsl"}`, `{"kind":"custom","command_line":"…"}`; a value that does not parse means Auto.
- The probe's Windows inputs: `%SystemRoot%`, `%ProgramFiles%`, `%ComSpec%`, `%PATH%`, `HKLM\SOFTWARE\GitForWindows\InstallPath`.

**Account and machines** (wire in `ui/settings.rs:114-215`, `ui/login.rs:181`, `ui/pairing.rs:435`, `ui/root.rs:1008-1023`, `ui/sidebar.rs`)
- `AccountFlow::can_sign_out(&self) -> bool`.
- `strings::failure_sentence(Lang, code: &str) -> String` for every account, sign-in and pairing error line; `google_error` never returns a raw code.
- `MachineInfo { …, can_host: bool }`; `fingerprint` may be `""`.
- `sidebar::{OfferRule::{RelayCanHost, AnyMac}, offer_rule_from_env(Option<&str>) -> OfferRule, can_offer_access(&MachineInfo, OfferRule) -> bool, request_targets<'a>(&'a [MachineInfo], has_link: &dyn Fn(&str) -> bool, OfferRule) -> Vec<&'a MachineInfo>, request_panel_notes(&[MachineInfo], OfferRule) -> &'static [Str], build_groups_with(…, OfferRule) -> Vec<MachineGroup>}`; the "+" picker replaces its filter (`root.rs:1017`) with `request_targets`, and shows `request_panel_notes` lines.
- New `Str`: `MacCannotHostYet`, `SignInOnYourMac`, `ServerProblem`, `RateLimited`, `SignInUnavailable` (`Str::ALL.len()` = 114).
- `shellx-core` `machines.list` items now carry `"can_host": bool`.

**Diagnostics** (wire in the logger, the panic hook, `--diagnose`)
- `redact::redact(&str) -> String` on every log line, panic message and report line.
- `diagnose::{DiagnosticsReport, Check, DisplayInfo, GpuInfo, LOG_TAIL_LINES (= 200), format_report(&DiagnosticsReport) -> String}`.

**Tooling**
- `scripts/shellx/check-windows-build.sh [--vps]`: compiles the committed HEAD of `shellx-model`, `shellx-remote`, `shellx-app` (all targets) for `x86_64-pc-windows-msvc`; exit 0 means it compiles. Every later branch with `cfg(windows)` code runs it before review.
- `windows/vendor/gpui-0.2.2/`: patches (a) `src/platform/windows/events.rs`, (b) `vsync.rs`, (c) `directx_renderer.rs`/`platform.rs` each go in their own commit with the notice line on every changed file and a row in `windows/vendor/README.md`; `windows/vendor/check-gpui.sh` must pass.
- `scripts/shellx/release/build-windows-cross.sh --preflight` checks the VPS guards; the full build refuses to start when they fail.

**Contract**
- `relay/contract/desktop-api.json`: Part 2 adds `can_host` to `GET /v2/machines` here first (with the relay change and its test), then in the fake.
- `os_info::os_version()` returns `"unknown"` on failure, which the relay refuses (contract case `os_version unknown`): the later plan should send a valid version instead.

**For the paused email-first plan** (`plans/2026-11-11-shellx-email-code-signin-windows.md`)
- `ServerProblem`, `RateLimited`, `SignInUnavailable` already exist with its wording: it adds 12 `Str` variants, not 15 (`Str::ALL` 126).
- Its line "`google_error(lang, "rate_limited")` is still `Some(login_failed(lang, "rate_limited"))`" becomes `Some(t(lang, Str::RateLimited).to_string())`; its `email_error` can fall back to `failure_sentence`.
- `MachineInfo` literals need `can_host`; `core_service.rs` has the new test `sign_in_with_a_mac_already_in_the_account`.

---

## Setup (each part, once)

Part T:
```bash
cd /Users/richard/Documents/helper/shellx
git worktree add .worktrees/windows-usable-tooling -b feat/shellx-windows-usable-tooling develop
cd .worktrees/windows-usable-tooling
export PATH="$(brew --prefix zig@0.16)/bin:$HOME/.cargo/bin:$PATH"
export CMUX_GHOSTTY_SRC=/Users/richard/Documents/helper/shellx/ghostty
test "$(git -C "$CMUX_GHOSTTY_SRC" rev-parse HEAD)" = "$(git ls-tree HEAD ghostty | awk '{print $3}')"
(cd windows && cargo test --locked -p shellx-model)                 # expect: 192 passed
(cd windows && cargo test --release --locked -p shellx-app)         # expect: 142 passed (cold build ~5 min)
```
Part L: the same with `.worktrees/windows-usable-rules` and `feat/shellx-windows-usable-rules`, plus:
```bash
(cd shellx-core && cargo test --workspace --locked)                 # expect: 236 passed in total
(cd relay && npm ci && npm run typecheck)                           # node_modules is not in the checkout
swift test --package-path Packages/Shared/ShellXBrand               # record the count
```
If the ghostty check fails (the main checkout's submodule moved), stop and report. If a baseline count differs, record the new number and use it in the expected outputs below.

---

## Part T: tooling (spec §6 group 0)

### Task T1: Compile-for-Windows command, local Docker route (time-boxed)

**Files:**
- Create: `windows/cross/check.Dockerfile`
- Create: `windows/cross/zig-libc-msvc.sh`
- Create: `windows/cross/check-in-container.sh`
- Create: `scripts/shellx/check-windows-build.sh`
- Modify: `windows/cross/build-in-container.sh:22-34` (source `zig-libc-msvc.sh` instead of the inline block), `windows/cross/Dockerfile:67` (also copy `zig-libc-msvc.sh`)

**Interfaces:**
- Produces: `scripts/shellx/check-windows-build.sh [--vps]`, exit 0 = compiles; `windows/cross/check-in-container.sh` (runs in either image with `/src` holding `windows`, `cmux-tui`, `shellx-core`, `ghostty`, and `CMUX_TUI_BUILD_COMMIT` set).

**Time box:** two hours of wall time from the first `docker build` in Step 2. If Steps 2–4 do not all pass within it (one fix attempt allowed), commit nothing from this task, delete the four new files, restore the two modified ones, write the failing step and its last 30 output lines in the task report, and do Task T3.

- [ ] **Step 1: Write the four files**

`check.Dockerfile`: `FROM ubuntu:24.04`; the same `ARG`s as `Dockerfile` (`RUST_VERSION=1.95.0`, `ZIG_VERSION=0.16.0`, `CARGO_XWIN_VERSION=0.23.1`); apt packages `ca-certificates curl xz-utils git python3 build-essential pkg-config clang-18 lld-18 llvm-18 libclang-18-dev` (no wine, msitools, xvfb, Inno, fxc); rustup minimal plus target `x86_64-pc-windows-msvc`; `arch=$(uname -m)` (`x86_64` or `aarch64`) chooses `cargo-xwin-v${V}.${arch}-unknown-linux-musl.tar.gz` and `zig-${arch}-linux-${ZIG}.tar.xz`; the `ENV` block of `Dockerfile:69-79` without `GPUI_FXC_PATH`, `WINEPREFIX`, `WINEDEBUG`, `WINEDLLOVERRIDES`; copy `llvm-rc.sh zig-libc-msvc.sh check-in-container.sh` to `/opt/winbuild/`. If the aarch64 cargo-xwin asset does not exist (`curl -sfI` fails), install it with `cargo install cargo-xwin --version 0.23.1 --locked` instead.

`zig-libc-msvc.sh`: the `xwin_root`/`ZIG_LIBC` block of `build-in-container.sh:22-34`, moved verbatim; sourced, exports `ZIG_LIBC`. `build-in-container.sh` sources it.

`check-in-container.sh`: `set -euo pipefail`; refuse unless `CMUX_TUI_BUILD_COMMIT` is 40 hex; `unset CMUX_GHOSTTY_SRC`; `export CARGO_TARGET_DIR=/cache/target ZIG_LOCAL_CACHE_DIR=/cache/zig-local`; source `zig-libc-msvc.sh`; `cd /src/windows`; print `rustc`, `cargo-xwin`, `zig` versions; run
```bash
cargo xwin check --locked --target x86_64-pc-windows-msvc -p shellx-model -p shellx-remote -p shellx-app --all-targets
```
then print `== windows check: OK`.

`check-windows-build.sh` (local by default):
1. `--vps` delegates to `SHELLX_WINBUILD_CHECK=1 scripts/shellx/release/build-windows-cross.sh` when Task T3 was done; otherwise it prints `VPS route not built: the local route passed (see Task T1)` and exits 2.
2. Warn (as `build-windows-cross.sh` does) when `windows`, `cmux-tui` or `shellx-core` have uncommitted changes: they are not checked.
3. Image tag = first 12 hex of `sha256` over the working-tree bytes of `check.Dockerfile llvm-rc.sh zig-libc-msvc.sh check-in-container.sh` (so the recipe can change without a commit); image `shellx-wincheck:<tag>`, built with `docker build -f check.Dockerfile` from a context of exactly those four files when missing.
4. Source dir `src=$(mktemp -d "${TMPDIR:-/tmp}/shellx-wincheck.XXXXXX")`, removed on exit. `git archive HEAD windows cmux-tui shellx-core | tar -x -m -C "$src"`. Ghostty: the commit `git ls-tree HEAD ghostty` names, taken with `git -C <dir> archive --prefix=ghostty/ <sha> | tar -x -m -C "$src"` from the first of `$CMUX_GHOSTTY_SRC`, `<repo>/ghostty`, `<first worktree of git worktree list>/ghostty` where `git -C <dir> cat-file -e <sha>^{commit}` succeeds; none → fail with the `CMUX_GHOSTTY_SRC` hint.
5. `docker volume create shellx-wincheck-cache`; `docker run --rm --name shellx-wincheck-run --memory 6g --cpus 8 -e CARGO_BUILD_JOBS=6 -e CMUX_TUI_BUILD_COMMIT=$(git rev-parse HEAD) -v shellx-wincheck-cache:/cache -v "$src":/src <image> bash /opt/winbuild/check-in-container.sh`; its exit status is the script's; print `Checked <commit> for Windows (x86_64-pc-windows-msvc): OK` on success.

- [ ] **Step 2: Cold run on the branch HEAD (green expected)**

Run: `time scripts/shellx/check-windows-build.sh`
Expected: exit 0, `== windows check: OK`, no `Killed`/exit 137. Record the wall time.
If it fails only with rustc errors located in `windows/**` source (Windows-only test code has not been compiled since 2026-10-19), the command works: record the errors in the task report as a finding for the orchestrator (Part T does not edit `shellx-app` source), and judge this step by the same run with `--lib --bins` in place of `--all-targets` passing.

- [ ] **Step 3: Confirm the docker memory and disk**

Run: `docker info --format '{{.NCPU}} {{.MemTotal}}'; docker system df -v | grep shellx-wincheck`
Expected: memory about 8.3e9; the cache volume size noted in the report.

- [ ] **Step 4: Red probe after the green run (proves Windows code is compiled and no stale verdict)**

```bash
git switch -c probe/wincheck-red
printf '\n#[cfg(windows)]\ncompile_error!("shellx-wincheck-probe");\n' >> windows/shellx-app/src/main.rs
git commit -qam "probe: windows-only compile error"
scripts/shellx/check-windows-build.sh; echo "exit=$?"
git switch feat/shellx-windows-usable-tooling && git branch -D probe/wincheck-red
```
Expected: exit ≠ 0 and the output contains `shellx-wincheck-probe`. (`git commit -a` takes only the tracked `main.rs`; the new tooling files stay untracked.)

- [ ] **Step 5: Warm run on HEAD**

Run: `time scripts/shellx/check-windows-build.sh`
Expected: exit 0 in under 10 minutes.

- [ ] **Step 6: Commit**

```bash
git add windows/cross/check.Dockerfile windows/cross/zig-libc-msvc.sh windows/cross/check-in-container.sh \
        windows/cross/build-in-container.sh windows/cross/Dockerfile scripts/shellx/check-windows-build.sh
git commit -m "tooling(windows): compile shellx-app for Windows from this Mac with a local Docker check image

Cold <m> min, warm <m> min; a cfg(windows) compile_error commit after a green run is reported red."
```

### Task T2: Guards for every VPS build

**Files:**
- Modify: `scripts/shellx/release/build-windows-cross.sh` (header, the `ssh_opts` line, step 2 extraction, new preflight before step 1, after step 5)

**Interfaces:**
- Produces: `build-windows-cross.sh --preflight` (guards only, exit 0/1); env `SHELLX_WINBUILD_MIN_FREE_GIB` (default 14); every run uses container name `shellx-winbuild-run`.

- [ ] **Step 1: Write the red preflight check**

Run: `SHELLX_VPS=higio-vps SHELLX_VPS_SSH_OPTS='' scripts/shellx/release/build-windows-cross.sh --preflight; echo "exit=$?"`
Expected today: it does not understand `--preflight` (it takes it as `OUT_DIR` and starts a build). Stop it with Ctrl-C at the branding line; this is the red.

- [ ] **Step 2: Implement**

- `read -r -a ssh_opts <<< "${SHELLX_VPS_SSH_OPTS-"-S $HOME/.ssh/cm-shellx-vps"}"` (Ruling 6).
- `preflight()` over ssh: free GiB of `~` (`df -Pk ~ | awk 'NR==2 {print int($4/1048576)}'`) must be ≥ `SHELLX_WINBUILD_MIN_FREE_GIB`, else exit 1 with `VPS has <n> GiB free in ~; a Windows build needs <min> (4 stay free for deploys)`; `docker ps -q -f name=^shellx-winbuild-run$` must be empty, else exit 1 with `another Windows build is running on the VPS`. Print `preflight: <n> GiB free, no Windows build running`.
- `--preflight` as the first argument runs only `preflight` and exits; a normal run calls it before step 1.
- Step 2's remote `tar -xzf ../src.tgz` becomes `tar -xmzf ../src.tgz` (Ruling 2).
- After step 5: print the free GiB; when it is under the minimum, list `docker images shellx-winbuild --format '{{.Tag}}'` and remove (`docker image rm`) only the tags that are not the current one. Never `docker system prune`, never other images.
- Header comment: document `--preflight`, the minimum and the single-run rule.

- [ ] **Step 3: Verify**

Run: `SHELLX_VPS=higio-vps SHELLX_VPS_SSH_OPTS='' scripts/shellx/release/build-windows-cross.sh --preflight; echo "exit=$?"`
Expected: `preflight: <n> GiB free, no Windows build running`, `exit=0` (if `<n>` < 14, expected `exit=1` with the disk sentence: report it and do not run Task T5's VPS step until the user frees space).
Run: `SHELLX_WINBUILD_MIN_FREE_GIB=100000 SHELLX_VPS=higio-vps SHELLX_VPS_SSH_OPTS='' scripts/shellx/release/build-windows-cross.sh --preflight; echo "exit=$?"`
Expected: the disk sentence and `exit=1`.
Run: `bash -n scripts/shellx/release/build-windows-cross.sh` → no output.

- [ ] **Step 4: Commit**

```bash
git add scripts/shellx/release/build-windows-cross.sh
git commit -m "tooling(windows): the VPS cross build checks free disk and refuses a second run; fresh mtimes for sources"
```

### Task T3: VPS check mode (only if Task T1 failed its time box)

**Files:**
- Create: `windows/cross/zig-libc-msvc.sh`, `windows/cross/check-in-container.sh` (exactly as Task T1 Step 1)
- Create: `scripts/shellx/check-windows-build.sh` (only its `--vps` route and the warning; with no argument it prints `local route not available (see Task T1 report); use --vps` and exits 2)
- Modify: `windows/cross/Dockerfile:67`, `windows/cross/build-in-container.sh:22-34`, `scripts/shellx/release/build-windows-cross.sh`

**Interfaces:**
- Consumes: Task T2's `preflight`.
- Produces: `SHELLX_WINBUILD_CHECK=1 build-windows-cross.sh` = the check, no installer, cache kept.

- [ ] **Step 1: Implement check mode in `build-windows-cross.sh`**: skip the branding check; steps 1 and 2 as usual (image, sources, guards); step 3 runs `bash /opt/winbuild/check-in-container.sh` in the same `docker run` (same `--cpus 4 --memory 10g --name shellx-winbuild-run`, same volume) and passes its exit status; no download; step 5 never removes `/cache/target`. The Dockerfile copies the two new scripts.
- [ ] **Step 2: Run Task T1 Steps 2, 4, 5 with `scripts/shellx/check-windows-build.sh --vps`** (the image rebuilds once; the probe branch must be pushed nowhere: the script archives the local HEAD). Expected: as in Task T1 (green, red probe, warm under 10 min).
- [ ] **Step 3: Commit**: `tooling(windows): VPS check mode for the Windows compile (local Docker route failed: <one line why>)`.

### Task T4: gpui 0.2.2 as a pristine copy under `[patch.crates-io]`

**Files:**
- Create: `windows/vendor/gpui-0.2.2/**` (commit 1, nothing else)
- Create: `windows/vendor/README.md`, `windows/vendor/check-gpui.sh` (commit 2)
- Modify: `windows/Cargo.toml` (`[workspace] exclude`, `[patch.crates-io]`), `windows/Cargo.lock`, `.gitattributes` (commit 2)

**Interfaces:**
- Produces: `windows/vendor/check-gpui.sh` (exit 0 when the copy equals the crate except the files that carry the notice, and those are exactly the files that differ; prints the list).

- [ ] **Step 1: Copy the crate and prove it identical**

```bash
crate=~/.cargo/registry/cache/index.crates.io-1949cf8c6b5b557f/gpui-0.2.2.crate
[ -f "$crate" ] || (cd windows && cargo fetch --locked)
echo "979b45cfa6ec723b6f42330915a1b3769b930d02b2d505f9697f8ca602bee707  $crate" | shasum -a 256 -c
mkdir -p windows/vendor && tar -xzf "$crate" -C windows/vendor
t=$(mktemp -d) && tar -xzf "$crate" -C "$t" && diff -r "$t/gpui-0.2.2" windows/vendor/gpui-0.2.2 && echo IDENTICAL
git add windows/vendor/gpui-0.2.2 && git status --porcelain windows/vendor | grep -c '^A'
tar -tzf "$crate" | grep -vc '/$'
```
Expected: `OK`, `IDENTICAL`, and the two counts equal. (No repo or global ignore rule matches these files; checked while writing this plan.)

- [ ] **Step 2: Commit 1 (pristine)**

```bash
git commit -m "vendor(windows): gpui 0.2.2 exactly as published (crate sha256 979b45cf…, Apache-2.0)

Byte-identical to gpui-0.2.2.crate; not used by the build yet. Patches follow as separate commits."
```

- [ ] **Step 3: Write `check-gpui.sh` and `README.md`, and see the patch is not active (red)**

`check-gpui.sh`: find the crate in `~/.cargo/registry/cache/*/gpui-0.2.2.crate`, else download `https://static.crates.io/crates/gpui/gpui-0.2.2.crate` to a temp file; verify the sha256 above (hard-coded: the lock loses it in Step 4); extract to a temp dir; `diff -rq` against `windows/vendor/gpui-0.2.2`; collect files that differ and files whose first line starts with `// Modified by ShellX:`; fail if a file exists on one side only, or if the two sets differ; print `gpui-0.2.2: pristine` or `gpui-0.2.2: N patched file(s): <list>`.
`README.md` (short): what the copy is, the crate checksum, why it is vendored (spec §4.2), the notice rule, how to check (`check-gpui.sh`), and a patch table with columns patch / files / reason / commit (empty now).

Run: `windows/vendor/check-gpui.sh` → `gpui-0.2.2: pristine`.
Run: `(cd windows && cargo metadata --format-version 1 --locked | python3 -c 'import json,sys; m=json.load(sys.stdin); print([p["source"] for p in m["packages"] if p["name"]=="gpui"])')`
Expected (red for this task's goal): `['registry+https://github.com/rust-lang/crates.io-index']`.

- [ ] **Step 4: Point cargo at the copy**

`windows/Cargo.toml`: under `[workspace]` add `exclude = ["vendor"]` (Ruling 3); add
```toml
# gpui 0.2.2, vendored to carry fixes (windows/vendor/README.md). Every build uses this copy.
[patch.crates-io]
gpui = { path = "vendor/gpui-0.2.2" }
```
`.gitattributes`: add `windows/vendor/** linguist-vendored`.
Update the lock without other changes: `(cd windows && cargo metadata --format-version 1 --offline >/dev/null)` (no `--locked`, so cargo may rewrite the gpui entry; `--offline`, so nothing else moves).

- [ ] **Step 5: Verify**

```bash
git diff --numstat windows/Cargo.lock                                  # expect: 0	2	windows/Cargo.lock
git diff windows/Cargo.lock | grep '^-[^-]'                            # expect: the gpui source and checksum lines only
(cd windows && cargo metadata --format-version 1 --locked | python3 -c 'import json,sys; m=json.load(sys.stdin); print(len(m["workspace_members"]), [p["source"] for p in m["packages"] if p["name"]=="gpui"])')
                                                                       # expect: 3 [None]
(cd windows && cargo test --locked -p shellx-model)                    # expect: 192 passed
(cd windows && cargo build --release --locked -p shellx-app)           # expect: Finished; gpui compiles from vendor/
(cd windows && cargo test --release --locked -p shellx-app)            # expect: 142 passed
scripts/shellx/check-windows-build.sh                                  # (or --vps) expect: OK
```
If gpui fails to compile here because of its own `#![deny(missing_docs)]` (`src/gpui.rs:2`) or `#![deny(unsafe_op_in_unsafe_fn)]` (`src/platform/windows/window.rs:1`) now that its lints are not capped (a path dependency), stop and report: fixing it is a fifth patch, which needs the orchestrator.
Note for anyone running the cross build between this commit and Task T5: it is broken (the container's patch script finds no registry gpui). Do not run it.

- [ ] **Step 6: Commit 2**

```bash
git add windows/Cargo.toml windows/Cargo.lock windows/vendor/README.md windows/vendor/check-gpui.sh .gitattributes
git commit -m "build(windows): every build uses the vendored gpui 0.2.2 ([patch.crates-io]); Cargo.lock loses gpui's source and checksum only"
```

### Task T5: Patch (d), the shader step for cross builds, in the copy

**Files:**
- Modify: `windows/vendor/gpui-0.2.2/build.rs:1`, `:24-27`, `:248-249`
- Delete: `windows/cross/patch-gpui-build-rs.py`
- Modify: `windows/cross/build-in-container.sh:45` (remove the call), `windows/cross/Dockerfile:67` (remove it from `COPY`), `scripts/shellx/release/build-windows-cross.sh:18-20` (header), `windows/vendor/README.md` (table row)

**Interfaces:**
- Consumes: Task T4's copy and `check-gpui.sh`; Task T2's guards.

- [ ] **Step 1: See the two host gates (red)**

Run: `grep -n 'cfg(target_os = "windows")' windows/vendor/gpui-0.2.2/build.rs`
Expected: lines 25 and 248 (the gate on the `windows::build()` call and on `mod windows`).

- [ ] **Step 2: Patch**: remove exactly those two attribute lines (what `patch-gpui-build-rs.py` did); insert as line 1 `// Modified by ShellX: compile the HLSL shaders for a Windows target on any build host (cross builds). See windows/vendor/README.md.`; add the README row (patch d, `build.rs`, reason, this commit). Delete the script, its call and its `COPY` entry; the header of `build-windows-cross.sh` now says the vendored gpui (patch d) compiles the HLSL on any host with the SDK's `fxc.exe` under wine.

- [ ] **Step 3: Verify on this Mac**

```bash
windows/vendor/check-gpui.sh                                   # expect: gpui-0.2.2: 1 patched file(s): build.rs
grep -c 'cfg(target_os = "windows")' windows/vendor/gpui-0.2.2/build.rs   # expect: 0
git grep -n patch-gpui -- windows scripts                     # expect: nothing
(cd windows && cargo build --release --locked -p shellx-app)  # expect: Finished
(cd windows && cargo test --release --locked -p shellx-app)   # expect: 142 passed
scripts/shellx/check-windows-build.sh                         # expect: OK
```

- [ ] **Step 4: Commit (before the VPS proof: the cross build compiles the committed HEAD)**

```bash
git add -A windows/vendor/gpui-0.2.2/build.rs windows/vendor/README.md windows/cross scripts/shellx/release/build-windows-cross.sh
git commit -m "vendor(windows): gpui patch (d): shaders compile for a Windows target on any host; drop the container's build.rs patch script

The cross-build image rebuilds once (windows/cross changed)."
```

- [ ] **Step 5: Prove the cross build still produces an exe (VPS, guarded, one run)**

```bash
out=$(mktemp -d "${TMPDIR:-/tmp}/shellx-wincross-proof.XXXXXX")   # or your scratchpad; never dist/ or the Desktop
SHELLX_VPS=higio-vps SHELLX_VPS_SSH_OPTS='' scripts/shellx/release/build-windows-cross.sh --preflight
SHELLX_VPS=higio-vps SHELLX_VPS_SSH_OPTS='' scripts/shellx/release/build-windows-cross.sh "$out"
```
Expected: preflight exit 0; the build ends with `Built <out>/ShellX-Setup-1.7.0.exe (unsigned)` (Inno's `Successful compile` line is in the filtered output). The release build of `shellx-desktop.exe` can only link if gpui's build script wrote `shaders_bytes.rs` through `fxc` under wine (`directx_renderer.rs:1558` includes it), so the exe is the proof of patch (d). Record the sha256 from `<out>/ShellX-Setup-1.7.0.exe.sha256`, then `rm -rf "$out"`: this exe carries the public release's name and must not be mistaken for it (spec §3 anti-goal). If preflight fails, report it and stop; do not free space outside ShellX's own images.

- [ ] **Step 6: Record**: add the VPS result (sha256, duration, free GiB after) to the task report; no commit.

---

## Part L: rules (spec §6 group 1)

Commands used below (from the Part L worktree, with the Setup environment):
- MODEL: `(cd windows && cargo test --locked -p shellx-model)`
- CORE: `(cd shellx-core && cargo test --workspace --locked)`
- APP: `(cd windows && cargo test --release --locked -p shellx-app)`
- RELAY: `(cd relay && npm run typecheck && npx vitest run test/desktop-contract.test.ts)`

### Task L1: The fake relay lists machines in the real relay's shape

**Files:**
- Modify: `shellx-core/fake-api/src/lib.rs` (`list_machines` ~`:871-894`, state, new toggle beside `set_list_all_pairings` ~`:630`)
- Test: `shellx-core/tests/machines.rs:100-132`, `:173-183`

**Interfaces:**
- Produces: `FakeApi::set_list_machine_keys(&self, on: bool)`; by default `GET /v2/machines` items carry exactly `machine_id, name, platform, online, last_seen_unix, fingerprint` (`relay/src/v2/machines.ts:84-108`).

- [ ] **Step 1: Rewrite the three tests**

```rust
// list_marks_this_machine_and_offline_after_90s: line 118 becomes
assert_eq!(m["fingerprint"], Value::Null, "the relay sends no key, so the core has no fingerprint (D1)");

#[test]
fn list_fingerprint_is_null_in_the_relays_shape() {   // replaces list_fingerprint_of_this_machine_matches_login_fingerprint
    let (core, _fake, _dir) = support::logged_out();
    let l = login(&core);
    assert_eq!(l["fingerprint"].as_str().unwrap().len(), 16);
    core.call("machines.register", reg_params()).unwrap();
    let r = core.call("machines.list", json!({})).unwrap();
    assert_eq!(r["machines"][0]["fingerprint"], Value::Null);
}

// list_fingerprint_is_computed_from_a_padded_standard_key: before the list call
fake.set_list_machine_keys(true);
```
- [ ] **Step 2: Run to verify they fail**: `(cd shellx-core && cargo test --locked --test machines)` → compile error `no method named set_list_machine_keys found for struct FakeApi`. (Once it compiles against today's list, the first two fail on a 16-hex fingerprint where `null` is expected.)
- [ ] **Step 3: Implement**: the default list item has the six relay keys; with the toggle on, it also has `noise_public_key_b64`.
- [ ] **Step 4: Run**: CORE → all pass, same total as the baseline.
- [ ] **Step 5: Record the Windows red this exposes (Blocker 1 through the real core)**: APP filtered: `(cd windows && cargo test --release --locked -p shellx-app against_fake_api)` → `account_session_against_fake_api`, `google_session_against_fake_api` and `core_bridge::…login_register_list_heartbeat_logout_against_fake_api` FAIL with `machines.list: invalid type: null, expected a string`. Paste the lines into the commit message.
- [ ] **Step 6: Commit**: `test(shellx-core): the fake relay lists machines like the real relay (no key, fingerprint null); Windows sign-in tests now red (R4 Blocker 1)`.

### Task L2: Windows sign-in completes when the list has `fingerprint: null` (R4 Blocker 1)

**Files:**
- Modify: `windows/shellx-model/src/sidebar.rs:16` (+ deserializer)
- Test: `windows/shellx-model/src/sidebar.rs` tests, `windows/shellx-model/src/core_api.rs` tests, `windows/shellx-app/src/core_service.rs` tests

**Interfaces:**
- Consumes: Task L1's fake shape.
- Produces: `MachineInfo.fingerprint: String`, `""` for null, absent or non-string (Ruling 8); `fn string_or_empty` (private).

- [ ] **Step 1: Write the failing tests**

```rust
// sidebar.rs
#[test] fn null_absent_or_odd_fingerprint_reads_as_empty() {
    // items with "fingerprint": null, no fingerprint key, and "fingerprint": 42 → each parses, fingerprint == ""
}
// core_api.rs: the core's output for the body relay/test/v2-machines.test.ts:108-111 pins
#[test] fn list_machines_accepts_the_cores_output_for_the_relays_list() {
    // FakeCore "machines.list" → {"machines":[{"is_this_machine":false,"machine_id":"m1","name":"Mac-Studio",
    //   "platform":"macos","online":false,"last_seen_unix":0,"fingerprint":null}]}
    // list_machines(&f) is Ok, one item, fingerprint == "", name == "Mac-Studio"
}
// core_service.rs (R4 flowA's second run: the account already has a signed-in Mac)
#[test] fn sign_in_with_a_mac_already_in_the_account() {
    // FakeApi::start(FakeOptions::default()); the Mac: let mac = crate::core_bridge::CoreBridge::new();
    // config_set(&mac, &cfg(&base, &mac_dir)) (its own state dir), then mac.call("auth.login", {"email":"a@b.c","password":"pw"}),
    // mac.call("machines.register", {"name":"MacBook","platform":"macos","os_version":"15.5","app_version":"2.0.0"}),
    // mac.call("machines.heartbeat", {}).
    // The Windows flow: drive(Started) → LoggedOut; drive(LoginSubmitted {a@b.c, password}) →
    assert_eq!(ran, ["CallLogin { email: \"a@b.c\", password: \"<redacted>\" }", "CallList", "CallRegister", "CallList", "CallSession"]);
    // state LoggedIn; machines() has 2: this PC (is_this_machine) and "MacBook" with platform "macos", online, fingerprint ""
}
```
- [ ] **Step 2: Run to verify they fail**: MODEL → the two model tests fail (`invalid type: null, expected a string`); APP → the new test fails with `ran == ["CallLogin …", "CallList"]` and state `Error(… bad_response … machines.list: invalid type: null, expected a string)`.
- [ ] **Step 3: Commit the red tests**: `test(windows): sign-in ends in machines.list bad_response when the list has fingerprint null (R4 Blocker 1) [red]` with the red lines in the body.
- [ ] **Step 4: Implement**: `#[serde(default, deserialize_with = "string_or_empty")] pub fingerprint: String`; `string_or_empty` reads a `serde_json::Value` and keeps only a string.
- [ ] **Step 5: Run**: MODEL → all pass; APP → all pass, including the three tests L1 turned red.
- [ ] **Step 6: Commit**: `fix(windows): the machine list accepts fingerprint null, so sign-in completes against the real relay (R4 Blocker 1)`.

### Task L3: One source for the relay's answers and request rules

**Files:**
- Create: `relay/contract/desktop-api.json`
- Create: `relay/test/desktop-contract.test.ts`
- Create: `shellx-core/tests/relay_contract.rs`
- Modify: `shellx-core/fake-api/src/lib.rs` (new `pub fn fetch` beside `browse` ~`:1894`; the drifts the test finds)
- Modify: `shellx-core/fake-api/tests/google.rs:238`, `shellx-core/fake-api/tests/ticket_format.rs:41`, `scripts/shellx/remote-e2e/harness.py:394`, `:467` (versions the relay refuses)

**Interfaces:**
- Produces: the contract file (format below); `shellx_fake_api::fetch(method: &str, url: &str, bearer: Option<&str>, body: Option<&serde_json::Value>) -> Result<(u16, String), String>` (loopback HTTP/1.1, `Connection: close`, like `browse`).

Contract format (both runners implement the same small checker):
- `"responses"`: list of `{ "route", "case"?, "status", "body" }`. `body` is a shape: an object = exactly these keys (a key ending in `?` may be absent); a one-element array = non-empty array whose every element matches; a string = type tokens `string | integer | number | boolean | null` joined by `|`; `null` = empty body. One entry `"route": "error"` gives the error envelope `{"error":{"code":"string","message":"string"}}`.
- `"requests"`: list of `{ "route", "base", "cases": [{ "label", "set", "status", "error"? }] }`; each case = a fresh account, `base` overridden by `set`; for `POST /v2/machines` the runner adds a fresh 32-byte url-safe key unless `set` has `noise_public_key_b64`.
- Top-level `"about"`: one sentence: change the relay, then this file, then the fake.

Entries (statuses and shapes from `relay/src`; the relay test is the referee: if it fails, correct the file, never the relay):

| route | status | body |
| --- | --- | --- |
| `GET /v2/machines` | 200 | `{"machines":[{"machine_id":"string","name":"string","platform":"string","online":"boolean","last_seen_unix":"integer|null","fingerprint":"string"}]}` |
| `POST /v2/machines` case `new` / `again` | 201 / 200 | `{"machine_id":"string","slot":"string","link_slot":"string"}` |
| `POST /v2/machines/:id/heartbeat` | 204 | `null` |
| `POST /v2/pairings` | 201 | `{"pairing_id":"string","code":"string"}` |
| `GET /v2/pairings?role=requester` (after approve) | 200 | `{"pairings":[{"pairing_id","from_machine_id","to_machine_id","requester_fingerprint","requester_x25519_b64","code","status": all "string", "sealed_invite_b64?":"string"}]}` |
| `POST /v2/relay/tickets` (`permission: "register"`, own machine) | 200 | `{"ticket":"string","expires_at_unix":"integer","relay_url":"string"}` |
| `GET /v1/version` | 200 | `{"min_agent":"string","min_mobile":"string","latest_agent":{"version":"string","mac_url":"string","win_url":"string"}}` |
| `POST /v1/auth/email/code` | 202 | `{"challenge_id":"string","expires_in":"integer","resend_in":"integer","email":"string"}` |
| `POST /v1/auth/email/verify` | 200 | `{"user_id":"string","device_id":"string","token":"string","email":"string"}` |
| `GET /v1/account/identities` (after an email sign-in) | 200 | `{"identities":[{"identity_id":"string","provider":"string","email":"string|null","is_private_email":"boolean","linked_via_device_name":"string|null","created_at_unix":"integer"}]}` |

Request cases, `POST /v2/machines`, base `{"name":"Mac","platform":"macos","os_version":"15.2","app_version":"1.0.0"}`:
- 201: `base`; name `"x"`×100; name `"  Máy của Phú  "`; `{"platform":"windows","os_version":"10.0.26100.1"}`; key `"+/v7"`×10 + `"+/s="` (32 bytes of 0xfb, standard base64 with padding).
- 400 `invalid_machine`: name `"   "`; name `"x"`×101; name `"😀"`×51 (102 UTF-16 units); name `5`; platform `"linux"`; platform `"ios"`; os_version `"15.x"`, `"unknown"`, `"e2e"`, `"1.2.3.4.5"`; app_version `"1.0"`, `"1.0.0-beta"`, `"1"`; key `"A"`×42 (31 bytes); key `"!!!"`.

Request cases, `POST /v1/auth/email/code`, base `{"email":"foo@bar.com","locale":"en"}`:
- 202: `base`; email `" Foo@Bar.COM "`.
- 400 `invalid_email`: `"nope"`, `"a@b"`, `"phú@bar.com"`, `5`. 400 `disposable_email`: `"x@mailinator.com"`.

- [ ] **Step 1: Write the contract file and the relay test**

`desktop-contract.test.ts` imports the file (`with { type: "json" }`, as `src/auth/email.ts` does), has `checkShape(value, shape, path)` and one `it` per response entry and one `it.each` per request route. Recipes (all in `test/helpers.ts`): `makeApp`, `registerAccount`, `loginDesktop` (two desktops of one account, both `registerMachine`, one heartbeat, so the list has two items), `requestPairing` + `approvePairing`, `call(app, "POST", "/v2/relay/tickets", …)`, email with `new FakeEmailGateway()` and `makeApp({ email: mail, emailCode: () => CODE })` as in `test/auth-email-verify.test.ts`, then `emailSession` for identities. Every error case also checks the `error` envelope shape.
- [ ] **Step 2: Run it**: RELAY → PASS. A failure means the file is wrong: correct the file, never `relay/src`.
- [ ] **Step 3: Write the core test**: `shellx-core/tests/relay_contract.rs` reads `concat!(env!("CARGO_MANIFEST_DIR"), "/../relay/contract/desktop-api.json")` at run time, starts `FakeApi::start(FakeOptions::default())`, gets desktop tokens through `POST /v1/auth/login` (`{"email","password":"pw","device":{"kind":"desktop","name","platform":"windows","public_key"}}`) or the email routes (`fake.email_code(email)`), and checks the same entries and cases with `fetch` and a Rust `check_shape`. Test names: `fake_answers_in_the_relays_shapes`, `fake_refuses_what_the_relay_refuses`.
- [ ] **Step 4: Run to verify it fails**: `(cd shellx-core && cargo test --locked --test relay_contract)` → red. Expected drifts (from reading; the run is the truth): register answers 200 not 201; heartbeat 200 `{}` not 204 empty; platform `ios` accepted; standard-base64 key refused; 51 emoji accepted; `os_version` `"unknown"`/`"e2e"` and `app_version` `"1"` accepted.
- [ ] **Step 5: Fix the fake** to each relay rule (Ruling 11) until both tests pass; then change `os_version: "1"`/`app_version: "1"` in `fake-api/tests/google.rs:238` and `ticket_format.rs:41` to `"15.5"`/`"2.0.0"`, `os_version="e2e"` in `harness.py:394,467` to `"15.5"`, and any `fake-api` test that pinned the old statuses (200 for a first register, 200 for a heartbeat) to the relay's.
- [ ] **Step 6: Run**: CORE → all pass; `(cd relay && npm test)` → all pass; APP → all pass; `python3 -I -m py_compile scripts/shellx/remote-e2e/harness.py` → no output.
- [ ] **Step 7: Commit**: `test(relay, shellx-core): one contract file for the relay answers and rules the desktop apps use; the fake relay follows it`.

### Task L4: The core forwards `can_host`

**Files:**
- Modify: `shellx-core/src/api.rs:203-219` (`MachineItem`), `shellx-core/src/machines.rs:97-105`, `shellx-core/fake-api/src/lib.rs` (`Machine`, list, hook)
- Test: `shellx-core/tests/machines.rs`

**Interfaces:**
- Produces: every `machines.list` item has `"can_host": bool`; `FakeApi::set_machine_can_host(&self, machine_id: &str, value: serde_json::Value)` (the list item carries `can_host` with that value; never set → no key).

- [ ] **Step 1: Write the failing tests**

```rust
#[test] fn list_forwards_can_host_and_defaults_to_false() {
    // register; list → can_host == false (no key from the relay);
    // set_machine_can_host(id, json!(true)) → true; json!(false) → false
}
#[test] fn list_survives_odd_can_host_values() {
    // for json!(null), json!("true"), json!(1), json!({}) → the list call is Ok and can_host == false
}
```
- [ ] **Step 2: Run to verify they fail**: `(cd shellx-core && cargo test --locked --test machines can_host)` → compile error (no hook), then `can_host` missing.
- [ ] **Step 3: Implement**: `MachineItem` gets `#[serde(default, deserialize_with = "true_only")] pub can_host: bool` and loses the unused server `fingerprint` field (`grep -n fingerprint shellx-core/src/machines.rs shellx-core/src/api.rs` shows no reader; any type is then ignored); the list item adds `"can_host": m.can_host`.
- [ ] **Step 4: Run**: CORE → all pass (the contract test stays green: the hook is used only here). `swift test --package-path Packages/Shared/ShellXBrand` → same count as the baseline, all pass (`MachineListReply.Item`, `ShellXRemoteServiceSupport.swift:39-55`, is a synthesized `Decodable` and ignores the new key).
- [ ] **Step 5: Commit**: `feat(shellx-core): machines.list forwards the relay's can_host (absent or not true = false)`.

### Task L5: Only Macs that can host are offered; honest sentences; the override

**Files:**
- Modify: `windows/shellx-model/src/sidebar.rs`, `windows/shellx-model/src/strings.rs` (`Str`, `ALL`, both `t` arms, count test)
- Modify (literals and one expectation): `windows/shellx-model/src/account.rs:727-737`, `windows/shellx-app/src/shell_info.rs:99-107`, `:257-294`, `windows/shellx-app/src/remote_tabs.rs:1086-1094`
- Test: `sidebar.rs`, `strings.rs`, `shell_info.rs`, `core_service.rs` (the L2 test)

**Interfaces:**
- Consumes: Task L4's `can_host` key.
- Produces: `MachineInfo.can_host: bool`; `OfferRule`, `offer_rule_from_env`, `can_offer_access`, `request_targets`, `request_panel_notes`, `build_groups_with` (signatures under "Interfaces for the later plans"); `Str::MacCannotHostYet`, `Str::SignInOnYourMac`.

Rules: `can_offer_access(m, rule)` = `!m.is_this_machine && m.platform == "macos" && (m.can_host || rule == AnyMac)`; in `build_groups_with`, an online machine with `Access::None` gets `RequestAccess` only when `can_offer_access`, else `RowAction::None` (Ruling 14); `request_targets` = machines with `can_offer_access` and no link; `request_panel_notes`: no Mac other than this machine in the list → `[MacCannotHostYet, SignInOnYourMac]`; some Mac but none offerable → `[MacCannotHostYet]`; else `[]`. `offer_rule_from_env(v)` = `AnyMac` only for `v.map(str::trim) == Some("1")`.

Sentences:
- `MacCannotHostYet`: vi "ShellX cho Mac hiện chưa nhận kết nối từ máy tính Windows. Terminal trên máy này vẫn dùng bình thường." en "ShellX for Mac doesn't accept connections from Windows PCs yet. Terminals on this PC work as usual."
- `SignInOnYourMac`: vi "Đăng nhập ShellX trên Mac bằng cùng tài khoản để thấy Mac ở đây." en "Sign in to ShellX on your Mac with the same account to see it here."

- [ ] **Step 1: Write the failing tests**

```rust
#[test] fn only_macs_the_relay_says_can_host_get_request_access() {
    // online mac can_host → RequestAccess; online mac !can_host → None; online windows can_host → None;
    // offline mac can_host → None; granted mac !can_host → Open; pending mac !can_host → ShowCode("123456")
}
#[test] fn any_mac_rule_offers_every_online_mac_but_never_a_pc() { /* build_groups_with(.., AnyMac) */ }
#[test] fn offer_rule_reads_the_environment_value() {
    // None, Some(""), Some("0"), Some("true"), Some("yes") → RelayCanHost; Some("1"), Some(" 1 ") → AnyMac
}
#[test] fn request_targets_skip_this_machine_linked_and_unofferable() { /* has_link("m2") excluded */ }
#[test] fn request_panel_notes_tell_the_truth() {
    // [this PC] → [MacCannotHostYet, SignInOnYourMac]; [this PC, a PC] → same; [.., mac !can_host] → [MacCannotHostYet];
    // [.., mac can_host] → []; [.., mac !can_host] with AnyMac → []
}
#[test] fn can_host_reads_true_only_for_json_true() { /* absent, false, null, "true", 1 → false; true → true */ }
// strings.rs: exact vi/en text of the two sentences; all_has_no_duplicates → Str::ALL.len() == 111
// shell_info.rs sidebar_machines_this_pc_first_then_server_list: the online windows "m-other" now → RowAction::None;
//   add an online mac with can_host → RequestAccess
// core_service.rs sign_in_with_a_mac_already_in_the_account: build_groups(flow.machines(), &|_| Access::None, 0, Lang::Vi)
//   gives the Mac RowAction::None (the relay sent no can_host)
```
- [ ] **Step 2: Run to verify they fail**: MODEL → compile errors (`can_host`, `OfferRule`, `Str::MacCannotHostYet` missing).
- [ ] **Step 3: Implement** in `sidebar.rs` and `strings.rs`; add `can_host: false` to the literals listed under Files (for `this_machine()`, `false`).
- [ ] **Step 4: Run**: MODEL → all pass; APP → all pass.
- [ ] **Step 5: Commit**: `feat(windows): offer access only to Macs the relay says can host; say why the list is empty; SHELLX_OFFER_ALL_MACS=1 for Part 2 testing`.

### Task L6: Sign-out in the error state; sentences instead of codes

**Files:**
- Modify: `windows/shellx-model/src/account.rs` (field, `can_sign_out`, transitions), `windows/shellx-model/src/strings.rs` (`Str`, `failure_sentence`, `google_error:551`)
- Test: `account.rs`, `strings.rs` (`google_error_maps_codes:870-873`, count test)

**Interfaces:**
- Produces: `AccountFlow::can_sign_out(&self) -> bool` (Ruling 17, private field `has_session: bool`, cleared in `reset_session`); `strings::failure_sentence(lang: Lang, code: &str) -> String` (Ruling 16); `Str::{ServerProblem, RateLimited, SignInUnavailable}`.

Sentences (the email-first plan's catalog wording, unchanged):
- `ServerProblem`: vi "ShellX đang gặp sự cố. Thử lại sau." en "ShellX is having a problem. Try again later."
- `RateLimited`: vi "Thử lại sau ít phút." en "Try again in a few minutes."
- `SignInUnavailable`: vi "Bản này chưa dùng được cách đăng nhập này." en "This way of signing in isn't available in this build."

- [ ] **Step 1: Write the failing tests**

```rust
#[test] fn sign_out_is_offered_in_the_error_state_and_ends_the_retry_loop() {
    // LoggedOut → LoginSubmitted → LoginResult(Ok) → [CallList] → ListResult(Err(bad_response "machines.list: …"))
    // state Error, can_sign_out(); LogoutRequested → [CallLogout]; LogoutResult(Ok) → LoggedOut, !can_sign_out();
    // Tick(100_000) → []
}
#[test] fn no_sign_out_after_a_first_sign_in_failed() { /* LoggedOut → LoginResult(Err(invalid_credentials)) → Error, !can_sign_out() */ }
#[test] fn startup_error_with_a_session_offers_sign_out() { /* Started → ListResult(Err(network)) → Error, can_sign_out() */ }
#[test] fn register_failure_offers_sign_out() { /* login ok → list [] → CallRegister → Registered(Err(invalid_machine)) → can_sign_out() */ }
// strings.rs
#[test] fn failure_sentences_never_show_codes() {
    // both langs: network → RelayUnreachable; rate_limited → RateLimited;
    // not_found, http_404, not_configured, email_sign_in_disabled, password_sign_in_removed → SignInUnavailable;
    // switch_from_signed_in_device → SwitchFromSignedInDevice;
    // bad_response, server, http_502, io, invalid_machine, "" → ServerProblem;
    // and for each output: !contains('_') && !contains("http")
}
// google_error_maps_codes: google_error(lang, "rate_limited") == Some(t(lang, Str::RateLimited).to_string());
//   google_error(lang, "not_configured") == Some(t(lang, Str::SignInUnavailable).to_string())
// exact vi/en of the three sentences; Str::ALL.len() == 114
```
- [ ] **Step 2: Run to verify they fail**: MODEL → compile errors.
- [ ] **Step 3: Implement**.
- [ ] **Step 4: Run**: MODEL → all pass; APP → all pass (`smoke.rs` keeps using `login_failed`).
- [ ] **Step 5: Commit**: `feat(windows): sign-out is allowed in the error state; account errors read as sentences (R4 Major 6, Minor 9, 10)`.

### Task L7: First-window size rule (R1 F2)

**Files:**
- Create: `windows/shellx-model/src/first_window.rs`; Modify: `windows/shellx-model/src/lib.rs`

**Interfaces:**
- Produces: `WorkArea`, `FirstWindow`, `first_window(WorkArea) -> FirstWindow`, `pub const PREFERRED: (f32, f32) = (1200.0, 760.0)`, `pub const MINIMUM: (f32, f32) = (720.0, 420.0)` (Ruling 18).

- [ ] **Step 1: Write the failing tests** (work areas in logical px, Windows 11 taskbar 48 px at the bottom unless named)

```rust
#[test] fn first_window_fits_the_four_screens_of_r1() {
    // (screen, work area x,y,w,h) → expect x,y,w,h,maximized
    // 1920×1080 @150%: (0,0,1280,672) → (40,0,1200,672,false)
    // 1366×768 @100%:  (0,0,1366,720) → (83,0,1200,720,false)
    // 2160×1440 @200%: (0,0,1080,672) → (0,0,1080,672,false)
    // 2256×1504 @200%: (0,0,1128,704) → (0,0,1128,704,false)
    // 3840×2160 @300%: (0,0,1280,672) → (40,0,1200,672,false)
}
#[test] fn large_screens_keep_1200_by_760_centred() {
    // 1920×1080 @100%: (0,0,1920,1032) → (360,136,1200,760,false); @125%: (0,0,1536,816) → (168,28,1200,760,false)
}
#[test] fn first_window_stays_inside_a_work_area_that_does_not_start_at_zero() {
    // taskbar left: (48,0,1232,720) → (64,0,1200,720,false); monitor left of primary: (-1920,0,1920,1032) → (-1560,136,1200,760,false)
    // taskbar top: (0,48,1280,672) → (40,48,1200,672,false)
}
#[test] fn small_screens_shrink_or_open_maximized() {
    // 800×600: (0,0,800,560) → (0,0,800,560,false); 640×480: (0,0,640,440) → (0,0,640,440,true);
    // fractional 1366×768 @125%: (0,0,1092.8,566.4) → (0,0,1092.8,566.4,false)
}
#[test] fn a_broken_work_area_opens_maximized() { /* w or h 0, negative, NaN, inf → maximized true, width 1200, height 760 */ }
```
- [ ] **Step 2: Run to verify they fail**: MODEL → `first_window` missing.
- [ ] **Step 3: Implement**: `W = min(1200, wa.w)`, `H = min(760, wa.h)`, `x = wa.x + ((wa.w − W) / 2).floor()`, `y` likewise; `maximized = W < 720 || H < 420`; non-finite or ≤ 0 width/height → `x`, `y` = `wa.x`, `wa.y` when finite else 0, size 1200×760, maximized.
- [ ] **Step 4: Run**: MODEL → all pass.
- [ ] **Step 5: Commit**: `feat(windows): first-window size fits the work area (R1 F2)`.

### Task L8: Touchpad scroll accumulator and the alternate-screen wheel (R2 F2, F13)

**Files:**
- Create: `windows/shellx-model/src/mouse.rs`; Modify: `lib.rs`

**Interfaces:**
- Produces: `ScrollAccumulator`, `ScreenModes`, `WheelAction`, `wheel_action` (Rulings 19, 20).

GPUI-Windows sends `ScrollDelta::Lines(delta / 120 × 3)` per `WM_MOUSEWHEEL` (R2 F2): a notch is 3.0 lines; touchpad messages of delta 8 or 30 are 0.2 or 0.75 lines.

- [ ] **Step 1: Write the failing tests**

```rust
#[test] fn a_wheel_notch_scrolls_three_lines() { /* add(3.0) == 3 twice; add(-3.0) == -3 */ }
#[test] fn touchpad_steps_add_up() {
    // five add(0.2) → [0,0,0,0,1]; four add(0.75) → [0,1,1,1]; forty add(0.2) sum == 8
}
#[test] fn a_change_of_direction_drops_the_remainder() { /* add(0.6)==0; add(-0.2)==0; add(-0.9)==-1 */ }
#[test] fn odd_deltas_never_panic() {
    // add(0.6)==0; add(f64::NAN)==0; add(f64::INFINITY)==0; add(f64::NEG_INFINITY)==0; add(0.6)==1 (the 0.6 survived);
    // fresh: add(1e12) == 1000 then add(0.5) == 0 (remainder dropped); add(-1e12) == -1000
}
#[test] fn the_wheel_scrolls_back_on_the_primary_screen() { /* wheel_action(3, {alternate:false, mouse:false|true}) == Scrollback(3) */ }
#[test] fn the_wheel_sends_arrows_in_full_screen_programs() {
    // ({alternate:true, mouse_reporting:false}): 3 → Arrows{key:"up",count:3}; -2 → Arrows{key:"down",count:2}
    // ({alternate:true, mouse_reporting:true}): 3 → None; 0 with any modes → None
}
```
- [ ] **Step 2: Run to verify they fail**: MODEL → `mouse` missing.
- [ ] **Step 3: Implement**: `add`: ignore non-finite; reset when signs differ; `rem += lines`; `whole = (rem + rem.signum() * 1e-6).trunc()`; `rem -= whole`; return `whole.clamp(-1000.0, 1000.0) as i32`, dropping the remainder when clamped.
- [ ] **Step 4: Run**: MODEL → all pass.
- [ ] **Step 5: Commit**: `feat(windows): touchpad scrolling accumulates; the wheel sends arrows in full-screen programs (R2 F2, F13)`.

### Task L9: Shortcut shapes GPUI-Windows reports (R2 F5, F7)

**Files:**
- Modify: `windows/shellx-model/src/keys.rs:78-127`
- Test: `keys.rs` tests, `modal.rs` tests

**Interfaces:**
- Produces: `pub fn is_window_system_key(k: &KeyIn) -> bool` (Alt held alone with `f4` or `space`); `map_key` changes per Rulings 23, 24.

Inputs from the probe (`…/scratchpad/windows-review/keyprobe/src/main.rs`): Alt+Shift+= arrives as `KeyIn { key: "+", alt: true, shift: false, .. }`, Alt+Shift+- as `key: "_"`, Alt+F4 as `key: "f4", alt: true`, Alt+Space as `key: "space", alt: true`.

- [ ] **Step 1: Write the failing tests**

```rust
#[test] fn split_shortcuts_as_gpui_windows_reports_them() {
    // alt("+") → App(SplitRight); alt("_") → App(SplitDown); the Mac shapes alt_shift("=") / alt_shift("-") still split;
    // alt("=") → Chord("alt+="); alt("-") → Chord("alt+-")
}
#[test] fn alt_f4_and_alt_space_go_to_windows() {
    // alt("f4") and alt("space") → Ignore; is_window_system_key true for both;
    // alt_shift("f4") → Chord("alt+shift+f4"), k("f4") → Chord("f4"), ctrl("f4") → Chord("ctrl+f4"), is_window_system_key false for these
}
// modal.rs: with Panels { settings: true, .. } and with forced_update, root_key(&map_key(&alt("f4"), &NO_SEL), false) == RootKey::Pass
```
- [ ] **Step 2: Run to verify they fail**: MODEL → `alt("+")` gives `Chord("alt++")`, `alt("f4")` gives `Chord("alt+f4")`; `is_window_system_key` missing.
- [ ] **Step 3: Commit the red tests** (with `is_window_system_key` stubbed to `false` so it compiles): `test(windows): Alt+Shift+=/- and Alt+F4 as GPUI-Windows reports them [red]`.
- [ ] **Step 4: Implement**: in `app_binding`, `(false, true, false, "+")` → `SplitRight`, `(false, true, false, "_")` → `SplitDown`; in `map_key`, after the composing/Win check, `is_window_system_key(k)` → `Ignore`.
- [ ] **Step 5: Run**: MODEL → all pass.
- [ ] **Step 6: Commit**: `fix(windows): split shortcuts work with GPUI-Windows key shapes; Alt+F4 and Alt+Space reach Windows (R2 F5, F7)`.

### Task L10: Multi-line paste and right-click rules (R2 F18, F10, F4)

**Files:**
- Modify: `windows/shellx-model/src/paste.rs`, `windows/shellx-model/src/mouse.rs`

**Interfaces:**
- Produces: `paste::needs_paste_confirmation(text: &str, bracketed: bool) -> bool`; `mouse::{SecondaryButton, PaneClick, secondary_click}` (Rulings 21, 22).

- [ ] **Step 1: Write the failing tests**

```rust
#[test] fn multi_line_means_text_after_a_newline() {
    // false: "echo hi", "echo hi\n", "echo hi\r\n", "a\n  \t\n", "a\n\u{00A0}", ""
    // true:  "a\nb", "a\r\nb\r\n", "a\rb", "\nb", "echo 1\necho 2\necho 3"
}
#[test] fn a_bracketed_paste_never_asks() { /* needs_paste_confirmation("a\nb", true) == false */ }
#[test] fn secondary_clicks_follow_the_windows_console() {
    // unfocused pane: Right and Middle, with or without selection → FocusOnly
    // focused: Right + selection → CopySelection; Right, no selection → Paste; Middle → Nothing
}
```
- [ ] **Step 2: Run to verify they fail**: MODEL → missing items.
- [ ] **Step 3: Implement**.
- [ ] **Step 4: Run**: MODEL → all pass.
- [ ] **Step 5: Commit**: `feat(windows): rules for multi-line paste confirmation and right/middle clicks (R2 F18, F10, F4)`.

### Task L11: Command lines by Windows rules, and finding the program

**Files:**
- Create: `windows/shellx-model/src/shell.rs`; Modify: `lib.rs`

**Interfaces:**
- Produces: `parse_command_line`, `CommandLineError::{Empty, UnclosedQuote}`, `ShellProbe` (`Default`), `pub fn resolve_program(program: &str, probe: &ShellProbe, exists: &dyn Fn(&str) -> bool) -> Option<String>`, `ShellLaunch`, `ShellKind`, `custom_launch`, `CustomShellError::{Empty, UnclosedQuote, NotFound(String)}` (Ruling 26).

Parsing: argv[0] — starting with `"`, everything up to the next `"`, else up to the first space or tab, no escape processing. Later arguments — space/tab separate outside quotes; `2n` backslashes + `"` → `n` backslashes and the quote toggles; `2n+1` backslashes + `"` → `n` backslashes and a literal `"`; other backslashes literal; inside quotes `""` → a literal `"` and stay quoted. A quote still open at the end → `UnclosedQuote`. Only whitespace → `Empty`.
Resolving: a program containing `\`, `/` or `:` is checked as given, then with `.exe` added when it has no extension; otherwise each `;`-separated `PATH` entry (surrounding quotes stripped, empty entries skipped) joined with `\`, plain then `.exe`. First existing wins.

- [ ] **Step 1: Write the failing tests**

```rust
#[test] fn command_lines_split_like_windows() {
    // r#""C:\Program Files\Git\bin\bash.exe" --login -i"# → [r"C:\Program Files\Git\bin\bash.exe", "--login", "-i"]
    // "wsl.exe -d Ubuntu" → ["wsl.exe","-d","Ubuntu"]; r#"cmd.exe /k "echo hi""# → ["cmd.exe","/k","echo hi"]
    // r#"bash -c "echo \"a b\"""# → ["bash","-c",r#"echo "a b""#]; r#""C:\x\\" a"# → [r"C:\x\\", "a"]
    // r#"x a\\\\"b c""# → ["x", r"a\\b c"]; r#"x a\\\"b"# → ["x", r#"a\"b"#]; r"x a\b" → ["x", r"a\b"]; r#"x "a""b""# → ["x", r#"a"b"#]
    // "x\t\ty" → ["x","y"]
}
#[test] fn bad_command_lines_are_reported() { /* "", "   " → Empty; r#"pwsh -Command "C:\path\""# → UnclosedQuote */ }
#[test] fn programs_resolve_by_path_or_as_given() {
    // probe.path = r#"C:\Windows\system32;"C:\Program Files\Git\cmd";;C:\Users\Phú\scoop\shims"#
    // exists = {r"C:\Windows\system32\wsl.exe", r"C:\Users\Phú\scoop\shims\pwsh.exe", r"C:\Program Files\Git\bin\bash.exe"}
    // "wsl.exe" and "wsl" → r"C:\Windows\system32\wsl.exe"; "pwsh" → scoop path; the bash path → itself; r"C:\Program" → None; "nope" → None
}
#[test] fn custom_lines_name_the_missing_program() {
    // custom_launch(r#""C:\Program Files\Git\bin\bash.exe" --login -i"#) → Ok { kind: None, program: that path, args: ["--login","-i"], osc7_hook: false }
    // custom_launch(r"C:\Program Files\Git\bin\bash.exe --login") → Err(NotFound(r"C:\Program".into())); "" → Err(Empty)
}
```
- [ ] **Step 2: Run to verify they fail**: MODEL → `shell` missing.
- [ ] **Step 3: Implement**.
- [ ] **Step 4: Run**: MODEL → all pass.
- [ ] **Step 5: Commit**: `feat(windows): parse a custom shell command line by Windows rules and find its program`.

### Task L12: Shell catalogue, choice and fallback order (R3 M1, m4)

**Files:**
- Modify: `windows/shellx-model/src/shell.rs`

**Interfaces:**
- Consumes: Task L11.
- Produces: `find_shells`, `ShellChoice` (serde, values under "Interfaces for the later plans"), `LaunchPlan`, `ShellError`, `launch_plan` (Ruling 25); PowerShell entries get `args = ["-NoLogo", "-NoExit", "-Command", POWERSHELL_PROMPT_HOOK]` and `osc7_hook: true`. This task defines `pub const POWERSHELL_PROMPT_HOOK: &str` as today's `local_pty.rs:204` `POWERSHELL_HOOK` text, unchanged; Task L13 changes it.

Paths: Pwsh = first `PATH` entry with `pwsh.exe`, else `{ProgramFiles}\PowerShell\7\pwsh.exe`; WindowsPowerShell = `{SystemRoot}\System32\WindowsPowerShell\v1.0\powershell.exe`; Cmd = `ComSpec` if it exists, else `{SystemRoot}\System32\cmd.exe`; GitBash = `{git_install_path}\bin\bash.exe`, else `{ProgramFiles}\Git\bin\bash.exe`, args `["--login", "-i"]`; Wsl = `{SystemRoot}\System32\wsl.exe`, no args. `SystemRoot` absent → `C:\Windows`; trailing `\` of a base is trimmed before joining.

- [ ] **Step 1: Write the failing tests**

```rust
// probe: system_root r"C:\Windows", program_files r"C:\Program Files", comspec r"C:\Windows\system32\cmd.exe",
//   path r"C:\Windows\System32;C:\Users\Phú\AppData\Local\Microsoft\WindowsApps", git_install_path r"D:\Tools\Git"
// ALL = {r"C:\Program Files\PowerShell\7\pwsh.exe", r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe",
//        r"C:\Windows\system32\cmd.exe", r"D:\Tools\Git\bin\bash.exe", r"C:\Windows\System32\wsl.exe"}
// (the test's `exists` compares strings exactly; Windows' own lookup ignores case)
#[test] fn every_installed_shell_is_found_in_order() { /* kinds [Pwsh, WindowsPowerShell, Cmd, GitBash, Wsl] with the paths and args above */ }
#[test] fn pwsh_on_path_wins() { /* ALL + r"C:\Users\Phú\AppData\Local\Microsoft\WindowsApps\pwsh.exe" → Pwsh program is that one */ }
#[test] fn a_plain_windows_finds_powershell_and_cmd() { /* only powershell.exe and cmd.exe → [WindowsPowerShell, Cmd]; comspec None + System32\cmd.exe → Cmd found */ }
#[test] fn auto_prefers_pwsh_and_falls_back_once() {
    // ALL: first Pwsh, fallback WindowsPowerShell; powershell+cmd: WindowsPowerShell then Cmd; cmd only: Cmd, None; nothing: Err(NoShellFound)
}
#[test] fn a_chosen_shell_falls_back_to_auto() {
    // Known{GitBash} with ALL → GitBash then Pwsh; Known{Pwsh} → Pwsh then WindowsPowerShell; Known{GitBash} without git → the Auto plan
    // Custom{"wsl.exe -d Ubuntu"} (wsl on PATH) → custom first, Pwsh fallback; Custom unresolvable → Err(Custom(NotFound))
}
#[test] fn shellx_shell_keeps_old_values_working() {
    // with ALL + r"C:\Program Files\Git\bin\bash.exe" + r"C:\Users\Phú\AppData\Local\Microsoft\WindowsApps\pwsh.exe":
    // override r"C:\Program Files\Git\bin\bash.exe" (unquoted, exists) → program that, args [] (beats Known{Pwsh}), fallback Auto first
    // override r#""C:\Program Files\Git\bin\bash.exe" -l"# → args ["-l"]; override "pwsh" → the WindowsApps path (first on PATH)
    // override "   " → ignored; override "nope.exe" → Err(Override(NotFound("nope.exe")))
}
#[test] fn the_choice_is_stored_as_small_json() {
    // Auto ↔ {"kind":"auto"}; Known{GitBash} ↔ {"kind":"known","shell":"git_bash"}; WindowsPowerShell ↔ "windows_powershell";
    // Custom ↔ {"kind":"custom","command_line":"wsl.exe"}; {"kind":"bash"} fails to parse
}
```
- [ ] **Step 2: Run to verify they fail**: MODEL → missing items.
- [ ] **Step 3: Implement**.
- [ ] **Step 4: Run**: MODEL → all pass.
- [ ] **Step 5: Commit**: `feat(windows): shell catalogue (PowerShell 7 first), user choice, SHELLX_SHELL command lines, one fallback (R3 M1, m4)`.

### Task L13: The prompt hook sends a percent-encoded directory (R3 m1)

**Files:**
- Modify: `windows/shellx-model/src/shell.rs` (`POWERSHELL_PROMPT_HOOK`, `osc7_url`)
- Test: `shell.rs`; `windows/shellx-app/src/cwd.rs` tests

**Interfaces:**
- Produces: `POWERSHELL_PROMPT_HOOK` (below), `osc7_url(computer_name: &str, provider_path: &str) -> String` = `file://{computer}/` + the path split on `\`, each segment percent-encoded per UTF-8 byte keeping only `A-Z a-z 0-9 - . _ ~` (uppercase hex, as .NET `EscapeDataString`), joined with `/` (Ruling 27).

Hook text (today's `local_pty.rs` hook with the encoding swapped in; no backslash stands before a double quote, so portable-pty's quoting passes it byte-exact):
```text
if ($function:prompt) { $__shellxPrompt = $function:prompt; function global:prompt { $p = & $__shellxPrompt; $l = $ExecutionContext.SessionState.Path.CurrentLocation; if ($l.Provider.Name -eq 'FileSystem') { [Console]::Write([char]27 + ']7;file://' + $env:COMPUTERNAME + '/' + ((($l.ProviderPath -split '\\') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/') + [char]27 + '\') }; $p } } else { function global:prompt { $l = $ExecutionContext.SessionState.Path.CurrentLocation; if ($l.Provider.Name -eq 'FileSystem') { [Console]::Write([char]27 + ']7;file://' + $env:COMPUTERNAME + '/' + ((($l.ProviderPath -split '\\') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/') + [char]27 + '\') }; "PS $($l.Path)> " } }
```

- [ ] **Step 1: Write the failing tests**

```rust
// shell.rs
#[test] fn the_hook_percent_encodes_the_directory() {
    // contains "[uri]::EscapeDataString" and "]7;file://"; does not contain "-replace '\\\\','/'"; does not contain "\\\""
}
#[test] fn osc7_urls_are_ascii_whatever_the_folder() {
    // ("PC", r"C:\Users\Phú\Tài liệu") → "file://PC/C%3A/Users/Ph%C3%BA/T%C3%A0i%20li%E1%BB%87u"
    // ("PC", r"C:\") → "file://PC/C%3A/"; ("PC", r"\\srv\share\Dự án") → "file://PC///srv/share/D%E1%BB%B1%20%C3%A1n"
    // ("PC", r"C:\a%b") → "file://PC/C%3A/a%25b"; every output is ASCII
}
// cwd.rs (shellx-app)
#[test] fn percent_encoded_osc7_round_trips() {
    // for P in [r"C:\Users\Phú\Tài liệu", r"C:\", r"\\srv\share\Dự án", r"C:\a%b", r"D:\100% done"]:
    //   cwd_from_osc7(&shellx_model::shell::osc7_url("PC", P)) == Some(P.to_string())
}
```
- [ ] **Step 2: Run to verify they fail**: MODEL → `osc7_url` missing / hook without `EscapeDataString`.
- [ ] **Step 3: Implement**.
- [ ] **Step 4: Run**: MODEL → all pass; APP → all pass.
- [ ] **Step 5: Commit**: `feat(windows): the PowerShell prompt hook sends the folder percent-encoded as UTF-8 (R3 m1)`.

### Task L14: The redactor

**Files:**
- Create: `windows/shellx-model/src/redact.rs`; Modify: `lib.rs`

**Interfaces:**
- Produces: `pub fn redact(text: &str) -> String`, idempotent, no panic on any input; replacements `<email>`, `<key>`, `<token>`, `<code>`.

Rules, applied in this order:
1. Email → `<email>`: around each `@`, a local part of one or more chars that are alphanumeric (Unicode) or in `._%+-`, and a domain of alphanumeric or `-` labels joined by `.`, at least two non-empty labels (trailing `.`/`-` not taken).
2. Resend key → `<key>`: `re_` not preceded by an alphanumeric or `_`, followed by at least 8 of `[A-Za-z0-9_]`.
3. Token → `<token>`: a maximal run of `[A-Za-z0-9_+/-]` plus any trailing `=`, at least 32 chars without the `=`, except a run of only `[0-9A-Fa-f-]` (ids, hashes, commits) and a run that contains `/` but no ASCII digit (plain paths).
4. Code → `<code>`: exactly 6 ASCII digits with no digit on either side, when the 24 chars before or after on the same line contain (case-insensitive) `code`, `otp` or `mã`.

- [ ] **Step 1: Write the failing tests**

```rust
const T43: &str = "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-AbCdE"; // 43 chars, base64url
#[test] fn redacts_each_kind() {
    // "signed in as phu.le+test@gmail.com via email" → "signed in as <email> via email"; "user Phú@ví-dụ.vn" → "user <email>"
    // "RESEND_API_KEY=re_AbCdEf123_xyz" → "RESEND_API_KEY=<key>"; "your code is 123456" → "your code is <code>"; "Mã: 112233" → "Mã: <code>"
}
#[test] fn redacts_secrets_in_json_urls_and_headers() {
    // format!("Authorization: Bearer {T43}") → "Authorization: Bearer <token>"; format!(r#"{{"token":"{T43}"}}"#) → r#"{"token":"<token>"}"#
    // format!("GET /cb?code=123456&state={T43}") → "GET /cb?code=<code>&state=<token>"; format!("{T43}.{T43}") → "<token>.<token>"
    // format!("panicked at src/ui/account.rs:12:5:\nlogin failed for a@b.co with {T43}") → no "a@b.co", no T43
    // "+/v7"×10 + "+/s=" → "<token>"
}
#[test] fn keeps_paths_ids_and_versions_readable() {
    // unchanged: r"C:\Users\Phú\Tài liệu\dự án", "machine 0e7a1c2b-3d4e-4f50-8a9b-0c1d2e3f4a5b online",
    // "commit c06834ec4e5f7a8b9c0d1e2f3a4b5c6d7e8f9a0b", "GPU Intel(R) UHD Graphics 620 driver 31.0.101.2125",
    // "https://relay.shellx.pro/v2/relay", "/Users/richard/Documents/helper/shellx", "1920x1080 150%", "pid 123456 started",
    // "1234567 code", "prepare_something re_x"
}
#[test] fn redaction_is_idempotent_and_total() {
    // redact(redact(s)) == redact(s) for every string above; no panic for "@", "@@@", "a@", "@b.c", "ế@ê.ễ", "re_", 10_000 × "a"
}
```
- [ ] **Step 2: Run to verify they fail**: MODEL → `redact` missing.
- [ ] **Step 3: Implement** by scanning chars (no regex: Part L adds no dependency).
- [ ] **Step 4: Run**: MODEL → all pass.
- [ ] **Step 5: Commit**: `feat(windows): redactor for log, crash and report lines (emails, tokens, codes, keys)`.

### Task L15: Account types never print emails or machine names in Debug

**Files:**
- Modify: `windows/shellx-model/src/account.rs` (`AccountFlow` Debug, `LoginSubmitted` and `CallLogin` arms), `sidebar.rs` (`MachineInfo` Debug), `core_api.rs` (`SignInMethod` Debug)

**Interfaces:**
- Produces: hand-written `Debug` (Ruling 28): `AccountFlow` shows `state`, machine count, flags, `email: <set>|<none>`, method count; `MachineInfo` shows `machine_id`, `platform`, `online`, `can_host`, `is_this_machine`, `name: <n chars>`; `SignInMethod` shows `identity_id`, `provider`, `is_private_email`; `LoginSubmitted`/`CallLogin` show `email: "<redacted>"`.

- [ ] **Step 1: Write the failing test**

```rust
#[test] fn account_debug_never_shows_emails_or_machine_names() {
    // a flow signed in by Google as "secret.person@example.com", machines named "Phú's MacBook" and "Bếp-PC",
    // methods with email "secret.person@example.com" and linked_via_device_name "iPhone của Phú";
    // Debug of the flow, of LoginSubmitted { email: "secret.person@example.com", .. }, of CallLogin, of each MachineInfo
    // and SignInMethod contains none of "secret.person", "Phú's MacBook", "Bếp-PC", "iPhone của Phú"
}
```
- [ ] **Step 2: Run to verify it fails**: MODEL → the derived `Debug` prints them.
- [ ] **Step 3: Implement**; update the two tests that read the email from `Debug`: `core_service.rs:407` and the first entry of Task L2's `sign_in_with_a_mac_already_in_the_account` become `"CallLogin { email: \"<redacted>\", password: \"<redacted>\" }"` (`grep -rn 'email: \\"' windows/shellx-app/src windows/shellx-model/src` finds no others today).
- [ ] **Step 4: Run**: MODEL → all pass; APP → all pass.
- [ ] **Step 5: Commit**: `feat(windows): account and machine values hide emails and names in Debug output`.

### Task L16: Diagnostics report model and formatter

**Files:**
- Create: `windows/shellx-model/src/diagnose.rs`; Modify: `lib.rs`

**Interfaces:**
- Consumes: Task L14 `redact`.
- Produces (all `Clone, Debug, Default`):
  - `Check { name: String, ok: bool, millis: Option<u64>, detail: String }`
  - `DisplayInfo { name: String, width_px: u32, height_px: u32, scale_percent: u32, work_area: (i32, i32, u32, u32) }`
  - `GpuInfo { name: String, driver: String, feature_level: String }`
  - `DiagnosticsReport { app_version, commit, build_kind, created_utc, windows_version, cpu: String; cpu_features: Vec<String>; displays: Vec<DisplayInfo>; first_window, chosen_gpu, render_mode, dwm_timing: String; gpus: Vec<GpuInfo>; keyboard_layouts, input_methods, typing_tools_running, shells_found: Vec<String>; shell_chosen: String; shell_checks: Vec<Check>; state_dir: Check; sign_in: String /* "signed out" or the method, never the address */; relay: Check /* version.check result and time */; crash_files: Vec<String>; log_tail: Vec<String> }`
  - `pub const LOG_TAIL_LINES: usize = 200;` `pub fn format_report(r: &DiagnosticsReport) -> String`.

Format: first line `ShellX diagnostics`, then sections in this order, each a `[name]` line followed by `key: value` lines: `[app]`, `[windows]`, `[cpu]`, `[displays]`, `[gpu]`, `[keyboard]`, `[shells]`, `[state]`, `[account]`, `[relay]`, `[crash files]`, `[log: last 200 lines]`. An empty value reads `unknown`, an empty list `none`; a check reads `ok`/`failed`, its time in ms and its detail. Only the last `LOG_TAIL_LINES` log lines are written. Every output line goes through `redact` (Ruling 29).

- [ ] **Step 1: Write the failing tests**

```rust
#[test] fn report_lists_every_section_in_order() { /* the 12 headers appear in order */ }
#[test] fn report_redacts_planted_secrets_everywhere() {
    // fill every String and every list entry (log_tail, crash_files, check details, GPU names, shells, layouts) with
    // "phu@example.com", T43 (the 43-char token), "code 123456", "re_AbCdEfGh123";
    // output contains none of the four, and contains "<email>"
}
#[test] fn report_keeps_only_the_last_200_log_lines() {
    // log_tail "line 0".."line 249": some output line == "line 249" and one == "line 50"; no output line == "line 49"
}
#[test] fn empty_values_read_unknown_or_none() { /* Default report: "windows: unknown", "crash files" section shows "none" */ }
```
- [ ] **Step 2: Run to verify they fail**: MODEL → `diagnose` missing.
- [ ] **Step 3: Implement**.
- [ ] **Step 4: Run**: MODEL → all pass.
- [ ] **Step 5: Commit**: `feat(windows): diagnostics report model and text formatter, redacted line by line`.

---

## Finishing each part

Part T, from its worktree:
```bash
(cd windows && cargo test --locked -p shellx-model)              # 192 passed
(cd windows && cargo test --release --locked -p shellx-app)      # 142 passed
scripts/shellx/check-windows-build.sh                            # OK (or --vps)
windows/vendor/check-gpui.sh                                     # 1 patched file(s): build.rs
python3 scripts/verify-local.py --affected develop               # report what it ran and its result
git log --oneline develop..HEAD                                  # T1 (or T3), T2, T4 ×2, T5
```
Part L, from its worktree: MODEL (192 + the new tests), CORE (236 + new), APP (142 + new), `(cd relay && npm test)`, `swift test --package-path Packages/Shared/ShellXBrand`, `python3 scripts/verify-local.py --affected develop`, `git diff --stat develop -- windows/Cargo.lock shellx-core/Cargo.lock` (empty), and `git diff --stat develop -- Packages Sources` (empty).

Each part's report lists: commits, red and green outputs of the bug-fix tasks, test counts, times (T1/T5), any finding the orchestrator must decide (Windows-only code that fails to compile, gpui lint errors, VPS disk).

## Not verified while writing this plan (guesses)

- That cargo-xwin 0.23.1 publishes an `aarch64-unknown-linux-musl` build and that zig 0.16.0's arm64 tarball is named `zig-aarch64-linux-0.16.0.tar.xz` (Task T1 has a `cargo install` fallback for the first).
- That `cargo xwin check` works from an arm64 Linux container (bindgen for ghostty-vt-sys, zig cross-compiling libghostty-vt for `x86_64-windows-msvc`), and its cold and warm times and memory within 6 GB; the 10-minute warm goal is the spec's.
- 14 GiB as the VPS minimum free space; the VPS's current free space was not read.
- That gpui 0.2.2 compiles without errors when its `deny` lints are no longer capped (a path dependency) under Rust 1.95.
- That Windows-only test code in `shellx-app` still compiles for Windows (not compiled since 2026-10-19).
- The exact shapes of `GET /v1/account/identities` (`email` nullable) and of the requester pairing list (`sealed_invite_b64` optional); the relay test arbitrates.
- The list of fake-relay drifts in Task L3 Step 4 (read from code, not run).
- That `[uri]::EscapeDataString` in Windows PowerShell 5.1 (.NET Framework 4.x) encodes exactly the RFC 3986 unreserved set as UTF-8; `osc7_url` assumes it.
- Baseline counts (192, 236, 142, `Str::ALL` 109) are today's; a merge into `develop` before the branches start would change them.

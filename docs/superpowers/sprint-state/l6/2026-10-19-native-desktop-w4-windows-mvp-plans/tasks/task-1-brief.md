# Task 1: Workspace, promote the GPUI spike, Windows CI

Binding constraints: `../constraints.md` (read it). Worktree `~/Documents/myProjects/shellx-wt-l6`, branch `shellx/l6-windows`.

## Goal
Create the Cargo workspace `windows/` with crates `shellx-model` (skeleton) and `shellx-app` (the GPUI spike promoted as-is, renamed), plus `.github/workflows/shellx-windows.yml`, push, and get CI green on GitHub (`lephus/shellx`).

## Source material
- Spike: local branch `shellx/w0-spikes`, dir `spikes/windows-term` (commit ada66c3042): Cargo.toml, Cargo.lock, build.rs, resources/{app_icon.ico, shellx-term.manifest, shellx-term.rc}, src/{main.rs, app.rs, session.rs, smoke.rs}. Inspect with `git show shellx/w0-spikes:<path>`; copy with `git show … > newpath` (do NOT check spikes/ into this branch).
- Spike workflow: `git show shellx/w0-spikes:.github/workflows/shellx-windows-spike.yml`, job `term-spike` (green run 39149103261 in the old repo). Reuse its steps/pins verbatim where applicable.
- `.github/actions/setup-cmux-tui-rust/` was deleted in this repo; restore it: `git checkout shellx/w0-spikes -- .github/actions/setup-cmux-tui-rust` (ruled by controller).

## Steps
1. `windows/Cargo.toml` = workspace: `members = ["shellx-model", "shellx-app"]`, `resolver = "3"`, `[workspace.package] version = "2.0.0", edition = "2024", rust-version = "1.91", license = "GPL-3.0-or-later", publish = false`, `[workspace.dependencies] serde = { version = "1", features = ["derive"] }, serde_json = "1"`, `[profile.release] codegen-units = 4` (from spike). Add `windows/.gitignore` with `/target`.
2. `windows/shellx-model/`: Cargo.toml (inherits workspace package fields; deps serde + serde_json from the workspace — add them NOW so later model tasks never touch Cargo.lock), `src/lib.rs` with a crate doc comment ("pure Rust model for the ShellX Windows app: no GPUI, no libghostty") and one smoke test (e.g. `VERSION` const = `env!("CARGO_PKG_VERSION")` asserted to equal "2.0.0"). Nothing else (Tasks 2–4 fill it).
3. `windows/shellx-app/`: the spike, with these changes only:
   - package name `shellx-app`, fields inherited from the workspace, `[[bin]] name = "shellx-desktop"`, path deps fixed for the new depth (`../../cmux-tui/crates/cmux-pty`, `../../cmux-tui/crates/ghostty-vt`), add `shellx-model = { path = "../shellx-model" }` (unused import is fine only if referenced; reference `shellx_model::VERSION` in `--version` handling, see below). Keep `gpui = { version = "=0.2.2", default-features = false }` under `[target.'cfg(windows)'.dependencies]`, `embed-resource = "3"` build-dep. Remove the spike's own `[workspace]` table and `[profile]` (workspace owns them).
   - resources renamed `resources/shellx.rc`, `resources/shellx.manifest` (update the .rc's manifest reference and build.rs paths; manifest assemblyIdentity name → `ShellX.Desktop`, version `2.0.0.0`; keep PerMonitorV2 DPI awareness exactly as the spike had it). Keep `app_icon.ico`.
   - `main.rs`: flags `--smoke` (spike smoke, unchanged behavior) and `--version` (prints `shellx-desktop <VERSION>` and exits 0). Window title "ShellX". Keep everything else of the spike (session.rs, smoke.rs, app.rs) unchanged apart from names/strings that say "spike" (env var `SHELLX_SPIKE_SHELL` → `SHELLX_SHELL`). Module restructuring is Task 5/7, not now.
   - Header comment in app.rs noting GPUI-derived code origin is only required where code is adapted from GPUI examples (spike app.rs is original; leave as is).
4. `windows/Cargo.lock`: start from the spike's Cargo.lock (proven resolution, gpui 0.2.2) copied into windows/, then let cargo update it for the new workspace (`cd windows && cargo metadata --format-version 1 >/dev/null` or `cargo tree -p shellx-model`). Must be committed; CI uses `--locked`. Do not run `cargo update` broadly.
5. Local Mac check (fast, no GPUI build): `cd windows && cargo test --locked -p shellx-model` passes; `cargo tree --locked -p shellx-app --target x86_64-pc-windows-msvc | head` resolves. Do NOT `cargo build -p shellx-app` on the Mac.
6. `.github/workflows/shellx-windows.yml` (name "ShellX Windows"):
   - `on: push: branches: [shellx/l6-windows, shellx/sprint]` with `paths: [windows/**, cmux-tui/crates/**, cmux-tui/Cargo.toml, .github/workflows/shellx-windows.yml, .github/actions/setup-cmux-tui-rust/**]`; plus `workflow_dispatch`. `permissions: {}` top level; `concurrency: group: shellx-windows-${{ github.ref }}, cancel-in-progress: true`.
   - job `model` on `ubuntu-24.04`, `permissions: contents: read`, timeout 20: checkout (same pinned sha as spike, persist-credentials false), `./.github/actions/setup-cmux-tui-rust`, `Swatinem/rust-cache` (same pin) with `workspaces: windows -> target`, key `shellx-model`, then `cargo test --locked -p shellx-model` in `windows/`.
   - job `app` on `windows-2025`, timeout 75, `permissions: contents: read`, env `TARGET: x86_64-pc-windows-msvc`: steps as spike `term-spike` (checkout, `bash scripts/ci/init-submodule.sh ghostty`, zig version via `scripts/ghostty-zig-version.sh`, `mlugg/setup-zig` pin, rust action, `rustup target add`, rust-cache `windows -> target` key `shellx-app`), build `cargo build --release --locked -p shellx-app --target "$TARGET"` (with `unset CMUX_GHOSTTY_SRC`), run `cargo test --locked -p shellx-model --target "$TARGET"`, stage `dist/shellx-desktop.exe` (+ any DLLs, dumpbin dependents as spike), upload artifact named `shellx-desktop` (retention 14), then headless smoke `timeout 180 ./…/shellx-desktop.exe --smoke` (same PASS-line logic as spike) and `--version` check (`grep -F "shellx-desktop 2.0.0"`; note GUI-subsystem exe may not print to a pipe in release — if so, the step must assert the exit code only and say why in a comment).
   - Keep action pins identical to the spike workflow (sha-pinned). No secrets, nothing published.
7. Commit (explicit paths), push `git push origin shellx/l6-windows`, watch `gh run watch -R lephus/shellx <id>` (use `gh run list -R lephus/shellx --branch shellx/l6-windows --workflow shellx-windows.yml -L 1`). Fix until both jobs are green. Cold Windows build ≈ 15–25 min. Iterate with pushes only when a fix is ready (batch).

## Acceptance
- `cargo test --locked -p shellx-model` green on the Mac and in CI `model`.
- CI `app` job green: release build, `--smoke` PASS, artifact `shellx-desktop` uploaded.
- Report: run id(s), artifact name, total CI time, any warnings.

## Commit message
`feat(shellx-windows): windows/ workspace, shellx-app from the GPUI spike, Windows CI`

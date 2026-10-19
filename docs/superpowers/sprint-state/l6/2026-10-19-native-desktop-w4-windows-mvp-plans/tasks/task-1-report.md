# Task 1 report: workspace, GPUI spike promoted, Windows CI

Status: DONE. Commit 41ca85e229 "feat(shellx-windows): windows/ workspace, shellx-app from the GPUI spike, Windows CI" (pushed to origin shellx/l6-windows). Single commit, no fix commits; shellx-model/src untouched since.

## Built
- windows/ workspace (resolver 3, edition 2024, version 2.0.0), crates shellx-model (VERSION const + 1 test; serde/serde_json already in deps) and shellx-app (spike promoted; bin shellx-desktop; --smoke, --version; title "ShellX"; app_id pro.shellx.desktop; SHELLX_SHELL env; resources shellx.rc/shellx.manifest, assemblyIdentity ShellX.Desktop 2.0.0.0, PerMonitorV2 kept).
- windows/Cargo.lock from the spike lock; cargo only added the new workspace members (no broad update). `--locked` works.
- .github/workflows/shellx-windows.yml (jobs model, app) and restored .github/actions/setup-cmux-tui-rust.

## Evidence
- Mac: `cargo test --locked -p shellx-model` 1 passed; `cargo tree --locked -p shellx-app --target x86_64-pc-windows-msvc` resolves.
- CI run 39165923924 (success, ~13.5 min total wall): model 39s; app 13m26s (release build 9m32s cold, smoke: PASS in 2.33s, `--version` printed "shellx-desktop 2.0.0" even from the GUI-subsystem exe via pipe, so the grep check passes for real). Artifact: shellx-desktop (retention 14).
- Warnings: `unused import: ChildKiller` (rustc, spike code, left as-is per brief); GitHub Node 20 deprecation notice for upload-artifact/setup-zig.

## Concerns
None blocking. Run was on the rust-cache cold; warm builds should be faster.

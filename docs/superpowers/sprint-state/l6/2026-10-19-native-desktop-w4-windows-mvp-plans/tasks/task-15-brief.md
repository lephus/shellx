# Task 15: README, accessibility stopgap, G1/G3 checklists

Binding constraints: `../constraints.md`. Docs only (no code changes unless a doc command is wrong).

## Files
- `windows/README.md` (English, concise): what the Windows MVP is; crates (`shellx-model`, `shellx-remote`, `shellx-app`) and what runs where (model tests on any OS; app builds only on `windows-2025` CI); how to get the build (`gh run download <run-id> -R lephus/shellx -n shellx-desktop` / `-n ShellX-Setup-2.0.0-sprint`); flags `--smoke`, `--smoke-ui-assets`, `--version`; env `SHELLX_LANG=en`, `SHELLX_SHELL`, `SHELLX_API_BASE` (debug builds only); state dirs (`%LOCALAPPDATA%\ShellX\native\{core,remote}`) and why they never overlap the Flutter app's; keyboard shortcuts table (from `shellx_model::keys`); coexistence with the Flutter ShellX (different AppId/exe/dir/Start-menu name); licenses/credits (GPL-3.0-or-later; cmux-tui crates; coolicons CC BY 4.0 "coolicons by Kryston Schwarze"; JetBrains Mono, Space Grotesk OFL 1.1; GPUI Apache-2.0).
- Accessibility stopgap section: GPUI 0.2.2 exposes no UI Automation tree, so Narrator cannot read the terminal grid or controls (G1 expectation). Stopgap in this build: window title = "ShellX — <focused tab title>" (Narrator reads window titles) — implement that one-liner in `ui/root.rs` if not already there (window.set_window_title on focus/tab/title change) — and the recommendation to use Windows Terminal for screen-reader-heavy work until UIA lands (post-sprint item). Do not invent other a11y features.
- Latency procedure section: Typometer vs Windows Terminal on the same PC, same font size, 5 runs each, record median/p95 (G1).
- `windows/G1-G3-CHECKLIST.md` (Vietnamese, for the user, short, checkboxes): G1 (on the spike or this build): Telex built-in / Unikey / EVKey typing `tiếng Việt` in PowerShell (committed text correct, candidate window position), 150 % and 200 % scaling crisp, Typometer vs Windows Terminal, Narrator (expected fail). G3: install `ShellX-Setup-2.0.0-sprint.exe` while the Flutter ShellX is installed and running (Flutter keeps running, both in Start menu), split/tabs/exit-last-shell, select + Ctrl+C / Ctrl+Shift+C / Ctrl+C interrupt, paste multi-line, sign in, the Mac appears in the sidebar, request access → code matches on the Mac → approve on the Mac → open the Mac terminal, type `tiếng Việt`, unplug network → "đang kết nối lại…" → reconnects; uninstall leaves the Flutter app intact. Each item: what to do, what "pass" looks like, where to report.
- The exact artifact download commands with the latest green run id (fill in from `gh run list -R lephus/shellx --branch shellx/l6-windows --workflow shellx-windows.yml -L 1`).

## Acceptance
- Docs match the code as built (verify every flag/env/shortcut against source). Stage only your files. Push with the last batch.

## Commit
`docs(shellx-windows): README, accessibility stopgap, G1/G3 checklists`

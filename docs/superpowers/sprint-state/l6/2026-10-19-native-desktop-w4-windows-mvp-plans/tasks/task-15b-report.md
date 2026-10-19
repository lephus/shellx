# Task 15b report

Commit 3cb8cc0b85 `docs(shellx-windows): refresh README and G1/G3 checklists for the remote view and final-wave changes` (only windows/README.md and windows/G1-G3-CHECKLIST.md).

## Changed
README: CI step `Test shellx-app`; 14-day artifact retention; `--smoke` description (fake-backed core/account/pairing/remote-session/remote-tab flows, then ConPTY); state dirs (`core\tickets\invite-*.uri` deleted after first enrolled connect); modal rule (Esc closes topmost panel, shortcuts swallowed); new "Remote view" section (Mở from sidebar/pairing panel, second Mở = new shell, split, pill texts, input refused/flash, exit closes one pane, sign-out closes remote tabs, respawn-storm guard 5 per 10 s); a11y stopgap wording (focused pane only, Narrator expected not to read the grid, Windows Terminal); licenses stated exactly.
Checklist: run id 39205433045 (head 0f7d20ca36) with the controller-refresh note, 14-day retention; G1 IME items split TSF Telex vs Unikey/EVKey (backspace modes, pass = final line correct, tool property); G3 now 20 checkbox lines (pairing, open from panel/sidebar, byte-exact Telex via cat|xxd, paste with ESC[201~ into cat -v, resize/stty size, split, disconnect/reconnect, exit, sign-out, modal Esc, title/Narrator, 100/150 % visual).

## Verified against source
Flags in main.rs (--version, --smoke, --smoke-ui-assets, --smoke-panes only; no --smoke-remote flag exists, so none listed); SHELLX_LANG/SHELLX_SHELL (local_pty.rs default_shell)/SHELLX_API_BASE (debug only, core_service.rs); keys.rs bindings; paths.rs dirs; modal.rs; RespawnGuard constants (tabs.rs); strings.rs pill/flash texts; remote_tabs.rs overlay mapping; title format (term_view.rs prepaint, BASE_TITLE); CI step in shellx-windows.yml; licenses (cmux-tui/Cargo.toml workspace `license = "MIT"`; root LICENSE: GPL-3.0-or-later unless a file says otherwise, BUSL only in listed dirs).

## Not verified / concerns
- `gh` is not installed here: could not check run 39205433045 status or artifact names; controller must refresh the run id.
- License is ambiguous in the tree: cmux-tui crates declare MIT while root LICENSE says GPL-3.0-or-later for cmux material; README states both facts verbatim rather than picking one. There is no LICENSE file inside cmux-tui/.
- README claims the ConPTY part of `--smoke` fails on non-Windows (from the 13b report: "later PowerShell step fails as before"), not re-run.
- Nothing in the UI was run (GPUI is Windows-only); checklist expectations come from the 13b "Needs user" list and source. modal.rs doc mentions Ctrl+Shift+D/E, which keys.rs does not bind; not documented.
- Not pushed.

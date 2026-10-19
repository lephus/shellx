# Task 5 report: TermCore over a PtyLink

Status: DONE. Commit 8189ce08ef on shellx/l6-windows (pushed). CI run 39167342800: success (model + app jobs; release build, `--smoke` PASS, `--version`).

Built
- src/term_core.rs: PtyLink trait (&self), TermCore (new/feed/send_text/send_chord/encode_chord/paste/bracketed_paste/resize/size/scroll_lines/title/frame/text_lines/selection_text/link_closed). Palette: set_default_colors(TERM_FG, TERM_BG, TERM_CURSOR) + set_default_palette with ANSI 0-15.
- src/local_pty.rs: LocalPty (PtyLink over cmux-pty), spawn, spawn_reader, default_shell; is_closed = child exited or write failed; child killed on drop. Unused ChildKiller import gone.
- src/fonts.rs + assets/fonts (JetBrains Mono 2.304 x4, Space Grotesk 2.0.0 static Bold, both OFL texts); app.rs registers fonts via add_fonts, grid font = "JetBrains Mono" with Cascadia/Consolas/Segoe fallbacks; paste goes through TermCore::paste (bracketed only with mode 2004).
- smoke.rs over TermCore + LocalPty; added palette (default bg == TERM_BG) and fonts (5, TrueType magic) checks. session.rs deleted.

Tests (Mac): `cargo test -p shellx-app --bin shellx-desktop` (no lib target exists, so `--lib` does not apply): 6 passed (palette_applied, paste_is_bracketed_only_when_mode_2004_set, send_text_is_one_utf8_write, resize_reaches_link_once, query_reply_goes_to_link, fonts). Tests passed on first run (written together with the code, not red-first).
Decision: Mac route (ghostty submodule already initialised; 1m build) rather than a CI test step, so no workflow change was needed.

Concerns
- On the Mac build, dead-code warnings for TERMINAL_FAMILY/DISPLAY_FAMILY/scroll_lines/title (used only under cfg(windows)); harmless.
- `--smoke` palette/fonts lines ran in CI; window UI itself (font rendering) is unverified visually.
- windows/Cargo.toml and Cargo.lock show as modified in the worktree (Task 6); I did not stage them.

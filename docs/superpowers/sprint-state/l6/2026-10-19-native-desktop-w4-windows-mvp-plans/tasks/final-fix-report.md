# Final fix wave (final whole-branch review)

Branch `shellx/l6-windows`, base `3cb8cc0b85`. One agent, no subagents. Requirements: `final-fix-findings.md`.

## Commits

| sha | subject |
|---|---|
| c5a0b72fc1 | fix(shellx-windows): final review fixes: no screen text in the window title, locked state writes, IME helper, ticket and backoff fixes, remote paste cap |
| c2087a601d | docs(shellx-windows): title privacy, corrected G3 paste/xxd criteria, remote detach and relay-hiccup limitations |
| RUNID_COMMIT | RUNID_SUBJECT |

## Mac test commands (all green on the final code)

```
export PATH=$HOME/.cargo/bin:<scratchpad>/zig-dl/zig-aarch64-macos-0.16.0:$PATH CARGO_INCREMENTAL=0; unset CMUX_GHOSTTY_SRC; cd windows
cargo test --locked -p shellx-model                     # 149 passed (was 146)
cargo test --locked -p shellx-remote                    # 30 passed, 2 ignored e2e (was 28)
cargo test --locked -p shellx-app --bin shellx-desktop  # 116 passed (was 102)
```
The app suite was run 6 more times (5 with the known flaky `invite_file_name_never_shared_after_sanitizing` skipped) and shellx-remote 3 more times: no failures. One full run hung once in the known Mac-only flake; the rerun passed.

## F1 window title privacy

- `shell_info.rs` (GPUI-free): `window_title(osc_title, cursor_line, screen_reader)`, `BASE_TITLE` (moved here), `TITLE_MAX_CHARS = 80`, `a11y_title_env`, `ScreenReaderProbe` (caches the answer, asks again at most once per second; a clock going backwards asks again). Default title: `<OSC title> - ShellX` or `ShellX`, never screen text; the text is stripped of control chars, trimmed and clipped to 80 chars (char-based). Screen-reader mode: the cursor line (cleaned the same way), else the OSC title.
- `os_info::screen_reader_running()`: `SystemParametersInfoW(SPI_GETSCREENREADER)`; windows-sys feature `Win32_UI_WindowsAndMessaging` added (no lockfile change).
- `ui/term_view.rs`: `screen_reader_title()` = `SHELLX_A11Y_TITLE=1` (read once) or the probe; the cursor line is collected only when `focused && screen_reader_title()`; the title comes from `window_title`.
- Tests: `default_title_never_carries_screen_text`, `screen_reader_title_carries_the_cursor_line`, `title_text_is_clipped_and_has_no_control_chars`, `a11y_title_env_needs_exactly_one`, `screen_reader_probe_asks_at_most_once_per_second`.
- RED: the tests did not compile (19 errors: `window_title`, `a11y_title_env`, `ScreenReaderProbe`, `TITLE_MAX_CHARS` missing). GREEN: 10/10 `shell_info` tests.
- Docs: README "Accessibility stopgap" rewritten (default title has no screen text; cursor line only in screen-reader mode, which Narrator itself turns on, or with `SHELLX_A11Y_TITLE=1`); checklist G1 Narrator item and G3 "Tiêu đề / Narrator" item updated to match.

## F2 checklist criteria

- G3 paste: the clipboard gets a real ESC through ``Set-Clipboard "a`e[201~b`nc"``. Pass: both lines arrive (`ab`, `c`), the marker is REMOVED, so `cat -v` shows no `^[[201~` or any ESC sequence, and nothing runs.
- G3 Telex: `cat | xxd` prints only at EOF, so the step now says "then Ctrl+D" (or use `od -An -tx1`).
- Release note (Minor 9) in README "Known limitations" and as a new G3 item: `Ctrl+Shift+W` on a remote pane only detaches (the shell keeps running on the Mac); every second "Mở" or remote split creates a new workspace on the Mac.
- Run id: see "CI" below (the checklist cites the run of the code head).

## F3 concurrent writers

- `links_store.rs`: one process-wide `static LINKS_LOCK` taken by `load`, `save` and the new `update(|links| ...)` (load-modify-save under one lock); temp names are `links.json.tmp<pid>-<seq>` (atomic counter). Both writers now use `update`: `PairingService` (save after pairing) and `Ctx::forget_invite` in `remote_session.rs`.
  - Test `concurrent_updates_through_separate_stores_lose_nothing`: 5 rounds of 16 threads, each with its own `LinksStore`, upsert different machines at a barrier: all 16 records present, the file parses, no temp file left. Plus `update_returns_the_saved_links`.
  - RED (naive `update` = load + save without the lock): FAILED, the threads panicked in `update(...).unwrap()` (rename of the shared temp name failed). GREEN after the lock and unique temp names.
- `shellx-remote/src/store.rs`: one process-wide `static STATE_LOCK` around `remember_slot`, `PlainStore::open` (read-or-create of the identity, so creation is single-flight) and `PlainStore::pin`; `write_private` uses `<name>.tmp<pid>-<seq>` and removes the temp file when the write or rename fails.
  - Tests `concurrent_opens_create_one_identity` (20 rounds, 4 threads open a fresh dir at a barrier: one identity, the same on reopen) and `concurrent_pins_and_slots_lose_nothing` (8 threads pin + remember a slot each: all present, no temp file left).
  - RED: both FAILED (threads panicked on the shared `*.tmp` rename / read of a half-replaced file; different identities). GREEN: 30/30.

## F4 text_edit test UB

- `wipe` now calls `zeroed_allocation(&mut String) -> Vec<u8>`: takes the allocation, `fill(0)`, `resize(cap, 0)`, `black_box`; returned with len == capacity, every byte initialized. `wipe` then clears it and puts it back (behaviour unchanged).
- The unsafe `backing()` helper (it read the String's whole capacity with `from_raw_parts`, including never-written spare bytes) and `has()` are gone; no `unsafe` remains in the module.
- Tests: `zeroed_allocation_zeroes_bytes_edited_away` (a truncated "hunter2": the returned Vec is the same allocation, len == capacity, all zero); `clear_zeroes_bytes_edited_away` rewritten safely: Backspace only shortens the live text (same pointer/capacity), `clear()` and `set_text()` keep the same allocation and empty it (they go through `zeroed_allocation`), mid-line delete case kept.
- RED: no Miri on this machine (stable toolchains only), so the UB is shown by reading the old helper: it read `capacity` bytes where only the typed bytes had been written. GREEN: 12/12 `text_edit` tests.

## F5 IME commit logic

- New GPUI-free `shellx-app/src/ime.rs`: trait `ImeTarget { write_text(&str) -> bool; scroll_to_bottom() }`, `committed_text` (drops control chars except Tab), `commit(...) -> Commit { Empty, Sent, Refused }` (ends the preedit, one write), `update_preedit(...) -> bool` (stores the preedit, scrolls, sends nothing; empty ends it).
- `term_view.rs`: `impl ImeTarget for Backend` (None: accepted, nothing written; Local: `TermCore::send_text`; Remote: `RemoteMirror::send_text`, false when not attached); `replace_text_in_range` / `replace_and_mark_text_in_range` call the helpers, clear the selection when `clears_selection()` / composing, and flash InputPaused on `Refused`. Same behaviour as before (an empty commit never writes and never flashes).
- Tests: `telex_preedit_then_one_commit_write` (7 preedit updates -> 0 writes, commit "tiếng Việt" -> exactly 1 write `74 69 e1 ba bf 6e 67 20 56 69 e1 bb 87 74`), `nfd_commit_is_sent_unnormalized` ("tie\u{302}\u{301}ng" byte for byte), `control_chars_are_dropped_but_tab_is_kept` ("\r", "\n", "\x03" dropped, "\t" kept), `refused_remote_writes_nothing_and_says_refused`, `empty_preedit_ends_the_composition_without_sending`.
- RED evidence (refactor, so by mutation): dropping Tab in the filter and writing during the preedit made `control_chars_are_dropped_but_tab_is_kept` and `telex_preedit_then_one_commit_write` FAIL; restored, 5/5 pass.

## F6 ticket cleanup

- Removed `Ctx::last_ticket` and the worker-exit `remove_file` (shellx-remote's `ticket.rs` already deletes each ticket after reading it; a replacement session for the same Mac mints to the same name). `Ctx::mint` is now just `mint_connect_ticket`.
- New test `a_finishing_session_leaves_a_newer_ticket_alone`: after attach, a "fresh ticket" is written at the shared path, the last pane closes, the session finishes: the file is still there with its content. RED: FAILED (`NotFound`, the old session deleted it). GREEN.
- `closing_the_last_pane_finishes_the_session` keeps its assertion, reworded: no stale ticket is left because the client consumed it.

## F7 connect-then-drop backoff

- `remote_state.rs`: `pub const STABLE_CONNECTED_MS = 10_000`; `ConnState` gets a private `connected_at_ms`; `Connected` records it instead of resetting `failures`; a private `settle(now_ms)` at the start of every `on(...)` resets `failures` once the link has been Connected for >= 10 s (and forgets the stamp when not Connected). Public API unchanged.
- Tests: `disconnect_backs_off_and_mints_new_ticket` now connects-then-drops (9.999 s) on every second attempt and still sees 1, 2, 4, 8, 16, 30, 30 s with a fresh ticket each; `backoff_resets_after_connect` drops after exactly 10 s -> 1 s; new `connect_then_drop_keeps_backing_off` (drops 0.5 s after connecting: 1, 2, 4, 8, 16, 30 s; 9.999 s still 30 s; a duplicate Connected does not restart the window; 10.001 s -> 1 s).
- RED: `connect_then_drop_keeps_backing_off` FAILED (`[1000, 1000, 1000, 1000, 1000, 1000]`), `disconnect_backs_off_and_mints_new_ticket` FAILED (attempt 2 instead of 3). GREEN: 149/149.

## Minor 1 remote paste cap

- `shellx-model/src/paste.rs`: `REMOTE_PASTE_MAX_BYTES = 8 MiB`, `remote_paste_fits(encoded_len)`; test `remote_paste_cap_is_8_mib_of_encoded_bytes` (bound, markers count, UTF-8 bytes count).
- `Str::PasteTooLarge` (vi "Nội dung dán quá lớn (tối đa 8 MB)", en "Paste too large (8 MB max)"), in `Str::ALL` (73) and `SHELL_STRINGS`.
- `TermCore::paste` split into `encode_paste` + `write_paste`; `RemoteMirror::paste(text) -> Paste { Sent, Refused, TooLarge }` (not attached -> Refused first; encoded size over the cap -> TooLarge, nothing written). `TermView::paste_clipboard` uses it for remote panes and flashes InputPaused or PasteTooLarge; local paste unchanged.
- Test `remote_paste_over_8_mib_is_refused_whole` (exactly 8 MiB sent in one write; +1 byte refused; bracketed markers push the 8 MiB text over; small bracketed paste still one write; detached -> Refused, nothing sent). RED: did not compile (no `paste` / `Paste`). GREEN.
- README remote section and a G3 item ("Dán quá lớn vào Mac") document it.

## Controller rulings

- Important 4: one sentence in README "Known limitations" and in the G3 disconnect item ("input typed during the first ~30 s of a relay hiccup may arrive late").
- Minor 3, 5, 6, 7, 8, 10, 11, 13: not touched.

## CI

RUNID_CI

## Concerns

- The cfg(windows) UI changes (term_view title/IME/paste wiring, `SystemParametersInfoW`) compile only on CI; the Narrator behaviour itself still needs the manual G1 check.
- F4 RED could not be shown with Miri (not installed); the fix removes every read of spare capacity instead.

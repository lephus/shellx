# Task 16 report: final-wave hygiene

Branch `shellx/l6-windows`, base `f2b2542213`. Implementer: one agent, no subagents.

## Commits

| sha | subject |
|---|---|
| 66471f1742 | test(shellx-core): fake API enforces the registered device key on pairing requests (L4 R17/R13) — cherry-pick of L5 55ebf4fff6 |
| 674493bcc2 | test(shellx-core): deterministic sealed-invite tamper tests — cherry-pick of L5 f030e222b3 |
| 5ffa60a802 | fix(shellx-app): selection overflow at the last column; Windows CI runs the app tests and watches the ghostty inputs (task 16 D.1, D.3, D.4) |
| d81964ab75 | fix(shellx-app): a heartbeat that says this machine is gone lists and registers it again (task 16 D.2) |
| 5ab51d5a41 | fix(shellx-app): password hygiene: wipe the password on close, masked Debug, keep it when the login is not accepted (task 16 A) |
| bd3ea95441 | fix(shellx-app): one modal rule for panels; stop respawning a shell that exits instantly (task 16 B, C) |

## CI

- Early push `5ffa60a802` (D.1, D.3, D.4 and the cherry-picks): run 39200456880. All four jobs passed, including the new `Test shellx-app` step on windows-2025. No tests failed only on Windows, so no tests needed changing.
- Round-0 head `bd3ea95441`: run 39202745851. model, app, remote-e2e and installer all passed. The `app` job covers the build and the shellx-model, shellx-remote and shellx-app tests plus the smoke run. The cfg(windows) UI code compiled there.
- Fix round 1 head: see "Fix round 1" at the end.

## A. Password hygiene

1. **Close wipes the password.** `TextEdit::clear()` now zeroes the content bytes in place (`wipe`: take the `String`, `fill(0)`, `black_box`, `clear`, keep the allocation) instead of dropping the buffer with the password in it. A masked `TextEdit::new(true)` reserves 128 bytes up front so a typed password normally never reallocates (a reallocation would leave the old copy in freed memory: "where practical"). `LoginPanel::close()` (Esc, Cancel, the sidebar hiding) clears the password field; the sign-in success path clears it too (it was already cleared on submit).
2. **Masked `Debug`.** `TextEdit` no longer derives `Debug`; the hand-written impl prints `content: *** (N bytes)` for a masked field (the plain field still prints its text). Test `text_edit::masked_debug_shows_no_typed_char` (typed text and an IME preedit, none of their chars in `{:?}`), `clear_wipes_and_keeps_the_buffer` (same capacity after clear, then reusable).
3. **Submit keeps the password when the flow would ignore it.** New `AccountFlow::accepts_login()` (`state != LoggingIn`), used by the `LoginSubmitted` handler itself, exposed as `AccountService::accepts_login()`. `LoginPanel::submit()` returns before touching the fields when it is false (register phase, or a login already running), so the password is cleared only when the login is accepted. Test `account::login_accepted_only_outside_logging_in` (register phase ignored and not accepted; signed out accepted; not accepted while the login runs; accepted again after a failure).
4. **Unhandled chords in a field / sidebar toggle.** Keys a field does not use bubble to `RootView::on_key_down`, which now swallows every key while a panel is open (B), so they never run a command or move focus to the terminal. `RootView::toggle_sidebar(window, cx)` (title bar button; Ctrl+Shift+B only without panels): hiding the sidebar closes the sign-in fields (wiping the password) and the machine picker that live in it, then refocuses through the modal rule (topmost panel, else the terminal), so focus never stays on an undrawn field.

## B. One modal rule

`shellx-model/src/modal.rs` (pure, tested): `Panels { forced_update, settings, pairing, login, picker }` -> `top()` (drawing order: overlay, settings, pairing, login, picker), `allows_app_commands()`, `esc_target()` (topmost, never the overlay), `must_close()` (settings under the overlay). Tests: `nothing_open_allows_commands_and_esc_goes_to_the_terminal`, `any_panel_swallows_commands_and_esc_closes_it`, `esc_closes_the_topmost_one_at_a_time`, `forced_update_overlay_cannot_be_closed_and_closes_settings`.

Wiring in `ui/root.rs`:
- `panels(cx)` builds the set (login/picker count only while the sidebar is visible).
- `focus_terminal` focuses the topmost panel (overlay focus, settings, pairing, the login field via new `LoginPanel::focus_target`, the root's own new `root_focus` for the picker), else the active pane. Every close path (`SettingsEvent::Closed`, `PairingEvent::Closed`, `LoginPanelEvent::Closed`, picker toggle) goes through it, so the terminal gets the keyboard only when the last panel closed.
- `run_command` returns unless `allows_app_commands()` (covers Ctrl+Shift+T/W/D/E, Ctrl+, , sidebar toggle, tab/pane focus from keys or from a pane's `TermEvent::Command`).
- `on_key_down`: overlay -> swallow all; any panel -> plain Esc closes `esc_target()` (`close_top_panel`), everything else swallowed.
- `focus_pane` (pane click) and `select_tab` (session row click) do nothing but give the keyboard back to the panel while one is open.
- The account observer closes the settings panel when `must_close()` says so (forced update arrived).
- Picker: new `PairingPanel::close_picker`; `toggle_machine_picker(window, cx)` refocuses (the root's `track_focus(root_focus)` receives Esc).

## C. Respawn storm guard

`shellx-model/src/tabs.rs`: `RespawnGuard` (`RESPAWN_LIMIT = 5`, `RESPAWN_WINDOW_MS = 10_000`). `on_close(&CloseOutcome, now_ms)`: a `Respawned` pane is *held* when 5 respawns already happened in the last 10 s; `retry(&mut Tabs, now)` forgets the history and replaces the held pane with a fresh one. Tests: `respawn_storm_stops_after_five_in_ten_seconds` (2 Hz exits: 5 respawns, the 6th held, closing the held pane stays held, other outcomes do not count, retry gives a fresh unheld pane, retry without a held pane is `NotFound`), `slow_exits_keep_respawning` (1 exit / 2.5 s never holds; a burst after a quiet 10 s starts from zero). The existing `closing_last_pane_of_last_tab_respawns` is unchanged.

Window: `RootView::close_pane` feeds the guard (time = ms since the view started); `reconcile` creates `TermView::new_held` (no shell) for a held local pane; it shows `Str::ShellExitsAtStart` ("Shell thoát ngay khi khởi động. Kiểm tra SHELLX_SHELL." / "The shell exits as soon as it starts. Check SHELLX_SHELL."), `Str::PressAnyKeyToRetry` and a primary "Thử lại" button; any key down or the button emits the new `TermEvent::Retry`, which runs `RespawnGuard::retry` and reconciles. Str table: 70 -> 72 keys, exact vi string tested.

## D. Smaller fixes

1. `selection.rs`: `spans` uses `e.col.saturating_add(1)`, `word_at` returns `col.saturating_add(1)` and clamps `usize` ends to `u16::MAX` (`u16::try_from(..).unwrap_or(u16::MAX)`), `cells_before_and_in` saturates too. Test `max_column_and_long_lines_never_overflow` — RED first: `attempt to add with overflow` at `selection.rs:78`.
2. Account / paths:
   - `register_requested` reset: already reset on logout (`reset_session`), on login success and on every list that has this machine (Task 10b). New: `AccountEvent::HeartbeatResult`; `run_account_action(CallHeartbeat)` now returns it (it returned `None` before). `machine_not_found` / `not_registered` resets `register_requested` and lists at once, so a removed machine registers again (also out of the stuck `Error(not_registered)` state). Other heartbeat errors change nothing. Tests: `account::heartbeat_machine_not_found_lists_and_registers_again` (RED first: the variant did not exist), `core_service::actions_map_to_calls_and_events` now asserts the event.
   - LOCALAPPDATA unset: already fixed in Task 10b (`paths::native_dir` errors, no Default-profile fallback; `this_pc_config` turns it into the visible `state_dir` error; tests `windows_layout_and_missing_local_app_data`, `config_set_once_before_the_first_call_and_retried_after_a_failure`). No change.
   - Stale `ListResult(not_logged_in)` during `LoggingIn`: already dropped while `login_in_flight` (Task 10b, test `list_result_ignored_while_login_in_flight`). No change.
   - `LogoutFailed`: Task 10b added the equivalent outcome: `LogoutResult(Err(e))` (not `not_logged_in`) keeps the session and sets `AccountFlow::notice()`, which the settings panel shows (`settings.rs` account section); test `logout_failure_stays_logged_in_with_notice`. Ruling: no separate `LogoutFailed` variant added (it would duplicate `notice`).
3. Workflow push `paths`: added `scripts/ci/init-submodule.sh`, `scripts/ghostty-zig-version.sh`, `ghostty`.
4. Workflow job `app`: new step `Test shellx-app` after `Test shellx-remote`, `timeout-minutes: 15`, `unset CMUX_GHOSTTY_SRC; cargo test --release --locked -p shellx-app --bin shellx-desktop --target "$TARGET"`.
5. Cherry-picked L5 `55ebf4fff6` and `f030e222b3` cleanly (only `shellx-core/fake-api/src/lib.rs`, `shellx-core/tests/pairing.rs`, `shellx-core/tests/seal.rs`). With the fake API enforcing R17, `cargo test -p shellx-app --bin shellx-desktop` and `-p shellx-model` stayed green with no change: L6 never sends a key (`register_machine` sends no `noise_public_key_b64`, asserted by `core_api` test; pairing goes through shellx-core with the device key).

## Mac verification

```
export PATH=$HOME/.cargo/bin:…zig-aarch64-macos-0.16.0:$PATH CARGO_INCREMENTAL=0; unset CMUX_GHOSTTY_SRC; cd windows
cargo test --locked -p shellx-model                  -> test result: ok. 144 passed; 0 failed
cargo test --locked -p shellx-app --bin shellx-desktop -> test result: ok. 102 passed; 0 failed (0.80 s)
```
Baseline after the cherry-picks (before any change): model 133 passed, app 102 passed (the first run hit the known `invite_file_name_never_shared_after_sanitizing` hang; rerun green). Tests were run through a 300 s guard script.

## Deviations / rulings

- D.2 items already done by Task 10b (LOCALAPPDATA, stale list, failed-logout notice) were verified and left; only the heartbeat reset was missing.
- A.1: zeroing is best effort without `unsafe`/a zeroize crate: in-place zero + `black_box`, and a 128-byte reservation so typing does not reallocate. Copies made by the OS/IME or by GPUI text shaping of the masked display (only bullets) are out of reach.
- B: Ctrl+, is swallowed while any panel is open (also while settings itself is open), as the brief lists it; the title bar buttons (settings, sidebar) still work by click. Sidebar "+"/"Mở" clicks are not blocked (only the overlay blocks them, as before); session-row clicks are (tab focus).
- B/A.4: chords are swallowed at RootView (one place) instead of in `TextField`.
- C: retry is "any key down" in the held pane or the button; app shortcuts typed there also retry.
- D.4 was pushed early (with D.1/D.3) so Windows-only test failures would show while A/B/C were written.

## Fix round 1 (review: 2 Important, 2 Minor)

Commit `0f7d20ca36`: fix(shellx-app): picker owns its focus (no root focus on inert clicks); wipe spare capacity and on drop; sign-in opens only under no higher panel (task 16 review 1).

**Important 1: root `track_focus` took focus on inert clicks.** I chose the first option: the machine picker gets its own focusable element, and `track_focus` is gone from the root. `RootView.root_focus` is renamed `picker_focus`. `sidebar::render` now takes `picker: Option<(&[PickerEntry], &FocusHandle)>`, and `machine_picker` calls `.track_focus(focus)` on the list. When the picker is the topmost panel, `focus_terminal` focuses that handle. Esc then bubbles from the picker to `RootView::on_key_down`, which closes the picker through `close_top_panel` as before.

Why this option: it removes the cause. No inert element tracks a focus handle any more, so GPUI's click-to-focus fallback (div.rs:2022-2036) has nothing to focus on the title bar, the bell, the banner or empty sidebar space. The two alternatives keep a focus handle on the whole window and add a second rule to repair it.

Invariant: focus is on the topmost panel, the picker or the active pane. `modal::Panels::top()` decides which, and `modal.rs` tests it. That GPUI no longer moves focus on an inert click depends on the element tree, which only builds on Windows, so CI is the only check: the app job compiles it. No one has clicked through it on Windows yet.

**Important 2: the wipe left edited-away bytes.** `wipe` now calls `resize(capacity, 0)` after `fill(0)`, so the whole allocation is zeroed without reallocating. Other changes:
- `impl Drop for TextEdit` wipes a masked buffer. `new()` lists every field, because struct-update syntax does not work on a type that implements Drop.
- `Clone` stays derived. A clone owns its own buffer, and its Drop wipes it.
- `set_text` wipes the old content before writing the new text.
- `splice` wipes its cleaned temporary copy of the typed or pasted text.

New test `clear_zeroes_bytes_edited_away`. A test-only `backing()` reads the whole allocation up to `capacity()` through `unsafe` (only in the test module) and covers three cases:
- type `hunter2`, press Backspace twice, then clear: the whole buffer is zero.
- delete in the middle of the text, then clear: the whole buffer is zero.
- `set_text` on the same allocation: the old text is gone.

The test failed first: the buffer after clear was `[0,0,0,0,0,114,50,0,…]`, which is "r2".

**Minor 4.** `LoginPanel::submit` checks that the email and password are not empty first. Only after that does it copy the password, once, and that copy moves straight into the login call.

**Minor 6.** New `Panels::may_open(panel)`: a panel may open only if nothing above it in the drawing order is open. New test `a_panel_opens_only_when_nothing_above_it_is_open`:
- the sign-in fields may open with nothing open, while they are already open, or above the picker.
- they may not open under pairing, settings or the overlay.
- settings may not open under the overlay.

`LoginPanel::open` no longer focuses a field. It emits the new `LoginPanelEvent::Opened`, and RootView handles it:
- if `may_open(Login)` is true, it refocuses, so the field gets the keyboard.
- otherwise it closes the sign-in fields again (which wipes the password) and the keyboard stays where it was.

Esc behaves as before.

**Deferred, not fixed (as instructed):**
- "Thử lại" in a held pane that is no longer the last pane (the user opened another tab) closes that pane's tab, because `RespawnGuard::retry` closes the held pane. It only respawns when the pane was the last one.
- The title-bar sidebar toggle still works under the forced-update overlay.
- A password longer than 128 bytes reallocates, which leaves a copy in freed memory.

**Commands and output (Mac):**
```
cargo test --locked -p shellx-model -k clear_zeroes   (before fix) -> FAILED, buffer shows 114,50 ("r2")
cargo test --locked -p shellx-model -k modal          (before may_open) -> E0599 no method `may_open`
cargo test --locked -p shellx-model                   -> ok. 146 passed; 0 failed
cargo test --locked -p shellx-app --bin shellx-desktop -> ok. 102 passed; 0 failed
```
The first shellx-app run hung on the known Mac-only flake `invite_file_name_never_shared_after_sanitizing`. The rerun passed.

CI: run 39205433045 (https://github.com/lephus/shellx/actions/runs/39205433045) for head `0f7d20ca36`. All four jobs passed: model, app (including Test shellx-app), remote-e2e and installer.

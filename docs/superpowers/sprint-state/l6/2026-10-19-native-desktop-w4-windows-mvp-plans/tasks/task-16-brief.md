# Task 16: final-wave hygiene (deferred Important/security-flavoured minors from Tasks 3, 8, 10a/b, 11, 12b)

Not a plan task: the controller adds it because the ledger parked these as "FIX IN FINAL WAVE" and fixing them before the whole-branch review keeps that review on the final code. Binding: `../constraints.md`. Scope is exactly the list below; nothing else.

## A. Password hygiene (Task 10b review, `ui/login.rs`, `ui/text_field.rs`, `shellx-model/src/text_edit.rs`, `shellx-model/src/account.rs`)
1. Closing the login panel (`close()`) must clear the typed password (zero the buffer: `clear` + overwrite the old capacity where practical) — today the masked field keeps it.
2. `TextEdit` (`#[derive(Debug)]`) must not print the content of a masked field: implement `Debug` by hand (or a masked newtype) so `{:?}` shows only the length/`***`. Test: masked edit's `format!("{:?}")` contains no typed character.
3. `submit()` must not clear the password when the account flow ignored `LoginSubmitted` (register phase / not accepting); clear it only when the submit was accepted. Test at the model/service level.
4. Unhandled key chords in a text field must not bubble to `RootView` and move focus to the terminal while a panel is open (see modal rule B). `toggle_sidebar` while a field is focused must leave a valid focus.

## B. One modal rule (Tasks 10b/11/12b minors)
`RootView`: while any panel is open (forced-update overlay, login, pairing, settings, machine picker) app commands (Ctrl+Shift+T/W/D/E, Ctrl+, sidebar toggle, tab/pane focus, terminal clicks) are swallowed; `Esc` closes the topmost closable panel (settings and pairing and login; not the forced-update overlay); the settings panel never stays open under the forced-update overlay (the overlay closes it). Focus returns to the terminal when the last panel closes. Keep it as a small pure helper in `shellx-model` with tests if the rule can be expressed without GPUI (open-panel set -> allowed commands / Esc target), and wire it in `ui/root.rs`.

## C. Respawn storm guard (Task 8)
When the last pane's shell exits instantly, `closing_last_pane_of_last_tab_respawns` currently respawns forever (~2 Hz). Add a guard in the model/workspace: N (use 5) respawns within 10 s stop the respawn and show a pane/tab message (`Str` key, Vietnamese "Shell thoát ngay khi khởi động. Kiểm tra SHELLX_SHELL." + en) with a "Thử lại" action or any key to retry. Test in `shellx-model`/`workspace.rs`.

## D. Smaller fixes
1. `shellx-model/src/selection.rs`: u16 `+1` overflow at `col == u16::MAX` -> `saturating_add`; `as u16` truncation on lines longer than 65535 -> clamp. Test.
2. Task 10a minors in `shellx-model/src/account.rs` + `core_service.rs`/`paths.rs`: `register_requested` never resets (a remotely revoked/removed machine must be able to register again after a fresh login: reset on logout and on a `machine_not_found`/not-registered heartbeat error); LOCALAPPDATA unset must NOT fall back to writing under a Default profile (fail with a visible error instead — never write secrets next to the cwd or into another user's profile); stale `ListResult(not_logged_in)` during `LoggingIn` must not cancel the login; add a `LogoutFailed` outcome so a failed logout is shown, not swallowed.
3. `.github/workflows/shellx-windows.yml`: add `scripts/ci/init-submodule.sh`, `scripts/ghostty-zig-version.sh` and `ghostty` to the push `paths` filter.
4. `.github/workflows/shellx-windows.yml` job `app`: after `Test shellx-remote` add a step `Test shellx-app` running `cargo test --release --locked -p shellx-app --bin shellx-desktop --target "$TARGET"` (with `unset CMUX_GHOSTTY_SRC`), so the ~90 app unit tests (remote session/link, pairing, links store, core service, TermCore) run on Windows too, not only on the Mac. If a test fails on Windows only because of a test-environment assumption (paths, `/tmp`, line endings, env vars), fix the test (not the product code) and say so; if it reveals a product bug, fix the bug and add a regression test.
5. Merge the two newest shellx-core test commits of L5 into the lane (they touch only `shellx-core/`): `git cherry-pick 55ebf4fff6 f030e222b3` (if the cherry-pick conflicts or touches other paths, stop and report). The fake API now enforces R17 (pairing request key must equal the machine's registered key): run `cargo test --locked -p shellx-app --bin shellx-desktop` and `cargo test --locked -p shellx-model` and fix any L6 test or code that breaks (L6 must never send its own key: `machines.register` without `noise_public_key_b64`, `pair.request` inside shellx-core uses the device key).

## Tests / CI
Mac: `cargo test --locked -p shellx-model` and `-p shellx-app --bin shellx-desktop` green. UI/Windows-only wiring (A.4, B, C message) is verified by CI (push, `ci_wait.py`, all jobs green; the new `Test shellx-app` step must be green too).

## Commit
One commit per lettered group is fine, e.g. `fix(shellx-app): password hygiene …`, `fix(shellx-app): one modal rule …`, `fix(shellx-app): stop respawning a shell that exits instantly`, `fix(shellx-app): final-wave minors (selection overflow, account reset, workflow)`.

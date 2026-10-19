# Task 13b report: open a Mac terminal from the sidebar (UI wiring)

**Status: DONE.** Final head `f2b2542213` (fix round 1) is green on all four CI jobs (run `39198318679`); the first head `e29255d212` was green too (run `39195202807`).

Commit `e29255d212` on `shellx/l6-windows`:
`feat(shellx-app): open a Mac terminal from the sidebar with status overlay, split and close (13b)`.
Pushed with `git push origin shellx/l6-windows` (the push also carried `d05c44e7a8` (CI matcher) and `5dc5a09c3a` (13a review 2)).

Files (only these were staged; committed with `git commit -- <paths>`):
- **new:** `windows/shellx-app/src/remote_tabs.rs` (GPUI-free glue, tests, smoke driver)
- **UI (cfg(windows), CI-compiled only):** `windows/shellx-app/src/ui/{term_view.rs, root.rs, sidebar.rs, pairing.rs}`
- **shared, small:** `windows/shellx-app/src/{main.rs (mod line), smoke.rs (one step), shell_info.rs (SHELL_STRINGS + remote title)}`
- **model:** `windows/shellx-model/src/{strings.rs, tabs.rs}`

`remote_session.rs` / `remote_link.rs` were NOT edited (no blocking bug found).

## What I built

### `remote_tabs.rs` (GPUI-free, tested on the Mac)
- `SessionApi` trait (implemented for `RemoteSession`, faked in tests) so the window logic is testable.
- `RemoteTabs<S>` — the window owns one:
  - **one session per `machine_id`**, shared by all of that Mac's panes; reused while `!status().finished`, otherwise a new one is started (also when it finishes between the check and `open_pane`: one retry on a fresh session). A finished session that panes still use stays theirs (their `close_pane` goes to it).
  - **`plan(pane, Want)` + `open(pane, machine_id, terminal_id, record, online, sink, start)`**: the Want is the plan (Open / split), else `want_for_target(terminal_id)` (`""` → `First`, id → `Terminal(id)`). A new session gets `set_machine_online(online)` *before* the pane, so an offline Mac shows "ngoại tuyến" at once.
  - **model `PaneId` → (session, session pane id)**: `pane_closed(pane)` calls `session.close_pane(id)`. ~~A session no pane uses any more is dropped from the map (Drop → `close()`), so the next Open starts afresh (no revive race).~~ **Corrected in fix round 1:** that drop closed a session whose invitation enrollment was still waiting for approval, so a second "Mở" enrolled the same invitation again. The session now stays in the map until it has finished (see "Fix round 1").
  - **`machines_updated(&[MachineInfo])`**: `set_machine_online` per session, only on change.
  - **`status_changed(pane) -> bool`**: true once per session that started from a not-enrolled link (or one still naming its invite) when its status reaches `Connected` (enrollment saved: `enrolled = true`, invite removed) or `NeedsPairing` (expired invite dropped). The window then sends `Cmd::LoadLinks` (task-12b).
  - **`close_all()`**: `session.close()` on every session (map and panes), clears everything.
- `open_want(tabs, machine)`: `First` when the Mac has no pane yet, else `New` (a second "Mở" creates a new shell on the Mac, like "+" for a local tab, instead of a useless second mirror of the same terminal).
- `split_target(tabs, focused)`: remote → `(Remote{machine, ""}, Some(Want::New))` (C12), local → `(Local, None)`.
- `coalesce(events)`: merges runs of `Output` into one feed (the UI task drains in batches); order otherwise kept.
- `AccountWatch::update(&AccountState) -> bool`: true on sign-out after a sign-in, or a sign-in as another machine.
- `overlay(&SessionStatus, lang) -> Option<Overlay{title: Str, tone: Running|Muted|Error, details}>` (rules below) and `failed_overlay(&OpenError)`.
- `app_session_config(record, core)` / `start_app_session`: exactly the brief's values — `invite_dir = paths::core_dir()?.join("tickets")`, `links: Some(LinksStore::default_location()?)`, `state_dir = paths::remote_dir()?`, `device_name = os_info::device_name()`, `connector = Arc::new(RelayConnector)`, `time_scale: 1`, the shared core. No relay URL anywhere (R17: route/slot come from the link, tickets from `tickets.mint`).
- `smoke()`: the window's remote-tab path with the real `RemoteSession` against 13a's fake Mac (used by `--smoke` and a Mac test).

### UI
- **`ui/term_view.rs`**: `TermView` now holds `Backend::{None, Local{core, link}, Remote(Box<Remote{mirror, session, status, title}>)}`.
  - `Backend::core()` returns the local core or `mirror.core()` **per use** (doc says never keep it); every former `self.session` use (prepaint/resize, frame, IME cell, copy, paste, scroll, follow-viewport, scroll-to-bottom on compose) goes through it, so local and remote share rendering, selection, copy, bracketed paste (`TermCore::paste` → `encode_paste`), IME placement and mouse selection unchanged. `follow_viewport` re-reads the core after the update (a reset replaces it).
  - `new_remote(opened, rx, window, cx)`: one UI task per pane drains the pane's `async_channel` (sink = `tx.send_blocking(e).is_ok()` from the session's threads), coalesces output, and applies each event: `Reset` → selection dropped; `Fed` → selection follows the viewport; `Status` → re-read `session.status()` (the UI only reads snapshots); `Retargeted(id)` → `TermEvent::Retargeted`; `Ended` → `TermEvent::Exited` (the normal close path). The mirror's OSC title is cached after each update for the sidebar/session bar.
  - **Input gating**: IME/typed commit → `RemoteMirror::send_text` (ONE write of the committed UTF-8; preedit never leaves); refused (not attached) → dropped + flash `Str::InputPaused`. Chords go through `core.send_chord` (link drops them when not attached) and flash when refused. Paste is refused up front with the flash.
  - **Status flash** (none existed): a small RAISE/BORDER line at the bottom of the pane for 2.5 s (`flash_seq` guards early clears). Also used once for a new `save_error` (the pill is gone while connected).
  - **Pill**: absolute layer, centered card RAISE fill, 1 px BORDER, radius 10, dot + title (+ MUTED small detail lines, centered, ≤ 440 px). No gradient, glow or shadow. A layer without listeners, so mouse selection underneath still works.
  - The a11y/window-title code in `TermElement::prepaint` is shared, so a focused remote pane writes the title like a local one (item 7).
- **`ui/root.rs`**: owns `remotes: RemoteTabs<RemoteSession>` and `account_watch`.
  - `reconcile` opens `PaneTarget::Remote` panes through `remotes.open` (links from the pairing panel cache, online flag from the machine list, the shared `Services.core`); every pane the model drops → `remotes.pane_closed` (→ `session.close_pane`).
  - `open_remote(machine_id)`: new tab `Remote{machine, ""}` + `plan(open_want)`; blocked during a forced update.
  - Split commands → `split(axis)` with `split_target` (remote → `Want::New` on the same session; local stays local). Ctrl+Shift+T (`new_tab`) stays local.
  - `TermEvent::Retargeted` → `Tabs::retarget`; `TermEvent::RemoteStatus` → `remotes.status_changed` → `pairing.reload_links()` (`Cmd::LoadLinks`).
  - Account observer → `account_changed`: `machines_updated(account.machines())` (the 15 s list) and, on `AccountWatch` true, `close_all_remote`: `remotes.close_all()` then `tabs.close_pane` for every `tabs.remote_panes()` and `reconcile` (the last pane respawns a local tab).
  - Titles: a Mac tab is "<OSC title or Mac name>" and the session bar says "› <Mac name>".
  - Sidebar rows carry their machine: a Mac's tabs are listed under its group (still listed while it is offline, so they stay reachable); a Mac not in the list → under this PC.
- **`ui/sidebar.rs`**: `RowAction::Open` → primary "Mở" button → `RootView::open_remote`; rows grouped by `SessionRow.machine_id`.
- **`ui/pairing.rs`**: "Mở" after approval is enabled once the link is saved (disabled otherwise; the save-error line explains); click → panel closes, `PairingEvent::Open(machine_id)` → `RootView::open_remote`. New `links()` / `reload_links()`.

### Model
- `strings.rs`: `FingerprintMismatch` ("Khóa của máy không khớp, không kết nối" / "The machine's key does not match; not connecting"), `NeedsPairing` ("Cần xin quyền truy cập lại" / "Request access again"), `RemoteAttachFailed` ("Không mở được phiên trên máy kia, đang thử lại…" / "Could not open the session on the other machine, retrying…"). Count test 67 → 70; new test `remote_pane_strings`.
- `tabs.rs`: `Tabs::retarget(pane, terminal_id)` and `Tabs::remote_panes()`; tests `retarget_updates_only_remote_panes`, `closing_every_remote_pane_leaves_a_local_tab`.
- `shell_info.rs`: SHELL_STRINGS + Connecting, Reconnecting, RemoteEnded, InputPaused, FingerprintMismatch, NeedsPairing, RemoteAttachFailed (51 → 58); `remote_session_title`.

## Brief items → coverage
1. Sidebar Open / pairing "Mở" → remote tab; one session per machine (reuse/new); `PaneTarget::Remote`; `Retargeted` updates the target; `Ended` closes only that pane via the existing close/respawn path (Review Focus 4: `Tabs::close_pane` → `Respawned` for the last pane); closing a pane → `session.close_pane(id)`. Tests: `one_session_per_mac_shared_by_its_panes`, `a_finished_session_is_replaced_and_its_panes_keep_theirs`, `closing_panes_detaches_and_the_last_one_drops_the_session`, smoke steps, `closing_every_remote_pane_leaves_a_local_tab`.
2. Remote TermView over `RemoteMirror`, core per use, shared rendering/selection/copy/paste/IME; gated input; refused commits dropped + `InputPaused` flash; Telex commit = ONE write (smoke: "tiếng Việt" = 1 write through the split's mirror; 13a's `remote_commit_sends_composed_utf8` covers the link).
3. Pill while `phase != Connected` or an error is set; RAISE/BORDER, no glow; Connecting/Reconnecting (RUNNING), Offline (MUTED), RemoteEnded (MUTED), FingerprintMismatch/NeedsPairing (ERROR, new Str keys), attach_error (`RemoteAttachFailed`, RUNNING, error as detail), save_error as a detail line. UI reads only `status()` snapshots; one UI task per pane over `async_channel`. Test `pill_per_status`.
4. Split of a remote pane → `Want::New` on the same session (smoke: same `Arc`, `creates == 1`, terminal "2"); local split stays local; Ctrl+Shift+T stays local. Test `open_and_split_wants`.
5. Machine list → `set_machine_online` on change (`online_flag_is_sent_at_start_and_on_change_only`); SessionConfig values verbatim; the shared `Services.core` (`ConfiguredCore` over `shellx_core::Core`) is `Send + Sync` and not serialized behind the account worker (the worker only holds an `Arc` clone; `Core::call` locks only for config/store lookup and login/logout), so no adapter was needed. Links reload after enrollment: `links_reload_once_after_enrollment_or_a_dropped_invitation` + smoke.
6. Sign-out / account change: `AccountWatch` + `close_all` + remote panes closed through the model (`account_watch_closes_on_sign_out_or_another_account`, `close_all_closes_every_session`, smoke's last step).
7. Window title: shared `TermElement` prepaint (focused pane only).
8. No telemetry, no relay URL, no gradients/glows/shadows, Vietnamese default strings.

## Rulings / deviations
- **Second "Mở" on the same Mac** opens a new tab with a NEW terminal on the Mac (`Want::New`); only the first Open shows the Mac's first terminal. A second mirror of the same terminal seemed useless; the existing tab stays selectable from the sidebar row under the Mac.
- **Pill visibility**: shown while not connected or when `error` is set, or (fix round 1) when `attach_error` is set and THIS pane is not attached. `save_error` alone does not raise the pill (it would cover a working terminal for the whole session); it is a detail line whenever the pill shows, and it is flashed once when it first appears.
- **Detail lines**: `status.reason` is shown under "đang kết nối lại…" (why the last attempt failed); not asked for, but otherwise a stuck reconnect gives the user nothing to go on. Details are clipped to 200 chars.
- **Third new Str key** `RemoteAttachFailed` (the brief named two "e.g." keys; an attach error while connected needed a title).
- Sidebar rows now sit under their machine (a Mac's tabs under the Mac). Before, every tab was listed under this PC with the "PowerShell" fallback title, which is wrong for a Mac tab.

## Tests and evidence (Mac)
Environment: `export PATH=$HOME/.cargo/bin:<zig 0.16.0>:$PATH CARGO_INCREMENTAL=0; unset CMUX_GHOSTTY_SRC`, in `windows/`.
- `cargo test --locked -p shellx-model` → `test result: ok. 133 passed; 0 failed`.
- `cargo test --locked -p shellx-app --bin shellx-desktop` → `test result: ok. 98 passed; 0 failed` (12 of them are the new `remote_tabs::tests::*`, incl. `smoke_remote_tabs`; `shell_info`'s title test gained the remote assertions). Repeated full runs: my tests never failed or hung (see Concerns 2-3 for two pre-existing flakes); `remote_tabs` alone: 40/40 runs green.
- `./target/debug/shellx-desktop --smoke-ui-assets` → `smoke-ui-assets: 21 icons, 58 strings x 2 languages` / `PASS`.
- `./target/debug/shellx-desktop --smoke` (Mac; the later PowerShell step fails as before) printed
  `smoke-remote-tabs: open -> terminal 1, links reloaded once; split -> terminal 2 on the same session, 1 write; its end closed only that pane; sign-out closed the session`.
- `cargo clippy --locked -p shellx-model -p shellx-app --all-targets`: no findings in my files (pre-existing ones in term_core.rs, fonts.rs, selection.rs). rustfmt (edition 2024) clean on every file I touched (an unrelated reformat rustfmt made to `smoke.rs::pairing_flow` was not kept).

## CI
- Run `39195202807` (head `e29255d212`, contains `d05c44e7a8` and `5dc5a09c3a`): **all green** — app (x86_64-pc-windows-msvc) success (the GPUI UI compiled on the first push), remote-e2e success, model success, installer success. (The GitHub API budget was exhausted for a while; `ci_wait.py` retried until it could read the verdict.)
- Fix-round head: see "Fix round 1".

## Needs user (G3, live Windows → Mac; GPUI runs only there)
Prerequisites: relay v2 deployed, the L5 Mac bridge running ShellX, the user signed in on both, the Mac paired (Task 12 flow).
1. **Open from the pairing panel**: after "Đã được chấp thuận", "Mở" is enabled; click → the panel closes, a new tab shows the pill "đang kết nối…" (yellow dot), then the Mac's terminal. `core\tickets\invite-<id>.uri` is gone and `remote\links.json` has `"enrolled": true` and no `invite_path`; the sidebar still shows the Mac as granted (cached links reloaded).
2. **Open from the sidebar**: the Mac row shows "Mở"; the tab is listed under the Mac's group, titled with the Mac shell's title (or the Mac's name); the session bar reads "<title> › <Mac name>". A second "Mở" opens another tab with a new shell on the Mac (it also appears in the Mac's window, C12).
3. **Telex** (Unikey or Windows Vietnamese Telex): on the Mac run `cat | xxd`, type `tiếng Việt` + Enter in the remote pane: the bytes are exactly `74 69 e1 ba bf 6e 67 20 56 69 e1 bb 87 74 0a` (no backspaces / raw keys). The candidate window opens under the remote cursor.
4. **Paste / copy / selection**: drag-select and copy with Ctrl+Shift+C; at the Mac's zsh prompt (bracketed paste on) paste a two-line text that contains `ESC[201~` with Ctrl+Shift+V: it is inserted as text and nothing runs until Enter.
5. **Resize**: resize the window; `stty size` on the Mac follows.
6. **Split**: Alt+Shift+= / Alt+Shift+- in the remote pane → a new remote pane with a new shell on the Mac; the same keys in a local pane give a local PowerShell; Ctrl+Shift+T is always local.
7. **Disconnect**: Wi-Fi off on the Mac (or quit ShellX there) → pill "đang kết nối lại…" with the reason underneath (or "ngoại tuyến" after the next 15 s list says offline); typing, Enter or paste flash "Mất kết nối, tạm ngừng nhập" at the bottom and nothing arrives later; back online → reconnects within ~30 s, pill gone, typing works. The UI stays responsive throughout.
8. **End**: `exit` in one remote pane → only that pane closes (sibling takes the space); `exit` in the last pane of the last tab → a fresh local PowerShell tab, the app never quits (also watch 13a's deferred #3: a reattach instead of a close).
9. **Sign out** (Settings) → every remote tab closes, a local tab remains; signing in again and "Mở" reconnects.
10. **Window title / Narrator**: focus a remote pane, Insert+T reads the remote cursor line.
11. Visual check of the pill and the flash at 100/150 % scale (centered, RAISE/BORDER, no glow).

## Concerns
1. **UI unverified at runtime** (GPUI compiles only on CI): pill layering over the grid, focus after "Mở" from the pairing panel, and the flash position are visual checks for G3.
2. **Pre-existing flaky hang, not mine** — `pairing_service::tests::invite_file_name_never_shared_after_sanitizing` (Task 12b) hangs in `HashSet::from_iter` (hashbrown probe loop, sampled stack) in ~12/100 runs **even alone** (`--exact`), and ~3/20 full runs with my tests skipped. CI does not run `shellx-app` bin tests, so CI is unaffected; whoever owns `pairing_service.rs` should look (it looks like a std/hashbrown or toolchain issue on aarch64-macOS 1.95 rather than test logic).
3. **Pre-existing flaky 13a test** — `remote_session::tests::resize_reaches_the_view_and_the_next_attach` failed 2 of ~35 full runs (timing: events list ended with `Status` only). It is in `remote_session.rs` (the parallel implementer's file).
4. `RemoteSession::status()` is read on each `Status` event per pane; cheap (mutex clone).
5. Tabs of an offline Mac stay listed under its dimmed group (U14 says offline machines show no sessions; these are open tabs of this window, so they stay reachable).

## Fix round 1 (controller review: Important 1, Minor 2)

Commit `f2b2542213` `fix(shellx-app): never enroll one invitation twice when a tab closes during approval; attach-error pill only on the failing pane (13b review)`, files `windows/shellx-app/src/{remote_session.rs, remote_tabs.rs, ui/term_view.rs}` (committed with `git commit -- <paths>`; remote_session.rs edited for this fix only, as allowed; its public API is unchanged).

### Important 1: one invitation enrolled twice (tab closed during the approval wait, then "Mở" again)
- **13b (`remote_tabs.rs`)**: `pane_closed` no longer removes the Mac's session from the map (removing it dropped the last `Arc` together with the view's, and `Drop` called `close()`). The session stays until `status().finished`; `open` reuses any session that has not finished. New `prune()` (called from `pane_closed` and `machines_updated`, i.e. at least every 15 s) lets go of finished sessions no pane uses. When a session ends: by itself after its last pane (13a: immediately when no enrollment runs, otherwise when the enrollment result lands with no pane), by `close_all` (sign-out), or by `Drop` when RootView goes (app exit).
- **13a (`remote_session.rs`)**: new `Worker::park`. When the last pane closes while `enrolling.is_some()`, the worker does not exit: `status().finished` stays false (`finished` is now `Idle && enrolling.is_none()` or `Final`), so `open_pane` still sends to it. While parked: an `OpenPane` revives the session (`revive` + handle, as in the queued-revive path; its connect is deferred and takes the enrollment's host in `linked`); the enrollment result ends `enrolling` (its client is dropped when no pane wants it) and the worker finishes Idle as before (late `OpenPane`s still revive through the existing drain); `Close` (sign-out, Drop) makes the stop final at once. The `open_pane` / `finished` lock protocol is unchanged.

### Minor 2: attach-error pill over working panes
- **13b**: `overlay(status, attached, lang)`; the Connected + `attach_error` arm is raised only when THIS pane is not attached. `TermView` passes `remote.mirror.link().accepts_input()`.
- **13a**: `ClosePane` clears `attach_error` (and publishes) when the remaining panes have no attach failures.

### Tests (TDD)
New / changed tests were written first and run against the old code with a stub `overlay(.., _attached, ..)` so they compile.
RED — `cargo test --locked -p shellx-app --bin shellx-desktop -- remote_`:
```
test remote_session::tests::an_enrollment_ending_without_a_pane_finishes_idle_and_close_ends_it_early ... FAILED
test remote_tabs::tests::closing_panes_detaches_and_keeps_the_session_until_it_finishes ... FAILED
test remote_tabs::tests::pill_per_status ... FAILED
test remote_session::tests::last_pane_closing_during_an_enrollment_keeps_the_session_for_the_next_pane ... FAILED
  the session finished while its enrollment waits for approval
test remote_tabs::tests::closing_the_tab_during_an_approval_never_enrolls_twice ... FAILED
  assertion `left == right` failed: a second enrollment started
test remote_session::tests::closing_the_failing_pane_clears_the_attach_error ... FAILED
  timed out waiting for attach error cleared
test result: FAILED. 41 passed; 6 failed; 0 ignored; 0 measured; 55 filtered out; finished in 10.01s
```
GREEN after the fix: `test result: ok. 47 passed; 0 failed; ... 55 filtered out; finished in 0.78s`.

What they cover:
- `remote_tabs::tests::closing_the_tab_during_an_approval_never_enrolls_twice` — real `RemoteSession` + 13a fake connector, blocked invitation connect; the only pane closed (and its view's `Arc` dropped), "Mở" again from the cached not-enrolled record → 1 session started, exactly ONE (invitation) connect, one approval, 1 host, the new pane attaches, the invitation deleted, links.json enrolled.
- `remote_session::tests::last_pane_closing_during_an_enrollment_keeps_the_session_for_the_next_pane` — after the last pane closes during the approval wait the session is not finished; a later `open_pane` is accepted and attaches to the enrolled host; 1 connect, 1 host, invite deleted, Connected.
- `remote_session::tests::an_enrollment_ending_without_a_pane_finishes_idle_and_close_ends_it_early` — approval with no pane waiting: the result lands (invite deleted, link enrolled), then the session finishes and refuses panes; and `close()` during the parked wait finishes it at once.
- `remote_session::tests::closing_the_failing_pane_clears_the_attach_error` — one attached pane, a second one failing to attach (attach error set); closing the failing pane clears `attach_error`, the sibling stays attached, the session stays.
- `remote_tabs::tests::closing_panes_detaches_and_keeps_the_session_until_it_finishes` (replaces `..._the_last_one_drops_the_session`) — the last pane closed: session kept and not closed, the next Open reuses it; once finished, `machines_updated` prunes it and the next Open starts a new one.
- `remote_tabs::tests::pill_per_status` — Connected + attach error: pill on a non-attached pane, none on an attached one.
- The existing 13a enrollment tests (`reviving_during_an_enrollment_never_enrolls_twice`, `an_enrollment_ending_while_the_session_stops_is_not_lost`, `offline_during_approval_never_enrolls_twice`, `closing_the_last_pane_finishes_the_session`, `closing_the_last_pane_and_opening_another_revives_the_session`) pass unchanged.

### Commands and output (Mac, in `windows/`, `CARGO_INCREMENTAL=0`, zig on PATH)
- remote tests 10x in a row (`target/debug/deps/shellx_desktop-* -q remote_`): 10/10 `test result: ok. 47 passed; 0 failed`.
- `cargo test --locked -p shellx-model` → `ok. 133 passed; 0 failed`.
- `cargo test --locked -p shellx-app --bin shellx-desktop`: full suite `ok. 102 passed; 0 failed` (and 4 more full runs `ok. 101 passed ... 1 filtered out` skipping only the known Mac-only flaky `pairing_service::tests::invite_file_name_never_shared_after_sanitizing`, which hung one other full run, as reported before).
- `--smoke` (Mac): `smoke-remote: ...` and `smoke-remote-tabs: open -> terminal 1, links reloaded once; split -> terminal 2 on the same session, 1 write; its end closed only that pane; sign-out closed the session` unchanged.
- rustfmt (edition 2024) `--check` clean on the 3 files; clippy (`-p shellx-app --all-targets`): no findings in my files.

### CI
- Run `39198318679` (head `f2b2542213`): **all green** — app (x86_64-pc-windows-msvc) success, remote-e2e success, model success, installer success.

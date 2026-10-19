# Task 13a report: remote Mac terminal session (non-UI)

**Status: DONE.** Commit `0b2f0ea513` is pushed to `shellx/l6-windows`. CI: see "Tests and CI evidence" below.

The commit message is `feat(shellx-app): view and type into a Mac terminal over relay v2 with reconnect and input gating (13a: RemoteLink, RemoteSession, non-UI)`.

Files:
- **new:** `windows/shellx-app/src/remote_link.rs`, `windows/shellx-app/src/remote_session.rs`
- **mod lines:** `windows/shellx-app/src/main.rs`
- **`smoke.rs`:** `remote_session()` plus one call in `run()`
- **`term_core.rs`:** `new_mirror`, explained below
- **`shellx-remote/src/lib.rs`:** `Attachment::into_parts`, explained below
- **deps:** `shellx-app/Cargo.toml` gains a `shellx-remote` path dep, and `Cargo.lock` gains one line. These are workspace crates only; no external deps were added.

I did not touch `src/ui/*`.

## Design

The data flows in three hops:
1. **Network to worker.** Job threads report each mint, connect, attach and end check as a message to the `RemoteSession` worker thread.
2. **Pump to UI.** One pump thread per view sends `PaneEvent`s to the pane's sink.
3. **UI thread.** It calls `RemoteMirror::apply(event)` and reads `RemoteSession::status()`.

The UI thread and the worker never block on the network. Every blocking `RemoteClient` call (connect up to 300 s, list/create 15 s, attach 20 s) and every `tickets.mint` runs on a short-lived job thread.

### `remote_link.rs`

- **`RemoteLink` (implements `PtyLink`)** is a stable link per pane that survives reconnects. Its inner view is a `ViewInput`, swapped in by `install(view, attached_size)` and removed by `clear_view()`.
  - `write` makes ONE `view.write(bytes)` call. With no view (connecting, reconnecting, offline, mismatch, ended) the input is dropped, never queued.
  - `resize` records the pane grid, which the next attach uses. It sends to the Mac only when the grid changed. This dedup also stops a resize loop if the Mac keeps a different grid.
  - `is_closed()` is true only after the remote terminal really ended.
  - `accepts_input()` is true when a view is attached and the terminal has not ended.
- **`ViewInput` trait.** It is implemented for `shellx_remote::AttachmentInput` and for the fakes.
- **`PaneEvent`:** `Reset{cols,rows}`, `Snapshot`, `Output`, `Status`, `Retargeted{terminal_id}`, `Ended`. `PaneSink = Arc<dyn Fn(PaneEvent) -> bool + Send + Sync>`.
- **`pump()`** drains the attachment receiver promptly; the channel is unbounded (Task 6 carry-over). It drops events of a replaced view, using view generations.
- **`RemoteMirror`** is UI-thread state that owns the mirror `TermCore`.
  - `apply`: a `Reset` replaces the `TermCore` at the Mac's grid. libghostty has no reset, so a fresh core is built, as the brief allows. Then `Snapshot` and `Output` are fed in order.
  - `send_text` returns `false` when input is refused. 13b then flashes `Str::InputPaused`, and the text is dropped.

### `term_core.rs` addition: `TermCore::new_mirror`

This is a small, additive change to another task's file. It builds the same core without libghostty's `on_pty_write` callback.

The reason: cmux-tui's terminal host already answers DA, DSR and Kitty queries. `cmux-tui-core/src/surface.rs:2161-2166` says a mirror "answering here would inject one duplicate reply … into the child input". The test `mirror_never_answers_queries` covers this.

`TermCore::new` is unchanged.

### `shellx-remote` addition: `Attachment::into_parts() -> (AttachmentInput, Receiver<AttachEvent>)`

`std::sync::mpsc::Receiver` is not `Sync`. So the pane link (`write`/`resize`) and the pump thread (`recv`) cannot share one `Attachment`.

The commands, surface and alive flag moved into a public `AttachmentInput` that is `Send + Sync`. It carries the old `Drop`: it marks the view dead and sends `Close`. The existing `Attachment::{events, write, resize, detach}` API and its behaviour are unchanged.

New unit test: `attachment_parts_split_send_sync_input_from_the_receiver`.

### `remote_session.rs`

`RemoteSession` covers one Mac (one client) shared by all its panes. A worker thread owns the `ConnState` and runs its actions:

- **Tickets.**
  - `MintTicket{attempt}`: `mint_connect_ticket(core, machine_id, ticket_file_name(id))`.
  - The file name is `connect-<machine_id>.ticket`, sanitized to core's bare-name rule (`[a-z0-9._-]`, ≤ 64 bytes), the same way as `invite_file_name`.
  - `Connect{attempt, ticket_path}`: `RemoteClient::connect`. The ticket callback returns the minted ticket on its first call and mints a fresh one on every later call (relay reconnects inside the client).
- **Invite and enrollment.**
  - The invite is used only if `!(link.enrolled || RemoteClient::is_enrolled(state_dir, link.daemon_fingerprint))`. The second check is a fallback for the case where saving `links.json` failed after an earlier enrollment.
  - The connect config also takes `state_dir` (`paths::remote_dir()` in the app), `device_name`, and `relay_route`/`relay_slot` from the link. Nothing is hard-coded, which satisfies R17.
- **Carry-over: fingerprint check.**
  - After connect, `client.daemon_fingerprint()` is compared with `link.daemon_fingerprint` (from `pair.poll`; both are base64url SHA-256[..16]).
  - On a mismatch the client is dropped, nothing is attached, and the session ends with `SessionError::FingerprintMismatch{expected, got}`.
  - The panes stay open (not `is_closed`) so the UI can show the error.
- **Carry-over: after the first verified connect,** the invitation file is DELETED (`NotFound` is fine) and the link is saved with `enrolled = true, invite_path = None` (load, upsert, then an atomic save via `LinksStore`). This happens on the connect job thread, so it is persisted even if the pane closed during the approval wait. A save failure is reported in `status().save_error` and does not stop the connect.
- **Attach.** After connect, every pane attaches with `resolve_and_attach`:
  - `Want::First` attaches the first listed terminal, or `create_terminal` when the Mac has none.
  - `Want::Terminal(id)` attaches `id` if it is still listed. Otherwise it attaches a free listed terminal or creates one (a daemon restart renumbers surfaces), and emits `Retargeted`.
  - `Want::New` (split) runs `create_terminal` on the same Mac (C12).
  - Every first attach emits `Retargeted{id}`, so 13b can store the real `terminal_id` in `PaneTarget::Remote`.
- **Carry-over: `Ended` handling.** An `AttachEvent::Ended` is confirmed off-thread with `list_terminals`:
  - If the client is closed, or the list call fails, it counts as a disconnect and the session reconnects.
  - If the terminal is still listed and this view had shown a snapshot, the pane reattaches.
  - Otherwise the pane ends: its link is marked ended and its sink gets `PaneEvent::Ended`. Only that pane closes.
  - When the last pane ends, the session gets `ConnEvent::RemoteEnded`, then `Str::RemoteEnded`, and finishes.
- **Disconnects.**
  - Triggers: `AttachEvent::Disconnected`, the 500 ms watchdog seeing `client.closed()`, or an attach failure.
  - Effect: the client and all views are dropped, so input is refused at once. `ConnState` shows Reconnecting and backs off 1, 2, 4, 8, 16, 30 s, and every attempt mints a fresh ticket.
  - Results that belong to abandoned attempts are dropped by attempt id.
- **Errors that stop retrying.** A connect error containing "request access again" (shellx-remote's text for an expired invitation or a PC that is not enrolled) becomes `SessionError::NeedsPairing`; the session finishes instead of retrying forever.
- **Shutdown.** `close()`, `Drop`, or closing the last pane ends the session (`ConnEvent::Close`), drops the client (non-blocking per Task 6) and deletes the last ticket file.

`fake` module (compiled in all builds, for tests and `--smoke`): `FakeConnector`, `FakeHost` and `FakeView`, plus `MintingCore` (a `tickets.mint` stand-in that writes a ticket file and counts mints).

## API for 13b

```rust
use crate::remote_session::{RemoteSession, SessionConfig, RelayConnector, Want, SessionStatus, SessionError, RemotePane};
use crate::remote_link::{RemoteMirror, PaneEvent, PaneSink, Applied};

// one per machine_id; create a new one when status().finished
let session = RemoteSession::start(SessionConfig {
    record: links_store.load()?.get(machine_id).cloned()?,   // shellx_model::links::RemoteLink
    core: shared_core.clone(),            // Arc<dyn CoreCall> (ConfiguredCore), off-UI-thread safe
    connector: Arc::new(RelayConnector),
    state_dir: paths::remote_dir()?,
    device_name: os_info::device_name(),
    links: Some(LinksStore::default_location()?),
    time_scale: 1,
})?;
let (tx, rx) = async_channel::unbounded();
let sink: PaneSink = Arc::new(move |e| tx.send_blocking(e).is_ok());
let RemotePane { id, link } = session.open_pane(Want::First /* sidebar Open */ | Want::New /* split */ | Want::Terminal(id), cols, rows, sink)?;
let mut mirror = RemoteMirror::new(link.clone())?;       // TermView uses mirror.core() like a local TermCore
// UI task: while let Ok(e) = rx.recv().await { match mirror.apply(e)? { Applied::Ended => close pane via tabs, Applied::Retargeted(id) => update PaneTarget, _ => notify } }
// input: if !mirror.send_text(commit) { flash Str::InputPaused }   (chords/paste via mirror.core(): gated in the link)
// overlay: let s = session.status(); show pill while s.phase != Connected: s.shown (Reconnecting/Offline/RemoteEnded/Connecting), s.error (FingerprintMismatch / NeedsPairing: needs new Str keys)
// resize: mirror.core().resize(..) as for local panes (the link dedups and forwards)
// machine poll (15 s): session.set_machine_online(info.online)
// pane closed in UI: session.close_pane(id)
```

How the session behaves for the UI:
- **No blocking.** All of the methods above return without blocking.
- **Status.** `status()` is a cheap clone under a mutex.
- **Repaint.** Sinks are called from worker and pump threads. A `PaneEvent::Status` means "repaint the overlay".
- **Pane ids.** `RemotePane.id` is local to the session. 13b maps model `PaneId` → (machine_id, pane id).
- **Strings.** There are no `Str` keys for fingerprint mismatch or "request access again" yet. 13b should add them (strings.rs is owned by others right now).

## Tests and CI evidence

Mac (`cd windows && CARGO_INCREMENTAL=0 cargo test --locked -p shellx-app --bin shellx-desktop`): 70 passed, 0 failed. 23 of them are new.

The 23 new tests are listed below. I also ran the remote tests 15 times in a row: 15/15 green, about 0.08 s each.

`remote_link`, 7 tests:
- `remote_commit_sends_composed_utf8`: exactly one write, `74 69 e1 ba bf 6e 67 20 56 69 e1 bb 87 74`.
- `input_while_reconnecting_is_refused_not_queued`: covers the `RemoteMirror::send_text`, `TermCore::send_text` and `send_chord` paths.
- `mirror_never_answers_queries`
- `reset_snapshot_output_build_the_screen`
- `resize_is_recorded_deduplicated_and_sent_on_install`
- `pump_forwards_in_order_and_reports_the_end`: includes stale-view drop and hang-up.
- `ended_link_is_closed_and_refuses_input`

`remote_session`, 16 tests:
- `smoke_drives_the_fake_mac`
- `ticket_file_name_fits_core_rules`
- `enrolls_once_then_connects_enrolled_with_fresh_tickets`:
  - the invite is used once, then deleted; links.json is saved enrolled
  - a second callback call mints again
  - reconnecting uses no invite and a new mint
- `falls_back_to_the_client_enrollment_record`
- `fingerprint_mismatch_never_attaches`: 0 attaches, the error is set, the link is not marked enrolled, and a later `open_pane` is refused.
- `needs_pairing_stops_retrying`
- `connect_failures_back_off_and_mint_each_time`: 3 attempts, 3 mints, Reconnecting shown, input refused.
- `reconnecting_refuses_input_and_never_queues_it`
- `ended_terminal_closes_only_that_pane_then_remote_ended`: the split (`Want::New`) gets terminal "2" and `Retargeted`; the sibling keeps working; the last end gives `RemoteEnded` and a finished session.
- `ended_with_the_client_closed_is_a_disconnect`
- `ended_while_the_list_fails_is_a_disconnect`
- `detached_but_still_listed_reattaches`
- `after_a_daemon_restart_the_pane_moves_to_a_live_terminal`
- `offline_machine_waits_then_connects_when_online`
- `closing_the_last_pane_finishes_the_session`: the ticket file is cleaned up.
- `resize_reaches_the_view_and_the_next_attach`

`shellx-remote` (`cargo test --locked -p shellx-remote`): 28 passed. That is 27 existing tests plus the new `into_parts` test.

Task 6 e2e on the Mac against the real relay and daemon:
- Command: `SHELLX_E2E_BIN_DIR=~/Documents/myProjects/shellx-pro/cmux-tui/target/debug cargo test -p shellx-remote --test relay_e2e -- --ignored`, using the W0 debug binaries read-only (the harness copies them to /tmp).
- `vietnamese_round_trip` ok and `reconnects_after_daemon_restart` ok, 2/2 in 34 s.
- `Disconnected` came 29.99 s after the kill, and dropping the dead client took 34 µs.
- No /tmp/shx* dirs or processes were left behind.

Mac `--smoke` printed `smoke-remote: enrolled (invite deleted), "tiếng Việt" = 1 write, input refused while reconnecting, reconnected with a fresh ticket (2 mints)`. It ran after the pairing check. The later PowerShell step fails on the Mac as before; that is expected.

Lint and format: clippy shows no findings in my files, and rustfmt is clean on my files and on my `term_core.rs` hunk.

**No RemoteSession e2e against the real relay.** Reusing `shellx-remote/tests/support` from shellx-app would need `getrandom` as a new dev-dep of shellx-app, and the harness lives in another crate's tests. Not cheap, so it was skipped per the brief. The fake tests plus CI `remote-e2e` cover it instead.

CI:
- Run `39176197253` (my push of `0b2f0ea513`) was cancelled by the concurrency group when the next implementer pushed `56acdac036`.
- Run `39176242679` (head `56acdac036`, which contains `0b2f0ea513`) is all green: app (windows-2025), model, remote-e2e and installer.
- The Windows `--smoke` log has `smoke-remote: enrolled (invite deleted), "tiếng Việt" = 1 write, input refused while reconnecting, reconnected with a fresh ticket (2 mints)`, then `smoke: PASS in 3.14s`.
- shellx-remote tests pass on Windows.
- remote-e2e (ubuntu): `vietnamese_round_trip` ok and `reconnects_after_daemon_restart` ok, 2 passed in 31.98 s.

## Needs user (live Windows → Mac, gates G2/G3)

Prerequisites: deployed relay v2 (`wss://relay.shellx.pro/v2/relay`), the L5 Mac bridge running ShellX (cmux-tui daemon registered on the relay), and the user's login on both machines. 13b must also be merged, because it adds the sidebar Open.

1. **Install.** On the Windows PC, install `ShellX-Setup-2.0.0-sprint.exe` and sign in.
2. **Pair.** In the sidebar, pick the Mac, choose "Yêu cầu truy cập", check the 6-digit code on the Mac and approve it (Task 12).
3. **First open.** Click Mở / Open on the Mac row.
   - Expect "đang kết nối…", then the Mac's terminal screen.
   - `%LOCALAPPDATA%\ShellX\native\core\tickets\invite-<id>.uri` must be gone afterwards.
   - `%LOCALAPPDATA%\ShellX\native\remote\links.json` must show `"enrolled": true` and no `invite_path`.
4. **Vietnamese input.** Type `echo tiếng Việt` with Telex (Unikey or Windows Vietnamese Telex) and press Enter. The Mac's shell must print `tiếng Việt`.
5. **Resize.** Resize the window. `stty size` on the Mac must follow.
6. **Disconnect.** Turn off Wi-Fi on the Mac, or quit ShellX there.
   - The pane must show "đang kết nối lại…" (or "ngoại tuyến" once the 15 s machine poll says offline).
   - Typing must flash "Mất kết nối, tạm ngừng nhập" and nothing must arrive later.
   - Turn it back on: the pane must reconnect within about 30 s, and typing must work again.
7. **Split.** Split the remote pane. A new shell must open on the Mac.
8. **End.** Type `exit` in one remote pane. Only that pane must close.

## Concerns

1. **Grid authority.** The mirror is reset to the Mac's grid on each `Resized`. If the Mac keeps a grid different from the pane's, the dedup prevents a loop, but the local VT is resized to the pane grid while the remote stays at its own size. There is no shared-sizing support (Task 6 does not advertise `shared-sizing-v1`).
2. **Ticket file name.** The verbatim name `connect-<machine_id>.ticket` is shared by overlapping mints of one machine. An abandoned attempt's late mint can overwrite the current attempt's file before it is read. Both are valid connect tickets for the same target, so this is harmless. The last file is deleted when the session ends.
3. **`NeedsPairing` detection** relies on shellx-remote's error text "request access again" (both of its messages for this case). A typed error in shellx-remote would be sturdier.
4. **Unused invite on mismatch.** On a fingerprint mismatch the invite file is left alone and the link is not changed; the user must request access again. With an invitation, Noise already pins the invite's daemon key, so a mismatch should only happen for a corrupted or tampered link.
5. **Mirror colors.** `colors-changed` and the vt-state palette are not exposed (Task 6 gap), so the mirror renders with the ShellX palette.
6. **Large file.** `remote_session.rs` is about 1.9k lines after rustfmt, about half of it fakes and tests. The fakes are compiled into release builds because `--smoke` needs them.

## Fix round 1 (controller review)

All changes are in `windows/shellx-app/src/remote_session.rs`. `shellx-remote` was not touched.

1. **Persistent attach failure (Important).**
   - With the client still open, an attach error is now a per-pane failure. The pane keeps `attach_failures` and a `retry_at` on the same 1, 2, 4, 8, 16, 30 s schedule (`backoff_ms`), run by the worker loop's timer.
   - The connection is never lost for it and no ticket is minted. A disconnect happens only if `host.closed()`.
   - `resolve_and_attach` now returns the id of a terminal it created even when the attach then fails. The pane's `want` becomes `Want::Terminal(created)`, so a retry attaches to that terminal instead of creating another one on the Mac.
   - New `SessionStatus.attach_error` holds the last reason. It is cleared once every pane has attached. A success resets the pane's counter.
   - Covering test: `attach_failure_backs_off_per_pane_without_reconnecting`. On an empty Mac with every attach failing, the test checks that within about 600 ms:
     - 3–5 attach calls happen (delays 50/100/200 ms at time_scale 20; a storm would make about 12)
     - there is 1 host and 1 mint
     - `create_terminal` runs exactly once
     - the phase stays Connected and `attach_error` is set
   - Once attaches succeed again, the pane attaches to the created terminal "1", with no second create.
2. **Close/open race (Minor).**
   - `open_pane` now checks `finished` and sends while holding the status lock. The worker publishes `finished` under that lock and only then drains its queue.
   - If the stop came from the last pane closing (`Stop::Idle`) and an `OpenPane` is queued, the session revives: a new `ConnState`, served again.
   - After a final stop (close, remote end, error), queued panes are answered. They get `Ended` with the link marked ended. With a session error they get `Status` instead, so the error shows.
   - Covering tests:
     - `closing_the_last_pane_and_opening_another_revives_the_session` (10 rounds of close then open)
     - `a_pane_opened_on_a_closed_session_is_answered`
4. **One invitation, one enrollment (Minor).**
   - The worker decides `use_invite` before it spawns the connect, and records an invitation connect as `enrolling`.
   - While that job runs (it can outlive its attempt, for example when the Mac goes offline during the up-to-300 s approval wait), a new `Connect` is deferred.
   - When the enrollment result arrives, the deferred attempt takes it (success, fingerprint mismatch or needs-pairing). On a plain failure, the deferred connect starts then.
   - Covering test: `offline_during_approval_never_enrolls_twice`. It goes offline, then online (a second mint), checks that no second connect starts, then approves. The result is one connect, one host, an attached pane, and the invitation deleted.
5. **Stale pill (Minor).** `shown` is cleared whenever the phase is Connected. This is asserted in `connect_failures_back_off_and_mint_each_time` (`status.shown == None` after the reconnect).
6. **Thread spawn failure (Minor).** `spawn_job` now takes a failure message that is posted to the worker if the thread cannot start:
   - mint: `Minted{Err}`
   - connect: `Linked{Err(Other)}`
   - attach: `Attached{Err}`
   - pump: `ViewEnd{Disconnected}`
   - end check: `EndChecked{Lost}`

   So the attempt fails and backs off instead of hanging. There is no test, because a thread spawn failure cannot be injected without a seam.
- **Security.**
  - New `SessionConfig.invite_dir`. 13b must pass shellx-core's tickets dir, `paths::core_dir()?.join("tickets")`; core writes `invite-*.uri` there.
  - `forget_invite` deletes the invitation only if `invite_path_ok` holds: the file name is `invite-<x>.uri`, and its parent dir canonicalizes to `invite_dir`. Otherwise the file is kept and `save_error` says "not deleting …". The link is saved without `invite_path` either way.
  - The invitation is now also deleted on `NeedsPairing` (expired or consumed), and the link is saved without it, still not enrolled.
  - Covering tests:
    - `invitation_is_deleted_only_from_the_tickets_dir`: the right file is deleted. A wrong name, another dir, `..` traversal and an empty `invite-.uri` are refused, and the enrollment still completes.
    - `needs_pairing_stops_retrying`: now also checks that the invite is deleted and the link has no `invite_path`.
- **#3 (deferred, as ruled).** On a real daemon, a shell `exit` may lead to a reattach instead of a pane close. That happens if the surface is still listed (not `dead`) when the end check runs right after `detached`. To verify in the live G3 check: type `exit` in a remote pane and the pane must close.

The API changes for 13b are `SessionConfig.invite_dir` and `SessionStatus.attach_error`. Nothing else changed.

Command: `cd windows && CARGO_INCREMENTAL=0 cargo test --locked -p shellx-app --bin shellx-desktop`

Output:
- `test result: ok. 83 passed; 0 failed`. That includes 28 remote tests (5 new); the 83 also include other implementers' new tests.
- `remote_` tests: 10/10 runs green in a row.
- clippy: 0 findings in `remote_*.rs`. rustfmt: clean.
- Mac `--smoke`: the `smoke-remote` line is unchanged.

CI:
- Run `39178012013` (my push of `5f849c0ef5`) was cancelled by the concurrency group when Task 12b pushed `e31b82e77d`.
- Run `39178302908` (head `e31b82e77d`, which contains `5f849c0ef5`) is all green: app, model, remote-e2e and installer.

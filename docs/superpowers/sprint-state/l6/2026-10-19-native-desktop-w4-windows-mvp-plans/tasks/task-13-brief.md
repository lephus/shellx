# Task 13: Remote Mac terminal view (open, type, resize, reconnect)

Binding constraints: `../constraints.md`; Review Focus 1 (Vietnamese composed on Windows reaches the Mac as ONE UTF-8 write of the composed text) and 3 (offline / relay restart / expired ticket: pane shows "ngoại tuyến"/"đang kết nối lại…", refuses input, never blocks the UI thread, reconnects with backoff 1,2,4,8,16,30 s using a freshly minted ticket). Builds on: `shellx_remote::{RemoteClient, ConnectConfig, Attachment, AttachEvent}` (Task 6 — read its report for the API as built), `TermCore` + `PtyLink` (Task 5), `PaneHost`/tabs UI (Task 8), `links_store` (Task 12), `remote_state::ConnState`, `core_api::mint_connect_ticket`, `sidebar::RowAction::Open`.

## Files
- `src/remote_link.rs` (cross-platform, no GPUI): `RemoteLink` implementing `PtyLink` over an `Attachment`: `write` → `attachment.write(bytes)` (one message per call, dropped with no error when not connected — input refused), `resize` → `attachment.resize`, `is_closed` → ended. A pump thread turns `AttachEvent`s into: Snapshot → reset/feed the pane's TermCore (create a fresh TermCore for a snapshot if libghostty has no reset), Output → feed, Resized → note size, Ended → pane ends (close_pane path → sibling takes the space; last pane → Respawned local tab), Disconnected → `ConnState` event.
- `src/remote_session.rs` (no GPUI): per remote machine, one `RemoteClient` shared by its panes; runs `ConnState` actions on a worker thread: `MintTicket` → `mint_connect_ticket(core, machine_id, "connect-<machine_id>.ticket")`; `Connect` → `RemoteClient::connect(ConnectConfig { state_dir: remote_dir(), device_name, relay_route, relay_slot, invite_path: link.invite_path if !link.enrolled, ticket: callback that mints a fresh ticket each call })`; after the first successful connect set `enrolled = true` and delete the invite file; then `list_terminals` (none → `create_terminal`) → `attach(first, cols, rows)`.
- UI: sidebar row action Open (and the pairing panel's "Mở") → new tab with `PaneTarget::Remote{machine_id, terminal_id}` whose TermView is backed by `RemoteLink`; split of a remote pane → `create_terminal` on the same machine (spec §8.6 C12: the new shell runs on the host) → new remote pane. Pane overlay while not Connected: centered pill (bg RAISE, BORDER) with `Str::Reconnecting` (RUNNING dot) / `Str::Offline` (MUTED) / `Str::RemoteEnded`; input refused (`accepts_input()`), IME commits while disconnected are dropped (not queued) and a status flash `Str::InputPaused` is shown. Machine list (15 s poll) feeds `MachineOffline`/`MachineOnline`.
- All network work off the UI thread; the UI thread only reads state snapshots.

## Tests
- Mac (no GPUI): `remote_commit_sends_composed_utf8` — a TermCore over `RemoteLink` with a fake attachment: IME commit `"tiếng Việt"` → exactly one attachment write with bytes `74 69 e1 ba bf 6e 67 20 56 69 e1 bb 87 74`; input while Reconnecting → no write. If `shellx-app` lib tests cannot run on the Mac, put the fake-attachment test in `shellx-remote` or drive it from `--smoke` on CI, and say which.
- Task 6's e2e (`vietnamese_round_trip`, `reconnects_after_daemon_restart`) must still pass (CI `remote-e2e`).
- Live Windows→Mac run needs gate G2/G3 (deployed relay v2 + L5 Mac bridge + the user's login): list under "Needs user" with exact steps.

## Cut rule
Master cut order: if this task is not green by lane clock ~T+8:30, ship without it (sidebar Open shows "sắp có"); report what exists.

## CI / acceptance
- `app` + `remote-e2e` green. Stage only your files. Push.

## Commit
`feat(shellx-app): view and type into a Mac terminal over relay v2 with reconnect and input gating`

## Carried from Task 6 review (binding)
- After the first successful enrolled connect, DELETE the invitation file (it holds the PSK + an embedded relay ticket) and set `enrolled = true`.
- Compare `pair.poll`'s `daemon_fingerprint` (stored in the link) with `RemoteClient::daemon_fingerprint()` after connect; on mismatch drop the client, show an error, never attach.
- Treat `AttachEvent::Ended` followed by `client.closed()` as a disconnect (reconnect), not a remote session end; only `Ended` with the client still open ends the pane.
- Event/command channels are unbounded: drain events promptly on a pump thread (never on the UI thread).

## L0 binding R17 (2026-10-19)
POST /v2/pairings returns 400 unless requester_x25519_b64 equals the machine's registered noise_public_key_b64 (D1: one X25519 device key per state_dir for login, machines.register and pairing). Never pass a key from the app: machines.register without noise_public_key_b64 (core fills the device key), pair.request inside shellx-core uses the same key. Fingerprints are computed locally (shellx-core returns them). relay_url = wss://relay.shellx.pro/v2/relay — take it only from tickets.mint / pair.poll, never hard-code it.

## Split (controller ruling): 13a non-UI, 13b UI
- **13a:** `src/remote_link.rs`, `src/remote_session.rs` (GPUI-free, worker threads, ConnState driving, enrollment + invite deletion + fingerprint check from the Task 6 carry-over), test `remote_commit_sends_composed_utf8` and the Reconnecting input-refusal test; `mod` lines in main.rs; a `--smoke` check that drives RemoteSession against a fake attachment. Do NOT touch `src/ui/*`.
- **13b:** UI wiring (sidebar Open → remote tab, overlay pill, split of a remote pane).

## Carried from Task 12b
- links.json is cached by the UI: every write (e.g. `enrolled = true` after enrollment) must go through `LinksStore` and then the UI must reload (`Cmd::LoadLinks`, see task-12b-report.md). Wire RemoteSession's enrollment save to trigger that reload.

## From Task 13a fix round (API)
- Pass `SessionConfig.invite_dir = paths::core_dir()?.join("tickets")`; show `SessionStatus.attach_error` in the pane overlay when set. Read the fix section of task-13a-report.md for the final API.

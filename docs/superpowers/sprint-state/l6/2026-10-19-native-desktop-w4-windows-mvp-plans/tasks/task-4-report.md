# Task 4 report: shellx-model sidebar / remote_state / update / core_api

Status: DONE. Commit: see `git log -1` on shellx/l6-windows ("feat(shellx-model): sidebar groups, ..."). Not pushed.

Files: windows/shellx-model/src/{core_api.rs, sidebar.rs, remote_state.rs, update.rs, lib.rs (4 pub mod lines)}. No Cargo/strings.rs changes (existing Str keys sufficed).

TDD evidence
- core_api+sidebar: tests + todo!() stubs -> 14 failed / 51 passed; then implemented -> 65 passed.
- update: 4 failed -> 4 passed.
- remote_state: 18 failed (all) with todo!() stubs -> implemented; two tests failed once on a design point (a retry tick emits only MintTicket, not ShowStatus(Connecting)); fixed in code -> green.
- Final: `cargo test --locked -p shellx-model` 87 passed, 0 failed; clippy `-D warnings` clean; fmt clean.

Decisions / deviations
- build_groups dropped `now_unix` (unused, YAGNI): signature `(machines, access, utc_offset_secs, lang)`.
- CoreConfig has no `platform` field; config_set always sends "windows".
- Pairing polls are scheduled when the previous poll result arrives (no overlapping polls), so cadence is 2 s + call latency; the scheduled tick is capped at the 300 000 ms deadline; Tick at/after the deadline -> Expired. Approved poll missing any invite field -> Failed(bad_response).
- ConnState adds an `Offline` phase (ConnPhase::Offline) and a `machine_online` flag: MachineOffline while Connected only sets the flag; the next Disconnected then goes Offline instead of backing off. Open on a known-offline machine -> Offline. A `Connected` event arriving when not Connecting returns `Drop` (stray link). Tick before retry_at_ms is ignored (stale ticks). `last_reason()` accessor added.
- Retry ticks emit only MintTicket (status stays "reconnecting"); first Open / MachineOnline emit ShowStatus(Connecting)+MintTicket.
- FakeCore::on/on_seq return &FakeCore for chaining; `on_seq` with empty vec = unknown_method.
- PairingFlow ignores stale Requested/Polled/Tick after Cancel (state Idle); a later Start while a stale Requested is still in flight could mis-pair (app should discard results by flow generation if it matters).

Concerns: none blocking. Windows CI not needed (pure Rust).

## Fix round 1
Changes
1. core_api: `Registered.slot` is `String`; test uses a b64url value (`register_machine_sends_no_key`).
2. remote_state ConnState: attempt ids (monotonic per ConnState). API: `MintTicket{attempt}`, `Connect{attempt, ticket_path}`, `Drop{attempt: Option<u32>}` (None = everything: Close and RemoteEnded), events `TicketMinted{attempt,result}`, `Connected{attempt}`, `Disconnected{attempt,reason}`. Private Minting/Linking step; TicketMinted outside Minting and Connected-accepted outside Linking are not honoured; mismatched attempt events ignored; a Connected that is not the live link's answers `Drop{Some(attempt)}`; duplicate Connected for the live link is ignored. MachineOffline in Connecting emits `Drop{Some(cur)}` + ShowStatus(Offline); in Reconnecting nothing is in flight so only ShowStatus.
3. PairingFlow: `next_tick_at` + `poll_in_flight` (kept beside PairState, whose shape is unchanged); Tick ignored if early or poll in flight (deadline check still first); `Polled{pairing_id, result}` ignored unless a poll is in flight and the id matches the current Waiting pairing. `Requested` accepted only in Requesting (not tagged with a generation: a stale Requested from a cancelled request that lands after a restart is still accepted; needs a request-generation if the app can restart that quickly).
4. sidebar: `last_seen_unix` defaults to 0 for absent/null.
Covering tests: `offline_online_flap_during_mint_yields_one_connect`, `stale_connected_during_new_mint_is_not_accepted`, `offline_while_linking_drops_the_link`, `pairing_cancel_restart_old_tick_does_not_double_poll_chain`, `pairing_stale_polled_is_ignored`, `pairing_unsolicited_polled_is_ignored`, `null_or_absent_last_seen_is_zero_and_does_not_fail_the_list`; existing conn/pairing tests migrated to the new API. (Tests were written together with the fix, no separate RED run this round.)
Command: `cd windows && cargo test --locked -p shellx-model` -> 93 passed, 0 failed; clippy `-D warnings` clean; `cargo fmt --check` clean.

# Task 4: shellx-model — sidebar groups, remote/pairing state machines, update rule, shellx-core API

Binding constraints: `../constraints.md`. Files: ONLY `windows/shellx-model/src/{sidebar.rs, remote_state.rs, update.rs, core_api.rs}` plus `pub mod` lines in `lib.rs`. Pure Rust (serde, serde_json only; do NOT edit Cargo.toml/Cargo.lock; no clock or thread in the model — time is passed in). TDD. Run `cd ~/Documents/myProjects/shellx-wt-l6/windows && cargo test --locked -p shellx-model`. Commit locally only, staging only your files. Existing modules you may use: `strings.rs` (`Lang`, `Str`, `t`, `offline_last_seen`, `update_available`), `palette.rs`, `tabs.rs`.

## core_api.rs — K3 `shellx-core` calls (contract: master plan K3 + L5 ruling D5)
- `#[derive(Clone, Debug, PartialEq, Eq)] pub struct CoreErr { pub code: String, pub message: String }` (+ `Display`).
- `pub trait CoreCall: Send + Sync { fn call(&self, method: &str, params: serde_json::Value) -> Result<serde_json::Value, CoreErr>; }` — same shape as `shellx_core::Core::call` so the app bridges it in a few lines (Task 10).
- `pub fn parse_envelope(s: &str) -> Result<Value, CoreErr>` for the C-ABI envelope: `{"ok": <value>}` → Ok(value); `{"error": {"code", "message"}}` → Err; anything else → `CoreErr{code:"bad_envelope"}`.
- Typed wrappers (free functions taking `&dyn CoreCall`, serde structs with `#[derive(Deserialize)]`, unknown fields ignored, optional fields `Option`):
  - `config_set(core, &CoreConfig { api_base, state_dir, app_version, os_version, platform: "windows", device_name })` → `config.set` (all keys as named).
  - `login(core, email, password) -> LoginInfo { user_id, device_id, device_public_key_b64, fingerprint }` → `auth.login`.
  - `logout(core)` → `auth.logout`.
  - `register_machine(core, name, os_version, app_version) -> Registered { machine_id, slot }` → `machines.register {name, platform:"windows", os_version, app_version}` (no key: core fills the device key, D1).
  - `list_machines(core) -> Vec<MachineInfo>` → `machines.list` → `{machines:[{machine_id, name, platform, online, last_seen_unix, fingerprint, is_this_machine}]}` (MachineInfo is defined in sidebar.rs; `is_this_machine` defaults false when absent).
  - `heartbeat(core)` → `machines.heartbeat`.
  - `mint_connect_ticket(core, target_machine_id, write_to: &str) -> TicketFile { path, expires_at_unix, relay_url }` → `tickets.mint {permission:"connect", target_machine_id, write_to}`.
  - `pair_request(core, to_machine_id) -> PairRequested { pairing_id, code, fingerprint }` → `pair.request`.
  - `pair_poll(core, pairing_id, write_invite_to: &str) -> PairPoll { status: PairStatus, invite_path: Option<String>, relay_route: Option<String>, relay_slot: Option<String>, daemon_fingerprint: Option<String> }` → `pair.poll`; `PairStatus` = `Pending | Approved | Denied | Expired` from the strings `"pending" | "approved" | "denied" | "expired"`.
  - `version_check(core) -> VersionInfo { status: String, min_version: Option<String>, latest_version: Option<String>, download_url: Option<String> }` → `version.check`.
  - A response that does not deserialize → `CoreErr{code:"bad_response"}`.
- `pub struct FakeCore` (in the crate, not cfg(test): the app uses it for `--smoke-ui` and while shellx-core is absent): records calls (`calls() -> Vec<(String, Value)>`), returns scripted results: `FakeCore::new()`, `.on(method, result: Result<Value, CoreErr>)` (sticky), `.on_seq(method, Vec<Result<…>>)` (one per call, last repeats). Unscripted → `CoreErr{code:"unknown_method"}`. Interior mutability via `Mutex`.
- Tests: envelope ok/error/garbage; every wrapper sends the exact method name and params (assert via `FakeCore::calls`) and parses a realistic response; `register_machine` sends no `noise_public_key_b64`; bad response → `bad_response`.

## sidebar.rs — machines → sidebar groups (spec §7.1 items 2–3, §8.6)
- `#[derive(Clone, Debug, PartialEq, Deserialize)] pub struct MachineInfo { machine_id, name, platform /* "macos"|"windows" */, online: bool, last_seen_unix: i64, fingerprint, #[serde(default)] is_this_machine: bool }`.
- `pub enum Access { None, Pending { code: String }, Granted }` — local knowledge per machine id, passed in.
- `pub enum MachineIcon { Laptop /* macos */, Desktop /* windows and anything else */ }` (VPS/`Data` is out of the MVP).
- `pub enum RowAction { None, Open, RequestAccess, ShowCode(String) }`.
- `pub struct MachineGroup { pub machine_id, pub title: String, pub note: Option<String> /* Str::ThisMachine for self */, pub icon, pub online: bool, pub dimmed: bool, pub subtitle: Option<String> /* offline text */, pub action: RowAction, pub sessions_visible: bool }`.
- `pub fn build_groups(machines: &[MachineInfo], access: &dyn Fn(&str) -> Access, now_unix: i64, utc_offset_secs: i32, lang: Lang) -> Vec<MachineGroup>`:
  - this machine (`is_this_machine`) first, always online, never dimmed, action None, note "máy này", sessions_visible true (local sessions);
  - then the others: online ones (sorted by name, case-insensitive, then machine_id), then offline ones (same sort);
  - offline: `dimmed = true`, `subtitle = offline_last_seen(lang, HH, MM)` of `last_seen_unix + utc_offset_secs` (UTC arithmetic, no tz crate), action None, sessions_visible false (U14). If `last_seen_unix <= 0` → subtitle just "ngoại tuyến".
  - online others: Access::Granted → Open (sessions_visible true); Access::Pending{code} → ShowCode(code); Access::None → RequestAccess.
  - `now_unix` is unused unless you need it for "today" logic — if unused, drop the parameter (YAGNI) and say so in the report.
- Tests: ordering (self first, online before offline, name sort), offline subtitle with offset +7h (`last_seen_unix` 1760841900 = 2025-10-19 02:45 UTC → "ngoại tuyến · lần cuối 09:45"), icons per platform, action per access state, missing `is_this_machine` deserializes as false.

## remote_state.rs — pairing + connection state machines (Review Focus 3)
Pure, event-driven: `fn on(&mut self, ev, now_ms: u64) -> Vec<Action>`; the app executes actions off the UI thread and feeds results back as events.
- Pairing (`PairingFlow`): states `Idle → Requesting → Waiting { pairing_id, code, started_ms } → Approved { invite_path, relay_route, relay_slot, daemon_fingerprint } | Denied | Expired | Failed(CoreErr)`. Events: `Start{to_machine_id}`, `Requested(Result<PairRequested, CoreErr>)`, `Tick` (timer), `Polled(Result<PairPoll, CoreErr>)`, `Cancel`. Actions: `CallPairRequest{to}`, `CallPairPoll{pairing_id}`, `ScheduleTick{at_ms}`, `Done`. Poll every 2000 ms; give up at 300 000 ms after `started_ms` → Expired; a failed poll keeps waiting (transient) up to the deadline; a Denied/Expired poll result is terminal; Cancel from any non-terminal state → Idle with `Done`.
- Connection (`ConnState`): `Disconnected → Connecting { attempt } → Connected → Reconnecting { attempt, retry_at_ms } … → Ended`. Events: `Open`, `Connected`, `Disconnected { reason }`, `TicketMinted(Result<TicketFile, CoreErr>)`, `Tick`, `MachineOffline`, `MachineOnline`, `RemoteEnded`, `Close`. Actions: `MintTicket`, `Connect { ticket_path }`, `ScheduleTick { at_ms }`, `ShowStatus(Str)` (Connecting / Reconnecting / Offline / RemoteEnded), `Drop`.
  - Every (re)connect attempt starts with `MintTicket` (a fresh ticket each time, never reusing an old one), then `Connect` with the minted path.
  - Backoff after the n-th consecutive failure: 1, 2, 4, 8, 16, 30, 30, … seconds (cap 30 s); reset to 1 s after `Connected`.
  - `MachineOffline` while not Connected: stop retrying (no ticks) and show Offline; `MachineOnline` → reconnect immediately (attempt resets).
  - `RemoteEnded` → Ended (no retry). `Close` → Ended + Drop.
  - `pub fn accepts_input(&self) -> bool` — true only in Connected.
- Tests (name them): `disconnect_backs_off_and_mints_new_ticket` (drive 7 failures: the scheduled delays are exactly 1,2,4,8,16,30,30 s and each retry emits MintTicket before Connect), `backoff_resets_after_connect`, `ticket_mint_failure_counts_as_failed_attempt`, `offline_machine_stops_retries_until_online`, `input_refused_unless_connected`, `pairing_polls_every_2s_until_approved`, `pairing_expires_after_5_minutes`, `pairing_denied_is_terminal`, `pairing_cancel_returns_idle`.

## update.rs — version.check → UpdateStatus
- `pub enum UpdateStatus { UpToDate, Available { version: String, url: Option<String> }, Required { min: String, url: Option<String> }, Unknown }`.
- `pub fn from_version_info(info: &VersionInfo) -> UpdateStatus` — trusts `status` ("ok" → UpToDate, "update_available" → Available{latest_version, download_url}, "update_required" → Required{min_version, download_url}); unknown status or missing version → Unknown.
- `pub fn from_result(r: Result<VersionInfo, CoreErr>) -> UpdateStatus` — errors → Unknown (never blocks the app offline).
- `pub fn banner(status: &UpdateStatus, lang) -> Option<String>` — Available → `update_available(lang, v)`, Required → `t(lang, Str::UpdateRequired)`, others None.
- Tests for each status, error, banner text.

## Commit
`feat(shellx-model): sidebar groups, pairing/connection state machines with backoff, update rule, shellx-core API + FakeCore`
Report to the report path given in your dispatch.

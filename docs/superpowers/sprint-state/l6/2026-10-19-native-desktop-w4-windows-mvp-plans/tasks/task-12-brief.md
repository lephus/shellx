# Task 12: Pairing requester flow (request access to a Mac, show the 6-digit code, wait for on-site approval)

Binding constraints: `../constraints.md`; master K1/K3 + L5 D5: `pair.request {to_machine_id}` → `{pairing_id, code, fingerprint}`; `pair.poll {pairing_id, write_invite_to}` → `{status, invite_path, relay_route, relay_slot, daemon_fingerprint}`; invite PSK never leaves shellx-core except into the owner-only invite file. Spec §8.5 (approval on the target; the approval screen shows the requester's fingerprint, so we show OUR fingerprint too so the user can compare). Model: `shellx_model::remote_state::PairingFlow`, `core_api::{pair_request, pair_poll}`, `sidebar::{Access, RowAction}`.

## Files
- `shellx-model/src/links.rs` (new, pure + serde): `pub struct RemoteLink { machine_id, machine_name, relay_route, relay_slot, invite_path: Option<String>, daemon_fingerprint, enrolled: bool }`, `pub struct Links { links: Vec<RemoteLink> }` with `load_from_str`/`to_string_pretty`, `upsert`, `get(machine_id)`, `remove`, `access_for(machine_id, pending: &HashMap<String, String /*code*/>) -> Access`. Tests: round trip, upsert replaces, access mapping (link → Granted, pending → Pending{code}, none → None).
- `src/links_store.rs`: persists `Links` at `remote_dir()/links.json` (atomic write: temp + rename; on Windows the per-user `%LOCALAPPDATA%` ACL is the protection; note it for security review). Contains no secrets (the invite file path, not its content).
- `ui/pairing.rs`: the request-access panel.
- Hooks: sidebar `RowAction::RequestAccess` button (secondary style, `Str::RequestAccess`) on an online machine without a link; the machines-header `Icon::AddPlus` opens a small list of the account's other machines that have no link (same action). `RowAction::ShowCode(code)` shows the code inline in the row while waiting.

## Flow
1. Click Xin quyền truy cập → `PairingFlow::Start` → `pair.request` off the UI thread.
2. Panel (card RAISE/BORDER, centered over the main area): title "Xin quyền truy cập <machine name>", the 6-digit code in Space Grotesk Bold 32 px TEXT_HI with letter spacing, formatted `123 456`; below: `Str::PairingCodeHint`; "Mã thiết bị của bạn: <fingerprint as 4×4 groups>" in MUTED mono; status line `Str::WaitingApproval` with a running-yellow dot (RUNNING); secondary button Huỷ.
3. Poll every 2 s via the state machine (`pair.poll` with `write_invite_to: "invite-<machine_id>.uri"`), give up at 5 min (Expired).
4. Approved → save `RemoteLink { enrolled: false, invite_path, relay_route, relay_slot, daemon_fingerprint }` → panel shows `Str::Approved` (DONE) + primary button Mở (Task 13 opens the remote session; until Task 13 lands, the button is shown disabled with tooltip "sắp có"). Denied → `Str::Denied` (ERROR) + Thử lại; Expired → `Str::Expired` + Thử lại.
5. Closing the panel while waiting = Cancel (stops polling).

## Tests
- Model: links.rs tests above; PairingFlow already tested (Task 4).
- A GPUI-free `PairingService` (in `src/pairing_service.rs`) that runs PairingFlow actions against any `CoreCall`: test with `FakeCore` on the Mac if shellx-app lib tests run there, else in `--smoke` (CI): scripted `pair.request` → `pair.poll` pending, pending, approved ⇒ link saved with the returned fields in a temp dir; denied ⇒ no link.
- Live run against the deployed API is possible only after gate G2 (L4 deploy): if `curl -s -o /dev/null -w '%{http_code}' https://relay.shellx.pro/v2/machines` returns 401 (route exists), note it; no live login (needs the user's password) — list it under "Needs user".

## CI / acceptance
- `app` green. Stage only your files. Push.

## Commit
`feat(shellx-app): request access to a Mac with on-site approval code, remote links store`

## Carried from Task 4 (parked finding)
`PairingFlow` accepts a stale `Requested` that arrives after Cancel → Start (for another machine) and adopts the old pairing as the new one. The PairingService must tag each `pair.request` call with a generation counter (and the target machine id) and drop any result whose generation is not current before feeding `Requested` into the flow. Test it (cancel A, start B, A's result arrives first → ignored).
NOTE (Task 4 fix): ConnState/PairingFlow events now carry ids: `Polled` has `pairing_id`; read `shellx-model/src/remote_state.rs` for the current API.

## L0 binding R17 (2026-10-19)
POST /v2/pairings returns 400 unless requester_x25519_b64 equals the machine's registered noise_public_key_b64 (D1: one X25519 device key per state_dir for login, machines.register and pairing). Never pass a key from the app: machines.register without noise_public_key_b64 (core fills the device key), pair.request inside shellx-core uses the same key. Fingerprints are computed locally (shellx-core returns them). relay_url = wss://relay.shellx.pro/v2/relay — take it only from tickets.mint / pair.poll, never hard-code it.

## Split (controller ruling): 12a now (non-UI), 12b later (UI)
- **12a:** `shellx-model/src/links.rs` (+tests), `src/links_store.rs`, `src/pairing_service.rs` (GPUI-free; drives PairingFlow against any CoreCall; generation guard from the Task 4 carry-over; on Approved saves the link; tests with FakeCore on the Mac via `cargo test -p shellx-app --bin shellx-desktop` and a `--smoke` scripted run). `mod` lines in main.rs, one small function + call in smoke.rs. Do NOT touch `src/ui/*` (other implementers are editing UI files).
- **12b:** ui/pairing.rs + sidebar/header hooks.

## 12b carry-overs (from the 12a review; fix in this dispatch)
- `invite_file_name()` is lossy: append a short hash (e.g. first 8 hex of SHA-256 or a simple FNV of the original id — no new crate: shellx-core has sha2 but the app should not depend on it; FNV-1a 64 in a few lines is fine) whenever sanitizing changed or truncated the id, so two machines never share an invite file (it holds the PSK). Test.
- Show `save_error()` in the pairing panel (ERROR text) when saving the link fails after Approved; on a corrupt links.json rename it to `links.json.bad-<unix>` and start fresh (log the rename), with a test.
- Run `PairingService::execute` AND `finish` (store I/O) off the UI thread; always deliver a JobResult (core calls are bounded by shellx-core's HTTP timeouts — check and note them).

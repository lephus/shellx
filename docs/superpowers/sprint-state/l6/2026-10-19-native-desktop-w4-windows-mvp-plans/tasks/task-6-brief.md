# Task 6: `shellx-remote` — in-process remote client (relay v2 → Noise → mux control → attach-surface) that compiles on Windows; Linux/Mac e2e

Binding constraints: `../constraints.md` (esp.: `cmux-remote` / `cmux-terminal-client` with `default-features = false`, no iroh, no wireguard; edits under `cmux-tui/` limited to `cfg` gating for the Windows client path, each ≤ 10 lines, commented `// ShellX: Windows client path`; rustls only; GPL-compatible). This is the lane's riskiest task — early on purpose. Timebox: aim to finish in ~2 h wall-clock including CI.

## Goal
A GPUI-free crate `windows/shellx-remote` the Windows app (Task 13) uses to view and type into a terminal of a Mac running ShellX (a `cmux-tui` daemon registered on `cmux-relay`, D-W0-1 protocol (b)). No local Unix socket, no `cmux-tui` sidecar process (Windows has no Unix-socket CLI path): the client runs in-process on tokio.

## Facts (from the W0 ledger / spikes — read these sources, don't re-derive)
- Ledger "Relay spike" (`docs/superpowers/ledgers/native-desktop.md`, section "Relay spike (W0 Task 4)"): enroll → approve flow, invite URI `cmux://enroll/<b64url json>` = `{version, id, secret (PSK), daemon_public_key, daemon_fingerprint, daemon_name, expires_at_unix, route_hints, relay_access:[{route, slot, ticket}], approval_required}`; client `remote connect <relay> --invite-file … --device-name … --headless` performs XXpsk3 via the relay then waits for on-site approval, then reconnects as `auth:"enrolled"`.
- Port estimate on branch `shellx/w0-spikes`: `git show shellx/w0-spikes:spikes/protocol/windows-daemon-port-estimate.md` — §0 and rows W1 (cmux-remote never compiled for Windows: `cmux-tui/Cargo.toml` Unix-only dep, unguarded `UnixStream` in `crates/cmux-remote/src/provider/dial.rs`), W9, W12 (Windows client). Protocol core files have no Unix code: `cmux-remote/src/{connection,link,session,client,crypto,service}.rs`, `provider/{websocket,stream}.rs`, `mux_client.rs`, relay provider.
- `cmux-tui/docs/remote.md` "Embedded clients": `MuxLineClient` in `cmux-remote` is the request/response form of the mux control bridge (catalog without a local socket). `crates/cmux-terminal-client` (iOS C ABI) is a complete embedded client — read it as the reference for identity/state dir, connect, catalog; it needs `iroh-transport`, so do NOT depend on it unless you can make it build with `default-features=false` without iroh within the ≤10-line cfg rule; prefer depending on `cmux-remote` (+ `cmux-remote-protocol`) directly and porting the few functions you need (MIT code from the cmux-tui workspace; keep a header comment naming the origin file).
- `cmux-tui/crates/cmux-tui/src/remote_runtime.rs` `run_client` / `connect_first_available` (≈ lines 792–930) is how `remote connect` builds the connection + `ServiceMultiplexer::new(connection, EndpointRole::Client)`; the local socket there is only a bridge — you replace it with in-process mux-control requests.
- Attach protocol: `cmux-tui/spec/events.md` ("Attach stream v6 PTY": `vt-state`, `resized`, `output`, `colors-changed`, `detached`, `overflow`), `spec/commands.md` (`attach-surface`, terminal list, `workspace create`, input/resize commands). The Mac bridge spike drove exactly this with a stock client (ledger "Mac bridge spike"). Use the v6 PTY mode: the Windows `TermCore` feeds the `vt-state` snapshot then raw `output` bytes into its own libghostty-vt (double parse renders identically, ledger).
- Tickets come from shellx-core `tickets.mint {permission:"connect", target_machine_id, write_to}` (a file path, ≤ 120 s lifetime) and `pair.poll` gives `{invite_path, relay_route, relay_slot, daemon_fingerprint}`. The client must take the ticket through a callback/file each (re)connect (`cmux-remote/src/provider/relay.rs` already has a ticket `Callback` source, ≈ lines 70–75, and a file source).
- Client identity: persistent under a caller-owned state dir (`%LOCALAPPDATA%\ShellX\native\remote\` on Windows). Owner-only file checks (`secure_directory.rs`, `secret_file.rs`) are Unsupported off Unix (security-sensitive): for the CLIENT identity on Windows, ruled by the controller: store under the per-user `%LOCALAPPDATA%` (user-profile ACLs already exclude other users), gate the Unix-only checks with cfg, and list this in the report as a "needs security review" item. Never weaken the Unix path.

## API (exact shape; Task 13 codes against it)
```rust
pub struct ConnectConfig {
    pub state_dir: PathBuf,          // client identity dir (created 0700 on Unix)
    pub device_name: String,         // shown on the Mac's approval screen
    pub relay_route: String,         // from pair.poll (e.g. "wss://relay.shellx.pro/v2/relay")
    pub relay_slot: String,
    pub invite_path: Option<PathBuf>,// first connect after pairing; None once enrolled
    pub ticket: Arc<dyn Fn() -> anyhow::Result<PathBuf> + Send + Sync>, // mints a fresh connect ticket file per (re)connect
}
pub struct RemoteClient { /* tokio runtime handle + connection + mux */ }
impl RemoteClient {
    pub fn connect(cfg: ConnectConfig) -> anyhow::Result<RemoteClient>;          // blocking; spawns its own tokio runtime thread; waits for enrollment approval when invite_path is Some (timeout 300 s)
    pub fn is_enrolled(state_dir: &Path, daemon_fingerprint: &str) -> bool;       // so the app knows whether an invite is still needed
    pub fn list_terminals(&self) -> anyhow::Result<Vec<RemoteTerminal>>;          // RemoteTerminal { id: String, title: String, cols: u16, rows: u16 }
    pub fn create_terminal(&self) -> anyhow::Result<RemoteTerminal>;              // creates a workspace/terminal when the Mac has none (L5 bridge: `workspace create --name "ShellX"`)
    pub fn attach(&self, terminal_id: &str, cols: u16, rows: u16) -> anyhow::Result<Attachment>;
    pub fn closed(&self) -> bool;
}
pub struct Attachment { /* … */ }
impl Attachment {
    pub fn events(&self) -> &std::sync::mpsc::Receiver<AttachEvent>;  // or crossbeam/async-channel; std is fine
    pub fn write(&self, bytes: &[u8]) -> anyhow::Result<()>;          // input, ONE message per call (composed IME text stays one UTF-8 write)
    pub fn resize(&self, cols: u16, rows: u16) -> anyhow::Result<()>;
    pub fn detach(self);
}
pub enum AttachEvent { Snapshot(Vec<u8>) /* vt-state bytes */, Output(Vec<u8>), Resized { cols: u16, rows: u16 }, Ended /* surface exited / detached */, Disconnected(String) }
```
No GPUI types, no blocking of the caller's thread except `connect`/`list`/`create`/`attach` (Task 13 calls them off the UI thread). Adjust names only if the protocol forces it, and document the change in the report.

## Tests
- Unit tests for any pure code you write (invite parsing, event decoding) — run on the Mac.
- `tests/relay_e2e.rs` + `tests/support/mod.rs`, `#[ignore]`, Unix only (`#![cfg(unix)]`): builds/locates `cmux-relay` and `cmux-tui` from the cmux-tui workspace (`cargo build -p cmux-relay -p cmux-tui --release` in `cmux-tui/`, binary paths via env `SHELLX_E2E_BIN_DIR` defaulting to `cmux-tui/target/release`), mints register/connect tickets with `cmux-relay`'s CLI mint (ledger "Ticket format"; `cmux-relay/src/main.rs:18-46`), starts relay + `cmux-tui server start --headless --ephemeral --relay … --relay-slot … --relay-ticket-file …`, creates an invite (`remote enroll create … --advertise <route> --relay-route <route> …`), connects `RemoteClient` with it, approves via `remote enroll approve`, then: `list_terminals` (create one if empty), `attach`, write `printf 'tiếng Việt\n'`-style input and assert the output contains `tiếng Việt` (test `vietnamese_round_trip`), resize works, and `reconnects_after_daemon_restart` (kill + restart the daemon on the same state; with `--ephemeral` the daemon state is lost, so assert instead: the client reports Disconnected, and a new `RemoteClient::connect` with a fresh ticket succeeds — document what is tested). All processes under a temp dir; secrets/tickets removed at the end. Run it on the Mac: `cargo test -p shellx-remote --test relay_e2e -- --ignored --nocapture` (needs the cmux-tui build: check `df -h /` ≥ 15 GB free first; cmux-tui needs the ghostty submodule: `git submodule update --init ghostty --reference ~/Documents/myProjects/shellx-pro/ghostty` from the worktree root; Zig at `~/.local/zig-0.16.0`). If another lane already built these binaries, you may point `SHELLX_E2E_BIN_DIR` at `~/Documents/myProjects/shellx-wt-l5/cmux-tui/target/release` READ-ONLY if they exist (never write there).
- CI (`.github/workflows/shellx-windows.yml`): add job `remote-e2e` on `ubuntu-24.04` (ghostty submodule + zig + rust like the `app` job; cache `cmux-tui -> target` and `windows -> target`) running `cargo test --locked -p shellx-remote` and the ignored e2e; and in the `app` job (windows-2025) add `cargo build --release --locked -p shellx-remote --target $TARGET` (compile proof on Windows; share the target dir so it's warm). Push and get all jobs green.

## Fallback (decide yourself, report it)
If the in-process client is not achievable in the timebox, deliver in this order and stop: (1) `shellx-remote` with the API above where `connect` returns a clear `Err("remote view not available in this build")` on Windows, (2) all of cmux-remote's client path compiling on Windows in CI (cfg gating ≤10 lines each), (3) the e2e on Unix proving the API end to end. Report precisely what is missing.

## Commit
`feat(shellx-remote): in-process cmux remote client over relay v2 (attach-surface), Windows build + Unix e2e`

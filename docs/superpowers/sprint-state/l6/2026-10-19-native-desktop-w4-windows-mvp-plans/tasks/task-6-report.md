# Task 6 report: `shellx-remote`

**Status: DONE.** The in-process client works. No fallback was needed.

- Commit `8002a99089`: `feat(shellx-remote): in-process cmux remote client over relay v2 (attach-surface), Windows build + Unix e2e`. It is pushed to `shellx/l6-windows`.
- CI run `39168776979` (it covers the push of `8002a99089` and the later `f168cbfe76`) is green in all three jobs: `model`, `remote-e2e` and `app` (windows-2025). The earlier run `39168588868` was cancelled by the concurrency group when `f168cbfe76` was pushed.

## Approach and why

The crate depends directly on `cmux-remote` (`default-features = false`, so no iroh and no WireGuard) and on `cmux-remote-protocol`. It does **not** depend on `cmux-terminal-client`, because that crate needs `iroh-transport`.

How a connection is made:
- **Transport.** `RelayProvider::with_credentials` uses a `RelayCredentialSource::callback`. The callback calls the app's `ticket` closure. Connect requests use `relay+ws(s)://…`, with `LanePolicy::Auto`.
- **Authentication.** `ClientConnection::connect_with_reconnect_groups` runs Noise XX, or XXpsk3 with the invitation. Its `ReconnectGroupSource` makes a new relay group on each reconnect, so each reconnect gets a fresh ticket.
- **Services.** `ServiceMultiplexer` (Client role) carries the mux control service.
- **Control requests.** One upstream `MuxLineClient` serves request/response calls: `identify`, `set-client-info`, `list-workspaces` and `new-workspace`.
- **Attachments.** Each `Attachment` opens its own MuxControl stream and runs a writer task and a reader task. The commands are `identify`, then `attach-surface {surface, cols, rows}` (when `attach-initial-size` is advertised), then `send {bytes}` and `resize-surface`.

Code ported from upstream (MIT; each file names its origin in a header comment):
- `src/mux.rs`: the CMXL line codec (`encode_line`, assembler), the lane choice and `await_opened`. Upstream these are `pub(crate)`; the Mac sidecar reaches them only through its Unix-socket bridge.
- `src/lib.rs` follows the structure of `cmux-terminal-client::connect_route_client` and `remote_runtime::run_client`.

On Windows, cmux-tui needs no local socket and no sidecar process.

## API as built (shape from the brief, unchanged)

`ConnectConfig {state_dir, device_name, relay_route, relay_slot, invite_path, ticket}`, `RemoteClient::{connect, is_enrolled, list_terminals, create_terminal, attach, closed}`, `Attachment::{events, write, resize, detach}`, `AttachEvent::{Snapshot, Output, Resized{cols,rows}, Ended, Disconnected(String)}`, `RemoteTerminal {id, title, cols, rows}`.

Additions and semantics Task 13 must know:
- **Extra accessor:** `RemoteClient::daemon_fingerprint()`.
- **Event order:** every `Snapshot` comes right after a `Resized`. This holds for the first `vt-state` and for every v6 `resized` replay. On `Resized`, create a fresh mirror at cols×rows. Then feed the `Snapshot`, then the `Output` events in order.
- **Overflow:** a daemon `overflow` event becomes `Disconnected`, and the app should reattach.
- **Terminal ids:** `RemoteTerminal.id` is the daemon surface id as a decimal string. It is only valid for one daemon boot.
- **Pairing and the slot map:** `connect` without an invitation looks up the pinned daemon key by `relay_slot`. All Macs share the relay route, so the route cannot select the Mac. The map is `shellx-slots.json` in `state_dir`, written at enrollment. This is why `ConnectConfig` needs no fingerprint field.
- **Ticket files:** a ticket is read once and the file is then deleted. One minted ticket is reused for up to 30 s, which covers the control socket plus about 3 circuits of one connect.
- **Recovery and `Disconnected`:** in-place recovery is bounded (`maximum_duration` 30 s, backoff 250 ms → 4 s). After that the multiplexer turns fatal: views get `Disconnected` and `closed()` becomes true. The app's 1→30 s backoff then builds a new `RemoteClient` with a fresh ticket.
- **Refused input:** `write` returns `Err` once a view has ended.
- **Threading:**
  - The client runs its own 2-worker tokio runtime.
  - `connect`, `list_terminals`, `create_terminal` and `attach` block the calling thread.
  - `write`, `resize` and `detach` never block.
  - Don't call the blocking ones or drop the client from inside another tokio runtime.
  - If the `RemoteClient` is dropped, every attachment channel hangs up.
- **Timeouts:**
  - enrollment with approval: 300 s
  - enrolled connect: 30 s
  - requests: 15 s
  - attach: 20 s
- **TLS:** ring is installed as the rustls provider, and `rustls` is added as a dependency with `ring`. Without it, nothing in this workspace enabled a rustls crypto provider, and `wss://` would have panicked. A unit test (`wss_has_a_tls_provider`) guards this.

## cmux-tui edits (cfg gating only, each commented `// ShellX: Windows client path`)

| File | Lines | What |
| --- | --- | --- |
| `cmux-tui/crates/cmux-remote/src/provider/dial.rs` | +8 / −1 (one hunk) | `UnixStream` import made `cfg(unix)`. Off Unix there is a stub whose `connect` returns `Unsupported`. The SOCKS hub dial fails at runtime instead of breaking the build. |
| `cmux-tui/crates/cmux-remote/src/services.rs` | +2 | `#[cfg(unix)]` on `validate_renderer_host_hello`, which uses the Unix-only terminal-host types. |

With these two gates, all of `cmux-remote` compiles on Windows. I found them with a local `cargo check --target x86_64-pc-windows-gnu` (zig cc wrapper); msvc was then confirmed on CI.

## Tests and CI evidence

Unit tests: 25 on Unix, 23 on Windows (two of the Unix ones are cfg(unix)). They cover:
- the codec (round trip, multi-part out of order, interleaving, bad packets)
- event decoding (vt-state, pending, v6 `data` / v7 `replay`, output with UTF-8 bytes, detached, overflow, bad payloads, responses)
- tree parsing
- the plain store and the slot map
- `is_enrolled` never creating the dir
- Unix modes 0700 / 0600
- ticket reuse, deletion and error memory
- rejection of a world-readable ticket on Unix
- relay route mapping
- an invitation file round trip
- the reconnect policy
- the TLS provider

The e2e lives in `tests/relay_e2e.rs` and `tests/support/mod.rs`. It is `#![cfg(unix)]` and `#[ignore]`:
- **Isolation:** binaries are copied to `/tmp/shx…`, every process runs with an isolated env (HOME, TMPDIR, no inherited variables), and secrets, tickets and the invitation are removed on drop.
- **`vietnamese_round_trip`:**
  - The client enrolls with a `ws://` route and the owner CLI approves it.
  - It lists terminals, or creates one when there are none, then attaches.
  - It writes `printf '%s-%s\n' 'tiếng Việt' $((6*7))` as one write and asserts `tiếng Việt-42` in the output. The marker only appears in the shell's output, never in the echo of the typed line.
  - It resizes to 120×40, asserts `Resized{120,40}`, and asserts `stty size` prints `40 120`.
  - After a detach, `list_terminals` still works.
- **`reconnects_after_daemon_restart`:**
  - The daemon is SIGKILLed (no graceful detach). The view gets `Disconnected` (about 30 s, the in-place recovery bound) and `write` returns `Err`.
  - The daemon restarts on the same `--remote-state-dir`, and `closed()` becomes true.
  - A new `RemoteClient::connect` with no invitation (enrolled auth) and a freshly minted ticket succeeds against the restarted daemon. A new attach round trip (`again-42`) works.
  - Not tested: resuming the same view across a restart. That is impossible with `--ephemeral`, because workspace state dies with the daemon.

Runs:
- **Mac:** both e2e tests pass, 2/2 in 34 s, and no processes or `/tmp/shx*` dirs are left behind. The binaries were the existing W0 debug builds from `~/Documents/myProjects/shellx-pro/cmux-tui/target/debug`, copied to scratch (read-only use). I did no local cmux-tui build because the disk was at the floor. `git diff 5348097e66 HEAD` shows no change in `cmux-remote/src`, `cmux-remote-protocol` or `cmux-relay`.
- **CI run `39168776979`:**
  - `remote-e2e` (ubuntu-24.04): cmux-relay + cmux-tui release builds in 3m44s (LTO off for test binaries), unit tests 25/25, e2e 2/2 (`Disconnected` after 29.99 s).
  - `app` (windows-2025, msvc): `cargo build --release --locked -p shellx-remote` finishes in 4m00s, and `cargo test --release -p shellx-remote` passes 23/23 on Windows, including the plain store on NTFS.
  - `model`: green.

## Workflow changes (`.github/workflows/shellx-windows.yml`)

- New job `remote-e2e` on ubuntu-24.04: ghostty submodule, zig, pinned Rust, rust-cache for `cmux-tui -> target` and `windows -> target`, then `cargo build --release --locked -p cmux-relay -p cmux-tui` with `CARGO_PROFILE_RELEASE_LTO=false` and `CODEGEN_UNITS=16`, then the unit tests and the ignored e2e (`SHELLX_E2E_BIN_DIR`).
- In the `app` job: "Build shellx-remote" and "Test shellx-remote" steps, both release profile so they reuse the shellx-app dependencies.

## Needs security review

1. **Windows client identity (controller ruling, applied).** `store.rs` uses a `PlainStore` on non-Unix: `shellx-client-identity.json` (X25519 private key) and `shellx-known-daemons.json` under the caller's state dir. It has no explicit owner-only DACL, no owner-SID check, no reparse-point or link-count check and no file lock. It relies on the per-user `%LOCALAPPDATA%` ACL. Unix still uses upstream `ClientIdentityStore`, unchanged.
2. **Windows ticket and invitation files.** These are plain reads (size-capped) with no owner check. Unix keeps `secret_file::read_owner_only_string`. Ticket files are deleted after reading on both platforms.
3. **Slot map trust.** `shellx-slots.json` (slot → fingerprint) only selects which pinned key a connect expects. Noise still verifies the daemon key, and a mismatch is a hard error.
4. **Approval screen.** Approval shows the `device_name` sent by the client. Per the ledger, the Mac's approval UI must also show the device fingerprint (out of scope here).

## What's missing / notes

- **Colors not surfaced.** `colors-changed` and the vt-state `colors` (palette, cursor style) are not exposed in `AttachEvent`, because the API has no variant for them. Task 13 renders with its own palette.
- **No compact input path.** Input is sent as JSON `send {bytes}`. The compact `mux-input-v1` packets are not used (an optimization, not needed for correctness).
- **Shared sizing.** The client does not advertise `shared-sizing-v1`, `view-attachment-lease-v1` or `terminal-pending-sequence-v1`. Without the pending capability, the server appends pending bytes to the snapshot, which is correct for us.
- **No wss e2e.** `wss://` was not tested end to end; the e2e uses `ws://` on loopback. The TLS provider is unit-tested.
- **A file from Task 5 got into my commit.** `8002a99089` also contains `windows/shellx-app/src/ui/term_view.rs` (753 lines). The Task 5 implementer had already staged it in the shared index, and `git commit` takes everything staged. The controller was told. Correction: `8002a99089` on its own does **not** build shellx-app on Windows (the staged file goes with an `app.rs` rename that is not in that commit). The next commit, `f168cbfe76`, fixes the build, and CI run `39168776979` is green on it. History was not rewritten. From now on I commit with `git commit -- <paths>`.
- **Disk left behind:** 14 GiB free. `windows/target` is 5.2 GB (debug). I deleted my windows-gnu check output (583 MB) and the scratch binary copies. The `x86_64-pc-windows-gnu` rust-std is installed for toolchain 1.95.0 (~250 MB; removable with `rustup target remove --toolchain 1.95.0 x86_64-pc-windows-gnu`). The `ghostty` submodule is now initialized in the worktree.

## Fix round 1 (controller review)

Changes are in `windows/shellx-remote` only.

1. **`RemoteClient` drop no longer blocks (Important).** `Drop` now moves the runtime and the inner state into a detached `shellx-remote-close` thread. That thread does the three graceful closes (each bounded at 2 s) and `shutdown_timeout(500 ms)`; `drop` itself returns at once. If the thread cannot be spawned, the graceful close is skipped instead of blocking. A drop from inside a tokio context no longer calls `block_on` on the caller's thread, so it cannot panic. `Attachment::detach`/drop only queue a `Close` command on an unbounded channel, so they never block. Covering test: the e2e `reconnects_after_daemon_restart` now drops the attachment and the client after the daemon was killed, and asserts the drop takes less than 100 ms (measured on the Mac: 66.7 µs).
2. **Connect error path.** On `Err`, `connect` now calls `runtime.shutdown_background()`. The implicit runtime drop no longer waits for in-flight `spawn_blocking` work, such as the app's ticket callback.
3. **Ticket cache.** A cached ticket is now reused only within one connect burst. `TicketSource::new_burst()` is called before every reconnect group (`RelayReconnect::next_group`) and again when that group's connect fails, so a ticket the relay rejected is never retried by a later attempt. Each `RemoteClient::connect` already had its own empty source. The 30 s cap still bounds reuse within a burst. Inside a single burst, upstream's one immediate auth retry can still get the same dead ticket; that burst then fails and the next one mints fresh. Covering unit test: `ticket::tests::a_new_burst_never_reuses_the_previous_ticket`.
4. **`is_enrolled` is read-only.** It only reads `shellx-slots.json`, which is written only after the daemon key was pinned. It no longer calls `ClientIdentityStore::load_or_create` (which created a key and a lock) and no longer builds a runtime. Covering unit tests: `store::tests::is_enrolled_has_no_side_effects` (an existing empty dir stays empty), plus the existing `is_enrolled_never_creates_the_dir` and `slot_map_selects_the_pinned_daemon`.
5. **Report wording.** The term_view.rs paragraph above is corrected.
6. **Crate docs** (`src/lib.rs`, "Contract notes for the app", no code changes):
   - The channels are unbounded, so there is no backpressure.
   - `Ended` can also mean the daemon was stopped gracefully; treat `Ended` together with `closed()` as "reconnect".
   - The caller must delete the invitation file after a successful enrollment, and should compare `pair.poll`'s `daemon_fingerprint` with `daemon_fingerprint()`.
   - Dropping a client returns immediately.

Commands and output:
- `cd windows && CARGO_INCREMENTAL=0 cargo test --locked -p shellx-remote`: `test result: ok. 27 passed; 0 failed` (lib), `0 passed; 2 ignored` (relay_e2e).
- `cargo clippy -p shellx-remote --tests`: no findings in shellx-remote.
- Mac e2e with the W0 binaries (copied to scratch, read-only use): `SHELLX_E2E_BIN_DIR=… cargo test --locked -p shellx-remote --test relay_e2e -- --ignored --nocapture`:
  - `vietnamese_round_trip ... ok`
  - `view 29.98s after daemon kill: Disconnected("reconnect deadline expired after 22 attempts")`
  - `dropping the dead client took 66.709µs`
  - `reconnects_after_daemon_restart ... ok`
  - `test result: ok. 2 passed`
  - No processes or `/tmp/shx*` dirs left behind.

CI: the runs for the fix commit `6463ad16fa` (`39170478594`) and for `87da2d498a` were cancelled by newer pushes. Run `39170733197` (head `10c18e58ba`, which contains `6463ad16fa`) is all green: app, remote-e2e, model and installer.

# Task 8 report: remote e2e harness and `shellx-remote.yml`

Status: DONE_WITH_CONCERNS (all CI jobs green on the first push; the concerns are findings for other tasks, see the end)
Branch `shellx/l5-remote`, worktree /Users/lehuuphu/Documents/myProjects/shellx-wt-l5, base 8afed49289.
Commits: `c6c1875324 test(shellx): remote e2e harness (fake API, cmux-relay, patched daemon) and shellx-remote CI` (one commit, no CI-fix commits needed)
Pushed: `git push origin shellx/l5-remote` (only this branch).

## What was built

- `scripts/shellx/remote-e2e/fake_app.py`: a stand-in for the Mac app on the virtual PTY socket, ported from the spike (`git show 4e1ed7bc41:spikes/protocol/mac-bridge/fake_app.py`). Changes from the spike:
  - The hello's `protocol` is checked. Anything other than 1 is refused: the connection closes with no ack, so `virtual_pty::open` fails.
  - The ack is `{"surface_id","workspace_id","mode"}`. `mode` is `attach` for the first terminal while none is bound and `create` after that (D7).
  - The fake app sends its own grid `S` and a banner `O` (`SHELLX-FAKE-APP ready` + prompt).
  - Input is echoed back with `\r`→`\r\n`.
  - Every `R` gets the forced `S` echo, because the Mac owns the grid.
  - `K` ends the connection.
  - Every `I` payload is written to `--input-log` as `<conn> <hex>`, one frame per line. `--log` records events and lengths only.
- `scripts/shellx/remote-e2e/harness.py`: `Harness(bin_dir, core_bin_dir, ticket_ttl)` with `start_relay/stop_relay/start_api/machine/host_cli/start_host_daemon/restart_host_daemon/pair/connect_viewer/approve_pending/viewer_cli/viewer_ok/first_terminal/fake_app_input/logs/dump_logs/close`. `Machine` has its own `core/` state dir (0700), its own `SHELLX_CORE_CONFIG`, and `core(method, **params)`, `login()`, `register()` and `start_ticket_refresher(write_to, permission, target=None)`. Also exported: `wait_until(timeout, fn)`.
  - Layout: one run is one dir, `/private/tmp/sx-XXXXXXXX` (0700, short enough for sun_path). Every machine has its own `core/ home/ tmp/ run/ d/` (daemon `--remote-state-dir`), `c/` (client `--state-dir`) and `b/` (bridge socket dir, 0700). `close()` stops everything (refreshers, client supervisor, client, daemon, fake app, API, relay) and then removes the dir. tearDown asserts that the dir is gone.
  - Environment: every process gets an explicit environment dict (the same effect as `env -i`, without putting the secret in argv). The dict holds `HOME`, `TMPDIR`, `XDG_RUNTIME_DIR` and `CMUX_TUI_CONFIG` inside the harness dir, plus `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, `USER`, `LOGNAME`, `LANG` and `TERM`.
  - Secrets: the relay HMAC secret is `secrets.token_hex(32)` per run and goes to the relay and the fake API by env only. The fake-account password is random per run (`SHELLX_FAKE_PASSWORD` env for the API).
    - The harness log has method names, result codes and durations, never params or stdout.
    - Errors copied from failing commands are redacted (tickets, invites, secret, password).
    - `dump_logs` (printed only on failure) also redacts, and it skips the input hex log.
- `tests/test_shellx_remote_e2e.py`: the brief's 4 tests, with the bodies kept verbatim.
  - `setUp` builds nothing. It reads `SHELLX_E2E_BIN` and `SHELLX_E2E_CORE_BIN` and calls `skipTest` with the exact build commands when the binaries are missing.
  - It then starts the relay and API, logs in and registers both machines, and starts the host daemon. For the three tests that use `self.term`, it also enrolls the viewer (pair → connect → approve → `workspace create` → `first_terminal`).
- `.github/workflows/shellx-remote.yml`, with jobs `core` (matrix ubuntu-24.04/macos-26), `swift-package` (macos-26) and `bridge-e2e` (ubuntu-24.04, 60 min); details are under Deviations (CI).
- `tests/test-execution.toml`: the entry exactly as the brief gives it (`lane = "manual"`, the brief's reason).

## Deviations from the brief (the source wins)

1. **Relay path is `/v1/relay`, not `/v2/relay`.**
   - Stock cmux-relay routes only `/healthz`, `/v1/relay` and `/ws` (`cmux-tui/crates/cmux-relay/src/relay.rs:243-245`).
   - The fake API is started with `--relay-url ws://127.0.0.1:<port>/v1/relay`. The harness turns the `relay_url` from `tickets.mint` into `relay+ws://127.0.0.1:<port>/v1/relay`, which keeps the D6 conversion and the path.
   - Relay start: `cmux-relay serve --bind 127.0.0.1:<port>` with env `CMUX_RELAY_HMAC_SECRET` and `CMUX_RELAY_ISSUER=shellx-relay` (`config.rs:180-185`). The fake API uses `--issuer shellx-relay`.
2. **cmux strips the path from invite routes** (`cmux-remote/src/identity.rs:2216-2219`, `credential_free_route_hint`, applied to `route_hints` and `relay_access[].route` at `:1108-1111`).
   - So `pair.poll` returns `relay_route = relay+ws://127.0.0.1:<port>`. The harness checks it against `route_origin(route)`, and checks `relay_slot` and `daemon_fingerprint` (against `remote enroll status --json`).
   - This is a D6 finding; see Concerns 1.
3. **The viewer client is supervised and restarted** (not in the brief's interface).
   - Upstream `remote connect` ends in two cases:
     - (a) after a daemon restart: `connection protocol failed: daemon no longer has the requested logical session` (seen in client-viewer-1.log);
     - (b) after any relay authentication rejection: `relay rejected the authenticated operation`, which is non-retryable (`cmux-remote/src/provider/relay.rs:1557-1574`, `:1590-1592`).
   - After approval, `_supervise_client` does what Task 12's app does. It restarts `remote connect <route> --daemon <fingerprint> --relay-slot … --relay-ticket-file … --state-dir … --local-socket … --headless --device-name …` as an enrolled device (no invite; the daemon is pinned in the client state dir) on a 1, 2, 4, 8, 16, 30 s backoff (RF2).
   - Without this, `test_enrolled_device_reconnects_after_daemon_restart` fails every time (RED, below).
4. **The ticket refresher floor is 0.25 s, not 1 s.** The rule is still mint, then sleep `max(floor, (exp-now)/2)`.
   - Ticket expiry is a whole second, so a fresh 2 s ticket has 1-2 s left. With a 1 s floor the file can hold an already-expired ticket for one mint latency in some cycles.
   - A connecting cmux client treats `invalid-ticket` as fatal (item 3b).
   - Refreshing at half-life keeps at least ~0.5 s of life in the file.
5. **The harness serializes `shellx-core-cli` calls per machine.**
   - `StateStore::open` runs `sweep_stale_temps` on the state dir and on `tickets/` (`shellx-core/src/store.rs:205-208`, `:285-286`). It documents that it "Assumes one process owns a state dir".
   - When the refresher thread and a main-thread call ran two CLI processes at once, one swept the other's temp file. Seen: `host: tickets.mint -> io: rename …/tickets/invite-connect.ticket: No such file or directory (os error 2)`.
   - The app has one in-process Core, so this is not a product bug as specified; see Concerns 3.
6. **Flags, checked against the source:**
   - `server start` (`cmux-tui/src/main.rs:740-885`): the brief's flags apply as given (`--session --headless --ephemeral --socket --remote-state-dir --relay --relay-slot --relay-ticket-file`). `rewrite_server_start` turns it into a foreground headless run (`main.rs:1323-1355`).
   - `remote enroll create|pending|approve|status` (`remote_cli.rs:1381-1478`): as in the brief, with `--session` and `--state-dir` appended by `host_cli`.
     - `create` prints only the URI; `--json` would give `{"uri"}` (`cmux-remote/src/admin.rs:717-725`). So the invitation id is decoded from the URI (`identity.rs:106-125`) and kept in memory only.
     - `pending --json` is a list of `{invitation_id, device_name, device_fingerprint, requested_at_unix}` (`identity.rs:478-483`).
   - `remote connect` (`remote_cli.rs:111-160`, `:404-415`): as in the brief.
     - CLI relay credentials override the invite's static ticket only for an identical route string (`remote_cli.rs:657-675`). Because of item 2 the invite route is a second candidate, and it carries the invite's 2 s ticket, which is already expired.
     - Restarts add `--daemon <fingerprint>`.
   - Daemon readiness = `remote enroll status --json` answers.
7. **`stop_relay` is SIGKILL.** It is an outage, and the relay's graceful shutdown waits for every WebSocket to close (`cmux-relay/src/main.rs:51-55`).
8. **`SHELLX_E2E_REQUIRE=1`** (set by CI) turns the missing-binaries skip into a failure, so CI cannot pass by skipping.
9. **D3 accepted, so Step 6 (placeholder ticket) was skipped.**
10. **CI: inlined Rust setup and pins** (ruling R9).
    - The Rust setup inlines `/Users/lehuuphu/Documents/myProjects/shellx-pro/.github/actions/setup-cmux-tui-rust/action.yml`: rustup if missing, then the toolchain from `cmux-tui/rust-toolchain.toml` (1.95.0), set as default. It is used for shellx-core too.
    - The ghostty submodule is initialised with `scripts/ci/init-submodule.sh ghostty` (only ghostty).
    - Pins: checkout `de0fac2e…` v6.0.2 and Swatinem/rust-cache `6323deb1…` v2.9.2, both from cmux-tui.yml.
    - The `core` job also runs `scripts/test_check_deps.py`, and runs c-smoke only on macOS.
    - `swift-package` is kept, a judgement call. shellx-mac.yml runs the same `swift test` inside its 120-min app-build job, which is cancelled on every new push. This job is ~1-2 min and keeps the lane's evidence in one workflow. It runs `scripts/select-ci-xcode.sh` first, like shellx-mac.yml.

## Tests

### RED

The tests were written first, before the harness existed: `SHELLX_E2E_BIN=/nonexistent SHELLX_E2E_CORE_BIN=/nonexistent python3 tests/test_shellx_remote_e2e.py` →
```
  File ".../tests/test_shellx_remote_e2e.py", line 29, in <module>
    from harness import Harness, wait_until  # noqa: E402
ModuleNotFoundError: No module named 'harness'
```
Further RED runs during implementation, against real binaries:
- First run: `pair` refused the invite's route (`sealed invite names relay route 'relay+ws://127.0.0.1:55502', not '…/v1/relay'`). This led to item 2.
- First full run: `test_enrolled_device_reconnects_after_daemon_restart` FAIL, because the client exited with "daemon no longer has the requested logical session". This led to item 3.
- `test_reconnect_after_relay_restart_with_2s_tickets` was intermittent: 1 of 4 full runs failed, and 4 of 8 single runs failed between the fixes.
  - The failures were "relay rejected the authenticated operation" and `tickets.mint -> io: rename …`.
  - A temporary diagnostic `eprintln!` in cmux-relay's `RelayError::control` gave the relay codes in one failing run: `invalid-ticket` "relay ticket has expired" ×13, `lease-expired` ×15, `ticket-mint-failed` ×6. The patch was reverted; `git status` shows cmux-tui unchanged.
  - This led to items 4 and 5.

### GREEN (local, macOS)

Binaries: patched cmux-tui and cmux-relay built from this worktree into the shared target (`CARGO_INCREMENTAL=0 CARGO_TARGET_DIR=/Users/lehuuphu/Documents/myProjects/shellx-pro/cmux-tui/target cargo build -p cmux-tui -p cmux-relay --locked`, 3 m 55 s), plus shellx-core `cargo build --workspace --locked`.

`SHELLX_E2E_BIN=/Users/lehuuphu/Documents/myProjects/shellx-pro/cmux-tui/target/debug SHELLX_E2E_CORE_BIN=$PWD/shellx-core/target/debug python3 tests/test_shellx_remote_e2e.py -v`:
```
test_enroll_via_sealed_invite_and_view ... ok
test_enrolled_device_reconnects_after_daemon_restart ... ok
test_reconnect_after_relay_restart_with_2s_tickets ... ok
test_vietnamese_round_trip ... ok
Ran 4 tests in 21.530s
OK
```
- After the final fixes:
  - the relay test alone passed 6 of 6 times;
  - the full suite passed 4 of 4 times (28.7 s, 20.9 s, 19.8 s, 50.7 s), plus the final run above;
  - no `/tmp/sx-*` dir and no stray process was left.
- These GREEN runs used a cmux-relay binary that still had the diagnostic `eprintln!` on its error path (see Concerns 5). Behaviour is otherwise identical; CI builds the clean source.
- Without the binaries, the suite skips: `OK (skipped=4)`, rc 0. shellx-mac.yml's `tests/test_shellx_*.py` loop also runs this file and gets that result.
- Registry: `scripts/ci/validate_test_execution_registry.py` reports nothing for this test. It exits 1 both before and after this change, because of pre-existing "lane not run by any workflow" entries now that cmux's workflows are gone.

### CI

Run **39173969849** (shellx-remote, push of c6c1875324): conclusion **success**, all 4 jobs green.
- shellx-core (ubuntu-24.04): success, 42 s.
- shellx-core (macos-26): success, 1 m 28 s.
- ShellXBrand package tests: success, 1 m 06 s.
- virtual PTY + remote e2e (linux): success, 11 m 02 s, cold cache.
  - `cargo test -p cmux-tui-core --lib virtual_pty --locked`: `test result: ok. 11 passed; 0 failed` (Task 7's tests on Linux).
  - e2e: `test_enroll_via_sealed_invite_and_view ... ok`, `test_enrolled_device_reconnects_after_daemon_restart ... ok`, `test_reconnect_after_relay_restart_with_2s_tickets ... ok`, `test_vietnamese_round_trip ... ok`, `Ran 4 tests in 27.795s`, `OK`.
  - The downloaded job log has 0 matches for `v2\.[A-Za-z0-9_-]{20,}\.`.
- shellx-mac run 39173969814 started on the same push (separate workflow, not part of this task).

## Files changed
- New: `/Users/lehuuphu/Documents/myProjects/shellx-wt-l5/scripts/shellx/remote-e2e/harness.py`, `/Users/lehuuphu/Documents/myProjects/shellx-wt-l5/scripts/shellx/remote-e2e/fake_app.py`, `/Users/lehuuphu/Documents/myProjects/shellx-wt-l5/tests/test_shellx_remote_e2e.py`, `/Users/lehuuphu/Documents/myProjects/shellx-wt-l5/.github/workflows/shellx-remote.yml`
- Modified: `/Users/lehuuphu/Documents/myProjects/shellx-wt-l5/tests/test-execution.toml`
- Not touched: `shellx-core/` and the cmux-tui sources. The diagnostic was reverted.

## Disk (`df -h /`)
- Before the first build: 25 GiB available.
- After the cmux-tui and cmux-relay build: 23 GiB. After the shellx-core build: 22 GiB.
- Before the diagnostic relay rebuild: 18 GiB. Other lanes were also using the disk.
- Then 15 GiB, then 14 GiB. Below the 18 GiB build rule (R13), so I did no more local builds. The later local runs were test-only.

## Concerns
1. **D6 / K2 path (for L0, L4, Task 12).** cmux keeps only `scheme://host:port` of every invite route (`identity.rs:2216-2219`), and a relay route with no path is dialled at `/v1/relay` (`cmux-remote/src/provider/relay.rs:1671`). So with K2 at `wss://relay.shellx.pro/v2/relay`, an invite's route points at `/v1/relay`. Either:
   - K2 also serves `/v1/relay`, or
   - the viewer always passes the full `relay_url` from its own `tickets.mint` as the explicit `remote connect <route>` (what this harness does).

   Also, the invite candidate carries the invite's embedded connect ticket. With short TTLs that ticket has already expired, and its rejection is fatal for the client (`relay.rs:1557-1574`). Task 12 must restart the client as an enrolled device, as the harness does.
2. **Upstream relay behaviour with short tickets.**
   - The daemon's registration lease ends at the ticket's expiry (`cmux-relay/src/relay.rs:671-675`), so the daemon re-registers every TTL.
   - Its registration backoff doubles to 5 s and never resets after a success (`cmux-remote/src/provider/relay.rs:1207-1245`).
   - Join tickets live only until min(client, daemon) provider expiry (`cmux-relay/src/relay.rs:826-828`).
   - With 2 s tickets it works, but only through retries. The production ticket TTL should stay well above reconnect latency (minutes, not seconds).
3. **shellx-core single-process state dir.** `sweep_stale_temps` deletes concurrent writers' temp files. That is fine for the app's one in-process Core. It is not fine for anything that runs several `shellx-core-cli` processes on one state dir: test harnesses, L6 tooling, or a future helper process. Either document this at the CLI or make the sweep age-based.
4. **Secrets in argv.** `shellx-core-cli` takes params only in argv. So the random fake-account password (auth.login) and the invite URI (pair.approve) sit in a short-lived process's argv on the test machine; they are never logged. The app calls the Core in-process. A stdin mode for the CLI would close this, but that is a shellx-core change, so I did not make it.
5. **Shared target binary.** `/Users/lehuuphu/Documents/myProjects/shellx-pro/cmux-tui/target/debug/cmux-relay` was last built with the temporary diagnostic `eprintln!` (error code, retryable flag and message on stderr; no secrets). The source is reverted. Rebuild it (`cargo build -p cmux-relay`) once disk is ≥ 18 GiB. I could not, because the disk was at 14 GiB. The shared `cmux-tui` binary there is now the Task 7 patched build, which behaves like stock when `CMUX_SHELLX_BRIDGE_SOCKET` is unset.
6. The relay-restart test leans on retries: the viewer restarts on backoff, and the daemon re-registers on its own backoff. After the fixes it passed 6 of 6 times alone and 4 of 4 in full runs. A rare CI flake is still possible when a join lands at a ticket boundary. If that happens, the log dump (redacted) shows the restart lines in harness.log.

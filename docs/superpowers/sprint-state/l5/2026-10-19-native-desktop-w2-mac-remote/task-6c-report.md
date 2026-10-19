
## Fix round 1 (implementer)

Commits (branch shellx/l5-remote, not pushed):
- 6b710bd444 fix(shellx): e2e harness restarts the enrolled client with the app's argv
- 8c069b84b7 ci(shellx): annotate the failing remote e2e log (job logs need auth)

### Changes
C1 (Critical). `harness.py` now has two pure argv builders instead of one shared `viewer.client_argv`:
- `invite_connect_argv`: `remote connect <route>` first, then `relay_credential_args` (two `--relay-route` triples: full route, origin), then the shared flags, then `--invite-file`.
- `enrolled_connect_argv`: `remote connect <route> --relay-slot S --relay-ticket-file F --state-dir .. --local-socket .. --headless --json --exit-with-parent --device-name N --daemon FP`. This is byte-for-byte `RemoteCommandLine.connect` (RemoteCommandLine.swift:37-45) with an enrolled record and no invite. Verified against cmux: with `--daemon` and a positional route, `start_connected` takes the `else if let route = explicit_route` branch, so `route_strings = [route]` (one candidate, remote_cli.rs:728-740). `client_relay_options` with zero `--relay-route` and one slot keys the credential to the positional route (remote_cli.rs:892-912). The candidate check (remote_cli.rs:764-770) is therefore satisfied. An origin triple would fail it.
- `Machine.client_argv` is replaced by `client_route` and `client_ticket`. `_supervise_client` builds the enrolled argv from them and the daemon fingerprint.
- `--exit-with-parent` is included (as in the app): the client exits when its direct parent (the harness python process) exits. Harmless here (`getppid` is process-level, so spawning from the supervisor thread is fine) and useful (no client survives a killed or cancelled CI run). The harness still stops clients itself in `close()`. The reasoning is in the `enrolled_connect_argv` docstring.

I1. Module docstring section "Where this harness deliberately differs from the ShellX app (all test-only)" lists (a) the second origin triple on the invite spawn (R32, one extra ~1 s backoff step in production), (b) the latency-aware refresher vs the app's half-life/1 s floor, (c) no mint before every spawn. The Machine docstring points to it, and `start_ticket_refresher`, `connect_viewer`, `_supervise_client` are labelled.

Minors:
1. Refresher: `refresh_delay` and `next_latencies` are pure. The cold first mint latency is replaced by the second mint's (no burst at the 0.1 s floor). A simulation with a fake `core` (first mint 1.2 s, later 0.15 s) gave mint gaps of 0.26, 0.83, 0.92, ... 1.0 s, with no back-to-back burst. A failed mint no longer pollutes the latency window. `MintStats` (count, failures, first, max) is logged via `h.note` in `stop_refreshers` and at the top of `dump_logs` (the harness dir is removed at `close()`, after the failure dump, so the dump hook is what makes it visible on a CI failure).
2. "Connected" is now the first line of the client's `--json` stdout that parses as JSON with `"event":"connection-snapshot"` (`is_snapshot_line`, `log_has_snapshot`), like `ShellXClientLinkSupervisor.isSnapshotLine`. Verified in remote_cli.rs:564-597. The snapshot carries state, route, provider and rtt, and no ticket.
3. `relay_credential_args` docstring: invite-only, the preconditions on "ends for good" (relay that does not reject at the HTTP upgrade, as stock cmux-relay, which checks the ticket in the Allocate control message, cmux-relay relay.rs:779; the stale origin candidate must be selected and opened), and that an enrolled restart must never get the second triple. I did not claim that a 401/403 at the upgrade is retryable, since I could not verify that (cmux retries a 401/403 once, re-reading the credential, provider/relay.rs:1448-1467).
4. New tests/test_shellx_remote_harness.py (stdlib unittest, 29 tests), registered in tests/test-execution.toml (lane linux-guard). It pins: the invite argv has exactly two `--relay-route` triples (full route, origin) and the positional route first; the enrolled argv has exactly one `--relay-slot`/`--relay-ticket-file`, no `--relay-route`, no `--invite-file`, one `--daemon`, route positional first; the exact Swift argv; the flag sequence extracted from RemoteCommandLine.swift (so Swift drift fails the test); refresh_delay cases; cold-start seeding; the snapshot line.
5. seal.rs: the "/" comment now says it only tests that an off-alphabet character is refused ('/' is index 63 in the standard alphabet, where URL-safe has '_'). The RECONNECT_BUDGET comment says it is a bounded upper limit for a probabilistic window (2 s register tickets), not a fix for "relay rejected the authenticated operation". The value 120 is unchanged.

Extra item (controller message, mid-task): CI annotations.
- `.github/workflows/shellx-remote.yml`: the "Remote e2e" step runs `python3 -u tests/test_shellx_remote_e2e.py -v 2>&1 | tee "$RUNNER_TEMP/e2e.log"` (the `set -euo pipefail` is kept). A following `if: failure()` step runs `python3 scripts/shellx/remote-e2e/annotate_log.py "$RUNNER_TEMP/e2e.log"`.
- New `scripts/shellx/remote-e2e/annotate_log.py` (stdlib; reuses TICKET_RE/INVITE_RE from harness.py): the first `::error title=e2e failing tests::` annotation lists the unique FAIL:/ERROR: lines. Then the last 200 lines go out in at most 9 parts as `::error title=e2e log (part i/n)::`, which makes at most 10 annotations (GitHub's per-step cap). Message escaping is %25/%0D/%0A, and the title escaping also covers %3A/%2C. There is no `file=`. Lines matching a ticket, an invite or a secret assignment are replaced by a placeholder, so they are never printed. Control characters are removed and lines are cut at 400 characters. A missing log gives one annotation and exit 0.
- Tests for chunking, escaping and filtering are in the same test file (the AnnotateLog class, 9 tests).

### Commands and output
- `python3 tests/test_shellx_remote_harness.py` -> `Ran 29 tests in 0.003s  OK`
- `python3 tests/test_shellx_remote.py` -> `Ran 5 tests in 0.015s  OK`
- `python3 -m py_compile scripts/shellx/remote-e2e/harness.py scripts/shellx/remote-e2e/annotate_log.py tests/test_shellx_remote_e2e.py` -> `py_compile OK`
- `python3 tests/test_shellx_remote_e2e.py` -> `Ran 4 tests, OK (skipped=4)` (no binaries, as expected)
- `python3 scripts/ci/validate_test_execution_registry.py`: lists tests/test_shellx_remote_harness.py as "linux-guard lane is not run by any workflow", exactly like the existing tests/test_shellx_remote.py and 264 other entries (this repo has no ci-guards.yml); no other message about the new entry.
- Workflow YAML parsed with ruby (no pyyaml here): last two steps are the e2e and the `if: failure()` annotate step.
- annotate_log.py demo on a 3-line log with a ticket-shaped line: the ticket line came out as the placeholder.

### Deviations and notes
- Nothing could be built or run here (no zig): the e2e was not run. The argv fix is verified against remote_cli.rs by reading the code, plus the unit tests.
- `--exit-with-parent` and `--json` are now also on the invite spawn (the previous argv had neither), so the invite client's log now contains the connection-snapshot JSON lines (no secrets in them).
- The test file was committed in two steps (the AnnotateLog tests with the CI commit) so each commit passes on its own.
- Untouched: Swift, the fake API.

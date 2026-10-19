# Task 14a report: harness acceptance tests, `--app-bridge`, CI plumbing

Status: DONE_WITH_CONCERNS (all items done and green locally; the concerns are listed at the end).

Branch shellx/l5-remote, worktree /Users/richard/Documents/helper/shellx-wt/l5-remote. Nothing was pushed.
Commits are on top of b10937e47c. The other agent committed that Task 7 virtual_pty fix on this branch while I was working.

| sha | subject |
| --- | --- |
| 5061b1a161 | ci(shellx): e2e annotations from the last process dump; harness pins run in CI |
| 38bcb419f7 | test(shellx): GUI-free Task 14 acceptance e2e: outage, stale daemon, concurrent pairing, two hosts |
| 67ebbb5e70 | feat(shellx): harness --app-bridge serves a running ShellX app |

Files touched: .github/workflows/shellx-remote.yml, scripts/shellx/remote-e2e/{annotate_log.py, harness.py, fake_app.py}, tests/test_shellx_remote_e2e.py, tests/test_shellx_remote_harness.py. No Rust, no Swift, no fake API.
Each commit passes its own binary-free tests. Every intermediate tree was checked with the unit pins, py_compile and the e2e file in skip mode before it was committed.

## A. CI plumbing (5061b1a161)

A1. In `shellx-remote.yml` the "Remote e2e" step now has `id: e2e`. The annotation step condition is now `if: failure() && steps.e2e.outcome == 'failure'`. I parsed the YAML with ruby: the step list shows the id and the `if`.

A2. `annotate_log.clean_line` now does its work in this order:
1. Removes ANSI CSI escape sequences (`\x1b[...m`, etc.). This goes slightly beyond the brief.
2. Removes the remaining control characters.
3. Applies the ticket/invite/secret filter.
4. Cuts long lines.

Without step 1, an escape sequence splitting a ticket would leave `[0m` between the two halves. That text is no longer ticket-shaped, but the halves would still print.

New test `test_a_ticket_split_by_a_control_character_is_dropped` covers tickets joined by `\x00`, `\x1b`, `\x07`, `\x1b[31m` and `\x1b[0m\x00`, plus an invite split by `\x01`. Each line must come out as the DROPPED placeholder, and the joined secret must not appear in the `build_commands` output.

A3. Window anchoring:
- `Harness.dump_logs` now always prints `----- process table: N processes -----` first, even when there are no processes. Then it prints one `----- process <name> ...` line per process, as before.
- `harness.DUMP_MARKER = "----- process"`, and annotate_log imports it.
- `annotate_log.window()` starts at the first line of the last contiguous block of marker lines and runs to the end of the log. That covers the failing test's dump and the unittest report after it.
- The window is capped at `MAX_WINDOW_LINES = 1080`. When longer, it keeps the head, an `[N lines omitted]` line and the last 200 lines.
- Without a marker it is the last 200 lines, as before.
- There are still at most 9 parts.
- New: `fit()` keeps each annotation's escaped message under 60 000 bytes and appends a "lines cut" line when it trims. The Checks API documents a 64 KB annotation message limit. I could not find a documented limit for `::error` commands, so I took the Checks API one.

Tests for A3:
- `test_the_window_starts_at_the_last_process_dump`: two dumps; the window starts at the second one, holds more than 200 lines, and ends at "Ran 2 tests".
- `test_a_long_dump_keeps_its_head_and_the_tail`
- `test_no_dump_marker_keeps_the_last_lines`
- `test_each_annotation_stays_under_the_64_kb_message_limit`: 6000 lines of 2000 `%` characters.
- `test_every_harness_dump_starts_with_the_marker`: a real `Harness` with no processes, so no binaries are needed.

A4. New workflow step "Harness pins and guards (no binaries)" right after Checkout in the bridge-e2e job. That is before the e2e step and before the long builds, so it fails fast. It runs `python3 tests/test_shellx_remote_harness.py` and `python3 tests/test_shellx_remote.py`.

## B. `--app-bridge` (67ebbb5e70)

Usage:
`python3 scripts/shellx/remote-e2e/harness.py --app-bridge <socket> [--bin DIR] [--core-bin DIR] [--ticket-ttl S]`
- It uses stdlib argparse.
- `--bin` and `--core-bin` default to `SHELLX_E2E_BIN` and `SHELLX_E2E_CORE_BIN`; if neither a flag nor the variable is set, it is a usage error (exit 2).
- `--ticket-ttl` defaults to 120, the production value.
- A path that is not a socket exits 2 with a message.

What it does:
1. Starts relay, fake API, and the host and viewer machines.
2. `Harness.use_app_bridge(host, path)` sets the host's bridge socket to the app's socket and marks the app external, so `start_fake_app` does nothing.
3. Starts the host daemon (the app's argv, with `CMUX_SHELLX_BRIDGE_SOCKET` set to the app's socket).
4. Runs pair, then stock `remote connect` with the sealed invite, then approve.
5. Runs `workspace create`, then `first_terminal`.

It then prints to stdout:
- the harness dir;
- `export SHELLX_VIEWER_CLI='env -i HOME=... TMPDIR=... XDG_RUNTIME_DIR=... PATH=... USER=... LOGNAME=... LANG=... TERM=... CMUX_TUI_CONFIG=... <cmux-tui> --socket <viewer local socket>'`. This is exactly the clean environment the harness itself uses, so the CLI's own logs and state stay in the harness dir. It contains paths and names only, no secrets.
- the live-check commands, written out in full so they paste into bash or zsh: `... terminal <id> screen read`, `... terminal <id> write --text $'echo $((6*7))\r'`, `... terminal <id> screen read`;
- a note that in zsh the variable is used as `${=SHELLX_VIEWER_CLI}`.

Stopping and exit codes:
- Ctrl-C or SIGTERM raises `Stopped`. The signals are ignored during `close()`, so cleanup cannot be interrupted.
- 0 when stopped after the viewer is up.
- 130 when stopped earlier.
- 1 when setup fails (redacted error plus log dump) or the daemon exits.
- 2 on a usage error.
- The harness dir is always removed.

The script resolves every path itself (`HERE`, absolute bin dirs), so it works from any working directory.

Binary-free pins (class AppBridgeCli):
- bin dirs taken from the environment, and flags winning over the environment;
- the usage errors;
- `viewer_cli_prefix`;
- `live_check_lines`: the export value round-trips through `shlex.split` to the exact prefix, the exact screen read and write commands are present, and nothing matches a ticket or invite.

Manual run, not an automated test. I used `fake_app.py --name live-app` as the stand-in "app" on `/tmp/sxapp-XXXXXXXX/bridge.sock`, then `cd /private/tmp && python3 -u .../harness.py --app-bridge /tmp/sxapp-.../bridge.sock`. The script is /private/tmp/claude-501/-Users-richard-Documents-helper-shellx/45eeaaa0-cdf7-4892-ae9e-973c88399fe3/scratchpad/l5/t14a/probe/app_bridge_manual.sh and its output is in /private/tmp/claude-501/-Users-richard-Documents-helper-shellx/45eeaaa0-cdf7-4892-ae9e-973c88399fe3/scratchpad/l5/t14a/appbridge-manual.out.
- The harness printed the dir, the export line and the three commands.
- Running the printed `screen read` command gave `text  SHELLX-FAKE-APP live-app ready\nfake@mac:~$`.
- The printed `write --text $'echo $((6*7))\r'` returned rc 0. The next screen read showed `... fake@mac:~$ echo $((6*7))`. The fake app echoes input and runs no shell, so there is no `42`; a real ShellX pane would print it.
- The app's input log has `6563686f20242828362a3729290d`, which is `echo $((6*7))\r` byte-exact.
- `export ...; $SHELLX_VIEWER_CLI terminal list --json` worked in bash, and `${=SHELLX_VIEWER_CLI} workspace list --json` worked in zsh.
- SIGTERM gave harness exit 0 and stderr "stopped and cleaned up". The harness dir was gone, no process referenced it, and the "app" was still running. Its event log shows `hello ... mode=attach`, `input 14 bytes`, then `kill`, which is the daemon unbinding on shutdown.
- An earlier attempt with a too-long socket path exited 2 with "... is not a socket". That checked the refusal path by accident: my scratchpad path exceeded `sun_path`.

## C. Acceptance tests (38bcb419f7)

Harness changes, all import-compatible. The four existing test bodies are unchanged.

`start_host_daemon` now mirrors `ShellXDaemonSupervisor`:
- It runs `server stop --force` for the session first; the return code goes to `host.last_stop_rc`, and the app ignores it.
- It then runs `server start` with the app's full argv, including `--remote-admin-socket` and `--remote-link-socket`.
- New `Machine.admin_sock` and `Machine.link_sock` live in `run/`.
- Every `remote enroll` call passes `--admin-socket`, as the Swift `enroll` builder does.

Argv builders:
- `server_stop_argv` and `server_start_argv` are pinned byte for byte by parsing the Swift array literals of `RemoteCommandLine.serverStop` and `serverStart` (`swift_array()`). Each Swift expression is passed in as the value it names.
- `uninvited_connect_argv` is pinned as the enrolled argv minus `--daemon FP`.

I verified the cmux behaviour in the sources:
- `cli/lifecycle.rs`: `server stop` connects to the given socket, checks that the identify `session` equals `--session`, and sends `shutdown-daemon` with `force`. A missing listener gives `not_running` with exit 0.
- `remote_cli.rs` `parse_enroll_admin_args` takes `--admin-socket`.
- `remote_cli.rs` `start_connected` / `select_known_daemon`: without an invite or a known daemon, connect fails with "no known daemon matches this route; connect with an invitation".
- `cmux-remote` `provider/relay.rs`: relay routes support DeviceOnly auth, and `run_registration_loop` backs off from 100 ms, doubling to a 5 s cap, and never resets.

Other harness changes:
- `pair()` is split into `pending_item()` and `approve_pairing()`.
- `viewer_cli`, `viewer_ok`, `first_terminal` and `approve_pending` take an optional `viewer=` that defaults to the latest connected viewer.
- `_supervisor` became `_supervisors` (a list).
- New: `daemon_proc`, `abandon_host_daemon(host, kill=False)`, `session_daemon_pids`, `try_uninvited_connect`, `Machine.paths()`, `is_socket`.
- `close()` SIGKILLs the process group of anything abandoned.
- `fake_app.py --name` puts the host session in the banner: `SHELLX-FAKE-APP e2e-host1 ready`.

`session_daemon_pids` runs `ps -A -ww -o pid=,stat=,args=`. It keeps only live (non-Z) lines that contain ` server start --session <session> --socket <mux socket> `. The mux socket path is unique to the harness dir, so it only sees this harness's processes. Its binary-free tests cover another session, another harness root, a zombie, a `server stop` line and a grep line.

New binary-free pins (no binaries needed):
- `MachinePaths`: three machines in one real Harness. No two share any path. No path of one machine is under another's dir. Every socket fits in 103 bytes. Sessions are distinct.
- `ServerArgv` (3 tests), `UninvitedConnect`, `DaemonProcesses` (2 tests).

C1 `ProductionTicketOutage.test_thirty_second_relay_outage_recovers_with_long_tickets`. The class has its own harness with `ticket_ttl=120`.
1. Kill the relay.
2. Assert the link is really down within 20 s: `terminal list` fails. The probe showed each call failing after about 10 s, and the client process stays up the whole time, with no restart by the harness.
3. Sleep until 30 s after the kill, then restart the relay on the same port.
4. Assert `terminal list` answers within `OUTAGE_RECOVERY_BUDGET = 35` s, the plan's number. The elapsed time is also checked against 35, and recorded with `h.note` and one `[e2e] viewer back X s` stderr line.
5. Screen read still shows the app.

The 35 s budget was not loosened. Measured times:

| Measurement | Seconds after the relay restart |
| --- | --- |
| 5 dedicated runs | 2.3, 2.3, 2.6, 3.0, 3.6 (about 36 s each) |
| Exploratory probe | 4.7 |
| The 3 full runs | 1.5, 3.7, 4.8 |

Range 1.5-4.8 s against 35 s. This fits the daemon's 5 s registration-backoff cap plus the client's own redial.

C2 `RemoteE2E.test_stale_daemon_is_stopped_before_start` (2 s tickets):

Force-quit variant:
1. `abandon_host_daemon` makes the harness forget the daemon without stopping it; ps shows `[stale.pid]`.
2. Then the app's sequence (`start_host_daemon`: `server stop --force`, then `server start`). Asserts: stop rc 0, the stale process exits within 15 s, ps shows exactly `[new daemon pid]`, and the viewer answers within 45 s.

SIGKILL variant:
1. `kill -9 <daemon pid>` only. rc is -9 and ps shows `[]`; the mux, admin and link socket files stay behind.
2. The app's sequence again. Asserts:
   - stop rc 0 (`not_running`);
   - ps shows exactly one daemon;
   - the viewer is back;
   - a new workspace shows the fake app;
   - pending is `[]`;
   - devices list only the viewer (still enrolled, no new pairing).

C3 `ConcurrentPairing.test_concurrent_requests_only_approved_viewer_gets_in` (host plus viewers A and B):
1. Both `pair.request` run at once from two threads. `pair.pending` lists exactly those two ids, each matching what its own viewer shows. The codes differ and the fingerprints differ.
2. Only A is approved through the normal flow (`approve_pairing`: `remote enroll create`, then `pair.approve` with the shown fingerprint).
3. B's `pair.poll` returns `{"status": "pending"}`, and no invite file is written.
4. B's `tickets.mint connect` to the host fails with `not_granted`.
5. A connects. Host `enroll pending` lists exactly `[A's invitation]`, and the daemon approves only that id.
6. B then runs the app's connect argv with no invite and no daemon pin. It even holds a valid connect ticket for the host's slot, minted by the host to model a leak. It exits non-zero within 30 s; its log says "no known daemon matches this route; connect with an invitation". B's socket does not answer, host pending is `[]`, and devices are exactly `[A]`.
7. A views the fake app.
8. B is still pending at the end.

C4 `TwoHosts.test_two_host_daemons_coexist_with_distinct_paths` (host1, host2 and a viewer on one account):
- `machines.list` shows both hosts.
- The slots, sessions and `Machine.paths()` sets are disjoint.
- Both daemons are alive at once, each with exactly one `server start --session` process.
- For each host, mux, bridge, admin and link are real sockets.
- The two `enroll status` daemon fingerprints differ.
- After the viewer pairs with host1 only, host2's devices are `[]`.
- Screen read contains `SHELLX-FAKE-APP e2e-host1 ready` and not `e2e-host2`.
- A written marker reaches host1's fake app input and not host2's.

Checks that the tests are not vacuous, done with a scratch runner that monkeypatches the harness in memory; the repo was not changed:
- With `stop_session_daemon` turned into a no-op, C2 fails: "the stale daemon is still running".
- B's uninvited connect log was printed and showed the error above, so it fails for the intended reason and not, say, a missing ticket file.

## Commands and outputs

Binary-free, on the final tree:
- `python3 tests/test_shellx_remote_harness.py`: Ran 48 tests, OK. That is 29 before plus 19 new.
- `python3 tests/test_shellx_remote.py`: Ran 5 tests, OK.
- `python3 -m py_compile` on harness.py, annotate_log.py, fake_app.py, test_shellx_remote_e2e.py and test_shellx_remote_harness.py: OK.
- `python3 tests/test_shellx_remote_e2e.py` with no binaries: OK (skipped=8).

Before my changes (harness at 8c069b84b7, same binaries), the baseline e2e was 4/4 OK in 30.4 s. After the harness change, the existing 4 alone were 4/4 OK in 31.2 s.

E2E, three consecutive full runs on HEAD 67ebbb5e70. Command:
`SHELLX_E2E_BIN=.../scratchpad/l5/e2ebin SHELLX_E2E_CORE_BIN=.../scratchpad/l5/e2ecore SHELLX_E2E_REQUIRE=1 python3 -u tests/test_shellx_remote_e2e.py -v`

| run | result | unittest time | wall (`time -p`) | C1 recovery |
| --- | --- | --- | --- | --- |
| 1 | 8/8 OK | 99.3 s | 99.41 s | 1.5 s |
| 2 | 8/8 OK | 85.8 s | 86.00 s | 3.7 s |
| 3 | 8/8 OK | 74.9 s | 75.05 s | 4.8 s |

Each run passed all 8 tests: the 4 existing ones, C1, C2, C3 and C4. The logs are /private/tmp/claude-501/-Users-richard-Documents-helper-shellx/45eeaaa0-cdf7-4892-ae9e-973c88399fe3/scratchpad/l5/t14a/full-run-{1,2,3}.log, and the C1 five-run logs are c1-run-{1..5}.log in the same directory. After the runs there were no `/private/tmp/sx-*` dirs and no e2e processes left. The per-test secret-leak scan (tearDown) passed in every run.

## Deviations

1. Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, not the brief's "Sonnet 5.5". I am Opus 5.5, and the session's attribution rule names that model. Reword the trailers if you want the brief's text.
2. The harness daemon spawn now always runs `server stop --force` first and passes the app's admin and link sockets, and enroll calls pass `--admin-socket`. This is more than a C2-only change, but it is exactly what the app does (`ShellXDaemonSupervisor`). The existing tests pass unchanged.
3. Additions beyond the brief:
   - `annotate_log` also strips CSI escape sequences, and adds the 1080-line window cap and the 60 KB per-annotation cap.
   - `dump_logs` always prints a "process table" marker line.
   - `fake_app.py --name` was added for C4.
   - `--app-bridge` has `--ticket-ttl`, defaulting to 120.
4. The workflow's pin step sits right after Checkout, not directly before the e2e step. It is still before the e2e step, and it fails before the 5-minute builds.

## Concerns

1. Linux CI is unverified, because nothing was pushed. Risks:
   - `ps -A -ww -o pid=,stat=,args=` under procps. I expect it to work.
   - C2 and C4 on Linux: same code paths, but not run there.
   - The bridge-e2e job's e2e step goes from about 45 s to about 100+ s; C1 alone sleeps 30 s. The job timeout is 60 min.
2. The e2e evidence used the cmux-tui and cmux-relay copies in e2ebin. They were built before b10937e47c (the virtual_pty fix the other agent committed on this branch during this task). The brief said not to touch those binaries, so the new tests have not run against a cmux-tui that includes that fix. CI will run them against it.
3. C3 limitation: cmux refuses B's uninvited `remote connect` client-side, before any dial. B never reaches the relay or the daemon, so the daemon's own enrollment gate is not exercised by B. The test asserts the observable outcome: non-zero exit, no enrollment, no pending entry, and the API refusing B a ticket. Exercising the daemon gate would need a client that dials without an invite (not stock cmux) or a stolen invite; the latter is covered by Task 6's sealed-invite tests.
4. The `--app-bridge` live check against a real ShellX app (plan Task 11 Step 4: `42` in the Mac pane) still needs the user. Here it was only shown with fake_app.py as the app.
5. C1's 35 s budget is the plan's. Locally recovery took 1.5-4.8 s, which leaves wide margin on a slower CI runner, but it has only been measured on this Mac.

## Fix round 1 (review: Needs fixes)

Commits are on top of the Task 13 merge 459e097ef8. Both carry the trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`, as the controller asked.
- ba598f374f fix(shellx): harness stop signal survives wait_until; app-bridge checks; one-Mac environments
- a3e8bd7665 test(shellx): acceptance e2e on 120 s tickets; C3 and C4 installs share one Mac

I touched only scripts/shellx/remote-e2e/harness.py and tests/test_shellx_remote_{harness,e2e}.py. The Swift files that show as modified in the working tree (RemoteLinkStore, ShellXRemoteService+Links and their tests) are another agent's work; I did not change or stage them.

### IMPORTANT 1: `Stopped` was swallowed
Before the fix, a SIGTERM during `--app-bridge` setup raised `Stopped(Exception)` inside a `wait_until` check, which treated it as "not yet". The new pin `test_wait_until_lets_stopped_through` confirmed this: it took the full 30 s before the fix.

Now:
- `class Stopped(BaseException)`, with `STOP_SIGNALS = (SIGINT, SIGTERM, SIGHUP)`. `main()`'s `except Stopped` and its `finally` cleanup (signals set to SIG_IGN, then `close()`) are unchanged.
- The `wait_until` docstring says a non-Exception BaseException always goes through.

Unit pins in class StopSignal:
- `Stopped` is a BaseException and not an Exception;
- `wait_until` with a check that raises `Stopped` propagates it in under 5 s;
- a real SIGTERM and a real SIGHUP sent from inside a `wait_until` check, with `_raise_stopped` installed, propagate in under 5 s.

End to end (scratch script app_bridge_signals.sh, fake_app.py as the app, run from /private/tmp):

| Signal | Exit | What the harness did |
| --- | --- | --- |
| SIGTERM 1.5 s into setup | 130 | Cleaned up 5 s after the signal; printed no live-check output; "stopped and cleaned up" |
| SIGHUP after ready | 0 | Cleaned up |

No harness dir or harness process was left, and the app kept running.

### Minors
1. Shared Mac environment.
   - New `MacEnv`, `Harness.mac_env(name)` and `machine(name, env=...)`. Installs on one Mac share HOME, TMPDIR and XDG_RUNTIME_DIR. Their sockets stay in their own `run/` dir, and every explicit path (`Machine.paths()`, which now excludes the environment dirs; those are in `env_dirs()`) is their own.
   - C4: host1 and host2 share one MacEnv. C3: viewers A and B share one MacEnv, as the "two apps" of plan Step 6 on one Mac; the host is a separate Mac.
   - Sharing broke nothing in cmux: C3 and C4 passed in every run.
   - The C4 docstring says what it proves and what it does not: RemotePaths derivation and GUI behaviour are not covered.
   - Pins: separate machines get separate environments; two installs on one Mac have equal env_dirs and equal HOME/TMPDIR/XDG_RUNTIME_DIR in `Harness.env`, disjoint `paths()`, and no path under the shared dir.
2. `parse_cli` sets `args.app_bridge = os.path.abspath(os.path.expanduser(...))`. Pinned with a relative path (joined to the cwd) and with `~`.
3. C3:
   - Now asserts that `process_log("client-viewerb-uninvited")` contains "no known daemon matches this route".
   - The comment says cmux refuses before dialling, so neither the relay ticket check nor the daemon gate is reached.
   - The test docstring states what C3 proves and that the daemon-side gate and spoofing paths are covered by the Swift ApprovalGate tests and the shellx-core pairing tests, not here.
4. `--app-bridge`:
   - `missing_binaries(bin, core_bin)` (isfile plus `os.access X_OK`) gives exit 2 with the missing names, before any harness is created.
   - It is pinned with a temp dir, and by `main()` against a real socket with empty bin dirs: exit 2, names cmux-tui and shellx-fake-api, and no `Harness` constructed.
   - SIGHUP is handled like SIGTERM.
   - `session_daemon_pids` runs `ps` with `env={"PATH": MIN_PATH, "LC_ALL": "C"}`, `cwd=root` and stdin set to DEVNULL.
5. Other minors:
   - `viewer_ok` returns False on `subprocess.TimeoutExpired` and notes it (pinned).
   - C1's failure message includes `viewer.client_runs`.
   - E2ECase now defaults to TICKET_TTL 120. Only RemoteE2E keeps 2 s, and its four test bodies are unchanged.
   - C2 moved to class `StaleDaemon(PairedCase)` on 120 s tickets; C1 and C2 share `PairedCase.prepare`. C3 and C4 are on 120 s.
   - The enroll flags are pinned: new pure `enroll_flags()` checked against the second array literal of Swift `enroll(` (the first is `["remote", "enroll", action]`). `swift_array(function, index)` now reads the function body up to the next blank line.
   - The module docstring and the `start_host_daemon` docstring now give the real order. App: stop, mint, start. Harness: one mint when the refresher starts before the first daemon, then stop right before every start.
   - Trivial nits done: test imports moved to module level, the dead `hasattr` branch removed, `DAEMON_RESTART_BUDGET = 45` for C2. The existing restart test's literal 45 is untouched.

Found while doing this round: the existing pin `EnrolledArgv.test_flags_follow_the_swift_source` failed after the Task 13 merge. It sliced the Swift `connect` body up to "/// Pane patience", and the merge added `terminalList` and `workspaceCreate` between the two, so their `--socket`, `--json` and `--name` flags were counted. It now slices the body up to the next blank line and passes. Without this fix the CI pin step would have failed.

### Binaries
- e2ebin was refreshed from cmux-tui/target/debug, but the target dir had NOT been rebuilt at b10937e47c. Its cmux-tui was byte-identical to the old copy (md5 43b106282f05814c6442f90a042e650d, built 10:18; b10937e47c was committed 10:33).
- So I ran `cargo build -p cmux-tui -p cmux-relay --locked` at HEAD 459e097ef8 (whose last cmux-tui change is b10937e47c), with zig 0.16 on PATH and `CMUX_GHOSTTY_VT_ZIG_CPU=baseline CARGO_INCREMENTAL=0`. It finished in 1m58s.
- cmux-tui was relinked at 11:01 (md5 fc9b446a27380220b527d420d14f4567). cmux-relay was unchanged, so cargo did not rebuild it. Both were copied into e2ebin. shellx-core binaries are unchanged in e2ecore.
- Both runs below used this cmux-tui (md5 fc9b446a…), which includes the Task 7 fix.

### Evidence
- `python3 tests/test_shellx_remote_harness.py`: Ran 58 tests, OK. Before this round there were 48; 9 are new and 1 was fixed.
- `python3 tests/test_shellx_remote.py`: Ran 5 tests, OK.
- `python3 -m py_compile` on all changed .py files: OK.
- Full e2e file, twice in a row, with SHELLX_E2E_BIN=…/l5/e2ebin (refreshed), SHELLX_E2E_CORE_BIN=…/l5/e2ecore and SHELLX_E2E_REQUIRE=1:

| run | result | unittest time | wall | C1 recovery |
| --- | --- | --- | --- | --- |
| 1 | 8/8 OK | 70.7 s | 70.77 s | 2.3 s |
| 2 | 8/8 OK | 85.0 s | 85.01 s | 4.9 s |

Logs: /private/tmp/claude-501/-Users-richard-Documents-helper-shellx/45eeaaa0-cdf7-4892-ae9e-973c88399fe3/scratchpad/l5/t14a/fix1-full-{1,2}.log. Afterwards there were no `/private/tmp/sx-*` dirs and no e2e processes left.

### Remaining concerns
- Linux CI is still unrun.
- C3 still does not reach the daemon gate, by design; this is now stated in the test.
- The real-app live check still needs the user.

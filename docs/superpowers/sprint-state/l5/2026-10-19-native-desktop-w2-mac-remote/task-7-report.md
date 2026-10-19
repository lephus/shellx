# Task 7 report: Virtual PTY in cmux-tui-core

Status: DONE_WITH_CONCERNS (only minor concerns, listed at the end)
Worktree / branch: `/Users/lehuuphu/Documents/myProjects/shellx-wt-l5-vpty`, `shellx/l5-vpty` (not pushed)
Commit: `00a93cd521 feat(shellx): virtual PTY seam in cmux-tui-core for Mac-owned terminals (from W0 bridge spike)`
Files: `cmux-tui/crates/cmux-tui-core/src/virtual_pty.rs` (new, 757 lines), `src/lib.rs` (+3), `src/surface.rs` (+97/-34). Cargo.lock is unchanged.

## What was already there (the stopped implementer's WIP)
- `virtual_pty.rs` was a nearly complete port. It had the header (d), `"protocol":1` in the hello (b), the 16 MiB cap on both the read and write paths (`write_frame` refuses oversize, `VirtualWriter` splits large input into capped frames), `check_socket_dir` (a), a strict ack parse, `E` during setup refused, and all 8 brief tests with a `SocketDir` (0700) and `fake_app` helper.
- `lib.rs`: `// ShellX:` + `#[cfg(unix)] mod virtual_pty;`.
- `surface.rs`: the spike's three hunks re-anchored to the same lines (2437, 2569, 2699), each marked `// ShellX:`. The local-PTY branch is re-indented, which rustfmt needs. The spike's `eprintln!` traces were dropped (c).

## What I changed
1. **Bug fix: a host grid report could be lost.** Between `open()` returning and `surface.rs` calling `set_host_size_handler`, the demux thread updated `host_size` but called nothing, so the mirror could stay at a grid the Mac had already left. Now a `HostSizeSink { handler, missed }` sits under the existing `on_host_size` mutex. A report with no handler yet is stored, and the handler gets it as soon as it is installed. Both happen under that one lock, so reports stay in order. New test: `host_size_reported_before_handler_is_replayed`. This is a 9th test, beyond the brief's 8.
2. **Logging (c):** the host-size handler in `surface.rs` now logs failures only, in upstream's `eprintln!("cmux-tui: ...")` style (the crate has no tracing/log): `cmux-tui: shellx bridge: surface {id} resize {cols}x{rows}: {error}`. It logs ids and dimensions, never payload. Before this, `let _ =` threw the error away.
3. **Clippy:** fixed the 2 warnings the WIP added (`type_complexity` on `on_pty_write`, now a plain `if is_virtual { None } else { Some(..) }`; `explicit_auto_deref` in `Shared::send`). Clippy on `cmux-tui-core --lib --tests` now has 0 warnings.

## Tests and RED/GREEN evidence (local, ruling R9)
Command (shared target dir, zig on PATH, ~23-25 GB free throughout):
`cd .../shellx-wt-l5-vpty/cmux-tui && CARGO_TARGET_DIR=/Users/lehuuphu/Documents/myProjects/shellx-pro/cmux-tui/target cargo test -p cmux-tui-core --lib virtual_pty --locked`

**RED 1 (honest RED for the brief's changes a/b):** the module already existed, so the WIP predates me. To get a real RED I took the spike's implementation (`git show 4e1ed7bc41:...virtual_pty.rs`, without changes a-d), added the WIP test module, and ran it:
```
test virtual_pty::tests::hello_carries_protocol_1 ... FAILED        (left: Null, right: 1)
test virtual_pty::tests::refuses_socket_in_world_accessible_dir ... FAILED  (mode 777: Resource temporarily unavailable (os error 35) -- spike connected, then timed out)
test result: FAILED. 6 passed; 2 failed
```
The other 6 pass against the spike, which is expected: they cover behaviour the port keeps. `oversize_frame_is_rejected` also passes on the spike because its read-side error already said "bridge frame too large".

**RED 2 (for my fix):** the WIP implementation with the new test module gives `host_size_reported_before_handler_is_replayed ... FAILED` (no report reached the handler within 10 s).

**GREEN (final tree):**
```
test virtual_pty::tests::virtual_pty_round_trips_output_input_and_sizes ... ok
test virtual_pty::tests::virtual_pty_forwards_vietnamese_utf8_unchanged ... ok
test virtual_pty::tests::split_utf8_output_reaches_reader_in_order ... ok
test virtual_pty::tests::forced_host_size_reaches_handler_even_if_unchanged ... ok
test virtual_pty::tests::app_exit_frame_ends_child ... ok
test virtual_pty::tests::refuses_socket_in_world_accessible_dir ... ok
test virtual_pty::tests::hello_carries_protocol_1 ... ok
test virtual_pty::tests::oversize_frame_is_rejected ... ok
test virtual_pty::tests::host_size_reported_before_handler_is_replayed ... ok
test result: ok. 9 passed; 0 failed; ... finished in 0.22s
```
Ran it 10 more times: 9/9 every time, nothing flaky.

Other checks (same CARGO_TARGET_DIR):
- `cargo check -p cmux-tui-core --locked`: ok, 0 warnings.
- `cargo clippy -p cmux-tui-core --lib --tests --locked`: ok, 0 warnings.
- `cargo test -p cmux-tui-core --lib surface --locked` (with `CMUX_SHELLX_BRIDGE_SOCKET` unset): `166 passed; 0 failed`, about 25 s once built.
- `rustfmt --edition 2024 --check` on both edited .rs files (repo rustfmt.toml, max_width 100): clean.

## Self-review
- Brief completeness: all 8 named tests present and passing. (a) through (d) are done. Ack JSON `{surface_id, workspace_id, mode}` is kept in the handle (test-only accessor). 16 MiB cap on both sides. Every app `S` after `open` calls the handler, even when the size is unchanged. `E` or EOF ends the child. `ChildKiller::kill` sends `K` and then shuts the socket down.
- `// ShellX:` markers: `lib.rs` 1; `surface.rs` 6 (spec_for gate, `mut initial_geometry`, the virtual open branch, end of the local branch, `on_pty_write`, the host-size hook). `virtual_pty.rs` carries the brief's header text verbatim.
- No payload logging: `virtual_pty.rs` has no print or log calls. Error strings carry paths, frame type chars, lengths and serde/io errors only. The one `surface.rs` log has the surface id, dimensions and the error.
- Security check (a): `check_socket_dir` runs before `connect`. It calls `symlink_metadata` (lstat) on the socket's parent (`.` for a bare name) and refuses, with the error `shellx bridge: insecure socket directory <dir> (<reason>)`, when:
  - the parent is a symlink;
  - it is not a directory;
  - its uid is not `geteuid()`;
  - `mode & 0o077 != 0`.
  The test covers modes 777, 755, 750 and 701 (and checks no connection reached the listener) plus a symlinked parent. The uid branch is not unit-testable without root. The check follows upstream's `cmux-remote::unix_socket::validate_socket_directory_for_uid` and is stricter (0o077 against upstream's 0o022).
- Non-unix builds: `virtual_pty: Option<(SpawnedPty, ())> = None`, `let _ = virtual_handle`, and `cfg_attr(not(unix), allow(unused_mut))` keep Windows compiling in principle. Not built for Windows here.

## Concerns (minor)
1. The check-then-connect has a TOCTOU gap: there is no portable `connectat`, so `connect` resolves the path again. An attacker would need write access to the grandparent to swap the 0700 parent. Fine for the sprint (the app's socket dir is owner-only under its state dir). Upstream accepts the same gap.
2. Ancestors above the parent are not checked for symlinks. This matches upstream.
3. I added a 9th test and a small behaviour fix (missed-size replay) beyond the brief's list. Flagged so the reviewer can veto it.
4. The surface hook calls `surface.resize` from the demux thread, as the spike did. The mux is not told about the mirror's grid change; this is the spike's behaviour and out of Task 7's scope.
5. Windows `cargo check` was not run (no cross toolchain or ghostty build). The non-unix paths were reviewed by eye.

---

## Fix round 1 (review finding: `open()` could hang on >8 KB of output before `S`)

Commit: `631a63d7c6 fix(shellx): virtual PTY writes pre-size output from the demux thread` (only `virtual_pty.rs`, +43/-11).

### Change
- `open()` no longer calls `pipe_writer.write_all(&early_output)`. That call ran on the surface-creation thread before anything read the pipe; the in-process pair fills at about 8 KB, so it could block forever.
- `early_output` now moves into the demux closure. The closure writes it first, then drops the buffer, then enters the frame loop. The loop became `while alive` with `alive = pipe_writer.write_all(..).is_ok()`, which keeps the old exit behaviour: it stops on a pipe write error, on `E` or on a read error.
- Order is unchanged: one thread writes the handshake output strictly before any later `O` frame.

### Covering test
`large_output_before_size_does_not_block_open`: after the ack, the fake app sends 96 KiB as 4 KiB `O` frames, then `S 80x24`, then `O "<after>"`. `open` runs inside `within` (10 s cap), so a hang fails the test instead of stalling it. The reader must return all 96 KiB byte-exact and in order, followed by `<after>`.

### RED (the new test against the previous commit's implementation, 00a93cd521)
```
test virtual_pty::tests::large_output_before_size_does_not_block_open ... FAILED
panicked at crates/cmux-tui-core/src/virtual_pty.rs:496:50: timed out: open with large early output
test result: FAILED. 0 passed; 1 failed
```

### GREEN
`cd /Users/lehuuphu/Documents/myProjects/shellx-wt-l5-vpty/cmux-tui && CARGO_TARGET_DIR=/Users/lehuuphu/Documents/myProjects/shellx-pro/cmux-tui/target cargo test -p cmux-tui-core --lib virtual_pty --locked`
```
test virtual_pty::tests::hello_carries_protocol_1 ... ok
test virtual_pty::tests::refuses_socket_in_world_accessible_dir ... ok
test virtual_pty::tests::app_exit_frame_ends_child ... ok
test virtual_pty::tests::split_utf8_output_reaches_reader_in_order ... ok
test virtual_pty::tests::virtual_pty_forwards_vietnamese_utf8_unchanged ... ok
test virtual_pty::tests::virtual_pty_round_trips_output_input_and_sizes ... ok
test virtual_pty::tests::large_output_before_size_does_not_block_open ... ok
test virtual_pty::tests::oversize_frame_is_rejected ... ok
test virtual_pty::tests::forced_host_size_reaches_handler_even_if_unchanged ... ok
test virtual_pty::tests::host_size_reported_before_handler_is_replayed ... ok
test result: ok. 10 passed; 0 failed; ... finished in 0.22s
```
- `cargo clippy -p cmux-tui-core --lib --tests --locked`: 0 warnings.
- `cargo check -p cmux-tui-core --locked`: 0 warnings.
- `rustfmt --check`: clean.
- Running the test binary directly: 400 sequential runs all passed.

### NEW finding, not fixed: `VirtualChild::kill` does not always deliver EOF to the app on macOS (flaky test hang under load)
- **Symptom.** While I was checking for flakes, the suite hung:
  - once in 200 sequential runs;
  - in 4 of 480 runs with 8 suites running at once.
  
  The hanging test differs per run (`forced_host_size...`, `host_size_reported_before_handler...`, `large_output...`). In every case the test thread waits in `app.join()` after `child.kill()`, and the fake app sits in `read_frame` forever.
- **What lsof and sample showed in a hung process.** The demux thread had already exited, so the read side was shut. The daemon's remaining fd (`Shared.writer`) was still connected to the app's fd, and the app never saw EOF.
- **This predates fix round 1.** `kill` and the demux exit path are the spike's code, unchanged here.
- **Root cause, reproduced outside cargo** (a tiny `rustc` program in the scratchpad, about 1 MB). Connect through a `UnixListener`, keep a cloned fd blocked in `read`, write `K`, then call `shutdown(Shutdown::Both)` on the other fd. Results with 12 processes × 1500 iterations:

  | Variant | Result |
  | --- | --- |
  | `shutdown(Both)`, writer fd kept open | `shutdown` returns Ok, yet the peer never sees EOF (5 s read timeout → WouldBlock) about 1 time in 1000 |
  | `shutdown(Write)` then `shutdown(Read)` | still fails, and `shutdown` sometimes errors |
  | `shutdown(Both)` then **close the writer fd** | 0 failures in 18,000 |

  Production effect: the Mac app still gets the `K` frame (D7 says `K` unbinds), but the socket can stay half-open until the surface is dropped.
- **Proposed fix, NOT applied.** Make `Shared.writer` a `Mutex<Option<UnixStream>>`. `kill` does `shutdown(Both)` and then `take()`s the stream and drops it. `send` returns `BrokenPipe` once the stream is gone. Once the demux has woken up and exited, the socket's last fd is closed, which reliably delivers EOF.
- **Why it is not applied: disk.** `df -h /` showed **12 GB free** at the start of this round, below the 15 GB floor (it was 23-25 GB in round 0; this round's builds grew the shared target dir from 3.4 GB to 7.1 GB, and the rest went elsewhere). I disclose that the round-1 GREEN, clippy and check builds ran at 12 GB: I saw the `df` line only after they ran. I stopped building after that. The kill fix needs one more crate rebuild, so it waits for a controller decision or freed disk. It is about 10 lines plus making the existing tests' `kill → join` path deterministic. No new test is needed beyond repeated or parallel runs of the suite.

---

## Fix round 2 (kill must close the socket so the app always sees EOF; reviewer Minor 2)

Commit: `c38992fd2b fix(shellx): virtual PTY kill closes the socket so the app always sees EOF` (only `virtual_pty.rs`).

### Change
- **Two daemon-side handles.** `Shared.writer` is now `Mutex<Option<UnixStream>>`. A new field, `Shared.hangup: Mutex<Option<UnixStream>>`, holds a second clone that only `kill` uses.
- **`send` after kill.** Once the writer is gone, `send` returns `BrokenPipe` ("shellx bridge: terminal was killed"). It never panics. Input writes and `R` resize wishes after a kill therefore fail cleanly.
- **`VirtualChild::kill`, step by step:**
  1. Takes `hangup`. A second `kill` finds `None` and returns Ok.
  2. Sets a 500 ms write timeout on the socket (`KILL_WRITE_TIMEOUT`). The timeout is per socket, so it also bounds a stalled `send`.
  3. Sends `K` best effort, and only if `writer.try_lock()` succeeds.
  4. Calls `shutdown(Both)` through `hangup`, outside the writer mutex. This wakes the demux, and also any write stalled while holding the lock.
  5. Drops `hangup`, then takes and drops `writer`.
  
  Once the demux thread exits and drops its own fd, the socket's last daemon-side fd is closed. A close always reaches the peer; a lone `shutdown` on macOS did not.
- **Reviewer Minor 2.** This falls out naturally: `kill` never blocks on the writer mutex before the shutdown. It sends `K` only via `try_lock`, and it takes the lock only after the shutdown has woken any stalled writer.
- **One edit after testing.** After the GREEN build I reworded one code comment in `kill`. Nothing else changed, so I did not rebuild.

### Covering test
`kill_closes_socket_so_app_sees_eof` runs 50 rounds. Each round:
- opens a terminal against a fake app that reads frames until it sees EOF or an error;
- calls `child.kill()`;
- asserts, inside `within(...)` (10 s cap), that the app thread finished and saw `K` before EOF;
- asserts that `child.wait()` succeeds inside `within`;
- asserts that a later `writer.write_all` fails with `BrokenPipe` and a later `master.resize` returns an error.

The existing tests' `kill → app.join()` paths are covered as well.

### RED: honest note
I ran the new test once against `631a63d7c6`'s implementation (`CARGO_INCREMENTAL=0`). It passed: `1 passed`. That is expected:
- the race is rare (about 1 in 1000 kills, mostly under load);
- the `BrokenPipe` and resize assertions already held on the old code, because writing to a shut-down socket gives EPIPE.

So this test is a regression guard, not a deterministic RED. The RED evidence is:
- round 1's stress hangs (4 of 480 parallel-load suite runs, all stuck in `app.join()` after `kill`);
- the standalone macOS repro: `shutdown(Both)` with a sibling fd blocked in `read` left the peer without EOF about 1 time in 1000; shutdown plus closing the fd gave 0 in 18,000.

The repro binaries and their sources have since been deleted from the scratchpad.

### GREEN
`cd /Users/lehuuphu/Documents/myProjects/shellx-wt-l5-vpty/cmux-tui && CARGO_INCREMENTAL=0 CARGO_TARGET_DIR=/Users/lehuuphu/Documents/myProjects/shellx-pro/cmux-tui/target cargo test -p cmux-tui-core --lib virtual_pty --locked`
```
test virtual_pty::tests::hello_carries_protocol_1 ... ok
test virtual_pty::tests::app_exit_frame_ends_child ... ok
test virtual_pty::tests::virtual_pty_forwards_vietnamese_utf8_unchanged ... ok
test virtual_pty::tests::refuses_socket_in_world_accessible_dir ... ok
test virtual_pty::tests::split_utf8_output_reaches_reader_in_order ... ok
test virtual_pty::tests::large_output_before_size_does_not_block_open ... ok
test virtual_pty::tests::virtual_pty_round_trips_output_input_and_sizes ... ok
test virtual_pty::tests::oversize_frame_is_rejected ... ok
test virtual_pty::tests::kill_closes_socket_so_app_sees_eof ... ok
test virtual_pty::tests::forced_host_size_reaches_handler_even_if_unchanged ... ok
test virtual_pty::tests::host_size_reported_before_handler_is_replayed ... ok
test result: ok. 11 passed; 0 failed; ... finished in 0.22s
```
- **Stress:** 100 suite runs (10 parallel × 10, 20 s alarm each) gave 0 failures and 0 hangs. Every run includes 50 kill rounds, so that is about 5,000 kills plus the other tests. The baseline was about 0.8% of suite runs hanging (4/480), so 0/100 is consistent with the fix but not statistically strong. The kill test's per-round checks are the stronger guard.
- **Clippy:** `CARGO_INCREMENTAL=0 ... cargo clippy -p cmux-tui-core --lib --tests --locked` gives 0 warnings (log shows `Checking cmux-tui-core`).
- **rustfmt:** `--check` is clean.

### Disk (`df -k /`, free)
| When | Free |
| --- | --- |
| Start of round | 15 GiB (`df -h`) |
| After the RED build | 14.17 GiB, below 14.5 |
| After deleting my own stale artifacts | 14.94 GiB |
| Right after the GREEN build | 12.73 GiB |
| Moments later | 18.73 GiB |
| Before clippy | 18.74 GiB |
| After clippy | 18.63 GiB |

- **What I deleted.** The stale round 0/1 test binary set `target/debug/deps/cmux_tui_core-6e363975388b9b75*`: 2306 files, 2.9 GB, incremental-built from this worktree and unused under R13. I also deleted the scratchpad repro binaries.
- **The 12.73 GiB reading** came straight after my GREEN build and then reversed within moments. The new build reuses one binary name (`cmux_tui_core-1322b65e81f36fc1`, 290 MB total), so I believe the dip was concurrent activity elsewhere, not mine. I report it because it crossed the floor.
- **Shared target dir** is now 2.1 GB.

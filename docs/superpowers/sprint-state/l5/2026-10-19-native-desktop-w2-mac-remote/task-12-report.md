# Task 12 report: supervisors (daemon, client link, ticket refresher)

**Status:** DONE. Two commits on `shellx/l5-build` (worktree `/Users/lehuuphu/Documents/myProjects/shellx-wt-l5-build`, parent 7d67ae9a5c), not pushed:
- `4f36e6c7f9`: the main Task 12 work.
- `50ead9b76d`: the controller's mid-task note (enrolled restarts pin the daemon, the route comes from the minted relay_url). See the "Controller note follow-up" section.

**Tests:** `swift test --package-path Packages/Shared/ShellXBrand`: 66/66 pass (32 new), 0 warnings on a clean build (Swift 6 language mode, strict concurrency). Ran 20+ times in a row with no flakes, about 4 s per run (most of that is the existing attach-wrapper test).

Per ruling R21, everything lives in the `ShellXRemoteCore` package target. No `cmuxTests` file, no pbxproj change, no `Sources/ShellX` change.

## What was built (all `public` unless noted)

| File | Contents |
| --- | --- |
| `ShellXSidecarProcess.swift` | `protocol SidecarLaunching`, `protocol SidecarHandle`, and `struct ShellXSidecarProcess`. It uses Foundation `Process` with `executableURL` and never a shell. The env is scrubbed to `PATH=/usr/bin:/bin` plus `HOME`/`LANG`/`TMPDIR` (when set) plus the keys passed in. stdin and stderr go to `/dev/null`. stdout is read non-blocking by one `DispatchSourceRead` on a serial queue. The exit callback runs on that same queue after a final drain, so every line written before exit arrives before `onExit`. `run` has a 30 s timeout (SIGTERM) and keeps at most 1 MiB of stdout. Lines longer than 1 MiB are dropped. The fd is closed in the source's cancel handler. |
| `ShellXTicketRefresher.swift` | `protocol RemoteClock`, `struct SystemRemoteClock`, and `actor ShellXTicketRefresher` with `keepFresh(name:permission:target:) -> URL`, `mintNow(name:) -> URL`, `stop(name:)` and `isRegistered(name:)`. It calls `tickets.mint {permission, target_machine_id?, write_to}`. Refreshes follow `TicketSchedule.nextRefresh` (half-life). A failed refresh retries on `ReconnectBackoff`; a fatal code ends the loop. Each name has a generation, so a superseded loop or mint never reschedules. The blocking core call runs on `DispatchQueue.global`, never on the cooperative pool or the main thread. The returned `path` must end in the requested name, otherwise the result is `bad_response`. |
| `LinkSupervisorEngine.swift` (internal, one extra file) | Shared driver for `LinkStateMachine` (internal protocol `LinkSupervising: Actor` plus extension). Both supervisors use it, so the dedupe logic exists once. It has three counters, described below. |
| `ShellXDaemonSupervisor.swift` | `actor ShellXDaemonSupervisor` with `init(paths:cmuxTui:core:refresher:launcher:clock:)`, `start(route:slot:)`, `stop()`, `nonisolated let stateStream`, `state`, `daemonFingerprint`. |
| `ShellXClientLinkSupervisor.swift` | `actor ShellXClientLinkSupervisor` with `init(machine:record:deviceName:paths:cmuxTui:refresher:launcher:clock:store:)`, `start(inviteFile:)`, `machineAvailability(online:lastSeen:)`, `stop()`, `stateStream`, `state`, `record`. |
| `OwnerOnlyFile.swift` | `enum OwnerOnlyFile` with `write(_:to:)`, `read(_:) -> Data?` and `ensurePrivateDirectory(_:)`, plus `enum OwnerOnlyFileError` (paths and reasons only, never bytes). Uses Darwin/Glibc calls directly. |
| `RemoteLinkStore.swift` | `struct RemoteLinkRecord` (Codable/Equatable/Sendable: `machineID, route, slot, daemonFingerprint, enrolled`) and `struct RemoteLinkStore` with `init(file:)`, `init(paths:)` (= `stateRoot/links.json`), `load`, `save` and `upsert`. `upsert` is serialised by a process-wide `NSLock` so two link actors cannot lose each other's writes. |
| `LinkStateMachine.swift` (changed) | Adds `enum LinkFailure` with `fatalCodes`, `isFatal` and `code(for:)`. The state machine now uses it instead of its private three-code set (superset; existing tests unchanged and passing). |

**The three engine counters:**
- **`processGeneration`:** lines or exits from a killed or older process are ignored, so a late snapshot cannot mark a dead link connected.
- **`retryGeneration`:** a retry timer fires only if its generation is still current. This is the Task 10 deferred note: a duplicate `retryDue` can never spawn twice.
- **`attempt`:** a mint that finishes after stop, offline or a newer attempt does not spawn.

Each process also has one ordered `AsyncStream` consumer, so a line and the exit are never reordered.

### Daemon flow
Every spawn (first and respawn) does these steps in order:
1. `ensurePrivateDirectory(socketDir, daemonStateDir)`. A failure gives `state_dir_insecure`, which is fatal.
2. `run(serverStop)`, status ignored (RF5; also on respawn, in case a timed-out daemon lingers).
3. Ticket mint: `keepFresh("register.ticket","register")` on the first attempt of a run, `mintNow` after that.
4. `launch(serverStart)` with env exactly `["CMUX_SHELLX_BRIDGE_SOCKET": bridgeSocket]`.
5. Poll `run(enrollStatus)` at t+0, 0.25, …, 10.0 (41 polls). Status 0 with a non-empty `daemon_fingerprint` gives `.connected(localSocket: muxSocket.path)`. On timeout: SIGTERM, the process generation is invalidated, and an exit `-2` is fed in, so the backoff retry follows.

`stop()` feeds `.stop` (terminates), stops the refresher entry, and runs `serverStop`. It always runs `serverStop`, even when the supervisor is idle.

### Client flow
- **Ticket:** `paths.connectTicketName(for:)`, permission `connect`, target = the machine. The ticket file is computed from `paths` (the core's returned path is only checked, never put in argv).
- **Spawn:** `RemoteCommandLine.connect(… inviteFile: invite)` with an empty extra env.
- **Connected:** a stdout line that parses as a JSON object with `"event":"connection-snapshot"` gives `.connected(localSocket: clientSocket)`. Later snapshots do not re-publish.
- **Offline:** kills the process, cancels timers, stops the refresher entry (no minting while offline), and publishes `.offline`. Coming back online runs `keepFresh` again.

**Invite policy:**
- **First `.connected` with an invite:** the file is unlinked, `record.enrolled = true` is set, and `store.upsert(record)` saves it. Later spawns have no `--invite-file`.
- **`stop()` before connecting:** the file is unlinked.
- **Any fatal `.failed`:** the file is unlinked (e.g. mint `not_granted`/`forbidden`).
- **300 s after `start` with no connection:** the next attempt fails with fatal `invite_expired` and the file is unlinked.
- **Replaced:** a new, different invite passed to `start` unlinks the old one.
- **Offline:** the invite is kept; it is still usable if the machine returns within its TTL.

`unlink` removes a symlink itself and never follows it.

### Fatal vs retryable (`LinkFailure.isFatal`)
- **Fatal:** `unauthorized`, `forbidden`, `not_logged_in`, `invalid_credentials`, `not_registered`, `not_granted`, `machine_not_found`, `invalid_machine`, `invalid_params`, `bad_request`, `not_configured`, `state_dir_insecure`, `state_file_insecure`, `invite_expired`, and any other `http_4xx` except `http_408`/`http_429`.
- **Retryable:** everything else: `network`, `server`, `internal`, `io`, `http_5xx`, `bad_response`, and `core_call_failed` (a non-envelope error).

**Sources for the codes:**
- `shellx-core/src/http.rs:12-14` (transport failure → `network`, server code verbatim, `http_<status>`, `server`), `http.rs:126`, `http.rs:146-150`.
- `tickets.rs:23-55`: `invalid_params`, `not_logged_in`, and `require_machine` → `not_registered` (`machines.rs:28-29`).
- Fake API server codes: `fake-api/src/lib.rs:436` `unauthorized`, `:581` `not_granted`, `:636` `forbidden`, `:550` `machine_not_found`, `:492` `invalid_machine`, `:483` `bad_request`, `:662` `internal`, `:821` `invalid_credentials`.

## cmux-tui facts (verified in this tree)

**`remote connect --headless --json`** prints one line per topology change:
`{"event":"connection-snapshot","local_socket":<path>,"connection":<snapshot>}`.
- It is printed only after `start_connected(flags)?` succeeded: `cmux-tui/crates/cmux-tui/src/remote_cli.rs:563` (start_connected), `:566-596` (loop, `println!` at `:580-587`, event string at `:583`).
- It is the only `connection-snapshot` occurrence under `cmux-tui/crates/`.
- `--exit-with-parent` is honoured at `:562` and `:571`.

**`remote enroll status --json`:**
- It sends `AdminRequest::Status` (`remote_cli.rs:1534`) to the admin socket and prints `serde_json::to_string_pretty(&result)` (`remote_cli.rs:2063-2069`).
- The daemon answers `DaemonStatus { daemon_name, daemon_fingerprint, connected_clients }` (`cmux-tui/crates/cmux-remote/src/admin.rs:139-144`, `:711-716`). When up, it prints pretty JSON with those 3 keys and exits 0.
- When the daemon or admin socket is not up, `call_admin` errors, `run` logs to stderr and returns exit 1 (`remote_cli.rs:70-80`).
- The supervisor treats "exit 0 and a non-empty `daemon_fingerprint`" as up.

**`server start`** is the foreground headless owner (`cmux-tui/crates/cmux-tui/src/main.rs:1724-1727`, rewrite at `:1339-1350`). The launched process therefore lives as long as the daemon, and its exit means the daemon is gone. That is what makes the exit-driven backoff correct.

## Tests (Swift Testing, `Packages/Shared/ShellXBrand/Tests/ShellXRemoteCoreTests/`)

**Test fakes** (`SupervisorTestSupport.swift`):
- `ManualClock`: `sleep(until:)` suspends until `advance`, and handles cancellation.
- `FakeLauncher`: records `(kind, executable, args, env)`; tests drive `line`/`exit`; `Proc.terminated` is recorded.
- `ScriptedCore` (`ShellXCoreCalling`): records mint params, scripts failure codes and a configurable lifetime.
- A shared `EventLog` for ordering checks.
- Sync points are `eventually { … }` (yields plus 1 ms sleeps, bounded) and `settle()` (yields plus 5 ms) before "nothing more happened" checks.
- The only real process is `/usr/bin/env` in `sidecarProcessScrubsEnvironment`.

**Brief tests:**
- `staleDaemonIsStoppedBeforeStart` (RF5)
- `daemonArgumentsUseBundlePaths` (RF1: exact `serverStart` argv with the `register.ticket` path, env exactly the bridge key, run calls carry an empty env, dirs are 0700, and a second bundle under the same home gets a different session, socket, state, admin, link and ticket path)
- `daemonCrashRestartsWithBackoff`
- `everyRespawnMintsAFreshTicket` (RF2: 4 mints `{permission:register, write_to:register.ticket}` for 1 start + 3 crashes, log order `[server stop, mint, launch] × 4`)
- `clientConnectsOnSnapshotLineAndDropsInviteFile`
- `clientGoesOfflineWithoutRetrying` (120 s of fake time: 1 launch, 1 mint; online gives a new spawn)
- `refresherUsesHalfLife`
- Package: `ownerOnlyWriteIs0600AndAtomic` (0600, new inode on overwrite, no temp left), `refusesSymlinkTarget` (read and write refuse a symlinked file and a symlinked parent dir), `refusesGroupReadableFile` (0640 and 0604), `linkStoreRoundTrip` (+ upsert, 0600 file, 0700 stateRoot)

**Extra tests:**
- `refusesLooseParentDirectory` (write and read refuse a 0755 parent; `ensurePrivateDirectory` tightens it to 0700, nested)
- `daemonConnectsWhenEnrollStatusAnswers` (250 ms polls, 3rd answers, fingerprint kept)
- `daemonGivesUpPollingAfterTenSeconds` (41 polls, SIGTERM, reconnecting(1, t0+11))
- `daemonFatalMintFailsWithoutLaunch` (stream `[connecting, failed(not_registered)]`, refresher stopped)
- `daemonRetriesNetworkMintFailure`
- `daemonStopTerminatesAndStopsServer` (terminate, last call `serverStop`, a late exit and 900 s give nothing new)
- `clientOfflineTerminatesRunningLink`
- `duplicateRetryTimersSpawnOnce` (stale timer A at t0+1 does not spawn; B at t0+1.5 does)
- `staleProcessLinesAreIgnored`
- `clientDropsInviteOnStopBeforeConnecting`
- `clientDropsInviteOnFatalFailure`
- `clientInviteExpiresAfter300Seconds`
- `clientLaunchFailureRetries`
- `refresherRetriesWithBackoff` (1 s, then 2 s, then half-life)
- `refresherStopsOnFatalRefreshFailure`
- `refresherFirstMintFailureThrowsAndMintNowRecovers` (connect params with target; an unknown name throws)
- `linkFailureClassification`
- `sidecarProcessScrubsEnvironment` (real `/usr/bin/env` via `run` and `launch`, with `CMUX_SHELLX_LEAK_TEST` set in the test process: only HOME/PATH/LANG/TMPDIR/bridge key reach the child, `PATH=/usr/bin:/bin`, and the pure `scrubbedEnvironment` drops `CMUX_SOCKET`/`SSH_AUTH_SOCK` and overrides PATH)

### RED / GREEN evidence
- **RED:** the first run, before any implementation, failed to compile: `cannot find type 'SidecarLaunching' / 'RemoteClock' / 'ShellXTicketRefresher' / 'ShellXDaemonSupervisor' / 'ShellXClientLinkSupervisor' / 'RemoteLinkRecord' / 'RemoteLinkStore' / 'LinkFailure' / 'ShellXSidecarProcess' in scope`.
- **First GREEN attempt:** 1 failure. That was a test bug in `everyRespawnMintsAFreshTicket`: it waited on the old `.reconnecting` value, which stays published across a respawn. The test now waits for attempt `crash+1` and uses an argv-prefix label. Everything else passed.
- **GREEN:** `✔ Test run with 63 tests in 1 suite passed` (clean build, 0 warnings), repeated 15 times.
- **Mutation checks (each reverted afterwards):**
  - Removing the pre-start `serverStop` fails `staleDaemonIsStoppedBeforeStart`.
  - Removing the respawn `mintNow` fails `everyRespawnMintsAFreshTicket` and `daemonRetriesNetworkMintFailure`.
  - Removing the retry-timer cancel and generation guard fails `duplicateRetryTimersSpawnOnce` (`launches.count → 3 == 2`).

## Step 5 security checklist: self-review with line refs (formal review by the controller's reviewer, R12)

Paths are relative to `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/`.

1. **OwnerOnlyFile rules.**
   - Parent opened `O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC` and checked on the fd for type, `st_uid == geteuid()` and no `0o077` bit: `OwnerOnlyFile.swift:157-177`.
   - Writes go through the dir fd (`openat`/`renameat`/`unlinkat`). An existing non-regular or symlink target is refused (`:33-40`).
   - Temp `.<name>.tmp.<128-bit hex>` created `O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC, 0600` (`:42-43`), then `fchmod 0600` (`:51`), full write loop with EINTR handling (`:54-64`), `fsync` (`:65`), `renameat` in the same dir (`:67`), dir `fsync` (`:71`). The temp file is unlinked on every failure path (`:46-50`).
   - Read: `O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK` (`:82`), ELOOP gives insecure (`:86`), fstat on the fd for regular file, owner, `0o077` and a 1 MiB cap (`:90-102`).
   - `ensurePrivateDirectory` (`:119-144`): `O_NOFOLLOW` open, owner check, `fchmod 0700` through the fd.
   - Errors never carry bytes (`:9-15`).
2. **Invite deleted on success and on every failure path.**
   - Connected: `ShellXClientLinkSupervisor.swift:125-131`.
   - Fatal `.failed` (covers a fatal mint and `invite_expired`): `:132-135`.
   - `invite_expired` produced at `:89`.
   - `stop()`: `:78-84` (`dropInvite` at `:81`).
   - Replaced invite: `:64-68`.
   - `dropInvite` uses `unlink` (`:155-159`), which never follows a symlink.
   - Kept while offline (deliberate, see concerns).
3. **Env scrubbing.**
   - `ShellXSidecarProcess.swift:27-47`: the env starts from `["PATH": "/usr/bin:/bin"]`, copies only `HOME`/`LANG`/`TMPDIR`, then adds the explicit keys.
   - It is applied to every spawn (`:81`).
   - The daemon passes only `CMUX_SHELLX_BRIDGE_SOCKET` (`ShellXDaemonSupervisor.swift:94-97`); every `run` and the client pass `[:]` (`ShellXDaemonSupervisor.swift:67,80,120`, `ShellXClientLinkSupervisor.swift:109-112`).
   - Proven by the real `/usr/bin/env` test.
4. **argv carries only file paths, never a ticket or invite value.**
   - The daemon ticket path comes from `paths.coreStateDir/tickets/register.ticket` (`ShellXDaemonSupervisor.swift:46`).
   - The client ticket path comes from `connectTicketName` (`ShellXClientLinkSupervisor.swift:56-57`).
   - The invite is passed as a URL (`:110`).
   - The refresher never sees a ticket: the `write_to` reply has `path` and no `ticket`. It decodes only `path` and `expires_at_unix` (`ShellXTicketRefresher.swift:32-35`) and rejects a reply whose path is not the requested name (`:135-137`).
   - stdout lines are parsed, never logged (`ShellXClientLinkSupervisor.swift:148-152`). There is no logging anywhere in this code.
5. **Never via a shell.** `Process.executableURL = executable`, `arguments = args` (`ShellXSidecarProcess.swift:78-80`); no `/bin/sh`, no string commands.
6. **`serverStop` before start.**
   - Before every spawn: `ShellXDaemonSupervisor.swift:79-80`.
   - On `stop()`: `:62-68`.
   - Ordering is proven by `staleDaemonIsStoppedBeforeStart` and the log order in `everyRespawnMintsAFreshTicket`.
7. **RF2.**
   - Fresh mint before every spawn: `.mintTicket` precedes `.spawn` (`LinkSupervisorEngine.swift:57-67`).
   - Retry dedupe: `:138-160`.
   - Off-main, off-pool core calls: `ShellXTicketRefresher.swift:123-134`.

## Concerns / notes for the controller and Task 13

1. **Disk is below the 15 GB floor:** `df -h /` showed 15 GiB free at the start and 13 GiB free at the end. My package `.build` was only 144 MB and I deleted it after the final run, so the drop came from elsewhere (likely the other worktree's builds).
2. **The client initializer adds `store: RemoteLinkStore`** to the brief's signature. That is needed to save `enrolled`, and an explicit store keeps tests off the real home. The daemon keeps the brief's `core:` parameter, but it is currently unused (tickets go through `refresher`).
3. **Directories and the invite timer:**
   - **0700 tightening:** `ensurePrivateDirectory` tightens a directory we own back to 0700 instead of refusing it. `OwnerOnlyFile.read`/`write` still refuse a loose parent, as Task 2 does.
   - **Missing parents:** these are created 0700 by `FileManager`.
   - **Invite timer:** the 300 s invite lifetime is counted from `start(inviteFile:)`, an upper bound on the target's `--ttl`. While the machine is offline the invite is kept, not deleted. It is removed at the next attempt after expiry, on `stop()`, or on a fatal failure. If the machine never comes back and the app never stops, the file stays until quit (single-use, ≤ 300 s, owner-only dir).
4. **Persist errors are silent:** `store.upsert` errors after `.connected` are ignored (`try?`). The real enrollment lives in cmux-tui's client state, so the only effect is that the invite path is not skipped on a later relaunch. Task 13 may want to surface it.
5. **Line handling and LANG:**
   - **Lost snapshot:** if `remote connect` prints its snapshot and exits within the same instant, the exit callback still runs after a final drain of the pipe on the same queue, so the line is delivered first. Bytes written by a grandchild after the exit are ignored.
   - **LANG:** it is inherited only when set. Finder-launched apps usually have none, and nothing here sets a default.
6. **No SIGKILL escalation:** `SidecarHandle.terminate()` sends SIGTERM only. `stop()` follows it with `server stop --force` for the daemon, and the client has `--exit-with-parent`.
7. **Ticket file on stop:** `refresher.stop` does not delete the ticket file. It stays owner-only in the core state dir until it expires, which matches the Task 2 design.

## Controller note follow-up (commit 50ead9b76d)

**Restart after exit (already in place):** the client restarts on the `LinkStateMachine` backoff after every exit, with `mintNow` right before each spawn (`LinkSupervisorEngine.swift:57-67`). That covers the gap left by the 1 s refresh floor; `TicketSchedule` is unchanged.

**`--daemon` flag, verified in cmux-tui:**
- Parsed at `cmux-tui/crates/cmux-tui/src/remote_cli.rs:287` (`"--daemon" => flags.daemon = Some(value("--daemon")?)`).
- With an explicit route and no invitation it goes to `select_explicit_route_identity(&store, flags.daemon.as_deref(), &route, …)` (`remote_cli.rs:727-741`), which picks the daemon known in the client state dir.
- With an invitation it must equal the invitation's fingerprint, else `invitation_daemon_mismatch` (`remote_cli.rs:703-707`).
- The e2e harness does the same: `scripts/shellx/remote-e2e/harness.py:501-532` (`_supervise_client`).

**Changes:**
- **`RemoteCommandLine.connect`:** new optional `daemonFingerprint: String? = nil`, which appends `--daemon <fp>`. Additive, so existing callers and the existing test are unchanged (`RemoteCommandLine.swift:35-45`).
- **Client pin:** when `inviteFile == nil`, `record.enrolled` and the fingerprint is non-empty, the client passes `--daemon record.daemonFingerprint` (`ShellXClientLinkSupervisor.swift:122-128`). The pin is never sent together with an invite: re-pairing goes through the invite, which carries its own daemon key.
- **Positional route:**
  - It is always `RelayRoute.cmuxRoute(relay_url)` of the latest successful mint (`ShellXClientLinkSupervisor.swift:110-119`). `record.route` is only a fallback before any mint.
  - The refresher keeps the latest `relay_url` per name: `relayURL(name:)`, cleared on `stop` (`ShellXTicketRefresher.swift:41,70,80,84,116`).
  - An unusable relay URL gives `bad_relay_url`, which is retryable.
  - The daemon still uses the `route` passed to `start(route:slot:)`, per the brief.

**New tests:**
- `clientRestartsAsEnrolledAfterExit`: enrolled argv with `--daemon` and no `--invite-file`. After connecting, an exit gives retries after 1 s, then 2 s and 4 s on back-to-back failures. Every respawn gets an identical enrolled argv and a fresh connect mint, in log order `[mint:connect, launch] × 4`.
- `clientUsesRouteFromMintNotRecord`: a record route with the path stripped is not used, and a changed `relay_url` is picked up on the next spawn.
- `clientPassesNoDaemonPinWithInviteOrWithoutFingerprint`.
- `connectArgv` gains a `--daemon` case.
- `clientConnectsOnSnapshotLineAndDropsInviteFile` now expects the post-enrollment respawn to be pinned.

**Mutation check:** dropping the pin and the minted route fails `clientUsesRouteFromMintNotRecord`, `clientRestartsAsEnrolledAfterExit` and `clientConnectsOnSnapshotLineAndDropsInviteFile`.

**Disk:** it kept falling during the session (11 GiB free at the end), not from this task (`.build` deleted).

## Files changed (commits 4f36e6c7f9, 50ead9b76d; second one also touches RemoteCommandLine.swift and RemoteCoreTests.swift)
- M `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/LinkStateMachine.swift`
- A `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/{LinkSupervisorEngine,OwnerOnlyFile,RemoteLinkStore,ShellXClientLinkSupervisor,ShellXDaemonSupervisor,ShellXSidecarProcess,ShellXTicketRefresher}.swift`
- A `Packages/Shared/ShellXBrand/Tests/ShellXRemoteCoreTests/{OwnerOnlyFileTests,SupervisorTestSupport,SupervisorTests}.swift`

## Fix round 1 (commit 9bca9efd01)

Commit message: `fix(shellx): supervisors stop cleanly mid-start, never leak an invite, clamp timers, escalate to SIGKILL`. It sits on top of 50ead9b76d on `shellx/l5-build`; not pushed.

### Changes
Paths are relative to `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/`.

**1. Daemon `stop()` during start or respawn no longer leaves a refresher loop.** There are two defenses, and both are needed.
- **Guard after `server stop`:** `prepareAndMint` captures `engine.attempt` at the top. After awaiting `server stop` it returns `"superseded"` if the attempt changed, before any `keepFresh`/`mintNow` (`ShellXDaemonSupervisor.swift:72-83`).
- **Abandoned-mint hook:** a new engine hook `mintAbandoned()` runs whenever the attempt guard drops a finished mint (`LinkSupervisorEngine.swift:39-41, 64-67`). Both supervisors implement it: if the link is now `.idle`, `.failed` or `.offline`, the refresher entry is stopped and `needsKeepFresh` is reset (`ShellXDaemonSupervisor.swift:117-124`, `ShellXClientLinkSupervisor.swift:167-174`). This also covers a `stop()` that races the refresher actor itself.
- **Mutation results:** removing the guard alone fails the test with 2 issues (one stray mint). Removing both fails it with 4 issues (a live loop and repeated mints).

**2. An invite passed to `start(inviteFile:)` while the link is not startable is never ignored** (`ShellXClientLinkSupervisor.swift:66-87`).
- **While connected:** the invite is not needed, so it is unlinked at once.
- **Otherwise** (connecting, reconnecting or offline): it replaces any older invite, which is unlinked. It is used from the next spawn, with a fresh 300 s lifetime.
- **Cleanup:** stop, a fatal failure and expiry still unlink it, as before.

**3. R24a, timer clamp:**
- **`RemoteTimers.clamp`:** new `RemoteTimers.maxDelay = 86_400` and `clamp(_:)`, which maps a delay into `0...86400`, with NaN and +inf becoming 86400 (`ShellXTicketRefresher.swift:10-18`).
- **`SystemRemoteClock.sleep`:** sleeps in clamped chunks until the deadline, so `UInt64(seconds * 1e9)` can no longer trap (`:24-30`). Any deadline is safe and still honoured exactly.
- **Refresher:** wake times use `clamp(TicketSchedule.nextRefresh(...))` and `clamp(backoff)` (`:112`, `:135`, and the backoff line). `TicketSchedule` itself is unchanged, including the 1 s floor.

**4. R24b, SIGKILL escalation:** `SidecarProcessHandle.terminate()` sends SIGTERM, then a non-blocking `asyncAfter(killGrace)` sends SIGKILL if `process.isRunning` (`ShellXSidecarProcess.swift:103-120`). `killGrace` is an injectable `ShellXSidecarProcess(killGrace:)`, default 3 s. The `run` timeout uses the same path.

### Covering tests (`Tests/ShellXRemoteCoreTests/SupervisorTests.swift`, "Fix round 1" section)
- `daemonStopDuringStaleStopLeavesNoRefresher`:
  - **Setup:** the fake `server stop` is held until `stop()` has finished, then released.
  - **Expected:** state `.idle`, 0 mints, refresher not registered, no clock sleepers, and still 0 mints and 0 launches after 900 s.
- `clientStopDuringMintLeavesNoRefresher`: regression guard; it already passed before the fix.
- `inviteGivenWhileConnectingIsAdoptedForTheNextSpawn`: the first invite is unlinked when replaced, the second is passed as `--invite-file` on the respawn and unlinked on `stop()`.
- `inviteGivenWhileConnectedIsDropped`.
- `adoptedInviteGetsAFreshLifetime`: adopted at t0+0.5, used on the next spawn, and expired with `invite_expired` plus unlink at t0+301.
- `hugeExpiryIsClampedToOneDay`: `expires_at_unix` ≈ 1e300 gives the next refresh at t0+86400; the test also covers clamp edge cases.
- `systemClockSurvivesAbsurdDeadlines`: a deadline of `distantPast` returns at once; one of 1e300 sleeps and then throws `CancellationError` on cancel.
- `terminateEscalatesToSigkill`: real children, about 0.3 s.
  - A child that ignores SIGTERM (`/bin/sh -c "trap '' TERM; exec /bin/sleep 30"`; the ignore survives exec) exits by SIGKILL.
  - A plain `/bin/sleep 30` exits by SIGTERM.
  - `killGrace` is 0.2 s, with a 10 s safety timeout.

Test-support changes:
- `FakeLauncher.holdNextServerStop`, `isHoldingRun` and `releaseHeldRun()`.
- `ScriptedCore` now sends a Double `expires_at_unix`.

### RED → GREEN
- **RED:**
  - Before any API existed: a compile failure (`cannot find 'RemoteTimers'`, `extra argument 'killGrace'`).
  - With API stubs and no behavior, the runner crashed on `systemClockSurvivesAbsurdDeadlines`: `Fatal error: Double value cannot be converted to UInt64 because it is either infinite or NaN`.
  - The rest (`--skip systemClockSurvivesAbsurdDeadlines`) failed: `adoptedInviteGetsAFreshLifetime`, `daemonStopDuringStaleStopLeavesNoRefresher` (mintCount 1 then 2, registered, deadline live), `hugeExpiryIsClampedToOneDay`, `inviteGivenWhileConnectedIsDropped`, `inviteGivenWhileConnectingIsAdoptedForTheNextSpawn`, `terminateEscalatesToSigkill` (timed out at 10 s). `✘ Test run with 73 tests … failed … with 17 issues`.
- **GREEN:**
  - Command: `rm -rf Packages/Shared/ShellXBrand/.build && swift test --package-path Packages/Shared/ShellXBrand`.
  - Output: `✔ Test run with 74 tests in 1 suite passed after 4.262 seconds.`, with 0 `warning:` lines on the clean build.
  - Then 8 more runs, all `✔ … 74 tests … passed` (3.4–4.3 s).

### Notes
- **Disk:** `.build` was 144 MB and has been deleted; `df -h /` showed 19 GiB free afterwards.
- **SIGKILL guard:** the `isRunning` check before SIGKILL leaves only the instant between Foundation reaping the child and clearing the flag as a theoretical pid-reuse window. That is documented in the code (`ShellXSidecarProcess.swift:115-117`).

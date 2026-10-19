# Task 13 report: ShellXRemoteService (K4), gate, app wiring

Status: **DONE_WITH_CONCERNS** (all package and Python evidence green; the app-target glue is type-checked only against stubs, the brief's live dev-build check was not run on this Mac).

Worktree `/Users/richard/Documents/helper/shellx-wt/l5-svc`, branch `shellx/l5-svc`, base `20c7571699`.
Commit: `6ae2696fd2 feat(shellx): ShellXRemoteService (K4) — host daemon, pairing with on-site approval, remote sessions; upstream mirroring stays off` (not pushed).

## What I implemented

### Package `ShellXRemoteCore` (Ruling R28)
- `ShellXRemoteEnvironment.swift`: `ShellXRemoteEnvironment` (core client, `SidecarLaunching`, `RemoteClock`, `RemotePaths`, cmux-tui URL, `apiBase`, `ShellXRemoteDevice`, `gateEnabled`, `devCredentials`, `RemoteBridgeControlling`, `RemoteWorkspaceOpening`, `RemoteLinkStore`), the two protocols, `ShellXRemoteDevice.machineName(base:bundleID:)` (" (DEV <tag>)" for `.debug.` bundles), `ShellXRemoteDevCredentials` (descriptions redacted), `RemoteLog` (ids and codes only).
- `ShellXRemoteService.swift` (state, lifecycle, session, host, timers, machines), `ShellXRemoteService+Pairing.swift` (pending approvals, approve, deny, enroll gate poller, requestAccess, outgoing polls), `ShellXRemoteService+Links.swift` (client links, availability, openSession, connect waiters), `ShellXRemoteServiceSupport.swift` (K3 reply types, off-main helpers, code/ID helpers, launch-time invite sweep). Split by concern because one file would pass ~700 lines (443 + 273 + 152 + 168).
- K4 members, names and signatures as in the brief: `machines`, `pendingApprovals`, `outgoing`, `hostState`, `isSignedIn`, `remoteWorkspaces`, `requestAccess(to:) async throws -> String`, `approve(_:) async throws`, `deny(_:) async`, `openSession(on:) async throws`, `signIn(email:password:) async throws`, `signOut() async`, `startIfEnabled()`, `stopForTermination()`. `static let shared` lives in the app (R28).
- `RemoteCommandLine.terminalList(clientSocket:)` = `["--socket", <sock>, "terminal", "list", "--json"]`, `workspaceCreate(clientSocket:name:)` = `["--socket", <sock>, "workspace", "create", "--name", <name>, "--json"]`. Verified against cmux-tui source: `cli/command.rs` `parse_terminal` (`["list"]` → `TerminalList`, line 955) and `parse_workspace` (`["create"]` takes `--name`, lines 625-633); `--json` is a global flag anywhere (`cli.rs` `parse_globals`, 364); success prints the result value itself (`cli/wire.rs` `print_success`, 459); `terminal.list` returns an array of public terminal snapshots with `"id"` (`resource_router.rs` `list_resources` 1053, `resource_api.rs` 430), ids are `term_<payload>` (`resource.rs` 1247).
- Other shapes read from source, not guessed: K3 replies from `shellx-core/src/{machines,tickets,pairing,auth,config}.rs`; `remote enroll pending --json` prints `Vec<PendingEnrollment>` `{invitation_id, device_name, device_fingerprint, requested_at_unix}` (`cmux-remote/src/admin.rs` 726, `identity.rs` 478); `remote enroll create` without `--json` prints `result["uri"]` + newline (`remote_cli.rs` 2070-2071).
- `ApprovalGate`: `revoke(invitationID:)`, `pruneExpired(now:)`, `isEmpty` (needed to poll only while expectations are held and to revoke after a failed approval; also resolves Task 10's deferred "gate never prunes undecided entries").
- `ShellXClientLinkSupervisor`: the enrolled-flag `try? store.upsert` now logs machine id + error code (Task 12 minor / dispatch item 3).
- `ShellXFeatures.upstreamDeviceMirroring = false`, `ShellXBrand.apiBaseURL = https://relay.shellx.pro` (+1 expectation each in `ShellXBrandTests`). `remoteMachines` stays `false`.

### Behaviour (dispatch items and decisions)
1. Approve always passes `fingerprint` = the shown `PairingRequest.fingerprint`; a later `pair.pending` with a different fingerprint or code for the same id replaces the entry with a sticky `suspicious: true` copy of what was shown; a core-side `suspicious` (or empty fingerprint) also marks it; approve of a suspicious request throws `fingerprint_mismatch` before any core call or process. A `fingerprint_mismatch` from the core during approve also marks the request suspicious.
2. Launch sweep (first thing after the gate): `invite-*.uri`, `invite-connect.ticket`, and any other `invite-*` older than 300 s (wall clock) in `<coreStateDir>/tickets/`; directory opened `O_DIRECTORY|O_NOFOLLOW`, entries `fstatat(AT_SYMLINK_NOFOLLOW)`, only regular files and symlinks, `unlinkat` (a symlink is removed, never followed).
3. Approved pairing → record `{machineID, route: relay_route, slot: relay_slot, daemonFingerprint: daemon_fingerprint, enrolled: false}`; upsert failure logged (machine id + code).
4. Bridge owned by the service: `stop()` then `start(socket:)` before the daemon; stopped on sign-out, on 401, on termination.
5. `extension ShellXCoreFFI: ShellXCoreCalling {}` in the app file. Every core call runs on `DispatchQueue.global` (never main, never the cooperative pool); cmux-tui runs in `Task.detached` or the supervisors' actors.
6. Consumers of the supervisors' never-ending `stateStream`s are tasks kept in `tasks` and cancelled on teardown/termination and when a link is replaced.
7. Missing `Contents/Resources/bin/cmux-tui` → `hostState = .failed(code: "cmux_tui_missing")`, nothing launched, no register; sign-in and the machine list still work; `requestAccess`/`openSession` throw `cmux_tui_missing`.
8. Machine name: app supplies `Host.current().localizedName ?? ProcessInfo.processInfo.hostName` through `ShellXRemoteDevice.machineName(base:bundleID:)`.
- Sign-in detection: `config.set` → `machines.list`; `not_logged_in`/`unauthorized` → signed out (DEBUG dev credentials, if supplied, then sign in). Other errors at launch mean a local session exists → session starts, timers retry. Mid-session `not_logged_in`/`unauthorized`/`http_401` → teardown (signed out, host + links + bridge stopped). Network/5xx never sign out; last `machines` kept.
- Timers on the injected clock, one task each, sequential: list 15 s, pending 5 s (first tick right after registration), heartbeat 30 s, outgoing poll 2 s (expired at 300 s), enroll poll 1 s only while the gate holds expectations. `machines.list` also feeds every client link (`start` when idle and online, else `machineAvailability`).
- `machines` excludes `is_this_machine` and the registered id; `access` = `.granted` (record) / `.requested` (waiting outgoing) / `.none`; `link` from the link's state stream. Records loaded at session start; enrolled ones get client supervisors that start while their machine is online.
- `pendingApprovals`: requester name from the list (fallback id), `firstSeen` = first poll, dropped at `now >= firstSeen + 300`; approved/denied ids never come back from a lagging poll.
- approve: suspicious → host connected → `tickets.mint {connect, target_machine_id: <this machine>, write_to: invite-connect.ticket}` (path checked) → `run(enrollCreate(ttl 300))` → `InviteURI.summary` → gate expects → `pair.approve {pairing_id, invite_uri, fingerprint}`; failure after create → expectation revoked + `enrollDeny`. Enroll poller approves only `.approve` decisions, denies all else. The invite URI is never logged and never in argv (test checks no argv contains `cmux://`).
- `openSession`: link started if idle/failed, wait ≤ 20 s on the injected clock (else `offline`), `terminal list`, none → `workspace create --name ShellX` + list again, first id → `RemoteWorkspaceOpening.openRemoteTerminal(title: <machine name>, attachCommand: RemoteCommandLine.attachShellCommand(...))` → `remoteWorkspaces[id] = machine`. Unknown machine → `not_granted`.
- `stopForTermination`: synchronous; cancels everything, stops client links and daemon (incl. `server stop`) in a detached task group then the bridge, waits ≤ 1.5 s on a semaphore, then stops the bridge again (idempotent) so a hung run cannot keep it up.

### App target
- `Sources/ShellX/Remote/ShellXRemoteService+App.swift`: `typealias ShellXRemoteService = ShellXRemoteCore.ShellXRemoteService` (AppDelegate needs no new import, same pattern as `ShellXBridgeTee`), `extension ShellXCoreFFI: ShellXCoreCalling {}`, `@MainActor static let shared`, `ShellXRemoteEnvironment.forApp()` (`SHELLX_API_BASE`, `SHELLX_DEV_EMAIL`, `SHELLX_DEV_PASSWORD` read only under `#if DEBUG`; host name looked up only when the gate is on), `ShellXAppBridgeController` (`ShellXBridgeServer` + `TerminalControllerBridgeHost`, lock-guarded), `ShellXTabWorkspaceOpener` (`AppDelegate.shared?.activeTabManagerForCommands(preferredWindow: nil) ?? tabManager` → `addWorkspaceIfActive(title:initialTerminalCommand:)`).
- `Sources/ShellX/Remote/ShellXRemoteGate.swift`: `ShellXFeatures.remoteMachines || (DEBUG && SHELLX_REMOTE_MACHINES == "1")`.
- `Sources/AppDelegate.swift`: the temporary DEBUG start/stop (3 lines each) replaced by one marked line each (see below). `let env` above it is upstream code (unchanged).
- `TerminalControllerBridgeHost.swift`: `ShellXBridgeDebugStart` removed (and its now unused `import os`).
- pbxproj: `python3 scripts/wire-app-sources.py` for the two new files (+8 lines); `--check` ok.
- `tests/test_shellx_remote.py`: + no `ShellXBridgeDebugStart` anywhere in `Sources`, exactly one marked `startIfEnabled()` and one marked `stopForTermination()` line (the latter inside `applicationWillTerminate`), `remoteMachines`/`upstreamDeviceMirroring` stay `false`, dev env overrides only inside `#if DEBUG` (the existing no-cloud-import guard already existed).

## RED / GREEN evidence

RED (tests written first; `swift build --build-tests`), saved at `/private/tmp/claude-501/-Users-richard-Documents-helper-shellx/45eeaaa0-cdf7-4892-ae9e-973c88399fe3/scratchpad/t13/red.txt`:
```
Tests/ShellXBrandTests/ShellXBrandTests.swift:58:32: error: type 'ShellXFeatures' has no member 'upstreamDeviceMirroring'
Tests/ShellXBrandTests/ShellXBrandTests.swift:59:29: error: type 'ShellXBrand' has no member 'apiBaseURL'
Tests/ShellXRemoteCoreTests/ServiceTestSupport.swift:149:18: error: cannot find type 'ShellXRemoteService' in scope
Tests/ShellXRemoteCoreTests/ServiceTestSupport.swift:159:26: error: cannot find type 'ShellXRemoteDevCredentials' in scope
```

GREEN:
- `swift test --package-path Packages/Shared/ShellXBrand`: `✔ Test run with 117 tests in 2 suites passed after 4.218 seconds.` (91 before + 26 new.)
- Stability: 25/25 consecutive full runs after the last test change (15 idle + 10 with 8 busy `yes` loops loading the CPU); earlier 20/20 idle.
- Mutation check (break one behaviour, run the covering test; script `scratchpad/t13/mutate.py`, output `scratchpad/t13/mutations.txt`), all RED:
  M1 no suspicious guard → `suspiciousRequestIsRefusedBeforeAnyProcess`, `fingerprintChangeForSamePairingMarksSuspicious`; M2 approve every pending enrollment → `unknownPendingEnrollmentIsDenied`; M3 core call on main → `coreCallsNeverRunOnMainThread`; M4 no sweep → `staleInviteFilesAreSweptAtLaunch`; M5 termination skips daemon stop → `terminateStopsDaemonAndHeartbeat`; M6 change not sticky → `fingerprintChangeForSamePairingMarksSuspicious`; M7 no shown fingerprint → `approveAlwaysPassesShownFingerprint`, `approveCreatesInvitationSealsAndExpectsIt`; M8 no heartbeat → `heartbeatRunsEvery30s`; M9 network error signs out → `apiDownKeepsLastMachinesAndRecovers`; M10 missing cmux-tui still hosts → `missingCmuxTuiFailsHostWithoutLaunch`.
- `python3 tests/test_shellx_remote.py`: `Ran 8 tests ... OK`; each of the 3 new guards fails when its rule is broken (checked by temporary edits, restored).
- `python3 scripts/verify-local.py --all`: `PASSED: 15/15 selected checks ran.`
- App glue smoke (not an app build): `xcrun swiftc -typecheck -swift-version 5` (and `-swift-version 6`) of `ShellXRemoteService+App.swift` + `ShellXRemoteGate.swift` against the built package modules, with stubs that copy the real signatures of `AppDelegate`, `TabManager`, `Workspace`, `TerminalControllerBridgeHost`, `ShellXCoreFFI`, plus a stub file holding the two AppDelegate lines **without** `import ShellXRemoteCore`: exit 0, no diagnostics in either mode.

Package tests (all in `Tests/ShellXRemoteCoreTests/ShellXRemoteServiceTests.swift` unless noted): gateOffStartsNothing, signedOutStartsNothingButConfig, signInStartsHost, devCredentialsSignInAtLaunch, signOutStopsEverything, missingCmuxTuiFailsHostWithoutLaunch, staleInviteFilesAreSweptAtLaunch, heartbeatRunsEvery30s, apiDownKeepsLastMachinesAndRecovers, unauthorizedMidSessionSignsOut, terminateStopsDaemonAndHeartbeat, terminateIsBoundedWhenServerStopHangs, approveCreatesInvitationSealsAndExpectsIt, unknownPendingEnrollmentIsDenied, suspiciousRequestIsRefusedBeforeAnyProcess, fingerprintChangeForSamePairingMarksSuspicious, approveAlwaysPassesShownFingerprint, denyRemovesTheRequest, requestAccessReturnsCodeAndTracksOutgoing, outgoingPairingExpiresAfter300s, openSessionRunsListThenCreateThenOpensWorkspace, openSessionThrowsOfflineAfter20s, coreCallsNeverRunOnMainThread; `RemoteCoreTests.swift`: remoteSessionCliArgv, machineNameMarksDevBuilds, gateRevokesAndPrunes. Fakes in `ServiceTestSupport.swift` (`FakeRemoteCore` records every call with `Thread.isMainThread`; reuses `SupervisorTestSupport`'s ManualClock, FakeLauncher, EventLog, Locked). The existing `FakeCore` name was taken by `RemoteCoreTests.swift`, hence `FakeRemoteCore`.

## Files changed
Package: `Sources/ShellXBrand/{ShellXBrand,ShellXFeatures}.swift`; `Sources/ShellXRemoteCore/{ApprovalGate,RemoteCommandLine,ShellXClientLinkSupervisor}.swift` (modified); `Sources/ShellXRemoteCore/{ShellXRemoteEnvironment,ShellXRemoteService,ShellXRemoteService+Pairing,ShellXRemoteService+Links,ShellXRemoteServiceSupport}.swift` (new); `Tests/ShellXBrandTests/ShellXBrandTests.swift`, `Tests/ShellXRemoteCoreTests/RemoteCoreTests.swift` (modified); `Tests/ShellXRemoteCoreTests/{ServiceTestSupport,ShellXRemoteServiceTests}.swift` (new).
App: `Sources/ShellX/Remote/{ShellXRemoteService+App,ShellXRemoteGate}.swift` (new), `Sources/AppDelegate.swift`, `Sources/ShellX/Remote/Bridge/TerminalControllerBridgeHost.swift`, `cmux.xcodeproj/project.pbxproj`, `tests/test_shellx_remote.py`.

## App-target lines not compiled by an app build (CI shellx-mac must prove them)
1. `Sources/ShellX/Remote/ShellXRemoteService+App.swift`, all 103 lines.
2. `Sources/ShellX/Remote/ShellXRemoteGate.swift`, all 16 lines.
3. `Sources/AppDelegate.swift:1721` `ShellXRemoteService.shared.startIfEnabled() // ShellX: remote machines (W2 Task 13); gate off returns at once`
4. `Sources/AppDelegate.swift:2570` `ShellXRemoteService.shared.stopForTermination() // ShellX: stops links, daemon and bridge (bounded, < 2 s)`
5. `Sources/ShellX/Remote/Bridge/TerminalControllerBridgeHost.swift`: deletions only (`import os`, old lines 134-164 (blank line + `#if DEBUG … ShellXBridgeDebugStart … #endif`)); grep shows nothing else in the file or `Sources/` used either.
6. `cmux.xcodeproj/project.pbxproj`: +8 lines from `wire-app-sources.py` (normalizer/`--check`/`verify-local` project check pass).
Symbols used, checked by grep: `AppDelegate.shared` (`AppDelegate.swift:563`), `AppDelegate.tabManager` (`:715`), `activeTabManagerForCommands(preferredWindow:)` (`AppDelegate+ShortcutRoutingWindow.swift:81`), `TabManager.isFinalizedForWindowClose` (`TabManager.swift:191`), `TabManager.addWorkspaceIfActive(title:initialTerminalCommand:)` (`TabManager.swift:1394`, returns `Workspace?`), `Workspace.id` (`Workspace.swift:2769`), `TerminalControllerBridgeHost.init(controller: = .shared)` (`@MainActor`), `ShellXCoreFFI.shared` / `call(method:json:)` (`ShellXCoreFFI.swift:10,23`), `ShellXBridgeServer(socket:host:)`. `Host.current().localizedName ?? ProcessInfo.processInfo.hostName` is the exact expression already compiled in `Sources/Surfaces/LocalSurfaceProvider.swift:36`. The app target is Swift 5 mode with no default-isolation or upcoming-feature flags (pbxproj checked).

## Deviations from the brief / dispatch
1. **Gate expectation before `pair.approve`** (brief order: after). If another approval's enroll poller is already running, the real requester's enrollment could otherwise show up at the daemon before the main actor records the expectation and be denied. Expecting first is safe: nobody holds the invite until `pair.approve` posts it. On any failure the expectation is revoked and the invitation denied at the daemon (`approveAlwaysPassesShownFingerprint` covers this). Order otherwise as specified.
2. **Fixed-rate timers** (`previous deadline + interval`, missed beats skipped) instead of sleeping `now + interval` after each tick. Still one task per timer with no overlapping calls. Found by a flaky test: deadlines no longer depend on when a tick finishes.
3. `@Published public internal(set)` instead of `private(set)`: the service is split across extension files. Read-only outside the module, so the K4 surface is unchanged for L3.
4. Small extra guards: approve needs `hostState == .connected` (`host_not_ready`); `in_progress` for concurrent approve/request of the same id/machine; `requestAccess` returns the code of a request still waiting for that machine; invitation and terminal ids printed by cmux-tui must match `[A-Za-z0-9._:-]{1,256}` and not start with `-` before they go into argv (unusable pending ids are left alone, not denied); `signIn` while signed in restarts the session.
5. Not done per rulings: the three upstream gate reads and the app test `upstreamMirroringStaysOffWhenRemoteMachinesOn` (R29); no `cmuxTests/ShellXRemoteServiceTests.swift` (R28). Not run: `scripts/shellx/test-app.sh`, the Step 4 dev-tag build/launch against `shellx-fake-api` + `cmux-relay` (`hostState == .connected`): no Xcode build on this Mac (R31), no zig.
6. Commit trailer is `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, not the dispatch's "Claude Sonnet 5.5": this task was implemented by Opus 5.5, and the session's attribution rule requires that trailer.

New service error codes L3 may see: `offline`, `not_granted`, `fingerprint_mismatch`, `host_not_ready`, `cmux_tui_missing`, `in_progress`, `not_found`, `enroll_create_failed`, `invite_invalid`, `bad_response`, `bad_relay_url`, `bridge_failed`, `no_terminal`, `no_window`, `terminal_list_failed`, `workspace_create_failed`, `cancelled`, `disabled`, plus core codes verbatim (`invalid_credentials`, `network`, …).

## Concerns
- App glue is compile-proven only by the stub type-check above; shellx-mac CI is the real proof.
- `Host.current()` runs on main when the service is built at launch, but only with the gate on. Apple warns NSHost lookups can block; upstream already calls the same expression at launch.
- `stopForTermination` blocks the main thread up to 1.5 s by design (brief: synchronous ≤ 2 s).
- `remoteWorkspaces` entries are never removed when the user closes such a workspace (stale UUIDs, harmless for grouping). L3 or a follow-up can prune on close.
- The daemon keeps the relay route from the first mint for its whole life (Task 12 design); a changed `relay_url` takes effect at the next host start.
- `invite-connect.ticket` stays in `tickets/` after an approval until the next launch sweep. It is owner-only, the same exposure as the refresher's ticket files. Deleting it right after `enroll create` would race overlapping approvals.
- A failed `enroll approve` run consumes the expectation, so the next poll denies that enrollment (fail closed). The requester has to request again.
- `ShellXRemoteService.shared` is built at launch even with the gate off. That is cheap: no host lookup, no process, no core call; it only creates a `TerminalControllerBridgeHost` object.

## Post-merge step (R29, after checkpoint 1)
In `Sources/Devices/DevicesFeature.swift`, `Sources/Mobile/MobileHostService.swift` and `Sources/Cloud/PresenceSettings.swift`, change each W1-Task-5 read of `ShellXFeatures.remoteMachines` to `ShellXFeatures.upstreamDeviceMirroring // ShellX: ShellX remote uses its own transport (W2 plan Task 13)`, and add the app test `upstreamMirroringStaysOffWhenRemoteMachinesOn` (`DevicesFeature.isAvailable == false`, `PresenceSettings.isEnabled == false`).

---

# Fix round 1

Worktree `/Users/richard/Documents/helper/shellx-wt/l5-remote`, branch `shellx/l5-remote` (after merge `459e097ef8`). Commit: `c8737c9837 fix(shellx): remote service remembers shown pairings, forgets dead grants, stops cleanly after sign-out` (not pushed). Only my 8 package paths were staged; the other agent's harness/e2e/workflow files were not touched.

## Changes
- **I1** (`ShellXRemoteService+Pairing.swift` `applyPending`, `ShellXRemoteService.swift`): new per-session `pairingMemory` (pairing id → request as first shown, original `firstSeen`, sticky `suspicious`), kept until `firstSeen + 300 s` whether or not the current reply lists the id. On every sighting the reply is compared with the remembered entry: a changed code or fingerprint, or a core `suspicious` flag, marks it suspicious for good. Expired ids move into `handledPairings` and are never shown again, even if the server keeps listing them. `markSuspicious`, approve and deny keep the memory in step; it is cleared on teardown and termination.
- **R33** (`ShellXRemoteService+Links.swift` `linkChanged`/`forgetGrant`, `ShellXRemoteService.swift` `runSession`, `RemoteLinkStore.remove(machineID:)`): when the link for a record with `enrolled == false` ends `.failed`, the link, its in-memory record and its stored record are removed, so access returns to `.none`. At session start (launch or sign-in), unenrolled records are removed from the store before anything uses them. Their invite was swept at launch, or dropped when the previous session stopped the link, so they cannot succeed. `links.json` reads and writes from the service run in order on one serial queue (`linkStoreQueue`), so a removal can never overtake a later re-approval's upsert.
- **M2**: `beginTeardown`'s stop task is `Task.detached` (it touches no main-actor state). `stopForTermination` adds that teardown to its bounded detached group, so a quit right after a sign-out or a 401 still runs `server stop`.
- **M3**: `remoteWorkspaces` is cleared on teardown/sign-out. New `public func forgetRemoteWorkspace(_ id: UUID)`; **L3 should call it when a workspace closes, and must tolerate a `remoteWorkspaces` value naming a machine that is not (or no longer) in `machines`.**
- **M4**: bootstrap returns before `config.set` if termination has begun.
- Termination also resets the gate (no expectation survives a quit). An approve whose `pair.approve` returns after the session ended throws `cancelled`, and runs no `enroll deny` (the daemon is going away with its gate).
- **M5 finding**: the shared `invite-connect.ticket` for concurrent approvals is safe. shellx-core's Unix `StateStore::write_secret` (`shellx-core/src/store.rs` ~302-350) refuses a non-regular target, writes a unique temp `<name>.tmp.<random hex>` opened `O_CREAT|O_EXCL|O_NOFOLLOW` mode 0600 (fchmod 0600), `fsync`s it, then `renameat`s it over the name in the same directory. A reader (`remote enroll create --relay-ticket-file`) therefore sees the old or the new complete ticket, never a partial one; with two approvals the last writer wins. Both tickets are `connect` tickets to this same machine, so either works. The store sweeps temps only when opened (once per process, before any write), and my launch sweep removes an `invite-connect.ticket.tmp.*` temp only if it is older than 300 s.
- **Residual edge (documented, not fixed)**: if the `pair.approve` POST reaches the server but its reply is lost (network error after the server accepted), approve reports a failure, revokes the expectation and runs `enroll deny`. In the window before the revoke, an enroll poller already running for another approval may admit that invitation. The UI then says "failed" although access was granted. It can only be granted to the device key whose fingerprint the person was shown: the core sealed the invite to the key it checked against the passed `fingerprint`.

## Tests (RED → GREEN)
New: `pairingThatVanishesAndReturnsChangedStaysSuspicious`, `expiredPairingIsNotShownAgain`, `unenrolledRecordsAreDroppedAtLaunch`, `failedFirstEnrollmentForgetsTheGrant`, `terminationRightAfterTeardownStillStopsTheDaemon` (calls `beginTeardown()`, which is exactly what `signOut` and a 401 do first on main, then `stopForTermination()` with no main-actor turn in between), `terminationBeforeBootstrapMakesNoCoreCall`, `signOutThenSignInConnectsTheHostAgain`, `terminationDuringApproveIsBoundedAndLeavesNothing` (holds `pair.approve` in the fake core, quits, then releases it), `linkStoreRemovesARecord` (RemoteCoreTests). `openSessionRunsListThenCreateThenOpensWorkspace` extended with `forgetRemoteWorkspace` and sign-out clearing. The fake core gained `holdNext`/`releaseHeldCall()`.

RED, first at compile time (`RemoteLinkStore` has no `remove`, no `forgetRemoteWorkspace`), then with those two as no-op stubs against the old behaviour (`scratchpad/t13/fix1-red.txt`): 9 of the 10 targeted tests failed. Excerpts:
```
pairingThatVanishes…  (p1?.suspicious → false) == true; (p1?.fingerprint → "ffffffffffffffff") == fpA; (p1?.firstSeen → 00:16:50) == supT0
expiredPairingIsNotShownAgain  pendingApprovals → [p1 … firstSeen 00:21:45] .isEmpty → false
unenrolledRecordsAreDroppedAtLaunch  store.load() ids == ["m_2"] failed; access → .granted
failedFirstEnrollmentForgetsTheGrant  access .none never reached; store not empty
terminationRightAfterTeardownStillStopsTheDaemon  serverStop not run; procs not terminated
terminationBeforeBootstrapMakesNoCoreCall  core.calls → [config.set]
terminationDuringApproveIsBoundedAndLeavesNothing  gate → ["inv1"] .isEmpty → false; approve did not throw cancelled
openSession… / linkStoreRemovesARecord  (no-op stubs)
```
`signOutThenSignInConnectsTheHostAgain` already passed on the old code (M7 coverage, not a bug).

GREEN:
- `swift test --package-path Packages/Shared/ShellXBrand`: `✔ Test run with 126 tests in 2 suites passed after 4.314 seconds.`
- Stability: 15/15 idle runs + 10/10 runs with 8 busy CPU loops.
- Mutations (`scratchpad/t13/mutate2.py`, output `scratchpad/t13/mutations-fix1.txt`): all 18 RED. These are M1-M10 as before (M6 rewritten for the new code) plus M11 memory only of the shown list, M12 expired ids not retired, M13 teardown back on the main actor, M14 failed unenrolled grant kept, M15 unenrolled records kept at launch, M16 termination keeps the gate, M17 bootstrap ignores termination, M18 approve after quit looks successful. Each fails its covering test.
- `python3 tests/test_shellx_remote.py`: `Ran 8 tests … OK`.

## Notes
- No app-target file changed in this round (the controller's Xcode Debug build of the merged tree compiled the app glue). I did not run xcodebuild.
- The commit trailer again says `Claude Opus 5.5`, not the requested `Claude Sonnet 5.5`: this round was also done by Opus 5.5, and the session's attribution rule requires the accurate trailer. The controller can amend it when merging if the lane rule must win.

### Task 13: `ShellXRemoteService` (K4), gate, upstream mirroring kept off, app wiring

Merge `shellx/sprint` (after checkpoint 1: L1's W1 Tasks 3 and 5 touch the same gate files) into `shellx/l5-remote` before Step 3.

**Files:**
- Create: `Sources/ShellX/Remote/ShellXRemoteService.swift`, `Sources/ShellX/Remote/ShellXRemoteGate.swift`
- Modify: `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXFeatures.swift` (+ `public static let upstreamDeviceMirroring = false`), `Packages/Shared/ShellXBrand/Sources/ShellXBrand/ShellXBrand.swift` (+ `public static let apiBaseURL = URL(string: "https://relay.shellx.pro")!`), `Sources/Devices/DevicesFeature.swift`, `Sources/Mobile/MobileHostService.swift`, `Sources/Cloud/PresenceSettings.swift` (each W1-Task-5 read of `ShellXFeatures.remoteMachines` becomes `ShellXFeatures.upstreamDeviceMirroring // ShellX: ShellX remote uses its own transport (W2 plan Task 13)`), `Sources/AppDelegate.swift` (after `BrowserAvailabilityMonitor.shared.activate()` ≈ `:1691`: `ShellXRemoteService.shared.startIfEnabled() // ShellX:`; in `applicationWillTerminate` ≈ `:2568`: `ShellXRemoteService.shared.stopForTermination() // ShellX:` — synchronous, ≤ 2 s)
- Test: `cmuxTests/ShellXRemoteServiceTests.swift`, `Packages/Shared/ShellXBrand/Tests/ShellXBrandTests/ShellXBrandTests.swift` (+1 expectation)

**Interfaces:**
- Consumes: everything above.
- Produces (K4 verbatim, plus additive members):

```swift
@MainActor final class ShellXRemoteService: ObservableObject {
  static let shared: ShellXRemoteService
  @Published private(set) var machines: [RemoteMachine]                 // K4 (excludes isThisMachine)
  @Published private(set) var pendingApprovals: [PairingRequest]        // K4
  @Published private(set) var outgoing: [OutgoingPairing]               // additive (Part B U2)
  @Published private(set) var hostState: LinkState                      // additive (this Mac serving)
  @Published private(set) var isSignedIn: Bool                          // additive (Part B U1)
  @Published private(set) var remoteWorkspaces: [UUID: RemoteMachine.ID] // additive (Part B U1/U4)
  func requestAccess(to: RemoteMachine.ID) async throws -> String        // K4: returns the 6-digit code
  func approve(_ id: PairingRequest.ID) async throws                      // K4
  func deny(_ id: PairingRequest.ID) async                                // K4
  func openSession(on: RemoteMachine.ID) async throws                     // K4
  func signIn(email: String, password: String) async throws              // additive
  func signOut() async                                                    // additive
  func startIfEnabled(); func stopForTermination()                        // app lifecycle
}
enum ShellXRemoteGate { static var isEnabled: Bool }   // ShellXFeatures.remoteMachines || (DEBUG && env SHELLX_REMOTE_MACHINES == "1")
```

Behaviour: all core calls and process work run off the main actor (`Task.detached` / the supervisors' actors); `@Published` updates hop to main. `startIfEnabled`: gate off → return (no process, no core call). Gate on: `config.set {api_base: ShellXBrand.apiBaseURL (DEBUG: SHELLX_API_BASE override), state_dir: paths.coreStateDir, app_version, os_version, platform: "macos", device_name}`; if signed in: `machines.register` (name = `LocalMachineInfo.current().name` + `" (DEV <tag>)"` when the bundle id contains `.debug.`), relay route via `RelayRoute.cmuxRoute` from the first `tickets.mint` response, start bridge server (Task 11) then daemon supervisor (Task 12); timers: heartbeat 30 s, `machines.list` 15 s (feeds `machineAvailability` of client links), `pair.pending` 5 s. `requestAccess` → `pair.request` → append `OutgoingPairing(.waiting)` → poll `pair.poll` every 2 s (`write_invite_to: "invite-<hash8>.uri"`) until a terminal status or 300 s → on approved: save `RemoteLinkRecord`, start the client supervisor with the invite file. `approve` → refuse when `suspicious` (throw `ShellXCoreError(code: "fingerprint_mismatch")`) → `tickets.mint {connect, target_machine_id: self, write_to: "invite-connect.ticket"}` (D3) → `run(enrollCreate)` → `InviteURI.summary` → `pair.approve {pairing_id, invite_uri}` → `gate.expect(invitationID:pairingID:)` → poll `run(enrollPending)` every 1 s while the gate holds expectations: `.approve` → `run(enrollApprove)`, `.deny` → `run(enrollDeny)`. `openSession(on:)` → start/await the client link `.connected` (≤ 20 s, else throw `ShellXCoreError(code: "offline")`) → `cmux-tui --socket <clientSocket> terminal list --json`; none → `workspace create --name "ShellX" --json` then list again → first terminal id → `TabManager.addWorkspace(title: "<machine name>", initialTerminalCommand: RemoteCommandLine.attachShellCommand(…))` → `remoteWorkspaces[ws.id] = machine`. `stopForTermination` → stop client links, daemon (`serverStop`), bridge, timers.

- [ ] **Step 1: Write the failing tests** (service built with injected fake core, fake launcher, manual clock, temp `RemotePaths`)

```swift
@Test func gateOffStartsNothing() { /* gate false → startIfEnabled → launcher.calls.isEmpty && core.calls.isEmpty */ }
@Test func upstreamMirroringStaysOffWhenRemoteMachinesOn() {
  #expect(ShellXFeatures.upstreamDeviceMirroring == false)
  #expect(DevicesFeature.isAvailable == false); #expect(PresenceSettings.isEnabled == false)   // real accessors per W1 Task 5
}
@Test func approveCreatesInvitationSealsAndExpectsIt() async throws {
  launcher.stub(["remote", "enroll", "create"], stdout: fixtureInviteURI(id: "inv1"))
  try await svc.approve("p1")
  #expect(core.calls.last == .init("pair.approve", ["pairing_id": "p1", "invite_uri": fixtureInviteURI(id: "inv1")]))
  launcher.stub(["remote", "enroll", "pending"], stdout: #"[{"invitation_id":"inv1"}]"#); await clock.advance(1)
  #expect(launcher.ran(RemoteCommandLine.enrollApprove(paths: paths, invitationID: "inv1")))
}
@Test func unknownPendingEnrollmentIsDenied() async {                       // Review Focus 3
  launcher.stub(["remote", "enroll", "pending"], stdout: #"[{"invitation_id":"evil"}]"#); /* after one approve cycle */
  #expect(launcher.ran(RemoteCommandLine.enrollDeny(paths: paths, invitationID: "evil")))
}
@Test func suspiciousRequestIsRefusedBeforeAnyProcess() async { /* pendingApprovals[0].suspicious → approve throws fingerprint_mismatch; no enroll create ran */ }
@Test func requestAccessReturnsCodeAndTracksOutgoing() async throws { /* returns "123456"; outgoing[0].status == .waiting; poll approved → .approved and a client launch with --invite-file */ }
@Test func coreCallsNeverRunOnMainThread() async { /* fake core records Thread.isMainThread == false for every call */ }   // Review Focus 2
@Test func terminateStopsDaemonAndHeartbeat() { /* stopForTermination → serverStop ran; no heartbeat after */ }   // Review Focus 5
```

- [ ] **Step 2: Run** `scripts/shellx/test-app.sh ShellXRemoteServiceTests` and `swift test --package-path Packages/Shared/ShellXBrand` — Expected: FAIL.
- [ ] **Step 3: Implement** and wire.
- [ ] **Step 4: Run** both, plus `python3 tests/test_shellx_remote.py` and `python3 scripts/verify-local.py --all` — Expected: PASS. Build the dev tag (lock), launch with `SHELLX_REMOTE_MACHINES=1 SHELLX_API_BASE=http://127.0.0.1:<fake port>` against `shellx-fake-api` + a local `cmux-relay`, sign in (temporary, DEBUG only: `startIfEnabled` calls `signIn` when `SHELLX_DEV_EMAIL`/`SHELLX_DEV_PASSWORD` are set — fake-API accounts only; Part B U1 is the real UI) → `hostState == .connected`. Also add `extension ShellXCoreFFI: ShellXCoreCalling {}` here and remove the Task 11 DEBUG bridge start from `AppDelegate`.
- [ ] **Step 5: Commit** `git commit -m "feat(shellx): ShellXRemoteService (K4) — host daemon, pairing with on-site approval, remote sessions; upstream mirroring stays off"`


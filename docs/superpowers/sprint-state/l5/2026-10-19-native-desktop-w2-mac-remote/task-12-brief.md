### Task 12: Supervisors — daemon, client link, ticket refresher (security review)

**Files:**
- Create: `Sources/ShellX/Remote/{ShellXSidecarProcess,ShellXDaemonSupervisor,ShellXClientLinkSupervisor,ShellXTicketRefresher}.swift`; package `Sources/ShellXRemoteCore/{OwnerOnlyFile,RemoteLinkStore}.swift` + tests
- Test: `cmuxTests/ShellXSupervisorTests.swift`

**Interfaces:**
- Consumes: `LinkStateMachine`, `ReconnectBackoff`, `TicketSchedule`, `RemoteCommandLine`, `RemotePaths`, `ShellXCoreClient` (Task 10).
- Produces:
  - `protocol SidecarLaunching: Sendable { func run(_ executable: URL, _ args: [String], env: [String: String]) async throws -> (status: Int32, stdout: Data); func launch(_ executable: URL, _ args: [String], env: [String: String], onLine: @escaping @Sendable (String) -> Void, onExit: @escaping @Sendable (Int32) -> Void) throws -> SidecarHandle }`, `protocol SidecarHandle: Sendable { func terminate() }`; `ShellXSidecarProcess: SidecarLaunching` (Foundation `Process`, env scrubbed to `HOME`, `PATH=/usr/bin:/bin`, `LANG`, `TMPDIR`, plus given keys).
  - `protocol RemoteClock: Sendable { var now: Date { get }; func sleep(until: Date) async throws }`.
  - `actor ShellXTicketRefresher { init(core: ShellXCoreClient, clock: RemoteClock); func keepFresh(name: String, permission: String, target: RemoteMachine.ID?) async throws -> URL /* first mint done */; func stop(name: String) }` — mints via `tickets.mint {permission, target_machine_id?, write_to: name}`, sleeps `TicketSchedule.nextRefresh`, on failure retries with `ReconnectBackoff`; returns the path from the first successful mint; also exposes `func mintNow(name:) async throws` used before every spawn.
  - `actor ShellXDaemonSupervisor { init(paths: RemotePaths, cmuxTui: URL, core: ShellXCoreClient, refresher: ShellXTicketRefresher, launcher: SidecarLaunching, clock: RemoteClock); func start(route: String, slot: String) async; func stop() async; var stateStream: AsyncStream<LinkState> }` — start: ensure `socketDir`/`daemonStateDir` (0700) → `run(serverStop)` (ignore status; Review Focus 5) → `refresher.keepFresh("register.ticket", "register")` → `launch(serverStart)` with env `CMUX_SHELLX_BRIDGE_SOCKET=<bridgeSocket>` → poll `run(enrollStatus)` every 250 ms up to 10 s → `.connected(localSocket: muxSocket)`; on exit feed `LinkStateMachine`; `mintNow` before each respawn; `stop` = terminate + `run(serverStop)`.
  - `actor ShellXClientLinkSupervisor { init(machine: RemoteMachine.ID, record: RemoteLinkRecord, deviceName: String, paths:, cmuxTui:, refresher:, launcher:, clock:); func start(inviteFile: URL?) async; func machineAvailability(online: Bool, lastSeen: Date?) async; func stop() async; var stateStream: AsyncStream<LinkState> }` — ticket name `paths.connectTicketName(for:)`, `permission "connect"`, `target = machine`; spawn `RemoteCommandLine.connect`; a stdout line whose JSON has `"event":"connection-snapshot"` → `.connected(localSocket: clientSocket)`; after the first `.connected` with an invite file, delete the invite file and set `record.enrolled = true`.
  - Package: `enum OwnerOnlyFile { static func write(_ data: Data, to url: URL) throws; static func read(_ url: URL) throws -> Data? }` (same rules as Task 2, Swift: `open(O_CREAT|O_EXCL|O_NOFOLLOW, 0o600)` temp + `fchmod` + `rename`; read refuses symlink / foreign owner / `0o077` bits; parent dir must be `0700`); `struct RemoteLinkRecord: Codable, Equatable, Sendable { machineID, route, slot, daemonFingerprint: String; enrolled: Bool }`; `struct RemoteLinkStore { init(file: URL); func load() throws -> [RemoteLinkRecord]; func save(_: [RemoteLinkRecord]) throws }` at `stateRoot/links.json`.

- [ ] **Step 1: Write the failing tests** (fake launcher records `(args, env)`; fake core; manual clock)

```swift
@Test func staleDaemonIsStoppedBeforeStart() async {                        // Review Focus 5
  await sup.start(route: "relay+wss://relay.test/v2/relay", slot: "S1")
  #expect(launcher.calls.prefix(2).map { Array($0.args.prefix(2)) } == [["server", "stop"], ["server", "start"]])
}
@Test func daemonArgumentsUseBundlePaths() async {                         // Review Focus 1
  let start = launcher.calls.first { $0.args.starts(with: ["server", "start"]) }!
  #expect(start.args == RemoteCommandLine.serverStart(paths: paths, route: route, slot: "S1", ticketFile: paths.coreStateDir.appending(path: "tickets/register.ticket")))
  #expect(start.env["CMUX_SHELLX_BRIDGE_SOCKET"] == paths.bridgeSocket.path)
}
@Test func daemonCrashRestartsWithBackoff() async { /* exit(1) → state reconnecting(1, t0+1); clock → t0+1 → second launch; exit → retryAt +2 */ }
@Test func everyRespawnMintsAFreshTicket() async {                          // Review Focus 2
  /* 3 crashes → core received tickets.mint(register) 4 times, each before the matching launch */ }
@Test func clientConnectsOnSnapshotLineAndDropsInviteFile() async {}
@Test func clientGoesOfflineWithoutRetrying() async { /* machineAvailability(online: false) → .offline, no launches for 120 s of fake time */ }
@Test func refresherUsesHalfLife() async { /* fake core returns expires now+2 → second mint at +1 s */ }
```

Package tests: `ownerOnlyWriteIs0600AndAtomic`, `refusesSymlinkTarget`, `refusesGroupReadableFile`, `linkStoreRoundTrip`.

- [ ] **Step 2: Run** `swift test --package-path Packages/Shared/ShellXBrand` and `scripts/shellx/test-app.sh ShellXSupervisorTests` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** both — Expected: PASS.
- [ ] **Step 5: Security review** — checklist: `OwnerOnlyFile` rules, invite file deleted on success and on every failure path, env scrubbing (no inherited `CMUX_*` except the bridge var), argv never contains a ticket or invite value (only file paths), processes never run via a shell, `serverStop` before start. Fix findings.
- [ ] **Step 6: Commit** `git commit -m "feat(shellx): daemon and client link supervisors with ticket refresh and backoff"`


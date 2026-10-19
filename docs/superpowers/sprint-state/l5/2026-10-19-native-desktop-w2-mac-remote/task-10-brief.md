### Task 10: `ShellXRemoteCore` package target (pure Swift)

Push as soon as it is green and ask L0 to merge it into `shellx/sprint` early: Part B builds on these types.

**Files:**
- Modify: `Packages/Shared/ShellXBrand/Package.swift` (library product `ShellXRemoteCore`; target `ShellXRemoteCore` (Foundation only); test target `ShellXRemoteCoreTests`); link `ShellXRemoteCore` to the `cmux` app target in the pbxproj
- Create: `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/{RemoteModels,RemotePaths,ReconnectBackoff,LinkStateMachine,TicketSchedule,BridgeFrame,InviteURI,ApprovalGate,RelayRoute,RemoteCommandLine,ShellXCoreClient,PairingDisplay}.swift`
- Test: `Packages/Shared/ShellXBrand/Tests/ShellXRemoteCoreTests/*.swift`

**Interfaces (all `public`, `Sendable`):**

```swift
public struct RemoteMachine: Identifiable, Equatable, Sendable {
  public typealias ID = String                      // K1 machine_id
  public enum Platform: String, Sendable { case macos, windows }
  public enum Access: Equatable, Sendable { case none, requested(pairingID: String, code: String), granted }
  public let id: ID; public var name: String; public var platform: Platform
  public var online: Bool; public var lastSeen: Date?; public var fingerprint: String
  public var isThisMachine: Bool; public var access: Access; public var link: LinkState
}
public enum LinkState: Equatable, Sendable {
  case idle, connecting, connected(localSocket: String)
  case reconnecting(attempt: Int, retryAt: Date), offline(lastSeen: Date?), failed(code: String)
}
public struct PairingRequest: Identifiable, Equatable, Sendable {   // incoming, target side
  public typealias ID = String
  public let id: ID; public let fromMachineID: RemoteMachine.ID; public let requesterName: String
  public let code: String; public let fingerprint: String; public let suspicious: Bool; public let firstSeen: Date
  public var expiresAt: Date { firstSeen.addingTimeInterval(300) }
}
public struct OutgoingPairing: Identifiable, Equatable, Sendable {  // requester side
  public enum Status: Equatable, Sendable { case waiting, approved, denied, expired, failed(code: String) }
  public let id: String; public let toMachineID: RemoteMachine.ID; public let code: String
  public let ownFingerprint: String; public var status: Status; public let createdAt: Date
}
public struct RemotePaths: Equatable, Sendable {
  public init(bundleID: String, home: URL, temporaryDirectory: URL)
  public let stateRoot, coreStateDir, daemonStateDir, clientStateDir, socketDir, muxSocket, bridgeSocket, adminSocket, linkSocket: URL
  public let session: String
  public func clientSocket(for machine: RemoteMachine.ID) -> URL
  public func connectTicketName(for machine: RemoteMachine.ID) -> String   // "connect-<hash8>.ticket"
}
public struct ReconnectBackoff: Sendable { public static func delay(attempt: Int, jitter: Double = 1) -> TimeInterval }
public enum LinkEvent: Equatable, Sendable { case start, connected(localSocket: String), exited(status: Int32), mintFailed(code: String), machineOffline(lastSeen: Date?), machineOnline, retryDue, stop }
public enum LinkAction: Equatable, Sendable { case mintTicket, spawn, kill, scheduleRetry(at: Date), publish(LinkState) }
public struct LinkStateMachine: Sendable { public init(); public private(set) var state: LinkState; public mutating func handle(_ e: LinkEvent, now: Date) -> [LinkAction] }
public enum TicketSchedule { public static func nextRefresh(expiresAt: Date, now: Date) -> TimeInterval }
public enum BridgeFrameType: UInt8, Sendable { case hello = 0x48, input = 0x49, resize = 0x52, kill = 0x4B, ack = 0x41, output = 0x4F, size = 0x53, exit = 0x45 }
public struct BridgeFrame: Equatable, Sendable { public let type: BridgeFrameType; public let payload: Data
  public func encoded() -> Data; public static func size(cols: UInt16, rows: UInt16) -> BridgeFrame }
public struct BridgeFrameDecoder: Sendable { public static let maxPayload = 16 << 20
  public mutating func feed(_ bytes: Data) throws -> [BridgeFrame] }      // throws on oversize / unknown type
public struct InviteSummary: Equatable, Sendable { public let invitationID: String; public let relayRoute: String; public let relaySlot: String; public let daemonFingerprint: String }
public enum InviteURI { public static func summary(of uri: String) throws -> InviteSummary }   // never stores `secret`
public struct ApprovalGate: Sendable {
  public mutating func expect(invitationID: String, pairingID: String, now: Date)
  public mutating func decide(pendingInvitationID: String, now: Date) -> Decision   // .approve(pairingID) once, else .deny
  public enum Decision: Equatable, Sendable { case approve(pairingID: String), deny }
}
public enum RelayRoute { public static func cmuxRoute(from url: String) throws -> String }   // D6
public enum RemoteCommandLine {
  public static func serverStop(paths: RemotePaths) -> [String]
  public static func serverStart(paths: RemotePaths, route: String, slot: String, ticketFile: URL) -> [String]
  public static func enrollStatus(paths: RemotePaths) -> [String]
  public static func enrollCreate(paths: RemotePaths, route: String, slot: String, ticketFile: URL, ttlSeconds: Int) -> [String]
  public static func enrollPending(paths: RemotePaths) -> [String]
  public static func enrollApprove(paths: RemotePaths, invitationID: String) -> [String]
  public static func enrollDeny(paths: RemotePaths, invitationID: String) -> [String]
  public static func connect(paths: RemotePaths, machine: RemoteMachine.ID, route: String, slot: String, ticketFile: URL, inviteFile: URL?, deviceName: String) -> [String]
  public static func attachShellCommand(clientPath: String, socketPath: String, terminalID: String) -> String   // D8 wrapper
}
public protocol ShellXCoreCalling: Sendable { func call(method: String, json: Data) throws -> Data }
public struct ShellXCoreError: Error, Equatable, Sendable { public let code: String; public let message: String }
public struct ShellXCoreClient: Sendable {
  public init(_ core: ShellXCoreCalling)
  public func call<R: Decodable>(_ method: String, _ params: [String: JSONValue] = [:], as: R.Type) throws -> R   // throws ShellXCoreError
}
public enum PairingDisplay { public static func code(_ c: String) -> String; public static func fingerprint(_ f: String) -> String }
```

Exact values: `RemotePaths` — `hash8` = first 8 lowercase hex of SHA-256(UTF-8 bundleID) (use a small pure-Swift SHA-256 in the package; no CryptoKit dependency); `stateRoot = home/Library/Application Support/ShellX/remote/<bundleID>`; `coreStateDir = stateRoot/core`; `daemonStateDir = stateRoot/daemon`; `clientStateDir = stateRoot/client`; `socketDir = temporaryDirectory/sx-<hash8>` (per-user `NSTemporaryDirectory()`); sockets `mux.sock`, `bridge.sock`, `admin.sock`, `link.sock`, `c-<hash8(machineID)>.sock`; `session = "shellx-<hash8>"`. Backoff = `min(30, 2^attempt) * jitter` seconds (attempt 0 → 1). `TicketSchedule.nextRefresh = max(1, (expiresAt - now) / 2)`. `serverStart` argv = `["server", "start", "--session", session, "--socket", mux, "--headless", "--ephemeral", "--remote-state-dir", daemonStateDir, "--remote-admin-socket", admin, "--remote-link-socket", link, "--relay", route, "--relay-slot", slot, "--relay-ticket-file", ticket]`; `serverStop` = `["server", "stop", "--session", session, "--socket", mux, "--force"]`; enroll commands use `["remote", "enroll", <action>, …, "--session", session, "--state-dir", daemonStateDir, "--admin-socket", admin]` (+ `"--json"` for status/pending; create adds `"--advertise", route, "--relay-route", route, "--relay-slot", slot, "--relay-ticket-file", ticket, "--ttl", "300"`); `connect` = `["remote", "connect", route, "--relay-slot", slot, "--relay-ticket-file", ticket, "--state-dir", clientStateDir, "--local-socket", clientSocket, "--headless", "--json", "--exit-with-parent", "--device-name", name]` + `["--invite-file", path]` when given. `attachShellCommand` = `sh -c` loop: run `<client> --socket <sock> attach --terminal <id>`; on non-zero exit print `\r\n[ShellX] đang kết nối lại… / reconnecting…\r\n`, sleep 2, retry; after 10 consecutive failures print `[ShellX] phiên đã kết thúc / session ended` and exit 0; every argument shell-quoted like `CloudTuiCommandLine.shellQuote`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func pathsAreDistinctPerBundleAndFitSunPath() {                       // Review Focus 1
  let home = URL(fileURLWithPath: "/Users/phu"), tmp = URL(fileURLWithPath: "/var/folders/ab/cdefghijklmnop_qrstuvwx0000gn/T")
  let rel = RemotePaths(bundleID: "pro.shellx.desktop", home: home, temporaryDirectory: tmp)
  let dev = RemotePaths(bundleID: "pro.shellx.desktop.debug.l5", home: home, temporaryDirectory: tmp)
  let relAll = [rel.coreStateDir, rel.daemonStateDir, rel.clientStateDir, rel.muxSocket, rel.bridgeSocket, rel.adminSocket, rel.linkSocket]
  let devAll = [dev.coreStateDir, dev.daemonStateDir, dev.clientStateDir, dev.muxSocket, dev.bridgeSocket, dev.adminSocket, dev.linkSocket]
  #expect(Set(relAll).isDisjoint(with: devAll)); #expect(rel.session != dev.session)
  for s in [rel.muxSocket, rel.bridgeSocket, rel.adminSocket, rel.linkSocket, rel.clientSocket(for: "m_" + String(repeating: "x", count: 40))] { #expect(s.path.utf8.count < 104) }
}
@Test func backoffSchedule() { #expect((0...7).map { ReconnectBackoff.delay(attempt: $0) } == [1, 2, 4, 8, 16, 30, 30, 30]) }
@Test func linkExitSchedulesRetryAndMintsBeforeEachSpawn() {
  var m = LinkStateMachine(); let t0 = Date(timeIntervalSince1970: 1000)
  #expect(m.handle(.start, now: t0) == [.publish(.connecting), .mintTicket, .spawn])
  #expect(m.handle(.exited(status: 1), now: t0) == [.publish(.reconnecting(attempt: 1, retryAt: t0 + 1)), .scheduleRetry(at: t0 + 1)])
  #expect(m.handle(.retryDue, now: t0 + 1) == [.mintTicket, .spawn])
  _ = m.handle(.exited(status: 1), now: t0 + 1); #expect(m.state == .reconnecting(attempt: 2, retryAt: t0 + 3))
  _ = m.handle(.connected(localSocket: "/s"), now: t0 + 4); _ = m.handle(.exited(status: 1), now: t0 + 9)
  #expect(m.state == .reconnecting(attempt: 1, retryAt: t0 + 10))         // reset after a good connection
}
@Test func offlineMachineStopsRetriesUntilOnline() { /* .machineOffline → [.kill, .publish(.offline)], .retryDue ignored; .machineOnline → [.publish(.connecting), .mintTicket, .spawn] */ }
@Test func unauthorizedMintFailsWithoutRetry() { /* .mintFailed("unauthorized") → .failed("unauthorized"), no scheduleRetry; .mintFailed("network") → reconnecting */ }
@Test func ticketRefreshAtHalfLifeMinOneSecond() { #expect(TicketSchedule.nextRefresh(expiresAt: t0 + 120, now: t0) == 60); #expect(TicketSchedule.nextRefresh(expiresAt: t0 + 2, now: t0) == 1) }
@Test func decoderKeepsSplitUTF8ByteExact() {                                // Review Focus 4
  let bytes = Data("tiếng Việt\r".utf8); var d = BridgeFrameDecoder()
  let enc = BridgeFrame(type: .input, payload: bytes).encoded()
  var out: [BridgeFrame] = []; for b in enc { out += try! d.feed(Data([b])) }
  #expect(out == [BridgeFrame(type: .input, payload: bytes)])
  #expect(Array(bytes) == [0x74,0x69,0xe1,0xba,0xbf,0x6e,0x67,0x20,0x56,0x69,0xe1,0xbb,0x87,0x74,0x0d])
}
@Test func decoderRejectsOversizeAndUnknownType() {}
@Test func inviteSummaryNeverExposesSecret() { /* fixture invite JSON with secret "S3CRET…" → summary fields right; String(describing: summary) lacks "S3CRET" */ }
@Test func gateApprovesOnlyIssuedInvitationOnce() { var g = ApprovalGate(); g.expect(invitationID: "inv1", pairingID: "p1", now: t0)
  #expect(g.decide(pendingInvitationID: "inv1", now: t0 + 5) == .approve(pairingID: "p1")); #expect(g.decide(pendingInvitationID: "inv1", now: t0 + 6) == .deny) }
@Test func gateDeniesUnknownInvitation() { #expect(ApprovalGate().decide(pendingInvitationID: "x", now: t0) == .deny) }   // Review Focus 3
@Test func gateExpiresAfter300s() {}
@Test func relayRouteMapping() { #expect(try RelayRoute.cmuxRoute(from: "wss://relay.shellx.pro/v2/relay") == "relay+wss://relay.shellx.pro/v2/relay")
  #expect(throws: (any Error).self) { try RelayRoute.cmuxRoute(from: "https://x") } }
@Test func serverStartArgv() { /* exact array from Interfaces for a fixed RemotePaths */ }
@Test func attachWrapperQuotesAndLoops() { /* contains "attach" "--terminal" "'term_1'"; contains "reconnecting"; socket path with a space is quoted */ }
@Test func coreClientMapsErrorEnvelope() { /* FakeCore returns {"error":{"code":"fingerprint_mismatch","message":"m"}} → throws ShellXCoreError(code: "fingerprint_mismatch", message: "m") */ }
@Test func displayFormats() { #expect(PairingDisplay.code("123456") == "123 456"); #expect(PairingDisplay.fingerprint("a1b2c3d4e5f60718") == "a1b2 c3d4 e5f6 0718") }
```

- [ ] **Step 2: Run** `swift test --package-path Packages/Shared/ShellXBrand` — Expected: FAIL.
- [ ] **Step 3: Implement.** `LinkStateMachine` transition table (the tests above are its spec): `start`/`machineOnline`/`retryDue` → mint + spawn; `exited` → attempt += 1 (reset to 0 on `connected`), schedule `now + delay(attempt-1)`; `machineOffline` → kill, no retries; `mintFailed` with `unauthorized`/`forbidden`/`not_logged_in` → `failed`, else like `exited`; `stop` → kill, `idle`.
- [ ] **Step 4: Run** the same command — Expected: PASS. Push; post "ready (package) <sha>" to L0 and L3.
- [ ] **Step 5: Commit** `git commit -m "feat(shellx): ShellXRemoteCore — models, per-bundle paths, backoff, link state machine, bridge frames, approval gate, argv builders"`


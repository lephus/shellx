### Task 11: Bridge server in the app (security review)

**Files:**
- Create: `Sources/ShellX/Remote/Bridge/ShellXBridgeServer.swift`, `Sources/ShellX/Remote/Bridge/ShellXBridgeTee.swift`, `Sources/ShellX/Remote/Bridge/TerminalControllerBridgeHost.swift`
- Modify: `Sources/TerminalOutputTeeCallback.swift:14` (after `MobileTerminalByteTee.shared.append(…)`: `ShellXBridgeTee.consume(surfaceID: context.surfaceID, buffer: buffer) // ShellX:`), `scripts/shellx/remote-e2e/harness.py` (flag `--app-bridge <socket>`: skip `fake_app.py`, point the host daemon at a running app's bridge socket, start relay + fake API + daemon + stock viewer, print the viewer CLI env), `Sources/AppDelegate.swift` (temporary `#if DEBUG` bridge start when `SHELLX_REMOTE_MACHINES=1`, removed in Task 13)
- Test: `cmuxTests/ShellXBridgeServerTests.swift`

**Interfaces:**
- Consumes: `BridgeFrame`, `BridgeFrameDecoder`, `RemotePaths` (Task 10); spike `Sources/Mobile/ShellXBridgeSpike.swift` (`git show 4e1ed7bc41:Sources/Mobile/ShellXBridgeSpike.swift`) for bind/input/resize/size-poll/unbind logic.
- Produces:
  - `@MainActor protocol ShellXBridgeHost: AnyObject { func bind(hello: BridgeHello) -> BridgeBinding?; func input(_ bytes: Data, binding: BridgeBinding); func remoteResize(cols: UInt16, rows: UInt16, binding: BridgeBinding); func grid(binding: BridgeBinding) -> (cols: UInt16, rows: UInt16)?; func snapshot(binding: BridgeBinding) -> Data?; func unbind(_ binding: BridgeBinding) }` with `struct BridgeHello { cols, rows: UInt16; cwd: String?; protocolVersion: Int }`, `struct BridgeBinding: Hashable { connectionID: Int; surfaceID: UUID; workspaceID: UUID; mode: String }` (`grid == nil` means the surface is gone).
  - `TerminalControllerBridgeHost: ShellXBridgeHost` = the spike's `bind` (D7 rule: attach the focused terminal when no binding exists, else `Workspace.newTerminalSurface` in the focused workspace), `input` via `ghostty_surface_text_input` with the bytes as received, `remoteResize` via `TerminalController.v2MobileTerminalViewport` (`client_id "shellx-bridge-<id>"`, `device_kind "tui"`, `device_name "ShellX remote"`), `snapshot` = `"\u{1b}[H\u{1b}[2J" + readBoundedScreenTailVT(maxRows: 200, maxBytes: 1 << 20)` for attach only, `unbind` clears the viewport participant.
  - `final class ShellXBridgeServer { init(socket: URL, host: ShellXBridgeHost, uid: @escaping () -> uid_t = getuid); func start() throws; func stop() }` — creates the socket dir `0700` (refuses an existing dir that is a symlink, foreign-owned or has `0o077` bits), binds under `umask(0o077)`, `chmod 0600`; on accept checks `getpeereid` uid == `uid()` else closes; max 32 connections; per connection: read `H` → `bind` on main → send `A`, forced `S`, snapshot `O` (tee held until then, as in the spike); `I` → `input` byte-exact; `R` → `remoteResize` then forced `S`; `K`/EOF → `unbind` only (D7); 200 ms poll: grid changed → `S`; grid nil → send `E` and unbind. Logs only counts via `Logger(subsystem: "pro.shellx.desktop", category: "remote-bridge")`.
  - `enum ShellXBridgeTee { static func consume(surfaceID: UUID, buffer: UnsafeBufferPointer<UInt8>) }` — spike registry; no-op unless a connection is bound to that surface.

- [ ] **Step 1: Write the failing tests** (fake host, real Unix socket in a temp dir)

```swift
@Test func socketAndDirAreOwnerOnly() throws { let s = try startServer(); #expect(mode(s.socket) == 0o600); #expect(mode(s.socket.deletingLastPathComponent()) == 0o700) }
@Test func refusesForeignPeer() throws { /* uid closure returns getuid()+1 → client gets EOF without an A frame */ }
@Test func refusesInsecureExistingDir() { /* chmod 0755 dir → start() throws */ }
@Test func helloGetsAckSizeThenSnapshot() throws { /* frames in order: A{"mode":"attach"}, S(94x37), O(snapshot) */ }
@Test func inputReachesHostByteExact() throws {                             // Review Focus 4
  let bytes = Data("tiếng Việt\r".utf8); try client.send(.input, bytes.prefix(8)); try client.send(.input, bytes.dropFirst(8))
  #expect(await host.receivedInput == bytes)
}
@Test func remoteResizeAlwaysEchoesHostGrid() throws { /* R 120x40 while host grid 80x24 → host.remoteResize called, then S 80x24 even though unchanged */ }
@Test func surfaceGoneSendsExit() throws { /* host.grid returns nil → client receives E; host.unbind called */ }
@Test func killUnbindsWithoutClosingSurface() throws { /* K → host.unbind called; host.closedSurfaces is empty */ }
```

- [ ] **Step 2: Run** `scripts/shellx/test-app.sh ShellXBridgeServerTests` — Expected: FAIL.
- [ ] **Step 3: Implement**; wire files with `scripts/wire-app-sources.py` and `scripts/sync-test-wiring`.
- [ ] **Step 4: Run** the suite — Expected: PASS. Live check (bridge server started from a DEBUG-only call in `AppDelegate` guarded by `SHELLX_REMOTE_MACHINES=1`, replaced by the service in Task 13): launch the Task 9 dev build, run `python3 scripts/shellx/remote-e2e/harness.py --app-bridge "$TMPDIR/sx-<hash8>/bridge.sock"` from `/private/tmp` (TCC note in the ledger) → viewer `terminal <id> screen read` shows the focused ShellX terminal; `write --text $'echo $((6*7))\r'` prints `42` in the Mac pane.
- [ ] **Step 5: Security review** — checklist: dir/socket perms and refusal of pre-existing insecure dirs, peer uid check before any read, connection cap, frame cap enforced before allocation, no payload logging, input never converted to `String`, tee hot path allocation-free when unbound, main-thread hops only for TerminalController calls. Fix findings.
- [ ] **Step 6: Commit** `git commit -m "feat(shellx): bridge server serving Mac terminals to the cmux-tui virtual PTY"`


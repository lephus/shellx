# Task 11 report: bridge server in the app

Worktree `/Users/lehuuphu/Documents/myProjects/shellx-wt-l5-build`, branch `shellx/l5-build`, not pushed.

Commits (on top of 9bca9efd01):
- `18cf0f3fc6` feat(shellx): bridge server serving Mac terminals to the cmux-tui virtual PTY (package)
- `50176d71d9` feat(shellx): TerminalController bridge host, output tee hook and DEBUG bridge start (app)

## What I built

Package (ruling R23), `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/Bridge/`:
- `ShellXBridgeHost.swift`: `BridgeHello`, `BridgeBinding` (Hashable, Sendable) with the `A` payload, and `@MainActor public protocol ShellXBridgeHost: AnyObject, Sendable` with the brief's six methods.
- `ShellXBridgeTee.swift`: `public enum ShellXBridgeTee { static func consume(surfaceID:buffer:) }`, plus `isBound(surfaceID:)` and internal register/unregister. The registry is an `OSAllocatedUnfairLock`.
- `ShellXBridgeServer.swift`: `public final class ShellXBridgeServer` with `init(socket:host:uid: = getuid)`, `start() throws`, `stop()`, `connectionCount`, `maxConnections = 32` and `StartError`. It also holds two internal classes. `BridgeConnection` does the per-connection read source, the serial write queue, the output hold and the pending-bytes cap. `BridgeRouter` is `@MainActor` and holds the bindings, the host calls and the 200 ms poll on a main-queue `DispatchSourceTimer`.
- New C target `Sources/ShellXRemoteAtomicsC` (one `atomic_bool`, two functions). `ShellXRemoteCore` depends on it. `Package.swift` changed by 2 lines. See concern 1 for why.

App:
- `Sources/ShellX/Remote/Bridge/TerminalControllerBridgeHost.swift`, wired with `scripts/wire-app-sources.py` (`--check` ok). It contains:
  - `TerminalControllerBridgeHost`, the spike's logic.
  - `typealias ShellXBridgeTee = ShellXRemoteCore.ShellXBridgeTee`, so the upstream hook needs no extra import. I checked this pattern with `swiftc -typecheck` in Swift 5 and Swift 6 modes on a two-module sample.
  - `#if DEBUG enum ShellXBridgeDebugStart`. It starts the server only when `SHELLX_REMOTE_MACHINES=1`, on `RemotePaths(bundleID: Bundle.main.bundleIdentifier, home:, temporaryDirectory: NSTemporaryDirectory()).bridgeSocket`. It uses a guard instead of `!`.
- `Sources/TerminalOutputTeeCallback.swift:15`: `ShellXBridgeTee.consume(surfaceID: context.surfaceID, buffer: buffer) // ShellX:`, placed after `MobileTerminalByteTee.shared.append(…)`.
- `Sources/AppDelegate.swift`: `#if DEBUG ShellXBridgeDebugStart.startIfRequested(environment: env) // ShellX: temporary, removed in Task 13` right after `let env = …` in `applicationDidFinishLaunching`, and `ShellXBridgeDebugStart.stop()` as the first line of `applicationWillTerminate`.

Protocol behaviour (matches `cmux-tui-core/src/virtual_pty.rs`):
- `H` is decoded with `JSONDecoder`, which is type-strict. `protocol` must be 1. `cols` and `rows` must fit `UInt16`. A `cwd` longer than 4096 bytes or containing NUL is dropped. A bad hello, a first frame that is not `H`, or a refused bind sends `E` and then closes gracefully.
- On bind:
  1. The tee is registered while output is held.
  2. `A` is sent: `{"mode","surface_id","workspace_id"}`, sorted keys, uppercase UUIDs.
  3. A forced `S` is sent.
  4. The snapshot goes out as `O`, followed by the output held while it was taken.
  5. Live `O` frames follow.
- `I` → `host.input(Data)` byte exact.
- `R` → `host.remoteResize`, then `S` every time.
- Poll: `S` when the grid changed. A `nil` grid sends `E` and unbinds.
- `K`, EOF, or a protocol error → unbind only. The server has no close-surface path.
- The connection ID is passed to the host in `BridgeHello.connectionID` (addition to the brief's struct). The host needs it for the `shellx-bridge-<id>` `client_id`, and the router rebuilds the binding with the server's ID, so a host cannot spoof it.

## API signatures I relied on (current tree)

- `TerminalController` is `@MainActor class`, `static let shared` (`Sources/TerminalController.swift:129-131`).
- `mobileCanonicalTerminalTarget(params:) -> (workspace: Workspace, surfaceID: UUID, target: ControlTerminalSocketTarget)?` (`Sources/TerminalController+ControlTerminalBinding.swift:164`). `ControlTerminalSocketTarget` has `surfaceID` and `surface: TerminalSurface` (`:16-25`).
- `mobileResolveWorkspaceAndSurface(params:requireTerminal:) -> (tabManager:, workspace:, surfaceId:)?` (`Sources/TerminalController.swift:17112`).
- `v2MobileTerminalViewport(params:) -> V2CallResult` (`Sources/TerminalController.swift:16361`). Its params: `client_id`, `viewport_columns`, `viewport_rows`, `viewport_generation` (`:16835-16843`), and `clear` with generation (`:16383-16388`). Rows are clamped to 5…120.
- `Workspace.newTerminalSurface(inPane:focus:workingDirectory:…autoRefreshMetadata:preserveFocusWhenUnfocused:…allowTextBoxFocusDefault:inheritStartupWork:) -> TerminalPanel?` (`Sources/Workspace.swift:9600`). I kept the argument order. `bonsplitController.focusedPaneId ?? …allPaneIds.first` is the same expression as `Workspace.swift:995`.
- `TerminalSurface.readBoundedScreenTailVT(maxRows:maxBytes:) -> String?` is `@MainActor public` (`Packages/macOS/CmuxTerminal/Sources/CmuxTerminal/Surface/TerminalSurface+TextCapture.swift:29`).
- `TerminalSurface.liveSurfaceForGhosttyAccess(reason:) -> ghostty_surface_t?` (`…/TerminalSurface+RuntimeLifecycle.swift:162`).
- `ghostty_surface_text_input(ghostty_surface_t, const char*, uintptr_t)` (`ghostty/include/ghostty.h:1640`).
- `ghostty_surface_size` → `{uint16_t columns, rows, …}` (`ghostty.h:639-646, 1511`).
- `ShellXRemoteCore` is already in the cmux target's frameworks and package product dependencies (`project.pbxproj` lines 9307 and 14096).

Host decisions:
- D7: attach is used only while the host has no binding (`states.isEmpty`). Otherwise the host creates a tab in the focused workspace, and creates one too when the focused panel is not a terminal.
- When the target exists but its ghostty surface is not live yet (a new tab before its view attaches), `grid` returns the last known grid, or the hello size as a fallback. It returns `nil` only when the target is gone. Without this, a created tab could get `E` right after bind.
- `snapshot` returns `"\e[H\e[2J" + tail VT` for attach only.
- `unbind` clears the viewport participant with generation + 1.

## Tests (Swift Testing, `Tests/ShellXRemoteCoreTests/BridgeServerTests.swift`)

The tests use a fake `@MainActor` host and a real Unix socket under `/tmp/sx-test-<hex>/bridge.sock`. Blocking client reads run in `Task.detached` so the main queue keeps serving host hops. The suite is `.serialized`.

The 8 brief tests:
- `socketAndDirAreOwnerOnly` (also checks that `stop` removes the socket)
- `refusesForeignPeer`
- `refusesInsecureExistingDir` (0755, 0701, symlink)
- `helloGetsAckSizeThenSnapshot` (also held output after the snapshot, then live tee bytes)
- `inputReachesHostByteExact` (Review Focus 4: split after byte 8, checks the 14 bytes `74 69 e1 ba bf …`)
- `remoteResizeAlwaysEchoesHostGrid`
- `surfaceGoneSendsExit`
- `killUnbindsWithoutClosingSurface`

Extras:
- `refusesTooLongSocketPath`
- `pollReportsChangedGrid`
- `eofUnbindsLikeKill`
- `stopUnbindsBoundConnections`
- `refusedBindAndBadHelloSendExit` (refused bind, protocol 2, `I` before `H`)
- `oversizeFrameIsRefusedBeforeReadingPayload`
- `connectionCapIs32`
- `teeIgnoresUnboundSurfaces`

Results:
- RED: the suite did not compile ("cannot find type 'BridgeHello'/'ShellXBridgeHost'…").
- GREEN: `swift test --package-path Packages/Shared/ShellXBrand` → 90 tests in 2 suites passed, with 0 warnings after a forced recompile of every source. It also passed 6 runs in a row.
- Mutation check: removing the uid comparison failed `refusesForeignPeer`, and making the resize echo non-forced failed `remoteResizeAlwaysEchoesHostGrid`. Both mutations were reverted.
- `python3 tests/test_shellx_remote.py`: OK.
- `.build` (152 MB) was deleted afterwards.

## Step 5 security checklist self-review (ShellXBridgeServer.swift unless noted)

| Item | Where | Status |
| --- | --- | --- |
| Socket dir 0700, created by us | `mkdir(path, 0o700)` :198 | ok |
| Refuse existing insecure dir: symlink / not a dir / foreign owner / any 0o077 bit | `lstat` + checks :201-206. Refused, never repaired. | ok. Foreign owner is not unit-tested (needs root). |
| Bind under umask(0o077), then chmod 0600 | :83-95 (errno captured before the umask is restored) | ok. umask is process-wide for the few µs of `bind` (same as the spike). |
| Stale or foreign socket file | :210-216: only a socket is unlinked, a live one (connect succeeds) → `.socketInUse`, a non-socket → `.notASocket`. `stop` unlinks only if dev/ino still match :128. | ok |
| sun_path length | :63-65 → `.pathTooLong` | ok |
| Peer uid checked before anything is read | `getpeereid` + `peerUID == uid()` in `admit` :158. The read source is created only in `connection.start()` after it. | ok |
| Max 32 connections | :166 (count of live, peer-checked connections). Listen backlog 32 :99. | ok |
| Frame cap before allocation | `BridgeFrameDecoder.feed` throws `oversize` once the 5-byte header is in. Reads are 64 KiB chunks :321, so at most one chunk is buffered for an oversized frame. Error → hard close. | ok. A valid ≤16 MiB frame is still buffered while it arrives: worst case 32 × 16 MiB from same-uid peers. |
| Outbound memory bound | pending + held bytes capped at 64 MiB per connection :245/:387/:417. Over the cap → drop the connection. | ok (added beyond the brief) |
| No payload logging | `Logger(subsystem: "pro.shellx.desktop", category: "remote-bridge")` :7. Messages carry connection ids, counts, byte totals and `mode` only (:112, 132, 161, 171, 323, 335, 424, 491, 523, 532, 560, 579). The app's start-failure log has StartError only (operation/errno/reason, no path). | ok |
| Input never converted to String | `I` payload stays `Data` from decoder → main hop :349 → `host.input` → `withUnsafeBytes` → `ghostty_surface_text_input` (app :66-72) | ok |
| Tee hot path allocation-free and lock-free when unbound | `ShellXBridgeTee.swift:13`: one relaxed C11 atomic load. The lock and `Data` copy happen only for a bound surface (:15-16). The flag is stored with release under the registry lock. | ok |
| Main-thread hops only for host calls | Hops at :341, 349, 355, 180. The router is `@MainActor`. Accept, read and write never touch main. | ok |
| Reads and writes independent per connection | read source on `readQueue`, blocking writes on serial `writeQueue`. `shutdown(2)` unblocks a stalled write (graceful close waits ≤ 2 s). | ok |
| FD hygiene | `FD_CLOEXEC` on the listener :75 and each accepted fd :149, so shells and sidecars spawned by the app do not inherit them. `SO_NOSIGPIPE` :153. `O_NONBLOCK` (inherited from the listener) is cleared on accepted fds. | ok |
| Dead connection must not open a Mac tab | `router.bind` returns early if the connection already ended :521 | ok |
| D7: K/EOF never closes a Mac tab | Kill, EOF and error all go to `end` → close hook → `router.unbind` → `host.unbind`. There is no close API. | ok |

Lifecycle fixes I made during self-review, both covered by `stopUnbindsBoundConnections`:
- The close hook captures the router strongly, so a connection closed after the server is released is still unbound (tee unregistered, viewport cleared).
- A connection ended before its read source started now closes its fd directly.

## Not verified until CI or the live check

- The app side (TerminalControllerBridgeHost, alias, AppDelegate lines) is not compiled locally (no Xcode build, per the rules). The signatures were read from source. CI must prove it.
- The new C target in the local package has not been through Xcode yet. The precedent is `CmuxFoundationAtomicsC`.
- The Step 4 live check has not been run: a DEBUG app with `SHELLX_REMOTE_MACHINES=1`, then the harness, then `screen read` and `echo $((6*7))` → 42. Remaining live questions:
  - Real `v2MobileTerminalViewport` behaviour with `client_id shellx-bridge-<n>`.
  - Whether `mobileResolveWorkspaceAndSurface(params: [:])` resolves the focused window.
  - Whether a created tab's surface goes live without focus.
- `scripts/shellx/remote-e2e/harness.py --app-bridge` was not done: the harness (Task 8) does not exist on `shellx/l5-build`. It still has to be added wherever Task 8 lands.

## Files changed

- `Packages/Shared/ShellXBrand/Package.swift`
- `Packages/Shared/ShellXBrand/Sources/ShellXRemoteAtomicsC/{ShellXRemoteAtomicsC.c,include/ShellXRemoteAtomicsC.h}` (new)
- `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/Bridge/{ShellXBridgeHost,ShellXBridgeTee,ShellXBridgeServer}.swift` (new)
- `Packages/Shared/ShellXBrand/Tests/ShellXRemoteCoreTests/BridgeServerTests.swift` (new)
- `Sources/ShellX/Remote/Bridge/TerminalControllerBridgeHost.swift` (new)
- `Sources/TerminalOutputTeeCallback.swift` (+1 line)
- `Sources/AppDelegate.swift` (+6 lines, two `#if DEBUG` blocks)
- `cmux.xcodeproj/project.pbxproj` (+4 lines, from wire-app-sources)

## Concerns

1. **Not Foundation + os only.** There is no Swift atomic on macOS 14: `Synchronization.Atomic` needs 15, and weak-linking `libswiftSynchronization` on 14 is unverified. So the lock-free "any bound" gate is a 14-line C11 target inside the ShellX package. The alternative is an uncontended `OSAllocatedUnfairLock` on every output chunk, which is a lock on the hot path. Controller: accept the C target, or rule otherwise.
2. **Protocol additions.** `ShellXBridgeHost` refines `Sendable`, so a nonisolated server can hold a main-actor host under Swift 6 rules; every `@MainActor` class conforms anyway. `BridgeHello` gained `connectionID`.
3. **Timing.** The daemon waits 10 s for `A`, and `bind` runs on main. A main thread blocked for more than 10 s fails that terminal's open. That is acceptable but worth knowing.
4. **umask.** `umask(0o077)` around `bind` is process-wide, so another thread creating a file in that window gets tighter permissions. This is the brief's requirement.
5. **Disk.** Free space was 12 GB at the end, below the 13 GB floor: it dropped from 17 GB during the session because of other activity; my `.build` was deleted.

## Fix round 1 (Ruling R27)

Commit `5bece5295b` fix(shellx): bridge test splits inside a character, lock-based tee flag, hello deadline, no accept spin. Package only; the app files are unchanged.

1. **Test now splits inside a character (Review Focus 4).** `inputReachesHostByteExact` sends `prefix(4)` / `dropFirst(4)` of "tiếng Việt\r", which cuts "ế" as `e1 ba | bf`. It then sends one `I` frame holding "Việt" across two `sendRaw` writes, cut after header + 3 bytes (inside "ệ", `e1 bb | 87`), with a 20 ms gap between the writes. It checks that the host received exactly the concatenated bytes.
2. **Lock-based tee flag (Ruling R26).**
   - The C target `ShellXRemoteAtomicsC` is deleted, and `Package.swift` is back to its 9bca9efd01 content (diff is empty).
   - `ShellXBridgeTee.swift:9` adds `anyBound = OSAllocatedUnfairLock(initialState: false)`.
   - The unbound path in `consume` (`:13`) is one uncontended lock read of a Bool, with no allocation.
   - The flag is written only inside `register`/`unregister`, under the registry lock (`:31`, `:40`). The lock order is always registry → flag, and `consume` never holds both locks at once.
3. **No accept spin.** `ShellXBridgeServer.swift:152`: on `EMFILE`/`ENFILE`, `pauseAccepting()` (`:161`) suspends the listen source, counts the stall, logs the count only, and resumes it on `acceptQueue` after 100 ms (`acceptBackoff`). This path is not unit-tested, because it needs the process fd limit exhausted.
4. **Hello deadline.**
   - `init(socket:host:uid:helloTimeout: = 10)` (`defaultHelloTimeout`).
   - Each connection schedules a deadline on its read queue (`:325`). If no valid `H` has arrived by then, it does a hard `end`, logs the connection id only, and the close hook frees the slot.
   - New test `silentConnectionIsClosedAfterHelloDeadline` (timeout 0.2 s):
     - A silent client gets EOF with no frame, and `connectionCount` returns to 0.
     - A client that says hello in time gets `A` and is still connected 0.4 s later.
   - Mutation check: disabling the deadline makes this test fail with 3 issues (reverted).

Command: `swift test --package-path Packages/Shared/ShellXBrand`
Output: `✔ Test run with 91 tests in 2 suites passed`. It passed 5 times, one of them after a forced recompile of every source, with 0 `warning:` / `error:` lines. `.build` deleted afterwards. `df -h /` shows 17 GB free.

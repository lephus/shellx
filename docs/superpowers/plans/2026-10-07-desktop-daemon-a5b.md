# ShellX Desktop A5b — `shellx-mux` Daemon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shells, PTYs and the phone relay live in a headless `ShellX --daemon` process (`shellx-mux`) so quitting (⌘Q), crashing or updating the window never ends a shell; the window reattaches over an authenticated local socket/pipe, and "Thoát hoàn toàn" stops everything.

**Architecture:** A pure-Dart `mux` layer in `packages/shellx_agent` (framed CBOR messages reusing `termFrame`/`decodeCbor`, mutual-HMAC handshake reusing `hmacSha256`, endpoint file, `MuxTransport` with Unix-socket and in-memory implementations, `MuxServer` serving any `LocalSessions`, and `RemoteLocalSessions` implementing `LocalSessions` over a `MuxClient`). The desktop app gains a daemon entry point (`daemonMain`) that runs today's `SessionCore` + `AgentController` headless, a `RemoteAgentController` mirroring `AgentViewState`, a Windows named-pipe transport (FFI), a `DaemonLauncher` (connect-or-spawn, version check), two quit flows and the reattach path that uses A5a's layout file. A contract test suite runs the same `LocalSessions` tests in-process and over the wire.

**Tech Stack:** Dart ^3.11 / Flutter 3.41.4 (fvm), `package:test` + `fake_async` (agent), `flutter_test` (desktop), flutter_riverpod 3, `cbor` via `shellx_core` (`encodeCbor`/`decodeCbor`), `cryptography` (via `hmacSha256`), `win32` + `ffi` (Windows pipe), Swift (macOS runner), C++ (Windows runner), Inno Setup.

**Spec:** `docs/superpowers/specs/2026-10-07-desktop-daemon-a5b-design.md` (binding; B1–B9 and D1–D30 are final). **UI design:** `docs/superpowers/design/2026-10-07-shellx-desktop-ui-a5.md` §6–§9 (A5b rows) ("UI-A5 §N"). A5a spec/plan must be merged and read: A5b reuses `RestorePersistence`, `RestoreSnapshot.daemon`/`SavedPane.session` and `InfoStrip`.

## Prerequisite: A5a merged; manual-check machines available

Start `feat/desktop-a5b` from `main` **after A5a is merged**. Tasks marked **⚠ MANUAL** need a real Mac (Apple Silicon, macOS 13+) and a real Windows 10 1809+/11 machine; an executor without the machine stops at that step, records "pending manual" in `docs/superpowers/ledgers/a1-desktop-terminal.md` under `## A5b (daemon) — execution`, and continues with the next task — **the branch is not merged until every ⚠ step is recorded as passed.**

Baseline before Task 1 (record counts):

```bash
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test
cd ../../apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test
```

## Global Constraints

- The spec wins; UI-A5 wins for visuals and copy. No new colour tokens. User-facing Vietnamese says **"phiên nền"**, English **"background service"** — never "daemon" in UI text.
- Toolchain and commands as in A5a (fvm 3.41.4; `dart test` in `packages/shellx_agent`, `flutter test` in `apps/desktop`, `dart format --set-exit-if-changed`, `flutter analyze` / `dart analyze`).
- **Phone protocol unchanged (D29):** no edits to `packages/shellx_core/lib/src/protocol/messages.dart`, `apps/mobile`, `relay/`, `term/`. `packages/shellx_agent` may gain the new `src/mux/` directory and the `LocalSessionView.backlog` doc change only — **no new dependencies in `packages/shellx_agent/pubspec.yaml`**.
- Frozen wire (D7): 4-byte big-endian length + one CBOR map ≤ 65,536 bytes; `hello`, `auth`, `ready`, `daemon.status`, `daemon.quit` shapes never change; `kMuxProtocol = 1`; unknown keys and event types ignored; unknown request types → `error{code: unknown_type}`.
- Handshake (D6): labels `shellx-mux/daemon` and `shellx-mux/client`; nonces 32 bytes; handshake timeout 2 s; at most 4 connections handshaking.
- Flow control (D11): stop a view above 2,097,152 unacked bytes, resume with `view.reset` below 524,288; UI acks at ≥ 65,536 bytes or every 100 ms.
- Lifecycle timings: connect attempt 1 s; spawn-and-retry 100 ms steps up to 5 s; daemon idle exit 10 s (D27); full-quit kill wait 3 s; incompatible daemon quit wait 4 s.
- Settings ownership (D13): daemon keys `remote_access_enabled`, `keep_awake_enabled`, `launch_at_startup_enabled`, `onboarding_done`, `terminal_sharing_enabled`, `terminal_sharing_files`, `command_notify_threshold_seconds`, `desktop_notifications_enabled`, `desktop_notifications_only_unfocused`; every other key is UI-owned. A process never writes the other's keys.
- Privacy/logging (D23, D30): never log message contents, tokens, secrets, paths of user files or terminal text — only message type, error code, `runtimeType`.
- Every interface gaining members updates **every** implementer in the same task (`SessionManager`, `FakeLocalSessions`, `RemoteLocalSessions`).
- Code style as in A1–A5a. Every task ends green (its tests, full suites from Task 5 on), formatted, analyzer clean, committed with only the listed files — never `git add -A`.

## Review Focus

1. **The UI stalls while a shell floods output** (debugger pause, SIGSTOP, a long GC) — daemon memory must stay bounded per view and the UI must resume with a reset, not a half-written escape sequence. Pinned by the ack/reset tests in Task 4 and the `RemoteSessionView` reset test in Task 5.
2. **A stale endpoint file / a squatter** (daemon crashed leaving `endpoint`; another process bound the pipe name or socket first; a process without the secret connects) — the UI must never send input to a peer that has not proven the secret, and must spawn a fresh daemon. Pinned by the handshake tests in Task 2 and the launcher tests in Task 7.
3. **The daemon dies while the UI is open** — tabs must not print "[Tiến trình đã thoát…]" exit lines, input is dropped not queued forever, and the restart restores from A5a without a duplicate tab. Pinned by the `daemon_lost` tests in Task 8.
4. **A new UI meets an old daemon** (protocol differs; same protocol but older app) — never attach across protocols; with 0 sessions quietly replace; with sessions ask (UI-A5 §7.3). Pinned by the launcher tests in Task 7 and the prompt test in Task 8.
5. **Two processes writing settings** (UI toggles a daemon-owned switch; daemon changes `notifyThreshold`) — the change must go through `agent.call` and come back via `agent.state`; no stale cached value in either process. Pinned by the ownership test in Task 6.

---

## File Structure

| File | Responsibility |
|---|---|
| Create `packages/shellx_agent/lib/src/mux/mux_messages.dart` | `MuxMessage`, `MuxType`, `MuxError`, codecs for `SessionSummary`/`SessionNotice` |
| Create `packages/shellx_agent/lib/src/mux/mux_handshake.dart` | proofs, `MuxHello`, `serverHandshake`, `clientHandshake` |
| Create `packages/shellx_agent/lib/src/mux/mux_endpoint.dart` | endpoint file read/write/delete-if-owned |
| Create `packages/shellx_agent/lib/src/mux/mux_transport.dart` | `MuxTransport`, `MuxConnection`, `MuxListener`, `UnixMuxTransport`, `MemoryMuxTransport`, `socketPathFor` |
| Create `packages/shellx_agent/lib/src/mux/mux_server.dart` | `MuxServer`, `AgentBridge`, per-client link, ack window |
| Create `packages/shellx_agent/lib/src/mux/remote_local_sessions.dart` | `MuxClient`, `RemoteLocalSessions`, `RemoteSessionView` |
| Modify `packages/shellx_agent/lib/shellx_agent.dart` | exports |
| Modify `packages/shellx_agent/lib/src/session/local_sessions.dart` | `backlog` contract doc (D10) |
| Create `packages/shellx_agent/test/mux/*.dart`, `test/support/local_sessions_contract.dart` | tests |
| Create `apps/desktop/lib/daemon_main.dart` | `daemonMain` entry point |
| Create `apps/desktop/lib/src/mux/launch_mode.dart` | `LaunchMode parseLaunchMode(List<String>)` |
| Create `apps/desktop/lib/src/mux/daemon_host.dart` | lock, endpoint, idle exit, quit |
| Create `apps/desktop/lib/src/mux/daemon_launcher.dart` | connect-or-spawn, outcomes |
| Create `apps/desktop/lib/src/mux/windows_pipe_transport.dart` | named pipe via FFI |
| Create `apps/desktop/lib/src/mux/windows_runtime_copy.dart` | D3 copy |
| Create `apps/desktop/lib/src/agent/agent_controller_base.dart`, `agent_state_codec.dart`, `remote_agent_controller.dart`, `agent_bridge_impl.dart` | agent split (D12) |
| Modify `apps/desktop/lib/src/agent/agent_controller.dart`, `desktop_services.dart`, `platform/settings_store.dart` | base class, async signatures, key ownership |
| Modify `apps/desktop/lib/main.dart`, `tray/*`, `ui/terminal/terminal_pane.dart`, `ui/activation.dart` | UI process, quit flows, dialogs, strips |
| Modify `apps/desktop/lib/src/restore/restore_persistence.dart`, `terminal/terminal_tabs.dart` | reattach mode (D18) |
| Modify `apps/desktop/macos/Runner/AppDelegate.swift`, `MainFlutterWindow.swift` | headless mode (D2), ⌥⌘Q menu item |
| Modify `apps/desktop/windows/runner/main.cpp`, create `daemon_runner.cpp`/`.h`, `CMakeLists.txt` | headless mode (D3) |
| Modify `release/windows/shellx.iss`, `release/tests/inno.test.mjs` | D21 |
| Modify `docs/superpowers/HANDOFF.md`, ledger | §16 |

---

### Task 1: ⚠ Spike — the app binary runs headless with `--daemon` (D2, D3)

The riskiest assumption first: a headless Flutter engine in the same bundle/exe, with the plugins the daemon needs and **no** window, Dock icon or taskbar button — and Finder/Dock still opening the UI while only the daemon runs.

**Files:**
- Create: `apps/desktop/lib/src/mux/launch_mode.dart`, `apps/desktop/lib/daemon_main.dart` (stub)
- Modify: `apps/desktop/lib/main.dart` (export `daemonMain` so the entry point is compiled into AOT)
- Modify: `apps/desktop/macos/Runner/AppDelegate.swift`, `apps/desktop/macos/Runner/MainFlutterWindow.swift`
- Modify: `apps/desktop/windows/runner/main.cpp`; Create `apps/desktop/windows/runner/daemon_runner.cpp`, `daemon_runner.h`; Modify `apps/desktop/windows/runner/CMakeLists.txt`
- Test: `apps/desktop/test/mux/launch_mode_test.dart`

**Interfaces:**
- Produces: `enum LaunchMode { ui, daemon, terminalSharingCleanup }`, `LaunchMode parseLaunchMode(List<String> args)`; Dart entry point `@pragma('vm:entry-point') Future<void> daemonMain(List<String> args)` in `daemon_main.dart` (stub in this task: writes `<app support>/mux/heartbeat` with its pid every 2 s using `path_provider`, then real body in Task 7).

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/mux/launch_mode.dart';

void main() {
  test('launch modes', () {
    expect(parseLaunchMode(const []), LaunchMode.ui);
    expect(parseLaunchMode(const ['--daemon']), LaunchMode.daemon);
    expect(parseLaunchMode(const ['--terminal-sharing-cleanup']),
        LaunchMode.terminalSharingCleanup);
    expect(parseLaunchMode(const ['-psn_0_12345']), LaunchMode.ui); // Finder
  });
}
```

- [ ] **Step 2: Run it to verify it fails** — `flutter test test/mux/launch_mode_test.dart` → FAIL (missing file).

- [ ] **Step 3: Implement the Dart side**

`launch_mode.dart`:

```dart
/// How this process was started (A5b D2, D3).
enum LaunchMode { ui, daemon, terminalSharingCleanup }

LaunchMode parseLaunchMode(List<String> args) {
  if (args.contains('--daemon')) return LaunchMode.daemon;
  if (args.contains('--terminal-sharing-cleanup')) {
    return LaunchMode.terminalSharingCleanup;
  }
  return LaunchMode.ui;
}
```

`daemon_main.dart` (stub):

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// The `shellx-mux` entry point (A5b D2/D3): started by the native runner
/// on a headless engine. Task 1 stub: proves the engine, plugins and
/// process lifetime; Task 7 replaces the body.
@pragma('vm:entry-point')
Future<void> daemonMain(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  final beat = File('${support.path}${Platform.pathSeparator}mux${Platform.pathSeparator}heartbeat');
  await beat.parent.create(recursive: true);
  Timer.periodic(const Duration(seconds: 2), (_) {
    beat.writeAsStringSync('$pid ${DateTime.now().toIso8601String()}');
  });
}
```

In `main.dart` add `export 'daemon_main.dart' show daemonMain;` near the imports (keeps the symbol reachable for AOT tree shaking together with the pragma) and make the existing `--terminal-sharing-cleanup` check use `parseLaunchMode(args) == LaunchMode.terminalSharingCleanup`. On Windows the runner passes `--daemon` only to the daemon entry point, so `main` never sees it; add a guard anyway: `if (parseLaunchMode(args) == LaunchMode.daemon) return daemonMain(args);`.

- [ ] **Step 4: Implement the macOS side (⚠ MANUAL verification in Step 6)**

`AppDelegate.swift`:

```swift
/// A5b D2: the same binary started with `--daemon` is the headless
/// `shellx-mux`: no window, no Dock icon, no menu bar.
let isDaemon = CommandLine.arguments.contains("--daemon")

@main
class AppDelegate: FlutterAppDelegate {
  private var daemonEngine: FlutterEngine?

  override func applicationWillFinishLaunching(_ notification: Notification) {
    if isDaemon { NSApp.setActivationPolicy(.prohibited) }
    super.applicationWillFinishLaunching(notification)
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if isDaemon {
      let engine = FlutterEngine(name: "shellx-mux", project: nil, allowHeadlessExecution: true)
      engine.run(withEntrypoint: "daemonMain")
      DaemonPlugins.register(engine)
      LaunchAtLoginChannel.register(messenger: engine.binaryMessenger)
      daemonEngine = engine
      return
    }
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(willPowerOff(_:)),
      name: NSWorkspace.willPowerOffNotification, object: nil)
    super.applicationDidFinishLaunching(notification)
  }

  // A5b D2: LaunchServices may route a Finder/Dock/Spotlight "open" to the
  // daemon (same bundle id). The daemon then starts the UI instead.
  override func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    if isDaemon { DaemonForwarder.openUi(); return false }
    for window in sender.windows where window.isMiniaturized {
      window.deminiaturize(nil)
    }
    AppChannel.reopen()
    return false
  }
  // … existing members unchanged; in applicationShouldTerminate add first:
  //   if isDaemon { return .terminateNow }
}

enum DaemonForwarder {
  static func openUi() {
    let config = NSWorkspace.OpenConfiguration()
    config.createsNewApplicationInstance = true
    config.activates = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config)
  }
}

/// Only what the daemon uses (no window_manager, tray_manager,
/// screen_retriever: they need a view).
enum DaemonPlugins {
  static func register(_ registry: FlutterPluginRegistry) {
    FlutterSecureStoragePlugin.register(with: registry.registrar(forPlugin: "FlutterSecureStoragePlugin"))
    SharedPreferencesPlugin.register(with: registry.registrar(forPlugin: "SharedPreferencesPlugin"))
    PathProviderPlugin.register(with: registry.registrar(forPlugin: "PathProviderPlugin"))
    FPPPackageInfoPlusPlugin.register(with: registry.registrar(forPlugin: "FPPPackageInfoPlusPlugin"))
    LocalNotifierPlugin.register(with: registry.registrar(forPlugin: "LocalNotifierPlugin"))
  }
}
```

Use the exact plugin class names from `macos/Flutter/GeneratedPluginRegistrant.swift` (copy the lines for these five plugins; add their `import` lines). `MainFlutterWindow.awakeFromNib`: first line `if isDaemon { super.awakeFromNib(); return }` (no `FlutterViewController`, so no second engine; the nib window is never ordered front).

- [ ] **Step 5: Implement the Windows side (⚠ MANUAL verification in Step 6)**

`daemon_runner.h`/`.cpp`:

```cpp
// A5b D3: headless shellx-mux — one FlutterEngine, no window.
#include <flutter/dart_project.h>
#include <flutter/flutter_engine.h>
#include <windows.h>
#include "flutter/generated_plugin_registrant.h"  // only for the include paths

#include <flutter_secure_storage_windows/flutter_secure_storage_windows_plugin.h>
#include <local_notifier/local_notifier_plugin.h>

int RunDaemon(flutter::DartProject project) {
  project.set_dart_entrypoint("daemonMain");
  flutter::FlutterEngine engine(project);
  if (!engine.Run("daemonMain")) return EXIT_FAILURE;
  FlutterSecureStorageWindowsPluginRegisterWithRegistrar(
      engine.GetRegistrarForPlugin("FlutterSecureStorageWindowsPlugin"));
  LocalNotifierPluginRegisterWithRegistrar(
      engine.GetRegistrarForPlugin("LocalNotifierPlugin"));
  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }
  return EXIT_SUCCESS;
}
```

(Take the exact registrar function names from `windows/flutter/generated_plugin_registrant.cc`; `path_provider_windows`, `shared_preferences_windows`, `package_info_plus` are Dart/FFI on Windows and need no registration.) In `main.cpp`, after `CoInitializeEx` and building `project`/`command_line_arguments`:

```cpp
  for (const auto& arg : command_line_arguments) {
    if (arg == "--daemon") {
      project.set_dart_entrypoint_arguments(std::move(command_line_arguments));
      int code = RunDaemon(std::move(project));
      ::CoUninitialize();
      return code;
    }
  }
```

Add `daemon_runner.cpp` to `BINARY_NAME` sources in `windows/runner/CMakeLists.txt`.

- [ ] **Step 6: ⚠ MANUAL — spike checks (record each result in the ledger)**

macOS (`flutter build macos --release`, then):
1. `build/macos/Build/Products/Release/ShellX.app/Contents/MacOS/ShellX --daemon &` → no Dock icon, no menu bar, no window; `cat ~/Library/Application\ Support/pro.shellx.desktop/mux/heartbeat` updates every 2 s; `ps -o rss= -p <pid>` < 150 MB.
2. With only the daemon running: double-click ShellX.app in Finder, Spotlight "ShellX", `open -a ShellX` → a **UI** instance starts (window visible) — either LaunchServices starts a new process directly, or the daemon forwards (`DaemonForwarder`). Then Dock click on the running UI → the UI handles reopen (not the daemon).
3. Quit the UI (still old A1 quit in this task) → daemon heartbeat continues.
4. **Decision:** if 2 fails in any variant, stop and switch D2 to the documented fallback (helper bundle `Contents/Helpers/ShellX Mux.app`); write the ruling in the ledger before Task 7.

Windows (`flutter build windows --release`):
5. `ShellX.exe --daemon` from a terminal → no window, no taskbar button; heartbeat in `%APPDATA%\pro.shellx\ShellX\mux\heartbeat` updates; Task Manager shows one `ShellX.exe`.
6. Start `ShellX.exe` normally → UI appears; close it → daemon continues.

- [ ] **Step 7: Run tests, format, analyze, commit**

```bash
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && cd ../..
git add apps/desktop/lib/src/mux/launch_mode.dart apps/desktop/lib/daemon_main.dart apps/desktop/lib/main.dart apps/desktop/macos/Runner/AppDelegate.swift apps/desktop/macos/Runner/MainFlutterWindow.swift apps/desktop/windows/runner/main.cpp apps/desktop/windows/runner/daemon_runner.cpp apps/desktop/windows/runner/daemon_runner.h apps/desktop/windows/runner/CMakeLists.txt apps/desktop/test/mux/launch_mode_test.dart docs/superpowers/ledgers/a1-desktop-terminal.md
git commit -m "feat(desktop): headless --daemon launch mode on a Flutter engine without a window (A5b D2, D3 spike)"
```

---

### Task 2: Mux wire — messages, frames, mutual-HMAC handshake (D6, D7, D9)

**Files:**
- Create: `packages/shellx_agent/lib/src/mux/mux_messages.dart`, `packages/shellx_agent/lib/src/mux/mux_handshake.dart`
- Modify: `packages/shellx_agent/lib/shellx_agent.dart` (exports)
- Test: `packages/shellx_agent/test/mux/mux_messages_test.dart`, `packages/shellx_agent/test/mux/mux_handshake_test.dart`

**Interfaces:**
- Consumes: `encodeCbor`, `decodeCbor`, `concatBytes` (`shellx_core`); `hmacSha256`, `termFrame`, `TermFrameReader`, `kTermMaxFrame`, `kTermMaxChunk` (agent `term/`); `SessionSummary`, `SessionOrigin`, `SessionNotice`, `SessionNoticeKind`, `CompletedCommand`, `DriverSide`.
- Produces:
  - `const int kMuxProtocol = 1;`
  - `abstract final class MuxType` with string constants: `hello, auth, ready, result, error, daemonStatus = 'daemon.status', daemonQuit = 'daemon.quit', sessionsList = 'sessions.list', sessionsChanged = 'sessions.changed', sessionsOpen = 'sessions.open', sessionsClose = 'sessions.close', sessionsNotice = 'sessions.notice', sessionsWatchPorts = 'sessions.watchPorts', viewOpen = 'view.open', viewOut = 'view.out', viewDriver = 'view.driver', viewExit = 'view.exit', viewWrite = 'view.write', viewReply = 'view.reply', viewResize = 'view.resize', viewAck = 'view.ack', viewReset = 'view.reset', viewClose = 'view.close', agentState = 'agent.state', agentCall = 'agent.call', agentGet = 'agent.get'`.
  - `abstract final class MuxError` codes: `unknownType = 'unknown_type', badRequest = 'bad_request', notFound = 'not_found', busy, unsupportedRole = 'unsupported_role', sessionLimit = 'session_limit', spawnFailed = 'spawn_failed', internal`.
  - `final class MuxMessage { const MuxMessage(String type, {int? q, Map<String, Object?> fields = const {}}); String get type; int? get q; Map<String, Object?> get fields; T? get<T>(String key); }`
  - `Uint8List encodeMux(MuxMessage m)` (returns a **frame**: length prefix + CBOR); `final class MuxFrameDecoder { List<MuxMessage> add(List<int> chunk); }` (throws `FormatException` on oversize/garbage)
  - `Map<String, Object?> summaryToWire(SessionSummary s)`, `SessionSummary summaryFromWire(Map<Object?, Object?> m)`, `Map<String, Object?> noticeToWire(SessionNotice n)`, `SessionNotice noticeFromWire(Map<Object?, Object?> m)`
  - `Uint8List daemonProof(Uint8List secret, Uint8List nonceClient, Uint8List nonceDaemon)`, `Uint8List clientProof(Uint8List secret, Uint8List nonceDaemon, Uint8List nonceClient)`
  - `final class MuxPeerInfo { const MuxPeerInfo({required int protocol, required String app, String? role, String? instance, int? pid, int? sessions, List<String> caps = const []}); }`
  - `Future<MuxPeerInfo> clientHandshake(MuxConnection c, {required Uint8List secret, required String app, required String role, Duration timeout})` — throws `MuxHandshakeException`
  - `Future<MuxPeerInfo> serverHandshake(MuxConnection c, {required Uint8List secret, required MuxPeerInfo self, Duration timeout})`
  - `final class MuxHandshakeException implements Exception { const MuxHandshakeException(String reason); }`
  - `MuxConnection` is defined in Task 3; to keep this task self-contained, declare it here in `mux_transport.dart` as the interface only (`abstract interface class MuxConnection { Stream<MuxMessage> get messages; void send(MuxMessage m); Future<void> close(); }`) and add `MemoryMuxTransport.pair()` (two linked in-memory connections that run every message through `encodeMux`/`MuxFrameDecoder`) — Task 3 adds the real transports.

- [ ] **Step 1: Write the failing tests**

`packages/shellx_agent/test/mux/mux_messages_test.dart`:

```dart
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

void main() {
  test('round trip through frames, split across chunks', () {
    final m = MuxMessage(MuxType.viewWrite, q: 7, fields: {
      'id': 3,
      'data': Uint8List.fromList([1, 2, 255]),
      'future': 'ignored by old peers',
    });
    final frame = encodeMux(m);
    final d = MuxFrameDecoder();
    expect(d.add(frame.sublist(0, 5)), isEmpty);
    final out = d.add(frame.sublist(5)).single;
    expect(out.type, MuxType.viewWrite);
    expect(out.q, 7);
    expect(out.get<int>('id'), 3);
    expect(out.get<Uint8List>('data'), [1, 2, 255]);
  });

  test('oversize frame and garbage are rejected', () {
    final big = Uint8List(4)..buffer.asByteData().setUint32(0, 65537);
    expect(() => MuxFrameDecoder().add(big), throwsFormatException);
    final junk = Uint8List.fromList([0, 0, 0, 2, 0xff, 0xff]);
    expect(() => MuxFrameDecoder().add(junk), throwsFormatException);
    final notMap = encodeCborFrame([1, 2]);
    expect(() => MuxFrameDecoder().add(notMap), throwsFormatException);
  });

  test('golden bytes of the frozen hello (D7)', () {
    final hello = encodeMux(MuxMessage(MuxType.hello, fields: {
      'protocol': 1,
      'app': '1.0.0',
      'role': 'ui',
      'nonce': Uint8List(32),
    }));
    expect(bytesToHex(hello.sublist(0, 4)), '00000037');
    expect(hello.length, 4 + 0x37);
  });

  test('SessionSummary and SessionNotice survive the wire', () {
    final s = SessionSummary(
      id: 4, index: 2, shell: 'zsh', createdAt: DateTime.utc(2026, 10, 7),
      attachedMobileId: 'm1', origin: SessionOrigin.desktop, title: 'vim',
      driver: DriverSide.desktop, runningCommand: true, cwd: '/w',
      gitBranch: 'main', ports: const [3000, 5173],
    );
    final back = summaryFromWire(summaryToWire(s));
    expect([back.id, back.index, back.shell, back.attachedMobileId, back.origin,
            back.title, back.driver, back.runningCommand, back.cwd, back.gitBranch, back.ports],
        [4, 2, 'zsh', 'm1', SessionOrigin.desktop, 'vim', DriverSide.desktop, true, '/w', 'main', [3000, 5173]]);
    expect(back.createdAt, s.createdAt);
    final n = SessionNotice(
      sessionId: 4, kind: SessionNoticeKind.command, at: DateTime.utc(2026),
      command: const CompletedCommand(commandLine: 'make', exitCode: 2, duration: Duration(seconds: 11)),
    );
    final nb = noticeFromWire(noticeToWire(n));
    expect(nb.kind, SessionNoticeKind.command);
    expect(nb.command!.exitCode, 2);
    expect(nb.command!.duration, const Duration(seconds: 11));
  });
}

Uint8List encodeCborFrame(Object value) {
  final body = encodeCbor(value);
  return termFrame(body);
}
```

(The golden length `0x37` must be computed once by running the encoder and then **frozen**; if the first run differs, set the expected hex to the actual value, review the CBOR by hand (map of 5 keys in insertion order `t, protocol, app, role, nonce`), and never change it again.)

`packages/shellx_agent/test/mux/mux_handshake_test.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

final secret = Uint8List.fromList(List.generate(32, (i) => i));
const self = MuxPeerInfo(protocol: 1, app: '1.6.0', instance: 'i1', pid: 42, sessions: 3, caps: ['x']);

void main() {
  test('both sides prove the secret; info exchanged', () async {
    final (a, b) = MemoryMuxTransport.pair();
    final server = serverHandshake(b, secret: secret, self: self);
    final client = await clientHandshake(a, secret: secret, app: '1.6.1', role: 'ui');
    expect(client.instance, 'i1');
    expect(client.sessions, 3);
    expect((await server).role, 'ui');
  });

  test('a client without the secret is refused before anything else', () async {
    final (a, b) = MemoryMuxTransport.pair();
    final server = serverHandshake(b, secret: secret, self: self);
    await expectLater(
      clientHandshake(a, secret: Uint8List(32), app: '1', role: 'ui'),
      throwsA(isA<MuxHandshakeException>()), // daemon proof does not verify
    );
    await expectLater(server, throwsA(isA<MuxHandshakeException>()));
  });

  test('a squatter that cannot prove the secret gets no auth from the client',
      () async {
    final (a, b) = MemoryMuxTransport.pair();
    final sent = <MuxMessage>[];
    b.messages.listen((m) {
      sent.add(m);
      if (m.type == MuxType.hello) {
        b.send(MuxMessage(MuxType.hello, fields: {
          'protocol': 1, 'app': 'evil', 'nonce': Uint8List(32), 'proof': Uint8List(32),
        }));
      }
    });
    await expectLater(
      clientHandshake(a, secret: secret, app: '1', role: 'ui'),
      throwsA(isA<MuxHandshakeException>()),
    );
    expect(sent.map((m) => m.type), [MuxType.hello]); // never `auth`
  });

  test('silence → timeout after 2 s', () {
    fakeAsync((async) {
      final (a, _) = MemoryMuxTransport.pair();
      Object? error;
      clientHandshake(a, secret: secret, app: '1', role: 'ui').catchError((Object e) {
        error = e;
        return self;
      });
      async.elapse(const Duration(milliseconds: 1999));
      expect(error, isNull);
      async.elapse(const Duration(milliseconds: 2));
      expect(error, isA<MuxHandshakeException>());
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail** — `cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test test/mux` → FAIL.

- [ ] **Step 3: Implement**

`mux_messages.dart`:

```dart
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import '../notify/command_tracker.dart';
import '../session/session_manager.dart';
import '../session/session_notice.dart';
import '../term/term_frames.dart';

/// A5b D7: bump only for a breaking change.
const int kMuxProtocol = 1;

abstract final class MuxType {
  static const hello = 'hello', auth = 'auth', ready = 'ready';
  static const result = 'result', error = 'error';
  static const daemonStatus = 'daemon.status', daemonQuit = 'daemon.quit';
  static const sessionsList = 'sessions.list';
  static const sessionsChanged = 'sessions.changed';
  static const sessionsOpen = 'sessions.open';
  static const sessionsClose = 'sessions.close';
  static const sessionsNotice = 'sessions.notice';
  static const sessionsWatchPorts = 'sessions.watchPorts';
  static const viewOpen = 'view.open', viewOut = 'view.out';
  static const viewDriver = 'view.driver', viewExit = 'view.exit';
  static const viewWrite = 'view.write', viewReply = 'view.reply';
  static const viewResize = 'view.resize', viewAck = 'view.ack';
  static const viewReset = 'view.reset', viewClose = 'view.close';
  static const agentState = 'agent.state', agentCall = 'agent.call';
  static const agentGet = 'agent.get';
}

abstract final class MuxError {
  static const unknownType = 'unknown_type', badRequest = 'bad_request';
  static const notFound = 'not_found', busy = 'busy';
  static const unsupportedRole = 'unsupported_role';
  static const sessionLimit = 'session_limit', spawnFailed = 'spawn_failed';
  static const internal = 'internal';
}

/// One message (D9): `{"t": type, "q": request id?, …fields}`. An open
/// map: unknown keys are carried and ignored (D7).
final class MuxMessage {
  const MuxMessage(this.type, {this.q, this.fields = const {}});
  final String type;
  final int? q;
  final Map<String, Object?> fields;

  T? get<T>(String key) {
    final v = fields[key];
    return v is T ? v : null;
  }

  @override
  String toString() => 'MuxMessage($type${q == null ? '' : ' #$q'})';
}

Uint8List encodeMux(MuxMessage m) => termFrame(
  encodeCbor({'t': m.type, 'q': ?m.q, ...m.fields}),
);

/// Bytes from a connection → messages. Throws [FormatException] on a frame
/// over 64 KiB, bad CBOR (depth > 8 included) or a payload that is not a
/// map with a string `t`: the caller closes the connection (D26).
final class MuxFrameDecoder {
  final _frames = TermFrameReader();

  List<MuxMessage> add(List<int> chunk) => [
    for (final payload in _frames.add(chunk)) _decode(payload),
  ];

  static MuxMessage _decode(Uint8List payload) {
    final value = decodeCbor(payload);
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('mux payload is not a map');
    }
    final type = value['t'];
    final q = value['q'];
    if (type is! String || (q != null && q is! int)) {
      throw const FormatException('mux message without a type');
    }
    return MuxMessage(type, q: q as int?, fields: {
      for (final MapEntry(:key, :value) in value.entries)
        if (key is String && key != 't' && key != 'q') key: value,
    });
  }
}

Map<String, Object?> summaryToWire(SessionSummary s) => {
  'id': s.id,
  'index': s.index,
  'shell': s.shell,
  'created': s.createdAt.toUtc().microsecondsSinceEpoch,
  'mobile': s.attachedMobileId,
  'origin': s.origin.name,
  'title': s.title,
  'driver': s.driver.wire,
  'running': s.runningCommand,
  'cwd': s.cwd,
  'branch': s.gitBranch,
  'ports': s.ports,
};

SessionSummary summaryFromWire(Map<Object?, Object?> m) => SessionSummary(
  id: m['id']! as int,
  index: m['index']! as int,
  shell: m['shell']! as String,
  createdAt: DateTime.fromMicrosecondsSinceEpoch(m['created']! as int, isUtc: true),
  attachedMobileId: m['mobile'] as String?,
  origin: SessionOrigin.values.byName(m['origin']! as String),
  title: m['title'] as String? ?? '',
  driver: DriverSide.fromWire(m['driver']! as String),
  runningCommand: m['running'] as bool? ?? false,
  cwd: m['cwd'] as String?,
  gitBranch: m['branch'] as String?,
  ports: [for (final p in m['ports'] as List<Object?>? ?? const []) p! as int],
);

Map<String, Object?> noticeToWire(SessionNotice n) => {
  'id': n.sessionId,
  'kind': n.kind.name,
  'at': n.at.toUtc().microsecondsSinceEpoch,
  'title': n.title,
  'body': n.body,
  if (n.command case final c?) ...{
    'cmd': c.commandLine,
    'code': c.exitCode,
    'ms': c.duration.inMilliseconds,
  },
};

SessionNotice noticeFromWire(Map<Object?, Object?> m) => SessionNotice(
  sessionId: m['id']! as int,
  kind: SessionNoticeKind.values.byName(m['kind']! as String),
  at: DateTime.fromMicrosecondsSinceEpoch(m['at']! as int, isUtc: true),
  title: m['title'] as String?,
  body: m['body'] as String?,
  command: m.containsKey('code')
      ? CompletedCommand(
          commandLine: m['cmd'] as String?,
          exitCode: m['code']! as int,
          duration: Duration(milliseconds: m['ms']! as int),
        )
      : null,
);
```

(Check `DriverSide` exposes `wire`/`fromWire` in `shellx_core` — it does: `enum DriverSide { desktop('desktop'), …; static DriverSide fromWire(String) }`; if the field is named differently, use that name. The `'q': ?m.q` null-aware map entry needs Dart ≥ 3.8; the repo uses ^3.11.)

`mux_handshake.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import '../term/term_auth.dart';
import 'mux_messages.dart';
import 'mux_transport.dart';

final _daemonLabel = utf8.encode('shellx-mux/daemon');
final _clientLabel = utf8.encode('shellx-mux/client');

Uint8List daemonProof(Uint8List secret, Uint8List nonceClient, Uint8List nonceDaemon) =>
    hmacSha256(secret, concatBytes([_daemonLabel, nonceClient, nonceDaemon]));

Uint8List clientProof(Uint8List secret, Uint8List nonceDaemon, Uint8List nonceClient) =>
    hmacSha256(secret, concatBytes([_clientLabel, nonceDaemon, nonceClient]));

final class MuxHandshakeException implements Exception {
  const MuxHandshakeException(this.reason);
  final String reason;
  @override
  String toString() => 'MuxHandshakeException: $reason';
}

final class MuxPeerInfo {
  const MuxPeerInfo({
    required this.protocol,
    required this.app,
    this.role,
    this.instance,
    this.pid,
    this.sessions,
    this.caps = const [],
  });
  final int protocol;
  final String app;
  final String? role;
  final String? instance;
  final int? pid;
  final int? sessions;
  final List<String> caps;
}

Uint8List _nonce() {
  final r = Random.secure();
  return Uint8List.fromList(List.generate(32, (_) => r.nextInt(256)));
}

bool _same(Uint8List a, Uint8List? b) {
  if (b == null || a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// D6, client side: hello → verify the daemon's proof → auth → ready.
Future<MuxPeerInfo> clientHandshake(
  MuxConnection c, {
  required Uint8List secret,
  required String app,
  required String role,
  Duration timeout = const Duration(seconds: 2),
}) async {
  final nonceClient = _nonce();
  final incoming = StreamIterator(c.messages);
  try {
    c.send(MuxMessage(MuxType.hello, fields: {
      'protocol': kMuxProtocol, 'app': app, 'role': role, 'nonce': nonceClient,
    }));
    final hello = await _next(incoming, MuxType.hello, timeout);
    final nonceDaemon = hello.get<Uint8List>('nonce');
    if (nonceDaemon == null ||
        !_same(daemonProof(secret, nonceClient, nonceDaemon), hello.get<Uint8List>('proof'))) {
      throw const MuxHandshakeException('daemon proof');
    }
    c.send(MuxMessage(MuxType.auth, fields: {
      'proof': clientProof(secret, nonceDaemon, nonceClient),
    }));
    await _next(incoming, MuxType.ready, timeout);
    return MuxPeerInfo(
      protocol: hello.get<int>('protocol') ?? -1,
      app: hello.get<String>('app') ?? '',
      instance: hello.get<String>('instance'),
      pid: hello.get<int>('pid'),
      sessions: hello.get<int>('sessions'),
      caps: [for (final c in hello.get<List<Object?>>('caps') ?? const []) '$c'],
    );
  } on MuxHandshakeException {
    await c.close();
    rethrow;
  } finally {
    // Hands the stream back: later messages go to the caller's listener.
    await incoming.cancel();
  }
}

/// D6, daemon side. Returns the client's info; throws (and closes) on a
/// wrong proof or timeout.
Future<MuxPeerInfo> serverHandshake(
  MuxConnection c, {
  required Uint8List secret,
  required MuxPeerInfo self,
  Duration timeout = const Duration(seconds: 2),
}) async {
  final incoming = StreamIterator(c.messages);
  try {
    final hello = await _next(incoming, MuxType.hello, timeout);
    final nonceClient = hello.get<Uint8List>('nonce');
    if (nonceClient == null || nonceClient.length != 32) {
      throw const MuxHandshakeException('client nonce');
    }
    final nonceDaemon = _nonce();
    c.send(MuxMessage(MuxType.hello, fields: {
      'protocol': self.protocol, 'app': self.app, 'nonce': nonceDaemon,
      'proof': daemonProof(secret, nonceClient, nonceDaemon),
      'instance': self.instance, 'pid': self.pid, 'sessions': self.sessions,
      'caps': self.caps,
    }));
    final auth = await _next(incoming, MuxType.auth, timeout);
    if (!_same(clientProof(secret, nonceDaemon, nonceClient), auth.get<Uint8List>('proof'))) {
      throw const MuxHandshakeException('client proof');
    }
    c.send(const MuxMessage(MuxType.ready));
    return MuxPeerInfo(
      protocol: hello.get<int>('protocol') ?? -1,
      app: hello.get<String>('app') ?? '',
      role: hello.get<String>('role'),
    );
  } on MuxHandshakeException {
    await c.close();
    rethrow;
  } finally {
    await incoming.cancel();
  }
}

Future<MuxMessage> _next(StreamIterator<MuxMessage> it, String type, Duration timeout) async {
  final bool more;
  try {
    more = await it.moveNext().timeout(timeout);
  } on TimeoutException {
    throw const MuxHandshakeException('timeout');
  }
  if (!more || it.current.type != type) {
    throw MuxHandshakeException('expected $type');
  }
  return it.current;
}
```

Because `StreamIterator.cancel` cancels the underlying subscription, `MuxConnection.messages` must be a **broadcast-safe re-listenable** stream: implement `messages` in every transport as a broadcast stream that buffers nothing (handshake happens before the caller listens; the caller attaches its listener synchronously after the handshake future completes, and the peer sends nothing unsolicited before `ready` + the first request). Document this on the interface.

`mux_transport.dart` (interface + memory pair in this task):

```dart
import 'dart:async';
import 'dart:typed_data';

import 'mux_messages.dart';

/// A5b D4: one authenticated-later link. [messages] is a broadcast stream
/// (the handshake listens first, the session layer after it).
abstract interface class MuxConnection {
  Stream<MuxMessage> get messages;
  void send(MuxMessage message);
  Future<void> close();
  Future<void> get done;
}

/// Byte-faithful in-memory pair (every message is framed and decoded).
final class MemoryMuxTransport {
  static (MuxConnection, MuxConnection) pair() {
    final a = _MemoryConnection(), b = _MemoryConnection();
    a._peer = b;
    b._peer = a;
    return (a, b);
  }
}

final class _MemoryConnection implements MuxConnection {
  late _MemoryConnection _peer;
  final _in = StreamController<MuxMessage>.broadcast();
  final _decoder = MuxFrameDecoder();
  final _done = Completer<void>();
  bool _closed = false;

  @override
  Stream<MuxMessage> get messages => _in.stream;

  @override
  void send(MuxMessage message) {
    if (_closed || _peer._closed) return;
    final frame = encodeMux(message);
    scheduleMicrotask(() => _peer._receive(frame));
  }

  void _receive(Uint8List bytes) {
    if (_closed) return;
    try {
      for (final m in _decoder.add(bytes)) {
        _in.add(m);
      }
    } on FormatException {
      unawaited(close());
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _in.close();
    if (!_done.isCompleted) _done.complete();
    unawaited(_peer.close());
  }

  @override
  Future<void> get done => _done.future;
}
```

Exports in `shellx_agent.dart`: `src/mux/mux_messages.dart`, `src/mux/mux_handshake.dart`, `src/mux/mux_transport.dart`.

- [ ] **Step 4: Run tests** — `dart test test/mux` → PASS; full `dart test` green.

- [ ] **Step 5: Format, analyze, commit**

```bash
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart format --set-exit-if-changed lib/src/mux test/mux && ~/fvm/versions/3.41.4/bin/dart analyze && cd ../..
git add packages/shellx_agent/lib/src/mux packages/shellx_agent/lib/shellx_agent.dart packages/shellx_agent/test/mux
git commit -m "feat(agent): mux wire — framed CBOR messages and mutual HMAC handshake (A5b D6, D7, D9)"
```

---

### Task 3: Endpoint file and transports — Unix socket (macOS), named pipe (Windows ⚠) (D4, D5)

**Files:**
- Create: `packages/shellx_agent/lib/src/mux/mux_endpoint.dart`
- Modify: `packages/shellx_agent/lib/src/mux/mux_transport.dart` (`MuxListener`, `MuxTransport`, `UnixMuxTransport`, `socketPathFor`, `StreamMuxConnection`)
- Create: `apps/desktop/lib/src/mux/windows_pipe_transport.dart`
- Test: `packages/shellx_agent/test/mux/mux_endpoint_test.dart`, `packages/shellx_agent/test/mux/unix_mux_transport_test.dart`, `apps/desktop/test/mux/windows_pipe_transport_test.dart` (`testOn: 'windows'`)

**Interfaces:**
- Consumes: Task 2 (`MuxConnection`, `MuxFrameDecoder`, `encodeMux`); `EndpointFile` patterns (temp + chmod + rename).
- Produces:
  - `final class MuxEndpointInfo { const MuxEndpointInfo({required String address, required Uint8List secret, required int pid, required String instance, required int protocol, required String app}); String format(); static MuxEndpointInfo? parse(String text); }`
  - `final class MuxEndpointFile { MuxEndpointFile(String path, {bool? posix}); Future<String> write(MuxEndpointInfo info); Future<MuxEndpointInfo?> read(); Future<void> deleteIfOwned(String contents); }`
  - `abstract interface class MuxListener { Stream<MuxConnection> get connections; Future<void> close(); String get address; }`
  - `abstract interface class MuxTransport { Future<MuxListener> listen(String address); Future<MuxConnection> connect(String address, {Duration timeout}); }`
  - `String socketPathFor({required String muxDirectory, required String tmpDirectory, required int uid})` (≤ 103 bytes else `$TMPDIR/shellx-mux-<uid>.sock`)
  - `final class UnixMuxTransport implements MuxTransport` (chmod 0600 after bind; removes a stale socket file before bind)
  - `final class StreamMuxConnection implements MuxConnection` wrapping any `Stream<Uint8List>` + `void Function(Uint8List)` sink (used by Unix and Windows)
  - Desktop: `final class WindowsPipeTransport implements MuxTransport` and `String pipeNameForUser(String sid)` → `\\.\pipe\shellx-mux-<first 16 hex of sha256(sid)>`

- [ ] **Step 1: Write the failing tests**

`mux_endpoint_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('mux_ep'));
  tearDown(() => dir.delete(recursive: true));

  final info = MuxEndpointInfo(
    address: '/tmp/x.sock', secret: Uint8List.fromList(List.filled(32, 0xab)),
    pid: 42, instance: 'f' * 32, protocol: 1, app: '1.6.0',
  );

  test('format/parse round trip; exact text', () {
    expect(info.format(),
        'v=1\naddress=/tmp/x.sock\nsecret=${'ab' * 32}\npid=42\ninstance=${'f' * 32}\nprotocol=1\napp=1.6.0\n');
    final back = MuxEndpointInfo.parse(info.format())!;
    expect(back.secret, info.secret);
    expect(MuxEndpointInfo.parse('v=2\n'), isNull);
    expect(MuxEndpointInfo.parse('garbage'), isNull);
  });

  test('written 0600 in a 0700 dir; deleteIfOwned', () async {
    final file = MuxEndpointFile('${dir.path}/mux/endpoint');
    final contents = await file.write(info);
    String mode(String p) => (Process.runSync('stat', ['-f', '%Lp', p]).stdout as String).trim();
    expect(mode('${dir.path}/mux'), '700');
    expect(mode('${dir.path}/mux/endpoint'), '600');
    expect((await file.read())!.pid, 42);
    await file.deleteIfOwned('other');
    expect(File('${dir.path}/mux/endpoint').existsSync(), isTrue);
    await file.deleteIfOwned(contents);
    expect(File('${dir.path}/mux/endpoint').existsSync(), isFalse);
  }, testOn: 'mac-os');
}
```

`unix_mux_transport_test.dart`:

```dart
import 'dart:io';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('mux_t'));
  tearDown(() => dir.delete(recursive: true));

  test('long paths fall back to TMPDIR', () {
    expect(socketPathFor(muxDirectory: '/a/mux', tmpDirectory: '/t/', uid: 501), '/a/mux/mux.sock');
    final long = '/${'x' * 100}';
    expect(socketPathFor(muxDirectory: long, tmpDirectory: '/t/', uid: 501), '/t/shellx-mux-501.sock');
  });

  test('socket is 0600; messages flow both ways; a stale file is replaced', () async {
    final path = '${dir.path}/mux.sock';
    File(path).writeAsStringSync('stale');
    final t = UnixMuxTransport();
    final listener = await t.listen(path);
    expect((Process.runSync('stat', ['-f', '%Lp', path]).stdout as String).trim(), '600');
    final serverSide = listener.connections.first;
    final client = await t.connect(path);
    final server = await serverSide;
    final got = server.messages.first;
    client.send(const MuxMessage(MuxType.daemonStatus, q: 1));
    expect((await got).q, 1);
    final back = client.messages.first;
    server.send(const MuxMessage(MuxType.result, q: 1));
    expect((await back).type, MuxType.result);
    await client.close();
    await server.done;
    await listener.close();
  }, testOn: 'mac-os || linux');

  test('connect to nothing fails fast', () async {
    await expectLater(
      UnixMuxTransport().connect('${dir.path}/none.sock', timeout: const Duration(milliseconds: 300)),
      throwsA(isA<SocketException>()),
    );
  }, testOn: 'mac-os || linux');
}
```

`apps/desktop/test/mux/windows_pipe_transport_test.dart` (`@TestOn('windows')`): pipe name derivation (pure, runs everywhere — put it in a separate non-`TestOn` test), then listen/connect/round trip, a second `listen` on the same name fails (`FILE_FLAG_FIRST_PIPE_INSTANCE`), and the pipe's security descriptor (read with `GetSecurityInfo`) has exactly one ACE for the current user SID.

- [ ] **Step 2: Run tests to verify they fail.**

- [ ] **Step 3: Implement**

`mux_endpoint.dart` — mirror `EndpointFile` (`term_endpoint.dart`) exactly for write (dir create, `chmod 700` dir, empty temp, `chmod 600` temp, write, rename) and `deleteIfOwned`; `format()` produces the seven lines shown in the test; `parse` requires `v=1` and all keys, `secret` 64 hex → 32 bytes (`hexToBytes` from `shellx_core`), returns null on anything else.

`mux_transport.dart` additions:

```dart
abstract interface class MuxListener {
  Stream<MuxConnection> get connections;
  String get address;
  Future<void> close();
}

abstract interface class MuxTransport {
  Future<MuxListener> listen(String address);
  Future<MuxConnection> connect(String address, {Duration timeout = const Duration(seconds: 1)});
}

/// `sun_path` is 104 bytes on macOS (103 + NUL).
String socketPathFor({required String muxDirectory, required String tmpDirectory, required int uid}) {
  final preferred = '$muxDirectory/mux.sock';
  if (utf8.encode(preferred).length <= 103) return preferred;
  final tmp = tmpDirectory.endsWith('/') ? tmpDirectory : '$tmpDirectory/';
  return '${tmp}shellx-mux-$uid.sock';
}

/// Frames over any byte stream (Unix socket, Windows pipe isolate).
final class StreamMuxConnection implements MuxConnection {
  StreamMuxConnection(Stream<Uint8List> input, this._write, this._closeSink) {
    _sub = input.listen(
      (bytes) {
        try {
          for (final m in _decoder.add(bytes)) {
            _in.add(m);
          }
        } on FormatException {
          unawaited(close()); // D26: garbage closes the link
        }
      },
      onDone: () => unawaited(close()),
      onError: (Object _) => unawaited(close()),
    );
  }

  final void Function(Uint8List bytes) _write;
  final Future<void> Function() _closeSink;
  final _in = StreamController<MuxMessage>.broadcast();
  final _decoder = MuxFrameDecoder();
  final _done = Completer<void>();
  late final StreamSubscription<Uint8List> _sub;
  bool _closed = false;

  @override
  Stream<MuxMessage> get messages => _in.stream;

  @override
  void send(MuxMessage message) {
    if (!_closed) _write(encodeMux(message));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub.cancel();
    await _closeSink();
    await _in.close();
    _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}

final class UnixMuxTransport implements MuxTransport {
  @override
  Future<MuxListener> listen(String address) async {
    final stale = File(address);
    if (await stale.exists()) await stale.delete();
    final server = await ServerSocket.bind(
      InternetAddress(address, type: InternetAddressType.unix), 0);
    final chmod = await Process.run('/bin/chmod', ['600', address]);
    if (chmod.exitCode != 0) {
      await server.close();
      throw FileSystemException('chmod 600 failed', address);
    }
    return _UnixListener(server, address);
  }

  @override
  Future<MuxConnection> connect(String address, {Duration timeout = const Duration(seconds: 1)}) async {
    final socket = await Socket.connect(
      InternetAddress(address, type: InternetAddressType.unix), 0, timeout: timeout);
    return _wrap(socket);
  }

  static MuxConnection _wrap(Socket s) => StreamMuxConnection(
    s, s.add, () async { await s.close(); s.destroy(); });
}

final class _UnixListener implements MuxListener {
  _UnixListener(this._server, this.address);
  final ServerSocket _server;
  @override
  final String address;
  @override
  Stream<MuxConnection> get connections => _server.map(UnixMuxTransport._wrap);
  @override
  Future<void> close() async {
    await _server.close();
    try { await File(address).delete(); } on FileSystemException { /* gone */ }
  }
}
```

(add imports `dart:convert`, `dart:io`.)

`apps/desktop/lib/src/mux/windows_pipe_transport.dart` — FFI via `package:win32`:
- Name: `pipeNameForUser(sid)` = `r'\\.\pipe\shellx-mux-' + sha256(utf8(sid)).hex.substring(0, 16)`; SID string from `OpenProcessToken` + `GetTokenInformation(TokenUser)` + `ConvertSidToStringSid`.
- Security: `ConvertStringSecurityDescriptorToSecurityDescriptor('D:P(A;;GA;;;<SID>)')` into `SECURITY_ATTRIBUTES`.
- Listen: a helper isolate loops `CreateNamedPipe(name, PIPE_ACCESS_DUPLEX | (first ? FILE_FLAG_FIRST_PIPE_INSTANCE : 0), PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS, PIPE_UNLIMITED_INSTANCES, 65536, 65536, 0, sa)` → `ConnectNamedPipe` (blocking) → spawns a per-connection isolate that loops `ReadFile` into 64 KiB buffers and posts `Uint8List`s through a `SendPort`; writes are posted to the connection isolate's `ReceivePort`, which calls `WriteFile` (blocking, in order). A failed first `CreateNamedPipe` with `ERROR_ACCESS_DENIED`/`ERROR_PIPE_BUSY` → `listen` throws `StateError('pipe name taken')` (D4: squatter).
- Connect: `WaitNamedPipe(name, timeoutMs)` then `CreateFile(name, GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING, 0, 0)` in a connection isolate as above; failure → `SocketException('pipe unavailable')`.
- Close: `CloseHandle` from the owning isolate; the reader loop ends on `ERROR_BROKEN_PIPE`.
- Both sides wrap bytes with `StreamMuxConnection`.

Keep the FFI code in this one file with a doc comment block listing each Win32 call and why; any API missing from `win32` 5.15 is bound with `DynamicLibrary.open('kernel32.dll').lookupFunction`.

- [ ] **Step 4: Run tests** — agent `dart test test/mux` PASS on macOS; desktop suite green (Windows tests skipped on macOS).

- [ ] **Step 5: ⚠ MANUAL (Windows):** run `flutter test test/mux/windows_pipe_transport_test.dart` on Windows; then from PowerShell: `[System.IO.Directory]::GetFiles('\\.\pipe\') | Select-String shellx-mux` while the test listener runs, and `(Get-Acl -Path "\\.\pipe\shellx-mux-…").Access` (or the test's `GetSecurityInfo` output) shows only the user. Record in the ledger. If named pipes prove unworkable, apply the spec D4 fallback (loopback TCP + same handshake): implement `LoopbackMuxTransport` in `packages/shellx_agent/lib/src/mux/mux_transport.dart` (bind `127.0.0.1:0`, address `tcp:<port>`), record the ruling, and continue.

- [ ] **Step 6: Format, analyze, commit**

```bash
git add packages/shellx_agent/lib/src/mux packages/shellx_agent/test/mux apps/desktop/lib/src/mux/windows_pipe_transport.dart apps/desktop/test/mux/windows_pipe_transport_test.dart
git commit -m "feat(mux): endpoint file, Unix socket transport (0600, TMPDIR fallback), Windows named pipe transport (A5b D4, D5)"
```

---

### Task 4: `MuxServer` — sessions and views over the wire, ack window, roles, status, quit (D8–D11, D23, D26)

**Files:**
- Create: `packages/shellx_agent/lib/src/mux/mux_server.dart`
- Test: `packages/shellx_agent/test/mux/mux_server_test.dart`

**Interfaces:**
- Consumes: Tasks 2–3; `LocalSessions`, `LocalSessionView`, `SessionLimitException`, `SpawnFailedException`; `SessionRig` (tests).
- Produces:
  - `abstract interface class AgentBridge { Stream<Map<String, Object?>> get states; Map<String, Object?> get current; Future<Object?> call(String method, Map<String, Object?> args); }`
  - `final class MuxServer { MuxServer({required LocalSessions sessions, required Uint8List secret, required MuxPeerInfo self, AgentBridge? agent, required Future<void> Function() onQuit, void Function(bool uiAttached)? onUiChanged, int stopAbove = 2097152, int resumeBelow = 524288, Duration coalesce = const Duration(milliseconds: 16)}); void serve(MuxListener listener); bool get uiAttached; Future<void> close(); }`
  - Wire behaviour (requests answer `result`/`error` with the same `q`):
    - `sessions.list` → `result{sessions: [...]}`; event `sessions.changed{sessions}` on `LocalSessions.changes` (coalesced 16 ms). **Nothing is sent unsolicited** before the client's first request (the client attaches its listener only after the handshake returns).
    - `agent.get` → `result{state}` (current `AgentViewState` wire map, or null without a bridge).
    - `sessions.open{cols, rows, cwd?}` → `result{id}` | `error{session_limit, max}` | `error{spawn_failed, message}`.
    - `sessions.close{id}`, `sessions.watchPorts{visible}` → `result{}`.
    - `sessions.notice` events from `LocalSessions.notices`.
    - `view.open{id}` → `result{}`, then `view.out{id, data}` (backlog first, chunks ≤ 61,440), `view.driver{id, side}`, `view.exit{id, code, onRequest}`; unknown id → `view.exit{id, code: -1, onRequest: true}`.
    - `view.write|reply{id, data}`, `view.resize{id, cols, rows}`, `view.close{id}` → no reply. `view.ack{id, bytes}` → window accounting.
    - `daemon.status` → `result{sessions: n, instance, app, protocol}` (allowed before a role check: frozen).
    - `daemon.quit` → calls `onQuit` and answers `result{}` after it returns.
    - `agent.call{m, a}` → `result{value}` | `error{internal, message}`; `agent.state{state}` events from `AgentBridge.states`.
    - Role `ui`: one at a time (second → `error{busy}` + close). Role `cli` or other → `error{unsupported_role}` + close.
    - Unknown request type with `q` → `error{unknown_type}`; unknown event without `q` → ignored.

- [ ] **Step 1: Write the failing tests** (`mux_server_test.dart`, using `SessionRig`, `MemoryMuxTransport.pair()` and a tiny `TestListener implements MuxListener` that yields connections you push):

```dart
// helpers
Future<MuxConnection> attach(MuxServer server, TestListener l, {String role = 'ui'}) async {
  final (client, daemonSide) = MemoryMuxTransport.pair();
  l.push(daemonSide);
  await clientHandshake(client, secret: secret, app: '1.6.0', role: role);
  return client;
}
Future<MuxMessage> request(MuxConnection c, MuxMessage m) {
  final reply = c.messages.firstWhere((r) => r.q == m.q && (r.type == MuxType.result || r.type == MuxType.error));
  c.send(m);
  return reply;
}
```

Tests (each a `test(...)` with full assertions):
1. `sessions.list after ready returns the current list; a later open fires sessions.changed` — rig opens one session first; `result.sessions` length 1, `summaryFromWire` id matches; no message arrives before the first request.
2. `sessions.open → result{id}; PTY started with cwd` — `rig.factory` records `workingDirectory` (`'/Users/test'` home when cwd null).
3. `session limit and spawn failure become typed errors` — `SessionRig(maxSessions: 1)`; second open → `error{code: session_limit, max: 1}`; `rig.factory.failNext = true` → `spawn_failed`.
4. `view.open streams backlog then live output, then exit` — rig session prints `"abc"` before `view.open`; collect `view.out` data → `"abc"`; print `"def"` → next `view.out`; end shell with 3 → `view.exit{code: 3, onRequest: false}`.
5. `view.write reaches the PTY and makes the desktop drive` — `rig.pty(0).written` contains bytes; `view.driver{side: desktop}` observed.
6. `ack window: stops above 2 MiB unacked, resets below 512 KiB (D11)` — `MuxServer(stopAbove: 1000, resumeBelow: 200)`; print 3 × 600 bytes without acks → client receives ≤ 1,600 bytes of `view.out` then nothing for a 4th print; send `view.ack{bytes: 1500}` → client receives `view.reset{data}` whose `data` equals the session's current ring-buffer contents, then live output resumes.
7. `a second ui is refused busy; cli is unsupported (D8)`.
8. `unknown request → unknown_type; unknown event ignored; garbage closes` — send `MuxMessage('x.y', q: 9)` → `error{unknown_type}`; send `MuxMessage('x.z')` → no reply, connection open; then push raw bytes `[0,0,0,1,0xff]` on a `StreamMuxConnection` pair → `done` completes.
9. `daemon.status answers sessions count; daemon.quit runs onQuit then answers` — `onQuit` completer observed before `result`.
10. `agent.get returns the current state; agent.state on change; agent.call forwards` — fake `AgentBridge`.
11. `a closed UI connection disposes its views; the session keeps running` — after `client.close()`, `rig.manager.sessions` still has the session; `server.uiAttached` false; `onUiChanged(false)` called.
12. `handshake with a wrong secret never reaches the session layer` — no `sessions.changed` delivered, connection closed.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement `mux_server.dart`**

```dart
import 'dart:async';
import 'dart:typed_data';

import '../session/local_sessions.dart';
import '../term/term_frames.dart';
import 'mux_handshake.dart';
import 'mux_messages.dart';
import 'mux_transport.dart';

abstract interface class AgentBridge {
  Stream<Map<String, Object?>> get states;
  Map<String, Object?> get current;
  Future<Object?> call(String method, Map<String, Object?> args);
}

/// A5b §3.1: serves one [LocalSessions] to authenticated local clients.
final class MuxServer {
  MuxServer({
    required this.sessions,
    required Uint8List secret,
    required MuxPeerInfo self,
    this.agent,
    required this.onQuit,
    this.onUiChanged,
    this.stopAbove = 2097152,
    this.resumeBelow = 524288,
    this.coalesce = const Duration(milliseconds: 16),
  }) : _secret = secret,
       _self = self;

  final LocalSessions sessions;
  final AgentBridge? agent;
  final Future<void> Function() onQuit;
  final void Function(bool uiAttached)? onUiChanged;
  final int stopAbove, resumeBelow;
  final Duration coalesce;
  final Uint8List _secret;
  final MuxPeerInfo _self;
  final _links = <_ClientLink>{};
  StreamSubscription<MuxConnection>? _accept;
  int _handshaking = 0;
  _ClientLink? _ui;

  bool get uiAttached => _ui != null;

  void serve(MuxListener listener) {
    _accept = listener.connections.listen(_onConnection);
  }

  Future<void> _onConnection(MuxConnection c) async {
    if (_handshaking >= 4) {
      await c.close(); // D23
      return;
    }
    _handshaking++;
    MuxPeerInfo peer;
    try {
      peer = await serverHandshake(
        c,
        secret: _secret,
        self: MuxPeerInfo(
          protocol: _self.protocol, app: _self.app, instance: _self.instance,
          pid: _self.pid, sessions: sessions.sessions.length, caps: _self.caps,
        ),
      );
    } on MuxHandshakeException {
      return;
    } finally {
      _handshaking--;
    }
    if (peer.role != 'ui') {
      c.send(const MuxMessage(MuxType.error, fields: {'code': MuxError.unsupportedRole}));
      await c.close();
      return;
    }
    if (_ui != null) {
      c.send(const MuxMessage(MuxType.error, fields: {'code': MuxError.busy}));
      await c.close();
      return;
    }
    final link = _ClientLink(this, c);
    _links.add(link);
    _ui = link;
    onUiChanged?.call(true);
    unawaited(c.done.then((_) {
      link.dispose();
      _links.remove(link);
      if (identical(_ui, link)) {
        _ui = null;
        onUiChanged?.call(false);
      }
    }));
    link.start();
  }

  Future<void> close() async {
    await _accept?.cancel();
    for (final l in [..._links]) {
      await l.connection.close();
    }
  }
}

final class _ViewLink {
  _ViewLink(this.view);
  LocalSessionView view;
  StreamSubscription<Uint8List>? out;
  StreamSubscription<Object?>? driver;
  int unacked = 0;
  bool paused = false;
}

final class _ClientLink {
  _ClientLink(this.server, this.connection);
  final MuxServer server;
  final MuxConnection connection;
  final _views = <int, _ViewLink>{};
  final _subs = <StreamSubscription<Object?>>[];
  Timer? _changedTimer;

  void start() {
    _subs
      ..add(connection.messages.listen(_onMessage))
      ..add(server.sessions.changes.listen((_) => _scheduleChanged()))
      ..add(server.sessions.notices.listen((n) =>
          connection.send(MuxMessage(MuxType.sessionsNotice, fields: noticeToWire(n)))));
    final agent = server.agent;
    if (agent != null) {
      _subs.add(agent.states.listen((s) =>
          connection.send(MuxMessage(MuxType.agentState, fields: {'state': s}))));
    }
    // Nothing unsolicited before the client's first request: the client
    // starts listening only after the handshake returns, so it asks for
    // the current list (`sessions.list`) and agent state (`agent.get`).
  }

  void _scheduleChanged() {
    _changedTimer ??= Timer(server.coalesce, () {
      _changedTimer = null;
      _sendChanged();
    });
  }

  void _sendChanged() => connection.send(MuxMessage(MuxType.sessionsChanged, fields: {
    'sessions': [for (final s in server.sessions.sessions) summaryToWire(s)],
  }));

  void _reply(int? q, [Map<String, Object?> fields = const {}]) {
    if (q != null) connection.send(MuxMessage(MuxType.result, q: q, fields: fields));
  }

  void _error(int? q, String code, [String? message]) {
    if (q != null) {
      connection.send(MuxMessage(MuxType.error, q: q, fields: {'code': code, 'message': ?message}));
    }
  }

  Future<void> _onMessage(MuxMessage m) async {
    final q = m.q;
    try {
      switch (m.type) {
        case MuxType.daemonStatus:
          _reply(q, {
            'sessions': server.sessions.sessions.length,
            'instance': server._self.instance, 'app': server._self.app,
            'protocol': server._self.protocol,
          });
        case MuxType.daemonQuit:
          await server.onQuit();
          _reply(q);
        case MuxType.sessionsList:
          _reply(q, {'sessions': [for (final s in server.sessions.sessions) summaryToWire(s)]});
        case MuxType.sessionsOpen:
          final id = await server.sessions.open(
            cols: m.get<int>('cols')!, rows: m.get<int>('rows')!, cwd: m.get<String>('cwd'));
          _reply(q, {'id': id});
        case MuxType.sessionsClose:
          server.sessions.close(m.get<int>('id')!);
          _reply(q);
        case MuxType.sessionsWatchPorts:
          server.sessions.watchPorts(m.get<bool>('visible')!);
          _reply(q);
        case MuxType.viewOpen:
          _openView(m.get<int>('id')!);
          _reply(q);
        case MuxType.viewWrite:
          _views[m.get<int>('id')]?.view.write(m.get<Uint8List>('data')!);
        case MuxType.viewReply:
          _views[m.get<int>('id')]?.view.reply(m.get<Uint8List>('data')!);
        case MuxType.viewResize:
          _views[m.get<int>('id')]?.view.resize(m.get<int>('cols')!, m.get<int>('rows')!);
        case MuxType.viewAck:
          _ack(m.get<int>('id')!, m.get<int>('bytes')!);
        case MuxType.viewClose:
          _closeView(m.get<int>('id')!);
        case MuxType.agentGet:
          _reply(q, {'state': server.agent?.current});
        case MuxType.agentCall:
          final agent = server.agent;
          if (agent == null) {
            _error(q, MuxError.unknownType);
            return;
          }
          final value = await agent.call(
            m.get<String>('m')!,
            {for (final e in (m.get<Map<Object?, Object?>>('a') ?? const {}).entries) '${e.key}': e.value},
          );
          _reply(q, {'value': value});
        default:
          _error(q, MuxError.unknownType);
      }
    } on SessionLimitException catch (e) {
      _error(q, MuxError.sessionLimit, '${e.max}');
    } on SpawnFailedException catch (e) {
      _error(q, MuxError.spawnFailed, e.message);
    } on TypeError {
      _error(q, MuxError.badRequest); // a missing or mistyped field
    } on Object catch (e) {
      _error(q, MuxError.internal, e.runtimeType.toString());
    }
  }

  void _openView(int id) {
    _closeView(id);
    final LocalSessionView view;
    try {
      view = server.sessions.view(id);
    } on StateError {
      connection.send(MuxMessage(MuxType.viewExit, fields: {'id': id, 'code': -1, 'onRequest': true}));
      return;
    }
    final link = _ViewLink(view);
    _views[id] = link;
    _sendOut(id, link, view.backlog);
    _listen(id, link);
    link.driver = view.driver.listen((side) =>
        connection.send(MuxMessage(MuxType.viewDriver, fields: {'id': id, 'side': side.wire})));
    unawaited(view.exitCode.then((code) {
      if (_views[id] != link) return;
      connection.send(MuxMessage(MuxType.viewExit,
          fields: {'id': id, 'code': code, 'onRequest': view.closedOnRequest}));
    }));
  }

  void _listen(int id, _ViewLink link) {
    link.out = link.view.output.listen((bytes) {
      if (link.paused) return; // D11: dropped; the reset carries the ring buffer
      _sendOut(id, link, bytes);
      if (link.unacked > server.stopAbove) link.paused = true;
    });
  }

  void _sendOut(int id, _ViewLink link, Uint8List bytes) {
    for (var i = 0; i < bytes.length; i += kTermMaxChunk) {
      final end = i + kTermMaxChunk < bytes.length ? i + kTermMaxChunk : bytes.length;
      final piece = Uint8List.sublistView(bytes, i, end);
      link.unacked += piece.length;
      connection.send(MuxMessage(MuxType.viewOut, fields: {'id': id, 'data': piece}));
    }
  }

  void _ack(int id, int bytes) {
    final link = _views[id];
    if (link == null) return;
    link.unacked = (link.unacked - bytes).clamp(0, 1 << 62);
    if (link.paused && link.unacked < server.resumeBelow) {
      // A fresh view: its backlog is the ring buffer now (D11).
      unawaited(link.out?.cancel());
      link.view.dispose();
      final LocalSessionView fresh;
      try {
        fresh = server.sessions.view(id);
      } on StateError {
        return; // ended meanwhile: view.exit already went out
      }
      link
        ..view = fresh
        ..paused = false
        ..unacked = 0;
      final data = fresh.backlog;
      link.unacked += data.length;
      connection.send(MuxMessage(MuxType.viewReset, fields: {'id': id, 'data': data}));
      _listen(id, link);
    }
  }

  void _closeView(int id) {
    final link = _views.remove(id);
    if (link == null) return;
    unawaited(link.out?.cancel());
    unawaited(link.driver?.cancel());
    link.view.dispose();
  }

  void dispose() {
    _changedTimer?.cancel();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    for (final id in [..._views.keys]) {
      _closeView(id);
    }
  }
}
```

`view.reset` data may exceed one frame (ring buffer 256 KiB): send it as `view.reset{id}` followed by `view.out` chunks instead — change the reset send to `connection.send(MuxMessage(MuxType.viewReset, fields: {'id': id})); _sendOut(id, link, data);` and adjust test 6 to read the reset marker and the following `view.out` chunks. Export `mux_server.dart` from `shellx_agent.dart`.

- [ ] **Step 4: Run tests** — `dart test test/mux` PASS; full agent suite green.

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_agent/lib/src/mux/mux_server.dart packages/shellx_agent/lib/shellx_agent.dart packages/shellx_agent/test/mux/mux_server_test.dart
git commit -m "feat(mux): MuxServer — sessions/views over the wire, ack window with reset, one UI, status and quit (A5b D8-D11, D26)"
```

---

### Task 5: `RemoteLocalSessions` + contract test suite (D10, D11, D28)

**Files:**
- Create: `packages/shellx_agent/lib/src/mux/remote_local_sessions.dart`
- Create: `packages/shellx_agent/test/support/local_sessions_contract.dart`
- Create: `packages/shellx_agent/test/session/local_sessions_contract_test.dart`
- Modify: `packages/shellx_agent/lib/src/session/local_sessions.dart` (doc of `backlog`, `view`)
- Modify: `packages/shellx_agent/lib/shellx_agent.dart`

**Interfaces:**
- Consumes: Tasks 2–4.
- Produces:
  - `final class MuxClient { MuxClient(MuxConnection c); Future<MuxMessage> request(String type, [Map<String, Object?> fields]); void send(String type, [Map<String, Object?> fields]); Stream<MuxMessage> get events; Future<void> get done; Future<void> close(); }` — `request` completes with the `result` message or throws `MuxRemoteException(code, message)`; all pending requests fail with `MuxRemoteException('disconnected')` when the connection ends.
  - `final class MuxRemoteException implements Exception { const MuxRemoteException(this.code, [this.message]); }`
  - `final class RemoteLocalSessions implements LocalSessions { RemoteLocalSessions(MuxClient client, {int ackEvery = 65536, Duration ackDelay = const Duration(milliseconds: 100)}); Future<void> get ready; /* completes when the first sessions.list answer arrives */ bool get connected; }`
  - `RemoteSessionView implements LocalSessionView` — `backlog` is empty; on `view.reset` it emits a `Uint8List` of `'\r\n\x1b[H\x1b[2J'` before the reset data (D11).
  - `Future<void> runLocalSessionsContract(String name, Future<LocalSessionsHarness> Function() make)` in `test/support/local_sessions_contract.dart`, where `LocalSessionsHarness { LocalSessions get sessions; SessionRig get rig; Future<void> dispose(); }`.

- [ ] **Step 1: Write the failing tests**

`local_sessions_contract.dart` — one `group(name, …)` with these tests, written only against `LocalSessions`/`LocalSessionView` and `harness.rig` (fake PTYs):
1. `open → listed in sessions and changes fires` (`await sessions.changes.first` after `open`, `sessions.single.origin == desktop`).
2. `open(cwd:) uses the directory when it exists` (rig `directoryExists` returns true for `/w`).
3. `backlog + output carry everything printed, in order` — print `"one"` before `view`, `"two"` after; concatenating `backlog` and the `output` chunks gives `"onetwo"` (works whether `backlog` is empty or not — that is the D10 contract).
4. `write reaches the PTY; resize reaches the PTY` (`rig.pty(0).written`, `.size`).
5. `driver stream reports desktop after a write`.
6. `exitCode completes with the shell's code; closedOnRequest false`; `close(id)` → exit with `closedOnRequest` true.
7. `limit → SessionLimitException`; `spawn failure → SpawnFailedException`.
8. `notices: an OSC 9 from the shell arrives as a SessionNotice` (`rig.pty(0).emit('\x1b]9;hi\x07')`).
9. `view of an unknown id ends at once or throws StateError` — accept either (spec "Sửa LocalSessions").

`local_sessions_contract_test.dart`:

```dart
void main() {
  runLocalSessionsContract('in-process SessionManager', () async {
    final rig = SessionRig(maxSessions: 2);
    return LocalSessionsHarness(rig.manager, rig, () async {});
  });
  runLocalSessionsContract('RemoteLocalSessions over MuxServer', () async {
    final rig = SessionRig(maxSessions: 2);
    final listener = TestListener();
    final server = MuxServer(
      sessions: rig.manager, secret: secret,
      self: const MuxPeerInfo(protocol: 1, app: 't', instance: 'i'),
      onQuit: () async {},
    )..serve(listener);
    final (client, daemonSide) = MemoryMuxTransport.pair();
    listener.push(daemonSide);
    await clientHandshake(client, secret: secret, app: 't', role: 'ui');
    final remote = RemoteLocalSessions(MuxClient(client));
    await remote.ready;
    return LocalSessionsHarness(remote, rig, () async {
      await client.close();
      await server.close();
    });
  });
}
```

(move `TestListener` and `secret` from Task 4's test into `test/support/mux_fixtures.dart` and import it in both.)

Plus `remote_local_sessions_test.dart`:
- `pending requests fail with disconnected when the daemon goes`;
- `acks are sent after 64 KiB or 100 ms` (count `view.ack` messages with a spy connection);
- `view.reset writes clear-screen then the data` (server with tiny window from Task 4, collect `output` text: contains `'\r\n\x1b[H\x1b[2J'` followed by the ring-buffer text);
- `sessions getter mirrors sessions.changed synchronously after the event`.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement `remote_local_sessions.dart`**

Key parts (complete the obvious remainder exactly as specified in Interfaces):

```dart
final class MuxClient {
  MuxClient(this._c) {
    _sub = _c.messages.listen(_onMessage);
    unawaited(_c.done.then((_) => _failAll()));
  }
  final MuxConnection _c;
  late final StreamSubscription<MuxMessage> _sub;
  final _pending = <int, Completer<MuxMessage>>{};
  final _events = StreamController<MuxMessage>.broadcast(sync: true);
  var _next = 1;

  Stream<MuxMessage> get events => _events.stream;
  Future<void> get done => _c.done;

  Future<MuxMessage> request(String type, [Map<String, Object?> fields = const {}]) {
    final q = _next++;
    final c = Completer<MuxMessage>();
    _pending[q] = c;
    _c.send(MuxMessage(type, q: q, fields: fields));
    return c.future;
  }

  void send(String type, [Map<String, Object?> fields = const {}]) =>
      _c.send(MuxMessage(type, fields: fields));

  void _onMessage(MuxMessage m) {
    final waiting = m.q == null ? null : _pending.remove(m.q);
    if (waiting != null) {
      if (m.type == MuxType.error) {
        waiting.completeError(MuxRemoteException(m.get<String>('code') ?? MuxError.internal, m.get<String>('message')));
      } else {
        waiting.complete(m);
      }
      return;
    }
    _events.add(m);
  }

  void _failAll() {
    for (final c in _pending.values) {
      c.completeError(const MuxRemoteException('disconnected'));
    }
    _pending.clear();
    unawaited(_events.close());
  }

  Future<void> close() async {
    await _sub.cancel();
    await _c.close();
  }
}

final class RemoteLocalSessions implements LocalSessions {
  RemoteLocalSessions(this._client, {this.ackEvery = 65536, this.ackDelay = const Duration(milliseconds: 100)}) {
    _client.events.listen(_onEvent, onDone: () => _connected = false);
    // The first list comes from a request (the daemon sends nothing
    // unsolicited); `sessions.changed` keeps it current afterwards.
    unawaited(_client.request(MuxType.sessionsList).then((r) {
      _apply(r.get<List<Object?>>('sessions') ?? const []);
    }, onError: (Object _) {}));
  }

  void _apply(List<Object?> wire) {
    _sessions = List.unmodifiable([
      for (final s in wire) summaryFromWire(s! as Map<Object?, Object?>),
    ]);
    if (!_ready.isCompleted) _ready.complete();
    _changes.add(null);
  }
  final MuxClient _client;
  final int ackEvery;
  final Duration ackDelay;
  var _sessions = const <SessionSummary>[];
  final _changes = StreamController<void>.broadcast();
  final _notices = StreamController<SessionNotice>.broadcast();
  final _views = <int, RemoteSessionView>{};
  final _ready = Completer<void>();
  bool _connected = true;

  Future<void> get ready => _ready.future;
  bool get connected => _connected;

  @override
  List<SessionSummary> get sessions => _sessions;
  @override
  Stream<void> get changes => _changes.stream;
  @override
  Stream<SessionNotice> get notices => _notices.stream;

  @override
  Future<int> open({required int cols, required int rows, String? cwd}) async {
    try {
      final r = await _client.request(MuxType.sessionsOpen, {'cols': cols, 'rows': rows, 'cwd': ?cwd});
      return r.get<int>('id')!;
    } on MuxRemoteException catch (e) {
      throw switch (e.code) {
        MuxError.sessionLimit => SessionLimitException(int.tryParse(e.message ?? '') ?? 32),
        MuxError.spawnFailed => SpawnFailedException(e.message ?? ''),
        _ => SpawnFailedException(e.code),
      };
    }
  }

  @override
  LocalSessionView view(int id) {
    final v = RemoteSessionView._(this, id);
    _views[id]?._end(-1, onRequest: true);
    _views[id] = v;
    unawaited(_client.request(MuxType.viewOpen, {'id': id}).catchError((Object _) => const MuxMessage(MuxType.result)));
    return v;
  }

  @override
  void close(int id) => _client.send(MuxType.sessionsClose, {'id': id});

  @override
  void watchPorts(bool visible) => _client.send(MuxType.sessionsWatchPorts, {'visible': visible});

  void _onEvent(MuxMessage m) {
    switch (m.type) {
      case MuxType.sessionsChanged:
        _apply(m.get<List<Object?>>('sessions') ?? const []);
      case MuxType.sessionsNotice:
        _notices.add(noticeFromWire(m.fields));
      case MuxType.viewOut:
        _views[m.get<int>('id')]?._out(m.get<Uint8List>('data')!);
      case MuxType.viewReset:
        _views[m.get<int>('id')]?._reset();
      case MuxType.viewDriver:
        _views[m.get<int>('id')]?._driver(DriverSide.fromWire(m.get<String>('side')!));
      case MuxType.viewExit:
        _views.remove(m.get<int>('id'))?._end(m.get<int>('code')!, onRequest: m.get<bool>('onRequest') ?? false);
    }
  }
}
```

`RemoteSessionView`: `backlog => Uint8List(0)`; `output` single-subscription controller that buffers until listened (like the in-process view); `_out(bytes)` adds and counts `_unacked`, sending `view.ack{id, bytes}` when `_unacked >= ackEvery` or after `ackDelay` via a one-shot timer; `_reset()` adds `utf8.encode('\r\n\x1b[H\x1b[2J')`; `driver` broadcast; `exitCode` completer; `closedOnRequest`; `write/reply` send `view.write|reply{id, data}`, `resize` sends `view.resize`, `dispose` sends `view.close` and closes `output`. When the client disconnects, **do not** complete `exitCode` (D15: the UI must not print exit lines) — expose `RemoteLocalSessions.disconnected` (`Future<void>` = `_client.done`) instead.

`local_sessions.dart` doc changes for `backlog` and `view` exactly as spec D10 / "Sửa LocalSessions".

- [ ] **Step 4: Run tests** — contract suite passes **twice** (both names); full agent suite green.

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_agent/lib/src/mux/remote_local_sessions.dart packages/shellx_agent/lib/src/session/local_sessions.dart packages/shellx_agent/lib/shellx_agent.dart packages/shellx_agent/test/support/local_sessions_contract.dart packages/shellx_agent/test/support/mux_fixtures.dart packages/shellx_agent/test/session/local_sessions_contract_test.dart packages/shellx_agent/test/mux/remote_local_sessions_test.dart packages/shellx_agent/test/mux/mux_server_test.dart
git commit -m "feat(mux): RemoteLocalSessions over MuxClient; one LocalSessions contract suite for in-process and remote (A5b D10, D11, D28)"
```

---

### Task 6: Agent split — `AgentControllerBase`, state codec, `RemoteAgentController`, bridge, settings ownership (D12, D13)

**Files:**
- Create: `apps/desktop/lib/src/agent/agent_controller_base.dart`, `agent_state_codec.dart`, `remote_agent_controller.dart`, `agent_bridge_impl.dart`
- Modify: `apps/desktop/lib/src/agent/agent_controller.dart` (extends base; sync-return methods → `Future`), every caller (`tray_actions.dart`, dialogs/pages under `lib/src/ui/`)
- Modify: `apps/desktop/lib/src/platform/settings_store.dart` (`DaemonSettingKeys`, `UiSettingKeys`)
- Test: `apps/desktop/test/agent/agent_state_codec_test.dart`, `remote_agent_controller_test.dart`, `settings_ownership_test.dart`

**Interfaces:**
- Consumes: `AgentViewState` and its member types (`RelayConnectionState`, `SessionSummary`, `TrustedDevice`, `PairingView`, `UpdateNotice`, `TerminalSharingView`, `DesktopSessionSummary`); Task 2 `summaryToWire`/`summaryFromWire`; Task 4 `AgentBridge`; Task 5 `MuxClient`.
- Produces:
  - `abstract class AgentControllerBase extends Notifier<AgentViewState>` declaring, with these exact signatures: `Future<void> bootstrap({bool watchForWake = true}); Future<void> signIn({required String email, required String password, required bool register}); Future<void> signOut(); Future<void> changePassword(String newPassword); Future<void> setRemoteAccess(bool enabled); Future<void> setNotifyThreshold(int seconds); Future<void> setDesktopNotifications(bool enabled); Future<void> setDesktopNotificationsOnlyUnfocused(bool enabled); Future<void> setKeepAwake(bool enabled); Future<void> setLaunchAtStartup(bool enabled); Future<void> completeOnboarding(); Future<PairingView?> startPairing(); Future<void> cancelPairing(); Future<void> revoke(String mobileId); Future<void> closeSession(int id); Future<SharingPlan?> prepareTerminalSharing(); Future<bool> enableTerminalSharing(SharingPlan plan); Future<void> disableTerminalSharing(); Future<void> disconnectDesktopPhone(int id); Future<void> closeAllSessions(); Future<void> reconnect(); Future<void> checkForUpdate(); Future<void> shutdown();` (take `signIn`'s real parameter list from `agent_controller.dart` — keep it identical).
  - `final agentControllerProvider = NotifierProvider<AgentControllerBase, AgentViewState>(AgentController.new);` (moved into `agent_controller_base.dart` and re-exported from `agent_controller.dart`).
  - `Map<String, Object?> agentStateToWire(AgentViewState s)`, `AgentViewState agentStateFromWire(Map<Object?, Object?> m)`; `SharingPlan` ↔ wire likewise.
  - `final class RemoteAgentController extends AgentControllerBase` (state from `agent.state`; methods → `client.request(MuxType.agentCall, {'m': name, 'a': args})`; `bootstrap` returns once the first state arrived).
  - `final class ControllerAgentBridge implements AgentBridge { ControllerAgentBridge(ProviderContainer container); }` mapping each method name to the real controller.
  - `abstract final class DaemonSettingKeys { static const Set<String> all = {…the nine keys…}; }`, `abstract final class UiSettingKeys { static const Set<String> all = {…the rest + 'quit_keeps_sessions_explained'…}; }`; `SettingKeys.quitKeepsSessionsExplained = 'quit_keeps_sessions_explained'` added to `SettingKeys.all`.

- [ ] **Step 1: Write the failing tests**

`agent_state_codec_test.dart`: build a fully populated `AgentViewState` (every field non-default: signed in, email, relay connected, 2 sessions, 1 trusted device, a pairing view, an update notice, terminal sharing with one desktop session, threshold 30, both notification switches false) → `agentStateFromWire(agentStateToWire(s))` equals field by field (write an `expectSameState(a, b)` helper comparing every field, including nested lists).

`remote_agent_controller_test.dart`: with a `MemoryMuxTransport.pair()` and a hand-written fake daemon that answers `agent.call` by recording `(m, a)`:
- for **every** method of `AgentControllerBase` (iterate a table `{name: (controller) => controller.method(args)}`), the fake receives exactly that `m` and the arguments map; `startPairing` returns the decoded `PairingView`;
- a daemon `error{internal}` makes the call throw `MuxRemoteException`;
- `state` follows `agent.state` events.

`settings_ownership_test.dart`:

```dart
test('every key has exactly one owner (D13)', () {
  expect(DaemonSettingKeys.all.intersection(UiSettingKeys.all), isEmpty);
  expect(DaemonSettingKeys.all.union(UiSettingKeys.all), SettingKeys.all);
});
test('the UI never writes a daemon key', () {
  // Static scan: UI-only files must not name a daemon key.
  for (final f in ['lib/src/tray/tray_actions.dart', 'lib/src/ui', 'lib/src/terminal', 'lib/src/restore']) {
    final files = FileSystemEntity.isDirectorySync(f)
        ? Directory(f).listSync(recursive: true).whereType<File>()
        : [File(f)];
    for (final file in files) {
      final text = file.readAsStringSync();
      for (final key in ['remoteAccess', 'keepAwake', 'launchAtStartup', 'onboardingDone', 'terminalSharing', 'notifyThreshold', 'desktopNotifications']) {
        expect(text.contains('SettingKeys.$key'), isFalse, reason: '${file.path} uses $key');
      }
    }
  }
});
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement**
- Move the provider and declare `AgentControllerBase`; `class AgentController extends AgentControllerBase` with `@override` on every listed method; change `startPairing`, `cancelPairing`, `closeSession`, `disconnectDesktopPhone`, `closeAllSessions`, `reconnect` to `Future` (wrap bodies in `async`), update callers to `await` (grep `agentControllerProvider.notifier` and fix each call site; tests for those widgets keep passing).
- Codec: one function per member type; enums by `name`; `DateTime` as UTC microseconds; `PairingView`/`UpdateNotice`/`TrustedDevice`/`DesktopSessionSummary` field by field (read each class and include every field).
- `ControllerAgentBridge.call` — a `switch (method)` with one case per name calling `container.read(agentControllerProvider.notifier)` and returning a wire value (`startPairing` → pairing map or null; `prepareTerminalSharing` → plan map; `enableTerminalSharing` → bool; others → null); unknown → `throw ArgumentError(method)` (server maps to `internal`). `states` = a broadcast stream fed by `container.listen(agentControllerProvider, …)` mapping through `agentStateToWire`, coalesced to one per 16 ms.
- `RemoteAgentController.build()` returns `const AgentViewState()`, subscribes to `client.events` for `agent.state`, and requests `agent.get` once (the daemon sends nothing unsolicited); `bootstrap()` completes when that first state has been applied.

- [ ] **Step 4: Run tests** — new tests PASS; full desktop suite green (the existing `agent_controller_test.dart` still drives the real controller).

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/agent apps/desktop/lib/src/platform/settings_store.dart apps/desktop/lib/src/tray apps/desktop/lib/src/ui apps/desktop/test/agent
git commit -m "refactor(desktop): AgentControllerBase with a remote twin, AgentViewState wire codec, agent bridge, settings ownership (A5b D12, D13)"
```

---

### Task 7: Daemon host, `daemonMain`, `DaemonLauncher`, Windows runtime copy (D3, D5, D16, D19, D27)

**Files:**
- Create: `apps/desktop/lib/src/mux/daemon_host.dart`, `apps/desktop/lib/src/mux/daemon_launcher.dart`, `apps/desktop/lib/src/mux/windows_runtime_copy.dart`, `apps/desktop/lib/src/mux/mux_paths.dart`
- Modify: `apps/desktop/lib/daemon_main.dart` (real body)
- Test: `apps/desktop/test/mux/daemon_host_test.dart`, `daemon_launcher_test.dart`, `windows_runtime_copy_test.dart`

**Interfaces:**
- Consumes: Tasks 2–6; `SingleInstanceLock` (generalised: constructor gains `lockFileName` parameter, default `shellx.lock`); `SessionCore`; `DesktopServices` (daemon variant: `sessions` = core manager); `runBounded`.
- Produces:
  - `final class MuxPaths { MuxPaths({required String muxDirectory, required String tmpDirectory, required int uid, required bool windows, String? pipeName}); String get endpoint; String get lock; String get address; }` (`muxDirectory`: macOS `<app support>/mux`; Windows `%LOCALAPPDATA%\ShellX\mux`)
  - `final class DaemonHost { DaemonHost({required MuxServer server, required MuxEndpointFile endpoint, required MuxEndpointInfo info, required bool Function() hasSessions, required bool Function() servingPhones, required Future<void> Function() shutdown, required void Function(int code) exit, Duration idle = const Duration(seconds: 10)}); Future<void> start(MuxListener listener); void onUiChanged(bool attached); void onStateChanged(); Future<void> quit(); }`
  - `sealed class DaemonConnection` with `Attached({required MuxClient client, required MuxPeerInfo info})`, `Incompatible({required MuxClient client, required MuxPeerInfo info})`, `StartFailed()`.
  - `final class DaemonLauncher { DaemonLauncher({required MuxTransport transport, required MuxEndpointFile endpoint, required Future<bool> Function() daemonLockFree, required Future<void> Function() spawn, required String appVersion, Duration attempt = const Duration(seconds: 1), Duration retryEvery = const Duration(milliseconds: 100), Duration retryFor = const Duration(seconds: 5)}); Future<DaemonConnection> connect(); Future<DaemonConnection> replaceIncompatible(Incompatible old); }`
  - `Future<String> prepareWindowsRuntime({required String installDir, required String localAppData, required String version, FileOps ops = const RealFileOps()})` → path of `shellx-mux.exe`.

- [ ] **Step 1: Write the failing tests**

`daemon_host_test.dart` (`fake_async`): idle exit only when no UI ≥ 10 s **and** no sessions **and** not serving phones; UI reattaching within 10 s cancels; `quit()` runs `shutdown` (bounded 3 s), deletes the endpoint if owned, then `exit(0)`; `start` writes the endpoint with a fresh 32-byte secret and 32-hex instance each time.

`daemon_launcher_test.dart` (fake transport/endpoint/spawn/lock):
1. endpoint valid + handshake ok + protocol 1 → `Attached`; no spawn.
2. no endpoint → lock free → spawn once → connect succeeds on the 3rd retry → `Attached`.
3. endpoint stale (connect refused) and lock **held** (a daemon starting) → no spawn, retries until it answers.
4. daemon proof wrong (squatter, Review Focus 2) → treated as not running: lock free? spawn; lock held → `StartFailed` after 5 s, and **no** `view.*`/`sessions.*` message ever sent on the bad connection.
5. protocol 2 with `sessions: 0` → `connect` sends `daemon.quit`, waits for `done` (≤ 4 s), spawns, returns `Attached`.
6. protocol 2 with `sessions: 3` → `Incompatible(info.sessions == 3)`; `replaceIncompatible` → `daemon.quit` + spawn + `Attached`.
7. nothing ever answers → `StartFailed` after 5 s (fake clock).

`windows_runtime_copy_test.dart` (in-memory `FileOps`): copies `ShellX.exe` → `shellx-mux.exe`, all `.dll`, `data/**` into `<local>\ShellX\mux\<version>\` via a temp dir + rename; second call with identical sizes is a no-op; returns the exe path; `cleanupOldRuntimes(keep: version)` deletes other version dirs and ignores "in use" errors.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement**

`daemon_host.dart`:

```dart
final class DaemonHost {
  DaemonHost({
    required this.server,
    required this.endpoint,
    required this.info,
    required this.hasSessions,
    required this.servingPhones,
    required this.shutdown,
    required this.exit,
    this.idle = const Duration(seconds: 10),
  });
  final MuxServer server;
  final MuxEndpointFile endpoint;
  final MuxEndpointInfo info;
  final bool Function() hasSessions;
  final bool Function() servingPhones;
  final Future<void> Function() shutdown;
  final void Function(int code) exit;
  final Duration idle;
  Timer? _idle;
  String? _written;
  bool _quitting = false;

  Future<void> start(MuxListener listener) async {
    server.serve(listener);
    _written = await endpoint.write(info);
    onStateChanged();
  }

  void onUiChanged(bool attached) => onStateChanged();

  /// D27: arm the idle exit only when nothing needs the daemon.
  void onStateChanged() {
    final idleNow = !server.uiAttached && !hasSessions() && !servingPhones();
    if (!idleNow) {
      _idle?.cancel();
      _idle = null;
      return;
    }
    _idle ??= Timer(idle, () => unawaited(quit()));
  }

  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    _idle?.cancel();
    await runBounded(shutdown, timeout: const Duration(seconds: 3), label: 'daemon shutdown');
    final written = _written;
    if (written != null) await endpoint.deleteIfOwned(written);
    await server.close();
    exit(0);
  }
}
```

(`runBounded` lives in `lib/src/startup.dart`; import it.)

`daemon_launcher.dart` — `connect()`:

```dart
  Future<DaemonConnection> connect() async {
    final first = await _tryAttach();
    if (first != null) return _classify(first);
    if (await daemonLockFree()) await spawn();
    final deadline = DateTime.now().add(retryFor); // use an injected clock in tests
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(retryEvery);
      final next = await _tryAttach();
      if (next != null) return _classify(next);
    }
    return const StartFailed();
  }

  Future<(MuxClient, MuxPeerInfo)?> _tryAttach() async {
    final ep = await endpoint.read();
    if (ep == null) return null;
    MuxConnection? c;
    try {
      c = await transport.connect(ep.address, timeout: attempt);
      final info = await clientHandshake(c, secret: ep.secret, app: appVersion, role: 'ui', timeout: attempt);
      return (MuxClient(c), info);
    } on Object {
      await c?.close();
      return null;
    }
  }

  Future<DaemonConnection> _classify((MuxClient, MuxPeerInfo) found) async {
    final (client, info) = found;
    if (info.protocol == kMuxProtocol) return Attached(client: client, info: info);
    if ((info.sessions ?? 0) == 0) return replaceIncompatible(Incompatible(client: client, info: info));
    return Incompatible(client: client, info: info);
  }

  /// D19: stop the old daemon (it closes its shells) and start ours.
  Future<DaemonConnection> replaceIncompatible(Incompatible old) async {
    try {
      await old.client.request(MuxType.daemonQuit).timeout(const Duration(seconds: 4));
    } on Object {
      // Old daemon gone or unresponsive: its lock frees when it exits.
    }
    await old.client.done.timeout(const Duration(seconds: 4), onTimeout: () {});
    return connect();
  }
```

Inject `DateTime Function() now` and a `Future<void> Function(Duration) sleep` for fake-clock tests instead of `DateTime.now`/`Future.delayed` (add both to the constructor with real defaults).

`daemon_main.dart` (real body): parse paths (`MuxPaths`), take `SingleInstanceLock(muxDir, lockFileName: 'mux.lock')` (not acquired → `exit(0)`), Windows: `cleanupOldRuntimes`, build exactly what `main.dart` builds today for the agent side (settings, `SessionCore`, `DesktopServices` with `sessions: core.sessions`, `quitApp` → `exit`), a `ProviderContainer` with the `desktopServicesProvider` override, call `bootstrap()` on `AgentController`, build `MuxServer` (`sessions: core.sessions`, `agent: ControllerAgentBridge(container)`, `onQuit: host.quit`, `onUiChanged: host.onUiChanged`), listen via `UnixMuxTransport` (macOS) / `WindowsPipeTransport` (Windows), `host.start(listener)`, and `core.sessions.changes.listen((_) => host.onStateChanged())`, `container.listen(agentControllerProvider, (_, _) => host.onStateChanged())`. `servingPhones` = `state.signedIn && state.remoteAccess`. `shutdown` = `AgentController.shutdown()` (it already calls `closeAll` and waits for PTY kills, A1). Move the now-shared construction into a helper `buildAgentSide(...)` in `lib/src/agent/agent_side.dart` used only by the daemon (the UI no longer builds it after Task 8).

- [ ] **Step 4: Run tests** — PASS; full desktop suite green.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib/src/mux apps/desktop/lib/daemon_main.dart apps/desktop/lib/src/agent/agent_side.dart apps/desktop/lib/src/platform/single_instance.dart apps/desktop/test/mux
git commit -m "feat(desktop): daemon host with idle exit, daemonMain serving sessions and agent, launcher with version check, Windows runtime copy (A5b D3, D5, D16, D19, D27)"
```

---

### Task 8: UI process — attach, reattach restore, two quits, prompts, daemon-lost strip (D14, D15, D18, D19, D25; UI-A5 §6–§9)

**Files:**
- Modify: `apps/desktop/lib/main.dart` (UI path only), `apps/desktop/lib/src/tray/tray_action.dart`, `tray_menu.dart`, `tray_actions.dart`
- Modify: `apps/desktop/lib/src/restore/restore_persistence.dart`, `restore_snapshot.dart` (`daemon` instance written), `apps/desktop/lib/src/terminal/terminal_tabs.dart` (`reattach`)
- Create: `apps/desktop/lib/src/mux/daemon_state.dart` (Riverpod: connection status, lost/restarted strip, dialogs)
- Modify: `apps/desktop/lib/src/ui/terminal/terminal_pane.dart` (strips, empty-state variant), `apps/desktop/lib/src/ui/window_router.dart` (new dialog routes)
- Modify: `apps/desktop/macos/Runner/AppDelegate.swift` (app menu "Thoát hoàn toàn ⌥⌘Q" → `quitAllRequested`), `apps/desktop/lib/src/platform/app_reopen.dart`
- Modify: ARB files (+ generated) — UI-A5 §9 A5b rows
- Test: `apps/desktop/test/ui/quit_flows_test.dart`, `test/mux/daemon_lost_test.dart`, `test/restore/reattach_test.dart`, `test/ui/daemon_dialogs_test.dart`

**Interfaces:**
- Consumes: Tasks 5–7; A5a `RestorePersistence.restoreAtStartup`, `flushAll`, `InfoStrip`, `RestorePlan`.
- Produces:
  - Tray: `TrayKeys.quitAll = 'quit_all'`; `final class QuitAll extends TrayAction`; `Quit` now quits the UI only.
  - `RestorePersistence.restoreAtStartup(RestoreLoad load, {String? daemonInstance})` — when `load.snapshot?.daemon == daemonInstance` and non-null → **reattach** via `TerminalTabs.reattach(snapshot)`; else A5a reopen. `captureSnapshot(..., daemon: currentInstance)` from then on.
  - `Future<RestoreOutcome> TerminalTabs.reattach(RestoreSnapshot snapshot)` — builds trees from live session ids (`SavedPane.session`), no `open`, no saved text; panes whose session is not in `_local.sessions` are dropped; remaining live sessions become tabs via `_sync()`.
  - `final daemonStateProvider = NotifierProvider<DaemonStateNotifier, DaemonUiState>(…)`; `DaemonUiState { DaemonStrip? strip; }`, `enum DaemonStrip { restarted, lost }`.
  - `appChannel` method `quitAllRequested` (macOS menu ⌥⌘Q).

- [ ] **Step 1: Write the failing tests**

`quit_flows_test.dart` (widget tests over the terminal page with `RemoteLocalSessions` on a memory pair to a `MuxServer` over `SessionRig`, or with fakes recording calls):
1. `⌘Q with sessions, first time → explanation dialog (UI-A5 §7.1); "Thoát" → flushAll(clean: true), no daemon.quit, UI exit called; key quit_keeps_sessions_explained = true`.
2. `⌘Q second time → no dialog, exits at once; no confirmation ever`.
3. `⌘Q with no sessions → no dialog`.
4. `Thoát hoàn toàn with sessions → A1 confirm with action "Thoát hoàn toàn"; confirm → flushAll(clean: true) then daemon.quit then exit; cancel → nothing`.
5. `Esc on the explanation → stays, key not set`.
6. Windows variant of §7.1 body (`quitUiExplainedBodyWindows`) when `isWindows`.

`daemon_lost_test.dart` (Review Focus 3):
1. daemon connection closes unexpectedly → **no** exit line written into any tab terminal (`buffer` has no "[Process exited" / "[Tiến trình đã thoát"); `flushAll(clean: false)` called **before** the restart; launcher `connect()` called once; on `Attached` → A5a reopen restore runs with the snapshot just saved; strip `restarted` shown; no duplicate tab (tab count equals the snapshot's).
2. restart fails (`StartFailed`) → strip `lost` with "Thử lại"; tapping it retries.
3. keystrokes typed while disconnected are dropped (no exception, nothing sent later).

`reattach_test.dart`: snapshot with `daemon: 'i1'` and `session` ids 5/6 of live sessions → `restoreAtStartup(load, daemonInstance: 'i1')` → no `open` calls (`openCwds` empty), tree uses ids 5/6, no divider; a live session 9 not in the snapshot → its own tab in Default; with `daemonInstance: 'i2'` → A5a reopen path (`openCwds` non-empty).

`daemon_dialogs_test.dart`: §7.3 incompatible dialog strings, destructive primary, initial focus on "Để sau", Esc = "Để sau" → UI exit; primary → `replaceIncompatible` then normal start; §7.4 start-failed dialog: "Thử lại" calls `connect()` again, "Thoát" exits, Esc does nothing; empty state shows `daemonUnavailableEmpty` and no "Mở tab mới" button while waiting.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement**
- ARB: every A5b row of UI-A5 §9 (en with metadata, vi), `flutter gen-l10n`. Tray menu: replace `item(TrayKeys.quit, l10n.trayQuit)` by `item(TrayKeys.quit, l10n.trayQuitUi), item(TrayKeys.quitAll, l10n.trayQuitAll)` in both menus; delete the `trayQuit` key from the ARB files.
- `tray_actions.dart`: `case Quit():` → if `!explained && sessions.isNotEmpty` show §7.1 (two buttons; "Thoát hoàn toàn" dispatches `const QuitAll()`, whose A1 confirm then follows per UI-A5 §7.2), set the key on either button, then `flushAll(clean: true)` (bounded 2 s) and `services.quitUi()`; `case QuitAll():` the A1 confirm with `confirmQuitAllAction`, then `flushAll(clean: true)`, `await client.request(MuxType.daemonQuit)` (bounded 4 s), `services.quitUi()`.
- `main.dart` UI path: no `SessionCore`, no runtime; `final launcher = DaemonLauncher(...)` (Windows: `spawn` = `prepareWindowsRuntime` + `Process.start(muxExe, ['--daemon'], mode: ProcessStartMode.detached)`; macOS: `Process.start(Platform.resolvedExecutable, ['--daemon'], mode: ProcessStartMode.detached)`); `switch (await launcher.connect())` → `Attached` continue; `Incompatible` → §7.3; `StartFailed` → §7.4 (both shown over the window before restore). Override `localSessionsProvider` with `RemoteLocalSessions(client)` (await `ready`), `agentControllerProvider` with `RemoteAgentController.new`; then A5a startup with `daemonInstance: info.instance`. `listenForPortWatch` unchanged (goes through the remote `watchPorts`). Disconnect watcher: `remote.disconnected.then((_) => container.read(daemonStateProvider.notifier).lost())` unless a full quit is in progress.
- `DaemonStateNotifier.lost()`: `flushAll(clean: false)` → `launcher.connect()` → on `Attached`: swap the provider overrides by rebuilding the `ProviderScope`'s `localSessionsProvider`/`agentControllerProvider` values (hold the remote objects in a `ValueNotifier` the providers read, so `ref.invalidate(localSessionsProvider)` rebuilds `TerminalTabs` against the new connection), run `restoreAtStartup(await store.loadLayout(), daemonInstance: null)` (forces reopen), set strip `restarted`; otherwise strip `lost`.
- `TerminalTabs`: while `_local` is a `RemoteLocalSessions` that is disconnected, `_exited` is never reached (views do not complete `exitCode`, Task 5) and `write` goes nowhere; `reattach` as specified.
- macOS app menu: in `AppDelegate.applicationDidFinishLaunching` (UI mode) insert after the existing Quit item: `NSMenuItem(title: <localized from Dart via channel at startup: "Thoát hoàn toàn">, action: #selector(quitAll), keyEquivalent: "q")` with `keyEquivalentModifierMask = [.command, .option]`; `@objc func quitAll() { AppChannel.quitAllRequested() }`; Dart maps it to `trayActions.handle(const QuitAll())`. Dart sends the localized title once with `setQuitAllTitle(String)` on `appChannel`.
- Strips: `terminal_pane.dart` adds a third `AnimatedSwitcher` with `InfoStrip` for `DaemonStrip.restarted` (`Icons.history`, text `daemonRestartedStrip`) and `DaemonStrip.lost` (`Icons.error_outline`, `err`, text `daemonLostStrip`, action "Thử lại" with spinner while retrying), both after the A5a restore strip.

- [ ] **Step 4: Run tests** — new tests PASS; full desktop and agent suites green.

- [ ] **Step 5: Commit**

```bash
git add apps/desktop/lib apps/desktop/macos/Runner/AppDelegate.swift apps/desktop/test
git commit -m "feat(desktop): UI attaches to shellx-mux — reattach restore, Quit vs Quit Completely, outdated/failed service dialogs, service-lost strip (A5b D14, D15, D18, D19)"
```

---

### Task 9: ⚠ Installer, HANDOFF §16, end-to-end manual verification (D20, D21; spec criteria 1–8)

**Files:**
- Modify: `release/windows/shellx.iss`, `release/tests/inno.test.mjs`
- Modify: `docs/superpowers/HANDOFF.md`, `docs/superpowers/ledgers/a1-desktop-terminal.md`

- [ ] **Step 1: Write the failing release tests**

```js
test('install stops only the UI, without /T (A5b D21)', () => {
  assert.match(iss, /taskkill\.exe'\), '\/F \/IM "\{#AppExeName\}"'/);
  assert.doesNotMatch(iss, /PrepareToInstall[\s\S]*\/F \/T \/IM "\{#AppExeName\}"/);
});
test('uninstall stops shellx-mux and deletes mux + restore', () => {
  assert.match(iss, /Parameters: "\/F \/T \/IM ""shellx-mux\.exe"""/);
  assert.match(iss, /Name: "\{localappdata\}\\ShellX\\mux"/);
});
```

- [ ] **Step 2: Run** `cd release && node --test tests/inno.test.mjs` → FAIL.

- [ ] **Step 3: Implement** — `PrepareToInstall`: `'/F /IM "{#AppExeName}"'` (comment: the daemon runs as `shellx-mux.exe` from `%LOCALAPPDATA%\ShellX\mux\<version>` and keeps the shells alive across the update, A5b D3/D21). `[UninstallRun]`: first `Filename: "{sys}\taskkill.exe"; Parameters: "/F /T /IM ""shellx-mux.exe"""; Flags: runhidden; RunOnceId: "StopShellxMux"`, then the existing UI kill. `[UninstallDelete]`: `Type: filesandordirs; Name: "{localappdata}\ShellX\mux"`. Re-run the release tests → PASS.

- [ ] **Step 4: HANDOFF §16** — append:

```markdown
## 16. Phiên nền `shellx-mux` — A5b (2026-10-07)

Spec `specs/2026-10-07-desktop-daemon-a5b-design.md`, plan `plans/2026-10-07-desktop-daemon-a5b.md`. ShellX giờ là hai tiến trình: giao diện (`ShellX`) và phiên nền (`ShellX --daemon`; Windows chạy bản chép `%LOCALAPPDATA%\ShellX\mux\<version>\shellx-mux.exe`). ⌘Q/"Thoát" chỉ đóng giao diện; "Thoát hoàn toàn" (tray, ⌥⌘Q) dừng mọi shell. Kênh: macOS `~/Library/Application Support/pro.shellx.desktop/mux/mux.sock` (0600), Windows `\\.\pipe\shellx-mux-<hash>`; token trong `mux/endpoint` (0600), đổi mỗi lần phiên nền khởi động.

### Thử tay — macOS (bắt buộc trước khi merge)
- [ ] Spec tiêu chí 1: `top` + `sleep 600` → ⌘Q → còn `--daemon`, không còn UI → mở lại ≤ 1,5 s, `top` vẫn chạy; điện thoại không bị ngắt
- [ ] Tiêu chí 2: `kill -9` UI → mở lại, không dải A5a
- [ ] Tiêu chí 3: `kill -9` daemon khi UI mở → dải "đã được khởi động lại" ≤ 3 s, tab mở lại ở cwd cũ
- [ ] Tiêu chí 4: Thoát hoàn toàn → xác nhận → `pgrep` rỗng ≤ 4 s
- [ ] Tiêu chí 5: thay ShellX.app (Finder Replace, DMG mới) khi có phiên → shell sống; mở bản mới gắn lại (cùng protocol)
- [ ] Tiêu chí 6: `ls -l` socket `srw-------`, thư mục `drwx------`; một user khác không `nc -U` được
- [ ] Tiêu chí 7: `yes | head -n 2000000`; `kill -STOP` UI 30 s trong lúc `yes` → RSS daemon tăng < 4 MiB/view; `kill -CONT` → UI hiện lại sau một lần vẽ lại
- [ ] Tiêu chí 8: khởi động cùng máy → sau đăng nhập có `--daemon`, điện thoại thấy online
- [ ] Finder/Dock/Spotlight mở ShellX khi chỉ daemon chạy → UI mở (D2)
- [ ] Thông báo agent (đăng nhập lỗi, thu hồi điện thoại) hiện từ daemon (D24)

### Thử tay — Windows
- [ ] Như macOS (tiêu chí 1–8) với Task Manager; chạy Setup bản mới khi có phiên → shell sống (D21)
- [ ] ACL pipe chỉ người dùng; `taskkill /IM ShellX.exe` không giết `shellx-mux.exe`
- [ ] Toast của daemon hiện tên "ShellX" (AUMID, D24)
- [ ] Gỡ cài đặt: không còn `shellx-mux.exe`, xoá `mux` và `restore`
```

- [ ] **Step 5: ⚠ MANUAL — run every HANDOFF §16 check on both machines**; write each result (pass/fail + note) under `## A5b (daemon) — execution` in the ledger. Any failure → fix in a follow-up commit on this branch with a test where possible, then re-run the failed check.

- [ ] **Step 6: Full verification**

```bash
cd release && node --test tests/ && cd ..
cd packages/shellx_agent && ~/fvm/versions/3.41.4/bin/dart test && ~/fvm/versions/3.41.4/bin/dart analyze && cd ../..
cd apps/desktop && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter test && PATH=~/fvm/versions/3.41.4/bin:$PATH flutter analyze && cd ../..
```

Expected: all green; agent count = baseline + mux tests + contract suite ×2.

- [ ] **Step 7: Commit**

```bash
git add release/windows/shellx.iss release/tests/inno.test.mjs docs/superpowers/HANDOFF.md docs/superpowers/ledgers/a1-desktop-terminal.md
git commit -m "build(windows): updates stop only the UI; uninstall stops shellx-mux; HANDOFF §16 (A5b D21)"
```

---

## Self-Review

**Spec coverage:** criteria 1–2 (UI quit/crash keep shells) → T1 (headless), T7 (daemon), T8 (Quit UI-only, reattach); 3 (daemon dies) → T8 `daemon_lost`; 4 (full quit) → T7 `quit`, T8 `QuitAll`; 5 (updates) → T7 launcher + T8 dialog + T9 installer + manual; 6 (security) → T2 handshake, T3 permissions/ACL, T4 limits; 7 (performance) → T4/T5 ack window + manual; 8 (login) → D17 no-code (UI start runs the launcher) + manual; 9 (no regression, contract) → T5 + full suites. Decisions: D1 → T6/T7/T8; D2/D3 → T1, T7 (copy); D4 → T3; D5 → T3/T7; D6/D7 → T2; D8/D9 → T4; D10/D11 → T4/T5; D12/D13 → T6; D14 → T8; D15 → T8; D16 → T7; D17 → no code; D18 → T8; D19 → T7/T8; D20 → T9 manual; D21 → T9; D22 → T4 (`ui.*`/`cli` reserved: `unsupported_role`, `unknown_type`); D23 → T2–T4; D24 → T7 (daemon notifier) + manual; D25 → no code; D26 → T3/T4; D27 → T7; D28 → T5; D29 → constraint; D30 → no code.

**Placeholder scan:** native plugin class names and `signIn`'s parameter list are copied from named source files at execution (exact file given); every other step has code or an exact test list.

**Type consistency:** `MuxConnection` (T2) used by T3–T7; `MuxPeerInfo.sessions/instance` (T2) read by T7/T8; `AgentBridge` (T4) implemented by `ControllerAgentBridge` (T6); `RemoteLocalSessions.disconnected`/`ready` (T5) used by T8; `restoreAtStartup(load, {daemonInstance})` (T8) extends A5a's signature compatibly.

**Review Focus:** 1 → T4 test 6 + T5 reset test; 2 → T2 squatter/wrong-secret tests + T7 launcher test 4; 3 → T8 `daemon_lost` tests; 4 → T7 launcher tests 5–6 + T8 dialog test; 5 → T6 ownership + round-trip tests.

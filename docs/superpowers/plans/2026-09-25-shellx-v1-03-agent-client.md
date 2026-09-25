# ShellX v1.0 — Plan 03: `shellx_agent`, `shellx_client`, `shellx_e2e` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure-Dart agent logic (terminal sessions, ring buffer, flow control, Noise responder, pairing, trust list), the pure-Dart phone logic (machines, tabs, Noise initiator, pairing, re-attach) and a headless end-to-end suite that runs both over the real relay.

**Architecture:** `shellx_agent` owns sessions (`SessionManager` over a `Pty` interface) and the agent side of the channel protocol (`AgentService` = handshake responder + one batched encrypted channel per phone). `shellx_client` owns the phone side (`ClientService` routes relay frames, `MachineClient` per pinned machine, `ClientTab` per session). Both consume `shellx_core` only through overview §5.1–§5.5. Agent↔client behaviour is tested in memory through a fake relay hub (`FakeRelay`) with fake PTYs and `fake_async`; `shellx_e2e` repeats the key flows against the real relay (`npm run dev` in `relay/`) with `dart:io` processes.

**Tech Stack:** Dart 3.11 pub workspace; `shellx_core` (plan 02); `meta` (`@internal`); dev: `test ^1.30.0`, `fake_async ^1.3.3`, `http` (`MockClient`).

**Spec:** `docs/superpowers/specs/2026-09-25-shellx-v1-design.md` (§5.3–§5.5, §6.3–§6.5, §7, §9.4, §12, §13). **Contracts:** `docs/superpowers/plans/2026-09-25-shellx-v1-00-overview.md` §4 and §5 (binding).

---

## Global Constraints

Everything in overview §2 applies to every task. Values this plan implements, copied from the spec / overview:

- Session ids (spec §6.4, amended): "`id` của phiên là số nguyên do agent cấp: bắt đầu từ một giá trị ngẫu nhiên trong `[1, 2^31)` mỗi lần agent khởi động rồi tăng dần, để điện thoại không gắn nhầm vào phiên mới trùng id sau khi agent khởi động lại." Implemented per `SessionManager` instance (`Random.secure()` by default, injectable `Random? random`); `index` stays 1..n.
- Sessions (spec §7): "tối đa **10 phiên** mỗi máy. Vượt thì trả `error {code: "session_limit"}`"; "**Bộ đệm vòng** 256 KiB mỗi phiên, lưu `[start, end)` theo `seq`. Agent đọc PTY liên tục kể cả khi không có client gắn vào; khi đầy thì ghi đè dữ liệu cũ nhất"; "v1.0 **không tự đóng** phiên bị bỏ quên".
- Shell (spec §7): macOS "`dscl . -read /Users/<user> UserShell`, chạy dạng login shell (`-l`) … nếu không đọc được thì dùng `/bin/zsh`"; Windows "`pwsh.exe` nếu có trong PATH, nếu không thì `powershell.exe`". Environment: "thư mục ban đầu là home; `TERM=xterm-256color`, `COLORTERM=truecolor`, `LANG=en_US.UTF-8` nếu chưa đặt, `SHELLX=1`".
- Attach (spec §7): "`last_seq ≥ start`: gửi output từ `last_seq` tới `end`. `last_seq < start`: gửi `session.reset`, rồi output từ `start`. Sau đó áp dụng `cols, rows` … Nếu kích thước không đổi, agent resize sang `(cols, rows - 1)` rồi về `(cols, rows)` … Cuối cùng gửi `session.attached`." `last_seq > end` is treated like `last_seq < start` (overview §6 line 3). "`session.attach` từ điện thoại khác làm client cũ nhận `session.detached {reason: "taken_over"}`. Kênh của client bị hủy thì phiên trở thành không gắn (không cần tin nhắn)." Closing from the tray: "`session.detached {reason: "closed_by_host"}` rồi `session.exited`".
- Flow control (spec §6.5): batch "mỗi 16 ms … hoặc gửi ngay khi output chờ đạt 16 KiB. Mỗi tin `output` tối đa 16 KiB"; phone input "lớn hơn 16 KiB được cắt thành nhiều tin"; "`ack`: mobile gửi khi nhận thêm ≥ 32 KiB kể từ `ack` trước, hoặc 100 ms sau lần nhận cuối"; "agent ngừng gửi output của một phiên khi `sent - acked > 256 KiB`, nhưng **vẫn đọc PTY** … Khi được gửi tiếp mà dữ liệu cần gửi đã bị ghi đè, agent gửi `session.reset` rồi gửi lại từ đầu bộ đệm." The agent never lets `sent - acked` exceed 256 KiB.
- Frame budget (plan 02 contract addition): core exports `kMaxSealedBatchBytes = 65493`; `SecureChannel.seal` throws `ArgumentError` above it. A flush is split into several TRANSPORT payloads (3 full 16 KiB outputs fit, 4 do not), measured with `encodeBatch`.
- Channel (spec §6.3): initiator = mobile, responder = agent; "Mobile sinh `channel_id` ngẫu nhiên cho mỗi lần bắt tay"; prologue "`"shellx/1" || agent_device_id || mobile_device_id`"; HS1 `{proto: 1, app, name, platform}`, HS2 `{proto: 1, app, status}`, "Status khác `"ok"` thì agent hủy kênh ngay sau khi gửi HS2"; "Agent giữ tối đa một kênh cho mỗi `mobile_device_id`; HS1 mới từ cùng điện thoại thay thế kênh cũ"; "Mọi lỗi giải mã: hủy kênh; mobile bắt tay lại với `channel_id` mới. **Không có chế độ truyền không mã hóa.**"
- Pairing (spec §5.3): code "32 byte ngẫu nhiên, dùng một lần, hết hạn sau 5 phút hoặc khi đóng cửa sổ QR. Mỗi lúc chỉ có tối đa một mã hiệu lực"; the phone checks `d` against `GET /v1/devices`; pairing completes only when the agent decrypts `pair.confirm`; then trust list + invalidate code + `POST /v1/pairings` + notification; the phone pins `{agent_device_id, agent_public_key}`. "Sai mã ghép nối làm điện thoại không giải mã được tin bắt tay thứ hai."
- Trust (spec §5.4–§5.5): "Agent chỉ chấp nhận khóa có trong danh sách tin cậy cục bộ. **Agent là nguồn sự thật về tin cậy**"; revoke = remove key, close channels and sessions of that phone, `DELETE /v1/pairings/:agent_id/:mobile_id`; `pairing_removed` from the hub removes the key ("Relay chỉ có thể *bớt* tin cậy").
- cols/rows from the phone are clamped to [1, 1000] by the agent; the phone does not send `resize` when cols or rows < 1 (overview §5.6, §6 line 4).
- Relay 4002 close, or HTTP 401 before the WebSocket upgrade, → `RelayConnectionState.revoked` (plan 02); spec §5.2: "Agent nhận 4002 thì xử lý như đăng xuất" — the agent surfaces it as `AgentRevoked`; the desktop app (plan 04) does the logout.
- E2E: relay dev server `cd relay && npm run dev` on `127.0.0.1:8787` with rate limits off (overview §4.3); enabled by `SHELLX_E2E_RELAY=http://127.0.0.1:8787`, otherwise every E2E test is skipped (overview §3). One fresh account per test, email `e2e-<random hex>@example.com`.
- Consume `shellx_core` only through overview §5.1–§5.5. Dev dependency pins for every pure-Dart package: `test: ^1.30.0`, `fake_async: ^1.3.3`.

## Review Focus

Owned by this plan (overview §6 lines 1–4) plus plan-specific ones. Each line names the test that pins it.

1. **UTF-8 characters split across `output` messages or across a reset** — text must never show `�`. Tests: Task 11 `multi-byte characters split across output messages decode whole`, `a reset drops a half-received character and starts a fresh decoder`; Task 12 `UTF-8 characters split between two output batches arrive whole`.
2. **A tab taken over by another phone is not re-attached when the connection comes back** (no endless tug-of-war). Test: Task 14 `a tab taken over by another phone is not re-attached on reconnect`.
3. **`session.attach` with `last_seq > end`, or with an id that no longer exists (agent restarted)** — agent answers `session.reset` / `error session_not_found`; the client tab ends. Tests: Task 4 `attach with last_seq beyond end resets and replays from start`, `attach to an unknown id answers session_not_found with that id`; Task 12 `attach to a session that no longer exists fails with session_not_found`; Task 14 `after an agent restart an unknown session id ends the tab with session_not_found`, `after an agent restart a new session never takes over an old tab, even when last_seq is within its output` (random first ids, spec §6.4), `output that overflowed the buffer while away arrives as a reset and the newest 256 KiB`; Task 4 `each manager instance picks its own starting id`.
4. **Terminal size 0 or huge** — agent clamps to [1, 1000], phone does not send below 1. Tests: Task 4 `open clamps zero and huge terminal sizes into [1, 1000]`, `input and resize only come from the attached phone; sizes are clamped`, `attach with an unchanged size nudges the height…` (rows = 1 nudges to 2, never 0); Task 12 `resize is ignored below 1 and clamped to 1000 by the agent`.
5. **A QR code seen by two phones (photographed)** — only the first `pair.confirm` wins; the code is single-use. Tests: Task 9 `a code works once: a second confirmation with it is rejected`; Task 13 `a used code cannot pair a second phone`.
6. **The relay tampering with identities** (swapping the device id in DATA, or presenting a trusted key under another device id) — no answer or `untrusted`, never a channel. Tests: Task 8 `a relay-swapped device id breaks the prologue: no answer`, `trust binds the relay peer id…`, `trust binds the key…`.
7. **Output replayed during attach arrives before the UI subscribes to the tab** — it must not be lost. Test: Task 11 `events emitted before the first listener are replayed to it`.
8. **A replay burst (up to 256 KiB) larger than one 64 KiB frame** — split into several TRANSPORT payloads. Tests: Task 7 `a burst of full chunks is split into payloads that fit a frame`, `splitIntoBatches measures encoded sizes`; Task 12 `the phone receives far more than the 256 KiB window thanks to acks` (the fake hub rejects frames > 64 KiB).

## Notes for the executor

- Run every `dart test` from the package directory (commands below include the `cd`). `dart pub get` at the repo root resolves the whole workspace.
- **fake_async pitfall:** `StreamSubscription.cancel()` returns a root-zone future that never completes inside `fakeAsync`. Library code in this plan never awaits `cancel()` (it uses `unawaited`), and tests never `drive()` a `stop()` call — they call it and `settle()`. If a harness test stalls "within 0:01:00 of fake time" on a reconnect, look for an awaited root-zone future on `RelayConnection`'s reconnect path in `shellx_core`.
- `FakeRelay`, `FakePty` and `drive.dart` are written once in `shellx_agent/test/support/` (Tasks 4 and 6) and **copied byte-for-byte** into `shellx_client/test/support/` in Task 12. Never edit the copies; re-copy if the originals change.
- `ClientTab` and `MachineClient` have `@internal` constructors/members (from `package:meta`): the contract (overview §5.7) lists no constructors, and apps must only obtain them through `ClientService`/`MachineClient`.
- `AgentChannel` and `HandshakeResponder` live in `lib/src/service/` and are **not** exported; their tests import them via `package:shellx_agent/src/...`.

## File map

```
pubspec.yaml                                   (modify: workspace lines, Tasks 1, 10, 15)
packages/shellx_agent/
  pubspec.yaml, lib/shellx_agent.dart
  lib/src/pty/pty.dart                         Pty, ShellCommand, PtyFactory
  lib/src/pty/session_environment.dart         buildSessionEnvironment
  lib/src/pty/shell_resolver.dart              ShellResolver, ProcessRunner, PlatformShellResolver
  lib/src/pty/process_pty.dart                 ProcessPtyFactory (dart:io Process)
  lib/src/session/ring_buffer.dart             RingBuffer
  lib/src/session/session_manager.dart         OutboundMessage, SessionSummary, SessionOpenedEvent, SessionManager
  lib/src/trust/trusted_store.dart             TrustedDevice, TrustedStore
  lib/src/pairing/pairing_code_manager.dart    PairingOffer, PairingCodeManager
  lib/src/service/agent_channel.dart           AgentChannel, splitIntoBatches (internal)
  lib/src/service/handshake_responder.dart     HandshakeResponder, HandshakeAnswer (internal)
  lib/src/service/agent_events.dart            AgentEvent + subclasses (incl. AgentRevoked)
  lib/src/service/agent_service.dart           AgentService
  test/support/{fake_pty,session_rig,drive,fake_relay,test_mobile}.dart
packages/shellx_client/
  pubspec.yaml, lib/shellx_client.dart
  lib/src/client_types.dart                    PairingFailure/Exception, MachineConnection*, AppErrorException
  lib/src/pinned_store.dart                    PinnedMachine, PinnedStore
  lib/src/client_tab.dart                      TabEvent + subclasses, ClientTab
  lib/src/machine_client.dart                  MachineClient
  lib/src/client_service.dart                  ClientService
  test/support/{fake_relay,fake_pty,drive}.dart (copies), test/support/harness.dart
packages/shellx_e2e/
  pubspec.yaml, test/support/e2e_world.dart, test/e2e_test.dart
```

---

### Task 1: Scaffold `shellx_agent`; PTY interfaces, session environment, shell resolver

**Files:**
- Modify: `pubspec.yaml` (root) — add one `workspace:` line
- Create: `packages/shellx_agent/pubspec.yaml`, `packages/shellx_agent/lib/shellx_agent.dart`
- Create: `packages/shellx_agent/lib/src/pty/pty.dart`, `packages/shellx_agent/lib/src/pty/session_environment.dart`, `packages/shellx_agent/lib/src/pty/shell_resolver.dart`
- Test: `packages/shellx_agent/test/pty/shell_resolver_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks (plan 02 must have created the workspace root and `packages/shellx_core`).
- Produces (overview §5.6):
  - `abstract interface class Pty { Stream<Uint8List> get output; Future<int> get exitCode; void write(Uint8List data); void resize(int cols, int rows); void kill(); }` — adapters must close `output` when the process exits.
  - `final class ShellCommand { const ShellCommand({required String executable, required List<String> arguments, required String name}); }` (value equality added).
  - `abstract interface class PtyFactory { Pty spawn(ShellCommand command, {required String workingDirectory, required Map<String, String> environment, required int cols, required int rows}); }`
  - `abstract interface class ShellResolver { Future<ShellCommand> resolve(); }`, `typedef ProcessRunner = Future<ProcessResult> Function(String executable, List<String> arguments);`
  - `final class PlatformShellResolver implements ShellResolver { PlatformShellResolver({required String operatingSystem, required Map<String, String> environment, ProcessRunner? run, Future<bool> Function(String executable)? isOnPath}); static const ShellCommand macFallback; }`
  - `Map<String, String> buildSessionEnvironment(Map<String, String> base);`

- [ ] **Step 1: Scaffold the package**

In the root `pubspec.yaml`, add this line to the `workspace:` list (keep every existing line):

```yaml
  - packages/shellx_agent
```

`packages/shellx_agent/pubspec.yaml`:

```yaml
name: shellx_agent
description: ShellX desktop agent logic (sessions, pairing responder, trust) in pure Dart.
publish_to: none
resolution: workspace
environment:
  sdk: ^3.11.0
dependencies:
  shellx_core: any
dev_dependencies:
  fake_async: ^1.3.3
  http: ^1.2.0
  test: ^1.30.0
```

`packages/shellx_agent/lib/shellx_agent.dart`:

```dart
/// ShellX desktop agent logic: sessions, pairing responder, trust list.
library;
```

Run: `dart pub get` (repo root). Expected: `Got dependencies!`

- [ ] **Step 2: Write the failing test**

`packages/shellx_agent/test/pty/shell_resolver_test.dart`:

```dart
import 'dart:io';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

ProcessRunner fakeRun(String stdout, {int exitCode = 0, List<String>? calls}) {
  return (executable, arguments) async {
    calls?.add('$executable ${arguments.join(' ')}');
    return ProcessResult(1, exitCode, stdout, '');
  };
}

void main() {
  group('buildSessionEnvironment', () {
    test('sets TERM, COLORTERM, SHELLX and keeps the base environment', () {
      final env = buildSessionEnvironment({'HOME': '/Users/me', 'TERM': 'dumb'});
      expect(env['HOME'], '/Users/me');
      expect(env['TERM'], 'xterm-256color');
      expect(env['COLORTERM'], 'truecolor');
      expect(env['SHELLX'], '1');
    });

    test('defaults LANG only when unset or empty', () {
      expect(buildSessionEnvironment({})['LANG'], 'en_US.UTF-8');
      expect(buildSessionEnvironment({'LANG': ''})['LANG'], 'en_US.UTF-8');
      expect(buildSessionEnvironment({'LANG': 'vi_VN.UTF-8'})['LANG'],
          'vi_VN.UTF-8');
    });

    test('does not modify the base map', () {
      final base = {'PATH': '/bin'};
      buildSessionEnvironment(base);
      expect(base, {'PATH': '/bin'});
    });
  });

  group('PlatformShellResolver on macOS', () {
    test('reads the login shell with dscl and runs it with -l', () async {
      final calls = <String>[];
      final resolver = PlatformShellResolver(
        operatingSystem: 'macos',
        environment: {'USER': 'phu'},
        run: fakeRun('UserShell: /opt/homebrew/bin/fish\n', calls: calls),
      );
      final shell = await resolver.resolve();
      expect(calls, ['dscl . -read /Users/phu UserShell']);
      expect(
          shell,
          const ShellCommand(
              executable: '/opt/homebrew/bin/fish',
              arguments: ['-l'],
              name: 'fish'));
    });

    test('accepts the value on the line after the key', () async {
      final resolver = PlatformShellResolver(
        operatingSystem: 'macos',
        environment: {'USER': 'phu'},
        run: fakeRun('UserShell:\n /bin/bash\n'),
      );
      expect((await resolver.resolve()).executable, '/bin/bash');
    });

    test('falls back to /bin/zsh -l when dscl fails', () async {
      final resolver = PlatformShellResolver(
        operatingSystem: 'macos',
        environment: {'USER': 'phu'},
        run: fakeRun('', exitCode: 56),
      );
      expect(await resolver.resolve(), PlatformShellResolver.macFallback);
    });

    test('falls back when the output has no absolute path', () async {
      final resolver = PlatformShellResolver(
        operatingSystem: 'macos',
        environment: {'USER': 'phu'},
        run: fakeRun('No such key: UserShell\n'),
      );
      expect(await resolver.resolve(), PlatformShellResolver.macFallback);
    });

    test('falls back when the runner throws or USER is missing', () async {
      final throwing = PlatformShellResolver(
        operatingSystem: 'macos',
        environment: {'USER': 'phu'},
        run: (_, _) async => throw const ProcessException('dscl', []),
      );
      expect(await throwing.resolve(), PlatformShellResolver.macFallback);
      final noUser =
          PlatformShellResolver(operatingSystem: 'macos', environment: {});
      expect(await noUser.resolve(), PlatformShellResolver.macFallback);
    });
  });

  group('PlatformShellResolver on Windows', () {
    test('prefers pwsh.exe when it is on PATH', () async {
      final resolver = PlatformShellResolver(
        operatingSystem: 'windows',
        environment: {},
        isOnPath: (exe) async => exe == 'pwsh.exe',
      );
      expect(
          await resolver.resolve(),
          const ShellCommand(
              executable: 'pwsh.exe', arguments: [], name: 'pwsh'));
    });

    test('uses powershell.exe otherwise', () async {
      final resolver = PlatformShellResolver(
        operatingSystem: 'windows',
        environment: {},
        isOnPath: (_) async => false,
      );
      expect(
          await resolver.resolve(),
          const ShellCommand(
              executable: 'powershell.exe', arguments: [], name: 'powershell'));
    });
  });

  test('other operating systems use /bin/sh', () async {
    final resolver =
        PlatformShellResolver(operatingSystem: 'linux', environment: {});
    expect(
        await resolver.resolve(),
        const ShellCommand(executable: '/bin/sh', arguments: [], name: 'sh'));
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `cd packages/shellx_agent && dart test test/pty/shell_resolver_test.dart`
Expected: FAIL — compilation errors such as `Method not found: 'buildSessionEnvironment'` and `Couldn't find constructor 'PlatformShellResolver'`.

- [ ] **Step 4: Implement**

`packages/shellx_agent/lib/src/pty/pty.dart`:

```dart
import 'dart:typed_data';

/// A pseudo-terminal running one shell process.
///
/// Adapter contract (desktop `flutter_pty` adapter and [ProcessPtyFactory]):
/// - [output] is a single-subscription stream that is closed (done) when the
///   process exits;
/// - [exitCode] completes once the process has exited;
/// - [kill] terminates the whole process tree.
abstract interface class Pty {
  Stream<Uint8List> get output;
  Future<int> get exitCode;
  void write(Uint8List data);
  void resize(int cols, int rows);
  void kill();
}

/// The shell to start for a new session.
final class ShellCommand {
  const ShellCommand({
    required this.executable,
    required this.arguments,
    required this.name,
  });

  final String executable;
  final List<String> arguments;

  /// Short display name used in tab titles, e.g. "zsh" or "pwsh".
  final String name;

  @override
  bool operator ==(Object other) =>
      other is ShellCommand &&
      other.executable == executable &&
      other.name == name &&
      other.arguments.length == arguments.length &&
      Iterable<int>.generate(arguments.length)
          .every((i) => other.arguments[i] == arguments[i]);

  @override
  int get hashCode => Object.hash(executable, name, Object.hashAll(arguments));

  @override
  String toString() => 'ShellCommand($executable ${arguments.join(' ')})';
}

/// Starts [Pty]s. [spawn] may throw synchronously when the shell cannot be
/// started; the session manager reports that as `spawn_failed`.
abstract interface class PtyFactory {
  Pty spawn(
    ShellCommand command, {
    required String workingDirectory,
    required Map<String, String> environment,
    required int cols,
    required int rows,
  });
}
```

`packages/shellx_agent/lib/src/pty/session_environment.dart`:

```dart
/// Environment for a new terminal session (spec §7): the agent's own
/// environment plus `TERM=xterm-256color`, `COLORTERM=truecolor`,
/// `LANG=en_US.UTF-8` when LANG is unset or empty, and `SHELLX=1`.
Map<String, String> buildSessionEnvironment(Map<String, String> base) {
  final environment = Map<String, String>.of(base);
  environment['TERM'] = 'xterm-256color';
  environment['COLORTERM'] = 'truecolor';
  if ((environment['LANG'] ?? '').isEmpty) {
    environment['LANG'] = 'en_US.UTF-8';
  }
  environment['SHELLX'] = '1';
  return environment;
}
```

`packages/shellx_agent/lib/src/pty/shell_resolver.dart`:

```dart
import 'dart:io';

import 'pty.dart';

/// Decides which shell a new session runs.
abstract interface class ShellResolver {
  Future<ShellCommand> resolve();
}

typedef ProcessRunner = Future<ProcessResult> Function(
    String executable, List<String> arguments);

/// Spec §7:
/// - macOS: the login shell from `dscl . -read /Users/<user> UserShell`,
///   started as a login shell (`-l`); `/bin/zsh -l` when it cannot be read.
/// - Windows: `pwsh.exe` when it is on PATH, otherwise `powershell.exe`.
/// - Any other OS (tests, CI): `/bin/sh`.
final class PlatformShellResolver implements ShellResolver {
  PlatformShellResolver({
    required String operatingSystem,
    required Map<String, String> environment,
    ProcessRunner? run,
    Future<bool> Function(String executable)? isOnPath,
  })  : _operatingSystem = operatingSystem,
        _environment = environment,
        _run = run ?? _runProcess,
        _isOnPath = isOnPath;

  static const ShellCommand macFallback =
      ShellCommand(executable: '/bin/zsh', arguments: ['-l'], name: 'zsh');

  final String _operatingSystem;
  final Map<String, String> _environment;
  final ProcessRunner _run;
  final Future<bool> Function(String executable)? _isOnPath;

  static Future<ProcessResult> _runProcess(
          String executable, List<String> arguments) =>
      Process.run(executable, arguments);

  @override
  Future<ShellCommand> resolve() async {
    switch (_operatingSystem) {
      case 'macos':
        return _resolveMac();
      case 'windows':
        final hasPwsh = await (_isOnPath ?? _searchPath)('pwsh.exe');
        return hasPwsh
            ? const ShellCommand(
                executable: 'pwsh.exe', arguments: [], name: 'pwsh')
            : const ShellCommand(
                executable: 'powershell.exe', arguments: [], name: 'powershell');
      default:
        return const ShellCommand(
            executable: '/bin/sh', arguments: [], name: 'sh');
    }
  }

  Future<ShellCommand> _resolveMac() async {
    final user = _environment['USER'] ?? _environment['LOGNAME'];
    if (user == null || user.isEmpty) return macFallback;
    try {
      final result =
          await _run('dscl', ['.', '-read', '/Users/$user', 'UserShell']);
      if (result.exitCode != 0) return macFallback;
      final shell = _parseUserShell('${result.stdout}');
      if (shell == null) return macFallback;
      return ShellCommand(
          executable: shell, arguments: const ['-l'], name: shell.split('/').last);
    } catch (_) {
      return macFallback;
    }
  }

  /// Parses `UserShell: /bin/zsh` (value on the same line or on the next).
  static String? _parseUserShell(String output) {
    final lines = output.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('UserShell:')) continue;
      var value = line.substring('UserShell:'.length).trim();
      if (value.isEmpty && i + 1 < lines.length) value = lines[i + 1].trim();
      return value.startsWith('/') ? value : null;
    }
    return null;
  }

  Future<bool> _searchPath(String executable) async {
    final path = _environment['PATH'] ?? _environment['Path'] ?? '';
    for (final entry in path.split(';')) {
      final directory = entry.trim();
      if (directory.isEmpty) continue;
      final prefix = directory.endsWith(r'\') ? directory : '$directory\\';
      if (await File('$prefix$executable').exists()) return true;
    }
    return false;
  }
}
```

Replace the whole content of `packages/shellx_agent/lib/shellx_agent.dart` with:

```dart
/// ShellX desktop agent logic: sessions, pairing responder, trust list.
library;

export 'src/pty/pty.dart';
export 'src/pty/session_environment.dart';
export 'src/pty/shell_resolver.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/shellx_agent && dart test test/pty/shell_resolver_test.dart`
Expected: `+11: All tests passed!`

Run: `dart analyze packages/shellx_agent` (repo root). Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml packages/shellx_agent/pubspec.yaml packages/shellx_agent/lib packages/shellx_agent/test
git commit -m "feat(agent): scaffold shellx_agent with PTY interfaces and shell resolver"
```

### Task 2: `ProcessPtyFactory` (dart:io Process, used by E2E)

**Files:**
- Create: `packages/shellx_agent/lib/src/pty/process_pty.dart`
- Modify: `packages/shellx_agent/lib/shellx_agent.dart`
- Test: `packages/shellx_agent/test/pty/process_pty_test.dart`

**Interfaces:**
- Consumes: `Pty`, `PtyFactory`, `ShellCommand`, `buildSessionEnvironment` (Task 1).
- Produces: `final class ProcessPtyFactory implements PtyFactory { const ProcessPtyFactory(); }` — no TTY; stdout+stderr merged into `output`; `resize` is a no-op; `kill` sends SIGKILL; writes before the process started are buffered; a start failure writes `shellx: failed to start shell: …` to `output` and completes `exitCode` with 127 (spawn is synchronous, so it cannot throw `spawn_failed`).

- [ ] **Step 1: Write the failing test**

`packages/shellx_agent/test/pty/process_pty_test.dart`:

```dart
@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

const sh = ShellCommand(executable: '/bin/sh', arguments: [], name: 'sh');

Pty spawnSh() => const ProcessPtyFactory().spawn(
      sh,
      workingDirectory: Directory.systemTemp.path,
      environment: buildSessionEnvironment(Platform.environment),
      cols: 80,
      rows: 24,
    );

Future<String> collect(Pty pty) async {
  final bytes = <int>[];
  await pty.output.forEach(bytes.addAll);
  return utf8.decode(bytes);
}

void main() {
  test('runs commands written before the process started', () async {
    final pty = spawnSh();
    final output = collect(pty);
    pty.write(Uint8List.fromList(utf8.encode('echo hello; exit 3\n')));
    expect(await pty.exitCode, 3);
    expect(await output, 'hello\n');
  });

  test('merges stderr into output and passes the session environment',
      () async {
    final pty = spawnSh();
    final output = collect(pty);
    pty.write(Uint8List.fromList(
        utf8.encode(r'echo "$SHELLX $TERM"; echo oops 1>&2; exit 0' '\n')));
    expect(await pty.exitCode, 0);
    final text = await output;
    expect(text, contains('1 xterm-256color'));
    expect(text, contains('oops'));
  });

  test('resize is a no-op and kill ends the process', () async {
    final pty = spawnSh();
    final output = collect(pty);
    pty.resize(100, 40);
    pty.kill();
    expect(await pty.exitCode.timeout(const Duration(seconds: 5)), isNot(0));
    await output;
  });

  test('a missing executable reports exit code 127 and a message', () async {
    final pty = const ProcessPtyFactory().spawn(
      const ShellCommand(
          executable: '/nonexistent/shell', arguments: [], name: 'x'),
      workingDirectory: Directory.systemTemp.path,
      environment: const {},
      cols: 80,
      rows: 24,
    );
    final output = collect(pty);
    expect(await pty.exitCode, 127);
    expect(await output, contains('failed to start shell'));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/shellx_agent && dart test test/pty/process_pty_test.dart`
Expected: FAIL — compilation error `Couldn't find constructor 'ProcessPtyFactory'`.

- [ ] **Step 3: Implement**

`packages/shellx_agent/lib/src/pty/process_pty.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'pty.dart';

/// [PtyFactory] backed by `dart:io` [Process] (no TTY). Used by the headless
/// end-to-end tests; the desktop app uses a real PTY adapter instead.
/// stdout and stderr are merged into [Pty.output]; [Pty.resize] is a no-op.
final class ProcessPtyFactory implements PtyFactory {
  const ProcessPtyFactory();

  @override
  Pty spawn(
    ShellCommand command, {
    required String workingDirectory,
    required Map<String, String> environment,
    required int cols,
    required int rows,
  }) {
    return _ProcessPty(Process.start(
      command.executable,
      command.arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: false,
    ));
  }
}

final class _ProcessPty implements Pty {
  _ProcessPty(Future<Process> starting) {
    starting.then(_onStarted, onError: _onStartFailed);
  }

  final _output = StreamController<Uint8List>();
  final _exitCode = Completer<int>();
  final _pendingWrites = <Uint8List>[];
  Process? _process;
  bool _killRequested = false;

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  void _onStarted(Process process) {
    _process = process;
    var openStreams = 2;
    void streamDone() {
      openStreams--;
      if (openStreams == 0) _output.close();
    }

    void forward(List<int> data) => _output.add(Uint8List.fromList(data));
    process.stdout.listen(forward, onDone: streamDone, onError: (Object _) {});
    process.stderr.listen(forward, onDone: streamDone, onError: (Object _) {});
    process.stdin.done.catchError((Object _) {});
    process.exitCode.then(_exitCode.complete);
    if (_killRequested) {
      process.kill(ProcessSignal.sigkill);
      return;
    }
    for (final data in _pendingWrites) {
      process.stdin.add(data);
    }
    _pendingWrites.clear();
  }

  void _onStartFailed(Object error) {
    _output.add(Uint8List.fromList(
        utf8.encode('shellx: failed to start shell: $error\r\n')));
    _output.close();
    _exitCode.complete(127);
  }

  @override
  void write(Uint8List data) {
    final process = _process;
    if (process == null) {
      _pendingWrites.add(Uint8List.fromList(data));
      return;
    }
    try {
      process.stdin.add(data);
    } on StateError {
      // stdin already closed: the shell has exited.
    }
  }

  @override
  void resize(int cols, int rows) {}

  @override
  void kill() {
    _killRequested = true;
    _process?.kill(ProcessSignal.sigkill);
  }
}
```

Replace the whole content of `packages/shellx_agent/lib/shellx_agent.dart` with:

```dart
/// ShellX desktop agent logic: sessions, pairing responder, trust list.
library;

export 'src/pty/process_pty.dart';
export 'src/pty/pty.dart';
export 'src/pty/session_environment.dart';
export 'src/pty/shell_resolver.dart';
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/shellx_agent && dart test test/pty/process_pty_test.dart`
Expected: `+4: All tests passed!` (on Windows the file is skipped by `@TestOn`).

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_agent/lib packages/shellx_agent/test/pty/process_pty_test.dart
git commit -m "feat(agent): add ProcessPtyFactory for headless sessions"
```

### Task 3: `RingBuffer`

**Files:**
- Create: `packages/shellx_agent/lib/src/session/ring_buffer.dart`
- Modify: `packages/shellx_agent/lib/shellx_agent.dart`
- Test: `packages/shellx_agent/test/session/ring_buffer_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `final class RingBuffer { RingBuffer(int capacity); int get start; int get end; void append(Uint8List data); Uint8List read(int from, int maxBytes); }` — positions are absolute stream offsets (`seq`); `read` throws `RangeError` unless `start <= from <= end`, `ArgumentError` for negative `maxBytes` or a non-positive capacity.

- [ ] **Step 1: Write the failing test**

`packages/shellx_agent/test/session/ring_buffer_test.dart`:

```dart
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

Uint8List bytes(int from, int count) =>
    Uint8List.fromList(List.generate(count, (i) => (from + i) % 256));

void main() {
  test('starts empty', () {
    final ring = RingBuffer(8);
    expect(ring.start, 0);
    expect(ring.end, 0);
    expect(ring.read(0, 10), isEmpty);
  });

  test('appends and reads by absolute position', () {
    final ring = RingBuffer(8);
    ring.append(bytes(0, 5));
    expect(ring.start, 0);
    expect(ring.end, 5);
    expect(ring.read(0, 5), bytes(0, 5));
    expect(ring.read(2, 2), bytes(2, 2));
    expect(ring.read(3, 100), bytes(3, 2));
    expect(ring.read(5, 4), isEmpty);
  });

  test('overwrites the oldest bytes and wraps around', () {
    final ring = RingBuffer(8);
    ring.append(bytes(0, 6));
    ring.append(bytes(6, 6));
    expect(ring.start, 4);
    expect(ring.end, 12);
    expect(ring.read(4, 8), bytes(4, 8));
    expect(ring.read(7, 3), bytes(7, 3));
  });

  test('a single append larger than the capacity keeps the newest bytes', () {
    final ring = RingBuffer(8);
    ring.append(bytes(0, 3));
    ring.append(bytes(3, 20));
    expect(ring.start, 15);
    expect(ring.end, 23);
    expect(ring.read(15, 8), bytes(15, 8));
  });

  test('rejects reads outside [start, end]', () {
    final ring = RingBuffer(4);
    ring.append(bytes(0, 10));
    expect(() => ring.read(5, 1), throwsRangeError);
    expect(() => ring.read(11, 1), throwsRangeError);
    expect(() => ring.read(6, -1), throwsArgumentError);
  });

  test('rejects a non-positive capacity', () {
    expect(() => RingBuffer(0), throwsArgumentError);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/shellx_agent && dart test test/session/ring_buffer_test.dart`
Expected: FAIL — compilation error `Couldn't find constructor 'RingBuffer'`.

- [ ] **Step 3: Implement**

`packages/shellx_agent/lib/src/session/ring_buffer.dart`:

```dart
import 'dart:math';
import 'dart:typed_data';

/// Fixed-capacity byte ring addressed by absolute stream position (`seq`).
/// Holds the bytes `[start, end)`; appending past capacity overwrites the
/// oldest bytes and advances [start].
final class RingBuffer {
  RingBuffer(int capacity)
      : _capacity = capacity,
        _bytes = Uint8List(capacity) {
    if (capacity <= 0) throw ArgumentError.value(capacity, 'capacity');
  }

  final int _capacity;
  final Uint8List _bytes;
  int _end = 0;

  int get start => max(0, _end - _capacity);
  int get end => _end;

  void append(Uint8List data) {
    if (data.isEmpty) return;
    var source = data;
    if (source.length > _capacity) {
      source = Uint8List.sublistView(source, source.length - _capacity);
    }
    final skipped = data.length - source.length;
    var position = (_end + skipped) % _capacity;
    var offset = 0;
    while (offset < source.length) {
      final count = min(source.length - offset, _capacity - position);
      _bytes.setRange(position, position + count, source, offset);
      offset += count;
      position = (position + count) % _capacity;
    }
    _end += data.length;
  }

  /// Returns up to [maxBytes] bytes starting at stream position [from].
  /// Requires `start <= from <= end`.
  Uint8List read(int from, int maxBytes) {
    if (from < start || from > end) {
      throw RangeError('read from $from outside [$start, $end]');
    }
    if (maxBytes < 0) throw ArgumentError.value(maxBytes, 'maxBytes');
    final length = min(maxBytes, _end - from);
    final result = Uint8List(length);
    var position = from % _capacity;
    var offset = 0;
    while (offset < length) {
      final count = min(length - offset, _capacity - position);
      result.setRange(offset, offset + count, _bytes, position);
      offset += count;
      position = (position + count) % _capacity;
    }
    return result;
  }
}
```

Replace the whole content of `packages/shellx_agent/lib/shellx_agent.dart` with:

```dart
/// ShellX desktop agent logic: sessions, pairing responder, trust list.
library;

export 'src/pty/process_pty.dart';
export 'src/pty/pty.dart';
export 'src/pty/session_environment.dart';
export 'src/pty/shell_resolver.dart';
export 'src/session/ring_buffer.dart';
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/shellx_agent && dart test test/session/ring_buffer_test.dart`
Expected: `+6: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_agent/lib packages/shellx_agent/test/session/ring_buffer_test.dart
git commit -m "feat(agent): add RingBuffer"
```

### Task 4: `SessionManager` — sessions, output, attach/reset, send window

**Files:**
- Create: `packages/shellx_agent/lib/src/session/session_manager.dart`
- Modify: `packages/shellx_agent/lib/shellx_agent.dart`
- Create (test support): `packages/shellx_agent/test/support/fake_pty.dart`, `packages/shellx_agent/test/support/session_rig.dart`
- Test: `packages/shellx_agent/test/session/session_manager_test.dart`, `packages/shellx_agent/test/session/session_attach_test.dart`

**Interfaces:**
- Consumes: `Pty`, `PtyFactory`, `ShellCommand`, `ShellResolver`, `buildSessionEnvironment` (Task 1), `RingBuffer` (Task 3); core `AppMessage` subclasses, `kMaxOutputChunk`.
- Produces (overview §5.6):
  - `final class OutboundMessage { const OutboundMessage(String mobileId, AppMessage message); }`
  - `final class SessionSummary { id, index, shell, createdAt, attachedMobileId }`, `final class SessionOpenedEvent { const SessionOpenedEvent(String mobileId, int sessionId); }`
  - `final class SessionManager { SessionManager({required PtyFactory ptyFactory, required ShellResolver shellResolver, required String homeDirectory, required Map<String, String> baseEnvironment, int maxSessions = 10, int bufferCapacity = 256 * 1024, int sendWindow = 256 * 1024, Random? random}); Stream<OutboundMessage> get outbound /* sync broadcast */; Future<void> handle(String mobileId, AppMessage message); void mobileDisconnected(String mobileId); void closeSessionsAttachedTo(String mobileId); void closeSession(int id); void closeAll(); List<SessionSummary> get sessions; Stream<void> get changes; Stream<SessionOpenedEvent> get opened; }`
  - Behaviour: ids start at a random value in [1, 2^31) chosen per instance (`random ?? Random.secure()`) and increase by one, so they never repeat within the process and differ across agent restarts (spec §6.4, amended); `index` = lowest free positive number; `session.close`/`session.attach` for an unknown id answer `error session_not_found` with `id`; `input`/`resize`/`ack` are accepted only from the attached phone; a session ends when `exitCode` completes and `output` is done (at most 2 s grace).
  - Test support: `FakePty` (`emit`, `emitBytes`, `exit`, `writes`, `resizes`, `killed`, `writtenText`, `killExitCode = -15`), `FakePtyFactory` (`ptys`, `failWith`), `FixedShellResolver` (default `/bin/zsh -l`, name `zsh`), `SessionRig({maxSessions, bufferCapacity, sendWindow, Random? random /* default Random(1) */})`, `phone`/`tablet` ids, `outputText`, `outputBytes`. Tests always use the ids returned by `session.opened`, never literal 1/2/3.

- [ ] **Step 1: Write the test support**

`packages/shellx_agent/test/support/fake_pty.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';

/// Scriptable [Pty]: tests push output with [emit] and end it with [exit].
final class FakePty implements Pty {
  FakePty({
    required this.command,
    required this.workingDirectory,
    required this.environment,
    required this.initialCols,
    required this.initialRows,
  });

  final ShellCommand command;
  final String workingDirectory;
  final Map<String, String> environment;
  final int initialCols;
  final int initialRows;

  final _output = StreamController<Uint8List>();
  final _exitCode = Completer<int>();
  final writes = <Uint8List>[];
  final resizes = <(int, int)>[];
  bool killed = false;

  /// Exit code reported when the session is killed (SIGTERM on POSIX).
  static const int killExitCode = -15;

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  void write(Uint8List data) => writes.add(Uint8List.fromList(data));

  @override
  void resize(int cols, int rows) => resizes.add((cols, rows));

  @override
  void kill() {
    killed = true;
    exit(killExitCode);
  }

  void emit(String text) => emitBytes(utf8.encode(text));

  void emitBytes(List<int> bytes) {
    if (!_output.isClosed) _output.add(Uint8List.fromList(bytes));
  }

  void exit(int code) {
    if (_exitCode.isCompleted) return;
    _output.close();
    _exitCode.complete(code);
  }

  /// Everything written to the shell, decoded as UTF-8.
  String get writtenText => utf8.decode([for (final w in writes) ...w]);
}

final class FakePtyFactory implements PtyFactory {
  final ptys = <FakePty>[];

  /// When set, the next [spawn] calls throw this.
  Object? failWith;

  @override
  Pty spawn(
    ShellCommand command, {
    required String workingDirectory,
    required Map<String, String> environment,
    required int cols,
    required int rows,
  }) {
    final error = failWith;
    if (error != null) throw error;
    final pty = FakePty(
      command: command,
      workingDirectory: workingDirectory,
      environment: environment,
      initialCols: cols,
      initialRows: rows,
    );
    ptys.add(pty);
    return pty;
  }
}

final class FixedShellResolver implements ShellResolver {
  const FixedShellResolver([
    this.command =
        const ShellCommand(executable: '/bin/zsh', arguments: ['-l'], name: 'zsh'),
  ]);

  final ShellCommand command;

  @override
  Future<ShellCommand> resolve() async => command;
}
```

`packages/shellx_agent/test/support/session_rig.dart`:

```dart
import 'dart:convert';
import 'dart:math';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';

import 'fake_pty.dart';

const phone = 'b0000000-0000-4000-8000-000000000002';
const tablet = 'b0000000-0000-4000-8000-000000000003';

/// A [SessionManager] over [FakePtyFactory] that records every outbound
/// message.
final class SessionRig {
  SessionRig({
    int maxSessions = 10,
    int bufferCapacity = 256 * 1024,
    int sendWindow = 256 * 1024,
    Random? random,
  }) {
    manager = SessionManager(
      ptyFactory: factory,
      shellResolver: const FixedShellResolver(),
      homeDirectory: '/Users/test',
      baseEnvironment: const {'PATH': '/usr/bin'},
      maxSessions: maxSessions,
      bufferCapacity: bufferCapacity,
      sendWindow: sendWindow,
      random: random ?? Random(1),
    );
    manager.outbound.listen(sent.add);
  }

  final factory = FakePtyFactory();
  late final SessionManager manager;
  final sent = <OutboundMessage>[];

  /// Messages sent to [mobileId], in order.
  List<AppMessage> to(String mobileId) =>
      [for (final o in sent) if (o.mobileId == mobileId) o.message];

  /// Opens a session for [mobileId] and returns its id.
  Future<int> open(String mobileId, {int cols = 80, int rows = 24}) async {
    await manager.handle(mobileId, SessionOpen(cols: cols, rows: rows));
    return to(mobileId).whereType<SessionOpened>().last.id;
  }

  FakePty pty(int spawnIndex) => factory.ptys[spawnIndex];

  void clear() => sent.clear();
}

/// Concatenated output text of session [id] in [messages].
String outputText(List<AppMessage> messages, int id) => utf8.decode([
      for (final m in messages.whereType<OutputMessage>())
        if (m.id == id) ...m.data,
    ]);

/// Total output bytes of session [id] in [messages].
int outputBytes(List<AppMessage> messages, int id) => messages
    .whereType<OutputMessage>()
    .where((m) => m.id == id)
    .fold(0, (sum, m) => sum + m.data.length);
```

- [ ] **Step 2: Write the failing tests**

`packages/shellx_agent/test/session/session_manager_test.dart`:

```dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/fake_pty.dart';
import '../support/session_rig.dart';

void main() {
  test('open spawns the shell in the home directory with the session env',
      () async {
    final rig = SessionRig();
    await rig.manager.handle(phone, const SessionOpen(cols: 80, rows: 24));

    final opened = rig.to(phone).single as SessionOpened;
    expect((opened.index, opened.shell), (1, 'zsh'));
    expect(rig.manager.sessions.single.id, opened.id);
    final pty = rig.pty(0);
    expect(pty.command.executable, '/bin/zsh');
    expect(pty.command.arguments, ['-l']);
    expect(pty.workingDirectory, '/Users/test');
    expect(pty.environment['PATH'], '/usr/bin');
    expect(pty.environment['TERM'], 'xterm-256color');
    expect(pty.environment['SHELLX'], '1');
    expect((pty.initialCols, pty.initialRows), (80, 24));
    expect(rig.manager.sessions.single.attachedMobileId, phone);
  });

  test('open clamps zero and huge terminal sizes into [1, 1000]', () async {
    final rig = SessionRig();
    await rig.open(phone, cols: 0, rows: -3);
    await rig.open(phone, cols: 5000, rows: 100000);
    expect((rig.pty(0).initialCols, rig.pty(0).initialRows), (1, 1));
    expect((rig.pty(1).initialCols, rig.pty(1).initialRows), (1000, 1000));
  });

  test('output is sent in chunks of at most 16 KiB numbered by byte',
      () async {
    final rig = SessionRig();
    final id = await rig.open(phone);
    rig.clear();
    rig.pty(0).emitBytes(List.filled(40 * 1024, 0x61));
    await pumpEventQueue();

    final outputs = rig.to(phone).whereType<OutputMessage>().toList();
    expect([for (final o in outputs) (o.id, o.seq, o.data.length)], [
      (id, 0, 16384),
      (id, 16384, 16384),
      (id, 32768, 8192),
    ]);
  });

  test('the 11th session is refused with session_limit', () async {
    final rig = SessionRig();
    for (var i = 0; i < 10; i++) {
      await rig.open(phone);
    }
    rig.clear();
    await rig.manager.handle(phone, const SessionOpen(cols: 80, rows: 24));

    final error = rig.to(phone).single as ErrorMessage;
    expect(error.code, AppErrorCode.sessionLimit);
    expect(error.id, isNull);
    expect(rig.manager.sessions, hasLength(10));
  });

  test('a spawn failure answers spawn_failed and creates no session',
      () async {
    final rig = SessionRig();
    rig.factory.failWith = StateError('no pty');
    await rig.manager.handle(phone, const SessionOpen(cols: 80, rows: 24));

    final error = rig.to(phone).single as ErrorMessage;
    expect(error.code, AppErrorCode.spawnFailed);
    expect(error.message, contains('no pty'));
    expect(rig.manager.sessions, isEmpty);
  });

  test('ids start at a random value in [1, 2^31) and increase by one; '
      'indexes reuse the lowest free number', () async {
    final rig = SessionRig();
    final first = await rig.open(phone);
    await rig.open(phone);
    rig.pty(0).exit(0);
    await pumpEventQueue();
    await rig.open(phone);

    expect(first, inInclusiveRange(1, (1 << 31) - 1));
    final opened = rig.to(phone).whereType<SessionOpened>().toList();
    expect([for (final o in opened) (o.id, o.index)],
        [(first, 1), (first + 1, 2), (first + 2, 1)]);
  });

  test('each manager instance picks its own starting id', () async {
    final a = SessionRig(random: Random(1));
    final b = SessionRig(random: Random(2));
    expect(await a.open(phone), isNot(await b.open(phone)));

    // Without an injected Random the manager uses Random.secure().
    final manager = SessionManager(
      ptyFactory: FakePtyFactory(),
      shellResolver: const FixedShellResolver(),
      homeDirectory: '/Users/test',
      baseEnvironment: const {},
    );
    final sent = <OutboundMessage>[];
    manager.outbound.listen(sent.add);
    await manager.handle(phone, const SessionOpen(cols: 80, rows: 24));
    expect((sent.single.message as SessionOpened).id,
        inInclusiveRange(1, (1 << 31) - 1));
  });

  test('session.list reports every session and whether it is attached',
      () async {
    final rig = SessionRig();
    final first = await rig.open(phone);
    final second = await rig.open(phone);
    rig.manager.mobileDisconnected(phone);
    await rig.manager.handle(
        tablet, SessionAttach(id: second, cols: 80, rows: 24, lastSeq: 0));
    rig.clear();
    await rig.manager.handle(tablet, const SessionList());

    final result = rig.to(tablet).single as SessionListResult;
    expect([for (final s in result.sessions) (s.id, s.index, s.shell, s.attached)],
        [(first, 1, 'zsh', false), (second, 2, 'zsh', true)]);
    expect(result.sessions.first.createdAt, greaterThan(0));
  });

  test('input and resize only come from the attached phone; sizes are clamped',
      () async {
    final rig = SessionRig();
    final id = await rig.open(phone);
    final data = Uint8List.fromList(utf8.encode('ls\r'));
    await rig.manager.handle(phone, InputMessage(id: id, data: data));
    await rig.manager.handle(tablet, InputMessage(id: id, data: data));
    await rig.manager.handle(phone, ResizeMessage(id: id, cols: 100, rows: 30));
    await rig.manager.handle(phone, ResizeMessage(id: id, cols: 0, rows: 5000));
    await rig.manager.handle(tablet, ResizeMessage(id: id, cols: 50, rows: 50));

    expect(rig.pty(0).writtenText, 'ls\r');
    expect(rig.pty(0).resizes, [(100, 30), (1, 1000)]);
  });

  test('shell exit sends session.exited and removes the session', () async {
    final rig = SessionRig();
    final id = await rig.open(phone);
    rig.pty(0).emit('bye\r\n');
    rig.pty(0).exit(7);
    await pumpEventQueue();

    final messages = rig.to(phone);
    expect(outputText(messages, id), 'bye\r\n');
    expect(messages.last, isA<SessionExited>());
    expect((messages.last as SessionExited).exitCode, 7);
    expect(rig.manager.sessions, isEmpty);
  });

  test('session.close kills the shell; an unknown id answers session_not_found',
      () async {
    final rig = SessionRig();
    final id = await rig.open(phone);
    await rig.manager.handle(phone, SessionClose(id: id));
    await pumpEventQueue();
    await rig.manager.handle(phone, SessionClose(id: id + 1));

    expect(rig.pty(0).killed, isTrue);
    final messages = rig.to(phone);
    expect(messages[messages.length - 2], isA<SessionExited>());
    final error = messages.last as ErrorMessage;
    expect((error.code, error.id), (AppErrorCode.sessionNotFound, id + 1));
  });

  test('closeSession from the tray sends detached(closed_by_host) then exited',
      () async {
    final rig = SessionRig();
    final id = await rig.open(phone);
    rig.clear();
    rig.manager.closeSession(id);
    await pumpEventQueue();

    final messages = rig.to(phone);
    expect(messages, hasLength(2));
    final detached = messages[0] as SessionDetached;
    expect((detached.id, detached.reason), (id, DetachReason.closedByHost));
    final exited = messages[1] as SessionExited;
    expect((exited.id, exited.exitCode), (id, FakePty.killExitCode));
    expect(rig.manager.sessions, isEmpty);
  });

  test('closeAll closes every session', () async {
    final rig = SessionRig();
    await rig.open(phone);
    await rig.open(tablet);
    rig.manager.closeAll();
    await pumpEventQueue();
    expect(rig.factory.ptys.every((p) => p.killed), isTrue);
    expect(rig.manager.sessions, isEmpty);
  });

  test('sessions keep running and buffering with no phone attached', () async {
    final rig = SessionRig();
    final id = await rig.open(phone);
    rig.manager.mobileDisconnected(phone);
    rig.clear();
    rig.pty(0).emit('still here');
    await pumpEventQueue();

    expect(rig.sent, isEmpty);
    expect(rig.manager.sessions.single.id, id);
    expect(rig.manager.sessions.single.attachedMobileId, isNull);
  });

  test('changes and opened streams report activity', () async {
    final rig = SessionRig();
    var changes = 0;
    final opened = <SessionOpenedEvent>[];
    rig.manager.changes.listen((_) => changes++);
    rig.manager.opened.listen(opened.add);
    final id = await rig.open(phone);
    rig.pty(0).exit(0);
    await pumpEventQueue();

    expect([for (final e in opened) (e.mobileId, e.sessionId)], [(phone, id)]);
    expect(changes, 2);
  });
}
```

`packages/shellx_agent/test/session/session_attach_test.dart`:

```dart
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/session_rig.dart';

void main() {
  test('attach inside the buffer replays from last_seq, then session.attached',
      () async {
    final rig = SessionRig();
    final id = await rig.open(phone);
    rig.pty(0).emit('0123456789');
    await pumpEventQueue();
    rig.manager.mobileDisconnected(phone);
    rig.pty(0).emit('ABC');
    await pumpEventQueue();
    rig.clear();

    await rig.manager.handle(
        phone, SessionAttach(id: id, cols: 80, rows: 24, lastSeq: 4));

    final messages = rig.to(phone);
    expect(messages.first, isA<OutputMessage>());
    expect((messages.first as OutputMessage).seq, 4);
    expect(outputText(messages, id), '456789ABC');
    expect(messages.last, isA<SessionAttached>());
    expect(messages.whereType<SessionReset>(), isEmpty);
  });

  test('attach with last_seq before start resets and replays from start',
      () async {
    final rig = SessionRig(bufferCapacity: 8);
    final id = await rig.open(phone);
    rig.manager.mobileDisconnected(phone);
    rig.pty(0).emit('0123456789ABCD'); // 14 bytes: start = 6
    await pumpEventQueue();
    rig.clear();

    await rig.manager.handle(
        phone, SessionAttach(id: id, cols: 80, rows: 24, lastSeq: 2));

    final messages = rig.to(phone);
    expect(messages.first, isA<SessionReset>());
    expect((messages[1] as OutputMessage).seq, 6);
    expect(outputText(messages, id), '6789ABCD');
    expect(messages.last, isA<SessionAttached>());
  });

  test('attach with last_seq beyond end resets and replays from start',
      () async {
    final rig = SessionRig();
    final id = await rig.open(phone);
    rig.pty(0).emit('hello');
    await pumpEventQueue();
    rig.clear();

    await rig.manager.handle(
        phone, SessionAttach(id: id, cols: 80, rows: 24, lastSeq: 5000));

    final messages = rig.to(phone);
    expect(messages.first, isA<SessionReset>());
    expect((messages[1] as OutputMessage).seq, 0);
    expect(outputText(messages, id), 'hello');
    expect(messages.last, isA<SessionAttached>());
  });

  test('attach to an unknown id answers session_not_found with that id',
      () async {
    final rig = SessionRig();
    await rig.manager.handle(
        phone, const SessionAttach(id: 42, cols: 80, rows: 24, lastSeq: 0));

    final error = rig.to(phone).single as ErrorMessage;
    expect((error.code, error.id), (AppErrorCode.sessionNotFound, 42));
  });

  test('attach with an unchanged size nudges the height to force a redraw',
      () async {
    final rig = SessionRig();
    final id = await rig.open(phone, cols: 80, rows: 24);
    await rig.manager.handle(
        phone, SessionAttach(id: id, cols: 80, rows: 24, lastSeq: 0));
    expect(rig.pty(0).resizes, [(80, 23), (80, 24)]);

    await rig.manager.handle(
        phone, SessionAttach(id: id, cols: 100, rows: 30, lastSeq: 0));
    expect(rig.pty(0).resizes, [(80, 23), (80, 24), (100, 30)]);

    final tiny = await rig.open(phone, cols: 0, rows: 0);
    await rig.manager.handle(
        phone, SessionAttach(id: tiny, cols: 0, rows: 0, lastSeq: 0));
    expect(rig.pty(1).resizes, [(1, 2), (1, 1)]);
  });

  test('attach from another phone detaches the first one with taken_over',
      () async {
    final rig = SessionRig();
    final id = await rig.open(phone);
    rig.clear();
    await rig.manager.handle(
        tablet, SessionAttach(id: id, cols: 80, rows: 24, lastSeq: 0));
    rig.pty(0).emit('for tablet');
    await pumpEventQueue();
    await rig.manager.handle(phone,
        InputMessage(id: id, data: Uint8List.fromList('ignored'.codeUnits)));

    final toPhone = rig.to(phone);
    expect(toPhone, hasLength(1));
    final detached = toPhone.single as SessionDetached;
    expect((detached.id, detached.reason), (id, DetachReason.takenOver));
    expect(outputText(rig.to(tablet), id), 'for tablet');
    expect(rig.pty(0).writes, isEmpty);
    expect(rig.manager.sessions.single.attachedMobileId, tablet);
  });

  test('send window: stops at 256 KiB unacknowledged, resumes on ack',
      () async {
    final rig = SessionRig(bufferCapacity: 1024 * 1024);
    final id = await rig.open(phone);
    rig.pty(0).emitBytes(List.filled(300 * 1024, 0x78));
    await pumpEventQueue();
    expect(outputBytes(rig.to(phone), id), 256 * 1024);

    await rig.manager.handle(phone, AckMessage(id: id, seq: 64 * 1024));
    expect(outputBytes(rig.to(phone), id), 300 * 1024);
    final last = rig.to(phone).whereType<OutputMessage>().last;
    expect(last.seq + last.data.length, 300 * 1024);
  });

  test('data overwritten while blocked is replaced by reset + replay from start',
      () async {
    final rig = SessionRig(bufferCapacity: 64 * 1024, sendWindow: 16 * 1024);
    final id = await rig.open(phone);
    rig.pty(0).emitBytes(List.filled(16 * 1024, 0x61));
    await pumpEventQueue();
    rig.pty(0).emitBytes(List.filled(100 * 1024, 0x62)); // start = 52 KiB
    await pumpEventQueue();
    rig.clear();

    await rig.manager.handle(phone, AckMessage(id: id, seq: 16 * 1024));

    final messages = rig.to(phone);
    expect(messages.first, isA<SessionReset>());
    final output = messages[1] as OutputMessage;
    expect((output.seq, output.data.length), (52 * 1024, 16 * 1024));
    expect(output.data.every((b) => b == 0x62), isTrue);
  });

  test('acks beyond what was sent are clamped', () async {
    final rig = SessionRig(sendWindow: 8);
    final id = await rig.open(phone);
    rig.pty(0).emit('0123456789abcdef');
    await pumpEventQueue();
    await rig.manager.handle(phone, AckMessage(id: id, seq: 1 << 40));
    expect(outputText(rig.to(phone), id), '0123456789abcdef');
  });

  test('mobileDisconnected detaches silently; closeSessionsAttachedTo kills '
      'only that phone’s sessions', () async {
    final rig = SessionRig();
    await rig.open(phone);
    await rig.open(tablet);
    rig.clear();
    rig.manager.mobileDisconnected(phone);
    expect(rig.sent, isEmpty);
    expect(rig.manager.sessions.first.attachedMobileId, isNull);

    rig.manager.closeSessionsAttachedTo(tablet);
    await pumpEventQueue();
    expect(rig.pty(0).killed, isFalse);
    expect(rig.pty(1).killed, isTrue);
    expect(rig.manager.sessions, hasLength(1));
  });
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `cd packages/shellx_agent && dart test test/session`
Expected: FAIL — compilation errors such as `Type 'SessionManager' not found` and `Type 'OutboundMessage' not found` (the ring buffer tests in the same folder still pass).

- [ ] **Step 4: Implement**

`packages/shellx_agent/lib/src/session/session_manager.dart`:

```dart
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import '../pty/pty.dart';
import '../pty/session_environment.dart';
import '../pty/shell_resolver.dart';
import 'ring_buffer.dart';

/// An application message the agent must deliver to one phone.
final class OutboundMessage {
  const OutboundMessage(this.mobileId, this.message);
  final String mobileId;
  final AppMessage message;
}

/// Read-only view of a session for the tray menu.
final class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.index,
    required this.shell,
    required this.createdAt,
    required this.attachedMobileId,
  });
  final int id, index;
  final String shell;
  final DateTime createdAt;
  final String? attachedMobileId;
}

/// Emitted when a phone opens a new session (desktop notification).
final class SessionOpenedEvent {
  const SessionOpenedEvent(this.mobileId, this.sessionId);
  final String mobileId;
  final int sessionId;
}

const int _minDimension = 1;
const int _maxDimension = 1000;

/// Session ids start at a random value in [1, 2^31) (spec §6.4).
const int _idUpperBound = 1 << 31;
const Duration _outputDrainGrace = Duration(seconds: 2);

int _clampDimension(int value) => value.clamp(_minDimension, _maxDimension);

final class _Session {
  _Session({
    required this.id,
    required this.index,
    required this.shell,
    required this.createdAt,
    required this.pty,
    required this.buffer,
    required this.cols,
    required this.rows,
    required this.attachedMobileId,
  });

  final int id;
  final int index;
  final String shell;
  final DateTime createdAt;
  final Pty pty;
  final RingBuffer buffer;
  int cols;
  int rows;
  String? attachedMobileId;

  /// Phone that still gets `session.exited` after a `closed_by_host` detach.
  String? exitRecipient;

  /// Next stream position to send to the attached phone.
  int sent = 0;

  /// Highest position acknowledged by the attached phone.
  int acked = 0;

  StreamSubscription<Uint8List>? output;
}

/// Owns every terminal session of the agent (spec §6.5 and §7).
///
/// Session ids start at a random value in [1, 2^31) chosen per instance
/// ([random] defaults to `Random.secure()`) and then increase by one, so a
/// phone re-attaching after an agent restart cannot land on a new session
/// that reuses its old id (spec §6.4). `index` is still 1..n.
final class SessionManager {
  SessionManager({
    required PtyFactory ptyFactory,
    required ShellResolver shellResolver,
    required String homeDirectory,
    required Map<String, String> baseEnvironment,
    int maxSessions = 10,
    int bufferCapacity = 256 * 1024,
    int sendWindow = 256 * 1024,
    Random? random,
  })  : _ptyFactory = ptyFactory,
        _shellResolver = shellResolver,
        _homeDirectory = homeDirectory,
        _baseEnvironment = baseEnvironment,
        _maxSessions = maxSessions,
        _bufferCapacity = bufferCapacity,
        _sendWindow = sendWindow,
        _nextId = (random ?? Random.secure()).nextInt(_idUpperBound - 1) + 1;

  final PtyFactory _ptyFactory;
  final ShellResolver _shellResolver;
  final String _homeDirectory;
  final Map<String, String> _baseEnvironment;
  final int _maxSessions;
  final int _bufferCapacity;
  final int _sendWindow;

  final _outbound = StreamController<OutboundMessage>.broadcast(sync: true);
  final _changes = StreamController<void>.broadcast();
  final _opened = StreamController<SessionOpenedEvent>.broadcast();
  final _sessions = <int, _Session>{};
  int _nextId;
  int _pendingOpens = 0;

  /// Messages to deliver, in order. Synchronous broadcast stream.
  Stream<OutboundMessage> get outbound => _outbound.stream;

  /// Fires whenever the session list or an attachment changes.
  Stream<void> get changes => _changes.stream;

  Stream<SessionOpenedEvent> get opened => _opened.stream;

  List<SessionSummary> get sessions => [
        for (final s in _sessions.values)
          SessionSummary(
            id: s.id,
            index: s.index,
            shell: s.shell,
            createdAt: s.createdAt,
            attachedMobileId: s.attachedMobileId,
          ),
      ];

  /// Handles one decrypted message from phone [mobileId].
  Future<void> handle(String mobileId, AppMessage message) async {
    switch (message) {
      case SessionList():
        _send(mobileId, SessionListResult([
          for (final s in _sessions.values)
            SessionInfo(
              id: s.id,
              index: s.index,
              shell: s.shell,
              createdAt: s.createdAt.millisecondsSinceEpoch,
              attached: s.attachedMobileId != null,
            ),
        ]));
      case SessionOpen(:final cols, :final rows):
        await _open(mobileId, cols, rows);
      case SessionAttach(:final id, :final cols, :final rows, :final lastSeq):
        _attach(mobileId, id, cols, rows, lastSeq);
      case InputMessage(:final id, :final data):
        _attachedTo(mobileId, id)?.pty.write(data);
      case ResizeMessage(:final id, :final cols, :final rows):
        final session = _attachedTo(mobileId, id);
        if (session != null) _resize(session, cols, rows);
      case AckMessage(:final id, :final seq):
        final session = _attachedTo(mobileId, id);
        if (session == null) return;
        session.acked = max(session.acked, min(seq, session.sent));
        _pump(session);
      case SessionClose(:final id):
        final session = _sessions[id];
        if (session == null) {
          _notFound(mobileId, id);
          return;
        }
        session.pty.kill();
      default:
        // pair.confirm is handled by AgentService; agent→phone types are
        // never accepted from a phone.
        break;
    }
  }

  /// The channel to [mobileId] is gone: its sessions become unattached
  /// (no message is sent).
  void mobileDisconnected(String mobileId) {
    var changed = false;
    for (final session in _sessions.values) {
      if (session.attachedMobileId == mobileId) {
        session.attachedMobileId = null;
        changed = true;
      }
      if (session.exitRecipient == mobileId) session.exitRecipient = null;
    }
    if (changed) _changes.add(null);
  }

  /// Kills every session attached to [mobileId] (used when revoking a phone).
  void closeSessionsAttachedTo(String mobileId) {
    for (final session in _sessions.values.toList()) {
      if (session.attachedMobileId == mobileId) session.pty.kill();
    }
  }

  /// Closes a session from the tray: `session.detached {closed_by_host}`
  /// now, `session.exited` once the shell is gone.
  void closeSession(int id) {
    final session = _sessions[id];
    if (session == null) return;
    final mobileId = session.attachedMobileId;
    if (mobileId != null) {
      _send(mobileId,
          SessionDetached(id: id, reason: DetachReason.closedByHost));
      session.attachedMobileId = null;
      session.exitRecipient = mobileId;
      _changes.add(null);
    }
    session.pty.kill();
  }

  void closeAll() {
    for (final id in _sessions.keys.toList()) {
      closeSession(id);
    }
  }

  Future<void> _open(String mobileId, int cols, int rows) async {
    if (_sessions.length + _pendingOpens >= _maxSessions) {
      _send(
          mobileId,
          ErrorMessage(
            code: AppErrorCode.sessionLimit,
            message: 'This machine already has $_maxSessions open sessions.',
          ));
      return;
    }
    final c = _clampDimension(cols);
    final r = _clampDimension(rows);
    _pendingOpens++;
    final ShellCommand command;
    final Pty pty;
    try {
      command = await _shellResolver.resolve();
      pty = _ptyFactory.spawn(
        command,
        workingDirectory: _homeDirectory,
        environment: buildSessionEnvironment(_baseEnvironment),
        cols: c,
        rows: r,
      );
    } catch (error) {
      _send(mobileId,
          ErrorMessage(code: AppErrorCode.spawnFailed, message: '$error'));
      return;
    } finally {
      _pendingOpens--;
    }
    final session = _Session(
      id: _nextId++,
      index: _lowestFreeIndex(),
      shell: command.name,
      createdAt: DateTime.now(),
      pty: pty,
      buffer: RingBuffer(_bufferCapacity),
      cols: c,
      rows: r,
      attachedMobileId: mobileId,
    );
    _sessions[session.id] = session;
    _send(mobileId, SessionOpened(
        id: session.id, index: session.index, shell: session.shell));
    _watch(session);
    _opened.add(SessionOpenedEvent(mobileId, session.id));
    _changes.add(null);
  }

  void _attach(String mobileId, int id, int cols, int rows, int lastSeq) {
    final session = _sessions[id];
    if (session == null) {
      _notFound(mobileId, id);
      return;
    }
    final previous = session.attachedMobileId;
    if (previous != null && previous != mobileId) {
      _send(previous, SessionDetached(id: id, reason: DetachReason.takenOver));
    }
    session.attachedMobileId = mobileId;
    session.exitRecipient = null;
    final buffer = session.buffer;
    if (lastSeq < buffer.start || lastSeq > buffer.end) {
      _send(mobileId, SessionReset(id: id));
      session.sent = buffer.start;
    } else {
      session.sent = lastSeq;
    }
    session.acked = session.sent;
    _pump(session);
    final c = _clampDimension(cols);
    final r = _clampDimension(rows);
    if (c == session.cols && r == session.rows) {
      // Same size: bounce the height so full-screen programs redraw.
      session.pty.resize(c, r > _minDimension ? r - 1 : r + 1);
      session.pty.resize(c, r);
    } else {
      session.cols = c;
      session.rows = r;
      session.pty.resize(c, r);
    }
    _send(mobileId, SessionAttached(id: id));
    if (previous != mobileId) _changes.add(null);
  }

  void _resize(_Session session, int cols, int rows) {
    final c = _clampDimension(cols);
    final r = _clampDimension(rows);
    if (c == session.cols && r == session.rows) return;
    session.cols = c;
    session.rows = r;
    session.pty.resize(c, r);
  }

  void _watch(_Session session) {
    final outputDone = Completer<void>();
    session.output = session.pty.output.listen(
      (data) {
        session.buffer.append(data);
        _pump(session);
      },
      onDone: outputDone.complete,
      onError: (Object _) {},
    );
    session.pty.exitCode.then((code) async {
      await outputDone.future.timeout(_outputDrainGrace, onTimeout: () {});
      _finish(session, code);
    }, onError: (Object _) => _finish(session, -1));
  }

  void _finish(_Session session, int exitCode) {
    if (!identical(_sessions[session.id], session)) return;
    _pump(session);
    final recipient = session.attachedMobileId ?? session.exitRecipient;
    _sessions.remove(session.id);
    session.output?.cancel();
    if (recipient != null) {
      _send(recipient, SessionExited(id: session.id, exitCode: exitCode));
    }
    _changes.add(null);
  }

  /// Sends buffered output to the attached phone while the send window
  /// allows. Data overwritten before it could be sent triggers a reset.
  void _pump(_Session session) {
    final mobileId = session.attachedMobileId;
    if (mobileId == null) return;
    final buffer = session.buffer;
    while (session.sent < buffer.end &&
        session.sent - session.acked < _sendWindow) {
      if (session.sent < buffer.start) {
        _send(mobileId, SessionReset(id: session.id));
        session.sent = buffer.start;
        session.acked = buffer.start;
        continue;
      }
      final room = _sendWindow - (session.sent - session.acked);
      final count =
          min(min(kMaxOutputChunk, buffer.end - session.sent), room);
      final data = buffer.read(session.sent, count);
      _send(mobileId,
          OutputMessage(id: session.id, seq: session.sent, data: data));
      session.sent += count;
    }
  }

  _Session? _attachedTo(String mobileId, int id) {
    final session = _sessions[id];
    return session != null && session.attachedMobileId == mobileId
        ? session
        : null;
  }

  int _lowestFreeIndex() {
    final used = {for (final s in _sessions.values) s.index};
    var index = 1;
    while (used.contains(index)) {
      index++;
    }
    return index;
  }

  void _notFound(String mobileId, int id) {
    _send(
        mobileId,
        ErrorMessage(
          code: AppErrorCode.sessionNotFound,
          message: 'Session $id not found',
          id: id,
        ));
  }

  void _send(String mobileId, AppMessage message) =>
      _outbound.add(OutboundMessage(mobileId, message));
}
```

Replace the whole content of `packages/shellx_agent/lib/shellx_agent.dart` with:

```dart
/// ShellX desktop agent logic: sessions, pairing responder, trust list.
library;

export 'src/pty/process_pty.dart';
export 'src/pty/pty.dart';
export 'src/pty/session_environment.dart';
export 'src/pty/shell_resolver.dart';
export 'src/session/ring_buffer.dart';
export 'src/session/session_manager.dart';
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/shellx_agent && dart test test/session`
Expected: `+31: All tests passed!` (15 + 10 + 6 ring buffer tests).

- [ ] **Step 6: Commit**

```bash
git add packages/shellx_agent/lib packages/shellx_agent/test/support/fake_pty.dart packages/shellx_agent/test/support/session_rig.dart packages/shellx_agent/test/session
git commit -m "feat(agent): add SessionManager with attach, reset and send window"
```

### Task 5: `TrustedStore` and `PairingCodeManager`

**Files:**
- Create: `packages/shellx_agent/lib/src/trust/trusted_store.dart`, `packages/shellx_agent/lib/src/pairing/pairing_code_manager.dart`
- Modify: `packages/shellx_agent/lib/shellx_agent.dart`
- Test: `packages/shellx_agent/test/trust/trusted_store_test.dart`, `packages/shellx_agent/test/pairing/pairing_code_manager_test.dart`

**Interfaces:**
- Consumes: core `KeyValueStore`, `InMemoryKeyValueStore`, `base64UrlNoPad`, `fromBase64UrlNoPad`.
- Produces (overview §5.6):
  - `final class TrustedDevice { const TrustedDevice({required String mobileId, required Uint8List publicKey, required String name, required DateTime pairedAt}); Map<String, Object?> toJson(); static TrustedDevice fromJson(Map<String, Object?> json); }` — JSON keys `mobile_id`, `public_key` (base64url), `name`, `paired_at` (unix ms).
  - `final class TrustedStore { TrustedStore(KeyValueStore store); static const String storageKey = 'trusted_devices'; Future<List<TrustedDevice>> list(); Future<TrustedDevice?> find(String mobileId); Future<void> add(TrustedDevice device); Future<void> remove(String mobileId); Future<void> clear(); Stream<void> get changes; }` — mutations are serialized; unreadable storage reads as empty (fail closed).
  - `final class PairingOffer { const PairingOffer({required Uint8List secret, required DateTime expiresAt}); }`
  - `final class PairingCodeManager { PairingCodeManager({DateTime Function()? now, Random? random}); PairingOffer create({Duration ttl = const Duration(minutes: 5)}); Uint8List? get activeSecret; void invalidate(); static const int secretLength = 32; }`

- [ ] **Step 1: Write the failing tests**

`packages/shellx_agent/test/trust/trusted_store_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

TrustedDevice device(String id, int keyByte, {String name = 'Phone'}) =>
    TrustedDevice(
      mobileId: id,
      publicKey: Uint8List.fromList(List.filled(32, keyByte)),
      name: name,
      pairedAt: DateTime.utc(2026, 9, 25, 10),
    );

void main() {
  test('TrustedDevice round-trips through JSON with a base64url key', () {
    final original = device('m1', 7, name: 'iPhone của Phú');
    final json = original.toJson();
    expect(json['public_key'], base64UrlNoPad(original.publicKey));
    expect(json['paired_at'], DateTime.utc(2026, 9, 25, 10).millisecondsSinceEpoch);
    final copy = TrustedDevice.fromJson(json);
    expect(copy.mobileId, 'm1');
    expect(copy.publicKey, original.publicKey);
    expect(copy.name, 'iPhone của Phú');
    expect(copy.pairedAt, original.pairedAt);
  });

  test('add, find, list, replace and remove', () async {
    final kv = InMemoryKeyValueStore();
    final store = TrustedStore(kv);
    expect(await store.list(), isEmpty);

    await store.add(device('m1', 1));
    await store.add(device('m2', 2));
    await store.add(device('m1', 3, name: 'New phone'));

    final all = await store.list();
    expect([for (final d in all) d.mobileId], ['m2', 'm1']);
    expect((await store.find('m1'))!.publicKey.first, 3);
    expect(await store.find('m9'), isNull);

    await store.remove('m2');
    expect([for (final d in await store.list()) d.mobileId], ['m1']);
    await store.clear();
    expect(await store.list(), isEmpty);
  });

  test('persists as a JSON array under trusted_devices', () async {
    final kv = InMemoryKeyValueStore();
    await TrustedStore(kv).add(device('m1', 1));
    final raw = await kv.read(TrustedStore.storageKey);
    expect(TrustedStore.storageKey, 'trusted_devices');
    expect(jsonDecode(raw!), isA<List<Object?>>());
    expect((await TrustedStore(kv).find('m1')), isNotNull);
  });

  test('corrupt storage fails closed (nobody is trusted)', () async {
    final kv = InMemoryKeyValueStore();
    await kv.write(TrustedStore.storageKey, '{not json');
    expect(await TrustedStore(kv).list(), isEmpty);
  });

  test('concurrent adds are not lost and changes fire per mutation', () async {
    final store = TrustedStore(InMemoryKeyValueStore());
    var changes = 0;
    store.changes.listen((_) => changes++);
    await Future.wait([
      store.add(device('m1', 1)),
      store.add(device('m2', 2)),
      store.add(device('m3', 3)),
    ]);
    await pumpEventQueue();
    expect(await store.list(), hasLength(3));
    expect(changes, 3);
  });
}
```

`packages/shellx_agent/test/pairing/pairing_code_manager_test.dart`:

```dart
import 'dart:math';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  late DateTime now;
  late PairingCodeManager manager;

  setUp(() {
    now = DateTime.utc(2026, 9, 25, 12);
    manager = PairingCodeManager(now: () => now, random: Random(1));
  });

  test('no code is active initially', () {
    expect(manager.activeSecret, isNull);
  });

  test('create returns a 32-byte secret valid for 5 minutes', () {
    final offer = manager.create();
    expect(offer.secret, hasLength(32));
    expect(offer.expiresAt, now.add(const Duration(minutes: 5)));
    expect(manager.activeSecret, offer.secret);

    now = now.add(const Duration(minutes: 4, seconds: 59));
    expect(manager.activeSecret, offer.secret);
    now = now.add(const Duration(seconds: 1));
    expect(manager.activeSecret, isNull);
  });

  test('a new code replaces the previous one', () {
    final first = manager.create();
    final second = manager.create();
    expect(second.secret, isNot(first.secret));
    expect(manager.activeSecret, second.secret);
  });

  test('invalidate removes the code', () {
    manager.create();
    manager.invalidate();
    expect(manager.activeSecret, isNull);
  });

  test('the default random source is secure and codes differ', () {
    final real = PairingCodeManager();
    expect(real.create().secret, isNot(real.create().secret));
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `cd packages/shellx_agent && dart test test/trust test/pairing`
Expected: FAIL — compilation errors `Couldn't find constructor 'TrustedDevice'`, `Couldn't find constructor 'PairingCodeManager'`.

- [ ] **Step 3: Implement**

`packages/shellx_agent/lib/src/trust/trusted_store.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

/// A phone this agent trusts (spec §5.3 step 5).
final class TrustedDevice {
  const TrustedDevice({
    required this.mobileId,
    required this.publicKey,
    required this.name,
    required this.pairedAt,
  });

  final String mobileId;
  final Uint8List publicKey;
  final String name;
  final DateTime pairedAt;

  Map<String, Object?> toJson() => {
        'mobile_id': mobileId,
        'public_key': base64UrlNoPad(publicKey),
        'name': name,
        'paired_at': pairedAt.millisecondsSinceEpoch,
      };

  static TrustedDevice fromJson(Map<String, Object?> json) => TrustedDevice(
        mobileId: json['mobile_id'] as String,
        publicKey: fromBase64UrlNoPad(json['public_key'] as String),
        name: json['name'] as String,
        pairedAt: DateTime.fromMillisecondsSinceEpoch(json['paired_at'] as int,
            isUtc: true),
      );
}

/// Local trust list — the only source of truth for trust (spec §5.4).
/// Stored as a JSON array under [storageKey]. Unreadable data counts as
/// "no trusted devices" (fail closed).
final class TrustedStore {
  TrustedStore(KeyValueStore store) : _store = store;

  static const String storageKey = 'trusted_devices';

  final KeyValueStore _store;
  final _changes = StreamController<void>.broadcast();
  Future<void> _lock = Future.value();

  Stream<void> get changes => _changes.stream;

  Future<List<TrustedDevice>> list() => _read();

  Future<TrustedDevice?> find(String mobileId) async {
    for (final device in await _read()) {
      if (device.mobileId == mobileId) return device;
    }
    return null;
  }

  /// Adds [device], replacing an entry with the same mobileId.
  Future<void> add(TrustedDevice device) => _mutate((devices) => [
        ...devices.where((d) => d.mobileId != device.mobileId),
        device,
      ]);

  Future<void> remove(String mobileId) => _mutate(
      (devices) => devices.where((d) => d.mobileId != mobileId).toList());

  Future<void> clear() => _mutate((_) => const []);

  Future<List<TrustedDevice>> _read() async {
    final raw = await _store.read(storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<Object?>;
      return [
        for (final entry in decoded)
          TrustedDevice.fromJson((entry as Map).cast<String, Object?>()),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _mutate(
      List<TrustedDevice> Function(List<TrustedDevice> devices) change) {
    final next = _lock.then((_) async {
      final updated = change(await _read());
      await _store.write(
          storageKey, jsonEncode([for (final d in updated) d.toJson()]));
      _changes.add(null);
    });
    _lock = next.catchError((Object _) {});
    return next;
  }
}
```

`packages/shellx_agent/lib/src/pairing/pairing_code_manager.dart`:

```dart
import 'dart:math';
import 'dart:typed_data';

/// A pairing code shown in the QR window.
final class PairingOffer {
  const PairingOffer({required this.secret, required this.expiresAt});
  final Uint8List secret;
  final DateTime expiresAt;
}

/// Holds at most one single-use pairing code (spec §5.3 step 1):
/// 32 random bytes, valid for 5 minutes or until invalidated.
final class PairingCodeManager {
  PairingCodeManager({DateTime Function()? now, Random? random})
      : _now = now ?? DateTime.now,
        _random = random ?? Random.secure();

  static const int secretLength = 32;

  final DateTime Function() _now;
  final Random _random;
  PairingOffer? _offer;

  /// Creates a new code, replacing any previous one.
  PairingOffer create({Duration ttl = const Duration(minutes: 5)}) {
    final secret = Uint8List(secretLength);
    for (var i = 0; i < secret.length; i++) {
      secret[i] = _random.nextInt(256);
    }
    return _offer = PairingOffer(secret: secret, expiresAt: _now().add(ttl));
  }

  /// The current code, or null when there is none or it has expired.
  Uint8List? get activeSecret {
    final offer = _offer;
    if (offer == null) return null;
    if (!_now().isBefore(offer.expiresAt)) {
      _offer = null;
      return null;
    }
    return offer.secret;
  }

  void invalidate() => _offer = null;
}
```

Replace the whole content of `packages/shellx_agent/lib/shellx_agent.dart` with:

```dart
/// ShellX desktop agent logic: sessions, pairing responder, trust list.
library;

export 'src/pairing/pairing_code_manager.dart';
export 'src/pty/process_pty.dart';
export 'src/pty/pty.dart';
export 'src/pty/session_environment.dart';
export 'src/pty/shell_resolver.dart';
export 'src/session/ring_buffer.dart';
export 'src/session/session_manager.dart';
export 'src/trust/trusted_store.dart';
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/shellx_agent && dart test test/trust test/pairing`
Expected: `+10: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_agent/lib packages/shellx_agent/test/trust packages/shellx_agent/test/pairing
git commit -m "feat(agent): add TrustedStore and PairingCodeManager"
```

### Task 6: In-memory relay harness (`FakeRelay`, fake sockets, `drive`)

**Files:**
- Create: `packages/shellx_agent/test/support/drive.dart`, `packages/shellx_agent/test/support/fake_relay.dart`
- Test: `packages/shellx_agent/test/support/fake_relay_test.dart`

**Interfaces:**
- Consumes: core `RelaySocket`, `RelaySocketConnector`, `RelayConnection`, `Backoff`, frames (§5.1), `ShellxApi`, `DeviceKind`, `DevicePlatform`, `RelayCloseCode`.
- Produces (test-only, reused by Tasks 9, 12–14):
  - `T drive<T>(FakeAsync async, Future<T> future, {Duration limit = const Duration(seconds: 60)})` — advances fake time in 1 ms steps until the future completes; rethrows its error. `void settle(FakeAsync async, [Duration duration = const Duration(milliseconds: 100)])`.
  - `final class FakeRelay` — overview §4.1 hub semantics: DATA routed only inside one account with `peer` rewritten to the source; `ERROR peer_offline` (with device id and channel) for offline peers or other accounts; PRESENCE to others on connect/disconnect and the list of online devices to the newcomer (self excluded); a second connection of the same device closes the first with 4001; frames > 64 KiB → `ERROR frame_too_large`; `ping` → `pong`. Members: `wsUri`, `baseUri`, `addDevice({id, userId, kind, name?, platform?}) → FakeDevice` (token `token-<id>`), `connector`, `httpClient` (`MockClient`: `GET /v1/devices`, `POST /v1/pairings`, `DELETE /v1/pairings/:a/:m` which sends `pairing_removed` to the other party), `isOnline`, `dropConnection(id, {int code = 1006})`, `setReachable(id, bool)`, `sendEvent(id, map)`, `pairings`, `requests`, `delivered`, `onData` hook `DataFrame? Function(String from, String to, DataFrame frame)` (return null to drop).

- [ ] **Step 1: Write the failing test**

`packages/shellx_agent/test/support/fake_relay_test.dart`:

```dart
import 'dart:math';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'drive.dart';
import 'fake_relay.dart';

const userA = 'user-a';
const userB = 'user-b';
const agentId = 'a0000000-0000-4000-8000-000000000001';
const phoneId = 'b0000000-0000-4000-8000-000000000002';
const strangerId = 'c0000000-0000-4000-8000-000000000009';

RelayConnection connect(FakeRelay relay, FakeDevice device) => RelayConnection(
      wsUri: relay.wsUri,
      token: () => device.token,
      connector: relay.connector,
      backoff: Backoff(random: Random(3)),
    );

void main() {
  test('routes DATA inside one account, rewriting peer to the source', () {
    fakeAsync((async) {
      final relay = FakeRelay();
      final agent = relay.addDevice(id: agentId, userId: userA, kind: DeviceKind.agent);
      final phone = relay.addDevice(id: phoneId, userId: userA, kind: DeviceKind.mobile);
      final a = connect(relay, agent)..start();
      final p = connect(relay, phone)..start();
      final atAgent = <RelayFrame>[];
      a.frames.listen(atAgent.add);
      settle(async);

      final channel = ChannelId.random(Random(1));
      p.send(DataFrame(peer: agentId, channel: channel, payload: Uint8List.fromList([4, 1, 2])));
      settle(async);

      final data = atAgent.whereType<DataFrame>().single;
      expect(data.peer, phoneId);
      expect(data.channel, channel);
      expect(data.payload, [4, 1, 2]);
    });
  });

  test('sends PRESENCE on connect and disconnect', () {
    fakeAsync((async) {
      final relay = FakeRelay();
      final agent = relay.addDevice(id: agentId, userId: userA, kind: DeviceKind.agent);
      final phone = relay.addDevice(id: phoneId, userId: userA, kind: DeviceKind.mobile);
      final a = connect(relay, agent)..start();
      final atAgent = <PresenceFrame>[];
      a.frames.listen((f) {
        if (f is PresenceFrame) atAgent.add(f);
      });
      settle(async);
      final p = connect(relay, phone)..start();
      final atPhone = <PresenceFrame>[];
      p.frames.listen((f) {
        if (f is PresenceFrame) atPhone.add(f);
      });
      settle(async);
      expect([for (final f in atPhone) (f.deviceId, f.online)], [(agentId, true)]);
      expect([for (final f in atAgent) (f.deviceId, f.online)], [(phoneId, true)]);

      relay.setReachable(phoneId, false);
      relay.dropConnection(phoneId);
      settle(async);
      expect([for (final f in atAgent) (f.deviceId, f.online)],
          [(phoneId, true), (phoneId, false)]);
      expect(relay.isOnline(phoneId), isFalse);
    });
  });

  test('answers peer_offline for offline peers and other accounts', () {
    fakeAsync((async) {
      final relay = FakeRelay();
      final phone = relay.addDevice(id: phoneId, userId: userA, kind: DeviceKind.mobile);
      final stranger = relay.addDevice(id: strangerId, userId: userB, kind: DeviceKind.agent);
      final p = connect(relay, phone)..start();
      connect(relay, stranger).start();
      final errors = <ErrorFrame>[];
      p.frames.listen((f) {
        if (f is ErrorFrame) errors.add(f);
      });
      settle(async);

      final channel = ChannelId.random(Random(2));
      p.send(DataFrame(peer: strangerId, channel: channel, payload: Uint8List(1)));
      p.send(DataFrame(peer: agentId, channel: channel, payload: Uint8List(1)));
      settle(async);

      expect([for (final e in errors) (e.code, e.deviceId, e.channel)], [
        (RelayErrorCode.peerOffline, strangerId, channel),
        (RelayErrorCode.peerOffline, agentId, channel),
      ]);
      expect(relay.delivered, isEmpty);
    });
  });

  test('a second connection of the same device replaces the first (4001)', () {
    fakeAsync((async) {
      final relay = FakeRelay();
      final phone = relay.addDevice(id: phoneId, userId: userA, kind: DeviceKind.mobile);
      final first = connect(relay, phone)..start();
      settle(async);
      final second = connect(relay, phone)..start();
      settle(async);
      expect(first.state, RelayConnectionState.replaced);
      expect(second.state, RelayConnectionState.connected);
    });
  });

  test('answers ping with pong so connections stay up', () {
    fakeAsync((async) {
      final relay = FakeRelay();
      final phone = relay.addDevice(id: phoneId, userId: userA, kind: DeviceKind.mobile);
      final p = connect(relay, phone)..start();
      async.elapse(const Duration(minutes: 3));
      expect(p.state, RelayConnectionState.connected);
    });
  });

  test('serves devices, pairings and pairing removal over HTTP', () {
    fakeAsync((async) {
      final relay = FakeRelay();
      final agent = relay.addDevice(id: agentId, userId: userA, kind: DeviceKind.agent);
      final phone = relay.addDevice(id: phoneId, userId: userA, kind: DeviceKind.mobile);
      relay.addDevice(id: strangerId, userId: userB, kind: DeviceKind.agent);
      final agentApi = ShellxApi(baseUri: relay.baseUri, httpClient: relay.httpClient)
        ..token = agent.token;
      final phoneApi = ShellxApi(baseUri: relay.baseUri, httpClient: relay.httpClient)
        ..token = phone.token;
      final a = connect(relay, agent)..start();
      final events = <EventFrame>[];
      a.frames.listen((f) {
        if (f is EventFrame) events.add(f);
      });
      settle(async);

      final devices = drive(async, phoneApi.devices());
      expect({for (final d in devices) d.id}, {agentId, phoneId});
      expect(devices.firstWhere((d) => d.id == agentId).online, isTrue);

      drive(async, agentApi.createPairing(phoneId));
      expect(relay.pairings, {(agentId, phoneId)});
      drive(async, phoneApi.deletePairing(agentId, phoneId));
      settle(async);
      expect(relay.pairings, isEmpty);
      expect(events.single.event,
          {'event': 'pairing_removed', 'agent_id': agentId, 'mobile_id': phoneId});
      expect(relay.requests, [
        'GET /v1/devices',
        'POST /v1/pairings',
        'DELETE /v1/pairings/$agentId/$phoneId',
      ]);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/shellx_agent && dart test test/support/fake_relay_test.dart`
Expected: FAIL — `Error when reading 'test/support/drive.dart'` / `'fake_relay.dart'`: file not found.

- [ ] **Step 3: Implement the harness**

`packages/shellx_agent/test/support/drive.dart`:

```dart
import 'package:fake_async/fake_async.dart';

/// Advances fake time in 1 ms steps until [future] completes, then returns
/// its value (or rethrows its error). Fails after [limit] of fake time.
T drive<T>(FakeAsync async, Future<T> future,
    {Duration limit = const Duration(seconds: 60)}) {
  var done = false;
  late T value;
  Object? error;
  StackTrace? stackTrace;
  future.then((v) {
    value = v;
    done = true;
  }, onError: (Object e, StackTrace s) {
    error = e;
    stackTrace = s;
    done = true;
  });
  var waited = Duration.zero;
  const step = Duration(milliseconds: 1);
  while (!done) {
    if (waited >= limit) {
      throw StateError('Future did not complete within $limit of fake time');
    }
    async.elapse(step);
    waited += step;
  }
  if (error != null) Error.throwWithStackTrace(error!, stackTrace!);
  return value;
}

/// Lets timers and microtasks run for [duration] of fake time.
void settle(FakeAsync async,
    [Duration duration = const Duration(milliseconds: 100)]) {
  async.elapse(duration);
}
```

`packages/shellx_agent/test/support/fake_relay.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shellx_core/shellx_core.dart';

/// A device registered with the [FakeRelay].
final class FakeDevice {
  FakeDevice({
    required this.id,
    required this.userId,
    required this.kind,
    required this.name,
    required this.platform,
  }) : token = 'token-$id';

  final String id;
  final String userId;
  final DeviceKind kind;
  final String name;
  final DevicePlatform platform;
  final String token;
}

/// Thrown by the fake connector while a device is marked unreachable.
final class FakeRelayUnreachable implements Exception {
  const FakeRelayUnreachable(this.deviceId);
  final String deviceId;
  @override
  String toString() => 'FakeRelayUnreachable($deviceId)';
}

/// In-memory relay: the `UserHub` routing of overview §4.1 behind fake
/// [RelaySocket]s, plus the REST endpoints the agent and client call
/// (`GET /v1/devices`, `POST /v1/pairings`, `DELETE /v1/pairings/:a/:m`)
/// behind a `MockClient`.
final class FakeRelay {
  final Uri wsUri = Uri.parse('ws://relay.test/v1/ws');
  final Uri baseUri = Uri.parse('http://relay.test');

  final _devices = <String, FakeDevice>{};
  final _connections = <String, FakeRelaySocket>{};
  final _unreachable = <String>{};

  /// Display-only pairing records: (agentId, mobileId).
  final pairings = <(String, String)>{};

  /// Every HTTP request served, as "METHOD /path".
  final requests = <String>[];

  /// Every DATA frame delivered: (from, to, payload).
  final delivered = <({String from, String to, Uint8List payload})>[];

  /// Optional hook applied to each DATA frame before delivery. It receives
  /// the frame as the target would see it (peer = source) and returns the
  /// frame to deliver, or null to drop it.
  DataFrame? Function(String from, String to, DataFrame frame)? onData;

  FakeDevice addDevice({
    required String id,
    required String userId,
    required DeviceKind kind,
    String? name,
    DevicePlatform? platform,
  }) {
    final device = FakeDevice(
      id: id,
      userId: userId,
      kind: kind,
      name: name ?? (kind == DeviceKind.agent ? 'Test Mac' : 'Test Phone'),
      platform: platform ??
          (kind == DeviceKind.agent ? DevicePlatform.macos : DevicePlatform.ios),
    );
    _devices[id] = device;
    return device;
  }

  RelaySocketConnector get connector => _connect;

  http.Client get httpClient => MockClient(_handleHttp);

  bool isOnline(String deviceId) => _connections.containsKey(deviceId);

  /// Closes the device's socket from the hub side (network drop by default).
  void dropConnection(String deviceId, {int code = 1006}) =>
      _connections[deviceId]?.serverClose(code);

  /// While unreachable, connection attempts from the device fail.
  void setReachable(String deviceId, bool reachable) {
    if (reachable) {
      _unreachable.remove(deviceId);
    } else {
      _unreachable.add(deviceId);
    }
  }

  /// Sends an EVENT frame to one device (if online).
  void sendEvent(String deviceId, Map<String, String> event) =>
      _connections[deviceId]?.deliver(EventFrame(event).encode());

  Future<RelaySocket> _connect(Uri uri, Map<String, String> headers) async {
    final authorization =
        headers['Authorization'] ?? headers['authorization'] ?? '';
    final token = authorization.replaceFirst('Bearer ', '');
    final device =
        _devices.values.where((d) => d.token == token).firstOrNull;
    if (device == null) throw StateError('unknown token');
    if (_unreachable.contains(device.id)) {
      throw FakeRelayUnreachable(device.id);
    }
    _connections[device.id]?.serverClose(RelayCloseCode.replaced);
    final socket = FakeRelaySocket._(this, device);
    _connections[device.id] = socket;
    for (final other in _connections.values) {
      if (identical(other, socket) || other.device.userId != device.userId) {
        continue;
      }
      socket.deliver(
          PresenceFrame(deviceId: other.device.id, online: true).encode());
      other.deliver(PresenceFrame(deviceId: device.id, online: true).encode());
    }
    return socket;
  }

  void _onClientFrame(FakeRelaySocket from, Uint8List bytes) {
    if (bytes.length > kMaxFrameBytes) {
      from.deliver(ErrorFrame(code: RelayErrorCode.frameTooLarge).encode());
      return;
    }
    final RelayFrame frame;
    try {
      frame = RelayFrame.decode(bytes);
    } on FrameFormatException {
      from.deliver(ErrorFrame(code: RelayErrorCode.badFrame).encode());
      return;
    }
    if (frame is! DataFrame) {
      from.deliver(ErrorFrame(code: RelayErrorCode.badFrame).encode());
      return;
    }
    final target = _connections[frame.peer];
    if (target == null || target.device.userId != from.device.userId) {
      from.deliver(ErrorFrame(
        code: RelayErrorCode.peerOffline,
        deviceId: frame.peer,
        channel: frame.channel,
      ).encode());
      return;
    }
    DataFrame? outgoing = DataFrame(
        peer: from.device.id, channel: frame.channel, payload: frame.payload);
    final hook = onData;
    if (hook != null) outgoing = hook(from.device.id, frame.peer, outgoing);
    if (outgoing == null) return;
    delivered.add(
        (from: from.device.id, to: frame.peer, payload: outgoing.payload));
    target.deliver(outgoing.encode());
  }

  void _onDisconnected(FakeRelaySocket socket) {
    final id = socket.device.id;
    if (!identical(_connections[id], socket)) return;
    _connections.remove(id);
    for (final other in _connections.values) {
      if (other.device.userId != socket.device.userId) continue;
      other.deliver(PresenceFrame(deviceId: id, online: false).encode());
    }
  }

  Future<http.Response> _handleHttp(http.Request request) async {
    requests.add('${request.method} ${request.url.path}');
    final authorization = request.headers['authorization'] ??
        request.headers['Authorization'] ??
        '';
    final token = authorization.replaceFirst('Bearer ', '');
    final caller = _devices.values.where((d) => d.token == token).firstOrNull;
    if (caller == null) {
      return _error(401, 'unauthorized', 'Missing or invalid token');
    }
    final segments = request.url.pathSegments;
    if (request.method == 'GET' && request.url.path == '/v1/devices') {
      return http.Response(
        jsonEncode([
          for (final d in _devices.values)
            if (d.userId == caller.userId)
              {
                'id': d.id,
                'kind': d.kind.name,
                'name': d.name,
                'platform': d.platform.name,
                'online': isOnline(d.id),
                'last_seen_at': null,
                'paired_with_me': pairings.contains((d.id, caller.id)) ||
                    pairings.contains((caller.id, d.id)),
              },
        ]),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'POST' && request.url.path == '/v1/pairings') {
      if (caller.kind != DeviceKind.agent) {
        return _error(403, 'agent_only', 'Only an agent can create pairings');
      }
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final mobile = _devices[body['mobile_id']];
      if (mobile == null ||
          mobile.userId != caller.userId ||
          mobile.kind != DeviceKind.mobile) {
        return _error(404, 'device_not_found', 'Device not found');
      }
      pairings.add((caller.id, mobile.id));
      return http.Response('', 201);
    }
    if (request.method == 'DELETE' &&
        segments.length == 4 &&
        segments[0] == 'v1' &&
        segments[1] == 'pairings') {
      final agentId = segments[2];
      final mobileId = segments[3];
      if (caller.id != agentId && caller.id != mobileId) {
        return _error(403, 'forbidden', 'Not part of this pairing');
      }
      pairings.remove((agentId, mobileId));
      final other = caller.id == agentId ? mobileId : agentId;
      sendEvent(other, {
        'event': 'pairing_removed',
        'agent_id': agentId,
        'mobile_id': mobileId,
      });
      return http.Response('', 204);
    }
    return _error(404, 'not_found', 'Not found');
  }

  http.Response _error(int status, String code, String message) =>
      http.Response(
        jsonEncode({
          'error': {'code': code, 'message': message},
        }),
        status,
        headers: {'content-type': 'application/json'},
      );
}

/// Client end of a fake WebSocket. Answers `ping` with `pong` like the hub's
/// auto-response.
final class FakeRelaySocket implements RelaySocket {
  FakeRelaySocket._(this._relay, this.device);

  final FakeRelay _relay;
  final FakeDevice device;
  final _incoming = StreamController<Object>();
  int? _closeCode;
  bool _closed = false;

  @override
  Stream<Object> get messages => _incoming.stream;

  @override
  int? get closeCode => _closeCode;

  @override
  void sendText(String text) {
    if (_closed) return;
    if (text == 'ping') _incoming.add('pong');
  }

  @override
  void sendBytes(Uint8List bytes) {
    if (_closed) return;
    _relay._onClientFrame(this, Uint8List.fromList(bytes));
  }

  @override
  Future<void> close([int? code, String? reason]) async =>
      _terminate(code ?? 1005);

  void serverClose(int code) => _terminate(code);

  void deliver(Uint8List bytes) {
    if (!_closed) _incoming.add(bytes);
  }

  void _terminate(int code) {
    if (_closed) return;
    _closed = true;
    _closeCode = code;
    _incoming.close();
    _relay._onDisconnected(this);
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/shellx_agent && dart test test/support/fake_relay_test.dart`
Expected: `+6: All tests passed!` If `a second connection … replaces the first` or `answers ping with pong` fails, compare core's `RelayConnection` with overview §5.5 (4001 → `replaced`, ping every 30 s, pong within 10 s) before touching the fake.

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_agent/test/support/drive.dart packages/shellx_agent/test/support/fake_relay.dart packages/shellx_agent/test/support/fake_relay_test.dart
git commit -m "test(agent): add in-memory fake relay harness"
```

### Task 7: `AgentChannel` — per-channel batching (16 ms / 16 KiB) and frame-sized splitting

**Files:**
- Create: `packages/shellx_agent/lib/src/service/agent_channel.dart` (internal, not exported)
- Test: `packages/shellx_agent/test/service/agent_channel_test.dart`

**Interfaces:**
- Consumes: core `SecureChannel`, `ChannelId`, `DataFrame`, `RelayFrame`, `AppMessage`, `OutputMessage`, `encodeBatch`, `kMaxSealedBatchBytes`; `drive` (Task 6).
- Produces (used by Task 9):
  - `const int kFlushThresholdBytes = 16 * 1024;`
  - `List<List<AppMessage>> splitIntoBatches(List<AppMessage> messages)` — order-preserving, each batch's `encodeBatch` ≤ `kMaxSealedBatchBytes`.
  - `final class AgentChannel { AgentChannel({required String mobileId, required ChannelId channelId, required String name, required Uint8List remoteStatic, required SecureChannel secure, required bool Function(RelayFrame frame) send, Uint8List? pairingSecret, Duration flushInterval = const Duration(milliseconds: 16)}); bool get isPairing; Future<List<AppMessage>> open(Uint8List noiseMessage); void enqueue(AppMessage message); void flush(); void close(); }` — first pending message starts a one-shot `flushInterval` timer; pending output ≥ 16 KiB schedules a microtask flush (so one synchronous pump burst is collected); seals are chained so nonces go out in order.

- [ ] **Step 1: Write the failing test**

`packages/shellx_agent/test/service/agent_channel_test.dart`:

```dart
import 'dart:math';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/src/service/agent_channel.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/drive.dart';

const agentId = 'a0000000-0000-4000-8000-000000000001';
const phoneId = 'b0000000-0000-4000-8000-000000000002';

/// Two ends of an established IK channel: (agent side, phone side).
Future<(SecureChannel, SecureChannel)> securePair() async {
  final agentKey = await NoiseKeyPair.generate();
  final phoneKey = await NoiseKeyPair.generate();
  final prologue = buildPrologue(agentDeviceId: agentId, mobileDeviceId: phoneId);
  final initiator = NoiseHandshake.initiator(
      pattern: NoisePattern.ik,
      localStatic: phoneKey,
      remoteStatic: agentKey.publicKey,
      prologue: prologue);
  final responder = NoiseHandshake.responder(
      pattern: NoisePattern.ik, localStatic: agentKey, prologue: prologue);
  await responder.readMessage(await initiator.writeMessage());
  await initiator.readMessage(await responder.writeMessage());
  return (SecureChannel(responder.split()), SecureChannel(initiator.split()));
}

OutputMessage output(int seq, int length) =>
    OutputMessage(id: 1, seq: seq, data: Uint8List(length));

void main() {
  late SecureChannel agentSide;
  late SecureChannel phoneSide;
  late ChannelId channelId;

  setUp(() async {
    (agentSide, phoneSide) = await securePair();
    channelId = ChannelId.random(Random(5));
  });

  AgentChannel newChannel(List<DataFrame> sent, {Uint8List? pairingSecret}) =>
      AgentChannel(
        mobileId: phoneId,
        channelId: channelId,
        name: 'Pixel',
        remoteStatic: Uint8List(32),
        secure: agentSide,
        send: (frame) {
          sent.add(frame as DataFrame);
          return true;
        },
        pairingSecret: pairingSecret,
      );

  List<AppMessage> openFrame(FakeAsync async, DataFrame frame) {
    final payload = ChannelPayload.decode(frame.payload);
    expect(payload.kind, PayloadKind.transport);
    return drive(async, phoneSide.open(payload.noiseMessage));
  }

  test('messages queued within 16 ms go out together in one TRANSPORT', () {
    fakeAsync((async) {
      final sent = <DataFrame>[];
      final channel = newChannel(sent);
      channel.enqueue(output(0, 10));
      async.elapse(const Duration(milliseconds: 5));
      channel.enqueue(const SessionAttached(id: 1));
      async.elapse(const Duration(milliseconds: 10));
      expect(sent, isEmpty);
      async.elapse(const Duration(milliseconds: 1));

      expect(sent, hasLength(1));
      expect(sent.single.peer, phoneId);
      expect(sent.single.channel, channelId);
      final batch = openFrame(async, sent.single);
      expect(batch.map((m) => m.type), ['output', 'session.attached']);
    });
  });

  test('pending output reaching 16 KiB is flushed immediately', () {
    fakeAsync((async) {
      final sent = <DataFrame>[];
      final channel = newChannel(sent);
      channel.enqueue(output(0, 10 * 1024));
      async.flushMicrotasks();
      expect(sent, isEmpty);
      channel.enqueue(output(10 * 1024, 6 * 1024));
      async.flushMicrotasks();

      expect(sent, hasLength(1));
      expect(openFrame(async, sent.single), hasLength(2));
    });
  });

  test('a burst of full chunks is split into payloads that fit a frame', () {
    fakeAsync((async) {
      final sent = <DataFrame>[];
      final channel = newChannel(sent);
      for (var i = 0; i < 5; i++) {
        channel.enqueue(output(i * 16 * 1024, 16 * 1024));
      }
      async.flushMicrotasks();

      final batches = [for (final frame in sent) openFrame(async, frame)];
      expect([for (final b in batches) b.length], [3, 2]);
      for (final frame in sent) {
        expect(frame.encode().length, lessThanOrEqualTo(kMaxFrameBytes));
      }
      expect([for (final b in batches) for (final m in b) (m as OutputMessage).seq],
          [for (var i = 0; i < 5; i++) i * 16 * 1024]);
    });
  });

  test('splitIntoBatches measures encoded sizes', () {
    final small = [for (var i = 0; i < 50; i++) SessionAttached(id: i)];
    expect(splitIntoBatches(small), hasLength(1));
    final big = [for (var i = 0; i < 7; i++) output(0, 16 * 1024)];
    final batches = splitIntoBatches(big);
    expect([for (final b in batches) b.length], [3, 3, 1]);
    for (final batch in batches) {
      expect(encodeBatch(batch).length, lessThanOrEqualTo(kMaxSealedBatchBytes));
    }
  });

  test('batches are sealed and sent in order', () {
    fakeAsync((async) {
      final sent = <DataFrame>[];
      final channel = newChannel(sent);
      channel.enqueue(output(0, 1));
      async.elapse(const Duration(milliseconds: 16));
      channel.enqueue(output(1, 16 * 1024));
      channel.enqueue(output(16 * 1024 + 1, 1));
      async.elapse(const Duration(milliseconds: 16));

      expect(sent, hasLength(2));
      final seqs = [
        for (final frame in sent)
          for (final m in openFrame(async, frame)) (m as OutputMessage).seq,
      ];
      expect(seqs, [0, 1, 16 * 1024 + 1]);
    });
  });

  test('close drops pending messages and stops sending', () {
    fakeAsync((async) {
      final sent = <DataFrame>[];
      final channel = newChannel(sent);
      channel.enqueue(output(0, 1));
      channel.close();
      channel.enqueue(output(1, 1));
      async.elapse(const Duration(milliseconds: 50));
      expect(sent, isEmpty);
    });
  });

  test('isPairing is true only for channels created with a pairing secret',
      () {
    expect(newChannel([]).isPairing, isFalse);
    expect(newChannel([], pairingSecret: Uint8List(32)).isPairing, isTrue);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/shellx_agent && dart test test/service/agent_channel_test.dart`
Expected: FAIL — `Error when reading 'lib/src/service/agent_channel.dart'`.

- [ ] **Step 3: Implement**

`packages/shellx_agent/lib/src/service/agent_channel.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

/// Pending output that triggers an immediate flush (spec §6.5).
const int kFlushThresholdBytes = 16 * 1024;

/// Upper bound for a CBOR array header of up to 65535 items.
const int _arrayHeaderAllowance = 3;

/// Splits [messages], in order, into batches whose encoded CBOR array stays
/// within [kMaxSealedBatchBytes] (so each sealed DATA frame is ≤ 64 KiB).
/// Sizes are measured with [encodeBatch]; three full 16 KiB outputs fit in
/// one batch, four do not.
List<List<AppMessage>> splitIntoBatches(List<AppMessage> messages) {
  final batches = <List<AppMessage>>[];
  var current = <AppMessage>[];
  var size = _arrayHeaderAllowance;
  for (final message in messages) {
    final messageSize = encodeBatch([message]).length - 1;
    if (current.isNotEmpty && size + messageSize > kMaxSealedBatchBytes) {
      batches.add(current);
      current = <AppMessage>[];
      size = _arrayHeaderAllowance;
    }
    current.add(message);
    size += messageSize;
  }
  if (current.isNotEmpty) batches.add(current);
  return batches;
}

/// One established encrypted channel to a phone.
///
/// Outgoing messages are batched: everything pending is sent
/// [flushInterval] after the first pending message, or immediately (in a
/// microtask, so a synchronous burst from one pump is collected first) once
/// pending `output` data reaches [kFlushThresholdBytes]. A flush produces as
/// many TRANSPORT payloads as [splitIntoBatches] needs. Sealing is serialized
/// so Noise nonces go out in order.
final class AgentChannel {
  AgentChannel({
    required this.mobileId,
    required this.channelId,
    required this.name,
    required this.remoteStatic,
    required SecureChannel secure,
    required bool Function(RelayFrame frame) send,
    this.pairingSecret,
    Duration flushInterval = const Duration(milliseconds: 16),
  })  : _secure = secure,
        _send = send,
        _flushInterval = flushInterval;

  final String mobileId;
  final ChannelId channelId;

  /// Device name from the HS1 payload.
  final String name;

  /// The phone's static public key proven by the handshake.
  final Uint8List remoteStatic;

  /// Pairing code used as PSK; non-null only for a pairing (IKpsk2) channel.
  final Uint8List? pairingSecret;

  final SecureChannel _secure;
  final bool Function(RelayFrame frame) _send;
  final Duration _flushInterval;
  final _pending = <AppMessage>[];
  int _pendingOutputBytes = 0;
  Timer? _timer;
  bool _flushScheduled = false;
  Future<void> _sendChain = Future.value();
  bool _closed = false;

  bool get isPairing => pairingSecret != null;

  Future<List<AppMessage>> open(Uint8List noiseMessage) =>
      _secure.open(noiseMessage);

  void enqueue(AppMessage message) {
    if (_closed) return;
    _pending.add(message);
    if (message is OutputMessage) _pendingOutputBytes += message.data.length;
    if (_pendingOutputBytes >= kFlushThresholdBytes) {
      _timer?.cancel();
      _timer = null;
      if (!_flushScheduled) {
        _flushScheduled = true;
        scheduleMicrotask(flush);
      }
    } else {
      _timer ??= Timer(_flushInterval, flush);
    }
  }

  void flush() {
    _flushScheduled = false;
    _timer?.cancel();
    _timer = null;
    if (_closed || _pending.isEmpty) return;
    final batches = splitIntoBatches(_pending);
    _pending.clear();
    _pendingOutputBytes = 0;
    for (final batch in batches) {
      _sendChain = _sendChain.then((_) async {
        final payload = await _secure.seal(batch);
        if (_closed) return;
        _send(DataFrame(peer: mobileId, channel: channelId, payload: payload));
      }).catchError((Object _) {});
    }
  }

  void close() {
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/shellx_agent && dart test test/service/agent_channel_test.dart`
Expected: `+7: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_agent/lib/src/service/agent_channel.dart packages/shellx_agent/test/service/agent_channel_test.dart
git commit -m "feat(agent): add per-channel output batching"
```

### Task 8: `HandshakeResponder` — HS1_IK / HS1_IKPSK2, HS2 status, trust binding

**Files:**
- Create: `packages/shellx_agent/lib/src/service/handshake_responder.dart` (internal, not exported)
- Test: `packages/shellx_agent/test/service/handshake_responder_test.dart`

**Interfaces:**
- Consumes: `TrustedStore`, `TrustedDevice`, `PairingCodeManager` (Task 5); core `NoiseHandshake`, `NoisePattern`, `NoiseKeyPair`, `NoiseTransport`, `Hs1Payload`, `Hs2Payload`, `HandshakeStatus`, `kAppProtocolVersion`, `ChannelPayload`, `PayloadKind`, `buildPrologue`, `constantTimeEquals`.
- Produces (used by Task 9):
  - `final class HandshakeAnswer { Uint8List reply /* encoded ChannelPayload(hs2) */; HandshakeStatus status; Hs1Payload hello; Uint8List remoteStatic; NoiseTransport? transport /* only when ok */; Uint8List? pairingSecret /* only for an accepted IKpsk2 */; }`
  - `final class HandshakeResponder { HandshakeResponder({required String deviceId, required NoiseKeyPair identity, required String appVersion, required TrustedStore trusted, required PairingCodeManager pairing, Random? random}); Future<HandshakeAnswer?> answer({required String mobileId, required PayloadKind kind, required Uint8List message}); }`
  - Rules: undecryptable/malformed HS1 → `null` (nothing can be answered); `proto != 1` → `proto_unsupported`; IK → `ok` only if the trust list has **this relay peer id** with **this static key**, else `untrusted`; IKpsk2 with an active code → `ok` (code remembered in `pairingSecret`), without one → random PSK + `pairing_invalid` (the phone cannot even decrypt HS2).

- [ ] **Step 1: Write the failing test**

`packages/shellx_agent/test/service/handshake_responder_test.dart`:

```dart
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_agent/src/service/handshake_responder.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

const agentId = 'a0000000-0000-4000-8000-000000000001';
const phoneId = 'b0000000-0000-4000-8000-000000000002';
const tabletId = 'b0000000-0000-4000-8000-000000000003';

void main() {
  late NoiseKeyPair agentKey;
  late NoiseKeyPair phoneKey;
  late NoiseKeyPair otherKey;
  late TrustedStore trusted;
  late PairingCodeManager pairing;

  setUpAll(() async {
    agentKey = await NoiseKeyPair.generate();
    phoneKey = await NoiseKeyPair.generate();
    otherKey = await NoiseKeyPair.generate();
  });

  setUp(() async {
    trusted = TrustedStore(InMemoryKeyValueStore());
    pairing = PairingCodeManager();
    await trusted.add(TrustedDevice(
        mobileId: phoneId,
        publicKey: phoneKey.publicKey,
        name: 'Pixel',
        pairedAt: DateTime.utc(2026)));
  });

  HandshakeResponder responder({Random? random}) => HandshakeResponder(
        deviceId: agentId,
        identity: agentKey,
        appVersion: '1.0.0',
        trusted: trusted,
        pairing: pairing,
        random: random,
      );

  /// Runs HS1 from a phone. [claimedId] is the relay peer id the agent sees;
  /// [prologueId] is the id the phone put in its prologue.
  Future<(HandshakeAnswer?, NoiseHandshake)> hello({
    HandshakeResponder? using,
    NoisePattern pattern = NoisePattern.ik,
    Uint8List? psk,
    NoiseKeyPair? key,
    String claimedId = phoneId,
    String? prologueId,
    Uint8List? agentPublicKey,
    int proto = kAppProtocolVersion,
  }) async {
    final initiator = NoiseHandshake.initiator(
      pattern: pattern,
      localStatic: key ?? phoneKey,
      remoteStatic: agentPublicKey ?? agentKey.publicKey,
      prologue: buildPrologue(
          agentDeviceId: agentId, mobileDeviceId: prologueId ?? claimedId),
      psk: psk,
    );
    final message = await initiator.writeMessage(Hs1Payload(
      proto: proto,
      app: '1.0.0',
      name: 'Pixel',
      platform: DevicePlatform.android,
    ).encode());
    final answer = await (using ?? responder()).answer(
      mobileId: claimedId,
      kind: pattern == NoisePattern.ik ? PayloadKind.hs1Ik : PayloadKind.hs1IkPsk2,
      message: message,
    );
    return (answer, initiator);
  }

  Future<Hs2Payload> readReply(
      NoiseHandshake initiator, HandshakeAnswer answer) async {
    final payload = ChannelPayload.decode(answer.reply);
    expect(payload.kind, PayloadKind.hs2);
    return Hs2Payload.decode(await initiator.readMessage(payload.noiseMessage));
  }

  test('a trusted phone gets ok and a working transport', () async {
    final (answer, initiator) = await hello();
    expect(answer!.status, HandshakeStatus.ok);
    expect(answer.hello.name, 'Pixel');
    expect(answer.remoteStatic, phoneKey.publicKey);
    expect(answer.pairingSecret, isNull);
    final reply = await readReply(initiator, answer);
    expect((reply.proto, reply.app, reply.status),
        (1, '1.0.0', HandshakeStatus.ok));

    final phoneSide = SecureChannel(initiator.split());
    final agentSide = SecureChannel(answer.transport!);
    final sealed = ChannelPayload.decode(await phoneSide.seal([const SessionList()]));
    expect((await agentSide.open(sealed.noiseMessage)).single, isA<SessionList>());
  });

  test('an unknown key is untrusted and gets no transport', () async {
    final (answer, initiator) = await hello(key: otherKey);
    expect(answer!.status, HandshakeStatus.untrusted);
    expect(answer.transport, isNull);
    expect((await readReply(initiator, answer)).status, HandshakeStatus.untrusted);
  });

  test('trust binds the relay peer id: a trusted key under another id is '
      'untrusted', () async {
    final (answer, _) = await hello(claimedId: tabletId);
    expect(answer!.status, HandshakeStatus.untrusted);
  });

  test('trust binds the key: the trusted id with another key is untrusted',
      () async {
    final (answer, _) = await hello(key: otherKey, claimedId: phoneId);
    expect(answer!.status, HandshakeStatus.untrusted);
  });

  test('another protocol version gets proto_unsupported', () async {
    final (answer, initiator) = await hello(proto: 2);
    expect(answer!.status, HandshakeStatus.protoUnsupported);
    expect(answer.transport, isNull);
    expect((await readReply(initiator, answer)).status,
        HandshakeStatus.protoUnsupported);
  });

  test('a relay-swapped device id breaks the prologue: no answer', () async {
    final (answer, _) = await hello(claimedId: tabletId, prologueId: phoneId);
    expect(answer, isNull);
  });

  test('HS1 addressed to another agent key cannot be answered', () async {
    final (answer, _) = await hello(agentPublicKey: otherKey.publicKey);
    expect(answer, isNull);
  });

  test('garbage and non-HS1 kinds are ignored', () async {
    expect(
        await responder().answer(
            mobileId: phoneId,
            kind: PayloadKind.hs1Ik,
            message: Uint8List.fromList([1, 2, 3])),
        isNull);
    expect(
        await responder().answer(
            mobileId: phoneId, kind: PayloadKind.transport, message: Uint8List(64)),
        isNull);
  });

  test('pairing with the active code is accepted and remembers the code',
      () async {
    final secret = pairing.create().secret;
    final (answer, initiator) = await hello(
        pattern: NoisePattern.ikPsk2, psk: secret, key: otherKey, claimedId: tabletId);
    expect(answer!.status, HandshakeStatus.ok);
    expect(answer.pairingSecret, secret);
    expect(answer.remoteStatic, otherKey.publicKey);
    expect((await readReply(initiator, answer)).status, HandshakeStatus.ok);
  });

  test('pairing with a wrong code: the phone cannot decrypt HS2', () async {
    pairing.create();
    final wrong = Uint8List.fromList(List.filled(32, 9));
    final (answer, initiator) = await hello(
        pattern: NoisePattern.ikPsk2, psk: wrong, key: otherKey, claimedId: tabletId);
    expect(answer!.status, HandshakeStatus.ok);
    await expectLater(
        initiator.readMessage(ChannelPayload.decode(answer.reply).noiseMessage),
        throwsA(isA<NoiseException>()));
  });

  test('pairing without an active code uses a random PSK and pairing_invalid',
      () async {
    // HandshakeResponder draws the random PSK from the injected Random.
    final expectedPsk = Uint8List.fromList(_bytesFrom(Random(99), 32));
    final (answer, initiator) = await hello(
      using: responder(random: Random(99)),
      pattern: NoisePattern.ikPsk2,
      psk: expectedPsk,
      key: otherKey,
      claimedId: tabletId,
    );
    expect(answer!.status, HandshakeStatus.pairingInvalid);
    expect(answer.transport, isNull);
    expect(answer.pairingSecret, isNull);
    expect((await readReply(initiator, answer)).status,
        HandshakeStatus.pairingInvalid);
  });
}

List<int> _bytesFrom(Random random, int length) =>
    List.generate(length, (_) => random.nextInt(256));
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/shellx_agent && dart test test/service/handshake_responder_test.dart`
Expected: FAIL — `Error when reading 'lib/src/service/handshake_responder.dart'`.

- [ ] **Step 3: Implement**

`packages/shellx_agent/lib/src/service/handshake_responder.dart`:

```dart
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import '../pairing/pairing_code_manager.dart';
import '../trust/trusted_store.dart';

/// Outcome of answering one HS1.
final class HandshakeAnswer {
  const HandshakeAnswer({
    required this.reply,
    required this.status,
    required this.hello,
    required this.remoteStatic,
    required this.transport,
    required this.pairingSecret,
  });

  /// Encoded `ChannelPayload(hs2, …)` — the DATA payload to send back.
  final Uint8List reply;
  final HandshakeStatus status;
  final Hs1Payload hello;
  final Uint8List remoteStatic;

  /// Transport keys; non-null only when [status] is ok.
  final NoiseTransport? transport;

  /// PSK of an accepted pairing handshake; null otherwise.
  final Uint8List? pairingSecret;
}

/// Noise responder for HS1_IK / HS1_IKPSK2 (spec §5.3, §5.4, §6.3).
final class HandshakeResponder {
  HandshakeResponder({
    required String deviceId,
    required NoiseKeyPair identity,
    required String appVersion,
    required TrustedStore trusted,
    required PairingCodeManager pairing,
    Random? random,
  })  : _deviceId = deviceId,
        _identity = identity,
        _appVersion = appVersion,
        _trusted = trusted,
        _pairing = pairing,
        _random = random ?? Random.secure();

  final String _deviceId;
  final NoiseKeyPair _identity;
  final String _appVersion;
  final TrustedStore _trusted;
  final PairingCodeManager _pairing;
  final Random _random;

  /// Returns null when message 1 cannot be decrypted or decoded: nothing
  /// can be answered (wrong agent key, prologue mismatch, garbage).
  Future<HandshakeAnswer?> answer({
    required String mobileId,
    required PayloadKind kind,
    required Uint8List message,
  }) async {
    final NoisePattern pattern;
    Uint8List? psk;
    Uint8List? activeSecret;
    switch (kind) {
      case PayloadKind.hs1Ik:
        pattern = NoisePattern.ik;
      case PayloadKind.hs1IkPsk2:
        pattern = NoisePattern.ikPsk2;
        activeSecret = _pairing.activeSecret;
        // No active code: answer with a random PSK so the phone cannot even
        // decrypt HS2, and never accept the pairing.
        psk = activeSecret ?? _randomBytes(32);
      case PayloadKind.hs2 || PayloadKind.transport:
        return null;
    }
    final handshake = NoiseHandshake.responder(
      pattern: pattern,
      localStatic: _identity,
      prologue: buildPrologue(agentDeviceId: _deviceId, mobileDeviceId: mobileId),
      psk: psk,
    );
    final Hs1Payload hello;
    try {
      hello = Hs1Payload.decode(await handshake.readMessage(message));
    } catch (_) {
      return null; // Undecryptable or malformed HS1: nothing to answer.
    }
    final remoteStatic = handshake.remoteStatic!;
    final HandshakeStatus status;
    if (hello.proto != kAppProtocolVersion) {
      status = HandshakeStatus.protoUnsupported;
    } else if (pattern == NoisePattern.ikPsk2) {
      status = activeSecret == null
          ? HandshakeStatus.pairingInvalid
          : HandshakeStatus.ok;
    } else {
      // Trust binds the relay peer id AND the static key proven by Noise.
      final device = await _trusted.find(mobileId);
      status = device != null && constantTimeEquals(device.publicKey, remoteStatic)
          ? HandshakeStatus.ok
          : HandshakeStatus.untrusted;
    }
    final reply = await handshake.writeMessage(Hs2Payload(
      proto: kAppProtocolVersion,
      app: _appVersion,
      status: status,
    ).encode());
    final ok = status == HandshakeStatus.ok;
    return HandshakeAnswer(
      reply: ChannelPayload(PayloadKind.hs2, reply).encode(),
      status: status,
      hello: hello,
      remoteStatic: remoteStatic,
      transport: ok ? handshake.split() : null,
      pairingSecret: ok && pattern == NoisePattern.ikPsk2 ? psk : null,
    );
  }

  Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/shellx_agent && dart test test/service/handshake_responder_test.dart`
Expected: `+11: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_agent/lib/src/service/handshake_responder.dart packages/shellx_agent/test/service/handshake_responder_test.dart
git commit -m "feat(agent): add Noise handshake responder with trust checks"
```

### Task 9: `AgentService` — channels, routing, pairing completion, revoke, events

**Files:**
- Create: `packages/shellx_agent/lib/src/service/agent_events.dart`, `packages/shellx_agent/lib/src/service/agent_service.dart`
- Modify: `packages/shellx_agent/lib/shellx_agent.dart`
- Create (test support): `packages/shellx_agent/test/support/test_mobile.dart`
- Test: `packages/shellx_agent/test/service/agent_service_test.dart`

**Interfaces:**
- Consumes: `SessionManager`, `OutboundMessage`, `SessionOpenedEvent` (Task 4); `TrustedStore`, `TrustedDevice`, `PairingCodeManager` (Task 5); `FakeRelay`, `drive`, `settle` (Task 6); `AgentChannel` (Task 7); `HandshakeResponder` (Task 8); core `RelayConnection`, `RelayConnectionState`, frames, `ShellxApi`, `ApiException`, `PairingUri`, `SecureChannel`.
- Produces (overview §5.6, plus `AgentRevoked`):
  - `sealed class AgentEvent`; `MobilePaired(TrustedDevice device)`; `SessionOpenedByMobile({required String mobileName, required int sessionId})`; `ActiveChannelsChanged(int count)`; **`AgentRevoked()`** (relay state became `revoked`: 4002 or HTTP 401).
  - `final class AgentService { AgentService({required RelayConnection relay, required ShellxApi api, required String deviceId, required NoiseKeyPair identity, required TrustedStore trusted, required SessionManager sessions, required PairingCodeManager pairing, required String appVersion, Duration flushInterval = const Duration(milliseconds: 16)}); Future<void> start(); Future<void> stop(); Stream<AgentEvent> get events; int get activeChannelCount; PairingUri startPairing(); void cancelPairing(); Future<void> revoke(String mobileId); }`
  - `start()` subscribes and calls `relay.start()`; `stop()` drops every channel and calls `relay.stop()` — it does **not** close sessions (the app calls `sessions.closeAll()` when turning remote access off or logging out).
  - Frame handling is serialized. An accepted HS1 replaces that phone's previous channel (its sessions become unattached); a rejected HS1 leaves the existing channel alone. A pairing channel accepts exactly one message: `pair.confirm` while the code used in the handshake is still active → trust + invalidate + `MobilePaired` + `POST /v1/pairings` (API errors ignored); the pairing channel is then closed. Any decrypt/decode error, PRESENCE offline, `ERROR peer_offline` for the channel, or the relay leaving `connected` drops channels (`sessions.mobileDisconnected`). `EVENT pairing_removed` for this agent removes trust and drops the channel.
  - Test support `TestMobile` (`start()`, `handshake({agentId, agentKey, pattern, psk, proto, name}) → HandshakeResult{channelId, status, channel, decryptFailed}`), `MobileChannel` (`send`, `sendRaw`, `batches`, `received`, `messagesOf<T>()`).

- [ ] **Step 1: Write the test support**

`packages/shellx_agent/test/support/test_mobile.dart`:

```dart
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import 'fake_relay.dart';

/// Result of [TestMobile.handshake]. [status] is null when no HS2 arrived
/// within 5 s; [decryptFailed] is true when HS2 could not be decrypted.
final class HandshakeResult {
  const HandshakeResult({
    required this.channelId,
    this.status,
    this.channel,
    this.decryptFailed = false,
  });
  final ChannelId channelId;
  final HandshakeStatus? status;
  final MobileChannel? channel;
  final bool decryptFailed;
}

/// A scripted phone that speaks the channel protocol directly (Noise
/// initiator) so AgentService can be tested as a black box.
final class TestMobile {
  TestMobile({
    required FakeRelay relay,
    required this.device,
    required this.identity,
  }) : connection = RelayConnection(
          wsUri: relay.wsUri,
          token: () => device.token,
          connector: relay.connector,
          backoff: Backoff(random: Random(7)),
        );

  final FakeDevice device;
  final NoiseKeyPair identity;
  final RelayConnection connection;
  final _pendingHs2 = <ChannelId, Completer<Uint8List?>>{};
  final channels = <ChannelId, MobileChannel>{};
  final errors = <ErrorFrame>[];

  void start() {
    connection.frames.listen(_onFrame);
    connection.start();
  }

  void _onFrame(RelayFrame frame) {
    switch (frame) {
      case DataFrame(:final channel, :final payload):
        final decoded = ChannelPayload.decode(payload);
        if (decoded.kind == PayloadKind.hs2) {
          final pending = _pendingHs2.remove(channel);
          if (pending != null && !pending.isCompleted) {
            pending.complete(decoded.noiseMessage);
          }
        } else if (decoded.kind == PayloadKind.transport) {
          channels[channel]?._receive(decoded.noiseMessage);
        }
      case ErrorFrame():
        errors.add(frame);
      case PresenceFrame() || EventFrame():
        break;
    }
  }

  Future<HandshakeResult> handshake({
    required String agentId,
    required Uint8List agentKey,
    NoisePattern pattern = NoisePattern.ik,
    Uint8List? psk,
    int proto = kAppProtocolVersion,
    String name = 'Test Phone',
  }) async {
    final handshake = NoiseHandshake.initiator(
      pattern: pattern,
      localStatic: identity,
      remoteStatic: agentKey,
      prologue:
          buildPrologue(agentDeviceId: agentId, mobileDeviceId: device.id),
      psk: psk,
    );
    final hello = await handshake.writeMessage(Hs1Payload(
      proto: proto,
      app: '1.0.0',
      name: name,
      platform: DevicePlatform.ios,
    ).encode());
    final channelId = ChannelId.random();
    final reply = Completer<Uint8List?>();
    _pendingHs2[channelId] = reply;
    connection.send(DataFrame(
      peer: agentId,
      channel: channelId,
      payload: ChannelPayload(
        pattern == NoisePattern.ik ? PayloadKind.hs1Ik : PayloadKind.hs1IkPsk2,
        hello,
      ).encode(),
    ));
    final message = await reply.future
        .timeout(const Duration(seconds: 5), onTimeout: () => null);
    _pendingHs2.remove(channelId);
    if (message == null) return HandshakeResult(channelId: channelId);
    final Hs2Payload answer;
    try {
      answer = Hs2Payload.decode(await handshake.readMessage(message));
    } on NoiseException {
      return HandshakeResult(channelId: channelId, decryptFailed: true);
    }
    MobileChannel? channel;
    if (answer.status == HandshakeStatus.ok) {
      channel = MobileChannel._(
          this, agentId, channelId, SecureChannel(handshake.split()));
      channels[channelId] = channel;
    }
    return HandshakeResult(
        channelId: channelId, status: answer.status, channel: channel);
  }
}

/// The phone end of an established channel.
final class MobileChannel {
  MobileChannel._(this._mobile, this.agentId, this.channelId, this._secure);

  final TestMobile _mobile;
  final String agentId;
  final ChannelId channelId;
  final SecureChannel _secure;
  Future<void> _inbox = Future.value();
  Future<void> _outbox = Future.value();

  /// Every decrypted TRANSPORT payload, in arrival order.
  final batches = <List<AppMessage>>[];

  List<AppMessage> get received => [for (final batch in batches) ...batch];

  List<T> messagesOf<T extends AppMessage>() =>
      received.whereType<T>().toList();

  Future<void> send(List<AppMessage> messages) {
    final result = _outbox.then((_) async {
      final payload = await _secure.seal(messages);
      _mobile.connection
          .send(DataFrame(peer: agentId, channel: channelId, payload: payload));
    });
    _outbox = result;
    return result;
  }

  /// Sends [noiseMessage] as a TRANSPORT payload without encrypting it.
  void sendRaw(Uint8List noiseMessage) {
    _mobile.connection.send(DataFrame(
      peer: agentId,
      channel: channelId,
      payload: ChannelPayload(PayloadKind.transport, noiseMessage).encode(),
    ));
  }

  void _receive(Uint8List noiseMessage) {
    _inbox = _inbox.then((_) async {
      batches.add(await _secure.open(noiseMessage));
    }).catchError((Object _) {});
  }
}
```

- [ ] **Step 2: Write the failing test**

`packages/shellx_agent/test/service/agent_service_test.dart`:

```dart
import 'dart:math';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/drive.dart';
import '../support/fake_pty.dart';
import '../support/fake_relay.dart';
import '../support/test_mobile.dart';

const userId = 'user-1';
const agentId = 'a0000000-0000-4000-8000-000000000001';
const phoneId = 'b0000000-0000-4000-8000-000000000002';
const tabletId = 'b0000000-0000-4000-8000-000000000003';
const spareId = 'b0000000-0000-4000-8000-000000000004';

late NoiseKeyPair agentKey;
late NoiseKeyPair phoneKey;
late NoiseKeyPair tabletKey;
late NoiseKeyPair spareKey;

/// A real AgentService on a FakeRelay with three scripted phones. Only the
/// phone is trusted initially.
final class AgentRig {
  AgentRig(this.async) {
    agentDevice =
        relay.addDevice(id: agentId, userId: userId, kind: DeviceKind.agent);
    trusted = TrustedStore(InMemoryKeyValueStore());
    drive(
        async,
        trusted.add(TrustedDevice(
            mobileId: phoneId,
            publicKey: phoneKey.publicKey,
            name: 'Test Phone',
            pairedAt: DateTime.utc(2026))));
    pairing = PairingCodeManager(now: () => now);
    sessions = SessionManager(
      ptyFactory: ptys,
      shellResolver: const FixedShellResolver(),
      homeDirectory: '/Users/test',
      baseEnvironment: const {},
    );
    service = AgentService(
      relay: RelayConnection(
        wsUri: relay.wsUri,
        token: () => agentDevice.token,
        connector: relay.connector,
        backoff: Backoff(random: Random(11)),
      ),
      api: ShellxApi(baseUri: relay.baseUri, httpClient: relay.httpClient)
        ..token = agentDevice.token,
      deviceId: agentId,
      identity: agentKey,
      trusted: trusted,
      sessions: sessions,
      pairing: pairing,
      appVersion: '1.0.0',
    );
    service.events.listen(events.add);
    drive(async, service.start());
    phone = _mobile(phoneId, phoneKey);
    tablet = _mobile(tabletId, tabletKey);
    spare = _mobile(spareId, spareKey);
    settle(async);
  }

  final FakeAsync async;
  final relay = FakeRelay();
  final ptys = FakePtyFactory();
  final events = <AgentEvent>[];
  DateTime now = DateTime.utc(2026, 9, 25, 12);
  late final FakeDevice agentDevice;
  late final TrustedStore trusted;
  late final PairingCodeManager pairing;
  late final SessionManager sessions;
  late final AgentService service;
  late final TestMobile phone;
  late final TestMobile tablet;
  late final TestMobile spare;

  TestMobile _mobile(String id, NoiseKeyPair key) => TestMobile(
        relay: relay,
        device: relay.addDevice(id: id, userId: userId, kind: DeviceKind.mobile),
        identity: key,
      )..start();

  HandshakeResult handshake(TestMobile mobile,
          {NoisePattern pattern = NoisePattern.ik,
          Uint8List? psk,
          String name = 'Test Phone'}) =>
      drive(
          async,
          mobile.handshake(
            agentId: agentId,
            agentKey: agentKey.publicKey,
            pattern: pattern,
            psk: psk,
            name: name,
          ));

  void send(MobileChannel channel, List<AppMessage> messages) {
    drive(async, channel.send(messages));
    settle(async);
  }

  TrustedDevice? findTrusted(String id) => drive(async, trusted.find(id));
}

void main() {
  setUpAll(() async {
    agentKey = await NoiseKeyPair.generate();
    phoneKey = await NoiseKeyPair.generate();
    tabletKey = await NoiseKeyPair.generate();
    spareKey = await NoiseKeyPair.generate();
  });

  test('a trusted phone gets ok and exactly one channel', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final result = rig.handshake(rig.phone);
      expect(result.status, HandshakeStatus.ok);
      expect(rig.service.activeChannelCount, 1);
      expect(rig.events.whereType<ActiveChannelsChanged>().last.count, 1);
    });
  });

  test('an untrusted phone gets untrusted and no channel', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      expect(rig.handshake(rig.tablet).status, HandshakeStatus.untrusted);
      expect(rig.service.activeChannelCount, 0);
    });
  });

  test('app messages reach the session manager and replies come back', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final channel = rig.handshake(rig.phone).channel!;
      rig.send(channel, [const SessionOpen(cols: 80, rows: 24)]);
      rig.ptys.ptys.single.emit('hello');
      settle(async);

      final opened = channel.messagesOf<SessionOpened>().single;
      expect(opened.index, 1);
      expect(String.fromCharCodes(channel.messagesOf<OutputMessage>().single.data),
          'hello');
      final notice = rig.events.whereType<SessionOpenedByMobile>().single;
      expect((notice.mobileName, notice.sessionId), ('Test Phone', opened.id));
    });
  });

  test('output is batched per channel: 16 ms timer, immediate at 16 KiB', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final channel = rig.handshake(rig.phone).channel!;
      rig.send(channel, [const SessionOpen(cols: 80, rows: 24)]);
      final pty = rig.ptys.ptys.single;
      final before = channel.batches.length;

      pty.emit('a');
      async.elapse(const Duration(milliseconds: 5));
      pty.emit('b');
      async.elapse(const Duration(milliseconds: 20));
      expect(channel.batches.length, before + 1);
      expect(channel.batches.last.whereType<OutputMessage>(), hasLength(2));

      pty.emitBytes(List.filled(20 * 1024, 0x7a));
      async.flushMicrotasks();
      expect(channel.batches.length, before + 2);
      expect([
        for (final o in channel.batches.last.whereType<OutputMessage>())
          o.data.length,
      ], [16 * 1024, 4 * 1024]);
      async.elapse(const Duration(milliseconds: 16));
      expect(channel.batches.length, before + 2);
    });
  });

  test('a new HS1 from the same phone replaces its channel and detaches '
      'its sessions', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final first = rig.handshake(rig.phone).channel!;
      rig.send(first, [const SessionOpen(cols: 80, rows: 24)]);
      final second = rig.handshake(rig.phone).channel!;
      expect(rig.service.activeChannelCount, 1);
      expect(rig.sessions.sessions.single.attachedMobileId, isNull);

      final repliesOnFirst = first.received.length;
      rig.send(first, [const SessionList()]);
      expect(first.received.length, repliesOnFirst);
      rig.send(second, [const SessionList()]);
      expect(second.messagesOf<SessionListResult>(), hasLength(1));
    });
  });

  test('any decrypt error drops the channel', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final channel = rig.handshake(rig.phone).channel!;
      rig.send(channel, [const SessionOpen(cols: 80, rows: 24)]);
      channel.sendRaw(Uint8List.fromList(List.filled(40, 7)));
      settle(async);
      expect(rig.service.activeChannelCount, 0);
      expect(rig.sessions.sessions.single.attachedMobileId, isNull);
    });
  });

  test('PRESENCE offline drops the channel but the session keeps running', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final channel = rig.handshake(rig.phone).channel!;
      rig.send(channel, [const SessionOpen(cols: 80, rows: 24)]);
      rig.relay.setReachable(phoneId, false);
      rig.relay.dropConnection(phoneId);
      settle(async);
      expect(rig.service.activeChannelCount, 0);
      expect(rig.sessions.sessions.single.attachedMobileId, isNull);
      expect(rig.ptys.ptys.single.killed, isFalse);
    });
  });

  test('losing the agent relay connection drops every channel', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      rig.handshake(rig.phone);
      rig.relay.dropConnection(agentId);
      async.flushMicrotasks();
      expect(rig.service.activeChannelCount, 0);
      async.elapse(const Duration(seconds: 2));
      expect(rig.relay.isOnline(agentId), isTrue);
      expect(rig.handshake(rig.phone).status, HandshakeStatus.ok);
    });
  });

  test('a 4002 close surfaces AgentRevoked; the relay stays down', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      rig.handshake(rig.phone);
      rig.relay.dropConnection(agentId, code: RelayCloseCode.revoked);
      settle(async);
      expect(rig.events.whereType<AgentRevoked>(), hasLength(1));
      expect(rig.service.activeChannelCount, 0);
      async.elapse(const Duration(seconds: 5));
      expect(rig.relay.isOnline(agentId), isFalse);
    });
  });

  test('pairing: pair.confirm trusts the phone, burns the code and records '
      'the pairing', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final uri = rig.service.startPairing();
      expect(uri.agentDeviceId, agentId);
      expect(uri.agentPublicKey, agentKey.publicKey);
      expect(uri.secret, hasLength(32));

      final result = rig.handshake(rig.tablet,
          pattern: NoisePattern.ikPsk2, psk: uri.secret, name: 'iPad');
      expect(result.status, HandshakeStatus.ok);
      expect(rig.findTrusted(tabletId), isNull);
      rig.send(result.channel!, [const PairConfirm()]);

      final paired = rig.events.whereType<MobilePaired>().single.device;
      expect((paired.mobileId, paired.name), (tabletId, 'iPad'));
      expect(rig.findTrusted(tabletId)!.publicKey, tabletKey.publicKey);
      expect(rig.pairing.activeSecret, isNull);
      expect(rig.relay.pairings, {(agentId, tabletId)});
      expect(rig.service.activeChannelCount, 0);
      expect(rig.handshake(rig.tablet).status, HandshakeStatus.ok);
    });
  });

  test('a pairing channel accepts nothing but pair.confirm', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final uri = rig.service.startPairing();
      final channel = rig
          .handshake(rig.tablet, pattern: NoisePattern.ikPsk2, psk: uri.secret)
          .channel!;
      rig.send(channel, [const SessionList(), const PairConfirm()]);
      expect(channel.received, isEmpty);
      expect(rig.findTrusted(tabletId), isNull);
      expect(rig.service.activeChannelCount, 0);
    });
  });

  test('a code works once: a second confirmation with it is rejected', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final uri = rig.service.startPairing();
      final a = rig.handshake(rig.tablet, pattern: NoisePattern.ikPsk2, psk: uri.secret);
      final b = rig.handshake(rig.spare, pattern: NoisePattern.ikPsk2, psk: uri.secret);
      rig.send(a.channel!, [const PairConfirm()]);
      rig.send(b.channel!, [const PairConfirm()]);
      expect(rig.findTrusted(tabletId), isNotNull);
      expect(rig.findTrusted(spareId), isNull);
    });
  });

  test('an expired or cancelled code cannot pair (HS2 is undecryptable)', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final expired = rig.service.startPairing();
      rig.now = rig.now.add(const Duration(minutes: 6));
      final late = rig.handshake(rig.tablet,
          pattern: NoisePattern.ikPsk2, psk: expired.secret);
      expect(late.decryptFailed, isTrue);

      final cancelled = rig.service.startPairing();
      rig.service.cancelPairing();
      final result = rig.handshake(rig.tablet,
          pattern: NoisePattern.ikPsk2, psk: cancelled.secret);
      expect(result.decryptFailed, isTrue);
      expect(rig.findTrusted(tabletId), isNull);
    });
  });

  test('revoke removes trust, kills the phone’s sessions, drops its channel '
      'and deletes the pairing record', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      rig.relay.pairings.add((agentId, phoneId));
      final channel = rig.handshake(rig.phone).channel!;
      rig.send(channel, [const SessionOpen(cols: 80, rows: 24)]);

      drive(async, rig.service.revoke(phoneId));
      settle(async);

      expect(rig.findTrusted(phoneId), isNull);
      expect(rig.ptys.ptys.single.killed, isTrue);
      expect(rig.service.activeChannelCount, 0);
      expect(rig.relay.requests, contains('DELETE /v1/pairings/$agentId/$phoneId'));
      expect(rig.relay.pairings, isEmpty);
      expect(rig.handshake(rig.phone).status, HandshakeStatus.untrusted);
    });
  });

  test('EVENT pairing_removed for this agent removes trust', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      rig.handshake(rig.phone);
      rig.relay.sendEvent(agentId, {
        'event': 'pairing_removed',
        'agent_id': 'a0000000-0000-4000-8000-00000000ffff',
        'mobile_id': phoneId,
      });
      settle(async);
      expect(rig.findTrusted(phoneId), isNotNull);

      rig.relay.sendEvent(agentId, {
        'event': 'pairing_removed',
        'agent_id': agentId,
        'mobile_id': phoneId,
      });
      settle(async);
      expect(rig.findTrusted(phoneId), isNull);
      expect(rig.service.activeChannelCount, 0);
    });
  });

  test('stop drops channels and disconnects without closing sessions', () {
    fakeAsync((async) {
      final rig = AgentRig(async);
      final channel = rig.handshake(rig.phone).channel!;
      rig.send(channel, [const SessionOpen(cols: 80, rows: 24)]);
      rig.service.stop();
      settle(async);
      expect(rig.service.activeChannelCount, 0);
      expect(rig.relay.isOnline(agentId), isFalse);
      expect(rig.sessions.sessions, hasLength(1));
    });
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `cd packages/shellx_agent && dart test test/service/agent_service_test.dart`
Expected: FAIL — compilation errors `Type 'AgentService' not found`, `Type 'AgentEvent' not found`.

- [ ] **Step 4: Implement**

`packages/shellx_agent/lib/src/service/agent_events.dart`:

```dart
import '../trust/trusted_store.dart';

/// Notifications for the desktop UI.
sealed class AgentEvent {
  const AgentEvent();
}

/// A phone completed pairing (show "Paired with `name`", close the QR window).
final class MobilePaired extends AgentEvent {
  const MobilePaired(this.device);
  final TrustedDevice device;
}

/// A phone opened a new terminal session (system notification).
final class SessionOpenedByMobile extends AgentEvent {
  const SessionOpenedByMobile({required this.mobileName, required this.sessionId});
  final String mobileName;
  final int sessionId;
}

/// The number of open encrypted channels changed (tray icon state).
final class ActiveChannelsChanged extends AgentEvent {
  const ActiveChannelsChanged(this.count);
  final int count;
}

/// The relay closed the agent's connection with 4002 (token revoked: account
/// deleted, or password changed on another machine). The relay connection
/// does not reconnect; the desktop app decides what to clear (spec §5.2).
final class AgentRevoked extends AgentEvent {
  const AgentRevoked();
}
```

`packages/shellx_agent/lib/src/service/agent_service.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import '../pairing/pairing_code_manager.dart';
import '../session/session_manager.dart';
import '../trust/trusted_store.dart';
import 'agent_channel.dart';
import 'agent_events.dart';
import 'handshake_responder.dart';

/// The agent side of the relay protocol: answers handshakes, keeps at most
/// one encrypted channel per phone, routes app messages to [SessionManager]
/// and completes pairing.
///
/// [start] subscribes and calls `relay.start()`. [stop] drops every channel
/// and calls `relay.stop()`; it does not close sessions (call
/// `SessionManager.closeAll()` for that).
final class AgentService {
  AgentService({
    required RelayConnection relay,
    required ShellxApi api,
    required String deviceId,
    required NoiseKeyPair identity,
    required TrustedStore trusted,
    required SessionManager sessions,
    required PairingCodeManager pairing,
    required String appVersion,
    Duration flushInterval = const Duration(milliseconds: 16),
  })  : _relay = relay,
        _api = api,
        _deviceId = deviceId,
        _identity = identity,
        _trusted = trusted,
        _sessions = sessions,
        _pairing = pairing,
        _flushInterval = flushInterval,
        _responder = HandshakeResponder(
          deviceId: deviceId,
          identity: identity,
          appVersion: appVersion,
          trusted: trusted,
          pairing: pairing,
        );

  final RelayConnection _relay;
  final ShellxApi _api;
  final String _deviceId;
  final NoiseKeyPair _identity;
  final TrustedStore _trusted;
  final SessionManager _sessions;
  final PairingCodeManager _pairing;
  final Duration _flushInterval;
  final HandshakeResponder _responder;

  final _events = StreamController<AgentEvent>.broadcast();
  final _channels = <String, AgentChannel>{};
  final _subscriptions = <StreamSubscription<Object?>>[];
  Future<void> _inbox = Future.value();
  bool _running = false;

  Stream<AgentEvent> get events => _events.stream;

  int get activeChannelCount => _channels.length;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _subscriptions
      ..add(_relay.frames.listen((frame) => _enqueue(() => _onFrame(frame))))
      ..add(_relay.states.listen((state) => _enqueue(() async {
            if (state == RelayConnectionState.connected) return;
            _dropAllChannels();
            if (state == RelayConnectionState.revoked) {
              _events.add(const AgentRevoked());
            }
          })))
      ..add(_sessions.outbound
          .listen((out) => _channels[out.mobileId]?.enqueue(out.message)))
      ..add(_sessions.opened.listen((event) => _events.add(
          SessionOpenedByMobile(
              mobileName: _channels[event.mobileId]?.name ?? event.mobileId,
              sessionId: event.sessionId))));
    _relay.start();
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    for (final subscription in _subscriptions) {
      // Not awaited: cancel() may return a root-zone future.
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _dropAllChannels();
    await _relay.stop();
  }

  /// Creates a single-use pairing code and the QR URI that carries it.
  PairingUri startPairing() {
    final offer = _pairing.create();
    return PairingUri(
      agentDeviceId: _deviceId,
      agentPublicKey: _identity.publicKey,
      secret: offer.secret,
    );
  }

  /// The QR window was closed: the code stops working immediately.
  void cancelPairing() => _pairing.invalidate();

  /// Tray → "Paired devices" → Revoke (spec §5.5).
  Future<void> revoke(String mobileId) async {
    await _trusted.remove(mobileId);
    _sessions.closeSessionsAttachedTo(mobileId);
    _dropChannel(mobileId);
    try {
      await _api.deletePairing(_deviceId, mobileId);
    } on ApiException {
      // The server record is display-only; local trust is already gone.
    }
  }

  void _enqueue(Future<void> Function() task) {
    _inbox = _inbox.then((_) {
      if (!_running) return null;
      return task();
    }).catchError((Object _) {});
  }

  Future<void> _onFrame(RelayFrame frame) async {
    switch (frame) {
      case DataFrame():
        await _onData(frame);
      case PresenceFrame(:final deviceId, :final online):
        if (!online) _dropChannel(deviceId);
      case ErrorFrame(:final code, :final deviceId, :final channel):
        if (code == RelayErrorCode.peerOffline &&
            _channels[deviceId]?.channelId == channel) {
          _dropChannel(deviceId);
        }
      case EventFrame(:final event):
        await _onEvent(event);
    }
  }

  Future<void> _onData(DataFrame frame) async {
    final ChannelPayload payload;
    try {
      payload = ChannelPayload.decode(frame.payload);
    } on FrameFormatException {
      return;
    }
    switch (payload.kind) {
      case PayloadKind.hs1Ik || PayloadKind.hs1IkPsk2:
        await _onHello(frame, payload);
      case PayloadKind.transport:
        await _onTransport(frame, payload.noiseMessage);
      case PayloadKind.hs2:
        break; // The agent is always the responder.
    }
  }

  Future<void> _onHello(DataFrame frame, ChannelPayload payload) async {
    final mobileId = frame.peer;
    final answer = await _responder.answer(
        mobileId: mobileId, kind: payload.kind, message: payload.noiseMessage);
    if (answer == null || !_running) return;
    _relay.send(DataFrame(
        peer: mobileId, channel: frame.channel, payload: answer.reply));
    final transport = answer.transport;
    if (transport == null) return; // Status was not ok: no channel.
    // One channel per phone: a new accepted HS1 replaces the old channel.
    final previous = _channels.remove(mobileId);
    if (previous != null) {
      previous.close();
      _sessions.mobileDisconnected(mobileId);
    }
    _channels[mobileId] = AgentChannel(
      mobileId: mobileId,
      channelId: frame.channel,
      name: answer.hello.name,
      remoteStatic: answer.remoteStatic,
      secure: SecureChannel(transport),
      send: _relay.send,
      pairingSecret: answer.pairingSecret,
      flushInterval: _flushInterval,
    );
    _events.add(ActiveChannelsChanged(_channels.length));
  }

  Future<void> _onTransport(DataFrame frame, Uint8List noiseMessage) async {
    final mobileId = frame.peer;
    final channel = _channels[mobileId];
    if (channel == null || channel.channelId != frame.channel) return;
    final List<AppMessage> messages;
    try {
      messages = await channel.open(noiseMessage);
    } catch (_) {
      _dropChannel(mobileId); // Any decrypt/decode error kills the channel.
      return;
    }
    for (final message in messages) {
      if (!identical(_channels[mobileId], channel)) return;
      if (channel.isPairing) {
        await _completePairing(channel, message);
        return;
      }
      if (message is PairConfirm) continue;
      await _sessions.handle(mobileId, message);
    }
  }

  /// Pairing succeeds only on a decrypted `pair.confirm` while the code used
  /// for the handshake is still the active one (spec §5.3 step 5).
  Future<void> _completePairing(AgentChannel channel, AppMessage message) async {
    _dropChannel(channel.mobileId); // A pairing channel carries one message.
    final active = _pairing.activeSecret;
    if (message is! PairConfirm ||
        active == null ||
        !constantTimeEquals(active, channel.pairingSecret!)) {
      return;
    }
    _pairing.invalidate();
    final device = TrustedDevice(
      mobileId: channel.mobileId,
      publicKey: channel.remoteStatic,
      name: channel.name,
      pairedAt: DateTime.now().toUtc(),
    );
    await _trusted.add(device);
    _events.add(MobilePaired(device));
    try {
      await _api.createPairing(channel.mobileId);
    } on ApiException {
      // Display-only record; the pairing is already effective locally.
    }
  }

  Future<void> _onEvent(Map<String, String> event) async {
    if (event['event'] != 'pairing_removed' || event['agent_id'] != _deviceId) {
      return;
    }
    final mobileId = event['mobile_id'];
    if (mobileId == null) return;
    await _trusted.remove(mobileId);
    _dropChannel(mobileId);
  }

  void _dropChannel(String mobileId) {
    final channel = _channels.remove(mobileId);
    if (channel == null) return;
    channel.close();
    _sessions.mobileDisconnected(mobileId);
    _events.add(ActiveChannelsChanged(_channels.length));
  }

  void _dropAllChannels() {
    for (final mobileId in _channels.keys.toList()) {
      _dropChannel(mobileId);
    }
  }
}
```

Replace the whole content of `packages/shellx_agent/lib/shellx_agent.dart` with:

```dart
/// ShellX desktop agent logic: sessions, pairing responder, trust list.
library;

export 'src/pairing/pairing_code_manager.dart';
export 'src/pty/process_pty.dart';
export 'src/pty/pty.dart';
export 'src/pty/session_environment.dart';
export 'src/pty/shell_resolver.dart';
export 'src/service/agent_events.dart';
export 'src/service/agent_service.dart';
export 'src/session/ring_buffer.dart';
export 'src/session/session_manager.dart';
export 'src/trust/trusted_store.dart';
```

- [ ] **Step 5: Run the whole package**

Run: `cd packages/shellx_agent && dart test`
Expected: `+96: All tests passed!` (16 in `agent_service_test.dart`).

Run: `dart analyze packages/shellx_agent` (repo root). Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add packages/shellx_agent/lib packages/shellx_agent/test/support/test_mobile.dart packages/shellx_agent/test/service/agent_service_test.dart
git commit -m "feat(agent): add AgentService"
```

### Task 10: Scaffold `shellx_client`; public types and `PinnedStore`

**Files:**
- Modify: `pubspec.yaml` (root) — add one `workspace:` line
- Create: `packages/shellx_client/pubspec.yaml`, `packages/shellx_client/lib/shellx_client.dart`
- Create: `packages/shellx_client/lib/src/client_types.dart`, `packages/shellx_client/lib/src/pinned_store.dart`
- Test: `packages/shellx_client/test/pinned_store_test.dart`

**Interfaces:**
- Consumes: core `KeyValueStore`, `InMemoryKeyValueStore`, `base64UrlNoPad`, `fromBase64UrlNoPad`, `AppErrorCode`.
- Produces (overview §5.7, plus `MachineConnectionException`):
  - `enum PairingFailure { notInAccount, invalidOrExpired, agentOffline, protocolUnsupported, timeout }`, `final class PairingException { const PairingException(PairingFailure failure); }`
  - `enum MachineConnectionFailure { untrusted, protocolUnsupported, agentOffline, timeout }`, **`final class MachineConnectionException implements Exception { const MachineConnectionException(MachineConnectionFailure failure); }`** — what `MachineClient` throws "according to `MachineFailed`".
  - `sealed class MachineConnectionState`; `MachineIdle`, `MachineConnecting`, `MachineReady`, `MachineFailed(MachineConnectionFailure failure)`.
  - `final class AppErrorException { const AppErrorException(AppErrorCode code, String message); }`
  - `final class PinnedMachine { const PinnedMachine({required String agentId, required Uint8List publicKey, required DateTime pairedAt}); toJson(); static fromJson(json); }` (keys `agent_id`, `public_key`, `paired_at`), `final class PinnedStore { PinnedStore(KeyValueStore store, {required String userId}); /* key 'pinned_machines_<userId>' */ list(); find(agentId); add(machine); remove(agentId); }`

- [ ] **Step 1: Scaffold the package**

In the root `pubspec.yaml`, add this line to the `workspace:` list (keep every existing line):

```yaml
  - packages/shellx_client
```

`packages/shellx_client/pubspec.yaml`:

```yaml
name: shellx_client
description: ShellX mobile client logic (machines, tabs, pairing initiator) in pure Dart.
publish_to: none
resolution: workspace
environment:
  sdk: ^3.11.0
dependencies:
  meta: ^1.16.0
  shellx_core: any
dev_dependencies:
  fake_async: ^1.3.3
  http: ^1.2.0
  shellx_agent: any
  test: ^1.30.0
```

`packages/shellx_client/lib/shellx_client.dart`:

```dart
/// ShellX mobile client logic: machines, tabs, pairing initiator.
library;
```

Run: `dart pub get` (repo root). Expected: `Got dependencies!`

- [ ] **Step 2: Write the failing test**

`packages/shellx_client/test/pinned_store_test.dart`:

```dart
import 'dart:typed_data';

import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

PinnedMachine machine(String id, int keyByte) => PinnedMachine(
      agentId: id,
      publicKey: Uint8List.fromList(List.filled(32, keyByte)),
      pairedAt: DateTime.utc(2026, 9, 25),
    );

void main() {
  test('PinnedMachine round-trips through JSON', () {
    final original = machine('a1', 5);
    final json = original.toJson();
    expect(json['agent_id'], 'a1');
    expect(json['public_key'], base64UrlNoPad(original.publicKey));
    final copy = PinnedMachine.fromJson(json);
    expect(copy.publicKey, original.publicKey);
    expect(copy.pairedAt, original.pairedAt);
  });

  test('add, find, replace and remove', () async {
    final store = PinnedStore(InMemoryKeyValueStore(), userId: 'u1');
    await store.add(machine('a1', 1));
    await store.add(machine('a2', 2));
    await store.add(machine('a1', 3));
    expect([for (final m in await store.list()) m.agentId], ['a2', 'a1']);
    expect((await store.find('a1'))!.publicKey.first, 3);
    await store.remove('a1');
    expect(await store.find('a1'), isNull);
  });

  test('pins are stored per account under pinned_machines_<userId>', () async {
    final kv = InMemoryKeyValueStore();
    await PinnedStore(kv, userId: 'u1').add(machine('a1', 1));
    expect(await kv.read('pinned_machines_u1'), isNotNull);
    expect(await PinnedStore(kv, userId: 'u2').list(), isEmpty);
    expect(await PinnedStore(kv, userId: 'u1').list(), hasLength(1));
  });

  test('corrupt storage reads as no pins', () async {
    final kv = InMemoryKeyValueStore();
    await kv.write('pinned_machines_u1', '[{"agent_id": 1}]');
    expect(await PinnedStore(kv, userId: 'u1').list(), isEmpty);
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `cd packages/shellx_client && dart test test/pinned_store_test.dart`
Expected: FAIL — compilation error `Couldn't find constructor 'PinnedMachine'`.

- [ ] **Step 4: Implement**

`packages/shellx_client/lib/src/client_types.dart`:

```dart
import 'package:shellx_core/shellx_core.dart';

/// Why [ClientService.pair] failed (spec §5.3, §12).
enum PairingFailure {
  /// The QR's agent id is not a device of this account.
  notInAccount,

  /// Wrong, expired or already used pairing code.
  invalidOrExpired,
  agentOffline,
  protocolUnsupported,
  timeout,
}

final class PairingException implements Exception {
  const PairingException(this.failure);
  final PairingFailure failure;
  @override
  String toString() => 'PairingException(${failure.name})';
}

/// Why an IK handshake with a pinned machine failed.
enum MachineConnectionFailure { untrusted, protocolUnsupported, agentOffline, timeout }

/// Thrown by [MachineClient] operations when the machine cannot be reached.
final class MachineConnectionException implements Exception {
  const MachineConnectionException(this.failure);
  final MachineConnectionFailure failure;
  @override
  String toString() => 'MachineConnectionException(${failure.name})';
}

sealed class MachineConnectionState {
  const MachineConnectionState();
}

final class MachineIdle extends MachineConnectionState {
  const MachineIdle();
}

final class MachineConnecting extends MachineConnectionState {
  const MachineConnecting();
}

final class MachineReady extends MachineConnectionState {
  const MachineReady();
}

final class MachineFailed extends MachineConnectionState {
  const MachineFailed(this.failure);
  final MachineConnectionFailure failure;
}

/// An `error` message from the agent answering one of our requests.
final class AppErrorException implements Exception {
  const AppErrorException(this.code, this.message);
  final AppErrorCode code;
  final String message;
  @override
  String toString() => 'AppErrorException(${code.wire}: $message)';
}
```

`packages/shellx_client/lib/src/pinned_store.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

/// A machine whose static key this phone pinned when pairing (spec §5.3
/// step 6).
final class PinnedMachine {
  const PinnedMachine({
    required this.agentId,
    required this.publicKey,
    required this.pairedAt,
  });

  final String agentId;
  final Uint8List publicKey;
  final DateTime pairedAt;

  Map<String, Object?> toJson() => {
        'agent_id': agentId,
        'public_key': base64UrlNoPad(publicKey),
        'paired_at': pairedAt.millisecondsSinceEpoch,
      };

  static PinnedMachine fromJson(Map<String, Object?> json) => PinnedMachine(
        agentId: json['agent_id'] as String,
        publicKey: fromBase64UrlNoPad(json['public_key'] as String),
        pairedAt: DateTime.fromMillisecondsSinceEpoch(json['paired_at'] as int,
            isUtc: true),
      );
}

/// Pinned machines of one account, stored as a JSON array under
/// `pinned_machines_<userId>` so another account on the same phone never
/// sees them (spec §5.2).
final class PinnedStore {
  PinnedStore(KeyValueStore store, {required String userId})
      : _store = store,
        _key = 'pinned_machines_$userId';

  final KeyValueStore _store;
  final String _key;
  Future<void> _lock = Future.value();

  Future<List<PinnedMachine>> list() => _read();

  Future<PinnedMachine?> find(String agentId) async {
    for (final machine in await _read()) {
      if (machine.agentId == agentId) return machine;
    }
    return null;
  }

  /// Adds [machine], replacing an entry with the same agentId.
  Future<void> add(PinnedMachine machine) => _mutate((machines) => [
        ...machines.where((m) => m.agentId != machine.agentId),
        machine,
      ]);

  Future<void> remove(String agentId) => _mutate(
      (machines) => machines.where((m) => m.agentId != agentId).toList());

  Future<List<PinnedMachine>> _read() async {
    final raw = await _store.read(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<Object?>;
      return [
        for (final entry in decoded)
          PinnedMachine.fromJson((entry as Map).cast<String, Object?>()),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _mutate(
      List<PinnedMachine> Function(List<PinnedMachine> machines) change) {
    final next = _lock.then((_) async {
      final updated = change(await _read());
      await _store.write(
          _key, jsonEncode([for (final m in updated) m.toJson()]));
    });
    _lock = next.catchError((Object _) {});
    return next;
  }
}
```

Replace the whole content of `packages/shellx_client/lib/shellx_client.dart` with:

```dart
/// ShellX mobile client logic: machines, tabs, pairing initiator.
library;

export 'src/client_types.dart';
export 'src/pinned_store.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/shellx_client && dart test test/pinned_store_test.dart`
Expected: `+4: All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml packages/shellx_client/pubspec.yaml packages/shellx_client/lib packages/shellx_client/test/pinned_store_test.dart
git commit -m "feat(client): scaffold shellx_client with types and PinnedStore"
```

### Task 11: `ClientTab` — streaming UTF-8, `received`, ack policy, event backlog

**Files:**
- Create: `packages/shellx_client/lib/src/client_tab.dart`
- Modify: `packages/shellx_client/lib/shellx_client.dart`
- Test: `packages/shellx_client/test/client_tab_test.dart`

**Interfaces:**
- Consumes: core `AckMessage`, `AppErrorCode`, `DetachReason`; `package:meta` `@internal`.
- Produces (overview §5.7):
  - `sealed class TabEvent`; `TabOutput(String text)`, `TabReset()`, `TabExited(int exitCode)`, `TabDetached(DetachReason reason)`, `TabError(AppErrorCode code, String message)`.
  - `const int kAckThresholdBytes = 32 * 1024; const Duration kAckDelay = Duration(milliseconds: 100);`
  - `final class ClientTab { int get id; int get index; String get shell; int get received; bool get isAttached; Stream<TabEvent> get events; }` with `@internal`: `ClientTab({required int id, required int index, required String shell, required int cols, required int rows, required void Function(AckMessage ack) sendAck})`, `cols`, `rows`, `updateSize`, `beginAttach`, `handleOutput(int seq, Uint8List data)`, `handleReset`, `handleExited`, `handleDetached`, `handleError`, `dispose`.
  - Semantics: duplicate/overlapping output is trimmed by `seq`; reset sets `received = 0` and uses a fresh decoder (a half character is dropped, never shown as `�`); acks fire at ≥ 32 KiB unacked or 100 ms after the last output; events before the first listener are buffered and replayed to it.

- [ ] **Step 1: Write the failing test**

`packages/shellx_client/test/client_tab_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

ClientTab newTab(List<AckMessage> acks) => ClientTab(
      id: 3,
      index: 1,
      shell: 'zsh',
      cols: 80,
      rows: 24,
      sendAck: acks.add,
    );

Uint8List bytes(List<int> values) => Uint8List.fromList(values);

/// Delivers [data] as consecutive output messages cut at [cuts].
void deliver(ClientTab tab, List<int> data, List<int> cuts, {int from = 0}) {
  var start = 0;
  for (final cut in [...cuts, data.length]) {
    tab.handleOutput(from + start, bytes(data.sublist(start, cut)));
    start = cut;
  }
}

String textOf(List<TabEvent> events) =>
    events.whereType<TabOutput>().map((e) => e.text).join();

void main() {
  test('multi-byte characters split across output messages decode whole', () {
    fakeAsync((async) {
      final tab = newTab([]);
      final events = <TabEvent>[];
      tab.events.listen(events.add);
      final data = utf8.encode('Việt Nam 😀!');
      // Cut inside "ệ" (3 bytes) and inside the emoji (4 bytes).
      final e = utf8.encode('Vi').length;
      final emoji = utf8.encode('Việt Nam ').length;
      deliver(tab, data, [e + 1, e + 2, emoji + 1, emoji + 3]);
      async.flushMicrotasks();

      expect(textOf(events), 'Việt Nam 😀!');
      expect(textOf(events), isNot(contains('�')));
      expect(tab.received, data.length);
    });
  });

  test('a reset drops a half-received character and starts a fresh decoder',
      () {
    fakeAsync((async) {
      final tab = newTab([]);
      final events = <TabEvent>[];
      tab.events.listen(events.add);
      final e = utf8.encode('ệ');
      tab.handleOutput(0, bytes([0x61, e[0]])); // "a" + first byte of "ệ"
      tab.handleReset();
      tab.handleOutput(500, bytes(utf8.encode('ok')));
      async.flushMicrotasks();

      expect(events.map((e) => e.runtimeType),
          [TabOutput, TabReset, TabOutput]);
      expect(textOf(events), 'aok');
      expect(textOf(events), isNot(contains('�')));
      expect(tab.received, 502);
    });
  });

  test('received follows seq; duplicates and overlaps are not shown twice',
      () {
    fakeAsync((async) {
      final tab = newTab([]);
      final events = <TabEvent>[];
      tab.events.listen(events.add);
      tab.handleOutput(0, bytes(utf8.encode('abcd')));
      tab.handleOutput(0, bytes(utf8.encode('abcd')));
      tab.handleOutput(2, bytes(utf8.encode('cdef')));
      async.flushMicrotasks();
      expect(textOf(events), 'abcdef');
      expect(tab.received, 6);
    });
  });

  test('acks after 32 KiB immediately, otherwise 100 ms after the last output',
      () {
    fakeAsync((async) {
      final acks = <AckMessage>[];
      final tab = newTab(acks);
      tab.handleOutput(0, Uint8List(10));
      async.elapse(const Duration(milliseconds: 60));
      tab.handleOutput(10, Uint8List(10));
      async.elapse(const Duration(milliseconds: 99));
      expect(acks, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect([for (final a in acks) (a.id, a.seq)], [(3, 20)]);

      tab.handleOutput(20, Uint8List(32 * 1024));
      expect(acks.last.seq, 20 + 32 * 1024);
      async.elapse(const Duration(seconds: 1));
      expect(acks, hasLength(2));
    });
  });

  test('beginAttach counts everything received as acknowledged', () {
    fakeAsync((async) {
      final acks = <AckMessage>[];
      final tab = newTab(acks);
      tab.handleOutput(0, Uint8List(100));
      tab.beginAttach();
      async.elapse(const Duration(seconds: 1));
      expect(acks, isEmpty);
    });
  });

  test('detached, exited and error end the tab and stop acks', () {
    fakeAsync((async) {
      final acks = <AckMessage>[];
      final tab = newTab(acks);
      final events = <TabEvent>[];
      tab.events.listen(events.add);
      tab.handleOutput(0, Uint8List(10));
      tab.handleDetached(DetachReason.takenOver);
      async.elapse(const Duration(seconds: 1));
      expect(tab.isAttached, isFalse);
      expect(acks, isEmpty);

      tab.beginAttach();
      expect(tab.isAttached, isTrue);
      tab.handleExited(0);
      expect(tab.isAttached, isFalse);
      tab.beginAttach();
      tab.handleError(AppErrorCode.sessionNotFound, 'gone');
      expect(tab.isAttached, isFalse);
      async.flushMicrotasks();
      expect(events.map((e) => e.runtimeType),
          [TabOutput, TabDetached, TabExited, TabError]);
    });
  });

  test('events emitted before the first listener are replayed to it', () {
    fakeAsync((async) {
      final tab = newTab([]);
      tab.handleReset();
      tab.handleOutput(0, bytes(utf8.encode('replayed')));
      final events = <TabEvent>[];
      tab.events.listen(events.add);
      async.flushMicrotasks();
      expect(events.first, isA<TabReset>());
      expect(textOf(events), 'replayed');
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/shellx_client && dart test test/client_tab_test.dart`
Expected: FAIL — compilation errors `Couldn't find constructor 'ClientTab'`, `Type 'TabEvent' not found`.

- [ ] **Step 3: Implement**

`packages/shellx_client/lib/src/client_tab.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:shellx_core/shellx_core.dart';

sealed class TabEvent {
  const TabEvent();
}

/// Terminal output, already decoded from UTF-8 as a stream: a character
/// split across two `output` messages is emitted whole.
final class TabOutput extends TabEvent {
  const TabOutput(this.text);
  final String text;
}

/// The agent restarted the stream from the start of its buffer: clear the
/// screen before writing further output.
final class TabReset extends TabEvent {
  const TabReset();
}

final class TabExited extends TabEvent {
  const TabExited(this.exitCode);
  final int exitCode;
}

final class TabDetached extends TabEvent {
  const TabDetached(this.reason);
  final DetachReason reason;
}

/// The session is gone or could not be used (e.g. `session_not_found`
/// after the agent restarted): the UI shows "Session ended".
final class TabError extends TabEvent {
  const TabError(this.code, this.message);
  final AppErrorCode code;
  final String message;
}

/// Send an ack after this many unacknowledged bytes (spec §6.5).
const int kAckThresholdBytes = 32 * 1024;

/// Or this long after the last output while bytes are unacknowledged.
const Duration kAckDelay = Duration(milliseconds: 100);

/// One terminal tab attached to a session on a machine.
///
/// Events emitted before the first listener subscribes are buffered and
/// replayed to it (replayed output arrives before `attach()` returns);
/// after that the stream behaves as a plain broadcast stream.
final class ClientTab {
  @internal
  ClientTab({
    required this.id,
    required this.index,
    required this.shell,
    required int cols,
    required int rows,
    required void Function(AckMessage ack) sendAck,
  })  : _cols = cols,
        _rows = rows,
        _sendAck = sendAck {
    _decoder = _newDecoder();
  }

  final int id;
  final int index;
  final String shell;
  final void Function(AckMessage ack) _sendAck;

  late final StreamController<TabEvent> _events =
      StreamController<TabEvent>.broadcast(onListen: _replayBacklog);
  final _backlog = <TabEvent>[];
  bool _everListened = false;
  late ByteConversionSink _decoder;
  int _cols;
  int _rows;
  int _received = 0;
  int _acked = 0;
  bool _attached = true;
  Timer? _ackTimer;

  /// Total output bytes received: the `last_seq` for re-attaching.
  int get received => _received;

  /// False after [TabDetached], [TabExited] or [TabError].
  bool get isAttached => _attached;

  Stream<TabEvent> get events => _events.stream;

  @internal
  int get cols => _cols;

  @internal
  int get rows => _rows;

  @internal
  void updateSize(int cols, int rows) {
    _cols = cols;
    _rows = rows;
  }

  /// Called when (re-)attaching: the agent treats everything up to
  /// [received] as acknowledged.
  @internal
  void beginAttach() {
    _attached = true;
    _acked = _received;
  }

  @internal
  void handleOutput(int seq, Uint8List data) {
    if (!_attached) return;
    final end = seq + data.length;
    if (end <= _received) return; // Duplicate.
    final fresh = seq < _received
        ? Uint8List.sublistView(data, _received - seq)
        : data;
    _received = end;
    _decoder.add(fresh);
    if (_received - _acked >= kAckThresholdBytes) {
      _flushAck();
    } else {
      _ackTimer?.cancel();
      _ackTimer = Timer(kAckDelay, _flushAck);
    }
  }

  @internal
  void handleReset() {
    // A fresh decoder drops any half-received multi-byte character.
    _decoder = _newDecoder();
    _received = 0;
    _acked = 0;
    _cancelAck();
    _emit(const TabReset());
  }

  @internal
  void handleExited(int exitCode) {
    _end();
    _emit(TabExited(exitCode));
  }

  @internal
  void handleDetached(DetachReason reason) {
    _end();
    _emit(TabDetached(reason));
  }

  @internal
  void handleError(AppErrorCode code, String message) {
    _end();
    _emit(TabError(code, message));
  }

  @internal
  void dispose() {
    _end();
    _events.close();
  }

  void _end() {
    _attached = false;
    _cancelAck();
  }

  void _flushAck() {
    _cancelAck();
    if (!_attached || _received <= _acked) return;
    _acked = _received;
    _sendAck(AckMessage(id: id, seq: _received));
  }

  void _cancelAck() {
    _ackTimer?.cancel();
    _ackTimer = null;
  }

  ByteConversionSink _newDecoder() =>
      const Utf8Decoder(allowMalformed: true).startChunkedConversion(
          _TextSink((text) {
        if (text.isNotEmpty) _emit(TabOutput(text));
      }));

  void _emit(TabEvent event) {
    if (_events.isClosed) return;
    if (_everListened) {
      _events.add(event);
    } else {
      _backlog.add(event);
    }
  }

  void _replayBacklog() {
    if (_everListened) return;
    _everListened = true;
    for (final event in _backlog) {
      _events.add(event);
    }
    _backlog.clear();
  }
}

final class _TextSink implements Sink<String> {
  _TextSink(this._onText);
  final void Function(String text) _onText;

  @override
  void add(String data) => _onText(data);

  @override
  void close() {}
}
```

Replace the whole content of `packages/shellx_client/lib/shellx_client.dart` with:

```dart
/// ShellX mobile client logic: machines, tabs, pairing initiator.
library;

export 'src/client_tab.dart';
export 'src/client_types.dart';
export 'src/pinned_store.dart';
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/shellx_client && dart test test/client_tab_test.dart`
Expected: `+7: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_client/lib packages/shellx_client/test/client_tab_test.dart
git commit -m "feat(client): add ClientTab with streaming UTF-8 and ack policy"
```

### Task 12: `MachineClient` and `ClientService` — IK connect and sessions over the channel

**Files:**
- Create: `packages/shellx_client/lib/src/machine_client.dart`, `packages/shellx_client/lib/src/client_service.dart`
- Modify: `packages/shellx_client/lib/shellx_client.dart`
- Create (test support): `packages/shellx_client/test/support/fake_relay.dart`, `packages/shellx_client/test/support/fake_pty.dart`, `packages/shellx_client/test/support/drive.dart` (copies), `packages/shellx_client/test/support/harness.dart`
- Test: `packages/shellx_client/test/machine_client_test.dart`

**Interfaces:**
- Consumes: Tasks 10–11; `shellx_agent` (dev dependency: real `AgentService`, `SessionManager`, `TrustedStore`, `PairingCodeManager`); Task 6/4 harness files; core `RelayConnection`, frames, Noise, `SecureChannel`, `Hs1Payload`/`Hs2Payload`, app messages, `kMaxOutputChunk`.
- Produces (overview §5.7; pairing in Task 13, re-attach in Task 14):
  - `final class MachineClient { String get agentId; MachineConnectionState get state; Stream<MachineConnectionState> get states; Future<void> connect(); Future<List<SessionInfo>> listSessions(); Future<ClientTab> openSession({required int cols, required int rows}); Future<ClientTab> attach(int id, {required int cols, required int rows}); List<ClientTab> get tabs; void input(int id, Uint8List data); void resize(int id, int cols, int rows); Future<void> closeTab(int id); }` + `@internal` constructor, `handleFrame(RelayFrame)`, `relayLost()`, `shutdown()`.
  - `connect()` failures: no/odd pin or HS2 `untrusted`/`pairing_invalid` → `untrusted` (and the pin is forgotten, spec §12); HS2 `proto_unsupported`, other proto or undecodable HS2 → `protocolUnsupported`; `ERROR peer_offline` → `agentOffline`; no HS2 within `handshakeTimeout`, relay not connected, or undecryptable HS2 → `timeout`. Requests (`listSessions`, `openSession`, `attach`) time out with `MachineConnectionException(timeout)`; losing the channel fails them with `agentOffline`. `attach(id)` of an id not in the last `session.list` → `AppErrorException(session_not_found)` without sending; agent `error` → `AppErrorException`. `closeTab` sends `session.close` only for an attached tab.
  - `final class ClientService { ClientService({required RelayConnection relay, required ShellxApi api, required String deviceId, required String userId, required NoiseKeyPair identity, required PinnedStore pinned, required String appVersion, required String deviceName, required DevicePlatform platform, Duration handshakeTimeout = const Duration(seconds: 10)}); Future<void> start(); Future<void> stop(); bool isOnline(String agentId); Stream<PresenceFrame> get presence; MachineClient machine(String agentId); }` — `start()` loads pins then calls `relay.start()`; `machine()` throws `StateError` when not pinned and returns one instance per agent; on relay loss it emits synthetic offline PRESENCE for every online device.
  - Test support `Harness(FakeAsync, TestKeys, {bool paired = true})`: real agent + phone + tablet (same account) + a foreign-account agent; `run`, `pty`, `phoneMachine`, `tabletMachine`, `startAgent` (each start seeds its `SessionManager` with `Random(1000 + n)`, so a restarted agent starts at a different id), `restartAgent`, `disconnectPhone`, `reconnectPhone`, `now`; `TabRecorder`; ids `agentId`, `phoneId`, `tabletId`, `foreignAgentId`, `userId`.

- [ ] **Step 1: Copy the shared test support (byte-for-byte)**

```bash
mkdir -p packages/shellx_client/test/support
cp packages/shellx_agent/test/support/fake_relay.dart packages/shellx_client/test/support/fake_relay.dart
cp packages/shellx_agent/test/support/fake_pty.dart packages/shellx_client/test/support/fake_pty.dart
cp packages/shellx_agent/test/support/drive.dart packages/shellx_client/test/support/drive.dart
```

- [ ] **Step 2: Write the harness**

`packages/shellx_client/test/support/harness.dart`:

```dart
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';

import 'drive.dart';
import 'fake_pty.dart';
import 'fake_relay.dart';

const userId = 'user-1';
const agentId = 'a0000000-0000-4000-8000-000000000001';
const phoneId = 'b0000000-0000-4000-8000-000000000002';
const tabletId = 'b0000000-0000-4000-8000-000000000003';
const foreignAgentId = 'c0000000-0000-4000-8000-000000000009';

/// Static keys, generated once per test file in `setUpAll`.
final class TestKeys {
  TestKeys._(this.agent, this.phone, this.tablet, this.other);
  final NoiseKeyPair agent, phone, tablet, other;

  static Future<TestKeys> generate() async => TestKeys._(
        await NoiseKeyPair.generate(),
        await NoiseKeyPair.generate(),
        await NoiseKeyPair.generate(),
        await NoiseKeyPair.generate(),
      );
}

/// A real [AgentService] (fake PTYs) and two real [ClientService]s (phone and
/// tablet, same account) wired through a [FakeRelay]. With `paired: true`
/// both phones are already trusted by the agent and have its key pinned.
final class Harness {
  Harness(this.async, this.keys, {bool paired = true}) {
    agentDevice =
        relay.addDevice(id: agentId, userId: userId, kind: DeviceKind.agent);
    phoneDevice =
        relay.addDevice(id: phoneId, userId: userId, kind: DeviceKind.mobile);
    tabletDevice = relay.addDevice(
        id: tabletId, userId: userId, kind: DeviceKind.mobile, name: 'Tablet');
    relay.addDevice(
        id: foreignAgentId, userId: 'user-2', kind: DeviceKind.agent);
    trusted = TrustedStore(InMemoryKeyValueStore());
    if (paired) {
      run(trusted.add(TrustedDevice(
          mobileId: phoneId,
          publicKey: keys.phone.publicKey,
          name: 'Test Phone',
          pairedAt: DateTime.utc(2026))));
      run(trusted.add(TrustedDevice(
          mobileId: tabletId,
          publicKey: keys.tablet.publicKey,
          name: 'Tablet',
          pairedAt: DateTime.utc(2026))));
    }
    startAgent();
    phonePins = PinnedStore(InMemoryKeyValueStore(), userId: userId);
    tabletPins = PinnedStore(InMemoryKeyValueStore(), userId: userId);
    phone = _client(phoneDevice, keys.phone, phonePins, paired: paired);
    tablet = _client(tabletDevice, keys.tablet, tabletPins, paired: paired);
    settle(async);
  }

  final FakeAsync async;
  final TestKeys keys;
  final relay = FakeRelay();
  final agentEvents = <AgentEvent>[];
  DateTime now = DateTime.utc(2026, 9, 25, 12);
  late final FakeDevice agentDevice;
  late final FakeDevice phoneDevice;
  late final FakeDevice tabletDevice;
  late final TrustedStore trusted;
  late final PinnedStore phonePins;
  late final PinnedStore tabletPins;
  late final ClientService phone;
  late final ClientService tablet;
  late FakePtyFactory ptys;
  late SessionManager sessions;
  late AgentService agent;
  int _agentStarts = 0;

  /// Drives [future] to completion in fake time.
  T run<T>(Future<T> future) => drive(async, future);

  /// The most recently spawned fake shell.
  FakePty get pty => ptys.ptys.last;

  MachineClient get phoneMachine => phone.machine(agentId);
  MachineClient get tabletMachine => tablet.machine(agentId);

  /// Starts a fresh agent process: new session manager (its own random
  /// first session id), same identity and trust list.
  void startAgent() {
    ptys = FakePtyFactory();
    sessions = SessionManager(
      ptyFactory: ptys,
      shellResolver: const FixedShellResolver(),
      homeDirectory: '/Users/test',
      baseEnvironment: const {},
      random: Random(1000 + _agentStarts++),
    );
    agent = AgentService(
      relay: RelayConnection(
        wsUri: relay.wsUri,
        token: () => agentDevice.token,
        connector: relay.connector,
        backoff: Backoff(random: Random(11)),
      ),
      api: ShellxApi(baseUri: relay.baseUri, httpClient: relay.httpClient)
        ..token = agentDevice.token,
      deviceId: agentId,
      identity: keys.agent,
      trusted: trusted,
      sessions: sessions,
      pairing: PairingCodeManager(now: () => now),
      appVersion: '1.0.0',
    );
    agent.events.listen(agentEvents.add);
    run(agent.start());
    settle(async);
  }

  /// Simulates quitting the agent (all sessions lost) and starting it again.
  void restartAgent() {
    agent.stop();
    sessions.closeAll();
    settle(async);
    startAgent();
  }

  /// Cuts the phone off the relay; it cannot reconnect until [reconnectPhone].
  void disconnectPhone() {
    relay.setReachable(phoneId, false);
    relay.dropConnection(phoneId);
    settle(async);
  }

  /// Lets the phone reconnect (backoff ≤ 1 s) and finish re-attaching.
  void reconnectPhone() {
    relay.setReachable(phoneId, true);
    async.elapse(const Duration(seconds: 3));
  }

  ClientService _client(
    FakeDevice device,
    NoiseKeyPair identity,
    PinnedStore pins, {
    required bool paired,
  }) {
    if (paired) {
      run(pins.add(PinnedMachine(
          agentId: agentId,
          publicKey: keys.agent.publicKey,
          pairedAt: DateTime.utc(2026))));
    }
    final service = ClientService(
      relay: RelayConnection(
        wsUri: relay.wsUri,
        token: () => device.token,
        connector: relay.connector,
        backoff: Backoff(random: Random(21)),
      ),
      api: ShellxApi(baseUri: relay.baseUri, httpClient: relay.httpClient)
        ..token = device.token,
      deviceId: device.id,
      userId: userId,
      identity: identity,
      pinned: pins,
      appVersion: '1.0.0',
      deviceName: device.name,
      platform: DevicePlatform.ios,
    );
    run(service.start());
    return service;
  }
}

/// Records every event of a tab.
final class TabRecorder {
  TabRecorder(ClientTab tab) {
    tab.events.listen(events.add);
  }

  final events = <TabEvent>[];

  String get text => events.whereType<TabOutput>().map((e) => e.text).join();
}
```

- [ ] **Step 3: Write the failing test**

`packages/shellx_client/test/machine_client_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/drive.dart';
import 'support/harness.dart';

Matcher failsWith(MachineConnectionFailure failure) => throwsA(
    isA<MachineConnectionException>().having((e) => e.failure, 'failure', failure));

Matcher appError(AppErrorCode code) =>
    throwsA(isA<AppErrorException>().having((e) => e.code, 'code', code));

void main() {
  late TestKeys keys;
  setUpAll(() async => keys = await TestKeys.generate());

  test('connect performs the IK handshake and becomes ready', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final states = <MachineConnectionState>[];
      h.phoneMachine.states.listen(states.add);
      h.run(h.phoneMachine.connect());
      settle(async);
      expect(h.phoneMachine.state, isA<MachineReady>());
      expect(states.map((s) => s.runtimeType), [MachineConnecting, MachineReady]);
      expect(h.agent.activeChannelCount, 1);
    });
  });

  test('untrusted: fails, forgets the pinned key', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      h.run(h.trusted.remove(phoneId));
      final machine = h.phoneMachine;
      expect(() => h.run(machine.connect()),
          failsWith(MachineConnectionFailure.untrusted));
      expect(machine.state, isA<MachineFailed>());
      expect(h.run(h.phonePins.find(agentId)), isNull);
      expect(() => h.phone.machine(agentId), throwsStateError);
    });
  });

  test('agent offline: fails with agentOffline', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      h.agent.stop();
      settle(async);
      expect(() => h.run(h.phoneMachine.connect()),
          failsWith(MachineConnectionFailure.agentOffline));
    });
  });

  test('no answer: fails with timeout after the handshake timeout', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      h.relay.onData = (from, to, frame) => to == agentId ? null : frame;
      final started = async.elapsed;
      expect(() => h.run(h.phoneMachine.connect()),
          failsWith(MachineConnectionFailure.timeout));
      expect(async.elapsed - started, greaterThanOrEqualTo(const Duration(seconds: 10)));
    });
  });

  test('proto_unsupported from the agent maps to protocolUnsupported', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      h.agent.stop();
      settle(async);
      // A hand-written agent that answers every HS1 with proto_unsupported.
      final raw = RelayConnection(
        wsUri: h.relay.wsUri,
        token: () => h.agentDevice.token,
        connector: h.relay.connector,
      );
      raw.frames.listen((frame) async {
        if (frame is! DataFrame) return;
        final hello = ChannelPayload.decode(frame.payload);
        final responder = NoiseHandshake.responder(
          pattern: NoisePattern.ik,
          localStatic: keys.agent,
          prologue: buildPrologue(agentDeviceId: agentId, mobileDeviceId: frame.peer),
        );
        await responder.readMessage(hello.noiseMessage);
        final reply = await responder.writeMessage(Hs2Payload(
          proto: 2,
          app: '9.0.0',
          status: HandshakeStatus.protoUnsupported,
        ).encode());
        raw.send(DataFrame(
          peer: frame.peer,
          channel: frame.channel,
          payload: ChannelPayload(PayloadKind.hs2, reply).encode(),
        ));
      });
      raw.start();
      settle(async);
      expect(() => h.run(h.phoneMachine.connect()),
          failsWith(MachineConnectionFailure.protocolUnsupported));
    });
  });

  test('openSession, output and input', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final recorder = TabRecorder(tab);
      expect((tab.index, tab.shell, tab.isAttached), (1, 'zsh', true));

      h.pty.emit('hello');
      settle(async);
      h.phoneMachine.input(tab.id, Uint8List.fromList(utf8.encode('ls\r')));
      settle(async);

      expect(recorder.text, 'hello');
      expect(tab.received, 5);
      expect(h.pty.writtenText, 'ls\r');
      expect(h.phoneMachine.tabs.single, same(tab));
    });
  });

  test('input larger than 16 KiB is split into several messages', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final paste = Uint8List.fromList(List.generate(40 * 1024, (i) => 0x61 + i % 26));
      h.phoneMachine.input(tab.id, paste);
      settle(async);
      expect([for (final w in h.pty.writes) w.length], [16384, 16384, 8192]);
      expect([for (final w in h.pty.writes) ...w], paste);
    });
  });

  test('resize is ignored below 1 and clamped to 1000 by the agent', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      h.phoneMachine.resize(tab.id, 0, 10);
      h.phoneMachine.resize(tab.id, 10, 0);
      h.phoneMachine.resize(tab.id, -5, -5);
      h.phoneMachine.resize(tab.id, 100, 40);
      h.phoneMachine.resize(tab.id, 5000, 5000);
      settle(async);
      expect(h.pty.resizes, [(100, 40), (1000, 1000)]);
    });
  });

  test('the phone receives far more than the 256 KiB window thanks to acks',
      () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      for (var i = 0; i < 30; i++) {
        h.pty.emitBytes(List.filled(32 * 1024, 0x2e));
      }
      async.elapse(const Duration(seconds: 2));
      expect(tab.received, 30 * 32 * 1024);
    });
  });

  test('UTF-8 characters split between two output batches arrive whole', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final recorder = TabRecorder(tab);
      final data = utf8.encode('Xin chào 😀');
      h.pty.emitBytes(data.sublist(0, 7)); // ends inside "à"
      async.elapse(const Duration(milliseconds: 20));
      h.pty.emitBytes(data.sublist(7, 12)); // ends inside the emoji
      async.elapse(const Duration(milliseconds: 20));
      h.pty.emitBytes(data.sublist(12));
      settle(async);
      expect(recorder.text, 'Xin chào 😀');
      expect(recorder.text, isNot(contains('�')));
    });
  });

  test('listSessions and attach from a second phone take the session over',
      () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final phoneTab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final phoneEvents = TabRecorder(phoneTab);
      h.pty.emit('shared ');
      settle(async);

      final listed = h.run(h.tabletMachine.listSessions());
      expect([for (final s in listed) (s.id, s.index, s.shell, s.attached)],
          [(phoneTab.id, 1, 'zsh', true)]);
      final tabletTab =
          h.run(h.tabletMachine.attach(phoneTab.id, cols: 100, rows: 30));
      final tabletEvents = TabRecorder(tabletTab);
      h.pty.emit('screen');
      settle(async);

      expect(phoneTab.isAttached, isFalse);
      expect(phoneEvents.events.last, isA<TabDetached>());
      expect((phoneEvents.events.last as TabDetached).reason, DetachReason.takenOver);
      expect(tabletTab.isAttached, isTrue);
      expect(tabletEvents.text, 'shared screen');
      expect(h.pty.resizes.last, (100, 30));
    });
  });

  test('session_limit and spawn_failed surface as AppErrorException', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      for (var i = 0; i < 10; i++) {
        h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      }
      expect(() => h.run(h.phoneMachine.openSession(cols: 80, rows: 24)),
          appError(AppErrorCode.sessionLimit));
      h.sessions.closeAll();
      settle(async);
      h.ptys.failWith = StateError('no pty');
      expect(() => h.run(h.phoneMachine.openSession(cols: 80, rows: 24)),
          appError(AppErrorCode.spawnFailed));
    });
  });

  test('attach to a session that no longer exists fails with session_not_found',
      () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      expect(() => h.run(h.tabletMachine.attach(77, cols: 80, rows: 24)),
          appError(AppErrorCode.sessionNotFound));

      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      h.run(h.tabletMachine.listSessions());
      h.pty.exit(0);
      settle(async);
      expect(() => h.run(h.tabletMachine.attach(tab.id, cols: 80, rows: 24)),
          appError(AppErrorCode.sessionNotFound));
      expect(h.tabletMachine.tabs, isEmpty);
    });
  });

  test('shell exit, closed_by_host and closeTab', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final exiting = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final exitingEvents = TabRecorder(exiting);
      h.pty.exit(3);
      settle(async);
      expect(exiting.isAttached, isFalse);
      expect((exitingEvents.events.last as TabExited).exitCode, 3);

      final hosted = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final hostedEvents = TabRecorder(hosted);
      h.sessions.closeSession(hosted.id);
      settle(async);
      expect(hostedEvents.events.map((e) => e.runtimeType), [TabDetached, TabExited]);
      expect((hostedEvents.events.first as TabDetached).reason, DetachReason.closedByHost);

      final closing = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      h.run(h.phoneMachine.closeTab(closing.id));
      settle(async);
      expect(h.pty.killed, isTrue);
      expect(h.phoneMachine.tabs.map((t) => t.id), [exiting.id, hosted.id]);
      h.run(h.phoneMachine.closeTab(exiting.id));
      h.run(h.phoneMachine.closeTab(hosted.id));
      expect(h.phoneMachine.tabs, isEmpty);
    });
  });
}
```

- [ ] **Step 4: Run it to verify it fails**

Run: `cd packages/shellx_client && dart test test/machine_client_test.dart`
Expected: FAIL — compilation errors `Type 'ClientService' not found`, `Type 'MachineClient' not found`.

- [ ] **Step 5: Implement**

`packages/shellx_client/lib/src/machine_client.dart`:

```dart
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:shellx_core/shellx_core.dart';

import 'client_tab.dart';
import 'client_types.dart';

final class _PendingOpen {
  _PendingOpen(this.cols, this.rows);
  final int cols;
  final int rows;
  final completer = Completer<ClientTab>();
}

/// The phone's connection to one pinned machine: IK handshake, request /
/// response over the encrypted channel, and the machine's tabs.
///
/// Created by [ClientService.machine]; frames for this agent are routed to
/// it by the service.
final class MachineClient {
  @internal
  MachineClient({
    required this.agentId,
    required RelayConnection relay,
    required String deviceId,
    required NoiseKeyPair identity,
    required Hs1Payload hello,
    required Duration timeout,
    required Uint8List? Function() pinnedKey,
    required Future<void> Function() forgetPin,
  })  : _relay = relay,
        _deviceId = deviceId,
        _identity = identity,
        _hello = hello,
        _timeout = timeout,
        _pinnedKey = pinnedKey,
        _forgetPin = forgetPin;

  final String agentId;
  final RelayConnection _relay;
  final String _deviceId;
  final NoiseKeyPair _identity;
  final Hs1Payload _hello;
  final Duration _timeout;
  final Uint8List? Function() _pinnedKey;
  final Future<void> Function() _forgetPin;

  MachineConnectionState _state = const MachineIdle();
  final _states = StreamController<MachineConnectionState>.broadcast();
  Future<void>? _connecting;
  ({ChannelId channel, Completer<Uint8List?> reply})? _handshake;
  ChannelId? _channelId;
  SecureChannel? _secure;
  Future<void> _inbox = Future.value();
  Future<void> _outbox = Future.value();

  final _tabs = <int, ClientTab>{};
  final _pendingOpens = <_PendingOpen>[];
  final _pendingLists = <Completer<List<SessionInfo>>>[];
  final _pendingAttaches = <int, Completer<void>>{};
  var _known = <int, SessionInfo>{};

  MachineConnectionState get state => _state;

  Stream<MachineConnectionState> get states => _states.stream;

  List<ClientTab> get tabs => List.unmodifiable(_tabs.values);

  /// IK handshake with the pinned key. Throws [MachineConnectionException]
  /// and moves to [MachineFailed] on failure; no-op when already ready.
  Future<void> connect() {
    if (_state is MachineReady) return Future.value();
    return _connecting ??=
        _handshakeNow().whenComplete(() => _connecting = null);
  }

  Future<List<SessionInfo>> listSessions() async {
    await connect();
    final completer = Completer<List<SessionInfo>>();
    _pendingLists.add(completer);
    unawaited(_send([const SessionList()]));
    return completer.future.timeout(_timeout, onTimeout: () {
      _pendingLists.remove(completer);
      throw const MachineConnectionException(MachineConnectionFailure.timeout);
    });
  }

  /// Opens a new session. Throws [AppErrorException] (`session_limit`,
  /// `spawn_failed`) or [MachineConnectionException].
  Future<ClientTab> openSession({required int cols, required int rows}) async {
    await connect();
    final pending = _PendingOpen(cols, rows);
    _pendingOpens.add(pending);
    unawaited(_send([SessionOpen(cols: cols, rows: rows)]));
    return pending.completer.future.timeout(_timeout, onTimeout: () {
      _pendingOpens.remove(pending);
      throw const MachineConnectionException(MachineConnectionFailure.timeout);
    });
  }

  /// Attaches to an existing session (from [listSessions]) or re-attaches an
  /// existing tab. Throws [AppErrorException] with `session_not_found` when
  /// the session no longer exists.
  Future<ClientTab> attach(int id, {required int cols, required int rows}) async {
    await connect();
    var tab = _tabs[id];
    final isNew = tab == null;
    if (tab == null) {
      final info = _known[id] ??
          (await listSessions()).where((s) => s.id == id).firstOrNull;
      if (info == null) {
        throw AppErrorException(
            AppErrorCode.sessionNotFound, 'Session $id not found');
      }
      tab = ClientTab(
        id: id,
        index: info.index,
        shell: info.shell,
        cols: cols,
        rows: rows,
        sendAck: _sendAck,
      );
      _tabs[id] = tab;
    }
    tab.updateSize(cols, rows);
    try {
      await _attach(tab);
    } catch (_) {
      if (isNew) {
        _tabs.remove(id);
        tab.dispose();
      }
      rethrow;
    }
    return tab;
  }

  /// Sends keystrokes; data larger than 16 KiB is split into several
  /// `input` messages. Dropped while the channel is down.
  void input(int id, Uint8List data) {
    final tab = _tabs[id];
    if (tab == null || !tab.isAttached || _secure == null) return;
    for (var offset = 0; offset < data.length; offset += kMaxOutputChunk) {
      final end = min(offset + kMaxOutputChunk, data.length);
      unawaited(_send([InputMessage(id: id, data: data.sublist(offset, end))]));
    }
  }

  /// Ignored when [cols] or [rows] is below 1 (keyboard animating, rotation).
  void resize(int id, int cols, int rows) {
    if (cols < 1 || rows < 1) return;
    final tab = _tabs[id];
    if (tab == null) return;
    tab.updateSize(cols, rows);
    if (!tab.isAttached || _secure == null) return;
    unawaited(_send([ResizeMessage(id: id, cols: cols, rows: rows)]));
  }

  /// Removes the tab. An attached tab also closes its session on the agent;
  /// a detached or ended tab is only removed locally.
  Future<void> closeTab(int id) async {
    final tab = _tabs.remove(id);
    if (tab == null) return;
    final wasAttached = tab.isAttached;
    tab.dispose();
    if (wasAttached) await _send([SessionClose(id: id)]);
  }

  /// Routed here by [ClientService]: DATA from this agent, ERROR and
  /// PRESENCE about it.
  @internal
  void handleFrame(RelayFrame frame) {
    _inbox = _inbox.then((_) => _onFrame(frame)).catchError((Object _) {});
  }

  /// The phone's relay connection dropped: the channel is gone.
  @internal
  void relayLost() {
    _inbox = _inbox.then((_) => _channelLost()).catchError((Object _) {});
  }

  /// Unpaired: forget the channel and every tab without touching sessions.
  @internal
  void shutdown() {
    _channelLost();
    for (final tab in _tabs.values) {
      tab.dispose();
    }
    _tabs.clear();
  }

  Future<void> _handshakeNow() async {
    final key = _pinnedKey();
    if (key == null || key.length != 32) {
      _fail(MachineConnectionFailure.untrusted);
    }
    _setState(const MachineConnecting());
    final handshake = NoiseHandshake.initiator(
      pattern: NoisePattern.ik,
      localStatic: _identity,
      remoteStatic: key,
      prologue: buildPrologue(agentDeviceId: agentId, mobileDeviceId: _deviceId),
    );
    final hello = await handshake.writeMessage(_hello.encode());
    final channel = ChannelId.random();
    final reply = Completer<Uint8List?>();
    _handshake = (channel: channel, reply: reply);
    final sent = _relay.send(DataFrame(
      peer: agentId,
      channel: channel,
      payload: ChannelPayload(PayloadKind.hs1Ik, hello).encode(),
    ));
    Uint8List? message;
    try {
      if (!sent) _fail(MachineConnectionFailure.timeout);
      message = await reply.future.timeout(_timeout);
    } on TimeoutException {
      _fail(MachineConnectionFailure.timeout);
    } finally {
      _handshake = null;
    }
    if (message == null) _fail(MachineConnectionFailure.agentOffline);
    final Hs2Payload answer;
    try {
      answer = Hs2Payload.decode(await handshake.readMessage(message));
    } on FormatException {
      _fail(MachineConnectionFailure.protocolUnsupported);
    } catch (_) {
      _fail(MachineConnectionFailure.timeout); // Undecryptable: like no answer.
    }
    if (answer.proto != kAppProtocolVersion ||
        answer.status == HandshakeStatus.protoUnsupported) {
      _fail(MachineConnectionFailure.protocolUnsupported);
    }
    if (answer.status != HandshakeStatus.ok) {
      await _forgetPin(); // Spec §12: untrusted → drop the pinned key.
      _fail(MachineConnectionFailure.untrusted);
    }
    _channelId = channel;
    _secure = SecureChannel(handshake.split());
    _setState(const MachineReady());
  }

  Never _fail(MachineConnectionFailure failure) {
    _setState(MachineFailed(failure));
    throw MachineConnectionException(failure);
  }

  Future<void> _onFrame(RelayFrame frame) async {
    switch (frame) {
      case DataFrame(:final channel, :final payload):
        final ChannelPayload decoded;
        try {
          decoded = ChannelPayload.decode(payload);
        } on FrameFormatException {
          return;
        }
        if (decoded.kind == PayloadKind.hs2) {
          final pending = _handshake;
          if (pending != null &&
              pending.channel == channel &&
              !pending.reply.isCompleted) {
            pending.reply.complete(decoded.noiseMessage);
          }
          return;
        }
        final secure = _secure;
        if (decoded.kind != PayloadKind.transport ||
            secure == null ||
            channel != _channelId) {
          return;
        }
        final List<AppMessage> messages;
        try {
          messages = await secure.open(decoded.noiseMessage);
        } catch (_) {
          _channelLost(); // Spec §6.3: any decrypt error drops the channel.
          return;
        }
        if (!identical(secure, _secure)) return;
        messages.forEach(_dispatch);
      case ErrorFrame(:final code, :final channel):
        if (code != RelayErrorCode.peerOffline) return;
        final pending = _handshake;
        if (pending != null &&
            pending.channel == channel &&
            !pending.reply.isCompleted) {
          pending.reply.complete(null);
        } else if (channel == _channelId) {
          _channelLost();
        }
      case PresenceFrame(:final online):
        if (!online) _channelLost();
      case EventFrame():
        break;
    }
  }

  void _dispatch(AppMessage message) {
    switch (message) {
      case SessionListResult(:final sessions):
        _known = {for (final s in sessions) s.id: s};
        if (_pendingLists.isNotEmpty) {
          _pendingLists.removeAt(0).complete(sessions);
        }
      case SessionOpened(:final id, :final index, :final shell):
        if (_pendingOpens.isEmpty) return;
        final pending = _pendingOpens.removeAt(0);
        final tab = ClientTab(
          id: id,
          index: index,
          shell: shell,
          cols: pending.cols,
          rows: pending.rows,
          sendAck: _sendAck,
        );
        _tabs[id] = tab;
        pending.completer.complete(tab);
      case SessionAttached(:final id):
        _pendingAttaches.remove(id)?.complete();
      case SessionReset(:final id):
        _tabs[id]?.handleReset();
      case OutputMessage(:final id, :final seq, :final data):
        _tabs[id]?.handleOutput(seq, data);
      case SessionExited(:final id, :final exitCode):
        _tabs[id]?.handleExited(exitCode);
      case SessionDetached(:final id, :final reason):
        _tabs[id]?.handleDetached(reason);
      case ErrorMessage(:final code, :final message, :final id):
        final error = AppErrorException(code, message);
        if (id == null) {
          if (_pendingOpens.isNotEmpty) {
            _pendingOpens.removeAt(0).completer.completeError(error);
          }
          return;
        }
        _pendingAttaches.remove(id)?.completeError(error);
        _tabs[id]?.handleError(code, message);
      default:
        break;
    }
  }

  Future<void> _attach(ClientTab tab) {
    tab.beginAttach();
    final done = Completer<void>();
    _pendingAttaches[tab.id] = done;
    unawaited(_send([
      SessionAttach(
          id: tab.id, cols: tab.cols, rows: tab.rows, lastSeq: tab.received),
    ]));
    return done.future.timeout(_timeout, onTimeout: () {
      _pendingAttaches.remove(tab.id);
      throw const MachineConnectionException(MachineConnectionFailure.timeout);
    });
  }

  void _channelLost() {
    _secure = null;
    _channelId = null;
    const lost =
        MachineConnectionException(MachineConnectionFailure.agentOffline);
    for (final pending in _pendingOpens) {
      pending.completer.completeError(lost);
    }
    _pendingOpens.clear();
    for (final pending in _pendingLists) {
      pending.completeError(lost);
    }
    _pendingLists.clear();
    for (final pending in _pendingAttaches.values) {
      pending.completeError(lost);
    }
    _pendingAttaches.clear();
    if (_state is MachineReady) _setState(const MachineIdle());
  }

  void _sendAck(AckMessage ack) => unawaited(_send([ack]));

  Future<void> _send(List<AppMessage> messages) {
    final secure = _secure;
    final channel = _channelId;
    if (secure == null || channel == null) return Future.value();
    final result = _outbox.then((_) async {
      final payload = await secure.seal(messages);
      if (!identical(secure, _secure)) return;
      _relay.send(DataFrame(peer: agentId, channel: channel, payload: payload));
    });
    _outbox = result.catchError((Object _) {});
    return result;
  }

  void _setState(MachineConnectionState state) {
    _state = state;
    _states.add(state);
  }
}
```

`packages/shellx_client/lib/src/client_service.dart`:

```dart
import 'dart:async';

import 'package:shellx_core/shellx_core.dart';

import 'machine_client.dart';
import 'pinned_store.dart';

/// The phone side of the relay protocol: presence and one [MachineClient]
/// per pinned machine.
///
/// [start] loads the pinned machines, subscribes and calls `relay.start()`;
/// [stop] calls `relay.stop()`.
final class ClientService {
  ClientService({
    required RelayConnection relay,
    required ShellxApi api,
    required String deviceId,
    required String userId,
    required NoiseKeyPair identity,
    required PinnedStore pinned,
    required String appVersion,
    required String deviceName,
    required DevicePlatform platform,
    Duration handshakeTimeout = const Duration(seconds: 10),
  })  : _relay = relay,
        _deviceId = deviceId,
        _identity = identity,
        _pinned = pinned,
        _timeout = handshakeTimeout,
        _hello = Hs1Payload(
          proto: kAppProtocolVersion,
          app: appVersion,
          name: deviceName,
          platform: platform,
        );

  final RelayConnection _relay;
  final String _deviceId;
  final NoiseKeyPair _identity;
  final PinnedStore _pinned;
  final Duration _timeout;
  final Hs1Payload _hello;

  final _pins = <String, PinnedMachine>{};
  final _machines = <String, MachineClient>{};
  final _online = <String>{};
  final _presence = StreamController<PresenceFrame>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];
  bool _connected = false;

  Stream<PresenceFrame> get presence => _presence.stream;

  bool isOnline(String agentId) => _online.contains(agentId);

  Future<void> start() async {
    if (_subscriptions.isNotEmpty) return;
    for (final machine in await _pinned.list()) {
      _pins[machine.agentId] = machine;
    }
    _subscriptions
      ..add(_relay.frames.listen(_onFrame))
      ..add(_relay.states.listen(_onState));
    _relay.start();
  }

  Future<void> stop() async {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel()); // May return a root-zone future.
    }
    _subscriptions.clear();
    _onState(RelayConnectionState.stopped);
    await _relay.stop();
  }

  /// The client for a pinned machine; the same instance per [agentId].
  /// Throws [StateError] when the machine is not pinned (call [start] first).
  MachineClient machine(String agentId) {
    if (!_pins.containsKey(agentId)) {
      throw StateError('Machine $agentId is not paired with this phone');
    }
    return _machines[agentId] ??= MachineClient(
      agentId: agentId,
      relay: _relay,
      deviceId: _deviceId,
      identity: _identity,
      hello: _hello,
      timeout: _timeout,
      pinnedKey: () => _pins[agentId]?.publicKey,
      forgetPin: () => _forget(agentId),
    );
  }

  Future<void> _forget(String agentId) async {
    _pins.remove(agentId);
    await _pinned.remove(agentId);
  }

  void _onFrame(RelayFrame frame) {
    switch (frame) {
      case PresenceFrame(:final deviceId, :final online):
        if (online) {
          _online.add(deviceId);
        } else {
          _online.remove(deviceId);
        }
        _presence.add(frame);
        _machines[deviceId]?.handleFrame(frame);
      case DataFrame(:final peer):
        _machines[peer]?.handleFrame(frame);
      case ErrorFrame(:final deviceId):
        _machines[deviceId]?.handleFrame(frame);
      case EventFrame():
        break;
    }
  }

  void _onState(RelayConnectionState state) {
    final connected = state == RelayConnectionState.connected;
    if (connected == _connected) return;
    _connected = connected;
    if (connected) return;
    for (final deviceId in _online.toList()) {
      _presence.add(PresenceFrame(deviceId: deviceId, online: false));
    }
    _online.clear();
    for (final machine in _machines.values) {
      machine.relayLost();
    }
  }
}
```

Replace the whole content of `packages/shellx_client/lib/shellx_client.dart` with:

```dart
/// ShellX mobile client logic: machines, tabs, pairing initiator.
library;

export 'src/client_service.dart';
export 'src/client_tab.dart';
export 'src/client_types.dart';
export 'src/machine_client.dart';
export 'src/pinned_store.dart';
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd packages/shellx_client && dart test test/machine_client_test.dart`
Expected: `+14: All tests passed!`

Run: `dart analyze packages/shellx_client` (repo root). Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add packages/shellx_client/lib packages/shellx_client/test/support packages/shellx_client/test/machine_client_test.dart
git commit -m "feat(client): add MachineClient and ClientService"
```

### Task 13: Pairing initiator (IKpsk2), `unpair`, `pairing_removed`

**Files:**
- Modify: `packages/shellx_client/lib/src/client_service.dart` (full replacement below)
- Test: `packages/shellx_client/test/client_service_test.dart`

**Interfaces:**
- Consumes: Task 12 `ClientService`/`MachineClient`; `AgentService.startPairing/cancelPairing/revoke` (Task 9) in tests; core `PairingUri`, `NoisePattern.ikPsk2`, `PairConfirm`, `ShellxApi.devices/deletePairing`.
- Produces (overview §5.7):
  - `Future<void> pair(PairingUri uri)` — agent id not an agent of `api.devices()` → `notInAccount` (nothing sent); key/secret not 32 bytes, undecryptable HS2 (wrong/expired/used code) or HS2 `pairing_invalid`/`untrusted` → `invalidOrExpired`; `proto_unsupported`/other proto/undecodable HS2 → `protocolUnsupported`; `ERROR peer_offline` → `agentOffline`; no HS2 within `handshakeTimeout` or relay down → `timeout`; `ok` → send `pair.confirm` on the pairing channel, pin `{agentId, publicKey from the QR}`, done. `ApiException` from `devices()` propagates.
  - `Future<void> unpair(String agentId)` — shuts the `MachineClient` down (tabs disposed, sessions untouched), forgets the pin, then `DELETE /v1/pairings/<agentId>/<me>` (errors propagate).
  - `EVENT pairing_removed` addressed to this phone forgets that agent's pin (the relay can only reduce trust).

- [ ] **Step 1: Write the failing test**

`packages/shellx_client/test/client_service_test.dart`:

```dart
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/drive.dart';
import 'support/harness.dart';

Matcher pairingFails(PairingFailure failure) => throwsA(
    isA<PairingException>().having((e) => e.failure, 'failure', failure));

void main() {
  late TestKeys keys;
  setUpAll(() async => keys = await TestKeys.generate());

  test('pair pins the agent key, the agent trusts the phone, IK then works',
      () {
    fakeAsync((async) {
      final h = Harness(async, keys, paired: false);
      final uri = h.agent.startPairing();
      h.run(h.phone.pair(uri));
      settle(async);

      final pin = h.run(h.phonePins.find(agentId))!;
      expect(pin.publicKey, keys.agent.publicKey);
      final trusted = h.run(h.trusted.find(phoneId))!;
      expect(trusted.publicKey, keys.phone.publicKey);
      expect(trusted.name, 'Test Phone');
      expect(h.agentEvents.whereType<MobilePaired>(), hasLength(1));
      expect(h.relay.pairings, {(agentId, phoneId)});

      h.run(h.phoneMachine.connect());
      expect(h.phoneMachine.state, isA<MachineReady>());
    });
  });

  test('a QR from a machine of another account is refused before any '
      'handshake', () {
    fakeAsync((async) {
      final h = Harness(async, keys, paired: false);
      final uri = PairingUri(
        agentDeviceId: foreignAgentId,
        agentPublicKey: keys.other.publicKey,
        secret: Uint8List(32),
      );
      expect(() => h.run(h.phone.pair(uri)),
          pairingFails(PairingFailure.notInAccount));
      expect(h.relay.delivered, isEmpty);
    });
  });

  test('a wrong pairing secret is invalidOrExpired', () {
    fakeAsync((async) {
      final h = Harness(async, keys, paired: false);
      final real = h.agent.startPairing();
      final forged = PairingUri(
        agentDeviceId: real.agentDeviceId,
        agentPublicKey: real.agentPublicKey,
        secret: Uint8List.fromList(List.filled(32, 1)),
      );
      expect(() => h.run(h.phone.pair(forged)),
          pairingFails(PairingFailure.invalidOrExpired));
      expect(h.run(h.phonePins.list()), isEmpty);
      expect(h.run(h.trusted.find(phoneId)), isNull);
    });
  });

  test('an expired or cancelled code is invalidOrExpired', () {
    fakeAsync((async) {
      final h = Harness(async, keys, paired: false);
      final expired = h.agent.startPairing();
      h.now = h.now.add(const Duration(minutes: 5, seconds: 1));
      expect(() => h.run(h.phone.pair(expired)),
          pairingFails(PairingFailure.invalidOrExpired));

      final cancelled = h.agent.startPairing();
      h.agent.cancelPairing();
      expect(() => h.run(h.phone.pair(cancelled)),
          pairingFails(PairingFailure.invalidOrExpired));
      expect(h.run(h.trusted.find(phoneId)), isNull);
    });
  });

  test('a used code cannot pair a second phone', () {
    fakeAsync((async) {
      final h = Harness(async, keys, paired: false);
      final uri = h.agent.startPairing();
      h.run(h.phone.pair(uri));
      expect(() => h.run(h.tablet.pair(uri)),
          pairingFails(PairingFailure.invalidOrExpired));
    });
  });

  test('pairing with an offline agent fails with agentOffline', () {
    fakeAsync((async) {
      final h = Harness(async, keys, paired: false);
      final uri = h.agent.startPairing();
      h.agent.stop();
      settle(async);
      expect(() => h.run(h.phone.pair(uri)),
          pairingFails(PairingFailure.agentOffline));
    });
  });

  test('no answer (e.g. a QR with the wrong agent key) times out', () {
    fakeAsync((async) {
      final h = Harness(async, keys, paired: false);
      final real = h.agent.startPairing();
      final wrongKey = PairingUri(
        agentDeviceId: agentId,
        agentPublicKey: keys.other.publicKey,
        secret: real.secret,
      );
      expect(() => h.run(h.phone.pair(wrongKey)),
          pairingFails(PairingFailure.timeout));
    });
  });

  test('machine() needs a pin and returns one instance per agent', () {
    fakeAsync((async) {
      final unpaired = Harness(async, keys, paired: false);
      expect(() => unpaired.phone.machine(agentId), throwsStateError);
      final h = Harness(async, keys);
      expect(h.phone.machine(agentId), same(h.phone.machine(agentId)));
    });
  });

  test('presence and isOnline follow the agent', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final seen = <(String, bool)>[];
      h.phone.presence.listen((p) => seen.add((p.deviceId, p.online)));
      expect(h.phone.isOnline(agentId), isTrue);
      h.agent.stop();
      settle(async);
      expect(h.phone.isOnline(agentId), isFalse);
      expect(seen, [(agentId, false)]);
    });
  });

  test('unpair forgets the pin, deletes the pairing and the agent stops '
      'trusting the phone', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      h.run(h.phone.unpair(agentId));
      settle(async);

      expect(h.run(h.phonePins.find(agentId)), isNull);
      expect(tab.isAttached, isFalse);
      expect(h.relay.requests, contains('DELETE /v1/pairings/$agentId/$phoneId'));
      expect(h.run(h.trusted.find(phoneId)), isNull);
      expect(h.sessions.sessions, hasLength(1)); // Sessions are not closed.
    });
  });

  test('when the agent revokes the phone, pairing_removed forgets the pin',
      () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      h.run(h.agent.revoke(phoneId));
      settle(async);
      expect(h.run(h.phonePins.find(agentId)), isNull);
      expect(h.run(h.tabletPins.find(agentId)), isNotNull);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/shellx_client && dart test test/client_service_test.dart`
Expected: FAIL — compilation errors `The method 'pair' isn't defined for the type 'ClientService'` and `The method 'unpair' isn't defined…`.

- [ ] **Step 3: Implement — replace the whole of `packages/shellx_client/lib/src/client_service.dart` with:**

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:shellx_core/shellx_core.dart';

import 'client_types.dart';
import 'machine_client.dart';
import 'pinned_store.dart';

/// The phone side of the relay protocol: presence, pairing (Noise IKpsk2
/// initiator) and one [MachineClient] per pinned machine.
///
/// [start] loads the pinned machines, subscribes and calls `relay.start()`;
/// [stop] calls `relay.stop()`.
final class ClientService {
  ClientService({
    required RelayConnection relay,
    required ShellxApi api,
    required String deviceId,
    required String userId,
    required NoiseKeyPair identity,
    required PinnedStore pinned,
    required String appVersion,
    required String deviceName,
    required DevicePlatform platform,
    Duration handshakeTimeout = const Duration(seconds: 10),
  })  : _relay = relay,
        _api = api,
        _deviceId = deviceId,
        _identity = identity,
        _pinned = pinned,
        _timeout = handshakeTimeout,
        _hello = Hs1Payload(
          proto: kAppProtocolVersion,
          app: appVersion,
          name: deviceName,
          platform: platform,
        );

  final RelayConnection _relay;
  final ShellxApi _api;
  final String _deviceId;
  final NoiseKeyPair _identity;
  final PinnedStore _pinned;
  final Duration _timeout;
  final Hs1Payload _hello;

  final _pins = <String, PinnedMachine>{};
  final _machines = <String, MachineClient>{};
  final _online = <String>{};
  final _presence = StreamController<PresenceFrame>.broadcast();
  final _pairings = <ChannelId, ({String agentId, Completer<Uint8List?> reply})>{};
  final _subscriptions = <StreamSubscription<Object?>>[];
  bool _connected = false;

  Stream<PresenceFrame> get presence => _presence.stream;

  bool isOnline(String agentId) => _online.contains(agentId);

  Future<void> start() async {
    if (_subscriptions.isNotEmpty) return;
    for (final machine in await _pinned.list()) {
      _pins[machine.agentId] = machine;
    }
    _subscriptions
      ..add(_relay.frames.listen(_onFrame))
      ..add(_relay.states.listen(_onState));
    _relay.start();
  }

  Future<void> stop() async {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel()); // May return a root-zone future.
    }
    _subscriptions.clear();
    _onState(RelayConnectionState.stopped);
    await _relay.stop();
  }

  /// The client for a pinned machine; the same instance per [agentId].
  /// Throws [StateError] when the machine is not pinned (call [start] first).
  MachineClient machine(String agentId) {
    if (!_pins.containsKey(agentId)) {
      throw StateError('Machine $agentId is not paired with this phone');
    }
    return _machines[agentId] ??= MachineClient(
      agentId: agentId,
      relay: _relay,
      deviceId: _deviceId,
      identity: _identity,
      hello: _hello,
      timeout: _timeout,
      pinnedKey: () => _pins[agentId]?.publicKey,
      forgetPin: () => _forget(agentId),
    );
  }

  /// Pairs with the machine in a scanned QR (spec §5.3 steps 3–6).
  /// Throws [PairingException]; network errors surface as [ApiException].
  Future<void> pair(PairingUri uri) async {
    final agentId = uri.agentDeviceId;
    final devices = await _api.devices();
    if (!devices.any((d) => d.id == agentId && d.kind == DeviceKind.agent)) {
      throw const PairingException(PairingFailure.notInAccount);
    }
    if (uri.secret.length != 32 || uri.agentPublicKey.length != 32) {
      throw const PairingException(PairingFailure.invalidOrExpired);
    }
    final handshake = NoiseHandshake.initiator(
      pattern: NoisePattern.ikPsk2,
      localStatic: _identity,
      remoteStatic: uri.agentPublicKey,
      prologue: buildPrologue(agentDeviceId: agentId, mobileDeviceId: _deviceId),
      psk: uri.secret,
    );
    final hello = await handshake.writeMessage(_hello.encode());
    final channel = ChannelId.random();
    final reply = Completer<Uint8List?>();
    _pairings[channel] = (agentId: agentId, reply: reply);
    try {
      final sent = _relay.send(DataFrame(
        peer: agentId,
        channel: channel,
        payload: ChannelPayload(PayloadKind.hs1IkPsk2, hello).encode(),
      ));
      if (!sent) throw const PairingException(PairingFailure.timeout);
      final Uint8List? message;
      try {
        message = await reply.future.timeout(_timeout);
      } on TimeoutException {
        throw const PairingException(PairingFailure.timeout);
      }
      if (message == null) {
        throw const PairingException(PairingFailure.agentOffline);
      }
      final Hs2Payload answer;
      try {
        answer = Hs2Payload.decode(await handshake.readMessage(message));
      } on FormatException {
        throw const PairingException(PairingFailure.protocolUnsupported);
      } catch (_) {
        // Wrong or expired code: HS2 cannot be decrypted (spec §5.3).
        throw const PairingException(PairingFailure.invalidOrExpired);
      }
      if (answer.proto != kAppProtocolVersion ||
          answer.status == HandshakeStatus.protoUnsupported) {
        throw const PairingException(PairingFailure.protocolUnsupported);
      }
      if (answer.status != HandshakeStatus.ok) {
        throw const PairingException(PairingFailure.invalidOrExpired);
      }
      final secure = SecureChannel(handshake.split());
      _relay.send(DataFrame(
        peer: agentId,
        channel: channel,
        payload: await secure.seal(const [PairConfirm()]),
      ));
      final pin = PinnedMachine(
        agentId: agentId,
        publicKey: uri.agentPublicKey,
        pairedAt: DateTime.now().toUtc(),
      );
      await _pinned.add(pin);
      _pins[agentId] = pin;
    } finally {
      _pairings.remove(channel);
    }
  }

  /// Settings → unpair (spec §5.5): forget the pin and the machine's tabs,
  /// then delete the pairing record (the hub tells the agent).
  Future<void> unpair(String agentId) async {
    _machines.remove(agentId)?.shutdown();
    await _forget(agentId);
    await _api.deletePairing(agentId, _deviceId);
  }

  Future<void> _forget(String agentId) async {
    _pins.remove(agentId);
    await _pinned.remove(agentId);
  }

  void _onFrame(RelayFrame frame) {
    switch (frame) {
      case PresenceFrame(:final deviceId, :final online):
        if (online) {
          _online.add(deviceId);
        } else {
          _online.remove(deviceId);
        }
        _presence.add(frame);
        _machines[deviceId]?.handleFrame(frame);
      case DataFrame(:final peer, :final channel, :final payload):
        final pairing = _pairings[channel];
        if (pairing != null && pairing.agentId == peer) {
          try {
            final decoded = ChannelPayload.decode(payload);
            if (decoded.kind == PayloadKind.hs2 && !pairing.reply.isCompleted) {
              pairing.reply.complete(decoded.noiseMessage);
            }
          } on FrameFormatException {
            // Ignore garbage on the pairing channel.
          }
          return;
        }
        _machines[peer]?.handleFrame(frame);
      case ErrorFrame(:final code, :final deviceId, :final channel):
        final pairing = _pairings[channel];
        if (pairing != null &&
            pairing.agentId == deviceId &&
            code == RelayErrorCode.peerOffline &&
            !pairing.reply.isCompleted) {
          pairing.reply.complete(null);
          return;
        }
        _machines[deviceId]?.handleFrame(frame);
      case EventFrame(:final event):
        // The agent revoked this phone: forget the pinned key too.
        final agentId = event['agent_id'];
        if (event['event'] == 'pairing_removed' &&
            event['mobile_id'] == _deviceId &&
            agentId != null) {
          unawaited(_forget(agentId));
        }
    }
  }

  void _onState(RelayConnectionState state) {
    final connected = state == RelayConnectionState.connected;
    if (connected == _connected) return;
    _connected = connected;
    if (connected) return;
    for (final deviceId in _online.toList()) {
      _presence.add(PresenceFrame(deviceId: deviceId, online: false));
    }
    _online.clear();
    for (final machine in _machines.values) {
      machine.relayLost();
    }
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd packages/shellx_client && dart test test/client_service_test.dart test/machine_client_test.dart`
Expected: `+25: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_client/lib/src/client_service.dart packages/shellx_client/test/client_service_test.dart
git commit -m "feat(client): add pairing initiator and unpair"
```

### Task 14: Automatic re-handshake and re-attach

**Files:**
- Modify: `packages/shellx_client/lib/src/machine_client.dart` (5 edits), `packages/shellx_client/lib/src/client_service.dart` (1 edit)
- Test: `packages/shellx_client/test/reconnect_test.dart`

**Interfaces:**
- Consumes: Tasks 12–13; harness `disconnectPhone`, `reconnectPhone`, `restartAgent`.
- Produces: `@internal void MachineClient.relayConnected()`; behaviour (overview §5.7 comment): when the phone's relay reconnects, when the agent's PRESENCE comes back online, or after a decrypt error, the machine re-handshakes on a **new** `channel_id` and re-attaches every tab with `isAttached == true` using `lastSeq = received`, one at a time. Tabs that were taken over, exited or ended are not re-attached; a machine without such tabs stays idle. `session_not_found` ends the tab (`TabError`) — after an agent restart this is what happens even when the new agent has a session with more output than `last_seq`, because ids start at a new random value; `session.reset` clears it (`TabReset`, e.g. after more than 256 KiB was produced while away). `_resume` is never awaited inside the frame queue (it waits for HS2 from that same queue).

- [ ] **Step 1: Write the failing test**

`packages/shellx_client/test/reconnect_test.dart`:

```dart
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/drive.dart';
import 'support/harness.dart';

void main() {
  late TestKeys keys;
  setUpAll(() async => keys = await TestKeys.generate());

  test('after a relay drop the phone re-handshakes, re-attaches with '
      'last_seq and receives the output it missed', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final recorder = TabRecorder(tab);
      h.pty.emit('before ');
      settle(async);

      h.disconnectPhone();
      expect(h.sessions.sessions.single.attachedMobileId, isNull);
      h.pty.emit('during');
      settle(async);
      expect(recorder.text, 'before ');

      h.reconnectPhone();
      expect(h.phoneMachine.state, isA<MachineReady>());
      expect(tab.isAttached, isTrue);
      expect(recorder.text, 'before during');
      expect(recorder.events.whereType<TabReset>(), isEmpty);
      expect(h.sessions.sessions.single.attachedMobileId, phoneId);
      expect(h.pty.resizes, [(80, 23), (80, 24)]);
    });
  });

  test('a tab taken over by another phone is not re-attached on reconnect',
      () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final phoneTab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      h.run(h.tabletMachine.listSessions());
      final tabletTab =
          h.run(h.tabletMachine.attach(phoneTab.id, cols: 80, rows: 24));
      final tabletEvents = TabRecorder(tabletTab);
      settle(async);
      expect(phoneTab.isAttached, isFalse);

      h.disconnectPhone();
      h.reconnectPhone();

      expect(phoneTab.isAttached, isFalse);
      expect(h.sessions.sessions.single.attachedMobileId, tabletId);
      expect(tabletTab.isAttached, isTrue);
      expect(tabletEvents.events.whereType<TabDetached>(), isEmpty);
      expect(h.phoneMachine.state, isA<MachineIdle>());
    });
  });

  test('after an agent restart an unknown session id ends the tab with '
      'session_not_found', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final recorder = TabRecorder(tab);
      settle(async);

      h.restartAgent();
      async.elapse(const Duration(seconds: 3));

      expect(tab.isAttached, isFalse);
      final error = recorder.events.whereType<TabError>().single;
      expect(error.code, AppErrorCode.sessionNotFound);
      expect(h.phoneMachine.state, isA<MachineReady>());
    });
  });

  test('after an agent restart a new session never takes over an old tab, '
      'even when last_seq is within its output', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final recorder = TabRecorder(tab);
      h.pty.emit('hello');
      settle(async);

      // While the phone is away the agent restarts and the tablet opens a new
      // session with more output than the phone's last_seq (5 bytes).
      h.disconnectPhone();
      h.restartAgent();
      final other = h.run(h.tabletMachine.openSession(cols: 80, rows: 24));
      expect(other.id, isNot(tab.id));
      h.pty.emit('output of another session');
      settle(async);

      h.reconnectPhone();
      expect(tab.isAttached, isFalse);
      expect(recorder.events.whereType<TabError>().single.code,
          AppErrorCode.sessionNotFound);
      expect(recorder.text, 'hello');
      expect(h.sessions.sessions.single.attachedMobileId, tabletId);
    });
  });

  test('output that overflowed the buffer while away arrives as a reset and '
      'the newest 256 KiB', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final recorder = TabRecorder(tab);
      h.pty.emit('old');
      settle(async);

      h.disconnectPhone();
      h.pty.emitBytes(List.filled(300 * 1024, 0x2e));
      settle(async);
      h.reconnectPhone();

      expect(recorder.events.whereType<TabReset>(), hasLength(1));
      final afterReset = recorder.events
          .skipWhile((e) => e is! TabReset)
          .whereType<TabOutput>()
          .map((e) => e.text)
          .join();
      expect(afterReset.length, 256 * 1024);
      expect(tab.received, 3 + 300 * 1024);
      expect(tab.isAttached, isTrue);
    });
  });

  test('a frame that fails to decrypt makes the phone handshake again on a '
      'new channel and re-attach', () {
    fakeAsync((async) {
      final h = Harness(async, keys);
      final channels = <ChannelId>{};
      var corruptNext = false;
      h.relay.onData = (from, to, frame) {
        if (from == phoneId) channels.add(frame.channel);
        if (corruptNext &&
            from == agentId &&
            frame.payload.first == PayloadKind.transport.wire) {
          corruptNext = false;
          final bad = Uint8List.fromList(frame.payload);
          bad[bad.length - 1] ^= 0xff;
          return DataFrame(peer: frame.peer, channel: frame.channel, payload: bad);
        }
        return frame;
      };
      final tab = h.run(h.phoneMachine.openSession(cols: 80, rows: 24));
      final recorder = TabRecorder(tab);
      settle(async);

      corruptNext = true;
      h.pty.emit('abc');
      async.elapse(const Duration(seconds: 1));

      expect(recorder.text, 'abc');
      expect(tab.isAttached, isTrue);
      expect(channels, hasLength(2));
      expect(h.phoneMachine.state, isA<MachineReady>());
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/shellx_client && dart test test/reconnect_test.dart`
Expected: FAIL — 5 of 6 tests fail (e.g. `Expected: 'before during' Actual: 'before '`, `Expected: an object with length of <1> Actual: WhereTypeIterable<TabReset>:[]`); only the taken-over test passes.

- [ ] **Step 3: Implement**

Edit 1 in `packages/shellx_client/lib/src/machine_client.dart` — replace exactly:

```dart
  Future<void> _outbox = Future.value();

  final _tabs
```

with:

```dart
  Future<void> _outbox = Future.value();
  bool _resuming = false;

  final _tabs
```

Edit 2 in `packages/shellx_client/lib/src/machine_client.dart` — replace exactly:

```dart
  /// The phone's relay connection dropped: the channel is gone.
  @internal
  void relayLost() {
    _inbox = _inbox.then((_) => _channelLost()).catchError((Object _) {});
  }

```

with:

```dart
  /// The phone's relay connection dropped: the channel is gone.
  @internal
  void relayLost() {
    _inbox = _inbox.then((_) => _channelLost()).catchError((Object _) {});
  }

  /// The phone's relay connection is back: re-handshake and re-attach.
  @internal
  void relayConnected() {
    _inbox = _inbox.then((_) => unawaited(_resume())).catchError((Object _) {});
  }

```

Edit 3 in `packages/shellx_client/lib/src/machine_client.dart` — replace exactly:

```dart
        } catch (_) {
          _channelLost(); // Spec §6.3: any decrypt error drops the channel.
          return;
        }
```

with:

```dart
        } catch (_) {
          // Spec §6.3: drop the channel and handshake again on a new id.
          _channelLost();
          unawaited(_resume());
          return;
        }
```

Edit 4 in `packages/shellx_client/lib/src/machine_client.dart` — replace exactly:

```dart
      case PresenceFrame(:final online):
        if (!online) _channelLost();
```

with:

```dart
      case PresenceFrame(:final online):
        if (online) {
          unawaited(_resume()); // Never awaited here: it waits for HS2.
        } else {
          _channelLost();
        }
```

Edit 5 in `packages/shellx_client/lib/src/machine_client.dart` — replace exactly:

```dart
  void _channelLost() {
```

with:

```dart
  /// Re-handshake and re-attach every tab that is still attached (not
  /// taken over, exited or ended) with `last_seq = received`.
  Future<void> _resume() async {
    if (_resuming || _state is MachineReady || _state is MachineConnecting) {
      return;
    }
    final wanted = _tabs.values.where((t) => t.isAttached).toList();
    if (wanted.isEmpty) return;
    _resuming = true;
    try {
      await connect();
      for (final tab in wanted) {
        if (!tab.isAttached || !identical(_tabs[tab.id], tab)) continue;
        try {
          await _attach(tab);
        } on AppErrorException {
          // The tab already received TabError (session_not_found).
        }
      }
    } on MachineConnectionException {
      // State is MachineFailed; the next reconnect or PRESENCE retries.
    } finally {
      _resuming = false;
    }
  }

  void _channelLost() {
```

Edit 1 in `packages/shellx_client/lib/src/client_service.dart` — replace exactly:

```dart
    if (connected) return;
```

with:

```dart
    if (connected) {
      for (final machine in _machines.values) {
        machine.relayConnected();
      }
      return;
    }
```

- [ ] **Step 4: Run the whole package**

Run: `cd packages/shellx_client && dart test`
Expected: `+42: All tests passed!`

Run: `dart analyze packages/shellx_client` (repo root). Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add packages/shellx_client/lib packages/shellx_client/test/reconnect_test.dart
git commit -m "feat(client): re-handshake and re-attach tabs after reconnect"
```

### Task 15: `shellx_e2e` — headless end-to-end suite over the real relay

**Files:**
- Modify: `pubspec.yaml` (root) — add one `workspace:` line
- Create: `packages/shellx_e2e/pubspec.yaml`, `packages/shellx_e2e/test/support/e2e_world.dart`
- Test: `packages/shellx_e2e/test/e2e_test.dart`

**Interfaces:**
- Consumes: everything above; core `ShellxApi.register/login/deleteAccount`, `DeviceIdentity.loadOrCreate`, `ioRelaySocketConnector`, `RelayConnection.reconnectNow`; relay dev server (plan 01, overview §4.3).
- Produces (test-only): `waitUntil`, `DroppableConnector` (`blocked`, `drop()` closes the live socket with 4000), `TabText`, `E2ePhone.login(baseUri, email, password, {name, pins})` (`deviceId`, `api`, `relay`, `connector`, `pinned`, `service`), `E2eWorld.create(baseUri)` (fresh account `e2e-<hex>@example.com`, agent with `ProcessPtyFactory` + `/bin/sh`, `phone`, `intruder` pre-pinned with the agent key, `clockSkew` for the pairing clock, `dispose()` stops everything and deletes the account best-effort).
- Scenarios (spec §13): register → pair → open session → `echo hello` → drop the phone's connection → output produced while away is replayed after re-attach; unknown key rejected (`untrusted`, pin forgotten); expired code and wrong secret → `invalidOrExpired`; account deletion → `AgentRevoked`.

- [ ] **Step 1: Scaffold the package**

In the root `pubspec.yaml`, add this line to the `workspace:` list (keep every existing line):

```yaml
  - packages/shellx_e2e
```

`packages/shellx_e2e/pubspec.yaml`:

```yaml
name: shellx_e2e
description: Headless end-to-end tests for ShellX (agent + client + relay).
publish_to: none
resolution: workspace
environment:
  sdk: ^3.11.0
dev_dependencies:
  shellx_agent: any
  shellx_client: any
  shellx_core: any
  test: ^1.30.0
```

Run: `dart pub get` (repo root). Expected: `Got dependencies!`

- [ ] **Step 2: Write the test**

`packages/shellx_e2e/test/e2e_test.dart`:

```dart
@TestOn('mac-os || linux')
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import 'support/e2e_world.dart';

final String? relayUrl = Platform.environment['SHELLX_E2E_RELAY'];

Uint8List keys(String text) => Uint8List.fromList(utf8.encode(text));

Matcher pairingFails(PairingFailure failure) => throwsA(
    isA<PairingException>().having((e) => e.failure, 'failure', failure));

/// A fresh account and devices for one test, torn down afterwards.
Future<E2eWorld> newWorld() async {
  final world = await E2eWorld.create(Uri.parse(relayUrl!));
  addTearDown(world.dispose);
  return world;
}

void main() {
  group('end-to-end over a real relay', () {
    test('pair → open session → echo → drop connection → re-attach replays '
        'missed output', () async {
      final world = await newWorld();
      final paired = world.agent.events.firstWhere((e) => e is MobilePaired);
      await world.phone.service.pair(world.agent.startPairing());
      final device = ((await paired.timeout(const Duration(seconds: 10)))
              as MobilePaired)
          .device;
      expect(device.mobileId, world.phone.deviceId);

      final machine = world.phone.service.machine(world.agentId);
      await machine.connect();
      final tab = await machine.openSession(cols: 80, rows: 24);
      final output = TabText(tab);
      machine.input(tab.id, keys('echo hello\n'));
      await waitUntil(() => output.text.contains('hello'),
          reason: 'no "hello" in ${jsonEncode(output.text)}');

      machine.input(tab.id, keys('echo started; sleep 1; echo after-drop\n'));
      await waitUntil(() => output.text.contains('started'));
      world.phone.connector.blocked = true;
      await world.phone.connector.drop();
      await waitUntil(() => world.agent.activeChannelCount == 0,
          reason: 'agent did not notice the phone going offline');
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(output.text, isNot(contains('after-drop')));

      world.phone.connector.blocked = false;
      world.phone.relay.reconnectNow();
      await waitUntil(() => output.text.contains('after-drop'),
          timeout: const Duration(seconds: 40),
          reason: 'missed output was not replayed: ${jsonEncode(output.text)}');
      expect(tab.isAttached, isTrue);
      expect(world.sessions.sessions.single.attachedMobileId,
          world.phone.deviceId);
    });

    test('a phone whose key the agent does not trust is rejected', () async {
      final world = await newWorld();
      final machine = world.intruder.service.machine(world.agentId);
      await expectLater(
          machine.connect(),
          throwsA(isA<MachineConnectionException>().having(
              (e) => e.failure, 'failure', MachineConnectionFailure.untrusted)));
      expect(await world.intruder.pinned.find(world.agentId), isNull);
      expect(await world.trusted.find(world.intruder.deviceId), isNull);
    });

    test('an expired pairing code is rejected', () async {
      final world = await newWorld();
      final uri = world.agent.startPairing();
      world.clockSkew += const Duration(minutes: 6);
      await expectLater(world.intruder.service.pair(uri),
          pairingFails(PairingFailure.invalidOrExpired));
      expect(await world.trusted.find(world.intruder.deviceId), isNull);
    });

    test('a wrong pairing secret is rejected', () async {
      final world = await newWorld();
      final real = world.agent.startPairing();
      final forged = PairingUri(
        agentDeviceId: real.agentDeviceId,
        agentPublicKey: real.agentPublicKey,
        secret: Uint8List.fromList(List.filled(32, 7)),
      );
      await expectLater(world.intruder.service.pair(forged),
          pairingFails(PairingFailure.invalidOrExpired));
      expect(await world.trusted.find(world.intruder.deviceId), isNull);
    });

    test('deleting the account revokes the agent (AgentRevoked)', () async {
      final world = await newWorld();
      final revoked = world.agent.events.firstWhere((e) => e is AgentRevoked);
      await world.phone.api.deleteAccount(E2eWorld.password);
      await revoked.timeout(const Duration(seconds: 10));
      expect(world.agent.activeChannelCount, 0);
    });
  },
      skip: relayUrl == null
          ? 'Set SHELLX_E2E_RELAY=http://127.0.0.1:8787 (npm run dev in relay/) '
              'to run'
          : null);
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `cd packages/shellx_e2e && dart test`
Expected: FAIL — `Error when reading 'test/support/e2e_world.dart'`.

- [ ] **Step 4: Write the E2E world**

`packages/shellx_e2e/test/support/e2e_world.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_client/shellx_client.dart';
import 'package:shellx_core/shellx_core.dart';

/// Polls [condition] every 20 ms until it holds or [timeout] passes.
Future<void> waitUntil(bool Function() condition,
    {Duration timeout = const Duration(seconds: 15), String? reason}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(reason ?? 'condition not met', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Real WebSocket connector that keeps the latest socket so a test can cut
/// the connection, and can refuse new connections while [blocked].
final class DroppableConnector {
  RelaySocket? _socket;
  bool blocked = false;

  Future<RelaySocket> call(Uri uri, Map<String, String> headers) async {
    if (blocked) throw const SocketException('blocked by the e2e test');
    return _socket = await ioRelaySocketConnector(uri, headers);
  }

  /// Closes the current socket as if the network had dropped.
  Future<void> drop() async => _socket?.close(4000, 'e2e drop');
}

/// Collects the decoded text of a tab.
final class TabText {
  TabText(ClientTab tab) {
    tab.events.listen((event) {
      if (event is TabOutput) _buffer.write(event.text);
    });
  }
  final _buffer = StringBuffer();
  String get text => _buffer.toString();
}

/// `/bin/sh` without a login profile keeps the e2e output deterministic.
final class _PlainShell implements ShellResolver {
  const _PlainShell();
  @override
  Future<ShellCommand> resolve() async =>
      const ShellCommand(executable: '/bin/sh', arguments: [], name: 'sh');
}

/// A phone logged into the test account.
final class E2ePhone {
  E2ePhone._(this.deviceId, this.api, this.relay, this.connector, this.pinned,
      this.service);

  final String deviceId;
  final ShellxApi api;
  final RelayConnection relay;
  final DroppableConnector connector;
  final PinnedStore pinned;
  final ClientService service;

  static Future<E2ePhone> login(
    Uri baseUri,
    String email,
    String password, {
    required String name,
    List<PinnedMachine> pins = const [],
  }) async {
    final storage = InMemoryKeyValueStore();
    final identity = await DeviceIdentity.loadOrCreate(storage);
    final api = ShellxApi(baseUri: baseUri);
    final auth = await api.login(
      email,
      password,
      DeviceInfo(
        kind: DeviceKind.mobile,
        name: name,
        platform: DevicePlatform.android,
        publicKey: identity.publicKey,
      ),
    );
    api.token = auth.token;
    final pinned = PinnedStore(storage, userId: auth.userId);
    for (final pin in pins) {
      await pinned.add(pin);
    }
    final connector = DroppableConnector();
    final relay = RelayConnection(
      wsUri: wsUriFor(baseUri),
      token: () => api.token,
      connector: connector.call,
    );
    final service = ClientService(
      relay: relay,
      api: api,
      deviceId: auth.deviceId,
      userId: auth.userId,
      identity: identity,
      pinned: pinned,
      appVersion: '1.0.0',
      deviceName: name,
      platform: DevicePlatform.android,
    );
    await service.start();
    await waitUntil(() => relay.state == RelayConnectionState.connected,
        reason: '$name did not connect to the relay');
    return E2ePhone._(auth.deviceId, api, relay, connector, pinned, service);
  }
}

Uri wsUriFor(Uri baseUri) => baseUri.replace(
    scheme: baseUri.scheme == 'https' ? 'wss' : 'ws', path: '/v1/ws');

/// A fresh account (unique random email; the dev relay has rate limits off)
/// with a real agent (dart:io processes) and two phones: the user's phone
/// and an intruder who knows the password but never scanned the QR code (it
/// pins the agent key it somehow learned).
final class E2eWorld {
  E2eWorld._();

  static const password = 'e2e-password-1234';

  late final String agentId;
  late final NoiseKeyPair agentKey;
  late final TrustedStore trusted;
  late final SessionManager sessions;
  late final AgentService agent;
  late final E2ePhone phone;
  late final E2ePhone intruder;

  /// Added to the agent's clock to expire pairing codes.
  Duration clockSkew = Duration.zero;

  static Future<E2eWorld> create(Uri baseUri) async {
    final world = E2eWorld._();
    final random = Random.secure();
    final tag = List.generate(16, (_) => random.nextInt(16).toRadixString(16)).join();
    final email = 'e2e-$tag@example.com';

    final storage = InMemoryKeyValueStore();
    world.agentKey = await DeviceIdentity.loadOrCreate(storage);
    final api = ShellxApi(baseUri: baseUri);
    final auth = await api.register(
      email,
      password,
      DeviceInfo(
        kind: DeviceKind.agent,
        name: 'e2e-agent',
        platform: DevicePlatform.macos,
        publicKey: world.agentKey.publicKey,
      ),
    );
    api.token = auth.token;
    world.agentId = auth.deviceId;
    world.trusted = TrustedStore(storage);
    world.sessions = SessionManager(
      ptyFactory: const ProcessPtyFactory(),
      shellResolver: const _PlainShell(),
      homeDirectory: Directory.systemTemp.path,
      baseEnvironment: Platform.environment,
    );
    final relay = RelayConnection(wsUri: wsUriFor(baseUri), token: () => api.token);
    world.agent = AgentService(
      relay: relay,
      api: api,
      deviceId: auth.deviceId,
      identity: world.agentKey,
      trusted: world.trusted,
      sessions: world.sessions,
      pairing: PairingCodeManager(
          now: () => DateTime.now().add(world.clockSkew)),
      appVersion: '1.0.0',
    );
    await world.agent.start();
    await waitUntil(() => relay.state == RelayConnectionState.connected,
        reason: 'agent did not connect to the relay');

    world.phone = await E2ePhone.login(baseUri, email, password, name: 'e2e-phone');
    world.intruder = await E2ePhone.login(
      baseUri,
      email,
      password,
      name: 'e2e-intruder',
      pins: [
        PinnedMachine(
            agentId: auth.deviceId,
            publicKey: world.agentKey.publicKey,
            pairedAt: DateTime.now().toUtc()),
      ],
    );
    return world;
  }

  /// Stops everything and deletes the account (best effort).
  Future<void> dispose() async {
    sessions.closeAll();
    await phone.service.stop();
    await intruder.service.stop();
    await agent.stop();
    try {
      await phone.api.deleteAccount(password);
    } on ApiException {
      // Already deleted by the test.
    }
  }
}
```

- [ ] **Step 5: Run without a relay (CI default)**

Run: `cd packages/shellx_e2e && dart test`
Expected: `~5: All tests skipped.` with the skip reason `Set SHELLX_E2E_RELAY=…`.

- [ ] **Step 6: Run against the relay dev server**

In a second terminal: `cd relay && npm run dev` (applies local D1 migrations, serves `http://127.0.0.1:8787` with rate limits off; needs plan 01 merged). Then:

Run: `cd packages/shellx_e2e && SHELLX_E2E_RELAY=http://127.0.0.1:8787 dart test`
Expected: `+5: All tests passed!` (runs on macOS/Linux only: `@TestOn('mac-os || linux')`). Stop the dev server afterwards.

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml packages/shellx_e2e
git commit -m "test(e2e): add headless end-to-end tests over the relay"
```

---

## Final verification

- [ ] Run `dart analyze packages/shellx_agent packages/shellx_client packages/shellx_e2e` → `No issues found!`
- [ ] Run `cd packages/shellx_agent && dart test` → `+96: All tests passed!`
- [ ] Run `cd packages/shellx_client && dart test` → `+42: All tests passed!`
- [ ] Run `cd packages/shellx_e2e && dart test` → all skipped; with `SHELLX_E2E_RELAY` and the dev relay → `+5: All tests passed!`

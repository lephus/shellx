// End to end on macOS, in a temporary HOME (the user's own startup files are
// never touched): the installer copies a real `shellx-term` into `bin` and
// writes the zsh block into `.zshrc`; a real interactive zsh in a PTY (via
// script(1), standing in for a new Terminal.app window) runs the block, execs
// `shellx-term`, which connects to a real CoreAgentRuntime's local server and
// shows up as a desktop session. Then turning sharing off restores `.zshrc`.
//
// Needs a built `shellx-term`: the Xcode phase or `cargo build --release` in
// term/ (or SHELLX_TERM_BINARY). Skipped, saying why, when there is none.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:shellx_desktop/src/agent/agent_runtime.dart';
import 'package:shellx_desktop/src/agent/session_core.dart';
import 'package:shellx_desktop/src/terminal_sharing/sharing_paths.dart';
import 'package:shellx_desktop/src/terminal_sharing/shell_blocks.dart';
import 'package:shellx_desktop/src/terminal_sharing/terminal_sharing_setup.dart';

String? _findBinary() {
  final explicit = Platform.environment['SHELLX_TERM_BINARY'];
  if (explicit != null && File(explicit).existsSync()) return explicit;
  final term = p.normalize(
    p.join(Directory.current.path, '..', '..', 'term', 'target'),
  );
  for (final candidate in [
    p.join(term, 'release', 'shellx-term'),
    p.join(term, 'aarch64-apple-darwin', 'release', 'shellx-term'),
    p.join(term, 'x86_64-apple-darwin', 'release', 'shellx-term'),
  ]) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

final class _NoPty implements PtyFactory {
  @override
  Pty spawn(
    ShellCommand command, {
    required String workingDirectory,
    required Map<String, String> environment,
    required int cols,
    required int rows,
  }) => throw UnsupportedError('no shell sessions in this test');
}

final class _SilentRelaySocket implements RelaySocket {
  final _incoming = StreamController<Object>();
  @override
  Stream<Object> get messages => _incoming.stream;
  @override
  void sendText(String text) {}
  @override
  void sendBytes(Uint8List bytes) {}
  @override
  Future<void> close([int? code, String? reason]) async {
    if (!_incoming.isClosed) await _incoming.close();
  }

  @override
  int? get closeCode => null;
}

void main() {
  final binary = Platform.isMacOS ? _findBinary() : null;
  final skip = !Platform.isMacOS
      ? 'macOS only'
      : binary == null
      ? 'no built shellx-term (cargo build --release in term/)'
      : false;

  test(
    'switch on in a temp HOME: a new zsh window becomes a desktop '
    'session; switch off restores .zshrc',
    () async {
      final root = Directory.systemTemp.createTempSync('shellx-e2e-');
      final home = p.join(root.path, 'home');
      Directory(home).createSync();
      final zshrc = File(p.join(home, '.zshrc'))
        ..writeAsStringSync('export SHELLX_E2E_MARK=1\n');
      // The "app bundle": Contents/MacOS/ShellX + Contents/Helpers/shellx-term.
      final app = p.join(root.path, 'ShellX.app', 'Contents');
      Directory(p.join(app, 'Helpers')).createSync(recursive: true);
      File(binary!).copySync(p.join(app, 'Helpers', 'shellx-term'));
      await Process.run('/bin/chmod', [
        '755',
        p.join(app, 'Helpers', 'shellx-term'),
      ]);

      final paths = SharingPaths.macos(
        home: home,
        executable: p.join(app, 'MacOS', 'ShellX'),
      );
      final setup = TerminalSharingSetup(paths: paths);
      final api = ShellxApi(baseUri: Uri.parse('https://relay.invalid'));
      final runtime = CoreAgentRuntime(
        RuntimeParams(
          credentials: const AgentCredentials(
            token: 't',
            deviceId: '22222222-2222-4222-8222-222222222222',
            userId: '11111111-1111-4111-8111-111111111111',
            email: 'e2e@example.com',
          ),
          identity: await NoiseKeyPair.generate(),
          trusted: TrustedStore(InMemoryKeyValueStore()),
          api: api,
        ),
        core: SessionCore(
          ptyFactory: _NoPty(),
          shellResolver: PlatformShellResolver(
            operatingSystem: 'macos',
            environment: {'HOME': home},
          ),
          homeDirectory: home,
          baseEnvironment: {'HOME': home},
          api: api,
        ),
        relayBaseUri: Uri.parse('https://relay.invalid'),
        appVersion: '1.0.0',
        termEndpointPath: termEndpointPath(
          environment: {'HOME': home},
          windows: false,
        ),
        connector: (uri, headers) async => _SilentRelaySocket(),
      );
      Process? window;
      try {
        await runtime.start();
        // What AgentController.enableTerminalSharing does.
        final plan = await setup.prepare();
        expect(plan.files.map((f) => f.path), [zshrc.path]);
        await setup.enable(plan);
        await runtime.setTerminalSharing(true);
        expect(
          zshrc.readAsStringSync(),
          '${zshBlock}export SHELLX_E2E_MARK=1\n',
        );
        expect(File(paths.binary).existsSync(), isTrue);

        // A new terminal window: an interactive login zsh on a fresh PTY.
        window = await Process.start(
          '/usr/bin/script',
          ['-q', '/dev/null', '/bin/zsh', '-il'],
          environment: {
            'HOME': home,
            'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
            'TERM': 'xterm-256color',
            'SHELL': '/bin/zsh',
            'TERM_PROGRAM': 'Apple_Terminal',
            'LANG': 'en_US.UTF-8',
          },
          includeParentEnvironment: false,
        );
        final output = StringBuffer();
        window.stdout.transform(utf8.decoder).listen(output.write);
        window.stderr.transform(utf8.decoder).listen(output.write);

        for (var i = 0; i < 100 && runtime.desktopSessions.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(runtime.desktopSessions, hasLength(1), reason: '$output');
        final session = runtime.desktopSessions.single;
        expect(session.app, 'Terminal');
        expect(session.shell, 'zsh');
        expect(session.connected, isTrue);

        // The user's .zshrc still ran inside the wrapped shell.
        window.stdin.write(
          r'echo "mark=$SHELLX_E2E_MARK wrapped=${SHELLX_TERM:+yes}"'
          '\n',
        );
        for (
          var i = 0;
          i < 50 && !output.toString().contains('mark=1 wrapped=yes');
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(output.toString(), contains('mark=1 wrapped=yes'));

        // Closing paths of the app never end the terminal.
        runtime.shellSessions.closeAll();
        runtime.shellSessions.closeSession(session.id);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(runtime.desktopSessions.single.connected, isTrue);

        // The window exits: the session goes.
        window.stdin.write('exit 3\n');
        expect(await window.exitCode.timeout(const Duration(seconds: 10)), 3);
        window = null;
        for (var i = 0; i < 100 && runtime.desktopSessions.isNotEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(runtime.desktopSessions, isEmpty);

        // Switch off: blocks out, server stopped, bin gone.
        final result = await setup.disable(
          stopServer: () => runtime.setTerminalSharing(false),
        );
        expect(result.complete, isTrue);
        expect(zshrc.readAsStringSync(), 'export SHELLX_E2E_MARK=1\n');
        expect(Directory(paths.binDir).existsSync(), isFalse);
        expect(
          File(
            termEndpointPath(environment: {'HOME': home}, windows: false),
          ).existsSync(),
          isFalse,
        );
      } finally {
        window?.kill(ProcessSignal.sigkill);
        await runtime.stop();
        root.deleteSync(recursive: true);
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 1)),
  );
}

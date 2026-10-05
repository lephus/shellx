@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/fake_pty.dart' show FixedShellResolver;
import '../support/session_rig.dart' show outputText;

const phone = 'b0000000-0000-4000-8000-000000000002';

/// A real shell (no tty, interactive) started by SessionManager with the
/// hook, and notifications going to a fake relay.
void main() {
  for (final shell in const [
    ShellCommand(executable: '/bin/zsh', arguments: ['-i'], name: 'zsh'),
    ShellCommand(executable: '/bin/bash', arguments: ['-i'], name: 'bash'),
  ]) {
    // The agent times a command from the arrival of 133;C to the arrival of
    // 133;D. Under a loaded parallel test run the agent's event loop can be
    // starved for a moment and read both in one chunk, so the command runs
    // long enough (3 s) for that never to hide it, and the duration is checked
    // as a range. That the hook really emits C before the command runs (not
    // buffered behind its output) is checked on the bytes: C comes before the
    // output of an external program that runs first.
    test('${shell.name}: `/bin/echo before; sleep 3; false` over a zero '
        'threshold sends "✗ … · exit 1 · <n> s" with n >= 1; C precedes the '
        'command\'s output', () async {
      final temp = Directory.systemTemp.createTempSync('shellx-hook-e2e-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final home = Directory('${temp.path}/home')..createSync();
      final bodies = <Map<String, dynamic>>[];
      final api = ShellxApi(
        baseUri: Uri.parse('https://relay.test'),
        httpClient: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{"sent":1}', 202);
        }),
      )..token = 'agent';
      final manager = SessionManager(
        ptyFactory: const ProcessPtyFactory(),
        shellResolver: FixedShellResolver(shell),
        homeDirectory: home.path,
        baseEnvironment: {
          'HOME': home.path,
          'PATH': '/usr/bin:/bin',
          'BASH_SILENCE_DEPRECATION_WARNING': '1',
        },
        shellIntegration: ShellIntegration(directory: '${temp.path}/hooks'),
        notifications: AgentNotifications(
          NotificationsConfig(
            api: api,
            threshold: () => Duration.zero,
            machineName: () => 'MacBook',
            locale: () => 'en_US',
          ),
        ),
      );
      addTearDown(manager.closeAll);
      final sent = <AppMessage>[];
      manager.outbound.listen((o) => sent.add(o.message));
      final opened = manager.outbound
          .map((o) => o.message)
          .where((m) => m is SessionOpened)
          .cast<SessionOpened>()
          .first;
      await manager.handle(phone, const SessionOpen(cols: 80, rows: 24));
      final id = (await opened).id;
      await manager.handle(
        phone,
        InputMessage(
          id: id,
          data: Uint8List.fromList(
            utf8.encode('/bin/echo before; sleep 3; false\n'),
          ),
        ),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (bodies.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(bodies, isNotEmpty, reason: 'no notification');
      expect(bodies.first['title'], 'MacBook · Session 1');
      final body = bodies.first['body'] as String;
      final match = RegExp(
        r'^✗ /bin/echo before; sleep 3; false · exit 1 · (\d+) s$',
      ).firstMatch(body);
      expect(match, isNotNull, reason: body);
      expect(int.parse(match!.group(1)!), inInclusiveRange(1, 10));
      final output = outputText(sent, id);
      final start = output.indexOf('\x1b]133;C\x07');
      final before = output.indexOf('before', start < 0 ? 0 : start);
      expect(start, isNonNegative, reason: 'no 133;C');
      expect(before, greaterThan(start), reason: 'C after the output');
      expect(
        output.lastIndexOf('\x1b]133;D;1\x07'),
        greaterThan(before),
        reason: 'D before the output',
      );
      expect(bodies.first['data'], {'session_id': '$id', 'kind': 'command'});
    }, skip: File(shell.executable).existsSync() ? null : 'no ${shell.name}');
  }
}

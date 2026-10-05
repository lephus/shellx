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

const phone = 'b0000000-0000-4000-8000-000000000002';

/// A real shell (no tty, interactive) started by SessionManager with the
/// hook, and notifications going to a fake relay.
void main() {
  for (final shell in const [
    ShellCommand(executable: '/bin/zsh', arguments: ['-i'], name: 'zsh'),
    ShellCommand(executable: '/bin/bash', arguments: ['-i'], name: 'bash'),
  ]) {
    test('${shell.name}: `sleep 1; false` over a zero threshold sends '
        '"✗ sleep 1; false · exit 1 · 1 s"', () async {
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
          data: Uint8List.fromList(utf8.encode('sleep 1; false\n')),
        ),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (bodies.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(bodies, isNotEmpty, reason: 'no notification');
      expect(bodies.first['title'], 'MacBook · Session 1');
      expect(bodies.first['body'], '✗ sleep 1; false · exit 1 · 1 s');
      expect(bodies.first['data'], {'session_id': '$id', 'kind': 'command'});
    }, skip: File(shell.executable).existsSync() ? null : 'no ${shell.name}');
  }
}

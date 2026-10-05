@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

import '../support/fake_term.dart';

void main() {
  test('start/stop: enabled, endpoint, sessions cleared, port closed', () async {
    final home = await Directory.systemTemp.createTemp('sharing-');
    addTearDown(() => home.delete(recursive: true));
    final path = '${home.path}/term/endpoint';
    var next = 1;
    final sessions = DesktopSessionManager(nextId: () => next++);
    final sharing = TerminalSharing(endpointPath: path, sessions: sessions);
    expect(sharing.enabled, isFalse);
    await sharing.start();
    expect(sharing.enabled, isTrue);

    final (port, secret) = readEndpoint(path);
    final term = await FakeTerm.connect(port);
    expect(await term.handshake(secret), isA<AgentReady>());
    await pumpEventQueue();
    expect(sessions.sessions, hasLength(1));

    await sharing.stop();
    expect(sharing.enabled, isFalse);
    expect(sessions.sessions, isEmpty);
    expect(File(path).existsSync(), isFalse);
    await term.closed.timeout(const Duration(seconds: 2));
  });
}

@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

import '../support/fake_term.dart';

void main() {
  test(
    'start/stop: enabled, endpoint, sessions cleared, port closed',
    () async {
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
    },
  );

  test(
    'stop while start is in flight leaves sharing off and no endpoint file',
    () async {
      final home = await Directory.systemTemp.createTemp('sharing-');
      addTearDown(() => home.delete(recursive: true));
      final path = '${home.path}/term/endpoint';
      var next = 1;
      final sessions = DesktopSessionManager(nextId: () => next++);
      final sharing = TerminalSharing(endpointPath: path, sessions: sessions);
      addTearDown(sharing.stop);

      final starting = sharing.start();
      final stopping = sharing.stop();
      await starting;
      await stopping;

      expect(sharing.enabled, isFalse);
      expect(File(path).existsSync(), isFalse);
    },
  );

  test('two concurrent starts bind one server', () async {
    final home = await Directory.systemTemp.createTemp('sharing-');
    addTearDown(() => home.delete(recursive: true));
    final path = '${home.path}/term/endpoint';
    var next = 1;
    final sessions = DesktopSessionManager(nextId: () => next++);
    final sharing = TerminalSharing(endpointPath: path, sessions: sessions);
    addTearDown(sharing.stop);

    final ports = <int>{};
    await Future.wait([
      sharing.start().then((_) => ports.add(readEndpoint(path).$1)),
      sharing.start().then((_) => ports.add(readEndpoint(path).$1)),
    ]);
    expect(sharing.enabled, isTrue);
    expect(ports, hasLength(1));

    await sharing.stop();
    expect(File(path).existsSync(), isFalse);
    // Nothing is left listening on any port either start published.
    for (final port in ports) {
      await expectLater(
        Socket.connect(InternetAddress.loopbackIPv4, port),
        throwsA(isA<SocketException>()),
      );
    }
  });
}

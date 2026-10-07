import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/mux/daemon_host.dart';

import '../support/fake_local_sessions.dart';
import 'mux_test_support.dart';

void main() {
  late Directory directory;
  late MuxEndpointFile endpoint;
  late FakeLocalSessions sessions;
  late TestListener listener;
  late DaemonHost host;
  late MuxServer server;
  late MuxEndpointInfo info;
  var sessionCount = 0;
  var phones = false;
  var shutdowns = 0;
  var shutdownTime = Duration.zero;
  final exits = <int>[];

  DaemonHost build({
    Duration idle = const Duration(seconds: 10),
    Duration shutdownTimeout = const Duration(seconds: 10),
  }) {
    final identity = newDaemonIdentity();
    info = MuxEndpointInfo(
      address: 'test',
      secret: identity.secret,
      pid: 4242,
      instance: identity.instance,
      protocol: kMuxProtocol,
      app: '1.6.0',
    );
    server = MuxServer(
      sessions: sessions,
      secret: info.secret,
      self: MuxPeerInfo(
        protocol: kMuxProtocol,
        app: '1.6.0',
        instance: info.instance,
        pid: 4242,
      ),
      onQuit: () => host.quit(),
      onUiChanged: (a) => host.onUiChanged(a),
    );
    host = DaemonHost(
      server: server,
      endpoint: endpoint,
      info: info,
      hasSessions: () => sessionCount > 0,
      servingPhones: () => phones,
      shutdown: () async {
        shutdowns++;
        await Future<void>.delayed(shutdownTime);
      },
      exit: exits.add,
      idle: idle,
      shutdownTimeout: shutdownTimeout,
      log: (_) {},
    );
    return host;
  }

  setUp(() {
    directory = Directory.systemTemp.createTempSync('daemon_host');
    endpoint = MuxEndpointFile('${directory.path}/endpoint');
    sessions = FakeLocalSessions();
    listener = TestListener();
    sessionCount = 0;
    phones = false;
    shutdowns = 0;
    shutdownTime = Duration.zero;
    exits.clear();
  });
  tearDown(() => directory.deleteSync(recursive: true));

  group('idle exit (D27)', () {
    test('exits after 10 s with no UI, no sessions, no phones', () {
      fakeAsync((async) {
        build();
        host.onStateChanged();
        async.elapse(const Duration(seconds: 9, milliseconds: 900));
        expect(shutdowns, 0);
        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();
        expect(shutdowns, 1);
      });
    });

    for (final (label, set) in <(String, void Function())>[
      ('a session', () => sessionCount = 1),
      ('a phone being served', () => phones = true),
    ]) {
      test('$label keeps it running', () {
        fakeAsync((async) {
          build();
          set();
          host.onStateChanged();
          async.elapse(const Duration(minutes: 5));
          expect(shutdowns, 0);
          expect(exits, isEmpty);
        });
      });
    }

    test('a session that ends re-arms the exit', () {
      fakeAsync((async) {
        build();
        sessionCount = 1;
        host.onStateChanged();
        async.elapse(const Duration(minutes: 1));
        sessionCount = 0;
        host.onStateChanged();
        async.elapse(const Duration(seconds: 11));
        async.flushMicrotasks();
        expect(shutdowns, 1);
      });
    });

    test('a state that changed without a notice cancels the exit at 10 s', () {
      fakeAsync((async) {
        build();
        host.onStateChanged();
        async.elapse(const Duration(seconds: 5));
        // e.g. a cli client connected: no event reaches the host.
        sessionCount = 1;
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();
        expect(shutdowns, 0);
      });
    });

    test('a UI attaching within 10 s cancels; leaving re-arms', () async {
      final h = build(idle: const Duration(milliseconds: 200));
      await h.start(listener);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final ui = await attachClient(listener, secret: info.secret);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(shutdowns, 0, reason: 'a UI is attached');
      await ui.close();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(shutdowns, 0);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(shutdowns, 1);
      expect(exits, [0]);
    });
  });

  group('start and quit', () {
    test('start writes an endpoint with a fresh secret and instance', () async {
      final first = build();
      await first.start(listener);
      final a = (await endpoint.read())!;
      expect(a.secret, hasLength(32));
      expect(a.instance, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(a.pid, 4242);
      expect(a.protocol, kMuxProtocol);
      await first.quit();

      final second = build();
      await second.start(listener);
      final b = (await endpoint.read())!;
      expect(b.secret, isNot(a.secret));
      expect(b.instance, isNot(a.instance));
      await second.quit();
    });

    test('a client with the file\'s secret gets in, others do not', () async {
      final h = build();
      await h.start(listener);
      final e = (await endpoint.read())!;
      final ui = await attachClient(listener, secret: e.secret);
      expect(server.uiAttached, isTrue);
      await ui.close();
      final (c, s) = MemoryMuxTransport.pair();
      listener.push(s);
      await expectLater(
        clientHandshake(c, secret: testSecret, app: '1.6.0', role: 'ui'),
        throwsA(isA<MuxHandshakeException>()),
      );
      await h.quit();
    });

    test('quit: shutdown, endpoint deleted, exit(0), once', () async {
      final h = build();
      await h.start(listener);
      expect(File(endpoint.path).existsSync(), isTrue);
      await Future.wait([h.quit(), h.quit()]);
      await h.quit();
      expect(shutdowns, 1);
      expect(File(endpoint.path).existsSync(), isFalse);
      expect(exits, [0]);
    });

    test('daemon.quit over the wire runs it', () async {
      final h = build();
      await h.start(listener);
      final ui = await attachClient(listener, secret: info.secret);
      // The daemon closes the link as it quits: the caller sees the
      // connection end (the reply may not get out first).
      await ui.request(MuxType.daemonQuit).then<void>((_) {}, onError: (_) {});
      await ui.done;
      expect(shutdowns, 1);
      expect(exits, [0]);
      await h.quit();
    });

    test('a newer daemon\'s endpoint is not deleted', () async {
      final h = build();
      await h.start(listener);
      final other = MuxEndpointInfo(
        address: 'other',
        secret: info.secret,
        pid: 1,
        instance: 'f' * 32,
        protocol: kMuxProtocol,
        app: '1.6.0',
      );
      await endpoint.write(other);
      await h.quit();
      expect((await endpoint.read())!.address, 'other');
    });

    test('a shutdown that hangs is cut at its bound, then exits', () async {
      shutdownTime = const Duration(seconds: 30);
      final h = build(shutdownTimeout: const Duration(milliseconds: 100));
      await h.start(listener);
      final watch = Stopwatch()..start();
      await h.quit();
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(exits, [0]);
      expect(File(endpoint.path).existsSync(), isFalse);
    });
  });
}

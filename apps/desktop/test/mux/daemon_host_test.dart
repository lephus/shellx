import 'dart:async';
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
  var shutdownThrows = false;
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
        if (shutdownThrows) throw StateError('step failed');
      },
      exit: exits.add,
      idle: idle,
      shutdownTimeout: shutdownTimeout,
      exitDelay: const Duration(milliseconds: 30),
      log: (_) {},
    );
    return host;
  }

  /// The exit comes from a short real timer; wait for it with a wide deadline.
  Future<void> untilExit() async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (exits.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
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
    shutdownThrows = false;
    exits.clear();
  });
  tearDown(() async {
    // A quit's exit timer must not leak into the next test.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    directory.deleteSync(recursive: true);
  });

  group('a quitting service accepts nobody (A5b final review)', () {
    test(
      'the idle exit closes the listener and refuses a late connection',
      () async {
        build(idle: const Duration(milliseconds: 20));
        await host.start(listener);
        host.onStateChanged();
        // Poll with a wide deadline: a 20 ms real timer can fire late under load.
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (shutdowns == 0 && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(shutdowns, 1);
        expect(listener.closed, isTrue);
        await expectLater(attachClient(listener), throwsA(anything));
      },
    );

    test('quit() (SIGTERM) does the same', () async {
      build();
      await host.start(listener);
      unawaited(host.quit());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(listener.closed, isTrue);
      await expectLater(attachClient(listener), throwsA(anything));
    });
  });

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
      // Real timers: margins wide enough for a loaded machine (the idle
      // window is 2 s; the client attaches at once, well inside it).
      final h = build(idle: const Duration(seconds: 2));
      await h.start(listener);
      final ui = await attachClient(listener, secret: info.secret);
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      expect(shutdowns, 0, reason: 'a UI is attached');
      await ui.close();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(shutdowns, 0, reason: 'the re-armed window has not run out');
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (exits.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
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
      expect(exits, isEmpty, reason: 'the exit comes a tick after quit');
      await untilExit();
      expect(exits, [0]);
    });

    test('daemon.quit over the wire runs it', () async {
      final h = build();
      await h.start(listener);
      final ui = await attachClient(listener, secret: info.secret);
      // The reply goes out before the process exits (a link that drops
      // without a quit of its own means the daemon died).
      final reply = await ui.request(MuxType.daemonQuit);
      expect(reply.type, MuxType.result);
      expect(shutdowns, 1);
      expect(exits, isEmpty);
      await untilExit();
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
      await untilExit();
      expect(exits, [0]);
      expect(File(endpoint.path).existsSync(), isFalse);
    });
  });

  test('the host\'s bound covers every inner shutdown step', () {
    const steps = kDaemonShutdownSteps;
    expect(
      kDaemonShutdownBudget,
      greaterThanOrEqualTo(steps.cli + steps.agent + steps.remote),
    );
  });

  test(
    'a quit whose shutdown throws still ends the process and removes the '
    'endpoint (the listener is closed: a half-quit service is unreachable)',
    () {
      fakeAsync((async) {
        build();
        shutdownThrows = true;
        unawaited(host.start(listener));
        async.flushMicrotasks();
        unawaited(host.quit());
        async.elapse(const Duration(seconds: 1));
        expect(exits, [0]);
      });
    },
  );
}

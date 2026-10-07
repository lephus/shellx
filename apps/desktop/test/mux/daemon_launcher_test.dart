import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_desktop/src/mux/daemon_launcher.dart';

import 'mux_test_support.dart';

/// A fake daemon on a fake clock: [connect] reaches it only while [up] (and
/// after [upAfterAttempts] attempts), it proves [secret], reports
/// [protocol] and [sessions], and ends on `daemon.quit`.
final class FakeDaemonTransport implements MuxTransport {
  FakeDaemonTransport({
    required this.clock,
    this.protocol = kMuxProtocol,
    this.sessions = 0,
  });

  final FakeClock clock;
  bool up = false;
  int protocol;
  int? sessions;
  Uint8List secret = testSecret;
  int attempts = 0;
  int upAfterAttempts = 0;

  /// Every message type that arrived on a connection, in order.
  final received = <String>[];
  int quits = 0;

  /// Refuses `daemon.quit` (a daemon that will not go away).
  bool ignoreQuit = false;

  @override
  Future<MuxListener> listen(String address) => throw UnimplementedError();

  @override
  Future<MuxConnection> connect(
    String address, {
    Duration timeout = const Duration(seconds: 1),
  }) async {
    attempts++;
    if (!up || attempts <= upAfterAttempts) {
      throw const SocketException('refused');
    }
    final (client, server) = MemoryMuxTransport.pair();
    unawaited(_serve(server));
    return client;
  }

  Future<void> _serve(MuxConnection c) async {
    var authed = false;
    final tap = c.messages.listen((m) {
      received.add(m.type);
      if (authed && m.type == MuxType.daemonQuit && !ignoreQuit) {
        quits++;
        up = false;
        unawaited(c.close());
      }
    });
    try {
      await serverHandshake(
        c,
        secret: secret,
        self: MuxPeerInfo(
          protocol: protocol,
          app: '1.5.0',
          instance: 'a' * 32,
          pid: 7,
          sessions: sessions,
        ),
      );
    } on Object {
      await tap.cancel();
      return;
    }
    authed = true;
  }
}

final class FakeClock {
  var now = DateTime(2026, 10, 7, 9);
  Future<void> sleep(Duration d) async => now = now.add(d);
}

void main() {
  late Directory directory;
  late MuxEndpointFile endpoint;
  late FakeClock clock;
  late FakeDaemonTransport transport;
  var lockFree = true;
  var spawns = 0;
  FutureOr<void> Function() onSpawn = () async {};

  Future<void> writeEndpoint({Uint8List? secret}) => endpoint.write(
    MuxEndpointInfo(
      address: 'test',
      secret: secret ?? testSecret,
      pid: 7,
      instance: 'a' * 32,
      protocol: kMuxProtocol,
      app: '1.5.0',
    ),
  );

  DaemonLauncher launcher() => DaemonLauncher(
    transport: transport,
    endpoint: endpoint,
    daemonLockFree: () async => lockFree,
    spawn: () async {
      spawns++;
      await onSpawn();
    },
    appVersion: '1.6.0',
    quitWait: const Duration(milliseconds: 200),
    now: () => clock.now,
    sleep: clock.sleep,
  );

  setUp(() {
    directory = Directory.systemTemp.createTempSync('daemon_launcher');
    endpoint = MuxEndpointFile('${directory.path}/endpoint');
    clock = FakeClock();
    transport = FakeDaemonTransport(clock: clock);
    lockFree = true;
    spawns = 0;
    onSpawn = () async {};
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test(
    '1. a running daemon of this protocol: attached, nothing spawned',
    () async {
      transport.up = true;
      await endpoint.write(
        MuxEndpointInfo(
          address: 'test',
          secret: testSecret,
          pid: 7,
          instance: 'a' * 32,
          protocol: kMuxProtocol,
          app: '1.5.0',
        ),
      );
      final r = await launcher().connect();
      expect(r, isA<Attached>());
      final a = r as Attached;
      expect(a.started, isFalse);
      expect(a.info.protocol, kMuxProtocol);
      expect(spawns, 0);
    },
  );

  test(
    '2. no endpoint, lock free: spawn once, attached on the 3rd retry',
    () async {
      // The daemon writes its endpoint when it starts, answers from its 3rd
      // connection attempt on.
      onSpawn = () async {
        transport.up = true;
        transport.upAfterAttempts = 2; // attempt 1 was before the spawn
        await writeEndpoint();
      };
      // The first read finds no endpoint, so no connection is tried then.
      final r = await launcher().connect();
      expect(spawns, 1);
      expect(r, isA<Attached>());
      expect((r as Attached).started, isTrue);
      expect(transport.attempts, 3);
    },
  );

  test(
    '3. stale endpoint, lock held (a daemon starting): no spawn, retries',
    () async {
      await writeEndpoint();
      lockFree = false;
      var asked = 0;
      final l = DaemonLauncher(
        transport: transport,
        endpoint: endpoint,
        daemonLockFree: () async => lockFree,
        spawn: () async => spawns++,
        appVersion: '1.6.0',
        now: () => clock.now,
        sleep: (d) async {
          asked++;
          await clock.sleep(d);
          if (asked == 4) transport.up = true;
        },
      );
      final r = await l.connect();
      expect(spawns, 0);
      expect(r, isA<Attached>());
      expect((r as Attached).started, isFalse);
    },
  );

  group('4. a peer that does not know the secret (Review Focus 2)', () {
    test('lock free: treated as not running, a daemon is spawned', () async {
      transport
        ..up = true
        ..secret = Uint8List(32);
      await writeEndpoint();
      onSpawn = () async {
        transport.secret = testSecret;
      };
      final r = await launcher().connect();
      expect(spawns, 1);
      expect(r, isA<Attached>());
      // Only `hello` ever reached the squatter, then the next real daemon
      // got a full handshake.
      expect(transport.received.first, MuxType.hello);
    });

    test('lock held: StartFailed after 5 s, nothing but hello sent', () async {
      transport
        ..up = true
        ..secret = Uint8List(32);
      await writeEndpoint();
      lockFree = false;
      final start = clock.now;
      final r = await launcher().connect();
      expect(r, isA<StartFailed>());
      expect(spawns, 0);
      expect(
        clock.now.difference(start),
        greaterThanOrEqualTo(const Duration(seconds: 5)),
      );
      expect(
        transport.received.where((t) => t != MuxType.hello),
        isEmpty,
        reason: 'no auth, view.* or sessions.* to a peer without the secret',
      );
    });
  });

  test('5. protocol 2 with 0 sessions: quit, wait, spawn, attached', () async {
    transport
      ..up = true
      ..protocol = 2;
    await writeEndpoint();
    onSpawn = () async {
      transport
        ..protocol = kMuxProtocol
        ..up = true;
      await writeEndpoint();
    };
    final r = await launcher().connect();
    expect(transport.quits, 1);
    expect(spawns, 1);
    expect(r, isA<Attached>());
    expect((r as Attached).info.protocol, kMuxProtocol);
  });

  test(
    '6. protocol 2 with 3 sessions: Incompatible; replace = quit + spawn',
    () async {
      transport
        ..up = true
        ..protocol = 2
        ..sessions = 3;
      await writeEndpoint();
      final l = launcher();
      final r = await l.connect();
      expect(r, isA<Incompatible>());
      expect((r as Incompatible).info.sessions, 3);
      expect(transport.quits, 0);
      expect(spawns, 0);
      onSpawn = () async {
        transport
          ..protocol = kMuxProtocol
          ..sessions = 0
          ..up = true;
        await writeEndpoint();
      };
      final replaced = await l.replaceIncompatible(r);
      expect(transport.quits, 1);
      expect(spawns, 1);
      expect(replaced, isA<Attached>());
    },
  );

  test(
    'a daemon that will not quit is reported, not retried forever',
    () async {
      transport
        ..up = true
        ..protocol = 2
        ..ignoreQuit = true;
      await writeEndpoint();
      final r = await launcher().connect();
      expect(r, isA<Incompatible>());
      expect(spawns, 0);
    },
  );

  test('an unknown session count is never replaced silently', () async {
    transport
      ..up = true
      ..protocol = 2
      ..sessions = null;
    await writeEndpoint();
    final r = await launcher().connect();
    expect(r, isA<Incompatible>());
    expect(transport.quits, 0);
    expect(spawns, 0);
  });

  test('replace waits for the old daemon\'s lock before it spawns', () async {
    transport
      ..up = true
      ..protocol = 2
      ..sessions = 3;
    await writeEndpoint();
    final l = launcher();
    final old = await l.connect() as Incompatible;
    var sleeps = 0;
    final waiting = DaemonLauncher(
      transport: transport,
      endpoint: endpoint,
      daemonLockFree: () async => sleeps >= 5,
      spawn: () async {
        expect(sleeps, greaterThanOrEqualTo(5), reason: 'lock was held');
        spawns++;
        transport
          ..protocol = kMuxProtocol
          ..sessions = 0
          ..up = true;
        await writeEndpoint();
      },
      appVersion: '1.6.0',
      quitWait: const Duration(milliseconds: 200),
      now: () => clock.now,
      sleep: (d) async {
        sleeps++;
        await clock.sleep(d);
      },
    );
    final r = await waiting.replaceIncompatible(old);
    expect(r, isA<Attached>());
    expect(spawns, 1);
  });

  test('replace gives up waiting after 12 s of a held lock', () async {
    transport
      ..up = true
      ..protocol = 2
      ..sessions = 3;
    await writeEndpoint();
    final old = await launcher().connect() as Incompatible;
    final start = clock.now;
    final held = DaemonLauncher(
      transport: transport,
      endpoint: endpoint,
      daemonLockFree: () async => false,
      spawn: () async => spawns++,
      appVersion: '1.6.0',
      quitWait: const Duration(milliseconds: 200),
      now: () => clock.now,
      sleep: clock.sleep,
    );
    final r = await held.replaceIncompatible(old);
    expect(r, isA<StartFailed>());
    expect(
      clock.now.difference(start),
      greaterThanOrEqualTo(const Duration(seconds: 17)),
    );
  });

  test('7. nothing ever answers: StartFailed after 5 s', () async {
    final start = clock.now;
    final r = await launcher().connect();
    expect(r, isA<StartFailed>());
    expect(spawns, 1);
    expect(clock.now.difference(start), const Duration(seconds: 5));
  });

  test('8. findRunning never spawns: none running is null', () async {
    final r = await launcher().findRunning();
    expect(r, isNull);
    expect(spawns, 0);
    expect(transport.attempts, 0); // no endpoint, nothing to try
  });

  test(
    '9. findRunning attaches to a running daemon, replaces nothing',
    () async {
      transport
        ..up = true
        ..protocol = kMuxProtocol + 1
        ..sessions = 0;
      await writeEndpoint();
      final r = await launcher().findRunning();
      // Another protocol is reported as is (the caller decides), never
      // replaced here.
      expect(r, isA<Incompatible>());
      expect(transport.quits, 0);
    },
  );

  test(
    '10. the UI\'s request handler is the client\'s (ui.* from the daemon)',
    () async {
      transport.up = true;
      await writeEndpoint();
      Future<Map<String, Object?>> handler(MuxMessage m) async => {};
      final withHandler = DaemonLauncher(
        transport: transport,
        endpoint: endpoint,
        daemonLockFree: () async => lockFree,
        spawn: () async => spawns++,
        appVersion: '1.6.0',
        onRequest: handler,
        now: () => clock.now,
        sleep: clock.sleep,
      );
      final r = await withHandler.connect() as Attached;
      expect(r.client.onRequest, same(handler));
    },
  );

  test(
    '11. the probe client answers no requests (it is not the window)',
    () async {
      transport.up = true;
      await writeEndpoint();
      Future<Map<String, Object?>> handler(MuxMessage m) async => {};
      final probing = DaemonLauncher(
        transport: transport,
        endpoint: endpoint,
        daemonLockFree: () async => lockFree,
        spawn: () async => spawns++,
        appVersion: '1.6.0',
        onRequest: handler,
        now: () => clock.now,
        sleep: clock.sleep,
      );
      final r = await probing.findRunning() as Attached;
      expect(r.client.onRequest, isNull);
    },
  );
}

import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

final secret = Uint8List.fromList(List.generate(32, (i) => i));
const self = MuxPeerInfo(
  protocol: 1,
  app: '1.6.0',
  instance: 'i1',
  pid: 42,
  sessions: 3,
  caps: ['x'],
);

void main() {
  test('both sides prove the secret; info exchanged', () async {
    final (a, b) = MemoryMuxTransport.pair();
    final server = serverHandshake(b, secret: secret, self: self);
    final client = await clientHandshake(
      a,
      secret: secret,
      app: '1.6.1',
      role: 'ui',
    );
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

  test(
    'a squatter that cannot prove the secret gets no auth from the client',
    () async {
      final (a, b) = MemoryMuxTransport.pair();
      final sent = <MuxMessage>[];
      b.messages.listen((m) {
        sent.add(m);
        if (m.type == MuxType.hello) {
          b.send(
            MuxMessage(
              MuxType.hello,
              fields: {
                'protocol': 1,
                'app': 'evil',
                'nonce': Uint8List(32),
                'proof': Uint8List(32),
              },
            ),
          );
        }
      });
      await expectLater(
        clientHandshake(a, secret: secret, app: '1', role: 'ui'),
        throwsA(isA<MuxHandshakeException>()),
      );
      expect(sent.map((m) => m.type), [MuxType.hello]); // never `auth`
    },
  );

  test('silence → timeout after 2 s', () {
    fakeAsync((async) {
      final (a, _) = MemoryMuxTransport.pair();
      Object? error;
      clientHandshake(a, secret: secret, app: '1', role: 'ui').catchError((
        Object e,
      ) {
        error = e;
        return self;
      });
      async.elapse(const Duration(milliseconds: 1999));
      expect(error, isNull);
      async.elapse(const Duration(milliseconds: 2));
      expect(error, isA<MuxHandshakeException>());
    });
  });

  group('optional auth.token (A7 amendment, A5b D7 additive)', () {
    test('travels in auth only; the host returns it', () async {
      final (a, b) = MemoryMuxTransport.pair();
      final seen = <MuxMessage>[];
      b.messages.listen(seen.add);
      final server = serverHandshake(b, secret: secret, self: self);
      await clientHandshake(
        a,
        secret: secret,
        app: '1',
        role: 'cli',
        token: 'tok-1',
      );
      final peer = await server;
      expect(peer.token, 'tok-1');
      expect(peer.role, 'cli');
      final hello = seen.firstWhere((m) => m.type == MuxType.hello);
      final auth = seen.firstWhere((m) => m.type == MuxType.auth);
      expect(hello.fields.containsKey('token'), isFalse);
      expect(auth.get<String>('token'), 'tok-1');
    });

    test('absent → null, and no key on the wire', () async {
      final (a, b) = MemoryMuxTransport.pair();
      final seen = <MuxMessage>[];
      b.messages.listen(seen.add);
      final server = serverHandshake(b, secret: secret, self: self);
      await clientHandshake(a, secret: secret, app: '1', role: 'cli');
      expect((await server).token, isNull);
      final auth = seen.firstWhere((m) => m.type == MuxType.auth);
      expect(auth.fields.containsKey('token'), isFalse);
    });

    test('a squatter never sees the token', () async {
      final (a, b) = MemoryMuxTransport.pair();
      final sent = <MuxMessage>[];
      b.messages.listen((m) {
        sent.add(m);
        if (m.type == MuxType.hello) {
          b.send(
            MuxMessage(
              MuxType.hello,
              fields: {
                'protocol': 1,
                'app': 'evil',
                'nonce': Uint8List(32),
                'proof': Uint8List(32),
              },
            ),
          );
        }
      });
      await expectLater(
        clientHandshake(a, secret: secret, app: '1', role: 'cli', token: 't'),
        throwsA(isA<MuxHandshakeException>()),
      );
      expect(sent.map((m) => m.type), [MuxType.hello]);
      expect(sent.any((m) => m.fields.containsKey('token')), isFalse);
    });
  });

  group('hostile peers (A7 Task 2 review)', () {
    Uint8List nonce(int n, int seed) =>
        Uint8List.fromList(List.generate(n, (i) => seed + i));

    Future<(_Manual, Future<MuxPeerInfo>, MuxMessage)> serverAfterHello({
      int nonceLength = 32,
    }) async {
      final m = _Manual();
      final server = serverHandshake(m.conn, secret: secret, self: self);
      // Handled later by the test; not an uncaught error meanwhile.
      server.ignore();
      m.feed([_hello(nonce(nonceLength, 1))]);
      await pumpEventQueue();
      return (m, server, m.out.isEmpty ? _none : m.out.single);
    }

    Future<void> expectRefused(
      Future<MuxPeerInfo> handshake,
      String reason,
      _Manual m,
    ) async {
      await expectLater(
        handshake,
        throwsA(
          isA<MuxHandshakeException>().having(
            (e) => e.reason,
            'reason',
            reason,
          ),
        ),
      );
      await m.conn.done.timeout(const Duration(seconds: 1));
    }

    test('a wrong client proof → refused, closed, no ready', () async {
      final (m, server, _) = await serverAfterHello();
      m.feed([
        MuxMessage(MuxType.auth, fields: {'proof': Uint8List(32)}),
      ]);
      await expectRefused(server, 'client proof', m);
      expect(m.out.map((x) => x.type), [MuxType.hello]);
    });

    test(
      'the daemon proof reflected back as the client proof → refused',
      () async {
        final (m, server, hello) = await serverAfterHello();
        m.feed([
          MuxMessage(
            MuxType.auth,
            fields: {'proof': hello.get<Uint8List>('proof')},
          ),
        ]);
        await expectRefused(server, 'client proof', m);
        expect(m.out.map((x) => x.type), [MuxType.hello]);
      },
    );

    test(
      'a 16-byte client nonce → refused before the host proves anything',
      () async {
        final (m, server, _) = await serverAfterHello(nonceLength: 16);
        await expectRefused(server, 'client nonce', m);
        expect(m.out, isEmpty);
      },
    );

    test('a 16-byte daemon nonce (even with a matching proof) → refused, '
        'no auth sent', () async {
      final m = _Manual();
      final client = clientHandshake(
        m.conn,
        secret: secret,
        app: '1',
        role: 'cli',
        token: 't',
      );
      await pumpEventQueue();
      final nc = m.out.single.get<Uint8List>('nonce')!;
      final nd = nonce(16, 0x80);
      m.feed([_daemonHello(nc, nd)]);
      await expectRefused(client, 'daemon nonce', m);
      expect(m.out.map((x) => x.type), [MuxType.hello]);
    });

    test('a request in the same read as auth is not lost (server)', () async {
      final (m, server, hello) = await serverAfterHello();
      final nd = hello.get<Uint8List>('nonce')!;
      m.feed([
        MuxMessage(
          MuxType.auth,
          fields: {'proof': clientProof(secret, nd, nonce(32, 1))},
        ),
        const MuxMessage(MuxType.daemonStatus, q: 1),
      ]);
      final peer = await server;
      expect(peer.early.map((x) => (x.type, x.q)), [(MuxType.daemonStatus, 1)]);
    });

    test('a push in the same read as ready is not lost (client)', () async {
      final m = _Manual();
      final client = clientHandshake(
        m.conn,
        secret: secret,
        app: '1',
        role: 'ui',
      );
      await pumpEventQueue();
      final nc = m.out.single.get<Uint8List>('nonce')!;
      m.feed([_daemonHello(nc, nonce(32, 0x80))]);
      await pumpEventQueue();
      expect(m.out.last.type, MuxType.auth);
      m.feed([
        const MuxMessage(MuxType.ready),
        const MuxMessage(MuxType.sessionsChanged, fields: {'n': 1}),
      ]);
      final peer = await client;
      expect(peer.early.map((x) => x.type), [MuxType.sessionsChanged]);
    });

    test('one 2 s deadline for the whole handshake (D6)', () {
      fakeAsync((async) {
        final m = _Manual();
        Object? error;
        clientHandshake(
          m.conn,
          secret: secret,
          app: '1',
          role: 'ui',
        ).then<void>((_) {}, onError: (Object e) => error = e);
        async.flushMicrotasks();
        final nc = m.out.single.get<Uint8List>('nonce')!;
        async.elapse(const Duration(milliseconds: 1500));
        m.feed([_daemonHello(nc, nonce(32, 0x80))]); // valid, but late
        async.elapse(const Duration(milliseconds: 499));
        expect(error, isNull);
        expect(m.out.last.type, MuxType.auth);
        async.elapse(const Duration(milliseconds: 2));
        expect(
          error,
          isA<MuxHandshakeException>().having((e) => e.reason, 'r', 'timeout'),
        );
      });
    });
  });
}

const _none = MuxMessage('none');

MuxMessage _hello(Uint8List nonce) => MuxMessage(
  MuxType.hello,
  fields: {'protocol': 1, 'app': '1', 'role': 'cli', 'nonce': nonce},
);

MuxMessage _daemonHello(Uint8List nonceClient, Uint8List nonceDaemon) =>
    MuxMessage(
      MuxType.hello,
      fields: {
        'protocol': 1,
        'app': '1.6.0',
        'nonce': nonceDaemon,
        'proof': daemonProof(secret, nonceClient, nonceDaemon),
      },
    );

/// A connection whose peer is the test: [out] holds what it sent, [feed]
/// delivers messages to it in one read.
final class _Manual {
  _Manual() {
    conn = StreamMuxConnection(
      input.stream,
      (bytes) => out.addAll(_decoder.add(bytes)),
      () async {},
    );
  }

  final input = StreamController<Uint8List>();
  final out = <MuxMessage>[];
  final _decoder = MuxFrameDecoder();
  late final StreamMuxConnection conn;

  void feed(List<MuxMessage> messages) =>
      input.add(concatBytes([for (final m in messages) encodeMux(m)]));
}

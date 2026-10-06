import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:shellx_agent/shellx_agent.dart';
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
}

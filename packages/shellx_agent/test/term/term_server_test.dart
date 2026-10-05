@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:test/test.dart';

import '../support/fake_term.dart';

void main() {
  late Directory home;
  late String path;
  late TermServer server;
  late List<TermLink> links;
  late bool admitAll;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('term-server-');
    path = '${home.path}/term/endpoint';
    links = [];
    admitAll = true;
    server = TermServer(
      endpointPath: path,
      admit: (_) => admitAll,
      onLink: links.add,
      handshakeTimeout: const Duration(milliseconds: 300),
    );
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    await home.delete(recursive: true);
  });

  test(
    'start writes the endpoint; stop removes it and closes the port',
    () async {
      expect(server.running, isTrue);
      final (port, _) = readEndpoint(path);
      expect(port, server.port);
      await server.stop();
      expect(server.running, isFalse);
      expect(File(path).existsSync(), isFalse);
      await expectLater(
        Socket.connect(InternetAddress.loopbackIPv4, port),
        throwsA(isA<SocketException>()),
      );
    },
  );

  test('a correct handshake gets ready and hands over a link', () async {
    final (port, secret) = readEndpoint(path);
    final term = await FakeTerm.connect(port);
    final nonce = Uint8List.fromList(List.generate(32, (i) => i + 1));
    term.send(TermHello(v: 1, nonce: nonce));
    final challenge = await term.next() as AgentChallenge;
    expect(
      challenge.mac,
      agentProof(secret, nonce, challenge.nonce),
      reason: 'the agent proves it knows the secret',
    );
    term.send(
      TermAuth(
        mac: termProof(secret, challenge.nonce, nonce),
        info: termInfo(app: 'iTerm2'),
      ),
    );
    expect(await term.next(), isA<AgentReady>());
    await pumpEventQueue();
    expect(links.single.info.app, 'iTerm2');

    final got = <TermToAgent>[];
    links.single.messages.listen(got.add);
    term.send(TermSnapshot(data: Uint8List.fromList([65]), last: true));
    links.single.send(AgentIn(data: Uint8List.fromList([66])));
    expect(await term.next(), isA<AgentIn>());
    await pumpEventQueue();
    expect(got.single, isA<TermSnapshot>());
    term.destroy();
  });

  test('a link outlives the handshake deadline', () async {
    final (port, secret) = readEndpoint(path);
    final term = await FakeTerm.connect(port);
    expect(await term.handshake(secret), isA<AgentReady>());
    await pumpEventQueue();
    // Twice the 300 ms handshake deadline: the deadline must not touch a
    // link that finished its handshake.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    var closed = false;
    unawaited(term.closed.then((_) => closed = true));
    await pumpEventQueue();
    expect(closed, isFalse);
    links.single.send(AgentIn(data: Uint8List.fromList([67])));
    final message = await term.next();
    expect(message, isA<AgentIn>());
    expect((message! as AgentIn).data, [67]);
    expect(closed, isFalse);
    term.destroy();
  });

  test('a wrong term proof is closed without ready or reject', () async {
    final (port, secret) = readEndpoint(path);
    final term = await FakeTerm.connect(port);
    expect(await term.handshake(secret, wrongProof: true), isNull);
    expect(links, isEmpty);
  });

  test('a peer without the key that stops after hello is cut off', () async {
    final (port, _) = readEndpoint(path);
    final term = await FakeTerm.connect(port);
    term.send(TermHello(v: 1, nonce: Uint8List(32)));
    expect(await term.next(), isA<AgentChallenge>());
    await term.closed.timeout(const Duration(seconds: 2));
    expect(links, isEmpty);
  });

  test('a byte-by-byte trickle cannot outlast the deadline', () async {
    final (port, _) = readEndpoint(path);
    final term = await FakeTerm.connect(port);
    final bytes = termFrame(TermHello(v: 1, nonce: Uint8List(32)).encode());
    final sw = Stopwatch()..start();
    unawaited(() async {
      for (final byte in bytes) {
        term.sendRaw([byte]);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }());
    await term.closed.timeout(const Duration(seconds: 2));
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });

  test('an unknown version is rejected with version', () async {
    final (port, _) = readEndpoint(path);
    final term = await FakeTerm.connect(port);
    term.send(TermHello(v: 2, nonce: Uint8List(32)));
    expect((await term.next() as AgentReject).reason, AgentReject.version);
    await term.closed.timeout(const Duration(seconds: 2));
  });

  test('admit false is rejected with limit after a correct auth', () async {
    admitAll = false;
    final (port, secret) = readEndpoint(path);
    final term = await FakeTerm.connect(port);
    final answer = await term.handshake(secret);
    expect((answer as AgentReject).reason, AgentReject.limit);
    await term.closed.timeout(const Duration(seconds: 2));
    expect(links, isEmpty);
  });

  test(
    'an oversized frame or an unknown message before ready closes',
    () async {
      final (port, _) = readEndpoint(path);
      final big = await FakeTerm.connect(port);
      big.sendRaw([0, 1, 0, 1]);
      await big.closed.timeout(const Duration(seconds: 2));
      final odd = await FakeTerm.connect(port);
      odd.sendRaw(termFrame(encodeCbor({'t': 'future'})));
      await odd.closed.timeout(const Duration(seconds: 2));
    },
  );

  test(
    'a link whose peer stops reading closes itself past 1 MiB queued',
    () async {
      final (port, secret) = readEndpoint(path);
      final term = await FakeTerm.connect(port);
      expect(await term.handshake(secret), isA<AgentReady>());
      await pumpEventQueue();
      final link = links.single;
      var done = false;
      link.messages.listen(null, onDone: () => done = true);
      final chunk = AgentIn(data: Uint8List(kTermMaxChunk));
      for (var i = 0; i < 40; i++) {
        link.send(chunk); // synchronous: nothing is flushed in between
      }
      await pumpEventQueue();
      expect(done, isTrue);
    },
  );

  test(
    'stop closes links and pending handshakes; restart has a new secret',
    () async {
      final (port, secret) = readEndpoint(path);
      final linked = await FakeTerm.connect(port);
      expect(await linked.handshake(secret), isA<AgentReady>());
      final pending = await FakeTerm.connect(port);
      pending.send(TermHello(v: 1, nonce: Uint8List(32)));
      expect(await pending.next(), isA<AgentChallenge>());
      await server.stop();
      await linked.closed.timeout(const Duration(seconds: 2));
      await pending.closed.timeout(const Duration(seconds: 2));
      await server.start();
      final (_, newSecret) = readEndpoint(path);
      expect(newSecret, isNot(secret));
    },
  );

  test('stop leaves an endpoint file rewritten by someone else', () async {
    File(path).writeAsStringSync('v=1\nport=9\nsecret=${'0' * 64}\n');
    await server.stop();
    expect(File(path).existsSync(), isTrue);
  });
}

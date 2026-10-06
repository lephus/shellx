import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

/// A7 Task 5 review I2: what a host needs to bound its memory — bytes the
/// peer has not taken, a future for "all taken", and a way to stop reading.
void main() {
  MuxMessage big(int i) =>
      MuxMessage(MuxType.viewOut, q: i, fields: {'data': Uint8List(60000)});

  group('memory transport', () {
    test('close delivers the frames sent before it', () async {
      final (a, b) = MemoryMuxTransport.pair();
      final got = <int?>[];
      final ended = Completer<void>();
      b.messages.listen((m) => got.add(m.q), onDone: ended.complete);
      a.send(const MuxMessage(MuxType.result, q: 1));
      a.send(const MuxMessage(MuxType.error, q: 2));
      await a.close();
      await ended.future.timeout(const Duration(seconds: 1));
      expect(got, [1, 2]);
    });

    test('pendingBytes until the peer takes them; pauseInput holds them; '
        'resume delivers in order; drained completes', () async {
      final (a, b) = MemoryMuxTransport.pair();
      final got = <int?>[];
      b.messages.listen((m) => got.add(m.q));
      expect(a.pendingBytes, 0);
      await a.drained.timeout(const Duration(seconds: 1));
      b.pauseInput();
      for (var i = 1; i <= 3; i++) {
        a.send(big(i));
      }
      var drained = false;
      unawaited(a.drained.then((_) => drained = true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(a.pendingBytes, greaterThan(180000));
      expect([got, drained], [isEmpty, false]);
      b.resumeInput();
      await a.drained.timeout(const Duration(seconds: 1));
      expect(a.pendingBytes, 0);
      await Future<void>.delayed(Duration.zero);
      expect(got, [1, 2, 3]);
    });

    test('a reader that closes frees the sender', () async {
      final (a, b) = MemoryMuxTransport.pair();
      b.pauseInput();
      a.send(big(1));
      await Future<void>.delayed(Duration.zero);
      expect(a.pendingBytes, greaterThan(0));
      await b.close();
      await a.drained.timeout(const Duration(seconds: 1));
      expect(a.pendingBytes, 0);
      await a.done.timeout(const Duration(seconds: 1));
    });

    test('a paused reader still gets what was sent before the peer '
        'closed', () async {
      final (a, b) = MemoryMuxTransport.pair();
      final got = <int?>[];
      final ended = Completer<void>();
      b.messages.listen((m) => got.add(m.q), onDone: ended.complete);
      b.pauseInput();
      a.send(const MuxMessage(MuxType.result, q: 7));
      await a.close();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(got, isEmpty);
      b.resumeInput();
      await ended.future.timeout(const Duration(seconds: 1));
      expect(got, [7]);
    });
  });

  group('stream connection', () {
    test('without a flush hook (Windows pipe) nothing is counted', () async {
      final c = StreamMuxConnection(
        StreamController<Uint8List>().stream,
        (_) {},
        () async {},
      );
      c.send(big(1));
      expect(c.pendingBytes, 0);
      await c.drained.timeout(const Duration(seconds: 1));
    });

    test('with a flush hook: counted until the flush completes', () async {
      final written = <int>[];
      var flush = Completer<void>();
      final c = StreamMuxConnection(
        StreamController<Uint8List>().stream,
        (b) => written.add(b.length),
        () async {},
        flush: () => flush.future,
      );
      c.send(big(1));
      c.send(big(2));
      await Future<void>.delayed(Duration.zero);
      expect(c.pendingBytes, greaterThan(120000));
      c.send(big(3)); // queued behind the flush in progress
      flush.complete();
      flush = Completer<void>()..complete();
      await c.drained.timeout(const Duration(seconds: 1));
      expect([c.pendingBytes, written.length], [0, 3]);
    });

    test('once closed: nothing pending, drained at once; a flush that ends '
        'after the close timeout never subtracts (A7 Task 5 review)', () async {
      final flush = Completer<void>();
      final c = StreamMuxConnection(
        StreamController<Uint8List>().stream,
        (_) {},
        () async {},
        flush: () => flush.future,
      );
      c.send(big(1));
      await Future<void>.delayed(Duration.zero);
      expect(c.pendingBytes, greaterThan(60000));
      final closing = c.close(); // waits up to 1 s for the stuck flush
      expect(c.pendingBytes, 0);
      await c.drained.timeout(const Duration(milliseconds: 100));
      await closing.timeout(const Duration(seconds: 3));
      flush.complete(); // the peer finally took it, after the close
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(c.pendingBytes, 0);
      await c.drained.timeout(const Duration(milliseconds: 100));
    });
  });

  group('unix socket', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('mux_bp'));
    tearDown(() => dir.delete(recursive: true));

    test('a peer that does not read: bytes stay pending until it reads; '
        'close still delivers everything', () async {
      final path = '${dir.path}/mux.sock';
      final t = UnixMuxTransport();
      final listener = await t.listen(path);
      final serverSide = listener.connections.first;
      final client = await t.connect(path);
      final server = await serverSide;
      client.pauseInput();
      for (var i = 0; i < 50; i++) {
        server.send(big(i));
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(server.pendingBytes, greaterThan(0));
      var drained = false;
      unawaited(server.drained.then((_) => drained = true));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(drained, isFalse);
      final got = <int?>[];
      client.messages.listen((m) => got.add(m.q));
      server.send(const MuxMessage(MuxType.result, q: 99));
      unawaited(server.close());
      client.resumeInput();
      await client.done.timeout(const Duration(seconds: 5));
      expect(got.length, 51);
      expect(got.last, 99);
      expect(server.pendingBytes, 0);
      await listener.close();
    }, testOn: 'mac-os || linux');

    test(
      'pauseInput stops delivery; resumeInput restarts it',
      () async {
        final path = '${dir.path}/mux.sock';
        final t = UnixMuxTransport();
        final listener = await t.listen(path);
        final serverSide = listener.connections.first;
        final client = await t.connect(path);
        final server = await serverSide;
        final got = <int?>[];
        server.messages.listen((m) => got.add(m.q));
        server.pauseInput();
        client.send(const MuxMessage(MuxType.daemonStatus, q: 1));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(got, isEmpty);
        server.resumeInput();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(got, [1]);
        await client.close();
        await server.done.timeout(const Duration(seconds: 2));
        await listener.close();
      },
      testOn: 'mac-os || linux',
    );
  });
}

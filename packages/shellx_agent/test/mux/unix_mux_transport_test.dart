import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  group(
    'StreamMuxConnection errors (A7 Task 2 review r2)',
    streamConnectionErrors,
  );

  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('mux_t'));
  tearDown(() => dir.delete(recursive: true));

  test('long paths fall back to TMPDIR', () {
    expect(
      socketPathFor(muxDirectory: '/a/mux', tmpDirectory: '/t/', uid: 501),
      '/a/mux/mux.sock',
    );
    final long = '/${'x' * 100}';
    expect(
      socketPathFor(muxDirectory: long, tmpDirectory: '/t/', uid: 501),
      '/t/shellx-mux-501.sock',
    );
  });

  test(
    'socket is 0600; messages flow both ways; a stale socket is replaced',
    () async {
      final path = '${dir.path}/mux.sock';
      await _staleSocket(path);
      final t = UnixMuxTransport();
      final listener = await t.listen(path);
      expect(
        (Process.runSync('stat', ['-f', '%Lp', path]).stdout as String).trim(),
        '600',
      );
      final serverSide = listener.connections.first;
      final client = await t.connect(path);
      final server = await serverSide;
      final got = server.messages.first;
      client.send(const MuxMessage(MuxType.daemonStatus, q: 1));
      expect((await got).q, 1);
      final back = client.messages.first;
      server.send(const MuxMessage(MuxType.result, q: 1));
      expect((await back).type, MuxType.result);
      await client.close();
      await server.done;
      await listener.close();
    },
    testOn: 'mac-os || linux',
  );

  test('connect to nothing fails fast', () async {
    await expectLater(
      UnixMuxTransport().connect(
        '${dir.path}/none.sock',
        timeout: const Duration(milliseconds: 300),
      ),
      throwsA(isA<SocketException>()),
    );
  }, testOn: 'mac-os || linux');

  test(
    'a path that is not a socket is never deleted: listen fails',
    () async {
      final path = '${dir.path}/mux.sock';
      File(path).writeAsStringSync('not ours');
      await expectLater(UnixMuxTransport().listen(path), throwsA(anything));
      expect(File(path).readAsStringSync(), 'not ours');
    },
    testOn: 'mac-os || linux',
  );

  test('a peer that sends garbage and vanishes under ~3 MB of pending '
      'writes: done completes, no error escapes', () async {
    final path = '${dir.path}/mux.sock';
    final errors = <Object>[];
    final finished = Completer<void>();
    runZonedGuarded(
      () async {
        final listener = await UnixMuxTransport().listen(path);
        final serverSide = listener.connections.first;
        final raw = await Socket.connect(
          InternetAddress(path, type: InternetAddressType.unix),
          0,
        );
        final server = await serverSide;
        final chunk = Uint8List(60000);
        for (var i = 0; i < 50; i++) {
          server.send(MuxMessage(MuxType.viewOut, fields: {'data': chunk}));
        }
        raw.add([0, 0, 0, 2, 0xff, 0xff]); // garbage → the host closes
        await raw.flush();
        raw.destroy();
        await server.done.timeout(const Duration(seconds: 5));
        server.send(const MuxMessage(MuxType.result, q: 9)); // after close
        await listener.close();
        if (!finished.isCompleted) finished.complete();
      },
      (e, _) {
        errors.add(e);
        if (!finished.isCompleted) finished.complete();
      },
    );
    await finished.future.timeout(const Duration(seconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(errors, isEmpty);
  }, testOn: 'mac-os || linux');
}

/// A socket file left behind by a host that died.
Future<void> _staleSocket(String path) async {
  final server = await ServerSocket.bind(
    InternetAddress(path, type: InternetAddressType.unix),
    0,
  );
  await server.close();
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.unixDomainSock) {
    // Some runtimes unlink on close: recreate it from a child process.
    Process.runSync('/usr/bin/python3', [
      '-c',
      'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])',
      path,
    ]);
  }
  expect(
    FileSystemEntity.typeSync(path, followLinks: false),
    FileSystemEntityType.unixDomainSock,
  );
}

void streamConnectionErrors() {
  test('send: an oversized message throws ArgumentError to the caller', () {
    final c = StreamMuxConnection(
      const Stream<Uint8List>.empty(),
      (_) {},
      () async {},
    );
    expect(
      () => c.send(
        MuxMessage(MuxType.viewOut, fields: {'data': Uint8List(70000)}),
      ),
      throwsArgumentError,
    );
  });

  test('send: a dead sink (StateError) is swallowed', () {
    final c = StreamMuxConnection(
      StreamController<Uint8List>().stream,
      (_) => throw StateError('closed'),
      () async {},
    );
    c.send(const MuxMessage(MuxType.result, q: 1));
  });

  test('close: an unexpected sink error still completes done, then is '
      'reported to the zone', () async {
    final errors = <Object>[];
    final finished = Completer<void>();
    runZonedGuarded(() async {
      final c = StreamMuxConnection(
        StreamController<Uint8List>().stream,
        (_) {},
        () async => throw const FormatException('bug'),
      );
      await c.close();
      await c.done.timeout(const Duration(seconds: 1));
      finished.complete();
    }, (e, _) => errors.add(e));
    await finished.future.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(Duration.zero);
    expect(errors, [isFormatException]);
  });
}

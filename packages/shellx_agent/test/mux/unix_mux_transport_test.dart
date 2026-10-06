import 'dart:io';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
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
    'socket is 0600; messages flow both ways; a stale file is replaced',
    () async {
      final path = '${dir.path}/mux.sock';
      File(path).writeAsStringSync('stale');
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
}

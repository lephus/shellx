import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('mux_ep'));
  tearDown(() => dir.delete(recursive: true));

  final info = MuxEndpointInfo(
    address: '/tmp/x.sock',
    secret: Uint8List.fromList(List.filled(32, 0xab)),
    pid: 42,
    instance: 'f' * 32,
    protocol: 1,
    app: '1.6.0',
  );

  test('format/parse round trip; exact text', () {
    expect(
      info.format(),
      'v=1\naddress=/tmp/x.sock\nsecret=${'ab' * 32}\npid=42\ninstance=${'f' * 32}\nprotocol=1\napp=1.6.0\n',
    );
    final back = MuxEndpointInfo.parse(info.format())!;
    expect(back.secret, info.secret);
    expect(MuxEndpointInfo.parse('v=2\n'), isNull);
    expect(MuxEndpointInfo.parse('garbage'), isNull);
  });

  test('written 0600 in a 0700 dir; deleteIfOwned', () async {
    final file = MuxEndpointFile('${dir.path}/mux/endpoint');
    final contents = await file.write(info);
    String mode(String p) =>
        (Process.runSync('stat', ['-f', '%Lp', p]).stdout as String).trim();
    expect(mode('${dir.path}/mux'), '700');
    expect(mode('${dir.path}/mux/endpoint'), '600');
    expect((await file.read())!.pid, 42);
    await file.deleteIfOwned('other');
    expect(File('${dir.path}/mux/endpoint').existsSync(), isTrue);
    await file.deleteIfOwned(contents);
    expect(File('${dir.path}/mux/endpoint').existsSync(), isFalse);
  }, testOn: 'mac-os');
}

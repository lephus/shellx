@TestOn('mac-os || linux')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:shellx_agent/shellx_agent.dart';
import 'package:test/test.dart';

void main() {
  late Directory home;
  setUp(() async => home = await Directory.systemTemp.createTemp('endpoint-'));
  tearDown(() => home.delete(recursive: true));

  final secret = Uint8List.fromList(List.generate(32, (i) => i));

  test('paths per platform', () {
    expect(
      termEndpointPath(environment: {'HOME': '/Users/u'}, windows: false),
      '/Users/u/Library/Application Support/ShellX/term/endpoint',
    );
    expect(
      termEndpointPath(
        environment: {'LOCALAPPDATA': r'C:\Users\u\AppData\Local'},
        windows: true,
      ),
      r'C:\Users\u\AppData\Local\ShellX\term\endpoint',
    );
    expect(
      () => termEndpointPath(environment: {'HOME': ''}, windows: false),
      throwsStateError,
    );
    expect(
      () => termEndpointPath(environment: const {}, windows: true),
      throwsStateError,
    );
  });

  test('format is exactly three lines (spec §6.1)', () {
    expect(
      formatEndpoint(54321, secret),
      'v=1\nport=54321\nsecret='
      '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f\n',
    );
  });

  test('write creates the directory 0700 and the file 0600', () async {
    final path = termEndpointPath(
      environment: {'HOME': home.path},
      windows: false,
    );
    final contents = await EndpointFile(path).write(4000, secret);
    expect(File(path).readAsStringSync(), contents);
    expect(File(path).statSync().modeString(), 'rw-------');
    expect(File(path).parent.statSync().modeString(), 'rwx------');
    final leftovers = File(path).parent.listSync().map((e) => e.path);
    expect(leftovers, [path], reason: 'no temp file left behind');
  });

  test('a second write replaces the file', () async {
    final path = '${home.path}/term/endpoint';
    final file = EndpointFile(path);
    await file.write(1, secret);
    final second = await file.write(2, secret);
    expect(File(path).readAsStringSync(), second);
    expect(second, contains('port=2'));
  });

  test('deleteIfOwned deletes only our own contents', () async {
    final path = '${home.path}/term/endpoint';
    final file = EndpointFile(path);
    final ours = await file.write(1, secret);
    File(path).writeAsStringSync('v=1\nport=9\nsecret=${'0' * 64}\n');
    await file.deleteIfOwned(ours);
    expect(File(path).existsSync(), isTrue, reason: 'a newer agent wrote it');
    final again = await file.write(3, secret);
    await file.deleteIfOwned(again);
    expect(File(path).existsSync(), isFalse);
    await file.deleteIfOwned(again); // already gone: no error
  });
}

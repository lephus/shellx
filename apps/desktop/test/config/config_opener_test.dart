import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/config_opener.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('shellx-a9-open'));
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'a missing file is created from the template, then opened (D37)',
    () async {
      final runs = <List<String>>[];
      final opener = ConfigFileOpener(
        windows: false,
        start: (exe, args) async => runs.add([exe, ...args]),
      );
      final path = '${dir.path}/shellx/config';
      expect(await opener.open(path, template: '# hi\n'), isTrue);
      expect(File(path).readAsStringSync(), '# hi\n');
      expect(runs.single, ['/usr/bin/open', '-t', path]);
      // An existing file is never rewritten.
      File(path).writeAsStringSync('font-size = 14\n');
      await opener.open(path, template: '# hi\n');
      expect(File(path).readAsStringSync(), 'font-size = 14\n');
    },
  );

  test('Windows: Notepad', () async {
    final runs = <List<String>>[];
    final opener = ConfigFileOpener(
      windows: true,
      start: (exe, args) async => runs.add([exe, ...args]),
    );
    await opener.open('${dir.path}/c', template: '');
    expect(runs.single.first, 'notepad.exe');
  });

  test('a failure returns false, never throws', () async {
    final print = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) {};
    addTearDown(() => debugPrint = print);
    final opener = ConfigFileOpener(
      windows: false,
      start: (_, _) async => throw const OSError('no'),
    );
    expect(await opener.open('${dir.path}/x', template: ''), isFalse);
  });
}

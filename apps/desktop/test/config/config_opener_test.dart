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
      expect(await opener.open(path, template: () => '# hi\n'), isTrue);
      expect(File(path).readAsStringSync(), '# hi\n');
      expect(runs.single, ['/usr/bin/open', '-t', path]);
      // An existing file is never rewritten.
      File(path).writeAsStringSync('font-size = 14\n');
      await opener.open(path, template: () => '# hi\n');
      expect(File(path).readAsStringSync(), 'font-size = 14\n');
    },
  );

  test('Windows: Notepad', () async {
    final runs = <List<String>>[];
    final opener = ConfigFileOpener(
      windows: true,
      start: (exe, args) async => runs.add([exe, ...args]),
    );
    await opener.open('${dir.path}/c', template: () => '');
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
    expect(await opener.open('${dir.path}/x', template: () => ''), isFalse);
  });

  test('Notepad gets the path as its argument', () async {
    final runs = <List<String>>[];
    final opener = ConfigFileOpener(
      windows: true,
      start: (exe, args) async => runs.add([exe, ...args]),
    );
    final path = '${dir.path}/c';
    await opener.open(path, template: () => '');
    expect(runs.single, ['notepad.exe', path]);
  });

  test('a double open creates once and neither reports a failure', () async {
    final runs = <List<String>>[];
    final opener = ConfigFileOpener(
      windows: false,
      start: (exe, args) async => runs.add([exe, ...args]),
    );
    final path = '${dir.path}/shellx/config';
    final results = await Future.wait([
      opener.open(path, template: () => '# hi\n'),
      opener.open(path, template: () => '# hi\n'),
    ]);
    expect(results, [true, true]);
    expect(File(path).readAsStringSync(), '# hi\n');
    expect(runs, hasLength(2));
    expect(Directory('${dir.path}/shellx').listSync().map((e) => e.path), [
      path,
    ]);
  });

  test('the template is built only when the file is missing', () async {
    final opener = ConfigFileOpener(windows: false, start: (_, _) async {});
    final path = '${dir.path}/c';
    File(path).writeAsStringSync('x\n');
    await opener.open(path, template: () => fail('built for an existing file'));
    expect(File(path).readAsStringSync(), 'x\n');
  });

  test('a failing template leaves neither a file nor a temp file', () async {
    final opener = ConfigFileOpener(windows: false, start: (_, _) async {});
    final path = '${dir.path}/shellx/config';
    expect(
      await opener.open(path, template: () => throw StateError('x')),
      isFalse,
    );
    expect(File(path).existsSync(), isFalse);
    expect(Directory('${dir.path}/shellx').listSync(), isEmpty);
  });

  test('an existing file wins a lost race and no temp file stays', () async {
    final opener = ConfigFileOpener(windows: false, start: (_, _) async {});
    final path = '${dir.path}/shellx/config';
    Directory('${dir.path}/shellx').createSync();
    var built = 0;
    // Another process creates the file while the template is being built.
    final ok = await opener.open(
      path,
      template: () {
        built++;
        File(path).writeAsStringSync('theirs\n');
        return 'ours\n';
      },
    );
    expect(ok, isTrue);
    expect(built, 1);
    expect(File(path).readAsStringSync(), 'theirs\n');
    expect(Directory('${dir.path}/shellx').listSync().map((e) => e.path), [
      path,
    ]);
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/platform/url_opener.dart';

void main() {
  for (final windows in [false, true]) {
    test('openLocalPort opens http://localhost:PORT/ only '
        '(${windows ? 'Windows' : 'macOS'}, A2 D9)', () async {
      final runs = <String>[];
      final opener = SystemUrlOpener(
        isWindows: windows,
        run: (exe, args) async {
          runs.add('$exe ${args.join(' ')}');
          return ProcessResult(0, 0, '', '');
        },
      );
      await opener.openLocalPort(5173);
      expect(runs.single, endsWith('http://localhost:5173/'));
      for (final bad in [0, -1, 65536]) {
        expect(() => opener.openLocalPort(bad), throwsArgumentError);
      }
      // open() still refuses plain http.
      expect(
        () => opener.open(Uri.parse('http://localhost:5173/')),
        throwsArgumentError,
      );
      expect(runs, hasLength(1));
    });
  }
}

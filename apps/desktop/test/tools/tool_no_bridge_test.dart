import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// V2-3 D16: ShellX never runs code in a tool's page — no JavaScript
/// channel, no script, no snapshot — and the engine says so in its source.
void main() {
  test('no bridge, script or snapshot in the tool path (D16)', () {
    const banned = [
      'runJavaScript',
      'runJavaScriptReturningResult',
      'addJavaScriptChannel',
      'addUserScript',
      'WKUserScript',
      'takeSnapshot',
      'evaluateJavaScript',
      'capturePng',
    ];
    final files = [
      for (final dir in [
        'lib/src/browser',
        'lib/src/tools',
        'lib/src/ui/tools',
      ])
        // `lib/src/ui/tools` comes with the dock (plan Task 12).
        if (Directory(dir).existsSync())
          ...Directory(dir)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')),
      File('macos/Runner/BrowserNative.swift'),
    ];
    expect(files, isNotEmpty);
    for (final f in files) {
      final text = f.readAsStringSync();
      for (final word in banned) {
        expect(text, isNot(contains(word)), reason: '${f.path}: $word');
      }
    }
  });
}

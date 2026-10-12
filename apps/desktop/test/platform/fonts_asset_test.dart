import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  test('xterm is the vendored 4.0.0, like mobile (A1 D12)', () {
    expect(
      pubspec,
      contains(
        RegExp(
          r'^  xterm:\n    path: ../../third_party/xterm$',
          multiLine: true,
        ),
      ),
    );
    expect(
      File('../../third_party/xterm/pubspec.yaml').readAsStringSync(),
      contains('version: 4.0.0+shellx.'),
    );
  });

  test('JetBrains Mono is bundled with its SIL OFL text (A1 D16)', () {
    expect(pubspec, contains('family: JetBrainsMono'));
    for (final face in ['Regular', 'Bold', 'Italic', 'BoldItalic']) {
      expect(
        File('assets/fonts/JetBrainsMono-$face.ttf').existsSync(),
        isTrue,
        reason: face,
      );
    }
    final license = File('assets/licenses/JetBrainsMono-OFL.txt');
    expect(license.readAsStringSync(), contains('SIL OPEN FONT LICENSE'));
    expect(pubspec, contains('- assets/licenses/'));
  });
}

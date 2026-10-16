import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_design/shellx_design.dart';

void main() {
  test('families by platform (§6.1): SF Mono only on iOS and macOS', () {
    for (final p in [TargetPlatform.iOS, TargetPlatform.macOS]) {
      expect(ShellxFonts.isApple(p), isTrue);
      expect(ShellxFonts.uiFamily(p), 'SF Mono');
      expect(ShellxFonts.uiFallback(p), ['JetBrainsMono']);
    }
    for (final p in [
      TargetPlatform.android,
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.fuchsia,
    ]) {
      expect(ShellxFonts.isApple(p), isFalse);
      expect(ShellxFonts.uiFamily(p), 'JetBrainsMono');
      expect(ShellxFonts.uiFallback(p), isEmpty);
    }
    expect(ShellxFonts.systemMono, 'SF Mono');
    expect(ShellxFonts.bundledMono, 'JetBrainsMono');
    expect(ShellxFonts.bundledMonoLight, 'JetBrainsMonoLight');
  });
}

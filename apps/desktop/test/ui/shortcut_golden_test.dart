import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_shortcuts.dart';

/// Spec D24 / criterion 1: the default tables after A9 are today's tables
/// (plus A9's three new chords, Step 5). The fixtures are written once,
/// from the code as it was before A9 (`WRITE_GOLDEN=1`).
String _activator(ShortcutActivator a) {
  final s = a as SingleActivator;
  return [
        if (s.control) 'ctrl',
        if (s.alt) 'alt',
        if (s.shift) 'shift',
        if (s.meta) 'meta',
        s.trigger.keyId.toRadixString(16),
      ].join('+') +
      (s.includeRepeats ? '' : ' norepeat');
}

String _describe(Intent i) => switch (i) {
  SelectTabIntent(:final position) => 'SelectTabIntent($position)',
  SplitPaneIntent(:final axis) => 'SplitPaneIntent(${axis.name})',
  FocusPaneIntent(:final direction) => 'FocusPaneIntent(${direction.name})',
  ResizePaneIntent(:final direction) => 'ResizePaneIntent(${direction.name})',
  SelectAllIntent(:final fromMenu) =>
    fromMenu ? 'SelectAllIntent(menu)' : 'SelectAllIntent',
  _ => i.runtimeType.toString(),
};

Set<String> signatures(Map<ShortcutActivator, Intent> map) => {
  for (final e in map.entries) '${_activator(e.key)} -> ${_describe(e.value)}',
};

/// Chords A9 adds on purpose (spec D24); empty until Step 5.
Set<String> a9Additions(String map, String platform) => const {};

void main() {
  // No browser map: A6 is not merged ("browser pending A6").
  final maps =
      <String, Map<ShortcutActivator, Intent> Function(TargetPlatform)>{
        'desktop': desktopShortcuts,
        'view': terminalViewShortcuts,
      };
  for (final (name, platform) in [
    ('mac', TargetPlatform.macOS),
    ('win', TargetPlatform.windows),
  ]) {
    for (final MapEntry(key: map, value: build) in maps.entries) {
      test('$map / $name equals the pre-A9 table (D24)', () {
        final file = File('test/ui/fixtures/shortcuts_${map}_$name.txt');
        final actual = signatures(build(platform)).toList()..sort();
        // Two activators for one chord would make a map lookup ambiguous.
        expect(
          actual.map((s) => s.split(' -> ').first).toSet(),
          hasLength(actual.length),
        );
        if (Platform.environment['WRITE_GOLDEN'] == '1') {
          file
            ..createSync(recursive: true)
            ..writeAsStringSync('${actual.join('\n')}\n');
        }
        final expected = file
            .readAsLinesSync()
            .where((l) => l.isNotEmpty)
            .toSet();
        expect(actual.toSet(), expected.union(a9Additions(map, name)));
      });
    }
  }
}

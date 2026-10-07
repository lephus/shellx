import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/config/keybind_actions.dart';
import 'package:shellx_desktop/src/config/keybind_trigger.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_shortcuts.dart';

/// Spec D24 / criterion 1: the default tables after A9 are today's tables
/// plus A9's three new chords. The fixtures were written once, from the
/// code as it was before A9 (commit d5bdf16); they are frozen and this
/// test can only read them.
Set<String> signatures(Map<ShortcutActivator, Intent> map) => {
  for (final e in map.entries)
    '${describeActivator(e.key)} -> ${describeIntent(e.value)}',
};

/// Chords A9 adds on purpose (spec D24), and A8's ⌘⇧K (D41). No browser map: A6 is not merged.
Set<String> a9Additions(String map, String platform) => platform == 'mac'
    ? const {
        'shift+meta+2c norepeat -> ReloadConfigIntent',
        'meta+2c norepeat -> OpenConfigIntent',
        'shift+meta+70 norepeat -> CommandPaletteIntent',
        // A8 D41: "Connect to a server".
        'shift+meta+6b norepeat -> OpenSshConnectIntent',
      }
    : const {
        'ctrl+shift+2c norepeat -> ReloadConfigIntent',
        'ctrl+2c norepeat -> OpenConfigIntent',
        'ctrl+shift+70 norepeat -> CommandPaletteIntent',
        'ctrl+shift+6b norepeat -> OpenSshConnectIntent',
      };

/// A10 D4: find in terminal (⌘F/⌘G; Ctrl+Shift+F/G).
Set<String> a10Additions(String platform) => platform == 'mac'
    ? const {
        'meta+66 norepeat -> StartSearchIntent',
        'meta+67 -> NavigateSearchIntent(next)',
        'shift+meta+67 -> NavigateSearchIntent(previous)',
      }
    : const {
        'ctrl+shift+66 norepeat -> StartSearchIntent',
        'ctrl+shift+67 -> NavigateSearchIntent(next)',
        'ctrl+alt+shift+67 -> NavigateSearchIntent(previous)',
      };

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
        final expected = file
            .readAsLinesSync()
            .where((l) => l.isNotEmpty)
            .toSet();
        expect(
          actual.toSet(),
          expected.union(a9Additions(map, name)).union(a10Additions(name)),
        );
      });
    }
  }
}

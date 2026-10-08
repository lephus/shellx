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
        'shift+meta+70 norepeat -> CommandPaletteIntent',
        // A8 D41: "Connect to a server".
        'shift+meta+6b norepeat -> OpenSshConnectIntent',
      }
    : const {
        'ctrl+shift+2c norepeat -> ReloadConfigIntent',
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

/// A11 D10, a deliberate change of A9 D37: ⌘, / Ctrl+, now opens Settings and
/// the configuration file moved to ⌘⌥, / Ctrl+Shift+Alt+, (Windows: left Alt
/// only). A9's `OpenConfigIntent` line on ⌘, / Ctrl+, is replaced.
Set<String> a11Changes(String platform) => platform == 'mac'
    ? const {
        'meta+2c norepeat -> OpenSettingsIntent',
        'alt+meta+2c norepeat -> OpenConfigIntent',
      }
    : const {
        'ctrl+2c norepeat -> OpenSettingsIntent',
        'ctrl+alt+shift+2c norepeat -> OpenConfigIntent',
      };

/// A11: D11 macOS line editing at the prompt (Windows binds none), D13
/// copy mode (⌘⇧M / Ctrl+Shift+M), D14 reopen closed (⌘⇧T /
/// Ctrl+Shift+Alt+T), D21 search all (⌘⇧F / Ctrl+Shift+Alt+F), D15 focus history (⌘⌃[ / ⌘⌃]; Ctrl+Alt+[ / ]).
Set<String> a11Additions(String platform) => platform == 'mac'
    ? const {
        'meta+100000302 -> EditLineIntent(line_start)',
        'meta+100000303 -> EditLineIntent(line_end)',
        'meta+100000008 -> EditLineIntent(delete_line)',
        'alt+100000008 -> EditLineIntent(delete_word)',
        'alt+10000007f -> EditLineIntent(delete_word_forward)',
        'shift+meta+6d norepeat -> ToggleCopyModeIntent',
        'shift+meta+74 norepeat -> ReopenClosedIntent',
        'shift+meta+66 norepeat -> SearchAllIntent',
        'ctrl+meta+5b norepeat -> FocusHistoryIntent(back)',
        'ctrl+meta+5d norepeat -> FocusHistoryIntent(forward)',
      }
    : const {
        'ctrl+shift+6d norepeat -> ToggleCopyModeIntent',
        'ctrl+alt+shift+74 norepeat -> ReopenClosedIntent',
        'ctrl+alt+shift+66 norepeat -> SearchAllIntent',
        'ctrl+alt+5b norepeat -> FocusHistoryIntent(back)',
        'ctrl+alt+5d norepeat -> FocusHistoryIntent(forward)',
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
          expected
              .union(a9Additions(map, name))
              .union(a10Additions(name))
              .union(a11Additions(name))
              .union(a11Changes(name)),
        );
      });
    }
  }
}

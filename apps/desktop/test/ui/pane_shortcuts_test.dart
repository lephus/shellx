import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellx_desktop/src/terminal/pane_layout.dart';
import 'package:shellx_desktop/src/ui/terminal/terminal_shortcuts.dart';

Intent? _find(
  Map<ShortcutActivator, Intent> map,
  LogicalKeyboardKey key, {
  bool meta = false,
  bool control = false,
  bool shift = false,
  bool alt = false,
}) {
  for (final MapEntry(key: a, value: i) in map.entries) {
    if (a is SingleActivator &&
        a.trigger == key &&
        a.meta == meta &&
        a.control == control &&
        a.shift == shift &&
        a.alt == alt) {
      return i;
    }
  }
  return null;
}

void main() {
  for (final (name, build) in [
    ('TerminalView', terminalViewShortcuts),
    ('workspace', desktopShortcuts),
  ]) {
    test('$name: macOS pane chords (P3)', () {
      final m = build(TargetPlatform.macOS);
      expect(
        (_find(m, LogicalKeyboardKey.keyD, meta: true) as SplitPaneIntent).axis,
        SplitAxis.row,
      );
      expect(
        (_find(m, LogicalKeyboardKey.keyD, meta: true, shift: true)
                as SplitPaneIntent)
            .axis,
        SplitAxis.column,
      );
      expect(
        (_find(m, LogicalKeyboardKey.arrowLeft, meta: true, alt: true)
                as FocusPaneIntent)
            .direction,
        PaneDirection.left,
      );
      expect(
        _find(m, LogicalKeyboardKey.enter, meta: true, shift: true),
        isA<TogglePaneZoomIntent>(),
      );
      expect(
        _find(m, LogicalKeyboardKey.equal, meta: true, control: true),
        isA<EqualizePanesIntent>(),
      );
      expect(
        (_find(m, LogicalKeyboardKey.arrowDown, meta: true, control: true)
                as ResizePaneIntent)
            .direction,
        PaneDirection.down,
      );
    });

    test('$name: Windows pane chords (D20), no clash with font keys', () {
      final m = build(TargetPlatform.windows);
      expect(
        (_find(m, LogicalKeyboardKey.keyD, control: true, shift: true)
                as SplitPaneIntent)
            .axis,
        SplitAxis.row,
      );
      expect(
        (_find(
                  m,
                  LogicalKeyboardKey.keyD,
                  control: true,
                  shift: true,
                  alt: true,
                )
                as SplitPaneIntent)
            .axis,
        SplitAxis.column,
      );
      expect(
        _find(m, LogicalKeyboardKey.arrowRight, control: true, alt: true),
        isA<FocusPaneIntent>(),
      );
      expect(
        _find(m, LogicalKeyboardKey.enter, control: true, shift: true),
        isA<TogglePaneZoomIntent>(),
      );
      expect(
        _find(
          m,
          LogicalKeyboardKey.equal,
          control: true,
          shift: true,
          alt: true,
        ),
        isA<EqualizePanesIntent>(),
      );
      expect(
        _find(
          m,
          LogicalKeyboardKey.arrowUp,
          control: true,
          shift: true,
          alt: true,
        ),
        isA<ResizePaneIntent>(),
      );
      // A1 font keys are untouched.
      expect(
        _find(m, LogicalKeyboardKey.equal, control: true, shift: true),
        isA<FontBiggerIntent>(),
      );
    });
  }

  test('split, zoom and equalize ignore key repeat; focus/resize repeat', () {
    final m = terminalViewShortcuts(TargetPlatform.macOS);
    for (final MapEntry(key: a, value: i) in m.entries) {
      if (a is! SingleActivator) continue;
      if (i is SplitPaneIntent ||
          i is TogglePaneZoomIntent ||
          i is EqualizePanesIntent) {
        expect(a.includeRepeats, isFalse, reason: '$i');
      }
      if (i is FocusPaneIntent || i is ResizePaneIntent) {
        expect(a.includeRepeats, isTrue, reason: '$i');
      }
    }
  });
}

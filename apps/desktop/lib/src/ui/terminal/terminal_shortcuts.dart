import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class NewTabIntent extends Intent {
  const NewTabIntent();
}

class CloseTabIntent extends Intent {
  const CloseTabIntent();
}

class SelectTabIntent extends Intent {
  const SelectTabIntent(this.position);

  /// 1-based.
  final int position;
}

class NextTabIntent extends Intent {
  const NextTabIntent();
}

class PreviousTabIntent extends Intent {
  const PreviousTabIntent();
}

class CopySelectionIntent extends Intent {
  const CopySelectionIntent();
}

class PasteClipboardIntent extends Intent {
  const PasteClipboardIntent();
}

class FontBiggerIntent extends Intent {
  const FontBiggerIntent();
}

class FontSmallerIntent extends Intent {
  const FontSmallerIntent();
}

class FontResetIntent extends Intent {
  const FontResetIntent();
}

class NextRegionIntent extends Intent {
  const NextRegionIntent();
}

class PreviousRegionIntent extends Intent {
  const PreviousRegionIntent();
}

const _digits = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

/// Spec criterion 2 and UI §3.6. The same map goes to the workspace's
/// `Shortcuts` and to every `TerminalView` (xterm would otherwise consume
/// Ctrl+Tab, Ctrl+Shift+T… as terminal input). Windows tab-number and font
/// chords follow Windows Terminal, which leaves Ctrl+digit to the shell.
Map<ShortcutActivator, Intent> desktopShortcuts(TargetPlatform platform) {
  final mac = platform == TargetPlatform.macOS;
  SingleActivator primary(LogicalKeyboardKey key) => mac
      ? SingleActivator(key, meta: true)
      : SingleActivator(key, control: true, shift: true);
  SingleActivator font(LogicalKeyboardKey key, {bool shift = false}) => mac
      ? SingleActivator(key, meta: true, shift: shift)
      : SingleActivator(key, control: true, shift: shift);
  return {
    primary(LogicalKeyboardKey.keyT): const NewTabIntent(),
    primary(LogicalKeyboardKey.keyW): const CloseTabIntent(),
    primary(LogicalKeyboardKey.keyC): const CopySelectionIntent(),
    primary(LogicalKeyboardKey.keyV): const PasteClipboardIntent(),
    // TerminalView's own default, kept because this map replaces it; the
    // workspace has no action for it, so outside the terminal it is a no-op.
    if (mac)
      const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
          const SelectAllTextIntent(SelectionChangedCause.keyboard),
    for (var i = 0; i < _digits.length; i++)
      (mac
              ? SingleActivator(_digits[i], meta: true)
              : SingleActivator(_digits[i], control: true, alt: true)):
          SelectTabIntent(i + 1),
    const SingleActivator(LogicalKeyboardKey.tab, control: true):
        const NextTabIntent(),
    const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true):
        const PreviousTabIntent(),
    font(LogicalKeyboardKey.equal): const FontBiggerIntent(),
    // ⌘+ is ⌘⇧= on a US layout; `add` is the "+" key of layouts that have
    // one (German…), and the keypad.
    font(LogicalKeyboardKey.equal, shift: true): const FontBiggerIntent(),
    font(LogicalKeyboardKey.add): const FontBiggerIntent(),
    font(LogicalKeyboardKey.numpadAdd): const FontBiggerIntent(),
    font(LogicalKeyboardKey.minus): const FontSmallerIntent(),
    font(LogicalKeyboardKey.numpadSubtract): const FontSmallerIntent(),
    font(LogicalKeyboardKey.digit0): const FontResetIntent(),
    font(LogicalKeyboardKey.numpad0): const FontResetIntent(),
    const SingleActivator(LogicalKeyboardKey.f6): const NextRegionIntent(),
    const SingleActivator(LogicalKeyboardKey.f6, shift: true):
        const PreviousRegionIntent(),
  };
}

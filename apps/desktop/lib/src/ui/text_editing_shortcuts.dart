import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// ⌘A/⌘C/⌘X/⌘V (Ctrl on Windows and Linux, plus the terminal's own
/// Ctrl+Shift+C/V) as the editing intents of the text field below.
///
/// Wrapped around a field inside the workspace, it keeps the window's
/// terminal shortcuts (copy the selection, paste into the terminal) from
/// taking those keys: the focused field's own `Shortcuts` come first.
/// Shared by the inline rename field (A2) and the command palette (A9 D7).
Map<ShortcutActivator, Intent> textEditingShortcuts() {
  final mac = defaultTargetPlatform == TargetPlatform.macOS;
  SingleActivator key(LogicalKeyboardKey k, {bool shift = false}) => mac
      ? SingleActivator(k, meta: true, shift: shift)
      : SingleActivator(k, control: true, shift: shift);
  return {
    key(LogicalKeyboardKey.keyA): const SelectAllTextIntent(
      SelectionChangedCause.keyboard,
    ),
    key(LogicalKeyboardKey.keyC): CopySelectionTextIntent.copy,
    key(LogicalKeyboardKey.keyX): const CopySelectionTextIntent.cut(
      SelectionChangedCause.keyboard,
    ),
    key(LogicalKeyboardKey.keyV): const PasteTextIntent(
      SelectionChangedCause.keyboard,
    ),
    if (!mac) ...{
      key(LogicalKeyboardKey.keyC, shift: true): CopySelectionTextIntent.copy,
      key(LogicalKeyboardKey.keyV, shift: true): const PasteTextIntent(
        SelectionChangedCause.keyboard,
      ),
    },
  };
}

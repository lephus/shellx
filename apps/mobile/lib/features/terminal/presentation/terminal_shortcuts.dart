import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Copy/paste shortcuts for `TerminalView` with a hardware keyboard.
///
/// xterm.dart's defaults bind Ctrl+A / Ctrl+V on Android, which would swallow
/// keys the shell needs (readline, tmux, vim), so Android uses Ctrl+Shift+C/V
/// like desktop terminals; iOS/iPadOS uses ⌘C / ⌘V. No select-all binding.
Map<ShortcutActivator, Intent> terminalShortcuts(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return {
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): CopySelectionTextIntent.copy,
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): const PasteTextIntent(
          SelectionChangedCause.keyboard,
        ),
      };
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return {
        const SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true): CopySelectionTextIntent.copy,
        const SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true): const PasteTextIntent(
          SelectionChangedCause.keyboard,
        ),
      };
  }
}

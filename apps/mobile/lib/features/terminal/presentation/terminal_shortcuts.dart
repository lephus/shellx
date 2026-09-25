import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Intent for pasting text to the terminal with normalization.
///
/// The handler must normalize the pasted text with [normalizePastedText],
/// then call `terminal.paste(text)` which adds bracketed-paste markers
/// if the terminal enabled mode 2004.
///
/// This custom intent prevents xterm.dart's internal `TerminalActions` from
/// intercepting the paste before normalization can occur.
class ShellxPasteIntent extends Intent {
  const ShellxPasteIntent();
}

/// Intent for copying selected text from the terminal.
///
/// This custom intent prevents interference with xterm.dart's internal shortcuts.
class ShellxCopyIntent extends Intent {
  const ShellxCopyIntent();
}

/// Copy/paste shortcuts for `TerminalView` with a hardware keyboard.
///
/// xterm.dart's defaults bind Ctrl+A / Ctrl+V on Android, which would swallow
/// keys the shell needs (readline, tmux, vim), so Android uses Ctrl+Shift+C/V
/// like desktop terminals; iOS/iPadOS uses ⌘C / ⌘V. No select-all binding.
///
/// Uses ShellX custom intents ([ShellxPasteIntent], [ShellxCopyIntent]) so
/// the app-level `Actions` widget can normalize pasted text before sending it
/// to the terminal.
Map<ShortcutActivator, Intent> terminalShortcuts(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return {
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): const ShellxCopyIntent(),
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): const ShellxPasteIntent(),
      };
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return {
        const SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true): const ShellxCopyIntent(),
        const SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true): const ShellxPasteIntent(),
      };
  }
}

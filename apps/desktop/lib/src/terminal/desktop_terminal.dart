import 'package:xterm/xterm.dart';

import 'terminal_input.dart';

/// xterm [Terminal] for a desktop tab. xterm reports both what the user
/// typed and what the emulator answers by itself (cursor position, device
/// attributes) through `onOutput`; this class splits them:
/// [onUserInput] takes the driver (A1 D6), [onReply] is written only while
/// the desktop drives (`LocalSessionView.reply`). Callers never set
/// `onOutput` themselves.
final class DesktopTerminal extends Terminal {
  DesktopTerminal({super.maxLines = 10000, super.platform})
    : super(inputHandler: desktopInputHandler) {
    onOutput = _route;
  }

  void Function(String data)? onUserInput;
  void Function(String data)? onReply;

  int _userDepth = 0;

  void _route(String data) =>
      (_userDepth > 0 ? onUserInput : onReply)?.call(data);

  T _asUser<T>(T Function() body) {
    _userDepth++;
    try {
      return body();
    } finally {
      _userDepth--;
    }
  }

  @override
  bool keyInput(
    TerminalKey key, {
    bool shift = false,
    bool alt = false,
    bool ctrl = false,
  }) => _asUser(() => super.keyInput(key, shift: shift, alt: alt, ctrl: ctrl));

  @override
  bool charInput(int charCode, {bool alt = false, bool ctrl = false}) =>
      _asUser(() => super.charInput(charCode, alt: alt, ctrl: ctrl));

  /// IME commits and plain text: control characters stripped, LF → CR.
  @override
  void textInput(String text) =>
      _asUser(() => super.textInput(normalizeTypedText(text)));

  /// Clipboard: cleaned so a paste can never end bracketed paste early.
  @override
  void paste(String text) =>
      _asUser(() => super.paste(normalizePastedText(text)));

  @override
  bool mouseInput(
    TerminalMouseButton button,
    TerminalMouseButtonState buttonState,
    CellOffset position,
  ) => _asUser(() => super.mouseInput(button, buttonState, position));
}

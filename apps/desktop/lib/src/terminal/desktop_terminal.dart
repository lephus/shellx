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

  /// xterm's reflow keeps every blank row under the cursor, so wrapping
  /// the lines for a narrower window pushes the top line into the
  /// scrollback while the screen ends in empty rows (the prompt scrolls
  /// off, M-1). Blank rows below the cursor are dropped instead, until
  /// the screen fits, as iTerm2 and Terminal.app do.
  @override
  void resize(
    int newWidth,
    int newHeight, [
    int? pixelWidth,
    int? pixelHeight,
  ]) {
    super.resize(newWidth, newHeight, pixelWidth, pixelHeight);
    if (isUsingAltBuffer) return;
    final buffer = mainBuffer;
    while (buffer.scrollBack > 0 &&
        buffer.height - 1 > buffer.absoluteCursorY &&
        buffer.lines[buffer.height - 1].getTrimmedLength() == 0) {
      buffer.lines.pop();
      // The screen's top moved up one row: keep the cursor on its line.
      buffer.setCursorY(buffer.cursorY + 1);
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

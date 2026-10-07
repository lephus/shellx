import 'package:xterm/xterm.dart';

import 'terminal_input.dart';

/// xterm [Terminal] for a desktop tab. xterm reports both what the user
/// typed and what the emulator answers by itself (cursor position, device
/// attributes) through `onOutput`; this class splits them:
/// [onUserInput] takes the driver (A1 D6), [onReply] is written only while
/// the desktop drives (`LocalSessionView.reply`). Callers never set
/// `onOutput` themselves.
final class DesktopTerminal extends Terminal {
  DesktopTerminal({
    super.maxLines = 10000,
    super.platform,
    TerminalInputHandler? inputHandler,
  }) : super(inputHandler: inputHandler ?? desktopInputHandler) {
    onOutput = _route;
  }

  /// A9 D31: bytes from the user's own key binding (`text:`, `csi:`,
  /// `esc:`), sent as typed input (the desktop takes the driver, A1 D6)
  /// and, like Ghostty, not filtered: the configuration is the user's.
  void sendUserText(String data) => _asUser(() => onOutput?.call(data));

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

  /// Rows earlier resizes pushed into the scrollback (a shorter window
  /// with the cursor at the bottom) that a taller one may bring back.
  int _pushedByResize = 0;

  /// The scrollback right after the last resize; a different value at the
  /// next resize means output scrolled since, and the rows pushed then are
  /// no longer the ones above the screen.
  int? _scrollBackAfterResize;

  /// Keeps the screen where it is across a resize (M-1):
  /// - xterm's reflow keeps every blank row under the cursor, so wrapping
  ///   for a narrower window pushed the top line into the scrollback while
  ///   the screen ended in empty rows. Only what this resize pushed is
  ///   undone, by dropping blank rows below the cursor (as iTerm2 and
  ///   Terminal.app do).
  /// - A taller window makes xterm pull scrollback down over the screen;
  ///   after a clear (Ctrl+L) that brought old output back and moved the
  ///   prompt down. Only rows an earlier resize pushed up come back; the
  ///   rest stays in the scrollback and the new rows are blank below.
  @override
  void resize(
    int newWidth,
    int newHeight, [
    int? pixelWidth,
    int? pixelHeight,
  ]) {
    final buffer = mainBuffer;
    final before = buffer.scrollBack;
    if (_scrollBackAfterResize != before) _pushedByResize = 0;
    super.resize(newWidth, newHeight, pixelWidth, pixelHeight);
    if (!isUsingAltBuffer) {
      while (buffer.scrollBack > before &&
          buffer.height - 1 > buffer.absoluteCursorY &&
          buffer.lines[buffer.height - 1].getTrimmedLength() == 0) {
        buffer.lines.pop();
        // The screen's top moved up one row: keep the cursor on its line.
        buffer.setCursorY(buffer.cursorY + 1);
      }
      final after = buffer.scrollBack;
      if (after > before) {
        _pushedByResize += after - before;
      } else if (after < before) {
        final pulled = before - after;
        final allowed = pulled < _pushedByResize ? pulled : _pushedByResize;
        _pushedByResize -= allowed;
        for (var i = allowed; i < pulled; i++) {
          // Put back one blank row under the screen: its top moves down
          // one row, so the cursor stays on its line.
          buffer.lines.push(BufferLine(viewWidth));
          buffer.setCursorY(buffer.cursorY - 1);
        }
      }
    }
    _scrollBackAfterResize = buffer.scrollBack;
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

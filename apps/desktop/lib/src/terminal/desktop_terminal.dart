import 'dart:async';

import 'package:shellx_core/shellx_core.dart';
import 'package:xterm/xterm.dart';

import '../platform/ime_trace.dart';
import 'hyperlink_registry.dart';
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
    // A10 D11: OSC 8 hyperlinks (xterm hands them over, stores nothing).
    onPrivateOSC = (code, args) {
      if (code == '8') hyperlinks.handle(buffer, args);
    };
  }

  final _sgr = SgrFilter();

  /// Every byte any program, local, A5b or SSH, sends to this tab goes
  /// through here, and xterm 4.0.0 misreads some SGR forms Claude Code
  /// uses (`CSI > 4;2 m` underlined every line, 22 left bold on): the
  /// filter rewrites them first (shellx_core SgrFilter has the list).
  @override
  void write(String data) {
    final filtered = _sgr.filter(data);
    ImeTrace.note('out ${data.length}${_syncOpen ? ' sync' : ''}');
    final opens = _opensSync(filtered);
    // Before the parse: it notifies the views when it is done.
    if (opens == true) _beginSync();
    super.write(filtered);
    if (opens == false) _endSync();
  }

  /// Longest a synchronized-output frame (`CSI ? 2026 h`) may stay unshown
  /// when its `l` never comes (the spec's own fallback is of this order).
  static const Duration syncOutputTimeout = Duration(milliseconds: 150);

  bool _syncOpen = false;
  bool _syncPending = false;
  Timer? _syncTimer;

  /// Synchronized output (`CSI ? 2026 h` ... `l`, which Claude Code wraps
  /// every frame in): xterm 4.0.0 ignores the mode and notifies its views
  /// after every pty read, and a frame spans several reads. Each of those
  /// notifications makes the terminal view send the input method a new caret
  /// rectangle (`TextInput.setCaretRect`/`setEditableSizeAndTransform`) at
  /// whatever row the half-drawn frame has the cursor on; on macOS every one
  /// reaches IMKit while a Vietnamese word is composed. Holding the
  /// notification until the frame is complete sends one, for where the
  /// frame ended. Also what the mode is for: no half-drawn frames on screen.
  /// true: the chunk leaves a frame open; false: it ends one; null: neither.
  bool? _opensSync(String data) {
    final h = data.lastIndexOf('\x1b[?2026h');
    final l = data.lastIndexOf('\x1b[?2026l');
    if (h < 0 && l < 0) return null;
    return h > l;
  }

  void _beginSync() {
    _syncOpen = true;
    _syncTimer ??= Timer(syncOutputTimeout, _endSync);
  }

  void _endSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _syncOpen = false;
    if (_syncPending) {
      _syncPending = false;
      super.notifyListeners();
    }
  }

  @override
  void notifyListeners() {
    if (_syncOpen) {
      _syncPending = true;
      return;
    }
    super.notifyListeners();
  }

  /// A10 D11: where the program put OSC 8 links.
  final hyperlinks = HyperlinkRegistry();

  // The ranges are anchors of one buffer; a screen switch (vim, less)
  // drops them rather than point them at the other screen's lines. (xterm
  // 4.0.0 has no RIS, ESC c, to handle.)
  @override
  void useAltBuffer() {
    hyperlinks.clear();
    super.useAltBuffer();
  }

  @override
  void useMainBuffer() {
    hyperlinks.clear();
    super.useMainBuffer();
  }

  bool _wantsCursor = true;
  bool _blinkOn = true;

  /// The program's DECTCEM (`ESC[?25h/l`) is remembered; what xterm draws is
  /// that AND the blink phase.
  @override
  void setCursorVisibleMode(bool enabled) {
    _wantsCursor = enabled;
    super.setCursorVisibleMode(enabled && _blinkOn);
  }

  /// Blinker only: the program's wish is untouched. No `notifyListeners()`
  /// (find, the driver pill and the IME rect listen to the terminal and a
  /// blink is none of their business; theme changes would also clear
  /// xterm's glyph cache): the controller repaints instead.
  void applyBlinkPhase(bool on) {
    if (_blinkOn == on) return;
    _blinkOn = on;
    super.setCursorVisibleMode(_wantsCursor && on);
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

/// [TerminalController] a blink can ask to repaint without touching the
/// terminal (A11 D17).
class DesktopTerminalController extends TerminalController {
  void repaint() => notifyListeners();
}

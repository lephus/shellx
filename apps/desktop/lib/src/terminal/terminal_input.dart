import 'package:xterm/core.dart';

/// Cursor and navigation keys as xterm encodes them.
///
/// xterm.dart 4.0.0's keytab (a) derives application cursor mode from DECKPAM
/// (`ESC =`) instead of DECCKM (`ESC [ ? 1 h`) and (b) encodes Alt/Shift+arrow
/// as Ctrl+arrow and drops Ctrl+Alt+arrow. This handler runs first and fixes
/// both, and sends macOS Option+←/→ at the shell as ESC b / ESC f; every
/// other key falls through to [defaultInputHandler].
final class CursorKeysInputHandler implements TerminalInputHandler {
  const CursorKeysInputHandler();

  @override
  String? call(TerminalKeyboardEvent event) {
    final letter = switch (event.key) {
      TerminalKey.arrowUp => 'A',
      TerminalKey.arrowDown => 'B',
      TerminalKey.arrowRight => 'C',
      TerminalKey.arrowLeft => 'D',
      TerminalKey.home => 'H',
      TerminalKey.end => 'F',
      _ => null,
    };
    if (letter == null) return null;
    // macOS: Option+←/→ alone at the shell (main screen) moves by word,
    // as Terminal.app and iTerm2 send it: ESC b / ESC f, which readline,
    // zle and fish all bind. Full-screen programs get the xterm form.
    if (event.platform == TerminalTargetPlatform.macos &&
        event.alt &&
        !event.shift &&
        !event.ctrl &&
        !event.altBuffer &&
        (letter == 'D' || letter == 'C')) {
      return letter == 'D' ? '\x1bb' : '\x1bf';
    }
    final modifier =
        1 + (event.shift ? 1 : 0) + (event.alt ? 2 : 0) + (event.ctrl ? 4 : 0);
    if (modifier > 1) return '\x1b[1;$modifier$letter';
    return event.state.cursorKeysMode ? '\x1bO$letter' : '\x1b[$letter';
  }
}

/// Input handler of every desktop terminal: the cursor-key fix first, then
/// xterm's defaults.
const TerminalInputHandler desktopInputHandler = CascadeInputHandler([
  CursorKeysInputHandler(),
  defaultInputHandler,
]);

/// Control characters typed or pasted text must never carry: ESC and every
/// other C0 control except tab, LF and CR, DEL, and the C1 range
/// (U+0080–U+009F, which includes the 8-bit CSI U+009B).
final RegExp _unsafeControls = RegExp(
  '[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F\\x7F\\u0080-\\u009F]',
);

/// The Return key of a soft keyboard arrives as "\n"; terminals send CR.
///
/// Also strips [_unsafeControls]: `TerminalView._onInsert` feeds IME commit
/// text and the Gboard clipboard chip through `Terminal.textInput` with no
/// sanitising of its own, so untrusted IME text could otherwise inject a
/// bracketed-paste-end marker or other escape sequence the same way a
/// malicious clipboard paste could (see [normalizePastedText]). Runs before
/// [applyModifiersToText], so a sticky Ctrl still maps the character that
/// follows.
String normalizeTypedText(String text) =>
    text.replaceAll(_unsafeControls, '').replaceAll('\n', '\r');

/// Makes clipboard text safe to send as a paste: control characters are
/// stripped and line breaks become CR, like xterm and iTerm2 do.
///
/// Stripping ESC is what keeps bracketed paste honest: a clipboard holding
/// `ESC[201~` would otherwise end the paste early, and whatever follows it
/// would run as typed input (pastejacking). Without bracketed paste, an ESC
/// would still let the paste inject key sequences, so this applies in both
/// modes.
String normalizePastedText(String text) => text
    .replaceAll(_unsafeControls, '')
    .replaceAll('\r\n', '\r')
    .replaceAll('\n', '\r');

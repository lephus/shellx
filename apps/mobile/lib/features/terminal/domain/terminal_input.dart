import 'package:xterm/core.dart';

/// Cursor and navigation keys as xterm encodes them.
///
/// xterm.dart 4.0.0's keytab (a) derives application cursor mode from DECKPAM
/// (`ESC =`) instead of DECCKM (`ESC [ ? 1 h`) and (b) encodes Alt/Shift+arrow
/// as Ctrl+arrow and drops Ctrl+Alt+arrow. This handler runs first and fixes
/// both; every other key falls through to [defaultInputHandler].
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
    final modifier = 1 + (event.shift ? 1 : 0) + (event.alt ? 2 : 0) + (event.ctrl ? 4 : 0);
    if (modifier > 1) return '\x1b[1;$modifier$letter';
    return event.state.cursorKeysMode ? '\x1bO$letter' : '\x1b[$letter';
  }
}

/// Input handler for every ShellX terminal.
const TerminalInputHandler shellxInputHandler = CascadeInputHandler([CursorKeysInputHandler(), defaultInputHandler]);

/// Ctrl+[char] → the C0 control character xterm sends, or null when there is none.
String? controlCharacterFor(String char) {
  if (char.length != 1) return null;
  final code = char.codeUnitAt(0);
  if (code >= 0x61 && code <= 0x7a) return String.fromCharCode(code - 0x60); // a..z
  if (code >= 0x40 && code <= 0x5f) return String.fromCharCode(code - 0x40); // @ A..Z [ \ ] ^ _
  if (code == 0x20) return '\x00'; // Ctrl+Space
  if (code == 0x2f) return '\x1f'; // Ctrl+/
  if (code == 0x3f) return '\x7f'; // Ctrl+?
  return null;
}

/// Applies Ctrl/Alt to the first character of typed [text]: Ctrl maps to a
/// control character, Alt prefixes ESC (xterm "metaSendsEscape").
String applyModifiersToText(String text, {required bool ctrl, required bool alt}) {
  if (text.isEmpty || (!ctrl && !alt)) return text;
  final first = String.fromCharCode(text.runes.first);
  final rest = text.substring(first.length);
  var head = ctrl ? (controlCharacterFor(first) ?? first) : first;
  if (alt) head = '\x1b$head';
  return '$head$rest';
}

/// The Return key of a soft keyboard arrives as "\n"; terminals send CR.
String normalizeTypedText(String text) => text.replaceAll('\n', '\r');

/// Control characters a paste must never carry: ESC and every other C0
/// control except tab, LF and CR, DEL, and the C1 range (U+0080–U+009F,
/// which includes the 8-bit CSI U+009B).
final RegExp _pasteControls = RegExp('[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F\\x7F\\u0080-\\u009F]');

/// Makes clipboard text safe to send as a paste: control characters are
/// stripped and line breaks become CR, like xterm and iTerm2 do.
///
/// Stripping ESC is what keeps bracketed paste honest: a clipboard holding
/// `ESC[201~` would otherwise end the paste early, and whatever follows it
/// would run as typed input (pastejacking). Without bracketed paste, an ESC
/// would still let the paste inject key sequences, so this applies in both
/// modes.
String normalizePastedText(String text) =>
    text.replaceAll(_pasteControls, '').replaceAll('\r\n', '\r').replaceAll('\n', '\r');

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

/// Pasted line breaks become CR, like xterm and iTerm2 do.
String normalizePastedText(String text) => text.replaceAll('\r\n', '\r').replaceAll('\n', '\r');

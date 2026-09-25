import 'package:flutter/painting.dart';
import 'package:xterm/xterm.dart';

/// Terminal colours of the ShellX design (`--t-*`): the terminal is dark in both app themes.
abstract final class TerminalColors {
  static const Color background = Color(0xFF0B1215);
  static const Color chrome = Color(0xFF111B1E);
  static const Color chrome2 = Color(0xFF1A272B);
  static const Color line = Color(0xFF243337);
  static const Color foreground = Color(0xFFD4E1E4);
  static const Color dim = Color(0xFF6C8288);
  static const Color title = Color(0xFFE8F0F2);
  static const Color green = Color(0xFF7ED492);
  static const Color cyan = Color(0xFF5FD4E2);
  static const Color yellow = Color(0xFFE9C46A);
  static const Color red = Color(0xFFF07178);
  static const Color blue = Color(0xFF82AAFF);
  static const Color magenta = Color(0xFFC792EA);

  /// "Đóng tab" on the session-ended card.
  static const Color secondaryAction = Color(0xFF23353A);

  /// Text on a cyan button.
  static const Color onCyan = Color(0xFF05282D);

  /// Floating notice (e.g. `session_limit`).
  static const Color noticeBackground = Color(0xFF2A1416);
  static const Color noticeText = Color(0xFFFFD9DB);
  static const Color noticeBorder = Color(0xFF5A2A2E);

  /// ANSI palette for xterm.
  static const TerminalTheme theme = TerminalTheme(
    cursor: foreground,
    selection: Color(0x665FD4E2),
    foreground: foreground,
    background: background,
    black: chrome2,
    red: red,
    green: green,
    yellow: yellow,
    blue: blue,
    magenta: magenta,
    cyan: cyan,
    white: foreground,
    brightBlack: dim,
    brightRed: Color(0xFFFF8F95),
    brightGreen: Color(0xFF9BE3AB),
    brightYellow: Color(0xFFF2D68C),
    brightBlue: Color(0xFFA5C2FF),
    brightMagenta: Color(0xFFDAB3F1),
    brightCyan: Color(0xFF8FE3EC),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: yellow,
    searchHitBackgroundCurrent: cyan,
    searchHitForeground: background,
  );
}

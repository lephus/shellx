import 'package:flutter/painting.dart';

/// V2-5a A24, §5.7: the default "ShellX" terminal palette and the phone's
/// terminal chrome, dark in both phone modes. The colours only: each app
/// builds its own xterm `TerminalTheme` from them (the package does not
/// depend on xterm). A user's own theme keeps its colours; a key it leaves
/// out takes these.
abstract final class ShellxTerminalPalette {
  /// The desktop's `bgTerminal`.
  static const Color background = Color(0xFF1C222E);
  static const Color foreground = Color(0xFFDDE3EC);
  static const Color cursor = foreground;

  /// Cyan 30 %.
  static const Color selection = Color(0x4D34C8E8);

  // ANSI 0–7.
  /// A visible block on [background] (1.30:1).
  static const Color black = Color(0xFF2C3547);
  static const Color red = Color(0xFFF07178);
  static const Color green = Color(0xFF7ED492);
  static const Color yellow = Color(0xFFE9C46A);
  static const Color blue = Color(0xFF82AAFF);
  static const Color magenta = Color(0xFFC792EA);
  static const Color cyan = Color(0xFF5FD4E2);
  static const Color white = foreground;

  // ANSI 8–15.
  /// 4.96:1 on [background] (the old `#6C8288` is 3.94:1 there).
  static const Color brightBlack = Color(0xFF8590A6);
  static const Color brightRed = Color(0xFFFF8F95);
  static const Color brightGreen = Color(0xFF9BE3AB);
  static const Color brightYellow = Color(0xFFF2D68C);
  static const Color brightBlue = Color(0xFFA5C2FF);
  static const Color brightMagenta = Color(0xFFDAB3F1);
  static const Color brightCyan = Color(0xFF8FE3EC);
  static const Color brightWhite = Color(0xFFFFFFFF);

  static const Color searchHitBackground = yellow;
  static const Color searchHitBackgroundCurrent = cyan;
  static const Color searchHitForeground = background;

  // The phone's terminal chrome.
  static const Color chrome = Color(0xFF242C3B);
  static const Color chrome2 = Color(0xFF2C3547);

  /// Lines in the chrome (solid).
  static const Color line = Color(0xFF343944);

  /// Decoration only.
  static const Color dim = Color(0xFF767A81);

  /// Secondary text on the chrome: 5.96:1 on [chrome], 5.23:1 on [chrome2].
  static const Color muted = Color(0xFFA7A9AE);
  static const Color title = Color(0xFFFFFFFF);

  /// "Đóng tab" on the session-ended card.
  static const Color secondaryAction = Color(0xFF323B4F);

  /// Text on a [cyan] button.
  static const Color onCyan = Color(0xFF0E1A26);

  /// A floating notice (`session_limit`).
  static const Color noticeBackground = Color(0xFF453F50);
  static const Color noticeText = Color(0xFFFFD9DB);
  static const Color noticeBorder = Color(0xFF5F4959);

  /// "Máy tính đang dùng terminal này" over a desktop terminal (text:
  /// [yellow]).
  static const Color driverBannerBackground = Color(0xFF3B3937);
  static const Color driverBannerBorder = Color(0xFF554B3A);
}

import 'package:flutter/painting.dart';

/// V2-5a §5.3, §5.6: the dark palette both apps share (the desktop, and the
/// phone in dark mode). Navy layers from the reference, text as solid
/// colours (white 100/87/75/60/50/38 % over the page, A18) so contrast can
/// be computed on any surface, hairlines as alpha (A19).
abstract final class ShellxPalette {
  // Navy layers (A17), darkest first.
  /// Inset: fields, tracks, the terminal, the desktop pane.
  static const Color navy900 = Color(0xFF1C222E);

  /// The phone's page; the desktop sidebar.
  static const Color navy850 = Color(0xFF222834);

  /// Bars: the phone's bottom bar and terminal chrome.
  static const Color navy825 = Color(0xFF242C3B);

  /// Hover on the page; pushed (a pressed raised element).
  static const Color navy800 = Color(0xFF28303F);

  /// Surfaces: cards, sheets, dialogs, menus, toasts.
  static const Color navy750 = Color(0xFF2C3547);

  /// Raised or selected; tooltips.
  static const Color navy700 = Color(0xFF323B4F);

  /// Pressed on the page; hover on a surface.
  static const Color navy650 = Color(0xFF38445A);

  /// Pressed on a surface.
  static const Color navy600 = Color(0xFF3F4B62);

  // Text (A18): solid, never alpha.
  static const Color white100 = Color(0xFFFFFFFF);
  static const Color white87 = Color(0xFFE2E3E5);
  static const Color white75 = Color(0xFFCACCD1);
  static const Color white60 = Color(0xFFA7A9AE);

  /// Placeholder, on [navy900] only.
  static const Color white50 = Color(0xFF8E9096);

  /// Decoration only, never text.
  static const Color white38 = Color(0xFF767A81);

  // Lines (A19).
  /// Dividers: white 8 %.
  static const Color hairline = Color(0x14FFFFFF);

  /// Decorative borders: white 10 %.
  static const Color hairlineStrong = Color(0x1AFFFFFF);

  /// A sheet's drag handle: white 20 %.
  static const Color handle = Color(0x33FFFFFF);

  /// A field's outline: solid, ≥ 3:1 on inset, page and surface.
  static const Color fieldOutline = Color(0xFF76829C);

  // Accents (A21, A22).
  /// The single accent: focus, selection bar, running dot, an icon that is
  /// on, progress.
  static const Color cyan = Color(0xFF34C8E8);

  /// Ink on [cyan].
  static const Color onCyan = Color(0xFF0E1A26);

  /// Tinted background: badges, a selected list item.
  static const Color cyanSoft = Color(0xFF253E4D);

  /// Decoration, or text from 18 px on the page.
  static const Color azure = Color(0xFF3D9CEA);

  /// Links and text buttons.
  static const Color link = Color(0xFF5EADEE);

  /// Text and icons on a gradient.
  static const Color onAccent = Color(0xFFFFFFFF);

  // Gradient stops (A20, A30).
  static const Color accentLight = Color(0xFF1A9BD8);
  static const Color accentStrongLight = Color(0xFF157CAD);
  static const Color indigo = Color(0xFF4E4AF2);
  static const Color wedgeBottom = Color(0xFF3C65CF);

  // Status (§5.6).
  /// Also the online dot.
  static const Color ok = Color(0xFF5ED39C);
  static const Color okSoft = Color(0xFF293D40);
  static const Color warn = Color(0xFFF5B94E);
  static const Color warnSoft = Color(0xFF3B3937);
  static const Color warnLine = Color(0xFF554B3A);
  static const Color error = Color(0xFFFF8A94);
  static const Color errorSoft = Color(0xFF3D3440);
  static const Color onError = Color(0xFF2A0A0C);
  static const Color errorHover = Color(0xFFFF98A1);
  static const Color noticeBg = Color(0xFF453F50);
  static const Color noticeText = Color(0xFFFFD9DB);
  static const Color noticeLine = Color(0xFF5F4959);
  static const Color inProgress = Color(0xFF6EA8FE);

  // Others.
  /// Behind dialogs and sheets.
  static const Color scrim = Color(0x99000000);
  static const Color scrollThumb = Color(0xFF3D424C);
  static const Color scrollThumbHover = Color(0xFF4E535D);

  /// The phone's extra-keys bar follows the system keyboard (as before).
  static const Color keyboardBackground = Color(0xFF1E1F21);
  static const Color keyboardKey = Color(0xFF47484B);
  static const Color keyboardInk = Color(0xFFFFFFFF);

  /// Glass ([navy700] at 80 %, A29).
  static const Color glassFill = Color(0xCC323B4F);
}

/// V2-5a §5.4: the phone's light variant, same navy and azure hues (A25).
abstract final class ShellxLightPalette {
  static const Color page = Color(0xFFEAEFF5);
  static const Color surface = Color(0xFFF5F7FA);
  static const Color raised = Color(0xFFFFFFFF);

  /// Inset and fields; also pushed.
  static const Color inset = Color(0xFFE0E6EE);
  static const Color text = Color(0xFF141A26);
  static const Color textSecondary = Color(0xFF4E586B);

  /// On [inset].
  static const Color placeholder = Color(0xFF596376);

  /// Dividers and decorative borders: navy 10 %.
  static const Color hairline = Color(0x1A141A26);
  static const Color handle = Color(0x33141A26);
  static const Color fieldOutline = Color(0xFF717C92);

  /// Solid: links, an icon that is on, focus, the key accent.
  static const Color primary = Color(0xFF1767AD);
  static const Color primarySoft = Color(0xFFDCE8F3);
  static const Color ok = Color(0xFF256B45);
  static const Color okDot = Color(0xFF2E8A57);
  static const Color okSoft = Color(0xFFE9F0EC);
  static const Color warn = Color(0xFF7F4C00);
  static const Color warnSoft = Color(0xFFF2EDE6);
  static const Color error = Color(0xFFB0202B);
  static const Color errorSoft = Color(0xFFF7E9EA);
  static const Color scrim = Color(0x73141A26);
  static const Color keyboardBackground = Color(0xFFD1D4DA);
  static const Color keyboardKey = Color(0xFFFFFFFF);
  static const Color keyboardInk = Color(0xFF000000);
  static const Color keyboardLink = Color(0xFF14598F);
  static const Color keyboardError = Color(0xFFA3161D);
  static const Color glassFill = Color(0xCCFFFFFF);
  static const Color glassBorder = Color(0x14141A26);
}

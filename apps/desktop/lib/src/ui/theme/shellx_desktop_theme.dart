import 'package:flutter/material.dart';

/// UI §1.1. One dark theme for the whole window (A1 has no light theme).
abstract final class ShellxDesktopColors {
  static const Color bgTerminal = Color(0xFF0B1215);
  static const Color bgSidebar = Color(0xFF111B1E);
  static const Color rowHover = Color(0xFF172427);
  static const Color rowSelected = Color(0xFF1A272B);
  static const Color rowPressed = Color(0xFF203034);
  static const Color line = Color(0xFF243337);
  static const Color surface = Color(0xFF172023);
  static const Color surfaceInset = Color(0xFF0D1315);
  static const Color border = Color(0xFF2B373A);
  static const Color borderInput = Color(0xFF5E7176);
  static const Color textPrimary = Color(0xFFD4E1E4);
  static const Color textTitle = Color(0xFFE8F0F2);
  static const Color textSecondary = Color(0xFF93A5A9);
  static const Color textDialog2 = Color(0xFFA7B6BA);
  static const Color textPlaceholder = Color(0xFF6F8186);

  /// Decorative only (UI §1.1): never body text on the sidebar.
  static const Color dim = Color(0xFF6C8288);
  static const Color accent = Color(0xFF5FD4E2);
  static const Color primary = Color(0xFF2DBFCF);
  static const Color onPrimary = Color(0xFF04282D);
  static const Color primarySoft = Color(0xFF0E363C);
  static const Color ok = Color(0xFF7ED492);
  static const Color warn = Color(0xFFE9C46A);
  static const Color warnBg = Color(0xFF2A2412);
  static const Color warnBorder = Color(0xFF4A3F1C);
  static const Color err = Color(0xFFF07178);
  static const Color errDialog = Color(0xFFF26A70);
  static const Color onErr = Color(0xFF2A0A0C);
  static const Color noticeBg = Color(0xFF2A1416);
  static const Color noticeText = Color(0xFFFFD9DB);
  static const Color noticeBorder = Color(0xFF5A2A2E);
  static const Color scrim = Color(0x99000000);
  static const Color scrollThumb = Color(0xFF2B373A);
  static const Color scrollThumbHover = Color(0xFF3A4A4E);

  /// UI §3.3 button states.
  static const Color primaryHover = Color(0xFF4CCAD8);
  static const Color primaryPressed = Color(0xFF26A9B8);
  static const Color destructiveHover = Color(0xFFF4848A);

  /// UI §3: disabled = 38 % opacity.
  static const double disabledOpacity = 0.38;
}

/// UI §1.2 spacing scale (px).
abstract final class ShellxSpace {
  static const double s2 = 2, s4 = 4, s6 = 6, s8 = 8, s12 = 12;
  static const double s16 = 16, s20 = 20, s24 = 24, s32 = 32;
}

/// UI §1.2 radii.
abstract final class ShellxRadius {
  static const double r4 = 4, r6 = 6, r8 = 8, r12 = 12, pill = 999;
}

/// UI §1.2 fixed sizes, §2 window, §2.2 sidebar, §2.5 pill, §2.8 toast,
/// §4 dialogs.
abstract final class ShellxSizes {
  static const double sidebarWidth = 220;
  static const double row = 30;
  static const double rowGap = 2;
  static const double headerBandMac = 38;
  static const double headerBandWindows = 36;
  static const double paneHeaderMac = 28;
  static const double signedOutStrip = 36;
  static const double driverPill = 28;
  static const double button = 32;
  static const double input = 36;
  static const double icon = 16;
  static const double iconHit = 28;
  static const double mark = 14;
  static const double dot = 8;
  static const double trafficLightsInset = 80;
  static const double listMarginH = 6;
  static const double listTop = 4;
  static const double listBottom = 8;
  static const Size minWindow = Size(640, 400);
  static const Size defaultWindow = Size(1100, 720);
  static const double dialogWidth = 400;
  static const double dialogWidthOnboarding = 480;
  static const double dialogWidthLong = 520;
  static const double toastMaxWidth = 420;
  static const double toastMinHeight = 36;
  static const double pillMaxWidth = 560;
  static const double emptyMaxWidth = 320;
  static const EdgeInsets terminalPadding = EdgeInsets.fromLTRB(10, 6, 10, 6);

  /// UI §2.1: macOS header content sits on the traffic-light centre line.
  static const double trafficLightsCenterY = 14;

  /// UI §2.1: the pane header title takes at most 60 % of the pane.
  static const double paneHeaderTitleFactor = 0.6;

  /// UI §1.3: row height grows with the text scale: max(30, 18·s + 12).
  static const double rowTextLine = 18;
  static const double rowTextPadding = 12;

  /// UI §2.2 tab row: dot slot, selected bar (2 × 16).
  static const double dotSlot = 16;
  static const double dotRing = 1.5;
  static const double selectedBarWidth = 2;
  static const double selectedBarHeight = 16;

  /// UI §2.2 overlay scrollbar.
  static const double scrollbarThickness = 6;
  static const double scrollbarRadius = 3;
  static const double scrollbarMargin = 2;

  /// UI §3 focused state: 2 px accent ring inside the radius.
  static const double focusRing = 2;

  /// UI §3.2 `+`: 28 hit, 24 visual; busy spinner 12, stroke 1.5.
  static const double iconVisual = 24;
  static const double spinner = 12;
  static const double spinnerStroke = 1.5;

  /// UI §3.3 buttons: min width 80, padding 0/14; text button 28 high,
  /// padding 0/10.
  static const double buttonMinWidth = 80;
  static const double buttonPaddingH = 14;
  static const double textButton = 28;
  static const double textButtonPaddingH = 10;

  /// UI §3.1 context menu: min width 180, item 28 high, padding 0/10.
  static const double menuMinWidth = 180;
  static const double menuItem = 28;
  static const double menuItemPaddingH = 10;

  /// UI §2.8 toast close: 24 × 24 button, 14 glyph.
  static const double toastClose = 24;
  static const double toastCloseGlyph = 14;

  /// UI §2.7 empty-state icon.
  static const double emptyIcon = 32;
}

/// UI §1.3. No fontFamily: the platform UI font (SF Pro / Segoe UI).
abstract final class ShellxText {
  static const TextStyle caption = TextStyle(
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w500,
  );
  static const TextStyle small = TextStyle(fontSize: 12, height: 16 / 12);
  static const TextStyle body = TextStyle(fontSize: 13, height: 18 / 13);
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle dialogBody = TextStyle(fontSize: 14, height: 20 / 14);
  static const TextStyle label = TextStyle(
    fontSize: 12.5,
    height: 16 / 12.5,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle dialogTitle = TextStyle(
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle emptyTitle = TextStyle(
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w600,
  );
}

/// UI §1.4.
abstract final class ShellxShadows {
  static const List<BoxShadow> e1 = [
    BoxShadow(offset: Offset(0, 4), blurRadius: 16, color: Color(0x73000000)),
  ];

  /// [e1] for Material surfaces that only take an elevation (the context
  /// menu of `showMenu`): a shadow of about the same offset and blur.
  static const double e1Elevation = 8;
  static const Color e1ShadowColor = Color(0x73000000);
  static const List<BoxShadow> e2 = [
    BoxShadow(offset: Offset(0, 16), blurRadius: 48, color: Color(0x8C000000)),
  ];
}

/// UI §1.5. Use [of] so reduced motion turns every duration to zero.
abstract final class ShellxMotion {
  static const Duration fast = Duration(milliseconds: 80);
  static const Duration base = Duration(milliseconds: 150);
  static const Duration exit = Duration(milliseconds: 120);
  static const Duration toastIn = Duration(milliseconds: 160);
  static const Duration toastVisible = Duration(seconds: 4);
  static const Duration toastVisibleError = Duration(seconds: 6);
  static const Duration tooltipWait = Duration(milliseconds: 500);
  static const Duration scrollbarFade = Duration(milliseconds: 800);
  static const Curve fastCurve = Curves.easeOut;
  static const Curve baseCurve = Curves.easeOutCubic;
  static const Curve exitCurve = Curves.easeIn;

  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

/// The window's only theme (replaces `colorSchemeSeed` in app.dart).
ThemeData buildDesktopTheme() {
  const colors = ColorScheme.dark(
    primary: ShellxDesktopColors.primary,
    onPrimary: ShellxDesktopColors.onPrimary,
    secondary: ShellxDesktopColors.accent,
    surface: ShellxDesktopColors.surface,
    onSurface: ShellxDesktopColors.textPrimary,
    error: ShellxDesktopColors.errDialog,
    onError: ShellxDesktopColors.onErr,
    outline: ShellxDesktopColors.borderInput,
    outlineVariant: ShellxDesktopColors.border,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colors,
    scaffoldBackgroundColor: ShellxDesktopColors.bgTerminal,
    dividerColor: ShellxDesktopColors.line,
    dividerTheme: const DividerThemeData(
      color: ShellxDesktopColors.line,
      thickness: 1,
      space: 1,
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: ShellxMotion.tooltipWait,
      textStyle: TextStyle(
        fontSize: 12,
        height: 16 / 12,
        color: ShellxDesktopColors.textPrimary,
      ),
      decoration: BoxDecoration(
        color: ShellxDesktopColors.rowSelected,
        borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r6)),
        border: Border.fromBorderSide(
          BorderSide(color: ShellxDesktopColors.border),
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: ShellxDesktopColors.surfaceInset,
      hintStyle: TextStyle(color: ShellxDesktopColors.textPlaceholder),
      labelStyle: TextStyle(color: ShellxDesktopColors.textDialog2),
      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r6)),
        borderSide: BorderSide(color: ShellxDesktopColors.borderInput),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r6)),
        borderSide: BorderSide(color: ShellxDesktopColors.accent),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r6)),
        borderSide: BorderSide(color: ShellxDesktopColors.errDialog),
      ),
    ),
  );
}

import 'dart:math';

import 'package:flutter/material.dart';

/// UI §1.1. One dark theme for the whole window (A1 has no light theme).
abstract final class ShellxDesktopColors {
  static const Color bgTerminal = Color(0xFF0B1215);
  static const Color bgSidebar = Color(0xFF111B1E);
  static const Color rowHover = Color(0xFF172427);

  /// 1.26:1 on `bgSidebar` (S-7: the selected row reads at a glance);
  /// hover stays darker, pressed lighter.
  static const Color rowSelected = Color(0xFF1F2F34);
  static const Color rowPressed = Color(0xFF26393E);
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
  // A11 D18: the tab status "in progress".
  static const Color statusInProgress = Color(0xFF6EA8FE);
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

  // A6 (UI-A6 §1.2). The minimum equals the browser pane's `kBrowserMinSize`.
  static const double browserToolbar = 32;
  static const double browserToolbarPadH = 6;
  static const double browserButton = 28;
  static const double browserButtonGap = 2;
  static const double browserAddressHeight = 24;
  static const double browserAddressPadH = 8;
  static const double browserOriginIcon = 14;
  static const double browserProgress = 2;
  static const double browserMinWidth = 240; // == kBrowserMinSize.width
  static const double browserMinHeight = 160; // == kBrowserMinSize.height
  static const double browserAgentMark = 20;
  static const double browserErrorMaxWidth = 420;

  // A8 (UI-A8 §1.2).
  static const double remoteMark = 12;
  static const double remoteMarkGap = 2;
  static const double connectingDot = 4;
  static const double remoteStrip = 32;
  static const double remoteStripPadH = 8;
  static const double remoteStripButton = 24;
  static const double connectDialogWidth = 520;
  static const double connectTabBar = 32;
  static const double suggestionRow = 28;
  static const double tmuxRow = 40;
  static const int suggestionListMax = 8;

  /// UI-A8 §1.3: the strip grows with the text scale.
  static double remoteStripFor(TextScaler scaler) =>
      max(remoteStrip, scaler.scale(18) + 14);

  static const double row = 30;
  static const double rowGap = 2;
  static const double headerBandMac = 38;
  static const double headerBandWindows = 36;
  static const double paneHeaderMac = 28;
  static const double signedOutStrip = 36;

  /// UI-A5 §4: a strip over the terminal grows with the text scale:
  /// max(36, 18·s + 18).
  static double infoStripFor(TextScaler scaler) =>
      max(signedOutStrip, scaler.scale(rowTextLine) + rowTextLine);
  static const double driverPill = 28;
  static const double button = 32;
  static const double input = 36;

  // A3 (UI-A3 §1.2).
  static const double paneDivider = 1;
  static const double paneDividerHit = 6;
  static const double paneHeader = 22;
  static const double paneHeaderPadH = 8;
  static const double paneHeaderDot = 6;
  static const double paneHeaderClose = 18;
  static const double paneFocusOutline = 1;

  /// Final ruling S-1: the divider while hovered or dragged (paint only;
  /// the layout line stays [paneDivider]).
  static const double paneDividerActive = 3;

  /// Final ruling S-3: an unfocused pane's ring sits this far inside the
  /// pane, clear of a neighbour's focus outline.
  static const double paneRingInset = 2;
  static const int paneMinCols = 20;
  static const int paneMinRows = 5;
  static const double paneResizeStep = 0.05;
  static const double paneCountIcon = 12;
  static const double paneCountGap = 2;

  /// A7 D27 (A6 UI §2.1): the "Agent" chip on a sidebar row and on a pane
  /// header — height, icon and side padding.
  static const double agentChipRowHeight = 16;
  static const double agentChipPaneHeight = 20;
  static const double agentChipRowIcon = 12;
  static const double agentChipPaneIcon = 14;
  static const double agentChipRowPadH = 6;
  static const double agentChipPanePadH = 8;

  // A12 D12: the agent status badge (a row's, a pane header's).
  static const double agentBadgeRowIcon = 12;
  static const double agentBadgePaneIcon = 14;

  /// A row narrower than this shows the badge's icon only.
  static const double agentBadgeCompactBelow = 160;

  /// UI-A3 §1.3.
  static double paneHeaderFor(TextScaler scaler) =>
      max(paneHeader, scaler.scale(16) + 6);

  /// UI §3.4 field padding (0/10 around a 20 px line: 36 high) and the
  /// label above it.
  static const double inputPaddingH = 10;
  static const double inputPaddingV = 8;
  static const double labelGap = 6;
  static const double fieldGap = 16;
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

  /// The `dialogTitle` line (17/22), for centring the Windows close button.
  static const double dialogTitleLine = 22;
  static const double toastMaxWidth = 420;
  static const double toastMinHeight = 36;
  static const double pillMaxWidth = 560;

  /// UI §2.5: below this pane width the pill uses the short copy.
  static const double pillCompactBelow = 520;

  /// Final ruling S-4: below this pane width the pill is its icon only.
  static const double pillIconOnlyBelow = 260;
  static const double emptyMaxWidth = 320;
  static const EdgeInsets terminalPadding = EdgeInsets.fromLTRB(10, 6, 10, 6);

  /// UI §2.1: macOS header content sits on the traffic-light centre line.
  static const double trafficLightsCenterY = 14;

  /// UI §2.1: the pane header title takes at most 60 % of the pane.
  static const double paneHeaderTitleFactor = 0.6;

  /// UI §1.3: row height grows with the text scale: max(30, 18·s + 12).
  static const double rowTextLine = 18;
  static const double rowTextPadding = 12;

  /// UI §2.2 tab row: dot slot, running dot centre, selected bar (3 × 18;
  /// 1 px clear of the keyboard ring when both show).
  static const double dotSlot = 16;
  static const double dotRing = 1.5;
  static const double dotCentre = 4;
  static const double selectedBarWidth = 3;
  static const double selectedBarHeight = 18;
  static const double selectedBarGap = 1;

  /// UI §2.2 row close button: 24 hit, 20 visual, 14 glyph.
  static const double rowCloseHit = 24;
  static const double rowCloseVisual = 20;
  static const double rowCloseGlyph = 14;

  /// UI §3.1: the full-title tooltip beside the sidebar, at most this wide.
  static const double titleTooltipMaxWidth = 360;

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

  /// UI §3.3 loading button: a 14 px spinner before the label.
  static const double buttonSpinner = 14;

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

  /// UI-A2 §1.2: a row with a context line (6 + 18 + 2 + 14 + 6).
  static const double rowWithContext = 46;
  static const double rowContextPadding = 6;
  static const double contextLine = 14;
  static const double contextGap = 2;
  static const double contextInset = 32;
  static const double portHit = 24;
  static const double portGap = 4;
  static const double portPadH = 2;

  /// UI-A2 §2.1 (V8): the branch glyph before the branch, and its gap.
  static const double branchGlyph = 10;
  static const double branchGlyphGap = 2;

  /// UI-A2 §3 workspace header.
  static const double workspaceHeader = 28;
  static const double workspaceHeaderTop = 8;
  static const double workspaceHeaderText = 16;
  static const double chevronHit = 20;
  static const double headerAddHit = 24;
  static const double headerAddVisual = 20;
  static const double headerCountMin = 16;
  static const double collapsedMarkHeight = 12;
  static const double emptyWorkspaceRow = 30;

  /// UI-A2 §3 (V9): tab rows sit this far right of their header while
  /// headers show, so the tree's depth reads at a glance.
  static const double workspaceRowIndent = 8;

  /// UI-A2 §4, §6.
  static const double renameField = 22;
  static const double dropLine = 2;
  static const double dragAutoScrollZone = 32;
  static const double dragAutoScrollSpeed = 240;

  /// UI-A2 §6 (V1): the drag chip sits this far right of and below the
  /// pointer, at most this wide, and this far from what it would cover.
  static const double dragGhostOffsetX = 12;
  static const double dragGhostOffsetY = 10;
  static const double dragGhostMaxWidth = 208;
  static const double dragGhostClearance = 4;
  static const double menuDivider = 9;

  /// UI-A4 §1.2.
  static const double badgeHeight = 16;
  static const double badgeMinWidth = 16;
  static const double badgePadH = 4;
  static const double badgeGap = 4;
  static const double notificationLine = 14;
  static const double notificationGap = 2;
  static const double notificationIcon = 11;
  static const double notificationIconGap = 4;
  static const double rowWithNotification = 46;
  static const double rowWithNotificationAndContext = 62;
  // A11 D18: description + notification + context.
  static const double rowWithThreeLines = 78;
  static const double tabStatusDot = 8;
  static const double pinIcon = 12;
  static const double ringWidth = 2;
  static const double ringGlowWidth = 1;
  static const double aggregateDot = 6;
  static const double panelWidth = 360;
  static const double panelMaxHeight = 480;
  static const double panelOffsetY = 4;
  static const double panelHeader = 36;

  /// UI-A4 §5.2: the footer line ("Next unread  ⌘⇧U").
  static const double panelFooter = 24;
  static const double panelItem = 52;
  static const double panelUnreadSlot = 16;
  static const double panelEmptyIcon = 24;
  static const double headerBellGap = 4;
  static const double bellDot = 6;

  /// UI-A9 §5: the pending-prefix pill.
  static const double sequenceIndicatorHeight = 28;

  /// UI-A9 §1.2: the palette, the problems panel, the shortcut editor.
  static const double paletteWidth = 560;
  static const double paletteTop = 56;
  static const double paletteMaxHeight = 420;
  static const double paletteRow = 36;
  static const double paletteField = 40;
  static const double problemsWidth = 600;
  static const double problemsMaxHeight = 480;
  static const double problemRow = 52;
  static const double shortcutsWidth = 720;
  static const double shortcutsHeight = 600;
  static const double shortcutsRow = 40;
  static const double keycapHeight = 20;
  static const double keycapGap = 4;
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

  /// UI-A2 §6: hovering a dragged tab over a collapsed header expands it.
  static const Duration dragExpandDelay = Duration(milliseconds: 600);
  static const Curve fastCurve = Curves.easeOut;
  static const Curve baseCurve = Curves.easeOutCubic;
  static const Curve exitCurve = Curves.easeIn;

  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

/// UI §3 focus ring for filled buttons: a ring inside the fill is lost
/// (`accent` on `primary` is 1.27:1), so a 2 px `accent` ring is drawn
/// [gap] px outside the button, over whatever is behind it (≥ 3:1 on
/// `surface` and `bgTerminal`, WCAG 2.4.11).
class OutsideFocusRingBorder extends RoundedRectangleBorder {
  const OutsideFocusRingBorder({super.borderRadius, this.gap = ShellxSpace.s2});

  final double gap;

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final ring = borderRadius
        .resolve(textDirection)
        .toRRect(rect)
        .inflate(gap + ShellxSizes.focusRing / 2);
    canvas.drawRRect(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ShellxSizes.focusRing
        ..color = ShellxDesktopColors.accent,
    );
  }

  @override
  OutsideFocusRingBorder copyWith({
    BorderSide? side,
    BorderRadiusGeometry? borderRadius,
  }) => OutsideFocusRingBorder(
    borderRadius: borderRadius ?? this.borderRadius,
    gap: gap,
  );

  @override
  OutsideFocusRingBorder scale(double t) =>
      OutsideFocusRingBorder(borderRadius: borderRadius * t, gap: gap * t);

  // The button's shape animates between states (`fast`): never through a
  // plain RoundedRectangleBorder, which would drop the ring.
  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => t < 0.5 ? a : this;

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => t < 0.5 ? this : b;

  @override
  bool operator ==(Object other) =>
      other is OutsideFocusRingBorder &&
      other.borderRadius == borderRadius &&
      other.gap == gap;

  @override
  int get hashCode => Object.hash(borderRadius, gap);
}

/// `r6` buttons; a filled one ([outsideRing]) shows keyboard focus with
/// [OutsideFocusRingBorder] instead of a ring inside its fill.
WidgetStateProperty<OutlinedBorder> buttonShape({required bool outsideRing}) {
  const radius = BorderRadius.all(Radius.circular(ShellxRadius.r6));
  return WidgetStateProperty.resolveWith(
    (states) => outsideRing && states.contains(WidgetState.focused)
        ? const OutsideFocusRingBorder(borderRadius: radius)
        : const RoundedRectangleBorder(borderRadius: radius),
  );
}

/// [style] in the platform UI font of [theme] (SF Pro / Segoe UI): the
/// [ShellxText] styles carry no family, and a style that replaces the
/// ambient one (button labels, tooltips, text fields) would otherwise fall
/// back to the engine default font.
TextStyle uiFont(TextStyle style, TextTheme theme) {
  final base = theme.bodyMedium;
  return style.copyWith(
    fontFamily: base?.fontFamily,
    fontFamilyFallback: base?.fontFamilyFallback,
  );
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
  final base = ThemeData(
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
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: ShellxDesktopColors.surfaceInset,
      hintStyle: TextStyle(color: ShellxDesktopColors.textPlaceholder),
      // UI §3.4: 36 high (20 px `dialogBody` line + 8 + 8), padding 0/10;
      // the label sits above the field (LabeledField), never inside it.
      isDense: true,
      contentPadding: EdgeInsets.symmetric(
        horizontal: ShellxSizes.inputPaddingH,
        vertical: ShellxSizes.inputPaddingV,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r6)),
        borderSide: BorderSide(color: ShellxDesktopColors.borderInput),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r6)),
        borderSide: BorderSide(color: ShellxDesktopColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r6)),
        borderSide: BorderSide(color: ShellxDesktopColors.accent),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r6)),
        borderSide: BorderSide(color: ShellxDesktopColors.errDialog),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r6)),
        borderSide: BorderSide(color: ShellxDesktopColors.errDialog),
      ),
    ),
    // UI §1.1 dark tokens instead of the stock grey Material switch.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? ShellxDesktopColors.accent
            : ShellxDesktopColors.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? ShellxDesktopColors.primarySoft
            : ShellxDesktopColors.surfaceInset,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? ShellxDesktopColors.accent
            : ShellxDesktopColors.borderInput,
      ),
    ),
  );
  return base.copyWith(
    tooltipTheme: TooltipThemeData(
      waitDuration: ShellxMotion.tooltipWait,
      textStyle: uiFont(
        ShellxText.small.copyWith(color: ShellxDesktopColors.textPrimary),
        base.textTheme,
      ),
      decoration: const BoxDecoration(
        color: ShellxDesktopColors.rowSelected,
        borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r6)),
        border: Border.fromBorderSide(
          BorderSide(color: ShellxDesktopColors.border),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
  );
}

/// UI §3.3 / §4: the legacy pages reused as dialog bodies get their look
/// from this theme (applied by the dialog host only, so the terminal
/// workspace keeps its own explicit styles).
ThemeData buildDialogTheme(ThemeData base, {required bool reduceMotion}) {
  const focusRing = BorderSide(
    color: ShellxDesktopColors.accent,
    width: ShellxSizes.focusRing,
  );
  Color disabled(Color c) =>
      c.withValues(alpha: ShellxDesktopColors.disabledOpacity);
  WidgetStateProperty<Color> fill(Color idle, Color hover, Color pressed) =>
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? disabled(idle)
            : states.contains(WidgetState.pressed)
            ? pressed
            : states.contains(WidgetState.hovered)
            ? hover
            : idle,
      );
  WidgetStateProperty<Color> ink(Color color) =>
      WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.disabled) ? disabled(color) : color,
      );
  final text = base.textTheme;
  ButtonStyle shape({
    required WidgetStateProperty<Color> foreground,
    required WidgetStateProperty<Color> background,
    BorderSide? side,
    bool filled = false,
  }) => ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(
      Size(ShellxSizes.buttonMinWidth, ShellxSizes.button),
    ),
    fixedSize: const WidgetStatePropertyAll(
      Size.fromHeight(ShellxSizes.button),
    ),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: ShellxSizes.buttonPaddingH),
    ),
    shape: buttonShape(outsideRing: filled),
    textStyle: WidgetStatePropertyAll(uiFont(ShellxText.bodyStrong, text)),
    elevation: const WidgetStatePropertyAll(0),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    animationDuration: reduceMotion ? Duration.zero : ShellxMotion.fast,
    foregroundColor: foreground,
    backgroundColor: background,
    // Material reports `focused` only for keyboard focus (UI §3). A filled
    // button draws its ring outside instead ([OutsideFocusRingBorder]).
    side: WidgetStateProperty.resolveWith(
      (states) =>
          !filled && states.contains(WidgetState.focused) ? focusRing : side,
    ),
  );
  TextStyle ui(TextStyle style, Color color) =>
      uiFont(style.copyWith(color: color), text);
  return base.copyWith(
    textTheme: text.copyWith(
      headlineSmall: ui(ShellxText.dialogTitle, ShellxDesktopColors.textTitle),
      titleLarge: ui(ShellxText.dialogTitle, ShellxDesktopColors.textTitle),
      titleMedium: ui(ShellxText.bodyStrong, ShellxDesktopColors.textTitle),
      bodyLarge: ui(ShellxText.dialogBody, ShellxDesktopColors.textTitle),
      bodyMedium: ui(ShellxText.dialogBody, ShellxDesktopColors.textDialog2),
      bodySmall: ui(ShellxText.small, ShellxDesktopColors.textDialog2),
      labelLarge: uiFont(ShellxText.bodyStrong, text),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: shape(
        filled: true,
        foreground: ink(ShellxDesktopColors.onPrimary),
        background: fill(
          ShellxDesktopColors.primary,
          ShellxDesktopColors.primaryHover,
          ShellxDesktopColors.primaryPressed,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: shape(
        foreground: ink(ShellxDesktopColors.textPrimary),
        background: fill(
          Colors.transparent,
          ShellxDesktopColors.rowHover,
          ShellxDesktopColors.rowPressed,
        ),
        side: const BorderSide(color: ShellxDesktopColors.borderInput),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: shape(
        foreground: ink(ShellxDesktopColors.accent),
        background: fill(
          Colors.transparent,
          ShellxDesktopColors.rowHover,
          ShellxDesktopColors.rowPressed,
        ),
      ),
    ),
  );
}

/// UI §3.3 destructive button (closing tabs, signing out, quitting).
ButtonStyle destructiveButtonStyle() => ButtonStyle(
  foregroundColor: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.disabled)
        ? ShellxDesktopColors.onErr.withValues(
            alpha: ShellxDesktopColors.disabledOpacity,
          )
        : ShellxDesktopColors.onErr,
  ),
  backgroundColor: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.disabled)
        ? ShellxDesktopColors.errDialog.withValues(
            alpha: ShellxDesktopColors.disabledOpacity,
          )
        : states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed)
        ? ShellxDesktopColors.destructiveHover
        : ShellxDesktopColors.errDialog,
  ),
);

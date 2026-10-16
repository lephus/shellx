import 'dart:math';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:shellx_design/shellx_design.dart';

/// UI §1.1, V2-5a §5.9. One dark theme for the whole window (A1 has no light
/// theme). The names are the call sites'; every value is the shared
/// package's (no hex here, V2-5a §10.4).
abstract final class ShellxDesktopColors {
  static const Color bgTerminal = ShellxPalette.navy900;
  static const Color bgSidebar = ShellxPalette.navy850;
  static const Color rowHover = ShellxPalette.navy800;

  /// 1.32:1 on `bgSidebar` (S-7: the selected row reads at a glance);
  /// hover stays darker, pressed lighter.
  static const Color rowSelected = ShellxPalette.navy700;
  static const Color rowPressed = ShellxPalette.navy650;

  /// White 8 % (V2-5a A19): never the base of another colour.
  static const Color line = ShellxPalette.hairline;
  static const Color surface = ShellxPalette.navy750;
  static const Color surfaceInset = ShellxPalette.navy900;

  /// White 10 % (V2-5a A19).
  static const Color border = ShellxPalette.hairlineStrong;
  static const Color borderInput = ShellxPalette.fieldOutline;
  static const Color textPrimary = ShellxPalette.white87;
  static const Color textTitle = ShellxPalette.white100;
  static const Color textSecondary = ShellxPalette.white60;
  static const Color textDialog2 = ShellxPalette.white75;
  static const Color textPlaceholder = ShellxPalette.white50;

  /// Decorative only (UI §1.1): never body text on the sidebar.
  static const Color dim = ShellxPalette.white38;
  static const Color accent = ShellxPalette.cyan;
  static const Color primary = ShellxPalette.cyan;
  static const Color onPrimary = ShellxPalette.onCyan;
  static const Color primarySoft = ShellxPalette.cyanSoft;
  static const Color ok = ShellxPalette.ok;
  static const Color warn = ShellxPalette.warn;
  static const Color warnBg = ShellxPalette.warnSoft;
  static const Color warnBorder = ShellxPalette.warnLine;
  static const Color err = ShellxPalette.error;
  // A11 D18: the tab status "in progress".
  static const Color statusInProgress = ShellxPalette.inProgress;
  static const Color errDialog = ShellxPalette.error;
  static const Color onErr = ShellxPalette.onError;
  static const Color noticeBg = ShellxPalette.noticeBg;
  static const Color noticeText = ShellxPalette.noticeText;
  static const Color noticeBorder = ShellxPalette.noticeLine;
  static const Color scrim = ShellxPalette.scrim;
  static const Color scrollThumb = ShellxPalette.scrollThumb;
  static const Color scrollThumbHover = ShellxPalette.scrollThumbHover;

  /// UI §3.3 button states (the primary button is a gradient, V2-5a A50).
  static const Color destructiveHover = ShellxPalette.errorHover;

  /// V2-5a A50: text and icons on a gradient.
  static const Color onAccent = ShellxPalette.onAccent;

  /// V2-5a A21: text buttons, markdown links, buttons on strips.
  static const Color link = ShellxPalette.link;

  /// V2-5a A50: a menu item or a pressable card hovered, pressed.
  static const Color overlayHover = ShellxPalette.navy650;
  static const Color overlayPressed = ShellxPalette.navy600;

  /// V2-5a A28: a raised element while pressed (it loses its shadow).
  static const Color pushed = ShellxPalette.navy800;

  /// UI §3: disabled = 38 % opacity.
  static const double disabledOpacity = 0.38;
}

/// UI §1.2 spacing scale (px), V2-5a §5.8.
abstract final class ShellxSpace {
  static const double s2 = ShellxSpacing.s2, s4 = ShellxSpacing.s4;
  static const double s6 = ShellxSpacing.s6, s8 = ShellxSpacing.s8;
  static const double s12 = ShellxSpacing.s12, s16 = ShellxSpacing.s16;
  static const double s20 = ShellxSpacing.s20, s24 = ShellxSpacing.s24;
  static const double s32 = ShellxSpacing.s32;
}

/// UI §1.2 radii, V2-5a A27: the old names, the new values (`r4` 6, `r6` 10,
/// `r8` 16, `r12` 28).
abstract final class ShellxRadius {
  static const double r4 = ShellxRadii.tiny, r6 = ShellxRadii.control;
  static const double r8 = ShellxRadii.card, r12 = ShellxRadii.sheet;
  static const double pill = ShellxRadii.pill;
}

/// UI §1.2 fixed sizes, §2 window, §2.2 sidebar, §2.5 pill, §2.8 toast,
/// §4 dialogs.
abstract final class ShellxSizes {
  static const double sidebarWidth = 220;

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

/// UI §1.3, V2-5a §6.5: the monospaced scale (SF Mono on macOS, JetBrains
/// Mono on Windows), one size smaller, line heights in px unchanged. No
/// family (the theme gives it) and each weight with its `wght` axis. On
/// Windows, [ShellxTypeScale.desktopWindowsBoost] px larger (A36).
abstract final class ShellxText {
  static TextStyle _on(TextStyle style) =>
      ShellxTypeScale.desktopFor(style, defaultTargetPlatform);

  /// 11/14, 500.
  static TextStyle get caption => _on(ShellxTypeScale.desktopCaption);

  /// 11.5/16.
  static TextStyle get small => _on(ShellxTypeScale.desktopSmall);

  /// 12/18.
  static TextStyle get body => _on(ShellxTypeScale.desktopBody);

  /// 12/18, 600.
  static TextStyle get bodyStrong => _on(ShellxTypeScale.desktopBodyStrong);

  /// 13/20.
  static TextStyle get dialogBody => _on(ShellxTypeScale.desktopDialogBody);

  /// 11.5/16, 600.
  static TextStyle get label => _on(ShellxTypeScale.desktopLabel);

  /// 16/22, 600.
  static TextStyle get dialogTitle => _on(ShellxTypeScale.desktopDialogTitle);

  /// 14/20, 600.
  static TextStyle get emptyTitle => _on(ShellxTypeScale.desktopEmptyTitle);

  /// 22/28, 600: for V2-5b (the AI home greeting).
  static TextStyle get display => _on(ShellxTypeScale.desktopDisplay);
}

/// UI §1.4, V2-5a §5.8.
abstract final class ShellxShadows {
  /// `float1`: menus, toasts, tooltips.
  static const List<BoxShadow> e1 = ShellxElevation.darkFloat1;

  /// [e1] for Material surfaces that only take an elevation (the context
  /// menu of `showMenu`): a shadow of about the same offset and blur.
  static const double e1Elevation = ShellxElevation.float1Elevation;
  static const Color e1ShadowColor = ShellxElevation.float1ShadowColor;

  /// `float2`: dialogs.
  static const List<BoxShadow> e2 = ShellxElevation.darkFloat2;

  /// V2-5a A28: a raised element (`raisedSmall`): a secondary button, the
  /// selected row, the selected segment.
  static const List<BoxShadow> raised = ShellxElevation.darkRaisedSmall;

  /// V2-5a A28: the inner shadow of a track ([ShellxInsetBox]).
  static const ShellxInsetShadow inset = ShellxInsetShadow(
    ShellxElevation.darkInset,
  );
}

/// UI §1.5, V2-5a §5.8. Use [of] so reduced motion turns every duration to
/// zero.
abstract final class ShellxMotion {
  static const Duration fast = ShellxDurations.fast;
  static const Duration base = ShellxDurations.base;
  static const Duration exit = ShellxDurations.exit;
  static const Duration toastIn = ShellxDurations.toastIn;
  static const Duration toastVisible = ShellxDurations.toastVisible;
  static const Duration toastVisibleError = ShellxDurations.toastVisibleError;
  static const Duration tooltipWait = ShellxDurations.tooltipWait;
  static const Duration scrollbarFade = ShellxDurations.scrollbarFade;

  /// V2-5a: a segment's tile sliding to its new place.
  static const Duration slide = ShellxDurations.slide;

  /// UI-A2 §6: hovering a dragged tab over a collapsed header expands it.
  static const Duration dragExpandDelay = ShellxDurations.dragExpandDelay;
  static const Curve fastCurve = ShellxCurves.fast;
  static const Curve baseCurve = ShellxCurves.base;
  static const Curve exitCurve = ShellxCurves.exit;
  static const Curve slideCurve = ShellxCurves.slide;

  static Duration of(BuildContext context, Duration duration) =>
      ShellxDurations.of(context, duration);
}

/// UI §3 focus ring for filled buttons: a ring inside the fill is lost
/// (cyan on the gradient), so a 2 px `accent` ring is drawn [gap] px outside
/// the button, over whatever is behind it (≥ 3:1 on `surface` and
/// `bgTerminal`, WCAG 2.4.11).
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

/// [style] in the UI font of [theme] (SF Mono on macOS, JetBrains Mono on
/// Windows, V2-5a §6.1): the [ShellxText] styles carry no family, and a
/// style that replaces the ambient one (button labels, tooltips, text
/// fields) would otherwise fall back to the engine default font.
TextStyle uiFont(TextStyle style, TextTheme theme) {
  final base = theme.bodyMedium;
  return style.copyWith(
    fontFamily: base?.fontFamily,
    fontFamilyFallback: base?.fontFamilyFallback,
  );
}

/// UI §3: a 2 px `accent` ring inside the radius, keyboard focus only.
const BorderSide _focusRing = BorderSide(
  color: ShellxDesktopColors.accent,
  width: ShellxSizes.focusRing,
);

const BorderRadius _control = BorderRadius.all(
  Radius.circular(ShellxRadius.r6),
);

Color _disabled(Color c) =>
    c.withValues(alpha: c.a * ShellxDesktopColors.disabledOpacity);

WidgetStateProperty<Color> _ink(Color color) => WidgetStateProperty.resolveWith(
  (states) => states.contains(WidgetState.disabled) ? _disabled(color) : color,
);

/// V2-5a A38, §7.1: the gradient primary button. `accentStrong` (desktop
/// labels are 12 px), a white label, black 8 % hovered and 16 % pressed
/// (drawn by the layer: Material's ink would sit under the gradient), 38 %
/// disabled, the keyboard ring outside (S-9). Still a [FilledButton].
ButtonStyle shellxPrimaryButtonStyle() => ButtonStyle(
  shape: buttonShape(outsideRing: true),
  elevation: const WidgetStatePropertyAll(0),
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  foregroundColor: _ink(ShellxDesktopColors.onAccent),
  iconColor: _ink(ShellxDesktopColors.onAccent),
  backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
  backgroundBuilder: shellxGradientLayer(
    gradient: ShellxGradients.accentStrong,
    borderRadius: _control,
    disabledOpacity: ShellxDesktopColors.disabledOpacity,
  ),
  side: const WidgetStatePropertyAll(BorderSide.none),
);

/// V2-5a §7.1: the raised secondary button. `rowSelected` (navy700) with
/// the `raisedSmall` shadow, `overlayHover` hovered; pressed sinks: `pushed`,
/// no shadow. The keyboard ring is inside.
ButtonStyle shellxSecondaryButtonStyle() => ButtonStyle(
  shape: buttonShape(outsideRing: false),
  elevation: const WidgetStatePropertyAll(0),
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  foregroundColor: _ink(ShellxDesktopColors.textPrimary),
  iconColor: _ink(ShellxDesktopColors.textPrimary),
  backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
  backgroundBuilder: (context, states, child) {
    final disabled = states.contains(WidgetState.disabled);
    final pressed = !disabled && states.contains(WidgetState.pressed);
    final fill = disabled
        ? _disabled(ShellxDesktopColors.rowSelected)
        : pressed
        ? ShellxDesktopColors.pushed
        : states.contains(WidgetState.hovered)
        ? ShellxDesktopColors.overlayHover
        : ShellxDesktopColors.rowSelected;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: _control,
        boxShadow: disabled || pressed ? null : ShellxShadows.raised,
      ),
      child: child,
    );
  },
  side: WidgetStateProperty.resolveWith(
    (states) =>
        states.contains(WidgetState.focused) ? _focusRing : BorderSide.none,
  ),
);

/// V2-5a §7.1: the text button. `link`, no fill; `rowHover` hovered,
/// `rowPressed` pressed; the keyboard ring inside.
ButtonStyle shellxTextButtonStyle() => ButtonStyle(
  shape: buttonShape(outsideRing: false),
  elevation: const WidgetStatePropertyAll(0),
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  foregroundColor: _ink(ShellxDesktopColors.link),
  iconColor: _ink(ShellxDesktopColors.link),
  backgroundColor: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.disabled)
        ? Colors.transparent
        : states.contains(WidgetState.pressed)
        ? ShellxDesktopColors.rowPressed
        : states.contains(WidgetState.hovered)
        ? ShellxDesktopColors.rowHover
        : Colors.transparent,
  ),
  side: WidgetStateProperty.resolveWith(
    (states) =>
        states.contains(WidgetState.focused) ? _focusRing : BorderSide.none,
  ),
);

/// The window's only theme (replaces `colorSchemeSeed` in app.dart): the
/// colours of V2-5a §5.9, the family of the platform (§6.1), each text
/// style's `wght` axis set (A35), every Material component themed (A39).
ThemeData buildDesktopTheme() {
  final platform = defaultTargetPlatform;
  const colors = ColorScheme.dark(
    primary: ShellxDesktopColors.primary,
    onPrimary: ShellxDesktopColors.onPrimary,
    primaryContainer: ShellxDesktopColors.primarySoft,
    onPrimaryContainer: ShellxDesktopColors.textTitle,
    secondary: ShellxDesktopColors.accent,
    onSecondary: ShellxDesktopColors.onPrimary,
    surface: ShellxDesktopColors.surface,
    onSurface: ShellxDesktopColors.textPrimary,
    onSurfaceVariant: ShellxDesktopColors.textSecondary,
    surfaceContainerLowest: ShellxPalette.navy900,
    surfaceContainerLow: ShellxPalette.navy850,
    surfaceContainer: ShellxPalette.navy750,
    surfaceContainerHigh: ShellxPalette.navy750,
    surfaceContainerHighest: ShellxPalette.navy700,
    surfaceTint: Colors.transparent,
    error: ShellxDesktopColors.errDialog,
    onError: ShellxDesktopColors.onErr,
    outline: ShellxDesktopColors.borderInput,
    outlineVariant: ShellxDesktopColors.border,
    scrim: ShellxDesktopColors.scrim,
  );
  OutlineInputBorder field(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(ShellxRadii.card)),
        borderSide: BorderSide(color: color, width: width),
      );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colors,
    fontFamily: ShellxFonts.uiFamily(platform),
    fontFamilyFallback: ShellxFonts.uiFallback(platform),
    scaffoldBackgroundColor: ShellxDesktopColors.bgTerminal,
    canvasColor: ShellxDesktopColors.bgTerminal,
    dividerColor: ShellxDesktopColors.line,
    dividerTheme: const DividerThemeData(
      color: ShellxDesktopColors.line,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ShellxDesktopColors.surfaceInset,
      hoverColor: Colors.transparent,
      hintStyle: const TextStyle(color: ShellxDesktopColors.textPlaceholder),
      // UI §3.4: 36 high (20 px `dialogBody` line + 8 + 8), padding 0/10;
      // the label sits above the field (LabeledField), never inside it.
      // V2-5a A43: inset navy900, outline ≥ 3:1, radius 16, no inner shadow.
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: ShellxSizes.inputPaddingH,
        vertical: ShellxSizes.inputPaddingV,
      ),
      enabledBorder: WidgetStateInputBorder.resolveWith(
        (states) => field(
          states.contains(WidgetState.hovered)
              ? ShellxDesktopColors.textSecondary
              : ShellxDesktopColors.borderInput,
        ),
      ),
      disabledBorder: field(
        ShellxDesktopColors.borderInput.withValues(alpha: 0.5),
      ),
      focusedBorder: field(ShellxDesktopColors.accent, width: 1.5),
      errorBorder: field(ShellxDesktopColors.errDialog),
      focusedErrorBorder: field(ShellxDesktopColors.errDialog, width: 1.5),
    ),
    // UI §1.1 tokens instead of the stock Material switch; V2-5a: the thumb
    // is ink on the cyan track when on.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? ShellxDesktopColors.onPrimary
            : ShellxDesktopColors.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? ShellxDesktopColors.primary
            : ShellxDesktopColors.surfaceInset,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? ShellxDesktopColors.primary
            : ShellxDesktopColors.borderInput,
      ),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: ShellxDesktopColors.accent,
      inactiveTrackColor: ShellxDesktopColors.surfaceInset,
      thumbColor: ShellxDesktopColors.accent,
      overlayColor: ShellxPalette.hairlineStrong,
      valueIndicatorColor: ShellxDesktopColors.rowSelected,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: ShellxDesktopColors.accent,
      linearTrackColor: ShellxDesktopColors.rowSelected,
      circularTrackColor: Colors.transparent,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: ShellxDesktopColors.accent,
      selectionColor: ShellxTerminalPalette.selection,
      selectionHandleColor: ShellxDesktopColors.accent,
    ),
    iconTheme: const IconThemeData(color: ShellxDesktopColors.textPrimary),
    dialogTheme: const DialogThemeData(
      backgroundColor: ShellxDesktopColors.surface,
      surfaceTintColor: Colors.transparent,
      barrierColor: ShellxDesktopColors.scrim,
      elevation: 24,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r12)),
        side: BorderSide(color: ShellxDesktopColors.border),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: ShellxDesktopColors.surface,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: ShellxDesktopColors.scrim,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ShellxRadius.r12),
        ),
      ),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: ShellxDesktopColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: ShellxShadows.e1Elevation,
      shadowColor: ShellxShadows.e1ShadowColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r8)),
        side: BorderSide(color: ShellxDesktopColors.border),
      ),
    ),
  );
  final text = shellxWeightedTextTheme(base.textTheme);
  const menu = MenuStyle(
    backgroundColor: WidgetStatePropertyAll(ShellxDesktopColors.surface),
    surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
    elevation: WidgetStatePropertyAll(ShellxShadows.e1Elevation),
    shadowColor: WidgetStatePropertyAll(ShellxShadows.e1ShadowColor),
    padding: WidgetStatePropertyAll(EdgeInsets.all(ShellxSpace.s4)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r8)),
        side: BorderSide(color: ShellxDesktopColors.border),
      ),
    ),
  );
  return base.copyWith(
    textTheme: text,
    primaryTextTheme: shellxWeightedTextTheme(base.primaryTextTheme),
    menuTheme: const MenuThemeData(style: menu),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: menu,
      inputDecorationTheme: base.inputDecorationTheme,
      textStyle: uiFont(
        ShellxText.dialogBody.copyWith(color: ShellxDesktopColors.textTitle),
        text,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: shellxPrimaryButtonStyle()),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: shellxSecondaryButtonStyle(),
    ),
    textButtonTheme: TextButtonThemeData(style: shellxTextButtonStyle()),
    tooltipTheme: TooltipThemeData(
      waitDuration: ShellxMotion.tooltipWait,
      textStyle: uiFont(
        ShellxText.small.copyWith(color: ShellxDesktopColors.textPrimary),
        text,
      ),
      decoration: const BoxDecoration(
        color: ShellxDesktopColors.rowSelected,
        borderRadius: BorderRadius.all(Radius.circular(ShellxRadius.r6)),
        border: Border.fromBorderSide(
          BorderSide(color: ShellxDesktopColors.border),
        ),
        boxShadow: ShellxShadows.e1,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
  );
}

/// UI §3.3 / §4: the legacy pages reused as dialog bodies get their look
/// from this theme (applied by the dialog host only): the dialog type
/// scale, and buttons 32 high, at least 80 wide, padded 0/14, over the
/// window's button styles.
ThemeData buildDialogTheme(ThemeData base, {required bool reduceMotion}) {
  final text = base.textTheme;
  ButtonStyle sized(ButtonStyle style) => style.copyWith(
    minimumSize: const WidgetStatePropertyAll(
      Size(ShellxSizes.buttonMinWidth, ShellxSizes.button),
    ),
    fixedSize: const WidgetStatePropertyAll(
      Size.fromHeight(ShellxSizes.button),
    ),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: ShellxSizes.buttonPaddingH),
    ),
    textStyle: WidgetStatePropertyAll(uiFont(ShellxText.bodyStrong, text)),
    animationDuration: reduceMotion ? Duration.zero : ShellxMotion.fast,
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
      style: sized(shellxPrimaryButtonStyle()),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: sized(shellxSecondaryButtonStyle()),
    ),
    textButtonTheme: TextButtonThemeData(style: sized(shellxTextButtonStyle())),
  );
}

/// UI §3.3, V2-5a §7.1: the destructive button (closing tabs, signing out,
/// quitting). `error` with `onError` ink, never a gradient: it brings its
/// own layer, so a theme's gradient never shows through. Hovered
/// `destructiveHover`, pressed shaded black 16 %, the keyboard ring outside.
ButtonStyle destructiveButtonStyle() => ButtonStyle(
  shape: buttonShape(outsideRing: true),
  foregroundColor: _ink(ShellxDesktopColors.onErr),
  iconColor: _ink(ShellxDesktopColors.onErr),
  backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
  backgroundBuilder: (context, states, child) => DecoratedBox(
    decoration: BoxDecoration(
      color: states.contains(WidgetState.disabled)
          ? _disabled(ShellxDesktopColors.errDialog)
          : states.contains(WidgetState.pressed)
          ? Color.alphaBlend(
              ShellxGradients.pressedShade,
              ShellxDesktopColors.errDialog,
            )
          : states.contains(WidgetState.hovered)
          ? ShellxDesktopColors.destructiveHover
          : ShellxDesktopColors.errDialog,
      borderRadius: _control,
    ),
    child: child,
  ),
);

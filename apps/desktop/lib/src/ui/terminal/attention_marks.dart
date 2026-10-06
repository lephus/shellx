import 'dart:math';

import 'package:flutter/material.dart';

import '../../terminal/tab_attention.dart';
import '../theme/shellx_desktop_theme.dart';
import 'session_tab_row.dart' show besideSidebar;

/// UI-A4 §2.1: accent pill with the unread count (`1`…`99`, `99+`), right
/// after the title. The count is in the row's semantics label (§8).
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    // UI-A4 §1.3: max(16, scale(14) + 2); one digit stays a circle.
    final height = max(
      ShellxSizes.badgeHeight,
      scaler.scale(ShellxSizes.notificationLine) + 2,
    );
    return ExcludeSemantics(
      child: Container(
        key: const Key('row.badge'),
        height: height,
        constraints: BoxConstraints(
          minWidth: max(ShellxSizes.badgeMinWidth, height),
        ),
        padding: const EdgeInsets.symmetric(horizontal: ShellxSizes.badgePadH),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ShellxDesktopColors.accent,
          borderRadius: BorderRadius.circular(ShellxRadius.pill),
        ),
        child: Text(
          unreadBadgeLabel(count),
          maxLines: 1,
          softWrap: false,
          style: ShellxText.caption.copyWith(
            fontWeight: FontWeight.w600,
            color: ShellxDesktopColors.onPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// UI-A4 §2.1: bell icon + the last unread text (D9), one line, cut at
/// the end; the full text (at most [tooltipMaxChars]) as a tooltip only
/// when it is cut. The text is in the row's semantics label (§8).
class NotificationLine extends StatelessWidget {
  const NotificationLine({super.key, required this.text});
  final String text;

  /// UI-A4 §2.1: "tối đa 200 ký tự".
  static const tooltipMaxChars = 200;

  @override
  Widget build(BuildContext context) {
    final style = ShellxText.caption.copyWith(
      color: ShellxDesktopColors.textSecondary,
    );
    return ExcludeSemantics(
      child: Row(
        key: const Key('row.notification'),
        children: [
          const Icon(
            Icons.notifications_none,
            size: ShellxSizes.notificationIcon,
            color: ShellxDesktopColors.accent,
          ),
          const SizedBox(width: ShellxSizes.notificationIconGap),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final line = Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                );
                final painter = TextPainter(
                  text: TextSpan(
                    text: text,
                    style: DefaultTextStyle.of(context).style.merge(style),
                  ),
                  maxLines: 1,
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout(maxWidth: constraints.maxWidth);
                final cut = painter.didExceedMaxLines;
                painter.dispose();
                if (!cut) return line;
                final chars = text.characters;
                return Tooltip(
                  message: chars.length > tooltipMaxChars
                      ? '${chars.take(tooltipMaxChars - 1)}…'
                      : text,
                  excludeFromSemantics: true,
                  waitDuration: ShellxMotion.tooltipWait,
                  positionDelegate: besideSidebar,
                  constraints: const BoxConstraints(
                    maxWidth: ShellxSizes.titleTooltipMaxWidth,
                  ),
                  child: line,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// UI-A4 §4: 2 px `accent` with 1 px `accent` 40 % inside, square, over
/// the terminal area; fades in `base`, out `exit`, never loops, and is
/// static (instant) with reduced motion. Paint only: the terminal's
/// constraints never change, so the PTY is never resized (A1 D6).
class AttentionRing extends StatelessWidget {
  const AttentionRing({super.key, required this.visible});
  final bool visible;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: ShellxMotion.of(
          context,
          visible ? ShellxMotion.base : ShellxMotion.exit,
        ),
        curve: visible ? ShellxMotion.baseCurve : ShellxMotion.exitCurve,
        child: DecoratedBox(
          key: const Key('pane.ring'),
          decoration: BoxDecoration(
            border: Border.all(
              color: ShellxDesktopColors.accent,
              width: ShellxSizes.ringWidth,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(ShellxSizes.ringWidth),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  // `#665FD4E2`, the terminal's selection colour (§1.1).
                  color: ShellxDesktopColors.accent.withValues(alpha: 0.4),
                  width: ShellxSizes.ringGlowWidth,
                ),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    ),
  );
}

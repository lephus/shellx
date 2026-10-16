import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/shellx_desktop_theme.dart';
import 'terminal_overlays.dart';

/// UI-A5 §4: a neutral strip over the terminal area (the abnormal-end
/// notice; A5b's background-session strip). Never hides itself (WCAG
/// 2.2.1): "Đóng" or Esc while the keyboard is inside calls [onClose].
/// A live region; a cut text has a tooltip with all of it.
class InfoStrip extends StatelessWidget {
  const InfoStrip({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.closeText,
    required this.closeLabel,
    required this.onClose,
    this.focusNode,
    this.actions = const [],
  });

  final IconData icon;
  final Color iconColor;
  final String text;

  /// The close button's text (`actionClose`).
  final String closeText;

  /// What a screen reader reads for the close button (UI-A5 §8).
  final String closeLabel;
  final VoidCallback onClose;

  /// The close button's node: F6 lands here.
  final FocusNode? focusNode;

  /// Buttons before the close button.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final style = ShellxText.body.copyWith(
      color: ShellxDesktopColors.textPrimary,
    );
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              onClose();
              return null;
            },
          ),
        },
        child: Semantics(
          container: true,
          liveRegion: true,
          child: Container(
            key: const Key('infoStrip'),
            height: ShellxSizes.infoStripFor(MediaQuery.textScalerOf(context)),
            decoration: stripDecoration,
            padding: stripPadding,
            child: Row(
              children: [
                Icon(icon, size: ShellxSizes.icon, color: iconColor),
                const SizedBox(width: ShellxSpace.s8),
                Expanded(child: _text(context, style)),
                ...actions,
                TextButton(
                  key: const Key('infoStrip.close'),
                  focusNode: focusNode,
                  onPressed: onClose,
                  style: stripTextButtonStyle(context),
                  child: Text(closeText, semanticsLabel: closeLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One line, cut at the end; the tooltip shows it all when cut.
  Widget _text(BuildContext context, TextStyle style) => LayoutBuilder(
    builder: (context, constraints) {
      final line = Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
      return Tooltip(
        message: text,
        excludeFromSemantics: true,
        waitDuration: ShellxMotion.tooltipWait,
        child: line,
      );
    },
  );
}

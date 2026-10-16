import 'package:flutter/material.dart';

import '../terminal/shortcut_labels.dart';
import '../terminal/terminal_overlays.dart';
import '../theme/shellx_desktop_theme.dart';

/// One dialog's content (UI §4): padding 24, title → 8 → body → 24 →
/// [footer]. The dialog is as tall as this content, up to the window's
/// room; then the body scrolls (scrollbar shown) while the title stays and
/// the [footer] (the actions) stays pinned under a 1 px `line`, so the
/// primary action is always on screen, even at 640×400.
class DialogBody extends StatefulWidget {
  const DialogBody({
    super.key,
    required this.title,
    required this.content,
    this.footer,
  });

  final String title;

  /// Stretched to the dialog width, top to bottom.
  final List<Widget> content;
  final Widget? footer;

  @override
  State<DialogBody> createState() => _DialogBodyState();
}

class _DialogBodyState extends State<DialogBody> {
  final _scroll = ScrollController();
  bool _overflows = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool _onMetrics(ScrollMetricsNotification notification) {
    final overflows = notification.metrics.maxScrollExtent > 0;
    if (overflows != _overflows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _overflows = overflows);
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final footer = widget.footer;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            ShellxSpace.s24,
            ShellxSpace.s24,
            // Windows: clear of the close button (28 at inset 12).
            isMacDesktop
                ? ShellxSpace.s24
                : ShellxSizes.iconHit + ShellxSpace.s12 + ShellxSpace.s4,
            ShellxSpace.s8,
          ),
          child: Text(widget.title, style: theme.textTheme.titleLarge),
        ),
        Flexible(
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: _onMetrics,
            child: ShellxScrollbar(
              controller: _scroll,
              alwaysVisible: true,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(
                  ShellxSpace.s24,
                  0,
                  ShellxSpace.s24,
                  footer == null ? ShellxSpace.s24 : 0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.content,
                ),
              ),
            ),
          ),
        ),
        if (footer != null) ...[
          Container(
            key: const Key('dialog.footerLine'),
            height: 1,
            color: _overflows ? ShellxDesktopColors.line : Colors.transparent,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ShellxSpace.s24,
              ShellxSpace.s24 - 1,
              ShellxSpace.s24,
              ShellxSpace.s24,
            ),
            child: footer,
          ),
        ],
      ],
    );
  }
}

/// UI §3.4 field: the label above (`label` 12.5/600 `textDialog2`), 6 px,
/// then the 36 px field. Merged for screen readers, so the field is
/// announced with its label.
class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.field});
  final String label;
  final Widget field;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: ShellxText.label.copyWith(
            color: ShellxDesktopColors.textDialog2,
          ),
        ),
        const SizedBox(height: ShellxSizes.labelGap),
        field,
      ],
    ),
  );
}

/// An error under a form (UI §3.4: `small` `errDialog`).
class DialogError extends StatelessWidget {
  const DialogError(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: ShellxSpace.s8),
    child: Text(
      text,
      style: ShellxText.small.copyWith(color: ShellxDesktopColors.errDialog),
    ),
  );
}

import 'package:flutter/material.dart';

import '../../ai/line_diff.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_theme.dart';

/// A line diff (D17): removed lines on `err`, added on `ok`, the gaps as
/// "⋯". Smoothness: past 40 rows it is a fixed-height virtualized list.
class AiDiffView extends StatelessWidget {
  const AiDiffView({super.key, required this.lines, this.height = 360});

  /// From [withContext] (null: lines left out) or a whole diff.
  final List<DiffLine?> lines;
  final double height;

  static const double _row = 17;

  @override
  Widget build(BuildContext context) {
    Widget row(int i) => _Row(line: lines[i]);
    final body = lines.length <= 40
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (var i = 0; i < lines.length; i++) row(i)],
          )
        : SizedBox(
            height: height,
            child: ListView.builder(
              itemExtent: _row,
              itemCount: lines.length,
              itemBuilder: (context, i) => row(i),
            ),
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ShellxDesktopColors.surfaceInset,
        borderRadius: BorderRadius.circular(ShellxRadius.r6),
        border: Border.all(color: ShellxDesktopColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ShellxRadius.r6),
        child: body,
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.line});
  final DiffLine? line;

  @override
  Widget build(BuildContext context) {
    final l = line;
    if (l == null) {
      return const SizedBox(
        height: AiDiffView._row,
        child: Center(
          child: Text(
            '⋯',
            style: TextStyle(color: ShellxDesktopColors.dim, fontSize: 11),
          ),
        ),
      );
    }
    final (bg, mark, color) = switch (l.op) {
      DiffOp.added => (
        ShellxDesktopColors.ok.withValues(alpha: 0.12),
        '+',
        ShellxDesktopColors.ok,
      ),
      DiffOp.removed => (
        ShellxDesktopColors.err.withValues(alpha: 0.12),
        '−',
        ShellxDesktopColors.err,
      ),
      DiffOp.same => (
        Colors.transparent,
        ' ',
        ShellxDesktopColors.textSecondary,
      ),
    };
    final no = '${l.newNo ?? l.oldNo ?? ''}'.padLeft(4);
    return Container(
      height: AiDiffView._row,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s6),
      child: Text(
        '$no $mark ${l.text}',
        maxLines: 1,
        overflow: TextOverflow.clip,
        softWrap: false,
        style: kAiMono.copyWith(
          color: l.op == DiffOp.same ? ShellxDesktopColors.textPrimary : color,
        ),
      ),
    );
  }
}

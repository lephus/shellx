import 'package:flutter/material.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../../l10n/app_localizations.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_labels.dart';
import 'ai_scope.dart';

/// The end of a turn (spec §4.2): "Turn N · 0:41 · 2 files changed +44 −5 ·
/// View · Revert turn", or "Stopped turn N…", "Turn N was interrupted…".
/// "View" and "Revert turn" are the Changes panel's (Task 20).
class AiTurnSummary extends StatelessWidget {
  const AiTurnSummary({super.key, required this.item});
  final TurnEndItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ui = AiPaneScope.of(context).ui;
    final time = aiClock(item.elapsed);
    final n = item.turn;
    final changes = item.changes;
    final head = switch (item.outcome) {
      TurnOutcome.finished =>
        changes == null || changes.isEmpty
            ? l10n.aiTurnDone(n, time)
            : l10n.aiTurnSummary(n, time, changes.length),
      TurnOutcome.cancelled => l10n.aiTurnStopped(n, time),
      TurnOutcome.interrupted => l10n.aiTurnInterrupted(n, time),
      TurnOutcome.failed => l10n.aiTurnFailed(n, time),
    };
    final added = changes?.fold(0, (a, c) => a + (c.added ?? 0)) ?? 0;
    final removed = changes?.fold(0, (a, c) => a + (c.removed ?? 0)) ?? 0;
    final dim = ShellxText.small.copyWith(
      color: ShellxDesktopColors.textSecondary,
    );
    final stopped = item.outcome != TurnOutcome.finished;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ShellxSpace.s4),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: ShellxSpace.s8,
        children: [
          Text(
            head,
            key: const Key('ai.turn.summary'),
            style: dim.copyWith(
              color: stopped ? ShellxDesktopColors.warn : null,
            ),
          ),
          if (changes != null && changes.isNotEmpty) ...[
            Text('+$added', style: dim.copyWith(color: ShellxDesktopColors.ok)),
            Text(
              '−$removed',
              style: dim.copyWith(color: ShellxDesktopColors.err),
            ),
            TextButton(
              key: const Key('ai.turn.view'),
              onPressed: ui.openPanel,
              child: Text(l10n.aiTurnView),
            ),
            if (item.checkpoint != null && ui.onRevertTurn != null)
              TextButton.icon(
                key: const Key('ai.turn.revert'),
                onPressed: () => ui.onRevertTurn?.call(n),
                icon: const Icon(Icons.undo, size: 14),
                label: Text(l10n.aiRevertTurn),
              ),
          ] else if (item.outcome == TurnOutcome.finished && changes != null)
            Text(l10n.aiTurnNoChanges, style: dim),
          if (item.error case final error?)
            Text(error, style: dim.copyWith(color: ShellxDesktopColors.err)),
        ],
      ),
    );
  }
}

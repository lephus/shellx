import 'package:flutter/material.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart' show PromptSource;

import '../../../l10n/app_localizations.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_composer.dart';
import 'ai_images.dart';
import 'ai_scope.dart';
import 'ai_theme.dart';

/// The dock under the conversation (spec §4.1), top to bottom: the plan
/// (folds), the permission bar (Task 16), the queue, the composer.
///
/// All of it is "in" the composer's field for a tap: on macOS and Windows a
/// click outside a field takes its focus, and with it keys 1–9, Esc and
/// typing, so a click on Send, on Allow or on a chip would leave the composer
/// deaf until it is clicked again.
class AiDock extends StatelessWidget {
  const AiDock({super.key, this.focusNode, this.permissionBar, this.keyHook});

  final FocusNode? focusNode;

  /// The permission bar (Task 16); null: none.
  final Widget? permissionBar;
  final AiKeyHook? keyHook;

  @override
  Widget build(BuildContext context) {
    final scope = AiPaneScope.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AiSizes.column),
        child: TextFieldTapRegion(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AiSelect<List<PlanEntry>>(
                frames: scope.frames,
                select: (s) => s.plan,
                builder: (context, plan) => plan.isEmpty
                    ? const SizedBox.shrink()
                    : AiPlanBar(entries: plan),
              ),
              ?permissionBar,
              AiSelect<String>(
                frames: scope.frames,
                select: (s) => [for (final q in s.queue) q.id].join(','),
                builder: (context, _) {
                  final s = scope.state;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final q in s.queue)
                        AiQueuedRow(
                          key: ValueKey(q.id),
                          text: q.text,
                          fromPhone: q.source == PromptSource.phone,
                          onRemove: () => s.removeQueued(q.id),
                        ),
                    ],
                  );
                },
              ),
              // D16: images pasted or dropped on the composer.
              AiImageInput(
                child: AiComposer(focusNode: focusNode, keyHook: keyHook),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tallest an open plan grows before it scrolls.
const double kAiPlanMax = 200;

/// The agent's plan (`plan` updates): one line that folds open.
class AiPlanBar extends StatefulWidget {
  const AiPlanBar({super.key, required this.entries});
  final List<PlanEntry> entries;

  @override
  State<AiPlanBar> createState() => _AiPlanBarState();
}

class _AiPlanBarState extends State<AiPlanBar> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final done = widget.entries
        .where((e) => e.status == PlanStatus.completed)
        .length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            key: const Key('ai.plan'),
            onPressed: () => setState(() => _open = !_open),
            icon: Icon(_open ? Icons.expand_less : Icons.expand_more, size: 16),
            label: Text(l10n.aiPlan(done, widget.entries.length)),
          ),
          if (_open)
            // A plan has no length either: the composer stays in the window.
            AiCapped(
              max: kAiPlanMax,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in widget.entries)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: ShellxSpace.s12,
                        bottom: ShellxSpace.s4,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            switch (e.status) {
                              PlanStatus.completed => Icons.check,
                              PlanStatus.inProgress => Icons.circle,
                              PlanStatus.pending => Icons.circle_outlined,
                            },
                            size: 12,
                            color: e.status == PlanStatus.inProgress
                                ? ShellxDesktopColors.accent
                                : ShellxDesktopColors.textSecondary,
                          ),
                          const SizedBox(width: ShellxSpace.s6),
                          Expanded(
                            child: Text(
                              e.content,
                              style: ShellxText.small.copyWith(
                                color: e.status == PlanStatus.completed
                                    ? ShellxDesktopColors.textSecondary
                                    : ShellxDesktopColors.textPrimary,
                              ),
                            ),
                          ),
                          if (e.priority == 'high')
                            Text(
                              l10n.aiPlanHigh,
                              style: ShellxText.caption.copyWith(
                                color: ShellxDesktopColors.warn,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One queued prompt (D16): "Queued: “…” — sent when this turn ends", led by
/// "You · from your phone" when a paired phone sent it (V2-2b B24), and ×.
class AiQueuedRow extends StatelessWidget {
  const AiQueuedRow({
    super.key,
    required this.text,
    required this.onRemove,
    this.fromPhone = false,
  });
  final String text;
  final VoidCallback onRemove;
  final bool fromPhone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final short = text.length > 60 ? '${text.substring(0, 60)}…' : text;
    final style = ShellxText.small.copyWith(
      color: ShellxDesktopColors.textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ShellxSpace.s16),
      child: Row(
        children: [
          const Icon(
            Icons.schedule,
            size: 14,
            color: ShellxDesktopColors.textSecondary,
          ),
          const SizedBox(width: ShellxSpace.s6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (fromPhone)
                    TextSpan(
                      text: '${l10n.aiYouFromPhone} · ',
                      style: style.copyWith(fontWeight: FontWeight.w600),
                    ),
                  TextSpan(text: l10n.aiQueued(short)),
                ],
              ),
              key: const Key('ai.queued.text'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          IconButton(
            tooltip: l10n.aiQueueRemove,
            iconSize: 14,
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

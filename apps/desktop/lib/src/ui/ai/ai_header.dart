import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/agent_names.dart' show agentStateWord;
import '../../terminal/agent_status.dart';
import '../../terminal/agent_status_notifier.dart' show agentPaneBadgeProvider;
import '../theme/shellx_desktop_theme.dart';
import 'ai_labels.dart';
import 'ai_scope.dart' show AiEverySecond;
import 'ai_theme.dart';

/// What the header shows of a session. Compared once per frame, so the
/// header rebuilds when its status changes, never per streamed chunk.
typedef AiHeaderView = ({
  AgentPhase phase,
  bool needsInput,
  DateTime? started,
  bool stopping,
});

AiHeaderView aiHeaderViewOf(AiSessionState s) => (
  phase: s.phase,
  needsInput: s.needsInput,
  started: s.turn?.startedAt,
  stopping: s.turn?.cancelRequested ?? false,
);

/// The header's status (spec §4.1, A12's words): a question first, then a
/// running turn, then the agent's phase; at rest, A12's "Done" after a turn
/// (it knows "Done" from "Idle"), else "Idle".
({String text, Color color, IconData? icon}) aiStatusOf(
  AppLocalizations l10n,
  AiHeaderView v,
  AgentState? a12,
) {
  if (v.stopping) {
    return (text: l10n.aiStopping, color: ShellxDesktopColors.warn, icon: null);
  }
  if (v.needsInput) {
    return (
      text: agentStateWord(l10n, AgentState.needsInput),
      color: ShellxDesktopColors.warn,
      icon: Icons.warning_amber_rounded,
    );
  }
  if (v.started != null) {
    return (
      text: agentStateWord(l10n, AgentState.running),
      color: ShellxDesktopColors.accent,
      icon: Icons.circle,
    );
  }
  return switch (v.phase) {
    AgentPhase.starting => (
      text: l10n.aiStatusStarting,
      color: ShellxDesktopColors.textSecondary,
      icon: null,
    ),
    AgentPhase.needsAuth => (
      text: l10n.aiStatusSignIn,
      color: ShellxDesktopColors.warn,
      icon: Icons.key_outlined,
    ),
    AgentPhase.failed => (
      text: l10n.aiStatusStopped,
      color: ShellxDesktopColors.err,
      icon: Icons.error_outline,
    ),
    AgentPhase.stopped => (
      text: l10n.aiStatusNotRunning,
      color: ShellxDesktopColors.textSecondary,
      icon: null,
    ),
    AgentPhase.ready || AgentPhase.running =>
      a12 == AgentState.done
          ? (
              text: agentStateWord(l10n, AgentState.done),
              color: ShellxDesktopColors.ok,
              icon: Icons.check,
            )
          : (
              text: agentStateWord(l10n, AgentState.idle),
              color: ShellxDesktopColors.textSecondary,
              icon: Icons.circle_outlined,
            ),
  };
}

/// The AI pane's header (spec §4.1, 34 px): the agent, the session title,
/// the status (with a clock while a turn runs: "Running · 0:12"), then
/// History, Changes · Files, Terminal, Zoom and ⋯. A button whose action
/// is null is not shown.
class AiHeader extends ConsumerWidget {
  const AiHeader({
    super.key,
    required this.paneId,
    required this.agentName,
    required this.title,
    required this.view,
    this.onHistory,
    this.onPanel,
    this.panelOpen = false,
    required this.onTerminal,
    this.onZoom,
    required this.onMore,
  });

  final int paneId;
  final String agentName;
  final String title;
  final AiHeaderView view;
  final VoidCallback? onHistory;
  final VoidCallback? onPanel;
  final bool panelOpen;
  final VoidCallback onTerminal;
  final VoidCallback? onZoom;

  /// ⋯, with the point under the button (global) for the menu.
  final void Function(Offset at) onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final a12 = ref.watch(agentPaneBadgeProvider(paneId))?.state;
    final status = aiStatusOf(l10n, view, a12);
    final started = view.started;
    Widget button(
      IconData glyph,
      String tip,
      VoidCallback onPressed,
      Key key, {
      bool on = false,
    }) => IconButton(
      key: key,
      tooltip: tip,
      iconSize: 16,
      visualDensity: VisualDensity.compact,
      color: on
          ? ShellxDesktopColors.accent
          : ShellxDesktopColors.textSecondary,
      onPressed: onPressed,
      icon: Icon(glyph),
    );
    return SizedBox(
      height: AiSizes.header,
      child: Padding(
        padding: const EdgeInsets.only(
          left: ShellxSpace.s12,
          right: ShellxSpace.s4,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.auto_awesome,
              size: 14,
              color: ShellxDesktopColors.accent,
            ),
            const SizedBox(width: ShellxSpace.s6),
            Text(
              agentName,
              style: ShellxText.bodyStrong.copyWith(
                color: ShellxDesktopColors.textPrimary,
              ),
            ),
            const SizedBox(width: ShellxSpace.s8),
            Flexible(
              child: Text(
                title,
                key: const Key('ai.header.title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ShellxText.small.copyWith(
                  color: ShellxDesktopColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: ShellxSpace.s12),
            // A live region of its own, saying the state and nothing that
            // changes while it holds (the clock is for the eyes): without a
            // container the flag lands on the whole pane, and a clock in the
            // label is read again every second.
            Semantics(
              container: true,
              liveRegion: true,
              label: status.text,
              excludeSemantics: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (status.icon case final glyph?) ...[
                    Icon(glyph, size: 12, color: status.color),
                    const SizedBox(width: ShellxSpace.s4),
                  ],
                  if (started == null)
                    Text(
                      status.text,
                      key: const Key('ai.header.status'),
                      style: ShellxText.caption.copyWith(color: status.color),
                    )
                  else
                    _Clock(
                      key: const Key('ai.header.status'),
                      label: status.text,
                      since: started,
                      color: status.color,
                    ),
                ],
              ),
            ),
            const Spacer(),
            if (onHistory case final open?)
              button(
                Icons.history,
                l10n.aiHistory,
                open,
                const Key('ai.history'),
              ),
            if (onPanel case final toggle?)
              button(
                Icons.vertical_split_outlined,
                l10n.aiHeaderPanel,
                toggle,
                const Key('ai.panel'),
                on: panelOpen,
              ),
            button(
              Icons.terminal,
              l10n.aiHeaderTerminal,
              onTerminal,
              const Key('ai.terminal'),
            ),
            if (onZoom case final zoom?)
              button(
                Icons.fullscreen,
                l10n.aiHeaderZoom,
                zoom,
                const Key('ai.zoom'),
              ),
            Builder(
              builder: (context) =>
                  button(Icons.more_horiz, l10n.aiHeaderMore, () {
                    final box = context.findRenderObject()! as RenderBox;
                    onMore(box.localToGlobal(Offset(0, box.size.height)));
                  }, const Key('ai.more')),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Running · 0:12": the time since [since], once a second (text, never an
/// animation), while the pane is on screen.
class _Clock extends StatelessWidget {
  const _Clock({
    super.key,
    required this.label,
    required this.since,
    required this.color,
  });

  final String label;
  final DateTime since;
  final Color color;

  @override
  Widget build(BuildContext context) => AiEverySecond(
    builder: (context) => Text(
      AppLocalizations.of(
        context,
      ).aiStatusWithTime(label, aiClock(DateTime.now().difference(since))),
      style: ShellxText.caption.copyWith(color: color),
    ),
  );
}

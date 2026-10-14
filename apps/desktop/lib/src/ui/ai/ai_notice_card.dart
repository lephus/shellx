import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/shellx_ai.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/desktop_services.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_log_dialog.dart';
import 'ai_scope.dart';

/// Node's download page ("Installation guide", spec §4.5).
final Uri kNodeDownloadPage = Uri.parse('https://nodejs.org/en/download');

/// The reason undo is off, in words (`aiNoUndo`, spec §6).
String aiUndoReason(AppLocalizations l10n, UndoOff reason) => switch (reason) {
  UndoOff.noGit => l10n.aiUndoNoGit,
  UndoOff.noCommandLineTools => l10n.aiUndoNoCommandLineTools,
  UndoOff.gitTooOld => l10n.aiUndoGitTooOld,
  UndoOff.tooManyFiles => l10n.aiUndoTooManyFiles,
  UndoOff.tooSlow => l10n.aiUndoTooSlow,
  UndoOff.failed => l10n.aiUndoFailed,
};

/// A notice in the conversation (spec §4.5, §6) with what can be done
/// about it. A notice whose problem went away folds to one dim line.
class AiNoticeCard extends ConsumerWidget {
  const AiNoticeCard({super.key, required this.item});
  final NoticeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scope = AiPaneScope.of(context);
    final runtime = scope.runtime;
    final agent = scope.state.agentName;
    void log() => unawaited(showAiLogDialog(context, runtime));
    Widget button(String label, VoidCallback onPressed, {Key? key}) =>
        OutlinedButton(key: key, onPressed: onPressed, child: Text(label));
    final (
      IconData icon,
      Color color,
      String text,
      List<Widget> actions,
    ) = switch (item.notice) {
      LoginNeeded(:final methods) => (
        Icons.key_outlined,
        ShellxDesktopColors.warn,
        l10n.aiLoginNeeded(agent),
        [
          for (final m in methods)
            switch (m) {
              AuthMethodTerminal() => button(
                m.name,
                () => scope.ui.onRun?.call(AiRunLogin(m)),
                key: ValueKey('ai.login.${m.id}'),
              ),
              AuthMethodAgent() => button(
                m.name,
                () => unawaited(runtime.authenticate(m.id)),
                key: ValueKey('ai.login.${m.id}'),
              ),
              AuthMethodOther() => Text(m.name),
            },
        ],
      ),
      NodeMissing(:final required) => (
        Icons.info_outline,
        ShellxDesktopColors.warn,
        l10n.aiNodeMissing(agent, required),
        [
          button(l10n.aiNodeGuide, () {
            unawaited(
              ref
                  .read(desktopServicesProvider)
                  .urlOpener
                  .open(kNodeDownloadPage)
                  .catchError((Object e) {
                    debugPrint('ShellX: page not opened: ${e.runtimeType}');
                  }),
            );
          }, key: const Key('ai.node.guide')),
        ],
      ),
      AgentNotInstalled(:final canInstall) => (
        Icons.download_outlined,
        ShellxDesktopColors.warn,
        canInstall
            ? l10n.aiNotInstalled(agent)
            : '${l10n.aiNotInstalled(agent)}. ${l10n.aiNoNpm}',
        [
          if (canInstall)
            button(
              l10n.aiInstall,
              () => scope.ui.onRun?.call(const AiRunInstall()),
              key: const Key('ai.install'),
            ),
        ],
      ),
      AgentMissing(:final command, :final shimOnly) => (
        Icons.search_off,
        ShellxDesktopColors.err,
        shimOnly
            ? '${l10n.aiCommandMissing(command)}. ${l10n.aiCommandShimOnly}'
            : l10n.aiCommandMissing(command),
        const <Widget>[],
      ),
      AgentExited(:final exitCode) => (
        Icons.error_outline,
        ShellxDesktopColors.err,
        l10n.aiAgentExited(agent, exitCode),
        [
          button(
            l10n.aiRestart,
            () => unawaited(runtime.restart()),
            key: const Key('ai.restart'),
          ),
          button(l10n.aiMenuViewLog, log, key: const Key('ai.log')),
        ],
      ),
      AgentOutputInvalid() => (
        Icons.error_outline,
        ShellxDesktopColors.err,
        l10n.aiAgentOutputInvalid(agent),
        [
          button(
            l10n.aiRestart,
            () => unawaited(runtime.restart()),
            key: const Key('ai.restart'),
          ),
          button(l10n.aiMenuViewLog, log, key: const Key('ai.log')),
        ],
      ),
      StartFailed() => (
        Icons.error_outline,
        ShellxDesktopColors.err,
        l10n.aiStartFailed(agent),
        [
          button(
            l10n.aiRetry,
            () => unawaited(runtime.retry()),
            key: const Key('ai.retry'),
          ),
          button(l10n.aiMenuViewLog, log, key: const Key('ai.log')),
        ],
      ),
      CannotResume() => (
        Icons.history,
        ShellxDesktopColors.textSecondary,
        l10n.aiCannotResume,
        const <Widget>[],
      ),
      FolderMissing() => (
        Icons.folder_off_outlined,
        ShellxDesktopColors.err,
        l10n.aiFolderMissing,
        [
          button(
            l10n.aiChooseFolder,
            () => scope.ui.onChooseFolder?.call(),
            key: const Key('ai.chooseFolder'),
          ),
        ],
      ),
      UndoUnavailable(:final reason, :final turnOnly) => (
        Icons.undo,
        ShellxDesktopColors.textSecondary,
        turnOnly
            ? l10n.aiNoUndoTurn(aiUndoReason(l10n, reason))
            : l10n.aiNoUndo(aiUndoReason(l10n, reason)),
        const <Widget>[],
      ),
    };
    if (item.resolved) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: ShellxText.small.copyWith(color: ShellxDesktopColors.dim),
      );
    }
    final warn = color == ShellxDesktopColors.warn;
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(ShellxSpace.s12),
        decoration: BoxDecoration(
          color: warn
              ? ShellxDesktopColors.warnBg
              : ShellxDesktopColors.surface,
          borderRadius: BorderRadius.circular(ShellxRadius.r8),
          border: Border.all(
            color: warn
                ? ShellxDesktopColors.warnBorder
                : ShellxDesktopColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: ShellxSpace.s8),
                Expanded(
                  child: Text(
                    text,
                    style: ShellxText.body.copyWith(
                      color: ShellxDesktopColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: ShellxSpace.s8),
              Wrap(
                spacing: ShellxSpace.s8,
                runSpacing: ShellxSpace.s6,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

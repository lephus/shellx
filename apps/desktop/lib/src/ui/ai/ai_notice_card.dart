import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_acp/shellx_acp.dart';
import 'package:shellx_ai/host.dart' show AiRuntime;
import 'package:shellx_ai/shellx_ai.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/desktop_services.dart';
import '../../ai/ai_host_provider.dart';
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
  UndoOff.broadFolder => l10n.aiUndoBroadFolder,
  UndoOff.tooManyFiles => l10n.aiUndoTooManyFiles,
  UndoOff.tooSlow => l10n.aiUndoTooSlow,
  UndoOff.failed => l10n.aiUndoFailed,
};

/// "Check again", on a card about something the user sets up outside ShellX
/// (Node, git, an agent's command): the login environment the host kept is
/// forgotten (on Windows its PATH is read from the registry again), then the
/// agent starts again (V2-1 final review I-4). Without it, a Node installed
/// after the app started stays unseen until the app is restarted.
void aiCheckAgain(WidgetRef ref, AiRuntime runtime) {
  try {
    ref.read(aiHostProvider).env.invalidate();
  } on Object {
    // No AI host in this window (a test of something else): the start says.
  }
  unawaited(runtime.retry());
}

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
    // What the user installs outside ShellX is seen again after "Check again";
    // on Windows the environment may still be the old one (the registry could
    // not be read), and the card says how to be sure.
    final checkAgain = button(
      l10n.aiCheckAgain,
      () => aiCheckAgain(ref, runtime),
      key: const Key('ai.checkAgain'),
    );
    final restartHint = Theme.of(context).platform == TargetPlatform.windows
        ? l10n.aiRestartShellxHint
        : null;
    final (
      IconData icon,
      Color color,
      String text,
      List<Widget> actions,
      String? hint,
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
        null,
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
          checkAgain,
        ],
        restartHint,
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
            )
          else
            checkAgain,
        ],
        canInstall ? null : restartHint,
      ),
      AgentMissing(:final command, :final shimOnly) => (
        Icons.search_off,
        ShellxDesktopColors.err,
        shimOnly
            ? '${l10n.aiCommandMissing(command)}. ${l10n.aiCommandShimOnly}'
            : l10n.aiCommandMissing(command),
        [checkAgain],
        restartHint,
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
        null,
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
        null,
      ),
      StartFailed(:final reason) => (
        Icons.error_outline,
        ShellxDesktopColors.err,
        l10n.aiStartFailed(agent),
        [
          button(
            l10n.aiRetry,
            () => unawaited(runtime.retry()),
            key: const Key('ai.retry'),
          ),
          // Retrying repeats the load of a session that cannot be reopened,
          // for good; this lets it go (V2-1 final review I-6).
          if (reason == StartFailure.session && runtime.resumesSession)
            button(
              l10n.aiStartNewSession,
              () => unawaited(runtime.retry(newSession: true)),
              key: const Key('ai.newSession'),
            ),
          button(l10n.aiMenuViewLog, log, key: const Key('ai.log')),
        ],
        null,
      ),
      CannotResume() => (
        Icons.history,
        ShellxDesktopColors.textSecondary,
        l10n.aiCannotResume,
        const <Widget>[],
        null,
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
        null,
      ),
      UndoUnavailable(:final reason, :final turnOnly) => (
        Icons.undo,
        ShellxDesktopColors.textSecondary,
        turnOnly
            ? l10n.aiNoUndoTurn(aiUndoReason(l10n, reason))
            : l10n.aiNoUndo(aiUndoReason(l10n, reason)),
        const <Widget>[],
        null,
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
            if (hint != null) ...[
              const SizedBox(height: ShellxSpace.s6),
              Text(
                hint,
                key: const Key('ai.restartHint'),
                style: ShellxText.small.copyWith(
                  color: ShellxDesktopColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

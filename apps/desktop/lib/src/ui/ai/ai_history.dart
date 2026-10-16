import 'package:flutter/material.dart';
import 'package:shellx_ai/host.dart';

import '../../../l10n/app_localizations.dart';
import '../theme/shellx_desktop_theme.dart';

/// "2026-10-13 09:30" in local time; the agent's text when it is no date.
String aiHistoryWhen(String? updatedAt) {
  final at = updatedAt == null ? null : DateTime.tryParse(updatedAt);
  if (at == null) return updatedAt ?? '';
  final t = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}

/// D15, spec §4.1: "Session history" — the agent's earlier sessions for
/// this folder (`session/list {cwd}`). The current one is marked and not
/// offered; another opens in a new AI tab that reopens it (`session/load`,
/// D14) through [onOpen].
Future<void> showAiHistory(
  BuildContext context,
  AiRuntime runtime, {
  required void Function(String sessionId, String? title) onOpen,
}) async {
  final result = await runtime.listSessions();
  if (!context.mounted) return;
  final state = runtime.state;
  await showDialog<void>(
    context: context,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      final dim = ShellxText.small.copyWith(
        color: ShellxDesktopColors.textSecondary,
      );
      final sessions = result?.sessions ?? const [];
      final Widget body;
      if (result == null) {
        body = Text(l10n.aiHistoryUnavailable(state.agentName), style: dim);
      } else if (sessions.isEmpty) {
        body = Text(l10n.aiHistoryEmpty, style: dim);
      } else {
        body = ListView.builder(
          itemCount: sessions.length,
          itemBuilder: (context, i) {
            final s = sessions[i];
            return ListTile(
              key: ValueKey('ai.history.${s.sessionId}'),
              dense: true,
              enabled: s.sessionId != state.sessionId,
              title: Text(
                (s.title?.trim().isNotEmpty ?? false)
                    ? s.title!
                    : l10n.aiHistoryUntitled,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(aiHistoryWhen(s.updatedAt), style: dim),
              trailing: s.sessionId == state.sessionId
                  ? Text(l10n.aiHistoryCurrent, style: dim)
                  : null,
              onTap: () {
                Navigator.of(context).pop();
                onOpen(s.sessionId, s.title);
              },
            );
          },
        );
      }
      return AlertDialog(
        key: const Key('ai.history.dialog'),
        title: Text(l10n.aiHistory),
        content: SizedBox(width: 480, height: 360, child: body),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.actionClose),
          ),
        ],
      );
    },
  );
}

import 'package:flutter/material.dart';
import 'package:shellx_ai/host.dart';

import '../../../l10n/app_localizations.dart';
import '../theme/shellx_desktop_theme.dart';
import 'ai_theme.dart';

/// "View log" (D20): the agent's stderr, kept in memory only (the last
/// 256 KiB). Shown, never logged.
Future<void> showAiLogDialog(BuildContext context, AiRuntime runtime) {
  final l10n = AppLocalizations.of(context);
  final text = runtime.stderrTail;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.aiLogTitle),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.aiLogNote,
              style: ShellxText.small.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
            const SizedBox(height: ShellxSpace.s8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: SingleChildScrollView(
                child: SelectableText(
                  text.isEmpty ? l10n.aiLogEmpty : text,
                  key: const Key('ai.log.text'),
                  style: kAiMono,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionClose),
        ),
      ],
    ),
  );
}

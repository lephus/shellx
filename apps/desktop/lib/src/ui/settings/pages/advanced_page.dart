import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../config/config_controller.dart';
import '../../theme/shellx_desktop_theme.dart';
import '../settings_row.dart';
import '../settings_values.dart';
import '../settings_writer.dart';
import 'page_parts.dart';

/// Advanced: Ghostty import, the configuration problems, the file itself and
/// "Undo everything changed here".
class AdvancedPage extends ConsumerWidget {
  const AdvancedPage({super.key, required this.onShowProblems});
  final VoidCallback onShowProblems;

  Future<void> _undoAll(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('settings.reset-all.dialog'),
        content: Text(l10n.settingsResetAllConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            key: const Key('settings.reset-all.confirm'),
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.settingsResetAll),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final result = await ref.read(settingsWriterProvider).resetAll();
    reportWrite(ref, result);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scope = SettingsScope.of(context);
    final problems = ref.watch(
      shellxConfigProvider.select((s) => s.visibleProblemCount),
    );
    final path = ref.watch(configPathsProvider).shellx;
    return PageFrame(
      children: [
        settingWidget(settingById('ghostty-config')),
        ActionRow(
          key: const Key('settings.problems'),
          label: l10n.settingsProblems(problems),
          button: l10n.settingsProblemsShow,
          onPressed: problems > 0 ? onShowProblems : null,
        ),
        ActionRow(
          key: const Key('settings.reload'),
          label: l10n.trayConfigReload,
          button: l10n.settingsReload,
          onPressed: () => unawaited(
            ref.read(shellxConfigProvider.notifier).load(manual: true),
          ),
        ),
        ActionRow(
          key: const Key('settings.config-path'),
          label: l10n.settingsConfigPath,
          caption: path,
          button: l10n.settingsCopyPath,
          onPressed: () =>
              unawaited(Clipboard.setData(ClipboardData(text: path))),
        ),
        ActionRow(
          key: const Key('settings.open-file-row'),
          label: l10n.settingsOpenFile,
          button: l10n.settingsOpenFile,
          onPressed: scope.onOpenFile,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: const Key('settings.reset-all'),
              style: OutlinedButton.styleFrom(
                foregroundColor: ShellxDesktopColors.err,
              ),
              onPressed: () => unawaited(_undoAll(context, ref)),
              child: Text(l10n.settingsResetAll),
            ),
          ),
        ),
      ],
    );
  }
}

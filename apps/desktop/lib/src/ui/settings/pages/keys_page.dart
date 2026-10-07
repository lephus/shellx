import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../config/config_controller.dart';
import '../../config/shortcuts_sheet.dart';
import '../../theme/shellx_desktop_theme.dart';
import '../settings_row.dart';
import 'page_parts.dart';

/// Keyboard shortcuts: the shortcut editor of A9, and the user's own
/// commands (read-only here).
class KeysPage extends ConsumerWidget {
  const KeysPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final names = [
      for (final c in ref.watch(
        shellxConfigProvider.select((s) => s.config.commands),
      ))
        c.name,
    ];
    final scope = SettingsScope.of(context);
    return PageFrame(
      scroll: false,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            names.isEmpty
                ? l10n.settingsCommandsNote
                : '${l10n.settingsCommandsNote} ${names.join(', ')}',
            key: const Key('settings.commands-note'),
            style: ShellxText.small.copyWith(
              color: ShellxDesktopColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: ShortcutsEditor(onOpenFile: scope.onOpenFile, embedded: true),
        ),
      ],
    );
  }
}

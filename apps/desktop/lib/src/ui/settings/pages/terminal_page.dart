import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../config/config_controller.dart';
import '../../../tray/tray_action.dart';
import '../../../tray/tray_actions.dart';
import 'page_parts.dart';

/// Terminal: scrollback, where new tabs start, Option as Alt (macOS), the
/// close question, the global show/hide shortcut, and what is saved when
/// the app quits.
class TerminalPage extends ConsumerWidget {
  const TerminalPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mac = ref.watch(configPlatformProvider) == TargetPlatform.macOS;
    final hasSaved = ref.watch(
      trayLocalStateProvider.select((s) => s.hasSavedScrollback),
    );
    return PageFrame(
      children: [
        settingWidget(
          settingById('scrollback-limit'),
          note: l10n.settingsScrollbackNote,
        ),
        settingWidget(settingById('working-directory')),
        if (mac) settingWidget(settingById('macos-option-as-alt')),
        settingWidget(settingById('confirm-close-surface')),
        settingWidget(settingById('restore-scrollback')),
        settingWidget(settingById('global-hotkey')),
        ActionRow(
          key: const Key('setting.clear-saved-scrollback'),
          label: l10n.trayClearSavedScrollback,
          button: l10n.trayClearSavedScrollback,
          onPressed: hasSaved
              ? () => unawaited(
                  ref
                      .read(trayActionsProvider)
                      .handle(const ClearSavedScrollback()),
                )
              : null,
        ),
      ],
    );
  }
}

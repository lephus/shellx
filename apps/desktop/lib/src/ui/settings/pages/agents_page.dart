import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../tray/tray_action.dart';
import '../../../tray/tray_actions.dart';
import 'page_parts.dart';

/// Agents: notifications, the long-command threshold, the `shellx` command
/// line and the SSH hook. Every switch is the tray's own.
class AgentsPage extends ConsumerWidget {
  const AgentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return PageFrame(
      children: [
        settingWidget(settingById('desktop-notifications')),
        settingWidget(settingById('desktop-notifications-only-unfocused')),
        settingWidget(settingById('notify-threshold')),
        SectionHeader(l10n.trayCommandLine),
        settingWidget(settingById('cli-control')),
        settingWidget(settingById('cli-allow-external')),
        settingWidget(settingById('cli-path')),
        ActionRow(
          key: const Key('setting.cli-skills'),
          label: l10n.trayCliCopySkills,
          button: l10n.trayCliCopySkills,
          onPressed: () => unawaited(
            ref.read(trayActionsProvider).handle(const CopySkillsCommand()),
          ),
        ),
        SectionHeader(l10n.sshTrayMenu),
        settingWidget(settingById('ssh-hook')),
      ],
    );
  }
}

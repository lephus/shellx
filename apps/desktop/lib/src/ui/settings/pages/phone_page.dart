import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../agent/agent_controller.dart';
import '../../../tray/tray_action.dart';
import '../../../tray/tray_actions.dart';
import '../../theme/shellx_desktop_theme.dart';
import 'page_parts.dart';

/// Phone: remote access, pairing, paired devices and terminal sharing. Signed
/// out the rows are locked and a "Sign in" button leads to the login window.
class PhonePage extends ConsumerWidget {
  const PhonePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final agent = ref.watch(agentControllerProvider);
    final handle = ref.read(trayActionsProvider).handle;
    final signedIn = agent.signedIn;
    return PageFrame(
      children: [
        if (!signedIn)
          ActionRow(
            key: const Key('settings.phone.sign-in'),
            label: l10n.settingsLoginNeeded,
            button: l10n.traySignIn,
            onPressed: () => unawaited(handle(const SignIn())),
          ),
        settingWidget(settingById('remote-access'), enabled: signedIn),
        ActionRow(
          key: const Key('setting.pair'),
          label: l10n.trayPairPhone,
          button: l10n.trayPairPhone,
          onPressed: signedIn && agent.remoteAccess
              ? () => unawaited(handle(const PairPhone()))
              : null,
        ),
        SectionHeader(l10n.trayPairedDevices),
        if (agent.trusted.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              l10n.trayNoDevices,
              style: ShellxText.small.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
          ),
        for (final device in agent.trusted)
          ActionRow(
            key: Key('setting.device.${device.mobileId}'),
            label: device.name,
            button: l10n.trayRevoke,
            onPressed: signedIn
                ? () => unawaited(handle(RevokeDevice(device.mobileId)))
                : null,
          ),
        if (agent.terminalSharing.available)
          settingWidget(
            settingById('terminal-sharing'),
            enabled: signedIn && !agent.terminalSharing.busy,
          ),
      ],
    );
  }
}

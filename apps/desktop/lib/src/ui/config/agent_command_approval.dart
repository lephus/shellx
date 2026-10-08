import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../integrations/agent_command_runner.dart';
import '../../terminal/sidebar_workspaces.dart' show settingsStoreProvider;
import '../window_router.dart';

/// A12 D17: asks whether ShellX may run [command] when an agent changes
/// state, showing the exact string. "Allow" stores its hash (never the
/// string). The dialog starts on Cancel: an approval is never the default
/// key.
Future<bool> reviewAgentCommand(
  WidgetRef ref,
  AppLocalizations l10n,
  String command,
) async {
  final router = ref.read(windowRouterProvider.notifier);
  final settings = ref.read(settingsStoreProvider);
  final ok = await router.confirm(
    ConfirmRequest(
      title: l10n.agentCommandApproveTitle,
      body: '${l10n.agentCommandApproveBody}\n\n$command',
      confirmLabel: l10n.agentCommandApproveAllow,
      cancelLabel: l10n.agentCommandApproveCancel,
      long: true,
    ),
  );
  if (!ok) return false;
  await approveCommand(settings, commandHash(command));
  return true;
}

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/agent_controller.dart';
import '../agent/desktop_services.dart';
import 'window_router.dart';

/// The user started ShellX again while it runs: a second launch (Windows,
/// or `open -n`: SingleInstanceLock.activationRequests) or, on macOS, a
/// reopen of the running app (app_reopen.dart). Signed out: the login
/// window. Signed in: a notification saying where ShellX lives (on macOS
/// the reopen also brings an open window forward). Never throws.
Future<void> handleActivation(
  ProviderContainer container, {
  required bool isWindows,
}) async {
  if (!container.read(agentControllerProvider).signedIn) {
    container.read(windowRouterProvider.notifier).open(const LoginRoute());
    return;
  }
  final services = container.read(desktopServicesProvider);
  final l10n = services.l10n;
  try {
    await services.notifier.show(
      title: l10n.notifyAlreadyRunningTitle,
      body: l10n.notifyAlreadyRunningBody(isWindows ? 'windows' : 'macos'),
    );
  } catch (error) {
    debugPrint(
      'ShellX: already-running notification failed: ${error.runtimeType}',
    );
  }
}

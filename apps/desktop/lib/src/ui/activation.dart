import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../terminal/terminal_tabs.dart';
import 'window_router.dart';

/// A1 D11: launch, a second launch, the Dock, a macOS reopen and the tray
/// all show the terminal window; with no tab at all, one is opened. Never
/// throws.
Future<void> openTerminalWindow({
  required WindowRouter router,
  required TerminalTabs tabs,
}) async {
  router.showTerminal();
  try {
    await tabs.ensureTab();
  } catch (error) {
    debugPrint('ShellX: opening a tab failed: ${error.runtimeType}');
  }
}

Future<void> handleActivation(ProviderContainer container) =>
    openTerminalWindow(
      router: container.read(windowRouterProvider.notifier),
      tabs: container.read(terminalTabsProvider.notifier),
    );

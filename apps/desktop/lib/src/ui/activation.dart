import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../terminal/tab_attention.dart';
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

/// A4 D16: a system notification was clicked. The window comes to the
/// front (no new tab, unlike activation; [activateApp] is macOS
/// `NSApp.activate`), then the tab is selected, its workspace expanded,
/// read at once and the terminal focused. A closed tab only raises the
/// window; so does a command-line notification (A7 D23), which also reads
/// the command-line entries.
void openTabFromNotification(
  ProviderContainer container,
  int tabId, {
  void Function()? activateApp,
}) {
  container.read(windowRouterProvider.notifier).showTerminal();
  activateApp?.call();
  final attention = container.read(tabAttentionProvider.notifier);
  if (tabId == kCommandLineTabId) {
    attention.markRead(kCommandLineTabId);
    return;
  }
  attention.jumpTo(tabId);
}

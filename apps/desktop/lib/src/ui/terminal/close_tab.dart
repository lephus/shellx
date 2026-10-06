import '../../../l10n/app_localizations.dart';
import '../../terminal/terminal_tabs.dart';
import '../window_router.dart';

/// ⌘W, "Đóng tab", middle click (D15, UI §3.1): asks first while the shell
/// hook reports a running command, otherwise closes at once.
Future<void> closeTabWithConfirm({
  required TerminalTabs tabs,
  required WindowRouter router,
  required AppLocalizations l10n,
  required TerminalTab tab,
}) async {
  if (tabs.needsCloseConfirm(tab.id)) {
    final ok = await router.confirm(
      ConfirmRequest(
        title: l10n.confirmCloseRunningTitle(tab.label),
        body: l10n.confirmCloseRunningBody,
        confirmLabel: l10n.confirmCloseRunningAction,
      ),
    );
    if (!ok) return;
  }
  tabs.close(tab.id);
}

/// ⌘W on a split tab, the pane ×, "Đóng pane" (D6, D28): asks while that
/// pane runs a command. A one-pane tab goes through [closeTabWithConfirm]
/// (the A1 dialog, word for word).
Future<void> closePaneWithConfirm({
  required TerminalTabs tabs,
  required WindowRouter router,
  required AppLocalizations l10n,
  required TerminalTab tab,
  required int paneId,
}) async {
  final pane = tab.panes[paneId];
  if (pane == null) return;
  if (!tab.isSplit) {
    return closeTabWithConfirm(
      tabs: tabs,
      router: router,
      l10n: l10n,
      tab: tab,
    );
  }
  if (tabs.needsPaneCloseConfirm(paneId)) {
    final ok = await router.confirm(
      ConfirmRequest(
        title: l10n.confirmCloseRunningTitle(pane.automaticLabel),
        body: l10n.confirmCloseRunningPaneBody,
        confirmLabel: l10n.confirmCloseRunningPaneAction,
      ),
    );
    if (!ok) return;
  }
  tabs.closePane(paneId);
}

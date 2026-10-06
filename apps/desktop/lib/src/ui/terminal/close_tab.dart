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

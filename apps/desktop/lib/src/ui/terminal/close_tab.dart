import '../../../l10n/app_localizations.dart';
import '../../config/shellx_config.dart' show ConfirmClose;
import '../../terminal/terminal_tabs.dart';
import '../window_router.dart';

/// ⌘W, "Đóng tab", middle click (D15, UI §3.1): asks first while the shell
/// hook reports a running command, otherwise closes at once; [confirm] is
/// A9 D20. A split tab says how many of its panes run one (D28).
Future<void> closeTabWithConfirm({
  required TerminalTabs tabs,
  required WindowRouter router,
  required AppLocalizations l10n,
  required TerminalTab tab,
  ConfirmClose confirm = ConfirmClose.whenRunning,
}) async {
  final running = tabs.runningPaneCount(tab.id);
  // V2-1 D3: an AI tab whose agent is working counts as running.
  final aiBusy = tab.isAi && (tabs.aiBusy?.call(tab.id) ?? false);
  // A11 D18: a pinned tab asks too, unless the user turned the question
  // off (confirm-close-surface = false).
  final pinned = tab.meta.pinned && confirm != ConfirmClose.never;
  // A9 D20: Ghostty's confirm-close-surface; `true` = A1 D15 / A3 D28.
  final ask =
      pinned ||
      switch (confirm) {
        ConfirmClose.never => false,
        ConfirmClose.always => true,
        ConfirmClose.whenRunning => running > 0 || aiBusy,
      };
  if (ask && aiBusy && !pinned) {
    // V2-1 D3: "Stop the turn and close?"
    final ok = await router.confirm(
      ConfirmRequest(
        title: l10n.aiCloseRunningTitle,
        body: l10n.aiCloseRunningBody(tab.ai?.agentName ?? ''),
        confirmLabel: l10n.aiCloseRunningAction,
      ),
    );
    if (!ok) return;
  } else if (ask) {
    final ok = await router.confirm(
      ConfirmRequest(
        title: pinned
            ? l10n.tabPinnedCloseTitle
            : l10n.confirmCloseRunningTitle(tab.label),
        body: pinned
            ? [
                l10n.tabPinnedCloseBody(tab.label),
                if (running > 0)
                  tab.isSplit
                      ? l10n.confirmCloseRunningPanesBody(running)
                      : l10n.confirmCloseRunningBody,
              ].join(' ')
            : running > 0
            ? (tab.isSplit
                  ? l10n.confirmCloseRunningPanesBody(running)
                  : l10n.confirmCloseRunningBody)
            : (tab.isSplit
                  ? l10n.confirmCloseAlwaysPanesBody(tab.paneCount)
                  : l10n.confirmCloseAlwaysBody),
        confirmLabel: l10n.confirmCloseRunningAction,
      ),
    );
    if (!ok) return;
  }
  tabs.close(tab.id);
}

/// ⌘W on a split tab, the pane ×, "Đóng pane" (D6, D28): asks while that
/// pane runs a command (A9 D20 [confirm]). A one-pane tab goes through
/// [closeTabWithConfirm].
Future<void> closePaneWithConfirm({
  required TerminalTabs tabs,
  required WindowRouter router,
  required AppLocalizations l10n,
  required TerminalTab tab,
  required int paneId,
  ConfirmClose confirm = ConfirmClose.whenRunning,
}) async {
  // V2-1 D3: closing the AI pane closes its tab.
  if (isAiPaneId(paneId)) {
    return closeTabWithConfirm(
      tabs: tabs,
      router: router,
      l10n: l10n,
      tab: tab,
      confirm: confirm,
    );
  }
  final pane = tab.panes[paneId];
  if (pane == null) return;
  if (!tab.isSplit) {
    return closeTabWithConfirm(
      tabs: tabs,
      router: router,
      l10n: l10n,
      tab: tab,
      confirm: confirm,
    );
  }
  final running = tabs.needsPaneCloseConfirm(paneId);
  final ask = switch (confirm) {
    ConfirmClose.never => false,
    ConfirmClose.always => true,
    ConfirmClose.whenRunning => running,
  };
  if (ask) {
    final ok = await router.confirm(
      ConfirmRequest(
        title: l10n.confirmCloseRunningTitle(pane.automaticLabel),
        body: running
            ? l10n.confirmCloseRunningPaneBody
            : l10n.confirmClosePaneAlwaysBody,
        confirmLabel: l10n.confirmCloseRunningPaneAction,
      ),
    );
    if (!ok) return;
  }
  tabs.closePane(paneId);
}

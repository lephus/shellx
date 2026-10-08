import 'dart:async';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:xterm/xterm.dart' show TerminalStyle;

import '../../../l10n/app_localizations.dart';
import '../../agent/agent_controller.dart';
import '../../agent/agent_state.dart';
import '../../agent/desktop_services.dart' show clockProvider;
import '../../mux/daemon_state.dart';
import '../../restore/restore_persistence.dart';
import '../../restore/scrollback_codec.dart' show formatRestoreTime;
import '../../terminal/sidebar_workspaces.dart';
import '../../terminal/tab_attention.dart';
import '../../terminal/terminal_appearance.dart';
import '../../terminal/terminal_font_size.dart';
import '../../terminal/terminal_style.dart';
import '../../remote/ssh_actions.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import '../window_router.dart';
import 'info_strip.dart';
import 'key_sequence.dart';
import 'pane_tree_view.dart';
import 'shortcut_labels.dart';
import 'terminal_overlays.dart';

/// UI §2.1 pane header (macOS) and §2.3 pane: the signed-out strip, one
/// TerminalView per tab (all mounted, so hidden tabs keep their buffer),
/// and the overlays that never resize the terminal (driver pill, toast).
class TerminalPane extends ConsumerStatefulWidget {
  const TerminalPane({
    super.key,
    required this.terminalFocus,
    required this.emptyFocus,
    this.stripFocus,
    this.restoreStripFocus,
    this.daemonStripFocus,
    this.shortcuts,
    this.onKeyEvent,
    required this.onClosePane,
    this.onShowConfigProblems,
  });

  /// The selected tab's TerminalView focus (UI §3.6 region 1).
  final FocusNode terminalFocus;

  /// The empty state's "Open new tab" button.
  final FocusNode emptyFocus;

  /// The signed-out strip's button (UI §3.6 region 3).
  final FocusNode? stripFocus;

  /// The abnormal-end strip's "Đóng" (UI-A5 §4, between the sidebar and
  /// the terminal in the region cycle).
  final FocusNode? restoreStripFocus;

  /// The background-service strip's "Đóng" (UI-A5 §7.5, right after the
  /// restore strip).
  final FocusNode? daemonStripFocus;

  /// Passed to every TerminalView: the window shortcuts must win over
  /// xterm's own key handling.
  final Map<ShortcutActivator, Intent>? shortcuts;

  /// A key reaching a pane's terminal first (A9 D28 key sequences).
  final KeyEventResult Function(KeyEvent event)? onKeyEvent;

  /// A pane's ×, middle click (UI-A3 §2.1): the workspace asks first when
  /// a command runs there.
  final void Function(int sessionId) onClosePane;

  /// The toast's "Show" for configuration problems (A9).
  final VoidCallback? onShowConfigProblems;

  @override
  ConsumerState<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends ConsumerState<TerminalPane> {
  /// One scrollback controller per pane (the overlay scrollbar of UI §2.3).
  final _scrolls = <int, ScrollController>{};

  ScrollController _scrollFor(int id) =>
      _scrolls.putIfAbsent(id, ScrollController.new);

  /// Controllers of closed panes go after the frame that unmounts their
  /// view.
  void _dropClosed(List<TerminalTab> tabs) {
    final ids = {for (final tab in tabs) ...tab.panes.keys};
    final gone = [
      for (final id in _scrolls.keys)
        if (!ids.contains(id)) id,
    ];
    if (gone.isEmpty) return;
    final controllers = [for (final id in gone) _scrolls.remove(id)!];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in controllers) {
        c.dispose();
      }
    });
  }

  StreamSubscription<PaneReplacement>? _replacements;

  @override
  void dispose() {
    unawaited(_replacements?.cancel());
    for (final c in _scrolls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _dismiss(TabNotice notice) {
    // An outgoing toast's timer must not dismiss the notice that replaced it.
    if (identical(ref.read(terminalTabsProvider).notice, notice)) {
      ref.read(terminalTabsProvider.notifier).dismissNotice();
    }
  }

  @override
  void initState() {
    super.initState();
    // A8 D22: the scrollback controller follows a reconnected pane.
    _replacements = ref
        .read(terminalTabsProvider.notifier)
        .paneReplacements
        .listen((r) {
          final c = _scrolls.remove(r.from);
          if (c != null) _scrolls[r.to] = c;
        });
    // UI-A5 §4: polite, once, when a strip appears (also one shown before
    // this pane was built).
    ref.listenManual<RestoreStripState?>(restoreStripProvider, (_, next) {
      if (next != null) _announceStrip(next);
    }, fireImmediately: true);
  }

  void _announceStrip(RestoreStripState strip) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(ref.read(restoreStripProvider), strip)) {
        return;
      }
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          _restoreStripText(strip),
          Directionality.of(context),
        ),
      );
    });
  }

  /// D12, D24: dismissed for this run; the keyboard goes to the terminal.
  void _dismissStrip() {
    ref.read(restoreStripProvider.notifier).dismiss();
    _returnFocus();
  }

  String _restoreStripText(RestoreStripState strip) {
    final l10n = AppLocalizations.of(context);
    final at = strip.contentsAt;
    return at == null
        ? l10n.restoreAbnormalNoText(strip.tabs)
        : l10n.restoreAbnormalStrip(
            strip.tabs,
            formatRestoreTime(
              at,
              ref.read(clockProvider)(),
              localeName: l10n.localeName,
              yesterday: l10n.restoreTimeYesterday,
            ),
          );
  }

  Widget _restoreStrip(RestoreStripState? strip) {
    if (strip == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return InfoStrip(
      key: const Key('pane.restoreStrip'),
      icon: Icons.history,
      iconColor: ShellxDesktopColors.textSecondary,
      text: _restoreStripText(strip),
      closeText: l10n.actionClose,
      closeLabel: l10n.restoreStripCloseLabel,
      focusNode: widget.restoreStripFocus,
      onClose: _dismissStrip,
    );
  }

  /// UI-A5 §7.5: the service restarted, or could not be restarted.
  Widget _daemonStrip(DaemonUiState daemon) {
    final strip = daemon.strip;
    if (strip == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final lost = strip == DaemonStrip.lost;
    if (strip == DaemonStrip.stopping) {
      return InfoStrip(
        key: const Key('pane.daemonStrip'),
        icon: Icons.hourglass_empty,
        iconColor: ShellxDesktopColors.textSecondary,
        text: l10n.daemonStoppingStrip,
        closeText: l10n.actionClose,
        closeLabel: l10n.restoreStripCloseLabel,
        focusNode: widget.daemonStripFocus,
        onClose: () => ref.read(daemonStateProvider.notifier).dismissStrip(),
      );
    }
    return InfoStrip(
      key: const Key('pane.daemonStrip'),
      icon: lost ? Icons.error_outline : Icons.history,
      iconColor: lost
          ? ShellxDesktopColors.err
          : ShellxDesktopColors.textSecondary,
      text: lost ? l10n.daemonLostStrip : l10n.daemonRestartedStrip,
      closeText: l10n.actionClose,
      closeLabel: l10n.restoreStripCloseLabel,
      focusNode: widget.daemonStripFocus,
      onClose: () {
        ref.read(daemonStateProvider.notifier).dismissStrip();
        _returnFocus();
      },
      actions: [
        if (lost)
          TextButton(
            key: const Key('daemonStrip.retry'),
            style: stripTextButtonStyle(context),
            onPressed: daemon.retrying
                ? null
                : () =>
                      unawaited(ref.read(daemonStateProvider.notifier).retry()),
            child: daemon.retrying
                ? Semantics(
                    label: l10n.daemonRetryLabel,
                    child: const SizedBox.square(
                      dimension: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Text(l10n.daemonRetry, semanticsLabel: l10n.daemonRetryLabel),
          ),
      ],
    );
  }

  /// Where the keyboard goes when the toast it was on disappears.
  void _returnFocus() {
    final empty = ref.read(terminalTabsProvider).tabs.isEmpty;
    (empty ? widget.emptyFocus : widget.terminalFocus).requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(terminalTabsProvider);
    final fontSize = ref.watch(terminalFontSizeProvider);
    final phase = ref.watch(agentControllerProvider.select((s) => s.phase));
    final selected = state.selected;
    // UI-A4 §4, A3 D18: the selected tab's panes that notified are ringed.
    // Only the unread map matters here, not the history.
    final unread = ref.watch(tabAttentionProvider.select((a) => a.unread));
    Set<int> unreadPanes(int tabId) =>
        unread[tabId]?.panes.keys.toSet() ?? const <int>{};
    // A9: font, theme, cursor and padding follow the configuration live.
    final appearance = ref.watch(terminalAppearanceProvider);
    final padding = appearance.padding;
    final style = desktopTerminalStyle(
      fontSize,
      families: appearance.families,
      regular: appearance.regular,
      cellHeightPercent: appearance.cellHeightPercent,
    );
    // A11 D19: a tab draws at the global size plus its workspace's step.
    // Only the steps are watched, so a sidebar change that moves none
    // rebuilds nothing here.
    final steps = ref.watch(sidebarWorkspacesProvider.select(_tabSteps));
    final styles = <double, TerminalStyle>{0: style};
    TerminalStyle styleFor(int tabId) => styles.putIfAbsent(
      steps.of(tabId),
      () => desktopTerminalStyle(
        effectiveFontSize(fontSize, steps.of(tabId)),
        families: appearance.families,
        regular: appearance.regular,
        cellHeightPercent: appearance.cellHeightPercent,
      ),
    );
    final tabs = ref.read(terminalTabsProvider.notifier);
    final selectedIndex = selected == null ? 0 : state.tabs.indexOf(selected);
    _dropClosed(state.tabs);
    final notice = state.notice;
    final restoreStrip = ref.watch(restoreStripProvider);
    final daemon = ref.watch(daemonStateProvider);

    return ColoredBox(
      color: ShellxDesktopColors.bgTerminal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isMacDesktop)
            DragToMoveArea(
              child: SizedBox(
                height: ShellxSizes.paneHeaderMac,
                child: Center(
                  child: FractionallySizedBox(
                    widthFactor: ShellxSizes.paneHeaderTitleFactor,
                    child: ExcludeSemantics(
                      child: Text(
                        selected?.label ?? 'ShellX',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ShellxText.small.copyWith(
                          color: ShellxDesktopColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          AnimatedSwitcher(
            duration: ShellxMotion.of(context, ShellxMotion.base),
            switchInCurve: ShellxMotion.baseCurve,
            layoutBuilder: _stretch,
            child: phase == AuthPhase.signedOut
                ? SignedOutStrip(
                    focusNode: widget.stripFocus,
                    onSignIn: () => ref
                        .read(windowRouterProvider.notifier)
                        .open(const LoginRoute()),
                  )
                : const SizedBox.shrink(),
          ),
          // UI-A5 §4: under the signed-out strip; leaves with a 120 ms
          // fade, taking no keyboard or clicks on its way out.
          AnimatedSwitcher(
            duration: ShellxMotion.of(context, ShellxMotion.base),
            reverseDuration: ShellxMotion.of(context, ShellxMotion.exit),
            switchInCurve: ShellxMotion.baseCurve,
            switchOutCurve: ShellxMotion.exitCurve,
            transitionBuilder: _stripTransition,
            layoutBuilder: _stretch,
            child: _restoreStrip(restoreStrip),
          ),
          // UI-A5 §7.5: after the restore strip, same fade.
          AnimatedSwitcher(
            duration: ShellxMotion.of(context, ShellxMotion.base),
            reverseDuration: ShellxMotion.of(context, ShellxMotion.exit),
            switchInCurve: ShellxMotion.baseCurve,
            switchOutCurve: ShellxMotion.exitCurve,
            transitionBuilder: _stripTransition,
            layoutBuilder: _stretch,
            child: _daemonStrip(daemon),
          ),
          Expanded(
            // D15: the terminal area (padding and the cells around panes)
            // takes the theme's background; the chrome above keeps ShellX's.
            child: ColoredBox(
              key: const ValueKey('terminal.area'),
              color: appearance.background,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final grid = measureTerminalGrid(
                    padding.deflateSize(constraints.biggest),
                    style,
                    MediaQuery.textScalerOf(context),
                  );
                  // Only stores the size for the next open: safe during layout.
                  if (grid != null) tabs.reportGrid(grid);
                  final scaler = MediaQuery.textScalerOf(context);
                  // The selected tab's own size (A11 D19): its panes are the
                  // ones being laid out.
                  final cell = measureTerminalCell(
                    styleFor(selected?.id ?? -1),
                    scaler,
                  );
                  // D4: 20 × 5 cells + padding + the pane header.
                  tabs.reportPaneMetrics(
                    PaneMetrics(
                      area: constraints.biggest,
                      minPane: Size(
                        ShellxSizes.paneMinCols * cell.width +
                            padding.horizontal,
                        ShellxSizes.paneMinRows * cell.height +
                            padding.vertical +
                            ShellxSizes.paneHeaderFor(scaler),
                      ),
                      divider: ShellxSizes.paneDivider,
                      // The real one: a test or an embedder may override
                      // MediaQuery's.
                      devicePixelRatio: View.of(context).devicePixelRatio,
                    ),
                  );
                  return Stack(
                    children: [
                      if (state.tabs.isEmpty)
                        // The empty state uses ShellX's own (dark) text
                        // tokens, so it keeps ShellX's background even under
                        // a light theme (D15).
                        Positioned.fill(
                          child: ColoredBox(
                            color: ShellxDesktopColors.bgTerminal,
                            child: EmptyTerminalState(
                              onOpen: () => unawaited(
                                ref.read(sshActionsProvider).newTab(),
                              ),
                              buttonFocus: widget.emptyFocus,
                            ),
                          ),
                        )
                      else
                        Positioned.fill(
                          child: IndexedStack(
                            index: selectedIndex < 0 ? 0 : selectedIndex,
                            sizing: StackFit.expand,
                            children: [
                              for (final tab in state.tabs)
                                PaneTreeView(
                                  key: ValueKey('terminal.${tab.id}'),
                                  tab: tab,
                                  selected: tab.id == selected?.id,
                                  terminalFocus: widget.terminalFocus,
                                  style: styleFor(tab.id),
                                  shortcuts: widget.shortcuts,
                                  onKeyEvent: widget.onKeyEvent,
                                  scrollFor: _scrollFor,
                                  onClosePane: widget.onClosePane,
                                  ringed: tab.id == selected?.id
                                      ? unreadPanes(tab.id)
                                      : const <int>{},
                                  // A pane with unread hidden by the zoom.
                                  hiddenUnread:
                                      tab.zoomedPaneId != null &&
                                      unreadPanes(
                                        tab.id,
                                      ).any((id) => id != tab.zoomedPaneId),
                                  toastShowing: notice != null,
                                ),
                            ],
                          ),
                        ),
                      // UI §2.8: one toast, bottom centre of the whole area.
                      // UI-A9 §5: the sequence pill is bottom right of the area,
                      // over every pane; above a toast, never under it.
                      Positioned(
                        bottom: ShellxSpace.s16,
                        left: ShellxSpace.s12,
                        right: ShellxSpace.s12,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Align(
                              alignment: Alignment.centerRight,
                              child: SequenceIndicator(),
                            ),
                            if (notice != null)
                              const SizedBox(height: ShellxSpace.s8),
                            Center(
                              child: AnimatedSwitcher(
                                duration: ShellxMotion.of(
                                  context,
                                  ShellxMotion.toastIn,
                                ),
                                reverseDuration: ShellxMotion.of(
                                  context,
                                  ShellxMotion.exit,
                                ),
                                switchInCurve: ShellxMotion.baseCurve,
                                switchOutCurve: ShellxMotion.exitCurve,
                                transitionBuilder: _toastTransition,
                                child: notice == null
                                    ? const SizedBox.shrink()
                                    : NoticeToast(
                                        key: ObjectKey(notice),
                                        notice: notice,
                                        onDismiss: () => _dismiss(notice),
                                        onReturnFocus: _returnFocus,
                                        onAction: widget.onShowConfigProblems,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The strip spans the pane width while it fades.
  static Widget _stretch(Widget? current, List<Widget> previous) =>
      Stack(fit: StackFit.passthrough, children: [...previous, ?current]);

  /// A fade; the outgoing strip takes no clicks and no keyboard.
  static Widget _stripTransition(Widget child, Animation<double> animation) =>
      AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final leaving = animation.status == AnimationStatus.reverse;
          return IgnorePointer(
            ignoring: leaving,
            child: ExcludeFocus(excluding: leaving, child: child!),
          );
        },
        child: FadeTransition(opacity: animation, child: child),
      );

  /// UI §1.5 toast: fade + translateY 8 → 0.
  static Widget _toastTransition(Widget child, Animation<double> animation) =>
      FadeTransition(
        opacity: animation,
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, ShellxSpace.s8 * (1 - animation.value)),
            child: child,
          ),
          child: child,
        ),
      );
}

/// A11 D19: the text size step of every tab whose workspace has one, with
/// value equality so `select` only fires when a step really changes.
@immutable
final class _TabSteps {
  const _TabSteps(this._byTab);
  final Map<int, double> _byTab;

  double of(int tabId) => _byTab[tabId] ?? 0;

  @override
  bool operator ==(Object other) =>
      other is _TabSteps && mapEquals(other._byTab, _byTab);

  @override
  int get hashCode => Object.hashAllUnordered([
    for (final e in _byTab.entries) Object.hash(e.key, e.value),
  ]);
}

_TabSteps _tabSteps(SidebarState s) => _TabSteps({
  for (final w in s.workspaces)
    if (w.fontStep != 0)
      for (final id in s.tabsOf(w.id)) id: w.fontStep,
});

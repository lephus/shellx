import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_core/shellx_core.dart';
import 'package:window_manager/window_manager.dart';
import 'package:xterm/xterm.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/agent_controller.dart';
import '../../agent/agent_state.dart';
import '../../terminal/terminal_font_size.dart';
import '../../terminal/terminal_style.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import '../theme/terminal_colors.dart';
import '../window_router.dart';
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
    this.shortcuts,
  });

  /// The selected tab's TerminalView focus (UI §3.6 region 1).
  final FocusNode terminalFocus;

  /// The empty state's "Open new tab" button.
  final FocusNode emptyFocus;

  /// The signed-out strip's button (UI §3.6 region 3).
  final FocusNode? stripFocus;

  /// Passed to every TerminalView: the window shortcuts must win over
  /// xterm's own key handling.
  final Map<ShortcutActivator, Intent>? shortcuts;

  @override
  ConsumerState<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends ConsumerState<TerminalPane> {
  /// One scrollback controller per tab (the overlay scrollbar of UI §2.3).
  final _scrolls = <int, ScrollController>{};

  ScrollController _scrollFor(int id) =>
      _scrolls.putIfAbsent(id, ScrollController.new);

  /// Controllers of closed tabs go after the frame that unmounts their view.
  void _dropClosed(List<TerminalTab> tabs) {
    final ids = {for (final tab in tabs) tab.id};
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

  @override
  void dispose() {
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

  /// Where the keyboard goes when the toast it was on disappears.
  void _returnFocus() {
    final empty = ref.read(terminalTabsProvider).tabs.isEmpty;
    (empty ? widget.emptyFocus : widget.terminalFocus).requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(terminalTabsProvider);
    final fontSize = ref.watch(terminalFontSizeProvider);
    final phase = ref.watch(agentControllerProvider.select((s) => s.phase));
    final selected = state.selected;
    final style = desktopTerminalStyle(fontSize);
    final tabs = ref.read(terminalTabsProvider.notifier);
    final selectedIndex = selected == null ? 0 : state.tabs.indexOf(selected);
    _dropClosed(state.tabs);
    final notice = state.notice;
    final phoneDrives =
        selected != null &&
        !selected.exited &&
        selected.driver == DriverSide.phone;

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
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final grid = measureTerminalGrid(
                  ShellxSizes.terminalPadding.deflateSize(constraints.biggest),
                  style,
                  MediaQuery.textScalerOf(context),
                );
                // Only stores the size for the next open: safe during layout.
                if (grid != null) tabs.reportGrid(grid);
                return Stack(
                  children: [
                    if (state.tabs.isEmpty)
                      Positioned.fill(
                        child: EmptyTerminalState(
                          onOpen: tabs.openTab,
                          buttonFocus: widget.emptyFocus,
                        ),
                      )
                    else
                      Positioned.fill(
                        child: IndexedStack(
                          index: selectedIndex < 0 ? 0 : selectedIndex,
                          sizing: StackFit.expand,
                          children: [
                            for (final tab in state.tabs)
                              _TabTerminal(
                                key: ValueKey('terminal.${tab.id}'),
                                tab: tab,
                                label: l10n.terminalPaneLabel(tab.label),
                                scrollController: _scrollFor(tab.id),
                                focusNode: tab.id == selected?.id
                                    ? widget.terminalFocus
                                    : null,
                                style: style,
                                shortcuts: widget.shortcuts,
                              ),
                          ],
                        ),
                      ),
                    Positioned(
                      top: ShellxSpace.s8,
                      left: ShellxSpace.s16,
                      right: ShellxSpace.s16,
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: ShellxMotion.of(context, ShellxMotion.base),
                          reverseDuration: ShellxMotion.of(
                            context,
                            ShellxMotion.exit,
                          ),
                          switchInCurve: ShellxMotion.baseCurve,
                          switchOutCurve: ShellxMotion.exitCurve,
                          child: phoneDrives
                              ? const DriverPill()
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: ShellxSpace.s16,
                      left: ShellxSpace.s16,
                      right: ShellxSpace.s16,
                      child: Center(
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
                                ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// The strip spans the pane width while it fades.
  static Widget _stretch(Widget? current, List<Widget> previous) =>
      Stack(fit: StackFit.passthrough, children: [...previous, ?current]);

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

/// One tab's terminal with its overlay scrollbar (UI §2.3) and the
/// "Terminal {title}" label (UI §3.7).
class _TabTerminal extends StatelessWidget {
  const _TabTerminal({
    super.key,
    required this.tab,
    required this.label,
    required this.scrollController,
    required this.focusNode,
    required this.style,
    required this.shortcuts,
  });

  final TerminalTab tab;
  final String label;
  final ScrollController scrollController;
  final FocusNode? focusNode;
  final TerminalStyle style;
  final Map<ShortcutActivator, Intent>? shortcuts;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    container: true,
    child: ShellxScrollbar(
      controller: scrollController,
      child: TerminalView(
        tab.terminal,
        controller: tab.selection,
        scrollController: scrollController,
        focusNode: focusNode,
        autofocus: focusNode != null,
        theme: TerminalColors.theme,
        textStyle: style,
        padding: ShellxSizes.terminalPadding,
        shortcuts: shortcuts,
      ),
    ),
  );
}

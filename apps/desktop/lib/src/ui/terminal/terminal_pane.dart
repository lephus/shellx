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
import 'shellx_menu.dart';
import 'shortcut_labels.dart';
import 'terminal_shortcuts.dart';
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
                    // UI §2.5 (ruling S-2): top-right, clear of where
                    // people read; when the cursor (the prompt line) is
                    // under that corner it moves to the bottom-right.
                    if (selected != null)
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: ShellxSpace.s8,
                            horizontal: ShellxSpace.s12,
                          ),
                          child: _DriverPillSlot(
                            terminal: selected.terminal,
                            cellHeight: measureTerminalCell(
                              style,
                              MediaQuery.textScalerOf(context),
                            ).height,
                            // The toast owns the bottom while it shows.
                            canMoveDown: notice == null,
                            child: AnimatedSwitcher(
                              duration: ShellxMotion.of(
                                context,
                                ShellxMotion.base,
                              ),
                              reverseDuration: ShellxMotion.of(
                                context,
                                ShellxMotion.exit,
                              ),
                              switchInCurve: ShellxMotion.baseCurve,
                              switchOutCurve: ShellxMotion.exitCurve,
                              child: phoneDrives
                                  ? DriverPill(
                                      compact:
                                          constraints.maxWidth <
                                          ShellxSizes.pillCompactBelow,
                                    )
                                  : const SizedBox.shrink(),
                            ),
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
    // A buffer scrolled by part of a row paints that row outside the
    // view; the clip keeps it off the signed-out strip and pane header.
    child: ClipRect(
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
          // Only when the program did not take the mouse (xterm reports
          // the click to it first): vim or htop with mouse mode keep it.
          onSecondaryTapUp: (details, _) =>
              _menu(context, details.globalPosition),
        ),
      ),
    ),
  );

  /// Ruling I6: Copy (only with a selection), Paste, Select all, through
  /// the window's own actions so the menu and the shortcuts do the same.
  Future<void> _menu(BuildContext context, Offset at) async {
    final l10n = AppLocalizations.of(context);
    final intent = await showShellxMenu<Intent>(
      context: context,
      at: at,
      entries: [
        ShellxMenuEntry(
          key: const Key('menu.copy'),
          value: const CopySelectionIntent(),
          label: l10n.terminalCopy,
          shortcut: copyShortcutLabel(),
          enabled: tab.selection.selection != null,
        ),
        ShellxMenuEntry(
          key: const Key('menu.paste'),
          value: const PasteClipboardIntent(),
          label: l10n.terminalPaste,
          shortcut: pasteShortcutLabel(),
        ),
        ShellxMenuEntry(
          key: const Key('menu.selectAll'),
          value: const SelectAllIntent(),
          label: l10n.terminalSelectAll,
          shortcut: selectAllShortcutLabel(),
        ),
      ],
    );
    if (intent == null || !context.mounted) return;
    Actions.maybeInvoke(context, intent);
    focusNode?.requestFocus();
  }
}

/// Puts the driver pill top-right, or bottom-right while the cursor is on
/// the rows the top corner covers (a fresh prompt is on the first row).
/// Follows the terminal as it writes, rebuilding only when the corner
/// changes.
class _DriverPillSlot extends StatefulWidget {
  const _DriverPillSlot({
    required this.terminal,
    required this.cellHeight,
    required this.canMoveDown,
    required this.child,
  });

  final Terminal terminal;
  final double cellHeight;
  final bool canMoveDown;
  final Widget child;

  @override
  State<_DriverPillSlot> createState() => _DriverPillSlotState();
}

class _DriverPillSlotState extends State<_DriverPillSlot> {
  late bool _down = _cursorUnderCorner();

  @override
  void initState() {
    super.initState();
    widget.terminal.addListener(_onTerminal);
  }

  @override
  void didUpdateWidget(_DriverPillSlot old) {
    super.didUpdateWidget(old);
    if (!identical(old.terminal, widget.terminal)) {
      old.terminal.removeListener(_onTerminal);
      widget.terminal.addListener(_onTerminal);
    }
    _down = _cursorUnderCorner();
  }

  @override
  void dispose() {
    widget.terminal.removeListener(_onTerminal);
    super.dispose();
  }

  /// The rows under the pill's corner: its 8 px inset and 28 px height,
  /// past the terminal's own top padding.
  bool _cursorUnderCorner() {
    final cell = widget.cellHeight;
    if (cell <= 0) return false;
    final covered =
        ((ShellxSpace.s8 +
                    ShellxSizes.driverPill -
                    ShellxSizes.terminalPadding.top) /
                cell)
            .ceil();
    return widget.terminal.buffer.cursorY < covered;
  }

  void _onTerminal() {
    final down = _cursorUnderCorner();
    if (down != _down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: _down && widget.canMoveDown
        ? Alignment.bottomRight
        : Alignment.topRight,
    child: widget.child,
  );
}

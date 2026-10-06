import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import 'session_tab_row.dart';
import 'shortcut_labels.dart';
import 'terminal_overlays.dart';

/// UI §2.2: header band with `+`, then the tab list.
class SessionSidebar extends ConsumerStatefulWidget {
  const SessionSidebar({
    super.key,
    required this.focusNode,
    required this.scrollController,
    required this.onSelected,
    required this.onClose,
  });

  /// The list's single tab stop (UI §3.6).
  final FocusNode focusNode;

  /// Owned by the workspace page (outlives rebuilds).
  final ScrollController scrollController;

  /// After a click: select + focus the terminal (UI §3.1).
  final void Function(int id) onSelected;
  final void Function(TerminalTab tab) onClose;

  @override
  ConsumerState<SessionSidebar> createState() => _SessionSidebarState();
}

class _SessionSidebarState extends ConsumerState<SessionSidebar> {
  /// Rows by tab id, so Shift+F10 can open the selected row's menu.
  final _rows = <int, GlobalKey<SessionTabRowState>>{};

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_refresh);
    FocusManager.instance.addHighlightModeListener(_onHighlightMode);
  }

  @override
  void didUpdateWidget(SessionSidebar old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_refresh);
      widget.focusNode.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_refresh);
    FocusManager.instance.removeHighlightModeListener(_onHighlightMode);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _onHighlightMode(FocusHighlightMode _) => _refresh();

  /// The ring shows only for keyboard focus (UI §3).
  bool get _showFocus =>
      widget.focusNode.hasFocus &&
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final menu =
        key == LogicalKeyboardKey.contextMenu ||
        (key == LogicalKeyboardKey.f10 &&
            HardwareKeyboard.instance.isShiftPressed);
    if (!menu) return KeyEventResult.ignored;
    final id = ref.read(terminalTabsProvider).selectedId;
    if (id == null) return KeyEventResult.ignored;
    _rows[id]?.currentState?.openMenu();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(terminalTabsProvider);
    final mac = isMacDesktop;
    final shortcut = newTabShortcutLabel();
    final newTab = ShellxIconButton(
      key: const Key('sidebar.newTab'),
      icon: Icons.add,
      semanticLabel: l10n.terminalNewTab,
      tooltip: shortcutTooltip(l10n.terminalNewTabTooltip(shortcut), shortcut),
      busy: state.opening,
      onPressed: () => ref.read(terminalTabsProvider.notifier).openTab(),
    );
    final band = SizedBox(
      height: mac ? ShellxSizes.headerBandMac : ShellxSizes.headerBandWindows,
      child: Row(
        crossAxisAlignment: mac
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          // macOS: the traffic lights own the left 80 px (UI §2.1).
          if (mac) const SizedBox(width: ShellxSizes.trafficLightsInset),
          const Spacer(),
          Padding(
            // macOS: centred on the traffic-light line y = 14 (UI §2.1).
            padding: EdgeInsets.only(
              top: mac
                  ? ShellxSizes.trafficLightsCenterY - ShellxSizes.iconHit / 2
                  : 0,
            ),
            child: newTab,
          ),
          // 8 px from the right edge to the 24 px visual (28 hit − 24) / 2.
          const SizedBox(
            width:
                ShellxSpace.s8 -
                (ShellxSizes.iconHit - ShellxSizes.iconVisual) / 2,
          ),
        ],
      ),
    );

    final ids = {for (final tab in state.tabs) tab.id};
    _rows.removeWhere((id, _) => !ids.contains(id));

    return ColoredBox(
      color: ShellxDesktopColors.bgSidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mac) DragToMoveArea(child: band) else band,
          Expanded(
            child: Semantics(
              label: l10n.sidebarLabel,
              container: true,
              child: Focus(
                focusNode: widget.focusNode,
                onKeyEvent: _onKey,
                child: ShellxScrollbar(
                  controller: widget.scrollController,
                  showOnHover: true,
                  child: ListView.separated(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.fromLTRB(
                      ShellxSizes.listMarginH,
                      ShellxSizes.listTop,
                      ShellxSizes.listMarginH,
                      ShellxSizes.listBottom,
                    ),
                    itemCount: state.tabs.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: ShellxSizes.rowGap),
                    itemBuilder: (context, i) {
                      final tab = state.tabs[i];
                      final selected = tab.id == state.selectedId;
                      return KeyedSubtree(
                        key: ValueKey('tab.${tab.id}'),
                        child: SessionTabRow(
                          key: _rows.putIfAbsent(tab.id, GlobalKey.new),
                          tab: tab,
                          selected: selected,
                          focused: selected && _showFocus,
                          position: i + 1,
                          count: state.tabs.length,
                          onSelect: () => widget.onSelected(tab.id),
                          onClose: () => widget.onClose(tab),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

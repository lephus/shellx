import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../l10n/app_localizations.dart';
import '../../terminal/sidebar_workspaces.dart';
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
    required this.onEscape,
  });

  /// The list's single tab stop (UI §3.6).
  final FocusNode focusNode;

  /// Owned by the workspace page (outlives rebuilds).
  final ScrollController scrollController;

  /// After a click: select + focus the terminal (UI §3.1).
  final void Function(int id) onSelected;
  final void Function(TerminalTab tab) onClose;

  /// Esc in the list: back to the terminal (UI §3.6).
  final VoidCallback onEscape;

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

  /// The rows on screen, in the sidebar's visible order (C5).
  List<TerminalTab> _visibleTabs() {
    final byId = {for (final t in ref.read(terminalTabsProvider).tabs) t.id: t};
    return [
      for (final id in ref.read(sidebarWorkspacesProvider).visibleTabIds)
        ?byId[id],
    ];
  }

  /// The ring shows only for keyboard focus (UI §3).
  bool get _showFocus =>
      widget.focusNode.hasFocus &&
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  /// UI §3.6 list keys. ↑/↓/Home/End move the selection itself (the
  /// terminal on the right follows; the workspace does not take the focus
  /// while the list has it) rather than a separate roving highlight;
  /// Enter/Space/Esc hand the keyboard back to the terminal; Shift+F10 and
  /// the Menu key open the selected row's menu.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final state = ref.read(terminalTabsProvider);
    final workspaces = ref.read(sidebarWorkspacesProvider.notifier);
    final menu =
        key == LogicalKeyboardKey.contextMenu ||
        (key == LogicalKeyboardKey.f10 &&
            HardwareKeyboard.instance.isShiftPressed);
    if (menu) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      final id = state.selectedId;
      if (id == null) return KeyEventResult.ignored;
      _openMenu(id);
      return KeyEventResult.handled;
    }
    // Plain keys only: chords (Ctrl+Tab, ⌘1…) belong to the window.
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    switch (key) {
      case LogicalKeyboardKey.arrowDown:
        workspaces.step(1);
      case LogicalKeyboardKey.arrowUp:
        workspaces.step(-1);
      case LogicalKeyboardKey.home:
        workspaces.selectVisible(1);
      case LogicalKeyboardKey.end:
        workspaces.selectVisible(_visibleTabs().length);
      case LogicalKeyboardKey.enter ||
          LogicalKeyboardKey.numpadEnter ||
          LogicalKeyboardKey.space:
        final id = state.selectedId;
        if (id == null) return KeyEventResult.ignored;
        widget.onSelected(id); // selects + focuses the terminal
      case LogicalKeyboardKey.escape:
        widget.onEscape();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// The list builds only the rows on screen: an off-screen row is
  /// scrolled in first, then its menu opens.
  void _openMenu(int id) {
    _reveal(id);
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted) _rows[id]?.currentState?.openMenu();
      })
      ..ensureVisualUpdate();
  }

  /// Scrolls the row of [id] fully into view (rows are a fixed height, so
  /// this works for rows the list has not built). The lazy list only
  /// estimates its extent until it builds the rows near the end, so a
  /// jump the estimate cut short is finished on the next frames.
  void _reveal(int id, {int retries = 2}) {
    final controller = widget.scrollController;
    if (!mounted || !controller.hasClients) return;
    final tabs = _visibleTabs();
    final index = tabs.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final row = SessionTabRow.heightFor(MediaQuery.textScalerOf(context));
    final top = ShellxSizes.listTop + index * (row + ShellxSizes.rowGap);
    final bottom = top + row;
    final position = controller.position;
    final viewport = position.viewportDimension;
    double? target;
    if (top - ShellxSizes.listTop < position.pixels) {
      target = top - ShellxSizes.listTop;
    } else if (bottom + ShellxSizes.listBottom > position.pixels + viewport) {
      target = bottom + ShellxSizes.listBottom - viewport;
    }
    if (target == null) return;
    controller.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
    if (target > position.maxScrollExtent && retries > 0) {
      WidgetsBinding.instance
        ..addPostFrameCallback((_) => _reveal(id, retries: retries - 1))
        ..ensureVisualUpdate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(terminalTabsProvider);
    ref.watch(sidebarWorkspacesProvider);
    final rows = _visibleTabs();
    // Keyboard or ⌘1…⌘9 moved the selection: keep its row on screen.
    ref.listen(terminalTabsProvider.select((s) => s.selectedId), (_, id) {
      if (id == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(id));
    });
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

    final ids = {for (final tab in rows) tab.id};
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
                // An empty list is no tab stop (UI §3.6).
                canRequestFocus: rows.isNotEmpty,
                skipTraversal: rows.isEmpty,
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
                    itemCount: rows.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: ShellxSizes.rowGap),
                    itemBuilder: (context, i) {
                      final tab = rows[i];
                      final selected = tab.id == state.selectedId;
                      return KeyedSubtree(
                        key: ValueKey('tab.${tab.id}'),
                        child: SessionTabRow(
                          key: _rows.putIfAbsent(tab.id, GlobalKey.new),
                          tab: tab,
                          selected: selected,
                          focused: selected && _showFocus,
                          position: i + 1,
                          count: rows.length,
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

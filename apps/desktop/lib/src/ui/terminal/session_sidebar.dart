import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/desktop_services.dart';
import '../../terminal/local_sessions_provider.dart';
import '../../terminal/sidebar_workspaces.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import 'inline_name_field.dart';
import 'session_tab_row.dart';
import 'shellx_menu.dart';
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

  /// The name field the list's keyboard opened (F2, the menu from
  /// Shift+F10): when it closes the keyboard comes back to the list;
  /// otherwise (a double-click, ⌘⇧N) to the terminal (UI-A2 §4).
  RenameTarget? _renameFromList;

  static const _newWorkspace = '\u0000new';

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

  /// What the list shows, top to bottom: the visible rows (C5) and, until
  /// the workspace headers arrive (Task 9), the name field of a workspace
  /// being renamed (⌘⇧N, "Move to workspace… → New workspace") where its
  /// header goes.
  List<_Item> _items() {
    final s = ref.read(sidebarWorkspacesProvider);
    final byId = {for (final t in ref.read(terminalTabsProvider).tabs) t.id: t};
    final items = <_Item>[];
    for (final w in s.workspaces) {
      if (s.showHeaders && s.renaming == RenameWorkspace(w.id)) {
        items.add(_WorkspaceNameItem(w));
      }
      if (s.showHeaders && w.collapsed) continue;
      final ids = s.tabsOf(w.id);
      for (final (i, id) in ids.indexed) {
        final tab = byId[id];
        if (tab != null) {
          items.add(_RowItem(tab, w, i + 1, ids.length));
        }
      }
    }
    return items;
  }

  /// UI-A2 §1.3 header height, which the workspace name field stands in
  /// for.
  static double _workspaceItemHeight(TextScaler scaler) => max(
    ShellxSizes.workspaceHeader,
    scaler.scale(ShellxSizes.workspaceHeaderText) + 12,
  );

  double _itemHeight(_Item item, TextScaler scaler) => switch (item) {
    _RowItem(:final tab) => SessionTabRow.heightFor(
      scaler,
      context: tab.hasContext,
    ),
    _WorkspaceNameItem() => _workspaceItemHeight(scaler),
  };

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
    // Keys typed into a name field inside the list are the field's
    // (arrows, Home/End, Space, Enter).
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
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
    final keyboard = HardwareKeyboard.instance;
    // UI-A2 §8: ⌥↑/⌥↓ (Alt+↑/↓) move the selected tab one place.
    if (keyboard.isAltPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isShiftPressed &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      final id = state.selectedId;
      if (id == null) return KeyEventResult.ignored;
      if (key == LogicalKeyboardKey.arrowUp) {
        workspaces.moveUp(id);
      } else {
        workspaces.moveDown(id);
      }
      _announceMove(id);
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(id));
      return KeyEventResult.handled;
    }
    // Plain keys only: chords (Ctrl+Tab, ⌘1…) belong to the window.
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
      case LogicalKeyboardKey.f2:
        if (event is KeyRepeatEvent) return KeyEventResult.handled;
        final id = state.selectedId;
        // A selected tab hidden in a collapsed workspace has no row.
        if (id == null || !_visibleTabs().any((t) => t.id == id)) {
          return KeyEventResult.ignored;
        }
        _startTabRename(id, fromList: true);
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

  /// Scrolls the row of [id] fully into view (row heights are known up
  /// front, so this works for rows the list has not built). The lazy list only
  /// estimates its extent until it builds the rows near the end, so a
  /// jump the estimate cut short is finished on the next frames.
  void _reveal(int id, {int retries = 2}) {
    final controller = widget.scrollController;
    if (!mounted || !controller.hasClients) return;
    final scaler = MediaQuery.textScalerOf(context);
    final items = _items();
    final index = items.indexWhere((i) => i is _RowItem && i.tab.id == id);
    if (index < 0) return;
    // UI-A2 §1.3: rows differ in height, so the offset is their sum.
    var top = ShellxSizes.listTop;
    for (var i = 0; i < index; i++) {
      top += _itemHeight(items[i], scaler) + ShellxSizes.rowGap;
    }
    final bottom = top + _itemHeight(items[index], scaler);
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

  // ---- rename (UI-A2 §4) ------------------------------------------------

  void _startTabRename(int id, {required bool fromList}) {
    final target = RenameTab(id);
    _renameFromList = fromList ? target : null;
    ref.read(sidebarWorkspacesProvider.notifier).startRename(target);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(id));
  }

  void _commitTabName(int id, String text) {
    ref.read(terminalTabsProvider.notifier).rename(id, text);
    _endRename();
  }

  void _commitWorkspaceName(String id, String text) {
    ref.read(sidebarWorkspacesProvider.notifier).rename(id, text);
    _endRename();
  }

  /// Closes the name field and hands the keyboard back: to the list when
  /// the list opened it, else to the terminal. A field that closed because
  /// the focus went somewhere on purpose (another click, ⌘T, ⌘1, a
  /// dialog) leaves the focus there.
  void _endRename() {
    final workspaces = ref.read(sidebarWorkspacesProvider.notifier);
    final fromList =
        _renameFromList != null &&
        ref.read(sidebarWorkspacesProvider).renaming == _renameFromList;
    _renameFromList = null;
    workspaces.endRename();
    final list = widget.focusNode;
    final primary = FocusManager.instance.primaryFocus;
    final ours =
        primary == null ||
        primary == list ||
        list.ancestors.contains(primary) ||
        list.descendants.contains(primary);
    if (!ours) return;
    if (fromList && _visibleTabs().isNotEmpty) {
      list.requestFocus();
    } else {
      widget.onEscape(); // the terminal
    }
  }

  // ---- ports, moves, menus (UI-A2 §2.4, §5, §8) -------------------------

  Future<void> _openPort(int port) async {
    try {
      await ref.read(desktopServicesProvider).urlOpener.openLocalPort(port);
    } catch (_) {
      if (mounted) {
        ref
            .read(terminalTabsProvider.notifier)
            .showNotice(const PortOpenFailedNotice());
      }
    }
  }

  /// "claude, tab 2 of 3 in Backend": where the tab is after a move.
  String? _whereIs(int id) {
    final l10n = AppLocalizations.of(context);
    final s = ref.read(sidebarWorkspacesProvider);
    final ws = s.workspaceOf(id);
    if (ws == null) return null;
    final list = s.tabsOf(ws);
    final index = list.indexOf(id) + 1;
    return s.showHeaders
        ? l10n.sidebarPositionInWorkspace(
            index,
            list.length,
            ref.read(sidebarWorkspacesProvider.notifier).displayName(ws),
          )
        : l10n.sidebarPosition(index, list.length);
  }

  /// After a keyboard or menu move: say where the tab is now (UI-A2 §8).
  void _announceMove(int id) {
    final tab = ref
        .read(terminalTabsProvider)
        .tabs
        .where((t) => t.id == id)
        .firstOrNull;
    final where = _whereIs(id);
    if (tab == null || where == null) return;
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        '${tab.label}, $where',
        Directionality.of(context),
      ),
    );
  }

  void _moveUp(int id) {
    ref.read(sidebarWorkspacesProvider.notifier).moveUp(id);
    _announceMove(id);
  }

  void _moveDown(int id) {
    ref.read(sidebarWorkspacesProvider.notifier).moveDown(id);
    _announceMove(id);
  }

  /// UI-A2 §5.1.
  Future<void> _rowMenu(TerminalTab tab, Offset at) async {
    final l10n = AppLocalizations.of(context);
    // Shift+F10 / the Menu key: the list has the keyboard (UI-A2 §4).
    final fromList = widget.focusNode.hasFocus;
    final workspaces = ref.read(sidebarWorkspacesProvider.notifier);
    // The five smallest (UI-A2 §5.1).
    final ports = tab.exited
        ? const <int>[]
        : ([...tab.ports]..sort()).take(5).toList();
    final choice = await showShellxMenu<Object>(
      context: context,
      at: at,
      entries: [
        ShellxMenuEntry(
          key: const Key('menu.renameTab'),
          value: _RowAction.rename,
          label: l10n.tabRename,
          shortcut: renameShortcutLabel(),
        ),
        if (tab.customTitle != null)
          ShellxMenuEntry(
            key: const Key('menu.automaticName'),
            value: _RowAction.automaticName,
            label: l10n.tabUseAutomaticName,
          ),
        ShellxMenuEntry(
          key: const Key('menu.moveTo'),
          value: _RowAction.moveTo,
          label: l10n.tabMoveTo,
          dividerBefore: true,
        ),
        ShellxMenuEntry(
          key: const Key('menu.moveUp'),
          value: _RowAction.moveUp,
          label: l10n.tabMoveUp,
          shortcut: moveUpShortcutLabel(),
          enabled: workspaces.canMoveUp(tab.id),
        ),
        ShellxMenuEntry(
          key: const Key('menu.moveDown'),
          value: _RowAction.moveDown,
          label: l10n.tabMoveDown,
          shortcut: moveDownShortcutLabel(),
          enabled: workspaces.canMoveDown(tab.id),
        ),
        for (final (i, port) in ports.indexed)
          ShellxMenuEntry(
            key: Key('menu.port.$port'),
            value: port,
            label: l10n.tabOpenPort(port),
            dividerBefore: i == 0,
          ),
        ShellxMenuEntry(
          key: const Key('menu.closeTab'),
          value: _RowAction.close,
          label: l10n.terminalCloseTab,
          shortcut: closeTabShortcutLabel(),
          dividerBefore: true,
        ),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case _RowAction.rename:
        _startTabRename(tab.id, fromList: fromList);
      case _RowAction.automaticName:
        ref.read(terminalTabsProvider.notifier).rename(tab.id, null);
      case _RowAction.moveTo:
        await _moveToMenu(tab, at, fromList: fromList);
      case _RowAction.moveUp:
        _moveUp(tab.id);
      case _RowAction.moveDown:
        _moveDown(tab.id);
      case _RowAction.close:
        widget.onClose(tab);
      case final int port:
        await _openPort(port);
    }
  }

  /// UI-A2 §5.3: every other workspace in sidebar order, then "New
  /// workspace" (moves the tab there and opens its name field).
  Future<void> _moveToMenu(
    TerminalTab tab,
    Offset at, {
    required bool fromList,
  }) async {
    final l10n = AppLocalizations.of(context);
    final s = ref.read(sidebarWorkspacesProvider);
    final from = s.workspaceOf(tab.id);
    final others = [
      for (final w in s.workspaces)
        if (w.id != from) w,
    ];
    final choice = await showShellxMenu<String>(
      context: context,
      at: at,
      entries: [
        for (final w in others)
          ShellxMenuEntry(
            key: Key('menu.moveTo.${w.id}'),
            value: w.id,
            label: w.displayName(l10n),
          ),
        ShellxMenuEntry(
          key: const Key('menu.moveTo.new'),
          value: _newWorkspace,
          label: l10n.workspaceNew,
          shortcut: newWorkspaceShortcutLabel(),
          dividerBefore: others.isNotEmpty,
        ),
      ],
    );
    if (choice == null || !mounted) return;
    final workspaces = ref.read(sidebarWorkspacesProvider.notifier);
    if (choice == _newWorkspace) {
      await workspaces.create(moveTab: tab.id);
      if (!mounted) return;
      _renameFromList = fromList
          ? ref.read(sidebarWorkspacesProvider).renaming
          : null;
    } else {
      workspaces.moveTab(tab.id, choice);
      _announceMove(tab.id);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(tab.id));
  }

  /// Below the row's left edge (where Shift+F10 opens menus).
  Offset _rowAnchor(int id) {
    final box = _rows[id]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Offset.zero;
    return box.localToGlobal(Offset(ShellxSpace.s8, box.size.height));
  }

  /// UI-A2 §8: rename, move (only what can be done), one per port.
  Map<CustomSemanticsAction, VoidCallback> _rowActions(
    AppLocalizations l10n,
    TerminalTab tab,
  ) {
    final workspaces = ref.read(sidebarWorkspacesProvider.notifier);
    return {
      CustomSemanticsAction(label: l10n.tabRename): () =>
          _startTabRename(tab.id, fromList: widget.focusNode.hasFocus),
      CustomSemanticsAction(label: l10n.tabMoveTo): () => unawaited(
        _moveToMenu(
          tab,
          _rowAnchor(tab.id),
          fromList: widget.focusNode.hasFocus,
        ),
      ),
      if (workspaces.canMoveUp(tab.id))
        CustomSemanticsAction(label: l10n.tabMoveUp): () => _moveUp(tab.id),
      if (workspaces.canMoveDown(tab.id))
        CustomSemanticsAction(label: l10n.tabMoveDown): () => _moveDown(tab.id),
      for (final port in tab.exited ? const <int>[] : tab.ports)
        CustomSemanticsAction(label: l10n.tabOpenPort(port)): () =>
            unawaited(_openPort(port)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(terminalTabsProvider);
    final sidebar = ref.watch(sidebarWorkspacesProvider);
    final home = ref.watch(homeDirectoryProvider);
    final items = _items();
    final rows = [
      for (final item in items)
        if (item is _RowItem) item,
    ];
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

    final positions = {for (final (i, row) in rows.indexed) row.tab.id: i + 1};
    final ids = positions.keys.toSet();
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
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: ShellxSizes.rowGap),
                    itemBuilder: (context, i) => switch (items[i]) {
                      _RowItem(
                        :final tab,
                        :final workspace,
                        :final index,
                        :final of,
                      ) =>
                        KeyedSubtree(
                          key: ValueKey('tab.${tab.id}'),
                          child: SessionTabRow(
                            key: _rows.putIfAbsent(tab.id, GlobalKey.new),
                            tab: tab,
                            selected: tab.id == state.selectedId,
                            focused: tab.id == state.selectedId && _showFocus,
                            position: positions[tab.id]!,
                            count: rows.length,
                            positionLabel: sidebar.showHeaders
                                ? l10n.sidebarPositionInWorkspace(
                                    index,
                                    of,
                                    workspace.displayName(l10n),
                                  )
                                : null,
                            home: home,
                            renaming: sidebar.renaming == RenameTab(tab.id),
                            onSelect: () => widget.onSelected(tab.id),
                            onClose: () => widget.onClose(tab),
                            onStartRename: () =>
                                _startTabRename(tab.id, fromList: false),
                            onRename: (text) => _commitTabName(tab.id, text),
                            onCancelRename: _endRename,
                            onOpenPort: (port) => unawaited(_openPort(port)),
                            onMenu: (at) => unawaited(_rowMenu(tab, at)),
                            extraActions: _rowActions(l10n, tab),
                          ),
                        ),
                      _WorkspaceNameItem(:final workspace) => KeyedSubtree(
                        key: ValueKey('ws.${workspace.id}'),
                        child: _WorkspaceNameField(
                          height: _workspaceItemHeight(
                            MediaQuery.textScalerOf(context),
                          ),
                          initial: workspace.displayName(l10n),
                          label: l10n.workspaceNameField,
                          onCommit: (text) =>
                              _commitWorkspaceName(workspace.id, text),
                          onCancel: _endRename,
                        ),
                      ),
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

enum _RowAction { rename, automaticName, moveTo, moveUp, moveDown, close }

sealed class _Item {
  const _Item();
}

/// A tab's row; [index] of [of] is its place in [workspace].
final class _RowItem extends _Item {
  const _RowItem(this.tab, this.workspace, this.index, this.of);
  final TerminalTab tab;
  final Workspace workspace;
  final int index;
  final int of;
}

/// A workspace's open name field.
final class _WorkspaceNameItem extends _Item {
  const _WorkspaceNameItem(this.workspace);
  final Workspace workspace;
}

/// The name field of a workspace header being renamed (UI-A2 §3.2, §4):
/// `small` w600 `textTitle`, between the chevron's and the count's slots.
/// The workspace header itself (Task 9) takes it over.
class _WorkspaceNameField extends StatelessWidget {
  const _WorkspaceNameField({
    required this.height,
    required this.initial,
    required this.label,
    required this.onCommit,
    required this.onCancel,
  });

  final double height;
  final String initial;
  final String label;
  final void Function(String text) onCommit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Padding(
      // |4| chevron 20 |4| name |4| count ≥ 16 |2| + 24 |4| (UI-A2 §3.1).
      padding: const EdgeInsets.only(
        left: ShellxSpace.s4 + ShellxSizes.chevronHit + ShellxSpace.s4,
        right:
            ShellxSpace.s4 +
            ShellxSizes.headerCountMin +
            ShellxSpace.s2 +
            ShellxSizes.headerAddHit +
            ShellxSpace.s4,
      ),
      child: Center(
        child: InlineNameField(
          initial: initial,
          style: ShellxText.small.copyWith(fontWeight: FontWeight.w600),
          label: label,
          onCommit: onCommit,
          onCancel: onCancel,
        ),
      ),
    ),
  );
}

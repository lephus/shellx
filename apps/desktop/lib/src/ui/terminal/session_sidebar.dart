import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
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
import 'session_tab_row.dart';
import 'shellx_menu.dart';
import 'shortcut_labels.dart';
import 'terminal_overlays.dart';
import 'workspace_header.dart';

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

  /// D14: the list's keyboard cursor is on this workspace header (null:
  /// on the selected row, as in A1). See [_cursorHeader].
  String? _headerCursor;

  /// Headers by workspace id, so Shift+F10 can open a header's menu.
  final _headerKeys = <String, GlobalKey<WorkspaceHeaderState>>{};

  // UI-A2 §6 drag state.

  /// The slot (workspace, index) a drop on a row goes to.
  (String, int)? _drop;

  /// A header (workspace id) or an empty hint (`empty.<id>`) under the
  /// dragged tab.
  String? _dropTarget;
  bool _dragging = false;

  /// Where the pointer holds the dragged row (the feedback keeps it
  /// there; drop details report the feedback's corner).
  Offset _grab = Offset.zero;
  Timer? _scrollTimer;
  Timer? _expandTimer;
  double _scrollVelocity = 0;
  final _listKey = GlobalKey();

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
    _scrollTimer?.cancel();
    _expandTimer?.cancel();
    widget.focusNode.removeListener(_refresh);
    FocusManager.instance.removeHighlightModeListener(_onHighlightMode);
    super.dispose();
  }

  void _refresh() {
    // The cursor is the list's: it goes back to the selected row once the
    // list loses the keyboard.
    if (!widget.focusNode.hasFocus) _headerCursor = null;
    if (mounted) setState(() {});
  }

  void _onHighlightMode(FocusHighlightMode _) => _refresh();

  /// What the list shows, top to bottom (C5; UI-A2 §3, §3.4): with two
  /// workspaces or more, each one's header, then its rows, or its empty
  /// hint, unless it is collapsed; with one, the A1 rows alone (D10).
  List<_Item> _items() {
    final s = ref.read(sidebarWorkspacesProvider);
    final tabsState = ref.read(terminalTabsProvider);
    final byId = {for (final t in tabsState.tabs) t.id: t};
    final items = <_Item>[];
    for (final w in s.workspaces) {
      final tabs = [for (final id in s.tabsOf(w.id)) ?byId[id]];
      if (s.showHeaders) {
        items.add(
          _HeaderItem(
            w,
            tabs.length,
            w.collapsed && tabs.any((t) => t.id == tabsState.selectedId),
          ),
        );
        if (w.collapsed) continue;
        if (tabs.isEmpty) {
          items.add(_EmptyItem(w.id));
          continue;
        }
      }
      for (final (i, tab) in tabs.indexed) {
        items.add(_RowItem(tab, w, i, tabs.length));
      }
    }
    return items;
  }

  /// Space above item [i]: 8 above a header (the first item has the
  /// list's top padding only), else the A1 row gap (UI-A2 §3.1).
  static double _gapBefore(List<_Item> items, int i) => i == 0
      ? 0
      : items[i] is _HeaderItem
      ? ShellxSizes.workspaceHeaderTop
      : ShellxSizes.rowGap;

  /// UI-A2 §1.3 heights.
  static double _extent(_Item item, TextScaler scaler) => switch (item) {
    _HeaderItem() => WorkspaceHeader.heightFor(scaler),
    _RowItem(:final tab) => SessionTabRow.heightFor(
      scaler,
      context: tab.hasContext,
    ),
    _EmptyItem() => max(
      ShellxSizes.emptyWorkspaceRow,
      scaler.scale(ShellxSizes.contextLine) + 16,
    ),
  };

  /// What the keyboard walks (D14): headers (workspace ids) and visible
  /// rows (tab ids); the empty hints are no stops (UI-A2 §3.4).
  List<Object> _navigation() => [
    for (final item in _items())
      switch (item) {
        _HeaderItem(:final workspace) => workspace.id,
        _RowItem(:final tab) => tab.id,
        _EmptyItem() => null,
      },
  ].nonNulls.toList();

  /// The header the list's keyboard cursor is on (D14), or null for the
  /// selected row. A selected tab hidden in a collapsed workspace has no
  /// row: its header stands in for it, so the ring never disappears.
  String? _cursorHeader() {
    final s = ref.read(sidebarWorkspacesProvider);
    if (!s.showHeaders) return null;
    final explicit = _headerCursor;
    if (explicit != null && s.workspace(explicit) != null) return explicit;
    final id = ref.read(terminalTabsProvider).selectedId;
    if (id == null || s.visibleTabIds.contains(id)) return null;
    return s.workspaceOf(id);
  }

  /// The rows on screen, in the sidebar's visible order (C5).
  List<TerminalTab> _visibleTabs() {
    final byId = {for (final t in ref.read(terminalTabsProvider).tabs) t.id: t};
    return [
      for (final id in ref.read(sidebarWorkspacesProvider).visibleTabIds)
        ?byId[id],
    ];
  }

  /// The ring shows only for keyboard focus (UI §3).
  /// Not while a name field inside the list has the keyboard: the field's
  /// own border shows where typing goes.
  bool get _showFocus =>
      widget.focusNode.hasPrimaryFocus &&
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  /// UI §3.6 list keys. ↑/↓/Home/End move the selection itself (the
  /// terminal on the right follows; the workspace does not take the focus
  /// while the list has it) rather than a separate roving highlight;
  /// Enter/Space/Esc hand the keyboard back to the terminal; Shift+F10 and
  /// the Menu key open the selected row's menu. With workspace headers the
  /// list is a tree (D14, UI-A2 §8): the cursor also stops on headers
  /// (without changing the tab), ←/→ collapse, expand and move between a
  /// header and its rows, Enter/Space on a header toggles it.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Keys typed into a name field inside the list are the field's
    // (arrows, Home/End, Space, Enter).
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final state = ref.read(terminalTabsProvider);
    final s = ref.read(sidebarWorkspacesProvider);
    final workspaces = ref.read(sidebarWorkspacesProvider.notifier);
    final keyboard = HardwareKeyboard.instance;
    final cursor = _cursorHeader();
    final header = cursor == null ? null : s.workspace(cursor);
    final menu =
        key == LogicalKeyboardKey.contextMenu ||
        (key == LogicalKeyboardKey.f10 && keyboard.isShiftPressed);
    if (menu) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      if (header != null) {
        _openHeaderMenu(header.id);
        return KeyEventResult.handled;
      }
      final id = state.selectedId;
      if (id == null) return KeyEventResult.ignored;
      _openMenu(id);
      return KeyEventResult.handled;
    }
    // UI-A2 §8: ⌥↑/⌥↓ (Alt+↑/↓) move the selected tab one place.
    if (keyboard.isAltPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isShiftPressed &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      // Headers do not move (UI-A2 §6: workspaces keep creation order).
      if (header != null) return KeyEventResult.handled;
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
    if (key == LogicalKeyboardKey.escape) {
      setState(() => _headerCursor = null);
      widget.onEscape();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f2) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      if (header != null) {
        _startWorkspaceRename(header.id, fromList: true);
        return KeyEventResult.handled;
      }
      final id = state.selectedId;
      // A selected tab hidden in a collapsed workspace has no row.
      if (id == null || !_visibleTabs().any((t) => t.id == id)) {
        return KeyEventResult.ignored;
      }
      _startTabRename(id, fromList: true);
      return KeyEventResult.handled;
    }
    if (!s.showHeaders) {
      // One workspace: the A1 list (D10).
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
        default:
          return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }

    final nav = _navigation();
    final at = header != null
        ? nav.indexOf(header.id)
        : nav.indexOf(state.selectedId ?? -1);
    void go(int i) {
      if (nav.isEmpty) return;
      final target = nav[i.clamp(0, nav.length - 1)];
      if (target is String) {
        setState(() => _headerCursor = target);
      } else {
        setState(() => _headerCursor = null);
        ref.read(terminalTabsProvider.notifier).select(target as int);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(target));
    }

    switch (key) {
      case LogicalKeyboardKey.arrowDown:
        go(at < 0 ? 0 : at + 1);
      case LogicalKeyboardKey.arrowUp:
        go(at < 0 ? 0 : at - 1);
      case LogicalKeyboardKey.home:
        go(0);
      case LogicalKeyboardKey.end:
        go(nav.length - 1);
      case LogicalKeyboardKey.arrowLeft:
        if (header == null) {
          // A row: up to its workspace's header.
          final ws = s.workspaceOf(state.selectedId ?? -1);
          if (ws == null) return KeyEventResult.ignored;
          setState(() => _headerCursor = ws);
          WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(ws));
        } else {
          setState(() => _headerCursor = header.id);
          workspaces.setCollapsed(header.id, true);
        }
      case LogicalKeyboardKey.arrowRight:
        if (header == null) return KeyEventResult.ignored;
        setState(() => _headerCursor = header.id);
        if (header.collapsed) {
          workspaces.setCollapsed(header.id, false);
        } else {
          final first = s.tabsOf(header.id).firstOrNull;
          if (first != null) go(nav.indexOf(first));
        }
      case LogicalKeyboardKey.enter ||
          LogicalKeyboardKey.numpadEnter ||
          LogicalKeyboardKey.space:
        if (header != null) {
          setState(() => _headerCursor = header.id);
          workspaces.toggleCollapsed(header.id);
        } else {
          final id = state.selectedId;
          if (id == null) return KeyEventResult.ignored;
          widget.onSelected(id); // selects + focuses the terminal
        }
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

  /// Shift+F10 / Menu key on a header (UI-A2 §5.2), scrolled in first.
  void _openHeaderMenu(String id) {
    _reveal(id);
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted) _headerKeys[id]?.currentState?.openMenu();
      })
      ..ensureVisualUpdate();
  }

  /// Scrolls the item of [target] (a tab id, or a workspace id for its
  /// header) fully into view. Heights are known up front (UI-A2 §1.3), so
  /// this works for items the list has not built: the offset is the sum
  /// of the items and gaps above. The lazy list only estimates its extent
  /// until it builds the items near the end, so a jump the estimate cut
  /// short is finished on the next frames.
  void _reveal(Object target, {int retries = 2}) {
    final controller = widget.scrollController;
    if (!mounted || !controller.hasClients) return;
    final scaler = MediaQuery.textScalerOf(context);
    final items = _items();
    var top = ShellxSizes.listTop;
    double? found;
    var extent = 0.0;
    for (final (i, item) in items.indexed) {
      top += _gapBefore(items, i);
      extent = _extent(item, scaler);
      final matches = switch (item) {
        _HeaderItem(:final workspace) => workspace.id == target,
        _RowItem(:final tab) => tab.id == target,
        _EmptyItem() => false,
      };
      if (matches) {
        found = top;
        break;
      }
      top += extent;
    }
    if (found == null) return;
    final bottom = found + extent;
    final position = controller.position;
    final viewport = position.viewportDimension;
    double? jump;
    if (found - ShellxSizes.listTop < position.pixels) {
      jump = found - ShellxSizes.listTop;
    } else if (bottom + ShellxSizes.listBottom > position.pixels + viewport) {
      jump = bottom + ShellxSizes.listBottom - viewport;
    }
    if (jump == null) return;
    controller.jumpTo(
      jump.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
    if (jump > position.maxScrollExtent && retries > 0) {
      WidgetsBinding.instance
        ..addPostFrameCallback((_) => _reveal(target, retries: retries - 1))
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

  void _startWorkspaceRename(String id, {required bool fromList}) {
    final target = RenameWorkspace(id);
    _renameFromList = fromList ? target : null;
    ref.read(sidebarWorkspacesProvider.notifier).startRename(target);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(id));
  }

  /// Enter on the automatic name as it opened changes nothing: storing it
  /// would freeze the OSC title and offer "Use automatic name" for a name
  /// the user never chose.
  void _commitTabName(int id, String text) {
    if (!mounted) return;
    final tab = ref
        .read(terminalTabsProvider)
        .tabs
        .where((t) => t.id == id)
        .firstOrNull;
    final untouched =
        tab != null && tab.customTitle == null && text.trim() == tab.label;
    if (tab != null && !untouched) {
      ref.read(terminalTabsProvider.notifier).rename(id, text);
    }
    _endRename(RenameTab(id));
  }

  void _commitWorkspaceName(String id, String text) {
    if (!mounted) return;
    ref.read(sidebarWorkspacesProvider.notifier).rename(id, text);
    _endRename(RenameWorkspace(id));
  }

  /// Closes the name field and hands the keyboard back: to the list when
  /// the list opened it, else to the terminal. A field that closed because
  /// the focus went somewhere on purpose (another click, ⌘T, ⌘1, a
  /// dialog) leaves the focus there.
  ///
  /// A field that went away while another rename took over (⌘⇧N opened
  /// a workspace's field) only saves its text: [target] is no longer the
  /// open one, so neither the rename nor the focus is touched.
  void _endRename(RenameTarget target) {
    if (!mounted) return;
    if (ref.read(sidebarWorkspacesProvider).renaming != target) return;
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
    // With headers the list is a tab stop even without a visible row.
    if (fromList && _items().isNotEmpty) {
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

  /// UI-A2 §5.2.
  Future<void> _headerMenu(Workspace w, Offset at) async {
    final l10n = AppLocalizations.of(context);
    // Shift+F10 / the Menu key: the list has the keyboard (UI-A2 §4).
    final fromList = widget.focusNode.hasFocus;
    final choice = await showShellxMenu<_HeaderAction>(
      context: context,
      at: at,
      entries: [
        ShellxMenuEntry(
          key: const Key('menu.ws.newTab'),
          value: _HeaderAction.newTab,
          label: l10n.workspaceNewTab,
        ),
        ShellxMenuEntry(
          key: const Key('menu.ws.rename'),
          value: _HeaderAction.rename,
          label: l10n.workspaceRename,
          shortcut: renameShortcutLabel(),
        ),
        ShellxMenuEntry(
          key: const Key('menu.ws.toggle'),
          value: _HeaderAction.toggle,
          label: w.collapsed ? l10n.workspaceExpand : l10n.workspaceCollapse,
          shortcut: w.collapsed ? '→' : '←',
        ),
        ShellxMenuEntry(
          key: const Key('menu.ws.delete'),
          value: _HeaderAction.delete,
          label: l10n.workspaceDelete,
          enabled: !w.isDefault,
          dividerBefore: true,
        ),
      ],
    );
    if (!mounted || choice == null) return;
    final workspaces = ref.read(sidebarWorkspacesProvider.notifier);
    switch (choice) {
      case _HeaderAction.newTab:
        await workspaces.openTabIn(w.id);
      case _HeaderAction.rename:
        _startWorkspaceRename(w.id, fromList: fromList);
      case _HeaderAction.toggle:
        workspaces.toggleCollapsed(w.id);
      case _HeaderAction.delete:
        workspaces.delete(w.id);
    }
  }

  // ---- drag and drop (UI-A2 §6) -----------------------------------------

  /// The feedback keeps the row where the pointer grabbed it.
  Offset _anchor(Draggable<Object> d, BuildContext context, Offset position) =>
      _grab = childDragAnchorStrategy(d, context, position);

  void _stopDrag() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
    _expandTimer?.cancel();
    _expandTimer = null;
    if (!mounted) return;
    setState(() {
      _dragging = false;
      _drop = null;
      _dropTarget = null;
    });
  }

  /// UI-A2 §6: in the list's top or bottom 32 px, scroll 240 px/s that
  /// way (above or below the list counts too, as long as the pointer is
  /// over the sidebar's width).
  void _autoScroll(Offset global) {
    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(global);
    const zone = ShellxSizes.dragAutoScrollZone;
    final inside = local.dx >= 0 && local.dx < box.size.width;
    _scrollVelocity = !inside
        ? 0
        : local.dy < zone
        ? -ShellxSizes.dragAutoScrollSpeed
        : local.dy > box.size.height - zone
        ? ShellxSizes.dragAutoScrollSpeed
        : 0;
    if (_scrollVelocity == 0) {
      _scrollTimer?.cancel();
      _scrollTimer = null;
      return;
    }
    const tick = Duration(milliseconds: 16);
    _scrollTimer ??= Timer.periodic(tick, (_) {
      final controller = widget.scrollController;
      if (!controller.hasClients) return;
      final p = controller.position;
      final next =
          (p.pixels +
                  _scrollVelocity *
                      tick.inMicroseconds /
                      Duration.microsecondsPerSecond)
              .clamp(p.minScrollExtent, p.maxScrollExtent);
      if (next != p.pixels) controller.jumpTo(next);
    });
  }

  /// Upper half of a row: drop before it; lower half: after it. [pointer]
  /// is global.
  void _hoverRow(_RowItem item, Offset pointer) {
    final box =
        _rows[item.tab.id]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final before = box.globalToLocal(pointer).dy < box.size.height / 2;
    final slot = (item.workspace.id, item.index + (before ? 0 : 1));
    if (slot == _drop && _dropTarget == null) return;
    setState(() {
      _drop = slot;
      _dropTarget = null;
    });
  }

  void _leaveRow() {
    if (_drop != null) setState(() => _drop = null);
  }

  /// A header (workspace id) or an empty hint (`empty.<id>`); over a
  /// collapsed header for 600 ms, the workspace expands (UI-A2 §6).
  void _hoverTarget(String target, {String? header}) {
    if (_dropTarget == target) return;
    _expandTimer?.cancel();
    _expandTimer = null;
    final s = ref.read(sidebarWorkspacesProvider);
    if (header != null && (s.workspace(header)?.collapsed ?? false)) {
      _expandTimer = Timer(ShellxMotion.dragExpandDelay, () {
        _expandTimer = null;
        if (mounted) {
          ref
              .read(sidebarWorkspacesProvider.notifier)
              .setCollapsed(header, false);
        }
      });
    }
    setState(() {
      _dropTarget = target;
      _drop = null;
    });
  }

  void _leaveTarget(String target) {
    if (_dropTarget != target) return;
    _expandTimer?.cancel();
    _expandTimer = null;
    setState(() => _dropTarget = null);
  }

  /// A tab closed mid-drag is simply not moved (moveTab ignores it).
  void _dropAt(int tabId, String workspaceId, [int? index]) {
    ref
        .read(sidebarWorkspacesProvider.notifier)
        .moveTab(tabId, workspaceId, index);
    _stopDrag();
  }

  Widget _draggable(
    TerminalTab tab,
    String home,
    Widget row, {
    required bool enabled,
  }) => _RowDraggable(
    data: tab.id,
    maxSimultaneousDrags: enabled ? null : 0,
    dragAnchorStrategy: _anchor,
    feedback: _DragFeedback(tab: tab, home: home),
    childWhenDragging: Opacity(
      opacity: ShellxDesktopColors.disabledOpacity,
      child: row,
    ),
    onDragStarted: () => setState(() => _dragging = true),
    onDragEnd: (_) => _stopDrag(),
    onDraggableCanceled: (_, _) => _stopDrag(),
    child: row,
  );

  /// The row and the gap above it: the gap belongs to "before this row",
  /// where its drop line shows.
  Widget _rowTarget(_RowItem item, double gap, Widget row) => DragTarget<int>(
    onMove: (d) => _hoverRow(item, d.offset + _grab),
    onLeave: (_) => _leaveRow(),
    onAcceptWithDetails: (d) {
      final drop = _drop;
      if (drop != null) {
        _dropAt(d.data, drop.$1, drop.$2);
      } else {
        _stopDrag();
      }
    },
    builder: (context, _, _) {
      final drop = _drop;
      final here = drop != null && drop.$1 == item.workspace.id;
      final before = here && drop.$2 == item.index;
      final after =
          here && drop.$2 == item.count && item.index == item.count - 1;
      return Padding(
        padding: EdgeInsets.only(top: gap),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            row,
            // In the 2 px gap between two rows (UI-A2 §6).
            if (before)
              const Positioned(
                left: 0,
                right: 0,
                top: -ShellxSizes.dropLine,
                child: _DropLine(),
              ),
            if (after)
              const Positioned(
                left: 0,
                right: 0,
                bottom: -ShellxSizes.dropLine,
                child: _DropLine(),
              ),
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(terminalTabsProvider);
    final sidebar = ref.watch(sidebarWorkspacesProvider);
    final home = ref.watch(homeDirectoryProvider);
    final workspaces = ref.read(sidebarWorkspacesProvider.notifier);
    final scaler = MediaQuery.textScalerOf(context);
    final items = _items();
    final rows = [
      for (final item in items)
        if (item is _RowItem) item,
    ];
    // Keyboard or ⌘1…⌘9 moved the selection: keep its row on screen; the
    // list's cursor goes with it (D14).
    ref.listen(terminalTabsProvider.select((s) => s.selectedId), (_, id) {
      _headerCursor = null;
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
    _rows.removeWhere((id, _) => !positions.containsKey(id));
    _headerKeys.removeWhere((id, _) => sidebar.workspace(id) == null);
    final cursor = _cursorHeader();

    Widget header(_HeaderItem item) {
      final w = item.workspace;
      return KeyedSubtree(
        key: ValueKey('ws.${w.id}'),
        child: DragTarget<int>(
          onMove: (_) => _hoverTarget(w.id, header: w.id),
          onLeave: (_) => _leaveTarget(w.id),
          onAcceptWithDetails: (d) => _dropAt(d.data, w.id),
          builder: (context, _, _) => WorkspaceHeader(
            key: _headerKeys.putIfAbsent(w.id, GlobalKey.new),
            name: w.displayName(l10n),
            count: item.count,
            collapsed: w.collapsed,
            containsSelected: item.containsSelected,
            focused: _showFocus && cursor == w.id,
            renaming: sidebar.renaming == RenameWorkspace(w.id),
            dropTarget: _dropTarget == w.id,
            deletable: !w.isDefault,
            onToggle: () => workspaces.toggleCollapsed(w.id),
            onStartRename: () => _startWorkspaceRename(w.id, fromList: false),
            onRename: (text) => _commitWorkspaceName(w.id, text),
            onCancelRename: () => _endRename(RenameWorkspace(w.id)),
            onNewTab: () => unawaited(workspaces.openTabIn(w.id)),
            onMenu: (at) => unawaited(_headerMenu(w, at)),
            onDelete: () => workspaces.delete(w.id),
          ),
        ),
      );
    }

    Widget empty(_EmptyItem item) {
      final target = 'empty.${item.workspaceId}';
      return DragTarget<int>(
        onMove: (_) => _hoverTarget(target),
        onLeave: (_) => _leaveTarget(target),
        onAcceptWithDetails: (d) => _dropAt(d.data, item.workspaceId, 0),
        builder: (context, _, _) => Container(
          key: ValueKey(target),
          height: _extent(item, scaler),
          padding: const EdgeInsets.only(left: ShellxSizes.contextInset),
          alignment: Alignment.centerLeft,
          decoration: _dropTarget == target
              ? BoxDecoration(
                  color: ShellxDesktopColors.primarySoft,
                  border: Border.all(color: ShellxDesktopColors.accent),
                  borderRadius: BorderRadius.circular(ShellxRadius.r6),
                )
              : null,
          // Read through the header's "0 tabs" (UI-A2 §3.4).
          child: ExcludeSemantics(
            child: Text(
              l10n.workspaceEmptyHint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ShellxText.caption.copyWith(
                color: ShellxDesktopColors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    Widget tabRow(_RowItem item, double gap) {
      final tab = item.tab;
      final row = SessionTabRow(
        key: _rows.putIfAbsent(tab.id, GlobalKey.new),
        tab: tab,
        selected: tab.id == state.selectedId,
        focused: tab.id == state.selectedId && _showFocus && cursor == null,
        position: positions[tab.id]!,
        count: rows.length,
        positionLabel: sidebar.showHeaders
            ? l10n.sidebarPositionInWorkspace(
                item.index + 1,
                item.count,
                item.workspace.displayName(l10n),
              )
            : null,
        home: home,
        renaming: sidebar.renaming == RenameTab(tab.id),
        onSelect: () {
          setState(() => _headerCursor = null);
          widget.onSelected(tab.id);
        },
        onClose: () => widget.onClose(tab),
        onStartRename: () => _startTabRename(tab.id, fromList: false),
        onRename: (text) => _commitTabName(tab.id, text),
        onCancelRename: () => _endRename(RenameTab(tab.id)),
        onOpenPort: (port) => unawaited(_openPort(port)),
        onMenu: (at) => unawaited(_rowMenu(tab, at)),
        extraActions: _rowActions(l10n, tab),
      );
      return _rowTarget(
        item,
        gap,
        KeyedSubtree(
          key: ValueKey('tab.${tab.id}'),
          // The open name field takes the clicks and drags (UI-A2 §4). The
          // draggable stays in the tree (only switched off), so opening the
          // field never rebuilds the row's subtree.
          child: _draggable(
            tab,
            home,
            row,
            enabled: sidebar.renaming != RenameTab(tab.id),
          ),
        ),
      );
    }

    final list = ListView.builder(
      key: _listKey,
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(
        ShellxSizes.listMarginH,
        ShellxSizes.listTop,
        ShellxSizes.listMarginH,
        ShellxSizes.listBottom,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        final gap = _gapBefore(items, i);
        if (item is _RowItem) return tabRow(item, gap);
        return Padding(
          padding: EdgeInsets.only(top: gap),
          child: switch (item) {
            _HeaderItem() => header(item),
            _EmptyItem() => empty(item),
            _RowItem() => const SizedBox.shrink(), // handled above
          },
        );
      },
    );

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
                canRequestFocus: items.isNotEmpty,
                skipTraversal: items.isEmpty,
                onKeyEvent: _onKey,
                child: Listener(
                  // The pointer drives auto-scroll even once the dragged
                  // row scrolled out of the list (UI-A2 §6).
                  onPointerMove: (e) {
                    if (_dragging) _autoScroll(e.position);
                  },
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ShellxScrollbar(
                          controller: widget.scrollController,
                          showOnHover: true,
                          child: list,
                        ),
                      ),
                      // UI-A2 §6: `grabbing` over the whole list while a
                      // tab is dragged, over port links and × too; it lets
                      // every hit through to the targets below.
                      if (_dragging)
                        const Positioned.fill(
                          child: MouseRegion(
                            cursor: SystemMouseCursors.grabbing,
                            opaque: false,
                            hitTestBehavior: HitTestBehavior.translucent,
                          ),
                        ),
                    ],
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

enum _HeaderAction { newTab, rename, toggle, delete }

/// What the list shows, top to bottom (UI-A2 §3, §3.4).
sealed class _Item {
  const _Item();
}

final class _HeaderItem extends _Item {
  const _HeaderItem(this.workspace, this.count, this.containsSelected);
  final Workspace workspace;
  final int count;

  /// Collapsed while holding the selected tab (UI-A2 §3.2).
  final bool containsSelected;
}

/// A tab's row: [index] (0-based) of [count] in [workspace].
final class _RowItem extends _Item {
  const _RowItem(this.tab, this.workspace, this.index, this.count);
  final TerminalTab tab;
  final Workspace workspace;
  final int index;
  final int count;
}

/// The hint of an expanded workspace without tabs (UI-A2 §3.4).
final class _EmptyItem extends _Item {
  const _EmptyItem(this.workspaceId);
  final String workspaceId;
}

/// UI-A2 §6 drop line: 2 px `accent`, radius 1, as wide as the row.
class _DropLine extends StatelessWidget {
  const _DropLine();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      key: const Key('drop.line'),
      height: ShellxSizes.dropLine,
      decoration: BoxDecoration(
        color: ShellxDesktopColors.accent,
        borderRadius: BorderRadius.circular(ShellxSizes.dropLine / 2),
      ),
    ),
  );
}

/// UI-A2 §6: a row starts dragging once the pointer moved more than 4 px
/// with the left button held, so a click with a slight jitter still
/// selects (Flutter's mouse slop is 1 px).
class _RowDraggable extends Draggable<int> {
  const _RowDraggable({
    required super.data,
    required super.feedback,
    required super.child,
    super.childWhenDragging,
    super.dragAnchorStrategy,
    super.onDragStarted,
    super.onDragEnd,
    super.onDraggableCanceled,
    super.maxSimultaneousDrags,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => _RowDragRecognizer()..onStart = onStart;
}

class _RowDragRecognizer extends MultiDragGestureRecognizer {
  _RowDragRecognizer() : super(debugOwner: null);

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      _RowDragPointerState(event.position, event.kind, gestureSettings);

  @override
  String get debugDescription => 'sidebar row drag';
}

class _RowDragPointerState extends MultiDragPointerState {
  _RowDragPointerState(
    super.initialPosition,
    super.kind,
    super.gestureSettings,
  );

  static const double _slop = 4;

  @override
  void checkForResolutionAfterMove() {
    if (pendingDelta!.distance > _slop) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) =>
      starter(initialPosition);
}

/// UI-A2 §6 drag feedback: a copy of the row, 208 wide, on `rowSelected`
/// with a 1 px `border`, `r6` and `e1`, at 92 %.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.tab, required this.home});
  final TerminalTab tab;
  final String home;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: Opacity(
          opacity: 0.92,
          child: Container(
            width: ShellxSizes.sidebarWidth - 2 * ShellxSizes.listMarginH,
            decoration: BoxDecoration(
              color: ShellxDesktopColors.rowSelected,
              borderRadius: BorderRadius.circular(ShellxRadius.r6),
              boxShadow: ShellxShadows.e1,
            ),
            foregroundDecoration: BoxDecoration(
              border: Border.all(color: ShellxDesktopColors.border),
              borderRadius: BorderRadius.circular(ShellxRadius.r6),
            ),
            child: SessionTabRow(
              tab: tab,
              selected: false,
              position: 1,
              count: 1,
              home: home,
              onSelect: () {},
              onClose: () {},
            ),
          ),
        ),
      ),
    ),
  );
}

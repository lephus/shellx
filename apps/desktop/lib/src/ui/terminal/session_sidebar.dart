import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../l10n/app_localizations.dart';
import '../../agent/desktop_services.dart' show desktopServicesProvider;
import '../../cli/agent_marks.dart';
import '../../integrations/pr_status.dart';
import '../../integrations/pr_status_parse.dart' show PrInfo;
import '../../terminal/agent_status_notifier.dart'
    show agentLiveTabsProvider, agentTabBadgeProvider;
import '../../terminal/local_sessions_provider.dart';
import '../../terminal/pane_layout.dart';
import '../../terminal/sidebar_workspaces.dart';
import '../../terminal/tab_attention.dart';
import '../../terminal/tab_meta.dart';
import '../../config/config_controller.dart';
import '../../remote/remote_port_forwards.dart';
import '../../terminal/terminal_tabs.dart';
import '../theme/shellx_desktop_theme.dart';
import 'session_tab_row.dart';
import 'shellx_menu.dart';
import 'sidebar_new_button.dart';
import 'sidebar_remote.dart';
import 'shortcut_labels.dart';
import 'sidebar_drag.dart';
import 'terminal_overlays.dart';
import 'terminal_shortcuts.dart';
import 'workspace_header.dart';

/// (hit − visual) / 2: where the 24 px visual of a 28 px icon button starts.
const double _bellInset = (ShellxSizes.iconHit - ShellxSizes.iconVisual) / 2;

/// UI §2.2: header band with the bell and `+`, then the tab list.
class SessionSidebar extends ConsumerStatefulWidget {
  const SessionSidebar({
    super.key,
    required this.focusNode,
    required this.scrollController,
    required this.onSelected,
    required this.onClose,
    required this.onEscape,
    this.panelOpen = false,
    required this.onToggleNotifications,
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

  /// The notifications panel is open: the bell shows "on" (UI-A4 §5.1).
  final bool panelOpen;

  /// The bell: open or close the panel (the page owns it).
  final VoidCallback onToggleNotifications;

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

  /// The tab being dragged: no drop line where it already is.
  int? _draggedId;

  /// V1: where the drag chip goes; the feedback's origin is the pointer,
  /// so drop details report the pointer itself.
  final _ghost = ValueNotifier(
    const DragGhostPlacement(pointer: Offset.zero, bounds: Rect.zero),
  );

  /// Empty-group hints by workspace id (the chip keeps clear of them).
  final _emptyKeys = <String, GlobalKey>{};

  /// The pinned copy of the current group's header (V7).
  final _stickyKey = GlobalKey();

  /// V6: the row (`('row', tabId)`) or header (`('ws', workspaceId)`)
  /// whose context menu is open.
  Object? _menuFor;
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
    _ghost.dispose();
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
    final attention = ref.read(tabAttentionProvider);
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
            // UI-A4 §3 (D22): only while collapsed.
            hasUnread:
                w.collapsed && tabs.any((t) => attention.hasUnread(t.id)),
          ),
        );
        if (w.collapsed) continue;
        if (tabs.isEmpty) {
          items.add(_EmptyItem(w.id));
          continue;
        }
      }
      for (final (i, tab) in tabs.indexed) {
        items.add(
          _RowItem(
            tab,
            w,
            i,
            tabs.length,
            notified: attention.hasUnread(tab.id),
            editingDescription: s.renaming == EditDescription(tab.id),
          ),
        );
      }
    }
    return items;
  }

  /// The list item's identity, independent of its index.
  static Key _itemKey(_Item item) => switch (item) {
    _HeaderItem(:final workspace) => ValueKey(('header', workspace.id)),
    _RowItem(:final tab) => ValueKey(('row', tab.id)),
    _EmptyItem(:final workspaceId) => ValueKey(('empty', workspaceId)),
  };

  /// Space above item [i]: 8 above a header (the first item has the
  /// list's top padding only), else the A1 row gap (UI-A2 §3.1).
  static double _gapBefore(List<_Item> items, int i) => i == 0
      ? 0
      : items[i] is _HeaderItem
      ? ShellxSizes.workspaceHeaderTop
      : ShellxSizes.rowGap;

  /// UI-A2 §1.3 + UI-A4 §1.3 heights.
  static double _extent(_Item item, TextScaler scaler) => switch (item) {
    _HeaderItem() => WorkspaceHeader.heightFor(scaler),
    _RowItem(:final tab, :final notified, :final editingDescription) =>
      SessionTabRow.heightFor(
        scaler,
        context: tab.hasContext,
        notification: notified,
        description: tab.meta.description.isNotEmpty,
        editingDescription: editingDescription,
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
        _announceHeader(target);
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
          _announceHeader(ws);
          WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(ws));
        } else {
          setState(() => _headerCursor = header.id);
          if (!header.collapsed) {
            workspaces.setCollapsed(header.id, true);
            _announceHeader(header.id);
          }
        }
      case LogicalKeyboardKey.arrowRight:
        if (header == null) return KeyEventResult.ignored;
        setState(() => _headerCursor = header.id);
        if (header.collapsed) {
          workspaces.setCollapsed(header.id, false);
          _announceHeader(header.id);
        } else {
          // Its first row (a member without a tab yet has no row).
          final first = nav.indexWhere(
            (t) => t is int && s.workspaceOf(t) == header.id,
          );
          if (first >= 0) go(first);
        }
      case LogicalKeyboardKey.enter ||
          LogicalKeyboardKey.numpadEnter ||
          LogicalKeyboardKey.space:
        if (header != null) {
          setState(() => _headerCursor = header.id);
          workspaces.toggleCollapsed(header.id);
          _announceHeader(header.id);
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
    // V7: a row's group header is pinned over the list's top; the row
    // must show below it.
    final inset =
        target is int && ref.read(sidebarWorkspacesProvider).showHeaders
        ? WorkspaceHeader.heightFor(scaler)
        : 0.0;
    double? jump;
    if (found - ShellxSizes.listTop - inset < position.pixels) {
      jump = found - ShellxSizes.listTop - inset;
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

  // ---- pin, description, status (A11 D18) -------------------------------

  void _togglePin(TerminalTab tab) {
    ref
        .read(terminalTabsProvider.notifier)
        .setMeta(tab.id, (m) => m.copyWith(pinned: !m.pinned));
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(tab.id));
  }

  void _startDescription(int id, {required bool fromList}) {
    final target = EditDescription(id);
    _renameFromList = fromList ? target : null;
    ref.read(sidebarWorkspacesProvider.notifier).startRename(target);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(id));
  }

  void _commitDescription(int id, String text) {
    if (!mounted) return;
    ref
        .read(terminalTabsProvider.notifier)
        .setMeta(id, (m) => m.copyWith(description: text));
    _endRename(EditDescription(id));
  }

  /// "Status ▸": the five states at the row menu's place, the current one
  /// checked.
  Future<void> _statusMenu(TerminalTab tab, Offset at) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showShellxMenu<TabStatus>(
      context: context,
      at: at,
      entries: [
        for (final s in TabStatus.values)
          ShellxMenuEntry(
            key: Key('menu.status.${s.wire}'),
            value: s,
            label: tabStatusText(l10n, s),
            checked: tab.meta.status == s,
          ),
      ],
    );
    if (choice == null || !mounted) return;
    ref
        .read(terminalTabsProvider.notifier)
        .setMeta(tab.id, (m) => m.copyWith(status: choice));
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

  /// A8 D19: an SSH tab's port goes through a forward. A tab's ports are
  /// its focused pane's (`TerminalTab.ports`), so that pane owns the port.
  /// A12 D16: the pull request's page, in the browser. The address was
  /// checked when it was read (https, no user information); the opener
  /// checks again.
  Future<void> _openPr(PrInfo pr) async {
    try {
      final uri = Uri.parse(pr.url);
      await ref.read(desktopServicesProvider).urlOpener.open(uri);
    } on Object catch (e) {
      debugPrint('ShellX: pull request not opened: ${e.runtimeType}');
    }
  }

  Future<void> _openPort(TerminalTab tab, int port) =>
      ref.read(remotePortForwardsProvider.notifier).open(tab.focused, port);

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

  /// D14 / UI-A2 §8: the list's focus stays on the list node, so a screen
  /// reader hears where the tree cursor landed, and a header's new state
  /// after a toggle: "Workspace Backend, 2 tabs, collapsed".
  void _announceHeader(String id) {
    final l10n = AppLocalizations.of(context);
    final s = ref.read(sidebarWorkspacesProvider);
    final w = s.workspace(id);
    if (w == null) return;
    final tabsState = ref.read(terminalTabsProvider);
    final present = {for (final t in tabsState.tabs) t.id};
    final members = [
      for (final t in s.tabsOf(id))
        if (present.contains(t)) t,
    ];
    final message = [
      l10n.workspaceHeaderSemantics(w.displayName(l10n), members.length),
      if (w.collapsed && members.contains(tabsState.selectedId))
        l10n.workspaceContainsSelected,
      w.collapsed ? l10n.workspaceCollapsedState : l10n.workspaceExpandedState,
    ].join(', ');
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
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

  /// V6: [menuFor] keeps its highlight while [show] (a menu) is open.
  Future<T?> _withMenuOpen<T>(
    Object menuFor,
    Future<T?> Function() show,
  ) async {
    setState(() => _menuFor = menuFor);
    try {
      return await show();
    } finally {
      if (mounted && _menuFor == menuFor) setState(() => _menuFor = null);
    }
  }

  /// UI-A2 §5.1. More than two ports go into an "Open port in browser…"
  /// submenu (V12), so the menu stays short.
  Future<void> _rowMenu(TerminalTab tab, Offset at) async {
    final l10n = AppLocalizations.of(context);
    // Shift+F10 / the Menu key: the list has the keyboard (UI-A2 §4).
    final fromList = widget.focusNode.hasFocus;
    final workspaces = ref.read(sidebarWorkspacesProvider.notifier);
    // The five smallest (UI-A2 §5.1).
    final ports = tab.exited
        ? const <int>[]
        : ([...tab.ports]..sort()).take(5).toList();
    final portSubmenu = ports.length > 2;
    final attention = ref.read(tabAttentionProvider);
    final remoteEntries = remoteRowEntries(l10n, tab);
    await _withMenuOpen(('row', tab.id), () async {
      final choice = await showShellxMenu<Object>(
        context: context,
        at: at,
        entries: [
          ...remoteEntries,
          // UI-A4 §10.4 (D23): first, dimmed when there is nothing to read.
          ShellxMenuEntry(
            key: const Key('menu.markRead'),
            value: _RowAction.markRead,
            label: l10n.attentionMarkRead,
            enabled: attention.hasUnread(tab.id),
            dividerBefore: remoteEntries.isNotEmpty,
          ),
          ShellxMenuEntry(
            key: const Key('menu.markAllRead'),
            value: _RowAction.markAllRead,
            label: l10n.attentionMarkAllRead,
            enabled: attention.totalUnread > 0,
          ),
          ShellxMenuEntry(
            key: const Key('menu.renameTab'),
            value: _RowAction.rename,
            label: l10n.tabRename,
            shortcut: renameShortcutLabel(),
            dividerBefore: true,
          ),
          if (tab.customTitle != null)
            ShellxMenuEntry(
              key: const Key('menu.automaticName'),
              value: _RowAction.automaticName,
              label: l10n.tabUseAutomaticName,
            ),
          // A11 D18.
          ShellxMenuEntry(
            key: const Key('menu.pinTab'),
            value: _RowAction.togglePin,
            label: tab.meta.pinned ? l10n.tabUnpin : l10n.tabPin,
            dividerBefore: true,
          ),
          ShellxMenuEntry(
            key: const Key('menu.setDescription'),
            value: _RowAction.setDescription,
            label: l10n.tabSetDescription,
          ),
          ShellxMenuEntry(
            key: const Key('menu.status'),
            value: _RowAction.status,
            label: '${l10n.tabStatusMenu} ▸',
          ),
          // UI-A3 §4.2.
          ShellxMenuEntry(
            key: const Key('menu.row.splitRight'),
            value: _RowAction.splitRight,
            label: l10n.paneSplitRight,
            shortcut: splitRightShortcutLabel(),
            dividerBefore: true,
          ),
          ShellxMenuEntry(
            key: const Key('menu.row.splitDown'),
            value: _RowAction.splitDown,
            label: l10n.paneSplitDown,
            shortcut: splitDownShortcutLabel(),
          ),
          if (tab.isSplit)
            ShellxMenuEntry(
              key: const Key('menu.row.equalize'),
              value: _RowAction.equalize,
              label: l10n.paneEqualize,
              shortcut: equalizePanesShortcutLabel(),
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
          if (portSubmenu)
            ShellxMenuEntry(
              key: const Key('menu.ports'),
              value: _RowAction.ports,
              label: l10n.tabOpenPortMenu,
              dividerBefore: true,
            )
          else
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
            // Final N-2: a split tab says every pane goes.
            label: tab.isSplit
                ? l10n.terminalCloseTabAllPanes
                : l10n.terminalCloseTab,
            // D6: ⌘W closes a pane of a split tab.
            shortcut: tab.isSplit ? null : closeTabShortcutLabel(),
            dividerBefore: true,
          ),
        ],
      );
      if (!mounted) return null;
      switch (choice) {
        case _RowAction.markRead:
          ref.read(tabAttentionProvider.notifier).markRead(tab.id);
        case _RowAction.markAllRead:
          ref.read(tabAttentionProvider.notifier).markAllRead();
        case _RowAction.rename:
          _startTabRename(tab.id, fromList: fromList);
        case _RowAction.automaticName:
          ref.read(terminalTabsProvider.notifier).rename(tab.id, null);
        case _RowAction.togglePin:
          _togglePin(tab);
        case _RowAction.setDescription:
          _startDescription(tab.id, fromList: fromList);
        case _RowAction.status:
          await _statusMenu(tab, at);
        case _RowAction.splitRight:
          _splitFromRow(tab, SplitAxis.row);
        case _RowAction.splitDown:
          _splitFromRow(tab, SplitAxis.column);
        case _RowAction.equalize:
          widget.onSelected(tab.id);
          Actions.maybeInvoke(context, const EqualizePanesIntent());
        case _RowAction.moveTo:
          await _moveToMenu(tab, at, fromList: fromList);
        case _RowAction.ports:
          await _portMenu(tab, ports, at);
        case _RowAction.moveUp:
          _moveUp(tab.id);
        case _RowAction.moveDown:
          _moveDown(tab.id);
        case _RowAction.close:
          widget.onClose(tab);
        case final int port:
          await _openPort(tab, port);
        case final RemoteMenuAction action:
          await runRemoteMenuAction(ref, action, tab: tab);
      }
      return null;
    });
  }

  /// V12: one entry per port ("Open http://localhost:3000"), at the same
  /// place as the row menu.
  Future<void> _portMenu(TerminalTab tab, List<int> ports, Offset at) async {
    final l10n = AppLocalizations.of(context);
    final port = await showShellxMenu<int>(
      context: context,
      at: at,
      entries: [
        for (final port in ports)
          ShellxMenuEntry(
            key: Key('menu.port.$port'),
            value: port,
            label: l10n.portOpenTooltip(port),
          ),
      ],
    );
    if (port != null && mounted) await _openPort(tab, port);
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
        // V6: the submenu names the tab it moves.
        ShellxMenuEntry(
          key: const Key('menu.moveTo.title'),
          value: '',
          label: l10n.tabMoveToTitle(tab.label),
          heading: true,
        ),
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
          dividerBefore: true,
        ),
      ],
    );
    if (choice == null || choice.isEmpty || !mounted) return;
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

  /// D21/D30: the row's tab is selected first, then the window's split
  /// action runs (announcement and focus included).
  void _splitFromRow(TerminalTab tab, SplitAxis axis) {
    widget.onSelected(tab.id);
    Actions.maybeInvoke(context, SplitPaneIntent(axis));
  }

  /// UI-A2 §8 + UI-A4 §8, in the row menu's order (the row adds "Mark
  /// as read" before and "Close tab" after): mark all as read (when
  /// anything is unread), rename, move (only what can be done), one per
  /// port.
  Map<CustomSemanticsAction, VoidCallback> _rowActions(
    AppLocalizations l10n,
    TerminalTab tab, [
    PrInfo? pr,
  ]) {
    final workspaces = ref.read(sidebarWorkspacesProvider.notifier);
    final anyUnread = ref.read(tabAttentionProvider).totalUnread > 0;
    return {
      if (anyUnread)
        CustomSemanticsAction(label: l10n.attentionMarkAllRead): () =>
            ref.read(tabAttentionProvider.notifier).markAllRead(),
      CustomSemanticsAction(label: l10n.tabRename): () =>
          _startTabRename(tab.id, fromList: widget.focusNode.hasFocus),
      CustomSemanticsAction(
        label: tab.meta.pinned ? l10n.tabUnpin : l10n.tabPin,
      ): () =>
          _togglePin(tab),
      CustomSemanticsAction(label: l10n.tabSetDescription): () =>
          _startDescription(tab.id, fromList: widget.focusNode.hasFocus),
      // UI-A3 §8.
      CustomSemanticsAction(label: l10n.paneSplitRight): () =>
          _splitFromRow(tab, SplitAxis.row),
      CustomSemanticsAction(label: l10n.paneSplitDown): () =>
          _splitFromRow(tab, SplitAxis.column),
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
            unawaited(_openPort(tab, port)),
      if (pr != null)
        CustomSemanticsAction(label: l10n.tabOpenPr(pr.number)): () =>
            unawaited(_openPr(pr)),
    };
  }

  /// UI-A2 §5.2.
  Future<void> _headerMenu(Workspace w, Offset at) async {
    final l10n = AppLocalizations.of(context);
    // Shift+F10 / the Menu key: the list has the keyboard (UI-A2 §4).
    final fromList = widget.focusNode.hasFocus;
    final remoteEntries = remoteHeaderEntries(
      l10n,
      w,
      canReconnect: workspaceCanReconnect(ref, w.id),
    );
    final choice = await _withMenuOpen(
      ('ws', w.id),
      () => showShellxMenu<Object>(
        context: context,
        at: at,
        entries: [
          ...remoteEntries,
          // A server workspace's "New SSH tab on …" replaces this one.
          if (w.ssh == null)
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
            dividerBefore: remoteEntries.isNotEmpty,
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
            // V12: say why it is greyed out.
            tooltip: w.isDefault ? l10n.workspaceDeleteDefaultReason : null,
            dividerBefore: true,
          ),
        ],
      ),
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
      case final RemoteMenuAction action:
        await runRemoteMenuAction(ref, action, workspaceId: w.id);
    }
  }

  // ---- drag and drop (UI-A2 §6) -----------------------------------------

  /// V1: the feedback's origin is the pointer (the chip hangs off it).
  Offset _anchor(Draggable<Object> d, BuildContext context, Offset position) {
    _placeGhost(pointer: position, avoid: null);
    return Offset.zero;
  }

  Rect? _globalRect(BuildContext? context) {
    final box = context?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Moves the chip; [avoid] keeps what it must not cover (unchanged when
  /// left out).
  void _placeGhost({Offset? pointer, Object? avoid = _keepAvoid}) {
    final now = _ghost.value;
    _ghost.value = DragGhostPlacement(
      pointer: pointer ?? now.pointer,
      bounds: _globalRect(_listKey.currentContext) ?? now.bounds,
      avoid: identical(avoid, _keepAvoid) ? now.avoid : avoid as Rect?,
    );
  }

  static const Object _keepAvoid = Object();

  void _stopDrag() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
    _expandTimer?.cancel();
    _expandTimer = null;
    if (!mounted) return;
    setState(() {
      _dragging = false;
      _draggedId = null;
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
      if (next == p.pixels) return;
      controller.jumpTo(next);
      // The content moved under a still pointer: the slot it showed is
      // stale until the pointer moves again (no drop meanwhile).
      _expandTimer?.cancel();
      _expandTimer = null;
      if (_drop != null || _dropTarget != null) {
        setState(() {
          _drop = null;
          _dropTarget = null;
        });
      }
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
    // The drop line sits in the 2 px gap above or below the row.
    final rect = box.localToGlobal(Offset.zero) & box.size;
    _placeGhost(
      avoid: _isNoOp(slot)
          ? null
          : Rect.fromLTRB(
              rect.left,
              before ? rect.top - ShellxSizes.dropLine : rect.bottom,
              rect.right,
              before ? rect.top : rect.bottom + ShellxSizes.dropLine,
            ),
    );
    if (slot == _drop && _dropTarget == null) return;
    setState(() {
      _drop = slot;
      _dropTarget = null;
    });
  }

  void _leaveRow() {
    _placeGhost(avoid: null); // no stale rect to jump around
    if (_drop != null) setState(() => _drop = null);
  }

  /// A header (workspace id) or an empty hint (`empty.<id>`); over a
  /// collapsed header for 600 ms, the workspace expands (UI-A2 §6).
  void _hoverTarget(String target, BuildContext? context, {String? header}) {
    _placeGhost(avoid: _globalRect(context));
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
    _placeGhost(avoid: null);
    _expandTimer?.cancel();
    _expandTimer = null;
    setState(() => _dropTarget = null);
  }

  /// A drop at [slot] would leave the dragged tab where it is.
  bool _isNoOp((String, int) slot) {
    final id = _draggedId;
    if (id == null) return false;
    final s = ref.read(sidebarWorkspacesProvider);
    if (s.workspaceOf(id) != slot.$1) return false;
    final at = s.tabsOf(slot.$1).indexOf(id);
    return slot.$2 == at || slot.$2 == at + 1;
  }

  /// A tab closed mid-drag is simply not moved (moveTab ignores it). A
  /// real move is announced like ⌥↑/⌥↓ (UI-A2 §8).
  void _dropAt(int tabId, String workspaceId, [int? index]) {
    final s = ref.read(sidebarWorkspacesProvider);
    final from = s.workspaceOf(tabId);
    final list = s.tabsOf(workspaceId);
    final noOp =
        from == workspaceId &&
        (index == null
            ? list.lastOrNull == tabId
            : _isNoOp((workspaceId, index)));
    ref
        .read(sidebarWorkspacesProvider.notifier)
        .moveTab(tabId, workspaceId, index);
    _stopDrag();
    if (from != null && !noOp) _announceMove(tabId);
  }

  void _endDragLater() {
    if (!_dragging) return;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted && _dragging) _stopDrag();
      })
      ..ensureVisualUpdate();
  }

  /// A header or empty hint takes the drop only while it shows as the
  /// target (not after the list scrolled under the pointer).
  void _dropOnTarget(String target, int tabId, String workspaceId, [int? i]) {
    if (_dropTarget == target) {
      _dropAt(tabId, workspaceId, i);
    } else {
      _stopDrag();
    }
  }

  Widget _draggable(
    TerminalTab tab,
    String home,
    Widget row, {
    required bool enabled,
  }) => SidebarRowDraggable(
    data: tab.id,
    maxSimultaneousDrags: enabled ? null : 0,
    dragAnchorStrategy: _anchor,
    feedback: SidebarDragFeedback(tab: tab, placement: _ghost),
    childWhenDragging: Opacity(
      opacity: ShellxDesktopColors.disabledOpacity,
      child: row,
    ),
    onDragStarted: () => setState(() {
      _dragging = true;
      _draggedId = tab.id;
    }),
    onDragEnd: (_) => _stopDrag(),
    onDraggableCanceled: (_, _) => _stopDrag(),
    child: row,
  );

  /// The row and the gap above it: the gap belongs to "before this row",
  /// where its drop line shows.
  Widget _rowTarget(_RowItem item, double gap, Widget row) => DragTarget<int>(
    onMove: (d) => _hoverRow(item, d.offset),
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
      final slot = _drop;
      final drop = slot == null || _isNoOp(slot) ? null : slot;
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
                child: SidebarDropLine(),
              ),
            if (after)
              const Positioned(
                left: 0,
                right: 0,
                bottom: -ShellxSizes.dropLine,
                child: SidebarDropLine(),
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
    // A8: rows' port tooltips say whether a server's port is forwarded.
    ref.watch(remotePortForwardsProvider);
    registerRowActionOrder(l10n);
    // Only the unread map: history alone (a notice the user saw) does not
    // rebuild the sidebar.
    final unread = ref.watch(tabAttentionProvider.select((s) => s.unread));
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
    // Tooltips and menu hints follow a reload (A9 D29).
    ref.watch(shellxConfigProvider.select((s) => s.bindings));
    final shortcut = newTabShortcutLabel();
    final newTab = SidebarNewButton(
      semanticLabel: l10n.terminalNewTab,
      tooltip: shortcutTooltip(l10n.terminalNewTabTooltip, shortcut),
      busy: state.opening,
    );
    // UI-A4 §5.1: hollow at 0; filled with a 6 px dot when anything is
    // unread; `rowSelected` ("on") while the panel is open.
    final total = unread.values.fold(0, (sum, u) => sum + u.count);
    final bellShortcut = notificationsShortcutLabel();
    final bell = Stack(
      clipBehavior: Clip.none,
      children: [
        ShellxIconButton(
          key: const Key('sidebar.bell'),
          icon: total > 0 ? Icons.notifications : Icons.notifications_none,
          semanticLabel: total > 0
              ? '${l10n.notificationsPanelTitle}, '
                    '${l10n.attentionUnreadCount(total)}'
              : l10n.notificationsPanelTitle,
          tooltip: shortcutTooltip(
            l10n.notificationsPanelTooltip,
            bellShortcut,
          ),
          selected: widget.panelOpen,
          onPressed: widget.onToggleNotifications,
        ),
        if (total > 0)
          const Positioned(
            // Centre (19, 7) of the 24 visual, which sits 2 px inside 28.
            left: _bellInset + 19 - ShellxSizes.bellDot / 2,
            top: _bellInset + 7 - ShellxSizes.bellDot / 2,
            child: IgnorePointer(
              child: SizedBox.square(
                key: Key('sidebar.bell.dot'),
                dimension: ShellxSizes.bellDot,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: ShellxDesktopColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    // A gear that opens Settings (and its Projects page) with a click, so
    // it is not reachable by ⌘, alone.
    final settings = ShellxIconButton(
      key: const Key('sidebar.settings'),
      icon: Icons.settings_outlined,
      semanticLabel: l10n.settingsTitle,
      tooltip: shortcutTooltip(l10n.settingsTooltip, settingsShortcutLabel()),
      onPressed: () =>
          Actions.maybeInvoke(context, const OpenSettingsIntent()),
    );
    // macOS: both centred on the traffic-light line y = 14 (UI §2.1).
    final buttonTop = EdgeInsets.only(
      top: mac ? ShellxSizes.trafficLightsCenterY - ShellxSizes.iconHit / 2 : 0,
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
          // Tab order: settings → bell → `+` → list (UI-A4 §5.1).
          Padding(padding: buttonTop, child: settings),
          const SizedBox(width: ShellxSizes.headerBellGap - 2 * _bellInset),
          Padding(padding: buttonTop, child: bell),
          // 4 px between the 24 px visuals (A1 band): the hit squares touch.
          const SizedBox(width: ShellxSizes.headerBellGap - 2 * _bellInset),
          Padding(padding: buttonTop, child: newTab),
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
    _emptyKeys.removeWhere((id, _) => sidebar.workspace(id) == null);
    final cursor = _cursorHeader();
    final indent = sidebar.showHeaders ? ShellxSizes.workspaceRowIndent : 0.0;

    /// The 8 px above a header drops into it too (no dead band). [sticky]:
    /// the pinned copy over the list's top (V7): no name field, no ring,
    /// not in semantics (the real header is), the same drop target.
    Widget header(_HeaderItem item, double gap, {bool sticky = false}) {
      final w = item.workspace;
      final key = sticky
          ? _stickyKey
          : _headerKeys.putIfAbsent(w.id, GlobalKey.new);
      return DragTarget<int>(
        onMove: (_) => _hoverTarget(w.id, key.currentContext, header: w.id),
        onLeave: (_) => _leaveTarget(w.id),
        onAcceptWithDetails: (d) => _dropOnTarget(w.id, d.data, w.id),
        builder: (context, _, _) => Padding(
          padding: EdgeInsets.only(top: gap),
          child: KeyedSubtree(
            key: ValueKey(sticky ? 'sticky.ws.${w.id}' : 'ws.${w.id}'),
            child: WorkspaceHeader(
              key: key,
              workspaceId: w.id,
              name: w.displayName(l10n),
              fontStep: w.fontStep,
              count: item.count,
              collapsed: w.collapsed,
              containsSelected: item.containsSelected,
              hasUnread: item.hasUnread,
              ssh: w.ssh,
              focused: !sticky && _showFocus && cursor == w.id,
              renaming: !sticky && sidebar.renaming == RenameWorkspace(w.id),
              dropTarget: _dropTarget == w.id,
              deletable: !w.isDefault,
              menuOpen: _menuFor == ('ws', w.id),
              onToggle: () => workspaces.toggleCollapsed(w.id),
              onStartRename: () => _startWorkspaceRename(w.id, fromList: false),
              onRename: (text) => _commitWorkspaceName(w.id, text),
              onCancelRename: () => _endRename(RenameWorkspace(w.id)),
              onNewTab: () => unawaited(workspaces.openTabIn(w.id)),
              onMenu: (at) => unawaited(_headerMenu(w, at)),
              onDelete: () => workspaces.delete(w.id),
            ),
          ),
        ),
      );
    }

    Widget empty(_EmptyItem item) {
      final target = 'empty.${item.workspaceId}';
      final key = _emptyKeys.putIfAbsent(item.workspaceId, GlobalKey.new);
      return DragTarget<int>(
        onMove: (_) => _hoverTarget(target, key.currentContext),
        onLeave: (_) => _leaveTarget(target),
        onAcceptWithDetails: (d) =>
            _dropOnTarget(target, d.data, item.workspaceId, 0),
        builder: (context, _, _) => KeyedSubtree(
          key: key,
          child: Container(
            key: ValueKey(target),
            height: _extent(item, scaler),
            padding: const EdgeInsets.only(left: ShellxSizes.contextInset),
            alignment: Alignment.centerLeft,
            decoration: _dropTarget == target
                ? BoxDecoration(
                    color: ShellxDesktopColors.primarySoft,
                    borderRadius: BorderRadius.circular(ShellxRadius.r6),
                  )
                : null,
            // The border in front: it never moves the text by 1 px.
            foregroundDecoration: _dropTarget == target
                ? BoxDecoration(
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
        ),
      );
    }

    Widget tabRow(_RowItem item, double gap) {
      final tab = item.tab;
      // A7 D27, ruling M7: each row watches only its own mark, so a
      // command rebuilds that row, not the sidebar. The marks prune
      // themselves at expiry, so the chip goes on time.
      final row = Consumer(
        builder: (context, rowRef, _) {
          // A12 D16: the pull request of the branch; only the tab in view
          // asks for a lookup.
          final pr = rowRef.watch(
            prChipProvider((
              cwd: tab.cwd,
              branch: tab.gitBranch,
              remote: tab.focused.remote != null,
              visible: tab.id == state.selectedId,
            )),
          );
          return SessionTabRow(
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
            editingDescription: sidebar.renaming == EditDescription(tab.id),
            onDescription: (text) => _commitDescription(tab.id, text),
            onCancelDescription: () => _endRename(EditDescription(tab.id)),
            onOpenPort: (port) => unawaited(_openPort(tab, port)),
            portTooltip: (port) => remotePortTooltipFor(ref, l10n, tab, port),
            onMenu: (at) => unawaited(_rowMenu(tab, at)),
            extraActions: _rowActions(l10n, tab, pr),
            menuOpen: _menuFor == ('row', tab.id),
            unread: unread[tab.id],
            onMarkRead: () =>
                ref.read(tabAttentionProvider.notifier).markRead(tab.id),
            pr: pr,
            onOpenPr: (info) => unawaited(_openPr(info)),
            agentStatus: rowRef.watch(agentTabBadgeProvider(tab.id)),
            agentLive: rowRef.watch(
              agentLiveTabsProvider.select((s) => s.contains(tab.id)),
            ),
            agent: rowRef.watch(
              agentMarksProvider.select(
                (m) =>
                    m.tabActive(tab.id, rowRef.read(agentMarksClockProvider)()),
              ),
            ),
          );
        },
      );
      // V9: under a header, rows sit 8 px in. The padding is always
      // there (0 without headers): the row's subtree never changes shape.
      return Padding(
        padding: EdgeInsets.only(left: indent),
        child: _rowTarget(
          item,
          gap,
          KeyedSubtree(
            key: ValueKey('tab.${tab.id}'),
            // The open name field takes the clicks and drags (UI-A2 §4).
            // The draggable stays in the tree (only switched off), so
            // opening the field never rebuilds the row's subtree.
            child: _draggable(
              tab,
              home,
              row,
              enabled:
                  sidebar.renaming != RenameTab(tab.id) &&
                  sidebar.renaming != EditDescription(tab.id),
            ),
          ),
        ),
      );
    }

    // Item tops in the list's content, for the pinned header (V7).
    final tops = <double>[];
    var nextTop = ShellxSizes.listTop;
    for (final (i, item) in items.indexed) {
      nextTop += _gapBefore(items, i);
      tops.add(nextTop);
      nextTop += _extent(item, scaler);
    }
    final headerHeight = WorkspaceHeader.heightFor(scaler);

    /// V7: once a group's header scrolls above the list's top while its
    /// rows still show, a copy of it stays pinned there (pushed up by the
    /// next header), with a 1 px `line` under it. Without a pinned header,
    /// the same line marks a list scrolled under the band.
    Widget pinned(BuildContext context, Widget? _) {
      final controller = widget.scrollController;
      final pixels = controller.hasClients ? controller.offset : 0.0;
      if (pixels <= 0) return const SizedBox.shrink();
      const edge = Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: 1,
        child: ColoredBox(
          key: Key('sidebar.scrollEdge'),
          color: ShellxDesktopColors.line,
        ),
      );
      int? at;
      if (sidebar.showHeaders) {
        for (final (i, item) in items.indexed) {
          if (item is _HeaderItem && tops[i] < pixels) at = i;
        }
      }
      if (at == null) return const Stack(children: [edge]);
      final next = items.indexed
          .skip(at + 1)
          .where((e) => e.$2 is _HeaderItem)
          .firstOrNull;
      var y = 0.0;
      if (next != null) {
        final limit =
            tops[next.$1] -
            ShellxSizes.workspaceHeaderTop -
            pixels -
            headerHeight;
        if (limit <= -headerHeight) return const Stack(children: [edge]);
        y = min(0, limit);
      }
      return Stack(
        children: [
          Positioned(
            top: y,
            left: 0,
            // The 6 px right gutter stays the scrollbar thumb's.
            right: ShellxSizes.listMarginH,
            child: ExcludeSemantics(
              child: DecoratedBox(
                key: const Key('sidebar.stickyBand'),
                decoration: const BoxDecoration(
                  color: ShellxDesktopColors.bgSidebar,
                  border: Border(
                    bottom: BorderSide(color: ShellxDesktopColors.line),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: ShellxSizes.listMarginH),
                  child: header(items[at] as _HeaderItem, 0, sticky: true),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final itemIndex = {
      for (final (i, item) in items.indexed) _itemKey(item): i,
    };
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
      // Items keep their elements when others are inserted or removed
      // above them: an open name field is never rebuilt elsewhere (it
      // would commit what was typed and reopen with the old name).
      findChildIndexCallback: (key) => itemIndex[key],
      itemBuilder: (context, i) {
        final item = items[i];
        final gap = _gapBefore(items, i);
        return KeyedSubtree(
          key: _itemKey(item),
          child: switch (item) {
            _RowItem() => tabRow(item, gap),
            _HeaderItem() => header(item, gap),
            _EmptyItem() => Padding(
              padding: EdgeInsets.only(top: gap, left: indent),
              child: empty(item),
            ),
          },
        );
      },
    );

    return ColoredBox(
      color: ShellxDesktopColors.bgSidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The drag area lies under the buttons, not around them: a click
          // on the bell or `+` never waits for its double-click (zoom).
          if (mac)
            Stack(
              children: [
                const Positioned.fill(
                  child: DragToMoveArea(child: SizedBox.expand()),
                ),
                band,
              ],
            )
          else
            band,
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
                    if (!_dragging) return;
                    _autoScroll(e.position);
                    _placeGhost(pointer: e.position);
                  },
                  // A safety net: whatever ends the drag (or fails to, if
                  // its source row is gone), the drag state never
                  // outlives the button. After the frame, so a drop is
                  // handled first.
                  onPointerUp: (_) => _endDragLater(),
                  onPointerCancel: (_) => _endDragLater(),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ShellxScrollbar(
                          controller: widget.scrollController,
                          showOnHover: true,
                          crossAxisMargin: 0,
                          child: list,
                        ),
                      ),
                      Positioned.fill(
                        child: ListenableBuilder(
                          listenable: widget.scrollController,
                          builder: pinned,
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

enum _RowAction {
  markRead,
  markAllRead,
  rename,
  automaticName,
  togglePin,
  setDescription,
  status,
  splitRight,
  splitDown,
  equalize,
  moveTo,
  moveUp,
  moveDown,
  ports,
  close,
}

enum _HeaderAction { newTab, rename, toggle, delete }

/// What the list shows, top to bottom (UI-A2 §3, §3.4).
sealed class _Item {
  const _Item();
}

final class _HeaderItem extends _Item {
  const _HeaderItem(
    this.workspace,
    this.count,
    this.containsSelected, {
    this.hasUnread = false,
  });
  final Workspace workspace;
  final int count;

  /// Collapsed while holding the selected tab (UI-A2 §3.2).
  final bool containsSelected;

  /// Collapsed while holding a tab with unread (UI-A4 §3, D22).
  final bool hasUnread;
}

/// A tab's row: [index] (0-based) of [count] in [workspace].
final class _RowItem extends _Item {
  const _RowItem(
    this.tab,
    this.workspace,
    this.index,
    this.count, {
    this.notified = false,
    this.editingDescription = false,
  });
  final TerminalTab tab;
  final Workspace workspace;
  final int index;
  final int count;

  /// The tab has unread: the row grows by the notification line
  /// (UI-A4 §1.3).
  final bool notified;

  /// A11 D18: the description field is open on this row.
  final bool editingDescription;
}

/// The hint of an expanded workspace without tabs (UI-A2 §3.4).
final class _EmptyItem extends _Item {
  const _EmptyItem(this.workspaceId);
  final String workspaceId;
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart' show SessionLaunch;

import '../restore/restore_capture.dart' show savePaneTree;
import '../restore/restore_snapshot.dart';
import '../restore/scrollback_codec.dart';
import 'local_sessions_provider.dart' show appL10nProvider;
import 'sidebar_workspaces.dart';
import 'terminal_tabs.dart';
import '../agent/desktop_services.dart' show clockProvider;

// A11 D14: what the user closed, kept in memory so ⌘⇧T can bring it back.
// Never written to disk, never logged: the text is what the terminal showed.

/// UTF-8 size of [s] without keeping a copy around.
int _utf8Length(String s) => utf8.encoder.convert(s).length;

sealed class ClosedItem {
  const ClosedItem();

  /// The text this item holds, in UTF-8 bytes (the ring's budget).
  int get textBytes;

  /// A closed tab with neither text nor a folder is not worth a slot.
  bool get isWorthKeeping;

  /// When it was closed; the divider of the reopened text says so.
  DateTime? get closedAt;

  ClosedItem withoutText();

  /// Never what the terminal showed (A11 §5).
  @override
  String toString() => '…';
}

final class ClosedTab extends ClosedItem {
  ClosedTab({
    required this.tab,
    required this.textByKey,
    required this.workspaceId,
    required this.index,
    required this.label,
    this.closedAt,
  });

  /// The tab as A5a saves it (panes, split tree, focus, zoom, name).
  final SavedTab tab;

  /// Per pane key: the scrollback as printable text + SGR.
  final Map<String, String> textByKey;
  final String? workspaceId;

  /// Its place among the workspace's tabs when it closed.
  final int index;
  final String label;
  @override
  final DateTime? closedAt;

  @override
  late final int textBytes = textByKey.values.fold(
    0,
    (n, t) => n + _utf8Length(t),
  );

  @override
  bool get isWorthKeeping =>
      textBytes > 0 ||
      savedLeaves(tab.layout).any((p) => p.cwd != null || p.launch != null);

  @override
  ClosedItem withoutText() => ClosedTab(
    tab: tab,
    textByKey: const {},
    workspaceId: workspaceId,
    index: index,
    label: label,
    closedAt: closedAt,
  );
}

final class ClosedPane extends ClosedItem {
  ClosedPane({
    required this.tabId,
    required this.cwd,
    required this.launch,
    required this.text,
    required this.label,
    this.closedAt,
  });

  /// The tab it was a pane of.
  final int tabId;
  final String? cwd;
  final SessionLaunch? launch;
  final String text;
  final String label;
  @override
  final DateTime? closedAt;

  @override
  late final int textBytes = _utf8Length(text);

  @override
  bool get isWorthKeeping => text.isNotEmpty || cwd != null || launch != null;

  @override
  ClosedItem withoutText() => ClosedPane(
    tabId: tabId,
    cwd: cwd,
    launch: launch,
    text: '',
    label: label,
    closedAt: closedAt,
  );
}

/// The newest [maxItems] closed items within [maxBytes] of text; the oldest
/// go first.
class ClosedItems {
  ClosedItems({this.maxItems = 10, this.maxBytes = 2 * 1024 * 1024});
  final int maxItems;
  final int maxBytes;
  final List<ClosedItem> _items = []; // oldest first

  int get length => _items.length;
  int get totalBytes => _items.fold(0, (n, i) => n + i.textBytes);
  ClosedItem? peek() => _items.isEmpty ? null : _items.last;
  ClosedItem? pop() => _items.isEmpty ? null : _items.removeLast();
  void clear() => _items.clear();

  void push(ClosedItem item) {
    if (!item.isWorthKeeping) return;
    _items.add(item.textBytes > maxBytes ? item.withoutText() : item);
    while (_items.length > maxItems) {
      _items.removeAt(0);
    }
    while (totalBytes > maxBytes && _items.length > 1) {
      _items.removeAt(0);
    }
  }

  @override
  String toString() => '…';
}

/// The ring and a counter that changes with it (what a menu watches).
final class ClosedItemsState {
  const ClosedItemsState(this.ring, this.version);
  final ClosedItems ring;
  final int version;
  int get length => ring.length;

  @override
  String toString() => '…';
}

final closedItemsProvider =
    NotifierProvider<ClosedItemsNotifier, ClosedItemsState>(
      ClosedItemsNotifier.new,
    );

class ClosedItemsNotifier extends Notifier<ClosedItemsState> {
  final _ring = ClosedItems();
  var _version = 0;

  @override
  ClosedItemsState build() {
    ref.onDispose(_ring.clear);
    return ClosedItemsState(_ring, _version);
  }

  void _changed() => state = ClosedItemsState(_ring, ++_version);

  void push(ClosedItem item) {
    _ring.push(item);
    _changed();
  }

  ClosedItem? pop() {
    final item = _ring.pop();
    if (item != null) _changed();
    return item;
  }

  void clear() {
    _ring.clear();
    _changed();
  }

  /// ⌘⇧T: brings back the newest closed tab or pane. Nothing to bring:
  /// a toast. A restore running: nothing happens (the item stays).
  /// A reopen that fails puts the item back.
  Future<void> reopenNewest() async {
    final tabs = ref.read(terminalTabsProvider.notifier);
    if (tabs.restoring) return;
    final item = pop();
    if (item == null) {
      tabs.showNotice(const ReopenNothingNotice());
      return;
    }
    final l10n = ref.read(appL10nProvider);
    final now = ref.read(clockProvider)();
    final time = formatRestoreTime(
      item.closedAt ?? now,
      now,
      localeName: l10n.localeName,
      yesterday: l10n.restoreTimeYesterday,
    );
    final divider = restoreDivider(l10n.terminalRestoredDivider(time));
    switch (item) {
      case ClosedTab():
        final outcome = await tabs.reopenClosed(
          item,
          dividerFor: (_) => divider,
        );
        if (!ref.mounted) return;
        final id = outcome.tabIdByKey[item.tab.key];
        if (id == null) {
          push(item);
          return;
        }
        final sidebar = ref.read(sidebarWorkspacesProvider.notifier);
        final ws = item.workspaceId;
        if (ws != null &&
            ref.read(sidebarWorkspacesProvider).workspace(ws) != null) {
          sidebar.moveTab(id, ws, item.index);
        }
        if (outcome.panesFailed == 0) {
          tabs.showNotice(ReopenedNotice(item.label));
        }
      case ClosedPane():
        final id = await tabs.reopenClosedPane(item, divider: divider);
        if (!ref.mounted) return;
        if (id == null) {
          push(item);
          return;
        }
        tabs.showNotice(ReopenedNotice(item.label));
    }
  }
}

/// A11 D14: listens to the tab list and keeps what closes. Read once at
/// startup. A tab that goes while one of its panes lives on elsewhere (a
/// move, a reconnect, the service laying the tree over its sessions) is
/// not a close; nothing is kept while a restore runs.
final closedItemsRecorderProvider = NotifierProvider<ClosedItemsRecorder, void>(
  ClosedItemsRecorder.new,
);

class ClosedItemsRecorder extends Notifier<void> {
  /// Where each tab sat in the sidebar when it last changed: a close
  /// removes the tab from the sidebar too, maybe before this hears of it.
  final _placeOf = <int, (String, int)>{};

  /// Sessions a reconnect replaced (A8 D22): their pane lives on.
  final _replaced = <int>{};

  @override
  void build() {
    final tabs = ref.read(terminalTabsProvider.notifier);
    final replacements = tabs.paneReplacements.listen((r) {
      _replaced.add(r.from);
      if (_replaced.length > 256) _replaced.remove(_replaced.first);
    });
    ref.onDispose(() => unawaited(replacements.cancel()));
    _remember(ref.read(sidebarWorkspacesProvider));
    ref.listen<SidebarState>(sidebarWorkspacesProvider, (_, s) => _remember(s));
    ref.listen<TerminalTabsState>(terminalTabsProvider, _onTabs);
  }

  void _remember(SidebarState s) {
    for (final MapEntry(key: ws, value: ids) in s.members.entries) {
      for (var i = 0; i < ids.length; i++) {
        _placeOf[ids[i]] = (ws, i);
      }
    }
  }

  void _onTabs(TerminalTabsState? prev, TerminalTabsState next) {
    if (prev == null) return;
    if (ref.read(terminalTabsProvider.notifier).restoring) return;
    try {
      final alive = {for (final t in next.tabs) ...t.panes.keys};
      final nextById = {for (final t in next.tabs) t.id: t};
      final now = ref.read(clockProvider)();
      for (final t in prev.tabs) {
        final still = nextById[t.id];
        if (still == null) {
          final lives = t.panes.keys.any(
            (id) => alive.contains(id) || _replaced.contains(id),
          );
          if (!lives) _captureTab(t, now);
          _placeOf.remove(t.id);
          continue;
        }
        for (final MapEntry(key: id, value: pane) in t.panes.entries) {
          if (still.panes.containsKey(id) ||
              alive.contains(id) ||
              _replaced.contains(id)) {
            continue;
          }
          _push(
            ClosedPane(
              tabId: t.id,
              cwd: pane.remote == null ? pane.cwd : null,
              launch: pane.remote?.launch.forReconnect(pane.cwd),
              text: encodeScrollback(pane.terminal),
              label: pane.automaticLabel,
              closedAt: now,
            ),
          );
        }
      }
    } on Object catch (e) {
      // Only the kind of error: the rest could be what the terminal showed.
      debugPrint('closed items: capture failed (${e.runtimeType})');
    }
  }

  void _captureTab(TerminalTab t, DateTime now) {
    final keys = <int, String>{};
    String keyOf(int id) => keys.putIfAbsent(id, newPaneKey);
    final layout = savePaneTree(t.layout, t, keyOf, includeExited: true);
    if (layout == null) return;
    final leaves = savedLeaves(layout);
    final inLayout = {for (final p in leaves) p.key};
    String? live(int? id) {
      if (id == null) return null;
      final key = keys[id];
      return key != null && inLayout.contains(key) ? key : null;
    }

    final text = <String, String>{};
    for (final MapEntry(key: id, value: pane) in t.panes.entries) {
      final key = keys[id];
      if (key == null || !inLayout.contains(key)) continue;
      final saved = encodeScrollback(pane.terminal);
      if (saved.isNotEmpty) text[key] = saved;
    }
    final place = _placeOf[t.id];
    _push(
      ClosedTab(
        tab: SavedTab(
          key: keyOf(t.id),
          name: t.customTitle,
          focused: live(t.focusedPaneId) ?? leaves.first.key,
          zoomed: live(t.zoomedPaneId),
          layout: layout,
          pinned: t.meta.pinned,
          description: t.meta.description,
          status: t.meta.status,
        ),
        textByKey: text,
        workspaceId: place?.$1,
        index: place?.$2 ?? 0,
        label: t.label,
        closedAt: now,
      ),
    );
  }

  void _push(ClosedItem item) =>
      ref.read(closedItemsProvider.notifier).push(item);
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shellx_agent/shellx_agent.dart';

import '../../l10n/app_localizations.dart';
import '../ui/window_focus.dart';
import '../ui/window_router.dart';
import 'local_sessions_provider.dart';
import 'sidebar_workspaces.dart';
import 'terminal_tabs.dart';

enum AttentionKind { message, command, bell }

/// A tab's unread notifications since it was last read (A4 D8, D9).
@immutable
final class TabUnread {
  const TabUnread({
    required this.count,
    required this.text,
    required this.kind,
    required this.at,
  });
  final int count;

  /// The last one's text (the sidebar line).
  final String text;
  final AttentionKind kind;
  final DateTime at;
}

/// One panel entry (A4 D11). Text lives only in memory (N9).
@immutable
final class AttentionEntry {
  const AttentionEntry({
    required this.seq,
    required this.tabId,
    required this.tabLabel,
    required this.kind,
    required this.text,
    required this.at,
    this.read = false,
    this.repeat = 1,
    this.closed = false,
  });
  final int seq;
  final int tabId;

  /// The tab's label when it arrived (shown once the tab is gone).
  final String tabLabel;
  final AttentionKind kind;
  final String text;
  final DateTime at;
  final bool read;

  /// Merged consecutive bells ("Chuông ×N").
  final int repeat;

  /// The tab is gone: shown as "Tab đã đóng", not jumpable.
  final bool closed;

  AttentionEntry copyWith({
    bool? read,
    int? repeat,
    DateTime? at,
    bool? closed,
  }) => AttentionEntry(
    seq: seq,
    tabId: tabId,
    tabLabel: tabLabel,
    kind: kind,
    text: text,
    at: at ?? this.at,
    read: read ?? this.read,
    repeat: repeat ?? this.repeat,
    closed: closed ?? this.closed,
  );
}

@immutable
final class AttentionState {
  const AttentionState({this.unread = const {}, this.history = const []});

  final Map<int, TabUnread> unread;

  /// Newest first, at most [TabAttention.historyLimit].
  final List<AttentionEntry> history;

  int get totalUnread => unread.values.fold(0, (sum, u) => sum + u.count);
  bool hasUnread(int tabId) => unread.containsKey(tabId);
}

/// A notice the user has not seen (not D7): system notification, taskbar
/// flash, screen-reader announcement.
@immutable
final class AttentionArrival {
  const AttentionArrival({
    required this.tabId,
    required this.kind,
    required this.text,
    required this.at,
  });
  final int tabId;
  final AttentionKind kind;
  final String text;
  final DateTime at;
}

/// UI-A4 §2.1, D8.
String unreadBadgeLabel(int count) => count > 99 ? '99+' : '$count';

/// C0, DEL, C1 and the Unicode line/paragraph separators: anything that
/// would break the one line (D9).
final _controls = RegExp(r'\s*[\x00-\x1f\x7f-\x9f\u2028\u2029]+\s*');

String _oneLine(String? text) => (text ?? '').replaceAll(_controls, ' ').trim();

/// A4 D9: the line a notice shows, on one line.
String noticeText(SessionNotice n, AppLocalizations l10n) {
  switch (n.kind) {
    case SessionNoticeKind.message:
      final title = _oneLine(n.title);
      final body = _oneLine(n.body);
      if (title.isEmpty) return body;
      return body.isEmpty ? title : '$title: $body';
    case SessionNoticeKind.command:
      final command = n.command;
      if (command == null) return '';
      return _oneLine(NotificationText(l10n.localeName).commandBody(command));
    case SessionNoticeKind.bell:
      return l10n.attentionBell;
  }
}

AttentionKind _kindOf(SessionNoticeKind kind) => switch (kind) {
  SessionNoticeKind.message => AttentionKind.message,
  SessionNoticeKind.command => AttentionKind.command,
  SessionNoticeKind.bell => AttentionKind.bell,
};

final tabAttentionProvider = NotifierProvider<TabAttention, AttentionState>(
  TabAttention.new,
);

/// Which tabs want the user (A4 N2–N5, D4, D7–D13, D26). UI state of this
/// window only; the agent just reports notices.
class TabAttention extends Notifier<AttentionState> {
  static const int historyLimit = 50;
  static const Duration dwell = Duration(seconds: 1);

  final _arrivals = StreamController<AttentionArrival>.broadcast(sync: true);
  final _reads = StreamController<int>.broadcast(sync: true);
  Timer? _dwell;
  int? _dwellFor;
  int _seq = 0;

  /// Notices the user has not seen. Consumers subscribe from a
  /// `ref.listen` of [tabAttentionProvider]'s notifier, not a cached
  /// stream: a rebuild of this provider closes it.
  Stream<AttentionArrival> get arrivals => _arrivals.stream;

  /// Tab ids that were marked read (their system notification is removed).
  /// Same lifetime rule as [arrivals].
  Stream<int> get reads => _reads.stream;

  @override
  AttentionState build() {
    final local = ref.watch(localSessionsProvider);
    final sub = local.notices.listen(_onNotice);
    ref.listen<TerminalTabsState>(terminalTabsProvider, (_, tabs) {
      _dropGone(tabs);
      _armDwell();
    });
    // The sources, not the derived windowActiveProvider (see its doc).
    ref.listen<bool>(windowFocusProvider, (_, _) => _armDwell());
    ref.listen<bool>(
      windowRouterProvider.select((w) => w.visible),
      (_, _) => _armDwell(),
    );
    ref.onDispose(() {
      unawaited(sub.cancel());
      _dwell?.cancel();
      unawaited(_arrivals.close());
      unawaited(_reads.close());
    });
    return const AttentionState();
  }

  void markRead(int tabId) => _markRead({tabId});

  /// One state update for all tabs.
  void markAllRead() => _markRead(state.unread.keys.toSet());

  void _markRead(Set<int> tabIds) {
    final had = [
      for (final id in state.unread.keys)
        if (tabIds.contains(id)) id,
    ];
    final stale = state.history.any((e) => !e.read && tabIds.contains(e.tabId));
    if (_dwellFor != null && tabIds.contains(_dwellFor)) _cancelDwell();
    if (had.isEmpty && !stale) return;
    state = AttentionState(
      unread: Map.of(state.unread)..removeWhere((id, _) => tabIds.contains(id)),
      history: [
        for (final e in state.history)
          !e.read && tabIds.contains(e.tabId) ? e.copyWith(read: true) : e,
      ],
    );
    had.forEach(_reads.add);
  }

  /// D13: the next tab with unread after the selected one, in sidebar
  /// order (collapsed workspaces included), wrapping.
  int? nextUnread() {
    if (state.unread.isEmpty) return null;
    final order = ref.read(sidebarWorkspacesProvider).orderedTabIds;
    if (order.isEmpty) return null;
    final start = order.indexOf(
      ref.read(terminalTabsProvider).selectedId ?? -1,
    );
    for (var step = 1; step <= order.length; step++) {
      final id = order[(start + step) % order.length];
      if (state.hasUnread(id)) return id;
    }
    return null;
  }

  /// D16 / panel Enter / next unread: select, expand its workspace, read
  /// at once (the user asked), keyboard to the terminal. False when the
  /// tab is gone.
  bool jumpTo(int tabId) {
    if (!ref.read(terminalTabsProvider).tabs.any((t) => t.id == tabId)) {
      return false;
    }
    ref.read(sidebarWorkspacesProvider.notifier).reveal(tabId);
    ref.read(terminalTabsProvider.notifier).select(tabId);
    markRead(tabId);
    ref.read(terminalFocusRequestProvider.notifier).request();
    return true;
  }

  // ---- internals --------------------------------------------------------

  bool get _active => readWindowActive(ref);

  void _onNotice(SessionNotice notice) {
    if (!ref.mounted) return;
    final tabs = ref.read(terminalTabsProvider);
    TerminalTab? tab;
    for (final t in tabs.tabs) {
      if (t.id == notice.sessionId) tab = t;
    }
    if (tab == null) return; // not (or no longer) a tab of this window
    final seen = tabs.selectedId == tab.id && _active;
    if (seen && notice.kind == SessionNoticeKind.bell) return; // D7
    final kind = _kindOf(notice.kind);
    final text = noticeText(notice, ref.read(appL10nProvider));
    final history = _withEntry(tab, kind, text, notice.at, read: seen);
    if (seen) {
      state = AttentionState(unread: state.unread, history: history);
      return;
    }
    final before = state.unread[tab.id];
    state = AttentionState(
      unread: {
        ...state.unread,
        tab.id: TabUnread(
          count: (before?.count ?? 0) + 1,
          text: text,
          kind: kind,
          at: notice.at,
        ),
      },
      history: history,
    );
    _arrivals.add(
      AttentionArrival(tabId: tab.id, kind: kind, text: text, at: notice.at),
    );
    _armDwell();
  }

  List<AttentionEntry> _withEntry(
    TerminalTab tab,
    AttentionKind kind,
    String text,
    DateTime at, {
    required bool read,
  }) {
    final history = state.history;
    final first = history.firstOrNull;
    if (kind == AttentionKind.bell &&
        first != null &&
        first.kind == AttentionKind.bell &&
        first.tabId == tab.id &&
        first.read == read) {
      return [
        first.copyWith(repeat: first.repeat + 1, at: at),
        ...history.skip(1),
      ];
    }
    return [
      AttentionEntry(
        seq: _seq++,
        tabId: tab.id,
        tabLabel: tab.label,
        kind: kind,
        text: text,
        at: at,
        read: read,
      ),
      ...history.take(historyLimit - 1),
    ];
  }

  /// D26: tabs that went away lose their unread; history keeps them,
  /// closed and read (nothing is left to read there).
  void _dropGone(TerminalTabsState tabs) {
    final ids = {for (final t in tabs.tabs) t.id};
    final gone = state.unread.keys.where((id) => !ids.contains(id)).toList();
    final closing = state.history.any(
      (e) => !e.closed && !ids.contains(e.tabId),
    );
    if (gone.isEmpty && !closing) return;
    state = AttentionState(
      unread: Map.of(state.unread)..removeWhere((id, _) => !ids.contains(id)),
      history: [
        for (final e in state.history)
          !e.closed && !ids.contains(e.tabId)
              ? e.copyWith(closed: true, read: true)
              : e,
      ],
    );
    for (final id in gone) {
      _reads.add(id);
    }
  }

  /// D10: one timer for the selected tab while it has unread and the
  /// window is active; unchanged conditions keep the running timer.
  void _armDwell() {
    if (!ref.mounted) return;
    final id = ref.read(terminalTabsProvider).selectedId;
    final wanted = id != null && state.hasUnread(id) && _active;
    if (!wanted) {
      _cancelDwell();
      return;
    }
    if (_dwellFor == id && (_dwell?.isActive ?? false)) return;
    _cancelDwell();
    _dwellFor = id;
    _dwell = Timer(dwell, () {
      _dwellFor = null;
      if (!ref.mounted) return;
      if (ref.read(terminalTabsProvider).selectedId == id && _active) {
        markRead(id);
      }
    });
  }

  void _cancelDwell() {
    _dwell?.cancel();
    _dwell = null;
    _dwellFor = null;
  }
}
